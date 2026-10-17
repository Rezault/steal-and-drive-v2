-- Approved balance constants. Currency uses base values, before condition and parts.
local BalanceConfig = {
	["Version"] = 6,
	-- Driving pays 30% of the previous rate; garage income and car values are independent.
	--[[ CUT AGAIN 2026-10-13 (punch list E1, Aleafo: "the earning you get from drives is screwing up
		the balancing"). WAS 4000 / 400. Worked out on the punch list: a 1-minute World 1 drive paid
		~$980 (distance $765 + near misses ~$90 + traps ~$125) against a ~$1,106 average stolen car, so
		the drive was worth nearly the car. TARGET: a drive pays about a third of the car you steal in
		it. NOW 12000 / 800: $0.05/stud, near misses halved -> ~$350 a minute, ratio ~0.32 : 1. Every
		world scales off `firstValue(world)`, so the ratio holds everywhere. Softer if it feels stingy:
		8000 / 600 (~$560/min, ~0.5 : 1). ]]
	["DrivingCashDivisor"] = 12000,
	["NearMissCashDivisor"] = 800,
	-- Reviewed 2026-10-14: buffed World 1 middle values; starter/top and world gates retained.
	-- Later-world intermediate prices preserve baseline expected spawn value (within 0.1%).
	["Values"] = { { 600, 6000, 9000, 12000, 16000, 20000, 25000, 30000, 35000, 40000 }, { 60000, 70000, 80000, 100000, 125000, 150000, 200000, 250000, 325000, 400000 }, { 600000, 700000, 800000, 1000000, 1250000, 1500000, 2000000, 2500000, 3250000, 4000000 }, { 6000000, 7000000, 8000000, 10000000, 12500000, 15000000, 20000000, 25000000, 32500000, 40000000 }, { 60000000, 70000000, 80000000, 100000000, 125000000, 150000000, 200000000, 250000000, 325000000, 400000000 } },
	--- World 2 stays 100k (the owner, 2026-10-09): the rarer road (`RungWeights`) is what slows world 1.
	["WorldCosts"] = { 0, 100000, 8000000, 140000000, 1850000000 },
	["WorldWeightsByAge"] = { 1, 0.4, 0.15, 0.05, 0.02 },
	-- Approved 2026-10-15: moderate later-level cost reductions for Luck, Customers and Jump.
	-- Early World 1 prices, upgrade effects, world requirements and Floor2 at 2.5M are retained.
	["UpgradePrices"] = {
	["Luck"] = { 1000, 4000, 150000, 500000, 2000000, 5000000, 15000000, 40000000, 150000000, 400000000 },
	["Customers"] = { 1500, 15000, 400000, 500000 },
	["Jump"] = { 2000, 100000, 1000000, 10000000, 100000000 },
	["Floor2"] = { 750000 },
},
	["UpgradeWorlds"] = {
	["Luck"] = { 1, 1, 2, 2, 3, 3, 4, 4, 5, 5 },
	["Customers"] = { 1, 1, 2, 3 },
	["Jump"] = { 1, 2, 3, 4, 5 },
	["Floor2"] = { 2 },
},
	-- Ten independent rungs, two per rarity band. For Worlds 2-5, each band's
	-- combined end weight is unchanged: 49.79 / 47 / 2.5 / 0.65 / 0.06.
	-- World 1: a small Epic increase is funded from Civic. Legendary weights,
	-- starting odds, prices and world gates are unchanged (2026-10-09).
	["RungWeights"] = { { 35.85, 29, 23.4, 8, 2.5, 0.7, 0.35, 0.15, 0.05, 0.02 }, { 25, 24.79, 24, 23, 1.6, 0.9, 0.45, 0.2, 0.04, 0.02 }, { 25, 24.79, 24, 23, 1.6, 0.9, 0.45, 0.2, 0.04, 0.02 }, { 25, 24.79, 24, 23, 1.6, 0.9, 0.45, 0.2, 0.04, 0.02 }, { 25, 24.79, 24, 23, 1.6, 0.9, 0.45, 0.2, 0.04, 0.02 } },
	["FromTiles"] = { { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } },
	["OfflineGateFraction"] = 0.25,
	["InsuranceLimit"] = 3,
	["InsuranceCondition"] = 0.25,
}
function BalanceConfig.firstValue(world: number?): number
 return BalanceConfig.Values[math.clamp(math.floor(world or 1), 1, 5)][1]
end
-- Approved Oct15: worth and road rewards are independent. Preserve the prior driving nerf.
BalanceConfig.RoadReferenceValues = { 600, 26000, 240000, 2150000, 19000000 }
function BalanceConfig.roadValue(world: number?): number
 return BalanceConfig.RoadReferenceValues[math.clamp(math.floor(world or 1), 1, 5)]
end
return BalanceConfig


