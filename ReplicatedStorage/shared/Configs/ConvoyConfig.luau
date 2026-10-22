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
ConvoyConfig.Chance = 1 -- TEMP TEST, was 0.25
--- Seconds into the run it arrives, rolled per run. Late enough that the road is up to speed.
ConvoyConfig.After = { 6, 8 } -- TEMP TEST, was { 40, 110 }

-- === What ===================================================================

--- One car per entry, front of the line first. Rare, Epic, Epic, Legendary.
ConvoyConfig.Bands = { 3, 4, 4, 5 }
--- The lowest band a missing one may fall back to. Never Common (1) or Uncommon (2).
ConvoyConfig.MinBand = 3

-- === How it drives ==========================================================

--- Studs behind the player the front car appears, and between consecutive cars along the road.
--- Cars alternate between two lanes, so two in one lane are `2 * Spacing` apart: room to land a steal.
ConvoyConfig.Behind = 120
ConvoyConfig.Spacing = 60
--- Speed while catching up, as a share of the player's cruise. Above 1 or it never passes.
ConvoyConfig.PassSpeed = 1.3
--- Once a car is this far ahead of the player it settles to `SettleSpeed` of their cruise and drives
--- on as ordinary traffic, so the player can catch it and steal it.
ConvoyConfig.SettleAhead = 90
ConvoyConfig.SettleSpeed = 0.85
--- A convoy car this many studs behind the player, in their lane, moves over or holds at their speed.
ConvoyConfig.YieldGap = 100
--[[ Passing slower traffic. A convoy car with a slower car within `Look` studs ahead in its lane
	moves over to a neighbouring lane (never the player's) that has no slower car within `Clear`.
	Without it the line sat behind cars the player had already passed and was never seen.

	NEVER STUCK FOR LONG. Still blocked after `Patience` seconds, it takes any neighbour with room
	alongside (traffic further up that lane or not), or the car in its way pulls over for it. Still
	blocked after `GhostAfter` while behind the player, it drives through the blocker: out of the chase
	camera's view, and far better than the player never seeing the convoy. ]]
ConvoyConfig.Overtake = { Look = 140, Clear = 90, Patience = 1, GhostAfter = 2.5 }
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
