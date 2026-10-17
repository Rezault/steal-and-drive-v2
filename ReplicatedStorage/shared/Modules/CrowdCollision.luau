--[[
	CrowdCollision  (shared)
	------------------------
	Two collision groups and one rule: A PERSON NEVER PUSHES A PERSON.

	    CharacterGroup   every player's character, tagged as it spawns.
	    NpcGroup         every rig the server walks around on its own — today that is
	                     CustomerService's showroom visitors, and nothing else.

	    NPC x NPC              OFF
	    NPC x Character        OFF
	    Character x Character  OFF (since 2026-10-14; see `ensure`)
	    everything else        ON, exactly as it was before this existed.

	WHY THE PLAYERS NEED A GROUP AT ALL, when it was only the NPCs that were asked to stop colliding.
	Collidability is a property of a PAIR of groups and never of one part, and a character sits in
	"Default" — which is also the showroom floor, the podiums, the plaza and the whole map. Switching
	NPC-vs-Default off would take the floor with it and drop the crowd through the world on the first
	step. So the players come out of Default into a group of their own, and the pair switched off is
	NPC-vs-Character. Both groups still collide with Default, so both still stand on the ground.

	WHY THE MATRIX IS SPELLED OUT IN FULL rather than left to the register-time default of
	collide-with-everything: the same reason `CarCollision` asserts its own every run. A group saved
	into the place file comes back with whatever mask it was last given, and "the group exists" is not
	"the group is wired up".

	=== THE ORDERING TRAP, AND WHY THIS FILE HANDLES IT BOTH WAYS =============================

	`CarCollision.ensure` wires traffic by SWEEPING every group registered at the moment it runs and
	switching all of them off against `TrafficGroup`. Two consequences:

	  • If this file registers first, that sweep covers our two groups for free — traffic ignores
	    people, which is what a character in Default already got.
	  • If it registers second, the sweep has already happened and latched, and our groups would be
	    left colliding with traffic. A player seated in a car would then be hit in the chest by every
	    traffic shell their own car meets.

	Nothing orders the two services that call these, so the driving pairs are asserted at the bottom
	of `ensure` as well, guarded on the driving groups actually being registered (they are not, when
	`TrafficConfig.Collision.Enabled` is off). Whichever file runs second writes the same values the
	first one did, so the order genuinely does not matter.

	=== WHAT THIS IS NOT =====================================================================

	It is not a way to hide a rig from a spatial query. Default still collides with both groups, so a
	query left in "Default" — which is every query in this codebase that is not deliberately in
	`PlayerGroup` — sees customers and characters exactly as it did before. See the note on
	`TrafficConfig.Collision` for the one case where that is NOT true, and why it bites.
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)

local CrowdCollision = {}

CrowdCollision.CharacterGroup = "Character"
CrowdCollision.NpcGroup = "NPC"

-- Latched only on SUCCESS, for the same reason CarCollision's is: the groups are a property of the
-- world rather than of a plot, so there is no reason to re-walk the registry once it is right — but a
-- caller that asked before it worked has to be able to ask again.
local ready = false
local warned = false
local bound = false

--[[ Make sure the two groups exist and the matrix says what this file's header says.

	Idempotent, and split down the same line `CarCollision.ensure` is: REGISTERING a group and editing
	the matrix belong to the server alone, while ASSIGNING one to a part is allowed anywhere. The
	client half is here only so client code can ask whether the names have replicated before building
	a query in one; nothing on the client assigns these. ]]
function CrowdCollision.ensure(): boolean
	if ready then
		return true
	end

	if not RunService:IsServer() then
		ready = PhysicsService:IsCollisionGroupRegistered(CrowdCollision.CharacterGroup)
			and PhysicsService:IsCollisionGroupRegistered(CrowdCollision.NpcGroup)
		return ready
	end

	local character, npc = CrowdCollision.CharacterGroup, CrowdCollision.NpcGroup

	local ok, err = pcall(function()
		for _, name in { character, npc } do
			if not PhysicsService:IsCollisionGroupRegistered(name) then
				PhysicsService:RegisterCollisionGroup(name)
			end
		end

		-- The rule, and the only two pairs in here that are false. Flip these back to true and the
		-- crowd shoulder-barges its way around the showroom again, which is what it used to do.
		PhysicsService:CollisionGroupSetCollidable(npc, npc, false)
		PhysicsService:CollisionGroupSetCollidable(npc, character, false)

		-- The world. Both groups keep it, or neither group could stand up.
		PhysicsService:CollisionGroupSetCollidable(npc, "Default", true)
		PhysicsService:CollisionGroupSetCollidable(character, "Default", true)
		--[[ PLAYERS PASS THROUGH PLAYERS (2026-10-14, the owner: "disable collisions between players").
			WAS true, "only the NPCs were asked to stop": players body-blocked each other in doorways,
			on the pads and on a crowded lot, and could shove each other around a plot. Flip back to
			true for the old shoving. ]]
		PhysicsService:CollisionGroupSetCollidable(character, character, false)

		--[[ The driving groups, when they are there — see the ordering trap in the header. Each pair
			is the value a character in "Default" already had, so a person on foot meets a car, a
			wreck and a traffic shell exactly as they did before: traffic is inert to everything but
			the car you are driving, and both of the other two are ordinary solid things. ]]
		local car = TrafficConfig.Collision
		for _, group in { character, npc } do
			if PhysicsService:IsCollisionGroupRegistered(car.TrafficGroup) then
				PhysicsService:CollisionGroupSetCollidable(car.TrafficGroup, group, false)
			end
			if PhysicsService:IsCollisionGroupRegistered(car.PlayerGroup) then
				PhysicsService:CollisionGroupSetCollidable(car.PlayerGroup, group, true)
			end
			if PhysicsService:IsCollisionGroupRegistered(car.DebrisGroup) then
				PhysicsService:CollisionGroupSetCollidable(car.DebrisGroup, group, true)
			end
		end
	end)

	ready = ok
	if not ok and not warned then
		warned = true
		warn(string.format("[CrowdCollision] groups unavailable (%s); the crowd stays solid.", tostring(err)))
	end
	return ok
end

-- Every BasePart under `model`, including the `Handle` inside each accessory. Assigning a group is
-- cheap and re-assigning one is a no-op, so this is safe to run over a rig twice.
local function tag(model: Model, group: string)
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.CollisionGroup = group
		end
	end
end

--[[ Put one crowd rig in the NPC group.

	Called on the TEMPLATE rather than on each spawned customer (`CustomerService._prepareRig`), which
	is both cheaper and safer: `CollisionGroup` is an ordinary property, so a clone arrives already in
	the group instead of spending its first frames solid while a loop walks it. ]]
function CrowdCollision.applyNpc(model: Model)
	if not CrowdCollision.ensure() then
		return
	end
	tag(model, CrowdCollision.NpcGroup)
end

--[[ Put one player's character in the Character group, and keep it there.

	THE DESCENDANT WATCH IS NOT BELT-AND-BRACES. `CharacterAdded` fires with the body assembled, but a
	character keeps growing afterwards: appearance can finish loading late, and every tool a player
	equips parents a fresh `Handle` in. A part that arrives after the walk is a part still in Default,
	which is a player an NPC can walk into — the whole bug, back on one limb.

	Returns the connection so the caller can drop it when the character is replaced. It does not need
	disconnecting on Destroy: destroying an instance disconnects everything connected to it. ]]
function CrowdCollision.applyCharacter(character: Model): RBXScriptConnection?
	if not CrowdCollision.ensure() then
		return nil
	end
	local group = CrowdCollision.CharacterGroup
	tag(character, group)
	return character.DescendantAdded:Connect(function(inst)
		if inst:IsA("BasePart") then
			inst.CollisionGroup = group
		end
	end)
end

--[[ Tag every character in the server, now and for the rest of the session.

	PROCESS-LIFETIME ON PURPOSE, which is why it is here and not on a service's trove: a collision
	group is a fact about the world, there is no state to leak, and a teardown that untagged characters
	would leave them in Default with a live crowd still walking about. Idempotent, so more than one
	caller may switch it on.

	Called from `CustomerService.init`, because customers are the only reason players need a group of
	their own. A second NPC system would call it too and get the second caller's no-op. ]]
function CrowdCollision.bindPlayers()
	if bound or not RunService:IsServer() then
		return
	end
	if not CrowdCollision.ensure() then
		return
	end
	bound = true

	-- One live DescendantAdded connection per player, replaced on each respawn so a session's worth of
	-- dead characters does not leave a session's worth of connections behind.
	local watching: { [Player]: RBXScriptConnection } = {}

	local function onCharacter(player: Player, character: Model)
		local previous = watching[player]
		if previous then
			previous:Disconnect()
		end
		watching[player] = CrowdCollision.applyCharacter(character)
	end

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		-- `CharacterAutoLoads` is off in this place and PlotService loads the first character in its
		-- `start`, so this normally finds nothing. It is what covers a hot reload, where a player can
		-- already be standing in their own showroom by the time this runs.
		if player.Character then
			onCharacter(player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local conn = watching[player]
		if conn then
			conn:Disconnect()
		end
		watching[player] = nil
	end)
end

return CrowdCollision
