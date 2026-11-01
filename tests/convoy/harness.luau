-- Self-check for ConvoyConfig.pick. Run: sh tests/convoy/run.sh (it supplies SOURCE).
local ConvoyConfig = assert(loadstring(SOURCE))()

-- Roblox's Random, enough of it: a seeded LCG.
local function rng(seed)
	local state = seed
	return {
		NextInteger = function(_, lo, hi)
			state = (state * 1103515245 + 12345) % 2147483648
			return lo + state % (hi - lo + 1)
		end,
	}
end

local function ladder(bands)
	local tiers = {}
	for band, bodies in bands do
		table.insert(tiers, { Band = band, Tier = band, Bodies = bodies })
	end
	return tiers
end

local failed, passed = 0, 0
local function check(ok, name)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name)
	end
end

check(ConvoyConfig.PlayerGap > 0 and ConvoyConfig.PlayerGap < ConvoyConfig.YieldGap, "rear safety gap sits inside the braking range")
check(ConvoyConfig.GhostBehind < ConvoyConfig.Behind, "the convoy spawns far enough back to drive through traffic on its way in")
check(ConvoyConfig.Overtake.Retry > 0 and ConvoyConfig.Overtake.GiveUp > ConvoyConfig.Overtake.Retry, "a boxed-in car tries to overtake before it gives up")

-- The entrance uses every non-player lane once, starting at the far edge.
for playerLane = 1, 5 do
	local lanes = ConvoyConfig.formationLanes(playerLane, 5)
	local seen = {}
	for _, lane in lanes do
		seen[lane] = true
	end
	check(#lanes == 4 and not seen[playerLane], "formation excludes the player lane")
	check(math.abs(lanes[1] - playerLane) >= math.abs(lanes[#lanes] - playerLane), "formation starts farthest away")
end

-- A full world: one per slot, bands in order, the two Epics never the same car.
for seed = 1, 200 do
	local picks = ConvoyConfig.pick(rng(seed), ladder({ { "C1" }, { "U1" }, { "R1", "R2" }, { "E1", "E2", "E3" }, { "L1" } }))
	local bands = {}
	for _, p in picks do
		table.insert(bands, p.tier.Band)
	end
	if seed == 1 then
		check(table.concat(bands, ",") == "3,4,4,5", "Rare, Epic, Epic, Legendary in order")
	end
	check(#picks == 4 and picks[2].body ~= picks[3].body, "no duplicate Epic when there are enough")
	for _, p in picks do
		check(p.tier.Band >= 3, "never Common or Uncommon")
	end
end

-- One Epic body only: the duplicate is allowed rather than dropping a car.
local one = ConvoyConfig.pick(rng(7), ladder({ { "C1" }, { "U1" }, { "R1" }, { "E1" }, { "L1" } }))
check(#one == 4 and one[2].body == "E1" and one[3].body == "E1", "single Epic repeats")

-- No Legendary in this world: that slot falls back to Epic, never lower.
local short = ConvoyConfig.pick(rng(3), { { Band = 1, Bodies = { "C1" } }, { Band = 3, Bodies = { "R1" } }, { Band = 4, Bodies = { "E1", "E2", "E3" } } })
check(#short == 4 and short[4].tier.Band == 4, "missing Legendary falls back to Epic")

-- Nothing at Rare or above: no convoy at all.
check(#ConvoyConfig.pick(rng(1), ladder({ { "C1" }, { "U1" } })) == 0, "no convoy from a Common/Uncommon world")

-- The rung is the tier's index in the ladder, which is what the client validates against.
local tiers = ladder({ { "C1" }, { "U1" }, { "R1" }, { "E1" }, { "L1" } })
for _, p in ConvoyConfig.pick(rng(5), tiers) do
	check(tiers[p.rung] == p.tier, "rung indexes the ladder")
end

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
	error("convoy checks failed")
end
