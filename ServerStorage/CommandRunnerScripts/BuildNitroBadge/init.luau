--[[
	BuildNitroBadge: Command Runner command

	Builds `StarterGui.DrivingHud.NitroBadge` — the round nitro readout that stands beside the
	speedo: a bottle in a dark disc, a ring sweeping around it, and a glow behind the pair while
	the bottle is alight.

	=== WHY THIS IS A COMMAND AND NOT `Instance.new` IN A CONTROLLER ==========================

	The same reason `BuildSpeedoV2` is one, and its header argues it at length: the whole driving
	HUD is authored in Studio so Dylan can nudge it in the Explorer, and a controller that creates
	its own instances takes that away. `DrivingHudController` finds this badge and drives it; it
	never makes it.

	Idempotent, like every builder here: `NitroBadge` is destroyed and made again on every run, so
	a hand edit to the badge is lost on the next one and the fix is to make the edit HERE or in
	`NitroConfig.Hud.Badge`. Nothing else under `DrivingHud` is touched, so `Cluster`, `Controls`,
	`SpeedoV2` and both old nitro bars survive it.

	=== THE ARC IS TWO HALVES CUT BY A TURNING GRADIENT ======================================

	Half a ring, twice, each pinned to the badge and never moved. What turns is a `UIGradient` on
	each one, carrying a hard step through its centre: a gradient cuts along a line through the
	middle of the element it sits on, so turning the gradient turns that line around the clock and
	the half of the art on the far side of it goes transparent.

	Because each texture only EXISTS in its own half of the circle, the cut and the art together
	make exactly one arc from twelve o'clock, with no third piece to keep in step:

	  Right  the first half of the tank, twelve round to six. Its cut turns with the tank up to the
	         halfway mark and is switched off past it, where the whole half is lit.
	  Left   the second half, six round to twelve. It is hidden below halfway, because a cut can
	         only ever keep a half-plane and below halfway the one it would keep reaches back over
	         twelve into art that has not been earned yet.

	So the controller's whole job is one number per half, and the two arcs meet at twelve and at six
	with no seam because they are the same texture either side of one line.

	=== ...AND EXPLICITLY NOT BY CLIPPING A ROTATED IMAGE ====================================

	The obvious build is a half-ring TURNED about the badge with the wrong half clipped away, and it
	was the first one written here. It does not survive contact with the engine. A `GuiObject` with a
	non-zero `Rotation` is not clipped by an ancestor's `ClipsDescendants` at all (the same trap
	`RaceUIController`'s sunburst hit), and a `CanvasGroup`, which is the documented answer to that,
	could not be shown to clip anything in an edit-mode probe: a full ring at twice the group's
	width, unrotated, still drew in full. The gradient needs no clipping from anybody, so it does not
	care either way, and it is cheaper besides: a CanvasGroup re-renders to a texture every time a
	child moves, and this writes one float on a plain ImageLabel.

	=== EVERY NUMBER COMES OUT OF `NitroConfig.Hud.Badge` ====================================

	Not out of this file, the same contract `BuildSpeedoV2` has with `SpeedoConfig`: the controller
	reads that table to drive the badge and this reads it to draw it, so there is one place to
	retune and no way for the two to disagree. The cost is that a config edit needs a re-run.

	It does NOT act on `Hud.Layout`. That flag is meant to be flipped and looked at, and
	`DrivingHudController._attachNitro` is what shows one readout and hides the others at runtime.
	Building this badge on a place still set to `Vertical` is harmless: it sits there hidden until
	the flag moves, and the command says so.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)
local NitroConfig = require(ReplicatedStorage.shared.Configs.NitroConfig)

local HUD_NAME = "DrivingHud"
local BADGE_NAME = "NitroBadge"

--- Ubuntu Bold: the kit's type, and it ships with Roblox so nothing is uploaded.
local KIT_FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

--- `TextScaled` needs a legal `TextSize` before it takes over. The value never renders.
local SEED_TEXT_SIZE = 8

--[[ The step that cuts a half of the ring, and it is a CONSTANT: the arc is drawn by turning the
	gradient, never by rebuilding this. Opaque up to the element's centre and clear past it, so the
	line it cuts along runs through the middle of the badge whichever way the gradient faces.

	`CUT_EDGE` is a hairline of ramp rather than an infinitely sharp step, for the reason the nitro
	bar's own cut gives: `NumberSequence` keypoints have to advance, and on a ring this thin the
	ramp is the only anti-aliasing the leading edge gets. ]]
local CUT_EDGE = 0.004
local CUT_STEP = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.5 + CUT_EDGE, 1),
	NumberSequenceKeypoint.new(1, 1),
})

--- The four corners, as the anchor that parks the badge INTO one, so a margin is a gap from the
--- screen edge at any viewport rather than a gap that grows with the badge. Lifted from
--- `BuildSpeedoV2` deliberately: the two have to park by the same rule or they drift apart.
local CORNERS: { [string]: Vector2 } = {
	BottomRight = Vector2.new(1, 1),
	BottomLeft = Vector2.new(0, 1),
	TopRight = Vector2.new(1, 0),
	TopLeft = Vector2.new(0, 0),
}

local function cornerPosition(corner: string, margin: Vector2): UDim2
	local anchor = CORNERS[corner] or CORNERS.BottomRight
	local x = if anchor.X == 0 then margin.X else 1 - margin.X
	local y = if anchor.Y == 0 then margin.Y else 1 - margin.Y
	return UDim2.fromScale(x, y)
end

local function dim(color: Color3, by: number): Color3
	return Color3.new(color.R * by, color.G * by, color.B * by)
end

--- Centred on its parent and filling it, which is what almost everything in this badge is.
local function fill(item: GuiObject, scale: number?): GuiObject
	local at = scale or 1
	item.AnchorPoint = Vector2.new(0.5, 0.5)
	item.Position = UDim2.fromScale(0.5, 0.5)
	item.Size = UDim2.fromScale(at, at)
	item.BackgroundTransparency = 1
	item.BorderSizePixel = 0
	return item
end

local function image(name: string, asset: string, parent: Instance, zindex: number): ImageLabel
	local item = Instance.new("ImageLabel")
	item.Name = name
	item.Image = asset
	item.ScaleType = Enum.ScaleType.Fit
	item.ZIndex = zindex
	fill(item)
	item.Parent = parent
	return item
end

--- The badge's own frame: square at any viewport, parked in its corner.
local function buildFrame(hud: Instance): Frame
	local badge = NitroConfig.Hud.Badge

	local frame = Instance.new("Frame")
	frame.Name = BADGE_NAME
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.AnchorPoint = CORNERS[badge.Corner] or CORNERS.BottomRight
	frame.Position = cornerPosition(badge.Corner, badge.Margin)
	--[[ A REAL BOX ON BOTH AXES, not `UDim2.new(0, 0, Height, 0)`. `FitWithinMaxSize` fits the
		element inside the box it is authored at, so a zero width collapses it to nothing at all
		rather than resolving to the aspect. Square then falls out of the constraint below, with
		the HEIGHT dominant so the badge is the same size on a phone and an ultrawide. ]]
	frame.Size = UDim2.fromScale(badge.Height, badge.Height)
	--- Over the pedals. In this corner something is always underneath it, and a readout that can
	--- be hidden by a control is not a readout.
	frame.ZIndex = 5
	frame.Parent = hud

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.AspectType = Enum.AspectType.FitWithinMaxSize
	aspect.Parent = frame

	return frame
end

--- The bloom behind everything, off by default: the controller lights it on the burn alone.
local function buildGlow(frame: Frame)
	local badge = NitroConfig.Hud.Badge
	local glow = image("Glow", badge.Art.Glow, frame, 1)
	glow.Size = UDim2.fromScale(badge.Glow.Scale, badge.Glow.Scale)
	glow.ImageTransparency = 1
	glow.ImageColor3 = NitroConfig.Hud.ReadyColor
end

--- The dark disc, and the rim that keeps it off a bright road.
local function buildPlate(frame: Frame)
	local badge = NitroConfig.Hud.Badge

	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.BackgroundColor3 = badge.Plate
	plate.BackgroundTransparency = badge.PlateTransparency
	plate.BorderSizePixel = 0
	plate.ZIndex = 2
	--- Inside the ring rather than under it: the ring's art runs to the edge of its own canvas, so
	--- a plate at full size would sit behind the arc and dull it.
	fill(plate, 0.86)
	plate.BackgroundTransparency = badge.PlateTransparency
	plate.Parent = frame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = plate

	local stroke = Instance.new("UIStroke")
	stroke.Color = badge.PlateStroke
	stroke.Thickness = badge.PlateStrokeThickness
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = plate
end

--[[ The ring: one dim track, and the two halves the arc is cut out of.

	ONE UPLOAD DRAWS BOTH HALVES. `NitroRingHalf.png` is the LEFT half of the ring, and the same
	image turned 180 is the right half, so there is no second file to keep in step with the first.
	That turn is authored here and never moves again: the only thing that moves at runtime is the
	gradient's rotation. ]]
local function buildRing(frame: Frame)
	local badge = NitroConfig.Hud.Badge

	local track = image("RingTrack", badge.Art.Ring, frame, 3)
	track.ImageColor3 = dim(NitroConfig.Hud.ReadyColor, badge.RingDim)

	local arc = Instance.new("Frame")
	arc.Name = "Arc"
	arc.ZIndex = 4
	fill(arc)
	arc.Parent = frame

	for _, side in { "Right", "Left" } do
		local half = image(side, badge.Art.RingHalf, arc, 4)
		half.ImageColor3 = NitroConfig.Hud.ReadyColor
		half.Rotation = if side == "Right" then 180 else 0
		--- An empty tank, which is what a badge nobody is driving should read as. The controller
		--- takes the left half away again below halfway.
		half.Visible = side == "Right"

		local cut = Instance.new("UIGradient")
		cut.Name = "Cut"
		cut.Transparency = CUT_STEP
		--- Twelve o'clock, in each half's own space: the right half's element is turned 180, so
		--- its gradient is turned back by the same 180 to cut on the same line of the clock.
		cut.Rotation = if side == "Right" then -180 else 0
		cut.Parent = half
	end
end

--[[ The bottle: the well, the liquid and the glass, in that order.

	`Liquid` carries the `Cut` gradient the Fill style drains it with, authored here rather than
	added at runtime for the reason every other piece of this HUD is authored: the controller
	finds instances, it does not make them. 270 is bottom to top. ]]
local function buildIcon(frame: Frame)
	local badge = NitroConfig.Hud.Badge

	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.ZIndex = 6
	fill(icon, badge.IconScale)
	icon.Parent = frame

	local well = image("Well", badge.Art.Liquid, icon, 6)
	well.ImageColor3 = dim(NitroConfig.Hud.ReadyColor, badge.WellDim)

	local liquid = image("Liquid", badge.Art.Liquid, icon, 7)
	liquid.ImageColor3 = NitroConfig.Hud.ReadyColor

	local cut = Instance.new("UIGradient")
	cut.Name = "Cut"
	cut.Rotation = 270
	cut.Parent = liquid

	image("Glass", badge.Art.Glass, icon, 8)
end

--[[ The percent, ABOVE the badge. Optional, and absent rather than hidden when it is off.

	Above and not below, which is where it started: the badge stands on the speedo now, and a label
	under it lands on that panel's rounded top edge. Above, the column reads percent, badge, speed,
	and nothing overlaps anything.

	It is also the one piece of this badge that is arguably redundant, since in `Ring` style the
	arc IS the percentage and the number under it is the speedo's. `ShowAmount` is there for that
	argument to be settled by looking. ]]
local function buildAmount(frame: Frame)
	local badge = NitroConfig.Hud.Badge
	if not badge.ShowAmount then
		return
	end

	local amount = Instance.new("TextLabel")
	amount.Name = "Amount"
	amount.BackgroundTransparency = 1
	amount.Text = "100%"
	amount.FontFace = KIT_FONT
	amount.TextSize = SEED_TEXT_SIZE
	amount.TextScaled = true
	amount.TextColor3 = badge.AmountColor
	amount.AnchorPoint = Vector2.new(0.5, 1)
	amount.Position = UDim2.fromScale(0.5, -0.02)
	amount.Size = UDim2.fromScale(0.8, 0.2)
	amount.ZIndex = 6
	amount.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(8, 12, 22)
	stroke.Thickness = 2
	--- Miter on TEXT, where the glyphs' interior corners want to stay sharp. Round is for rims.
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	stroke.Parent = amount
end

--[[ What the badge lands on, in the badge's own terms.

	Reported rather than fixed. Every one of these controls is authored in the Explorer and moving
	somebody's brake pedal out from under a readout is not a decision a builder gets to make on its
	own, but landing a badge on one silently is worse, so the numbers go in the output.

	ON TOUCH ONLY, AND THE WARNING SAYS SO. `DrivingHudController._applyTouchOnly` hides the whole
	`Controls` frame on a keyboard, so on a desktop this corner is the badge and the speedo and
	nothing else; measured in a playtest, `Controls.Visible` was false while every child of it was
	true. The overlap is real on a phone and only there.

	Measured on a 16:9 viewport, because scale positions on this ScreenGui resolve against the
	viewport and an overlap is an aspect-dependent question. It is the aspect the HUD was laid out
	on and the one the answer matters at. ]]
local function overlaps(frame: Frame, hud: Instance): { string }
	local badge = NitroConfig.Hud.Badge
	local aspect = 16 / 9

	local side = badge.Height / aspect -- the badge is square, so its width in X-scale
	local anchor = CORNERS[badge.Corner] or CORNERS.BottomRight
	local at = cornerPosition(badge.Corner, badge.Margin)
	local left = at.X.Scale - anchor.X * side
	local top = at.Y.Scale - anchor.Y * badge.Height
	local right, bottom = left + side, top + badge.Height

	local hits = {}
	local controls = hud:FindFirstChild("Controls")
	for _, item in (if controls then controls:GetChildren() else {}) do
		if item:IsA("GuiObject") and item.Visible then
			local w, h = item.Size.X.Scale, item.Size.Y.Scale
			local l = item.Position.X.Scale - item.AnchorPoint.X * w
			local t = item.Position.Y.Scale - item.AnchorPoint.Y * h
			if l < right and l + w > left and t < bottom and t + h > top then
				table.insert(hits, item.Name)
			end
		end
	end
	return hits
end

return {
	Description = "Builds StarterGui.DrivingHud.NitroBadge, the round nitro readout (bottle, ring and glow), from NitroConfig.Hud.Badge. Rebuilds it on every run.",
	Tags = { "UI", "Driving" },
	AutoRecordChanges = true,
	Arguments = {},

	Run = function(props: Types.Props, _arguments: Types.ArgumentResult)
		local out = props:Output()
		out:clear()

		local hud = StarterGui:FindFirstChild(HUD_NAME)
		if not hud then
			out:error(string.format("StarterGui has no `%s`. Import the driving HUD art first.", HUD_NAME))
			return
		end

		local existing = hud:FindFirstChild(BADGE_NAME)
		if existing then
			existing:Destroy()
		end

		local badge = NitroConfig.Hud.Badge
		local frame = buildFrame(hud)
		buildGlow(frame)
		buildPlate(frame)
		buildRing(frame)
		buildIcon(frame)
		buildAmount(frame)

		out:print(string.format("Built %s.%s, style `%s`.", HUD_NAME, BADGE_NAME, badge.Style))

		local missing = {}
		for name, asset in badge.Art do
			if type(asset) ~= "string" or asset == "" or asset == "rbxassetid://0" then
				table.insert(missing, name)
			end
		end
		if #missing > 0 then
			table.sort(missing)
			out:warn(string.format("No art id for: %s. Those pieces will render as nothing.", table.concat(missing, ", ")))
		end

		if NitroConfig.Hud.Layout ~= "Badge" then
			out:warn(
				string.format(
					"NitroConfig.Hud.Layout is `%s`, so the badge stays hidden and the %s bar is still the live readout.",
					NitroConfig.Hud.Layout,
					NitroConfig.Hud.Layout
				)
			)
		end
		if not NitroConfig.Enabled then
			out:warn("NitroConfig.Enabled is false, so nitro is off outright and nothing here will show.")
		end

		local hits = overlaps(frame, hud)
		if #hits > 0 then
			out:warn(
				string.format(
					"On TOUCH at 16:9 the badge lands on Controls.%s (the Controls frame is hidden on a keyboard, so a desktop is clear). Nudge that control in the Explorer, or move the badge with NitroConfig.Hud.Badge.Margin and re-run.",
					table.concat(hits, ", Controls.")
				)
			)
		end

		pcall(function()
			props:SetSelection({ frame })
		end)
	end,
} :: Types.ScriptModule
