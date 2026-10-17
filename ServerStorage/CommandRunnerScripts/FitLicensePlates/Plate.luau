--[[
	FitLicensePlates/Plate — the fitting geometry

	Puts one number plate on the back of a CarBones rig: where it goes, how big it is, and how it
	is welded on. `init.luau` is the Command Runner wrapper around this; everything that decides
	what the plate looks like is here.

	=== WHERE THE PLATE GOES ===================================================

	Not a hardcoded offset, because the roster is 63 differently-proportioned bodies on one chassis
	(8.5-12.9 studs wide, supercars to hatchbacks) and any single offset is inside the bodywork on
	half of them. It is RAYCAST, from the car's own wheel-centre frame — the same frame
	`RigCarBody` builds, and for the same reason: a Blender export and CarBones disagree about
	which axis is forward, so the four wheel centres are the only thing that reliably says.

		the rearmost point on the CENTRELINE whose surface faces backwards,
		searched between 18% and 55% of the body's height.

	Both ends of that band are load-bearing. Without the 18% floor the search finds the diffuser lip
	on every mid-engined car and the plate ends up scraping the road (the F5 and the Roadster both
	did, on 2026-08-20). Without the 55% ceiling it finds the rear WING on the cars that have one,
	and hangs the plate off the spoiler. In between, "rearmost point that faces backwards" is the
	rear bumper on essentially every body in the pack, which is where a plate belongs.

	On top of that, a plate that lands in the bottom 24% is offered a LIFT: the search is re-run
	with the floor at 24% and the higher answer taken, but only if it does not have to stand proud
	to get there. That is the R34, whose bumper is a tall flat face — rearmost alone put its plate
	half off the bottom edge next to the exhaust, and 24% puts it in the middle of the panel for
	0.01 studs of standoff. It is also why the lift is conditional rather than just a higher floor:
	on the F5 the same move costs 0.37 studs and the plate hangs in the air, so the F5 keeps the
	low answer, which is where a mid-engined car's plate goes anyway.

	TWO TIDIER RULES WERE MEASURED ACROSS THE ROSTER ON 2026-08-20 AND ARE BOTH WORSE.
	Taking the CENTRE of the tallest rear-facing band fixes the R34 and breaks the Sian and the
	918, walking their plates off the valance and up onto the engine deck — on a mid-engined body
	the tallest flat rear-facing surface is not the bumper. Taking the HIGHEST point within a few
	hundredths of the rearmost breaks far more: the Camaro's bumper is flat enough over its whole
	height that the plate climbs to 54% and lands between the taillights. Rearmost-within-a-band is
	the cruder rule and the one that is right more often.

	=== THE ROTATION IS AXIS-ALIGNED TO THE MOUNT, AND IT HAS TO BE =============

	This is the one thing here that is not a taste call, and it is invisible until a real client
	looks at the car.

	The first version pitched the plate to match the surface it sat on, so it hugged a sloped
	bumper. On the SERVER that is exactly what you get. On a STREAMING CLIENT the plate arrives in
	the right place with its rotation snapped to the mount's own — a plate lying flat, facing into
	the boot. Every other mesh in the dress survives the trip, and the difference is that all of
	them sit at an exact 90-degree multiple from `RedressMount` and the tilted plate did not.
	Measured both ways in a playtest on 2026-08-20: at (-8, 180, 0) off the mount the client read
	(0, 0, 0); re-welded at exactly (0, 180, 0) the client read (0, 180, 0).

	So the plate's rotation is taken from the MOUNT and yawed a clean half-turn, never from the
	raycast normal. Only the POSITION comes out of the fit. A vertical plate is also the truer
	answer — real ones are — and `standoff` below is what stops that costing anything.

	=== IT NEVER SINKS INTO THE BODYWORK =======================================

	A vertical plate on a bumper that slopes would bury one edge. `standoff` casts a 3x3 grid over
	the plate's own footprint and takes the deepest hit, so the plate is pushed out far enough that
	no corner is inside the panel. Most bodies come back 0.00 — flat enough that it costs nothing —
	and the handful that don't get the few hundredths they need.

	=== TWO SCALES, NOT ONE ====================================================

	Width and height scale together off the authored art. DEPTH DOES NOT, and scaling it uniformly
	is a bug you can see: at 2.2 studs wide the plate would be 0.05 studs thick, the white face and
	the frame it sits in land inside the same depth quantum, and the frame's mounting notches
	z-fight into a shimmering mess. The frame gets an absolute depth instead, which reads as a
	chunky toon plate rather than a decal and separates the two meshes properly.

	`RenderFidelity.Precise` for the same class of reason: at this size Automatic swaps in the
	crudest LOD, which closes the frame's opening and turns the plate into a white blob.

	=== NAMING IS A CONTRACT ===================================================

	`plate_frame` / `plate_face`. `plate` is a hardware token in `Modules/CarPaint`, so neither
	part is ever swept into a repaint by sharing a texture — a body-coloured number plate is the
	obvious way this looks broken. Neither name carries `body`, which would override that veto, and
	neither matches `^shell_%d+_body$`, which is what keeps `Modules/CarDoorRig` from deciding the
	plate is a door.

	The text is a SurfaceGui on `plate_face`. Two clone filters strip everything that isn't a
	render class off a dress part — `TrafficService._buildShell` and `CarBody.swapMeshes` — and
	both list `SurfaceGui` so the plate arrives with its text on a traffic car and on a stolen one.

	=== WHAT IT SAYS IS NOT THIS MODULE'S JOB ==================================

	At runtime the text is owned by `Configs/PlateConfig` and written by `Modules/CarPlate` — a car
	you own is plated off its identity, a car on the road rolls one per spawn. What this command
	writes is the state a rig is in before any of that runs, so it asks the same config for the
	same answer (`Plate.textFor`) rather than inventing a placeholder: the roster in Studio then
	looks like the roster in the game.
]]

local CORNERS = { "FL", "FR", "RL", "RR" }
local MOUNT_NAME = "RedressMount"
local HULL_NAME = "HitBox"
local PLATE_PREFIX = "plate_"
local FRAME_NAME = "plate_frame"
local FACE_NAME = "plate_face"
local TEXT_NAME = "PlateText"
-- What a plate reads when `PlateConfig` cannot be reached at all. See `Plate.textFor`.
local FALLBACK_TEXT = "STEAL"

local Plate = {}

Plate.Defaults = {
	-- Plate width in studs. The pack's bodies run 8.5-12.9 wide, so 2.2 is 17-26% of a car's
	-- width — near the real 12"-on-a-6ft-car ratio, and still legible from the chase camera.
	Width = 2.2,
	-- Absolute frame depth. See the header: this is deliberately not the width's scale factor.
	Depth = 0.14,
	-- How far proud of the bodywork the plate's own front face sits, on top of `standoff`.
	Proud = 0.01,
	-- The slice of the body's height the rear surface is searched in.
	BandLow = 0.18,
	BandHigh = 0.55,
	-- Where a plate would rather sit than the bottom of the band, and the standoff that buys the
	-- lift back off again. See `chooseAnchor`.
	Prefer = 0.24,
	MaxStandoff = 0.08,
	--[[ EMPTY MEANS "GIVE EACH CAR ITS OWN", which is the normal case — see `Plate.textFor`. A
		non-empty string here (or in the command's `Text` argument) puts that one string on every car
		it fits, which is what you want when you are looking at placement rather than at plates. ]]
	Text = "",
}

Plate.Font = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)
Plate.Ink = Color3.fromRGB(27, 42, 53)

--[[ The car's own frame, built from the four wheel centres: +X right, +Y up, +Z REARWARD.

	Same construction as `RigCarBody`, and nil for anything that isn't a CarBones rig. Note the
	sign — this frame's `LookVector` is the car's forward, so local +Z is the back of the car,
	which is the direction everything below measures in. ]]
function Plate.carFrame(car: Model): CFrame?
	local chassis = car and car:FindFirstChild("Chassis")
	if not chassis then
		return nil
	end
	local wheels = {}
	for _, corner in CORNERS do
		local suspension = chassis:FindFirstChild("Suspension" .. corner)
		local wheel = suspension and suspension:FindFirstChild("Wheel")
		if not (wheel and wheel:IsA("BasePart")) then
			return nil
		end
		wheels[corner] = wheel.Position
	end
	local front = (wheels.FL + wheels.FR) * 0.5
	local rear = (wheels.RL + wheels.RR) * 0.5
	local left = (wheels.FL + wheels.RL) * 0.5
	local right = (wheels.FR + wheels.RR) * 0.5
	local forward = (front - rear).Unit
	local across = (right - left).Unit
	local up = across:Cross(forward).Unit
	local origin = (wheels.FL + wheels.FR + wheels.RL + wheels.RR) * 0.25
	return CFrame.fromMatrix(origin, forward:Cross(up).Unit, up, -forward)
end

--[[ The bodywork the fit is measured against: everything visible under `Body/` except the
	chassis's own hull, the four wheel visuals and any plate already on the car.

	The wheels come out because they are the widest thing at bumper height on most of the pack and
	a wheel arch is not a surface to hang a plate off. The existing plate comes out so a re-run
	measures the car rather than its own last answer. ]]
function Plate.dressParts(car: Model): { BasePart }
	local body = car and car:FindFirstChild("Body")
	local out = {}
	if not body then
		return out
	end
	local corners = {}
	for _, corner in CORNERS do
		corners[corner] = body:FindFirstChild(corner)
	end
	for _, inst in body:GetDescendants() do
		if not (inst:IsA("BasePart") and inst.Name ~= HULL_NAME and inst.Transparency < 1) then
			continue
		end
		if string.sub(inst.Name, 1, #PLATE_PREFIX) == PLATE_PREFIX then
			continue
		end
		local onAWheel = false
		for _, model in corners do
			if model and inst:IsDescendantOf(model) then
				onAWheel = true
				break
			end
		end
		if not onAWheel then
			table.insert(out, inst)
		end
	end
	return out
end

-- The box `parts` occupy in `frame`, corner by corner. Part bounding boxes rather than mesh
-- geometry, which is the same approximation the rest of the car tooling makes.
function Plate.localBounds(parts: { BasePart }, frame: CFrame): (Vector3, Vector3)
	local min = Vector3.new(math.huge, math.huge, math.huge)
	local max = -min
	for _, part in parts do
		local rel = frame:ToObjectSpace(part.CFrame)
		local half = part.Size * 0.5
		for x = -1, 1, 2 do
			for y = -1, 1, 2 do
				for z = -1, 1, 2 do
					local corner = rel * Vector3.new(half.X * x, half.Y * y, half.Z * z)
					min, max = min:Min(corner), max:Max(corner)
				end
			end
		end
	end
	return min, max
end

--[[ The prefab's two meshes, measured against `plate_frame`'s own frame.

	`plate_frame.CFrame.LookVector` points out of the white face, which is what makes the placement
	below a plain "put this frame there". The authored model carries a rotated `PivotOffset` from
	its Blender export, so the parts' CFrames are used and `Model:GetPivot` deliberately is not. ]]
function Plate.prefabPieces(prefab: Model)
	local frame = prefab and prefab:FindFirstChild(FRAME_NAME)
	local face = prefab and prefab:FindFirstChild(FACE_NAME)
	if not (frame and frame:IsA("BasePart") and face and face:IsA("BasePart")) then
		return nil
	end
	local reference = frame.CFrame
	local pieces = {}
	for _, part in { frame, face } do
		table.insert(pieces, {
			source = part,
			name = part.Name,
			offset = reference:ToObjectSpace(part.CFrame),
			size = part.Size,
		})
	end
	return pieces, frame.Size
end

--[[ What this car's plate reads when the caller did not name a string.

	The SAME plate the game gives that body at runtime, which is the point of the whole function: a
	master rig is a car in its authored livery, so it is hashed as `<body>:<Stock>` — exactly the
	`GarageConfig.carKey` a stock car is identified by everywhere else. The roster in Studio then
	reads as the roster in the game, and if `PlateConfig.Enabled` is ever turned off, 65 cars fall
	back to 65 plausible plates instead of 65 copies of one placeholder.

	REQUIRED THROUGH A pcall, deliberately. This module is a Studio plugin command living in
	ServerStorage; `ReplicatedStorage.shared` is Rojo-synced source that may simply not be in the
	place yet. A missing config makes the command write a placeholder, not fail to fit a plate. ]]
function Plate.textFor(car: Model): string
	local ok, text = pcall(function()
		local shared = game:GetService("ReplicatedStorage"):WaitForChild("shared", 5)
		local configs = shared and shared:WaitForChild("Configs", 5)
		local PlateConfig = require(configs:WaitForChild("PlateConfig", 5))
		local PaintConfig = require(configs:WaitForChild("PaintConfig", 5))
		local GarageConfig = require(configs:WaitForChild("GarageConfig", 5))
		return PlateConfig.forKey(GarageConfig.carKey(car.Name, PaintConfig.StockIndex))
	end)
	return if ok and type(text) == "string" and text ~= "" then text else FALLBACK_TEXT
end

--[[ The text on a plate face. Rebuilt rather than edited, so a re-run cannot leave a half-updated
	gui behind, and idempotent for the same reason.

	`LightInfluence = 1` so the lettering darkens with the panel it is printed on; at 0 it glows in
	the car's own shadow and reads as a screen rather than as paint. `MaxDistance` is well inside
	the point where a 2.2-stud plate is a single pixel — traffic 300 studs up the road does not
	need to be rendering text. ]]
function Plate.writeText(face: BasePart, text: string): SurfaceGui
	local existing = face:FindFirstChild(TEXT_NAME)
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = TEXT_NAME
	gui.Face = Enum.NormalId.Front -- the LookVector side, which is the white face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 200
	gui.LightInfluence = 1
	gui.MaxDistance = 150
	gui.ResetOnSpawn = false
	gui.Parent = face

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	-- Half the face's height, so `TextScaled` lands under the engine's 100px ceiling and the
	-- lettering is limited by the plate's width rather than silently clamped.
	label.Size = UDim2.fromScale(0.84, 0.52)
	label.FontFace = Plate.Font
	label.TextScaled = true
	label.TextColor3 = Plate.Ink
	label.Text = text
	label.Parent = gui

	return gui
end

--[[ How far out of the surface the plate has to sit for no corner of it to be inside the panel.

	Nine samples over the plate's own footprint rather than one on the centre, because the centre
	is the one point a vertical plate on a sloped bumper is guaranteed to touch. ]]
local function standoff(cast, anchor: Vector3, width: number, height: number): number
	local out = Vector3.zAxis
	local push = 0
	for x = -1, 1 do
		for y = -1, 1 do
			local sample = anchor + Vector3.new(x * width * 0.48, y * height * 0.48, 0)
			local hit = cast(sample + out * 3, -out, 6)
			if hit then
				push = math.max(push, (hit - sample):Dot(out))
			end
		end
	end
	return push
end

export type Fit = {
	position: CFrame,
	height: number, -- where it landed, as a fraction of the body's height
	inset: number, -- how far in front of the car's rearmost point it sits
	standoff: number,
	text: string, -- what it ended up reading, which is per-car unless the caller named one
	estimated: boolean?, -- placed off the bounding box: no surface could be hit. Look at it.
}

--[[ Put a plate on `car`, replacing any it already has. Returns the fit, or nil and why not.

	Order matters in the weld loop and it is the same rule the redress lives by: the CFrame is set
	before the WeldConstraint is parented, because a WeldConstraint bakes the offset it finds at
	the moment it binds. There is no yield in it. ]]
function Plate.place(car: Model, prefab: Model, options): (Fit?, string?)
	options = options or {}
	local width = options.Width or Plate.Defaults.Width
	local depth = options.Depth or Plate.Defaults.Depth
	local proud = options.Proud or Plate.Defaults.Proud
	local bandLow = options.BandLow or Plate.Defaults.BandLow
	local bandHigh = options.BandHigh or Plate.Defaults.BandHigh
	local prefer = options.Prefer or Plate.Defaults.Prefer
	local maxStandoff = options.MaxStandoff or Plate.Defaults.MaxStandoff
	-- Empty (the default) = this car's own generated plate; a string = that string, on every car.
	local wanted = options.Text or Plate.Defaults.Text
	local text = if wanted ~= "" then wanted else Plate.textFor(car)

	local frame = Plate.carFrame(car)
	if not frame then
		return nil, "not a CarBones rig (no Chassis/Suspension*/Wheel)"
	end
	local body = car:FindFirstChild("Body")
	local mount = car.Chassis:FindFirstChild(MOUNT_NAME)
	if not (body and mount and mount:IsA("BasePart")) then
		return nil, "no Body folder or no Chassis." .. MOUNT_NAME
	end
	local pieces, authored = Plate.prefabPieces(prefab)
	if not pieces then
		return nil, "prefab has no " .. FRAME_NAME .. "/" .. FACE_NAME
	end

	local parts = Plate.dressParts(car)
	if #parts == 0 then
		return nil, "no visible bodywork to measure"
	end
	local min, max = Plate.localBounds(parts, frame)
	local bodyHeight = max.Y - min.Y

	-- The dress is published CanQuery=false, so it has to be opened up for the fit and put back.
	local wasQueryable = {}
	for _, part in parts do
		wasQueryable[part] = part.CanQuery
		part.CanQuery = true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = parts
	local function cast(origin: Vector3, direction: Vector3, length: number)
		local result = workspace:Raycast(frame * origin, frame:VectorToWorldSpace(direction) * length, params)
		if not result then
			return nil, nil
		end
		return frame:PointToObjectSpace(result.Position), frame:VectorToObjectSpace(result.Normal)
	end

	-- The rearmost rear-facing point on the centreline, searched between `low` and `bandHigh`.
	-- Facing backwards and not merely hit: a near-horizontal boot lid is the rearmost thing on
	-- some bodies and is not a surface a plate hangs on.
	--[[ `inverted` (2026-10-09): accept a surface whose normal points FORWARD instead. A mesh exported
		inside-out (the Maybach's `Retopo_*` body, a retopology export) reports every face's normal
		reversed, so its rear bumper reads as facing the front and the ordinary pass finds nothing at
		all ("no rear-facing surface on the centreline"). Only ever the SECOND pass, after the honest
		one has come back empty: on a correctly-wound body a forward-facing hit is the inside of
		something, and must never win over a real rear face. ]]
	local function rearmost(low: number, inverted: boolean?): Vector3?
		local best
		for y = min.Y + low * bodyHeight, min.Y + bandHigh * bodyHeight, 0.04 do
			local point, normal = cast(Vector3.new(0, y, max.Z + 4), -Vector3.zAxis, 10)
			--- A miss returns no normal at all, so the hit is tested before the normal is read.
			if point and normal then
				local facing = if inverted then -normal.Z else normal.Z
				if facing >= 0.5 and (not best or point.Z > best.Z) then
					best = point
				end
			end
		end
		return best
	end

	local scale = width / authored.X
	local depthScale = depth / authored.Z
	local plateHeight = authored.Y * scale

	--- Whichever winding found the bumper is the one the lift below searches with, too.
	local inverted = false
	local best = rearmost(bandLow)
	if not best then
		inverted = true
		best = rearmost(bandLow, true)
	end
	--[[ NO SURFACE AT ALL (2026-10-09): the last resort, for a body whose meshes have no collision
		geometry for a ray to hit. The Maybach's export arrived that way — a ray down the centreline
		at every height, 60 studs long, hit nothing — and a dress part never collides in play, so the
		car itself is fine; only this measurement is blind. The plate goes where the BOUNDING BOX
		says the back is, at `Prefer` up the body: right on a car with a squared-off tail, a little
		proud on a rounded one. `estimated` in the result tells the caller to look at it. ]]
	local estimated = false
	if not best and not cast(Vector3.new(0, min.Y + bodyHeight * 0.5, max.Z + 4), -Vector3.zAxis, (max.Z - min.Z) + 8) then
		estimated = true
		best = Vector3.new(0, min.Y + prefer * bodyHeight, max.Z)
	end
	if not best then
		for _, part in parts do
			part.CanQuery = wasQueryable[part]
		end
		return nil, "no rear-facing surface on the centreline"
	end
	local anchor = Vector3.new(0, best.Y, best.Z)
	local push = if estimated then 0 else standoff(cast, anchor, width, plateHeight)

	-- The lift. See the header: a plate down in the bottom `prefer` of the body is offered the
	-- best spot above that line, and takes it only if it can sit there flush.
	if not estimated and (best.Y - min.Y) / bodyHeight < prefer then
		local higher = rearmost(prefer, inverted)
		if higher then
			local liftedAnchor = Vector3.new(0, higher.Y, higher.Z)
			local liftedPush = standoff(cast, liftedAnchor, width, plateHeight)
			if liftedPush <= maxStandoff then
				best, anchor, push = higher, liftedAnchor, liftedPush
			end
		end
	end
	for _, part in parts do
		part.CanQuery = wasQueryable[part]
	end

	local centreLocal = anchor + Vector3.zAxis * (push + depth * 0.5 + proud)
	local centre = frame * centreLocal
	-- ROTATION OFF THE MOUNT, NEVER OFF THE SURFACE — see the header. A clean half-turn puts the
	-- plate's face out the back of the car and keeps the offset axis-aligned, which is the only
	-- form that survives streaming.
	local pose = CFrame.new(centre) * mount.CFrame.Rotation * CFrame.Angles(0, math.pi, 0)

	for _, old in body:GetChildren() do
		if string.sub(old.Name, 1, #PLATE_PREFIX) == PLATE_PREFIX then
			old:Destroy()
		end
	end
	for _, piece in pieces do
		local clone = piece.source:Clone()
		clone:ClearAllChildren()
		clone.Name = piece.name
		clone.Size = Vector3.new(piece.size.X * scale, piece.size.Y * scale, piece.size.Z * depthScale)
		local offset = piece.offset.Position
		clone.CFrame = pose
			* CFrame.new(offset.X * scale, offset.Y * scale, offset.Z * depthScale)
			* (piece.offset - offset)
		-- The dress contract, part for part: massless so a plate cannot change how a car handles,
		-- and out of every spatial query so it is not a thing the wall sensor or a clip can hit.
		clone.Anchored = false
		clone.Massless = true
		clone.CanCollide = false
		clone.CanQuery = false
		clone.CanTouch = false
		clone.CastShadow = parts[1].CastShadow
		clone.RenderFidelity = Enum.RenderFidelity.Precise
		clone.PivotOffset = CFrame.identity
		clone.Parent = body

		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = mount, clone
		weld.Parent = clone

		if clone.Name == FACE_NAME then
			Plate.writeText(clone, text)
		end
	end

	return {
		position = pose,
		height = (best.Y - min.Y) / bodyHeight,
		inset = max.Z - centreLocal.Z,
		standoff = push,
		text = text,
		estimated = estimated,
	}
end

return Plate
