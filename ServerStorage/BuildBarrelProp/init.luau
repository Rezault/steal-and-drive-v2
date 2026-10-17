--[[
	BuildBarrelProp — Command Runner command

	Cuts `Workspace.Assets.World1.Barrel` out of the drum already standing in
	`Workspace.Assets.World1.Oil`, recoloured, so the `Barrel` obstacle kind stops being three loose
	primitive cylinders and becomes one delivered mesh like every other world-1 prop.

	=== WHY IT EXISTS =========================================================

	THE BUG IT FIXES IS THE SMASH, not the look. `ObstacleController._smash` throws a hit prop by
	writing the SAME `AssemblyAngularVelocity` onto every part of it. On a welded assembly that is one
	write repeated and the thing tumbles as one object. The primitive `Barrel` is not welded — the
	fallback `Build` path makes loose parts — so its two dark bands spun about their OWN centres
	instead of orbiting the body's, and a barrel you hit came apart into a cylinder with two rings
	drifting out of it. Reported as "the mid-part kind of comes off".

	A barrel coming apart is not even wrong as an idea (`Crate` asks for exactly that with
	`Smash.Break`), but the pieces have to be pieces someone modelled. Two rings sliding through a
	cylinder are not. The delivered drum is a SINGLE MeshPart, so the failure mode cannot happen at
	all: one part, one spin.

	=== WHY THE OIL DRUM ======================================================

	Because it is already the right object. `Oil`'s hazard is a spill with a drum standing in it, and
	that drum (`Cylinder.072`, mesh `104939548328095`) is a ribbed 55-gallon barrel with rolling hoops
	modelled in. Cutting the `Barrel` kind from the same mesh means the two kinds are the same object
	in two liveries rather than two different guesses at what a barrel looks like — which is the whole
	reason the primitive read as out of place next to the modeller's cone and barricade.

	=== WHAT IT IS NOT ========================================================

	NOT A RESIZE. The prop is delivered at whatever size the modeller drew it and
	`ObstacleService._fitProp` scales it to `ObstacleConfig.Kinds.Barrel.Art.Width` at server start.
	Nothing here should touch scale — see the `Art.Width` note in `ObstacleConfig`, which is where the
	5-stud figure and its arithmetic live.

	NOT A REPAINT OF THE OIL DRUM. The source keeps its red. Blue is the copy's, and it has a job:
	one drum is a solid you smash for 12 HP and the other is a slick that takes your grip, and at
	85 studs/s a player has about half a second to tell them apart. They are the same silhouette now,
	so colour is the only thing left doing that work.

	IDEMPOTENT. An existing `Barrel` is destroyed and re-cut every run.
]]

local ServerStorage = game:GetService("ServerStorage")

local Types = require(script.Types)

-- === Scope ==================================================================

local ASSETS_FOLDER = "Assets"
local WORLD_FOLDER = "World1"
local SOURCE_MODEL = "Oil"
local PROP_NAME = "Barrel"

--[[ The drum inside `Oil`, by mesh rather than by name. `Cylinder.072` is a Blender export name and
	the next redelivery of that set can renumber it; the mesh id is the thing that actually says
	"this is the drum". Name is tried first anyway, so a set that keeps its names costs no search. ]]
local DRUM_PART_NAME = "Cylinder.072"
local DRUM_MESH_ID = "rbxassetid://104939548328095"

-- === Look ===================================================================

--[[ Chosen against the four the road already has — orange cone, yellow/black barricade, red oil drum,
	grey asphalt — because it is the only one of them that is not already spoken for. Steel read as
	the deck it stands on, amber read as the barricade, and rust read as the oil drum, which is the
	one confusion that costs a player HP. ]]
local BARREL_COLOR = Color3.fromRGB(38, 92, 178)

--[[ Whatever the source drum wears, which today is `Glacier` across the whole delivered world-1 set.
	Copied rather than named so a re-lit set does not leave this one prop behind; `nil` keeps it. ]]
local BARREL_MATERIAL: Enum.Material? = nil

--[[ Where the cut prop is parked in the authoring line. The world-1 props stand in a row along Z at
	x ≈ -1071 and this drops into the 24-stud hole between `Barrier` and `Oil`, so the set still reads
	as a set in the Explorer and in the viewport. Placement is authoring convenience ONLY — the road
	places obstacles with `PivotTo` and never reads this. ]]
	Parked off `Barrier` and not off `Oil`, even though `Oil` is where the mesh comes from: `Oil`'s
	bounding box is dominated by its two spill planes, so its centre is 4.5 studs off the line the
	rest of the row stands on and a barrel parked from it lands out of the queue. ]]
local PARK_BESIDE = "Barrier"
local PARK_OFFSET = Vector3.new(0, 0, 12)

-- === Build ==================================================================

-- The authoring folder, wherever it currently lives. Workspace in edit mode; ServerStorage if
-- `RelocationService` has already swept it, which is what happens the moment anybody playtests.
local function findWorldFolder(): Instance?
	local assets = workspace:FindFirstChild(ASSETS_FOLDER) or ServerStorage:FindFirstChild(ASSETS_FOLDER)
	return assets and assets:FindFirstChild(WORLD_FOLDER)
end

local function findDrum(source: Instance): MeshPart?
	local named = source:FindFirstChild(DRUM_PART_NAME)
	if named and named:IsA("MeshPart") then
		return named
	end
	for _, part in source:GetDescendants() do
		if part:IsA("MeshPart") and part.MeshId == DRUM_MESH_ID then
			return part
		end
	end
	return nil
end

-- World-space AABB, the same measurement `ObstacleService._fitProp` makes, and for the same reason:
-- a delivered pivot is arbitrary so `GetBoundingBox` reports a box that has already been un-turned.
local function worldBounds(model: Model): (Vector3?, Vector3?)
	local min, max
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local half = part.Size * 0.5
			for x = -1, 1, 2 do
				for y = -1, 1, 2 do
					for z = -1, 1, 2 do
						local corner = part.CFrame * Vector3.new(half.X * x, half.Y * y, half.Z * z)
						min = min and min:Min(corner) or corner
						max = max and max:Max(corner) or corner
					end
				end
			end
		end
	end
	return min, max
end

return {
	Description = "Cut Assets.World1.Barrel out of the drum inside Assets.World1.Oil and recolour it, so the Barrel obstacle is one delivered mesh instead of three loose primitive cylinders. Idempotent.",
	Tags = { "Obstacles", "Props", "World1" },
	AutoRecordChanges = true,

	Arguments = {} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		local world = findWorldFolder()
		if not world then
			out:error(
				string.format("Could not find %s.%s in Workspace or ServerStorage.", ASSETS_FOLDER, WORLD_FOLDER)
			)
			return
		end

		local source = world:FindFirstChild(SOURCE_MODEL)
		if not source then
			out:error(string.format("%s has no %s to cut the drum out of.", world:GetFullName(), SOURCE_MODEL))
			return
		end

		local drum = findDrum(source)
		if not drum then
			out:error(
				string.format(
					"No drum in %s: expected a MeshPart named %s or carrying mesh %s.",
					source:GetFullName(),
					DRUM_PART_NAME,
					DRUM_MESH_ID
				)
			)
			return
		end

		local existing = world:FindFirstChild(PROP_NAME)
		local replaced = existing ~= nil
		if existing then
			existing:Destroy()
		end

		local prop = Instance.new("Model")
		prop.Name = PROP_NAME

		local body = drum:Clone()
		body.Name = "Drum"
		body.Color = BARREL_COLOR
		if BARREL_MATERIAL then
			body.Material = BARREL_MATERIAL
		end
		--[[ Anchored and inert here as well as in `_fitProp`, because the authoring copy sits in
			Workspace where an unanchored part falls through the world the first time anybody
			playtests with `Assets` still parented there. ]]
		body.Anchored = true
		body.CanCollide = false
		body.CanQuery = false
		body.CanTouch = false
		body.Parent = prop

		--[[ No PrimaryPart, deliberately. `_fitProp` clears it before setting `WorldPivot` because a
			Model with one reports that PART's frame as its pivot and ignores `WorldPivot` outright —
			so shipping one would only be a thing the fitter has to undo. ]]
		prop.Parent = world

		local anchor = world:FindFirstChild(PARK_BESIDE)
		if anchor and anchor:IsA("Model") then
			local min, max = worldBounds(anchor)
			local ourMin, ourMax = worldBounds(prop)
			if min and max and ourMin and ourMax then
				-- Same ground line as the prop it parks next to, so the row stands on one floor.
				local footprint = Vector3.new((ourMin.X + ourMax.X) * 0.5, ourMin.Y, (ourMin.Z + ourMax.Z) * 0.5)
				local target = Vector3.new((min.X + max.X) * 0.5, min.Y, (min.Z + max.Z) * 0.5) + PARK_OFFSET
				prop:PivotTo(prop:GetPivot() + (target - footprint))
			end
		end

		local min, max = worldBounds(prop)
		local extent = (min and max) and (max - min) or Vector3.zero
		out:print(
			string.format(
				"%s %s from %s's drum, coloured %d,%d,%d. Delivered size %.2f x %.2f x %.2f — ObstacleService scales it to Kinds.Barrel.Art.Width at server start.",
				if replaced then "Re-cut" else "Cut",
				prop:GetFullName(),
				SOURCE_MODEL,
				math.round(BARREL_COLOR.R * 255),
				math.round(BARREL_COLOR.G * 255),
				math.round(BARREL_COLOR.B * 255),
				extent.X,
				extent.Y,
				extent.Z
			)
		)
		pcall(function()
			props:SetSelection({ prop })
		end)
	end,
} :: Types.ScriptModule
