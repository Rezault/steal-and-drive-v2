--[[
	LobbyDriveController  (client)
	------------------------------
	How a car you spawned in the lobby STEERS (`LobbyCarConfig.Handling`). Until 2026-10-08 it drove
	on the bare CarBones rig, and the owner's verdict was "very stiff, cars behave weird, it's not
	enjoyable". The handling stats are the server's half (`LobbyCarService._prepare` stamps the car's
	own `CarConfig` row and the lobby's damping); the steering is this file.

	=== THE STOCK STEERING PATH, READ FROM THE RIG'S OWN SOURCE — 2026-10-08 ===

	The owner pasted the place-side `Chassis` and `Driver` (they are not in git). What they do:

	    Driver   a `while … wait()` loop (~30Hz) passing the RAW key value — 0 or ±1, no ramp — to
	    Chassis  `UpdateSteering(steer, vel)`: steer /= 1 + 0.2·speed/MaxSpeed, then
	             SteeringPrismatic.TargetPosition = steer³ · MaxSteer
	    the rack a servo PrismaticConstraint that travels to that target at its own `Speed`, pushing
	             with its own `ServoMaxForce`, limited to ±MaxSteer (UpperLimit/LowerLimit).

	So no script ramps anything: the "slow for half a second, then suddenly steers more" the owner felt
	on the second cut is the RACK — a servo creeping toward lock against the tyres' scrub and then
	breaking free — and the cube turning any partial travel into almost nothing. Two earlier cuts eased
	the INPUT and wrapped the stock call; both were treating a symptom one step upstream of the cause.

	WHAT THIS DOES NOW: it OWNS the rack target while you drive. Every Heartbeat it writes
	`TargetPosition` itself, LINEAR in your input (no cube — a held key is full lock, half a stick is
	half), scaled down with speed, eased over a short `SteerRise`/`SteerFall`. The stock
	`UpdateSteering` is wrapped only to read the Driver's raw value (which also carries touch, from the
	kit's own on-screen wheel) and is otherwise NOT called, so nothing writes the cubed target over this
	one. And the rack servo is given `RackSpeed` and `RackForceScale` so the wheels arrive when told.

	Installed when the local player takes the DRIVER's seat of a lobby car (`LobbyCarConfig.
	OwnerAttribute` on the model — a race car is `DriveController`'s and never touched here), and
	everything is put back — the stock function, the rack's three servo properties — on leaving it.
	A rig without the parts keeps stock steering and says so once.

	`LobbyCarConfig.Handling.Enabled = false`: the bare rig, exactly as before.

	=== THE DRIFT'S EFFECTS ARE EVERYONE'S — 2026-10-14 ===
	The drift's PHYSICS is the driver's alone (`_drift`). Its smoke, sound and skid marks are drawn by
	`_effects` on every client, for every lobby car whose `Handling.Drift.Attribute` the server set from
	the driver's `ReportLobbyDrift`. Two sources of "is it drifting", in this order: the local car reads
	`self._drifting` (no round trip), every other car reads the attribute. `LobbyCarConfig.Handling.Drift`
	has why the effects are not built on the server.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local DriveConfig = require(ReplicatedStorage.shared.Configs.DriveConfig)
local LobbyCarConfig = require(ReplicatedStorage.shared.Configs.LobbyCarConfig)
local CollectorConfig = require(ReplicatedStorage.shared.Configs.CollectorConfig)
local ArcadeKit = require(ReplicatedStorage.shared.Modules.ArcadeKit)
--- For `StudsPerMaxSpeed`: the `MaxSpeed` attribute is not studs/s, and the conversion lives there.
local WindConfig = require(ReplicatedStorage.shared.Configs.WindConfig)
--- For the hotbar's touch row height, which the drift button stands on. The CONFIG and not
--- `CarryHotbarController`: only the pixel numbers are needed, not a live dependency on the bar.
local CarryConfig = require(ReplicatedStorage.shared.Configs.CarryConfig)

local LobbyDriveController = Shard.new("LobbyDriveController")

LobbyDriveController:withRemoteEvents({
	--- client -> server (on: boolean), on each change only. `LobbyCarService._onDriftReport` checks it.
	"ReportLobbyDrift",
})

--- Longest frame the steering ease will integrate over; a hitch must not jump the wheels to lock.
local MAX_STEP = 0.1

--- The drift's input binding (`LobbyCarConfig.Handling.Drift`). Above the PlayerModule's shift-lock
--- switch, and sunk, so holding Shift in a lobby car drifts instead of toggling mouse lock.
local DRIFT_ACTION = "LobbyCarDrift"
local DRIFT_PRIORITY = Enum.ContextActionPriority.High.Value + 100
--- Sign of a steer value that turns LEFT, which is +Y yaw (`DriveConfig.PositiveSteerIsLeft`).
local STEER_LEFT = if DriveConfig.PositiveSteerIsLeft then 1 else -1

--- Defined below with the drift; forward-declared because `_effects` uses them first.
local rearWheelsOf: (car: Model) -> { BasePart }
local buildSmoke: (wheel: BasePart) -> ParticleEmitter

--- The lobby car a seat belongs to, or nil for any other seat (a race car, a chair).
local function lobbyCarOf(seat: Instance): Model?
	local node = seat.Parent
	while node and node ~= workspace do
		if node:IsA("Model") and node:GetAttribute(LobbyCarConfig.OwnerAttribute) ~= nil then
			return node
		end
		node = node.Parent
	end
	return nil
end

--- `value` moved toward `target` by at most `step`. Pure.
local function approach(value: number, target: number, step: number): number
	if value < target then
		return math.min(value + step, target)
	end
	return math.max(value - step, target)
end

--[[ How much of full lock is allowed at the car's current speed: 1 up to `FullLockBelow` of its top
	speed, easing down to `HighSpeedLock` at its top speed. LINEAR now (the cube is gone), so 0.5 is
	half the lock in the wheels. ]]
function LobbyDriveController._lockFor(self): number
	local cfg = LobbyCarConfig.Handling
	local seat = self._seat
	local dial = self._car and self._car:GetAttribute("MaxSpeed")
	if not (seat and type(dial) == "number" and dial > 0) then
		return 1
	end
	if self._drifting then
		return LobbyCarConfig.Handling.Drift.Lock -- a drift steers at most of the lock (`Handling.Drift`)
	end
	local top = dial * WindConfig.StudsPerMaxSpeed
	local speed = math.abs(seat.AssemblyLinearVelocity:Dot(seat.CFrame.LookVector))
	local over = math.clamp((speed / top - cfg.FullLockBelow) / math.max(1e-3, 1 - cfg.FullLockBelow), 0, 1)
	return 1 + (cfg.HighSpeedLock - 1) * over
end

--[[ One frame of steering: ease toward the Driver's raw input, limit by speed, write the rack.
	Rising is "further from centre in the same direction"; anything else — letting go, or swapping
	sides — is falling, which is quicker: a car that will not straighten up when you let go is the
	stiffness this exists to remove. ]]
function LobbyDriveController._tick(self, dt: number)
	local rack = self._rack
	if not (rack and rack.Parent) then
		return
	end
	local cfg = LobbyCarConfig.Handling
	local target = math.clamp(self._raw, -1, 1)
	local current = self._steerOut
	local rising = math.abs(target) > math.abs(current) and (current == 0 or math.sign(target) == math.sign(current))
	local seconds = if rising then cfg.SteerRise else cfg.SteerFall
	self._steerOut = approach(current, target, if seconds > 0 then math.min(dt, MAX_STEP) / seconds else 1)

	self:_drift(dt)
	--- The rack's own limit is what the chassis set from `MaxSteer`; `LockScale` trims it for the lobby.
	rack.TargetPosition = self._steerOut * self:_lockFor() * rack.UpperLimit * cfg.LockScale
end

--[[ The drift, one frame (`LobbyCarConfig.Handling.Drift`): on while the key is held and the car is
	moving forward faster than `MinSpeed`; the rear grip drops, the yaw assist turns the car into the
	steer, smoke comes off the back. Every change is undone the frame it goes off. ]]
function LobbyDriveController._drift(self, dt: number)
	local cfg = LobbyCarConfig.Handling.Drift
	local car, seat = self._car, self._seat
	local root = car and car.PrimaryPart
	local on = false
	if cfg and cfg.Enabled and self._driftHeld and root and seat then
		--[[ Speed OVER THE GROUND, not along the nose (2026-10-14): mid-drift the car points across its own
			path, so the nose-speed fell under `MinSpeed`, the drift switched off, grip came back, the car
			straightened, and it switched on again — several times a second, restarting the sound. And
			HELD below the start speed once on (`HoldShare`), for the same flicker at the threshold. ]]
		local up = seat.CFrame.UpVector
		local velocity = seat.AssemblyLinearVelocity
		local speed = (velocity - up * velocity:Dot(up)).Magnitude
		on = speed > (if self._drifting then cfg.MinSpeed * cfg.HoldShare else cfg.MinSpeed)
	end
	if on ~= self._drifting then
		self._drifting = on
		self:_setRearGrip(on)
		self:getRemoteEvent("ReportLobbyDrift"):Fire(on)
	end
	if not on then
		return
	end
	local up = seat.CFrame.UpVector
	local spin = root.AssemblyAngularVelocity
	local yaw = spin:Dot(up)
	local want = self._steerOut * STEER_LEFT * cfg.YawRate
	local nextYaw = yaw + (want - yaw) * math.min(1, cfg.YawGain * math.min(dt, MAX_STEP))
	root.AssemblyAngularVelocity = spin + up * (nextYaw - yaw)
end

-- === The effects, for every drifting lobby car (header) ======================

--[[ Every frame: start the effects on each lobby car that has begun drifting, end them on each that
	has stopped, lay skid marks under the ones still going. One car per player at most, so walking the
	folder each frame is a handful of attribute reads. ]]
function LobbyDriveController._effects(self)
	local cfg = LobbyCarConfig.Handling.Drift
	local folder = workspace:FindFirstChild(LobbyCarConfig.FolderName)
	local seen = {}
	for _, car in if folder then folder:GetChildren() else {} do
		local on = if car == self._car then self._drifting else car:GetAttribute(cfg.Attribute) == true
		if on and car:IsA("Model") then
			seen[car] = true
			local fx = self._fx[car]
			if not fx then
				fx = self:_startEffects(car)
				self._fx[car] = fx
			end
			self:_skid(car, fx.last)
		end
	end
	for car, fx in self._fx do
		if not seen[car] then
			self:_endEffects(fx)
			self._fx[car] = nil
		end
	end
end

--- Smoke on the rear wheels and the looped sound on the car, both on. The handle `_endEffects` takes.
function LobbyDriveController._startEffects(self, car: Model)
	local cfg = LobbyCarConfig.Handling.Drift
	local fx = { smoke = {}, sound = nil :: Sound?, last = {} :: { [BasePart]: Vector3 } }
	if cfg.Smoke then
		for _, wheel in rearWheelsOf(car) do
			table.insert(fx.smoke, buildSmoke(wheel))
		end
	end
	local root = car.PrimaryPart
	local sfx = cfg.Sound
	if sfx and sfx.SoundId ~= 0 and root then
		local sound = Instance.new("Sound")
		sound.Name = "DriftSound"
		sound.SoundId = "rbxassetid://" .. sfx.SoundId
		sound.Volume = sfx.Volume
		sound.Looped = true
		--- Tapered so it is really silent at `SilentBeyond`, not a whisper across the whole map.
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = sfx.FullVolumeWithin or 10
		sound.RollOffMaxDistance = sfx.SilentBeyond or 160
		if sfx.Loop then
			sound.PlaybackRegionsEnabled = true
			sound.LoopRegion = NumberRange.new(sfx.Loop[1], sfx.Loop[2])
		end
		sound.Parent = root
		--- From the top, into the loop (`Drift.Sound.Loop`).
		sound:Play()
		fx.sound = sound
	end
	return fx
end

--- Off at once: the sound stops dead (2026-10-14, the clip's ending lingered after a short drift); the
--- smoke stops emitting and is removed once its last puffs are gone; laid marks fade on their own.
function LobbyDriveController._endEffects(self, fx)
	if fx.sound then
		fx.sound:Destroy()
	end
	for _, emitter in fx.smoke do
		emitter.Enabled = false
		task.delay(emitter.Lifetime.Max, emitter.Destroy, emitter)
	end
end

-- === Skid marks (`Drift.Skid`) ===============================================

--- One strip from `from` to `to`, lying on the surface with normal `normal`, held then faded.
function LobbyDriveController._skidStrip(self, from: Vector3, to: Vector3, normal: Vector3)
	local cfg = LobbyCarConfig.Handling.Drift.Skid
	local strip = Instance.new("Part")
	strip.Name = "Skid"
	strip.Anchored, strip.CanCollide, strip.CanQuery, strip.CanTouch = true, false, false, false
	strip.CastShadow = false
	strip.Material = Enum.Material.SmoothPlastic
	strip.Color = cfg.Color
	strip.Transparency = cfg.Transparency
	strip.Size = Vector3.new(cfg.Width, 0.02, (to - from).Magnitude + cfg.Width * 0.5)
	strip.CFrame = CFrame.lookAt((from + to) / 2, to, normal)
	strip.Parent = self._skidFolder
	table.insert(self._skids, strip)
	if #self._skids > cfg.Max then
		table.remove(self._skids, 1):Destroy()
	end
	task.delay(cfg.Hold, function()
		if strip.Parent then
			local fade = TweenService:Create(strip, TweenInfo.new(cfg.Fade), { Transparency = 1 })
			fade.Completed:Once(function()
				local at = table.find(self._skids, strip)
				if at then
					table.remove(self._skids, at)
				end
				strip:Destroy()
			end)
			fade:Play()
		end
	end)
end

--- Lay the next strip under each rear wheel that has moved `Step` since its last one. A jump larger
--- than a few steps (airborne, a respawn) starts a fresh line instead of drawing across the gap.
function LobbyDriveController._skid(self, car: Model, lastAt: { [BasePart]: Vector3 })
	local cfg = LobbyCarConfig.Handling.Drift.Skid
	if not (cfg and cfg.Enabled) then
		return
	end
	if not self._skidFolder then
		self._skidFolder = Instance.new("Folder")
		self._skidFolder.Name = "LobbySkidMarks"
		self._skidFolder.Parent = workspace
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	--- Characters too, since the car's driver and passengers are anyone's, not just ours.
	local ignore = { car, self._skidFolder }
	for _, player in Players:GetPlayers() do
		table.insert(ignore, player.Character)
	end
	params.FilterDescendantsInstances = ignore
	for _, wheel in rearWheelsOf(car) do
		local hit = workspace:Raycast(wheel.Position, Vector3.new(0, -(wheel.Size.Y / 2 + 2), 0), params)
		local last = lastAt[wheel]
		if not hit then
			lastAt[wheel] = nil
		else
			local point = hit.Position + hit.Normal * 0.03
			if not last then
				lastAt[wheel] = point
			else
				local gap = (point - last).Magnitude
				if gap > cfg.Step * 8 then
					lastAt[wheel] = point
				elseif gap >= cfg.Step then
					self:_skidStrip(last, point, hit.Normal)
					lastAt[wheel] = point
				end
			end
		end
	end
end

function LobbyDriveController._rearWheels(self): { BasePart }
	return if self._car then rearWheelsOf(self._car) else {}
end

--- The two rear wheels (`Chassis/SuspensionRL|RR/Wheel`), or none on a rig named otherwise.
rearWheelsOf = function(car: Model): { BasePart }
	local chassis = car:FindFirstChild("Chassis")
	local wheels = {}
	for _, corner in { "RL", "RR" } do
		local suspension = chassis and chassis:FindFirstChild("Suspension" .. corner)
		local wheel = suspension and suspension:FindFirstChild("Wheel")
		if wheel and wheel:IsA("BasePart") then
			table.insert(wheels, wheel)
		end
	end
	return wheels
end

--- Rear grip down for a drift, or back to exactly what it was.
function LobbyDriveController._setRearGrip(self, low: boolean)
	if low then
		self._gripWas = {}
		for _, wheel in self:_rearWheels() do
			local old = wheel.CustomPhysicalProperties or PhysicalProperties.new(wheel.Material)
			self._gripWas[wheel] = wheel.CustomPhysicalProperties
			wheel.CustomPhysicalProperties = PhysicalProperties.new(
				old.Density,
				old.Friction * LobbyCarConfig.Handling.Drift.RearGrip,
				old.Elasticity,
				old.FrictionWeight,
				old.ElasticityWeight
			)
		end
		return
	end
	for wheel, was in self._gripWas or {} do
		if wheel.Parent then
			wheel.CustomPhysicalProperties = was
		end
	end
	self._gripWas = nil
end

--[[ The on-screen DRIFT button (`Drift.TouchButton`), on a touch device only. Held: the press that
	began on it is followed to its end wherever the finger goes, so sliding off the button still lets go. ]]
function LobbyDriveController._buildTouchButton(self)
	local cfg = LobbyCarConfig.Handling.Drift.TouchButton
	if not (cfg and cfg.Enabled and UserInputService.PreferredInput == Enum.PreferredInput.Touch) then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "LobbyDrift"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	local holder = Instance.new("Frame")
	local hotbar = CarryConfig.Hotbar
	--[[ Bottom edge pinned `cfg.Gap` px above the hotbar's touch row (tile + the bar's 8px frame +
		`Margin`), not at a screen share. The bar is pixel-sized and drawn at 960 over this gui's 20, so
		on a phone a share low enough to sit beside it on a tablet lands under it (header of
		`LobbyCarConfig.Handling.Drift.TouchButton`). `AboveHotbar = false`: the old centred share. ]]
	holder.AnchorPoint = if cfg.AboveHotbar then Vector2.new(0.5, 1) else Vector2.new(0.5, 0.5)
	holder.Position = if cfg.AboveHotbar
		then UDim2.new(cfg.Position.X, 0, 1 - hotbar.Lift, -(hotbar.Margin + (hotbar.TouchSize or hotbar.Size) + 8 + cfg.Gap))
		else UDim2.fromScale(cfg.Position.X, cfg.Position.Y)
	holder.Size = UDim2.fromScale(cfg.Height * cfg.Aspect, cfg.Height)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = cfg.Aspect
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = holder
	local button, caption = ArcadeKit.button(holder, "Claim", 0, 0, 1, 1)
	caption.Text = cfg.Title
	local pressing: InputObject? = nil
	button.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
			pressing = input
			self._driftHeld = true
			self._touchDrift = true
		end
	end)
	self._touchEnd = UserInputService.InputEnded:Connect(function(input: InputObject)
		if input == pressing then
			pressing = nil
			self._driftHeld = false
			self._touchDrift = false
		end
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self._touchGui = gui
end

--- Tyre smoke on one rear wheel, on.
buildSmoke = function(wheel: BasePart): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "DriftSmoke"
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(230, 230, 235))
	--[[ HEAVIER, 2026-10-14 (the owner: "make drifting release some more smoke"). WAS rate 40, size
		1.5 -> 5, life 0.6-1.1s, starting at 0.35 see-through. IS twice the puffs, bigger, longer-lived
		and denser at birth, so a drift leaves a cloud hanging behind it rather than a wisp. It is
		drawn per drifting car on every client nearby, so do not keep doubling it. ]]
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.6, 0.6), NumberSequenceKeypoint.new(1, 1) })
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 8) })
	emitter.Lifetime = NumberRange.new(1, 1.8)
	emitter.Rate = 80
	emitter.RotSpeed = NumberRange.new(-40, 40)
	emitter.Speed = NumberRange.new(2, 5)
	emitter.SpreadAngle = Vector2.new(30, 30)
	emitter.Parent = wheel
	return emitter
end

--[[ The compression stop (`LobbyCarConfig.Handling.Struts`): each strut's limits on, its floor
	`Travel` below its length at rest. Read when the driver takes the seat, which is when the car is
	sitting on its wheels. Only the driving client sets it, and that is enough: the driver owns the
	car's physics while they drive it. Put back exactly by `_teardown`. ]]
function LobbyDriveController._limitStruts(self, car: Model)
	local cfg = LobbyCarConfig.Handling.Struts
	if not (cfg and cfg.Enabled) then
		return
	end
	local constraints = car:FindFirstChild("Constraints")
	self._strutsWas = {}
	for _, spring in (if constraints then constraints:GetChildren() else {}) do
		if spring:IsA("SpringConstraint") and string.find(spring.Name, "^StrutSpring") then
			self._strutsWas[spring] = { min = spring.MinLength, enabled = spring.LimitsEnabled }
			local rest = math.clamp(spring.CurrentLength, spring.FreeLength - cfg.MaxSag, spring.FreeLength)
			spring.MinLength = math.max(0.05, rest - cfg.Travel)
			spring.LimitsEnabled = true
		end
	end
end

--- Take over this car's steering (header). False, and stock steering, for a rig we cannot hook.
function LobbyDriveController._install(self, car: Model, seat: VehicleSeat): boolean
	self:_teardown()
	local cfg = LobbyCarConfig.Handling
	local scripts = car:FindFirstChild("Scripts")
	local module = scripts and scripts:FindFirstChild("Chassis")
	local constraints = car:FindFirstChild("Constraints")
	local rack = constraints and constraints:FindFirstChild("SteeringPrismatic")
	if not (module and module:IsA("ModuleScript") and rack and rack:IsA("PrismaticConstraint")) then
		return false
	end
	--- The car's own module, required as the stock Driver requires it (same instance, same cached
	--- table); a rig that throws on require is one the Driver cannot run either.
	local ok, chassis = pcall(require, module)
	if not (ok and type(chassis) == "table" and type(chassis.UpdateSteering) == "function") then
		if not self._warned then
			self._warned = true
			self.log:warn("A lobby car's chassis could not be hooked; it steers with the stock rack.")
		end
		return false
	end

	self._car, self._seat, self._chassis, self._stock = car, seat, chassis, chassis.UpdateSteering
	self._raw, self._steerOut = 0, 0
	--- Read the Driver's raw value, write nothing: `_tick` owns the target (header).
	chassis.UpdateSteering = function(steer)
		self._raw = if type(steer) == "number" then steer else 0
	end
	--[[ The DRIFT button is also the gas (2026-10-14: "on mobile I can't accelerate and drift at the same
		time"). Both thumbs are taken — steering on the left, the pedals on the right — so holding DRIFT
		with the right thumb holds full throttle too, which is what W + Shift is on a keyboard. Only while
		the TOUCH button is held; the keyboard and gamepad keep their own throttle. ]]
	local stockThrottle = chassis.UpdateThrottle
	self._stockThrottle = stockThrottle
	--- Collector (owner, 2026-11-01: "auto drive forward, but i can control direction"): full gas unless
	--- the player is braking or reversing, so S still stops the car.
	local auto = CollectorConfig.Enabled and CollectorConfig.Drive.AutoThrottle
	if type(stockThrottle) == "function" then
		chassis.UpdateThrottle = function(speed, throttle)
			if self._touchDrift or (auto and not (type(throttle) == "number" and throttle < 0)) then
				throttle = 1
			end
			return stockThrottle(speed, throttle)
		end
	end

	self._rack = rack
	self._rackWas = {
		LinearResponsiveness = rack.LinearResponsiveness,
		Speed = rack.Speed,
		ServoMaxForce = rack.ServoMaxForce,
	}
	rack.LinearResponsiveness = cfg.RackResponsiveness or DriveConfig.SteerRackResponsiveness
	rack.Speed = math.max(rack.Speed, cfg.RackSpeed)
	rack.ServoMaxForce = rack.ServoMaxForce * cfg.RackForceScale
	self:_limitStruts(car)

	local drift = cfg.Drift
	self._driftHeld, self._drifting = false, false
	if drift and drift.Enabled then
		ContextActionService:BindActionAtPriority(DRIFT_ACTION, function(_, state)
			self._driftHeld = state == Enum.UserInputState.Begin
			return Enum.ContextActionResult.Sink
		end, false, DRIFT_PRIORITY, table.unpack(drift.Keys))
		self:_buildTouchButton()
	end

	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_tick(dt)
	end)
	return true
end

--- Hand the car back exactly as it was: the stock function and the rack's authored servo.
function LobbyDriveController._teardown(self)
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	--- The drift first, while the car it changed is still known: grip back, smoke gone, key released.
	ContextActionService:UnbindAction(DRIFT_ACTION)
	if self._touchGui then
		self._touchGui:Destroy()
		self._touchGui = nil
	end
	if self._touchEnd then
		self._touchEnd:Disconnect()
		self._touchEnd = nil
	end
	if self._drifting then
		self:_setRearGrip(false)
		--- Everyone else's effects end with it; ours end on `_effects`' next frame.
		self:getRemoteEvent("ReportLobbyDrift"):Fire(false)
	end
	self._driftHeld, self._drifting = false, false
	local chassis, stock = self._chassis, self._stock
	if chassis and stock then
		chassis.UpdateSteering = stock
	end
	if chassis and self._stockThrottle then
		chassis.UpdateThrottle = self._stockThrottle
	end
	self._stockThrottle, self._touchDrift = nil, false
	local rack, was = self._rack, self._rackWas
	if rack and rack.Parent and was then
		for property, value in was do
			(rack :: any)[property] = value
		end
	end
	--- The struts as the rig had them (`_limitStruts`).
	for spring, before in self._strutsWas or {} do
		if spring.Parent then
			spring.MinLength = before.min
			spring.LimitsEnabled = before.enabled
		end
	end
	self._strutsWas = nil
	self._car, self._seat, self._chassis, self._stock = nil, nil, nil, nil
	self._rack, self._rackWas = nil, nil
end

--- PUBLIC (HopController): the lobby car the local player is driving right now, or nil.
function LobbyDriveController.getCar(self): Model?
	return self._car
end

--- PUBLIC (HopController): the driver's steer right now, -1..1, positive toward `DriveConfig.PositiveSteerIsLeft`.
function LobbyDriveController.getSteer(self): number
	return math.clamp(self._raw or 0, -1, 1)
end

--- Follow one character's seat: install on the driver's seat of a lobby car, tear down on leaving.
function LobbyDriveController._watch(self, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	humanoid.Seated:Connect(function(active: boolean, seat: Instance?)
		if not (active and seat and seat:IsA("VehicleSeat")) then
			self:_teardown()
			return
		end
		local car = lobbyCarOf(seat)
		if car then
			self:_install(car, seat)
		end
	end)
end

LobbyDriveController:withLifecycle({
	init = function(self)
		self._skids = {} :: { BasePart }
		self._fx = {} -- [car Model] = `_startEffects`' handle, for each car drifting on this screen
		self._driftHeld, self._drifting = false, false
		self._raw = 0
		self._steerOut = 0
		self._warned = false
	end,

	start = function(self)
		if not LobbyCarConfig.Handling.Enabled then
			return
		end
		local drift = LobbyCarConfig.Handling.Drift
		if drift and drift.Enabled then
			RunService.Heartbeat:Connect(function()
				self:_effects()
			end)
		end
		local player = Players.LocalPlayer
		if player.Character then
			task.spawn(self._watch, self, player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			self:_teardown()
			self:_watch(character)
		end)
	end,
})

return LobbyDriveController
