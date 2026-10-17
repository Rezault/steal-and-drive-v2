--[[
	TestEngineController  (client)
	------------------------------
	A STAND-IN ENGINE NOTE, for testing a clip before the real per-engine-type sets exist (2026-10-14,
	the owner: "use one sound for now and change the pitch to match RPMs", `DriveConfig.TestEngine`).

	One looped clip on whatever car the local player is DRIVING (race or lobby), its pitch read off the
	same simulated six-speed the dashboard uses (`Modules/AutomaticGearbox`, `DriveConfig.Gearbox`): it
	climbs through each gear, drops on the upshift, and settles to `IdlePitch` near a standstill. The
	kit's own engine layers on that car are muted ON THIS CLIENT ONLY while it runs — found as the
	looped sounds already on the car that are not ours (`KEEP`), since the kit's layer names live in
	the place, not in git. Everything is put back when the player leaves the seat.

	Local only: other players still hear the kit engine. `DriveConfig.TestEngine.Enabled = false`: the
	kit engine, exactly as before.

	=== REAL ENGINES, PER CAR — 2026-10-14 ===
	A car with a pack in `Configs/EngineSoundConfig` (the German straight six, on the six cars that
	file lists) drives on that instead of the stand-in clip: `Modules/EngineAudio`'s layers, fed the
	same gearbox. Every other car is on the stand-in, exactly as before. Same muting of the kit, same
	silence under the loading screen, same local-only.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local DriveConfig = require(ReplicatedStorage.shared.Configs.DriveConfig)
--- `StudsPerMaxSpeed`: the `MaxSpeed` attribute is not studs/s (`DriveController` uses the same).
local WindConfig = require(ReplicatedStorage.shared.Configs.WindConfig)
local AutomaticGearbox = require(ReplicatedStorage.shared.Modules.AutomaticGearbox)
--- A car's pack, and the layered engine that plays one (header, "REAL ENGINES").
local EngineSoundConfig = require(ReplicatedStorage.shared.Configs.EngineSoundConfig)
local EngineAudio = require(ReplicatedStorage.shared.Modules.EngineAudio)
--- The body a car is: a lobby car carries it as `LobbyCarConfig.BodyAttribute`, a race car as `Body`.
local LobbyCarConfig = require(ReplicatedStorage.shared.Configs.LobbyCarConfig)
local CarStats = require(ReplicatedStorage.shared.Modules.CarStats)

local TestEngineController = Shard.new("TestEngineController")

--- The dashboard's conversion (`DriveController.MPH_PER_STUD`), so the gears change where its do.
local MPH_PER_STUD = 0.6263
--- Looped sounds on a car that are NOT engine layers and must never be muted.
local KEEP = { CarRadio = true, DriftSound = true, TestEngine = true }

--- The car model a driver's seat belongs to: the nearest ancestor holding a `Chassis`.
local function carOf(seat: Instance): Model?
	local node = seat.Parent
	while node and node ~= workspace do
		if node:IsA("Model") and node:FindFirstChild("Chassis") then
			return node
		end
		node = node.Parent
	end
	return nil
end

--- Mute one kit engine layer, remembering its volume to give back.
function TestEngineController._mute(self, sound: Instance)
	local ours = string.sub(sound.Name, 1, #EngineAudio.Prefix) == EngineAudio.Prefix
	if sound:IsA("Sound") and sound.Looped and not KEEP[sound.Name] and not ours and self._muted[sound] == nil then
		self._muted[sound] = sound.Volume
		sound.Volume = 0
	end
end

function TestEngineController._attach(self, car: Model, seat: BasePart)
	local cfg = DriveConfig.TestEngine
	--- On the driver's seat, which every rig has; a car's PrimaryPart is not always set.
	local root = seat
	self._car, self._gear, self._pitch = car, 1, cfg.IdlePitch
	self._lastMph = nil
	local body = car:GetAttribute(LobbyCarConfig.BodyAttribute)
	local pack = EngineSoundConfig.packFor(if type(body) == "string" then body else CarStats.bodyOf(car))
	if pack then
		self._engine = EngineAudio.new(root, pack, cfg.FullVolumeWithin or 10)
	end
	local sound = if pack then nil else Instance.new("Sound")
	if sound then
		sound.Name = "TestEngine"
		sound.SoundId = "rbxassetid://" .. cfg.SoundId
		sound.Volume = cfg.Volume
		sound.RollOffMinDistance = cfg.FullVolumeWithin or 10
		sound.Looped = true
		sound.PlaybackSpeed = cfg.IdlePitch
		sound.Parent = root
		sound:Play()
		self._sound = sound
		--- Say what happened, so a silent clip is told apart from a missing hook: a test tool, so it talks.
		print(string.format("[TestEngine] on %s (sound %d)", car.Name, cfg.SoundId))
		task.delay(3, function()
			if self._sound == sound and not sound.IsLoaded then
				warn(string.format("[TestEngine] " .. 
					"Test engine sound %d has not loaded after 3s; it is probably private or not shared with this experience.",
					cfg.SoundId
				))
			end
		end)
	end
	if cfg.MuteKit then
		for _, inst in car:GetDescendants() do
			self:_mute(inst)
		end
		--- The kit can build its layers a beat after the seat is taken; catch those too.
		self._added = car.DescendantAdded:Connect(function(inst)
			task.defer(function()
				self:_mute(inst)
			end)
		end)
	end
end

function TestEngineController._detach(self)
	if self._added then
		self._added:Disconnect()
		self._added = nil
	end
	for sound, volume in self._muted do
		if sound.Parent then
			sound.Volume = volume
		end
	end
	self._muted = {}
	if self._sound then
		self._sound:Destroy()
		self._sound = nil
	end
	if self._engine then
		self._engine:destroy()
		self._engine = nil
	end
	self._car = nil
end

--- Every frame: follow the seat, and set the pitch from the simulated gearbox.
function TestEngineController._step(self, dt: number)
	local cfg = DriveConfig.TestEngine
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local car = if seat and seat:IsA("VehicleSeat") then carOf(seat) else nil
	--- Silent once banked (2026-10-14): the car rides the truck out with the driver still seated.
	local getaway = Shard.get("GetawayController")
	if car and getaway and getaway:isBanked() then
		car = nil
	end
	if car ~= self._car then
		self:_detach()
		if car and seat then
			self:_attach(car, seat)
		end
	end
	local sound = self._sound
	local engine = self._engine
	if not ((sound or engine) and seat) then
		return
	end
	--[[ Silent under the entry's loading screen (2026-10-14, the owner heard it there): the driver is
		seated in the built car before the screen lifts. Kept ATTACHED and only turned down, so the kit
		engine it mutes stays muted rather than coming back for the length of the load. ]]
	local raceUI = Shard.get("RaceUIController")
	local loading = raceUI ~= nil and raceUI:isLoading()
	if sound then
		sound.Volume = if loading then 0 else cfg.Volume
	end

	local mph = math.abs(seat.AssemblyLinearVelocity:Dot(seat.CFrame.LookVector)) * MPH_PER_STUD
	local dial = car and car:GetAttribute("MaxSpeed")
	local box = DriveConfig.Gearbox
	local top = if type(dial) == "number" and dial > 0 then dial * WindConfig.StudsPerMaxSpeed * MPH_PER_STUD else box.TopMph
	local gear, through = AutomaticGearbox.sample(mph, self._gear, top, box.Gears, box.DownshiftHysteresis)
	self._gear = gear
	if engine then
		--- Off the throttle only while it is really slowing (`EngineSoundConfig.Mix.DecelMph`).
		local last = self._lastMph or mph
		self._lastMph = mph
		local accelerating = (mph - last) / math.max(dt, 1e-3) > -EngineSoundConfig.Mix.DecelMph
		engine:update(through, mph < cfg.IdleBelowMph, accelerating, if loading then 0 else 1, dt, gear)
		return
	end
	--- Idle near a standstill; otherwise low -> high through the gear, each gear a touch higher.
	local want = if mph < cfg.IdleBelowMph
		then cfg.IdlePitch
		else cfg.LowPitch + (cfg.HighPitch - cfg.LowPitch) * through + cfg.PerGear * (gear - 1)
	self._pitch += (want - self._pitch) * math.min(1, cfg.Response * dt)
	sound.PlaybackSpeed = self._pitch
end

TestEngineController:withLifecycle({
	init = function(self)
		self._muted = {} :: { [Sound]: number }
		self._gear, self._pitch = 1, 1
	end,

	start = function(self)
		if not (DriveConfig.TestEngine and DriveConfig.TestEngine.Enabled) then
			return
		end
		RunService.Heartbeat:Connect(function(dt)
			self:_step(dt)
		end)
	end,
})

return TestEngineController
