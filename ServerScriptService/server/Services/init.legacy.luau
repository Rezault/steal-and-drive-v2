local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data = require(script.Parent.Data)
local Promise = require(ReplicatedStorage.Packages.Promise)
local Shard = require(ReplicatedStorage.Packages.Shard)
--- One broken service must not stop the rest (`Modules/BootGuard` has the whole of why).
local BootGuard = require(ReplicatedStorage.shared.Modules.BootGuard)

for _, service in script:GetChildren() do
	if service:IsA("ModuleScript") then
		--- A module that throws while loading is named and skipped, not the end of the loop.
		local ok, module = pcall(require, service)
		if ok then
			BootGuard.wrap(module, service.Name)
		else
			warn(string.format("[Boot] %s failed to load; it is off for this session.\n%s", service.Name, tostring(module)))
		end
	end
end
local start = workspace:GetServerTimeNow()

Promise.new(function(resolve)
	Data:initialize()
	Shard.init()
	resolve()
end)
	:andThen(function()
		Shard.start()
	end)
	:andThen(function()
		print("[SHARD]", workspace:GetServerTimeNow() - start, "ms to init and start services")
		-- print("All services initialized and started successfully.")
		workspace:SetAttribute("ShardServerStarted", true)
	end)
	:catch(function(err)
		warn("Error starting services:", err)
		--[[ STILL SAY STARTED (2026-10-14). Every client waits on this flag before it loads anything,
			so a server that never set it handed every player a two-minute join screen and then a black
			one. With each service guarded this is only reachable through `Data`, and a client told why
			can at least say so on screen (`ShardServerFailed`, read by the client bootstrap). ]]
		workspace:SetAttribute("ShardServerFailed", tostring(err))
		workspace:SetAttribute("ShardServerStarted", true)
	end)
