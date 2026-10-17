--[[
	BuildIndexV2: Command Runner command

	Builds `StarterGui.MainUIV2.Pages.Index` out of the Cartoony Kit's `IndexUI`. Phase 3 of
	`docs/NewUI-Migration-Plan.md`; the running record is `docs/NewUI-Migration-Notes.md`.

	Run `BuildMainUIV2` first: this fills in a screen that already exists rather than creating one.
	`Pages.Index` is destroyed and made again on every run, and nothing else under `Pages` is touched,
	so it is safe beside the other Phase 3 commands and safe to re-run.

	THE PAGE IS THE CAR COLLECTION: one card per car in the game, the ones you have stolen drawn as
	the car and the rest as a black cut-out. The shipping page's header is the long version of what
	it is for; this is what the kit's shape changed about it.

	=== THE KIT'S INDEX IS ALREADY A COLLECTION SCREEN ========================================

	One card is a rarity word on top, a picture filling it, a name along the bottom, on a coloured
	sunray face. Beside the panel is a column of five rarity buttons. That is our collection with
	the words changed, so the card is kept as the artist drew it and renamed `CarCard`, and the spare
	cells go.

	THE FIVE BUTTONS ARE OUR FIVE BANDS, and that is a coincidence worth checking rather than
	assuming. `Modules/CarRarity` prints one word off `TrafficConfig.Bands` and there are five of those:
	BEATER, SEDAN, COUPE, SPORTS, SUPERCAR. So `Uncommon`, `Rare`, `Epic`, `Legendary` and `Mythic`
	are not renamed one for one; they are destroyed and one button is stamped per band off the first
	of them, in band order, top to bottom. A sixth band tomorrow is a sixth button with no edit here.
	Each carries a `Band` attribute, which is the page's whole contract with the rail.

	=== THE COLOUR MOVED FROM THE WORD TO THE CARD ============================================

	The kit colours both: a rainbow of card faces and a gradient on every rarity word, deliberately
	out of step with each other (a green `Uncommon` on an orange card). The artist's faces are
	decoration, since they follow the column rather than the rarity.

	Here the CARD wears the band's colour and the word goes white, which is how the kit draws its
	own `Common`. The card is the biggest coloured thing on the screen, so it is the one that should
	say what kind of car this is; a filtered grid then comes out one colour, the colour of the rail
	button that filtered it. Colouring the word too would put a purple word on a purple card.

	The Cars page (`PagesV2/Dealership`) colours the WORD, on a face the kit drew in one colour. Same
	module, same five colours, one on each screen's loudest surface. Both gradients are named `Tint`
	and both are two stops lifted towards white at the top, which is the shape the artist's own ramps
	have. The page repaints them from `CarRarity` on every build, so these values are only what the
	Explorer shows.

	=== WHAT IS ADDED, AND WHY ================================================================

	  • `Header.Count`, "12/43 STOLEN", in the band between the title and the close button. The
	    shipping page counts along a bottom bar the kit does not have, and the header's empty band is
	    exactly the shape of a line of type; `BuildMarketV2` puts its countdown in the same place for
	    the same reason. A clone of `Header.Title`, so it is the header's own face and rim.
	  • `Rate`, what a stolen car pays, over the car's lower right corner. The shipping slot prints it
	    and dropping it would be the migration quietly removing the one number on this screen worth
	    acting on. A clone of `Rarity` with its gradient taken off, so it is the card's own type. It
	    sits where `BuildDealershipV2` puts its level chip, over the empty road under the car.

	=== WHAT IS CHANGED ======================================================================

	  • `Icon` keeps its RECT and loses its picture. It is the box the car is drawn in
	    (`Modules/CarViewportGrid` lays a viewport over it at runtime), and the artist's placeholder
	    is a pink rabbit. The Cars page leaves its kit icon under the car as a fallback; on a screen
	    that is a catalogue of cars, a rabbit captioned CIVIC is worse than an empty card.
	  • `Rarity` loses its gradient (above) and is named in upper case, as is `Title`. Every word on
	    the Cars page is upper case and the same car is printed on both.

	=== WHAT IS NOT HERE =====================================================================

	The shipping page's world pager, search box and MAPS tab. The kit draws none of them, and the
	rail is the filter this art has; the notes carry the reasoning and what went with each.

	NO CAR IS BUILT HERE, and the cell keeps its authored scale: `KitPage` reads the `UIGridLayout`
	and owns the canvas, exactly as it does for the Cars page.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)
local KitGrowth = require(ReplicatedStorage.shared.Modules.KitGrowth)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage

local PAGE_NAME = "Index"
local KIT_FRAME = "IndexUI"

--- The kit's names, and ours. Every one of ours is a path in `PagesV2/Index`.
local KIT_CELL = "Template"
local CELL_NAME = "CarCard"
local RARITY_LABEL = "Rarity"
local TINT_NAME = "Tint"
local ICON_NAME = "Icon"
local RATE_NAME = "Rate"
local COUNT_NAME = "Count"
local RAIL_NAME = "SideBtns"
--- The attribute a rail button carries: its index into `TrafficConfig.Bands`.
local BAND_ATTRIBUTE = "Band"

--[[ How far the count stops short of the close button, as a fraction of that button's width. The
	same gutter `BuildMarketV2` leaves its clock, so two headers with something in the band read
	alike. ]]
local COUNT_GUTTER = 0.5

--[[ The rate chip, in fractions of the card. Over the car's lower right corner, clear of `Title`
	(which starts at 0.747) and inset from the rim by what `BuildDealershipV2` insets its chips.
	Wide, because it is right-aligned and `TextScaled` sizes it by height: `$1.2K/s` and `$6.0/s`
	come out at one type size. ]]
local RATE_INSET = 0.05
local RATE_BOTTOM = 0.735
local RATE_WIDTH = 0.62
local RATE_HEIGHT = 0.13

--- How much white goes into the top of a band's ramp. `PagesV2/Dealership`'s number, and the page
--- repaints with the same one.
local RAMP_LIFT = 0.35

--- The kit's own placeholders, so a freshly built page reads as the finished screen in the Explorer.
local TITLE_TEXT = "INDEX"
local COUNT_PLACEHOLDER = "12/43 STOLEN"
local NAME_PLACEHOLDER = "CIVIC"
local RATE_PLACEHOLDER = "$6.0/s"

local NBSP = "\u{00A0}"

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

local function xSpan(gui: GuiObject): (number, number)
	local left = gui.Position.X.Scale - gui.AnchorPoint.X * gui.Size.X.Scale
	return left, left + gui.Size.X.Scale
end

--- A band's colour as the ramp the kit's faces are drawn in. See the header.
local function ramp(colour: Color3): ColorSequence
	return ColorSequence.new(colour:Lerp(Color3.new(1, 1, 1), RAMP_LIFT), colour)
end

--- Upper case with every space unbreakable, which is what a TextScaled caption needs.
local function caption(text: string): string
	return (string.gsub(string.upper(text), " ", NBSP))
end

return {
	Description = "Build StarterGui.MainUIV2.Pages.Index (the car collection) from the Cartoony Kit's IndexUI: one CarCard coloured by rarity band, a rail of one filter button per CarRarity band, the stolen count in the header and a rate chip on the card. Rebuilds the page every run.",
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

		--[[ Read in the plugin VM, which caches `require` and does not notice a sync. That is fine for
			these two: the band list and its colours change about never, and the page repaints both
			from the live modules anyway. ]]
		local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
		local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
		local bands = TrafficConfig.Bands

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
		local closeBtn = header and header:FindFirstChild("CloseBtn")
		if not (headerTitle and headerTitle:IsA("TextLabel")) then
			out:error(string.format("The kit's %s has no `Header.Title`.", KIT_FRAME))
			page:Destroy()
			return
		end
		headerTitle.Text = TITLE_TEXT

		local count: TextLabel? = nil
		if closeBtn and closeBtn:IsA("GuiObject") then
			local _titleLeft, titleRight = xSpan(headerTitle)
			local closeLeft = xSpan(closeBtn)
			local right = closeLeft - COUNT_GUTTER * closeBtn.Size.X.Scale

			local label = headerTitle:Clone()
			label.Name = COUNT_NAME
			label.Text = COUNT_PLACEHOLDER
			--- Against the close button's side of the band, so "9/43" becoming "10/43" grows left into
			--- the empty band rather than towards the X.
			label.TextXAlignment = Enum.TextXAlignment.Right
			label.AnchorPoint = Vector2.new(1, headerTitle.AnchorPoint.Y)
			label.Size = UDim2.new(math.max(0, right - titleRight), 0, headerTitle.Size.Y.Scale, 0)
			label.Position = UDim2.new(right, 0, headerTitle.Position.Y.Scale, 0)
			label.Parent = header
			count = label
		else
			out:warn("The kit's `Header.CloseBtn` is gone, so there is nowhere to hang the count.")
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

		local card = kept :: GuiObject
		card.Name = CELL_NAME

		local rarity = card:FindFirstChild(RARITY_LABEL)
		local cardTitle = card:FindFirstChild("Title")
		local icon = card:FindFirstChild(ICON_NAME)
		if not (rarity and rarity:IsA("TextLabel") and cardTitle and cardTitle:IsA("TextLabel") and icon and icon:IsA("ImageLabel")) then
			out:error(string.format("`%s` is missing `%s`, `Title` or `%s`.", CELL_NAME, RARITY_LABEL, ICON_NAME))
			page:Destroy()
			return
		end

		local placeholderColour = CarRarity.colourOf(1)
		local cardTint = card:FindFirstChildOfClass("UIGradient")
		if cardTint then
			cardTint.Name = TINT_NAME
			cardTint.Color = ramp(placeholderColour)
		else
			out:warn(string.format("`%s` has no UIGradient; every card will be the kit's white.", CELL_NAME))
		end

		--- The word goes white, the kit's own `Common`. Header: the colour is on the card.
		for _, gradient in rarity:GetChildren() do
			if gradient:IsA("UIGradient") then
				gradient:Destroy()
			end
		end
		rarity.TextColor3 = Color3.new(1, 1, 1)
		rarity.Text = caption(bands[1] and bands[1].Name or "Beater")
		cardTitle.Text = NAME_PLACEHOLDER

		--- The rabbit goes; the box stays. Header, "What is changed".
		icon.Image = ""

		local rate = rarity:Clone()
		rate.Name = RATE_NAME
		rate.Text = RATE_PLACEHOLDER
		rate.TextXAlignment = Enum.TextXAlignment.Right
		rate.AnchorPoint = Vector2.new(1, 1)
		rate.Position = UDim2.fromScale(1 - RATE_INSET, RATE_BOTTOM)
		rate.Size = UDim2.fromScale(RATE_WIDTH, RATE_HEIGHT)
		rate.Parent = card

		-- === The rail =======================================================
		local rail = page:FindFirstChild(RAIL_NAME)
		local stamp: GuiButton? = nil
		local dropped = 0
		if rail then
			for _, child in rail:GetChildren() do
				if child:IsA("GuiButton") then
					if not stamp then
						stamp = child
						child.Parent = nil
					else
						child:Destroy()
					end
					dropped += 1
				end
			end
		end
		if not (rail and stamp) then
			out:error(string.format("The kit's %s has no `%s` buttons to stamp the bands from.", KIT_FRAME, RAIL_NAME))
			page:Destroy()
			return
		end

		local stamped = {}
		for index, band in bands do
			local button = (stamp :: GuiButton):Clone()
			button.Name = band.Name .. "Btn"
			button.LayoutOrder = index
			button:SetAttribute(BAND_ATTRIBUTE, index)
			local title = button:FindFirstChild("Title")
			if title and title:IsA("TextLabel") then
				title.Text = caption(band.Name)
			end
			local tint = button:FindFirstChildOfClass("UIGradient")
			if tint then
				tint.Name = TINT_NAME
				tint.Color = ramp(CarRarity.colourOf(index))
			end
			button.Parent = rail
			table.insert(stamped, button.Name)
		end
		stamp:Destroy()

		--- Bigger than the kit, text caps included. See `Modules/KitGrowth`.
		KitGrowth.apply(page, KitGrowth.Pages)
		page.Parent = pages

		out:print(string.format("Built %s.Pages.%s from the kit's %s.", SCREEN_NAME, PAGE_NAME, KIT_FRAME))
		out:print(
			string.format(
				"Card `%s`: %d spare cells dropped, face gradient named `%s`, rarity word white, `%s` chip added, icon cleared.",
				CELL_NAME,
				spares,
				TINT_NAME,
				RATE_NAME
			)
		)
		out:print(
			string.format(
				"Rail: %d kit buttons became %d bands (%s). Header `%s` %s.",
				dropped,
				#stamped,
				table.concat(stamped, ", "),
				COUNT_NAME,
				if count then "added" else "NOT added"
			)
		)

		pcall(function()
			props:SetSelection({ page })
		end)
	end,
} :: Types.ScriptModule
