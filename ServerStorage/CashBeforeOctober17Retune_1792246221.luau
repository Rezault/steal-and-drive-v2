--[[
	CashConfig
	----------
	CASH PACKS: the Robux top-up offered at the moment you press a price you cannot meet.

	=== READ THIS FIRST: A PACK IS OFFERED, AND THE OFFER IS STILL THE POINT ==================

	The only way one of these was ever seen, until 2026-09-03, was by pressing something you are
	short of: a dealer bay, a bay kiosk, the forecourt billboard, a world tile. All four of those
	refused SILENTLY before this file existed, and that silent refusal is the thing being replaced.

	The design is worth defending in one line, because the obvious alternative is a shop. A shop
	full of cash packs is furniture the player stops seeing inside a session. An offer that arrives
	the instant they wanted something and could not have it is the same offer with every scrap of
	context supplied for free, and it costs no screen space at all.

	THIS HEADER USED TO SAY NO SCREEN MAY EVER LIST THESE, AND THERE IS NOW ONE THAT DOES. The SHOP
	page's Currency tab (`Controllers/UIController/Pages/Shop`) reads `Packs` below and draws the
	whole ladder. That is a change of policy, made deliberately, and the paragraph above survives it
	intact: the shortfall offer is still the route that sells, still the one every refusal site
	calls, and nothing about it moved. What the tab adds is somewhere for a player who has already
	decided to spend to go and do it, which the offer path cannot serve because it only ever fires
	at the moment of a refusal.

	IT FOLLOWS THAT THIS FILE IS READ BY TWO KINDS OF CALLER NOW, and they want different things.
	`packFor` answers "what closes this gap", which is the offer. The shop wants the LADDER, in
	order, whole, including rungs a particular player would never be offered. Both read `Packs`
	directly and neither is allowed to reorder it: the shop draws the rungs top to bottom and paints
	one glyph per POSITION (`UIAssets.CashTiers`), so the order here is now on screen.

	=== WHY THERE ARE SIX OF THEM ============================================================

	The cash economy spans six orders of magnitude and it is not close. The cheapest thing a dealer
	bay ever offers is a tier 1 car at $1,440. The dearest is the top car of world 4 at
	$3,331,355,040, with the world 4 gate at $1.3B standing in front of it, and the bay ladder
	reaching $255M on its own. One pack cannot serve both ends of that: sized for the bottom it is
	invisible by world 2, sized for the top it hands a new player the entire game on their first
	press.

	So the ladder is six rungs, ten times apart, and every rung is anchored to something a player is
	actually standing in front of at the moment it gets offered to them:

	    RUNG   CASH             R$      $ per R$    what the player is looking at
	    -------------------------------------------------------------------------------------
	    1      $15,000            29        517     a starter car, plus the first bay levels
	    2      $150,000           89      1,685     a top of world 1 car ($56,160)
	    3      $1,500,000        249      6,024     most of a top of world 2 car ($2,190,240)
	    4      $15,000,000       599     25,042     half the world 3 gate ($33,000,000)
	    5      $150,000,000    1,399    107,219     a top of world 3 car ($85,419,360)
	    6      $1,500,000,000  2,999    500,167     the world 4 gate ($1,300,000,000)

	DOLLARS GET CHEAPER AS THE RUNGS CLIMB, ON PURPOSE. Cash inflates 39x per world (a world's
	bottom car pays 39 times what the world below it did, and `GarageConfig.Income` derives that
	ratio rather than declaring it), so a rung priced by the dollar would be unbuyable by world 3.
	Ten times the cash for roughly two and a half times the Robux is what keeps every rung worth
	about the same THING, which is the only currency a player actually reasons in.

	ONE HONEST WEAKNESS, WRITTEN DOWN SO IT IS RETUNED RATHER THAN REDISCOVERED. Income inflates
	faster than this ladder does, so measured in TIME SAVED the top rungs are the weakest: rung 2 is
	about fifteen minutes of a finished world 1 lot, rung 5 about four minutes of a finished world 3
	one. If the dashboard ever says the upper rungs do not sell, the fix is the `Price` column here
	and nothing else in the codebase has to move.

	=== WHERE THIS SITS AGAINST THE OTHER FOUR PRODUCTS ======================================

	`OfflineConfig.Boost` is better value per dollar than any rung here on a full lot and that is
	correct, not an oversight. The boost is gated twice over: it pays out only what the bays were
	already holding, capped by `GarageConfig.Income.MaxBankedSeconds`, and it can only be claimed
	against an absence that actually happened. A pack is buyable on demand, unlimited, at any hour.
	The gated product has to be the better deal or nobody buys it, and an on demand product under
	it would kill the welcome back screen outright.

	`RandomCarConfig` sells a car and this sells the money for one, so the two look like rivals and
	are not. A pull is a roll against the whole ladder for a flat 99 and most of what it buys is the
	moment. A pack is a specific car the player already chose, at a price that scales with how good
	that car is. They answer different questions, and rung 3 costing more than a pull is that
	difference priced: choosing beats rolling, so choosing costs more.

	=== THE ONE NUMBER THAT DECIDES WHICH RUNG IS OFFERED =====================================

	THE SHORTFALL, never the price. A player $1 short of a $1.3B world tile is offered rung 1 for 29
	Robux, because $1 is what they are missing. A player at zero pressing the same tile is offered
	rung 6. `packFor` is a dozen lines and that is the whole of the rule, but it is the rule that
	makes an unasked for Robux modal defensible: it never asks for more than the gap.

	SHORT BY MORE THAN THE TOP RUNG IS ANSWERED WITH THE TOP RUNG rather than with nothing. Only the
	world 4 top car reaches that today ($3.33B against rung 6's $1.5B), and being offered half of
	what you need is honest as long as the pack says what it grants, which Roblox's own modal does.
	The alternative is the silent refusal this file exists to delete.

	=== A PACK GRANTS CASH, AND CASH IS ALREADY DURABLE =======================================

	Every other product in this game banks a counter (`ExtraLives`, `OfflineBoosts`,
	`RandomCarPulls`) because a receipt arrives when it arrives and the thing bought has to survive
	the wait. `DevProductsHandler`'s header is the long version.

	THIS PRODUCT NEEDS NO COUNTER, because the thing it grants IS a profile key. Cash is written by
	`GarageService.addCash` and read back from the same place a second later, a week later, or on
	another server. There is nothing to spend in front of a screen and nothing lost by granting it
	late, so `CashService.grantCash` writes it straight in. That is not this file breaking the
	banking rule, it is the banking rule reaching its base case.

	`Enabled = false` takes the whole thing out: no prompt from any of the four sites, no product
	registered in `DevProductsHandler`, and the four refusals go back to being silent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- The rbxsync generated id table. Ids are resolved out of here by KEY and never pasted, so a pack
--- that has not been synced yet reads as "cannot be sold" rather than as product 0.
local GameIds = require(ReplicatedStorage.shared.GameIds)
--- For `cashFor` (scaling, below): the income attributes, the world a player has reached and that
--- world's car prices. All three are configs that require nothing of this file.
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local BalanceConfig = require(ReplicatedStorage.shared.Configs.BalanceConfig)

local CashConfig = {}

--- Master switch. The last line of the header says exactly what off means.
CashConfig.Enabled = true

-- === The ladder =============================================================

export type Pack = {
	--- Ties this rung to its `[products.<key>]` block in `rbxsync.toml`.
	Key: string,
	--- The product's name on Roblox and on every screen (the amount is the player's, see `cashFor`).
	Name: string,
	--- The FIXED amount, paid only with `Scaling.Enabled` off. With it on, see `cashFor`.
	Cash: number,
	--- Scaling: minutes of the player's live income this rung is worth.
	Minutes: number,
	--- Scaling: never less than this many of the cheapest car in their best world, never more than
	--- this many of the dearest.
	FloorCars: number,
	CapCars: number,
	--[[ What Roblox charges. Written here as well as in `rbxsync.toml` so a caller can reason about
		the cost without a `GetProductInfo` round trip, and the two have to agree by hand. Same
		contract as `OfflineConfig.Boost.Price` and `ReviveConfig.Tiers[n].Price`, same one line
		failure if it is broken. ]]
	Price: number,
	--- Filled in below from `GameIds`. Zero means never synced, which reads everywhere as "this rung
	--- cannot be sold" and is the whole reason `sellable` exists.
	ProductId: number,
	--- `ByWorld`: what this rung pays in each world, read at the player's highest unlocked world.
	CashByWorld: { number }?,
	--- No longer sold: never offered and never a gift, but still registered so a late receipt pays.
	Retired: boolean?,
}

--[[ Six rungs, ten times apart, argued at length in the header.

	KEYED BY RUNG AND NOT BY AMOUNT (`Cash1`, not `Cash15K`), following `ReviveConfig.Tiers`. A key
	names a POSITION on the ladder, so retuning what a rung grants stays a one number edit here and
	never orphans a product that has already been created on Roblox and bought by somebody.

	ORDER IS NOT LOAD BEARING TO `packFor`, WHICH IT WAS THE WHOLE STORY UNTIL THE SHOP EXISTED.
	`packFor` scans for the smallest rung that covers a gap rather than walking the list in order,
	so nothing about an offer cares where a rung sits here. The SHOP's Currency tab does: it draws
	this table in order and paints `UIAssets.CashTiers[n]` on the nth rung. So a rung inserted in
	the middle is still a one line edit HERE, and it costs one more glyph there. Uploading it is
	written up in `assets/ui/gvesster/tiers/README.md`; until it is, every rung from the new one up
	wears the glyph of the rung below it and the top of the ladder repeats. ]]
CashConfig.Packs = {
	{ Key = "Cash1", Name = "Pocket Change", Cash = 15_000, Price = 29, Minutes = 10, FloorCars = 1, CapCars = 0.5, ProductId = 0 },
	{ Key = "Cash2", Name = "Stack of Cash", Cash = 150_000, Price = 89, Minutes = 30, FloorCars = 2, CapCars = 1.5, ProductId = 0 },
	{ Key = "Cash3", Name = "Cash Briefcase", Cash = 1_500_000, Price = 249, Minutes = 90, FloorCars = 5, CapCars = 4, ProductId = 0 },
	{ Key = "Cash4", Name = "Armored Truck", Cash = 15_000_000, Price = 599, Minutes = 240, FloorCars = 12, CapCars = 10, ProductId = 0 },
	{ Key = "Cash5", Name = "Bank Vault", Cash = 150_000_000, Price = 1_399, Minutes = 600, FloorCars = 30, CapCars = 25, ProductId = 0 },
	{ Key = "Cash6", Name = "Bank Heist", Cash = 1_500_000_000, Price = 2_999, Minutes = 1_440, FloorCars = 70, CapCars = 60, ProductId = 0 },
} :: { Pack }

--[[ === A PACK IS WORTH YOUR TIME, NOT A FIXED SUM — 2026-10-15 ===
	WAS: each rung paid a fixed `Cash`, $15K to $1.5B. The ladder this header argues was written
	against an older economy (its "top of world 4 car at $3.3B" is long gone: `BalanceConfig.Values`
	now runs $600 to $124M), and a fixed sum is a fortune at one end of the game and nothing at the
	other.
	IS (the owner: "make the cash devproducts scale with player progress"): a rung pays `Minutes` of
	the player's LIVE income (`cashFor`), the genre's "an hour of your earnings", because income is
	already the sum of their world, their cars, their upgrades and their storey. Two guards:
	  FLOOR  `FloorCars` x the cheapest car in their best unlocked world, so an empty lot (no income
	         yet, or every car in the inventory) still buys something worth having.
	  CAP    `CapCars` x the dearest car in that world, so a late lot's 24 hours cannot leap a whole
	         world in one purchase.
	The Robux PRICE cannot change per player (a product's price is fixed on Roblox), so the AMOUNT is
	what scales, and it is shown by name ("Bank Heist") with the live figure on our own screens:
	Roblox's purchase window only ever shows the product's name. The server works the amount out
	again at the receipt (`CashService.grantCash`) from the attributes it wrote itself, so a client
	cannot move it. `Scaling.Enabled = false`: the fixed `Cash` column, exactly as before. ]]
CashConfig.Scaling = { Enabled = false }

--[[ === FIXED, PER WORLD: THE OWNER'S OWN NUMBERS (2026-10-15, later the same day) ===
	WAS: the scaling just above, minutes of the player's income floored and capped by world.
	IS (the owner: not dynamic, set "per world"): each rung pays a FIXED amount for the player's
	HIGHEST UNLOCKED world (`WorldConfig.highestUnlocked`), not the world they are standing in, so a
	World 3 player buying while driving World 1 still gets World 3's figure. The table is the owner's,
	from the Cash Pack Prices page (https://claude.ai/artifact/1THZazqAAzKob5U71FNDbq). World 5
	repeats World 4 because that is what the owner set. A gifted pack pays the RECIPIENT's world
	(`GiftService` hands it to `CashService.grantCash`, which calls `cashFor` for them).

	BANK HEIST IS REMOVED, confirmed by Dylan the same evening. Its shop card came off that morning
	because the lone card under Armored Truck made the list look uneven (`ShopConfig.OffShelf`), and
	the owner's $1 in every world meant "not sold". Left as it was, it would have been exactly the
	rung `packFor` offers somebody $1 short, for 2,999 Robux. So it is never offered and never a
	gift. It stays REGISTERED (`DevProductsHandler`), because a purchase window opened before this
	shipped can still send a receipt, and that receipt pays Bank Vault's figure rather than $1.

	Precedence in `cashFor`: `Scaling` when it is on, else this table, else the fixed `Cash` column.
	`ByWorld.Enabled = false` with `Scaling` off is the fixed column, exactly as before. ]]
CashConfig.ByWorld = { Enabled = true }

local BY_WORLD: { [string]: { number } } = {
	--          World 1     World 2       World 3        World 4          World 5
	Cash1 = { 20_000, 400_000, 5_000_000, 65_000_000, 65_000_000 },
	Cash2 = { 60_000, 1_200_000, 15_000_000, 200_000_000, 200_000_000 },
	Cash3 = { 150_000, 3_500_000, 45_000_000, 600_000_000, 600_000_000 },
	Cash4 = { 350_000, 9_000_000, 110_000_000, 1_500_000_000, 1_500_000_000 },
	Cash5 = { 800_000, 22_000_000, 300_000_000, 4_000_000_000, 4_000_000_000 },
	--- Retired (above). The owner's figure is $1; a stray receipt is paid at Bank Vault's.
	Cash6 = { 800_000, 22_000_000, 300_000_000, 4_000_000_000, 4_000_000_000 },
}
local RETIRED = { Cash6 = true }

for _, pack in CashConfig.Packs do
	pack.CashByWorld = BY_WORLD[pack.Key]
	pack.Retired = RETIRED[pack.Key] == true
end

--- Round to two significant figures ($48,213 -> $48,000), so a pack reads as a price, not a reading.
local function round2(amount: number): number
	if amount < 100 then
		return math.max(1, math.floor(amount))
	end
	local step = 10 ^ (math.floor(math.log10(amount)) - 1)
	return math.floor(amount / step) * step
end

--[[ What `pack` pays `player` right now (header just above). Pure apart from reading the player:
	the income attributes the server publishes (`GarageConfig.Hud.TipRate`, tips per hour, and
	`RateAttribute`, passive dollars per second) and their highest unlocked world. Same answer on the
	server, which pays it, and on the client, which shows it. ]]
function CashConfig.cashFor(pack: Pack, player: Player?): number
	if not (CashConfig.Scaling.Enabled and player) then
		--- `ByWorld`: the owner's figure for their highest unlocked world (world 1 without a player).
		local column = CashConfig.ByWorld.Enabled and pack.CashByWorld
		if column then
			return column[math.clamp(WorldConfig.highestUnlocked(player), 1, #column)]
		end
		return pack.Cash
	end
	local tips = player:GetAttribute(GarageConfig.Hud.TipRate.Attribute)
	local passive = player:GetAttribute(GarageConfig.RateAttribute)
	local perHour = (if type(tips) == "number" then tips else 0) + (if type(passive) == "number" then passive * 3600 else 0)
	local world = math.clamp(WorldConfig.highestUnlocked(player), 1, #BalanceConfig.Values)
	local cars = BalanceConfig.Values[world]
	local floor = cars[1] * pack.FloorCars
	local cap = cars[#cars] * pack.CapCars
	return round2(math.clamp(perHour * pack.Minutes / 60, floor, math.max(floor, cap)))
end

for _, pack in CashConfig.Packs do
	pack.ProductId = GameIds["products." .. pack.Key] or 0
end

-- === Picking one ============================================================

--- Is there anything here that can actually be bought? False before the first `rbxsync sync`, and
--- false with the feature switched off, which every caller reads as "refuse the way we always did".
function CashConfig.sellable(): boolean
	if not CashConfig.Enabled then
		return false
	end
	for _, pack in CashConfig.Packs do
		if pack.ProductId ~= 0 and not pack.Retired then
			return true
		end
	end
	return false
end

--[[ The rung to offer somebody who is `shortfall` dollars short.

	THE CHEAPEST ONE THAT CLOSES THE GAP, falling back to the biggest rung on the board when nothing
	closes it. The input is the GAP and never the price, which is what stops a modal asking for a
	billion just because a billion was on the sign.

	Rungs with no product id are skipped rather than offered, so a half synced ladder degrades to
	the rungs that do exist instead of prompting against product 0. So are retired rungs. ]]
function CashConfig.packFor(shortfall: number, player: Player?): Pack?
	if not CashConfig.sellable() then
		return nil
	end

	local wanted = math.max(1, math.ceil(shortfall or 0))
	local best: Pack? = nil
	local biggest: Pack? = nil

	for _, pack in CashConfig.Packs do
		if pack.ProductId ~= 0 and not pack.Retired then
			--- What the rung pays THIS player (`cashFor`); the fixed column without one.
			local cash = CashConfig.cashFor(pack, player)
			if not biggest or cash > CashConfig.cashFor(biggest, player) then
				biggest = pack
			end
			if cash >= wanted and (not best or cash < CashConfig.cashFor(best, player)) then
				best = pack
			end
		end
	end

	return best or biggest
end

--- The rung a receipt belongs to. `DevProductsHandler` registers by product id, so this is what
--- turns one back into an amount without a second table to keep in step.
function CashConfig.packOf(productId: number): Pack?
	for _, pack in CashConfig.Packs do
		if pack.ProductId ~= 0 and pack.ProductId == productId then
			return pack
		end
	end
	return nil
end

-- === Opening the modal ======================================================

--[[ Seconds between one player's offers, and it is deliberately an order of magnitude longer than
	the purchase cooldowns on the four sites that call it (`CarDealConfig.Prompt.Cooldown` is 0.5,
	`UpgradeConfig.PurchaseCooldown` and `WorldConfig.PurchaseCooldown` are both 0.35).

	Those numbers guard a profile write and are sized for one. This guards a MODAL. A held proximity
	prompt, or a leant on button, would otherwise throw Roblox's purchase window up twice a second
	at somebody whose only crime is being poor, which is the most obnoxious thing this feature could
	possibly do. Eight seconds is long enough that a second window is always a second decision. ]]
CashConfig.PromptCooldown = 8

--[[ How long an open modal is assumed to still be open, seconds.

	`PromptProductPurchaseFinished` takes the flag down in every ordinary case, and this is the
	backstop for the case where it does not: a client that crashed or left with the window up would
	otherwise hold its own top up offer shut for the rest of the session. Generous, because the cost
	of being wrong in this direction is one extra modal and the cost in the other is a dead feature. ]]
CashConfig.PromptTimeout = 180

--[[ How long a receipt will wait for `GarageService` to have this player's profile in hand.

	IT IS A WAIT AND NOT A CHECK, because the caller is `ProcessReceipt` and the money has already
	changed hands. `GarageService.addCash` is a silent no op against a profile it has not cached
	yet, and a receipt landing on the same frame as the join can reach it first. Running out of this
	makes the grant THROW, which `PurchaseIdCheckAsync` turns into `NotProcessedYet` so Roblox
	retries later. The failure mode is a delay, never cash a player paid for and did not get. ]]
CashConfig.GrantWait = 30

-- Rebase fixed cash packs with the world's economy. Robux prices and product IDs stay fixed.
-- Keep each pack non-decreasing across worlds, including the existing shared W4/W5 tier.
for _, pack in CashConfig.Packs do
 local column = pack.CashByWorld
 if column then
  local previous = 0
  for world, amount in column do
   local raw = amount * (BalanceConfig.CurrencyScaleByWorld[world] or 1)
   local step = 10 ^ math.max(0, math.floor(math.log10(math.max(raw, 1))) - 1)
   column[world] = math.max(previous, math.round(raw / step) * step)
   previous = column[world]
  end
 end
end
return CashConfig
