--[[
	Market page, V2  (client)
	-------------------------
	The rotating car shop on the Cartoony Kit: four listings, each with a portrait of the actual car,
	its name, its rarity, what it earns parked, a price and a buy-all price, under a countdown to the
	next rotation in the header.

	`BuildMarketV2` (Command Runner) cloned the kit's `ItemShopUI` into `MainUIV2.Pages.Market`, made
	the Robux button into the second cash button and hung the clock in the header. Its header carries
	every decision about the SHAPE of this screen; this file is the behaviour.

	=== THE THREE RULES THE SHIPPING PAGE HAS, UNCHANGED ======================================

	1. THE SHELF IS NOT DECIDED HERE. `Modules/MarketStock` rolls it from the wall clock, and both
	   market pages read that one module so they cannot disagree about what is for sale. It was this
	   page's arrival that lifted it out of `Pages/Market`.

	2. THE COUNTDOWN IS DERIVED FROM A DEADLINE, NEVER DECREMENTED. `deadline - os.time()`,
	   formatted. One subtraction survives a page left open for an hour, an alt-tab and a hung frame.

	3. BUYING IS A STUB AND SAYS SO. It logs the purchase it would have made and moves no money. The
	   shipping page's `_requestPurchase` holds the long version of what a `MarketService` would have
	   to expose, and that list is unchanged by the skin.

	=== WHAT THE KIT TOOK OVER ===============================================================

	`KitPage` owns the list, the row heights and the canvas, so `_layoutShelf`, `RowScale` and the
	hand-driven scrollbar are all gone: about half the shipping page. The pill palette is gone too.
	The kit draws the buy button in green and the same button refused in grey, so a price nobody can
	pay is the artist's own drawing rather than an image swap and a transparency.

	=== AND THE THREE THINGS THIS PAGE HAS THAT THE SHIPPING ONE DOES NOT =====================

	THE CAR IS ON THE CARD. The shipping row leaves the portrait as an empty square and its header
	says why: a client used to be unable to build one. That has not been true since `CarViewport`
	landed, and this row is 40% empty space with a car-sized hole in the middle of it, so it gets the
	real body in the real livery. The kit's own icon stays underneath as the fallback for a body with
	no published shell.

	WHAT A CAR EARNS IS PRINTED ON IT. The kit drew a description line and a car listing has one
	sentence worth saying: this is what it pays you per second once it is parked. That number is the
	entire argument for the price above it (`MarketStock.BuySeconds`), and the shipping page leaves
	the player to know it.

	A PRICE YOU CANNOT PAY IS DRAWN AS ONE. The shipping page dims a sold-out pill and says nothing
	about cash at all. Here the disabled face goes on whenever the wallet is short, so the row
	answers "can I have this" before it is pressed.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local MarketStock = require(ReplicatedStorage.shared.Modules.MarketStock)
local KitPage = require(script.Parent.Parent.KitPage)

local PAGE_NAME = "Market"

local Page = KitPage.extend(PAGE_NAME)

--- The kit's row templates, as `BuildMarketV2` left them.
local ROW_NAME = "Listing"
local NOTE_NAME = "Note"
local SPACER_NAME = "Padding"

--[[ Where the note and the spacer sit relative to the listings. The shelf takes 1..n, so both of
	these are past anything a rotation can hold. ]]
local NOTE_ORDER = 500
local SPACER_ORDER = 999

--- Which car a row is showing, read back off the row at press time. See `_wireSlot`.
local BODY_ATTRIBUTE = "Body"

--- The portrait this page lays over the kit's icon, and the icon it hides when it succeeds.
local CAR_VIEW = "Car"

--[[ The portrait's shape, and it is a constant rather than a measurement because the PANEL's shape
	is: `ItemShopUI` carries a `UIAspectRatioConstraint`, so the icon comes out square (measured:
	1.0000) at every resolution this game runs at. `CarViewport.set` wants the number rather than the
	frame for exactly this reason, and a measured one would be zero on the frame a row is built in. ]]
local SQUARE = 1

--[[ How much white goes into the top of a rarity's ramp.

	The kit writes "Rare" in a two-stop gradient, light at the top and saturated at the bottom, and
	our five rarities each have one flat colour (`CarRarity.Colours`). So the colour is the bottom
	stop and this is how far the top one is lifted towards white: the artist's shape, our hue. Flat
	would read as a label printed over the card rather than as part of it. ]]
local RARITY_LIFT = 0.35

--[[ How often the countdown is recomputed while the page is open. A quarter second rather than a
	whole one, for the reason `PagesV2/Quest` gives at length: a DERIVED clock ticked at 1s skips a
	number roughly every other minute, because its tick and the real second boundary drift apart. ]]
local TIMER_TICK = 0.25

--- The market's own copy. Everything a player reads on this page that is not a number is here.
local EMPTY_TEXT = "No cars on the shelf right now"
local SOLD_OUT_TEXT = "Sold out"
local TIMER_FORMAT = "Resets in %s"
local STOCK_FORMAT = "%d in stock. Earns %s/s in your garage."
local SOLD_OUT_FORMAT = "Sold out. Earns %s/s in your garage."
--- The same two lines without passive income; see `describe`.
local STOCK_VALUE_FORMAT = "%d in stock. Worth %s."
local SOLD_OUT_VALUE_FORMAT = "Sold out. Worth %s."
--- The multiplication sign, so a total reads as a quantity times a price rather than as a second
--- price. `\u{00D7}`, which Fredoka One draws; the Robux mark in the Shop page's prices is the
--- precedent for trusting the face with a character outside ASCII.
local ALL_FORMAT = "\u{00D7}%d %s"

local NBSP = "\u{00A0}"

--- Every label on this row is `TextScaled`, which breaks a line sooner than it picks a smaller font.
--- A string with no space in it cannot break, so it shrinks instead.
local function oneLine(text: string): string
	return (string.gsub(text, " ", NBSP))
end

--[[ A rarity's colour as the ramp the kit drew: lifted towards white at the top, the colour itself
	at the bottom. Two stops, which is what the artist's own gradient has. ]]
local function rarityRamp(colour: Color3): ColorSequence
	return ColorSequence.new(colour:Lerp(Color3.new(1, 1, 1), RARITY_LIFT), colour)
end

--[[ The backdrop a car is rendered against, as the row's own gradient halfway down: the portrait
	sits in the middle of the card, and this colour is only ever seen one pixel at a time round the
	car's outline (`CarViewport.new`). Read off the art rather than typed in, so a repainted card
	repaints the fringe with it.

	FIRST AND LAST KEYPOINT, because the kit's card ramps between exactly two. ]]
local function cardColour(row: GuiObject): Color3?
	local gradient = row:FindFirstChildOfClass("UIGradient")
	if not gradient then
		return nil
	end
	local stops = gradient.Color.Keypoints
	return stops[1].Value:Lerp(stops[#stops].Value, 0.5)
end

--- What a listing earns its owner, per second, once it is parked. The price above it is 360 of
--- these (`MarketStock.BuySeconds`), which is the whole pitch.
local function describe(entry: MarketStock.Listing): string
	--[[ Without passive income (2026-09-28) a parked car earns nothing a second, so "earns $X/s in
		your garage" would be a promise the garage no longer keeps. The line says what the car is WORTH
		instead — the model's market value, which is what tips and a buyer's offer are measured from. ]]
	if not GarageConfig.Income.Passive then
		local value = GarageConfig.formatCash(GarageConfig.valueOf(entry.Tier))
		if entry.Stock > 0 then
			return string.format(STOCK_VALUE_FORMAT, entry.Stock, value)
		end
		return string.format(SOLD_OUT_VALUE_FORMAT, value)
	end
	local rate = GarageConfig.formatRate(GarageConfig.rateOf(entry.Tier))
	if entry.Stock > 0 then
		return string.format(STOCK_FORMAT, entry.Stock, rate)
	end
	return string.format(SOLD_OUT_FORMAT, rate)
end

-- === Building ===============================================================

function Page.initialize(self)
	--- The kit's text caps are pixels for a 1080-tall screen; this keeps them in proportion above it.
	KitPage.scaleTextCaps(self.PageUI)

	--[[ The listing rows, in the order they are drawn. NOT `self._rows`, which is `KitPage`'s own
		list of everything it has stamped, the note and the spacer included. A page extending
		`KitPage` owns the names it invents and nothing else. ]]
	self._listings = {} :: { GuiObject }
	self.Stock = {} :: { MarketStock.Listing }
	self.Period = nil :: number?
	self.Deadline = 0

	self.TimerLabel = self.Header and self.Header:FindFirstChild("Timer")
	if not self.TimerLabel then
		warn("[Market] No `Header.Timer`; the shelf has no countdown. Run BuildMarketV2.")
	end

	self:_buildFixedRows()

	--[[ Filled before the page is ever opened, which is load-bearing rather than tidy: `UIController`
		preloads every image under the page immediately after this returns, and it can only preload
		rows that exist. ]]
	self:_refreshStock()
	--- The header is painted here too, so the clock in the Explorer is never the one a player sees.
	self:_updateTimer()

	--[[ The wallet decides which face each button wears, so it is repainted when the wallet moves.
		Only while the page is up: garage income moves this attribute several times a minute and a
		shut page repainting eight buttons for it is work nobody can see. `StartOpenThread` repaints
		on the way in, which is what makes that safe. ]]
	local player = Players.LocalPlayer
	if player then
		player:GetAttributeChangedSignal(GarageConfig.CashAttribute):Connect(function()
			if self.PageUI.Visible then
				self:_paintPrices()
			end
		end)
	end
end

--[[ The two rows that are not listings: the empty-shelf note and the kit's bottom spacer.

	BOTH ARE STAMPED ONCE, HERE, and neither is ever destroyed. The note is hidden rather than taken
	out, so the empty state is a `Visible` flip with nothing to rebuild, and `KitPage._updateCanvas`
	counts only visible rows so a hidden note costs the canvas nothing. ]]
function Page:_buildFixedRows()
	local note = self:newRow(NOTE_NAME)
	if note then
		note.LayoutOrder = NOTE_ORDER
		note.Visible = false
		if note:IsA("TextLabel") then
			note.Text = EMPTY_TEXT
		end
	end
	self.Note = note

	local spacer = self:newRow(SPACER_NAME)
	if spacer then
		spacer.LayoutOrder = SPACER_ORDER
	end
end

--[[ One listing, wired and parented. Painting is somebody else's job.

	The clone carries its tags with it, so both buy buttons are already `UIButton`s with hover, sound
	and a gamepad highlight, and nothing here wires any of that. ]]
function Page:_newRow(index: number): GuiObject?
	local row = self:newRow(ROW_NAME)
	if not row then
		return nil
	end
	row.LayoutOrder = index

	--[[ The portrait, laid over the kit's icon rather than replacing it. `CarViewport` is the one
		module that puts a car in a box, and it builds the frame itself, so there is no second copy
		of its camera or its lighting here or in the build command. ]]
	local icon = row:FindFirstChild("Icon")
	if icon and icon:IsA("GuiObject") then
		local view = CarViewport.new(row, CAR_VIEW, cardColour(row))
		view.AnchorPoint = icon.AnchorPoint
		view.Position = icon.Position
		view.Size = icon.Size
		view.ZIndex = icon.ZIndex
	end

	self:_wireSlot(row, "BuyOne", 1)
	self:_wireSlot(row, "BuyAll", 0)

	table.insert(self._listings, row)
	return row
end

--[[ Point one of the row's two buttons at a purchase.

	`quantity` of 0 means "however many are left", which is the buy-all pill: the count is read at
	press time along with the car, so a shelf that rotated under the cursor cannot sell the number
	of cars the last rotation had.

	THE CAR IS READ OFF THE ROW rather than closed over here, for the same reason: a row is reused
	across rotations, and a handler holding yesterday's listing is a button that sells a car the
	shelf no longer has. `Activated` and not `MouseButton1Click`, so a gamepad's A works. ]]
function Page:_wireSlot(row: GuiObject, slotName: string, quantity: number)
	local slot = row:FindFirstChild("Btns")
	slot = slot and slot:FindFirstChild(slotName)
	local button = slot and slot:FindFirstChild("BuyBtn")
	if not (button and button:IsA("GuiButton")) then
		warn(string.format("[Market] `%s.Btns.%s.BuyBtn` is missing. Run BuildMarketV2.", ROW_NAME, slotName))
		return
	end

	button.Activated:Connect(function()
		self:_requestPurchase(row:GetAttribute(BODY_ATTRIBUTE), quantity)
	end)
end

-- === Painting ===============================================================

--[[ What the player can spend. One line, but it is a SEAM: the edit-mode page probe has no
	LocalPlayer, so every price would be refused and the render would be a screen of grey buttons
	that is nothing like the screen. A probe hands this a number instead. ]]
function Page:_cash(): number
	local player = Players.LocalPlayer
	return (player and player:GetAttribute(GarageConfig.CashAttribute)) or 0
end


--[[ Bring the rows into line with the stock, then paint them.

	A ROTATION REPLACES THE WHOLE SHELF, so this rebuilds rather than diffing: every row is a
	different car fifteen minutes later, and there is nothing on this page that survives a rotation
	worth keeping. (`PagesV2/Quest` keys its rows by id for the opposite reason: one card leaves a
	board the rest of which is unchanged.) ]]
function Page:_renderRows()
	for _, row in self._listings do
		self:removeRow(row)
	end
	table.clear(self._listings)

	for index, entry in self.Stock do
		local row = self:_newRow(index)
		if row then
			self:_paintRow(row, entry)
		end
	end

	self:_updateEmptyState()
end

--- Everything on one row that comes off the listing rather than off the wallet.
function Page:_paintRow(row: GuiObject, entry: MarketStock.Listing)
	row:SetAttribute(BODY_ATTRIBUTE, entry.Body)

	local text = row:FindFirstChild("Text")
	local title = text and text:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		--- `displayName` is what every other screen in this game calls a car, and it is already
		--- one-line: it breaks `Sedan12` into two words and joins the pair with a hard space.
		title.Text = GarageConfig.displayName(entry.Body)
	end

	local rarity = text and text:FindFirstChild("Rarity")
	if rarity and rarity:IsA("TextLabel") then
		--[[ `CarRarity` rather than the listing's own `Rarity` field: they are the same word off the
			same ladder, and that module is the only thing in the game that also has the COLOUR. One
			lookup keeps the word and the colour from ever disagreeing. ]]
		local word, colour = CarRarity.labelOf(entry.Body)
		rarity.Text = oneLine(string.upper(word))
		local tint = rarity:FindFirstChild("Tint")
		if tint and tint:IsA("UIGradient") then
			tint.Color = rarityRamp(colour)
		end
	end

	local description = text and text:FindFirstChild("Description")
	if description and description:IsA("TextLabel") then
		--- The one wrapped label on the row: two lines of small type is what the artist drew this
		--- box for, so it keeps its spaces.
		description.Text = describe(entry)
	end

	local view = row:FindFirstChild(CAR_VIEW)
	local icon = row:FindFirstChild("Icon")
	if view and view:IsA("ViewportFrame") then
		--- The kit's icon is the fallback and shows only when there is no body to draw, because the
		--- portrait is transparent where the car is not and would otherwise be a car on a chest.
		local drawn = CarViewport.set(view, entry.Body, { aspect = SQUARE })
		if icon and icon:IsA("GuiObject") then
			icon.Visible = not drawn
		end
	end

	self:_paintPrices(row, entry)
end

--[[ The two buy buttons, on one rule: a button you can press is the artist's coloured pill, and a
	button you cannot is the same pill in grey with the same price still on it.

	Called on its own whenever the wallet moves, so it takes no decisions that are not about money
	or stock. With no arguments it repaints every row.

	BUY ALL IS ABSENT RATHER THAN GREY WHEN THERE IS ONE CAR LEFT. A pill offering to buy all one of
	them is a second button that does what the first one does, and the house rule for a control that
	leads nowhere is to draw nothing (`Pages/Market` on the gift button, `PagesV2/Shop` on the same).
	The row's own layout centres the survivor. ]]
function Page:_paintPrices(row: GuiObject?, entry: MarketStock.Listing?)
	if not row then
		for index, listing in self._listings do
			self:_paintPrices(listing, self.Stock[index])
		end
		return
	end
	if not entry then
		return
	end

	local cash = self:_cash()
	local inStock = entry.Stock > 0
	local total = entry.Price * entry.Stock

	self:_paintSlot(
		row,
		"BuyOne",
		true,
		if inStock then oneLine(GarageConfig.formatCash(entry.Price)) else oneLine(SOLD_OUT_TEXT),
		inStock and cash >= entry.Price
	)
	self:_paintSlot(
		row,
		"BuyAll",
		inStock and entry.Stock > 1,
		oneLine(string.format(ALL_FORMAT, entry.Stock, GarageConfig.formatCash(total))),
		cash >= total
	)
end

--- One slot: whether it is there at all, what it says, and which of its two faces is showing.
function Page:_paintSlot(row: GuiObject, slotName: string, shown: boolean, caption: string, enabled: boolean)
	local slot = row:FindFirstChild("Btns")
	slot = slot and slot:FindFirstChild(slotName)
	if not (slot and slot:IsA("GuiObject")) then
		return
	end

	slot.Visible = shown

	local button = slot:FindFirstChild("BuyBtn")
	local refused = slot:FindFirstChild("DisabledBtn")
	if button and button:IsA("GuiObject") then
		button.Visible = enabled
		local label = button:FindFirstChild("Title")
		if label and label:IsA("TextLabel") then
			label.Text = caption
		end
	end
	if refused and refused:IsA("GuiObject") then
		refused.Visible = not enabled
		local label = refused:FindFirstChild("Title")
		if label and label:IsA("TextLabel") then
			label.Text = caption
		end
	end
end

--[[ An empty shelf is a real state and says so. It only happens when the live world has no ladder
	at all, which is a config with nothing in it rather than a rotation that went badly, so there is
	one message rather than the quest board's two. ]]
function Page:_updateEmptyState()
	if self.Note then
		self.Note.Visible = #self.Stock == 0
		self:_updateCanvas()
	end
end

-- === The clock ==============================================================

function Page:_updateTimer()
	local remaining = self.Deadline - os.time()
	if remaining <= 0 then
		--- The rotation rolled while the page was open. `_refreshStock` rebuilds the shelf and moves
		--- the deadline; the clock below then draws the new one rather than a frame of zero.
		self:_refreshStock()
		remaining = math.max(0, self.Deadline - os.time())
	end

	local label = self.TimerLabel
	if label and label:IsA("TextLabel") then
		local text = oneLine(string.format(TIMER_FORMAT, MarketStock.formatDuration(remaining)))
		--- Compared before it is written: this runs four times a second and the string changes once.
		if text ~= self._timerText then
			self._timerText = text
			label.Text = text
		end
	end
end

-- === Data ===================================================================

--- Rebuild only when the wall clock has rolled into a new shop period. Everything else on this page
--- is a repaint of the same four cars.
function Page:_refreshStock()
	local period = MarketStock.periodNow()
	if period == self.Period then
		return
	end

	self.Period = period
	self.Deadline = MarketStock.deadlineOf(period)
	self.Stock = MarketStock.roll(period)
	self:_renderRows()
end

-- === Buying =================================================================

--[[ STUB. NOTHING IS BOUGHT AND NO MONEY MOVES, and `Pages/Market._requestPurchase` holds the long
	version of what a `MarketService` would have to expose for it to become real. That list is about
	the server and is not changed by this page existing.

	`quantity` of 0 is the buy-all pill: whatever is on the shelf right now. ]]
function Page:_requestPurchase(body: unknown, quantity: number)
	local entry: MarketStock.Listing? = nil
	for _, listing in self.Stock do
		if listing.Body == body then
			entry = listing
			break
		end
	end
	if not entry or entry.Stock <= 0 then
		return
	end

	local count = if quantity > 0 then math.min(quantity, entry.Stock) else entry.Stock
	local cash = self:_cash()

	warn(string.format(
		"[Market] STUB purchase, nothing bought: %s (Tier %d, %s) x%d at %s each = %s. Player cash %s. "
			.. "No purchase remote exists yet - see Pages/Market.luau _requestPurchase.",
		entry.Body,
		entry.Tier,
		entry.Rarity,
		count,
		GarageConfig.formatCash(entry.Price),
		GarageConfig.formatCash(entry.Price * count),
		GarageConfig.formatCash(cash)
	))
end

-- === Open and close =========================================================

--[[ The countdown only runs while the page is on screen: it is derived from a deadline, so there is
	nothing to keep warm while it is shut. ]]
function Page:StartOpenThread()
	if self.List then
		self.List.CanvasPosition = Vector2.zero
	end

	self:_refreshStock()
	--- The wallet moved while the page was shut, so the faces are repainted on the way in. This is
	--- what lets the cash listener skip a page nobody is looking at.
	self:_paintPrices()
	self:_updateTimer()

	if self._timerConnection then
		return
	end
	local accumulated = 0
	self._timerConnection = RunService.Heartbeat:Connect(function(delta)
		accumulated += delta
		if accumulated < TIMER_TICK then
			return
		end
		accumulated = 0
		self:_updateTimer()
	end)
end

function Page:StartCloseThread()
	if self._timerConnection then
		self._timerConnection:Disconnect()
		self._timerConnection = nil
	end
end

return Page
