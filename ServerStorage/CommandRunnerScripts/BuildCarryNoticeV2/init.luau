--[[
	BuildCarryNoticeV2: Command Runner command

	Builds `StarterGui.MainUIV2.Screens.CarryNotice`, the carried car toast's template, out of the
	Cartoony Kit's `PromptUI`. It is the card a player sees when they get home with a car in their
	hands (`CarryConfig.Hint`, drawn by `CarryController`).

	Run `BuildMainUIV2` first: this fills in a shelf that already exists rather than creating one.
	`Screens.CarryNotice` is destroyed and made again on every run, and nothing else on the shelf is
	touched, so it is safe beside the other Phase 4 commands and safe to re-run.

	=== COMPACT CARRY TOAST — 2026-10-04 ======================================================

	CarryNoticeLayout now tightens this frame after construction and on runtime clones. The carry
	card keeps the weather notice's art, but uses a shorter body and smaller icon; the original
	full-height PromptUI left too much empty space around two short lines.

	=== IT WAS THE WEATHER NOTICE'S TWIN =====================================================

	`BuildWeatherNoticeV2` cut the same kit frame into a toast a few weeks before this, and every
	decision it made applies here: the same `PromptUI`, the same bare glyph in the same square, the
	same header with the close button taken off, the same `Ceiling` type caps, the same top centre
	landing. Two toasts in one band that were drawn differently would read as two different games, so
	the only things that differ here are what the card says and which glyph is in the square.

	    Header.Title   what happened            "Your New Car", the kit's own heading type
	    Main.Well      the glyph                the HUD rail's bare car, which is the picture this
	                                            game already uses for "a car of yours". `Well` is an
	                                            empty square that only positions it, and the note
	                                            below is why there is nothing painted in it
	    Main.Car       which car                "RED CAMARO" (`GarageConfig.carName`), the biggest
	                                            line on the card because it is the prize. It is NOT
	                                            called `Name`: a child of that name is shadowed by
	                                            its parent's own `Name` property, so `Main.Name`
	                                            would hand back the string "Main"
	    Main.Line      what to do with it       one sentence, no key named: the bay's own prompt
	                                            draws the right button for the device

	There is no clock, so the header title keeps the kit's full width rather than giving up its right
	end. The question and both buttons go: a notice is not something you answer.

	=== THE GLYPH SITS ON NOTHING, AND THAT IS THE CORRECTION ==================================

	It used to sit in a clone of `CodesUI.Main.XProfile.Logo`, the kit's navy square, and on this card
	that square read as a hole punched in the panel: a near black fill under a pure black rim, on a
	white body, next to type outlined in the kit's navy rather than in black. Nothing else in this UI
	is black.

	THE WELL WAS NEVER WRONG WHERE IT CAME FROM. In `CodesUI` that square sits on `XProfile`, a
	saturated cyan-to-blue strip, and a dark inset on a bright strip is exactly right. Lifting it out
	of that strip and dropping it on white is what broke it, and no amount of softening the rim fixes
	a layer whose whole job was to be darker than a blue that is no longer behind it.

	SO THE LAYER GOES, and the glyph is drawn bare at the full size of the square it used to sit in.
	That is also what the rest of this UI does: the HUD rail's cells are bare art and the new UI's
	grid is tile-less icons. Both toasts' glyphs carry their own outlines (the car here, all six
	Gvesster weather badges on the other card, checked on white), so none of them needs a plate under
	it to hold together. `BuildWeatherNoticeV2` makes the same square the same way, for the same
	reason, and the two are meant to stay identical.

	`Well` STAYS, as an empty square that only positions the glyph. It is the name both controllers
	reach through to find `Icon`, and the name is cheaper to keep than to chase.

	=== THE TYPE CEILINGS =====================================================================

	Both body lines are `TextScaled` under a `UITextSizeConstraint` named `Ceiling` carrying a
	`Fraction` attribute: a ceiling as a fraction of the CARD's height, rewritten in pixels by
	`CarryController._fitNotice` whenever the card resizes. Same instrument, same names, same reason
	as the weather notice: two rows in differently sized boxes render at sizes that agree, and a
	string that does not fit still shrinks rather than spilling.

	DO NOT "FIX" A WRAPPED LINE WITH `TextWrapped = false`. That silently clears `TextScaled` and
	drops the label to 8px. Shorten the copy in `CarryConfig.Hint` instead.

	=== WHERE IT SITS =========================================================================

	Anchored at its top centre and parked at the weather notice's shown position, a margin from the
	top edge in the kit's space (`IgnoreGuiInset` false, so 0 is already under the topbar). The
	controller slides it from above the screen to there.
]]

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)
local CarryNoticeLayout = require(game:GetService("ReplicatedStorage").shared.Modules.CarryNoticeLayout)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local SHELF_NAME = "Screens"
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage
local BUTTON_TAG = "UIButton" -- Components/Button

local SCREEN = "CarryNotice" -- CarryController's ScreenGui, and the template's name on the shelf
local KIT_FRAME = "PromptUI"

--- `CarryController`'s shown position: a fraction of the screen from the top edge.
local SHOWN_Y = 0.022 -- CarryConfig.Hint.Kit.ShownY

--- The glyph. `UIAssets.Upgrades.HeaderIcon`, which is the HUD rail's Cars cell: the bare car,
--- PixFixed, cropped flush to its art like every kit icon.
local CAR_ICON = "rbxassetid://91216847938226"

--- What `_fitNotice` reads. See the header.
local CEILING_NAME = "Ceiling"
local FRACTION_ATTRIBUTE = "Fraction"

--[[ The glyph's square, as a fraction of the card body's HEIGHT, and the glyph inside it as a
	fraction of that square. The margin round the square is the same on all three sides it has, which
	is what sets the text column's left edge. Both are the weather notice's.

	THE GLYPH FILLS THE SQUARE now that there is nothing painted behind it (see the header). At the
	0.7 this was, the art was inset to clear a rim that is no longer there, which left the glyph
	looking small and lost in the margin instead of centred in a plate. It is `Fit`, so a glyph that
	is not square still keeps its own shape. ]]
local WELL_HEIGHT = 0.76
local ICON_SIZE = 1

--[[ The two body lines, as a centre and a height in the body's own scale, top to bottom, and each
	line's type ceiling as a fraction of the CARD's height.

	THE NAME IS THE BIGGER OF THE TWO. It is the thing being handed over, and it is also the shorter
	string: a line that reads "RED CAMARO" at the instruction's size would look like a caption of it
	rather than the point of the card. ]]
local LINES = {
	{ Name = "Car", Y = 0.335, Height = 0.34, Fraction = 0.15, Placeholder = "RED CAMARO" },
	{ Name = "Line", Y = 0.69, Height = 0.3, Fraction = 0.1, Placeholder = "Park it in a bay on your lot" },
}

--- Placeholder, so a freshly built template reads as the finished card in the Explorer. The kit sets
--- its headings in title case, and `CarryController` writes `CarryConfig.Hint.KitTitle` over this.
local TITLE_PLACEHOLDER = "Your New Car"

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
	Description = "Build StarterGui.MainUIV2.Screens.CarryNotice (the carried car toast's template) from the Cartoony Kit's PromptUI: the heading in the header, the game's own car glyph drawn bare on the body, and two lines for the car's name and what to do with it. Rebuilds the template every run.",
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
		--- The title keeps the kit's own width and its own cap: there is no clock to make room for,
		--- and a heading the kit sized is right.
		title.Text = TITLE_PLACEHOLDER

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
		--- painted on it: it is the box the glyph is centred in and the name the controllers reach
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
		icon.Image = CAR_ICON
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Size = UDim2.fromScale(ICON_SIZE, ICON_SIZE)
		--- `Fit` and not `Stretch`: the glyph keeps its own aspect inside the square whatever it is.
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

		CarryNoticeLayout.apply(card)
		card.Parent = shelf

		out:print(string.format("Built %s.%s.%s from the kit's %s.", SCREEN_NAME, SHELF_NAME, SCREEN, KIT_FRAME))
		out:print("Header: Title. Body: Well (the bare car glyph), Car, Line. Close button and Yes/No removed.")

		pcall(function()
			props:SetSelection({ card })
		end)
	end,
} :: Types.ScriptModule
