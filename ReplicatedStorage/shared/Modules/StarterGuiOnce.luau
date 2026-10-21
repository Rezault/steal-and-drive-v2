--[[
	StarterGuiOnce  (server and client)
	-----------------------------------
	SENDS THE AUTHORED SCREENGUIS TO A CLIENT ONCE, NOT TWICE (2026-10-20).

	StarterGui replicates. Every gui in it reached a client two times per join: once as part of
	StarterGui itself, before `game.Loaded`, and again as the server's PlayerGui copy when the
	character first loaded. For `MainUIV2` that was 4,243 instances sent twice, and the server kept a
	third copy per player in its PlayerGui for the whole session, which nothing on the server reads.

	So at boot the server MOVES every such gui out of StarterGui into `ReplicatedStorage.<FolderName>`
	(`relocate`, from `StarterGuiService.init`), which replicates once, and each client clones them
	into its own PlayerGui when its character first appears (`copyInto`, from the client bootstrap):
	the moment the engine's copy used to land, so nothing waiting on a gui sees it sooner or later
	than it did. The place file is untouched. The guis are authored and built (every Command Runner
	builder) in StarterGui exactly as before, and a playtest's move reverts when it stops.

	ONLY `ResetOnSpawn = false` GUIS MOVE. The engine destroys and re-copies a ResetOnSpawn gui on
	every respawn, and that is not behaviour worth re-implementing here. Every gui in the place is
	false today; one authored true later simply stays in StarterGui and ships the old way.

	ANYTHING THAT LOOKS IN StarterGui AT RUNTIME should ask `find` instead. In edit mode nothing has
	moved and `find` answers from StarterGui.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local StarterGuiOnce = {}

StarterGuiOnce.FolderName = "StarterGuiOnce"

local function movable(instance: Instance): boolean
	return instance:IsA("LayerCollector") and not instance.ResetOnSpawn
end

--- Server, at boot: move every movable gui out of StarterGui. Returns how many moved.
function StarterGuiOnce.relocate(): number
	local folder = ReplicatedStorage:FindFirstChild(StarterGuiOnce.FolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = StarterGuiOnce.FolderName
		folder.Parent = ReplicatedStorage
	end
	local moved = 0
	for _, child in StarterGui:GetChildren() do
		if movable(child) then
			child.Parent = folder
			moved += 1
		end
	end
	return moved
end

--- Where an authored gui is now: StarterGui in edit mode (or for one that did not move), the folder
--- once the server has moved it. Nil if it is in neither.
function StarterGuiOnce.find(name: string): Instance?
	local here = StarterGui:FindFirstChild(name)
	if here then
		return here
	end
	local folder = ReplicatedStorage:FindFirstChild(StarterGuiOnce.FolderName)
	return if folder then folder:FindFirstChild(name) else nil
end

--[[ Client: clone the moved guis into PlayerGui when the character first appears. Once a session,
	because every one of them is `ResetOnSpawn = false`.

	A gui ALREADY in PlayerGui is skipped. That is the engine's own copy, in a session whose character
	loaded before the server had moved anything (Studio's player can join before the services start),
	and two of one ScreenGui is the outcome to rule out.

	Waits for `game.Loaded` first. The folder replicates as part of ReplicatedStorage, so if it is not
	here by then this server moved nothing and the engine is copying the old way. ]]
function StarterGuiOnce.copyInto(player: Player)
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	local folder = ReplicatedStorage:FindFirstChild(StarterGuiOnce.FolderName)
	if not folder then
		return
	end
	local playerGui = player:WaitForChild("PlayerGui")
	if not player.Character then
		player.CharacterAdded:Wait()
	end
	for _, gui in folder:GetChildren() do
		if not playerGui:FindFirstChild(gui.Name) then
			gui:Clone().Parent = playerGui
		end
	end
end

return StarterGuiOnce
