--[[
	CarCollision  (shared)
	----------------------
	The one place the driving collision groups are registered, and the only code that assigns
	them. Two groups, one relationship:

	    PlayerGroup   the car you are driving. Collides with everything it always did — the
	                  road deck, the guardrails, the ground — plus TrafficGroup.
	    TrafficGroup  a traffic car's `Hit` volume. Collides with PlayerGroup and NOTHING else:
	                  not the road, not the obstacles, not other traffic, not any other player's
	                  car and not a character on foot.

	Why this is shared rather than living in either half. The player's car is tagged SERVER-side,
	as RaceService clones it, so every part arrives at the client already in its group instead of
	being chased through replication. The traffic shells are tagged CLIENT-side, because they
	only ever exist there (TrafficController). Both sides need the same two names and the same
	matrix, so both call `ensure` and neither owns it.

	`ensure` is idempotent and split down that same line, because the two halves have different
	privileges. REGISTERING a group and editing the collidable matrix is the server's alone;
	ASSIGNING one to a part is allowed anywhere. So the server registers at startup and asserts
	the matrix every run — a group can survive in a saved place file with a stale, collide-with-
	everything mask, and "it exists" is not "it's wired up" — while the client only checks that
	both names replicated in and then tags its own parts. A client that tried to register would
	throw, and a race that swallowed that error would quietly hand back non-solid traffic.

	See TrafficConfig.Collision for the design notes, in particular the one that bites: a spatial
	query carries a collision group too, so anything that needs to SEE traffic must query as
	PlayerGroup (`queryGroup` below).
]]

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)

local CarCollision = {}

-- Latched only on SUCCESS. The groups are a property of the world rather than of a race, so
-- there's no reason to re-walk the registry once it's right — but a client that asked before the
-- server's groups replicated has to be able to ask again, so a failure never latches.
local ready = false
local warned = false

--[[ Make sure the groups exist and are wired to each other. Returns false when collision is
	switched off in config, or when the groups aren't there to be used — either way callers leave
	their parts alone and traffic stays what it was before this existed: a pure query volume you
	drive straight through. ]]
function CarCollision.ensure(): boolean
	local cfg = TrafficConfig.Collision
	if not cfg.Enabled then
		return false
	end
	if ready then
		return true
	end

	if not RunService:IsServer() then
		-- Client. It may tag parts but not register groups or touch the matrix, so all there is
		-- to do is confirm the server's registration replicated in.
		ready = PhysicsService:IsCollisionGroupRegistered(cfg.PlayerGroup)
			and PhysicsService:IsCollisionGroupRegistered(cfg.TrafficGroup)
		if not ready and not warned then
			warned = true
			warn("[CarCollision] driving collision groups haven't replicated; traffic stays non-solid.")
		end
		return ready
	end

	local ok, err = pcall(function()
		for _, name in { cfg.PlayerGroup, cfg.TrafficGroup, cfg.DebrisGroup } do
			if not PhysicsService:IsCollisionGroupRegistered(name) then
				PhysicsService:RegisterCollisionGroup(name)
			end
		end
		local trial = cfg.ArcadeTrial
		if trial and not PhysicsService:IsCollisionGroupRegistered(trial.Group) then
			PhysicsService:RegisterCollisionGroup(trial.Group)
		end
		-- Asserted every run, not just on first registration: a group saved into the place file
		-- comes back collidable with everything, and existing is not the same as being wired up.
		-- Live traffic is inert to the whole world — itself included, and any group added later...
		-- ...but ONLY the groups that exist at this moment, and this runs once. A group registered
		-- after this sweep has to switch itself off against TrafficGroup; `Modules/CrowdCollision`
		-- is the one that does, and its header has the trap in full. Read that before adding a
		-- third file that registers a group.
		for _, group in PhysicsService:GetRegisteredCollisionGroups() do
			PhysicsService:CollisionGroupSetCollidable(cfg.TrafficGroup, group.name, false)
		end
		-- ...except the car you're driving.
		PhysicsService:CollisionGroupSetCollidable(cfg.TrafficGroup, cfg.PlayerGroup, true)
		--[[ === A CAR MUST STILL MEET ITSELF — 2026-10-15 ===
			WAS (2026-10-14, "disable collisions between lobby cars"): `PlayerGroup` x `PlayerGroup`
			switched off. That also switched off a car's WHEELS against its own BODY (they are separate
			assemblies in the same group), and on these rigs that contact is the suspension's hard stop:
			with it gone a hard landing or a drift drove the wheels up inside the body and stood the car
			on its nose (the owner: "the wheels are like inside the car"; it was what "car suspensions
			are completely broken" was, all along). IS: `PlayerGroup` collides with itself again, as it
			always had, and lobby cars stop meeting EACH OTHER a different way: each one is given a
			`LobbyCar<n>` group of its own (`applyLobbyCar`), which meets itself and none of the others. ]]
		PhysicsService:CollisionGroupSetCollidable(cfg.PlayerGroup, cfg.PlayerGroup, true)
		for i = 1, CarCollision.LobbySlots do
			local mine = CarCollision.lobbyGroup(i)
			if not PhysicsService:IsCollisionGroupRegistered(mine) then
				PhysicsService:RegisterCollisionGroup(mine)
			end
		end
		for i = 1, CarCollision.LobbySlots do
			local mine = CarCollision.lobbyGroup(i)
			for j = 1, CarCollision.LobbySlots do
				PhysicsService:CollisionGroupSetCollidable(mine, CarCollision.lobbyGroup(j), i == j)
			end
			--- Everything else exactly as a car in `PlayerGroup` meets it.
			PhysicsService:CollisionGroupSetCollidable(mine, "Default", true)
			PhysicsService:CollisionGroupSetCollidable(mine, cfg.PlayerGroup, false)
			PhysicsService:CollisionGroupSetCollidable(mine, cfg.TrafficGroup, false)
			PhysicsService:CollisionGroupSetCollidable(mine, cfg.DebrisGroup, false)
		end

		-- Debris is simulated, so it needs the opposite of that: something to land on. Spelled out
		-- rather than left to the register-time defaults, for the same stale-mask reason as above.
		PhysicsService:CollisionGroupSetCollidable(cfg.DebrisGroup, "Default", true)
		-- Knocked traffic keeps road/debris physics without repeatedly pinning the driver.
		PhysicsService:CollisionGroupSetCollidable(cfg.DebrisGroup, cfg.PlayerGroup, false)
		PhysicsService:CollisionGroupSetCollidable(cfg.DebrisGroup, cfg.DebrisGroup, true)
		PhysicsService:CollisionGroupSetCollidable(cfg.DebrisGroup, cfg.TrafficGroup, false)
		if trial then
			for _, group in PhysicsService:GetRegisteredCollisionGroups() do
				PhysicsService:CollisionGroupSetCollidable(trial.Group, group.name, false)
			end
			PhysicsService:CollisionGroupSetCollidable(trial.Group, "Default", true)
			PhysicsService:CollisionGroupSetCollidable(trial.Group, cfg.PlayerGroup, true)
		end
	end)

	ready = ok
	if not ok and not warned then
		warned = true
		warn(string.format("[CarCollision] collision groups unavailable (%s); traffic stays non-solid.", tostring(err)))
	end
	return ok
end

--[[ Lobby cars' own groups (header note in `ensure`, "A CAR MUST STILL MEET ITSELF"). Eight is the
	plots (six) with room to spare; a ninth car at once shares a group and can touch the car it shares
	with, which is the old behaviour, not a break. ]]
CarCollision.LobbySlots = 8
function CarCollision.lobbyGroup(slot: number): string
	return "LobbyCar" .. slot
end

--[[ Put a lobby car in a `LobbyCar<n>` group no other lobby car in `folder` is using, so its wheels
	still meet its body but it passes through every other lobby car. The slot is kept on the car as an
	attribute so the next car can see it is taken. Falls back to `applyCar` if the groups are not up. ]]
function CarCollision.applyLobbyCar(car: Model, folder: Instance?)
	if not CarCollision.ensure() then
		return
	end
	local used = {}
	for _, other in (if folder then folder:GetChildren() else {}) do
		if other ~= car then
			local slot = other:GetAttribute("LobbyCarGroup")
			if type(slot) == "number" then
				used[slot] = true
			end
		end
	end
	local slot = 1
	while used[slot] and slot < CarCollision.LobbySlots do
		slot += 1
	end
	car:SetAttribute("LobbyCarGroup", slot)
	local group = CarCollision.lobbyGroup(slot)
	for _, inst in car:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.CollisionGroup = group
		end
	end
end

-- Put a whole car in `PlayerGroup`. Called on the server the moment RaceService clones one, so
-- the group replicates as part of the car rather than being applied to parts as they trickle in.
-- Safe on a car that's already tagged; re-tagging is a no-op.
function CarCollision.applyCar(car: Model)
	if not CarCollision.ensure() then
		return
	end
	local group = TrafficConfig.Collision.PlayerGroup
	for _, inst in car:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.CollisionGroup = group
		end
	end
end

-- Make one traffic shell's `Hit` volume solid. The published template is non-colliding (it's a
-- query volume first, and nothing on the server has any use for a solid one), so this is what
-- promotes a clone — once per shell, at build time, and it survives pooling.
function CarCollision.applyTraffic(hit: BasePart)
	if not CarCollision.ensure() then
		return
	end
	hit.CollisionGroup = TrafficConfig.Collision.TrafficGroup
	hit.CanCollide = not TrafficConfig.Collision.ArcadeContact
end

-- Move one traffic volume between the anchored group and the simulated one. `physical` is the only
-- thing that decides whether it can touch the road, so this has to be called in step with
-- Anchored — a physical car left in the anchored group falls through the world.
function CarCollision.setTrafficPhysical(hit: BasePart, physical: boolean)
	if not CarCollision.ensure() then
		return
	end
	local cfg = TrafficConfig.Collision
	hit.CollisionGroup = if physical then cfg.DebrisGroup else cfg.TrafficGroup
	hit.CanCollide = physical or not cfg.ArcadeContact -- Live traffic uses contact queries; debris keeps road physics.
end
-- A knocked, unanchored shell may push against the driver briefly during the arcade trial.
-- Live anchored traffic NEVER uses this group.
function CarCollision.setTrafficImpact(hit: BasePart)
 CarCollision.setTrafficPhysical(hit, true)
 local cfg = TrafficConfig.Collision.ArcadeTrial
 if cfg and cfg.Enabled and CarCollision.ensure() then
  hit.CollisionGroup = cfg.Group
 end
end

-- Spent traffic is visual-only: it cannot pin the driver, block another car, or catch a rail.
function CarCollision.setTrafficGhost(model: Model, hit: BasePart)
 local previous = {}
 for _, part in model:GetDescendants() do
  if part:IsA("BasePart") then
   previous[part] = { part.CanCollide, part.CanTouch, part.CanQuery }
   part.CanCollide = false
   part.CanTouch = false
   part.CanQuery = false
  end
 end
 hit.CanCollide, hit.CanTouch, hit.CanQuery = false, false, false
 return previous
end

return CarCollision
