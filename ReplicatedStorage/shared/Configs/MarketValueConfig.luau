--[[
	MarketValueConfig
	-----------------
	WHAT ONE CAR IS WORTH, as one number that everything which prices a car reads: the sell lot, the
	dealership's valuation, a customer's tip, and a buyer's offer. Pure — it takes a car's facts and
	returns dollars, and it reads no profile and writes nothing, so a client can run it to draw a
	price and the server can run it to pay one and the two cannot disagree.

	=== WHY THIS IS NOT JUST `GarageConfig.valueOf` ===========================================

	`valueOf` prices a MODEL: a tier and a mutation, i.e. what every red Charged Camaro is worth. That
	was the whole answer while a car was only its key. The dealership rework (2026-09-28) gives each
	car state of its own — first the condition it banked in, later whatever the customization bay
	does to it — and two copies of one model stop being worth the same. This is the function of the
	CAR, and `valueOf` is the base it multiplies.

	The alternative is each caller applying the condition itself, and that is the mistake
	`GarageConfig.rateOf` was written to prevent once already: a multiplier applied in three places
	out of four is a buyer offering a price the sell lot disagrees with.

	=== WHAT IS AND IS NOT IN IT YET ===========================================================

	  • TIER and MUTATION, through `GarageConfig.valueOf`, unchanged.
	  • CONDITION, the fraction of HP the run car had left when it banked (`GetawayService` reads
	    it off the car; `GarageService` stores it in `Garage.CarData`).
	  • PARTS, since 2026-09-28: whatever the customization bay has fitted (`CustomizeConfig`), as a
	    multiplier on top of condition. The record was a table from the start so they could join it
	    without any caller changing shape, and none did. Cosmetics are not in yet.

	`Enabled = false` prices every car as its model, i.e. exactly `GarageConfig.valueOf` — the
	honest A/B for whether condition is carrying its weight, and the old behaviour, exactly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ The base price of a model. A CONFIG requiring a config: `valueOf` is pure arithmetic over the
	income ladder, and pulling it in costs no dependency on any service. ]]
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
--[[ What fitted parts are worth. A CONFIG requiring a config, and it has to be this direction:
	`CustomizeConfig` requires nothing, and the workshop's prices are worked out by `WorkshopService`
	calling this file, never the other way round. ]]
local CustomizeConfig = require(ReplicatedStorage.shared.Configs.CustomizeConfig)

local MarketValueConfig = {}

MarketValueConfig.Enabled = true

-- === Condition ==============================================================
MarketValueConfig.Condition = {
	--[[ What a car with no recorded condition is in: full. Every car banked before condition
		existed has no record (`GarageConfig.Keys.CarData`), and so does anything handed over rather
		than driven home — a market deal, a random pull, an admin grant. A car nobody crashed is a
		car in perfect condition, which is the only reading that does not quietly devalue a
		collection the moment this file ships. ]]
	Default = 1,

	--[[ What a car at ZERO condition is still worth, as a fraction of a perfect one. The multiplier
		runs in a straight line from this at 0 to 1 at full:

		    factor = Floor + (1 - Floor) * condition

		0.5 IS A TASTE CALL, not a measurement. Its job is to make a battered bank read as worth less
		without making it worthless: a car that limped into the truck on its last sliver of HP was
		still a car you got away with, and the "never nothing" rule `GarageService.awardCar` carries
		for the run applies to its price too. Lower makes crashing on the way home cost more and
		makes the workshop's repair (`CustomizeConfig.Repair`) worth more; 0 would price a wreck at nothing,
		which reads as a bug on the offer screen. ]]
	Floor = 0.5,
}

--[[ Clamp a stored condition into [0, 1], with the default for anything that is not a number.
	NaN is tested explicitly: it fails every comparison and would sail through the clamp. ]]
function MarketValueConfig.conditionOf(raw: unknown): number
	if type(raw) ~= "number" or raw ~= raw then
		return MarketValueConfig.Condition.Default
	end
	return math.clamp(raw, 0, 1)
end

-- The multiplier a condition applies to a model's base price. See `Condition.Floor` for the line.
function MarketValueConfig.conditionFactor(condition: unknown): number
	if not MarketValueConfig.Enabled then
		return 1
	end
	local floor = MarketValueConfig.Condition.Floor
	return floor + (1 - floor) * MarketValueConfig.conditionOf(condition)
end

--[[ Whole dollars one car is worth. `data` is its `Garage.CarData` record, or nil for a car that has
	none — which is most of them, and means defaults.

	Rounded here and not by callers, so a price drawn on a sign and a price paid by a buyer are the
	same integer rather than the same float rounded twice. ]]
function MarketValueConfig.valueOf(tier: number?, mutation: string?, data: { [string]: any }?): number
	local base = GarageConfig.valueOf(tier, mutation)
	local condition = if type(data) == "table" then data.Condition else nil
	local parts = if type(data) == "table" then data.Parts else nil
	--- Parts ride on top of condition rather than beside it, so a battered car's new engine is worth
	--- less than a clean one's — the same engine in a worse car. `CustomizeConfig.ValuePerLevel`.
	return math.round(base * MarketValueConfig.conditionFactor(condition) * CustomizeConfig.partsFactor(parts))
end

--- The same, from a car ID or key and its record. A body off the roster is worth nothing, the same
--- answer `GarageConfig.valueOfCollection` gives it.
function MarketValueConfig.valueOfId(id: string, data: { [string]: any }?): number
	local body, _paint, mutation = GarageConfig.parseCarKey(id)
	return MarketValueConfig.valueOf(body and GarageConfig.TierOfBody[body], mutation, data)
end

--[[ A car's record as a CLIENT can know it: its condition and its parts, read off the two
	broadcasts the server keeps on its owner (`GarageConfig.ConditionAttribute`,
	`CustomizeConfig.PartsAttribute`). Every screen that prices a car goes through this, so a screen
	cannot remember one half of the record and forget the other — which is exactly what adding parts
	would otherwise have done to the two screens that only read condition. A nil owner (they left)
	answers the empty record, i.e. the model's price. ]]
function MarketValueConfig.broadcastRecord(owner: Player?, id: string): { [string]: any }
	if not owner then
		return {}
	end
	local conditions = GarageConfig.decodeConditions(owner:GetAttribute(GarageConfig.ConditionAttribute))
	local parts = CustomizeConfig.decodeParts(owner:GetAttribute(CustomizeConfig.PartsAttribute))
	return { Condition = conditions[id], Parts = parts[id] }
end

return MarketValueConfig
