--[[
	HopController  (client)
	-----------------------
	The limited event car's hop (`DriveConfig.Hop`): while the player is driving a body flagged `Hop`
	in `WorldConfig.EventBodies`, a key (and a touch button) launches the car off the deck on cold-gas
	thrusters, one under every wheel, the way the real Roadster lifted off. Held, it climbs like a
	jetpack; let go, it falls and lands on a cushion of air.

	TWO CARS IT CAN BE UNDER THE PLAYER. In a run it is `RoadController:getCar()` and it flies only while
	`DriveController:isDriving()` (not mid-bail, not frozen). In the lobby it is the car
	`LobbyDriveController` has the driver's seat of. Followed every frame, because a steal swaps the body
	mid-run and getting in or out of a lobby car swaps it too; the button and the thrusters go with it.

	=== WHY IT LIFTS EVERY ASSEMBLY, AND WHY THE GYRO ==========================================

	A CarBones rig is not one physics body: each wheel is its own assembly, hung off the chassis by
	springs and hinges. Lifting only the PrimaryPart (the first cut) left the four wheels behind on their
	springs, and the drag levered the car over. In a run `DriveController`'s upright servo hid that; the
	lobby has no servo, so it flipped (the owner, 2026-10-22). So the rise is written to EVERY assembly in
	the car (`_rise`), and while airborne the gyro (`_level`) holds roll and pitch at level.

	VELOCITY WRITES, NOT CFRAME WRITES, for `DriveController._recover`'s reason. The drive layer writes
	the PrimaryPart's velocity every frame but carries its Y through, so the rise survives it; a lobby
	car is plain physics and owned by its driver, so the write lands there too.

	=== THE LOOK ================================================================================

	`DriveConfig.Hop.Puff` has the parts. The thrusters are Attachments on the PrimaryPart at each tyre's
	contact patch (`_buildRig`), built when a hop car comes under the player and destroyed when it goes,
	so they ride with the car and each wheel emits from its own spot (one shared emitter moved between
	four spots in one frame emits all four bursts at the last spot, which is why the first cut puffed
	from one wheel). Everything is client-side: other players in the lobby see the car hop, not the gas.
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
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local HopController = Shard.new("HopController"):withDependencies({ "DriveController", "RoadController" })

local ACTION_NAME = "RaceHop"
--- The physics wheels every CarBones rig has (`TrafficService` reads the same four).
local CORNERS = { "FL", "FR", "RL", "RR" }
--- The per-wheel emitters, in `DriveConfig.Hop.Puff`.
local THRUSTER_PARTS = { "Plume", "Core", "Frost" }

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

--[[ The thrusters for one car: an attachment per tyre on the PrimaryPart (or one under its middle for a
	rig without the four wheels), each carrying the three per-wheel emitters, plus the underglow. ]]
function HopController._buildRig(self, car: Model, primary: BasePart)
	local puff = DriveConfig.Hop.Puff
	local rig = { car = car, thrusters = {}, emitters = {}, assemblies = {} }
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
	end
	local glow = Instance.new("PointLight")
	glow.Name = "HopGlow"
	glow.Color = puff.Glow.Color
	glow.Range = puff.Glow.Range
	glow.Brightness = 0
	glow.Shadows = false
	glow.Parent = primary
	rig.glow = glow
	--- Every physics body in the car, for `_rise` (header): roots only, so each is written once.
	for _, part in car:GetDescendants() do
		if part:IsA("BasePart") and not part.Anchored and part.AssemblyRootPart == part then
			table.insert(rig.assemblies, part)
		end
	end
	self._rig = rig
end

function HopController._destroyRig(self)
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
	rig.glow:Destroy()
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

--- Where the ray starts above the PrimaryPart, so nothing level with the chassis can hide the ground.
local PROBE_LIFT = 3
--- Seconds; longer than any honest flight (1.4s of thrust, a fall from ~35 studs, the settle).
local MAX_FLIGHT = 8

--[[ The ground under the car within `probe` studs of the PrimaryPart, or nil; and how far below the
	PrimaryPart it is. Only collidable parts count, as `RoadController._hasGroundUnder` does, so a lane
	line or a trigger volume is not mistaken for the deck. ]]
function HopController._groundBelow(self, car: Model, primary: BasePart, probe: number): (RaycastResult?, number)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { car, Players.LocalPlayer.Character :: Instance }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(primary.Position + Vector3.new(0, PROBE_LIFT, 0), Vector3.new(0, -(probe + PROBE_LIFT), 0), params)
	return hit, if hit then hit.Distance - PROBE_LIFT else math.huge
end

--- Say once per reason why a press did not hop, so a playtest's Output names the blocker.
function HopController._refused(self, why: string)
	self._saidWhy = self._saidWhy or {}
	if not self._saidWhy[why] then
		self._saidWhy[why] = true
		self.log:warn("Hop refused (" .. (if self._racing then "run" else "lobby") .. "): " .. why)
	end
end

--- Set the whole car's upward speed (header: every assembly, not just the chassis).
function HopController._rise(self, speed: number)
	for _, part in self._rig.assemblies do
		if part.Parent then
			local v = part.AssemblyLinearVelocity
			part.AssemblyLinearVelocity = Vector3.new(v.X, speed, v.Z)
		end
	end
end

--- The gyro (`DriveConfig.Hop.Gyro`): roll and pitch pulled back to level, yaw left to the steering.
function HopController._level(self, primary: BasePart)
	local tilt = primary.CFrame.UpVector:Cross(Vector3.yAxis)
	local spin = primary.AssemblyAngularVelocity
	primary.AssemblyAngularVelocity = Vector3.new(0, spin.Y, 0) + tilt * DriveConfig.Hop.Gyro.Gain
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

--- Thrusters lit or out: the streams and the held underglow.
function HopController._setThrust(self, on: boolean)
	local rig = self._rig
	if not rig or rig.lit == on then
		return
	end
	rig.lit = on
	for _, made in rig.emitters do
		made.Enabled = on
	end
	TweenService:Create(rig.glow, TweenInfo.new(0.15), {
		Brightness = if on then DriveConfig.Hop.Puff.Glow.Brightness else 0,
	}):Play()
end

function HopController._hop(self)
	local car = self._car
	local primary = car and car.PrimaryPart
	if not (primary and self._rig) then
		self:_refused("no car or no thrusters under the player")
		return
	end
	if self._racing and not self._drive:isDriving() then
		self:_refused("DriveController says the car is not driving (frozen, suspended or not installed)")
		return
	end
	local now = os.clock()
	local cfg = DriveConfig.Hop
	if now - self._lastHop < cfg.Cooldown or self._flight then
		return
	end
	local ground, rest = self:_groundBelow(car, primary, cfg.GroundProbe)
	if not ground then
		self:_refused(string.format("no collidable ground within %d studs under the car", cfg.GroundProbe))
		return
	end
	self._lastHop = now
	self:_rise(cfg.Speed)
	self:_blast(car, primary, 1, cfg.Puff.Ring.To)
	--- The flight `_fly` steers until the car is back on the deck. `rest` is how far the ground sits
	--- below the PrimaryPart with the wheels down; every landing height is measured from it.
	self._flight = {
		car = car,
		launchY = primary.Position.Y,
		rest = rest,
		thrust = 0,
		sinceWash = 0,
		cushioned = false,
		landedAt = nil :: number?,
		checked = false,
		startedAt = now,
	}
	local sound = cfg.Sound
	if self._sounds and sound then
		self._sounds:PlayNamed(sound.Group, sound.Name)
	end
end

--[[ One frame of a flight (`DriveConfig.Hop`, "it flies like a jetpack"). Always: the gyro. Held key:
	hold the climb at `Thrust.Speed`, thrusters lit, washing the ground below, until the time or the
	height runs out. Falling near the ground: cap the fall and blast once. Over when the car is back on
	the deck, swapped, or no longer drivable. ]]
function HopController._fly(self, dt: number)
	local flight = self._flight
	local car = self._car
	local primary = car and car.PrimaryPart
	if not (primary and self._rig and car == flight.car) or (self._racing and not self._drive:isDriving()) then
		self._flight = nil
		self:_setThrust(false)
		return
	end
	local cfg = DriveConfig.Hop
	self:_level(primary)
	local v = primary.AssemblyLinearVelocity
	--- The first frame after launch: if the rise did not survive, something in this mode overwrote it.
	if not flight.checked then
		flight.checked = true
		if v.Y < cfg.Speed * 0.5 then
			self:_refused(string.format("launched at %d studs/s up but the next frame read %.1f; something overwrote it", cfg.Speed, v.Y))
		end
	end

	--- Settling: wheels are down, the gyro holds a moment longer so a bounce cannot tip it.
	if flight.landedAt then
		if os.clock() - flight.landedAt >= cfg.Land.Settle then
			self._flight = nil
		end
		return
	end

	local thrust = cfg.Thrust
	local lit = self._held and flight.thrust < thrust.Seconds and primary.Position.Y - flight.launchY < thrust.MaxHeight
	self:_setThrust(lit)
	if lit then
		flight.thrust += dt
		if v.Y < thrust.Speed then
			self:_rise(thrust.Speed)
		end
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

	--[[ The descent, measured above where the car sits at rest (`flight.rest`). From `Probe` up the fall
		is capped at `Speed` and the cushion fires once; over the last `Final` the cap eases down to
		`Touch`, so the wheels meet the deck at a walk. Down when within half a stud of rest. ]]
	local land = cfg.Land
	if v.Y < 0 then
		local _, below = self:_groundBelow(car, primary, flight.rest + land.Probe)
		local height = below - flight.rest
		if height <= land.Probe then
			if not flight.cushioned then
				flight.cushioned = true
				self:_blast(car, primary, cfg.Puff.Land.Scale, cfg.Puff.Land.RingTo)
			end
			local cap = land.Touch + (land.Speed - land.Touch) * math.clamp(height / land.Final, 0, 1)
			if v.Y < -cap then
				self:_rise(-cap)
			end
			if height <= 0.5 then
				flight.landedAt = os.clock()
			end
		end
	elseif flight.cushioned then
		--- Stopped falling inside the cushion: on its wheels, a hair above the measured rest.
		flight.landedAt = os.clock()
	end
	--- Backstop: no flight outlives `MAX_FLIGHT`, whatever the ground did (a car driven off an edge).
	if os.clock() - flight.startedAt > MAX_FLIGHT then
		self._flight = nil
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
		--- Held is the jetpack (`_fly`); End and Cancel both let go.
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
		end
		self:_bind()
	else
		self._flight = nil
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
	self._flight = nil
	self:_destroyRig()
	self:_unbind()
end

HopController:withRemoteEvents({
	{
		RaceStart = function()
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
		RunService.Heartbeat:Connect(function(dt)
			self:_step(dt)
		end)
	end,
})

return HopController
