--[[
	BuildWeatherNoticeV2: Command Runner command

	Builds `StarterGui.MainUIV2.Screens.WeatherNotice`, the weather event toast's template, out of the
	Cartoony Kit's `PromptUI`. Phase 4 of `docs/NewUI-Migration-Plan.md`; the running record is
	`docs/NewUI-Migration-Notes.md`.

	Run `BuildMainUIV2` first: this fills in a shelf that already exists rather than creating one.
	`Screens.WeatherNotice` is destroyed and made again on every run, and nothing else on the shelf is
	touched, so it is safe beside the other Phase 4 commands and safe to re-run.

	=== WHY A TOAST OF ITS OWN AND NOT THE HUD'S BOOSTS ROW ==================================

	The plan offered both. The kit's `Boosts` row is three glyphs the size of a thumbnail in the
	bottom right corner, each with a timer over it and a percentage under it: a place to keep an
	active boost ticking, not a place to announce anything. The notice says four things (what the
	sky is doing, in which world, one line of flavour, and what the cars pay) and it says them once,
	for seven seconds, to a player who is meant to act on it. Squeezed onto the row, three of the four
	would go, and the card would become a different feature: a badge that has to live for the whole
	event, follow the player between worlds and hide for a race. That may well be worth building (it
	is in the Phase 4 notes as a follow-up), but it is not this screen.

	The race was the other question, and it does not decide anything here: the notice never shows
	during a race (`WeatherController._onStarted` returns for `_racing`), so the HUD's race hide
	would neither help nor hurt.

	=== THE KIT DREW A TOAST ALREADY ==========================================================

	`PromptUI` is a header over a white card, 2.29:1, and the shipping card is a cap over a navy body
	at 2.42:1 and 34% of the screen. At 1247x651 the kit's comes out 419x183 and the shipping one
	424x175: the same box. So:

	    Header.Title   the event                           the kit's, kept
	    Header.Clock   how long is left                    the Title's own type, right aligned,
	                                                       where the close button was
	    Main.Well      the event's glyph                   drawn bare on the body; `Well` is an empty
	                                                       square that only positions it, and the
	                                                       note below is why nothing is painted in it
	    Main.World     which world                         the card's own outlined body type,
	    Main.Blurb     one line of flavour                 three single lines in place of the
	    Main.Payoff    what the cars pay, in the           kit's two-line sentence
	                   mutation's colour

	The close button and the Yes/No buttons go. The notice is not a question and nothing on it can be
	pressed, so no `UIButton` tag survives into the template.

	=== THE GLYPH SITS ON NOTHING, AND THAT IS THE CORRECTION ==================================

	It used to sit in a clone of `CodesUI.Main.XProfile.Logo`, the kit's navy square, and on this card
	that square read as a hole punched in the panel: a near black fill under a pure black rim, on a
	white body, next to type outlined in the kit's navy rather than in black. Nothing else in this UI
	is black.

	"THE GLYPHS WERE DRAWN FOR NAVY", which is what this note used to say, was true of the SHIPPING
	card and is what carried the mistake across. That card is a navy panel, so a navy well on it is
	one shade on another and the glyph is the only bright thing. The kit's card is WHITE, and the
	same well on it is the darkest thing on the screen. The well was never wrong where it came from
	either: in `CodesUI` it sits on `XProfile`, a saturated cyan-to-blue strip, and a dark inset on a
	bright strip is exactly right. Lifting it onto white is what broke it.

	SO THE LAYER GOES, and the glyph is drawn bare at the full size of the square it used to sit in.
	All six Gvesster weather badges carry their own outlines and were checked on this white body: Fog
	is the palest and still holds. That is also what the rest of this UI does, since the HUD rail's
	cells are bare art and the new UI's grid is tile-less icons. `BuildCarryNoticeV2` makes the same
	square the same way, for the same reason, and the two are meant to stay identical.

	THE SHIPPING CARD KEEPS ITS WELL (`WeatherController._buildNotice`, the flag-off path). Its panel
	really is navy, so the slot art there is doing the job it was drawn for.

	`Well` STAYS, as an empty square that only positions the glyph. It is the name both controllers
	reach through to find `Icon`, and the name is cheaper to keep than to chase.

	=== THE TYPE CEILINGS ARE THE SHIPPING CARD'S INSTRUMENT ==================================

	Every line is `TextScaled` under a `UITextSizeConstraint` named `Ceiling` with a `Fraction`
	attribute: a ceiling as a fraction of the CARD's height, rewritten in pixels by
	`WeatherController._fitNotice` whenever the card resizes. That is how the shipping card keeps four
	rows in differently-sized boxes rendering at sizes that agree, and naming them the same way means
	the one function serves both cards. The header title keeps the kit's own ceiling: it is the
	heading, and a heading the kit sized is right.

	=== WHERE IT SITS =========================================================================

	Anchored at its top centre and parked at the shipping card's shown position, a margin from the
	top edge in the kit's space (`IgnoreGuiInset` false, so 0 is already under the topbar). The
	controller slides it from above the screen to there.
]]

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local SHELF_NAME = "Screens"
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage
local BUTTON_TAG = "UIButton" -- Components/Button

local SCREEN = "WeatherNotice" -- WeatherController's ScreenGui, and the template's name on the shelf
local KIT_FRAME = "PromptUI"

--- `WeatherController`'s shown position: a fraction of the screen from the top edge.
local SHOWN_Y = 0.022 -- WeatherController NOTICE_SHOWN_Y

--- What `_fitNotice` reads. See the header.
local CEILING_NAME = "Ceiling"
local FRACTION_ATTRIBUTE = "Fraction"

--[[ The glyph's square, as a fraction of the card body's HEIGHT, and the glyph inside it as a
	fraction of that square. The margin round the square is the same on all three sides it has, which
	is what sets the text column's left edge.

	THE GLYPH FILLS THE SQUARE now that there is nothing painted behind it (see the header). At the
	0.7 this was, the art was inset to clear a rim that is no longer there, which left the glyph
	looking small and lost in the margin instead of centred in a plate. It is `Fit`, so the six
	glyphs, which are not all one aspect, each keep their own shape. ]]
local WELL_HEIGHT = 0.76
local ICON_SIZE = 1

--- What the template wears in the Explorer, overwritten per event at runtime: `UIAssets.Weather.Rain`.
local PLACEHOLDER_ICON = "rbxassetid://128452250548788"

--[[ The three body lines, as a centre and a height in the body's own scale, top to bottom, and each
	line's type ceiling as a fraction of the CARD's height. The payoff is the largest because it is
	the line the card exists to say; the world is the smallest because it is the one about where
	rather than what. The clock sits in the header at the world's weight, like the shipping card's. ]]
local LINES = {
	{ Name = "World", Y = 0.22, Height = 0.26, Fraction = 0.1, Placeholder = "IN THE DESERT" },
	{ Name = "Blurb", Y = 0.5, Height = 0.28, Fraction = 0.11, Placeholder = "Lightning is hitting the road." },
	{ Name = "Payoff", Y = 0.78, Height = 0.28, Fraction = 0.125, Placeholder = "CHARGED CARS PAY x3.5" },
}
local CLOCK_FRACTION = 0.095

--- The header: the title gives up the right of the bar to the clock.
local TITLE_WIDTH = 0.62
local CLOCK_WIDTH = 0.36
local CLOCK_HEIGHT = 0.62

--- Placeholders, so a freshly built template reads as the finished card in the Explorer.
local TITLE_PLACEHOLDER = "Thunderstorm"
local CLOCK_PLACEHOLDER = "3:30 LEFT"

--- The card height the placeholders' ceilings are worked out against, so the Explorer preview is
--- the right size before `_fitNotice` ever runs: the kit's own at 1247x651.
local PREVIEW_HEIGHT = 183

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

--- Turn a label's kit size cap into a ceiling `_fitNotice` rewrites. See the header.
local function ceiling(label: TextLabel, fraction: number)
	local cap = label:FindFirstChildOfClass("UITextSizeConstraint")
	if not cap then
		cap = Instance.new("UITextSizeConstraint")
		cap.Parent = label
	end
	cap.Name = CEILING_NAME
	cap.MinTextSize = 8
	cap.MaxTextSize = math.max(8, math.round(PREVIEW_HEIGHT * fraction))
	cap:SetAttribute(FRACTION_ATTRIBUTE, fraction)
end

return {
	Description = "Build StarterGui.MainUIV2.Screens.WeatherNotice (the weather event toast's template) from the Cartoony Kit's PromptUI: the event in the header with the clock beside it, the event glyph drawn bare on the body, and three lines for the world, the blurb and the payoff. Rebuilds the template every run.",
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
		local kitTitle = kitFrame and walk(kitFrame, { "Header", "Title" })
		local kitBody = kitFrame and walk(kitFrame, { "Main", "Title" })
		local kitAspect = kitFrame and kitFrame:FindFirstChildOfClass("UIAspectRatioConstraint")
		if
			not (
				kitFrame
				and kitTitle
				and kitTitle:IsA("TextLabel")
				and kitBody
				and kitBody:IsA("TextLabel")
				and kitAspect
			)
		then
			out:error(string.format("The kit is missing `%s` with `Header.Title`, `Main.Title` and its aspect.", KIT_FRAME))
			return
		end

		local existing = shelf:FindFirstChild(SCREEN)
		if existing then
			existing:Destroy()
		end

		local card = kitFrame:Clone() :: GuiObject
		card.Name = SCREEN
		card.Visible = true
		card.AnchorPoint = Vector2.new(0.5, 0)
		card.Position = UDim2.new(0.5, 0, SHOWN_Y, 0)

		local header = card:FindFirstChild("Header") :: GuiObject
		local main = card:FindFirstChild("Main") :: GuiObject
		local title = header:FindFirstChild("Title") :: TextLabel
		local body = main:FindFirstChild("Title") :: TextLabel

		-- === The header ========================================================
		title.Text = TITLE_PLACEHOLDER
		title.Size = UDim2.new(TITLE_WIDTH, 0, title.Size.Y.Scale, 0)

		local clock = title:Clone()
		clock.Name = "Clock"
		clock.Text = CLOCK_PLACEHOLDER
		clock.TextXAlignment = Enum.TextXAlignment.Right
		clock.AnchorPoint = Vector2.new(1, 0.5)
		clock.Position = UDim2.fromScale(1, 0.5)
		clock.Size = UDim2.fromScale(CLOCK_WIDTH, CLOCK_HEIGHT)
		ceiling(clock, CLOCK_FRACTION)
		clock.Parent = header

		local close = header:FindFirstChild("CloseBtn")
		if close then
			close:Destroy()
		end

		-- === The body ==========================================================
		--[[ The body's own shape, in pixels per pixel, so the well can be square and the margins
			equal in both directions while everything stays in scale. ]]
		local bodyAspect = kitAspect.AspectRatio * main.Size.X.Scale / main.Size.Y.Scale
		local marginY = (1 - WELL_HEIGHT) / 2
		local marginX = marginY / bodyAspect
		local wellWidth = WELL_HEIGHT / bodyAspect

		--- Ours rather than a clone of the kit's navy square, and the header says why. Nothing is
		--- painted on it: it is the box the glyph is centred in and the name the controller reaches
		--- through, and it is built rather than cloned so there is no rim to strip afterwards.
		local well = Instance.new("Frame")
		well.Name = "Well"
		well.AnchorPoint = Vector2.new(0.5, 0.5)
		well.Position = UDim2.fromScale(marginX + wellWidth / 2, 0.5)
		well.Size = UDim2.fromScale(wellWidth, WELL_HEIGHT)
		well.BackgroundTransparency = 1
		well.BorderSizePixel = 0

		local square = Instance.new("UIAspectRatioConstraint")
		square.AspectRatio = 1
		square.DominantAxis = Enum.DominantAxis.Height
		square.Parent = well

		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		--- A real badge rather than an empty box, so a freshly built template reads as the finished
		--- card in the Explorer. `WeatherController._onStarted` writes the running event's over it.
		icon.Image = PLACEHOLDER_ICON
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Size = UDim2.fromScale(ICON_SIZE, ICON_SIZE)
		--- `Fit` and not `Stretch`: the six glyphs are not all one aspect, and this is the one place
		--- on the card where the art is not being drawn at the size it was exported at.
		icon.ScaleType = Enum.ScaleType.Fit
		icon.BackgroundTransparency = 1
		icon.BorderSizePixel = 0
		icon.Parent = well

		well.Parent = main

		local columnLeft = 2 * marginX + wellWidth
		local columnWidth = 1 - columnLeft - marginX
		for _, spec in LINES do
			local line = body:Clone()
			line.Name = spec.Name
			line.Text = spec.Placeholder
			line.TextXAlignment = Enum.TextXAlignment.Left
			line.TextYAlignment = Enum.TextYAlignment.Center
			line.AnchorPoint = Vector2.new(0, 0.5)
			line.Position = UDim2.fromScale(columnLeft, spec.Y)
			line.Size = UDim2.fromScale(columnWidth, spec.Height)
			ceiling(line, spec.Fraction)
			line.Parent = main
		end

		body:Destroy()
		local btns = main:FindFirstChild("Btns")
		if btns then
			btns:Destroy()
		end

		--- Nothing on a notice is pressable, so nothing on it may be a button the component binds.
		local stray = 0
		for _, descendant in card:GetDescendants() do
			if CollectionService:HasTag(descendant, BUTTON_TAG) then
				CollectionService:RemoveTag(descendant, BUTTON_TAG)
				stray += 1
			end
		end
		if stray > 0 then
			out:warn(string.format("Removed %d stray %s tag(s) from the notice.", stray, BUTTON_TAG))
		end

		card.Parent = shelf

		out:print(string.format("Built %s.%s.%s from the kit's %s.", SCREEN_NAME, SHELF_NAME, SCREEN, KIT_FRAME))
		out:print("Header: Title and Clock. Body: Well (the bare glyph), World, Blurb, Payoff. Close button and Yes/No removed.")

		pcall(function()
			props:SetSelection({ card })
		end)
	end,
} :: Types.ScriptModule
