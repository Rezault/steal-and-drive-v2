--[[ RoamingCarService — every car on the collector highway, and who stole it
	==========================================================================

	THE SERVER IS THE ONLY PLACE A HIGHWAY CAR EXISTS. It rolls what each car is (body, paint,
	mutation, requirement), drives it down its lane, and decides who stole what. Clients only draw it. This
	is the opposite of the road run, where traffic was client-local and the server could only bound
	a client's claims with single-use tokens (`EncounterService`); nothing here trusts a client's
	word about a car, so none of that machinery is reused.

	REPLICATION: one `Configuration` per car in `ReplicatedStorage.RoamingCars` (not Workspace —
	the place streams, and a car you cannot see must still be a car you were told about). Its
	attributes are the car (`Body`, `Paint`, `Mutation`, `Tier`, `Rung`, `Required`, `Zone`,
	`Secret`) and its LEG (`A`, `B`, `T0`, `T1`, server-clock seconds): arch to arch down its lane, written
	once when it spawns. Everyone, including the server's own distance check, computes the position with
	`CollectorConfig.positionAt`, so a driving car costs no replication at all after its first frame.

	A CAPTURE (`RoamCapture(id)`) is accepted only if, in this order:
	  1. the request is well-formed and the player is off cooldown;
	  2. the car exists and is not already claimed;
	  3. the character is alive and within `Radius + Slack + speed x latency` of where the car is NOW;
	  4. the profile is loaded and the player's Steal Power meets the car's requirement.
	Then the car is marked claimed and destroyed BEFORE anything yields, so two players racing for
	the same car cannot both pass step 2 — Luau runs one handler to its first yield, and there is
	no yield between the check and the claim. Only then is `GarageService.awardCar` called, with
	the server's own record of the car; the client never names a body, paint or mutation.

	`awardCar` HAS NO IDEMPOTENCY OF ITS OWN (every call mints a car), so the claimed-and-removed
	car is that idempotency: a replayed id finds nothing at step 2.

	WORLD EVENTS: every `Events.ResetPeriod` all zones are re-rolled and 1–3 SECRET cars appear,
	announced to the server; between resets a RUSH multiplies one zone's mutation odds for a minute.
	Both are announced through one remote, and the next reset time is a workspace attribute so the
	HUD countdown needs no traffic of its own. ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local CollectorConfig = require(ReplicatedStorage.shared.Configs.CollectorConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
local LobbyCarConfig = require(ReplicatedStorage.shared.Configs.LobbyCarConfig)
local CollectorWorld = require(script.CollectorWorld)

local Remotes = CollectorConfig.Remotes

type Car = {
	id: string,
	inst: Configuration,
	zone: number,
	body: string,
	tier: number,
	rung: number,
	paint: number,
	mutation: string?,
	required: number,
	secret: boolean,
	lane: number,
	a: Vector3,
	b: Vector3,
	t0: number,
	t1: number,
	claimed: boolean,
}

local Service = Shard.new("RoamingCarService")
	:withDependencies({ "GarageService", "WorldService", "WeatherService" })

Service:withRemoteEvents({
	Remotes.Captured, -- server -> capturer: the result, success or why not
	Remotes.Announce, -- server -> all: resets, secret spawns, rushes, secret steals
	{
		[Remotes.Capture] = function(player: Player, id: unknown)
			Service:_onCapture(player, id)
		end,
	},
})

Service:withSignals({ "CarCaptured" }) -- (player, body, tier, mutation, secret)

local function now(): number
	return workspace:GetServerTimeNow()
end

-- === Rolling a car ===========================================================

--- Bodies the client can actually draw. Shells are published by `TrafficService` at boot; a body
--- with no shell is skipped rather than spawned invisible.
function Service._drawable(self, body: string): boolean
	local folder = ReplicatedStorage:FindFirstChild(TrafficConfig.TemplateFolderName)
	return folder == nil or folder:FindFirstChild(body) ~= nil
end

function Service._rollRung(self, zone: number, forced: { number }?): number
	if forced then
		return forced[self._rng:NextInteger(1, #forced)]
	end
	local weights = CollectorConfig.Spawn.RungWeights
	local total = 0
	for _, w in weights do
		total += w
	end
	local pick = self._rng:NextNumber() * total
	for rung, w in weights do
		pick -= w
		if pick <= 0 then
			return rung
		end
	end
	return 1
end

function Service._rollMutation(self, zone: number): string?
	local Weather = Shard.get("WeatherService")
	local event = Weather and Weather:activeEventFor(zone) or nil
	local tries = math.max(1, math.floor(CollectorConfig.Spawn.MutationChance))
	if self._rush and self._rush.zone == zone and now() < self._rush.endsAt then
		tries *= CollectorConfig.Events.RushMutation
	end
	for _ = 1, tries do
		local key = WeatherConfig.roll(self._rng, event)
		if key then
			return key
		end
	end
	return nil
end

--[[ A lane for a car of `rung` coming out of `zone`'s arch now, or nil when every lane's last car is
	still within `MinGap` of the arch. Prefers the lane speed its rarity asks for (`Road.FastRungs`). ]]
function Service._pickLane(self, zone: number, rung: number): number?
	local road = CollectorConfig.Road
	local t = now()
	local last = self._laneAt[zone]
	local want = if rung >= road.FastRungs[2] then 3 elseif rung >= road.FastRungs[1] then 2 else 1
	local speedsByRank = { road.LaneSpeeds[1], road.LaneSpeeds[2], road.LaneSpeeds[3] }
	local free, preferred = {}, {}
	for lane, speed in road.LaneSpeeds do
		if (t - (last[lane] or -math.huge)) * speed >= road.MinGap then
			table.insert(free, lane)
			if speed == speedsByRank[want] then
				table.insert(preferred, lane)
			end
		end
	end
	local pool = if #preferred > 0 and self._rng:NextNumber() < road.LanePreference then preferred else free
	return if #pool > 0 then pool[self._rng:NextInteger(1, #pool)] else nil
end

--[[ Roll a car for `zone` and put it on the road. `lane`/`along` place it mid-road (the fill after a
	reset); without them it comes out of the arch in a free lane, or not at all. ]]
function Service._newCar(self, zone: number, secret: boolean, lane: number?, along: number?): Car?
	local cars = WorldConfig.get(zone).Cars
	local rung, body
	for _ = 1, 8 do
		rung = self:_rollRung(zone, if secret then CollectorConfig.Events.SecretRungs else nil)
		body = cars[rung]
		if body and self:_drawable(body) then
			break
		end
		body = nil
	end
	if not body then
		return nil
	end
	local tier = GarageConfig.TierOfBody[body]
	if not tier then
		return nil
	end

	local mutation
	if secret then
		local pool = CollectorConfig.Events.SecretMutations
		mutation = WeatherConfig.sanitize(pool[self._rng:NextInteger(1, #pool)])
	else
		mutation = self:_rollMutation(zone)
	end

	lane = lane or self:_pickLane(zone, rung)
	if not lane then
		return nil
	end

	self._serial += 1
	local id = string.format("%d", self._serial)
	local inst = Instance.new("Configuration")
	inst.Name = id
	local car: Car = {
		id = id,
		inst = inst,
		zone = zone,
		body = body,
		tier = tier,
		rung = rung,
		paint = PaintConfig.roll(self._rng, body),
		mutation = mutation,
		required = CollectorConfig.requiredFor(tier),
		secret = secret,
		lane = lane,
		a = Vector3.zero,
		b = Vector3.zero,
		t0 = 0,
		t1 = 0,
		claimed = false,
	}
	self:_setLeg(car, along or 0)
	if not along then
		self._laneAt[zone][lane] = now()
	end
	inst:SetAttribute("Body", body)
	inst:SetAttribute("Tier", tier)
	inst:SetAttribute("Rung", rung)
	inst:SetAttribute("Paint", car.paint)
	inst:SetAttribute("Mutation", mutation or "")
	inst:SetAttribute("Required", car.required)
	inst:SetAttribute("Zone", zone)
	inst:SetAttribute("Secret", secret)
	self._cars[id] = car
	inst.Parent = self._folder
	return car
end

function Service._writeLeg(self, car: Car)
	car.inst:SetAttribute("A", car.a)
	car.inst:SetAttribute("B", car.b)
	car.inst:SetAttribute("T0", car.t0)
	car.inst:SetAttribute("T1", car.t1)
end

--- Arch to arch down the car's lane, starting `along` studs past its zone's arch.
function Service._setLeg(self, car: Car, along: number)
	local zStart, zEnd = CollectorConfig.zoneRoad(car.zone)
	local x = CollectorConfig.laneX(car.lane)
	local y = CollectorConfig.Corridor.FloorY
	local speed = CollectorConfig.Road.LaneSpeeds[car.lane]
	car.a = Vector3.new(x, y, zStart - along)
	car.b = Vector3.new(x, y, zEnd)
	car.t0 = now()
	car.t1 = car.t0 + math.max(car.a.Z - car.b.Z, 0) / speed
	self:_writeLeg(car)
end

function Service._remove(self, car: Car)
	self._cars[car.id] = nil
	car.inst:Destroy()
end

-- === Traffic =================================================================

--[[ Seconds between cars out of one zone's arch, so that about `Spawn.CarsPerZone` are on its road at
	once: that count is (spawn rate) x (average time a car spends crossing), and the average is over the
	lanes because a car is equally likely to end up in any of them. ]]
function Service._spawnEvery(self): number
	local road = CollectorConfig.Road
	local zStart, zEnd = CollectorConfig.zoneRoad(1)
	local length = zStart - zEnd
	local total = 0
	for _, speed in road.LaneSpeeds do
		total += length / speed
	end
	return (total / #road.LaneSpeeds) / CollectorConfig.Spawn.CarsPerZone
end

--- Fill a zone's road mid-flow (boot, reset, rush), at the spacing the spawner would have left.
function Service._fill(self, zone: number)
	local road = CollectorConfig.Road
	local zStart, zEnd = CollectorConfig.zoneRoad(zone)
	local length = zStart - zEnd
	local every = self:_spawnEvery()
	local t = now()
	for lane, speed in road.LaneSpeeds do
		-- Cars already in this lane (a secret kept through a rush) keep their room.
		local taken = {}
		for _, car in self._cars do
			if car.zone == zone and car.lane == lane then
				table.insert(taken, zStart - CollectorConfig.positionAt(car.a, car.b, car.t0, car.t1, t).Z)
			end
		end
		-- Each lane gets 1 in #lanes of the spawns, so its cars are `speed x every x #lanes` apart.
		local spacing = speed * every * #road.LaneSpeeds
		local along = self._rng:NextNumber(0, spacing)
		while along < length - road.MinGap do
			local clear = true
			for _, other in taken do
				if math.abs(other - along) < road.MinGap then
					clear = false
				end
			end
			if clear then
				self:_newCar(zone, false, lane, along)
			end
			along += math.max(road.MinGap, spacing * self._rng:NextNumber(0.6, 1.4))
		end
		-- The next car out of this arch keeps its distance from the last one filled near it.
		self._laneAt[zone][lane] = now()
	end
end

--- One tick of the road: cars that reached the far arch leave (a SECRET goes round again), and each
--- zone's arch lets out its next car when it is due.
function Service._stepTraffic(self, t: number)
	for _, car in table.clone(self._cars) do
		if t >= car.t1 and not car.claimed then
			if car.secret then
				self:_setLeg(car, 0)
			else
				self:_remove(car)
			end
		end
	end
	local every = self:_spawnEvery()
	for zone = 1, #CollectorConfig.Zones do
		if t >= (self._nextSpawn[zone] or 0) then
			local car = self:_newCar(zone, false)
			-- No free lane: try again shortly rather than waiting a whole interval.
			self._nextSpawn[zone] = t + if car then every * self._rng:NextNumber(0.6, 1.4) else 0.3
		end
	end
end

-- === Events ==================================================================

function Service._announce(self, payload: { [string]: any })
	self:getRemoteEvent(Remotes.Announce):FireAll(payload)
end

function Service._reset(self)
	for _, car in table.clone(self._cars) do
		if not car.claimed then
			self:_remove(car)
		end
	end

	-- Secret cars first, one each in a few distinct random zones, in a fast lane partway down the road
	-- (so they are on screen at once); the fill then leaves them room. They lap until the next reset.
	local events = CollectorConfig.Events
	local road = CollectorConfig.Road
	local fastest = math.max(table.unpack(road.LaneSpeeds))
	local fastLanes = {}
	for lane, speed in road.LaneSpeeds do
		if speed == fastest then
			table.insert(fastLanes, lane)
		end
	end
	local zones = {}
	for zone = 1, #CollectorConfig.Zones do
		table.insert(zones, zone)
	end
	local secrets = {}
	for _ = 1, self._rng:NextInteger(events.SecretsMin, events.SecretsMax) do
		local zone = table.remove(zones, self._rng:NextInteger(1, #zones))
		local zStart, zEnd = CollectorConfig.zoneRoad(zone or 1)
		local lane = fastLanes[self._rng:NextInteger(1, #fastLanes)]
		local car = zone and self:_newCar(zone, true, lane, self._rng:NextNumber(0, (zStart - zEnd) * 0.5))
		if car then
			table.insert(secrets, { body = car.body, zone = zone, mutation = car.mutation })
		end
	end

	for zone = 1, #CollectorConfig.Zones do
		self:_fill(zone)
	end

	workspace:SetAttribute(CollectorConfig.NextResetAttribute, now() + events.ResetPeriod)
	self:_announce({ kind = "reset", secrets = secrets })
end

function Service._startRush(self)
	local events = CollectorConfig.Events
	local zone = self._rng:NextInteger(1, #CollectorConfig.Zones)
	local endsAt = now() + events.RushSeconds
	self._rush = { zone = zone, endsAt = endsAt }
	workspace:SetAttribute(CollectorConfig.RushAttribute, string.format("%d|%.3f", zone, endsAt))
	-- Re-roll that zone's ordinary cars at once, so the rush is visible when you get there.
	for _, car in table.clone(self._cars) do
		if car.zone == zone and not car.secret then
			self:_remove(car)
		end
	end
	self:_fill(zone)
	self:_announce({ kind = "rush", zone = zone, endsAt = endsAt })
end

-- === Capture =================================================================

function Service._reply(self, player: Player, result: { [string]: any })
	self:getRemoteEvent(Remotes.Captured):Fire(player, result)
end

function Service._onCapture(self, player: Player, id: unknown)
	if not CollectorConfig.Enabled or type(id) ~= "string" or #id > 16 then
		return
	end
	local clock = os.clock()
	if clock - (self._cooldowns[player] or -math.huge) < CollectorConfig.Capture.Cooldown then
		return
	end
	self._cooldowns[player] = clock

	local car = self._cars[id]
	if not car or car.claimed then
		self:_reply(player, { ok = false, reason = "gone", id = id })
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")) then
		return
	end
	local t = now()
	local at = CollectorConfig.positionAt(car.a, car.b, car.t0, car.t1, t)
	local legSpeed = if car.t1 > car.t0 then (car.b - car.a).Magnitude / (car.t1 - car.t0) else 0
	local capture = CollectorConfig.Capture
	local allowed = capture.Radius + capture.Slack + legSpeed * capture.LatencySeconds
	local offset = root.Position - at
	local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
	if flat > allowed or math.abs(offset.Y) > 30 then
		self:_reply(player, { ok = false, reason = "far", id = id })
		return
	end

	local Garage = Shard.get("GarageService")
	if not (Garage and Garage:isProfileReady(player)) then
		return
	end
	local power = CollectorConfig.powerOf(player)
	if power < car.required then
		self:_reply(player, { ok = false, reason = "weak", id = id, required = car.required })
		return
	end

	-- THE CLAIM. Nothing above yields, so nobody else can have got here for this car.
	car.claimed = true
	self:_remove(car)

	local outcome, amount, carId = Garage:awardCar(player, car.tier, car.body, car.paint, car.mutation, capture.Source)
	if outcome == "rejected" then
		self.log:warn(string.format("%s's capture of %s was rejected by GarageService.", player.Name, car.body))
		self:_reply(player, { ok = false, reason = "rejected", id = id })
		return
	end

	self:_reply(player, {
		ok = true,
		id = id,
		body = car.body,
		tier = car.tier,
		rung = car.rung,
		paint = car.paint,
		mutation = car.mutation,
		secret = car.secret,
		outcome = outcome,
		amount = amount,
		carId = carId,
		zone = car.zone,
	})
	self:getSignal("CarCaptured"):Fire(player, car.body, car.tier, car.mutation, car.secret)
	if CollectorConfig.Drive.Swap then
		-- A full inventory sells the car (no id); they still get to drive it.
		self:_driveCaptured(player, car, carId or GarageConfig.carKey(car.body, car.paint, car.mutation), carId == nil)
	end
	if car.secret then
		self:_announce({ kind = "stolen", player = player.DisplayName, body = car.body, zone = car.zone, mutation = car.mutation })
	end
end

-- === Driving (CollectorConfig.Drive) ===========================================

--- Replace the player's car with the one they just took, standing where it was, nose down its lane.
function Service._driveCaptured(self, player: Player, car: Car, key: string, free: boolean)
	local Lobby = Shard.get("LobbyCarService")
	if not Lobby then
		return
	end
	local current = Lobby:getLobbyCar(player)
	if current and current:GetAttribute(LobbyCarConfig.KeyAttribute) == key then
		return -- same key would read as "put it away"
	end
	local p = CollectorConfig.positionAt(car.a, car.b, car.t0, car.t1, now())
	local floor = Vector3.new(p.X, CollectorConfig.Corridor.FloorY + 0.3, p.Z)
	local ahead = Vector3.new(car.b.X - car.a.X, 0, car.b.Z - car.a.Z)
	if ahead.Magnitude < 0.5 then
		ahead = Vector3.new(0, 0, -1) -- the way every lane runs
	end
	local ok, reason = Lobby:setLobbyCar(player, key, {
		ground = CFrame.lookAt(floor, floor + ahead.Unit),
		seat = true,
		seatDelay = CollectorConfig.Drive.SeatDelay,
		free = free,
	})
	if not ok then
		self.log:warn(string.format("%s could not drive their %s: %s", player.Name, key, reason))
	end
end

--- Park the start car beside a player who has none. Free, and not added to their inventory.
function Service._ensureCar(self, player: Player)
	local Lobby = Shard.get("LobbyCarService")
	local Starts = Shard.get("StartCarService")
	if not (player.Parent and Lobby and Starts) or Lobby:getLobbyCar(player) then
		return
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local body, paint, mutation = Starts:carFor(player, 1)
	local ok, reason = Lobby:setLobbyCar(player, GarageConfig.carKey(body, paint, mutation), { free = true })
	if not ok then
		self.log:warn(string.format("No starter car for %s: %s", player.Name, reason))
	end
end

function Service._watchStarter(self)
	local delay = CollectorConfig.Drive.StarterDelay
	local function later(player: Player)
		task.delay(delay, self._ensureCar, self, player)
	end
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			later(player)
		end)
		if player.Character then
			later(player)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	-- Death, Back to Base, selling it: any despawn that is not a swap leaves them with no car.
	local Lobby = Shard.get("LobbyCarService")
	if Lobby then
		Lobby:getSignal("CarDespawned"):Connect(later)
	end
end

-- === Players: world follows the zone you stand in ============================

--[[ Public: a highway steal landed (`StealService._onLanded`, `CollectorConfig.RoadSteal`). `car` is
	`EncounterService`'s record of the token the client redeemed — the SERVER's roll, never the
	client's word — so tier, body, paint and mutation are trusted as they stand.

	THE ⚡ GATE IS RE-CHECKED HERE. The client refuses to lock a car you cannot take
	(`StealController`), but a client is not a trust boundary: a forged landing on a car above your
	power is answered "weak" and banks nothing. Returns whether the car was awarded. ]]
function Service.awardRoadSteal(self, player: Player, car: { tier: number, body: string, paint: number?, mutation: string? }): boolean
	local Garage = Shard.get("GarageService")
	if not (Garage and Garage:isProfileReady(player)) then
		return false
	end
	local required = CollectorConfig.requiredForBody(car.body) or CollectorConfig.requiredFor(car.tier)
	if CollectorConfig.powerOf(player) < required then
		self:_reply(player, { ok = false, reason = "weak", required = required })
		return false
	end
	local outcome, amount, carId = Garage:awardCar(player, car.tier, car.body, car.paint, car.mutation, CollectorConfig.Capture.Source)
	if outcome == "rejected" then
		self.log:warn(string.format("%s's road steal of %s was rejected by GarageService.", player.Name, car.body))
		return false
	end
	self:_reply(player, {
		ok = true,
		body = car.body,
		tier = car.tier,
		paint = car.paint,
		mutation = car.mutation,
		outcome = outcome,
		amount = amount,
		carId = carId,
	})
	self:getSignal("CarCaptured"):Fire(player, car.body, car.tier, car.mutation, false)
	return true
end

--[[ Two pieces of existing state are kept in step with the collector so the systems that read
	them (music, customer tip scale, the Index, upgrade gates) keep working without knowing it exists:
	  • `WorldsUnlocked` rises when your Steal Power first reaches a zone's cheapest car, and
	  • `World` follows the zone you are standing in (only ever to an unlocked one).
	Both through `WorldService`, which persists and publishes them as it always has. ]]
function Service._syncPlayer(self, player: Player)
	local Garage = Shard.get("GarageService")
	local World = Shard.get("WorldService")
	if not (Garage and World and Garage:isProfileReady(player)) then
		return
	end
	local power = CollectorConfig.powerOf(player)
	local highest = World:highestUnlocked(player)
	local reach = highest
	for zone = highest + 1, #CollectorConfig.Zones do
		if power >= CollectorConfig.zoneMinimum(zone) then
			reach = zone
		end
	end
	if reach > highest then
		World:setUnlocked(player, reach)
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local zone = CollectorConfig.zoneAt(root.Position)
		if zone > 0 and zone <= math.max(reach, 1) and World:worldOf(player) ~= zone then
			World:setWorld(player, zone)
		end
	end
end

-- === Lifecycle ===============================================================

Service:withLifecycle({
	init = function(self)
		self._rng = Random.new()
		self._serial = 0
		self._cars = {} :: { [string]: Car }
		-- [zone][lane] = when the last car came out of that arch in that lane
		self._laneAt = {} :: { [number]: { [number]: number } }
		for zone = 1, #CollectorConfig.Zones do
			self._laneAt[zone] = {}
		end
		self._nextSpawn = {} :: { [number]: number }
		self._cooldowns = {} :: { [Player]: number }
		self._rush = nil
	end,

	start = function(self)
		-- Road steals (`awardRoadSteal`) need nothing started; the highway below is the Roaming mode.
		if not (CollectorConfig.Enabled and CollectorConfig.Roaming) then
			return
		end
		local folder = ReplicatedStorage:FindFirstChild(CollectorConfig.FolderName)
		if folder then
			folder:ClearAllChildren()
		else
			folder = Instance.new("Folder")
			folder.Name = CollectorConfig.FolderName
			folder.Parent = ReplicatedStorage
		end
		self._folder = folder

		CollectorWorld.build()
		if CollectorConfig.Drive.Starter then
			self:_watchStarter()
		end

		self._playerLeft = Players.PlayerRemoving:Connect(function(player)
			self._cooldowns[player] = nil
		end)

		task.spawn(function()
			-- Wait for TrafficService to publish shells so the first roll can tell what is drawable.
			ReplicatedStorage:WaitForChild(TrafficConfig.TemplateFolderName, 15)
			self:_reset()
			local events = CollectorConfig.Events
			workspace:SetAttribute(CollectorConfig.NextResetAttribute, now() + events.FirstResetDelay)
			local nextRush = now() + events.RushEvery
			local nextSync = 0
			while self._folder.Parent do
				local t = now()
				self:_stepTraffic(t)
				if t >= (workspace:GetAttribute(CollectorConfig.NextResetAttribute) or math.huge) then
					self:_reset()
					nextRush = t + events.RushEvery
				elseif t >= nextRush then
					self:_startRush()
					nextRush = t + events.ResetPeriod -- once between resets
				end
				if self._rush and t >= self._rush.endsAt then
					self._rush = nil
					workspace:SetAttribute(CollectorConfig.RushAttribute, "")
				end
				if t >= nextSync then
					nextSync = t + 1
					for _, player in Players:GetPlayers() do
						task.spawn(self._syncPlayer, self, player)
					end
				end
				task.wait(0.1)
			end
		end)
	end,
})

Service:withCleanup(function()
	if Service._playerLeft then
		Service._playerLeft:Disconnect()
	end
	if Service._folder then
		Service._folder:Destroy()
	end
end)

return Service
