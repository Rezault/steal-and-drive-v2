--[[
	GetawayHudController  (client)
	------------------------------
	WHAT THE PLAYER IS TOLD ABOUT THE GETAWAY TRUCK. Two pieces that hand off to one another:

	    (steal) --> [ card counting down on the right ] --spawn--> [ marker over the truck ] --> gone
	                        "how long do I survive"                    "that one, there"

	Until this existed the answer was NOTHING, unless the player happened to be on the tutorial's
	BANK beat. That is the gap it closes, and it is a real one: `GetawayConfig` is a carefully tuned
	beat — armed by a steal, arriving somewhere in a ten-to-sixteen second band, three hundred studs
	out in the middle lane — and none of it is legible from the driving seat. The truck is white and
	it arrives among white traffic. A player who has not been told is a player whose runs all end in
	a wreck, having never found the other ending the whole game is built around (GDD §3.5).

	IT OWNS NO STATE OF ITS OWN ABOUT THE TRUCK. Everything on screen is read from
	`GetawayController` every frame through two accessors — `getCountdown` and `getTruck` — and
	nothing here is driven by an event. That is deliberate and it is what makes the display
	unbreakable: a truck that spawns, is missed, despawns and is re-armed moves this display through
	four states without a single subscription to get out of sync, and a wreck or a revive needs no
	handler here at all because both are already visible in what those two accessors answer.

	THE TWO ARE NEVER BOTH UP. The card leaves as the marker arrives, because they say the same
	thing at different times and a screen carrying both is a screen saying it twice.

	...AND NEITHER IS EVER UP ALONGSIDE THE TUTORIAL'S CHIP. `TutorialController` already floats a
	pill-and-arrow over the truck on its BANK beat, with a distance under it — the same idea as this
	marker, aimed at the same object. A first-timer would otherwise get two glyphs stacked over one
	truck, bobbing out of phase. `getChipTarget` is the test, and the tutorial wins: its chip is
	louder on purpose, because the player it is for needs it to be.

	TIMED ON THE WALL CLOCK, NOT ON `TimeScale`. The countdown it draws runs on real seconds because
	the thing it is counting down to does (`GetawayController._loop` applies the scale BELOW its
	spawn arm, deliberately, so a held world cannot stretch the gap between trucks), and a readout
	on a different clock from the event would drift away from it in front of the player. The fades
	and the pop are real-time for the same reason: they are chrome, not world motion.

	EVERY NUMBER IS IN `GetawayConfig.Hud`. What is in this file is layout and sequencing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local GetawayConfig = require(ReplicatedStorage.shared.Configs.GetawayConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)

local GetawayHudController = Shard.new("GetawayHudController"):withDependencies({
	"GetawayController",
})

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

--- `TextScaled` would sooner break a caption onto a second line than pick a smaller font, so every
--- one-line label in this project is written through a non-breaking space. See RaceUIController.
local NBSP = utf8.char(0xA0)
local function oneLine(text: string): string
	return (string.gsub(text, "%s+", NBSP))
end

--[[ UNDER the near-miss toast's 900 and well under the respawn screen (999) and the return fade
	(1000). A countdown is the least urgent thing that can be on this screen: anything that lands on
	top of it — a wreck, a revive question, the results — is a thing the player has to answer, and
	this must never be drawn over one of those. It is above the driving HUD's 895 only because it
	does not overlap it at all. ]]
local DISPLAY_ORDER = 890

-- === The card's internal layout ==============================================
-- Fractions of the card's own box. The glyph sits left and the two rows of information stack to the
-- right of it, which is the shape every chip in this kit uses: picture, then what it says.
local ICON_X, ICON_Y = 0.025, 0.44
local ICON_BOX = Vector2.new(0.24, 0.5)
local ROW_X = 0.30 -- everything right of the glyph starts here
local ROW_RIGHT = 0.968 -- ...and ends here
local TITLE_Y, TITLE_HEIGHT = 0.3, 0.34
local SECONDS_WIDTH = 0.2
local BAR_Y = 0.735

-- === Build ===================================================================

function GetawayHudController._build(self)
	local cfg = GetawayConfig.Hud
	local card = cfg.Card

	local gui = Instance.new("ScreenGui")
	gui.Name = "GetawayHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = DISPLAY_ORDER
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	--[[ NOT `Active`, and nothing under it is either — the tutorial card's rule, for the tutorial
		card's reason. This is a panel sitting over a live game with a car being steered underneath
		it, and on a touch device the right of the screen is where fingers are. A readout that ate a
		press would be a readout that occasionally cost somebody a steal. ]]
	local root = Instance.new("Frame")
	root.Name = "Card"
	--- Anchored to its own RIGHT edge, so `Margin` is the gap from the screen edge at any viewport
	--- rather than a gap that grows with the card.
	root.AnchorPoint = Vector2.new(1, 0.5)
	root.Position = UDim2.fromScale(1 - card.Margin, card.CentreY)
	root.Size = UDim2.fromScale(card.Size.X, card.Size.Y)
	root.BackgroundColor3 = card.PanelColor
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Parent = gui

	--[[ The arrival pop rides a UIScale rather than the frame's Size, which is the near-miss toast's
		note: the labels inside are `TextScaled`, so animating the box animates the font and the two
		rows re-flow in the middle of the pop. A UIScale scales the rendered result and re-flows
		nothing. ]]
	local scale = Instance.new("UIScale")
	scale.Parent = root

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(card.CornerRadius, 0)
	corner.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.Color = card.StrokeColor
	stroke.Thickness = card.StrokeThickness
	stroke.Transparency = 1
	stroke.Parent = root

	--[[ The glyph, and the one element here whose aspect is NOT the card's to decide. The card is
		sized in scale on both axes, so its shape moves with the viewport; the truck must not skew
		with it. A real box plus an aspect constraint, never a zero-width box — `FitWithinMaxSize`
		collapses that to nothing rather than resolving it from the aspect. ]]
	local icon = Instance.new("ImageLabel")
	icon.Name = "Truck"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.fromScale(ICON_X, ICON_Y)
	icon.Size = UDim2.fromScale(ICON_BOX.X, ICON_BOX.Y)
	icon.BackgroundTransparency = 1
	icon.Image = UIAssets.url(UIAssets.Getaway.Truck)
	--- Stretch, not Slice: the box holds the art's aspect (above), and nothing about this glyph is
	--- nine-sliced. See the standing note in `UIAssets.Slice`.
	icon.ScaleType = Enum.ScaleType.Stretch
	icon.ImageTransparency = 1
	icon.Parent = root

	local iconAspect = Instance.new("UIAspectRatioConstraint")
	iconAspect.AspectRatio = UIAssets.GetawaySize.Truck.X / UIAssets.GetawaySize.Truck.Y
	iconAspect.Parent = icon

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0, 0.5)
	title.Position = UDim2.fromScale(ROW_X, TITLE_Y)
	title.Size = UDim2.fromScale(ROW_RIGHT - ROW_X - SECONDS_WIDTH, TITLE_HEIGHT)
	title.BackgroundTransparency = 1
	title.FontFace = FONT
	title.Text = oneLine(card.Title)
	title.TextColor3 = card.TitleColor
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextScaled = true
	title.TextTransparency = 1
	title.Parent = root

	--- Right-aligned against the bar's own right edge, so the number and the bar end on the same
	--- vertical — the card reads as two rows rather than as four loose pieces.
	local seconds = Instance.new("TextLabel")
	seconds.Name = "Seconds"
	seconds.AnchorPoint = Vector2.new(1, 0.5)
	seconds.Position = UDim2.fromScale(ROW_RIGHT, TITLE_Y)
	seconds.Size = UDim2.fromScale(SECONDS_WIDTH, TITLE_HEIGHT)
	seconds.BackgroundTransparency = 1
	seconds.FontFace = FONT
	seconds.Text = ""
	seconds.TextColor3 = card.SecondsColor
	seconds.TextXAlignment = Enum.TextXAlignment.Right
	seconds.TextScaled = true
	seconds.TextTransparency = 1
	seconds.Parent = root

	--[[ The bar: a pill and its trough, no track art. `GetawayConfig.Hud.Card` argues for that at
		length — it is the construction the nitro bar and the car's HP bar already use, so the three
		bars on this screen are one thing built one way. ]]
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.fromScale(ROW_X, BAR_Y)
	track.Size = UDim2.fromScale(ROW_RIGHT - ROW_X, card.BarHeight)
	--- The trough IS the fill, dimmed, so the two can never disagree about hue however the fill
	--- colour is retuned. Same trick and same number as `NitroConfig.Hud.TrackDim`.
	track.BackgroundColor3 = Color3.new(
		card.FillColor.R * card.TrackDim,
		card.FillColor.G * card.TrackDim,
		card.FillColor.B * card.TrackDim
	)
	track.BackgroundTransparency = 1
	track.BorderSizePixel = 0
	track.Parent = root

	local trackCorner = Instance.new("UICorner")
	--- A full pill at any height: `UICorner`'s scale is taken against the frame's SHORTER side, so
	--- 0.5 is a semicircular cap however wide the bar gets.
	trackCorner.CornerRadius = UDim.new(0.5, 0)
	trackCorner.Parent = track

	--[[ THE ONE PLACE IN THIS FILE THAT IS NOT ANCHORED AT ITS CENTRE, and the project's standing
		exception: a fill bar is edge-driven, so it grows from its left edge and the anchor has to
		be there or the bar would expand in both directions from the middle. ]]
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.fromScale(0, 0.5)
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = card.FillColor
	fill.BackgroundTransparency = 1
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill

	self._gui = gui
	self._card = root
	self._cardScale = scale
	self._cardStroke = stroke
	self._icon = icon
	self._title = title
	self._seconds = seconds
	self._track = track
	self._fill = fill

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

--[[ The marker, built ONCE for the session and re-adorned rather than rebuilt per truck.

	That is a direct lesson from the tutorial's chip, whose header records stacking three billboards
	on one mat inside a single session: anything that builds a `ResetOnSpawn = false` BillboardGui
	per appearance has to destroy the last one on every path that leads to a new one, and there are
	more of those paths than there look to be. One instance, re-pointed, has no such paths. ]]
function GetawayHudController._buildMarker(self)
	local marker = GetawayConfig.Hud.Marker

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GetawayMarker"
	billboard.Size = UDim2.fromOffset(marker.Size.X, marker.Size.Y)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = math.huge
	billboard.ResetOnSpawn = false
	billboard.Enabled = false

	local icon = Instance.new("ImageLabel")
	icon.Name = "Truck"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.38)
	icon.Size = UDim2.fromScale(1, 0.62)
	icon.BackgroundTransparency = 1
	icon.Image = UIAssets.url(UIAssets.Getaway.Truck)
	icon.ScaleType = Enum.ScaleType.Stretch
	icon.ImageTransparency = 1
	icon.Parent = billboard

	--- Holds the glyph's aspect inside whatever box the distance shrink leaves it, so the truck
	--- never squashes as the marker scales.
	local iconAspect = Instance.new("UIAspectRatioConstraint")
	iconAspect.AspectRatio = UIAssets.GetawaySize.Truck.X / UIAssets.GetawaySize.Truck.Y
	iconAspect.Parent = icon

	local distance = Instance.new("TextLabel")
	distance.Name = "Distance"
	distance.AnchorPoint = Vector2.new(0.5, 0.5)
	distance.Position = UDim2.fromScale(0.5, 0.86)
	distance.Size = UDim2.fromScale(1, 0.24)
	distance.BackgroundTransparency = 1
	distance.FontFace = FONT
	distance.Text = ""
	distance.TextColor3 = marker.DistanceColor
	distance.TextScaled = true
	distance.TextTransparency = 1
	distance.Parent = billboard

	--- Matched to the text's own transparency on every write rather than left solid, so the outline
	--- can never read as more present than the glyph it is outlining. The chip does the same.
	local stroke = Instance.new("UIStroke")
	stroke.Color = marker.StrokeColor
	stroke.Thickness = marker.StrokeThickness
	stroke.Transparency = 1
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = distance

	self._marker = billboard
	self._markerIcon = icon
	self._markerDistance = distance
	self._markerStroke = stroke

	billboard.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- === The card ================================================================

--[[ One step of the countdown card. `remaining`/`total` are `GetawayController.getCountdown`'s, and
	`arrived` says whether the wait ended because a truck actually turned up — which is the whole
	difference between the card's two exits. A wait that ends with a truck has earned its little
	arrival beat; one that ends because the run was wrecked has not, and simply leaves. ]]
function GetawayHudController._stepCard(self, dt: number, remaining: number?, total: number?, arrived: boolean)
	local card = GetawayConfig.Hud.Card

	if remaining then
		--- Coming back from "leave" is a RETRY — a truck was missed and the next one is armed — so
		--- the bar restarts rather than resuming where the last one got to.
		if self._phase ~= "show" then
			self._phase = "show"
			self._frac = 0
		end
		self._alpha = math.min(1, self._alpha + dt / card.FadeIn)

		--[[ THE BAR IS HELD MONOTONIC, and this is not decoration. `getCountdown`'s own note says
			the remainder can exceed the total: when every candidate spot is standing inside the
			obstacle course the controller pushes the spawn out by a second and tries again, so the
			raw fraction would step BACKWARDS on screen. A progress bar that goes back is a bar that
			tells the player something is wrong when nothing is. It stalls instead, which is the
			honest reading of "this is taking longer than advertised". ]]
		local want = if total and total > 0 then math.clamp(1 - remaining / total, 0, 1) else 0
		self._frac = math.max(self._frac, want)

		--- Rounded UP and floored at one, so the last second reads "1s" for a whole second rather
		--- than the card sitting on a "0s" it cannot leave until the spawn actually lands.
		self._seconds.Text = string.format(card.SecondsFormat, math.max(1, math.ceil(remaining)))
	elseif self._phase == "show" then
		--- The wait is over. Which exit depends on why.
		self._phase = if arrived then "arrive" else "leave"
		self._phaseT = 0
	end

	if self._phase == "arrive" then
		self._phaseT += dt
		--- The bar completes rather than being left wherever the last frame put it: this is the one
		--- moment it is allowed to be exactly true.
		self._frac = 1
		self._seconds.Text = ""
		--- Out and back, so the card springs and settles instead of ending up bigger than it started.
		local half = card.PopTime
		local t = self._phaseT
		local pop = if t < half then t / half elseif t < half * 2 then 2 - t / half else 0
		self._cardScale.Scale = 1 + (card.PopTo - 1) * pop
		if self._phaseT >= half * 2 + card.HoldFull then
			self._phase = "leave"
			self._phaseT = 0
		end
	elseif self._phase == "leave" then
		self._cardScale.Scale = 1
		self._alpha = math.max(0, self._alpha - dt / card.FadeOut)
		if self._alpha <= 0 then
			self._phase = "off"
		end
	elseif self._phase == "off" then
		self._cardScale.Scale = 1
	end

	local a = self._alpha
	self._card.Visible = a > 0
	if a <= 0 then
		return
	end
	--- One alpha drives every layer of the card, so it arrives and leaves as one object rather than
	--- as a panel with its contents catching up.
	self._card.BackgroundTransparency = 1 - (1 - card.PanelTransparency) * a
	self._cardStroke.Transparency = 1 - a
	self._icon.ImageTransparency = 1 - a
	self._title.TextTransparency = 1 - a
	self._seconds.TextTransparency = 1 - a
	self._track.BackgroundTransparency = 1 - a
	self._fill.BackgroundTransparency = 1 - a
	self._fill.Size = UDim2.fromScale(self._frac, 1)
end

-- === The marker ==============================================================

--- Studs above the truck's PrimaryPart to float the marker, measured off the MODEL's bounding box
--- rather than off the part: `getTruck` hands back a box somewhere inside the bodywork, and
--- clearing that clears nothing. Same measurement, same reason, as the tutorial chip's `_chipHeight`.
function GetawayHudController._markerHeight(self, part: BasePart): number
	local clear = GetawayConfig.Hud.Marker.Clear
	local model = part:FindFirstAncestorWhichIsA("Model")
	if model then
		local box, size = model:GetBoundingBox()
		return (box.Position.Y - part.Position.Y) + size.Y * 0.5 + clear
	end
	return part.Size.Y * 0.5 + clear
end

--[[ One step of the marker. Everything here is a fact about where the CAMERA is, so it is all
	answered together, once a frame.

	THE SIZE, which shrinks with range for the reason `Marker.RefStuds` gives. Gated on the number
	having actually moved, because a `Size` write re-lays-out the whole billboard and the marker
	spends most of its life against one of the two clamps.

	THE HEIGHT, which is a CEILING and not a position. Four studs above the roof of a 22-stud truck
	is 26 studs up: a gentle angle at three hundred studs and straight overhead at twenty. Left
	alone the marker climbs off the top of the screen over the last seconds of the chase — exactly
	when the player is lining up on the ramp. So it sits at the roof while that is in shot and
	slides down the back of the truck as the player closes.

	THE FADE, which is the marker getting out of the way of the thing it is pointing at. See
	`Marker.FadeNear`. ]]
function GetawayHudController._stepMarker(self, dt: number, truck: BasePart?)
	local cfg = GetawayConfig.Hud.Marker
	local billboard = self._marker

	if not truck then
		self._markerAlpha = 0
		billboard.Enabled = false
		billboard.Adornee = nil
		return
	end

	if billboard.Adornee ~= truck then
		--- A new truck is a new appearance: fade in again rather than inheriting the last one's
		--- alpha, which would pop a fully-lit marker onto a truck 400 studs away.
		billboard.Adornee = truck
		self._markerAlpha = 0
		self._markerScale = 0 -- forces the size write below
	end

	self._markerAlpha = math.min(1, self._markerAlpha + dt / cfg.FadeIn)

	local camera = workspace.CurrentCamera
	local height = self:_markerHeight(truck)
	local near = 1

	if camera then
		local eye = camera.CFrame.Position
		local to = truck.Position - eye
		local away = to.Magnitude

		local want = math.clamp(cfg.RefStuds / math.max(away, 1), cfg.MinScale, 1)
		if math.abs(want - self._markerScale) >= 0.002 then
			self._markerScale = want
			--- Fractional pixels rather than rounded ones, so the box's aspect is exact at every
			--- size and the glyph inside it never skews by a rounding pixel.
			billboard.Size = UDim2.fromOffset(cfg.Size.X * want, cfg.Size.Y * want)
			--- Under the same gate and for the same reason: the outline is quoted at the full marker
			--- and has to shrink with the text or it thickens into it as the truck pulls away.
			self._markerStroke.Thickness = cfg.StrokeThickness * want
		end

		--- Off the FLAT distance, because the cone is about how far the eye has to look UP, and a
		--- straight-line distance would let the marker creep higher as the camera rose.
		local flat = Vector3.new(to.X, 0, to.Z).Magnitude
		local ceiling = (eye.Y + flat * cfg.Rise) - truck.Position.Y
		height = math.min(height, math.max(ceiling, cfg.Clear))

		--- The close-range fade. Measured from the camera like the size is, because both are about
		--- how big the truck looks rather than about how far the player has to drive.
		if cfg.FadeFar > cfg.FadeNear then
			near = math.clamp((away - cfg.FadeNear) / (cfg.FadeFar - cfg.FadeNear), 0, 1)
		end
	end

	local a = self._markerAlpha * near
	billboard.Enabled = a > 0.01
	if not billboard.Enabled then
		return
	end

	--- Real time, not `TimeScale`: this is chrome floating above the world, not motion in it, and a
	--- held world should not freeze it mid-bob.
	self._bob += dt
	local bob = math.sin(self._bob * math.pi * 2 / cfg.BobPeriod) * cfg.BobStuds
	billboard.StudsOffsetWorldSpace = Vector3.new(0, height + bob, 0)

	self._markerIcon.ImageTransparency = 1 - (1 - cfg.IconTransparency) * a

	--- Measured from the PLAYER, not from the camera, because this is the number they are driving —
	--- the same distance the tutorial chip prints, in the same words, so the two can never quote the
	--- same gap differently.
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		self._markerDistance.Text = string.format(cfg.DistanceFormat, math.floor((root.Position - truck.Position).Magnitude))
		self._markerDistance.TextTransparency = 1 - (1 - cfg.TextTransparency) * a
	else
		self._markerDistance.Text = ""
	end
	self._markerStroke.Transparency = self._markerDistance.TextTransparency
end

-- === The loop ================================================================

function GetawayHudController._loop(self, dt: number)
	local getaway = self._getaway
	if not getaway then
		return
	end

	local truck = getaway:getTruck()

	--[[ THE TUTORIAL WINS. Its chip is the same idea aimed at the same object, and its own note says
		why it is the louder of the two: the player it is drawn for will not recognise the truck at
		all. Two glyphs stacked over one truck, bobbing out of phase, is what this line prevents.

		Asked of the tutorial every frame rather than latched on a beat, because the chip comes and
		goes for reasons this controller has no view of — a page opening, a retry landing, the beat
		advancing mid-chase. A soft `Shard.get` rather than a declared dependency: a place without a
		TutorialController should cost this feature nothing. ]]
	local tutorial = self._tutorial
	local chipped = tutorial ~= nil and truck ~= nil and tutorial:getChipTarget() == truck
	--- A truck shut by a chase (`GetawayConfig.PoliceLock`) is not an exit, so nothing points at it.
	local locked = getaway:isPoliceLocked()

	local remaining, total = getaway:getCountdown()
	self:_stepCard(dt, remaining, total, truck ~= nil)
	self:_stepMarker(dt, if chipped or locked then nil else truck)
end

function GetawayHudController._start(self)
	--- `_gui` is the test for "was this ever built", which covers both the disabled switch and the
	--- boot that found no GetawayController. A race can start without either.
	if self._conn or not self._gui then
		return
	end
	self._phase = "off"
	self._alpha = 0
	self._frac = 0
	self._phaseT = 0
	self._markerAlpha = 0
	self._markerScale = 0
	self._gui.Enabled = true
	self._conn = RunService.RenderStepped:Connect(function(dt)
		self:_loop(dt)
	end)
end

--[[ Torn down on `RaceEnd` rather than left running, for the reason the tutorial's own loop states:
	a per-frame connection that outlives what it draws is the feature being paid for at the moments
	it is doing nothing. There is no truck outside a race and no countdown to draw. ]]
function GetawayHudController._stop(self)
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	self._phase = "off"
	self._alpha = 0
	self._frac = 0
	if self._gui then
		self._gui.Enabled = false
		self._card.Visible = false
		self._cardScale.Scale = 1
		self._fill.Size = UDim2.fromScale(0, 1)
	end
	if self._marker then
		self._marker.Enabled = false
		self._marker.Adornee = nil
	end
	self._markerAlpha = 0
end

GetawayHudController:withRemoteEvents({
	{
		RaceStart = function()
			GetawayHudController:_start()
		end,
		--[[ A wreck needs NO handler and deliberately has none. `getCountdown` already answers nil
			once the run is wrecked and `getTruck` stops being an exit, so the card fades itself out
			on the next frame through the ordinary path — and a revive re-arms the truck, which the
			same accessor reports without anything here having to remember it happened. This is the
			whole benefit of reading state rather than subscribing to it; see the header. ]]
		RaceEnd = function()
			GetawayHudController:_stop()
		end,
	},
})

GetawayHudController:withLifecycle({
	init = function(self)
		self._phase = "off" -- "off" | "show" | "arrive" | "leave"
		self._phaseT = 0
		self._alpha = 0 -- the card's one transparency driver
		self._frac = 0 -- ...and its bar, held monotonic; see `_stepCard`
		self._markerAlpha = 0
		self._markerScale = 0
		self._bob = 0
	end,

	start = function(self)
		if not GetawayConfig.Hud.Enabled then
			return
		end
		self._getaway = Shard.get("GetawayController")
		if not self._getaway then
			self.log:warn("GetawayController unavailable; the truck will arrive unannounced.")
			return
		end
		--- Soft, not a declared dependency — see `_loop`. A place with no tutorial simply never has
		--- a chip to stand down for.
		self._tutorial = Shard.get("TutorialController")

		self:_build()
		self:_buildMarker()
	end,
})

return GetawayHudController
