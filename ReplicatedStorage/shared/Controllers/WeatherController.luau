--[[
	WeatherController  (client)
	---------------------------
	THE SKY, AND THE ONLY THING THAT DRAWS IT. `WeatherService` decides what the weather is and when;
	this turns that into something you can see, on the one machine that can see it.

	Two halves, and they run at different times on purpose:

	  1. THE LOOK, during a race only. Lighting, an Atmosphere, a colour grade, and a particle box
	     riding the camera. It goes up on `RaceStart` if this player's world has weather, comes down
	     on `RaceEnd`, and changes under a moving car when a storm starts or stops mid-run — which is
	     an ordinary thing, not an edge case: a run is a minute or two and an event is a few minutes.
	  2. THE NOTICE, in the lobby. A card that slides in from the top when an event starts in THIS
	     player's world, naming it and quoting what its cars pay. `WeatherService` also replays it
	     for whatever is already running when you join, and it fires at nobody else — see
	     `WeatherConfig.StartedEvent` for why the chat line that used to be here is gone, and
	     `UIController/Pages/Teleport` for what tells you about the other three worlds. It is built
	     out of the `car ui` kit's own textures rather than drawn in flat fills — the block over
	     `_buildNotice` is the account of that, and it is the same recipe the plot signage uses.

	=== WHY LIGHTING IS SAFE TO WRITE ==========================================================

	`Lighting` is one shared instance, and this file changes it. That is fine here and would not be
	in most games, for the reason the whole race stack is built on: DRIVING IS SOLO. Every client
	builds its own road, its own traffic and its own truck (RoadController's header), and a client
	writing its own Lighting is local to that client — nobody else's sky moves.

	It is still put back exactly as it was found, and that matters more than it looks: the lobby is
	the same place with the same Lighting, so a race that ended without restoring would leave a
	player standing on their forecourt in a sandstorm forever. `_capture` reads the live values at
	the moment the effect goes up rather than reading them from a config, so a build that re-authors
	the lobby's time of day needs no edit here.

	=== ONE THING WRITES LIGHTING DURING A RUN, AND IT IS THIS FILE =============================

	`DayNightController` owns the lobby's sky and stands down for the length of a race so that this
	one can have it. That leaves it unable to answer a player who opens the settings screen mid-run
	and picks DAY, which is a press the topbar still offers during a race. `rebase` is the way in:
	that file hands this one the sky it wants, this one swaps it in as the thing `_capture` had
	taken and repaints, and the count of files writing Lighting stays at one. See the block over
	`rebase` for what an event's own `Look` still outranks.

	=== THE PARTICLE BOX LIVES UNDER THE CAMERA ================================================

	Exactly as `WindController`'s does, and for exactly the same reason — see that file's header. A
	BasePart parented to `workspace.CurrentCamera` renders and cannot be found by any raycast or
	region query, which matters because this game queries the road constantly and a hundred-stud
	invisible box travelling with the player would be in the way of all of it.

	Particles are NOT locked to the part. They are born above the camera and left in world space, so
	you drive through the rain rather than carrying it. Locked, it would read as a windscreen effect.

	=== TWO SETS OF PARTICLES, ONE SWITCH ======================================================

	`WeatherConfig.EventVfx` picks what an event draws. Off, it is the one box above, built by
	`_buildSky` exactly as the sky first shipped. On, it is the event's `Vfx` block (`_buildVfx`):
	several boxes built from the VFXer library's textures, some of them standing on the road, plus a
	bolt on every flash in the thunderstorm and meteors in the meteor shower. The Lighting half is the
	same either way, so the switch can never change how far anybody can see.

	=== WHAT IS NOT HERE =======================================================================

	Mutations. A mutated car is dressed by `Modules/CarMutation` at the point it spawns
	(`TrafficController`), which is where the cars are. This file is the sky and nothing else.

	HOUSE RULE: no wiki-style double-bracket links in this comment — the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameplayFeedback = require(ReplicatedStorage.shared.Modules.GameplayFeedback)
local Shard = require(ReplicatedStorage.Packages.Shard)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)
local ArcadeKit = require(ReplicatedStorage.shared.Modules.ArcadeKit)

local WeatherController = Shard.new("WeatherController")

--- How long the sky takes to change, seconds. Long enough that a storm arriving mid-race reads as
--- weather rolling in rather than as a light switch, short enough that a run which is only ninety
--- seconds long actually gets to see it.
local FADE_IN = 3
--- ...and out. Faster, because the run is usually ending and nobody is watching the sky clear.
local FADE_OUT = 1.5

--- Names for everything this file parents into shared services, so a reload finds its own leftovers
--- rather than stacking a second set on top of them.
local ATMOSPHERE_NAME = "WeatherAtmosphere"
local GRADE_NAME = "WeatherGrade"
local SKY_NAME = "WeatherSky"

--[[ THE NOTICE'S TIMINGS AND ITS TWO POSITIONS.

	`SHOWN` is a fraction of the viewport and clears the Roblox topbar — the ScreenGui keeps the GUI
	inset, so 0 is already under it.

	HIDDEN IS NOT A FRACTION, and that is a fix rather than a preference. It was -0.25 of the
	viewport, which is only far enough to hide the card when the card is shorter than a quarter of
	the screen — and it is not, on a phone held sideways. Measured in the simulator at 896x414: the
	card stands 149px in a 335px-tall GUI, so "hidden" put its top at -84px and left 65px of it, the
	cap included, parked over the top of the screen. The old build had the same arithmetic and the
	same bug. `_hiddenPosition` measures the card instead, so it is off screen by construction at any
	viewport, and `HIDDEN_GAP` is the clearance above the edge that makes that visibly true rather
	than exactly true.

	It matters beyond tidiness: a card on its way out when a race starts stops mid-slide, and the top
	centre of the screen during a race belongs to the car's HP bar.

	`HOLD` is long by toast standards and deliberately: this is not a near miss congratulating you on
	something you just did, it is a piece of information you are meant to act on, and the action is
	"open the world screen and press Play". Seven seconds is about how long that takes to decide. ]]
local NOTICE_SHOWN_Y = 0.022
local NOTICE_HIDDEN_GAP = 12
local NOTICE_IN = 0.4
local NOTICE_HOLD = 7
local NOTICE_OUT = 0.35

--[[ THE CARD IS A PAGE OF THE KIT, NOT A ROUNDED RECTANGLE — 2026-08-26.

	It used to be a flat `#364157` Frame with a `UICorner` and a `UIStroke` in the event's colour,
	which is the same rounded-rect-and-neon-outline every other game on the platform draws and the
	exact thing the plot signage and the customer speech bubble were rebuilt to get away from
	(`assets/ui/upgrades/README.md`, `UIAssets.Bubble`). Standing in the lobby it sat two hundred
	pixels from the RANDOM CAR panel, which is real kit art, and the two did not look like the same
	game.

	So it is made of the kit's own parts now and no new art was drawn for it:

	  * the BODY is `UIAssets.Upgrades.SignPanel`, whose 746x308 canvas is 2.422:1 — within a
	    percent of the shape this card already was. That export exists because the garage-door sign
	    needed the kit at a wide aspect; a toast is the same problem, so it is the same drawing.
	  * the CAP is `UIAssets.SpawnCar.TitleBar`, the woven `#0066FF` bar every page in this kit
	    wears, inset by the panel texture's own 5px border exactly as `BuildPlotUpgradeSigns` insets
	    it — flush to the border, not over it, which is where the mockup puts it.
	  * the ICON sits in `UIAssets.Page.SlotSquare`, the empty Index collection slot, so the glyph
	    has a seat instead of floating on the navy.
	  * the PAYOFF is plain type in the mutation's own colour. It was a `UIAssets.Pill` until
	    2026-09-15 and read as a button, because the pill IS this kit's button (see `_buildNotice`).

	AND THE TYPE IS BOLD NOW, which is a bug fix rather than a restyle. Every other surface in this
	game is set in `Font.new(".../Ubuntu.json", Bold)`; this card asked for `Enum.Font.Ubuntu`, and
	that enum resolves to Ubuntu REGULAR — measured, not assumed (`TextBounds` 304 vs 319 on the
	same string at the same size). One lighter weight in a UI that is bold everywhere else is a good
	part of why the card read as somebody else's screen. ]]

--- Ubuntu Bold, the kit's face. `Enum.Font.Ubuntu` is NOT this — see the note above.
local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

--- `#28334B`, painted BEHIND the panel texture. The kit draws every navy surface at 80% so a page
--- you have opened lets the game show through; this is not a page you have opened, it is a toast
--- over a bright plaza in daylight, and at 80% the sky read straight through the sentence. Same
--- call and same reasoning as the speech bubble's (`UIAssets.Bubble`) and the forecourt board's.
--- The art then composites 80% of `#28334B` over `#28334B` and lands where it was drawn.
local NOTICE_FACE = Color3.fromRGB(40, 51, 75)
local NOTICE_TEXT = Color3.new(1, 1, 1)
local NOTICE_MUTED = Color3.fromRGB(168, 179, 208) -- the kit's secondary copy
local NOTICE_TEXT_STROKE = Color3.fromRGB(10, 20, 32)

--[[ The card's shape and everything laid out inside it, in fractions of the card.

	THE ASPECT IS THE TEXTURE'S, 746/308, and it is held by a constraint rather than by the two ends
	of a `UISizeConstraint` agreeing. That matters for one reason: the panel's 5px border and 5px
	inner rim come from LAYER STYLES and so do not scale with the art — stretch the texture off its
	drawn aspect and the border comes out thinner on two sides than on the other two, which is the
	wrongness `assets/ui/upgrades/README.md` describes as reading as "off" without being nameable.

	`BORDER_X`/`BORDER_Y` are that 5px expressed against the export's own canvas, which is what the
	cap is inset by. ]]
local NOTICE_ASPECT = 746 / 308
local BORDER_X = 5 / 746
local BORDER_Y = 5 / 308

--- How wide the card wants to be, and the pixel floor and ceiling that keep that sane on a phone
--- and on an ultrawide. The floor is what the old build used; the ceiling is a little over it.
local NOTICE_CARD_WIDTH = 0.34
local NOTICE_MIN_WIDTH = 360
local NOTICE_MAX_WIDTH = 620
--- The transparent box the panel is fitted inside, in pixels. Comfortably over the tallest the
--- panel can ever be (`NOTICE_MAX_WIDTH / NOTICE_ASPECT`, 256) so the WIDTH is always what binds.
local NOTICE_CARD_BOX = 400

--- Fractions of the card, ordered the way the eye reads it. The cap is deeper than a page's (a page
--- gives its bar a tenth of a tall panel; this one is short and wide, and a tenth of it is 25px on
--- a phone) and the two columns under it split at the icon well's right edge. The three rows under
--- the cap are ONE line each and spaced evenly down the well's height.
local NOTICE_LAYOUT = {
	Cap = { x = BORDER_X, y = BORDER_Y, w = 1 - 2 * BORDER_X, h = 0.2 },
	Title = { x = 0.03, w = 0.62 },
	Clock = { x = 0.66, w = 0.31 },
	Well = { x = 0.028, y = 0.255, h = 0.69 },
	--- Inside the well, so the glyph never touches the slot's painted rim.
	Icon = 0.16,
	Column = { x = 0.335, w = 0.635 },
	World = { y = 0.3, h = 0.12 },
	Blurb = { y = 0.5, h = 0.15 },
	Payoff = { y = 0.72, h = 0.17 },
}

--[[ ONE TYPE SCALE FOR THE WHOLE CARD, as fractions of the card's HEIGHT, applied as a
	`UITextSizeConstraint` ceiling with `TextScaled` left on.

	Same instrument the upgrade board uses and for the same reason: every string the game ships fits
	its box at the ceiling, so the four rows render at sizes that agree with each other and the card
	reads as one design rather than four labels that happened to land near each other. A string that
	does NOT fit — a translation into a longer language — still shrinks rather than spilling.

	EVERY ROW IS ONE LINE, the blurb included since it lost its second sentence (it only repeated
	the payoff). The copy is short by construction (the world is on its own row rather than in the
	title for exactly this reason), and the ceilings are sized under the width at which `TextScaled`
	would reach for a second line. Do NOT "fix" a wrap by writing `TextWrapped = false`: that silently
	clears `TextScaled` and drops the label to the default 8px, which is measured in this repo more
	than once. Shorten the string instead; `WeatherConfig`'s `Blurb` has the budget. ]]
local NOTICE_TYPE = {
	Title = 0.155,
	Clock = 0.1,
	World = 0.105,
	Blurb = 0.115,
	Payoff = 0.13,
}

--[[ THE NEW UI'S CARD (`NewUIConfig`): where its template is authored, and how long to wait for it.
	`BuildWeatherNoticeV2` puts it on the hidden `MainUIV2.Screens` shelf; `_buildNoticeKit` clones
	it. The wait is for the shelf replicating at join, which has always landed long before the first
	event, so ten seconds is a fence rather than a budget. ]]
local NOTICE_SHELF = "Screens"
local NOTICE_TEMPLATE = "WeatherNotice"
local NOTICE_TEMPLATE_WAIT = 10

--[[ How far above the camera the particle box sits, and how big it is.

	WIDER THAN THE ROAD (60 studs of lanes plus verges) so rain does not stop at the kerb, and tall
	enough that a particle born at the top is still falling when it passes the camera.

	AND NO BIGGER THAN THAT, which is the part that was got wrong first and is worth writing down.
	The first build of this used a 220 x 90 x 260 box, which is five million cubic studs; at the
	rates below that is about one particle per thirty thousand of them, and measured in a playtest
	the result was a thunderstorm with perhaps twenty visible streaks — indistinguishable from clear
	weather in a screenshot. Density is what makes rain read, and density is rate divided by VOLUME,
	so the box is the first number to reach for and the rate is the second.

	At 140 x 70 x 140 the volume is 1.4 million and the camera is inside it rather than at the bottom
	of it, so most of what is alive is in shot. `Ahead` and `Lift` are deliberately equal and modest:
	far enough that the box does not clip through the chase camera, close enough that the player is
	standing in the weather rather than watching it fall in front of them. ]]
local BOX = { Width = 140, Depth = 140, Height = 70, Lift = 34, Ahead = 34 }

--[[ THE LIBRARY LOOK (`WeatherConfig.EventVfx`). Everything below `_buildSky` that is not the
	original box is this: an event's `Vfx` layers, each its own box riding the camera, the
	thunderstorm's bolt and the meteor shower's meteors. All of it lives in one Folder under the
	camera, for the header's reason, so tearing an event down is one Destroy.

	`MAX_LAYERS` bounds how many emitters a config can put up at once, so a typo cannot build a
	fountain. `GROUND_EVERY` is how often the ground is re-probed when there is no road to ask (a
	sky staged in the lobby); during a race the deck height comes from `RoadController`. ]]
local VFX_NAME = "WeatherVfx"
--- The original streak: a soft dot that a NEGATIVE `Squash` stretches along its fall. A layer with
--- no `Texture` gets it, which is how the old rain's numbers carry over into a `Vfx` block.
local STREAK_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local MAX_LAYERS = 5
local GROUND_EVERY = 0.25

--- A layer's `Flipbook`, `Direction` and `Facing`, by name. See the `Vfx` block in WeatherConfig.
local FLIPBOOKS = {
	Grid2x2 = Enum.ParticleFlipbookLayout.Grid2x2,
	Grid4x4 = Enum.ParticleFlipbookLayout.Grid4x4,
	Grid8x8 = Enum.ParticleFlipbookLayout.Grid8x8,
}
local DIRECTIONS = {
	Down = Enum.NormalId.Bottom,
	Up = Enum.NormalId.Top,
	Across = Enum.NormalId.Right,
}
local FACINGS = {
	Streak = Enum.ParticleOrientation.VelocityParallel,
	Camera = Enum.ParticleOrientation.FacingCamera,
	Upright = Enum.ParticleOrientation.FacingCameraWorldUp,
	Flat = Enum.ParticleOrientation.VelocityPerpendicular,
}

--[[ How a bolt fades: on, a flicker off, back on, and out, across its short life. A real stroke is
	several return strokes down the same channel inside half a second, and the double flicker is most
	of what makes a line in the sky read as lightning rather than as a light switching on and off. ]]
local BOLT_FLICKER = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.12, 0.05),
	NumberSequenceKeypoint.new(0.2, 0.85),
	NumberSequenceKeypoint.new(0.3, 0.05),
	NumberSequenceKeypoint.new(0.45, 0.7),
	NumberSequenceKeypoint.new(0.55, 0.2),
	NumberSequenceKeypoint.new(1, 1),
})

--- A spec's number, or a random one out of its `{ min, max }`.
local function roll(rng: Random, value: unknown, fallback: number): number
	if type(value) == "table" and type(value[1]) == "number" and type(value[2]) == "number" then
		return rng:NextNumber(math.min(value[1], value[2]), math.max(value[1], value[2]))
	end
	return if type(value) == "number" then value else fallback
end

--- A spec's number or `{ min, max }` as the engine's range.
local function rangeOf(value: unknown, fallback: number): NumberRange
	if type(value) == "table" and type(value[1]) == "number" and type(value[2]) == "number" then
		return NumberRange.new(math.min(value[1], value[2]), math.max(value[1], value[2]))
	end
	return NumberRange.new(if type(value) == "number" then value else fallback)
end

--- A spec's number, or its list spread evenly from birth (0) to death (1), as a sequence.
local function sequenceOf(value: unknown, fallback: number): NumberSequence
	local list = if type(value) == "table" then value :: { any } else { value }
	local count = math.min(#list, 20)
	if count < 2 then
		local only = list[1]
		return NumberSequence.new(if type(only) == "number" then only else fallback)
	end
	local points = table.create(count)
	for i = 1, count do
		local v = list[i]
		points[i] = NumberSequenceKeypoint.new((i - 1) / (count - 1), if type(v) == "number" then v else fallback)
	end
	return NumberSequence.new(points)
end

--- A sequence's value at `t` (0..1), interpolated between its keypoints.
local function sampleSequence(sequence: NumberSequence, t: number): number
	t = math.clamp(t, 0, 1)
	local points = sequence.Keypoints
	for i = 2, #points do
		local after = points[i]
		if t <= after.Time then
			local before = points[i - 1]
			local span = after.Time - before.Time
			local k = if span > 0 then (t - before.Time) / span else 1
			return before.Value + (after.Value - before.Value) * k
		end
	end
	return points[#points].Value
end

--- An invisible part to hang an emitter or a trail off. Anchored and out of every query, though
--- under the camera nothing can find it anyway (see the header).
local function carrier(name: string, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	part.Size = size
	return part
end

--[[ Write one layer spec onto an emitter. Every property a spec can reach is written, so what an
	emitter looks like is the spec and nothing left over from how it was made. `facing` is the
	default for a spec that names none: the falling layers default to streaks, and the one-off
	emitters (a bolt, a meteor's head, its blast) to facing the camera, because a streak with no
	velocity has no direction to lie along. ]]
local function dressLayer(emitter: ParticleEmitter, spec: any, facing: Enum.ParticleOrientation?)
	emitter.Texture = if type(spec.Texture) == "string" then spec.Texture else STREAK_TEXTURE
	local flipbook = FLIPBOOKS[spec.Flipbook]
	emitter.FlipbookLayout = flipbook or Enum.ParticleFlipbookLayout.None
	if flipbook and spec.RandomFrame == true then
		-- One still frame per particle: the engine's own recipe is a random start and no framerate.
		emitter.FlipbookMode = Enum.ParticleFlipbookMode.Loop
		emitter.FlipbookFramerate = NumberRange.new(0)
		emitter.FlipbookStartRandom = true
	else
		--[[ OneShot plays the sheet once across each life, which is what every sheet here is drawn
			for. Written every time: the default is Loop at one frame a second, which shows a short
			particle its first frame and nothing else. ]]
		emitter.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
		emitter.FlipbookStartRandom = false
	end

	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.EmissionDirection = DIRECTIONS[spec.Direction] or Enum.NormalId.Bottom
	emitter.Orientation = FACINGS[spec.Facing] or facing or Enum.ParticleOrientation.VelocityParallel
	emitter.Squash = NumberSequence.new(spec.Squash or 0)

	emitter.Rate = spec.Rate or 20
	emitter.Speed = rangeOf(spec.Speed, 0)
	emitter.Lifetime = rangeOf(spec.Lifetime, 1)
	emitter.Size = sequenceOf(spec.Size, 1)
	emitter.Transparency = sequenceOf(spec.Transparency, 0.4)
	local color = if typeof(spec.Color) == "Color3" then spec.Color else Color3.new(1, 1, 1)
	emitter.Color = ColorSequence.new(color, if typeof(spec.ColorEnd) == "Color3" then spec.ColorEnd else color)
	emitter.LightEmission = spec.Glow or 0
	emitter.LightInfluence = 0
	emitter.Brightness = spec.Brightness or 1

	emitter.Acceleration = Vector3.new(spec.Wind or 0, -(spec.Gravity or 0), 0)
	emitter.Drag = spec.Drag or 0
	local spread = spec.Spread or 6
	emitter.SpreadAngle = Vector2.new(spread, spread)
	--- A number is how far either way of upright; `{ min, max }` is an exact range.
	emitter.Rotation = if type(spec.Rotation) == "table"
		then rangeOf(spec.Rotation, 0)
		else NumberRange.new(-(spec.Rotation or 0), spec.Rotation or 0)
	local spin = spec.Spin or 0
	emitter.RotSpeed = NumberRange.new(-spin, spin)
	emitter.LockedToPart = spec.Locked == true
	-- The carriers are anchored and moved by CFrame, so there is no velocity worth inheriting.
	emitter.VelocityInheritance = 0
	emitter.ZOffset = spec.ZOffset or 0
end

--- A layer's `Box`, with every field it leaves out taken from the original camera box.
local function boxOf(spec: any): { Width: number, Height: number, Depth: number, Ahead: number, Lift: number }
	local box = if type(spec.Box) == "table" then spec.Box else {}
	return {
		Width = box.Width or BOX.Width,
		Height = box.Height or BOX.Height,
		Depth = box.Depth or BOX.Depth,
		Ahead = box.Ahead or BOX.Ahead,
		Lift = box.Lift or (if spec.Ground == true then 0 else BOX.Lift),
	}
end

--- The camera's look, flattened onto the ground and made a unit. Straight down falls back to +Z.
local function flatten(look: Vector3): Vector3
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
end

-- === The notice ============================================================
--[[ THE CARD THAT SLIDES IN WHEN THE WEATHER CHANGES WHERE YOU LIVE.

	Built in code, like every other screen this project animates (`NearMissController`'s header has
	the full argument): there is no layout here to nudge in the Explorer — an icon, three lines and a
	slide — and the layout that does exist is authored in the place.

	BUILT ON FIRST USE AND THEN KEPT. Most sessions see one of these, some see none, and a
	`ScreenGui` built at boot for an event that may not happen for eleven minutes is a screen nobody
	asked for. Kept afterwards because the second one is free and re-arming beats rebuilding.

	`ResetOnSpawn` off, or a notice would vanish the moment a race ended under it.

	WITH THE NEW UI ON, THE CARD IS THE KIT'S (`_buildNoticeKit`), and everything below this line
	is the shipping card, unchanged. ]]
function WeatherController._buildNotice(self)
	if self._notice then
		return
	end
	if UIRoot.isNewUI() and self:_buildNoticeKit() then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "WeatherNotice"
	gui.ResetOnSpawn = false
	--[[ The inset is KEPT (`IgnoreGuiInset` left false), which is the whole placement decision: at
		the top of the screen the Roblox topbar is the one thing this cannot be under, and letting
		the engine measure it is more reliable than guessing 36 pixels. ]]
	gui.DisplayOrder = 800
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	--[[ A transparent box that exists to be the thing the slide tween moves, and to carry the pixel
		floor and ceiling on the card's WIDTH.

		WHY THE TWO CONSTRAINTS ARE ON DIFFERENT INSTANCES. The card's height has to come from its
		width through the texture's aspect, and a `UISizeConstraint` clamps BOTH axes — put the two
		on one frame and they fight over the height, which is how a card ends up a few percent off
		the aspect its border was drawn at. Here the box owns the width and the panel inside it owns
		the shape; the box is always the taller of the two, so the panel never runs out of room. ]]
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0)
	--- Parked off screen, and re-measured every time it is shown — see `_hiddenPosition`.
	card.Position = UDim2.new(0.5, 0, 0, -NOTICE_CARD_BOX)
	--[[ THE HEIGHT IS A FIXED PIXEL BOX AND NOT A FRACTION OF ANYTHING, which is the one number in
		here that took a measurement to get right.

		The panel derives its height from its width, so this box only has to be tall enough never to be
		the binding constraint — and a scale height is not: at 34% of a landscape phone's GUI it comes
		out 114px, under the 149px a card at the 360px width floor needs, so the aspect constraint fits
		by HEIGHT instead and the card lands 276px wide with the floor silently ignored. `NOTICE_CARD_BOX`
		is above the tallest the panel can ever be (620 / 2.422 = 256), so width always binds. ]]
	card.Size = UDim2.new(NOTICE_CARD_WIDTH, 0, 0, NOTICE_CARD_BOX)
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0
	card.Parent = gui

	--[[ Bounded in PIXELS as well as scale, and on the WIDTH only — the height above is already a
		fixed box. A card that is 34% of the viewport is right on a phone and absurd on an ultrawide,
		and every row inside is `TextScaled`, so without a ceiling the type grows with the monitor
		rather than with the message. ]]
	local bounds = Instance.new("UISizeConstraint")
	bounds.MinSize = Vector2.new(NOTICE_MIN_WIDTH, 0)
	bounds.MaxSize = Vector2.new(NOTICE_MAX_WIDTH, NOTICE_CARD_BOX)
	bounds.Parent = card

	--- The kit panel itself: border, inner rim and weave all drawn into the texture, so there is no
	--- `UICorner` and no `UIStroke` anywhere on this card any more.
	local panel = Instance.new("ImageLabel")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.fromScale(0.5, 0)
	panel.Size = UDim2.fromScale(1, 1)
	panel.Image = UIAssets.url(UIAssets.Upgrades.SignPanel)
	--- `Stretch`, never `Slice`: the texture is exported at the aspect it is drawn at and the aspect
	--- constraint below holds it there, so the stretch is identity. See the standing note in
	--- `UIAssets.Slice` for why a slice inset is the wrong tool for almost everything in this kit.
	panel.ScaleType = Enum.ScaleType.Stretch
	panel.BackgroundColor3 = NOTICE_FACE
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel = 0
	panel.Parent = card

	local shape = Instance.new("UIAspectRatioConstraint")
	shape.AspectRatio = NOTICE_ASPECT
	shape.DominantAxis = Enum.DominantAxis.Width
	shape.AspectType = Enum.AspectType.FitWithinMaxSize
	shape.Parent = panel

	--- The woven `#0066FF` cap, inset by the panel texture's own 5px border rather than run edge to
	--- edge — flush to the border, not over it, which is where the mockup puts every page's bar.
	local cap = Instance.new("ImageLabel")
	cap.Name = "Cap"
	cap.Position = UDim2.fromScale(NOTICE_LAYOUT.Cap.x, NOTICE_LAYOUT.Cap.y)
	cap.Size = UDim2.fromScale(NOTICE_LAYOUT.Cap.w, NOTICE_LAYOUT.Cap.h)
	cap.Image = UIAssets.url(UIAssets.SpawnCar.TitleBar)
	cap.ScaleType = Enum.ScaleType.Stretch
	cap.BackgroundTransparency = 1
	cap.BorderSizePixel = 0
	cap.Parent = panel

	--[[ One row of type. `fraction` is a ceiling against the CARD's height rather than against this
		row's own box, which is what makes rows in differently-sized boxes agree with each other —
		the single instrument the upgrade board's `TYPE` table uses.

		It is recomputed on every resize because a `UITextSizeConstraint` is in pixels and the card
		is sized in scale. `_fitNotice` is the one place that happens. ]]
	local rows: { TextLabel } = {}
	local function line(name: string, parent: Instance, colour: Color3, fraction: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.FontFace = FONT
		label.TextColor3 = colour
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Center
		--- Do NOT follow this with a `TextWrapped` write. It silently clears `TextScaled` and drops
		--- the label to the default 8px with nothing anywhere reporting a problem.
		label.TextScaled = true
		label.Text = ""

		local ceiling = Instance.new("UITextSizeConstraint")
		ceiling.Name = "Ceiling"
		ceiling.MinTextSize = 8
		ceiling.MaxTextSize = 8 -- rewritten by `_fitNotice` before anybody sees it
		ceiling:SetAttribute("Fraction", fraction)
		ceiling.Parent = label

		label.Parent = parent
		table.insert(rows, label)
		return label
	end

	--- The event's name, in the cap. WHITE, like every other title in this kit — the identity the
	--- old build put in a coloured rim is carried by the glyph and the pill now, which are art.
	local title = line("Title", cap, NOTICE_TEXT, NOTICE_TYPE.Title)
	title.AnchorPoint = Vector2.new(0, 0.5)
	title.Position = UDim2.fromScale(NOTICE_LAYOUT.Title.x, 0.5)
	title.Size = UDim2.fromScale(NOTICE_LAYOUT.Title.w, 0.72)

	--[[ How long is left, on the far end of the same bar. It rides the cap rather than taking a row
		of its own because it is a clock and a clock belongs in a header — and because the row it
		used to share with the payoff cost that line a third of its width to a middot and a time. ]]
	local clock = line("Clock", cap, NOTICE_TEXT, NOTICE_TYPE.Clock)
	clock.AnchorPoint = Vector2.new(0, 0.5)
	clock.Position = UDim2.fromScale(NOTICE_LAYOUT.Clock.x, 0.5)
	clock.Size = UDim2.fromScale(NOTICE_LAYOUT.Clock.w, 0.62)
	clock.TextXAlignment = Enum.TextXAlignment.Right
	clock.TextTransparency = 0.15

	--- The glyph's seat: the kit's own empty collection slot, which is the one square well this UI
	--- has. Without it the icon floats on bare navy, which is what it did before.
	local well = Instance.new("ImageLabel")
	well.Name = "Well"
	well.Position = UDim2.fromScale(NOTICE_LAYOUT.Well.x, NOTICE_LAYOUT.Well.y)
	--[[ A REAL width box, not `UDim2.fromScale(0, h)`. `AspectType.ScaleWithParentSize` resolves the
		element against its PARENT rather than against its authored size, so the authored width is
		only a starting point — but a zero one still collapses under the default `AspectType`, and
		that trap has cost this repo an afternoon before (see `UIAssets`' sizing note). ]]
	well.Size = UDim2.fromScale(NOTICE_LAYOUT.Well.h / NOTICE_ASPECT, NOTICE_LAYOUT.Well.h)
	well.Image = UIAssets.url(UIAssets.Page.SlotSquare)
	well.ScaleType = Enum.ScaleType.Stretch
	well.BackgroundTransparency = 1
	well.BorderSizePixel = 0
	well.Parent = panel

	--- Square off the well's HEIGHT, at the slot art's own near-square aspect so its painted rim is
	--- the same weight top and bottom as it is left and right.
	local wellShape = Instance.new("UIAspectRatioConstraint")
	wellShape.AspectRatio = UIAssets.Size.SlotSquare.X / UIAssets.Size.SlotSquare.Y
	wellShape.DominantAxis = Enum.DominantAxis.Height
	wellShape.AspectType = Enum.AspectType.ScaleWithParentSize
	wellShape.Parent = well

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(1 - NOTICE_LAYOUT.Icon * 2, 1 - NOTICE_LAYOUT.Icon * 2)
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	--- `Fit` and not `Stretch`: the six weather glyphs are not all one aspect, and this is the one
	--- place on the card where the art is not being drawn at the size it was exported at.
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = well

	--- Which world this is, under the cap and in the kit's secondary copy — the one line on the card
	--- about WHERE rather than about what the sky is doing.
	local world = line("World", panel, NOTICE_MUTED, NOTICE_TYPE.World)
	world.Position = UDim2.fromScale(NOTICE_LAYOUT.Column.x, NOTICE_LAYOUT.World.y)
	world.Size = UDim2.fromScale(NOTICE_LAYOUT.Column.w, NOTICE_LAYOUT.World.h)

	--- The sentence: one line of flavour, what the sky is doing.
	local blurb = line("Blurb", panel, NOTICE_TEXT, NOTICE_TYPE.Blurb)
	blurb.Position = UDim2.fromScale(NOTICE_LAYOUT.Column.x, NOTICE_LAYOUT.Blurb.y)
	blurb.Size = UDim2.fromScale(NOTICE_LAYOUT.Column.w, NOTICE_LAYOUT.Blurb.h)

	--[[ THE PAYOFF, AS TYPE AND NOTHING ELSE. It sat on a `UIAssets.Pill` until 2026-09-15, and a
		pill is this kit's BUTTON: the upgrade board's UPGRADE, the market's filter chips, the same
		bevel and weave. So the one line on the card that is information and not an action looked
		like the one thing on it to press, and nothing happened when you did. A line of text with
		nothing behind it cannot be mistaken for that.

		Its colour is the MUTATION's (`WeatherConfig.Mutations[].Color`), set per event in
		`_onStarted`: the same identity colour the car carries on the road, and every one of the six
		clears 3.5:1 on the kit navy, where the pill faces it replaces did not (Blue is `#0066FF`). ]]
	local payoff = line("Payoff", panel, NOTICE_TEXT, NOTICE_TYPE.Payoff)
	payoff.Position = UDim2.fromScale(NOTICE_LAYOUT.Column.x, NOTICE_LAYOUT.Payoff.y)
	payoff.Size = UDim2.fromScale(NOTICE_LAYOUT.Column.w, NOTICE_LAYOUT.Payoff.h)

	--- The one stroke left on the card, and it is on TYPE rather than on a panel: the title is read
	--- across a `#0066FF` bar, and the kit's own boards give their headline the same hairline.
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = NOTICE_TEXT_STROKE
	titleStroke.Thickness = 2
	titleStroke.Transparency = 0.55
	titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	titleStroke.Parent = title

	self._notice = gui
	self._noticeCard = card
	self._noticePanel = panel
	self._noticeIcon = icon
	self._noticeTitle = title
	self._noticeClock = clock
	self._noticeWorld = world
	self._noticeBlurb = blurb
	self._noticePayoff = payoff
	self._noticeRows = rows

	--- Ceilings are in pixels and the card is sized in scale, so they are re-derived whenever the
	--- panel's own size changes — a viewport resize, a device rotation, or the first layout pass.
	self._noticeFit = panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_fitNotice()
	end)
	self:_compactNotice()
	self:_fitNotice()

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

--[[ THE SAME CARD ON THE CARTOONY KIT, for the new UI (`NewUIConfig`).

	THE ART IS AUTHORED, NOT BUILT. `BuildWeatherNoticeV2` cuts it out of the kit's `PromptUI` onto
	the hidden `MainUIV2.Screens` shelf, and its header has why it is a toast of its own and not the
	HUD's Boosts row. This clones it into a ScreenGui of this file's own at the same 800, because a
	frame inside `MainUIV2` would share that ScreenGui's one layer with the menus.

	IT FILLS IN THE FIELDS `_buildNotice` FILLS IN, and that is the whole integration. The slide, the
	hold, the hidden position and the type ceilings all read `_noticeCard`, `_noticePanel` and
	`_noticeRows`, and the kit card is the card and the panel at once: nothing measures a box around
	it. The template names each row's size cap `Ceiling` with a `Fraction`, so `_fitNotice` is the
	one function for both cards.

	THE KIT'S SPACE, and the one the shipping card already sat in: `IgnoreGuiInset` false with
	`CoreUISafeInsets`, which is where the kit frame was laid out, so 0 is already under the topbar.

	FALSE, AND A WARNING, when the template is not in the place. `_buildNotice` then builds the
	shipping card, so a place that is missing the art still tells the player about the storm. ]]
function WeatherController._buildNoticeKit(self): boolean
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", NOTICE_TEMPLATE_WAIT)
	local root = playerGui and UIRoot.wait(playerGui :: PlayerGui, NOTICE_TEMPLATE_WAIT)
	local shelf = root and root:WaitForChild(NOTICE_SHELF, NOTICE_TEMPLATE_WAIT)
	local template = shelf and shelf:WaitForChild(NOTICE_TEMPLATE, NOTICE_TEMPLATE_WAIT)
	if not (template and template:IsA("GuiObject")) then
		self.log:warn(
			string.format(
				"No %s.%s.%s in this place (run BuildWeatherNoticeV2); showing the shipping card instead.",
				UIRoot.name(),
				NOTICE_SHELF,
				NOTICE_TEMPLATE
			)
		)
		return false
	end

	local card = template:Clone() :: GuiObject
	card.Name = "Card"
	--- The kit's text caps are pixels for a 1080-tall screen; this keeps them in proportion above it.
	--- The line ceilings are `_fitNotice`'s and are named `Ceiling`, which the helper leaves alone.
	require(script.Parent.UIController.KitPage).scaleTextCaps(card)

	local header = card:FindFirstChild("Header")
	local main = card:FindFirstChild("Main")
	local well = main and main:FindFirstChild("Well")
	local parts = {
		title = header and header:FindFirstChild("Title"),
		clock = header and header:FindFirstChild("Clock"),
		icon = well and well:FindFirstChild("Icon"),
		world = main and main:FindFirstChild("World"),
		blurb = main and main:FindFirstChild("Blurb"),
		payoff = main and main:FindFirstChild("Payoff"),
	}
	--- By name, not by `pairs`: a part that is missing is a nil, and a nil is not in the table to visit.
	for _, name in { "title", "clock", "icon", "world", "blurb", "payoff" } do
		if not parts[name] then
			self.log:warn(string.format("The %s template has no `%s`; re-run BuildWeatherNoticeV2. Showing the shipping card instead.", NOTICE_TEMPLATE, name))
			card:Destroy()
			return false
		end
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "WeatherNotice"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 800
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	--- Anchored at its top centre by the build command, and parked off screen the way `_buildNotice`
	--- parks the shipping one; `_showNotice` re-measures it on every show.
	card.Visible = true
	card.Position = UDim2.new(0.5, 0, 0, -NOTICE_CARD_BOX)
	card.Parent = gui

	self._notice = gui
	self._noticeKit = true
	self._noticeCard = card
	self._noticePanel = card
	self._noticeIcon = parts.icon
	self._noticeTitle = parts.title
	self._noticeClock = parts.clock
	self._noticeWorld = parts.world
	self._noticeBlurb = parts.blurb
	self._noticePayoff = parts.payoff
	--- The header title keeps the kit's own cap, so it is not one of these. See the build command.
	self._noticeRows = { parts.clock, parts.world, parts.blurb, parts.payoff }

	self._noticeFit = card:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_fitNotice()
	end)
	self:_compactNotice()
	self:_fitNotice()

	gui.Parent = playerGui
	return true
end

--[[ 2026-10-12: The page-shaped event notice covered the road. Keep the kit art, but fit
	both template and fallback to two rows: event/timer, then icon/bonus (or the blurb).
	Runtime sizing also repairs templates already published, without another Studio rebuild. ]]
function WeatherController._compactNotice(self)
	local card, panel = self._noticeCard, self._noticePanel
	card.Size = UDim2.new(0.34, 0, 0, 120)
	local bounds = card:FindFirstChildOfClass("UISizeConstraint") or Instance.new("UISizeConstraint")
	bounds.MinSize = Vector2.new(260, 0)
	bounds.MaxSize = Vector2.new(420, 120)
	bounds.Parent = card
	local shape = panel:FindFirstChildOfClass("UIAspectRatioConstraint")
	if shape then shape.AspectRatio = 4.5 end
	local header = self._noticeTitle.Parent
	header.AnchorPoint = Vector2.new(0, 0)
	header.Position = UDim2.fromScale(0.03, 0.04)
	header.Size = UDim2.fromScale(0.94, 0.4)
	self._noticeTitle.AnchorPoint = Vector2.new(0, 0.5)
	self._noticeTitle.Position = UDim2.fromScale(0, 0.5)
	self._noticeTitle.Size = UDim2.fromScale(0.70, 0.9)
	self._noticeClock.AnchorPoint = Vector2.new(1, 0.5)
	self._noticeClock.Position = UDim2.fromScale(1, 0.5)
	self._noticeClock.Size = UDim2.fromScale(0.28, 0.7)
	local titleCap = self._noticeTitle:FindFirstChildOfClass("UITextSizeConstraint")
	if titleCap then
		titleCap.MinTextSize = 8
		titleCap.MaxTextSize = 24
		if titleCap.Name == "Ceiling" then titleCap:SetAttribute("Fraction", 0.30) end
	end
	local main = self._noticePayoff.Parent
	if self._noticeKit then
		main.AnchorPoint = Vector2.new(0, 0)
		main.Position = UDim2.fromScale(0.03, 0.46)
		main.Size = UDim2.fromScale(0.94, 0.49)
	end
	local well = self._noticeIcon.Parent
	well.AnchorPoint = Vector2.new(0, 0.5)
	well.Position = UDim2.fromScale(0.02, if self._noticeKit then 0.5 else 0.72)
	well.Size = UDim2.fromScale(0.12, if self._noticeKit then 0.9 else 0.44)
	local square = well:FindFirstChildOfClass("UIAspectRatioConstraint")
	if square then square.AspectType = Enum.AspectType.FitWithinMaxSize end
	self._noticeWorld.Visible = false
	for _, label in { self._noticePayoff, self._noticeBlurb } do
		label.AnchorPoint = Vector2.new(0, 0.5)
		label.Position = UDim2.fromScale(0.16, if self._noticeKit then 0.5 else 0.72)
		label.Size = UDim2.fromScale(0.82, if self._noticeKit then 0.8 else 0.39)
	end
	for _, label in { self._noticeClock, self._noticePayoff, self._noticeBlurb } do
		local ceiling = label:FindFirstChild("Ceiling")
		if ceiling then ceiling:SetAttribute("Fraction", if label == self._noticeClock then 0.20 else 0.25) end
	end
end

--[[ Re-derive every row's `MaxTextSize` from the card's rendered height.

	`TextScaled` on its own sizes each row to its own box, which is exactly what made the old card
	look like four unrelated labels: a short world name rendered huge and a long blurb rendered
	small, in boxes only a few percent apart. One ceiling per row against ONE measurement is what
	makes them agree.

	A zero height — the frame has not been laid out yet, or the GUI is disabled — is skipped rather
	than written, because a ceiling of zero is a label that renders nothing. ]]
function WeatherController._fitNotice(self)
	local panel = self._noticePanel
	if not panel then
		return
	end
	local height = panel.AbsoluteSize.Y
	if height <= 0 then
		return
	end
	for _, label in self._noticeRows do
		local ceiling = label:FindFirstChild("Ceiling")
		if ceiling and ceiling:IsA("UITextSizeConstraint") then
			local fraction = ceiling:GetAttribute("Fraction")
			if type(fraction) == "number" then
				ceiling.MaxTextSize = math.max(8, math.round(height * fraction))
			end
		end
	end
end

--[[ Where "off screen" is, in pixels, measured off the card rather than guessed at as a fraction
	of the viewport.

	The PANEL is what is measured and the CARD is what moves: the card is a fixed 400px box and the
	panel is however tall its width made it, so parking the card by its own height would send it four
	hundred pixels up on a phone for no reason and make the slide read as a launch. The panel sits at
	the card's top, so clearing the panel clears everything anybody can see.

	A panel that has not been laid out yet (`AbsoluteSize.Y` of 0, before the first frame) falls back
	to the full box, which is over-far but never under-far — the failure this replaces. ]]
function WeatherController._hiddenPosition(self): UDim2
	local panel = self._noticePanel
	local height = if panel and panel.AbsoluteSize.Y > 0 then panel.AbsoluteSize.Y else NOTICE_CARD_BOX
	return UDim2.new(0.5, 0, 0, -(height + NOTICE_HIDDEN_GAP))
end

--- Put the card away. Also the tail of `_showNotice`'s own timer, so there is exactly one way down.
function WeatherController._hideNotice(self)
	if not (self._notice and self._notice.Enabled) then
		return
	end
	self._noticeToken += 1
	local token = self._noticeToken
	local tween = TweenService:Create(
		self._noticeCard,
		TweenInfo.new(NOTICE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = self:_hiddenPosition() }
	)
	self._noticeTween = tween
	tween.Completed:Connect(function()
		-- Fenced, so a notice that arrived during the slide out does not have its own card disabled
		-- out from under it by the previous one finishing.
		if self._noticeToken == token and self._notice then
			self._notice.Enabled = false
		end
	end)
	tween:Play()
end

--[[ AN EVENT HAS STARTED IN THIS PLAYER'S WORLD. Say so.

	`world` is theirs by construction — the server only fires this at the players in it
	(`WeatherService._flush`) — and it is still NAMED on the card. That is not redundancy: a player
	standing in the lobby has no other reminder of which world they last drove, and "RUSH HOUR IN THE
	DESERT" is a sentence they can act on where "RUSH HOUR" is a sentence they have to think about.

	NOT DURING A RACE, and that is the one real placement decision in this file. The top-centre band
	belongs to the car's HP bar (`StarterGui.CarHud.HPBar`), so there is nowhere to put this that is
	not over something the player is reading at speed — and there is no need to: the sky changes
	around them, and under rush hour the road visibly fills up. The card is for the lobby, which is
	where the decision it is asking for gets made.

	AN UNKNOWN EVENT KEY SHOWS NOTHING. Same reasoning as `TipsConfig`'s: during a soft deploy a
	server can be one build ahead of a client, and a blank card is a worse answer than no card. ]]
function WeatherController._onStarted(self, world: unknown, key: unknown, endsAt: unknown)
	local event = WeatherConfig.eventOf(key)
	if not (event and self._live) or self._racing then
		return
	end
	-- No weather announcements while there is any tutorial left, lobby beats included.
	if TutorialConfig.isUnfinished(Players.LocalPlayer:GetAttribute(TutorialConfig.StepAttribute)) then
		return
	end
	self:_buildNotice()
	if not self._notice or self._racing then
		return
	end

	local id = WeatherConfig.iconOf(event.Key)
	self._noticeIcon.Image = if id then UIAssets.url(id) else ""

	--- WHITE ON THE CAP, like every title in this kit. The event's colour used to be here and in the
	--- card's rim; it is in the glyph and the pill now, both of which are art rather than a tint.
	--- The Cartoony Kit sets its headings in title case ("Settings", "Prompt Request"), so the new
	--- UI's card takes the name as written.
	--[[ THE WORLD IS IN THE TITLE (2026-10-14, the owner: "this is not telling me which world it's in;
		I know it's my current one but a player doesn't"). The compact card (2026-10-12) hides the world
		row below to stay off the road, so the place rides on the title instead: "Thunderstorm in the
		City". The world's SHORT name (`WorldConfig.shortName`), so the longest pairing still fits the
		title's box at a readable size. ]]
	local place = WorldConfig.shortName(world)
	local title = string.format("%s in the %s", event.Name, place)
	self._noticeTitle.Text = if self._noticeKit then title else string.upper(title)

	--[[ The world on its own row rather than joined onto the title, which is where it was: "RUSH
		HOUR IN THE CITY" fits and "THUNDERSTORM IN THE FOREST MOUNTAINS" does not, and a title that
		is legible for four of the twenty-four combinations is not a title. Split, both halves are
		short enough to have a ceiling that holds — see `line`.

		"IN THE DESERT" and not "IN DESERT": every world in `WorldConfig` is named as a place and
		every one of them takes the article. A world named something that did not would want this
		line rewritten rather than the article dropped, because "IN CITY" reads as a bug. ]]
	self._noticeWorld.Text = string.format("IN THE %s", string.upper(WorldConfig.displayName(world)))
	self._noticeBlurb.Text = event.Blurb

	--[[ HOW LONG IS LEFT, which is what `endsAt` is on the wire for. It is nearly always the full
		window and would not be worth saying at all — but this same handler is what a player who joined
		two minutes into an event gets (`WeatherService`'s replay), and "RUSH HOUR" with fifty seconds
		left is a different proposition from "RUSH HOUR".

		IT IS ON THE CAP NOW rather than sharing the payoff's row behind a middot, which is what let
		the payoff have a pill to itself. A clock in a header is also simply where a clock goes. ]]
	local left = if type(endsAt) == "number" then endsAt - workspace:GetServerTimeNow() else 0
	self._noticeClock.Text = if left > 1
		then string.format("%d:%02d LEFT", math.floor(left / 60), math.floor(left % 60))
		else ""

	--[[ THE PAYOFF. The title is what the sky is doing and this is what it is worth, in the
		mutation's own colour so the line reads as the car it is about.

		AN EVENT WITH NO MUTATION HIDES THE LINE rather than printing "x1", which would read as a
		penalty. Nothing else on the card moves when it goes: the rows above it are positioned from
		the top, so the card simply has a space where the line would be. ]]
	local mutationKey = WeatherConfig.MutationOfEvent[event.Key]
	local mutation = mutationKey and WeatherConfig.mutationOf(mutationKey)
	self._noticePayoff.Visible = mutation ~= nil
	self._noticeBlurb.Visible = mutation == nil
	if mutation then
		self._noticePayoff.TextColor3 = if typeof(mutation.Color) == "Color3" then mutation.Color else NOTICE_TEXT
		self._noticePayoff.Text = string.format(
			"%s CAR VALUE %s",
			mutation.Name,
			WeatherConfig.formatMultiplier(WeatherConfig.valueMultiplierOf(mutationKey))
		)
	else
		self._noticePayoff.Text = ""
	end

	GameplayFeedback.play("EventStarted")
	self:_showNotice()
end

--[[ Slide it in, hold, slide it out. Re-arming an already-open card rather than stacking a second
	one, exactly as the near-miss toast does: two notices can only land together when an admin forces
	one over a scheduled one, and a pile of cards is the wrong answer to that.

	TOKENED, and cancelled rather than merely fenced. A hold still counting down from the previous
	notice would otherwise put this one away early. ]]
function WeatherController._showNotice(self)
	self._noticeToken += 1
	local token = self._noticeToken
	if self._noticeTween then
		self._noticeTween:Cancel()
		self._noticeTween = nil
	end

	self._notice.Enabled = true
	self._noticeCard.Position = self:_hiddenPosition()

	local tween = TweenService:Create(
		self._noticeCard,
		TweenInfo.new(NOTICE_IN, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		--- Shown IS a viewport fraction: it is a margin from the top edge, and a margin should grow
		--- with the screen. Hidden is not, for the reason the constants block gives.
		{ Position = UDim2.new(0.5, 0, NOTICE_SHOWN_Y, 0) }
	)
	self._noticeTween = tween
	tween:Play()

	task.delay(NOTICE_IN + NOTICE_HOLD, function()
		if self._noticeToken == token then
			self:_hideNotice()
		end
	end)
end

-- === Lighting ===============================================================

--[[ Everything the effect is about to overwrite, read off the live services.

	READ, NOT CONFIGURED. The lobby's authored sky is whatever the map has, and this game has four
	maps; a restore that wrote remembered constants back would put every world's sky back to world
	1's. Captured at the moment the effect goes up, so it is always the sky this player was actually
	looking at.

	The Atmosphere is the awkward one. A place may or may not have one authored, so either we adopt
	the existing instance and put its properties back, or we make one and destroy it — and which of
	those happened has to be remembered, which is what `owned` is. ]]
function WeatherController._capture(self)
	if self._saved then
		return
	end

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local owned = false
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = ATMOSPHERE_NAME
		--[[ Born at the CLEAR sky, not at the event's values. The tween below is what moves it, and
			an Atmosphere parented straight in at density 0.5 is a wall of fog appearing on one
			frame — which is the single most noticeable way this effect can look broken. ]]
		atmosphere.Density = 0
		atmosphere.Haze = 0
		atmosphere.Glare = 0
		atmosphere.Parent = Lighting
		owned = true
	end

	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = GRADE_NAME
	grade.TintColor = Color3.new(1, 1, 1)
	grade.Parent = Lighting

	self._saved = {
		clock = Lighting.ClockTime,
		ambient = Lighting.Ambient,
		outdoor = Lighting.OutdoorAmbient,
		brightness = Lighting.Brightness,
		fogColor = Lighting.FogColor,
		fogStart = Lighting.FogStart,
		fogEnd = Lighting.FogEnd,
		atmosphere = atmosphere,
		atmosphereOwned = owned,
		atmosphereWas = {
			Density = atmosphere.Density,
			Offset = atmosphere.Offset,
			Color = atmosphere.Color,
			Decay = atmosphere.Decay,
			Glare = atmosphere.Glare,
			Haze = atmosphere.Haze,
		},
		grade = grade,
	}
end

--- Put the sky back exactly as `_capture` found it, and take our own instances away. Instant rather
--- than tweened: the one caller is the end of a race, and the fade is already over the screen.
function WeatherController._restore(self)
	local saved = self._saved
	if not saved then
		return
	end
	self._saved = nil

	--[[ Cancelled BEFORE anything is written back. A tween still running owns these properties and
		would spend the next three seconds undoing the restore one frame at a time, which reads as
		the lobby slowly turning back into a storm. ]]
	self:_cancelTweens()

	Lighting.ClockTime = saved.clock
	Lighting.Ambient = saved.ambient
	Lighting.OutdoorAmbient = saved.outdoor
	Lighting.Brightness = saved.brightness
	Lighting.FogColor = saved.fogColor
	Lighting.FogStart = saved.fogStart
	Lighting.FogEnd = saved.fogEnd

	if saved.atmosphere and saved.atmosphere.Parent then
		if saved.atmosphereOwned then
			saved.atmosphere:Destroy()
		else
			for property, value in saved.atmosphereWas do
				(saved.atmosphere :: any)[property] = value
			end
		end
	end
	if saved.grade then
		saved.grade:Destroy()
	end
end

--- Stop every tween this file has running. Kept as a list rather than as fields, because the count
--- differs by event (an event with no Atmosphere block starts one fewer).
function WeatherController._cancelTweens(self)
	for _, tween in self._tweens do
		pcall(function()
			tween:Cancel()
		end)
	end
	table.clear(self._tweens)
end

--- Start one tween and remember it, so `_cancelTweens` can stop it.
function WeatherController._tween(self, instance: Instance, seconds: number, goal: { [string]: any })
	local tween = TweenService:Create(instance, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), goal)
	table.insert(self._tweens, tween)
	tween:Play()
end

--[[ Move Lighting towards this event's `Look`, or back to the captured sky with a nil event.

	EVERY FIELD IS OPTIONAL. An event with no `Clock` keeps the map's time of day, one with no `Fog`
	keeps the map's fog. That is what makes a new event a few lines in `WeatherConfig` rather than a
	full sky each time — and it is why each block is guarded rather than defaulted: a default would
	mean "unspecified" and "authored to the default" were the same thing, and the first designer to
	want a fogless storm would have no way to say so. ]]
function WeatherController._paint(self, event, seconds: number)
	local saved = self._saved
	if not saved then
		return
	end
	self:_cancelTweens()

	local look = event and event.Look or nil

	local goal = {
		ClockTime = if look and look.Clock then look.Clock else saved.clock,
		Ambient = if look and look.Ambient then look.Ambient else saved.ambient,
		OutdoorAmbient = if look and look.Outdoor then look.Outdoor else saved.outdoor,
		Brightness = if look and look.Brightness then look.Brightness else saved.brightness,
		FogColor = if look and look.Fog then look.Fog.Color else saved.fogColor,
		FogStart = if look and look.Fog then look.Fog.Start else saved.fogStart,
		FogEnd = if look and look.Fog then look.Fog.End else saved.fogEnd,
	}
	self:_tween(Lighting, seconds, goal)

	if saved.atmosphere and saved.atmosphere.Parent then
		local air = look and look.Atmosphere
		self:_tween(saved.atmosphere, seconds, {
			Density = if air then air.Density else saved.atmosphereWas.Density,
			Offset = if air then air.Offset else saved.atmosphereWas.Offset,
			Color = if air then air.Color else saved.atmosphereWas.Color,
			Decay = if air then air.Decay else saved.atmosphereWas.Decay,
			Glare = if air then air.Glare else saved.atmosphereWas.Glare,
			Haze = if air then air.Haze else saved.atmosphereWas.Haze,
		})
	end

	if saved.grade and saved.grade.Parent then
		self:_tween(saved.grade, seconds, {
			TintColor = if look and look.Tint then look.Tint else Color3.new(1, 1, 1),
		})
	end
end

--[[ Public (`DayNightController`): THE SKY THIS RUN WAS CAPTURED FROM HAS CHANGED. Take the new one
	as the base every `Look` composes over, and repaint onto it.

	WHAT IT IS FOR, in one line: a player who opens the settings screen mid-run and picks DAY. The
	gear is on the topbar during a race even though the rail and the pages are not, so that press is
	reachable exactly where `DayNightController` has stood down and cannot answer it. Before this the
	press was accepted, saved, and drawn on the settings screen while the sky did not move until the
	run was over, which is a screen saying "held at daytime" over a night road.

	IT REPLACES THE CAPTURE RATHER THAN WRITING LIGHTING, and that is the whole reason this is one
	function here instead of a truce between two files. `_capture` took the lobby's sky as the thing
	an event is composed over; this swaps in the sky the player has just asked for and runs the same
	`_paint` again. The event still wins every field it names, `_restore` still puts back exactly one
	saved table, and there is still only ever one file writing Lighting during a run.

	AN EVENT'S OWN `Clock` OUTRANKS THE PREFERENCE, deliberately. A Meteor Shower is authored at 23
	because that is what a meteor shower looks like, and a player picking DAY has changed their
	ordinary sky rather than overruled the weather. Their answer is waiting the moment it ends.

	`Density` AND `Offset` ARE NOT TOUCHED. They are the weather's dial (a storm is mostly density)
	and a time of day has no business moving them, which is the same split `DayNightController`
	makes when it reads them at boot and never writes them.

	Returns false when there is nothing captured to rebase, which is weather switched off or no run
	up. The caller writes Lighting itself in that case, and that is safe for the reason it is false:
	nothing here is holding it. ]]
function WeatherController.rebase(self, sky: {
	Clock: number,
	Ambient: Color3,
	Outdoor: Color3,
	Brightness: number,
	Atmosphere: { Color: Color3, Decay: Color3, Glare: number, Haze: number },
}, seconds: number?): boolean
	local saved = self._saved
	if not (saved and sky) then
		return false
	end

	saved.clock = sky.Clock
	saved.ambient = sky.Ambient
	saved.outdoor = sky.Outdoor
	saved.brightness = sky.Brightness

	local air = sky.Atmosphere
	if air and saved.atmosphereWas then
		saved.atmosphereWas.Color = air.Color
		saved.atmosphereWas.Decay = air.Decay
		saved.atmosphereWas.Glare = air.Glare
		saved.atmosphereWas.Haze = air.Haze
	end

	--- The event as it stands, so a rebase during a storm re-composes that storm over the new sky
	--- rather than clearing it. Nil is the ordinary case and paints straight to the new base.
	local event = if self._event then WeatherConfig.eventOf(self._event) else nil
	self:_paint(event, seconds or FADE_OUT)
	return true
end

-- === The falling stuff ======================================================

--[[ Build the particle box under the camera. One part, one emitter, rebuilt per event because every
	property on it comes from the event — there is nothing worth keeping between two of them.

	Returns nil for an event with no `Particles` (fog has none: there is nothing falling in fog, and
	inventing something would read as drizzle). ]]
function WeatherController._buildSky(self, event): BasePart?
	local spec = event and event.Particles
	local camera = workspace.CurrentCamera
	if not (spec and camera) then
		return nil
	end

	local box = Instance.new("Part")
	box.Name = SKY_NAME
	box.Anchored = true
	box.Transparency = 1
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.CastShadow = false
	box.Locked = true
	box.Size = Vector3.new(BOX.Width, BOX.Height, BOX.Depth)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Fall"
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	--[[ DOWN, and left in world space. `EmissionDirection.Bottom` is what makes rain fall; the
		unlocked particles are what make you drive THROUGH it rather than carry it (see the header).
		`Orientation = VelocityParallel` plus `Squash` is what turns a round dot into a streak — the
		same trick the wind streaks use, and the reason `Squash` is a per-event number: it is the
		difference between a raindrop, a meteor and a grain of sand. ]]
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.LockedToPart = false
	emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	emitter.Squash = NumberSequence.new(spec.Squash or 1)
	emitter.Rate = spec.Rate or 100
	emitter.Speed = NumberRange.new(spec.Speed or 100)
	emitter.Lifetime = NumberRange.new(spec.Lifetime or 0.6)
	emitter.Size = NumberSequence.new(spec.Size or 1)
	emitter.Color = ColorSequence.new(spec.Color or Color3.new(1, 1, 1))
	emitter.Transparency = NumberSequence.new(spec.Transparency or 0.4)
	emitter.LightEmission = spec.Glow or 0
	emitter.LightInfluence = 0
	--[[ `Drag` is the crosswind, and it is the one field that is not literally a Roblox property: it
		is applied as sideways ACCELERATION rather than as drag, because what a designer wants from
		"sandstorm, drag 3" is grit blowing across the road, not grit slowing down. Scaled off the
		fall speed so a fast event and a slow one blow at proportionate angles. ]]
	local sideways = (spec.Drag or 0) * (spec.Speed or 100) * 0.25
	emitter.Acceleration = Vector3.new(sideways, 0, 0)
	emitter.SpreadAngle = Vector2.new(6, 6)
	emitter.Parent = box

	box.Parent = camera
	return box
end

--- Follow the camera. One CFrame write a frame, which is what the whole `_step` connection exists
--- for — everything else about an event is set once when it starts.
function WeatherController._step(self)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local cf = camera.CFrame
	--[[ Ahead of the camera and above it, in the direction it is LOOKING but flattened. Following the
		full look vector would tip the box when the chase camera pitches, which swings the whole
		rainfall off vertical every time the car crests a rise. ]]
	local flat = flatten(cf.LookVector)
	if self._sky and self._sky.Parent then
		self._sky.CFrame = CFrame.new(cf.Position + flat * BOX.Ahead + Vector3.yAxis * BOX.Lift)
	end
	if self._vfx then
		self:_stepVfx(cf.Position, flat)
	end
	self:_stepChip()
end

-- === The event chip (`WeatherConfig.Chip`) =================================

--- The chip's pixels wide per pixel high: icon on the left, three lines of type beside it.
local CHIP_ASPECT = 5

--[[ Built once, on the first event of the session; hidden rather than destroyed between them.

	THE KIT'S CARD (2026-10-17, Dylan: the chip was "not consistent with the new template"). WAS a flat
	dark box with a pixel rim in the event's colour and near-black outlines on the type. IS
	`ArcadeKit.card` in the kit's blue, the face the lobby's `WeatherNotice` wears, with the kit's white
	outlined type and its gold for the clock. The event's colour lives in the icon, as on the notice:
	the mutation colours are pale blues that would vanish on a blue face. ]]
function WeatherController._buildChip(self)
	local cfg = WeatherConfig.Chip
	local gui = Instance.new("ScreenGui")
	gui.Name = "WeatherEventChip"
	gui.ResetOnSpawn = false
	--- Measured from BELOW the Roblox top bar, so a short window or a phone cannot tuck it under it.
	gui.IgnoreGuiInset = false
	--- Over the run's own HUD screens, which used to draw across it (`WeatherConfig.Chip`).
	gui.DisplayOrder = 20
	--- The kit's parts are layered for Sibling; a new ScreenGui defaults to Global.
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0, 0)
	holder.Position = UDim2.fromScale(cfg.Left, cfg.Top)
	holder.Size = UDim2.fromScale(cfg.Height * CHIP_ASPECT, cfg.Height)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = CHIP_ASPECT
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = holder
	local face = ArcadeKit.card(holder, { aspect = CHIP_ASPECT, face = ArcadeKit.Faces.Blue, sunray = false })
	local icon = Instance.new("ImageLabel")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.fromScale(0.03, 0.5)
	icon.Size = UDim2.fromScale(0.16, 0.8)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 4
	icon.Parent = face
	local function text(y: number, h: number, colour: Color3): TextLabel
		local label = ArcadeKit.text(face, 0.21, y, 0.75, h, colour, true)
		label.TextXAlignment = Enum.TextXAlignment.Left
		return label
	end
	local title = text(0.07, 0.36, ArcadeKit.White)
	local line = text(0.44, 0.25, ArcadeKit.White)
	local clock = text(0.7, 0.22, ArcadeKit.Gold)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self._chip = { gui = gui, holder = holder, icon = icon, title = title, line = line, clock = clock, shownSecond = -1 }
end

--- Public (the top-left stack: `LuckProgressController`, `PoliceHudController`): the event chip's bottom
--- edge in `AbsolutePosition` space while it is up, else nil, so the cards under it can sit below it.
function WeatherController.chipBottom(self): number?
	local chip = self._chip
	if not (chip and chip.gui.Enabled and chip.holder.AbsoluteSize.Y > 0) then
		return nil
	end
	return chip.holder.AbsolutePosition.Y + chip.holder.AbsoluteSize.Y
end

--[[ Point the chip at the event now on the road, or hide it (`key` nil). Called from `_switch`, the
	one place the sky changes, so the chip and the weather cannot disagree. ]]
function WeatherController._setChip(self, key: string?)
	local cfg = WeatherConfig.Chip
	local event = WeatherConfig.eventOf(key)
	local mutation = event and WeatherConfig.mutationOf(event.Mutation)
	if not (cfg.Enabled and event and mutation) then
		if self._chip then
			self._chip.gui.Enabled = false
		end
		return
	end
	if not self._chip then
		self:_buildChip()
	end
	local chip = self._chip
	local icon = WeatherConfig.iconOf(key)
	chip.icon.Image = if icon then UIAssets.url(icon) else ""
	chip.icon.Visible = icon ~= nil
	chip.title.Text = string.upper(event.Name)
	local chance = math.round((tonumber(mutation.EventChance) or 0) * 100)
	chip.line.Text = string.format(cfg.Line, chance, mutation.Name, tostring(WeatherConfig.valueMultiplierOf(mutation.Key)))
	chip.shownSecond = -1
	chip.gui.Enabled = true
end

--- The clock, once a second. The deadline is the schedule's own (`_eventEndsAt`, from `_evaluate`).
function WeatherController._stepChip(self)
	local chip = self._chip
	if not (chip and chip.gui.Enabled and self._eventEndsAt) then
		return
	end
	local left = math.max(0, math.ceil(self._eventEndsAt - workspace:GetServerTimeNow()))
	if left ~= chip.shownSecond then
		chip.shownSecond = left
		chip.clock.Text = string.format(WeatherConfig.Chip.Ends, left // 60, left % 60)
	end
end

-- === The library look ======================================================

--[[ Build an event's `Vfx`: one carrier part per layer, and the bolt and meteor rigs if it has them.
	Everything goes into one Folder under the camera, so `_clearSky` is one Destroy.

	The carriers are placed once before the folder is parented, so the first frame of emission comes
	out where the box belongs rather than at the world origin. ]]
function WeatherController._buildVfx(self, vfx: any): Folder?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end

	local folder = Instance.new("Folder")
	folder.Name = VFX_NAME

	for index, spec in (if type(vfx.Layers) == "table" then vfx.Layers else {}) do
		if index > MAX_LAYERS then
			break
		end
		local box = boxOf(spec)
		local part = carrier("Layer" .. index, Vector3.new(box.Width, math.max(box.Height, 0.05), box.Depth))
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Emitter"
		dressLayer(emitter, spec)
		emitter.Parent = part
		part.Parent = folder
		table.insert(self._vfxLayers, {
			part = part,
			emitter = emitter,
			box = box,
			ground = spec.Ground == true,
			prewarm = if type(spec.Prewarm) == "number" then math.clamp(spec.Prewarm, 0, 60) else 0,
		})
	end

	if type(vfx.Bolts) == "table" then
		self._boltRig = self:_buildBolt(vfx.Bolts, folder)
	end
	if type(vfx.Meteors) == "table" then
		self:_buildMeteors(vfx.Meteors, folder)
	end

	self._vfx = folder
	self:_stepVfx(camera.CFrame.Position, flatten(camera.CFrame.LookVector))
	folder.Parent = camera
	-- Only once it is in the world: an emitter with no place in it has nowhere to emit from.
	for _, layer in self._vfxLayers do
		if layer.prewarm > 0 then
			layer.emitter:Emit(layer.prewarm)
		end
	end
	return folder
end

--- Follow the camera, and move whatever meteors are in the air. One CFrame write per layer.
function WeatherController._stepVfx(self, position: Vector3, flat: Vector3)
	local ground: number? = nil
	for _, layer in self._vfxLayers do
		local box = layer.box
		local at = position + flat * box.Ahead
		local y
		if layer.ground then
			ground = ground or self:_groundY(position)
			y = (ground :: number) + box.Lift + box.Height * 0.5
		else
			y = position.Y + box.Lift
		end
		layer.part.CFrame = CFrame.new(at.X, y, at.Z)
	end
	if #self._meteors > 0 then
		self:_flyMeteors()
	end
	self:_stepBolt()
end

--[[ The height of the road under the camera, for the layers that stand on it.

	IN A RACE IT IS THE DECK, read from `RoadController`: constant for the whole run, already on this
	player's storey, and not fooled by a traffic car's roof passing underneath the way a ray would be.

	Anywhere else (a sky staged in the lobby, or the first frames of a run while the road is still
	being laid) it is whatever a ray straight down finds, asked a few times a second rather than every
	frame. Nothing below means a flat guess under the camera. ]]
function WeatherController._groundY(self, from: Vector3): number
	local road = self._road
	if road and road:isWorldReady() then
		local info = road:getRoadInfo()
		if info and type(info.deckY) == "number" then
			return info.deckY
		end
	end

	local now = os.clock()
	if self._groundCache and now < self._groundAt then
		return self._groundCache
	end
	self._groundAt = now + GROUND_EVERY

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace.CurrentCamera, Players.LocalPlayer.Character }
	local hit = workspace:Raycast(from, Vector3.new(0, -500, 0), params)
	self._groundCache = if hit then hit.Position.Y else from.Y - 10
	return self._groundCache
end

--[[ The thunderstorm's bolt rig, built from BEAMS rather than a sprite.

	The library's bolt sheet was tried first and it is the wrong tool here: it is a soft, smoky
	drawing, and at four hundred studs through a storm's atmosphere it read as a white plume. A bolt
	is a hard line with kinks in it, and a chain of beams between attachments is exactly that. It is
	the same construction as the VFXer plugin's Lightning Beam add-on (A to B attachments), which
	cannot be called from a game script, so it is rebuilt here.

	One carrier at the world origin holds every attachment, so an attachment's `Position` IS its
	world position. The main channel is `Segments` beams, each branch `BRANCH_STEPS` more, and the
	whole pool is built once per event and re-laid on every strike. The glow is a particle on its own
	carrier: the cloud lighting up around the top of the channel. ]]
local BRANCH_STEPS = 4
local MAX_BRANCHES = 3

function WeatherController._buildBolt(self, spec: any, folder: Folder)
	local part = carrier("Bolt", Vector3.one)
	part.CFrame = CFrame.identity

	local width = spec.Width or 3
	local color = ColorSequence.new(if typeof(spec.Color) == "Color3" then spec.Color else Color3.new(1, 1, 1))
	local function chain(name: string, steps: number, from: number, to: number)
		local points, beams = table.create(steps + 1), table.create(steps)
		for i = 1, steps + 1 do
			local attachment = Instance.new("Attachment")
			attachment.Name = name .. i
			attachment.Parent = part
			points[i] = attachment
		end
		for i = 1, steps do
			local beam = Instance.new("Beam")
			beam.Name = name .. "Beam" .. i
			beam.Attachment0 = points[i]
			beam.Attachment1 = points[i + 1]
			beam.FaceCamera = true
			beam.Segments = 1
			-- Tapering from `from` to `to` along the chain, so a channel thins toward the ground and a
			-- branch toward its tip.
			beam.Width0 = width * (from + (to - from) * (i - 1) / steps)
			beam.Width1 = width * (from + (to - from) * i / steps)
			beam.Color = color
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Brightness = spec.Brightness or 5
			beam.Transparency = NumberSequence.new(1)
			beam.Enabled = false
			beam.Parent = part
			beams[i] = beam
		end
		return { points = points, beams = beams }
	end

	local segments = math.clamp(spec.Segments or 12, 4, 24)
	local main = chain("Main", segments, 1, 0.6)
	local branches = {}
	for index = 1, MAX_BRANCHES do
		branches[index] = chain("Branch" .. index, BRANCH_STEPS, 0.55, 0.15)
	end
	part.Parent = folder

	local glowPart, glow = nil, nil
	if type(spec.Glow) == "table" then
		glowPart = carrier("BoltGlow", Vector3.one)
		glow = Instance.new("ParticleEmitter")
		glow.Name = "Glow"
		dressLayer(glow, {
			Texture = spec.Glow.Texture,
			Lifetime = spec.Glow.Lifetime or 0.35,
			Size = spec.Glow.Size or 300,
			Color = spec.Glow.Color,
			Transparency = { spec.Glow.Transparency or 0.5, 1 },
			Glow = 1,
			Speed = 0,
			Spread = 0,
		}, Enum.ParticleOrientation.FacingCamera)
		glow.Enabled = false
		glow.Parent = glowPart
		glowPart.Parent = folder
	end

	return {
		spec = spec,
		part = part,
		segments = segments,
		main = main,
		branches = branches,
		lit = 0, -- how many branches the current strike uses
		t0 = nil :: number?, -- when the current strike landed; nil when nothing is on screen
		alpha = 1,
		glowPart = glowPart,
		glow = glow,
	}
end

--[[ Draw one bolt, somewhere down the road. Called by `_strike`, so it lands on the same frame as
	the flash. A no-op with no rig, which is every event but the thunderstorm and the thunderstorm
	with `EventVfx` off: that sky is the flash alone, as it shipped.

	THE CHANNEL IS A RANDOM WALK. Each point down from the cloud strays a little further sideways
	than the one above it, clamped to `Wander` of the bolt's height, which is what gives a stroke
	its jagged, leaning shape instead of the zigzag of evenly alternating kinks. The branches split
	off the upper part of it and die out in the air. `_stepBolt` then flickers the whole thing and
	puts it away. ]]
function WeatherController._bolt(self)
	local rig = self._boltRig
	local camera = workspace.CurrentCamera
	if not (rig and camera and rig.part.Parent) then
		return
	end
	local spec = rig.spec
	local rng = self._rng
	local cf = camera.CFrame
	local flat = flatten(cf.LookVector)
	local side = flat:Cross(Vector3.yAxis)
	local down = -Vector3.yAxis
	local ground = self:_groundY(cf.Position)
	local height = roll(rng, spec.Height, 320)

	local foot = Vector3.new(cf.Position.X, ground, cf.Position.Z)
		+ flat * roll(rng, spec.Distance, 440)
		+ side * rng:NextNumber(-1, 1) * (spec.Across or 300)
	local top = foot + Vector3.yAxis * height

	local segments = rig.segments
	local step = height / segments
	local limit = (spec.Wander or 0.16) * height
	local drift = Vector3.zero
	local points = rig.main.points
	points[1].Position = top
	for i = 1, segments do
		drift += side * rng:NextNumber(-1, 1) * step * 0.7 + flat * rng:NextNumber(-1, 1) * step * 0.3
		if drift.Magnitude > limit then
			drift = drift.Unit * limit
		end
		points[i + 1].Position = top:Lerp(foot, i / segments) + drift
	end

	local lit = math.floor(roll(rng, spec.Branches, 2) + 0.5)
	rig.lit = math.clamp(lit, 0, MAX_BRANCHES)
	for index, branch in rig.branches do
		if index <= rig.lit then
			local at = points[rng:NextInteger(2, math.max(2, math.floor(segments * 0.6)))].Position
			local lean = side * (if rng:NextNumber() < 0.5 then -1 else 1)
			for s, attachment in branch.points do
				attachment.Position = at
				if s <= BRANCH_STEPS then
					at += (lean * rng:NextNumber(0.5, 1) + down * rng:NextNumber(0.6, 1.2)).Unit * step * 0.8
				end
			end
		end
		for _, beam in branch.beams do
			beam.Enabled = index <= rig.lit
		end
	end
	for _, beam in rig.main.beams do
		beam.Enabled = true
	end

	rig.t0 = os.clock()
	rig.alpha = -1 -- forces the first `_stepBolt` write
	self:_stepBolt()

	if rig.glow then
		rig.glowPart.CFrame = CFrame.new(top)
		rig.glow:Emit(1)
	end
end

--[[ Flicker the bolt on screen along `BOLT_FLICKER`, and put it away at the end of its life. Called
	every frame by `_stepVfx`; one comparison when nothing is on screen. Branches run a little fainter
	than the channel, as they do in a photograph. ]]
function WeatherController._stepBolt(self)
	local rig = self._boltRig
	if not (rig and rig.t0) then
		return
	end
	local t = (os.clock() - rig.t0) / (rig.spec.Lifetime or 0.4)
	if t >= 1 then
		rig.t0 = nil
		for _, beam in rig.main.beams do
			beam.Enabled = false
		end
		for _, branch in rig.branches do
			for _, beam in branch.beams do
				beam.Enabled = false
			end
		end
		return
	end

	local alpha = sampleSequence(BOLT_FLICKER, t)
	if math.abs(alpha - rig.alpha) < 0.02 then
		return
	end
	rig.alpha = alpha
	local channel = NumberSequence.new(alpha)
	for _, beam in rig.main.beams do
		beam.Transparency = channel
	end
	local fainter = NumberSequence.new(math.min(1, alpha + 0.3))
	for index = 1, rig.lit do
		for _, beam in rig.branches[index].beams do
			beam.Transparency = fainter
		end
	end
end

--[[ The meteor shower's pool: `Pool` rigs built once for the event and flown over and over, each a
	carrier with a trail for the tail, a head emitter pinned to it and a smoke emitter that leaves its
	puffs hanging in the sky behind. One shared blast rig goes up where a meteor comes down. ]]
function WeatherController._buildMeteors(self, spec: any, folder: Folder)
	self._meteorSpec = spec
	local tail = if type(spec.Tail) == "table" then spec.Tail else {}
	local half = (tail.Width or 6) * 0.5
	local tailStart = if typeof(tail.Color) == "Color3" then tail.Color else Color3.fromRGB(255, 170, 80)
	local tailEnd = if typeof(tail.ColorEnd) == "Color3" then tail.ColorEnd else tailStart

	for index = 1, math.clamp(spec.Pool or 5, 1, 12) do
		local part = carrier("Meteor" .. index, Vector3.one)

		local top = Instance.new("Attachment")
		top.Name = "TailTop"
		top.Position = Vector3.new(0, half, 0)
		top.Parent = part
		local bottom = Instance.new("Attachment")
		bottom.Name = "TailBottom"
		bottom.Position = Vector3.new(0, -half, 0)
		bottom.Parent = part

		local trail = Instance.new("Trail")
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.FaceCamera = true
		trail.Lifetime = tail.Lifetime or 0.5
		trail.Color = ColorSequence.new(tailStart, tailEnd)
		trail.Transparency = NumberSequence.new(0, 1)
		trail.WidthScale = NumberSequence.new(1, 0.15)
		trail.LightEmission = 1
		trail.LightInfluence = 0
		trail.Brightness = tail.Brightness or 1
		trail.Enabled = false
		trail.Parent = part

		local head = Instance.new("ParticleEmitter")
		head.Name = "Head"
		dressLayer(head, if type(spec.Head) == "table" then spec.Head else {}, Enum.ParticleOrientation.FacingCamera)
		-- Pinned, so the head stays a ball of fire at the front instead of smearing into a second tail.
		head.LockedToPart = true
		head.Enabled = false
		head.Parent = part

		local smoke = Instance.new("ParticleEmitter")
		smoke.Name = "Smoke"
		dressLayer(smoke, if type(spec.Smoke) == "table" then spec.Smoke else {}, Enum.ParticleOrientation.FacingCamera)
		smoke.Enabled = false
		smoke.Parent = part

		part.Parent = folder
		table.insert(self._meteors, { part = part, trail = trail, head = head, smoke = smoke, flight = nil, freeAt = 0 })
	end

	if type(spec.Blast) == "table" then
		local part = carrier("Blast", Vector3.one)
		local blast = Instance.new("ParticleEmitter")
		blast.Name = "Blast"
		dressLayer(blast, spec.Blast, Enum.ParticleOrientation.FacingCameraWorldUp)
		blast.Enabled = false
		blast.Parent = part
		--[[ The flash that goes with it: a big additive glow for the first fraction of a second. The
			fireball sheet starts small and much of it lands behind the roadside buildings; the flash
			is what says "that one came down" over the rooftops. ]]
		local flash = nil
		if type(spec.Blast.Flash) == "table" then
			flash = Instance.new("ParticleEmitter")
			flash.Name = "Flash"
			dressLayer(flash, spec.Blast.Flash, Enum.ParticleOrientation.FacingCamera)
			flash.Enabled = false
			flash.Parent = part
		end
		part.Parent = folder
		self._blast = { part = part, emitter = blast, flash = flash, spec = spec.Blast }
	end
end

--[[ Arm the next launch. Chained `task.delay`s fenced by `_token`, exactly as `_armLightning` is and
	for its reasons: a launch that outlives its event must not fire into the next one. ]]
function WeatherController._armMeteors(self)
	local spec = self._meteorSpec
	if not spec then
		return
	end
	local token = self._token
	task.delay(roll(self._rng, spec.Every, 1.2), function()
		if self._token ~= token then
			return
		end
		self:_launchMeteor()
		self:_armMeteors()
	end)
end

--[[ Send one meteor across the sky, if a rig is free.

	THEY ALL FALL THE SAME WAY. A real shower streams out of one point in the sky (the radiant), so
	every meteor in it travels roughly parallel to every other; random directions read as fireworks.
	`_meteorSide` is rolled once per event and each launch starts on the far side of the view from
	where it is heading, so it crosses the frame rather than leaving it.

	A meteor that burns out flies for `Flight` seconds. One that lands flies until it reaches the
	road's height, which is the horizon at this distance, and `_endMeteor` puts the blast there. ]]
function WeatherController._launchMeteor(self)
	local spec = self._meteorSpec
	local camera = workspace.CurrentCamera
	if not (spec and camera) then
		return
	end
	local now = os.clock()
	local rig = nil
	for _, candidate in self._meteors do
		if not candidate.flight and now >= candidate.freeAt then
			rig = candidate
			break
		end
	end
	if not rig then
		return
	end

	local rng = self._rng
	local cf = camera.CFrame
	local flat = flatten(cf.LookVector)
	local side = flat:Cross(Vector3.yAxis)
	local heading = self._meteorSide
	local ground = self:_groundY(cf.Position)

	local height = roll(rng, spec.Height, 380)
	local start = Vector3.new(cf.Position.X, ground + height, cf.Position.Z)
		+ flat * roll(rng, spec.Distance, 600)
		- side * heading * rng:NextNumber(-0.3, 1) * (spec.Across or 400)

	local dive = math.rad(roll(rng, spec.Dive, 30))
	local direction = (side * heading * math.cos(dive) - Vector3.yAxis * math.sin(dive) + flat * rng:NextNumber(-0.12, 0.2)).Unit
	local speed = roll(rng, spec.Speed, 360)
	local impact = rng:NextNumber() < (spec.Impact or 0)
	local duration = if impact
		then height / math.max(-direction.Y * speed, 1)
		else roll(rng, spec.Flight, 1.3)

	rig.flight = {
		from = start,
		to = start + direction * speed * duration,
		t0 = now,
		duration = duration,
		impact = impact,
	}
	rig.part.CFrame = CFrame.lookAt(start, rig.flight.to)
	--- Cleared AFTER the move, so the tail does not draw a line from where this rig last landed.
	rig.trail:Clear()
	rig.trail.Enabled = true
	rig.head.Enabled = true
	rig.smoke.Enabled = true
end

--- Move every meteor in the air along its path, and finish the ones that have arrived.
function WeatherController._flyMeteors(self)
	local now = os.clock()
	for _, rig in self._meteors do
		local flight = rig.flight
		if flight then
			local t = (now - flight.t0) / flight.duration
			if t >= 1 then
				self:_endMeteor(rig, now)
			else
				rig.part.CFrame = CFrame.lookAt(flight.from:Lerp(flight.to, t), flight.to)
			end
		elseif rig.trail.Enabled and now >= rig.freeAt then
			rig.trail.Enabled = false
		end
	end
end

--[[ A meteor has burnt out or come down. The rig parks where it ended and stops emitting, and its
	tail drains away behind it over the trail's own lifetime before it can fly again. A landing also
	sets off the blast, lifted so the fireball sits on the horizon rather than half under it. ]]
function WeatherController._endMeteor(self, rig: any, now: number)
	local flight = rig.flight
	rig.flight = nil
	rig.part.CFrame = CFrame.new(flight.to)
	rig.head.Enabled = false
	rig.smoke.Enabled = false
	rig.freeAt = now + rig.trail.Lifetime + 0.05

	local blast = self._blast
	if flight.impact and blast then
		-- The size a sheet reaches, lifting the fireball so it sits on the horizon, not half under it.
		local size = sequenceOf(blast.spec.Size, 120).Keypoints
		blast.part.CFrame = CFrame.new(flight.to + Vector3.yAxis * size[#size].Value * 0.3)
		blast.emitter:Emit(1)
		if blast.flash then
			blast.flash:Emit(1)
		end
	end
end

--[[ The road has been rebased (`RoadController.onWorldShift`), and the camera with it. The layers
	follow the camera on their own next frame; a meteor is flying a path in world space, so it is
	carried by the same shift, and its tail cleared so the jump does not draw across the sky. ]]
function WeatherController._shiftVfx(self, shift: Vector3)
	for _, rig in self._meteors do
		local flight = rig.flight
		if flight then
			flight.from += shift
			flight.to += shift
		end
		rig.part.CFrame += shift
		rig.trail:Clear()
	end
end

--- Take the current sky's particles down, whichever build put them up.
function WeatherController._clearSky(self)
	if self._sky then
		self._sky:Destroy()
		self._sky = nil
	end
	if self._vfx then
		self._vfx:Destroy()
		self._vfx = nil
	end
	table.clear(self._vfxLayers)
	table.clear(self._meteors)
	self._meteorSpec = nil
	self._boltRig = nil
	self._blast = nil
end

--[[ Put an event's particles up: its `Vfx` while `WeatherConfig.EventVfx` is on and it has one,
	and otherwise the original box, built exactly as it always was. ]]
function WeatherController._raiseSky(self, event)
	local vfx = WeatherConfig.vfxOf(event)
	if vfx then
		self._meteorSide = if self._rng:NextNumber() < 0.5 then -1 else 1
		self._vfx = self:_buildVfx(vfx)
	else
		self._sky = self:_buildSky(event)
	end
end

-- === Lightning ==============================================================

--[[ The thunderstorm's flash: Brightness slammed up for a few frames and eased back down.

	A FLASH AND NOT A BOLT. A bolt needs art, needs to be somewhere specific, and would be behind the
	camera half the time; the flash is what a player actually registers, and it is three numbers.

	It writes `Lighting.Brightness` directly rather than through `_tween`, and that is deliberate: the
	strike has to be able to interrupt itself and the sky tween has to be able to interrupt IT. The
	value it eases back to is read from the event rather than from the live property, so a strike
	landing while the sky is still fading in cannot leave the brightness stranded at its flash value. ]]
function WeatherController._strike(self)
	local event = self._event and WeatherConfig.eventOf(self._event)
	local spec = event and event.Lightning
	if not (spec and self._saved) then
		return
	end
	local base = (event.Look and event.Look.Brightness) or self._saved.brightness

	Lighting.Brightness = spec.Brightness
	-- The bolt the flash came from, when the library look is up. Nothing otherwise.
	self:_bolt()
	task.delay(spec.Hold, function()
		-- The event may have ended, or the race, in the few frames the flash was up. Either way the
		-- ease-down is wrong and whatever replaced it is right.
		if self._event ~= (event and event.Key) or not self._saved then
			return
		end
		TweenService:Create(
			Lighting,
			TweenInfo.new(spec.Fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Brightness = base }
		):Play()
	end)
end

--- Arm the next strike, if this event has any. A chained `task.delay` rather than an accumulator on
--- the frame loop, for `TipsService._loop`'s reason: this fires every few SECONDS, and sixty
--- comparisons a second to measure that is work to answer a question a sleeping thread answers free.
function WeatherController._armLightning(self)
	local event = self._event and WeatherConfig.eventOf(self._event)
	local spec = event and event.Lightning
	if not spec then
		return
	end

	local token = self._token
	task.delay(self._rng:NextNumber(spec.Every[1], spec.Every[2]), function()
		--[[ THE TOKEN IS THE WHOLE GUARD. A sleeping strike outlives the event that armed it, the
			race that armed that, and — if the player pressed Play again quickly — most of the next
			one. Comparing the token rather than a boolean is what makes a stale thread from two
			races ago unable to flash the sky of this one. ]]
		if self._token ~= token then
			return
		end
		self:_strike()
		self:_armLightning()
	end)
end

-- === Deciding =============================================================

--[[ What the weather in this player's race world is right now, and put the sky where it belongs.

	Called on race start, whenever the schedule attribute changes, and on a slow poll — the poll only
	because an event ENDS on a deadline that the attribute write announces, and a client that missed
	that write would otherwise stay in a storm forever. One string compare a second.

	`seconds` is how long the change should take. A race starting into an existing storm gets 0 —
	the weather was already there before the player arrived, and fading it in would say otherwise. ]]
function WeatherController._evaluate(self, seconds: number?)
	if not (self._racing and WeatherConfig.Enabled) then
		return
	end

	local state = WeatherConfig.decode(workspace:GetAttribute(WeatherConfig.Attribute))
	local entry = state[self._world or 0]
	local key = if entry and workspace:GetServerTimeNow() < entry.endsAt then entry.event else nil
	if self._tutorialRun then
		key = nil
	end
	--- The event chip's clock (`_stepChip`) counts down to this.
	self._eventEndsAt = if key and entry then entry.endsAt else nil
	if key == self._event then
		return
	end
	self:_switch(key, seconds)
end

--- Change the sky to `key` (nil for clear). `_evaluate` decides WHEN; this is the change itself.
function WeatherController._switch(self, key: string?, seconds: number?)
	self._event = key
	--[[ Bumped on EVERY change, including into and out of clear. It is what fences the lightning
		threads — see `_armLightning` — and a token that only moved when an event started would let a
		strike from the storm before last land during this one. The meteor launches ride it too. ]]
	self._token += 1

	self:_clearSky()
	self:_setChip(key)

	local event = WeatherConfig.eventOf(key)
	if not event then
		self:_paint(nil, seconds or FADE_OUT)
		return
	end

	self:_paint(event, seconds or FADE_IN)
	self:_raiseSky(event)
	self:_armLightning()
	self:_armMeteors()
end

-- === Lifecycle ==============================================================

function WeatherController._onRaceStart(self, world: number?)
	self:_onRaceEnd() -- idempotent; a race that started without the last one ending must not stack

	if not WeatherConfig.Enabled then
		return
	end
	--[[ The world the run was BUILT from, not the one on the player attribute — the same argument
		RoadController and TrafficController make about the same value. The sky, the road and the cars
		on it all have to have come from one answer. ]]
	self._world = WorldConfig.resolve(world)
	self._racing = true
	-- A lobby announcement must not survive race entry or a lazy template load into the run.
	self._noticeToken += 1
	if self._noticeTween then
		self._noticeTween:Cancel()
		self._noticeTween = nil
	end
	if self._notice then self._notice.Enabled = false end
	-- The tutorial's run always drives under a clear sky (`TutorialConfig.isTutorialRun`), latched here.
	self._tutorialRun = TutorialConfig.isTutorialRun(Players.LocalPlayer:GetAttribute(TutorialConfig.StepAttribute))
	self:_capture()

	--[[ Zero, not `FADE_IN`. A run that starts into a storm that has been running for two minutes
		should open IN it; fading the sky in over the first three seconds would tell the player the
		weather arrived with them. A storm that starts mid-race gets the fade, because then it did. ]]
	self:_evaluate(0)

	self._attrConn = workspace:GetAttributeChangedSignal(WeatherConfig.Attribute):Connect(function()
		self:_evaluate()
	end)
	self._stepConn = RunService.RenderStepped:Connect(function()
		self:_step()
	end)
	-- A rebase moves the road and the camera; meteors in flight are carried with them (`_shiftVfx`).
	if self._road then
		self._unshift = self._road:onWorldShift(function(shift: Vector3)
			self:_shiftVfx(shift)
		end)
	end
	self._pollAt = os.clock() + 1
	self._pollConn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now >= self._pollAt then
			self._pollAt = now + 1
			self:_evaluate()
		end
	end)
end

function WeatherController._onRaceEnd(self)
	self._racing = false
	self._staged = false
	self._world = nil
	self._event = nil
	self._eventEndsAt = nil
	self._token += 1
	--- The run's event chip goes with the run (it is cleared here, not through `_switch`).
	self:_setChip(nil)

	for _, field in { "_attrConn", "_stepConn", "_pollConn" } do
		local conn = (self :: any)[field]
		if conn then
			conn:Disconnect();
			(self :: any)[field] = nil
		end
	end
	if self._unshift then
		self._unshift()
		self._unshift = nil
	end
	self:_clearSky()
	self:_restore()
end

--[[ PUBLIC (ObstacleController): the key of the event this client's race is being driven in right
	now, or nil for a clear sky or no race. It is the very answer the sky is drawn from, the tutorial's
	always-clear run included, so the road the rain lays puddles on can never be wet under a dry sky
	or dry under a wet one. ]]
function WeatherController.currentEvent(self): string?
	return if self._racing then self._event else nil
end

-- === The panel =============================================================
--[[ Three functions the F2 admin panel's Weather tab calls, and nothing else does.

	The problem they solve: an event is only DRAWN during a race (`_racing`), because that is the
	only place the sky belongs — so an admin who forces a thunderstorm and then stands in the lobby
	watching for it sees a clear day and concludes the feature is broken. Staging puts the race's
	sky up without a race.

	They are the race's own entry points and not a second implementation of them, which is the whole
	reason this is three lines rather than a preview mode: what an admin stages is exactly what a
	player gets, including the fade, the particles, the lightning and the tear-down.

	A REAL RACE OUTRANKS A STAGED SKY. `_onRaceStart` opens by ending whatever was up, so a run that
	starts while a preview is staged takes the sky over cleanly, and `_staged` goes down with it —
	which is what stops the panel then offering to "unstage" a sky it no longer owns. ]]

--- Put `world`'s current sky up outside a race. Idempotent; re-staging re-reads the schedule.
function WeatherController.debugStage(self, world: unknown): boolean
	--[[ A running race owns the sky and this must not take it: `_onRaceStart` would re-open the
		effect on whichever world the panel happens to have selected, which mid-run is a player
		watching the wrong weather. Re-staging an already-staged sky is fine and is how the panel
		switches worlds. ]]
	if not WeatherConfig.Enabled or (self._racing and not self._staged) then
		return false
	end
	self:_onRaceStart(WorldConfig.resolve(world))
	self._staged = true
	return true
end

--- Take a staged sky down. Does nothing during a real race, whose sky is not ours to end.
function WeatherController.debugUnstage(self)
	if not self._staged then
		return
	end
	self:_onRaceEnd()
end

--[[ Rebuild the particles of whatever sky is up, keeping the event and the Lighting as they are.
	The panel's `EventVfx` switch calls this after flipping the flag, so the library look and the
	original can be compared on the same storm without waiting for the next one. False when no sky
	is up to rebuild. ]]
function WeatherController.debugRefresh(self): boolean
	if not self._racing then
		return false
	end
	local event = WeatherConfig.eventOf(self._event)
	self._token += 1
	self:_clearSky()
	if event then
		self:_raiseSky(event)
		self:_armLightning()
		self:_armMeteors()
	end
	return true
end

--- What this client is drawing right now, and on whose authority. Read by the panel every frame, so
--- it allocates one small table and touches nothing.
function WeatherController.debugState(self): { racing: boolean, staged: boolean, world: number?, event: string? }
	return {
		racing = self._racing == true,
		staged = self._staged == true,
		world = self._world,
		event = self._event,
	}
end

WeatherController:withRemoteEvents({
	{
		[WeatherConfig.StartedEvent] = function(world: unknown, key: unknown, endsAt: unknown)
			WeatherController:_onStarted(world, key, endsAt)
		end,
		--[[ The world arrives with the seed, which is why this unpacks the same three arguments
			`RoadController` does rather than reading the player attribute. ]]
		RaceStart = function(_seed: unknown, world: unknown)
			WeatherController:_onRaceStart(if type(world) == "number" then world else nil)
		end,
		RaceEnd = function()
			WeatherController:_onRaceEnd()
		end,
	},
})

WeatherController:withLifecycle({
	init = function(self)
		self._saved = nil
		self._sky = nil :: BasePart?
		self._event = nil :: string?
		self._world = nil :: number?
		self._racing = false
		--- Set only by `debugStage`, and only so the panel knows whose sky is up. Never true in a race.
		self._staged = false
		self._tweens = {} :: { Tween }
		self._token = 0
		self._pollAt = 0
		--[[ The notice, built on first use (`_buildNotice`). Its tween and its token are kept apart
			from `_tweens`/`_token` above on purpose: those are the SKY'S, and `_cancelTweens` kills
			every one of them at race start — which would strand a notice half way down the screen. ]]
		self._notice = nil :: ScreenGui?
		--- True when the card is the new UI's (`_buildNoticeKit`). Read only for the title's case.
		self._noticeKit = false
		self._noticeTween = nil :: Tween?
		self._noticeToken = 0
		--- The rows whose `UITextSizeConstraint` ceilings `_fitNotice` re-derives, and the connection
		--- that calls it. Both live as long as the card does, which is the session — the card is
		--- built once and re-armed, so there is nothing here to disconnect.
		self._noticeRows = {} :: { TextLabel }
		self._noticeFit = nil :: RBXScriptConnection?
		--[[ Set in `start` rather than assumed, so a notice landing between the remote binding and
			the feature check is dropped rather than acted on. Same shape as `TipsController`. ]]
		self._live = false
		self._rng = Random.new()

		--[[ The library look (`WeatherConfig.EventVfx`): its Folder, one record per layer, the meteor
			pool and its spec, the shared blast, the bolt rig, and which way this event's meteors fall.
			All emptied by `_clearSky`. The ground cache is `_groundY`'s, for when there is no road. ]]
		self._vfx = nil :: Folder?
		self._vfxLayers = {} :: { any }
		self._meteors = {} :: { any }
		self._meteorSpec = nil
		self._meteorSide = 1
		self._blast = nil
		self._boltRig = nil
		self._groundCache = nil :: number?
		self._groundAt = 0
		self._unshift = nil :: (() -> ())?
	end,

	start = function(self)
		if not WeatherConfig.Enabled then
			return
		end
		-- The deck height the library look's road layers stand on, and the rebase they ride.
		self._road = Shard.get("RoadController")
		self._live = true
	end,
})

return WeatherController
