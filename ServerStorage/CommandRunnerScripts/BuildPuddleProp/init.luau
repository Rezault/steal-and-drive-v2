--[[
	BuildPuddleProp: Command Runner command

	Cuts `Workspace.Assets.Weather.Puddle` out of world 3's black ice sheet (`Assets.World3.Ice`) and
	reskins it as water, so the rain's `Puddle` obstacle kind (`ObstacleConfig.Kinds.Puddle`) is a
	delivered mesh like every other prop rather than the round primitive it falls back to.

	=== WHY THE ICE SHEET =====================================================

	Because it is already the right object: one flat MeshPart (`Plane.021`, mesh `94226701966129`) with
	an irregular, pooled outline, a third of a stud thick. A frozen puddle and a wet one are the same
	shape; only the surface differs. Dylan pointed at it for exactly this.

	=== WHY `Assets.Weather` AND NOT A WORLD'S FOLDER =========================

	The rain can fall on any of the four roads, so its puddle belongs to none of them.
	`ObstacleService._publishProps` publishes every kind the weather can lay into EVERY map's prop
	folder, from `Assets.<ObstacleConfig.Puddles.SourceFolderName>` (this folder) unless the map's own
	art folder has one by the same name. A world that wants a themed puddle can have one by dropping
	it in there; nothing here needs to change.

	=== WHAT IT IS NOT ========================================================

	NOT A RESIZE. `_fitProp` scales it to `Kinds.Puddle.Art.Width` at server start, and every puddle on
	the road is then turned and sized again by `ObstacleController._dressPuddle`. Nothing here touches
	scale.

	NOT A REPAINT OF THE ICE. The source keeps its pale Glacier; black ice is the harshest slick in the
	game and a puddle the gentlest, and on world 3's road in the rain both can be lying on the same
	tile. They share an outline, so the SURFACE is what tells them apart: pale, bright and patterned
	against dark, glossy and rippling. That difference is the whole job of the constants below.

	IDEMPOTENT. An existing `Puddle` is destroyed and re-cut every run.
]]

local ServerStorage = game:GetService("ServerStorage")

local Types = require(script.Types)

-- === Scope ==================================================================

local ASSETS_FOLDER = "Assets"
local SOURCE_WORLD = "World3"
local SOURCE_MODEL = "Ice"
local TARGET_FOLDER = "Weather" -- ObstacleConfig.Puddles.SourceFolderName
local PROP_NAME = "Puddle" -- ObstacleConfig.Kinds.Puddle.Art.Model

--- The sheet inside `Ice`, by mesh rather than by name: `Plane.021` is a Blender export name and a
--- redelivery can renumber it. Name is tried first anyway, so a set that keeps its names costs no search.
local SHEET_PART_NAME = "Plane.021"
local SHEET_MESH_ID = "rbxassetid://94226701966129"

-- === Look ===================================================================

--[[ WATER ON ASPHALT READS LIGHTER THAN THE ROAD, NOT DARKER, and that is the one thing to hold on to
	when tuning this. A real puddle is a mirror of the sky lying on a dark surface, so what you see is
	the overcast, a shade darker. A puddle painted darker than the deck is a stain, which is oil's
	look and exactly the hazard this must not be mistaken for.

	So it is `Glass`, a little see-through, in a cool slate: the road shows through at the rim where
	water is shallow, and the surface picks up the sky. ]]
local WATER_MATERIAL = Enum.Material.Glass
local WATER_COLOR = Color3.fromRGB(78, 92, 108)
local WATER_TRANSPARENCY = 0.15
local WATER_REFLECTANCE = 0.25

--[[ Parked at the end of the authoring row, past world 4's props, so the set still reads as a set in
	the Explorer and the viewport. Authoring convenience ONLY: the road places obstacles with `PivotTo`
	and never reads this. ]]
local PARK_WORLD = "World4"
local PARK_BESIDE = "Bridge"
local PARK_OFFSET = Vector3.new(0, 0, 34)

-- === Build ==================================================================

-- The authoring folder, wherever it currently lives. Workspace in edit mode; ServerStorage if
-- `RelocationService` has already swept it, which is what happens the moment anybody playtests.
local function findAssets(): Instance?
	return workspace:FindFirstChild(ASSETS_FOLDER) or ServerStorage:FindFirstChild(ASSETS_FOLDER)
end

local function findSheet(source: Instance): MeshPart?
	local named = source:FindFirstChild(SHEET_PART_NAME)
	if named and named:IsA("MeshPart") then
		return named
	end
	for _, part in source:GetDescendants() do
		if part:IsA("MeshPart") and part.MeshId == SHEET_MESH_ID then
			return part
		end
	end
	return nil
end

-- World-space AABB, the measurement `ObstacleService._fitProp` makes, for its reason: a delivered
-- pivot is arbitrary, so `GetBoundingBox` reports a box that has already been un-turned.
local function worldBounds(model: Instance): (Vector3?, Vector3?)
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
	Description = "Cut Assets.Weather.Puddle out of Assets.World3.Ice and reskin it as water, so the rain's Puddle obstacle is a delivered mesh instead of a round primitive. Idempotent.",
	Tags = { "Obstacles", "Props", "Weather" },
	AutoRecordChanges = true,

	Arguments = {} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		local assets = findAssets()
		local world = assets and assets:FindFirstChild(SOURCE_WORLD)
		local source = world and world:FindFirstChild(SOURCE_MODEL)
		if not source then
			out:error(
				string.format("Could not find %s.%s.%s in Workspace or ServerStorage.", ASSETS_FOLDER, SOURCE_WORLD, SOURCE_MODEL)
			)
			return
		end

		local sheet = findSheet(source)
		if not sheet then
			out:error(
				string.format(
					"No sheet in %s: expected a MeshPart named %s or carrying mesh %s.",
					source:GetFullName(),
					SHEET_PART_NAME,
					SHEET_MESH_ID
				)
			)
			return
		end

		local folder = assets:FindFirstChild(TARGET_FOLDER)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = TARGET_FOLDER
			folder.Parent = assets
		end

		local existing = folder:FindFirstChild(PROP_NAME)
		local replaced = existing ~= nil
		if existing then
			existing:Destroy()
		end

		local prop = Instance.new("Model")
		prop.Name = PROP_NAME

		local water = sheet:Clone()
		water.Name = "Water"
		water.Material = WATER_MATERIAL
		water.Color = WATER_COLOR
		water.Transparency = WATER_TRANSPARENCY
		water.Reflectance = WATER_REFLECTANCE
		-- A third of a stud of water lying on the deck has no shadow worth drawing, and a flat sheet
		-- that casts one onto the road right under itself only ever shows as a dark fringe.
		water.CastShadow = false
		--[[ Anchored and inert here as well as in `_fitProp`, because the authoring copy sits in
			Workspace, where an unanchored part falls through the world the first time anybody
			playtests with `Assets` still parented there. ]]
		water.Anchored = true
		water.CanCollide = false
		water.CanQuery = false
		water.CanTouch = false
		-- The source's own turn is kept: `Kinds.Puddle.Art.Yaw` is written against the ice's
		-- delivered orientation, and every puddle is turned to a random angle on the road anyway.
		water.Parent = prop

		-- No PrimaryPart, for `BuildBarrelProp`'s reason: `_fitProp` would only have to clear it.
		prop.Parent = folder

		local parkWorld = assets:FindFirstChild(PARK_WORLD)
		local anchor = parkWorld and parkWorld:FindFirstChild(PARK_BESIDE)
		if anchor then
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
				"%s %s from %s's sheet: %s %d,%d,%d at transparency %.2f, reflectance %.2f. Delivered size %.2f x %.2f x %.2f; ObstacleService scales it to Kinds.Puddle.Art.Width at server start.",
				if replaced then "Re-cut" else "Cut",
				prop:GetFullName(),
				SOURCE_MODEL,
				WATER_MATERIAL.Name,
				math.round(WATER_COLOR.R * 255),
				math.round(WATER_COLOR.G * 255),
				math.round(WATER_COLOR.B * 255),
				WATER_TRANSPARENCY,
				WATER_REFLECTANCE,
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
