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
	cylinder are not.

	This prop carries two ring parts of its own (the straps, below), so the count is not what closes
	that bug — the WELD is. `ObstacleService._fitProp` welds every part of a delivered prop to the
	biggest one, which is the drum, and one `AssemblyAngularVelocity` write on a welded assembly is
	one spin about one centre. The fallback `Build` path is welded by `_buildObstacle` now for the
	same reason. Anything added here must be a part of this Model, never a loose sibling.

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

	NOT A REPAINT OF THE OIL DRUM. The source keeps its red. The copy's colour is its own, and it has
	a job: one drum is a solid you smash for 12 HP and the other is a slick that takes your grip, and
	at 85 studs/s a player has about half a second to tell them apart. They are the same silhouette,
	so colour and the straps are all that is left doing that work.

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

--[[ GREEN, AND THE REASON IS THE BACKDROP RATHER THAN THE PALETTE. The first cut of this prop was
	blue, `Color3.fromRGB(38, 92, 178)`, argued for on the grounds that orange, amber and rust were
	spoken for by the cone, the barricade and the oil drum. That reasoning only looked at the other
	PROPS, and the thing a barrel is actually seen against is the city: measured off a render, the
	sky comes back `85,177,255` and the blue drum `21,123,255` — the same hue with the blue channel
	pinned at 255 on both, standing in front of blue-grey towers. It was a darker patch of the
	background, which is what "something off about it" turned out to mean.

	Green is the only saturated hue on the world-1 road that is neither the backdrop nor another
	hazard, and it is a colour a real 55-gallon drum comes in. It does not collide with the game's
	"this one GIVES you something" language either: `BoostPad` and `GravityLift` are futuristic-map
	props, so nothing green stands on the city road to be confused with.

	Runners-up, both rendered on the deck before this was picked, in case taste says otherwise:
	cream `226,224,212` (loud, but competes with the lane markings) and the old blue kept with the
	straps below added (fixes the shape, not the hue). ]]
local BARREL_COLOR = Color3.fromRGB(40, 150, 70)

--[[ The two rolling hoops, and the whole point of them is that a MeshPart has ONE colour: the drum's
	rivets and hoops are geometry, so the only way to get a second colour onto it without splitting
	the mesh and re-uploading is to lay parts over the features. The hoops take that well because
	they are bands; the rivets do not, and are left as relief. ]]
local STRAP_COLOR = Color3.fromRGB(28, 30, 38)

--[[ Whatever the source drum wears, which today is `Glacier` across the whole delivered world-1 set.
	Copied rather than named so a re-lit set does not leave this one prop behind; `nil` keeps it. ]]
local BARREL_MATERIAL: Enum.Material? = nil

--[[ THE STRAPS ARE FRACTIONS OF THE DRUM, not stud numbers, so a re-delivered `Oil` at another size
	still lands them on the modelled hoops. Every figure was measured off a near-orthographic render
	of this mesh (camera 200 studs out at FOV 5, calibrated against the part box), because the
	geometry cannot be read any other way — `CreateEditableMeshAsync` refuses this asset with "no
	permission to load asset", the mesh being the modeller's upload and not ours.

	What that render says: the drum's own raised hoops sit at 0.336 and 0.669 of its height and are
	about 0.05 of it thick, and — the load-bearing measurement — **the mesh renders 6.68 studs wide
	inside a 7.62-stud part box**. The MeshPart's `Size` is not the geometry (a Roblox commonplace,
	and this one is 14% loose), which is what leaves room for a hoop that stands proud of the body
	and still does not touch the box.

	THAT IS WHY THE DIAMETER IS A RATIO JUST UNDER 1 AND MUST STAY THERE. `ObstacleService._fitProp`
	scales the prop by the model's world AABB against `Kinds.Barrel.Art.Width`, and the AABB is the
	drum's part box. A strap inside the box changes nothing: the barrel keeps the size the `Art.Width`
	note derives from `Oil`'s own drum, and not one authored course moves. A strap WIDER than the box
	would silently shrink the barrel by whatever it overhung.

	First attempt used 0.9 of the box — flush with the mesh, invisible past about 20 studs. The
	rivets are relief on the same surface, so a band has to clear them by a real margin to read as a
	band and not as a shadow. 0.99 stands 0.44 studs proud, which is the whole width of a rivet. ]]
local STRAP_DIAMETER_RATIO = 0.99 -- of the drum's part-box width; > 1 would rescale the barrel
local STRAP_THICKNESS_RATIO = 0.102 -- of the drum's height, i.e. twice the modelled hoop
local STRAP_HEIGHTS = { 0.669, 0.336 } -- of the drum's height, measured off the modelled hoops

--[[ Where the cut prop is parked in the authoring line. The world-1 props stand in a row along Z at
	x ≈ -1071 and this drops into the 24-stud hole between `Barrier` and `Oil`, so the set still reads
	as a set in the Explorer and in the viewport. Placement is authoring convenience ONLY — the road
	places obstacles with `PivotTo` and never reads this.

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
		body.CFrame = CFrame.new(body.Position) -- the delivered drum carries a 90 yaw; it is round
		body.Parent = prop

		--[[ Cylinder parts rather than anything cleverer: the drum is round in plan, so a cylinder
			laid on its side about the vertical axis IS a band, and it costs two parts.

			`_fitProp` welds every part of a prop to the biggest one — the drum, by `Size.Magnitude`
			— so the straps arrive on the road as part of one assembly. That matters more than it
			looks: `_smash` throws a prop by writing the same `AssemblyAngularVelocity` onto every
			part, and it was exactly an UNWELDED multi-part barrel that used to come apart mid-tumble
			(see the `Smash` note in ObstacleConfig). Welded, they orbit the drum's centre with it. ]]
		for i, height in STRAP_HEIGHTS do
			local strap = Instance.new("Part")
			strap.Name = "Strap" .. i
			strap.Shape = Enum.PartType.Cylinder
			strap.Size = Vector3.new(
				body.Size.Y * STRAP_THICKNESS_RATIO,
				body.Size.X * STRAP_DIAMETER_RATIO,
				body.Size.X * STRAP_DIAMETER_RATIO
			)
			strap.Color = STRAP_COLOR
			strap.Material = body.Material
			strap.Anchored = true
			strap.CanCollide = false
			strap.CanQuery = false
			strap.CanTouch = false
			-- A cylinder's circular axis is its X, so the 90 about Z is what stands it up.
			strap.CFrame = CFrame.new(body.Position + Vector3.new(0, (height - 0.5) * body.Size.Y, 0))
				* CFrame.Angles(0, 0, math.rad(90))
			strap.Parent = prop
		end

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
				"%s %s from %s's drum, body %d,%d,%d with %d straps at %d,%d,%d. Delivered size %.2f x %.2f x %.2f — ObstacleService scales it to Kinds.Barrel.Art.Width at server start.",
				if replaced then "Re-cut" else "Cut",
				prop:GetFullName(),
				SOURCE_MODEL,
				math.round(BARREL_COLOR.R * 255),
				math.round(BARREL_COLOR.G * 255),
				math.round(BARREL_COLOR.B * 255),
				#STRAP_HEIGHTS,
				math.round(STRAP_COLOR.R * 255),
				math.round(STRAP_COLOR.G * 255),
				math.round(STRAP_COLOR.B * 255),
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
