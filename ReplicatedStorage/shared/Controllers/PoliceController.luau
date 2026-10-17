--[[
	PoliceController  (client)
	--------------------------
	THE CHASE. Two cruisers on your rear quarters and a helicopter ahead of you, arriving when the
	road reaches a police section or when you steal one of the best cars on it, and staying for the
	better part of a minute. While they are on you the road has one extra rule and it is the endless
	runner's: DON'T MAKE TWO MISTAKES IN A ROW. Every crash takes a bite out of the bar and two
	crashes close together take far more than two crashes apart do; every second on the brake bleeds
	it. They close as it falls, and when it is empty one of them comes off its station and PITs you
	off the road.

	It lives on the client for the reason the road, the traffic, the obstacles and the truck do
	(see `RoadController`): driving is solo, so every driver owns their own copy of the world and
	nothing here replicates. `PoliceService` publishes the two vehicles, marks the sections and
	ratifies the bust. Everything else happens on this machine.

	=== THE BAR IS THE ONLY THING THAT ENDS A RUN ==============================================

	One number, 1 for safe and 0 for caught. It is what the HUD draws, it is what a strike bites and
	a brake bleeds, and it is the only thing in this file that can end a run.

	That is worth stating as a rule because the obvious alternative is worse: a chase built out of
	several independent ENDINGS (a timer, a distance to the nearest cruiser, a crash count that
	arrests you on its own) has several ways to kill a player and no single thing they can watch.

	=== ...AND EVERY VEHICLE IS PLACED AGAINST ONE NUMBER TOO, WHICH IS NOT QUITE THAT ONE ======

	`_stationValue`, 0..2, and it is the bar with three pieces of theatre composed onto it. Nothing
	in it can bust a player, save one, or move the bar by a thousandth; all it decides is where the
	cars are, which is where the player actually reads their situation from.

	    the BAR       0..1, above. Drains on the brake, bitten by a crash.
	    the LEAD      +0..1, how far you are pulling away (`PoliceConfig.Lead`). Only above a full
	                  bar, and zeroed outright by a strike, so the two never overlap.
	    the SWOOP     a decaying dive PAST what the bar asks for, on the frame of a crash and sized
	                  by the bite it took (`PoliceConfig.Strikes.Swoop`).
	    the ARRIVAL   a ceiling for the opening seconds of a chase (`PoliceConfig.Entry`), so the
	                  cruisers sweep up level with the door before settling into a pursuit.

	So one chase is four shots out of the same window: they come up beside you as the sirens start,
	settle back, sink out of the bottom corners while you drive it clean, and dive back onto you the
	instant you touch anything. Under `PoliceConfig.Lineup.From` one of them stops holding station
	altogether and starts jockeying for the angle it needs to end the run from (`_lineupCar`).

	The picture out of the window and the bar on the screen still cannot disagree about how much
	trouble the player is in, because everything above is monotonic in the bar: more bar is always
	further away. What the extra travel buys is that the difference is VISIBLE - a cone's bite is a
	tenth of a bar, and a station that moved by a tenth of a bar is a station nobody can see move.

	TWO THINGS MOVE IT AND THEY ARE DIFFERENT SHAPES.

	  • A STRIKE is instantaneous. Every impact the road can hand you arrives at `reportStrike` and
	    takes a bite sized by how hard it was, multiplied if it lands inside
	    `PoliceConfig.Strikes.Chain.Window` of the last one. That multiplier is the whole feature:
	    it is what makes "a sideswipe" and "a sideswipe then a barrier" two different events rather
	    than the same event twice.
	  • THE DRAIN is continuous, and it is the brake. `PoliceConfig.drainRate` prices the car's
	    speed against `PoliceConfig.Floor` of what it cruises at, so leaning on the brake bleeds the
	    bar for as long as you are down there.

	    THE ONE SLOW SPELL IT DOES NOT PRICE IS A STEAL. The handoff hands you the traffic car's
	    speed, which is under the floor by construction, so a landed steal buys
	    `PoliceConfig.StealGrace` seconds in which being slow costs nothing (`reportSteal`). It
	    waives the drain alone: the refill still runs, and a crash still costs full price.

	    AND THE ONE THING THAT PAYS IT BACK FASTER IS THE BOTTLE. While nitro burns and the car is
	    over the floor, the refill runs faster, and so do three things that are not the bar: the
	    chase clock, the crash swoop and the lead (`_loop`, and `PoliceConfig.Nitro` for the
	    numbers and the balance). A crash during a burn still costs full price.

	THE CHAIN IS THE ONE PIECE OF STATE THAT IS NOT THE BAR, and it is deliberately not one: it is
	a timestamp and a count, it cannot end a run by itself, and everything it does it does by
	changing how much a strike takes out of the bar. A reader that wants to know how close to caught
	somebody is still has exactly one number to read.

	=== WHAT AN ARREST LOOKS LIKE ==============================================================

	The bar reaching zero does not end the run on that frame. `_beginPit` takes a cruiser off its
	station, puts its nose into the player's back quarter and spins the car; only when it is already
	sideways is `PoliceBusted` sent and the run ended. `PoliceConfig.Pit` carries the argument for
	that at length, and the mechanism is `TrafficController._knock`'s, pointed the other way: an
	impulse at a CONTACT POINT, so the lever arm decides the spin and nothing here scripts it.

	The one thing that is different from knocking a traffic car about is that the player's car is
	being STEERED. `DriveController` writes both assembly velocities every frame from the player's
	input, so an impulse landing on it is erased within about a stud (the same wall the slick
	hazards ran into: see `ObstacleController._onHit` on why they take grip instead of pushing).
	So the PIT suspends the shim first, which is the same lever `StealController` pulls to fly a
	bailed car. The run is over at that point; there is nothing left for the player to steer.

	=== WHY A PURSUER IS NOT A TRAFFIC CAR =====================================================

	It shares the road-frame trick and nothing else. Like traffic it keeps an `along` coordinate and
	a `cross` offset and is composed into a world CFrame every frame, so it is unaffected by tile
	recycles and rides `RoadController:onWorldShift` through a rebase. Unlike traffic it is not a
	population, it does not drive anywhere, it never spawns or culls, and it is not solid to
	anything at all (`PoliceConfig` note 2). It holds a STATION on the player, and the station is
	what moves.

	It follows that a pursuer will occasionally pass through a traffic car. That is accepted and it
	is the right trade: making them avoid traffic would mean either a per-frame query per pursuer or
	a lane-picking layer that competes with the player for the lane they are trying to use, and both
	buy less than they cost for a vehicle the player is looking at edge-on for a second at a time.
	Nothing about it can affect the run, because a pursuer cannot touch anything.

	=== WHY THEY ARE PLACED WHERE THEY ARE PLACED ==============================================

	Because the chase camera is 28 studs behind the car and 13 above it, looking 17 degrees down.
	A cruiser directly astern is either inside the player's car or behind the lens, and a helicopter
	directly overhead is above the top of the frame. Both are placed to be SEEN. The measurements
	and the arithmetic are in `PoliceConfig.Cruisers` and `PoliceConfig.Helicopter`; this file only
	obeys them.

	=== THE TWO WAYS ONE STARTS ================================================================

	THE ROAD asks for one. The police section comes up ahead (`_sectionAhead`), or enough tiles
	have passed since the last chase for them to come back (`_repeatDue`). Both are facts about
	where the player is, both are gated by `PoliceConfig.Cooldown`, and both are tested on every
	frame there is no chase running.

	THE PLAYER asks for the other. A steal that lands on one of the top rungs of the world's ladder
	is CALLED IN, which is `reportSteal` and `PoliceConfig.StealHeat` (there for what counts as
	worth coming for, and for why it is a rung rather than a price). It is stamped rather than
	armed on the spot, because a steal can land in any of the four states this file has: the call
	waits out `StealHeat.Delay`, is answered on the first frame there is no chase in the way of it,
	and lapses after `StealHeat.Window` if that frame never comes. It ignores the cooldown, and it
	never outlives a wreck.

	EVERYTHING DOWNSTREAM OF THE ARM IS THE SAME. One `_arm`, one bar, one rolled duration, one
	ending, one cooldown. `_armReason` rides along for the alert line and for nothing else, so a
	called-in chase cannot drift into being a second kind of chase.

	=== WHAT UNDOES A WRECK ====================================================================

	`RaceWrecked` tears the chase down and `RaceRevived` is its inverse: a revive out of a bust
	re-arms the chase with a fresh bar, which is the second wind the whole revive path exists to
	sell. A handler here that listened to one and not the other would be a system that stays
	switched off for the rest of a revived run, which is the failure `RaceService` warns about
	beside its own `RaceRevived`.

	HOUSE RULE: no wiki-style double-bracket links in this comment. The closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local DriveConfig = require(ReplicatedStorage.shared.Configs.DriveConfig)
--- For `HitBoxName` alone: the PIT needs the player's hull to place its contact point, and the
--- HitBox is the one part of a redressed car whose size is the car (`ObstacleConfig`'s header).
--- The mirror of `ObstacleController` requiring `PoliceConfig` for its `Cause`.
local ObstacleConfig = require(ReplicatedStorage.shared.Configs.ObstacleConfig)
local PoliceConfig = require(ReplicatedStorage.shared.Configs.PoliceConfig)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local WindConfig = require(ReplicatedStorage.shared.Configs.WindConfig)

local PoliceController = Shard.new("PoliceController"):withDependencies({ "RoadController" })

--- Seconds to wait for the published vehicles at boot. Generous, and off the critical path: this is
--- resolved in a spawned thread so a place that never publishes them costs one warning rather than
--- holding up every controller behind it.
local TEMPLATE_WAIT = 20

--[[ Frame-rate independent easing toward a target: the fraction of the remaining gap closed per
	second, expressed so that a 20fps frame and a 240fps frame land in the same place.

	Written here rather than borrowed because three different things ease at three different rates
	(the helicopter's station, the peel-off, and the bar's own smoothing), and an ease that is not
	frame-rate independent is the classic way a feature feels different on a phone.

	THE CRUISERS DO NOT USE THIS. They are placed with `spring` below, for the reason that one and
	`PoliceConfig.Cruisers.Lag` both give at length. ]]
local function ease(current: number, target: number, rate: number, dt: number): number
	return target + (current - target) * math.exp(-rate * dt)
end

--[[ A CRITICALLY DAMPED SPRING toward a target, returning the new value AND its new speed. What a
	cruiser is placed with, and the reason a crash no longer reads as a car being picked up and put
	down (`PoliceConfig.Cruisers.Lag` carries the argument in full).

	THE DIFFERENCE FROM `ease` ABOVE IS ENTIRELY IN THE FIRST TENTH OF A SECOND. Both curves start
	apart and finish together. An exponential ease is fastest on the frame the target moves and
	slows all the way in, so a station that STEPS - which is what the bar, the lead and the swoop all
	do on the frame of a crash - hands the car its top speed instantly and it appears at the new
	place rather than driving there. A critically damped spring carries a velocity, so it starts
	from whatever the car was already doing, accelerates, and settles without overshooting. It is
	the difference between a model being moved and a driver reacting, and it is the only thing this
	returns that `ease` cannot: the SPEED, which `_placeCar` needs anyway to point a cruiser at where
	it is going.

	CLOSED FORM AND EXACT, not an integration, so it is frame-rate independent for the same reason
	`ease` is and by the same test: 20fps and 240fps land on the same value. `x(t) = T + (a + b t)
	e^(-w t)` is the critically damped solution, with `a` the current offset and `b` fixed by the
	current speed; a hitched frame drives `e^(-w t)` to zero and lands exactly on the target with no
	speed left, which is the right way for this to fail. ]]
local function spring(current: number, speed: number, target: number, rate: number, dt: number): (number, number)
	local offset = current - target
	local slope = speed + rate * offset
	local decay = math.exp(-rate * dt)
	local moved = (offset + slope * dt) * decay
	return target + moved, (slope - rate * (offset + slope * dt)) * decay
end

--[[ The lowest point of a model, as a distance BELOW its pivot.

	`Model:GetBoundingBox` is not used, and deliberately: it measures in the model's PIVOT frame, so
	a model whose pivot is rotated reports a box that is not the one standing on the road. This
	sweeps the parts and projects each one's own box onto the world Y axis, which is exact for a
	part at any orientation and is the same projection `GetawayController` uses on the truck's bay.

	It is what puts a cruiser's wheels on the deck without this file knowing anything about how the
	modeller centred the mesh inside its part. ]]
local function dropBelowPivot(model: Model): number
	local pivotY = model:GetPivot().Position.Y
	local lowest = math.huge
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local half = part.Size * 0.5
			local x, y, z = part.CFrame.XVector, part.CFrame.YVector, part.CFrame.ZVector
			local halfY = math.abs(x.Y) * half.X + math.abs(y.Y) * half.Y + math.abs(z.Y) * half.Z
			lowest = math.min(lowest, part.Position.Y - halfY)
		end
	end
	if lowest == math.huge then
		return 0
	end
	return pivotY - lowest
end

--[[ Half of a part's extent along an arbitrary world axis.

	The same projection `dropBelowPivot` runs onto world Y, generalised, and exact for a part at any
	orientation. The PIT needs the player's car measured along the ROAD's axes rather than its own,
	because the car's own frame is about to stop meaning anything and because nothing in this file
	should have to know which way round a given rig's primary part faces.

	`Model:GetBoundingBox` is not used here for the reason it is not used there: it measures in the
	model's PIVOT frame, so a model whose pivot is rotated reports a box that is not the one on the
	road. ]]
local function halfAlong(part: BasePart, axis: Vector3): number
	local half = part.Size * 0.5
	local frame = part.CFrame
	return math.abs(frame.XVector:Dot(axis)) * half.X
		+ math.abs(frame.YVector:Dot(axis)) * half.Y
		+ math.abs(frame.ZVector:Dot(axis)) * half.Z
end

-- === Road frame =============================================================

--- World position of a point in the road frame, at deck height plus `lift`. The same composition
--- `TrafficController._worldPos` and `GetawayController._worldPos` use, and exact rather than
--- approximate because the road contract's ForwardAxis is a world axis.
function PoliceController._worldPos(self, alongCoord: number, crossOffset: number, lift: number): Vector3
	local info = self._info
	return info.forward * alongCoord
		+ info.cross * (info.driveCenter + crossOffset)
		+ Vector3.yAxis * (info.deckY + lift)
end

--- Our own car, via the seat we are sitting in. One line, and it is `RoadController`'s answer
--- rather than a second search of our own, so every client-side layer agrees which car is the
--- player's even while StreamingEnabled is taking the model away and giving it back.
function PoliceController._resolveCar(self): boolean
	local car = self._road:getCar()
	self._playerCar = car
	return car ~= nil and car.Parent ~= nil and car.PrimaryPart ~= nil
end

-- === Where everybody is supposed to be ======================================

--[[ How far through the arrival we are, as the CEILING it puts on the station value, or nil once it
	is over (`PoliceConfig.Entry`).

	nil rather than 2 on purpose, and two callers depend on it: `_stationValue` skips the clamp
	entirely, and `_loop` uses "the arrival is over" as one of the conditions for the lead to start
	building. Without that second reader a chase would begin earning ground during its own opening
	sweep and then snap straight out to a full lead on the frame the sweep released, which is the one
	way this beat can look like a bug rather than like driving. ]]
function PoliceController._entryCeiling(self, now: number): number?
	local entry = PoliceConfig.Entry
	if not (entry.Enabled and self._state == "live") then
		return nil
	end
	local since = now - (self._armedAt or 0)
	if since <= entry.Hold then
		return entry.Station
	end
	local out = (since - entry.Hold) / math.max(entry.Release, 1e-3)
	if out >= 1 then
		return nil
	end
	--- Smoothstepped, so the release leaves the hold gently and arrives on the bar's station gently.
	--- A linear one reads as the cars being let go of.
	local eased = out * out * (3 - 2 * out)
	return entry.Station + (1 - entry.Station) * eased
end

--[[ THE ONE NUMBER EVERY PURSUER IS PLACED AGAINST, 0..2. `PoliceConfig.station`'s header is the
	scale; this is what composes it, and it is the only thing allowed to.

	Four terms, in the order they were added and in the order they matter:

	  • THE BAR, 0..1, which is the rule. Everything else here is decoration on it and none of it
	    can bust a player, save a player or move the bar by a thousandth.
	  • THE LEAD, +0..1, which is what driving well looks like out of the window. It only exists
	    above a full bar, so the two never overlap and the sum is never ambiguous.
	  • THE SWOOP, a decaying dive on the frame of a crash (`Strikes.Swoop`), sized by the bite that
	    crash took. It goes PAST what the bar is asking for and drifts back out to it, which is what
	    makes a light hit visible: the bite a cone takes is a tenth of a bar, and a station that
	    moved by a tenth of a bar is a station nobody can see move.
	  • THE ARRIVAL, a ceiling rather than a term, so it can only ever bring them nearer.

	CLAMPED ONCE, AT THE END. Every term above is free to overshoot on the frame it lands; the clamp
	is what makes a swoop on top of an already-empty bar mean "as close as they go" rather than a
	negative station nothing downstream is expecting. ]]
function PoliceController._stationValue(self, now: number): number
	local value = self._bar + self._lead

	--[[ THE SWOOP HOLDS AT FULL BEFORE IT LETS GO, which the spring under the cruisers is what made
		necessary (`spring`, and `PoliceConfig.Cruisers.Lag`). It used to decay from the frame it
		armed, and against an ease that covered most of its ground immediately that was fine. A
		spring takes about a second to arrive, so a dive that starts retreating at once is a dive the
		car never reaches: the numbers would say 0.40 and the eye would see a fraction of it.

		`Hold` is roughly the spring's own trip, so the car gets all the way in, and the ramp out is
		smoothstepped so they leave gently and are gone by the end rather than sliding out at a
		constant rate and stopping dead.

		AGED RATHER THAN TIMED. `_swoopAge` is seconds of swoop, advanced by `_loop`, and it runs
		faster while nitro burns (`PoliceConfig.Nitro.SwoopScale`), which is the whole of how a
		lit bottle makes a dive fall short. Off the wall clock it could not be sped up. ]]
	local swoop = PoliceConfig.Strikes.Swoop
	if swoop and self._swoopAmount > 0 and swoop.Time > 0 then
		local since = self._swoopAge
		if since < swoop.Time then
			local hold = swoop.Hold or 0
			local left = 1
			if since > hold then
				local out = (since - hold) / math.max(swoop.Time - hold, 1e-3)
				left = 1 - out * out * (3 - 2 * out)
			end
			value -= self._swoopAmount * left
		end
	end

	local ceiling = self:_entryCeiling(now)
	if ceiling then
		value = math.min(value, ceiling)
	end

	return math.clamp(value, 0, 2)
end

-- === Strikes ================================================================

--[[ PUBLIC (`ObstacleController.applyImpact`). The player just hit something.

	ONE DOOR FOR EVERY HAZARD IN THE GAME, and it is deliberately not this file's job to know what
	came through it. `applyImpact` is already the single path every impact takes (obstacle clips,
	guardrail scrapes and `TrafficController`'s car clips all call it), so the strike is taken there
	and a hazard added tomorrow is priced by the police for free. All that arrives is the `Shake`
	the hazard asked for, which `PoliceConfig.strikeSeverity` turns into a 0..1; see
	`PoliceConfig.Strikes.Shake` for why that field and not `SpeedKeep`.

	THE CHAIN IS COUNTED HERE AND NOWHERE ELSE. A strike inside `Chain.Window` of the last one is
	one link deeper than that one was, and the depth multiplies the bite. It is counted off the
	CLOCK rather than off the bar, which is the distinction the whole rule rests on: the bar refills
	and would forgive, and the point of "too close together" is that the road does not.

	Every refusal below is the same refusal, which is that the player is not being marked right now:
	no chase, the panel is holding the bar, or the opening grace is still up. A chase that armed on
	the frame of a crash must not charge the player for a crash they were already committed to. ]]
--[[ In the getaway truck's shelter (`GetawayConfig.Shelter`, 2026-10-09)? While it is true a strike is
	not charged, the drain is waived and the arrest cannot begin: a car caught on the ramp is slow and
	touching things for reasons that are the truck's, and the screenshot that asked for this was a
	bust on exactly that. ]]
function PoliceController._sheltered(self): boolean
	local getaway = Shard.get("GetawayController")
	return getaway ~= nil and getaway:isSheltered()
end

--- Is a getaway truck on the road within `PoliceConfig.TruckClearance` of the player's car? Straight-
--- line studs; the road is straight enough that this is the distance along it to within a lane.
function PoliceController._truckNear(self): boolean
	local reach = PoliceConfig.TruckClearance or 0
	local getaway = Shard.get("GetawayController")
	local truck = if reach > 0 and getaway then getaway:getTruck() else nil
	local car = self._playerCar
	local hull = car and car.PrimaryPart
	return truck ~= nil and hull ~= nil and (truck.Position - hull.Position).Magnitude <= reach
end

function PoliceController.reportStrike(self, shake: number?)
	if self._state ~= "live" or self._held or not PoliceConfig.Strikes.Enabled or self:_sheltered() then
		return
	end
	local now = os.clock()
	if now < self._graceUntil then
		return
	end

	local chain = PoliceConfig.Strikes.Chain
	local links = if now - self._lastStrikeAt <= chain.Window then self._chainLinks + 1 else 0
	self._lastStrikeAt = now
	self._chainLinks = links
	self._struckAt = now
	self._swoopAge = 0

	local bite = PoliceConfig.strikeBite(PoliceConfig.strikeSeverity(shake), links)
	self._bar = math.clamp(self._bar - bite, 0, 1)
	self._refillHoldUntil = now + PoliceConfig.Strikes.Settle

	--[[ THE LEAD IS SPENT IN ONE FRAME, and it is spent BEFORE the bite rather than instead of it.
		A player who had pulled away and then hit something loses the ground they had earned AND
		pays full price for the crash, which is the whole reason the lead is a separate number from
		the bar (`PoliceConfig.Lead`). It is also the largest single movement anything in this file
		makes: from a full lead the cruisers come from half out of the bottom corner of the frame to
		inside the bar's station in about a second. ]]
	self._lead = 0

	--[[ ...and the swoop that carries them past it, sized off the BITE rather than off the severity
		so that the chain multiplies it for free: a chained hit is already over `Bite.Max` and clamps
		to the full dive, which is `Strikes.Chain` stated in position. ]]
	local swoop = PoliceConfig.Strikes.Swoop
	self._swoopAmount = if swoop
		then swoop.Amount * math.clamp(bite / math.max(PoliceConfig.Strikes.Bite.Max, 1e-3), 0, 1)
		else 0
end

--[[ NOTHING IS MOVED ON THE FRAME OF A STRIKE, and that is the point rather than an omission.

	There used to be a `_lunge` here: every cruiser was pushed 75% of the way to the station the new
	bar asked for, outright, on the frame of the hit, so that the crash and the closing read as one
	event rather than two. It was answering a real problem. It answered it by teleporting a car, and
	that is what it looked like: a cruiser that changes position without ever having had a speed
	does not read as a driver reacting, and because `_placeCar` aims each car at where it is going,
	the nose swung over on the frame after the jump and swung back a second later. A pivot, from a
	car that never turned a wheel.

	THE JOB IT WAS DOING IS NOW SHARED BY TWO THINGS THAT DO IT WITHOUT MOVING ANYTHING. The station
	itself dives further and holds there (`Strikes.Swoop`, above), and the cars are placed with a
	critically damped spring instead of an exponential ease (`spring`), so they leave from whatever
	speed they already had and accelerate into it. The crash and the closing are still one event.
	The closing is now something the player watches happen. ]]

-- === The steal: a grace, and a call =========================================

--[[ PUBLIC (`StealController.onStolen`). The player just landed a steal, on a car of this tier.

	THE SECOND DOOR IN THIS FILE THE ROAD KNOCKS ON, and it answers a steal with two things that
	point opposite ways: a GRACE, below, and for a car worth coming for a CALL to the police, at the
	bottom. Both are correct at once, and this is the only place that has to know that.

	THE GRACE FIRST, which is the opposite of `reportStrike` in every way that matters: a strike is
	the player being charged for something they did, and this is the chase declining to charge them
	for something the STEAL did. `StealConfig.Handoff.InheritVelocity` is 1, so a mount ends with the
	player doing whatever the car they took was doing (24 to 44 studs/s against a floor near 50), and
	the drain would otherwise start biting on the frame the flight ends.
	See `PoliceConfig.StealGrace` for the measurement and for why the window is the length it is.

	STAMPED RATHER THAN LATCHED, and never shortened. `math.max` so a steal landing inside a window
	already running (a chase that armed a moment ago, a second steal on top of the first) extends it
	instead of trading a long grace for a short one. It is the same composition `_graceUntil` and this
	one have with each other: both are read, and whichever is still up wins.

	DELIBERATELY NOT GATED ON `_state == "live"`. A steal taken with no chase on stamps a window that
	simply expires unread, and a steal taken a beat before a section arms is exactly the case a gate
	here would drop on the floor. The gate that matters is in the loop, where the bar is. ]]
function PoliceController.reportSteal(self, tier: number?)
	if not PoliceConfig.Enabled then
		return
	end
	local now = os.clock()
	self._stealGraceUntil = math.max(self._stealGraceUntil, now + PoliceConfig.StealGrace)

	--[[ ...AND THE OTHER HALF OF THE SAME DOOR, which is the exact opposite of a grace: a car good
		enough to be worth coming for calls the police (`PoliceConfig.StealHeat`).

		The two land on the same steal and they do not fight, because they are about different
		seconds. The grace is about the handoff, which arrives under the floor by construction; the
		call is about the forty seconds after that. A chase armed by a steal therefore opens with
		its drain waived, which is exactly the opening a chase armed on a car doing traffic pace
		ought to have.

		STAMPED HERE AND ANSWERED IN THE LOOP (`_callDue`). `_arm` is only reachable from a chase
		that is off, and a steal can land in any state, so a call made during a live
		chase, an arrest or a peel-off is a call that has to wait. `StealHeat.Window` is what
		decides whether it is still worth answering by the time it can be.

		`_active` gates it because a call is a piece of RACE state: outside a race there is no
		folder to parent a cruiser into, which is the same thing `debugArm` refuses on. ]]
	if self._active and not self._tutorialRun and PoliceConfig.isHighValueSteal(tier) then
		self._stealArmAt = now + PoliceConfig.StealHeat.Delay
	end
end

-- === Building a pursuer =====================================================

--[[ The two neon lamps on a cruiser's light bar, plus their spill lights.

	They are anchored parts parented INTO the model and never touched again except for colour and
	transparency: `Model:PivotTo` moves every part of a model rigidly, so a lamp placed once at the
	right offset rides the cruiser for the rest of the chase for free. That is the whole reason this
	is a build step and not a per-frame one.

	RED TAKES THE NEGATIVE SIDE AND BLUE THE POSITIVE because that is how the mesh is painted
	(`PoliceConfig.Cruisers.Bar`, measured). A lamp of the wrong colour over the wrong half of the
	bar does not read as a stylised light, it reads as a mistake. ]]
function PoliceController._buildBar(self, rec)
	local bar = PoliceConfig.Cruisers.Bar
	local light = PoliceConfig.Cruisers.Light
	local base = rec.root.CFrame

	for _, side in { { key = "lampRed", sign = -1, colour = bar.Red }, { key = "lampBlue", sign = 1, colour = bar.Blue } } do
		local lamp = Instance.new("Part")
		lamp.Name = "PoliceLamp"
		lamp.Size = bar.Size
		lamp.CFrame = base * CFrame.new(bar.X, bar.Y, bar.Z * side.sign)
		lamp.Anchored = true
		lamp.CanCollide = false
		lamp.CanQuery = false
		lamp.CanTouch = false
		lamp.CastShadow = false
		lamp.Material = Enum.Material.Neon
		lamp.Color = side.colour
		lamp.Parent = rec.model
		rec[side.key] = lamp

		if light.Enabled then
			local point = Instance.new("PointLight")
			point.Color = side.colour
			point.Range = light.Range
			point.Brightness = light.Brightness
			point.Shadows = false -- a shadow-casting light on a moving car is the most expensive
			point.Parent = lamp    -- thing this layer could possibly draw, for no visible gain
		end
	end
end

--[[ The helicopter's three extras: the rotor disc, the belly beacon and the searchlight.

	THE ROTOR DISC EXISTS BECAUSE THE AIRCRAFT IS ONE MESHPART. Its blades are modelled into the
	same geometry as its fuselage and cannot turn, and a static rotor is the first thing anyone
	notices about a hovering helicopter. The disc spins on top of them, which is how a rotor reads
	at speed anyway: the blades supply the shape and the disc supplies the blur.

	Roblox's cylinder runs along its own local X, so a horizontal disc is a cylinder rolled 90
	degrees about Z. It is the one part of a pursuer that is re-posed every frame, because it is the
	one part that has to move relative to the model rather than with it. ]]
function PoliceController._buildHeli(self, rec)
	local cfg = PoliceConfig.Helicopter
	local scale = cfg.Scale
	local base = rec.root.CFrame

	local rotor = Instance.new("Part")
	rotor.Name = "PoliceRotor"
	rotor.Shape = Enum.PartType.Cylinder
	rotor.Size = Vector3.new(cfg.Rotor.Thickness, cfg.Rotor.Radius * 2, cfg.Rotor.Radius * 2) * scale
	rotor.Anchored = true
	rotor.CanCollide = false
	rotor.CanQuery = false
	rotor.CanTouch = false
	rotor.CastShadow = false
	rotor.Color = cfg.Rotor.Color
	rotor.Transparency = cfg.Rotor.Transparency
	rotor.CFrame = base * CFrame.new(cfg.Rotor.Offset * scale)
	rotor.Parent = rec.model
	rec.rotor = rotor

	if cfg.Beacon.Enabled then
		local beacon = Instance.new("Part")
		beacon.Name = "PoliceBeacon"
		beacon.Shape = Enum.PartType.Ball
		beacon.Size = Vector3.one * (cfg.Beacon.Size * scale)
		beacon.Anchored = true
		beacon.CanCollide = false
		beacon.CanQuery = false
		beacon.CanTouch = false
		beacon.CastShadow = false
		beacon.Material = Enum.Material.Neon
		beacon.Color = PoliceConfig.Cruisers.Bar.Red
		beacon.CFrame = base * CFrame.new(cfg.Beacon.Offset * scale)
		beacon.Parent = rec.model
		rec.beacon = beacon

		local point = Instance.new("PointLight")
		point.Range = cfg.Beacon.Range
		point.Brightness = cfg.Beacon.Brightness
		point.Shadows = false
		point.Parent = beacon
		rec.beaconLight = point
	end

	if cfg.Search.Enabled then
		--[[ A part of its own, because a SpotLight shines out of a FACE and the face has to point
			at the player's car rather than wherever the airframe happens to be pointing. It is
			re-aimed every frame in `_placeHeli`, after the model has been moved.

			`Front` is the -Z face, which is what `CFrame.lookAt` already aims, so aiming this is one
			`lookAt` and no correction. ]]
		local emitter = Instance.new("Part")
		emitter.Name = "PoliceSearchlight"
		emitter.Size = Vector3.one * 0.6
		emitter.Anchored = true
		emitter.Transparency = 1
		emitter.CanCollide = false
		emitter.CanQuery = false
		emitter.CanTouch = false
		emitter.CastShadow = false
		emitter.Parent = rec.model
		rec.search = emitter

		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Angle = cfg.Search.Angle
		spot.Range = cfg.Search.Range
		spot.Brightness = cfg.Search.Brightness
		spot.Color = cfg.Search.Color
		spot.Shadows = false
		spot.Parent = emitter
	end
end

--[[ The siren, cloned onto a cruiser's root so it is POSITIONAL.

	`SoundService` is not Rojo synced, so the clip lives in the place with its `SoundId` left blank
	until an id is pasted in (`PoliceConfig.Sound`, and `SoundController`'s header for the
	convention). A missing group and a blank id are both silence and neither is an error: the chase
	works today and gets its siren the moment somebody fills it in.

	Warned about ONCE per session rather than per chase. A group that does not exist would otherwise
	put two lines in the output every time a chase arms, for a state that is expected. ]]
function PoliceController._attachSiren(self, rec)
	local template = self._sirenTemplate
	if template == nil then
		local group = SoundService:FindFirstChild(PoliceConfig.Sound.GroupName)
		template = (group and group:FindFirstChildWhichIsA("Sound")) or false
		self._sirenTemplate = template
		if not template then
			self.log:info(string.format(
				"No SoundService.%s to play; the chase runs silent until one is authored.",
				PoliceConfig.Sound.GroupName
			))
		end
	end
	if not template then
		return
	end

	local siren = template:Clone()
	siren.Name = "PoliceSiren"
	siren.Looped = true
	siren.Volume = PoliceConfig.Sound.Volume
	siren.RollOffMode = Enum.RollOffMode.InverseTapered
	siren.RollOffMinDistance = PoliceConfig.Sound.RollOffMin
	siren.RollOffMaxDistance = PoliceConfig.Sound.RollOffMax
	siren.Parent = rec.root
	siren:Play()
	rec.siren = siren
end

--[[ Clone one pursuer and put it in its opening position.

	`NoseYawDeg` is the one piece of art knowledge in here and it is a rotation, not a guess: both
	models were rendered head on to find which way they face. The cruiser's mesh has its nose along
	its part's local +X and the helicopter's along local -Z, and `CFrame.lookAt` aims -Z, so the
	cruiser needs a quarter turn and the helicopter needs nothing. Held as a CFrame on the record so
	the per-frame path is one multiply.

	Everything else the record carries is measured rather than assumed: `dropBelowPivot` supplies
	the deck fit, and `PoliceConfig` note 5 says where the rest of the numbers came from. ]]
function PoliceController._spawnPursuer(self, kind: string, index: number, side: number)
	local template = self._templates[kind]
	if not template then
		return nil
	end

	local model = template:Clone()
	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not root then
		model:Destroy()
		return nil
	end
	model.PrimaryPart = root

	local isCar = kind == "car"
	local cfg = if isCar then PoliceConfig.Cruisers else PoliceConfig.Helicopter
	local rec = {
		kind = kind,
		model = model,
		root = root,
		side = side,
		noseFix = CFrame.Angles(0, math.rad(cfg.NoseYawDeg), 0),
		--- Its own place in every sine below, so two cruisers on the same station never move as one
		--- object mirrored. Golden-ratio spaced rather than random: it is reproducible, and it never
		--- accidentally hands two of them the same phase.
		phase = (index * 0.618) % 1,
		--- ...and the same idea for the light bar, which is a square wave rather than a sine and so
		--- has only two places to be. See `_flashOn`.
		alternate = index % 2 == 0,
		lateral = 0,
		--- The two speeds the spring in `_placeCar` carries between frames, one per axis. Zero is
		--- the honest opening value and it is what makes the arrival out of `EntryStuds` a car
		--- pulling out and accelerating rather than a car already at full chat.
		gapSpeed = 0,
		crossSpeed = 0,
	}

	--[[ The opening position, and it is the station this pursuer will be holding a second from now
		with `EntryStuds` of extra distance behind it. From there the station easing IS the arrival:
		there is no slide-in animation and no spawn timer, because a car that is already easing onto
		a station comes out of the fog on its own.

		A cruiser enters from BEHIND (a negative offset down the road) and the helicopter from
		AHEAD and higher, because that is the direction each of them is going to be holding station
		from. Entering from the wrong side would have the helicopter fly backwards past the player
		to take up a position in front of them. ]]
	--- The station it is easing ONTO, which is the arrival's if there is one (`PoliceConfig.Entry`)
	--- and the ordinary one if not. Taken here rather than assumed to be 1 so the opening sweep is
	--- one continuous motion: out of the fog and straight up to the door, with no waypoint in it.
	local opening = if PoliceConfig.Entry.Enabled then PoliceConfig.Entry.Station else 1

	if isCar then
		self:_buildBar(rec)
		self:_attachSiren(rec)
		rec.lift = dropBelowPivot(model) * cfg.Scale
		rec.gap = -PoliceConfig.station(cfg.Standoff, opening) - cfg.EntryStuds
		rec.cross = self._playerCross + side * PoliceConfig.station(cfg.Lateral, opening)
	else
		self:_buildHeli(rec)
		rec.lift = 0 -- the helicopter's height is stated outright rather than measured off the deck
		rec.gap = PoliceConfig.station(cfg.Ahead, opening) + cfg.EntryStuds
		rec.cross = self._playerCross
		rec.height = PoliceConfig.station(cfg.Height, opening) + cfg.EntryRise
	end
	rec.along = self._playerAlong + rec.gap

	--- Scaled LAST, after the lamps and the rotor are in, so `Model:ScaleTo` carries them with the
	--- model rather than leaving a full-size light bar on a shrunken car.
	if cfg.Scale ~= 1 then
		model:ScaleTo(cfg.Scale)
	end

	model.Parent = self._folder
	table.insert(self._pursuers, rec)
	return rec
end

-- === Placing a pursuer ======================================================

--[[ Which half of the flash cycle we are in: true is the red half.

	ONE CLOCK FOR THE WHOLE CHASE, read the same way by every pursuer and by the HUD, so nothing in
	the beat can drift out of step with anything else. `alternate` inverts it for every other
	vehicle, which is what stops two cruisers reading as one light source mirrored: in unison they
	pulse the screen red and then blue together, and alternating they trade, which is what a pair of
	real cars does and is the difference between "police" and "a strobe".

	`math.floor` on the wall clock rather than an accumulator, for `WeatherController._armLightning`'s
	reason inverted: this is asked several times a frame and the cheapest correct answer is the one
	that needs no state at all. ]]
function PoliceController._flashOn(self, alternate: boolean?): boolean
	local red = math.floor(os.clock() / math.max(PoliceConfig.Cruisers.FlashTime, 1e-3)) % 2 == 0
	return if alternate then not red else red
end

--- Paint one cruiser's bar for the current half of the flash. Cheap enough to run unconditionally
--- (two transparency writes and two booleans) and written that way on purpose: a guard comparing
--- against the last state would be one more thing to reset on a revive.
function PoliceController._paintBar(self, rec, redLit: boolean)
	local off = PoliceConfig.Cruisers.Bar.OffTransparency
	if rec.lampRed then
		rec.lampRed.Transparency = if redLit then 0 else off
		local light = rec.lampRed:FindFirstChildWhichIsA("PointLight")
		if light then
			light.Enabled = redLit
		end
	end
	if rec.lampBlue then
		rec.lampBlue.Transparency = if redLit then off else 0
		local light = rec.lampBlue:FindFirstChildWhichIsA("PointLight")
		if light then
			light.Enabled = not redLit
		end
	end
end

--[[ One cruiser, one frame.

	=== THE ALONG AXIS SPRINGS A GAP, THE CROSS AXIS SPRINGS A POSITION ======================

	They look like the same line of code and they must not be. Any filter chasing a MOVING target
	settles at a permanent offset behind it, and the two axes have very different speeds under them:

	  • ALONG, the target moves at whatever the player is doing, which is 70 to 115 studs/s all
	    race. That is tens of studs of standing extra distance at any rate this would sensibly use,
	    so the station would be a function of how fast the player happens to be going. That is not a
	    small error and it points the wrong way: flooring it would put the police FURTHER back the
	    faster you drove. Measured, before this was fixed: a cruiser asked for 15 studs back sat at
	    39, and the helicopter asked for 74 ahead sat at 37. So the GAP is what is filtered, and the
	    player's motion never enters it.
	  • CROSS, the target only moves when the player changes lane, which is a transient that
	    averages to nothing. Here the lag is the whole point: it is what makes a cruiser follow you
	    across rather than being welded to your door. So this one filters the POSITION.

	THE FILTER IS A CRITICALLY DAMPED SPRING (`spring`), not the exponential `ease` the helicopter
	and the peel-off still use, and `PoliceConfig.Cruisers.Lag` carries the argument for it at
	length. In one line: the stations STEP on the frame of a crash, an ease answers a step at its
	top speed, and a car that is at top speed on the frame it starts moving does not look like a car.

	IT IS AIMED AT WHERE IT IS GOING, not down the road. Composing the heading out of the two rates
	the way `TrafficController._place` does keeps a car that is sliding across to cut you off
	pointed into the slide, which is most of what makes it look driven rather than dragged. The
	spring hands that rate over directly, which is the second thing it buys: the old frame
	difference was noise at 240fps and a staircase at 20, and the heading wore both. ]]
function PoliceController._placeCar(self, rec, dt: number, now: number, value: number, lineup: number?)
	local cfg = PoliceConfig.Cruisers
	local info = self._info
	local surge = math.sin((now * cfg.Surge.Hz + rec.phase) * math.pi * 2) * cfg.Surge.Studs
	local weave = math.sin((now * cfg.Weave.Hz + rec.phase) * math.pi * 2) * cfg.Weave.Studs

	local wantGap = -PoliceConfig.station(cfg.Standoff, value) + surge
	local wantCross = self._playerCross + rec.side * (PoliceConfig.station(cfg.Lateral, value) + weave)

	--- ...and once the HUD says LOSING YOU, back past the lens and out of shot (`Cruisers.Shaken`).
	--- Read off the same `LeadFrom` the caption swaps at, so the words and the window cannot disagree.
	local shaken = cfg.Shaken
	if shaken and value > 1 then
		local from = PoliceConfig.Hud.Bar.LeadFrom or 0
		local t = math.clamp((value - 1 - from) / math.max(shaken.Span, 1e-3), 0, 1)
		wantGap -= shaken.Studs * t * t * (3 - 2 * t)
	end
	--- One rate per axis, and they are spring rates rather than ease rates (`spring`, and the long
	--- note on `Cruisers.Lag`). `Along` is the slower of the two on purpose: closing the gap is the
	--- axis the player is being asked to watch, and following a lane change is not.
	local lagAlong = cfg.Lag.Along
	local lagAcross = cfg.Lag.Across

	--[[ ...and the tell, blended OVER the station rather than replacing it (`PoliceConfig.Lineup`).

		Only ever one car gets a non-zero blend and `_loop` is what decides which, by the same rule
		the arrest itself uses, so the car that spends the last of the bar jockeying for an angle is
		the car that comes and takes it. Everything is a lerp toward the lineup rather than a switch
		to it, including the `Lag`: the tell coming on is a car making its mind up, and a station
		that swapped over on one frame would read as the model being moved rather than driven.

		THE FEINT IS ON THE GAP AND NOT ON THE CROSS. At `Side` the cruiser is about a stud clear of
		the player's bodywork, so a dart across would be a collision; a dart along the road is a car
		closing on the quarter and backing off it again, which is both safe and the thing a pursuit
		driver is actually doing while they wait for the angle. It is folded to 0..1 rather than left
		as a sine so it only ever CLOSES: `Behind` is the far end of the swing, for the reason the
		config gives. ]]
	if lineup and lineup > 0 then
		local set = PoliceConfig.Lineup
		local feint = (math.sin((now * set.Feint.Hz + rec.phase) * math.pi * 2) + 1) * 0.5 * set.Feint.Studs
		wantGap += (-(set.Behind - feint) - wantGap) * lineup
		wantCross += ((self._playerCross + rec.side * set.Side) - wantCross) * lineup
		lagAlong += (set.Lag - lagAlong) * lineup
		lagAcross += (set.Lag - lagAcross) * lineup
	end

	--[[ ...and the deck, which is the one thing every offset above is composed WITHOUT.

		Each of them is measured from the PLAYER, so a player hugging the outer lane (`Lanes` run to
		30 on a deck 73 wide) puts the outside cruiser 22 studs past the edge of the road and leaves
		it driving on air. It has always been reachable and `Cruisers.Lateral.Lead` is what made it
		likely, because that one is wide enough to reach the edge from the middle.

		HALF A CRUISER OF MARGIN, so the clamp lands the car's flank on the edge rather than its
		centre. A cruiser held here is a cruiser that has run out of road, which is what it looks
		like: it stops spreading and rides the line while the other one goes on out. ]]
	local margin = info.driveWidth * 0.5 - cfg.EdgeMargin
	if margin > 0 then
		wantCross = math.clamp(wantCross, -margin, margin)
	end

	rec.gap, rec.gapSpeed = spring(rec.gap, rec.gapSpeed, wantGap, lagAlong, dt)
	rec.along = self._playerAlong + rec.gap
	rec.cross, rec.crossSpeed = spring(rec.cross, rec.crossSpeed, wantCross, lagAcross, dt)
	--- The spring's OWN speed rather than a frame difference of the position it just wrote. Same
	--- number, and it is the one the heading below is composed out of, so it is worth saying why:
	--- a difference divided by `dt` is noise at 240fps and a step at 20, and a heading built out of
	--- it jitters at one end and staircases at the other. This one is analytic at any frame rate.
	rec.lateral = rec.crossSpeed

	local pos = self:_worldPos(rec.along, rec.cross, rec.lift)
	--- The forward term is the player's own speed rather than the cruiser's, because a pursuer that
	--- is exactly matching you has no road speed of its own to steer by and would point sideways
	--- whenever it changed lanes. Floored so a chase that arms while the car is barely moving still
	--- has a direction to compose against.
	local dir = info.forward * math.max(self._playerSpeed, 20) + info.cross * rec.lateral
	rec.model:PivotTo(CFrame.lookAt(pos, pos + dir) * rec.noseFix)
end

--[[ The helicopter, one frame.

	Three things move it: the station against the bar (ahead and above), a slow lateral drift, and a
	bob. The bank is derived from the drift's own RATE rather than tracked, so it stays correct for
	whatever the drift is retuned to, and the nose-down pitch comes up with the bar because an
	aircraft that is closing on something is nose down.

	The rotor and the searchlight are posed AFTER the model has been moved, in that order and for
	two different reasons: the rotor has to turn relative to a model that has just been placed, and
	the searchlight has to be aimed at a car whose position this frame is already known. ]]
function PoliceController._placeHeli(self, rec, dt: number, now: number, value: number)
	local cfg = PoliceConfig.Helicopter
	local info = self._info

	local drift = math.sin((now * cfg.Drift.Hz + rec.phase) * math.pi * 2) * cfg.Drift.Studs
	local bob = math.sin((now * cfg.Bob.Hz + rec.phase * 2) * math.pi * 2) * cfg.Bob.Studs

	--- The along axis eases a GAP and the other two ease positions, for the reason `_placeCar`
	--- spells out at length. It bites hardest here: at `Lag` 1.8 the aircraft would have sat forty
	--- studs nearer than asked for, and at the closing end of the bar that is behind the player.
	local wantGap = PoliceConfig.station(cfg.Ahead, value)
	local wantCross = self._playerCross + drift
	local wantHeight = PoliceConfig.station(cfg.Height, value) + bob

	local lastCross = rec.cross
	rec.gap = ease(rec.gap, wantGap, cfg.Lag, dt)
	rec.along = self._playerAlong + rec.gap
	rec.cross = ease(rec.cross, wantCross, cfg.Lag, dt)
	rec.height = ease(rec.height, wantHeight, cfg.Lag, dt)
	rec.lateral = if dt > 0 then (rec.cross - lastCross) / dt else 0

	local pos = self:_worldPos(rec.along, rec.cross, rec.height)
	--- Banked into the drift and pitched down as it closes. Both are applied in the aircraft's own
	--- frame after the heading, so neither can turn into a yaw.
	local bank = math.clamp(rec.lateral / math.max(cfg.Drift.Studs, 1e-3), -1, 1) * math.rad(cfg.BankDeg)
	local pitch = math.rad(cfg.PitchDeg) * (1 - math.clamp(value, 0, 1))
	local frame = CFrame.lookAt(pos, pos + info.forward) * rec.noseFix * CFrame.Angles(-pitch, 0, bank)
	rec.model:PivotTo(frame)

	if rec.rotor then
		rec.spin = ((rec.spin or 0) + cfg.Rotor.Speed * dt) % (math.pi * 2)
		rec.rotor.CFrame = rec.root.CFrame
			* CFrame.new(cfg.Rotor.Offset * cfg.Scale)
			* CFrame.Angles(0, rec.spin, 0)
			* CFrame.Angles(0, 0, math.pi * 0.5)
	end
	if rec.search and self._playerCar and self._playerCar.PrimaryPart then
		rec.search.CFrame = CFrame.lookAt(rec.search.Position, self._playerCar.PrimaryPart.Position)
	end
end

-- === Arming =================================================================

--[[ Is there a marked police section close enough in front of us to start a chase?

	Walks the live road rather than asking which tile index we are on, because the marked tile is a
	piece of ART and the road is what knows where the art currently is. A tile's pivot sits at its
	START (`RoadController` lays them out that way and `ObstacleLayout` measures from the same
	place), so this is a straight range test: we are inside the window that opens `ArmLead` studs
	before the section and closes at the far end of it.

	The closing end matters as much as the opening one. Without it, a section the player has already
	driven past would go on satisfying the test for the rest of the run, and every cooldown
	expiring would immediately re-arm off a tile that is now a mile behind them. ]]
function PoliceController._sectionAhead(self): boolean
	local info = self._info
	for _, tile in self._road:getSegments() do
		if tile.Parent and tile:GetAttribute(PoliceConfig.SectionAttribute) then
			local start = self._road:along(tile:GetPivot().Position)
			if self._playerAlong >= start - PoliceConfig.ArmLead and self._playerAlong < start + info.segmentLength then
				return true
			end
		end
	end
	return false
end

--[[ ...and the two triggers that are not the art.

	`FallbackTile` is for a world that has no police section yet, which is three of the four
	(`PoliceConfig`'s note on it). `RepeatTiles` is for the fact that the City's section is reached
	exactly once: the road's segments are a progression, so tile 4 is on the road while the tile
	index is 9 to 11 and never again. Without a repeat, the answer to "can the police come back?"
	would be no, in the one world that has police at all.

	The repeat only starts counting after a chase has actually happened, so the police section is
	still the thing that introduces them. After that you are a car they are looking for. ]]
function PoliceController._repeatDue(self): boolean
	local tileIndex = self:_tileIndex()
	if not tileIndex then
		return false
	end
	if self._chases == 0 then
		local fallback = PoliceConfig.FallbackTile
		return type(fallback) == "number" and tileIndex >= fallback
	end
	local every = PoliceConfig.RepeatTiles
	if type(every) ~= "number" or every <= 0 then
		return false
	end
	return tileIndex >= (self._lastChaseTile or 0) + every
end

--[[ ...and the one trigger that is not the road at all: is there a steal call to answer on this
	frame, and is it still worth answering?

	Three states rather than two, which is what makes it worth a function: no call outstanding, a
	call whose `StealHeat.Delay` has not run out yet, and a call that has been waiting longer than
	`StealHeat.Window` because a chase, an arrest or a peel-off was in the way for all of it. The
	last of those is DROPPED here rather than allowed to arm late. A chase arriving a minute after
	the car that caused it is not the beat this feature is, and the player would read it as the road
	having armed one.

	It cannot answer true over a run that is ending: `_onWrecked` clears the call outright, which is
	the same thing its `math.huge` cooldown does for the two road triggers. ]]
function PoliceController._callDue(self, now: number): boolean
	if self._stealArmAt <= 0 or now < self._stealArmAt then
		return false
	end
	if now > self._stealArmAt + PoliceConfig.StealHeat.Window then
		self._stealArmAt = 0
		return false
	end
	return PoliceConfig.StealHeat.IgnoreCooldown or now >= self._cooldownUntil
end

--- Which stretch of road we are on, as the tile's own `TileIndex`, or nil off the live road. The
--- same range test `TrafficController._tileIndexAt` runs, against our own along-coordinate.
function PoliceController._tileIndex(self): number?
	local info = self._info
	for _, tile in self._road:getSegments() do
		if tile.Parent then
			local start = self._road:along(tile:GetPivot().Position)
			if self._playerAlong >= start and self._playerAlong < start + info.segmentLength then
				local index = tile:GetAttribute("TileIndex")
				return if type(index) == "number" then index else nil
			end
		end
	end
	return nil
end

--- Start one. Everything that decides how a chase goes is stamped here and nothing reads a config
--- roll twice, so the duration a chase is going to run for is fixed the moment it starts rather
--- than being re-rolled on whatever frame it is next asked about.
function PoliceController._arm(self, reason: string?)
	local now = os.clock()
	self._state = "live"
	--- "road" for either of the road's own triggers, "steal" for a car that was called in. Read by
	--- the HUD's alert and by nothing else (`getChase`), because a chase is a chase.
	self._armReason = reason or "road"
	self._bar = 1
	--- ...and the two placement-only numbers that ride on it, both of which are a previous chase's
	--- business (`_stationValue`). The lead especially: arming into one would open a chase with the
	--- cruisers already dropping away.
	self._lead = 0
	self._swoopAmount = 0
	--- A chase is a clean sheet: the chain a player carried into it from the last one would price
	--- their first crash off a mistake the police were not there for.
	self._lastStrikeAt = -math.huge
	self._chainLinks = 0
	self._refillHoldUntil = 0
	self._struckAt = -math.huge
	self._swoopAge = math.huge
	self:_endPit()
	self._graceUntil = now + PoliceConfig.Grace
	self._endsAt = now + self._rng:NextNumber(PoliceConfig.Duration[1], PoliceConfig.Duration[2])
	--- What nitro has taken off `_endsAt` so far, against `PoliceConfig.Nitro.MaxCut`. Per chase.
	self._nitroCut = 0
	self._armedAt = now
	self._chases += 1
	self._lastChaseTile = self:_tileIndex() or self._lastChaseTile or 0
	--- A call is consumed by ANY arm and not only by the one it caused. A road chase that got to
	--- the frame first has already given the player the thing the call was going to give them, and
	--- leaving it stamped would hand them a second chase the moment this one ended.
	self._stealArmAt = 0

	self:_spawnPursuer("car", 1, -1)
	if PoliceConfig.Cruisers.Count > 1 then
		for index = 2, PoliceConfig.Cruisers.Count do
			self:_spawnPursuer("car", index, if index % 2 == 0 then 1 else -1)
		end
	end
	if PoliceConfig.Helicopter.Enabled then
		self:_spawnPursuer("heli", 1, 1)
	end

	self:_reportChase(true, self:_sheltered())
end

--[[ Tell the server a chase began or ended (`PoliceService`'s chase record, which `GetawayService`
	refuses a bank against: `GetawayConfig.PoliceLock`). Sent on a change only. `live` is the same
	"chased" the getaway's own lock reads, so "leaving" is false; `sheltered` is its grace. Nothing
	on this side waits on it or reads it back. ]]
function PoliceController._reportChase(self, live: boolean, sheltered: boolean?)
	local graced = live and sheltered == true
	if live == self._reportedLive and graced == self._reportedGraced then
		return
	end
	self._reportedLive = live
	self._reportedGraced = graced
	self:getRemoteEvent("PoliceChase"):Fire(live, graced)
end

--[[ The chase is over and the player survived it. Send everything away rather than deleting it.

	`PullAway` is a beat, not a tidy-up: the cruisers fall back down the road and the helicopter
	climbs out of frame, and only then is anything destroyed. A chase that ended by every vehicle
	vanishing on one frame would be the only thing in this game that does, and it would make the
	forty seconds before it read as a scripted sequence rather than as police who gave up. ]]
function PoliceController._lose(self)
	if self._state ~= "live" then
		return
	end
	self._state = "leaving"
	self._leaveAt = os.clock() + PoliceConfig.PullAway.Time
	self._cooldownUntil = self._leaveAt + PoliceConfig.Cooldown
	self:_reportChase(false)
	for _, rec in self._pursuers do
		if rec.siren then
			rec.siren:Stop()
		end
		--- Where the peel-off starts from (`_stepLeaving`). A pair already shaken off behind the lens
		--- must keep falling back, not ease forward to `Standoff.Far` and into shot first.
		rec.leaveGap = rec.gap
	end
end

--[[ They have you. Spin the car first if there is a car to spin, and report it either way.

	The PIT is not a second ending and it cannot fail into one: `_beginPit` answers false for every
	reason it might not be able to run (no car, no road frame, no cruiser left to do it, the feature
	switched off) and the bust is reported on this frame exactly as it always was. There is no path
	through here that leaves a player with an empty bar and a live race. ]]
function PoliceController._bust(self)
	if PoliceConfig.Pit.Enabled and self:_beginPit() then
		return
	end
	self:_reportBust()
end

--[[ Give back everything a PIT took, whether or not the PIT finished.

	TWO THINGS ARE HELD and both of them are held on purpose: the obstacle course is suspended so
	the road cannot turn an arrest into an ordinary wreck, and the tyres are softened so the car
	slides rather than digging in (`_hit` has the argument for each).

	IT IS DELIBERATELY NOT CALLED BY `_reportBust`, which is the one non-obvious thing here. At the
	moment the bust is sent the car is still sideways and still moving, and putting the grip back on
	that frame stops it dead under the banner. So the hold outlives the report by the length of the
	wreck beat, and `RaceWrecked` is what releases it. The cost of that is one more thing a revive
	has to undo, which is why every exit goes through this one function.

	The drive shim needs nothing given back: `RaceWrecked` tears it down and `DriveController`
	clears its own suspension there. Idempotent, and a no-op when no PIT ever ran. ]]
function PoliceController._endPit(self)
	self._pit = nil
	if self._pitTyres then
		for _, saved in self._pitTyres do
			--- A destroyed part is locked and would throw. `Parent` is the cheap test for one, and a
			--- car that has been taken away has nothing that needs its grip back anyway.
			if saved.part.Parent then
				saved.part.CustomPhysicalProperties = saved.was
			end
		end
		self._pitTyres = nil
	end
	if self._pitHeldCourse then
		self._pitHeldCourse = false
		local course = Shard.get("ObstacleController")
		if course then
			course:setSuspended(false)
		end
	end
end

--[[ Tell the server and await the ending (2026-10-12).
	`off` can arm a new chase on the next frame, refilling the bar while driving is still suspended.
	`busted` cannot: only the wreck, revive or race lifecycle releases this wait. Send before stopping
	the visual sirens so a destroyed sound cannot prevent the server receiving the arrest. ]]
function PoliceController._reportBust(self)
	if not self._active or self._state == "busted" then
		return
	end
	self._state = "busted"
	--- `_pit` and not `_endPit`: the car is still sliding and what the arrest is holding has to
	--- outlive the report by the length of the wreck beat. See `_endPit`.
	self._pit = nil
	self:getRemoteEvent("PoliceBusted"):Fire()
	for _, rec in self._pursuers do
		if rec.siren then
			rec.siren:Stop()
		end
	end
end

-- === The PIT ================================================================

--[[ WHICH SIDE AN ARREST COMES IN FROM, +1 or -1 on the road's own cross axis.

	THE ONE DECISION IN THE WHOLE ARREST, and it is made about the ROAD rather than about the cars.
	The impulse pushes the player away from the cruiser, so a PIT delivered from the inside spins
	them toward the edge they are already nearest, and a spin that regularly put the player over the
	edge would turn an arrest into a fall: a different wreck with a different cause, out of a beat
	that is supposed to end in one specific way. So the cruiser used is the one on the OUTSIDE, and
	the car goes toward the middle of the deck.

	`_playerCross` is signed off the road's own cross axis and a pursuer's `side` is composed against
	that same axis in `_placeCar`, so the two agree by construction: matching the sign of one to the
	other is the whole of the arithmetic. `PoliceConfig.Pit.FromSide` overrides it for a photograph.

	PULLED OUT OF `_beginPit` SO THE TELL CAN ASK THE SAME QUESTION (`_lineupCar`). The car that
	spends the last of the bar setting an arrest up has to be the car that then performs it, and the
	only way to guarantee that is for both to be reading one rule. ]]
function PoliceController._pitSide(self): number
	local forced = PoliceConfig.Pit.FromSide
	if type(forced) == "number" and forced ~= 0 then
		return if forced > 0 then 1 else -1
	end
	return if self._playerCross >= 0 then 1 else -1
end

--- ...and the cruiser sitting on it: the outside one if there is one, and any cruiser rather than
--- none (a `Cruisers.Count` of 1 puts the only car on the left, and an arrest from the wrong side
--- beats no arrest at all). nil only when there is no cruiser left on the road at all.
function PoliceController._pitCar(self)
	local side = self:_pitSide()
	local chosen
	for _, rec in self._pursuers do
		if rec.kind == "car" then
			chosen = chosen or rec
			if rec.side == side then
				return rec
			end
		end
	end
	return chosen
end

--[[ THE TELL (`PoliceConfig.Lineup`): which cruiser is setting the arrest up, and how far into it
	it is. nil and 0 for the whole of an ordinary chase.

	STATELESS, AND THAT IS THE FEATURE. It is recomputed every frame off the bar and off which side
	of the deck the player is on, so a player who crosses the centre line while one car is lining up
	hands the job to the OTHER one: the first drifts back to its station and the second comes down
	onto the quarter. That is correct rather than merely convenient, for the reason `_pitSide` gives,
	and it is what makes the tell worth having: it can be answered by moving.

	Gated on `Pit.Enabled` as well as on its own switch, because a tell for an arrest that is never
	going to happen is a lie told in the most expensive place available. ]]
function PoliceController._lineupCar(self)
	local set = PoliceConfig.Lineup
	if not (set.Enabled and PoliceConfig.Pit.Enabled) or set.From <= 0 then
		return nil, 0
	end
	local blend = (set.From - self._bar) / set.From
	if blend <= 0 then
		return nil, 0
	end
	return self:_pitCar(), math.clamp(blend, 0, 1)
end

--[[ Take a cruiser off its station and set it at the player's back quarter. False = cannot.

	IT IS THE CAR THE TELL WAS ALREADY USING, because both ask `_pitCar`. So the approach below
	starts from wherever the lineup had it (`PoliceConfig.Lineup.Behind`, a few studs further back
	than the contact point) rather than from an ordinary station, and the arrest reads as the end of
	something that had been building rather than as a car teleporting into position.

	The chosen cruiser keeps every piece of state it already had. It is not respawned, not moved and
	not re-parented: the approach below is the same `gap` and `cross` it has been holding all chase,
	driven from somewhere else for half a second. ]]
function PoliceController._beginPit(self): boolean
	local primary = self._playerCar and self._playerCar.PrimaryPart
	if not (primary and self._info) then
		return false
	end

	local chosen = self:_pitCar()
	if not chosen then
		return false
	end

	self._state = "pit"
	self._pit = {
		rec = chosen,
		startedAt = os.clock(),
		fromGap = chosen.gap,
		fromCross = chosen.cross,
		hitAt = nil,
	}
	-- 2026-10-12: a streamed-out car or failed visual update must not hold an arrest forever.
	-- The extra second leaves the normal approach/spin untouched; identity cancels stale timers.
	local pit = self._pit
	task.delay(PoliceConfig.Pit.Approach + PoliceConfig.Pit.Spin + 1, function()
		if self._active and self._state == "pit" and self._pit == pit then
			self.log:warn("Police arrest visuals stalled; completing the bust.")
			self:_reportBust()
		end
	end)
	return true
end

--[[ The approach and the hit, one frame of it.

	THE OTHER PURSUERS GO ON HOLDING AN EMPTY-BAR STATION while this happens, rather than being
	frozen or hidden. The arrest is a shot of two cars and a helicopter doing three different things,
	and a road that empties out around the one that is working would read as the chase having ended
	before the thing that ends it.

	The chosen car is driven by a straight interpolation rather than by `_placeCar`'s ease, and that
	is the one place in this file that is true. An ease never arrives: it asymptotes, and the whole
	of this beat is the arrival landing on a known frame so the impulse can be applied on it. Eased,
	the contact would happen a little late and a little short, and how late and how short would
	depend on the frame rate.

	Smoothstepped, so the car leaves its station gently and closes hard, which is the shape a driver
	setting a PIT up actually makes. ]]
function PoliceController._stepPit(self, dt: number, now: number)
	local pit = self._pit
	if not pit then
		self:_reportBust() -- cannot happen; reported rather than stalled if it ever does
		return
	end
	local cfg = PoliceConfig.Pit
	local info = self._info
	local rec = pit.rec

	for _, other in self._pursuers do
		if other ~= rec then
			if other.kind == "car" then
				self:_placeCar(other, dt, now, 0)
				self:_paintBar(other, self:_flashOn(other.alternate))
			else
				self:_placeHeli(other, dt, now, 0)
			end
		end
	end

	local t = math.clamp((now - pit.startedAt) / math.max(cfg.Approach, 1e-3), 0, 1)
	local eased = t * t * (3 - 2 * t)
	local lastCross = rec.cross
	--- A gap is NEGATIVE for a car that is behind (see `_placeCar`), so a positive `Behind` of 13
	--- studs is a gap of -13. Stated in the config the way a person would say it out loud.
	rec.gap = pit.fromGap + (-cfg.Behind - pit.fromGap) * eased
	rec.cross = pit.fromCross + ((self._playerCross + rec.side * cfg.Side) - pit.fromCross) * eased
	rec.along = self._playerAlong + rec.gap
	rec.lateral = if dt > 0 then (rec.cross - lastCross) / dt else 0

	local pos = self:_worldPos(rec.along, rec.cross, rec.lift)
	--- Pointed into its own closing rate, exactly as `_placeCar` composes a heading, which is what
	--- makes the last of the approach read as a car turning in rather than sliding sideways.
	local dir = info.forward * math.max(self._playerSpeed, 20) + info.cross * rec.lateral
	rec.model:PivotTo(CFrame.lookAt(pos, pos + dir) * rec.noseFix)
	self:_paintBar(rec, self:_flashOn(rec.alternate))

	if not pit.hitAt then
		if t >= 1 then
			pit.hitAt = now
			self:_hit(rec)
		end
		return
	end
	if now - pit.hitAt >= cfg.Spin then
		self:_reportBust()
	end
end

--[[ The contact. Hand the car to physics and put an impulse into its back quarter.

	`TrafficController._knock`'S MECHANISM, POINTED THE OTHER WAY, and the shared shape is the point:
	NOTHING HERE DECIDES HOW THE CAR ROTATES. The impulse goes in at a point on the bodywork, so the
	lever arm, and therefore the spin, is whatever the geometry says it is. A heavier body comes
	round more slowly than a light one because it is heavier, not because this file was told about
	it, and `Push` is multiplied by the assembly's own mass for the same reason it is over there: it
	keeps the number denominated in studs per second rather than in impulse units.

	SUSPENDING THE SHIM IS NOT OPTIONAL AND IT COMES FIRST. `DriveController._lane` writes both
	assembly velocities every frame from the player's input, so an impulse applied before the shim
	is off buys about a stud of travel before the lane ease erases it. It is the same wall the slick
	hazards hit from the other side (`ObstacleController._onHit`), and it is why they take grip
	rather than pushing the car. There is nothing to give back afterwards: the bust ends the run,
	`RaceWrecked` tears the shim down and `DriveController._teardown` clears the flag itself.

	MEASURED AGAINST THE ROAD, NOT AGAINST THE CAR. Which flank is being hit, where the back of the
	car is, and which way the shove points are all composed out of `info.forward` and `info.cross`,
	so none of it depends on which way round a given rig's primary part happens to face, and none
	of it goes wrong as the car starts to come round, because it is all read once, here. ]]
function PoliceController._hit(self, rec)
	local car = self._playerCar
	local primary = car and car.PrimaryPart
	if not (primary and self._info) then
		return
	end
	local cfg = PoliceConfig.Pit
	local info = self._info

	if self._drive then
		self._drive:suspend()
	end

	--[[ ...and stop the ROAD being able to take this ending away.

		A car sweeping sideways at 85 studs/s clips everything in the lane it is crossing, and any
		one of those is priced in HP by the server. So an arrest could quietly become an ordinary
		wreck on the last second of a beat that exists to end one specific way, and which one the
		player got would depend on whether the PIT happened to land on a course.

		It is the same suspension `StealController` uses while a bailed car is being flown through
		the geometry it is nominally inside, for the same reason: the car is not being DRIVEN
		through this, so it must not be charged for it. `_endPit` puts it back, and every exit from
		this state goes through `_endPit`. ]]
	local course = Shard.get("ObstacleController")
	if course then
		course:setSuspended(true)
		self._pitHeldCourse = true
	end

	--[[ ...and let go of the road, which is the difference between a spin and a car hitting a wall.

		`PoliceConfig.Pit.TyreGrip` carries the measurement at length. The short version is that
		this chassis grips laterally hard enough that a car yawed past about twenty five degrees
		scrubs all of its speed off in half a second, so the stock tyres turn every value of `Push`
		into the same abrupt stop. Softened, the same impulse produces the shot: round to backwards,
		still sliding, still losing speed as the banner lands.

		SAVED PER PART, INCLUDING THE nil. `CustomPhysicalProperties` is nil on a part that is using
		its material's defaults, and writing a made-up table back would be worse than leaving it
		alone. `_endPit` puts back exactly what was found. ]]
	local grip = cfg.TyreGrip
	if grip then
		self._pitTyres = {}
		for _, part in car:GetDescendants() do
			if part:IsA("BasePart") and part.Name == "Wheel" and part.Parent and part.Parent.Name:find("Suspension") then
				local was = part.CurrentPhysicalProperties
				table.insert(self._pitTyres, { part = part, was = part.CustomPhysicalProperties })
				part.CustomPhysicalProperties =
					PhysicalProperties.new(was.Density, grip.Friction, was.Elasticity, grip.Weight, was.ElasticityWeight)
			end
		end
	end

	--- The hull rather than the primary part, because a redressed car's root is a chassis component
	--- and the HitBox is the one part whose size is the CAR (`ObstacleConfig`'s header). Falling
	--- back to the root keeps this working on a rig that has not got one, just less precisely placed.
	local hull = car:FindFirstChild(ObstacleConfig.HitBoxName, true)
	if not (hull and hull:IsA("BasePart")) then
		hull = primary
	end
	--- +1 when the cruiser is on the road's +cross side of us. Taken from where the cruiser actually
	--- IS rather than from its `side`, so a PIT forced from the far side by `FromSide` still shoves
	--- the player the way the car that hit them was pointing.
	local flank = if rec.cross >= self._playerCross then 1 else -1
	local flankDir = info.cross * flank

	--- Measured off the HULL's centre and not the root's. A redressed car's primary part is a
	--- chassis component sitting a little off the car's true centre, and a contact point placed
	--- from it would be off by that much on both axes at once.
	local contact = hull.Position
		+ flankDir * halfAlong(hull, info.cross)
		- info.forward * (halfAlong(hull, info.forward) * cfg.Quarter)
	--- Away from the cruiser and a little up. The lift is `Knock.Lift`'s job done here: it takes
	--- just enough weight off the inside wheels that the spin breaks traction instead of the tyres
	--- holding the car straight through it. Small. This is not a launch.
	local dir = (-flankDir + Vector3.yAxis * cfg.Lift).Unit
	primary:ApplyImpulseAtPosition(dir * (cfg.Push * primary.AssemblyMass), contact)

	--[[ ...and what it FEELS like, through the one door every impact in this game goes through.

		The kind handed over is mechanically empty on purpose: `SpeedKeep` of 1 and no `SideKick` or
		`Yaw`, so `applyImpact` contributes nothing to the car's motion and the impulse above is the
		only thing moving it. Two systems shoving the same car would be two answers to the question
		the contact point exists to settle. What is wanted from it is the shake and the smoke puff,
		which are the two things it owns and this file has no business rebuilding.

		It cannot come back round as a strike: `reportStrike` refuses anything that is not a live
		chase, and by here the state is `pit`. ]]
	local obstacles = Shard.get("ObstacleController")
	if obstacles then
		local side = if flankDir:Dot(primary.CFrame.RightVector) >= 0 then 1 else -1
		obstacles:applyImpact(side, { SpeedKeep = 1, SideKick = 0, Yaw = 0, Shake = cfg.Shake }, 1, flankDir, "Car")
	end
end

-- === The loop ===============================================================

--[[ How fast this car has to be going to keep the police off, in studs per second.

	`getTopSpeed` answers in the rig's `MaxSpeed` units, which are NOT studs per second: the
	conversion is `WindConfig.StudsPerMaxSpeed`, which is where that measurement is kept and how to
	re-take it. Boost is divided back out because the floor is a fraction of what the car does with
	NOTHING HELD: a floor measured against the boosted ceiling would make holding accelerate a
	requirement rather than an option, and the beat is meant to be about not stopping.

	nil while the car has not declared a `MaxSpeed` yet, which is the first frames of a race.
	`PoliceConfig.drainRate` reads that as "not draining", because a chase that cannot measure the
	player must never be allowed to bust them. ]]
function PoliceController._cruiseSpeed(self): number
	local dial = self._drive and self._drive:getTopSpeed()
	if not dial then
		return 0
	end
	local boost = if DriveConfig.AllowBoost then DriveConfig.BoostSpeedScale else 1
	return dial * WindConfig.StudsPerMaxSpeed / math.max(boost, 1e-3)
end

--- ...and the fraction of it the police are watching for. Both readers want the cruise itself as
--- well - the drain measures how far UNDER the floor you are and the lead how far OVER it, and the
--- second of those needs the top of the range to scale against - so the division is one line up.
function PoliceController._floorSpeed(self): number
	return self:_cruiseSpeed() * PoliceConfig.Floor
end

function PoliceController._loop(self, dt: number)
	if not self._active or self._state == "busted" then
		return
	end
	local info = self._road:getRoadInfo()
	if not (info and self:_resolveCar()) then
		return -- no road or no car yet; there is nothing to hold station on
	end
	self._info = info

	local primary = self._playerCar.PrimaryPart
	local position = primary.Position
	self._playerAlong = position:Dot(info.forward)
	self._playerCross = position:Dot(info.cross) - info.driveCenter
	--[[ Along the ROAD and not along the nose, for `WindConfig`'s reason: a nose-relative reading
		picks up sideways velocity, and sustained hard steering ratchets it past what the car is
		actually doing down the road. A speed floor measured that way would be free to anybody
		willing to saw at the wheel. ]]
	self._playerSpeed = primary.AssemblyLinearVelocity:Dot(info.forward)

	local now = os.clock()

	if self._state == "off" then
		-- No chases on the tutorial's run (`TutorialConfig.isTutorialRun`), latched at race start.
		if self._tutorialRun then
			return
		end
		--- Not with the getaway truck in reach (`PoliceConfig.TruckClearance`). Before `_callDue`, so a
		--- pending call-in is held rather than spent while the truck is there.
		if self:_truckNear() then
			return
		end
		--- The call goes first. It is the trigger with an expiry on it, and the two road ones are
		--- true for a whole tile at a time, so testing them first would let a section swallow the
		--- chase the player earned and print the wrong line over it.
		if self:_callDue(now) then
			self:_arm("steal")
		elseif now >= self._cooldownUntil and (self:_sectionAhead() or self:_repeatDue()) then
			self:_arm()
		end
		return
	end

	if self._state == "leaving" then
		self:_stepLeaving(dt, now)
		return
	end

	--- The shelter grace ends on the first frame the player is outside the shelter, which is when
	--- the getaway's own lock closes (`GetawayController._stepPoliceLock`). The server has to hear it.
	if self._reportedGraced and not self:_sheltered() then
		self:_reportChase(true, false)
	end

	--[[ The arrest is already happening. It runs the pursuers itself and it ends by REPORTING the
		bust, so it deliberately sits above everything below: the bar is at zero and re-testing it
		here every frame would send a second bust for the length of the spin. ]]
	if self._state == "pit" then
		local ok, err = pcall(self._stepPit, self, dt, now)
		if not ok then
			-- The player is already caught; broken theatre must still reach the normal server ending.
			self.log:warn(string.format("Police arrest visuals failed; completing the bust: %s", tostring(err)))
			self:_reportBust()
		end
		return
	end

	--[[ THE BOTTLE, asked once and answered for every term below that reads it
		(`PoliceConfig.Nitro`). One question, "is nitro burning AND actually moving you", and the
		second half is not decoration: `isBurning` stays true for a player wedged against debris
		with the key held, and a chase that ran its clock down for a car going nowhere would be
		paying out in the one situation the drain exists to punish.

		`NitroController` already answers false whenever the player is not driving (a bail, a frozen
		beat, a wreck), so that is not asked again here. ]]
	local floorSpeed = self:_floorSpeed()
	local nitro = PoliceConfig.Nitro
	local escaping = nitro.Enabled
		and self._nitro ~= nil
		and self._nitro:isBurning()
		and floorSpeed > 0
		and self._playerSpeed >= floorSpeed

	--[[ ...and the one thing it buys that changes how long this lasts. `_endsAt` is pulled in rather
		than a second clock kept beside it, so the test at the bottom of this function is still the
		only thing that ends a chase. Counted against `MaxCut` per chase, so no run of near misses
		topping the bottle up can take more off than that. Not gated on `_held`: the panel's hold
		freezes the bar, and the duration runs on through it. ]]
	if escaping then
		local cut = math.min(dt * (nitro.ClockScale - 1), nitro.MaxCut - self._nitroCut)
		if cut > 0 then
			self._endsAt -= cut
			self._nitroCut += cut
		end
	end

	--[[ THE BAR, and the one condition under which it does not move: the player is not driving.

		`isDriving` is false in three situations that all mean the same thing here: the shim is not
		installed, the car is suspended (a bail, with StealController flying it), or the world is
		held still (a tutorial beat, the entry freeze). In every one of them the car is anchored, and
		an anchored assembly goes on reporting whatever velocity it was frozen at forever
		(see `WindConfig`'s note on the same trap). A bar that read that number would either drain
		through a hold the player cannot act in or refill through one they are not driving in, and
		both are wrong for the same reason: the player is not being asked a question, so they must
		not be being marked on the answer. ]]
	local driving = self._drive == nil or self._drive:isDriving()
	--- `_held` is the admin panel's freeze and is false in every ordinary session. It stops the
	--- bar moving and nothing else, so a held chase still runs its duration out (`debugHold`).
	if driving and not self._held and now >= self._graceUntil then
		local rate = PoliceConfig.drainRate(self._playerSpeed, floorSpeed)
		--[[ ...and the one thing a STEAL does to it, which is waive the drain and only the
			drain. The handoff hands the player the traffic car's speed and that is under the
			floor by construction, so the seconds after a mount are seconds the player did not
			choose to be slow in (`PoliceConfig.StealGrace`, and `reportSteal` for the door).
			Written as a rate of zero rather than as a skip of the whole block so that a car
			already back over the floor goes on REFILLING through it: the point of the window is
			that a steal is a way out, and one that only paused the clock would not be. ]]
		if rate > 0 and (now < self._stealGraceUntil or self:_sheltered()) then
			rate = 0
		end
		--- ...and the bottle, which speeds the REFILL and nothing else (`Nitro.RefillScale`). It
		--- still waits out the settle below: a lit bottle does not get to skip the second in which
		--- the player reads what the crash cost.
		if rate < 0 and escaping then
			rate *= nitro.RefillScale
		end
		--[[ ...and the one thing a strike does to the drain, which is hold the REFILL for
			`Strikes.Settle`. `drainRate` answers a negative number for refilling, so this is one
			comparison, and it is deliberately only that one: a bar that is still DRAINING goes on
			draining straight through the hold. A player who crashes and then sits there under the
			floor has made two mistakes, and forgiving the second because of the first would be the
			settle turning into a shield. ]]
		if not (rate < 0 and now < self._refillHoldUntil) then
			self._bar = math.clamp(self._bar - rate * dt, 0, 1)
		end
	end

	--[[ THE LEAD: the same question the bar asks, pointed the other way. Not "how close am I to
		being caught" but "am I getting away with it" (`PoliceConfig.Lead`). It only moves above a
		FULL bar, so the two are never both running and the sum the stations are read off
		(`_stationValue`) is never ambiguous about which half of the beat the player is in.

		EVERY CONDITION HERE IS ONE OF THE BAR'S, REUSED, and that is the argument for the list
		rather than an accident of it: a player is earning ground exactly when there is nothing left
		for them to be recovering from. Driving, not frozen by the panel, the opening grace over, the
		strike settle expired, the arrival finished, the bar full. `PoliceConfig.leadRate` is handed
		that one answer and prices the rest off speed, so there is no second clock in here to drift.

		THE ARRIVAL IS IN THE LIST FOR A SPECIFIC REASON. Without it a chase would spend its opening
		sweep quietly earning lead behind the ceiling holding the cars at the player's door, and then
		snap out to a full lead on the frame that ceiling released - the one way this beat can look
		like a fault rather than like driving. ]]
	local lead = PoliceConfig.Lead
	if lead.Enabled and self._state == "live" then
		local gaining = driving
			and not self._held
			and self._bar >= 1
			and now >= self._graceUntil
			and now >= self._refillHoldUntil
			and self:_entryCeiling(now) == nil
		local rate = PoliceConfig.leadRate(self._playerSpeed, floorSpeed, self:_cruiseSpeed(), gaining)
		--- Scaled on the way UP only (`Nitro.LeadScale`). The collapse is what a mistake costs, and a
		--- lit bottle must not soften it.
		if rate > 0 and escaping then
			rate *= nitro.LeadScale
		end
		self._lead = math.clamp(self._lead + rate * dt, 0, 1)
	else
		self._lead = 0
	end

	--- The swoop's own clock (`_stationValue`), which a lit bottle runs faster (`Nitro.SwoopScale`).
	self._swoopAge += dt * (if escaping then nitro.SwoopScale else 1)

	--- One number for every vehicle out of the window (`_stationValue`), and one cruiser allowed to
	--- ignore it because it is setting the arrest up (`_lineupCar`). Both are answered once, here,
	--- rather than per pursuer: two cars asking `_lineupCar` on the same frame would be two chances
	--- for them to disagree about which of them is the one doing it.
	local value = self:_stationValue(now)
	local lineupRec, lineupBlend = self:_lineupCar()
	for _, rec in self._pursuers do
		--- Every other vehicle inverted, so a pair of cruisers trade colours rather than pulsing
		--- together. See `_flashOn`.
		local redLit = self:_flashOn(rec.alternate)
		if rec.kind == "car" then
			self:_placeCar(rec, dt, now, value, if rec == lineupRec then lineupBlend else 0)
			self:_paintBar(rec, redLit)
		else
			self:_placeHeli(rec, dt, now, value)
			if rec.beacon then
				rec.beacon.Color = if redLit then PoliceConfig.Cruisers.Bar.Red else PoliceConfig.Cruisers.Bar.Blue
				rec.beacon.Transparency = if redLit then 0 else 0.35
				if rec.beaconLight then
					rec.beaconLight.Color = rec.beacon.Color
				end
			end
		end
	end

	--- The BAR and not `value`: the swoop and the arrival both push that number around for looks,
	--- and neither of them is allowed anywhere near the thing that ends a run.
	--- Held while the player is in the truck's shelter (`_sheltered`): an empty bar that reaches the
	--- ramp is still a bust if they drive away, and a bank if they get in. Re-tested every frame.
	if self._bar <= 0 and not self:_sheltered() then
		self:_bust()
	elseif now >= self._endsAt then
		self:_lose()
	end
end

--[[ The peel-off. The cruisers drop back down the road and the helicopter climbs, both on the same
	0..1, and the whole chase is destroyed when it reaches 1.

	It runs on the same station composition everything else does, so a pursuer leaving is still tied
	to the road frame and still rides a rebase. What changes is only what it is holding station on:
	a point behind and above, moving away. ]]
function PoliceController._stepLeaving(self, dt: number, now: number)
	local pull = PoliceConfig.PullAway
	local left = math.max(self._leaveAt - now, 0)
	local t = 1 - (left / math.max(pull.Time, 1e-3))

	for _, rec in self._pursuers do
		if rec.kind == "car" then
			--- The gap, not the position, exactly as `_placeCar` does and for the same reason: a
			--- peel-off eased against a moving car would drop back at a rate set by how fast the
			--- player is going rather than by `PullAway`.
			local from = math.min(-PoliceConfig.Cruisers.Standoff.Far, rec.leaveGap or 0)
			rec.gap = ease(rec.gap, from - pull.Studs * t, 2.4, dt)
			rec.along = self._playerAlong + rec.gap
			rec.cross = ease(rec.cross, self._playerCross + rec.side * PoliceConfig.Cruisers.Lateral.Far, 2.4, dt)
			local pos = self:_worldPos(rec.along, rec.cross, rec.lift)
			rec.model:PivotTo(CFrame.lookAt(pos, pos + self._info.forward) * rec.noseFix)
			--- The bar goes dark as they give up, which is the clearest possible statement that the
			--- rule is off. It happens before they are out of sight on purpose.
			self:_paintBar(rec, false)
			if rec.lampRed then
				rec.lampRed.Transparency = PoliceConfig.Cruisers.Bar.OffTransparency
				local light = rec.lampRed:FindFirstChildWhichIsA("PointLight")
				if light then
					light.Enabled = false
				end
			end
		else
			self:_placeHeli(rec, dt, now, 1)
			rec.height += pull.Rise * t * dt
			if rec.beaconLight then
				rec.beaconLight.Enabled = false
			end
			if rec.beacon then
				rec.beacon.Transparency = 0.6
			end
			if rec.search then
				local spot = rec.search:FindFirstChildWhichIsA("SpotLight")
				if spot then
					spot.Enabled = false
				end
			end
		end
	end

	if left <= 0 then
		self:_clearPursuers()
		self._state = "off"
	end
end

-- === Lifecycle ==============================================================

function PoliceController._clearPursuers(self)
	for _, rec in self._pursuers do
		if rec.siren then
			rec.siren:Stop()
		end
		if rec.model then
			rec.model:Destroy()
		end
	end
	table.clear(self._pursuers)
end

--[[ A rebase moved the road out from under us. Shift with it.

	CHEAPER HERE THAN ANYWHERE ELSE THAT DOES THIS, because a pursuer's position is a GAP from the
	player and a gap survives a rebase untouched: the next frame re-derives `_playerAlong` from the
	car, which the rebase has already moved, and every vehicle lands correctly with nothing having
	been corrected. Traffic has to shift its own coordinate because a traffic car's position is
	absolute; ours is not.

	WHAT IS STILL NEEDED IS THE FRAME ITSELF. This runs inside the rebase, and the models are not
	re-placed until this controller's own Heartbeat handler comes round, which may be after
	`RoadController`'s. A pursuer left where it was for that one frame is a police car nine tiles
	away, visible for 16 milliseconds, which is exactly long enough to read as a glitch. The
	`PivotTo` is rigid, so a cruiser's lamps and a helicopter's rotor go with it.

	`_playerAlong` is corrected for the same one frame, so anything that reads it before the next
	loop sees the shifted world rather than the old one.

	Listeners are called inside the rebase frame and must not yield. Nothing here does. ]]
function PoliceController._onWorldShift(self, shift: Vector3)
	if not (self._active and self._info) then
		return
	end
	local delta = shift:Dot(self._info.forward)
	if delta == 0 then
		return
	end
	self._playerAlong += delta
	for _, rec in self._pursuers do
		rec.along += delta
		rec.model:PivotTo(rec.model:GetPivot() + shift)
	end
end

function PoliceController._onRaceStart(self, world: number?)
	self:_teardown()
	self._tutorialRun = TutorialConfig.isTutorialRun(Players.LocalPlayer:GetAttribute(TutorialConfig.StepAttribute))
	if not (PoliceConfig.Enabled and self._road) then
		return
	end
	if not (self._templates.car or self._templates.heli) then
		return -- nothing was published; warned about once at boot
	end

	local folder = Instance.new("Folder")
	folder.Name = PoliceConfig.FolderName
	folder.Parent = workspace
	self._folder = folder

	self._active = true
	self._state = "off"
	self._bar = 1
	self._lead = 0
	self._swoopAmount = 0
	self:_endPit()
	self._lastStrikeAt = -math.huge
	self._chainLinks = 0
	self._refillHoldUntil = 0
	self._stealGraceUntil = 0
	self._stealArmAt = 0
	self._struckAt = -math.huge
	self._swoopAge = math.huge
	self._chases = 0
	self._lastChaseTile = nil
	self._cooldownUntil = 0
	self._playerAlong = 0
	self._playerCross = 0
	self._playerSpeed = 0
	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_loop(dt)
	end)
end

--[[ The run ended badly. Everything goes, and the chase does NOT continue over the wreck beat.

	It covers every cause, not just a bust: a player who wrecks on an obstacle mid-chase should not
	spend the last second and a half of their run being circled by a helicopter, and one who is
	busted should see the cruisers still there when the banner lands, which is what `PullAway` being
	skipped here gives them. The cars are destroyed by `_teardown` a moment later when `RaceEnd`
	lands, or immediately if the wreck is not revivable. ]]
function PoliceController._onWrecked(self)
	self._state = "off"
	--- A wreck can land mid-PIT (an HP death from the same contact, or a fall), and the spin is not
	--- the thing that ends a run: it is the report that does, and the run is already ending.
	self:_endPit()
	self._cooldownUntil = math.huge -- nothing may re-arm over a run that is ending
	--- ...and the steal call is dropped rather than left to the cooldown, because it is the one
	--- trigger allowed to ignore that (`StealHeat.IgnoreCooldown`). A car called in a second before
	--- the crash that ended the run must not bring the police to the wreck beat.
	self._stealArmAt = 0
	for _, rec in self._pursuers do
		if rec.siren then
			rec.siren:Stop()
		end
	end
end

--[[ PUBLIC (`GetawayController._bank`, just BEFORE it sends the bank). The run ended well: the car
	is shut in the truck and nothing may come for it there (2026-10-15, Dylan: "make it so police
	don't show up if you just got into the getaway truck").

	THE HOLE WAS `TruckClearance`'s. It holds a chase off while a truck is in reach and finds the
	truck through `getTruck`, which answers nil from the frame the run banks. So a road trigger or a
	steal's call the truck had been holding back fired the moment the player was in the van, and the
	cruisers turned up for the exit shot. `_onWrecked`'s answer for the other way a run ends: nothing
	re-arms and the call is dropped. A chase that is somehow live (the shelter grace, `debugArm`)
	peels off instead of following the truck out.

	...AND THE SERVER IS TOLD. Its steal floor (`PoliceService._onStolen`) assumes a top-rung steal is
	always answered with a chase, and a call dropped here never is, so without this the bank would be
	held for the rest of the floor with the player sat in the van. `PoliceChase(false, true)` is "no
	chase, in the truck", sent ahead of the bank so the server has it first. ]]
function PoliceController.onBanked(self)
	if not self._active then
		return
	end
	if self._state == "live" then
		self:_lose()
	end
	self._cooldownUntil = math.huge
	self._stealArmAt = 0
	self:getRemoteEvent("PoliceChase"):Fire(false, true)
end

--[[ ...and the wreck was paid out of. The exact inverse, and it re-arms rather than merely
	restoring: the car is going back on the road at the point it was caught, in the middle of a
	police section, and putting the player back there with no police would be the revive quietly
	removing the thing they just paid to survive.

	A FRESH BAR AND A FRESH DURATION, because it is a fresh chase. `PoliceConfig.Grace` covers the
	moment the controls come back, which is the same problem it covers at an ordinary arm.

	IT RE-ARMS AS A ROAD CHASE whatever started the last one. The alert that lands on a revive has
	one job, which is to hand back the rule the player is about to be marked on again; why the first
	chase began is old news by then, and the car it was about is the one they are sitting in. ]]
function PoliceController._onRevived(self)
	if not self._active then
		return
	end
	self:_clearPursuers()
	self._cooldownUntil = 0
	self._state = "off"
	self._bar = 1
	self._lead = 0
	self._swoopAmount = 0
	self:_endPit()
	if self._chases > 0 then
		self:_arm()
	end
end

function PoliceController._teardown(self)
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	self._active = false
	self._state = "off"
	--- Not reported: the server drops its record when the race ends (`PoliceService`, `RaceLeft`).
	self._reportedLive = false
	self._reportedGraced = false
	self._bar = 1
	self._lead = 0
	self._swoopAmount = 0
	self:_endPit()
	self._lastStrikeAt = -math.huge
	self._chainLinks = 0
	self._refillHoldUntil = 0
	self._stealGraceUntil = 0
	self._stealArmAt = 0
	self._struckAt = -math.huge
	self._swoopAge = math.huge
	self:_clearPursuers()
	if self._folder then
		self._folder:Destroy()
		self._folder = nil
	end
	self._info = nil
	self._playerCar = nil
end

-- === What the HUD reads =====================================================

--[[ PUBLIC (`PoliceHudController`). Everything on screen, in one table, or nil when there is no
	chase to draw.

	POLLED RATHER THAN PUSHED, exactly as the getaway card reads its truck. That is what makes the
	display unbreakable: a chase that arms, is survived, is re-armed and is then wrecked out of
	moves the HUD through five states without a single subscription to get out of sync, and a
	revive needs no handler on that side at all because it is already visible in what this answers.

	`bar` is the same 0..1 every vehicle out of the window is placed against, so the two can never
	disagree about how close to caught the player is. ]]
function PoliceController.getChase(self)
	if not self._active or self._state == "off" or self._state == "busted" then
		return nil
	end
	local now = os.clock()
	return {
		state = self._state,
		bar = self._bar,
		--[[ ...and how far past a full one the player is pulling away (`PoliceConfig.Lead`), 0..1.

			OFFERED RATHER THAN REQUIRED. The cruisers are where this is meant to be read and the
			HUD has never needed it, but it is the one piece of chase state a bar cannot show, so
			anything that wants to say "you are getting away with it" has it without reaching into
			the controller. It is 0 for the whole of any chase in which the bar is not full. ]]
		lead = self._lead,
		--- Why this one started, "road" or "steal". The alert is the only reader: it is what lets
		--- the arm tell a player who has just taken a car that this is about the car.
		reason = self._armReason,
		--- Seconds since the chase armed, for anything that wants to hold off until the pursuers
		--- have actually arrived.
		since = now - (self._armedAt or 0),
		--[[ ...and seconds since the last crash cost the player bar, which is what the HUD's flash
			is driven off. math.huge for a chase with no strike in it yet, so a reader can test it
			against a window without checking for a nil first. ]]
		struck = now - self._struckAt,
	}
end

-- === What the admin panel reads and drives ==================================

--[[ PUBLIC (`AdminPanelController`'s Police tab). The whole chase in one table, answered every
	frame and answered whether or not there is a chase to describe.

	Deliberately wider than `getChase`, which answers only what the HUD draws. Half of what the panel
	is for is saying WHY there is no chase, and the four reasons are four different states rather
	than degrees of one: the feature is switched off, the vehicles were never published, no race is
	running, or a race is running and nothing has armed yet.

	The two road questions each walk the live segments, which is the same walk `_loop` already does
	and is only paid while the panel is open. Both are skipped without a road frame, because they
	read `_info` and there is none until the first loop frame of a race. ]]
function PoliceController.debugState(self)
	local now = os.clock()
	local onRoad = self._active and self._info ~= nil
	return {
		enabled = PoliceConfig.Enabled,
		published = (self._templates.car or self._templates.heli) ~= nil,
		active = self._active == true,
		state = self._state,
		bar = self._bar,
		held = self._held == true,
		--[[ THE THREE NUMBERS BETWEEN THE BAR AND THE CARS, which is most of what a tuning pass on
			this feature is now looking at:

			    `lead`     0..1, how far the player is pulling away (`PoliceConfig.Lead`).
			    `station`  0..2, what every vehicle is actually placed against (`_stationValue`):
			               the bar plus the lead, less the crash swoop, under the arrival's ceiling.
			    `lineup`   0..1, how far into setting the arrest up the outside cruiser is
			               (`PoliceConfig.Lineup`). 0 for the whole of an ordinary chase.

			`station` is the one to watch. It is the only number the cruisers, the helicopter and
			nothing else read, so a station that is not where the eye says the cars are is a
			placement bug and a station that is exactly where they are is a tuning question. ]]
		lead = self._lead,
		station = if self._state == "live" then self:_stationValue(now) else self._bar,
		lineup = select(2, self:_lineupCar()),
		chases = self._chases,
		pursuers = #self._pursuers,
		speed = self._playerSpeed,
		--- The chain, as the panel wants to read it: how deep it is now, and how long the window has
		--- left to run. Both 0 on clean road, so "no chain" and "a chain that has just expired" print
		--- the same, which is what they mean.
		chain = if now - self._lastStrikeAt <= PoliceConfig.Strikes.Chain.Window then self._chainLinks + 1 else 0,
		chainLeft = math.max(PoliceConfig.Strikes.Chain.Window - (now - self._lastStrikeAt), 0),
		--- Seconds the bar is still barred from refilling by the last strike (`Strikes.Settle`).
		settle = math.max(self._refillHoldUntil - now, 0),
		--- 0 outside a race, and 0 for the first frames of one: the chassis has not declared a
		--- `MaxSpeed` yet, which `drainRate` reads as "do not drain".
		floorSpeed = if self._active then self:_floorSpeed() else 0,
		--- Seconds of the rolled duration left, and of the opening grace. Both 0 outside a live one.
		left = if self._state == "live" then math.max(self._endsAt - now, 0) else 0,
		--- ...and how much of it nitro has taken off, against `PoliceConfig.Nitro.MaxCut`.
		nitroCut = if self._state == "live" then self._nitroCut else 0,
		grace = if self._state == "live" then math.max(self._graceUntil - now, 0) else 0,
		--- ...and of the steal's, which is deliberately not gated on the state: it is stamped by a
		--- mount, and a mount does not care whether anybody is chasing you (`reportSteal`).
		stealGrace = math.max(self._stealGraceUntil - now, 0),
		--[[ ...and the call a high value steal makes (`StealHeat`): whether one is outstanding, and
			how much of its `Delay` is left. Zero seconds with `stealCall` still true is a call that
			is ready and is waiting for a chase, an arrest or a peel-off to be out of its way. ]]
		stealCall = self._stealArmAt > 0,
		stealCallIn = if self._stealArmAt > 0 then math.max(self._stealArmAt - now, 0) else 0,
		--- math.huge for the whole of a run that is ending, because that is what `_onWrecked` writes
		--- to say "nothing may re-arm over this". A caller printing it must expect an infinity.
		cooldown = if self._state == "off" then math.max(self._cooldownUntil - now, 0) else 0,
		tile = if onRoad then self:_tileIndex() else nil,
		sectionAhead = if onRoad then self:_sectionAhead() else false,
	}
end

--[[ Force one. The same `_arm` a police section fires, with nothing skipped: it rolls its own
	duration, counts toward `_chases` and stamps `_lastChaseTile`, so everything after it (the
	peel-off, the cooldown, whether a repeat is due) is what would have happened had the road armed
	it. There is deliberately no lighter "preview" mode, for the reason the weather panel has none:
	a chase that skipped its own entry points would be testing a lookalike.

	IT REFUSES OFF THE ROAD rather than arming into nothing. `_spawnPursuer` parents its clones into
	`self._folder`, which exists only during a race, so outside one the cruisers would be created
	unparented, hold station against a road frame that is not there, and never be seen.

	Clears a chase already in progress first, so a second press replaces the vehicles rather than
	adding a second set of them to the road. ]]
function PoliceController.debugArm(self): boolean
	if not (self._active and self._info) then
		return false
	end
	if not (self._templates.car or self._templates.heli) then
		return false
	end
	self:_clearPursuers()
	self:_arm()
	return true
end

--- Survive it now: the `PullAway` beat and the cooldown behind it, exactly as running the duration
--- out would have given you. False if there was no live chase to end.
function PoliceController.debugLose(self): boolean
	if self._state ~= "live" then
		return false
	end
	self:_lose()
	return true
end

--[[ ...and be caught now. THE REAL ARREST, which means the PIT as well as the report: a cruiser
	comes off its station and spins the car, and only then is `PoliceBusted` sent, the server
	ratifies it and the run ends through `wreckRace`. So the banner, the results headline and the
	revive offer are the shipping ones, and so is the second and a half in front of them.

	It answers TRUE the moment the arrest starts rather than when the run ends, because that is the
	question the button asks. False if there was no live chase to be caught in, since the server
	would refuse a bust claim from a client that is not in one anyway. ]]
function PoliceController.debugBust(self): boolean
	if self._state ~= "live" then
		return false
	end
	self:_bust()
	return true
end

--[[ Hold the bar where it is, or let it move again.

	The bar empties in three and a half seconds at a standstill and a single barrier takes nearly
	half of it in one frame, which is the beat working and is far too fast to look at anything in.
	Holding it is how the cruisers' closing stations and the HUD's colours get inspected AT a value
	rather than in passing.

	The panel pushes this every frame from its checkbox, so the switch and the box cannot drift
	apart, and nothing else in this file writes it. It gates the DRAIN and the STRIKES, which is the
	two things that move the bar and nothing more: the duration clock goes on running, so a held
	chase still ends on time. ]]
function PoliceController.debugHold(self, held: boolean)
	self._held = held == true
end

--[[ Put the bar somewhere. Every station and every colour in the chase is derived from it, so this
	moves the cruisers, the helicopter and the HUD together on the next frame.

	Set to 0 without the hold on and the next frame arrests you, PIT and all, which is not a special
	case: it is the same `bar <= 0` the road catches you with. ]]
function PoliceController.debugSetBar(self, value: number)
	self._bar = math.clamp(value, 0, 1)
	--- ...and the lead with it, off anything but a full bar, because that is the invariant every
	--- other writer of the bar holds: a lead sitting on top of a bar the panel has just dragged to
	--- a tenth would put the cruisers a lane away from a player one hit off an arrest.
	if self._bar < 1 then
		self._lead = 0
	end
end

--[[ Land a strike of a given `Shake`, exactly as a hazard would.

	THE REAL PATH, with nothing skipped: it chains off the last one, holds the refill, arms the swoop
	that brings the cruisers up and can bust you, so pressing it twice quickly is the feature being
	tested rather than a lookalike. The band it is read against is `Strikes.Shake`, so 1.2 is a barrier and 0.35 is a
	cone; the panel prints the ladder beside the button.

	False if there was no live chase to be struck in, which is the same refusal `reportStrike` makes
	and for the same reason. ]]
function PoliceController.debugStrike(self, shake: number): boolean
	if self._state ~= "live" then
		return false
	end
	local before = self._bar
	self:reportStrike(shake)
	return self._bar < before
end

PoliceController:withRemoteEvents({
	{
		RaceStart = function(_seed, world)
			PoliceController:_onRaceStart(world)
		end,
		RaceWrecked = function()
			PoliceController:_onWrecked()
		end,
		RaceRevived = function()
			PoliceController:_onRevived()
		end,
		RaceEnd = function()
			PoliceController:_teardown()
		end,
	},
	"PoliceBusted",
	"PoliceChase",
})

PoliceController:withLifecycle({
	init = function(self)
		self._active = false
		--- "off", "live", "pit", "busted" (awaiting the server) or "leaving" (the peel-off).
		self._state = "off"
		self._bar = 1
		--- The two numbers that decorate the bar for placement and for nothing else: how far the
		--- player is pulling away (`PoliceConfig.Lead`) and how hard the last crash dived the
		--- cruisers in past what the bar asked for (`Strikes.Swoop`, decayed off `_struckAt`).
		--- Neither can move the bar, end a run or save one. See `_stationValue`.
		self._lead = 0
		self._swoopAmount = 0
		self._chases = 0
		--- The chain: when the last strike landed and how many links deep it was. Counted off the
		--- CLOCK rather than off the bar, which is the whole of what makes "too close together"
		--- different from "twice" (see `reportStrike`). -inf = no strike this chase.
		self._lastStrikeAt = -math.huge
		self._chainLinks = 0
		--- os.clock() before which the bar may not REFILL (`Strikes.Settle`), and when the last
		--- strike landed for anything that wants to react to one. The HUD's flash is the only
		--- reader of the second, and it reads it through `getChase`.
		self._refillHoldUntil = 0
		self._struckAt = -math.huge
		--- Seconds of swoop the last strike has aged through, which is not the same as seconds since
		--- it: a lit bottle ages it faster (`_stationValue`). math.huge = no swoop running.
		self._swoopAge = math.huge
		--- Seconds nitro has taken off the live chase's clock (`PoliceConfig.Nitro.MaxCut`).
		self._nitroCut = 0
		--- The arrest in progress, or nil: `{ rec, startedAt, fromGap, fromCross, hitAt }`. See
		--- `_beginPit`. Only ever non-nil while `_state` is "pit".
		self._pit = nil
		--- ...and the two things that arrest is HOLDING, both of which have to be given back:
		--- `ObstacleController`'s suspension, and the chassis wheels' own physical properties as
		--- `{ part, was }` pairs (`was` is legitimately nil). See `_endPit`.
		self._pitHeldCourse = false
		self._pitTyres = nil
		self._pursuers = {}
		self._templates = {}
		--- What the server was last told (`_reportChase`): a chase is on, and the player was in the
		--- truck's shelter when it armed and has not left it since.
		self._reportedLive = false
		self._reportedGraced = false
		self._cooldownUntil = 0
		self._graceUntil = 0
		--- ...and the same thing a landed steal buys, kept apart from the one above because it
		--- waives the DRAIN alone and not the strikes (`reportSteal`). Both are read every frame,
		--- and whichever is still up wins.
		self._stealGraceUntil = 0
		--- os.clock() at which a high value steal's call may arm a chase, or 0 for no call. It is
		--- a stamp and not a latch: it expires on its own after `StealHeat.Window` (`_callDue`).
		self._stealArmAt = 0
		--- What armed the live chase, for the alert alone (`_arm`). "road" out of the box so a
		--- reader before the first chase gets the ordinary answer rather than nil.
		self._armReason = "road"
		self._endsAt = 0
		self._leaveAt = 0
		self._armedAt = 0
		self._playerAlong = 0
		self._playerCross = 0
		self._playerSpeed = 0
		self._sirenTemplate = nil -- nil = not looked for yet, false = looked for and absent
		--- The admin panel's bar freeze, off unless its Police tab is open and ticked. Never
		--- written anywhere else, and deliberately not cleared by `_teardown`: it is a switch the
		--- panel owns for the session rather than a piece of chase state (`debugHold`).
		self._held = false
		self._rng = Random.new()
	end,

	start = function(self)
		self._road = Shard.get("RoadController")
		--[[ The drive shim, for two questions: what this car cruises at, and whether the player is
			in control of it right now. It is not a hard dependency: a chase without it measures no floor
			and therefore never busts anybody, which is the safe direction to fail in. In practice it is
			always there. ]]
		self._drive = Shard.get("DriveController")

		--- Registered once for the session, like a remote handler: a rebase is a property of the
		--- world rather than of any one race.
		if self._road then
			self._road:onWorldShift(function(shift)
				self:_onWorldShift(shift)
			end)
		end

		--[[ ...and for the steal, which is the one thing the chase has to forgive. Registered the
			same way and for the same reason: a steal is a fact about the run rather than about any
			one chase, and `onStolen` fires at the end of a handoff whether or not one is live.

			Not a hard dependency either. A missing StealController means there are no steals to
			forgive, which is the same shape of failure a missing road or drive shim has here. ]]
		local steal = Shard.get("StealController")
		if steal then
			steal:onStolen(function(tier)
				self:reportSteal(tier)
			end)
		end

		--- The bottle, asked whether it is burning and nothing else (`PoliceConfig.Nitro`). Soft for
		--- the same reason: no nitro is a chase that runs at its ordinary rates.
		self._nitro = Shard.get("NitroController")

		--- Resolved off the critical path. `RaceStart` arrives long after this, and blocking client
		--- boot on models the server may not have published would be worse than one warned-about
		--- police-free race.
		task.spawn(function()
			local folder = ReplicatedStorage:WaitForChild(PoliceConfig.TemplateFolderName, TEMPLATE_WAIT)
			if not folder then
				self.log:warn("No police vehicles were published; races run without a chase.")
				return
			end
			self._templates.car = folder:FindFirstChild(PoliceConfig.TemplateNames.Car)
			self._templates.heli = folder:FindFirstChild(PoliceConfig.TemplateNames.Heli)
			if not self._templates.car then
				self.log:warn("No police cruiser was published; the chase will run with the helicopter alone.")
			end
		end)
	end,
})

return PoliceController
