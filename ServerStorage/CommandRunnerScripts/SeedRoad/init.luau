--[[
	SeedRoad — Command Runner command

	Duplicates the selected RoadSegment along its forward axis to pre-seed the
	infinite-driving road so it can be tested before the streaming / recycling
	code has generated anything.

	- Forward-only (default): all Count clones are placed ahead of the selection.
	- Centered: the selected segment is treated as the MIDDLE and Count clones
	  are placed on each side (ahead and behind).

	Reads the RoadSegment streaming contract (attributes on the model):
		SegmentLength — length of the drivable deck along the drive axis (tile offset)
		ForwardAxis   — "X" | "Y" | "Z" driving direction (default "Z")

	Clones inherit CollectionService tags and attributes, so the streaming
	code still recognises the seeded tiles. See the RoadSegment docs/memory
	for the full contract.
]]

local Types = require(script.Types)

return {
	AutoRecordChanges = true,
	Description = "Duplicate the selected RoadSegment along the drive axis to pre-seed the infinite-driving road. Optionally centers so the selected tile is the middle.",
	Tags = { "Road", "Testing" },
	Arguments = {
		Count = {
			Type = "number",
			Default = 10,
			Min = 1,
			Step = 1,
			LayoutOrder = 1,
			Description = "How many duplicate segments to create (per direction when 'Centered' is on; otherwise all forward).",
		},
		Centered = {
			Type = "boolean",
			Default = false,
			LayoutOrder = 2,
			Description = "Treat the selected segment as the middle and seed clones in BOTH directions (Count on each side).",
		},
		GroupInFolder = {
			Type = "boolean",
			Default = false,
			LayoutOrder = 3,
			Description = "Parent the source + clones into a Folder named 'RoadSegments' (created next to the source if missing).",
		},
		ClearOtherSegments = {
			Type = "button",
			Default = "Remove all except selected",
			LayoutOrder = 4,
			Description = "Delete every tagged RoadSegment except the one currently selected — lets you edit that tile, then re-seed. Undoable.",
			Run = function(props: Types.Props, _value: any)
				local out = props:Output()

				local keep = props.FirstSelected
				if not keep or not keep:IsA("Model") then
					out:error("Select the RoadSegment you want to KEEP first.")
					return
				end

				local CollectionService = game:GetService("CollectionService")
				local ChangeHistoryService = game:GetService("ChangeHistoryService")

				-- Set Parent = nil inside a recording (Studio's own undoable-delete
				-- pattern) rather than :Destroy(), so a single undo brings them back.
				local recording = ChangeHistoryService:TryBeginRecording("SeedRoad: keep only selected segment")
				local removed = 0
				for _, seg in ipairs(CollectionService:GetTagged("RoadSegment")) do
					if seg ~= keep and seg:IsDescendantOf(workspace) then
						seg.Parent = nil
						removed += 1
					end
				end
				if recording then
					ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
				end

				props:SetSelection({ keep })
				out:print(string.format("Removed %d other segment(s); kept '%s'. Edit it, then re-seed.", removed, keep.Name))
			end,
		},
	} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		local source = props.FirstSelected
		if not source or not source:IsA("Model") then
			out:error("Select a RoadSegment (Model) first — it's the tile that gets duplicated.")
			return
		end

		local count = math.max(1, math.floor(tonumber(arguments.Count) or 10))
		local centered = arguments.Centered == true

		-- Resolve the forward tiling offset from the streaming contract.
		local forwardAxis = tostring(source:GetAttribute("ForwardAxis") or "Z"):upper()
		local segmentLength = source:GetAttribute("SegmentLength")
		if type(segmentLength) ~= "number" then
			local _, size = source:GetBoundingBox()
			segmentLength = (forwardAxis == "X" and size.X)
				or (forwardAxis == "Y" and size.Y)
				or size.Z
			out:warn(string.format(
				"No SegmentLength attribute found; falling back to bounding-box length %.2f along %s.",
				segmentLength, forwardAxis
			))
		end

		local axis
		if forwardAxis == "X" then
			axis = Vector3.xAxis
		elseif forwardAxis == "Y" then
			axis = Vector3.yAxis
		else
			axis = Vector3.zAxis
		end
		local forwardOffset = CFrame.new(axis * segmentLength)
		local backOffset = CFrame.new(axis * -segmentLength)

		-- Optionally corral everything into a folder for tidy pre-seeding.
		-- Reuse an existing "RoadSegments" folder (including the one the source
		-- is already inside) so repeated grouped seeds never nest folder-in-folder.
		local parent = source.Parent
		if arguments.GroupInFolder then
			local FOLDER_NAME = "RoadSegments"
			local folder
			if parent and parent:IsA("Folder") and parent.Name == FOLDER_NAME then
				-- Source is already grouped; reuse its folder instead of nesting.
				folder = parent
			else
				folder = parent and parent:FindFirstChild(FOLDER_NAME)
				if not (folder and folder:IsA("Folder")) then
					folder = Instance.new("Folder")
					folder.Name = FOLDER_NAME
					folder.Parent = parent
				end
			end
			source.Parent = folder
			parent = folder
		end

		local created = {}

		-- Chain each clone off the previous segment's pivot so seams line up
		-- even when the source is rotated (matches the recycle formula:
		-- clone:PivotTo(prev:GetPivot() * CFrame.new(0, 0, SegmentLength))).
		local function seed(offset: CFrame)
			local prev = source
			for _ = 1, count do
				local clone = source:Clone()
				clone:PivotTo(prev:GetPivot() * offset)
				clone.Parent = parent
				prev = clone
				table.insert(created, clone)
			end
		end

		seed(forwardOffset)
		if centered then
			seed(backOffset)
		end

		-- Cosmetic niceties; never let them abort the seed.
		pcall(function()
			props:SetSelection(created)
			props:FocusView(created)
		end)

		local total = #created + 1 -- clones + the original
		out:print(string.format(
			"Seeded %d segment(s)%s @ %.2f studs along %s. Road now spans ~%.0f studs across %d tiles.",
			#created,
			centered and string.format(" (%d each side of the middle)", count) or " forward",
			segmentLength, forwardAxis, total * segmentLength, total
		))
	end,
} :: Types.ScriptModule
