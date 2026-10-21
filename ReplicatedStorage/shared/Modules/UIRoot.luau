--[[
	UIRoot  (client)
	----------------
	WHICH ScreenGui IS THE MENU UI. One question, asked in one place, answered once per session.

	The Cartoony Kit migration authors a second UI beside the first (`MainUI` and `MainUIV2`, both in
	`StarterGui`, both `ResetOnSpawn = false`) and picks between them with `NewUIConfig.Enabled`. Some
	sixteen files look the UI up by name today. Every one of them asks here instead, so there is no
	file left that can be right about one answer and wrong about the other.

	WITH THE FLAG OFF THIS RETURNS `MainUI` AND NOTHING ELSE HAPPENS, which is the whole point of the
	switch: the old path has to be byte-for-byte the old path until the new one is finished.

	=== THE UNUSED ONE IS DESTROYED, NOT DISABLED =============================================

	The first lookup claims the UI: it enables the one in use and destroys the other. Three reasons,
	and the first is the one that matters.

	  • NOTHING CAN BIND HALF OF EACH. A disabled ScreenGui is still a tree full of buttons, and a
	    tag observer, a `FindFirstChild(name, true)` or a stray `WaitForChild` binds it as happily as
	    the live one. Destroying is the only version of "not in use" that a later file cannot get
	    wrong.
	  • `Enabled` IN THE PLACE STOPS MATTERING, so both can be toggled freely while editing without
	    changing what a player sees.
	  • The unused tree is thousands of instances the client keeps for nothing.

	A late arrival is covered: if the other UI has not replicated yet when the claim runs, a short
	watch destroys it when it turns up. Anything that resolved `MainUI` by hand before the claim, with
	the flag on, is holding a destroyed instance. That is the bug this module exists to make
	impossible, so the way to fix one is to route that file through here rather than to re-order boot.

	=== THE OVERRIDE ==========================================================================

	`NewUIConfig.OverrideAttribute` on the Player forces one answer for one tester (see that file).
	Read once, at the first lookup, because a UI that changes its mind between two lookups is a UI
	built half from each.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NewUIConfig = require(ReplicatedStorage.shared.Configs.NewUIConfig)
--- Where an authored ScreenGui is at runtime: the server moves them out of StarterGui at boot.
local StarterGuiOnce = require(ReplicatedStorage.shared.Modules.StarterGuiOnce)

--- How long the claim waits for the OTHER UI before deciding it is not in this place. Generous,
--- because nothing is blocked on it: this runs in its own thread and only ever destroys.
local OTHER_WAIT = 20

local UIRoot = {}

local resolved: boolean? = nil
local claimedIn: PlayerGui? = nil

--[[ Is the new UI the one in use? Cached from the first call. ]]
function UIRoot.isNewUI(): boolean
	if resolved == nil then
		local enabled = NewUIConfig.Enabled == true

		--- Nil on the server, where nothing should be asking this anyway; the config's own value is
		--- then the answer and no attribute can move it.
		local player = Players.LocalPlayer
		if player then
			local override = player:GetAttribute(NewUIConfig.OverrideAttribute)
			if type(override) == "boolean" then
				enabled = override
			end
		end

		--[[ THE OLD UI IS NOT IN STARTERGUI ANY MORE (2026-10-20). It is parked at
			`ServerStorage.UIImports.MainUI`, because StarterGui replicates: every join was sending it
			twice (StarterGui itself, then the PlayerGui copy) only for the claim below to destroy it.
			An answer of "old" with no old UI to give would leave every lookup waiting on a ScreenGui
			that never comes, so it falls back to the new one. Drag it back to use the old UI again. ]]
		if not enabled and not StarterGuiOnce.find(NewUIConfig.LegacyScreenGuiName) then
			warn("[UIRoot] The old UI is not in StarterGui (it is parked in ServerStorage.UIImports); using the new one.")
			enabled = true
		end

		resolved = enabled
	end
	return resolved :: boolean
end

--- The name of the ScreenGui in use, and of the one that is not.
function UIRoot.name(): string
	return if UIRoot.isNewUI() then NewUIConfig.ScreenGuiName else NewUIConfig.LegacyScreenGuiName
end

function UIRoot.otherName(): string
	return if UIRoot.isNewUI() then NewUIConfig.LegacyScreenGuiName else NewUIConfig.ScreenGuiName
end

--- The folder of page modules that goes with the answer. `UIController` is the only caller.
function UIRoot.pagesFolderName(): string
	return if UIRoot.isNewUI() then NewUIConfig.PagesFolderName else NewUIConfig.LegacyPagesFolderName
end

--[[ Enable ours, destroy theirs. Once per PlayerGui, and safe to call from anywhere: the first
	lookup of the session runs it and every lookup after it is a no-op. ]]
local function claim(playerGui: PlayerGui, ours: ScreenGui?)
	if claimedIn == playerGui then
		return
	end
	claimedIn = playerGui

	if ours then
		ours.Enabled = true
	end

	local otherName = UIRoot.otherName()
	local other = playerGui:FindFirstChild(otherName)
	if other then
		other:Destroy()
		return
	end

	--[[ Not here yet. Both are StarterGui clones and arrive in one batch, so this is the rare case
		rather than the normal one, but a UI that replicated a frame late would otherwise sit there
		live underneath the one in use. ]]
	task.spawn(function()
		local late = playerGui:WaitForChild(otherName, OTHER_WAIT)
		if late and claimedIn == playerGui then
			late:Destroy()
		end
	end)
end

--[[ The UI, waited for. `timeout` is optional and behaves like `WaitForChild`'s: nil waits forever.
	Callers that can carry on without a UI should pass one, the way `GamepadNav` and
	`GarageHudController` do, so a place missing the art warns instead of hanging. ]]
function UIRoot.wait(playerGui: PlayerGui, timeout: number?): ScreenGui?
	local screenGui = if timeout
		then playerGui:WaitForChild(UIRoot.name(), timeout)
		else playerGui:WaitForChild(UIRoot.name())
	claim(playerGui, screenGui :: ScreenGui?)
	return screenGui :: ScreenGui?
end

--- The UI if it is already there, without waiting. Nil is an ordinary answer.
function UIRoot.find(playerGui: PlayerGui): ScreenGui?
	local screenGui = playerGui:FindFirstChild(UIRoot.name())
	if screenGui then
		claim(playerGui, screenGui :: ScreenGui)
	end
	return screenGui :: ScreenGui?
end

return UIRoot
