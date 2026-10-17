--[[
	BuildStartCarV2: Command Runner command

	Builds `StarterGui.MainUIV2.Pages.StartCar` out of the Cartoony Kit's `InventoryUI`. Phase 3 of
	`docs/NewUI-Migration-Plan.md`; the running record is `docs/NewUI-Migration-Notes.md`.

	Run `BuildMainUIV2` first: this fills in a screen that already exists rather than creating one.
	`Pages.StartCar` is destroyed and made again on every run, and nothing else under `Pages` is
	touched, so it is safe beside the other Phase 3 commands and safe to re-run.

	THE PAGE IS SELECT CAR, the third press of Play: Play opens the worlds, a world opens this, and a
	card here starts the run in that world and that car. `PagesV2/StartCar` is the behaviour and
	`StartCarController` holds the two facts the cards are drawn from.

	=== WHY INVENTORYUI AND NOT TEAMSELECTIONUI ================================================

	The plan offered both, and `TeamSelectionUI` is the closer WORD: three tall cards, a big picture
	on each, and a green `Play` under it, which is exactly what a press on this screen does. It lost
	on the one thing a car picker cannot do without. Its `Main` is a horizontal `UIListLayout` of
	three fixed cards with no `ScrollingFrame` at all, and this list is the starter plus every car a
	player owns, which is forty for somebody who has been playing a week. Making that frame scroll
	would be inventing a layout the artist never drew, sideways, which `KitPage` does not read.

	`InventoryUI` is the same question the cars inventory already answers ("pick one of your cars")
	in a grid that scrolls, with a search for the forty-car case, and `PagesV2/Dealership` has
	already proven the card, the grid geometry and `Modules/CarViewportGrid` on it. So this is that
	frame, and the card's button is the Play verb instead of the Equip one.

	=== WHAT CHANGES FROM THE KIT'S CARD =======================================================

	    Template            the grid cell, renamed `CarCard`
	      Template          the face, renamed `Face`: Rarity, Icon (the car goes over it), Title
	      Btns              EquipBtn (green, "DRIVE")      EquippedBtn (grey): DELETED

	  • THE GREY BUTTON IS DELETED, NOT HIDDEN. The kit draws it for a card that is already what you
	    are asking for, and on this screen there is no such card: pressing the car you drove last
	    time still starts a run, which is the whole of what a press here means. A grey face that can
	    never show is a second button the page would have to remember to keep hidden. The kit master
	    still has it.
	  • `Rim`, a stroke on the face in the kit's own green, off by default, and `Selected`, a chip
	    reading SELECTED, hidden by default. Together they mark the car the
	    server has stored (`StartCarConfig.Attribute`), which is the car the next run starts in. The
	    rim is `BuildDealershipV2`'s, made the same way. The chip is there as well because a rim is
	    a tint on the artist's white border and reads as one, and "which of these is mine already"
	    is the one question the shipping screen answers in words. The chip sits in the low band of
	    the face, over the road under the car, where the cars inventory puts its level.

	    The chip wears the BUTTON's gradient, harvested at build time, so SELECTED and DRIVE are the
	    same yellow-to-green and the card reads as one statement rather than two colours arguing.

	=== AND FROM THE KIT'S TOP BAR =============================================================

	`EquipBestBtn` and `DeleteBtn` go, as on the cars inventory: neither has a feature behind it.
	The search stays and has its prompt moved out of `Text` (the kit typed it in).

	THE `50/50` READOUT BECOMES THE WORLD. The screen is choosing a car FOR a world, and the one
	thing the shipping page never said on it is which world that is, so a player who pressed the
	wrong card on the screen before had nothing here to tell them. Its backpack icon goes (a bag
	next to a place name says nothing), and the readout is given the width the artist gave the
	search bar, because it holds a name as long as FUTURISTIC CITY where the kit's held five
	characters. The search takes the rest of the bar, worked out from the bar's own numbers.

	=== FOUR COLUMNS, NOT THE KIT'S FIVE =====================================================

	The cars inventory's cards, drawn the same size here: `KitGrowth.columns` rebuilds the grid four
	across and grows the card and its text caps to match (about 1.28). Dylan asked for bigger cards on
	both screens, for a better view of the cars. No car is built here; `Modules/CarViewportGrid` puts
	them in at runtime.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)
local KitGrowth = require(ReplicatedStorage.shared.Modules.KitGrowth)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage

local PAGE_NAME = "StartCar" -- StartCarConfig.PageName
local KIT_FRAME = "InventoryUI"

--- The kit's names, and ours. The card's names match `BuildDealershipV2`'s on purpose: it is the
--- same kit card, and one set of paths across both screens is one set to remember.
local KIT_CELL = "Template"
local CELL_NAME = "CarCard"
local KIT_FACE = "Template" -- the face is called the same thing as the cell it is in
local FACE_NAME = "Face"

--- What the page reads off a card. Every one of these is a path in `PagesV2/StartCar`, and
--- `Btns.EquipBtn` is also the tutorial's `TutorialConfig.StartCarPathV2`.
local RARITY_LABEL = "Rarity"
local RARITY_TINT = "Tint"
local SELECTED_CHIP = "Selected"
--[[ NOT `Active`: a child of a GuiObject may not be named after one of its properties, because the
	property wins the lookup. `BuildDealershipV2` found that out in a playtest. ]]
local ACTIVE_STROKE = "Rim"
local BTNS = "Btns"
local ACTION_BTN = "EquipBtn"
local STATE_BTN = "EquippedBtn"
local NOTE_NAME = "Note"

--- Cards across the grid. See "Four columns" in the header.
local COLUMNS = KitGrowth.CarColumns

--- The kit's top-bar actions, which have no feature behind them here. See the header.
local TOPBAR_DROPS = { "EquipBestBtn", "DeleteBtn" }
local SEARCH_BAR = "SearchBar"
local STORAGE = "Storage"

--[[ The SELECTED chip, in fractions of the card's face: the low band `BuildDealershipV2` puts its
	level chip in, clear of `Title` (which starts at 0.744), because the car is letterboxed and its
	bottom edge is empty road.

	AS WIDE AS `Rarity` AND CENTRED LIKE IT, which the render decided. `TextScaled` sizes a label to
	its own string and SELECTED is as long as SUPERCAR, so the first cut (0.62 wide, left-aligned
	like the level chip) set it at two thirds of the rarity's size and it read as a footnote on the
	one card the screen is meant to point out. Same box, same word length, same size. ]]
local CHIP_BOTTOM = 0.72
local CHIP_WIDTH = 0.9
local CHIP_HEIGHT = 0.15

--- How much of the `Storage` readout the caption takes once its icon is gone. The artist's own
--- inset, mirrored: the title box was 0.46 beside a 0.22 icon, centred in a list.
local CAPTION_FILL = 0.9

--- The kit's own placeholders, so a freshly built page reads as the finished screen in the Explorer.
--- The page writes every one of these on open.
local TITLE_TEXT = "Select Car"
local CAPTION_PLACEHOLDER = "CITY"
local NAME_PLACEHOLDER = "CAMARO"
local RARITY_PLACEHOLDER = "SEDAN"
local ACTION_PLACEHOLDER = "DRIVE"
local SELECTED_PLACEHOLDER = "SELECTED"
local NOTE_PLACEHOLDER = "No cars match that"

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

--[[ EVEN ROOM ROUND WHAT SITS IN A BAR, exactly as on the cars inventory: the kit's list packs its
	children edge to edge, so the widened search's outline sat on the bar's rim at both ends. The
	kit's vertical margin is the unit, measured to the OUTLINE, so the gap between two children is
	the margin plus one more outline. Fractions of the bar's WIDTH, through the page's own aspect
	constraint so they hold at every screen size. ]]
local function barSpacing(page: GuiObject, bar: GuiObject, child: GuiObject): (number?, number?)
	local aspect = page:FindFirstChildOfClass("UIAspectRatioConstraint")
	if not aspect or bar.Size.Y.Scale == 0 then
		return nil, nil
	end
	local widthInHeights = aspect.AspectRatio * bar.Size.X.Scale / bar.Size.Y.Scale
	local height = child.Size.Y.Scale
	local stroke = child:FindFirstChildOfClass("UIStroke")
	--- A scaled stroke is a fraction of the child's short side, which in a bar is its height.
	local outline = if stroke and stroke.Enabled and stroke.StrokeSizingMode == Enum.StrokeSizingMode.ScaledSize
		then stroke.Thickness * height
		else 0
	local margin = (1 - height) / 2
	return margin / widthInHeights, (margin + outline) / widthInHeights
end

--[[ WIDENING A BAR WIDENS EVERYTHING IN IT, exactly as on the cars inventory: the kit places `Icon`
	and `TextBox` in fractions of the bar's WIDTH, so the doubled bar drew the magnifier twice as wide
	as it is tall. Every child's X is scaled back to the pixels the artist drew from the left edge,
	then the box alone is stretched out to the kit's own right margin. ]]
local function holdBarContents(bar: GuiObject, kitWidth: number, box: GuiObject?)
	local k = kitWidth / bar.Size.X.Scale
	if k >= 1 then
		return
	end
	for _, child in bar:GetChildren() do
		if child:IsA("GuiObject") then
			local size, position = child.Size, child.Position
			child.Size = UDim2.new(size.X.Scale * k, size.X.Offset, size.Y.Scale, size.Y.Offset)
			child.Position = UDim2.new(position.X.Scale * k, position.X.Offset, position.Y.Scale, position.Y.Offset)
		end
	end
	if box then
		local left = box.Position.X.Scale - box.AnchorPoint.X * box.Size.X.Scale
		local right = left + box.Size.X.Scale
		local margin = k - right -- the kit's right margin, in the new bar's fractions
		local width = 1 - margin - left
		box.Size = UDim2.new(width, box.Size.X.Offset, box.Size.Y.Scale, box.Size.Y.Offset)
		box.Position = UDim2.new(left + box.AnchorPoint.X * width, box.Position.X.Offset, box.Position.Y.Scale, box.Position.Y.Offset)
	end
end

--- The saturated end of a gradient, which is the end a rim wants: the light end of the kit's ramps
--- is the highlight and reads as white at one pixel wide.
local function deepEnd(gradient: UIGradient?): Color3?
	if not gradient then
		return nil
	end
	local stops = gradient.Color.Keypoints
	return stops[#stops].Value
end

return {
	Description = "Build StarterGui.MainUIV2.Pages.StartCar (SELECT CAR, the third press of Play) from the Cartoony Kit's InventoryUI: a four-column card grid whose Equip button becomes DRIVE, a rim and a SELECTED chip for the stored car, and the storage readout turned into the world's name. Rebuilds the page every run.",
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
		local grid = list and list:FindFirstChildOfClass("UIGridLayout")
		if not (main and main:IsA("GuiObject") and list and grid) then
			out:error(string.format("The kit's %s has no `Main.ScrollingFrame` with a UIGridLayout; there is no grid to fill.", KIT_FRAME))
			page:Destroy()
			return
		end

		-- === The header =====================================================
		local header = page:FindFirstChild("Header")
		local headerTitle = header and header:FindFirstChild("Title")
		if not (headerTitle and headerTitle:IsA("TextLabel")) then
			out:error(string.format("The kit's %s has no `Header.Title`.", KIT_FRAME))
			page:Destroy()
			return
		end
		headerTitle.Text = TITLE_TEXT

		-- === The top bar ====================================================
		local topBar = page:FindFirstChild("TopBar")
		local dropped = 0
		local searchBar = topBar and topBar:FindFirstChild(SEARCH_BAR)
		local storage = topBar and topBar:FindFirstChild(STORAGE)
		if topBar then
			for _, name in TOPBAR_DROPS do
				local button = topBar:FindFirstChild(name)
				if button then
					button:Destroy()
					dropped += 1
				end
			end

			--[[ The readout takes the search bar's authored width and the search takes what is
				left. Read BEFORE either is written, because the second line overwrites the number
				the first one needs. Both are children of a horizontal, centred `UIListLayout`, so they
				are sized rather than placed, and what the even margins leave splits evenly at the
				ends. ]]
			local layout = topBar:FindFirstChildOfClass("UIListLayout")
			if searchBar and searchBar:IsA("GuiObject") and storage and storage:IsA("GuiObject") and layout then
				local kitWidth = searchBar.Size.X.Scale
				local edge, gap = barSpacing(page, topBar :: GuiObject, searchBar)
				if edge and gap then
					layout.Padding = UDim.new(gap, 0)
					layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
				else
					edge, gap = 0, layout.Padding.Scale
					out:warn(string.format("The kit's %s has no UIAspectRatioConstraint; the top bar keeps the kit's spacing.", KIT_FRAME))
				end
				local captionWidth = math.max(storage.Size.X.Scale, kitWidth)
				storage.Size = UDim2.new(captionWidth, 0, storage.Size.Y.Scale, 0)
				searchBar.Size = UDim2.new(1 - captionWidth - gap - 2 * edge, 0, searchBar.Size.Y.Scale, 0)
				holdBarContents(searchBar, kitWidth, searchBar:FindFirstChildWhichIsA("TextBox"))
			end

			--[[ THE KIT TYPED THE PROMPT INTO THE BOX, exactly as on the cars inventory: `Text` is
				"Search...", so a page filtering on it opens filtering for the word "search". ]]
			local box = searchBar and searchBar:FindFirstChildWhichIsA("TextBox")
			if box then
				if box.PlaceholderText == "" then
					box.PlaceholderText = box.Text
				end
				box.Text = ""
				box.ClearTextOnFocus = false
			else
				out:warn(string.format("`%s` has no TextBox; the list cannot be searched.", SEARCH_BAR))
			end

			if storage then
				local icon = storage:FindFirstChild("Icon")
				if icon then
					icon:Destroy()
				end
				local caption = storage:FindFirstChild("Title")
				if caption and caption:IsA("TextLabel") then
					caption.Text = CAPTION_PLACEHOLDER
					caption.Size = UDim2.new(CAPTION_FILL, 0, caption.Size.Y.Scale, 0)
				else
					out:warn(string.format("`%s` has no Title; the page cannot say which world it is for.", STORAGE))
				end
			end
		else
			out:warn(string.format("The kit's %s has no `TopBar`; there is no search and no world caption.", KIT_FRAME))
		end

		-- === The card =======================================================
		local kept: GuiObject? = nil
		local spares = 0
		for _, child in list:GetChildren() do
			if child.Name ~= KIT_CELL or not child:IsA("GuiObject") then
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
			out:error(string.format("The kit's %s grid has no `%s` cell to build from.", KIT_FRAME, KIT_CELL))
			page:Destroy()
			return
		end

		local cell = kept :: GuiObject
		cell.Name = CELL_NAME

		-- === The grid =======================================================
		--- Four across, card and text caps grown to match. See "Four columns" in the header.
		KitGrowth.columns(grid, cell, COLUMNS)

		local face = cell:FindFirstChild(KIT_FACE)
		local btns = cell:FindFirstChild(BTNS)
		if not (face and face:IsA("GuiObject") and btns and btns:IsA("GuiObject")) then
			out:error(string.format("`%s` is missing its face or its `%s` row.", CELL_NAME, BTNS))
			page:Destroy()
			return
		end
		face.Name = FACE_NAME

		local rarity = face:FindFirstChild(RARITY_LABEL)
		local cardTitle = face:FindFirstChild("Title")
		if not (rarity and rarity:IsA("TextLabel") and cardTitle and cardTitle:IsA("TextLabel")) then
			out:error(string.format("`%s.%s` is missing `%s` or `Title`.", CELL_NAME, FACE_NAME, RARITY_LABEL))
			page:Destroy()
			return
		end
		cardTitle.Text = NAME_PLACEHOLDER
		rarity.Text = RARITY_PLACEHOLDER

		local tint = rarity:FindFirstChildOfClass("UIGradient")
		if tint then
			tint.Name = RARITY_TINT
		else
			out:warn(string.format("`%s.%s` has no UIGradient; every rarity will read in one colour.", FACE_NAME, RARITY_LABEL))
		end

		-- === The button =====================================================
		local action = btns:FindFirstChild(ACTION_BTN)
		if not (action and action:IsA("GuiButton")) then
			out:error(string.format("`%s.%s` has no `%s` to press.", CELL_NAME, BTNS, ACTION_BTN))
			page:Destroy()
			return
		end
		action.Visible = true
		local actionTitle = action:FindFirstChild("Title")
		if actionTitle and actionTitle:IsA("TextLabel") then
			actionTitle.Text = ACTION_PLACEHOLDER
		end
		local actionRamp = action:FindFirstChildOfClass("UIGradient")

		local state = btns:FindFirstChild(STATE_BTN)
		if state then
			state:Destroy()
		end

		-- === The SELECTED chip ==============================================
		--[[ A clone of `Rarity`, so it carries the face, the outline and the size constraint the rest
			of the card wears, and its ramp swapped for the button's. ]]
		local chip = rarity:Clone()
		chip.Name = SELECTED_CHIP
		chip.Text = SELECTED_PLACEHOLDER
		chip.AnchorPoint = Vector2.new(0.5, 1)
		chip.Position = UDim2.fromScale(0.5, CHIP_BOTTOM)
		chip.Size = UDim2.fromScale(CHIP_WIDTH, CHIP_HEIGHT)
		chip.ZIndex = rarity.ZIndex + 1
		chip.Visible = false
		local chipTint = chip:FindFirstChild(RARITY_TINT)
		if chipTint and chipTint:IsA("UIGradient") and actionRamp then
			chipTint.Color = actionRamp.Color
		elseif not actionRamp then
			out:warn(string.format("`%s.%s` has no gradient; SELECTED keeps the rarity's colour.", BTNS, ACTION_BTN))
		end
		chip.Parent = face

		-- === The rim ========================================================
		local green = deepEnd(actionRamp)
		local rim: UIStroke? = nil
		for _, stroke in face:GetChildren() do
			if stroke:IsA("UIStroke") then
				local clone = stroke:Clone()
				clone.Name = ACTIVE_STROKE
				clone.Enabled = false
				if green then
					clone.Color = green
				end
				clone.Parent = face
				rim = clone
				break
			end
		end
		if not rim then
			out:warn(string.format("`%s` has no UIStroke to copy; the selected card will have no rim.", FACE_NAME))
		end

		-- === The empty line =================================================
		--[[ Over the well rather than in the grid, for `BuildDealershipV2`'s reason: a note stamped
			as a cell is a card-shaped hole the layout flows the rest of the list around. ]]
		local note = headerTitle:Clone()
		note.Name = NOTE_NAME
		note.Text = NOTE_PLACEHOLDER
		note.TextXAlignment = Enum.TextXAlignment.Center
		note.TextWrapped = true
		note.Visible = false
		note.AnchorPoint = Vector2.new(0.5, 0.5)
		note.Position = UDim2.fromScale(0.5, 0.5)
		note.Size = UDim2.fromScale(0.9, 0.33)
		note.ZIndex = list.ZIndex + 1
		note.Parent = main

		--- Bigger than the kit, text caps included. See `Modules/KitGrowth`.
		KitGrowth.apply(page, KitGrowth.Pages)
		page.Parent = pages

		--[[ THE DETAIL WINGS, which are one builder shared by both car screens
			(`BuildCarDetailV2.Panel`). They have to be made HERE as well as by their own command,
			because this one destroys and remakes the page on every run and would otherwise throw
			them away; and they are made LAST, after the growth above, so the labels they clone are
			already the page's own size and every text cap they are given is in the pixels the page
			is actually drawn at.

			LOOKED UP RATHER THAN REQUIRED AT THE TOP: a place whose `CommandRunnerScripts` does not
			have that command still builds a working page, and says out loud what it is missing. ]]
		local detailCommand = script.Parent:FindFirstChild("BuildCarDetailV2")
		local panel = detailCommand and detailCommand:FindFirstChild("Panel")
		if panel and panel:IsA("ModuleScript") then
			local built, message = require(panel).build(page)
			if built then
				out:print(message)
			else
				out:warn(message)
			end
		else
			out:warn("No `BuildCarDetailV2.Panel` beside this command; the page is built without its detail wings.")
		end

		out:print(string.format("Built %s.Pages.%s from the kit's %s.", SCREEN_NAME, PAGE_NAME, KIT_FRAME))
		out:print(
			string.format(
				"Card `%s`: %d spare cells dropped, face renamed `%s`, `%s` deleted, `%s` and `%s` added.",
				CELL_NAME,
				spares,
				FACE_NAME,
				STATE_BTN,
				SELECTED_CHIP,
				ACTIVE_STROKE
			)
		)
		out:print(
			string.format(
				"Top bar: %d kit buttons dropped, search %.3f, world caption %.3f. `%s` sits over the well.",
				dropped,
				searchBar and searchBar:IsA("GuiObject") and searchBar.Size.X.Scale or 0,
				storage and storage:IsA("GuiObject") and storage.Size.X.Scale or 0,
				NOTE_NAME
			)
		)

		pcall(function()
			props:SetSelection({ page })
		end)
	end,
} :: Types.ScriptModule
