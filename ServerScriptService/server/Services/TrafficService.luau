--[[
	TrafficService  (server — traffic body PROVIDER + clip pricing)
	--------------------------------------------------------------
	Traffic is client-sided for the same reason the road and the obstacles are: driving is
	solo, so each driver owns their own copy of the world and nothing about it needs to
	replicate (see RoadController). This service therefore runs no traffic. It does two
	things:

	  1. Publishes a stripped VISUAL SHELL of each car in `TrafficConfig.AllBodies` into
	     `ReplicatedStorage.TrafficCars`, so every client has something cheap to clone. This
	     mirrors RoadService publishing its one road tile. Each shell doubles as the DRESS a steal
	     puts on the player's car — see `_stampMountFrames` for the five frames that makes possible.
	  2. Prices a clip. The client owns the car and the traffic, so it's the only side that
	     can see the contact; it says "I clipped one" and the server decides the damage from
	     TrafficConfig and hands it to ObstacleService, which owns HP.

	Why a shell and not a car. `Workspace.CarSystem.TestCar_FirstTestCar` is a full CarBones
	rig — 50 parts of chassis, suspension, seats, constraints and eleven scripts, every one
	of which would start running the moment a copy hit Workspace. A dozen of those is not a
	traffic system, it's a physics bomb. The shell keeps the 19 visible meshes, welds them to
	one anchored root, and throws the rest away: no scripts, no seats, no simulation, one
	CFrame write per car per frame. See `_buildShell`.

	The root's CFrame is the car's WHEELS-ON-DECK frame — the pivot dropped to the lowest
	point of the bodywork — so the client places a car with
	`root.CFrame = CFrame.lookAt(deckPoint, deckPoint + roadForward)` and nothing has to know
	this body's ride height. A differently-proportioned redress gets that for free.

	On trust: see the `ClipCooldown` note in TrafficConfig. The server can rate-limit a clip
	but cannot identify which car was clipped, because traffic (unlike obstacles) isn't
	derivable from a seed. That's the same accepted, under-report-only gap ObstacleService
	documents, and it stays accepted exactly as long as driving is solo.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local RaceConfig = require(ReplicatedStorage.shared.Configs.RaceConfig)
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local CarCollision = require(ReplicatedStorage.shared.Modules.CarCollision)
local CarDoorRig = require(ReplicatedStorage.shared.Modules.CarDoorRig)
local CarRoster = require(ReplicatedStorage.shared.Modules.CarRoster)

local TrafficService = Shard.new("TrafficService"):withDependencies({ "ObstacleService" })

TrafficService:withRemoteEvents({
	{
		-- client -> server: "I clipped a traffic car, this hard". The severity is the one thing
		-- the server can't derive — only the driver's client holds both cars' velocities — and
		-- it's still not the client's to name an AMOUNT: it sends 0..1 and the server prices it.
		TrafficHit = function(player: Player, severity: unknown)
			TrafficService:_onTrafficHit(player, severity)
		end,
	},
})

-- The four suspension corners, in the order their names are suffixed on the chassis.
local CORNERS = { "FL", "FR", "RL", "RR" }
-- Prefix of the chassis models that carry a physics wheel, and the wheel part's own name.
local SUSPENSION_PREFIX = "Suspension"
local WHEEL_NAME = "Wheel"
-- The chassis part every non-wheel visual mesh is welded to.
local MOUNT_NAME = "RedressMount"

-- Which visual parts of a source car make up its body. Everything under `Body/` that you can
-- actually see: on the Lambo redress that's 52 meshes (36 shell + 16 wheel), and deliberately
-- NOT the `HitBox` (the chassis's invisible mid-height hull — handoff doc §5) or the emptied-out
-- reference panels left behind by the redress. Structure-agnostic on purpose: it walks
-- descendants, so a body that nests its doors, wheels and light housings works unchanged.
function TrafficService._visualParts(self, source: Model): { BasePart }
	local parts = {}
	local body = source:FindFirstChild("Body")
	if not body then
		return parts
	end
	for _, inst in body:GetDescendants() do
		if inst:IsA("BasePart") and inst.Name ~= "HitBox" and inst.Transparency < 1 then
			table.insert(parts, inst)
		end
	end
	return parts
end

--[[ Bounds of a set of parts in `frame`'s space, swept corner by corner.

	Not `Model:GetBoundingBox()`, which would take in the chassis, the seats and the invisible
	hull — we want the box around what a player can SEE, because that's what has to sit on the
	deck and what the clip volume has to match. (The same distinction bit the impact smoke
	twice; see ObstacleConfig.HitSmoke.) ]]
function TrafficService._localBounds(self, parts: { BasePart }, frame: CFrame): (Vector3, Vector3)
	local min, max
	for _, part in parts do
		local lc = frame:ToObjectSpace(part.CFrame)
		local half = part.Size * 0.5
		for i = -1, 1, 2 do
			for j = -1, 1, 2 do
				for k = -1, 1, 2 do
					local p = lc * Vector3.new(half.X * i, half.Y * j, half.Z * k)
					min = if min
						then Vector3.new(math.min(min.X, p.X), math.min(min.Y, p.Y), math.min(min.Z, p.Z))
						else p
					max = if max
						then Vector3.new(math.max(max.X, p.X), math.max(max.Y, p.Y), math.max(max.Z, p.Z))
						else p
				end
			end
		end
	end
	return min or Vector3.zero, max or Vector3.zero
end

--[[ WHICH CHASSIS PART A VISUAL MESH HANGS OFF, as the tag `CarBody.swapMeshes` reads back to graft
	this body onto the car a player is driving: `"Body"` for the bodywork, or a corner (`"FL"`…) for a
	wheel visual.

	Read off the mesh's OWN WeldConstraint rather than from its name or its parent folder, because the
	weld is the thing that is actually true — a wheel visual is a wheel visual because it is welded to
	`SuspensionFL.Wheel` and therefore spins and steers, not because it happens to live in a model
	called `FL` or to be named `wheel_FL`. Both of those conventions hold across the 33-car pack and
	neither is guaranteed by anything.

	CHAINS ARE FOLLOWED, up to a few hops, because a redress may hang a mesh off another mesh rather
	than off the chassis directly — the Lambo's door skins are welded to their door root, which is on a
	hinge rather than a weld. Anything that can't be resolved falls back to the bodywork mount, which
	for a door means it comes across welded shut instead of rigged; a body whose doors have to keep
	working needs its rig transferred too, which is a separate job (handoff doc §4).

	The hop limit is a cycle guard as much as a depth limit: two parts welded to each other in both
	directions is a legal rig and would otherwise loop forever. ]]
function TrafficService._mountTag(self, part: BasePart): string
	local current: BasePart = part
	local seen = { [part] = true }
	for _ = 1, 4 do
		local weld
		for _, child in current:GetChildren() do
			if child:IsA("WeldConstraint") and child.Part0 and child.Part1 then
				weld = child
				break
			end
		end
		if not weld then
			break
		end
		local other = if weld.Part1 == current then weld.Part0 else weld.Part1
		if not other or seen[other] then
			break
		end
		seen[other] = true

		if other.Name == MOUNT_NAME then
			return "Body"
		end
		local holder = other.Parent
		if other.Name == WHEEL_NAME and holder and string.find(holder.Name, SUSPENSION_PREFIX, 1, true) == 1 then
			return string.sub(holder.Name, #SUSPENSION_PREFIX + 1)
		end
		current = other
	end
	return "Body"
end

--[[ Stamp the shell with the frames its meshes were authored against, so a client can put this body
	on a car that has none of the source's geometry to measure.

	THIS IS THE WHOLE REASON A STEAL CAN SWAP BODIES. A shell is a flat bag of meshes welded to one
	root; the car a player drives hangs its bodywork off `Chassis.RedressMount` and its wheel visuals
	off the four `Suspension*/Wheel` parts. Those five frames are what turn one into the other:
	`CarBody.swapMeshes` reads a mesh's offset from the frame recorded here and re-applies it to the
	matching part on the target chassis. Every car in the pack is the same CarBones chassis, so that
	offset means exactly the same thing on both ends (verified: identical hull size, wheelbase and
	mount-relative wheel and seat offsets across all 33).

	WHY NOT MEASURE THE DECK INSTEAD. The obvious alternative — align both cars' wheels-on-deck frames
	— is off by the target's live SUSPENSION TRAVEL at the moment of the swap, because the player's car
	is a simulated rig whose body sits wherever the springs currently hold it. The mount frames are
	rigid parts of the chassis, so they carry no such error. It also means a wheel visual can be welded
	to the live physics wheel at whatever steering angle and roll phase it is currently at, and land
	correctly, because the offset is measured against a source wheel in the same rest pose.

	Recorded ROOT-RELATIVE, not in world space, so they survive the shell being cloned and driven down
	a road: the meshes are welded to `Root`, so `Root.CFrame * MountFrame` is always where the source's
	`RedressMount` would be if this shell were that car.

	A source with no `RedressMount` gets no attributes and simply can't be stolen INTO — it still
	drives as traffic. That is a real state (`CarBones` itself has no `Body/`), so it warns rather than
	failing the publish. ]]
function TrafficService._stampMountFrames(self, shell: Model, source: Model, rootCF: CFrame): boolean
	local chassis = source:FindFirstChild("Chassis")
	local mount = chassis and chassis:FindFirstChild(MOUNT_NAME)
	if not (mount and mount:IsA("BasePart")) then
		self.log:warn(string.format(
			"'%s' has no Chassis.%s, so a steal can't redress into it; it will still drive as traffic.",
			source.Name,
			MOUNT_NAME
		))
		return false
	end

	shell:SetAttribute("MountFrame", rootCF:ToObjectSpace(mount.CFrame))
	for _, corner in CORNERS do
		local suspension = chassis:FindFirstChild(SUSPENSION_PREFIX .. corner)
		local wheel = suspension and suspension:FindFirstChild(WHEEL_NAME)
		if wheel and wheel:IsA("BasePart") then
			shell:SetAttribute("WheelFrame" .. corner, rootCF:ToObjectSpace(wheel.CFrame))
		end
	end
	return true
end

--[[ Work out this body's driver door and driver seat ONCE, here, so the client never has to.

	THE CLIENT CANNOT DERIVE EITHER OF THESE. `CarDoorRig.plan` finds a door by measuring `Body/`
	panels against `Chassis.RedressMount` and the seat they straddle — and a traffic shell has none
	of those: it is a flat bag of welded meshes with an invisible `Root` and `Hit`, by design. The
	source car sitting in `Workspace.CarSystem` has all three, and this function runs with it in
	hand, so the answer is stamped rather than reconstructed. Same reason and the same shape as
	`_stampMountFrames`.

	WHAT THE CLIENT DOES WITH IT (`Modules/ShellDoors`, `StealController._mount`): swings the door of
	the car you are landing on, and puts the driver you throw out in the seat. Both beats are half of
	the landing animation, and both are silently absent without this.

	ROOT-RELATIVE, for the same reason the mount frames are: the shell is cloned, pooled and driven
	down a road, so `Root.CFrame * DoorHinge` is always where this body's hinge line is right now.

	ONLY THE DRIVER'S SIDE (`FL`). `CarDoorRig` wires only that door on a real car — the player
	leaves through it, and a passenger door flapping open on its own reads as damage — and the same
	fiction holds here: the person being thrown out is the driver.

	A BODY WITH NO SEPARABLE PANEL IS A NORMAL OUTCOME, not an error. Three in the pack genuinely
	have none (`docs/CarDoors_RigPlan.md` §6), and the beat degrades to a driver coming out through a
	shut door rather than to a broken steal — so this logs what it found and moves on. ]]
function TrafficService._doorPlan(self, source: Model, rootCF: CFrame)
	local plan, why = CarDoorRig.plan(source)
	local side = plan and plan.sides.FL
	if not side then
		self.log:info(string.format(
			"'%s' publishes without a door plan (%s); a steal into it opens no door.",
			source.Name,
			tostring(why or "no driver-side panel")
		))
		return nil
	end

	local panels = { [side.panel] = true }
	for _, extra in side.extras do
		panels[extra] = true
	end
	return {
		panels = panels,
		-- `side.hinge` is stated in the car's own frame, which `plan.frame` (the RedressMount) is.
		hinge = rootCF:ToObjectSpace(plan.frame * side.hinge),
		seat = rootCF:ToObjectSpace(side.seat.CFrame),
	}
end

--[[ Turn a rigged car into a traffic shell.

	Shape of the result:
	    Shell (Model, PrimaryPart = Root)
	      Root  — anchored, invisible, query-blind. THE car's frame: positioned at the pivot
	              dropped to the bottom of the bodywork, so its CFrame is where the wheels
	              meet the deck. Everything else is welded to it, which makes the whole car one
	              anchored assembly that moves with a single CFrame write.
	      Hit   — the one query-visible part, sized to the visible bodywork. This is what the
	              driver's clip poll finds, what the client makes solid against the driver's car
	              (CarCollision), and the volume the steal flow lands on.
	      ...   — the visual meshes, massless, non-colliding, query-blind, each carrying a
	              `DressMount` attribute naming the chassis part it belongs on (see `_mountTag`),
	              and — on the driver's door panel and whatever rides on it — a `DoorPanel` flag
	              (see `_doorPlan`).

	Plus, on the model: `BodyLength`/`BodyWidth`, the five mount frames (`_stampMountFrames`), and
	`DoorHinge`/`DriverSeat` (`_doorPlan`). Everything the client needs to drive, dress, open and
	populate this body without ever seeing the rig it came from.

	Nothing here is ever simulated: the root is anchored and the rest is rigidly welded to it,
	so gravity, suspension and contacts all sit this out entirely.

	IT IS ALSO THE DRESS A STEAL PUTS ON THE PLAYER'S CAR. `CarBody.swapMeshes` clones these meshes
	straight off the live shell the player landed on, which is why the `DressMount` tags and the mount
	frames (`_stampMountFrames`) are recorded here rather than derived on the client: the client has the
	shell and no access to the source rig's geometry. Nothing extra is published for it — the same 20-odd
	meshes serve as both the traffic car you see and the body you drive away in. ]]
function TrafficService._buildShell(self, source: Model): Model?
	local visuals = self:_visualParts(source)
	if #visuals == 0 then
		self.log:warn(string.format("'%s' has no visible Body parts; skipping it.", source.Name))
		return nil
	end

	local pivot = source:GetPivot()
	local min, max = self:_localBounds(visuals, pivot)
	local size = max - min
	local centre = (min + max) * 0.5
	-- The pivot dropped to ground level. Keeping the pivot's X/Z (rather than the box centre's)
	-- means a shell sits in a lane exactly where the real car would, and its nose faces the
	-- root's LookVector — same convention RaceService spawns the player's car on.
	local rootCF = pivot * CFrame.new(0, min.Y, 0)
	-- Surveyed before anything is cloned, because the discriminator needs the SOURCE's chassis and
	-- the clone loop below needs to know which meshes it is copying.
	local door = self:_doorPlan(source, rootCF)

	local shell = Instance.new("Model")
	shell.Name = source.Name

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one * 0.2
	root.CFrame = rootCF
	root.Anchored = true
	root.Transparency = 1
	root.CastShadow = false
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = shell
	shell.PrimaryPart = root

	local hit = Instance.new("Part")
	hit.Name = "Hit"
	hit.Size = size
	hit.CFrame = rootCF * CFrame.new(centre.X, centre.Y - min.Y, centre.Z)
	hit.Anchored = false
	--[[ NOT massless, and this part alone carries the shell's mass. Every visual mesh is massless and
		the Root is a 0.2-stud cube, so this box IS the car as far as physics is concerned — which is
		what makes it possible to unanchor a shell on impact and have it behave like a car rather than
		like a leaf (TrafficConfig.Knock). While the shell is anchored — which is all of its life until
		something hits it — mass costs nothing, because an anchored assembly is never simulated.

		Explicit physical properties rather than the material default so the mass the impulse is
		measured against is a number a designer chose, and so a redress can't quietly change how hard
		traffic hits by shipping a different material. ]]
	hit.Massless = false
	hit.CustomPhysicalProperties = PhysicalProperties.new(
		TrafficConfig.Knock.Density,
		TrafficConfig.Knock.Friction,
		TrafficConfig.Knock.Elasticity
	)
	hit.Transparency = 1
	hit.CastShadow = false
	-- Published non-colliding and ungrouped: the server has no traffic to simulate, so a solid
	-- shell here would only be a solid shell in ReplicatedStorage. The client promotes its own
	-- clones as it builds them (CarCollision.applyTraffic), which is where the collision group
	-- that pairs a traffic car with the driver's car — and nothing else — gets attached.
	hit.CanCollide = false
	hit.CanTouch = false -- the client polls, same as it does for obstacles
	hit.CanQuery = true
	hit.Parent = shell
	local hitWeld = Instance.new("WeldConstraint")
	hitWeld.Part0, hitWeld.Part1 = root, hit
	hitWeld.Parent = hit

	--- A limited event car keeps its authored effects (the Rocket Edition's thrusters), which then ride
	--- along as its traffic look and as the dress a steal or a start car puts on.
	local keepFx = WorldConfig.EventBodies[source.Name] ~= nil
	for _, part in visuals do
		local clone = part:Clone()
		-- Drop the rig's joints (each mesh carries the WeldConstraint that tied it to the
		-- chassis) and anything else riding along; keep only what makes it render. A
		-- `SurfaceGui` counts: the number plate's text is a TextLabel on `plate_face`, so
		-- dropping it publishes every traffic car with a blank white plate.
		for _, child in clone:GetChildren() do
			local render = child:IsA("SpecialMesh")
				or child:IsA("Decal")
				or child:IsA("Texture")
				or child:IsA("SurfaceAppearance")
				or child:IsA("SurfaceGui")
				or (keepFx and (child:IsA("Attachment") or child:IsA("ParticleEmitter") or child:IsA("Beam")
					or child:IsA("Trail") or child:IsA("Light") or child:IsA("Fire")))
			if not render then
				child:Destroy()
			end
		end
		clone.Anchored = false
		clone.Massless = true
		clone.CanCollide = false
		clone.CanQuery = false
		clone.CanTouch = false
		--[[ `CastShadows` IS APPLIED CLIENT-SIDE (TrafficController._buildRecord), not here, and that
			moved once this shell became the dress a steal puts on the player's car. Stripping shadows
			in the published template made `TrafficConfig.CastShadows = false` — the config's own
			first-choice perf lever — also silently stop every STOLEN car casting a shadow, for the rest
			of the run, which reads as the car floating. The published body keeps whatever its artist
			authored; the traffic clone is what gets stripped. ]]
		-- Which chassis part this mesh goes back on when the body is grafted onto a real car. Read off
		-- the SOURCE part, before its weld is dropped above — the clone no longer has one.
		clone:SetAttribute("DressMount", self:_mountTag(part))
		-- Marks the panel (and its window, and whatever else rides on it) as the one group of meshes
		-- `ShellDoors` may turn. Stamped per mesh rather than as a name list on the model, because a
		-- redress renames nothing and the client would have to re-run the survey to read one.
		if door and door.panels[part] then
			clone:SetAttribute("DoorPanel", true)
		end
		clone.Parent = shell
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = root, clone
		weld.Parent = clone
	end

	-- Read by the client so it never has to re-measure a body it didn't build.
	shell:SetAttribute("BodyLength", size.Z)
	shell:SetAttribute("BodyWidth", size.X)
	if door then
		shell:SetAttribute("DoorHinge", door.hinge)
		shell:SetAttribute("DriverSeat", door.seat)
	end
	self:_stampMountFrames(shell, source, rootCF)
	return shell
end

-- The pristine source car for a traffic body: by name in the roster (`CarRoster`, because the
-- folder is relocated out of Workspace at boot), falling back to anything tagged Car — the same
-- resolution RaceService uses for the player's car, so the two can't drift apart on a rename.
function TrafficService._findSource(self, name: string): Model?
	local named = CarRoster.car(name)
	if named then
		return named
	end
	for _, inst in CollectionService:GetTagged(RaceConfig.CarTag) do
		if inst:IsA("Model") and inst.Name == name then
			return inst
		end
	end
	return nil
end

--[[ Build every configured body once at startup and publish them. Reuses an already-published
	folder from a prior edit-session run rather than rebuilding it, same as RoadService does
	with its tile template.

	REUSE IS CONDITIONAL, and both conditions exist because a stale folder is silent rather than loud.
	A shell published before this file learned to stamp mount frames looks perfectly fine as traffic
	and simply refuses every steal redress, which reads as the steal being broken; and a body dropped
	from the roster keeps turning up on the road because `TrafficController` publishes whatever it
	finds in the folder rather than re-reading the config. So anything unrecognised is dropped and
	anything without a `MountFrame` is rebuilt. Both are startup-only, so the cost is a non-issue. ]]
function TrafficService._publishBodies(self)
	local folder = ReplicatedStorage:FindFirstChild(TrafficConfig.TemplateFolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = TrafficConfig.TemplateFolderName
		folder.Parent = ReplicatedStorage
	end

	--[[ EVERY world's cars, not the default world's. ReplicatedStorage is one folder for the whole
		server and a world is per player, so "publish the live world's eight" stopped being a thing
		that exists — see the roster block at the bottom of TrafficConfig. ]]
	local rebuild = folder:GetAttribute("RosterRevision") ~= TrafficConfig.TemplateRevision
	local wanted = {}
	for _, name in TrafficConfig.DisplayBodies or TrafficConfig.AllBodies do
		wanted[name] = true
	end
	for _, child in folder:GetChildren() do
		-- `MountFrame` is absent both on a stale shell and on a body that genuinely has no
		-- `RedressMount` to record. Rebuilding the latter every startup costs one shell and warns
		-- once, which is the right amount of noise for a rig that can't be stolen.
		if rebuild or not wanted[child.Name] or child:GetAttribute("MountFrame") == nil then
			child:Destroy()
		end
	end

	local built = 0
	for _, name in TrafficConfig.DisplayBodies or TrafficConfig.AllBodies do
		if folder:FindFirstChild(name) then
			built += 1
			continue
		end
		local source = self:_findSource(name)
		if not source then
			self.log:warn(string.format("No car named '%s' to build a traffic body from.", name))
			continue
		end
		local shell = self:_buildShell(source)
		if shell then
			shell.Parent = folder
			built += 1
		end
	end

	folder:SetAttribute("RosterRevision", TrafficConfig.TemplateRevision)
	if built == 0 then
		self.log:warn("No traffic bodies could be published; this session's roads run empty.")
	else
		self.log:info(string.format("Published %d traffic body shell(s).", built))
	end
end

--[[ A clip landed. Rate-limited here, priced from config, and handed to the one place HP moves.

	`severity` is 0..1 off the wire and therefore not to be trusted as-is. Anything that isn't a
	real number in range is priced at the MAXIMUM, deliberately: the only direction this is
	exploitable is downward (a client can under-report, as it always could by simply not reporting),
	so there must be no payoff in sending nonsense. NaN is checked explicitly because it fails every
	comparison — `math.clamp` would propagate it straight into the damage. ]]
function TrafficService._onTrafficHit(self, player: Player, severity: unknown)
	if not TrafficConfig.Enabled then
		return
	end
	local scale = 1
	if type(severity) == "number" and severity == severity then
		scale = math.clamp(severity, 0, 1)
	end

	local now = os.clock()
	if now - (self._lastHit[player] or 0) < TrafficConfig.ClipCooldown then
		return
	end

	local ObstacleService = Shard.get("ObstacleService")
	if not ObstacleService then
		return
	end
	-- Rounded because HP is shown to the player and every other hazard costs a whole number; an
	-- interpolated cost would otherwise leave the HUD reading 86.4.
	local range = TrafficConfig.Clip.Damage
	local damage = math.floor(range[1] + (range[2] - range[1]) * scale + 0.5)

	-- Only stamp the cooldown when the damage actually lands, so a report from someone who
	-- isn't racing can't shadow a real clip a moment later.
	if ObstacleService:applyHazardDamage(player, damage) then
		self._lastHit[player] = now
	end
end

TrafficService:withLifecycle({
	init = function(self)
		self._lastHit = {} -- [Player] = os.clock() of the last clip we charged for
	end,

	start = function(self)
		if not TrafficConfig.Enabled then
			return
		end
		-- Register the driving collision groups here, at server start, so they're part of the
		-- world every client replicates in rather than something each one has to race for at
		-- RaceStart. Both sides call this; it's idempotent (see CarCollision).
		CarCollision.ensure()
		self:_publishBodies()

		Players.PlayerRemoving:Connect(function(player)
			self._lastHit[player] = nil
		end)
	end,
})

return TrafficService
