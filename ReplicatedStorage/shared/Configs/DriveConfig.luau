--[[
	DriveConfig
	-----------
	The arcade drive layer — everything that turns the stock CarBones car into a mobile-style
	traffic racer: the throttle drives itself, and the player only ever changes lane.

	THERE ARE TWO STEERING MODELS IN HERE and exactly one is live at a time, chosen by
	`DirectSteering` below. They are genuinely different ideas about what steering IS, so read
	this before touching either set of numbers:

	  • DIRECT (DirectSteering = true, the default). Input creates a bounded, speed-shaped yaw
	    target first; a reduced cross-road velocity assist then supports the intended trajectory.
	    The two are coupled in DriveController._lane, with strong release and reversal recovery.

	  • CONE (DirectSteering = false). Input goes to the tuned CarBones steering rack, the nose
	    swings up to 30°, and tyre grip turns that into sideways movement. The rotation causes
	    the lane change, so it has to come first and be big. A real car, and the original
	    design — kept because it's a one-line A/B and it's the honest physical baseline.

	Three things to know before editing:

	1. NOTHING HERE RE-TUNES THE PHYSICS. Per the car-system handoff doc (§1), the CarBones
	   suspension / ballast / wheels are tuned and stay untouched, and every throttle value
	   below still reshapes the *input* the stock chassis takes rather than the chassis itself.

	   Direct mode does, however, stop the STEERING RACK deciding where the car goes sideways:
	   it writes the car's cross-road velocity and holds its heading directly (see
	   DriveController). That's a deliberate, signed-off departure from "driving feel is
	   already solved by CarBones" — for steering only, and reversible with one boolean. It is
	   still not a re-tune: no spring, ballast or rack value changes, and the rack still steers
	   the front wheels for show (RackSteerVisual).

	2. EVERYTHING IS MEASURED AGAINST THE ROAD, NOT THE CAMERA OR THE CAR. "Heading error" is
	   the angle between the car's nose and the road's drive direction, and "lateral" is studs
	   across the road from its drive centre — both from RoadController's road frame, so they
	   stay meaningful no matter where the road has been recycled or rebased to. Zero heading
	   error = pointed straight down the road; zero lateral = on the centre line.

	3. THE CAMERA IS SIZED AGAINST THESE NUMBERS. CameraConfig's Turning section takes a share
	   of the heading the car actually reaches, and direct mode's few degrees of lean is a very
	   different signal from the cone's 30°. Change LeanDeg or DirectSteering and re-read that
	   section — its defaults are sized for direct mode.

	Reference numbers for tuning: the deck is ~73.5 studs wide (obstacle lanes at ±30) and the car
	is ~8.4 wide.

	FOR SPEEDS, MEASURE — DO NOT TRUST A NUMBER IN THIS FILE. The "~52 studs/s cruise, ~71 boosted"
	this file was written around came off one early test car and is not what any shipping car does.
	Measured on the road: the tier-1 Civic every run now starts in (WorldConfig.StartRung) cruises
	71-75 and the tier-4 Charger holds a rock-steady 84-85, boosting to ~115. The rig's own
	`MaxSpeed` attribute is in a third scale again — it reads 34.4 on the Civic doing ~71 — so
	nothing on the rig is studs/s either, and a ratio between two of these scales is meaningless.

	THIS COST US TWICE ALREADY, which is why the warning is at the top: LaneSpeed carried a strafe
	ceiling computed at 52 that was roughly twice as strict as the real cruise justified, and the
	old lean ramps were both placed at "boosted cruise" 70 and saturated in ordinary driving.
	Those now use fractions of each car's boosted ceiling, the same scale as the camera and wind.
]]

local DriveConfig = {}

-- Master switch. Off = the stock CarBones controls, exactly as they were before this layer
-- existed (hold W to go, full steering lock, U-turns allowed).
DriveConfig.Enabled = true

-- === Throttle ===============================================================
-- Three states off the one throttle axis the stock Driver already computes, with the default in
-- the middle and both ends hold-only — let go of either and the car returns to cruise by itself:
--
--   hold accelerate  → boost, faster than default        (BoostSpeedScale)
--   nothing held     → the DEFAULT cruise                (the car's authored MaxSpeed)
--   hold brake       → a dab, slower, down to a floor    (BrakeStrength / MinSpeedFraction)
--
-- Throttle itself is always full; what changes between states is how fast the car is *allowed*
-- to go. This is the value handed to the chassis every frame in place of the player's accelerate
-- input. 1 = full.
--
-- THERE IS A FOURTH STATE AND IT IS NOT IN THIS FILE. Nitro (`NitroConfig`) is a bigger scale on
-- the same speed dial, held on its own key, bought out of a tank that runs out. It sits above boost
-- and `DriveController._speedDial` resolves the two with `math.max` rather than by multiplying, so
-- nitro means one speed whatever else is held. Nothing below changes for it; the only thing to know
-- while tuning here is that every nitro scale must stay above `BoostSpeedScale` or the button
-- silently does nothing (NitroConfig asserts that at load).
DriveConfig.AutoThrottle = 1

-- Fixed ceiling on positive forward acceleration; faster cars take longer to build speed.
-- Civic from rest to 70 studs/s (2026-10-13): uncapped 1.0s, 18 took 4.1s and felt sluggish,
-- 36 takes 2.2s. Raise it for a snappier launch, lower it for more of a build.
-- OFF since 2026-10-14 (the owner: "someone made the start of the run much slower than it used to be,
-- change it back"): the uncapped 1.0s launch, exactly as before the cap. Back on = the 2.2s build.
DriveConfig.ForwardAcceleration = { Enabled = false, StudsPerSecondSquared = 36, NitroStudsPerSecondSquared = 54 }

-- The chassis has no physical gearbox. This shared display/audio model divides measured road
-- speed into six bands: RPM climbs inside a band, drops on an upshift, and blips on a downshift.
-- Keeping it here makes the dashboard gear and the engine note use the same shift points.
DriveConfig.Gearbox = {
	TopMph = 68,
	Gears = 6,
	DownshiftHysteresis = 0.12,
}

--[[ A STAND-IN ENGINE (2026-10-14, `TestEngineController`): one looped clip pitched by the gearbox
	above, on whatever car the local player drives, the kit's engine layers muted locally while it runs.
	For trying a clip before the per-engine-type sets exist. Pitches are PlaybackSpeed: `IdlePitch` under
	`IdleBelowMph`, then `LowPitch` -> `HighPitch` through each gear plus `PerGear` per gear up, eased
	at `Response` per second. `Enabled = false`: the kit's engine, exactly as before. ]]
DriveConfig.TestEngine = {
	Enabled = true,
	SoundId = 532147820,
	--- Fallback engine at 80% of its prior 1.5 volume, matching the pack trim.
	Volume = 1.2,
	--- Studs from the car before it starts fading: past the chase camera, so the driver hears it full.
	FullVolumeWithin = 40,
	MuteKit = true,
	IdlePitch = 0.7,
	IdleBelowMph = 3,
	LowPitch = 0.85,
	HighPitch = 1.45,
	PerGear = 0.03,
	Response = 10,
}

--[[ ENGINE NOTE. Whether this controller drives the CarBones engine audio, or leaves the kit to it.

	=== WHY IT HAS TO ==========================================================================

	The kit's audio is good: three tracks crossfaded on an RPM figure it integrates itself
	(`Scripts/Effects`), with `BaseEngineRPM` / `MaxEngineRPM` read off the rig. The RPM is where it
	goes wrong for THIS game, and the reason is one curve in `Scripts/Chassis.UpdateThrottle`:

	    local r = math.abs(velocity.Magnitude / maxSpeed * 2.5)
	    gainModifier = math.exp(-3 * r * r)

	`gainModifier` is what lifts the engine from its idle-ish base toward its ceiling, and that
	Gaussian is dead by 40% of the car's top speed:

	    share of max   0.10   0.20   0.30   0.40   0.50   0.74   1.00
	    gainModifier   0.83   0.47   0.18   0.05   0.009  0.00004  0

	It is a sensible curve for a car that pulls away, revs, and settles. This game never pulls away:
	`AutoThrottle` holds the throttle at full and the car sits between 70% and 100% of its ceiling
	for an entire run. So `gainModifier` is ~0 the whole time, the RPM collapses to the base term,
	and the engine holds ONE NOTE from the first second to the last. That is the flatness — not the
	samples, not the mix, one curve tuned for a use this game does not have.

	=== WHY IT IS AN OVERRIDE AND NOT AN EDIT ==================================================

	Kit scripts live in the place file, not in git: they do not diff, they do not review, and a
	fresh CarBones import silently reverts them. So this wraps rather than edits, exactly as
	`_holdSeat` and `DrivingHudController._suppressStockSpeedo` do with the same kit.

	The hook is clean. `Chassis` calls `Effects:SetThrottleEnabled(state, gain)` on the MODULE table
	rather than an instance, and `gainModifier` is a module-level local, so requiring the same
	ModuleScript and calling the same method writes the same value the kit writes.

	THE WRITE ORDER DOES NOT NEED WINNING, which is what makes this safe without a latch. The kit's
	Driver is a legacy `while ... wait()` loop, so it writes at ~30Hz; this writes every Heartbeat.
	And `Effects` does not USE the value directly — it integrates toward it at `ENGINE_GAIN_ACCEL`
	(0.1) per frame, so the note is a heavy average of many writes rather than a read of the last
	one. Ours dominate by weight of numbers; a frame the kit wins is inaudible.

	=== THE CURVE ==============================================================================

	The same simulated six-speed the dashboard uses. Inside each speed band the target climbs from
	`MinGain` to full load; crossing the top changes gear, cuts load for `ShiftPause`, and begins the
	climb again. A downshift jumps back up the lower gear's RPM band, giving the natural throttle
	blip. The chassis remains untouched: this only changes the RPM target driving its three authored
	engine layers.

	Set `Enabled = false` to hand the engine back to the kit exactly as it was. ]]
DriveConfig.EngineAudio = {
	Enabled = true,
	--- Lowest loaded-engine target inside each gear. Every band sweeps from here to 1.
	MinGain = 0.2,
	--- Brief clutch/load cut after an upshift. Existing CarBones tracks supply the sound; this only
	--- gives their RPM integrator a sharper change to articulate.
	ShiftPause = 0.1,
	ShiftGain = 0.08,

	--[[ The rev a steal lands on (`StealController._notifyStolen` calls `DriveController.rev`).
		Players asked for an engine rev when they take a car, and it is played ON this engine rather
		than as a clip over it: a recorded rev is somebody else's engine at somebody else's pitch,
		and it would sit on top of the three layers this car is already playing.

		WHY THE GAINS ARE OUT OF RANGE. The kit's `Effects` (server side) eases its RPM toward the
		target at `ENGINE_GAIN_ACCEL` = 0.1 per second of difference, a ten second time constant, so
		a gain of 1 held for half a second moves the note by a few percent. The target is
		`base + gain * (top - base)` and the result is clamped to the kit's own top RPM, so a gain far
		above 1 only makes the climb STEEP: the note still stops at this car's authored redline. A
		negative gain is the same trick downward, pulling the note back off the redline instead of
		leaving it to hang there for seconds; the kit clamps that at its idle RPM.

		`RiseTime` at `RiseGain`, then `FallTime` at `FallGain`, then the gearbox curve above takes
		the engine back. Measured on the Civic in a race (2026-10-13), as pitch against the idle
		layer: cruise sits at 2.17 and the steal flight lets it sag to 1.42; the rise takes it to the
		2.96 clamp in 0.4s and the fall brings it to about 2.4, a little over cruise on purpose,
		since landing under cruise would leave a ten second bog while the kit climbs back. The kit's client sends at most five updates a second, so neither phase is
		worth making shorter than 0.2. `Enabled = false` takes the rev out and leaves the rest of
		the engine as it was. ]]
	Rev = {
		Enabled = true,
		RiseTime = 0.45,
		RiseGain = 20,
		FallTime = 0.4,
		FallGain = -6,
	},
}

-- === Boost (hold accelerate) ================================================
DriveConfig.AllowBoost = true

-- Multiplier applied to the car's `MaxSpeed` attribute while accelerate is held. The authored
-- value stays the default cruise, so this is purely additive — it can't regress the baseline feel.
--
-- Why MaxSpeed and not the motor's target velocity: the stock throttle damps driving torque by
-- exp(-3r²) where r = speed / MaxSpeed, and the car settles where that torque dies — far short of
-- the target the motors were ever asked for. Raising the motor target alone would change nothing
-- at all; scaling MaxSpeed drags the whole torque curve up with it.
--
-- The shape of that curve is what 1.35 is sized against, and the shape is scale-free: r is a
-- RATIO, so boost lands ~35% on top of whatever a given car cruises at, whatever that is. Only the
-- ratio should be read out of this comment. The absolute figures it was derived from (torque down
-- to 15% of peak at 51 and 5% at 64, equilibrium ~52 studs/s, ~71 boosted) are the old test car's
-- and are not the fleet's — see the header. Measured today: the Civic cruises 71-75 and boosts to
-- ~96-101, the Charger 84-85 to ~115, which is the same 1.35 doing its job.
DriveConfig.BoostSpeedScale = 1.35

-- Let a deliberate brake input (S / Down / L2 / the touch brake button) slow the car? On, but
-- strictly as a *dab* — see the three values below. Release it and AutoThrottle above pulls the
-- car straight back up to speed on its own, which is the whole feel: you scrub a little to
-- thread a gap, then it winds back up for you.
DriveConfig.AllowBrake = true

-- How hard the brake is allowed to bite, as the throttle value handed to the chassis. The stock
-- chassis squares this into braking torque, so 1 is roughly 23% more braking torque than the old
-- 0.9 command and gives a late gap decision an immediate emergency-save response.
DriveConfig.BrakeStrength = 1
-- Stock chassis caps wheel braking at 100 rad/s^2 regardless of available torque.
DriveConfig.BrakeAngularAcceleration = 220

-- The floor the brake will never take you below, as a fraction of the fastest the car has gone
-- this run. A floor is not optional: the stock chassis reads a held brake at a standstill as
-- REVERSE, which would undo the one rule this whole controller exists to enforce.
--
-- Measured against the *run's own peak* rather than a rated top speed on purpose. The car's
-- `MaxSpeed` attribute (40 on the test car, not the stock 75) is in one unit, `VehicleSeat.MaxSpeed`
-- ends up in another, and the stock torque damping compares linear studs/s against an angular
-- figure — so real cruising speed is only about two thirds of any number you can read off the
-- rig. Tracking the peak sidesteps all of it and stays correct for any redress.
--
-- Note the peak includes speed reached under boost, so once a player has used boost the floor
-- sits at 32% of their *boosted* best — i.e. braking from a normal cruise sheds proportionally
-- less. That's a coherent rule ("you can always shed a fixed fraction of your best speed") and
-- the invariant that matters is untouched, but if the brake ends up feeling weak in practice
-- this is the number to drop.
DriveConfig.MinSpeedFraction = 0.18

-- Braking eases off across this much of the peak speed above the floor, so holding the brake
-- settles onto the floor instead of chattering between full brake and full throttle. Inside the
-- band the shaped throttle drops under the chassis's own 0.1 idle threshold, so the last of it
-- is a coast rather than a fight. The narrow 0.1 band makes the initial bite much stronger than
-- the final settle without allowing reverse. Narrower than before so full braking remains active
-- deeper into the stop and only eases during the last eight percent above the floor.
DriveConfig.BrakeFadeFraction = 0.06

-- The chassis's OWN speed (the `currentSpeed` it is handed, not the body's) under which a brake is
-- handed over as a coast instead (`DriveController`'s `UpdateThrottle` wrapper, 2026-10-15). The
-- floor above is measured off the body; the stock reverse branch reads this number, and the two can
-- part for a frame at the end of a hard stop. 3 is six times the stock branch's own 0.5, enough to
-- clear a frame's disagreement and still far under any floor a real run sets.
DriveConfig.ReverseGuardSpeed = 3

-- Known edge case, left as-is because it's benign and self-correcting: hold the brake from the
-- instant the car goes live and the peak never gets established at cruising speed, so you settle
-- into a band at 45-60% of whatever little speed you did reach — a crawl, until you let go. The
-- invariant that matters still holds (the car only ever moves forward), and releasing the brake
-- for a moment fixes it permanently. Guarding it would need a hardcoded "up to speed" number,
-- and the whole reason the floor tracks the peak is that no such number can be read off the rig.

-- Let the handbrake (Space / ButtonA) still lock the rear wheels? Off by default for the
-- same reason — holding it is a way to park, which would undo the auto-throttle. Turn it
-- back on if you want it as a drift/dodge button.
DriveConfig.AllowHandbrake = false

-- === Lane change (DirectSteering) ===========================================
--[[ The steering model the game ships with: input is a request to be SOMEWHERE ELSE ACROSS THE
	ROAD, not a request to rotate. Hold left and the car slides left at a steady rate, eases to a
	stop when you let go, and leans a few degrees while it's moving. Nothing winds up, so it
	answers the instant you press — which is the single biggest difference from the cone.

	Off = the heading cone below, unchanged, and every value in this section is ignored. ]]
DriveConfig.DirectSteering = true

--[[ Sideways speed at full input, studs/s.

	26 was where this started, and it wasn't arbitrary: it's exactly what the cone already gave you
	(a 30° heading at the 52 studs/s cruise this file was written against carries ~26 studs/s
	sideways), so direct mode launched with the same lateral authority the car had before it and
	spent none of that on wind-up or on pointing the nose 30° off. That made the swap safe. It also
	made 26 a FLOOR rather than a target, and the move playtesting says feels slow is the full-width
	cut — right-hand edge to left-hand edge, 60 studs, which took 2.97s at 26 and 2.58s at 30.
	(Every timing in this section and the next is simulated against the integrator itself at 60Hz,
	edge fade included: hold full input from one edge and count until the slide drops under
	0.5 studs/s at the other. The real car takes ~10% longer than that says — tyre scrub against the
	crab, see LaneEdgeFade — so the 2.60s predicted for 30 measured 2.88s on the road.)

	34 brings the predicted cut to 2.37s. That is a bigger step than the last one, and it is one the
	old ceiling forbade: "past ~35 the car reads as strafing" was computed against a 52 studs/s
	cruise, and NO CAR IN THIS GAME CRUISES AT 52. Measured: the tier-4 Charger holds a rock-steady
	84-85 flat, the tier-1 Civic every run now starts in (WorldConfig.StartRung) holds ~71-75. At the
	real cruise the crab at 34 is ~18°, not the 34° that ceiling feared — and 18° against a 5-7°
	lean still reads as a car going roughly where it is pointed.

	WHAT ACTUALLY BOUNDS THIS IS THE EDGE, NOT THE CRAB. Past ~44 the car overshoots LaneHalfWidth
	hard enough to grind the barrier again whatever LaneEdgeFade is set to — the damping ratio
	spelled out under LaneEdgeFade falls back to 0.79, which is roughly where it was when the grind
	was costing half the car's speed. 34 keeps a wide margin under that, and still leaves the higher
	tiers somewhere visible to go, since this is the number tier handling scaling would multiply
	when it lands. ]]
-- CURRENT HYBRID BASELINE: 58 is the intended trajectory speed before LateralAssist reduces the
-- direct write, producing 41.76 studs/s at full input. Visual yaw is deliberately decoupled below,
-- so this makes the lane change substantially quicker without making the car point farther sideways.
DriveConfig.LaneSpeed = 58

--[[ How fast that sideways speed eases in and out, per second (exponential time constant, so
	~0.09s at 11, down from ~0.13s at 8).

	This is the "smoothly" in "smoothly moves onto the next lane" and the most important feel knob
	in the section. Too high and the car snaps sideways like a menu cursor — the giveaway that a
	lane change is scripted. Too low and you're back to input lag, which is what direct mode
	exists to remove.

	IT IS ALSO THE HALF A PLAYER ACTUALLY FEELS. "Steering feels heavy" came back from two testers
	separately, and what a complaint like that registers is the first fifth of a second after the
	key goes down — which is this, not LaneSpeed. A 0.15s press reaches 81% of lane speed at 11
	against 70% at 8, and a release has 90% of the slide gone in 0.21s against 0.29s. Both
	directions count: being able to STOP on a lane is most of what precision is.

	11 is not near any measured ceiling. Touch has been shipping at 16 (8 under the old x2 scale) on
	the same car and the same road without ever reading as a menu cursor — which is the honest upper
	bound this arm had available all along. It was 7, then 8; the step to 11 is the desktop half of
	the answer the Touch section below reached first. Touch still scales this, and now scales it far
	less, because most of what it was buying is in the shared value. ]]
-- CURRENT HYBRID BASELINE: 21 lets the lateral spring reach the faster trajectory promptly while
-- leaving enough build-up for the yaw cue to remain readable.
DriveConfig.LaneAccel = 21

--[[ WEIGHT. Whether the lane change carries any mass, or arrives and simply stops.

	WHAT THIS FIXES. `LaneAccel` above eases the car's cross-road VELOCITY toward the target with a
	first-order filter — `x += (want - x) * (1 - exp(-dt * k))`. That is a perfectly smooth ramp
	with no inertia anywhere in it: let go and the sideways motion decays to nothing and stops dead
	on the new line, every time, exactly on cue. It is precise, and precise is why it reads as a
	cursor rather than a car. Nothing about the movement says the thing being moved has mass.

	WHAT REPLACES IT. The same target, reached by a SPRING instead of a filter: the car accelerates
	toward the commanded cross speed and is damped on the way. Two consequences, and both of them
	are the point —

	  • starting a lane change has a beat of build-up rather than an instant ramp, and
	  • ending one overshoots slightly and settles back, because the mass that was moving sideways
	    has to be stopped and does not stop for free.

	`Damping` is the ratio: 1 is critically damped (weight, no overshoot at all), and below 1
	overshoots by roughly `exp(-pi * z / sqrt(1 - z*z))` — so 0.8 is 1.5% and invisible, 0.5 is 16%
	and reads as sloppy. 0.65 is about 7%, which on a 34 stud/s lane speed is a couple of stud/s of
	settle: felt, and gone inside a third of a second.

	THE FREQUENCY IS `LaneAccel` ITSELF rather than a second number to keep in step with it. A
	critically damped spring at w settles in about the same time as a first-order filter at k = w,
	so leaving this on and setting `Damping = 1` is very close to the handling that shipped — which
	is what makes `Enabled` a real A/B rather than a jump to somewhere unrelated.

	`MaxStep` CLAMPS THE INTEGRATION and is not a tuning value. This is explicit integration, which
	goes unstable past dt = 2/w (0.18s at LaneAccel 11); a frame hitch inside that range still
	overshoots hard. Clamping the step makes a dropped frame move the car slightly LESS than real
	time rather than flinging it across the road, which is the correct direction to fail in — and
	the shove-adoption below reads velocity from the chassis, so nothing desynchronises.

	Set `Enabled = false` for the exact first-order filter this replaced. ]]
DriveConfig.LaneWeight = {
	Enabled = true,
	Damping = 0.78,
	MaxStep = 1 / 30,
}

--[[ HYBRID ASSISTED STEERING. Direct mode still owns the cross-road velocity, but it no longer
	uses that write as the whole lane change. Input first asks for a readable road-relative yaw;
	the lateral spring then supports the trajectory at only `LateralAssist` of `LaneSpeed`.

	The two yaw limits are reached by speed fraction: ordinary cruise sits near `NormalYawDeg`, and
	boost/nitro can grow toward `TopYawDeg`. `AbsoluteYawDeg` is the invariant backstop shared by
	config tests and the controller. `MinForwardSpeed` keeps atan2 from asking for a huge angle while
	the chassis is still pulling away.

	Reversing left-to-right temporarily scales the opposite lateral request. The spring therefore
	has to shed the old motion before it builds the new one, producing a short readable transition
	without countersteer or a loss of authority. Release gets its own response so the car can settle
	quickly while retaining a little weight. ]]
DriveConfig.HybridSteering = {
	LateralAssist = 0.72,
	NormalYawDeg = 9,
	TopYawDeg = 12,
	AbsoluteYawDeg = 14,
	-- Extra nose angle only while the requested lane-change velocity is still building. It fades
	-- naturally as the car starts translating. Zero keeps the current subtle visual response.
	TurnInYawBoostDeg = 0,
	-- Keyboard input jumps directly between -1, 0 and 1, but the visible heading should not.
	-- These rates smooth only yaw/body presentation; lateral movement still reads raw input.
	VisualInputResponse = 6.5,
	VisualReleaseResponse = 5.5,
	VisualReversalResponse = 4.5,
	-- Independent velocity used only to derive visible heading. Holding this at the earlier 30
	-- baseline lets LaneSpeed increase movement authority without increasing yaw magnitude.
	VisualTrajectorySpeed = 30,
	YawSpeedStartFraction = 0.2,
	YawSpeedFullFraction = 1,
	MinForwardSpeed = 35,
	YawResponse = 8.5,
	YawReleaseResponse = 8,
	YawReversalResponse = 7.5,
	ReversalLateralScale = 0.72,
	ReversalThreshold = 1.5,
}

--[[ Studs either side of the road's drive centre the player may reach. Obstacle lanes sit at ±30
	and the deck is ~73.5 wide (so ~36.75 to the edge, less half a car ≈ 32 of usable room), which
	makes 30 "the full width the course actually uses" with a little margin.

	A clamp is not optional here the way it was under the cone. The cone couldn't push the car
	anywhere the tyres wouldn't take it, so the walls could be left to do their job; a direct
	velocity write happily drives the car into a wall and grinds along it. Outward input fades to
	nothing across LaneEdgeFade before the limit — inward is never restricted, at any position. ]]
DriveConfig.LaneHalfWidth = 30

--[[ Studs before LaneHalfWidth across which outward input winds down to nothing.

	THIS IS A DAMPER, NOT A MARGIN — and reading it as a margin is exactly what kept it at 6 and
	cost the car half its speed. Inside the fade the lane model stops being a first-order ease and
	becomes a spring: `want` falls off linearly with the distance still to run while `_lane` chases
	it at LaneAccel. That is a damped second-order system, and its damping ratio is

	    sqrt(LaneAccel * LaneEdgeFade / (4 * LaneSpeed * HybridSteering.LateralAssist))

	Below 1 it OVERSHOOTS: the car crosses LaneHalfWidth, buries itself in the barrier, and sits
	there still carrying sideways speed — which the tyres then scrub off the FORWARD direction. That
	is the entire mechanism behind "holding a lane against the edge costs half your speed", and it
	is why the fix is here and not in the clamp.

	At the old 30/8/6 the ratio was 0.63. Predicted overshoot 1.2 studs, measured 1.9 on the road,
	and holding full input against the edge took the car from 91 studs/s to 44 — less than half, for
	as long as you stayed there. The hybrid's effective assisted target is only 72% of LaneSpeed,
	which increases the damping margin before the same ten-stud fade and reduces edge scrub.

	The one thing it does cost is the outermost lane, because the wind-down now starts 10 studs out
	instead of 6: a dodge from the middle lane into the ±30 lane takes 0.68s against 0.63s on
	desktop, 0.62s against 0.48s on touch. Everything that ends inside the road got quicker instead
	(centre to mid lane 0.58s → 0.50s, full-width cut 2.13s → 2.00s). Fifty milliseconds on one
	dodge against never again losing half your speed to a barrier is not a close trade.

	RE-CHECK THE RATIO IF YOU MOVE LaneSpeed OR LaneAccel — that is why the formula is written out
	here rather than a bare number. Keep it at or above ~0.85; zero overshoot exactly wants
	LaneEdgeFade >= 4 * LaneSpeed * LateralAssist / LaneAccel. At 58 / 21 / 0.72 the exact desktop
	threshold is 7.95, leaving useful margin under the shared ten-stud fade. Touch scales speed and
	ease but never this distance, so re-check both arms when either scale changes. ]]
DriveConfig.LaneEdgeFade = 10

-- === Touch (the on-screen arrows) ===========================================
--[[ The same lane change, tuned for an input you cannot feather.

	A key or a stick is analogue in the way that matters here: you press it the instant you decide,
	you hold it exactly as long as you mean to, and you release on the frame you're happy. A finger
	on a button is none of those — there's the reach and the contact, and a press is SHORT, so the
	ease-in eats most of it. At the shared LaneAccel a 0.15s tap reaches 81% of LaneSpeed before it
	starts decaying again — but it was 70% when this section was written, and 65% before that, which
	is precisely the "I pressed it and not much happened" that came back from playing on mobile. The
	buttons were never the problem; they publish the same full ±1 a key does (DrivingHudController).
	What they can't do is HOLD it.

	NOTE HOW MUCH OF THIS THE SHARED VALUES NOW DO. LaneAccel and LaneSpeed are already 21 and 58 for
	everyone, so these scales only carry the gap that is genuinely about short finger presses. Read
	them as "how much MORE than desktop", not as the whole of touch's tuning.

	So touch gets the SAME lane change, answered faster. Both scales multiply the two values above
	and nothing else changes — the clamp, the edge fade, the lean, the crab, and the way a hit
	knocks you off your line are all identical, so there is still only one steering model to reason
	about and one place to tune it.

	Live whenever the on-screen arrows are what's steering, and always on a device with no keyboard
	(where the stock touch slider is the only other option and shares the problem). Clicking the
	arrows with a mouse therefore gets you the mobile feel in Studio, which is the honest A/B — see
	DriveController._touchSteering. ]]
--[[ STEERING ON A THUMB DEVICE IS THE STICK (2026-10-20: "instead of having left and right arrows lets use
	just joystick so that when we jump there's no context switching"). Roblox's own thumbstick stays on
	for the whole race (`DrivingHudController._syncStockControls`) and the left/right arrows are hidden;
	the car's driver already steers from the stick's X, and the same stick flies the jump. Gas, brake,
	nitro and the steal button are unchanged. `false`: the arrows, and the stick off in races, as before. ]]
DriveConfig.TouchJoystick = true

DriveConfig.Touch = {
	--[[ How much faster the sideways speed eases in AND out. This is the responsiveness half, and
		it's the one that was actually missing.

		1.35 x 21 = 28.35. Touch therefore reaches and sheds the quicker trajectory faster than desktop,
		which preserves short taps as useful lane corrections instead of making them all-or-nothing.

		It also keeps the coast into the edge fade short: LaneSpeed/LaneAccel is 2.25 studs on touch
		against 2.76 on desktop. Both remain comfortably inside LaneEdgeFade's ten-stud damping band. ]]
	LaneAccelScale = 1.35,

	--[[ How much faster the car actually crosses the deck. Deliberately the smaller half:
		1.1 x 58 = 63.8 before LateralAssist, or 45.94 studs/s of assisted trajectory.

		WHAT SETS THE CEILING HERE IS NOT THE VISUAL YAW, IT IS THE EDGE — see LaneEdgeFade. At the
		current 63.8/28.35/10 values, touch retains more damping margin than desktop. ]]
	LaneSpeedScale = 1.1,
}

-- === Legacy lean values =====================================================
--[[ Direct mode's rotation. It is a CONSEQUENCE of moving sideways rather than the cause of it,
	which is the whole point — but the car still has to look like it's going where it's going, and
	a body that stayed rigidly square to the road while sliding across three lanes reads as a bug.

	Small is the brief. This is a highway lane change, not a corner. ]]

-- Degrees the nose leans at full LaneSpeed. 5 is about the least you can see and the most that
-- still reads as a lane change; at 10 it starts to look like cornering again.
-- Retained for the old direct-mode A/B and slick documentation. HybridSteering owns live yaw.
DriveConfig.LeanDeg = 5

-- Shares of this car's ordinary boosted ceiling. Using fractions keeps the body language alive on
-- every rung instead of letting the starter car saturate a threshold authored for an older rig.
DriveConfig.LeanSpeedStartFraction = 0.18
DriveConfig.LeanSpeedFullFraction = 0.55

--[[ Degrees the nose leans at full input once you're at the TOP of your speed range, replacing
	LeanDeg there rather than adding to it. The ramp above already leans the car more the faster
	you go, but only by scaling the same 5° from a standstill, so flat out you get exactly LeanDeg
	and no more. This is the bit on top of that: at full chat the car turns in a little harder.

	It's a rotation change and nothing else — LaneSpeed is untouched, so a lane change still takes
	the same time and covers the same ground at every speed. What changes is only how much the car
	angles into it, which is the one part of the reference that keeps scaling past cruise.

	7 is deliberately a small step up from 5 — visible at speed, still nowhere near the ~10 where
	a lane change starts reading as cornering. Set it equal to LeanDeg to switch this off. ]]
DriveConfig.LeanTopDeg = 7

-- The extra turn-in belongs to the run from cruise into boost, not to one absolute speed. Most
-- cars cruise around 0.72-0.78 of this ceiling and reach 1 while boost is held.
DriveConfig.LeanTopStartFraction = 0.72
DriveConfig.LeanTopFullFraction = 1.0

--[[ How hard the car is held at the lean angle, per second. This is a servo on the heading, so it
	is also what unwinds a collision: it pulls toward the target from ANY angle, which is why
	direct mode doesn't need the cone's countersteer or its RecoverYaw* staging. MaxYawRate below
	is the ceiling on how fast it's allowed to do that, and the reason a hit still reads as a hit
	instead of being erased.

	8 holds the lean crisply without looking magnetised. Lower feels floatier and lets hits push
	the car further off line before it recovers. ]]
DriveConfig.LeanGain = 8

-- Optional tuning telemetry. When enabled, DriveController writes throttled attributes onto the
-- player's car; there are no per-frame prints and the default has zero replicated/log noise.
DriveConfig.Debug = {
	Enabled = false,
	SampleInterval = 0.1,
}

--[[ Subtle chassis load. The current CarBones dress is welded directly to RedressMount, so it has
	no independent visual shell that can safely receive a Transform. These tiny road-relative
	angular-velocity targets therefore move the owned assembly itself; the caps stay below ordinary
	suspension travel and the upright recovery takes over immediately outside `MaxTiltDeg`.

	Roll is the body leaning away from lateral load. Dive reacts immediately to a held brake; squat
	uses measured forward acceleration so releasing the brake settles naturally as speed rebuilds. ]]
DriveConfig.BodyMotion = {
	Enabled = true,
	RollDeg = 1.5,
	-- Share of roll driven immediately by steering input; zero keeps roll tied to actual movement.
	InputRollShare = 0,
	BrakeDiveDeg = 1.25,
	AccelSquatDeg = 0.7,
	AccelForFull = 28,
	Response = 8,
	MaxRate = 0.7,
	MaxTiltDeg = 6,
}

--[[ === The fishtail (what a slick LOOKS like) ================================

	How the car shows that it is on something slippery. `ObstacleConfig.Oil` is the only thing that
	causes one today (via DriveController.applySlick), but this is the CAR's half of it rather than
	the hazard's, which is why it lives here: any future slick kind gets the same wag scaled by its
	own grip loss, and there is one place to tune how "loose" a slippery road feels.

	IT EXISTS BECAUSE GRIP LOSS ALONE IS INVISIBLE. A slick takes the car's steering and changes
	nothing else about it — same speed, same posture, same everything — so from the driver's seat a
	car on oil is indistinguishable from a car whose controls have broken. It was reported as
	exactly that: a handling regression, not a hazard. The wag is the only thing on screen that says
	"you are still on it", and it has to carry that on its own, because the puddle is under the car
	and out of frame by the time it matters.

	READ `DriveController._slickWobble` BEFORE CHANGING EITHER NUMBER. The wag is a moving SERVO
	TARGET, not an angular-velocity kick — a kick is overwritten inside one frame by the lean servo
	(measured: 0.0° of lasting rotation from a sustained 2 rad/s, which is why `ObstacleConfig.Oil`
	carries `Yaw = 0`). It is also rotation only: the car's cross-road velocity is never touched, so
	the fishtail cannot push the player off the line they are holding. It makes the car look like it
	is fighting for that line, which is the honest picture — the grip loss is what actually costs
	them. ]]
DriveConfig.Slick = {
	--[[ Peak degrees of extra heading at the moment of contact, decaying to nothing as the grip
		comes back. Sits against LeanDeg (5) and LeanTopDeg (7), so 7 is "as far off-axis as a
		flat-out lane change" — plainly visible without the car ever pointing anywhere it could not
		point under ordinary driving.

		The yaw servo reaches it comfortably: LeanGain 8 against a peak target of ~0.24 rad asks for
		~2 rad/s, inside the MaxYawRate 3.0 ceiling, so the wag is never clipped into a triangle
		wave at one end of its travel. Raise this past ~12 and it starts to read as a spin rather
		than a slide, and the camera's Turning share (CameraConfig) begins to swing with it. ]]
	WobbleDeg = 9,

	--[[ Wags per second. At the shipped 1.6s slick this is a little over two full cycles — out,
		back, out, settle — which is enough to read as a rhythm rather than as one twitch, and few
		enough that it never turns into a vibration.

		Tuned against the DURATION rather than in the abstract: keep the product around 2 if the
		slick's length changes, or a shorter slick will end mid-wag and look like it was cut off. ]]
	WobbleHz = 1.3,
}

--[[ Fraction of the raw steering input passed through to the tuned CarBones rack. PURELY VISUAL:
	direct mode fully specifies the car's cross-road velocity and yaw rate every frame, so
	whatever the rack does about either is overwritten — what survives is the front wheels
	visibly turning into the lane change, which is worth having and free.

	0 leaves the wheels dead straight while the car slides, which looks wrong the moment anyone
	looks closely. 1 turns them to full lock for a gentle lane change, which looks just as wrong.
	0.26 keeps the wheel cue present without letting a binary keyboard press read as a snap. ]]
DriveConfig.RackSteerVisual = 0.26

--[[ THE WOBBLE FIX. `LinearResponsiveness` written onto the car's `Constraints.SteeringPrismatic`
	servo — how hard the steering rack holds the position it has been told to hold.

	The stock rack is soft enough to be UNSTABLE. CarBones steers through a real linkage (a servo
	prismatic pushing two tie rods into two knuckle hinges) rather than by rotating the wheels
	directly, and at the shipped 45 that servo cannot hold station against the loads the tyres feed
	back up it. The rack self-oscillates: measured on the test car, driving DEAD STRAIGHT with the
	servo target at exactly 0, the rack swung 0.29 studs peak-to-peak and the front wheels waggled
	±5° at ~6Hz, which rocked the whole body about 2° through the tie rods and torsion bars. That is
	the left-right wobble, and the diagonal, opposite-corners rock is what it looks like from behind.

	Three things pinned it down, all measured rather than reasoned:
	  • it is not the road      — the frequency stays ~6Hz from 58 to 104 studs/s, so it is a
	                              resonance in the car, not something it is driving over.
	  • it is not this layer    — LeanGain from 8 down to 0.5 changes the wobble by nothing at all,
	                              and it survives with both of _lane's velocity writes removed.
	  • it is not torque steer  — cutting the front motors to zero (making it rear-drive) does not
	                              help either. It IS drive-torque-EXCITED, though: the whole thing
	                              collapses to nothing the moment the throttle comes off, which is
	                              why it only ever shows up while you are actually driving.

	100 is measured, not guessed: the front-wheel waggle goes from 11.2° peak-to-peak to 0.16° and
	the body roll from 2.13° to 0.04°. Anything from ~75 up kills it; past ~150 the roll starts
	creeping back as the stiffer rack passes road input straight into the body, so this sits in the
	middle of the band that works. Set it to nil to leave the rig exactly as authored.

	Second, smaller effect worth knowing about: at 45 the rack never actually reaches its target
	(told full lock, it settled at 38% of it), so stiffening it means the front wheels now turn
	further for the same input. In direct mode that is cosmetic-only — RackSteerVisual feeds it and
	the chassis cubes that, so a full-input lane change asks for ~3% of lock either way, and the
	visible change is small. In CONE mode (DirectSteering = false) the rack really is the steering,
	so expect it to bite noticeably harder there and re-check FreeYawDeg/MaxYawDeg if you go back.

	Applied by DriveController at install and put back on teardown, deliberately: the car lives in
	the place rather than in git, so authoring it onto the model would be silently undone by the
	next CarBones import or redress. Here it is version-controlled and applies to any car that
	spawns. Nothing in the stock Chassis module ever writes this property, so the value sticks. ]]
DriveConfig.SteerRackResponsiveness = 100

-- === The heading cone (no U-turns) ==========================================
-- Only live when DirectSteering above is false. This is the original rack-steered model: the
-- player steers the tuned CarBones rack and the layer limits how far off the road they may point.

-- Inside this many degrees off the road direction the player has full steering authority
-- and this layer does nothing at all. Make it as wide as you can stand — this is where the
-- car feels like a car.
DriveConfig.FreeYawDeg = 30

-- Steering that would point the car *further* off the road fades from full to zero across
-- FreeYawDeg → MaxYawDeg. At MaxYawDeg the player simply cannot turn out any further;
-- steering back toward the road is never restricted at any angle.
DriveConfig.MaxYawDeg = 45

-- Past MaxYawDeg the layer steers back for you. The assist ramps in over this many degrees
-- of overshoot and tops out at CounterSteerStrength (as a fraction of full lock). This is
-- ordinary steering input, so it goes through the tuned rack like the player's would.
DriveConfig.CounterSteerRampDeg = 12
DriveConfig.CounterSteerStrength = 0.8

-- === Backstop (spin-out recovery) ===========================================
-- CONE MODE ONLY, apart from MaxYawRate at the end, which both models share. Direct mode's lean
-- servo (LeanGain) already pulls the heading back from any angle, so it needs no staged recovery —
-- these three values are ignored while DirectSteering is true.
--[[ Nothing the player can steer reaches these angles. What does is a COLLISION — since traffic
	cars became solid (TrafficConfig.Collision) the biggest source of unwanted rotation by far is
	a contact with one, and it's a different animal from the obstacle yaw kicks this backstop was
	originally sized for (ObstacleConfig caps those at 0.7 rad/s):

	  • it can impose far more yaw than any kick, and
	  • it does so CONTINUOUSLY while you're touching the car, all the while taking away the
	    traction the countersteer above needs — so the polite blend below simply loses.

	That combination is how a player ends up pointed back up their own road. Three things stop it, in
	order of when they act. First, a hit traffic car is UNANCHORED and takes an impulse
	(TrafficConfig.Knock), so it moves away instead of standing there as an immovable wall — that
	removes most of the sustained contact at source, and is why the earlier fix of making hit cars
	stop colliding was able to be dropped. Then MaxYawRate caps whatever spin the hit did impart, and
	HardYawDeg is the floor under both.

	Keep all three. The first is a design choice that could be tuned away (`Knock.MinSeverity`, or a
	heavy enough car that barely budges), and the other two are what make "you can never be turned
	all the way around" a guarantee rather than a side effect of the current numbers. It matters
	because a car pointed more than ~90° off is driving back up its own road, which the countersteer
	can only unwind through a wide circle. ]]
DriveConfig.RecoverYawDeg = 100
-- Yaw rate the backstop turns at, rad/s (1.6 ≈ 92°/s).
DriveConfig.RecoverRate = 1.6
-- How hard it grabs, per second. Higher = snappier, more obviously scripted.
DriveConfig.RecoverGain = 6

--[[ Hard ceiling on how fast the car may rotate about its own vertical axis, rad/s, whatever
	caused it. Shared by both steering models: in direct mode it's the ceiling on LeanGain's servo,
	and therefore the thing that stops a collision being erased the instant it lands. 0 disables it.

	3.0 ≈ 172°/s, which is well clear of anything driving produces — the cone caps heading at
	MaxYawDeg, so sustained fast rotation isn't reachable by steering, and the rack's transient
	yaw through a flick sits around 2 — and well under what ramming a solid car at a closing speed
	produces. So in normal play this never fires; DriveController only writes when it's actually
	clamping. Drop it toward 2 if spin-outs still feel too loose, but not below the rack's own
	transient or you'll be capping ordinary corners. ]]
DriveConfig.MaxYawRate = 3.0

--[[ Past this heading error the backstop stops negotiating and SETS the yaw rate outright instead
	of blending toward it. This is the line that makes "you can never be turned all the way
	around" actually true rather than merely likely.

	135° is chosen to sit above anything the gentle recovery should be reaching (RecoverYawDeg at
	100 plus its ramp) while still leaving the car short of sideways-on-to-backwards. With
	MaxYawRate above holding the spin to 172°/s, a hit taken at zero error crosses 100° in about
	0.6s and is seized here — so the worst case a collision can produce is roughly 140°, ugly and
	recoverable, never a U-turn.

	Note this is an angular-VELOCITY write like the blend it replaces, never a CFrame write — see
	DriveController._recover for why that distinction is not negotiable. ]]
DriveConfig.HardYawDeg = 135

-- === Upright (the flip backstop) ============================================
--[[ THE OTHER TWO AXES. Everything above this point is about YAW — where the nose points — and
	yaw is the only rotation the game has an opinion about, because it's the only one steering can
	produce. Roll and pitch were left entirely to the suspension, which is right up until something
	puts the car on its roof: nothing in the drive layer, the chassis or the road brings it back,
	so a flip is a dead run that the player can still steer, still hear and still see a speedo for.

	It is reachable. There are no ramps or jumps in the obstacle set, so the car has no legitimate
	reason to leave level flight — but a solid traffic car clipped at a shallow angle can lever a
	wheel up (TrafficConfig.Collision), and the steal's handoff materialises the car in a lane that
	is only clear because the shell it landed on is about to be recycled. That's where it was first
	hit: a steal taken alongside a second car, which is what `StealConfig.Handoff.ClearMargin` now
	closes at source. This section is the general answer behind it.

	TWO MECHANISMS, in the same relationship as the yaw backstop's blend and its hard set: one
	physical and always the first thing to act, one a guarantee that it ends.

	  1. THE RIGHTING SERVO. Past `FreeTiltDeg` the car is rotated back toward level by an angular-
	     velocity write, exactly the tool `_lane` already holds the heading with. It ramps in over
	     `EngageDeg`, so a car that has merely been leaned on gets a gentle hand and a car that is
	     genuinely going over gets a firm one. Most of what this catches never becomes a flip at
	     all, and no reset beat plays — the player feels a car that refuses to trip, not a rescue.
	  2. THE RESET. If the car is still past `FlippedDeg` after `ResetAfter` seconds, the servo has
	     lost — it is on its roof, its wheels are off the deck and it has nothing to push against —
	     and the car is placed back on the road upright, square to it, keeping its position and a
	     share of its speed. That is a CFrame write, so it is done with the car ANCHORED, per the
	     same rule the steal's handoff spells out at length.

	Set `Enabled = false` to have flips be permanent again.

	Read this section together with MaxYawRate above: they bound the same envelope from two
	directions, and neither is a difficulty dial. Being spun, shoved and stood on your nose all
	still happen and still cost you speed — what they can't do any more is end the run silently. ]]
DriveConfig.Upright = {
	Enabled = true,

	--[[ Degrees off vertical the car may lean before any of this engages. Dormant below it, so
		normal driving is untouched by construction.

		20 is a long way outside anything the rig produces. Measured body roll with the rack
		stiffened is 0.04° dead straight and ~2° through the worst of the pre-fix wobble; the lane
		change is a yaw lean and adds no roll at all; and there are no ramps in ObstacleConfig, so
		the car never leaves the deck under its own steam. Anything past 20° is a collision. ]]
	FreeTiltDeg = 20,

	--[[ Degrees past FreeTiltDeg across which the servo ramps from doing nothing to fully owning
		the car's roll and pitch rate. A ramp rather than a switch for the reason every other
		threshold in this file has one: at full authority the servo SPECIFIES those two axes, and
		snapping that on at a hard angle would read as the car hitting an invisible rail.

		12 puts full authority at 32°, which is well past a lean you could drive out of and well
		short of the 70° where the car is already gone. ]]
	EngageDeg = 12,

	-- Righting rotation, radians/s per radian of tilt past FreeTiltDeg. This is the same shape as
	-- LeanGain — a servo, so it pulls from any angle — and 5 rights a 45° lean in about a third of
	-- a second. Lower feels like a car with a low centre of gravity; higher feels magnetised.
	LevelGain = 5,

	-- Ceiling on that rotation, rad/s. The reason a hit still reads as a hit: the car is allowed to
	-- be knocked over quickly, it just can't be un-knocked faster than this. 3.5 ≈ 200°/s, so even
	-- a full inversion takes most of a second to come back — which is what makes it a recovery you
	-- watch rather than a pop. Sits alongside MaxYawRate (3.0) on the yaw axis.
	MaxLevelRate = 3.5,

	--[[ Past this many degrees the car is FLIPPED: on its side or its roof, no wheel is carrying
		load, and everything that would normally right it — suspension, tyres, the servo above
		pushing against the deck — has nothing to work with.

		70 rather than 90 on purpose. A car resting at 75° is not coming back on its own, and
		waiting for it to fall the rest of the way just adds dead air to the beat. ]]
	FlippedDeg = 70,

	--[[ Vertical speed the car is held at, minimum, while it is flipped — a FLOOR on the Y
		component, not an added push, so it can't accumulate.

		This is what stops the recovery grinding. The servo rotates the assembly whether or not
		anything is in the way, so a car spun on its roof digs its corners into the deck and gets
		flung by the solver resolving that. 6 studs/s lifts it clear over the ~0.9s the roll takes,
		about four studs, and it lands back on its wheels. It also happens to be the whole visible
		reaction: a little hop-and-roll, which is the arcade version of righting a car and cheap
		enough not to need juice bolted onto it. 0 switches it off. ]]
	Lift = 6,

	--[[ Seconds continuously past FlippedDeg before the reset takes over from the servo.

		Long enough that the servo gets a real attempt first (it needs ~0.9s from fully inverted at
		MaxLevelRate) and short enough that a landing on the roof never becomes waiting. When the
		servo does win, the reset never runs at all — which is the intended common case. ]]
	ResetAfter = 1.1,

	-- Studs the reset leaves the car's lowest bodywork above the deck, for the suspension to take
	-- down. Same value and same reason as RaceConfig.SpawnClearance and StealConfig.Handoff.Clearance.
	Clearance = 0.5,

	--[[ Fraction of the car's along-road speed carried through the reset. The flip already cost
		the player most of it (they've been sliding on a roof), so this mostly decides whether they
		come back rolling or from a standstill; AutoThrottle winds them back up either way.

		0.4 is a real penalty that still isn't a stop. Cross-road speed and all rotation are dropped
		outright — the reset exists to hand back a car pointed down the road and settled. ]]
	KeepSpeed = 0.4,
}

--[[ === Pinned: the car that is stuck but not flipped ========================

	`Upright` above recovers a car that has GONE OVER, and it is gated entirely on tilt — nothing in
	it fires for a car sitting flat. That leaves the other half of "stuck" with no way out at all,
	and it is the half players actually report: wedged upright against the median, half up on the
	raised kerb, throttle doing nothing, speedo reading 3 MPH. Three testers hit it in one session
	(playtests/2026-08-24), plus the same state reached a second way — the getaway truck spawning on
	top of the car you just stole, which leaves the two hulls interpenetrating and nothing to clear
	them.

	The recovery already exists; only the trigger was missing. `_resetUpright` puts the car back on
	the deck, upright, square to the road, and — this is the line that matters here — it clamps the
	cross-road offset into `LaneHalfWidth` on the way, precisely "because the most common way to get
	properly stuck is to slide into the guardrail". So a pinned car reaches the same reset a flipped
	one does, and comes back on the lane rather than back on the rail it was welded to.

	IT IS GATED ON THE PLAYER ASKING TO GO. Speed alone would fire on somebody stopped at the top of
	a run, braking, or held by a tutorial beat; throttle-and-no-speed is unambiguous, and it is a
	question the shim can answer for free because `_shapeThrottle` already stashes the raw input for
	the tutorial to read. UNDER `AutoThrottle` THE PEDAL IS ALWAYS DOWN, so "asking to go" is "not
	holding the brake" (2026-10-07): it used to want the raw input positive, which meant holding
	BOOST, and a player who just steered was never rescued. ]]
DriveConfig.Pinned = {
	Enabled = true,

	--[[ Forward studs/s under which the car counts as going nowhere.

		6 is about 4 MPH. Deliberately above the 3 MPH the wedge reports show rather than at a dead
		stop: a car grinding along a rail is still technically moving, and a threshold at zero would
		watch it do that for the rest of the run. Well under anything a driver would call driving. ]]
	Speed = 6,

	--[[ Seconds of throttle-with-no-speed before the reset takes over.

		2.5 is long on purpose. This is the last resort, and every false positive is a car that
		teleports sideways under a player who was merely accelerating out of a corner slowly — much
		worse than the two extra seconds a genuinely stuck player waits. Nothing in normal driving
		holds full throttle under 6 studs/s for this long: from a standstill the roster's slowest
		body is past it in well under a second.

		It is also the effective cooldown. The timer resets after each reset, so a car that is
		somehow still pinned afterwards is retried on the same interval rather than every frame. ]]
	After = 2.5,

	--[[ Studs around the car inside which knocked traffic (wrecks only, never live traffic) is
		recycled just before the reset. The reset keeps our place on the road, so without this a car
		wedged against a wreck is put straight back inside it. Two car lengths. 0 = leave them. ]]
	ClearWrecks = 40,
}

-- === Staying in the car =====================================================

--[[ Hold the player in their seat for the length of a race, so the stock "get out" cannot end a
	run by accident.

	THE STOCK VEHICLE OWNS E, and the comment in StealConfig.Prompt claiming otherwise was simply
	wrong: the deployed `Driver` LocalScript binds `VehicleChassisExitVehicle` to
	`Keymap.EnterVehicleKeyboard` (E) and `Keymap.EnterVehicleGamepad` (ButtonY), and that handler
	calls `LocalVehicleSeating.ExitSeat()`. Pressing E mid-race therefore unseats the driver at
	speed — which is not a get-out, it is the end of the run, because RaceService's `_watchRiderWeld`
	and RoadController's car latch are both built on the player staying in that seat. Reported as
	"I pressed E and the race just ended".

	This does NOT touch the lobby. It is bound on RaceStart and dropped on RaceEnd, so a car driven
	anywhere else keeps its ordinary exit (the boss's explicit ask — the lobby's own get-out is a
	later pass).

	The steal is deliberately unaffected: StealController binds E at `StealConfig.BindPriority`
	(3500) for the length of a flight, which is above the priority below, so E still takes a car
	while you are in the air and still does nothing at all when you are not. ]]
DriveConfig.HoldSeatDuringRace = true

--[[ The keys to swallow, mirroring the stock `Keymap.EnterVehicleKeyboard` / `EnterVehicleGamepad`.

	Duplicated here rather than read off the car's own Keymap on purpose: that module is place-side
	and per-car (43 copies), so requiring it would make this depend on a structure a redress or a
	fresh CarBones import can change, to save maintaining two constants that have not moved since
	the kit shipped. If a future kit rebinds the exit key, this is the one line to follow it. ]]
DriveConfig.ExitKeys = { Enum.KeyCode.E, Enum.KeyCode.ButtonY }

--[[ Priority the swallow is bound at, chosen to sit in the gap between two things that must both
	keep working:

	  • ABOVE the stock exit binding, which uses plain `BindAction` and so lands on
	    ContextActionPriority.Default (2000). That is the whole point.
	  • BELOW the stock raw-input binding at .High (3000) and below StealConfig.BindPriority (3500),
	    so neither driving input nor the steal's own E can be starved by this.

	2500 is that gap. Sharing a priority with either neighbour would leave the winner decided by
	bind ORDER, which changes with how fast the server deploys the controls. ]]
DriveConfig.ExitLockPriority = Enum.ContextActionPriority.High.Value - 500

-- === Rig assumptions ========================================================
-- Which way a positive `steer` value turns the stock chassis. True (left) is what the
-- shipped CarBones Keymap produces: SteerLeft has no Sign so it yields +1, SteerRight is
-- Sign = -1, and the touch stick is `-GetMoveVector().X`. Flip this only if a rig's
-- steering is rebound — if it's ever wrong, the cone will push the car *away* from the
-- road instead of back onto it, which is unmistakable.
DriveConfig.PositiveSteerIsLeft = true

-- Settle nitro overspeed without changing lateral or vertical motion.
DriveConfig.NitroRecovery = { Seconds = 6, Deceleration = 55, CruiseHeadroom = 1.04, KickCooldown = 1 }
function DriveConfig.nitroRecoveryDelta(speed: number, ceiling: number, dt: number): number
	return math.min(math.max(speed - ceiling, 0), DriveConfig.NitroRecovery.Deceleration * math.clamp(dt, 0, 0.1))
end
--[[ THE FLOATER'S HOP (2026-10-22, the Roadster Limited Event). A car flagged `Hop` in
	`WorldConfig.EventBodies` lifts off on cold-gas thrusters, one under every wheel, the way the real
	Roadster did at its Oct 15 2026 demo. In a run and in the lobby. Its own key, because Space is the
	bail in a run and the character's jump in the lobby. `Enabled = false`: no hop.

	TAP: a kick of `Speed` studs/s up, every physics body in the car at once.
	HOLD: the thrusters stay lit and the car climbs to `Float.Height` above the launch and FLOATS there,
	bobbing, for up to `Float.Seconds`. Under the race camera's follow cap (`CameraConfig.MaxJumpFollowStuds`
	25), so the car stays in shot. Let go, or run out, and it comes down.
	THE LANDING: from `Land.Probe` studs above where the car sits at rest, the thrusters fire again and
	hold the fall to `Land.Speed`, easing to `Touch` over the last `Final`, so the wheels meet the deck at
	a walk. The gyro holds on for `Settle` seconds after.

	PHYSICS CONSTRAINTS, NOT VELOCITY WRITES (2026-10-22, third pass). A `LinearVelocity` on every
	assembly lifts the chassis and the four wheels together, with a force cap (`Accel`, studs/s² on top of
	gravity) so it eases in instead of snapping; an `AlignOrientation` is the gyro. The second cut wrote
	velocities by hand each frame: it felt stiff, a lobby car could still tip, and in a run it lifted
	nothing, because it listed the car's bodies once, during the countdown, when the car is anchored. ]]
DriveConfig.Hop = {
	Enabled = true,
	--- L3, not DPadUp: DPadUp is `GamepadConfig.FocusGlyph` (open the menu), and L3 is bound nowhere else.
	Keys = { Enum.KeyCode.R, Enum.KeyCode.ButtonL3 },
	--- The on-screen button on touch devices (ContextActionService's own).
	Title = "HOP",
	ButtonPosition = UDim2.new(1, -170, 1, -210),
	Cooldown = 0.8,
	--- A hop starts only with the ground this close under the PrimaryPart.
	GroundProbe = 8,
	Speed = 50,
	Float = {
		Height = 14,
		--- Fastest climb toward the float height, studs/s, and how hard it closes the gap (per second).
		Climb = 34,
		Gain = 4,
		Accel = 160,
		Seconds = 3,
		--- Air (seconds of `Seconds`) every run launch spends, tap or hold, so tapping is not free.
		TapCost = 0.6,
		--- Time on grounded wheels to refill the whole air reserve after it is empty.
		RechargeSeconds = 8,
		Bob = { Studs = 0.8, Rate = 2.2 },
	},
	--[[ The in-run air reserve: a nitro-badge clone whose ring drains while R is held. `Offset` is
		its fallback placement when the shared powerup row is disabled; with the row on, layout is automatic. ]]
	Hud = {
		Enabled = true,
		Icon = 91745376365273,
		Color = Color3.fromRGB(110, 225, 255),
		Offset = Vector2.new(-1.12, 0),
	},
	Land = { Probe = 14, Speed = 16, Final = 4, Touch = 4, Settle = 0.6, Accel = 140 },
	--[[ IN A RUN THE CAR IS FLOWN, NOT SIMULATED (2026-10-22, fourth pass: three physics cuts lifted nothing
		in a run while working in the lobby). The run hop is the steal's own proven machinery
		(`StealController._onBail`): the drive layer is suspended, the car anchored and moved along the road
		frame each frame, then handed back at its resting height with its speed. So nothing in a run can
		cancel it, and nothing can flip it. Same `Speed`, `Float` and `Land` numbers as the lobby.
		`Gravity` is a share of `workspace.Gravity` for the fall (under 1 is floatier); `AirLaneSpeed` is
		how fast the steer moves the car across the road in the air (studs/s, `DriveConfig.LaneSpeed` is the
		ground's); `MaxPitchDeg`/`MaxRollDeg` tilt it with the climb and lean it into that steer. The lobby has
		real walls and no road frame, so it keeps the physics version. ]]
	Run = { Gravity = 0.8, AirLaneSpeed = 40, MaxPitchDeg = 9, MaxRollDeg = 12 },
	--[[ THE GYRO: the real car's attitude-control thrusters. Holds the car upright in the air (`Responsiveness`,
		the constraint's own), leaving yaw to the steering. It is not dead level, for life: the nose lifts up to
		`MaxPitchDeg` as the car climbs and dips as it falls. In the lobby the steer turns the car in the air
		(`AirTurnRate`, rad/s at full lock) and it leans into the turn (`MaxRollDeg`); in a run the drive layer
		already owns the heading. ]]
	Gyro = { Responsiveness = 25, MaxPitchDeg = 9, AirTurnRate = 2.2, MaxRollDeg = 10 },
	--[[ THE LOOK. One thruster per wheel, mounted on the chassis at the tyre's contact patch so it rides
		with the car (never on the wheel, which spins):
		  `Plume`  frosty cold-gas jet, the body of the thrust.
		  `Core`   a hot cyan needle inside it, additive, so the jet reads as powered from far down the road.
		  `Frost`  glitter thrown off the jet, the "it is freezing cold" note.
		  `Trail`  a cyan streak off each thruster while the car is in the air.
		Each streams at `Rate` while thrusting (scaled down on the landing burn) and fires `Burst` at once on
		launch (`Land.Scale` of that on touchdown). On the ground under the car: `Cloud`, a billow blown flat
		(launch, landing, and the wash while flying low), and `Ring`, a shimmering shockwave disc. `Glow` is a
		cyan underlight, flashed on launch and held while thrusting. Every count is per wheel. ]]
	Puff = {
		Plume = {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Color = { Color3.fromRGB(200, 240, 255), Color3.fromRGB(235, 245, 255) },
			LightEmission = 0.4,
			Rate = 70,
			Burst = 22,
			Speed = { 45, 70 },
			Spread = 10,
			Lifetime = { 0.3, 0.55 },
			Size = { 1, 5 },
			Transparency = 0.15,
		},
		Core = {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Color = { Color3.fromRGB(120, 230, 255), Color3.fromRGB(60, 140, 255) },
			LightEmission = 1,
			Rate = 110,
			Burst = 12,
			Speed = { 70, 90 },
			Spread = 3,
			Lifetime = { 0.1, 0.18 },
			Size = { 1.1, 0.2 },
			Transparency = 0,
		},
		Frost = {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Color = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 220, 255) },
			LightEmission = 1,
			Rate = 25,
			Burst = 14,
			Speed = { 12, 28 },
			Spread = 55,
			Lifetime = { 0.5, 0.9 },
			Size = { 0.5, 0 },
			Transparency = 0,
		},
		Cloud = {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Color = { Color3.fromRGB(225, 240, 255), Color3.fromRGB(200, 215, 230) },
			LightEmission = 0.2,
			Rate = 0,
			Burst = 26,
			Speed = { 18, 32 },
			Spread = 80,
			Lifetime = { 0.8, 1.4 },
			Size = { 3, 10 },
			Transparency = 0.3,
		},
		Trail = {
			Color = { Color3.fromRGB(110, 225, 255), Color3.fromRGB(255, 255, 255) },
			Lifetime = 0.3,
			Width = 0.7,
			Transparency = 0.25,
		},
		--- Seconds between ground-wash puffs while thrusting, and how far down the ground still gets one.
		Wash = { Every = 0.09, Count = 4, Reach = 30 },
		Ring = { Color = Color3.fromRGB(120, 220, 255), From = 4, To = 34, Time = 0.45, Transparency = 0.2 },
		Glow = { Color = Color3.fromRGB(90, 200, 255), Range = 18, Brightness = 3, Flash = 8 },
		--- The landing burn's streams, as a share of `Rate`; its burst, as a share of `Burst`; its ring.
		Land = { Rate = 0.45, Scale = 0.5, RingTo = 20 },
	},
	--[[ SOUND. `Loop` is the experience group's authored thrust clip; `Launch` and `Land` use Roblox's
		built-in character clips as lightweight bookends. A clip named `Name` in `SoundService[Group]`
		replaces the launch once one is authored. ]]
	Sound = {
		Group = "Steal",
		Name = "Hop",
		Launch = { Id = "rbxasset://sounds/action_jump.mp3", Volume = 0.9, Pitch = 0.55 },
		Loop = { Id = "rbxassetid://131792141808870", Volume = 2.5, Pitch = 1 },
		Land = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.8, Pitch = 0.7 },
	},
	--- The camera: the race camera's own punches in a run (`StealJuiceConfig.Punch.HopLaunch`/`HopLand`); in
	--- the lobby a field-of-view kick of `LobbyFovKick` degrees, eased back over `LobbyFovTime` seconds.
	Camera = { LobbyFovKick = 10, LobbyFovTime = 0.5 },
}
return DriveConfig
