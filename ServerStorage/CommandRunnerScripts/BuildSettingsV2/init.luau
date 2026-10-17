--[[
	BuildSettingsV2: Command Runner command

	Builds `StarterGui.MainUIV2.Pages.Settings` out of the Cartoony Kit's `SettingsUI`. Phase 3 of
	`docs/NewUI-Migration-Plan.md`; the running record is `docs/NewUI-Migration-Notes.md`.

	Run `BuildMainUIV2` first: this fills in a screen that already exists rather than creating one.
	`Pages.Settings` is destroyed and made again on every run, and nothing else under `Pages` is
	touched, so it is safe beside the other Phase 3 commands and safe to re-run.

	=== THE KIT SHIPS THREE ROW TEMPLATES AND WE USE ALL THREE ================================

	`ToggleTemplate` is a switch: a blue track with a green `On` swatch at the right and a red `Off`
	swatch at the left, one visible at a time. `SliderTemplate` is a track with a knob.
	`BtnTemplate` is a captioned button with a greyed twin under it.

	`Modules/SettingsRows` says a setting is either a SLIDER or a TOGGLE, and a toggle holds any
	number of answers. So the page picks by how many answers there are:

	  • TWO answers go on `ToggleTemplate`, because that is what a switch is. The swatches carry no
	    caption (the artist set `TextTransparency = 1` on both, and at the size they are drawn a word
	    would not fit), so the COLOUR and the SIDE are the whole of the answer. That puts one
	    requirement on the config, and it is written here because nothing else states it: **the "off"
	    answer must be listed first.** `InterfaceConfig` lists `shown` then `hidden`, which is right.
	  • THREE OR MORE go on `BtnTemplate`, whose `Title` prints the answer in the answer's own words
	    and which a press steps to the next of. That is the shipping screen's model exactly, and it is
	    what Time of day needs when `DayNightConfig.Enabled` comes back on.

	One rule, no special cases, and each control is used for the thing it was drawn to be.

	=== WHAT THIS COMMAND ACTUALLY CHANGES ===================================================

	Two things, and both are for the percentage readout beside a volume slider:

	  • THE ROW GAINS A `Readout`, cloned from its own `Title` so it is the artist's type rather than
	    a label built in code. The kit drew no readout because the kit's sliders are nameless; ours
	    say 40% and the shipping screen has said so since the sliders landed. Losing it in a re-skin
	    would be the migration quietly removing information.
	  • THE TRACK NARROWS to make room, from 0.38 of the row to 0.29. That is the cheaper of the two
	    ways to fit it: the alternative is shrinking the slider rows' `Title`, which would leave two
	    rows' names set smaller than the rest of the list. A slider track is decorative width and
	    nobody reads it, where a column of names that do not line up is the first thing you see.

	The knob is also renamed `Knob`. The kit calls it `Toggle`, which is the name of the TRACK on the
	row template next door, and two different things called `Toggle` on one screen is a path nobody
	can read.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)
local KitGrowth = require(ReplicatedStorage.shared.Modules.KitGrowth)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage

local PAGE_NAME = "Settings" -- SettingsConfig.PageName
local KIT_FRAME = "SettingsUI"

--- The slider row, its track, and what the knob inside the track is renamed to. See the header.
local SLIDER_ROW = "SliderTemplate"
local TRACK_NAME = "Slider"
local KIT_KNOB_NAME = "Toggle"
local KNOB_NAME = "Knob"

--- The percentage label added beside a track, and the row child it is cloned from.
local READOUT_NAME = "Readout"
local TITLE_NAME = "Title"

--[[ Where the readout and the narrowed track sit, in the row's own scale, as a left edge and a width.

	MEASURED OFF THE ARTIST'S ROW, not invented: their `Title` runs 0.030 to 0.530 and their `Slider`
	runs 0.600 to 0.980. The readout takes the empty run between the two and the track gives up its
	left end to make that run wide enough to hold "100%". Both keep the artist's right edge at 0.980
	and the gutters either side of the readout are the same 0.02 the row already had. ]]
local READOUT_LEFT, READOUT_WIDTH = 0.545, 0.12
local TRACK_LEFT, TRACK_WIDTH = 0.69, 0.29

--- The kit's own placeholder, so a freshly built row reads as a row before anything binds to it.
local READOUT_PLACEHOLDER = "100%"

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

--- Put a GuiObject at a left edge and a width, in its parent's scale, keeping its anchor and its Y.
local function span(gui: GuiObject, left: number, width: number)
	gui.Size = UDim2.new(width, gui.Size.X.Offset, gui.Size.Y.Scale, gui.Size.Y.Offset)
	gui.Position = UDim2.new(
		left + gui.AnchorPoint.X * width,
		gui.Position.X.Offset,
		gui.Position.Y.Scale,
		gui.Position.Y.Offset
	)
end

return {
	Description = "Build StarterGui.MainUIV2.Pages.Settings from the Cartoony Kit's SettingsUI: three row templates kept as drawn, plus a percentage Readout beside a narrowed slider track. Rebuilds the page every run.",
	Tags = { "UI", "NewUI" },
	AutoRecordChanges = true,

	Arguments = {} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		local screen = StarterGui:FindFirstChild(SCREEN_NAME)
		local pages = screen and screen:FindFirstChild("Pages")
		if not (pages and pages:IsA("GuiObject")) then
			out:error(string.format("No StarterGui.%s.Pages. Run BuildMainUIV2 first.", SCREEN_NAME))
			return
		end

		local container, why = findTemplate()
		if not container then
			out:error(string.format("The kit is not where it should be: %s", why))
			return
		end

		local kitFrame = container:FindFirstChild(KIT_FRAME)
		if not kitFrame then
			out:error(string.format("%s has no `%s` to build from.", container:GetFullName(), KIT_FRAME))
			return
		end

		local existing = pages:FindFirstChild(PAGE_NAME)
		if existing then
			existing:Destroy()
		end

		local page = kitFrame:Clone()
		page.Name = PAGE_NAME

		local list = page:FindFirstChild("Main")
		list = list and list:FindFirstChildOfClass("ScrollingFrame")
		if not list then
			out:error(string.format("The kit's %s has no `Main.ScrollingFrame`; there is no list to fill.", KIT_FRAME))
			page:Destroy()
			return
		end

		--[[ Every drawn copy of the slider row, not just the first. `KitPage` keeps the first of each
			name as its template and destroys the rest, but WHICH copy it keeps is `GetChildren` order,
			so dressing only one would be a coin toss over whether the readout survived. ]]
		local dressed = 0
		for _, row in list:GetChildren() do
			if row.Name == SLIDER_ROW and row:IsA("GuiObject") then
				local track = row:FindFirstChild(TRACK_NAME)
				local title = row:FindFirstChild(TITLE_NAME)
				if not (track and track:IsA("GuiObject") and title and title:IsA("TextLabel")) then
					out:warn(string.format("A `%s` has no `%s` and `%s`; it gets no readout.", SLIDER_ROW, TRACK_NAME, TITLE_NAME))
					continue
				end

				local knob = track:FindFirstChild(KIT_KNOB_NAME)
				if knob then
					knob.Name = KNOB_NAME
				end

				span(track :: GuiObject, TRACK_LEFT, TRACK_WIDTH)

				local readout = title:Clone()
				readout.Name = READOUT_NAME
				readout.Text = READOUT_PLACEHOLDER
				--- Right against the track it belongs to, where a left-aligned one would drift away
				--- from it as the number got shorter.
				readout.TextXAlignment = Enum.TextXAlignment.Right
				--- `TextScaled` stays on, and `TextWrapped` is left alone because writing it false switches
				--- `TextScaled` off (the Phase 5 device pass found the readout stuck at 14px, spilling out of
				--- its box on a phone). "100%" has no space, so there is nothing for a wrap to break on.
				readout.TextScaled = true
				readout.Parent = row
				span(readout, READOUT_LEFT, READOUT_WIDTH)

				dressed += 1
			end
		end

		if dressed == 0 then
			out:warn(string.format("No `%s` rows found; the volume sliders will have no percentage.", SLIDER_ROW))
		end

		--- Bigger than the kit, text caps included. See `Modules/KitGrowth`.
		KitGrowth.apply(page, KitGrowth.Pages)
		page.Parent = pages

		local kinds = {}
		for _, row in list:GetChildren() do
			if row:IsA("GuiObject") and not kinds[row.Name] then
				kinds[row.Name] = true
			end
		end
		local names = {}
		for name in kinds do
			table.insert(names, name)
		end
		table.sort(names)

		out:print(
			string.format(
				"Built %s.Pages.%s from the kit's %s. Row templates: %s.",
				SCREEN_NAME,
				PAGE_NAME,
				KIT_FRAME,
				table.concat(names, ", ")
			)
		)
		out:print(
			string.format(
				"%d slider row(s) dressed: knob renamed `%s`, track narrowed to %.2f, `%s` added beside it.",
				dressed,
				KNOB_NAME,
				TRACK_WIDTH,
				READOUT_NAME
			)
		)
		out:print("Two-answer settings go on `ToggleTemplate` (the off answer must be listed first), three or more on `BtnTemplate`. See the header.")

		pcall(function()
			props:SetSelection({ page })
		end)
	end,
} :: Types.ScriptModule
