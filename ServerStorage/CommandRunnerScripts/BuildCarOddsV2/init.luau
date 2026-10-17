--[[
	BuildCarOddsV2: Command Runner command

	Builds `StarterGui.MainUIV2.Pages.CarOdds` out of the Cartoony Kit's `IndexUI`: the random car's
	odds as a page in the middle of the screen, opened by the ODDS button on the offer card
	(`BuildRandomCarV2` gives that button `Page = "CarOdds"`).

	Run `BuildMainUIV2` first: this fills in a screen that already exists rather than creating one.
	`Pages.CarOdds` is destroyed and made again on every run, and nothing else under `Pages` is touched.

	=== WHY A PAGE (2026-10-15) ===============================================================

	Roblox's paid random items policy wants every outcome of a pull with its own chance, behind a
	button that says what it is. That list was a tooltip beside the card first: ten cars, the paint
	rows and the notes in 260 pixels, which Dylan found hard to read. A page has room for each car as
	a card with the car itself in it, which is the Index page's shape exactly, so this is that page's
	build with the collection taken out and the odds put in.

	=== WHAT THE KIT'S INDEX BECOMES ===========================================================

	    Header.Title        ODDS
	    Header.World        `Header.Title`'s type at the close button's end: which world's odds these
	                        are (a pull rolls the world you are in)
	    Main.ScrollingFrame the grid, shortened to leave room for the note under it
	      CarCard           the kit card as `BuildIndexV2` dresses it: a `Tint` face, white `Rarity`
	                        word, the `Icon` box cleared for the car, and `Chance` where the Index
	                        prints a rate. The page stamps one per car AND one per paint colour.
	    Main.Note           one line under the grid: the factory-only cars and the rounding note
	    SideBtns            two tabs, CARS and PAINT, each with a `Tab` attribute. Two lists of ten
	                        and fifteen read better than one of twenty-five, and the kit's rail is
	                        already a column of filter buttons. Moved to the panel's LEFT: the offer
	                        card the page opens from sits against the right-hand edge, and the
	                        kit's rail on the right drew over it.

	The page (`PagesV2/CarOdds`) writes every word and colour from `RandomCarConfig` on each open, so
	the strings here are what the Explorer shows and nothing more.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)
local KitGrowth = require(ReplicatedStorage.shared.Modules.KitGrowth)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage

local PAGE_NAME = "CarOdds" -- RandomCarConfig.Odds.PageName
local KIT_FRAME = "IndexUI"

--- The kit's names, and ours. Every one of ours is a path in `PagesV2/CarOdds`.
local KIT_CELL = "Template"
local CELL_NAME = "CarCard"
local TINT_NAME = "Tint"
local WORLD_NAME = "World"
local NOTE_NAME = "Note"
local CHANCE_NAME = "Chance"
local RAIL_NAME = "SideBtns"
local TAB_ATTRIBUTE = "Tab"

--[[ The two tabs, top to bottom, and the kit rail button each is cut from (the artist's colours are
	kept: these are tabs, not rarities). A missing kit name falls back to whichever button is left. ]]
local TABS = {
	{ Tab = "Cars", Text = "CARS", From = "RareBtn" },
	{ Tab = "Paint", Text = "PAINT", From = "EpicBtn" },
}

--- How far the world name stops short of the close button, as `BuildIndexV2` places its count.
local WORLD_GUTTER = 0.5

--- The grid's share of `Main`; the note takes the strip under it.
local LIST_HEIGHT = 0.87
local NOTE_WIDTH = 0.94
local NOTE_HEIGHT = 0.11 -- two wrapped lines, so the note is not set smaller than the cards' type

--[[ `Chance`, in fractions of the card: centred over the lower part of the car, above the name. It
	is the number the page exists for, so it is set as big as the name under it. ]]
local CHANCE_Y = 0.665
local CHANCE_WIDTH = 0.9
local CHANCE_HEIGHT = 0.17

local RAMP_LIFT = 0.35

local TITLE_TEXT = "ODDS"
local WORLD_PLACEHOLDER = "WORLD 1"
local NAME_PLACEHOLDER = "CIVARO"
local CHANCE_PLACEHOLDER = "35.843%"
local NOTE_PLACEHOLDER = "ODDS ARE ROUNDED AND MAY NOT ADD UP TO 100%."

local NBSP = "\u{00A0}"

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

local function xSpan(gui: GuiObject): (number, number)
	local left = gui.Position.X.Scale - gui.AnchorPoint.X * gui.Size.X.Scale
	return left, left + gui.Size.X.Scale
end

local function ramp(colour: Color3): ColorSequence
	return ColorSequence.new(colour:Lerp(Color3.new(1, 1, 1), RAMP_LIFT), colour)
end

local function caption(text: string): string
	return (string.gsub(string.upper(text), " ", NBSP))
end

return {
	Description = "Build StarterGui.MainUIV2.Pages.CarOdds (the random car's odds, opened by the offer card's ODDS button) from the Cartoony Kit's IndexUI: a CarCard per outcome with a Chance line, CARS and PAINT tabs on the rail, the world in the header and a note under the grid. Rebuilds the page every run.",
	Tags = { "UI", "NewUI" },
	AutoRecordChanges = true,

	Arguments = {} :: Types.ArgumentType,

	Run = function(props: Types.Props, _arguments: Types.ArgumentResult)
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

		local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)

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
			out:error(string.format("The kit's %s has no `Main.ScrollingFrame` with a UIGridLayout.", KIT_FRAME))
			page:Destroy()
			return
		end

		-- === The header =====================================================
		local header = page:FindFirstChild("Header")
		local headerTitle = header and header:FindFirstChild("Title")
		local closeBtn = header and header:FindFirstChild("CloseBtn")
		if not (headerTitle and headerTitle:IsA("TextLabel") and closeBtn and closeBtn:IsA("GuiObject")) then
			out:error(string.format("The kit's %s has no `Header.Title` and `Header.CloseBtn`.", KIT_FRAME))
			page:Destroy()
			return
		end
		headerTitle.Text = TITLE_TEXT

		local _titleLeft, titleRight = xSpan(headerTitle)
		local closeLeft = xSpan(closeBtn)
		local right = closeLeft - WORLD_GUTTER * closeBtn.Size.X.Scale
		local world = headerTitle:Clone()
		world.Name = WORLD_NAME
		world.Text = WORLD_PLACEHOLDER
		world.TextXAlignment = Enum.TextXAlignment.Right
		world.AnchorPoint = Vector2.new(1, headerTitle.AnchorPoint.Y)
		world.Size = UDim2.new(math.max(0, right - titleRight), 0, headerTitle.Size.Y.Scale, 0)
		world.Position = UDim2.new(right, 0, headerTitle.Position.Y.Scale, 0)
		world.Parent = header

		-- === The card =======================================================
		local kept: GuiObject? = nil
		for _, child in list:GetChildren() do
			if child.Name ~= KIT_CELL or not child:IsA("GuiObject") then
				continue
			end
			if kept then
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
		local card = kept :: GuiObject
		card.Name = CELL_NAME

		local rarity = card:FindFirstChild("Rarity")
		local cardTitle = card:FindFirstChild("Title")
		local icon = card:FindFirstChild("Icon")
		if not (rarity and rarity:IsA("TextLabel") and cardTitle and cardTitle:IsA("TextLabel") and icon and icon:IsA("ImageLabel")) then
			out:error(string.format("`%s` is missing `Rarity`, `Title` or `Icon`.", CELL_NAME))
			page:Destroy()
			return
		end

		local cardTint = card:FindFirstChildOfClass("UIGradient")
		if cardTint then
			cardTint.Name = TINT_NAME
			cardTint.Color = ramp(CarRarity.colourOf(1))
		else
			out:warn(string.format("`%s` has no UIGradient; every card will be the kit's white.", CELL_NAME))
		end
		for _, gradient in rarity:GetChildren() do
			if gradient:IsA("UIGradient") then
				gradient:Destroy()
			end
		end
		rarity.TextColor3 = Color3.new(1, 1, 1)
		rarity.Text = "COMMON"
		cardTitle.Text = NAME_PLACEHOLDER
		icon.Image = ""

		local chance = rarity:Clone()
		chance.Name = CHANCE_NAME
		chance.Text = CHANCE_PLACEHOLDER
		chance.TextXAlignment = Enum.TextXAlignment.Center
		chance.AnchorPoint = Vector2.new(0.5, 0.5)
		chance.Position = UDim2.fromScale(0.5, CHANCE_Y)
		chance.Size = UDim2.fromScale(CHANCE_WIDTH, CHANCE_HEIGHT)
		chance.Parent = card

		-- === The note under the grid ========================================
		list.AnchorPoint = Vector2.new(0.5, 0)
		list.Position = UDim2.fromScale(0.5, 0)
		list.Size = UDim2.fromScale(list.Size.X.Scale, LIST_HEIGHT)

		local note = cardTitle:Clone()
		note.Name = NOTE_NAME
		note.Text = NOTE_PLACEHOLDER
		note.TextWrapped = true
		note.TextXAlignment = Enum.TextXAlignment.Center
		note.AnchorPoint = Vector2.new(0.5, 0.5)
		note.Position = UDim2.fromScale(0.5, LIST_HEIGHT + (1 - LIST_HEIGHT) / 2)
		note.Size = UDim2.fromScale(NOTE_WIDTH, NOTE_HEIGHT)
		note.Parent = main

		-- === The tabs =======================================================
		local rail = page:FindFirstChild(RAIL_NAME)
		if not rail then
			out:error(string.format("The kit's %s has no `%s` rail for the tabs.", KIT_FRAME, RAIL_NAME))
			page:Destroy()
			return
		end
		local spare: { GuiButton } = {}
		for _, child in rail:GetChildren() do
			if child:IsA("GuiButton") then
				table.insert(spare, child)
			end
		end
		local made = {}
		for index, spec in TABS do
			local button: GuiButton? = rail:FindFirstChild(spec.From) :: GuiButton?
			local at = button and table.find(spare, button)
			if at then
				table.remove(spare, at)
			else
				button = table.remove(spare, 1)
			end
			if not button then
				out:error(string.format("The kit's %s rail has too few buttons for %d tabs.", KIT_FRAME, #TABS))
				page:Destroy()
				return
			end
			button.Name = spec.Tab .. "Btn"
			button.LayoutOrder = index
			button:SetAttribute(TAB_ATTRIBUTE, spec.Tab)
			local title = button:FindFirstChild("Title")
			if title and title:IsA("TextLabel") then
				title.Text = caption(spec.Text)
			end
			table.insert(made, button.Name)
		end
		for _, button in spare do
			button:Destroy()
		end
		--- Mirrored onto the panel's left. See the header.
		if rail:IsA("GuiObject") then
			rail.AnchorPoint = Vector2.new(1 - rail.AnchorPoint.X, rail.AnchorPoint.Y)
			rail.Position = UDim2.new(1 - rail.Position.X.Scale, -rail.Position.X.Offset, rail.Position.Y.Scale, rail.Position.Y.Offset)
		end

		KitGrowth.apply(page, KitGrowth.Pages)
		page.Parent = pages

		out:print(string.format("Built %s.Pages.%s from the kit's %s: header `%s`, card `%s` with `%s`, `Main.%s`, tabs %s.", SCREEN_NAME, PAGE_NAME, KIT_FRAME, WORLD_NAME, CELL_NAME, CHANCE_NAME, NOTE_NAME, table.concat(made, ", ")))

		pcall(function()
			props:SetSelection({ page })
		end)
	end,
} :: Types.ScriptModule
