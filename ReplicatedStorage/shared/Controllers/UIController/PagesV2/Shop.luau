--[[
	Shop page, V2  (client)
	-----------------------
	The Robux shop on the Cartoony Kit: ONE scrolling list of sections, not three tabs.
	`Configs/ShopConfig` says what CAN be sold; the list itself says what is on sale, and where.

	=== THE CARDS ARE AUTHORED (2026-10-15) ==================================================

	The owner drew the whole list, every card a real product with its own artwork, and it is
	stashed at `ServerStorage.UIImports.ShopV2List` for `BuildShopV2` to drop into
	`Pages.Shop.Main`. Each card says what it sells:

	  ShopProductKey   the entry's `Key`: "Radio", "Cash3", "JDMBundle"
	  ShopCatalogKind  "GamePass", or "Product" for a bundle or a cash pack

	SO THIS PAGE NO LONGER STAMPS ANYTHING. It finds the cards, wires each one ONCE, and repaints
	them on every open. Move a card, reorder a row, give one new art in the Explorer, and nothing
	here changes. To put something new on sale, duplicate a card and point its `ShopProductKey` at
	the new entry: a sellable entry with no card is warned about at boot, which is the one way the
	list and the config can drift apart.

	THE PAGE WRITES ONLY WHAT MOVES AT RUNTIME: the price (what Roblox charges this player), the
	owned state, and a cash tile's line (a pack pays this player's own figure). Every title and
	blurb is the card's own text, so a copy change is an Explorer edit.

	AN UNSELLABLE CARD IS HIDDEN, then a row with nothing left in it, then a heading with no rows
	left under it. A row with one card hidden keeps the other, centred by the row's own layout.

	`KitPage` still owns the list's pixel sizing (`extend`'s `AuthoredList`): every row's height is
	its `PreviewHeightScale` of the list's, and the gap and padding are the list's own
	`ShopGapScale`, `ShopPaddingTopScale` and `ShopPaddingBottomScale`.

	=== WHAT IT STILL DOES, BECAUSE THESE ARE NOT ABOUT THE ART ===============================

	1. IT SELLS NOTHING BY ITSELF. Every purchase is `MarketplaceService:PromptPurchase` or
	   `PromptGamePassPurchase`, which is Roblox's modal and Roblox's money. There is no remote here
	   and there must not be one: the server learns about a sale from a RECEIPT (`DevProductsHandler`)
	   or from `UserOwnsGamePassAsync`, never from a client saying it bought something.

	   THE GIFT BUTTON IS THE EXCEPTION AND IT STILL SELLS NOTHING. A receipt cannot carry a
	   recipient, so the server has to write down who a gift is for before Roblox's window opens.
	   `GiftController` asks and `GiftService` decides; the money still only moves on a receipt.

	2. NOTHING UNWIRED IS DRAWN. `ShopConfig.isSellable` fails two ways: an id of 0 was never synced,
	   and an unwired pass exists on Roblox but nothing reads its ownership yet. A card that takes
	   Robux for nothing is the worst thing this page could ship. `ShopConfig.ShowUnwired` fills it
	   out for a look.

	3. OWNERSHIP IS ASKED ONCE PER OPEN. `UserOwnsGamePassAsync` is a web call, so it is made for the
	   visible passes when the page opens and cached while it is up. A player who buys one while the
	   page is open is caught by `PromptGamePassPurchaseFinished`.

	The codes box is not in the owner's list and is added under the last section (`_buildCodes`).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
--- The code box at the foot of the list (`_buildCodes`): its words, and the kit's button for it.
local CodesConfig = require(ReplicatedStorage.shared.Configs.CodesConfig)
local ArcadeKit = require(ReplicatedStorage.shared.Modules.ArcadeKit)
local Shard = require(ReplicatedStorage.Packages.Shard)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local GiftConfig = require(ReplicatedStorage.shared.Configs.GiftConfig)
local PassConfig = require(ReplicatedStorage.shared.Configs.PassConfig)
local ShopConfig = require(ReplicatedStorage.shared.Configs.ShopConfig)
--- What a cash pack pays THIS player (`CashConfig.cashFor`, the figure for their highest world).
local CashConfig = require(ReplicatedStorage.shared.Configs.CashConfig)
local GiftPickerV2 = require(script.Parent.Parent.Components.GiftPickerV2)
local KitPage = require(script.Parent.Parent.KitPage)

local Page = KitPage.extend("Shop", { AuthoredList = true })

--- What a card sells, by the entry's `Key`, and which catalogue that key is in. Header.
local KEY_ATTRIBUTE = "ShopProductKey"
local KIND_ATTRIBUTE = "ShopCatalogKind"
local GAME_PASS = "GamePass"
--- The id the card was authored against. Only checked, never sold: `GameIds` is the truth.
local CATALOG_ID_ATTRIBUTE = "ShopCatalogId"

--- The list's own spacing, as shares of its height. Header.
local GAP_ATTRIBUTE = "ShopGapScale"
local PAD_TOP_ATTRIBUTE = "ShopPaddingTopScale"
local PAD_BOTTOM_ATTRIBUTE = "ShopPaddingBottomScale"

--- A row that only spaces the list out. Every other row with no cards in it is a heading.
local SPACER_NAME = "Padding"

--- The heading the codes box borrows (`_buildCodes`), and how tall its row is next to that heading.
local CODES_HEADING = "CashTitle"
local CODES_ROW_HEIGHT = 2.2

--[[ The ROBUX GLYPH, which is the one thing on this page written the kit's way rather than ours.

	`ShopConfig.priceLabel` prints "R$149" and every pill in the shipping UI reads that way. The kit
	drew its prices as U+E002, Roblox's own Robux mark from the private use area, followed by the
	number, and it is in every `PurchaseBtn` in the pack. Written as an escape rather than pasted, so
	the file survives a tool that normalises its encoding.

	IF IT EVER RENDERS AS A BLANK BOX, this line is the whole fix: return `ShopConfig.priceLabel(n)`
	instead. Fredoka One is an uploaded face and the mark comes from Roblox's fallback, so this is a
	thing to look at rather than a thing to assume. ]]
local ROBUX = utf8.char(0xE002)
local function priceLabel(price: number): string
	return ROBUX .. " " .. tostring(price)
end

--[[ WHAT ROBLOX SAYS THIS PLAYER PAYS (2026-10-15, Aleafo: "make sure the prices are updated
	based on the price"). The config's `Price` is what the product was priced at when it was
	written, and Roblox can move it: a price changed on the dashboard, regional pricing, price
	optimisation. `GetProductInfo` on the CLIENT answers for this player, so the pill says what the
	purchase window will say. Asked once per id per session, and a failed or slow call leaves the
	config price showing: a pill that is briefly stale beats a blank one. ]]
local livePrices: { [string]: number | false } = {}
local function livePrice(id: number, infoType: Enum.InfoType): number?
	local key = infoType.Name .. tostring(id)
	if livePrices[key] == nil then
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(id, infoType)
		end)
		livePrices[key] = if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then info.PriceInRobux else false
	end
	local price = livePrices[key]
	return if price then price else nil
end

--- What the greyed pill says in place of a price on a pass this player already owns.
local OWNED_LABEL = "Owned"

--[[ What a cash pack says it grants. `GarageConfig.formatCash` with a hollow decimal taken off.

	THE DECIMAL IS RIGHT EVERYWHERE ELSE AND WRONG HERE. `formatCash` always prints one, because
	everywhere else the number is arbitrary and moving. A cash pack is neither: every rung is a round
	15, 150 or 1500 times a power of ten by construction, so the decimal is always a zero, and six
	tiles reading "$150.0K" beside "$1.5M" spend a character each saying nothing.

	ONLY A ZERO IS REMOVED, so a rung retuned to something that is not round keeps its digit rather
	than being silently rounded on the tile selling it. ]]
local function packAmount(cash: number): string
	return (string.gsub(GarageConfig.formatCash(cash), "%.0(%a)$", "%1"))
end

--- "10 min", "1.5 hr": how much of the player's earnings a pack is.
local function packSpan(minutes: number): string
	return if minutes >= 60 then string.format("%g hr", minutes / 60) else string.format("%d min", minutes)
end

--- The cards in one row: the row itself when it IS a card (a bundle), else its children that are.
local function cardsOf(row: GuiObject): { GuiObject }
	if row:GetAttribute(KEY_ATTRIBUTE) ~= nil then
		return { row }
	end
	local cards = {}
	for _, child in row:GetChildren() do
		if child:IsA("GuiObject") and child:GetAttribute(KEY_ATTRIBUTE) ~= nil then
			table.insert(cards, child)
		end
	end
	return cards
end

local function passOf(key: string): ShopConfig.Pass?
	for _, pass in ShopConfig.Passes do
		if pass.Key == key then
			return pass
		end
	end
	return nil
end

--- A cash pack by `Key`, off `CashConfig.Packs`.
local function packOf(key: string)
	for _, pack in ShopConfig.cashPacks() do
		if pack.Key == key then
			return pack
		end
	end
	return nil
end

--[[ One card's sale, resolved once from its attributes: what it costs, how to buy it, whether this
	player already owns it, and anything else it repaints on open. ]]
type Sale = {
	Key: string,
	Id: number,
	InfoType: Enum.InfoType,
	Price: number,
	Buy: () -> (),
	Owned: () -> boolean,
	Paint: ((card: GuiObject) -> ())?,
}

type Card = {
	Card: GuiObject,
	Sale: Sale,
	Purchase: GuiButton,
	Disabled: GuiObject?,
}

-- === Building ===============================================================

function Page.initialize(self)
	--- The kit's text caps are pixels for a 1080-tall screen; this keeps them in proportion above it.
	KitPage.scaleTextCaps(self.PageUI)

	self.Owned = {} :: { [string]: boolean }
	self.Cards = {} :: { Card }

	--[[ THE ONLY THING GIFTING REMEMBERS, and it lives for exactly one round trip: the gift whose
		button was pressed, held so a REFUSAL can put the picker back up over the right card. There is
		no "currently gifting to" and there is no mode. `ShopConfig.Gift` has the argument for why
		that state went away. ]]
	self.PendingGift = nil :: GiftConfig.Gift?
	self.Picker = GiftPickerV2.new(self.PageUI)

	if not self.List then
		warn("[Shop] Pages.Shop has no Main.ScrollingFrame; run BuildShopV2.")
		return
	end
	self:_readSpacing()
	self:_bindCards()
	self:_hideEmpty()
	self:_buildCodes()

	--[[ The one event that can move a card without asking Roblox again. It fires on this client for
		this client, so a `true` is a purchase that actually completed. ]]
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if player ~= Players.LocalPlayer or not purchased then
			return
		end
		for _, pass in ShopConfig.Passes do
			if pass.PassId == passId then
				self.Owned[pass.Key] = true
				self:_paint()
				break
			end
		end
	end)

	--- A once-only bundle bought while the page is up turns OWNED as the server records it.
	Players.LocalPlayer:GetAttributeChangedSignal(ShopConfig.BundleStand.BoughtAttribute):Connect(function()
		self:_paint()
	end)

	--[[ The server's status line, and a toast when somebody gives this player something. Both arrive
		through `Dispatcher` rather than off a remote held here. See `GiftController`, which has no
		screen and cannot know whether this page is built yet. ]]
	--- A code's answer (`CodesController`), shown under the box.
	Dispatcher:Subscribe(CodesConfig.Remotes.Result, function(result)
		self:_codeResult(result)
	end)
	Dispatcher:Subscribe(GiftConfig.ReplyName, function(ok: boolean, message: string)
		local gift = self.PendingGift
		self.PendingGift = nil

		--[[ REFUSALS GO TO THE PICKER'S OWN TITLE BAR, which is where the player last looked, and it
			reopens ON THE SAME GIFT so it is a retry rather than a dead end. The commonest refusal by
			far is a recipient who left the server between the pick and the request, and the answer to
			that is the same list with somebody else on it. ]]
		if not ok and gift then
			self:_pickFor(gift, string.upper(message))
		end
	end)

	Dispatcher:Subscribe(GiftConfig.ReceivedName, function(_fromName: string, _title: string)
		--[[ A gift landing on THIS player while they are looking at the shop. A card showing a price
			for a pass they have just been given has to stop doing that, and the cheapest correct way
			is to forget what we knew and ask again. ]]
		self.Owned = {}
		self:_refreshOwnership()
	end)

	--- Painted at start rather than on first open, so the first open is not a page filling itself in.
	self:_paint()
end

function Page:StartOpenThread()
	--- Repainted on open so the cash tiles say what a pack pays NOW (they scale with income).
	self:_paint()
	self:_refreshOwnership()
	if self._codeStatus then
		self._codeStatus.Text = ""
	end
end

function Page:StartCloseThread()
	--- A picker left up behind a closed page would be the first thing on screen the next time it
	--- opened, asking about a card nobody is looking at any more.
	self.Picker:close()
end

--[[ The list's gap and padding, off its own attributes. `KitPage` read them off the `UIListLayout`
	and `UIPadding`, which an authored list sets in offset for the Explorer's preview, so it found
	zeros. A list without the attributes keeps whatever `KitPage` made of it. ]]
function Page:_readSpacing()
	local list = self.List :: ScrollingFrame
	local function read(name: string): number?
		local value = list:GetAttribute(name)
		return if type(value) == "number" then value else nil
	end
	self._gapScale = read(GAP_ATTRIBUTE) or self._gapScale
	self._padScale.top = read(PAD_TOP_ATTRIBUTE) or self._padScale.top
	self._padScale.bottom = read(PAD_BOTTOM_ATTRIBUTE) or self._padScale.bottom
	self:_syncMetrics()
end

--[[ Find every card, resolve what it sells and wire it. Once: the cards live as long as the page.

	A card that cannot be sold is hidden here and never wired. Sellability does not change while the
	game runs (it is ids and config), so this is decided once and `_hideEmpty` follows it. ]]
function Page:_bindCards()
	local carded = {} :: { [string]: boolean }
	for _, row in self:rows() do
		for _, card in cardsOf(row) do
			local sale = self:_saleFor(card)
			if sale then
				carded[sale.Key] = true
				local wired = self:_wireCard(card, sale)
				if wired then
					table.insert(self.Cards, wired)
				else
					card.Visible = false
				end
			else
				card.Visible = false
			end
		end
	end
	self:_warnUncarded(carded)
end

--[[ What one card sells, or nil when it cannot be sold (and so is not shown).

	THE CATALOGUE IS ASKED BY KEY, never by the card's `ShopCatalogId`. The id on the card is what
	it was authored against, and a product re-synced under a new id would leave it stale; `GameIds`
	is what the purchase has to use. A mismatch is warned about so a stale card is noticed. ]]
function Page:_saleFor(card: GuiObject): Sale?
	local key = card:GetAttribute(KEY_ATTRIBUTE)
	if type(key) ~= "string" then
		return nil
	end
	local player = Players.LocalPlayer
	local sale: Sale? = nil

	if card:GetAttribute(KIND_ATTRIBUTE) == GAME_PASS then
		local pass = passOf(key)
		if not pass then
			warn(string.format("[Shop] Card `%s` sells the pass `%s`, which ShopConfig.Passes does not have.", card:GetFullName(), key))
			return nil
		end
		if not ShopConfig.isSellable(pass) then
			return nil
		end
		sale = {
			Key = key,
			Id = pass.PassId,
			InfoType = Enum.InfoType.GamePass,
			Price = pass.Price,
			Buy = function()
				MarketplaceService:PromptGamePassPurchase(player, pass.PassId)
			end,
			Owned = function()
				return self.Owned[key] == true
			end,
		}
	elseif ShopConfig.bundleOf(key) then
		local bundle = ShopConfig.bundleOf(key) :: ShopConfig.Bundle
		if not ShopConfig.isSellable(bundle) then
			return nil
		end
		sale = {
			Key = key,
			Id = bundle.ProductId,
			InfoType = Enum.InfoType.Product,
			Price = bundle.Price,
			--- A once-only bundle already bought draws OWNED and opens nothing (`Bundle.OncePerPlayer`).
			Buy = function()
				if not ShopConfig.boughtOnce(player, bundle) then
					MarketplaceService:PromptProductPurchase(player, bundle.ProductId)
				end
			end,
			Owned = function()
				return ShopConfig.boughtOnce(player, bundle)
			end,
		}
	else
		local pack = packOf(key)
		if not pack then
			warn(string.format("[Shop] Card `%s` sells `%s`, which is not a pass, a bundle or a cash pack.", card:GetFullName(), key))
			return nil
		end
		if pack.ProductId == 0 then
			return nil
		end
		sale = {
			Key = key,
			Id = pack.ProductId,
			InfoType = Enum.InfoType.Product,
			Price = pack.Price,
			Buy = function()
				MarketplaceService:PromptProductPurchase(player, pack.ProductId)
			end,
			--- A cash pack is never "owned".
			Owned = function()
				return false
			end,
			--[[ The amount is the player's own (`CashConfig.cashFor`), so the tile says the figure,
				since Roblox's purchase window will only show the pack's name. The name is the card's own
				title. With `Scaling` on it also says what the figure is ("10 min of your earnings");
				with the owner's fixed per-world table (2026-10-15) it is just the figure. ]]
			Paint = function(painted: GuiObject)
				local amount = packAmount(CashConfig.cashFor(pack, player))
				local line = if CashConfig.Scaling.Enabled
					then string.format("%s: %s of your earnings", amount, packSpan(pack.Minutes))
					else string.format("%s cash", amount)
				self:_setText(painted, "Description", line)
			end,
		}
	end

	local authoredId = card:GetAttribute(CATALOG_ID_ATTRIBUTE)
	if sale and type(authoredId) == "number" and authoredId ~= sale.Id then
		warn(string.format("[Shop] Card `%s` was drawn for id %d but `%s` is %d now; selling %d.", card.Name, authoredId, key, sale.Id, sale.Id))
	end
	return sale
end

--[[ A sellable entry with no card is not on sale anywhere, and nothing else would say so. Warned
	once at boot: it is the list falling behind the config, which only an Explorer edit fixes. ]]
function Page:_warnUncarded(carded: { [string]: boolean })
	local missing = {}
	for _, pass in ShopConfig.visiblePasses() do
		if not carded[pass.Key] then
			table.insert(missing, pass.Key)
		end
	end
	for _, bundle in ShopConfig.visibleBundles() do
		if not carded[bundle.Key] then
			table.insert(missing, bundle.Key)
		end
	end
	for _, pack in ShopConfig.cashPacks() do
		if pack.ProductId ~= 0 and not carded[pack.Key] and not ShopConfig.OffShelf[pack.Key] then
			table.insert(missing, pack.Key)
		end
	end
	if #missing > 0 then
		warn(string.format("[Shop] On sale but with no card in the shop list: %s. Duplicate a card and set its %s.", table.concat(missing, ", "), KEY_ATTRIBUTE))
	end
end

--[[ Hide every row left with no card showing, and every heading left with no row under it.

	A HEADING IS ANY ROW WITH NO CARDS THAT IS NOT THE SPACER, and its section is the card rows
	after it up to the next heading. Read off the list rather than named, so a new section the owner
	draws needs nothing here. ]]
function Page:_hideEmpty()
	local heading: GuiObject? = nil
	local headingFilled = false
	local function closeSection()
		if heading then
			heading.Visible = headingFilled
		end
	end

	for _, row in self:rows() do
		local cards = cardsOf(row)
		if #cards > 0 then
			local any = false
			for _, card in cards do
				any = any or card.Visible
			end
			row.Visible = any
			headingFilled = headingFilled or any
		elseif row.Name ~= SPACER_NAME then
			closeSection()
			heading = row
			headingFilled = false
		end
	end
	closeSection()
	self:_updateCanvas()
end

--[[ Repaint every shown card: its price, whether it is owned, and anything of its own. Cheap, and
	it is the whole of what an open has to do now that nothing is rebuilt. ]]
function Page:_paint()
	for _, shown in self.Cards do
		local sale = shown.Sale
		local owned = sale.Owned()

		--[[ THE OWNED STATE IS DRAWN, NOT BUILT. `DisabledBtn` is the same pill in grey, sitting under
			the live one in the artist's file with `Visible` off. ]]
		shown.Purchase.Visible = not owned
		if shown.Disabled then
			shown.Disabled.Visible = owned
		end

		self:_setText(shown.Purchase, "Title", priceLabel(sale.Price))
		--- The real price for THIS player replaces the config's as soon as Roblox answers (`livePrice`).
		--- Cached after the first answer, so a later open paints it in the same frame.
		if sale.Id ~= 0 then
			task.spawn(function()
				local live = livePrice(sale.Id, sale.InfoType)
				if live and shown.Purchase.Parent then
					self:_setText(shown.Purchase, "Title", priceLabel(live))
				end
			end)
		end

		if sale.Paint then
			sale.Paint(shown.Card)
		end
	end
end

--[[ THE CODE BOX (2026-10-15), the last thing in the list: a copy of the cash heading reading CODES,
	then a row of its own with a text box, the kit's green button and a line for the answer. Built in
	code because the kit has no text-entry row and the owner's list has no codes section; sized off
	the heading so it scales with the list. The press goes to `CodesController` (a page holds no
	remotes), and the answer comes back through `_codeResult`. `CodesConfig.Enabled = false`: no
	section at all. ]]
function Page:_buildCodes()
	if not CodesConfig.Enabled then
		return
	end
	local rows = self:rows()
	local source: GuiObject? = nil
	for _, row in rows do
		if row.Name == CODES_HEADING then
			source = row
			break
		end
	end
	if not source then
		warn(string.format("[Shop] No `%s` row to copy for the codes heading; the codes box is not drawn.", CODES_HEADING))
		return
	end
	local headingScale = self._rowScaleOf[source] or 0

	--- Above the trailing spacer, so the codes box is the last thing before the panel's rim.
	local at = if rows[#rows] and rows[#rows].Name == SPACER_NAME then #rows else #rows + 1

	local words = CodesConfig.Text
	local title = source:Clone()
	title.Name = "CodesTitle"
	title.Visible = true
	local label = title:FindFirstChild("Title")
	if label and label:IsA("TextLabel") then
		label.Text = words.Title
	end
	local icon = title:FindFirstChild("Icon")
	if icon and icon:IsA("GuiObject") then
		icon.Visible = false
	end
	self:adoptRow(title, headingScale, at)

	local row = Instance.new("Frame")
	row.Name = "Codes"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 0)

	local field = Instance.new("Frame")
	field.Position = UDim2.fromScale(0.05, 0.05)
	field.Size = UDim2.fromScale(0.6, 0.55)
	field.BackgroundColor3 = Color3.new(1, 1, 1)
	field.Parent = row
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.25, 0)
	round.Parent = field
	ArcadeKit.stroke(field, 3, true)
	local box = Instance.new("TextBox")
	box.BackgroundTransparency = 1
	box.Position = UDim2.fromScale(0.05, 0.12)
	box.Size = UDim2.fromScale(0.9, 0.76)
	box.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	box.TextScaled = true
	box.Text = ""
	box.PlaceholderText = words.Placeholder
	box.TextColor3 = ArcadeKit.Navy
	box.PlaceholderColor3 = Color3.fromRGB(140, 150, 170)
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Parent = field

	local button, caption = ArcadeKit.button(row, "Claim", 0.68, 0.05, 0.27, 0.55)
	caption.Text = words.Button

	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromScale(0.05, 0.66)
	status.Size = UDim2.fromScale(0.9, 0.3)
	status.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	status.TextScaled = true
	status.Text = ""
	status.TextColor3 = Color3.new(1, 1, 1)
	ArcadeKit.outline(status)
	status.Parent = row
	self._codeStatus = status

	local function send()
		local text = box.Text
		if CodesConfig.normalize(text) == nil then
			return
		end
		local controller = Shard.get("CodesController")
		if controller then
			controller:redeem(text)
		end
	end
	if button:IsA("GuiButton") then
		self:tagButton(button)
		button.Activated:Connect(send)
	end
	box.FocusLost:Connect(function(enter: boolean)
		if enter then
			send()
		end
	end)

	self:adoptRow(row, headingScale * CODES_ROW_HEIGHT, at + 1)
end

--- The server's answer to a code: green for paid, red for refused, on the line under the box.
function Page:_codeResult(result)
	local status = self._codeStatus
	if not (status and status.Parent and type(result) == "table") then
		return
	end
	status.Text = tostring(result.message)
	status.TextColor3 = if result.ok then Color3.fromRGB(110, 230, 60) else Color3.fromRGB(255, 90, 90)
end

-- === One card ===============================================================

function Page:_setText(card: GuiObject, name: string, text: string)
	local label = card:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

--[[ Wire one card's buttons, once: what pressing the price does, the greyed pill's word, and a gift
	button if what is on it can be given away. Answers nil for a card with no price button, which
	is then hidden rather than shown unbuyable.

	AN OWNED PASS STILL GETS A GIFT BUTTON, which is the one rule here that is not obvious. Owning a
	pass says nothing about whether the person you are buying it for owns it, so the greyed pill
	takes the price's place and the gift button stays beside it. The server does not check the
	recipient's ownership either, and `PassService.grant`'s header says why: the gifter cannot see
	what the recipient owns and should not be able to. ]]
function Page:_wireCard(card: GuiObject, sale: Sale): Card?
	local btns = card:FindFirstChild("Btns")
	local mainBtns = btns and btns:FindFirstChild("MainBtns")
	local purchase = mainBtns and mainBtns:FindFirstChild("PurchaseBtn")
	local disabled = mainBtns and mainBtns:FindFirstChild("DisabledBtn")
	if not (btns and mainBtns and purchase and purchase:IsA("GuiButton")) then
		warn(string.format("[Shop] Card for `%s` has no Btns.MainBtns.PurchaseBtn; it cannot be bought.", sale.Key))
		return nil
	end

	local greyed = if disabled and disabled:IsA("GuiObject") then disabled else nil
	if greyed then
		self:_setText(greyed, "Title", OWNED_LABEL)
	end

	--- `Activated` rather than `MouseButton1Click`: mouse, touch and a gamepad's A. The tag the
	--- button arrived with gives it the hover, the sound and `Selectable`; this is only the press.
	purchase.Activated:Connect(sale.Buy)

	local wired: Card = { Card = card, Sale = sale, Purchase = purchase, Disabled = greyed }

	local gift = btns:FindFirstChild("GiftBtn")
	if not (gift and gift:IsA("GuiButton")) then
		return wired
	end

	--[[ NOTHING IS DRAWN FOR A CARD THAT CANNOT BE GIFTED. `ShopConfig.giftFor` answers nil for an
		unwired pass, for a rung that never synced and for the bundles, which is the same call note 2
		makes about the cards themselves: draw nothing rather than a control that leads nowhere.

		AND THE PRICE PILL TAKES THE ROOM BACK. `Btns` lays its two children out left to right, so a
		destroyed gift button would otherwise leave the pill sitting at three quarters width against
		the left edge of a strip drawn for both. The kit's own answer to this is the `Slash` it drew
		across `GiftBtn`, a gift button visibly struck out. That is a real alternative and it is
		still in the art if the missing button ever reads as something failing to load. ]]
	local entry = ShopConfig.giftFor(sale.Key)
	if not entry then
		gift:Destroy()
		mainBtns.Size = UDim2.new(1, 0, mainBtns.Size.Y.Scale, mainBtns.Size.Y.Offset)
		return wired
	end

	gift.Activated:Connect(function()
		self:_pickFor(entry)
	end)
	return wired
end

-- === Gifting ================================================================

--[[ Ask who one gift is for, and then ask the server to open Roblox's window for it.

	`title` is passed only on the retry after a refusal, where the reason takes the title bar's
	place. An ordinary open names the thing being given, which is the whole of the picker's job.

	A CANCEL COSTS NOTHING AND LEAVES NOTHING BEHIND. The picker calls back exactly once, with a
	player or with nil for its close button, and nothing has been recorded by then, so there is no
	mode to get out of and no card to put back. ]]
function Page:_pickFor(gift: GiftConfig.Gift, title: string?)
	--- A cash gift is named, not priced: it pays the RECIPIENT's figure (`CashService.grantCash`).
	local name = gift.Title
	--- Upper, because every title bar in this kit is. The refusal path arrives already upper.
	local heading = title or string.upper(string.format(ShopConfig.Gift.PickerFormat, name))

	self.Picker:open(heading, ShopConfig.Gift.PickerEmpty, function(player: Player?)
		if not player then
			return
		end
		local controller = Shard.get("GiftController")
		if not controller then
			return
		end
		--[[ Recorded for the REPLY, which is the only thing left that can need to know which card
			this came from. `GiftController` re-checks the recipient and `GiftService` decides; this is
			a note to ourselves, not a claim. ]]
		self.PendingGift = gift
		controller:request(gift.Key, player)
	end)
end

-- === Ownership ==============================================================

--[[ Which of the visible passes does this player own? Asked once per open.

	THE SERVER'S ATTRIBUTE IS ASKED FIRST, AND THAT IS NOT AN OPTIMISATION. Since gifting landed,
	ownership is the UNION of two sources, bought on Roblox or given by another player, and
	`UserOwnsGamePassAsync` only knows about the first. A page that asked Roblox alone would show a
	BUY pill for a pass somebody had been given, and take their Robux for it. `PassService` computes
	the union server-side and mirrors it onto the Player under `PassConfig.ownedAttribute`, so that
	attribute is the answer and the web call below is only the fallback for a client whose join has
	not published yet.

	THE ATTRIBUTE IS A BROADCAST AND DECIDES NOTHING, which is why reading it here is safe: this is a
	screen deciding what to draw, and every actual ruling is made on the server against
	`PassService`.

	THE FALLBACK IS WRAPPED PER CALL: one failure costs one card its greyed pill rather than taking
	the page down. A pass whose answer never arrives stays un-owned, which shows a price to somebody
	who already bought it. That is the safe way round, because Roblox's own prompt then tells them they own
	it and takes no money. ]]
function Page:_refreshOwnership()
	local player = Players.LocalPlayer
	task.spawn(function()
		local changed = false
		for _, pass in ShopConfig.visiblePasses() do
			if self.Owned[pass.Key] == nil then
				local published = player:GetAttribute(PassConfig.ownedAttribute(pass.Key))
				if type(published) == "boolean" then
					self.Owned[pass.Key] = published
					changed = true
				else
					local ok, owns = pcall(function()
						return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.PassId)
					end)
					if ok then
						self.Owned[pass.Key] = owns
						changed = true
					end
				end
			end
		end
		if changed then
			self:_paint()
		end
	end)
end

return Page
