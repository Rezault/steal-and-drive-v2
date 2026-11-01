--[[
	CarViewport  (shared, client-side in practice)
	---------------------------------------------
	"Show me that car, in this box." A ViewportFrame with one of the roster's bodies standing in it,
	in the colour this player owns it in — the picture the dealership card needs and the one the
	spawn-car card will want next.

	One module rather than a copy in each page, because the picture is the same picture: the same
	pose, the same lighting and the same framing on every screen that shows a car in a box, and two
	pages disagreeing about any of the three shows up as one screen's cars looking wrong.

	SIX THINGS TO KNOW BEFORE CHANGING ANY OF IT.

	1. THE MODEL COMES FROM `ReplicatedStorage.TrafficCars`, AND IT HAS TO. The obvious source is
	   `Workspace.CarSystem` — the roster the garage podiums are built from — and a client cannot use
	   it: StreamingEnabled is on, so `CarSystem` is not replicated to clients at all. `Market.luau`
	   still carries a note saying a client-side viewport is therefore impossible; it is out of date,
	   because `TrafficService` publishes a stripped shell of every ownable body into
	   `ReplicatedStorage` at startup for the traffic layer, and those shells are on every client
	   already. Nothing extra is replicated to make this work.

	   THAT FOLDER COVERS EVERY OWNABLE BODY, not by luck: a car is owned by being stolen off the
	   road, `TrafficConfig.AllBodies` is what the road can roll, and `GarageConfig.TierOfBody` is the
	   same authored ladder. A body missing from it is a body no player can have, so `set` returning
	   false is a genuinely empty case rather than a hole to paper over.

	2. IT IS A CLONE, ALWAYS, BECAUSE PAINTING IS ONE-WAY. `CarPaint` works by clearing the MeshPart
	   texture the roster's colour actually lives in (see its header), so painting a published shell
	   would strip the template every traffic car on the road is cloned from, and there is no undo.

	3. EVERY WELD DIES BEFORE ANY `CFrame` IS WRITTEN. The shell welds all ~25 meshes to its `Root`,
	   and writing `CFrame` on a part that is still welded drags the whole assembly instead of moving
	   the part — the same trap that once dragged a roster master across the map. Order matters here
	   and only here: strip, then place.

	4. THE CAMERA MOVES; THE CAR NEVER DOES. The clone has no PrimaryPart once `Root` is gone, so its
	   pivot is its own bounding-box centre and `Model:PivotTo` preserves each child's offset rather
	   than resetting it — re-posing a model that way COMPOUNDS, and the car winds itself up. The car
	   is placed once, centred on the origin, and everything after that is one camera CFrame.

	5. THE FRAMING IS FITTED TO THE BOX AND TO THE FRAME'S SHAPE. A card viewport is much wider than
	   it is tall and the results screen's is square, so a distance that fits one crops the other.
	   `set` takes the aspect rather than reading `AbsoluteSize`, because a card built this frame has
	   not been laid out yet and would measure 0 — pass the number you sized the frame with.

	6. A CAR CAN ALSO TURN, and only a big picture should. `CarViewport.spin` orbits the camera at a
	   distance settled once for the whole revolution, which is what keeps the car from breathing in
	   and out of the frame; the section at the bottom of this file has the reasoning. A card's
	   picture stays a still, because forty of them turning is forty cameras a frame.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CarPaint = require(ReplicatedStorage.shared.Modules.CarPaint)
--- A mutation's look on the picture (`Options.mutation`): the module every car in the world wears it by.
local CarMutation = require(ReplicatedStorage.shared.Modules.CarMutation)
--- `ViewportTint` on a mutation, for the looks a ViewportFrame cannot draw.
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local CarPlate = require(ReplicatedStorage.shared.Modules.CarPlate)
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)

local CarViewport = {}

-- The shell's own two structural parts (`TrafficService._buildShell`). Both are invisible; neither is
-- bodywork, and the `Hit` box in particular would frame the shot around a volume nobody can see.
local ROOT_NAME = "Root"
local HIT_NAME = "Hit"

local MODEL_NAME = "Car"

--[[ The pose. Shared with the results screen (`RaceUIController`) on purpose — a car looks the same
	in the garage as it does on the podium, which is the whole reason this is one module.

	`YAW` is measured in the car's own frame, where the nose is local -Z: 180 is nose-on, so 215 is a
	three-quarter front off the driver's side. `PITCH` is how far the camera sits above the car — high
	enough to read the roofline, well short of a plan view. `FOV` is narrow because a wide lens on a
	20-stud car bends it into a caricature. ]]
local YAW = 215
local PITCH = 15
local FOV = 30

--[[ How far off the tightest fit the camera sits. Over 1 backs it away, so the car has a little air
	round it rather than touching the edges of the frame; under 1 would crop it. Small, because the
	fit below is a real fit rather than an estimate that needs a safety factor — see `frameDistance`. ]]
local MARGIN = 1.04

-- Lighting, which has no relationship to the world's. Lifted ambient because the alternative is a
-- black silhouette: there is no sky and no bounce in a ViewportFrame, so anything the key light
-- misses is exactly as dark as it is left.
local AMBIENT = Color3.fromRGB(120, 126, 140)
local LIGHT = Color3.fromRGB(255, 250, 236)
local LIGHT_DIR = Vector3.new(-0.4, -1, -0.55).Unit

--[[ The colour the car's EDGES blend into, and not a background: `BackgroundTransparency` stays 1
	below, so nothing here is ever drawn as a fill.

	A ViewportFrame composites its 3D render against `BackgroundColor3` BEFORE the frame's
	transparency is applied. Every pixel the car only partly covers — which is the whole silhouette
	of it, one pixel wide — therefore comes out part car and part background colour whatever the
	transparency says, and `Instance.new` hands out `(163, 162, 165)`. That is the white outline
	traced round every car on the collection and dealership screens.

	Matching it to the card behind is the fix: the fringe pixel still blends, but it blends into the
	card and disappears. `#28334B` is the kit's card face — the Index slot square and the dealership's
	car card are both filled with it, and so is the page panel under them — so one default covers both
	callers, and a page built on other art passes its own. ]]
local BACKDROP = Color3.fromRGB(40, 51, 75)

--[[ === THE LOCKED LOOK ======================================================================

	A car nobody has found yet, on the collection screen: a flat cut-out of the right shape and
	nothing else. `silhouette` in the options below.

	IT IS FLAT ON PURPOSE, not "the car, but dark". A dark car still catches the key light down one
	flank and reads as a black car — which is a car you can identify, and there is one on the roster.
	A cut-out reads as an absence. So the lighting is inverted for this case rather than dimmed: FULL
	ambient and NO directional light, which is the one combination a ViewportFrame renders with no
	shading at all, so every surface comes out at exactly the colour it is painted and the whole model
	resolves to one silhouette.

	Painting the parts is still necessary and is not a second way of doing the same thing — it is what
	makes every surface the SAME colour, so the flat render has one colour to be. It also has to
	square up three things that would otherwise punch holes in the shape: the glass (which would show
	the panel straight through the greenhouse), any Neon lamp (self-lit, so it ignores the lighting
	above entirely), and the texture the roster's paint actually lives in. ]]
local SILHOUETTE_COLOR = Color3.fromRGB(13, 15, 21)
CarViewport.SilhouetteColor = SILHOUETTE_COLOR
local SILHOUETTE_AMBIENT = Color3.new(1, 1, 1)
local SILHOUETTE_LIGHT = Color3.new(0, 0, 0)

--[[ Everything in a cloned shell that can tie one of its parts to a part outside it.

	THE FOUR CLASSES ARE NOT ONE FAMILY, which is why this is a list rather than an `IsA` or two.
	`WeldConstraint` and `NoCollisionConstraint` descend from `Instance` DIRECTLY — they are neither
	`JointInstance` nor `Constraint`, whatever their names suggest — and `WeldConstraint` is the one
	class a shell is actually held together with. Miss it and note 3 above happens. ]]
local function tiesToAnotherPart(inst: Instance): boolean
	return inst:IsA("JointInstance")
		or inst:IsA("Constraint")
		or inst:IsA("WeldConstraint")
		or inst:IsA("NoCollisionConstraint")
end

--[[ Half the extent a part's box presents on each axis of the frame it is measured in.

	PROJECTED OFF THE BOX AXES RATHER THAN READ OUT OF `Size`, because the wheels are rotated about
	their axles: a wheel's `Size.Y` is not its vertical extent, and using it drops the car through the
	bottom of the frame by most of a wheel. It matters sideways too — several roster bodies are one
	mesh per material rather than per side, so a "part" can be both headlights at once and its box is
	nothing like axis-aligned. ]]
local function projectHalf(offset: CFrame, size: Vector3): Vector3
	local right, up, look = offset.RightVector, offset.UpVector, offset.LookVector
	return Vector3.new(
		0.5 * (math.abs(right.X) * size.X + math.abs(up.X) * size.Y + math.abs(look.X) * size.Z),
		0.5 * (math.abs(right.Y) * size.X + math.abs(up.Y) * size.Y + math.abs(look.Y) * size.Z),
		0.5 * (math.abs(right.Z) * size.X + math.abs(up.Z) * size.Y + math.abs(look.Z) * size.Z)
	)
end

--[[ The unit direction the camera looks from, in the car's own frame. Nose is local -Z; see `YAW`.

	`yaw` and `pitch` default to the pose above, which is every still picture in the game. The
	TURNTABLE passes a moving yaw (a spin is this same shot with one number moving), and a picture
	with a shot of its own (`Options.yaw`, the Play menu's hero) passes both. ]]
local function eyeDirection(yaw: number?, pitch: number?): Vector3
	local turn, tilt = math.rad(yaw or YAW), math.rad(pitch or PITCH)
	return Vector3.new(math.sin(turn) * math.cos(tilt), math.sin(tilt), math.cos(turn) * math.cos(tilt))
end

--[[ Every part's own eight corners, in the car's frame, from the offsets `set` has already placed
	them at.

	CORNERS RATHER THAN CENTRES OR `Size`, for the reason `projectHalf` above has at length: the
	wheels are rotated about their axles and several bodies are one mesh per material rather than per
	side, so a part's `Size` is not its extent and its centre is not an edge. ]]
local function cornersOf(placed: { [BasePart]: CFrame }): { Vector3 }
	local corners = {}
	for part, offset in placed do
		local half = part.Size / 2
		for x = -1, 1, 2 do
			for y = -1, 1, 2 do
				for z = -1, 1, 2 do
					table.insert(corners, offset * Vector3.new(half.X * x, half.Y * y, half.Z * z))
				end
			end
		end
	end
	return corners
end

--[[ How far the frame reaches across and up, per stud of depth. `MARGIN` is spent here rather than
	on the distance, so it is the same fraction of the frame whichever axis ends up binding — a
	margin added to a distance is not.

	`FieldOfView` is the VERTICAL angle (the default `FieldOfViewMode`), so the horizontal one is what
	gets widened by the aspect. Do it the other way round and every wide frame crops the car. ]]
local function reachOf(aspect: number): (number, number)
	local vTan = math.tan(math.rad(FOV) / 2) / MARGIN
	return vTan * math.max(aspect, 0.01), vTan
end

--[[ The corners as a camera at `yaw` sees them: the pose fixes the camera's ROTATION, so a corner's
	camera-space position is its car-space position turned by the inverse of it, with the distance
	left to fall out as a term in Z. Done once per yaw and read many times by the bisection. ]]
local function seenFrom(corners: { Vector3 }, yaw: number, pitch: number?): { Vector3 }
	local inverse = CFrame.lookAt(eyeDirection(yaw, pitch), Vector3.zero).Rotation:Inverse()
	local seen = table.create(#corners)
	for index, corner in corners do
		seen[index] = inverse * corner
	end
	return seen
end

--[[ Does a camera `distance` away hold every corner, and where does it have to be AIMED to do it?

	For a corner at camera-space `a`, a camera at distance `d` shifted by `u` sees it at depth
	`d - a.Z`, inside the frustum while

	    |a.X - u.X| <= (d - a.Z) * hTan          |a.Y - u.Y| <= (d - a.Z) * vTan

	which is an interval of allowed shifts per corner per axis. It fits when those intersect, and the
	aim returned is the middle of what is left. A corner BEHIND the camera gives a negative depth,
	which collapses the interval and reads as "does not fit" without needing a case of its own. ]]
local function aimFor(seen: { Vector3 }, distance: number, hTan: number, vTan: number): (boolean, number, number)
	local xLow, xHigh, yLow, yHigh = -math.huge, math.huge, -math.huge, math.huge
	for _, corner in seen do
		local depth = distance - corner.Z
		local reachX, reachY = depth * hTan, depth * vTan
		xLow, xHigh = math.max(xLow, corner.X - reachX), math.min(xHigh, corner.X + reachX)
		yLow, yHigh = math.max(yLow, corner.Y - reachY), math.min(yHigh, corner.Y + reachY)
	end
	return xLow <= xHigh and yLow <= yHigh, (xLow + xHigh) / 2, (yLow + yHigh) / 2
end

--[[ The nearest distance that holds this car in a frame of this shape.

	=== IT FITS THE PARTS, NOT THE CAR'S BOUNDING BOX ==========================================

	A car's bounding box has material at none of its eight corners: the roofline stops well short of
	the nose, and the box's top-front and bottom-rear corners — the two the tilt drives furthest apart
	on screen — are empty air. Framing to the box therefore frames a volume noticeably taller than the
	car looks, and the car sits marooned in the middle of a card it ought to be filling.

	=== AND THE CAMERA MAY SLIDE TO CENTRE WHAT IT FOUND =======================================

	Which is where most of the frame actually comes from, and is not obvious. A car centred on its own
	box does NOT come out centred on screen once the camera is tilted above it: the near-side sill
	projects much further down than the far-side roof projects up, and on the roster's bodies it lands
	about a fifth of the frame low. Fitting a shot that is off-centre wastes twice the offset in empty
	frame — the Sian, the widest body here, was filling 64% of the width with the camera aimed at its
	box centre and fills it with the camera aimed where the car actually is.

	So the answer wanted is the smallest distance whose intervals (`aimFor`) still intersect. Those
	only ever widen as the camera backs away, so it is a bisection, and both ends of the bracket are
	known answers rather than guesses: FAR is the distance that fits with the camera aimed dead at the
	car's centre — the largest demand any one corner makes of an unshifted camera, and the shot this
	would be without the slide — and NEAR is the nearest corner, from where the car is partly behind
	the camera and nothing fits at all. Eighteen halvings of a range under a hundred studs lands
	inside a thousandth of a stud. ]]
local function fitDistance(seen: { Vector3 }, hTan: number, vTan: number): number
	local near, far = -math.huge, 0
	for _, corner in seen do
		near = math.max(near, corner.Z)
		far = math.max(far, corner.Z + math.abs(corner.X) / hTan, corner.Z + math.abs(corner.Y) / vTan)
	end

	for _ = 1, 18 do
		local middle = (near + far) / 2
		if (aimFor(seen, middle, hTan, vTan)) then
			far = middle
		else
			near = middle
		end
	end
	return far
end

--[[ The camera, `distance` away at `yaw`, aimed where the car actually is.

	The shift is multiplied on the RIGHT, so it is in the camera's own right and up axes and the pose
	is untouched: it is a lens shift rather than a new angle. The camera no longer looks at the car's
	centre, which is the entire point. ]]
local function cameraAt(seen: { Vector3 }, yaw: number, distance: number, hTan: number, vTan: number, pitch: number?): CFrame
	local _, shiftX, shiftY = aimFor(seen, distance, hTan, vTan)
	return CFrame.lookAt(eyeDirection(yaw, pitch) * distance, Vector3.zero) * CFrame.new(shiftX, shiftY, 0)
end

--- Where the camera goes to hold this car at the pose above (or at `yaw`/`pitch`, a shot of its
--- own), filling a frame of this aspect. `placed` is every part at the offset it has already been
--- moved to.
local function cameraFor(placed: { [BasePart]: CFrame }, aspect: number, yaw: number?, pitch: number?): CFrame
	local corners = cornersOf(placed)
	if #corners == 0 then
		return CFrame.lookAt(eyeDirection(yaw, pitch), Vector3.zero)
	end
	local hTan, vTan = reachOf(aspect)
	local seen = seenFrom(corners, yaw or YAW, pitch)
	return cameraAt(seen, yaw or YAW, fitDistance(seen, hTan, vTan), hTan, vTan, pitch)
end

--[[ Flatten a car into one shape, for the locked look above.

	EVERY PART, not the paintwork. `CarPaint` deliberately leaves the wheels, glass and lamps alone —
	that is the whole of what it is for — and every one of them is exactly what has to go here. There
	is no shared rule to reuse: "which parts are the car's colour" and "which parts are the car" are
	different questions with different answers.

	Nothing is remembered for putting back, because nothing ever is: this runs on a fresh clone that
	is thrown away when the slot unlocks or scrolls off. ]]
local function flatten(model: Model)
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		--[[ A ColorMap beats `Color` outright, same as a TextureID does, so a panel wearing one would
			be the only part of the car that still showed its paint — a single lit door on a cut-out.
			Unparented rather than destroyed only out of habit from `CarPaint`; this clone has no way
			back. ]]
		local surface = part:FindFirstChildOfClass("SurfaceAppearance")
		if surface then
			surface.Parent = nil
		end
		if part:IsA("MeshPart") then
			part.TextureID = ""
		end
		part.Color = SILHOUETTE_COLOR
		-- SmoothPlastic and no reflectance: nothing left that can catch a highlight and hint at a
		-- surface, in case this is ever shown under a light that is not the flat one above.
		part.Material = Enum.Material.SmoothPlastic
		part.Reflectance = 0
		part.Transparency = 0
	end
end

-- The published shells. Looked up per call rather than latched, because they are published at server
-- startup and a page can be built before that has replicated — a latched nil would be permanent.
local function templates(): Instance?
	return ReplicatedStorage:FindFirstChild(TrafficConfig.TemplateFolderName)
end

--- Is there a body to show for this name? Cheap; no clone, no build.
function CarViewport.has(body: unknown): boolean
	if type(body) ~= "string" then
		return false
	end
	local folder = templates()
	local template = folder and folder:FindFirstChild(body)
	return template ~= nil and template:IsA("Model")
end

--[[ An empty viewport, ready to be handed a car. Parented, invisible, and costing nothing until
	`set` puts something in it — a ViewportFrame with no children renders nothing.

	`ImageTransparency` IS THE FADE on one of these: it is the RENDERED SCENE's transparency, so a
	caller dimming a card (the dealership fades the cars parked on other bays) writes one number here
	rather than walking 25 parts.

	`backdrop` is the colour of whatever this is being laid on, and it is only ever seen one pixel at
	a time round the edge of the car — see `BACKDROP`. The default is the kit's card, which is what
	both callers put one of these on. ]]
function CarViewport.new(parent: GuiObject, name: string?, backdrop: Color3?): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = name or "CarView"
	viewport.BackgroundTransparency = 1
	viewport.BackgroundColor3 = backdrop or BACKDROP
	viewport.BorderSizePixel = 0
	viewport.Ambient = AMBIENT
	viewport.LightColor = LIGHT
	viewport.LightDirection = LIGHT_DIR
	viewport.Visible = false
	--[[ No `WorldModel`: nothing in here is simulated, jointed or lit by anything but the three
		properties above, and a WorldModel would only add a physics-capable container for a model
		whose every part arrives anchored.

		`Active` STAYS FALSE, which is what lets a card keep working as a button with this sitting on
		top of it — an active GuiObject swallows the click. ]]
	local camera = Instance.new("Camera")
	camera.FieldOfView = FOV
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	viewport.Parent = parent
	return viewport
end

--- Empty a viewport and hide it. Safe to call on one that is already empty.
function CarViewport.clear(viewport: ViewportFrame)
	local car = viewport:FindFirstChild(MODEL_NAME)
	if car then
		car:Destroy()
	end
	viewport.Visible = false
end

--[[ What a car is being shown as.

	`paint` is a palette index; nothing, or a Stock index, leaves the body in the livery its artist
	gave it. `aspect` is width/height of the frame this is going in — passed rather than measured, see
	header note 5. `silhouette` draws the locked cut-out instead of the car, and ignores `paint`
	because a shape has no colour. ]]
export type Options = {
	paint: number?,
	aspect: number?,
	silhouette: boolean?,
	--- A weather mutation key: the car drawn RUSTED / GHOST / ... (2026-10-14: an inventory full of
	--- mutated cars drew them all plain). Colours and materials show; its particles do not render here.
	mutation: string?,
	--[[ A SHOT OF ITS OWN, for the one picture on a screen that is the screen's subject rather than a
		card in a grid: the Play menu's hero banner (2026-10-25). Nil is the shared pose, which is what
		every card wants and why it is the default; see `YAW` for what the numbers mean. ]]
	yaw: number?,
	pitch: number?,
	--[[ ...and a key light of its own. `LIGHT_DIR` arrives from behind the car's far shoulder as the
		shared pose sees it, so the flank facing the lens is lit by the ambient alone and a red car reads
		maroon; a banner that big shows it. Nil is the shared light. Written on every `set`, so a viewport
		handed a hero shot once does not keep its light for the next car. ]]
	light: Vector3?,
	ambient: Color3?,
}

--[[ Put a body in this viewport. Returns false — leaving the frame empty and hidden — when there is
	no such body published, which is the one failure mode and is not worth a warning on a screen that
	draws a card per car. ]]
local function fitViewportMaterials(model: Model)
	-- ForceField depends on world rendering; use a visible spectral finish in menu portraits.
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Material == Enum.Material.ForceField then
			part.Material = Enum.Material.Neon
			part.Transparency = math.max(part.Transparency, 0.2)
		end
	end
end

function CarViewport.set(viewport: ViewportFrame, body: unknown, options: Options?): boolean
	local settings = options or {}
	CarViewport.clear(viewport)
	if type(body) ~= "string" then
		return false
	end

	local folder = templates()
	local template = folder and folder:FindFirstChild(body)
	if not (template and template:IsA("Model")) then
		return false
	end

	local clone = template:Clone()
	clone.Name = MODEL_NAME

	--[[ The frame everything is measured and re-expressed in: the shell's `Root`, which
		`TrafficService` puts at the car's pivot dropped to the ground with the nose down its own
		LookVector. `GetPivot` is the fallback for a hand-made template with no PrimaryPart, and it is
		only a fallback: with no primary part it is a WORLD axis-aligned box centre with no rotation
		worth having, and the templates do not sit at world identity. ]]
	local root = clone.PrimaryPart or clone:FindFirstChild(ROOT_NAME)
	local frame = if root and root:IsA("BasePart") then root.CFrame else clone:GetPivot()
	local inverse = frame:Inverse()

	--[[ Strip first, place second. Every weld in here points at `Root`, and a write to a welded
		part's CFrame moves the assembly rather than the part — header note 3. The shells are
		published with nothing but render children on them (`TrafficService._buildShell` drops the
		rest), so joints are the whole list of what has to go. ]]
	local offsets: { [BasePart]: CFrame } = {}
	local low: Vector3?, high: Vector3? = nil, nil
	for _, descendant in clone:GetDescendants() do
		if tiesToAnotherPart(descendant) then
			descendant:Destroy()
		end
	end
	for _, descendant in clone:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end
		if descendant.Name == ROOT_NAME or descendant.Name == HIT_NAME then
			descendant:Destroy() -- structural, invisible, and not part of the car's shape
			continue
		end
		descendant.Anchored = true
		descendant.CanCollide = false
		descendant.CanQuery = false
		descendant.CanTouch = false
		descendant.CastShadow = false

		local offset = inverse * descendant.CFrame
		offsets[descendant] = offset
		local half = projectHalf(offset, descendant.Size)
		low = if low then low:Min(offset.Position - half) else offset.Position - half
		high = if high then high:Max(offset.Position + half) else offset.Position + half
	end

	if not (low and high) then
		clone:Destroy() -- a shell of no visible parts: nothing to show, and nothing to frame on
		return false
	end

	--[[ Moved onto the origin, centred on its own box rather than on the shell's frame — the shell's
		`Root` sits on the ground under the pivot, half a car below where the middle of it is.

		STILL NECESSARY EVEN THOUGH THE CAMERA CENTRES ITSELF. The camera can slide across the shot but
		never along it, so a car parked away from the origin would be fitted by BACKING OFF until it
		came into frame — the fit would be answering "how far is it" rather than "how big is it". ]]
	local centre = (low + high) / 2
	for part, offset in offsets do
		local placed = CFrame.new(-centre) * offset
		part.CFrame = placed
		offsets[part] = placed -- the framing below measures where the parts ARE, not where they were
	end

	--[[ Finished while still unparented, alongside the placement above and for the same reason: the
		car appears in the frame done rather than in its stock livery for a frame.

		THE LIGHTING IS WRITTEN ON BOTH BRANCHES, not just the locked one. A viewport outlives what is
		in it — the collection screen's slots keep theirs and swap the car out the moment the body is
		stolen — so a frame that had been a cut-out would stay unlit under the real car. ]]
	if settings.silhouette then
		viewport.Ambient = SILHOUETTE_AMBIENT
		viewport.LightColor = SILHOUETTE_LIGHT
		flatten(clone)
		--[[ The plate goes out with the lights. A cut-out is a car this player has not found yet, and
			a `SurfaceGui` is not a `BasePart` — `flatten` cannot reach it — so left alone it renders a
			perfectly legible number floating on an otherwise blacked-out shape. ]]
		local plate = CarPlate.label(clone)
		if plate then
			plate.Visible = false
		end
	else
		local ambient = settings.ambient or AMBIENT
		viewport.Ambient = ambient
		viewport.LightColor = LIGHT
		viewport.LightDirection = settings.light or LIGHT_DIR
		-- A stock index paints nothing, and that is correct: the car is already wearing its own.
		CarPaint.apply(clone, settings.paint, body)
		--- After the paint, as on the road and the podium: the mutation dresses over whatever colour it is.
		if settings.mutation then
			CarMutation.apply(clone, settings.mutation, false)
			fitViewportMaterials(clone)
			--[[ A mutation whose look a ViewportFrame cannot draw (`ViewportTint`: Soaked's glass has
				nothing to reflect, Charged is sparks and an outline) lights the car in its colour
				instead, so the card still shows a car that is not stock. Reset with the paint above on
				the next car. ]]
			local mutation = WeatherConfig.mutationOf(settings.mutation)
			if mutation and mutation.ViewportTint and typeof(mutation.Color) == "Color3" then
				viewport.LightColor = mutation.Color
				viewport.Ambient = ambient:Lerp(mutation.Color, 0.4)
			end
		end
		--[[ And its number, hashed out of the same body-and-colour pair (`PlateConfig.forKey`), so
			the card on this page reads the same plate as the car it is a picture of — the one on the
			podium and the one parked in the street. The shells are published wearing the roster's
			placeholder, so without this every card on the page reads the same number. ]]
		CarPlate.apply(clone, body, settings.paint)
	end
	clone.Parent = viewport

	local camera = viewport.CurrentCamera
	if camera then
		camera.CFrame = cameraFor(offsets, settings.aspect or 1, settings.yaw, settings.pitch)
	end

	viewport.Visible = true
	return true
end

-- === The turntable ==========================================================
--[[ A car that turns on the spot, for a panel big enough to be worth watching: the detail wings on
	the cars inventory and the car picker (`Components/CarDetailV2`). A card's picture is still a
	still — forty of them turning is forty cameras a frame for a picture the size of a thumbnail.

	=== THE WHOLE SHOT IS SETTLED ONCE AND ONLY THE YAW MOVES =================================

	Which is the whole design of it, and both halves of it were learned the same way: in motion.

	RE-FITTING THE DISTANCE PER FRAME BREATHES. A car is three times longer than it is wide, so a fit
	that is honest at every yaw pulls the camera in and pushes it out twice a turn, and the car pulses
	in the frame like a lens hunting focus.

	AND RE-AIMING PER FRAME SWINGS, which is the same mistake one step further in and was this file's
	first answer: hold the distance, and keep the car centred per frame as its silhouette changes
	shape. It reads wrong for a reason that only shows up once it is turning. THE AIM THAT CENTRES A
	SILHOUETTE IS NOT SYMMETRIC UNDER A PERSPECTIVE CAMERA: a corner nearer the lens has less frame to
	reach across than a far one (`aimFor`'s `depth`), so on a long body the aim leans towards whichever
	END IS NEARER, and the two ends swap twice a revolution. Measured on the Camaro in the detail
	wings, sampling a whole turn: the aim swept 6.2 studs, a QUARTER of the frame's width, and the car
	slid from side to side across the panel instead of turning on the spot. Dylan, 2026-09-17: "why
	does the car do a weird rotation? Maybe it should rotate from one point."

	So ONE distance and ONE lens shift are chosen for the whole revolution — the closest the camera can
	stand while a single shift holds every sampled yaw. The car is centred on the origin (`set` puts it
	there) and the shift is a constant in the camera's own axes, so the origin lands on the same pixel
	at every yaw: the car turns about a point that does not move, which is what was asked for. It is
	also cheaper than what it replaced, since a frame is now a `lookAt` and a multiply with no pass
	over the car's corners at all.

	SAMPLED RATHER THAN SOLVED. The worst yaw is nearly always side-on, but "nearly" is doing work
	there: the tilt means the roofline and the sills swap which of them is binding as the car turns,
	and a wing mirror or a spoiler can take a body past its own side view. Sixteen samples is every
	22.5 degrees, and they are answered together, by the same bisection a still picture pays for once.

	IT IS THE CAMERA THAT MOVES, not the car — header note 4, and it is not a preference. The clone
	has no PrimaryPart once `Root` is gone, so `Model:PivotTo` would preserve each child's offset
	rather than reset it, and re-posing that way COMPOUNDS: the car would wind itself up. ]]
local TURN_SAMPLES = 16

--[[ Degrees a second. A showroom turntable rather than a display stand: a full revolution in about
	fourteen seconds, which is slow enough that nothing on the car smears and quick enough that a
	player who looks at the panel for two seconds sees it move. ]]
local TURN_SPEED = 26

--[[ The shot a whole turntable is drawn from: how far the camera stands, and the ONE lens shift that
	holds the car at every yaw it is going to pass through.

	IT IS `fitDistance` WITH THE SAMPLES INTERSECTED AS WELL AS THE CORNERS. A shift is applied in the
	camera's own right and up axes, so one pair of numbers means the same thing in every sample's own
	frame and the intersection of their intervals is exactly the constraint on it. The intervals only
	widen as the camera backs away, so it is the same bisection, and both ends of the bracket are
	still known answers: FAR is the distance at which an UNSHIFTED camera holds every sample (each
	sample's own `far`, the largest taken), and NEAR is the nearest corner any of them has, from where
	part of the car is behind the camera and nothing fits at all. ]]
local function turntableShot(corners: { Vector3 }, hTan: number, vTan: number): (number, number, number)
	local views = table.create(TURN_SAMPLES)
	for sample = 0, TURN_SAMPLES - 1 do
		views[sample + 1] = seenFrom(corners, YAW + sample * 360 / TURN_SAMPLES)
	end

	local near, far = -math.huge, 0
	for _, seen in views do
		for _, corner in seen do
			near = math.max(near, corner.Z)
			far = math.max(far, corner.Z + math.abs(corner.X) / hTan, corner.Z + math.abs(corner.Y) / vTan)
		end
	end

	--- Every sample at once: it holds when one shift is legal in all of them.
	local function holds(distance: number): (boolean, number, number)
		local xLow, xHigh, yLow, yHigh = -math.huge, math.huge, -math.huge, math.huge
		for _, seen in views do
			for _, corner in seen do
				local depth = distance - corner.Z
				local reachX, reachY = depth * hTan, depth * vTan
				xLow, xHigh = math.max(xLow, corner.X - reachX), math.min(xHigh, corner.X + reachX)
				yLow, yHigh = math.max(yLow, corner.Y - reachY), math.min(yHigh, corner.Y + reachY)
			end
		end
		return xLow <= xHigh and yLow <= yHigh, (xLow + xHigh) / 2, (yLow + yHigh) / 2
	end

	for _ = 1, 18 do
		local middle = (near + far) / 2
		if (holds(middle)) then
			far = middle
		else
			near = middle
		end
	end

	local _, shiftX, shiftY = holds(far)
	return far, shiftX, shiftY
end

--- What a spin is being turned at. `aspect` is the frame's width over its height, passed rather than
--- measured for the same reason `set` takes one — see header note 5.
export type SpinOptions = {
	aspect: number?,
	degreesPerSecond: number?,
}

--- A spin in progress. `stop` is idempotent and is the only thing a caller ever needs.
export type Spin = {
	stop: () -> (),
}

--[[ Turn the car already in this viewport. Nil when there is nothing in it to turn, which is the
	same empty case `set` returns false for and wants no warning either.

	IT STOPS ITSELF when the car or the frame goes, so a page that forgets to is a page that leaks
	nothing. Stop it by hand anyway when the panel is put away: the connection is a callback a frame
	doing real arithmetic, and a panel nobody is looking at should cost nothing at all. ]]
function CarViewport.spin(viewport: ViewportFrame, options: SpinOptions?): Spin?
	local settings = options or {}
	local camera = viewport.CurrentCamera
	local model = viewport:FindFirstChild(MODEL_NAME)
	if not (camera and model and model:IsA("Model")) then
		return nil
	end

	--- Where `set` left every part. The car is not moved again; see the section header.
	local placed: { [BasePart]: CFrame } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			placed[descendant] = descendant.CFrame
		end
	end

	local corners = cornersOf(placed)
	if #corners == 0 then
		return nil
	end

	local hTan, vTan = reachOf(settings.aspect or 1)
	local radius, shiftX, shiftY = turntableShot(corners, hTan, vTan)
	--- The lens shift, made once. A frame of the turn is this multiplied onto a `lookAt` and nothing
	--- else, which is the whole of what makes the car turn about a point that does not move.
	local aim = CFrame.new(shiftX, shiftY, 0)

	local speed = settings.degreesPerSecond or TURN_SPEED
	--- Started at the pose every still picture uses, so a car that appears and then begins to turn
	--- has not jumped to a different shot first.
	local yaw = YAW
	local connection: RBXScriptConnection? = nil

	local spin = {}
	function spin.stop()
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end

	local function step(delta: number)
		--- The car or the frame has gone: a card scrolled off, a page was rebuilt, the panel was
		--- handed another car. Nothing to turn and nobody to tell.
		if model.Parent ~= viewport or not viewport:IsDescendantOf(game) then
			spin.stop()
			return
		end
		yaw = (yaw + speed * delta) % 360
		camera.CFrame = CFrame.lookAt(eyeDirection(yaw) * radius, Vector3.zero) * aim
	end

	--- The first frame is drawn here rather than a sixtieth of a second from now, so the car is at
	--- the turntable's distance the moment it appears instead of stepping back into it.
	step(0)
	connection = RunService.RenderStepped:Connect(step)
	return spin
end

-- === The entrance ===========================================================
--[[ A car that SWINGS INTO its still instead of appearing in it: the Play menu's hero, each time the
	screen opens or a car is picked (2026-10-25). The camera starts `swing` degrees further round and
	`pull` times further out, and eases onto exactly the shot `set` left, so its last frame IS the
	still and nothing jumps when it stops.

	TWO FITS, NOT ONE A FRAME. The start and the end are each fitted once (`fitDistance` and its aim,
	the pair a still pays for) and the frames between interpolate the yaw, the distance and the lens
	shift. A fit per frame is the turntable's "breathing" (its section above); over half a second,
	easing in, a moving distance reads as the dolly it is meant to be instead.

	A ONE-SHOT, NOT A LOOP. It stops itself when it lands, and the handle's `stop` is the same
	idempotent stop a spin hands back, for a page put away mid-swing. ]]
local ARRIVE_SWING = 40
local ARRIVE_PULL = 1.12
local ARRIVE_SECONDS = 0.55

export type ArriveOptions = {
	aspect: number?,
	--- The still it lands on: the same two numbers `set` was given, or nil for the shared pose.
	yaw: number?,
	pitch: number?,
	--- Degrees round from the still that it starts at; positive starts it nearer side-on.
	swing: number?,
	--- How much further out it starts, as a multiple of the distance that fits the car there.
	pull: number?,
	seconds: number?,
}

--[[ Swing the car already in this viewport into its still. Nil when there is nothing in it, the same
	empty case `set` returns false for. Call it straight after `set`, with the same aspect and pose. ]]
function CarViewport.arrive(viewport: ViewportFrame, options: ArriveOptions?): Spin?
	local settings = options or {}
	local camera = viewport.CurrentCamera
	local model = viewport:FindFirstChild(MODEL_NAME)
	if not (camera and model and model:IsA("Model")) then
		return nil
	end

	--- Where `set` left every part, exactly as the turntable reads them.
	local placed: { [BasePart]: CFrame } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			placed[descendant] = descendant.CFrame
		end
	end
	local corners = cornersOf(placed)
	if #corners == 0 then
		return nil
	end

	local hTan, vTan = reachOf(settings.aspect or 1)
	local pitch = settings.pitch
	local landYaw = settings.yaw or YAW
	local startYaw = landYaw + (settings.swing or ARRIVE_SWING)
	--- One end of the swing: how far out, and the lens shift that centres the car from there.
	local function shot(yaw: number, pull: number): (number, number, number)
		local seen = seenFrom(corners, yaw, pitch)
		local distance = fitDistance(seen, hTan, vTan) * pull
		local _, shiftX, shiftY = aimFor(seen, distance, hTan, vTan)
		return distance, shiftX, shiftY
	end
	local fromDistance, fromX, fromY = shot(startYaw, settings.pull or ARRIVE_PULL)
	local toDistance, toX, toY = shot(landYaw, 1)
	local seconds = math.max(settings.seconds or ARRIVE_SECONDS, 1e-3)

	local elapsed = 0
	local connection: RBXScriptConnection? = nil
	local arrival = {}
	function arrival.stop()
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end

	local function step(delta: number)
		if model.Parent ~= viewport or not viewport:IsDescendantOf(game) then
			arrival.stop()
			return
		end
		elapsed = math.min(elapsed + delta, seconds)
		local t = TweenService:GetValue(elapsed / seconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		local yaw = startYaw + (landYaw - startYaw) * t
		local distance = fromDistance + (toDistance - fromDistance) * t
		local shift = CFrame.new(fromX + (toX - fromX) * t, fromY + (toY - fromY) * t, 0)
		camera.CFrame = CFrame.lookAt(eyeDirection(yaw, pitch) * distance, Vector3.zero) * shift
		if elapsed >= seconds then
			arrival.stop()
		end
	end

	--- The first frame is drawn here, so the car never shows at its still for a frame and then jumps
	--- back to where the swing starts.
	step(0)
	connection = RunService.RenderStepped:Connect(step)
	return arrival
end

return CarViewport
