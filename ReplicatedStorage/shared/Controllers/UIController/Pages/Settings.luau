--[[
	Settings page  (client)
	-----------------------
	The settings list: one row per setting, the name on the left and the control on the right.
	Opened by the gear in the topbar (`TopbarController`), and by nothing else.

	IT IS THE BOSS'S SCREEN, AUTHORED IN THE EXPLORER, AND THIS FILE DRAWS ALMOST NOTHING. Everything
	the list is made of lives at `StarterGui.MainUI.Pages.Settings`: the panel, the row band, the
	gold toggle pill, the slider track and its knob. What is here is the wiring.

	The exception is the CHROME, and it is two instances: the woven title cap this page did not come
	with, and the three faces of the X. `_dressChrome` is the whole of it and says why.

	That is the whole reason this replaced a `SettingsController` that built its own ScreenGui out of
	Frames and UICorners: a screen that needs a source edit to change a colour is a screen the person
	who designs it cannot change. See `ui-architecture-preference` in the project memory.

	SEVEN THINGS TO KNOW BEFORE CHANGING ANY OF IT.

	1. THE AUTHORED ROWS ARE TEMPLATES, NOT THE LIST. `Slots` holds four rows in the place: two
	   toggles and two sliders, all named `Settings`. This takes ONE of each as a template, empties
	   `Slots`, and clones one row per entry in `_specs`. So the number of rows on screen is decided
	   by which features are switched on, and restyling a row in the Explorer restyles every row of
	   that kind. Adding a fifth authored row does nothing; adding a spec adds a row.

	   The same bargain the Quest board, SPAWN CARS and START CAR make with their authored samples,
	   and for the same reason.

	2. THERE ARE EXACTLY TWO KINDS OF CONTROL and a spec says which by its `Kind`.

	     • `toggle` is the gold pill. It holds ANY NUMBER OF ANSWERS, not two: pressing it steps to
	       the next one, the pill slides to that answer's position along the track, and the caption
	       on the pill is the answer. Two answers is the drawing exactly (the pill sits flush left or
	       flush right); three is the same pill at three stops, which is how Time of day fits a
	       control that was drawn as an on/off switch without inventing a second control.
	     • `slider` is the thin track. It carries a 0 to 1 and a percentage readout.

	   A dropdown would start to earn its place at four or five answers, where a caption you have to
	   step through stops being findable. Nothing here has that many.

	3. IT DECIDES NOTHING, AND IT NO LONGER DECIDES WHAT IS ON THE LIST EITHER. Every row asks its
	   feature's own controller what the answer is and hands a press straight back to it; the repaint
	   comes round through that feature's state event rather than being done on the way out. One
	   truth, one direction, the same bargain the topbar's mute button makes. That is also what makes
	   the H key work for free: hide the UI from a keyboard with this screen open and the pill slides
	   on its own.

	   WHICH SETTINGS EXIST MOVED TO `Modules/SettingsRows` on 2026-09-15, because the Cartoony Kit
	   screen behind `NewUIConfig.Enabled` shows the same list. A fifth setting is one edit there and
	   no edit here. What is left in this file is drawing.

	4. THE LAYOUT IS MEASURED OFF THE ART, never typed in again. The label's left edge, the width it
	   is given, where the pill sits at either end of its travel and how tall a row is are all read
	   back from the authored row in `_measure`. Two things are deliberately NOT where the artist put
	   them, and `_dressRow` is where both happen: the name is left aligned and widened to the
	   control's edge, because the authored box is sized for the word "Settings" and the real names
	   are longer; and the pill's caption box is widened for the same reason ("Hidden" does not fit
	   in a box cut for "Off"). Moving either in the Explorer will not move it on screen.

	5. ROW HEIGHTS ARE IN PIXELS, AND THAT IS NOT A STYLE CHOICE. Inside a ScrollingFrame a child's Y
	   scale resolves against the CANVAS, and a scale canvas resolves against the ScrollingFrame's
	   PARENT, so the authored 0.0744 of a 2x canvas is really 0.1489 of the page. Left in scale with
	   a content-sized canvas the two feed each other and run away (the Quest board's note 2 has the
	   measured numbers). So `_syncMetrics` converts the authored proportion to pixels off the page's
	   live `AbsoluteSize` and computes the canvas from the row count, and it redoes both on resize.

	6. THE LIST LAYOUT IS RE-AIMED AT RUNTIME. The authored `UIListLayout` is a HORIZONTAL one with
	   `Wraps` on, which stacks full-width rows one per line and does reach the right answer. This
	   sets it to a vertical list ordered by `LayoutOrder` instead, because the row order is now this
	   file's decision and `SortOrder.Name` cannot express it, because every authored row is called
	   `Settings`. It is a change to the runtime copy in PlayerGui; the place is untouched.

	7. THE STATUS SENTENCES ARE GONE, and that is the one thing the old screen had that this does
	   not. The artist's row is a name and a control on one line with no room for a second, so
	   `DayNightConfig.statusFor` and `InterfaceConfig.statusFor` are no longer shown anywhere. The
	   line worth missing is the hidden-interface one that named the H key; the SHOW UI button in the
	   topbar is what is left saying there is a way back, and its caption carries the key. If a row ever needs its sentence, the honest fix is a
	   second line authored into the row band, not a caption squeezed under the name.

	HOUSE RULE: no wiki-style double-bracket links in this comment, the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UIControllerTypes = require(script.Parent.Parent.UIControllerTypes)
local UIGeom = require(script.Parent.Parent.UIGeom)
local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local AudioConfig = require(ReplicatedStorage.shared.Configs.AudioConfig)
local SettingsConfig = require(ReplicatedStorage.shared.Configs.SettingsConfig)
local SettingsRows = require(ReplicatedStorage.shared.Modules.SettingsRows)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)

local PAGE_NAME = SettingsConfig.PageName

--- How long the gold pill takes to slide onto a new answer. Short: it is answering a press, and a
--- press should look immediate.
local SLIDE_TIME = 0.14

--- How long the slider knob takes to catch up when the value moved without being dragged (the seed
--- landing, or another client of the same player). A drag sets it with no tween at all.
local SETTLE_TIME = 0.08

--[[ The gap between the name and the control, as a fraction of a row. The name is widened up to
	this much short of the control's left edge; see header note 4 on why it is widened at all. ]]
local LABEL_GUTTER = 0.02

--- How much of the gold pill the caption may use. The authored box is cut for "Off" and the answers
--- on this screen run to "Hidden" and "Night".
local CAPTION_WIDTH = 0.86

--[[ The invisible box that catches a press on a slider, as a multiple of the authored TRACK.

	IT HAS TO BE MUCH TALLER THAN THE TRACK. The track is drawn about 6px tall on a 1080p screen,
	which is a fine LINE and an impossible target, especially on a phone. Six times it is roughly the
	height of the knob, which is the thing a player thinks they are aiming at. ]]
local HIT_HEIGHT = 6

--[[ How far the X swells under a cursor, read off the `Scale` attribute by `Components/Button`.

	1.06 IS WHAT THE OTHER PAGES USE. Quest, Market and Index sit at 1.05 and Teleport and Start Car
	at 1.06, so this is the kit's own number rather than one picked for this screen. It is barely
	over the component's 1.05 default on purpose: the X now wears the kit's art, which carries its
	own brighter hover face, and a swell loud enough to notice on top of that reads as two things
	answering one cursor. ]]
local CLOSE_HOVER_SCALE = 1.06

--[[ How far down the page the header cap reaches, in the page's own scale.

	THE SAME 0.104 THE SHOP USES, and that is not a coincidence to be tidied away: both imported
	pages point `BG` at the same texture (`86485756805541`) and their `XButton` rects are identical
	to the last decimal, so the painted band is in the same place on both. `BuildShopPage` carries
	the long version of how the number was measured and why the cap is full width. ]]
local CAP_HEIGHT = 0.104

--[[ ...and the two controls take no swell at all (`Scale` 1), which is not that decision made
	harder. The gold pill is a picture that already has a pressed state, and a slider's hit box is a
	transparent rectangle inside a track it must not leave, so growing either moves nothing a player
	can see and overhangs the row. ]]
local CONTROL_HOVER_SCALE = 1

--- One step of a slider from a controller's DPad. The same grain the slider itself has, so a stick
--- and a drag cannot land on different values.
local PAD_STEP = AudioConfig.Step
local PAD_ACTION = "SettingsSliderStep"
local PAD_PRIORITY = Enum.ContextActionPriority.High.Value + 600

--[[ Ubuntu BOLD, the kit's face, and a `Font` object rather than an `Enum.Font` because
	`Enum.Font.Ubuntu` is Ubuntu REGULAR. Written to `FontFace`, never to `Font`. Every other screen
	in this game spells this same line; see `_dressFont` for why this one needs it at all. ]]
local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

--- Non-breaking, because `TextScaled` would sooner break a caption onto a second line than pick a
--- smaller font. Every space in a one-line caption on this screen is this one.
local NBSP = utf8.char(0xA0)

local function oneLine(text: string): string
	return (string.gsub(text, "%s+", NBSP))
end

local Page = {}
Page.__index = Page

function Page.new(UIController: UIControllerTypes.UIController)
	local self = setmetatable({}, Page)
	self.UIController = UIController
	self.Player = UIController.Player or Players.LocalPlayer

	local mainUI = UIController.PlayerGui:WaitForChild("MainUI")
	self.PageUI = mainUI:WaitForChild("Pages"):WaitForChild(PAGE_NAME)

	self.Slots = self.PageUI:WaitForChild("Slots")

	--- One entry per drawn row, in the order they appear. A list rather than a map because the ORDER
	--- is the layout: a row's index is where in the stack it sits.
	self._rows = {}
	self._drag = nil :: any

	self:_dressFont()
	self:_dressChrome()

	-- A LOCAL, never `self.Close`: the controller treats a `Close` field on a page as that page's
	-- custom close ROUTINE and calls it, so parking the button there makes closing throw.
	local close = self.PageUI:WaitForChild("XButton")
	close:SetAttribute("Scale", CLOSE_HOVER_SCALE)
	CollectionService:AddTag(close, "UIButton")
	close.MouseButton1Click:Connect(function()
		self.UIController:closePage(PAGE_NAME)
	end)

	self:_measure()
	self:_build()
	self:_watchState()

	return self
end

function Page.initialize(_self) end

-- === The chrome =============================================================

--[[ THE IMPORTED PAGE IS SET IN ARIAL AND THE REST OF THE GAME IS NOT.

	Every other page in `MainUI.Pages` is Ubuntu Bold, which is the face `car ui.psd` is drawn in.
	This one arrived from somewhere else with Roblox's default left on all eleven of its labels, and
	the difference reads immediately: it is a settings screen borrowed from another game sitting
	inside this one. (The shop page has the same import and the same problem, half converted.)

	FIXED HERE RATHER THAN IN THE PLACE, for the reason `_dressChrome` gives directly below: the
	artist re-imports this screen, and a place edit is exactly the piece a re-import throws away
	without saying so.

	IT WALKS THE TEXT RATHER THAN NAMING IT, because the claim being made is that NOTHING on this
	page is in another face, and a list of names is one label out of date the first time a row gains
	one. Called BEFORE `_measure`, so the row templates are cloned already set and every row built
	from them inherits the face instead of being fixed up one at a time. ]]
function Page:_dressFont()
	for _, inst in self.PageUI:GetDescendants() do
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			inst.FontFace = FONT
		end
	end
end

--[[ The two pieces of this screen that are NOT the artist's, and the only two.

	Header note 1 says this file draws nothing, and that stays true of the LIST: every row, pill,
	track and knob on screen is cloned from art in the Explorer. The frame around it is a different
	matter, because the import did not come off the kit's chassis and two pieces of it were the
	import's own rather than the kit's.

	1. THE CAP. `BG` is one texture with a FLAT blue header baked into it. Every other page in this
	   kit wears a WOVEN cap as its own ImageLabel over the panel, so this lays one on: same asset,
	   same full bleed, same reasoning `BuildShopPage` sets out at length for the Shop, which is
	   literally the same texture underneath. Blue rather than an accent because blue is what is
	   painted there and because the kit's three accents are spoken for (Index orange, Quests red,
	   Market green); Teleport and Start Car are blue for the same reason.

	2. THE X. The import brought a flat red rounded square with one state. `UIAssets.Page.Close` is
	   the crimson coin every other page closes with, and it has a hover and a pressed face. The
	   artist's RECT does not move: their X is square in pixels and centred in the band they
	   painted, which is not where the kit pages put theirs, so only the three faces change.

	WHY AT RUNTIME AND NOT IN THE PLACE. The Shop's equivalent lives in `BuildShopPage` because that
	script already owns the Shop's chrome; this page has no build script at all and dresses itself
	from the art every time it is constructed, so a place edit here would be the one piece of this
	screen that a re-import silently threw away. Idempotent either way: it reuses the cap if one is
	already there. ]]
function Page:_dressChrome()
	local page = self.PageUI

	local bg = page:FindFirstChild("BG")
	if bg then
		bg.ZIndex = 1
	end

	local cap = page:FindFirstChild("TitleBar") :: ImageLabel?
	if not cap then
		cap = Instance.new("ImageLabel")
		cap.Name = "TitleBar"
		cap.Parent = page
	end
	cap.AnchorPoint = Vector2.new(0.5, 0)
	cap.BackgroundTransparency = 1
	cap.Position = UDim2.fromScale(0.5, 0)
	cap.Size = UDim2.fromScale(1, CAP_HEIGHT)
	cap.Image = UIAssets.url(UIAssets.SpawnCar.TitleBar)
	-- Stretch and never 9-slice. These caps have a corner radius of zero and their alpha is a plain
	-- rectangle, so slicing one only pins the artist's hairline rim at texture pixels.
	cap.ScaleType = Enum.ScaleType.Stretch
	cap.ZIndex = 2

	local title = page:FindFirstChild("Title")
	if title then
		title.ZIndex = 3
	end

	local close = page:FindFirstChild("XButton") :: ImageButton?
	if close then
		close.ZIndex = 4
		close.Image = UIAssets.url(UIAssets.Page.Close.Idle)
		close.HoverImage = UIAssets.url(UIAssets.Page.Close.Hover)
		close.PressedImage = UIAssets.url(UIAssets.Page.Close.Pressed)
		-- Or Roblox lays its own press tint over `PressedImage` and the two darken together. Every
		-- kit page has this off; the import shipped it on because it had no pressed face to protect.
		close.AutoButtonColor = false
	end
end

-- === Reading the art ========================================================

--[[ Everything this file needs to know about the authored row, taken off the authored row.

	THE TEMPLATES ARE FOUND BY WHAT IS INSIDE THEM, not by name or by position: every row in the
	place is called `Settings`, so the toggle is "the row whose pill has a caption in it" and the
	slider is "the row with a percentage readout". That means the artist can reorder them, rename
	them or add a fifth without this having to be told. ]]
function Page:_measure()
	local toggle, slider
	for _, child in self.Slots:GetChildren() do
		if child:IsA("GuiObject") then
			local container = child:FindFirstChild("ButtonContainer")
			local button = container and container:FindFirstChild("Button")
			if button and button:FindFirstChildWhichIsA("TextLabel") then
				toggle = toggle or child
			elseif button and child:FindFirstChild("%") then
				slider = slider or child
			end
		end
	end

	assert(toggle, "Pages.Settings: no authored toggle row (a row whose ButtonContainer.Button has a caption)")
	assert(slider, "Pages.Settings: no authored slider row (a row with a `%` readout beside its track)")

	self._templates = { toggle = toggle:Clone(), slider = slider:Clone() }

	--[[ The row's height as a fraction of the PAGE, which is not the number written on the row.
		Header note 5: a scale child of a ScrollingFrame measures against the canvas, and a scale
		canvas measures against the ScrollingFrame's parent, so the two multiply. ]]
	local canvasScale = self.Slots.CanvasSize.Y.Scale
	if canvasScale <= 0 then
		canvasScale = 1
	end
	self._rowRatio = toggle.Size.Y.Scale * canvasScale

	local layout = self.Slots:FindFirstChildWhichIsA("UIListLayout")
	assert(layout, "Pages.Settings: Slots has no UIListLayout")
	self._layout = layout
	self._padRatio = layout.Padding.Scale * canvasScale

	--- The name's left edge, and the left edge of the nearest control on either kind of row. Both
	--- through `UIGeom` rather than off `Position`, because these are anchored at their centres.
	local label = toggle:FindFirstChild("Settings")
	self._labelLeft = if label then UIGeom.left(label) else 0.02
	self._labelHeight = if label then label.Size.Y.Scale else 0.45

	local controlLeft =
		math.min(UIGeom.left(toggle.ButtonContainer :: GuiObject), UIGeom.left(slider.ButtonContainer :: GuiObject))
	self._labelWidth = math.max(controlLeft - LABEL_GUTTER - self._labelLeft, 0.1)

	--[[ The two ends of the gold pill's travel. Only the LOW end is authored (the artist drew the
		pill at "Off"); the high end is its mirror, which is what the row's own symmetry says and
		what the pill's width confirms, since it overhangs the container by the same sliver at each end. ]]
	self._knobLow = (toggle.ButtonContainer :: any).Button.Position.X.Scale
	self._knobHigh = 1 - self._knobLow
end

-- === Building ===============================================================

--[[ The settings on this screen, in the order they appear, each one switched on by its own feature.

	THE LIST ITSELF MOVED TO `Modules/SettingsRows` on 2026-09-15, because the Cartoony Kit settings
	screen behind `NewUIConfig.Enabled` shows the same settings and a fifth one should be one edit
	rather than two that have to agree. Everything that used to be written out here is there, with the
	reasoning: every controller fetched per call, a toggle holding any number of answers, and why
	hiding the interface has to close this screen first.

	WHAT STAYED HERE is the one thing only this screen can do, and it is the argument for the callback
	below: putting this page away on the spot, before `InterfaceController` sweeps, because a page
	still up when the sweep runs is a page the restore faithfully brings back. ]]
function Page:_specs()
	return SettingsRows.build(function()
		self.PageUI.Visible = false
		self.UIController:closePage(PAGE_NAME)
	end)
end

function Page:_build()
	--- Header note 6: the row order is this file's now, and every authored row has the same name.
	self._layout.FillDirection = Enum.FillDirection.Vertical
	self._layout.Wraps = false
	self._layout.SortOrder = Enum.SortOrder.LayoutOrder
	self.Slots.ScrollingDirection = Enum.ScrollingDirection.Y

	--- The authored rows are the templates and the templates are already copied. Note 1.
	for _, child in self.Slots:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	for index, spec in self:_specs() do
		local row = if spec.Kind == "slider" then self:_buildSlider(spec, index) else self:_buildToggle(spec, index)
		table.insert(self._rows, row)
	end

	self:_syncMetrics()
	self.PageUI:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_syncMetrics()
	end)

	self:_paint(false)
end

--[[ The parts of a row that are the same whichever control it carries: the frame's name and order,
	and the setting's name widened and pushed to the left edge of the band.

	SENTENCE CASE, as the artist drew it. The cap over the panel is a heading and these are list
	items, and shouting both flattens them. ]]
function Page:_dressRow(spec, index: number): Frame
	local template = if spec.Kind == "slider" then self._templates.slider else self._templates.toggle
	local frame = template:Clone()
	frame.Name = "Row_" .. tostring(index)
	frame.LayoutOrder = index
	frame.Visible = true

	--[[ Renamed off `Settings`, which is also the row's own name and the page's: a child sharing its
		parent's name makes every path through this file ambiguous to read even where it is not
		ambiguous to the engine. ]]
	local label = frame:FindFirstChild("Settings") :: TextLabel?
	if label then
		label.Name = "Label"
		label.Text = spec.Title
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextWrapped = false
		UIGeom.reanchor(label, Vector2.new(0, 0.5))
		label.Size = UDim2.fromScale(self._labelWidth, self._labelHeight)
		UIGeom.place(label, self._labelLeft, 0.5 - self._labelHeight / 2)
	end

	frame.Parent = self.Slots
	return frame
end

--[[ A toggle row: the gold pill, one caption per answer, and a press that steps to the next.

	THE CAPTIONS ARE CLONES OF THE ARTIST'S, not new TextLabels, so each one keeps the font, the
	outline and the size he drew. The authored pair (`Off` and `On`) are the sample; the first is
	kept as the template for however many answers there are and both originals go. ]]
function Page:_buildToggle(spec, index: number)
	local frame = self:_dressRow(spec, index)
	local knob = (frame.ButtonContainer :: any).Button :: ImageButton

	local caption: TextLabel?
	for _, child in knob:GetChildren() do
		if child:IsA("TextLabel") then
			if not caption then
				caption = child:Clone()
			end
			child:Destroy()
		end
	end

	local captions = {}
	for optionIndex, option in spec.Options do
		local label = if caption then caption:Clone() else Instance.new("TextLabel")
		--- The fallback arm is the one label on this screen `_dressFont` never saw, because it is
		--- made here rather than cloned off the art. A bare TextLabel is SourceSans.
		label.FontFace = FONT
		label.Name = "Option_" .. tostring(optionIndex)
		label.Text = oneLine(option.Name)
		label.TextWrapped = false
		label.Size = UDim2.fromScale(CAPTION_WIDTH, label.Size.Y.Scale)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Visible = false
		label.Parent = knob
		table.insert(captions, label)
	end

	knob:SetAttribute("Scale", CONTROL_HOVER_SCALE)
	CollectionService:AddTag(knob, "UIButton")

	local row = {
		kind = "toggle",
		spec = spec,
		title = spec.Title,
		frame = frame,
		knob = knob,
		captions = captions,
		options = spec.Options,
		current = spec.current,
		choose = spec.choose,
		tween = nil :: Tween?,
	}

	--[[ `Activated` and not `MouseButton1Click`, because it is the one event a mouse, a touch and a
		gamepad A press all raise. Wiring both would double-fire every mouse press, which on a
		three-answer row steps past the answer the player aimed at. ]]
	knob.Activated:Connect(function()
		self:_step(row)
	end)

	return row
end

--[[ A slider row: the thin track, the knob on it, the percentage beside it, and an invisible box
	over the lot that is what a press actually lands on. See `HIT_HEIGHT`. ]]
function Page:_buildSlider(spec, index: number)
	local frame = self:_dressRow(spec, index)
	local track = frame.ButtonContainer :: Frame
	local knob = track:FindFirstChild("Button") :: ImageButton

	local readout = frame:FindFirstChild("%") :: TextLabel?
	if readout then
		readout.Name = "Readout"
		readout.TextWrapped = false
	end

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.AnchorPoint = Vector2.new(0.5, 0.5)
	hit.Position = UDim2.fromScale(0.5, 0.5)
	hit.Size = UDim2.fromScale(1, HIT_HEIGHT)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	--- Draws nothing, and still set: `_dressFont` claims every text object on this page is in the
	--- kit's face, and a claim with two quiet exceptions in it is one nobody can check.
	hit.FontFace = FONT
	hit.AutoButtonColor = false
	--- Over the knob, so one handler sees every press on this control rather than two seeing half
	--- each. The knob is a picture underneath it and never has to be pressed itself.
	hit.ZIndex = knob.ZIndex + 1
	hit.Parent = track

	hit:SetAttribute("Scale", CONTROL_HOVER_SCALE)
	CollectionService:AddTag(hit, "UIButton")

	local row = {
		kind = "slider",
		title = spec.Title,
		frame = frame,
		track = track,
		knob = knob,
		hit = hit,
		readout = readout,
		current = spec.current,
		set = spec.set,
		tween = nil :: Tween?,
	}

	hit.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			self:_beginDrag(row, input)
		end
	end)

	--[[ The console half. A gamepad has no cursor to drag with, so the DPad steps the value while
		the engine's highlight is sitting on this row, and the binding goes away the moment it moves
		off. No icon is drawn: left and right on a slider is the one control on a gamepad that has
		never needed explaining. ]]
	hit.SelectionGained:Connect(function()
		self:_bindPad(row)
	end)
	hit.SelectionLost:Connect(function()
		self:_unbindPad(row)
	end)

	return row
end

-- === Layout =================================================================

--[[ Row heights and the canvas, in pixels, off the page's live size. Header note 5 is the argument;
	this is the arithmetic. Called once at build and again on every resize. ]]
function Page:_syncMetrics()
	--[[ THE OPEN TWEEN IS DIVIDED BACK OUT. `UIController` scales every page from 0.9 through a
		`UIScale` it adds to the page frame, and `AbsoluteSize` reports the SCALED size, so a naive
		read would make the rows 10% short and then grow them frame by frame all the way up the
		tween. Dividing by the scale gives the page's settled height on the first call and the same
		number on every call after, so the rows are sized once and the tween is left to do its own
		job of scaling everything at once.

		Read off the instance rather than off `self._pageScale`, which the controller sets AFTER
		`.new()` has run and this has been called for the first time. ]]
	local scale = self.PageUI:FindFirstChildOfClass("UIScale")
	local pageHeight = self.PageUI.AbsoluteSize.Y / math.max(if scale then scale.Scale else 1, 0.01)
	if pageHeight <= 0 then
		return -- not laid out yet; the AbsoluteSize signal brings us back
	end

	local rowPx = math.max(1, math.round(self._rowRatio * pageHeight))
	local padPx = math.max(0, math.round(self._padRatio * pageHeight))

	self._layout.Padding = UDim.new(0, padPx)
	for _, row in self._rows do
		row.frame.Size = UDim2.new(row.frame.Size.X.Scale, 0, 0, rowPx)
	end

	local count = #self._rows
	self.Slots.CanvasSize = UDim2.fromOffset(0, count * rowPx + math.max(count - 1, 0) * padPx)
end

-- === Drawing ================================================================

--[[ Draw every row from the one thing that decides it: the answer its own controller is holding.

	`animate` is false exactly once per open, from `StartOpenThread`: a control has to be sitting on
	the answer before the panel scales up, not sliding onto it from wherever it was left. Everywhere
	else it is true, because everywhere else something has just moved. ]]
function Page:_paint(animate: boolean?)
	for _, row in self._rows do
		if row.kind == "toggle" then
			self:_paintToggle(row, animate)
		else
			self:_paintSlider(row, animate)
		end
	end
end

function Page:_paintToggle(row, animate: boolean?)
	local count = #row.options
	local chosen = SettingsRows.indexOf(row.spec, row.current())

	for index, caption in row.captions do
		caption.Visible = index == chosen
	end

	--- One answer has nowhere to slide to and sits in the middle rather than at the low end, which
	--- would read as an off switch.
	local alpha = if count > 1 then (chosen - 1) / (count - 1) else 0.5
	local x = if count > 1 then self._knobLow + (self._knobHigh - self._knobLow) * alpha else 0.5
	self:_moveKnob(row, x, if animate then SLIDE_TIME else 0)
end

function Page:_paintSlider(row, animate: boolean?)
	local value = AudioConfig.clamp(row.current(), 0)

	if row.readout then
		row.readout.Text = AudioConfig.format(value)
	end

	--[[ The knob's travel is inset by half its own width at each end, so 0% and 100% put it flush
		inside the track rather than half outside it. The VALUE still runs the full width of the
		track; only the picture is inset. ]]
	local half = row.knob.Size.X.Scale / 2
	self:_moveKnob(row, half + value * (1 - 2 * half), if animate then SETTLE_TIME else 0)
end

--- Put a control's knob at `x` (a fraction of its container), tweening if there is time to.
function Page:_moveKnob(row, x: number, time: number)
	local position = UDim2.new(x, 0, row.knob.Position.Y.Scale, row.knob.Position.Y.Offset)

	if row.tween then
		row.tween:Cancel()
		row.tween = nil
	end

	if time <= 0 then
		row.knob.Position = position
		return
	end

	local tween = TweenService:Create(
		row.knob,
		TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = position }
	)
	row.tween = tween
	tween:Play()
end

-- === Answers ================================================================

--[[ Step a toggle to its next answer, wrapping.

	APPLIED THROUGH THE CONTROLLER AND NOT HERE, and the repaint comes back round through the state
	event rather than being done on the way out. Header note 3. ]]
function Page:_step(row)
	local nextOption = SettingsRows.nextOption(row.spec, row.current())
	if not nextOption then
		return
	end

	if not row.choose(nextOption.Key) then
		warn(string.format("Pages.Settings: the controller behind %q is not up; the press did nothing.", row.title))
	end
end

--[[ Set a slider, live.

	`commit` IS WHAT REACHES THE SERVER, and it is false for every frame of a drag and true when the
	finger comes off. A drag is one decision made over half a second, not thirty of them, and firing
	a remote per frame of it would be the noisiest thing this UI does. The level itself is applied on
	every frame either way, because that is what makes a volume slider feel like a volume slider. ]]
function Page:_setSlider(row, value: number, commit: boolean): number
	local level = AudioConfig.clamp(value, 0)
	row.set(level, commit)
	--- Painted here rather than waiting for the state event, because a controller that refuses (or
	--- is not up) still has to leave the knob somewhere sensible, and a drag repaints itself.
	self:_paintSlider(row, false)
	return level
end

--- Where a press at screen-x `x` lands on `row`'s track, as a 0 to 1.
function Page:_valueAt(row, x: number): number
	local width = row.track.AbsoluteSize.X
	if width <= 0 then
		return 0
	end
	--- `MainUI.IgnoreGuiInset` is true, so `AbsolutePosition` and an InputObject's position are in
	--- the same space and there is no topbar inset to subtract.
	return math.clamp((x - row.track.AbsolutePosition.X) / width, 0, 1)
end

--[[ A press on a slider: jump to it, then follow the pointer until it lifts.

	ONE DRAG AT A TIME across the whole screen (`self._drag`), because two fingers on two sliders is
	not a thing anybody is doing and holding one is what lets the move and release wires be a single
	pair rather than a pair per row. ]]
function Page:_beginDrag(row, input: InputObject)
	self:_endDrag()

	local drag = { row = row, value = self:_setSlider(row, self:_valueAt(row, input.Position.X), false) }

	drag.moved = UserInputService.InputChanged:Connect(function(moving)
		if
			moving.UserInputType == Enum.UserInputType.MouseMovement
			or moving.UserInputType == Enum.UserInputType.Touch
		then
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

--- Let go. `commit` saves what the slider is sitting on; a drag interrupted by the page closing
--- does not, because nothing about it was a decision.
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
	ContextActionService:BindActionAtPriority(
		PAD_ACTION,
		function(_action, state, input)
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			local step = if input.KeyCode == Enum.KeyCode.DPadLeft then -PAD_STEP else PAD_STEP
			self:_setSlider(row, AudioConfig.clamp(row.current(), 0) + step, true)
			return Enum.ContextActionResult.Sink
		end,
		false,
		PAD_PRIORITY,
		Enum.KeyCode.DPadLeft,
		Enum.KeyCode.DPadRight
	)
end

function Page:_unbindPad(_row)
	ContextActionService:UnbindAction(PAD_ACTION)
end

-- === Listening ==============================================================

--[[ A setting moving, however it moved: this screen, the server's saved answer landing while the
	screen happens to be open, or the H key toggling the interface from underneath it.

	EVERY EVENT REPAINTS EVERY ROW rather than only its own. A repaint is four function calls and a
	handful of properties, so telling them apart would cost more code than it saves work, and it
	would be a second place that has to learn about a fifth setting. ]]
function Page:_watchState()
	for _, event in SettingsRows.StateEvents do
		Dispatcher:Subscribe(event, function()
			if self.PageUI.Visible then
				self:_paint(true)
			end
		end)
	end
end

--[[ `UIController`'s hook for "the page is opening", called before its scale tween and without this
	page having to own that tween. Every control is put on its answer WITHOUT animating, so nothing
	is caught mid-slide as the panel comes up. ]]
function Page.StartOpenThread(self)
	self:_paint(false)
end

--- ...and its hook for "the page is closing". A drag that never got its release (the X pressed with
--- a finger still down, a race starting) is dropped rather than left holding two connections.
function Page.StartCloseThread(self)
	self:_endDrag()
	self:_unbindPad()
end

return Page
