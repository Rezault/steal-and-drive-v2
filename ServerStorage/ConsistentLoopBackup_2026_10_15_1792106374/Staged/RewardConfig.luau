--[[
	RewardConfig
	------------
	WHAT A RUN PAYS. The garage (GarageConfig) is what your cars pay you while they stand still;
	this is what the driving itself pays, and the two are deliberately separate numbers.

	Three payouts, and the third is the one that makes the other two a decision:

	  1. DISTANCE CASH. Every stud you drive is worth `Distance.CashPerStud`, banked at the end of
	     the run. It is the floor under a run: the reason a session that never lands a steal is
	     still worth playing, and the reason driving into the truck in the starter car — which
	     awards no car, because the starter has no identity to award (GarageService._readCar) —
	     is no longer a minute of play for nothing.

	  2. CAR XP, on a bank only. The body you got away with gains XP for the distance you drove,
	     levels up, and a levelled body is FASTER the next time you are in one (`SpeedPerLevel`,
	     applied by StealController._applyTier on top of that car's own `CarConfig.MaxSpeed`). This
	     is the reason to keep stealing the same car rather than only ever chasing a higher tier.

	  3. THE CRASH SPLIT. Wreck and you keep `Crash.CashFraction` of the distance cash and nothing
	     else — no car, no XP. THIS IS THE WHOLE RISK CURVE. Push on for a better car and you are
	     staking three quarters of what you have already earned; bank now and you keep all of it.
	     At 0 the run is pure gambling and a bad crash feels like the game took something; at 1
	     banking stops being a decision at all, because crashing costs you only the car. The
	     interesting range is narrow and this is the first number to move if the run feels either
	     punishing or pointless.

	AND ONE BONUS ON TOP, which is priced in a file of its own: near misses (`NearMissConfig`). It
	rides in through `payoutFor` as a plain number of dollars rather than being worked out here, for
	two reasons — it is the one term in the payout the server cannot measure for itself, and a feature
	that can be switched off has no business being wired into this file's arithmetic. It takes the
	same crash split as the distance; `payoutFor` says why.

	WHY DISTANCE IS MEASURED ON THE SERVER, AND WHAT THAT BUYS. Everything else in the run is
	reported by the client because the client is the only side that can see it — the road, the
	traffic, the obstacles and the truck are all client-built (see RoadController's header). Distance
	is the one exception: the server OWNS the car, so it can watch its own copy move and never has to
	take a number from anyone. `RewardService` does exactly that, which is why cash is the one reward
	here with no trust gap in it at all. XP rides on the same measurement, so it inherits that for
	free; only WHICH BODY the XP lands on is still the client's word (the same accepted gap
	`GetawayService` documents, closed by the same server-rolled spawn token).
]]

local BalanceConfig = require(script.Parent.BalanceConfig)
local RewardConfig = {}

-- Master switch. Off = runs pay nothing and no XP is written. The race loop and the garage are
-- untouched, which is also how you A/B whether the run economy is pulling its weight.
RewardConfig.Enabled = true

-- === Measuring the distance =================================================
--[[ How the server turns "the car moved" into a number.

	A SAMPLE, NOT A PHYSICS STEP. The car's forward-axis coordinate is read on a slow poll and the
	positive change between reads is accumulated. 0.1s matches `RaceConfig.VoidCheckInterval` on
	purpose — both are polls of the same handful of live cars, and a run is thousands of studs long,
	so a tenth of a second of granularity is invisible in the payout.

	`MaxStudsPerSecond` IS A REBASE FILTER, and it is the only subtle part of this file. The client
	shifts its whole local world (and the car, which it owns) back toward the origin every
	`RaceConfig.RebaseThresholdStuds` — see RoadController._shiftWorld — and that replicates to the
	server as the car jumping thousands of studs in one frame. A sample bigger than this is therefore
	NOT travel, and it is DISCARDED rather than clamped: clamping would credit a phantom sample's
	worth of studs to a rebase that happened to shift forward, where discarding costs at most one
	sample of real travel (about seven studs, once per eight thousand). 200 is comfortably above the
	~71 studs/s the car reaches on boost (DriveConfig.BoostSpeedScale) and comfortably below any
	shift a rebase can make, which is at least one whole road segment.

	Backwards movement is never counted. Reversing to re-take a stretch of road you were already
	paid for is not distance, and the endless runner has no reason to allow farming it. ]]
RewardConfig.Sample = {
	Interval = 0.1,
	MaxStudsPerSecond = 750,
}

-- === Distance cash ==========================================================
--[[ `CashPerStud = 0.1` — a stud is a tenth of a dollar, so a hundred studs is ten dollars.

	Sized against the thing it is competing with rather than against a feel: a clean run out to
	where mid-ladder traffic spawns is roughly four thousand studs, which is 400. The bottom car of
	a world sells for 480 (`GarageConfig.Income.SellSeconds` x its rate), and PARKED it earns that
	back every four minutes forever. So a full run of distance is worth about one beater — real money
	to a new player with an empty lot, and a rounding error next to banking the top of the world
	(18,720). That ordering is the point: distance is the floor, the car is still the prize. ]]
RewardConfig.Distance = {
	CashPerStud = 0.1,

	--[[ Studs to one metre, for the READOUT only — nothing in the payout maths goes through it.

		A stud is the unit the run is measured and paid in, and a meaningless one to read: "4,000"
		on a results screen is a number with no scale attached to it. Metres are what every other
		endless runner puts there, so the results line converts once, here.

		4.4 is this world's own scale rather than Roblox's nominal 3.57 — a car here measures 19.9
		studs nose to tail (`CarBody`'s HitBox), which is a real car's ~4.5m. See the prop-scaling
		note: every model in the place was sized against the car, so the car is what sets it.

		Set to 1 to show raw studs instead. ]]
	StudsPerMeter = 4.4,

	--[[ Below this many studs a run pays nothing at all.

		An entry that fails before the car ever goes live still runs the whole end-of-run path
		(RaceService fires its exits for a car that never moved), and paying two dollars for it
		would put a payout line on screen for something that never happened. Well under the length
		of one road segment, so no real run can land here. ]]
	MinStuds = 25,
}

-- === The crash split ========================================================
--[[ What a wreck keeps. See the header — this is the risk curve.

	0.25 is chosen so the ARITHMETIC of pushing on is honest at the moment you are asked to decide.
	Passing up a truck to reach the next tier means roughly doubling your remaining distance; at a
	quarter kept, crashing costs you three quarters of what is already banked, which is a real stake
	without being ruinous, and it stays a stake at every distance rather than only late in a run.

	It covers EVERY way a run ends badly, not just running out of HP: a whiffed bail onto the tarmac,
	falling out of the world, dying, and disconnecting mid-run all settle through the same path
	(RewardService.endRun). One rule, no ending that quietly pays differently. ]]
RewardConfig.Crash = {
	CashFraction = 0.25,
}

-- === Car XP =================================================================
--[[ XP IS PER BODY, NOT PER PLAYER, and it is earned only on a bank.

	A body — `Sedan12`, `Sports16` — is what a car IS in this game (`GarageConfig.Banking`'s header
	makes the same point about the collection: two different Tier 3s are two different cars to own).
	So XP attaches to the body, and a player's profile carries one XP number per body they have
	banked. Bank the same car again and it levels; the roster of 43 becomes 43 separate progressions
	rather than one bar.

	ONLY ON A BANK, which is the checklist's own reading and also the only one that keeps the crash
	rule meaningful: if a wreck paid XP, the safe run and the greedy run would differ only in cash.

	WHAT A LEVEL DOES: it makes that body FASTER — `SpeedPerLevel` multiplies the top speed the car
	is set to when you are driving one, against that car's own `CarConfig.MaxSpeed`. It is the ONE
	place a particular player's copy of a car diverges from the stock numbers in `CarConfig`, which
	is why it is applied by the controller rather than stamped by `CarStats`. Today that lands when
	you steal one mid-run (StealController._applyTier); the day "start your run in a car you own"
	ships, it lands at the line too, through the same multiplier. ]]
RewardConfig.Xp = {
	--[[ XP per stud driven, awarded to the banked body. At 0.1 the four-thousand-stud run above is
		400 XP, so a body reaches level 2 in a run and a bit, and level 10 in roughly forty banks of
		that car. Deliberately the same shape as the cash rate so "a long run is worth more" means
		the same thing to both. ]]
	PerStud = 0.1,

	--[[ The ladder. XP needed to REACH level L is `LevelBase * (L - 1)^LevelCurve`, so:

		    L2 = 500    L3 = 1,516    L4 = 2,900    L5 = 4,595    L10 = 16,817

		Superlinear (1.6) rather than geometric, because the reward is a small linear speed bump
		rather than a compounding income multiplier — a geometric ladder against a linear payoff
		makes the last levels unreachable for no reason. Levels come cheap early, which is where the
		player needs to feel that stealing the same car twice did something. ]]
	LevelBase = 500,
	LevelCurve = 1.6,

	--[[ Top speed added per level above 1, as a fraction. Level 10 is +18%.

		Bounded against the tier ladder on purpose: a world's `CarConfig.MaxSpeed` values span 34.4
		to 48.8, so a fully levelled bottom car (34.4 x 1.18 = 40.6) draws level with a stock third
		rung and no further. A levelled beater should feel like a rewarded beater, never like a
		shortcut past the tier gating the whole run is built around.

		THAT BOUND IS NOW SOMETHING YOU CAN BREAK, and it is worth knowing before you do: the spread
		used to be a resampled curve that could not be edited per car, and it is now 29 hand-editable
		numbers. Compress a world's ladder and this multiplier starts reaching further up it. ]]
	MaxLevel = 10,
	SpeedPerLevel = 0.02,
}

-- === Derived ================================================================

--[[ WHAT A FINISHED RUN PAYS, all of it: the distance, plus whatever BONUS was earned along the way,
	both cut by the same crash split. Returns the total and the part of that total which was bonus.

	`bonus` is near-miss money today (`NearMissConfig`, banked by RewardService) and is deliberately
	an argument rather than something this file knows how to work out — it is the one term in the
	payout the server cannot measure for itself, and keeping it at arm's length is what stops this
	file's arithmetic depending on a feature that can be switched off.

	IT TAKES THE SAME CRASH SPLIT AS THE DISTANCE, and that is a design decision rather than an
	implementation detail. `Crash.CashFraction` exists so that everything you have earned so far is at
	stake when you choose to push on; a bonus that was paid in full on a wreck would be a growing
	slice of the run that carrying on costs you nothing to protect, which takes the teeth out of the
	one decision the whole loop is built around. Push on with a chain going and you are staking that
	too.

	The two are floored separately, so the bonus half can be a dollar under its share of the total —
	which is invisible, because the results screen shows the total and the bonus and never the
	subtraction between them. `bonus` is clamped INTO the total for the one case that would otherwise
	read as broken: a run under `MinStuds` pays nothing at all, bonus included (see that field).

	`banked` = drove into the getaway truck; anything else is a crash.

	=== AND `multiplier` IS THE WEATHER ========================================================

	A mutated car multiplies the WHOLE payout — the distance and the bonus together — and it is the
	last thing applied, after the crash split. `WeatherConfig` prices it; this file only multiplies,
	which is the same arm's length `bonus` is kept at and for the same reason: a payout formula that
	knew what a thunderstorm was would stop working the day somebody switched the weather off.

	AFTER THE SPLIT AND NOT BEFORE IT, which is invisible in the banked case (the split is 1) and is
	the whole question in the crashed one. It reads as "a quarter of five times the run" rather than
	"five times a quarter of it" — identical arithmetic, but it means the multiplier is not something
	a wreck can be argued to have kept in full. In practice a wreck cannot carry one at all: a
	mutation only prices a bank, because a crash awards no car for it to be on. It is written to
	compose anyway, because the day a wreck pays out a partial car this is the line that would
	otherwise quietly be wrong.

	nil, 1, a NaN or anything else nonsensical all mean "no mutation", so every caller can hand
	whatever it has straight in. ]]
function RewardConfig.payoutFor(studs: number, bonus: number?, banked: boolean, multiplier: number?, world: number?): (number, number)
	if not RewardConfig.Enabled or type(studs) ~= "number" or studs ~= studs then
		return 0, 0
	end
	if studs < RewardConfig.Distance.MinStuds then
		return 0, 0
	end
	local extra = if type(bonus) == "number" and bonus == bonus and bonus > 0 then bonus else 0
	local fraction = if banked then 1 else RewardConfig.Crash.CashFraction
	local scale = if type(multiplier) == "number" and multiplier == multiplier and multiplier > 0
		then multiplier
		else 1
	local total = math.max(0, math.floor((studs * RewardConfig.perStudFor(world) + extra) * fraction * scale))
	--[[ The bonus half is scaled too. It has to be: the results screen draws the bonus as a slice OF
		the total, and a bonus that had not been multiplied would shrink to a rounding error next to a
		five-times distance — which reads as the near misses having stopped paying. ]]
	return total, math.clamp(math.floor(extra * fraction * scale), 0, total)
end

-- The distance half on its own. Kept as its own name because "what is a run's distance worth" is a
-- question two callers ask for reasons that have nothing to do with a bonus — including the cap on
-- the bonus itself (`NearMissConfig.cap`), which is measured against exactly this.
function RewardConfig.cashFor(studs: number, banked: boolean, world: number?): number
	return (RewardConfig.payoutFor(studs, 0, banked, 1, world))
end

--[[ How far the run went, for a label: metres at this world's scale (`StudsPerMeter`), comma
	grouped, suffixed. Never abbreviated the way `GarageConfig.formatCash` is — a run is hundreds of
	metres, not hundreds of thousands, so the band where a suffix earns its place is out of reach.

	nil, NOT "0m", for anything that doesn't round to a whole metre. An entry that falls over before
	the car goes live still runs the whole end-of-run path (see `MinStuds`), and the results screen
	has no distance line to draw for a run that never moved — the same reason it has no payout line
	for one. Callers show the line only when this answers. ]]
function RewardConfig.formatDistance(studs: number?): string?
	if type(studs) ~= "number" or studs ~= studs or math.abs(studs) == math.huge then
		return nil
	end
	local metres = math.floor(studs / RewardConfig.Distance.StudsPerMeter + 0.5)
	if metres < 1 then
		return nil
	end

	local text, count = tostring(metres), 0
	repeat
		text, count = string.gsub(text, "^(%d+)(%d%d%d)", "%1,%2")
	until count == 0
	return text .. "m"
end

-- XP for a banked run. Crashes never reach this — see the `Xp` header.
function RewardConfig.xpFor(studs: number): number
	if not RewardConfig.Enabled or type(studs) ~= "number" or studs ~= studs then
		return 0
	end
	if studs < RewardConfig.Distance.MinStuds then
		return 0
	end
	return math.max(0, math.floor(studs * RewardConfig.Xp.PerStud))
end

-- Total XP needed to REACH this level. Level 1 is free (owning the car is what level 1 means).
function RewardConfig.xpForLevel(level: number): number
	if level <= 1 then
		return 0
	end
	return math.round(RewardConfig.Xp.LevelBase * (level - 1) ^ RewardConfig.Xp.LevelCurve)
end

--[[ Which level a body's XP total buys. Counted up rather than solved, because `MaxLevel` is ten:
	the loop is shorter than the inverse of the curve is to read, and it stays correct if the ladder
	is ever hand-edited into something that has no closed form. ]]
function RewardConfig.levelFor(xp: number?): number
	if type(xp) ~= "number" or xp ~= xp or xp <= 0 then
		return 1
	end
	local level = 1
	for candidate = 2, RewardConfig.Xp.MaxLevel do
		if xp < RewardConfig.xpForLevel(candidate) then
			break
		end
		level = candidate
	end
	return level
end

-- XP still to go before the next level, and nil at the cap. For a readout, not for the maths.
function RewardConfig.xpToNext(xp: number?): number?
	local level = RewardConfig.levelFor(xp)
	if level >= RewardConfig.Xp.MaxLevel then
		return nil
	end
	return math.max(0, RewardConfig.xpForLevel(level + 1) - (if type(xp) == "number" then xp else 0))
end

-- The multiplier a levelled body's top speed gets. 1 at level 1, so an unlevelled car is
-- untouched and every call site can apply this unconditionally.
function RewardConfig.speedScaleFor(level: number?): number
	if type(level) ~= "number" or level ~= level or level <= 1 then
		return 1
	end
	local capped = math.min(level, RewardConfig.Xp.MaxLevel)
	return 1 + RewardConfig.Xp.SpeedPerLevel * (capped - 1)
end

--[[ The broadcast, and its two halves.

	Levels reach the client as one string on the Player (`GarageConfig.LevelsAttribute`), exactly as
	the collection and the lot already do — attributes replicate, so the client needs no remote and
	no round trip to know how fast the car it just stole should be.

	ONLY BODIES ABOVE LEVEL 1 ARE WRITTEN. Level 1 is the default every reader falls back to, so
	listing it would be 43 entries of "no change"; a fresh player broadcasts an empty string. ]]
function RewardConfig.encodeLevels(xpByBody: { [string]: number }?): string
	if type(xpByBody) ~= "table" then
		return ""
	end
	local parts = {}
	for body, xp in xpByBody do
		if type(body) == "string" and body ~= "" then
			local level = RewardConfig.levelFor(xp)
			if level > 1 then
				table.insert(parts, string.format("%s:%d", body, level))
			end
		end
	end
	table.sort(parts) -- stable, so the attribute doesn't churn when nothing changed
	return table.concat(parts, ",")
end

-- The other half. Anything malformed is simply skipped: this is read on the hot path of a steal,
-- and a car at level 1 is the correct answer to "I could not tell".
function RewardConfig.decodeLevels(encoded: unknown): { [string]: number }
	local out = {}
	if type(encoded) ~= "string" or encoded == "" then
		return out
	end
	for body, level in string.gmatch(encoded, "([^,:]+):(%d+)") do
		local number = tonumber(level)
		if number then
			out[body] = math.clamp(number, 1, RewardConfig.Xp.MaxLevel)
		end
	end
	return out
end

-- Convenience for the one client that reads this: the level of one body, straight off the string.
function RewardConfig.levelOf(encoded: unknown, body: string?): number
	if type(body) ~= "string" then
		return 1
	end
	return RewardConfig.decodeLevels(encoded)[body] or 1
end

-- Driving pay per stud is `BalanceConfig.DrivingCashDivisor`'s (2026-10-13: the old
-- `Distance.CashPerStud = 0.15` override here was read by nothing and only misled).
function RewardConfig.perStudFor(world: number?): number
 return BalanceConfig.roadValue(world) / BalanceConfig.DrivingCashDivisor
end

return RewardConfig


