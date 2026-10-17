--[[
	DealershipMarkerController  (client)
	------------------------------------
	The pin that hangs over YOUR dealership once you have driven away from it.
	Your own headshot in the kit's socket, the distance under it, a tail pointing at the roof.
	2026-10-12: A matching BACK TO BASE card above the bottom-left cash HUD shares this plot lookup and lobby loop;
	its press uses PlotService's existing RequestGoHome validation and safe seat exit.
	2026-10-13: On touch that card is a one-line pill docked over the Play button instead, because the
	bottom-left is the thumbstick there (`PlotConfig.Marker.Home.Touch`, `_fitHome`).

	It is the other half of the question the dealership sign answers. Six plots, all built from the
	same reference layout, spread over about 1,200 studs of plaza: the sign tells a VISITOR whose
	lot they are standing on, and from two streets away it tells nobody anything, because at that
	range every lot is the same building and there are six of them. So the sign answers "whose is
	this?" and this answers "where is mine?". `PlotConfig.Marker` carries the design; what follows
	is the four things that shape the code.

	=== 1. THE POSITION IS CACHED, BECAUSE THE PLOT STREAMS OUT ================================

	`StreamingEnabled` is on. The lot you are trying to find your way back to is, at exactly the
	moment you want it, usually NOT in this client's DataModel. So nothing here may hold on to an
	instance inside the plot:

	  * the anchor is an `Attachment` of our own on `workspace.Terrain`, which is one object that
	    can never stream out, and the billboard adorns to that;
	  * the plot model is used only to MEASURE, and the measurement is kept.

	A marker adorned to a part of the plot would switch itself off at range. That is a marker that
	works only while you can already see the building it is pointing at.

	AND THE MEASUREMENT IS MONOTONIC, which is not a micro-optimisation but the answer to the one
	way this can be wrong. A model's tag fires before its descendants have replicated, so a
	`GetBoundingBox` taken the moment a plot streams in can be measuring half a plot. A half plot
	is never TALLER than the whole one, so keeping the largest top ever seen converges on the roof
	and can never sink the pin into it. It also picks up a second floor being bought (24 studs of
	`FloorSpacing`) for free, on the next pass, with nothing here having to know that happened.

	=== 2. THE DUPLICATE PLOT IS REAL AND IT CLAIMS INDEX 1 ====================================

	`workspace.Plot7` is a full copy of Plot1 left behind by map work, 478 studs off the island. It
	carries the `Plot` tag and it claims `PlotIndex` 1. `PlotService` refuses it by requiring a plot
	to be a descendant of `Map.Plots` as well as tagged, and this has to make the same check for a
	sharper reason than the server does: a wrong sign is a cosmetic bug, and a waypoint pointing at
	a plot in the sea is the feature doing the exact opposite of its job for whoever holds plot 1.

	=== 3. IT STANDS DOWN FOR A RACE, BY DISCONNECTING =========================================

	`RaceStart` and `RaceEnd`, the bracket the play button and the cash pill use, for the reason
	`RaceEntryController` sets out: the lobby's furniture has no business over the road. Here it is
	the render loop itself that goes rather than a flag the loop reads, because the loop is doing
	nothing else. A per-frame connection that outlives what it draws is the feature being paid for
	at the moments it is not running.

	=== 4. THE FADE IS THE DISTANCE, NOT A TWEEN ===============================================

	The pin is gone below `HideStuds`, full strength above `ShowStuds`, and linear between, read
	straight off where the player is standing. There is no timer and no remembered state.

	Two thresholds with hysteresis would need this file to remember which side of them it was last
	on, and what that state buys is a marker that POPS. A ramp cannot flicker at the boundary
	because there is no boundary to sit on, and because the player crosses it by driving, the fade
	is already paced by how fast they are going: pull away hard and it arrives quickly, roll away
	and it arrives slowly. Neither of those is something a fixed tween duration can do.

	THE TWO ENDS OF THE RAMP ARE NOT CONSTANTS. A player with a car in their hands gets a nearer
	pair (`PlotConfig.Marker.Carry`), so the pin holds on until the bay glow has taken over instead
	of letting go fifty studs short of it. It is still a ramp and it still cannot flicker; only its
	ends moved, and they moved between frames, which a ramp with no remembered side is free to do.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Observers = require(ReplicatedStorage.Packages.Observers)
local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local CarryConfig = require(ReplicatedStorage.shared.Configs.CarryConfig)
local GamepadConfig = require(ReplicatedStorage.shared.Configs.GamepadConfig)
local PlotConfig = require(ReplicatedStorage.shared.Configs.PlotConfig)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local ArcadeKit = require(ReplicatedStorage.shared.Modules.ArcadeKit)

--- Ubuntu BOLD. `Enum.Font.Ubuntu` is Ubuntu REGULAR, which is why this is a `Font` object.
local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

--[[ Seconds between re-measurements of the plot, while the plot is actually in the DataModel.

	It only ever runs while the player is near enough for the lot to be streamed in, which is also
	the only time the measurement can be trusted and the only time the pin is not being drawn. ]]
local MEASURE_INTERVAL = 2

--- Below this the billboard is switched off outright rather than drawn at a transparency nobody
--- can see. `Enabled` costs nothing to write and stops the engine laying out an invisible panel.
local ALPHA_EPSILON = 0.01

--- Scale changes smaller than this are not written. See `_step`.
local SCALE_EPSILON = 0.002

-- Leave the bottom fifth for the income and cash HUD, matching the requested spot under the icons.
local HOME_POSITION = UDim2.new(0, 18, 0.78, 0)
local HOME_HIDDEN_POSITION = HOME_POSITION + UDim2.fromOffset(-28, 0)
--- The card's pixels wide per pixel high on keyboard and gamepad. The touch pill's is in `PlotConfig`.
local HOME_ASPECT = 2.45

local DealershipMarkerController = Shard.new("DealershipMarkerController")

-- === The pin ================================================================

--[[ Build it once and park it invisible.

	IN `PlayerGui` WITH AN `Adornee`, never parented into Workspace. It is this client's own chrome
	and it belongs on this client's own screen, and it is also the construction that photographs in
	a Studio capture, which the Workspace-parented one does not.

	`AlwaysOnTop` IS ON, and it is the one place this file disagrees with every other billboard in
	the game. The speech bubble and the sell sign are both about a thing you are looking at, so
	drawing them through a wall would be drawing a label inside a building. This is a waypoint: the
	whole point is that it is visible when the lot is behind a block of flats, which is when you
	need it. The cost is that it will be missing from every in-engine screenshot. ]]
function DealershipMarkerController._build(self)
	local cfg = PlotConfig.Marker
	local box = UIAssets.MarkerBox

	--[[ The anchor. An `Attachment` and not a part, on `Terrain` and not in a folder: Terrain is
		always there and never streams, an Attachment has no physics and cannot turn up in anybody's
		raycast or `GetPartBoundsInBox`, and both of those are stronger than remembering to switch
		`CanQuery` and `CanTouch` off on a part. Its `WorldPosition` is written after parenting,
		because an attachment written before it has a parent reads that value as a LOCAL offset. ]]
	local anchor = Instance.new("Attachment")
	anchor.Name = "DealershipMarkerAnchor"
	anchor.Parent = workspace.Terrain

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DealershipMarker"
	billboard.Adornee = anchor
	billboard.Size = UDim2.fromOffset(cfg.Size.X, cfg.Size.Y)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = math.huge
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	billboard.Enabled = false
	--[[ Half the pin's height upwards, which stands the TAIL TIP on the anchor instead of the pin's
		middle. In screen space, so the pin sits the same way on its point at every distance and at
		every size the shrink below puts it at. ]]
	billboard.SizeOffset = Vector2.new(0, 0.5)

	local pin = Instance.new("ImageLabel")
	pin.Name = "Pin"
	pin.Size = UDim2.fromScale(1, 1)
	pin.BackgroundTransparency = 1
	pin.Image = UIAssets.url(UIAssets.Marker.Pin)
	--- `Stretch`, never `Slice`: `Marker.Size` is the texture's own aspect, so the stretch is the
	--- identity. A `Slice` here would inflate the corners as the pin shrinks with distance.
	pin.ScaleType = Enum.ScaleType.Stretch
	pin.ImageTransparency = 1
	pin.BorderSizePixel = 0
	pin.Parent = billboard

	--[[ The face. `rbxthumb` resolves client-side with no web call and without yielding, so this is
		filled in the moment the plot is known rather than a frame or two later.

		THE CIRCLE IS A `UICorner` AND THE RING IS THE TEXTURE'S. The socket is drawn into the pin
		in the sign's own `#0066FF`, one ring width wider than this label, so what shows around a
		round headshot is the same accent the dealership sign rings its own headshot with. Nothing
		here has to paint a stroke, and there is no second colour to keep in step with the art.

		AND IT IS A BUTTON (2026-10-12): press your own face to go home (`PlotConfig.Marker.Home`).
		It takes input because the billboard is in PlayerGui with an Adornee and `Active` on; one
		parented under Workspace draws the same and never fires. It is only pressable while drawn,
		which is only in the lobby and only from far enough away that going home is worth a press. ]]
	local home = PlotConfig.Marker.Home
	local pressable = home ~= nil and home.Enabled
	local headshot = Instance.new(if pressable then "ImageButton" else "ImageLabel") :: ImageLabel
	headshot.Name = "Headshot"
	headshot.AnchorPoint = Vector2.new(0.5, 0.5)
	headshot.Position = UDim2.fromScale(box.HeadshotCentre.X, box.HeadshotCentre.Y)
	headshot.Size = UDim2.fromScale(box.HeadshotSize.X, box.HeadshotSize.Y)
	headshot.BackgroundTransparency = 1
	headshot.Image = ""
	headshot.ScaleType = Enum.ScaleType.Fit
	headshot.ImageTransparency = 1
	headshot.BorderSizePixel = 0
	headshot.Parent = pin

	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = headshot

	if pressable then
		billboard.Active = true
		local button = headshot :: any
		button.AutoButtonColor = false
		self._trove:Add(button.Activated:Connect(function()
			if billboard.Enabled then
				self:getRemoteEvent("RequestGoHome"):Fire()
			end
		end))
	end

	local caption = Instance.new("TextLabel")
	caption.Name = "Distance"
	caption.AnchorPoint = Vector2.new(0.5, 0.5)
	caption.Position = UDim2.fromScale(box.CaptionCentre.X, box.CaptionCentre.Y)
	caption.Size = UDim2.fromScale(box.CaptionSize.X, box.CaptionSize.Y)
	caption.BackgroundTransparency = 1
	caption.FontFace = FONT
	caption.Text = ""
	caption.TextColor3 = cfg.CaptionColor
	caption.TextScaled = true
	caption.TextTransparency = 1
	caption.Parent = pin

	--- Matched to the text's own transparency on every write rather than left solid, so the outline
	--- can never read as more present than the glyphs it is outlining.
	local stroke = Instance.new("UIStroke")
	stroke.Color = cfg.CaptionStrokeColor
	stroke.Thickness = cfg.CaptionStrokeThickness
	stroke.Transparency = 1
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = caption

	self._anchor = anchor
	self._billboard = billboard
	self._pin = pin
	self._headshot = headshot
	self._caption = caption
	self._stroke = stroke

	billboard.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self._trove:Add(billboard)
	self._trove:Add(anchor)
end

-- === Which plot is mine =====================================================

-- 2026-10-12: A fixed screen target is easier to press than the distant pin. It shares the pin's
-- plot lookup and lobby loop; RequestGoHome still resolves ownership and race state on the server.
function DealershipMarkerController._buildHomeButton(self)
	if not PlotConfig.Marker.Home.Enabled then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "BackToBase"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Anchor, Size, Position and the two constraints are the layout's, written by `_fitHome`.
	local holder = Instance.new("CanvasGroup")
	holder.Name = "Home"
	holder.GroupTransparency = 1
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = gui
	local bounds = Instance.new("UISizeConstraint")
	bounds.Parent = holder
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.Parent = holder
	local press = Instance.new("TextButton")
	press.Name = "ReturnHome"
	press.Text = ""
	press.BackgroundTransparency = 1
	press.Size = UDim2.fromScale(1, 1)
	press.ZIndex = 10
	press.Parent = holder
	local scale = Instance.new("UIScale")
	scale.Parent = holder
	--- The selection pair is the pad's hover; see the tag below.
	for event, amount in { MouseEnter = 1.04, MouseLeave = 1, SelectionGained = 1.04, SelectionLost = 1 } do
		self._trove:Add(press[event]:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.12), { Scale = amount }):Play()
		end))
	end
	self._trove:Add(press.Activated:Connect(function()
		local now = os.clock()
		if not self._homeShown or not self._conn or now < (self._homeReadyAt or 0) then
			return
		end
		self._homeReadyAt = now + PlotConfig.Marker.Home.CooldownSeconds
		self:getRemoteEvent("RequestGoHome"):Fire()
	end))
	self._homeButton = holder
	self._homeBounds = bounds
	self._homeRatio = aspect
	self:_fitHome()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self._trove:Add(gui)
	--- In the HUD's DPad chain (`GamepadConfig.HudMemberTag`), so a controller can press it: it sits
	--- in a screen of its own, which the chain did not reach until 2026-10-15. After the parent.
	CollectionService:AddTag(press, GamepadConfig.HudMemberTag)
	local function refit()
		self:_fitHome()
	end
	self._trove:Add(UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(refit))
	self._trove:Add(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit))
end

--- Is the button wearing the compact pill docked over Play? On EVERY device since 2026-10-13 (the
--- owner: "move it on top of the Play button ... more compact"); it was touch-only before. Off = the
--- bottom-left card everywhere, as before this layout existed.
function DealershipMarkerController._touchHome(_self): boolean
	local touch = PlotConfig.Marker.Home.Touch
	return touch ~= nil and touch.Enabled
end

--[[ The kit card, its headshot and its caption, for one layout: the two-line card, or the one-line
	pill. Rebuilt whole when the device changes its mind, since the card's checker is fitted to one
	shape. The pill's pixel geometry is `_fitHome`'s, because it depends on the screen. ]]
function DealershipMarkerController._dressHome(self, touch: boolean)
	if self._homeFace then
		self._homeFace:Destroy()
		self._homeFace = nil
	end
	local layout = PlotConfig.Marker.Home.Touch
	local face = ArcadeKit.card(self._homeButton, {
		face = ArcadeKit.Faces.Cyan,
		aspect = if touch then layout.Aspect else HOME_ASPECT,
		sunray = false,
	})
	-- CanvasGroup clips at its bounds; inset the face so its outlined rim survives the fade.
	face.Position = UDim2.fromScale(0.03, 0.06)
	face.Size = UDim2.fromScale(0.94, 0.88)
	--- The pill is the caption alone (2026-10-13: "remove the player headshot"); the card keeps its face.
	local portrait = nil
	if not touch then
		portrait = Instance.new("ImageLabel")
		portrait.BackgroundTransparency = 1
		portrait.Position = UDim2.fromScale(0.06, 0.17)
		portrait.Size = UDim2.fromScale(0.27, 0.66)
		portrait.Image = string.format(PlotConfig.SignHeadshotFormat, Players.LocalPlayer.UserId)
		portrait.ZIndex = 4
		portrait.Parent = face
		ArcadeKit.corner(portrait, 1)
	end
	local title = ArcadeKit.text(face, 0.35, 0.18, 0.6, 0.64, ArcadeKit.White, true)
	title.Text = if touch then layout.Title else "BACK TO\nBASE"
	self._homeFace = face
	self._homePortrait = portrait
	self._homeTitle = title
end

--[[ Shape the button for the device in hand, and again whenever the input or the window changes.

	Keyboard and gamepad: the card, bottom-left over the cash HUD, scale-sized between a floor and
	a ceiling. Touch: a pill sized off the screen's height (`PlotConfig.Marker.Home.Touch`), in
	pixels, so the headshot can be an exact circle and the caption one line beside it. Its place is
	measured off Play every frame it is up (`_placeHome`), not repeated from Play's own numbers. ]]
function DealershipMarkerController._fitHome(self)
	local holder = self._homeButton
	if not holder then
		return
	end
	local touch = self:_touchHome()
	if touch ~= self._homeTouch then
		self._homeTouch = touch
		self:_dressHome(touch)
	end
	local face, portrait, title = self._homeFace, self._homePortrait, self._homeTitle
	-- The pill carries no portrait (`_dressHome`); only the card needs one.
	if not (face and title and (touch or portrait)) then
		return
	end
	if touch then
		local layout = PlotConfig.Marker.Home.Touch
		local viewport = workspace.CurrentCamera.ViewportSize
		local height = math.floor(math.clamp(viewport.Y * layout.HeightShare, layout.MinHeight, layout.MaxHeight))
		local width = math.floor(height * layout.Aspect)
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Size = UDim2.fromOffset(width, height)
		self._homeBounds.MinSize = Vector2.zero
		self._homeBounds.MaxSize = Vector2.new(math.huge, math.huge)
		self._homeRatio.AspectRatio = width / height
		-- Three pixels clear of the clip on every side, the card's inset in pixels for a short shape.
		face.Position = UDim2.fromOffset(3, 3)
		face.Size = UDim2.new(1, -6, 1, -6)
		-- The caption alone, centred across the whole pill (no headshot since 2026-10-13).
		title.Position = UDim2.new(0, 8, 0.2, 0)
		title.Size = UDim2.new(1, -16, 0.6, 0)
		title.TextXAlignment = Enum.TextXAlignment.Center
	else
		holder.AnchorPoint = Vector2.new(0, 0.5)
		holder.Size = UDim2.fromScale(0.15, 0.1)
		self._homeBounds.MinSize = Vector2.new(150, 62)
		self._homeBounds.MaxSize = Vector2.new(210, 86)
		self._homeRatio.AspectRatio = HOME_ASPECT
	end
	self:_placeHome()
end

--[[ Where the button rests and where it slides in from, for the layout in hand. On touch that is
	centred over Play's top edge, read off Play's own box in screen space, so the pill follows Play
	when the carry hotbar lifts it. Nil when there is no Play to dock to. ]]
function DealershipMarkerController._homeTargets(self): (UDim2?, UDim2?)
	if not self._homeTouch then
		return HOME_POSITION, HOME_HIDDEN_POSITION
	end
	local entry = self._raceEntry or Shard.get("RaceEntryController")
	self._raceEntry = entry
	local play = entry and entry:playButton()
	local holder = self._homeButton
	local gui = holder and holder.Parent
	if not (play and gui and gui:IsA("GuiBase2d")) then
		return nil, nil
	end
	local layout = PlotConfig.Marker.Home.Touch
	local origin = gui.AbsolutePosition
	local x = play.AbsolutePosition.X + play.AbsoluteSize.X / 2 - origin.X
	local y = play.AbsolutePosition.Y - origin.Y - layout.Gap - holder.Size.Y.Offset / 2
	return UDim2.fromOffset(math.round(x), math.round(y)), UDim2.fromOffset(math.round(x), math.round(y + layout.Slide))
end

--- Put a resting button on its target. A sliding one is left to its tween, which reads the target
--- again on its way in.
function DealershipMarkerController._placeHome(self)
	local button = self._homeButton
	if not button or self._homeTween then
		return
	end
	local rest, away = self:_homeTargets()
	local target = if self._homeShown then rest else away
	if target and button.Position ~= target then
		button.Position = target
	end
end

-- Reverse the current tween when the player crosses back over the boundary, rather than snapping
-- to either endpoint. Race starts hide immediately so lobby UI cannot linger over the road.
function DealershipMarkerController._setHomeShown(self, shown: boolean, instant: boolean?)
	local button = self._homeButton
	if not button or (self._homeShown == shown and not instant) then return end
	self._homeShown = shown
	if self._homeTween then
		local previous = self._homeTween
		self._homeTween = nil
		previous:Cancel()
	end
	local rest, away = self:_homeTargets()
	local position = (if shown then rest else away) or button.Position
	local transparency = if shown then 0 else 1
	if instant then
		button.Position, button.GroupTransparency, button.Visible = position, transparency, shown
		return
	end
	if shown then button.Visible = true end
	local tween = TweenService:Create(button,
		TweenInfo.new(if shown then 0.28 else 0.18, Enum.EasingStyle.Quad, if shown then Enum.EasingDirection.Out else Enum.EasingDirection.In),
		{ Position = position, GroupTransparency = transparency })
	self._homeTween = tween
	tween.Completed:Once(function()
		if self._homeTween ~= tween then return end
		self._homeTween = nil
		if not self._homeShown then button.Visible = false end
	end)
	tween:Play()
end

function DealershipMarkerController._updateHomeButton(self, root: BasePart?)
	local button = self._homeButton
	if not button then
		return
	end
	local cf, size = self._footprintCF, self._footprintSize
	local character = root and root.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (self._index and cf and size and root and humanoid and humanoid.Health > 0) then
		self:_setHomeShown(false)
		return
	end
	-- The roof's height must not make somebody standing inside their showroom count as away.
	-- Three studs of slack avoids flickering while walking along the lot's edge.
	local offset = cf:PointToObjectSpace(root.Position)
	local away = math.abs(offset.X) > size.X / 2 + 3 or math.abs(offset.Z) > size.Z / 2 + 3
	if away and self._homeTouch then
		-- Docked over Play, so it goes where Play goes (a page open, a race), and it keeps out of the
		-- way of the tutorial's arrow, which points at Play from the very spot the pill rests on.
		local entry = self._raceEntry or Shard.get("RaceEntryController")
		self._raceEntry = entry
		local playUp = false
		if entry then
			local _, up = entry:playButton()
			playUp = up
		end
		away = playUp and not TutorialConfig.isUnfinished(Players.LocalPlayer:GetAttribute(TutorialConfig.StepAttribute))
	end
	self:_setHomeShown(away)
	if self._homeTouch then
		self:_placeHome()
	end
end

--[[ Is this tagged model one of the six real plots?

	Path-scoped exactly as `PlotService._discover` is, and for the sharper version of its reason:
	see note 2 in the header. The tag alone finds `workspace.Plot7`, which claims index 1. ]]
local function isRealPlot(plot: Instance): boolean
	local folder = plot.Parent
	if not (folder and folder.Name == PlotConfig.PlotsFolderName) then
		return false
	end
	local map = folder.Parent
	return map ~= nil and map.Name == PlotConfig.MapName and map.Parent == workspace
end

--[[ Take the plot's height, keeping the tallest answer ever seen, and stand the pin over its pivot.

	See note 1 in the header for why the height is the maximum rather than the latest.

	THE TWO COORDINATES COME FROM DIFFERENT PLACES ON PURPOSE, and the second one is a bug that was
	measured rather than guessed at. The bounding box is the only thing that can answer "how tall is
	this plot today", but its CENTRE wanders as decor streams in and out: two successive passes on
	the same lot put it 2 studs apart. Two studs is nothing at the range this is read from, and a
	pin that slides sideways while the player is looking at it is not nothing. The pivot is the
	plot's authored ground centre (`MapLayout` §3.3), it replicates with the Model rather than being
	derived from its parts, and it therefore cannot move at all. ]]
function DealershipMarkerController._readFootprint(self): boolean
	if not self._index then
		return false
	end
	local player = Players.LocalPlayer
	local cf = player:GetAttribute(PlotConfig.PlayerFootprintAttribute)
	local size = player:GetAttribute(PlotConfig.PlayerFootprintSizeAttribute)
	if typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" or size.X <= 0 or size.Z <= 0 then
		return false
	end
	self._footprintCF, self._footprintSize = cf, size
	return true
end

function DealershipMarkerController._measure(self, plot: Model)
	local ok, top = pcall(function()
		local cf, extents = plot:GetBoundingBox()
		-- Like the roof height, the footprint must not shrink as parts stream out around the player.
		local previous, size = self._footprintCF, self._footprintSize
		if previous and size then
			local offset = previous:PointToObjectSpace(cf.Position)
			local lowX = math.min(-size.X / 2, offset.X - extents.X / 2)
			local highX = math.max(size.X / 2, offset.X + extents.X / 2)
			local lowZ = math.min(-size.Z / 2, offset.Z - extents.Z / 2)
			local highZ = math.max(size.Z / 2, offset.Z + extents.Z / 2)
			self._footprintCF = previous * CFrame.new((lowX + highX) / 2, 0, (lowZ + highZ) / 2)
			self._footprintSize = Vector3.new(highX - lowX, 0, highZ - lowZ)
		else
			self._footprintCF, self._footprintSize = cf, extents
		end
		return cf.Position.Y + extents.Y / 2
	end)
	if not (ok and type(top) == "number") then
		return
	end
	self:_readFootprint() -- Keep partial streaming and moving NPCs from expanding the home boundary.

	self._top = math.max(self._top or -math.huge, top + PlotConfig.Marker.Clear)
	self._anchor.WorldPosition = Vector3.new(self:_centreOf(plot).X, self._top, self:_centreOf(plot).Z)
	self._measuredAt = os.clock()
end

--[[ Where over the plot the pin stands: its pivot, unless the pivot is not ON the plot.

	=== A PIVOT OFF THE PLOT — 2026-10-11 (the new map) ===
	The header's argument for the pivot (it is the authored ground centre and cannot wander) holds
	for a plot authored that way. A plot copied or regrouped during map work keeps whatever pivot it
	came with, and on the new map the owner's pin stood over the wrong building. So the pivot is
	checked against the plot's own footprint first: inside it (with `PIVOT_SLACK` studs to spare),
	it is used as before; outside, the bounding box's centre is taken ONCE and kept for this plot,
	which is the stability the pivot was chosen for, at the cost of a stud or two of placement. ]]
local PIVOT_SLACK = 6

function DealershipMarkerController._centreOf(self, plot: Model): Vector3
	if self._centreFor == plot and self._centre then
		return self._centre
	end
	local pivot = plot:GetPivot().Position
	local ok, cf, extents = pcall(plot.GetBoundingBox, plot)
	if not ok then
		return pivot
	end
	local offset = cf:PointToObjectSpace(pivot)
	local inside = math.abs(offset.X) <= extents.X / 2 + PIVOT_SLACK and math.abs(offset.Z) <= extents.Z / 2 + PIVOT_SLACK
	if inside then
		return pivot
	end
	self._centreFor, self._centre = plot, cf.Position
	return cf.Position
end

--[[ One tagged plot has arrived. Take it if it is mine, and hand back the undo.

	The plot index on the PLAYER and the one on the MODEL are the same attribute name held by two
	different instances, which is `PlotConfig`'s doing and worth reading twice. ]]
function DealershipMarkerController._bind(self, plot: Model)
	--[[ The nil check is not redundant with the comparison below it. A plot in `Map.Plots` with no
		index attribute is a malformed map rather than an impossibility, and while this client holds
		no plot the two nils would compare equal and it would bind the broken one. ]]
	if not (self._index and isRealPlot(plot)) then
		return nil
	end
	--[[ OWNERSHIP FIRST, THE INDEX ONLY AS A FALLBACK (2026-10-11, the new map: "the billboard shows
		the wrong plot for me"). `PlotService` stamps `OwnerUserIdAttribute` on the very model it gave
		this player, BEFORE it writes the index onto the player, so the owner is the server's answer
		itself and cannot be ambiguous. Matching the index alone was: a map with two plots carrying
		one `PlotIndex` (a copied plot keeps its source's number) has the server skip the second and
		this bind whichever came first. A plot owned by SOMEBODY ELSE is never taken, whatever its
		index says; an unowned one is taken on the index only while nothing better has been found. ]]
	local owner = plot:GetAttribute(PlotConfig.OwnerUserIdAttribute)
	local mine = owner == Players.LocalPlayer.UserId
	if not mine then
		if owner ~= nil or self._plotOwned or plot:GetAttribute(PlotConfig.IndexAttribute) ~= self._index then
			return nil
		end
	end
	self._plotOwned = mine
	if self._centreFor ~= plot then
		self._centreFor, self._centre = nil, nil
	end
	--- A different plot than the one measured so far (the index fallback replaced by the owned one):
	--- its roof is not that one's, and `_top` only ever rises, so it starts again.
	if self._plot ~= plot then
		self._top = nil
		self._footprintCF, self._footprintSize = nil, nil
	end

	self._plot = plot
	self:_measure(plot)

	return function()
		if self._plot == plot then
			self._plot = nil
		end
	end
end

--[[ The plot this client holds, from the attribute `PlotService` stamps on the Player.

	Re-read rather than remembered, because a claim can land after this controller starts and a
	release can land at any time. Clearing `_top` on a change is what stops a marker inheriting the
	height of a lot the player no longer owns. ]]
function DealershipMarkerController._onPlotChanged(self)
	local raw = Players.LocalPlayer:GetAttribute(PlotConfig.PlayerPlotAttribute)
	local index = if type(raw) == "number" then raw else nil
	if index == self._index then
		return
	end

	self._index = index
	self._footprintCF, self._footprintSize = nil, nil
	self._plot = nil
	self._plotOwned = false
	self._centreFor, self._centre = nil, nil
	self._top = nil
	self._measuredAt = 0
	self:_readFootprint()

	--- The face never changes for a session, but it is written here rather than at boot so that a
	--- player holding no plot is not carrying a loaded headshot on an invisible pin.
	self._headshot.Image = if index
		then string.format(PlotConfig.SignHeadshotFormat, Players.LocalPlayer.UserId)
		else ""

	--[[ The observer already ran for every plot that is streamed in, and it ran against the OLD
		index, so nothing is going to call `_bind` again until one streams back in. Sweep the six
		by hand instead. Off `Map.Plots` rather than off the tag, because that folder is the answer
		to `isRealPlot` and a missing map is a lobby with no plots in it rather than an error. ]]
	local map = index and workspace:FindFirstChild(PlotConfig.MapName)
	local plots = map and map:FindFirstChild(PlotConfig.PlotsFolderName)
	if plots then
		--- The plot stamped with this player's UserId wins (`_bind`); an index match is the fallback.
		local byIndex = nil
		for _, model in plots:GetChildren() do
			if not model:IsA("Model") then
				continue
			end
			if model:GetAttribute(PlotConfig.OwnerUserIdAttribute) == Players.LocalPlayer.UserId then
				self:_bind(model)
				byIndex = nil
				break
			elseif not byIndex and model:GetAttribute(PlotConfig.IndexAttribute) == index then
				byIndex = model
			end
		end
		if byIndex then
			self:_bind(byIndex)
		end
	end
end

-- === The loop ===============================================================

function DealershipMarkerController._step(self, dt: number)
	local cfg = PlotConfig.Marker
	local billboard = self._billboard

	--- Cheap first, in the order things go missing: no plot, no measurement, no character.
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	self:_updateHomeButton(if root and root:IsA("BasePart") then root else nil)
	if not (self._index and self._top and root and root:IsA("BasePart")) then
		billboard.Enabled = false
		return
	end

	--- Re-measure while the lot is streamed in, which is the same window in which the pin is not
	--- being drawn. See note 1.
	local plot = self._plot
	if plot and plot:IsDescendantOf(game) and os.clock() - self._measuredAt >= MEASURE_INTERVAL then
		self:_measure(plot)
	end

	--[[ Measured from the PLAYER and not from the camera, because this is the distance they have to
		drive. The camera can be twenty studs behind them or, during a bail, somewhere else
		entirely, and a waypoint that quoted the camera's gap would be quoting a number the player
		cannot act on. ]]
	local target = self._anchor.WorldPosition
	local away = (root.Position - target).Magnitude

	--[[ The band, and it is not the same band while a car is in the player's hands.

		`PlotConfig.Marker.Carry` has the argument. The short version is that the shipped band lets go
		fifty studs before the bay glow picks up, and somebody carrying a car across that ring is the
		one person who cannot afford the hole.

		READ PER FRAME OFF THE ATTRIBUTE rather than subscribed to. It is one attribute read inside a
		loop that is already measuring a distance and writing five properties, and a subscription would
		buy a cached boolean in exchange for the two connections that keep it true. ]]
	local hide, show = cfg.HideStuds, cfg.ShowStuds
	local carry = cfg.Carry
	if carry and carry.Enabled and CarryConfig.Enabled then
		local held = Players.LocalPlayer:GetAttribute(CarryConfig.Attribute)
		if type(held) == "string" and held ~= "" then
			hide, show = carry.HideStuds, carry.ShowStuds
		end
	end

	local span = math.max(show - hide, 1)
	local alpha = math.clamp((away - hide) / span, 0, 1)

	billboard.Enabled = alpha > ALPHA_EPSILON
	if not billboard.Enabled then
		return
	end

	--[[ The shrink. Full size out to `RefStuds` and smaller beyond it, floored at `MinScale`.

		Gated on a small epsilon because this is three property writes and the ratio moves by
		fractions of a percent while the player is stationary. Fractional pixels rather than rounded
		ones, so the box keeps the texture's exact aspect at every size and the headshot, which is a
		circle, never draws as an ellipse. ]]
	local want = math.clamp(cfg.RefStuds / math.max(away, 1), cfg.MinScale, 1)
	if math.abs(want - self._scale) >= SCALE_EPSILON then
		self._scale = want
		billboard.Size = UDim2.fromOffset(cfg.Size.X * want, cfg.Size.Y * want)
		--- Quoted at the full marker, so it has to come down with it or the outline thickens into
		--- the glyphs as the pin pulls away.
		self._stroke.Thickness = cfg.CaptionStrokeThickness * want
	end

	--[[ The float, as a fraction of the pin's own height rather than in studs.

		Studs are what the getaway marker's bob is in, and that one is over a truck at most 460
		studs out. This pin lives at up to about 1,200, where half a stud of world-space movement is
		less than a pixel and the bob simply stops existing. A fraction of the marker reads the same
		at every range, which is the same reason the marker is sized in offset. ]]
	self._bob += dt
	local bob = math.sin(self._bob * math.pi * 2 / cfg.BobPeriod) * cfg.BobFraction
	billboard.SizeOffset = Vector2.new(0, 0.5 + bob)

	self._pin.ImageTransparency = 1 - (1 - cfg.PinTransparency) * alpha
	self._headshot.ImageTransparency = 1 - alpha
	self._caption.Text = string.format(cfg.DistanceFormat, math.floor(away))
	self._caption.TextTransparency = 1 - (1 - cfg.CaptionTransparency) * alpha
	self._stroke.Transparency = self._caption.TextTransparency
end

--- The lobby is on. See note 3: the loop IS the switch.
function DealershipMarkerController._resume(self)
	if self._conn or not self._billboard then
		return
	end
	self._scale = 0 -- forces the size write on the first frame back
	self._conn = RunService.RenderStepped:Connect(function(dt)
		self:_step(dt)
	end)
end

function DealershipMarkerController._suspend(self)
	self:_setHomeShown(false, true)
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	if self._billboard then
		self._billboard.Enabled = false
	end
end

-- === Lifecycle ==============================================================

DealershipMarkerController:withRemoteEvents({
	-- client -> server: the headshot was pressed, take me home. See `PlotService._onGoHome`.
	"RequestGoHome",
	{
		RaceStart = function()
			DealershipMarkerController:_suspend()
		end,
		RaceEnd = function()
			DealershipMarkerController:_resume()
		end,
	},
})

DealershipMarkerController:withLifecycle({
	init = function(self)
		self._trove = Trove.new()
		--- The plot this client holds, and how high its roof is. `_top` doubles as "has this ever
		--- been measured", which is why it is nil rather than zero.
		self._index = nil :: number?
		self._plot = nil :: Model?
		self._top = nil :: number?
		self._measuredAt = 0
		self._scale = 0
		self._bob = 0
		self._conn = nil :: RBXScriptConnection?
		self._homeButton = nil :: CanvasGroup?
		self._homeShown = false
		--- Which layout the button is dressed for; nil until `_fitHome` first runs. See `_touchHome`.
		self._homeTouch = nil :: boolean?
		self._raceEntry = nil :: any
		self._footprintCF = nil :: CFrame?
		self._footprintSize = nil :: Vector3?
	end,

	--[[ In `start` and not `init`, the rule every module here follows: `init` may not yield and
		this reaches into Workspace and PlayerGui. `observeTag` then makes the timing a non-question,
		firing for the plots already here and for every one that streams in later. ]]
	start = function(self)
		if not (PlotConfig.Enabled and PlotConfig.Marker.Enabled) then
			return
		end

		self:_build()

		local player = Players.LocalPlayer
		self._trove:Add(player:GetAttributeChangedSignal(PlotConfig.PlayerPlotAttribute):Connect(function()
			self:_onPlotChanged()
		end))
		for _, attribute in { PlotConfig.PlayerFootprintAttribute, PlotConfig.PlayerFootprintSizeAttribute } do
			self._trove:Add(player:GetAttributeChangedSignal(attribute):Connect(function()
				self:_readFootprint()
			end))
		end
		self:_onPlotChanged()

		self._trove:Add(Observers.observeTag(PlotConfig.PlotTag, function(plot: Instance)
			if not plot:IsA("Model") then
				return nil
			end
			return self:_bind(plot)
		end, { workspace }))

		self:_resume()
		-- ArcadeKit waits for the UI shelf; the marker's race subscriptions must already be active.
		task.spawn(function()
			self:_buildHomeButton()
		end)
	end,
})

DealershipMarkerController:withCleanup(function()
	DealershipMarkerController:_suspend()
	if DealershipMarkerController._trove then
		DealershipMarkerController._trove:Destroy()
	end
end)

return DealershipMarkerController
