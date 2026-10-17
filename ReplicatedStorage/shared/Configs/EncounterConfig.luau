--[[
	EncounterConfig
	---------------
	THE SERVER DECIDES WHAT EVERY TRAFFIC CAR IS. Added 2026-09-28 after a security review found that
	a client could bank any car on the roster: traffic is simulated on the client (every driver owns
	their own road), so every car's tier, body, paint and mutation used to be rolled there too, and
	the steal and the bank simply reported them. An exploiter could start a run, fire the bank remote
	with the best car in the game, and get it.

	=== HOW IT WORKS ==========================================================================

	`EncounterService` (server) rolls each car — the same ladder, luck, weather and body weights the
	client used (`TrafficConfig.rollRung` / `rollBody`) — and hands it out with an opaque, single-use,
	expiring TOKEN. `TrafficController` (client) keeps a small queue of them and spawns only cars it
	was issued, so what drives down the road is what the server said. Then:

	  • A STEAL redeems the token (`StealService`): the server marks it spent and remembers that car
	    as the one this player is now driving. The health refill is priced from the SERVER's tier.
	  • A BANK takes no car identity from the client at all (`GetawayService`): it banks whatever the
	    server remembers the player stealing, or nothing.
	  • A NEAR MISS names the token of the car it passed (`RewardService`), and each token pays once —
	    so the bonus is bounded by cars the server actually put on this player's road.

	=== WHAT IS STILL TRUSTED, AND WHY THAT IS NOW BOUNDED ====================================

	The server still cannot see the road, so it cannot prove a steal happened near the car. What it
	CAN do is make every claim name a car it issued: a cheater can only steal from the handful of cars
	currently queued for them, rolled at the road's real odds, at the rate traffic really arrives
	(`Issue`). "Mint any car at will" becomes "steal a car that was really coming, a little early".

	THE DISTANCE THE TIER LADDER IS ROLLED AT is the client's, clamped (`MaxSpeed`): the ladder unlocks
	better rungs further down the road, and a client claiming tile 90 ten seconds into a run is capped
	at the furthest tile it could possibly have reached.

	`Enabled = false` puts every part of this back exactly as it was: the client rolls, the steal
	reports a tier, the bank reports the car. The honest A/B, and the escape hatch if a live issue
	appears — but it reopens the hole, so it is not a switch to leave off.
]]

local EncounterConfig = {}

EncounterConfig.Enabled = true

-- === The client's queue =====================================================

--[[ How many cars the client asks for at once, and the queue length at which it asks for more.

	Sized off the road rather than guessed: `TrafficConfig.PrimeCount` (14) cars are laid down at race
	start, and traffic then arrives about once a second (`SpawnInterval` 0.9-1.7s, faster inside a
	formation). Asking at 6 left with a batch of 12 means a refill is in flight with several seconds
	of cars still in hand — far longer than any round trip — so the spawner never waits on the network.
	If it ever does, it simply skips that spawn and tries again next tick; the road runs a little
	thinner for a moment rather than stalling. ]]
EncounterConfig.BatchSize = 12
EncounterConfig.RefillBelow = 6

-- === The server's limits ====================================================

--[[ Seconds an issued car stays redeemable. A car is spawned 140-1500 studs ahead
	(`TrafficConfig.PrimeBand`) and reached in well under a minute at any speed the game allows, so
	150 is generous for the slowest honest player and short enough that a hoarded token dies. ]]
EncounterConfig.Lifetime = 150

--[[ Unspent, unexpired cars one player may hold at once, which with RETIRING (below) means the cars
	actually on their road plus the ones queued to spawn.

	RETIRING IS WHAT MAKES THIS A CAP AND NOT A FUSE. A car that drives off the back of the road is
	recycled on the client, and nothing else ever spends its token: only a steal does. Before
	2026-09-30 every recycled car kept its slot until `Lifetime` ran out, so the cap filled after
	about 40 cars (35 to 45 seconds into any run, measured) and the server issued nothing more until
	the first batch expired at 150s. That was "the road ahead is empty" (Aleafo, 2026-09-28). Now the
	client hands back each recycled car's token on its next `EncounterRequest` and the server drops it
	(`EncounterService._retire`), so a slot comes free the moment a car leaves the road.

	SIZED OFF THE ROAD'S REAL PEAK: `TrafficConfig.MaxCars` 16 plus `TrailingAllowance` 3 is 19 cars
	live in clear weather and 31 in `RushHour` (Cars x1.75), and the queue can hold up to 17 (a batch
	of 12 landing at `RefillBelow` minus one). 31 + 17 = 48, so 64 leaves headroom for a pack without
	letting a client stockpile a pool worth cherry-picking. A client that never retires is held to
	this and starves only its own road. ]]
EncounterConfig.MaxOutstanding = 64

--[[ The issue rate: a token bucket. `Burst` covers the race start (priming plus the first batch);
	`PerSecond` is the steady refill, a little above the fastest honest arrival rate (packs in rush
	hour) so the road is never starved, and far below what a script spamming the remote would ask. ]]
EncounterConfig.Issue = {
	Burst = 40,
	PerSecond = 2.5,
}

--[[ Fastest the player can plausibly be going, studs per second, for clamping the distance a batch
	is rolled at (header, "the distance"). Deliberately above anything nitro reaches, because a car
	rolled at a slightly-too-short distance is a slightly-worse car for an HONEST player, and this
	clamp exists for the dishonest one. ]]
EncounterConfig.MaxSpeed = 450

--- Tiles ahead of the player's plausible position a batch may be rolled for: cars spawn up to a
--- tile and a half ahead (`TrafficConfig.PrimeBand`), so a request can honestly be that far out.
EncounterConfig.TileSlack = 2

-- === Integrity telemetry ====================================================

--[[ A run-end summary per player (`EncounterService._report`), and a WARNING — never a punishment —
	when a run looks implausible. The review's own advice: measure the false-positive rate before
	anything acts on these. Tune them against real logs, not in the abstract. ]]
EncounterConfig.Telemetry = {
	Enabled = true,
	--- A run this long (seconds) with no hit of any kind is worth a look: honest runs get clipped.
	NoHitSeconds = 180,
	--- More steals per minute than this is worth a look: a steal is a jump, a flight and a landing.
	MaxStealsPerMinute = 8,
}

return EncounterConfig
