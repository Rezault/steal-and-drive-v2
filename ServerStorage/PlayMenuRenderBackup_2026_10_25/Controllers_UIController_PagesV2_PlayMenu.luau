--[[
	PlayMenu page, V2 - PLAY ON ONE SCREEN  (client)
	------------------------------------------------
	"Where, in what, go." The world strip and the car strip side by side, the pick shown big in the
	hero, and DRIVE. It replaces Play -> Worlds -> Select Car with one screen (2026-10-25), behind
	`StartCarConfig.OneScreenPlay`. `BuildPlayMenuV2` (Command Runner) draws it.

	NOTHING HERE DECIDES ANYTHING, the same split as the two screens it replaces:
	  • A WORLD CARD is the Worlds row's own Play button stretched over the card (tag, `Action =
	    TeleportToWorld`, `World = <index>` on the card), so `WorldController` answers the press
	    exactly as it does on the Worlds page: buy, confirm, offer cash, or hand an owned world to
	    `StartCarController:choose`, which on this screen only SELECTS it (`WorldChosenEvent`).
	  • A CAR CARD selects locally. The server is told on DRIVE, world and car on one request
	    (`StartCarController:play` -> `RaceEntryController:play`), and `StartCarService` still decides
	    whether that car may be driven.
	  • DRIVE is armed like Select Car's buttons: a release only counts if its press began on it, so
	    the finger that pressed Play on the HUD cannot start a run by lifting over it.

	OPENS ON WHAT A PLAIN PLAY WOULD DRIVE: the world you are in, and your stored car (or the starter),
	so a player who presses Play then DRIVE gets exactly the run the old three presses gave them. A
	car double-pressed in the Cars Inventory arrives already selected (`takePending`).

	THE CARDS ARE SIZED IN PIXELS from the strip's rendered height, divided by the open tween's
	UIScale, because a scaled child of a ScrollingFrame resolves against the canvas (`KitPage`).
	The car pictures are drawn as their cards scroll into view rather than all at once: a strip of
	forty live viewports built on one frame is a hitch nobody needs for cards they never scroll to.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local InventoryConfig = require(ReplicatedStorage.shared.Configs.InventoryConfig)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)
local StartCarConfig = require(ReplicatedStorage.shared.Configs.StartCarConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local CarCardDress = require(ReplicatedStorage.shared.Modules.CarCardDress)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)
local CarDetail = require(script.Parent.Parent.Components.CarDetailV2)
local KitPage = require(script.Parent.Parent.KitPage)

local Page = KitPage.extend(StartCarConfig.PlayPageName)

local NBSP = "\u{00A0}"
local WHITE_RAMP = ColorSequence.new(Color3.new(1, 1, 1))
local FREE_COLOUR = Color3.fromRGB(150, 160, 175)
--- Each card's width over its height. The world strip fits every world across instead (never
--- wider than `WORLD_ASPECT`), so no world is ever half off the edge.
local WORLD_ASPECT = 1.4
local CAR_ASPECT = 1.25
--[[ As shares of the strip's height. The card borders are drawn OUTSIDE the card (a scaled stroke,
	~6px here), so the margin has to clear one border and the gap two, plus the daylight between. ]]
local GAP = 0.12
local INSET = 0.06
local POINTER_INPUT = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}

local function oneLine(text: string): string
	return (string.gsub(text, " ", NBSP))
end

--- Select Car's search key: lower case, letters and digits only, so "golf-gti" finds "Golf GTI".
local function normalize(text: string?): string
	return (string.gsub(string.lower(text or ""), "%W", ""))
end

local function rarityRamp(colour: Color3): ColorSequence
	return ColorSequence.new(colour:Lerp(Color3.new(1, 1, 1), 0.35), colour)
end

--- Select Car's guard (its header, note 4): a pointer release only counts if it was pressed here.
local function armPointer(button: GuiButton): (InputObject?) -> boolean
	local armed = false
	button.InputBegan:Connect(function(input: InputObject)
		if POINTER_INPUT[input.UserInputType] then
			armed = true
		end
	end)
	return function(input: InputObject?): boolean
		if input and POINTER_INPUT[input.UserInputType] and not armed then
			return false
		end
		armed = false
		return true
	end
end

local function setText(label: Instance?, text: string)
	if label and label:IsA("TextLabel") then
		label.Text = oneLine(text)
	end
end

local function worldThumb(index: number): number
	local map = WorldConfig.mapFor(index)
	local card = map and UIAssets.WorldCards[map]
	return if card then card.Thumb else UIAssets.worldThumb(map)
end

-- === Building ===============================================================

function Page.initialize(self)
	KitPage.scaleTextCaps(self.PageUI)
	self.Player = (self.UIController and self.UIController.Player) or Players.LocalPlayer
	self:setTitle("Play")

	local main = self.Main :: GuiObject
	local hero = main:FindFirstChild("Hero")
	local info = hero and hero:FindFirstChild("Info")
	local footer = main:FindFirstChild("Footer")
	local summary = footer and footer:FindFirstChild("Summary")
	self._hero = {
		backdrop = hero and hero:FindFirstChild("Backdrop"),
		world = info and info:FindFirstChild("World"),
		car = info and info:FindFirstChild("Car"),
		view = hero and hero:FindFirstChild("Car") and CarViewport.new(hero:FindFirstChild("Car") :: GuiObject, "View"),
	}
	self._summary = {
		thumb = summary and summary:FindFirstChild("Thumb"),
		text = summary and summary:FindFirstChild("Text"),
	}
	self._worldList = main:FindFirstChild("Worlds") and main.Worlds:FindFirstChild("List")
	self._carList = main:FindFirstChild("Cars") and main.Cars:FindFirstChild("List")
	if not (self._worldList and self._carList) then
		warn("[PlayMenu] The page is missing its strips; run BuildPlayMenuV2.")
		return
	end

	--- The two cards are templates: taken out of their strips and cloned per world / per car.
	self._worldTemplate = self._worldList:FindFirstChild("WorldCard")
	self._carTemplate = self._carList:FindFirstChild("CarCard")
	for _, template in { self._worldTemplate, self._carTemplate } do
		template.Parent = nil
	end
	local status = self._worldTemplate:FindFirstChild("Status")
	local gradient = status and status:FindFirstChildOfClass("UIGradient")
	self._liveRamp = gradient and gradient.Color

	self._worlds = {} :: { [number]: any }
	for index in WorldConfig.Worlds do
		self._worlds[index] = self:_makeWorld(index)
	end
	self._cars = {} :: { any }
	self._car = StartCarConfig.DefaultKey
	self._query = ""
	self._note = main.Cars:FindFirstChild("Note")
	local search = main:FindFirstChild("Search")
	self._searchBox = search and search:FindFirstChildWhichIsA("TextBox")
	if self._searchBox then
		self._searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			local query = normalize(self._searchBox.Text)
			if query ~= self._query then
				self._query = query
				self:_applyFilter()
			end
		end)
	end

	local drive = footer and footer:FindFirstChild("DriveBtn")
	if drive and drive:IsA("GuiButton") then
		local mayFire = armPointer(drive)
		drive.Activated:Connect(function(input: InputObject?)
			if mayFire(input) then
				self:_drive()
			end
		end)
	end

	Dispatcher:Subscribe(WorldConfig.StateEvent, function()
		if self.PageUI.Visible then
			self:_paintWorlds()
		end
	end)
	--- A new world is a new starter card, so the car strip is rebuilt; the picked car key is kept.
	Dispatcher:Subscribe(StartCarConfig.WorldChosenEvent, function()
		self:_rebuildCars()
		self:_paint()
	end)
	self.Player:GetAttributeChangedSignal(GarageConfig.OwnedAttribute):Connect(function()
		if self.PageUI.Visible then
			self:_rebuildCars()
			self:_paint()
		end
	end)
	for _, list in { self._worldList, self._carList } do
		list:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:_layout()
		end)
	end
	self._carList:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:_drawVisible()
	end)
	self:_layout()
	self:_paintWorlds()
end

function Page:_controller()
	return Shard.get("StartCarController")
end

--- The world being picked for: the card pressed last, else the one the player is in.
function Page:_world(): number
	local controller = self:_controller()
	return if controller then controller:world() else WorldConfig.ActiveIndex
end

function Page:_makeWorld(index: number)
	local card = self._worldTemplate:Clone()
	card.Name = "World" .. index
	card.LayoutOrder = index
	--- What `WorldController._worldOfButton` walks up to from the press.
	card:SetAttribute(WorldConfig.WorldAttribute, index)
	local map = card:FindFirstChild("Map")
	if map and map:IsA("ImageLabel") then
		map.Image = UIAssets.url(worldThumb(index))
	end
	setText(card:FindFirstChild("Title"), string.upper(WorldConfig.displayName(index)))
	card.Parent = self._worldList
	return {
		card = card,
		status = card:FindFirstChild("Status"),
		rim = card:FindFirstChild("Rim"),
		dim = card:FindFirstChild("Dim"),
		lock = card:FindFirstChild("Lock"),
	}
end

--[[ The car cards: the world's starter (unless you own its stock copy, which is the same car) and
	every car you may drive there, best first. `StartCarController.driveable` owns the rules, as it
	does for Select Car, so the two screens can never offer different lists. ]]
function Page:_rebuildCars()
	for _, entry in self._cars do
		entry.card:Destroy()
	end
	table.clear(self._cars)
	local controller = self:_controller()
	local world = self:_world()
	local owned = if controller then controller:driveable(world) else {}
	local starterBody = WorldConfig.startBodyFor(world)
	local stock = GarageConfig.carKey(starterBody, PaintConfig.StockIndex)
	local ownsStock = false
	for _, key in owned do
		ownsStock = ownsStock or GarageConfig.modelKeyOf(key) == stock
	end
	local starter = self:_makeCar(StartCarConfig.DefaultKey, starterBody, PaintConfig.StockIndex, nil)
	if not ownsStock then
		local rarity = starter.rarity
		setText(rarity, "FREE CAR")
		local tint = rarity and rarity:FindFirstChild("Tint")
		if tint and tint:IsA("UIGradient") then
			tint.Color = rarityRamp(FREE_COLOUR)
		end
	end
	table.insert(self._cars, starter)
	for _, key in owned do
		if GarageConfig.modelKeyOf(key) == stock then
			continue
		end
		local body, paint, mutation = GarageConfig.parseCarKey(key)
		if body then
			table.insert(self._cars, self:_makeCar(key, body, paint or PaintConfig.StockIndex, mutation))
		end
	end
	table.sort(self._cars, function(a, b)
		local ta = GarageConfig.TierOfBody[a.body] or 0
		local tb = GarageConfig.TierOfBody[b.body] or 0
		return if ta ~= tb then ta > tb else a.key < b.key
	end)
	for order, entry in self._cars do
		entry.card.LayoutOrder = order
	end
	self:_applyFilter()
end

--[[ Show only the cars whose name (or weather mutation) contains the search, in the same order.
	The picked car stays picked while hidden: searching is looking, not choosing. ]]
function Page:_applyFilter()
	local shown = 0
	for _, entry in self._cars do
		entry.card.Visible = self._query == "" or string.find(entry.search, self._query, 1, true) ~= nil
		shown += if entry.card.Visible then 1 else 0
	end
	local note = self._note
	if note and note:IsA("TextLabel") then
		note.Visible = shown == 0
		note.Text = oneLine(InventoryConfig.Text.NoMatch)
	end
	self._carList.CanvasPosition = Vector2.zero
	self:_layout()
end

function Page:_makeCar(key: string, body: string, paint: number, mutation: string?)
	local card = self._carTemplate:Clone()
	card.Name = if StartCarConfig.isDefault(key) then "Starter" else key
	local icon = card:FindFirstChild("Icon")
	local entry = {
		key = key,
		body = body,
		paint = paint,
		mutation = mutation,
		card = card,
		title = card:FindFirstChild("Title"),
		rarity = card:FindFirstChild("Rarity"),
		chip = card:FindFirstChild("Selected"),
		rim = card:FindFirstChild("Rim"),
		drawn = false,
		search = normalize((if mutation then WeatherConfig.nameOf(mutation) .. " " else "") .. GarageConfig.carName(body, paint)),
	}
	--- The kit's placeholder picture goes; the car is drawn over the same box when it scrolls in.
	if icon and icon:IsA("GuiObject") then
		if icon:IsA("ImageLabel") then
			icon.Image = ""
		end
		local view = CarViewport.new(card, "Car")
		view.AnchorPoint, view.Position, view.Size, view.ZIndex = icon.AnchorPoint, icon.Position, icon.Size, icon.ZIndex
		entry.viewport = view
	end
	setText(entry.title, GarageConfig.carName(body, paint))
	local word, colour = CarRarity.labelOf(body)
	setText(entry.rarity, string.upper(word))
	local tint = entry.rarity and entry.rarity:FindFirstChild("Tint")
	if tint and tint:IsA("UIGradient") then
		tint.Color = rarityRamp(colour)
	end
	setText(entry.chip, "SELECTED")
	CarCardDress.apply(card, entry.title, entry.rarity, body, mutation)
	local pick = card:FindFirstChild("PickBtn")
	if pick and pick:IsA("GuiButton") then
		CarDetail.hoverCard(card, pick, card:FindFirstChild("Hover") :: UIStroke?)
		pick.Activated:Connect(function()
			self._car = entry.key
			self:_paint()
		end)
	end
	card.Parent = self._carList
	return entry
end

-- === Layout =================================================================

--[[ One strip's cards in pixels and the canvas to fit them. `fit` lays every card across the
	strip's width (centred, no scrolling) at up to `aspect`; otherwise each is `aspect` wide and the
	strip scrolls. Returns the pitch, card plus gap. ]]
local function layStrip(list: ScrollingFrame, cards: { GuiObject }, aspect: number, k: number, fit: boolean): number
	local width, height = list.AbsoluteSize.X / k, list.AbsoluteSize.Y / k
	local inset = height * INSET
	local h = math.max(0, height - inset * 2)
	local gap = h * GAP
	local n = math.max(1, #cards)
	local w = h * aspect
	if fit then
		w = math.min(w, (width - inset * 2 - gap * (n - 1)) / n)
	end
	local layout = list:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.Padding = UDim.new(0, gap)
		layout.HorizontalAlignment = if fit then Enum.HorizontalAlignment.Center else Enum.HorizontalAlignment.Left
	end
	local padding = list:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
	padding.PaddingLeft, padding.PaddingRight = UDim.new(0, inset), UDim.new(0, inset)
	padding.Parent = list
	for _, card in cards do
		card.Size = UDim2.fromOffset(w, h)
	end
	local content = #cards * w + math.max(0, #cards - 1) * gap + inset * 2
	list.CanvasSize = UDim2.fromOffset(if fit then math.min(content, width) else content, 0)
	return w + gap
end

function Page:_layout()
	if not self._worldList then
		return
	end
	--- The open tween's UIScale is in every AbsoluteSize; offsets inside it get scaled again.
	local scale = self.PageUI:FindFirstChildOfClass("UIScale")
	local k = if scale and scale.Scale > 0 then scale.Scale else 1
	local worldCards = {}
	for _, entry in self._worlds do
		table.insert(worldCards, entry.card)
	end
	table.sort(worldCards, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	layStrip(self._worldList, worldCards, WORLD_ASPECT, k, true)
	--- Only the cars the search shows; `slot` is each one's place in that row, for `_drawVisible`.
	local carCards = {}
	for _, entry in self._cars do
		entry.slot = nil
		if entry.card.Visible then
			table.insert(carCards, entry.card)
			entry.slot = #carCards
		end
	end
	self._k = k
	self._carPitch = layStrip(self._carList, carCards, CAR_ASPECT, k, false)
	self:_drawVisible()
end

--- Draw the cars whose cards are on screen or one card either side of it (canvas offset units).
function Page:_drawVisible()
	local pitch = self._carPitch
	if not (pitch and pitch > 0) then
		return
	end
	local left = self._carList.CanvasPosition.X - pitch
	local right = self._carList.CanvasPosition.X + self._carList.AbsoluteWindowSize.X / (self._k or 1) + pitch
	for _, entry in self._cars do
		local x = ((entry.slot or 0) - 1) * pitch
		if entry.slot and not entry.drawn and entry.viewport and x + pitch >= left and x <= right then
			entry.drawn = true
			CarViewport.set(entry.viewport, entry.body, { paint = entry.paint, mutation = entry.mutation, aspect = CAR_ASPECT })
		end
	end
end

-- === Painting ===============================================================

--[[ Every world card from `WorldController:cardState`, the Worlds page's own answer:
	    play      SELECTED (green rim) / OWNED
	    buy       its price, or CONFIRM? on the second press
	    needs     dimmed, a lock, and how far down the road before it you are ]]
function Page:_paintWorlds()
	local controller = Shard.get("WorldController")
	local chosen = self:_world()
	for index, entry in self._worlds do
		local state = if controller then controller:cardState(index) else { label = "play" }
		if state.label == "racing" then
			continue
		end
		local line, ramp, locked = "OWNED", self._liveRamp, false
		if state.label == "needs" then
			local road = state.previousShort or state.previousName or "?"
			line = string.format("FINISH %s %d%%", string.upper(road), math.floor(math.clamp(state.progress or 0, 0, 1) * 100))
			ramp, locked = WHITE_RAMP, true
		elseif state.label == "confirm" then
			line = "CONFIRM?"
		elseif state.label == "buy" then
			line = GarageConfig.formatCash(state.cost or 0)
		elseif index == chosen then
			line = "SELECTED"
		end
		setText(entry.status, line)
		local gradient = entry.status and entry.status:FindFirstChildOfClass("UIGradient")
		if gradient and ramp then
			gradient.Color = ramp
		end
		if entry.dim then
			entry.dim.Visible = locked
		end
		if entry.lock then
			entry.lock.Visible = locked
		end
		if entry.rim and entry.rim:IsA("UIStroke") then
			entry.rim.Enabled = index == chosen and state.label == "play"
		end
	end
end

--- The selected car's entry, falling back to the starter for a key this list does not hold
--- (sold, or the stock copy of the starter), which is the car the server would start them in.
function Page:_selectedCar()
	local starter = nil
	for _, entry in self._cars do
		if entry.key == self._car then
			return entry
		end
		if StartCarConfig.isDefault(entry.key) then
			starter = entry
		end
	end
	return starter
end

function Page:_paint()
	if not self._worldList then
		return
	end
	self:_paintWorlds()
	local world = self:_world()
	local car = self:_selectedCar()
	for _, entry in self._cars do
		local here = entry == car
		if entry.rim and entry.rim:IsA("UIStroke") then
			entry.rim.Enabled = here
		end
		if entry.chip and entry.chip:IsA("GuiObject") then
			entry.chip.Visible = here
		end
	end
	local worldName = string.upper(WorldConfig.displayName(world))
	local carName = if car then string.upper(GarageConfig.carName(car.body, car.paint)) else ""
	setText(self._hero.world, worldName)
	setText(self._hero.car, carName)
	setText(self._summary.text, worldName .. "  •  " .. carName)
	local map = WorldConfig.mapFor(world)
	local art = map and UIAssets.WorldCards[map]
	if self._hero.backdrop and self._hero.backdrop:IsA("ImageLabel") then
		self._hero.backdrop.Image = UIAssets.url(if art then art.Backdrop else worldThumb(world))
	end
	if self._summary.thumb and self._summary.thumb:IsA("ImageLabel") then
		self._summary.thumb.Image = UIAssets.url(worldThumb(world))
	end
	self:_showHeroCar(car)
end

--- The big turning car. Only redrawn when the car changes, and only turned while the page is up.
function Page:_showHeroCar(car)
	local view = self._hero.view
	if not (view and car) then
		return
	end
	view.Size = UDim2.fromScale(1, 1)
	local size = view.AbsoluteSize
	local aspect = if size.Y > 0 then size.X / size.Y else 2
	local key = car.key .. "|" .. car.body
	if self._heroKey ~= key then
		self._heroKey = key
		if self._spin then
			self._spin.stop()
			self._spin = nil
		end
		CarViewport.set(view, car.body, { paint = car.paint, mutation = car.mutation, aspect = aspect })
	end
	if not self._spin and self.PageUI.Visible then
		self._spin = CarViewport.spin(view, { aspect = aspect })
	end
end

function Page:_drive()
	local controller = self:_controller()
	local car = self:_selectedCar()
	if controller then
		controller:play(if car then car.key else StartCarConfig.DefaultKey)
	end
end

-- === Open and close =========================================================

function Page:StartOpenThread()
	if not self._worldList then
		return
	end
	local controller = self:_controller()
	self._car = (controller and controller:takePending()) or (controller and controller:selected()) or StartCarConfig.DefaultKey
	self._worldList.CanvasPosition = Vector2.zero
	--- A search typed last time is cleared, by hand as well: the box's signal lands after the rebuild.
	self._query = ""
	if self._searchBox and self._searchBox.Text ~= "" then
		self._searchBox.Text = ""
	end
	self:_rebuildCars()
	self:_paint()
end

function Page:StartCloseThread()
	if self._spin then
		self._spin.stop()
		self._spin = nil
	end
end

return Page
