--[[
	BuildSpeedoV2: Command Runner command

	Builds `StarterGui.DrivingHud.SpeedoV2` — the minimal speed readout that replaces the half-dial
	gauge cluster: a light-blue panel holding a big white number, `MPH` beside it, and a row of
	segments under the pair that lights up from the left with a red band at the top.

	=== WHY THIS IS A COMMAND AND NOT `Instance.new` IN A CONTROLLER ==========================

	Because the whole driving HUD is authored in Studio and nothing about it is built in Luau at
	runtime. That is a standing rule with a reason behind it (`assets/ui/driving/README.md`, and the
	header of `DrivingHudController`): Dylan nudges this screen in the Explorer, and a controller
	that creates its own instances takes that away. `DrivingHudController` finds `SpeedoV2` and
	fills in the number and the segments; it never makes them.

	So this command is where the layout lives, and it is idempotent: `SpeedoV2` is destroyed and
	made again on every run. A hand edit to the panel is therefore lost on the next run and the fix
	is to make the edit HERE — the same bargain `BuildHudV2` states. Nothing else under `DrivingHud`
	is touched, so `Cluster`, `Controls` and the two nitro bars all survive it.

	=== EVERY NUMBER COMES OUT OF `SpeedoConfig` =============================================

	Not out of this file. The controller reads that config to drive the thing and this reads it to
	draw it, so there is one table to retune and no chance of the builder and the controller
	disagreeing about how many segments there are or where the redline starts. The cost is that a
	config edit needs a re-run before it shows up, which is the note at the bottom of that file.

	=== WHAT IT DOES NOT DO =================================================================

	It does not hide the old `Cluster`. `SpeedoConfig.Style` decides which readout is live and
	`DrivingHudController._attachSpeedo` acts on it at runtime, because that flag is meant to be
	flipped and looked at rather than rebuilt around. Building this panel on a place still set to
	`Dial` is harmless: it sits there hidden until the flag moves.

	It also does not touch the nitro. The vertical bar hangs off `Cluster` (which is why the cluster
	FRAME stays visible even on the `Bar` style) and moving it up beside this panel is the next job,
	not this one.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)
local SpeedoConfig = require(ReplicatedStorage.shared.Configs.SpeedoConfig)

local HUD_NAME = "DrivingHud"

--- Ubuntu Bold: the kit's type, everywhere, and it ships with Roblox so nothing is uploaded.
local KIT_FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

--[[ `TextScaled` needs a `TextSize` to have been set to something legal before it takes over, and 8
	is what every other label on this HUD carries. The value never renders. ]]
local SEED_TEXT_SIZE = 8

--- The four corners, as the anchor point that parks the panel INTO one. A margin is then a gap from
--- the screen edge at any viewport, rather than a gap that grows with the panel.
local CORNERS: { [string]: Vector2 } = {
	BottomRight = Vector2.new(1, 1),
	BottomLeft = Vector2.new(0, 1),
	TopRight = Vector2.new(1, 0),
	TopLeft = Vector2.new(0, 0),
}

--- Where that anchor lands, given the margin. Each axis is either the margin in from 0 or the
--- margin in from 1, which is exactly what the anchor above says.
local function cornerPosition(corner: string, margin: Vector2): UDim2
	local anchor = CORNERS[corner] or CORNERS.BottomRight
	local x = if anchor.X == 0 then margin.X else 1 - margin.X
	local y = if anchor.Y == 0 then margin.Y else 1 - margin.Y
	return UDim2.fromScale(x, y)
end

local function stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local line = Instance.new("UIStroke")
	line.Color = color
	line.Thickness = thickness
	--- Round, not Miter: a mitred stroke squares off the outside of a rounded rim. Miter is for the
	--- text outlines below, where the glyphs' interior corners want to stay sharp.
	line.LineJoinMode = Enum.LineJoinMode.Round
	line.Parent = parent
	return line
end

local function label(name: string, text: string, parent: Instance): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.BackgroundTransparency = 1
	item.Text = text
	item.FontFace = KIT_FONT
	item.TextSize = SEED_TEXT_SIZE
	item.TextScaled = true
	item.TextColor3 = SpeedoConfig.Readout.Color
	item.Parent = parent
	return item
end

--- The panel itself: the face, its gradient, its border and its curve.
local function buildPanel(hud: Instance): Frame
	local panel = SpeedoConfig.Panel

	local frame = Instance.new("Frame")
	frame.Name = SpeedoConfig.FrameName
	--- WHITE, because the `UIGradient` below multiplies — over white the ramp IS the colour, and
	--- both of its stops can be read straight out of the config. See `Panel.Face`.
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BorderSizePixel = 0
	frame.AnchorPoint = CORNERS[panel.Corner] or CORNERS.BottomRight
	frame.Position = cornerPosition(panel.Corner, panel.Margin)
	frame.Size = UDim2.fromScale(panel.Size.X, panel.Size.Y)
	frame.ZIndex = 2
	frame.Parent = hud

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = panel.AspectRatio
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.AspectType = Enum.AspectType.FitWithinMaxSize
	aspect.Parent = frame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(panel.CornerRadius, 0)
	corner.Parent = frame

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(panel.Face.Top, panel.Face.Bottom)
	gradient.Rotation = 90 -- top to bottom; 0 would run left to right
	gradient.Parent = frame

	stroke(frame, panel.Border, panel.BorderThickness)
	return frame
end

--[[ The number and its unit.

	NOT CENTRED AS A PAIR. The digits are right-aligned into a fixed box and `MPH` is left-aligned
	beside it, so the only thing that moves when 99 becomes 100 is the left edge of the digits — see
	`SpeedoConfig.Readout`. ]]
local function buildReadout(panel: Frame)
	local readout = SpeedoConfig.Readout

	local speed = label("Speed", readout.Placeholder, panel)
	speed.AnchorPoint = readout.Number.Anchor
	speed.Position = UDim2.fromScale(readout.Number.Position.X, readout.Number.Position.Y)
	speed.Size = UDim2.fromScale(readout.Number.Size.X, readout.Number.Size.Y)
	speed.TextXAlignment = Enum.TextXAlignment.Right
	speed.TextYAlignment = Enum.TextYAlignment.Center
	speed.ZIndex = 3

	local speedLine = stroke(speed, readout.Outline, readout.OutlineThickness)
	speedLine.LineJoinMode = Enum.LineJoinMode.Miter

	local unit = label("Unit", readout.UnitText, panel)
	unit.AnchorPoint = readout.Unit.Anchor
	unit.Position = UDim2.fromScale(readout.Unit.Position.X, readout.Unit.Position.Y)
	unit.Size = UDim2.fromScale(readout.Unit.Size.X, readout.Unit.Size.Y)
	unit.TextXAlignment = Enum.TextXAlignment.Left
	unit.TextYAlignment = Enum.TextYAlignment.Bottom
	unit.ZIndex = 3

	local unitLine = stroke(unit, readout.Outline, readout.UnitOutlineThickness)
	unitLine.LineJoinMode = Enum.LineJoinMode.Miter
end

--[[ The well and the segments in it.

	Each segment is placed by ARITHMETIC rather than by a `UIListLayout`, and in scale on both axes.
	A layout would have to be told a pixel padding, which is the one thing on this panel that cannot
	be authored once and left alone — the panel's pixel width changes with every viewport. Position
	`i` at `(i - 1 + gap/2) * pitch` and the spacing is a property of the bar rather than of the
	screen it is drawn on.

	Named `Seg1` upward so `DrivingHudController` can address them by index without caring what
	order the Explorer lists them in. ]]
local function buildBar(panel: Frame): (Frame, number)
	local bar = SpeedoConfig.Bar

	local well = Instance.new("Frame")
	well.Name = "Bar"
	well.BackgroundColor3 = bar.Well
	well.BorderSizePixel = 0
	well.AnchorPoint = bar.Anchor
	well.Position = UDim2.fromScale(bar.Position.X, bar.Position.Y)
	well.Size = UDim2.fromScale(bar.Size.X, bar.Size.Y)
	well.ZIndex = 3
	well.Parent = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(bar.WellCornerRadius, 0)
	corner.Parent = well

	stroke(well, bar.WellBorder, bar.WellBorderThickness)

	--- The segments live in their own inset frame rather than being inset one by one, so the well's
	--- border has clearance on all four sides without every segment having to know about it.
	local strip = Instance.new("Frame")
	strip.Name = "Segments"
	strip.BackgroundTransparency = 1
	strip.AnchorPoint = Vector2.new(0.5, 0.5)
	strip.Position = UDim2.fromScale(0.5, 0.5)
	strip.Size = UDim2.fromScale(1 - bar.Inset.X * 2, 1 - bar.Inset.Y * 2)
	strip.ZIndex = 4
	strip.Parent = well

	local pitch = 1 / bar.Count
	local redFrom = math.floor(bar.Count * SpeedoConfig.Redline) + 1

	for i = 1, bar.Count do
		local red = i >= redFrom
		local lit = i <= bar.PreviewLit

		local seg = Instance.new("Frame")
		seg.Name = string.format("Seg%d", i)
		seg.BorderSizePixel = 0
		seg.BackgroundColor3 = if red
			then (if lit then bar.RedlineLit else bar.RedlineUnlit)
			else (if lit then bar.Lit else bar.Unlit)
		seg.Position = UDim2.fromScale((i - 1 + bar.Gap * 0.5) * pitch, 0)
		seg.Size = UDim2.fromScale(pitch * (1 - bar.Gap), 1)
		seg.ZIndex = 4
		--- Which band this mark is in, written down rather than recomputed: the controller then
		--- does not have to know `Redline` at all, and a mark dragged about in the Explorer keeps
		--- the colour pair it was built with.
		seg:SetAttribute("Redline", red)
		seg.Parent = strip

		local segCorner = Instance.new("UICorner")
		segCorner.CornerRadius = UDim.new(bar.SegmentCornerRadius, 0)
		segCorner.Parent = seg
	end

	return well, redFrom
end

return {
	Description = "Builds StarterGui.DrivingHud.SpeedoV2, the minimal speed readout, from SpeedoConfig. Rebuilds it on every run.",
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

		local existing = hud:FindFirstChild(SpeedoConfig.FrameName)
		if existing then
			existing:Destroy()
		end

		local panel = buildPanel(hud)
		buildReadout(panel)
		local _, redFrom = buildBar(panel)

		out:print(string.format("Built %s.%s.", HUD_NAME, SpeedoConfig.FrameName))
		out:print(
			string.format(
				"%d segments, redline from Seg%d (%.0f of %d mph). Scale tops out at %d mph.",
				SpeedoConfig.Bar.Count,
				redFrom,
				SpeedoConfig.Redline * SpeedoConfig.ScaleTop,
				SpeedoConfig.ScaleTop,
				SpeedoConfig.ScaleTop
			)
		)
		if SpeedoConfig.Style ~= "Bar" then
			out:warn(
				string.format(
					"SpeedoConfig.Style is `%s`, so the old Cluster dial is still the live readout and this panel will stay hidden.",
					SpeedoConfig.Style
				)
			)
		end

		pcall(function()
			props:SetSelection({ panel })
		end)
	end,
} :: Types.ScriptModule
