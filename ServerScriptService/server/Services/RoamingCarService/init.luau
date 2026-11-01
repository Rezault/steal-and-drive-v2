--[[ RoamingCarService — every car roaming the collector zones, and who stole it
	==========================================================================

	THE SERVER IS THE ONLY PLACE A ROAMING CAR EXISTS. It rolls what each car is (body, paint,
	mutation, requirement), moves the herds, and decides who stole what. Clients only draw it. This
	is the opposite of the road run, where traffic was client-local and the server could only bound
	a client's claims with single-use tokens (`EncounterService`); nothing here trusts a client's
	word about a car, so none of that machinery is reused.

	REPLICATION: one `Configuration` per car in `ReplicatedStorage.RoamingCars` (not Workspace —
	the place streams, and a car you cannot see must still be a car you were told about). Its
	attributes are the car (`Body`, `Paint`, `Mutation`, `Tier`, `Rung`, `Required`, `Zone`,
	`Secret`) and its current LEG (`A`, `B`, `T0`, `T1`, server-clock seconds). A herd costs one
	attribute write per car per leg — every few seconds — and everyone, including the server's own
	distance check, computes the position with `CollectorConfig.positionAt`.

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
	herd: Herd?,
	offset: Vector3,
	a: Vector3,
	b: Vector3,
	t0: number,
	t1: number,
	claimed: boolean,
}

type Herd = {
	zone: number,
	members: { Car },
	centre: Vector3,
	speed: number,
	nextAt: number,
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

function Service._newCar(self, zone: number, position: Vector3, secret: boolean): Car?
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
		herd = nil,
		offset = Vector3.zero,
		a = position,
		b = position,
		t0 = now(),
		t1 = now(),
		claimed = false,
	}
	inst:SetAttribute("Body", body)
	inst:SetAttribute("Tier", tier)
	inst:SetAttribute("Rung", rung)
	inst:SetAttribute("Paint", car.paint)
	inst:SetAttribute("Mutation", mutation or "")
	inst:SetAttribute("Required", car.required)
	inst:SetAttribute("Zone", zone)
	inst:SetAttribute("Secret", secret)
	self:_writeLeg(car)
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

function Service._remove(self, car: Car)
	self._cars[car.id] = nil
	local herd = car.herd
	if herd then
		local index = table.find(herd.members, car)
		if index then
			table.remove(herd.members, index)
		end
		if #herd.members == 0 then
			local list = self._herds
			local at = table.find(list, herd)
			if at then
				table.remove(list, at)
			end
		end
	end
	car.inst:Destroy()
end

-- === Herds ===================================================================

function Service._randomPoint(self, zone: number, margin: number): Vector3
	local centre, hx, hz = CollectorConfig.zoneRect(zone)
	return centre
		+ Vector3.new(
			self._rng:NextNumber(-hx + margin, hx - margin),
			CollectorConfig.Move.Lift,
			self._rng:NextNumber(-hz + margin, hz - margin)
		)
end

function Service._spawnHerd(self, zone: number, size: number, secret: boolean): Herd?
	local spacing = CollectorConfig.Move.FormationSpacing
	local herd: Herd = {
		zone = zone,
		members = {},
		centre = self:_randomPoint(zone, spacing * 2),
		speed = 0,
		nextAt = now() + self._rng:NextNumber(0.5, 3),
	}
	local speeds = CollectorConfig.Move.Speed
	for i = 1, size do
		-- A loose wedge behind the leader, jittered so a herd never looks like a parade.
		local row = math.floor((i - 1) / 2)
		local side = if i % 2 == 0 then 1 else -1
		local offset = Vector3.new(
			(if i == 1 then 0 else side * spacing * 0.6) + self._rng:NextNumber(-3, 3),
			0,
			row * spacing + self._rng:NextNumber(-3, 3)
		)
		local car = self:_newCar(zone, herd.centre + offset, secret)
		if car then
			car.herd = herd
			car.offset = offset
			table.insert(herd.members, car)
			local speed = speeds[1] + (speeds[2] - speeds[1]) * (car.rung - 1) / 9
			herd.speed = math.max(herd.speed, speed)
		end
	end
	if #herd.members == 0 then
		return nil
	end
	table.insert(self._herds, herd)
	return herd
end

function Service._stepHerd(self, herd: Herd, t: number)
	local move = CollectorConfig.Move
	local spacing = move.FormationSpacing
	local centre, hx, hz = CollectorConfig.zoneRect(herd.zone)
	local distance = self._rng:NextNumber(move.LegDistance[1], move.LegDistance[2])
	local angle = self._rng:NextNumber(0, math.pi * 2)
	local target = herd.centre + Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance
	target = Vector3.new(
		math.clamp(target.X, centre.X - hx + spacing * 2, centre.X + hx - spacing * 2),
		herd.centre.Y,
		math.clamp(target.Z, centre.Z - hz + spacing * 2, centre.Z + hz - spacing * 2)
	)
	-- The formation turns with the herd, so the leader is always in front.
	local facing = CFrame.lookAt(herd.centre, target + Vector3.new(0, 0, 1e-3))
	local duration = 0
	for _, car in herd.members do
		local from = CollectorConfig.positionAt(car.a, car.b, car.t0, car.t1, t)
		local to = target + facing:VectorToWorldSpace(car.offset)
		car.a, car.b = from, to
		duration = math.max(duration, (to - from).Magnitude / herd.speed)
	end
	duration = math.max(duration, 0.5)
	for _, car in herd.members do
		car.t0, car.t1 = t, t + duration
		self:_writeLeg(car)
	end
	herd.centre = target
	herd.nextAt = t + duration + self._rng:NextNumber(move.Idle[1], move.Idle[2])
end

function Service._populate(self, zone: number)
	local count = 0
	for _, car in self._cars do
		if car.zone == zone and not car.secret then
			count += 1
		end
	end
	local want = CollectorConfig.Spawn.CarsPerZone
	local sizes = CollectorConfig.Spawn.HerdSize
	local guard = 0
	while count < want and guard < 20 do
		guard += 1
		local size = math.min(self._rng:NextInteger(sizes[1], sizes[2]), want - count)
		local herd = self:_spawnHerd(zone, size, false)
		count += if herd then #herd.members else 0
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
	table.clear(self._herds)
	self._refillAt = {}
	for zone = 1, #CollectorConfig.Zones do
		self:_populate(zone)
	end

	-- Secret cars: one each in a few distinct random zones.
	local events = CollectorConfig.Events
	local zones = {}
	for zone = 1, #CollectorConfig.Zones do
		table.insert(zones, zone)
	end
	local secrets = {}
	for _ = 1, self._rng:NextInteger(events.SecretsMin, events.SecretsMax) do
		local zone = table.remove(zones, self._rng:NextInteger(1, #zones))
		local herd = zone and self:_spawnHerd(zone, 1, true)
		local car = herd and herd.members[1]
		if car then
			table.insert(secrets, { body = car.body, zone = zone, mutation = car.mutation })
		end
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
	self:_populate(zone)
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
	local power = CollectorConfig.powerOf(Garage:getUpgrades(player))
	if power < car.required then
		self:_reply(player, { ok = false, reason = "weak", id = id, required = car.required })
		return
	end

	-- THE CLAIM. Nothing above yields, so nobody else can have got here for this car.
	car.claimed = true
	self:_remove(car)
	if not car.secret then
		local delay = CollectorConfig.Spawn.RespawnDelay
		self._refillAt[car.zone] = math.max(self._refillAt[car.zone] or 0, t + self._rng:NextNumber(delay[1], delay[2]))
	end

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
	if car.secret then
		self:_announce({ kind = "stolen", player = player.DisplayName, body = car.body, zone = car.zone, mutation = car.mutation })
	end
end

-- === Players: world follows the zone you stand in ============================

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
	local power = CollectorConfig.powerOf(Garage:getUpgrades(player))
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
		self._herds = {} :: { Herd }
		self._refillAt = {} :: { [number]: number }
		self._cooldowns = {} :: { [Player]: number }
		self._rush = nil
	end,

	start = function(self)
		if not CollectorConfig.Enabled then
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
				for _, herd in table.clone(self._herds) do
					if t >= herd.nextAt then
						self:_stepHerd(herd, t)
					end
				end
				for zone = 1, #CollectorConfig.Zones do
					if t >= (self._refillAt[zone] or 0) then
						self:_populate(zone)
						self._refillAt[zone] = t + 1
					end
				end
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
				task.wait(0.2)
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
