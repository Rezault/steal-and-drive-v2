-- Local driver's engine. Steals redress a rig in place, so body and seat are part of audio identity.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Shard = require(ReplicatedStorage.Packages.Shard)
local DriveConfig = require(ReplicatedStorage.shared.Configs.DriveConfig)
local WindConfig = require(ReplicatedStorage.shared.Configs.WindConfig)
local AutomaticGearbox = require(ReplicatedStorage.shared.Modules.AutomaticGearbox)
local EngineSoundConfig = require(ReplicatedStorage.shared.Configs.EngineSoundConfig)
local EngineAudio = require(ReplicatedStorage.shared.Modules.EngineAudio)
local LobbyCarConfig = require(ReplicatedStorage.shared.Configs.LobbyCarConfig)
local AudioConfig = require(ReplicatedStorage.shared.Configs.AudioConfig)

local TestEngineController = Shard.new("TestEngineController")
local MPH_PER_STUD = 0.6263
local KEEP = { CarRadio = true, DriftSound = true, TestEngine = true }
local function approach(value, target, rate, dt)
	return value + (target - value) * (1 - math.exp(-rate * math.max(dt, 0)))
end
local function carOf(seat)
	local node = seat.Parent
	while node and node ~= workspace do
		if node:IsA("Model") and node:FindFirstChild("Chassis") then return node end
		node = node.Parent
	end
	return nil
end
function TestEngineController._bodyOf(_self, car)
	local body = car:GetAttribute("Body")
	if type(body) == "string" and body ~= "" then return body end
	body = car:GetAttribute(LobbyCarConfig.BodyAttribute)
	return if type(body) == "string" and body ~= "" then body else car.Name
end

-- The kit rewrites Volume every update. A silent group keeps it muted regardless of write order.
function TestEngineController._mute(self, sound)
	if not sound:IsA("Sound") or not sound.Looped or KEEP[sound.Name]
		or sound.Name:sub(1, #EngineAudio.Prefix) == EngineAudio.Prefix or self._muted[sound] then return end
	if not self._silentGroup then
		local group = Instance.new("SoundGroup")
		group.Name = "LocalDriverKitMute"
		group.Volume = 0
		group.Parent = SoundService
		self._silentGroup = group
	end
	local originalGroup = sound.SoundGroup
	-- A late kit loop can be cloned from a template we already muted. Never restore our mute bus.
	if originalGroup == self._silentGroup then
		originalGroup = SoundService:FindFirstChild(AudioConfig.Sfx.GroupName)
	end
	self._muted[sound] = { group = originalGroup }
	sound.SoundGroup = self._silentGroup
end

function TestEngineController._clearTails(self)
	for _, tail in self._tails or {} do
		if tail.engine then tail.engine:destroy() end
		if tail.sound then tail.sound:Destroy() end
	end
	self._tails = {}
end

function TestEngineController._replaceEngine(self, body, loading)
	local cfg = DriveConfig.TestEngine
	local pack = EngineSoundConfig.packFor(body)
	self._body = body
	if self._pack == pack and (self._engine or self._sound) then return end
	local tail = { engine = self._engine, sound = self._sound }
	if tail.engine or tail.sound then
		table.insert(self._tails, tail)
		if tail.engine then tail.engine:fadeOut(EngineSoundConfig.Mix.SwapSeconds) end
		if tail.sound then
			TweenService:Create(tail.sound, TweenInfo.new(EngineSoundConfig.Mix.SwapSeconds), { Volume = 0 }):Play()
		end
		task.delay(EngineSoundConfig.Mix.SwapSeconds, function()
			if tail.engine then tail.engine:destroy() end
			if tail.sound then tail.sound:Destroy() end
			local index = table.find(self._tails, tail)
			if index then table.remove(self._tails, index) end
		end)
	end
	self._engine, self._sound, self._pack = nil, nil, pack
	self._pitch = cfg.IdlePitch
	if pack then
		local moving = self._seat.AssemblyLinearVelocity.Magnitude * MPH_PER_STUD >= cfg.IdleBelowMph
		-- A moving steal changes engine note without playing an ignition sound over the chase.
		self._engine = EngineAudio.new(self._seat, pack, cfg.FullVolumeWithin or 10, not moving and not loading)
	else
		local sound = Instance.new("Sound")
		sound.Name = "TestEngine"
		sound.SoundId = "rbxassetid://" .. cfg.SoundId
		sound.Volume = 0
		sound.RollOffMinDistance = cfg.FullVolumeWithin or 10
		sound.Looped = true
		sound.PlaybackSpeed = cfg.IdlePitch
		sound.Parent = self._seat
		sound:Play()
		self._sound = sound
	end
end

function TestEngineController._attach(self, car, seat, loading)
	self._car, self._seat, self._gear = car, seat, 1
	self._lastMph, self._acceleration, self._loaded = nil, 0, true
	self:_replaceEngine(self:_bodyOf(car), loading)
	if DriveConfig.TestEngine.MuteKit then
		for _, inst in car:GetDescendants() do self:_mute(inst) end
		self._added = car.DescendantAdded:Connect(function(inst)
			task.defer(function()
				if self._car == car and inst:IsDescendantOf(car) then self:_mute(inst) end
			end)
		end)
	end
end

function TestEngineController._detach(self)
	if self._added then self._added:Disconnect() self._added = nil end
	for sound, original in self._muted do
		if sound.Parent and sound.SoundGroup == self._silentGroup then sound.SoundGroup = original.group end
	end
	self._muted = {}
	if self._sound then self._sound:Destroy() end
	if self._engine then self._engine:destroy() end
	self:_clearTails()
	self._car, self._seat, self._body, self._pack, self._sound, self._engine = nil, nil, nil, nil, nil, nil
end

-- Exposed separately so both same-rig steals and completely different seats use the same handoff.
function TestEngineController._sync(self, car, seat, loading)
	if car ~= self._car or seat ~= self._seat then
		self:_detach()
		if car and seat then self:_attach(car, seat, loading) end
	elseif car then
		local body = self:_bodyOf(car)
		if body ~= self._body then
			self._gear, self._lastMph, self._acceleration = 1, nil, 0
			self:_replaceEngine(body, loading)
		end
	end
	if loading then self:_clearTails() end
end

function TestEngineController._driveSound(self, mph, top, throttle, loading, dt)
	local cfg, mix, box = DriveConfig.TestEngine, EngineSoundConfig.Mix, DriveConfig.Gearbox
	local gear, through = AutomaticGearbox.sample(mph, self._gear, top, box.Gears, box.DownshiftHysteresis)
	self._gear = gear
	local acceleration = if self._lastMph then (mph - self._lastMph) / math.max(dt, 1e-3) else 0
	self._lastMph = mph
	self._acceleration = approach(self._acceleration, math.clamp(acceleration, -100, 100), mix.SpeedResponse, dt)
	-- Hysteresis avoids load/coast chatter from tiny physics speed changes; braking is immediate.
	if throttle < -0.1 then self._loaded = false
	elseif throttle > 0.1 or self._acceleration > -mix.DecelMph * 0.4 then self._loaded = true
	elseif self._acceleration < -mix.DecelMph then self._loaded = false end
	local moving = math.clamp((mph - mix.IdleBlendFromMph) / (mix.IdleBlendToMph - mix.IdleBlendFromMph), 0, 1)
	if self._engine then
		self._engine:update(through, mph < cfg.IdleBelowMph, self._loaded, if loading then 0 else 1, dt, gear, moving)
	elseif self._sound then
		local runningPitch = cfg.LowPitch + (cfg.HighPitch - cfg.LowPitch) * through + cfg.PerGear * (gear - 1)
		local target = cfg.IdlePitch + (runningPitch - cfg.IdlePitch) * moving
		self._pitch = approach(self._pitch, target, cfg.Response, dt)
		self._sound.PlaybackSpeed = self._pitch
		self._sound.Volume = if loading then 0 else approach(self._sound.Volume, cfg.Volume, mix.VolumeResponse, dt)
	end
end

function TestEngineController._step(self, dt)
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local car = if seat and seat:IsA("VehicleSeat") then carOf(seat) else nil
	local getaway = Shard.get("GetawayController")
	if car and getaway and getaway:isBanked() then car = nil seat = nil end
	local raceUI = Shard.get("RaceUIController")
	local loading = raceUI ~= nil and raceUI:isLoading()
	self:_sync(car, if car then seat else nil, loading)
	if not (car and seat and (self._engine or self._sound)) then return end
	local mph = math.abs(seat.AssemblyLinearVelocity:Dot(seat.CFrame.LookVector)) * MPH_PER_STUD
	local dial = car:GetAttribute("MaxSpeed")
	local top = if type(dial) == "number" and dial > 0 then dial * WindConfig.StudsPerMaxSpeed * MPH_PER_STUD else DriveConfig.Gearbox.TopMph
	local drive = Shard.get("DriveController")
	local throttle = if drive and drive._car == car then drive:getThrottleInput() else seat.ThrottleFloat
	self:_driveSound(mph, top, throttle, loading, dt)
end

TestEngineController:withLifecycle({
	init = function(self)
		self._muted, self._tails = {}, {}
		self._gear, self._pitch = 1, 1
	end,
	start = function(self)
		if not (DriveConfig.TestEngine and DriveConfig.TestEngine.Enabled) then return end
		RunService.Heartbeat:Connect(function(dt) self:_step(dt) end)
	end,
})
return TestEngineController