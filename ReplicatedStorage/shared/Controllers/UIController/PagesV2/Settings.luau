--[[
	Settings page, V2  (client)
	---------------------------
	The settings list on the Cartoony Kit: one row per setting, the name on the left and the control
	on the right. Opened by the gear in the topbar (`TopbarController`), and by nothing else.

	WHAT IS ON THE LIST LIVES IN `Modules/SettingsRows`, shared with the shipping page. This file is
	drawing and nothing else: it knows how the kit's three row templates work and how to put an answer
	onto one. A fifth setting is an edit there and no edit here.

	`BuildSettingsV2` (Command Runner) cloned the kit's `SettingsUI` into `MainUIV2.Pages.Settings`,
	and its header carries the argument for which control a setting gets.

	=== THE KIT DREW THE CONTROLS, SO THERE IS ALMOST NO GEOMETRY HERE ========================

	The shipping page measures the artist's row to find the label's left edge, the width to give it,
	both ends of the pill's travel and how tall a row is, then re-aims the list layout and converts
	every proportion to pixels. None of that is here:

	  • `KitPage` owns the list, the row heights and the canvas.
	  • A toggle is TWO DRAWN SWATCHES and showing one of them, not a pill slid along a track. There
	    is no travel to measure and nothing to tween.
	  • A slider's knob still has to be placed, and that is the one piece of arithmetic left.

	=== THREE THINGS THAT ARE THE SAME AS THE SHIPPING PAGE ==================================

	1. IT DECIDES NOTHING. Every row asks its feature's controller what the answer is and hands a
	   press straight back to it; the repaint comes round through that feature's state event rather
	   than being done on the way out. That is what makes the H key work for free: hide the UI from a
	   keyboard with this screen open and the control moves on its own.

	2. HIDING THE INTERFACE CLOSES THIS SCREEN FIRST, on the spot rather than through the close tween.
	   `SettingsRows` takes that as a callback and `InterfaceController._hold` says why it matters: the
	   sweep records what each ScreenGui was doing so it can put it back, and a page still up when the
	   sweep runs is a page the restore faithfully brings back.

	3. A DRAG REACHES THE SERVER ONCE. `set(value, persist)` is called with `persist` false for every
	   frame of a drag and true when the finger comes off. The level itself is applied on every frame
	   either way, because that is what makes a volume slider feel like a volume slider.

	=== AND ONE THING THAT IS NOT ============================================================

	THE PERCENTAGE IS BESIDE THE TRACK RATHER THAN AFTER IT. The kit drew no readout, so
	`BuildSettingsV2` adds one out of the row's own `Title` and narrows the track to fit it. The
	number is the same `AudioConfig.format` the shipping screen prints.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local AudioConfig = require(ReplicatedStorage.shared.Configs.AudioConfig)
local SettingsRows = require(ReplicatedStorage.shared.Modules.SettingsRows)
local KitPage = require(script.Parent.Parent.KitPage)

local Page = KitPage.extend("Settings")

--- The kit's row templates, by what goes on them. See `BuildSettingsV2`'s header for the rule.
local SWITCH_ROW = "ToggleTemplate"
local STEPPER_ROW = "BtnTemplate"
local SLIDER_ROW = "SliderTemplate"

--[[ How many answers a setting may have and still be drawn as a switch. Two, because a switch is a
	thing with two sides; a third answer has nowhere to go on it. ]]
local SWITCH_ANSWERS = 2

--- How long the slider knob takes to catch up when the value moved without being dragged (the seed
--- landing, or another client of the same player). A drag sets it with no tween at all.
local SETTLE_TIME = 0.08

--[[ The invisible box that catches a press on a slider, as a multiple of the drawn TRACK.

	IT HAS TO BE MUCH TALLER THAN THE TRACK. The kit draws the track at 0.1 of a row, which on a
	phone is a fine LINE and an impossible target. Six times it is roughly the height of the knob,
	which is the thing a player thinks they are aiming at. The shipping page uses the same number for
	the same reason. ]]
local HIT_HEIGHT = 6

--[[ The controls take no hover swell (`Scale` 1), which is not that decision made carelessly. Every
	one of them is a picture that already has a pressed face, and a slider's hit box is a transparent
	rectangle inside a track it must not leave, so growing either moves nothing a player can see. ]]
local CONTROL_HOVER_SCALE = 1

--- One step of a slider from a controller's DPad. The same grain the slider itself has, so a stick
--- and a drag cannot land on different values.
local PAD_STEP = AudioConfig.Step
local PAD_ACTION = "SettingsV2SliderStep"
local PAD_PRIORITY = Enum.ContextActionPriority.High.Value + 600

--- Non-breaking, because `TextScaled` would sooner break a caption onto a second line than pick a
--- smaller font. Every space in a one-line answer on this screen is this one.
local NBSP = utf8.char(0xA0)

local function oneLine(text: string): string
	return (string.gsub(text, "%s+", NBSP))
end

-- === Building ===============================================================

function Page.initialize(self)
	--- The kit's text caps are pixels for a 1080-tall screen; this keeps them in proportion above it.
	KitPage.scaleTextCaps(self.PageUI)

	--[[ One record per setting on screen, in the order they appear.

		NOT `self._rows`, which is `KitPage`'s own list of the GuiObjects it has stamped. Reusing that
		name overwrote the base class's bookkeeping with records it then tried to read as instances,
		and the first `_paint` died on `kind is not a valid member of Frame`. A page extending
		`KitPage` owns the names it invents and nothing else. ]]
	self._settings = {}
	self._drag = nil :: any

	self:_build()
	self:_watchState()
end

function Page:_build()
	local specs = SettingsRows.build(function()
		--[[ On the spot, not through the close tween: a page still up when `InterfaceController`
			sweeps is a page its restore faithfully brings back. Header note 2. ]]
		self.PageUI.Visible = false
		self.UIController:closePage(self.PageName)
	end)

	for _, spec in specs do
		local row
		if spec.Kind == "slider" then
			row = self:_buildSlider(spec)
		elseif spec.Options and #spec.Options == SWITCH_ANSWERS then
			row = self:_buildSwitch(spec)
		else
			row = self:_buildStepper(spec)
		end
		if row then
			table.insert(self._settings, row)
		end
	end

	--- The kit's own bottom spacer, so the last row does not sit against the panel's rim.
	self:newRow("Padding")

	self:_paint(false)
end

--- The name on the left, which every row template draws the same way and none of them needs moved.
function Page:_startRow(templateName: string, spec): (GuiObject?, TextLabel?)
	local row = self:newRow(templateName)
	if not row then
		warn(string.format("[Settings] No `%s` row template; %q has nowhere to go.", templateName, spec.Title))
		return nil, nil
	end

	local title = row:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = spec.Title
	end
	return row, title
end

--[[ A SWITCH: the kit's two swatches, one showing at a time.

	THE COLOUR AND THE SIDE ARE THE WHOLE ANSWER. Both swatches carry `TextTransparency = 1` from the
	artist and are far too small for a word, so nothing is written on them. `BuildSettingsV2`'s header
	states the contract that makes that safe: a two-answer setting lists its "off" answer first, and
	that is the red one on the left.

	BOTH SWATCHES ARE WIRED, not just the visible one. Whichever is showing is the one a press lands
	on, and a press means "go to the other answer", so the two handlers are the same handler. ]]
function Page:_buildSwitch(spec)
	local frame, _title = self:_startRow(SWITCH_ROW, spec)
	if not frame then
		return nil
	end

	local track = frame:FindFirstChild("Toggle")
	local off = track and track:FindFirstChild("Off")
	local on = track and track:FindFirstChild("On")
	if not (off and off:IsA("GuiButton") and on and on:IsA("GuiButton")) then
		warn(string.format("[Settings] The `%s` row has no `Toggle.Off` and `Toggle.On`; %q cannot be pressed.", SWITCH_ROW, spec.Title))
		return nil
	end

	local row = { kind = "switch", spec = spec, frame = frame, swatches = { off, on } }

	for _, swatch in row.swatches do
		swatch:SetAttribute("Scale", CONTROL_HOVER_SCALE)
		--- `Activated` and not `MouseButton1Click`: it is the one event a mouse, a touch and a
		--- gamepad's A press all raise. The `UIButton` tag came with the clone.
		swatch.Activated:Connect(function()
			self:_step(row)
		end)
	end

	return row
end

--[[ A STEPPER: one captioned button, and a press moves to the next answer.

	THIS IS THE SHIPPING SCREEN'S MODEL, and it is what a setting with three or more answers gets.
	`BtnTemplate` ships a greyed `DisabledBtn` under the live one for a control that cannot be
	pressed; nothing on this screen is ever in that state, so it is taken out rather than left sitting
	invisible under every row. ]]
function Page:_buildStepper(spec)
	local frame, _title = self:_startRow(STEPPER_ROW, spec)
	if not frame then
		return nil
	end

	local btns = frame:FindFirstChild("Btns")
	local button = btns and btns:FindFirstChild("OnBtn")
	if not (button and button:IsA("GuiButton")) then
		warn(string.format("[Settings] The `%s` row has no `Btns.OnBtn`; %q cannot be pressed.", STEPPER_ROW, spec.Title))
		return nil
	end

	local disabled = btns:FindFirstChild("DisabledBtn")
	if disabled then
		disabled:Destroy()
	end

	local row = { kind = "stepper", spec = spec, frame = frame, button = button, caption = button:FindFirstChild("Title") }

	button:SetAttribute("Scale", CONTROL_HOVER_SCALE)
	button.Activated:Connect(function()
		self:_step(row)
	end)

	return row
end

--[[ A SLIDER: the kit's track and knob, the percentage beside it, and an invisible box over the lot
	that is what a press actually lands on. See `HIT_HEIGHT`. ]]
function Page:_buildSlider(spec)
	local frame, _title = self:_startRow(SLIDER_ROW, spec)
	if not frame then
		return nil
	end

	local track = frame:FindFirstChild("Slider")
	local knob = track and track:FindFirstChild("Knob")
	if not (track and track:IsA("GuiObject") and knob and knob:IsA("GuiObject")) then
		warn(string.format("[Settings] The `%s` row has no `Slider.Knob`; %q cannot be dragged.", SLIDER_ROW, spec.Title))
		return nil
	end

	--[[ THE KNOB IS A PICTURE AND MUST NOT BE A GAMEPAD TARGET. The kit tagged it `UIButton` with
		every other button in the pack, so a controller had two targets on one slider: the knob, which
		does nothing, and the `Hit` box below, which owns the DPad binding. Landing on the knob is a
		slider that silently refuses to move.

		THE TAG HAS TO COME OFF, not just `Selectable`. `Components/Button` FORCES `Selectable = true`
		when the tag lands and says why ("the tag is the statement of intent"), so writing false here
		and leaving the tag on is a race that the component wins: measured in a playtest, the knob came
		back selectable every time. Removing the tag is agreeing with that file rather than fighting
		it, and it costs nothing visible, because `CONTROL_HOVER_SCALE` is 1 and the press sound comes
		off the `Hit` box that covers the whole control anyway. ]]
	if knob:IsA("GuiButton") then
		knob:RemoveTag("UIButton")
		knob.Selectable = false
	end

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.AnchorPoint = Vector2.new(0.5, 0.5)
	hit.Position = UDim2.fromScale(0.5, 0.5)
	hit.Size = UDim2.fromScale(1, HIT_HEIGHT)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.AutoButtonColor = false
	--- Over the knob, so one handler sees every press on this control rather than two seeing half
	--- each. The knob is a picture underneath it and never has to be pressed itself.
	hit.ZIndex = knob.ZIndex + 1
	hit.Parent = track

	hit:SetAttribute("Scale", CONTROL_HOVER_SCALE)
	--- Built here rather than cloned, so it is the one control on this page that needs the tag asking
	--- for. It buys `Selectable`, which is what puts a gamepad's highlight on a slider at all.
	self:tagButton(hit)

	local row = {
		kind = "slider",
		spec = spec,
		frame = frame,
		track = track,
		knob = knob,
		hit = hit,
		readout = frame:FindFirstChild("Readout"),
		tween = nil :: Tween?,
	}

	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self:_beginDrag(row, input)
		end
	end)

	--[[ The console half. A gamepad has no cursor to drag with, so the DPad steps the value while the
		engine's highlight is sitting on this row, and the binding goes away the moment it moves off.
		No icon is drawn: left and right on a slider is the one control on a gamepad that has never
		needed explaining. ]]
	hit.SelectionGained:Connect(function()
		self:_bindPad(row)
	end)
	hit.SelectionLost:Connect(function()
		self:_unbindPad()
	end)

	return row
end

-- === Drawing ================================================================

--[[ Draw every row from the one thing that decides it: the answer its own controller is holding.

	`animate` is false exactly once per open, from `StartOpenThread`: a control has to be sitting on
	its answer before the panel scales up, not sliding onto it from wherever it was left. ]]
function Page:_paint(animate: boolean?)
	for _, row in self._settings do
		if row.kind == "slider" then
			self:_paintSlider(row, animate)
		elseif row.kind == "switch" then
			self:_paintSwitch(row)
		else
			self:_paintStepper(row)
		end
	end
end

function Page:_paintSwitch(row)
	local chosen = SettingsRows.indexOf(row.spec, row.spec.current())
	for index, swatch in row.swatches do
		swatch.Visible = index == chosen
	end
end

function Page:_paintStepper(row)
	local chosen = SettingsRows.indexOf(row.spec, row.spec.current())
	local option = row.spec.Options and row.spec.Options[chosen]
	if row.caption and row.caption:IsA("TextLabel") and option then
		row.caption.Text = oneLine(option.Name)
	end
end

function Page:_paintSlider(row, animate: boolean?)
	local value = AudioConfig.clamp(row.spec.current(), 0)

	if row.readout and row.readout:IsA("TextLabel") then
		row.readout.Text = AudioConfig.format(value)
	end

	--[[ The knob's travel is inset by half its own width at each end, so 0% and 100% put it flush
		inside the track rather than half outside it. The VALUE still runs the full width of the
		track; only the picture is inset. ]]
	local half = row.knob.Size.X.Scale / 2
	local x = half + value * (1 - 2 * half)
	local position = UDim2.new(x, 0, row.knob.Position.Y.Scale, row.knob.Position.Y.Offset)

	if row.tween then
		row.tween:Cancel()
		row.tween = nil
	end
	if not animate then
		row.knob.Position = position
		return
	end

	row.tween = TweenService:Create(
		row.knob,
		TweenInfo.new(SETTLE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = position }
	)
	row.tween:Play()
end

-- === Answers ================================================================

--[[ Step a toggle to its next answer, wrapping. `SettingsRows` owns the wrap, because it is the
	`Options` list's own rule and both settings screens step the same way.

	APPLIED THROUGH THE CONTROLLER AND NOT HERE, and the repaint comes back round through the state
	event rather than being done on the way out. ]]
function Page:_step(row)
	local nextOption = SettingsRows.nextOption(row.spec, row.spec.current())
	if not (nextOption and row.spec.choose) then
		return
	end

	if not row.spec.choose(nextOption.Key) then
		warn(string.format("[Settings] The controller behind %q is not up; the press did nothing.", row.spec.Title))
	end
end

--[[ Set a slider, live. `commit` is what reaches the server: false for every frame of a drag and
	true when the finger comes off. Header note 3. ]]
function Page:_setSlider(row, value: number, commit: boolean): number
	local level = AudioConfig.clamp(value, 0)
	if row.spec.set then
		row.spec.set(level, commit)
	end
	--- Painted here rather than waiting for the state event, because a controller that refuses (or is
	--- not up) still has to leave the knob somewhere sensible, and a drag repaints itself.
	self:_paintSlider(row, false)
	return level
end

--- Where a press at screen-x `x` lands on `row`'s track, as a 0 to 1.
function Page:_valueAt(row, x: number): number
	local width = row.track.AbsoluteSize.X
	if width <= 0 then
		return 0
	end

	--[[ THE INSET IS SUBTRACTED HERE AND IS NOT ON THE SHIPPING PAGE, and the two screens sit in
		different spaces: `MainUI` sets `IgnoreGuiInset = true`, so there an InputObject's position and
		`AbsolutePosition` are already the same space. `MainUIV2` is in the KIT's space
		(`IgnoreGuiInset = false`, `CoreUISafeInsets`), where `AbsolutePosition` is measured inside the
		inset and an InputObject is measured from the corner of the window.

		ON A DESKTOP THIS SUBTRACTS ZERO, because the inset a slider cares about is the X one and the
		topbar only insets Y. It is here for the device that does not: `CoreUISafeInsets` on a notched
		phone held sideways insets the LEFT edge, and there an unsubtracted press lands that far along
		the track from where the finger went down. Cheap to be right about now and invisible to catch
		later. ]]
	local inset = GuiService:GetGuiInset()
	return math.clamp((x - inset.X - row.track.AbsolutePosition.X) / width, 0, 1)
end

--[[ A press on a slider: jump to it, then follow the pointer until it lifts.

	ONE DRAG AT A TIME across the whole screen (`self._drag`), because two fingers on two sliders is
	not a thing anybody is doing, and holding one is what lets the move and release wires be a single
	pair rather than a pair per row. ]]
function Page:_beginDrag(row, input: InputObject)
	self:_endDrag()

	local drag = { row = row, value = self:_setSlider(row, self:_valueAt(row, input.Position.X), false) }

	drag.moved = UserInputService.InputChanged:Connect(function(moving)
		if moving.UserInputType == Enum.UserInputType.MouseMovement or moving.UserInputType == Enum.UserInputType.Touch then
			drag.value = self:_setSlider(row, self:_valueAt(row, moving.Position.X), false)
		end
	end)

	drag.ended = UserInputService.InputEnded:Connect(function(ending)
		if ending.UserInputType == input.UserInputType then
			self:_endDrag(true)
		end
	end)

	self._drag = drag
end

--- Let go. `commit` saves what the slider is sitting on; a drag interrupted by the page closing does
--- not, because nothing about it was a decision.
function Page:_endDrag(commit: boolean?)
	local drag = self._drag
	if not drag then
		return
	end
	self._drag = nil

	drag.moved:Disconnect()
	drag.ended:Disconnect()

	--- The value the drag actually finished on, remembered rather than read back off the controller:
	--- a controller that is not up would answer with its default and save that.
	if commit then
		self:_setSlider(drag.row, drag.value, true)
	end
end

-- === The gamepad ============================================================

function Page:_bindPad(row)
	ContextActionService:BindActionAtPriority(PAD_ACTION, function(_action, state, input)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		local step = if input.KeyCode == Enum.KeyCode.DPadLeft then -PAD_STEP else PAD_STEP
		self:_setSlider(row, AudioConfig.clamp(row.spec.current(), 0) + step, true)
		return Enum.ContextActionResult.Sink
	end, false, PAD_PRIORITY, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight)
end

function Page:_unbindPad()
	ContextActionService:UnbindAction(PAD_ACTION)
end

-- === Listening ==============================================================

--[[ A setting moving, however it moved: this screen, the server's saved answer landing while the
	screen happens to be open, or the H key toggling the interface from underneath it.

	EVERY EVENT REPAINTS EVERY ROW rather than only its own. A repaint is a handful of properties, so
	telling them apart would cost more code than it saves work, and it would be a second place that
	has to learn about a fifth setting. ]]
function Page:_watchState()
	for _, event in SettingsRows.StateEvents do
		Dispatcher:Subscribe(event, function()
			if self.PageUI.Visible then
				self:_paint(true)
			end
		end)
	end
end

--- `UIController`'s hook for "the page is opening", called before its scale tween. Every control is
--- put on its answer WITHOUT animating, so nothing is caught mid-slide as the panel comes up.
function Page:StartOpenThread()
	self:_paint(false)
end

--- ...and its hook for "the page is closing". A drag that never got its release (the X pressed with
--- a finger still down, a race starting) is dropped rather than left holding two connections.
function Page:StartCloseThread()
	self:_endDrag()
	self:_unbindPad()
end

return Page
