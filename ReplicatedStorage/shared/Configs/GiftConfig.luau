--[[
	GiftConfig
	----------
	BUY SOMETHING FOR SOMEBODY ELSE. The catalogue of what can be gifted, which product pays for
	each one, and the rules about who may be sent what. `GiftService` is the plumbing; this is the
	list and the limits.

	=== NOTHING HERE IS A NEW THING TO OWN =====================================================

	Every entry MIRRORS something the game already sells, at the price it already sells for, and
	grants what it already grants — to a different player. `rbxsync.toml`'s GIFTS section carries the
	commercial argument (why the price has to match exactly, why Roblox forces a pass to be mirrored
	as a developer product, why `for_sale` on a gift tracks `for_sale` on the thing it gifts).

	SO THE TABLE BELOW IS DERIVED, NOT TYPED. The cash rungs come out of `CashConfig.Packs` and the
	passes out of `PassConfig.Passes`, which means a rung whose dollar amount is retuned or a pass
	whose seam is switched off moves this list with it and cannot leave a gift card advertising
	something that is no longer true. The only thing written by hand per entry is the `rbxsync` key,
	because that is the one fact that lives outside this codebase.

	=== FOUR THINGS TO KNOW ====================================================================

	1. A GIFT IS SELLABLE ONLY IF ITS TARGET IS. Two ids have to resolve — the gift product, and the
	   thing being gifted — and for a pass the seam behind it has to be written as well. A gift
	   product for an unwired pass would take Robux and hand somebody an entitlement that does
	   nothing, which is worse than an unwired pass being on sale: the person left holding it never
	   chose to buy it. `isSellable` is that gate and the shop calls it before drawing anything.

	2. THE RECIPIENT DOES NOT HAVE TO BE ONLINE. Delivery is a ProfileStore message against their
	   save key, so the only thing needed to send one is a user id. What the SCREEN offers is a
	   different question and a narrower one — see `PickFrom` — but nothing in the delivery path
	   cares whether the recipient is in this server, in another one, or asleep.

	3. YOU CANNOT GIFT YOURSELF. Not because it would break anything — it would work perfectly and
	   cost the same as buying it — but because every one of those is a player who meant to pick
	   somebody and mis-tapped, and finding out by watching your own Robux leave is a bad way to
	   learn it. `GiftService` refuses it with a sentence.

	4. THE PRICE IS WRITTEN TWICE, as everywhere else in this game that spends Robux. Roblox charges
	   what `rbxsync.toml` says; a card says what this file says, and this file takes it from the
	   thing being mirrored. If the two disagree the card lies until somebody buys one.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CashConfig = require(ReplicatedStorage.shared.Configs.CashConfig)
--- For `formatCash` and nothing else — a gift's `Title` is the amount written the way every other
--- dollar figure in the game is written. It requires nothing that requires this, so no cycle.
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local GameIds = require(ReplicatedStorage.shared.GameIds)
local PassConfig = require(ReplicatedStorage.shared.Configs.PassConfig)

--- The cash rung a gift mirrors. `CashConfig` indexes its packs by product id and by shortfall, not
--- by key, because nothing before this needed to ask that question.
local function packOf(key: string): CashConfig.Pack?
	for _, pack in CashConfig.Packs do
		if pack.Key == key then
			return pack
		end
	end
	return nil
end

local GiftConfig = {}

--[[ Master switch. Off = no gift mode on the shop, every request refused, and every gift product
	inert. Roblox will still sell the products — that is `for_sale` in `rbxsync.toml` — so this is
	the switch for taking the FEATURE off while leaving the twelve products alone, which is what a
	problem with delivery rather than with a particular gift would want. ]]
GiftConfig.Enabled = true

--[[ Where a started purchase records who it is for, on the BUYER's profile. See `Settings.TEMPLATE`
	for the long version and `GiftService` for why a receipt leaves us no other way to know. ]]
GiftConfig.PendingKey = "PendingGifts"

-- === Remotes ================================================================

--[[ client -> server (giftKey, recipientUserId): open the Robux prompt for this gift.

	THE CLIENT NAMES THE GIFT AND THE PERSON AND NOTHING ELSE. It does not name a price, an amount,
	a product id or what the recipient gets — every one of those is looked up server-side off the
	key, which is the same trust shape `ObstacleService.UsePickup` uses ("the client cannot name a
	pack, an amount or a target"). The worst a lying client can do is ask to buy a real gift for a
	real user id, which is exactly what an honest one does. ]]
GiftConfig.RequestName = "RequestGift"

--- server -> client (ok: boolean, message: string): the status line under the gift picker. Carries
--- no state — see `RadioConfig.ReplyName` on why a reply that told the client what it now owns
--- would be a second source of truth for something the first one cannot be wrong about.
GiftConfig.ReplyName = "GiftReply"

--[[ server -> client (fromName: string, title: string): somebody gave you something, just now,
	while you were standing there. Purely a toast — the grant has already happened and is already on
	the profile before this goes out, so a client that misses it loses nothing but the moment.

	A GIFT THAT ARRIVES WHILE THE PLAYER IS OFFLINE GETS NO TOAST, and deliberately so: it lands
	through the ProfileStore message on their next join, at which point a popup saying "you have been
	given 2x Car HP" competes with the WELCOME BACK screen and the tutorial. The pass simply works
	and the shop card says OWNED. ]]
GiftConfig.ReceivedName = "GiftReceived"

--[[ What that toast says. `%s` is the sender's display name, then what they were given.

	THE ONE PIECE OF PLAYER-FACING COPY IN THIS FILE, and it is here rather than in `ShopConfig`
	with the rest of it because `GiftController` is what prints it and `GiftController` does not
	require `ShopConfig` — it has no screen and no shop. A string that lives where only one module
	can reach it is a string that is nil at the one moment it is needed. ]]
GiftConfig.ReceivedFormat = "%s sent you %s!"

-- === Limits =================================================================

--[[ Seconds between one player's gift prompts. The same guard `CashConfig.PromptCooldown` is, for
	the same reason: a purchase window is the one piece of UI a player cannot dismiss quickly, and a
	button that can open them back to back is a button somebody will lean on. Shorter than the cash
	one (8s) because this window is opened deliberately from a screen rather than thrown up in front
	of somebody who pressed a price they could not meet. ]]
GiftConfig.PromptCooldown = 3

--- How long a prompt is assumed to still be open if `PromptProductPurchaseFinished` never arrives.
--- The backstop for a client that crashed with the window up; see `CashConfig.PromptTimeout`.
GiftConfig.PromptTimeout = 120

--[[ How long a recorded intent is honoured for, in seconds. Seven days.

	IT HAS TO OUTLIVE THE RECEIPT AND THE RECEIPT CAN BE VERY LATE. Roblox re-delivers a receipt it
	is not sure landed, and "not sure" can mean days on a server that died mid-purchase. So this is
	measured in days rather than minutes, and the failure it guards against is not a slow receipt —
	it is an intent left on a profile for a purchase that never happened, being spent by an unrelated
	receipt for the same product a month later. `GiftService` has the whole argument under WHERE THE
	RECIPIENT IS KEPT. ]]
GiftConfig.IntentLifetime = 7 * 24 * 60 * 60

--[[ Who the gift screen offers to pick from.

	"server" — everybody in this server except the buyer. That is the whole picker today.

	IT IS NOT A FRIENDS LIST, AND THAT IS A DELIVERY DECISION RATHER THAN A DESIGN ONE. Nothing in
	the delivery path needs the recipient to be here (note 2), so a friends picker is a perfectly
	good future addition and needs no change below this line — `GiftService` validates a user id, not
	a presence. What it would need is `GetFriendsAsync` paging on the client and a name resolve on
	the server for someone who is not in the server to be read off. Until that exists, offering only
	people you can see keeps the picker honest: every name on it is a player who is definitely real
	and definitely spelt right. ]]
GiftConfig.PickFrom = "server"

-- === The catalogue ==========================================================

export type Gift = {
	--- The `[products.<key>]` block in `rbxsync.toml`. The one hand-written fact per entry.
	Key: string,
	--- What is being given. Decides which grant the receipt runs and nothing else.
	Kind: "cash" | "pass",
	--- The `CashConfig.Packs` key or the `PassConfig.Passes` key this mirrors.
	Target: string,
	--[[ What the card and the confirmation line call it. Derived, never typed: a pass takes
		`PassConfig.Title` (the name Roblox itself prints in the prompt) and a cash rung takes its
		own formatted amount, so neither can drift from the thing being sold. ]]
	Title: string,
	--- Robux. Taken from the thing being mirrored, never typed — see note 4.
	Price: number,
	--- Dollars, for a cash gift. Zero for a pass.
	Cash: number,
	--- Resolved from `GameIds` at require time. 0 means not synced, which means not sellable.
	ProductId: number,
}

--[[ Cash first, then passes, and that order is what the gift picker draws.

	CASH LEADS BECAUSE IT IS THE SMALLER DECISION. The cheapest gift in the game is 29 Robux of cash
	and the cheapest pass is 149, so a list that opened with passes would show a first-time gifter a
	price five times bigger than the one they might have said yes to. Same argument `ShopConfig`
	makes for drawing its passes cheapest-first. ]]
GiftConfig.Gifts = {} :: { Gift }

for _, pack in CashConfig.Packs do
	table.insert(GiftConfig.Gifts, {
		Key = "Gift" .. pack.Key,
		Kind = "cash" :: "cash",
		Target = pack.Key,
		--- The pack's name: a gifted pack pays the RECIPIENT's figure (`CashConfig.cashFor`).
		Title = pack.Name,
		Price = pack.Price,
		--- Zero for a retired rung (Bank Heist), which is what `isSellable` reads as "no gift card".
		Cash = if pack.Retired then 0 else pack.Cash,
		ProductId = 0,
	})
end

for _, pass in PassConfig.Passes do
	table.insert(GiftConfig.Gifts, {
		Key = "Gift" .. pass.Key,
		Kind = "pass" :: "pass",
		Target = pass.Key,
		--[[ BOTH TAKEN OFF `PassConfig`, NOT TYPED. That file holds the pass's Roblox name and price
			as one copy for the whole codebase, so a gift card, a shop card and Roblox's own purchase
			prompt cannot end up calling the same pass three different things at three different
			prices. `rbxsync.toml` is still what Roblox charges — see note 4. ]]
		Title = pass.Title,
		Price = pass.Price,
		Cash = 0,
		ProductId = 0,
	})
end

for _, gift in GiftConfig.Gifts do
	gift.ProductId = GameIds["products." .. gift.Key] or 0
end

local byKey: { [string]: Gift } = {}
for _, gift in GiftConfig.Gifts do
	byKey[gift.Key] = gift
end

-- === Rules ==================================================================

--[[ The cash rung a cash gift mirrors, or nil for a pass gift.

	IT EXISTS SO `GiftService` CAN PAY THROUGH `CashService.grantCash` rather than writing the
	balance itself. That call fires `CashGranted`, which is what `AnalyticsService` books cash
	entering the game from — and `CashService`'s own header says every other way cash enters already
	fires one. A gift that wrote the balance directly would be the first that did not, and the
	dashboard's economy view would stop balancing by exactly the amount people gift each other. ]]
function GiftConfig.packOf(gift: Gift): CashConfig.Pack?
	return if gift.Kind == "cash" then packOf(gift.Target) else nil
end

--- The entry for a gift key, or nil. `nil` is ordinary: a client may name a key from a newer build.
function GiftConfig.get(key: unknown): Gift?
	return if type(key) == "string" then byKey[key] else nil
end

--[[ The entry a product id pays for, or nil. `DevProductsHandler` turns a receipt into a gift with
	this, and it is the only place a gift product id is ever interpreted. ]]
function GiftConfig.ofProduct(productId: unknown): Gift?
	if type(productId) ~= "number" or productId == 0 then
		return nil
	end
	for _, gift in GiftConfig.Gifts do
		if gift.ProductId == productId then
			return gift
		end
	end
	return nil
end

--[[ Can this gift be bought right now? See note 1: two ids and, for a pass, a written seam.

	THE TARGET CHECK IS THE IMPORTANT HALF. A gift product that synced while the pass it gifts is
	still unwired is the exact state `rbxsync.toml` warns about, and it is a state this repository
	can reach on any day somebody runs a sync — so it is checked at read time rather than assumed
	away by a comment. ]]
function GiftConfig.isSellable(gift: unknown): boolean
	if not GiftConfig.Enabled then
		return false
	end
	local entry = if type(gift) == "table" then gift :: Gift else GiftConfig.get(gift)
	if not entry or entry.ProductId == 0 then
		return false
	end
	if entry.Kind == "cash" then
		--[[ The RUNG being mirrored has to be sellable, not merely "some rung is". `CashConfig
			.sellable()` answers the second question, which is the right one for the top-up offer it
			was written for and the wrong one here: a gift is for one specific rung, and a rung whose
			own product never synced would draw a card that cannot pay out. ]]
		local pack = packOf(entry.Target)
		return pack ~= nil and pack.ProductId ~= 0 and entry.Cash > 0
	end
	return PassConfig.isSellable(entry.Target)
end

--[[ Every gift that can actually be bought, in catalogue order.

	NOTHING DRAWS THIS LIST AS A LIST ANY MORE, and it is kept because it is the honest answer to
	"what is on sale". Until 2026-09-04 the shop had one GIFT toggle whose visibility this decided;
	a gift is now a button on the card of the thing being gifted, so the question is asked one card
	at a time through `ShopConfig.giftFor` and never about the catalogue as a whole. ]]
function GiftConfig.sellableGifts(): { Gift }
	local out = {}
	for _, gift in GiftConfig.Gifts do
		if GiftConfig.isSellable(gift) then
			table.insert(out, gift)
		end
	end
	return out
end

return GiftConfig
