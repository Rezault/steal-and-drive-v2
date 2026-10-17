--[[
	CameraConfig
	------------
	The race camera: a chase cam that rides the car's POSITION in the ROAD's frame and takes a
	PARTIAL, LAGGED share of its HEADING. Weave across the road and the shot slides sideways with
	you and swings a little way into the turn — enough that steering reads as rotation, not enough
	that the road stops reading as a straight corridor you're threading.

	Why it's a share and not all-or-nothing. There are two obvious cameras and both are wrong:

	  • Roblox's stock VehicleCamera, which is what you get by default the moment you sit in a
	    VehicleSeat, chases the heading 1:1 — so a flick of the wheel pivots the entire world and
	    the corridor read is gone.
	  • A FIXED orientation, built once from the road's forward axis, which is where this camera
	    started (Rodeo Stampede's shot, and the right instinct for a runner). It reads beautifully
	    in first person — where your view is bolted to the car, so yaw is its own feedback — and
	    wrong in third, because a frame that never rotates deletes every rotational cue a turn
	    has. You steer, the car pivots inside a static shot, and the only thing that actually
	    changes is a slow sideways slide. Identical physics, and it feels like understeer.

	What's here now is the middle ground the mobile traffic-racers use (Mr Racer, Traffic Racer,
	Racing Limits): most of the heading, capped well short of the nose, arriving a beat late, with
	a touch of bank.

	Three things to know before editing:

	1. YawFollow = 0 RESTORES THE OLD FIXED CAMERA EXACTLY — not approximately: the swing, the
	   rotated chase offset and the bank all collapse to identity, and every other value below
	   means what it always meant. Keep it that way, because it's the honest A/B for anything
	   you change in the Turning section.

	2. POSITION IS STILL PURE ROAD FRAME. Every distance below is measured along the road's own
	   axes, and the car's CFrame reaches exactly one thing: the swing. That's what keeps the shot
	   stable across tile recycles and RoadController's rebase (see RaceCameraController).

	3. FOLLOW LAG IS THE JUICE, not a bug. The gains below are what let the car slide within
	   the frame when you cut across a lane and settle back to centre when you straighten up.
	   Crank them all to 30 and you get a rigidly welded shot that reads as much less fast.

	Reference numbers for tuning: the deck is ~73.5 studs wide (obstacle lanes at ±30), the
	car is ~8.4 wide and ~21 long, cruise is ~52 studs/s and boosted cruise ~71.
]]

local CameraConfig = {}

-- Master switch. Off = whatever Roblox gives you, which is the stock VehicleCamera chasing
-- the car's heading. Worth flipping to compare feels.
CameraConfig.Enabled = true

-- === Where the shot sits ====================================================
-- All three are measured in the road's frame: Distance straight back down the road from the
-- car, Height above the deck. Neither depends on which way the car is pointing.

-- Studs behind the car. The high-chase experiment uses a little more distance so the raised shot
-- frames the full car and several lanes of traffic rather than looking down onto its roof alone.
CameraConfig.Distance = 28

-- Studs above the deck (RoadController's `deckY` — the same surface the car spawns on and
-- traffic drives on, so this is stable for a whole race even as tiles recycle).
CameraConfig.Height = 22

-- Degrees the camera tilts DOWN. This is the value that decides how the frame is split
-- between road and sky, and where the car sits vertically in it.
--
-- At the high-chase defaults (28 back, 22 up, 24° down, 68° FOV), the horizon moves toward the
-- top of the frame and considerably more road is visible around the car. This is intentionally
-- closer to an elevated arcade traffic-reading camera than a low cinematic chase camera.
-- Raise it to look further down at the road (more obstacle warning, less horizon), lower it
-- to open up the view ahead (more scenery, less warning).
CameraConfig.PitchDeg = 24

-- Field of view while racing, degrees. 70 is the Roblox default; wider exaggerates speed and
-- shows more of the road's width. Set to nil to leave whatever FOV the player already had.
CameraConfig.FieldOfView = 68

-- === The low chase (flag) ===================================================
--[[ The bridge shot, made permanent.

	`Cover` further down drops the camera to 11 studs and hands 8 degrees of down-pitch back
	whenever the road goes under something, and those two seconds are the shot we liked enough to
	ask for everywhere. This flag is that ask. Same height, same lens, all the time, with
	`Distance` and `FieldOfView` untouched, so what you get is the ducked shot exactly rather than
	a new one that resembles it.

	Enabled = false restores the high chase above, exactly. Nothing here rewrites `Height` or
	`PitchDeg`: those two still read as the shot the game ships without this flag, so they remain
	the honest A/B for anything tuned against them.

	WHILE THIS IS ON, THE DUCK IS OFF. The shot already sits under every roof in the game (the
	lowest is FuturisticCity's bridge at 17.6 studs), so all the duck could still do is tilt the
	lens on the one beat that now looks like the whole race. `RaceCameraController._stepCover`
	reads this flag and stays home while it is set. ]]
CameraConfig.LowChase = {
	Enabled = true,

	-- Studs above the deck, standing in for `Height`. It is `Cover.Height`.
	Height = 11,

	-- Degrees down, standing in for `PitchDeg`. It is `PitchDeg` plus `Cover.ExtraPitchDeg`
	-- (24 - 8), which is what the lens does under a bridge today.
	PitchDeg = 16,
}

-- === Turning (swing & bank) =================================================
-- The camera's share of the car's heading, and the section to reach for when steering "doesn't
-- feel right" in third person. The failure it fixes is specific: with a fixed frame, a turn has
-- no rotational cue at all — you steer, the car pivots inside a static shot, and the only thing
-- that changes is a slow sideways slide, which reads as understeer on a car that is in fact
-- turning perfectly well. First person never had the problem because your view IS the car.

-- Fraction of the car's heading error (the angle between its nose and the road direction) that
-- the camera adopts.
--
--   0    the fixed-orientation camera this started as, exactly. The honest A/B.
--   1    the shot lines up with the nose, so the car looks perfectly square in frame at all times
--        and only the world rotates.
--
-- THESE DEFAULTS ARE SIZED FOR HYBRID DIRECT STEERING, where the nose reaches 9° at normal cruise
-- and up to 12° at the top of the speed range. Taking 65% leaves the car visibly turning inside
-- the shot before the frame follows, while the road remains a primarily forward corridor.
--
-- If you switch DriveConfig back to the cone, re-tune BOTH: against a 30° nose, 1 pivots the world
-- like the stock VehicleCamera. 0.7 with a 15° cap is the pair that works there.
CameraConfig.YawFollow = 0.65

-- Hard cap on that swing, degrees, whatever the heading does.
--
-- 9 deliberately clips the camera's share of the 12° high-speed steering target, so the car can
-- rotate farther inside the shot. It also caps collision yaw so the corridor cannot whip around.
CameraConfig.YawMaxDeg = 9

-- How fast the swing closes on where it wants to be, per second — the same exponential as the
-- follow gains above.
--
-- Unlike those, this one is a real tradeoff rather than "higher is tighter". High reads
-- responsive and slightly mechanical; low reads weighty and lets the frame settle a beat after
-- you straighten up, which is a lot of the charm of these cameras. But push it too low and the
-- rotation arrives after the turn is over, which is the whole problem this section exists to
-- fix — so this is a floor as much as a taste knob. 7 ≈ a 0.14s lag.
CameraConfig.YawGain = 7

-- Degrees of roll at a full YawMaxDeg swing, scaled linearly by however far it's actually swung.
-- POSITIVE banks INTO the turn (turning left leans the camera left), which is the arcade
-- convention; NEGATIVE leans out of it, mimicking the car's real body roll. 0 = dead level.
--
-- Keep it small. This is a garnish you feel rather than see, and it's the one value here that
-- will look silly long before it looks strong — 2° is about where it stops being noticeable as
-- an effect and starts just making the turn feel weighted.
CameraConfig.RollDeg = 2

-- === Follow response ========================================================
-- Exponential approach rates, per second: the camera closes the gap to where it wants to be
-- at this rate. Higher = tighter and more welded, lower = looser and laggier. The steady-state
-- lag is exactly (speed / gain) studs, so at 52 studs/s a gain of 20 trails by 2.6 studs.
--
-- "Exactly" is worth the word. What the two horizontal axes smooth is the LAG ITSELF rather than
-- the camera's position (see `restingLag` in RaceCameraController), so the number they produce is
-- the one above and nothing else — in particular it does not vary with frame rate, and it does not
-- pick up the 240Hz steps the car's rendered position actually moves in. Read a gain as a distance
-- and it will hold at 20fps and 240.

-- Along the road. Wants to be stiff: this is the axis the car is covering ground on, and a
-- soft gain here just reads as the car creeping away from the camera.
--
-- It is no longer the knob that decides how much render/physics stepping lands on the car — that
-- was a real effect (0.13 studs of fore-aft judder at 20, worse at 4, gone at 500) and it is what
-- smoothing the lag instead of the position removed outright. This is now free to be a pure taste
-- value again: the only thing it sets is how far the shot falls back when the car speeds up.
CameraConfig.AlongGain = 20

-- Across the road — the one the player actually feels, because weaving is the whole input.
-- 6.5 trails the hybrid assist enough for the car to move visibly off-centre,
-- so a hard cut visibly throws the car off-centre before the shot catches up. Drop toward 4
-- for a loose, drifty frame; push past 15 and lateral movement stops reading at all.
CameraConfig.LateralGain = 6.5

-- Vertical. Deliberately the softest of the three: the deck is flat, so nearly all of this
-- axis's movement is jumps, ramps and suspension, and a stiff gain turns every one of them
-- into a camera bounce.
CameraConfig.HeightGain = 5

-- How much of the car's lateral position the camera adopts, 0..1. 1 = the camera ends up
-- directly behind the car (subject to LateralGain's lag) — the Rodeo Stampede default.
-- Below 1 the camera hangs back toward the road's centre line and the car ranges further
-- across the frame on its own; 0 pins the camera to the centre of the road and lets the car
-- slide right out of shot at the edges.
CameraConfig.LateralFollow = 0.62

--[[ Counter-framing at the outer lanes. With LateralFollow below one, the camera stays closer to
	the road centre than the car: car left means camera right of it, and vice versa. These values
	then aim the lens back toward the car without rotating the chase offset itself. Keeping the aim
	separate is load-bearing — rotating the chase offset would orbit the camera back toward the car
	and erase the composition we just created.

	AimStrength is a share of the honest angle from the counter-framed camera to the car. MaxYawDeg
	keeps the highway readable at the outer lane, and YawGain gives the lateral composition a softer,
	longer settle than the immediate steering swing. ]]
CameraConfig.LaneFraming = {
	AimStrength = 0.55,
	MaxYawDeg = 7,
	YawGain = 4.5,
}

-- Air time. Fraction of the car's height above the deck that the camera climbs with it, and
-- a ceiling on how far it will follow. Less than 1 on purpose: matching a jump exactly hides
-- the jump (nothing moves in frame), while ignoring it entirely drops the car off the bottom
-- of the screen. 0.6 lets the car rise in frame and still stay in it.
CameraConfig.JumpFollow = 0.6
CameraConfig.MaxJumpFollowStuds = 25

-- === Under a bridge =========================================================
--[[ The shot ducks when the road goes under something, and rises again once it is clear.

	WHAT IT FIXES IS NOT SUBTLE. City tiles carry bridges 20 to 22 studs over the deck and a tunnel
	roof at 27, and the shot rides at `Height` 22, so without this the camera drives THROUGH a
	bridge: for a few frames the screen is the underside of a concrete slab and the car is not in
	it. Dropping under the roof and giving a little of the down-pitch back turns that into the best
	two seconds of scenery on the map.

	MEASURED, NOT AUTHORED. Nothing here knows which tile it is on or which world is loaded. One ray
	a frame asks the road what is overhead just in front of the car, and every map answers for
	itself: City's bridges at 21.7, its tunnel at 27, Forest Mountains' overpasses at 27,
	FuturisticCity's bridges at 17.6. Nothing is tagged, and a new map needs no wiring.

	The pair that decides what counts as a roof is `RoofMinStuds` and `RoofMaxStuds`, and it is a
	BAND rather than a ceiling. Under the band is everything that stands ON the road, which is not
	cover: the tallest obstacle volume in the game is 8.4, the same number TrafficController and
	GetawayController probe under. Over it are the roofs that pass so high they never crowd the
	shot, and there are real ones to keep out: the arctic and forest tunnels sit at 51 to 65, and
	City 5 has a skybridge at 60. Every figure in this section was measured off the five world
	folders on 2026-09-17, so a map that lands with a lower deck is a reason to measure again. ]]
CameraConfig.Cover = {
	-- Off leaves the shot exactly as it was, bridge or no bridge, which is the honest A/B. This
	-- whole section is also inert while `CameraConfig.LowChase` is on, because the shot is then
	-- already down where the duck would put it.
	Enabled = true,

	-- Studs above the deck while covered, standing in for `Height`. 11 clears the lowest roof in
	-- the game with room to spare, and it is close to the height this camera shipped at before the
	-- high chase, so it reads as a shot the game already knows rather than a stunt.
	Height = 11,

	-- Degrees of down-pitch handed back while covered. Dropping 11 studs without touching the lens
	-- would swing the car up toward the middle of the frame and take the road ahead with it.
	-- NEGATIVE tilts the lens up, so -8 leaves the car a little higher in frame than usual, which
	-- is most of what sells being low, while keeping enough road in shot to drive by.
	ExtraPitchDeg = -8,

	-- Studs kept between the shot and the roof over it, and the floor it will not duck below.
	-- Neither bites on any map today: at `Height` 11 the lowest roof in the game still leaves 6.6
	-- studs over the lens. They are what keeps this honest if a lower one ever arrives.
	Clearance = 4,
	MinHeight = 6,

	-- What counts as a roof, studs above the deck. The header has where the band comes from.
	RoofMinStuds = 12,
	RoofMaxStuds = 40,

	-- How far ahead of the car the probe looks. In SECONDS of driving rather than studs, so the
	-- warning is the same beat at 50 studs/s and at 120, with a floor for the crawl at the start of
	-- a run. 0.7s is comfortably longer than `EnterGain` needs to finish the duck.
	LeadSeconds = 0.7,
	LeadMinStuds = 40,

	-- Studs past the far edge of the last roof that the shot stays down for, ON TOP of `Distance`.
	-- The chase distance is in there because the camera is still under the bridge for that many
	-- studs after the car has come out; this is the margin on top of it, so the rise starts once
	-- the shot is properly in the open rather than the instant it clears the edge.
	TrailStuds = 12,

	-- How fast the duck arrives, and how fast it lets go. Same exponential as the follow gains.
	-- Entering is the one with a deadline, since the bridge is coming whether the shot is ready or
	-- not; leaving has all the time in the world and takes a little of it.
	EnterGain = 5,
	ExitGain = 3.5,
}

-- === Flight (the steal) =====================================================
--[[ What changes while the player is in the air (StealController hands us the flight avatar via
	`setFlight`). Everything not listed here is unchanged, deliberately: the shot stays the same
	shot, framed on a different subject, because a camera that also changes lens mid-bail makes
	the arc impossible to learn.

	THE SUBJECT'S VELOCITY IS HANDED TO US RATHER THAN READ. That isn't a convenience — the flight
	avatar is anchored and CFrame-driven, so nothing it reports is the arc's. And what it reports is
	not zero, which is the trap: anchoring does not clear a velocity and a clone inherits one, so the
	avatar's root hands back whatever the CAR was doing at the instant of the bail and holds that
	figure for the whole flight (both measured). This camera's whole smoothness is built on a follow
	LAG derived from a measured velocity (see `restingLag`), so reading it would pin the shot's lag to
	the speed you bailed at while the arc brakes to a third of it. Third time that pattern has cost
	this codebase something; see the plan's §10.3, and `WindController._velocity` for the same
	mistake made in the other direction. ]]
CameraConfig.Flight = {
	-- Per-second blend for the flight-only distance and pitch. Applied entering and leaving so a
	-- jump or completed steal cannot produce a one-frame camera step.
	BlendResponse = 7,
	-- Air time follows much harder than it does on the road: on the deck a "jump" is suspension
	-- bob and the shot should ignore most of it, but in a bail the height IS the event. Still under
	-- 1 so the player rises in frame rather than being pinned to the middle of it.
	JumpFollow = 0.7,
	-- Ceiling on that, studs. The arc apexes ~21 studs up at the default launch, so this still has
	-- room to spare and only exists to stop a runaway flight dragging the camera into orbit. Worth
	-- re-checking against `StealConfig.Launch.Up` whenever the leap is made bigger: at 0.85 follow
	-- the camera only tracks 85% of the height anyway, so this bites at an apex of about 53 studs.
	MaxFollowStuds = 45,
	-- Extra studs back, so the whole arc and the car you're aiming at fit in one frame.
	ExtraDistance = 5,
	-- Degrees the shot tilts further DOWN while airborne. You're looking at the road you're going
	-- to land on, not the horizon — this is what makes the ground marker readable.
	ExtraPitchDeg = 3,
}

-- === Downed (you missed) ====================================================
--[[ The little cutscene on a whiffed bail: your driver is face down on the tarmac and the camera
	comes in to look at them while the WRECKED banner reads and the screen fades.

	This is the one shot in the game that is ABOUT the player rather than about the road, so it's
	the one place the framing rules above get broken on purpose: close, low, and tilted down hard
	enough that the deck fills the frame. The car isn't in it — StealController deliberately leaves
	it hidden for exactly this beat, so nothing coasts through the shot.

	`Height` is measured from the deck like the others, so ~5 is roughly head height on a standing
	character and reads as crouching over the body rather than standing on it. It still tracks along
	the road, so the body sliding to a stop stays framed, and traffic still streams past behind it —
	which is what stops it reading as a freeze-frame. ]]
CameraConfig.Downed = {
	Distance = 15,
	Height = 5,
	ExtraPitchDeg = 14,

	--[[ Does an ORDINARY WRECK get this shot too? It used to, and the reason it no longer does is
		the sentence three paragraphs up: the car isn't in the whiff's shot.

		In a wreck it very much is. `RaceService._throwRider` tips you out through the windscreen
		with the car's own momentum, so the body and the twenty-stud object that just threw it are
		travelling together and coasting to a stop in the same few studs of road. Pointing a close,
		low, hard-down shot at the body then puts the camera inside the wreck and the ragdoll
		through the bodywork — the visuals are massless and mostly non-colliding, so the body does
		not even land ON the car, it lands IN it.

		Off means a wreck simply holds the road shot it has held all race: the car, framed the way
		it has been framed for the whole run, coasting and smoking under the WRECKED banner. The
		throw is not lost — the body arcs up over the bonnet a few studs in front of a camera that
		is already looking that way, so you watch yourself come out of your own car rather than
		being cut to a close-up of it. Flip this back on to A/B the old cutscene; nothing else
		changes, and the whiffed bail keeps this shot either way (it comes in through `setFlight`,
		not through the attribute). ]]
	FramesThrownRider = false,
}

-- === Speed ==================================================================
--[[ The camera's reaction to going fast: it pulls back and opens up as the car approaches what
	THAT car can do. Together with `WindConfig`'s streaks and `NitroConfig.Fov`, this is the whole
	of how speed is sold.

	=== THIS WAS A FIXED STUD/S NUMBER AND IT WAS PINNED AT MAXIMUM ============================

	It used to be `PullbackSpeed = 75`, described here as sitting "just past boosted cruise (~71),
	so ordinary driving lands well inside the ramp". That 71 came from the same early test car
	`DriveConfig`'s header warns about at length, and it is not what any shipping car does.
	Measured: the tier-1 Civic cruises 71-75, and the tier-4 Charger holds 84-85 and boosts to 115.

	So `alongVel / 75` was clamped to 1 during ORDINARY DRIVING for every car in the game. The
	effect was not subtle-but-present, it was a constant: boosting a Charger moved this camera by
	nothing at all, because it had been sitting at full since the run started. A dial welded to its
	stop reads as no dial.

	=== SO IT IS A FRACTION OF THE CAR'S OWN CEILING ===========================================

	The same answer `WindConfig` already reached for the same reason, and stated the same way:
	"flat out" is a share of what THIS car can do, not a speed. A fixed number cannot work across a
	roster spanning 71 to 115 studs/s — it is either saturated for the fast cars or unreachable for
	the slow ones. A fraction is right for all 65, and it moves with a steal that swaps what you
	are driving.

	`Start` is where the camera begins to react and `Full` is where it is all the way open, both as
	shares of `DriveController:getTopSpeed()` converted to studs (see `WindConfig.StudsPerMaxSpeed`,
	which owns that conversion and how to re-take it).

	0.5 TO 1.0 IS CHOSEN OFF `BoostSpeedScale`. Cruise is top / 1.35 = 0.74 of the ceiling, so this
	band puts ordinary driving just under halfway open and holding accelerate takes it the rest of
	the way. That is the point: the two states have to LOOK different, and under the old constant
	they were the same picture. ]]
CameraConfig.SpeedStartFraction = 0.5
CameraConfig.SpeedFullFraction = 1.0

-- Per-second response shared by speed FOV, pullback and ordinary high-speed vibration. Filtering
-- the one source rather than each output prevents small chassis-speed fluctuations from making
-- three camera effects jitter independently. Roughly 0.17 seconds to close most of a change.
CameraConfig.SpeedResponse = 6

--[[ Extra studs of Distance at full speed. The car getting away from you.

	WAS 3, WHICH AGAINST A `Distance` OF 28 IS A TENTH AND WAS NEVER GOING TO BE SEEN — and, being
	saturated, was in practice a permanent +3 rather than a reaction to anything. ]]
CameraConfig.SpeedPullbackStuds = 8

--[[ Extra degrees of FieldOfView at full speed. Ignored when FieldOfView is nil.

	WAS 3. With a 70 base that made the game's entire FOV range 70-73 plus nitro's 7, and the first
	three of those were always applied — so the usable range a player could ever perceive was the
	nitro button alone. Arcade racers that read as fast swing 15-30 degrees between cruise and
	flat out; this is deliberately at the restrained end of that, because the shot is a chase cam
	on a lane-change game rather than a cockpit.

	The stack at 11: about 73 cruising, 79 boosted, and 94 boosted with the current nitro FOV. The top is
	brief by construction (`NitroConfig.Fov.FallTime`) and is meant to be the loudest moment in a
	run. Lower this first if the wide end reads as fish-eye on a phone. ]]
CameraConfig.SpeedFovDeg = 11

-- Optional camera tuning attributes, written to CurrentCamera at a throttled cadence. Disabled by
-- default and intentionally silent: Studio can watch the values without a render-step print flood.
CameraConfig.Debug = {
	Enabled = false,
	SampleInterval = 0.1,
}

-- A strong, high-frequency vibration while nitro is burning. Translation remains under a quarter
-- stud so the surge feels violent without moving traffic far enough to spoil gap reading.
CameraConfig.NitroShake = {
	Translation = 0.1,
	RotationDeg = 0.16,
	Frequency = 14,
}

--[[ A much quieter road-speed vibration. Wind streaks sell the air moving past the camera; this
	sells the chassis carrying the camera quickly over the road. It begins only near flat-out and
	uses a smooth speed-fraction ramp, so cruise stays clean and traffic never jitters while the
	player is still reading a gap. NitroShake is deliberately several times stronger and faster.

	Translation and rotation are hard visual bounds at FullFraction, not per-axis additions. Keep
	them tiny: this layer should be felt in the lane markings and guardrails, not seen as camera
	shake. Set Enabled false for an exact A/B without changing any movement or FOV tuning. ]]
CameraConfig.SpeedShake = {
	Enabled = true,
	StartFraction = 0.82,
	FullFraction = 1,
	Translation = 0.025,
	RotationDeg = 0.04,
	Frequency = 12,
}

-- === Game feel: hits, passes, lane changes ==================================
--[[ Three small camera reactions, all rotational or FOV, all on springs so they overshoot a hair and
	settle instead of snapping. They sit ON TOP of everything above and never move the follow point,
	so the lag maths in `restingLag` is untouched.

	  • IMPACT — every hit that goes through `ObstacleController.applyImpact` (obstacles, walls, traffic
	    clips) nods the camera down, rolls it toward the side that was hit, and squeezes the FOV, sized
	    by the hit's own `Shake`. Heavy hits (`HitStop.MinShake` and up) also HOLD the shot for a couple
	    of frames and ease back onto the car: the closest a physics car can get to a freeze-frame,
	    because the solver cannot be paused.
	  • PASS — a near miss rolls the camera a touch toward the car you shaved and pops the FOV. Scaled
	    per tier; a thread is the biggest.
	  • LANE — the horizon leans into a lane change in proportion to how fast you are moving sideways.

	`Scale` is the master: 0 turns every one of them off, 0.5 halves them. It is the first thing to
	reach for if anyone reports motion sickness, and the natural hook for a settings toggle later.

	Springs: `Frequency` is the natural frequency in Hz, `Damping` the ratio (1 = no overshoot,
	0.5 = visibly bouncy). Every "peak" below is the actual peak the spring reaches, not an input. ]]
CameraConfig.Juice = {
	Enabled = true,
	Scale = 1,

	Spring = {
		Frequency = 2.2,
		Damping = 0.6,
	},

	Impact = {
		-- Hits below this `Shake` get nothing extra (the translation shake still plays). Scrapes
		-- are ~0.25-0.4, cones and light clips ~0.5-0.8, barriers and heavy clips 1.2-1.6.
		MinShake = 0.3,
		-- The `Shake` at which every peak below is reached in full.
		FullShake = 1.4,
		RollPeakDeg = 3,
		PitchPeakDeg = 2.2, -- nose-down nod
		FovPeakDeg = -4, -- negative squeezes in, which reads as the car being stopped short
	},

	HitStop = {
		Enabled = true,
		MinShake = 0.9,
		-- Seconds the shot is held in place, then seconds it takes to ease back onto the car. Keep the
		-- hold under ~0.06: past that the car visibly slides out of a frozen shot.
		Seconds = 0.045,
		BlendSeconds = 0.09,
	},

	Pass = {
		-- Scale per tier for the peaks below. Trading paint is a contact and is already handled by
		-- the impact path, so it has no entry.
		Near = 0.35,
		Close = 1,
		Thread = 1.4,
		RollPeakDeg = 1.6,
		FovPeakDeg = 2.5,
	},

	Lane = {
		-- Degrees of lean at full sideways speed; positive leans INTO the move, like `RollDeg`.
		RollDeg = 1.5,
		-- Studs/s of sideways speed that counts as "full", matched to the hybrid's effective 41.76
		-- rather than its pre-assist LaneSpeed. This preserves the existing visual roll strength while
		-- movement itself becomes faster.
		FullSpeed = 42,
		-- Per-second ease toward the target lean.
		Gain = 7,
	},
}

return CameraConfig
