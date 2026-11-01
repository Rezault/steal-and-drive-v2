-- Test harness for the collector: the REAL CollectorConfig and RoamingCarService under stubs.
-- Covers the power/price ladders, the shared position function, and every capture rejection path,
-- including two players racing for one car (the award must happen exactly once).
-- SOURCES is prepended by tests/collector/run.sh.

local failures, passes = 0, 0
local function check(cond, msg)
	if cond then
		passes += 1
	else
		failures += 1
		print("FAIL: " .. msg)
	end
end

-- === A minimal Vector3 (plain luau has none) ===================================
local V = {}
V.__index = V
local function vec(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V)
end
V.__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__mul = function(a, s) return vec(a.X * s, a.Y * s, a.Z * s) end
V.__index = function(self, k)
	if k == "Magnitude" then return math.sqrt(self.X ^ 2 + self.Y ^ 2 + self.Z ^ 2) end
	return V[k]
end
function V.Lerp(a, b, t) return a + (b - a) * t end
local Vector3 = { new = vec, zero = vec(0, 0, 0), one = vec(1, 1, 1) }

-- === Stubs ======================================================================
local clock, serverNow = 0, 1000
local function proxy(path)
	return setmetatable({ __path = path }, { __index = function(self, k)
		if k == "Parent" then return proxy((string.match(rawget(self, "__path"), "^(.*)%.[^%.]+$"))) end
		return proxy(rawget(self, "__path") .. "." .. k)
	end })
end
local function Signal()
	local s = { handlers = {} }
	function s:Connect(fn) table.insert(self.handlers, fn); return { Disconnect = function() end } end
	function s:Fire(...) for _, fn in self.handlers do fn(...) end end
	return s
end

local modules = {}
local workspaceStub = { GetServerTimeNow = function() return serverNow end, SetAttribute = function() end, GetAttribute = function() end }
local function env(path)
	return setmetatable({
		game = { GetService = function(_, n)
			if n == "Players" then return { PlayerRemoving = Signal(), GetPlayers = function() return {} end } end
			return proxy(n)
		end },
		script = proxy(path),
		require = function(p) return modules[rawget(p, "__path")] or error("no stub " .. tostring(rawget(p, "__path"))) end,
		workspace = workspaceStub,
		Vector3 = Vector3,
		Color3 = { fromRGB = function(r, g, b) return { r, g, b } end, new = function(r, g, b) return { r, g, b } end },
		UDim2 = { fromOffset = function(x, y) return { x, y } end, fromScale = function(x, y) return { x, y } end },
		Enum = proxy("Enum"),
		Random = { new = function() return { NextNumber = function(_, a, b) return a or 0 end, NextInteger = function(_, a) return a end } end },
		os = setmetatable({ clock = function() return clock end }, { __index = os }),
		task = { spawn = function() end, wait = function() end, delay = function() end },
	}, { __index = _G })
end

-- GarageConfig.valueOf: the real curve's shape is "rising with tier, with dips at world starts".
local values = {}
for t = 1, 50 do
	values[t] = math.round(600 * 1.25 ^ (t - 1) * (if t % 10 == 1 and t > 1 then 0.6 else 1))
end
local upgradesOf = {} -- [player] = { Trainer = level }
modules["ReplicatedStorage.shared.Configs.UpgradeConfig"] = {
	levelOf = function(upgrades, key) return (type(upgrades) == "table" and upgrades[key]) or 0 end,
}
modules["ReplicatedStorage.shared.Configs.WorldConfig"] = { TierOfBody = { Civic = 1, M5 = 10, Jesko = 50 } }
modules["ReplicatedStorage.shared.Configs.GarageConfig"] = {
	valueOf = function(tier) return values[tier] end,
	TierOfBody = { Civic = 1, M5 = 10, Jesko = 50 },
}

local cfgFn = loadstring(SOURCES.CollectorConfig)
setfenv(cfgFn, env("ReplicatedStorage.shared.Configs.CollectorConfig"))
local Collector = cfgFn()
modules["ReplicatedStorage.shared.Configs.CollectorConfig"] = Collector

-- === Config: the ladders ===================================================
do
	check(Collector.requiredFor(1) == 10, "tier 1 needs 10")
	check(Collector.Power.Start == Collector.requiredFor(1), "a new player can steal the first car")
	local previous = 0
	for tier = 1, 50 do
		local r = Collector.requiredFor(tier)
		check(r > previous, "requirement rises at tier " .. tier)
		previous = r
	end
	check(Collector.requiredForBody("M5") == Collector.requiredFor(10), "a body needs its tier's power")
	check(Collector.requiredForBody("NotACar") == nil and Collector.requiredForBody(5) == nil, "no ladder, no requirement")
	local lastRate = 0
	for level = 0, Collector.Trainer.MaxLevel do
		local rate = Collector.rateAt(level)
		check(rate > lastRate, "the ride trains faster at level " .. level)
		lastRate = rate
	end
	check(Collector.rateAt(999) == Collector.rateAt(Collector.Trainer.MaxLevel), "rate clamps at the top")
	check(Collector.requiredFor(10) / Collector.rateAt(0) <= 180, "world 1's top car trains in under 3 minutes at level 0")
	local last = 0
	for level = 0, Collector.Trainer.MaxLevel - 1 do
		local cost = Collector.trainerCost(level)
		check(type(cost) == "number" and cost >= last, "price never dips at level " .. level)
		last = cost or last
	end
	check(Collector.trainerCost(Collector.Trainer.MaxLevel) == nil, "no price past the top")
	check(Collector.trainerCost(0) <= 1000, "first ride upgrade is about one Civic")
	check(Collector.formatPower(15100) == "15.1K" and Collector.formatPower(42.7) == "42", "power reads like the reference")
	check(Collector.zoneMinimum(2) == Collector.requiredFor(11), "zone 2 opens at tier 11")
end

-- === Config: positions and zones ============================================
do
	local a, b = vec(0, 0, 0), vec(100, 0, 0)
	check(Collector.positionAt(a, b, 10, 20, 5).X == 0, "before the leg: at A")
	check(Collector.positionAt(a, b, 10, 20, 25).X == 100, "after the leg: at B")
	check(math.abs(Collector.positionAt(a, b, 10, 20, 15).X - 50) < 1e-6, "halfway (smoothstep is symmetric)")
	check(Collector.positionAt(a, b, 10, 10, 10).X == 100, "zero-length leg is at B")
	local c = Collector.Corridor
	check(Collector.zoneAt(vec(c.CenterX, c.FloorY, c.StartZ + 10)) == 0, "the hub is zone 0")
	check(Collector.zoneAt(vec(c.CenterX, c.FloorY, c.StartZ - 1)) == 1, "just past the line is zone 1")
	check(Collector.zoneAt(vec(c.CenterX, c.FloorY, c.StartZ - c.ZoneLength * 4.5)) == 5, "zone 5")
	check(Collector.zoneAt(vec(c.CenterX, c.FloorY, c.StartZ - c.ZoneLength * 9)) == 0, "past the end is nowhere")
	check(Collector.zoneAt(vec(c.CenterX + 900, c.FloorY, c.StartZ - 50)) == 0, "outside the walls is nowhere")
end

-- === Service: capture ======================================================
local awards, replies, announces = {}, {}, {}
local ready = true
local Garage = {
	isProfileReady = function() return ready end,
	getUpgrades = function(_, player) return upgradesOf[player] or {} end,
	awardCar = function(_, player, tier, body, paint, mutation, source)
		table.insert(awards, { player = player, tier = tier, body = body, paint = paint, mutation = mutation, source = source })
		return "collected", 0, body .. "#1"
	end,
}
local registry = { GarageService = Garage }
local service
modules["ReplicatedStorage.Packages.Shard"] = {
	new = function()
		service = { handlers = {}, signals = {}, log = { info = function() end, warn = function() end } }
		function service:withDependencies() return self end
		function service:withSignals(names) for _, n in names do self.signals[n] = Signal() end return self end
		function service:getSignal(n) return self.signals[n] end
		function service:withRemoteEvents(defs)
			for _, d in defs do
				if type(d) == "table" then for k, fn in d do self.handlers[k] = fn end end
			end
			return self
		end
		function service:withLifecycle(l) self.lifecycle = l; return self end
		function service:withCleanup() return self end
		function service:getRemoteEvent(name)
			return {
				Fire = function(_, player, payload) table.insert(replies, { player = player, payload = payload }) end,
				FireAll = function(_, payload) table.insert(announces, payload) end,
			}
		end
		return service
	end,
	get = function(n) return registry[n] end,
}
for _, name in { "WeatherConfig", "PaintConfig", "TrafficConfig" } do
	modules["ReplicatedStorage.shared.Configs." .. name] = {}
end
modules["ServerScriptService.server.Services.RoamingCarService.CollectorWorld"] = { build = function() end }

local fn = loadstring(SOURCES.RoamingCarService)
setfenv(fn, env("ServerScriptService.server.Services.RoamingCarService"))
local s = fn()
s.lifecycle.init(s)

local function player(name, x, z)
	local root = { Position = vec(x, -87, z), IsA = function(_, c) return c == "BasePart" end }
	local humanoid = { Health = 100 }
	local character = {
		FindFirstChildOfClass = function(_, c) return if c == "Humanoid" then humanoid else nil end,
		FindFirstChild = function(_, n) return if n == "HumanoidRootPart" then root else nil end,
	}
	local attrs = {}
	return { Name = name, DisplayName = name, Character = character, root = root, humanoid = humanoid, attrs = attrs,
		GetAttribute = function(_, key) return attrs[key] end }
end

local destroyed = {}
local function addCar(id, tier, at, secret)
	local car = {
		id = id, zone = 1, body = "Civic", tier = tier, rung = 1, paint = 1, mutation = nil,
		required = Collector.requiredFor(tier), secret = secret or false, herd = nil, offset = Vector3.zero,
		a = at, b = at, t0 = serverNow, t1 = serverNow, claimed = false,
		inst = { Destroy = function() destroyed[id] = true end },
	}
	s._cars[id] = car
	return car
end
local function capture(p, id)
	clock += 1 -- clear the cooldown
	s.handlers[Collector.Remotes.Capture](p, id)
end
local function lastReply() return replies[#replies] and replies[#replies].payload end

local spot = vec(7490, -90, -1200)
local alice = player("Alice", 7495, -1200)

-- happy path, then the replay
addCar("1", 1, spot)
capture(alice, "1")
check(#awards == 1 and awards[1].body == "Civic" and awards[1].source == Collector.Capture.Source, "a stealable car in range is awarded")
check(lastReply().ok == true and lastReply().carId == "Civic#1", "the capturer is told it worked")
check(destroyed["1"] and s._cars["1"] == nil, "the car leaves the world")
capture(alice, "1")
check(#awards == 1 and lastReply().reason == "gone", "replaying the id awards nothing")

-- two players, one car: exactly one award
local bob = player("Bob", 7485, -1200)
addCar("2", 1, spot)
capture(alice, "2")
capture(bob, "2")
check(#awards == 2 and awards[2].player == alice, "racing players: only the first is awarded")
check(lastReply().ok == false and lastReply().reason == "gone", "the second is told it is gone")

-- out of range (car idle, so only Radius + Slack applies)
addCar("3", 1, spot)
local far = player("Far", 7490 + Collector.Capture.Radius + Collector.Capture.Slack + 5, -1200)
capture(far, "3")
check(#awards == 2 and lastReply().reason == "far" and s._cars["3"] ~= nil, "out of range is refused and the car stays")

-- a moving car is allowed its leg speed x latency
local moving = addCar("4", 1, spot)
moving.a, moving.b, moving.t0, moving.t1 = vec(7490, -90, -1150), vec(7490, -90, -1250), serverNow - 5, serverNow + 5
local chaser = player("Chaser", 7490 + Collector.Capture.Radius + Collector.Capture.Slack + 3, -1200)
capture(chaser, "4")
check(#awards == 3, "a moving car allows its speed x latency of slack")

-- not enough power
addCar("5", 12, spot)
capture(alice, "5")
check(#awards == 3 and lastReply().reason == "weak" and s._cars["5"] ~= nil, "too weak is refused and the car stays")
alice.attrs.StealPower = Collector.requiredFor(12)
capture(alice, "5")
check(#awards == 4 and awards[4].tier == 12, "with the power, the same car is awarded")

-- malformed, dead, cooldown, profile not ready
local before = #replies
s.handlers[Collector.Remotes.Capture](alice, 5)
s.handlers[Collector.Remotes.Capture](alice, string.rep("9", 40))
check(#replies == before, "malformed ids are ignored silently")
addCar("6", 1, spot)
alice.humanoid.Health = 0
capture(alice, "6")
check(#awards == 4 and s._cars["6"] ~= nil, "a dead character steals nothing")
alice.humanoid.Health = 100
clock += 1
s.handlers[Collector.Remotes.Capture](bob, "6")
s.handlers[Collector.Remotes.Capture](bob, "6") -- same instant: cooldown
check(#awards == 5, "cooldown swallows a same-instant repeat")
ready = false
addCar("7", 1, spot)
capture(alice, "7")
check(#awards == 5 and s._cars["7"] ~= nil, "no award before the profile loads")
ready = true

-- a secret car is announced when stolen
addCar("8", 1, spot, true)
capture(alice, "8")
check(announces[#announces] and announces[#announces].kind == "stolen", "stealing a secret is announced")


-- === Service: road steals (the jump-and-land path) ===========================
do
	local rider = player("Rider", 0, 0)
	local n = #awards
	rider.attrs.StealPower = Collector.requiredFor(10) - 1
	check(s:awardRoadSteal(rider, { tier = 10, body = "M5", paint = 2 }) == false, "a weak landing is refused")
	check(#awards == n and lastReply().reason == "weak" and lastReply().required == Collector.requiredFor(10), "the refusal says what is needed")
	rider.attrs.StealPower = Collector.requiredFor(10)
	check(s:awardRoadSteal(rider, { tier = 10, body = "M5", paint = 2 }) == true, "enough power takes the car")
	check(#awards == n + 1 and awards[#awards].body == "M5" and awards[#awards].source == Collector.Capture.Source, "the car goes to the garage")
	check(lastReply().ok == true and lastReply().carId == "M5#1", "the toast gets the car")
	ready = false
	check(s:awardRoadSteal(rider, { tier = 1, body = "Civic", paint = 1 }) == false and #awards == n + 1, "no award before the profile loads")
	ready = true
end

print(string.format("%d passed, %d failed", passes, failures))
