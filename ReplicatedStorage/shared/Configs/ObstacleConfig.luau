--[[
	ObstacleConfig
	--------------
	Everything designers tune for the dodge-the-obstacle layer: the obstacle kinds (look,
	damage, how hard a hit shoves you around), the named obstacle "courses", and the
	difficulty ramp that decides which courses appear how far into a run.

	Two things to know before editing:

	1. NOTHING HERE COLLIDES. Obstacles are built as inert visuals plus one invisible
	   query volume, so an obstacle can never stop the car dead, flip it, or fight the
	   tuned CarBones suspension (see the car-system handoff doc, §5/§7 — this is the
	   "arcade chip damage" answer to the collide-vs-query question). The whole feel of a
	   hit comes from `SpeedKeep` / `SideKick` / `Yaw` / `Shake` below, which the client
	   applies to the car it owns. That means the feel is 100% tunable from this file.

	2. LAYOUT IS SEEDED, NOT REPLICATED. ObstacleLayout turns (raceSeed, tileIndex) into
	   the exact obstacle list for a road tile. The client builds geometry from it and the
	   server re-derives the same list to validate hit reports, so no obstacle instance
	   ever replicates. Consequence: changing this file changes the layout for both sides
	   at once (good), but the two sides must be running the same build (they always are).

	Placement frame: every obstacle sits ON the deck at `DriveCenterX + Lanes[i]`, so
	`Size`/`Offset` are read as (across-the-road, up, along-the-road) and Offset.Y is
	measured up from the deck surface. `Shape = "Cylinder"` is Roblox's X-axis cylinder,
	so an upright one wants `Rotation = (0, 0, 90)` and `Size = (height, dia, dia)`.
]]

local ObstacleConfig = {}

-- Master switch. Off = the road streams exactly as it did before this layer existed.
ObstacleConfig.Enabled = false

-- Cosmetic obstacle models are smooth enough at 30 Hz. Query volumes continue updating every
-- Heartbeat, so this reduces model transforms without lowering collision accuracy.
ObstacleConfig.VisualInterval = 1 / 30

--[[ TESTING: the car can still be hit, but its HP never goes down — so a run never ends in a
	wreck and you can drive one seed for as long as you like.

	This is the switch for measuring DRIVING (steering feel, camera, suspension, top speed), where
	being sent back to the lobby mid-measurement is what ruins the reading. It deliberately leaves
	the *feel* of a hit completely intact — the shove, the yaw kick, the speed cut and the camera
	shake are ObstacleController's, applied client-side, and none of them are HP — so the physics
	you're measuring is byte-for-byte the physics that ships. Only the consequence is removed.

	It gates the ONE place HP moves (ObstacleService._applyDamage), which is why it covers every
	hazard at once: obstacles, guardrail scrapes and TrafficService's car clips all funnel through
	there. Server-side, so a client can't set it — and it is read live, so flipping it mid-session
	takes effect on the next hit without restarting the race.

	The two companion switches for the same job live next to the layers they turn off:
	  • ObstacleConfig.Enabled (above) — no obstacle course at all; the road streams empty.
	  • TrafficConfig.Enabled           — no traffic cars, which are SOLID and are the biggest
	                                      single source of unwanted rotation in a driving test.
	Turn all three off and you have a bare road to measure the car on. ]]
ObstacleConfig.Invulnerable = false

-- === Names ==================================================================
-- Folder created inside each local road tile to hold that tile's obstacles. Living
-- inside the tile Model is deliberate: RoadController moves tiles with Model:PivotTo,
-- which carries the obstacles along for free on both recycle and world-rebase.
ObstacleConfig.TileFolderName = "Obstacles"
-- Client-only folder that smashed props and their broken-off pieces fly into (outside the
-- tiles, so a recycle/rebase can't teleport mid-flight debris). See ObstacleConfig.Smash.
ObstacleConfig.DebrisFolderName = "ObstacleDebris"
-- The car part that owns Health/MaxHealth (the chassis's mid-height hull — see §5 of the
-- handoff doc; do NOT swap this for a full-height box).
ObstacleConfig.HitBoxName = "HitBox"
ObstacleConfig.DefaultMaxHealth = 100

--[[ THE 2X CAR HP GAME PASS (`passes.HealthDouble`, `ShopConfig`, `PassService`).

	ONE NUMBER, APPLIED IN ONE PLACE. `ObstacleService._setMaxHealth` is the only writer of a car's
	ceiling — its own comment explains why a second one would put the HP bar and the wreck check on
	different numbers — so the pass is a factor on that write and nothing else in the game learns it
	exists. No damage number changes, no course changes, no pickup changes: the car simply has twice
	as much to spend.

	IT MULTIPLIES THE CEILING, NOT THE DAMAGE, and those are not the same feature. Halving damage
	would make the cheapest hits free (a 4 HP tumbleweed becomes 2) and would quietly re-tune the
	arcade chip damage `ObstacleConfig` is built around. Doubling the ceiling leaves every hit
	costing exactly what it says on its kind and simply buys more of them. It also composes with
	`CarConfig.MaxHealth` for free, so a tier 8 car with the pass is still tougher than a tier 1 with
	it — the ladder is preserved rather than flattened.

	`Multiplier` IS WRITTEN HERE AND THE PRICE IS WRITTEN IN `rbxsync.toml`, and the two are related:
	2 is the number the pass NAME promises. Changing it to 1.5 without renaming the pass is the same
	class of failure as a price that disagrees with the card, except the player cannot check this one
	against anything. If it ever needs tuning, the name and the store description move with it.

	THE HEALTH BAR NEEDS NO CHANGE. It reads Health against MaxHealth off the HitBox, so a doubled
	ceiling draws as a full bar that empties half as fast, which is exactly the feeling being sold. ]]
ObstacleConfig.HealthPass = {
	--- The `PassConfig` key. `PassService:owns(player, Key)` is the whole ownership question.
	Key = "HealthDouble",
	--- What an owner's ceiling is multiplied by. See above on why this is the ceiling and not damage.
	Multiplier = 2,
}

-- === Prop art ===============================================================
--[[ Obstacles are built from the modeller's per-world prop MODELS when there are any, and from
	the primitive `Build` recipe on the kind when there aren't. The two are interchangeable on
	purpose: art lands one world and one kind at a time, and a kind with no art yet has to keep
	working rather than vanish off the road.

	WHERE THE ART IS AUTHORED. `Workspace.<PropSourceFolderName>` holds one folder per themed
	road, and inside it one Model per obstacle kind, named for the kind (`Cone`, `Barrier`, ...).
	That folder is tagged `RelocateObject`, so on a live server it is in ServerStorage rather than
	Workspace by the time anything reads it — `ObstacleService._propSource` looks in both, and the
	tag should stay on: this art has no business replicating to anyone.

	The folder is looked up by the world's MAP name first (`City`, `Desert`, ...) and by
	`World<n>` second, because the art belongs to the road's theme rather than to the car ladder
	driven on it — a cactus belongs to the desert whichever ladder is pointed at that map — but
	the modeller delivers them per world. Either name resolves; the map name is the one to prefer
	for anything new.

	WHAT THE ART DOESN'T HAVE TO GET RIGHT. Nothing about how a prop is delivered is load-bearing:
	pivot anywhere, any size, parts loose, any material. `ObstacleService._publishProps` fits each
	one to `Art.Width`, re-pivots it to the centre of its own footprint on the deck, welds it into
	one assembly and republishes it under `ReplicatedStorage.<PropFolderName>.<map>.<Kind>`, which
	is what the client clones. So the ONE number a designer sets per kind is `Art.Width` below.

	`Art.Width` is the across-the-road span of the fitted prop, in studs, and the prop is scaled
	UNIFORMLY to hit it — height and depth follow whatever the modeller drew. Note that it is a
	visual number and not the hit volume: `HitSize` stays authored separately, because a prop's
	widest point is often a flat base plate you should be able to clip without being charged for
	it (the world-1 cone is exactly this — a 4.6-wide plate under a 3.3-wide cone).

	NOT EVERY KIND HAS A FALLBACK, and from world 2 on none of them do. `Build` is what the
	world-1 kinds were drawn out of before their art landed; the desert set is authored against
	delivered models only, so a desert kind with no art builds NOTHING rather than a primitive
	from another world's visual language. Both states are supported — see the Kinds header.
	`Art.Yaw` (degrees) turns a prop drawn facing across the road to face down it instead, and is
	applied BEFORE the width is measured — so `Width` always describes the prop as it will stand on
	the road, whichever way round it was drawn. EVERY PROP DELIVERED SO FAR, in both worlds, is
	authored yawed 90 degrees, so assume a new one is too: it is invisible on something radially
	symmetric like the cone or the sand dune, and on anything longer than it is deep it is the
	difference between a barricade and a five-times-oversized one. Confirm it by reading the
	published size out of `ReplicatedStorage.ObstacleProps.<map>` rather than by eye — a prop that
	is half the road wide looks deliberate from the driving seat. ]]
ObstacleConfig.PropSourceFolderName = "Assets"
ObstacleConfig.PropFolderName = "ObstacleProps"

-- === Lanes ==================================================================
-- Cross-axis offsets from the road's DriveCenterX. DriveWidth is ~73.5 (±36.7), and 15-stud
-- lane spacing leaves a threadable gap between props.
--
-- WHICH CAR WIDTH A GAP IS CUT FOR — measured across all 65 rigs, 2026-08-19, and it is two
-- different numbers. Only one thing in this game can be CHARGED for a hit: the shared chassis
-- `HitBox`, 8.43 x 20.57, byte-identical on every car (the hit poll is one GetPartsInPart against
-- it, so a body that overhangs it cannot be hit at all). But the bodies bolted over that HitBox
-- run 8.5-12.9 wide, median 9.6, and two of them clear 11 (Sian 12.9, NewSports37 11.9). So a gap
-- cut to 8.43 is one the widest cars visibly plough through without ever being touched. Gaps here
-- are cut for ~10.5 — the 90th percentile body — which scores identically and stops nine cars in
-- ten from looking like they got away with something.
-- Courses below index into this list, so re-spacing lanes re-spaces every course.
ObstacleConfig.Lanes = { -30, -15, 0, 15, 30 }

-- === Kinds ==================================================================
--  Damage    HP removed per hit (server-applied; the client never sends a number).
--  SpeedKeep Fraction of velocity kept on impact — 1 = no slowdown, 0.5 = halved.
--  SideKick  Studs/s of sideways shove away from the thing you clipped.
--  Yaw       Rad/s of yaw kick away from the hit. Keep under ~1 or it reads as a spin-out.
--  Shake     Camera shake magnitude (studs of CameraOffset), decays over ~0.3s.
--  Smash     What happens to the THING YOU HIT -- tumble it off, break it apart, or leave it
--            standing. Absent = it stops counting and never moves. See `ObstacleConfig.Smash`.
--  HitSize   The invisible query volume. Slightly larger than the visual reads as fair.
--  Slick     Optional, and it changes what the kind IS: a Slick kind takes your GRIP for a
--            beat instead of taking your HP. See `Oil` below for the whole shape of it.
--  Roll      Optional, and the only field that moves an obstacle after it is built: the kind
--            sweeps across the road instead of standing on its lane. See `Tumbleweed`.
--  Boost     Optional, and the only field that GIVES the car something. `Speed` studs/s along the
--            road, `Lift` studs/s straight up, `Nitro` a fraction of a tank handed to
--            NitroController. Implies `Pass`. See `BoostPad` and `GravityLift`.
--  Pass      Optional. The car goes THROUGH this: the id is consumed (so it still isn't a dodge)
--            and nothing else happens at all -- no HP, no shove, no yaw, no shake, no smoke, no
--            police strike, no smash. `Damage = 0` is what the SERVER reads and this is what the
--            CLIENT reads, so a kind that passes has to say both. See `Hologram`.
--  Pickup    Optional, and the only field that hands the player something they KEEP. Names a pack
--            in `PickupConfig.Packs`; that file owns the payout, the art and the slot it banks
--            into, and everything here is the two lines it takes to be an obstacle. Implies
--            `Pass`, and is placed by its own layout pass rather than by a course -- read
--            `PickupConfig`'s header before touching either kind. See `HealthPack`/`NitroPack`.
--  Local     Optional. The SERVER NEVER HEARS ABOUT THIS KIND: a hit is felt on the client and
--            nothing is reported. Only for a kind that costs nothing and that the server has no
--            layout for anyway, which today is the rain's puddle. See `Puddle`.
--  Splash    Optional, and it replaces the impact beat: the car went through WATER, so there is no
--            smoke, no camera punch and no police strike, only a pull toward the side that is in
--            the water, a nudge of shake and a spray off the car. See `Puddle`.
ObstacleConfig.Kinds = {
	--[[ THE TWO ROAD PICKUPS. Everything that makes them interesting is in `PickupConfig`; what is
		here is only what `ObstacleLayout`, the client's hit poll and the server's hit check need to
		treat them as ordinary obstacles, which is the whole reason they are authored as kinds.

		THEY ARE IN NO COURSE AND NO TIER POOL, and that is not an omission. `ObstacleLayout.forTile`
		places them in a second pass with its own density and its own salted RNG, so they reach every
		map without a single ramp being edited and retuning them cannot reshuffle an obstacle. The
		consequence to know about: `ObstacleLayout.kindsFor` walks the ramps, so these two never
		appear in it, so `ObstacleService._publishProps` is never asked for art for them -- which is
		correct, because they have none and must not (see `PickupConfig`'s art note: a pack is drawn
		identically in every world so the glyph means one thing everywhere).

		`Pass = true` is what stops a reward feeling like a hit: no shove, no yaw, no shake, no
		smoke, no smash and no police strike during a chase. `Damage = 0` says the same thing to the
		server. Both are required -- see the Kinds legend.

		THE VOLUME IS BIGGER THAN THE ART, which is the exact opposite of the rule every other kind
		in this file follows. A cone's volume is cut IN from its base plate so you are never charged
		for a hit you could not really have taken; a pack's is cut OUT past its glyph so you are
		never denied a reward you clearly steered for. Both are the same rule -- give the player the
		benefit of the doubt -- and it only looks inverted because the two kinds of object are on
		opposite sides of it.

		14 TALL, which is the tallest volume in the game and deliberately so. The futuristic gravity
		lift throws the car to about 7 studs of apex and a hard landing bottoms the suspension out;
		a pack you fly straight through without collecting is a bug as far as anyone driving is
		concerned, so the volume covers the whole band the car can be in over its lane. ]]
	HealthPack = {
		Damage = 0,
		SpeedKeep = 1,
		SideKick = 0,
		Yaw = 0,
		--- Zero, unlike the boost pad's 0.25. A pad is a kick in the back and needs the camera to
		--- agree; a pack is picked up, not hit, and there is nothing for a shake to be the
		--- consequence of.
		Shake = 0,
		Pass = true,
		Pickup = "Health",
		HitSize = Vector3.new(13, 14, 8),
	},
	NitroPack = {
		Damage = 0,
		SpeedKeep = 1,
		SideKick = 0,
		Yaw = 0,
		Shake = 0,
		Pass = true,
		Pickup = "Nitro",
		--- The same volume as the health pack, and it must stay that way: two rewards that are
		--- collected from different distances would teach a player to trust their eye on one and
		--- not the other.
		HitSize = Vector3.new(13, 14, 8),
	},
	--- The Star (2026-10-13, punch list N2): a few seconds of invincibility and speed. Same volume as
	--- the other two for the reason the nitro pack gives; everything it does is `PickupConfig.Packs.Star`.
	StarPack = {
		Damage = 0,
		SpeedKeep = 1,
		SideKick = 0,
		Yaw = 0,
		Shake = 0,
		Pass = true,
		Pickup = "Star",
		HitSize = Vector3.new(13, 14, 8),
	},

	Cone = {
		Damage = 5,
		SpeedKeep = 0.94,
		SideKick = 3,
		Yaw = 0.18,
		Shake = 0.35,
		Smash = { Force = 1 },
		--[[ Sized to the CONE, not to its base plate. World 1's prop is a 4.6-wide square plate
			with a ~3.3-wide cone standing on it, and the plate is flat on the deck — well under
			the HitBox's deck+0.96 lower edge — so a volume that covered it would charge you for
			clipping something the car cannot physically touch. 3.4 is also what the primitive
			fallback below measures, so both builds of a cone punish the same line. ]]
		HitSize = Vector3.new(3.4, 5, 3.4),
		Art = { Model = "Cone", Width = 4.6 },
		-- Fallback for a world with no cone art yet. Deliberately the same footprint as the
		-- fitted prop, so a run that mixes the two never changes how a course threads.
		Build = {
			{
				Shape = "Block",
				Size = Vector3.new(3.2, 0.4, 3.2),
				Offset = Vector3.new(0, 0.2, 0),
				Color = Color3.fromRGB(38, 38, 42),
				Material = Enum.Material.Plastic,
			},
			{
				Shape = "Cylinder",
				Size = Vector3.new(4, 2.6, 2.6),
				Offset = Vector3.new(0, 2.2, 0),
				Rotation = Vector3.new(0, 0, 90),
				Color = Color3.fromRGB(255, 116, 24),
				Material = Enum.Material.Plastic,
			},
			{
				Shape = "Cylinder",
				Size = Vector3.new(0.8, 2.75, 2.75),
				Offset = Vector3.new(0, 2.7, 0),
				Rotation = Vector3.new(0, 0, 90),
				Color = Color3.fromRGB(245, 245, 240),
				Material = Enum.Material.Plastic,
			},
		},
	},

	Barrel = {
		Damage = 12,
		SpeedKeep = 0.84,
		SideKick = 6,
		Yaw = 0.35,
		Shake = 0.7,
		--[[ NO `Break`, and now that the art has landed that is finally an honest setting. A barrel
			bursting open is a perfectly good idea -- `Crate` asks for exactly that -- but breaking
			only looks like breaking when the pieces are pieces somebody modelled. The primitive
			below has three, and two of them are hoops around the third.

			It read as broken even WITHOUT `Break`, which is the bug the art fixed: `_smash` writes
			one shared `AssemblyAngularVelocity` onto every part, and the primitive path welded
			nothing, so the two hoops spun about their own centres instead of orbiting the body's
			and slid out of the barrel as it tumbled. Reported as the mid-part coming off. Both
			paths are welded now and neither can do it again: `_fitProp` welds a delivered prop to
			its biggest part, and `_buildObstacle` welds a `Build` recipe into one assembly, which
			is what let `Crate` go back to tumbling whole. The delivered barrel is a mesh plus two
			strap rings and tumbles as one because of that weld, not because it is one part. ]]
		Smash = { Force = 1 },
		HitSize = Vector3.new(4.8, 6.4, 4.8),
		--[[ THE OIL SLICK'S OWN DRUM, IN GREEN INSTEAD OF RED, WITH TWO DARK STRAPS. Cut from `Oil`'s
			mesh by the `BuildBarrelProp` Command Runner command, which carries the argument for why;
			the short version is that world 1 already had a modelled barrel standing in it and the
			`Barrel` kind was the only thing on the road still guessing at one out of cylinders.

			It was blue until 2026-09-08 and blue was the wrong read: the city's sky renders
			`85,177,255` and that drum `21,123,255`, so the hazard was a darker patch of its own
			backdrop. Green is the only saturated hue on this road spoken for by neither the
			backdrop nor another hazard. The straps are two Cylinder parts laid over the hoops the
			mesh already models, because a MeshPart has exactly one colour and this is the only way
			to get a second one onto it short of splitting the mesh. Both live in `BuildBarrelProp`,
			with the measurements they were derived from.

			5 IS NOT A TASTE NUMBER, it is the size that same drum comes out at inside `Oil`: that
			model fits to 18 across a 27.44-wide source, and 7.62 of drum times that 0.656 is 5.00
			wide and 5.78 tall. Ask for anything else here and the game ships two drums drawn at
			two scales. It also happens to land within a quarter-stud of the primitive it replaces
			(4.5 across, 6 tall), so not one authored course had to move.

			No `Yaw`, for the cone's reason: the drum is square in plan (7.62 x 7.62), so there is
			no long axis for a turn to put across the road. Every non-symmetric world-1 prop needs
			the 90. ]]
		Art = { Model = "Barrel", Width = 5 },
		-- Fallback for a world with no barrel art. Left at the footprint the prop fits to, so a run
		-- that mixes the two threads the same; see `Smash` above for what it does when hit.
		Build = {
			{
				Shape = "Cylinder",
				Size = Vector3.new(6, 4.5, 4.5),
				Offset = Vector3.new(0, 3, 0),
				Rotation = Vector3.new(0, 0, 90),
				Color = Color3.fromRGB(240, 196, 40),
				Material = Enum.Material.Metal,
			},
			{
				Shape = "Cylinder",
				Size = Vector3.new(0.7, 4.65, 4.65),
				Offset = Vector3.new(0, 1.7, 0),
				Rotation = Vector3.new(0, 0, 90),
				Color = Color3.fromRGB(30, 30, 34),
				Material = Enum.Material.Metal,
			},
			{
				Shape = "Cylinder",
				Size = Vector3.new(0.7, 4.65, 4.65),
				Offset = Vector3.new(0, 4.3, 0),
				Rotation = Vector3.new(0, 0, 90),
				Color = Color3.fromRGB(30, 30, 34),
				Material = Enum.Material.Metal,
			},
		},
	},

	Crate = {
		Damage = 15,
		SpeedKeep = 0.80,
		SideKick = 7,
		Yaw = 0.4,
		Shake = 0.8,
		--[[ TUMBLED WHOLE, not broken. This asked for `Break` on the reading that a crate coming
			apart is the whole point of a crate -- but the recipe below is not a crate cut into
			pieces, it is one box with a dark band painted round its middle as a second part. Broken,
			that band left on its own scatter and the box was left with a hole where its trim had
			been: read as a modelling fault, not as a crate bursting. Reported (2026-09-08) as the
			middle part coming apart.

			A crate that really bursts needs pieces somebody drew as pieces -- planks, a lid, a
			spilled load -- which is the same conclusion `Barrel` above reached about its hoops. Put
			`Break = true, Spread = 0.6` back the day a crate prop with those pieces is delivered.

			Whole is now honestly whole: the primitive `Build` parts are welded into one assembly at
			build time (`ObstacleController._buildObstacle`), so the single spin `_smash` writes
			tumbles the box and its band together instead of spinning each about its own centre. ]]
		Smash = { Force = 1 },
		HitSize = Vector3.new(6.3, 6.3, 6.3),
		Build = {
			{
				Shape = "Block",
				Size = Vector3.new(6, 6, 6),
				Offset = Vector3.new(0, 3, 0),
				Color = Color3.fromRGB(124, 92, 62),
				Material = Enum.Material.WoodPlanks,
			},
			{
				Shape = "Block",
				Size = Vector3.new(6.15, 1, 6.15),
				Offset = Vector3.new(0, 3, 0),
				Color = Color3.fromRGB(88, 64, 42),
				Material = Enum.Material.Wood,
			},
		},
	},

	-- A row of these across neighbouring lanes reads as one wall — "reads as" is load-bearing
	-- there, and the width note below says why.
	Barrier = {
		Damage = 25,
		SpeedKeep = 0.62,
		SideKick = 9,
		Yaw = 0.55,
		Shake = 1.2,
		--[[ It BURSTS. This was `false` -- the barricade stood there untouched while you drove
			through it, which is the one hit in the game where the object you are looking at gave
			you nothing back. It is an arm-and-feet barricade, not a wall poured into the road, so
			coming apart is also the honest read of what it is.

			Force is under 1 because it should shed off the bumper rather than launch: a barricade
			that sails over the camera turns a 25-damage mistake into a firework. ]]
		Smash = { Force = 0.85, Break = true, Spread = 0.7 },
		HitSize = Vector3.new(10, 5, 3),
		--[[ THIS WIDTH IS SET BY THE HEIGHT IT BUYS, which is worth saying out loud because the
			number reads like a gameplay dial and is really an art one. `Art.Width` scales the prop
			UNIFORMLY, so asking for the old primitive's 16-stud span stood the modeller's barricade
			up 10.0 studs tall — against cars whose own median height is 6.0. 10 across brings it to 6.3,
			which is car-roof height: tall enough to hide what is behind it, short enough to belong
			on the road. Picked by standing all the candidates next to a car, not by arithmetic.

			WHAT IT COSTS IN GAMEPLAY, and why that is the good half of the trade. Lanes are 15
			apart, so neighbours no longer overlap into one continuous wall — they leave 5 studs of
			daylight between them. Nothing fits that — the HitBox alone is 8.43 — so the wall is exactly
			as impassable as it was and merely looks like the row of separate barricades it is. The
			real change is in the authored gaps, which all open up: `gate` from 14 studs to 20,
			`wallGapLeft`/`Right` from 13.75 to 16.75, `oilTrap`'s second beat from 12 to 20. At 85
			studs/s those were tight enough to read as unfair.
			`Yaw` because the delivered barricade lies along Z. ]]
		Art = { Model = "Barrier", Width = 10, Yaw = 90 },
		-- Fallback: the same 10-stud span, so a world with no barricade art threads every wall
		-- course exactly as it is authored.
		Build = {
			{
				Shape = "Block",
				Size = Vector3.new(10, 4.5, 3),
				Offset = Vector3.new(0, 2.25, 0),
				Color = Color3.fromRGB(226, 226, 220),
				Material = Enum.Material.Concrete,
			},
			{
				Shape = "Block",
				Size = Vector3.new(1.6, 3.6, 3.2),
				Offset = Vector3.new(-3.1, 2.25, 0),
				Color = Color3.fromRGB(196, 58, 48),
				Material = Enum.Material.Concrete,
			},
			{
				Shape = "Block",
				Size = Vector3.new(1.6, 3.6, 3.2),
				Offset = Vector3.new(0, 2.25, 0),
				Color = Color3.fromRGB(196, 58, 48),
				Material = Enum.Material.Concrete,
			},
			{
				Shape = "Block",
				Size = Vector3.new(1.6, 3.6, 3.2),
				Offset = Vector3.new(3.1, 2.25, 0),
				Color = Color3.fromRGB(196, 58, 48),
				Material = Enum.Material.Concrete,
			},
		},
	},

	-- Late-run wall block: tall enough that you can't see the gap until you're close.
	Concrete = {
		Damage = 35,
		SpeedKeep = 0.5,
		SideKick = 11,
		Yaw = 0.7,
		Shake = 1.6,
		--[[ It breaks, but it does not fly. Half force is the difference between "I smashed a
			block" and "I punted a block": the chunks shove clear of the bumper and drop, and the
			35 damage is still the thing that teaches you not to do it again. ]]
		Smash = { Force = 0.5, Break = true, Spread = 0.45 },
		HitSize = Vector3.new(16, 8.4, 6.4),
		Build = {
			{
				Shape = "Block",
				Size = Vector3.new(16, 8, 6),
				Offset = Vector3.new(0, 4, 0),
				Color = Color3.fromRGB(146, 146, 142),
				Material = Enum.Material.Concrete,
			},
			{
				Shape = "Block",
				Size = Vector3.new(16.1, 1.4, 6.1),
				Offset = Vector3.new(0, 7.3, 0),
				Color = Color3.fromRGB(236, 196, 48),
				Material = Enum.Material.Concrete,
			},
		},
	},
	--[[ THE OIL SLICK -- the first hazard here that costs no HP at all.

		Everything above charges you and shoves you once. Oil charges nothing, does not slow you,
		and does not knock away: it takes the car's grip for a beat and lets the road do the rest.
		The whole cost is indirect -- it is about where the fishtail PUTS you -- which is why it is
		authored into courses in front of something solid rather than on its own (see `oilTrap`).

		`Damage = 0` is load-bearing and the server reads it: ObstacleService still consumes the id,
		so driving through a slick is correctly not a dodge (`clearedFor`), but it skips the HP
		write entirely rather than subtracting nothing from it.

		It keeps its full speed and takes no yaw, so the only two things that happen to you are the
		one-shot `SideKick` that breaks you loose and the `Slick` that stops you correcting it. ]]
	Oil = {
		Damage = 0,
		SpeedKeep = 1,
		--[[ The break-away: the shove that puts you off your line at the moment the grip goes. Not a
			punishment, which is what separates it from every other kind's — those are damage you can
			feel, this is the road moving under you.

			26 → 10, BECAUSE 26 READ AS A COLLISION AND NOT AS A SLIDE. It was the biggest kick in the
			file by a factor of more than two — Concrete, the heaviest solid thing in the game at 35
			damage, kicks 11 — so touching a puddle hit harder than driving into a block wall, and at
			the old grip you then could not correct it. It was reported as colliding with the oil, and
			the parts were checked: every one of them is CanCollide false on the road. Nothing was
			being hit. The kick was just far too big to read as anything else.

			10 still clears the floor it has to clear (DriveController's lane ease discards anything
			under 1.5 studs/s as ordinary physics, so the bar was never anywhere near 26) and still
			lands you off your line. What carries the rest of the read now is the FISHTAIL —
			`DriveConfig.Slick`, which did not exist when this was tuned and which is the thing that
			actually says "you are on oil" rather than "you hit something". ]]
		SideKick = 10,
		-- Zero because an external yaw write is overwritten inside one frame by the lean servo that
		-- holds the car's nose in direct steering -- measured, a sustained 2 rad/s turns the car 0.0
		-- degrees. That is not "a slick gets no rotation", it is "a slick cannot get its rotation
		-- from HERE": the wag comes from `DriveConfig.Slick`, which moves the servo's target instead
		-- of fighting it and so survives where this would not. Leave this at 0 and tune it there.
		Yaw = 0,
		Shake = 0.4,
		--[[ The DRUM goes and the spill stays, which is the whole reason `Smash` throws pieces by
			height rather than throwing the prop. Knocking this away as one body would peel two flat
			sheets of puddle off the road and send them through the air; leaving it alone entirely
			was the old answer, and it meant the one upright object in the hazard -- the thing you
			were looking at when you hit it -- absorbed a car at 85 studs/s without flinching. ]]
		Smash = { Force = 0.9, Break = true, Spread = 0.6 },
		-- Smaller than the 18-wide visual on both axes. Clipping the feathered edge of a spill is
		-- not something you would feel, so it should not be something that takes the car off you.
		HitSize = Vector3.new(15, 5, 10),
		--[[ The grip loss itself, handed straight to DriveController.applySlick -- read that function
			before touching either number, because WHICH LEVER THIS PULLS is not the obvious one.

			`Grip` is the fraction of its usual steering the car answers -- IT IS A FRACTION OF, NOT A
			REDUCTION BY, which is the single easiest thing to misread here: 0.15 left you with a
			SEVENTH of your steering, not 85% of it. It holds for `Duration` seconds and recovers
			linearly back to 1 across that window.

			It is not a slide: in direct steering the car's cross-road velocity is written from the
			player's input every frame, so a hazard cannot make the car slide by pushing it (measured:
			a 14 studs/s shove buys one stud before the lane ease erases it). What it can do is stop
			the wheel answering, which from the driver's seat is the same thing. Measured at 0.15, a
			player fighting the break-away recovered 2.9 studs of the 18.8 they would recover on dry
			road -- so you got shoved off your line and then watched yourself not correct it.

			0.15 → 0.35, in the same pass that cut `SideKick` and added the fishtail. At a seventh of
			your steering the car is not slippery, it is switched off, and with nothing on screen
			saying why (the puddle is under the car by then) it read as the controls breaking rather
			than as a hazard. A third of your steering still loses you the fight and still puts you
			where `oilTrap`'s barriers are waiting, but you are visibly in it rather than watching it.
			Put this back to 0.15 if oil should be near-unsurvivable now that it is legible.

			1.6 seconds is about 135 studs at cruise, which is why `oilTrap` puts its barriers 120 past
			the slick: you arrive still on ice. Lengthening this makes oil far more dangerous than the
			damage numbers anywhere in this file suggest, because its whole cost is what you hit next. ]]
		Slick = {
			Duration = 1.6,
			Grip = 0.35,
		},
		--[[ 18 across, from a prop drawn 27.4 wide with an 8.9-stud drum standing in it -- scaled
			off the DRUM rather than the spill, because a drum nearly twice the height of the car is
			the thing you notice first. At 18 across the drum stands 5.78, and THAT number is now
			load-bearing somewhere else: `Barrel` is a copy of this very mesh and its `Art.Width` of
			5 is reverse-engineered from it so the two drums are one size. Re-scale this and the
			barrel has to be re-scaled with it. ]]
		Art = { Model = "Oil", Width = 18, Yaw = 90 },
		--[[ Fallback: the spill, and the drum that leaked it. The drum is not decoration -- a dark
			puddle painted on dark asphalt is close to invisible at 85 studs/s, and the upright
			object beside it is the entire reason you can read this hazard in time to avoid it. ]]
		Build = {
			{
				Shape = "Cylinder",
				Size = Vector3.new(0.2, 15, 15),
				Offset = Vector3.new(0, 0.1, 0),
				Rotation = Vector3.new(0, 0, 90),
				Color = Color3.fromRGB(24, 22, 20),
				Material = Enum.Material.SmoothPlastic,
				Transparency = 0.15,
			},
			{
				Shape = "Cylinder",
				Size = Vector3.new(5.2, 3.8, 3.8),
				Offset = Vector3.new(5.4, 2.6, 0),
				Rotation = Vector3.new(0, 0, 90),
				Color = Color3.fromRGB(150, 48, 40),
				Material = Enum.Material.Metal,
			},
			{
				Shape = "Cylinder",
				Size = Vector3.new(0.6, 3.95, 3.95),
				Offset = Vector3.new(5.4, 1.6, 0),
				Rotation = Vector3.new(0, 0, 90),
				Color = Color3.fromRGB(58, 22, 18),
				Material = Enum.Material.Metal,
			},
			{
				Shape = "Cylinder",
				Size = Vector3.new(0.6, 3.95, 3.95),
				Offset = Vector3.new(5.4, 3.6, 0),
				Rotation = Vector3.new(0, 0, 90),
				Color = Color3.fromRGB(58, 22, 18),
				Material = Enum.Material.Metal,
			},
		},
	},

	--[[ THE BOOM -- the first obstacle you are meant to BREAK.

		Everything else splits cleanly in two: cheap things that tumble off the bonnet (cone,
		barrel, crate) and walls you must not touch (barrier, concrete). This is neither. It shuts
		34 studs of road in a single object -- more than two lanes, and the widest thing in the
		game -- but it is an arm on a stand, so it snaps. Going round costs you your lane position;
		going through costs 30 HP. That trade IS the kind, and it is why this breaks at a damage
		number nothing else breaks at.

		`SpeedKeep` is kinder than the barrier's for the same reason: you swat the arm off its
		stand rather than hitting a wall, so a boom takes the run out of your health bar and not
		out of your speed. ]]
	Barrier2 = {
		Damage = 30,
		SpeedKeep = 0.7,
		SideKick = 8,
		Yaw = 0.6,
		Shake = 1.4,
		-- Broken, not tumbled: the arm snaps off its stands and the pieces go their own ways, which
		-- is what "you swat it off" looks like. Tumbling the whole gantry away as one body read as
		-- the entire gate being weightless.
		Smash = { Force = 0.9, Break = true, Spread = 0.6 },
		--[[ 22 across for the same reason the barricade is 10: `Art.Width` scales the prop whole,
			and its own 34-stud span put the striped arm 10.6 studs up — a gantry the car would fit
			UNDER rather than a gate it has to answer. At 22 the arm crosses at 6.8, roughly a car's
			roofline, which is the height that makes it read as shut.

			A narrower boom re-cuts both boom courses, and they are re-authored below to match: a
			22-wide arm can no longer close half a road by itself, so `boomWeave` shuts each half
			with a PAIR and `boomGate` splits its middle with a cone. Change this number and those
			two courses have to be re-measured, not just re-read.

			Depth is 3.6 against a prop nearer 6.6, because most of that 6.6 is the splayed feet of
			the two stands -- flat on the deck, well under the HitBox's lower edge, and not something
			the car can reach. Same reasoning as the cone's base plate. ]]
		HitSize = Vector3.new(22, 5, 3.6),
		Art = { Model = "Barrier2", Width = 22, Yaw = 90 },
		-- Fallback: a striped arm across two stands, at the same 22-stud span, so a world with no
		-- boom art still threads `boomGate` and `boomWeave` exactly as they are authored.
		Build = {
			{
				Shape = "Block",
				Size = Vector3.new(2.2, 0.6, 2.6),
				Offset = Vector3.new(-10.7, 0.3, 0),
				Color = Color3.fromRGB(68, 70, 74),
				Material = Enum.Material.Metal,
			},
			{
				Shape = "Block",
				Size = Vector3.new(1.2, 5.6, 1.2),
				Offset = Vector3.new(-10.7, 2.8, 0),
				Color = Color3.fromRGB(150, 152, 156),
				Material = Enum.Material.Metal,
			},
			{
				Shape = "Block",
				Size = Vector3.new(2.2, 0.6, 2.6),
				Offset = Vector3.new(10.7, 0.3, 0),
				Color = Color3.fromRGB(68, 70, 74),
				Material = Enum.Material.Metal,
			},
			{
				Shape = "Block",
				Size = Vector3.new(1.2, 5.6, 1.2),
				Offset = Vector3.new(10.7, 2.8, 0),
				Color = Color3.fromRGB(150, 152, 156),
				Material = Enum.Material.Metal,
			},
			{
				Shape = "Block",
				Size = Vector3.new(22, 1.8, 1.4),
				Offset = Vector3.new(0, 5.2, 0),
				Color = Color3.fromRGB(236, 236, 232),
				Material = Enum.Material.SmoothPlastic,
			},
			{
				Shape = "Block",
				Size = Vector3.new(3.6, 1.9, 1.5),
				Offset = Vector3.new(-7.2, 5.2, 0),
				Color = Color3.fromRGB(196, 58, 48),
				Material = Enum.Material.SmoothPlastic,
			},
			{
				Shape = "Block",
				Size = Vector3.new(3.6, 1.9, 1.5),
				Offset = Vector3.new(0, 5.2, 0),
				Color = Color3.fromRGB(196, 58, 48),
				Material = Enum.Material.SmoothPlastic,
			},
			{
				Shape = "Block",
				Size = Vector3.new(3.6, 1.9, 1.5),
				Offset = Vector3.new(7.2, 5.2, 0),
				Color = Color3.fromRGB(196, 58, 48),
				Material = Enum.Material.SmoothPlastic,
			},
		},
	},

	--[[ === WORLD 2 — THE DESERT ==============================================================

		A SEPARATE SET, NOT A RESKIN. Everything above is world 1's: cones, barrels, barricades,
		concrete — road furniture, the things a city road puts in your way. None of it appears in
		the desert, and none of the desert's kinds appear in the city. The two sets never mix
		because the difficulty ramp is per MAP (`TiersByMap` below): a map's ramp names only its
		own courses, and a course names only its own kinds.

		THERE ARE NO `Build` FALLBACKS DOWN HERE, and that is deliberate rather than unfinished.
		The world-1 kinds carry primitives because they were authored before the art existed and
		had to keep working without it; every desert kind is built FROM the modeller's delivered
		model (`Workspace.Assets.World2`), so a kind with no art has nothing to draw and is skipped
		rather than replaced by a box that belongs to a different world. See
		`ObstacleController._buildObstacle`.

		WHAT THE SET IS MADE OF, and the read it is trying to teach. Almost nothing in the desert
		is tall, so height cannot be the signal the way it is in the city — COLOUR is:

		  GREEN IS CHEAP, BROWN IS EXPENSIVE, PALE YELLOW COSTS NO HP AT ALL.
		    Tumbleweed   4 HP   the one that MOVES. See `Roll`.
		    Cactus      10 HP   tall, narrow, impossible to miss. The desert's traffic cone.
		    CactusPatch 14 HP   low and wide. Eats a lane; you go round it, not over it.
		    Rock        16 HP   low and wide too, and the same silhouette. Costs nearly double.
		    Boulder     30 HP   the wall element. A row of these is the "find the gap" beat.
		    SandDune     0 HP   soft. Takes your GRIP and your speed, never your health.

		EVERY ONE OF THEM IS DELIVERED YAWED 90 DEGREES, exactly as world 1's props are, so every
		kind down here sets `Art.Yaw = 90` and none of them is optional. Without it the fitter
		measures the model's DEPTH and scales that to `Art.Width` — which is not a subtle 10%
		error: it made the boulders 37 studs across the road instead of 19, half the width of the
		whole drivable corridor. It is invisible on the dune and the tumbleweed, which are
		near-square in plan, and enormous on everything else. Check a new prop's published size
		before trusting it (`ReplicatedStorage.ObstacleProps.<map>`).

		Sizes come off the delivered models, in the model's own frame and therefore in the frame
		the yaw puts on the road (measured 2026-08-28, in studs, W x H x D):
		Ball 9.08 x 8.69 x 8.84, Cactus 7.49 x 13.11 x 4.10, Cactus2 17.48 x 3.67 x 10.36,
		Rock 12.87 x 2.67 x 10.18, Rocks2 16.04 x 4.87 x 8.25, SandDune 15.23 x 5.32 x 15.23.
		Every one of them is a SINGLE MeshPart, which is why no desert kind sets `Smash.Break`:
		there is nothing inside them to come apart, so they all leave as one body. ]]

	--[[ THE TUMBLEWEED — the first obstacle in the game that is not standing still.

		Every other kind is a fixed point on the road: it is at lane N and it stays there, so the
		only thing that changes between seeing it and reaching it is you. This one is the
		opposite. It is the cheapest thing in the desert to actually hit — 4 HP, less than a
		traffic cone — and the most annoying to plan around, because the gap you picked at 200
		studs is not the gap that is there when you arrive.

		`Roll` is what makes that happen. It is read by `ObstacleController._updateRollers` and by
		nothing else, and it is the only field in this file that moves an obstacle after it has
		been built. The motion is PURELY CLIENT-SIDE decoration over a hit the server still prices
		from the authored lane — `Sway` below is the one place the two are coupled. ]]
	Tumbleweed = {
		--[[ Four. It is a dead bush: it should cost less than a cone, because the hazard is where
			it PUT you and not what it took off you. ]]
		Damage = 4,
		SpeedKeep = 0.97,
		SideKick = 2.5,
		Yaw = 0.14,
		Shake = 0.3,
		-- The lightest thing in the game, so it gets the biggest throw in the file: it should
		-- clear the roof. One mesh, so no `Break` — it leaves whole, which is what a bush does.
		Smash = { Force = 1.6 },
		HitSize = Vector3.new(6.2, 6.4, 6.2),
		Art = { Model = "Ball", Width = 7, Yaw = 90 },
		--[[ HOW IT MOVES. A sine across the road, a bounce on top of it, and a roll rate derived
			from the sway, so the ball is always turning at the speed it is travelling rather than
			spinning on the spot.

			`Sway` IS THE ONE NUMBER THE SERVER ALSO READS. `ObstacleService._laneIsPlausible`
			rejects a reported hit whose lane the car was nowhere near, and a weed that wanders is
			by definition not at its authored lane when you hit it — so that check widens its
			tolerance by exactly this. Raise it and the server gets correspondingly more forgiving
			about where a tumbleweed hit may be claimed from; past about 15 the band starts to
			cover lanes the weed can never reach, which is the point where this stops being
			decoration and starts being a hole. 11 studs is most of the way to the next lane and
			nowhere near the one after it.

			`Speed` is radians per second, so a crossing and back takes 2*pi/Speed — about 7
			seconds at 0.9, roughly 600 studs at cruise. Deliberately slower than you close on it:
			you should be able to read which way it is going and aim at where it will not be.

			`Radius` is what it rolls ON, and it is half the FITTED height (`Width` 7 puts the ball
			at 6.7 tall), not half the model's authored height. Too small spins it faster than it
			travels, too large drags it — either way it skids instead of rolling. ]]
		Roll = {
			Sway = 11,
			Speed = 0.9,
			Hop = 1.2,
			-- Bounces per radian of sway. Three per crossing reads as wind-blown; much more and it
			-- looks like it is being dribbled.
			HopRate = 3.1,
			Radius = 3.35,
		},
	},

	--[[ THE SAGUARO — the desert's traffic cone, and the only tall thing in the set.

		At `Width` 6.5 it stands 11.4 studs against a 6-stud car, nearly twice the height the
		world-1 barricade was deliberately cut DOWN to. That is not the same mistake: a barricade
		taller than the car reads as scenery that has wandered onto the road, and a cactus taller
		than the car reads as a cactus. The height is what makes it legible at 85 studs/s in a
		world with no buildings to size anything against.

		The hit volume is the TRUNK and a little either side, not the arm span — the arm is at
		roof height and there is nothing on the car that can reach it. ]]
	Cactus = {
		Damage = 10,
		SpeedKeep = 0.9,
		SideKick = 4,
		Yaw = 0.22,
		Shake = 0.45,
		Smash = { Force = 1 },
		HitSize = Vector3.new(4.6, 7.5, 3.4),
		Art = { Model = "Cactus", Width = 6.5, Yaw = 90 },
	},

	--[[ THE PATCH — low, wide and green, which is the whole read: it is the cheap half of the
		"same silhouette, different price" pair it forms with `Rock`.

		13 studs of hit volume under a 15-stud visual eats most of a lane, so the answer to one is
		always to go round it rather than to pick a side of it. Being soft, it goes a good deal
		further than a rock does when you do not. ]]
	CactusPatch = {
		Damage = 14,
		SpeedKeep = 0.84,
		SideKick = 6,
		Yaw = 0.3,
		Shake = 0.7,
		Smash = { Force = 1.15 },
		HitSize = Vector3.new(13, 4.5, 8),
		Art = { Model = "Cactus2", Width = 15, Yaw = 90 },
	},

	--[[ THE ROCK FIELD — the expensive half of that pair. Half a dozen low domes strewn across 13
		studs of road, at almost exactly the patch's height and width, and the only difference you
		can see at speed is that it is brown.

		That pairing IS the desert's lesson, standing in for world 1's "walls are white and cones
		are orange": down here you read a hazard by colour, because there is no height to read it
		by. Hitting one costs 16 and barely moves it — `Force` 0.4 is the lowest throw in the
		file, because a car does not punt a rock. ]]
	Rock = {
		Damage = 16,
		SpeedKeep = 0.74,
		SideKick = 8,
		Yaw = 0.42,
		Shake = 0.95,
		Smash = { Force = 0.4 },
		HitSize = Vector3.new(11, 4.5, 9),
		Art = { Model = "Rock", Width = 13, Yaw = 90 },
	},

	--[[ THE BOULDERS — the desert's wall, and the only kind here authored to be laid in a ROW.

		13 studs of hit volume on the 15-stud lane grid leaves 2 studs between neighbours: nothing
		fits (the shared HitBox alone is 8.43), so a row of these is genuinely shut. The 19-stud
		VISUAL meanwhile overlaps its neighbours, so the same row reads as one continuous pile of
		rock instead of four separate objects standing suspiciously far apart. Same split as the
		boom's 22-wide volume under a wider prop, for the same reason.

		The daylight those two numbers buy is what every wall course below is cut against:
		`boulderGate` leaves 17 studs down the middle, `boulderGapLeft`/`Right` leave 15.2 at the
		shoulder. Change either number and all four have to be re-measured, not just re-read. ]]
	Boulder = {
		Damage = 30,
		SpeedKeep = 0.56,
		SideKick = 10,
		Yaw = 0.6,
		Shake = 1.4,
		-- It shoves clear of the bumper and drops; it does not sail. Same argument as `Concrete`.
		Smash = { Force = 0.45 },
		HitSize = Vector3.new(13, 5.5, 7.5),
		Art = { Model = "Rocks2", Width = 19, Yaw = 90 },
	},

	--[[ THE SAND DRIFT — the desert's answer to the oil slick, and the reason the desert does not
		simply inherit `Oil`.

		Same job: cost no HP, take the car's grip, and let whatever is 130 studs further on do the
		actual damage (`duneDrift`). Two differences, and both come from it being SAND:

		  IT SLOWS YOU DOWN. Oil keeps your speed exactly (`SpeedKeep` 1) because a puddle is a
		  frictionless film. A drift is a foot of loose sand and ploughing through it should cost
		  something — 0.86 is a shove in the back, well short of the 0.74 a rock takes.

		  IT CAN BE SEEN ON ITS OWN. Oil needs a drum standing beside it because a dark puddle on
		  dark asphalt is invisible at 85 studs/s. A 6-stud dune of pale sand across a road is the
		  most legible object in this set, which is why it is the hazard the desert can afford to
		  open with rather than hold back.

		`Damage = 0` is load-bearing exactly as it is on `Oil`: the server still consumes the id,
		so driving through one is correctly not a dodge, and it skips the HP write entirely rather
		than publishing a zero subtraction to everything watching Health. ]]
	SandDune = {
		Damage = 0,
		SpeedKeep = 0.86,
		--[[ 8 rather than oil's 10. The break-away wants to be smaller here because the drift is
			already slowing you: two hands on the car at once reads as a collision, which is the
			exact failure the oil kick was cut from 26 to fix. ]]
		SideKick = 8,
		-- Zero, for oil's reason: an external yaw write is erased inside one frame by the lean
		-- servo that holds the nose in direct steering. The wag comes from `DriveConfig.Slick`.
		-- Read `Oil.Yaw` in full before touching this.
		Yaw = 0,
		Shake = 0.5,
		--[[ It slumps, it does not fly. A cone of sand punted twenty studs down the road is the
			silliest thing this system could draw, so `Force` sits below even `Concrete`'s 0.5. ]]
		Smash = { Force = 0.3 },
		-- Narrower and shallower than the 17 x 17 visual, because a drift feathers out to nothing
		-- at its edges and clipping the feather is not something you would feel.
		HitSize = Vector3.new(13, 5.5, 11),
		--[[ Kinder than oil's 0.35/1.6 on both dials, because sand is taking speed off you at the
			same time and the courses it appears in are cut for a car that is slowing as it
			slides. ]]
		Slick = {
			Duration = 1.4,
			Grip = 0.4,
		},
		Art = { Model = "SandDune", Width = 17, Yaw = 90 },
	},

	--[[ === WORLD 3 — THE MOUNTAINS ===========================================================

		Read the desert block above first: the no-`Build` rule, the `Art.Yaw = 90` rule and the
		"a map's ramp names its own courses" seam are all set out there and all apply here
		unchanged. The art is `Workspace.Assets.World3`, the map is `Forest Mountains`.

		WHAT THIS WORLD IS FOR. The city taught you objects. The desert added one that MOVES. Up
		here the thing trying to end your run is the ROAD, and every other kind in the set exists
		to give the ice something to throw you into. That is why this is the only world whose
		free hazard is the very first thing it shows you (`iceGlide`, tier 1) rather than
		something held back to tier 2.

		Sizes off the delivered models, in the frame the yaw puts them on the road, W x H x D
		(measured 2026-08-28):
		Ice 15.16 x 0.29 x 12.67, Snowpile 22.88 x 6.74 x 19.96, SnowWall 14.01 x 1.88 x 9.62,
		Trunk 22.91 x 4.03 x 8.90, SnowBarrier 17.19 x 9.73 x 3.72, IceWall 12.79 x 5.44 x 5.83.

		Unlike the desert's, two of these have MORE THAN ONE PART — SnowBarrier is five and
		SnowWall is two — so those two are the first delivered props in the game that `Smash.Break`
		can do its real job on. The other four are single meshes and leave whole. ]]

	--[[ BLACK ICE — the third slick, and the first one that is not a weaker version of the other
		two.

		Oil and sand both say "you answer the wheel slowly". Ice says something else: you keep
		doing whatever you were already doing. That is not a metaphor, it is exactly what the drive
		model does with a near-zero `Grip`, and it is worth reading `DriveController._lane` to see
		why, because it is the one place this hazard is genuinely different in kind:

		    self._lateral += (want - self._lateral) * (1 - math.exp(-dt * laneAccel * grip))

		`laneAccel` is scaled by the grip, so at grip ~0 the second term vanishes and `_lateral` —
		the car's cross-road velocity — simply does not change. Not "changes slowly toward the
		centre": does not change. Whatever sideways speed you carried onto the sheet is the
		sideways speed you carry off it. Arrive dead straight and black ice is free. Arrive halfway
		through a lane change and you are going to finish that lane change whether or not there is
		anything in the way.

		THAT IS WHY THE COURSES BELOW PUT SOMETHING BEFORE THE ICE and not just after it.
		`oilTrap` and `duneDrift` are two-beat courses — slick, then a wall — because with oil and
		sand the hazard is that you cannot correct. Here the hazard is your own line, so
		`blackIceTrap` is three beats: something that MAKES you swerve, then the ice that keeps the
		swerve, then the wall the swerve was always going to reach.

		MEASURED, against the same bench the oil numbers came off (LaneAccel 11, LaneSpeed 34).
		Studs of road crossed from straight with the wheel hard over, dry road in brackets:

		    at 0.4s      at 0.8s      at 1.2s
		    oil    7.8   oil   20.2   oil   33.8    (dry: 11.4 / 24.4 / 38.0)
		    ice    3.1   ice   12.5   ice   25.4

		So in the half-second where you notice you are on it, oil leaves you 69% of your steering
		and ice leaves you 28%. By a second you have half your wheel back. It is a hard lock that
		fades, not a long soft one. ]]
	BlackIce = {
		--[[ Zero, and the server reads it, exactly as it does on `Oil`: the id is still consumed
			(sliding across a sheet is not a dodge) and the HP write is skipped entirely. ]]
		Damage = 0,
		-- Ice is frictionless. Oil keeps your speed for the same reason; sand does not, because
		-- sand is not.
		SpeedKeep = 1,
		--[[ FIVE, and it is the SMALLEST of the three slicks on purpose (oil 10, sand 8). On oil
			the kick is the hazard — it puts you somewhere and you fight your way back. Here the
			kick is only the thing that stops you arriving perfectly straight, because what happens
			next is decided by your line and not by the shove. A kick the size of oil's would
			decide it FOR you, which is a worse hazard and a much less interesting one: the whole
			point is that you drove yourself into it. ]]
		SideKick = 5,
		-- Zero, for the reason `Oil.Yaw` gives at length: the lean servo erases an external yaw
		-- write inside one frame. The wag comes from `DriveConfig.Slick`.
		Yaw = 0,
		Shake = 0.4,
		--[[ NO `Smash`, and it is the only kind in the game that wants none. Everything else is an
			object standing on the road and the argument in the Smash header applies — hitting a
			thing that does not flinch is the loudest "did that register?" there is. This is not an
			object. It is a sheet of ice 0.33 studs thick painted onto the deck, the car drives
			OVER it rather than into it, and the reaction is the slide. Knocking it away would peel
			the road surface up over the bonnet. ]]
		--[[ 14 x 12 under a 17 x 14 visual. A drift feathers and a spill feathers; a frozen puddle
			has a hard edge, so this is closer to its visual than the other two slicks are —
			trimmed only enough that clipping the last stud of the rim does not take the car off
			you. `Y` is 5 for `Oil`'s reason: the sheet is a third of a stud tall and the car's
			HitBox does not start until 0.96 above the deck, so a volume sized to the ART could
			never be touched at all. ]]
		HitSize = Vector3.new(14, 5, 12),
		--[[ The lock itself. `Grip` is a FRACTION OF your steering, not a reduction by it — read
			`Oil.Slick` before touching either number, and read the measurement in the header
			above before touching this one in particular.

			0.05 rather than 0: a sliver of authority left means the wheel is never quite dead, and
			"dead controls" is the exact failure that took oil from 0.15 to 0.35. Two things make
			the far lower number honest here that were not true of oil when that call was made.
			The fishtail (`DriveConfig.Slick`) now exists, so something on screen says why. And a
			pale blue sheet on black asphalt is legible from a long way off, where a dark puddle on
			dark asphalt was not — oil needed a drum standing next to it to be readable at all.
			You can see this one coming, which is what earns it the right to be this severe.

			2.0 seconds is about 170 studs at cruise and the longest window in the game. The
			recovery is LINEAR (DriveController._grip), so the duration is also what sets how fast
			the wheel comes back: lengthening it does not just extend the slide, it makes the early
			lock-out shallower per second. Shortening it does the opposite. The pair moves
			together — do not treat these as two independent dials. ]]
		Slick = {
			Duration = 2.0,
			Grip = 0.05,
		},
		Art = { Model = "Ice", Width = 17, Yaw = 90 },
	},

	--[[ THE DRIFT — soft, and the one kind in the game that takes your SPEED rather than your
		health.

		8 damage is less than a traffic cone, and 0.66 is the heaviest speed cut in the file by a
		distance (concrete, the hardest thing in world 1, keeps 0.5 but also charges 35). That
		split is the kind: ploughing a snowbank is not a crash, it is a stop. It reads as the one
		thing on the road you are allowed to be careless about, which is exactly why the courses
		use it as the SAFE answer to a harder question — see `barrierGate`. ]]
	Snowpile = {
		Damage = 8,
		SpeedKeep = 0.66,
		SideKick = 5,
		Yaw = 0.25,
		Shake = 0.6,
		-- It bursts forward off the bumper. Single mesh, so no `Break` to give it; the throw is
		-- doing all the work and it is the biggest one in the set for a reason.
		Smash = { Force = 1.2 },
		HitSize = Vector3.new(14, 5.5, 12),
		Art = { Model = "Snowpile", Width = 18, Yaw = 90 },
	},

	--[[ THE RIDGE — a low shelf of broken ice, and the world-3 half of the "same silhouette,
		different price" pair the desert made out of the cactus patch and the rock field.

		Here the two are the drift above and this: both low, both pale, both wide, and this one
		costs half again as much and barely moves when you hit it. Ice is not snow. Two parts, so
		it is one of only two kinds whose `Break` has real pieces to cut. ]]
	SnowWall = {
		Damage = 12,
		SpeedKeep = 0.78,
		SideKick = 7,
		Yaw = 0.35,
		Shake = 0.8,
		Smash = { Force = 0.7, Break = true, Spread = 0.5 },
		HitSize = Vector3.new(13, 4.5, 9),
		Art = { Model = "SnowWall", Width = 16, Yaw = 90 },
	},

	--[[ THE FALLEN TREE — 17 studs of road shut by one object, which makes it the widest single
		thing in the game after world 1's boom (22).

		It is the boom's shape of problem without the boom's answer: a gantry arm snaps and this
		does not, so there is no paying your way through it. `Force` 0.35 is near the bottom of the
		file — a car at 85 studs/s does not move a tree — and 20 damage is what you pay for finding
		that out.

		BEING 17 WIDE IS WHY IT IS NEVER LAID IN A ROW. Two of them on the 15-stud lane grid leave
		13 studs down the middle, under the 14 the Courses header asks for, so every course below
		uses them singly or strung along the road (`logJam`). Change `HitSize.X` and check that
		claim again before pairing them. ]]
	Trunk = {
		Damage = 20,
		SpeedKeep = 0.7,
		SideKick = 9,
		Yaw = 0.5,
		Shake = 1.1,
		Smash = { Force = 0.35 },
		HitSize = Vector3.new(17, 4.5, 4.5),
		Art = { Model = "Trunk", Width = 20, Yaw = 90 },
	},

	--[[ THE BARRICADE — world 3's wall element, and the best thing in the game to hit.

		Five separate parts (a striped board, two legs, a brace and the drift of snow sitting on
		top of it), so `Break` finally has a real assembly to cut: the board goes one way, the legs
		another, and the snow comes off the top of it as its own piece. Everything else in both new
		worlds is a single mesh that can only ever leave as one body.

		11 studs of hit volume on the 15-stud grid leaves 4 between neighbours — nothing fits, the
		HitBox alone is 8.43 — so a row is shut, while the 13-stud visual stands them close enough
		to read as one closed road. It fits to 7.4 tall, the tallest wall in the game, and that is
		the point of choosing it over the ice block: you cannot see what is behind it. ]]
	SnowBarrier = {
		Damage = 26,
		SpeedKeep = 0.6,
		SideKick = 9,
		Yaw = 0.55,
		Shake = 1.3,
		Smash = { Force = 0.9, Break = true, Spread = 0.7 },
		HitSize = Vector3.new(11, 6, 3),
		Art = { Model = "SnowBarrier", Width = 13, Yaw = 90 },
	},

	--[[ THE ICE BLOCK — the late-run heavy, and world 3's `Concrete`.

		A solid slab of glacier at roof height. It breaks nothing and goes nowhere (`Force` 0.4,
		below concrete's 0.5), and at 34 it is the second most expensive hit in the game. Where the
		barricade hides what is behind it, this one does not need to: it is meant to be seen from a
		long way back and steered around, and the 17-stud gate `iceGate` leaves is a real line. ]]
	IceWall = {
		Damage = 34,
		SpeedKeep = 0.5,
		SideKick = 11,
		Yaw = 0.65,
		Shake = 1.6,
		Smash = { Force = 0.4 },
		HitSize = Vector3.new(13, 6.5, 6),
		Art = { Model = "IceWall", Width = 15, Yaw = 90 },
	},

	--[[ === WORLD 4 — THE ARCTIC ==============================================================

		Art is `Workspace.Assets.World4`; the map is `Arctic`. The no-`Build` rule from the desert
		block applies.

		THESE ARE YAWED LIKE EVERYTHING ELSE, and the way that was nearly missed is worth writing
		down because it will happen again. Every PART in this set reports an orientation of zero, so
		a per-part rotation check says "not yawed" — but it is the model's PIVOT that is turned, and
		`Model:GetBoundingBox` reports in the pivot's frame, so the box comes back already un-turned
		and looks right too. Both of the obvious checks agree, and both are wrong.

		The one that is not wrong is the WORLD AABB, because that is what `_fitProp` measures:
		Guardrail's pivot box is 22.82 x 8.84 x 5.79 and its world extent is 5.79 x 8.84 x 22.82 —
		X and Z swapped. Published without a yaw it came out 16 wide, 24.4 TALL and 63 deep.

		AND THE RULE ITSELF IS NOT "ALWAYS 90". `Art.Yaw` is not a fact about how the prop was
		delivered, it is a decision about WHICH AXIS YOU WANT ACROSS THE ROAD: the fitter puts the
		model's world-X on the cross axis, and 90 swaps X and Z. Every prop so far is drawn with
		its long axis on world Z, so anything that should SPAN the road — a barrier, a wall, a
		beam, a patch — takes 90, and that is nearly all of them. Anything that should POINT down
		the road does not, and the futuristic city's holograms are exactly that: they are cars, and
		a car yawed 90 is a car lying sideways across your lane.

		WHAT THIS WORLD IS FOR, and it is the one world whose answer is "nothing new". The city
		taught you objects, the desert added one that moves, the mountains took the road away.
		The arctic is a rockfall: the heaviest damage numbers in the game, the tightest gaps, and
		no trick at all. A player arriving here has met every idea the game has; what is left is
		whether they can drive.

		Sizes off the delivered models, W x H x D (measured 2026-08-28):
		Boulder2 3.31 x 3.42 x 3.27, Boulder1 6.22 x 5.23 x 6.22, Boulders 12.63 x 5.56 x 9.11,
		Bridge 12.94 x 2.73 x 10.31, Asphalt 18.01 x 0.37 x 10.96, Guardrail 22.82 x 8.84 x 5.79.
		All but the guardrail are single meshes; it is three parts, so it is the only kind here
		`Smash.Break` has anything to cut. ]]

	--[[ THE SLICK THAT IS ALLOWED TO BE GENTLE — a stretch of the road surface that has broken up
		and frozen over.

		LEGIBILITY SETS SEVERITY, and this is the clearest case of that rule in the file. Black ice
		is brutal (grip 0.05) because it is a pale blue sheet you can see from 200 studs. Oil sits
		in the middle and needed a drum standing beside it to be readable at all. This prop is a
		near-black plate (27, 42, 53) lying flat on a dark road — the least visible hazard in the
		game — so it gets the gentlest numbers in the family and is a nuisance rather than a
		killer. Half your steering for a second is something you can drive out of; anything more
		would be a hit you never had the information to avoid.

		It is also the only slick that does all three things at once — some grip, some speed, and a
		shove — which is the right shape for the last world's surface hazard: no new idea, just
		everything you have already met arriving together. ]]
	BrokenRoad = {
		Damage = 0,
		SpeedKeep = 0.85,
		SideKick = 6,
		-- Zero, for `Oil.Yaw`'s reason. The wag comes from `DriveConfig.Slick`.
		Yaw = 0,
		Shake = 0.4,
		-- No `Smash`: it is the road surface, not a thing standing on it. Same argument as
		-- `BlackIce`.
		HitSize = Vector3.new(15, 5, 10),
		--[[ The gentlest slick in the game, and the shortest. One second is about 85 studs, which
			is inside a single course rather than across two — so unlike `oilTrap`, `duneDrift` and
			`blackIceTrap` this one is never authored with a wall waiting at the far end of it.
			See the header for why it is allowed to be this mild. ]]
		Slick = {
			Duration = 1.0,
			Grip = 0.5,
		},
		Art = { Model = "Asphalt", Width = 18, Yaw = 90 },
	},

	-- The cheap one: a single rock, roughly the size of a traffic cone's problem and priced like
	-- one. Fits to 5.2 tall, so unlike the desert's rubble you can actually see it coming.
	Scree = {
		Damage = 6,
		SpeedKeep = 0.93,
		SideKick = 3,
		Yaw = 0.2,
		Shake = 0.4,
		Smash = { Force = 1 },
		HitSize = Vector3.new(4.2, 5, 4.2),
		Art = { Model = "Boulder2", Width = 5, Yaw = 90 },
	},

	-- One rock the size of the car's nose. Not a wall and not a pebble: the kind you take on the
	-- chin when the line you wanted is gone.
	IceBoulder = {
		Damage = 14,
		SpeedKeep = 0.8,
		SideKick = 6,
		Yaw = 0.35,
		Shake = 0.75,
		Smash = { Force = 0.7 },
		HitSize = Vector3.new(6.5, 6, 6.5),
		Art = { Model = "Boulder1", Width = 7.5, Yaw = 90 },
	},

	--[[ A slab of the mountain that came down flat: 13.5 studs of hit volume at 3.4 tall. The low
		one, and the cheaper half of the pair it makes with `Rockfall` — same grey, same width,
		half the height and two thirds the damage. Height is the read here, which is the opposite
		of the desert's pair (where the read was colour) and deliberately so: there is only one
		colour up here. ]]
	Slab = {
		Damage = 18,
		SpeedKeep = 0.72,
		SideKick = 8,
		Yaw = 0.45,
		Shake = 1,
		Smash = { Force = 0.45 },
		HitSize = Vector3.new(13.5, 4.5, 10),
		Art = { Model = "Bridge", Width = 16, Yaw = 90 },
	},

	-- The pile that came down with it: as wide as the slab and twice as tall, so it hides what is
	-- behind it and costs accordingly.
	Rockfall = {
		Damage = 22,
		SpeedKeep = 0.66,
		SideKick = 9,
		Yaw = 0.5,
		Shake = 1.2,
		Smash = { Force = 0.5 },
		HitSize = Vector3.new(13, 6, 9),
		Art = { Model = "Boulders", Width = 15, Yaw = 90 },
	},

	--[[ THE WALL — a section of crash barrier torn off the edge of the road and left across it.

		13 studs of hit volume on the 15-stud grid leaves 2 between neighbours, so a row is shut,
		under a 16-stud visual that overlaps into one continuous rail. It fits to 6.2 tall, right
		at the car's roofline, which is the height the world-1 barricade was tuned to and for the
		same reason: tall enough to hide the gap until you are close, short enough to belong on the
		road.

		32 damage makes it the second heaviest thing in the game, behind world 3's ice block. That
		is the arctic's whole difficulty argument — there is no `Concrete` up here doing 35 and no
		trick either, just a wall that costs a third of your health every time you get the gap
		wrong. Three parts, so it comes apart when you do. ]]
	Crashrail = {
		Damage = 32,
		SpeedKeep = 0.55,
		SideKick = 10,
		Yaw = 0.6,
		Shake = 1.5,
		Smash = { Force = 0.8, Break = true, Spread = 0.6 },
		HitSize = Vector3.new(13, 6, 4),
		Art = { Model = "Guardrail", Width = 16, Yaw = 90 },
	},

	--[[ === THE FUTURISTIC CITY — AUTHORED, NOT YET LIVE =======================================

		Art is `Workspace.Assets.FuturisticCity`; the map is `Workspace.Worlds.FuturisticCity`,
		which is the fifth themed road and the one WorldConfig describes as "parked, not orphaned":
		there are five roads and four ladders, so nothing points at this map yet.

		THAT MEANS THIS SET IS INERT AND THAT IS FINE. `ObstacleService._publishProps` walks
		`WorldConfig.Worlds`, so a map with no world entry has no props published and
		`ObstacleLayout.tiersFor` is never called with its name. Everything below is authored,
		audited and unreachable until someone adds `Map = "FuturisticCity"` to a world (or appends
		a fifth — WorldConfig's note explains that it prices cleanly). Nothing here can affect a
		live run before then. These props are yawed 90 like every other set; see the arctic block
		above for the two checks that say otherwise and are both wrong.

		WHY IT IS WORTH AUTHORING NOW. Three of these seven do something no obstacle in the game
		has done before, and two of them needed new machinery that this file and
		`ObstacleController` now carry (`Boost` and `Pass` — see the Kinds legend at the top):

		  THE PADS GIVE INSTEAD OF TAKE. Every other kind in every other world subtracts something.
		  A boost pad adds speed and pays your nitro bottle back; a gravity lift throws the car in
		  the air. They are obstacles in the layout's sense — they have an id, a lane and a hit
		  volume — and the thing you want is to hit them.

		  THE HOLOGRAMS ARE LIES. A ghost car sits in a lane looking exactly like the thing you
		  have spent three worlds learning to swerve for, and passes straight through you. On its
		  own that is a joke; among the SOLID traffic cars TrafficController is already putting on
		  the same road, it is a real question, and swerving out of the way of a hologram into a
		  car that is not one is the funniest way to lose a run this game has.

		Sizes off the delivered models, W x H x D (measured 2026-08-28):
		Pad 13.24 x 1.30 x 12.88, Gravity 19.71 x 15.03 x 19.36, Mine 9.38 x 2.55 x 9.38,
		Laser 214.91 x 14.20 x 14.20, Sign 20.83 x 7.64 x 2.88, Holo1 35.48 x 11.05 x 13.33,
		Holo2 32.15 x 12.17 x 13.96.

		NOT ONE NUMBER BELOW HAS BEEN DRIVEN. The geometry is measured and the mechanics are
		verified to fire, but the FEEL of a boost, a launch and a landing is the one thing a bench
		cannot tell you. Treat every number in `BoostPad` and `GravityLift` as a first guess. ]]

	--[[ THE BOOST PAD — the first obstacle in the game you are meant to aim AT.

		Two payouts, and they are deliberately different in kind. `Speed` is immediate and brief:
		it goes straight into the assembly's velocity and the chassis pulls it back to the car's
		own top speed over the next second or so, so it reads as a shove in the back rather than a
		new cruise. `Nitro` is the one you keep — a third of a bottle handed to `NitroController`,
		which is the same currency `NearMissController` already pays out in, so a pad is worth
		about three near misses and a player already knows what that is worth.

		The pad does NOT run the impact beat: no shove, no yaw, no camera shake, no smoke and no
		police strike (see `Pass` in the Kinds legend). Being rewarded should not feel like being
		hit, and the strike report in particular would have a boost pad counting toward an arrest
		during a chase, which is absurd. ]]
	BoostPad = {
		Damage = 0,
		-- Untouched. A pad has no business editing speed through the impact path; `Boost.Speed`
		-- below is the only thing here that moves the car.
		SpeedKeep = 1,
		SideKick = 0,
		Yaw = 0,
		--[[ Small, and it is the one part of the impact beat a pad keeps — `_boost` applies it
			directly. A kick in the back with a perfectly still camera reads as a bug; this is a
			bump, well under the 0.35 a traffic cone gives. ]]
		Shake = 0.25,
		-- No `Smash`: you drive over it and it stays for the next person. It is street furniture
		-- that works, not something you broke.
		Boost = {
			--[[ Studs/s added along the road. Cruise is about 85 (see DriveConfig), so 30 is a bit
				over a third again and lands the car somewhere it cannot reach on throttle alone.
				It bleeds off on its own; there is no window to configure because the chassis's own
				top speed is the window. ]]
			Speed = 30,
			--[[ Fraction of a FULL nitro tank, in `NitroController.reward`'s currency. 0.35 is
				three near misses. Rewarding the bottle rather than a longer speed burst is what
				makes a pad worth taking a bad line for: the speed is now, the nitro is when you
				choose. ]]
			Nitro = 0.35,
		},
		-- Wider than the 15-stud visual is not possible here — this is one flat plate and the
		-- whole of it is the pad, so unlike a cone's base there is nothing to trim off. Y is 5
		-- because the plate is 1.5 tall and the car's HitBox does not start until 0.96 up.
		HitSize = Vector3.new(14, 5, 13),
		--[[ 270, not the 90 the rest of this set takes. The delivered chevrons point along world +X,
			and 90 turns +X to face BACK up the road (`_fitProp`'s turn, then the client's `base`,
			whose +Z is forward), so the pads told you to reverse. The fit is unchanged: a half
			turn leaves the footprint's box exactly where 90 put it. ]]
		Art = { Model = "Pad", Width = 15, Yaw = 270 },
	},

	--[[ THE GRAVITY LIFT — a ring of anti-grav that throws the car into the air.

		`Boost.Lift` writes the car's vertical velocity, and the two consequences are worth being
		explicit about because neither is coded for anywhere:

		  YOU FLY OVER THINGS. The hit poll is one overlap of the car's HitBox against the
		  obstacle volumes, and those volumes are 5 to 6.5 studs tall standing on the deck. A car
		  12 studs up is not overlapping any of them, so a launch clears low obstacles for free.
		  Nothing had to be written to make that true and nothing should be written to stop it —
		  it is the reason to build a course around one.

		  THE LANDING IS A FALSE WALL SCRAPE WAITING TO HAPPEN. `_checkWall` works by overlapping
		  a widened HitBox against the road itself, so a suspension bottoming out on landing reads
		  as a guardrail. That is exactly what `Wall.SettleTime` exists for after a car is set
		  down, and `_boost` re-uses it: it holds the scrape check off for the flight time it just
		  bought plus the usual settle. ]]
	GravityLift = {
		Damage = 0,
		SpeedKeep = 1,
		SideKick = 0,
		Yaw = 0,
		Shake = 0.5,
		Boost = {
			--[[ Studs/s straight up, SET rather than added (`_boost`), so taking a second lift
				while still rising cannot stack into orbit — verified: a lift taken at 200 up
				leaves the car at 200, not 262.

				62 MEASURES AT 7.0 STUDS OF APEX, not the 9.8 the ballistics give: the car is a
				sprung assembly and eats about a third of it. That still clears every hit volume in
				the game (the tallest is 6.5) with the HitBox's own 0.96 floor on top, and it is
				the number `liftJump` is cut against — read that course before changing this,
				because raising it moves the landing further from the lift and re-cuts the whole
				thing. ]]
			Lift = 62,
			-- A little forward with it, so the arc goes somewhere rather than straight up and
			-- down. Nowhere near the pad's 30 — this is a jump, not a launch down the road.
			Speed = 8,
		},
		-- The ring's opening, on the deck. The floating blocks above it are art and are well over
		-- the car's head.
		HitSize = Vector3.new(14, 5, 14),
		Art = { Model = "Gravity", Width = 18, Yaw = 90 },
	},

	--[[ THE HOLOGRAMS — two ghost cars, and the only kinds in the game the car passes straight
		through.

		`Pass` (see the Kinds legend) means no HP, no shove, no shake, no smoke, no police strike
		and no smash: the obstacle is consumed, so it correctly stops counting as a dodge, and
		absolutely nothing else happens. They are `Damage = 0` as well, which is what the server
		reads; `Pass` is what the CLIENT reads, and both have to say so.

		Two of them because the trick is a silhouette trick and one silhouette is a tell. They are
		sized against the real thing — the roster's bodies run 8.5 to 12.9 wide — rather than
		against their own art, which is drawn at truck scale. ]]
	Hologram = {
		Damage = 0,
		SpeedKeep = 1,
		SideKick = 0,
		Yaw = 0,
		Shake = 0,
		Pass = true,
		HitSize = Vector3.new(10, 6, 20),
		--[[ NO YAW, and these two are the only props in the game that want none — see the arctic
			block's note. A hologram is a CAR: its long axis belongs down the road, which is where
			the model already has it. Yawed, it lies across the road like a barricade, and the
			trick it is here to play stops working the moment it stops looking like traffic.
			Width 11 is the roster's own median body (9.6) plus a little, which fits it at about
			9 tall and 29 long — a van rather than a hatchback, because that is what was drawn. ]]
		Art = { Model = "Holo1", Width = 11 },
	},
	Hologram2 = {
		Damage = 0,
		SpeedKeep = 1,
		SideKick = 0,
		Yaw = 0,
		Shake = 0,
		Pass = true,
		HitSize = Vector3.new(10, 6, 20),
		-- No yaw, for `Hologram`'s reason.
		Art = { Model = "Holo2", Width = 11 },
	},

	--[[ THE MINE — small, flat, and the most expensive thing per stud of road it occupies.

		9 studs wide against a barricade's 11, and it costs more. That inversion is the point: it
		is the one hazard here you could drive past without noticing and the one you least want to
		find. Three parts, so it comes apart. ]]
	Mine = {
		Damage = 28,
		SpeedKeep = 0.62,
		SideKick = 10,
		Yaw = 0.6,
		Shake = 1.5,
		Smash = { Force = 1.3, Break = true, Spread = 0.9 },
		HitSize = Vector3.new(8, 5, 8),
		Art = { Model = "Mine", Width = 9, Yaw = 90 },
	},

	--[[ THE LASER — 28 studs of road shut by a beam two studs thick.

		The widest hit volume in the game after world 1's boom, and the only one with no mass
		behind it: it is a line across the road, so it hides nothing and can be read from as far
		away as you can see it. That is what lets it be this wide — the difficulty is entirely the
		crossing, never the surprise.

		The prop is delivered 215 studs long, so `Art.Width` is doing a lot of work here (scale
		0.14) and the beam ends up about 2 studs thick. It sits ON the deck like everything else
		the fitter grounds, which reads as a tripwire rather than a gate; that is a deliberate
		acceptance, not an oversight, because a beam at bumper height would need the fitter to
		learn about vertical offsets for one prop. ]]
	Laser = {
		Damage = 30,
		SpeedKeep = 0.6,
		SideKick = 9,
		Yaw = 0.5,
		Shake = 1.4,
		-- It is light. A beam knocked off its line should whip away rather than shove and drop.
		Smash = { Force = 1.1 },
		HitSize = Vector3.new(28, 4.5, 3),
		Art = { Model = "Laser", Width = 30, Yaw = 90 },
	},

	--[[ THE NEON SIGN — the futuristic city's wall element.

		12 studs of hit volume on the 15-stud grid leaves 3 between neighbours, so a row is shut,
		and it fits to 5.1 tall — a shade under the roofline, which is the shortest wall in the
		game. It is meant to be: this world's difficulty is the pads and the lies, not the walls,
		and a wall you can see over keeps the attention on what is past it. ]]
	NeonSign = {
		Damage = 24,
		SpeedKeep = 0.62,
		SideKick = 9,
		Yaw = 0.55,
		Shake = 1.25,
		Smash = { Force = 0.9, Break = true, Spread = 0.7 },
		HitSize = Vector3.new(12, 5.5, 2.5),
		Art = { Model = "Sign", Width = 14, Yaw = 90 },
	},

	--[[ === THE WEATHER'S OWN ==================================================================

		Kinds that no course names and no ramp deals. They are laid by the WEATHER, in a pass of their
		own over whichever road it is raining on (`ObstacleConfig.Puddles`), so they reach every map
		without a single tier pool being edited. Their art lives in the shared
		`Assets.<Puddles.SourceFolderName>` rather than in a world's folder for the same reason: the
		rain falls on all four roads. ]]

	--[[ THE PUDDLE: the rain's slick, and the gentlest one in the game on every dial.

		The same shape of hazard as `Oil`: it costs no HP and takes the car's grip for a beat. About
		half of one, because nobody authored it. A course is placed so that you can read it and plan
		a line through it; a puddle is weather, it lies wherever the rain left it, and it can be
		sitting in the lane you were already committed to. So it has to be survivable without a plan:

		    oil      grip 0.35 for 1.6s, kick 10 away from it, the full fishtail
		    puddle   grip 0.6  for 1.0s, a pull of up to 4 toward it, half the fishtail

		IT IS NOT A CRASH, which is why it has a beat of its own (`Splash`). Everything oil does runs
		through `ObstacleController.applyImpact`, which puffs smoke, punches the camera and bites the
		police bar. A puddle does none of that. It throws water.

		THE SERVER NEVER HEARS ABOUT IT (`Local`). It costs nothing, the server has no copy of where
		the rain put it (the weather pass is the client's alone, see `Puddles`), and a report it could
		not check would only spend the hit rate cap. That is also why a puddle is not a dodge in
		`ObstacleService.clearedFor`: it is not in the layout that function counts. ]]
	Puddle = {
		Damage = 0,
		--[[ The water's drag on the tyres, and the only thing it does to your speed. Oil keeps all of
			it (a film) and sand takes 14% (a foot of it); a puddle is an inch of water. ]]
		SpeedKeep = 0.97,
		--[[ THE PULL, and it points the other way from every other kind's kick: TOWARD the water. A car
			with one side's tyres in a puddle is dragged toward that side, which is what actually
			happens, and it is what makes clipping the edge of one feel different from driving through
			the middle of it. Scaled by how far off centre the car is (`ObstacleController._splash`):
			dead centre, both sides drag alike and it pulls nothing. At the rim it is 4, the smallest
			kick in the file and still over the 1.5 floor `DriveController._lane` needs to notice it. ]]
		SideKick = 4,
		-- Zero, for `Oil.Yaw`'s reason. The wag is `Slick.Wobble`'s share of `DriveConfig.Slick`.
		Yaw = 0,
		--[[ A bump, and the only piece of an impact a puddle keeps. Under a cone's 0.35, and it never
			reaches the police: `Splash` skips `applyImpact`, which is where the strike is taken. ]]
		Shake = 0.2,
		Local = true,
		-- No `Smash`: it is water lying on the road and the car drives through it. `BlackIce`'s reason.
		--[[ 11 x 9 under a pool of about 16 x 13 at `Scale` 1: water feathers out at its rim, and
			running the last two studs of a wet edge is not something you would feel. `Y` is 5 for
			`Oil`'s reason. `ObstacleController._dressPuddle` scales X and Z with the puddle. ]]
		HitSize = Vector3.new(11, 5, 9),
		--[[ About half an oil slick. Read `Oil.Slick` before touching either of the first two: `Grip` is
			a FRACTION of your steering, and the recovery is linear across `Duration`, so the pair moves
			together.

			`Wobble` is this slick's share of the fishtail (`DriveConfig.Slick.WobbleDeg`), which every
			other slick takes in full. The wag is what a player reads the severity off, and at 1 a
			puddle would have wagged the tail as far as black ice does. ]]
		Slick = {
			Duration = 1.0,
			Grip = 0.6,
			Wobble = 0.5,
		},
		--[[ THE SPRAY: the tell that you just went through water, thrown out of both flanks at road height
			and left hanging as the car drives out of it. The library's soft smoke sheet in white-blue,
			the same one the Soaked mutation's spray is made of, so wet reads one way everywhere.

			`Count` is per flank at `CountAtSpeed` (cruise), scaled by the speed you hit it at, so
			crawling through a puddle barely splashes and flying through one throws a sheet of it.

			Sized in a frozen race frame (2026-09-15). The first pass (9 a flank, 1.6 to 4.4 studs,
			70% opaque) was two specks at the front wheels from the chase camera; this is a soft sheet
			off each flank that trails back along the car and is gone inside a second. ]]
		Splash = {
			Texture = "rbxassetid://13975880803",
			Count = 14,
			CountAtSpeed = 85,
			Lifetime = { 0.5, 0.9 },
			Speed = { 12, 24 },
			Spread = 30,
			--- Degrees the throw leans out from straight up, toward its own flank.
			Tilt = 50,
			Size = { 2.4, 6.5 },
			Transparency = { 0.15, 1 },
			Color = Color3.fromRGB(214, 232, 248),
			Gravity = 50,
			Drag = 1.5,
			--[[ The share of the car's velocity the spray leaves with. High, so it hangs beside the car
				for a beat and then peels off, rather than streaming back through the chase camera,
				which is what the Ghost mutation's smoke did at 0.55. ]]
			Inherit = 0.8,
			--- A SoundGroup in SoundService, played at the car (`SoundController:PlayRandomAt`). Nil
			--- for silence.
			Sound = nil :: string?,
		},
		--[[ THE RIPPLES: rings opening on the water where the rain lands in it. This is what says WATER
			rather than "a darker patch" from the driving seat, and it is why a puddle can afford to be
			subtler than oil's red drum. Flat on the surface and pinned to it (so a tile recycle or a
			rebase carries them), and switched off the moment the rain stops, so a puddle the storm
			left behind lies still until its tile dries it.

			`Footprint` is the share of the hit volume's footprint a ring may open in, which keeps them
			on the water rather than on the tarmac beside it.

			The library's thin broken ring (`FinalWindTest`), flat. At the first pass's 0.3 to 2.4
			studs and 65% opaque the rings were invisible from anywhere but straight overhead; at these
			numbers they read from above as rain landing in water and from the chase camera as a
			glitter on the surface, which is all a pool at that angle can show. ]]
		Ripples = {
			Texture = "rbxassetid://14850595833",
			Rate = 12,
			Lifetime = { 0.6, 0.9 },
			Size = { 0.5, 3.6 },
			Transparency = { 0.1, 1 },
			Color = Color3.fromRGB(236, 244, 252),
			Glow = 0.3,
			Footprint = 0.9,
			--- Studs above the deck: the puddle's own surface.
			Lift = 0.32,
		},
		--[[ World 3's `Ice` sheet, reskinned as water (`BuildPuddleProp`): it is already the right
			shape, a flat irregular pool. 16 across at `Scale` 1, and every puddle is also turned to a
			random angle and sized within `Puddles.Scale`, so no two on one road are the same stamp.

			Its Glass is the DAYLIGHT look. Glass shows the sky, and under the thunderstorm's night it
			showed nothing, so that event dresses every puddle in a `Water` of its own
			(`WeatherConfig`, the storm's `Puddles`). ]]
		Art = { Model = "Puddle", Width = 16, Yaw = 90 },
		-- Fallback for a place without the art: a round sheet of the same water.
		Build = {
			{
				Shape = "Cylinder",
				Size = Vector3.new(0.2, 13, 13),
				Offset = Vector3.new(0, 0.1, 0),
				Rotation = Vector3.new(0, 0, 90),
				Color = Color3.fromRGB(58, 70, 84),
				Material = Enum.Material.Glass,
				Transparency = 0.25,
			},
		},
	},
}

-- === Smash ==================================================================
--[[ WHAT HAPPENS TO THE THING YOU HIT, which used to be a boolean and is now three dials.

	Under the old `KnockAway`, cones and barrels tumbled off the bonnet and everything heavier
	stood there, untouched, while the car drove through it. That is the loudest "did that even
	register?" in the game: every other half of a hit -- the shove, the yaw, the shake, the smoke,
	the HP -- happens to the CAR, and the object is the only thing the player is actually looking
	at when they hit it.

	Per kind, `Smash` reads over the base throw below:
	  Force   scales the whole throw. 1 is a cone off the bonnet; 0.5 is a lump of concrete that
	          shoves clear and drops rather than sails.
	  Break   cut the prop's welds first, so it comes apart into its own pieces instead of leaving
	          as one body. Only worth setting on a prop that HAS more than one piece -- with the
	          primitive fallbacks that is most of them, and the delivered art runs 2-6.
	  Spread  how differently each broken piece leaves, 0..1. At 0 they all go the same way and
	          read as one object shoved; at 1 they scatter.
	A kind with no `Smash` at all is the old `false`: it stops counting and nothing moves.

	ONLY THE PIECES THE CAR COULD HAVE REACHED ARE THROWN, and that rule is what makes `Break`
	safe on a hazard that is partly painted onto the road. `Floor` is the HitBox's own lower edge
	above the deck, so anything shorter than it was never in front of the car -- it was under it.
	The oil slick is the case that needs this: its drum flies, its two flat sheets of spill stay
	exactly where they were, and nothing peels the puddle off the road.

	None of this replicates and none of it can touch the run: the props are client-local geometry
	built from the seed, so a smash is pure decoration over a hit the server has already priced. ]]
ObstacleConfig.Smash = {
	-- Fraction of the car's velocity a piece leaves with -- this is what makes debris travel WITH
	-- you for a beat instead of stopping dead behind you at 85 studs/s.
	Carry = 0.55,
	-- Studs/s straight up, so a piece clears the bonnet rather than skidding along under the car.
	Lift = 22,
	-- Studs/s away from the car, along the flat line from the car to what it hit.
	Push = 12,
	-- Studs/s of random per-piece spread at `Spread = 1`.
	Scatter = 14,
	-- +/- rad/s of tumble.
	Spin = 8,
	-- Studs above the deck. A piece whose top sits under this never moves: the HitBox's lower edge
	-- is 0.96 above the deck, so nothing shorter than that is something the car can touch.
	Floor = 0.96,
	-- Seconds before the pieces are cleaned up. They never collide, so they fall through the road
	-- and out of shot well before this; it is a leak guard, not a timing.
	Life = 3,
}

-- === Impact smoke ===========================================================
-- The wreck plume's little sibling: a short puff off the flank that got hit, for obstacle clips
-- and wall scrapes alike (both run through ObstacleController.applyImpact, so one setting
-- covers both). Same `Smoke` effect as the wreck, just smaller and brief.
--
-- Severity is read off each hit's `Shake` value, which is already the "how big does this feel"
-- dial for everything else — so a cone barely puffs, concrete throws a real cloud, and there's
-- no second severity number per hazard to keep in sync. Current Shake spread: cone 0.35, wall
-- 0.5, barrel 0.7, crate 0.8, barrier 1.2, concrete 1.6.
ObstacleConfig.HitSmoke = {
	Enabled = true,

	-- Same effect as the wreck plume (Opacity 0.35 / RiseVelocity 12 / Size 8), lightened a shade
	-- because a small puff of the wreck's near-black barely separates from the asphalt. Set this
	-- back to Color3.fromRGB(38, 38, 42) if you'd rather it match the wreck exactly.
	Color = Color3.fromRGB(105, 103, 99),
	Opacity = 0.5,
	RiseVelocity = 11,

	-- Smoke.Size and emission time, interpolated between the weakest and strongest hit. Keep
	-- MaxSize under the wreck's 8 so a bad clip still doesn't read as a blown engine.
	MinSize = 2.5,
	MaxSize = 6.0,
	MinTime = 0.45,
	MaxTime = 1.1,
	-- The `Shake` value that earns a full-size puff. Anything at or above this maxes out.
	ShakeForFullPuff = 1.6,

	-- Where the puff sits. It's placed at the point on the car's bounding box that the hit came
	-- from — nose for a head-on, flank for a side-swipe, corner for a corner — then pushed this
	-- far past it into open air, and lifted clear of the sill.
	--
	-- Two bugs' worth of history here, both about placing it inside the car:
	--   1. Sized off the HitBox, which is the chassis's narrow mid-height hull (8.43 wide) and
	--      NOT the car you can see (10.36 wide). The puff landed 1.56 studs inside the mesh.
	--   2. Placed on a flank regardless of where the hit came from, because the impact code only
	--      knows a left/right `side`. Head-on hits puffed out of the door.
	-- Both are why this is measured from `car:GetBoundingBox()` along the actual hit direction.
	SurfaceOffset = 0.4, -- studs beyond the car's surface, along the direction the hit came from
	HeightOffset = 1.2, -- studs above the HitBox centre
}

-- === The wall ===============================================================
-- The road's guardrails are real, solid geometry — the one exception to "nothing here
-- collides", and deliberately so: physically containing the car on the road is the road's
-- job, and we leave that alone. What this block adds is the *cost* of riding the rail, using
-- the same chip damage and impact feel an obstacle gives you, ticking for as long as you
-- scrape rather than once.
--
-- Detection is a contact test against a purpose-built sensor volume. Two earlier attempts failed,
-- both worth knowing about because the road's edges are not what they look like:
--
--  1. A distance-from-the-edge threshold NEVER FIRED. `DriveWidth` is a *nominal* corridor width
--     measured to the outer rail line, not to the surface the car stops against. Nominal
--     half-width 36.73 minus a 4.22 car half-width put the trigger at |offset| = 32.01, but the
--     car is physically blocked at +31.80 / -29.30 — the threshold sat inside solid geometry.
--  2. Querying the `Guardrails` model only fired on ONE SIDE. The two edges are built
--     differently: eastbound the car is stopped by a *wheel* touching a guardrail at +31.80,
--     but westbound it's the HitBox hitting a raised kerb that belongs to `RoadSurface`, 2.5
--     studs INSIDE the guardrail line — so the rails are never reached on that side at all.
--
-- What works: shadow the car's HitBox with a query-only volume `Margin` studs wider on each side
-- and overlap it against the whole road tile with RespectCanCollide, which catches any raised
-- boundary geometry whatever it's called. The HitBox band (deck+0.96..deck+2.72) never reaches
-- the deck, and every obstacle part is CanCollide=false, so neither can register.
--
-- Use GetPartsInPart, NOT GetPartBoundsInBox: the latter is a bounding-box test, and the tile's
-- diagonal cable props have enormous AABBs that produce hits right across the middle of the road.
ObstacleConfig.Wall = {
	Enabled = true,

	-- Studs the sensor reaches past each flank of the car. Sized so a scrape registers just
	-- before the car is physically stopped: at 0.5 it fires at +31.34 / -28.76 against blocking
	-- at +31.80 / -29.30, and measured zero false hits anywhere in the -28..+30 drivable band
	-- sampled along the whole tile. It has to be more than a hair, because eastbound the wheel
	-- that does the blocking sits 0.03 studs outboard of the HitBox flank.
	Margin = 0.5,
	-- Seconds between ticks while you stay out there. `Damage / Cooldown` is the real knob:
	-- 4 per 0.5s = 8 HP/s, so grinding the rail costs a 100 HP car about 12 seconds of life —
	-- punishing, but survivable long enough to correct.
	Cooldown = 0.5,

	--[[ Seconds after the car is SET DOWN on the road before a scrape can register again.

		A car never arrives already sitting on its springs. `RaceService` holds it anchored while
		the client builds its local road, and the frame it lets go the body drops onto its
		suspension and bottoms out: measured at entry, the HitBox falls from its deck+0.96 ride
		height to roughly 1.4 studs INSIDE the deck, and takes ~1.1s to rebound. While it is down
		there the sensor is overlapping the deck itself — which is precisely what this test reads
		as "you are against a boundary". So every entry could charge two or three rail scrapes,
		kick the car sideways, shake the camera and puff smoke, before the player had the wheel.

		The band this check relies on (deck+0.96..deck+2.72, above) is only true of a SETTLED car,
		so the honest fix is to wait for one rather than to narrow the sensor — the west edge is a
		raised kerb that BELONGS to `RoadSurface` (see 2. above), so there is no "ignore the road
		surface" version of this test that still fires on both sides.

		Timed from the frame the car is unanchored, which is the same beat for all three ways a car
		is put on the road — entering, being revived, and landing a steal — so all three get the
		grace without having to know about each other.

		1.5 covers the measured rebound with room to spare and costs nothing: every one of those
		three set-downs leaves the car in the middle of the road, nowhere near a rail. ]]
	SettleTime = 1.5,

	-- Same field names as a Kind above, so the impact runs through the same code path.
	Damage = 4,
	SpeedKeep = 0.88,
	SideKick = 8,
	-- NOTE the yaw kick here points the nose AWAY from the wall — the opposite of an obstacle
	-- clip, which kicks it toward the hazard. Nose-in against a solid rail would just hold the
	-- car there and turn a scrape into a death sentence. See ObstacleController.applyImpact.
	Yaw = 0.2,
	Shake = 0.5,
}

-- === Courses ================================================================
-- One authored obstacle pattern. `Length` is the stretch of road it owns (the ramp adds
-- a gap after it); `Items` are placed at `Along` studs into that stretch, in `Lane`.
-- `Nudge` is optional and moves one item off the lane grid, in studs across the road
-- (+ towards lane 5). Lanes are a coarse 15 apart, so it is the only way to cut a gap
-- between two NEIGHBOURING items that is anything other than 15 minus their widths.
-- Rule of thumb: never fully block the road — always leave one lane-ish (>=14 studs) of
-- daylight, against the ~10.5-wide car the Lanes note above explains. An oil slick is the one
-- thing exempt from that, since driving into one costs no HP.
ObstacleConfig.Courses = {
	-- --- warm-up: one thing to notice ---
	warmup = {
		Length = 70,
		Items = {
			{ Kind = "Cone", Lane = 3, Along = 0 },
		},
	},
	conePair = {
		Length = 100,
		Items = {
			{ Kind = "Cone", Lane = 2, Along = 0 },
			{ Kind = "Cone", Lane = 4, Along = 40 },
		},
	},

	-- --- mid: forces a line choice ---
	--[[ The two crates are the left-of-centre blockage, and the answer is the left shoulder or a
		swing out to the right. THE MIDDLE USED TO BE A LIAR. On the bare lane grid the pair sat
		15 apart with 6.3-wide hit volumes, so the gap down the middle was 8.7 studs against a
		HitBox that is 8.43 wide: threadable on paper, 0.13 studs of clearance a side in practice,
		and every body bolted over that HitBox is wider still (median 9.6). It read as a line and
		paid out as a hit. The inner crate is nudged 8 studs out, which makes it 16.7 -- the
		narrowest gap the game already asks you to thread (`boomGate`) and a real margin for the
		~10.5-wide car the Lanes note is cut for. Both authored lines are untouched: the left
		shoulder is still 18.6 studs of daylight and the right side is still wide open. ]]
	crateRow = {
		Length = 120,
		Items = {
			{ Kind = "Crate", Lane = 2, Along = 0 },
			{ Kind = "Crate", Lane = 3, Along = 0, Nudge = 8 },
			{ Kind = "Cone", Lane = 5, Along = 60 },
		},
	},
	barrelRun = {
		Length = 160,
		Items = {
			{ Kind = "Barrel", Lane = 1, Along = 0 },
			{ Kind = "Barrel", Lane = 5, Along = 0 },
			{ Kind = "Barrel", Lane = 3, Along = 80 },
		},
	},
	slalom = {
		Length = 220,
		Items = {
			{ Kind = "Barrel", Lane = 2, Along = 0 },
			{ Kind = "Cone", Lane = 1, Along = 20 },
			{ Kind = "Barrel", Lane = 4, Along = 75 },
			{ Kind = "Cone", Lane = 5, Along = 95 },
			{ Kind = "Barrel", Lane = 2, Along = 150 },
		},
	},
	coneField = {
		Length = 230,
		Items = {
			{ Kind = "Cone", Lane = 1, Along = 0 },
			{ Kind = "Cone", Lane = 4, Along = 25 },
			{ Kind = "Cone", Lane = 2, Along = 60 },
			{ Kind = "Cone", Lane = 5, Along = 85 },
			{ Kind = "Cone", Lane = 3, Along = 120 },
			{ Kind = "Cone", Lane = 1, Along = 150 },
			{ Kind = "Cone", Lane = 4, Along = 175 },
			{ Kind = "Cone", Lane = 2, Along = 200 },
		},
	},

	-- --- walls: the whole road minus one gap ---
	-- gate = gap down the middle (lanes 1,2 and 4,5 walled).
	gate = {
		Length = 130,
		Items = {
			{ Kind = "Barrier", Lane = 1, Along = 0 },
			{ Kind = "Barrier", Lane = 2, Along = 0 },
			{ Kind = "Barrier", Lane = 4, Along = 0 },
			{ Kind = "Barrier", Lane = 5, Along = 0 },
			{ Kind = "Cone", Lane = 3, Along = 70 },
		},
	},
	wallGapLeft = {
		Length = 130,
		Items = {
			{ Kind = "Barrier", Lane = 2, Along = 0 },
			{ Kind = "Barrier", Lane = 3, Along = 0 },
			{ Kind = "Barrier", Lane = 4, Along = 0 },
			{ Kind = "Barrier", Lane = 5, Along = 0 },
		},
	},
	wallGapRight = {
		Length = 130,
		Items = {
			{ Kind = "Barrier", Lane = 1, Along = 0 },
			{ Kind = "Barrier", Lane = 2, Along = 0 },
			{ Kind = "Barrier", Lane = 3, Along = 0 },
			{ Kind = "Barrier", Lane = 4, Along = 0 },
		},
	},
	-- Two half-walls that make you cross the road.
	chicane = {
		Length = 210,
		Items = {
			{ Kind = "Barrier", Lane = 1, Along = 0 },
			{ Kind = "Barrier", Lane = 2, Along = 0 },
			{ Kind = "Barrier", Lane = 3, Along = 0 },
			{ Kind = "Barrier", Lane = 3, Along = 110 },
			{ Kind = "Barrier", Lane = 4, Along = 110 },
			{ Kind = "Barrier", Lane = 5, Along = 110 },
		},
	},
	-- Late-run: same shape as `gate` but in concrete, and it hurts.
	heavyGate = {
		Length = 150,
		Items = {
			{ Kind = "Concrete", Lane = 1, Along = 0 },
			{ Kind = "Concrete", Lane = 2, Along = 0 },
			{ Kind = "Concrete", Lane = 4, Along = 0 },
			{ Kind = "Concrete", Lane = 5, Along = 0 },
			{ Kind = "Barrel", Lane = 3, Along = 80 },
		},
	},
	--[[ --- oil: the courses where nothing that hits you is what kills you ---

		An oil course is two beats: the slick, and the solid thing far enough past it that you are
		still sideways when you get there. On its own a slick is free, so `oilPatch` is the teach
		(three ways through, cones after it to make you commit to one) and `oilTrap` is the exam --
		the two slicks leave about 12 studs of clean road at each shoulder and down the middle for
		a 10.4-wide car, and the barriers 120 studs later sit on the SAME lanes, so the line that
		threads the oil arrives already lined up with the gap. Get slicked and it will not. ]]
	oilPatch = {
		Length = 130,
		Items = {
			{ Kind = "Oil", Lane = 3, Along = 0 },
			{ Kind = "Cone", Lane = 2, Along = 70 },
			{ Kind = "Cone", Lane = 4, Along = 70 },
		},
	},
	oilTrap = {
		Length = 200,
		Items = {
			{ Kind = "Oil", Lane = 2, Along = 0 },
			{ Kind = "Oil", Lane = 4, Along = 0 },
			{ Kind = "Barrier", Lane = 2, Along = 120 },
			{ Kind = "Barrier", Lane = 4, Along = 120 },
		},
	},

	--[[ --- booms: go round, or pay to go through ---

		The wall courses above are threading puzzles with one answer. These are the same shape with
		a second answer bolted on, because a boom breaks: at any point in either of these you can
		stop steering and spend 30 HP instead of finding the gap. Both are wider than the barrier
		courses on purpose -- the difficulty here is meant to be the DECISION, not the gap.

		BOTH ARE MEASURED, not eyeballed, and both had to be re-cut when the boom came down from 34
		studs to 22 (see `Barrier2`). A 22-wide arm on the shoulder lane no longer reaches far
		enough in to make a middle, so:
		  `boomGate` puts a cone in the centre and turns one 38-stud hole into two 16.7-stud gaps,
		  either side of something you may also just flatten for 5 HP.
		  `boomWeave` shuts each half with a PAIR of booms (lanes 1+2, then 4+5) — one arm covered
		  a half-road at 34 wide and covers a third of one at 22 — leaving 40.7 studs open on the
		  far side, and 130 studs to get across to the other one. ]]
	boomGate = {
		Length = 170,
		Items = {
			{ Kind = "Barrier2", Lane = 1, Along = 0 },
			{ Kind = "Cone", Lane = 3, Along = 0 },
			{ Kind = "Barrier2", Lane = 5, Along = 0 },
			{ Kind = "Cone", Lane = 4, Along = 100 },
		},
	},
	boomWeave = {
		Length = 250,
		Items = {
			{ Kind = "Barrier2", Lane = 1, Along = 0 },
			{ Kind = "Barrier2", Lane = 2, Along = 0 },
			{ Kind = "Barrier2", Lane = 4, Along = 130 },
			{ Kind = "Barrier2", Lane = 5, Along = 130 },
		},
	},

	--[[ === WORLD 2 — THE DESERT =============================================================

		The city's courses are above and the desert's are here, in one flat table, because a course
		name is unique across the whole game and `ObstacleLayout` looks it up by name alone. What
		keeps the two sets apart is `TiersByMap` below: the desert's ramp names only these, and the
		city's ramp names only those, so no run ever mixes a cactus into a row of barricades.

		MEASURED THE SAME WAY the city's are. Half-widths of the hit volumes in play here:
		Tumbleweed 3.1, Cactus 2.3, CactusPatch 6.5, Rock 5.5, Boulder 6.5, SandDune 6.5, on the
		15-stud lane grid, against a road that runs +/-36.7 from its centre and a car cut for at
		~10.5 wide. Every daylight quoted below is that arithmetic, not an eyeball. ]]

	-- --- warm-up: one thing to notice, and it is the one that moves ---
	--[[ A tumbleweed alone, dead centre. It is the cheapest hit in the desert (4 HP) and it wanders
		11 studs either side of lane 3, so the first thing a new driver learns down here is that an
		obstacle can come to THEM. Meeting that idea for the first time on the one obstacle that
		barely charges for it is the same argument that put `oilPatch` early in the city. ]]
	weedRoll = {
		Length = 80,
		Items = {
			{ Kind = "Tumbleweed", Lane = 3, Along = 0 },
		},
	},
	cactusPair = {
		Length = 110,
		Items = {
			{ Kind = "Cactus", Lane = 2, Along = 0 },
			{ Kind = "Cactus", Lane = 4, Along = 45 },
		},
	},

	-- --- mid: forces a line choice ---
	--[[ Two rock fields left of centre, and the answer is the left shoulder or a swing right.
		THE NUDGE IS THE WHOLE COURSE, exactly as it is in the city's `crateRow`: on the bare lane
		grid the pair sits 15 apart with 11-wide volumes, leaving 4 studs down the middle — a gap
		that looks like a line and pays out as a hit. Nudged 11 studs out, the inner field sits at
		+11 and the middle opens to 15 studs, which is real against a ~10.5-wide car. The other two
		lines are untouched: 16.2 studs of left shoulder and 20.2 of open road on the right. ]]
	rockRow = {
		Length = 130,
		Items = {
			{ Kind = "Rock", Lane = 2, Along = 0 },
			{ Kind = "Rock", Lane = 3, Along = 0, Nudge = 11 },
			{ Kind = "Cactus", Lane = 5, Along = 70 },
		},
	},
	--[[ Two patches either side of centre: 17 studs down the middle, 15.2 at each shoulder. Three
		honest lines, and the first course that asks you to pick one at speed rather than react. ]]
	patchLine = {
		Length = 150,
		Items = {
			{ Kind = "CactusPatch", Lane = 2, Along = 0 },
			{ Kind = "CactusPatch", Lane = 4, Along = 0 },
			{ Kind = "Cactus", Lane = 3, Along = 80 },
		},
	},
	cactusScatter = {
		Length = 220,
		Items = {
			{ Kind = "Cactus", Lane = 1, Along = 0 },
			{ Kind = "Cactus", Lane = 4, Along = 25 },
			{ Kind = "Cactus", Lane = 2, Along = 60 },
			{ Kind = "Cactus", Lane = 5, Along = 85 },
			{ Kind = "Cactus", Lane = 3, Along = 120 },
			{ Kind = "Cactus", Lane = 1, Along = 155 },
			{ Kind = "Cactus", Lane = 4, Along = 180 },
		},
	},
	--[[ Five tumbleweeds over 230 studs, all sweeping on their own phase. Nothing here costs more
		than 4 HP and the course is nowhere near blocked at any instant — it is an ATTENTION tax,
		and it is the only course in the game whose shape is different every time you drive it. ]]
	weedStorm = {
		Length = 230,
		Items = {
			{ Kind = "Tumbleweed", Lane = 1, Along = 0 },
			{ Kind = "Tumbleweed", Lane = 4, Along = 0 },
			{ Kind = "Tumbleweed", Lane = 2, Along = 80 },
			{ Kind = "Tumbleweed", Lane = 5, Along = 85 },
			{ Kind = "Tumbleweed", Lane = 3, Along = 160 },
		},
	},
	--[[ Sand either side and a tumbleweed rolling through the gap between them. The drift costs no
		HP, so the honest line is straight down the middle — which is exactly where the one thing
		that will not hold still is. Nothing here can end a run; it is the teach for `duneDrift`. ]]
	duneRidge = {
		Length = 170,
		Items = {
			{ Kind = "SandDune", Lane = 2, Along = 0 },
			{ Kind = "SandDune", Lane = 4, Along = 0 },
			{ Kind = "Tumbleweed", Lane = 3, Along = 75 },
		},
	},

	-- --- walls: the whole road minus one gap ---
	--[[ Gap down the middle. Lanes 1 and 2 cover -36.5 to -8.5 and 4 and 5 cover 8.5 to 36.5 —
		2 studs between neighbours, nothing at all outside lane 1 or 5 — so the only way through is
		the 17-stud gate in the centre. The cactus 90 studs later stands just off it, so threading
		the gate is not the end of the course. ]]
	boulderGate = {
		Length = 170,
		Items = {
			{ Kind = "Boulder", Lane = 1, Along = 0 },
			{ Kind = "Boulder", Lane = 2, Along = 0 },
			{ Kind = "Boulder", Lane = 4, Along = 0 },
			{ Kind = "Boulder", Lane = 5, Along = 0 },
			{ Kind = "Cactus", Lane = 3, Along = 90, Nudge = 5 },
		},
	},
	-- 15.2 studs of daylight at the left shoulder, and nothing anywhere else.
	boulderGapLeft = {
		Length = 140,
		Items = {
			{ Kind = "Boulder", Lane = 2, Along = 0 },
			{ Kind = "Boulder", Lane = 3, Along = 0 },
			{ Kind = "Boulder", Lane = 4, Along = 0 },
			{ Kind = "Boulder", Lane = 5, Along = 0 },
		},
	},
	boulderGapRight = {
		Length = 140,
		Items = {
			{ Kind = "Boulder", Lane = 1, Along = 0 },
			{ Kind = "Boulder", Lane = 2, Along = 0 },
			{ Kind = "Boulder", Lane = 3, Along = 0 },
			{ Kind = "Boulder", Lane = 4, Along = 0 },
		},
	},
	-- Two half-walls that make you cross the road: 30.2 studs open on the right, then 30.2 on the
	-- left 115 studs later.
	boulderChicane = {
		Length = 220,
		Items = {
			{ Kind = "Boulder", Lane = 1, Along = 0 },
			{ Kind = "Boulder", Lane = 2, Along = 0 },
			{ Kind = "Boulder", Lane = 3, Along = 0 },
			{ Kind = "Boulder", Lane = 3, Along = 115 },
			{ Kind = "Boulder", Lane = 4, Along = 115 },
			{ Kind = "Boulder", Lane = 5, Along = 115 },
		},
	},

	--[[ THE EXAM, and the desert's `oilTrap` down to the geometry. Two drifts leave 17 studs down
		the middle and 15.2 at each shoulder; the boulders 130 studs later sit on the SAME lanes,
		so the line that threads the sand arrives already lined up with the gap. Get sanded and it
		will not — `SandDune.Slick` runs 1.4 seconds, and 130 studs at cruise is about 1.5, so you
		are still coming back onto the wheel when the rock arrives.

		Note the drift itself cannot end a run: everything that can is 130 studs downstream of it,
		which is what makes this a course you lose rather than a hit you take. ]]
	duneDrift = {
		Length = 210,
		Items = {
			{ Kind = "SandDune", Lane = 2, Along = 0 },
			{ Kind = "SandDune", Lane = 4, Along = 0 },
			{ Kind = "Boulder", Lane = 2, Along = 130 },
			{ Kind = "Boulder", Lane = 4, Along = 130 },
		},
	},
	--[[ Late-run: the wall, with the sand in front of it rather than beside it. Same 17-stud gate
		as `boulderGate`, but you meet it having just been through a drift on the very line that
		threads it — the one course in the desert where a mistake and the thing it costs you are
		only 110 studs apart. ]]
	sandedGate = {
		Length = 200,
		Items = {
			{ Kind = "SandDune", Lane = 3, Along = 0 },
			{ Kind = "Boulder", Lane = 1, Along = 110 },
			{ Kind = "Boulder", Lane = 2, Along = 110 },
			{ Kind = "Boulder", Lane = 4, Along = 110 },
			{ Kind = "Boulder", Lane = 5, Along = 110 },
		},
	},

	--[[ === WORLD 3 — THE MOUNTAINS ===========================================================

		Half-widths of the hit volumes in play here, for checking the arithmetic below: BlackIce 7,
		Snowpile 7, SnowWall 6.5, Trunk 8.5, SnowBarrier 5.5, IceWall 6.5, on the 15-stud lane grid
		against a road that runs +/-36.7 from its centre.

		THE ICE IS EXEMPT FROM THE DAYLIGHT RULE, like every zero-damage hazard — you can shut the
		whole road with it and the worst that happens is you cross it. What the ice cannot be is
		laid CASUALLY, because of what it does (see `BlackIce`): a sheet after a swerve is a
		different course from a sheet on an empty straight, and every placement below is one or the
		other on purpose. ]]

	-- --- warm-up: the road itself ---
	--[[ One sheet, dead centre, with nothing anywhere near it. The only thing that happens is that
		the wheel stops working for a beat on an empty road, which is the whole introduction: it
		costs nothing, there is nothing to hit, and the next time you meet one there will be. ]]
	iceGlide = {
		Length = 90,
		Items = {
			{ Kind = "BlackIce", Lane = 3, Along = 0 },
		},
	},
	snowDrift = {
		Length = 110,
		Items = {
			{ Kind = "Snowpile", Lane = 2, Along = 0 },
			{ Kind = "Snowpile", Lane = 4, Along = 50 },
		},
	},

	-- --- mid: forces a line choice ---
	-- 17 studs down the middle, 15.2 at each shoulder, and a drift in the middle 70 studs on so
	-- the centre line is not free.
	ridgeLine = {
		Length = 150,
		Items = {
			{ Kind = "SnowWall", Lane = 2, Along = 0 },
			{ Kind = "SnowWall", Lane = 4, Along = 0 },
			{ Kind = "Snowpile", Lane = 3, Along = 70 },
		},
	},
	-- One tree across the middle: 28.2 studs open either side of it, then a ridge on the left
	-- shoulder for whoever went that way.
	logRoll = {
		Length = 150,
		Items = {
			{ Kind = "Trunk", Lane = 3, Along = 0 },
			{ Kind = "SnowWall", Lane = 1, Along = 80 },
		},
	},
	--[[ THE LESSON, and it is a nasty one told cheaply. Ice on lanes 2 and 4 leaves the centre
		visibly clean, so the centre is where everyone goes — and 90 studs later the ridge is
		sitting in it. The out is to pick your lane BEFORE the sheets rather than after them, which
		is the one habit this world is trying to build. It costs 12 to get wrong. ]]
	icePatch = {
		Length = 170,
		Items = {
			{ Kind = "BlackIce", Lane = 2, Along = 0 },
			{ Kind = "BlackIce", Lane = 4, Along = 0 },
			{ Kind = "SnowWall", Lane = 3, Along = 90 },
		},
	},
	driftField = {
		Length = 230,
		Items = {
			{ Kind = "Snowpile", Lane = 1, Along = 0 },
			{ Kind = "Snowpile", Lane = 4, Along = 30 },
			{ Kind = "Snowpile", Lane = 2, Along = 75 },
			{ Kind = "Snowpile", Lane = 5, Along = 105 },
			{ Kind = "Snowpile", Lane = 3, Along = 155 },
		},
	},

	-- --- walls: the whole road minus one gap ---
	--[[ 19 studs down the middle — the widest gate in the game, and it is wide because of what is
		standing in it: the drift 90 studs on is the SAFE answer (8 damage, and it stops you dead)
		against a wall that charges 26. Threading the gate and then choosing to eat the snowbank
		rather than swerve is a real decision and the only place in world 3 that offers one. ]]
	barrierGate = {
		Length = 180,
		Items = {
			{ Kind = "SnowBarrier", Lane = 1, Along = 0 },
			{ Kind = "SnowBarrier", Lane = 2, Along = 0 },
			{ Kind = "SnowBarrier", Lane = 4, Along = 0 },
			{ Kind = "SnowBarrier", Lane = 5, Along = 0 },
			{ Kind = "Snowpile", Lane = 3, Along = 90 },
		},
	},
	-- 21.2 studs of daylight at the left shoulder, and nothing anywhere else.
	barrierGapLeft = {
		Length = 140,
		Items = {
			{ Kind = "SnowBarrier", Lane = 2, Along = 0 },
			{ Kind = "SnowBarrier", Lane = 3, Along = 0 },
			{ Kind = "SnowBarrier", Lane = 4, Along = 0 },
			{ Kind = "SnowBarrier", Lane = 5, Along = 0 },
		},
	},
	barrierGapRight = {
		Length = 140,
		Items = {
			{ Kind = "SnowBarrier", Lane = 1, Along = 0 },
			{ Kind = "SnowBarrier", Lane = 2, Along = 0 },
			{ Kind = "SnowBarrier", Lane = 3, Along = 0 },
			{ Kind = "SnowBarrier", Lane = 4, Along = 0 },
		},
	},
	barrierChicane = {
		Length = 220,
		Items = {
			{ Kind = "SnowBarrier", Lane = 1, Along = 0 },
			{ Kind = "SnowBarrier", Lane = 2, Along = 0 },
			{ Kind = "SnowBarrier", Lane = 3, Along = 0 },
			{ Kind = "SnowBarrier", Lane = 3, Along = 115 },
			{ Kind = "SnowBarrier", Lane = 4, Along = 115 },
			{ Kind = "SnowBarrier", Lane = 5, Along = 115 },
		},
	},

	--[[ THE EXAM, and the course the whole world is built around. Three beats where the city's and
		the desert's are two, because black ice punishes the LINE you arrive on and a two-beat
		course cannot give you a line to arrive on.

		  1. Barricades shut lanes 1 and 2. There is 46.2 studs of open road to the right and no
		     other answer, so everybody is moving right when they leave this beat.
		  2. 110 studs on, ice across lanes 3, 4 and 5 — the half you were just pushed into. It
		     costs nothing and it takes the wheel for two seconds, so the rightward drift you
		     arrived with is the drift you keep.
		  3. 100 studs after that, the ice block on lane 5, which is where that drift has been
		     taking you the whole time.

		The out is to be straight BEFORE the sheet: swerve early, settle, cross the ice flat. A
		player who swerves late is still turning when the ice arrives and arrives at the block with
		34 damage and no steering. Everything in this course is legible from the moment the
		barricades come into view — nothing here is a surprise, it is a plan you either make or
		do not. ]]
	blackIceTrap = {
		Length = 270,
		Items = {
			{ Kind = "SnowBarrier", Lane = 1, Along = 0 },
			{ Kind = "SnowBarrier", Lane = 2, Along = 0 },
			{ Kind = "BlackIce", Lane = 3, Along = 110 },
			{ Kind = "BlackIce", Lane = 4, Along = 110 },
			{ Kind = "BlackIce", Lane = 5, Along = 110 },
			{ Kind = "IceWall", Lane = 5, Along = 210 },
		},
	},
	--[[ Two trees strung down the road with a sheet of ice between them. Right of the first, then
		left for the second, and the crossing has to happen either before the ice or after it —
		trying to do it ON the ice is the mistake this course sells. 43.2 studs open at each log,
		so both beats are generous on their own; the course is entirely about the order. ]]
	logJam = {
		Length = 210,
		Items = {
			{ Kind = "Trunk", Lane = 2, Along = 0 },
			{ Kind = "BlackIce", Lane = 3, Along = 60 },
			{ Kind = "Trunk", Lane = 4, Along = 120 },
		},
	},
	-- Late-run: the same 17-stud gate in the heavy stuff, then a tree in the middle of whichever
	-- line you took through it.
	iceGate = {
		Length = 200,
		Items = {
			{ Kind = "IceWall", Lane = 1, Along = 0 },
			{ Kind = "IceWall", Lane = 2, Along = 0 },
			{ Kind = "IceWall", Lane = 4, Along = 0 },
			{ Kind = "IceWall", Lane = 5, Along = 0 },
			{ Kind = "Trunk", Lane = 3, Along = 110 },
		},
	},

	--[[ === WORLD 4 — THE ARCTIC ==============================================================

		Half-widths here: BrokenRoad 7.5, Scree 2.1, IceBoulder 3.25, Slab 6.75, Rockfall 6.5,
		Crashrail 6.5, on the 15-stud grid against a road running +/-36.7.

		THE GAPS ARE THE DIFFICULTY. Every other world has an idea; this one has arithmetic. The
		wall courses below leave the same 17 studs the other worlds do — the rule in the Courses
		header is not negotiable and a last world that cheats it is just an unfair one — but the
		SCATTER courses are cut far tighter than their equivalents elsewhere, and there are more
		beats per course. ]]

	-- --- warm-up ---
	screePair = {
		Length = 100,
		Items = {
			{ Kind = "Scree", Lane = 2, Along = 0 },
			{ Kind = "Scree", Lane = 4, Along = 45 },
		},
	},
	-- The gentle slick, on its own, with nothing to hit. See `BrokenRoad` for why this world's
	-- surface hazard never gets a wall put behind it.
	frozenPatch = {
		Length = 100,
		Items = {
			{ Kind = "BrokenRoad", Lane = 3, Along = 0 },
			{ Kind = "Scree", Lane = 2, Along = 60 },
		},
	},

	-- --- mid ---
	--[[ Two boulders left of centre with the inner one nudged out, same shape of problem as the
		city's `crateRow` and the desert's `rockRow` and cut the same way: 17.5 studs down the
		middle, 18.5 on the left shoulder, 24.5 open on the right. ]]
	boulderRun = {
		Length = 140,
		Items = {
			{ Kind = "IceBoulder", Lane = 2, Along = 0 },
			{ Kind = "IceBoulder", Lane = 3, Along = 0, Nudge = 9 },
			{ Kind = "Scree", Lane = 5, Along = 70 },
		},
	},
	-- Slab either side: 16.5 down the middle, 15.0 at each shoulder.
	slabLine = {
		Length = 150,
		Items = {
			{ Kind = "Slab", Lane = 2, Along = 0 },
			{ Kind = "Slab", Lane = 4, Along = 0 },
			{ Kind = "IceBoulder", Lane = 3, Along = 80 },
		},
	},
	screeField = {
		Length = 230,
		Items = {
			{ Kind = "Scree", Lane = 1, Along = 0 },
			{ Kind = "Scree", Lane = 4, Along = 25 },
			{ Kind = "IceBoulder", Lane = 2, Along = 60 },
			{ Kind = "Scree", Lane = 5, Along = 85 },
			{ Kind = "Scree", Lane = 3, Along = 120 },
			{ Kind = "IceBoulder", Lane = 1, Along = 155 },
			{ Kind = "Scree", Lane = 4, Along = 185 },
		},
	},
	-- The two halves of the pair, one after the other: the low slab, then the tall pile on the
	-- other side of the road. Same grey, same width, and 4 HP apart in what they cost.
	rockslide = {
		Length = 190,
		Items = {
			{ Kind = "Slab", Lane = 2, Along = 0 },
			{ Kind = "Rockfall", Lane = 4, Along = 100 },
			{ Kind = "Scree", Lane = 3, Along = 100 },
		},
	},

	-- --- walls ---
	-- 17 studs down the middle, and a boulder standing just off it 90 studs on.
	railGate = {
		Length = 180,
		Items = {
			{ Kind = "Crashrail", Lane = 1, Along = 0 },
			{ Kind = "Crashrail", Lane = 2, Along = 0 },
			{ Kind = "Crashrail", Lane = 4, Along = 0 },
			{ Kind = "Crashrail", Lane = 5, Along = 0 },
			{ Kind = "IceBoulder", Lane = 3, Along = 90, Nudge = 6 },
		},
	},
	railGapLeft = {
		Length = 140,
		Items = {
			{ Kind = "Crashrail", Lane = 2, Along = 0 },
			{ Kind = "Crashrail", Lane = 3, Along = 0 },
			{ Kind = "Crashrail", Lane = 4, Along = 0 },
			{ Kind = "Crashrail", Lane = 5, Along = 0 },
		},
	},
	railGapRight = {
		Length = 140,
		Items = {
			{ Kind = "Crashrail", Lane = 1, Along = 0 },
			{ Kind = "Crashrail", Lane = 2, Along = 0 },
			{ Kind = "Crashrail", Lane = 3, Along = 0 },
			{ Kind = "Crashrail", Lane = 4, Along = 0 },
		},
	},
	railChicane = {
		Length = 210,
		Items = {
			{ Kind = "Crashrail", Lane = 1, Along = 0 },
			{ Kind = "Crashrail", Lane = 2, Along = 0 },
			{ Kind = "Crashrail", Lane = 3, Along = 0 },
			{ Kind = "Crashrail", Lane = 3, Along = 110 },
			{ Kind = "Crashrail", Lane = 4, Along = 110 },
			{ Kind = "Crashrail", Lane = 5, Along = 110 },
		},
	},
	--[[ The late-run one, and the closest this world comes to a trick. Rockfall walls lanes 1, 2
		and 4, which leaves exactly two lines: 17 studs down the middle and 15.2 at the right
		shoulder. 110 studs on, a slab shuts the middle — so the middle line has to commit, and it
		has the whole left half of the road (30 studs) or that same right shoulder to commit to. A
		driver who took the shoulder at the first beat simply drives through. That is the course:
		one of the two openings is a dead end and the other is not, and which is which is only
		visible once you are past the first wall. ]]
	slideGate = {
		Length = 220,
		Items = {
			{ Kind = "Rockfall", Lane = 1, Along = 0 },
			{ Kind = "Rockfall", Lane = 2, Along = 0 },
			{ Kind = "Rockfall", Lane = 4, Along = 0 },
			{ Kind = "Slab", Lane = 3, Along = 110 },
			{ Kind = "Rockfall", Lane = 4, Along = 110 },
		},
	},

	--[[ === THE FUTURISTIC CITY ================================================================

		Authored against a map nothing points at yet — see the kinds block. Half-widths: BoostPad 7,
		GravityLift 7, Hologram 5.5, Mine 4, Laser 14, NeonSign 6.

		Pads and holograms are all `Damage = 0`, so like every free hazard they are exempt from the
		daylight rule. That exemption does more work here than anywhere else in the file: a course
		can shut the entire road with holograms, and should. ]]

	-- --- warm-up: the two things that are not trying to hurt you ---
	-- One pad, dead centre, on an empty stretch. Nothing to learn except that it is worth aiming
	-- for, which is the one habit this world adds.
	padRun = {
		Length = 110,
		Items = {
			{ Kind = "BoostPad", Lane = 3, Along = 0 },
			{ Kind = "BoostPad", Lane = 2, Along = 60 },
		},
	},
	--[[ THE JOKE, told once, cheaply, before it is ever used against you. Three ghost cars across
		the middle of the road with nothing else anywhere near them: you swerve, or you do not, and
		either way nothing happens. The point is to have met one before `ghostLane` puts one next
		to something real. ]]
	holoDrift = {
		Length = 130,
		Items = {
			{ Kind = "Hologram", Lane = 2, Along = 0 },
			{ Kind = "Hologram2", Lane = 3, Along = 0 },
			{ Kind = "Hologram", Lane = 4, Along = 0 },
		},
	},

	-- --- mid ---
	signPair = {
		Length = 120,
		Items = {
			{ Kind = "NeonSign", Lane = 2, Along = 0 },
			{ Kind = "NeonSign", Lane = 4, Along = 55 },
		},
	},
	--[[ A pad on the shoulder and a mine in the middle, so the fast line and the safe line are the
		same line — the only course here where being greedy is also being right. 32.7 studs of
		daylight either side of the mine. ]]
	minefield = {
		Length = 170,
		Items = {
			{ Kind = "Mine", Lane = 3, Along = 0 },
			{ Kind = "BoostPad", Lane = 1, Along = 0 },
			{ Kind = "Mine", Lane = 2, Along = 90 },
			{ Kind = "Mine", Lane = 4, Along = 90 },
		},
	},
	--[[ THE LIE THAT COSTS. A hologram in lane 2 and a NEON SIGN in lane 4, arriving together:
		swerve away from the ghost and you have swerved into 24 damage. The out is to have learned
		in `holoDrift` that magenta is free, and to look at what is on the other side before
		reacting. There is 45.7 studs of real daylight running from the left shoulder to just past
		the middle, and 15.7 more beyond the sign — the road is wide open, and the course is
		entirely about not flinching. ]]
	ghostLane = {
		Length = 160,
		Items = {
			{ Kind = "Hologram", Lane = 2, Along = 0 },
			{ Kind = "NeonSign", Lane = 4, Along = 0 },
			{ Kind = "Hologram2", Lane = 4, Along = 90 },
			{ Kind = "Mine", Lane = 2, Along = 90 },
		},
	},
	--[[ The laser shuts 28 studs of the middle, leaving 8.7 at each shoulder — which is under the
		14 the rule asks for on BOTH sides, so the laser is deliberately offset by a lane instead:
		at lane 2 it covers -29 to -1 and leaves 37.7 studs of open road to the right. One beam,
		one answer, and it is visible from as far as you can see. ]]
	beamLine = {
		Length = 160,
		Items = {
			{ Kind = "Laser", Lane = 2, Along = 0 },
			{ Kind = "Laser", Lane = 4, Along = 90 },
		},
	},

	-- --- the pads doing real work ---
	--[[ THE JUMP, and the geometry of it is the whole course. A gravity lift, then a minefield
		close enough behind it that you are still in the air over it.

		A LIFT CLEARS LOW THINGS, NOT WALLS, and the window it gives you is much tighter than the
		ballistics suggest. MEASURED on a live car (2026-08-28), not calculated: `Lift` 62 puts the
		HitBox's lower edge above 5 studs — the height of a mine's volume — from about 0.10 to
		0.31 seconds after the pad, apex 7.0 studs, back on the deck at 0.44s and still settling on
		its springs for another quarter second after that.

		A POINT-MASS SUM OVERSTATES ALL OF THAT BY ABOUT A THIRD (it predicts a 9.8-stud apex over
		0.63s), because the car is a sprung assembly on four constraints and not a thrown ball. Do
		not re-derive these numbers, re-measure them: fire `_boost` and log the HitBox's lower edge
		against distance travelled.

		In studs that window is roughly 9 to 27 at cruise and 10 to 32 at the speed the lift's own
		forward kick leaves you at, so the mines sit at 13 and 24 — inside it at BOTH ends of that
		range, with margin. A wall was the obvious thing to jump and is the wrong one: it would
		have to stand inside 30 studs to be cleared, which is a third of a second of warning for
		anyone who missed the pad, and that is an ambush rather than a gap.

		BOTH LINES ARE REAL, which is the test of a pad course. In the air it is free. On the
		ground it is a short slalom: the first mine shuts the middle and leaves 32.7 studs either
		side, and the pair 11 studs later opens the middle back up to 22 with 17.7 at each
		shoulder. Ordinary — no worse than `minefield` and no better. ]]
	liftJump = {
		Length = 170,
		Items = {
			{ Kind = "GravityLift", Lane = 3, Along = 0 },
			{ Kind = "Mine", Lane = 3, Along = 13 },
			{ Kind = "Mine", Lane = 2, Along = 24 },
			{ Kind = "Mine", Lane = 4, Along = 24 },
		},
	},
	--[[ Late-run: a boost pad into a gate you now arrive at 30 studs/s faster than you planned to.
		The pad is on the same lane as the gap, so taking it is free speed and correct — right up
		until the mine 100 studs past the gate, which is the part you now have less time to read. ]]
	overdrive = {
		Length = 230,
		Items = {
			{ Kind = "BoostPad", Lane = 3, Along = 0 },
			{ Kind = "NeonSign", Lane = 1, Along = 80 },
			{ Kind = "NeonSign", Lane = 2, Along = 80 },
			{ Kind = "NeonSign", Lane = 4, Along = 80 },
			{ Kind = "NeonSign", Lane = 5, Along = 80 },
			{ Kind = "Mine", Lane = 3, Along = 180 },
		},
	},
	signGate = {
		Length = 170,
		Items = {
			{ Kind = "NeonSign", Lane = 1, Along = 0 },
			{ Kind = "NeonSign", Lane = 2, Along = 0 },
			{ Kind = "NeonSign", Lane = 4, Along = 0 },
			{ Kind = "NeonSign", Lane = 5, Along = 0 },
			{ Kind = "Hologram", Lane = 3, Along = 90 },
		},
	},
	signChicane = {
		Length = 210,
		Items = {
			{ Kind = "NeonSign", Lane = 1, Along = 0 },
			{ Kind = "NeonSign", Lane = 2, Along = 0 },
			{ Kind = "NeonSign", Lane = 3, Along = 0 },
			{ Kind = "NeonSign", Lane = 3, Along = 110 },
			{ Kind = "NeonSign", Lane = 4, Along = 110 },
			{ Kind = "NeonSign", Lane = 5, Along = 110 },
		},
	},

}

-- === Difficulty ramp ========================================================
-- Tiers are matched in order against the tile index (tile 0 is the tile you spawn on),
-- so `UntilTile` is "this tier applies up to and including this tile". `Gap` is the
-- random breathing room in studs between one course and the next. One tile is ~1173
-- studs, so a tier with 200-stud courses and 150-stud gaps yields ~3 courses per tile.
--
-- THIS ONE IS THE FALLBACK: what a map with no entry in `TiersByMap` below gets, which today is
-- the Arctic alone. It was world 1's too until world 1 was given its own gentler opening (`City`,
-- below); this kept the pacing it had, because a world reached fourth has no business teaching
-- cones again. `TiersByMap` after it is where a world gets a different set of obstacles entirely.
ObstacleConfig.Tiers = {
	{ UntilTile = 1, Pool = { "warmup", "conePair" }, Gap = { 260, 380 } },
	-- `oilPatch` this early on purpose: a slick costs no HP, so the run where you first meet one
	-- is the run you can afford to learn it on.
	{ UntilTile = 3, Pool = { "conePair", "crateRow", "barrelRun", "oilPatch" }, Gap = { 190, 280 } },
	{
		UntilTile = 6,
		Pool = { "crateRow", "barrelRun", "slalom", "gate", "coneField", "oilPatch", "boomGate" },
		Gap = { 140, 220 },
	},
	{
		UntilTile = 10,
		Pool = {
			"slalom",
			"gate",
			"chicane",
			"coneField",
			"wallGapLeft",
			"wallGapRight",
			"oilTrap",
			"boomGate",
			"boomWeave",
		},
		Gap = { 110, 180 },
	},
	{
		UntilTile = math.huge,
		Pool = {
			"slalom",
			"gate",
			"chicane",
			"coneField",
			"wallGapLeft",
			"wallGapRight",
			"heavyGate",
			"oilTrap",
			"boomGate",
			"boomWeave",
		},
		Gap = { 85, 150 },
	},
}

--[[ PER-MAP RAMPS — the seam that keeps two worlds' obstacle sets from ever meeting.

	`ObstacleConfig.Tiers` above is the DEFAULT: it is what a map with no entry here gets, which
	today is the Arctic alone. A map named below gets its own ramp instead, and because a ramp
	names courses and a course names kinds, naming the ramp is all it takes to give a world an
	entirely separate set of obstacles. That is the whole mechanism — there is no per-world flag
	on a kind or a course.

	Keyed by the world's MAP name (`WorldConfig.mapFor`) rather than by world index, for the same
	reason the prop art is: the obstacles belong to the road's theme, so two ladders pointed at one
	map want one ramp between them. `ObstacleLayout.tiersFor` does the lookup, and both the client
	build and the server's hit check go through it — passing the map down from the race's world is
	what keeps the two sides deriving the same layout.

	A map added here with no art in `Workspace.Assets.<Map>` will build nothing at all, because the
	desert kinds have no primitive fallback. That is the intended failure: see the Kinds header. ]]
ObstacleConfig.TiersByMap = {
	--[[ WORLD 1 — the same ramp as the fallback above, stretched over the front of the run because
		this is the road a player has never driven before. Nothing is taken out and nothing new is
		added: every tier keeps the pool the fallback gives it, the thresholds just arrive later
		and the first three tiers breathe a little wider, and the top tier still lands on tile 11
		exactly as it does everywhere else. A first run is easier; a long one ends up in the same
		place.

		WHAT MOVED, tile by tile: tile 0 is now `warmup` alone, so the first obstacle anybody ever
		meets is one cone in the middle lane rather than a coin-flip between that and a pair. Cones
		hold until tile 2 instead of tile 1. The crates, barrels and the first oil slick land on
		tile 3 instead of tile 2, and the first WALL — the thing that can actually end a run — waits
		until tile 5 instead of tile 4. From tile 8 on this ramp and the fallback are identical.

		The top tier deliberately still starts at tile 11, because `TrafficConfig`'s top rung joins
		at tile 10 and the map progress bar is scaled to it (see `topTileFor`): a tier that opened
		past that would be one almost nobody drives far enough to see. ]]
	City = {
		--- The first obstacle of the first run: one cone, dead centre, nothing else on the tile.
		{ UntilTile = 0, Pool = { "warmup" }, Gap = { 320, 460 } },
		{ UntilTile = 2, Pool = { "warmup", "conePair" }, Gap = { 280, 400 } },
		{ UntilTile = 4, Pool = { "conePair", "crateRow", "barrelRun", "oilPatch" }, Gap = { 210, 300 } },
		{
			UntilTile = 7,
			Pool = { "crateRow", "barrelRun", "slalom", "gate", "coneField", "oilPatch", "boomGate" },
			Gap = { 150, 230 },
		},
		{
			UntilTile = 10,
			Pool = {
				"slalom",
				"gate",
				"chicane",
				"coneField",
				"wallGapLeft",
				"wallGapRight",
				"oilTrap",
				"boomGate",
				"boomWeave",
			},
			--- Identical to the fallback's from here up: the stretch is all in the tiers below.
			Gap = { 110, 180 },
		},
		{
			UntilTile = math.huge,
			Pool = {
				"slalom",
				"gate",
				"chicane",
				"coneField",
				"wallGapLeft",
				"wallGapRight",
				"heavyGate",
				"oilTrap",
				"boomGate",
				"boomWeave",
			},
			Gap = { 85, 150 },
		},
	},

	--[[ WORLD 2. Same shape of ramp as the fallback above and deliberately so — the tile
		thresholds and the gaps are identical to it, so a player who has learned to read one
		world's pacing reads the next one's too, and the difficulty of a world is carried by what
		is IN the courses rather than by how often they arrive. (World 1's `City` ramp is the one
		that steps out of line, and only over its front tiles; from tile 8 it is this shape too.)

		What is different is the order things are introduced in. The city opens on cones and holds
		its no-damage hazard back to tier 2; the desert opens on the tumbleweed and brings the sand
		in at tier 2, because both of those are cheap and the two ideas they teach — an obstacle
		that moves, and a hazard that costs grip rather than health — are the two things a city
		driver has never had to deal with. The walls arrive at tier 3 exactly as they do up there. ]]
	Desert = {
		{ UntilTile = 1, Pool = { "weedRoll", "cactusPair" }, Gap = { 260, 380 } },
		{ UntilTile = 3, Pool = { "cactusPair", "rockRow", "patchLine", "duneRidge" }, Gap = { 190, 280 } },
		{
			UntilTile = 6,
			Pool = { "rockRow", "patchLine", "cactusScatter", "weedStorm", "duneRidge", "boulderGate" },
			Gap = { 140, 220 },
		},
		{
			UntilTile = 10,
			Pool = {
				"patchLine",
				"cactusScatter",
				"weedStorm",
				"boulderGate",
				"boulderGapLeft",
				"boulderGapRight",
				"boulderChicane",
				"duneDrift",
			},
			Gap = { 110, 180 },
		},
		{
			UntilTile = math.huge,
			Pool = {
				"cactusScatter",
				"weedStorm",
				"boulderGate",
				"boulderGapLeft",
				"boulderGapRight",
				"boulderChicane",
				"duneDrift",
				"sandedGate",
			},
			Gap = { 85, 150 },
		},
	},

	--[[ WORLD 3. Same thresholds and gaps as the desert and the fallback — a player reads pacing
		once and it holds everywhere above world 1 — and again the difference is the ORDER things
		are introduced in.

		This is the only ramp that opens on a hazard that costs nothing. The city opens on cones
		and the desert on a tumbleweed, because in both of those the first lesson is "there are
		objects on the road". Up here the first lesson is that the road itself is against you, and
		the only honest way to teach the ice is on an empty straight where getting it wrong costs
		nothing at all (`iceGlide`). By tier 2 there is something waiting on the other side of it
		(`icePatch`), and by tier 4 the whole three-beat trap is live. ]]
	["Forest Mountains"] = {
		{ UntilTile = 1, Pool = { "iceGlide", "snowDrift" }, Gap = { 260, 380 } },
		{ UntilTile = 3, Pool = { "snowDrift", "ridgeLine", "logRoll", "icePatch" }, Gap = { 190, 280 } },
		{
			UntilTile = 6,
			Pool = { "ridgeLine", "logRoll", "icePatch", "driftField", "barrierGate", "logJam" },
			Gap = { 140, 220 },
		},
		{
			UntilTile = 10,
			Pool = {
				"driftField",
				"icePatch",
				"logJam",
				"barrierGate",
				"barrierGapLeft",
				"barrierGapRight",
				"barrierChicane",
				"blackIceTrap",
			},
			Gap = { 110, 180 },
		},
		{
			UntilTile = math.huge,
			Pool = {
				"driftField",
				"logJam",
				"barrierGate",
				"barrierGapLeft",
				"barrierGapRight",
				"barrierChicane",
				"blackIceTrap",
				"iceGate",
			},
			Gap = { 85, 150 },
		},
	},

	--[[ WORLD 4. The same thresholds again, and the same argument for keeping them: pacing is a
		thing a player learns once.

		This ramp is the only one with no free hazard in tier 1, because this world's surface
		hazard is a nuisance rather than a lesson (`BrokenRoad`) and there is nothing here that
		needs teaching. Everything in the arctic is something you have already met somewhere else,
		harder. ]]
	Arctic = {
		{ UntilTile = 1, Pool = { "screePair", "frozenPatch" }, Gap = { 260, 380 } },
		{ UntilTile = 3, Pool = { "screePair", "boulderRun", "slabLine", "frozenPatch" }, Gap = { 190, 280 } },
		{
			UntilTile = 6,
			Pool = { "boulderRun", "slabLine", "screeField", "rockslide", "railGate" },
			Gap = { 140, 220 },
		},
		{
			UntilTile = 10,
			Pool = {
				"screeField",
				"rockslide",
				"railGate",
				"railGapLeft",
				"railGapRight",
				"railChicane",
				"slideGate",
			},
			Gap = { 110, 180 },
		},
		{
			UntilTile = math.huge,
			Pool = {
				"screeField",
				"rockslide",
				"railGate",
				"railGapLeft",
				"railGapRight",
				"railChicane",
				"slideGate",
				"boulderRun",
			},
			Gap = { 85, 150 },
		},
	},

	--[[ THE FUTURISTIC CITY — reachable only once a world in `WorldConfig.Worlds` names this map.
		Until then `tiersFor` is never called with it and none of this runs; see the kinds block.

		The order of introduction is the whole ramp. Tier 1 is the two things that cannot hurt you,
		because both are lies of a sort — one gives you speed and one gives you nothing — and both
		have to be understood before they are used against you. `ghostLane` (tier 3) is the first
		time a hologram stands next to something solid, and `liftJump` and `overdrive` (tier 4) are
		the first time a pad is the answer to a wall rather than a treat on an empty road. ]]
	FuturisticCity = {
		{ UntilTile = 1, Pool = { "padRun", "holoDrift" }, Gap = { 260, 380 } },
		{ UntilTile = 3, Pool = { "holoDrift", "signPair", "padRun", "beamLine" }, Gap = { 190, 280 } },
		{
			UntilTile = 6,
			Pool = { "signPair", "beamLine", "minefield", "ghostLane", "signGate" },
			Gap = { 140, 220 },
		},
		{
			UntilTile = 10,
			Pool = {
				"minefield",
				"ghostLane",
				"beamLine",
				"signGate",
				"signChicane",
				"liftJump",
				"overdrive",
			},
			Gap = { 110, 180 },
		},
		{
			UntilTile = math.huge,
			Pool = {
				"minefield",
				"ghostLane",
				"signGate",
				"signChicane",
				"liftJump",
				"overdrive",
				"beamLine",
			},
			Gap = { 85, 150 },
		},
	},
}

-- Clear studs kept at the start/end of every tile so no course straddles a tile seam
-- (a course always lives inside exactly one tile — that's what makes it recyclable).
ObstacleConfig.LeadIn = 60
ObstacleConfig.TailOut = 60
-- Extra clear road after the spawn point on tile 0, so you're up to speed before the
-- first obstacle. The car spawns at the middle of tile 0.
ObstacleConfig.SpawnGraceStuds = 260

--[[ === THE RAIN'S PUDDLES ===================================================================

	Where the weather puts its puddles (`Kinds.Puddle`). A third pass over each road tile, after the
	courses and the pickups, and unlike both of them IT IS THE CLIENT'S ALONE.

	The weather is per world and can start or stop in the middle of a run (`WeatherConfig`), while the
	server re-derives a tile's obstacles from nothing but the seed and the map. A puddle laid inside
	`ObstacleLayout.forTile` would make the weather a fourth input to that contract, on both sides, for
	a hazard that costs nothing. So it is not: `ObstacleLayout.puddlesFor` is called by
	`ObstacleController` and by nothing else, the kind is `Local`, and every id it hands out is
	NEGATIVE, which no layout id ever is and which the server throws away on sight.

	HOW MANY is the event's business (`WeatherConfig.Events[].Puddles`: `Rain` about one a tile, the
	`Thunderstorm` about one and a half). How they are laid on the road is this block's, and both
	events share all of it.

	THE RAIN USUALLY STARTS MID-RUN, and that is the case this is shaped around rather than an edge of
	it: a storm runs three and a half minutes and a run one or two. The six tiles in front of the car
	were laid long before the rain arrived, and six tiles is over a minute of road, so puddles laid
	only as tiles recycle would first reach the player about eighty seconds into the storm. So every
	live tile is dressed the moment the rain starts, except within `Ahead` of the car, which is the one
	stretch where you would see a puddle appear out of nothing.

	They are never taken away mid-run. When the rain stops, the ripples stop, and each puddle dries up
	with its tile when that tile recycles. Water lying on the road for a minute after a shower is the
	honest picture anyway. What a puddle LOOKS like does follow the sky: an event's `Water` (the
	storm's night sheen) goes on every puddle on the road while that event is up, and comes off when
	it ends. ]]
ObstacleConfig.Puddles = {
	--- The folder a tile's puddles go in, inside the tile, beside its `TileFolderName` course. Its own
	--- folder so that traffic, whose obstacle lookahead reads the course folder only, drives through
	--- puddles instead of swerving round them as if they were solid.
	FolderName = "Puddles",
	--- `Assets.<this>` holds art shared by every world, because the rain falls on all of them. A
	--- world's own art folder is looked in first (`ObstacleService._publishProps`), so a map that
	--- wants a puddle of its own can have one by dropping it in.
	SourceFolderName = "Weather",
	--- Never more than this on one tile, whatever an event's chances say.
	MaxPerTile = 2,
	--- Clear road kept at each end of a tile, so a puddle never straddles a seam.
	LeadIn = 150,
	TailOut = 150,
	--- Which lanes, as indices into `ObstacleConfig.Lanes`, and how far either way of its lane a puddle
	--- may lie, in studs. All five and off the grid: water pools anywhere, the gutters included, and a
	--- puddle that only ever sat dead on a lane line would read as placed.
	Lanes = { 1, 2, 3, 4, 5 },
	Nudge = 5,
	--- Each puddle is sized by a factor in this range, hit volume and all, and turned to a random
	--- angle, so one road never shows the same stamp twice.
	Scale = { 0.8, 1.15 },
	--[[ How far a puddle keeps from every obstacle and pickup on its tile, as a box (`PickupConfig
		.Spawn` has the argument for a box over a radius). A puddle under a barricade is invisible, and
		one a few studs in front of a wall is an oil trap nobody authored: the slick is gentle, but
		`Duration` is still 85 studs of road. A candidate that fails is redrawn up to `Attempts`
		times and then dropped, which is the right failure on a tile that is full. ]]
	ClearAlong = 60,
	ClearCross = 20,
	Attempts = 6,
	--[[ Studs in front of the car inside which a puddle is never laid, for the rain arriving mid-run
		(see above). 450 is five seconds of road, and in the wet skies' own fog (`Fog.End` 1,400 in
		the rain, 1,100 in the storm) a flat pool that far out is a few pixels of grey. A tile laid as
		it recycles is thousands of studs off, so this only ever filters the first dressing. ]]
	Ahead = 450,
}

--[[ === THE BENCH ============================================================================

	One obstacle (or one authored course), laid down the road at a fixed distance and repeated,
	with nothing else on the tile. It is how a hazard gets LOOKED AT: the ramp that ships is a
	random draw over a pool, so meeting a particular kind means driving until it happens, and
	meeting it twice in a row means driving a lot further than that.

	IT IS NOT A SEPARATE ROAD. A benched run is an ordinary race — same car, same traffic rules,
	same server pricing — with `ObstacleLayout.forTile` answering from its bench branch instead of
	from the tier ramp. That is deliberately the only difference: a hazard tested on a bench that
	skipped the hit poll, the lane check or the damage path would be a hazard tested somewhere
	nobody drives.

	The panel's Obstacles tab arms it (`AdminService.Actions.bench` -> `ObstacleService.setBench`),
	and it rides to the client with `RaceStart` like the seed and the world do, because it is
	something the client BUILDS from.

	The numbers below are the defaults the tab's sliders start on and the bounds
	`ObstacleLayout.sanitizeBench` clamps to — that function is the rule, this is the slider. ]]
ObstacleConfig.Bench = {
	--- Studs of clear road between the spawn and the first one. The default is about seven
	--- seconds from a standing start, which is enough road to be at cruise and settled before
	--- the thing under test arrives — testing a hazard from a launch tests the launch.
	Lead = 500,
	LeadRange = { 120, 3000 },
	--- Studs between repeats. A hazard you get one attempt at per run is one you cannot compare
	--- two lines through, so the bench repeats forever; this is how long the walk back is.
	Spacing = 500,
	SpacingRange = { 150, 3000 },
	--- Which lane a single obstacle stands in. 3 is the middle of the road, which is where the
	--- car spawns, so the default really is "directly in front of you".
	Lane = 3,
	--- One in every lane instead of one in `Lane`. A wall you cannot miss, for the hazards that
	--- are only interesting when you actually drive into them (a slick, a boost pad, a mine).
	Row = false,
	--- HP stops moving for a benched run (`ObstacleService._applyDamage`). On by default because
	--- the point of a bench is the tenth hit, not the fourth: everything else about a hit — the
	--- shove, the yaw, the shake, the smoke, the smash — is untouched, and the wreck beat is
	--- reached by turning this off rather than by running out of road.
	Invulnerable = true,
	--- Whether the road still populates with traffic (`TrafficController._onRaceStart`). Off by
	--- default: a car clipping you three studs before a slick is a different test.
	Traffic = false,
	--[[ The name of what is armed, mirrored onto the Player so the panel can read it back for
		anybody in the server. `ObstacleService._bench` is the authority and this is a read-out of
		it, exactly as `PickupConfig.SlotAttribute` is for the pack slot.

		It is what stops a bench being forgotten. An armed bench outlives a run on purpose, so
		without something to read the panel would have no way to say why every run today has one
		cone in it. ]]
	Attribute = "ObstacleBench",
}

-- === Hit reporting ==========================================================
-- The client owns the car and the road, so it's the only side that can see a collision;
-- it reports the obstacle id and the SERVER decides the damage from `Kinds` above.
-- Ceiling on accepted reports per second — a real run peaks at ~5 (plowing a wall),
-- so this only exists to bound a malformed/spamming client.
--[[ How many obstacles one frame may build when a tile's course is laid.

	THE COURSE USED TO BE BUILT WHOLE, on the frame `_reconcileTiles` noticed a tile had recycled.
	The busiest tier emits about 25 obstacles (ObstacleLayout's header) and each one is a Model, an
	anchored hit Part and — for every kind with art — a `prop:Clone()`, on top of destroying the
	course the tile was carrying before. That is a periodic spike locked to the recycle cadence, and
	it landed on the same frames `RoadController` had already gone to some trouble to keep clear.

	SO IT IS SLICED, exactly like `RaceConfig.TileBuildBudget` slices the tile underneath it, and
	this is the same kind of number: obstacles per frame rather than instances per frame, because an
	obstacle is the indivisible unit here — its volume, its art and its attributes have to arrive
	together or the poll can see a hit box with nothing drawn under it.

	SIX IS SIZED OFF THE WORST COURSE AND THE LEAD AVAILABLE. Twenty-five obstacles at six a frame is
	five frames; a course is laid on a tile the car will not reach for `DesiredSegmentCount -
	SegmentsBehind - 1` segments, which is thousands of studs, so there is lead to spare and no
	reason to push this higher. The whole course is built OFF-TREE and parented in one call when it
	is finished (`_buildTile`), so a half-built course is never visible and never queryable. ]]
ObstacleConfig.BuildBudget = 6

ObstacleConfig.MaxHitsPerSecond = 12
-- Rebase-proof sanity check: a hit is rejected if the car's cross-axis position is
-- further than (obstacle half-width + this) from the obstacle's lane. Generous on
-- purpose — the server's copy of the car position lags the owner's by a frame or two.
ObstacleConfig.LaneCheckSlack = 16
-- Same idea for a wall scrape, but this one the server can genuinely verify rather than just
-- sanity-check: a scrape is rejected unless the car's flank is within this many studs of the
-- corridor edge. Generous for the same lag reason, plus the shove is already pushing the car
-- back off the rail by the time the report lands. Still far tighter than the ~73-stud corridor,
-- so it can't be claimed from the middle of the road.
ObstacleConfig.WallCheckSlack = 12

-- Stronger collision consequences, 2026-10-12. Preserve each hazard's relative severity.
-- Pickups, pass-through props and slippery surfaces with zero damage remain harmless directly.
ObstacleConfig.DamageBalance = { ObstacleScale = 1.6, WallDamage = 8 }
for _, kind in ObstacleConfig.Kinds do
 if kind.Damage and kind.Damage > 0 then
  kind.Damage = math.round(kind.Damage * ObstacleConfig.DamageBalance.ObstacleScale)
 end
end
ObstacleConfig.Wall.Damage = ObstacleConfig.DamageBalance.WallDamage

return ObstacleConfig
