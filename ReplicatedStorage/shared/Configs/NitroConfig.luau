--[[
	NitroConfig
	-----------
	The nitrous bottle: a tank you spend, a surge while you hold it, and the wait before you can
	spend it again. Every number the feature has is in this file.

	=== IT IS NOT THE SAME THING AS BOOST, AND THE DIFFERENCE IS THE POINT ======================

	`DriveConfig` already has a "go faster" and it is free: the throttle drives itself, and holding
	accelerate raises the car's speed dial by `BoostSpeedScale` (1.35) for as long as you like. That
	is the cruise/boost/brake trio, and nothing here replaces it.

	Nitro is the third rung above that trio and it is the only one with a COST. It raises the same
	dial further (`Power` below), it answers the frame you press it (`Kick`), and it runs out. So
	the three speeds a player has are:

	    nothing held      cruise, forever
	    accelerate held   boost, forever, +35%
	    nitro held        surge, for a few seconds, and then you have to earn it back

	Everything in `Tank` exists to make that last line true. If nitro is ever made free, boost is
	what it turns into and the button stops meaning anything.

	=== ONE DIAL, TAKEN AT ITS HIGHEST, NEVER MULTIPLIED ========================================

	Boost and nitro both move the car's `MaxSpeed` attribute and `DriveController` resolves them
	with `math.max`, not by multiplying. That is deliberate: multiplied, holding accelerate while
	firing nitro would land at 1.35 x 1.80 = 2.43 and a player would have two speeds for the same
	button depending on what their other hand was doing. Taken at the highest, nitro means one
	speed whatever else is held, and it is always the fastest thing on the car because every scale
	below is above `DriveConfig.BoostSpeedScale`.

	Keep that invariant if you retune `Power`. A nitro scale under the boost scale would make the
	button a no-op that still drains the tank, which reads as the feature being broken.

	=== THE SCALE IS A RATIO, SO IT TRAVELS ACROSS THE ROSTER ===================================

	`DriveConfig`'s boost note has the full argument and it applies unchanged here: the stock
	chassis damps driving torque by exp(-3r^2) with r = speed / MaxSpeed, so the car settles where
	that torque dies rather than where the motors were aimed. r is a RATIO, so scaling `MaxSpeed`
	drags the whole curve up and a given scale lands the same percentage on top of whatever a car
	cruises at. None of the numbers below are in studs per second except `Kick`, and that one is.

	Measured cruise for the two cars the drive layer was tuned against: the Civic cruises 71-75
	studs/s and boosts to 96-101, the Charger 84-85 to ~115.

	MEASURED AGAIN WITH NITRO FITTED, on the Civic, 2026-08-23, obstacles and traffic off so the
	only thing moving the number was the throttle:

	    cruise                          73-75 studs/s, dial 34.4
	    press                           dial 58.5 the same frame, 73 -> 85 inside 0.1s (the Kick)
	    a full 2.6s bottle              peak 107.6, i.e. +47% on cruise
	    the same bottle at scale 2.10   peak 129.8

	The current 2.15..2.40 range deliberately goes beyond that 2.10 measurement because nitro is now
	the run's brief spectacle rather than a restrained fourth speed. It therefore needs a traffic-on
	playtest: a world-1 beater already passed 130 studs/s at 2.10. Note also that neither measured
	figure is an equilibrium: a
	bottle is spent long before the torque curve settles, so what a player feels is the CLIMB rather
	than the ceiling, and the ceiling only decides how steep that climb is.

	=== WHAT SCALES WITH THE CAR, AND WHY IT IS THE RUNG AND NOT THE TIER =======================

	A better car gets a bigger bottle and a harder shove, and both are read off the car's position
	on ITS OWN WORLD'S LADDER rather than off its global tier. That matches how `CarConfig` authors
	speed and health: the stat curve restarts in every world, so world 2's beater is as slow as
	world 1's, and a nitro keyed to the global tier would hand a world-2 starter car the bottle of
	a world-1 supercar. `rungFraction` below is that 0..1 position, and everything tier-shaped in
	this file is a lerp across it.

	=== IT IS ON EVERY CAR TODAY, AND THAT IS A DECISION WITH A SEAM ============================

	Nitro is fitted to every car in the game right now so it can be played with. If it later becomes
	something bought (the dealership billboard already sells one driving upgrade, `UpgradeConfig`'s
	`Jump`), the seam is `NitroConfig.powerFor` : give it the owned level, lerp the same two ends
	wider, and nothing else in the feature has to know. Deliberately NOT wired to a profile yet, so
	there is no half-built economy hanging off an untested mechanic.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DriveConfig = require(ReplicatedStorage.shared.Configs.DriveConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local NitroConfig = {}

-- Master switch. Off = no key binding, no button on the HUD, no bar, and the drive layer never
-- hears about it.
NitroConfig.Enabled = true

-- === Input ==================================================================

--[[ HOLD to burn, release to stop. Not a tap-for-a-fixed-burst, because a burst you cannot cut
	short is a burst you have to plan a corner ahead, and this game's corner is a gap in traffic
	that opens half a second before you reach it.

	Neither key is claimed by anything else. The stock place-side `Keymap` uses W/Up/R2 for
	throttle, S/Down/L2 for brake, Space/ButtonA for the handbrake (which the bail then takes,
	`StealConfig.BailKeys`), A/D/Left/Right/Thumbstick1 for steering and E/ButtonY to enter, and
	`StealConfig.Prompt.Keys` takes E/ButtonX for the length of a flight. LeftShift and the left
	bumper are the two the whole race leaves alone. ]]
NitroConfig.Keys = { Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL1 }

--[[ Bound above the stock `Driver`, and sunk, for exactly the reason `StealConfig.BindPriority`
	spells out: that script binds its raw-input handler at `ContextActionPriority.High` (3000) and
	sinks every key it recognises. Ours are keys it does not recognise, so this priority costs
	nothing today. It is here so that a rig whose Keymap grows a LeftShift binding tomorrow loses
	the argument rather than winning it silently. ]]
NitroConfig.BindPriority = Enum.ContextActionPriority.High.Value + 500

-- === The tank ===============================================================

--[[ How long a full bottle lasts, in SECONDS OF BURN, at the bottom and the top of a world's
	ladder. Seconds rather than a unitless capacity because it is the number a player actually
	experiences, and because the drain rate then falls out of it instead of being a second dial
	that has to be kept in step.

	2.6 is long enough to clear a knot of traffic and short enough that you spend it on something.
	4.2 at the top of a ladder is not double: a supercar's bottle being twice a beater's would make
	the last rung feel like a different game rather than a better car. ]]
NitroConfig.Tank = {
	SecondsBottom = 2.6,
	SecondsTop = 4.2,

	--[[ Seconds from empty back to full, with nothing helping. The duty cycle is the design: about
		3 seconds of surge against 10 of waiting is a quarter of the run spent flat out, which is
		the shape a limited resource has to have to stay worth watching for. Drop this and the
		button stops being a decision. ]]
	RefillSeconds = 10,

	--[[ Dead time after the burn stops before the refill starts, so a player cannot stutter the key
		and sit permanently at the top of the tank. Also what makes the bar's refill read as a
		refill: without the pause it starts climbing on the same frame it stops falling, and the
		eye sees one continuous wobble instead of two states. ]]
	RefillDelay = 0.8,

	--[[ The tank has to be at least this full to LIGHT, as a fraction. Nothing stops it draining
		to zero once lit. Without a floor, a nearly-empty tank gives a few frames of surge per
		press, which on a held key is a machine-gun stutter of the speed dial, the flame and the
		FOV, and reads as the feature misfiring rather than as an empty bottle. ]]
	MinToFire = 0.15,

	--- How full a bottle a run STARTS with, as a fraction. Full: the first thing a player should
	--- get to do with a new mechanic is use it, not wait for it.
	StartFraction = 1,

	--[[ Does a steal refill the bottle? Yes, and it is the same rule as HP: taking a car gets you
		that car's tank, not the wreck of the last one's. It also pays the risk of the bail, which
		is the moment in this game most in need of paying. ]]
	RefillOnSteal = true,
}

-- === What a burn does =======================================================

NitroConfig.Power = {
	--[[ The `MaxSpeed` multiplier while burning, at the bottom and top of a world's ladder. Read
		the header first: this is resolved against boost with `math.max`, so BOTH ENDS MUST STAY
		ABOVE `DriveConfig.BoostSpeedScale` or the button silently does nothing on the cars below
		it. `NitroConfig.assertSane` checks that at load. ]]
	ScaleBottom = 1.6,
	ScaleTop = 1.8,

	--[[ Studs/s added along the road on the frame the bottle lights, once per press.

		The reason it exists: the chassis is TORQUE limited, so raising the dial changes where the
		car will eventually settle rather than how fast it is going now, and the climb to a 1.7 dial
		takes longer than the 3 seconds the bottle lasts. Without a kick the button's whole reward
		arrives after the button is finished, which reads as lag.

		It is one write to `AssemblyLinearVelocity` along the road's forward axis, which is the same
		tool `ObstacleController`'s shove and the wreck coast already use on this assembly, and
		`DriveController._lane` is provably indifferent to it (it swaps the CROSS component only).
		34 preserves the ignition shove as roughly the same share of cruise after the global ceiling
		moved from 2x authored speed to 1.4x; the sustained 2.15..2.40 scale supplies the surge after. ]]
	Kick = 20,
}

-- === Earning it back ========================================================

--[[ The bottle refills on a clock, and it also refills for driving well. Both, on purpose: the
	clock is what stops a bad run being unrecoverable, and the near miss is what makes the good run
	feel like it is paying for itself.

	The near miss is the right thing to pay on because it is already the game's skill move: it is
	measured, priced and toasted (`NearMissConfig`), and it happens in the exact moment nitro makes
	dangerous. Trading paint pays NOTHING, and that asymmetry is the whole message: shaving past a
	car earns you speed, hitting it does not. ]]
NitroConfig.Gain = {
	--- Fraction of a full tank a clean near miss pays back. A chain of five is half a bottle.
	PerNearMiss = 0.08,

	--- ...and a rub the other car shrugged off. Zero, see above. Here so the asymmetry is a number
	--- somebody chose rather than a case somebody forgot.
	PerTradingPaint = 0,

	--[[ Does a gain arriving mid-burn count? This note argued yes — refusing it means the moment you
		are most likely threading traffic is the moment threading it stops paying — and it shipped
		`true`; the balancing commit d1f41d3 set it `false` without a note, so near misses no longer
		refill a burning bottle. A NITRO PACK IS NOT GATED BY THIS (2026-10-08): it pays always, see
		`NitroController.reward`'s `always`. ]]
	WhileBurning = false,
}

-- === What it looks like =====================================================

--[[ The camera pushing in. Added on top of whatever `RaceCameraController` is already doing with
	`CameraConfig.FieldOfView` + `SpeedFovDeg`, through a public setter, so the two cannot fight
	over the property.

	Asymmetric on purpose, and this is the restrained reading of the effect: it snaps in over a
	sixth of a second so the press has an instant consequence, and it falls back over half a second
	so letting go is a glide rather than a second event competing with the first. ]]
NitroConfig.Fov = {
	Deg = 15,
	RiseTime = 0.18,
	FallTime = 0.75,
}

-- Ease the vibration separately from FOV so either visual can be tuned or disabled independently.
NitroConfig.Shake = {
	Enabled = true,
	RiseTime = 0.22,
	FallTime = 0.45,
}

--[[ The flame out of the back. Two emitters at the rear corners of the car's HitBox, cloned per
	race and destroyed with it.

	OFF THE HITBOX rather than off the body: every car in the game shares one HitBox convention
	(a redress fits the art to the chassis, not the other way round), so an offset stated as a
	fraction of that box is the same offset on all 65 rigs. A body-relative anchor would need a
	per-car table and would be wrong the first time a modeller re-exported one.

	THE TEXTURE IS AN ENGINE ONE, deliberately: no upload, no asset id to lose, and it is the same
	flipbook Roblox's own Fire uses, so it composites like every other flame a player has seen. ]]
NitroConfig.Flame = {
	Enabled = true,
	Texture = "rbxasset://textures/particles/fire_main.dds",

	--[[ THE TURBO FIRE, ON TOP (2026-09-30, the owner: "use the fire trbo for the nitro too, maybe
		combine them"). The delivered `fire trbo` effect's emitters (`Names`, found in the collision
		pack, `CrashVfxConfig.FolderName`) are cloned onto each jet BESIDE whatever flame the jet already
		has, and burn exactly when it does — one more layer, not a replacement.

		TWO OF THE ARTIST'S PROPERTIES ARE OVERRIDDEN and only two: `EmissionDirection = Back` and
		`VelocityInheritance = 1`, the pair `_buildFlames` calls load-bearing for any jet — authored as
		a campfire, the flame goes UP and is left hanging in the air behind a car doing 120 studs/s.
		Everything else (texture, colour, size, rate, lifetime) is the artist's.

		`Enabled = false` is the nitro flame exactly as before; a missing folder is the same, silently. ]]
	Turbo = {
		Enabled = true,
		Names = { "Fire1" },
		--[[ The artist's size and rate, multiplied (2026-09-30, "barely there" on the first playtest).
			A flame authored at a campfire's scale is a candle on the back of a car at speed. The only
			other overrides are the two above. ]]
		SizeScale = 2.2,
		RateScale = 2,
	},

	--[[ Where the two jets sit, as fractions of the HitBox's own size: X across (mirrored), Y up
		from its centre, Z along its length with +Z being the REAR (a Roblox part looks down -Z).
		0.5 is the back face exactly, so 0.47 tucks the emitter a hair inside the bumper. ]]
	Offset = Vector3.new(0.3, -0.15, 0.47),

	Rate = 190,
	Lifetime = NumberRange.new(0.12, 0.24),
	--- Studs/s the flame is thrown BACKWARDS at, i.e. against the car's travel. It has to be well
	--- under the car's own speed or the flame outruns the bumper and hangs in the air behind it.
	Speed = 46,
	SpreadDeg = 6,
	Size = 4.3,
	--- Fraction of the flame's life spent growing before it collapses. A jet is widest at its root.
	Taper = 0.65,
	--- Studs of light at the jets while burning, 0 to leave the car unlit.
	LightBrightness = 4,
	LightRange = 22,

	--[[ Nitrous burns blue and this kit's brand colour is blue, so the flame and the bar agree
		without either being tinted to match the other. White at the root is the hot core. ]]
	Core = Color3.fromRGB(235, 250, 255),
	Mid = Color3.fromRGB(60, 170, 255),
	Tail = Color3.fromRGB(0, 80, 220),

	--[[ THE LIBRARY LOOK, drawn instead of the jet above while `NitroConfig.FlameVfx` is on. The
		mount (`Offset`) and the light are shared; everything else is here.

		Why it exists: the engine flame tinted blue read as a water spray, because `fire_main` is a
		soft round puff and soft round blue puffs are what a hose throws. Three things make it read
		as a burn instead, and each is one layer: a fire sheet with real flame shapes rather than
		puffs, a white-hot glow pinned to the nozzle, and sparks thrown back past the flame. The
		colour runs blue into VIOLET at the tail, which no water does.

		Textures are from the VFXer plugin library (see `WeatherConfig`). A layer spec:

		    Texture, Flipbook   image id, and "Grid2x2" / "Grid4x4" / "Grid8x8" for a sheet
		    Colors              { root, middle, tail } across a particle's life
		    Size                { root, peak, tail } studs, the peak at `Taper` of the life
		    Transparency        { root, late, tail }, the late key at 0.7 of the life
		    Rate, Lifetime      per second, and { min, max } seconds
		    Speed               studs/s thrown backwards, a number or { min, max }
		    Spread, Rotation    degrees of cone, and degrees either way of upright at birth
		    Spin, Drag          degrees/s either way, and the slow-down
		    Squash              negative stretches along the travel on "VelocityParallel"
		    Orientation         "FacingCamera" (default) or "VelocityParallel"
		    Locked              true pins the particles to the car (the nozzle glow)
		    ZOffset             studs drawn toward the camera, to clear the road and the bumper
		    Glow, Brightness    LightEmission and Brightness. Both push a coloured layer toward
		                        white, which is how the first pass of this flame lost its blue ]]
	Vfx = {
		LightColor = Color3.fromRGB(110, 110, 255),

		Layers = {
			-- The flame itself, in the same shape and at the same pace as the original jet so its
			-- silhouette survives; only the texture and the colour moved.
			--
			-- The sheet is VFXer's blue fire (2x2), which is ALREADY coloured: `Colors` multiply it, so
			-- the violet tail comes out as a deep blue-violet rather than as violet. Tried against it
			-- and dropped: the white flame sheet `111860228388694` (read as ice shards once lit) and the
			-- curly wisps `122798754976132` (too thin to read behind a car). `Glow` stays under half:
			-- at 1 the blue burned to white over a pale road.
			--
			-- `ZOffset` 2 is load bearing. The jet sits a fraction of a stud above the deck, so a
			-- 3-stud flame quad cuts into the road and the cut shows as a flat bottom on a texture
			-- with hard edges (the soft engine flame hid it).
			{
				Name = "Flame",
				Texture = "rbxassetid://88016651726242",
				Flipbook = "Grid2x2",
				Colors = {
					Color3.fromRGB(255, 255, 255),
					Color3.fromRGB(100, 160, 255),
					Color3.fromRGB(165, 90, 255),
				},
				Size = { 1.2, 3, 0.6 },
				Taper = 0.45,
				Transparency = { 0.05, 0.35, 1 },
				Rate = 115,
				Lifetime = { 0.1, 0.22 },
				Speed = 46,
				Spread = 8,
				Rotation = 15,
				Spin = 0,
				Drag = 2,
				Glow = 0.4,
				Brightness = 1.1,
				ZOffset = 2,
			},
			-- The white-hot nozzle. Pinned, so it sits on the bumper at any speed.
			{
				Name = "Core",
				Texture = "rbxassetid://12713358298",
				Colors = {
					Color3.fromRGB(255, 255, 255),
					Color3.fromRGB(170, 215, 255),
					Color3.fromRGB(90, 140, 255),
				},
				Size = { 2.2, 2.6, 1.2 },
				Taper = 0.3,
				Transparency = { 0.1, 0.4, 1 },
				Rate = 45,
				Lifetime = { 0.06, 0.1 },
				Speed = 0,
				Spread = 0,
				Rotation = 0,
				Spin = 0,
				Drag = 0,
				Locked = true,
				Glow = 1,
				Brightness = 1.2,
				ZOffset = 1,
			},
			-- Sparks streaking back past the flame.
			{
				Name = "Sparks",
				Texture = "rbxassetid://12713358298",
				Orientation = "VelocityParallel",
				Colors = {
					Color3.fromRGB(235, 250, 255),
					Color3.fromRGB(80, 170, 255),
					Color3.fromRGB(160, 80, 255),
				},
				Size = { 0.35, 0.35, 0 },
				Taper = 0.5,
				Squash = -2.5,
				Transparency = { 0, 0.2, 1 },
				Rate = 26,
				Lifetime = { 0.2, 0.35 },
				Speed = { 60, 90 },
				Spread = 14,
				Rotation = 0,
				Spin = 0,
				Drag = 1,
				Glow = 0.8,
				Brightness = 1.2,
			},
		},
	},
}

--[[ Which flame a burn draws. True is `Flame.Vfx` (the library look), false is the original jet in
	`Flame` exactly as it shipped. Kept as a flag so the old look is one line away. The F2 panel's
	Pickups tab flips this client's copy live and rebuilds the flame on the car you are in. ]]
NitroConfig.FlameVfx = true

--[[ Nitro's ignition sound hook. The SoundGroup is authored in Studio like the near-miss groups;
	missing or blank sounds safely no-op, so code and UI can ship before the final clip is chosen.

	`Group` is a `SoundService` SoundGroup name, started through `SoundController:PlayRandom` on the
	frame the bottle lights and explicitly stopped when the burn ends. A child may therefore be a
	looped burn or a one-shot ignition clip. Add multiple children for non-repeating variations.
	A missing group or blank SoundId safely stays silent. ]]
NitroConfig.Sound = {
	Group = "Nitro" :: string?,
}

--[[ The screen. `DrivingHudController` owns the instances; these are the numbers it paints them
	with, and the names it looks the instances up by.

	THE UI IS AUTHORED IN STUDIO like the rest of the driving HUD (`StarterGui.DrivingHud`), so
	moving the bar or the button is an Explorer edit. Nothing below is a position. ]]
NitroConfig.Hud = {
	--[[ WHICH READOUT, and how it is dressed. Both are live A/B switches, not settings.

		THREE are authored in `StarterGui.DrivingHud` and only one is ever shown. `Nitro` is the
		wide bar over the cluster, `NitroVertical` a thin column standing beside the speedo, and
		`NitroBadge` the round one with the bottle in it, out at the bottom-right corner next to
		`SpeedoV2` (see `Badge` below, which is the whole of that feature). `Layout` picks;
		`_attachNitro` hides the rest. They are three authored instances rather than one instance
		the code reshapes, because layout in this HUD lives in Studio and a bar that has to be
		legal in every orientation ends up right in none of them.

		BADGE IS THE CURRENT ANSWER and it is one word from being either bar again. It went in on
		2026-09-18 and has had no human pass, so the two bars stay exactly where they were until
		it has had one.

		`Track` is the framed 800x80 art behind the pill. OFF is the current answer: with the
		track drawn there is a gap between the fill and the frame, and at this size that gap reads
		as slop rather than as a bezel. Off, the bar is a pill with a stroke, which is exactly how
		the car's own HP bar is built, so the two agree.

		When one of these wins, DELETE the loser and this switch. A flag that outlives its
		experiment is just a second thing that has to keep working. ]]
	Layout = "Badge" :: "Horizontal" | "Vertical" | "Badge",
	Track = false,

	--[[ The Frame each layout maps to, as a PATH under the ScreenGui, and the touch button inside
		`Controls`. Missing any of them is not an error: the feature still runs on the key, minus
		that readout.

		A path rather than a name for two reasons. The vertical bar hangs off `Cluster` and has to
		(see below), and `Nitro` is already the name of the touch BUTTON inside `Controls`, so a
		recursive search for the bar finds the button first. ]]
	Bars = {
		Horizontal = { "Nitro" },
		--[[ Under the CLUSTER, not the ScreenGui, and this is load bearing.

			The cluster carries its own `UIAspectRatioConstraint`, so its width is driven by the
			viewport's HEIGHT while a scale position on the ScreenGui is driven by its WIDTH.
			Those two cannot agree across aspect ratios: parked as a sibling at the spot that
			looks right on a 1345x620 desktop, the bar landed ON the gauge art at 1136x640. As a
			child of the cluster it is measured in the same frame as the dial it stands beside,
			and `Dial` is `Stretch` at size (1,1), so cluster coordinates ARE gauge coordinates. ]]
		Vertical = { "Cluster", "NitroVertical" },
		--- A direct child of the ScreenGui, like `SpeedoV2` and for the same reason: it is parked
		--- against a screen corner rather than against the retired gauge art, so it has no
		--- business being measured in the cluster's frame.
		Badge = { "NitroBadge" },
	},
	ButtonName = "Nitro",

	--- How fast the bar chases the tank, per second. High enough that a burn looks live, low
	--- enough that a near miss's payout reads as a jump rather than a teleport.
	FillLerp = 14,

	--[[ The fill's three states. Ready is the resting colour, Burning is the hot core it goes to
		while the key is held, and Low is where it sits under `Tank.MinToFire`, i.e. while the
		button will not answer. Three colours for three things the player needs to tell apart at a
		glance, and no more than that. ]]
	ReadyColor = Color3.fromRGB(0, 148, 255),
	BurningColor = Color3.fromRGB(200, 245, 255),
	LowColor = Color3.fromRGB(70, 92, 130),

	--- The trough behind the fill, as a fraction of the fill's own colour. Same trick the HP bar
	--- uses: the empty part is the full part, dimmed, so the two can never disagree about hue.
	TrackDim = 0.28,

	--- The pulse while burning: how far the fill's transparency travels, and how fast. A breath,
	--- not a strobe.
	BurnPulse = 0.25,
	BurnPulseHz = 6,

	--- One flash of white across the bar when the tank crosses back over `MinToFire`, i.e. the
	--- moment the button becomes usable again. Seconds. 0 to switch it off.
	ReadyFlash = 0.22,

	--- The caption, and how the number is written. Percent, because the tank is a fraction and
	--- seconds would be a different number on every car. The vertical bar has no room for the
	--- caption and simply has no `Caption` label; the percent under it carries the reading.
	Caption = "NITRO",
}

--[[ === THE BADGE ===========================================================================

	The round readout: a bottle in a dark disc with a ring around it, standing beside the speedo.
	`Layout = "Badge"` is the flag for the whole thing, and OFF means the two bars above are
	untouched and this table is dead weight rather than a second thing to keep working.

	=== THE TWO VERSIONS, AND WHY THEY ARE ONE BUILD ========================================

	`Style` picks which shape carries the reading, and both are drawn from the same five uploads:

	  Ring  the RING is the bar. It sweeps clockwise from twelve and drains as the tank does, and
	        the bottle inside is a full glyph that only changes colour. This is the reference
	        Dylan posted.
	  Fill  the BOTTLE is the bar. The ring goes dim and stays put, and the liquid inside the
	        glass rises and falls instead. The icon is the container.
	  Both  both at once, which is neither version and is here because the two code paths are
	        independent and an A/B with a third answer costs one string.

	There is no third drawing for any of that. `Art.Liquid` is white and is worn twice, dimmed as
	the well behind the liquid and at full colour as the liquid itself, which is the same trick
	the bar above and the car's HP bar use: two halves of one readout that can never disagree
	about hue because one IS the other.

	=== WHERE IT SITS, AND WHAT IT LANDS ON =================================================

	`Corner` and `Margin` park it exactly the way `SpeedoConfig.Panel` parks the speedo, so the two
	are measured by one rule at any viewport. The default stands it ON TOP OF the speedo, centred
	over that panel with a hair of air between them, which is where Dylan put it on 2026-09-18.

	CENTRED AT 16:9 AND PINNED BY ITS RIGHT EDGE. A corner margin fixes the edge, not the middle,
	and the badge's width is a fraction of the viewport's HEIGHT while the margin is a fraction of
	its WIDTH, so on a much taller or much wider screen the badge drifts a few percent of the panel
	against its centre. That is the cost of both being parked by the same corner rule, and it is
	worth less than a second scheme nobody else on this HUD uses.

	IT OVERLAPS A TOUCH CONTROL WHEREVER IT GOES, and that is not an oversight: with every control
	visible there is no square in this corner that touches nothing. On the keyboard that is moot,
	because the whole `Controls` frame is hidden there. `BuildNitroBadge` prints which controls the
	badge lands on so the choice is made with the numbers in hand, and the fix is one number here or
	a nudge to the pedal in the Explorer, which is where that pedal's layout lives.

	Both are fractions of the VIEWPORT, and `Height` is against its height rather than its width
	because the badge is square and a width fraction would grow it on every wider screen. ]]
NitroConfig.Hud.Badge = {
	Style = "Ring" :: "Ring" | "Fill" | "Both",

	Corner = "BottomRight" :: "BottomRight" | "BottomLeft" | "TopRight" | "TopLeft",
	--[[ Read off `SpeedoConfig.Panel` rather than guessed: that panel is anchored bottom-right at
		a margin of (0.017, 0.035) and is 0.156 x 0.119 of the viewport, so its top edge is at
		0.846 and its middle at x 0.905. `Margin.Y` stands the badge's bottom 0.012 above that top
		edge, and `Margin.X` puts its right edge where a 0.135-tall square centres on that middle
		at 16:9. Retune either and the badge moves as one piece. ]]
	Margin = Vector2.new(0.057, 0.166),
	Height = 0.135,

	--[[ The five uploads, as Image ids. `assets/ui/driving/build_nitro_badge.py` IS the art and
		`assets/ui/driving/README.md` carries the decal-to-image pairs.

		EVERY ONE OF THEM IS WHITE, so `ImageColor3` does the colouring and the three states below
		are the only place a nitro colour is written. A blank id here is not an error: the builder
		draws the piece anyway and it renders as nothing, which is a missing texture and not a
		missing badge. ]]
	Art = {
		Glass = "rbxassetid://135803889677891",
		Liquid = "rbxassetid://91553939610738",
		Ring = "rbxassetid://76914133988408",
		RingHalf = "rbxassetid://111964530528860",
		Glow = "rbxassetid://127775850218058",
	},

	--- The disc behind the bottle, and the rim around it. Transparency rather than a flat colour
	--- so the road still reads through it at speed, which is the one thing a HUD sitting over the
	--- middle of the screen has to do.
	Plate = Color3.fromRGB(18, 24, 42),
	PlateTransparency = 0.12,
	PlateStroke = Color3.fromRGB(10, 14, 26),
	PlateStrokeThickness = 2,

	--- The bottle inside the ring, as a fraction of the badge. Big enough to read at 100px on a
	--- phone, small enough that the ring is not wearing it as a collar.
	IconScale = 0.62,

	--- The ring's track and the bottle's well, each as a fraction of the fill's own colour. Same
	--- number and the same reason as `Hud.TrackDim` above.
	RingDim = 0.26,
	WellDim = 0.30,

	--[[ The bloom behind the disc while the bottle is alight. `Max` is its transparency at full
		burn and 1 switches it off; `Scale` is how far past the badge it spreads.

		It is on the BURN and nothing else. A glow that also rode the tank would be a second thing
		saying what the ring already says, and it would be lit for most of a race. ]]
	Glow = {
		Max = 0.35,
		Scale = 1.9,
	},

	--[[ The percent beside the badge, as the vertical bar carries one. OFF, and that is the answer
		Dylan gave on 2026-09-18 once the badge was standing on the speedo: the arc IS the
		percentage in `Ring`, the liquid is it in `Fill`, and the number under the pair is already
		the speedo's. A badge reads by shape, and this one has nothing left to say in words.

		True puts it back, ABOVE the badge, where `BuildNitroBadge` explains it has to go. ]]
	ShowAmount = false,
	AmountColor = Color3.fromRGB(226, 240, 255),
}

--- The path to the authored Frame the current `Layout` maps to, under the DrivingHud ScreenGui.
--- Falls back to the horizontal bar rather than to nothing, so a typo in the flag costs the bar
--- its shape and not its existence.
function NitroConfig.barPath(): { string }
	return NitroConfig.Hud.Bars[NitroConfig.Hud.Layout] or NitroConfig.Hud.Bars.Horizontal
end

-- === Asking about a car =====================================================

--[[ Where a body sits on its own world's ladder, 0 (that world's beater) to 1 (its best car).

	Not the global tier. See the header: `CarConfig` restarts its stat curve in every world, and a
	nitro keyed to the global tier would hand world 2's starter car the bottle of world 1's
	supercar. Anything unknown answers 0, which is the safe end: an unrostered rig gets the
	smallest bottle rather than the biggest. ]]
function NitroConfig.rungFraction(body: unknown): number
	if type(body) ~= "string" then
		return 0
	end
	local tier = WorldConfig.TierOfBody[body]
	local world = WorldConfig.WorldOfBody[body]
	if not (tier and world) then
		return 0
	end
	local cars = WorldConfig.carsFor(world)
	local rungs = #cars
	if rungs < 2 then
		return 0
	end
	local rung = tier - WorldConfig.RungOffset[world]
	return math.clamp((rung - 1) / (rungs - 1), 0, 1)
end

--[[ Everything a car's bottle is, in one call: how hard it pushes and how long it lasts.

	One function rather than two so a caller cannot read the scale of one car and the capacity of
	another, which is exactly what happens when a steal lands between two lookups.

	THIS IS THE UPGRADE SEAM. If nitro is ever sold, take the owned level here and widen the same
	two lerps with it. Every consumer already asks this question and none of them care how it is
	answered. ]]
function NitroConfig.powerFor(body: unknown): { scale: number, seconds: number }
	local t = NitroConfig.rungFraction(body)
	local power, tank = NitroConfig.Power, NitroConfig.Tank
	return {
		scale = power.ScaleBottom + (power.ScaleTop - power.ScaleBottom) * t,
		seconds = tank.SecondsBottom + (tank.SecondsTop - tank.SecondsBottom) * t,
	}
end

--[[ The one invariant this file has that a typo can break silently, checked at load rather than
	documented and hoped for: a nitro scale at or under the boost scale is a button that drains the
	tank and changes nothing, which is indistinguishable from the feature being broken. Warned
	rather than thrown, on the same principle as the rest of the config layer: a bad number should
	cost you the feature, not the game. ]]
function NitroConfig.assertSane()
	local boost = if DriveConfig.AllowBoost then DriveConfig.BoostSpeedScale else 1
	for name, scale in { ScaleBottom = NitroConfig.Power.ScaleBottom, ScaleTop = NitroConfig.Power.ScaleTop } do
		if scale <= boost then
			warn(
				string.format(
					"[NitroConfig] Power.%s (%.2f) is not above DriveConfig.BoostSpeedScale (%.2f); "
						.. "nitro will drain the tank without going any faster on those cars.",
					name,
					scale,
					boost
				)
			)
		end
	end
end

return NitroConfig
