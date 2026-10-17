--[[
	EngineAudio  (client)
	---------------------
	One car's layered engine (`Configs/EngineSoundConfig` has what a pack is and which cars have
	one). Built on a part of the car, fed where the RPM is every frame, destroyed when the driver
	leaves. EVERY LAYER LOOPS THE WHOLE TIME AND ONLY ITS VOLUME MOVES, which is what makes the
	crossfades seamless: a layer started and stopped at each band change would restart its clip from
	the top every time.

	Pure sound: it reads nothing off the car, so the caller decides what the RPM is (today the
	simulated gearbox in `TestEngineController`).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local EngineSoundConfig = require(ReplicatedStorage.shared.Configs.EngineSoundConfig)

local EngineAudio = {}
EngineAudio.__index = EngineAudio

--- Every layer's name starts with this, so `TestEngineController._mute` never takes one for the kit's.
EngineAudio.Prefix = "Engine_"

local function approach(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * math.max(dt, 0)))
end

local function sound(parent: Instance, name: string, id: number, looped: boolean, fullWithin: number): Sound
	local s = Instance.new("Sound")
	s.Name = EngineAudio.Prefix .. name
	s.SoundId = "rbxassetid://" .. id
	s.Looped = looped
	s.Volume = 0
	s.RollOffMinDistance = fullWithin
	s.Parent = parent
	return s
end

--- `fullWithin`: studs before the layers start to fade, as the stand-in's `FullVolumeWithin`.
function EngineAudio.new(parent: Instance, pack, fullWithin: number, playStartup: boolean?)
	local self = setmetatable({}, EngineAudio)
	self._pack = pack
	self._load = 1 -- 1 on the throttle, 0 off it, eased
	self._idleIn = 0 -- the idle's fade in under the startup clip
	self._volumes = {} :: { [Sound]: number }
	self._pitches = {} :: { [Sound]: number }
	self._moving = 0
	self._sounds = {} :: { Sound }
	--- Optional on a simple pack: without one, the engine loop itself idles (`update`).
	if pack.Idle then
		self._idle = sound(parent, "Idle", pack.Idle, true, fullWithin)
		table.insert(self._sounds, self._idle)
	end
	self._layers = {}
	--- A simple pack (`EngineSoundConfig.Packs.SupercarV8`): one loop, pitched rather than banded.
	if pack.Engine then
		self._engine = sound(parent, "Engine", pack.Engine, true, fullWithin)
		table.insert(self._sounds, self._engine)
	end
	if pack.MaxRpm then
		self._max = sound(parent, "MaxRpm", pack.MaxRpm, true, fullWithin)
		table.insert(self._sounds, self._max)
	end
	--- An electric pack (`Electric`) and a simple one have no bands.
	for _, band in if pack.Engine or pack.Electric then {} else { "Low", "Med", "High" } do
		local layer = {
			on = sound(parent, band .. "On", pack[band].On, true, fullWithin),
			off = sound(parent, band .. "Off", pack[band].Off, true, fullWithin),
		}
		self._layers[band] = layer
		table.insert(self._sounds, layer.on)
		table.insert(self._sounds, layer.off)
	end
	for _, s in self._sounds do
		s:Play()
	end
	--- A one-shot on every downshift (`EngineSoundConfig` `Downshift`): made after the loops start,
	--- so it is not one of them, and replayed from the top by `update` when the gear drops.
	if pack.Downshift then
		self._down = sound(parent, "Downshift", pack.Downshift, false, fullWithin)
		table.insert(self._sounds, self._down)
	end
	if pack.Startup and playStartup ~= false then
		local start = sound(parent, "Startup", pack.Startup, false, fullWithin)
		start.Volume = 0
		self._startup = start
		start:Play()
		start.Ended:Once(function()
			start:Destroy()
		end)
		table.insert(self._sounds, start)
	end
	return self
end

--[[ One frame. `through` is 0..1 through the current gear, `idle` whether the car is all but
	stopped, `accelerating` whether it is on the throttle (the caller's call, see `Mix.DecelMph`),
	`level` 0..1 on top of the pack's own volume (the caller's mute under a loading screen). ]]
function EngineAudio.update(self, through: number, idle: boolean, accelerating: boolean, level: number, dt: number, gear: number?, movingBlend: number?)
	if self._destroyed or self._fading then return end
	local mix = EngineSoundConfig.Mix
	if self._pack.Electric then
		return -- nothing to play (`EngineSoundConfig` `Electric`)
	end
	local master = self._pack.Volume
	local gains = self._pack.LayerGain or {}
	local function gain(name: string): number
		return gains[name] or 1
	end
	if self._startup and self._startup.Parent then self._startup.Volume = master * gain("Startup") * level end
	if self._down and level <= 0 then self._down:Stop() self._down.Volume = 0 end
	self._load = approach(self._load, if accelerating then 1 else 0, mix.LoadResponse, dt)
	self._idleIn = math.min(1, self._idleIn + dt / math.max(mix.IdleFadeIn, 0.01))

	local function set(s: Sound, target: number, pitch: number?)
		local v = approach(self._volumes[s] or 0, target, mix.VolumeResponse, dt)
		self._volumes[s] = v
		s.Volume = v * level -- loading mutes immediately, without waiting for the volume envelope
		if pitch then
			local p = approach(self._pitches[s] or pitch, pitch, mix.PitchResponse, dt)
			self._pitches[s] = p
			s.PlaybackSpeed = p
		end
	end

	self._moving = approach(self._moving, movingBlend or (if idle then 0 else 1), mix.VolumeResponse, dt)
	local moving = self._moving
	if self._idle then
		set(self._idle, master * gain("Idle") * (1 - moving) * self._idleIn)
	end
	--- A gear down while moving: the blip. Not off a standstill, where the gearbox falls to first.
	local down = self._down
	if down and gear and self._gear and gear < self._gear and not idle and level > 0 and master > 0 then
		down.Volume = master * gain("Downshift") * level * 0.7
		down.TimePosition = 0
		down:Play()
	end
	self._gear = gear
	local engine = self._engine
	if engine then
		local simple = mix.Simple
		local pitch = simple.Low + (simple.High - simple.Low) * through + simple.PerGear * ((gear or 1) - 1)
		pitch -= simple.OffPitch * (1 - self._load)
		pitch *= self._pack.Pitch or 1
		local loudness = 1 - (1 - simple.OffVolume) * (1 - self._load)
		if self._idle then
			set(engine, master * moving * loudness, pitch)
		else
			--- No idle clip: the loop stays on at a standstill, pitched down and quieter, as an idle.
			local idlePitch = simple.IdlePitch * (self._pack.Pitch or 1)
			set(engine, master * (simple.IdleVolume + (loudness - simple.IdleVolume) * moving), idlePitch + (pitch - idlePitch) * moving)
		end
		return
	end
	local totalWeight = 0
	for band in self._layers do
		local centre, reach = mix.Bands[band][1], mix.Bands[band][2]
		totalWeight += math.max(0, 1 - math.abs(through - centre) / reach)
	end
	for band, layer in self._layers do
		local centre, reach = mix.Bands[band][1], mix.Bands[band][2]
		local weight = math.max(0, 1 - math.abs(through - centre) / reach) / math.max(totalWeight, 0.001) * moving
		local pitch = 1 + math.clamp((through - centre) / reach, -1, 1) * mix.PitchSpan
		set(layer.on, master * gain(band .. "On") * weight * self._load, pitch)
		set(layer.off, master * gain(band .. "Off") * weight * (1 - self._load), pitch)
	end
	local top = math.clamp((through - mix.MaxRpmFrom) / math.max(1 - mix.MaxRpmFrom, 0.01), 0, 1)
	set(self._max, master * gain("MaxRpm") * top * self._load * moving)
end

function EngineAudio.fadeOut(self, seconds: number)
	if self._destroyed then return end
	self._fading = true
	for _, s in self._sounds do
		if s.Parent then TweenService:Create(s, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Volume = 0 }):Play() end
	end
end

function EngineAudio.destroy(self)
	if self._destroyed then return end
	self._destroyed = true
	for _, s in self._sounds do
		s:Destroy()
	end
	table.clear(self._sounds)
end

return EngineAudio
