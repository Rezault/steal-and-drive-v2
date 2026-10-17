--[[
	CarDisplay  (shared, server-side in practice)
	--------------------------------------------
	A CAR THAT IS ONLY LOOKED AT. Clone the dress off a roster body, cut every tie it has to the car
	it came from, paint it, plate it, and stand it somewhere.

	Two places in the game park a car nobody drives — the six podiums in a dealership showroom
	(`GarageService._buildDisplayCar`) and the stands out on the plaza that `CarDealService` sells
	from — and the awkward half of doing that is identical for both. It lives here because ONE of
	the three things below has already cost this project a bug, and a second hand-written copy of
	the same twenty lines is where it would cost it another.

	=== WHAT A DISPLAY CAR IS NOT ============================================================

	`Workspace.CarSystem.<Body>` is a full CarBones rig — 311 instances of chassis, constraints,
	seats, sounds and the whole stock vehicle script suite. A display car is its `Body` folder alone,
	about 50 parts of dress and wheel visuals, anchored and query-blind. Nothing here can be driven,
	sat in, or collided with, and nothing here is ever handed to the solver.

	=== THE THREE THINGS THAT LOOK LIKE HOUSEKEEPING AND ARE NOT =============================

	1. EVERY JOINT, CONSTRAINT AND WELD IN THE CLONE IS DESTROYED. A weld cloned out of a rig still
	   points at the ORIGINAL car's part — Roblox only remaps references that land inside the cloned
	   subtree, and the chassis is not in this one — so the copy arrives WELDED TO THE PRISTINE
	   TEMPLATE across the map. `Body` does carry them: every redressed body on the roster is held to
	   `Chassis.RedressMount` by a `WeldConstraint` per panel. Leave those and writing a CFrame on
	   the copy drags the roster master onto the podium, in its stock livery, to stand inside the
	   painted clone — a duplicate car on the bay and a hole in the roster. See `tiesToAnotherPart`
	   for why the obvious two-clause test walks straight past the one class that matters.

	2. THE PARTS ARE PLACED INDIVIDUALLY, NOT WITH `PivotTo`. `Body` has no PrimaryPart, so a pivot
	   would be its bounding-box centre with no rotation to speak of, and the roster cars sit at
	   arbitrary world orientations. Each part is re-expressed in the SOURCE CAR'S frame (whose
	   LookVector is the car's nose — the front wheels measure at local Z -6.2) and rebuilt against
	   the target, which is exact and needs no PrimaryPart on either side.

	3. THE PAINT GOES ON THE CLONE, NEVER THE SOURCE. `CarPaint` works by clearing the MeshPart
	   texture the roster's colour actually lives in, so the same call on the master would strip it
	   and there is no undo.

	=== THE SHAPE OF THE API =================================================================

	`build` gives you a model that is finished but NOT PARENTED and NOT PLACED, together with the
	offsets and the measured box its caller needs to decide where it goes. `place` writes those
	offsets against a CFrame. They are two calls rather than one because the two callers frame the
	car differently — a podium fits it to a deck, a plaza stand centres it on a cap — and both want
	to do that arithmetic with the box in hand and the car still off screen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarPaint = require(ReplicatedStorage.shared.Modules.CarPaint)
local CarPlate = require(ReplicatedStorage.shared.Modules.CarPlate)
local CarRoster = require(ReplicatedStorage.shared.Modules.CarRoster)

local CarDisplay = {}

--- The car's own bounding box, in the car's frame. Y is the only axis whose top is never wanted, so
--- only `minY` is carried — every caller uses it to sit the wheels on a surface.
export type Extents = { minX: number, maxX: number, minY: number, minZ: number, maxZ: number }

--- part -> its CFrame in the source car's frame. Handed back by `build` and consumed by `place`.
export type Offsets = { [BasePart]: CFrame }

export type Options = {
	--- The roster folder's name, resolved by `CarRoster` wherever it now lives. Defaults to `CarSystem`.
	rosterFolder: string?,
	--- The child of a roster car holding the visual dress. Defaults to `Body`.
	bodyFolder: string?,
	--- Stripped from the clone: it is the invisible physics hull, and a parked car has no physics.
	hitBoxName: string?,
	--- What the finished model is called. Defaults to `DisplayCar`.
	name: string?,
	--- Whether the dress casts a shadow. Defaults to false — the roster's bodies are authored with
	--- it off anyway, and a showroom of them is a real cost for something nobody looks at.
	castShadow: boolean?,
}

local DEFAULT_ROSTER = "CarSystem"
local DEFAULT_BODY = "Body"
local DEFAULT_HITBOX = "HitBox"
local DEFAULT_NAME = "DisplayCar"

--[[ Everything in a cloned dress that can tie one of its parts to a part outside it.

	THE FOUR CLASSES ARE NOT ONE FAMILY, and that is the entire reason this is a list rather than an
	`IsA` or two. `WeldConstraint` and `NoCollisionConstraint` descend from `Instance` DIRECTLY: they
	are neither `JointInstance` nor `Constraint`, whatever their names suggest. The obvious two-clause
	test therefore walks straight past `WeldConstraint` — which is the one class a redressed body is
	actually held on with (`RigCarBody` welds every panel to `Chassis.RedressMount` and every wheel
	visual to a `Suspension*.Wheel`), so it is the one that had to be caught.

	It reads as belt-and-braces and it is not: missed here, the clone arrives welded to the ROSTER
	MASTER across the map. See header note 1 for what that looks like on screen. ]]
function CarDisplay.tiesToAnotherPart(inst: Instance): boolean
	return inst:IsA("JointInstance")
		or inst:IsA("Constraint")
		or inst:IsA("WeldConstraint")
		or inst:IsA("NoCollisionConstraint")
end

--[[ The car's own bounding box, expressed in the car's frame.

	Every extent is projected off each part's box axes rather than read out of `Size`, because the
	wheels are rotated about their axles: a wheel's `Size.Y` is not its vertical extent, and using it
	drops the car through the deck by most of a wheel. It matters in X and Z too — several roster
	bodies are one mesh per material rather than per side, so a "part" can be both headlights at once
	and its box is nothing like axis-aligned.

	`Model:GetExtentsSize` would answer none of this: with no PrimaryPart it measures a WORLD
	axis-aligned box, and the roster cars sit at arbitrary world orientations. ]]
function CarDisplay.measure(parts: Offsets): Extents
	local e: Extents = { minX = math.huge, maxX = -math.huge, minY = math.huge, minZ = math.huge, maxZ = -math.huge }
	local any = false

	for part, offset in parts do
		local size = part.Size
		local right, up, look = offset.RightVector, offset.UpVector, offset.LookVector
		local position = offset.Position
		local halfX = 0.5 * (math.abs(right.X) * size.X + math.abs(up.X) * size.Y + math.abs(look.X) * size.Z)
		local halfY = 0.5 * (math.abs(right.Y) * size.X + math.abs(up.Y) * size.Y + math.abs(look.Y) * size.Z)
		local halfZ = 0.5 * (math.abs(right.Z) * size.X + math.abs(up.Z) * size.Y + math.abs(look.Z) * size.Z)

		e.minX = math.min(e.minX, position.X - halfX)
		e.maxX = math.max(e.maxX, position.X + halfX)
		e.minY = math.min(e.minY, position.Y - halfY)
		e.minZ = math.min(e.minZ, position.Z - halfZ)
		e.maxZ = math.max(e.maxZ, position.Z + halfZ)
		any = true
	end

	if not any then
		return { minX = 0, maxX = 0, minY = 0, minZ = 0, maxZ = 0 }
	end
	return e
end

--[[ The largest showroom angle this car can be turned to and still stand on the surface under it.

	A yaw ceiling is a look, not a promise. Turned by θ, a `width` x `length` car needs

	    w*cos(θ) + l*sin(θ)  across the surface        w*sin(θ) + l*cos(θ)  along it

	and the roster is not one size: most bodies are about 9 studs wide, while `Sian` — the one
	12.90-wide Lamborghini in the set — is wider than a showroom deck and hangs a wheel off the edge
	at any angle at all. So the angle is FITTED per body rather than applied per body, stepping down
	a degree at a time until it fits, and a car that will not fit square is placed square anyway
	(there is nothing better to do with it, and at that point it is the surface that is wrong).

	`ceiling` degrees of iterations per call, on a path that runs when a car is placed. ]]
function CarDisplay.fitYaw(width: number, length: number, deckWidth: number, deckDepth: number, ceiling: number): number
	for degrees = math.floor(ceiling), 1, -1 do
		local radians = math.rad(degrees)
		local sin, cos = math.abs(math.sin(radians)), math.abs(math.cos(radians))
		if width * cos + length * sin <= deckWidth and width * sin + length * cos <= deckDepth then
			return degrees
		end
	end
	return 0
end

--[[ Build one. Returns `(model, offsets, extents)`, or nil for a body the roster does not have.

	THE MODEL COMES BACK UNPARENTED AND UNPLACED — every part still sits at the source car's world
	pose. That is deliberate: the caller measures with `extents`, decides a target, calls `place`,
	and only then parents, so the car appears finished rather than sliding into position from
	wherever the roster master happens to stand.

	The paint and the plate ARE already on, for the same reason: a car that pops in wearing stock
	livery for one frame and then changes colour reads as a bug. `paint` is a palette index
	(`PaintConfig`); nil leaves the authored livery alone. ]]
function CarDisplay.build(bodyName: string, paint: number?, options: Options?): (Model?, Offsets, Extents)
	local opts = options or {} :: Options
	local empty: Offsets = {}
	local blank: Extents = { minX = 0, maxX = 0, minY = 0, minZ = 0, maxZ = 0 }

	--- Through `CarRoster` rather than off Workspace, because the roster is relocated to
	--- ServerStorage as the server boots. Every caller of this function is a service.
	local source = CarRoster.car(bodyName, opts.rosterFolder or DEFAULT_ROSTER)
	local dress = source and source:FindFirstChild(opts.bodyFolder or DEFAULT_BODY)
	if not (source and dress) then
		return nil, empty, blank
	end

	local carCF = source:GetPivot()
	local clone = dress:Clone()
	clone.Name = opts.name or DEFAULT_NAME

	local hitBox = clone:FindFirstChild(opts.hitBoxName or DEFAULT_HITBOX, true)
	if hitBox then
		hitBox:Destroy()
	end

	local castShadow = opts.castShadow == true
	local offsets: Offsets = {}
	for _, descendant in clone:GetDescendants() do
		if CarDisplay.tiesToAnotherPart(descendant) then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			offsets[descendant] = carCF:Inverse() * descendant.CFrame
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = castShadow
		end
	end

	CarPaint.apply(clone, paint, bodyName)

	--[[ Its plate. The number is hashed out of body-and-colour (`PlateConfig.forKey`), so the car on
		this stand reads the same as the one the player parks in the street and the one on their
		dealership card, with nothing stored and nothing passed between the three. ]]
	CarPlate.apply(clone, bodyName, paint)

	return clone, offsets, CarDisplay.measure(offsets)
end

--- Write the offsets against a target frame. Header note 2 is why this is a loop and not a `PivotTo`.
function CarDisplay.place(offsets: Offsets, target: CFrame)
	for part, offset in offsets do
		part.CFrame = target * offset
	end
end

--[[ A hand-placed marker part read as a place to stand a car (or a person): feet on its BOTTOM face,
	facing its FRONT face flattened to the ground. Also hides the part (invisible, non-colliding,
	query-blind), so a marker can be left bright in Studio. nil for a missing part or one facing
	straight up or down. The stands' shared convention (`GroupRewardService`, `BundleService`). ]]
function CarDisplay.markerFrame(part: Instance?): CFrame?
	if not (part and part:IsA("BasePart")) then
		return nil
	end
	part.Transparency, part.CanCollide, part.CanQuery, part.CanTouch = 1, false, false, false
	local look = part.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 1e-3 then
		return nil
	end
	local origin = part.Position - Vector3.yAxis * (part.Size.Y / 2)
	return CFrame.lookAt(origin, origin + look.Unit, Vector3.yAxis)
end

--[[ The frame that stands a built car on a flat surface: wheels on the top face, box centred over
	the point, nose down `facing`.

	CENTRED ON ITS BOX, NOT ON ITS PIVOT. The two are not the same thing on a roster body — the pivot
	comes from the chassis `FloorPanel`, and a dress fitted around it can sit a stud or so forward of
	centre. Parking by pivot leaves those cars visibly off their surface. ]]
function CarDisplay.standOn(extents: Extents, centre: Vector3, surfaceY: number, facing: CFrame, lift: number): CFrame
	local position = Vector3.new(centre.X, surfaceY - extents.minY + lift, centre.Z)
	return CFrame.lookAt(position, position + facing.LookVector, Vector3.yAxis)
		* CFrame.new(-(extents.minX + extents.maxX) / 2, 0, -(extents.minZ + extents.maxZ) / 2)
end

return CarDisplay
