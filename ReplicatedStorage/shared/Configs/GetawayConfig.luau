--[[
	GetawayConfig
	-------------
	The transport truck you bank a run into (GDD §3.4, `docs/GetawayTruck_Prep.md`). Some seconds
	after a steal a box truck rolls onto the road ahead of you, drops its rear ramp, and driving up
	into its bay ENDS THE RUN SUCCESSFULLY — you leave with the car you stole instead of wrecking it.

	Four things to know before editing:

	1. THE TRUCK ROLLS; IT IS NOT PARKED. That was a design call, and it is load-bearing rather than
	   flavour. The ramp the modeller shipped sits at 26.7 degrees, which a car meeting at 52 studs/s
	   uses as a jump — but the number that matters at the ramp foot is the CLOSING speed, not the
	   road speed. A truck holding `Speed` = 30 turns a 52-studs/s cruise into a 22-studs/s climb and
	   a 71-studs/s boost into 41, so the approach is a drive-in that you can still overcook. It also
	   makes catching the truck a chase, which is the beat the brief asked for. Lengthening the ramp
	   (prep doc §5.2) remains open and would make this dial less delicate — it does not replace it.
	   That edit is now the modeller's alone: the deploy angle is derived from the plate's own length
	   rather than configured, so a longer plate simply lands shallower (see `Fallback`).

	2. THE TRUCK IS CLIENT-SIDED, like the road, the obstacles and the traffic, and for the same
	   reason: driving is solo, so every driver owns their own copy of the world and none of it
	   replicates. `GetawayService` only PUBLISHES the model and ratifies the bank. What that costs
	   in trust is documented in that service's header — it is the same accepted gap the steal has.

	3. IT KEEPS ITS POSITION IN THE ROAD FRAME, exactly like a traffic car (see TrafficController's
	   header): an `along` coordinate advanced by `Speed * dt`, and a fixed `Lane` across. It is NOT
	   parented to a road tile, because it drives off the tile it spawned on, and it rides
	   `RoadController:onWorldShift` through a rebase.

	4. NOTHING HERE IS WELDED. Every part of the truck is anchored and jointless (prep doc §4), so
	   the doors and ramp are POSED by CFrame about their hinge attachments rather than swung by
	   constraints — the same technique `Modules/CarDoors` uses on the car. That is why the angles
	   below are read off the model's own attributes: the model is the contract, and this file only
	   supplies fallbacks for a truck that arrives without one.
]]

local GetawayConfig = {}

-- Master switch. Off = no truck ever spawns; a run ends only by wrecking, exactly as before.
-- Off while the collector banks every steal on landing (`CollectorConfig.RoadSteal`): a truck would
-- bank the same car twice and is a step the owner asked to drop ("it's yours instantly, keep driving").
local Collector = require(script.Parent.CollectorConfig)
GetawayConfig.Enabled = not (Collector.Enabled and Collector.RoadSteal)

-- === Names ==================================================================

-- The authored model in Workspace, as the modeller ships it. GetawayService publishes a clone and
-- stashes this one out of Workspace at runtime, so nothing truck-shaped replicates or sits on the
-- server. Same treatment RoadService gives the authored road.
GetawayConfig.SourceName = "Truck"

-- ReplicatedStorage child the publish lands in. Clients clone from here.
GetawayConfig.TemplateName = "GetawayTruck"

-- ServerStorage folder the authored model is parked in for the session. Non-destructive: an edit
-- session reverts on stop, so the truck stays where the modeller left it in the place file.
GetawayConfig.StashName = "StashedProps"

-- Client-only Workspace folder the live truck lives in. Deliberately NOT inside a road tile, for
-- the reason in note 3 above.
GetawayConfig.FolderName = "GetawayTruck"

-- === Part names inside the model ============================================
-- The contract `docs/GetawayTruck_Prep.md` §3 describes. Renaming a part in Studio without changing
-- it here is the one way to break this layer silently, so they are named rather than searched for.
GetawayConfig.Parts = {
	Ramp = "Ramp",
	Doors = "Doors", -- folder
	DoorL = "DoorL",
	DoorR = "DoorR",
	DoorHandle = "DoorHandle", -- straddles the seam, so it rides DoorL; see prep doc §5.1
	LoadZone = "LoadZone", -- the bay interior as one volume; what "the car is inside" is measured against
	HingeName = "Hinge", -- the Attachment on Ramp / DoorL / DoorR whose PrimaryAxis is the rotation axis
}

-- === Speed / placement ======================================================

--[[ How fast the truck holds, absolute studs/s — the same units every speed in TrafficConfig and
	DriveConfig is in. 30 sits at the top of the Tier 1 traffic band (24-30), so the truck reads as
	road furniture rather than as a set piece, while still being catchable. Raise it and the chase
	gets longer AND the ramp gets gentler; drop it toward 0 and you approach a parked truck at full
	cruise, which the ramp cannot absorb (note 1).

	THE CLOSING SPEEDS THIS PARAGRAPH USED TO QUOTE WERE WRONG and are corrected here because two
	other blocks in this file were sized off them. It said "a cruise closes at 22 studs/s and a boost
	at 41", from the same early test car `DriveConfig`'s header warns about at length. Measured cars
	against this 30 stud/s truck actually close at:

	    Civic (tier 1)   cruise 71-75  ->  41-45 studs/s
	    Charger (tier 4) cruise 84-85  ->  54-55 studs/s
	    Charger boosting        ~115   ->  ~85 studs/s, and more again on nitro

	So every approach is roughly TWICE as quick as this file assumed. `Open.Range` and the mechanism
	times below have both been re-sized for it; `Spawn.AheadMin`/`AheadMax`'s own note still quotes
	the old figure for the chase length, and that band is really 5-11 seconds rather than 14-21. ]]
GetawayConfig.Speed = 30

--[[ Which lane the truck rolls in, as a cross-axis offset from the road's drive centre — the same
	axis and origin `ObstacleConfig.Lanes` uses ({ -30, -15, 0, 15, 30 }).

	Centre, on purpose: the truck is the exit, and an exit you have to spot on the shoulder is an
	exit most players miss. It costs the two adjacent lanes their comfort — the truck measures 17.8
	studs across INCLUDING its mirrors, so a car in lane +/-15 clears them by 1.39 studs (prep doc
	§6.3) — which is a squeeze the traffic layer is told about rather than left to discover: see
	`TrafficConfig.AvoidTruck`. ]]
GetawayConfig.Lane = 0

-- === When a truck shows up ==================================================

GetawayConfig.Spawn = {
	--[[ Only after a steal. This is the brief's own framing — the truck is how you LEAVE WITH the
		car you took — and it also keeps a run from being bankable before it has earned anything.

		Turn it off to arm the truck at race start instead, which is what you want when you are
		testing the truck itself and don't feel like stealing a car first. ]]
	RequireSteal = true,

	--[[ Seconds after the arming steal before the truck appears. THE MAIN DIAL ON RUN LENGTH: the
		GDD targets 60-120s, and every run now ends either in a wreck or here, so a player who takes
		the first truck they see finishes a run in roughly (time to first steal) + this + the chase.
		Tune it against that target, never on its own. ]]
	Delay = { 10, 16 },

	-- Same, after a truck was missed and despawned behind you. Longer, so blowing past one is a
	-- real cost rather than a free retry three seconds later.
	RetryDelay = { 14, 22 },

	--[[ Studs ahead of the driver the truck appears. Far enough that it is never seen popping in
		(traffic spawns from 260), near enough that the chase is a beat and not a commute: at a
		cruise's 22 studs/s of closing speed this band is 14-21 seconds, and about half that if you
		hold boost the whole way. ]]
	AheadMin = 300,
	AheadMax = 460,
	ApproachSeconds = { 5, 6.5 },
	AheadCap = 1400,

	--[[ How many placements to try before giving up for this tick. A spot is rejected when the
		obstacle course is standing in it — a truck materialising inside a concrete barrier is the
		most visible failure this layer has, and it costs one box query to avoid. ]]
	Tries = 6,

	-- Studs of clear road the check demands IN FRONT of the truck, on top of the truck's own 54.4.
	-- The approach has to be clear too, or the truck lands legally on the far side of a gate you
	-- then cannot get through.
	ClearAhead = 160,
}

-- Studs behind the driver at which a missed truck is taken away. It is slower than you, so this
-- only ever happens by driving past it — which is a choice, and the truck leaving afterwards is
-- what makes it one.
GetawayConfig.DespawnBehind = 280

-- === The mechanism ==========================================================

GetawayConfig.Open = {
	--[[ Studs behind the truck at which it starts opening up. Comfortably further than the truck is
		ever first seen from, so the doors are already swinging when it comes into view — a truck
		that opens on your approach reads as a rendezvous, one that opens in your face reads as a
		trap.

		DERIVED FROM THE SPAWN DISTANCE RATHER THAN WRITTEN DOWN, because as a written number it
		contradicted the paragraph above it. It was 340 against a `Spawn.AheadMax` of 460: a truck
		that rolled the far end of its spawn band appeared 120 studs OUTSIDE its own opening range
		and sat there shut until you had closed that gap. The sentence above describes what this is
		for; +20 past the furthest a truck can ever appear is what actually delivers it, and it
		cannot fall out of step with the spawn band again.

		WHY IT MATTERED, and it is not just presentation. The deploy is ~1.7s of mechanism (the four
		times below) and the approach is the only thing paying for it. Closing speeds are far higher
		than the note on `GetawayConfig.Speed` assumes — that says "a cruise closes at 22 studs/s and
		a boost at 41", which is the same stale test-car figure `DriveConfig`'s header warns about.
		Measured cars against a 30 stud/s truck actually close at 41-45 (Civic cruise), 55 (Charger
		cruise) and ~85 boosting, faster again on nitro. At the bad end that is a truck reached in
		about two and a half seconds — and a spawn rolling anywhere in 300-340 used to be already
		inside the old range, so the mechanism started late AND had the least time to finish.

		The result was arriving at a ramp that was still coming down. Opening at spawn means the
		full spawn distance is available to the mechanism however fast the car is. ]]
	Range = 480,

	--[[ Seconds the doors take to open. Snappier than the ramp on purpose: they are light powered
		panels, and the ramp is the part you have to trust with the car.

		THE THREE MECHANISM TIMES WERE CUT ~25% (1.15/1.15/0.7 -> 0.9/0.85/0.55) because the whole
		sequence has to finish inside the approach, and the approach is twice as quick as this file
		assumed (see `GetawayConfig.Speed`). Sequenced by `RampAfterDoors`, the deploy now runs
		0.9 * 0.35 = 0.32s to the ramp's cue, + 0.85 slide, + 0.55 tilt = ~1.7s, down from ~2.25s.

		Against the worst realistic case — a nitro run reaching a truck that rolled `Spawn.AheadMin`
		— that is the difference between the ramp landing under the car and landing before it. The
		cut is deliberately modest: these times are also the ramp's WEIGHT, and a quarter-tonne steel
		plate that snaps out reads as cardboard. It still ran late, and the answer turned out to be
		neither of these nor more distance: `Deadline` below hurries the deploy only when a car is
		actually arriving too fast for it, so these stay the pace of every ordinary approach. ]]
	DoorTime = 0.9,

	--[[ THE RAMP IS A SLIDE-OUT, AND ITS TWO LEGS RUN IN ORDER: the plate slides straight back out
		of the bay, still flat, and only once it is clear of the sill does it tilt down onto the
		road. Shut, the same two run in reverse — up first, then in.

		It used to be one move: a 207-degree flip up through the doorway and over the rear sill. That
		lands in the same place (it has to — the deployed pose is measured, prep doc §6.4) but it
		reads as a hatch being thrown rather than as a ramp being deployed, and it spends its middle
		third standing vertically in the doorway, sweeping through both door leaves on the way.

		Sliding is what the real thing does, and it is cheaper geometry: the plate stays flat and
		below the header for the whole extension, so there is nothing for it to pass through, and the
		tilt is a 27-degree hinge behind an already-clear truck.

		The slide is the longer of the two: it is 14.8 studs of plate coming out on its rails, where
		the tilt is a short drop that the landing rebound (`Settle`) then punctuates. ]]
	RampSlideTime = 0.85,
	RampTiltTime = 0.55,

	--[[ How far the doors have to be open before the ramp starts SLIDING out, 0..1. Sequenced
		rather than simultaneous because the plate leaves through the doorway: at 0.35 raw the
		Quad/Out curve already has the leaves at 156 degrees — past straight-out-the-back and heading
		flat along the sides — so they are outboard of the 15.5-stud plate before it moves.

		Reversed on the way shut, where it gates the DOORS on the ramp being back in: the leaves
		sweep back through the plate's lane below 156 degrees, so they wait for it. ]]
	RampAfterDoors = 0.35,

	--[[ === THE RAMP HAS A DEADLINE NOW — 2026-09-28 ===========================================

		WHAT IT WAS. The deploy ran at the fixed pace above, and everything upstream of it was tuned
		to buy it enough approach: the times cut 25%, then `Range` pushed out to open at spawn. Both
		notes say "if it still runs late, push further out". It still ran late — a fast car on boost
		or nitro closes the 300-stud minimum spawn gap in under the 1.7s the deploy takes, and drove
		into a ramp that was still tilting down, which is a slope moving INTO the car and throws it.

		WHAT IT IS. The truck measures, every frame, how long until the car's nose reaches the foot of
		the ramp (gap / closing speed), and if the rest of the deploy at its authored pace would not be
		done `Margin` seconds before that, it runs the mechanism faster by exactly enough to be. At a
		cruise nothing changes — the approach is several seconds and the rate stays 1. A car arriving
		hot gets a ramp that snaps down in time, which reads as the crew seeing you coming.

		WHY THIS AND NOT MORE DISTANCE. Any fixed spawn gap loses to a fast enough car, and the roster
		gets faster every world; each push-out also makes the chase longer for the slow cars that
		were never the problem. A deadline is right at every speed by construction.

		`Enabled = false` restores the fixed-pace deploy, exactly. ]]
	Deadline = {
		Enabled = true,
		--- Seconds before the nose reaches the ramp foot that the tilt must already be down. Covers
		--- the landing rebound (`Settle.Time`) plus a frame or two of slop in the ETA.
		Margin = 0.35,
		--- Studs from the car's tracked position to its nose. The ETA is to the NOSE, and the along
		--- coordinate is the chassis centre; half of a long body, rounded up. A guess that errs early.
		NoseStuds = 10,
		--[[ The fastest the mechanism may run, as a multiple of the authored pace. At 8 the whole
			1.7s deploy takes ~0.21s — a pop rather than a motion, which is the last resort for a car
			that is practically already on the ramp. It exists so a car sitting ON the foot (ETA ~0)
			cannot ask for an infinite rate and finish the deploy in zero frames. ]]
		MaxRate = 8,
	},

	--[[ Easing for the DOORS. Quad/Out leaves smartly and settles rather than arriving at its stop
		at full speed, which is what a light powered door actually does. ]]
	Style = Enum.EasingStyle.Quad,
	Direction = Enum.EasingDirection.Out,

	--[[ Easing for BOTH ramp legs, which is deliberately not the doors'.

		Quad/Out is wrong for this part twice over. It leaves at full speed, and a quarter-tonne
		steel plate does not — it is heaved out of the bay. And because the same curve is replayed
		backwards on the way shut, "leaves fast, settles slow" becomes "creeps, then whips home",
		which is the flick the ramp used to end its close with.

		Sine/InOut is symmetric, so each leg eases off its stop and onto it in BOTH directions, and
		its fastest moment is its middle. It is also what makes the handoff between the two legs
		invisible: the slide arrives at zero speed and the tilt leaves at zero speed, so the plate
		does not stop and restart where they meet — it rolls from one into the other. ]]
	RampStyle = Enum.EasingStyle.Sine,
	RampDirection = Enum.EasingDirection.InOut,

	--[[ The ramp landing. A damped rebound of a couple of degrees the moment the ramp reaches the
		road, so it arrives with some weight instead of stopping dead in mid-air. Small on purpose:
		this is a loading ramp settling on its stop, not a diving board.

		`Cycles` counts BOUNCES, not wavelengths — the curve is rectified so every hump lifts the
		tip off the road and drops it back, never the reverse (see `_rampSettle`). Two, because the
		squared decay makes the second a third of the first, which is where it stops reading as a
		wobble and starts reading as weight. ]]
	Settle = {
		AngleDeg = 1.7,
		Time = 0.34,
		Cycles = 2,
	},
}

--[[ Fallback angles, degrees, for a truck that arrives without the attributes `GetawayTruck_Prep.md`
	§2 stamps on it. The model is the contract; these exist so a re-import that lost its attributes
	degrades to something posable instead of to a truck that never opens.

	The doors' 270 lays each leaf flat along the side of the box, as in the reference image; 90 would
	leave them straight out the back.

	THE RAMP ANGLE IS NOT READ FROM THE MODEL ANY MORE — the controller derives it, because once the
	ramp slides out flat the angle stops being a taste call and becomes arithmetic: the plate pivots
	on its own inboard end at the sill, so the only tilt that puts its tip on the road is
	`asin(hinge height / plate length)`. On today's truck that is 26.681 degrees, which is what
	`RampDeployAngleDeg` stamps — so the attribute is now a CROSS-CHECK (the controller warns if the
	two disagree) rather than an input. Lengthening the plate to soften the climb (prep doc §5.2) is
	therefore a model-only edit: the gentler angle follows from the geometry with nothing to update
	here. This fallback is only reached by a plate too short to reach the road at all. ]]
GetawayConfig.Fallback = {
	RampDeployAngleDeg = 26.68,
	DoorOpenAngleDeg = 270,
}

-- === Banking ================================================================

--[[ === ASSISTED RAMP ENTRY — 2026-10-04 ======================================

	The physical climb fought DriveController's world-level upright assist on a 26.7-degree
	ramp which is itself moved by CFrame. Boarding now takes the car only when its nose crosses
	the deployed ramp's foot from behind, then carries it up in the truck's frame. The bay test
	still owns the reward. Enabled = false restores the physical climb and ordinary bay docking.

	These are initial tuning choices, not measured tolerances. Keep the capture band narrow:
	widening it should never turn a pass alongside the truck into a successful boarding. ]]
GetawayConfig.Boarding = {
	Enabled = true,
	-- Shared with StealController._canBail: an anchored boarding car must not start a flight.
	Attribute = "GetawayBoarding",
	SideMargin = 0.35, -- clearance for the whole projected hull on BOTH ramp and doorway
	MaxYawDeg = 25, -- permits an imperfect approach without capturing a sideways collision
	MaxTiltDeg = 35, -- accepts the ramp's incline, rejects a rolling or inverted car
	MinClosingSpeed = 1, -- studs/s relative to the truck; falling behind is not entering
	MaxEntryGap = 0.75, -- catches a nose already touching the foot when the first sample arrives
	MinBottomHeight = -1, -- suspension compression may put the hull slightly below the road
	MaxBottomHeight = 3, -- excludes a car flying over the ramp instead of driving onto it
	MinSpeed = 12, -- avoids a walking-speed capture taking several seconds to climb
	MaxSpeed = 65, -- bounds a nitro arrival so the assisted climb remains visible
	WheelbaseFraction = 0.7, -- estimated axle spacing as a share of hull length, across the roster
	BlendDistance = 5, -- studs over which the measured entry pose settles onto the ramp profile
}

GetawayConfig.Bank = {
	--[[ Studs past the rear sill the car's hull CENTRE must reach before the run banks. The bay is
		41 studs deep and a car is 19.9 long, so 6 puts the nose about 16 studs in — unambiguously
		aboard, and still less than half the bay, so the bank fires while you are driving in rather
		than when you hit the bulkhead.

		Measured against the hull centre and not against an overlap query on purpose: `LoadZone` is
		published query-blind (see GetawayService) precisely so the stock CarBones suspension rays,
		which run as "Default" and are not ours to filter, can't try to drive up it. A point-in-box
		test needs no query at all and cannot be fooled by a collision group. ]]
	Depth = 6,

	-- Studs the bay volume is shrunk by on the other four faces before the test, so a car scraping
	-- along a wall or riding high over the ramp lip doesn't bank on a technicality.
	Margin = 1,

	--[[ THE BERTH. `Depth` fires the bank while the car is still HALF OUT — measured on the real
		model, the hull centre reaches 6 studs in with 4.29 studs of tail still past the rear sill —
		and that is the right trigger but the wrong place to stop. Freezing the car there shuts the
		doors through its own boot lid.

		So the bank no longer freezes the car where it fired; it slides it the rest of the way into a
		berth and squares it up, and the doors wait for that. `DockClearance` is the gap left between
		the tail and the sill once berthed: 1.5 studs reads as parked rather than as wedged, and the
		bay is 41 studs deep against a 20.6-stud car, so the nose still stops 19 studs short of the
		bulkhead. There is no risk of pushing through it — the berth is clamped off both faces.

		THE SLIDE IS SPEED-MATCHED, not timed, which is what makes the freeze invisible. A Quad/Out
		tween leaves at `2 * distance / time`, so the controller solves that for the time that starts
		the slide at exactly the closing speed the driver actually arrived with and decays it to a
		stop. Drive in off a cruise and the car simply coasts to a halt; the moment control is taken
		away is not a moment you can see. The clamp is there for the two ends the maths doesn't cover
		— crawling in at walking pace, or landing the boosted 41-studs/s version off the ramp. ]]
	DockClearance = 1.5,
	DockTimeMin = 0.3,
	DockTimeMax = 0.9,

	--[[ How far into the berth the mechanism waits before starting to shut, 0..1. Not 1: the ramp
		takes half a second to come off the deck and the tail is inside well before the car finishes
		settling, so overlapping them keeps the getaway quick without the ramp ever sweeping through
		the car. Raise it toward 1 if a body longer than the pack's ever gets in. ]]
	CloseAfterDock = 0.7,

	--[[ Seconds each leg takes to shut behind you. Faster than they opened: this one is a getaway.
		The ramp's two legs run in reverse order — the plate lifts off the road first, then retracts
		into the bay, and only then do the doors follow it in (`Open.RampAfterDoors`).

		Split per leg rather than one number for the ramp, because they are different motions: 27
		degrees of lift is a much smaller job than 14.8 studs of retraction, and one shared budget is
		what used to whip the shorter of the two home.

		These set the whole close beat at `RampTiltCloseTime + 0.65 * RampSlideCloseTime +
		DoorCloseTime` = 1.54s, which `RaceConfig.BankHoldTime` has to cover on top of the berth. ]]
	RampTiltCloseTime = 0.4,
	RampSlideCloseTime = 0.55,
	DoorCloseTime = 0.75,
}

-- === The screen =============================================================

--[[ WHAT THE PLAYER IS TOLD ABOUT THE TRUCK, which until now was nothing at all unless they were
	on the tutorial's BANK beat.

	That was the gap. Everything above this line is a well-tuned beat that the player has no way to
	read: a truck is armed on a steal, it arrives somewhere in a ten-to-sixteen second band, and it
	turns up three hundred studs out in the middle lane where it is a white smudge among white
	traffic. A first-timer gets a chip over it (`TutorialConfig`'s BANK beat, and the note there
	says exactly why); everybody else gets a run that ends in a wreck because they never learned
	there was another way for it to end.

	SO THERE ARE TWO PIECES AND THEY HAND OFF TO EACH OTHER. `Card` is a countdown on the right of
	the driving screen that answers "how long do I have to survive"; `Marker` is a glyph over the
	truck itself that answers "which of those is it". The card goes away as the marker arrives, so
	only ever one of them is on screen — see `GetawayHudController`.

	BOTH ARE DELIBERATELY QUIET. The near-miss toast's note makes the argument in full and it applies
	here twice over: this is a driving screen, the player is threading traffic at eighty-five studs a
	second, and the two things already drawn on it (the gauge cluster, the nitro bar) are both
	readouts you glance at rather than look at. Nothing here pops, flashes or grows except the one
	beat where the truck actually arrives, which is the one moment that has earned it. ]]
GetawayConfig.Hud = {
	--- Off = neither the card nor the marker is ever built, and the truck goes back to being
	--- something you find out about by driving into it. The tutorial's own chip is unaffected;
	--- it is TutorialController's and predates this.
	Enabled = true,

	--[[ THE COUNTDOWN CARD -------------------------------------------------------------------

		Right edge, mid-height. Every other band of this screen is taken: the gauge cluster owns the
		bottom, the near-miss toast the upper middle (0.235), the tutorial's objective card the top
		right (0.1 to 0.225), and the car's HP moved onto the car itself. This is the one band on
		the right that nothing else reaches, and it clears the tutorial card by a tenth of a screen
		— which matters, because the run where a player most needs this is the run where that card
		is also up. ]]
	Card = {
		--- Anchored to its RIGHT edge, so the margin from the screen edge is the margin whatever the
		--- viewport is. The 0.017 is the tutorial card's own `EDGE_MARGIN`, so the two line up.
		Margin = 0.017,
		CentreY = 0.4,
		--- Scale on both axes, the way the near-miss toast is sized. The card's aspect therefore
		--- moves a little with the viewport, which is tolerable for a bar and a word and is not for
		--- the truck glyph — that carries its own `UIAspectRatioConstraint`.
		Size = Vector2.new(0.185, 0.1),

		--[[ A PANEL, WHICH THE NEAR-MISS TOAST DELIBERATELY DOES NOT HAVE — and the difference is
			where the two things sit. That toast lands in the middle of the screen at the moment the
			player is reading the road through it, so anything opaque behind it is something in the
			way. This is at the extreme right edge, over sky and verge, where there is nothing behind
			it to see. A bar needs a seat to read against, and at 0.45 the road still shows through. ]]
		PanelColor = Color3.fromRGB(20, 27, 45),
		PanelTransparency = 0.45,
		--- The kit's own navy border, at the weight the driving HUD's other bars wear it.
		StrokeColor = Color3.fromRGB(12, 18, 34),
		StrokeThickness = 2,
		--- Corner radius as a fraction of the card's own HEIGHT, so it is the same curve on a phone
		--- and on a monitor rather than the same pixel count.
		CornerRadius = 0.22,

		Title = "GETAWAY",
		TitleColor = Color3.fromRGB(238, 242, 255),
		--- `%d` is whole seconds remaining. Rounded UP, so the last second reads "1s" for a whole
		--- second and the card never shows a zero it then sits on — see `_stepCard`.
		SecondsFormat = "%ds",
		SecondsColor = Color3.fromRGB(158, 176, 204),

		--[[ THE BAR IS A PILL WITH A STROKE AND NO TRACK ART, which is the settled house style for
			bars on this screen rather than a shortcut: `NitroConfig.Hud.Track` is off for the reason
			it spells out (the framed art leaves a gap that reads as slop at this size), and the car's
			own HP bar is built the same way. Three bars on one screen, one construction.

			`UIAssets.Bar.Track` / `Bar.FillBlue` are therefore deliberately NOT used here. They are
			panel-scale art for the Index and Quest screens and they carry 9-slice insets this bar
			has no use for — and a fill that travels from full width to nothing is precisely the case
			where a slice inflates its own corners. ]]
		BarHeight = 0.19, -- of the card
		--[[ Amber, and not the nitro bar's blue. The two are on screen together and they mean
			opposite things — one is a resource you spend, the other is a clock you cannot affect —
			so they may not be the same colour. This is the kit's PLAY gold (#FFC600), which in this
			palette is what "the thing you are trying to get to" is painted. ]]
		FillColor = Color3.fromRGB(255, 198, 0),
		--- The trough is the fill's own colour dimmed, so the two can never disagree about hue.
		--- Same trick and same number as the nitro bar's `TrackDim`.
		TrackDim = 0.28,

		--- Seconds the card takes to arrive and to leave. The arrival is quick because it is news;
		--- the exit is slower because it is a handoff to the marker rather than an event.
		FadeIn = 0.25,
		FadeOut = 0.45,

		--[[ THE ARRIVAL BEAT — the one moment either of these two pieces is allowed to be loud, and
			it is still only a fifth of a second of it. The bar reaches full, the whole card springs
			this far past its own size and settles back, and then it leaves.

			`PopFrom` is a UIScale rather than a Size for the near-miss toast's reason: the labels
			are `TextScaled`, so animating the box animates the font and the text re-flows mid-pop. ]]
		PopTo = 1.06,
		PopTime = 0.16,
		--- ...and how long the full bar is left standing before the card fades, so the completion is
		--- something the player sees rather than something that happens behind the fade.
		HoldFull = 0.5,
	},

	--[[ THE MARKER OVER THE TRUCK -------------------------------------------------------------

		A billboard rather than a projected screen icon, for the three reasons TutorialController's
		chip gives: a screen icon at a world target has to be projected, clamped to the viewport when
		the target is behind you, and re-aimed every frame the camera moves. A billboard has none of
		those problems, and `AlwaysOnTop` buys back the one thing it costs. ]]
	Marker = {
		--- Pixels at `RefStuds`, shrinking with distance between the two clamps below. The box holds
		--- the glyph's 1.869 aspect plus a line of distance text under it.
		Size = Vector2.new(132, 104),
		--[[ How the shrink works, and the reasoning is the chip's `CHIP_REF_STUDS`: offset alone is a
			constant pixel size at every range, which is right for a thing you walk up to and absurd
			for a truck three hundred studs out; scale alone is honest and unreadable. So it is full
			size at `RefStuds` and smaller as the truck pulls away, floored at `MinScale` because
			below about that the distance line stops being a number.

			THE REFERENCE IS NOT THE CHIP'S 80, and copying it was a bug worth recording. This marker
			is only ever ON SCREEN between about 150 studs (where `FadeNear` has dissolved it) and
			460 (`Spawn.AheadMax`, the furthest a truck ever appears). At a reference of 90 the ratio
			`90 / away` is 0.6 at the very closest of those and below the floor everywhere else — so
			the marker sat pinned at `MinScale` for its entire life and the shrink, which is the
			whole reason it is sized in offset, did nothing at all.

			The reference has to sit inside the visible band for the ramp to exist. At 200 the marker
			appears at 0.55-0.67 when the truck is first spotted, grows through 0.8 at 250, and
			reaches full size around the point it begins to fade — so it swells as the player closes
			and then dissolves into the truck it was pointing at, which is the arc this wants. ]]
		RefStuds = 200,
		MinScale = 0.55,

		--- Studs of clear air between the top of the truck's bounding box and the bottom of the
		--- marker. The chip uses 4 for the same job.
		Clear = 4,
		--[[ The tangent of the angle above the eye the marker may sit at. Same value, same reason,
			as the chip's `CHIP_RISE`: the race camera is pitched 17 degrees down under a 70-degree
			field, so there is about 18 degrees of headroom above horizontal and not the 35 a level
			camera would give. Left unclamped the marker climbs off the top of the screen over the
			last seconds of the chase, which is exactly when the player is lining up on the ramp. ]]
		Rise = 0.14,

		--[[ HOW SUBTLE IT ACTUALLY IS. The glyph never goes fully opaque: this is a hint about
			something already in front of you, not a waypoint you are following, and the truck is the
			biggest thing on the road by the time it matters. ]]
		IconTransparency = 0.25,
		TextTransparency = 0.4,

		--[[ ...AND IT GETS OUT OF THE WAY. Full strength beyond `FadeFar`, gone entirely by
			`FadeNear`, linearly between.

			This is the whole difference between this and the tutorial's chip, which stays up for the
			entire chase because a first-timer needs it to. Past a hundred studs the truck fills a
			third of the windscreen and is unmistakable; a marker still hanging over it then is
			drawing over the ramp the player is trying to line up on. So it hands over to the truck
			itself, and the last thing it does is get out of the way of the thing it was pointing at. ]]
		FadeFar = 150,
		FadeNear = 90,

		--- Seconds to fade up when a truck appears. Not zero: a glyph that pops into existence reads
		--- as a notification, and this is meant to read as something you noticed.
		FadeIn = 0.35,

		--- The bob, in studs and seconds. The chip's own numbers — a marker that sat dead still over
		--- a moving truck would read as a texture on it rather than as something floating above it.
		BobStuds = 0.5,
		BobPeriod = 2.4,

		--- `%d` is whole studs to the truck, measured from the player's own root — the same line the
		--- tutorial chip prints, in the same words, so the two never quote the same gap differently.
		DistanceFormat = "%d studs",
		DistanceColor = Color3.fromRGB(238, 242, 255),
		--[[ The distance line is the one thing here that wants an outline: the glyph is a solid
			shape with its own dark edge and its own halo baked in, and this is bare text hanging in
			the world — over a WHITE truck, for the whole chase. Thin on purpose, and `Contextual`,
			so it edges the glyphs where they meet a pale background without thickening them.
			Quoted at the full marker size and scaled down with it, exactly as `CHIP_STROKE` is. ]]
		StrokeThickness = 1.5,
		StrokeColor = Color3.fromRGB(6, 8, 12),
	},
}

--[[ === THE EXIT SHOT (2026-10-01) =========================================================

	Dylan: while the getaway's end panel is up, the camera should follow the truck as it drives off,
	so the moment reads as getting away rather than as a screen. `GetawayController._exitShot` hands
	this to `RaceCameraController.setCinematic` when the panel opens (`RaceEndPanel`), and the race's
	own teardown clears it, so it runs on through the fade home.

	THE CAMERA TRAVELS WITH THE TRUCK, so the road streams past and the truck holds its place. Over
	`Sweep` seconds it swings from `From`, behind the tailgate where the chase camera already was,
	round the truck's side to `To`, out ahead of it on the shoulder. `Angle` is degrees round from
	dead behind, `Distance` studs out from the truck's centre, `Up` studs above its deck.

	IT ENDS ON A CLOSE HERO SHOT OF THE CAB (Dylan, third pass): a camera car running just ahead of
	the truck and off its shoulder at windscreen height, 17 studs past the nose, so the cab fills the left third of the
	screen top to bottom (about 70% of its height) and the trailer runs away behind it toward the
	middle. Traffic it rams flies off the nose right past the lens.

	THE TWO PASSES BEFORE THIS put a small truck 90 studs away in the left strip, beside the panel
	(which covers about the middle 30-70% of the screen), and it read as odd: a little truck parked at
	the edge of the frame while everything else happened behind the panel. Measured, their lenses
	were both already within a few degrees of square to the road, so the aim was never the problem;
	the size was. A subject that fills its third of the frame is ordinary composition. These numbers
	came from a projection fitted to measured corners and searched over 16:9, 2:1 and a 2.17 phone:
	the cab stays inside the left 28% at all three, with the near corner just cropped by the frame
	edge on 16:9.

	THE LENS TURNS OVER THE SWEEP, measured from the cab. It starts aimed at it (`LookAhead`,
	`LookUp`) and turns away from it until it ends `LensYaw` degrees toward the truck from square to
	the road. The turn is a fixed angle off the cab rather than a blend toward the road axis, because
	mid-orbit the road axis points away from the truck and a blend toward it lost the truck from
	the frame for a second.

	THE CAMERA TRACKS THE TRUCK'S NOSE ACROSS THE ROAD with `CrossGain` (per second), stiffly,
	because this close every stud of trail is ~4% of the screen. The nose and not the centre: a
	swerving truck is yawed, and its front swings several studs wide of its centre. So a lane change reads the way it does from a
	camera car: the truck turns and leans, and the road and traffic swing past behind it. `LookGain` is
	the same follow for the cab point the lens is measured from. `Up` is above a car's roof, so traffic
	in the camera's lane passes under the lens rather than through it.

	`MaxCross` keeps the camera over the road (the barriers stand at about +/-44), and the weave only
	picks lanes the camera can follow to without crossing it: with the camera 26 studs to the side
	that is the centre and the two lanes beyond it. ]]
GetawayConfig.ExitShot = {
	BlendIn = 0.9, -- seconds from the chase camera into the shot
	Sweep = 3.4,
	From = { Angle = 0, Distance = 60, Up = 20 },
	-- 44 studs up the road from the truck's centre and 26 across: cos/sin of these.
	To = { Angle = 149.4, Distance = 51.1, Up = 11 },
	LookUp = 11, -- the cab point the lens is measured from: above the truck's deck position...
	LookAhead = 17, -- ...and this far up the road from its centre (the nose is +27)
	LensYaw = 11, -- degrees toward the truck from square to the road that the lens ends at
	CrossGain = 10,
	LookGain = 12,
	MaxCross = 38, -- studs either side of the drive centre the camera may stand: the outer lanes are 30
	Fov = 70,
}

--[[ ...and THE TRUCK MAKES A RUN FOR IT behind the panel (Dylan, 2026-10-01): it puts its foot down
	and goes straight through the traffic, the way a getaway truck would. Over `Accel` seconds from the
	panel opening it climbs from `GetawayConfig.Speed` to `Speed`, it stops being something traffic
	swerves round (`TrafficController.setAvoid`), and any car its box reaches is rammed out of the way
	(`TrafficController.ram`): thrown ahead of it at `Ram.Ahead` studs/s faster than the truck, off to
	whichever side of the truck's nose it was on at `Ram.Side`, and up at `Ram.Lift`. The truck itself
	never slows and takes nothing; it has no health to take. `Reach` is how far past its own nose a
	car counts as hit, in studs, so the shove lands as the bumpers meet rather than a frame after. ]]
GetawayConfig.Exit = {
	Speed = 95,
	Accel = 2.5,
	Reach = 4,
	Ram = { Ahead = 30, Side = 40, Lift = 24 },

	--[[ IT WEAVES (Dylan, 2026-10-01): a driver making a run for it picks gaps rather than holding the
		centre lane. Every `Reconsider` seconds the truck looks `Lookahead` studs past its nose in its
		own lane and the two beside it, for traffic within `LaneHalf` of each lane's centre and for the
		obstacle course, and moves one lane over when a neighbour has at least `Better` studs more clear
		road. When every lane is blocked it holds its line and the ram above clears the way, so it
		still ploughs through some of them.

		The move is a real lane change, not a slide: sideways speed eases up to `MaxLateral` at
		`LateralAccel`, the truck yaws into it (heading follows its own velocity), and the body leans
		`RollDeg` off the turn while it accelerates sideways. `StartAfter` holds the first move until
		the camera has started its sweep, so the first swerve is on screen. ]]
	Weave = {
		Enabled = true,
		StartAfter = 0.8,
		Reconsider = 0.3,
		Lookahead = 170,
		LaneHalf = 10, -- lanes are 15 apart, so a car one lane over is not "in" this one
		Better = 30,
		MaxLateral = 20,
		LateralAccel = 55,
		Gain = 2.6, -- per second: how hard it closes on the new lane before MaxLateral caps it
		RollDeg = 1.5,
		RollGain = 6,
	},
}

function GetawayConfig.approachAhead(closing: number, fraction: number): number
	local cfg = GetawayConfig.Spawn
	local t = math.clamp(fraction, 0, 1)
	local fixed = cfg.AheadMin + (cfg.AheadMax - cfg.AheadMin) * t
	local seconds = cfg.ApproachSeconds[1] + (cfg.ApproachSeconds[2] - cfg.ApproachSeconds[1]) * t
	return math.clamp(math.max(fixed, math.max(closing, 0) * seconds), cfg.AheadMin, cfg.AheadCap)
end
function GetawayConfig.openRange(closing: number): number
	return math.max(GetawayConfig.Open.Range, math.clamp(math.max(closing, 0) * 3 + 100, 0, 1400))
end

--[[ THE BANK FLASH (2026-10-06, the polish pass). Banking a supercar looked exactly like banking a
	beater. Now, the moment the car is in the bay, the truck flashes with light in the car's rarity
	colour (`CarRarity.colourOf`) and a column of it shoots up out of the trailer, both bigger the rarer
	the car (`PerBand` on top of the base, per band above 1), with a burst of sparkles. Client-side and
	purely visual. `Enabled = false`: the bank as before. ]]
GetawayConfig.BankFlash = {
	Enabled = true,
	Brightness = 4,
	PerBand = 2,
	Range = 30,
	Seconds = 0.9,
	BeamHeight = 30,
	BeamPerBand = 12,
	BeamWidth = 3,
	Sparkles = 30,
	SparklesPerBand = 20,
}

-- === Never stuck on the ramp ================================================
--[[ === THE RAMP CANNOT HOLD YOU — 2026-10-09 ===
	The owner, with a screenshot of a car wedged at the ramp's foot while the police busted it: "cars
	can get stuck on/in the ramp causing players to take damage or police to catch them ... patch it
	for good". What the audit of this file and `GetawayController` found:

	THE ASSIST WAS ONE-SHOT. `Boarding` catches a car only on the single frame its nose crosses the
	ramp's foot (`GetawayBoarding.enters`), and only if every one of ten tests passes on that frame —
	closing speed, yaw under 25 degrees, the whole hull inside the doorway with `SideMargin` to spare,
	the ramp already fully down and SOLID, no steal flight, the driving shim live. Miss any one and the
	next frame's sample starts past the foot, which `enters` rejects forever. From then on the car is
	plain physics against an anchored, CFrame-posed 26.7-degree plate moving at truck speed: it climbs,
	or it rides up the lip and wedges, or (arriving while the ramp was still deploying, centre inside
	the plate) the plate never goes solid at all (`_pose`'s guard) and the car sits half inside it.
	A wedged car is a SLOW car: the police bar drains under its floor speed, traffic rear-ends it, and
	that is the damage and the bust in the screenshot.

	THREE LAYERS NOW, each `Enabled` on its own:

	  `Rescue`   the second net. A car whose hull centre has sat on the ramp's footprint (or just
	             behind its foot, `Reach`) for `Dwell` seconds is captured from WHEREVER it is — any
	             speed, up to `MaxYawDeg` of yaw, off-centre, ramp solid or not — and climbed in by the
	             same assisted climb, which centres it. `Dwell` lets the ordinary capture go first.
	  `Stranded` a car whose centre is inside the bay box (no margins) for `Dwell` seconds banks, rather
	             than waiting on the strict `Bank` test — and an assisted climb that ends just outside
	             the strict test banks the same way instead of being released at the sill. The server
	             checks nothing positional on a bank (`GetawayService._onBanked` awards the recorded
	             car), so this only stops the client refusing a car that is visibly aboard.
	  `Shelter`  while the open truck's ramp is down and the hull is in the box behind it (`Behind`
	             studs past the ramp's foot, `Side` studs either side of the bay) or being climbed in,
	             nothing can punish being there: traffic hits (`TrafficController._onClip`), wall
	             scrapes (`ObstacleController._checkWall`) and police strikes are not charged, the
	             police drain is waived, and the arrest cannot begin (`PoliceController`). A failed
	             approach costs you the approach, never the run.

	`Enabled = false` on all three is the getaway exactly as it was. ]]
GetawayConfig.Rescue = {
	Enabled = true,
	Dwell = 0.15,
	--- Studs behind the ramp's foot a hull CENTRE still counts as "on it": about half a car, so a
	--- nose wedged against the lip is caught.
	Reach = 6,
	--- Studs beyond the ramp's half-width either side, for a car riding up its edge.
	SideSlack = 3,
	--- How high over the plate's surface a hull centre may be and still be ON it (not jumping it).
	Above = 6,
	MaxYawDeg = 70,
}
GetawayConfig.Stranded = {
	Enabled = true,
	Dwell = 0.3,
}
GetawayConfig.Shelter = {
	Enabled = true,
	Behind = 16,
	Side = 4,
}

--[[ NO GETAWAY WITH THE POLICE ON YOU (2026-10-12). While a chase is on (`PoliceController:getChase`,
	"live" or mid-PIT), the wait for a truck is HELD where it is, and a truck already on the road
	shuts its ramp and doors and will not take the car. You have to lose them first: once the
	cruisers peel off ("leaving") the wait runs again and an open truck reopens as you close on it.

	One grace: a player already in the truck's shelter (`Shelter`) when the chase arms is let in,
	because they had committed to the ramp before the police existed. Leaving the shelter ends it.

	`Enabled = false` is the getaway exactly as it was.

	=== A TRUCK ON THE ROAD LEAVES — 2026-10-14 ===
	WAS: a truck already out when the chase armed stayed on the road, shut, until it was driven past.
	A truck that had spawned a moment before the cruisers did sat closed in front of the player for
	the whole chase (the owner: "the van popped up as soon as the police started a chase, and didn't
	even open; it shouldn't be there when the police are"). IS (`Vanish`): it is taken off the road
	the frame the chase locks, and the wait for the next one starts over, held until the chase ends,
	so the next truck turns up only once the police are lost. A truck the player is already climbing
	into (`Shelter`'s grace, a climb under way) is left alone. `Vanish = false`: the shut truck again. ]]
GetawayConfig.PoliceLock = {
	Enabled = true,
	Vanish = true,
	--[[ Seconds the server holds a bank that arrived mid-chase before letting it through anyway
		(`GetawayService._onBanked`, 2026-10-15). The client only banks a car it has already shut in
		the truck, so a refused bank stranded the player in the van; held, it goes through when the
		chase ends, or after this, whichever is first. Long enough for an ordinary chase to peel off. ]]
	HoldSeconds = 20,
}

return GetawayConfig
