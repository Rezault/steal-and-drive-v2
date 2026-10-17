--[[
	CarMutation  (shared)
	---------------------
	WHAT A MUTATED CAR LOOKS LIKE. One module, because four callers have to agree on it and all four
	are looking at the same car at different points in its life:

	  • a traffic shell on the road, which is what you decide to jump at;
	  • the car under you the moment the steal lands, which is what you drove to the truck;
	  • the display car on a garage podium, which is what you got to keep;
	  • the viewport thumbnail on an inventory card, which is how you find it again.

	Any two of those disagreeing reads as the mutation having come off, so the look is decided here
	once and every caller asks for it by key.

	=== THE LOOK IS THREE INSTANCES, AND ONLY THE BADGE NEEDS ART ==============================

	  1. A `Highlight`. Fill and outline in the mutation's colours, so the car is recoloured WITHOUT
	     touching the paintwork underneath it. That last part is the whole reason it is a Highlight
	     and not a tint: the paint on a traffic shell is a rolled palette index that a steal carries
	     onto the player's bodywork and a bank writes into a save file (`CarPaint`, `PaintConfig`),
	     and a mutation that repainted the car would destroy the very thing it is riding on. A
	     Highlight is a render pass over the top; strip it and the car is untouched.
	  2. Optional `ParticleEmitter` LAYERS filling the car's own hit volume, for the mutations whose
	     tell should move: one for a plain sparkle, up to `MAX_LAYERS` for a look built from several
	     (Molten is flame, embers and smoke). See `WeatherConfig`'s `Sparkle` note.
	  3. A `BillboardGui` badge naming it and quoting its multiplier — TRAFFIC ONLY, see `apply`.
	     It is built from the kit (`UIAssets.Page.SlotSquare`, `UIAssets.Pill`, `UIAssets.Weather`)
	     rather than drawn as a coloured rounded rectangle, because it is the same thing the lobby's
	     weather notice says and had to look like it. The highlight needs no art at all, and an
	     emitter never needs more than a particle texture: nothing here is fitted to a body, because
	     all of it has to work on a car whose body is unknown.

	`Highlight` HAS A BUDGET. Roblox renders about 31 of them before it starts dropping the rest
	silently, and this game can have `TrafficConfig.MaxCars` (12) shells plus the player's car plus
	six podiums on screen. That is inside it, but not far inside it, which is why nothing here ever
	creates a second Highlight for a car that already has one — `apply` reuses.

	=== AND A FOURTH, THE SKIN: A REPAINT THAT REMEMBERS =======================================

	Most mutations are named for what happened to the METAL (rusted, molten, soaked, a ghost), and a
	Highlight cannot do that: it can only wash a colour over the car. So those four also put the
	car's own parts into an engine material (`WeatherConfig` `Skin`: `CorrodedMetal`, `CrackedLava`,
	`ForceField`, and `Glass` for the soaked car). That is the repaint point 1 above warns against,
	and it is safe for two reasons.

	A skin with no `Color` is not a repaint at all: it changes the MATERIAL and leaves the colour,
	the texture and the detail map exactly where the paint put them (Soaked, wet paint rather than a
	new colour). Only the material is remembered and put back for those.

	THE PAINT INDEX IS NOT THE PART COLOUR. What a steal carries and a bank saves is the `Paint`
	attribute (StealController `_applyTier`), and a skin never touches it. A Rusted car banked in red
	is a red car with rust on it, and the podium repaints it red before it rusts it again.

	AND IT IS UNDONE FROM WHAT THE PART ITSELF REMEMBERS. Before a skin changes a part it writes the
	material, colour, texture (and transparency, if it sets one) it found into ATTRIBUTES on that
	part, and parks any
	`SurfaceAppearance` (a paint detail map) in a Folder under it, where it stops drawing. Stripping
	reads them back. On the part and not in a table here, because the steal CLONES the shell's parts
	onto the player's car: attributes come across with a clone and a Lua table would not. The Folder
	does NOT come across (`CarBody.swapMeshes` keeps render children only), which is fine, because the
	steal repaints the new body before dressing it (see `_applyTier`) and that puts a fresh map on.

	`apply` STRIPS EVERY SKINNED PART IT CAN FIND BEFORE IT DOES ANYTHING ELSE, not only the ones it
	is about to skin. That is what keeps a pooled shell honest across forty dressings, and it is
	what lets `CarPaint.parts` (which reads textures to decide what is paintwork) see the car as it
	really is rather than as the last skin left it.

	=== POOLED RECORDS ARE WHY EVERYTHING HERE IS REUSED, NOT REBUILT ==========================

	`TrafficController` pools its shells: one record is one body's meshes for a whole race, spawned,
	recycled and spawned again as a different car every few seconds. So `apply` is written to be
	called on the same model dozens of times with a different key each time, and `apply(car, nil)` —
	the strip — has to leave the model exactly as it found it. Everything is therefore DISABLED
	rather than destroyed: an emitter that is off costs nothing and is there for the next spawn,
	where rebuilding would be thirty instances a minute per shell for the collector.

	=== THE EMITTER HANGS OFF THE HIT VOLUME, DELIBERATELY ======================================

	A `Box` emitter fills its PARENT PART's volume, and the parent that makes that mean something is
	already on every car in this game: the traffic shell's `Hit` and the player car's `HitBox` are
	both car-sized boxes. Parenting to those gets an effect that wraps the whole car for free, with
	no new part welded into a pooled shell — which matters, because a shell is something four systems
	do spatial queries around and a fifth measures a bounding box off.

	It falls back to the PrimaryPart and then to the car's LARGEST part when there is no hit volume,
	which is not a theoretical branch: the garage's podium car is a stripped clone with its hull
	deliberately deleted (`Modules/CarDisplay`), so that fallback is the whole reason a mutated car
	standing on a podium looks like one. See `hostOf`.

	HOUSE RULE: no wiki-style double-bracket links in this comment — the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CarPaint = require(ReplicatedStorage.shared.Modules.CarPaint)
local ObstacleConfig = require(ReplicatedStorage.shared.Configs.ObstacleConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)

local CarMutation = {}

--- The names everything here builds under. Fixed strings so a strip finds what an apply left, and
--- so anything walking a car in the Explorer can tell what these are.
local HIGHLIGHT_NAME = "MutationHighlight"
local EMITTER_NAME = "MutationSparkle"
local BADGE_NAME = "MutationBadge"

--[[ How many emitter layers one car can wear, and so how far a strip looks. Layer 1 keeps the old
	`MutationSparkle` name and layer N is `MutationSparkleN`, so a car dressed by an older build still
	strips. `Molten` uses three (flame, embers, smoke); four leaves one spare without letting a config
	grow a car into a particle fountain. ]]
local MAX_LAYERS = 4

--[[ What a skinned part remembers about itself (see the header's fourth piece). `SKIN_ATTR` holds
	the mutation key and is the test for "this part is skinned"; the other three are what it wore
	before. `STASH_NAME` is the Folder a part's SurfaceAppearances wait in while it is skinned. ]]
local SKIN_ATTR = "MutationSkin"
local WAS_MATERIAL_ATTR = "MutationWasMaterial"
local WAS_COLOR_ATTR = "MutationWasColor"
local WAS_TEXTURE_ATTR = "MutationWasTexture"
-- Only written by a skin that sets `Transparency` (none does today), so absent otherwise.
local WAS_TRANSPARENCY_ATTR = "MutationWasTransparency"
local STASH_NAME = "MutationStash"

-- The dress on a rigged car. Absent on a traffic shell and on a podium car, which are their own.
local BODY_FOLDER = "Body"

--- Invisible structural parts that no skin ever touches, by name. `CarPaint`'s list, for its reason.
local STRUCTURAL = { HitBox = true, Root = true, Hit = true }

--[[ HOW THE BADGE DIVIDES ITSELF UP: two HEIGHTS as fractions of the billboard's own, and the gap
	between them as a fraction of its WIDTH. The well and the pill take a height each and derive
	their width from their texture's aspect, so these three numbers plus `WeatherConfig.Badge.Size`
	are the whole layout and there is no other arithmetic anywhere in this file.

	THEY ARE ALSO WHAT SETS THAT `Size`, and the sum is worth keeping written down. The slot square
	is 0.994:1 and the pill is 3.891:1, so the two of them come to

	    0.88 * 0.994  +  0.70 * 3.891  =  3.60 badge-HEIGHTS of content,

	and with `A` for the badge's own aspect (`Size.X / Size.Y`) the row fits when

	    3.60 / A  +  0.03  <=  1,   i.e.  A >= 3.72.

	`Badge.Size` is 11.8x3, so A is 3.93 and about 3% of the width is clear at each end. UNDER 3.72
	IT BREAKS IN TWO SILENT WAYS AT ONCE, neither of which errors: each child's own constraint clamps
	it to the parent box, so the PILL loses height (it is the wider of the two and hits the wall
	first) and stops matching the well; and the `UIListLayout` still overflows, so the row spills past
	both ends of a billboard that does not clip. Change either end and check the other.

	AND THE WHOLE THING IS KEPT AS NARROW AS THAT ARITHMETIC ALLOWS, because `RushHour` is the case
	that decides it: at `Impatient`'s 0.22 against 21 cars there are four or five of these on screen
	at once, and a marker sized for a lone rare car becomes a wall of pills on the one event that is
	about volume. 11.8 studs is about one car width — wide enough to read, not wide enough to tile.

	THE PILL IS THE SHORTER OF THE TWO on purpose. The well is a heavy square with a painted rim and
	the pill is a light lozenge; matched in height the square dominates, and the thing being read is
	the words. The notice card splits them the same way for the same reason. ]]
local BADGE_WELL_HEIGHT = 0.88
local BADGE_PILL_HEIGHT = 0.7
local BADGE_GAP = 0.03

--- How far inside the well the glyph sits, per edge, so it never touches the slot's painted rim.
--- The notice card's own number.
local BADGE_ICON_INSET = 0.16

--- The pill caption's centre line. Not 0.5: the artist's pill face sits slightly high in its own
--- canvas, so a caption centred on the BOX reads visibly low against the FACE.
local BADGE_LABEL_CENTRE = 0.46

--- `TextScaled` would sooner break a caption onto a second line than pick a smaller font, so the
--- name and the multiplier are joined by a non-breaking space. Same answer as RaceUIController's,
--- and the reason nothing here writes `TextWrapped` (which would clear `TextScaled` outright).
local NBSP = utf8.char(0xA0)

--[[ The attribute a car wears so that anything holding only the Model can ask what it is.

	THIS IS THE PART THAT ACTUALLY TRAVELS. The steal reads it off the shell it landed on, stamps it
	on the player's car, and the truck reads it back off that car and sends it with the bank — the
	same route the tier, the body and the paint take, and for the same reason: between the spawn and
	the truck, the only record of what is wrong with this car is the car. ]]
CarMutation.Attribute = "Mutation"

--[[ The texture a layer uses when its spec names none. A stock engine texture, so a plain sparkle
	reads on a car of any colour at any distance with nothing to upload.

	`rbxasset://` and not `rbxassetid://`: it ships with the engine, so it costs no fetch and cannot
	fail to load on a cold client. The layers that DO name a texture (the Charged arcs, the Molten
	flame, the Ghost wisps) take it from the VFXer plugin's library; see `WeatherConfig`. ]]
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

--- `Flipbook` in a layer spec, by name. A spec with none is a single still image.
local FLIPBOOKS = {
	Grid2x2 = Enum.ParticleFlipbookLayout.Grid2x2,
	Grid4x4 = Enum.ParticleFlipbookLayout.Grid4x4,
	Grid8x8 = Enum.ParticleFlipbookLayout.Grid8x8,
}

--[[ The bob tween currently driving each badge, so a re-arm can cancel the one it replaces — see
	`setBadge`. WEAK-KEYED: a destroyed badge (a shell that went out with the race) drops out of here
	on its own, which is what stops a module-level table becoming a leak that outlives every race in
	the session. ]]
local bobs: { [BillboardGui]: Tween } = setmetatable({}, { __mode = "k" }) :: any

-- === Finding somewhere to put things ========================================

--[[ Is this something we can dress at all?

	A MODEL, AND THAT IS THE WHOLE TEST. It used to also require a `PrimaryPart`, which was wrong and
	silently so: the garage's podium car is a clone of the body's `Body` FOLDER with its joints
	destroyed and its hull deleted (`Modules/CarDisplay`), so it has no PrimaryPart at all — and
	every mutated car a player owned stood on its podium completely undressed, with the attribute not
	even stamped. Nothing errored, because the guard just returned false.

	A `Highlight` needs no part in any case: parented to the Model with a nil `Adornee` it adorns
	everything under it. Only the emitter and the badge need somewhere to hang, and that is `hostOf`'s
	problem rather than this one's. ]]
local function dressable(car: Instance?): boolean
	return car ~= nil and car:IsA("Model")
end

--[[ The part the emitter and the badge hang off, best first.

	`Hit` is the traffic shell's hull and `ObstacleConfig.HitBoxName` is the player car's, and either
	is ideal: both are car-sized boxes, so a `Box` emitter parented to one wraps the whole car for
	free (see the header). Checked in that order because a traffic shell is the common case by a
	factor of twelve.

	THE FALLBACK IS THE BIGGEST PART, not the first one found, and that is what makes a podium car
	work: it has no hull, so without a rule the emitter would land on whichever panel `GetDescendants`
	happened to return first — a wing mirror as often as a roof — and the sparkle would come out of
	one corner. The largest part of a stripped body is the shell, which is close enough to the shape
	of the car to read correctly.

	Nil only for a Model with no parts in it at all, which is the frame a traffic shell spends between
	being cloned and being built. `apply` treats that as "highlight only". ]]
local function hostOf(car: Model): BasePart?
	local hit = car:FindFirstChild("Hit")
	if hit and hit:IsA("BasePart") then
		return hit
	end
	local box = car:FindFirstChild(ObstacleConfig.HitBoxName, true)
	if box and box:IsA("BasePart") then
		return box
	end
	if car.PrimaryPart then
		return car.PrimaryPart
	end

	local best, bestVolume = nil, 0
	for _, part in car:GetDescendants() do
		if part:IsA("BasePart") then
			local size = part.Size
			local volume = size.X * size.Y * size.Z
			if volume > bestVolume then
				best, bestVolume = part, volume
			end
		end
	end
	return best
end

-- === The pieces =============================================================

--- The car's Highlight, made if it has none. Never more than one per car; see the budget note.
local function ensureHighlight(car: Model): Highlight
	local existing = car:FindFirstChild(HIGHLIGHT_NAME)
	if existing and existing:IsA("Highlight") then
		return existing
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = HIGHLIGHT_NAME
	--[[ Occluded, NOT AlwaysOnTop. The other setting draws the car THROUGH the road, through the
		traffic in front of it and through the obstacle you are about to hit, which on a mutated car
		in the outside lane reads as an X-ray bug rather than as a rare car. The badge is what makes
		it findable at distance; the highlight only has to make it obvious once it is in view. ]]
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Parent = car
	return highlight
end

--- The name emitter layer `layer` builds under. See `MAX_LAYERS` for why layer 1 is unnumbered.
local function emitterName(layer: number): string
	return if layer == 1 then EMITTER_NAME else EMITTER_NAME .. layer
end

--- Layer `layer`'s emitter if the car already has one. Looked for, never made: see `apply`'s strip.
local function existingEmitter(car: Model, layer: number): ParticleEmitter?
	local host = hostOf(car)
	local existing = host and host:FindFirstChild(emitterName(layer))
	return if existing and existing:IsA("ParticleEmitter") then existing else nil
end

--- Layer `layer`'s emitter, made if the car has none and if there is somewhere to hang it. Only the
--- properties no spec ever changes are set here; `dressEmitter` writes the rest on every dressing.
local function ensureEmitter(car: Model, layer: number): ParticleEmitter?
	local existing = existingEmitter(car, layer)
	if existing then
		return existing
	end
	local host = hostOf(car)
	if not host then
		return nil
	end

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = emitterName(layer)
	emitter.Enabled = false
	-- Fill the host's volume rather than emit from its centre. See the header on why the host is
	-- the hit box.
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Orientation = Enum.ParticleOrientation.FacingCamera
	emitter.Parent = host
	return emitter
end

--[[ A mutation's emitter layers as a list: `Sparkle` may be one spec (the old shape, and still the
	common one) or an array of them. Anything past `MAX_LAYERS` is ignored rather than built, so a
	typo in the config cannot put a dozen emitters on every shell on the road. ]]
local function layersOf(mutation: any): { any }
	local sparkle = mutation.Sparkle
	if type(sparkle) ~= "table" then
		return {}
	end
	local layers = if sparkle[1] ~= nil then sparkle else { sparkle }
	if #layers > MAX_LAYERS then
		return table.move(layers, 1, MAX_LAYERS, 1, {})
	end
	return layers
end

--- A spec's `Speed`: a number for one speed, or `{ min, max }` for a spread of them.
local function speedOf(value: unknown): NumberRange
	if type(value) == "table" and type(value[1]) == "number" and type(value[2]) == "number" then
		return NumberRange.new(math.min(value[1], value[2]), math.max(value[1], value[2]))
	end
	return NumberRange.new(if type(value) == "number" then value else 3)
end

--[[ Write one layer spec onto its emitter. EVERY property a spec can touch is written on every
	dressing, the defaults included, and never left from the last one: the emitter is pooled with its
	shell, so the slot that was Molten's flame one spawn has to be a plain sparkle the next, and a
	flipbook or a size ramp left behind would put the old mutation's shape on the new one.

	The defaults are exactly what the single sparkle always was, so a spec written before layers
	existed renders as it did. `fallback` is the colour for a spec that names none. ]]
local function dressEmitter(emitter: ParticleEmitter, spec: any, fallback: Color3)
	emitter.Texture = if type(spec.Texture) == "string" then spec.Texture else SPARKLE_TEXTURE
	emitter.FlipbookLayout = FLIPBOOKS[spec.Flipbook] or Enum.ParticleFlipbookLayout.None
	--[[ OneShot plays the sheet exactly once across each particle's life, which is what every sheet
		here is drawn for (an arc that grows and breaks, a flame that flares and dies). Written here
		and not only when the emitter is made, because the default is `Loop` at 1 frame a second: an
		emitter built without it shows a 0.3s particle its FIRST frame and nothing else, which on the
		arc sheet is a speck. ]]
	emitter.FlipbookMode = Enum.ParticleFlipbookMode.OneShot

	-- The start and end of a life. An end left out holds the start, so a plain spec is constant.
	local color = if typeof(spec.Color) == "Color3" then spec.Color else fallback
	emitter.Color = ColorSequence.new(color, if typeof(spec.ColorEnd) == "Color3" then spec.ColorEnd else color)
	local size = spec.Size or 0.5
	emitter.Size = NumberSequence.new(size, spec.SizeEnd or size)
	local alpha = spec.Transparency or 0.4
	emitter.Transparency = NumberSequence.new(alpha, spec.Fade or alpha)

	emitter.Rate = spec.Rate or 20
	emitter.Speed = speedOf(spec.Speed)
	-- A spread of lifetimes rather than one value, so the effect does not pulse in waves.
	local life = spec.Lifetime or 0.8
	emitter.Lifetime = NumberRange.new(life * 0.6, life)
	emitter.LightEmission = spec.Glow or 0
	emitter.Brightness = spec.Brightness or 1
	emitter.Drag = spec.Drag or 0
	emitter.ZOffset = spec.ZOffset or 0

	local spread = spec.Spread or 35
	emitter.SpreadAngle = Vector2.new(spread, spread)
	-- `Rotation` is how far either way of upright a particle may start (180 is any angle), and
	-- `Spin` how fast either way it turns. A flame wants a small tilt and no spin; a flake wants both.
	local tilt = spec.Rotation or 180
	emitter.Rotation = NumberRange.new(-tilt, tilt)
	local spin = spec.Spin or 90
	emitter.RotSpeed = NumberRange.new(-spin, spin)

	--[[ `Surface` spawns on the host box's TOP FACE only (a Box emitter's surface is the one face its
		`EmissionDirection` names), which on a car-sized hit box is a plane at roof height: right for
		something rising off the car, like a flame. The default fills the whole box instead, which
		puts particles on and inside the panels. ]]
	emitter.ShapeStyle = if spec.Surface == true
		then Enum.ParticleEmitterShapeStyle.Surface
		else Enum.ParticleEmitterShapeStyle.Volume

	--[[ `Locked` pins the particles to the car, so they ride on the paintwork however fast it is going
		(the Charged arcs). Otherwise they inherit `Inherit` of the car's velocity: 0.75 by default,
		which is what stops a car at 40 studs/s leaving its own sparkle in a line behind it on the
		tarmac, while the little lag left over is what makes the effect read as coming OFF the car
		rather than being painted on it. Lower trails it further. ]]
	emitter.LockedToPart = spec.Locked == true
	emitter.VelocityInheritance = spec.Inherit or 0.75

	-- A gentle lift by default, so particles drift off the roof instead of hanging in the cabin.
	-- `Lift` overrides it, and below zero it is gravity: the rust's flakes fall.
	local top = emitter.Speed.Max
	emitter.Acceleration = Vector3.new(0, if type(spec.Lift) == "number" then spec.Lift else top * 0.5, 0)
end

--- Switch a layer off and drop what it had in the air, so a recycled shell does not carry the last
--- car's flame across the road with it.
local function quiet(emitter: ParticleEmitter?)
	if emitter then
		emitter.Enabled = false
		emitter:Clear()
	end
end

--[[ The badge: the event's glyph in a kit slot well, then a kit pill naming the mutation and
	quoting its multiplier.

	A BILLBOARD AND NOT SOMETHING ON THE BODYWORK, and the timing is the reason. The steal arc takes
	about a second and a half and cannot be called off once it is launched (StealController), so the
	player has to know what they are jumping at BEFORE they commit — which means the tell has to read
	at two or three hundred studs, where a mutated car is a few pixels of coloured highlight and any
	decal on it is nothing at all.

	=== IT IS THE LOBBY NOTICE'S OWN SENTENCE, SHRUNK — 2026-08-28 ==============================

	It used to be a `Frame` with a `UICorner` at half its height and a black `UIStroke`, painted the
	mutation's raw `Color`. That is the rounded-rect-and-neon construction the notice card, the
	forecourt sign and the customer speech bubble were each rebuilt to get away from — and this was
	the worst of the three, because the notice that ANNOUNCES the weather and the badge on the car
	that weather produced are on screen within seconds of each other and were drawn in two different
	visual languages.

	So it is made of the notice's own parts, in the notice's own order, and no new art was drawn:

	  • the WELL is `UIAssets.Page.SlotSquare`, the empty Index collection slot, carrying the EVENT's
	    glyph (`WeatherConfig.mutationIcon`). The glyph rather than the mutation's, because there is
	    no mutation art and there does not need to be: the weather is what is recognised at two
	    hundred studs and the words are what is read once you are close. The glyphs are full colour
	    and are NEVER tinted (`ImageColor3` multiplies), so they need a dark seat — against bare sky
	    the two pale ones, fog and sandstorm, dissolve.
	  • the PILL is `UIAssets.Pill`, picked by `WeatherConfig.mutationPill`, which is the SAME lookup
	    the notice's payoff line and the world card's flag use. One table, so a MOLTEN car wears one
	    red pill on all three surfaces instead of three different reds.

	AND THE CAPTION WAS TWO BUGS, not two choices. It asked for `Enum.Font.Ubuntu`, which resolves to
	Ubuntu REGULAR in a kit that is Bold everywhere else; and it wrote `TextWrapped = false` AFTER
	`TextScaled = true`, which silently CLEARS `TextScaled` and drops the label to the default
	`TextSize` of 8. Eight pixels is what "a little text label" means, and it is why the badge's type
	got relatively smaller the closer you drove to it. Nothing here writes `TextWrapped` at all — the
	name and the multiplier are joined by a NON-BREAKING SPACE instead, which is this project's
	standing answer to `TextScaled` reaching for a second line (see RaceUIController).

	NO `UITextSizeConstraint` EITHER, and that is deliberate rather than an omission. A ceiling is
	the instrument for making SEVERAL rows in differently-sized boxes agree with each other — what
	the notice card needs and what this has one row of. Here a cap would freeze the type while the
	pill behind it kept growing, which is a big pill with small writing in it at close range.

	Built once per car and then only recoloured and re-labelled, for the pooling reason in the
	header. The bob is a looping tween rather than a per-frame step so that nothing here needs a
	connection or a heartbeat of its own; note that a MINIMISED Studio runs no render step, so during
	a playtest in a background window the badge will sit still. That is the tween caveat this repo
	has hit before and not a bug in this file. ]]
local function ensureBadge(car: Model): BillboardGui?
	local host = hostOf(car)
	if not host then
		return nil
	end

	local existing = host:FindFirstChild(BADGE_NAME)
	if existing and existing:IsA("BillboardGui") then
		return existing
	end

	local cfg = WeatherConfig.Badge

	local billboard = Instance.new("BillboardGui")
	billboard.Name = BADGE_NAME
	billboard.Size = UDim2.fromScale(cfg.Size.X, cfg.Size.Y)
	billboard.SizeOffset = Vector2.new(0, 0)
	billboard.AlwaysOnTop = true -- unlike the highlight: a marker you cannot see is not a marker
	billboard.LightInfluence = 0
	billboard.MaxDistance = cfg.MaxDistance
	billboard.Enabled = false
	billboard.ResetOnSpawn = false

	--[[ A transparent box for the layout to run in. A `UIListLayout` needs a `GuiObject` parent and
		a `BillboardGui` is not one, so this frame is not decoration — it is the only thing that can
		hold the row. ]]
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Parent = billboard

	--[[ THE ROW LAYS ITSELF OUT, which is what lets the well and the pill keep their drawn aspects
		without this file doing any trigonometry against the billboard's stud size. Each of the two
		takes its HEIGHT from `root` and derives its width from its own texture's aspect (see the
		constraints below), and the layout then centres whatever widths come out of that.

		It also gets the empty case for free: an event this build has no glyph for hides the well,
		and a `UIListLayout` skips invisible children — so the pill re-centres on its own rather than
		sitting off to one side of a gap. ]]
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(BADGE_GAP, 0)
	row.Parent = root

	--- The glyph's seat. Hidden by `setBadge` when there is no glyph to put in it.
	local well = Instance.new("ImageLabel")
	well.Name = "Well"
	well.LayoutOrder = 1
	--[[ A REAL width box rather than `UDim2.fromScale(0, h)`: `AspectType.ScaleWithParentSize`
		resolves against the PARENT so the authored width is only a starting point, but a zero one
		still collapses under the default `AspectType` and that trap has cost this repo an afternoon
		before (see `UIAssets`' sizing note). ]]
	well.Size = UDim2.fromScale(0.2, BADGE_WELL_HEIGHT)
	well.Image = UIAssets.url(UIAssets.Page.SlotSquare)
	well.ScaleType = Enum.ScaleType.Stretch
	well.BackgroundTransparency = 1
	well.BorderSizePixel = 0
	well.Parent = root

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
	icon.Size = UDim2.fromScale(1 - BADGE_ICON_INSET * 2, 1 - BADGE_ICON_INSET * 2)
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	--- `Fit` and not `Stretch`: the six weather glyphs are square canvases but the drawings inside
	--- them are not all one shape, and this is the one place on the badge where the art is not being
	--- drawn at the size it was exported at.
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = well

	--[[ The pill, `Stretch` with the art's own 3.891:1 held by the constraint below and NEVER
		`Slice`. A 9-sliced pill holds its corners at 1:1 texture pixels and renders as a fat lozenge
		at any size but the art's; that is written up at length under `UIAssets.Slice` and it is the
		single most repeated mistake in this kit. ]]
	local pill = Instance.new("ImageLabel")
	pill.Name = "Pill"
	pill.LayoutOrder = 2
	pill.Size = UDim2.fromScale(0.7, BADGE_PILL_HEIGHT)
	pill.ScaleType = Enum.ScaleType.Stretch
	pill.BackgroundTransparency = 1
	pill.BorderSizePixel = 0
	pill.Parent = root

	local pillShape = Instance.new("UIAspectRatioConstraint")
	pillShape.AspectRatio = UIAssets.Size.Pill.X / UIAssets.Size.Pill.Y
	pillShape.DominantAxis = Enum.DominantAxis.Height
	pillShape.AspectType = Enum.AspectType.ScaleWithParentSize
	pillShape.Parent = pill

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	--[[ Centred on the pill's FACE and not on its box, and inset from it. The artist's face sits
		slightly high in the art's own canvas, so a caption centred on the box reads visibly low —
		the same hair of offset the notice card's payoff line and the plaza's pills use. ]]
	label.AnchorPoint = Vector2.new(0.5, 0.5) -- house convention, see the UI anchor note
	label.Position = UDim2.fromScale(0.5, BADGE_LABEL_CENTRE)
	--- Inset from the face rather than filling it. The kit's own captions (the plaza's plaques, the
	--- upgrade board's UPGRADE) leave about a tenth of the pill clear at each end, and the pill's
	--- ends are round — type run to the edge crowds the curve.
	label.Size = UDim2.fromScale(0.76, 0.42)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = cfg.FontFace
	label.TextScaled = true
	label.Text = ""
	label.Parent = pill

	billboard.Parent = host
	return billboard
end

-- === The skin ===============================================================

--- Where a skin looks for parts: `Body/` on a rigged car, the model itself on a shell or a podium
--- car. The same answer `CarPaint` gives, so "All" and "Paint" walk the same tree.
local function dressOf(car: Model): Instance
	return car:FindFirstChild(BODY_FOLDER) or car
end

--[[ The parts a skin covers. "All" is every visible part of the dress, which is the ghost: glass,
	wheels and cabin going spectral with the body is the look. Anything else is the paintwork as
	`CarPaint` answers it, so the trim, the grille, the glass and the lamps keep the artist's look
	and a rusted car still has a face. Asked AFTER `stripSkin`, because `CarPaint.parts` reads
	textures and a skin clears them. ]]
local function skinParts(car: Model, scope: unknown): { BasePart }
	if scope ~= "All" then
		return CarPaint.parts(car)
	end
	local parts = {}
	for _, inst in dressOf(car):GetDescendants() do
		if inst:IsA("BasePart") and inst.Transparency < 1 and not STRUCTURAL[inst.Name] then
			table.insert(parts, inst)
		end
	end
	return parts
end

--[[ Put one part into a skin, writing what it wore first onto the part itself.

	WITH A `color` THE SKIN REPLACES THE PAINT. The texture is cleared because it beats `Color`
	outright on this roster (`CarPaint`'s header), and a SurfaceAppearance is parked because it beats
	the MATERIAL outright: a painted car with a detail map would otherwise keep its paint and never
	show the rust at all. Parked in a Folder under the part rather than unparented, so the part is
	the only thing that has to remember it.

	WITHOUT ONE IT KEEPS THE PAINT and only the material changes, so the colour, texture and detail
	map are neither touched nor stashed. A panel wearing a detail map shows no change at all that
	way, because its SurfaceAppearance draws over the material (`WeatherConfig`'s `Skin` note).

	`transparency` is optional and no mutation passes one today. Soaked's glass did, until it was
	judged too see-through and went opaque with a water spray doing the work instead. ]]
local function skinPart(part: BasePart, key: string, material: Enum.Material, color: Color3?, transparency: number?)
	part:SetAttribute(WAS_MATERIAL_ATTR, part.Material.Name)
	if transparency then
		part:SetAttribute(WAS_TRANSPARENCY_ATTR, part.Transparency)
		part.Transparency = transparency
	end

	if color then
		part:SetAttribute(WAS_COLOR_ATTR, part.Color)
		if part:IsA("MeshPart") then
			part:SetAttribute(WAS_TEXTURE_ATTR, part.TextureID)
			part.TextureID = ""
		end

		local stash = nil
		for _, child in part:GetChildren() do
			if child:IsA("SurfaceAppearance") then
				if not stash then
					stash = Instance.new("Folder")
					stash.Name = STASH_NAME
				end
				child.Parent = stash
			end
		end
		if stash then
			stash.Parent = part
		end

		part.Color = color
	end

	part.Material = material
	part:SetAttribute(SKIN_ATTR, key)
end

--[[ Put one skinned part back exactly as `skinPart` found it, and forget the skin.

	Every field is checked rather than trusted, because the attributes can outlive the rest: a part
	cloned onto the player's car by a steal brings its attributes and leaves its stash Folder behind.
	A missing stash is therefore normal and restores nothing, and the repaint the steal does next is
	what puts a detail map back. ]]
local function unskinPart(part: BasePart)
	local material = part:GetAttribute(WAS_MATERIAL_ATTR)
	if type(material) == "string" then
		local ok, value = pcall(function()
			return (Enum.Material :: any)[material]
		end)
		if ok and typeof(value) == "EnumItem" then
			part.Material = value
		end
	end
	local color = part:GetAttribute(WAS_COLOR_ATTR)
	if typeof(color) == "Color3" then
		part.Color = color
	end
	local texture = part:GetAttribute(WAS_TEXTURE_ATTR)
	if type(texture) == "string" and part:IsA("MeshPart") then
		part.TextureID = texture
	end
	local transparency = part:GetAttribute(WAS_TRANSPARENCY_ATTR)
	if type(transparency) == "number" then
		part.Transparency = transparency
	end

	local stash = part:FindFirstChild(STASH_NAME)
	if stash then
		for _, surface in stash:GetChildren() do
			surface.Parent = part
		end
		stash:Destroy()
	end

	part:SetAttribute(SKIN_ATTR, nil)
	part:SetAttribute(WAS_MATERIAL_ATTR, nil)
	part:SetAttribute(WAS_COLOR_ATTR, nil)
	part:SetAttribute(WAS_TEXTURE_ATTR, nil)
	part:SetAttribute(WAS_TRANSPARENCY_ATTR, nil)
end

--[[ Take every skin off the car. The WHOLE dress, not the parts the next skin is about to cover:
	a ghost covers the glass and a rust does not, so a pooled shell going from one to the other
	would otherwise keep ghost windows under its rust. A walk of ~50 parts, once per dressing. ]]
local function stripSkin(car: Model)
	for _, inst in dressOf(car):GetDescendants() do
		if inst:IsA("BasePart") and inst:GetAttribute(SKIN_ATTR) ~= nil then
			unskinPart(inst)
		end
	end
end

-- === Applying ===============================================================

--[[ Show or hide the badge over `car`. Separate from `apply` because the two are wanted apart: the
	road wants a badge on every mutated shell, and the player's own car must never have one (it would
	hang in the middle of the chase camera for the rest of the run).

	`nil` hides without building, so an unmutated car never grows a BillboardGui it will not use. ]]
function CarMutation.setBadge(car: Instance?, key: unknown)
	if not dressable(car) then
		return
	end
	local model = car :: Model
	local host = hostOf(model)
	local mutation = WeatherConfig.mutationOf(WeatherConfig.sanitize(key))

	if not mutation or not WeatherConfig.Badge.Enabled then
		local existing = host and host:FindFirstChild(BADGE_NAME)
		if existing and existing:IsA("BillboardGui") then
			existing.Enabled = false
		end
		return
	end

	local billboard = ensureBadge(model)
	if not billboard then
		return
	end

	--[[ Repaint, rather than rebuild. Everything below is a property write on instances `ensureBadge`
		already made, which is the pooling contract: one shell is dressed as forty different cars in a
		race and none of those forty may allocate.

		THE PILL AND THE GLYPH COME FROM THE SAME PLACE THE NOTICE'S DO — `mutationPill` routes
		through the mutation's event to the kit face, and `mutationIcon` to that event's glyph. Both
		can answer "nothing sensible": an unknown event falls to the neutral silver pill, and a
		missing glyph hides the well entirely rather than showing an empty slot. ]]
	local root = billboard:FindFirstChild("Root")
	local well = root and root:FindFirstChild("Well") :: ImageLabel?
	local icon = well and well:FindFirstChild("Icon") :: ImageLabel?
	local pill = root and root:FindFirstChild("Pill") :: ImageLabel?
	local label = pill and pill:FindFirstChild("Label") :: TextLabel?

	local face = WeatherConfig.mutationPill(mutation.Key)
	if pill then
		local art = UIAssets.Pill[face.Pill] or UIAssets.Pill.Silver
		pill.Image = UIAssets.url(art.Idle)
	end
	if label then
		--[[ The kit's own rule, and it is a readability one rather than a taste one: white on the
			three pale faces (Silver at luma 200, Orange 172, Sky 168) is about 1.5:1, so those take
			the outline navy instead. `WeatherConfig.NoticePills` carries the pairing so the badge
			and the world card's flag can never disagree about it. ]]
		label.TextColor3 = face.Text
		label.Text = mutation.Name
			.. NBSP
			.. WeatherConfig.formatMultiplier(WeatherConfig.valueMultiplierOf(mutation.Key))
	end

	local glyph = WeatherConfig.mutationIcon(mutation.Key)
	if icon then
		icon.Image = if glyph then UIAssets.url(glyph) else ""
	end
	if well then
		--- Hidden and not merely emptied: a `UIListLayout` skips invisible children, so the pill
		--- re-centres itself over the car instead of sitting beside an empty square.
		well.Visible = glyph ~= nil
	end

	--[[ Sit the badge above the car's own roof rather than at a fixed height. Measured off the model
		each time because one call site is a pooled shell (one body, always the same height) and the
		other is the player's car, which changes body on every steal — a cached offset would leave
		the badge inside the roof of the next car up the ladder.

		`GetExtentsSize` and not `GetBoundingBox`: the height is all that is wanted, and the
		pivot-relative frame the latter measures in has caught this repo out before. ]]
	local lift = model:GetExtentsSize().Y * 0.5 + WeatherConfig.Badge.Clearance
	billboard.Enabled = true

	--[[ The bob, armed ONCE PER HEIGHT. The tween owns `StudsOffsetWorldSpace` while it runs, so a
		plain write here would be overwritten on the next frame and the badge would keep bobbing
		around whatever height the FIRST car this shell was ever dressed as happened to be. Tagged on
		the instance rather than tracked in this module, so a pooled shell recycled a hundred times
		still owns exactly one tween — and rebuilt only when the height it was built for is no longer
		the height of the car under it, which is a steal changing the player's body, not a recycle.

		Bob switched off in config falls through to the plain write, which is also the path a
		zero-height degenerate model takes. ]]
	local armed = billboard:GetAttribute("BobLift")
	if WeatherConfig.Badge.Bob > 0 and lift > 0 then
		if armed ~= lift then
			--[[ Cancel the old one first. Two looping tweens on the same property do not blend, they
				fight, and the visible result is a badge that jitters instead of floating. There is no
				way to find a running tween from the instance it drives, which is what `bobs` is
				for — and why it is weak-keyed rather than a list this module has to prune. ]]
			local previous = bobs[billboard]
			if previous then
				previous:Cancel()
			end
			billboard:SetAttribute("BobLift", lift)
			billboard.StudsOffsetWorldSpace = Vector3.new(0, lift, 0)
			bobs[billboard] = TweenService:Create(
				billboard,
				TweenInfo.new(
					WeatherConfig.Badge.BobPeriod * 0.5,
					Enum.EasingStyle.Sine,
					Enum.EasingDirection.InOut,
					-1,
					true
				),
				{ StudsOffsetWorldSpace = Vector3.new(0, lift + WeatherConfig.Badge.Bob, 0) }
			)
			bobs[billboard]:Play()
		end
	else
		billboard.StudsOffsetWorldSpace = Vector3.new(0, lift, 0)
	end
end

--[[ Dress `car` as `key`, or strip it bare with a nil key. Returns whether the car is now mutated.

	IDEMPOTENT AND REVERSIBLE, which is the contract the pooled traffic records need: calling this
	forty times on one model with forty different keys must leave no residue, and `apply(car, nil)`
	must leave the model exactly as an unmutated one.

	`withBadge` is the traffic/player split — see `setBadge`. Defaults to false, so the dangerous
	one is the one you have to ask for.

	It stamps `CarMutation.Attribute` either way, and that stamp is what actually travels; the
	visuals are what the player sees and the attribute is what the game means. ]]
--- `skinOnly` (2026-10-14, the held car): the skin and the outline, no particle layers, for a model
--- drawn far below the size the particles are authored in studs for (`CarryConfig.Hold.MutationSkin`).
function CarMutation.apply(car: Instance?, key: unknown, withBadge: boolean?, skinOnly: boolean?): boolean
	if not dressable(car) then
		return false
	end
	local model = car :: Model
	local mutation = WeatherConfig.mutationOf(WeatherConfig.sanitize(key))

	model:SetAttribute(CarMutation.Attribute, if mutation then mutation.Key else nil)

	-- The last skin comes off first, whatever this dressing turns out to be. See the header.
	stripSkin(model)

	if not mutation then
		--[[ Stripping LOOKS FOR what is there rather than making it. A car that was never mutated has
			none of these, and building three instances in order to switch them off would put a
			Highlight and a BillboardGui on every one of the twelve shells on the road. ]]
		local highlight = model:FindFirstChild(HIGHLIGHT_NAME)
		if highlight and highlight:IsA("Highlight") then
			highlight.Enabled = false
		end
		for layer = 1, MAX_LAYERS do
			quiet(existingEmitter(model, layer))
		end
		CarMutation.setBadge(model, nil)
		return false
	end

	local skin = mutation.Skin
	if type(skin) == "table" and typeof(skin.Material) == "EnumItem" then
		-- No `Color` keeps the car's own paint (see `skinPart`).
		local color = if typeof(skin.Color) == "Color3" then skin.Color else nil
		local transparency = if type(skin.Transparency) == "number" then math.clamp(skin.Transparency, 0, 0.95) else nil
		for _, part in skinParts(model, skin.Parts) do
			skinPart(part, mutation.Key, skin.Material, color, transparency)
		end
	end

	--[[ The Highlight, if there is anything left for it to draw. The outline strength is the
		`WeatherConfig.Outline` flags and the fill is the mutation's own, so a skinned mutation with
		its fill at 1 and the outline flagged off has nothing to show, and its Highlight is switched
		OFF rather than left enabled drawing nothing: that is one back from the ~31 budget. So is
		`Highlight = false`, which is the ghost (see `WeatherConfig`'s Skin note). Never created just
		to be disabled, for the strip branch's reason above. ]]
	local fill = mutation.FillTransparency or 0.6
	local outline = WeatherConfig.outlineTransparency()
	if mutation.Highlight ~= false and (fill < 1 or outline < 1) then
		local highlight = ensureHighlight(model)
		highlight.FillColor = mutation.Fill or mutation.Color
		highlight.OutlineColor = mutation.Outline or mutation.Color
		highlight.FillTransparency = fill
		highlight.OutlineTransparency = outline
		highlight.Enabled = true
	else
		local existing = model:FindFirstChild(HIGHLIGHT_NAME)
		if existing and existing:IsA("Highlight") then
			existing.Enabled = false
		end
	end

	--[[ The emitter layers: one per spec, then every layer past the last spec switched off. The ones
		in use are made on demand; the rest are only looked for, because a car that has only ever
		been a one-layer rust has no second emitter to switch off, and building one to disable it is
		waste. A pooled shell that was Molten (three layers) and is now Ghost (one) keeps the other
		two, silent, for the next Molten. ]]
	local layers = if skinOnly then {} else layersOf(mutation)
	local fallback = mutation.Outline or mutation.Color
	for layer = 1, MAX_LAYERS do
		local spec = layers[layer]
		if type(spec) == "table" then
			local emitter = ensureEmitter(model, layer)
			if emitter then
				dressEmitter(emitter, spec, fallback)
				emitter.Enabled = true
			end
		else
			quiet(existingEmitter(model, layer))
		end
	end

	CarMutation.setBadge(model, if withBadge then mutation.Key else nil)
	return true
end

--- What a car says it is, straight off the attribute, sanitised. nil for an ordinary car — and for
--- one carrying a key this build does not have, which is the same thing as far as anything here is
--- concerned.
function CarMutation.of(car: Instance?): string?
	if not car then
		return nil
	end
	return WeatherConfig.sanitize(car:GetAttribute(CarMutation.Attribute))
end

return CarMutation
