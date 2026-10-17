--[[
	WeatherConfig
	-------------
	THE WEATHER, AND THE CARS IT LEAVES BEHIND. Two features that are really one, which is why they
	share a file: an EVENT is a stretch of time during which one world's road looks different, and a
	MUTATION is what that weather does to the traffic driving through it. Neither is worth much on
	its own — weather with no mutation is a filter over the screen, and a mutation with no weather is
	a rare car with no reason to be rare — so they are declared together and each names the other.

	=== FIVE THINGS TO KNOW BEFORE EDITING =====================================================

	1. AN EVENT IS PER WORLD, NOT PER SERVER. World 1 can be under a thunderstorm while worlds 2, 3
	   and 4 are clear. That is the whole point of the feature: it gives a player a reason to go
	   somewhere they were not already going, which a server-wide event cannot do because there is
	   nowhere else to be. Each world runs its own queue on its own offset (see `Schedule`), and the
	   wire carries all of them at once (see `Attribute`).

	2. THE SERVER OWNS THE CLOCK AND THE CLIENT OWNS THE LOOK. Same split as `TipsConfig` describes,
	   and for a stronger reason here: the road, the traffic and the obstacles are all client-built
	   (RoadController's header), so there is no server-side road for a raincloud to sit over. The
	   server decides WHAT is running WHERE and WHEN IT ENDS; every atmosphere property, particle and
	   highlight in this file is applied by `WeatherController` on the machine that can see it.

	3. A MUTATION HAS TWO MULTIPLIERS AND THEY ARE NOT THE SAME NUMBER. `Multiplier` is what the RUN
	   pays for getting away with it — a one-off, settled once, priced to feel like a jackpot.
	   `ValueMultiplier` is what the car is worth FOREVER once it is parked on a podium, and a number
	   that reads as generous on a single payout is ruinous when it is compounding every second of
	   every session. See `Mutations` for the sizing, and change `Multiplier` freely before you touch
	   the other one.

	4. WHAT A MUTATION LOOKS LIKE IS A HIGHLIGHT, AN EMITTER AND A KIT BADGE, AND FOR FOUR OF THEM A
	   SKIN. A `Highlight` in the mutation's colour, an optional particle emitter, and a billboard
	   badge — all built at runtime by `Modules/CarMutation`. The badge WAS a coloured rounded
	   rectangle drawn in code, on the grounds that no art existed for it; that stopped being true
	   when the lobby notice was rebuilt out of the kit, so the badge is now the kit's own slot well
	   and pill carrying the event's glyph, the mutation's name and its multiplier. See `Badge`.

	   A `Skin` is the car's own parts put into an engine material (every mutation but `Impatient`
	   and `Charged`), and `Outline` is the switch for the Highlight's rim. Both are in the
	   `Mutations` header.

	   `Icon` on each mutation is still empty and is still not needed: the glyph the badge draws is
	   the EVENT's (`Events[n].Icon`, which every event has), because the weather is what a player
	   recognises at two hundred studs and the mutation is what the words say once they are close.

	5. THE CHANCES ARE PER SPAWN, NOT PER RUN. `EventChance` is rolled for every traffic car that
	   spawns while that mutation's event is running, and `NaturalChance` for every car that spawns
	   when it is not. With `TrafficConfig.MaxCars` at 12 and a car recycling every few seconds, an
	   `EventChance` of 0.2 means roughly one mutated car in view at any moment — which is what "the
	   weather changed the road" should feel like. Anything above ~0.35 stops being an event and
	   starts being the normal state of that world.

	   MIND THE ONE EVENT THAT MOVES `MaxCars`. `RushHour` runs 21 cars rather than 12 (see `Traffic`
	   in the `Events` header), so a chance sized against 12 lands nearly twice as often under it —
	   which is why `Impatient` is set at 0.22 and not at the 0.35 that reasoning off a dozen cars
	   would have allowed.

	=== THE TRUST GAP, AND WHAT BOUNDS IT ======================================================

	Traffic is client-sided, so the client is the only thing that knows which car it stole and what
	was wrong with it — the same accepted gap `GetawayService` documents for the tier, the body and
	the paint. A mutation is worse than a paint, though, because a paint is cosmetic and this is
	MONEY: a client that names `Molten` on every bank has multiplied its own income by five.

	So it is bounded, and `WeatherService.couldHaveSpawned` is the bound. A claim is only honoured if
	the mutation is one that spawns naturally (`AllowNatural`), or if its event was actually running
	in that player's world at some point during that run — which the server knows because the server
	is the thing that started it. That does not make the claim verified; it makes the lie worth at
	most whatever the road was already handing out.

	HOUSE RULE: no wiki-style double-bracket links in this comment — the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- The badge art, by asset id. `UIAssets` is this project's asset registry and it requires nothing,
--- so this is a leaf dependency and cannot cycle back through `GarageConfig` the way a require of
--- anything gameplay-shaped would.
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)

local WeatherConfig = {}

--[[ Master switch. Off = `WeatherService` never starts a schedule, `WeatherController` binds
	nothing, no traffic car ever rolls a mutation and every multiplier in the game is 1. Every
	consumer routes through the functions at the bottom of this file, so this is a complete switch
	rather than something twelve call sites each have to remember to check. ]]
WeatherConfig.Enabled = true

--[[ THE EVENT VFX FLAG (2026-09-15). On, every event draws its `Vfx` block: layered emitters built
	from the VFXer plugin's texture library, plus the two things the first sky could not do, a real
	bolt of lightning in the thunderstorm and meteors you can watch come down in the meteor shower.
	Off, the sky is exactly the one that shipped first: each event's `Particles` streak box and the
	thunderstorm's flash, and nothing else.

	ONLY WHAT IS DRAWN IN THE AIR CHANGES. `Look` (the Lighting half: fog, atmosphere, time of day,
	grade) is shared by both, so flipping this can never move how far you can see down the road.

	Kept as a flag so the new look can be reverted in one line. The F2 panel's Weather tab flips this
	client's copy live, for a side by side on the same storm. See `Vfx` in the `Events` header. ]]
WeatherConfig.EventVfx = true

--[[ THE WIRE. One Workspace attribute holding EVERY world's state at once, comma separated:

	    "1=Thunderstorm:18402.5,3=Fog:18990.0"

	— world index, event key, and the `workspace:GetServerTimeNow()` it ends at. A world with no
	event is simply absent.

	AN ATTRIBUTE AND NOT A REMOTE, and the reasoning is `GarageConfig.OwnedAttribute`'s: attributes
	replicate on their own, so a player who joins in the middle of a storm sees it without asking, a
	client that missed a broadcast recovers on the next write, and the Teleport page can badge a
	world card with no round trip. The cost is one string write per schedule change — about one
	every few minutes per world.

	SERVER TIME, NOT A DURATION, because a duration decays and a deadline does not: a client that
	receives this two seconds late computes the same end for it as one that received it instantly.
	`workspace:GetServerTimeNow()` is the one clock both sides agree on. ]]
WeatherConfig.Attribute = "Weather"

--[[ server -> client `(world, eventKey, endsAt)`: an event has just started. `WeatherController`
	turns it into the notice that slides in at the top of the screen.

	IT IS SENT TO THE PLAYERS IN THAT WORLD AND TO NOBODY ELSE. It used to be a chat line fired at
	everybody for every world, which at one event every few minutes across four worlds is a running
	commentary on four places you are not — and chat is where a player looks for other players. What
	is left is a notice about the road you actually drive, which is the only one of the four you were
	ever going to act on in the next thirty seconds.

	THE OTHER THREE WORLDS ARE NOT SILENT, they are just not INTERRUPTING: the world-select screen
	badges every card that has weather on it (`UIController/Pages/Teleport`), which is the screen
	that asks "where do you want to go" and therefore the right place to answer it. The chat line was
	true for six seconds and this is true for as long as the event is.

	`endsAt` is on the wire so the notice can say how long is left without decoding the attribute.
	The STATE still rides `Attribute`, which replicates on its own and which a late joiner reads
	without asking; this is the notification only. ]]
WeatherConfig.StartedEvent = "WeatherStarted"

--[[ THE ADMIN OVERRIDE, both ways.

	client -> server `(action, world, key, seconds)`: the F2 panel's Weather tab asking the schedule
	to do something by hand — `"start"` an event now, `"stop"` whatever is running, or `"roll"` the
	next one early. server -> the one client that asked `(ok, message)`: what happened, as a sentence
	for the panel to print.

	THE SERVER RE-CHECKS `Admins.isAdmin` ON EVERY CALL and the panel's own gate is not a trust
	point — see that config's header. It has to, because this remote is the one thing in the feature
	that can conjure the window `couldHaveSpawned` reads: an unchecked "start a thunderstorm" is an
	unchecked x3.5 on every run banked for the next five minutes.

	ONE REMOTE AND AN ACTION STRING rather than three remotes. The three actions share every line of
	their validation — the admin check, the rate limit, the world resolve — and three remotes would
	mean three copies of all of it, which is three places for the admin check to be forgotten in. ]]
WeatherConfig.AdminEvent = "WeatherAdmin"

-- === The schedule ===========================================================
--[[ WEATHER RUNS ON A CLOCK, NOT ON A DICE ROLL, and it is the same clock in every server.

	Every world gets one event every `Period` seconds, lasting `Duration` seconds, starting
	`Offsets` seconds into its own period. That is the whole schedule: it is arithmetic on
	`workspace:GetServerTimeNow()`, so `WeatherService` does not so much run a timer as read what
	time it is.

	THREE THINGS THAT BUYS, and they are why this replaced the random gaps that used to be here:

	  • EVERY SERVER AGREES. The old schedule rolled its own gaps off its own `Random`, so "there is
	    a thunderstorm in the desert" was true in one server and false in the one next door. It is
	    now a fact about the time of day, which means a player can be TOLD it, can plan around it,
	    and can tell somebody else about it.
	  • A RESTART CHANGES NOTHING. There is no first gap to serve and no schedule to warm up: a
	    server six hours old and a server sixty seconds old are on the same beat.
	  • THE WORLDS CANNOT ALL FIRE AT ONCE, by construction rather than by luck — see `Offsets`.

	`Period` is fifteen minutes, which is short enough that a half-hour session sees two and long
	enough that arriving in one still feels like arriving in something.

	`Duration` is deliberately UNDER `Period` divided by the number of worlds (900 / 4 = 225). That
	is the whole reason the windows below fit end to end without touching; take it past 225 and the
	offsets can no longer keep four worlds apart no matter what they are set to.

	=== THE OFFSETS, AND WHY THEY ARE UNEVEN ==================================================

	One number per world: how far into the fifteen minutes that world's event starts. At the values
	below the four windows are

	    world 1   0:00 - 3:30        world 3   7:25 - 10:55
	    world 2   3:35 - 7:05        world 4  11:20 - 14:50

	— never two at once, and never more than twenty-five seconds anywhere on the map with nothing
	running. The CLEAR gaps between them are 5s, 20s, 25s and 10s rather than four equal ones, and
	that is the point of writing them out by hand instead of dividing: an even spread makes the game
	tick like a metronome, and a player who learns one world's rhythm learns all four.

	A WORLD PAST THE END OF THIS TABLE falls back to `(world - 1) * OffsetStride` wrapped into the
	period. That keeps a fifth world off world 1's window and promises nothing about the others —
	when a fifth world ships, write its number here. ]]
WeatherConfig.Schedule = {
	Period = 900,
	Duration = 210,
	Offsets = { 0, 215, 445, 680 },
	OffsetStride = 215,

	--[[ Never roll the same event twice running in the same world. THE GRID CANNOT DO THIS ANYWAY —
		a world's queue is a rotation and a rotation does not repeat until it wraps — so this now
		governs only the admin panel's random Roll button (`WeatherService._pick`). ]]
	NoImmediateRepeat = true,
}

-- === The events =============================================================
--[[ One entry per event, and `Key` is the identity — it goes on the wire, into the save file via a
	car key, and into a log line. IT MAY NEVER CONTAIN A COMMA OR A COLON, both of which separate
	fields in `Attribute` and in `GarageConfig.carKey`, and it should never be renamed once a build
	has shipped: a mutation key is part of what a car IS, so renaming one strands every copy of that
	car in every save file that holds it.

	THE ORDER OF THIS TABLE IS THE QUEUE. Every world walks it top to bottom, one entry per period,
	and each starts at a different place in it (`queuedEvent`), so reordering this table reorders
	what every world runs and inserting one in the middle shifts all four. Both are fine — it is
	weather, and nothing persists a slot — but it does mean this is no longer just a list.

	`Weight` therefore does NOT decide how often a sky turns up any more; the queue does, and every
	event turns up exactly as often as every other. It is the weighting on the admin panel's random
	Roll button and nothing else, which is why they are all still equal.

	`Icon` is the card badge on the world-select screen (`UIController/Pages/Teleport`), by asset id
	through `UIAssets.Weather`. Zero means "no art", and the badge falls back to naming the event in
	words — which is what every one of these was before the icons existed.

	=== WHAT `Look` IS ==========================================================================

	Everything `WeatherController` needs to make the road look like this and put it back afterwards.
	The fields are Lighting's own, so the names mean exactly what the Studio properties mean:

	    Clock          ClockTime while the event runs; nil leaves the authored time of day alone
	    Ambient        Lighting.Ambient
	    Outdoor        Lighting.OutdoorAmbient
	    Brightness     Lighting.Brightness
	    Fog            { Color, Start, End } -> FogColor / FogStart / FogEnd
	    Atmosphere     { Density, Offset, Color, Decay, Glare, Haze } -> an Atmosphere instance
	    Tint           a ColorCorrection tint, applied on top of everything else

	NOTHING HERE IS AUTHORED IN THE PLACE and nothing here is destructive: the controller captures
	whatever Lighting held before the event, tweens into these, and tweens back out. A build that
	changes the lobby's time of day tomorrow therefore needs no edit to this table.

	`Particles` is the weather you can see falling, built at the camera the way `WindConfig`'s
	streaks are. `Rate` is per second, `Speed` studs/s downward, `Size` studs, `Squash` how far a
	dot is stretched along its travel (which is what turns one into a raindrop), and `Drag` how hard
	the crosswind pulls it sideways. A nil `Particles` is a sky with only a colour grade, which
	`Fog` is: there is nothing falling in fog, and inventing something would read as drizzle.

	=== `Traffic`: ONE OF THE TWO THINGS WEATHER CAN DO THAT ARE NOT COSMETIC ==================

	(The other is `Puddles`, below.) Optional, and today exactly one event has it. Every field is a
	MULTIPLIER on the matching `TrafficConfig` number rather than a replacement for it, so re-tuning
	the road re-tunes the event with it and nothing here has to be re-derived when `MaxCars` moves:

	    Cars     x `TrafficConfig.MaxCars`        how many cars are on the road at once
	    Spawn    x `TrafficConfig.SpawnInterval`  seconds between spawn attempts, so LOWER is busier
	    Prime    x `TrafficConfig.PrimeCount`     how many are already out there at the start line
	    Speed    x each tier's cruise band        how fast they are all driving

	Applied on the CLIENT, by `TrafficController`, because that is where the cars are — the same
	split the rest of this feature is built on.

	KEEP IT TO ONE EVENT. Four events that each quietly changed the density would be four different
	difficulties of run with nothing on screen to say which one you are in; `Rain` does not touch the
	traffic. An event that changes how the road plays has to be an event the player can NAME.

	=== `Puddles`: THE RAIN LEAVES WATER ON THE ROAD ============================================

	Optional, and today on `Rain` and `Thunderstorm` (the storm lays more). While the event runs, the
	client lays puddles on its own road (`ObstacleConfig.Kinds.Puddle`, a gentle slick with ripples on
	it), a pass of their own that the server never sees. This block is HOW MANY, and nothing else:

	    Kind            the `ObstacleConfig.Kinds` entry laid ("Puddle")
	    ChancePerTile   chance a road tile (about 1,170 studs, 14 seconds at cruise) gets one
	    ChanceOfSecond  chance a tile that got one gets a second
	    Water           optional { Material, Color, Transparency, Reflectance } worn over the
	                    puddle art's own look while this sky is up, for a sky it does not read
	                    under (the storm's night). Every puddle on the road changes with the sky.

	Everything about WHERE they go (lanes, clearances, how far ahead of the car one may appear when
	the rain starts mid-run) is `ObstacleConfig.Puddles`, so another wet event is one line here.

	It passes the rule above because you can SEE it: a puddle is a thing lying in your lane with rain
	rippling it, not a number that moved. It belongs to the wet skies only and should stay a mild one.

	=== A PARTICLE MUST NOT BE THE COLOUR OF ITS OWN FOG ========================================

	Worth knowing before tuning any of these, because it is not obvious and it cost a debugging pass.
	The first sandstorm here had `Fog.Color` at 198,166,112 and grit at 222,188,130 — twenty-four
	points apart — and the effect was INVISIBLE in a playtest despite thirteen hundred particles a
	second landing squarely in frustum. Every event applies a heavy `Atmosphere` and a tint, so the
	whole frame converges on the fog colour; a particle painted the same colour has nothing to be
	seen against.

	So each event's `Color` is deliberately several shades LIGHTER than its own `Fog.Color`, and
	`Glow` (LightEmission) lifts it off the haze rather than being decoration. Transparency does the
	rest: past about 0.5 a particle stops reading through an atmosphere this dense.

	=== `Vfx`: THE LIBRARY LOOK, DRAWN INSTEAD OF `Particles` WHILE `EventVfx` IS ON ============

	`Particles` is one emitter in one box over the camera. `Vfx` is the same idea taken further:

	    Layers    up to five emitters, each in its OWN box, so rain can fall around the camera while
	              its splashes land on the road and its curtains hang half a mile out
	    Bolts     the thunderstorm only: a bolt drawn somewhere ahead on every flash
	    Meteors   the meteor shower only: bodies that fly across the sky with a burning tail, and
	              now and then come down on the horizon

	Nothing in `Particles` is read while `Vfx` draws, so each event's first sky is still in its
	`Particles` block, untouched, for the flag to go back to. A layer that wants the old streaks
	just repeats their numbers.

	A LAYER, field by field (every one optional):

	    Texture       the image. Default the original streak: a soft dot that `Squash` stretches
	    Flipbook      "Grid2x2", "Grid4x4" or "Grid8x8", played once across each particle's life
	    RandomFrame   with `Flipbook`: each particle is one still frame of the sheet, picked at random
	    Rate          per second
	    Prewarm       particles emitted the moment the layer goes up, so a slow layer (a cloud
	                  deck) does not take its whole lifetime to fill the sky at the start of a run
	    Lifetime      seconds, or { min, max }
	    Speed         studs/s, or { min, max }
	    Direction     "Down" (the default), "Up" or "Across" (world +X, which is across the race road)
	    Facing        "Streak" (the default: laid along its travel), "Camera", "Upright" (faces
	                  the camera but stays vertical), or "Flat" (lies across its travel: a particle
	                  going "Up" lies flat on the road)
	    Squash        how far a "Streak" is stretched. BELOW ZERO STRETCHES IT ALONG ITS TRAVEL.
	                  Above zero stretches it across, which is what every original `Particles`
	                  block does (their 9, 11, 6 and 2), and why the first rain fell as horizontal
	                  dashes. Those blocks are left as they shipped, for the flag to go back to
	    Size          studs, or a list from birth to death spread evenly over the life
	    Transparency  the same: one number, or a list (1, 0.7, 0.7, 1 fades in and back out)
	    Color         and `ColorEnd` for a colour that changes over the life
	    Glow          LightEmission. `Brightness` on top of it for a glow that has to beat a dark sky
	    Wind          sideways acceleration, studs/s/s, along world +X
	    Gravity       downward acceleration, studs/s/s (below zero lifts)
	    Drag          the engine's own drag: seconds for a particle to lose half its speed
	    Spread        degrees either way of `Direction` (6)
	    Rotation      degrees either way of upright a particle starts (0), or { min, max } exactly
	    Spin          degrees per second either way (0)
	    Locked        stays pinned to its box instead of being left in world space
	    Box           { Width, Height, Depth, Ahead, Lift } in studs. Default the original
	                  camera box. `Ahead` is along the camera's flattened look
	    Ground        the box stands ON THE ROAD: `Lift` is its underside above the deck, rather than
	                  its centre above the camera

	The fog rule above holds for every layer, and the library sheets are other creators' uploads
	referenced by id: a layer that has gone invisible is the first thing to check against the
	plugin's Library window.

	CEILINGS. Four events carry a cloud deck: a handful of huge soft clouds in a wide box a hundred
	studs over the camera. The engine's own `Clouds` would be cheaper and were the first idea, but
	they sit at one fixed altitude for the whole place, and every live race is its own storey 1,200
	studs above the last (`RaceConfig.Lanes`). Measured in Studio 2026-09-15: still overhead at
	6,000 studs, gone by 10,800, and the storeys go up to 18,000, so the upper racers in a busy
	server would drive under a clear sky. A deck that rides the camera is the same sky on every
	storey. It is kept to about fifty particles alive, because it is the layer that covers the most
	screen.

	A DECK IS `Locked` TO ITS BOX, and so rides along with the car. Left in world space the way
	the rain is, it was outrun: at race speed a cloud emitted half a mile ahead is overhead in five
	seconds and behind in ten, so a deck sized for a parked camera showed blue sky through the gaps
	the moment the car was moving. Real cloud is far enough away that it barely moves against a
	car either, so pinned is also what it should look like.

	NO PARTICLE HERE MAY BE OVER 300 STUDS. The engine quietly stops drawing one somewhere past
	that: measured on the thunderstorm's deck, 300 drew, 340 drew in patches, 360 and 400 drew
	nothing at all, with no warning anywhere. A deck that has gone missing is the first thing to
	check against this. ]]
WeatherConfig.Events = {
	{
		Key = "Rain",
		Name = "Rain",
		-- The middle row of the notice card. One sentence, no em dashes (house rule), and it names
		-- neither the world nor the mutation: the rows above and below it do, so one blurb serves
		-- whichever world it lands in. It has ONE line on the card, about 30 characters.
		Blurb = "It is bucketing down.",
		Color = Color3.fromRGB(96, 148, 210),
		Weight = 10,
		Icon = UIAssets.Weather.Rain,
		Mutation = "Soaked",
		Look = {
			Clock = 15.5,
			Ambient = Color3.fromRGB(70, 76, 86),
			Outdoor = Color3.fromRGB(92, 100, 112),
			Brightness = 1.4,
			Fog = { Color = Color3.fromRGB(126, 136, 148), Start = 120, End = 1400 },
			Atmosphere = {
				Density = 0.34,
				Offset = 0.1,
				Color = Color3.fromRGB(178, 188, 198),
				Decay = Color3.fromRGB(96, 108, 124),
				Glare = 0.1,
				Haze = 1.4,
			},
			Tint = Color3.fromRGB(214, 226, 240),
		},
		--[[ PUDDLES, every once in a while: about one a tile, so one every fourteen seconds or so at
			cruise. Often enough that a run in the rain meets several, rare enough that each one is a
			thing you notice and choose a line past rather than the texture of the road. See `Puddles`
			in the header, and `ObstacleConfig.Kinds.Puddle` for what driving through one does. ]]
		Puddles = { Kind = "Puddle", ChancePerTile = 0.75, ChanceOfSecond = 0.4 },
		--[[ `Rate` is per second, and it is sized against `WeatherController`'s BOX rather than picked
			for feel — see that constant's note. 900 at a 0.55s lifetime is ~500 streaks alive in
			1.4 million cubic studs, which is what ordinary rain looks like from inside it. ]]
		Particles = {
			Rate = 750,
			Speed = 150,
			Size = 1.6,
			Squash = 9,
			Drag = 0.15,
			Color = Color3.fromRGB(212, 228, 248),
			Transparency = 0.3,
			Lifetime = 0.55,
			Glow = 0.2,
		},
		Vfx = {
			Layers = {
				--[[ The rain itself: the original streaks, with the one fix they needed. Their
					`Squash` of 9 stretched every drop ACROSS its fall, so the first rain came down as
					horizontal dashes (see `Squash` in the header). At -7 they are the long vertical
					streaks of rain seen from inside it. ]]
				{
					Rate = 750,
					Speed = 150,
					Size = 1.6,
					Squash = -7,
					Wind = 5.6,
					Color = Color3.fromRGB(212, 228, 248),
					Transparency = 0.3,
					Lifetime = 0.55,
					Glow = 0.2,
				},
				--[[ Where it lands: the library's ring splash (a crown that opens and breaks), stood
					upright on the tarmac around and ahead of the car and left there as you drive
					through. This is the layer that says the ROAD is wet, which streaks in the air
					cannot. Pure white and a little glow: in daylight on dark tarmac a paler grey
					splash read as grey crescents of debris. ]]
				{
					Texture = "rbxassetid://89026348622924",
					Flipbook = "Grid4x4",
					Ground = true,
					Box = { Width = 70, Height = 0.2, Depth = 150, Ahead = 50, Lift = 0.3 },
					Facing = "Upright",
					Direction = "Up",
					Speed = 0,
					Rate = 300,
					Lifetime = { 0.25, 0.4 },
					Size = { 0.8, 2 },
					Color = Color3.new(1, 1, 1),
					Transparency = { 0, 0.55 },
					Glow = 0.5,
				},
				--[[ THE CLOUD DECK. The place's skybox is a bright cartoon blue, and rain falling out of
					it read as a sprinkler on a summer day. This is a ceiling of the library's soft
					cloud, big and grey, riding over the camera, so the sky the rain falls out of is
					overcast. See `CEILINGS` in the header for why it is particles and not the engine's
					own clouds. ]]
				{
					Texture = "rbxassetid://7216854921",
					Box = { Width = 900, Height = 40, Depth = 1000, Ahead = 420, Lift = 110 },
					Facing = "Camera",
					Direction = "Across",
					Speed = { 4, 8 },
					Rate = 5,
					Prewarm = 40,
					Locked = true,
					Lifetime = { 9, 12 },
					Size = 300,
					Color = Color3.fromRGB(140, 148, 160),
					Transparency = { 1, 0.2, 0.2, 1 },
					Rotation = 180,
					Spin = 3,
				},
			},
		},
	},

	{
		Key = "Fog",
		Name = "Fog",
		Blurb = "You cannot see a thing.",
		--[[ SLATE, NOT THE FOG'S OWN GREY. `Color` is the badge plate on the world card and the rim on
			the notice, and both carry a WHITE-ish icon: at the 168,176,186 this used to be, the pale
			cloud glyph all but disappeared into its own pill. Every other event's colour can be lifted
			off its sky; this one has to be pushed the other way. ]]
		Color = Color3.fromRGB(116, 132, 150),
		Weight = 10,
		Icon = UIAssets.Weather.Fog,
		Mutation = "Ghost",
		Look = {
			Clock = 7,
			Ambient = Color3.fromRGB(112, 116, 122),
			Outdoor = Color3.fromRGB(138, 142, 148),
			Brightness = 1.1,
			--[[ THE ONE EVENT THAT CHANGES HOW THE GAME PLAYS. A fog end of 520 studs is roughly six
				seconds of road at the 85 studs/s cruise, which is enough to react to traffic and not
				enough to plan around it. Pulling it under ~350 stops being atmosphere and starts
				being unfair: an obstacle course you cannot see until you are in it is not a course. ]]
			Fog = { Color = Color3.fromRGB(206, 210, 216), Start = 40, End = 520 },
			Atmosphere = {
				Density = 0.5,
				Offset = 0.25,
				Color = Color3.fromRGB(214, 218, 224),
				Decay = Color3.fromRGB(150, 156, 164),
				Glare = 0.3,
				Haze = 3,
			},
			Tint = Color3.fromRGB(228, 230, 234),
		},
		Particles = nil,
		--[[ Still nothing FALLS in fog. What the library adds is the fog itself moving: big soft wisps
			drifting low across the road, so you drive through banks of it rather than under a flat
			grey filter. Whiter than `Fog.Color` for the contrast rule, and faint, because this is the
			one event whose sight line is already the gameplay limit (`Fog.End`): a wisp may soften
			the car ahead, it must never hide it. ]]
		Vfx = {
			Layers = {
				-- At 0.8 they vanished into the fog they were meant to move; 0.5 is where they read.
				{
					Texture = "rbxassetid://7216854921",
					Ground = true,
					Box = { Width = 240, Height = 10, Depth = 240, Ahead = 80, Lift = 7 },
					Facing = "Camera",
					Direction = "Across",
					Speed = { 2, 5 },
					Rate = 24,
					Lifetime = { 3, 4.5 },
					Size = { 30, 44 },
					Color = Color3.fromRGB(246, 248, 251),
					Transparency = { 1, 0.5, 0.55, 1 },
					Rotation = 180,
					Spin = 8,
				},
				-- A low pale ceiling, so the sky over the fog is grey rather than the skybox's blue.
				{
					Texture = "rbxassetid://7216854921",
					Box = { Width = 900, Height = 30, Depth = 1000, Ahead = 420, Lift = 70 },
					Facing = "Camera",
					Direction = "Across",
					Speed = { 3, 6 },
					Rate = 5,
					Prewarm = 40,
					Locked = true,
					Lifetime = { 9, 12 },
					Size = 300,
					Color = Color3.fromRGB(200, 205, 212),
					Transparency = { 1, 0.2, 0.2, 1 },
					Rotation = 180,
					Spin = 3,
				},
			},
		},
	},

	{
		Key = "Thunderstorm",
		Name = "Thunderstorm",
		Blurb = "Lightning is hitting the road.",
		Color = Color3.fromRGB(126, 156, 255),
		Weight = 10,
		Icon = UIAssets.Weather.Thunderstorm,
		Mutation = "Charged",
		Look = {
			Clock = 20,
			Ambient = Color3.fromRGB(46, 50, 64),
			Outdoor = Color3.fromRGB(62, 68, 88),
			Brightness = 1,
			Fog = { Color = Color3.fromRGB(78, 86, 104), Start = 90, End = 1100 },
			Atmosphere = {
				Density = 0.42,
				Offset = 0.15,
				Color = Color3.fromRGB(150, 162, 190),
				Decay = Color3.fromRGB(60, 70, 96),
				Glare = 0.2,
				Haze = 2.2,
			},
			Tint = Color3.fromRGB(196, 206, 236),
		},
		--[[ The rain's puddles, about half as many again: 1.5 a tile measured, so one every nine
			seconds at cruise against the rain's fourteen. The storm is the worse weather, and more water
			on the road is the part of that you drive. Nearly every tile gets one and most get a second,
			which is as far as `ObstacleConfig.Puddles.MaxPerTile` (2) lets these two numbers go; more
			than this is a job for that cap, not for these.

			`Water` because this storm is at NIGHT (`Look.Clock` 20). The puddle's own Glass shows the
			sky, and a night sky on a black road left it invisible from the chase camera, under the
			storm's own splashes, measured in a playtest: a slick you cannot see. A faint slate Neon
			sheen reads as a wet road catching the street lights, and in the rain's daylight it looked
			flat next to the Glass, which is why it is the storm's alone. Picked side by side at 75
			studs from the chase camera: 80,92,110 at 0.65 was there but easy to lose among the
			splashes, a saturated blue read as a glowing pad, and this is the brightest that still
			reads as water. ]]
		Puddles = {
			Kind = "Puddle",
			ChancePerTile = 0.95,
			ChanceOfSecond = 0.7,
			Water = { Material = Enum.Material.Neon, Color = Color3.fromRGB(96, 110, 132), Transparency = 0.55 },
		},
		-- Heavier than the rain event, which is most of what makes it read as the worse weather.
		Particles = {
			Rate = 900,
			Speed = 190,
			Size = 1.8,
			Squash = 11,
			Drag = 0.3,
			Color = Color3.fromRGB(196, 214, 250),
			Transparency = 0.28,
			Lifetime = 0.5,
			Glow = 0.25,
		},
		--[[ The lightning: a full-screen flash every few seconds, brightening Lighting for a few
			frames rather than drawing a bolt. A bolt would need art, would need to be somewhere
			specific, and would be behind the camera half the time; the flash is what the player
			actually notices, and it is three numbers.

			`Every` is the gap between strikes in seconds, rolled per strike. ]]
		Lightning = {
			Every = { 4, 11 },
			Brightness = 4.5,
			Hold = 0.06,
			Fade = 0.45,
		},
		Vfx = {
			Layers = {
				--[[ The original heavy streaks, with the rain event's squash fix (11 drew them sideways),
					and a little finer: at 1.8, stretched properly, a drop falling past the lens drew a
					bright bar down the middle of the screen. ]]
				{
					Rate = 900,
					Speed = 190,
					Size = 1.5,
					Squash = -9,
					Wind = 14.25,
					Color = Color3.fromRGB(196, 214, 250),
					Transparency = 0.28,
					Lifetime = 0.5,
					Glow = 0.25,
				},
				-- The rain event's splashes, harder: more of them and bigger.
				{
					Texture = "rbxassetid://89026348622924",
					Flipbook = "Grid4x4",
					Ground = true,
					Box = { Width = 70, Height = 0.2, Depth = 150, Ahead = 50, Lift = 0.3 },
					Facing = "Upright",
					Direction = "Up",
					Speed = 0,
					Rate = 380,
					Lifetime = { 0.25, 0.4 },
					Size = { 1.2, 2.8 },
					Color = Color3.fromRGB(214, 226, 250),
					Transparency = { 0.15, 0.6 },
					Glow = 0.3,
				},
				-- The rain's cloud deck, near black: a storm at night is a lid on the world.
				{
					Texture = "rbxassetid://7216854921",
					Box = { Width = 900, Height = 40, Depth = 1000, Ahead = 420, Lift = 110 },
					Facing = "Camera",
					Direction = "Across",
					Speed = { 6, 12 },
					Rate = 5,
					Prewarm = 40,
					Locked = true,
					Lifetime = { 9, 12 },
					Size = 300,
					Color = Color3.fromRGB(70, 78, 96),
					Transparency = { 1, 0.15, 0.15, 1 },
					Rotation = 180,
					Spin = 4,
				},
			},
			--[[ THE BOLT THE FLASH NEVER HAD. On every strike `Lightning` already rolls, a bolt comes
				down somewhere along the road ahead, from the cloud deck to the ground, and flickers out
				the way a real stroke does (two or three return strokes in under half a second). The
				flash still fires with it; the bolt shows where it came from.

				Drawn with beams, not the library's bolt sprite: the sprite is soft and smoky and read
				as a white plume at this distance (see `_buildBolt`). `Height` is cloud to ground,
				`Distance` ahead along the camera's look and `Across` either side, so it never lands on
				the road near the car and never behind the camera. `Wander` is how far the channel may
				stray sideways as a fraction of its height, `Branches` how many forks split off it.
				`Glow` is the cloud lighting up around the top. ]]
			Bolts = {
				Height = { 280, 380 },
				Distance = { 300, 560 },
				Across = 340,
				Segments = 12,
				Wander = 0.16,
				Branches = { 1, 3 },
				Width = 3,
				Color = Color3.fromRGB(226, 234, 255),
				Brightness = 6,
				Lifetime = 0.4,
				Glow = {
					Texture = "rbxassetid://12713358298",
					Size = 300,
					Color = Color3.fromRGB(170, 190, 255),
					Transparency = 0.45,
					Lifetime = 0.4,
				},
			},
		},
	},

	{
		Key = "MeteorShower",
		Name = "Meteor Shower",
		Blurb = "The sky is falling.",
		Color = Color3.fromRGB(255, 138, 62),
		Weight = 10,
		Icon = UIAssets.Weather.MeteorShower,
		Mutation = "Molten",
		Look = {
			Clock = 23,
			Ambient = Color3.fromRGB(56, 44, 40),
			Outdoor = Color3.fromRGB(84, 62, 52),
			Brightness = 1.2,
			Fog = { Color = Color3.fromRGB(72, 50, 44), Start = 140, End = 1600 },
			Atmosphere = {
				Density = 0.3,
				Offset = 0.2,
				Color = Color3.fromRGB(226, 158, 116),
				Decay = Color3.fromRGB(120, 62, 40),
				Glare = 0.6,
				Haze = 1.8,
			},
			Tint = Color3.fromRGB(255, 216, 190),
		},
		--[[ The meteors themselves are the particles, and they fall SIDEWAYS as much as down —
			`Drag` is high, so the crosswind carries them across the screen. A meteor that fell
			straight down would read as orange rain. ]]
		--[[ DELIBERATELY SPARSE. A meteor shower is a handful of big bright objects, not weather —
			raise this much past ~60 and it stops being a sky full of meteors and becomes orange
			rain, which is the one thing this event must not look like. ]]
		Particles = {
			Rate = 45,
			Speed = 110,
			Size = 3.4,
			Squash = 6,
			Drag = 1.6,
			Color = Color3.fromRGB(255, 150, 70),
			Transparency = 0.2,
			Lifetime = 1.4,
			Glow = 1, -- LightEmission: the one weather that should be brighter than the sky behind it
		},
		Vfx = {
			--[[ Close to, the shower is ash and embers settling out of the sky: soft dots that cool
				from yellow to red as they drift down past the car. Thin, for the sparse rule above. ]]
			Layers = {
				{
					Texture = "rbxassetid://12713358298",
					Facing = "Camera",
					Speed = { 4, 9 },
					Spread = 25,
					Rate = 45,
					Lifetime = { 1.6, 2.6 },
					Size = { 0.35, 0 },
					Color = Color3.fromRGB(255, 214, 140),
					ColorEnd = Color3.fromRGB(220, 70, 30),
					Transparency = 0,
					Glow = 1,
					Brightness = 2,
					Wind = 6,
				},
			},
			--[[ THE METEORS THEMSELVES, as objects rather than particles: each one a burning head on a
				tail, crossing the sky ahead of you with smoke hanging behind it. Most burn out in the
				air, as real ones do; `Impact` of them come all the way down on the horizon and go up
				in the library's fireball.

				`Every` is the gap between launches, `Pool` the most in the sky at once. The path is
				measured from the camera when a meteor launches: `Distance` ahead, `Across` either
				side, starting `Height` above the road and diving at `Dive` degrees below level.
				`Speed` is studs per second along the path and `Flight` how long one that burns out
				lasts. Everything is kept well down the road, so a meteor is never a hazard and
				never lands on the car.

				LOW AND FAR, for the chase camera. It sees about 25 degrees of sky over the horizon,
				and in the city less than that between the buildings; launched 280 to 480 studs up
				they crossed above the top of the screen. The head and tail are sized for 500 to
				1,000 studs away, where a smaller one was a dash. ]]
			Meteors = {
				Every = { 0.6, 1.8 },
				Pool = 6,
				Distance = { 480, 950 },
				Across = 420,
				Height = { 140, 280 },
				Dive = { 22, 40 },
				Speed = { 280, 440 },
				Flight = { 1, 1.7 },
				Impact = 0.3,
				Head = {
					Texture = "rbxassetid://12713358298",
					Rate = 40,
					Lifetime = 0.14,
					Size = { 24, 9 },
					Color = Color3.fromRGB(255, 236, 190),
					ColorEnd = Color3.fromRGB(255, 150, 60),
					Transparency = 0,
					Glow = 1,
					Brightness = 3,
				},
				Tail = {
					Width = 12,
					Lifetime = 0.6,
					Color = Color3.fromRGB(255, 170, 80),
					ColorEnd = Color3.fromRGB(190, 50, 20),
					Brightness = 2,
				},
				Smoke = {
					Texture = "rbxassetid://13975880803",
					Flipbook = "Grid4x4",
					Rate = 22,
					Lifetime = { 1.4, 2.2 },
					Size = { 8, 22 },
					Color = Color3.fromRGB(150, 122, 110),
					Transparency = { 0.45, 1 },
					Speed = 0,
				},
				--[[ The fireball sheet's first frames are small in its canvas, so it is drawn big (at
					90 it was a speck on the horizon) and it cools from fire to smoke. `Flash` is the
					additive glow that goes up with it: most landings are behind the roadside buildings,
					and the flash over the rooftops is the part you see. ]]
				Blast = {
					Texture = "rbxassetid://14979969015",
					Flipbook = "Grid8x8",
					Size = { 150, 260 },
					Lifetime = 2.2,
					Color = Color3.fromRGB(255, 200, 130),
					ColorEnd = Color3.fromRGB(150, 110, 95),
					Transparency = 0,
					Glow = 0.6,
					Brightness = 3,
					Flash = {
						Texture = "rbxassetid://12713358298",
						Size = 300,
						Lifetime = 0.6,
						Color = Color3.fromRGB(255, 170, 90),
						Transparency = { 0.1, 1 },
						Glow = 1,
						Brightness = 2,
					},
				},
			},
		},
	},

	{
		Key = "Sandstorm",
		Name = "Sandstorm",
		Blurb = "A wall of sand is rolling in.",
		Color = Color3.fromRGB(216, 172, 96),
		Weight = 10,
		Icon = UIAssets.Weather.Sandstorm,
		Mutation = "Rusted",
		Look = {
			Clock = 12,
			-- Warmed off the first playtest, which read olive rather than sandy against this map's
			-- green-grey buildings.
			Ambient = Color3.fromRGB(112, 94, 66),
			Outdoor = Color3.fromRGB(158, 134, 96),
			Brightness = 1.6,
			Fog = { Color = Color3.fromRGB(198, 166, 112), Start = 60, End = 760 },
			Atmosphere = {
				Density = 0.46,
				Offset = 0.2,
				Color = Color3.fromRGB(232, 202, 148),
				Decay = Color3.fromRGB(158, 124, 72),
				Glare = 0.5,
				Haze = 2.6,
			},
			Tint = Color3.fromRGB(255, 238, 206),
		},
		--[[ The densest of the five, because grit is the one weather that is supposed to obscure
			things at close range — the fog event does it with fog, and this does it with particles. ]]
		Particles = {
			Rate = 950,
			Speed = 40,
			Size = 2.6,
			Squash = 2,
			Drag = 3, -- almost entirely horizontal: this is wind carrying grit, not grit falling
			-- Well clear of `Fog.Color` (198,166,112) — see the contrast note above, which this
			-- event is the cautionary tale for.
			Color = Color3.fromRGB(248, 228, 186),
			Transparency = 0.42,
			Lifetime = 1.1,
			Glow = 0.12,
		},
		Vfx = {
			Layers = {
				--[[ The original grit, now stretched ALONG the wind (its `Squash` of 2 drew each grain
					across its own travel) and finer: at the original 2.6 studs, stretched properly, the
					grains near the camera read as brushstrokes. ]]
				{
					Rate = 900,
					Speed = 40,
					Size = 1.3,
					Squash = -3,
					Wind = 30,
					Color = Color3.fromRGB(248, 228, 186),
					Transparency = 0.42,
					Lifetime = 1.1,
					Glow = 0.12,
				},
				--[[ Billows of dust rolling across the road on the wind: the library's noisy cloud,
					big and turning slowly. This is what makes it a sandSTORM and not sand in the air: the
					air itself moving past in lumps.

					DARKER THAN THE HAZE, the one layer here that breaks the lighter-than-its-fog rule
					the other way. Pale, they were the haze's own colour and vanished; a darker, redder
					sand reads as a dust cloud rolling through it. ]]
				{
					Texture = "rbxassetid://18450579677",
					Ground = true,
					Box = { Width = 300, Height = 14, Depth = 220, Ahead = 80, Lift = 6 },
					Facing = "Camera",
					Direction = "Across",
					Speed = { 40, 62 },
					Rate = 26,
					Lifetime = { 2.2, 3.2 },
					Size = { 20, 34 },
					Color = Color3.fromRGB(178, 138, 92),
					Transparency = { 1, 0.42, 0.5, 1 },
					Rotation = 180,
					Spin = 25,
				},
				--[[ Gusts: the library's wind swooshes, one still frame each, streaking across the road
					faster than the dust so the wind has a direction you can read. A streak lays its
					texture's WIDTH along its travel, so the sideways swoosh needs no turning. ]]
				{
					Texture = "rbxassetid://12943289715",
					Flipbook = "Grid2x2",
					RandomFrame = true,
					Box = { Width = 260, Height = 30, Depth = 160, Ahead = 60, Lift = -4 },
					Facing = "Streak",
					Direction = "Across",
					Speed = { 90, 130 },
					Rate = 18,
					Lifetime = { 0.8, 1.2 },
					Size = 12,
					Color = Color3.fromRGB(255, 242, 214),
					Transparency = { 1, 0.25, 1 },
				},
			},
		},
	},

	--[[ THE ONE EVENT THAT IS NOT WEATHER, and the only one that changes how a run PLAYS.

		Rush hour is the road at its busiest and slowest: nearly twice the cars, arriving twice as
		often, all of them driving about a fifth slower than they otherwise would. See `Traffic`
		below and the contract for it in this table's header.

		WHY THAT IS A GOOD THING TO STEAL IN, which is the design and not a side effect. Every other
		event pays by putting a RARE car on the road and asking you to find it; this one pays by
		putting an ORDINARY car within reach of every jump you make. So its mutation is the cheapest
		of the six and by far the most common (see `Impatient`) — the money comes from volume, and
		the event reads as "go now, they are everywhere" rather than "go and hunt".

		AND IT IS NOT FREE. Twenty-one cars on a five-lane road at four fifths pace is a road with
		much less daylight in it, so the same density that hands you targets is the thing that will
		put you into the back of one. That trade is the event.

		The sky is the drive home: a low sun, long shadows and warm smog, with nothing falling. It is
		the one `Look` here that is not bad weather, which is most of what stops it reading as a
		sixth kind of storm. ]]
	{
		Key = "RushHour",
		Name = "Rush Hour",
		Blurb = "The road is packed.",
		Color = Color3.fromRGB(255, 186, 72),
		Weight = 10,
		Icon = UIAssets.Weather.RushHour,
		Mutation = "Impatient",
		Look = {
			Clock = 17.6, -- low enough for long shadows, high enough that the road is still lit
			Ambient = Color3.fromRGB(92, 76, 58),
			Outdoor = Color3.fromRGB(150, 120, 88),
			Brightness = 1.5,
			--[[ The one event whose fog is pushed OUT rather than in. Rush hour must not cost you
				sight lines — the road is already full of cars, and taking the draw distance away as
				well would make it the hardest event in the game by accident. This is haze on the
				horizon and nothing nearer. ]]
			Fog = { Color = Color3.fromRGB(198, 148, 96), Start = 200, End = 2000 },
			Atmosphere = {
				Density = 0.26,
				Offset = 0.35,
				Color = Color3.fromRGB(246, 210, 158),
				Decay = Color3.fromRGB(152, 100, 62),
				-- The highest `Glare` of the six: a sun this low IS the effect, and glare is what
				-- puts it in the frame rather than merely tinting everything gold.
				Glare = 0.75,
				Haze = 2,
			},
			Tint = Color3.fromRGB(255, 228, 192),
		},
		-- Nothing falls out of a clear evening sky, and inventing something would read as drizzle —
		-- the same call `Fog` makes above.
		Particles = nil,
		--[[ Still nothing falling. What the library adds is the air of a jammed road at golden hour:
			dust motes lit up by the low sun, drifting and glinting, and a thin warm smog lying at
			bumper height. Both faint on purpose: this is the one event that is not bad weather. ]]
		Vfx = {
			Layers = {
				-- Gold, not cream: a paler mote read as snow.
				{
					Texture = "rbxassetid://12713358298",
					Box = { Width = 120, Height = 30, Depth = 120, Ahead = 30, Lift = -4 },
					Facing = "Camera",
					Direction = "Up",
					Spread = 180,
					Speed = { 0.5, 2 },
					Rate = 45,
					Lifetime = { 2.5, 4 },
					Size = 0.22,
					Color = Color3.fromRGB(255, 204, 128),
					Transparency = { 1, 0.35, 0.35, 1 },
					Glow = 1,
					Brightness = 1.5,
				},
				{
					Texture = "rbxassetid://13975880803",
					Flipbook = "Grid4x4",
					Ground = true,
					Box = { Width = 160, Height = 3, Depth = 200, Ahead = 70, Lift = 1 },
					Facing = "Camera",
					Direction = "Up",
					Speed = { 1, 2 },
					Rate = 10,
					Lifetime = { 3, 4 },
					Size = { 10, 22 },
					Color = Color3.fromRGB(196, 160, 124),
					Transparency = { 1, 0.82, 1 },
					Spin = 10,
					Rotation = 180,
				},
				-- A thin warm veil over the skybox's midday blue, so the sky agrees with the low sun.
				{
					Texture = "rbxassetid://7216854921",
					Box = { Width = 900, Height = 30, Depth = 1000, Ahead = 420, Lift = 120 },
					Facing = "Camera",
					Direction = "Across",
					Speed = { 3, 6 },
					Rate = 5,
					Prewarm = 40,
					Locked = true,
					Lifetime = { 9, 12 },
					Size = 300,
					Color = Color3.fromRGB(255, 176, 120),
					Transparency = { 1, 0.55, 0.55, 1 },
					Rotation = 180,
					Spin = 3,
				},
			},
		},
		--[[ 16 forward cars becomes 28, a routine spawn attempt every ~0.45s instead of every ~1.3s,
			25 booked into the opening prime, and everybody at four fifths of their usual cruise.

			`Cars` is the number that costs something: traffic is the most expensive thing the road
			draws (`TrafficConfig.CastShadows`), so this is the one figure to pull if rush hour turns
			out to be where low-end devices fall over. 1.75 was chosen as the most that still fits
			the spawn geometry comfortably — five lanes, `SpawnGap` 70, and a live band of ~1,860
			studs hold well over a hundred cars, so the road is nowhere near packed solid at 28. ]]
		Traffic = { Cars = 1.25, Spawn = 0.75, Prime = 1.25, Speed = 0.9 },
	},
}

-- === The mutations ==========================================================
--[[ One entry per mutation. `Key` is the identity and carries the same warning `Events.Key` does,
	with one more reason behind it: a mutation key ends up INSIDE A CAR KEY in the save file
	("Camaro:6:Charged"), so renaming one orphans every copy of that car anybody owns.

	=== THE FOUR FIELDS THE CARD ASKED FOR =====================================================

	    Event          which weather event this belongs to, by key
	    EventChance    per-spawn chance while that event is running in this world
	    AllowNatural   may it turn up with no event at all?
	    NaturalChance  per-spawn chance when it does

	`AllowNatural` is a switch of its own rather than "NaturalChance = 0" so that the intent is
	readable: a zero is something somebody might have forgotten to fill in, and a `false` is a
	decision. The two rarest mutations have it off, which is what makes their events worth chasing —
	if `Molten` turned up on a clear day, the meteor shower would only be a way of getting it faster.

	=== SIZING THE TWO MULTIPLIERS =============================================================

	`Multiplier` scales the WHOLE RUN PAYOUT on a bank (`RewardConfig.payoutFor`), distance and near
	misses together. A four-thousand-stud run pays 400, so a Molten bank pays 2,000 — about four
	minutes of a full lot of world 1's top car. That is a jackpot and not a shortcut past a world.

	`ValueMultiplier` scales that car's INCOME PER SECOND and therefore its sale price, forever, for
	as long as it is parked (`GarageConfig.rateOf`). It is much smaller than `Multiplier` and it has
	to be: income compounds over a session and a payout does not. At 2.5 a Molten world-1 top car
	earns 195/s against 78, which is worth going out for and is still under the bottom car of the
	next world. Take this table past ~3 and a lucky bank starts skipping a world's cash gate.

	`Weight` breaks a tie when two mutations could both land on the same spawn, which today can only
	happen between a natural roll and an event roll. Higher = more likely to win the tie.

	=== WHAT DRESSES THE CAR ===================================================================

	`Fill`/`Outline` are the `Highlight`'s two colours and `FillTransparency` is how much of the
	paintwork still shows through — near 1 for a mutation that should only rim the car, lower for
	one that should stain it. `Sparkle` is the particles coming off the car (below); nil for a
	mutation whose whole tell is the highlight. `Color` is the badge over the car and the payoff row
	on the notice card, and is usually the outline lifted until it reads on a dark panel.

	=== `Sparkle`: THE PARTICLES, ONE LAYER OR SEVERAL ========================================

	One spec, or an array of up to four (`CarMutation`'s `MAX_LAYERS`), each its own pooled emitter
	filling the car's hit box. Every field is optional, and a spec that sets only the first group
	renders exactly as the single sparkle always did:

	    Rate, Size, Lifetime, Speed, Transparency, Glow (LightEmission), Lift (up; below 0 falls),
	    Color (default the outline), Texture (default the stock sparkle)

	and the layered looks add:

	    Flipbook      "Grid4x4" (or 2x2, 8x8) plays the texture as a sheet, once per particle life
	    SizeEnd       size at the end of a life, for a flame that swells or an ember that dies out
	    ColorEnd      colour at the end of a life
	    Fade          transparency at the end of a life
	    Brightness    on top of Glow, for a glow that has to beat a dark sky
	    Speed         a number, or { min, max }
	    Spread        cone half-angle in degrees (35)
	    Rotation      how far either way of upright a particle starts (180, any angle)
	    Spin          how fast either way it turns (90)
	    Drag          how quickly it slows
	    Inherit       how much of the car's velocity it keeps (0.75); lower trails it further
	    Locked        pinned to the car, riding the paintwork (the Charged arcs)
	    Surface       spawn on the roof plane (the hit box's top face) instead of the whole box
	    ZOffset       draw nudged toward the camera

	THE LAYERED TEXTURES COME FROM THE VFXer PLUGIN'S TEXTURE LIBRARY (its Library window in Studio),
	and they are other creators' uploads referenced by id. If one is ever taken down its particles
	simply stop drawing and nothing errors, so a layer that has gone invisible is the first thing to
	check against the library.

	How strongly the outline is drawn is NOT a per-mutation number. It is the two flags in
	`Outline`, below this table, because the complaint they answer ("the outlines are too
	distracting") is about all six at once.

	=== `Skin`: THE CAR ITSELF, NOT A PASS DRAWN OVER IT =======================================

	Optional, and on four of the six. A Highlight can only wash a colour over a car; it cannot make
	one look corroded, cracked, wet or see-through, and those four mutations are named for exactly
	that. So their parts are put into an engine material instead, which needs no art and no upload:

	    Material       the `Enum.Material` the parts wear while mutated
	    Color          the part `Color` that goes with it (a material's own pattern is tinted by it).
	                   LEAVE IT OUT TO KEEP THE CAR'S OWN PAINT: the colour, the texture and the
	                   detail map all stay and only the material changes. That is `Soaked`
	    Parts          "Paint" for the paintwork only, "All" for every visible part of the car
	    Transparency   optional, and nothing sets one today. Soaked's glass did (0.45) until it was
	                   judged too see-through; the support stays for the next skin that wants it

	A SKIN WITH NO `Color` DOES NOTHING TO A PANEL WEARING A DETAIL MAP. A `SurfaceAppearance`
	draws its own maps and ignores the part's material, and its `Reflectance` too: measured
	2026-09-14 on a red M5, `Glass`, `Reflectance` 1 and a cleared roughness map all rendered
	identical to the plain car. So a painted car on a mapped body (the `PaintDetails` list) keeps
	its exact look under a paint-keeping skin, and only the particles say it is mutated. Parking the
	map would let the material through, but it would also flatten the grille, trim and mirror glass
	to body colour, which is the bug the maps exist to fix.

	Two go without, deliberately. `Impatient` is the commonest car on the table, a commuter in a jam
	rather than a car the weather did something to, and five of them in view should not be five cars
	in a new material. `Charged` wore an electric-blue `Foil` until Dylan asked for the car's own
	paint back (2026-09-14): the lightning arcs crawling over it already say what happened to it.

	"Paint" is `CarPaint.parts`, the same audited answer a repaint uses, so the trim, the grille, the
	glass and the lamps keep the artist's look and the car still has a face. "All" is for the ghost,
	where the whole car going spectral IS the look.

	IT IS REVERSIBLE, and it has to be: a traffic shell is pooled and comes back out as an ordinary
	car, and stealing a plain car while driving a rusted one has to take the rust off. `CarMutation`
	remembers what each part wore on the part itself and puts it back. The PAINT INDEX is untouched
	throughout, because it is an attribute and not the part colour, so a Rusted car banked in red is
	still a red car underneath its rust. Measured on the Camaro in Studio before choosing:
	`CorrodedMetal` and `CrackedLava` keep their pattern on these meshes, `ForceField` reads as a
	ghost in the fog event's own light, and plain transparency did not: it left a dark see-through
	car, because the Highlight that was meant to make it pale stopped drawing (below).

	A SKIN USUALLY WANTS NO HIGHLIGHT FILL. The material is the tell, and a colour wash over it
	flattens the pattern that made it worth having. `Highlight = false` goes further and drops the
	Highlight entirely, which is the ghost's case: an Occluded Highlight draws NOTHING, fill or
	outline, on a part in a transparent material, so on a ForceField car it would only spend one of
	the ~31 Highlights Roblox will draw. ]]
WeatherConfig.Mutations = {
	{
		Key = "Soaked",
		Name = "SOAKED",
		Event = "Rain",
		EventChance = 0.2,
		AllowNatural = true,
		NaturalChance = 0.02,
		Multiplier = 1.5,
		ValueMultiplier = 1.25,
		Weight = 10,
		Color = Color3.fromRGB(96, 176, 236),
		Fill = Color3.fromRGB(80, 150, 220),
		-- No wash: the water is the tell, and a blue fill would tint the car's own paint.
		FillTransparency = 1,
		Outline = Color3.fromRGB(150, 220, 255),
		--[[ THE CAR'S OWN PAINT, WET: the paintwork goes to `Glass` with no `Color`, so it keeps its
			colour and texture and picks up a glossy sky reflection on the roof and bonnet while the
			flanks stay the true paint. That is how wet paint reads, and it is the reflectance Dylan
			asked for (2026-09-14) without the cost of the `Reflectance` property itself, which blends
			the sky's colour over the whole car: a red car went visibly pink at 0.12 and pink at 0.2.

			It used to be a fixed aqua `Glass` (100,185,235), so every Soaked car was the same blue
			whatever it was painted, and before that 0.45 see-through. Dylan asked for the original
			colour back and the particles to carry the mutation. Also tried and dropped: `Ice` read as
			FROZEN rather than wet.

			A painted car on a mapped body shows no gloss (see `Skin` in the header): its detail map
			ignores the material, so there the spray is the whole tell. ]]
		Skin = { Material = Enum.Material.Glass, Parts = "Paint" },
		--[[ THE WATER: spray thrown off it and left hanging on the road behind, the library's soft
			smoke sheet in white-blue. It is the one layer that reads through the rain event's own
			streaks, and on the player's own car it stays at road level and fades before it reaches the
			chase camera.

			SPRAY ONLY, on Dylan's call. It used to carry sparkles too: falling drip glints (18 a second,
			later 70) and glints pinned to the paint as beaded water. Both read as sparkle rather than
			water, so they are gone; if the spray alone ever reads too quiet, raise its `Rate` and
			`Size` rather than bringing them back. ]]
		Sparkle = {
			Texture = "rbxassetid://13975880803",
			Flipbook = "Grid4x4",
			Rate = 14,
			Size = 1.8,
			SizeEnd = 4,
			Lifetime = 0.8,
			Speed = { 1, 3 },
			Spread = 40,
			Lift = 0.5,
			Spin = 20,
			Inherit = 0.6,
			Glow = 0.2,
			Transparency = 0.4,
			Fade = 0.9,
			Color = Color3.fromRGB(215, 235, 250),
		},
		Icon = "", -- no art yet; `Modules/CarMutation` draws the badge from `Name` and the multiplier
	},

	{
		Key = "Rusted",
		Name = "RUSTED",
		Event = "Sandstorm",
		EventChance = 0.15,
		AllowNatural = true,
		NaturalChance = 0.01,
		Multiplier = 2,
		ValueMultiplier = 1.4,
		Weight = 12,
		Color = Color3.fromRGB(196, 122, 58),
		Fill = Color3.fromRGB(150, 88, 42),
		-- No wash: the corroded paintwork is the tell, and an orange fill over it would flatten the
		-- pattern back into a tint.
		FillTransparency = 1,
		Outline = Color3.fromRGB(232, 158, 82),
		--[[ The paintwork corroded through. `Color` only TINTS this material, and gently: anything
			from 74 to 150 on red read as the same warm rust on the Camaro in Studio, near-black turns
			it to dark steel with rust patches, and pure green does turn it green, so the value is live
			but it is the material's own pattern doing most of the work. Trim, grille, glass and lamps
			stay the artist's, which is what keeps it reading as a rusted car and not a car-shaped lump
			of rust. ]]
		Skin = { Material = Enum.Material.CorrodedMetal, Color = Color3.fromRGB(96, 48, 24), Parts = "Paint" },
		--[[ Flakes coming OFF it, not a glint over it: no glow, the engine's plain square rather than
			the sparkle (it tumbles, which is what a flake does), a darker brown than the outline, and
			`Lift` below zero so they fall to the road instead of rising off the roof. Thin, because
			the rust is already doing the work. ]]
		Sparkle = {
			Rate = 10,
			Speed = 1.5,
			Size = 0.22,
			Lifetime = 1.2,
			Transparency = 0.2,
			Glow = 0,
			Lift = -9,
			Color = Color3.fromRGB(104, 54, 28),
			Texture = "rbxasset://textures/particles/SquareParticle.png",
		},
		Icon = "",
	},

	{
		Key = "Ghost",
		Name = "GHOST",
		Event = "Fog",
		EventChance = 0.12,
		AllowNatural = true,
		NaturalChance = 0.005,
		Multiplier = 2.5,
		ValueMultiplier = 1.6,
		Weight = 14,
		Color = Color3.fromRGB(196, 220, 236),
		--[[ THE WHOLE CAR GOES SPECTRAL. It used to be a pale Highlight wash over an ordinary opaque
			car, a tint rather than a ghost. `ForceField` is the engine's own
			shimmering, see-through material, so every visible part of the car (glass, wheels and
			cabin included) turns into a glowing shell you can see the road through.

			Still the one mutation that makes the car harder to see, which is the trade the fog event
			is built around: the rare car is out there and the weather is hiding it. The badge is
			what finds it at distance.

			CYAN, NOT WHITE. A near-white ForceField dissolved into the fog's own pale grey in Studio.
			A strong teal held up best against the grey but leaned green, so this is a cyan with a
			little of that teal in it.

			`Highlight = false` because a transparent material takes no Highlight at all (header). ]]
		Fill = Color3.fromRGB(210, 232, 248),
		FillTransparency = 1,
		Outline = Color3.fromRGB(240, 250, 255),
		Highlight = false,
		Skin = { Material = Enum.Material.ForceField, Color = Color3.fromRGB(130, 230, 245), Parts = "All" },
		--[[ Ectoplasm curling out of it: the library's soft smoke sheet in the skin's own cyan, half
			see-through and fading as it swells. `Inherit` below the default so a moving ghost leaves a
			short trail of wisps behind it, which in the fog is the tell that there is a car there at
			all. Not lower than 0.7: on the player's OWN ghost at 0.55 the trail streamed back through
			the chase camera as big cyan puffs across the speedometer. ]]
		Sparkle = {
			Texture = "rbxassetid://16924860127",
			Flipbook = "Grid4x4",
			Rate = 6,
			Size = 2.2,
			SizeEnd = 4.5,
			Lifetime = 1.6,
			Speed = { 1, 2.5 },
			Spread = 20,
			Lift = 1.2,
			Glow = 0.6,
			Brightness = 1.5,
			Spin = 30,
			Inherit = 0.7,
			Color = Color3.fromRGB(150, 240, 255),
			Transparency = 0.2,
			Fade = 0.8,
		},
		Icon = "",
	},

	{
		Key = "Charged",
		Name = "CHARGED",
		Event = "Thunderstorm",
		EventChance = 0.08,
		AllowNatural = false,
		NaturalChance = 0,
		Multiplier = 3.5,
		ValueMultiplier = 2,
		Weight = 16,
		Color = Color3.fromRGB(126, 156, 255),
		Fill = Color3.fromRGB(96, 130, 255),
		-- No wash: the arcs are the tell, and a blue fill would tint the car's own paint.
		FillTransparency = 1,
		Outline = Color3.fromRGB(190, 210, 255),
		--[[ NO SKIN: the car keeps its own paint and the lightning below is the whole look. It wore an
			electric-blue `Foil` (45,85,235) until 2026-09-14, which made every Charged car the same
			blue whatever colour it was, and Dylan asked for the original paint back. `Neon` had been
			tried before that and read as a flat blue cut-out. ]]
		Sparkle = {
			--[[ Lightning crawling over the panels: the library's 4x4 sheet of a blue arc growing,
				kinking and breaking up, one play per particle. `Locked`, so the arcs stay ON the car
				at any speed instead of streaming off the back like exhaust. Filling the whole box
				rather than the roof plane puts them on the doors and wings too; the body hides the
				ones that start deep inside it, which is what the rate is sized against (two or three
				on show at once). The sheet is already blue, so its colour is left white. ]]
			{
				Texture = "rbxassetid://109073879869955",
				Flipbook = "Grid4x4",
				Rate = 26,
				Size = 3.2,
				Lifetime = 0.35,
				Speed = 0,
				Lift = 0,
				Spin = 0,
				Glow = 1,
				Brightness = 3,
				Transparency = 0,
				Locked = true,
				Color = Color3.new(1, 1, 1),
			},
			-- The sparks spitting off it: short, fast and glowing is already what a spark is.
			{ Rate = 40, Speed = 9, Size = 0.45, Lifetime = 0.35, Transparency = 0.2, Glow = 1 },
		},
		Icon = "",
	},

	{
		Key = "Molten",
		Name = "MOLTEN",
		Event = "MeteorShower",
		EventChance = 0.05,
		AllowNatural = false,
		NaturalChance = 0,
		Multiplier = 5,
		ValueMultiplier = 2.5,
		Weight = 20,
		Color = Color3.fromRGB(255, 138, 62),
		Fill = Color3.fromRGB(255, 104, 32),
		-- No wash, for the rust's reason: an orange fill over the lava would bury the glowing cracks
		-- under a flat orange.
		FillTransparency = 1,
		Outline = Color3.fromRGB(255, 208, 130),
		--[[ The paintwork turned to cooling lava: `CrackedLava` is dark rock with glowing cracks, and
			it glows by itself, so it reads best exactly where this mutation lives, under the meteor
			shower's night sky. Trim and lamps stay the artist's, for the rust's reason. ]]
		Skin = { Material = Enum.Material.CrackedLava, Color = Color3.fromRGB(255, 110, 40), Parts = "Paint" },
		--[[ The rarest car in the game, so the loudest of the six, and every layer of it is still a
			thing hot metal actually does. Tuned under the meteor shower's own night sky. ]]
		Sparkle = {
			--[[ Flame licking up off the roof line: the library's 4x4 fire burst, one play per life,
				nearly upright (a flame that spins reads as a pinwheel). `Surface`, so it rises off the
				top of the car instead of burning away unseen inside the body. ]]
			{
				Texture = "rbxassetid://111860228388694",
				Flipbook = "Grid4x4",
				Surface = true,
				Rate = 9,
				Size = 2.2,
				SizeEnd = 3.2,
				Lifetime = 0.7,
				Speed = { 1.5, 3 },
				Spread = 10,
				Lift = 3,
				Rotation = 12,
				Spin = 0,
				Inherit = 0.9,
				-- Brightness stays at 1: at 2 the additive glow burned the flame to near white.
				Glow = 1,
				Brightness = 1,
				Transparency = 0,
				ZOffset = 0.3,
				Color = Color3.fromRGB(255, 140, 50),
				ColorEnd = Color3.fromRGB(220, 60, 20),
			},
			--[[ The embers. They used to be the stock sparkle at 0.8 studs, which is a four-pointed
				STAR, and on the lava they read as fairy dust. Now a soft dot a third of a stud across
				that cools from yellow to red and burns out, slowed by `Drag` so it floats. ]]
			{
				Texture = "rbxassetid://12713358298",
				Rate = 26,
				Size = 0.35,
				SizeEnd = 0,
				Lifetime = 1.6,
				Speed = { 4, 8 },
				Spread = 30,
				Lift = 3,
				Drag = 1.2,
				Spin = 0,
				Glow = 1,
				Brightness = 3,
				Transparency = 0,
				Color = Color3.fromRGB(255, 230, 150),
				ColorEnd = Color3.fromRGB(220, 60, 20),
			},
			--[[ Smoke coming off the hot paint. A warm grey well LIGHTER than this event's fog, which
				is dark (72,50,44): the first try was a smoke colour and vanished into the sky, the trap
				in the Events header. Thin, because it is the one layer that can hide the road. ]]
			{
				Texture = "rbxassetid://13975880803",
				Flipbook = "Grid4x4",
				Surface = true,
				Rate = 5,
				Size = 2,
				SizeEnd = 4.5,
				Lifetime = 1.8,
				Speed = { 2, 3.5 },
				Spread = 15,
				Lift = 1.5,
				Spin = 20,
				Inherit = 0.8,
				Glow = 0,
				Color = Color3.fromRGB(128, 112, 104),
				Transparency = 0.3,
				Fade = 0.75,
			},
		},
		Icon = "",
	},

	--[[ THE ODD ONE OUT, AND DELIBERATELY THE WORST ONE. Every mutation above is a rare car found in
		bad weather; this is an ordinary commuter in a traffic jam, and the whole of `RushHour` is
		built on that difference — the event pays by VOLUME rather than by rarity.

		So it is the cheapest multiplier on the table AND the commonest chance on it, which is the
		combination nothing else here has. At 0.22 against rush hour's 21 cars there are four or five
		of these in view at any moment, against `Soaked`'s two out of twelve; the event should read as
		"they are everywhere, go now", and a 1-in-5 that pays 1.6 does that where a 1-in-20 that pays
		5 would not.

		LOWEST `Weight` ON THE TABLE for the same reason, and it matters more here than anywhere else:
		with a fifth of the road wearing this, a `Soaked` or a `Rusted` car that also rolls during
		rush hour is the rarer and more interesting answer, and ties should go to it every time.

		Brake-light red rather than the event's gold, which is the one place a mutation deliberately
		does not echo its own sky. Gold on a gold-hour road is invisible, and a jam is a wall of red
		lights anyway. ]]
	{
		Key = "Impatient",
		Name = "IMPATIENT",
		Event = "RushHour",
		EventChance = 0.22,
		AllowNatural = true,
		NaturalChance = 0.02,
		Multiplier = 1.6,
		ValueMultiplier = 1.3,
		Weight = 6,
		Color = Color3.fromRGB(255, 116, 100),
		Fill = Color3.fromRGB(226, 62, 52),
		FillTransparency = 0.7,
		Outline = Color3.fromRGB(255, 150, 130),
		-- Thin and slow: this is the one mutation there are five of on screen at once, and five
		-- emitters at `Charged`'s forty a second is a particle budget spent on the common case.
		Sparkle = { Rate = 8, Speed = 2, Size = 0.4, Lifetime = 0.8, Transparency = 0.55, Glow = 0.3 },
		Icon = "",
	},
}

-- === The outline test =======================================================
--[[ TWO FLAGS FOR THE HIGHLIGHT'S RIM ON EVERY MUTATED CAR, because the outline was reported as
	too distracting and nobody knows yet which fix is right. Flip them here, or live from the F2
	panel's Weather tab (which changes this client only, see `AdminPanelController`).

	    Hidden   no outline at all. Wins over `Soft`.
	    Soft     the outline stays, faded to `SoftTransparency` so it rims the car without glowing
	    neither  the outline at full strength, which is how it shipped before this test

	Only the OUTLINE. The fill is each mutation's own `FillTransparency`, and since the skins it is
	only `Impatient` that still has one, so hiding the outline leaves that car as a red wash rather
	than a plain car. A mutation with no fill and a hidden outline has nothing left for its
	Highlight to draw, and `CarMutation` switches it off rather than keeping it enabled, which
	gives one back to the ~31-Highlight budget. With `Hidden` on, that is every mutation but
	`Impatient`. ]]
WeatherConfig.Outline = {
	-- ON as of 2026-09-14, Dylan's pick after the test. `Soft` is left on underneath it so turning
	-- this off goes back to the faded rim rather than the full one.
	Hidden = true,
	Soft = true,
	-- 0 is the old full-strength rim and 1 is none. At 0.65, in a playtest, it was a thin pale rim
	-- on a Molten car under the meteor shower's night sky and all but gone against the sandstorm.
	SoftTransparency = 0.65,
}

--- The `OutlineTransparency` every mutated car's Highlight takes, resolved from the two flags above.
--- One function so the car and the admin panel can never disagree about what the flags mean.
function WeatherConfig.outlineTransparency(): number
	local flags = WeatherConfig.Outline
	if flags.Hidden then
		return 1
	end
	if flags.Soft then
		local soft = flags.SoftTransparency
		return if type(soft) == "number" and soft == soft then math.clamp(soft, 0, 1) else 0.65
	end
	return 0
end

-- === The badge over the car =================================================
--[[ The pill `Modules/CarMutation` hangs above a mutated traffic car so you can tell what you are
	about to land on BEFORE you commit to the jump. That timing is the whole requirement: the steal
	arc takes about a second and a half and cannot be called off once it is launched, so a tell that
	only reads at ten studs is a tell that arrives after the decision.

	Hence a billboard rather than anything on the bodywork. `MaxDistance` is generous — a car 340
	studs out is one you are still closing on — and `Size` is in studs so it holds its apparent size
	rather than growing as you approach.

	`StudsOffset` clears the roof of the tallest body on the roster. Sized off the model's own
	bounding box at build time and offset from there, so it sits over a hatchback and a van alike.

	=== IT IS MADE OF THE KIT NOW, AND THIS TABLE SHRANK BECAUSE OF IT — 2026-08-28 ===========

	It used to be a `Frame` with a `UICorner`, a `UIStroke` and a background at the mutation's own
	`Color`, which is the same rounded-rect-and-neon-outline the lobby notice was rebuilt to get
	away from two days earlier — and the two were describing the SAME mutation to the same player,
	one over the car and one in a toast. So the badge is the notice's own sentence now: the event's
	glyph in a kit slot well, then a kit pill carrying the name and the multiplier.

	Four fields went with that, and none of them has a replacement here because the ART now decides
	what they used to: `BackgroundTransparency`, `TextColor`, `StrokeColor` and `StrokeTransparency`
	are all properties of a plate this badge no longer draws. The pill's face and its caption colour
	come from `noticePill`, which is the same lookup the world card's flag uses, so a MOLTEN car
	wears the same red pill on the road as it does on the Teleport page. ]]
WeatherConfig.Badge = {
	Enabled = true,
	--[[ WIDER THAN IT WAS (9x3), and forced rather than chosen: the well and the pill sit side by
		side, and at 0.994:1 and 3.891:1 respectively they come to about 3.6 of the badge's own
		height. Anything under about 3.72:1 and the pill starts losing height against the box while
		the row spills past its ends, both silently — so this number and that file's layout constants
		are one decision, and that is where the arithmetic is written out.

		AND NO WIDER THAN THAT. Rush hour puts four or five mutated cars on screen at once, so a
		badge is a thing there can be a wall of; 11.8 studs is about one car width. Height held at 3
		so it sits exactly as tall over the roof as it always did. ]]
	Size = Vector2.new(11.8, 3),
	Clearance = 2.4, -- studs above the top of the car's own bounding box
	MaxDistance = 340,
	--[[ Ubuntu BOLD, the kit's face — and a `Font` object rather than an `Enum.Font`, because
		`Enum.Font.Ubuntu` is Ubuntu REGULAR. That is not a guess: the notice card measured the two
		at 304 against 319 `TextBounds` on one string, and this badge asked for the enum. One
		lighter weight in a UI that is bold everywhere else is most of what "looks like a prototype"
		means. Written to `FontFace`, never to `Font`. ]]
	FontFace = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold),
	--[[ The badge bobs so it separates from the car under it at distance. Static, it reads as a
		decal on the roof; a slow float reads as a marker. Studs, and seconds for a full cycle. ]]
	Bob = 0.35,
	BobPeriod = 1.9,
}

-- === The lobby notice's palette =============================================
--[[ WHICH OF THE KIT'S SEVEN PILLS AN EVENT'S PAYOFF LINE IS DRAWN ON.

	The notice card is a page of the `car ui` kit and is made of the kit's own parts, the same way
	the forecourt billboard is (`assets/ui/upgrades/README.md`). That buys the border, the inner rim
	and the weave for free, and it costs exactly one thing: THE KIT HAS NO SURFACE THAT CAN BE
	PAINTED AN ARBITRARY COLOUR. Its panels are textures and its title cap is `#0066FF`, so the card
	cannot simply be tinted `event.Color` the way the old flat frame's `UIStroke` was.

	It does not need to be. Two things on the card already carry colour and both of them are art:
	the event's own GLYPH (`UIAssets.Weather`, drawn in the event's palette) and the PILL under it.
	This table is the second one — the nearest kit pill to what the event pays out, picked against
	the idle faces recorded in `assets/ui/pills/README.md`.

	THE NOTICE ITSELF STOPPED WEARING ONE ON 2026-09-15: a pill is the kit's button, and on a toast
	with nothing to press it read as one. Its payoff is plain type in the mutation's `Color` now.
	The world card's flag and the badge over a mutated car still read this table:

	    Blue #0066FF   Silver #B9CAEC   Orange #FFA200   Sky #61B4E4
	    Red  #EB703A   Purple #D03AEB   Green  #2FA40F

	`Text` is a property of the STATE, not of the label, for the reason `UpgradeConfig
	.ButtonTextColors` writes up at length: white on the pale faces (Silver at luma 200, Orange at
	172, Sky at 168) is around 1.5:1 and unreadable, so those three take the kit's own outline navy
	instead. Change a pill here and change its text colour in the same edit.

	SIX EVENTS AND SEVEN PILLS, so Purple is spare and Orange is worn twice. Sandstorm and Rush Hour
	are both amber events and both land on it; they are never on screen together, because a player
	has one world and a world has one event, and the glyph tells them apart at a glance anyway. ]]
local PILL_LIGHT = Color3.new(1, 1, 1)
local PILL_DARK = Color3.fromRGB(21, 29, 45) -- #151D2D, the kit's outline navy

WeatherConfig.NoticePills = {
	-- SOAKED is #60B0EC and Sky's face is #61B4E4 — the closest match in the set by a distance.
	Rain = { Pill = "Sky", Text = PILL_DARK },
	-- GHOST is #C4DCEC, pale and desaturated; Silver is the only pill in that register.
	Fog = { Pill = "Silver", Text = PILL_DARK },
	-- CHARGED is #7E9CFF. Blue is more saturated than that but it is the only pill on the hue;
	-- Purple is magenta and reads as a different weather entirely.
	Thunderstorm = { Pill = "Blue", Text = PILL_LIGHT },
	-- MOLTEN is #FF8A3E against Red's #EB703A. Red rather than Orange despite the name: the kit's
	-- "Red" pill is an orange-red, and it is nearer molten than the amber Orange one is.
	MeteorShower = { Pill = "Red", Text = PILL_LIGHT },
	-- RUSTED is #C47A3A, and Orange #FFA200 is the nearest face left once Red is spoken for.
	Sandstorm = { Pill = "Orange", Text = PILL_DARK },
	-- IMPATIENT is #FF7464. Orange again, and see the note above on why sharing is safe.
	RushHour = { Pill = "Orange", Text = PILL_DARK },
}

--- The pill a key with no entry falls back to. Silver is the kit's neutral and the one colour that
--- claims nothing about what the weather is, which is the right thing to say about an event this
--- build has never heard of.
WeatherConfig.NoticePillFallback = { Pill = "Silver", Text = PILL_DARK }

--- The pill an event with no mutation gets. Kept separate from the fallback above because "this
--- event pays nothing extra" and "this build does not know this event" are different facts.
function WeatherConfig.noticePill(key: unknown)
	if type(key) ~= "string" then
		return WeatherConfig.NoticePillFallback
	end
	return WeatherConfig.NoticePills[key] or WeatherConfig.NoticePillFallback
end

--[[ THE SAME PILL, ASKED FOR BY MUTATION INSTEAD OF BY EVENT — which is what the badge over the
	car and the world card's flag both hold.

	It routes through the mutation's own `Event` rather than keeping a second table, and that is the
	entire point of it: a MOLTEN car has to wear the same red pill on the road, on the world card and
	in the notice that announced the meteor shower, or the three surfaces are describing three
	different things to the same player. One table, three callers, no way for them to drift.

	A mutation with no `Event` (none ships today; a purely natural one is legal) falls to the neutral
	silver, which says nothing about weather — the right thing to say about a car that is odd for no
	reason anybody can point at. ]]
function WeatherConfig.mutationPill(key: unknown)
	local mutation = WeatherConfig.mutationOf(key)
	return WeatherConfig.noticePill(mutation and mutation.Event)
end

--[[ THE EVENT GLYPH A MUTATED CAR WEARS. The mutation's own event's icon, or nil.

	Nil is a real answer and every caller must draw without it: a mutation with no event has no
	glyph, and so does a client one deploy behind a server that added a seventh event. The badge
	hides its well in that case rather than showing an empty one. ]]
function WeatherConfig.mutationIcon(key: unknown): number?
	local mutation = WeatherConfig.mutationOf(key)
	return if mutation then WeatherConfig.iconOf(mutation.Event) else nil
end

-- === Derived ================================================================

--- `Key` -> event, and `Key` -> mutation, built once at load. Everything below looks up through
--- these rather than scanning the arrays, and so should every caller.
-- Mutation bonuses apply only to owned car value (2026-10-12).
-- Retired identities stay readable for saved cars, but never enter spawn/admin selection pools.
WeatherConfig.LegacyMutations = {}
for index = #WeatherConfig.Mutations, 1, -1 do
 local mutation = WeatherConfig.Mutations[index]
 mutation.Multiplier = 1
 if mutation.Key == "Rusted" or mutation.Key == "Impatient" then
  mutation.AllowNatural, mutation.NaturalChance, mutation.EventChance = false, 0, 0
  mutation.ValueMultiplier = 1
  WeatherConfig.LegacyMutations[mutation.Key] = mutation
  table.remove(WeatherConfig.Mutations, index)
 end
end
for index = #WeatherConfig.Events, 1, -1 do
 local event = WeatherConfig.Events[index]
 if event.Key == "Sandstorm" then table.remove(WeatherConfig.Events, index)
 elseif event.Key == "RushHour" then event.Mutation = nil end
end

WeatherConfig.EventsByKey = {}
WeatherConfig.MutationsByKey = {}

--- `event key` -> the mutation that event drives. One each today; a map rather than a field on the
--- event so that a second mutation per event is an edit to `Mutations` and to nothing else.
WeatherConfig.MutationOfEvent = {}

do
	for _, event in WeatherConfig.Events do
		WeatherConfig.EventsByKey[event.Key] = event
	end
	for _, mutation in WeatherConfig.Mutations do
		WeatherConfig.MutationsByKey[mutation.Key] = mutation
		if mutation.Event then
			WeatherConfig.MutationOfEvent[mutation.Event] = mutation.Key
		end
	end
end

--- The event a key names, or nil. Never throws on a value off the wire.
function WeatherConfig.eventOf(key: unknown)
	return if type(key) == "string" then WeatherConfig.EventsByKey[key] else nil
end

--- The mutation a key names, or nil. Never throws on a value off the wire or out of a save file.
function WeatherConfig.mutationOf(key: unknown)
	return if type(key) == "string" then (WeatherConfig.MutationsByKey[key] or WeatherConfig.LegacyMutations[key]) else nil
end

--[[ Read a mutation key off the wire, or out of a save file, and answer with one this build can
	use — or nil for "no mutation", which is always a legal answer.

	The same shape and the same reasoning as `PaintConfig.sanitize`: this is the ONLY place a
	mutation coming from outside the server becomes a mutation the server will act on, so a key this
	build does not have (a soft deploy, a hand-edited profile, a renamed entry) becomes an ordinary
	car rather than an error or a guess. It does NOT decide whether the player could have got it —
	that is `WeatherService.couldHaveSpawned`, and the two checks are deliberately separate because
	they answer different questions. ]]
function WeatherConfig.sanitize(key: unknown): string?
	if not WeatherConfig.Enabled or type(key) ~= "string" then
		return nil
	end
	return if WeatherConfig.mutationOf(key) then key else nil
end

--[[ What a mutated bank pays, as a multiplier on the whole run. 1 for no mutation, for an unknown
	key, and for the feature switched off — so every caller can multiply unconditionally and none of
	them needs a branch. ]]
function WeatherConfig.multiplierOf(_key: unknown): number
 -- Run cash is independent of mutation, including legacy saved cars.
 return 1
end

--- What a mutated car is worth PARKED, as a multiplier on its income per second and therefore on
--- its sale price. Same contract as `multiplierOf` and deliberately a different, smaller number —
--- see the `Mutations` header.
function WeatherConfig.valueMultiplierOf(key: unknown): number
	local mutation = WeatherConfig.mutationOf(key)
	if not (WeatherConfig.Enabled and mutation) then
		return 1
	end
	local value = mutation.ValueMultiplier
	return if type(value) == "number" and value == value and value > 0 then value else 1
end

--- What to call a mutation on a label or in a log. Never fails; an unknown key reports itself.
function WeatherConfig.nameOf(key: unknown): string
	local mutation = WeatherConfig.mutationOf(key)
	return if mutation then mutation.Name else string.format("mutation %s", tostring(key))
end

--- The colour a mutation badges in, or nil for one this build does not have.
function WeatherConfig.colorOf(key: unknown): Color3?
	local mutation = WeatherConfig.mutationOf(key)
	return if mutation then mutation.Color else nil
end

--[[ THE MULTIPLIER AS THE BADGE PRINTS IT. "x2" for a whole number, "x1.5" for anything else.

	Its own function because three screens quote this number — the badge over the car, the results
	line and the inventory card — and a multiplier that rendered as "x2.0" in one place and "x2" in
	another would read as two different mutations. ]]
function WeatherConfig.formatMultiplier(value: number): string
	if type(value) ~= "number" or value ~= value then
		return "x1"
	end
	if value % 1 == 0 then
		return string.format("x%d", value)
	end
	-- Parenthesised: `gsub` returns the count as a second value, and a bare `return a:gsub(...)`
	-- hands both of them back — which turns `string.format("%s", trim(x))` into an arity error at
	-- the call site rather than here, where it would be obvious.
	local trimmed = (string.gsub(string.format("x%.2f", value), "0+$", ""))
	return (string.gsub(trimmed, "%.$", ""))
end

--[[ ROLL ONE CAR'S MUTATION. `rng` is the caller's own generator, so a race that seeds its Random
	gets a repeatable road out of this for free — the same contract `PaintConfig.roll` has, and the
	reason neither of them owns a seed.

	`activeEvent` is the event key running in THIS player's world right now, or nil for clear
	weather. Every mutation is offered a roll on every spawn:

	  • the one belonging to `activeEvent` rolls at its `EventChance`;
	  • every other mutation rolls at its `NaturalChance`, and only if `AllowNatural`.

	SO A CLEAR SKY STILL MUTATES CARS, rarely, which is the card's own reading and is what stops the
	feature being invisible to a player who never happens to be online during an event. And an event
	does not suppress the others: a `Soaked` car can turn up during a sandstorm, because weather is
	not the only reason a car is odd.

	TIES GO TO `Weight`, HIGHEST WINS, because more than one can pass on the same spawn and a car
	can only be one thing. Weighting by rarity rather than taking the first hit means the outcome
	does not depend on the order of the table above, which is the kind of dependency that survives
	right up until somebody sorts it alphabetically. ]]
function WeatherConfig.roll(rng: Random, activeEvent: string?): string?
	if not WeatherConfig.Enabled then
		return nil
	end

	local best, bestWeight = nil, -math.huge
	for _, mutation in WeatherConfig.Mutations do
		local isEvent = activeEvent ~= nil and mutation.Event == activeEvent
		local chance = if isEvent
			then mutation.EventChance
			else (if mutation.AllowNatural then mutation.NaturalChance else 0)

		if type(chance) == "number" and chance > 0 and rng:NextNumber() < chance then
			local weight = if type(mutation.Weight) == "number" then mutation.Weight else 0
			if weight > bestWeight then
				best, bestWeight = mutation.Key, weight
			end
		end
	end
	return best
end

-- === Reading the clock ======================================================
--[[ The whole schedule, as three pure functions. `WeatherService` owns the state and the history;
	these own the question "what SHOULD be running", and they are here rather than there so that the
	client can ask it too — the admin panel prints the next slot, and nothing has to be sent for it.

	NOTHING IS STORED AND NOTHING IS SEEDED. Two servers asked the same question at the same second
	give the same answer, which is the property the whole grid exists for (see `Schedule`). ]]

--- How many seconds into a period `world`'s event starts. See `Schedule.Offsets`.
function WeatherConfig.offsetFor(world: number): number
	local schedule = WeatherConfig.Schedule
	local offset = schedule.Offsets[world]
	if type(offset) ~= "number" then
		offset = (world - 1) * schedule.OffsetStride
	end
	return offset % schedule.Period
end

--[[ Which fifteen-minute period `world` is in at `now`. Just an index, and the only handle there is
	on ONE PARTICULAR event: `WeatherService` remembers the slot an admin stopped so that stopping an
	event does not also suppress the next one. ]]
function WeatherConfig.slotAt(world: number, now: number): number
	return math.floor((now - WeatherConfig.offsetFor(world)) / WeatherConfig.Schedule.Period)
end

--[[ WHICH EVENT A WORLD RUNS IN A GIVEN SLOT — its queue.

	Every world walks `Events` in order, one entry per period, and each starts at a different place
	in the list. So the queue is the same list everywhere and no two worlds are ever on the same page
	of it, which is the cheapest way to give four worlds four different skies without four shuffles
	to keep in sync. A world cycles the whole table in `#Events` periods — an hour and a half at six
	events and fifteen minutes.

	`Weight` is NOT consulted here; see the `Events` header for what it still does. ]]
function WeatherConfig.queuedEvent(world: number, slot: number): string?
	local count = #WeatherConfig.Events
	if count == 0 then
		return nil
	end
	return WeatherConfig.Events[(slot + world - 1) % count + 1].Key
end

--[[ WHAT `world` SHOULD BE RUNNING AT `now`, or nil for the clear stretch between events.

	The one call the schedule is actually made of. `startedAt`/`endsAt` are absolute server time, the
	same clock the wire carries (`Attribute`), so a caller never has to add anything to them.

	Nil with the feature switched off, which is what makes `Enabled` a complete switch rather than
	something the service has to remember to check. ]]
function WeatherConfig.scheduledAt(world: number, now: number): { event: string, startedAt: number, endsAt: number, slot: number }?
	local schedule = WeatherConfig.Schedule
	if not WeatherConfig.Enabled or type(schedule.Period) ~= "number" or schedule.Period <= 0 then
		return nil
	end

	local slot = WeatherConfig.slotAt(world, now)
	local into = now - WeatherConfig.offsetFor(world) - slot * schedule.Period
	if into >= schedule.Duration then
		return nil
	end

	local key = WeatherConfig.queuedEvent(world, slot)
	if not key then
		return nil
	end
	local startedAt = now - into
	return { event = key, startedAt = startedAt, endsAt = startedAt + schedule.Duration, slot = slot }
end

-- === What an event does to the road =========================================
--[[ The four traffic multipliers an event carries, filled in with 1 wherever it does not — so every
	caller multiplies unconditionally and none of them needs a branch, the same contract
	`multiplierOf` has. See the `Traffic` section of the `Events` header for what each one scales.

	The no-event answer is one shared constant — the overwhelmingly common case, asked on every spawn
	attempt of every clear race — and an event's answer is a fresh table each time. NOTHING MAY WRITE
	TO WHAT THIS RETURNS; a caller that did would be editing the clear-weather default for the rest
	of the session. Every caller reads and multiplies. ]]
local NO_TRAFFIC = { Cars = 1, Spawn = 1, Prime = 1, Speed = 1 }

function WeatherConfig.trafficFor(key: unknown): { Cars: number, Spawn: number, Prime: number, Speed: number }
	local event = WeatherConfig.eventOf(key)
	local traffic = event and event.Traffic
	if not (WeatherConfig.Enabled and traffic) then
		return NO_TRAFFIC
	end

	local out = {}
	for field, default in NO_TRAFFIC do
		local value = traffic[field]
		out[field] = if type(value) == "number" and value == value and value > 0 then value else default
	end
	return out
end

--[[ The library look an event draws, or nil for "draw its original `Particles`". Nil with
	`EventVfx` off, and nil for an event with no `Vfx` block, so the controller has exactly one
	question to ask and the flag is decided in exactly one place. ]]
function WeatherConfig.vfxOf(event: unknown)
	if not WeatherConfig.EventVfx or type(event) ~= "table" then
		return nil
	end
	local vfx = (event :: any).Vfx
	return if type(vfx) == "table" then vfx else nil
end

--[[ The puddles an event lays (`Puddles` in the Events header), by key or by entry, or nil for a dry
	one. Nil with the master switch off, so a disabled weather leaves no water on anybody's road. ]]
function WeatherConfig.puddlesOf(event: unknown)
	if not WeatherConfig.Enabled then
		return nil
	end
	local entry = if type(event) == "table" then event else WeatherConfig.eventOf(event)
	local spec = entry and (entry :: any).Puddles
	return if type(spec) == "table" then spec else nil
end

--- The card badge's asset id for an event, or nil for one with no art (`Events.Icon`). Never throws
--- on a value off the wire.
function WeatherConfig.iconOf(key: unknown): number?
	local event = WeatherConfig.eventOf(key)
	local icon = event and event.Icon
	return if type(icon) == "number" and icon > 0 then icon else nil
end

-- === Encoding the wire ======================================================
--[[ The whole schedule as one attribute string — see `Attribute` for the format and why it is an
	attribute at all.

	`state` is `{ [world] = { event = "Rain", endsAt = <server time> } }`. Worlds with nothing
	running are simply left out, so a completely clear server writes "" and a reader that finds
	nothing for its world is correct without a special case.

	SORTED BY WORLD, which costs a table and buys idempotence: the attribute is compared against its
	old value before being written (`WeatherService._publish`), and an unsorted encode of an
	unchanged state would differ from itself between calls and write every time. ]]
function WeatherConfig.encode(state: { [number]: { event: string, endsAt: number } }): string
	local worlds = {}
	for world in state do
		table.insert(worlds, world)
	end
	table.sort(worlds)

	local parts = {}
	for _, world in worlds do
		local entry = state[world]
		if entry and WeatherConfig.EventsByKey[entry.event] then
			table.insert(parts, string.format("%d=%s:%.1f", world, entry.event, entry.endsAt))
		end
	end
	return table.concat(parts, ",")
end

--[[ The other end. Anything unparseable is SKIPPED rather than fatal, and an event key this build
	does not have is skipped too — a client one deploy behind the server shows clear weather for an
	event it has never heard of, which is the right failure: no sky it cannot draw, and no crash. ]]
function WeatherConfig.decode(raw: unknown): { [number]: { event: string, endsAt: number } }
	local out = {}
	if type(raw) ~= "string" or raw == "" then
		return out
	end
	for chunk in string.gmatch(raw, "[^,]+") do
		local world, event, endsAt = string.match(chunk, "^%s*(%d+)=([^:]+):([%d%.]+)%s*$")
		local index, deadline = tonumber(world), tonumber(endsAt)
		if index and deadline and event and WeatherConfig.EventsByKey[event] then
			out[index] = { event = event, endsAt = deadline }
		end
	end
	return out
end

-- Approved economy balance, 2026-10-04.
WeatherConfig.Schedule.Period = 480
WeatherConfig.Schedule.Duration = 90
WeatherConfig.Schedule.Offsets = {0, 96, 192, 288, 384}
WeatherConfig.Schedule.OffsetStride = 96
local revised = {
	["Soaked"] = {
	["NaturalChance"] = 0.03,
	["EventChance"] = 0.25,
},
	["Rusted"] = {
	["NaturalChance"] = 0.015,
	["EventChance"] = 0.18,
},
	["Ghost"] = {
	["NaturalChance"] = 0.005,
	["EventChance"] = 0.14,
},
	["Charged"] = {
	["NaturalChance"] = 0.0,
	["EventChance"] = 0.1,
},
	["Molten"] = {
	["NaturalChance"] = 0.0,
	["EventChance"] = 0.08,
},
	["Impatient"] = {
	["NaturalChance"] = 0.02,
	["EventChance"] = 0.28,
},
}
for _, mutation in WeatherConfig.Mutations do
 mutation.NaturalChance = revised[mutation.Key].NaturalChance
 mutation.EventChance = revised[mutation.Key].EventChance
end

return WeatherConfig
