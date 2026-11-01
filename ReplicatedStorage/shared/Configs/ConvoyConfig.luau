--[[
	ConvoyConfig
	------------
	THE CONVOY (2026-10-22). Now and then a run gets a rare group of four desirable cars that come
	up from BEHIND the player, overtake in a staggered line, and settle into the road ahead where
	they can be stolen the normal way (and, as always, only kept by driving one home).

	WHO DECIDES. The server, like every other car (`EncounterConfig`): `EncounterService` rolls
	whether this run has a convoy and when, picks the four cars out of this run's world, and issues
	them under ordinary tokens, so a steal and a bank treat a convoy car exactly like any other.
	`TrafficController` only decides where they drive.

	ALWAYS WORTH NOTICING. One car per entry in `Bands`, from that rarity band of the run's world
	(3 Rare, 4 Epic, 5 Legendary — `TrafficConfig` bands, the ones `CarRarity` prints), never Common
	or Uncommon. A world with no car in a band falls back one band at a time, never below `MinBand`.
	No body twice where the band has enough to choose from.

	THE PLAYER'S LANE IS KEPT CLEAR. Traffic never reacts to the player, because ordinary traffic is
	always slower and spawns ahead. A convoy car is the one thing on the road that catches up, so
	while it is still behind or beside the player it moves out of their lane, and holds at their
	speed if it cannot (`YieldGap`). A convoy that rear-ended the player would be charged to them as
	a crash.
]]

local ConvoyConfig = {}

ConvoyConfig.Enabled = true

-- === When ===================================================================

--- Share of (non-tutorial) runs that get a convoy. "Rare": most runs do not.
ConvoyConfig.Chance = 0.25
--- Seconds into the run it arrives, rolled per run. Late enough that the road is up to speed.
ConvoyConfig.After = { 40, 110 }
--- Persisted per player across runs, worlds and rejoins. Starts at issue, confirmed at appearance.
ConvoyConfig.Cooldown = 10 * 60
ConvoyConfig.ProfileKey = "ConvoyNextAt"
ConvoyConfig.ShownRemote = "EncounterConvoyShown"

-- === What ===================================================================

--- One car per entry, front of the line first. Rare, Epic, Epic, Legendary.
ConvoyConfig.Bands = { 3, 4, 4, 5 }
--- The lowest band a missing one may fall back to. Never Common (1) or Uncommon (2).
ConvoyConfig.MinBand = 3

-- === How it drives ==========================================================

--- Studs behind the player the front car appears, and the stagger between consecutive cars.
--- The four cars use four different non-player lanes, so the whole convoy arrives as one visible beat.
ConvoyConfig.Behind = 70
ConvoyConfig.Spacing = 32
--[[ Speed while catching up, as a share of how fast the player is ACTUALLY going (or their cruise,
	whichever is higher). Above 1 or it never passes. 2026-10-22: WAS 1.3 off cruise, which either
	never caught a player running past cruise or, when it did, was gone in a blink. ]]
ConvoyConfig.PassSpeed = 1.15
--[[ Once a car is `SettleAhead` studs in front it ESCORTS the player: `Escort.Speed` of their actual
	speed for `Escort.Seconds`, so the line stays in view, drifting slowly back towards them, which is
	the steal. After that (or once the player has passed it) it drives on at `SettleSpeed` of their
	cruise as ordinary traffic. ]]
ConvoyConfig.SettleAhead = 60
ConvoyConfig.Escort = { Speed = 0.95, Seconds = 12 }
ConvoyConfig.SettleSpeed = 0.85
--[[ A passing car that falls further behind than this (the player hit nitro) is moved back up to it.
	Behind the chase camera, so it is never seen, and it means a fast player cannot outrun the convoy
	before it has ever arrived. ]]
ConvoyConfig.CatchUp = 250
--[[ On its way in, a convoy car further than this behind the player drives through traffic (out of the
	chase camera's view, so the line always arrives). Closer, and once it has reached the player, it is
	solid and overtakes instead: a slower car within `Overtake.Look` in its lane and it changes lane,
	retrying every `Retry` seconds; still boxed in after `GiveUp` once it has arrived, it becomes
	ordinary traffic rather than sit there as a convoy car forever. 2026-10-23. ]]
ConvoyConfig.GhostBehind = 40
ConvoyConfig.Overtake = { Look = 80, Retry = 0.6, GiveUp = 3 }
--- Start matching the player inside this range; never close past `PlayerGap` in the same lane.
ConvoyConfig.YieldGap = 100
ConvoyConfig.PlayerGap = 36
--- Recycled once this far behind (the road's ordinary 120 would recycle it as it spawned).
ConvoyConfig.DespawnBehind = 450
--- Seconds the client may wait for a moment to put the convoy on the road (a hold, a flight)
--- before giving it up.
ConvoyConfig.SpawnWithin = 20

-- === Telling the player =====================================================

--- Published by `TrafficController` with the convoy's best body; `RareCarBannerController` shows it.
ConvoyConfig.Event = "ConvoyApproaching"
ConvoyConfig.Kicker = "RARE TO LEGENDARY"
ConvoyConfig.Title = "A CAR CONVOY IS APPROACHING!"

--- Non-player lanes, farthest first, so one four-car convoy spreads across a five-lane road.
function ConvoyConfig.formationLanes(playerLane: number, laneCount: number): { number }
	local out = {}
	for lane = 1, laneCount do
		if lane ~= playerLane then
			table.insert(out, lane)
		end
	end
	table.sort(out, function(a, b)
		local aDistance, bDistance = math.abs(a - playerLane), math.abs(b - playerLane)
		return if aDistance == bDistance then a < b else aDistance > bDistance
	end)
	return out
end

--[[ The convoy's cars out of one world's ladder (`TrafficConfig.tiersFor`): `{ rung, tier, body }` per
	entry of `Bands`, in order, or fewer if the world has nothing at or above `MinBand` for a slot.
	Pure, so `tests/convoy` can run it without a server. ]]
function ConvoyConfig.pick(rng: Random, tiers: { any }): { { rung: number, tier: any, body: string } }
	local used, out = {}, {}
	for _, want in ConvoyConfig.Bands do
		local fresh, any = {}, {}
		for band = want, ConvoyConfig.MinBand, -1 do
			for rung, tier in tiers do
				if tier.Band == band then
					for _, body in tier.Bodies or {} do
						table.insert(any, { rung = rung, tier = tier, body = body })
						if not used[body] then
							table.insert(fresh, any[#any])
						end
					end
				end
			end
			if #any > 0 then
				break
			end
		end
		local pool = if #fresh > 0 then fresh else any
		if #pool > 0 then
			local choice = pool[rng:NextInteger(1, #pool)]
			used[choice.body] = true
			table.insert(out, choice)
		end
	end
	return out
end

return ConvoyConfig
