--[[
	Shop page, V2  (client)
	-----------------------
	The Robux shop on the Cartoony Kit: ONE scrolling list of sections, not three tabs.
	`BuildShopV2` (Command Runner) cloned the kit's `RobuxShopUI` into `MainUIV2.Pages.Shop` and its
	header carries the argument for the shape. `Configs/ShopConfig` still says what is in it.

	This is `Pages/Shop`'s opposite number and it is a fifth the size. What went, and why, is worth
	reading before adding anything back.

	=== WHAT THIS PAGE NO LONGER DOES ========================================================

	  • NO TABS. The kit draws `FeaturedTitle`, `CashTitle` and `GamepassTitle` as rows inside the
	    list, so a section is a heading plus the rows under it. The old page's tab strip (a selected
	    face, a dim, a size lift, a label colour, one hue per tab) was about a control this art does
	    not have, and none of it is here.
	  • NO EMPTY-SECTION COPY. `_paintEmpty` existed because a tab you pressed and found empty reads
	    as a page that failed to load. A section with nothing in it is simply never stamped, so the
	    bundle section is absent today rather than apologising for itself.
	  • NO LAYOUT ARITHMETIC. The old page read the artist's cards back out of the Explorer as a row
	    pattern, repeated that pattern to fit however many entries there were, stretched a part-filled
	    row, re-picked card art by width and shrank the stretched card's children back. All of it was
	    in service of a shelf whose sections were sized in offset against a canvas. Here `KitPage`
	    owns the list and a row is a row: `newRow("CashTripleRow")` and fill the cards in it.
	  • NO GIFT BUTTON GEOMETRY. The old page built one, measured the card's rendered aspect to draw
	    a square in scale, slid the price pill left to make room and clamped the pair inside the
	    card's rim. THE ARTIST DREW IT. Every card in this kit ships `Btns{ MainBtns{ PurchaseBtn,
	    DisabledBtn }, GiftBtn }`, already tagged `UIButton`, which is the layout the owner asked for
	    on 2026-09-04 arrived at from the other direction.
	  • NO PILL REPAINT. `_paintBuy` swapped the import's flat green button for the kit's gold pill so
	    that a price had three faces and a hover. `PurchaseBtn` is a kit button and always was.

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

	=== THE SECTION ORDER IS CASH-SECOND, AND THAT IS `DefaultTab`'S ARGUMENT REPHRASED =======

	The kit drew Featured, Gamepasses, Cash. `ShopConfig.DefaultTab` picks Currency and says why: a
	player who opens this page has usually just been told they cannot afford something, and the cash
	ladder is the answer to that question. That argument does not die with the tabs, it becomes an
	argument about scroll position. So Cash goes second, one flick from the top, behind a Featured
	section that is one card when it exists at all.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local GiftConfig = require(ReplicatedStorage.shared.Configs.GiftConfig)
local PassConfig = require(ReplicatedStorage.shared.Configs.PassConfig)
local ShopConfig = require(ReplicatedStorage.shared.Configs.ShopConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local GiftPickerV2 = require(script.Parent.Parent.Components.GiftPickerV2)
local KitPage = require(script.Parent.Parent.KitPage)

local Page = KitPage.extend("Shop")

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

--- What the greyed pill says in place of a price on a pass this player already owns.
local OWNED_LABEL = "Owned"

--[[ How many cash tiles go in the first row and how many in every row after it.

	THE ARTIST'S OWN ESCALATION, read off the two rows they drew: three tall tiles, then wide cards
	the shape of a gamepass card. Six rungs come out as 3, 2 and 1, and the one on its own is the
	BIGGEST pack, drawn at the same size as the two above it and centred by the row's own layout.

	That is the case the old page had a whole mechanism for (`StretchLastRow`, nearest-template-by-
	width, and shrinking the stretched card's children back), because there a lone tile was a SMALL
	tile holding the dearest pack. Here the leftover lands in the wide row, so there is nothing to
	stretch and nothing to put back. ]]
local CASH_FIRST_ROW = 3
local CASH_ROW = 2

--- Two gamepass cards per row, as drawn. An odd last pass centres itself.
local GAMEPASS_ROW = 2

local function url(id: number): string
	return "rbxassetid://" .. tostring(id)
end

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

--[[ The cards inside one stamped row.

	BY NAME, because a row's other children are its layout and its art: `StarterPack` is a row that IS
	a card and its children are two labels, a background and a button strip. Every multi-card row in
	this kit fills itself with copies of one named template, either `CashTemplate` or `GamepassTemplate`,
	so the name is both the filter and the thing that says a row holds cards at all. ]]
local function cardsOf(row: GuiObject, cardName: string): { GuiObject }
	local cards = {}
	for _, child in row:GetChildren() do
		if child:IsA("GuiObject") and child.Name == cardName then
			table.insert(cards, child)
		end
	end
	return cards
end

-- === Building ===============================================================

function Page.initialize(self)
	--- The kit's text caps are pixels for a 1080-tall screen; this keeps them in proportion above it.
	KitPage.scaleTextCaps(self.PageUI)

	self.Owned = {} :: { [string]: boolean }

	--[[ THE ONLY THING GIFTING REMEMBERS, and it lives for exactly one round trip: the gift whose
		button was pressed, held so a REFUSAL can put the picker back up over the right card. There is
		no "currently gifting to" and there is no mode. `ShopConfig.Gift` has the argument for why
		that state went away. ]]
	self.PendingGift = nil :: GiftConfig.Gift?
	self.Picker = GiftPickerV2.new(self.PageUI)

	--[[ The one event that can move a card without asking Roblox again. It fires on this client for
		this client, so a `true` is a purchase that actually completed. ]]
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if player ~= Players.LocalPlayer or not purchased then
			return
		end
		for _, pass in ShopConfig.Passes do
			if pass.PassId == passId then
				self.Owned[pass.Key] = true
				self:_build()
				break
			end
		end
	end)

	--[[ The server's status line, and a toast when somebody gives this player something. Both arrive
		through `Dispatcher` rather than off a remote held here. See `GiftController`, which has no
		screen and cannot know whether this page is built yet. ]]
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

	--- Built at start rather than on first open, so the art is in the tree in time for the
	--- controller's preload pass and the first open is not a page assembling itself.
	self:_build()
end

function Page:StartOpenThread()
	self:_refreshOwnership()
end

function Page:StartCloseThread()
	--- A picker left up behind a closed page would be the first thing on screen the next time it
	--- opened, asking about a card nobody is looking at any more.
	self.Picker:close()
end

--[[ Stamp the whole list, top to bottom. Cheap enough to redo whenever anything changes: it is
	thirteen rows at most, and the alternative is three build functions that each have to know where
	their own section starts. ]]
function Page:_build()
	self:clearRows()

	self:_buildFeatured()
	self:_buildCash()
	self:_buildGamepasses()

	--- The kit's own bottom spacer, so the last card does not sit against the panel's rim.
	self:newRow("Padding")
end

--[[ Lay `count` entries into rows of a named template and hand each card back to `paint`.

	The row template arrives holding the cards the artist drew in it, so a part-filled row DESTROYS
	the ones it does not need and the row's own `UIListLayout` centres what is left. `LayoutOrder` is
	written on every card because they all share a name, and equal orders leave the draw order to
	whatever the Explorer happens to hold, which on a cash ladder is the difference between rungs
	that escalate and rungs that do not. ]]
function Page:_fill(templateName: string, cardName: string, count: number, perRow: number, paint: (GuiObject, number) -> ())
	local index = 0
	while index < count do
		local row = self:newRow(templateName)
		if not row then
			return
		end

		local cards = cardsOf(row, cardName)
		local take = math.min(perRow, #cards, count - index)

		--- A row template holding no cards would spin here forever rather than failing loudly.
		if take == 0 then
			warn(string.format("[Shop] Row `%s` holds no `%s`; %d entries have nowhere to go.", templateName, cardName, count - index))
			row:Destroy()
			return
		end

		for slot = 1, #cards do
			if slot <= take then
				index += 1
				cards[slot].LayoutOrder = slot
				paint(cards[slot], index)
			else
				cards[slot]:Destroy()
			end
		end
	end
end

--[[ The featured section: the bundles, on the kit's own `StarterPack` row.

	ONE ROW PER BUNDLE AND NO HEADING WHEN THERE ARE NONE. There is one bundle today and its product
	is unsynced, so this section does not exist on screen, which is the whole of what `_paintEmpty`
	used to have to say in a sentence. ]]
function Page:_buildFeatured()
	local bundles = ShopConfig.visibleBundles()
	if #bundles == 0 then
		return
	end

	self:newRow("FeaturedTitle")
	for _, bundle in bundles do
		--- The one row in this list that IS a card: `StarterPack` holds the labels directly, where
		--- the cash and gamepass rows hold copies of a card template. So it is stamped, not filled.
		local card = self:newRow("StarterPack")
		if not card then
			return
		end

		self:_setText(card, "Title", bundle.Title)
		--[[ SUBTITLE AND BLURB ON ONE LINE, because the kit's row has one body line where the old
			card had two. The subtitle says what is in the box and the blurb says why it is worth it;
			joined, they are still one sentence and a fragment, which is what that line is drawn for.

			The SAVING is on the end rather than in a badge of its own. `ShopConfig.savingLabel`
			computes it from the two prices so it cannot drift, and it is the strongest thing the card
			has to say, so it goes last where a reader stops. ]]
		local saving = ShopConfig.savingLabel(bundle)
		local body = bundle.Subtitle .. ". " .. bundle.Blurb
		if saving ~= "" then
			body = body .. "  " .. saving .. "."
		end
		self:_setText(card, "Description", body)
		self:_setIcon(card, bundle.IconId)

		--[[ There is no `GiftStarterBundle` product, so `giftFor` answers nil and this row loses its
			gift button. Deliberate rather than missed: the bundle is a NEW ACCOUNT's pack, and the
			player most likely to be given one is the player least likely to be standing in the server
			to be picked. ]]
		self:_wireCard(card, bundle.Key, bundle.Price, false, function()
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, bundle.ProductId)
		end)
	end
end

--[[ The cash ladder. Three tall tiles, then wide cards two at a time. See `CASH_FIRST_ROW`.

	THE RUNG IS CARRIED, NOT THE POSITION IN THIS LIST. A rung with no product id was never synced,
	so it is filtered out before anything is stamped. The rungs after it keep their own glyphs
	rather than sliding down into them: rung 5's silver case belongs to $150M whether or not $15M is
	on sale. ]]
function Page:_buildCash()
	local packs = {}
	for rung, pack in ShopConfig.cashPacks() do
		if pack.ProductId ~= 0 then
			table.insert(packs, { Pack = pack, Rung = rung })
		end
	end
	if #packs == 0 then
		return
	end

	self:newRow("CashTitle")

	local tiers = UIAssets.CashTiers

	local function paint(card: GuiObject, order: number)
		local pack = packs[order].Pack

		--[[ The glyph is the only part of a cash tile that says WHICH pack it is at a glance. See
			`UIAssets.CashTiers`: one drawing per rung, escalating note to throne, because all six of
			these products wear the same icon on Roblox and the product art can therefore say nothing.
			Clamped rather than left blank past the end of the list, so a seventh rung wears the
			throne instead of an empty square.

			THIS IS THE ONE PLACE V2 KEEPS ART FROM THE OLD KIT. The kit ships a single cash drawing
			and repeats it down the whole ladder, which is exactly the problem these six were drawn to
			fix. Open question 7's answer covers it: reuse our own art where a cell needs a specific
			picture. ]]
		local tier = tiers[math.min(packs[order].Rung, #tiers)]
		if tier then
			self:_setIcon(card, tier)
		end

		--- `formatCash` is the garage's own formatter, so a price on this tile and a price on a car
		--- read the same way. `packAmount` only takes off the trailing zero it leaves behind, and
		--- BOTH lines go through it: the headline and the sentence under it are the same number.
		local amount = packAmount(pack.Cash)
		self:_setText(card, "Title", amount)
		self:_setText(card, "Description", string.format("Receive %s instantly.", amount))

		--- A cash pack is never "owned", so the third argument is always false here.
		self:_wireCard(card, pack.Key, pack.Price, false, function()
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, pack.ProductId)
		end)
	end

	local first = math.min(CASH_FIRST_ROW, #packs)
	self:_fill("CashTripleRow", "CashTemplate", first, CASH_FIRST_ROW, paint)

	if #packs > first then
		--- The rungs above the third, on the wide card. `order` restarts at 1 inside `_fill`, so it
		--- is offset back onto the ladder here rather than by passing an index around.
		self:_fill("CashRow", "CashTemplate", #packs - first, CASH_ROW, function(card, order)
			paint(card, order + first)
		end)
	end
end

function Page:_buildGamepasses()
	local passes = ShopConfig.visiblePasses()
	if #passes == 0 then
		return
	end

	self:newRow("GamepassTitle")
	self:_fill("GamepassRow", "GamepassTemplate", #passes, GAMEPASS_ROW, function(card, order)
		local pass = passes[order]

		self:_setText(card, "Title", pass.Title)
		self:_setText(card, "Description", pass.Blurb)
		self:_setIcon(card, pass.IconId or 0)

		self:_wireCard(card, pass.Key, pass.Price, self.Owned[pass.Key] == true, function()
			if pass.PassId == 0 then
				return -- never synced; `isSellable` should already have kept this card off the shelf
			end
			MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, pass.PassId)
		end)
	end)
end

-- === One card ===============================================================

function Page:_setText(card: GuiObject, name: string, text: string)
	local label = card:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

--- Every card's picture is `BG.Sunray.Icon`; `BuildShopV2` made that one name out of the kit's two.
function Page:_setIcon(card: GuiObject, id: number)
	local bg = card:FindFirstChild("BG")
	local sunray = bg and bg:FindFirstChild("Sunray")
	local icon = sunray and sunray:FindFirstChild("Icon")
	if icon and icon:IsA("ImageLabel") then
		icon.Image = url(id)
	end
end

--[[ Wire one card's buttons: the price, what pressing it does, whether it is already owned, and a
	gift button if what is on it can be given away.

	ONE FUNCTION FOR ALL THREE SECTIONS, because "what does the price say, what does pressing it do,
	and is this one already owned" is the same three lines on a cash tile, a pass card and a bundle.

	AN OWNED PASS STILL GETS A GIFT BUTTON, which is the one rule here that is not obvious. Owning a
	pass says nothing about whether the person you are buying it for owns it, so the greyed pill
	takes the price's place and the gift button stays beside it. The server does not check the
	recipient's ownership either, and `PassService.grant`'s header says why: the gifter cannot see
	what the recipient owns and should not be able to. ]]
function Page:_wireCard(card: GuiObject, key: string, price: number, owned: boolean, buy: () -> ())
	local btns = card:FindFirstChild("Btns")
	local mainBtns = btns and btns:FindFirstChild("MainBtns")
	local purchase = mainBtns and mainBtns:FindFirstChild("PurchaseBtn")
	local disabled = mainBtns and mainBtns:FindFirstChild("DisabledBtn")
	if not (btns and mainBtns and purchase and purchase:IsA("GuiButton")) then
		warn(string.format("[Shop] Card for `%s` has no Btns.MainBtns.PurchaseBtn; it cannot be bought.", key))
		return
	end

	--[[ THE OWNED STATE IS DRAWN, NOT BUILT. `DisabledBtn` is the same pill in grey, sitting under
		the live one in the artist's file with `Visible` off. The old page had to make an OWNED badge
		on the pill's own rect and keep the two in step. ]]
	purchase.Visible = not owned
	self:_setText(purchase, "Title", priceLabel(price))
	if disabled and disabled:IsA("GuiObject") then
		disabled.Visible = owned
		self:_setText(disabled, "Title", OWNED_LABEL)
	end

	--- `Activated` rather than `MouseButton1Click`: mouse, touch and a gamepad's A. The tag the
	--- button arrived with gives it the hover, the sound and `Selectable`; this is only the press.
	purchase.Activated:Connect(buy)

	local gift = btns:FindFirstChild("GiftBtn")
	if not (gift and gift:IsA("GuiButton")) then
		return
	end

	--[[ NOTHING IS DRAWN FOR A CARD THAT CANNOT BE GIFTED. `ShopConfig.giftFor` answers nil for an
		unwired pass, for a rung that never synced and for the bundles, which is the same call note 2
		makes about the cards themselves: draw nothing rather than a control that leads nowhere.

		AND THE PRICE PILL TAKES THE ROOM BACK. `Btns` lays its two children out left to right, so a
		destroyed gift button would otherwise leave the pill sitting at three quarters width against
		the left edge of a strip drawn for both. The kit's own answer to this is the `Slash` it drew
		across `GiftBtn`, a gift button visibly struck out. That is a real alternative and it is
		still in the art if the missing button ever reads as something failing to load. ]]
	local entry = ShopConfig.giftFor(key)
	if not entry then
		gift:Destroy()
		mainBtns.Size = UDim2.new(1, 0, mainBtns.Size.Y.Scale, mainBtns.Size.Y.Offset)
		return
	end

	gift.Activated:Connect(function()
		self:_pickFor(entry)
	end)
end

-- === Gifting ================================================================

--[[ Ask who one gift is for, and then ask the server to open Roblox's window for it.

	`title` is passed only on the retry after a refusal, where the reason takes the title bar's
	place. An ordinary open names the thing being given, which is the whole of the picker's job.

	A CANCEL COSTS NOTHING AND LEAVES NOTHING BEHIND. The picker calls back exactly once, with a
	player or with nil for its close button, and nothing has been recorded by then, so there is no
	mode to get out of and no card to put back. ]]
function Page:_pickFor(gift: GiftConfig.Gift, title: string?)
	--- A cash rung is named the way its own tile names it. See `packAmount`.
	local name = if gift.Kind == "cash" then packAmount(gift.Cash) else gift.Title
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
			self:_build()
		end
	end)
end

return Page
