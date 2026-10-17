--[[
	BuildMarketV2: Command Runner command

	Builds `StarterGui.MainUIV2.Pages.Market` out of the Cartoony Kit's `ItemShopUI`. Phase 3 of
	`docs/NewUI-Migration-Plan.md`; the running record is `docs/NewUI-Migration-Notes.md`.

	Run `BuildMainUIV2` first: this fills in a screen that already exists rather than creating one.
	`Pages.Market` is destroyed and made again on every run, and nothing else under `Pages` is
	touched, so it is safe beside the other Phase 3 commands and safe to re-run.

	=== THE KIT'S ROW ALREADY HOLDS EVERY FIELD A LISTING HAS ==================================

	`Icon`, `Text{ Title, Rarity, Description }` and `Btns{ CashBtns{ BuyBtn, DisabledBtn },
	RobuxBtn }`. Our shelf sells cars for cash and has no Robux SKU in it, so the second button is
	the only thing on this row that has to become something else: it is the BUY ALL pill, which is
	what the plan asks for, and the shipping page has drawn it since the market landed.

	WHICH MEANS THE TWO BUTTONS MUST BE THE SAME SHAPE, and only one of them is. The kit gives the
	cash button a drawn disabled state (`DisabledBtn`, the same pill in grey with the price still
	on it) and gives the Robux button nothing. So `CashBtns` becomes `BuyOne`, a COPY of it becomes
	`BuyAll`, and the Robux button moves into the copy in place of its green one. Both slots are now
	`{ BuyBtn, DisabledBtn }`, the page has one path for both, and every pixel of both is still the
	artist's: the orange face, the white backing and the grey refusal are all drawn here.

	`BuyOne` IS ALSO MOVED ABOVE `BuyAll`, which reverses the artist's order. Robux sits on top in
	the kit because Robux is the thing that shop wants pressed. Here the top button is one car at
	one price, which is the common action and the cheap one.

	=== THE COUNTDOWN GOES IN THE HEADER, WHERE THE ARTIST LEFT A GAP ==========================

	`Header` is a title on the left at half its width and a close button at the far right, so the
	band between them is empty and is exactly the shape of a clock. The shipping market puts "RESET
	IN" in its title bar too, so a returning player finds it where they left it, and the plan's "the
	reset timer needs a place" is answered without moving anything the artist drew.

	It is a CLONE of `Header.Title`, so the face, the rim and the size constraint are the header's
	own, and it is right-aligned to stop against the close button's edge rather than floating.

	=== WHAT ELSE IS ADDED, AND WHY ===========================================================

	  • `Note`, the empty-shelf line, cloned from the row's `Title` so it is the artist's type. It is
	    a row like any other, which is the answer `BuildShopV2` and `BuildQuestV2` both gave.
	  • A NAME on the rarity label's gradient (`Tint`). The kit draws "Rare" in a cyan-to-blue ramp,
	    and our rarity is one of five bands with a colour of its own (`Modules/CarRarity`), so the
	    page writes that ramp per row. It is named because the page has to find exactly it: there is
	    a second UIGradient on the row one level up.

	=== WHAT IS NOT ADDED =====================================================================

	NO CAR PORTRAIT IS BUILT HERE. `Icon` stays exactly as the kit drew it, and `PagesV2/Market`
	lays a `ViewportFrame` over its rect at runtime through `Modules/CarViewport`, which is the one
	module allowed to put a car in a box. Building one here would be a second copy of that module's
	camera and lighting, and the kit icon underneath is then the fallback for a body with no
	published shell.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)
local KitGrowth = require(ReplicatedStorage.shared.Modules.KitGrowth)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage

local PAGE_NAME = "Market"
local KIT_FRAME = "ItemShopUI"

--- The kit's names, and ours.
local KIT_ROW = "Template"
local ROW_NAME = "Listing"
local SPACER_NAME = "Padding" -- the kit already calls its bottom spacer this
local NOTE_NAME = "Note"

--- What the page reads off the row. Every one of these is a path in `PagesV2/Market`.
local TEXT_BLOCK = "Text"
local RARITY_LABEL = "Rarity"
local RARITY_TINT = "Tint"
local BTNS = "Btns"
local KIT_CASH_SLOT = "CashBtns"
local KIT_ROBUX_BTN = "RobuxBtn"
local BUY_SLOT = "BuyOne"
local ALL_SLOT = "BuyAll"
local BUY_BTN = "BuyBtn"
local DISABLED_BTN = "DisabledBtn"

--- The header's countdown.
local TIMER_NAME = "Timer"

--[[ How far the clock stops short of the close button, as a fraction of that button's OWN width.

	Measured against the button rather than against the header, because what it has to clear is the
	button: half its width is the gap the artist left between the button and the panel's right rim,
	so the same number puts the same air on both sides of it. ]]
local TIMER_GUTTER = 0.5

--[[ How tall the empty-shelf note is, as a multiple of a listing.

	A third, which is one line of the row's own `Title` type. The market's note is one short sentence
	where the quest board's is two, and a note the height of a full listing would set it as a
	headline over an empty panel. ]]
local NOTE_ROW_SCALE = 0.34

--- The kit's own placeholders, so a freshly built page reads as the finished screen in the Explorer
--- before anything binds to it. All of them are overwritten on the first paint.
local TITLE_TEXT = "Market"
local TIMER_PLACEHOLDER = "Resets in 12m 34s"
local NAME_PLACEHOLDER = "CAMARO"
local RARITY_PLACEHOLDER = "SEDAN"
local DESC_PLACEHOLDER = "4 in stock. Earns $9/s in your garage."
local PRICE_PLACEHOLDER = "$2,160"
local ALL_PLACEHOLDER = "\u{00D7}4 $8,640"
local NOTE_PLACEHOLDER = "No cars on the shelf right now"

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

--- A GuiObject's left and right edges in its parent's X scale, anchor included.
local function xSpan(gui: GuiObject): (number, number)
	local left = gui.Position.X.Scale - gui.AnchorPoint.X * gui.Size.X.Scale
	return left, left + gui.Size.X.Scale
end

return {
	Description = "Build StarterGui.MainUIV2.Pages.Market from the Cartoony Kit's ItemShopUI: one Listing row whose Robux button becomes the Buy All pill, and the reset countdown in the header's empty band. Rebuilds the page every run.",
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
			out:error(string.format("The kit's %s has no `Main.ScrollingFrame`; there is no shelf to fill.", KIT_FRAME))
			page:Destroy()
			return
		end

		-- === The header =====================================================
		local header = page:FindFirstChild("Header")
		local headerTitle = header and header:FindFirstChild("Title")
		local closeBtn = header and header:FindFirstChild("CloseBtn")
		if not (headerTitle and headerTitle:IsA("TextLabel")) then
			out:error(string.format("The kit's %s has no `Header.Title`; there is no header to caption.", KIT_FRAME))
			page:Destroy()
			return
		end

		--[[ "Item Shop" is the kit's own name for this screen and ours is the Market: the page is
			called that everywhere it is routed to, and the HUD cell under it says the same word. ]]
		headerTitle.Text = TITLE_TEXT

		local timer: TextLabel? = nil
		if closeBtn and closeBtn:IsA("GuiObject") then
			local _titleLeft, titleRight = xSpan(headerTitle)
			local closeLeft = xSpan(closeBtn)
			local right = closeLeft - TIMER_GUTTER * closeBtn.Size.X.Scale

			local clock = headerTitle:Clone()
			clock.Name = TIMER_NAME
			clock.Text = TIMER_PLACEHOLDER
			--- Right against the close button's side of the gap, so a clock counting down from
			--- "1h 5m" to "47s" stays put instead of walking left as its figures drop.
			clock.TextXAlignment = Enum.TextXAlignment.Right
			clock.AnchorPoint = Vector2.new(1, headerTitle.AnchorPoint.Y)
			clock.Size = UDim2.new(math.max(0, right - titleRight), 0, headerTitle.Size.Y.Scale, 0)
			clock.Position = UDim2.new(right, 0, headerTitle.Position.Y.Scale, 0)
			clock.Parent = header
			timer = clock
		else
			out:warn("The kit's `Header.CloseBtn` is gone, so there is nowhere to hang the countdown.")
		end

		-- === The row ========================================================
		local kept: GuiObject? = nil
		local spares = 0
		for _, child in list:GetChildren() do
			if child.Name ~= KIT_ROW or not child:IsA("GuiObject") then
				continue
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

		local text = row:FindFirstChild(TEXT_BLOCK)
		local rowTitle = text and text:FindFirstChild("Title")
		local rarity = text and text:FindFirstChild(RARITY_LABEL)
		local description = text and text:FindFirstChild("Description")
		if not (rowTitle and rowTitle:IsA("TextLabel") and rarity and rarity:IsA("TextLabel") and description and description:IsA("TextLabel")) then
			out:error(string.format("`%s.%s` is missing Title, Rarity or Description; there is nothing to fill.", ROW_NAME, TEXT_BLOCK))
			page:Destroy()
			return
		end

		rowTitle.Text = NAME_PLACEHOLDER
		rarity.Text = RARITY_PLACEHOLDER
		description.Text = DESC_PLACEHOLDER

		--- One name for the one gradient the page writes to. The kit leaves it called `UIGradient`,
		--- which is also what the row's own background ramp is called two levels up.
		local tint = rarity:FindFirstChildOfClass("UIGradient")
		if tint then
			tint.Name = RARITY_TINT
		else
			out:warn(string.format("`%s.%s` has no UIGradient; every rarity will read in one colour.", TEXT_BLOCK, RARITY_LABEL))
		end

		-- === The two buy slots ==============================================
		local btns = row:FindFirstChild(BTNS)
		local buyOne = btns and btns:FindFirstChild(KIT_CASH_SLOT)
		local robuxBtn = btns and btns:FindFirstChild(KIT_ROBUX_BTN)
		if not (btns and buyOne and buyOne:IsA("GuiObject") and robuxBtn and robuxBtn:IsA("GuiButton")) then
			out:error(string.format("`%s.%s` is missing `%s` or `%s`; the row has no buttons to wire.", ROW_NAME, BTNS, KIT_CASH_SLOT, KIT_ROBUX_BTN))
			page:Destroy()
			return
		end

		local slotOne = buyOne :: GuiObject
		slotOne.Name = BUY_SLOT
		--- One car at one price is the common press, so it goes on top. See the header.
		slotOne.LayoutOrder = 0

		local buyBtn = slotOne:FindFirstChild(BUY_BTN)
		local disabledBtn = slotOne:FindFirstChild(DISABLED_BTN)
		if not (buyBtn and buyBtn:IsA("GuiButton") and disabledBtn and disabledBtn:IsA("GuiObject")) then
			out:error(string.format("`%s.%s` is missing `%s` or `%s`; there is no refused state to draw.", BTNS, BUY_SLOT, BUY_BTN, DISABLED_BTN))
			page:Destroy()
			return
		end

		--- Whatever state the artist left this copy in, the page paints it on the first frame.
		--- Normalised anyway, so a freshly built row reads as an affordable listing in the Explorer.
		buyBtn.Visible = true
		disabledBtn.Visible = false

		local buyTitle = buyBtn:FindFirstChild("Title")
		if buyTitle and buyTitle:IsA("TextLabel") then
			buyTitle.Text = PRICE_PLACEHOLDER
		end
		local disabledTitle = disabledBtn:FindFirstChild("Title")
		if disabledTitle and disabledTitle:IsA("TextLabel") then
			disabledTitle.Text = PRICE_PLACEHOLDER
		end

		--[[ The second slot is a COPY of the first, so it carries the white backing and the grey
			refusal with it, and the Robux button moves in where the copy's green one was. Cloning
			rather than building means the two slots cannot drift apart in the Explorer either. ]]
		local slotAll = slotOne:Clone()
		slotAll.Name = ALL_SLOT
		slotAll.LayoutOrder = 1
		local spareBuy = slotAll:FindFirstChild(BUY_BTN)
		if spareBuy then
			spareBuy:Destroy()
		end

		local orange = robuxBtn :: GuiButton
		orange.Name = BUY_BTN
		orange.AnchorPoint = Vector2.new(0.5, 0.5)
		orange.Position = UDim2.fromScale(0.5, 0.5)
		orange.Size = UDim2.fromScale(1, 1)
		orange.Visible = true
		orange.Parent = slotAll

		local allTitle = orange:FindFirstChild("Title")
		if allTitle and allTitle:IsA("TextLabel") then
			allTitle.Text = ALL_PLACEHOLDER
		end
		local allDisabled = slotAll:FindFirstChild(DISABLED_BTN)
		local allDisabledTitle = allDisabled and allDisabled:FindFirstChild("Title")
		if allDisabledTitle and allDisabledTitle:IsA("TextLabel") then
			allDisabledTitle.Text = ALL_PLACEHOLDER
		end

		slotAll.Parent = btns

		-- === The list's other two rows ======================================
		local spacer = list:FindFirstChild(SPACER_NAME)
		if not spacer then
			out:warn(string.format("The kit's `%s` spacer is gone; the last listing will sit against the rim.", SPACER_NAME))
		end

		--[[ The empty-shelf line. A row like any other, so it takes the list's own place rather than
			floating over it, and it is the artist's own `Title` type rather than a label built in
			code. Wrapped, which is the one label on this page that is: it is the only string here
			whose length is not something the layout controls. ]]
		local note = rowTitle:Clone()
		note.Name = NOTE_NAME
		note.Text = NOTE_PLACEHOLDER
		note.TextXAlignment = Enum.TextXAlignment.Center
		note.TextWrapped = true
		note.AnchorPoint = Vector2.new(0, 0)
		note.Position = UDim2.new()
		note.Size = UDim2.fromScale(row.Size.X.Scale, row.Size.Y.Scale * NOTE_ROW_SCALE)
		note.Parent = list

		--- Bigger than the kit, text caps included. See `Modules/KitGrowth`.
		KitGrowth.apply(page, KitGrowth.Pages)
		page.Parent = pages

		out:print(string.format("Built %s.Pages.%s from the kit's %s.", SCREEN_NAME, PAGE_NAME, KIT_FRAME))
		out:print(
			string.format(
				"Row `%s`: %d spare copies dropped, `%s` renamed `%s` and copied into `%s` with `%s` inside it, rarity gradient named `%s`.",
				ROW_NAME,
				spares,
				KIT_CASH_SLOT,
				BUY_SLOT,
				ALL_SLOT,
				KIT_ROBUX_BTN,
				RARITY_TINT
			)
		)
		out:print(
			string.format(
				"List rows: %s, %s, %s. Header captioned `%s`%s.",
				ROW_NAME,
				NOTE_NAME,
				if spacer then SPACER_NAME else "(no spacer)",
				TITLE_TEXT,
				if timer then string.format(" with the `%s` countdown beside it", TIMER_NAME) else " and no countdown"
			)
		)

		pcall(function()
			props:SetSelection({ page })
		end)
	end,
} :: Types.ScriptModule
