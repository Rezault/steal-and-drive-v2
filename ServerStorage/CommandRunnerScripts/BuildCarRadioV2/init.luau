--[[
	BuildCarRadioV2: Command Runner command

	Builds `StarterGui.MainUIV2.Screens.CarRadio`, the car radio panel's template, out of the Cartoony
	Kit's `SettingsUI`. Phase 4 of `docs/NewUI-Migration-Plan.md`; the running record is
	`docs/NewUI-Migration-Notes.md`.

	Run `BuildMainUIV2` first: this fills in a shelf that already exists rather than creating one.
	`Screens.CarRadio` is destroyed and made again on every run, and nothing else on the shelf is
	touched, so it is safe beside the other Phase 4 commands and safe to re-run.

	=== A TEMPLATE ON THE SHELF, NOT A PAGE ===================================================

	Nothing draws this from `MainUIV2`. `RadioPanelController` clones it into its own `CarRadio`
	ScreenGui at `DisplayOrder` 996, over the driving HUD, because the radio is opened from the topbar
	and the topbar is what survives a race. That controller's header has why it is not a page.

	=== A RADIO IS A SETTINGS LIST ============================================================

	The shipping panel is a 2x2 of station pills, a paste box with PLAY beside it, and OFF and MUSIC
	on a bottom row. Every one of those is a row the kit already draws on `SettingsUI`: a name on
	the left and one control on the right.

	    NoteTemplate      one line of the kit's outlined type, no card. What is playing, and the
	                      screen's answer line.
	    StationTemplate   `BtnTemplate` plus a `Genre` beside the name. Green Play, or the grey face
	                      reading On air for the station that is.
	    InputTemplate     `BtnTemplate` with its name swapped for CodesUI's input box (`Field`).
	    RadioTemplate     `BtnTemplate` plus an `OffBtn`: pink Off, the green price, or the grey face
	                      for Off-when-already-off and Checking.
	    ToggleTemplate    the kit's switch, kept as drawn. Music.

	=== WHAT IS BORROWED ======================================================================

	  • `OffBtn` is PromptUI's `DeclineBtn`, the pink "No Way!". Pink is the kit's stop colour (the
	    close X wears it too), and a green OFF or a grey one that works would each say the wrong
	    thing. Matched to `OnBtn`'s shape so the three faces are one pill in three states.
	  • `Field` is CodesUI's `CTAs.Input`, the white box with a `TextBox` in it, which is the one
	    text field the kit draws.

	=== THE GREY FACE CANNOT BE PRESSED =======================================================

	Settings deletes `DisabledBtn` and Teleport borrows a grey Frame for the same reason: grey is the
	kit's "not now". Here it is On air, Off with nothing playing, and Checking, and none of those is a
	press worth making. So it keeps its art and loses its `UIButton` tag, `Selectable` and
	`Interactable`, and nothing is under the cursor or the gamepad highlight. The tag has to go
	rather than `Selectable` alone: `Components/Button` forces `Selectable` back on for a tagged
	button (see the Settings gotchas in the notes).

	=== THE PANEL IS TALLER THAN THE KIT'S ====================================================

	The kit's list shows six rows, and this screen has nine: two notes, four stations, the paste box,
	the radio and the music. A radio that scrolls hides its OFF switch and its answer line below the
	fold, which are the two things on it a player must not have to look for.

	So the panel is stretched, and the stretch is COMPUTED rather than typed: the rows below are
	written as fractions of the kit's own list window, their sum says how many kit windows the list
	needs, and the panel grows by exactly that. Header and margins keep the kit's pixels, the list
	takes the extra, and every row, gap and padding is re-expressed against the new window so it
	keeps its pixel height too. The rows are drawn a little shorter than the kit's (0.128 against
	0.137), which is what holds the panel near three quarters of the screen rather than nine tenths.

	A fifth station costs nothing but a scroll: `KitPage` computes the canvas from the rows it
	stamps. Add one to `STATIONS` and re-run, and it fits again.

	=== WHAT IS REMOVED =======================================================================

	`SliderTemplate`, the spare copies of each row, and the kit's `Padding` spacer row, folded into
	the list's bottom padding (the same margin under the last row without the layout gap a spacer
	row brings with it; Teleport does the same).
]]

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local SHELF_NAME = "Screens"
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage
local BUTTON_TAG = "UIButton" -- Components/Button

local SCREEN = "CarRadio" -- RadioPanelController's ScreenGui, and the template's name on the shelf
local KIT_FRAME = "SettingsUI"
local OFF_SOURCE = { "PromptUI", "Main", "Btns", "DeclineBtn" }
local FIELD_SOURCE = { "CodesUI", "Main", "CTAs", "Input" }

--- The kit's row names, and the ones this command makes. Every one of ours is a path in
--- `RadioPanelController._buildKit`.
local KIT_BUTTON_ROW = "BtnTemplate"
local KIT_SWITCH_ROW = "ToggleTemplate"
local KIT_SPACER = "Padding"
local NOTE_ROW = "NoteTemplate"
local STATION_ROW = "StationTemplate"
local INPUT_ROW = "InputTemplate"
local RADIO_ROW = "RadioTemplate"

--[[ How many of each row the controller stamps, which is what the panel is stretched to fit.
	Typed rather than read: a Command Runner module reads the configs the plugin VM has cached, and
	that cache does not notice a Rojo sync. ]]
local STATIONS = 4 -- #RadioConfig.Stations
local MUSIC_ROW = true -- MusicConfig.Enabled
local NOTES = 2 -- what is playing, and the answer line

--[[ Row heights and the gap between rows, as fractions of the KIT'S list window (the numbers the
	artist's rows are drawn in: a row is 0.137, a gap 0.032). See the header for why the rows are
	a little shorter than that. ]]
local ROW = 0.128
local NOTE = 0.07
local GAP = 0.028

--- Canvas rounding: `KitPage` rounds every row to whole pixels, and a list that needs two more
--- than its window scrolls by two. One percent of spare window is invisible and ends that.
local FIT_SLACK = 0.01

--[[ The station row's two labels, as a left edge and a width in the row's own scale. The kit's
	`Title` runs 0.03 to 0.53 and its `Btns` start at 0.69; the name keeps the left edge, the genre
	takes the run up to the button, right aligned against it, and is drawn at a smaller height than
	the name so the two read as a name and its note. ]]
local STATION_TITLE_LEFT, STATION_TITLE_WIDTH = 0.03, 0.43
local GENRE_LEFT, GENRE_WIDTH = 0.47, 0.2
local GENRE_HEIGHT = 0.42

--- The paste box on the input row: the name's left edge to the gutter before the button, and the
--- button's own height so the two stand the same.
local FIELD_LEFT, FIELD_WIDTH = 0.03, 0.64

--- The kit's own placeholders and ours, so a freshly built template reads as the finished screen
--- in the Explorer. Every one is overwritten when the controller stamps a row.
local TITLE_TEXT = "Car Radio"
local NOTE_PLACEHOLDER = "Now playing: Asphalt Phantoms"
local STATION_PLACEHOLDER = "Drift FM"
local GENRE_PLACEHOLDER = "Phonk"
local PLAY_TEXT = "Play"
local ON_AIR_TEXT = "On air"
local RADIO_PLACEHOLDER = "Radio"
local OFF_TEXT = "Off"
local PRICE_PLACEHOLDER = utf8.char(0xE002) .. "149" -- the kit's own Robux mark, as the Shop prints it
local MUSIC_PLACEHOLDER = "Music"
local FIELD_PLACEHOLDER = "Paste an audio ID" -- RadioConfig.Custom.Placeholder

--- The kit template, or nil and a sentence saying which step of the path was missing.
local function findTemplate(): (Instance?, string?)
	local node: Instance = ServerStorage
	for _, step in TEMPLATE_PATH do
		local child = node:FindFirstChild(step)
		if not child then
			return nil, string.format("%s has no child `%s`.", node:GetFullName(), step)
		end
		node = child
	end
	local screen = node:FindFirstChildWhichIsA("ScreenGui")
	if not screen then
		return nil, string.format("%s holds no ScreenGui.", node:GetFullName())
	end
	local container = screen:FindFirstChild("Container")
	if not container then
		return nil, string.format("%s has no `Container` of frames.", screen:GetFullName())
	end
	return container, nil
end

--- Walk a path of names down from `root`, or nil.
local function walk(root: Instance, path: { string }): Instance?
	local node: Instance? = root
	for _, step in path do
		node = node and node:FindFirstChild(step)
	end
	return node
end

--- Put a GuiObject at a left edge and a width, in its parent's scale, keeping its anchor and its Y.
local function span(gui: GuiObject, left: number, width: number)
	gui.Size = UDim2.new(width, gui.Size.X.Offset, gui.Size.Y.Scale, gui.Size.Y.Offset)
	gui.Position = UDim2.new(left + gui.AnchorPoint.X * width, gui.Position.X.Offset, gui.Position.Y.Scale, gui.Position.Y.Offset)
end

--- A kit button's caption, whichever button it is.
local function setCaption(button: Instance?, text: string)
	local title = button and button:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = text
	end
end

--- The UIStrokes that draw a kit button's rim: inside its `Container` on most, on the button itself
--- on a few.
local function rimStrokes(button: Instance): { UIStroke }
	local strokes = {}
	local holder = button:FindFirstChild("Container") or button
	for _, child in holder:GetChildren() do
		if child:IsA("UIStroke") then
			table.insert(strokes, child)
		end
	end
	return strokes
end

--[[ Make a borrowed face the same pill as the one it sits beside: box, caption box and size cap,
	slash, rim weight and corner, all read off `reference`. PromptUI draws its buttons for a wider
	row, and without this the pink Off reads as a different button from the green one it replaces. ]]
local function matchFace(face: GuiObject, reference: GuiObject)
	face.AnchorPoint = reference.AnchorPoint
	face.Position = reference.Position
	face.Size = reference.Size
	face.ZIndex = reference.ZIndex

	local faceTitle = face:FindFirstChild("Title")
	local referenceTitle = reference:FindFirstChild("Title")
	if faceTitle and faceTitle:IsA("GuiObject") and referenceTitle and referenceTitle:IsA("GuiObject") then
		faceTitle.AnchorPoint = referenceTitle.AnchorPoint
		faceTitle.Position = referenceTitle.Position
		faceTitle.Size = referenceTitle.Size
		local faceCap = faceTitle:FindFirstChildOfClass("UITextSizeConstraint")
		local referenceCap = referenceTitle:FindFirstChildOfClass("UITextSizeConstraint")
		if faceCap and referenceCap then
			faceCap.MaxTextSize = referenceCap.MaxTextSize
		end
	end

	local faceSlash = face:FindFirstChild("BG") and face.BG:FindFirstChild("Slash")
	local referenceSlash = reference:FindFirstChild("BG") and reference.BG:FindFirstChild("Slash")
	if faceSlash and faceSlash:IsA("GuiObject") and referenceSlash and referenceSlash:IsA("GuiObject") then
		faceSlash.Position = referenceSlash.Position
		faceSlash.Size = referenceSlash.Size
	end

	local thickness = rimStrokes(reference)[1]
	if thickness then
		for _, stroke in rimStrokes(face) do
			stroke.Thickness = thickness.Thickness
		end
	end

	local corner = face:FindFirstChildOfClass("UICorner")
	local referenceCorner = reference:FindFirstChildOfClass("UICorner")
	if corner and referenceCorner then
		corner.CornerRadius = referenceCorner.CornerRadius
	end
end

--- The grey face, kept as art and taken out of every kind of input. See the header.
local function inert(button: GuiObject)
	if CollectionService:HasTag(button, BUTTON_TAG) then
		CollectionService:RemoveTag(button, BUTTON_TAG)
	end
	button.Selectable = false
	button.Interactable = false
	if button:IsA("GuiButton") then
		button.AutoButtonColor = false
	end
end

--- Re-express a row's height from kit-window units in the stretched window's.
local function setRowHeight(row: GuiObject, kitFraction: number, rescale: number)
	row.Size = UDim2.new(row.Size.X.Scale, row.Size.X.Offset, kitFraction * rescale, 0)
end

return {
	Description = "Build StarterGui.MainUIV2.Screens.CarRadio (the car radio panel's template) from the Cartoony Kit's SettingsUI: note, station, input, radio and music rows, a pink Off borrowed from PromptUI, CodesUI's input box, and the panel stretched to fit every row. Rebuilds the template every run.",
	Tags = { "UI", "NewUI" },
	AutoRecordChanges = true,

	Arguments = {} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		local screen = StarterGui:FindFirstChild(SCREEN_NAME)
		local shelf = screen and screen:FindFirstChild(SHELF_NAME)
		if not (shelf and shelf:IsA("GuiObject")) then
			out:error(string.format("No StarterGui.%s.%s. Run BuildMainUIV2 first.", SCREEN_NAME, SHELF_NAME))
			return
		end

		local container, why = findTemplate()
		if not container then
			out:error(string.format("The kit is not where it should be: %s", why))
			return
		end

		local kitFrame = container:FindFirstChild(KIT_FRAME)
		local offSource = walk(container, OFF_SOURCE)
		local fieldSource = walk(container, FIELD_SOURCE)
		if not (kitFrame and offSource and offSource:IsA("GuiObject") and fieldSource and fieldSource:IsA("GuiObject")) then
			out:error(
				string.format(
					"The kit is missing `%s`, `%s` or `%s`.",
					KIT_FRAME,
					table.concat(OFF_SOURCE, "."),
					table.concat(FIELD_SOURCE, ".")
				)
			)
			return
		end

		--- Read before anything is destroyed, so a kit that has changed shape stops the build with
		--- the template it already had still standing.
		local kitMain = kitFrame:FindFirstChild("Main")
		local kitList = kitMain and kitMain:FindFirstChildOfClass("ScrollingFrame")
		local kitRow = kitList and kitList:FindFirstChild(KIT_BUTTON_ROW)
		local kitSwitch = kitList and kitList:FindFirstChild(KIT_SWITCH_ROW)
		if not (kitRow and kitSwitch and kitFrame:FindFirstChild("Header") and kitFrame:FindFirstChildOfClass("UIAspectRatioConstraint")) then
			out:error(string.format("The kit's %s no longer has `Header`, its aspect, `Main.ScrollingFrame`, `%s` and `%s`.", KIT_FRAME, KIT_BUTTON_ROW, KIT_SWITCH_ROW))
			return
		end

		local existing = shelf:FindFirstChild(SCREEN)
		if existing then
			existing:Destroy()
		end

		local panel = kitFrame:Clone() :: GuiObject
		panel.Name = SCREEN
		--- Visible on the shelf, which is hidden itself: tick the shelf to see the template.
		--- `KitPage.bind` hides the runtime copy.
		panel.Visible = true

		local header = panel:FindFirstChild("Header") :: GuiObject
		local main = panel:FindFirstChild("Main") :: GuiObject
		local list = main:FindFirstChildOfClass("ScrollingFrame") :: ScrollingFrame

		local headerTitle = header:FindFirstChild("Title")
		if headerTitle and headerTitle:IsA("TextLabel") then
			headerTitle.Text = TITLE_TEXT
		end

		-- === The rows ===========================================================
		--- One of each kit row to cut ours from. Everything else in the list goes.
		local button, switch = nil, nil
		for _, child in list:GetChildren() do
			if not child:IsA("GuiObject") then
				continue
			end
			if child.Name == KIT_BUTTON_ROW and not button then
				button = child
			elseif child.Name == KIT_SWITCH_ROW and not switch then
				switch = child
			else
				child:Destroy() -- sliders, spare rows and the spacer
			end
		end
		button = button :: GuiObject
		switch = switch :: GuiObject

		--- Every kit row starts with both faces on; the controller shows one.
		local function faces(row: Instance): (GuiObject, GuiObject)
			local btns = row:FindFirstChild("Btns") :: Instance
			return btns:FindFirstChild("OnBtn") :: GuiObject, btns:FindFirstChild("DisabledBtn") :: GuiObject
		end

		-- A station: the name, the genre beside it, Play or On air.
		local station = button:Clone()
		station.Name = STATION_ROW
		local stationTitle = station:FindFirstChild("Title") :: TextLabel
		stationTitle.Text = STATION_PLACEHOLDER
		span(stationTitle, STATION_TITLE_LEFT, STATION_TITLE_WIDTH)
		local genre = stationTitle:Clone()
		genre.Name = "Genre"
		genre.Text = GENRE_PLACEHOLDER
		genre.TextXAlignment = Enum.TextXAlignment.Right
		genre.Size = UDim2.new(genre.Size.X.Scale, 0, GENRE_HEIGHT, 0)
		genre.Parent = station
		span(genre, GENRE_LEFT, GENRE_WIDTH)
		do
			local play, onAir = faces(station)
			setCaption(play, PLAY_TEXT)
			setCaption(onAir, ON_AIR_TEXT)
			play.Visible = true
			onAir.Visible = false
			inert(onAir)
		end
		station.Parent = list

		-- The paste box: CodesUI's field where the name was, Play beside it.
		local input = button:Clone()
		input.Name = INPUT_ROW
		local inputTitle = input:FindFirstChild("Title") :: GuiObject
		local field = (fieldSource :: GuiObject):Clone()
		field.Name = "Field"
		field.AnchorPoint = Vector2.new(0.5, 0.5)
		field.Position = UDim2.fromScale(0.5, 0.5)
		field.ZIndex = inputTitle.ZIndex
		do
			local btns = input:FindFirstChild("Btns") :: GuiObject
			field.Size = UDim2.new(FIELD_WIDTH, 0, btns.Size.Y.Scale, 0)
		end
		span(field, FIELD_LEFT, FIELD_WIDTH)
		local box = field:FindFirstChildOfClass("TextBox")
		if box then
			box.Text = ""
			box.PlaceholderText = FIELD_PLACEHOLDER
			box.ClearTextOnFocus = true
		else
			out:warn("CodesUI's input has no TextBox; the paste box will not take text.")
		end
		inputTitle:Destroy()
		field.Parent = input
		do
			local play, grey = faces(input)
			setCaption(play, PLAY_TEXT)
			setCaption(grey, PLAY_TEXT)
			play.Visible = true
			grey.Visible = false
			inert(grey)
		end
		input.Parent = list

		-- The radio as a whole: pink Off, the green price, or grey.
		local radio = button:Clone()
		radio.Name = RADIO_ROW
		local radioTitle = radio:FindFirstChild("Title") :: TextLabel
		radioTitle.Text = RADIO_PLACEHOLDER
		do
			local price, grey = faces(radio)
			setCaption(price, PRICE_PLACEHOLDER)
			setCaption(grey, OFF_TEXT)
			price.Visible = false
			grey.Visible = false
			inert(grey)

			local off = (offSource :: GuiObject):Clone()
			off.Name = "OffBtn"
			matchFace(off, price)
			setCaption(off, OFF_TEXT)
			off.Visible = true
			off.Parent = price.Parent
			if not CollectionService:HasTag(off, BUTTON_TAG) then
				out:warn("PromptUI's DeclineBtn is not tagged UIButton. Re-run PrepKitTemplate.")
			end
		end
		radio.Parent = list

		-- The note: one line of the row's own outlined type, with no card behind it.
		local note = Instance.new("Frame")
		note.Name = NOTE_ROW
		note.BackgroundTransparency = 1
		note.BorderSizePixel = 0
		note.Size = UDim2.new(button.Size.X.Scale, 0, NOTE, 0)
		local noteTitle = (button:FindFirstChild("Title") :: TextLabel):Clone()
		noteTitle.AnchorPoint = Vector2.new(0.5, 0.5)
		noteTitle.Position = UDim2.fromScale(0.5, 0.5)
		noteTitle.Size = UDim2.fromScale(1, 0.9)
		noteTitle.TextXAlignment = Enum.TextXAlignment.Center
		noteTitle.Text = NOTE_PLACEHOLDER
		noteTitle.Parent = note
		note.Parent = list

		-- Music: the kit's switch, as drawn, under its kit name.
		local switchTitle = switch:FindFirstChild("Title")
		if switchTitle and switchTitle:IsA("TextLabel") then
			switchTitle.Text = MUSIC_PLACEHOLDER
		end

		button:Destroy()

		-- === The stretch ========================================================
		local padding = list:FindFirstChildOfClass("UIPadding")
		local layout = list:FindFirstChildOfClass("UIListLayout")
		local padTop = if padding then padding.PaddingTop.Scale else 0

		local rows = NOTES + STATIONS + 2 + (if MUSIC_ROW then 1 else 0)
		--- The list's content in kit windows, padding top and bottom included. See the header.
		local content = 2 * padTop + NOTES * NOTE + (rows - NOTES) * ROW + (rows - 1) * GAP + FIT_SLACK
		local rescale = 1 / content

		--[[ The kit's margins in panel heights: above `Main` (the header lives there) and below it.
			Both keep their pixels, so both are divided by the stretch, and `Main` is everything
			between. ]]
		local mainTop = main.Position.Y.Scale - main.AnchorPoint.Y * main.Size.Y.Scale
		local mainBottom = 1 - mainTop - main.Size.Y.Scale
		local stretch = content * main.Size.Y.Scale + mainTop + mainBottom

		local aspect = panel:FindFirstChildOfClass("UIAspectRatioConstraint") :: UIAspectRatioConstraint
		aspect.AspectRatio /= stretch
		panel.Size = UDim2.new(panel.Size.X.Scale, panel.Size.X.Offset, panel.Size.Y.Scale * stretch, panel.Size.Y.Offset)

		header.Position = UDim2.new(header.Position.X.Scale, header.Position.X.Offset, header.Position.Y.Scale / stretch, 0)
		header.Size = UDim2.new(header.Size.X.Scale, header.Size.X.Offset, header.Size.Y.Scale / stretch, 0)

		local mainHeight = 1 - (mainTop + mainBottom) / stretch
		main.Size = UDim2.new(main.Size.X.Scale, main.Size.X.Offset, mainHeight, 0)
		main.Position = UDim2.new(main.Position.X.Scale, main.Position.X.Offset, mainTop / stretch + main.AnchorPoint.Y * mainHeight, 0)

		--- The checker pattern is drawn square; a taller box would draw it tall.
		local checkers = panel:FindFirstChild("BG") and panel.BG:FindFirstChild("CheckersBG")
		if checkers and checkers:IsA("GuiObject") then
			checkers.Size = UDim2.new(checkers.Size.X.Scale, 0, checkers.Size.Y.Scale / stretch, 0)
		end

		for _, row in list:GetChildren() do
			if row:IsA("GuiObject") then
				setRowHeight(row, if row.Name == NOTE_ROW then NOTE else ROW, rescale)
			end
		end
		if layout then
			layout.Padding = UDim.new(GAP * rescale, 0)
		end
		if padding then
			padding.PaddingTop = UDim.new(padTop * rescale, 0)
			padding.PaddingBottom = padding.PaddingTop
		end

		panel.Parent = shelf

		out:print(string.format("Built %s.%s.%s from the kit's %s.", SCREEN_NAME, SHELF_NAME, SCREEN, KIT_FRAME))
		out:print(
			string.format(
				"Rows: %s, %s, %s, %s, %s. Fitted for %d stations%s: the panel is %.3fx the kit's height, rows %.3f of the new window.",
				NOTE_ROW,
				STATION_ROW,
				INPUT_ROW,
				RADIO_ROW,
				KIT_SWITCH_ROW,
				STATIONS,
				if MUSIC_ROW then " and a music row" else "",
				stretch,
				ROW * rescale
			)
		)

		pcall(function()
			props:SetSelection({ panel })
		end)
	end,
} :: Types.ScriptModule
