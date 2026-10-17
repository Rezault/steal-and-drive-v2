--[[
	NormalizeRoadSegments — Command Runner command

	Takes raw imported road tiles and gives them the shape the streaming road needs: the
	OriginMarker pivot, the contract attributes, the invisible backstop walls, and the default
	map's five art buckets. Run it on `Workspace.Worlds` after any new world or variant lands.

	Read `Segment.luau` for what the contract is and why each part of it exists. This file is only
	the front end: it decides WHICH tiles get done, and forces every tile in a world onto ONE drive
	frame — tiles in the same world are meant to be interchangeable, so a corridor that drifts a
	stud between variants is a bug, not a variation.

	Idempotent: running it twice is a no-op the second time. Already-bucketed children are left
	where they are, so hand-sorting a tile afterwards survives the next run.
]]

local CollectionService = game:GetService("CollectionService")

local Segment = require(script.Segment)
local Types = require(script.Types)

local WORLDS_FOLDER = "Worlds"
-- The tile every other tile is measured against: the default map, live in Workspace.RoadSegments.
local REFERENCE_TAG = "RoadSegment"

local function findReference(): Model?
	for _, inst in CollectionService:GetTagged(REFERENCE_TAG) do
		if inst:IsA("Model") and inst:FindFirstChild("RoadSurface") then
			return inst
		end
	end
	return nil
end

local function tilesOf(folder: Instance): { Model }
	local tiles = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and tonumber(child.Name) then
			table.insert(tiles, child)
		end
	end
	table.sort(tiles, function(a, b)
		return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0)
	end)
	return tiles
end

-- One drive frame per world. Tiles are cloned into the same road, so they have to agree; the
-- median is used rather than the mean so one odd tile cannot drag the corridor off centre.
local function median(values: { number }): number?
	if #values == 0 then
		return nil
	end
	table.sort(values)
	return values[math.ceil(#values / 2)]
end

return {
	AutoRecordChanges = true,
	Description = "Give raw imported road tiles the streaming contract: OriginMarker pivot, attributes, backstop walls, and the default map's art buckets.",
	Tags = { "Road", "Worlds" },
	Arguments = {
		Scope = {
			Type = "dropdown",
			Default = "All worlds",
			Options = { "All worlds", "Selected world folder", "Selected tile" },
			LayoutOrder = 1,
			Description = "All worlds = every numbered tile under Workspace.Worlds. The other two work off the Explorer selection.",
		},
		DryRun = {
			Type = "boolean",
			Default = true,
			LayoutOrder = 2,
			Description = "Report what would change without touching anything. Turn off to apply.",
		},
	} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		local reference = findReference()
		if not reference then
			out:error("No reference tile found — expected a Model tagged 'RoadSegment' with a RoadSurface child (the default map).")
			return
		end
		local kit = Segment.harvestKit(reference)

		-- Gather the work as { worldName, tiles } so a whole world can be measured before any of
		-- it is changed.
		local jobs: { { name: string, tiles: { Model } } } = {}
		if arguments.Scope == "All worlds" then
			-- Parked in ServerStorage on 2026-10-13; Workspace still wins if dragged back.
			local worlds = workspace:FindFirstChild(WORLDS_FOLDER)
				or game:GetService("ServerStorage"):FindFirstChild(WORLDS_FOLDER)
			if not worlds then
				out:error(string.format("No %s folder in Workspace or ServerStorage.", WORLDS_FOLDER))
				return
			end
			for _, world in worlds:GetChildren() do
				if world:IsA("Folder") then
					local tiles = tilesOf(world)
					if #tiles > 0 then
						table.insert(jobs, { name = world.Name, tiles = tiles })
					end
				end
			end
		elseif arguments.Scope == "Selected world folder" then
			local folder = props.FirstSelected
			if not folder then
				out:error("Select a world folder (the one holding the numbered tiles).")
				return
			end
			table.insert(jobs, { name = folder.Name, tiles = tilesOf(folder) })
		else
			local tile = props.FirstSelected
			if not (tile and tile:IsA("Model")) then
				out:error("Select a tile (a Model).")
				return
			end
			table.insert(jobs, { name = tile.Parent and tile.Parent.Name or "?", tiles = { tile } })
		end

		local applied, skipped = 0, 0
		for _, job in jobs do
			-- Measure every tile first, then impose the world's consensus corridor on all of them.
			local plans = {}
			local widths, offsets = {}, {}
			for _, tile in job.tiles do
				local plan, why = Segment.plan(tile, kit)
				if plan then
					plans[tile] = plan
					if plan.frame.driveWidth then
						table.insert(widths, plan.frame.driveWidth)
						table.insert(offsets, plan.frame.driveCenterX - plan.frame.deckCentreX)
					end
				else
					out:warn(string.format("%s/%s skipped: %s", job.name, tile.Name, why))
					skipped += 1
				end
			end
			local width = median(widths)
			local offset = median(offsets)

			out:print(string.format("== %s (%d tile%s)", job.name, #job.tiles, #job.tiles == 1 and "" or "s"))
			for _, tile in job.tiles do
				local plan = plans[tile]
				if not plan then
					continue
				end
				-- Corridor width is a property of the world's road kit; the centre is per tile,
				-- but it should land the same distance off the deck centre in every one of them.
				local overrides = {}
				if width then
					overrides.driveWidth = width
				end
				if offset then
					overrides.driveCenterX = plan.frame.deckCentreX + offset
				end
				plan = Segment.plan(tile, kit, overrides)

				local parts = {}
				for bucket, count in plan.counts do
					table.insert(parts, string.format("%s %d", bucket, count))
				end
				table.sort(parts)
				out:print(string.format("   %-4s deck Y %.2f, corridor %.2f wide at X %.2f, entry Z %.1f | %s",
					tile.Name, plan.frame.deckTop, plan.frame.driveWidth or 0, plan.frame.driveCenterX,
					plan.frame.entryZ, #parts > 0 and table.concat(parts, ", ") or "already sorted"))
				for _, issue in plan.issues do
					out:warn(string.format("   %s/%s: %s", job.name, tile.Name, issue))
				end

				if not arguments.DryRun then
					Segment.apply(tile, plan, job.name, tonumber(tile.Name))
					applied += 1
				end
			end
		end

		if arguments.DryRun then
			out:print("Dry run — nothing changed. Turn DryRun off to apply.")
		else
			out:print(string.format("Normalised %d tile(s)%s.", applied, skipped > 0 and string.format(", skipped %d", skipped) or ""))
		end
	end,
} :: Types.ScriptModule
