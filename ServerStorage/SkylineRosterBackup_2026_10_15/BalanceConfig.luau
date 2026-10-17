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
	["Values"] = { { 600, 4000, 6000, 8000, 10500, 13500, 16500, 19500, 22500, 25000 }, { 26000, 29500, 35100, 42800, 53000, 66400, 84100, 108000, 139000, 180000 }, { 240000, 271000, 321000, 390000, 482000, 602000, 761000, 971000, 1250000, 1620000 }, { 2150000, 2430000, 2870000, 3480000, 4280000, 5340000, 6740000, 8570000, 11000000, 14300000 }, { 19000000, 21400000, 25300000, 30600000, 37500000, 46700000, 58800000, 74700000, 95800000, 124000000 } },
	--- World 2 stays 100k (the owner, 2026-10-09): the rarer road (`RungWeights`) is what slows world 1.
	["WorldCosts"] = { 0, 100000, 8000000, 130000000, 1700000000 },
	["WorldWeightsByAge"] = { 1, 0.4, 0.15, 0.05, 0.02 },
	-- Approved 2026-10-15: moderate later-level cost reductions for Luck, Customers and Jump.
	-- Early World 1 prices, upgrade effects, world requirements and Floor2 at 2.5M are retained.
	["UpgradePrices"] = {
	["Luck"] = { 1000, 4000, 350000, 1000000, 6000000, 15000000, 45000000, 110000000, 450000000, 1000000000 },
	["Customers"] = { 1500, 15000, 1500000, 12000000 },
	["Jump"] = { 2000, 175000, 3500000, 40000000, 400000000 },
	["Floor2"] = { 2500000 },
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
return BalanceConfig
