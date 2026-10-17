--[[
	StubVehiclePromptGui, a Command Runner command

	Replaces every car's inline `Scripts.LocalVehiclePromptGui` with a stub that requires the shared
	module in git, the same extraction `Scripts.Vehicle` had in 2026-07-26. Run it once to apply the
	move, and again after importing a fresh CarBones rig, which always arrives with the kit's own
	inline copy.

	=== WHY THIS ONE HAD TO MOVE ==============================================================

	`LocalVehiclePromptGui` draws the pill that floats over a car and offers you a way in. The kit
	picks its icon off the seat the prompt is parented to, which is right when a car carries one
	prompt per door and wrong here: a lobby car carries exactly ONE prompt speaking for all four
	seats (`LobbyCarService._wireEntry` has the measurement that forced that), so the pill drew a
	steering wheel even on the press that seats you in the back. Fixing it means the car telling the
	pill which seat is on offer, and that is a change to this script.

	IT CANNOT BE A CHANGE TO ONE COPY OF IT. Every rig in the roster carries its own, 79 of them at
	the time of writing, and `Vehicle.setup`'s `playerAdded` deploys the FIRST one that sees a player
	and skips every other, so which copy is running is a race nobody controls. Editing one car is
	editing the game 1/79th of the time, which is the worst possible outcome: it works on the test
	that happens to hit it and not on the report.

	AND THE PLACE IS NOT THE RECORD. `Workspace.CarSystem` is not in git, so an edit made by hand in
	the Explorer lives only in whichever .rbxl the person who made it happened to save. That is the
	same reasoning `ApplyPaintRenames` opens with, and this is the same kind of change: reproducible
	from a module, re-runnable against any copy of the place, a no-op that says so on a place that
	already has it.

	=== THE PRISTINE COPY ======================================================================

	`CarBones_BACKUP` deliberately holds the unpatched stock `Scripts.Vehicle` as the reference for
	diffing against a fresh CarBones import. This command STILL STUBS ITS PROMPT GUI, on purpose. A
	`Vehicle` script is per car and a stock one there affects only that car; a `LocalVehiclePromptGui`
	is deployed once per PLAYER and draws for every car on the map, so a stock copy left in the
	backup is a coin flip on whether anybody in the session gets the icon fix. The stock source is
	preserved in git instead: `src/shared/Modules/VehiclePromptGui.luau` is a faithful copy of it
	with its deviations called out in the header, and the first commit of that file is the original.

	=== WHAT IT TOUCHES ========================================================================

	`Source` on `LocalScript`s named `LocalVehiclePromptGui`, and nothing else. It never touches the
	`CarValue` and `ButtonGuiPrototype` children, which the module reads and which are the whole
	reason the stub has to stay a script inside the car rather than becoming a `require` from
	somewhere else.

	A script missing either child is REFUSED rather than stubbed, and reported. That is a car the
	stub would deploy into a player's GUI to sit there erroring on `WaitForChild`, which is worse
	than a car still running the kit's copy.
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Types = require(script.Types)

local SCRIPT_NAME = "LocalVehiclePromptGui"
local MODULE_NAME = "VehiclePromptGui"

--- The children the module reads off its own script. A copy without both is not stubbable.
local REQUIRED_CHILDREN = { "CarValue", "ButtonGuiPrototype" }

--[[ Where cars live. Not `game` itself, which would walk CoreGui-adjacent services and the whole
	of `ReplicatedFirst` for nothing; these four hold every rig in the place, including the ones
	parked outside the roster (`Workspace.Civic`, the rough car slots under a plot, and the old
	backup in ServerStorage). ]]
local ROOTS = { workspace, ServerStorage, ReplicatedStorage, ServerScriptService }

--[[ The stub. Written as one string so the thing this command installs is readable in the diff
	rather than assembled out of pieces.

	`WaitForChild` down the whole path and not `ReplicatedStorage.shared.Modules.X`, which is what the
	`Vehicle` stub can afford because it is a server Script running in a DataModel that already holds
	everything. This one is a LocalScript that is cloned into a PlayerGui, so it starts on a client
	whose replication order is not ours to assume. ]]
local STUB = [[
-- Thin stub. The pill this car raises is drawn by a shared module in git:
--   src/shared/Modules/VehiclePromptGui.luau  ->  ReplicatedStorage.shared.Modules.VehiclePromptGui
--
-- Installed by the StubVehiclePromptGui Command Runner command. Re-run it after importing a fresh
-- CarBones rig, which arrives carrying the kit's own inline copy of this script.
--
-- ONLY ONE OF THESE IS EVER DEPLOYED PER PLAYER. `Vehicle.setup`'s `playerAdded` takes the first car
-- that sees a player and skips every other, and the copy it deploys draws for every car on the map.
-- So which car's copy is running is a race, every copy has to say the same thing, and a stub is how
-- they are kept saying it: edit the module and all of them change together.
--
-- CarValue and ButtonGuiPrototype stay as children of this script. The module reads both.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("shared")
local Modules = shared:WaitForChild("Modules")

require(Modules:WaitForChild("VehiclePromptGui")).setup(script)
]]

--- Already ours? Asked of the require rather than of the whole source, so a stub somebody has added
--- a comment to still reads as done.
local function isStub(source: string): boolean
	return string.find(source, MODULE_NAME, 1, true) ~= nil and string.find(source, "require(", 1, true) ~= nil
end

local function missingChild(promptScript: Instance): string?
	for _, name in REQUIRED_CHILDREN do
		if not promptScript:FindFirstChild(name) then
			return name
		end
	end
	return nil
end

--- Where a car is, said in a way that fits a report column. The rig is the script's great
--- grandparent (`<car>.Scripts.LocalVehiclePromptGui`), which is the name worth printing.
local function rigOf(promptScript: Instance): string
	local scripts = promptScript.Parent
	local car = scripts and scripts.Parent
	return if car then car:GetFullName() else promptScript:GetFullName()
end

return {
	Description = "Points every car's LocalVehiclePromptGui at the shared module in git, so the entry pill is one file instead of 79.",
	Tags = { "cars", "roster", "scripts", "prompt" },
	AutoRecordChanges = true,

	Arguments = {
		DryRun = {
			Type = "boolean",
			Default = false,
			Description = "Report what would change without writing anything.",
			LayoutOrder = 1,
		},
		Force = {
			Type = "boolean",
			Default = false,
			Description = "Rewrite copies that are already stubs (use after changing the stub itself).",
			LayoutOrder = 2,
		},
	} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()
		out:clear()

		local dry = arguments.DryRun == true
		local force = arguments.Force == true

		--[[ The module has to be there before the stubs point at it, or the next playtest deploys 79
			scripts that all yield forever on a `WaitForChild` that will never finish. Rojo owns that
			file, so a missing one means the sync is not running rather than that the file is not
			written. ]]
		local sharedFolder = ReplicatedStorage:FindFirstChild("shared")
		local modules = sharedFolder and sharedFolder:FindFirstChild("Modules")
		if not (modules and modules:FindFirstChild(MODULE_NAME)) then
			out:error(
				string.format(
					"ReplicatedStorage.shared.Modules.%s is not in this place. Check that Rojo is connected and has synced src/shared/Modules/%s.luau, then run this again.",
					MODULE_NAME,
					MODULE_NAME
				)
			)
			return
		end

		local found = {}
		local seen = {}
		for _, root in ROOTS do
			for _, descendant in root:GetDescendants() do
				if descendant:IsA("LocalScript") and descendant.Name == SCRIPT_NAME and not seen[descendant] then
					seen[descendant] = true
					table.insert(found, descendant)
				end
			end
		end

		if #found == 0 then
			out:warn(string.format("No %s scripts anywhere in Workspace, ServerStorage, ReplicatedStorage or ServerScriptService.", SCRIPT_NAME))
			return
		end

		table.sort(found, function(a, b)
			return rigOf(a) < rigOf(b)
		end)

		--[[ One undo waypoint for the whole pass, because the plugin's `AutoRecordChanges` only
			applies when the plugin is the one running the command. Run by hand out of an
			`execute_luau` it is not, and an edit that is not on the undo stack is one the next
			unrelated Ctrl+Z reverts instead of what it was aimed at. `TryBeginRecording` returns nil
			if a recording is already open, which is a reason to carry on unrecorded and say so, not
			to refuse. ]]
		local recording
		if not dry then
			recording = ChangeHistoryService:TryBeginRecording("StubVehiclePromptGui", "Stub every LocalVehiclePromptGui")
			if not recording then
				out:warn("Could not open an undo recording, another one is already open. Applying anyway, but this pass will not be undoable as one step.")
			end
		end

		local counts = {}
		local rows = {}
		local disabled = {}

		for _, promptScript in found do
			local rig = rigOf(promptScript)
			local state, note

			local absent = missingChild(promptScript)
			if absent then
				state = "refused"
				note = "no " .. absent .. " child, stubbing it would deploy a script that yields forever"
			elseif isStub(promptScript.Source) and not force then
				state = "already"
				note = "points at the module"
			else
				state = if dry then "would" else "stubbed"
				note = if force and isStub(promptScript.Source) then "rewritten by Force" else string.format("%d bytes of inline copy replaced", #promptScript.Source)
				if not dry then
					promptScript.Source = STUB
				end
			end

			if promptScript.Disabled then
				table.insert(disabled, rig)
			end

			counts[state] = (counts[state] or 0) + 1
			table.insert(rows, { rig = rig, state = state, note = note })
		end

		if recording then
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
		end

		--[[ Only the interesting rows, because a healthy roster is 79 identical lines saying
			"already" and burying the one that says "refused" in the middle of them. ]]
		local printed = 0
		for _, row in rows do
			if row.state ~= "already" then
				if printed == 0 then
					out:print(string.format("%-46s %-8s %s", "rig", "state", "note"))
				end
				printed += 1
				out:print(string.format("%-46s %-8s %s", row.rig, row.state, row.note))
			end
		end

		if counts.refused then
			out:warn(
				string.format(
					"%d copy/copies were refused. Those cars keep the kit's inline script and will draw the wrong icon if one of them wins the deploy race.",
					counts.refused
				)
			)
		end

		if #disabled > 0 then
			out:warn(string.format("Disabled scripts, which will never deploy: %s", table.concat(disabled, ", ")))
		end

		local summary = {}
		for state, n in counts do
			table.insert(summary, string.format("%d %s", n, state))
		end
		table.sort(summary)
		out:print("")
		out:print(
			string.format(
				"%d %s scripts. %s%s",
				#found,
				SCRIPT_NAME,
				table.concat(summary, ", "),
				if dry then ". Nothing was changed." else ". Save the place, the roster is not in git."
			)
		)
	end,
} :: Types.ScriptModule
