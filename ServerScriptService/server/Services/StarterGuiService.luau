--[[
	StarterGuiService  (server)
	---------------------------
	Moves the authored guis out of StarterGui at boot so each client is sent them once instead of
	twice. The whole of the why is in `Modules/StarterGuiOnce`; this is only where the server half
	runs.

	`init`, not `start`, for the reason `RelocationService` gives for its sweep: every service's
	`init` is finished before any service starts, and long before a player's character loads, which
	is the moment the engine would otherwise copy StarterGui into their PlayerGui.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local StarterGuiOnce = require(ReplicatedStorage.shared.Modules.StarterGuiOnce)

local StarterGuiService = Shard.new("StarterGuiService")

StarterGuiService:withLifecycle({
	init = function(self)
		local moved = StarterGuiOnce.relocate()
		self.log:info(string.format(
			"Moved %d gui(s) from StarterGui to ReplicatedStorage.%s; clients copy them in themselves.",
			moved,
			StarterGuiOnce.FolderName
		))
	end,
})

return StarterGuiService
