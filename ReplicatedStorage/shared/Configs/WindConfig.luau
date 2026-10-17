--[[
	WindConfig
	----------
	THE AIR GOING PAST WHEN YOU ARE FLAT OUT. Streaks that swell in over the last few percent of
	what the car can do and are gone the moment you lift — so that being maxed out is something the
	screen shows rather than something the speedo says.

	The art is authored, not built here: `ReplicatedStorage.WindParticles` is a Part with three
	ParticleEmitters on it (Layer1..3), and its texture, colour, flipbook, squash and
	velocity-parallel orientation — everything that decides what a streak LOOKS like — are left
	exactly as authored. What this file owns is everything that depends on where the camera is and
	how fast it is going, which the artist had no way to author: how many streaks there are, how
	fast they fly, how long they live, how solid they are, and how they composite.

	=== IT IS FLAT OUT, NOT FAST: THE BAND IS A FRACTION OF **THIS CAR'S** TOP SPEED ============

	The wind is not a speedometer. It appears in the last few percent of what the car you are
	driving can do and nowhere else, so it says ONE thing — you are flat out — and says it the same
	way in a world-1 beater and in a supercar. An absolute speed band cannot do that: a number
	chosen so the Charger's boost tops it out would be ordinary cruising in a fast car, and the
	effect would drift from "flat out" to "expensive car" without anyone touching it.

	So the band is `StartFraction`..`FullFraction` OF THE CAR'S OWN CEILING, which is
	`DriveController:getTopSpeed()` — the base `MaxSpeed` attribute times the boost scale, i.e. the
	fastest that car goes with accelerate held. Measured on a Charger (the start car at the time)
	that lands the band at 101..112 studs/s, so ordinary cruising (a rock-steady 84-85, measured)
	has no wind at all and holding accelerate brings it in. Every car scales the same way, which is
	the point — the numbers move with `MaxSpeed`, the fractions do not.

	`StudsPerMaxSpeed` is the awkward part and there is no way around it: the attribute is not in
	studs per second. See its note.

	=== THE SPEED IT READS IS THE CAR'S, ALONG THE ROAD ========================================

	Two axes of that matter. Reading the CAR rather than the camera, because the camera's
	frame-to-frame speed swings ±15 studs/s around the car's steady value (its follow lag is the
	whole point of that camera) and a noisy input against a sharp threshold flickers. And along the
	ROAD rather than along the nose, because the nose picks up sideways velocity: sustained hard
	steering ratchets a nose-relative reading past 120 on a car that is doing 84 down the road,
	which would hand out a flat-out effect for cornering.

	It follows that there is no wind while the car is not being driven — either end of a race, where
	there is no car, and a wreck, which coasts out of the band on its own (which is why nothing in
	WindController has a wreck case in it). A FROZEN car does not follow, though, and used to be the
	hole in all of this: anchoring a part does not clear its velocity, so an anchored car goes on
	reporting the speed it was doing when it was frozen and the wind went on blowing for the whole of
	a bail, a whiff and everything after it. See `Flight` below and `WindController._velocity`.

	=== THE BOX ================================================================================

	Streaks spawn throughout a box that rides `Ahead` studs in front of the camera and are then
	left in world space, so the camera drives through and past its own weather — which is what
	makes the effect read as air rather than as a screen overlay. Width and Height only have to
	cover the frame at that distance; Depth is what stops them arriving in visible waves.
]]

local WindConfig = {}

-- Master switch. Off = no rig is ever built and nothing runs per-frame.
WindConfig.Enabled = true

-- Child of ReplicatedStorage the rig is cloned from, once per race. A Part with any number of
-- ParticleEmitters under it; `Layers` below is matched to them by name order.
WindConfig.Template = "WindParticles"

-- === The band ===============================================================
-- Shares of the car's own top speed (`DriveController:getTopSpeed()`), measured along the road.

--[[ Where the wind starts. On the starting car this puts it at 101 of a 112 studs/s ceiling.

	It is a band and not a switch because the car takes about eight seconds of held accelerate to
	pull from cruise to its ceiling: the wind comes in over the last two of those, which reads as
	the speed arriving rather than as an effect being turned on. Lifting off runs the same thing
	backwards over a longer coast.

	Do not lower this much. Ordinary cruise sits at 0.75 of the ceiling (84.3 of 112.2 measured),
	so anything under about 0.8 is on for the whole race and the effect stops meaning "flat out". ]]
WindConfig.StartFraction = 0.84

-- Where it reaches full. 1 is the car's own ceiling, and the car does genuinely sit there with
-- accelerate held — so the top of the band is a place you HOLD, not a spike you pass through.
WindConfig.FullFraction = 1

-- Shapes the band between those two. 1 is linear. There is very little room in a 10% band for a
-- curve to say anything, so this is mostly here to match the other ramps in the project.
WindConfig.Curve = 1

--[[ Studs per second per unit of the `MaxSpeed` attribute. 2.12, measured.

	The attribute is not a speed. The chassis damps its driving torque by exp(-3r²) with
	r = speed / MaxSpeed and the car settles where that torque dies, so what the attribute sets is
	a torque curve and the settled speed is an emergent multiple of it. The starting car reads 39.2
	on the dial and holds a rock-steady 84-85 studs/s; boosted it reads 52.92 and settles at 112.

	CALIBRATED ON THE BOOSTED FIGURE, deliberately: 112 / 52.92 = 2.12, where cruise alone would
	have said 2.15. The two disagree because the drag the car is settling against is not linear,
	and the boosted end is the one this file cares about — it is what `FullFraction` = 1 has to
	mean. Taking cruise's 2.15 instead puts the top of the band at 114.8, which the car never
	quite reaches, and the effect then tops out at four fifths of itself forever.

	TO RE-MEASURE: bare road (obstacles and traffic off), hold accelerate, wait for the speed to
	stop climbing — it takes a good eight seconds — then divide the settled along-road speed by
	`DriveController:getTopSpeed()`. If a future chassis changes that damping this is the number
	that goes stale, and the symptom is the wind never arriving (factor too high) or never leaving
	(too low) rather than an error. ]]
WindConfig.StudsPerMaxSpeed = 2.12

-- Seconds the intensity takes to close most of the gap to where it wants to be, coming up and
-- going down. The rise is the slower of the two here: the band is narrow, so the car crosses it in
-- a moment, and a swell rather than a switch is what stops that reading as a pop.
WindConfig.RiseTime = 0.25
WindConfig.FallTime = 0.5

-- A live near-miss chain can push an already-present wind effect past its ordinary ceiling. It
-- never creates wind below the speed band; it only makes flat-out driving feel hotter.
WindConfig.Flow = {
	RateBoost = 0.4,
	OpacityBoost = 0.1,
	SizeBoost = 0.08,
}

--[[ === WHEN YOU ARE OUT OF THE CAR (the bail) =================================

	A bail is the one time the player is doing 112 studs/s with no car around them, and it is not a
	case the band can be left to work out for itself: the car they left is ANCHORED, and an anchored
	car keeps reporting the speed it was frozen at forever. Left alone, a bail taken flat out ran the
	wind at full for the whole flight and a whiffed one ran it until the race ended.

	So StealController hands the arc over instead (`WindController.setFlight`) and the wind is
	measured against the FLIGHT: same band, same fraction of the same car's ceiling, read off the
	arc's along-road speed. Which ends the effect on its own, in the shape of the jump rather than on
	a cue — `Launch.ForwardKeep` = 1 means you leave the seat at exactly the speed you were doing, so
	the air rips past through the throw and the rise, and `Flight.Glide` brakes you to traffic pace a
	tenth of a second after the apex, which is far under the bottom of the band. It is dying at the
	top of the jump and gone through the float down.

	`Enabled = false` is the blunter reading of the same problem: the wind stops dead at the seat,
	and everything above still holds for the anchored car. ]]
WindConfig.Flight = {
	Enabled = true,

	--[[ How much of the arc's VERTICAL speed the streaks lean with, 0..1. 1 is the honest angle: at
		the throw (`StealConfig.Launch.Up` = 108 against ~112 along the road) that is about 44° off
		the road, so the air sweeps DOWN past you as you are thrown up, flattening out as the rise
		does — which is the whole reason this is here rather than the wind simply stopping.

		The tilt is the vertical only. Sideways is the player's own air steering and would swing the
		box every time they corrected a lane, for the same reason the band ignores sideways speed.

		Lower it if the streaks ride too high in the frame during the rise: the box goes where it
		aims (they are one axis, see `WindController._travel`), so at 1 its centre sits ~19 studs
		above the camera for the first third of a second. 0 keeps the flight's speed and puts the
		streaks flat down the road. ]]
	Tilt = 1,
}

--[[ === The box streaks spawn in ===============================================

	Studs. Width is across the direction of travel, Depth along it, Height up.

	SIZE THIS TO THE FRAME, NOT TO THE ROAD. Every streak that spawns outside the view costs the
	same as one inside it and is never seen, so the box wants to be about the frustum's
	cross-section at the distance it rides and no bigger. At `Ahead` = 28 and the race camera's
	70° vertical FOV that is roughly 39 studs tall and 70 wide on a 16:9 screen, and the defaults
	sit just inside it. Widening this does not give more wind — it gives the same wind, thinner,
	for the same cost. Raise `Layers[].Rate` for more wind.

	`Depth` is what keeps streaks from arriving in visible pulses, and the near face of the box
	(Ahead - Depth/2) is what must stay in FRONT of the camera: anything born behind it is spent
	before it is seen. ]]
WindConfig.Box = {
	Width = 64,
	Depth = 46,
	Height = 36,
}

-- Studs in front of the camera the box's CENTRE rides, and studs above it.
WindConfig.Ahead = 28
WindConfig.Lift = 1

-- === The streaks ============================================================

--[[ Seconds a streak lives.

	This and `Layers[].Rate` are the same knob wearing two hats: what is on screen at any moment is
	rate x lifetime, and both cost the same per particle. Lifetime is the cheaper half to spend,
	because a streak that outlives the frame is simply behind you and invisible, whereas rate has
	to keep paying to replace what left.

	The floor on it is the trip across the box: at cruise a streak closes on the camera at its own
	speed plus the car's, call it 145 studs/s, so it crosses the 46-stud box in a third of a
	second. Under that and streaks wink out in front of you, which reads as flicker. ]]
WindConfig.Lifetime = NumberRange.new(0.5, 0.9)

-- Studs/s a streak flies BACKWARD along the direction of travel, on top of the camera's own
-- motion — so the closing speed you actually see is roughly this plus your road speed. The idle
-- figure is not zero because a still particle has no velocity to orient along, and these are
-- oriented by velocity: at zero they would face an arbitrary way and read as confetti.
WindConfig.SpeedIdle = 16
WindConfig.SpeedFull = 85

-- Degrees of scatter on that direction. Small — this is wind down a road, not a snowstorm.
WindConfig.SpreadAngle = Vector2.new(3, 3)

--[[ Studs across, before the emitter's authored squash stretches it along its travel. The growth
	is the extra fraction added at full speed.

	This is much larger than it looks like it should be, and the authored Squash of -2 is why: side
	by side against the same emitter at Squash 0, it turns a broad soft swoosh into a long
	HAIRLINE. What lands on screen is therefore a line, not a 5-stud blob, and anything under about
	4 here is thin enough to disappear entirely against the road. ]]
WindConfig.Size = 5
WindConfig.SizeGrowth = 0.5

-- How solid a streak gets at each end of the band (0 = invisible, 1 = the texture at full).
-- The texture is a soft streak with very little alpha of its own, and the squash above thins it
-- further, so these read far gentler on screen than the numbers suggest — but they are still
-- deliberately short of solid. This sits between the player and the road they are reading at the
-- exact moment they are going fastest, so it has to be something you notice at the edge of the
-- frame rather than something you look through.
WindConfig.OpacityIdle = 0.3
WindConfig.OpacityFull = 0.82

--[[ How the streak composites, and the reason the art is invisible if you leave it as authored.

	The emitters ship at LightEmission 1, which is fully ADDITIVE: the streak adds its colour to
	whatever is behind it. That is right for a huge volume seen against distant scenery, and wrong
	here, because half of a race frame is bright sky and white lane paint — adding pale blue to
	something already near-white does nothing at all, and the effect simply disappears over the top
	half of the screen while working over the tarmac. Blending it mostly normally costs a little
	of the glow and gets an effect that reads the same wherever it happens to be.

	LightInfluence is the other half of the same problem: at 1 the streak is tinted by the scene's
	lighting, so it would go dim at dusk on a world that has one. At 0 it is its own colour. ]]
WindConfig.LightEmission = 0.3
WindConfig.LightInfluence = 0

-- Fractions of a streak's life spent fading in and beginning to fade out. The fade-in is what
-- hides the pop of a particle appearing out of nothing inside the frame; without it the box's
-- near face is visible as a line streaks are born on.
WindConfig.FadeIn = 0.15
WindConfig.FadeOut = 0.7

--[[ The emitters on the template, and what each one contributes.

	Three copies of one emitter would just be one emitter at triple the rate. Varying them gives
	the air some depth: a lot of small quick ones for the wash, a few big fast ones that whip past
	and are the thing you actually notice. `Rate` is particles per second AT FULL INTENSITY and
	scales down the ramp with everything else; `Size` and `Speed` are multipliers on the two
	values above.

	The totals are the effect's whole cost: 595/s across the three, times the ~0.7s average
	lifetime, is about 417 live particles at full — and full only happens while the car is
	held flat out, with nothing at all the rest of the time. A denser version of this measured
	about a quarter of a millisecond a frame in a running race. Everything else in this file is a
	number; this is the one that is a budget.

	Matched to the emitters BY NAME ORDER — Layer1 gets the first entry — and cycled, so an extra
	emitter added to the template gets the first layer's numbers rather than nothing. ]]
WindConfig.Layers = {
	{ Rate = 300, Size = 0.7, Speed = 0.8 },
	{ Rate = 190, Size = 1.0, Speed = 1.0 },
	{ Rate = 105, Size = 1.55, Speed = 1.3 },
}

return WindConfig
