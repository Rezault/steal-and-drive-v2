--[[
	CrashVfxConfig
	--------------
	WHAT EACH OF THE NEW COLLISION EFFECTS IS USED FOR (2026-09-30). The owner delivered a folder of
	particle effects for collisions — sparks, fires and smokes — and asked for them to be used where they
	fit. This file is that assignment; `CrashVfxController` is the machinery, and every hit reaches it
	through `ObstacleController.applyImpact`, the one door every collision already goes through.

	=== THE HIERARCHY, WHICH IS THE WHOLE DESIGN =================================================

	A car's damage should be readable from the car itself, and the effects escalate with what happened:

	    wall scrape    SPARKS only, small — a scrape repeats on a cooldown for as long as you ride the
	                   rail, and smoke on every tick would bury the car
	    car hit        SPARKS at the point of contact + a SMOKE puff
	    heavy hit      + a bigger smoke burst (`HeavyShake` and up, on the hit's own `Shake`)
	    damaged        BLACK SMOKE trailing from the hood while health is at or under `Damaged`
	    critical       + FIRE (fire3) on the hood at or under `Critical` — the car is visibly about to go
	    wrecked        fire, black smoke and the big smoke together, replacing the plain plume

	NOT A CRASH EFFECT: `fire trbo` (Fire1) reads as a turbo/exhaust flame, so it went to the nitro
	instead (`NitroConfig.Flame.Turbo`, same day, the owner's call) and is found in this same folder.
	NOT USED AT ALL: `fire2` (Fire2Old) and `fire` (Fire2) — both a single orange dot at a playable
	distance in the owner's preview (2026-10-02; `fire` was the critical fire until then); `Civic` is a
	car, not an effect. Wire any of them in here by name if that reading is wrong.

	=== HOW THE EFFECTS ARE FOUND ===============================================================

	`ReplicatedStorage.<FolderName>` (the owner moves the delivered folder there and renames it: a
	client can only clone what replicates to it). Each entry below is a list of NAMES, and a name
	matches any descendant of the folder: a ParticleEmitter by that name is used itself, anything else
	(a model or part) contributes every emitter inside it. TWO MODELS ARE BOTH CALLED "smoke", so those
	are named by their EMITTER ("Smoke", "BlackSmoke") rather than by the model.

	The emitters' own looks (texture, colour, size, lifetime) are the artist's and are never touched.
	What this file decides is WHEN they play and HOW MANY particles a burst throws — the one number a
	one-shot needs that an authored looping emitter does not carry. Those counts are guesses until seen
	in play, and they are the first numbers to move.

	`Enabled = false` is the game exactly as before: the plain grey `Smoke` puff on a hit
	(`ObstacleConfig.HitSmoke`) and the plain plume on a wreck.
]]

local CrashVfxConfig = {}

CrashVfxConfig.Enabled = true

--- Under ReplicatedStorage. Missing warns once and every effect below is simply skipped.
CrashVfxConfig.FolderName = "CrashVFX"

--[[ The `Shake` a hit must reach to count as HEAVY (`ObstacleConfig.Kinds[*].Shake`,
	`TrafficConfig.Clip`): a Barrier is 1.2, Concrete 1.6, a Cone 0.35. `FullShake` is where a burst's
	count reaches its `CountAtFull`. ]]
CrashVfxConfig.HeavyShake = 1.2
CrashVfxConfig.FullShake = 1.6

-- === One-shot bursts, at the point of contact =================================================
--[[ `Count` particles per emitter on the gentlest hit, `CountAtFull` on a `FullShake` one, lerped by
	the hit's own `Shake`. `SizeScale` multiplies the artist's particle size.

	=== TOO FAINT AT SPEED — 2026-09-30 ======================================================
	First playtest: "barely there". WAS a burst fired from a fixed world point, the artist's size,
	and 6-18 / 3-8 / 3-8 / 4-10 particles. At 100+ studs/s the car and the camera behind it are past a
	fixed point in a fraction of a second, so the burst was over before it was seen — the exact
	problem the old grey puff had and solved by tracking the car (`ObstacleConfig.HitSmoke`). NOW a
	burst rides the car at the contact point and its particles INHERIT the car's velocity (`Inherit`),
	so they stay beside the car and drift back rather than being dropped on the road; sizes are
	scaled up and counts roughly tripled. All of these are still the numbers to move.

	=== SCALED PER EFFECT, FROM A SIDE-BY-SIDE PREVIEW — 2026-10-02 ===========================
	Second playtest: "I mainly see smoke". The owner then laid every delivered effect out in a row
	at the same distance, and the row explained it: the pack is NOT AUTHORED AT ONE SCALE. `Smoke`
	is a wide soft cloud already (doubled, it swallowed the car and everything else in the shot),
	while `FadingFlare` is a scatter of specks a couple of pixels across (doubled, still specks).
	One shared multiplier can only ever make one of them right. WAS Sparks 2 / Scrape 1.6 / Puff 2 /
	HeavySmoke 2.2; NOW each is sized against what it looked like in that preview: the sparks go up
	a lot, the white puff comes back to the artist's own size, `smoke 2` (the dark puffy cloud, the
	best-reading smoke in the pack) a little. ]]
CrashVfxConfig.Bursts = {
	Sparks = { Names = { "FadingFlare" }, Count = 18, CountAtFull = 50, SizeScale = 5, LightEmission = 1 },
	ScrapeSparks = { Names = { "FadingFlare" }, Count = 10, CountAtFull = 24, SizeScale = 4, LightEmission = 1 },
	Puff = { Names = { "Smoke" }, Count = 4, CountAtFull = 10, SizeScale = 1 },
	HeavySmoke = { Names = { "smoke 2" }, Count = 10, CountAtFull = 24, SizeScale = 1.6 },

	--[[ The wreck's one-off blast (`Extras.Explosion`), fired once at the car's centre the moment it
		goes, BEFORE the wreck's loops settle into a steady burn. Always at full strength (t = 1, so
		`Count` and `CountAtFull` are the same number). Several times the size of anything a hit throws,
		because this is the one moment in a run that should out-shout every other effect. ]]
	ExplodeFire = { Names = { "Fire3" }, Count = 30, CountAtFull = 30, SizeScale = 3 },
	ExplodeSmoke = { Names = { "smoke 2" }, Count = 26, CountAtFull = 26, SizeScale = 2.6 },
	ExplodeSparks = { Names = { "FadingFlare" }, Count = 120, CountAtFull = 120, SizeScale = 6, LightEmission = 1 },
}

--[[ `LightEmission` (optional, on a burst) — `ParticleEmitter.LightEmission`, the additive-glow blend
	(2026-10-02, the owner: "make all the vfx 100x cooler"). 1 makes a particle ADD light to what is
	behind it rather than paint over it, which is the difference between an orange speck and a hot
	spark against a grey road. Only on the sparks: on smoke it reads as glowing fog, which is wrong.
	Omitted = the artist's own value. ]]

--[[ How much of the car's velocity every new particle carries (`ParticleEmitter.VelocityInheritance`),
	bursts and loops alike. 1 = glued to the car; 0 = dropped on the road (the artist's default,
	authored for a still scene). Just under 1, so smoke and sparks trail back off the car a little
	rather than sitting on it like a sticker. ]]
CrashVfxConfig.Inherit = 0.85

--- Which bursts each kind of collision throws. `Heavy` is added on top once `HeavyShake` is reached.
CrashVfxConfig.OnHit = {
	Car = { "Sparks", "Puff" },
	Obstacle = { "Sparks", "Puff" },
	Wall = { "ScrapeSparks" },
	Heavy = { "HeavySmoke" },
}

--[[ Replace the old grey `Smoke` puff on a hit (`ObstacleController._emitHitSmoke`) with the bursts
	above. False plays both, which is the A/B for whether the new puff carries the hit on its own. ]]
CrashVfxConfig.ReplaceHitSmoke = true

-- === Damage the car carries ==================================================================
--[[ Health fractions (of `MaxHealth`, the HitBox's own attributes — the HUD bar reads the same two)
	at which the looping effects on the hood switch on. They only ever switch when the stage CHANGES,
	never re-asserted every frame, because `StealController` switches every emitter on the car off for
	a flight and back on after, and a per-frame write here would fight it. ]]
CrashVfxConfig.Damaged = 0.5
--[[ === UNDER THE TUTORIAL'S FLOOR — 2026-10-05 ===========================================
	WAS 0.25, which is exactly `TutorialConfig.Rig.Stage.HealthFloor` — and since the floor now holds
	for the whole tutorial run (`TutorialConfig.Unlosable`), a first-timer who clipped a few cars drove
	the rest of it ON FIRE, the "about to go" signal on a car that by design cannot go. Just under the
	floor, so a tutorial car at its floor smokes and never burns; everywhere else it is the same stage
	a few HP later. Keep it below that floor if either moves. ]]
CrashVfxConfig.Critical = 0.2
--[[ Each loop is a list of LAYERS, each with its own `SizeScale`, for the same reason the bursts got one
	each (`Bursts`, 2026-10-02): the pack's effects are authored at very different scales.

	=== FIRE2 OUT, FIRE3 IN — 2026-10-02 =====================================================
	WAS `Damaged = { BlackSmoke }`, `Critical = { BlackSmoke, Fire2 }`, everything at one
	`LoopSizeScale = 1.8`. In the side-by-side preview `fire` (Fire2) was a single orange dot and
	`BlackSmoke` a faint grey wisp — both lost on a moving car, so "critical" never read as on fire.
	`fire3` (Fire3) was the one fire in the pack that reads as a fire at a distance, so it is the hood
	fire now (and still the wreck's), and BlackSmoke is scaled up hard to make a visible trail.

	=== ON FIRE ALL OVER, NOT JUST THE HOOD — 2026-10-02 =====================================
	The owner: "make the car on fire from other places too". WAS every layer on one hood point. NOW a
	layer names the `Spots` it burns at (`At`; omitted = the hood alone, which is the old behaviour,
	so listing only "Hood" everywhere is the exact revert). The smoke stays a single hood trail — five
	trails merge into one grey wall behind the car and hide the fires they came from. The FIRE spreads,
	and it escalates with the stage: two spots when critical, all of them on the wreck. ]]
CrashVfxConfig.Loops = {
	Damaged = {
		{ Names = { "BlackSmoke" }, SizeScale = 4 },
	},
	Critical = {
		{ Names = { "BlackSmoke" }, SizeScale = 4 },
		{ Names = { "Fire3" }, SizeScale = 1, At = { "Hood", "Rear" }, Glow = true },
	},
}

--[[ The emission rate a looping layer is given when the artist's emitter has none (`Rate` 0 — authored
	to be fired with `Emit`, which some of the pack visibly is: it played as a single puff in the
	preview). Without this such a layer switches on and shows nothing at all, silently. Only applied
	where the authored rate is zero; an emitter with its own rate keeps it. ]]
CrashVfxConfig.LoopFallbackRate = 12

--[[ The points on the car a looping layer can burn at (`At` on a layer), in the car's own frame as
	fractions of its extents: `Forward` of the half-length toward the nose, `Up` of the half-height
	above the centre, `Right` of the half-width toward the right. Fractions rather than studs so one
	set fits every body from a hatchback to a truck. The sides are staggered (one ahead of centre, one
	behind) so from the chase camera the two side fires do not sit in one line and read as one.
	`Hood` was the only point until 2026-10-02 and keeps its old numbers. ]]
CrashVfxConfig.Spots = {
	Hood = { Forward = 0.55, Up = 0.45, Right = 0 },
	Rear = { Forward = -0.7, Up = 0.35, Right = 0 },
	Left = { Forward = 0.15, Up = 0.2, Right = -0.85 },
	Right = { Forward = -0.25, Up = 0.2, Right = 0.85 },
	Roof = { Forward = -0.1, Up = 0.9, Right = 0 },
}

-- === The wreck ===============================================================================
--[[ On the wrecked car, until the run tears it down. Replaces the old plain plume
	(`ObstacleController._onWrecked`) while `ReplaceWreckSmoke` is on. The fire is at every spot and a
	little smaller per spot than the single hood fire was (WAS 1.8 at the hood alone), since five of
	them together already cover the car — at 1.8 each they merge into one orange blob. ]]
CrashVfxConfig.Wreck = {
	{ Names = { "Fire3" }, SizeScale = 1.4, At = { "Hood", "Rear", "Left", "Right", "Roof" }, Glow = true },
	{ Names = { "BlackSmoke" }, SizeScale = 5 },
	{ Names = { "smoke 2" }, SizeScale = 1.6 },
}
CrashVfxConfig.ReplaceWreckSmoke = true

-- === The extras: light, debris, the blast =====================================================
--[[ "MAKE ALL THE VFX 100x COOLER" (the owner, 2026-10-02). The particles were already the artist's
	best; what a crash in this game lacked was everything AROUND the particles. Four additions, each
	one a thing particles alone cannot do:

	    Flash      a point light that pops at the contact point and dies in a fraction of a second —
	               a hit LIGHTS UP the car and the road for a frame, which no particle can do
	    Glow       a flickering orange light at every burning spot (`Glow = true` on a loop layer), so a
	               car on fire casts firelight on itself and the tarmac instead of wearing flat decals
	    Debris     shards of the car's own bodywork thrown off a real hit, falling with gravity
	    Explosion  the wreck stops being "the loops switch on" and becomes a blast: fireball, smoke
	               cloud, a shower of sparks, a big flash and a spray of shards, then the steady burn

	`Enabled = false` (or any one of the four) is the effects exactly as they were before this section:
	particles only. Each is its own flag because each is its own A/B. ]]
CrashVfxConfig.Extras = {
	Enabled = true,

	--[[ Brightness and range lerp from the gentlest hit to a `FullShake` one, like burst counts do.
		`Decay` is how long the light takes to fall to nothing: ~a quarter-second reads as a flash, past
		~0.5s it reads as a lamp someone switched on. Warm white, not orange — a flash is metal on
		metal, and orange is kept for fire so the two do not blur together. ]]
	Flash = {
		Enabled = true,
		Color = Color3.fromRGB(255, 214, 160),
		Brightness = 5,
		BrightnessAtFull = 14,
		Range = 12,
		RangeAtFull = 26,
		Decay = 0.25,
	},

	--[[ The firelight. `Flicker` is how far brightness swings either side of `Brightness` (0.35 = +-35%),
		`FlickerSpeed` how fast — off smooth noise, not random per frame, because per-frame random reads
		as a broken bulb strobing and noise reads as flame. One light per burning SPOT, so a wreck with
		five fires has five lights; `Range` is kept short so they light the car and the road just
		around it, and do not wash the whole street orange. ]]
	Glow = {
		Enabled = true,
		Color = Color3.fromRGB(255, 120, 40),
		Brightness = 2.5,
		Range = 12,
		Flicker = 0.35,
		FlickerSpeed = 9,
	},

	--[[ Bits of the car: small thin slabs in the colour and material of the car's largest visible part
		(meant to be the body; a car whose body is a textured mesh with a white base colour throws white
		bits, which is the known miss). Client-only and NON-COLLIDING: a shard that could collide could
		knock the player's own car, which is simulated on this client, and a crash effect must never be
		a crash cause. The cost of that is a shard that lands on the road goes through it, which is why
		`Life` is short and the last 40% of it is a fade.

		Only off a real hit (`MinShake` and up — a cone is 0.35, a barrier 1.2) and never off a wall
		scrape, which repeats for as long as you ride the rail. `Inherit` is the share of the car's
		velocity a shard keeps, as with particles: just under 1, so they spray out and fall back past
		the car rather than being left on the road behind it. Speeds are in studs/s. ]]
	Debris = {
		Enabled = true,
		MinShake = 0.8,
		Count = 3,
		CountAtFull = 7,
		SizeMin = 0.3,
		SizeMax = 0.9,
		Speed = 26,
		Up = 22,
		Inherit = 0.8,
		Spin = 18,
		Life = 1.4,
	},

	--[[ The wreck blast. `Bursts` name entries in `CrashVfxConfig.Bursts`; `Debris` is a shard count,
		thrown in every direction rather than away from one contact point. The flash is the hit flash's
		colour, far bigger and slower to fade (a blast is meant to be SEEN fading). ]]
	Explosion = {
		Enabled = true,
		Bursts = { "ExplodeFire", "ExplodeSmoke", "ExplodeSparks" },
		Debris = 14,
		FlashBrightness = 24,
		FlashRange = 45,
		FlashDecay = 0.7,
	},
}

return CrashVfxConfig
