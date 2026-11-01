--[[
	StartCar page  (client)
	-----------------------
	"Which of my cars am I driving into this world?" — the third and last step of Play (Trello:
	PLAY → SELECT WORLD → ALLOW USER TO CHANGE CAR), opened by pressing a world card and closed by
	pressing a car, which is what actually starts the run.

	SEVEN THINGS TO KNOW BEFORE CHANGING ANY OF IT.

	1. IT IS THE SPAWN CARS PAGE'S TWIN, DELIBERATELY AND ALMOST EXACTLY. Same question shape (pick
	   one of your cars), same art, same machinery: samples measured out of the place, a UIGridLayout
	   in a ScrollingFrame, the authored scrollbar driven by hand, the collection read off a player
	   attribute, `Modules/CarViewportGrid` drawing the cars. The art in the place is a copy of that
	   page's with a different title, so IF YOU FIX A LAYOUT BUG IN ONE OF THESE TWO FILES, THE OTHER
	   ONE HAS IT TOO. What differs is only what a card MEANS: there it puts a car in the street, here
	   it starts a race in one.

	2. THE THREE CARDS IN THE PLACE ARE A LAYOUT SAMPLE, NOT THE LIST. The first is cloned once per
	   entry into a UIGridLayout and `Cards` is emptied at runtime. Cell size, column count and the
	   column gap are all MEASURED off those samples rather than typed in here — three samples is
	   what says "three columns", so adding a fourth in the Explorer widens the grid with no code
	   change.

	3. THE WORLD'S OWN STARTER IS ALWAYS AVAILABLE and is not a car out of the collection: its
	   key is `StartCarConfig.DefaultKey` (the empty string), which the server reads as "resolve
	   `WorldConfig.startBodyFor` at spawn time". That is what makes this screen safe to put in front
	   of every player on their very first run — a brand-new collection is not an empty page, it is a
	   page with the car they have always been given on it.

	   An owned copy of that same body in stock livery is skipped, because it would be a second card
	   for the identical car. A COLOURED copy is not skipped: that is a different car (see note 6).

	4. THE PRESS DOES NOT DECIDE ANYTHING. It publishes `StartCarConfig.PickEvent` and stops;
	   `StartCarController` pairs the car with the world this screen was opened for and hands both to
	   `RaceEntryController`, and the server owns whether you may drive it — a car it refuses becomes
	   the world's starter rather than a refused race (`StartCarService`). This page does not
	   optimistically repaint either: the `StartCar` attribute comes back and repaints it for real,
	   which is one code path instead of two.

	5. PRESSING A CAR STARTS THE RUN. There is no GO button and there is not meant to be one — this
	   is the last step of Play, and the world screen before it makes the same call about its own
	   cards. The X closes the screen without racing, and leaves you exactly where you were: nothing
	   has moved the player at the point this screen is up.

	6. THE CARS ON THE CARDS ARE A VIRTUALISED LIST, and `Modules/CarViewportGrid` is the whole of
	   it — read that module's header. This page's half is two calls: `_applyLayout` hands over the
	   cell geometry it has just worked out, and `_rebuild` hands over the cards in grid order.

	   THE COLOUR IS NOT DECORATION: one card is one KEY, body and colour both, so the picture is
	   what tells two of your three Camaros apart at a glance — and driving off in the red one you
	   stole rather than "a Camaro" is most of the point of the feature.

	7. IT REBUILDS ON EVERY OPEN, unlike its twin, because the world can be different every time it
	   is opened and the world decides both the starter card and (with
	   `StartCarConfig.WorldLadderOnly`) which owned cars are offered at all.

	HOUSE RULE: no wiki-style double-bracket links in this comment — the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UIControllerTypes = require(script.Parent.Parent.UIControllerTypes)
local UIGeom = require(script.Parent.Parent.UIGeom)
local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)
local StartCarConfig = require(ReplicatedStorage.shared.Configs.StartCarConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)
local CarViewportGrid = require(ReplicatedStorage.shared.Modules.CarViewportGrid)

local PAGE_NAME = StartCarConfig.PageName

-- Non-breaking spaces: TextScaled would rather wrap to a second line than shrink.
local DRIVE_TEXT = "DRIVE"
local SELECTED_TEXT = "SELECTED"
local NO_CARS_TEXT = "STEAL\u{00A0}A\u{00A0}CAR\u{00A0}FIRST"

-- The card the server has stored says so in white; the rest read as an invitation in the kit's
-- muted grey. Colour is the whole marker — see header note 4 on why it is never a repaint.
local SELECTED_COLOR = Color3.new(1, 1, 1)

--[[ How far a card swells under a cursor, read off the `Scale` attribute by `Components/Button`.
	Under that component's 1.05 default because a card is a big object and 5% of one is a lurch —
	the same number the SPAWN CARS page gives its cards, since they are the same authored card. ]]
local CARD_HOVER_SCALE = 1.02

-- Shortest the scroll thumb may get, as a fraction of its track.
local MIN_THUMB = 0.08

-- Where the car stands on a card, in fractions of it. Identical to the SPAWN CARS page's for the
-- reason in header note 1: it is the same authored card, and its four label positions are the
-- layout the car has to be fitted around.
local VIEW_WIDTH = 0.78
local VIEW_HEIGHT = 0.42
local VIEW_CENTRE_X = 0.585
local VIEW_CENTRE_Y = 0.41

--- A body's game name, on one line. `GarageConfig.displayName` since 2026-09-28: this page had its own
--- copy of the spacing rule, which would have printed the real car names `CarNameConfig` replaces.
local function displayName(body: string): string
	return GarageConfig.displayName(body)
end

--[[ What one card is called: "RED CAMARO", or just "CAMARO" for a car in its authored livery.

	Same rule and same wording as the dealership and SPAWN CARS screens', because it is the same list
	of cars seen from a third question. Stock takes no prefix: it is the car's own look rather than a
	colour choice, and "STOCK CAMARO" reads as a trim level. ]]
local function cardName(body: string, paint: number): string
	local name = displayName(body)
	--- One-colour bodies too: `GarageConfig.carName`'s rule.
	if paint == PaintConfig.StockIndex or #PaintConfig.poolFor(body) <= 1 then
		return name
	end
	return string.upper(string.gsub(PaintConfig.nameOf(paint), " ", "\u{00A0}")) .. "\u{00A0}" .. name
end

local Page = {}
Page.__index = Page

function Page.new(UIController: UIControllerTypes.UIController)
	local self = setmetatable({}, Page)
	self.UIController = UIController
	self.Player = UIController.Player or Players.LocalPlayer

	local mainUI = UIController.PlayerGui:WaitForChild("MainUI")
	self.PageUI = mainUI:WaitForChild("Pages"):WaitForChild(PAGE_NAME)

	self.Title = self.PageUI:WaitForChild("Title")
	self.Cards = self.PageUI:WaitForChild("Cards")
	self.ScrollBar = self.PageUI:WaitForChild("ScrollBar")

	self._entries = {}

	-- A LOCAL, never `self.Close`: the controller treats a `Close` field on a page as that page's
	-- custom close ROUTINE and calls it, so parking the button there makes closing throw.
	local close = self.PageUI:WaitForChild("Close")
	close.MouseButton1Click:Connect(function()
		self.UIController:closePage(PAGE_NAME)
	end)

	self:_buildGrid()
	self:_watchState()

	return self
end

function Page.initialize(_self) end

-- === Layout =================================================================

--[[ Grid metrics read back off the authored samples — header note 2. Everything is in PAGE scale
	(the coordinate space the mock-up was positioned in) until the offset pass in `_applyLayout`. ]]
function Page:_measure(samples: { GuiObject })
	local template = samples[1]
	local cardWidth = template.Size.X.Scale
	local cardHeight = template.Size.Y.Scale
	-- Edges, not raw Position: the samples are centre-anchored like the rest of the kit, so their
	-- Position is a centre. See UIGeom.
	local left, top = UIGeom.topLeft(template)
	local columns = math.max(#samples, 1)

	local gapX = if samples[2] then UIGeom.left(samples[2]) - left - cardWidth else 0
	gapX = math.max(gapX, 0)

	-- Square in PIXELS, not in scale: this page is 1.6x wider than it is tall, so a gap equal in
	-- scale is a third as tall on screen as it is wide.
	local aspectConstraint = self.PageUI:FindFirstChildOfClass("UIAspectRatioConstraint")
	local aspect = aspectConstraint and aspectConstraint.AspectRatio or 1
	local gapY = gapX * aspect

	local width = columns * cardWidth + (columns - 1) * gapX

	-- The list runs from the first row down to the bottom of the panel, inset by the same margin the
	-- artist left between the title bar and that first row. There is no bottom bar on this page — the
	-- panel IS the page box — so the floor is 1, not a Done button's position.
	local margin = math.max(top - UIGeom.bottom(self.Title), 0)
	local height = 1 - margin - top
	if height <= cardHeight then
		height = cardHeight
	end

	return {
		left = left,
		top = top,
		width = width,
		height = height,
		columns = columns,
		cardHeight = cardHeight,
		cellHeight = cardHeight / height,
		padX = gapX / width,
		padY = gapY / height,
	}
end

function Page:_buildGrid()
	local samples = {}
	for _, child in self.Cards:GetChildren() do
		if child:IsA("GuiObject") then
			table.insert(samples, child)
		end
	end
	table.sort(samples, function(a, b)
		return UIGeom.left(a) < UIGeom.left(b)
	end)

	if #samples == 0 then
		warn(`[{PAGE_NAME}] no sample card under Cards — the list needs one to clone. Page left empty.`)
		return
	end

	self._template = samples[1]:Clone()
	local grid = self:_measure(samples)
	self._grid = grid

	for _, child in self.Cards:GetChildren() do
		child:Destroy()
	end

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ClipsDescendants = true
	scroll.Position = UDim2.fromScale(grid.left, grid.top)
	scroll.Size = UDim2.fromScale(grid.width, grid.height)
	scroll.ZIndex = self.Cards.ZIndex
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 0 -- the authored ScrollBar image stands in
	scroll.ScrollBarImageTransparency = 1
	scroll.CanvasSize = UDim2.new()
	scroll.Active = true
	scroll.Parent = self.Cards
	self._scroll = scroll

	-- Header note 6. Made before the first layout pass, which is what hands it the cell geometry.
	self._views = CarViewportGrid.new(scroll, self.PageUI)

	local layout = Instance.new("UIGridLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.FillDirectionMaxCells = grid.columns
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Parent = scroll
	self._layout = layout

	--[[ Shown when there is nothing to list at all. The starter card means that should never happen —
		it is here for the case where the world's start body is missing from the config, which is a
		broken page rather than an empty collection, so the panel is never a bare well. ]]
	local empty = Instance.new("TextLabel")
	empty.Name = "NoCars"
	empty.BackgroundTransparency = 1
	empty.AnchorPoint = Vector2.new(0.5, 0.5)
	empty.Size = UDim2.fromScale(grid.width, grid.cardHeight * 0.35)
	UIGeom.place(empty, grid.left, grid.top + grid.height * 0.35)
	empty.ZIndex = self.Cards.ZIndex + 1
	empty.FontFace = self.Title.FontFace
	empty.TextColor3 = Color3.fromRGB(123, 133, 169)
	empty.TextScaled = true
	empty.Text = NO_CARS_TEXT
	empty.Visible = false
	empty.Parent = self.Cards
	self._empty = empty

	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_applyLayout()
	end)
	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:_updateScrollBar()
	end)

	self:_bindScrollBarDrag()
end

--[[ Cell geometry in offset, from the viewport's live pixel size.

	The cell WIDTH is derived from the padding rather than measured alongside it, so a row always
	adds up to exactly the viewport width no matter how the fractions round. ]]
function Page:_applyLayout()
	local scroll, grid, layout = self._scroll, self._grid, self._layout
	if not (scroll and grid and layout) then
		return
	end

	local size = scroll.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return -- not laid out yet; the AbsoluteSize signal brings us back
	end

	local padX = grid.padX * size.X
	local padY = grid.padY * size.Y
	local cellWidth = (size.X - padX * (grid.columns - 1)) / grid.columns
	local cellHeight = grid.cellHeight * size.Y

	layout.CellSize = UDim2.fromOffset(cellWidth, cellHeight)
	layout.CellPadding = UDim2.fromOffset(padX, padY)

	-- The same geometry, handed to the viewport grid so its window test runs against the numbers the
	-- cards are actually laid out with rather than a second copy that can disagree.
	if self._views then
		self._views:setLayout(
			grid.columns,
			cellHeight + padY,
			cellHeight,
			0,
			(VIEW_WIDTH * cellWidth) / (VIEW_HEIGHT * cellHeight)
		)
	end

	local rows = math.ceil(#self._entries / grid.columns)
	local canvas = if rows > 0 then rows * cellHeight + (rows - 1) * padY else 0
	scroll.CanvasSize = UDim2.fromOffset(0, canvas)

	self:_updateScrollBar()
end

-- === The authored scrollbar =================================================

function Page:_updateScrollBar()
	local scroll, bar, grid = self._scroll, self.ScrollBar, self._grid
	if not (scroll and bar and grid) then
		return
	end

	local window = scroll.AbsoluteWindowSize.Y
	local canvas = scroll.AbsoluteCanvasSize.Y
	if window <= 0 or canvas <= window + 1 then
		bar.Visible = false
		return
	end

	local track = grid.height
	local thumb = math.max(track * (window / canvas), track * MIN_THUMB)
	local progress = math.clamp(scroll.CanvasPosition.Y / (canvas - window), 0, 1)

	bar.Visible = true
	-- Size first: `place` corrects against the bar's current height, so a thumb resized afterwards
	-- would be positioned by the old one.
	bar.Size = UDim2.fromScale(bar.Size.X.Scale, thumb)
	UIGeom.place(bar, UIGeom.left(bar), grid.top + progress * (track - thumb))
end

--[[ Dragging the thumb, worked from the DELTA since the grab rather than from where the pointer is:
	AbsolutePosition and the pointer's own coordinates disagree by the Gui inset, and a delta cannot
	be wrong about an offset that is the same at both ends. ]]
function Page:_bindScrollBarDrag()
	local scroll, bar = self._scroll, self.ScrollBar
	if not (scroll and bar) then
		return
	end

	bar.Active = true
	local drag: { pointer: number, canvas: number }? = nil

	local function isDragInput(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end

	bar.InputBegan:Connect(function(input)
		if isDragInput(input) then
			drag = { pointer = input.Position.Y, canvas = scroll.CanvasPosition.Y }
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not drag then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local scrollable = scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y
		local travel = scroll.AbsoluteSize.Y - bar.AbsoluteSize.Y
		if scrollable <= 0 or travel <= 0 then
			return
		end

		local moved = (input.Position.Y - drag.pointer) * (scrollable / travel)
		scroll.CanvasPosition = Vector2.new(0, math.clamp(drag.canvas + moved, 0, scrollable))
	end)

	UserInputService.InputEnded:Connect(function(input)
		if isDragInput(input) then
			drag = nil
		end
	end)
end

-- === The list ===============================================================

--[[ One card. `key` is the car key the press sends — "Body:paint" for a car out of the collection,
	or `StartCarConfig.DefaultKey` for the world's own starter, whose body is passed in because there
	is no key to read it out of. ]]
function Page:_makeCard(key: string, body: string?, paint: number, order: number, mutation: string?)
	local card = self._template:Clone()
	card.Name = if key == StartCarConfig.DefaultKey then "Starter" else key
	card.LayoutOrder = order

	local name = card:FindFirstChild("CarName") :: TextLabel
	local rating = card:FindFirstChild("Rating") :: TextLabel
	local status = card:FindFirstChild("Status") :: TextLabel

	local tier = body and GarageConfig.TierOfBody[body]
	name.Text = if body then cardName(body, paint) else string.upper(key)
	rating.Text = if tier then tostring(tier) else "?"

	--[[ The car's own frame, empty for now: `CarViewportGrid` fills it in — and empties it again — as
		the list scrolls past, and header note 6 is why.

		Behind the card's four labels and still in front of the card's own art, which is one number
		because the GUI is `ZIndexBehavior.Sibling`: ZIndex orders a child against its SIBLINGS only,
		and a descendant always draws over its ancestor whatever it is set to. ]]
	local viewport = CarViewport.new(card, "CarView")
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(VIEW_CENTRE_X, VIEW_CENTRE_Y)
	viewport.Size = UDim2.fromScale(VIEW_WIDTH, VIEW_HEIGHT)
	viewport.ZIndex = 0

	card.Parent = self._scroll

	--[[ A CARD IS A BUTTON, so it carries the tag and gets the game's hover swell and its two sounds.
		Only possible since 2026-08-19: the swell used to be written to `Size`, and a `UIGridLayout` cell
		is drawn at the layout's CellSize whatever its own `Size` says — the tween was written and then
		ignored. It rides a UIScale now, so a lifted card moves nothing else in the grid. Measured at
		+2% on a 180x157 cell with its neighbours standing still. See `Components/Button`.

		No `Page` and no `Action` — what pressing a card MEANS is `_choose`, wired below, because it is
		a choice about a car this page is holding. ]]
	card:SetAttribute("Scale", CARD_HOVER_SCALE)
	CollectionService:AddTag(card, "UIButton")

	--[[ A RELEASE ONLY COUNTS IF ITS PRESS BEGAN ON THIS CARD, and that guard is the whole of the
		24 Aug "no time to choose a vehicle" bug (Flaquitajs, mobile).

		WHAT HAPPENED. The world card before this screen presses on the way DOWN — every tagged
		`UIButton` does, see `Components/Button` — and `UIController:openPage` draws this page in the
		same frame, with no lockout. So on a touch screen one finger did both steps: the DOWN chose
		CITY and painted the car grid under the finger, and the engine handed the release to whatever
		was under it by then, which was a card. In the clip the tap point on CITY's PLAY is dead
		centre of the CYAN GOLF GTI cell, and that is the car the run started in — 0.64s after the
		screen appeared. The player never chose anything.

		WHY NOT JUST MOVE TO `MouseButton1Down` like the rest of the kit. These cards are in a
		ScrollingFrame. A finger coming down on one may be starting a scroll, and Roblox cancels the
		CLICK when a drag turns out to be a scroll — it cannot cancel a down that has already fired.
		Acting on the down would start a race every time somebody tried to scroll their collection,
		which is a worse bug than this one.

		So the release stays the verb and the press is what arms it: `InputBegan` is the only event
		that says the press STARTED here, and a release with no matching press is somebody else's
		press finishing. Gamepad has no `InputBegan` to arm — it comes in on `Activated`, filtered to
		a controller input exactly as `Pages/Dealership` filters its own. ]]
	local armed = false
	card.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			armed = true
		end
	end)

	card.MouseButton1Click:Connect(function()
		if not armed then
			return
		end
		armed = false
		self:_choose(key)
	end)

	card.Activated:Connect(function(inputObject: InputObject?)
		-- Controller only; the pointer's own press already came in on `MouseButton1Click` above.
		if not inputObject or inputObject.UserInputType.Name:sub(1, 7) ~= "Gamepad" then
			return
		end
		armed = false
		self:_choose(key)
	end)

	-- The entry IS the grid's cell — `viewport`, `body` and `paint` are the fields `CarViewportGrid`
	-- reads, and it keeps its own bookkeeping alongside them. One table rather than two, so there is
	-- no pairing to keep in step.
	return {
		key = key,
		body = body,
		paint = paint,
		mutation = mutation,
		viewport = viewport,
		card = card,
		status = status,
		idleColor = status.TextColor3,
	}
end

--[[ Rebuild the list for the world this screen was opened for, best first including the starter.

	The controller owns both lists — which world this is and which cars qualify — so the rule about
	what may be driven where is written down once, next to the server's copy of it. ]]
function Page:_rebuild()
	if not self._scroll then
		return
	end

	for _, entry in self._entries do
		entry.card:Destroy()
	end
	table.clear(self._entries)

	local controller = Shard.get("StartCarController")
	local world = if controller then controller:world() else WorldConfig.ActiveIndex

	--[[ Header note 3: the starter is always offered, and an owned copy of the same body in the same
		(stock) livery is skipped rather than drawn as a second identical card. A COLOURED copy of it
		is a different car and stays. ]]
	local starterBody = if controller and controller:mode() ~= "race" then nil else WorldConfig.startBodyFor(world)
	local skip: string? = nil
	if starterBody then
		table.insert(self._entries, self:_makeCard(StartCarConfig.DefaultKey, starterBody, PaintConfig.StockIndex, 1))
		skip = GarageConfig.carKey(starterBody, PaintConfig.StockIndex)
	end

	local owned = if controller then controller:driveable(world) else {}
	for _, key in owned do
		if GarageConfig.modelKeyOf(key) == skip then
			continue
		end
		local body, paint, mutation = GarageConfig.parseCarKey(key)
		table.insert(self._entries, self:_makeCard(key, body, paint or PaintConfig.StockIndex, #self._entries + 1, mutation))
	end

	if self._empty then
		self._empty.Visible = #self._entries == 0
	end
	-- Keep the legacy page in the same best-to-worst order as PagesV2/StartCar (2026-10-04).
	table.sort(self._entries, function(a, b)
		local ta = GarageConfig.TierOfBody[a.body] or 0
		local tb = GarageConfig.TierOfBody[b.body] or 0
		return if ta ~= tb then ta > tb else a.key < b.key
	end)
	for order, entry in self._entries do
		entry.card.LayoutOrder = order
	end

	self._scroll.CanvasPosition = Vector2.new(0, 0)
	self:_applyLayout()
	-- After the layout, so the grid tests the new list against the new canvas rather than the old
	-- one. Every card is a cell and every cell has a car — there are no spacers on this page — and
	-- `_entries` is built in LayoutOrder order, so it IS the grid order the module asks for.
	if self._views then
		self._views:setCells(self._entries)
	end
end

--[[ Repaint which card the server has stored, without rebuilding. Runs on every change to the
	`StartCar` attribute and on every open, so it is the one that has to be cheap. ]]
function Page:_refresh()
	local controller = Shard.get("StartCarController")
	self.Title.Text = if controller and controller:mode() == "sell" then "SELL YOUR CARS" else "SELECT CAR"
	local chosen = if controller then controller:selected() else StartCarConfig.DefaultKey
	for _, entry in self._entries do
		local here = entry.key == chosen
		entry.status.Text = if controller and controller:mode() == "sell" then "SELL" elseif here then SELECTED_TEXT else DRIVE_TEXT
		entry.status.TextColor3 = if here then SELECTED_COLOR else entry.idleColor
	end
end

--- A card was clicked. Say which one and stop — header note 4.
function Page:_choose(key: string)
	Dispatcher:Publish(StartCarConfig.PickEvent, key)
end

function Page:_watchState()
	self:_rebuild()
	self:_refresh()

	self.Player:GetAttributeChangedSignal(GarageConfig.OwnedAttribute):Connect(function()
		self:_rebuild()
		self:_refresh()
	end)
	self.Player:GetAttributeChangedSignal(StartCarConfig.Attribute):Connect(function()
		self:_refresh()
	end)
end

--[[ UIController's hook for "the page is opening", called before its scale tween and without this
	page having to own that tween. A full rebuild rather than a repaint, because the world can be a
	different one every time this screen is opened — header note 7. ]]
function Page.StartOpenThread(self)
	self:_rebuild()
	self:_refresh()
end

return Page
