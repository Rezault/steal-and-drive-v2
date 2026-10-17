--[[
	PassConfig
	----------
	THE ENTITLEMENT LAYER. Which game passes exist as a KEY, what id each resolves to, which
	attribute it is broadcast on, and whether the code behind it is written yet. `PassService` is
	the only thing that answers ownership and this is the table it answers from.

	=== THIS IS NOT THE SHOP, AND THE SPLIT IS DELIBERATE =======================================

	`ShopConfig` owns COPY AND ORDER — the card title, the two-line blurb, the icon, which tab it
	sits on, which one is drawn first. This owns the FACT: that a key called `AutoCollect` names a
	real pass with a real id whose behaviour exists. A screen reads the first; a service reads the
	second; neither has an opinion about the other's job.

	IT TOOK ONE PLACE OUT OF THE THREE `ShopConfig` COMPLAINS ABOUT. That file's header note 3 says
	a pass's readiness is recorded in three places that have to agree — `for_sale` in `rbxsync.toml`,
	`Wired` in `ShopConfig`, and the seam itself. `Wired` is now DERIVED from `Live` below rather
	than typed a second time, so there are two: whether Roblox will take the money, and whether the
	game does anything with it. The shop reads this file for the answer.

	=== FIVE THINGS TO KNOW ====================================================================

	1. AN ID OF 0 MEANS "CANNOT BE SOLD", NEVER "FREE", exactly as it does everywhere else products
	   are resolved. `GameIds` answers nil for a key that has never been synced, `isSellable` reads
	   that as dead, and every screen and service takes the feature off rather than offering it.

	2. `Live` IS A CLAIM ABOUT CODE, NOT ABOUT ROBLOX. It says the seam named beside it is written
	   and playtested. A pass with `Live = false` may exist on Roblox, have an id, have icon art and
	   still be worth nothing, which is the state four of these were in on 2026-09-02.

	3. OWNERSHIP IS TWO SOURCES AND `PassService` UNIONS THEM. Bought on Roblox is
	   `UserOwnsGamePassAsync`; GIFTED is the `ProfileKey` table below, because Roblox has no way to
	   attach a pass to an account somebody else paid for. `PassService`'s header has the whole
	   argument and it is worth reading before adding a sixth reader of either.

	4. THE ATTRIBUTE IS A BROADCAST AND DECIDES NOTHING. `ownedAttribute(key)` is what a client
	   reads to draw a card as OWNED. Every ruling is made on the server against `PassService`, for
	   the same reason `GarageConfig.OwnedAttribute` is a mirror of the profile and not the profile:
	   an attribute is a replicated property and a client can lie about its own copy of it.

	5. THE NAMES ARE FROZEN BY WHAT ALREADY SHIPPED. `ownedAttribute` is `<Key>Pass`, which is not a
	   style choice: `RadioConfig.OwnedAttribute` has been the string `"RadioPass"` since the radio
	   shipped and `RadioController` reads it. The generator has to keep producing that exact string
	   for `Radio`, so do not "tidy" it into `Pass_<Key>` or `<Key>Owned`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- The rbxsync-generated id table. Ids are resolved by KEY and never pasted — see `shared/GameIds`.
local GameIds = require(ReplicatedStorage.shared.GameIds)

local PassConfig = {}

--[[ Master switch for the entitlement layer. Off = `PassService` answers false for everything and
	every pass behaves exactly as it did before it was bought, which is the state to put the game in
	if the ownership check itself is ever suspected of being the problem. It does NOT stop Roblox
	selling the passes — that is `for_sale` in `rbxsync.toml`, and it is deliberately not reachable
	from here: a switch in a config file that could silently take a paid pass away from everyone who
	owns it is a switch worth not having. ]]
PassConfig.Enabled = true

--[[ Gifted passes, as a set of pass keys on the profile: `{ AutoCollect = true }`.

	TOP-LEVEL for the same reason `ExtraLives`, `OfflineBoosts` and `RandomCarPulls` are:
	`PlayerProfile`'s string path is a recursive key search, so a key nested inside `Garage` would be
	reachable only by array path from the two places that touch it. See `Settings.TEMPLATE`.

	A SET AND NOT A LIST, because the only question ever asked of it is "is this key in here" and a
	list would make that a linear scan that can also hold the same pass twice. Nothing is ever
	removed: a gift is not revocable and there is no un-gifting, the same call `LikesGiven` makes.

	Absent is "has been gifted nothing", so no profile written before this key existed needs
	migrating. ]]
PassConfig.ProfileKey = "Passes"

-- === The passes =============================================================

export type Pass = {
	--- The `[passes.<key>]` block in `rbxsync.toml`, and the only name any other file needs.
	Key: string,
	--[[ The pass's name ON ROBLOX, character for character the `name` in its `rbxsync.toml` block.

		A FACT ABOUT THE STORE, NOT CARD COPY. It is what Roblox prints in the purchase prompt, so a
		screen that calls the pass anything else is a screen that surprises the player at the moment
		they are deciding. `ShopConfig` and `GiftConfig` both read it from here rather than keeping a
		copy, which is one fewer place for the shop and the prompt to disagree. ]]
	Title: string,
	--[[ Robux, and the same number as the `price` in its `rbxsync.toml` block.

		WHAT ROBLOX CHARGES IS STILL THE TOML AND ALWAYS WILL BE — this is the copy the game shows,
		and the two have to agree by hand. That contract is unchanged from `RadioConfig.Price`; what
		changed is that there is now ONE copy in the codebase instead of one per screen. ]]
	Price: number,
	--- Resolved from `GameIds` at require time. 0 means never synced, which means not sellable.
	PassId: number,
	--[[ Is the code behind it written and playtested? See note 2. A pass that is not live is
		refused by `isSellable`, so it is not drawn in the shop, not giftable, and `PassService`
		never asks Roblox about it. ]]
	Live: boolean,
	--- The file and function a reader has to change to make this pass do anything. Documentation.
	Seam: string,
}

--[[ Declaration order only. The SHOP's order is `ShopConfig.Passes` and is a separate decision made
	for a separate reason (cheapest first, so a first-time buyer reads a price they might say yes
	to). Nothing iterates this expecting a running order. ]]
PassConfig.Passes = {
	{
		Key = "Radio",
		Title = "Car Radio",
		Price = 49,
		PassId = 0,
		Live = true,
		Seam = "RadioService - shipped 2026-08-24, the first pass this game sold",
	},
	{
		Key = "AutoCollect",
		Title = "Auto Collect",
		Price = 249,
		PassId = 0,
		--[[ OFF SINCE 2026-09-28. Its whole behaviour is sweeping the collect mats, and without
			passive income (`GarageConfig.Income.Passive`) there is nothing on a mat to sweep — so
			selling it would take Robux for nothing, which rule 2 above exists to stop. Pre-release,
			so nobody owns it. `Live = false` also takes it out of the shop and the gift list
			(`isSellable`). Flip back with `Income.Passive`. ]]
		Live = false,
		Seam = "GarageService._sweep, on the GarageConfig.Collect.Auto interval",
	},
	{
		Key = "HealthDouble",
		Title = "2x Car HP",
		Price = 179,
		PassId = 0,
		Live = true,
		Seam = "ObstacleService._setMaxHealth, the one place a car HP ceiling is stamped",
	},
	{
		Key = "Nitro",
		Title = "Unlimited Nitro",
		Price = 199,
		PassId = 0,
		Live = false,
		Seam = "NitroConfig.powerFor, which already turns an owned level into a scale and a duration",
	},
	{
		Key = "CashDouble",
		Title = "2x Cash",
		Price = 399,
		PassId = 0,
		--[[ LIVE SINCE 2026-10-15 (pass 2039858373). Doubles what a player EARNS: tips, collected bay
			income, run payouts, speed traps and the offline payout, all through
			`GarageService.incomeMultiplier`. Not what they are GIVEN or BUY (cash packs, codes, daily
			rewards, quests, sales, refunds): doubling a cash pack would sell cash at half price. ]]
		Live = true,
		Seam = "GarageService.incomeMultiplier, read at every earning site",
	},
	{
		Key = "VIP",
		Title = "VIP",
		Price = 399,
		PassId = 0,
		Live = true,
		Seam = "VIPController tags; CustomerService tips and kinds; OfflineService income estimate",
	},
	{
		Key = "LuckyRoads",
		Title = "Lucky Roads",
		Price = 499,
		PassId = 0,
		Live = true,
		Seam = "UpgradeConfig.LuckyRoadsStep, one term in luckFactor, rolled by TrafficController._pickTier",
	},
} :: { Pass }

--- Resolved once, at require time, exactly as `CashConfig.Packs` and `ShopConfig.Passes` do.
for _, pass in PassConfig.Passes do
	pass.PassId = GameIds["passes." .. pass.Key] or 0
end

--- Keyed for the lookups below, which happen on the hot path of every ownership question.
local byKey: { [string]: Pass } = {}
for _, pass in PassConfig.Passes do
	byKey[pass.Key] = pass
end

-- === Rules ==================================================================

--- The declaration for a key, or nil. `nil` is an ordinary answer: a caller may hold a key from a
--- profile written by a newer build than this server is running.
function PassConfig.get(key: unknown): Pass?
	return if type(key) == "string" then byKey[key] else nil
end

--[[ Can this pass actually take money AND do something right now?

	THREE WAYS TO FAIL AND THEY ARE DIFFERENT PROBLEMS, the same three `ShopConfig.isSellable`
	separates: the layer is switched off, the id was never synced, or the seam is not written. None
	is recoverable from a caller, so every one of them means "do not offer this", never "offer it
	and hope". ]]
function PassConfig.isSellable(key: unknown): boolean
	if not PassConfig.Enabled then
		return false
	end
	local pass = PassConfig.get(key)
	return pass ~= nil and pass.PassId ~= 0 and pass.Live
end

--- The pass id for a key, or 0. Zero is the "cannot be sold" sentinel every caller already knows.
function PassConfig.idOf(key: unknown): number
	local pass = PassConfig.get(key)
	return if pass then pass.PassId else 0
end

--- The key a pass id belongs to, or nil. `PassService` needs this to turn a
--- `PromptGamePassPurchaseFinished` into something it can refresh.
function PassConfig.keyOf(passId: unknown): string?
	if type(passId) ~= "number" or passId == 0 then
		return nil
	end
	for _, pass in PassConfig.Passes do
		if pass.PassId == passId then
			return pass.Key
		end
	end
	return nil
end

--[[ The Player attribute this pass is broadcast on. `"RadioPass"` for `Radio` — see note 5, that
	string is frozen by what already shipped and `RadioConfig.OwnedAttribute` is the same value
	written out longhand. ]]
function PassConfig.ownedAttribute(key: string): string
	return key .. "Pass"
end

--- Every key whose seam is live and whose id resolved. The list `PassService` actually asks Roblox
--- about on a join, and the list the gift screen offers.
function PassConfig.sellableKeys(): { string }
	local out = {}
	for _, pass in PassConfig.Passes do
		if PassConfig.isSellable(pass.Key) then
			table.insert(out, pass.Key)
		end
	end
	return out
end

return PassConfig
