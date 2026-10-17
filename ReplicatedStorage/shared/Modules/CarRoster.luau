--[[
	CarRoster  (shared, but server in practice)
	-------------------------------------------
	Where the pristine car rigs live, asked rather than assumed.

	`CarSystem` is 21,525 instances of authored CarBones rigs, which is 16% of the place's Workspace,
	and no client has ever been able to use it: `StreamingEnabled` streams it out partway into a race
	(see the memory note that `CarViewport` and `RaceUIController` both cite), so everything
	client-side that wants to show a car goes through `ReplicatedStorage.TrafficCars` instead. It was
	still sitting in Workspace, though, which means every joining client downloaded ~6,800 of those
	instances before its loading screen would lift, for art it cannot read and never draws.

	So the folder is tagged `RelocateObject` with `Location = ServerStorage` and
	`RelocationService` moves it out as the server boots. This module is the "teaching those two
	where to look" that service's header says the move needs.

	=== IT LOOKS IN BOTH PLACES, AND THAT IS NOT THE PATTERN RELOCATIONSERVICE WARNS ABOUT =======

	That header's one rule is: only tag things nothing reads, because a consumer coping with "it
	might have moved, it might not" is the lazy re-resolution Meteor ended up carrying. The
	difference here is WHEN: relocation is synchronous in `init`, and every caller below resolves at
	`start` or later, on a race entry or a display build. So this is never asked before the answer is
	settled, and the Workspace branch is not a race with the move.

	It exists for two honest cases instead. An edit session that has never booted the game still has
	the rigs in Workspace, which is what an audit command run from the Command Runner sees; and a
	place whose folder was untagged by hand keeps working rather than losing every car in the game.
	ServerStorage is asked FIRST so that the relocated copy always wins, and there is only ever one.

	=== AND IT IS SERVER-ONLY, BY TEST RATHER THAN BY CONVENTION ================================

	`game:GetService("ServerStorage")` throws on a client, so the lookup is fenced behind
	`RunService:IsServer()`. Every caller is server-side today (`RaceService`, `TrafficService`,
	`LobbyCarService`, and `CarDisplay.build`, which only ever runs from a service), but `CarDisplay`
	is a shared module and a client that required it would otherwise take the error rather than the
	nil this hands back.
]]

local RunService = game:GetService("RunService")

local CarRoster = {}

--- The folder's authored name. `GarageConfig.Display.RosterFolderName` is the same string for the
--- display side; callers holding a config value pass it rather than relying on this.
CarRoster.Name = "CarSystem"

--- The roster folder, wherever it currently is, or nil in a place that has none.
function CarRoster.folder(name: string?): Instance?
	local wanted = name or CarRoster.Name
	--[[ `IsEdit` as well: the folder was parked in ServerStorage IN THE PLACE on 2026-10-13, so an
		edit-mode audit (where `IsServer` is false) has to look there too. ServerStorage is readable
		from a Studio edit session; it is only a live client that throws. ]]
	if RunService:IsServer() or RunService:IsEdit() then
		local stored = game:GetService("ServerStorage"):FindFirstChild(wanted)
		if stored then
			return stored
		end
	end
	return workspace:FindFirstChild(wanted)
end

--- One rig by body name, or nil. The Model test is the caller's usual next line, done here once.
function CarRoster.car(body: string, name: string?): Model?
	local folder = CarRoster.folder(name)
	local model = folder and folder:FindFirstChild(body)
	return if model and model:IsA("Model") then model :: Model else nil
end

--- Where the roster was found, for a log line that has to name it. Falls back to the plain name so
--- a warning about a missing car still reads correctly in a place that has no roster at all.
function CarRoster.path(name: string?): string
	local folder = CarRoster.folder(name)
	return if folder then folder:GetFullName() else (name or CarRoster.Name)
end

return CarRoster
