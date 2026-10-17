-- Approved balance constants. Currency uses base values, before condition and parts.
local BalanceConfig = {
	["Version"] = 2,
	--- World 1 grew a rung (2026-10-09, the Maybach, `WorldConfig`): it takes the M5's old 19,000 and
	--- the M5 moves up to 25,000 — under world 2's first car (26,000), so the worlds still don't overlap.
	["Values"] = { { 600, 1000, 1300, 1700, 2800, 4600, 7500, 12000, 19000, 25000 }, { 26000, 36000, 50000, 69000, 95000, 131000, 180000 }, { 240000, 330000, 455000, 625000, 860000, 1180000, 1620000 }, { 2150000, 2950000, 4050000, 5550000, 7600000, 10400000, 14300000 }, { 19000000, 26000000, 35500000, 48500000, 66300000, 90600000, 124000000 } },
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
	--[[ RARE CARS ARE RARE AGAIN — 2026-10-09. The owner, after a test: "rare cars show up wayyy too
		often ... it doesn't give the player dopamine ... they show up like every run". The arithmetic
		agrees: a car spawns every 0.9-1.7s (`TrafficConfig.SpawnInterval`), so a ~1.5-minute run rolls
		~85 cars, and at the old weights world 1's top car (1%) turned up in 57% of runs and its two
		LEGENDARY cars (4% together) about three times a run. Every later world's top car was 4%.

		WAS  W1 { 23, 19, 15, 13, 11, 9, 6, 3, 1 }      W2-5 { 27, 22, 18, 13, 10, 6, 4 }
		NOW  per-spawn percentages, chosen as "how many runs between sightings" (85 rolls a run):
		     W1 top car 0.1%  (seen ~1 run in 12)   2nd 0.25% (~1 in 5)   EPIC 0.8% (~1 in 2)
		     W2-5 top car 0.12%, 2nd 0.35%, then 1.5 / 5 / 15 / 33 / 45.
		A legendary is a run you remember now, and the rare-car banner (`TrafficConfig.Announce`) is
		an event. Luck still tilts toward the top as before (`TrafficConfig.rungWeight`), so the Luck
		upgrade is worth more than it was. Pair with `TrafficConfig.StartWeightsByWorld`, which had to
		come down with these: its old top-rung START weights were higher than these END weights.

		CALIBRATED, NOT GUESSED: a model of "bank the best of ~20 cars you could reach, 1.5-minute
		runs" reproduced the testers' 11-13 minutes to world 2 on the OLD weights.

		=== MUCH RARER, SAME PRICE — 2026-10-09 (same day) ===
		The first cut (W1 top 0.1%, W2-5 top 0.12%) came with world 2 raised to 150k; the owner kept
		100k and asked for the rare cars "much rarer" instead, so rarity alone carries the pacing. NOW,
		as runs between sightings (85 rolls a run):
		     W1   M5 0.05% (~1 run in 24)   Mustang 0.1% (~1 in 12)   EPIC 0.25% (~1 in 5)
		          then 0.7 / 2.5 / 8 / 23.4 / 29 / 36
		     W2-5 top 0.06% (~1 in 20)   2nd 0.15% (~1 in 8)   then 0.5 / 2.5 / 13 / 34 / 49.79
		The same model gives ~22 minutes to world 2 at 100k — the middle of Aleafo's 18-30. ]]
	--- The Maybach (2026-10-09) takes the M5's 0.05% (~1 run in 24); the M5 drops to 0.02% (~1 in 60).
	["RungWeights"] = { { 36, 29, 23.4, 8, 2.5, 0.7, 0.25, 0.1, 0.05, 0.02 }, { 49.79, 34, 13, 2.5, 0.5, 0.15, 0.06 }, { 49.79, 34, 13, 2.5, 0.5, 0.15, 0.06 }, { 49.79, 34, 13, 2.5, 0.5, 0.15, 0.06 }, { 49.79, 34, 13, 2.5, 0.5, 0.15, 0.06 } },
	["FromTiles"] = { { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0, 0 } },
	["OfflineGateFraction"] = 0.25,
	["InsuranceLimit"] = 3,
	["InsuranceCondition"] = 0.25,
}
function BalanceConfig.firstValue(world: number?): number
 return BalanceConfig.Values[math.clamp(math.floor(world or 1), 1, 5)][1]
end
return BalanceConfig
