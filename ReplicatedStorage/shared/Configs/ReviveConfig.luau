--[[
	ReviveConfig
	------------
	The paid continue: what the RESPAWN SCREEN offers when you wreck, and what taking it costs.

	=== THE SHAPE OF THE FEATURE ==============================================================

	A wreck used to be a straight line — HP hits zero, the car coasts and smokes, the screen fades,
	you are back in the lobby reading what the run was worth. This puts one decision in the middle
	of it: for `Tiers[n].Price` Robux, the run does not end. The same car is set back on the lane
	where it died with full health, you are put back in the seat, and the distance keeps counting
	from the number it was already on.

	THE RUN IS NOT SETTLED WHILE THE OFFER IS OPEN, and that is the load-bearing half of it.
	`RaceService.wreckRace` normally pays the run out the instant the controls are cut; with an offer
	live it holds that back until the offer resolves, because a settled run has already been banked
	as a crash — paid, XP-less, recorded against the map — and reviving out of one would either pay
	the player twice or make the revive worthless. `ReviveService` owns that window and is the only
	thing that closes it.

	=== WHY THE PRICE CLIMBS ==================================================================

	`Tiers` is a ladder, not a price: 25, then 45, then 75 within one run, and then no more offers.

	A flat price with no cap turns a good run into an unbounded purchase, which is bad for the
	player who did not mean to spend forty Robux and bad for the game (the leaderboard becomes a
	wallet ranking). A climbing price makes the FIRST one an easy yes — it is a small number against
	a run you are two minutes into — and makes the third an actual decision. The cap is where the
	ladder ends: `#Tiers` revives per run, and the fourth wreck is the one that sticks.

	The Robux prices here have to agree with `rbxsync.toml`, which is where the products are
	actually created and priced. Nothing checks that at runtime — this number is what the button
	says and that number is what the player is charged — so they are changed together or not at all.

	=== WHY A LIFE IS STORED RATHER THAN SPENT ================================================

	A purchase does not revive anybody. It increments `ExtraLives` on the profile, and the revive is
	a separate step that SPENDS one. That looks like a pointless indirection until you count the ways
	a receipt can arrive at a moment when there is nothing to revive: the offer timed out while the
	purchase prompt was still up, the player left, the server restarted mid-purchase, Roblox retried
	the receipt on their next session. Every one of those is a player who paid and got nothing.

	Stored, all of them are a player who paid and owns a life — which the very next wreck spends for
	free, without a prompt. The screen says so when they have one.

	=== WHAT CANNOT BE REVIVED ================================================================

	`RevivableCauses` is a whitelist, and the two absences are deliberate. See the note on it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameIds = require(ReplicatedStorage.shared.GameIds)

local ReviveConfig = {}

-- Master switch. False takes the offer out entirely: a wreck goes straight to the results screen,
-- exactly as it did before this existed, with no code path left half-live.
ReviveConfig.Enabled = true

--[[ The ladder. `key` ties a rung to its `[products.<key>]` block in `rbxsync.toml`; `ProductId` is
	filled in below from the rbxsync-generated `GameIds`, and is 0 only if the sync has not been run
	(which reads downstream as "this rung cannot be sold", never as "it is free").

	`Price` is what the BUTTON says. Roblox charges what the product is priced at, so this is a
	display value that has to be kept honest against `rbxsync.toml` by hand. ]]
ReviveConfig.Tiers = {
	{ key = "Revive1", Price = 25 },
	{ key = "Revive2", Price = 45 },
	{ key = "Revive3", Price = 75 },
}

for _, tier in ReviveConfig.Tiers do
	tier.ProductId = GameIds["products." .. tier.key] or 0
end

--[[ The profile key holding lives already paid for. Top-level on purpose: `PlayerProfile`'s string
	path is a recursive key search, so a nested key is only safely reachable by array path — and
	this one is read and written from two services. Defaults to 0 in `Settings.TEMPLATE`. ]]
ReviveConfig.ProfileKey = "ExtraLives"

--[[ Mirrored onto the Player as an attribute by `ReviveService` so the screen can read how many
	stored lives it may spend without a round trip. The screen is up for eight seconds and has to
	repaint the instant a purchase lands, which is exactly what an attribute changed signal is. ]]
ReviveConfig.LivesAttribute = "ExtraLives"

--[[ How long the offer stands before the run ends on its own.

	EIGHT SECONDS IS SIZED OFF THE PURCHASE, not off patience: tapping REVIVE opens Roblox's own
	purchase prompt, which is a modal the player has to read and confirm, and a countdown that
	expires while that prompt is up is a player watching their run end with their thumb on the buy
	button. `ReviveService` therefore SUSPENDS this clock while a prompt is open (see its
	`_onPromptFinished`) — so eight is only ever the time spent deciding, never the time spent
	transacting.

	It still has to be short. This is the one screen in the loop that stands between a player and
	their next run, and a wreck they never intended to pay out of should cost them a couple of
	seconds, not a stretch of thumb-twiddling. ]]
ReviveConfig.OfferTime = 8

--[[ Which endings get an offer, as a set keyed by `wreckRace`'s `cause`. Absent means no offer:
	the run ends the way it always did.

	`false` — nil, the ordinary HP death — is the case this feature exists for, and "thrown" (the
	rider prised out of the seat mid-race) is the same wreck reached a different way.

	THE TWO THAT ARE MISSING ARE MISSING ON PURPOSE:

	  • "fell" is the void guard (`RaceService._checkForFalls`). A car that has dropped out of the
	    world is a BUG being caught, not a mistake the player made, and selling somebody a revive out
	    of our own physics failure is the wrong side of a line. It goes home free, as it always has.
	  • "badLanding" is a whiffed bail — the player is face down on the tarmac with the camera on
	    them and the car hidden and anchored underneath. There is no car in that shot to be put back
	    on the road, and the beat it plays is a punchline, not a cliffhanger.

	AND ONE THAT IS PRESENT ON PURPOSE. "busted" is the police chase (`PoliceConfig.Cause`), and it
	is the ordinary death's case exactly: the car is intact, sitting on the road, with a rider still
	in the seat and a run's worth of distance behind it. What a revive buys there is better than
	what it buys anywhere else, because the chase restarts with a fresh bar rather than dropping the
	player back into the second that beat them. `PoliceController._onRevived` is the half of that
	which has to be true, and it is the reason this line is not simply a price on a failure.

	`cause` is nil for the ordinary death, so it is looked up as the string below rather than as nil
	— a nil key cannot be stored in a Lua table at all. ]]
ReviveConfig.OrdinaryCause = "wrecked"
ReviveConfig.RevivableCauses = {
	[ReviveConfig.OrdinaryCause] = true,
	thrown = true,
	--[[ Written out rather than required from `PoliceConfig`, which would be a config requiring a
		config for one string and would put a load-order edge under the revive path. The two are
		kept honest by `PoliceConfig.Cause` naming this file in its own note. ]]
	busted = true,
}

--[[ === Putting the car back ==============================================================

	The revive re-uses the SAME car rather than spawning a fresh one, so the body, the paint and the
	tier stats the player stole their way up to all survive it. What has to be undone is where the
	wreck left it: a car that has been coasting and rolling for a second and a half is somewhere
	between "stopped in lane" and "upside down in the barrier".

	It is therefore re-seated on the lane: same forward position along the road, lane centre,
	upright, facing down the road, at rest. Same maths `RaceService._spawnCar` uses to place a car
	on the deck in the first place — see `RoadService.getSpawnCFrame` — with the forward coordinate
	kept rather than reset, which is the whole difference between a revive and a restart. ]]

-- Studs above the deck the car is set down at, so the suspension settles it rather than starting
-- interpenetrated. The same clearance a fresh spawn uses (`RaceConfig.SpawnClearance`) and for the
-- same reason; kept separate so a revive can be lifted higher if a redress ever needs it.
ReviveConfig.DropClearance = 1.5

--[[ Studs BACK down the road from where the car died.

	Zero would be honest and is wrong: you wrecked because something was in front of you, and the
	obstacle that killed you is still exactly there. Dropping back a car length and a bit gives the
	player the same beat of road to react to that they would have had coming into it fresh, which is
	the difference between a revive and a second helping of the same crash.

	Not far enough to feel like lost ground — `RewardService` measures forward travel only, so this
	is a few studs the run has to re-drive and is never subtracted from a distance already banked. ]]
ReviveConfig.SetBackStuds = 28

--[[ How long the car is held still after it is set down, before the controls come back.

	The respawn screen is still up over the top of this, and that is the point: the reset — car
	teleporting, rider standing up out of a ragdoll and being re-seated, smoke stopping — happens
	entirely behind the overlay, and what the player sees is the screen dropping onto a car already
	sitting on the road ready to go. Long enough for the seat toggle in `_deployDriving` to finish,
	which is what actually gates it. ]]
ReviveConfig.ReviveHoldTime = 0.6

return ReviveConfig
