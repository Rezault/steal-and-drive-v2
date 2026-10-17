--[[
	TutorialDirector  (client)
	--------------------------
	What is on the road during somebody's first run.

	`TutorialController` owns the card, the arrow and the pause. This owns the WORLD those beats
	happen in: an empty road while a key is being taught, four cars at a chosen spacing when the
	beat is about traffic, and one car in a cleared radius when the beat is about stealing.

	=== WHY THE ROAD NEEDS A DIRECTOR AT ALL ==================================================

	The shipped spawner is good at keeping a road populated and has no opinion about what the first
	thirty seconds of somebody's life in this game look like. `TrafficConfig.PrimeCount` seeds ten
	cars between 140 and 1,500 studs at race start and `MaxCars` holds twelve around the driver
	after that, at rolled lanes and rolled speeds. That is the right road for the eight hundredth
	run and the wrong one for the first, where two questions have to be answerable at a glance:
	is there a car near me, and can I get past it.

	A rolled road answers both differently every time. Some first runs open with a clear quarter
	mile and some open with three cars abreast, and the tutorial has to teach the same lesson to
	both. So for the length of its in-race beats it deals the hand itself.

	IT DEALS AND THEN LETS GO. The staging stops at the steal — the moment the player has done the
	thing the game is named after — and the BANK beat, where they drive unaided until the truck
	arrives, is deliberately the first unstaged road they see. `ObstacleService`'s damage floor is
	scoped to exactly the same beats for exactly the same reason.

	=== IT IS ALL CLIENT-SIDE, WHICH IS WHAT MAKES IT CHEAP ===================================

	The road, the traffic, the obstacles and the getaway truck are already the client's own copy of
	the world — driving is solo and none of it replicates (`TrafficController`'s header). So staging
	a run is one controller reading a config table and calling three public methods on the traffic
	population. There is no server surface here at all, and nothing another player could see.

	What the server DOES own is unchanged: the steal is still ratified by `StealService`, the damage
	is still priced by `ObstacleService`, and the car the player keeps is still awarded by
	`GarageService`. The director chooses what is on the road; it does not decide what any of it is
	worth.

	=== HOW IT KNOWS ==========================================================================

	Off one player attribute, polled. `TutorialConfig.StepAttribute` carries the live beat id, and
	`TutorialConfig.isStaged` turns that into "should this road be staged" — the same read
	`GetawayController` makes for its truck timings and `ObstacleService` makes for its damage
	floor. Three consumers, one string, no subscriptions and nothing to unwind.

	POLLED RATHER THAN WATCHED, and slowly: `Interval` below is a fifth of a second, because every
	decision in here is about the next several seconds of road and none of them is improved by being
	made 60 times a second. An attribute-changed connection would be the tidier shape and would fire
	at the wrong moments — a beat can advance while a race is loading, and what this needs to know
	is when the beat AND the road are both ready.

	HOUSE RULE: no wiki-style double-bracket links in these comments — the closing pair ends the
	block comment early and the parse error points at the wrong line.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local TimeScale = require(ReplicatedStorage.shared.Modules.TimeScale)

local TutorialDirector = Shard.new("TutorialDirector"):withDependencies({
	"RoadController",
	"TrafficController",
	"StealController",
})

--- How often the road is looked at, in seconds. See the header on why this is not a connection.
local INTERVAL = 0.2

--- How many failed placements in a row before the steal beat stops holding the spawner shut and
--- lets the shipped road back in. Five ticks of `INTERVAL`, i.e. a second. See the branch in
--- `_tick` that reads it for why giving up is the right move and why not immediately.
local GIVE_UP = 5

--[[ The closest the steal target may ever be put, in studs. A floor on an aimed placement rather
	than a tuning dial, and it only ever binds in a case the beat cannot be played in anyway.

	`_placeStealTarget` aims the car at where the arc will come down, MINUS the ground the car covers
	while the player is in the air. A player who bails from a standstill covers no ground at all and
	the car covers sixty studs, so the arithmetic asks for a car sixty studs BEHIND the driver —
	which is both impossible to jump onto and, placed, a car appearing on top of them. Clamped, the
	degenerate case puts a car just far enough ahead to be visible and lets the beat fail honestly. ]]
local MIN_LEAD = 24

--[[ The most the steal target's pace may change per tick, studs/s. See `_aimStealTarget`.

	An EASE rather than a set, because the correction is applied to a car the player is looking
	straight at. Six studs/s over a fifth of a second is about thirty studs/s of acceleration — brisk,
	unremarkable, and over the nine or ten ticks of a flight it adds up to more authority than any
	correction has ever needed. Set outright it reads as the car being yanked. ]]
local PACE_EASE = 6

--[[ Which beats want the road AHEAD kept empty, every tick, for as long as they are up. Both end
	with a key press rather than with a manoeuvre, and neither is improved by a lorry arriving
	during it.

	`bail` is NOT here even though it is the third key-press beat, and that is the one exception
	worth knowing: it clears once and then puts a car BACK — the one that is about to be stolen — so
	a standing clear would delete its own target on the next tick. See `_tick`.

	`survive` and `bank` are not here for the opposite reason: one is about traffic and the other is
	about the truck. ]]
local CLEAR_ON = {
	boost = true,
	steer = true,
}

-- === The hand ===============================================================

--[[ Deal the SURVIVE beat's cars: `SurviveCars` of them, running away from the driver at an uneven
	spacing, no two adjacent ones in the same lane.

	THE SPACING IS UNEVEN ON PURPOSE. A regular pulse of cars reads as a wall and gets driven AT; the
	point of the beat is that the player picks a gap, which needs the gaps to differ enough to be
	worth picking between. `SurviveGap` is a band and each step is rolled inside it.

	THE LANE ALTERNATES rather than being rolled, which is the one rule that makes four cars a slalom
	instead of a queue. Rolled lanes put two in the same one about a third of the time, and two cars
	nose to tail in one lane is a single obstacle that happens to be twice as long.

	`placeCar` still tests the lane for room and falls back to its own roll if the requested one is
	occupied, so this is a preference rather than an instruction — a staged road that stacked two
	cars would be a worse first impression than one that put a car a lane over. ]]
function TutorialDirector._dealSurvive(self)
	local traffic = self._traffic
	local stage = TutorialConfig.Rig.Stage
	local lanes = traffic:laneCount()
	if lanes <= 0 then
		return
	end

	local along = traffic:playerAlong() + stage.SurviveLead
	--- Start on a lane away from the middle so the first car is one to steer AROUND rather than one
	--- sitting exactly where a player who has touched nothing is already pointed.
	local lane = 1 + (self._rng:NextInteger(0, 1) * (lanes - 1))

	for index = 1, stage.SurviveCars do
		traffic:placeCar(along, lane)
		if index < stage.SurviveCars then
			along += self._rng:NextNumber(stage.SurviveGap[1], stage.SurviveGap[2])
			--- Step by more than one lane where there are more than two, so consecutive cars are a
			--- real crossing rather than a drift.
			lane = 1 + ((lane - 1 + math.max(1, lanes - 2)) % lanes)
		end
	end
end

--[[ The four `StealTarget` dials that are distances and speeds, resolved against the cruise the
	player is actually driving at.

	They shipped as plain studs measured on a game that cruised at 52. The roster cruises at 71 to 103
	now, with traffic authored as shares of whatever car you are in, so a constant here was a constant
	that meant something different in every car of a run. `StealTarget` has the derivation
	and the three divisions it comes out of; this is only where the share is turned back into studs.

	RESOLVED ONCE PER USE RATHER THAN CACHED, because the number moves during a run: the whole point
	of the beat is that the player drives off in a faster car, and the next thing this places has to
	be placed for THAT car. One table so the two callers cannot resolve it differently, and so the
	cruise is read once. ]]
function TutorialDirector._stealDials(self)
	local spec = TutorialConfig.Rig.Stage.StealTarget
	local traffic = self._traffic
	local read = if traffic then traffic:playerCruise() else nil
	local cruise = if type(read) == "number" and read > 0 then read else nil
	local function dial(fraction: number?, absolute: number): number
		return if fraction and cruise then fraction * cruise else absolute
	end
	return {
		Fallback = dial(spec.FallbackFraction, spec.Fallback),
		Lead = dial(spec.LeadFraction, spec.Lead),
		MinPace = dial(spec.MinPaceFraction, spec.MinPace),
		MaxPace = dial(spec.MaxPaceFraction, spec.MaxPace),
	}
end

--[[ Put up the car the tutorial is going to be stolen, and clear the space around it.

	ONE BETTER THAN THE STARTER (`StealTarget.Tier`), because the loop is "steal a BETTER car" and a
	first steal that hands you a sidegrade teaches the verb without the reason. The car is otherwise
	an ordinary traffic car in every respect — rolled body, rolled colour, rolled speed — because it
	is the one the player keeps, and a car that behaved differently on the way in would be a car that
	behaves differently on the podium.

	THE RADIUS AROUND IT IS CLEARED FIRST and the board card asks for it in as many words. It is not
	decoration: the landing volume is the whole difficulty of a steal, and a first attempt that
	clips a bystander car on the way down reads as the mechanic not working rather than as a miss.

	IT IS PLACED WHEN THE JUMP IS ASKED FOR, not when the player is already in the air — see `_tick`,
	which calls this from the BAIL beat and retries it from AIRBORNE. The arc takes most of a second
	and the car has to be moving and settled into its lane by the time somebody is over it; a car
	that appeared at the apex would appear inside the shot.

	=== WHERE, AND WHY IT IS AN ANSWER RATHER THAN A NUMBER ==================================

	It is put where the jump will LAND, which nothing in this file is able to guess: see
	`StealTarget` in TutorialConfig for why a constant is wrong at every value, and
	`StealController.predictBail` for the arc that answers it. Three terms, and all three earn their
	place — dropping any one of them was a version of this that missed:

	    travel      what the arc covers, run forward through the real integrator from the player's
	                CURRENT speed. This is the term the old constant was standing in for.
	    settle      the player keeps DRIVING after this runs. The bail beat holds the card up for
	                its `Grace` before the world stops, and over that half second a driver at cruise
	                eats twenty-odd studs of the gap. Lead by what they are about to close.
	    airtime     the target is driving too, and it does not stop for the freeze either: it covers
	                its own pace times the whole flight. Aim where it WILL be, not where it is.

	What is left over is the roll on the car's own cruise (about six studs across a flight) and
	whatever the player steers in the air, and neither is knowable from here. `StealTarget.Reach`
	is the budget for both. ]]
function TutorialDirector._placeStealTarget(self, settle: number)
	local traffic = self._traffic
	local steal = self._steal
	local spec = TutorialConfig.Rig.Stage.StealTarget
	local dials = self:_stealDials()
	local here = traffic:playerAlong()

	--- `speed` is the player's ROAD speed, not the speed the arc leaves at. See `predictBail`: the
	--- difference between those two is a jump's worth of lead.
	local travel, airtime, speed
	if steal then
		travel, airtime, speed = steal:predictBail()
	end
	local pace = traffic:tierSpeed(spec.Tier)

	--- No road, no car, or no ladder yet: none of those are states this beat can be played in, so the
	--- fallback only has to be a number that does not put a car inside the player.
	local at = here + dials.Fallback
	if travel and pace then
		--[[ HOW FAST THE CAR IS ALLOWED TO DRIVE, which is a decision and not a roll — see `Lead`
			and `MinPace` in TutorialConfig. A jump closes the DIFFERENCE in speed, so a player who
			arrives at this beat slow cannot catch a car running at its tier's pace from any distance
			at all. `catchable` is the fastest this car can go and still be `Lead` studs in front at
			the moment the arc arrives; `math.min` means an ordinary quick run leaves it entirely
			alone, because there the tier's own pace is already the slower of the two. ]]
		local catchable = (travel - dials.Lead) / math.max(airtime, 0.01)
		-- The floor is itself floored at the tier's own pace, so a world whose tier 2 is slower than
		-- `MinPace` is left alone rather than sped up (and `math.clamp` is not handed an inverted range).
		pace = math.clamp(math.min(pace, catchable), math.min(dials.MinPace, pace), pace)
		at = here + travel + (speed - pace) * settle - pace * airtime
	end
	at = math.max(at, here + MIN_LEAD)

	--- Everything from the driver to well past the TOUCHDOWN, so the car lands in a hole rather than
	--- into whatever the previous beat left in front of the player. Measured off the aimed mark
	--- rather than off a constant, because the mark now moves with how fast the player is going.
	traffic:clearAhead(at - here + spec.Clear)

	--[[ IN THE PLAYER'S OWN LANE. Not decoration and not a preference — see `playerLane`: two lanes
		of separation puts the car outside the reach of any jump, and a lane picked at random is two
		or more lanes away most of the time on a five-lane road. This is the difference between a
		beat that always completes and one that completes sometimes.

		`placeCar` falls back to a lane of its own choosing if the one asked for is blocked, which is
		why `clearAhead` above runs first: by the time this is called there is nothing in that lane
		to block it. `Clean` is the other half of not being blocked — the shipped spawner also vetoes
		a lane with an obstacle up to 200 studs beyond the mark, which is a horizon for a car that has
		to keep driving and not for one that is stolen two seconds later. ]]
	local rec = traffic:placeCar(at, traffic:playerLane(), spec.Tier, spec.Clean)
	if not rec then
		--[[ Every lane at that coordinate was occupied or standing in the obstacle course. Not a
			warning on its own: the beat is still completable — there are other cars on the road and
			the player may steal any of them — and the retry on the next tick usually lands. What is
			worth warning about is never succeeding, which `_tick` counts.

			`_stealPlaced` stays false, so the next tick tries again from the player's NEW position
			rather than from the mark that failed. ]]
		return false
	end
	if travel and pace then
		--- ...and hold it to the pace the placement was aimed with. `placeCar` rolls a cruise inside
		--- the tier's band, which is the right car in every respect except the one this beat needs.
		--- Never upward: `min` leaves a car that already rolled slower exactly as it is.
		traffic:paceCar(rec, math.min(rec.speed, pace))
	end

	--[[ Remembered OUTSIDE `_staged`, which is cleared every time the beat changes — and the beat
		changes from BAIL to AIRBORNE in the middle of the arc this car exists for. A flag that reset
		there would put a second car on the road while the player was in the air over the first. It
		is cleared by `_standDown` and by a change of race, which is the end of the hand. ]]
	self._stealPlaced = true
	self._target = rec
	--- How far ahead this car actually went, so `_targetLost` can look at least that far before
	--- calling the road empty. An aimed placement is only as long as the arc it was aimed with, and
	--- a fast run's arc is longer than any fixed horizon written in the config.
	self._placedAhead = at - here
	return true
end

--[[ Has this beat lost the car it dealt, with the player back on the ground to be dealt to?

	=== THE BUG THIS EXISTS FOR ===============================================================

	`_stealPlaced` used to be a one-way latch: set by the placement, cleared only by `_standDown`,
	and `_standDown` only runs on a beat that is not staged or on a new race car. Neither of those
	happens to a player who misses the steal and carries on in the SAME race — and there is a
	well-travelled route to exactly that. Miss the car, land on tarmac, `StealController._whiff`
	reports it, the server wrecks the run, and the player pays to revive. `RaceService.reviveRace`
	puts them back in `self._cars[player]` — the same model, repositioned — so the race car never
	changes, and the AIRBORNE beat is still live because its only exit is a `CarStolen` the steal
	never earned.

	From there the director had a latched flag pointing at a car that was gone, a spawner it had
	shut on the way in, and no path back to either. The player drove the rest of the run down a
	road that could not repopulate itself with the objective card still asking them to take a car
	that was not there. That is the "no cars to steal" report, both halves of it, from one latch.

	=== WHY IT IS TWO CONDITIONS ==============================================================

	ONLY WHILE THEY ARE DRIVING. The flight states are the reason `_stealPlaced` deliberately
	outlives a beat change in the first place: the beat goes BAIL -> AIRBORNE in the middle of the
	arc the target was placed for, and anything that re-dealt there would put a second car on the
	road while the player was in the air over the first. `idle` is the only state that means the
	player is in a car, on the deck, with a jump still ahead of them — a launch, an arc, a perch
	and a mount are all mid-attempt and none of them wants help.

	AND ONLY WHEN THE ROAD IS ACTUALLY EMPTY, asked of the population rather than of the record we
	kept. See `TrafficController.hasCarAhead` for why the record cannot answer it: the records are
	pooled, so a recycled target is a live record for somebody else's car. It is also the better
	question — this beat needs a car to take, not the specific one it chose. A player who simply
	fell behind their target still has one out there and gets left alone. ]]
function TutorialDirector._targetLost(self): boolean
	local steal, traffic = self._steal, self._traffic
	if not traffic then
		return false
	end
	--- No StealController is the same fallback `_placeStealTarget` takes: assume they are driving,
	--- because the road being empty is then the whole of the evidence and it is still good evidence.
	local state = if steal then (select(1, steal:getFlight())) else "idle"
	if state ~= "idle" then
		return false
	end

	--[[ LOOK AT LEAST AS FAR AS THE CAR WE PUT DOWN. `Regrow` is a floor and cannot be the whole
		answer: the placement is aimed with the arc, the arc is as long as the player is fast, and a
		horizon shorter than the placement would read a perfectly good target as an empty road and
		deal a second car on the tick after the first. The gap only ever closes from there — the
		pace is picked to be catchable — so the distance it went out at is a safe ceiling to keep
		looking to, and `Clear` covers a player who slows down enough to let it stretch. ]]
	local spec = TutorialConfig.Rig.Stage.StealTarget
	local horizon = math.max(spec.Regrow, (self._placedAhead or 0) + spec.Clear)
	return not traffic:hasCarAhead(horizon)
end

--[[ Has the player been asked for the jump and simply kept on driving? Called once per tick of the
	steal beats, and it is the clock as well as the question.

	=== THE BUG THIS EXISTS FOR (2026-10-15) ==================================================

	The BAIL beat freezes the world to ask for the jump, and the freeze lets go on its own after
	`FREEZE_TIMEOUT` so a player whose key cannot reach the card is not stuck at a standstill. A
	player who just does not press it then drives on with the beat still up, and from there nothing
	in this file ever let go: the spawner stayed shut for the staged stretch, `_targetLost` kept
	dealing a single car into their lane, and `_placeStealTarget` cleared the road ahead every time it
	did. Reproduced in a playtest as one car on the road for minutes on end, rammed and re-dealt every
	few seconds. No truck either (it needs a steal) and no wreck (the tutorial cannot be lost), so
	the run had no way to end.

	=== WHAT COUNTS ===========================================================================

	Seconds of DRIVING: the player on the deck (`idle`) and the world moving. A frozen ask spends
	none of it, so the beat still gets its full freeze, and any flight starts the count again from
	zero, so a player who jumped and missed keeps a staged car for their next go. Only somebody who
	has been given the world back and chose to keep driving reaches `HandBack`. ]]
function TutorialDirector._ignoredTheJump(self): boolean
	local now = os.clock()
	local last = self._drivenAt
	self._drivenAt = now
	local steal = self._steal
	local state = if steal then (select(1, steal:getFlight())) else "idle"
	if state ~= "idle" then
		self._driven = 0
		return false
	end
	--- Clamped, so a gap in the ticks (a beat change, a hitch) cannot count as a long drive.
	if last and not TimeScale.isHeld() then
		self._driven += math.min(now - last, 0.5)
	end
	return self._driven >= TutorialConfig.Rig.Stage.StealTarget.HandBack
end

--[[ Stop staging the steal for the rest of this race and give the road back to the shipped spawner.

	LATCHED until `_standDown` (a new race or an unstaged beat), unlike `_gaveUp`, which a re-deal
	clears. BAIL and AIRBORNE alternate on every miss (`TutorialConfig.Rewind`) and a hand-back that
	reset there would shut the spawner again on the next attempt. The car already out there stays,
	as ordinary traffic. ]]
function TutorialDirector._handBack(self)
	self._handedBack = true
	self._stealPlaced = false
	self._target = nil
	self._placedAhead = nil
	self._traffic:setSpawning(true)
	self.log:info(
		string.format(
			"The jump was ignored for %ds of driving; the steal beat is on the shipped road now.",
			TutorialConfig.Rig.Stage.StealTarget.HandBack
		)
	)
end

--[[ Keep the target under the arc while the arc is in the air.

	=== WHY A PLACEMENT IS NOT ENOUGH ON ITS OWN =============================================

	`_placeStealTarget` aims at where a jump from HERE would land, and then several seconds pass
	before the jump happens: the objective card slides in, the DONE stamp plays over the last one,
	and the world does not stop until all of that is over. The player is driving throughout, closing
	on the car at the difference of their speeds, and the lead the placement worked out is not the
	lead they jump with. Measured, that gap was tens of studs, and once it was large enough the
	player passed the target before ever pressing Space — at which point no jump can reach it,
	because it is behind them.

	So the aim is finished in the air, where every unknown has become a number. `predictLanding` runs
	the live arc forward to its touchdown, and the car is given the pace that puts it there.

	IT IS A PACE CHANGE RATHER THAN A NUDGE ALONG THE ROAD, and that is the whole reason this is
	allowed to exist: the player is looking directly at this car for the two seconds it applies over.
	A position correction is a teleport and would be seen; a car that speeds up or slows down a
	little is a car in traffic. `PACE_EASE` keeps even that gradual, and `MinPace`/`MaxPace` keep it
	inside what a car on this road can plausibly do.

	ONLY WHILE THE ARC IS ACTUALLY FLYING. On a perch or a mount the car's speed is what the steal
	inherits and what the camera rides; nothing here may touch it then. ]]
function TutorialDirector._aimStealTarget(self)
	local steal, traffic, rec = self._steal, self._traffic, self._target
	if not (steal and traffic and rec and rec.hit and rec.hit.Parent and not rec.physical) then
		return
	end
	local state = steal:getFlight()
	if state ~= "air" then
		return
	end
	local landing, left = steal:predictLanding()
	--- Nothing useful to say in the last fraction of a second, and dividing by it would ask for a
	--- pace no car has.
	if not (landing and left and left > 0.15) then
		return
	end

	local dials = self:_stealDials()
	local want = math.clamp((landing - rec.along) / left, dials.MinPace, dials.MaxPace)
	traffic:paceCar(rec, rec.speed + math.clamp(want - rec.speed, -PACE_EASE, PACE_EASE))
end

-- === The loop ===============================================================

--[[ One look at the road. Everything in here is idempotent per beat: `_staged` remembers what has
	already been dealt for the beat that is live, so a tick that arrives twice inside one beat deals
	nothing twice.

	THE BEAT ID IS THE KEY, not a counter, so a beat that is re-served — a resume, a revive, a
	rejoin mid-run — deals its hand again rather than inheriting the last one's bookkeeping. ]]
function TutorialDirector._tick(self)
	local step = Players.LocalPlayer:GetAttribute(TutorialConfig.StepAttribute)

	if not TutorialConfig.isStaged(step) then
		self:_standDown()
		return
	end
	--- A staged beat with no road under it yet: the race is still loading, or this is the lobby half
	--- of a beat list. Nothing to deal onto and nothing to hand back.
	local car = self._road and self._road:getCar()
	if not car then
		return
	end

	--[[ A DIFFERENT CAR IS A DIFFERENT RACE, and the hand has to be forgotten between them.

		`_stealPlaced` deliberately outlives a beat change — the beat goes from BAIL to AIRBORNE in
		the middle of the arc the target was placed for, and a flag that reset there would put a
		second car on the road while the player was in the air over the first. Which left exactly one
		way out of it, `_standDown`, and `_standDown` only runs on a beat that is not staged.

		A WHIFFED STEAL IS BOTH OF THOSE AT ONCE. The player wrecks, the run ends, and the beat is
		still AIRBORNE — still staged — all the way back to the lobby and into the next race. So the
		next race began with `_stealPlaced` already true, the spawner still shut from the last one,
		and nothing ever put a car up: an empty road, an objective card asking for a steal, and no
		car in the world to steal. The tutorial could not be finished from there at all.

		The car instance is the honest signal because it is per-race and it is stable across
		everything that happens INSIDE one — the handoff redresses this same model rather than
		swapping it, so a steal does not read as a new race. ]]
	if car ~= self._raceCar then
		self._raceCar = car
		self:_standDown()
	end

	if self._beat ~= step then
		self._beat = step
		self._beatAt = os.clock()
		self._staged = {}
		--[[ The spawner stays shut for the whole staged stretch rather than per beat: it is one hand
			being dealt across several beats, and letting go between them would top the road up in
			the gaps.

			UNLESS THE STRETCH HAS ALREADY GIVEN THE ROAD BACK. `_gaveUp` outlives a beat change on
			purpose — BAIL and AIRBORNE are one attempt at one car, so a bail that could not be
			staged is an airborne that cannot be either — and re-shutting here would hand the next
			beat the empty road the last one had to be rescued from, with nothing left that would
			ever open it again. `_handedBack` is the same rule for a player who ignored the jump
			(see `_handBack`). ]]
		if not (self._gaveUp or self._handedBack) then
			self._traffic:setSpawning(false)
		end
	end

	if CLEAR_ON[step] then
		--- Every tick, not once: the beat can outlast the cars that were ahead when it started, and
		--- one that drifts back into the window from in front is one the player can still hit.
		self._traffic:clearAhead(TutorialConfig.Rig.Stage.ClearAhead)
		return
	end

	if step == "survive" then
		if not self._staged.survive then
			self._staged.survive = true
			--- Clear first, so the four cars are the only ones in the window rather than four more.
			self._traffic:clearAhead(TutorialConfig.Rig.Stage.SurviveLead)
			self:_dealSurvive()
		end
		return
	end

	--[[ BAIL and AIRBORNE share one job: there has to be a car in front of the player to take.

		It is done on BAIL — while the card is still asking for the jump — so that the car is out
		there, moving, and settled into its lane by the time anybody is above it. A car placed at the
		apex would appear inside the shot.

		AIRBORNE RETRIES IT rather than assuming it took, because there are two ways to arrive in the
		air without a target: a player who jumped before the placement landed, and a placement that
		found every lane occupied. Both are recoverable, and both are invisible from the card.

		`_attempts` turns "usually lands on the retry" into a report when it does not. This is the one
		thing in here whose failure a player experiences as the tutorial being broken, since the beat
		it feeds cannot be completed without a car to take.

		ONCE IT IS OUT THERE THE JOB CHANGES rather than ending: the placement was aimed at a jump
		that had not happened yet, and every tick after it is spent correcting that aim against the
		one that did. See `_aimStealTarget`. ]]
	if step == "bail" or step == "airborne" then
		--- The player was asked, got the world back, and kept driving. See `_ignoredTheJump`.
		if self._handedBack then
			return
		end
		if self:_ignoredTheJump() then
			self:_handBack()
			return
		end

		if self._stealPlaced then
			if not self:_targetLost() then
				self:_aimStealTarget()
				return
			end
			--[[ The car this beat was dealt for is gone and the player is driving again. Forget it
				and fall through to deal another, which is the whole of the fix — see `_targetLost`
				for the route that gets here and for why nothing else ever unlatched this. ]]
			self._stealPlaced = false
			self._target = nil
			self._placedAhead = nil
			self._attempts = 0
			self._gaveUp = false
			self.log:info("Steal target lost; dealing another.")
		end

		--[[ Staging this beat has been given up on, and the retries have to stop with it rather
			than carry on underneath. Not a tidy pairing — `_placeStealTarget` OPENS BY CLEARING
			everything ahead of the driver, so a retry running under a spawner we had just handed
			the road back to would delete the cars it let in, once every tick, and the player would
			watch the road try to refill and never manage it. Deal or get out of the way, never
			both. ]]
		if self._gaveUp then
			return
		end

		self._attempts += 1
		--[[ How long the player still gets to DRIVE before the world stops, which is what the
			placement has to lead by. `Settle` less however much of it has already gone — on the first
			look that is the whole of it, since `_beatAt` is stamped on the frame the beat arrives
			rather than on the next poll.

			NOT the beat's `Grace`, which is what this used to read and is only the last third of it:
			the card slides in and stamps DONE over the previous objective before the beat's own clock
			starts. See `Settle` in TutorialConfig for the measurement and for why being wrong about
			this looked like the placement being random.

			AIRBORNE gets nothing, and wants nothing: a retry from there is a player already in the
			air, with no driving left to do before the freeze. ]]
		local settle = if step == "bail" then TutorialConfig.Rig.Stage.StealTarget.Settle else 0
		local left = math.max(settle - (os.clock() - (self._beatAt or 0)), 0)
		if self:_placeStealTarget(left) then
			--- Our hand is back on the road, so the door closes behind it again. Idempotent, and it
			--- has to be said here rather than only on the beat change: a re-deal may be arriving
			--- after the giving-up branch below handed the road back.
			self._traffic:setSpawning(false)
			return
		end

		--[[ NOTHING COULD BE PUT DOWN, and after this long that is not a retry away from working.

			HAND THE ROAD BACK. The spawner is shut because the director is dealing, and a director
			that cannot deal is holding a door closed on an empty road for no reason — which is the
			state the "no cars to steal" report is a photograph of. What comes through it is an
			ordinary rolled car, which this beat has always been willing to accept: the objective is
			to take A car, and `_placeStealTarget` only exists to make the first one easy rather than
			to make it mandatory. A road the player can finish the tutorial on beats a choreographed
			one they cannot.

			Not on the first miss. A placement that loses a coin flip against an occupied lane
			usually lands on the very next tick, and flapping the spawner every 0.2s would deal cars
			into the clearance the retry is about to make. `GIVE_UP` is a second of honest trying
			first (five ticks at `INTERVAL`).

			STILL WARNED, and the warning moved here with the decision rather than staying at the old
			three-second mark: giving up IS the report now, and a second one three seconds later
			would be describing a state this branch has already left. A road the director could not
			deal onto is worth knowing about even though the player no longer pays for it. ]]
		if self._attempts >= GIVE_UP then
			self._gaveUp = true
			self._traffic:setSpawning(true)
			self.log:warn(
				"Could not put a steal target on the road after a second of trying — handing it back to the spawner so the beat is still finishable. Is the road full of obstacles here?"
			)
		end
	end
end

--[[ The staged stretch is over: hand the road back exactly as it was found.

	UNCONDITIONAL AND REPEATED, like every other release in this feature. This runs on the tick that
	first sees a non-staged beat and then does nothing on every tick after it, so a run that ends
	mid-beat, a skip, a wreck and a tutorial that finishes all reach it by the same path — and none
	of them has to be a path anybody remembered to write. ]]
function TutorialDirector._standDown(self)
	if not self._beat then
		return
	end
	self._beat = nil
	self._beatAt = nil
	self._staged = {}
	self._attempts = 0
	self._gaveUp = false
	self._handedBack = false
	self._driven = 0
	self._drivenAt = nil
	self._stealPlaced = false
	self._target = nil
	self._placedAhead = nil
	if self._traffic then
		self._traffic:setSpawning(true)
	end
end

TutorialDirector:withLifecycle({
	init = function(self)
		self._beat = nil
		--- The car the live hand was dealt for. A new one means a new race — see `_tick`.
		self._raceCar = nil
		--- When it arrived, so a placement can lead by the grace that is LEFT rather than by all of it.
		self._beatAt = nil
		--- What has already been dealt for the live beat. Keyed by beat, cleared when it changes.
		self._staged = {}
		self._attempts = 0
		--- Whether this beat has stopped trying to stage a target and handed the road back to the
		--- shipped spawner. Cleared with the rest of the hand — see `_tick` and `_standDown`.
		self._gaveUp = false
		--- Whether the player ignored the jump long enough that the steal beats stopped being
		--- staged for this race, and the seconds of driving counted toward it. See `_ignoredTheJump`.
		self._handedBack = false
		self._driven = 0
		self._drivenAt = nil
		--- Whether the car this run is going to be stolen is already out there. Deliberately NOT in
		--- `_staged`, which is cleared on every beat change — see `_placeStealTarget`.
		self._stealPlaced = false
		--- ...and which car that is, so its pace can be corrected while the player is in the air.
		self._target = nil
		--- ...and how far ahead it was put, which is the floor on how far `_targetLost` looks.
		self._placedAhead = nil
		--- Its own generator rather than the traffic controller's, so seeding one for a repeatable
		--- road does not have the tutorial's spacing consume rolls out of the population's.
		self._rng = Random.new()
	end,

	start = function(self)
		if not TutorialConfig.Rig.Stage.Enabled then
			return
		end
		--- Now, or when a bypassed session has the bypass lifted (the admin panel's Replay). See
		--- `TutorialConfig.whenOn`.
		TutorialConfig.whenOn(function()
			self:_boot()
		end)
	end,
})

--- Find the road and the traffic, and start watching the beat. Once, off `TutorialConfig.whenOn`.
function TutorialDirector._boot(self)
	if self._conn then
		return
	end
	self._road = Shard.get("RoadController")
	self._traffic = Shard.get("TrafficController")
	--- Optional, unlike the other two: without it the steal target falls back to a fixed lead
	--- rather than an aimed one, which is a worse beat and not a broken one.
	self._steal = Shard.get("StealController")
	if not (self._road and self._traffic) then
		self.log:warn("No RoadController/TrafficController; first runs will use the shipped road.")
		return
	end

	local accumulated = 0
	local seen = nil
	self._conn = RunService.Heartbeat:Connect(function(dt: number)
		accumulated += dt
		--[[ A BEAT CHANGE IS ACTED ON THE FRAME IT ARRIVES, and only a beat change — everything
			else still waits for `INTERVAL`. The poll is slow on purpose (see the header) and it
			was too slow for exactly one job: BAIL holds its card up for half a second and then
			stops the world, and the steal target has to be out on the road, aimed, and moving
			before that happens. Dealt up to a fifth of a second late, it was aimed from a
			position the player had already left, and the lead it was given was a lead they had
			already partly closed.

			One attribute read per frame to find out, which is the same read `_tick` makes and is
			cheaper than being wrong about where a car goes. ]]
		local step = Players.LocalPlayer:GetAttribute(TutorialConfig.StepAttribute)
		if step ~= seen then
			seen = step
			accumulated = INTERVAL
		end
		if accumulated < INTERVAL then
			return
		end
		accumulated = 0
		self:_tick()
	end)
end

TutorialDirector:withCleanup(function()
	if TutorialDirector._conn then
		TutorialDirector._conn:Disconnect()
		TutorialDirector._conn = nil
	end
	TutorialDirector:_standDown()
end)

return TutorialDirector
