--[[
	BuildDealershipV2: Command Runner command

	Builds `StarterGui.MainUIV2.Pages.Dealership` out of the Cartoony Kit's `InventoryUI`. Phase 3 of
	`docs/NewUI-Migration-Plan.md`; the running record is `docs/NewUI-Migration-Notes.md`.

	Run `BuildMainUIV2` first: this fills in a screen that already exists rather than creating one.
	`Pages.Dealership` is destroyed and made again on every run, and nothing else under `Pages` is
	touched, so it is safe beside the other Phase 3 commands and safe to re-run.

	THE PAGE IS THE CARS INVENTORY and it is now the grid's `Cars` cell, the one button in the new
	HUD that wears our own art rather than a kit icon. The shipping page's header is the long version
	of what it does; nothing about the FEATURE changed here.

	=== THE KIT'S CARD IS OUR CARD WITH THREE LABELS CHANGED ==================================

	One cell holds a face and a button:

	    Template            the grid cell
	      Template          the card face: Rarity on top, Icon filling it, Title along the bottom
	      Btns              EquipBtn (green, "Equip") and EquippedBtn (grey with a slash, hidden)

	Which is a car card: the rarity word we already print (`Modules/CarRarity`), the car's name, a
	picture, and a press. The artist even drew both button states, and they are the two this screen
	needs: a press that does something, and a card that is already what you are asking for.

	SO THE CELL IS RENAMED `CarCard`, THE FACE IS RENAMED `Face`, and the rest of this command is
	three things the kit does not draw and one it draws twice.

	=== WHAT IS ADDED, AND WHY ================================================================

	  • `Star`, the favourite chip. It has to be here because this screen is the only place in the
	    game a car can be starred, and a star is what makes the sell lot ask twice before it takes
	    one.
	  • `Level`, the `LVL 3` chip, which the page leaves empty on every car nobody has driven far in.

	    BOTH SIT OVER THE CAR'S LOWER CORNERS, and that is the shipping card's own argument: the
	    picture is the biggest thing on a card this size, the car is letterboxed, and its bottom
	    corners are empty road. The first version of this put the level on the rarity line and the
	    star beside it, and the render said no twice over: `TextScaled` shrinks a longer string, so
	    `SUPERCAR · LVL 2` came out at half the size of `COUPE` two cards along, and the star had to
	    cut the rarity's box to 0.56 to fit beside it. Each chip in its own box is each chip at its
	    own size, and the artist's `Rarity` keeps the width it was drawn with.
	  • `Rim`, a stroke on the face in the kit's own green, off by default. It marks the car this
	    screen is ABOUT: the one on the bay you walked up to, or the one standing in the street. The
	    green is harvested off `EquipBtn`'s gradient rather than typed in, so a retint of the kit
	    moves the rim with it.
	  • `Note`, the empty-list line, over `Main` rather than in the list. Every other V2 page makes
	    its note a row, and a row in a GRID is a card-shaped hole in the middle of the layout. This
	    one is a label across the well.

	=== WHAT IS REMOVED =======================================================================

	`EquipBestBtn` and `DeleteBtn`, the kit's two top-bar actions. There is no "equip best" on a
	screen where the verb is "put this car in the street", and deleting a car is `SellService`'s job
	at a location you drive to, which the shipping page's own rewrite note is emphatic about. The
	same call `BuildShopV2` made about `ServerLuck` and `CratePack`: the kit master still has them.

	The search bar then takes the width they leave, worked out from the artist's own numbers, so the
	top bar stays full rather than ending halfway across with a gap.

	=== FOUR COLUMNS, NOT THE KIT'S FIVE =====================================================

	Dylan, 2026-09-16: "make the cards a little bit bigger so that we have a better view of the
	cars". The page is already as big as a page gets, so the cards grow by dropping a column, the
	smallest step that still fills the row. `KitGrowth.columns` does it, and `BuildStartCarV2` calls
	it too: the four cells share what five did, and the height and every text cap on the card grow
	by the same factor (about 1.28), so a card is the kit's card drawn bigger.

	NO CAR IS BUILT HERE. `Modules/CarViewportGrid` puts the cars in the cards at runtime, a row
	either side of the scroll window and no more, and `PagesV2/Dealership` hands it the geometry.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)
local KitGrowth = require(ReplicatedStorage.shared.Modules.KitGrowth)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage

local PAGE_NAME = "Dealership"
local KIT_FRAME = "InventoryUI"

--- The kit's names, and ours.
local KIT_CELL = "Template"
local CELL_NAME = "CarCard"
local KIT_FACE = "Template" -- the face is called the same thing as the cell it is in
local FACE_NAME = "Face"

--- What the page reads off a card. Every one of these is a path in `PagesV2/Dealership`.
local RARITY_LABEL = "Rarity"
local RARITY_TINT = "Tint"
local STAR_NAME = "Star"
local LEVEL_LABEL = "Level"
--[[ NOT `Active`, which is what this was called until the first playtest threw on it: `Active` is
	a PROPERTY of every GuiObject, and an instance's property wins over its child, so `Face.Active`
	answered `true` rather than the stroke. A child of a GuiObject may not be named after one of its
	properties. ]]
local ACTIVE_STROKE = "Rim"
local BTNS = "Btns"
local ACTION_BTN = "EquipBtn"
local STATE_BTN = "EquippedBtn"
local NOTE_NAME = "Note"

--- The kit's top-bar actions, which have no feature behind them here. See the header.
local TOPBAR_DROPS = { "EquipBestBtn", "DeleteBtn" }
local SEARCH_BAR = "SearchBar"
local STORAGE = "Storage"

--- The gold star, `UIAssets.Inventory.Favorite`. Read rather than typed, so it cannot drift.
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)

--- Cards across the grid. See "Four columns" in the header.
local COLUMNS = KitGrowth.CarColumns

--[[ The two chips, in fractions of the card's face.

	A FIFTH OF THE FACE for the star. Small enough to read as a chip on a picture rather than as a
	control in its own right, big enough to stay a touch target on a phone: at 1080p the face is
	about 250px, so the chip is 55 and the finger target is the chip plus the card's own gap.

	`CHIP_BOTTOM` is where they both sit: clear of `Title`, which starts at 0.744, and low enough to
	be over the road rather than over the car. ]]
local STAR_SIZE = 0.22
local CHIP_INSET = 0.035
local CHIP_BOTTOM = 0.72
local LEVEL_WIDTH = 0.34
local LEVEL_HEIGHT = 0.15

--- The kit's own placeholders, so a freshly built page reads as the finished screen in the Explorer.
local TITLE_TEXT = "My Cars" -- InventoryConfig.Text.TitleInventory, in the kit's sentence case
local STORAGE_PLACEHOLDER = "12 cars"
local NAME_PLACEHOLDER = "CAMARO"
local RARITY_PLACEHOLDER = "SEDAN"
local ACTION_PLACEHOLDER = "Spawn"
local STATE_PLACEHOLDER = "In the street"
local NOTE_PLACEHOLDER = "Steal a car first"

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

--[[ EVEN ROOM ROUND WHAT SITS IN A BAR. The kit's list packs its children edge to edge, so once the
	search fills the bar its outline sits on the bar's own rim at both ends while there is a sliver
	above and below. The kit's vertical margin is the unit, and it is measured to the OUTLINE: the
	children's strokes are outside their boxes, so the ends need the margin and the gap between two
	children needs the margin plus one more outline to show the same strip of blue.

	Returns the end margin and the gap in fractions of the bar's WIDTH. The bar's width in heights
	comes off the page's own aspect constraint, so the numbers hold at every screen size. ]]
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

--[[ WIDENING A BAR WIDENS EVERYTHING IN IT. The kit places `Icon` and `TextBox` in fractions of
	the bar's WIDTH, so a bar made 2.5 times wider drew the magnifier 90px wide and 36 tall, and slid
	it and the prompt right. Every child's X is scaled back by the same factor, which pins each one
	to the pixels the artist drew from the bar's left edge, and then the box alone is stretched out
	to the kit's own right margin, so the new width is room to type rather than empty bar. ]]
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
	Description = "Build StarterGui.MainUIV2.Pages.Dealership (the cars inventory) from the Cartoony Kit's InventoryUI: a four-column card grid whose Equip button becomes the spawn and park verb, plus a favourite star and an active rim. Rebuilds the page every run.",
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
		--- The page renames itself on every open: bay mode and inventory mode are two screens with
		--- two titles (`InventoryConfig.Text`). This is only what the Explorer shows.
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

			--[[ The bar is a horizontal `UIListLayout`, so the search bar is widened rather than
				repositioned: it takes everything the two buttons left less the even margins, and
				`Storage` stays the width the artist drew. The list is centred, so what is left over
				splits into the same margin at both ends. Every number here is read off the bar. ]]
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
				local room = 1 - storage.Size.X.Scale - gap - 2 * edge
				searchBar.Size = UDim2.new(math.max(kitWidth, room), 0, searchBar.Size.Y.Scale, 0)
				holdBarContents(searchBar, kitWidth, searchBar:FindFirstChildWhichIsA("TextBox"))
			end

			--[[ THE KIT TYPED THE PROMPT INTO THE BOX. `TextBox.Text` is "Search...", not
				`PlaceholderText`, so a page that filters on the box's text opens filtering for the
				word "search" and shows an empty collection. Moved here rather than worked around in
				the page, because a prompt that is really text is wrong in the Explorer too: click
				the box in a playtest and you are editing the word. ]]
			local box = searchBar and searchBar:FindFirstChildWhichIsA("TextBox")
			if box then
				if box.PlaceholderText == "" then
					box.PlaceholderText = box.Text
				end
				box.Text = ""
				box.ClearTextOnFocus = false
			else
				out:warn(string.format("`%s` has no TextBox; the collection cannot be searched.", SEARCH_BAR))
			end

			local storageTitle = storage and storage:FindFirstChild("Title")
			if storageTitle and storageTitle:IsA("TextLabel") then
				storageTitle.Text = STORAGE_PLACEHOLDER
			end
		else
			out:warn(string.format("The kit's %s has no `TopBar`; there is no search and no count.", KIT_FRAME))
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

		--- One name for the one gradient the page writes to, exactly as on the market's listing row.
		local tint = rarity:FindFirstChildOfClass("UIGradient")
		if tint then
			tint.Name = RARITY_TINT
		else
			out:warn(string.format("`%s.%s` has no UIGradient; every rarity will read in one colour.", FACE_NAME, RARITY_LABEL))
		end

		-- === The two chips ==================================================
		local star = Instance.new("ImageButton")
		star.Name = STAR_NAME
		star.BackgroundTransparency = 1
		star.Image = UIAssets.url(UIAssets.Inventory.Favorite)
		star.ScaleType = Enum.ScaleType.Fit
		star.AutoButtonColor = false
		--- Centre-anchored so the hover grows it from its middle (house rule); the box is where a
		--- bottom-right anchor at `1 - CHIP_INSET, CHIP_BOTTOM` put it.
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.fromScale(1 - CHIP_INSET - STAR_SIZE / 2, CHIP_BOTTOM - STAR_SIZE / 2)
		star.Size = UDim2.fromScale(STAR_SIZE, STAR_SIZE)
		--- Over the picture, which is what a chip is.
		star.ZIndex = rarity.ZIndex + 1
		star.Parent = face

		--[[ The level, in the artist's own type: a clone of `Rarity` rather than a label built here,
			so it carries the face, the rim and the size constraint the rest of the card wears. Its
			gradient goes, because a level is not a rarity and two coloured captions on one card is
			a card with two headlines. ]]
		local level = rarity:Clone()
		level.Name = LEVEL_LABEL
		level.Text = ""
		level.TextXAlignment = Enum.TextXAlignment.Left
		level.AnchorPoint = Vector2.new(0, 1)
		level.Position = UDim2.fromScale(CHIP_INSET, CHIP_BOTTOM)
		level.Size = UDim2.fromScale(LEVEL_WIDTH, LEVEL_HEIGHT)
		level.ZIndex = star.ZIndex
		local levelTint = level:FindFirstChild(RARITY_TINT)
		if levelTint then
			levelTint:Destroy()
		end
		level.Parent = face
		--[[ NOT TAGGED `UIButton` HERE. The page tags it, because the tag is what gives a button the
			hover scale and the press sound, and `PrepKitTemplate` has already been over this frame:
			a tag added at build time would be the only one in the kit that did not come from there.
			The page also has to wire it, and a chip nothing is listening to is worse than no chip. ]]

		-- === The active rim =================================================
		local green = deepEnd(btns:FindFirstChild(ACTION_BTN) and btns[ACTION_BTN]:FindFirstChildOfClass("UIGradient"))
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
			out:warn(string.format("`%s` has no UIStroke to copy; the active card will have no rim.", FACE_NAME))
		elseif not green then
			out:warn(string.format("`%s.%s` has no gradient to take a colour from; the rim is the kit's white.", BTNS, ACTION_BTN))
		end

		-- === The two button states ==========================================
		local action = btns:FindFirstChild(ACTION_BTN)
		local state = btns:FindFirstChild(STATE_BTN)
		if not (action and action:IsA("GuiButton") and state and state:IsA("GuiObject")) then
			out:error(string.format("`%s.%s` is missing `%s` or `%s`.", CELL_NAME, BTNS, ACTION_BTN, STATE_BTN))
			page:Destroy()
			return
		end
		action.Visible = true
		state.Visible = false
		local actionTitle = action:FindFirstChild("Title")
		if actionTitle and actionTitle:IsA("TextLabel") then
			actionTitle.Text = ACTION_PLACEHOLDER
		end
		local stateTitle = state:FindFirstChild("Title")
		if stateTitle and stateTitle:IsA("TextLabel") then
			stateTitle.Text = STATE_PLACEHOLDER
		end

		-- === The empty line =================================================
		--[[ Over the well rather than in the grid. A note stamped as a CELL would be a card-shaped
			hole the layout flows the rest of the collection around, which is the one thing it must
			not be: the note only ever shows when there is nothing else in there. ]]
		local note = headerTitle:Clone()
		note.Name = NOTE_NAME
		note.Text = NOTE_PLACEHOLDER
		note.TextXAlignment = Enum.TextXAlignment.Center
		note.TextWrapped = true
		note.Visible = false
		note.AnchorPoint = Vector2.new(0.5, 0.5)
		note.Position = UDim2.fromScale(0.5, 0.5)
		--- A third of the well, so one short sentence is set at about the size of a card's name
		--- rather than as a headline across an empty panel.
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
				"Card `%s`: %d columns at %.4f x %.4f, %d spare cells dropped, face renamed `%s`, `%s`, `%s` and `%s` added over the car's lower corners, rarity gradient named `%s`.",
				CELL_NAME,
				COLUMNS,
				grid.CellSize.X.Scale,
				grid.CellSize.Y.Scale,
				spares,
				FACE_NAME,
				STAR_NAME,
				LEVEL_LABEL,
				ACTIVE_STROKE,
				RARITY_TINT
			)
		)
		out:print(
			string.format(
				"Top bar: %d kit buttons dropped, search widened to %.2f, `%s` kept. `%s` sits over the well.",
				dropped,
				searchBar and searchBar:IsA("GuiObject") and searchBar.Size.X.Scale or 0,
				STORAGE,
				NOTE_NAME
			)
		)

		pcall(function()
			props:SetSelection({ page })
		end)
	end,
} :: Types.ScriptModule
