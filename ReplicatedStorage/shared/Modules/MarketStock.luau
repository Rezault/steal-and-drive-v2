--[[
	MarketStock  (shared)
	---------------------
	WHAT IS ON THE MARKET'S SHELF RIGHT NOW, and what each thing costs. No instances, no drawing:
	one pure function of the wall clock that both market pages read.

	It was `Pages/Market`'s private half until the kit migration needed a second screen to agree with
	it (`docs/NewUI-Migration-Plan.md`, "Shared logic"). A client deriving its own shelf is fine. TWO
	clients deriving DIFFERENT shelves is not, and two copies of this arithmetic is how that happens.

	FOUR THINGS TO KNOW.

	1. THE STOCK IS DERIVED FROM THE CLOCK, NOT ROLLED AND STORED. The shop period is
	   `floor(os.time() / ResetSeconds)` and that number is the RNG seed, so the shelf is a pure
	   function of the wall clock. Three things fall out of it, and they are the same three that make
	   `GarageConfig`'s income work (see its header note 1): nothing has to be saved, nothing has to
	   be ticked, and every client in the server independently computes the SAME shelf. When a real
	   `MarketService` lands it can roll the stock the same way and the two will already agree.

	   A countdown drawn against `deadlineOf` is the other half of that: a page reads
	   `deadline - os.time()` rather than decrementing a counter, so an alt-tab, a lag spike or a
	   hung frame cannot make it drift.

	2. PRICES COME OFF THE GARAGE ECONOMY, IN THE GARAGE'S OWN UNITS. There is no price table here
	   and there must not be one: `GarageConfig` header note 3 explains why. A car costs `BuySeconds`
	   of its own income, exactly as it SELLS for `SellSeconds` of it, and the one invariant that
	   matters is that the first number is bigger than the second. See `BuySeconds`.

	3. THE POOL IS THE LIVE WORLD'S LADDER. `TrafficConfig.Tiers` is the world `WorldConfig` has
	   active, so a car re-tiered there is re-tiered, re-priced and re-graded here with no second
	   edit. It is also why `Slots` is small: eight cars is the whole pool.

	4. NOTHING HERE DECIDES A RARITY WORD OR A COLOUR. `Rarity` is carried through from the tier
	   because the roll already had it in hand; `Modules/CarRarity` is what turns a body into a word
	   and a colour, and the V2 page reads it from there.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)

local MarketStock = {}

--- One listing on the shelf. `Stock` and `Price` are the two fields the roll works out; the rest is
--- the tier it came off.
export type Listing = {
	Body: string,
	Tier: number,
	Rarity: string,
	Band: number,
	Weight: number,
	Stock: number,
	Price: number,
}

--[[ How many listings the shelf stocks.

	Four: a window small enough that what is in it feels chosen, and big enough that a bad rotation is
	not the whole shop. The old kit's `ScrollBar` thumb was drawn at a length that implies three or
	four rows of that size, which was the only hint that mockup gave and is why the shelf scrolls at
	all.

	IT USED TO BE FOUR OF 43 AND IS NOW FOUR OF EIGHT, because the shop sells the live world and a
	world is eight cars (`WorldConfig`). Half the world on the shelf at once is a much weaker rotation
	than it was; if the shop starts feeling like it has nothing new in it, this is the number, and the
	honest alternative is to stock the whole world and drop the rotation entirely. ]]
MarketStock.Slots = 4

--[[ Seconds between rotations. Fifteen minutes reads as "come back after a run" rather than as a
	daily chore, and the old mockup's own placeholder ("RESET IN: 2m 7s") is on this scale. ]]
MarketStock.ResetSeconds = 15 * 60

--[[ A car costs this many seconds of its own income.

	THE SAME UNIT `GarageConfig.Income.SellSeconds` IS IN, ON PURPOSE. Both sides of the trade are
	priced off `rateOf`, so the one thing that must never invert cannot: at 360 against SellSeconds'
	240, buying a car and banking it straight back always loses you 120 seconds of its income, and it
	stays true if `Income.Multiplier` ever changes, because that multiplier is inside `rateOf` and
	therefore inside both numbers.

	Read the other way it is the payback: a bought car earns its price back in six minutes and is free
	money after that, which is the sentence the shop is really selling. ]]
MarketStock.BuySeconds = 360

--[[ Units on the shelf, by rarity band: 5, 4, 3, 2, 1. The scarcity is the band's. A Supercar turns
	up as a single car you either take or lose, a beater turns up by the handful.

	KEYED BY BAND (1-5), NOT BY TIER. A tier is one car out of the live world now and there are eight
	of them in world 1, so `6 - tier` would stock the top four rungs identically and go negative the
	moment a world is bigger. `TrafficConfig` stamps the band a rung sits nearest onto every tier for
	exactly this. ]]
function MarketStock.stockForBand(band: number): number
	return math.max(1, 6 - band)
end

--[[ Every body the roster publishes, carrying the tier that priced it. Built once, from
	`TrafficConfig.Tiers` rather than from a list here, for the same reason `GarageConfig` derives its
	rate table from it: header note 3. ]]
local POOL: { Listing } = {}
do
	for _, tier in TrafficConfig.Tiers do
		for _, body in tier.Bodies or {} do
			table.insert(POOL, {
				Body = body,
				Tier = tier.Tier,
				-- `Body` is the car; `Rarity` is the band word its tier was graded against.
				Rarity = tier.Rarity or tier.Name,
				Band = tier.Band or 1,
				Weight = tier.Weight,
				Stock = 0,
				Price = 0,
			})
		end
	end
end

--- How many cars the shelf could ever draw from. A page writing an empty state wants to tell "the
--- roster is empty" apart from "this rotation is thin".
function MarketStock.poolSize(): number
	return #POOL
end

--- Which rotation the wall clock is in. The seed, and the only state this module has.
function MarketStock.periodNow(): number
	return math.floor(os.time() / MarketStock.ResetSeconds)
end

--- When a period ends, as an `os.time()`. A countdown is this minus now, recomputed rather than
--- counted down: header note 1.
function MarketStock.deadlineOf(period: number): number
	return (period + 1) * MarketStock.ResetSeconds
end

--[[ The shelf for a period. Deterministic in `period` alone.

	Weighted by the tier's own `Weight`, so the traffic ramp's rarity is the shop's rarity too and a
	Tier 5 listing is the same event on the shelf that it is on the road. Drawn without replacement,
	because the identity of a car is its body name (`GarageConfig.Banking`) and the same car twice is
	one wasted slot. ]]
function MarketStock.roll(period: number): { Listing }
	-- An LCG step off the period, so consecutive periods do not produce neighbouring seeds.
	local rng = Random.new((period * 1103515245 + 12345) % 2147483648)

	local remaining = table.clone(POOL)
	local picked: { Listing } = {}

	for _ = 1, math.min(MarketStock.Slots, #remaining) do
		local total = 0
		for _, candidate in remaining do
			total += candidate.Weight
		end

		local roll = rng:NextNumber() * total
		local index = #remaining
		for i, candidate in remaining do
			roll -= candidate.Weight
			if roll <= 0 then
				index = i
				break
			end
		end

		local entry = table.clone(table.remove(remaining, index))
		entry.Stock = MarketStock.stockForBand(entry.Band)
		entry.Price = math.round(GarageConfig.rateOf(entry.Tier) * MarketStock.BuySeconds)
		table.insert(picked, entry)
	end

	-- Best car at the top. A shop leads with the thing it wants you to want.
	table.sort(picked, function(a, b)
		if a.Tier ~= b.Tier then
			return a.Tier > b.Tier
		end
		return a.Body < b.Body
	end)

	return picked
end

--[[ "1h 5m" / "12m 34s" / "47s", for a countdown label.

	Non-breaking spaces, because every caller draws this with `TextScaled`, which would sooner break a
	clock onto two tiny lines than pick a smaller font. Same rule, same fix, as
	`GarageConfig.displayName`. ]]
function MarketStock.formatDuration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	local secs = seconds % 60

	if hours > 0 then
		return `{hours}h\u{00A0}{minutes}m`
	elseif minutes > 0 then
		return `{minutes}m\u{00A0}{secs}s`
	end
	return `{secs}s`
end

return MarketStock
