--[[
	CarOdds page, V2 - THE RANDOM CAR'S ODDS  (client)
	--------------------------------------------------
	"What can a random car be, and how likely is each?" Every outcome of a pull in the world the
	player is in, a card each, opened by the ODDS button on the offer card (`BuildRandomCarV2` gives it
	`Page = "CarOdds"`). Built by `BuildCarOddsV2` out of the kit's `IndexUI`, so it is the Index page's
	card and grid with a chance where the Index prints a rate.

	WHY IT EXISTS (2026-10-15): Roblox's paid random items policy wants every outcome with its own
	number, reachable before purchase behind a button that says what it is. That list was a tooltip
	beside the card, too small to read. `RandomCarConfig`'s header has the policy.

	=== WHAT IS ON IT ===========================================================================

	  • CARS: one card per car `RandomCarConfig.oddsFor` lists, in ladder order, the car drawn in it in
	    its factory paint, on its rarity's colour.
	  • PAINT: one card per colour the usual paint pool can roll (`RandomCarConfig.paintOdds`), the
	    card in that colour and the world's commonest car drawn wearing it. A pull rolls the colour after
	    the car, and body plus colour is the car, so the paint is part of what a pull gives.
	  • The note under the grid: the cars whose paint pool is not the usual one (the `KeepLivery` cars,
	    factory only) and the rounding note.

	READ OFF THE ROLL'S OWN ARITHMETIC, so it cannot print odds the server does not roll, and rebuilt on
	every open for the world the player is in then: a pull rolls that world's ladder.

	THE CARS ARE A VIRTUALISED GRID (`Modules/CarViewportGrid`), exactly as on the Index: a model per
	card that is on screen, released when the page shuts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)
local RandomCarConfig = require(ReplicatedStorage.shared.Configs.RandomCarConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)
local CarViewportGrid = require(ReplicatedStorage.shared.Modules.CarViewportGrid)
local KitPage = require(script.Parent.Parent.KitPage)

local PAGE_NAME = RandomCarConfig.Odds.PageName

local Page = KitPage.extend(PAGE_NAME)

--- What `BuildCarOddsV2` left, by name.
local CARD_NAME = "CarCard"
local TINT_NAME = "Tint"
local RAIL_NAME = "SideBtns"
local TAB_ATTRIBUTE = "Tab"
local CAR_VIEW = "Car"

--- How far the tab you are NOT on is dimmed. The Index rail's number for the same job.
local RAIL_DIM = 0.55
local RAMP_LIFT = 0.35

--- The face of the FACTORY card: factory paint is a different colour on every car, so a neutral.
local FACTORY_COLOUR = Color3.fromRGB(120, 134, 156)

local NBSP = "\u{00A0}"

local function caption(text: string): string
	return (string.gsub(string.upper(text), " ", NBSP))
end

local function ramp(colour: Color3): ColorSequence
	return ColorSequence.new(colour:Lerp(Color3.new(1, 1, 1), RAMP_LIFT), colour)
end

--- A label and the strokes that outline its type, faded together (see `PagesV2/Index`).
local function fadeText(label: Instance?, alpha: number)
	if not (label and label:IsA("TextLabel")) then
		return
	end
	label.TextTransparency = alpha
	for _, stroke in label:GetChildren() do
		if stroke:IsA("UIStroke") then
			stroke.Transparency = alpha
		end
	end
end

local function setText(parent: Instance, name: string, text: string)
	local label = parent:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

--[[ The line under the grid: each car whose paint is not the usual pool, then the rounding note.
	A `KeepLivery` car is one colour at 100%, which reads as "factory paint only"; any other pool is
	spelled out colour by colour. ]]
local function noteFor(paint: RandomCarConfig.PaintOdds): string
	local odds = RandomCarConfig.Odds
	local parts = {}
	for _, exception in paint.Exceptions do
		local names = {}
		for _, body in exception.Bodies do
			table.insert(names, GarageConfig.displayName(body))
		end
		local who = table.concat(names, ", ")
		local groups = exception.Groups
		if #groups == 1 and #groups[1].Indices == 1 and groups[1].Chance >= 1 then
			table.insert(parts, string.format(odds.OnlyFormat, who, RandomCarConfig.paintName(groups[1].Indices[1])))
		else
			local colours = {}
			for _, group in groups do
				for _, index in group.Indices do
					table.insert(colours, RandomCarConfig.paintName(index) .. " " .. RandomCarConfig.formatChance(group.Chance))
				end
			end
			table.insert(parts, string.format(odds.ExceptionFormat, who, table.concat(colours, ", ")))
		end
	end
	table.insert(parts, odds.Note)
	return string.upper(table.concat(parts, "  "))
end

-- === Building ===============================================================

function Page.initialize(self)
	KitPage.scaleTextCaps(self.PageUI)

	self.Player = (self.UIController and self.UIController.Player) or Players.LocalPlayer
	--- One record per card, in layout order. Each is also a `CarViewportGrid.Cell` (`viewport`,
	--- `body`, `paint`, `silhouette`, `fade`). NOT `self._rows`, which is `KitPage`'s.
	self._entries = {} :: { any }
	self._tab = "Cars"
	self._world = nil :: number?
	self._shown = 0

	self.World = self.Header and self.Header:FindFirstChild("World")
	self.Note = self.Main and self.Main:FindFirstChild("Note")

	self._views = CarViewportGrid.new(self.List :: ScrollingFrame, self.PageUI)
	if self.List then
		--- The cards are the targets, not the well (`PagesV2/Index`, "On a gamepad").
		self.List.Selectable = false
	end
	self:pinGridToWindow()
	self:_buildTabs()

	if self.List then
		self.List:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:pinGridToWindow()
			self:_applyGeometry()
		end)
	end

	--- A world change while the page is up (it should not happen, a teleport closes pages) still
	--- leaves it showing the world a pull would roll.
	self.Player:GetAttributeChangedSignal(WorldConfig.WorldAttribute):Connect(function()
		if self.PageUI.Visible then
			self:_fill()
			self:_setTab(self._tab)
		end
	end)
end

function Page:_buildTabs()
	self._tabs = {} :: { { button: GuiButton, tab: string } }
	local rail = self.PageUI:FindFirstChild(RAIL_NAME)
	if not rail then
		warn(string.format("[%s] no `%s` rail; the paint odds have no tab.", PAGE_NAME, RAIL_NAME))
		return
	end
	for _, button in rail:GetChildren() do
		local tab = button:GetAttribute(TAB_ATTRIBUTE)
		if not (button:IsA("GuiButton") and type(tab) == "string") then
			continue
		end
		setText(button, "Title", caption(RandomCarConfig.Odds.Tabs[tab] or tab))
		button.Activated:Connect(function()
			self:_setTab(tab)
		end)
		table.insert(self._tabs, { button = button, tab = tab })
	end
end

--- One card, dressed: its face, the top word, the name, the chance, and a viewport over `Icon`.
function Page:_card(colour: Color3, word: string, name: string, chance: number): (GuiObject?, ViewportFrame?)
	local card = self:newRow(CARD_NAME)
	if not card then
		return nil, nil
	end
	--- Selectable, pressing nothing, so a DPad can walk the grid and the list scrolls to follow.
	card.Selectable = true
	local tint = card:FindFirstChild(TINT_NAME)
	if tint and tint:IsA("UIGradient") then
		tint.Color = ramp(colour)
	end
	setText(card, "Rarity", caption(word))
	setText(card, "Title", name)
	setText(card, "Chance", RandomCarConfig.formatChance(chance))

	local icon = card:FindFirstChild("Icon")
	local viewport: ViewportFrame? = nil
	if icon and icon:IsA("GuiObject") then
		local view = CarViewport.new(card, CAR_VIEW, colour)
		view.AnchorPoint = icon.AnchorPoint
		view.Position = icon.Position
		view.Size = icon.Size
		view.ZIndex = icon.ZIndex + 1
		viewport = view
	end
	return card, viewport
end

--[[ Every card for the player's world, once per world. Cars first, in ladder order, then the paint
	colours, likeliest first and in palette order within a chance. ]]
function Page:_fill()
	local world = WorldConfig.resolve(self.Player:GetAttribute(WorldConfig.WorldAttribute))
	if self._world == world then
		return
	end
	self._world = world
	self._views:clear()
	self:clearRows()
	table.clear(self._entries)

	if self.World and self.World:IsA("TextLabel") then
		self.World.Text = caption(WorldConfig.displayName(world))
	end

	local cars = RandomCarConfig.oddsFor(world)
	local paint = RandomCarConfig.paintOdds(world)
	local special: { [string]: boolean } = {}
	for _, exception in paint.Exceptions do
		for _, body in exception.Bodies do
			special[body] = true
		end
	end

	--- The car the paint cards are drawn on: the likeliest one that rolls from the usual pool.
	local showcase: string? = nil
	local best = -1
	for _, car in cars do
		if not special[car.Body] and car.Chance > best then
			showcase, best = car.Body, car.Chance
		end
	end

	for _, car in cars do
		local word, band = CarRarity.of(car.Body)
		if word == "" then
			word, band = car.Rarity, car.Band
		end
		local card, viewport = self:_card(CarRarity.colourOf(band), word, GarageConfig.displayName(car.Body), car.Chance)
		if card then
			table.insert(self._entries, { tab = "Cars", card = card, viewport = viewport, body = car.Body, fade = 0 })
		end
	end

	for _, group in paint.Common do
		for _, index in group.Indices do
			local colour = if index == PaintConfig.StockIndex then FACTORY_COLOUR else PaintConfig.colorOf(index) or FACTORY_COLOUR
			local card, viewport = self:_card(colour, RandomCarConfig.Odds.PaintWord, RandomCarConfig.paintName(index), group.Chance)
			if card then
				table.insert(self._entries, {
					tab = "Paint",
					card = card,
					viewport = viewport,
					body = showcase,
					paint = if index == PaintConfig.StockIndex then nil else index,
					fade = 0,
				})
			end
		end
	end

	if self.Note and self.Note:IsA("TextLabel") then
		self.Note.Text = noteFor(paint)
	end
	self:_wireGamepad()
end

-- === The tabs ===============================================================

--[[ Show one tab's cards. A `UIGridLayout` lays out visible children only, so the hidden tab's cards
	take no room, and the viewport grid is handed the shown ones in order. ]]
function Page:_setTab(tab: string)
	self._tab = tab
	local cells = {}
	for _, entry in self._entries do
		local shown = entry.tab == tab
		entry.card.Visible = shown
		entry.slot = nil
		if shown then
			table.insert(cells, entry)
			entry.slot = #cells
		end
	end
	self._shown = #cells

	self:_updateCanvas()
	if self.List then
		self.List.CanvasPosition = Vector2.zero
	end
	self:_applyGeometry()
	self._views:setCells(cells)

	for _, item in self._tabs do
		local alpha = if item.tab == tab then 0 else RAIL_DIM
		local button = item.button
		button.BackgroundTransparency = alpha
		fadeText(button:FindFirstChild("Title"), alpha)
		local container = button:FindFirstChild("Container")
		if container then
			for _, stroke in container:GetChildren() do
				if stroke:IsA("UIStroke") then
					stroke.Transparency = alpha
				end
			end
		end
		local sheen = button:FindFirstChild("BG")
		if sheen and sheen:IsA("CanvasGroup") then
			sheen.GroupTransparency = alpha
		end
	end
	self:_refreshDoors()
end

--- The viewport grid's geometry, the Index page's way: the `Icon` box's aspect, not the cell's.
function Page:_applyGeometry()
	if not self.List then
		return
	end
	local columns, pitch, cellHeight, top, cellAspect = self:cellGeometry()
	local template = self.Templates[CARD_NAME]
	local icon = template and template:FindFirstChild("Icon")
	local aspect = cellAspect
	if icon and icon:IsA("GuiObject") and icon.Size.Y.Scale > 0 then
		aspect = cellAspect * icon.Size.X.Scale / icon.Size.Y.Scale
	end
	self._views:setLayout(columns, pitch, cellHeight, top, aspect)
end

-- === On a gamepad ===========================================================

--[[ The engine will not step into a scrolling grid from outside it (`PagesV2/Index` measured it), so
	the doors are set by hand: a tab's LEFT and the X's DOWN go to the end of the first row, and the
	last card of each row goes RIGHT to the tab that is lit. ]]
function Page:_firstRowEnd(): GuiObject?
	local columns = math.max(1, self._columns)
	local target = math.min(columns, self._shown)
	for _, entry in self._entries do
		if entry.slot == target then
			return entry.card
		end
	end
	return nil
end

function Page:_activeTab(): GuiObject?
	for _, item in self._tabs do
		if item.tab == self._tab then
			return item.button
		end
	end
	return nil
end

function Page:_refreshDoors()
	local door = self:_firstRowEnd()
	for _, item in self._tabs do
		item.button.NextSelectionLeft = door
	end
	if self.CloseBtn then
		self.CloseBtn.NextSelectionDown = door
	end
end

function Page:_wireGamepad()
	for _, entry in self._entries do
		entry.card.SelectionGained:Connect(function()
			local slot = entry.slot
			local columns = math.max(1, self._columns)
			local ends = slot ~= nil and (slot % columns == 0 or slot == self._shown)
			entry.card.NextSelectionRight = if ends then self:_activeTab() else nil
		end)
	end
end

--[[ Every open starts on CARS, for the world the player is in now. Before the page is shown, so the
	first frame is already the right list. ]]
function Page:StartOpenThread()
	self:_fill()
	self:_setTab("Cars")
end

return Page
