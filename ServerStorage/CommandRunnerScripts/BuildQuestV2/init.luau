--[[
	BuildQuestV2: Command Runner command

	Builds `StarterGui.MainUIV2.Pages.Quest` out of the Cartoony Kit's `QuestsUI`. Phase 3 of
	`docs/NewUI-Migration-Plan.md`; the running record is `docs/NewUI-Migration-Notes.md`.

	Run `BuildMainUIV2` first: this fills in a screen that already exists rather than creating one.
	`Pages.Quest` is destroyed and made again on every run, and nothing else under `Pages` is touched,
	so it is safe beside the other Phase 3 commands and safe to re-run.

	=== THE KIT DREW FOUR ROWS IN TWO STATES, AND BOTH STATES ARE THE FEATURE ==================

	`QuestsUI` ships four copies of `Template`, and they are not four copies: two are drawn in
	progress (blue fill at half width, the grey `DisabledBtn` showing) and two are drawn finished
	(a yellow-to-green fill at full width, the green `ClaimBtn` showing). That is the artist telling
	us what a done quest looks like, and it is worth more than the spare rows are.

	So this keeps ONE row, renamed `QuestRow`, and takes the finished state off a sibling before
	destroying it: the green ramp is written onto `Progress` as a `DoneColor` attribute, and
	`PagesV2/Quest` swaps it onto the live gradient when a quest completes. A ColorSequence is a
	supported attribute type, so the colour stays in the art where an artist can retune it rather
	than becoming six numbers typed into a page module.

	=== THE TABS STAY, AND THE CLOCK HANGS UNDER THE PANEL ====================================

	The kit draws `Daily / Weekly / Monthly / All Time` above the list. The first build took them out
	and put the clock in their space, because only the daily board exists. Dylan's call (2026-09-16):
	keep the four tabs as the artist left them, with Daily live and the other three saying "Coming
	soon" until they have boards (`QuestConfig.Tabs`), and move the clock OUT of the panel to sit
	under it.

	So `CategoryBtns` and the list are not touched at all, and `TimeLeft` is a child of the page
	itself, below its bottom edge. It is as tall as the tab strip and as wide as the cards (the
	strip's own width inside `Main`), and it sits as far below the panel as the header sits inside
	the panel's top (`FOOTER_GAP_FROM_HEADER`). A child of the page rather than of the screen, so the
	open tween scales it with the panel it belongs to.

	The bar inside the footer is a clone of the ROW's own `ProgressBar`, sized so it is drawn at the
	same thickness there as it is on a card. It is the same bar, full width, along the bottom.

	=== WHAT ELSE IS ADDED, AND WHY ===========================================================

	  • `Card` + `CardScale`, wrapped round the row's contents. A claimed card punches, fades and
	    folds while the ROW's height collapses under it, and those are two different instances: the
	    row is owned by the `UIListLayout` and its height is the thing that closes. The row keeps the
	    height; the card keeps the art. Same structure the shipping page builds in code, authored
	    here instead so it is visible in the Explorer.
	  • `BarLabel`, the `Progress: 3/5` caption. The kit's bar is bare, and a bar alone cannot say
	    how many of the 15,000 studs are left. It sits on the right half of the bar, just above it,
	    right-aligned to the bar's own right edge, set in the reward line's size (see
	    `BAR_LABEL_CLEARANCE`).
	  • `Note`, the empty-list line, cloned from the row's `Title` so it is the artist's type. It is a
	    row like any other, which is the same answer `BuildShopV2` gave the gift picker.
	  • `Padding`, the kit's own bottom spacer, renamed off `Frame` to the name Shop and Settings
	    already use for it.

	=== WHAT IS NOT ADDED =====================================================================

	NO REWARD ICON. The shipping row draws a chip with a banknote in it; the kit writes the reward as
	text in its own green, and that is better on this art. It costs one thing, and `PagesV2/Quest`
	pays it there: the claim's flyer is the reward LABEL rather than a banknote sprite.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)
local KitGrowth = require(ReplicatedStorage.shared.Modules.KitGrowth)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage

local PAGE_NAME = "Quest" -- QuestConfig.PageName
local KIT_FRAME = "QuestsUI"

--- The kit's names, and ours. `KIT_ROW` is renamed `ROW_NAME` and the rest of its copies destroyed.
local KIT_ROW = "Template"
local ROW_NAME = "QuestRow"
local KIT_SPACER = "Frame"
local SPACER_NAME = "Padding"
local CATEGORY_STRIP = "CategoryBtns"

--- What the page reads off the row. Every one of these is a path in `PagesV2/Quest`.
local CARD_NAME = "Card"
local CARD_SCALE = "CardScale"
local BAR_NAME = "ProgressBar"
local FILL_NAME = "Progress"
local FILL_GRADIENT = "Fill"
local DONE_ATTRIBUTE = "DoneColor"
local BAR_LABEL = "BarLabel"
local NOTE_NAME = "Note"

--- The footer, and the two things in it.
local FOOTER_NAME = "TimeLeft"
local FOOTER_TRACK = "Track"
local FOOTER_LABEL = "Label"

--[[ How far under the panel the footer sits, in the page's Y scale. The real number is read off the
	art at build time: the gap between the panel's top edge and the top of its `Header`. The clock is
	outside the panel with nothing behind it, and mirroring the header's margin is what makes it read
	as belonging to the panel above rather than to the screen. This is only the fallback for a kit
	whose header has gone, and it is what the kit measures. ]]
local FOOTER_GAP_FALLBACK = 0.038

--[[ How far the caption stops SHORT of the bar, as a fraction of the bar's own height.

	THE CAPTION IS THE REWARD LINE'S HEIGHT, which is the kit's own size for the second line of a
	card. The first cut squeezed it into the empty run between the quest name and the bar, which came
	out at about a third of the name and was too small to read (Dylan, 2026-09-16). At the reward's
	height its top runs up beside the quest name, which is why the box only takes the RIGHT HALF of
	the bar: a quest name is left-aligned and ends before the bar's midpoint, so the two share the
	band without touching, and a caption too long for its half shrinks rather than running into
	the name.

	Measured against the bar rather than against the row, because the thing it has to clear is the
	bar's rim: those strokes are `ScaledSize`, so they grow out of the bar's box by a fraction of the
	bar's height and there is no fixed gap that is right at every resolution. Rendered at a third of
	the bar with a full cash target in the caption, the two read as two lines; touching, the number
	reads as a label printed on the track. ]]
local BAR_LABEL_CLEARANCE = 0.35

--[[ How tall the empty-list note is, as a multiple of a quest row.

	Six tenths, which is two lines of the row's own `Title` type. "All quests claimed! Come back
	tomorrow." is six words and wraps to two; a note the height of a full card would set it as a
	headline over an empty panel. ]]
local NOTE_ROW_SCALE = 0.6

--- The kit's own placeholders, so a freshly built page reads as the finished screen before anything
--- binds to it. All three are overwritten on the first paint.
local FOOTER_PLACEHOLDER = "Time Left: 15h 15m 15s"
local BAR_PLACEHOLDER = "Progress: 10/15"
local NOTE_PLACEHOLDER = "No quests today"

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

--- A GuiObject's top and bottom edges in its parent's Y scale, anchor included.
local function span(gui: GuiObject): (number, number)
	local top = gui.Position.Y.Scale - gui.AnchorPoint.Y * gui.Size.Y.Scale
	return top, top + gui.Size.Y.Scale
end

--[[ Everything the row draws moves one level down, into a frame the outro can scale and fade as one
	object. The card takes the row's own look with it, because on this kit the ROW IS THE CARD: the
	white fill, the rim and the rounded corner are properties and children of the row itself, and a
	fold that left them behind would fade the quest's contents out of a card that stayed. ]]
local function wrapCard(row: GuiObject): Frame
	local card = Instance.new("Frame")
	card.Name = CARD_NAME
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(1, 1)
	card.ZIndex = row.ZIndex
	card.BackgroundColor3 = row.BackgroundColor3
	card.BackgroundTransparency = row.BackgroundTransparency
	card.BorderSizePixel = 0

	--- A snapshot, so reparenting as we walk it is safe. The corner and the rim come too.
	for _, child in row:GetChildren() do
		child.Parent = card
	end
	card.Parent = row

	--- The row is now nothing but a height.
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0

	local scale = Instance.new("UIScale")
	scale.Name = CARD_SCALE
	scale.Parent = card
	return card
end

return {
	Description = "Build StarterGui.MainUIV2.Pages.Quest from the Cartoony Kit's QuestsUI: one QuestRow with a Card wrapper and a progress caption, the kit's category tabs kept, and a TimeLeft footer under the panel. Rebuilds the page every run.",
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

		local main = page:FindFirstChild("Main")
		local list = main and main:FindFirstChildOfClass("ScrollingFrame")
		if not (main and main:IsA("GuiObject") and list) then
			out:error(string.format("The kit's %s has no `Main.ScrollingFrame`; there is no list to fill.", KIT_FRAME))
			page:Destroy()
			return
		end

		-- === The row ========================================================
		--[[ The finished state is harvested BEFORE the spare copies go, because it is the only place
			it exists. A row whose `ClaimBtn` is the visible one is the artist's drawing of a quest
			that is done, and the green ramp on its fill is the part worth keeping. ]]
		local kept: GuiObject? = nil
		local doneColor: ColorSequence? = nil
		local spares = 0
		for _, child in list:GetChildren() do
			if child.Name ~= KIT_ROW or not child:IsA("GuiObject") then
				continue
			end

			local bar = child:FindFirstChild(BAR_NAME)
			local fill = bar and bar:FindFirstChild(FILL_NAME)
			local claim = child:FindFirstChild("Btns")
			claim = claim and claim:FindFirstChild("ClaimBtn")
			if not doneColor and fill and claim and claim:IsA("GuiObject") and claim.Visible then
				local gradient = fill:FindFirstChildOfClass("UIGradient")
				doneColor = gradient and gradient.Color
			end

			if kept then
				spares += 1
				child:Destroy()
			else
				kept = child
			end
		end

		if not kept then
			out:error(string.format("The kit's %s list has no `%s` row to build from.", KIT_FRAME, KIT_ROW))
			page:Destroy()
			return
		end

		local row = kept :: GuiObject
		row.Name = ROW_NAME

		local bar = row:FindFirstChild(BAR_NAME)
		local fill = bar and bar:FindFirstChild(FILL_NAME)
		if not (bar and bar:IsA("GuiObject") and fill and fill:IsA("GuiObject")) then
			out:error(string.format("`%s` has no `%s.%s`; there is no progress bar to drive.", ROW_NAME, BAR_NAME, FILL_NAME))
			page:Destroy()
			return
		end

		--- One name for the one gradient the page writes to. The kit leaves it called `UIGradient`,
		--- which is also what the track's own gradient is called one level up.
		local fillGradient = fill:FindFirstChildOfClass("UIGradient")
		if fillGradient then
			fillGradient.Name = FILL_GRADIENT
		else
			out:warn(string.format("`%s.%s` has no UIGradient; the bar will not change colour.", BAR_NAME, FILL_NAME))
		end

		if doneColor then
			fill:SetAttribute(DONE_ATTRIBUTE, doneColor)
		else
			out:warn(string.format("No finished-state row in the kit; `%s` is unset and a full bar stays blue.", DONE_ATTRIBUTE))
		end

		--- Whatever state the artist left the kept copy in, the page paints it on the first frame.
		--- Normalised anyway so a freshly built row reads as an unfinished quest in the Explorer.
		local btns = row:FindFirstChild("Btns")
		local claimBtn = btns and btns:FindFirstChild("ClaimBtn")
		local disabledBtn = btns and btns:FindFirstChild("DisabledBtn")
		if claimBtn and claimBtn:IsA("GuiObject") then
			claimBtn.Visible = false
		end
		if disabledBtn and disabledBtn:IsA("GuiObject") then
			disabledBtn.Visible = true
		end
		if not (claimBtn and disabledBtn) then
			out:warn(string.format("`%s.Btns` is missing `ClaimBtn` or `DisabledBtn`; the row has no pressable state.", ROW_NAME))
		end

		-- === The progress caption ===========================================
		local text = row:FindFirstChild("Text")
		local title = text and text:FindFirstChild("Title")
		if not (title and title:IsA("TextLabel")) then
			out:error(string.format("`%s.Text.Title` is not a TextLabel; there is nothing to clone type from.", ROW_NAME))
			page:Destroy()
			return
		end

		local reward = (text :: Instance):FindFirstChild("Reward")
		if not (reward and reward:IsA("TextLabel")) then
			out:error(string.format("`%s.Text.Reward` is not a TextLabel; there is no line size to set the caption in.", ROW_NAME))
			page:Destroy()
			return
		end

		local barTop = span(bar :: GuiObject)
		local barLeft = bar.Position.X.Scale - bar.AnchorPoint.X * bar.Size.X.Scale
		local barRight = barLeft + bar.Size.X.Scale

		--- The reward line's height carried up into the row's scale. See `BAR_LABEL_CLEARANCE`.
		local captionHeight = reward.Size.Y.Scale * (text :: GuiObject).Size.Y.Scale
		local captionBottom = barTop - BAR_LABEL_CLEARANCE * bar.Size.Y.Scale

		local caption = (title :: TextLabel):Clone()
		caption.Name = BAR_LABEL
		caption.Text = BAR_PLACEHOLDER
		--- Right against the bar's own right edge: the number and the thing it describes stop at the
		--- same pixel, and a left-aligned one would drift away from the bar as the figures got short.
		caption.TextXAlignment = Enum.TextXAlignment.Right
		caption.TextYAlignment = Enum.TextYAlignment.Bottom
		caption.AnchorPoint = Vector2.new(1, 1)
		caption.Size = UDim2.fromScale(barRight - (barLeft + barRight) / 2, captionHeight)
		caption.Position = UDim2.fromScale(barRight, captionBottom)
		caption.Parent = row

		-- === The card wrapper ===============================================
		wrapCard(row)

		-- === The list's other two rows ======================================
		local spacer = list:FindFirstChild(KIT_SPACER)
		if spacer then
			spacer.Name = SPACER_NAME
		else
			out:warn(string.format("The kit's `%s` spacer is gone; the last quest will sit against the rim.", KIT_SPACER))
		end

		--[[ The empty-list line. A row like any other, so it takes the list's own place rather than
			floating over it, and it is the artist's own `Title` type rather than a label built in
			code. Wrapped, which is the one label on this page that is: it is the only string here
			whose length is not something the layout controls. ]]
		local note = (title :: TextLabel):Clone()
		note.Name = NOTE_NAME
		note.Text = NOTE_PLACEHOLDER
		note.TextXAlignment = Enum.TextXAlignment.Center
		note.TextWrapped = true
		note.AnchorPoint = Vector2.new(0, 0)
		note.Position = UDim2.new()
		note.Size = UDim2.fromScale(row.Size.X.Scale, row.Size.Y.Scale * NOTE_ROW_SCALE)
		note.Parent = list

		-- === The footer, under the panel ====================================
		--[[ The tab strip stays exactly as the kit drew it; `PagesV2/Quest` wires it. It is only read
			here, for the footer's size. ]]
		local strip = main:FindFirstChild(CATEGORY_STRIP)
		local footer: Frame? = nil
		if strip and strip:IsA("GuiObject") then
			local stripTop, stripBottom = span(strip)
			local mainScale = (main :: GuiObject).Size

			--- Every size below is in the PAGE's scale, because that is the footer's parent.
			local footerHeight = (stripBottom - stripTop) * mainScale.Y.Scale
			local footerWidth = strip.Size.X.Scale * mainScale.X.Scale

			local gap = FOOTER_GAP_FALLBACK
			local header = page:FindFirstChild("Header")
			if header and header:IsA("GuiObject") then
				gap = (span(header))
			end

			footer = Instance.new("Frame")
			local frame = footer :: Frame
			frame.Name = FOOTER_NAME
			frame.BackgroundTransparency = 1
			frame.BorderSizePixel = 0
			frame.AnchorPoint = Vector2.new(0.5, 0)
			--- Centred like `Main`, and the strip's width inside it, so the footer lines up with the cards.
			frame.Size = UDim2.fromScale(footerWidth, footerHeight)
			frame.Position = UDim2.fromScale((main :: GuiObject).Position.X.Scale, 1 + gap)
			frame.ZIndex = strip.ZIndex
			frame.Parent = page

			--[[ The same bar the cards carry, drawn at the same thickness. Its height on a card is
				its own fraction of a row, of the list, of `Main`, of the page; here it is that number
				divided by the footer's height, so the two are the same weight of line on screen. ]]
			local rowBarHeight = bar.Size.Y.Scale * row.Size.Y.Scale * list.Size.Y.Scale * mainScale.Y.Scale
			local trackHeight = math.clamp(rowBarHeight / frame.Size.Y.Scale, 0, 1)

			local track = (bar :: GuiObject):Clone()
			track.Name = FOOTER_TRACK
			track.AnchorPoint = Vector2.new(0.5, 1)
			track.Position = UDim2.fromScale(0.5, 1)
			track.Size = UDim2.fromScale(1, trackHeight)
			local trackFill = track:FindFirstChild(FILL_NAME)
			if trackFill and trackFill:IsA("GuiObject") then
				trackFill.Size = UDim2.fromScale(1, 1)
				--- The clone carried the row's finished colour with it. The clock drains and never
				--- completes, so it has no finished state to carry.
				trackFill:SetAttribute(DONE_ATTRIBUTE, nil)
			end
			track.Parent = frame

			--[[ The clock is set at the size of a QUEST NAME, and that is the whole reason this is
				arithmetic rather than a fraction of the footer.

				`TextScaled` fills the box it is given, so a clock that took the footer's spare height
				came out bigger than every quest on the board — which is the countdown shouting over
				the list it belongs to. Its box is the title's own height carried down through the
				row, the list, `Main` and the footer, so the two lines are the same type at every
				resolution. What is left over falls between the clock and the bar as a gap. ]]
			local titleHeight = title.Size.Y.Scale
				* text.Size.Y.Scale
				* row.Size.Y.Scale
				* list.Size.Y.Scale
				* mainScale.Y.Scale

			local clock = (title :: TextLabel):Clone()
			clock.Name = FOOTER_LABEL
			clock.Text = FOOTER_PLACEHOLDER
			clock.TextXAlignment = Enum.TextXAlignment.Center
			clock.AnchorPoint = Vector2.new(0.5, 0)
			clock.Position = UDim2.fromScale(0.5, 0)
			clock.Size = UDim2.fromScale(1, math.clamp(titleHeight / frame.Size.Y.Scale, 0, 1 - trackHeight))
			clock.Parent = frame
		else
			out:warn(string.format("The kit's `%s` is gone, so there is nowhere to put the countdown.", CATEGORY_STRIP))
		end

		--- Bigger than the kit, text caps included. See `Modules/KitGrowth`.
		KitGrowth.apply(page, KitGrowth.Pages)
		page.Parent = pages

		out:print(string.format("Built %s.Pages.%s from the kit's %s.", SCREEN_NAME, PAGE_NAME, KIT_FRAME))
		out:print(
			string.format(
				"Row `%s`: %d spare copies dropped, contents wrapped in `%s`, `%s` added above the bar, fill gradient named `%s`%s.",
				ROW_NAME,
				spares,
				CARD_NAME,
				BAR_LABEL,
				FILL_GRADIENT,
				if doneColor then string.format(", finished colour kept as the `%s` attribute", DONE_ATTRIBUTE) else ""
			)
		)
		out:print(
			string.format(
				"List rows: %s, %s, %s. %s",
				ROW_NAME,
				NOTE_NAME,
				SPACER_NAME,
				if footer
					then string.format("`%s` tabs kept; `%s` footer built under the panel.", CATEGORY_STRIP, FOOTER_NAME)
					else "No footer built."
			)
		)

		pcall(function()
			props:SetSelection({ page })
		end)
	end,
} :: Types.ScriptModule
