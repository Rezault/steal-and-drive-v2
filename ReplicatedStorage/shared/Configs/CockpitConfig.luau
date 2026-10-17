--[[
	CockpitConfig
	-------------
	THE FIRST-PERSON COCKPIT: the dash, the wheel and the driver's arms that `Modules/FirstPersonCockpit`
	draws over the world while `CameraConfig.FirstPerson` has the shot, and how the car's OWN wheel
	turns when that overlay is off (`CarWheel`, which is the default while the real cabins are on
	test). This file is the ART. The
	camera side (where the eye sits, how the view follows the car, the lens) is `CameraConfig.FirstPerson`,
	and the two are kept apart so the camera never has to know what colour a dashboard is.

	=== WHY IT IS DRAWN IN A VIEWPORT AND NOT WELDED TO THE CAR ================================

	The roster has 65 bodies from three vendors and three different ideas of an interior: pack A has a
	fused inner shell with a roof, pack B has seats and a wheel cloned in after the fact, pack C varies.
	From the driver's seat they range from a decent cabin (Civic) to a slot of windscreen under a roof
	(Sian). A cockpit built in the world would clip into every one of them differently.

	A ViewportFrame draws ON TOP of the world, so the dash and wheel are the same dash and wheel in
	every car, the real cabin (pillars, roof, mirror, the door beside you) shows through above the dash
	line, and nothing can poke through anything. It is the trick every first-person Roblox game uses
	for a viewmodel and the reason is the same. The cost is flat lighting (a viewport has an ambient
	and one directional light, no shadows), which on a dark dashboard is fine.

	=== ONE COCKPIT PER RARITY, NOT PER CAR ====================================================

	The band is `Modules/CarRarity` (Common, Uncommon, Rare, Epic, Legendary) and the accent colour is
	that module's colour for the band, so the cockpit says what every other rarity read in the game
	says. A theme below changes materials, trim, whether the wheel has a flat bottom and how much neon
	there is. Steal a Legendary mid-run and the cockpit turns gold with it, which is a reward you see
	for the rest of the race.

	=== GEOMETRY IS EYE-RELATIVE ================================================================

	Every position below is measured from the EYE, in studs: +X is the driver's right, +Y up, -Z ahead.
	Not from the seat, because the eye height is a slider (`CameraConfig.FirstPerson.EyeHeight`) and
	the dash has to stay a fixed distance under the eye whatever the slider says. A real cowl sits about
	a stud under the driver's eye line and that is the number everything else here hangs off.

	The driver sits 1.7 studs LEFT of the car's centreline on every rig (the seat survey of 2026-10-13
	read bodyRel.X = 1.7 for all 65), so `CabinCentreX` is where the centre console goes.
]]

local CockpitConfig = {}

-- === Layout (studs from the eye) ============================================

--- The cabin's centreline, right of the driver. The seat survey puts it at 1.7 on every rig.
CockpitConfig.CabinCentreX = 1.7

--- The whole dash, door to door. The cabins inside the shells run 7 to 8 studs wide.
CockpitConfig.DashWidth = 8.2

CockpitConfig.Dash = {
	--- The cowl: how far under the eye its top sits, where its near edge is and how deep it runs
	--- toward the windscreen. Tilted a little nose-down like a real dash top.
	TopDrop = 0.95,
	--- The near edge sits BEYOND the wheel (the hub is 1.62 ahead of the eye), the way a real cowl
	--- does, so the rim never passes through the dash top.
	NearZ = -2.0,
	Depth = 1.7,
	Thickness = 0.28,
	TiltDeg = 7,
	--- The vertical face under the cowl, toward the knees. Its bottom is well below the frame.
	FaceHeight = 1.9,
	--- The instrument hood over the cluster, in front of the driver. Its top is still under the eye.
	Hood = { Width = 1.9, Height = 0.42, Depth = 0.9 },
	--- The accent line along the top edge of the cowl (Rare and up light it). Thin on purpose: lit,
	--- it should read as a line of ambient light along the dash, not a bar of it.
	StripThickness = 0.04,
}

CockpitConfig.Cluster = {
	--- The dial on the pod behind the wheel: a dark disc, tick marks round it, one needle that sweeps
	--- with speed. You read it through the upper half of the rim, as in a real car. The radius is
	--- capped by the pod's height.
	Radius = 0.46,
	Ticks = 9,
	--- Needle sweep, degrees, as seen by the driver: `From` at rest, `To` at the car's ceiling.
	--- Measured counter-clockwise from the dial's 3 o'clock.
	NeedleFromDeg = 225,
	NeedleToDeg = -45,
	NeedleGain = 8, -- per second, how quickly the needle follows the speed
	--- The HP bar, drawn on the centre screen. Full is the accent colour, empty is red, and it
	--- shortens from the right. `Drop` is where it sits on the screen, 0 = bottom edge, 1 = top.
	Bar = { Width = 1.0, Height = 0.1, Drop = 0.55 },
	Low = Color3.fromRGB(235, 70, 60),
}

CockpitConfig.Wheel = {
	--- Where the hub is from the eye. The rim's top sits a little under the eye line, so the road
	--- ahead is never behind the wheel.
	Offset = Vector3.new(0, -0.92, -1.62),
	Radius = 0.62,
	RimThickness = 0.2,
	--- Degrees the wheel leans away from the driver (top further from you), like a real column.
	TiltDeg = 24,
	--- Rim pieces. 24 is where the joints stop reading as corners this close to the lens.
	Segments = 24,
	--- Degrees of lock at full steer, either way. Real cars turn 2.5 turns; arcade wheels do about
	--- this, which keeps the hands on the rim and keeps the upper hand short of 12 o'clock, where a
	--- forearm would cross the whole frame.
	MaxDeg = 70,
	--- Per second. How quickly the wheel follows the input. Soft enough to read as hands, fast enough
	--- that a flick is a flick.
	Gain = 14,
	--- Flat-bottom wheels drop the rim inside this many degrees either side of 6 o'clock and put a
	--- straight bar across instead.
	FlatBottomDeg = 28,
	--- The pad. `Ring` is how far the trim ring round it shows past its edge, `Badge` the badge's radius.
	Hub = { Radius = 0.3, Thickness = 0.22, Ring = 0.035, Badge = 0.06 },
	--- Spokes are the wheel's colour with a trim inlay down the face: `InlayWidth` wide, stopping
	--- `InlayInset` short of each end.
	Spoke = { Width = 0.2, Thickness = 0.1, InlayWidth = 0.05, InlayInset = 0.06 },
}

CockpitConfig.Console = {
	--- The centre stack, on the cabin centreline. A screen (lit on Rare and up) and a couple of vents.
	Screen = { Size = Vector3.new(1.35, 0.8, 0.06), Offset = Vector3.new(0, -1.42, -1.84), TiltDeg = 10 },
	Vents = 2,
	VentSize = Vector3.new(0.5, 0.22, 0.08),
}

-- === The arms ================================================================

CockpitConfig.Arms = {
	Enabled = true,
	--- Where the shoulders are from the eye. An R15 shoulder sits about a stud under the eye and a
	--- stud out from the centreline; the view never sees them, so they only have to be plausible.
	--- Further back and lower reads better (the upper arms stay out of frame) but an R15 arm is
	--- only 1.77 studs long, which is why `Scale` and the stretch below exist.
	Shoulder = Vector3.new(0.95, -1.45, 0.35),
	--- The limbs are drawn at this share of the character's own size: (width, length, depth). A
	--- full-size R15 arm half a stud from the lens is a wall, and it is the WIDTH that does it; the
	--- length is made up by the stretch below. Viewmodel arms are always slimmer than the body. 0.45
	--- read as planks once the hands were on the real wheel, which is nearer the lens than the drawn one.
	Scale = Vector3.new(0.36, 0.9, 0.36),
	--- If the hands cannot reach the rim at rest, the arms are lengthened (along the bone, once, at
	--- build) by up to this factor so they do. `ReachMargin` is the slack over the exact distance,
	--- so the elbows keep a bend and a turn of the wheel does not pull the hands off the rim.
	MaxStretch = 1.8,
	ReachMargin = 1.08,
	--- Where the hands hold the rim, degrees counter-clockwise from the dial's 3 o'clock as the driver
	--- sees the wheel, before the wheel turns. A touch under 9-and-3, so that at full lock the upper
	--- hand stops short of 12 o'clock instead of dragging a forearm across the whole frame.
	LeftGripDeg = 185,
	RightGripDeg = 355,
	--- Degrees the hands go round with the wheel before it slides under them. Full lock (70) took the
	--- upper hand to 1 o'clock and its forearm diagonally across the wheel and the dash.
	GripFollowDeg = 40,
	--- The elbow bends toward this direction (down and out). Only the direction matters.
	LeftPole = Vector3.new(-0.7, -1, 0.1),
	RightPole = Vector3.new(0.7, -1, 0.1),
	--- Driving gloves on both hands. A bare hand on a bare forearm is one skin-coloured block and the
	--- grip does not read; a dark glove is the hand. `Enabled` false (or nil) leaves the
	--- character's own skin. `Cuff` is the band round the wrist end: studs long, studs proud of the
	--- glove each side.
	Gloves = {
		--- Off since 2026-10-13: Dylan wanted the player's own bare hands.
		Enabled = false,
		Color = Color3.fromRGB(36, 36, 40),
		Material = Enum.Material.Leather,
		Cuff = { Color = Color3.fromRGB(66, 66, 72), Length = 0.1, Proud = 0.025 },
	},
	--- Fallback arm when the character has none we can use: plain parts in the body colour.
	Fallback = {
		UpperSize = Vector3.new(0.9, 1.25, 0.9),
		LowerSize = Vector3.new(0.85, 1.25, 0.85),
		HandSize = Vector3.new(0.85, 0.35, 0.85),
		Color = Color3.fromRGB(204, 142, 105),
	},
}

-- === The car's own wheel (overlay off) ======================================

--[[ With the overlay off (`CameraConfig.FirstPerson.Cockpit = false`) the lens looks at the car's
	real cabin, and the car's own `steering_wheel` turns with the steer. 61 of the 65 rigs have one as
	its own part; Lambo, Maybach, Car1 and TestCar do not, and simply have no wheel that turns.
	`Modules/FirstPersonWheel` does the turning and says why it is a clone.

	THE PIVOT IS MEASURED, NOT GUESSED. The wheel's box is no help: the rim is raked inside the mesh and
	a column stub stretches the box forward, so the box centre is not the hub and no box axis is the
	column. The meshes were downloaded through Open Cloud on 2026-10-13 and fitted (a plane through the
	rim's vertices is the axis, a circle through them is the hub). 45 of the 49 wheel meshes in the
	roster are one vendor wheel at different scales, which is `Axis` and `Centre` below; the rest are
	in `ByMesh`. Both are in the PART's own space: `Axis` a direction, `Centre` a share of `Size` from
	the part's centre. A mesh nobody measured gets the vendor wheel, which is right for any car from
	the same packs. ]]
CockpitConfig.CarWheel = {
	--- Degrees of lock at full steer, either way. The drawn wheel's number (`Wheel.MaxDeg`), because
	--- the hands hold this one too and past it the upper hand drags a forearm across the frame.
	MaxDeg = 70,
	--- Per second. How quickly the wheel follows the input.
	Gain = 14,
	--- The vendor wheel: the column leans 22.6 degrees off the part's X toward its Y, the rim sits a
	--- tenth of the box toward the driver because the stub fills the front of it, and the rim's
	--- centreline (where a hand holds it) is 0.467 of the box's largest side from the hub.
	Axis = Vector3.new(0.923, 0.385, 0),
	Centre = Vector3.new(0.095, 0, 0),
	Radius = 0.467,
	--- Keyed by the number in `MeshId`. The car is a comment, because a mesh can be on several.
	ByMesh = {
		["133376019024374"] = { Axis = Vector3.new(0.975, 0.222, 0), Centre = Vector3.new(-0.034, 0.003, 0), Radius = 0.445 }, -- GNX
		["82253470233939"] = { Axis = Vector3.new(0.959, 0.285, 0), Centre = Vector3.new(0.142, 0, 0) }, -- M600
		["108671486209433"] = { Axis = Vector3.new(-0.085, 0.996, 0), Centre = Vector3.new(0.062, -0.068, 0), Radius = 0.544 }, -- Roadster 2.0, modelled lying flat
		["112330365970858"] = { Centre = Vector3.new(0.067, 0.011, 0) }, -- RX7 F&F
		["138940291848283"] = { Centre = Vector3.new(0.123, 0.009, 0) }, -- SUPRA MK4
		["76545453182683"] = { Centre = Vector3.new(0.121, 0.011, 0) }, -- Supra MK4
		["87966982661816"] = { Centre = Vector3.new(0.123, 0.008, 0) }, -- S15
		["116408344858542"] = { Centre = Vector3.new(0.123, 0.009, 0) }, -- NewSports04
	} :: { [string]: { Axis: Vector3?, Centre: Vector3?, Radius: number? } },
}

-- === The black cabin =========================================================

--[[ `CameraConfig.FirstPerson.Cabin`: the car's cabin redrawn black, its own mirrors cut out (ours
	go back in, `Cabin.Detail` below), from a skin baked per car (`Configs/CabinSkinConfig` says what a skin is). Seen from the seat the car's shell
	is its PAINT from behind (a red Civic is red pillars, red roof, red door tops) and the mirrors are
	loose blobs; seen from outside every interior in the roster is dark. This makes the inside match
	the outside. `Modules/FirstPersonCabin` does it.

	The skin sits a hair nearer the eye than the shell (`Scale`, about the eye, so from the eye it
	covers exactly what the shell covers) and the car's own parts are hidden only once the lens has
	arrived in the seat (`HideAtBlend`): until then, and on the way out, the car looks like itself
	from the outside and the skin is just a dark interior seen through the glass. ]]
CockpitConfig.Cabin = {
	Color = Color3.fromRGB(24, 24, 27),
	Material = Enum.Material.SmoothPlastic,
	--- Share of the way from the eye to the shell the skin sits at. Under 1 so it never fights the
	--- shell for the same pixels while both are drawn.
	Scale = 0.97,
	--- The first-person blend (0 chase, 1 in the seat) past which the car's own parts are hidden.
	HideAtBlend = 0.97,
	--- Studs the live eye may sit from the eye a skin was baked for before the skin stands down
	--- (every triangle faces the BAKED eye, so far from it some would face away). A slider moved a
	--- long way does this; the car's own cabin shows instead.
	EyeTolerance = 0.6,
	--- A car with no baked skin gets its own opaque parts cloned in the cabin colour, at this
	--- `Scale`, with the originals left showing: the red insides go, the mirrors stay (dark). False
	--- leaves such a car exactly as it was.
	CloneUnbaked = true,
	CloneScale = 0.94,
	--[[ === A CAR WITH NO SKIN GETS THE DRAWN DASH — 2026-10-14 ===
		WAS: `CloneUnbaked`'s dark copy of the car's own parts, which on the Maybach (left out of the
		bake on purpose, `CabinSkinConfig`) and the three off-ladder bodies with no skin read as black
		blocks with the car's own mirrors, no gauges and often no hands (the owner: "some of the cars'
		first person view looks like this"). A skin that fails to load landed there too.
		IS: such a car is driven behind the rarity dash, wheel and arms (`Modules/FirstPersonCockpit`,
		the `CameraConfig.FirstPerson.Cockpit` look) while every baked car keeps its own cabin, and
		the dark copy is not built. `RaceCameraController._step` decides it per car off
		`FirstPersonCabin.hasSkin`. False: the dark copy again, exactly as before. ]]
	DashWhenUnbaked = true,
	--[[ === THE CABINS ARE FETCHED AHEAD — 2026-10-14 ===
		WAS: every skin, mirror and detail mesh was downloaded the first time it was needed, so the
		first first-person shot of the session, and the first in every newly stolen car, showed the
		car's own insides for a beat until its cabin arrived (the owner: "it takes a while, like the
		car is loading in"). IS: `PreloadAfter` seconds into the session every cabin mesh is fetched
		in the background, one at a time, so by the first race they are in memory and a jump into any
		car is instant. The car you enter is still asked for at once, ahead of the queue
		(`Modules/FirstPersonCabin.warm`). One at a time is the point: ~150 loads at once would queue
		behind the map's own streaming at the worst moment. The cost is the skins sitting in client
		memory all session, first person or not. False: load on first use, exactly as before. ]]
	Preload = true,
	PreloadAfter = 5,

	--[[ === HAND NUDGES FOR A BAD BAKE — 2026-10-14 ===
		`CabinSkinConfig` is generated and its pipeline (`assets/cabins/`) is not in this repo, so a
		car whose pieces it placed badly is corrected HERE, by body name, as offsets in the SEAT's
		frame in studs: +X the driver's right, +Y up, +Z TOWARD THE DRIVER. Groups: `Wheel` (the car's
		own steering wheel, while it is turned by `Modules/FirstPersonWheel`; the hands follow it),
		and the detail pieces `Cluster`, `Screen`, `Row`, `Vent`, `Mirror` (rear-view), `CarMirror`.

		READ EVERY FRAME, so it can be tuned live: in a Studio playtest, switch the command bar to the
		CLIENT and write e.g.
		    require(game.ReplicatedStorage.shared.Configs.CockpitConfig).Cabin.Nudge.GNX.Screen = Vector3.new(0, 0.2, 0)
		then copy the value that looks right back into this table. A rebake that fixes a car should
		delete its row here.

		GNX (the "Garnex", the owner: "the steering wheel and radio look like they're inside the
		dash"). Measured with Studio raycasts against its collision hull, so approximate: the wheel's
		centre is 1.68 ahead of the seat and its back face ~1.97, while the dash's back wall behind it
		is at ~1.75, so half the wheel is inside the dash (and the skin, drawn 3% nearer the eye,
		swallows the rest). Wheel +0.4 toward the driver clears it. The radio's face is centred 0.14
		over the dash top (2.84 over 2.70) with half its 0.44 height below that, so its foot is in the
		dash; +0.15 up stands it on top. Starting values, to be confirmed by eye. ]]
	Nudge = {
		--- Cluster +0.12 up, same day: with the wheel pulled clear, the skin's own steering-column boss
		--- (baked where the hub used to be) sat across the foot of the gauges ("the front part of the
		--- wheel looks off"). Up, the gauges read through the top half of the rim as on every other car.
		GNX = {
			Wheel = Vector3.new(0, 0, 0.4),
			Screen = Vector3.new(0, 0.15, 0),
			Cluster = Vector3.new(0, 0.12, 0),
		},
	} :: { [string]: { [string]: Vector3 } },
}

--[[ `CameraConfig.FirstPerson.CabinDetail`: what goes on the black cabin so it reads as a car and
	not a cave. The mirrors the skin cut out come back: the car's own door mirrors in its own paint
	(`CabinSkinConfig.Mirrors`, Dylan preferred them to a pair of ours), and a rear-view mirror of
	ours on a stalk to the roof or the glass. The dash gets what the vendors never modelled: gauges
	behind the wheel that follow the car, a radio screen on the dash top that shows the soundtrack,
	vents and a hazard switch. Where each piece goes in each car is `CabinSkinConfig.Detail`; this
	is how it looks.

	DARK ON DARK, with light only where a real dash has it: the dials and the screen are drawn unlit
	(they glow at night the way a real cluster does) and everything else is housings in the cabin's
	own black, with a little dark metal on the rings to catch a highlight. ]]
CockpitConfig.Cabin.Detail = {
	--- The binnacle, the screen's bezel and the rear-view mirror's shell. A shade off the cabin so the
	--- edges read against the dash behind them.
	Housing = { Color = Color3.fromRGB(32, 32, 36), Material = Enum.Material.SmoothPlastic },
	--- The rings round the dials and the vents.
	Trim = { Color = Color3.fromRGB(92, 94, 100), Material = Enum.Material.Metal },
	--- Inside a vent: the vanes and the barrel.
	VentCore = { Color = Color3.fromRGB(14, 14, 16), Material = Enum.Material.SmoothPlastic },
	--- Mirror glass. Roblox reflects the sky and never the scene, so a mirror is a sky-coloured
	--- sheen that darkens at night, which from the seat reads as glass.
	Glass = { Color = Color3.fromRGB(58, 62, 68), Material = Enum.Material.SmoothPlastic, Reflectance = 0.28 },
	--- The rear-view mirror's stalk and the foot it stands on.
	Stalk = { Color = Color3.fromRGB(26, 26, 30), Material = Enum.Material.SmoothPlastic },
	Hazard = { Color = Color3.fromRGB(36, 36, 40), Mark = Color3.fromRGB(196, 46, 40) },

	--- The lit faces: the gauges and the screen.
	Face = Color3.fromRGB(7, 8, 10),
	Ink = Color3.fromRGB(226, 230, 238), -- ticks, digits, the track name
	Dim = Color3.fromRGB(116, 122, 134), -- minor ticks, small labels
	--- The screen's one colour: the game's blue, softened so it glows and does not shout.
	Accent = Color3.fromRGB(96, 150, 255),
	Needle = Color3.fromRGB(255, 92, 50),
	Redline = Color3.fromRGB(205, 52, 44),
	Font = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),

	Gauges = {
		--- Degrees the needles sweep, clockwise, centred on 12 o'clock.
		SweepDeg = 240,
		--- Major ticks round a dial (the marks between them are minor). The tacho's last
		--- `RedTicks` majors are the redline.
		Ticks = 8,
		RedTicks = 1.5,
		--- The mph at the end of the speedo's sweep. Its majors are `SpeedTop / Ticks` apart and
		--- numbered, and its needle reads the HUD's own mph against them, so the needle and the
		--- digits under it always agree. A road car's 160: cruise sits about a third of the way
		--- round and nothing in the game pegs it.
		SpeedTop = 160,
		--- Pixels on the face's canvas: the numbers round a dial, and how far in from the rim.
		NumberSize = 14,
		NumberInset = 33,
		--- Per second, how quickly the rev needle follows. It drops with every upshift.
		NeedleGain = 12,
		--- Where the rev needle sits across a gear: `Idle` at the bottom of a band, `Shift` at its
		--- top. The gear is `Modules/AutomaticGearbox`'s, the one the engine note and HUD use.
		Idle = 0.22,
		Shift = 0.92,
	},

	Screen = {
		--- Bars on the screen's equaliser, and how quickly they chase the music's loudness.
		Bars = 9,
		BarGain = 16,
		--- `PlaybackLoudness` that fills a bar.
		FullLoudness = 320,
		--- Shown while the soundtrack is silent or muted.
		Silent = "Radio off",
	},
}

-- === The themes =============================================================

--[[ One per `CarRarity` band, bottom to top. `Accent` is left nil to take the band's own colour from
	`CarRarity.Colours`; set it to override. `Neon` lights the accent strip, the screen and the hub
	badge; off, they are the accent colour in plastic. ]]
export type Theme = {
	Name: string,
	Dash: Color3,
	DashMaterial: Enum.Material,
	Face: Color3,
	Trim: Color3,
	TrimMaterial: Enum.Material,
	Wheel: Color3,
	WheelMaterial: Enum.Material,
	Accent: Color3?,
	Neon: boolean,
	FlatBottom: boolean,
	TopStripe: boolean,
	Screen: boolean,
	Spokes: number,
}

CockpitConfig.Themes = {
	{
		Name = "Common",
		Dash = Color3.fromRGB(54, 54, 58),
		DashMaterial = Enum.Material.Plastic,
		Face = Color3.fromRGB(48, 48, 52),
		Trim = Color3.fromRGB(92, 92, 98),
		TrimMaterial = Enum.Material.Plastic,
		Wheel = Color3.fromRGB(38, 38, 42),
		WheelMaterial = Enum.Material.Plastic,
		Neon = false,
		FlatBottom = false,
		TopStripe = false,
		Screen = false,
		Spokes = 3,
	},
	{
		Name = "Uncommon",
		Dash = Color3.fromRGB(52, 54, 56),
		DashMaterial = Enum.Material.SmoothPlastic,
		Face = Color3.fromRGB(40, 42, 44),
		Trim = Color3.fromRGB(120, 124, 128),
		TrimMaterial = Enum.Material.Metal,
		Wheel = Color3.fromRGB(30, 32, 34),
		WheelMaterial = Enum.Material.SmoothPlastic,
		Neon = false,
		FlatBottom = false,
		TopStripe = true,
		Screen = true,
		Spokes = 3,
	},
	{
		Name = "Rare",
		Dash = Color3.fromRGB(34, 38, 48),
		DashMaterial = Enum.Material.Fabric,
		Face = Color3.fromRGB(26, 28, 36),
		Trim = Color3.fromRGB(190, 196, 206),
		TrimMaterial = Enum.Material.Metal,
		Wheel = Color3.fromRGB(28, 30, 38),
		WheelMaterial = Enum.Material.Leather,
		Neon = true,
		FlatBottom = false,
		TopStripe = true,
		Screen = true,
		Spokes = 3,
	},
	{
		Name = "Epic",
		Dash = Color3.fromRGB(26, 24, 34),
		DashMaterial = Enum.Material.SmoothPlastic,
		Face = Color3.fromRGB(20, 18, 28),
		Trim = Color3.fromRGB(70, 62, 90),
		TrimMaterial = Enum.Material.Metal,
		Wheel = Color3.fromRGB(22, 20, 30),
		WheelMaterial = Enum.Material.Leather,
		Neon = true,
		FlatBottom = true,
		TopStripe = true,
		Screen = true,
		Spokes = 3,
	},
	{
		Name = "Legendary",
		Dash = Color3.fromRGB(18, 18, 20),
		DashMaterial = Enum.Material.SmoothPlastic,
		Face = Color3.fromRGB(14, 14, 16),
		Trim = Color3.fromRGB(214, 170, 70),
		TrimMaterial = Enum.Material.Metal,
		Wheel = Color3.fromRGB(16, 16, 18),
		WheelMaterial = Enum.Material.Leather,
		Neon = true,
		FlatBottom = true,
		TopStripe = true,
		Screen = true,
		Spokes = 4,
	},
}

-- === Lighting ===============================================================

--[[ A ViewportFrame lights with an ambient and one directional light and nothing else. These are
	lifted toward white off `Lighting.OutdoorAmbient` so a night race still shows a dash, and the
	key light comes from up-front-left so the rim and the hands read as round. ]]
CockpitConfig.Light = {
	AmbientLift = 0.3, -- 0 = the world's outdoor ambient, 1 = white
	MinAmbient = Color3.fromRGB(84, 84, 92),
	Color = Color3.fromRGB(255, 250, 242),
	Direction = Vector3.new(-0.35, -1, -0.5),
	--- How often the ambient is re-read from `Lighting`, seconds. It only moves with the day cycle.
	Resample = 0.5,
}

--- Draw order for the cockpit's ScreenGui: over the world and the default layer, under every HUD
--- the game draws (the driving HUD is 895).
CockpitConfig.DisplayOrder = 3

return CockpitConfig
