--[[
	HopController  (client)
	-----------------------
	The Floater's hop (`DriveConfig.Hop`): while the player is driving a body flagged `Hop` in
	`WorldConfig.EventBodies`, a key (and a touch button) lifts the car off the deck on cold-gas
	thrusters, one under every wheel, the way the real Roadster lifted off. Tapped, it hops. Held, it
	climbs and FLOATS, bobbing, nose up, leaning into its turns. Let go and it comes down on a burn of
	the same thrusters, so it settles instead of slamming.

	TWO CARS IT CAN BE UNDER THE PLAYER. In a run it is `RoadController:getCar()` and it flies only while
	`DriveController:isDriving()` (not mid-bail, not frozen). In the lobby it is the car
	`LobbyDriveController` has the driver's seat of. Followed every frame, because a steal swaps the body
	mid-run and getting in or out of a lobby car swaps it too; the button and the thrusters go with it.

	=== IN A RUN THE CAR IS FLOWN (fourth pass, 2026-10-22) =====================================

	Three physics cuts worked in the lobby and lifted nothing in a run. So a run hop does not ask the
	solver at all: it is the steal's own flight machinery (`StealController._onBail`), which every run
	already trusts. The drive layer is suspended, every part anchored (remembering what a freeze had
	found, `DriveController.frozenAnchor`), and the car moved along the road frame each frame
	(`_flyRun`): along at its launch speed, across on the steer, up and down on a little 1-D flight of
	its own. It lands at exactly the height it left (`_landRun`) and is handed back with its speed.
	Road coordinates plus `RoadController.onWorldShift` keep it right across a rebase, as the steal's do.
	A bail is refused while it flies (`isFlying`, read by `StealController._canBail`): two controllers
	anchoring one car is the anchor bug that file documents.

	=== IN THE LOBBY IT IS CONSTRAINTS (third pass, 2026-10-22) ==================================

	A CarBones rig is not one physics body: each wheel is its own assembly, hung off the chassis by
	springs. So every assembly in the car gets its own `LinearVelocity` on the vertical line (`_buildLift`),
	all driven to the same target, so chassis and wheels rise as one and nothing levers the car over. The
	force is capped (`Accel` on top of gravity), so it eases in. An `AlignOrientation` is the gyro: it
	holds the car's up axis where `_fly` points it and leaves yaw alone.

	The assemblies are found AT LAUNCH, never before. The second cut listed them when the rig was built,
	which in a run is the countdown, when the car is anchored, so the list was empty and a run hop played
	its effects and lifted nothing (the owner, 2026-10-22).

	The launch kick itself is a velocity write, for `DriveController._recover`'s reason (never a CFrame).
	The drive layer writes the PrimaryPart's velocity every frame but carries its Y through.

	=== THE LOOK ================================================================================

	`DriveConfig.Hop.Puff` has the parts. The thrusters are Attachments on the PrimaryPart at each tyre's
	contact patch (`_buildRig`), built when a hop car comes under the player and destroyed when it goes, so
	they ride with the car and each wheel emits from its own spot. Everything is client-side: other players
	in the lobby see the car fly, not the gas.
]]

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local CarStats = require(ReplicatedStorage.shared.Modules.CarStats)
local DriveConfig = require(ReplicatedStorage.shared.Configs.DriveConfig)
--- Only for the boarding flag: a car the getaway truck has hold of is not ours to fly.
local GetawayConfig = require(ReplicatedStorage.shared.Configs.GetawayConfig)
local RoadEdgeGuard = require(ReplicatedStorage.shared.Modules.RoadEdgeGuard)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local HopController = Shard.new("HopController"):withDependencies({ "DriveController", "RoadController" })

local ACTION_NAME = "RaceHop"
--- The physics wheels every CarBones rig has (`TrafficService` reads the same four).
local CORNERS = { "FL", "FR", "RL", "RR" }
--- The per-wheel emitters, in `DriveConfig.Hop.Puff`.
local THRUSTER_PARTS = { "Plume", "Core", "Frost" }
--- Where the ground ray starts above the PrimaryPart, so nothing level with the chassis can hide the ground.
local PROBE_LIFT = 3
--- How far down the flight looks for the ground at all; past this the car is simply high.
local FAR_PROBE = 80
--- Seconds; longer than any honest flight (3s of float, a fall from ~25 studs, the settle).
local MAX_FLIGHT = 10
--- Sign of a steer value that turns LEFT, which is +Y yaw (`LobbyDriveController`'s same constant).
local STEER_LEFT = if DriveConfig.PositiveSteerIsLeft then 1 else -1

-- === Building the look ======================================================

--- A burst-and-stream emitter from one `Puff` entry, firing out of its attachment's -Y (down).
local function emitter(name: string, spec): ParticleEmitter
	local made = Instance.new("ParticleEmitter")
	made.Name = name
	made.Texture = spec.Texture
	made.Color = ColorSequence.new(spec.Color[1], spec.Color[2])
	made.LightEmission = spec.LightEmission
	made.LightInfluence = 1 - spec.LightEmission
	made.Rate = spec.Rate
	made.Enabled = false
	made.EmissionDirection = Enum.NormalId.Bottom
	made.SpreadAngle = Vector2.new(spec.Spread, spec.Spread)
	made.Speed = NumberRange.new(spec.Speed[1], spec.Speed[2])
	made.Lifetime = NumberRange.new(spec.Lifetime[1], spec.Lifetime[2])
	made.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, spec.Size[1]),
		NumberSequenceKeypoint.new(1, spec.Size[2]),
	})
	made.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, spec.Transparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	made.Drag = 5
	made.Rotation = NumberRange.new(0, 360)
	made.RotSpeed = NumberRange.new(-120, 120)
	return made
end

--- A built-in clip on the car, for `DriveConfig.Hop.Sound`'s `Launch`/`Loop`/`Land`.
local function sound(name: string, spec, parent: Instance, looped: boolean): Sound
	local made = Instance.new("Sound")
	made.Name = name
	made.SoundId = spec.Id
	made.Volume = spec.Volume
	made.PlaybackSpeed = spec.Pitch
	made.Looped = looped
	made.RollOffMode = Enum.RollOffMode.InverseTapered
	made.RollOffMinDistance = 40
	made.RollOffMaxDistance = 180
	made.Parent = parent
	return made
end

--- Where each tyre meets the road, in world space. Empty for a rig without the four suspension wheels.
local function contactPatches(car: Model, primary: BasePart): { Vector3 }
	local spots = {}
	local chassis = car:FindFirstChild("Chassis")
	for _, corner in CORNERS do
		local suspension = chassis and chassis:FindFirstChild("Suspension" .. corner)
		local wheel = suspension and suspension:FindFirstChild("Wheel")
		if wheel and wheel:IsA("BasePart") then
			local radius = math.max(wheel.Size.Y, wheel.Size.Z) * 0.5
			table.insert(spots, wheel.Position - primary.CFrame.UpVector * radius)
		end
	end
	return spots
end

--- Every unanchored physics body in the car, by its root, each once. Read live (header).
local function assembliesOf(car: Model): { BasePart }
	local roots, seen = {}, {}
	for _, part in car:GetDescendants() do
		if part:IsA("BasePart") and not part.Anchored then
			local root = part.AssemblyRootPart
			if root and not seen[root] and not root.Anchored then
				seen[root] = true
				table.insert(roots, root)
			end
		end
	end
	return roots
end

--[[ The thrusters for one car: an attachment per tyre on the PrimaryPart (or one under its middle for a
	rig without the four wheels), each carrying the three per-wheel emitters and a trail, plus the
	underglow and the sounds. Look only: nothing here touches the physics. ]]
function HopController._buildRig(self, car: Model, primary: BasePart)
	local hop = DriveConfig.Hop
	local puff = hop.Puff
	local rig = { car = car, thrusters = {}, emitters = {}, trails = {} }
	local spots = contactPatches(car, primary)
	if #spots == 0 then
		spots = { primary.Position - primary.CFrame.UpVector * primary.Size.Y * 0.5 }
	end
	for index, spot in spots do
		local mount = Instance.new("Attachment")
		mount.Name = "HopThruster" .. index
		mount.CFrame = CFrame.new(primary.CFrame:PointToObjectSpace(spot))
		for _, name in THRUSTER_PARTS do
			local made = emitter(name, puff[name])
			made.Parent = mount
			table.insert(rig.emitters, made)
		end
		mount.Parent = primary
		table.insert(rig.thrusters, mount)

		--- The streak: a ribbon across the thruster, left behind as the car moves.
		local spec = puff.Trail
		local left, right = Instance.new("Attachment"), Instance.new("Attachment")
		left.Name, right.Name = "HopTrailL" .. index, "HopTrailR" .. index
		left.CFrame = mount.CFrame * CFrame.new(-spec.Width * 0.5, 0, 0)
		right.CFrame = mount.CFrame * CFrame.new(spec.Width * 0.5, 0, 0)
		left.Parent, right.Parent = primary, primary
		local trail = Instance.new("Trail")
		trail.Name = "HopTrail"
		trail.Attachment0, trail.Attachment1 = left, right
		trail.Color = ColorSequence.new(spec.Color[1], spec.Color[2])
		trail.LightEmission = 1
		trail.LightInfluence = 0
		trail.Lifetime = spec.Lifetime
		trail.FaceCamera = true
		trail.Transparency = NumberSequence.new(spec.Transparency, 1)
		trail.WidthScale = NumberSequence.new(1, 0)
		trail.Enabled = false
		trail.Parent = left
		table.insert(rig.trails, { trail = trail, left = left, right = right })
	end
	local glow = Instance.new("PointLight")
	glow.Name = "HopGlow"
	glow.Color = puff.Glow.Color
	glow.Range = puff.Glow.Range
	glow.Brightness = 0
	glow.Shadows = false
	glow.Parent = primary
	rig.glow = glow
	rig.launch = sound("HopLaunch", hop.Sound.Launch, primary, false)
	rig.loop = sound("HopLoop", hop.Sound.Loop, primary, true)
	rig.land = sound("HopLand", hop.Sound.Land, primary, false)
	self._rig = rig
end

function HopController._destroyRig(self)
	self:_endFlight()
	local rig = self._rig
	if not rig then
		return
	end
	self._rig = nil
	for _, mount in rig.thrusters do
		--- Let the last of the gas finish rather than cutting it off mid-air.
		for _, child in mount:GetChildren() do
			(child :: ParticleEmitter).Enabled = false
		end
		Debris:AddItem(mount, 1.5)
	end
	for _, entry in rig.trails do
		entry.trail.Enabled = false
		Debris:AddItem(entry.left, 1)
		Debris:AddItem(entry.right, 1)
	end
	for _, made in { rig.glow, rig.launch, rig.loop, rig.land } do
		made:Destroy()
	end
end

--- The ground anchor: a Terrain attachment for the billow, which stays where it was blown.
function HopController._groundAnchor(self): Attachment
	if not self._ground then
		local anchor = Instance.new("Attachment")
		anchor.Name = "HopGround"
		local cloud = emitter("Cloud", DriveConfig.Hop.Puff.Cloud)
		--- Blown out across the ground, not down into it.
		cloud.EmissionDirection = Enum.NormalId.Top
		cloud.Acceleration = Vector3.new(0, -14, 0)
		cloud.Parent = anchor
		anchor.Parent = workspace.Terrain
		self._ground = anchor
	end
	return self._ground
end

--- A shimmering shockwave disc on the ground, expanding to `to` studs across and fading out.
local function shockwave(at: Vector3, to: number)
	local cfg = DriveConfig.Hop.Puff.Ring
	local ring = Instance.new("Part")
	ring.Name = "HopShockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.ForceField
	ring.Color = cfg.Color
	ring.Transparency = cfg.Transparency
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Size = Vector3.new(0.3, cfg.From, cfg.From)
	-- A cylinder's axis is X; lay it flat.
	ring.CFrame = CFrame.new(at + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(cfg.Time, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, to, to),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, cfg.Time)
end

-- === The physics ============================================================

--[[ The ground under the car within `probe` studs of the PrimaryPart, or nil; and how far below the
	PrimaryPart it is (math.huge for none). Only collidable parts count, as `RoadController._hasGroundUnder`
	does, so a lane line or a trigger volume is not mistaken for the deck. ]]
--- One params for every probe: `_step` asks every Heartbeat while grounded.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

function HopController._groundBelow(self, car: Model, primary: BasePart, probe: number): (RaycastResult?, number)
	local params = groundParams
	params.FilterDescendantsInstances = { car, Players.LocalPlayer.Character :: Instance }
	local hit = workspace:Raycast(primary.Position + Vector3.new(0, PROBE_LIFT, 0), Vector3.new(0, -(probe + PROBE_LIFT), 0), params)
	return hit, if hit then hit.Distance - PROBE_LIFT else math.huge
end

--[[ The flight's constraints, made at launch on the car as it is right now (header): a vertical
	`LinearVelocity` on every assembly, at its centre of mass so it lifts without turning it, switched off
	until `_setLift`; and the gyro, an `AlignOrientation` on the PrimaryPart whose primary axis is the car's
	up. Everything is parented under attachments the flight owns, so `_endFlight` removes it all. ]]
function HopController._buildLift(self, flight, car: Model, primary: BasePart)
	for _, root in assembliesOf(car) do
		local anchor = Instance.new("Attachment")
		anchor.Name = "HopLift"
		anchor.Parent = root
		anchor.WorldPosition = root.AssemblyCenterOfMass
		local lift = Instance.new("LinearVelocity")
		lift.Name = "HopLift"
		lift.Attachment0 = anchor
		lift.RelativeTo = Enum.ActuatorRelativeTo.World
		lift.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
		lift.LineDirection = Vector3.yAxis
		lift.ForceLimitsEnabled = true
		lift.Enabled = false
		lift.Parent = anchor
		table.insert(flight.lifts, { constraint = lift, mass = root.AssemblyMass })
		table.insert(flight.owned, anchor)
	end

	local mount = Instance.new("Attachment")
	mount.Name = "HopGyro"
	--- X is the primary axis an AlignOrientation steers; point it along the car's up.
	mount.CFrame = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, -Vector3.xAxis)
	mount.Parent = primary
	local gyro = Instance.new("AlignOrientation")
	gyro.Name = "HopGyro"
	gyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
	gyro.Attachment0 = mount
	--- Up only, yaw free. `AlignType` where this engine has it, the older switch where it does not.
	if not pcall(function()
		(gyro :: any).AlignType = Enum.AlignType.PrimaryAxisParallel
	end) then
		gyro.PrimaryAxisOnly = true
	end
	gyro.PrimaryAxis = Vector3.yAxis
	gyro.Responsiveness = DriveConfig.Hop.Gyro.Responsiveness
	gyro.MaxTorque = math.huge
	gyro.Parent = mount
	flight.gyro = gyro
	table.insert(flight.owned, mount)
end

--- Drive every assembly toward `speed` studs/s up, with at most `accel` studs/s² over gravity to do it.
function HopController._setLift(self, flight, speed: number, accel: number)
	local gravity = workspace.Gravity
	for _, entry in flight.lifts do
		local lift = entry.constraint
		lift.LineVelocity = speed
		lift.MaxForce = entry.mass * (gravity + accel)
		lift.Enabled = true
	end
end

function HopController._cutLift(self, flight)
	for _, entry in flight.lifts do
		entry.constraint.Enabled = false
	end
end

-- === Run flight =============================================================

--- Begin a deterministic run flight. The live chassis is suspended and anchored before any CFrame write.
function HopController._launchRun(self, car: Model, primary: BasePart): boolean
	local info = self._road and self._road:getRoadInfo()
	if not info then
		return false
	end
	if car:GetAttribute(GetawayConfig.Boarding.Attribute) then
		return false
	end

	local position = primary.Position
	local hitBox = car:FindFirstChild("HitBox", true)
	local crossLimit = if hitBox and hitBox:IsA("BasePart")
		then RoadEdgeGuard.limit(hitBox.CFrame, hitBox.Size, info.cross, info.driveWidth, DriveConfig.LaneHalfWidth)
		else DriveConfig.LaneHalfWidth
	local flight = {
		mode = "run",
		car = car,
		info = info,
		primaryToPivot = primary.CFrame:ToObjectSpace(car:GetPivot()),
		along = position:Dot(info.forward),
		cross = position:Dot(info.cross) - info.driveCenter,
		y = position.Y,
		launchY = position.Y,
		alongVel = math.max(primary.AssemblyLinearVelocity:Dot(info.forward), 0),
		yVel = DriveConfig.Hop.Speed,
		crossLimit = crossLimit,
		sinceWash = 0,
		cushioned = false,
		startedAt = os.clock(),
		anchors = {},
		owned = {},
	}

	for _, part in car:GetDescendants() do
		if part:IsA("BasePart") then
			local prior = self._drive:frozenAnchor(part)
			flight.anchors[part] = if prior ~= nil then prior else part.Anchored
			part.Anchored = true
		end
	end
	self._drive:suspend()
	self._flight = flight
	return true
end

--- Put the run car at its exact resting height, then hand it back to the drive layer.
function HopController._landRun(self, flight)
	local car = flight.car
	if car and car.Parent and car.PrimaryPart then
		local info = flight.info
		local position = info.forward * flight.along
			+ info.cross * (info.driveCenter + flight.cross)
			+ Vector3.yAxis * flight.launchY
		car:PivotTo(CFrame.lookAt(position, position + info.forward) * flight.primaryToPivot)
	end
	self:_punch("HopLand")
	self:_endFlight()
end

--- Move an anchored run car for one frame in road coordinates.
function HopController._flyRun(self, dt: number)
	local flight = self._flight
	local car = flight and flight.car
	local primary = car and car.PrimaryPart
	if not (flight and flight.mode == "run" and self._racing and car == self._car and primary and self._rig) then
		self:_endFlight()
		return
	end

	--- The truck takes the car: put it down at once rather than both of us moving it.
	if car:GetAttribute(GetawayConfig.Boarding.Attribute) then
		self:_landRun(flight)
		return
	end
	--- A freeze (pause, tutorial hold) holds the flight where it is; `DriveController.setFrozen` leaves
	--- the anchors to us while we fly. The clock moves with it, so `MAX_FLIGHT` does not cut a long hold.
	if self._drive:isFrozen() then
		flight.startedAt += dt
		self:_setThrust(0)
		return
	end

	dt = math.clamp(dt, 0, 0.1)
	local cfg = DriveConfig.Hop
	local float = cfg.Float
	local now = os.clock()
	local held = self._held and self._air > 0
	local height = flight.y - flight.launchY
	if held then
		self._air = math.max(0, self._air - dt)
		local bob = math.sin((now - flight.startedAt) * float.Bob.Rate * math.pi) * float.Bob.Studs
		local target = flight.launchY + float.Height + bob
		local want = math.clamp((target - flight.y) * float.Gain, -float.Climb * 0.5, float.Climb)
		if flight.yVel > want and flight.y < target then
			flight.yVel -= workspace.Gravity * cfg.Run.Gravity * dt
		else
			flight.yVel += math.clamp(want - flight.yVel, -float.Accel * dt, float.Accel * dt)
		end
		self:_setThrust(1)
	--[[ The landing burn, only once the key is let go (a hover bobbing at `Float.Height` dips under
		`Land.Probe` and fired it mid-air). No gravity here: the burn holds the fall on top of it, as the
		lobby's lift does. 2026-10-23: gravity (0.8 x 196) then a 140 correction lost every frame, so the
		fall never eased to `Touch`. ]]
	elseif flight.yVel < 0 and height <= cfg.Land.Probe then
		if not flight.cushioned then
			flight.cushioned = true
			local puff = cfg.Puff
			self:_blast(car, primary, puff.Land.Scale, puff.Land.RingTo)
			self._rig.land:Play()
		end
		local cap = cfg.Land.Touch
			+ (cfg.Land.Speed - cfg.Land.Touch) * math.clamp(height / cfg.Land.Final, 0, 1)
		local want = -cap
		flight.yVel += math.clamp(want - flight.yVel, -cfg.Land.Accel * dt, cfg.Land.Accel * dt)
		self:_setThrust(cfg.Puff.Land.Rate)
	else
		flight.yVel -= workspace.Gravity * cfg.Run.Gravity * dt
		self:_setThrust(0)
	end

	flight.along += flight.alongVel * dt
	local steer = self._drive:getSteerInput() * STEER_LEFT
	flight.cross = math.clamp(flight.cross + steer * cfg.Run.AirLaneSpeed * dt, -flight.crossLimit, flight.crossLimit)
	flight.y += flight.yVel * dt
	if flight.y <= flight.launchY or now - flight.startedAt > MAX_FLIGHT then
		self:_landRun(flight)
		return
	end

	local info = flight.info
	local position = info.forward * flight.along
		+ info.cross * (info.driveCenter + flight.cross)
		+ Vector3.yAxis * flight.y
	local pitch = math.rad(cfg.Run.MaxPitchDeg) * math.clamp(flight.yVel / float.Climb, -1, 1)
	local roll = math.rad(cfg.Run.MaxRollDeg) * steer
	local primaryFrame = CFrame.lookAt(position, position + info.forward) * CFrame.Angles(pitch, 0, roll)
	car:PivotTo(primaryFrame * flight.primaryToPivot)

	flight.sinceWash += dt
	local wash = cfg.Puff.Wash
	if flight.sinceWash >= wash.Every then
		flight.sinceWash = 0
		local ground = self:_groundBelow(car, primary, wash.Reach)
		if ground then
			local anchor = self:_groundAnchor()
			anchor.WorldCFrame = CFrame.new(ground.Position)
			anchor.Cloud:Emit(wash.Count)
		end
	end
end

--- Keep road-frame scalars aligned when RoadController rebases the live world.
function HopController._onWorldShift(self, shift: Vector3)
	local flight = self._flight
	if not (flight and flight.mode == "run") then
		return
	end
	flight.along += shift:Dot(flight.info.forward)
	flight.y += shift.Y
	flight.launchY += shift.Y
end

-- === The beats ==============================================================

--- One burst from every thruster and the ground under them: the launch at 1, the landing at less.
function HopController._blast(self, car: Model, primary: BasePart, scale: number, ringTo: number)
	local puff = DriveConfig.Hop.Puff
	for _, made in self._rig.emitters do
		made:Emit(math.ceil(puff[made.Name].Burst * scale))
	end
	local ground = self:_groundBelow(car, primary, puff.Wash.Reach)
	if ground then
		local anchor = self:_groundAnchor()
		anchor.WorldCFrame = CFrame.new(ground.Position)
		anchor.Cloud:Emit(math.ceil(puff.Cloud.Burst * scale))
		shockwave(ground.Position, ringTo)
	end
	local glow = self._rig.glow
	glow.Brightness = puff.Glow.Flash * scale
	TweenService:Create(glow, TweenInfo.new(0.35), { Brightness = 0 }):Play()
end

--- Thrusters lit at `rate` (a share of each emitter's `Rate`; 0 is out): the streams, the glow, the hiss.
function HopController._setThrust(self, rate: number)
	local rig = self._rig
	if not rig or rig.rate == rate then
		return
	end
	rig.rate = rate
	local puff = DriveConfig.Hop.Puff
	for _, made in rig.emitters do
		made.Rate = puff[made.Name].Rate * rate
		made.Enabled = rate > 0
	end
	TweenService:Create(rig.glow, TweenInfo.new(0.15), { Brightness = puff.Glow.Brightness * rate }):Play()
	if rate > 0 then
		rig.loop.Volume = DriveConfig.Hop.Sound.Loop.Volume * math.max(rate, 0.5)
		if not rig.loop.IsPlaying then
			rig.loop:Play()
		end
	else
		rig.loop:Stop()
	end
end

function HopController._setTrails(self, on: boolean)
	local rig = self._rig
	if not rig or rig.trailsOn == on then
		return
	end
	rig.trailsOn = on
	for _, entry in rig.trails do
		entry.trail.Enabled = on
	end
end

--- The camera's beat: the race camera's own punch in a run, a field-of-view kick in the lobby.
function HopController._punch(self, kind: string)
	if self._racing then
		local camera = Shard.get("RaceCameraController")
		if camera then
			camera:stealPunch(kind)
		end
		return
	end
	local camera = workspace.CurrentCamera
	if not (camera and kind == "HopLaunch") then
		return
	end
	local cfg = DriveConfig.Hop.Camera
	--- The base is taken once per kick-and-return, so a hop inside the last one's ease cannot ratchet it.
	self._fovBase = self._fovBase or camera.FieldOfView
	local base = self._fovBase
	if self._fovTween then
		self._fovTween:Cancel()
	end
	camera.FieldOfView = base + cfg.LobbyFovKick
	local tween = TweenService:Create(camera, TweenInfo.new(cfg.LobbyFovTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = base,
	})
	self._fovTween = tween
	tween.Completed:Connect(function()
		if self._fovTween == tween then
			self._fovTween, self._fovBase = nil, nil
		end
	end)
	tween:Play()
end

function HopController._hop(self)
	local car = self._car
	local primary = car and car.PrimaryPart
	if not (primary and self._rig) then
		return
	end
	if self._racing and not self._drive:isDriving() then
		return
	end
	local now = os.clock()
	local cfg = DriveConfig.Hop
	if now - self._lastHop < cfg.Cooldown or self._flight then
		return
	end
	local ground, rest = self:_groundBelow(car, primary, cfg.GroundProbe)
	if not ground then
		return
	end
	if self._racing then
		--- Every launch costs air, or tapping every `Cooldown` is a free, endless hop.
		if self._air < cfg.Float.TapCost then
			return
		end
		--- A run: flown, not simulated (header).
		if not self:_launchRun(car, primary) then
			return
		end
		self._air -= cfg.Float.TapCost
	else
		--[[ A CEILING, so hops cannot chain onto roofs and out of the map (2026-10-25 review): the float
			tops out `Float.Height` over where the car was boarded (`_baseY`), and no hop starts above that. ]]
		if primary.Position.Y > self._baseY + cfg.Float.Height then
			return
		end
		local roots = assembliesOf(car)
		if #roots == 0 then
			return
		end
		--- The kick: every body at once, so the wheels leave with the chassis.
		for _, root in roots do
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(v.X, cfg.Speed, v.Z)
		end
		--- `rest` is how far the ground sits below the PrimaryPart with the wheels down; every landing
		--- height is measured from it.
		local flight = {
			mode = "lobby",
			car = car,
			launchY = math.min(primary.Position.Y, self._baseY),
			rest = rest,
			fuel = 0,
			sinceWash = 0,
			cushioned = false,
			landedAt = nil :: number?,
			startedAt = now,
			lifts = {},
			owned = {},
			gyro = nil :: AlignOrientation?,
		}
		self._flight = flight
		self:_buildLift(flight, car, primary)
	end
	self._lastHop = now

	self:_blast(car, primary, 1, cfg.Puff.Ring.To)
	self:_setTrails(true)
	self:_punch("HopLaunch")
	local authored = self._sounds and cfg.Sound.Name and self._sounds:PlayNamed(cfg.Sound.Group, cfg.Sound.Name)
	if not authored then
		self._rig.launch:Play()
	end
end

--- Everything the flight made comes down; the thrusters go out. Safe to call with no flight.
function HopController._endFlight(self)
	local flight = self._flight
	if not flight then
		return
	end
	self._flight = nil
	if flight.mode == "run" then
		for part, anchored in flight.anchors do
			if part.Parent then
				part.Anchored = anchored
			end
		end
		local primary = flight.car and flight.car.PrimaryPart
		if primary and primary.Parent then
			primary.AssemblyLinearVelocity = flight.info.forward * flight.alongVel
			primary.AssemblyAngularVelocity = Vector3.zero
		end
		self._drive:resume()
	end
	for _, made in flight.owned do
		made:Destroy()
	end
	self:_setThrust(0)
	self:_setTrails(false)
end

--[[ The gyro's target, one frame: the car's up, tipped back by the climb (nose up rising, down falling)
	and, in the lobby, over into the air turn. Plus the air turn itself, a yaw rate off the steer, only
	while airborne and only in the lobby (a run's heading is `DriveController`'s). ]]
function HopController._attitude(self, flight, primary: BasePart, airborne: boolean)
	local gyro = flight.gyro
	if not gyro then
		return
	end
	local cfg = DriveConfig.Hop.Gyro
	local frame = primary.CFrame
	local look = Vector3.new(frame.LookVector.X, 0, frame.LookVector.Z)
	local right = Vector3.new(frame.RightVector.X, 0, frame.RightVector.Z)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.zAxis
	right = if right.Magnitude > 1e-3 then right.Unit else Vector3.xAxis

	local climb = math.clamp(primary.AssemblyLinearVelocity.Y / DriveConfig.Hop.Float.Climb, -1, 1)
	local pitch = math.rad(cfg.MaxPitchDeg) * climb

	local turn = 0
	if airborne and not self._racing and self._lobby then
		turn = self._lobby:getSteer() * STEER_LEFT
		local spin = primary.AssemblyAngularVelocity
		primary.AssemblyAngularVelocity = Vector3.new(spin.X, turn * cfg.AirTurnRate, spin.Z)
	end
	local roll = math.rad(cfg.MaxRollDeg) * turn

	--- Nose up tips the up axis backward; a left turn (positive) leans the up axis to the left.
	gyro.PrimaryAxis = (Vector3.yAxis - look * math.tan(pitch) - right * math.tan(roll)).Unit
end

--[[ One frame of a flight (`DriveConfig.Hop`, header). Held: climb toward the float height and hover
	there, bobbing, until the fuel runs out. Otherwise: fall free, until the ground is `Land.Probe` under the
	car, where the thrusters burn to cap the fall and ease it to `Touch`. Down when within half a stud of
	rest; the gyro holds on for `Settle`, then the flight is over. Over at once if the car is swapped or no
	longer drivable. ]]
function HopController._fly(self, dt: number)
	local flight = self._flight
	local car = self._car
	local primary = car and car.PrimaryPart
	if flight.mode == "run" then
		self:_flyRun(dt)
		return
	end
	if not (primary and self._rig and car == flight.car) or (self._racing and not self._drive:isDriving()) then
		self:_endFlight()
		return
	end
	local cfg = DriveConfig.Hop
	local now = os.clock()
	local v = primary.AssemblyLinearVelocity
	if now - flight.startedAt > MAX_FLIGHT then
		self:_endFlight()
		return
	end

	local _, below = self:_groundBelow(car, primary, FAR_PROBE)
	local height = below - flight.rest
	self:_attitude(flight, primary, height > 1.5)

	--- Down: the burn is off, the gyro holds a moment longer so a bounce cannot tip it.
	if flight.landedAt then
		self:_cutLift(flight)
		self:_setThrust(0)
		self:_setTrails(false)
		if now - flight.landedAt >= cfg.Land.Settle then
			self:_endFlight()
		end
		return
	end

	local float = cfg.Float
	if self._held and flight.fuel < float.Seconds then
		flight.fuel += dt
		local bob = math.sin((now - flight.startedAt) * float.Bob.Rate * math.pi) * float.Bob.Studs
		local target = flight.launchY + float.Height + bob
		local want = math.clamp((target - primary.Position.Y) * float.Gain, -float.Climb * 0.5, float.Climb)
		--- Still rising faster than the float wants and below it: the kick coasts up on its own.
		if v.Y > want and primary.Position.Y < target then
			self:_cutLift(flight)
		else
			self:_setLift(flight, want, float.Accel)
		end
		self:_setThrust(1)
		flight.sinceWash += dt
		local wash = cfg.Puff.Wash
		if flight.sinceWash >= wash.Every then
			flight.sinceWash = 0
			local ground = self:_groundBelow(car, primary, wash.Reach)
			if ground then
				local anchor = self:_groundAnchor()
				anchor.WorldCFrame = CFrame.new(ground.Position)
				anchor.Cloud:Emit(wash.Count)
			end
		end
		return
	end

	local land = cfg.Land
	if v.Y < 0 and height <= land.Probe then
		if not flight.cushioned then
			flight.cushioned = true
			local puff = cfg.Puff
			self:_blast(car, primary, puff.Land.Scale, puff.Land.RingTo)
			self._rig.land:Play()
		end
		local cap = land.Touch + (land.Speed - land.Touch) * math.clamp(height / land.Final, 0, 1)
		self:_setLift(flight, -cap, land.Accel)
		self:_setThrust(cfg.Puff.Land.Rate)
		if height <= 0.5 then
			flight.landedAt = now
			self:_punch("HopLand")
		end
	elseif flight.cushioned and v.Y > -1 and height < 2 then
		--- Stopped falling inside the burn: on its wheels, a hair above the measured rest.
		flight.landedAt = now
		self:_punch("HopLand")
	else
		self:_cutLift(flight)
		self:_setThrust(0)
	end
end

-- === Input and the car under the player =====================================

function HopController._bind(self)
	if self._bound then
		return
	end
	self._bound = true
	local cfg = DriveConfig.Hop
	ContextActionService:BindActionAtPriority(ACTION_NAME, function(_, inputState)
		--- Held is the float (`_fly`); End and Cancel both let go.
		self._held = inputState == Enum.UserInputState.Begin
		if self._held then
			self:_hop()
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.ContextActionPriority.High.Value + 500, table.unpack(cfg.Keys))
	ContextActionService:SetTitle(ACTION_NAME, cfg.Title)
	ContextActionService:SetPosition(ACTION_NAME, cfg.ButtonPosition)
end

function HopController._unbind(self)
	if not self._bound then
		return
	end
	self._bound = false
	self._held = false
	ContextActionService:UnbindAction(ACTION_NAME)
end

--- Follow the car under the player (header): a hop body binds the button and gets thrusters.
function HopController._step(self, dt: number)
	local car
	if self._racing then
		car = self._road and self._road:getCar()
	elseif self._lobby then
		car = self._lobby:getCar()
	end
	self._car = car
	local event = car and WorldConfig.EventBodies[CarStats.bodyOf(car)]
	local primary = car and car.PrimaryPart
	if event and event.Hop and primary then
		if not (self._rig and self._rig.car == car) then
			self:_destroyRig()
			self:_buildRig(car, primary)
			--- Where it was boarded: the lobby float's ceiling is measured from here (`_hop`).
			self._baseY = primary.Position.Y
		end
		self:_bind()
		--- Run air is a reserve, not a fresh tank per hop. It refills only while grounded.
		if self._racing and not self._flight then
			local ground = self:_groundBelow(car, primary, DriveConfig.Hop.GroundProbe)
			if ground then
				local float = DriveConfig.Hop.Float
				self._air = math.min(float.Seconds, self._air + float.Seconds / float.RechargeSeconds * dt)
			end
		end
	else
		self:_destroyRig()
		self:_unbind()
	end
	if self._flight then
		self:_fly(dt)
	end
end

--- In a run (true) or not (false). A wreck is not driving, so it reads as out until the revive.
function HopController._setRacing(self, racing: boolean)
	self._racing = racing
	self._car = nil
	self:_destroyRig()
	self:_unbind()
end

--- PUBLIC (StealController): true while this controller owns the run car's anchors.
--- Game-time road speed while the run chassis is anchored and moved by CFrame.
function HopController.roadSpeed(self): number?
	local flight = self._flight
	return if flight and flight.mode == "run" and flight.car == self._car then flight.alongVel else nil
end

function HopController.isFlying(self): boolean
	return self._flight ~= nil and self._flight.mode == "run"
end

--- PUBLIC (DrivingHudController): the current run car has the Floater hop.
function HopController.isAvailable(self): boolean
	return self._racing and self._bound
end

--- PUBLIC (DrivingHudController): fraction of the run hop's thrust reserve still available.
function HopController.airRemaining(self): number
	local seconds = DriveConfig.Hop.Float.Seconds
	return if seconds > 0 then math.clamp(self._air / seconds, 0, 1) else 0
end

HopController:withRemoteEvents({
	{
		RaceStart = function()
			HopController._air = DriveConfig.Hop.Float.Seconds
			HopController:_setRacing(true)
		end,
		RaceWrecked = function()
			HopController:_setRacing(false)
		end,
		RaceRevived = function()
			HopController:_setRacing(true)
		end,
		RaceEnd = function()
			HopController:_setRacing(false)
		end,
	},
})

HopController:withLifecycle({
	init = function(self)
		self._bound = false
		self._held = false
		self._racing = false
		self._car = nil
		self._rig = nil
		self._flight = nil
		self._air = DriveConfig.Hop.Float.Seconds
		self._baseY = 0
		self._lastHop = -math.huge
	end,

	start = function(self)
		if not DriveConfig.Hop.Enabled then
			return
		end
		self._drive = Shard.get("DriveController")
		self._road = Shard.get("RoadController")
		self._lobby = Shard.get("LobbyDriveController")
		self._sounds = Shard.get("SoundController")
		self._road:onWorldShift(function(shift)
			self:_onWorldShift(shift)
		end)
		RunService.Heartbeat:Connect(function(dt)
			self:_step(dt)
		end)
	end,
})

return HopController
