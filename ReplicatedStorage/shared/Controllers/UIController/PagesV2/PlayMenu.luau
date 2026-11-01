--[[
	PlayMenu page, V2 - PLAY ON ONE SCREEN  (client)
	------------------------------------------------
	"Where, in what, go." The world strip and the car strip, the pick shown big in the hero, and
	DRIVE. It replaces Play -> Worlds -> Select Car with one screen (2026-10-25), behind
	`StartCarConfig.OneScreenPlay`. `BuildPlayMenuV2` (Command Runner) draws it, and its header says
	what each part of the art is.

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
	car double-pressed in the Cars Inventory arrives already selected (`takePending`). The picked
	car's card is scrolled into the tray (`_reveal`), so a pick that is the tenth card is on screen.

	THE CARDS ARE SIZED IN PIXELS from the strip's rendered height, divided by the open tween's
	UIScale, because a scaled child of a ScrollingFrame resolves against the canvas (`KitPage`).
	The car pictures are drawn as their cards scroll into view rather than all at once: a strip of
	forty live viewports built on one frame is a hitch nobody needs for cards they never scroll to.

	=== DRAWN TO THE OWNER'S RENDER, 2026-10-25 ===============================================

	Dylan: "make the start frictionless". What of the render is behaviour lives here:
	  • THE HERO CAR IS A STILL THAT SWINGS IN. It was a turntable, and a turntable stands back far
	    enough to hold the car side-on, so at every other angle it was small in its own banner; and
	    the shared light comes from behind the car's far shoulder, so the flank in view was dark. Now
	    it is `HERO_SHOT`, a pose and light of its own fitted tight, and `CarViewport.arrive` swings
	    it in whenever the screen opens or the car changes.
	  • ONE PICKED LOOK (`_paintPicked`): rim, edge and check badge, on a world card and a car card
	    alike, the badge popping in when a card is newly picked. "Selected" is still written under the
	    world's name, as the render has it.
	  • TYPE IS SIZED OFF THE CARD rather than left to each label's `TextScaled`: a world's name wraps
	    onto a second line under a shared ceiling (FOREST / MOUNTAINS) instead of shrinking to a size
	    of its own, and the status line is measured (`_fitWorld`) so a price can wear the banknote and
	    the two stay centred together.
	  • THE SEARCH IS FOR A GARAGE BIGGER THAN THE TRAY: shown once the cars overflow it, or while it
	    holds a query. A garage of one free car gets `TEXT.Hint` in the tray's empty end instead.

	`StartOpenThread` runs a moment BEFORE `UIController` shows the page, so the swing and the pops
	ask `_live` (shown, or being opened) rather than `Visible`.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local InventoryConfig = require(ReplicatedStorage.shared.Configs.InventoryConfig)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)
local StartCarConfig = require(ReplicatedStorage.shared.Configs.StartCarConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local ArcadeKit = require(ReplicatedStorage.shared.Modules.ArcadeKit)
local CarCardDress = require(ReplicatedStorage.shared.Modules.CarCardDress)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)
local CarDetail = require(script.Parent.Parent.Components.CarDetailV2)
local KitPage = require(script.Parent.Parent.KitPage)

local Page = KitPage.extend(StartCarConfig.PlayPageName)

local NBSP = "\u{00A0}"
local WHITE_RAMP = ColorSequence.new(Color3.new(1, 1, 1))
--- A price, in the render's gold: green is what the kit pays OUT in, and "Selected" is green.
local PRICE_RAMP = ColorSequence.new(Color3.fromRGB(255, 240, 110), Color3.fromRGB(255, 186, 24))
--[[ The free car's face: the kit's blue, the panel's own colour, where a common body wears grey.
	FREE CAR is not a rarity and should not look like the lowest one; the render draws it blue, with
	its word in the green the kit pays out in. ]]
local FREE_FACE = ArcadeKit.Faces.Blue

--- The words. Statuses are in the render's sentence case; names stay in capitals.
local TEXT = {
	Ready = "Ready to drive",
	Selected = "Selected",
	Owned = "Owned",
	Confirm = "Confirm?",
	--- The road to drive to the end of, as the render says it, and how far down it once started.
	Needs = "Complete %s",
	NeedsStarted = "Complete %s %s",
	--- A softened rule (`RequirePrevious` below 1) has to say both numbers, as the Worlds page does.
	NeedsPart = "%s: %s / %s",
	FreeCar = "FREE CAR",
	Hint = "Steal cars on the road to drive them here!",
}

--- Each card's width over its height. The world strip fits every world across instead (never
--- wider than `WORLD_ASPECT`), so no world is ever half off the edge. `CAR_ASPECT` is also
--- `BuildPlayMenuV2`'s, which fits the card's sunray to it.
local WORLD_ASPECT = 1
local CAR_ASPECT = 2.5
--[[ As shares of the strip's height. The borders are drawn OUTSIDE the cards (scaled strokes), and a
	picked card's rim and edge reach further, so the gap clears two of those. The tray's margin also
	has to clear the check badge and the hover swell, because its list clips; the world row does not
	clip (`BuildPlayMenuV2`), so its margin only has to look right. ]]
local GAP = 0.15
local WORLD_INSET = 0.06
local CAR_INSET = 0.11
--[[ The cards' type, as shares of the card's height ("TYPE IS SIZED OFF THE CARD"). `STATUS_HEIGHT`
	and `STATUS_WIDTH` are the `StatusLine` box `BuildPlayMenuV2` draws. ]]
local TITLE_CAP = 0.15
local STATUS_CAP = 0.12
local STATUS_HEIGHT = 0.14
local STATUS_WIDTH = 0.92
local NAME_CAP = 0.2
local RARITY_CAP = 0.15
--- One line of a car's name, as a share of the card's height: its ceiling and the leading under it.
local NAME_LINE = NAME_CAP * 1.3
--- The banknote's width over its height as stored (`UIAssets.Size`), and its share of the line.
local CASH_ASPECT = UIAssets.Size.CashIcon.X / UIAssets.Size.CashIcon.Y
local CASH_HEIGHT = 0.92
--- The tray's hint is no wider than this many card heights, so it reads as a note beside the card.
local HINT_WIDTH = 3.4

--[[ The hero's shot (`CarViewport.Options`; header). A touch further round and lower than the
	cards' pose, for a banner much wider than it is tall, and lit from the lens side. ]]
local HERO_SHOT = {
	yaw = 222,
	pitch = 11,
	light = Vector3.new(0.55, -1, 0.5).Unit,
	ambient = Color3.fromRGB(150, 155, 170),
}
--- The hero car box's shape before it has ever been laid out, so a first fit is close.
local HERO_ASPECT = 3
--[[ The hero's viewport over its box. `CarViewport` fits every part's BOX, and a car's boxes stand
	clear of its paint (measured 2026-10-25: the Civaro filled 78% of the banner's height at a tight
	fit), so the frame is drawn this much bigger, centred, and the banner clips the empty margin. ]]
local HERO_ZOOM = 1.14
--- What the hero car's edge blends into: the sky of the panoramas behind it (`CarViewport.new`).
local HERO_BACKDROP = Color3.fromRGB(110, 190, 250)
--- A newly picked card's badge, popping in.
local POP = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
--[[ A locked world's shake when pressed, in degrees, one step a frame-and-a-bit. `WorldController`
	deliberately does nothing with that press ("you cannot go there yet") and leaves the card to say
	why; the shake only shows the press landed, and sends the eye to the line that says it. ]]
local SHAKE = { -6, 5, -3, 2, 0 }
local SHAKE_STEP = 0.04
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

--[[ A label's `Ceiling`, the size its `TextScaled` may grow to, in this card's pixels. Named so by
	`BuildPlayMenuV2` because `KitPage.scaleTextCaps` leaves a constraint called that alone. ]]
local function setCeiling(label: Instance?, size: number)
	local cap = label and label:FindFirstChild("Ceiling")
	if cap and cap:IsA("UITextSizeConstraint") then
		cap.MaxTextSize = math.clamp(math.round(size), 1, 100)
	end
end

local function worldThumb(index: number): number
	local map = WorldConfig.mapFor(index)
	local card = map and UIAssets.WorldCards[map]
	return if card then card.Thumb else UIAssets.worldThumb(map)
end

--[[ A car's name for its card: `carName`, with the one space between the colour and the model made
	breakable. `carName` joins every word with a non-breaking space so it prints on one line wherever
	it goes; on the plate BLACK SENERA would rather wrap there than shrink, and a model's own words
	(MAVIK 4) still never part. ]]
local function plateName(body: string, paint: number): string
	local model = GarageConfig.displayName(body)
	local full = GarageConfig.carName(body, paint)
	if #full <= #model then
		return full
	end
	return string.sub(full, 1, #full - #model - #NBSP) .. " " .. model
end

--- "62%", floored: a card that says 100% while its world is still locked is worse than 99%.
local function percent(fraction: number): string
	return string.format("%d%%", math.floor(fraction * 100))
end

--- The status line of a world whose previous road has not been driven to the end yet.
local function needsText(state): string
	local required = state.required or 1
	local progress = math.clamp(state.progress or 0, 0, required)
	local road = state.previousShort or state.previousName or "?"
	if required < 1 then
		return string.format(TEXT.NeedsPart, road, percent(progress), percent(required))
	end
	if progress > 0 then
		return string.format(TEXT.NeedsStarted, road, percent(progress))
	end
	return string.format(TEXT.Needs, road)
end

--- The middle of a card's face gradient: what its car picture's edge should blend into
--- (`CarViewport.new`'s `backdrop`), so no dark fringe is traced round the car.
local function faceColour(card: Instance): Color3?
	local gradient = card:FindFirstChildOfClass("UIGradient")
	local keys = gradient and gradient.Color.Keypoints
	if not (keys and #keys > 0) then
		return nil
	end
	return keys[1].Value:Lerp(keys[#keys].Value, 0.5)
end

-- === Building ===============================================================

function Page.initialize(self)
	KitPage.scaleTextCaps(self.PageUI)
	self.Player = (self.UIController and self.UIController.Player) or Players.LocalPlayer
	self:setTitle("Play")

	local main = self.Main :: GuiObject
	local hero = main:FindFirstChild("Hero")
	local carBox = hero and hero:FindFirstChild("Car")
	local footer = main:FindFirstChild("Footer")
	local summary = footer and footer:FindFirstChild("Summary")
	local cars = main:FindFirstChild("Cars")
	self._hero = {
		backdrop = hero and hero:FindFirstChild("Backdrop"),
		name = hero and hero:FindFirstChild("CarName"),
		view = if carBox and carBox:IsA("GuiObject") then CarViewport.new(carBox, "View", HERO_BACKDROP) else nil,
	}
	if self._hero.view then
		local view = self._hero.view
		view.AnchorPoint = Vector2.new(0.5, 0.5)
		view.Position = UDim2.fromScale(0.5, 0.5)
		view.Size = UDim2.fromScale(HERO_ZOOM, HERO_ZOOM)
	end
	setText(hero and hero:FindFirstChild("Tagline"), TEXT.Ready)
	self._summary = {
		thumb = summary and summary:FindFirstChild("Thumb"),
		text = summary and summary:FindFirstChild("Text"),
	}
	self._worldList = main:FindFirstChild("Worlds") and main.Worlds:FindFirstChild("List")
	self._carList = cars and cars:FindFirstChild("List")
	if not (self._worldList and self._carList) then
		warn("[PlayMenu] The page is missing its strips; run BuildPlayMenuV2.")
		self._worldList = nil
		return
	end

	--- The two cards are templates: taken out of their strips and cloned per world / per car.
	self._worldTemplate = self._worldList:FindFirstChild("WorldCard")
	self._carTemplate = self._carList:FindFirstChild("CarCard")
	if not (self._worldTemplate and self._carTemplate and self._worldTemplate:FindFirstChild("StatusLine")) then
		warn("[PlayMenu] The page's cards are out of date; run BuildPlayMenuV2.")
		self._worldList = nil
		return
	end
	for _, template in { self._worldTemplate, self._carTemplate } do
		template.Parent = nil
	end
	local status = self._worldTemplate:FindFirstChild("Status", true)
	local gradient = status and status:FindFirstChildOfClass("UIGradient")
	self._liveRamp = gradient and gradient.Color

	self._worlds = {} :: { [number]: any }
	for index in WorldConfig.Worlds do
		self._worlds[index] = self:_makeWorld(index)
	end
	self._cars = {} :: { any }
	self._car = StartCarConfig.DefaultKey
	self._query = ""
	self._note = cars:FindFirstChild("Note")
	self._hint = cars:FindFirstChild("Hint")
	if self._hint and self._hint:IsA("TextLabel") then
		--- Plain spaces: the hint is the one label here that is meant to wrap.
		self._hint.Text = TEXT.Hint
	end
	self._search = main:FindFirstChild("Search")
	self._searchBox = self._search and self._search:FindFirstChildWhichIsA("TextBox")
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

--- Shown, or being opened: `StartOpenThread` runs just before `UIController` shows the page.
function Page:_live(): boolean
	return self.PageUI.Visible or self._opening == true
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
	local title = card:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		--- Plain spaces, so a long name wraps onto a second line rather than shrinking (header).
		title.Text = string.upper(WorldConfig.displayName(index))
	end
	local line = card:FindFirstChild("StatusLine")
	local icon = line and line:FindFirstChild("Icon")
	if icon and icon:IsA("ImageLabel") then
		--- The one glyph this line wears, in front of a price; `_paintWorlds` shows it.
		icon.Image = UIAssets.url(UIAssets.WorldsPage.Cash)
		local shape = icon:FindFirstChildOfClass("UIAspectRatioConstraint")
		if shape then
			shape.AspectRatio = CASH_ASPECT
		end
	end
	local entry = {
		card = card,
		title = title,
		status = line and line:FindFirstChild("Status"),
		icon = icon,
		rim = card:FindFirstChild("Rim"),
		edge = card:FindFirstChild("Edge"),
		badge = card:FindFirstChild("Badge"),
		dim = card:FindFirstChild("Dim"),
		lock = card:FindFirstChild("Lock"),
		locked = false,
	}
	local gloss = card:FindFirstChild("Gloss")
	local press = card:FindFirstChild("Press")
	if press and press:IsA("GuiButton") then
		--- The same swell and ring a car card gives under the pointer, so both strips answer alike.
		CarDetail.hoverCard(card, press, (gloss and gloss:FindFirstChild("Hover")) :: UIStroke?)
		--- Beside `WorldController`'s own answer to the press, never instead of it (`SHAKE`).
		press.Activated:Connect(function()
			if entry.locked then
				self:_shake(entry)
			end
		end)
	end
	card.Parent = self._worldList
	return entry
end

--- `SHAKE`, once at a time: a second press mid-shake is the same news and does not restart it.
function Page:_shake(entry)
	if entry.shaking then
		return
	end
	entry.shaking = true
	task.spawn(function()
		for _, angle in SHAKE do
			entry.card.Rotation = angle
			task.wait(SHAKE_STEP)
		end
		entry.shaking = false
	end)
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
	table.insert(self._cars, self:_makeCar(StartCarConfig.DefaultKey, starterBody, PaintConfig.StockIndex, nil, not ownsStock))
	for _, key in owned do
		if GarageConfig.modelKeyOf(key) == stock then
			continue
		end
		local body, paint, mutation = GarageConfig.parseCarKey(key)
		if body then
			table.insert(self._cars, self:_makeCar(key, body, paint or PaintConfig.StockIndex, mutation, false))
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

--[[ One car card. `free` is the world's starter as the car nobody owns: the blue face and FREE CAR
	in the kit's green (`FREE_FACE`), where an owned car wears its rarity's face and word. ]]
function Page:_makeCar(key: string, body: string, paint: number, mutation: string?, free: boolean)
	local card = self._carTemplate:Clone()
	card.Name = if StartCarConfig.isDefault(key) then "Starter" else key
	local entry = {
		key = key,
		body = body,
		paint = paint,
		mutation = mutation,
		card = card,
		title = card:FindFirstChild("Title"),
		rarity = card:FindFirstChild("Rarity"),
		rim = card:FindFirstChild("Rim"),
		edge = card:FindFirstChild("Edge"),
		badge = card:FindFirstChild("Badge"),
		drawn = false,
		search = normalize((if mutation then WeatherConfig.nameOf(mutation) .. " " else "") .. GarageConfig.carName(body, paint)),
	}
	if entry.title and entry.title:IsA("TextLabel") then
		entry.title.Text = plateName(body, paint)
	end
	local word = CarRarity.labelOf(body)
	setText(entry.rarity, if free then TEXT.FreeCar else string.upper(word))
	CarCardDress.apply(card, entry.title, entry.rarity, body, mutation)
	if free then
		ArcadeKit.paint(card, FREE_FACE)
		--- `CarCardDress` turned the word's tint off (a rarity word on its own face would vanish);
		--- on the blue face the kit's green reads, so it goes back on in that.
		local tint = entry.rarity and entry.rarity:FindFirstChild("Tint")
		if tint and tint:IsA("UIGradient") and self._liveRamp then
			tint.Color = self._liveRamp
			tint.Enabled = true
		end
	end
	--- The kit's placeholder picture goes; the car is drawn over the same box when it scrolls in, its
	--- edge blending into the face just painted (`faceColour`).
	local icon = card:FindFirstChild("Icon")
	if icon and icon:IsA("GuiObject") then
		if icon:IsA("ImageLabel") then
			icon.Image = ""
		end
		local view = CarViewport.new(card, "Car", faceColour(card))
		view.AnchorPoint, view.Position, view.Size, view.ZIndex = icon.AnchorPoint, icon.Position, icon.Size, icon.ZIndex
		entry.viewport = view
		entry.viewAspect = CAR_ASPECT * icon.Size.X.Scale / math.max(icon.Size.Y.Scale, 0.01)
	end
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

--[[ One strip's cards in pixels and, for a scrolling strip, the canvas to fit them. `fit` lays every
	card across the strip's width (centred, no scrolling) at up to `aspect`; otherwise each is
	`aspect` wide and the strip scrolls. Returns the card's width and height, the gap, the margin, and
	how far the cards run past the strip's window (negative when they fit). ]]
local function layStrip(list: GuiObject, cards: { GuiObject }, aspect: number, k: number, fit: boolean, margin: number): (number, number, number, number, number)
	local width, height = list.AbsoluteSize.X / k, list.AbsoluteSize.Y / k
	local inset = height * margin
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
	if list:IsA("ScrollingFrame") then
		list.CanvasSize = UDim2.fromOffset(if fit then math.min(content, width) else content, 0)
	end
	return w, h, gap, inset, content - width
end

function Page:_layout()
	if not self._worldList then
		return
	end
	--- The open tween's UIScale is in every AbsoluteSize; offsets inside it get scaled again.
	local scale = self.PageUI:FindFirstChildOfClass("UIScale")
	local k = if scale and scale.Scale > 0 then scale.Scale else 1
	self._k = k
	local worldCards = {}
	for _, entry in self._worlds do
		table.insert(worldCards, entry.card)
	end
	table.sort(worldCards, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	local worldWidth, worldHeight = layStrip(self._worldList, worldCards, WORLD_ASPECT, k, true, WORLD_INSET)
	self._worldCard = Vector2.new(worldWidth, worldHeight)
	for _, entry in self._worlds do
		self:_fitWorld(entry)
	end

	--- Only the cars the search shows; `slot` is each one's place in that row, for `_drawVisible`.
	local carCards = {}
	for _, entry in self._cars do
		entry.slot = nil
		if entry.card.Visible then
			table.insert(carCards, entry.card)
			entry.slot = #carCards
		end
	end
	local carWidth, carHeight, gap, inset, overflow = layStrip(self._carList, carCards, CAR_ASPECT, k, false, CAR_INSET)
	self._carPitch, self._carInset = carWidth + gap, inset
	for _, entry in self._cars do
		self:_fitCarName(entry, carWidth, carHeight)
		setCeiling(entry.rarity, carHeight * RARITY_CAP)
	end
	--- The search is for a garage bigger than the tray (header). Kept up while it holds a query, or
	--- typing a name that fits would hide the box being typed in.
	if self._search and self._search:IsA("GuiObject") then
		self._search.Visible = overflow > 0.5 or self._query ~= ""
	end
	self:_placeHint(#carCards, carWidth + gap, inset, carHeight)
	--[[ The picked car is brought into the tray on open, and again on every step of the open tween:
		a scroll made at the tween's small first scale is clamped to that scale's canvas and does not
		grow back with it (`_canvasScale`). Done once the page is at full size. ]]
	if self._revealing then
		self:_reveal(self._revealing)
		if k >= 0.999 then
			self._revealing = nil
		end
	end
	self:_drawVisible()
end

--[[ How many of the tray's ABSOLUTE pixels make one of its canvas pixels, as the list itself was last
	laid out. `CanvasPosition` is in absolute pixels, not canvas ones (measured 2026-10-25: at a UIScale
	of 0.5 it halves, clamped to the scaled canvas), so every scroll sum goes through this rather than
	the page's own `UIScale`, which can be a frame ahead of the sizes. ]]
function Page:_canvasScale(): number
	local list = self._carList :: ScrollingFrame
	local canvas = list.CanvasSize.X.Offset
	if canvas > 0 and list.AbsoluteCanvasSize.X > 0 then
		return list.AbsoluteCanvasSize.X / canvas
	end
	return self._k or 1
end

--[[ A world card's type in its own pixels (header, "TYPE IS SIZED OFF THE CARD"): the name's ceiling,
	then the status line, measured with `TextService` (`TextBounds` lags a text change by a frame) so a
	price and its banknote are sized and centred as one. ]]
function Page:_fitWorld(entry)
	local size = self._worldCard
	if not (size and size.Y > 0) then
		return
	end
	setCeiling(entry.title, size.Y * TITLE_CAP)
	local status, icon = entry.status, entry.icon
	if not (status and status:IsA("TextLabel")) then
		return
	end
	local lineHeight = size.Y * STATUS_HEIGHT
	local gap = lineHeight * 0.18
	local room = size.X * STATUS_WIDTH
	if icon and icon.Visible then
		room -= lineHeight * CASH_HEIGHT * CASH_ASPECT + gap
	end
	local layout = status.Parent and status.Parent:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.Padding = UDim.new(0, gap)
	end
	local cap = math.max(1, math.round(size.Y * STATUS_CAP))
	local unbounded = Vector2.new(10000, 10000)
	local bounds = TextService:GetTextSize(status.Text, cap, Enum.Font.FredokaOne, unbounded)
	local textSize = cap
	if bounds.X > room and bounds.X > 0 then
		textSize = math.max(1, math.floor(cap * room / bounds.X))
		bounds = TextService:GetTextSize(status.Text, textSize, Enum.Font.FredokaOne, unbounded)
	end
	status.TextSize = textSize
	status.Size = UDim2.new(0, math.ceil(bounds.X) + 2, 1, 0)
end

--[[ A car card's name and rarity as one block, centred on the plate: the name on one line if it fits
	at its ceiling, else wrapped onto two, measured with `TextService` for `_fitWorld`'s reason. Kept
	per card until the card's size changes, because the open tween lays the tray out every frame. ]]
function Page:_fitCarName(entry, width: number, height: number)
	local title, rarity = entry.title, entry.rarity
	if not (title and title:IsA("TextLabel") and rarity and rarity:IsA("GuiObject")) then
		return
	end
	local cap = math.max(1, math.round(height * NAME_CAP))
	if entry.nameCap == cap then
		return
	end
	entry.nameCap = cap
	setCeiling(title, cap)
	local wide = TextService:GetTextSize(title.Text, cap, Enum.Font.FredokaOne, Vector2.new(10000, 10000)).X
	local lines = if wide > width * title.Size.X.Scale and string.find(title.Text, " ", 1, true) then 2 else 1
	local nameHeight = lines * NAME_LINE
	local rarityHeight = rarity.Size.Y.Scale
	local top = 0.5 - (nameHeight + rarityHeight) / 2
	--- The name's box hangs from its bottom edge (`BuildPlayMenuV2`), standing on the rarity.
	title.Size = UDim2.fromScale(title.Size.X.Scale, nameHeight)
	title.Position = UDim2.fromScale(title.Position.X.Scale, top + nameHeight)
	rarity.Position = UDim2.fromScale(rarity.Position.X.Scale, top + nameHeight + rarityHeight / 2)
end

--[[ The hint fills the tray's empty end after the cards, in the tray's own pixels: it is not in the
	list, so it never scrolls or counts towards the canvas. Only while the free car is the only car
	(and nothing is being searched), and only when the end left over is wide enough to say it in. ]]
function Page:_placeHint(shown: number, pitch: number, inset: number, cardHeight: number)
	local hint = self._hint
	if not (hint and hint:IsA("GuiObject")) then
		return
	end
	local tray = hint.Parent :: GuiObject
	local left = inset + shown * pitch
	local room = math.min(tray.AbsoluteSize.X / (self._k or 1) - left - inset, cardHeight * HINT_WIDTH)
	hint.Visible = #self._cars == 1 and shown == 1 and self._query == "" and room > cardHeight * 1.2
	if hint.Visible then
		hint.Position = UDim2.new(0, left, 0.5, 0)
		hint.Size = UDim2.new(0, room, 0, cardHeight * 0.62)
	end
end

--- Draw the cars whose cards are on screen or one card either side of it (canvas offset units).
function Page:_drawVisible()
	local pitch = self._carPitch
	if not (pitch and pitch > 0) then
		return
	end
	local scale = self:_canvasScale()
	local at = self._carList.CanvasPosition.X / scale
	local left = at - pitch
	local right = at + self._carList.AbsoluteWindowSize.X / scale + pitch
	for _, entry in self._cars do
		local x = ((entry.slot or 0) - 1) * pitch
		if entry.slot and not entry.drawn and entry.viewport and x + pitch >= left and x <= right then
			entry.drawn = true
			CarViewport.set(entry.viewport, entry.body, {
				paint = entry.paint,
				mutation = entry.mutation,
				aspect = entry.viewAspect or CAR_ASPECT,
			})
		end
	end
end

--[[ Scroll the tray so this car's card is in its window, by the least distance: a card already in
	view stays where it is. Worked in canvas pixels and written back in absolute ones (`_canvasScale`). ]]
function Page:_reveal(entry)
	local pitch = self._carPitch
	if not (entry and entry.slot and pitch and pitch > 0) then
		return
	end
	local list = self._carList :: ScrollingFrame
	local scale = self:_canvasScale()
	local window = list.AbsoluteWindowSize.X / scale
	local inset = self._carInset or 0
	local x = inset + (entry.slot - 1) * pitch
	local at = list.CanvasPosition.X / scale
	if x - inset < at then
		at = x - inset
	elseif x + pitch > at + window then
		at = x + pitch - window
	end
	list.CanvasPosition = Vector2.new(math.max(0, at) * scale, 0)
end

-- === Painting ===============================================================

--[[ The picked look, the same on both strips (header): the rim, its navy edge and the check badge.
	The badge pops in when a card BECOMES picked on a live screen, not on every repaint. ]]
function Page:_paintPicked(entry, picked: boolean)
	local was = entry.picked
	entry.picked = picked
	for _, line in { entry.rim, entry.edge } do
		if line and line:IsA("UIStroke") then
			line.Enabled = picked
		end
	end
	local badge = entry.badge
	if not (badge and badge:IsA("GuiObject")) then
		return
	end
	badge.Visible = picked
	local pop = badge:FindFirstChildOfClass("UIScale")
	if pop and picked and not was and self:_live() then
		pop.Scale = 0.4
		TweenService:Create(pop, POP, { Scale = 1 }):Play()
	end
end

--[[ Every world card from `WorldController:cardState`, the Worlds page's own answer:
	    play      Selected (rim and badge) / Owned
	    buy       its price behind the banknote, or Confirm? on the second press
	    needs     dimmed, a lock, and the road to complete before it ]]
function Page:_paintWorlds()
	local controller = Shard.get("WorldController")
	local chosen = self:_world()
	for index, entry in self._worlds do
		local state = if controller then controller:cardState(index) else { label = "play" }
		if state.label == "racing" then
			continue
		end
		local line, ramp, locked, priced = TEXT.Owned, self._liveRamp, false, false
		if state.label == "needs" then
			line, ramp, locked = needsText(state), WHITE_RAMP, true
		elseif state.label == "confirm" then
			line, ramp, priced = TEXT.Confirm, PRICE_RAMP, true
		elseif state.label == "buy" then
			line, ramp, priced = GarageConfig.formatCash(state.cost or 0), PRICE_RAMP, true
		elseif index == chosen then
			line = TEXT.Selected
		end
		setText(entry.status, line)
		local gradient = entry.status and entry.status:FindFirstChildOfClass("UIGradient")
		if gradient and ramp then
			gradient.Color = ramp
		end
		if entry.icon then
			entry.icon.Visible = priced
		end
		entry.locked = locked
		if entry.dim then
			entry.dim.Visible = locked
		end
		if entry.lock then
			entry.lock.Visible = locked
		end
		self:_paintPicked(entry, index == chosen and state.label == "play")
		self:_fitWorld(entry)
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
		self:_paintPicked(entry, entry == car)
	end
	local worldName = string.upper(WorldConfig.displayName(world))
	local carName = if car then string.upper(GarageConfig.carName(car.body, car.paint)) else ""
	setText(self._hero.name, carName)
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

--[[ The big car (header): set at the hero's own shot, then swung into it. Only redrawn when the car
	changes or the screen opens (`StartOpenThread` forgets the key), so picking a world that keeps the
	same car leaves it standing. ]]
function Page:_showHeroCar(car)
	local view = self._hero.view
	if not (view and car) then
		return
	end
	local key = car.key .. "|" .. car.body
	if self._heroKey == key then
		return
	end
	self._heroKey = key
	if self._arrival then
		self._arrival.stop()
		self._arrival = nil
	end
	--- The zoomed frame and its box share a shape, so the aspect read off the frame is the box's.
	local size = view.AbsoluteSize
	local aspect = if size.Y > 0 then size.X / size.Y else HERO_ASPECT
	local shot = {
		paint = car.paint,
		mutation = car.mutation,
		aspect = aspect,
		yaw = HERO_SHOT.yaw,
		pitch = HERO_SHOT.pitch,
		light = HERO_SHOT.light,
		ambient = HERO_SHOT.ambient,
	}
	if CarViewport.set(view, car.body, shot) and self:_live() then
		self._arrival = CarViewport.arrive(view, { aspect = aspect, yaw = HERO_SHOT.yaw, pitch = HERO_SHOT.pitch })
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
	--- A search typed last time is cleared, by hand as well: the box's signal lands after the rebuild.
	self._query = ""
	if self._searchBox and self._searchBox.Text ~= "" then
		self._searchBox.Text = ""
	end
	--- Every open swings the hero in and pops the picked badges, not only a change of pick (header).
	self._heroKey = nil
	for _, entry in self._worlds do
		entry.picked = nil
	end
	self._opening = true
	self:_rebuildCars()
	self:_paint()
	self._revealing = self:_selectedCar()
	self:_reveal(self._revealing)
	self._opening = false
end

function Page:StartCloseThread()
	if self._arrival then
		self._arrival.stop()
		self._arrival = nil
	end
end

return Page
