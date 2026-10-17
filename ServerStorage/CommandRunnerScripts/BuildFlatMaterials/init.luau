--[[
	BuildFlatMaterials, a Command Runner command

	Builds the flat twins `RoadService` points the race road at when `RoadStudsConfig.RoadStuds` is
	off. For every name in `RoadStudsConfig.Variants` it clones the textured MaterialVariant in
	`MaterialService`, clears every texture map on the clone and parents it back into
	`MaterialService` as `<name><FlatSuffix>` ("2022 Universal Flat").

	A clone rather than a fresh MaterialVariant so the twin keeps the original's BaseMaterial,
	StudsPerTile, pattern and physical properties. BaseMaterial has to match the part's Material or
	the twin binds nothing, and different physics would change how the race road grips.

	The twin sits in MaterialService with nothing referencing it until the server re-points the
	road at it, so building it changes nothing on its own, including in Studio's edit view.

	WHY THIS IS A COMMAND: the maps are PluginSecurity, so only Studio can clear them, and the result
	lives in the place, not in git. Re-runnable: it replaces a twin that is already there, so run it
	again after adding a name to the config or after a map import brings in a new copy of a variant.
	The textured originals are only read, never touched.
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(script.Types)

--- Every texture slot a MaterialVariant has. The Content twins are cleared alongside the ContentId ones.
local MAP_PROPERTIES = { "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap" }
local CONTENT_PROPERTIES = { "ColorMapContent", "NormalMapContent", "RoughnessMapContent", "MetalnessMapContent", "EmissiveMaskContent" }

--[[ The config is read fresh each run. A plain `require` in edit mode hands back whatever was cached
	the first time any plugin required it, so an edited `Variants` list would be ignored until
	Studio restarted. ]]
local function loadConfig()
	local module = ReplicatedStorage:FindFirstChild("shared")
	module = module and module:FindFirstChild("Configs")
	module = module and module:FindFirstChild("RoadStudsConfig")
	if not (module and module:IsA("ModuleScript")) then
		return nil
	end
	local copy = module:Clone()
	local ok, config = pcall(require, copy)
	copy:Destroy()
	return if ok then config else nil
end

local function hasMaps(variant: MaterialVariant): boolean
	for _, property in MAP_PROPERTIES do
		if (variant :: any)[property] ~= "" then
			return true
		end
	end
	return false
end

return {
	Description = "Builds flat (untextured) twins of the race road's MaterialVariants into MaterialService for RoadStudsConfig.",
	Tags = { "road", "materials", "studs" },
	AutoRecordChanges = true,

	Arguments = {} :: Types.ArgumentType,

	Run = function(props: Types.Props, _arguments: Types.ArgumentResult)
		local out = props:Output()
		out:clear()

		local config = loadConfig()
		if not config then
			out:error("ReplicatedStorage.shared.Configs.RoadStudsConfig is missing or does not load. Check that Rojo has synced it.")
			return
		end

		local recording = ChangeHistoryService:TryBeginRecording("BuildFlatMaterials", "Build flat MaterialVariant twins")
		if not recording then
			out:warn("Could not open an undo recording, another one is already open. Building anyway.")
		end

		local built, skipped = 0, 0
		for _, name in config.Variants do
			local flatName = name .. config.FlatSuffix
			local source = MaterialService:FindFirstChild(name)
			if not (source and source:IsA("MaterialVariant")) then
				skipped += 1
				out:warn(string.format("%-24s skipped, no MaterialVariant named %q in MaterialService", flatName, name))
				continue
			end

			local old = MaterialService:FindFirstChild(flatName)
			if old then
				old:Destroy()
			end

			local twin = source:Clone()
			twin.Name = flatName
			for _, property in MAP_PROPERTIES do
				(twin :: any)[property] = ""
			end
			for _, property in CONTENT_PROPERTIES do
				pcall(function()
					(twin :: any)[property] = Content.none
				end)
			end
			twin.Parent = MaterialService

			if hasMaps(twin) then
				out:warn(string.format("%-24s built but still carries a map; check it by hand", flatName))
			else
				out:print(string.format("%-24s built (base %s, %s studs per tile)", flatName, twin.BaseMaterial.Name, tostring(twin.StudsPerTile)))
			end
			built += 1
		end

		if recording then
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
		end

		out:print(string.format("%d built, %d skipped", built, skipped))
	end,
} :: Types.ScriptModule
