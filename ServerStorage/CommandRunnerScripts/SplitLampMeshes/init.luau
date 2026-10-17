--[[
	SplitLampMeshes, a Command Runner command

	Replaces lamp meshes that span the whole car with a LEFT half and a RIGHT half, so a turn signal
	(`Modules/CarBlinkers`) has a lamp of its own on each side to light. The list is `SPLITS` below
	and it is the whole command; everything else here is placing, checking and reporting.

	=== WHY THESE CARS ========================================================================

	`CarBlinkers` lights the lamps that sit wholly on one side of the car, and skips a lamp that
	crosses the centreline, because flashing a full-width tail bar would read as hazards. The Camaro
	(`light_red_01`, the red Neon bar) and the Challenger (`lens_red_01`, both tail lamp rectangles)
	draw their rear lamps as one mesh each, and nothing else at the back of either car is a lamp, so
	they had no rear blinker at all until those meshes were split.

	THE ROWS THAT ARE NOT HERE. On 2026-09-17 this command first split thirteen meshes on six cars,
	adding `GT`, `EVO`, `F5` and `350Z`. It was wrong about those four: the lamp you SEE on them is
	not the lamp mesh but a per side `glass_NN` cover in front of it, and once `CarBlinkers` learned
	to count those covers all four blinked without any split. Their eleven meshes were merged back
	the same day with `Revert` (every part back to its original mesh, size and position within
	0.0001 studs) and the rows deleted, because the fewer of a vendor's meshes this game carries as
	edited copies, the better. `BRZ/FRS/GT86` looked like a split too and was a rename instead: its
	lamps were already separate parts named as bodywork (`ApplyPaintRenames`).

	=== WHERE THE HALVES CAME FROM ============================================================

	The meshes are not readable in Studio (`CreateEditableMeshAsync` refuses them, and solid
	modelling rejects them as non-manifold), so the split was done offline: each source mesh was
	fetched through Open Cloud asset delivery, decoded (mesh v7, Draco), and its triangles divided by
	which side of the car's centreline their centroid falls on, keeping positions, normals and UVs
	exactly. Every mesh turned out to be two mirrored islands with a clear gap between them, so each
	half holds exactly half the triangles and no triangle was cut. The halves were uploaded as one
	model (asset 102135968770826, which also still holds the eleven unused ones) and each half's
	stored `InitialSize` matched the split to the fourth decimal on every axis, so the import neither
	rotated nor rescaled anything.

	=== HOW A HALF IS PLACED ==================================================================

	A MeshPart draws its mesh's bounding box stretched to `Size` and centred on `CFrame`. The halves
	keep the source mesh's own coordinates, so for each half the row records its box centre as an
	`offset` from the source box centre, and its box `size`, both in MESH units. The command scales
	both by the source part's `Size / MeshSize` and lays the half in the source part's frame. A half
	therefore lands exactly where its triangles were, and the pair renders identically to the part
	it replaces. `meshSize` guards that: a source part whose `MeshSize` does not match the row is a
	different mesh from the one that was split, and the row is refused.

	The halves are CLONES of the source part with the mesh swapped (`ApplyMesh`), so every authored
	property carries over: texture, material, colour, `DoubleSided`, fidelity, attributes. The
	clone's `WeldConstraint` is destroyed BEFORE anything else is written, because a cloned roster
	part still welds to the master car and writing its CFrame drags the car (see the
	welded-clone-drags-the-roster note). Each half is placed while unparented, then parented, then
	welded to whatever the source was welded to.

	=== WHAT IT TOUCHES =======================================================================

	`Workspace.CarSystem` and nothing else. That folder is the master roster, not in git, and every
	other copy of a car (traffic shells, the lobby car, the garage podium, dealership viewports) is
	cloned from it, so this is the one place the change has to be made.

	IDEMPOTENT. A rig that already has both halves and no source part reports `already`. A rig with
	the source part AND a half is refused as `collision`. `Revert` runs the other way, rebuilding the
	whole part from its left half with the same checks. Wrap a hand run in a ChangeHistoryService
	recording; `AutoRecordChanges` covers a run from the plugin.
]]

local AssetService = game:GetService("AssetService")

local Types = require(script.Types)

local ROSTER = "CarSystem"
local BODY_FOLDER = "Body"
-- Relative tolerance on `MeshSize`, which Roblox stores as float32.
local MESH_SIZE_TOLERANCE = 1e-3
local SIDES = { { key = "left", suffix = "_left" }, { key = "right", suffix = "_right" } }

type Half = { mesh: number, offset: Vector3, size: Vector3 }
type Split = { body: string, from: string, sourceMesh: number, meshSize: Vector3, left: Half, right: Half }

--[[ The splits. Generated from the offline split (see the header), one row per source part. Do not
	edit the vectors by hand: they are in MESH units and only mean something against the mesh the
	row's `meshSize` names. ]]
local SPLITS: { Split } = {
	{
		body = "Camaro",
		from = "light_red_01",
		sourceMesh = 135544464478516,
		meshSize = Vector3.new(116.601746, 52.0203247, 646.899414),
		left = { mesh = 128894086703190, offset = Vector3.new(0, 0, 226.64949), size = Vector3.new(116.601624, 52.0202637, 193.600464) },
		right = { mesh = 106799460878240, offset = Vector3.new(0.000122070312, 0, -226.600639), size = Vector3.new(116.601501, 52.0202637, 193.698166) },
	},
	{
		body = "Challenger",
		from = "lens_red_01",
		sourceMesh = 102423181805041,
		meshSize = Vector3.new(184.900085, 44.7601776, 696.801758),
		left = { mesh = 122303546564035, offset = Vector3.new(0.000122070312, 0, 264.300293), size = Vector3.new(184.899841, 44.7601471, 168.201172) },
		right = { mesh = 134611350917008, offset = Vector3.new(0, 0, -264.248779), size = Vector3.new(184.899963, 44.7601166, 168.304199) },
	},
}

local function jointOf(part: BasePart): BasePart?
	for _, child in part:GetChildren() do
		if child:IsA("WeldConstraint") and child.Part0 and child.Part1 then
			return if child.Part0 == part then child.Part1 else child.Part0
		end
	end
	return nil
end

local function sameSize(a: Vector3, b: Vector3): boolean
	for _, axis in { "X", "Y", "Z" } do
		local x, y = (a :: any)[axis], (b :: any)[axis]
		if math.abs(x - y) > MESH_SIZE_TOLERANCE * math.max(math.abs(y), 1) then
			return false
		end
	end
	return true
end

-- A copy of `template` wearing `mesh`, with every authored property of the template and none of its
-- joints. Not yet sized, placed, parented or welded.
local function remesh(template: MeshPart, mesh: number): MeshPart
	local donor = AssetService:CreateMeshPartAsync(Content.fromUri("rbxassetid://" .. tostring(mesh)), {
		CollisionFidelity = template.CollisionFidelity,
		RenderFidelity = template.RenderFidelity,
	})
	local part = template:Clone()
	-- FIRST, before any write: the clone's weld still points at the master car.
	for _, child in part:GetChildren() do
		if child:IsA("WeldConstraint") or child:IsA("JointInstance") or child:IsA("Constraint") then
			child:Destroy()
		end
	end
	part:ApplyMesh(donor)
	donor:Destroy()
	-- `ApplyMesh` is documented to carry the mesh and its fidelity only; restate the rest anyway so a
	-- change in what it copies cannot quietly strip the texture or the double-sidedness.
	part.TextureID = template.TextureID
	pcall(function()
		part.DoubleSided = template.DoubleSided
	end)
	return part
end

-- One half, built and placed but not yet parented or welded.
local function buildHalf(source: MeshPart, half: Half, name: string): MeshPart
	local part = remesh(source, half.mesh)
	local scale = source.Size / source.MeshSize
	part.Size = half.size * scale
	part.CFrame = source.CFrame * CFrame.new(half.offset * scale)
	part.Name = name
	return part
end

-- The inverse: the whole source part rebuilt from its left half, which carries the same frame, the
-- same scale and the same properties. Not yet parented or welded.
local function buildWhole(left: MeshPart, split: Split): MeshPart
	local part = remesh(left, split.sourceMesh)
	local scale = left.Size / split.left.size
	part.Size = split.meshSize * scale
	part.CFrame = left.CFrame * CFrame.new(-split.left.offset * scale)
	part.Name = split.from
	return part
end

return {
	Description = "Splits full-width lamp meshes into a left and a right half, so turn signals can light one side.",
	Tags = { "cars", "art", "roster", "lights" },
	AutoRecordChanges = true,

	Arguments = {
		Body = {
			Type = "string",
			Default = "",
			Description = "Only touch this body (blank = every body in the list).",
			PlaceholderText = "blank for all",
			ClearTextOnFocus = true,
			LayoutOrder = 1,
		},
		DryRun = {
			Type = "boolean",
			Default = false,
			Description = "Report what would change without touching the roster.",
			LayoutOrder = 2,
		},
		Revert = {
			Type = "boolean",
			Default = false,
			Description = "Merge the halves back into the original part instead of splitting.",
			LayoutOrder = 3,
		},
	} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()
		out:clear()

		-- The roster was parked in ServerStorage on 2026-10-13; Workspace still wins if dragged back.
		local folder = workspace:FindFirstChild(ROSTER) or game:GetService("ServerStorage"):FindFirstChild(ROSTER)
		if not folder then
			out:error(string.format("No %s in Workspace or ServerStorage.", ROSTER))
			return
		end
		local only = if type(arguments.Body) == "string" and arguments.Body ~= "" then arguments.Body else nil
		local dry = arguments.DryRun == true
		local revert = (arguments :: any).Revert == true

		local counts = {}
		local function report(split: Split, state: string, note: string?)
			counts[state] = (counts[state] or 0) + 1
			out:print(string.format("%-12s %-16s %-10s %s", split.body, split.from, state, note or ""))
		end

		out:print(string.format("%-12s %-16s %-10s %s", "body", "part", "state", "note"))
		for _, split in SPLITS do
			if only and split.body ~= only then
				continue
			end
			local rig = folder:FindFirstChild(split.body)
			local dress = rig and rig:FindFirstChild(BODY_FOLDER)
			if not dress then
				report(split, "missing", "no rig or no Body folder")
				continue
			end

			local source = dress:FindFirstChild(split.from)
			local halvesPresent = 0
			for _, side in SIDES do
				if dress:FindFirstChild(split.from .. side.suffix) then
					halvesPresent += 1
				end
			end

			if revert then
				local left = dress:FindFirstChild(split.from .. SIDES[1].suffix)
				local right = dress:FindFirstChild(split.from .. SIDES[2].suffix)
				if source and halvesPresent == 0 then
					report(split, "already", "whole")
				elseif source or halvesPresent ~= 2 then
					report(split, "collision", "not exactly two halves and no source, refusing to guess")
				elseif not (left:IsA("MeshPart") and right:IsA("MeshPart")) then
					report(split, "refused", "a half is not a MeshPart")
				else
					local mount = jointOf(left)
					if not mount then
						report(split, "refused", "the left half is welded to nothing")
					elseif dry then
						report(split, "would", "merge back, welded to " .. mount.Name)
					else
						local mountBefore = mount.CFrame
						local ok, whole = pcall(buildWhole, left, split)
						if not ok then
							report(split, "failed", tostring(whole))
						else
							whole.Parent = left.Parent
							local weld = Instance.new("WeldConstraint")
							weld.Part0, weld.Part1 = mount, whole
							weld.Parent = whole
							left:Destroy()
							right:Destroy()
							local drift = (mount.CFrame.Position - mountBefore.Position).Magnitude
							report(split, "merged", if drift > 1e-3 then string.format("WARNING the mount moved %.3f studs", drift) else "welded to " .. mount.Name)
						end
					end
				end
				continue
			end

			if not source then
				report(split, if halvesPresent == 2 then "already" else "missing", if halvesPresent == 2 then nil else "no source part and no halves")
				continue
			end
			if halvesPresent > 0 then
				report(split, "collision", "the source part AND a half exist, refusing to guess")
				continue
			end
			if not source:IsA("MeshPart") then
				report(split, "refused", "source is not a MeshPart")
				continue
			end
			if not sameSize(source.MeshSize, split.meshSize) then
				report(split, "refused", string.format("MeshSize %s is not the mesh this row was split from", tostring(source.MeshSize)))
				continue
			end
			local mount = jointOf(source)
			if not mount then
				report(split, "refused", "source is welded to nothing")
				continue
			end
			if dry then
				report(split, "would", "welded to " .. mount.Name)
				continue
			end

			local mountBefore = mount.CFrame
			local built = {}
			local ok, err = pcall(function()
				for _, side in SIDES do
					table.insert(built, buildHalf(source, (split :: any)[side.key], split.from .. side.suffix))
				end
			end)
			if not ok then
				for _, part in built do
					part:Destroy()
				end
				report(split, "failed", tostring(err))
				continue
			end

			for _, part in built do
				part.Parent = source.Parent
				local weld = Instance.new("WeldConstraint")
				weld.Part0, weld.Part1 = mount, part
				weld.Parent = part
			end
			source:Destroy()

			local drift = (mount.CFrame.Position - mountBefore.Position).Magnitude
			if drift > 1e-3 then
				report(split, "split", string.format("WARNING the mount moved %.3f studs", drift))
			else
				report(split, "split", string.format("%s + %s, welded to %s", built[1].Name, built[2].Name, mount.Name))
			end
		end

		local summary = {}
		for state, n in counts do
			table.insert(summary, string.format("%d %s", n, state))
		end
		table.sort(summary)
		out:print("")
		out:print((if dry then "Would apply: " else "Applied: ") .. table.concat(summary, ", "))
	end,
} :: Types.ScriptModule
