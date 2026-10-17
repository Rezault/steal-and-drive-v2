--[[
	CrashVfxController  (client)
	----------------------------
	Plays the delivered collision effects (`CrashVfxConfig`, which has the whole assignment of which
	effect means what). Three entry points, each owned by what already knew the moment:

	    impact(source, cframe, shake)   `ObstacleController.applyImpact` — every collision's one door
	    wreck(car)                      `ObstacleController._onWrecked`
	    (damage)                        this file, off the car HitBox's `Health` attribute

	THE LOOKS ARE THE ARTIST'S. Every emitter is a clone of one the owner authored; this file only
	switches them on and off and decides how many particles a one-shot burst throws.

	EVERYTHING RIDES THE CAR (since 2026-09-30; bursts were world-anchored and read as "barely there" —
	see `CrashVfxConfig.Bursts`). A burst is an attachment on the car's PrimaryPart at the contact point,
	and every particle inherits the car's velocity (`CrashVfxConfig.Inherit`), so it stays in frame
	beside a car doing 100 studs/s. A loop (damage smoke, fire) sits on attachments at named spots on
	the same part (`CrashVfxConfig.Spots` — the hood, and since 2026-10-02 the rear, sides and roof),
	and being a descendant of the car is what lets `StealController.hideTree` switch it off with
	everything else while the car is hidden for a flight.

	THREE OF THE ARTIST'S PROPERTIES ARE CHANGED, and only these: `VelocityInheritance` (above), `Size`
	(multiplied by the config's scale — the shape of the size curve is kept) and `Enabled` (the
	switching). Texture, colour, lifetime and speed stay as authored; so does rate, except that a
	looping layer authored with none gets `CrashVfxConfig.LoopFallbackRate` so it shows at all, and
	`LightEmission` on the bursts that ask for it (the sparks, since 2026-10-02).

	THE EXTRAS (2026-10-02, `CrashVfxConfig.Extras`): around the particles, lights and shards — a flash
	on every hit, firelight that flickers at every burning spot, bodywork thrown off a real hit, and a
	wreck that goes up as a blast. Lights are children of the car's attachments like everything else,
	so `hideTree` (which switches `Light`s too) hides them for a flight for free. Shards are the one
	thing NOT on the car: loose client-only parts in `CrashVfxLive` that never collide.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local DebrisService = game:GetService("Debris")

local Shard = require(ReplicatedStorage.Packages.Shard)
local CrashVfxConfig = require(ReplicatedStorage.shared.Configs.CrashVfxConfig)
local ObstacleConfig = require(ReplicatedStorage.shared.Configs.ObstacleConfig)

local CrashVfxController = Shard.new("CrashVfxController")

local LIVE_FOLDER = "CrashVfxLive"
--- Prefix of the attachment made for each of `CrashVfxConfig.Spots` (one per spot per car).
local SPOT_PREFIX = "CrashVfxSpot"
--- How often the car and its HitBox are looked up again. Health itself is event-driven.
local RESOLVE_INTERVAL = 1

-- === Finding the effects =====================================================================

--- The authored emitters a list of names points at (`CrashVfxConfig` "HOW THE EFFECTS ARE FOUND").
function CrashVfxController._templates(self, names: { string }): { ParticleEmitter }
	local key = table.concat(names, "|")
	local cached = self._cache[key]
	if cached then
		return cached
	end
	local folder = ReplicatedStorage:FindFirstChild(CrashVfxConfig.FolderName)
	if not folder then
		if not self._warned then
			self._warned = true
			self.log:warn(string.format("No ReplicatedStorage.%s; crashes play no new effects.", CrashVfxConfig.FolderName))
		end
		return {}
	end
	local out = {}
	for _, name in names do
		local before = #out
		for _, inst in folder:GetDescendants() do
			if inst.Name == name then
				if inst:IsA("ParticleEmitter") then
					table.insert(out, inst)
				else
					for _, child in inst:GetDescendants() do
						if child:IsA("ParticleEmitter") then
							table.insert(out, child)
						end
					end
				end
			end
		end
		--[[ A name that matches nothing is otherwise invisible: the effect just never plays, and a
			playtest reads it as "only smoke". Said once per name, with what it did find, so a renamed
			emitter in the delivered folder is a one-line fix in `CrashVfxConfig`. ]]
		if not self._reported[name] then
			self._reported[name] = true
			local found = #out - before
			if found == 0 then
				self.log:warn(string.format("No effect called %q in ReplicatedStorage.%s; that part of the crash effects will not show.", name, CrashVfxConfig.FolderName))
			else
				self.log:info(string.format("Crash effect %q: %d emitter(s).", name, found))
			end
		end
	end
	self._cache[key] = out
	return out
end

--- The artist's size curve, every keypoint and envelope multiplied by `scale`.
local function scaled(sequence: NumberSequence, scale: number): NumberSequence
	local points = {}
	for _, point in sequence.Keypoints do
		table.insert(points, NumberSequenceKeypoint.new(point.Time, point.Value * scale, point.Envelope * scale))
	end
	return NumberSequence.new(points)
end

--[[ A clone of `template`, dressed for a car at speed: inherits its velocity, scaled, switched off, and
	given `lightEmission` when the burst asks for glow (nil keeps the artist's). ]]
local function dressed(template: ParticleEmitter, sizeScale: number?, lightEmission: number?): ParticleEmitter
	local emitter = template:Clone()
	emitter.Enabled = false
	emitter.VelocityInheritance = CrashVfxConfig.Inherit
	if sizeScale and sizeScale ~= 1 then
		emitter.Size = scaled(emitter.Size, sizeScale)
	end
	if lightEmission then
		emitter.LightEmission = lightEmission
	end
	return emitter
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function CrashVfxController._liveFolder(self): Folder
	local folder = self._live
	if folder and folder.Parent then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = LIVE_FOLDER
	folder.Parent = workspace
	self._live = folder
	return folder
end

-- === Bursts ==================================================================================

--[[ One burst from `CrashVfxConfig.Bursts[name]` at `cframe` (world), sized by `t` (0..1). Mounted on
	the car at that point so it travels with it; a car that has gone falls back to a fixed point. ]]
--[[ A short-lived attachment at `cframe` (world): on the car's PrimaryPart when there is a car, so it
	travels with it; on an invisible anchored part when the car has gone. Returns the attachment and
	the thing to destroy when done (the attachment itself, or the anchor that holds it). ]]
function CrashVfxController._mount(self, name: string, cframe: CFrame): (Attachment, Instance)
	local car = self._car
	local primary = car and car.PrimaryPart
	local attachment = Instance.new("Attachment")
	attachment.Name = "CrashVfx" .. name
	if primary then
		attachment.CFrame = primary.CFrame:ToObjectSpace(cframe)
		attachment.Parent = primary
		return attachment, attachment
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = cframe
	anchor.Parent = self:_liveFolder()
	attachment.Parent = anchor
	return attachment, anchor
end

function CrashVfxController._burst(self, name: string, cframe: CFrame, t: number)
	local spec = CrashVfxConfig.Bursts[name]
	if not spec then
		return
	end
	local templates = self:_templates(spec.Names)
	if #templates == 0 then
		return
	end
	local attachment, holder = self:_mount(name, cframe)

	local count = math.max(1, math.round(lerp(spec.Count, spec.CountAtFull, t)))
	local longest = 0
	for _, template in templates do
		local emitter = dressed(template, spec.SizeScale, spec.LightEmission)
		emitter.Parent = attachment
		emitter:Emit(count)
		longest = math.max(longest, emitter.Lifetime.Max)
	end
	--- Gone once its longest particle has, so a crash-heavy run does not pile attachments up.
	task.delay(longest + 0.5, function()
		holder:Destroy()
	end)
end

--[[ PUBLIC (ObstacleController.applyImpact) — a collision. `source` is "Car", "Wall" or "Obstacle";
	`cframe` is the contact point on the car's skin (`_puffCFrame`); `shake` the hit's own `Shake`. ]]
function CrashVfxController.impact(self, source: string, cframe: CFrame, shake: number)
	if not CrashVfxConfig.Enabled then
		return
	end
	local t = math.clamp((shake or 0) / math.max(CrashVfxConfig.FullShake, 1e-3), 0, 1)
	for _, name in CrashVfxConfig.OnHit[source] or CrashVfxConfig.OnHit.Car do
		self:_burst(name, cframe, t)
	end
	if (shake or 0) >= CrashVfxConfig.HeavyShake then
		for _, name in CrashVfxConfig.OnHit.Heavy do
			self:_burst(name, cframe, t)
		end
	end

	local extras = CrashVfxConfig.Extras
	if not extras.Enabled then
		return
	end
	local flash = extras.Flash
	if flash.Enabled then
		self:_flash(cframe, lerp(flash.Brightness, flash.BrightnessAtFull, t), lerp(flash.Range, flash.RangeAtFull, t), flash.Decay)
	end
	local debris = extras.Debris
	if debris.Enabled and source ~= "Wall" and (shake or 0) >= debris.MinShake then
		local primary = self._car and self._car.PrimaryPart
		local outward = if primary then (cframe.Position - primary.Position) * Vector3.new(1, 0, 1) else Vector3.zero
		self:_debris(cframe.Position, outward, math.round(lerp(debris.Count, debris.CountAtFull, t)))
	end
end

-- === The extras (`CrashVfxConfig.Extras`) =====================================================

--- A point light that pops at `cframe` and fades to nothing over `decay` seconds.
function CrashVfxController._flash(self, cframe: CFrame, brightness: number, range: number, decay: number)
	local attachment, holder = self:_mount("Flash", cframe)
	local light = Instance.new("PointLight")
	light.Color = CrashVfxConfig.Extras.Flash.Color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = attachment
	TweenService:Create(light, TweenInfo.new(decay, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	DebrisService:AddItem(holder, decay + 0.1)
end

--[[ The colour and material of the car's largest visible part, meant to be the body. Read once per car
	(`_track`). Nil when the car has no visible part — shards then fall back to dark grey. ]]
local function bodyLook(car: Model, hitBox: BasePart?): { color: Color3, material: Enum.Material }?
	local best, bestVolume = nil, 0
	for _, inst in car:GetDescendants() do
		if inst:IsA("BasePart") and inst ~= hitBox and inst.Transparency < 0.5 then
			local volume = inst.Size.X * inst.Size.Y * inst.Size.Z
			if volume > bestVolume then
				best, bestVolume = inst, volume
			end
		end
	end
	return if best then { color = best.Color, material = best.Material } else nil
end

--[[ `count` shards of bodywork thrown from `origin`. `outward` is the direction away from the car
	(flat); a zero vector throws each shard in its own random direction, which is the blast. Why they
	never collide, and what that costs, is at `CrashVfxConfig.Extras.Debris`. ]]
function CrashVfxController._debris(self, origin: Vector3, outward: Vector3, count: number)
	local cfg = CrashVfxConfig.Extras.Debris
	local rng = self._rng
	local primary = self._car and self._car.PrimaryPart
	local carVelocity = if primary then primary.AssemblyLinearVelocity else Vector3.zero
	local look = self._look
	local folder = self:_liveFolder()
	local fade = TweenInfo.new(cfg.Life * 0.4, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, cfg.Life * 0.6)
	for _ = 1, count do
		local angle = rng:NextNumber(0, math.pi * 2)
		local away = if outward.Magnitude > 1e-3
			then outward.Unit + Vector3.new(rng:NextNumber(-0.6, 0.6), 0, rng:NextNumber(-0.6, 0.6))
			else Vector3.new(math.cos(angle), 0, math.sin(angle))
		local shard = Instance.new("Part")
		shard.Name = "CrashShard"
		shard.Size = Vector3.new(
			rng:NextNumber(cfg.SizeMin, cfg.SizeMax),
			rng:NextNumber(cfg.SizeMin, cfg.SizeMax) * 0.3,
			rng:NextNumber(cfg.SizeMin, cfg.SizeMax)
		)
		shard.Color = if look then look.color else Color3.fromRGB(45, 45, 50)
		shard.Material = if look then look.material else Enum.Material.SmoothPlastic
		shard.CanCollide = false
		shard.CanQuery = false
		shard.CanTouch = false
		shard.CastShadow = false
		shard.CFrame = CFrame.new(origin) * CFrame.Angles(rng:NextNumber(0, math.pi * 2), rng:NextNumber(0, math.pi * 2), 0)
		shard.Parent = folder
		shard.AssemblyLinearVelocity = carVelocity * cfg.Inherit
			+ away.Unit * cfg.Speed * rng:NextNumber(0.6, 1.2)
			+ Vector3.yAxis * cfg.Up * rng:NextNumber(0.6, 1.2)
		shard.AssemblyAngularVelocity = rng:NextUnitVector() * cfg.Spin
		TweenService:Create(shard, fade, { Transparency = 1 }):Play()
		DebrisService:AddItem(shard, cfg.Life)
	end
end

--- The wreck's one-off blast at the car's centre (`CrashVfxConfig.Extras.Explosion`).
function CrashVfxController._explode(self, car: Model)
	local extras = CrashVfxConfig.Extras
	local cfg = extras.Explosion
	local primary = car.PrimaryPart
	if not (extras.Enabled and cfg.Enabled and primary) then
		return
	end
	local at = primary.CFrame
	for _, name in cfg.Bursts do
		self:_burst(name, at, 1)
	end
	if extras.Flash.Enabled then
		self:_flash(at, cfg.FlashBrightness, cfg.FlashRange, cfg.FlashDecay)
	end
	if extras.Debris.Enabled then
		self:_debris(at.Position, Vector3.zero, cfg.Debris)
	end
end

-- === Loops on the car ========================================================================

--- The attachment for one of `CrashVfxConfig.Spots` on this car, made once per car. Nil for an unknown spot.
function CrashVfxController._spot(self, car: Model, name: string): Attachment?
	local primary = car.PrimaryPart
	local spot = CrashVfxConfig.Spots[name]
	if not (primary and spot) then
		return nil
	end
	local existing = primary:FindFirstChild(SPOT_PREFIX .. name)
	if existing and existing:IsA("Attachment") then
		return existing
	end
	local size = car:GetExtentsSize()
	local attachment = Instance.new("Attachment")
	attachment.Name = SPOT_PREFIX .. name
	-- LookVector is -Z, so the nose is toward -Z in the PrimaryPart's own frame.
	attachment.Position = Vector3.new(
		size.X * 0.5 * (spot.Right or 0),
		size.Y * 0.5 * (spot.Up or 0),
		-size.Z * 0.5 * (spot.Forward or 0)
	)
	attachment.Parent = primary
	return attachment
end

--[[ Switch one named set of looping layers (`CrashVfxConfig.Loops`, `.Wreck`) on this car on or off,
	building it the first time. ]]
function CrashVfxController._loop(
	self,
	key: string,
	layers: { { Names: { string }, SizeScale: number?, At: { string }?, Glow: boolean? } },
	on: boolean
)
	local car = self._car
	local set = self._loops[key]
	if not set then
		if not on or not car then
			return
		end
		set = {}
		for _, layer in layers do
			for _, spotName in layer.At or { "Hood" } do
				local spot = self:_spot(car, spotName)
				if not spot then
					continue
				end
				for _, template in self:_templates(layer.Names) do
					local emitter = dressed(template, layer.SizeScale)
					if emitter.Rate <= 0 then
						emitter.Rate = CrashVfxConfig.LoopFallbackRate
					end
					emitter.Parent = spot
					table.insert(set, emitter)
				end
				local glow = CrashVfxConfig.Extras.Glow
				if layer.Glow and glow.Enabled and CrashVfxConfig.Extras.Enabled then
					local light = Instance.new("PointLight")
					light.Name = "CrashVfxGlow"
					light.Color = glow.Color
					light.Brightness = glow.Brightness
					light.Range = glow.Range
					light.Shadows = false
					light.Enabled = false
					light.Parent = spot
					table.insert(set, light)
					self._glows[light] = self._rng:NextNumber(0, 1000)
				end
			end
		end
		self._loops[key] = set
	end
	--- Emitters and lights alike: both switch on `Enabled`, which is also what `hideTree` writes.
	for _, item in set do
		if item.Parent then
			item.Enabled = on
		end
	end
end

--[[ The firelight flicker, every frame, off smooth noise (why noise and not random: at
	`CrashVfxConfig.Extras.Glow`). Writes Brightness only, never `Enabled`, so it cannot fight the
	stage switching above or `hideTree`. Each light has its own noise seed so five fires do not pulse
	in step. ]]
function CrashVfxController._flicker(self)
	if next(self._glows) == nil then
		return
	end
	local glow = CrashVfxConfig.Extras.Glow
	local now = os.clock() * glow.FlickerSpeed
	for light, seed in self._glows do
		if not light.Parent then
			self._glows[light] = nil
			continue
		end
		light.Brightness = glow.Brightness * (1 + glow.Flicker * 2 * math.noise(now, seed))
	end
end

--[[ The damage stage off the HitBox's health. Only a CHANGE of stage writes anything — see
	`CrashVfxConfig.Damaged` on why re-asserting would fight the steal's hide. ]]
function CrashVfxController._onHealth(self)
	local hitBox = self._hitBox
	if not (hitBox and hitBox.Parent) or self._wrecked then
		return
	end
	local health = hitBox:GetAttribute("Health")
	local max = hitBox:GetAttribute("MaxHealth") or ObstacleConfig.DefaultMaxHealth
	if type(health) ~= "number" or type(max) ~= "number" or max <= 0 then
		return
	end
	local fraction = health / max
	local stage = if fraction <= CrashVfxConfig.Critical
		then "Critical"
		elseif fraction <= CrashVfxConfig.Damaged then "Damaged"
		else "Clean"
	if stage == self._stage then
		return
	end
	self._stage = stage
	self:_loop("Damaged", CrashVfxConfig.Loops.Damaged, stage == "Damaged")
	self:_loop("Critical", CrashVfxConfig.Loops.Critical, stage == "Critical")
end

--[[ PUBLIC (ObstacleController._onWrecked) — the car is done. The damage loops give way to the wreck
	set, which burns until the car is torn down with the run. Returns whether anything played, so the
	caller knows whether to skip the old plume (`CrashVfxConfig.ReplaceWreckSmoke`). ]]
function CrashVfxController.wreck(self, car: Model): boolean
	if not CrashVfxConfig.Enabled or #self:_templates(CrashVfxConfig.Wreck[1].Names) == 0 then
		return false
	end
	if car ~= self._car then
		self:_track(car)
	end
	self._wrecked = true
	self:_loop("Damaged", CrashVfxConfig.Loops.Damaged, false)
	self:_loop("Critical", CrashVfxConfig.Loops.Critical, false)
	self:_loop("Wreck", CrashVfxConfig.Wreck, true)
	self:_explode(car)
	return true
end

--[[ PUBLIC (ObstacleController._onRevived) — the wreck was revived out of, so the car is back on the
	road and must stop burning. The exact inverse of `wreck` (`RaceService.reviveRace` states the rule:
	a `RaceWrecked` reaction with no `RaceRevived` inverse stays on for the rest of the run — which is
	what this did until 2026-10-05, a revived car driving on wrapped in the wreck's fire). The damage
	stage is then read fresh off the health the revive put back. ]]
function CrashVfxController.revived(self)
	if not self._wrecked then
		return
	end
	self._wrecked = false
	self:_loop("Wreck", CrashVfxConfig.Wreck, false)
	self._stage = nil
	self:_onHealth()
end

-- === Following the car =======================================================================

--- Start following `car` (nil = none): fresh loops, fresh stage, the HitBox's health watched.
function CrashVfxController._track(self, car: Model?)
	if self._healthConn then
		self._healthConn:Disconnect()
		self._healthConn = nil
	end
	self._car = car
	self._loops = {}
	self._stage = nil
	self._wrecked = false
	self._hitBox = car and car:FindFirstChild(ObstacleConfig.HitBoxName, true) :: BasePart?
	self._look = if car then bodyLook(car, self._hitBox) else nil
	if self._hitBox then
		self._healthConn = self._hitBox:GetAttributeChangedSignal("Health"):Connect(function()
			self:_onHealth()
		end)
		self:_onHealth()
	end
end

--- The car being driven right now, as `RoadController` has it.
function CrashVfxController._currentCar(self): Model?
	local road = Shard.get("RoadController")
	local car = road and road.getCar and road:getCar()
	return if car and car.Parent then car else nil
end

CrashVfxController:withLifecycle({
	init = function(self)
		self._cache = {} :: { [string]: { ParticleEmitter } }
		self._reported = {} :: { [string]: boolean }
		self._loops = {} :: { [string]: { ParticleEmitter } }
		self._car = nil :: Model?
		self._hitBox = nil :: BasePart?
		self._stage = nil :: string?
		self._wrecked = false
		self._look = nil :: { color: Color3, material: Enum.Material }?
		self._glows = {} :: { [PointLight]: number }
		self._rng = Random.new()
	end,

	start = function(self)
		if not CrashVfxConfig.Enabled then
			return
		end
		--- The car changes per run (and between runs there is none); looked up at a slow tick, since
		--- the health that matters within a run is event-driven off the HitBox.
		local since = 0
		RunService.Heartbeat:Connect(function(dt)
			since += dt
			if since < RESOLVE_INTERVAL then
				return
			end
			since = 0
			local car = self:_currentCar()
			if car ~= self._car or (car and not (self._hitBox and self._hitBox.Parent)) then
				self:_track(car)
			end
		end)
		RunService.RenderStepped:Connect(function()
			self:_flicker()
		end)
		Players.LocalPlayer.CharacterRemoving:Connect(function()
			self:_track(nil)
		end)
	end,
})

return CrashVfxController
