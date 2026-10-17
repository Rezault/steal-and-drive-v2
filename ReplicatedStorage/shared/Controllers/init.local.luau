local ReplicatedStorage = game:GetService("ReplicatedStorage")
--- One broken controller must not stop the rest (`Modules/BootGuard` has the whole of why).
local BootGuard = require(ReplicatedStorage.shared.Modules.BootGuard)

--[[ Wait for the server, but NOT FOREVER (2026-10-14). This was an unbounded loop, so a server whose
	services never finished starting left every client here for good: the join screen's hard timeout,
	then black. After `SERVER_WAIT` seconds the client says so on the join screen and starts anyway. ]]
local SERVER_WAIT = 60
local waitedUntil = os.clock() + SERVER_WAIT
repeat
	task.wait()
until workspace:GetAttribute("ShardServerStarted") == true or os.clock() >= waitedUntil
if workspace:GetAttribute("ShardServerStarted") ~= true then
	warn("[Boot] The server never reported its services started; starting the client anyway.")
	BootGuard.report("server never started")
elseif workspace:GetAttribute("ShardServerFailed") then
	BootGuard.report("server: " .. tostring(workspace:GetAttribute("ShardServerFailed")))
end

local ReplicaClient = require(ReplicatedStorage.Packages.ReplicaClient)
local Promise = require(ReplicatedStorage.Packages.Promise)
local Shard = require(ReplicatedStorage.Packages.Shard)

for _, controller in script:GetChildren() do
	if controller:IsA("ModuleScript") then
		--- A module that throws while loading is named and skipped, not the end of the loop.
		local ok, module = pcall(require, controller)
		if ok then
			BootGuard.wrap(module, controller.Name)
		else
			warn(string.format("[Boot] %s failed to load; it is off for this session.\n%s", controller.Name, tostring(module)))
		end
	end
end

local start = workspace:GetServerTimeNow()

Promise.new(function(resolve)
	Shard.init()
	resolve()
end)
	:andThen(function()
		Shard.start()
	end)
	:andThen(function()
		print("[SHARD]", workspace:GetServerTimeNow() - start, "ms to init and start controllers")
		-- print("All controllers initialized and started successfully.")
		workspace:SetAttribute("ShardClientStarted", true)
		ReplicaClient.RequestData()
	end)
	:catch(function(err)
		warn("Error starting services:", err)
		--- The join screen says so instead of fading to black (`JoinScreen.local.luau`).
		BootGuard.report("client: " .. tostring(err))
	end)
