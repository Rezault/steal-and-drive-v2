--[[
	KnockableService  (server)
	--------------------------
	The lobby's bushes and trees, which a lobby car drives through and tears out of the ground
	(`LobbyCarConfig.Knockables` has the request and what counts as one).

	=== TWO RULES, AND WHY THE FIRST ONE IS A COLLISION GROUP ==================================

	1. A LOBBY CAR NEVER COLLIDES WITH ONE. Every knockable part is moved into its own group,
	   `KNOCK_GROUP`, which does not collide with `PlayerCar` (lobby and race cars). The alternative
	   was a `Touched` on each bush and unanchoring it on contact, and it loses: by the time Touched
	   fires the physics has already resolved the hit, so the car stops dead against an anchored hedge
	   for a frame and then the hedge flies. Here the car never meets it at all; the knock is found by
	   a box query around each moving car instead (`_sweep`), several times a second.
	2. A PLAYER ON FOOT STILL DOES. `KNOCK_GROUP` keeps colliding with Default and with characters, so
	   walking into a hedge is what it always was.

	Once knocked, a piece is put in the traffic DEBRIS group (`TrafficConfig.Collision.DebrisGroup`),
	which lands on the map and ignores cars, so a flying bush cannot pin the car that hit it. It grows
	back on its own: re-anchored where it stood, the group it had put back, faded in.

	THE SERVER OWNS IT so every player sees the same hedge fly. There is no trust question: a client
	can only drive its own car into things, which is the feature.
]]

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local LobbyCarConfig = require(ReplicatedStorage.shared.Configs.LobbyCarConfig)
local PlotConfig = require(ReplicatedStorage.shared.Configs.PlotConfig)
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
--- So the car groups exist before this one is wired against them (the ordering trap
--- `Modules/CrowdCollision`'s header describes).
local CarCollision = require(ReplicatedStorage.shared.Modules.CarCollision)

local KnockableService = Shard.new("KnockableService")

--- The group every standing knockable is in. An implementation detail, not a tuning knob.
local KNOCK_GROUP = "Knockable"
--- Seconds between box sweeps. A car at 60 studs/s moves 6 studs between two at this rate, under
--- the length of a car, so it cannot pass clean through a bush unseen.
local SWEEP_EVERY = 0.1

type Entry = { part: BasePart, cframe: CFrame, group: string, transparency: number }
type Record = { name: string, entries: { Entry }, down: boolean }

--[[ Register `KNOCK_GROUP` and say what it meets: the map and people, yes; cars and traffic, no.
	False, and a warning, when the groups cannot be had; the greenery then stays solid. ]]
function KnockableService._ensureGroup(self): boolean
	CarCollision.ensure()
	local car = TrafficConfig.Collision
	local ok, err = pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(KNOCK_GROUP) then
			PhysicsService:RegisterCollisionGroup(KNOCK_GROUP)
		end
		PhysicsService:CollisionGroupSetCollidable(KNOCK_GROUP, "Default", true)
		local others = { car.PlayerGroup, car.TrafficGroup }
		--- Lobby cars have a group each now (`CarCollision.applyLobbyCar`); none of them meets a bush.
		for i = 1, CarCollision.LobbySlots do
			table.insert(others, CarCollision.lobbyGroup(i))
		end
		for _, other in others do
			if PhysicsService:IsCollisionGroupRegistered(other) then
				PhysicsService:CollisionGroupSetCollidable(KNOCK_GROUP, other, false)
			end
		end
	end)
	if not ok then
		self.log:warn(string.format("No knockable greenery (%s); bushes and trees stay solid to cars.", tostring(err)))
	end
	return ok
end

--[[ Is `inst` one of `Knockables.Names` or tagged? Case blind on the name. `loose` is whether no
	Model stands between it and the map, which `LooseNames` (the rocks) require. ]]
local function matches(inst: Instance, cfg, loose: boolean): boolean
	if CollectionService:HasTag(inst, cfg.Tag) then
		return true
	end
	if loose and table.find(cfg.LooseNames or {}, inst.Name) then
		return true
	end
	--[[ WHOLE WORDS, NOT SUBSTRINGS (2026-10-14). "tree" as a substring matched "Street", and a
		street segment moved into `KNOCK_GROUP` is road a car falls through. The name is split into its
		words (spaces, digits, underscores and camelCase all break one: "PalmTree2" is palm, tree), and
		a word counts if it IS one of `Names` or its plural ("bushes", "trees"). ]]
	local spaced = string.gsub(inst.Name, "(%l)(%u)", "%1 %2")
	for token in string.gmatch(string.lower(spaced), "%a+") do
		for _, word in cfg.Names do
			if token == word or token == word .. "s" or token == word .. "es" then
				return true
			end
		end
	end
	return false
end

--[[ Find every knockable under the map, outermost first: a Model called "Tree" claims its own leaves
	and trunk, and a Part inside it called "TreeTop" is not a second tree. Only anchored things under
	`MaxSize`; anything else is skipped silently, since it is not scenery that can grow back. ]]
function KnockableService._discover(self)
	local cfg = LobbyCarConfig.Knockables
	local map = workspace:FindFirstChild(PlotConfig.MapName)
	if not map then
		self.log:warn("No map to find bushes and trees in; nothing is knockable.")
		return
	end
	local names = {}
	local function visit(inst: Instance, loose: boolean)
		if (inst:IsA("Model") or inst:IsA("BasePart")) and matches(inst, cfg, loose) then
			local parts = {}
			if inst:IsA("BasePart") then
				table.insert(parts, inst)
			end
			for _, d in inst:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(parts, d)
				end
			end
			local size = if inst:IsA("Model") then select(2, inst:GetBoundingBox()) else (inst :: BasePart).Size
			local fixed = #parts > 0
			for _, part in parts do
				fixed = fixed and part.Anchored
			end
			if fixed and math.max(size.X, size.Y, size.Z) <= cfg.MaxSize then
				local record: Record = { name = inst.Name, entries = {}, down = false }
				for _, part in parts do
					table.insert(record.entries, {
						part = part,
						cframe = part.CFrame,
						group = part.CollisionGroup,
						transparency = part.Transparency,
					})
					part.CollisionGroup = KNOCK_GROUP
					--- The sweep is a spatial query, so the part has to answer one.
					part.CanQuery = true
					self._byPart[part] = record
					table.insert(self._parts, part)
				end
				names[inst.Name] = (names[inst.Name] or 0) + 1
			end
			return -- its insides are its own, not more knockables
		end
		--- Inside any Model but the map itself, nothing below is loose any more.
		local stillLoose = loose and not (inst:IsA("Model") and inst ~= map)
		for _, child in inst:GetChildren() do
			visit(child, stillLoose)
		end
	end
	visit(map, true)

	local list = {}
	for name, count in names do
		table.insert(list, string.format("%s x%d", name, count))
	end
	table.sort(list)
	self.log:info(string.format("%d knockable parts: %s", #self._parts, table.concat(list, ", ")))
	self._params.FilterDescendantsInstances = self._parts
end

--[[ Tear one out: unanchor it into the debris group and throw it along the car's line, up, spinning.
	Then grow it back after `Respawn`. A record already down is left alone, so a car parked in a
	hedge does not keep re-flinging it. ]]
function KnockableService._knock(self, record: Record, velocity: Vector3)
	if record.down then
		return
	end
	record.down = true
	local cfg = LobbyCarConfig.Knockables
	local debris = TrafficConfig.Collision.DebrisGroup
	local rng = self._rng
	for _, entry in record.entries do
		local part = entry.part
		if part.Parent then
			part.CollisionGroup = debris
			part.Anchored = false
		end
	end
	for _, entry in record.entries do
		local part = entry.part
		if part.Parent and not part.Anchored then
			pcall(part.SetNetworkOwner, part, nil) -- the server throws it, so everyone sees one arc
			part.AssemblyLinearVelocity = velocity * cfg.Carry
				+ Vector3.new(rng:NextNumber(-4, 4), cfg.Lift, rng:NextNumber(-4, 4))
			part.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
				* cfg.Spin
		end
	end
	--[[ Off the board after `Flight`, before it can fall far enough for Roblox to destroy it
		(`LobbyCarConfig.Knockables.Flight` has the bug this closes): faded out, then frozen where it
		is, invisible, until the restore puts it back. Anchoring is the part that matters; the fade is
		so it does not vanish mid-air. ]]
	task.delay(cfg.Flight, function()
		if not record.down then
			return
		end
		for _, entry in record.entries do
			if entry.part.Parent then
				TweenService:Create(entry.part, TweenInfo.new(cfg.FadeOut), { Transparency = 1 }):Play()
			end
		end
		task.wait(cfg.FadeOut)
		for _, entry in record.entries do
			local part = entry.part
			if part.Parent and record.down then
				part.Anchored = true
				part.AssemblyLinearVelocity = Vector3.zero
				part.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end)
	task.delay(cfg.Respawn, function()
		self:_restore(record)
	end)
end

--- Back where it stood: anchored first (so no weld drags a neighbour), placed, regrouped, faded in.
function KnockableService._restore(self, record: Record)
	local cfg = LobbyCarConfig.Knockables
	for _, entry in record.entries do
		local part = entry.part
		if part.Parent then
			part.Anchored = true
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	for _, entry in record.entries do
		local part = entry.part
		if part.Parent then
			part.CFrame = entry.cframe
			part.CollisionGroup = KNOCK_GROUP
			part.Transparency = 1
			TweenService:Create(part, TweenInfo.new(cfg.FadeIn), { Transparency = entry.transparency }):Play()
		end
	end
	record.down = false
end

--- Every lobby car going fast enough: what knockables are inside its box (`SWEEP_EVERY`)?
function KnockableService._sweep(self)
	local folder = workspace:FindFirstChild(LobbyCarConfig.FolderName)
	if not folder or #self._parts == 0 then
		return
	end
	local min = LobbyCarConfig.Knockables.MinSpeed
	for _, car in folder:GetChildren() do
		local root = car:IsA("Model") and car.PrimaryPart
		if not root then
			continue
		end
		local velocity = root.AssemblyLinearVelocity
		if velocity.Magnitude < min then
			continue
		end
		--[[ THE CAR'S PATH, NOT ITS SPOT (2026-10-15, "sometimes I still collide with them, or they
			don't fall at all"). WAS the car's own box at the moment of the sweep: at speed a small bush
			fell between two sweeps and was never knocked (the car passes through it, they do not
			collide), and a tall one met the DRIVER first, whose character still collides with
			greenery (rule 2), before the next sweep knocked it. IS: a world-aligned box from where the
			car was a sweep ago to where it will be `Lookahead` seconds on, so nothing is skipped and a
			bush is out of the way just before the car and its driver arrive. ]]
		local frame, size = car:GetBoundingBox()
		local x, y, z = frame.XVector, frame.YVector, frame.ZVector
		local extent = Vector3.new(
			math.abs(x.X) * size.X + math.abs(y.X) * size.Y + math.abs(z.X) * size.Z,
			math.abs(x.Y) * size.X + math.abs(y.Y) * size.Y + math.abs(z.Y) * size.Z,
			math.abs(x.Z) * size.X + math.abs(y.Z) * size.Y + math.abs(z.Z) * size.Z
		)
		local ahead = LobbyCarConfig.Knockables.Lookahead
		local travel = velocity * (ahead + SWEEP_EVERY)
		local centre = frame.Position + velocity * ((ahead - SWEEP_EVERY) / 2)
		local box = extent + Vector3.new(math.abs(travel.X), math.abs(travel.Y), math.abs(travel.Z)) + Vector3.one
		for _, part in workspace:GetPartBoundsInBox(CFrame.new(centre), box, self._params) do
			local record = self._byPart[part]
			if record then
				self:_knock(record, velocity)
			end
		end
	end
end

KnockableService:withLifecycle({
	init = function(self)
		self._byPart = {} :: { [BasePart]: Record }
		self._parts = {} :: { BasePart }
		self._params = OverlapParams.new()
		self._params.FilterType = Enum.RaycastFilterType.Include
		self._rng = Random.new()
	end,

	start = function(self)
		local cfg = LobbyCarConfig.Knockables
		if not (cfg and cfg.Enabled) or not self:_ensureGroup() then
			return
		end
		self:_discover()
		local at = 0
		RunService.Heartbeat:Connect(function(dt)
			at += dt
			if at >= SWEEP_EVERY then
				at = 0
				self:_sweep()
			end
		end)
	end,
})

return KnockableService
