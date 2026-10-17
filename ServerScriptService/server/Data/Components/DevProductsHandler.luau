--[[
	DevProductsHandler
	------------------
	What each Robux developer product actually gives you, keyed by its product id.

	THE IDS ARE NOT TYPED IN HERE. `rbxsync.toml` is where a product is declared, named and priced;
	`rbxsync sync` creates it on Roblox and generates `shared/GameIds.luau`, and the config module
	for that feature resolves its own id out of that table by key. So a product is registered below
	by reading it off its config, never by pasting a number — which is what keeps this file correct
	when a product is recreated, and what makes a product that has not been synced yet register
	nothing at all rather than register against 0.

	A GRANT MUST BE SOMETHING A PROFILE CAN HOLD. Receipts do not arrive at convenient moments: this
	one can land while the player is mid-race, back in the lobby, or on a session days later after a
	retry, and it can arrive on a server that has never seen them do the thing they bought. So the
	products here write a durable counter and let the feature spend it — see `ExtraLives` in
	`Settings.TEMPLATE` for the long version of why.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local CashConfig = require(ReplicatedStorage.shared.Configs.CashConfig)
local GiftConfig = require(ReplicatedStorage.shared.Configs.GiftConfig)
local OfflineConfig = require(ReplicatedStorage.shared.Configs.OfflineConfig)
local RandomCarConfig = require(ReplicatedStorage.shared.Configs.RandomCarConfig)
local ReviveConfig = require(ReplicatedStorage.shared.Configs.ReviveConfig)
local ShopConfig = require(ReplicatedStorage.shared.Configs.ShopConfig)

local Types = require(script.Parent.Types)

--[[ How many purchase ids a profile remembers, to recognise a receipt Roblox delivers twice.

	WAS 100, IS 1000 (2026-09-28, security review). Roblox re-delivers a receipt until it is
	acknowledged, so the ledger's job is the window between a grant being saved and the
	acknowledgement landing — normally seconds. What 100 left open was the tail: a buyer of the
	repeatable products (cash packs, pulls, boosts) who made a hundred more purchases before an old
	unacknowledged receipt came back would have it evicted and granted twice. A purchase id is a
	~36-character string, so 1000 is about 40 KB against ProfileStore's 4 MB — cheap enough that the
	tail stops being reachable by any real buyer. ]]
local PURCHASE_ID_CACHE_SIZE = 1000

--[[ A grant that could not land: raise, so `PurchaseIdCheckAsync`'s pcall answers `NotProcessedYet`
	and Roblox re-delivers the receipt later, rather than acknowledging Robux for nothing. The raise IS
	the retry — see the cash block, which was already written this way. (2026-09-28, security review:
	the revive, boost and pull grants used to return quietly here and the receipt was consumed.) ]]
local function mustGrant(granted: unknown, what: string)
	if granted ~= true then
		error(string.format("%s could not be granted; the receipt will be retried.", what))
	end
end
local DevProductsHandler = {}
local ProductFunctions = {}

--[[ REVIVE — the paid continue on the respawn screen (`ReviveService`).

	One product per rung of `ReviveConfig.Tiers`, because the price climbs within a run and Roblox
	prices a product rather than a purchase. All three grant the same thing: one stored life. Which
	rung the player is on is the server's business, decided when the offer is made, so the product
	that got bought never has to be interpreted here.

	`Shard.get` is called at grant time rather than at load: this module is required by `Data`, which
	initialises well before the service layer, and a receipt can only ever arrive long after both. ]]
for _, tier in ReviveConfig.Tiers do
	if tier.ProductId ~= 0 then
		ProductFunctions[tier.ProductId] = function(_profile: Types.PlayerProfile, _data: Types.Data, player: Player?)
			local ReviveService = Shard.get("ReviveService")
			mustGrant(ReviveService and player and ReviveService:grantLife(player, 1), "A revive")
		end
	end
end

--[[ THE OFFLINE BOOST ON THE WELCOME BACK SCREEN (`OfflineService`).

	One product, buyable as often as they like — the opposite of the ladder above, because what it
	multiplies is capped by the lot rather than by how many times it has been bought.

	It grants a STORED boost and nothing else, for the reason at the top of this file: the receipt
	can land when the screen has already gone, and a multiplier that only exists while a panel is up
	is Robux paid for nothing. `OfflineService.grantBoost` banks it, and spends it on the spot only
	if the player is still looking at the offer it was bought for. ]]
if OfflineConfig.Boost.Enabled and OfflineConfig.Boost.ProductId ~= 0 then
	ProductFunctions[OfflineConfig.Boost.ProductId] = function(_profile: Types.PlayerProfile, _data: Types.Data, player: Player?)
		local OfflineService = Shard.get("OfflineService")
		mustGrant(OfflineService and player and OfflineService:grantBoost(player, 1), "An offline boost")
	end
end

--[[ THE RANDOM CAR PULL (`RandomCarService`).

	One product, bought as often as they like — the `OfflineBoost` shape rather than the revive
	ladder, because every pull is the same roll against the same table and a climbing price would
	only punish a player for enjoying it. `RandomCarConfig`'s header has the long version.

	IT BANKS A PULL AND ROLLS NOTHING. That is the rule at the top of this file applied to the one
	product where breaking it would be most tempting: rolling here would be one line, the car would
	land in the profile correctly, and the player would never see it happen. The roll is what 99
	Robux buys — the sunburst, the shape turning into a car — so the receipt banks the right to it
	and `RandomCarService` spends that in front of a screen.

	`grantPull` applies it on the spot if the player is sitting in front of the card they bought it
	from, exactly as `OfflineService.grantBoost` does, and banks it for the next screen if not. ]]
if RandomCarConfig.sellable() then
	ProductFunctions[RandomCarConfig.ProductId] = function(_profile: Types.PlayerProfile, _data: Types.Data, player: Player?)
		local RandomCarService = Shard.get("RandomCarService")
		mustGrant(RandomCarService and player and RandomCarService:grantPull(player, 1), "A random car pull")
	end
end

--[[ THE CASH PACKS (`CashService`).

	SIX PRODUCTS AND ONE GRANT, which is the only place in this file where a loop over a ladder is
	not also a loop over behaviours: `ReviveConfig.Tiers` climbs in price because the third revive
	of a run is worth less than the first, and all three still bank one life. These six climb
	because they hand over different AMOUNTS, and the amount is the only thing that differs. So the
	rung is captured per registration and read back off the receipt, never interpreted here.

	AND IT IS THE ONE PRODUCT IN THIS FILE THAT BANKS NOTHING. The rule at the top says a grant has
	to be something a profile can hold, and cash is not merely something a profile can hold, it IS a
	profile key. There is no counter to invent, nothing to spend in front of a screen, and nothing
	lost by a receipt that lands two sessions late. `CashService.grantCash` writes it in through
	`GarageService`, which is the only thing in the game allowed to write `Cash`.

	`grantCash` YIELDS AND CAN THROW, both wanted. It waits for the profile rather than testing for
	it, and a wait that runs out raises, which `PurchaseIdCheckAsync` turns into `NotProcessedYet`
	so Roblox re-delivers the receipt. The three products above used to warn and return instead,
	which acknowledged the receipt for nothing; since 2026-09-28 they raise too (`mustGrant`). ]]
if CashConfig.sellable() then
	for _, pack in CashConfig.Packs do
		if pack.ProductId ~= 0 then
			ProductFunctions[pack.ProductId] = function(_profile: Types.PlayerProfile, _data: Types.Data, player: Player?)
				local CashService = Shard.get("CashService")
				if not (CashService and player) then
					--- Raised rather than dropped, for the reason in the block above: the receipt is
					--- retried, and a player who paid gets their money on a server that can pay it.
					error("No CashService or no player, so a cash pack receipt cannot be paid in.")
				end
				CashService:grantCash(player, pack)
			end
		end
	end
end

--[[ THE GIFTS (`GiftService`).

	TWELVE PRODUCTS THAT MIRROR THINGS ALREADY REGISTERED ABOVE, and every one of them grants what
	its counterpart grants to somebody who is not the buyer. `GiftConfig` is the catalogue,
	`rbxsync.toml`'s GIFTS section is the commercial argument, and `GiftService`'s header is where
	the hard part lives.

	THE HARD PART IS THAT A RECEIPT CANNOT CARRY A RECIPIENT. `receiptInfo` names a product and a
	buyer, full stop — so the recipient was written to the BUYER's profile before the prompt opened
	and is read back here. That is why this registration passes the buyer rather than looking one up:
	`grantGift` needs the buyer's profile to find out who the gift was for.

	IT IS THE ONLY THING IN THIS FILE THAT CAN GRANT A GAME PASS, which contradicts the rule stated
	in `rbxsync.toml`'s Game Passes section ("nothing below appears in `DevProductsHandler`"). That
	rule holds for every pass anybody BUYS; a gifted pass has no Roblox ownership to read, so the
	entitlement is a profile key and `PassService` unions the two. Nothing else about passes changed.

	`grantGift` YIELDS AND CAN THROW, exactly as `grantCash` does, and for the same reason: a throw
	becomes `NotProcessedYet` and Roblox re-delivers, which is what a gift that could not be posted
	needs. See the ordering note in `grantGift` about putting the intent back before it raises. ]]
for _, gift in GiftConfig.Gifts do
	if gift.ProductId ~= 0 then
		ProductFunctions[gift.ProductId] = function(_profile: Types.PlayerProfile, _data: Types.Data, player: Player?)
			local GiftService = Shard.get("GiftService")
			if not (GiftService and player) then
				--- Raised rather than dropped, for the reason the cash block gives: the receipt is
				--- retried, and the gift reaches its recipient off a server that can send it.
				error("No GiftService or no player, so a gift receipt cannot be sent.")
			end
			GiftService:grantGift(player, gift)
		end
	end
end

--[[ THE CAR BUNDLES (`ShopConfig.Bundles`, `BundleService`, 2026-10-15).

	Cars and cash, both things a profile holds outright, so like the cash packs nothing is banked to
	spend later: `grantBundle` pays it all in. It waits for the profile and raises if it never comes,
	so a receipt that beat the join is retried rather than taken for nothing. ]]
for _, bundle in ShopConfig.Bundles do
	if ShopConfig.isSellable(bundle) then
		ProductFunctions[bundle.ProductId] = function(profile: Types.PlayerProfile, _data: Types.Data, player: Player?)
			local BundleService = Shard.get("BundleService")
			if not (BundleService and player) then
				error("No BundleService or no player, so a bundle receipt cannot be paid in.")
			end
			--- The profile goes with it, for a once-only bundle's record (`Bundle.OncePerPlayer`).
			BundleService:grantBundle(player, bundle, profile)
		end
	end
end

-- Internal:
function DevProductsHandler:ProcessReceipt(receiptInfo, data: Types.Data)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)

	--[[ Robux revenue, as a GameAnalytics business event. The SDK's own handler does the currency
		and product lookup, so this is the whole integration.

		BEFORE the grant rather than after, and outside the dedup: `PurchaseIdCheckAsync` returns
		early for a receipt Roblox is re-delivering, and a `return` inside it would silently stop
		reporting any purchase that needed a retry. Reporting is idempotent on GA's side — it keys on
		the purchase id — so the safe error here is reporting twice, not missing one. ]]
	local Analytics = Shard.get("AnalyticsService")
	if Analytics then
		Analytics:ReportReceipt(receiptInfo)
	end

	--[[ NOT HERE, NOT YET (2026-09-28, security review). A receipt for a player who has left this
		server is re-delivered by Roblox to whichever server they join next, which is the only one that
		can grant it; asking for a profile with a nil player here would fail inside the Data layer. ]]
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	--[[ AN UNKNOWN PRODUCT IS NOT ACKNOWLEDGED. It used to warn and fall through to a granted receipt,
		so a product created on Roblox but not yet registered here (an rbxsync run ahead of a deploy)
		took the Robux and gave nothing. Left unprocessed, Roblox keeps re-delivering it, and the build
		that knows the product grants it. ]]
	local grant = ProductFunctions[receiptInfo.ProductId]
	if not grant then
		warn("No product function defined for ProductId:", receiptInfo.ProductId, "- left unprocessed for a build that has one.")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local profile = data:GetProfileAsync(player)
	if profile then
		return self:PurchaseIdCheckAsync(profile:GetProfile(), receiptInfo.PurchaseId, function()
			grant(profile, data, player)
			--- Gamebeast wants NEW grants only, which is exactly when this closure runs (after the
			--- purchase-id dedup, and only if the grant did not throw). See `ReportGrantedPurchase`.
			if Analytics then
				Analytics:ReportGrantedPurchase(receiptInfo)
			end
		end)
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function DevProductsHandler:PurchaseIdCheckAsync(profile, purchase_id, grant_product): Enum.ProductPurchaseDecision
	if profile:IsActive() == true then
		local purchase_id_cache = profile.Data.PurchaseIdCache

		if purchase_id_cache == nil then
			purchase_id_cache = {}
			profile.Data.PurchaseIdCache = purchase_id_cache
		end

		if table.find(purchase_id_cache, purchase_id) == nil then
			local success, result = pcall(grant_product)
			if success ~= true then
				warn(`Failed to process receipt:`, profile.Key, purchase_id, result)
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end

			while #purchase_id_cache >= PURCHASE_ID_CACHE_SIZE do
				table.remove(purchase_id_cache, 1)
			end

			table.insert(purchase_id_cache, purchase_id)
		end

		local function is_purchase_saved()
			local saved_cache = profile.LastSavedData.PurchaseIdCache
			return if saved_cache ~= nil then table.find(saved_cache, purchase_id) ~= nil else false
		end

		if is_purchase_saved() == true then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		while profile:IsActive() == true do
			local last_saved_data = profile.LastSavedData

			profile:Save()

			if profile.LastSavedData == last_saved_data then
				profile.OnAfterSave:Wait()
			end

			if is_purchase_saved() == true then
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end

			if profile:IsActive() == true then
				task.wait(10)
			end
		end
	end

	return Enum.ProductPurchaseDecision.NotProcessedYet
end

return DevProductsHandler
