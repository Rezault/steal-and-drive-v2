--[[
	NitroController  (client)
	-------------------------
	The nitrous bottle: one tank, one held button, and everything that happens while it is held.

	It owns FOUR things and delegates every one of them to whoever already owns the thing being
	changed, which is why this file has no physics and no layout in it:

	  • THE TANK. A 0..1 fraction that drains while burning, refills on a clock after a pause, and
	    is topped up by near misses. This is the only state that is genuinely this controller's.
	  • THE SPEED, through `DriveController:setNitro`. That controller owns the car's speed dial and
	    resolves boost against nitro with `math.max` (see its `_speedDial`); we hand it a scale and
	    a one-off kick and never touch the car ourselves.
	  • THE SHOT, through `RaceCameraController:addFov`. That controller re-asserts FieldOfView every
	    render frame, so a push has to be pushed AT it rather than written to the camera. The ease
	    is ours (`NitroConfig.Fov`), the property is not.
	  • THE FLAME, two jets built onto the car's HitBox for the length of a race: the library layers
	    or the original single emitter, whichever `NitroConfig.FlameVfx` picks.

	The screen is not in that list. `DrivingHudController` draws the bar and binds the on-screen
	button, exactly as it does for the pedals and the arrows, and it reads this controller through
	the getters at the bottom. That keeps every authored instance in one file and every number about
	the mechanic in this one.

	=== WHY THE TANK IS A FRACTION AND THE CAPACITY IS SECONDS ==================================

	`NitroConfig` states a bottle as SECONDS OF BURN because that is what a designer can reason
	about, and it varies by car. The tank here is a FRACTION of whatever the current car's bottle
	is, because a steal changes the bottle underneath the player mid-run: carried as seconds, a
	steal onto a bigger car would silently look like the tank had emptied, and onto a smaller one
	like it had overfilled. As a fraction, "three quarters full" survives the swap and means the
	same thing on both sides of it. The drain rate is then `1 / seconds` and falls out of the one
	number rather than being a second dial that can drift out of step with it.

	=== THE HELD STATE HAS TWO SOURCES AND NEITHER MAY CANCEL THE OTHER ========================

	A key (or the left bumper) and an on-screen button, tracked separately and OR-ed. Summed the way
	`DriveController` sums the pedals would be wrong here because this is a boolean, not an axis:
	a player on a phone with a bluetooth keyboard who lifts one finger must not cut a burn the other
	hand is still holding. Two flags, one question.

	=== IT STOPS FOR THREE THINGS AND THEY ALL ASK THE SAME QUESTION ===========================

	`DriveController:isDriving()` is false when the shim is not installed (no race, or a wreck),
	when the car is suspended (mid-bail, StealController is flying it) and when the world is frozen
	(a tutorial beat, the race-entry countdown). All three have to stop the drain, because in all
	three the player cannot possibly be spending it, and one getter is what stops that being three
	separate bugs. It is checked every frame rather than at the press, because every one of them
	can begin in the middle of a burn.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local CarStats = require(ReplicatedStorage.shared.Modules.CarStats)
local NitroConfig = require(ReplicatedStorage.shared.Configs.NitroConfig)
--- Only for where the delivered effects live (`NitroConfig.Flame.Turbo` borrows `fire trbo` from them).
local CrashVfxConfig = require(ReplicatedStorage.shared.Configs.CrashVfxConfig)

local NitroController = Shard.new("NitroController"):withDependencies({ "DriveController", "RoadController" })

-- ContextActionService unbinds by name, so one shared name for the session.
local ACTION_NAME = "RaceNitro"

--- The car part every rig in the game is guaranteed to have and every redress keeps: the flame
--- mounts are stated as fractions of its size (see NitroConfig.Flame.Offset).
local HITBOX_NAME = "HitBox"

--- Name given to the two attachments we add, so a leftover from a client that errored mid-race is
--- identifiable in the Explorer rather than being an anonymous Attachment on somebody's car.
local JET_NAME = "NitroJet"

--[[ Frame-rate independent approach toward a target, the same shape the rest of this project's
	eases use: `rate` is a per-second time constant, so the result is identical at 30 and 240 fps.
	Local because it is three lines and copying them is cheaper than a dependency. ]]
local function approach(current: number, target: number, rate: number, dt: number): number
	if rate <= 0 then
		return target
	end
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

--- `Flipbook` in a `NitroConfig.Flame.Vfx` layer, by name. A layer with none is a single still image.
local FLIPBOOKS = {
	Grid2x2 = Enum.ParticleFlipbookLayout.Grid2x2,
	Grid4x4 = Enum.ParticleFlipbookLayout.Grid4x4,
	Grid8x8 = Enum.ParticleFlipbookLayout.Grid8x8,
}

--- A layer's `Speed` or `Lifetime`: a number for one value, or `{ min, max }` for a spread of them.
local function rangeOf(value: unknown, fallback: number): NumberRange
	if type(value) == "table" and type(value[1]) == "number" and type(value[2]) == "number" then
		return NumberRange.new(math.min(value[1], value[2]), math.max(value[1], value[2]))
	end
	return NumberRange.new(if type(value) == "number" then value else fallback)
end

--[[ One layer of the library flame (`NitroConfig.Flame.Vfx`), built disabled under its jet.

	`FlipbookMode` is written as OneShot because the default is `Loop` at one frame a second, which
	shows a 0.2s particle the first frame of its sheet and nothing else. `VelocityInheritance` is 1
	for the reason `_buildFlames` gives; a `Locked` layer ignores it and rides the bumper outright. ]]
local function buildLayer(spec: any, jet: Attachment): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = spec.Name or "Layer"
	emitter.Texture = spec.Texture
	emitter.FlipbookLayout = FLIPBOOKS[spec.Flipbook] or Enum.ParticleFlipbookLayout.None
	emitter.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	emitter.Orientation = if spec.Orientation == "VelocityParallel"
		then Enum.ParticleOrientation.VelocityParallel
		else Enum.ParticleOrientation.FacingCamera

	local colors, size, alpha = spec.Colors, spec.Size, spec.Transparency
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, colors[1]),
		ColorSequenceKeypoint.new(0.35, colors[2]),
		ColorSequenceKeypoint.new(1, colors[3]),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size[1]),
		NumberSequenceKeypoint.new(math.clamp(spec.Taper or 0.5, 0.05, 0.95), size[2]),
		NumberSequenceKeypoint.new(1, size[3]),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, alpha[1]),
		NumberSequenceKeypoint.new(0.7, alpha[2]),
		NumberSequenceKeypoint.new(1, alpha[3]),
	})
	emitter.Squash = NumberSequence.new(spec.Squash or 0)

	emitter.Rate = spec.Rate or 60
	emitter.Lifetime = rangeOf(spec.Lifetime, 0.2)
	emitter.Speed = rangeOf(spec.Speed, 0)
	local spread, tilt, spin = spec.Spread or 0, spec.Rotation or 0, spec.Spin or 0
	emitter.SpreadAngle = Vector2.new(spread, spread)
	emitter.Rotation = NumberRange.new(-tilt, tilt)
	emitter.RotSpeed = NumberRange.new(-spin, spin)
	emitter.EmissionDirection = Enum.NormalId.Back
	emitter.LockedToPart = spec.Locked == true
	emitter.VelocityInheritance = 1
	emitter.Drag = spec.Drag or 0
	emitter.LightEmission = spec.Glow or 1
	emitter.LightInfluence = 0
	emitter.Brightness = spec.Brightness or 1
	emitter.ZOffset = spec.ZOffset or 0
	emitter.Enabled = false
	emitter.Parent = jet
	return emitter
end

--- The jet's light, off until a burn, or nil when `Flame.LightBrightness` is 0.
local function makeLight(cfg: any, color: Color3, jet: Attachment): PointLight?
	if cfg.LightBrightness <= 0 then
		return nil
	end
	local light = Instance.new("PointLight")
	light.Brightness = cfg.LightBrightness
	light.Range = cfg.LightRange
	light.Color = color
	light.Enabled = false
	light.Parent = jet
	return light
end

-- === The tank ================================================================

--[[ Which car we are burning out of, and what its bottle is.

	Re-resolved whenever the model changes rather than latched at race start, because a steal swaps
	the car underneath the player without ending the race, and the new car's rung is what the new
	bottle should be sized to. `CarStats.bodyOf` is the one place in the game that knows how to ask
	a car what it is (the stamped `Body` attribute if it was stolen, the model name if it was not),
	so this cannot drift from what the rest of the game thinks the player is driving.

	A car we cannot identify still gets a bottle: `NitroConfig.rungFraction` answers 0 for anything
	unknown, which is the world's beater. The smallest bottle is the safe way to be wrong. ]]
function NitroController._bindCar(self, car: Model?)
	local body = if car then CarStats.bodyOf(car) else nil
	if car == self._car and body == self._bodyKey then
		return
	end
	local previous = self._car
	self._car = car
	self._bodyKey = body
	self:_destroyFlames()

	if not car then
		self._power = nil
		return
	end

	self._power = NitroConfig.powerFor(body)

	--[[ A FRESH CAR MID-RACE IS A STEAL, and a steal refills the bottle (NitroConfig.Tank
		.RefillOnSteal). The first car of a race is not one, which is what `previous` distinguishes:
		at race start `_car` is nil and the tank has already been set to `StartFraction`, and
		overwriting it here would make that setting unreachable. ]]
	if previous and NitroConfig.Tank.RefillOnSteal then
		self._tank = 1
		self._sinceBurn = math.huge
	end

	self:_buildFlames(car)
end

--[[ One frame of the tank, and the one place the mechanic's rules actually live.

	Drain and refill are mutually exclusive by construction rather than by a flag: burning consumes
	and resets the pause, and everything else counts toward the pause and then refills. There is no
	third state to get stuck in. ]]
function NitroController._stepTank(self, dt: number)
	local tank = NitroConfig.Tank
	local seconds = math.max((self._power and self._power.seconds) or tank.SecondsBottom, 0.1)

	if self._burning then
		self._tank = math.max(self._tank - dt / seconds, 0)
		self._sinceBurn = 0
		return
	end

	self._sinceBurn += dt
	if self._tank >= 1 or self._sinceBurn < tank.RefillDelay then
		return
	end
	local refill = math.max(tank.RefillSeconds, 0.1)
	self._tank = math.min(self._tank + dt / refill, 1)
end

--[[ Should the bottle be alight this frame?

	Asked fresh every frame rather than latched at the press, because every reason it could stop is
	a thing that begins mid-burn: the tank empties, the player lets go, a wreck tears the shim down,
	a bail suspends the car, a tutorial beat freezes the world.

	The one piece of hysteresis in here is `MinToFire`, and it applies to LIGHTING only: you need a
	sixth of a bottle to start and nothing stops you burning it to zero once you have. Without it, a
	held key on an almost-empty tank lights and dies every few frames, which stutters the speed
	dial, the flame and the camera all at once and reads as the feature misfiring. ]]
function NitroController._wantBurn(self): boolean
	if not (self._active and (self._keyHeld or self._hudHeld)) then
		return false
	end
	if not (self._drive and self._drive:isDriving()) then
		return false
	end
	if self._burning then
		return self._tank > 0
	end
	return self._tank >= NitroConfig.Tank.MinToFire
end

-- === Effects =================================================================

--[[ Build the two jets on the car's HitBox.

	OFF THE HITBOX and not off the body, because every rig in the game shares that box (a redress
	fits the art to the chassis, never the other way round) so one offset stated as a fraction of it
	is correct on all 65 rigs. Anchoring to body parts would need a per-car table and would be wrong
	the first time a modeller re-exported one.

	The box's own axes do the rest: a Roblox part looks down -Z, so +Z is the car's rear and
	`EmissionDirection = Back` throws the flame out behind it with no CFrame maths at all.

	`VelocityInheritance = 1` is the load-bearing property. At zero, a particle is born with no
	velocity of its own while the car leaves at 120 studs/s, so the flame detaches and hangs in the
	air a car's length behind the bumper. At one it carries the car's velocity and `Speed` becomes a
	RELATIVE backward drift, which is what makes it a jet stuck to the exhaust.

	`NitroConfig.FlameVfx` picks what each jet holds: the library layers (`Flame.Vfx`, built by
	`buildLayer`) or the original single emitter below, untouched. ]]
--[[ Clone the turbo fire (`NitroConfig.Flame.Turbo`) onto one jet and add it to that jet's emitters,
	so `_setFlame` switches it with the rest. The two overrides and why are at that config. ]]
local function addTurbo(attachment: Attachment, emitters: { ParticleEmitter })
	local turbo = NitroConfig.Flame.Turbo
	local folder = turbo and turbo.Enabled and ReplicatedStorage:FindFirstChild(CrashVfxConfig.FolderName)
	if not folder then
		return
	end
	for _, name in turbo.Names do
		for _, inst in folder:GetDescendants() do
			if inst.Name ~= name then
				continue
			end
			local sources = if inst:IsA("ParticleEmitter") then { inst } else inst:GetDescendants()
			for _, source in sources do
				if source:IsA("ParticleEmitter") then
					local emitter = source:Clone()
					emitter.EmissionDirection = Enum.NormalId.Back
					emitter.VelocityInheritance = 1
					emitter.Rate *= turbo.RateScale or 1
					local points = {}
					for _, point in emitter.Size.Keypoints do
						local k = turbo.SizeScale or 1
						table.insert(points, NumberSequenceKeypoint.new(point.Time, point.Value * k, point.Envelope * k))
					end
					emitter.Size = NumberSequence.new(points)
					emitter.Enabled = false
					emitter.Parent = attachment
					table.insert(emitters, emitter)
				end
			end
		end
	end
end

function NitroController._buildFlames(self, car: Model)
	local cfg = NitroConfig.Flame
	if not cfg.Enabled then
		return
	end
	local hit = car:FindFirstChild(HITBOX_NAME, true)
	if not (hit and hit:IsA("BasePart")) then
		self.log:warn(`Car has no {HITBOX_NAME} to mount the nitro jets on; racing without the flame.`)
		return
	end

	local size, offset = hit.Size, cfg.Offset
	local vfx = if NitroConfig.FlameVfx then cfg.Vfx else nil
	local jets = {}
	for _, sign in { -1, 1 } do
		local attachment = Instance.new("Attachment")
		attachment.Name = JET_NAME
		attachment.Position = Vector3.new(sign * offset.X * size.X, offset.Y * size.Y, offset.Z * size.Z)

		if vfx then
			local emitters = {}
			for _, spec in vfx.Layers do
				table.insert(emitters, buildLayer(spec, attachment))
			end
			addTurbo(attachment, emitters)
			local light = makeLight(cfg, vfx.LightColor, attachment)
			attachment.Parent = hit
			table.insert(jets, { attachment = attachment, emitters = emitters, light = light })
			continue
		end

		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = cfg.Texture
		emitter.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, cfg.Core),
			ColorSequenceKeypoint.new(0.35, cfg.Mid),
			ColorSequenceKeypoint.new(1, cfg.Tail),
		})
		-- Widest at the root and gone by the tail, which is the shape of a jet rather than of a
		-- puff. `Taper` is where the turn happens.
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, cfg.Size * 0.35),
			NumberSequenceKeypoint.new(math.clamp(cfg.Taper, 0.05, 0.95), cfg.Size),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(0.7, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Rate = cfg.Rate
		emitter.Lifetime = cfg.Lifetime
		emitter.Speed = NumberRange.new(cfg.Speed)
		emitter.SpreadAngle = Vector2.new(cfg.SpreadDeg, cfg.SpreadDeg)
		emitter.EmissionDirection = Enum.NormalId.Back
		emitter.VelocityInheritance = 1
		emitter.LightEmission = 0.85
		emitter.LightInfluence = 0
		emitter.Drag = 2
		emitter.Enabled = false
		emitter.Parent = attachment

		local light = makeLight(cfg, cfg.Mid, attachment)

		local emitters = { emitter }
		addTurbo(attachment, emitters)
		attachment.Parent = hit
		table.insert(jets, { attachment = attachment, emitters = emitters, light = light })
	end
	self._jets = jets
end

function NitroController._destroyFlames(self)
	for _, jet in self._jets do
		if jet.attachment.Parent then
			jet.attachment:Destroy()
		end
	end
	self._jets = {}
	--[[ ...and forget that they were alight, which is load-bearing rather than tidy. `_setFlame`
		only acts on a CHANGE, and a steal rebuilds the jets in the middle of a burn: left true, the
		next `_setFlame(true)` would return early and the new emitters would sit disabled for the
		rest of the bottle. Every rebuild starts from "the flame is out", which is what the fresh
		emitters actually are. ]]
	self._flameOn = false
end

--- Flame and light follow the burn exactly. Guarded on a change so a race is not two property
--- writes per jet per frame for the 75% of it that is not a burn.
function NitroController._setFlame(self, on: boolean)
	if self._flameOn == on then
		return
	end
	self._flameOn = on
	for _, jet in self._jets do
		for _, emitter in jet.emitters do
			emitter.Enabled = on
		end
		if jet.light then
			jet.light.Enabled = on
		end
	end
end

-- The Nitro group may contain a looped burn sound. SoundController gives this controller an owned
-- playback clone so release can stop the exact sound Roblox is playing.
function NitroController._stopSound(self)
	local sound = self._nitroSound
	self._nitroSound = nil
	if sound then
		sound:Stop()
		sound:Destroy()
	end
end

--[[ The camera push. Asymmetric on purpose (`NitroConfig.Fov`): in fast so the press has an
	instant consequence, out slowly so letting go glides rather than competing with the press for
	the player's attention.

	Pushed at the camera every frame rather than on the two frames it changes, because
	`RaceCameraController` re-asserts FieldOfView every render frame and a value written once would
	be gone before the player saw it. ]]
function NitroController._stepFov(self, dt: number)
	local cfg = NitroConfig.Fov
	if cfg.Deg == 0 then
		return
	end
	local want = if self._burning then cfg.Deg else 0
	local time = if self._burning then cfg.RiseTime else cfg.FallTime
	-- A time constant stated as "seconds to get there" is 1/seconds as a rate, floored so a zero
	-- in the config snaps instead of dividing by nothing.
	self._fov = approach(self._fov, want, if time > 0 then 1 / time else math.huge, dt)
	if math.abs(self._fov) < 0.01 then
		self._fov = 0
	end
	local camera = self._camera
	if camera then
		camera:addFov(self._fov)

		local shakeConfig = NitroConfig.Shake
		local shakeTarget = if shakeConfig.Enabled and self._burning then 1 else 0
		local shakeTime = if shakeTarget > self._shake then shakeConfig.RiseTime else shakeConfig.FallTime
		self._shake = approach(self._shake, shakeTarget, if shakeTime > 0 then 1 / shakeTime else math.huge, dt)
		if self._shake < 0.001 then
			self._shake = 0
		end
		if camera.setNitroShake then
			camera:setNitroShake(self._shake)
		end
	end
end

-- === The frame ===============================================================

function NitroController._step(self, dt: number)
	-- The car first: a steal swaps it mid-race and everything below is sized to whichever one we
	-- are actually sitting in.
	self:_bindCar(self._road and self._road:getCar() or nil)

	local burn = self:_wantBurn()
	if burn ~= self._burning then
		self._burning = burn
		--[[ The kick rides on the RISING edge only, which is why the scale and the kick go over in
			the same call: `DriveController.setNitro` fires the kick exactly when the scale crosses
			from off to on, so it cannot be double-paid by a frame where the tank refilled and the
			key was still down. ]]
		if burn then
			local power = self._power or NitroConfig.powerFor(nil)
			self._drive:setNitro(power.scale, NitroConfig.Power.Kick)
			-- Only when a group has actually been named. `PlayRandom` warns once about a group it
			-- cannot find, and a nil here means nobody has chosen a clip yet rather than that one
			-- is missing (`NitroConfig.Sound`).
			local group = NitroConfig.Sound.Group
			if group and self._sounds then
				self:_stopSound()
				self._nitroSound = self._sounds:PlayRandomOwned(group)
			end
		else
			self:_stopSound()
			self._drive:setNitro(nil)
		end
	end

	self:_stepTank(dt)
	self:_setFlame(self._burning)
	self:_stepFov(dt)
end

-- === Input ===================================================================

--[[ Bind the keys for the length of a race.

	Bound at `NitroConfig.BindPriority` and SUNK, on the same argument `StealConfig.BindPriority`
	makes: the stock place-side `Driver` binds its raw-input handler at `ContextActionPriority.High`
	(3000) and sinks every key its Keymap names. LeftShift and the left bumper are not in that
	Keymap, so today this priority costs nothing. It is here so a rig that grows a LeftShift binding
	tomorrow loses the argument instead of winning it silently.

	Begin AND End, unlike the bail's begin-only binding, because this is a hold. `Cancel` (which
	ContextActionService fires when a binding is taken away underneath a held key) lands in the same
	branch as End, which is what stops a menu opening mid-burn leaving the bottle alight. ]]
function NitroController._bind(self)
	if self._bound then
		return
	end
	self._bound = true
	ContextActionService:BindActionAtPriority(ACTION_NAME, function(_, inputState)
		self._keyHeld = inputState == Enum.UserInputState.Begin
		return Enum.ContextActionResult.Sink
	end, false, NitroConfig.BindPriority, table.unpack(NitroConfig.Keys))
end

function NitroController._unbind(self)
	if not self._bound then
		return
	end
	self._bound = false
	ContextActionService:UnbindAction(ACTION_NAME)
	self._keyHeld = false
end

-- === Public ==================================================================

--[[ PUBLIC (DrivingHudController) — the on-screen NITRO button is down, or is not.

	A separate flag from the key rather than the same one, because both are legitimately live at
	once on a touch device with a keyboard and neither may cancel the other. See the header. ]]
function NitroController.setHudHeld(self, held: boolean)
	self._hudHeld = held == true
end

--- PUBLIC — how full the bottle is, 0..1. The bar reads this.
function NitroController.getTank(self): number
	return self._tank
end

--- PUBLIC — is it alight right now? The bar's hot colour and its pulse ride on this.
function NitroController.isBurning(self): boolean
	return self._burning
end

--[[ PUBLIC — would a press light it right now?

	Deliberately does NOT ask whether the car is driving. This answers "is there enough in the
	bottle", which is what a readout wants to say; a frozen world should not make the gauge read
	empty when the tank is full. `_wantBurn` is where the driving check belongs and it is the only
	thing that has to make the distinction. ]]
function NitroController.canFire(self): boolean
	return self._tank >= NitroConfig.Tank.MinToFire
end

--- PUBLIC — is the feature switched on at all? The HUD asks once, so a place with the config off
--- draws no bar and no button rather than a dead one.
function NitroController.isEnabled(_self): boolean
	return NitroConfig.Enabled == true
end

--[[ PUBLIC (PickupController) — is the bottle actually live right now?

	A different question from `isEnabled`, and the difference is the one that matters to a caller
	about to PAY into the tank: this is false before the first race, after one ends, and in a rig
	missing the drive or road layer `_onRaceStart` refuses to run without. In every one of those
	states `reward` is a no-op, so a caller that only checked `isEnabled` would spend a player's
	nitro pack into nothing and clear their slot for it.

	It is the same `_active` `reward` itself gates on, exposed rather than re-derived, so the two can
	only ever agree. ]]
function NitroController.isRunning(self): boolean
	return self._active == true
end

--[[ PUBLIC (AdminPanelController): rebuild the flame on the car we are in, after the panel flips
	`NitroConfig.FlameVfx`. A burn in progress relights on the next frame, because `_destroyFlames`
	forgets the flame was on and `_step` asks again. False when no race has a car to rebuild on. ]]
function NitroController.debugRefresh(self): boolean
	local car = self._car
	if not (self._active and car) then
		return false
	end
	self:_destroyFlames()
	self:_buildFlames(car)
	return true
end

--[[ PUBLIC (NearMissController) — driving well pays the bottle back.

	`fraction` is of a FULL tank, not of the remainder, so a payout is worth the same whether the
	bottle is nearly empty or nearly full. That is the readable rule: five near misses is half a
	bottle, always.

	It lands mid-burn as well as between them (`NitroConfig.Gain.WhileBurning`), and refusing it
	would be backwards: threading traffic is exactly what nitro makes dangerous, so the moment it
	pays best is the moment it is being spent. It does NOT reset the refill pause, because the pause
	is about the burn, not about the tank moving.

	`always` (2026-10-08) skips the `WhileBurning` gate, for a NITRO PACK (`PickupController._onUsed`).
	The gate was turned off in a balance pass for the earned trickle, and a pack went through the same
	door — so a pack collected mid-boost vanished from the slot and put nothing in the bottle (the
	owner: "sometimes collecting a nitro powerup doesn't actually fill up my nitro"). A pack is an item
	the player picked up and spent; it pays every time. ]]
function NitroController.reward(self, fraction: number?, always: boolean?)
	if not (self._active and type(fraction) == "number" and fraction > 0) then
		return
	end
	if self._burning and not NitroConfig.Gain.WhileBurning and not always then
		return
	end
	self._tank = math.clamp(self._tank + fraction, 0, 1)
end

-- === Lifecycle ===============================================================

function NitroController._onRaceStart(self)
	self:_onRaceEnd() -- idempotent: a revive re-enters through here and must not stack a second loop
	-- The two that cannot be worked around. Without the drive layer there is no speed dial to
	-- raise, and without the road there is no way to tell which car we are in; a bottle that drains
	-- and does nothing is worse than no bottle, so the feature stands down rather than half-runs.
	if not (NitroConfig.Enabled and self._drive and self._road) then
		return
	end
	self._active = true
	self._tank = math.clamp(NitroConfig.Tank.StartFraction, 0, 1)
	self._sinceBurn = math.huge -- a fresh run is not waiting out a pause it never took
	self:_bind()
	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_step(dt)
	end)
end

--[[ Everything down, in the order that matters: stop the loop, then take the claims back.

	`setNitro(nil)` before the car reference goes, because the drive layer needs a live car to put
	the speed dial back on. It is belt and braces either way: `DriveController._teardown` restores
	the dial itself and a wreck reaches that first, but a race that unwinds by any other path (an
	error mid-frame, a place with the shim switched off) has to leave the car unraised too. ]]
function NitroController._onRaceEnd(self)
	self._active = false
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	self:_unbind()
	self._hudHeld = false
	self._burning = false
	self:_stopSound()
	if self._drive then
		self._drive:setNitro(nil)
	end
	self:_setFlame(false)
	self:_destroyFlames()
	self._car = nil
	self._power = nil
	self._fov = 0
	self._shake = 0
	if self._camera then
		self._camera:addFov(0)
		if self._camera.setNitroShake then
			self._camera:setNitroShake(0)
		end
	end
end

NitroController:withRemoteEvents({
	{
		RaceStart = function()
			NitroController:_onRaceStart()
		end,
		--[[ A wreck ends the burn and everything hanging off it. It is NOT the end of the run any
			more (`ReviveService` owns that), so this is a teardown that expects to be re-entered:
			`RaceRevived` below re-arms it on the car going back on the road, with a full bottle,
			which is the same rule a steal gets and for the same reason. Coming back from a wreck
			with the empty tank you crashed on would punish the revive. ]]
		RaceWrecked = function()
			NitroController:_onRaceEnd()
		end,
		RaceRevived = function()
			NitroController:_onRaceStart()
		end,
		RaceEnd = function()
			NitroController:_onRaceEnd()
		end,
	},
})

NitroController:withLifecycle({
	init = function(self)
		self._active = false
		self._bound = false
		self._tank = 0
		self._sinceBurn = math.huge
		self._burning = false
		self._keyHeld = false -- LeftShift / ButtonL1
		self._hudHeld = false -- the on-screen NITRO button
		self._car = nil
		self._power = nil -- { scale, seconds } for the car we are in; see _bindCar
		self._jets = {} -- the two flame attachments, for the length of one car
		self._flameOn = false
		self._fov = 0 -- degrees of camera push, eased; see _stepFov
		self._shake = 0 -- eased nitro vibration strength, 0..1
		self._nitroSound = nil -- currently playing Sound from SoundService.Nitro, if any

		NitroConfig.assertSane()
	end,

	start = function(self)
		--[[ Held for the session rather than looked up per frame, the same way WindController holds
			its two: Shard builds every controller once at boot and none of these can go away. The
			camera is optional on purpose (a place running the stock camera still gets the mechanic,
			just without the push), which is why every use of it is behind a nil check. ]]
		self._drive = Shard.get("DriveController")
		self._road = Shard.get("RoadController")
		self._camera = Shard.get("RaceCameraController")
		self._sounds = Shard.get("SoundController")
		local steal = Shard.get("StealController")
		if steal then
			self._stealRefresh = steal:onStolen(function()
				self._bodyKey = nil
				self:_bindCar(self._road and self._road:getCar() or nil)
			end)
		end
		if self._sounds and NitroConfig.Sound.Group then
			self._sounds:Preload(NitroConfig.Sound.Group)
		end
		if not (self._drive and self._road) then
			self.log:warn("DriveController or RoadController unavailable; nitro is off for this session.")
		end
	end,
})

return NitroController
