--[[
	Market page  (client)
	---------------------
	The rotating shop: a shelf of car listings, each with a portrait, name, stock, price and rarity,
	a buy and a buy-all pill, over a "RESET IN" countdown in the title bar.

	FIVE THINGS TO KNOW.

	1. `Listing` IS THE TEMPLATE, NOT THE SHELF. It lives inside `Shelf` (a ScrollingFrame with a
	   UIListLayout), hidden, and is cloned once per stocked item. Its children are positioned
	   against its own box, so a clone needs no geometry at all — only text and a pill colour.

	   The two pills were moved INTO it in the place, because a shelf that scrolls under two buttons
	   pinned to the page is two buttons pointing at whatever row happens to be under them. They hang
	   just below the row's own box, exactly where the mockup drew them relative to the listing, and
	   the list layout's padding is sized to clear them and then leave a gap, so a pill pair groups
	   upward to the row it owns. `_layoutShelf` is where that pitch is computed.

	   A clone needs no geometry EXCEPT its height, which cannot stay in scale once it is inside a
	   ScrollingFrame. See the note on `RowScale` in `Page.new` — that one conversion is the whole
	   reason `_layoutShelf` exists.

	2. WHAT IS ON THE SHELF IS NOT DECIDED HERE. `Modules/MarketStock` holds the period clock, the
	   roll and the pricing, and its header carries the reasoning that used to be in this one: the
	   shelf is a pure function of `os.time()`, so nothing is saved, nothing is ticked, and every
	   client computes the same four cars. It was lifted out of this file when the kit's market page
	   arrived and two screens had to agree about the same shop.

	   The countdown is the other half of that: it reads `deadline - os.time()` every frame rather
	   than decrementing a counter, so an alt-tab, a lag spike or a hung frame cannot make it drift.

	3. PRICES COME OFF THE GARAGE ECONOMY, IN THE GARAGE'S OWN UNITS. There is no price table here
	   and there must not be one — `GarageConfig` header note 3 explains why, and
	   `MarketStock.BuySeconds` is the one number. A car costs that many seconds of its own income,
	   exactly as it SELLS for `SellSeconds` of it.

	4. RARITY PICKS THE PILL COLOUR. A tier is one car out of the live world (`WorldConfig`), and the
	   five RARITY BANDS it is graded against are `TrafficConfig.Bands`; `RARITY_PILL` maps those five
	   words onto five of `UIAssets.Pill`'s seven colours — by word, so a world with a different
	   number of cars in it changes nothing on this shelf. (`Modules/CarRarity` answers the same
	   question with a Color3 for screens that print the word rather than a pill.) Blue and Red
	   are deliberately left out of that map — Blue is the buy-all pill's own colour and would read
	   as a rarity if a listing ever wore it, and Red is kept free for a state (cannot afford, sold
	   out) rather than spent on a tier.

	5. BUYING IS A STUB AND SAYS SO. It logs the purchase it would have made and moves no money. See
	   `_requestPurchase` for exactly what a server would have to expose.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local MarketStock = require(ReplicatedStorage.shared.Modules.MarketStock)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local UIControllerTypes = require(script.Parent.Parent.UIControllerTypes)
local UIGeom = require(script.Parent.Parent.UIGeom)

local PAGE_NAME = "Market"

-- === The shop ===============================================================

--- Rarity band name -> a key of `UIAssets.Pill`. Header note 4 for why Blue and Red are not in here.
--- By NAME rather than by index, so the shelf keeps its colours whatever a world's rung count is.
local RARITY_PILL = {
	Beater = "Silver",
	Sedan = "Green",
	Coupe = "Sky",
	Sports = "Purple",
	Supercar = "Orange",
}

-- Shortest the driven scrollbar thumb is allowed to get, as a fraction of its track. Past this it
-- stops reading as a handle and starts reading as a dot.
local MIN_THUMB = 0.08

-- === Page ===================================================================

local Page = {}
Page.__index = Page

function Page.new(UIController: UIControllerTypes.UIController)
	local self = setmetatable({}, Page)
	self.UIController = UIController

	local mainUI = UIController.PlayerGui:WaitForChild("MainUI")
	self.PageUI = mainUI:WaitForChild("Pages"):WaitForChild(PAGE_NAME)

	self.Shelf = self.PageUI:WaitForChild("Shelf")
	self.ListingTemplate = self.Shelf:WaitForChild("Listing")
	self.Layout = self.Shelf:WaitForChild("UIListLayout")
	self.ScrollBar = self.PageUI:WaitForChild("ScrollBar")
	self.ResetTimer = self.PageUI:WaitForChild("ResetTimer")

	--[[ The authored row proportions, captured once before anything is converted to pixels.

		A ROW CANNOT STAY SCALE-SIZED ONCE IT IS IN THE SHELF, and this is not a style choice. A
		scale-sized child of a ScrollingFrame measures against the CANVAS, not against the visible
		window — and the canvas is sized off the rows. Leave the clones in scale and the two chase
		each other: a shelf whose window was 298px laid its rows out on a 938px pitch, three rows
		deep in a box that fits one. So the template keeps its authored scale (it is what the
		Explorer reads, and it is the number below), and every clone is converted to offset against
		the shelf's real window in `_layoutShelf`. ]]
	self.RowScale = self.ListingTemplate.Size.Y.Scale
	self.PadScale = self.Layout.Padding.Scale

	self.Rows = {}
	self.Stock = {}
	self.Period = nil
	self.Deadline = 0

	local close = self.PageUI:WaitForChild("Close")
	close.MouseButton1Click:Connect(function()
		self.UIController:closePage(PAGE_NAME)
	end)

	return self
end

function Page.initialize(self)
	self.ListingTemplate.Visible = false

	-- Rows are sized in pixels, so the shelf changing size re-lays them out. `AbsoluteSize` rather
	-- than `AbsoluteWindowSize`: same thing here (the built-in bar is off, so the window IS the
	-- frame) and it is the property every GuiObject is guaranteed to signal on.
	self.Shelf:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_layoutShelf()
	end)
	for _, signal in { "CanvasPosition", "CanvasSize" } do
		self.Shelf:GetPropertyChangedSignal(signal):Connect(function()
			self:_syncScrollBar()
		end)
	end

	-- Built at start rather than on first open, so the row art is in the tree in time for
	-- `UIController`'s preload pass and the first open is not a page assembling itself.
	self:_refreshStock()
end

--[[ The controller's own open/close hooks. The countdown only runs while the page is on screen —
	it is derived from a deadline, so there is nothing to keep warm while it is shut. ]]
function Page:StartOpenThread()
	self:_refreshStock()
	self:_layoutShelf()
	self:_tickTimer()

	if self._timerConnection then
		self._timerConnection:Disconnect()
	end
	self._timerConnection = RunService.Heartbeat:Connect(function()
		self:_tickTimer()
	end)
end

function Page:StartCloseThread()
	if self._timerConnection then
		self._timerConnection:Disconnect()
		self._timerConnection = nil
	end
end

--- Recolour a pill button to a rarity. `colour` is a key of `UIAssets.Pill`.
function Page.setPillColour(_self, button: ImageButton, colour: string)
	local set = UIAssets.Pill[colour]
	if not set then
		return
	end
	button.Image = UIAssets.url(set.Idle)
	button.HoverImage = UIAssets.url(set.Hover)
	button.PressedImage = UIAssets.url(set.Pressed)
end

-- === Shelf ==================================================================

--- Rebuild only when the clock has rolled into a new shop period.
function Page:_refreshStock()
	local period = MarketStock.periodNow()
	if period == self.Period then
		return
	end

	self.Period = period
	self.Deadline = MarketStock.deadlineOf(period)
	self.Stock = MarketStock.roll(period)
	self:_buildShelf()
end

function Page:_buildShelf()
	for _, row in self.Rows do
		row:Destroy()
	end
	table.clear(self.Rows)

	for index, entry in self.Stock do
		local row = self.ListingTemplate:Clone()
		row.Name = `Listing_{entry.Body}`
		row.LayoutOrder = index
		row.Visible = true

		row.ItemName.Text = GarageConfig.displayName(entry.Body)
		row.ItemPrice.Text = GarageConfig.formatCash(entry.Price)
		row.ItemRarity.Text = entry.Rarity

		--[[ The portrait stays the authored empty item square. There is no per-car thumbnail in
			`UIAssets`, and a `ViewportFrame` of the roster body used to be impossible here because
			`Workspace.CarSystem` is not streamed to clients — that is no longer true.
			`Modules/CarViewport` draws one from the traffic shells in `ReplicatedStorage`, which every
			client already has; see the dealership page for what it costs and how it is kept cheap.
			Nothing is stopping this row from having one. ]]

		self:setPillColour(row.BuyButton, RARITY_PILL[entry.Rarity] or "Green")
		row.BuyAllLabel.Text = "BUY\u{00A0}ALL"

		row.BuyButton.MouseButton1Click:Connect(function()
			self:_requestPurchase(entry, 1)
		end)
		row.BuyAllButton.MouseButton1Click:Connect(function()
			self:_requestPurchase(entry, entry.Stock)
		end)

		self:_paintStock(row, entry)

		row.Parent = self.Shelf
		table.insert(self.Rows, row)
	end

	self:_layoutShelf()
end

--[[ Put the rows on a pixel grid measured off the shelf's visible window, and size the canvas to
	match. Re-run whenever the shelf resizes.

	Everything here is offset rather than scale, for the reason spelled out on `RowScale` in
	`Page.new`: scale inside a ScrollingFrame is measured against the canvas, and the canvas is what
	this function computes. Pixels break that circle. The row's own CHILDREN stay in scale — they
	measure against the row, which is not a ScrollingFrame, so the authored listing art is untouched
	and still resolution-independent. ]]
function Page:_layoutShelf()
	local window = self.Shelf.AbsoluteWindowSize
	if window.Y <= 0 then
		-- Laid out before the page has a size. The AbsoluteSize signal brings us back.
		return
	end

	local rowHeight = math.round(self.RowScale * window.Y)
	local padding = math.round(self.PadScale * window.Y)

	self.Layout.Padding = UDim.new(0, padding)
	for _, row in self.Rows do
		row.Size = UDim2.fromOffset(window.X, rowHeight)
	end

	-- One trailing padding beyond the last row: its pills hang below its own box, and that padding
	-- is exactly the gap sized to clear them.
	self.Shelf.CanvasSize = UDim2.fromOffset(0, #self.Rows * (rowHeight + padding))

	self:_syncScrollBar()
end

--- Stock count, and the two pills' state that goes with it.
function Page:_paintStock(row, entry)
	local inStock = entry.Stock > 0

	row.ItemStock.Text = if inStock then `Stock:\u{00A0}{entry.Stock}` else "SOLD\u{00A0}OUT"
	row.BuyLabel.Text = if inStock then "BUY" else "SOLD\u{00A0}OUT"

	--[[ Sold out dims the pills rather than recolouring them: the rarity colour is the row's
		identity and Silver, the obvious "off" pill, is also Tier 1's. ]]
	for _, button in { row.BuyButton, row.BuyAllButton } do
		button.Active = inStock
		button.AutoButtonColor = inStock
		button.ImageTransparency = if inStock then 0 else 0.6
	end
	for _, label in { row.BuyLabel, row.BuyAllLabel } do
		label.TextTransparency = if inStock then 0 else 0.4
	end
end

-- === The scrollbar ==========================================================

--[[ The authored `ScrollBar` image driven from the shelf's real scroll position. The shelf's own
	bar is off (`ScrollBarThickness = 0`) so there is exactly one of them and it is this one.

	Its track is the shelf's rect, read live rather than copied, so moving the shelf in the Explorer
	moves the bar with it. ]]
function Page:_syncScrollBar()
	local window = self.Shelf.AbsoluteWindowSize.Y
	local canvas = self.Shelf.AbsoluteCanvasSize.Y

	if window <= 0 or canvas <= window + 1 then
		-- Nothing to scroll. A bar that cannot move is a bar that is lying.
		self.ScrollBar.Visible = false
		return
	end
	self.ScrollBar.Visible = true

	-- The shelf's top EDGE, not its Position: the shelf is centre-anchored like the rest of the
	-- kit. See UIGeom.
	local trackTop = UIGeom.top(self.Shelf)
	local trackHeight = self.Shelf.Size.Y.Scale

	local thumb = math.clamp(window / canvas, MIN_THUMB, 1)
	local alpha = math.clamp(self.Shelf.CanvasPosition.Y / (canvas - window), 0, 1)

	-- Size first: `place` corrects against the bar's current height, so a thumb resized afterwards
	-- would be positioned by the old one.
	self.ScrollBar.Size = UDim2.fromScale(self.ScrollBar.Size.X.Scale, trackHeight * thumb)
	UIGeom.place(self.ScrollBar, UIGeom.left(self.ScrollBar), trackTop + alpha * trackHeight * (1 - thumb))
end

-- === Countdown ==============================================================

function Page:_tickTimer()
	local remaining = self.Deadline - os.time()

	if remaining <= 0 then
		self:_refreshStock()
		remaining = self.Deadline - os.time()
	end

	local text = `RESET\u{00A0}IN:\u{00A0}{MarketStock.formatDuration(remaining)}`
	if text ~= self._timerText then
		self._timerText = text
		self.ResetTimer.Text = text
	end
end

-- === Buying =================================================================

--[[ STUB. NOTHING IS BOUGHT AND NO MONEY MOVES.

	There is no purchase remote and this page is not the place to invent one — a shop that spends
	the player's cash is a server decision, not a UI one.

	WHAT A `MarketService` WOULD HAVE TO EXPOSE for this to become real, in the order it matters:

	  • THE STOCK, AUTHORITATIVELY. The shelf above is derived from `os.time()` and is therefore
	    already the same on every client, but a client deriving its own prices is a client that can
	    claim any price it likes. The server should roll the identical period seed and publish the
	    result — the natural shape is an attribute or a small replicated table holding
	    `{ Period, Deadline, Items = { { Body, Tier, Stock } } }`, with this page reading it instead
	    of `MarketStock.roll`, and that staying as the client-side fallback that makes the page work
	    with the service switched off.
	  • ONE REMOTE, `Buy(body, quantity)`, returning why it failed. Everything it needs to check is
	    already server-side: the price is `GarageConfig.rateOf(tier) * MarketStock.BuySeconds`, the
	    cash is the profile's, the tier of a body is `GarageConfig.TierOfBody`, and the bay it would
	    park into is `GarageService`'s. The client must send the body and the count and NOTHING ELSE — no price,
	    no tier.
	  • A DECISION THIS PAGE DELIBERATELY DID NOT MAKE: what a bought car does. Parking it straight
	    into a bay makes the market a way to skip the run, which is the whole game; handing it to the
	    player to drive makes it a loadout choice. `GarageConfig.Banking` has opinions about a full
	    lot that a purchase would have to respect either way.
	  • STOCK DECREMENT IS SHARED STATE. `Stock` here is per-listing, not per-player, so two players
	    buying the last Supercar is a race only the server can settle. That is also why this stub
	    does not decrement anything locally — a number that goes down and then comes back is worse
	    than a number that never moved. ]]
function Page:_requestPurchase(entry, quantity: number)
	if entry.Stock <= 0 then
		return
	end

	local cash = Players.LocalPlayer:GetAttribute(GarageConfig.CashAttribute) or 0

	warn(string.format(
		"[Market] STUB purchase, nothing bought: %s (Tier %d, %s) x%d at %s each = %s. Player cash %s. "
			.. "No purchase remote exists yet - see Pages/Market.luau _requestPurchase.",
		entry.Body,
		entry.Tier,
		entry.Rarity,
		quantity,
		GarageConfig.formatCash(entry.Price),
		GarageConfig.formatCash(entry.Price * quantity),
		GarageConfig.formatCash(cash)
	))
end

return Page
