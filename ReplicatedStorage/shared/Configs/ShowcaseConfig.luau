--[[
	ShowcaseConfig
	--------------
	THE NEW BEST CUTSCENE (2026-09-28, the partner's ask: "little show off when u get a sick car").
	When a car you get is worth more than any car you have ever been given, the game cuts to a stage —
	your avatar dancing beside the car, the camera sweeping round the pair, NEW BEST! over the top and
	the car's name under it — then hands the camera back.

	WHAT "BEST" MEANS. `GarageConfig.valueOf(tier, mutation)`: the car's rung and its weather, which is
	what makes a car rare. NOT its market value, which also carries condition and fitted parts — a
	mint repeat of the car you banked scratched last run is not a new best, it is the same car in
	better shape. Paint is not in it either, because paint is not in the price anywhere.

	A RECORD, NOT THE COLLECTION. The number is saved (`ProfileKey`) and only ever goes up. Measured
	against what you currently own instead, selling your best car would make the next decent one a
	"new best", and the cutscene would be announcing a car worse than one you have had.

	WHEN IT PLAYS. A bank ends the run, and the run's end is a results screen (the car you got, the
	money) and a fade home. The stage cuts in with a flash the moment that screen starts lifting
	(`RaceConfig.LiftingEvent`), so the plot is not seen between the two. A car from anywhere else
	(`Sources`) plays at once. It stays up until the player clicks.

	=== OVER THE RESULTS, THEN BACK AFTER THEM — 2026-09-28 / 2026-09-29 ======================

	The first playtest (2026-09-28) put the results before the stage, and it was moved to play OVER
	the results screen, which held itself up until the stage was done. The next day the call went
	back: the results screen introducing the car and THEN the show-off reads better. It first waited
	for the landing again (`ReturnedEvent`), and that showed the plot for a beat between the two — so
	it now cuts in on the lift's FIRST frame, behind a flash (`Transition`). It also ended itself
	after 7 seconds and now waits for a click. Two things from the first playtest stayed:
	  • The tutorial's "Your First Car" card switched itself on over the stage (it waits for the same
	    landing). A screen switching itself on mid-cutscene is now held off until the stage ends
	    (`ShowcaseController._holdGui`), which is what makes waiting for the landing safe.
	  • The stage read "very neon" — a Glass floor mirroring the sky, and key/fill lights blooming a
	    white car out — so the floor is matte and both lights were cut by about three quarters.

	THREE THINGS TO KNOW BEFORE TOUCHING THIS.

	  1. THE SERVER DECIDES, THE CLIENT ONLY DRAWS. `ShowcaseService` compares and writes the record
	     off `GarageService`'s `CarAwarded`; the client is told the car and cannot ask for one. The
	     remote carries nothing but pictures, so a forged one would show a cutscene and nothing else.
	  2. THE STAGE IS BUILT ON THE CLIENT, HIGH ABOVE THE PLAYER (`Stage.Above`), never in the lot. Your
	     own plot has buyers, customers and other players' cars walking through it; a closed room up
	     there has nothing in it that this file did not put there, and nobody else can see it.
	  3. THE AVATAR IS A CLONE OF YOUR CHARACTER. The real one stays where it is, controls off, so
	     nothing about the lobby — the carry in your hands, the bay you were stood at — has moved when
	     the camera comes back.

	`Enabled = false` restores the old behaviour exactly: no record is compared or written and nothing
	is sent. The record simply stops moving and picks up where it was when switched back on.
]]

local ShowcaseConfig = {}

ShowcaseConfig.Enabled = true

-- === The record ================================================================

--- Top-level profile key (see the `BestCarValue` note in `Settings.luau`).
ShowcaseConfig.ProfileKey = "BestCarValue"

--[[ Which `awardCar` sources are SHOWN (`GarageService.awardCar`'s sixth argument). Every source
	still moves the record — a pull that beats your best is your best — but only these cut to the
	stage. The pull is off because it already has a reveal of its own (`RandomCarController`), and
	two celebrations of one car back to back is one too many. `nil` is every caller that names no
	source (the car deal, the admin grant), and it is shown: those are cars the player chose to get.

	The first car a new player banks is ALWAYS a new best (the record starts at zero with nothing
	owned to seed it from), and that is deliberate — it is the first thing worth showing off. ]]
ShowcaseConfig.Sources = {
	Bank = true,
	Pull = false,
	--[[ Off for the collector's steals (2026-11): early on nearly every steal is a new best, and a
		click-to-continue cutscene every few seconds is the opposite of the reference's pace. The
		"IT'S YOURS!" toast is that beat (`CollectorHudController`). ]]
	Capture = false,
	Other = true, -- any source not named above, and no source at all
}

--- Is a car from `source` shown? Pure.
function ShowcaseConfig.shows(source: string?): boolean
	local listed = if source then ShowcaseConfig.Sources[source] else nil
	if listed == nil then
		return ShowcaseConfig.Sources.Other == true
	end
	return listed == true
end

--[[ How long the client waits for the run's results to lift before playing anyway, seconds. The
	results screen holds itself for a few seconds after the bank (longer with RACE AGAIN on offer); a
	player who leaves it up longer than this sees the stage over it. 45 is longer than anybody reads a
	results screen and short enough that a missed `ReturnedEvent` (a path that ends a run without one)
	does not lose the cutscene. (`LiftingEvent` since 2026-09-29; same argument.) ]]
ShowcaseConfig.ReturnTimeout = 45

-- === The stage =================================================================

ShowcaseConfig.Stage = {
	--[[ WHICH ROOM (2026-10-02). `"Garage"` is the dark garage from the mockup, its neon in the car's
		rarity colour (`ShowcaseConfig.Garage`, built by `Modules/ShowcaseGarage`). `"Round"` is the
		violet round room below, exactly as it was, kept as the A/B. ]]
	Room = "Garage",

	--[[ Where the stage is built. Far above anything on any world's map (the tallest thing there is
		the lot's second storey, well under 100 studs), so nothing streams into the shot. ]]
	--[[ === NEAR THE PLAYER, NOT AT THE EDGE OF THE WORLD — 2026-09-30 =====================

		WHAT IT WAS: a fixed `Origin` 4000 studs up. Playtested: the stage sometimes showed nothing but
		sky for a few seconds, then drew, then VANISHED after 15-20 seconds while the cutscene was still
		up. Nothing in this code destroys it before the click, so the engine was treating a spot that
		far from the character (the streaming focus) as outside the loaded world.

		WHAT IT IS: studs straight up from wherever the character stands, well inside the area kept
		loaded around them. The room is closed — floor, wall, lid — so the lot below never shows in the
		shot, and it is client-only, so nobody else sees a room in the sky. The stage also waits to be
		drawn before the cover lifts (`Timing.ReadyTimeout`). 200 clears the lot's second storey
		(under 100) with the room's own 44 of wall to spare. ]]
	Above = 200,

	--[[ The round floor and its wall. 34 studs of floor fits the longest body on the roster beside an
		avatar with room to spare; the wall at 38 keeps the camera's widest orbit (`Camera.Distance`
		plus the lens) inside it, so the shot never sees past the edge into the sky. ]]
	FloorRadius = 34,
	WallRadius = 38,
	WallHeight = 44,
	WallSegments = 28, -- round enough that no seam shows at the lens width below

	FloorColor = Color3.fromRGB(38, 26, 70),
	WallColor = Color3.fromRGB(14, 8, 34),
	--[[ The glowing bands on the wall and the floor's rim — the screenshot's pink-violet rings.
		Neon, so they light themselves whatever the world's `Lighting` is doing. ]]
	GlowColor = Color3.fromRGB(226, 150, 255),
	BandHeights = { 10, 22, 34 },

	--[[ The lights on the pair. `Lighting` belongs to whichever world the player is in (a night
		world is nearly black), so the stage brings its own: a key light above, a warm fill behind. ]]
	KeyBrightness = 1,
	FillColor = Color3.fromRGB(255, 196, 80),
	FillBrightness = 0.8,

	--[[ The gold flames behind the car. `Rate` particles a second — enough to read as a blaze behind a
		roofline, not so many that they hide it. ]]
	Flames = {
		Color = Color3.fromRGB(255, 200, 40),
		Rate = 45,
		Size = 9,
		Lifetime = 1.4,
	},
}

-- === The garage ================================================================
--[[ THE GARAGE (2026-10-02, from the mockup posted that day: "build a cool room like this, maybe match
	the neons with the color of the rarity of the car"). A dark concrete garage on square pillars: a
	roller door on the left, crates in the back corners, three downlights washing the back wall, a lit
	frame in the ceiling and a ring of light on the floor round the pair. Every strip of neon is the
	car's rarity colour (`CarRarity`), so a Supercar's room is gold and a Beater's is grey. Used when
	`Stage.Room` is `"Garage"`; `Modules/ShowcaseGarage` has how it is built.

	THE COLOUR ARRIVES WITH THE CAR. With the reveal on, the room holds dark (`Dim`, a grey that says
	nothing) and its neon comes on at the hit, rippling out from the car at `PowerSpeed`, so the rarity
	is told by the same bang that shows the car. With the reveal off it is lit from the first frame.

	Sizes are studs and are FLOORS: a long car pushes the camera out (`Camera.FitPadding`), and the
	room grows round it rather than letting the lens through a wall. ]]
ShowcaseConfig.Garage = {
	--- Wall to wall across the shot, at least. Wide enough that the camera's opening sweep (which
	--- starts out to the car's side) stays inside the side walls.
	Width = 68,
	--- From the point the camera looks at to the back wall.
	Back = 26,
	--- Past the camera's resting distance to the front wall, which is behind the lens.
	FrontMargin = 6,
	--[[ Floor to ceiling. Low enough that the ceiling and its lit frame show along the top of the
		resting shot, as in the mockup; at 24 the ceiling sits just out of frame. ]]
	Height = 18,

	PillarSize = 3.5,
	PillarSpacing = 22,
	--- The back wall's seams, studs apart.
	PanelWidth = 8,
	--- The neon line across the back wall, studs off the floor. The downlights hang under it.
	StripHeight = 12,

	--[[ Near-black and neutral on purpose. The room is lit by the WORLD's `Lighting.Ambient` as well
		as its own lamps, and by day that ambient is a bright lavender; anything lighter than this, or
		with blue in it, came out a washed teal once the green spill landed on it. ]]
	Colors = {
		Wall = Color3.fromRGB(30, 31, 34),
		Seam = Color3.fromRGB(16, 16, 18),
		Pillar = Color3.fromRGB(34, 35, 38),
		Trim = Color3.fromRGB(18, 18, 20),
		Floor = Color3.fromRGB(16, 17, 19),
		Ceiling = Color3.fromRGB(16, 16, 18),
		Door = Color3.fromRGB(52, 54, 58),
		DoorAlt = Color3.fromRGB(40, 41, 45),
		Crate = Color3.fromRGB(26, 27, 30),
		CrateEdge = Color3.fromRGB(50, 52, 57),
		--- The downlights' lenses and their light: warm white, so the wash is not the rarity colour too.
		Lamp = Color3.fromRGB(255, 236, 214),
	},

	--[[ THE FLOOR SHINES BY SHOWING A SECOND ROOM. Roblox reflects only the sky, so the room is built
		again upside down under the floor and the floor is this see-through: 0 is a matte floor and no
		reflection drawn at all, 1 would be a clear window onto the copy. The car and the avatar get
		their own upside-down twins. ]]
	Gloss = 0.32,

	--[[ The ring of light on the floor round the pair. `Radius` is a floor, a long car gets
		`PerLength` x its length. `Whiten` mixes the core toward white (0 is pure rarity colour), which
		is what makes a strip read as a light rather than as paint. ]]
	Ring = {
		Radius = 17,
		PerLength = 0.85,
		Segments = 72,
		Width = 0.4,
		Whiten = 0.25,
	},
	--- The lit frame in the ceiling: how far in from the walls, and how far toward white.
	CeilingInset = 9,
	CeilingWhiten = 0.7,

	--- The three downlights on the back wall.
	Downlights = {
		Count = 3,
		Spacing = 15,
		Brightness = 7,
		Range = 14,
		Angle = 64,
		--- Degrees the beam is tipped into the wall, so it draws a scallop down it rather than a pool on the floor.
		Tilt = 30,
		--[[ The scallop of light each one paints down the wall: studs wide and tall, how opaque at its
			brightest, and how far down (in heights) its edges start, which is what spreads it into a cone. ]]
		Wash = { Width = 8, Height = 10, Strength = 0.75, Spread = 0.45 },
	},
	--[[ The coloured light the neon throws on the walls and the floor. Point lights along the strips,
		roughly `Spacing` studs apart; without them a strip glows and lights nothing. ]]
	Spill = {
		Brightness = 2.4,
		Range = 11,
		Spacing = 14,
	},

	--[[ How far the rarity colour is taken toward black before it is put on neon. The engine draws
		neon several times brighter than its colour, so a light colour clips: the Sedan green drew as
		(95, 255, 232), a cyan, until it was taken a third of the way down. ]]
	NeonDepth = 0.35,
	--[[ The soft light on the wall round each wall strip, so a strip reads as a glowing tube rather
		than a painted line: a gradient painted on the wall (`ShowcaseGarage` has why it is not a
		light). The world's bloom cannot be counted on for it, it is 0.08 by day. `Height` is studs of
		wall it covers, `Strength` how opaque it is at the strip (0 to 1), `Brightness` the SurfaceGui's,
		where above 1 is brighter than its own colour. ]]
	Glow = {
		Height = 3,
		Strength = 0.55,
		Brightness = 1.2,
		PixelsPerStud = 8,
		--- Upright strips a patch that fades at its sides is cut into (the downlight washes). Fewer bands.
		Slices = 31,
	},

	--[[ The neon's colour while the room is off (the reveal's hold): an unlit tube, no hue in it, and
		light enough to draw the room's lines in the dark. ]]
	Dim = Color3.fromRGB(66, 68, 76),
	--[[ How much of the NEUTRAL light (the downlights, their lenses and the washes they paint) stays on
		through the hold, 0 to 1. With everything off the first playtest's hold was a black screen
		with a car-shaped hole in it, and the dancing avatar (which the reveal's `Dim` note says must
		stay visible) was lost. Only the rarity colour has to wait for the hit. ]]
	Standby = 0.4,
	--- How fast the switch-on ripples out from the car, studs a second, and how long each strip takes.
	PowerSpeed = 70,
	PowerFade = 0.2,

	--- The round room's gold flames behind the car. Off here: in a garage they read as the car on fire.
	Flames = false,

	--[[ THE WORLD'S LIGHT, TAKEN OUT OF THE ROOM WHILE IT DRAWS. The stage sits inside whatever world
		the player is in, and two of that world's settings reach through any wall: the SKY'S light
		(`EnvironmentDiffuseScale`, and `EnvironmentSpecularScale`, which mirrors the sky in every
		smooth surface at a glancing angle) and the AIR (`Atmosphere.Density`, a blue haze over
		everything 30 studs off). Together they turned the dark garage a washed-out blue-grey. These
		are set for the stage's frames ONLY: written just before each frame draws and the world's own
		values put back straight after, so no other script ever reads them (`ShowcaseGarage.holdWorld`
		has why that matters). `nil` here leaves the world's light alone. ]]
	World = {
		Lighting = {
			EnvironmentDiffuseScale = 0,
			EnvironmentSpecularScale = 0,
		},
		Atmosphere = {
			Density = 0,
		},
	},
}

-- === The shot ==================================================================

ShowcaseConfig.Camera = {
	FieldOfView = 40,
	--[[ The resting framing: how far back and how high, in studs, measured from between the car and
		the avatar. `Distance` is a floor — a long car pushes it further out (`FitPadding` × the pair's
		width), so a limo is framed as whole as a hatchback. ]]
	Distance = 24,
	Height = 5,
	FitPadding = 1.5,
	--[[ The sweep in: starts `StartAngle` degrees round to the car's side, closer (`StartScale` × the
		resting distance) and lower (`StartHeight`), and swings to the front over `SweepTime`. ]]
	StartAngle = 75,
	StartScale = 0.65,
	StartHeight = 1.5,
	SweepTime = 2.4,
	--- After the sweep, a slow drift either side of the front, so the hold is not a still.
	DriftDegrees = 7,
	DriftPeriod = 6,
}

-- === Timing ====================================================================

ShowcaseConfig.Timing = {
	FadeIn = 0.35, -- from black into the stage
	FadeOut = 0.35, -- to black, then back to the lobby
	--- How long before a click can end it. Long enough that the click that closed the results screen
	--- does not also close this. There is no timer after that: it waits for the click.
	SkipAfter = 1.5,
	--- Off the results: how long the flash takes to burn off into the stage (`Transition`).
	FlashOut = 0.7,
	--[[ The cover (flash or black) HOLDS until the stage has loaded — its meshes, the car's, the
		avatar's — and then `ReadyFrames` frames have drawn with the camera already on it, capped at
		`ReadyTimeout` seconds. The frames are for the renderer, which can still owe a frame or two after
		the content has arrived; the cap means a slow load shows a longer flash, never a stuck one.

		=== 4 -> 2 — 2026-10-15 === "a bit too much of a black screen before the new best played". A
		slow or failing asset (an avatar accessory, a car not yet seen this session) held the cover for
		the whole 4 seconds, which reads as the game hanging. At 2, the worst case is a piece of the
		stage popping in just after the fade, which is the better failure of the two. ]]
	ReadyTimeout = 2,
	ReadyFrames = 8,
}

--[[ The cut from the results to the stage: the screen goes this colour on the lift's first frame and
	burns off over `Timing.FlashOut`. Warm white rather than pure, so it belongs to the gold on the
	stage; black here would read as a load, not a reveal. ]]
ShowcaseConfig.Transition = {
	Color = Color3.fromRGB(255, 244, 214),
}

-- === The reveal ================================================================
--[[ THE CAR IS REVEALED, NOT JUST THERE (2026-10-02, the owner: "make the new best car cutscene a
	lot cooler. add some sort of reveal effect, maybe add confetti"). WAS: the cover lifted on the car
	already standing in full light, NEW BEST! popping in over it. NOW a beat of suspense, then a payoff:

	    cover clears   the room is dim, the avatar dances, a column of light grows from an EMPTY spot
	                   on the floor with sparkles streaming up it                          (`Hold`)
	    the rise       the car comes up out of the floor spinning, overshoots a touch and
	                   settles into the stage's three-quarter pose                         (`Rise`)
	    the hit        white flash, the lights slam on, a wave of light across the floor, a burst of
	                   sparkles, the camera kicks, NEW BEST! pops, the tag, name and price slide up one
	                   after another, and confetti fires from both bottom corners, then keeps falling

	THE CLICK TO LEAVE IS ONLY ARMED AFTER THE HIT (`Timing.SkipAfter` counts from it while this is on),
	so a click that was meant for the results screen cannot skip the reveal it was waiting for.

	CONFETTI IS ON THE SCREEN, NOT IN THE ROOM. 3D confetti needs a flat-square particle texture, and
	the built-in ones are all soft blobs, sparkles and flames — confetti made of those reads as glitter
	smoke. Frames in the cutscene's ScreenGui are crisp at any resolution, take a colour each, and flip
	like paper (width x |cos|), which a particle cannot. The sparkles, which ARE right as particles,
	are in the room.

	`Enabled = false` is the cutscene exactly as before: car in place and lit from the first frame,
	title popping as the cover clears, no confetti, click armed `SkipAfter` after the cover. ]]
ShowcaseConfig.Reveal = {
	Enabled = true,
	-- 2026-10-04: Author both clips under SoundService.NewBest so they inherit the SFX slider.
	-- Buildup is optional: a quiet ~1.3-second airy riser, cut at the color/flash hit, leaves room
	-- for Reveal's impact. No substitute clip is played if the riser has not been authored.
	Sounds = {
		Enabled = true,
		Group = "NewBest",
		Reveal = "Reveal",
		Buildup = "Buildup",

		--[[ THE HIT GETS BIGGER WITH THE CAR'S RARITY (punch list A3, 2026-10-13, Aleafo: "We need a
			different sound for the new best (based on rarity of the vehicle)"). Keyed by `CarRarity` band,
			1 Common to 5 Legendary. Each entry is a list of Sound names under `Group`, started together,
			so a band can layer the one below it with something heavier on top.

			FALLS BACK TO `Reveal`: a band with no entry, or whose Sounds are all missing from the place,
			plays the single clip every car used to get. A clip carrying a `StartAt` attribute (seconds)
			starts that far in, which trims a library clip's silent lead-in. ]]
		RevealByBand = {
			[1] = { "RevealCommon" },
			[2] = { "RevealUncommon" },
			[3] = { "Reveal" },
			[4] = { "Reveal", "RevealEpic" },
			[5] = { "Reveal", "RevealEpic", "RevealLegendary" },
		},
	},

	--[[ === THE SILHOUETTE — 2026-10-02 =====================================================
		Second playtest of the reveal: "the sparkles are there and the car isnt, takes a second to come
		in". An EMPTY stage is dead time however short it is made — there is nothing to look at but the
		promise of something. WAS `"Rise"`: the car under the floor for the hold, then up out of it. NOW
		`"Silhouette"`: THE CAR IS ON SCREEN FROM THE FIRST FRAME, BLACKED OUT — every surface black, its
		lights and textures off — spinning against a blazing sunburst (`Rays`), slowing as the camera
		rumbles harder, and on the hit its colour floods back in under the flash. The suspense is now
		"what IS it" with the shape in front of you, which is the whole trick of a silhouette reveal, and
		it never shows an empty floor.

		`"Rise"` is kept, untouched, as the A/B. The hold counts from the moment the cover starts to
		clear in this style (the car is already worth looking at through the flash), and `Rise` is not
		used by it. ]]
	Style = "Silhouette",

	--[[ Seconds of dim room and rising sparkles, then seconds the car takes to come up out of the floor
		(`Back` easing, so it overshoots and settles).
		=== QUICKER — 2026-10-02 ==============================================================
		WAS Hold 1.4, Rise 0.7; the owner, after seeing it: "make the car appear quicker". Now about half
		of each, which still reads as a beat of suspense before the hit rather than a pop. ]]
	Hold = 0.7,
	Rise = 0.4,
	--[[ `"Silhouette"` only: seconds from the cover starting to clear to the hit. The car spins down to
		its pose over exactly this (`Spins` turns, fastest first), so the hit lands as it stops. 1.3 is
		the flash burning off (0.7) and about half a second of black shape and rumble after it. ]]
	SilhouetteHold = 1.3,
	--- `"Silhouette"` only: how hard the camera rumbles by the end of the hold, studs. Ramps from 0.
	Rumble = 0.12,
	--- Whole turns on the way up (or, in `"Silhouette"`, over the hold). It always ends on the stage's
	--- pose, so this is flourish only.
	Spins = 1,
	--- Key and fill brightness during the hold, as a fraction of `Stage.KeyBrightness`/`FillBrightness`.
	--- Not 0: the avatar has to stay visible, dancing in the dark, or the hold reads as a load.
	Dim = 0.15,

	--- The column of light the car comes up through: neon, see-through, `Radius` studs wide.
	Beam = {
		--[[ Whether the column itself is drawn. OFF since 2026-10-02 (the owner: "remove that big
			cylinder thing, leave the sparkles"); the sparkles streaming up from the spot still mark
			where the car will come from. `true` brings the column back exactly as it was. ]]
		Show = false,
		Color = Color3.fromRGB(255, 226, 150),
		Radius = 4,
		Transparency = 0.6,
		ChargeRate = 40, -- sparkles a second streaming up it during the hold
	},
	--[[ THE SUNBURST (2026-10-02) — `Count` long neon spokes on a wheel standing behind the car, facing
		the camera's resting side, turning slowly. In the hold it is a dim glow the black car is cut out
		against (`HoldTransparency`); at the hit it blazes up (`Transparency`) and whips round
		(`HitSpin` degrees a second, falling away with the camera kick) before settling to `Spin`. Two
		colours alternating spoke by spoke, the stage's violet and the title's gold. `Behind` is studs
		back from the car and `Up` studs above the floor for the wheel's hub. `Enabled = false` is no
		sunburst in either style.

		OFF since 2026-10-02, the same day it was added: the owner liked the silhouette reveal but found
		the spokes "overdoing it a little". The black car now spins against the dim room and the stage's
		own glowing bands. `true` brings the sunburst back exactly as it was. ]]
	Rays = {
		Enabled = false,
		Count = 16,
		Width = 2.2,
		Length = 48,
		Behind = 16,
		Up = 5,
		Colors = { Color3.fromRGB(226, 150, 255), Color3.fromRGB(255, 210, 90) },
		HoldTransparency = 0.7,
		Transparency = 0.35,
		Spin = 12,
		HitSpin = 240,
	},
	--- The burst of sparkles round the car at the hit.
	Sparkles = 90,
	SparkleColor = Color3.fromRGB(255, 220, 120),
	--- The screen flash at the hit. Pure white and short — the warm `Transition` colour is the cut IN;
	--- this has to read as a second, separate bang.
	Flash = { Color = Color3.new(1, 1, 1), Time = 0.45 },
	--- The disc of light that races out across the floor from the car. The stage's own glow colour.
	Wave = { Color = Color3.fromRGB(226, 150, 255), Radius = 32, Time = 0.8 },

	--[[ The camera's kick at the hit: the lens widens by `FovKick` degrees and the eye shakes by up to
		`Shake` studs, both falling away as exp(-KickDecay * t) — at 5, gone to 8% in half a second. A
		widen rather than a zoom: the shot is already pushing in with the sweep, and two zooms fight. ]]
	FovKick = 10,
	Shake = 0.35,
	KickDecay = 5,

	--- NEW BEST! keeps breathing after its pop, to this scale and back, so the hold has a pulse.
	TitleBreathe = 1.06,
	--[[ The tag, name and price start `TextRise` (screen heights) low and invisible, and slide up into
		place `TextStagger` seconds apart, the first `TextLead` after the hit — after the title has
		landed, so the eye goes title -> name -> price, in that order. ]]
	TextRise = 0.04,
	TextStagger = 0.12,
	TextLead = 0.2,

	--[[ The screen confetti. `Burst` pieces from EACH bottom corner at the hit, then `RainPerSecond`
		falling from the top until the click. Units are screen fractions: `Gravity` in screen heights
		per second squared, `Drag` per second, so a falling piece settles near Gravity / Drag = 0.26
		screens a second — paper, not gravel. A cannon piece launched at up to 3 screens a second
		climbs about 3 / Drag = 0.86 of the screen before it turns. `SizeMin`/`SizeMax` are pixels at a
		900-pixel-tall screen, scaled to the real one. `MaxPieces` caps the frames alive at once. ]]
	Confetti = {
		Enabled = true,
		Burst = 70,
		RainPerSecond = 16,
		MaxPieces = 280,
		SizeMin = 9,
		SizeMax = 16,
		Gravity = 0.9,
		Drag = 3.5,
		Colors = {
			Color3.fromRGB(255, 214, 60),
			Color3.fromRGB(255, 92, 170),
			Color3.fromRGB(80, 210, 255),
			Color3.fromRGB(170, 110, 255),
			Color3.fromRGB(110, 235, 130),
			Color3.fromRGB(255, 255, 255),
		},
	},
}

-- === The dance =================================================================

--[[ The avatar's own dance, when it has one: the `dance`, `dance2` and `dance3` animations of its
	`Animate` script, which is whatever emote pack the player wears. One of those is picked at random.
	The ids below are Roblox's stock dances, used only when the avatar's `Animate` has none. ]]
ShowcaseConfig.Dance = {
	AnimateFolders = { "dance", "dance2", "dance3" },
	FallbackR15 = { "rbxassetid://507771019", "rbxassetid://507776043", "rbxassetid://507777268" },
	FallbackR6 = { "rbxassetid://182435998", "rbxassetid://182436842", "rbxassetid://182436935" },
}

-- === Words =====================================================================

ShowcaseConfig.Text = {
	Title = "NEW BEST!",
	WorthFormat = "WORTH %s",
	Continue = "Click to continue",
	--- Per device (2026-10-15): a console was told to click. The pad line sits beside an A glyph,
	--- drawn from the controller actually connected, so it never names a button in words.
	ContinueTouch = "Tap to continue",
	ContinuePad = "to continue",
}

ShowcaseConfig.Fonts = {
	Title = Font.new("rbxasset://fonts/families/LuckiestGuy.json"),
	Name = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy),
}

ShowcaseConfig.Colors = {
	TitleTop = Color3.fromRGB(255, 236, 110),
	TitleBottom = Color3.fromRGB(255, 170, 20),
	--- The WORTH line. The tag above the name (mutations only) wears the mutation's own
	--- `WeatherConfig` colour and falls back to this one for a mutation that has none.
	Tag = Color3.fromRGB(255, 196, 40),
	Name = Color3.fromRGB(255, 255, 255),
	Stroke = Color3.fromRGB(20, 12, 30),
}

return ShowcaseConfig
