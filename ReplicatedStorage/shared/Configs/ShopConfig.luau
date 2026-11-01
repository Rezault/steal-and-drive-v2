--[[
	ShopConfig
	----------
	THE ROBUX SHOP: the three tabs of the SHOP page (`Pages/Shop`), which is the only screen in this
	game that spends Robux on purpose rather than because a player pressed a price they could not
	meet. Every other Robux prompt in the game is an interruption offered at a moment (the wreck
	screen, the welcome back panel, a shortfall on a car). This is the one a player opens.

	The mockup is `car ui (3).psd`, `Old/Shop`, and it draws three tabs: BUNDLES, CURRENCY,
	GAMEPASSES. This file is what fills them.

	ON THE NEW UI (2026-10-15) THE CARD LIST OWNS ORDER AND COPY, NOT THIS FILE. The owner drew every
	card (`ServerStorage.UIImports.ShopV2List`), each naming the `Key` it sells, and `PagesV2/Shop`
	paints them in place. This file still decides what CAN be sold (ids, `Wired`, `isSellable`,
	`giftFor`, `boughtOnce`) and what a press does; a sellable entry with no card is warned about.

	=== FIVE THINGS TO KNOW ====================================================================

	1. THIS FILE OWNS COPY AND ORDER. IT DOES NOT OWN PRICES OR IDS.

	   `rbxsync.toml` is what Roblox actually charges and `GameIds.luau` is what it charges against,
	   and both are generated or hand written somewhere else. A price written here is only ever the
	   number the CARD SAYS, and the two have to agree. That is the same contract
	   `OfflineConfig.Boost.Price` and `ReviveConfig.Tiers[n].Price` carry, and it fails the same
	   way: silently, with the UI lying about the price until somebody buys one.

	   The CURRENCY tab does not even do that much. `CashConfig.Packs` already holds the six rungs,
	   their dollar amounts, their prices and their resolved product ids, so this file points at that
	   table rather than copying it. There is no second cash ladder here and there must not be one.

	2. AN ID OF 0 MEANS "CANNOT BE SOLD", NEVER "FREE". `GameIds` resolves an unsynced key to 0, so
	   every reader has to treat 0 as a dead card. `ShopConfig.isSellable` is that check and the page
	   calls it before drawing a price on anything.

	3. A PASS IS NOT SHOWN UNTIL ITS SEAM IS WIRED, and this is the load bearing rule in the file.

	   `Wired` IS NO LONGER TYPED HERE. It is read off `PassConfig.isSellable`, which is the same
	   answer `PassService` gives every seam in the game — so the shop cannot offer a pass the
	   server would refuse to honour, and the two cannot be edited apart. That is one fewer place
	   than this note used to describe.

	   SO THERE ARE TWO PLACES A PASS'S READINESS IS RECORDED and they have to agree: `for_sale` in
	   `rbxsync.toml` (whether Roblox will take the money) and `Live` in `PassConfig` (whether owning
	   it does anything). Turning a pass on means: write the seam, playtest it, flip `Live`, flip
	   `for_sale`, sync — in that order, and the sync is the go-live.

	   Three of the six are live today: Radio, Auto Collect and 2x Car HP. Nitro, 2x Cash and VIP
	   have ids and icon art and no behaviour, which is deliberate and is why they are not drawn.

	   `ShowUnwired` exists to look at the finished layout during development. It must ship false.

	4. THE GAMEPASS TAB SCROLLS AND THE MOCKUP'S FOUR SLOTS ARE NOT A LIMIT. The artist drew a 2x2
	   grid and there are five passes, which is why `Old/Shop` also carries a scroll bar. The grid is
	   a pitch, not a capacity. See `Pages/Shop` for how the rows are laid out, and note that it has
	   the same ScrollingFrame trap the Market page's header describes at length: a scale sized child
	   of a ScrollingFrame measures against the CANVAS, and the canvas is computed from the children.

	5. OWNERSHIP IS NOT A PROFILE KEY. `RadioConfig`'s header sets this out and it applies to all
	   five: a pass is owned on Roblox, `UserOwnsGamePassAsync` is the only copy that counts, there
	   is no receipt to process, and nothing about a pass belongs in `DevProductsHandler`. The
	   BUNDLE is the opposite and is a developer product for exactly that reason. Its own block
	   below says why.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CashConfig = require(ReplicatedStorage.shared.Configs.CashConfig)
local GameIds = require(ReplicatedStorage.shared.GameIds)
local GiftConfig = require(ReplicatedStorage.shared.Configs.GiftConfig)
local PassConfig = require(ReplicatedStorage.shared.Configs.PassConfig)

local ShopConfig = {}

--[[ Show passes and bundles whose seam is not written yet, as live cards with live prices.

	A DEVELOPMENT SWITCH, AND IT MUST SHIP FALSE. With it true the shop draws all five passes so the
	grid, the scroll pitch and the copy can be read at full length. With it false the shop draws only
	what actually works, which today is one pass. Note that flipping this does NOT make anything
	purchasable: Roblox refuses a prompt for a pass at `for_sale = false`, so the worst this can do
	is show a card whose BUY pill fails. That is still bad in front of a player. ]]
ShopConfig.ShowUnwired = false

-- The tab order, left to right. Names are what the section heading prints.
ShopConfig.Tabs = { "Bundles", "Currency", "Gamepasses" }

--[[ Which tab opens first.

	CURRENCY, NOT BUNDLES, even though bundles is drawn first and is the better deal. A player who
	opens the shop has usually just been told they cannot afford something, and the cash ladder is
	the answer to that question. The bundle is the answer to a question nobody asked yet, which is
	why it is one tab away rather than in the player's face. ]]
ShopConfig.DefaultTab = "Currency"

-- === Game passes ============================================================

export type Pass = {
	--- The `PassConfig` key, and the only name any other file needs. Everything else is looked up.
	Key: string,
	--- The card's body copy. Two short lines at the size the mockup draws. THE ONLY COPY THIS FILE
	--- STILL OWNS for a pass — title, price and readiness all come from `PassConfig`.
	Blurb: string,
	--- Filled in below from `PassConfig.Title`: the pass's name on Roblox, so the card and the
	--- purchase prompt cannot call it two different things.
	Title: string,
	--- Filled in below from `PassConfig.Price`. `rbxsync.toml` is still what Roblox charges.
	Price: number,
	--- Filled in below from `PassConfig.isSellable`. Header note 3.
	Wired: boolean,
	--- Resolved from `GameIds` at require time. 0 means not synced, which means not sellable.
	PassId: number,
	--[[ The pass's STORE icon, which the card draws in its circle.

		WRITTEN HERE RATHER THAN GENERATED, unlike `PassId`, and it is the one id in this project
		that is copied by hand. `rbxsync` uploads the icon and records it in `rbxsync.lock.toml` as
		`icon_asset_id`, but its codegen only emits the pass and product ids, so there is nothing to
		resolve against. Copy it out of the lockfile when an icon changes.

		These are ordinary Image ids and need no Decal round trip (`UIAssets` note 1 does not apply):
		checked with `CreateEditableImageAsync`, which loads all six and reports 150x150, because
		Roblox downscales a pass icon on upload. That is above what the card's circle renders at. ]]
	IconId: number,
}

--[[ Display order is DEAREST LAST, which is the opposite of most shops and is deliberate.

	The cheap pass is the one a first time buyer says yes to, and it is the one that has to be read
	first. Leading with VIP at 499 in front of an account that has never spent anything makes the
	whole tab read as expensive and the player closes it. Radio is first because it is the only one
	that is currently real. ]]
ShopConfig.Passes = {
	{
		Key = "Radio",
		Blurb = "Play music out of your car. Pick a station or paste your own track, and everyone nearby hears it.",
		Title = "",
		Price = 0,
		Wired = false,
		PassId = 0,
		IconId = 125894268442492,
	},
	{
		Key = "Nitro",
		Blurb = "Your nitro never empties. Hold it down for the whole run, in every car you drive.",
		Title = "",
		Price = 0,
		Wired = false,
		PassId = 0,
		IconId = 99921468576189,
	},
	{
		Key = "AutoCollect",
		Blurb = "Your bays collect themselves. No walking the lot, and your cars never stop earning while you race.",
		Title = "",
		Price = 0,
		Wired = false,
		PassId = 0,
		IconId = 71269586372431,
	},
	{
		Key = "HealthDouble",
		Blurb = "Every car you drive has double the health. Twice as much road before a wreck.",
		Title = "",
		Price = 0,
		Wired = false,
		PassId = 0,
		IconId = 126873990922819,
	},
	{
		Key = "LuckyRoads",
		Blurb = "Better cars on the road, every run. Rare traffic spawns far more often, and it stacks with the LUCK upgrades you own.",
		Title = "",
		Price = 0,
		Wired = false,
		PassId = 0,
		IconId = 71288365708196,
	},
	{
		Key = "CashDouble",
		Blurb = "Double every dollar you earn, forever: customer tips, run payouts and offline earnings.",
		Title = "",
		Price = 0,
		Wired = false,
		PassId = 0,
		IconId = 138187929865633,
	},
	{
		Key = "VIP",
		Blurb = "Gold VIP tags overhead and in chat, 35% bigger tips, and 2x VIP customers!",
		Title = "",
		Price = 0,
		Wired = false,
		PassId = 0,
		IconId = 129126956191963,
	},
} :: { Pass }

--[[ Everything but the blurb and the icon comes from `PassConfig`, resolved once at require time.

	FOUR FIELDS ABOVE ARE PLACEHOLDERS AND THIS LOOP IS WHERE THEY GET THEIR VALUES. They are written
	out in the table rather than omitted so the type checker sees a complete `Pass` and so a reader
	scanning the table is not left wondering where a card's price comes from — the answer is the
	line below, and it is the same direction `PassId` has always been filled in from `GameIds`.

	A KEY WITH NO `PassConfig` ENTRY WOULD BE DRAWN WITH NO TITLE AND NO PRICE, so it is refused
	loudly instead. That is unreachable today (both tables are hand-maintained in this repo) and it
	is exactly the kind of unreachable that stops being unreachable the week somebody renames a pass. ]]
for _, pass in ShopConfig.Passes do
	local declared = PassConfig.get(pass.Key)
	if declared then
		pass.Title = declared.Title
		pass.Price = declared.Price
	else
		warn(string.format("[ShopConfig] '%s' is not a pass in PassConfig, so its card cannot be drawn.", pass.Key))
	end
	pass.PassId = PassConfig.idOf(pass.Key)
	pass.Wired = PassConfig.isSellable(pass.Key)
end

-- === Bundles ================================================================

export type Bundle = {
	Key: string,
	--- The big line on the card.
	Title: string,
	--- The mockup's "Second title of bundle": what is actually in the box, in one line.
	Subtitle: string,
	--- The mockup's smaller "Description on the bundle": why it is worth it.
	Blurb: string,
	Price: number,
	--- What the same contents cost bought one at a time. The card shows the saving off this.
	PartsPrice: number,
	Wired: boolean,
	Seam: string,
	--- The FEATURED row wears the blue to cyan gradient the artist drew on the first card only.
	Featured: boolean,
	ProductId: number,
	--- The store icon. Copied from the lockfile by hand, for the reason `Pass.IconId` gives.
	IconId: number,
	--- What the receipt grants (`BundleService.grantBundle`): roster body names, stock paint, and cash.
	Cars: { string },
	Cash: number,
	--[[ Buyable once per player (2026-10-15, the Starter Bundle). The shop and the stand show OWNED
		and do not open the purchase once it is in `BundleStand.BoughtAttribute`. Roblox cannot be
		stopped from selling a product twice, so a second receipt (a forced prompt) still pays: the
		Robux is never taken for nothing. Never giftable either (`giftFor`). ]]
	OncePerPlayer: boolean?,
}

--- Has this player bought this once-only bundle? Off the replicated `BoughtAttribute`. Pure.
function ShopConfig.boughtOnce(player: Player, bundle: Bundle): boolean
	if not bundle.OncePerPlayer then
		return false
	end
	local list = player:GetAttribute(ShopConfig.BundleStand.BoughtAttribute)
	return type(list) == "string" and table.find(string.split(list, ","), bundle.Key) ~= nil
end

--[[ A BUNDLE IS A PRODUCT, NOT A PASS, and the test is whether there is anything to bank.

	`RadioConfig`'s header draws this line and `rbxsync.toml` repeats it: a pass is owned on Roblox
	and has no receipt, a product delivers a receipt and banks a counter on the profile. Everything
	in this box is a counter that already exists (cash on the balance, `RandomCarPulls`,
	`OfflineBoosts`), so this needs no new grant machinery, only a receipt that fires three grants
	the game already performs.

	THE SAVING IS THE WHOLE PITCH AND IT HAS TO BE TRUE. `PartsPrice` is the sum of the three
	products as priced in `rbxsync.toml` today (Cash2 89, RandomCar 99, OfflineBoost 49). If any of
	those three prices moves, this number moves with it or the card starts lying about the discount,
	which is a worse failure than the price contract in header note 1 because the player can check
	it against the Currency tab two clicks away.

	=== CAR BUNDLES — 2026-10-15 ===
	WAS: one unwired Starter Bundle of counters (cash, a pull, a boost) that nothing granted. IS:
	Aleafo's three CAR bundles, fixed contents named on the card. Fixed rather than rolled, so there
	are no odds to publish under Roblox's paid random items rules. Granted by `BundleService`. A car
	already owned goes in again (`GarageConfig.Banking.SellDuplicates` is off), and one that lands on
	a full inventory is auto-sold through `awardCar`'s own paid-receipt path, so a receipt never takes
	Robux for nothing.

	`Price` is only the FALLBACK. The pill shows what Roblox says this player pays
	(`GetProductInfo`, `PagesV2/Shop`), so a price changed on Roblox, or a regional or optimised price,
	is what the card says. `PartsPrice = 0` draws no SAVE badge: there is no honest "bought apart"
	price for a car you cannot buy apart.

	`ProductId` comes from `GameIds` by `Key`. Create the products as `StarterBundle`, `JDMBundle` and
	`SupercarBundle` and sync; a bundle with no id is simply not shown. ]]
ShopConfig.Bundles = {
	{
		Key = "StarterBundle",
		Title = "Starter Bundle",
		Subtitle = "Silven 15 + $10,000",
		Blurb = "A proper first car and the cash to get going.",
		Price = 49,
		PartsPrice = 0,
		Wired = true,
		Seam = "BundleService.grantBundle",
		Featured = true,
		ProductId = 0,
		IconId = 140540156188789,
		Cars = { "S15" },
		Cash = 10000,
		--- One per player, for ever (`BundleStand.BoughtAttribute`): a starter pack, priced as one.
		OncePerPlayer = true,
	},
	{
		Key = "JDMBundle",
		Title = "JDM Bundle",
		Subtitle = "Rexel 7 + Supran MK5 + Skylane 34",
		Blurb = "Three Japanese legends for your lot.",
		Price = 279,
		PartsPrice = 0,
		Wired = true,
		Seam = "BundleService.grantBundle",
		Featured = false,
		ProductId = 0,
		IconId = 140540156188789,
		Cars = { "RX7", "MK5 Supra", "Skyline R34" },
		Cash = 0,
	},
	{
		Key = "SupercarBundle",
		Title = "Supercar Bundle",
		Subtitle = "Aventra + Ferro 40 + Porten 918",
		Blurb = "The fastest way to a showroom of supercars.",
		Price = 799,
		PartsPrice = 0,
		Wired = true,
		Seam = "BundleService.grantBundle",
		Featured = false,
		ProductId = 0,
		IconId = 140540156188789,
		Cars = { "Lambo", "F40", "918" },
		Cash = 0,
	},
	--[[ The Roadster Limited Event's paid half (2026-10-22): the Rocket Edition, which never drives as
		traffic (`WorldConfig.EventBodies`, `Paid`). Hidden until the `FloaterRocketBundle` product exists
		and is synced into `GameIds`. ]]
	{
		Key = "FloaterRocketBundle",
		Title = "Floater Rocket Edition",
		Subtitle = "Limited: Floater Rocket",
		Blurb = "Body kit, live thrusters, sharper handling, and it hops.",
		Price = 399,
		PartsPrice = 0,
		Wired = false, -- Excluded from the October 26 mini update, even after product IDs are synced.
		Seam = "BundleService.grantBundle",
		Featured = false,
		ProductId = 0,
		IconId = 140540156188789,
		Cars = { "Tesla Roadster Rocket" },
		Cash = 0,
		OncePerPlayer = true,
	},
} :: { Bundle }

for _, bundle in ShopConfig.Bundles do
	bundle.ProductId = GameIds["products." .. bundle.Key] or 0
end

--- A bundle by its `Key`, or nil. For the lobby stands, which name theirs by attribute.
function ShopConfig.bundleOf(key: unknown): Bundle?
	for _, bundle in ShopConfig.Bundles do
		if bundle.Key == key then
			return bundle
		end
	end
	return nil
end

--[[ THE BUNDLES IN THE LOBBY (2026-10-15), the group reward stand's shape: a Model tagged `Tag`, with
	the attribute `Attribute` naming its bundle's `Key`, holding `CarSpot1`..`CarSpotN` (one per car,
	in `Cars` order) and an optional `Sign`. The parts read the stands' way (`CarDisplay.markerFrame`):
	bottom face on the ground, front face the way the car faces. `BundleService` parks the cars and
	the prompt; `BundleStandController` draws the sign with the player's live price and opens the
	purchase. A stand naming an unsold bundle (no product id) shows its cars and no prompt.
	`Enabled = false`: the stands stay bare. ]]
ShopConfig.BundleStand = {
	Enabled = true,
	Tag = "BundleStand",
	Attribute = "Bundle",
	--[[ === IT CYCLES — 2026-10-15 === (Aleafo: "make the cars cycle", one podium set for all the
		bundles). A stand may instead name several bundles in `ListAttribute`, comma separated, and
		shows them one at a time, `CycleSeconds` each. A bundle with fewer cars than the stand has
		podiums is centred on them. The server writes the bundle on show to `CurrentAttribute`, and
		the board, the price and the purchase all follow it. A stand with only `Attribute` shows that
		one bundle, as before. ]]
	ListAttribute = "Bundles",
	CurrentAttribute = "BundleCurrent",
	--[[ Seconds per slide (`BundleService._dress`): one bundle's cars, as many as the stand has
		podiums. A one-podium stand naming a three-car bundle shows each car this long in turn.
		2026-10-15: 10, Aleafo's number, with each podium its own bundle (WAS 6, cycling whole
		bundles across one three-podium stand). ]]
	CycleSeconds = 10,
	--- Degrees per second every car on a stand turns on its podium (client only). 0 stands them still.
	SpinDegreesPerSecond = 25,
	--- The player attribute listing every once-only bundle they own (`Bundle.OncePerPlayer`), and its
	--- profile key. The stand and the shop read it to show OWNED.
	BoughtAttribute = "BundlesBought",
	BoughtProfileKey = "BundlesBought",
	--- What a stand's board says in place of a price for a once-only bundle already owned.
	OwnedText = "OWNED",
	--[[ An authored podium set instead of `CarSpot` parts (`BundleService._podiumSpots`): podium
		models matching `PodiumPattern`, each with a `PlaceholderPrefix` car (its position and facing
		become the spot) and a `TerminalName` name plate. `PodiumYaw` turns every car by that many
		degrees, for placeholders whose pivot does not point along the nose (180 if they face
		backwards). ]]
	PodiumPattern = "Podium_%d+",
	PlaceholderPrefix = "Placeholder_",
	TerminalName = "CarInfoTerminal",
	PodiumYaw = 0,
	SpotPrefix = "CarSpot",
	SignName = "Sign",
	PromptName = "BundlePrompt",
	ActionText = "Buy Bundle",
	MaxDistance = 14,
	--- Studs above the ground the prompt sits at, on the middle car: about a car door.
	PromptHeight = 3.5,
	--[[ Studs. The board, and how high it floats over the MIDDLE car on a stand with no `Sign` part.
		8 clears every roof on the roster without climbing into the lobby's tree canopy, which is what
		hid it when it hung off a `Sign` placed 11 up (2026-10-15). `SignOnTop` draws it over anything
		in the way regardless, the way the stand's prompt already is. ]]
	SignSize = Vector2.new(13, 6),
	Lift = 8,
	SignOnTop = true,
	SignMaxDistance = 160,
}

-- === Currency ===============================================================

--[[ The six cash rungs, straight off `CashConfig`. Header note 1 on why there is no table here.

	The mockup draws FIVE tiles in a mosaic (three across, then two, the last one double width) and
	there are six rungs. The mosaic is a pitch rather than a capacity, the same way the gamepass 2x2
	is, and the tab scrolls. Do not drop a rung to make the drawing fit: `CashConfig.packFor` picks
	a rung from a player's SHORTFALL, so a rung missing from this tab is a gap a player can be sent
	to and then not find. ]]
function ShopConfig.cashPacks()
	return CashConfig.Packs
end

--[[ Rungs still sold but left out of the V2 shop list ON PURPOSE, so the page's boot check
	(`PagesV2/Shop._warnUncarded`) does not report them as the list falling behind the config.

	Bank Heist came off 2026-10-15: the owner found it uneven, one card alone under Armored Truck
	and Bank Vault. That overrules the note above for the shop only. It is still a product, so the
	shortfall offer can still name it, and so can a gift or a code. Put it back by restoring
	`UIImports.ShopV2List_WithBankHeist` and deleting its line here. ]]
ShopConfig.OffShelf = {
	Cash6 = true,
}

-- === Gifting ================================================================

--[[ A GIFT IS A BUTTON ON A CARD, NOT A MODE AND NOT A FOURTH TAB, and both halves of that are
	worth recording because both of the obvious alternatives were built first.

	A GIFT IS THE SAME CATALOGUE, POINTED AT SOMEBODY ELSE. `GiftConfig` mirrors every cash rung and
	every live pass at the same price, so a Gifts tab would be a near-exact copy of the two tabs
	beside it — the same six tiles and the same cards, drawn twice, and two places to keep the copy
	right. Worse, it splits a decision that is really one decision: a player who wants to give a
	friend a pass has already found the pass, on the Gamepasses tab, and does not want to go and
	find it again somewhere else.

	SO THE FIRST BUILD MADE IT A MODE — one GIFT toggle in the tab row that pointed the whole shelf
	at a recipient. That is what the owner replaced on 2026-09-04, and the reason is that a mode
	makes "who is this for" a state the PAGE is in rather than a fact about one purchase. It cost
	two presses to send one thing, a header that had to read GIFTING so the page did not lie about
	what its pills would do, and a rebuild of all three shelves every time somebody changed their
	mind about the recipient.

	A BUTTON BESIDE THE PRICE ASKS THE QUESTION WHERE IT HAS AN ANSWER: this card, this person,
	once. Nothing is remembered between two gifts, so there is no state to be stuck in and no way
	to buy something for a player you had forgotten you were pointed at.

	`GiftConfig.isSellable` still decides which cards carry a gift button, so a pass whose seam is
	unwired and a rung that never synced are un-giftable for the same reason they are unbuyable.

	THE COPY LIVES HERE AND THE RULES LIVE IN `GiftConfig`, which is the same split this file has
	with `PassConfig`. Nothing below decides anything. ]]
ShopConfig.Gift = {
	--[[ The picker's title, naming what is being given. `%s` is the gift's own name.

		IT NAMES THE THING RATHER THAN SAYING "PICK A PLAYER". The picker is opened from one card
		and answers one question, so the only thing a player can still be unsure of when it is up is
		which of the two buttons on that card they actually hit. The title answers that without
		anybody having to go back and look. ]]
	PickerFormat = "WHO GETS %s?",
	--- Shown in the picker when this player is alone in the server.
	PickerEmpty = "Nobody else is here right now.",
}

--[[ The gift entry that mirrors a shop card, or nil if that card cannot be gifted.

	KEYED OFF THE SAME `Key` THE CARD ALREADY CARRIES, so the page does not need a second table to
	map one to the other and a card whose gift is not sellable simply answers nil and keeps its
	ordinary BUY pill. `GiftConfig` builds its keys as `"Gift" .. key` for exactly this. ]]
function ShopConfig.giftFor(key: string): GiftConfig.Gift?
	--- A once-only bundle is never a gift (2026-10-15, the Starter Bundle), even if a gift product
	--- for it is ever made: it is one per ACCOUNT, and a gift would hand it to someone a second time.
	local bundle = ShopConfig.bundleOf(key)
	if bundle and bundle.OncePerPlayer then
		return nil
	end
	local gift = GiftConfig.get("Gift" .. key)
	return if gift and GiftConfig.isSellable(gift) then gift else nil
end

-- === Rules ==================================================================

--[[ Can this entry actually take money right now?

	Three ways to fail and they are different problems. An id of 0 was never synced (header note 2).
	`Wired = false` means the thing exists on Roblox but does nothing yet (header note 3). Neither is
	recoverable from the client, so the page's job is to not draw the card at all rather than to draw
	a card that fails when pressed. ]]
function ShopConfig.isSellable(entry: { Wired: boolean, PassId: number?, ProductId: number? }): boolean
	local id = entry.PassId or entry.ProductId or 0
	if id == 0 then
		return false
	end
	return entry.Wired or ShopConfig.ShowUnwired
end

--- The entries of a tab that should actually be drawn, in display order.
function ShopConfig.visiblePasses(): { Pass }
	local out = {}
	for _, pass in ShopConfig.Passes do
		if ShopConfig.isSellable(pass) then
			table.insert(out, pass)
		end
	end
	return out
end

function ShopConfig.visibleBundles(): { Bundle }
	local out = {}
	for _, bundle in ShopConfig.Bundles do
		if ShopConfig.isSellable(bundle) then
			table.insert(out, bundle)
		end
	end
	return out
end

--- "SAVE 24%". The card's own claim, computed rather than typed, so it cannot drift from the prices.
function ShopConfig.savingLabel(bundle: Bundle): string
	if bundle.PartsPrice <= 0 or bundle.Price >= bundle.PartsPrice then
		return ""
	end
	local percent = math.floor((1 - bundle.Price / bundle.PartsPrice) * 100 + 0.5)
	return string.format("SAVE %d%%", percent)
end

--- "R$149". One place, so every pill in the shop reads the same.
function ShopConfig.priceLabel(price: number): string
	return "R$" .. tostring(price)
end

return ShopConfig
