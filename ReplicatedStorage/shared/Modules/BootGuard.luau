--[[
	BootGuard  (shared — both bootstraps and the join screen)
	---------------------------------------------------------
	ONE BROKEN SYSTEM MUST NOT TAKE THE WHOLE GAME DOWN WITH IT (2026-10-14).

	The Shard framework calls every service's and every controller's `init` and then `start` in one
	plain loop (`Packages/_Index/luminalabsgames_shard/shard/init.luau`, `Module.init` / `Module.start`),
	with no `pcall` round any of them. So ONE that throws ends the loop: on the server
	`ShardServerStarted` is never set, every client waits on it forever, and every player on that server
	gets the join screen's two-minute hard timeout and then a black screen (a tester on an iPhone, the
	same day). One that YIELDS forever does the same thing more quietly.

	THE FIX IS HERE AND NOT IN THE PACKAGE. The vendored package is overwritten by the next package
	install, so an edit there would silently come undone. Instead the bootstraps hand every required
	module to `wrap`, which replaces its `init` / `start` with a guarded copy before Shard ever calls
	them:
	  * an ERROR is caught, printed with the module's name and a traceback, and recorded (`failed`);
	    the loop carries on, so a broken system costs that system and nothing else;
	  * a STALL cannot be cut short from here (the loop is waiting on it), but it is NAMED: a warning
	    after `STALL_WARN` seconds says which module the whole boot is stuck behind.

	And `report` / `failure` carry "the boot went wrong" to the join screen through a `ReplicatedFirst`
	attribute, so a dead client says so on screen instead of fading to black.
]]

local ReplicatedFirst = game:GetService("ReplicatedFirst")

local BootGuard = {}

--- Seconds a single init/start may run before it is named in the log as what the boot is waiting on.
--- Well past any honest start (the slowest measured are a couple of seconds of `WaitForChild`).
local STALL_WARN = 10
--- The `ReplicatedFirst` attribute the join screen reads (`JoinScreen.local.luau` spells it too, as
--- that script runs before any module can be required; keep the two in step).
BootGuard.FailedAttribute = "BootFailed"

--- Every module that threw on the way up, "Name.phase".
BootGuard.failed = {} :: { string }
--- Wall-clock seconds each guarded phase took, "Name.phase" -> seconds, yields included (a
--- `WaitForChild` counts). The client bootstrap adds "Name.require". Where a slow boot went.
BootGuard.timings = {} :: { [string]: number }

local function run(name: string, phase: string, fn: (any) -> (), self: any)
	local done = false
	task.delay(STALL_WARN, function()
		if not done then
			warn(string.format("[Boot] %s.%s has been running for %ds; the rest of the boot is waiting on it.", name, phase, STALL_WARN))
		end
	end)
	local began = os.clock()
	local ok, err = xpcall(fn, debug.traceback, self)
	BootGuard.timings[name .. "." .. phase] = os.clock() - began
	done = true
	if not ok then
		table.insert(BootGuard.failed, name .. "." .. phase)
		warn(string.format("[Boot] %s failed to %s; it is off for this session and everything else carries on.\n%s", name, phase, tostring(err)))
	end
end

--[[ Guard one required module's `init` and `start`, whichever way it declared them (the
	`withLifecycle` table Shard reads first, or plain `init` / `start` methods). A module that is not
	a Shard module (no `_lifecycle`) is left alone. ]]
function BootGuard.wrap(module: any, name: string)
	if type(module) ~= "table" or type(rawget(module, "_lifecycle")) ~= "table" then
		return
	end
	local lifecycle = module._lifecycle
	for _, phase in { "init", "start" } do
		local fn = lifecycle[phase]
		if type(fn) == "function" then
			lifecycle[phase] = function(self)
				run(name, phase, fn, self)
			end
		elseif type(rawget(module, phase)) == "function" then
			local method = rawget(module, phase)
			module[phase] = function(self)
				run(name, phase, method, self)
			end
		end
	end
end

--- Tell the join screen the boot went wrong (`why`, for the log line it prints). Client only in
--- practice; harmless on the server.
function BootGuard.report(why: string)
	ReplicatedFirst:SetAttribute(BootGuard.FailedAttribute, why)
end

--[[ The slowest entry in `timings` ("OfflineController.start") and its seconds, as two `ReplicatedFirst`
	attributes for the join funnel: `JoinScreen` sends them with its `started` report and the server
	puts them on `JoinFinished`, which is how a slow boot on a real phone gets a name. Called by the
	client bootstrap BEFORE it sets `ShardClientStarted`, so they are there when the screen looks.
	`JoinScreen` spells both names too; keep them in step. ]]
BootGuard.SlowestAttribute = "BootSlowest"
BootGuard.SlowestSecondsAttribute = "BootSlowestSeconds"
function BootGuard.publishSlowest()
	local slowest, seconds = nil, 0
	for key, took in BootGuard.timings do
		if took > seconds then
			slowest, seconds = key, took
		end
	end
	if slowest then
		ReplicatedFirst:SetAttribute(BootGuard.SlowestAttribute, slowest)
		ReplicatedFirst:SetAttribute(BootGuard.SlowestSecondsAttribute, seconds)
	end
end

return BootGuard
