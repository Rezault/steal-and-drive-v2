-- Test harness for PlaytimeRewardService: the REAL service and config under stubs (a fake clock,
-- a fake day, a fake profile, and a DailyRewardService that prices and records payouts).
-- SOURCES is prepended by tests/playtime/run.sh.

local failures, passes = 0, 0
local function check(cond, msg)
	if cond then
		passes += 1
	else
		failures += 1
		print("FAIL: " .. msg)
	end
end

local clock, day = 0, 100
local function Signal()
	local s = { handlers = {} }
	function s:Connect(fn) table.insert(self.handlers, fn) end
	function s:Fire(...) for _, fn in self.handlers do fn(...) end end
	return s
end
local Heartbeat, Removing, Ready = Signal(), Signal(), Signal()
local task = { spawn = function(f, ...) f(...) end, wait = function() end, defer = function(f, ...) f(...) end }

local player = { Name = "P", UserId = 1 }
local Players = { PlayerRemoving = Removing, GetPlayers = function() return { player } end }
player.Parent = Players

local data = {}
local profile = {
	IsActive = function() return true end,
	Get = function(_, path) return data[path[1]] end,
	Set = function(_, path, v) data[path[1]] = v end,
}
local sent, paid = {}, {}
local Daily = {
	priceSpec = function(_, _, spec) return spec.Kind, spec.Amount or spec.Floor, spec.Body end,
	pay = function(_, _, kind, amount, body, source, onGranted)
		table.insert(paid, { kind = kind, amount = amount, body = body, source = source })
		-- The real `pay` commits through this callback; the service records the claim there.
		if onGranted then onGranted() end
		return true
	end,
}
local Garage = { getSignal = function() return Ready end, isProfileReady = function() return false end }

local function boot()
	local registry = { GarageService = Garage, DailyRewardService = Daily }
	local service
	local Shard = {
		new = function()
			service = { handlers = {}, log = { info = function() end, warn = function() end } }
			function service:withDependencies() return self end
			function service:withRemoteEvents(defs)
				for _, d in defs do
					if type(d) == "table" then for k, fn in d do self.handlers[k] = fn end end
				end
				return self
			end
			function service:withLifecycle(l) self.lifecycle = l; return self end
			function service:getRemoteEvent() return { Fire = function(_, _, payload) table.insert(sent, payload) end } end
			return service
		end,
		get = function(n) return registry[n] end,
	}
	local function proxy(path)
		return setmetatable({ __path = path }, { __index = function(self, k)
			if k == "Parent" then return proxy((string.match(rawget(self, "__path"), "^(.*)%.[^%.]+$"))) end
			return proxy(rawget(self, "__path") .. "." .. k)
		end })
	end
	local modules = {
		["ReplicatedStorage.Packages.Shard"] = Shard,
		["ReplicatedStorage.shared.Configs.QuestConfig"] = { dayIndex = function() return day end },
		["ServerScriptService.server.Data"] = { GetProfileAsync = function() return profile end },
	}
	local services = { Players = Players, ReplicatedStorage = proxy("ReplicatedStorage"), RunService = { Heartbeat = Heartbeat } }
	local function env(path)
		return setmetatable({
			game = { GetService = function(_, n) return services[n] end },
			script = proxy(path),
			require = function(p) return modules[rawget(p, "__path")] or error("no stub " .. rawget(p, "__path")) end,
			task = task,
			os = setmetatable({ clock = function() return clock end }, { __index = os }),
		}, { __index = _G })
	end
	local cfgFn = loadstring(SOURCES.PlaytimeRewardConfig); setfenv(cfgFn, env("x")); local cfg = cfgFn()
	modules["ReplicatedStorage.shared.Configs.PlaytimeRewardConfig"] = cfg
	local fn = loadstring(SOURCES.PlaytimeRewardService); setfenv(fn, env("ServerScriptService.server.Services.PlaytimeRewardService"))
	local s = fn()
	s.lifecycle.init(s)
	s.lifecycle.start(s)
	return s, cfg
end

local function claim(s)
	clock += 2 -- past the message floor
	s.handlers.PlaytimeGiftClaim(player)
end
local function last() return sent[#sent] end

-- A fresh day: nothing claimable yet, and nothing inside a gift is given away.
local svc = boot()
Ready:Fire(player)
check(last().claimed == 0 and last().seconds == 0, "fresh ladder")
check(last().gifts[1].Minutes == 1 and last().gifts[1].Kind == nil and last().gifts[6].Body == nil, "unopened gifts do not say what is inside")
claim(svc)
check(#paid == 0, "nothing paid before 1 minute")

-- 1 minute in: gift 1, once, however hard it is pressed.
clock += 60
claim(svc)
svc.handlers.PlaytimeGiftClaim(player) -- same instant: dropped by the floor
check(#paid == 1 and paid[1].amount == 100 and paid[1].source == "Playtime", "gift 1 paid once")
check(last().justClaimed == 1, "reply names the gift")
check(last().gifts[1].Kind == "Cash" and last().gifts[2].Kind == nil, "only the opened gift is revealed")
claim(svc)
check(#paid == 1, "gift 2 not due yet")

-- Left and came back the same day: the clock and the count carry on.
Removing:Fire(player)
check(data.PlaytimeGifts.Claimed == 1 and data.PlaytimeGifts.Seconds >= 60, "saved on leave")
Heartbeat.handlers, Removing.handlers, Ready.handlers = {}, {}, {}
svc = boot()
Ready:Fire(player)
check(last().claimed == 1 and last().seconds >= 60, "resumed the same day")
clock += 120
claim(svc)
check(#paid == 2 and paid[2].amount == 250, "gift 2 after 3 minutes in total")

-- Waiting gifts are not lost: 30 minutes in, presses take 3, 4, 5 and 6 in order.
clock += 1800
claim(svc); claim(svc); claim(svc); claim(svc)
check(#paid == 6 and paid[4].kind == "Revive" and paid[6].kind == "Car", "the rest in order, the car last")
claim(svc)
check(#paid == 6, "nothing past the last gift")

-- The periodic save, and a new day starting the ladder over.
Heartbeat:Fire(61)
check(data.PlaytimeGifts.Claimed == 6, "periodic save")
day += 1
Heartbeat:Fire(61)
check(last().claimed == 0 and last().seconds < 5, "new day resets the ladder")
clock += 60
claim(svc)
check(#paid == 7, "new day's first gift")

-- Yesterday's record does not carry into today on a join.
Heartbeat.handlers, Removing.handlers, Ready.handlers = {}, {}, {}
data.PlaytimeGifts = { Day = day - 1, Seconds = 5000, Claimed = 6 }
svc = boot()
Ready:Fire(player)
check(last().claimed == 0 and last().seconds == 0, "old day ignored on join")

print(string.format("\n%d passed, %d failed", passes, failures))
