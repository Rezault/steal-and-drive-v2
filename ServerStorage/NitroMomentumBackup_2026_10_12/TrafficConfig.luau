--[[
	TrafficConfig
	-------------
	The cars you drive past — and, once the steal lands, the cars you take. Everything
	designers tune for the traffic layer: how many cars are on the road, how fast they go,
	how they pick lanes, which tiers show up how far into a run, and what clipping one costs.

	Four things to know before editing:

	1. TRAFFIC IS A STREAM, NOT A LAYOUT. Obstacles are seeded per road tile because they're
	   static — the same tile always carries the same course (see ObstacleLayout). Traffic
	   MOVES, so a tile-anchored layout can't work: a car placed on a tile six tiles ahead
	   drives off it long before you reach it, and there's no spawn distance you could pick
	   that stays true a minute later. Instead TrafficController keeps a POPULATION alive in
	   a window around the driver — spawn ahead, cull behind, top up on a timer — which is
	   how endless runners have always done traffic. `PrimeCount` fills that window at the
	   start of a race so the road isn't empty for the first half minute.

	2. TRAFFIC IS SOLID TO YOUR CAR AND TO NOTHING ELSE. Obstacles are pure query volumes and
	   traffic began as one too, which meant you drove clean through every car you hit and only
	   a scripted shove told you it had happened. So a traffic car's `Hit` volume now COLLIDES,
	   in its own collision group paired with the player's car alone — see `Collision` below,
	   assigned by `Modules/CarCollision`. Traffic still ignores traffic, the road, the obstacle
	   course and every other player. The contact supplies the shove now; `Collision.ClipFeel`
	   is what the scripted impact path (`ObstacleController.applyImpact`) still adds on top, so
	   the yaw, shake and smoke stay consistent with every other hazard. Set
	   `Collision.Enabled = false` to go back to ghosting through, in which case `Clip` supplies
	   the whole shove again. What the car you hit does back is `Knock`.

	3. TRAFFIC CARS ARE NOT REAL CARS. They're stripped visual shells (body meshes welded to
	   one anchored root — no chassis, no suspension, no scripts, no seats), built once by
	   TrafficService and cloned per car. That's what makes a dozen of them affordable. A steal
	   doesn't turn one into a car: it takes the shell's MESHES and grafts them onto the rig the
	   player is already sitting in, which is why the car you drive away in is the car you landed
	   on (`Modules/CarBody`). The shell's `Hit` volume is what the landing tests against, and the
	   shell itself goes straight back into the traffic pool.

	4. SPEEDS FOLLOW THE PLAYER CAR. Each band is a fraction of DriveController's measured normal
	   cruise reference, so a car swap preserves the intended closing-speed hierarchy. Absolute
	   `Speed` values remain compatibility fallbacks for legacy overrides. Weather and headway scale
	   the resolved studs/s after the per-car fraction is chosen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ObstacleConfig = require(ReplicatedStorage.shared.Configs.ObstacleConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
-- For the per-car rarity overrides that used to be `TrafficConfig.RungOverrides` — see the note
-- where they are applied, at the bottom of the tier build.
local CarConfig = require(ReplicatedStorage.shared.Configs.CarConfig)

local TrafficConfig = {}

-- Master switch. Off = an empty road, exactly as it was before this layer existed.
TrafficConfig.Enabled = true

-- === Names ==================================================================
-- ReplicatedStorage folder TrafficService publishes the stripped body shells into, one
-- child per entry in `AllBodies`. Clients clone from here; nothing traffic-related ever
-- replicates during a race.
TrafficConfig.TemplateFolderName = "TrafficCars"
-- Client-only Workspace folder the live traffic lives in. Deliberately NOT inside the road
-- tiles (unlike obstacles): tiles are the recycling unit, and a car that has driven off the
-- tile it spawned on would be teleported by that tile's next recycle. Traffic keeps its own
-- position in the road frame instead and rides `RoadController:onWorldShift` through a rebase.
TrafficConfig.FolderName = "TrafficCars"

--[[ Which cars in `Workspace.CarSystem` a traffic shell is stripped from.

	DERIVED FROM THE TIERS, at the bottom of this file, rather than written out here. A body no tier
	can roll has no business being published — it would cost a shell's worth of replication to every
	client and never turn up on a road — and a second hand-maintained list beside the tier list is how
	a body ends up unpublished while a tier silently falls back to "any car in the roster"
	(`TrafficController._pickBody`).

	A tier is one car out of one world, so a world's roster is exactly its own ladder — eight bodies
	for world 1 — and `AllBodies` is the 29 across all four, which is what actually gets published
	(see the roster block at the bottom for why it has to be all of them). To change what drives
	past, edit `WorldConfig`. There is nothing else to update. ]]
TrafficConfig.Bodies = {} -- reassigned from `TiersByWorld` at the end of this file

--[[ PAINT LIVES IN `PaintConfig` AND `Modules/CarPaint`, not here any more.

	This used to be `BodyMeshMatch = "BODY"`, a name substring deciding which meshes took a tier's
	colour. It is gone for two reasons, both measured rather than argued:

	  • THE NAME MATCH WAS INCOMPLETE. The Charger paints `trim_01` and both `trim_chrome_*` in body
	    colour, and none of them carries "body" in its name, so a name-only repaint left three flecks
	    of the original livery on the car.
	  • THE COLOUR PROPERTY DID NOTHING ANYWAY. Every body panel on this roster is a MeshPart with a
	    `TextureID`, and a texture beats `Color` outright — so the whole repaint path was a silent
	    no-op on every car in the game, colour pool or not.

	`CarPaint` replaces both halves: it resolves the paintwork from name tokens AND the shell's own
	texture, and it clears that texture before writing the colour. Everything that used to read this
	field now asks it instead. ]]

--[[ Traffic shadows. 16 cars x ~24 meshes is the single biggest thing this layer costs to draw, so
	this is the first lever to pull if the road gets expensive on low-end devices; `MaxCars` is the
	other. (The pack bodies run 17-29 visible parts each against the Lambo redress's 52, so moving
	traffic onto the roster roughly halved what a full road costs to draw.)

	THE 2026-07-29 NOTE HERE WAS WRONG, and it is worth recording how rather than just deleting it.
	It claimed this bought nothing because no body mesh in the place cast a shadow to begin with.
	Parsing the saved place on 2026-09-12 said otherwise: `Workspace.OrderedCarsByWorld`, which is
	what `TrafficService._buildShell` builds the published shells from, had `CastShadow` true on
	810 of its 810 MeshParts. Every traffic car on the road was casting one. The measurement was
	presumably taken against a different folder, or before the roster moved into that one.

	WHICH MADE IT THE WORST KIND OF CASTER, not merely one more. A full road is 16 cars of ~25
	meshes, and all of them MOVE — a static caster's contribution to the shadow map can be reused
	between frames, a moving one dirties its region every frame. ~300 moving casters is
	disproportionately more expensive than the same count parked.

	FALSE, THEREFORE, AND FALSE AS A STANDING GUARANTEE rather than as a one-off cleanup. A place-wide
	`CastShadow` pass on 2026-09-12 already turned these off at the source (810 down to 21), so
	flipping this today buys little on its own. It is set false so that the road cannot start casting
	300 moving shadows again as a SIDE EFFECT of an art change — the roster is shared with the dress a
	steal grafts onto the player's car, and somebody enabling contact shadows on the bodies for that
	reason should not silently be enabling them for the whole road too.

	Turning traffic shadows back on is therefore a deliberate edit to this line, with a frame budget
	in hand — not something an art pass can do by accident.

	Applied on the CLIENT'S clone rather than to the published shell — see
	`TrafficController._buildRecord`, and `TrafficService._buildShell` for why that distinction now
	matters at all. ]]
TrafficConfig.CastShadows = false

-- === Lanes ==================================================================
-- The SAME lane grid the obstacle courses use, on purpose: traffic and obstacles share the
-- road, and a car sitting between two obstacle lanes would block gaps the course authored as
-- daylight. Re-space `ObstacleConfig.Lanes` and both layers move together.
TrafficConfig.Lanes = ObstacleConfig.Lanes

-- Cross-axis studs two cars must be apart before they count as "different lanes". Lanes are
-- 15 apart and a car is ~10.4 wide, so 12 lets neighbouring lanes ignore each other while a
-- car halfway through a lane change still blocks both.
TrafficConfig.SideClearance = 12

-- === Population / streaming =================================================
-- Target number of useful cars AHEAD of the player. Recently passed cars get the small temporary
-- allowance below until they cross DespawnBehind; they no longer consume the forward-road budget.
TrafficConfig.MaxCars = 16

-- Extra live shells permitted behind the player while replacements are already appearing ahead.
-- This bounds the fix: normal traffic can briefly reach 19 models, never grow without limit.
TrafficConfig.TrailingAllowance = 3

--[[ Far traffic does not need a full model transform every render frame. Simulation still advances
	at Heartbeat rate, so lane choice, spawning, despawning and avoidance are unchanged; only the
	visual pose is decimated until a car is close enough to interact with. At 30 fps or below the
	interval naturally resolves to approximately every frame. ]]
TrafficConfig.VisualUpdate = {
	FullRateDistance = 420,
	FarInterval = 1 / 30,
}

-- Where LIVE replacement traffic appears, in studs ahead of the driver. This is deliberately
-- beyond the immediate gap-reading window: even a delayed member of a queued formation is
-- clamped back to this minimum when it actually spawns, so it cannot materialise near the car.
-- Race-start priming uses PrimeBand instead, since those cars exist before control is handed over.
TrafficConfig.SpawnAheadMin = 600
TrafficConfig.SpawnAheadMax = 1000

-- Seconds between spawn attempts once the road is up to population. An attempt that can't
-- find a clear lane is simply skipped and retried on the next one.
TrafficConfig.SpawnInterval = { 0.9, 1.7 }

-- If the road falls this many cars below its forward target, shorten any scheduled breathing room
-- and refill at this cadence. Failed clearance checks retry separately rather than consuming a
-- whole ordinary spawn interval.
TrafficConfig.Refill = {
	UrgentDeficit = 3,
	UrgentInterval = 0.35,
	FailedRetry = 0.25,
}

--[[ Density waves. Ordinary random spawns still make up most of the road; a successful formation
	roll books two or three cars at short intervals, then enforces breathing room. Slots are relative
	to a randomly selected centre lane and formation anchor. Every authored slice occupies at most
	three of the five lanes, so a formation always leaves a readable escape route. ]]
TrafficConfig.DensityWaves = {
	Enabled = true,
	FormationChance = 0.34,
	PackInterval = { 0.3, 0.55 },
	BreathingRoom = { 2.2, 3.4 },
	Formations = {
		{ Name = "TwoCarStagger", Slots = { { Along = 0, Lane = -1 }, { Along = 42, Lane = 1 } } },
		{ Name = "SideBySide", Slots = { { Along = 0, Lane = -1 }, { Along = 0, Lane = 1 } } },
		{
			Name = "ThreeCarOpening",
			Slots = { { Along = 0, Lane = -2 }, { Along = 18, Lane = 0 }, { Along = 0, Lane = 2 } },
		},
		{
			Name = "SlowThenFast",
			Slots = { { Along = 76, Lane = 0, PaceFraction = 0.55 }, { Along = 0, Lane = 0, PaceFraction = 0.82 } },
		},
		{ Name = "ThreadingOffset", Slots = { { Along = 0, Lane = -1 }, { Along = 14, Lane = 1 } } },
	},
}

-- Optional, disabled telemetry. Traffic writes target/closing speeds as model attributes at this
-- cadence; no prints are emitted and ordinary builds pay only the flag check.
TrafficConfig.Debug = {
	Enabled = false,
	SampleInterval = 0.15,
}

--[[ Cars placed instantly at race start, spread across `PrimeBand`, so the road is already
	busy on the first corner instead of filling up over the first half-minute.

	Without this the population takes MaxCars x SpawnInterval (~26s at the midpoint) to build — a
	large part of a run
	(GDD: 60-120s target) spent on an empty road. ]]
TrafficConfig.PrimeCount = 14

--[[ How many of the prime's cars may be built in one frame.

	THE PRIME USED TO BE A `for` LOOP, so every primed car landed on the single frame the road and the car
	first resolved — which is the RaceStart frame, the one `RaceConfig.TileBuildBudget` and
	`ObstacleConfig.BuildBudget` both exist to keep clear. A prime car that misses the pool is
	`_buildRecord`: a `template:Clone()` of a ~25-mesh shell plus a `CarPaint.parts` walk of ~30
	parts. Ten of those is ~250 instances cloned and ~300 parts walked, at the worst possible moment.

	TWO A FRAME PUTS THE FULL ROAD DOWN IN FIVE FRAMES, which is well under a tenth of a second and
	entirely invisible: `PrimeBand` starts 140 studs ahead of the car, so none of these cars is
	near enough to be watched arriving, and the run has not started moving yet anyway.

	IT ONLY COSTS ANYTHING ON THE FIRST RACE. `_release` pools shells by body name and the pool
	survives until teardown, so a second run through the same world primes out of the pool and never
	reaches `_buildRecord` at all. ]]
TrafficConfig.PrimeBudget = 2

--[[ How many pooled shells one frame may destroy when a race ends (`TrafficController._stepDrain`).

	Counted in MODELS, not instances, because a traffic shell is ~25 instances and is the natural
	indivisible unit — unlike a road tile, which is ~1,000 and has to be sliced from the inside.
	Four a frame clears a full end-of-race pool (up to 33 shells plus the twelve on the road) in
	about a dozen frames, none of which anyone can see: everything in that queue is already out of
	the scene before the drain touches it. ]]
TrafficConfig.DrainBudget = 4
TrafficConfig.PrimeBand = { 140, 1500 }

-- Studs behind / ahead of the driver at which a car is recycled back into the pool. Behind is
-- tight (the car is 22 long, so this is comfortably off-screen); ahead is generous so a
-- braking player doesn't lose the cars they were about to reach.
TrafficConfig.DespawnBehind = 120
TrafficConfig.DespawnAhead = 1600

-- Studs of clear road a spawn needs, in its lane, front and back, from any other traffic car.
TrafficConfig.SpawnGap = 70

--[[ Studs of road recycled either side of a REVIVE's landing point, across every lane
	(`TrafficController._onRevived`). A revived car is set down by the server, which cannot see this
	layer at all — so if traffic does not get out of the way, nothing does, and the car can land on
	top of one and sit there with its wheels spinning.

	The same 70 as `SpawnGap` above and for the same reason: it is the distance at which a car ahead
	stops being something you are already in and starts being something you are driving towards.
	Cleared behind as well as in front because the car comes back AT REST, so a car arriving from
	behind at full speed is as unfair as one underneath. ]]
TrafficConfig.ReviveClearStuds = 70
-- The same idea for a car moving over, and deliberately tighter: a spawn wants elbow room, but
-- a lane change only needs the space beside it to be empty. A car is 22 long, so 46 is roughly
-- "nothing overlapping me plus half a car of margin".
TrafficConfig.LaneChangeGap = 46

-- === Tiers ==================================================================
--[[ The GDD's distance ramp (§3.3), keyed to the road tile the driver is on — exactly the
	index the obstacle difficulty ramp already uses, so "how far in am I" means one thing.

	A tier joins the pool at `FromTile` and stays in it (the bottom car still turns up late in
	a run — trading *up* is the fantasy, so there has to be junk around to trade up from).
	`Weight` is the relative roll among whatever is unlocked, which is what makes the top car
	rare: once everything is in, it's 1 in 43.

	`SpeedFraction` is a share of this player's normal cruise. `Speed` is the legacy absolute
	fallback. `LaneChange` is the seconds between RECONSIDERATIONS, most of which come to nothing:
	`RoutineLaneChangeChance` declines the majority of them, and the controller suppresses the rest
	inside `PlayerLaneChangeZone` so the immediate gap stays readable.

	=== ONE TIER IS ONE CAR, AND THE WORLD DECIDES WHICH ======================================

	The tier ladder is no longer written here. `WorldConfig` holds four worlds of cars, each list
	ordered worst-to-best exactly as the art models are parked in `Workspace.OrderedCarsByWorld`,
	and the ACTIVE world's list becomes this table: one tier per car, in that order, holding that
	one body. World 1 is eight cars, so a run has eight rungs rather than five bands of nine.

	WHY THE SPLIT MOVED. The old five tiers each pooled nine or ten pack bodies (`Sedan12`,
	`Sports16`, …) sorted by what they looked like, because a tier had to be a *shape* when nothing
	distinguished one boxy saloon from another. That roster has since been renamed car by car and
	re-ordered by hand into worlds, and an authored order is strictly better information than a
	shape heuristic — so the ladder is now that order, and every car is priced, sped and gated by
	exactly where it sits in it. (It also fixes a live break: every pack name this table used to
	list stopped resolving when the roster was renamed, so `TrafficService._findSource` failed on
	all 43 and the road ran empty.)

	`Bands` below is what survives of the old five tiers: the tuned SHAPE of a run, resampled onto
	however many cars the live world has (`WorldConfig.resample`). The ends are exact — the bottom
	car of any world is still 24-30 studs/s from tile 0, the top still 39-44 from tile 10 — and the
	rungs between are interpolated, so re-tuning is still five numbers and not twenty-nine.

	TO MOVE A CAR, EDIT `WorldConfig`. To re-tune the ramp, edit `Bands`. To give ONE car a number
	the curve doesn't give it, edit that car's `Traffic` field in `CarConfig` — that is the escape
	hatch, and it is deliberate that it is the third thing you reach for and not the first.

	=== A TIER NO LONGER OWNS A COLOUR =========================================================

	`Colors` used to be a tier's paint pool, and it was nil on every tier — a colour band only ever
	existed because every tier drove the same Lambo and paint was the sole thing telling a beater from
	a supercar. One car per tier made the BODY the tell, which reads at chase-camera distance in a way
	a colour band never did, so the pools were switched off.

	They have not come back. What has arrived instead is `PaintConfig`, and the difference is the one
	that matters here: PAINT IS PER CAR AND PER SPAWN, NOT PER TIER. A colour says nothing about how
	fast the car is or how far into the run it appears — two Chargers on the same stretch of road can
	be different colours, and both are the same rung. That keeps the ladder legible (shape is still
	the tell) while stopping a lane of traffic looking like eight copies of eight cars.

	`TrafficController._spawn` rolls one palette index per car out of `PaintConfig`, and that index is
	what a steal carries onto the player's bodywork and a bank writes into the save file. Nothing in
	this file is involved. ]]
--[[ The five hand-tuned bands the ramp was built out of, bottom to top. These are the numbers to
	edit; the table below turns them into one rung per car in the live world.

	`Name` is kept for the shape each band describes, and is not what a tier is called any more — a
	tier is called after the car in it, because there is exactly one. ]]
--[[ === RARITY WORDS, NOT CAR WORDS — 2026-10-08 ===
	WAS: a car's rarity word was its band's `Name` — BEATER / SEDAN / COUPE / SPORTS / SUPERCAR. But the
	bands are RESAMPLED PER WORLD (below), so every world's top car was a "Supercar" and its bottom car a
	"Beater": world 1's BMW M5 (and its Mustang) read SUPERCAR, and world 5's DeLorean BEATER. Aleafo:
	"its calling a bmw m5 a supercar". The word described a kind of car; what the band actually measures
	is how rare the car is IN ITS WORLD. IS: each band carries a `RarityName` — COMMON / UNCOMMON / RARE
	/ EPIC / LEGENDARY — which is true of any car on any ladder, and is what the colours (grey to gold,
	`Modules/CarRarity`) already said. Every screen, the road banner and the discovery card read the
	word through `CarRarity`, so this one switch moves them all. `RarityWords = false`: the old car
	words, exactly. ]]
TrafficConfig.RarityWords = true

TrafficConfig.Bands = {
	{
		Name = "Beater",
		RarityName = "Common",
		FromTile = 0,
		Weight = 10,
		SpeedFraction = { 0.45, 0.60 },
		Speed = { 35, 47 },
		LaneChange = { 18, 30 },
	},
	{
		Name = "Sedan",
		RarityName = "Uncommon",
		FromTile = 1,
		Weight = 8,
		SpeedFraction = { 0.58, 0.72 },
		Speed = { 45, 56 },
		LaneChange = { 16, 27 },
	},
	{
		Name = "Coupe",
		RarityName = "Rare",
		FromTile = 3,
		Weight = 5,
		SpeedFraction = { 0.70, 0.84 },
		Speed = { 55, 66 },
		LaneChange = { 14, 24 },
	},
	{
		Name = "Sports",
		RarityName = "Epic",
		FromTile = 6,
		Weight = 3,
		SpeedFraction = { 0.82, 0.90 },
		Speed = { 64, 70 },
		LaneChange = { 12, 21 },
	},
	{
		Name = "Supercar",
		RarityName = "Legendary",
		FromTile = 10,
		Weight = 1,
		SpeedFraction = { 0.88, 0.94 },
		Speed = { 69, 73 },
		LaneChange = { 10, 18 },
	},
}

-- Used only until DriveController has resolved a car. The live spawn path normally receives the
-- per-car cruise, but failing to this value is safer than producing nil or stationary traffic.
TrafficConfig.FallbackPlayerCruise = 55

--[[ THE PER-CAR ESCAPE HATCH MOVED TO `CarConfig`. It used to be `TrafficConfig.RungOverrides`, a
	second table keyed by body name right here.

	It is now the `Traffic` field on a car's row, for one reason: how often a car turns up and how
	fast it drives are the same design conversation, and they were in two files. Deciding the
	Mustang should be rare AND a handful meant editing this table and a place-file attribute.

	Everything about how it behaves is unchanged — any field in it replaces the resampled one for
	that car alone — including that it should stay mostly empty. Reaching for it before re-tuning
	`Bands` is still how a ladder stops being a ladder. ]]

--[[ How much of a rung's traffic goes to its VARIANTS rather than to its ladder car — the extra
	bodies `WorldConfig.Variants` puts on a rung (that file's note 8).

	COLLECTIVELY, whatever the number of them: a rung with one variant shows it a third of the time
	at 1/3, and a rung with two shows a sixth each. That is what makes this one number rather than a
	table — a rung is a VALUE, the cars on it are interchangeable at that value, and "how often is
	the road showing me the alternate shape" is one design question with one answer.

	THE ARITHMETIC IS EXACT for any share written as 1/n. The ladder car's weight is
	`variants x (1 - share) / share`, which at 1/3 with one variant is 2 — so two rolls of the
	Supra to one of the R34, exactly a third, with no rounding anywhere. Write 0.3 instead and it
	rounds to the same 2; write 1/4 and it is 3 to 1. Prefer the fractions.

	A third is high on purpose. The complaint this whole mechanism answers is "I see many of the
	same car", and a variant that turns up one time in ten does not answer it — it is a rare sight,
	which is a different and much smaller feature. Turn it DOWN, not up, if the hero liveries start
	feeling ordinary. ]]
TrafficConfig.VariantShare = 1 / 3

--[[ The fewest rungs a spawn ever rolls between, however early in the run it is.

	THE FIRST TILE OF EVERY RUN USED TO BE A SINGLE CAR. A rung joins the pool at its `FromTile` and
	only the bottom one is in at tile 0, so the opening stretch of every world was one body over and
	over — measured on world 1: 100% Civic until tile 1, where three rungs open at once. That is the
	single strongest cause of "I keep seeing the same car" and it lands on the part of a run every
	player sees every time they press play.

	IT CANNOT LEAK A GOOD CAR EARLY, which is the only thing a distance ramp is actually for. It
	opens the BOTTOM `MinChoices` rungs — the first N of the ladder, never a random N — so world 1
	now opens on Civic / Golf GTI / Camaro instead of eight Civics, and both of the cars it lets in
	were already unlocking one tile later anyway. Nothing above rung 3 moves, and the top of the
	ladder is untouched.

	Set to 1 to go back to the pure `FromTile` gate. ]]
TrafficConfig.MinChoices = 3

--[[ One entry per car, in ladder order, FOR EVERY WORLD — `TiersByWorld[2]` is world 2's ladder.
	`Tier` is the GLOBAL rung (world 2's first car is tier 9 — `WorldConfig` note 3), `Rung` is the
	position within its own world, and `Bodies` is the single car, kept as an array so every
	consumer of a tier is unchanged.

	EVERY WORLD IS BUILT, not just the one the config calls default, because which world a car
	spawns for is now a question about a PLAYER (`WorldConfig.WorldAttribute`) and this table is
	loaded once per VM. Building all four costs a few dozen table entries at load; deriving one on
	demand would cost a resample per race. ]]
TrafficConfig.TiersByWorld = {}
do
	local bands = TrafficConfig.Bands

	-- One authored number per band, in band order — the curve `WorldConfig.resample` wants. The
	-- bands are the tuned shape of a run and are shared by every world; only the number of rungs
	-- they are resampled onto differs.
	local function column(field: string, part: number?): { number }
		local points = table.create(#bands)
		for index, band in bands do
			local value = band[field]
			points[index] = if part then value[part] else value
		end
		return points
	end

	local function roundTo(value: number, step: number): number
		return math.round(value / step) * step
	end

	for world in WorldConfig.Worlds do
		local cars = WorldConfig.carsFor(world)
		local count = #cars
		local firstTier = WorldConfig.firstTierFor(world)

		local fromTile = WorldConfig.resample(column("FromTile"), count)
		local weight = WorldConfig.resample(column("Weight"), count)
		local speedMin = WorldConfig.resample(column("Speed", 1), count)
		local speedMax = WorldConfig.resample(column("Speed", 2), count)
		local speedFractionMin = WorldConfig.resample(column("SpeedFraction", 1), count)
		local speedFractionMax = WorldConfig.resample(column("SpeedFraction", 2), count)
		local laneMin = WorldConfig.resample(column("LaneChange", 1), count)
		local laneMax = WorldConfig.resample(column("LaneChange", 2), count)

		local tiers = {}
		local unlocked = 0
		for rung, body in cars do
			--[[ Clamped non-decreasing. Two adjacent rungs can resample to 1.29 and 0.57 tiles and
				round the wrong way round, which would put the better car on the road first — a bug
				that would only ever show up as "why did I see that early?". ]]
			local tile = math.max(unlocked, math.round(fromTile[rung]))
			unlocked = tile

			--[[ The band this rung sits nearest, as an index and as its word. Nothing in the
				simulation reads it — it exists because a tier is called after its car now, and the
				shop still wants a RARITY to print on a listing ("Sports") rather than a model name
				("Mustang"). Nearest rather than interpolated for the obvious reason: there is no
				half-way between two words. ]]
			local band = math.clamp(math.floor((rung - 1) * #bands / math.max(1, count)) + 1, 1, #bands)

			local entry = {
				Tier = firstTier + rung - 1,
				Name = body,
				Rung = rung,
				World = world,
				Band = band,
				Rarity = if TrafficConfig.RarityWords then bands[band].RarityName or bands[band].Name else bands[band].Name,
				FromTile = tile,
				-- Floored at 1: a weight of 0 is a car that exists on the ladder and never spawns.
				Weight = math.max(1, math.round(weight[rung])),
				Speed = { math.round(speedMin[rung]), math.round(speedMax[rung]) },
				SpeedFraction = { roundTo(speedFractionMin[rung], 0.01), roundTo(speedFractionMax[rung], 0.01) },
				-- Half-seconds, because whole ones collapse three adjacent rungs onto the same value.
				LaneChange = { roundTo(laneMin[rung], 0.5), roundTo(laneMax[rung], 0.5) },
				--[[ Every car that wears this rung: the ladder car first, then whatever
					`WorldConfig.Variants` hung on it. `Bodies` has been an array since the day a tier
					pooled nine pack bodies; this is the first time since worlds landed that it holds
					more than one again, and every consumer of it was already written for the plural.

					THE LIST IS UNIQUE AND HAS TO STAY THAT WAY. Repeating a name would have been the
					cheaper way to weight it — it is exactly the knob `PaintConfig.Pools` documents —
					but four things walk `tier.Bodies` to build a ROSTER and only three of them dedupe:
					`UIController/Pages/Market`'s shelf pool does not, so a repeated name would put the
					same car on the shelf twice. `BodyWeights` below cannot do that to anybody. ]]
				Bodies = WorldConfig.bodiesOfRung(world, rung),
			}

			--[[ How often each of `Bodies` is rolled, parallel to it and read by
				`TrafficController._pickBody`. Nil for a rung with no variants, because a one-entry
				list needs no weights and a nil is one fewer table per rung. ]]
			if #entry.Bodies > 1 then
				local variants = #entry.Bodies - 1
				local share = math.clamp(TrafficConfig.VariantShare, 0.01, 1)
				local weights = table.create(#entry.Bodies, 1)
				-- Floored at 1: a share of 1 means "only ever the variants", which is not a thing
				-- this table is allowed to say — the ladder car is what the rung is named after.
				weights[1] = math.max(1, math.round(variants * (1 - share) / share))
				entry.BodyWeights = weights
			end

			-- The per-car escape hatch, now `CarConfig.Cars[body].Traffic` — see the note above the
			-- `Bands` table. Applied last so it beats everything the curve just decided.
			local overrides = CarConfig.trafficOverridesFor(body)
			for field, value in overrides do
				entry[field] = value
			end
			-- Existing per-car absolute speed overrides remain authoritative. New content should prefer
			-- SpeedFraction, but an old `Speed` must not silently lose its identity to the band curve.
			if overrides.Speed ~= nil and overrides.SpeedFraction == nil then
				entry.SpeedFraction = nil
			end

			tiers[rung] = entry
		end

		TrafficConfig.TiersByWorld[world] = tiers
	end
end

--- The ladder a given player's road rolls its traffic off. Falls back to the default world's for
--- an unresolvable index, same as everything else that takes one.
function TrafficConfig.tiersFor(world: unknown)
	return TrafficConfig.TiersByWorld[WorldConfig.resolve(world)]
end

-- The default world's ladder. Anything holding a player should call `tiersFor` instead.
TrafficConfig.Tiers = TrafficConfig.TiersByWorld[WorldConfig.ActiveIndex]

--[[ === THE ODDS ===============================================================================

	How often a rung is rolled, and what that comes to as a chance per car. Two functions, because
	two things ask: `TrafficController._pickTier` rolls a spawn off `rungWeight`, and the world-select
	card prints `chancesFor` under each world. They share the weight so the number on the card is
	the roll and cannot drift from it.

	LUCK IS IN IT. `luck` is `UpgradeConfig.luckFactor` for the player (1 for nobody), and it tilts
	the ladder toward its top: rung r of n is weighted by `luck ^ ((r - 1) / (n - 1))`, so the bottom
	car keeps its weight and the top car's is multiplied by the whole factor. It is measured against
	the WHOLE ladder and not whatever part of it is unlocked; `_pickTier`'s own note has the argument.

	`chancesFor` IS THE WHOLE ROAD, i.e. the odds once every rung is unlocked. A rung joins the pool
	at its `FromTile`, so the top car of a world cannot turn up at all in the first few hundred studs
	of a run; the card is answering "what can this road give me", and that answer is the road you
	get once you have driven far enough to see all of it. Variants split their rung by
	`BodyWeights`, which is the split `_pickBody` rolls. ]]
function TrafficConfig.rungWeight(tier, luck: number?, rungs: number, tileIndex: number?): number
	local weight = math.max(tonumber(tier.Weight) or 0, 0)
	if type(tileIndex) == "number" and type(tier.StartWeight) == "number" then
		local progress = math.clamp(tileIndex / TrafficConfig.OddsRampTiles, 0, 1)
		weight = tier.StartWeight + (weight - tier.StartWeight) * progress
	end
	local factor = luck or 1
	if factor > 1 then
		weight *= factor ^ (((tier.Rung or 1) - 1) / math.max(rungs - 1, 1))
	end
	return weight
end

--[[ === THE ROLL, SHARED — 2026-09-28 ========================================================

	`TrafficController._pickTier` / `_pickBody`'s arithmetic, lifted here so the SERVER can roll
	traffic too (`EncounterService`, `EncounterConfig`'s header for why it must). One copy on both
	sides, so a car the server issues is drawn from exactly the odds the client used to roll itself,
	and the world-select card's printed chances stay true either way. Pure: the caller's `Random`, and
	nothing else, decides the outcome. ]]

--[[ A rung for a spawn at `tileIndex`: its index into `tiers`, and the rung. Every rung up to
	`MinChoices` is always in the pool, the rest join at their `FromTile`; each is weighted by
	`rungWeight`, luck measured against the WHOLE ladder (`_pickTier`'s note has the argument). ]]
function TrafficConfig.rollRung(rng: Random, tiers, tileIndex: number, luck: number?): (number, any)
	local floor = math.max(1, TrafficConfig.MinChoices or 1)
	local pool, weights, total = {}, {}, 0
	for index, tier in tiers do
		if index <= floor or tileIndex >= tier.FromTile then
			local weight = TrafficConfig.rungWeight(tier, luck or 1, #tiers, tileIndex)
			table.insert(pool, index)
			table.insert(weights, weight)
			total += weight
		end
	end
	if #pool == 0 or total <= 0 then
		return 1, tiers[1]
	end
	local roll = rng:NextNumber() * total
	for slot, index in pool do
		roll -= weights[slot]
		if roll <= 0 then
			return index, tiers[index]
		end
	end
	local last = pool[#pool]
	return last, tiers[last]
end

--[[ A body NAME for a rung, by its `BodyWeights` (or evenly). `available` narrows it to names the
	caller can actually draw, when it knows; nil takes the rung's list as it stands. nil back only for
	a rung with no usable body at all. ]]
function TrafficConfig.rollBody(rng: Random, tier, available: { [string]: boolean }?): string?
	local names, weights, total = {}, {}, 0
	for slot, name in tier.Bodies or {} do
		if available == nil or available[name] then
			local weight = math.max(0, if tier.BodyWeights then tier.BodyWeights[slot] or 1 else 1)
			table.insert(names, name)
			table.insert(weights, weight)
			total += weight
		end
	end
	if #names == 0 then
		return nil
	end
	if total <= 0 then
		return names[rng:NextInteger(1, #names)]
	end
	local roll = rng:NextNumber() * total
	for slot, name in names do
		roll -= weights[slot]
		if roll <= 0 then
			return name
		end
	end
	return names[#names]
end

export type Chance = {
	Body: string,
	--- 0..1, and every entry for one world sums to 1.
	Chance: number,
	Tier: number,
	--- Index into `Bands`, i.e. the rarity `Modules/CarRarity` colours.
	Band: number,
}

--- Every car world `world`'s road can show, ladder order, each with its chance of being the car
--- any one spawn rolls. Variants follow their rung's ladder car.
function TrafficConfig.chancesFor(world: unknown, luck: number?): { Chance }
	local tiers = TrafficConfig.tiersFor(world) or {}
	local weights, total = table.create(#tiers), 0
	for index, tier in tiers do
		weights[index] = TrafficConfig.rungWeight(tier, luck, #tiers)
		total += weights[index]
	end

	local out = {}
	for index, tier in tiers do
		--- An all-zero ladder is a hand edit rather than a road; spread it evenly rather than divide
		--- by zero, the same fallback `_pickTier` takes.
		local share = if total > 0 then weights[index] / total else 1 / #tiers
		local bodies = tier.Bodies or { tier.Name }
		local split = tier.BodyWeights
		local splitTotal = 0
		for slot in bodies do
			splitTotal += math.max(if split then split[slot] or 1 else 1, 0)
		end
		for slot, body in bodies do
			local part = math.max(if split then split[slot] or 1 else 1, 0)
			table.insert(out, {
				Body = body,
				Chance = share * (if splitTotal > 0 then part / splitTotal else 1 / #bodies),
				Tier = tier.Tier,
				Band = tier.Band or 1,
			})
		end
	end
	return out
end

-- === Driving ================================================================
-- Cross-axis studs/s a lane change is made at. A 15-stud lane takes ~1.4s at 11, brisk enough
-- to read as deliberate and slow enough that you can react to it. It also sets the WORST case
-- the lookahead below has to cover: crossing all four lanes takes 60 / this = ~5.5s.
TrafficConfig.LaneChangeSpeed = 11

--[[ How many of a car's lane decisions actually turn into a lane change.

	The tier's `LaneChange` range is how often a car THINKS about moving over, and until now every
	one of those ticks produced a move. Sixteen cars alive at a mean of twenty seconds between
	reconsiderations is a lane change somewhere on the road about once a second, which is why it
	read as restless rather than as traffic, and why a playtester's word for it was cars changing
	lane at the last second in front of them.

	This is the coin flip that turns most of those reconsiderations down. At 0.15 a car moves over
	roughly once every two minutes of its own clock and it only lives for about half a minute inside
	the player's window, so MOST CARS NEVER CHANGE LANE AT ALL and the road offers one routine move
	every several seconds, nearly all of it far enough ahead that the warning billboard has not even
	drawn yet (`LaneChangeWarning.MaxDistance`). A lane change becomes an event you notice instead
	of the background.

	ONE NUMBER RATHER THAN FIVE LONGER `LaneChange` RANGES, because those ranges carry the tier
	ORDER as well as the rate: a supercar reconsiders twice as often as a beater and so still moves
	about twice as much. Scaling all of them by the same factor keeps that shape for free, and
	leaves one value to turn if the road ends up too static.

	FORCED AVOIDANCE IS NOT ROLLED. A car steering out of a barrier's lane is not expressing
	personality, and `_avoid` never reaches this. ]]

TrafficConfig.RoutineLaneChangeChance = 0.15

-- Routine personality lane changes are heavily suppressed inside the player's decision window.
-- Obstacle avoidance is exempt: a car may still leave a blocked lane rather than drive through a
-- wall. `Chance = 0` makes that promise absolute for routine changes: once a car enters this band,
-- the line the player read is the line it keeps.
TrafficConfig.PlayerLaneChangeZone = {
	Behind = 45,
	Ahead = 220,
	Chance = 0,
}

--[[ Routine lane changes announce their committed direction before the car starts crossing.

	`AssetName` is an artist-authored MeshPart in ReplicatedStorage. One clone is kept on each pooled
	traffic shell, moved above the car, and pointed across the road toward its intended lane. The mesh
	The current mesh's arrow tip is authored along local +X, so `MeshRotationDeg` turns that axis onto
	the requested road direction. Keep this correction centralized if the art is replaced later.
	`MaxDistance` is enforced manually
	because world-space parts do not have BillboardGui distance culling.

	Forced obstacle avoidance remains immediate: telegraphing a move after a car has already reached
	a wall would be more misleading than helpful. ]]
TrafficConfig.LaneChangeWarning = {
	AssetName = "IndicateArrow",
	Seconds = 1.15,
	FlashHz = 4,
	Height = 10.8,
	MaxDistance = 260,
	MeshRotationDeg = Vector3.new(0, -90, 0),
}

--[[ Turn signals. For as long as the arrow above is up (the warning beat, then the crossing), the
	car's own lamps on the side it is moving towards flash amber. `Modules/CarBlinkers` picks the
	lamps from each body's mesh names and geometry, and explains the choice.

	EVERY BODY BLINKS AT THE REAR, which is the end the chase camera sees. That took two fixes to the
	roster on 2026-09-17 on top of this module: the BRZ's tail lamps were named as bodywork
	(`ApplyPaintRenames`), and the Camaro's and Challenger's were single meshes spanning the car, now
	split in two (`SplitLampMeshes`). Six still blink at the rear only, because their headlamps are
	one mesh or none (`Golf GTI`, `Camaro`, `Model 3`, `Mustang`, `MK5 Supra`, `M4`).

	`Hz` is full on/off cycles a second. A real indicator runs at about 1.5, but the warning beat is
	only `LaneChangeWarning.Seconds` long, so this runs quicker to fit a couple of flashes in before
	the car moves. `Grow` is how much larger than its lamp a lit twin is drawn, as a fraction, and
	`Proud` is how far, in studs, it is pushed out towards its end of the car: together they keep
	the twin in front of the lamp instead of z-fighting it, and `Proud` is the one that matters on a
	thin lamp. `CoverEnd` is how far towards an end of the car, as a fraction of half its length, a
	`glass` part has to sit to count as a lamp cover rather than a window.

	The stop lamps are the same twin of the same lamps in red, and live in `BrakeLightConfig`; its
	`Proud` must stay UNDER this one so a flashing indicator shows through a lit brake light, and
	its `CoverEnd` must match this one. ]]
TrafficConfig.Blinkers = {
	Enabled = true,
	Hz = 2.5,
	Color = Color3.fromRGB(255, 150, 20),
	Grow = 0.04,
	Proud = 0.05,
	CoverEnd = 0.65,
}

--[[ How far ahead a car looks for obstacles in its own lane, in studs.

	This exists because traffic and obstacles share a road neither layer knows about: without it
	a traffic car drives serenely through a concrete barrier, which reads as broken instantly.

	Sized from the WORST case, not the typical one. Traffic closes on a static obstacle at its own
	speed, and the wall courses (`gate`, `chicane`, `heavyGate`, both `wallGap`s) block four of
	the five lanes — so a car on the wrong side has to cross the whole road, ~5.5s at
	`LaneChangeSpeed`, which is 150 studs for a Tier 1 and 240 for a Tier 5. 200 covers everything
	up to Tier 4 outright and leaves the fastest cars needing only to start moving a beat early,
	which the 0.3s check interval gives them. At 130 (the first pass) traffic spent ~1% of its
	life inside an obstacle; see TrafficController._avoid for the other half of that fix. ]]
TrafficConfig.AvoidLookahead = 200
-- Seconds between "is my lane still clear" checks. Each one is a single box query, staggered
-- across cars, so the real cost is about MaxCars / this per second.
TrafficConfig.AvoidCheckInterval = 0.3
-- Half-width of the box those checks sweep, studs. A shade under half a lane, so a car only
-- reacts to hazards it would actually hit rather than to the next lane's.
TrafficConfig.AvoidHalfWidth = 6.5

--[[ How traffic gets out of the getaway truck's way (`TrafficController._avoidAhead`, 2026-10-01).

	Not the obstacle rule above, because that one made the whole road move as one: every car within
	200 studs swerved inside the same 0.3s check the moment the truck appeared, and the probe's width
	caught the truck's mirrors from the two neighbouring lanes too. Read as choreographed.

	Each driver now reacts when it is `ReactSeconds` from the truck's tail at its own closing speed,
	rolled per car. The floor is the safety margin: a lane change clears the truck in ~1.2s at
	`LaneChangeSpeed` and the check runs every 0.3s, so nothing under ~1.6 is safe. Raise the top to
	make drivers cautious, lower it toward the floor for later, more last-second swerves.
	`MinReach` catches a car barely gaining on the truck, which would otherwise ride its bumper.
	`CarHalfWidth`/`CarHalfLength` size a traffic car against the truck's footprint (HitBox ~8.4 by ~22). ]]
TrafficConfig.AvoidTruck = {
	ReactSeconds = { 1.8, 4.5 },
	MinReach = 30,
	CarHalfWidth = 4.5,
	CarHalfLength = 11,
}

--[[ Following: how a car reacts to the one in front of it, in its own lane.

	Traffic had NO longitudinal awareness at all before this. Every car held the speed it rolled at
	spawn until something hit it, so two cars that ended up in the same lane simply drove through
	each other. That is not a hypothetical: the wall courses (`gate`, `heavyGate`, both `wallGap`s)
	leave exactly ONE of the five lanes open, so every car approaching one is FORCED into the same
	lane, and `TrafficController._avoid` deliberately does not check whether anybody is already
	there — driving through concrete is the worse sin, and its comment says so. Reported twice
	from the 16 Aug playtest as "cars merge into each other".

	LANE CHECKS ALONE CANNOT FIX THAT, which is worth being clear about before tightening one. Two
	cars abreast at a gate must both reach the one gap; there is no lane either of them can be sent
	to instead. One of them has to give way ALONG the road rather than across it, and that is what
	this is. The pair that would have merged becomes a queue through the gap, and the same rule
	stops traffic stacking anywhere else on the road.

	`LookAhead` is centre-to-centre and sized off the closing speed the tier table can produce: the
	spread is 24-44, so 20 studs/s worst case, which `Brake` bleeds off in ~1s over ~10 studs of
	closing. 60 leaves 34 studs of runway against the gap it is aiming for, so a car eases in behind
	rather than arriving at a swerve — and a routine catch-up is a gentle one, because it starts
	while the two cars are still a car-length and a half apart.

	`MinGap` is the centre-to-centre distance speeds are matched at — a car is ~22 long, so this is
	bumper to bumper plus a little. `GapGain` is studs/s asked off the leader's speed per stud of
	encroachment inside it, and it bites ONLY inside `MinGap`: a car merely catching one up matches
	speeds and settles, while a pair that is genuinely overlapping asks for the floor and backs off
	hard. Its real job is the time constant, `1 / GapGain` — an overlap decays exponentially at that
	rate, so it is what decides how long a merge stays visible. The first pass ran 0.6 (~1.7s) and
	measured 4-5 seconds to come clean, which is seconds of two cars inside each other on screen.

	`MinSpeedFactor` is a floor as a fraction of the car's OWN rolled cruise, and it is not
	optional. Traffic that can brake to a standstill parks in a lane forever, which blocks the road
	for the player and reads as a broken car rather than a slow one. ]]
TrafficConfig.Headway = {
	Enabled = true,
	LookAhead = 60,
	MinGap = 26,
	GapGain = 1.2,
	--[[ Studs/s^2, and a RATE LIMIT rather than a brake pedal: it caps how fast `speed` may move
		toward whatever the gap asks for, so a car easing in behind a slower one is still gentle
		(the ask is small) and only a car climbing out of an overlap uses the whole of it.

		Braking is the sharper of the two — falling in behind somebody has to happen before the
		overlap does, while picking the cruise back up afterwards is allowed to take its time.

		20 is where the curve flattens. Measured on a staged merge (two cars 6 studs apart, both
		committed to the same gap, equal speeds — the worst case the wall courses can produce):

		| Brake | closest approach | seconds visibly merged |
		|-------|------------------|------------------------|
		| 14    | 10.7 studs       | 0.86                   |
		| 20    | 12.6 studs       | 0.64                   |
		| 26    | 14.2 studs       | 0.53                   |

		By 20 the follower is already down on `MinSpeedFactor`, so the floor is the binding
		constraint and not this: 26 buys another tenth of a second and costs 0.8g — the physical
		limit of a road car — on every ordinary catch-up for the whole run. ]]
	Brake = 20,
	Recover = 5,
	MinSpeedFactor = 0.45,
}

-- === Colliding with a traffic car ===========================================
--[[ The collision groups that make a traffic car solid to the car you're driving and to nothing
	else. Registered and assigned by `Modules/CarCollision`: the player's car is tagged
	server-side as RaceService clones it, each traffic shell client-side as it's built.

	WHY GROUPS AND NOT JUST CanCollide. Traffic is client-local, and so is the road, so every
	driver's world sits in the same stretch of space. A plainly-collidable traffic car would
	therefore also hit, on your screen, every OTHER player's replicated car — which you don't own,
	so the server would spend the rest of their race correcting it. Pairing the two groups
	explicitly is what keeps a dozen local cars from shaking someone else's race apart. It gets
	traffic-ignores-traffic for free as well, which matters because `_avoid` deliberately drives
	cars through each other rather than leave one parked inside a concrete barrier.

	Two consequences worth knowing before tuning anything here:

	  • AN UNHIT TRAFFIC CAR IS ANCHORED and moved by a CFrame write, so until you hit it what you're
	    colliding with is an immovable wall that happens to be advancing. The FIRST real hit unanchors
	    it (see `Knock`), and from then on it's an ordinary rigidbody you can shunt around. So "can I
	    push this car" is answered by whether you've already hit it, which is worth knowing before
	    concluding the collision is inconsistent — it's the same seam `DebrisGroup` below exists for.
	  • A SPATIAL QUERY CARRIES A COLLISION GROUP TOO (OverlapParams/RaycastParams default to
	    "Default"), and a query in a group that doesn't collide with `TrafficGroup` silently comes
	    back empty. That's why TrafficController runs its clip poll as `PlayerGroup` — and why the
	    stock CarBones suspension raycasts, which run as "Default" and aren't ours to change,
	    can't see a traffic car. The body box still blocks you; there's just no wheel support on
	    the roof yet. That's a seam the steal flow will have to close (GDD §3.4). ]]
TrafficConfig.Collision = {
	Enabled = true,

	TrafficGroup = "TrafficCar",
	PlayerGroup = "PlayerCar",

	--[[ A car that has been hit and handed to physics (see `Knock`). It needs a group of its own
		because it needs the exact thing live traffic must NOT have: the road.

		An anchored shell is positioned by script, so it has no use for the deck and is kept off
		"Default" precisely so a dozen local cars can't collide with another player's replicated car.
		A physical one has to land on something — off "Default" it falls through the world. So debris
		collides with the road, the guardrails, your car and other debris (wrecks pile up), and only
		live anchored traffic is excluded, since an immovable shell is nothing to bounce off.

		The cost of that is the thing the anchored group was avoiding: on your screen, your debris can
		touch another player's car. It's bounded — debris is short-lived, rare, and you don't own that
		car so nothing you do to it sticks — but if racers ever share one stretch of road visibly,
		this is the seam, and the fix is to put the local road in a group of its own rather than to
		put debris back in Default. ]]
	DebrisGroup = "TrafficDebris",

	--[[ What the scripted impact still adds when the contact is real, used in place of `Clip`.

		The shove is the collision's job now, so the two mechanical fields are neutral: a clip
		that stops you physically AND scrubs 14% of your speed AND kicks you 7 studs/s sideways
		punishes one mistake three times over. Yaw and Shake stay — physics gives an inconsistent
		yaw off a flat box face, and the shake with its smoke puff is what reads as "that hurt".

		`Damage` is deliberately absent: HP is priced server-side from `Clip.Damage` either way,
		so a clip costs the same whether or not it's solid. ]]
	ClipFeel = {
		SpeedKeep = 1,
		SideKick = 0,
		Yaw = 0.32,
		Shake = 0.75,
	},

	-- What's left of the fields above at severity 0, so the gentlest contact still registers as
	-- something. Everything scales MinScale..1 across severity (see TrafficController._scaleKind):
	-- a graze gets a third of the yaw and shake of a real hit rather than the same jolt, which is
	-- the same reason the knock reaction is severity-driven. Below about 0.2 a hit stops reading at
	-- all and players report the collision as broken.
	MinScale = 0.3,

	--[[ Studs the clip poll's sensor volume reaches past the car's HitBox, fore and aft and on
		each flank.

		THIS IS WHAT MAKES A REAR-END REGISTER. Making traffic solid undermined the poll that
		non-solid traffic never needed, and it did so in one direction only: sideswipes stayed
		reliable while running into the back of a car mostly registered nothing. Three measured
		facts, which only line up against each other head-on:

		  1. `GetPartsInPart` needs real PENETRATION, not contact. Two boxes resting exactly face
		     to face come back with zero hits — checked at every gap from +0.5 down to -0.001, and
		     the first hit appears at -0.001.
		  2. A resolved contact oscillates either side of zero rather than settling inside, so the
		     bare HitBox is actually within the car ahead on a MINORITY of the frames it is
		     touching it — measured at under a third, against a sideswipe's every frame.
		  3. The poll also runs a frame out of step unless it goes first (see
		     TrafficController._loop), which adds `traffic speed * dt` on top — half a stud at
		     60fps, more as the frame rate drops. Measured on its own, that ordering alone halved
		     what was left of the bare HitBox's hit rate.

		(2) and (3) are why this reads as "nothing happens" rather than as flaky: what survives is
		a hit that lands only when you ram hard enough that the solver can't keep up within one
		step, which is a much narrower band than the one a player expects to be punished for.

		A sideswipe survives all three because something keeps driving the two boxes together: your
		steering holds you against the car and its lane change moves it into you. A rear-end has
		neither — you close head-on, the contact is flat face to flat face, and the solver's whole
		job is to leave no overlap for the poll to find.

		So the poll has to reach past the surface the car is stopped at. That is the same fix, for
		the same reason, as ObstacleConfig.Wall.Margin — read that note before touching this one.

		0.5 clears the measured oscillation band (+-0.25) with room to spare and cannot reach
		another lane: lanes are 15 apart, against a 8.43-wide hull and a 10.36-wide car, so there
		are 5.6 studs of daylight either side. Fore and aft it means the clip lands a frame or so
		before the bumpers actually meet — which is a bonus rather than a cost, because it lets the
		car you hit be MOVING by the time you reach it instead of an immovable wall you stop dead
		against (see the anchored-until-hit note above).

		Only applied when traffic is solid. Non-solid traffic is a pure query volume the HitBox
		passes clean through, so penetration is guaranteed and a margin would only make the hit
		land early. ]]
	ClipMargin = 0.5,
}

-- === Getting hit ============================================================
--[[ What a traffic car DOES when you hit it: it stops being scripted and becomes a rigidbody.

	A live traffic car is an anchored shell moved by a CFrame write, which is what makes a dozen of
	them affordable (TrafficController's header). On a real hit that shell is UNANCHORED, seeded with
	the velocity it was already carrying, and given one impulse at the contact point — after which
	the physics engine owns it completely. Nothing scripts its rotation, its slide or its recovery.

	Why hand it over instead of animating it. Two earlier passes scripted the reaction — a spin, then
	a gentler fishtail — and both had the same tell: the numbers were the same numbers every time, so
	the reaction never quite matched the hit that caused it. Physics gets that for free and gets it
	right, because the impulse is applied AT THE CONTACT POINT: catch a rear quarter and the lever arm
	makes it pivot, T-bone the door and it slides, clip it square from behind and it just gets shoved
	up the road. All of that used to be hand-derived (there was a `foreAft` term computing the lever
	arm by hand) and is now a consequence rather than a rule.

	It also fixes the pin properly. The reason a hit car used to have to stop colliding was that an
	anchored shell can't be pushed, so you could wedge against one and be rotated by the contact
	(that's what DriveConfig's HardYawDeg backstop exists for). A car that MOVES when you hit it
	can't wedge you. So traffic now stays solid for its whole life — you can shunt a wreck again,
	and shove it down the road ahead of you.

	TWO OUTCOMES, PICKED BY SEVERITY:

	  • a SCRAPE — stays anchored, stays AI traffic, twitches out of your way and carries on driving.
	    Its own lane easing pulls it back to its lane centre over about half a second, so there's no
	    recovery state because it never left the normal one. A graze shouldn't cost a car.
	  • a KNOCK — goes physical, permanently. It never rejoins traffic: it tumbles, slows, falls
	    behind, and the despawn window collects it.

	Most contacts in a normal run are scrapes. Set `MinSeverity = 0` if you want every contact,
	however light, to hand the car to physics. ]]
TrafficConfig.Knock = {
	Enabled = true,

	--[[ === Severity ===========================================================
		How hard the hit was, 0..1, measured from the CLOSING SPEED between the two cars along the
		line of contact — not from the fact that a contact happened. That distinction is the whole
		point: drawing level with a Tier 5 at a cruise closes at only ~8 studs/s and should barely
		disturb it, while catching a Tier 1 beater under boost closes at ~47 and should wreck it.
		Both were previously the same event.

		Derived from DriveConfig's speeds against this file's tier speeds: the driver cruises at ~52
		and boosts to ~71, traffic runs 24–44, so real closing speeds span roughly 0–47. 6 puts the
		floor just above "drifted into it while matching speed"; 34 means you have to genuinely run
		something down to max the reaction out, which leaves the top of the range meaningful. ]]
	ScrapeSpeed = 8,
	FullSpeed = 55,
	-- Below this severity a hit is a scrape and the car keeps driving. 0.25 lands the boundary at
	-- ~13 studs/s of closing speed — about the difference between changing lanes into someone and
	-- actually running into them.
	MinSeverity = 0.25,

	-- === Scrape ==============================================================
	-- Studs sideways the car is nudged, and the speed it keeps. Deliberately tiny: the nudge is
	-- fed straight into the same `cross` the lane easing owns, so the car drifts out and then
	-- steers itself back over about half a second — which IS the "wobble and recover", for free.
	ScrapeShove = 3.5,
	-- The speed half of that wobble now recovers as well as the cross half: `Headway` eases a car
	-- back to its rolled cruise whenever the road ahead is clear, so this is a beat of lost pace
	-- rather than a handicap the car carries for the rest of its life.
	ScrapeSpeedKeep = 0.94,

	-- === Knock: the hand-off to physics =====================================
	--[[ The velocity change the impulse is worth, studs/s, interpolated across severity.

		Expressed as a SPEED rather than as an impulse on purpose. An impulse is mass-dependent, so
		the moment anyone tunes `Density` below — or a redress lands with a different body size — a
		hardcoded impulse would silently mean something else. The controller multiplies this by the
		shell's actual `AssemblyMass` at the moment it goes physical, so these numbers keep meaning
		"this hit is worth about N studs/s to the car that took it" forever.

		Sized against the road: traffic runs 24–44 studs/s and lanes are 15 apart, so 12 at the
		bottom is a definite shove that leaves the car roughly where it was, and 40 at the top will
		put it across a lane or more and well out of shape. Push it much past ~60 and cars start
		leaving the road, which reads as a stunt rather than a crash. ]]
	Push = { 12, 40 },

	--[[ Fraction of `Push` added straight up, to unstick the car before the shove lands.

		Small and deliberately so. A little lift lets the car break traction and rotate freely
		instead of scrubbing flat along the deck, which is most of the difference between a hit that
		looks like a crash and one that looks like furniture being slid. Raise it and cars start
		taking off — at 0.5 they leave the ground entirely, which is the "too dramatic" failure mode
		of every previous pass here. Zero is a perfectly reasonable setting; it just reads heavier. ]]
	Lift = 0.08,

	--[[ Physical properties given to the shell's `Hit` volume, which is the only part carrying mass
		or collision. These decide everything about how debris behaves once physics owns it, so they
		matter more than any other numbers in this block.

		Density sets the mass the impulse is measured against and how the car trades momentum with
		you: the test body's Hit box is roughly 10.4 x 5 x 22 studs, so 0.9 puts it near 1000 mass —
		heavy enough to feel like a car rather than a prop, light enough that your own rig pushes it.
		Friction high-ish so it scrubs to a stop on the deck instead of gliding. Elasticity low
		because cars don't bounce; a springy value here is instantly comic. ]]
	Density = 0.9,
	Friction = 0.55,
	Elasticity = 0.15,

	--[[ === Give: leaning on a wreck until it moves ==========================
		UNVERIFIED AGAINST A REAL WEDGE — read this first. Everything below about the masses is
		measured and solid, and the ramp itself is measured working (give 0 -> 1 over `Time`, mass
		1144 -> 206 on a Civic shell, no effect on a moving player). What has NOT been shown is the
		part that matters: that a car actually pinned at 0 gets moving again once the mass drops. The
		one attempt against a genuine wedge was run without a race-liveness check and may have been
		measuring a run that had already ended, and the wedge could not be re-staged deterministically
		afterwards. Treat this as a plausible fix that is still owed a playtest, not a closed bug.

		There is one live counter-indication. In the genuine wedge that WAS captured, the driven
		wheels were spinning at 49.6 rad/s with the body at 0.0 studs/s — the tyres were already at
		their friction limit. A car in that state is limited by its own grip, not by the obstacle, and
		while dropping the obstacle's mass does lower the force REQUIRED (which is why this should
		still work), it buys nothing if what is really holding the car is the two hulls interpenetrating
		rather than the weight of the thing in front. That is the alternative to rule out next.

		THE MASSES THE REST OF THIS BLOCK IS TUNED AGAINST ARE OUT BY A FACTOR OF THREE, and this is
		the correction. `Density`'s note above says 0.9 is "light enough that your own rig pushes it".
		Measured in the place: a shell's `Hit` box comes out at 985 (Camaro) to 1269 (Golf GTI) —
		because the box is the body's whole bounding VOLUME rather than a car-shaped hull — against
		the 421 the player's own car masses. You are driving the lighter car, by 2.3x to 3x.

		With a run-up that is fine, and it reads well. From a standstill it is a wall, and a rear-end
		always ends at a standstill: the contact kills your speed against a shell that is still
		anchored, `_knock` hands it to physics a frame later, and `Push` is spent almost at once — at
		`Friction` 0.55 and gravity 196.2 a knocked car sheds 12 studs/s over 0.67 studs, and even a
		maxed 40 over 7.4. Under half a car length at the very top of the range. It parks inside your
		bonnet, and nothing else in this file can ever move it again: `_onClip` charges a car once for
		life so it can never be re-knocked, `_headway` skips `physical` records, and the despawn window
		is measured from a player who has stopped moving, so the wreck is immortal. Reported twice from
		the 16 Aug playtest as a rear-end wedging both cars.

		SO THE MASS GIVES INSTEAD OF THE PUSH GROWING. Lean on a wreck and it yields: `Density` is
		talked down toward `MinDensityFactor` over `Time` seconds of shoving. That is static friction
		breaking, in the one term that actually decides it — the force to slide a body is proportional
		to its mass, so this is linear in exactly what you need — and "push harder and eventually it
		gives" is what a player leaning on a stuck car already expects.

		WHY THE RAMP IS DRIVEN BY BEING STUCK RATHER THAN BY A CURVE. It only deepens while you are
		touching the car AND stalled, so it stops deepening the instant the wreck yields. That makes
		`MinDensityFactor` a guarantee rather than a target, and it means no number here has to predict
		how much drive force a redressed car has. 0.18 puts the worst case near 180-230 mass, well
		under the player's 421, so a give is certain rather than likely.

		AND IT HOLDS RATHER THAN RECOVERING WHILE YOU ARE STILL TOUCHING IT. Giving the mass back the
		moment the car started rolling would stall it again a few studs later and turn one shove into
		a stutter, so what has been earned is kept for as long as the contact lasts and only bleeds off
		(`Recover`) once the two come apart. Breaking something loose is not a thing you should have to
		keep re-doing.

		IF THIS DOES HOLD UP, nothing here needs a despawn timer, which is the fix it was picked over:
		a player who can move again is a player whose despawn window advances, so the wreck falls
		behind and is culled on the ordinary path. If it does not, the timer — or ejecting a wreck
		that is still inside the hull a second after the knock — is the next thing to try, and both
		are the same one-line hook in `_updateCars` this uses. ]]
	Give = {
		Enabled = true,
		-- Studs of separation between the two hulls still counted as leaning on it. Generous on
		-- purpose: a resolved contact oscillates either side of zero rather than settling inside it,
		-- which is the same measurement `Collision.ClipMargin` is sized from.
		Gap = 1.0,
		-- Our own forward speed, studs/s, below which we are stuck rather than driving. Comfortably
		-- under the slowest tier's 24, so shunting a wreck along the road at a crawl still counts as
		-- pushing and the give does not evaporate halfway through the job.
		Speed = 12,
		-- Seconds of sustained shoving to reach the floor, and seconds to give it back once the two
		-- are apart. Not symmetric, deliberately: a beat of leaning on something is what reads as
		-- effort, while a wreck that firmed up the instant it rolled off your bumper is a new wall.
		Time = 1.2,
		Recover = 0.8,
		-- What fraction of `Density` is left at full give.
		MinDensityFactor = 0.18,
		-- Seconds stalled against the same wreck before it is recycled outright, for the wreck that
		-- no amount of give can move: pinned against the rail, or inside your hull (the 2026-10-07
		-- "hit it into the side and you're stuck" report). Past `Time`, so a wreck you are genuinely
		-- shoving gets the chance to move first. 0 = never.
		ClearAfter = 1.6,
	},

	--[[ Tyre smoke off a car that's crashing. One Smoke per pooled shell, built on that shell's
		first knock and reused for the rest of the session, so a full fleet costs at most `MaxCars`
		emitters and they sit disabled the vast majority of the time.

		Sized by severity and cut off on a timer rather than by watching the car settle — physics
		debris can jitter against the deck for a long time at a speed that never quite reaches zero,
		and a plume that waits for stillness would trail the whole way down the road. ]]
	Smoke = {
		Enabled = true,
		Color = Color3.fromRGB(126, 124, 120),
		Opacity = 0.42,
		RiseVelocity = 9,
		-- Kept under the player's own impact puff (ObstacleConfig.HitSmoke maxes at 6) and well
		-- under the wreck plume's 8. This is a chirp of tyre smoke marking a car breaking traction,
		-- not a car on fire — oversizing it is the quickest way to make a hit look silly.
		MinSize = 2.0,
		MaxSize = 5.0,
		-- Seconds it stays on, light hit → heavy hit.
		Duration = { 0.5, 1.4 },
	},
}

-- === Clipping a traffic car =================================================
--[[ Same field names as an `ObstacleConfig.Kinds` entry, so it runs through the identical
	impact path (`ObstacleController.applyImpact`) — shove, yaw kick, camera shake and smoke
	puff all come free and stay consistent with every other hazard.

	With `Collision.Enabled` (the default) the client uses `Collision.ClipFeel` instead of the
	shove fields below and only `Damage` is still read, server-side. The rest is what a clip
	costs when traffic is back to being non-solid.

	`Damage` IS A RANGE, interpolated across the same severity the knock reaction uses, because a
	flat cost is unreadable: brushing a car you were already keeping pace with took exactly as much
	HP as running one down at closing speed, which teaches a player nothing about what to avoid.
	The ends are chosen against the obstacle scale (Cone 5, Barrel 12, Crate 15, then 25 and 35) so
	a graze costs about a cone and the worst ram costs more than a crate but still less than
	concrete — traffic is a mistake, not a wall. The old flat 13 sits close to the middle, so a
	typical hit is priced about where it always was.

	Sideswiping a moving car should never be the *efficient* way to get anywhere. Each traffic car
	can only charge you once — after that its volume goes query-blind until it's recycled — so
	grinding down the side of one isn't a bleed. ]]
TrafficConfig.Clip = {
	Damage = { 3, 18 },
	SpeedKeep = 0.86,
	SideKick = 7,
	Yaw = 0.32,
	Shake = 0.75,
}

--[[ Server-side floor on how often a clip can be charged, seconds.

	Unlike an obstacle, the server can't identify WHICH traffic car was clipped — traffic isn't
	seeded, so there's no id to look up and no lane to check the car's position against. What it
	can do is bound the rate, which is all that's needed: the exploitable direction has always
	been UNDER-reporting your own hits (see ObstacleService's header), and that's self-harm only
	while driving is solo. Over-reporting just damages your own car faster.

	SEVERITY RIDES ON THE SAME REPORT, and it widens that gap by a hair rather than opening a new
	one. The client measures the closing speed (only it can — it owns both cars) and sends a 0..1,
	so a cheat could always claim the lightest hit. It could already claim NO hit, so the ceiling on
	the exploit is unchanged: the worst case remains "takes less damage in a solo run". Two things
	keep it tight — the server clamps the number into range, and anything missing or malformed is
	priced at the MAXIMUM, so there is no version of sending garbage that pays. If driving ever
	stops being solo, this and the id problem above have to be solved together.

	Set from the shortest real gap between two clips — a car is 22 studs long and closing speeds
	run 8-45 studs/s, so back-to-back clips of different cars are ~0.5s apart at the very fastest. ]]
TrafficConfig.ClipCooldown = 0.65

--[[ The rosters: every body any tier can roll, deduplicated, in tier order — per world, and then
	all of them together.

	Built here rather than hand-written at the top of the file so the two can never disagree — see
	`TrafficConfig.Bodies` for why that matters. A tier with `Bodies = nil` ("any published body")
	contributes nothing to this list, which is the correct reading: it wants whatever the OTHER tiers
	have published, and if every tier were nil there would be nothing to publish and the road would
	run empty. That case warns, loudly, on both sides (TrafficService._publishBodies and
	TrafficController's start).

	`AllBodies` IS WHAT GETS PUBLISHED, and that is a deliberate change of shape. Shells live in
	ReplicatedStorage, which is one folder for the whole server — there is no per-player copy of it
	— so the moment two players can be in two different worlds at once, publishing "the live world's
	eight" stops being an option and it becomes all 29. The cost is 29 stripped visual shells built
	once at startup instead of 8; the alternative is a player driving into a world whose cars have
	not been built yet. ]]
TrafficConfig.BodiesByWorld = {}
TrafficConfig.AllBodies = {}
do
	local seenAnywhere = {}
	for world, tiers in TrafficConfig.TiersByWorld do
		local bodies, seen = {}, {}
		for _, tier in tiers do
			for _, name in tier.Bodies or {} do
				if not seen[name] then
					seen[name] = true
					table.insert(bodies, name)
				end
				if not seenAnywhere[name] then
					seenAnywhere[name] = true
					table.insert(TrafficConfig.AllBodies, name)
				end
			end
		end
		TrafficConfig.BodiesByWorld[world] = bodies
	end
end

--- The bodies a given player's road can put in front of them.
function TrafficConfig.bodiesFor(world: unknown): { string }
	return TrafficConfig.BodiesByWorld[WorldConfig.resolve(world)]
end

--[[ HOW FAR DOWN A WORLD'S ROAD THERE IS ANYTHING NEW TO SEE, in tiles: the `FromTile` of its top
	rung, i.e. the point at which the last car joins the traffic.

	IT IS THIS GAME'S FINISH LINE, and it is the only honest one available. The road is endless — it
	is recycled tiles, not a track with an end — so any "how far did I get, out of what?" needs a
	full scale that is not invented. The ladder supplies one: past the top rung's tile the road has
	shown you everything it has, and every rung below it is a real waypoint on the way there.

	Two screens are built on this and must not disagree about it, which is why it is here rather than
	on either of them: the results screen's ladder bar (`RaceUIController._planLadder`) and the
	collection screen's MAPS tab, whose percentage is a personal best measured against exactly this.

	Nil means "no progress worth showing" — a one-rung world, or a ladder that unlocks everything at
	tile 0. Both callers degrade rather than guess. ]]
function TrafficConfig.topTileFor(world: unknown): number?
	local tiers = TrafficConfig.tiersFor(world)
	if not (tiers and #tiers > 1) then
		return nil
	end
	-- All cars start eligible; this marks full rarity odds, not eligibility.
	return TrafficConfig.OddsRampTiles
end

-- The default world's roster. `AllBodies` is what the service publishes; this is what a caller
-- with no player in hand means when it says "the roster".
TrafficConfig.Bodies = TrafficConfig.BodiesByWorld[WorldConfig.ActiveIndex]

-- Publish retained owned cars for inventory previews and start-car redresses only.
-- Traffic, encounters, rewards and dealership stock continue using AllBodies/TiersByWorld.
TrafficConfig.DisplayBodies = table.clone(TrafficConfig.AllBodies)
local legacyBodies = {}
for body in WorldConfig.LegacyBodies do table.insert(legacyBodies, body) end
table.sort(legacyBodies)
for _, body in legacyBodies do table.insert(TrafficConfig.DisplayBodies, body) end

-- Approved economy balance, 2026-10-04.
--[[ Lowered with `BalanceConfig.RungWeights` (2026-10-09, its note has why). WAS
	W1 { 26, 21, 17, 13.5, 9.5, 6.5, 4, 2, 0.5 } and W2-5 { 30, 24, 19, 13, 8, 5, 1 }: the top rungs
	STARTED higher than the new weights END, so the ramp would have made the opening tiles the
	luckiest stretch of road. Now every rung starts at or below where it ends. ]]
--- Lowered again with the "much rarer" pass (same day, `BalanceConfig.RungWeights`); still at or below
--- every rung's end weight.
--- Ten entries since the Maybach joined world 1 (2026-10-09); the M5's start is below its end, as every
--- rung's must be.
TrafficConfig.World1StartWeights = { 44, 30, 18, 6, 1.5, 0.4, 0.1, 0.02, 0.005, 0.002 }
TrafficConfig.OddsRampTiles = 12 -- Slower distance progression after the speed buff (2026-10-12).
-- 2026-10-12: Explain the existing distance odds ramp at the result bar's tile milestones.
-- Presentation only: disabling this leaves encounter rolls and purchased luck untouched.
TrafficConfig.LuckProgress = {
	Enabled = true,
	Steps = 6, -- One visible milestone every two tiles; maximum odds at tile 12.
	Hold = 3, -- Long enough to read while driving; a later milestone replaces the card.
	Position = UDim2.fromOffset(16, 76), -- Top-left, below the Roblox controls (2026-10-12).
}
TrafficConfig.World1OddsRampTiles = TrafficConfig.OddsRampTiles
-- Preserve each later world's starting rarity-band mass while splitting ten bodies.
TrafficConfig.StartWeightsByWorld = { { 44, 30, 18, 6, 1.5, 0.4, 0.1, 0.02, 0.005, 0.002 }, { 32, 26, 23, 16, 1.3, 0.7, 0.35, 0.15, 0.014, 0.006 }, { 32, 26, 23, 16, 1.3, 0.7, 0.35, 0.15, 0.014, 0.006 }, { 32, 26, 23, 16, 1.3, 0.7, 0.35, 0.15, 0.014, 0.006 }, { 32, 26, 23, 16, 1.3, 0.7, 0.35, 0.15, 0.014, 0.006 } }
local Balance = require(script.Parent.BalanceConfig)
TrafficConfig.TemplateRevision = Balance.Version
for world, tiers in TrafficConfig.TiersByWorld do
 for rung, tier in tiers do
  tier.Weight = Balance.RungWeights[world][rung]
  tier.FromTile = Balance.FromTiles[world][rung]
  tier.StartWeight = TrafficConfig.StartWeightsByWorld[world][rung]
 end
end


--[[ THE RARE ONES SHINE (2026-10-06, the polish pass). A rare car on the road used to be a rarity
	plate and nothing else, which you read only once you were close. Cars of band `MinBand` and up
	(`CarRarity`) give off a slow stream of sparkles in their rarity colour, so "there's a good one"
	happens at a glance down the road. One emitter per shell, made once and switched with the car, so a
	pooled shell costs nothing extra when it comes back as a common. `Enabled = false`: no shine. ]]
TrafficConfig.RareShine = {
	Enabled = true,
	MinBand = 4,
	Rate = 6,
	Size = 1.1,
}


--[[ THE RARE-CAR ANNOUNCEMENT (2026-10-08, the polish pass). A top-rarity car on the road was a plate
	and a shine you only noticed once you were near it. Now when one spawns, a banner drops in at the
	top of the screen — "A SUPERCAR SENNA IS ON THE ROAD!" in its rarity colour — so the player knows to
	go hunting, which is the moment the rarity system is for. A WEATHER car counts from a lower band
	(`MutationMinBand`), because a mutation is rare in itself. At most one per `Cooldown` seconds, so a
	lucky stretch of road is still an event and not a ticker. Never on the tutorial's run.
	`RareCarBannerController` draws it off `Event`; `Enabled = false`: no banner. ]]
TrafficConfig.Announce = {
	Enabled = true,
	MinBand = 5,
	MutationMinBand = 3,
	Cooldown = 25,
	Event = "RareCarSpawned",
	--[[ TWO LINES ON A KIT CARD, NOT ONE SENTENCE (2026-10-12). The banner is the kit's day card faced
		in the car's rarity, the car itself turning on the left, `Kicker` (the rarity or the weather)
		over the car's name. The name is the big line: it is what the player goes looking for. ]]
	Kicker = "%s ON THE ROAD!",
	--- Seconds the banner holds before it slides back up.
	Hold = 2.8,
	--- Where it rests (screen share), between the near-miss toast (0.105) and the STOLEN toast (0.24).
	Y = 0.165,
	Sound = { Group = "Steal", Name = "RareSpotted" },
}

-- Stronger collision consequences, 2026-10-12. Closing-speed severity still prices each hit.
TrafficConfig.Clip.Damage = { 6, 32 }

-- Traffic target speeds rise only 3% overall while player speed ceilings rise 8%.
-- Relative speeds compensate for the faster player cruise used by the traffic spawn path.
for _, tiers in TrafficConfig.TiersByWorld do
 for _, tier in tiers do
  for index, value in tier.SpeedFraction do tier.SpeedFraction[index] = value * (1.03 / 1.08) end
  for index, value in tier.Speed do tier.Speed[index] = value * 1.03 end
 end
end

return TrafficConfig
