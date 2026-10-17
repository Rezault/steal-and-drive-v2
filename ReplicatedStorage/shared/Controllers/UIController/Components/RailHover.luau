--[[
	RailHover component  (client)
	-----------------------------
	WHAT POINTING AT ONE OF THE NEW HUD'S GRID ICONS DOES. The icon moves and its name comes up under
	it. Nothing else in the cell draws any more, so nothing else moves.

	Since Phase 5 (Dylan, 2026-09-16) the grid in `MainUIV2.HUD.Rail` is bare icons: no kit tile behind
	them and no caption under them. `BuildHudV2` authors that, and keeps each caption as a hidden child
	of the button named `Hint`. This file is the reaction that the tile's hover used to be.

	WITH THE FLAG OFF IT DOES NOTHING AT ALL. The old rail has its own hover art and no `Hint` to watch.

	=== BUTTON DECIDES WHEN, THIS DECIDES HOW =================================================

	`Components/Button` already knows when a button is being pointed at, for every device that can
	point: `MouseEnter` and `SelectionGained` in, `MouseLeave` and `SelectionLost` out, and nothing for
	a button that is switched off. It writes that answer somewhere this file can read, by showing the
	button's `Hint` and hiding it again. So this watches `Hint.Visible` and binds no input of its own.
	That is what makes a gamepad highlight and a cursor do exactly the same thing: there is one copy of
	the rules about when a button counts as hovered, and it is not in here.

	`Button`'s own reaction, the whole-button swell, is off on these buttons (`Scale = 1`, set by
	`BuildHudV2`). It rides a `UIScale` on the button, so it would grow the tooltip along with the icon.

	=== THE ICON, NOT THE CELL ================================================================

	It grows a little and tips a few degrees on a `Back` ease, which overshoots by a hair and settles,
	and it goes back on a plain ease that does not overshoot at all. Small on purpose: this plays every
	time a cursor crosses the rail, and a reaction a player sees forty times a session wants to be felt
	rather than watched. The knobs are the constants below.

	The grow rides a `UIScale` on the icon (`HoverPop`), for the reason `Button` gives for its own: the
	icon's authored `Size` stays the one source of truth.

	=== THE TOOLTIP ===========================================================================

	`Hint` is the kit's own caption label, so its look is the kit's: Fredoka One with the kit's navy
	outline, and no pill (in this kit a pill is a button). `BuildHudV2` rests it under the icon, which is
	where the kit drew the caption, and that spot is the answer to "never off screen, never under
	another HUD member":

	  • Beside the icon does not work in a two-wide grid. To the right of a left-hand icon is the
	    right-hand icon, and to its left is the edge of the screen.
	  • Beside the whole rail was rendered and dropped: for a left-hand icon the words land a whole
	    icon away, next to the wrong one.
	  • Under the icon, the words fit the gap between two rows without touching either icon, the
	    bottom row's words end far above the cash block, and the left-hand column's words (Index,
	    Cars, Shop) are short enough that centred on their icons they stay clear of the screen edge.

	While a cell is hovered it is drawn above its neighbours (`ZIndex` up by one), so the words sit
	over the row below rather than under it if a small screen ever brings them that close. The grid
	lays out by `LayoutOrder`, so the `ZIndex` moves nothing.

	It fades up from a hair below its resting place. THE OUTLINE ARRIVES LATE, in the second half of
	the fade: an outline is drawn under the whole glyph, so text and outline fading together show a
	grey letter with a dark ring round it on the way (see `NearMissConfig.Ui.StrokeFade`). The way out
	is instant, because `Button` hides `Hint` outright, and that is why nothing can linger: there is no
	fade out to leave an outline behind.

	=== PUT BACK WHEN THE GRID GOES ===========================================================

	A hover that is still on when the grid is taken off screen may never get its leave: a race hides
	`Rail` (`RaceEntryController`), the hide-UI switch disables the whole ScreenGui
	(`InterfaceController`), and a hidden button is not a button a cursor can leave. The icon would
	come back grown with its words still up. So any of those three switches going dark puts every icon
	back and hides every tooltip, which `Button` will simply show again on the next hover.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIControllerTypes = require(script.Parent.Parent.UIControllerTypes)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)

--- Seconds to wait for the authored UI, matching `HudRules` and `GamepadNav`.
local GUI_WAIT = 10

--- The names read here. `Rail`, `Main` and `Icon` are `BuildHudV2`'s; `Hint` is `Components/Button`'s.
local RAIL_NAME = "Rail"
local BUTTON_NAME = "Main"
local ICON_NAME = "Icon"
local HINT_NAME = "Hint"
local POP_NAME = "HoverPop"

-- === The knobs =====================================================================

--[[ The icon. `ICON_SCALE` is the size it grows to and `ICON_ANGLE` the degrees it tips (negative is
	anticlockwise). The `Back` ease on the way in overshoots both by about a tenth of the change, which
	is the settle. `BuildHudV2.TIP_TOP` rests the tooltip just clear of an icon at this size, so raise
	`ICON_SCALE` much past 1.1 and move that too. ]]
local ICON_SCALE = 1.1
local ICON_ANGLE = -6
local ICON_IN_TIME = 0.18
local ICON_OUT_TIME = 0.12

--[[ The tooltip. `TIP_RISE` is how far below its resting place it starts, as a fraction of the
	button's height. `TIP_STROKE_SHARE` is the part of the fade the outline takes, at the end. ]]
local TIP_TIME = 0.12
local TIP_RISE = 0.06
local TIP_STROKE_SHARE = 0.5

local ICON_IN = TweenInfo.new(ICON_IN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local ICON_OUT = TweenInfo.new(ICON_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TIP_IN = TweenInfo.new(TIP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local STROKE_IN = TweenInfo.new(
	TIP_TIME * TIP_STROKE_SHARE,
	Enum.EasingStyle.Linear,
	Enum.EasingDirection.Out,
	0,
	false,
	TIP_TIME * (1 - TIP_STROKE_SHARE)
)

--[[ Wire one cell, and hand back the function that puts it back. Nil for a cell that is not one of
	ours, with a warning, because a place whose grid was built before Phase 5 has no `Hint` and would
	otherwise just look like hover had stopped working.

	Waits per hop: this runs as the ScreenGui arrives, and a StarterGui clone is not promised to have
	all of itself yet. ]]
local function bindCell(cell: GuiObject): (() -> ())?
	local button = cell:WaitForChild(BUTTON_NAME, GUI_WAIT)
	local icon = button and button:WaitForChild(ICON_NAME, GUI_WAIT)
	local hint = button and button:WaitForChild(HINT_NAME, GUI_WAIT)
	if not (icon and icon:IsA("GuiObject") and hint and hint:IsA("TextLabel")) then
		warn(string.format("[RailHover] %s has no `Main.Icon` and `Main.Hint`; run BuildHudV2.", cell:GetFullName()))
		return nil
	end
	local stroke = hint:FindFirstChildOfClass("UIStroke")

	local pop = icon:FindFirstChild(POP_NAME) :: UIScale?
	if not pop then
		pop = Instance.new("UIScale")
		pop.Name = POP_NAME
		pop.Parent = icon
	end

	--- The resting pose, read once. Authored by the build command; nothing else writes these.
	local restZ = cell.ZIndex
	local restAngle = icon.Rotation
	local restPosition = hint.Position

	local hovered = false
	local playing: { Tween } = {}

	local function play(instance: Instance, info: TweenInfo, goal: { [string]: any })
		local tween = TweenService:Create(instance, info, goal)
		table.insert(playing, tween)
		tween:Play()
	end

	--[[ A cancelled tween stops where it is, so reversing mid-way starts from wherever the icon had got
		to rather than snapping. The tooltip's values are set outright on the way out, since it is
		hidden by then. ]]
	local function set(on: boolean)
		if on == hovered then
			return
		end
		hovered = on
		for _, tween in playing do
			tween:Cancel()
		end
		table.clear(playing)

		if on then
			cell.ZIndex = restZ + 1
			play(pop :: UIScale, ICON_IN, { Scale = ICON_SCALE })
			play(icon, ICON_IN, { Rotation = restAngle + ICON_ANGLE })

			hint.Position = restPosition + UDim2.fromScale(0, TIP_RISE)
			hint.TextTransparency = 1
			play(hint, TIP_IN, { Position = restPosition, TextTransparency = 0 })
			if stroke then
				stroke.Transparency = 1
				play(stroke, STROKE_IN, { Transparency = 0 })
			end
		else
			cell.ZIndex = restZ
			play(pop :: UIScale, ICON_OUT, { Scale = 1 })
			play(icon, ICON_OUT, { Rotation = restAngle })

			hint.Position = restPosition
			hint.TextTransparency = 0
			if stroke then
				stroke.Transparency = 0
			end
		end
	end

	--- Read the value rather than assume a toggle: a changed signal is deferred in this place, so an
	--- in and an out inside one frame can arrive as two handlers that both see the final answer.
	hint:GetPropertyChangedSignal("Visible"):Connect(function()
		set(hint.Visible)
	end)

	return function()
		hint.Visible = false
		set(false)
	end
end

return function(UIController: UIControllerTypes.UIController)
	task.spawn(function()
		if not UIRoot.isNewUI() then
			return
		end

		local mainUI = UIRoot.wait(UIController.PlayerGui, GUI_WAIT)
		local hud = mainUI and mainUI:WaitForChild("HUD", GUI_WAIT)
		local rail = hud and hud:WaitForChild(RAIL_NAME, GUI_WAIT)
		if not (mainUI and hud and rail and hud:IsA("GuiObject") and rail:IsA("GuiObject")) then
			--- Silent, like `HudRules`: `GarageHudController` and `GamepadNav` already say so when the
			--- UI is not in the place.
			return
		end

		--[[ The tooltip's size cap is the kit's, and the kit's caps are pixels for a screen 1080 tall,
			so at 4K the words would draw at about half their box. `KitPage.scaleTextCaps` is the one
			place that corrects that for every V2 screen, and the WHOLE HUD is handed to it here, not
			just the grid, because nothing else in the HUD calls it: the Phase 5 device pass measured
			the cash line and PLAY at 46% of their boxes at 4K while the tooltips were right. Required
			here rather than at the top so the flag-off path never loads `KitPage` at all, and guarded
			so this file does not break if the helper moves. ]]
		local KitPage = require(script.Parent.Parent.KitPage) :: any
		if type(KitPage.scaleTextCaps) == "function" then
			KitPage.scaleTextCaps(hud)
		end

		local putBack: { () -> () } = {}

		local function bind(child: Instance)
			if not child:IsA("GuiObject") then
				return -- the grid layout and the aspect constraint
			end
			task.spawn(function()
				local reset = bindCell(child)
				if reset then
					table.insert(putBack, reset)
				end
			end)
		end
		for _, child in rail:GetChildren() do
			bind(child)
		end
		rail.ChildAdded:Connect(bind)

		local function onSwitch()
			if mainUI.Enabled and hud.Visible and rail.Visible then
				return
			end
			for _, reset in putBack do
				reset()
			end
		end
		mainUI:GetPropertyChangedSignal("Enabled"):Connect(onSwitch)
		hud:GetPropertyChangedSignal("Visible"):Connect(onSwitch)
		rail:GetPropertyChangedSignal("Visible"):Connect(onSwitch)
	end)
end
