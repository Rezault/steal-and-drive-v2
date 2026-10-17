-- Approved balance constants. Currency uses base values, before condition and parts.
local BalanceConfig = {
	["Version"] = 9,
	-- Driving pays 30% of the previous rate; garage income and car values are independent.
	--[[ CUT AGAIN 2026-10-13 (punch list E1, Aleafo: "the earning you get from drives is screwing up
		the balancing"). WAS 4000 / 400. Worked out on the punch list: a 1-minute World 1 drive paid
		~$980 (distance $765 + near misses ~$90 + traps ~$125) against a ~$1,106 average stolen car, so
		the drive was worth nearly the car. TARGET: a drive pays about a third of the car you steal in
		it. NOW 12000 / 800: $0.05/stud, near misses halved -> ~$350 a minute, ratio ~0.32 : 1. Every
		world scales off `roadValue(world)`, so the ratio holds everywhere. Softer if it feels stingy:
		8000 / 600 (~$560/min, ~0.5 : 1). ]]
	["DrivingCashDivisor"] = 12000,
	["NearMissCashDivisor"] = 800,
	-- Rebased 2026-10-16 around the smaller gates; World 1 is unchanged.
	-- World 3 rarity premiums widened Oct 16; rare finds can outvalue early World 4 cars.
	["Values"] = { { 600, 6000, 9000, 12000, 16000, 20000, 25000, 30000, 35000, 40000 }, { 45000, 52500, 60000, 75000, 93750, 112500, 150000, 175000, 250000, 325000 }, { 220000, 250000, 290000, 330000, 400000, 480000, 600000, 750000, 1200000, 1600000 }, { 650000, 750000, 850000, 1050000, 1350000, 1600000, 2150000, 2700000, 3500000, 4300000 }, { 6000000, 7000000, 8000000, 10000000, 12500000, 15000000, 20000000, 25000000, 32500000, 40000000 } },
	-- Approved Oct 16: World 2 reduced from 100k to 85k for a slightly quicker first unlock.
	["WorldCosts"] = { 0, 85000, 6000000, 35000000, 200000000 },
	["WorldWeightsByAge"] = { 1, 0.4, 0.15, 0.05, 0.02 },
	-- Rebased 2026-10-16: prices follow earning power; later levels remain more expensive.
	-- Upgrade effects and world requirements are retained.
	["UpgradePrices"] = {
	["Customers"] = { 1500, 15000, 300000, 500000 },
	["Jump"] = { 2000, 75000, 250000, 1000000, 10000000 },
	["Luck"] = { 1000, 4000, 110000, 380000, 500000, 1300000, 1600000, 4300000, 15000000, 40000000 },
	["Floor2"] = { 500000 },
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
BalanceConfig.RoadReferenceValues = { 600, 19500, 60000, 230000, 1900000 }
function BalanceConfig.roadValue(world: number?): number
 return BalanceConfig.RoadReferenceValues[math.clamp(math.floor(world or 1), 1, 5)]
end
-- Monetary scales only: existing wallets are deliberately not converted.
BalanceConfig.CurrencyScaleByWorld = { 1, 0.75, 0.25, 0.10810810810810811, 0.1 }
-- Quest rewards follow the currency scale, independently of the compressed starter-car curve.
BalanceConfig.QuestReferenceValues = { 600, 45000, 150000, 650000, 6000000 }
function BalanceConfig.questValue(world: number?): number
 return BalanceConfig.QuestReferenceValues[math.clamp(math.floor(world or 1), 1, 5)]
end
return BalanceConfig


