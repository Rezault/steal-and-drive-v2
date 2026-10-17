--[[
	RigCarBody — Command Runner command

	Grafts a raw Blender car export onto the CarBones chassis: clones a already-rigged
	pack car for its chassis/scripts/attributes, clears `Body/`, and rebuilds it from the
	selected art model — scaled, oriented, renamed to the redress contract and welded.

	This is the pass that produced `Sedan23`-`Sedan26` / `Sports39`-`Sports44` on
	2026-07-31 (`docs/CarPackB_RigNotes.md`). It is the car-redress-fitting recipe made
	repeatable, and it reproduces the ORIGINAL 33-car pack's
	geometry to 0.011 studs when run against their source art — that equivalence is the
	evidence the transform is the same one, not a lookalike.

	=== THE TRANSFORM =========================================================

	Both frames come from the FOUR WHEEL CENTRES, never from model pivots or axis
	assumptions: a Blender export and CarBones disagree about which axis is forward, and a
	model's pivot can be rotated relative to its own parent's.

		fwd = mid(front pair) - mid(rear pair);  right = mid(right pair) - mid(left pair)
		frame = CFrame.fromMatrix(mid of all four, right, up)

	Scale is the WHEELBASE RATIO. Not overall length, not wheel diameter — the three
	disagree, and wheel-in-arch alignment is the thing the eye actually reads.

	NOTHING IS SNAPPED AFTERWARDS, and that is deliberate. Because both frames are built
	at their own wheel-centre midpoint, the transform lands fore/aft and vertical on the
	physics wheel exactly (measured: <0.003 studs across all ten cars) for free. The
	LATERAL residual that remains is the modeller's authored track, and snapping it away
	silently overrides their stance — it is what once pushed the 33-car pack's rear tyres
	proud of their arches. The WeldConstraint holds the offset for nothing.

	THE ONE THING THE WHEELBASE FIT DOES NOT LINE UP IS THE CABIN, and the seat is in the
	cabin. `fitSeats` is the correction: it slides the two front seats back to sit a
	measured distance behind THIS body's steering wheel, because the chassis seat is fixed
	and every body puts its wheel somewhere else.

	=== NAMING ================================================================

	Names are the redress contract, not decoration (see `Modules/CarBody`,
	`Modules/CarDoorRig`, `Modules/CarPaint`):

	  * `shell_NN_body` — bodywork. Must contain `body` as a WORD (the name is split on its
	    separators, so `trim` does not count as `rim`) to take a repaint outright, and must
	    match `^shell_%d+_body$` exactly or `CarDoorRig` cannot find the doors.
	  * `glass_NN` — window glass, and the only category this command restyles.
	  * everything else deliberately does NOT carry `body`. It can still be swept into a
	    repaint by sharing the shell panels' TextureID, which is how the body-coloured trim
	    on several roster cars is caught — so anything that must NEVER take the paint wants
	    a hardware word in its name (`wheel`, `glass`, `light`, `lens`, ...), which vetoes
	    the texture match. That list is in `CarPaint`.

	=== GLASS =================================================================

	TRANSPARENCY IS THE HALF OF THIS THAT SHOWS UP IN A PROPERTY DUMP, AND IT IS NOT THE
	HALF THAT MATTERS. The roster's window glass is `Color = (17,17,17)` on `SmoothPlastic`
	with no texture — a near-black pane you happen to see through. Match the transparency
	alone and leave the mesh at its imported grey with the body atlas still on it, and the
	result is not tinted glass, it is a hole: the pane washes out to clear and the car
	reads as having no windows at all. That shipped once, on 2026-07-31, and looked exactly
	like a bug.

	So a glass mesh gets ALL FOUR: the tint, `SmoothPlastic`, no `TextureID`, and the
	transparency. The default is 0.6 rather than the roster's 0.75 for one reason — pack A
	has a modelled interior behind its glass and pack B has none, so at 0.75 what shows
	through a pack B window is the bright ground and the bare chassis. 0.6 closes that gap
	without going opaque. On a body that DOES have an interior, 0.75 is the roster value.

	=== PACKS =================================================================

	THE NAMING VOCABULARY IS PER-PACK, AND SO IS THE WAY A WHEEL IS FOUND. Each entry in
	`PACKS` below owns three things a raw export cannot be read without: how its wheel
	groups are named, which material tokens mean "front lamp" vs "rear lamp", and how a
	source part name maps onto the redress contract. `detectPack` picks one by evidence;
	the `Pack` argument overrides it when a future export fools the heuristic.

	  * `B` — `Cube<digits>` wheel groups, materials `body018`/`windows001`/`brakelights`.
	  * `C` — the `Lpveh…` low-poly vendor pack, which is ALSO where the original pack A
	    came from, so it is rigged to pack A's richer roster vocabulary (`stock_NN_body`,
	    `lens_clear_NN`, `light_housing_NN`) rather than pack B's smaller one. Its parts
	    decompose as `Lpveh<car><component><n><material>`: the component says what the part
	    is, the material says which lamp colour it is.

	A pack C part named `glass*` is EITHER a window or a headlight cover, and the two want
	opposite treatment — tint one and you have tinted glass, tint the other and you have a
	dark smear over a headlight. They separate cleanly on geometry rather than on name:
	measured across all 16 bodies, windows sit within |0.28| of the car's centre fore/aft
	and up in the greenhouse, lamp covers beyond |0.76| and down at bumper height. There is
	no part anywhere in the gap, so `GLASS_CABIN_FRACTION` splits them.

	=== ASSUMPTIONS IT WILL SHOUT ABOUT =======================================

	  * Four wheels, one per corner, found the way the detected pack names them.
	  * Front is derived from the lights — a white/clear emissive lamp at one end, a red one
	    at the other. A model with neither errors rather than guessing, because a
	    back-to-front car passes every numeric check there is.
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Types = require(script.Types)

local CAR_SYSTEM = "CarSystem"
local BODY_FOLDER = "Body"
local HULL_NAME = "HitBox"
local MOUNT_NAME = "RedressMount"
local CORNERS = { "FL", "FR", "RL", "RR" }

-- The roster was parked in ServerStorage on 2026-10-13; Workspace still wins if dragged back.
local function rosterFolder(): Instance?
	return workspace:FindFirstChild(CAR_SYSTEM) or game:GetService("ServerStorage"):FindFirstChild(CAR_SYSTEM)
end

local FALLBACK_CATEGORY = "detail_%02d"

-- The roster's window glass, measured off pack A rather than chosen. See the header for
-- why the tint is load-bearing and the transparency alone is not.
local GLASS_PATTERN = "^glass"
local GLASS_TINT = Color3.fromRGB(17, 17, 17)

-- A pack C `glass*` part inside this fraction of the half-length is a window; beyond it,
-- a lamp cover. Measured, not chosen — see the header.
local GLASS_CABIN_FRACTION = 0.5

--[[ === The driving position ================================================================

	CarBones parks its `VehicleSeat` at a FIXED spot on the chassis (mount-local z -1.81), and a
	dress is fitted to that chassis BY WHEELBASE — nothing in the graft below lines a body's cabin
	up with the seat. So the seat lands wherever the interior happens to fall, and across the
	roster that was anywhere from 1.9 studs behind the steering wheel to 1.6 studs IN FRONT of it:
	the rider's chest inside the wheel, perched on the front lip of the cushion.

	The wheel is the only cabin landmark the packs name, and it is the right one — how far the
	driver sits behind the wheel is the thing that reads as wrong. `SEAT_GAP` is measured off a
	seated R15 in the Civic: hips 1.40 studs behind the wheel's rear face put their back against
	the seat's backrest with the arms still reaching forward. A pack that names no
	`steering_wheel` (pack B) leaves the seat where CarBones put it, and says so. ]]
local STEERING_WHEEL_NAME = "steering_wheel"
local FRONT_SEATS = { "VehicleSeat", "SeatFR" }
local REAR_SEAT_NAME = "SeatRL"
local SEAT_GAP = 1.40
-- Keep the front row clear of the rear bench, which has no per-body landmark to be fitted from
-- and so stays where CarBones put it.
local SEAT_REAR_CLEAR = 1.20

local function baseName(name: string): string
	return (name:gsub("%.%d+$", "")):lower()
end

--[[ ===== Pack B — `Cube<digits>` wheel groups, `body018`/`windows001` materials ===== ]]

-- Blender material token -> the name the redress contract wants. Order matters: the
-- first hit wins, so `brakelights` must be tested before any looser `brake` rule.
local PACK_B_CATEGORIES = {
	{ "body", "shell_%02d_body" },
	{ "windows", "glass_%02d" },
	{ "headlights", "light_white_%02d" },
	{ "brake", "light_red_%02d" },
	{ "reverse", "light_reverse_%02d" },
	{ "turn", "light_amber_%02d" },
	{ "reflector", "lens_red_%02d" },
	{ "grill", "grille_%02d" },
	{ "chrome", "trim_chrome_%02d" },
	{ "trim", "trim_%02d" },
	{ "secondary", "trim_%02d" },
}

local PackB = {
	Name = "B",
	-- Wheels arrive as four multi-part groups sharing a `Cube<n>` prefix.
	WheelKey = function(part: BasePart): string?
		return string.match(part.Name, "^(Cube%d+)")
	end,
	IsFrontLamp = function(token: string): boolean
		return string.find(token, "headlights", 1, true) ~= nil or string.find(token, "grill", 1, true) ~= nil
	end,
	IsRearLamp = function(token: string): boolean
		return string.find(token, "brake", 1, true) ~= nil
			or string.find(token, "reverse", 1, true) ~= nil
			or string.find(token, "reflector", 1, true) ~= nil
	end,
	CategoryOf = function(name: string): string
		local token = (baseName(name):gsub("^plane%d+", ""):gsub("^cube%d+", ""))
		for _, entry in PACK_B_CATEGORIES do
			if string.find(token, entry[1], 1, true) then
				return entry[2]
			end
		end
		return FALLBACK_CATEGORY
	end,
}

--[[ ===== Pack C — the `Lpveh…` vendor pack, rigged to pack A's vocabulary ===== ]]

-- Longest-first: `hredemmision01` must be tested before nothing, and `glasswh01` before a
-- looser `glass` rule would ever see it.
local PACK_C_MATERIALS =
	{ "hwemmision01", "hredemmision01", "glasswh01", "glassred01", "glassorn01", "hb01", "fp01", "pt01", "fgt01" }

-- Order matters: `steeringwheel` before `wheel`, and every `headlight*` spelling before
-- `glass`, because a tail-lamp's own material token contains the word "glass".
local PACK_C_COMPONENTS =
	{ "steeringwheel", "headlighton", "headlightst", "headlight", "wheelt", "wheel", "glass", "spoiler", "tuning", "stock" }

-- Lamp material -> roster name. These are the names pack A already uses, so a pack C car
-- reads the same in the explorer as the 33 that shipped before it.
local PACK_C_LAMPS = {
	hwemmision01 = "light_%02d", -- emissive white: the headlight itself
	hredemmision01 = "light_red_%02d", -- emissive red: the brake bar
	glassred01 = "lens_red_%02d",
	glassorn01 = "lens_amber_%02d",
	glasswh01 = "lens_clear_%02d",
	hb01 = "light_housing_%02d", -- the black bezel around a lamp, never painted
	[""] = "light_housing_%02d",
}

-- Body-coloured components. Each keeps its own word AND carries `body`, so a repaint takes
-- them and `CarDoorRig`'s `^shell_%d+_body$` still only ever matches a real panel.
local PACK_C_BODY = { shell = "shell_%02d_body", spoiler = "spoiler_%02d_body", stock = "stock_%02d_body", tuning = "tuning_%02d_body" }

local function packCDecompose(name: string): (string, string)
	local rest = baseName(name)
	local material = ""
	for _, candidate in PACK_C_MATERIALS do
		if string.sub(rest, -#candidate) == candidate then
			material = candidate
			rest = string.sub(rest, 1, -#candidate - 1)
			break
		end
	end
	local component = "shell"
	for _, candidate in PACK_C_COMPONENTS do
		if string.find(rest, candidate, 1, true) then
			component = candidate
			break
		end
	end
	return component, material
end

local PackC = {
	Name = "C",
	-- One part per corner, named `…wheel<n>…`. `steeringwheel` is excluded by the component
	-- ordering above, or every car would survey five wheels and one of them would be indoors.
	WheelKey = function(part: BasePart): string?
		local component = packCDecompose(part.Name)
		return if component == "wheel" or component == "wheelt" then part.Name else nil
	end,
	IsFrontLamp = function(token: string): boolean
		return string.find(token, "hwemmision", 1, true) ~= nil
	end,
	IsRearLamp = function(token: string): boolean
		return string.find(token, "hredemmision", 1, true) ~= nil or string.find(token, "glassred", 1, true) ~= nil
	end,
	-- `fraction` is the part's fore/aft offset as a fraction of the body's half-length; it
	-- is the only thing that separates a window from a headlight cover.
	CategoryOf = function(name: string, fraction: number): string
		local component, material = packCDecompose(name)
		if component == "steeringwheel" then
			return "steering_wheel"
		end
		if component == "glass" then
			if material == "glassred01" then
				return "lens_red_%02d"
			elseif material == "glassorn01" then
				return "lens_amber_%02d"
			elseif material == "hwemmision01" then
				return "light_%02d"
			end
			return if math.abs(fraction) > GLASS_CABIN_FRACTION then "lens_clear_%02d" else "glass_%02d"
		end
		if string.find(component, "headlight", 1, true) then
			return PACK_C_LAMPS[material] or "light_housing_%02d"
		end
		-- Stray `Cube<n>` scraps ride along in some exports (one is a zero-thickness sliver).
		-- They are not bodywork, so they must not take a repaint.
		if component == "shell" and string.match(baseName(name), "^cube%d+") then
			return FALLBACK_CATEGORY
		end
		return PACK_C_BODY[component] or FALLBACK_CATEGORY
	end,
}

local PACKS = { PackB, PackC }

-- Pick a pack by evidence rather than by asking. Whichever one finds four wheels wins; if
-- both do, the more specific vocabulary does.
local function detectPack(source: Model)
	local best, bestCount
	for _, pack in PACKS do
		local seen = {}
		local count = 0
		for _, child in source:GetChildren() do
			if child:IsA("BasePart") then
				local key = pack.WheelKey(child)
				if key and not seen[key] then
					seen[key] = true
					count += 1
				end
			end
		end
		if count == 4 and (not best or count > bestCount) then
			best, bestCount = pack, count
		end
	end
	return best
end

-- The car's own frame, derived from four wheel centres. Re-orthogonalised because the
-- two measured axes are not guaranteed perpendicular on a staggered-track car.
local function frameFrom(fl: Vector3, fr: Vector3, rl: Vector3, rr: Vector3): (CFrame, number)
	local forward = ((fl + fr) / 2) - ((rl + rr) / 2)
	local right = (((fr + rr) / 2) - ((fl + rl) / 2)).Unit
	local up = right:Cross(forward.Unit).Unit
	right = forward.Unit:Cross(up).Unit
	return CFrame.fromMatrix((fl + fr + rl + rr) / 4, right, up), forward.Magnitude
end

-- Which corner each wheel group is, and the source frame. Returns nil plus a reason
-- rather than a guess: every failure here produces a car that looks plausible and is
-- wrong, which is the expensive kind.
local function surveySource(source: Model, pack: any): (any?, string?)
	local groups, order = {}, {}
	for _, child in source:GetChildren() do
		local key = child:IsA("BasePart") and pack.WheelKey(child)
		if key then
			if not groups[key] then
				groups[key] = {}
				table.insert(order, key)
			end
			table.insert(groups[key], child)
		end
	end
	if #order ~= 4 then
		return nil, `pack {pack.Name}: expected 4 wheel groups, found {#order}`
	end

	local centres, mid = {}, Vector3.zero
	for _, prefix in order do
		local sum = Vector3.zero
		for _, part in groups[prefix] do
			sum += part.Position
		end
		centres[prefix] = sum / #groups[prefix]
		mid += centres[prefix]
	end
	mid /= 4

	-- Front from the lights, not from an axis convention.
	local frontSum, rearSum, frontN, rearN = 0, 0, 0, 0
	for _, child in source:GetChildren() do
		if child:IsA("BasePart") then
			local token, offset = baseName(child.Name), child.Position.X - mid.X
			if pack.IsFrontLamp(token) then
				frontSum, frontN = frontSum + offset, frontN + 1
			elseif pack.IsRearLamp(token) then
				rearSum, rearN = rearSum + offset, rearN + 1
			end
		end
	end
	-- One end is enough: the lamps that name a colour only ever sit at one end of a car, so
	-- a body with red lamps and no white ones (three in pack C) is still unambiguous.
	if frontN == 0 and rearN == 0 then
		return nil, "cannot tell front from rear: no front-lamp or tail-lamp meshes"
	end
	local frontIsMinusX = if frontN > 0 and rearN > 0
		then frontSum / frontN < rearSum / rearN
		elseif frontN > 0 then frontSum / frontN < 0
		else rearSum / rearN > 0

	local forward = Vector3.new(if frontIsMinusX then -1 else 1, 0, 0)
	local right = forward:Cross(Vector3.yAxis)
	local byCorner = {}
	for _, prefix in order do
		local v = centres[prefix] - mid
		byCorner[(if v:Dot(forward) > 0 then "F" else "R") .. (if v:Dot(right) < 0 then "L" else "R")] = prefix
	end
	for _, corner in CORNERS do
		if not byCorner[corner] then
			return nil, `wheel groups do not form four distinct corners (missing {corner})`
		end
	end

	local isWheel = {}
	for _, group in groups do
		for _, part in group do
			isWheel[part] = true
		end
	end

	local frame, wheelbase =
		frameFrom(centres[byCorner.FL], centres[byCorner.FR], centres[byCorner.RL], centres[byCorner.RR])
	return { groups = groups, byCorner = byCorner, frame = frame, wheelbase = wheelbase, isWheel = isWheel }, nil
end

--[[ Rig `source` onto a clone of `template`, parented to `parent` at `slot`.

	Returns the new car, or nil plus a reason. Never touches `source`: every part is
	cloned, so the art folder stays a clean re-run input. ]]
-- The extent of `part` measured in `frame`'s axes. The steering wheel is modelled rotated 90°,
-- so its `Size` axes are not the car's and the corners have to be walked.
local function extentIn(frame: CFrame, part: BasePart): (Vector3, Vector3)
	local rel = frame:ToObjectSpace(part.CFrame)
	local half = part.Size / 2
	local min = Vector3.new(math.huge, math.huge, math.huge)
	local max = Vector3.new(-math.huge, -math.huge, -math.huge)
	for x = -1, 1, 2 do
		for y = -1, 1, 2 do
			for z = -1, 1, 2 do
				local corner = (rel * CFrame.new(half.X * x, half.Y * y, half.Z * z)).Position
				min = Vector3.new(math.min(min.X, corner.X), math.min(min.Y, corner.Y), math.min(min.Z, corner.Z))
				max = Vector3.new(math.max(max.X, corner.X), math.max(max.Y, corner.Y), math.max(max.Z, corner.Z))
			end
		end
	end
	return min, max
end

--[[ Slide the front seats back so the driver sits `SEAT_GAP` behind this body's steering wheel.
	Returns how far they moved, or nil and the reason they didn't.

	IT ONLY EVER MOVES A RIDER BACKWARDS. A body whose wheel is already well forward of the seat
	(a mid-engined cockpit) has a driving position that is roomy rather than wrong, and pulling
	that rider TOWARDS the wheel to hit an exact gap is a change with nothing behind it.

	THE SEAT'S WELDS COME OFF FIRST AND GO BACK ON AFTER. A `WeldConstraint` re-reads the two
	parts' relative transform when it is enabled, so disable-move-enable re-welds the seat where
	it now is; writing `.CFrame` with the weld live drags every rigidly-welded part with it —
	the chassis, the dress, the whole car — instead of moving the seat within the assembly. It
	collects EVERY weld touching the seat rather than the `SeatToChassisWeld` alone because the
	front seats also carry a `DoorLatchWeld`, and on a handful of rigs that one is wired to a
	real door part that would otherwise be dragged along. ]]
local function fitSeats(car: Model): (number?, string?)
	local chassis = car:FindFirstChild("Chassis")
	local body = car:FindFirstChild(BODY_FOLDER)
	local mount = chassis and chassis:FindFirstChild(MOUNT_NAME)
	local seat = chassis and chassis:FindFirstChild(FRONT_SEATS[1])
	local wheel = body and body:FindFirstChild(STEERING_WHEEL_NAME)
	if not (mount and seat and seat:IsA("BasePart")) then
		return nil, "this rig has no chassis mount or driver seat"
	end
	if not (wheel and wheel:IsA("BasePart")) then
		return nil, `this pack names no {STEERING_WHEEL_NAME} to measure against`
	end

	local frame = (mount :: BasePart).CFrame
	local _, wheelBack = extentIn(frame, wheel :: BasePart)
	local seatZ = frame:ToObjectSpace((seat :: BasePart).CFrame).Position.Z
	local rear = chassis:FindFirstChild(REAR_SEAT_NAME)
	local rearZ = if rear and rear:IsA("BasePart")
		then frame:ToObjectSpace(rear.CFrame).Position.Z
		else seatZ + 4
	local target = math.clamp(wheelBack.Z + SEAT_GAP, seatZ, rearZ - SEAT_REAR_CLEAR)
	local delta = target - seatZ
	if delta < 0.02 then
		return nil, string.format("the driver already sits %.2f studs behind the wheel", seatZ - wheelBack.Z)
	end

	for _, seatName in FRONT_SEATS do
		local part = chassis:FindFirstChild(seatName)
		if part and part:IsA("BasePart") then
			local welds = {}
			for _, descendant in car:GetDescendants() do
				if descendant:IsA("WeldConstraint") and (descendant.Part0 == part or descendant.Part1 == part) then
					table.insert(welds, { weld = descendant, enabled = descendant.Enabled })
					descendant.Enabled = false
				end
			end
			part.CFrame = frame * CFrame.new(0, 0, delta) * frame:ToObjectSpace(part.CFrame)
			for _, entry in welds do
				entry.weld.Enabled = entry.enabled
			end
		end
	end
	return delta, nil
end

local function rig(source: Model, template: Model, pack: any, newName: string, slot: Vector3?, glassTransparency: number)
	local survey, err = surveySource(source, pack)
	if not survey then
		return nil, err
	end

	local car = template:Clone()
	car.Name = newName
	car.Parent = template.Parent
	if slot then
		local pivot = car:GetPivot()
		car:PivotTo(CFrame.new(slot.X - pivot.Position.X, 0, slot.Z - pivot.Position.Z) * pivot)
	end

	local body, chassis = car[BODY_FOLDER], car.Chassis
	local mount = chassis[MOUNT_NAME]
	-- The hull is the chassis's own, not part of the dress — it owns Health and is sized
	-- to the chassis, so a redress must leave it exactly alone.
	for _, child in body:GetChildren() do
		if child.Name ~= HULL_NAME then
			child:Destroy()
		end
	end

	local function physicsWheel(corner: string): BasePart
		return chassis["Suspension" .. corner].Wheel
	end
	local destination, destWheelbase = frameFrom(
		physicsWheel("FL").Position,
		physicsWheel("FR").Position,
		physicsWheel("RL").Position,
		physicsWheel("RR").Position
	)
	local scale = destWheelbase / survey.wheelbase

	local function place(sourcePart: BasePart, name: string, parent: Instance, weldTo: BasePart)
		local part = sourcePart:Clone()
		part.Name = name
		local rel = survey.frame:ToObjectSpace(sourcePart.CFrame)
		part.Size = sourcePart.Size * scale
		part.CFrame = destination * (CFrame.new(rel.Position * scale) * (rel - rel.Position))
		-- The massless-visuals contract: a dress weighs nothing and collides with nothing,
		-- so it can never retune the car it is bolted to.
		part.Anchored, part.Massless, part.CanCollide = false, true, false
		part.CanQuery, part.CanTouch = false, false
		part.CastShadow, part.CollisionGroup = false, "Default"
		if string.match(name, GLASS_PATTERN) then
			-- All four, not just the transparency — see the header.
			part.Color = GLASS_TINT
			part.Material = Enum.Material.SmoothPlastic
			part.Reflectance = 0
			if part:IsA("MeshPart") then
				part.TextureID = ""
			end
			part.Transparency = glassTransparency
		end
		part.Parent = parent
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = weldTo, part
		weld.Parent = part
	end

	-- Wheels. Welded to `Suspension*/Wheel` rather than to the body: weld a wheel visual
	-- to the bodywork and you get a car whose wheels neither spin nor steer.
	for _, corner in CORNERS do
		local group = Instance.new("Model")
		group.Name = corner
		group.Parent = body

		local parts = survey.groups[survey.byCorner[corner]]
		table.sort(parts, function(a, b)
			return math.max(a.Size.Y, a.Size.Z) > math.max(b.Size.Y, b.Size.Z)
		end)
		for index, part in parts do
			local name = if index == 1
				then `wheel_{corner}`
				elseif index == 2 then `rim_{corner}`
				else string.format("wheelpart_%s_%02d", corner, index)
			place(part, name, group, physicsWheel(corner))
		end

		-- `Suspension*/Wheel` is a GREEN DEBUG MARKER inherited from CarBones, not a tyre.
		-- Any dress whose visual wheel is smaller than its 3.0-stud diameter leaves it
		-- poking through as a green ring. Cosmetic, and touches no tuning attribute.
		physicsWheel(corner).Transparency = 1
	end

	-- Bodywork. Sorted front-to-back so the numbering is stable across re-runs and reads
	-- in the explorer the way the car reads on screen.
	local rest = {}
	for _, child in source:GetChildren() do
		if child:IsA("BasePart") and not survey.isWheel[child] then
			table.insert(rest, {
				part = child,
				key = survey.frame:ToObjectSpace(child.CFrame).Position * scale,
			})
		end
	end
	-- How far along the car a part sits, as a fraction of the half-length — the only thing
	-- that tells a pack C window from a headlight cover. Normalised against the furthest
	-- part centre rather than a bounding box so it needs no axis assumption.
	local halfLength = 0
	for _, entry in rest do
		halfLength = math.max(halfLength, math.abs(entry.key.Z))
	end
	for _, entry in rest do
		entry.format = pack.CategoryOf(entry.part.Name, if halfLength > 0 then entry.key.Z / halfLength else 0)
	end
	table.sort(rest, function(a, b)
		if math.abs(a.key.Z - b.key.Z) > 1e-3 then
			return a.key.Z < b.key.Z
		end
		if math.abs(a.key.X - b.key.X) > 1e-3 then
			return a.key.X < b.key.X
		end
		return a.key.Y < b.key.Y
	end)
	local counters = {}
	for _, entry in rest do
		counters[entry.format] = (counters[entry.format] or 0) + 1
		place(entry.part, string.format(entry.format, counters[entry.format]), body, mount)
	end

	return car, nil
end

return {
	AutoRecordChanges = true,
	Description = "Graft the selected raw Blender car export(s) onto the CarBones chassis: clone a rigged pack car, rebuild Body/ scaled by wheelbase, rename to the redress contract, weld and tint the glass.",
	Tags = { "Cars", "Art" },
	Arguments = {
		CarName = {
			Type = "string",
			Default = "",
			LayoutOrder = 1,
			PlaceholderText = "e.g. Sports45",
			Description = "Name for the rigged car. With several models selected, an index is appended (Sports45, Sports46...). Leave blank to reuse the source model's name.",
		},
		Template = {
			Type = "string",
			Default = "Sedan06",
			LayoutOrder = 2,
			Description = "Rigged car in Workspace.CarSystem to clone for its chassis, scripts, tuning attributes and tag. Any pack car works — all 43 carry identical attributes and their chassis agree to <0.05 studs.",
		},
		GlassTransparency = {
			Type = "slider",
			Default = 0.75,
			Min = 0,
			Max = 1,
			Step = 0.05,
			LayoutOrder = 3,
			Description = "Transparency for every glass_NN mesh. They always also get the roster's near-black tint on SmoothPlastic with no texture — without that, any value here reads as a hole rather than as glass. 0.75 is the roster's number and suits a body with a modelled interior; drop to 0.6 only for a body with an empty cabin, where 0.75 shows the bare chassis through the windows.",
		},
		Pack = {
			Type = "dropdown",
			Default = "Auto",
			Options = { "Auto", "B (Cube groups)", "C (Lpveh)" },
			LayoutOrder = 5,
			Description = "Which source pack's naming to read. Auto picks the one that finds four wheels, which has been right on every export so far; override only if a new export fools it.",
		},
		PlaceAt = {
			Type = "dropdown",
			Default = "Next free grid slot",
			Options = { "Next free grid slot", "Template position", "Source art position" },
			LayoutOrder = 4,
			Description = "Where to put the rigged car. The grid is the roster's own 32x22 stud layout in Workspace.CarSystem.",
		},
	},

	Validate = function(props: Types.Props): (boolean, string?)
		local carSystem = rosterFolder()
		if not carSystem then
			return false, `no {CAR_SYSTEM} in Workspace or ServerStorage`
		end
		if #props.Selected == 0 then
			return false, "Select the raw art model(s) to rig."
		end
		return true
	end,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()
		local carSystem = rosterFolder() :: Instance
		local template = carSystem:FindFirstChild(arguments.Template)
		if not (template and template:IsA("Model") and template:FindFirstChild("Chassis")) then
			out:error(`Template "{arguments.Template}" is not a rigged car in {carSystem:GetFullName()}.`)
			return
		end

		-- The roster's layout: 32 studs across, 22 along, growing in +X.
		local occupied, maxX = {}, -math.huge
		for _, car in carSystem:GetChildren() do
			local p = car:GetPivot().Position
			occupied[`{math.floor(p.X + 0.5)},{math.floor(p.Z + 0.5)}`] = true
			maxX = math.max(maxX, p.X)
		end
		local gridX, gridZ = 415, 475
		local function nextFreeSlot(): Vector3
			for column = 0, 40 do
				for row = 0, 5 do
					local x, z = gridX + column * 32, gridZ + row * 22
					if not occupied[`{x},{z}`] then
						occupied[`{x},{z}`] = true
						return Vector3.new(x, 0, z)
					end
				end
			end
			return Vector3.new(maxX + 32, 0, gridZ)
		end

		local recording = ChangeHistoryService:TryBeginRecording("RigCarBody")
		local built = {}
		for index, selected in props.Selected do
			if not selected:IsA("Model") then
				out:warn(`{selected.Name}: not a Model, skipped.`)
				continue
			end

			local name = arguments.CarName
			if name == "" then
				name = selected.Name
			elseif #props.Selected > 1 then
				local stem, digits = string.match(name, "^(.-)(%d+)$")
				name = if stem
					then stem .. string.format("%0" .. #digits .. "d", tonumber(digits) + index - 1)
					else `{name}{index}`
			end
			if carSystem:FindFirstChild(name) then
				out:warn(`{name}: already exists in Workspace.{CAR_SYSTEM}, skipped.`)
				continue
			end

			local pack = if arguments.Pack == "Auto"
				then detectPack(selected)
				elseif string.sub(arguments.Pack, 1, 1) == "B" then PackB
				else PackC
			if not pack then
				out:error(`{selected.Name}: no pack recognises four wheels here — check the export, or set Pack by hand.`)
				continue
			end

			local slot = if arguments.PlaceAt == "Next free grid slot"
				then nextFreeSlot()
				elseif arguments.PlaceAt == "Source art position" then selected:GetPivot().Position
				else nil
			local car, err = rig(selected, template, pack, name, slot, arguments.GlassTransparency)
			if not car then
				out:error(`{selected.Name}: {err}`)
				continue
			end

			-- The assertion that makes the massless-visuals rule checkable. A single missed
			-- `Massless` silently retunes the car and nothing else reports it.
			local dressMass = 0
			for _, d in car[BODY_FOLDER]:GetDescendants() do
				if d:IsA("BasePart") and d.Name ~= HULL_NAME and not d.Massless then
					dressMass += d:GetMass()
				end
			end
			if dressMass > 0 then
				out:warn(`{name}: dress contributes {string.format("%.4f", dressMass)} mass — it must be 0.`)
			end

			-- The chassis seat is body-agnostic and the dress is fitted by wheelbase, so the
			-- driving position has to be measured against this body's own cabin. See `fitSeats`.
			local seatShift, seatWhy = fitSeats(car)
			if seatShift then
				out:print(`{name}: front seats moved back {string.format("%.2f", seatShift)} studs to sit behind the wheel.`)
			else
				out:warn(`{name}: front seats left at the CarBones position — {seatWhy}.`)
			end

			table.insert(built, car)
			out:print(`{name}: rigged from {selected.Name} (pack {pack.Name}).`)
		end

		if recording then
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
		end
		if #built > 0 then
			props:SetSelection(built)
			out:print(`Rigged {#built} car(s). Add them to a world's list in WorldConfig to put them on the road.`)
		end
	end,
}
