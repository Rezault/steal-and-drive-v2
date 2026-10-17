--[[
	CodesController  (client)
	-------------------------
	The client end of codes (`CodesConfig`): sends what was typed in the shop's code box
	(`PagesV2/Shop`, which is a page and not a Shard controller, so it cannot hold a remote itself),
	and publishes the server's answer on `Dispatcher` as `CodesConfig.Remotes.Result` with
	`{ ok, message }` for the box to show.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local CodesConfig = require(ReplicatedStorage.shared.Configs.CodesConfig)

local CodesController = Shard.new("CodesController")

CodesController:withRemoteEvents({
	CodesConfig.Remotes.Redeem,
	{
		[CodesConfig.Remotes.Result] = function(ok: unknown, message: unknown)
			Dispatcher:Publish(CodesConfig.Remotes.Result, { ok = ok == true, message = tostring(message) })
		end,
	},
})

--- PUBLIC (`PagesV2/Shop`): try a code. The answer arrives on `Dispatcher` (header).
function CodesController.redeem(self, text: string)
	self:getRemoteEvent(CodesConfig.Remotes.Redeem):Fire(text)
end

return CodesController
