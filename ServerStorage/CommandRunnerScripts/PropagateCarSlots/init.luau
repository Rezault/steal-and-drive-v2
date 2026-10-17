--[[
	PropagateCarSlots — Command Runner command

	Copies the six finished `CarSlot` podiums from the reference plot onto every other plot, placed
	through each plot's own `Origin` so all six lots end up bay-for-bay identical.

	WHY THIS EXISTS. The slots were authored on Plot1 only (`docs/MapLayout.md` §4) — six podiums on
	floor 1, hand-placed against the real wall lines, at `Model:ScaleTo(0.85)` because six bays do
	not fit at 1:1. Plots 2–6 were left with an empty `CarSlots/` folder. That was fine while the
	slots were a layout exercise; it stops being fine the moment a banked car has to go somewhere,
	because five players out of six would have nowhere to park.

	IT IS A RE-PLACEMENT, NOT A PASTE, and that distinction is the whole command. The plots are rigid
	copies of one building on a circle around the plaza, so each is the reference rotated and
	translated (§3). A clone dropped at the source's world CFrame lands on Plot1 six times over. Each
	slot is therefore converted into PLOT-LOCAL space against the source's `Origin` and rebuilt
	against the target's:

	    localCF = source.Origin.CFrame:Inverse() * slot:GetPivot()
	    world   = target.Origin.CFrame * localCF

	Derived from the live geometry rather than read out of the `PlotLocalCFrame` attribute the slots
	already carry — that attribute is a human-readable STRING ("-43.1700, 2.1625, -6.0000 | yaw
	-90.0"), rounded to four places and holding yaw only, so parsing it would be both lossier and
	more fragile than the two lines above. It is re-stamped on the way out so the copies stay
	self-describing.

	FLOOR 2 IS DELIBERATELY NOT COPIED. Every plot is currently in the locked, floor-1-only state:
	`Building.Floor2` is out of Workspace, the roof is dropped onto floor 1, and the deck-2 podiums
	live at `ServerStorage.PlotUpgrades.Floor2Contents` waiting to be cloned in with the upgrade.
	Copying `CarSlot_F2_*` here would leave six podiums floating on the dropped roof — which is
	exactly the bug the locked-state work was written to avoid. So only slots whose `Floor` attribute
	is 1 are copied, and anything else is reported rather than guessed at.

	IDEMPOTENT. A target that already has a slot of the same name gets it replaced, not doubled up.
]]

local CollectionService = game:GetService("CollectionService")

local Types = require(script.Types)

-- === The map contract =======================================================

local PLOTS_PATH = { "Map", "Plots" }
local SLOTS_FOLDER_NAME = "CarSlots"
local SLOT_TAG = "CarSlot"

-- Attributes the slots already carry (MapLayout §4.1). `Floor` is what gates the copy.
local FLOOR_ATTRIBUTE = "Floor"
local INDEX_ATTRIBUTE = "SlotIndex"
local LOCAL_CFRAME_ATTRIBUTE = "PlotLocalCFrame"

-- Only floor 1 exists in the locked state. See the header.
local COPYABLE_FLOOR = 1

-- === Helpers ================================================================

--[[ The slot's base slab, which is what `PivotTo` has to be exact about.

	THE SOURCE MODEL HAS TWO CHILDREN BOTH NAMED `Platform` — the base and the top deck — so
	`slot.Platform` returns an arbitrary one of them and a clone can come out with its PrimaryPart
	pointing at either. The base is unambiguously the larger of the two by volume (16.41 x 1.43 x
	30.97 against 14.95 x 1.91 x 28.94 at 1:1), so pick by size rather than by name. ]]
local function basePlatform(slot: Model): BasePart?
	local best, bestVolume = nil, -1
	for _, child in ipairs(slot:GetDescendants()) do
		if child:IsA("BasePart") and child.Name == "Platform" then
			local volume = child.Size.X * child.Size.Y * child.Size.Z
			if volume > bestVolume then
				best, bestVolume = child, volume
			end
		end
	end
	return best
end

-- The human-readable placement string the existing slots carry, re-derived so copies match.
local function describeLocal(localCF: CFrame): string
	local _, yaw = localCF:ToOrientation()
	local p = localCF.Position
	return string.format("%.4f, %.4f, %.4f | yaw %.1f", p.X, p.Y, p.Z, math.deg(yaw))
end

local function slotsFolder(plot: Model): Folder
	local folder = plot:FindFirstChild(SLOTS_FOLDER_NAME)
	if not (folder and folder:IsA("Folder")) then
		if folder then
			folder:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = SLOTS_FOLDER_NAME
		folder.Parent = plot
	end
	return folder
end

return {
	Description = "Copies the reference plot's floor-1 CarSlot podiums onto every other plot, placed in plot-local space.",
	Tags = { "map", "plots", "garage" },
	AutoRecordChanges = true,

	Arguments = {
		SourcePlot = {
			Type = "string",
			Default = "Plot1",
			Description = "The plot the finished slots were authored on.",
			LayoutOrder = 1,
		},
		DryRun = {
			Type = "boolean",
			Default = false,
			Description = "Report what would be copied without touching anything.",
			LayoutOrder = 2,
		},
	} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		local folder: Instance = workspace
		for _, name in ipairs(PLOTS_PATH) do
			local nextFolder = folder:FindFirstChild(name)
			if not nextFolder then
				out:error(string.format("No workspace.%s — nothing to copy between.", table.concat(PLOTS_PATH, ".")))
				return
			end
			folder = nextFolder
		end

		local sourceName = if type(arguments.SourcePlot) == "string" and arguments.SourcePlot ~= "" then arguments.SourcePlot else "Plot1"
		local source = folder:FindFirstChild(sourceName)
		if not (source and source:IsA("Model") and source.PrimaryPart) then
			out:error(string.format("No %s with a PrimaryPart under %s.", sourceName, table.concat(PLOTS_PATH, ".")))
			return
		end

		local sourceSlots = source:FindFirstChild(SLOTS_FOLDER_NAME)
		if not sourceSlots then
			out:error(string.format("%s has no %s folder.", sourceName, SLOTS_FOLDER_NAME))
			return
		end

		--[[ Collect the templates first, and take the LOCAL CFrame while the source is still the
			only thing we have touched. Filtered by TAG rather than by attribute on purpose: the
			`RoughSlot_*` dev-aid cars carry the same `Floor` and `SlotIndex` attributes the real
			podiums do, and an attribute filter would sweep those up too. ]]
		local templates = {}
		local skipped = {}
		for _, slot in ipairs(sourceSlots:GetChildren()) do
			if not (slot:IsA("Model") and CollectionService:HasTag(slot, SLOT_TAG)) then
				continue
			end
			local floor = slot:GetAttribute(FLOOR_ATTRIBUTE)
			if floor ~= COPYABLE_FLOOR then
				table.insert(skipped, string.format("%s (Floor %s)", slot.Name, tostring(floor)))
				continue
			end
			table.insert(templates, {
				model = slot,
				localCF = source.PrimaryPart.CFrame:Inverse() * slot:GetPivot(),
			})
		end

		if #templates == 0 then
			out:error(string.format("%s has no floor-%d slots tagged '%s'.", sourceName, COPYABLE_FLOOR, SLOT_TAG))
			return
		end

		local targets = {}
		for _, plot in ipairs(folder:GetChildren()) do
			if plot:IsA("Model") and plot ~= source and plot.PrimaryPart then
				table.insert(targets, plot)
			end
		end

		if arguments.DryRun then
			out:print(
				string.format(
					"Dry run: would copy %d slot(s) from %s onto %d plot(s) — %d models.",
					#templates,
					sourceName,
					#targets,
					#templates * #targets
				)
			)
			for _, entry in ipairs(templates) do
				out:print(string.format("   %s  ->  %s", entry.model.Name, describeLocal(entry.localCF)))
			end
			if #skipped > 0 then
				out:warn(string.format("Not copied (only floor %d is unlocked): %s", COPYABLE_FLOOR, table.concat(skipped, ", ")))
			end
			return
		end

		local placed = {}
		for _, plot in ipairs(targets) do
			local destination = slotsFolder(plot)
			for _, entry in ipairs(templates) do
				local existing = destination:FindFirstChild(entry.model.Name)
				if existing then
					existing:Destroy()
				end

				local clone = entry.model:Clone()
				--[[ PrimaryPart before PivotTo, always. A model with no PrimaryPart pivots about its
					bounding-box centre, which for a slot is a point floating between the podium and
					its collect mat — the copy would land visibly short of the wall. ]]
				clone.PrimaryPart = basePlatform(clone)
				clone.Parent = destination
				clone:PivotTo(plot.PrimaryPart.CFrame * entry.localCF)
				clone:SetAttribute(LOCAL_CFRAME_ATTRIBUTE, describeLocal(entry.localCF))
				CollectionService:AddTag(clone, SLOT_TAG)
				table.insert(placed, clone)
			end
		end

		pcall(function()
			props:SetSelection(placed)
		end)

		if #skipped > 0 then
			out:warn(string.format("Not copied (only floor %d is unlocked): %s", COPYABLE_FLOOR, table.concat(skipped, ", ")))
		end
		out:print(
			string.format(
				"Copied %d slot(s) from %s onto %d plot(s) — %d podiums placed.",
				#templates,
				sourceName,
				#targets,
				#placed
			)
		)
	end,
} :: Types.ScriptModule
