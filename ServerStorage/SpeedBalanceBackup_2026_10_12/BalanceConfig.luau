-- Approved balance constants. Currency uses base values, before condition and parts.
local BalanceConfig = {
	["Version"] = 4,
	-- Ten values per world. Existing endpoints and World 1 prices are retained.
	-- Later-world intermediate prices preserve baseline expected spawn value (within 0.1%).
	["Values"] = { { 600, 1000, 1300, 1700, 2800, 4600, 7500, 12000, 19000, 25000 }, { 26000, 29500, 35100, 42800, 53000, 66400, 84100, 108000, 139000, 180000 }, { 240000, 271000, 321000, 390000, 482000, 602000, 761000, 971000, 1250000, 1620000 }, { 2150000, 2430000, 2870000, 3480000, 4280000, 5340000, 6740000, 8570000, 11000000, 14300000 }, { 19000000, 21400000, 25300000, 30600000, 37500000, 46700000, 58800000, 74700000, 95800000, 124000000 } },
	--- World 2 stays 100k (the owner, 2026-10-09): the rarer road (`RungWeights`) is what slows world 1.
	["WorldCosts"] = { 0, 100000, 8000000, 130000000, 1700000000 },
	["WorldWeightsByAge"] = { 1, 0.4, 0.15, 0.05, 0.02 },
	--[[ RE-PRICED 2026-10-08 against what the showroom actually earns in the world each level unlocks
		in (`CustomerConfig.Tip.ByWorld` has the simulation). WAS:
		    Luck      1k 4k | 20k 75k | 250k 900k | 3M 10M | 30M 90M
		    Customers 1.5k 15k | 120k | 1.2M
		    Jump      2k | 25k | 250k | 2.5M | 25M
		    Floor2    450k
		which was one to seven MINUTES of income everywhere past world 1 (Luck's last level: two
		minutes of a world 5 lot; Jump's: thirty seconds). NOW each level past world 1 is roughly 15-40
		minutes of that world's lot, so an upgrade is a goal again. World 1's own levels are unchanged:
		world 1 is on target and its levels are the first purchases a new player makes. ]]
	["UpgradePrices"] = {
	["Luck"] = { 1000, 4000, 500000, 1500000, 8000000, 20000000, 60000000, 150000000, 600000000, 1500000000 },
	["Customers"] = { 1500, 15000, 2000000, 20000000 },
	["Jump"] = { 2000, 250000, 5000000, 60000000, 600000000 },
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
