--[[
	WindController  (client)
	------------------------
	The air going past when you are flat out. One cloned Part full of streaks that rides in front
	of the camera, swelling in over the last few percent of what the car can do and gone again the
	moment you lift.

	Everything about how a streak LOOKS is authored on `ReplicatedStorage.WindParticles` and is
	left alone — texture, colour, flipbook, squash, the velocity-parallel orientation that makes
	them streaks rather than dots. This file owns the properties that could not be authored,
	because they depend on where the camera is and how fast the car is going: Rate, Speed,
	Lifetime, Size, Transparency and how it composites. Every number behind them is in `WindConfig`.

	=== "FLAT OUT" IS A FRACTION OF THIS CAR'S CEILING, NOT A SPEED =============================

	Three numbers make the band, and each is read from the thing that actually owns it:

	  • The CEILING, from `DriveController:getTopSpeed()` — the car's base `MaxSpeed` attribute
	    times the boost scale, which is the fastest that car goes with accelerate held. Read live
	    rather than latched, so a steal that swaps what you are driving moves the band with it.
	  • The SPEED, from the car's assembly velocity projected onto the ROAD's forward axis.
	  • The CONVERSION between them, because the attribute is not studs per second
	    (`WindConfig.StudsPerMaxSpeed` owns that measurement and how to re-take it).

	Both of the axes in the middle one are deliberate. The CAR rather than the camera, because the
	camera's frame-to-frame speed swings ±15 studs/s around the car's steady value — its follow lag
	is the whole point of that shot — and a noisy input against a sharp threshold flickers. Along
	the ROAD rather than along the nose, because a nose-relative reading picks up sideways velocity
	and hard steering ratchets it past 120 on a car doing 84, which would pay out a flat-out effect
	for cornering.

	It follows that there is no wind while the car is not being driven — at either end of a race
	there is no car at all, and a wreck coasts out of the band on its own, which is why there is no
	wreck case anywhere in this file. What does NOT follow is a FROZEN car, and that is the one this
	file got wrong for a while: anchoring a part does not clear its velocity, so every scripted
	freeze in this game leaves a car still reporting the speed it was doing at the moment it was
	frozen. `_velocity` is where that is dealt with.

	=== OUT OF THE CAR, THE AIR IS THE ONE YOU ARE FLYING THROUGH ==============================

	A bail is not "no car". It is the player, in the open, doing whatever the car was doing — so
	StealController hands the flight in (`setFlight`, the same handover and the same getter the race
	camera takes) and while it is set the band is measured against the ARC's along-road speed and the
	streaks are aimed along the arc rather than flat down the road.

	The lopsided arc then ends the effect on its own, which is the reason this is a handover rather
	than a switch-off: you leave the seat at exactly the car's speed (`StealConfig.Launch.ForwardKeep`
	= 1), so the air rips past through the throw and the rise, and `Flight.Glide` brakes you to
	traffic pace within a tenth of a second of the apex — well under the bottom of the band. The wind
	is dying by the top of the jump and gone through the float down. `WindConfig.Flight` owns both
	halves of that, and the switch that cuts it dead at the seat instead.

	=== THE RIG LIVES UNDER THE CAMERA =========================================================

	`workspace.CurrentCamera` is a real parent for BaseParts: they render, and they are not in
	Workspace. That last part is the reason. This game raycasts and region-queries the road
	constantly — traffic gaps, obstacle hits, the steal's landing check — and a 90-stud invisible
	box travelling with the player would be in the way of all of it. A part under the camera
	cannot be found by any of them, which is a stronger guarantee than remembering to set
	CanQuery and CanTouch on it (they are set anyway).

	Streaks themselves are NOT locked to the part. They are born inside the box and then left in
	world space, so the camera drives through and past its own weather. Locked to the part they
	would travel with you, which reads as a windscreen effect rather than as air.

	Binds one frame priority after RaceCameraController so it reads the camera where that shot
	actually left it this frame, rather than where it was last frame.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local WindConfig = require(ReplicatedStorage.shared.Configs.WindConfig)

local WindController = Shard.new("WindController")

-- BindToRenderStep unbinds by name, so this is one shared name for the session — same treatment,
-- same reason, as the race camera's.
local RENDER_NAME = "RaceWind"
-- One past the camera's own binding (Camera + 1), so the CFrame this reads is the finished shot.
local RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 2

local FLAT = Vector3.new(1, 0, 1)

--[[ How much the ramp has to move before the streaks are re-tuned.

	Rate is a number but Size and Transparency are NumberSequences, which means a fresh allocation
	per emitter per frame if this is applied blind. A hundredth of the band is invisible on a
	streak and takes the rebuild down to a handful of frames per second of driving. ]]
local APPLY_EPSILON = 0.01

-- Exponential approach: closes most of the gap in `tau` seconds regardless of framerate.
local function approach(current: number, target: number, tau: number, dt: number): number
	if tau <= 0 then
		return target
	end
	return current + (target - current) * (1 - math.exp(-dt / tau))
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- === The rig =================================================================

--[[ Clone the authored part, take the properties that are ours, and hand back the emitters paired
	with the layer each one is driven by.

	Returns nil if the template is missing, which is a real state rather than an error: the art is
	place-side (it is not in the Rojo tree), so a place that has not had it added yet should drive
	perfectly well with no wind rather than not drive. ]]
function WindController._build(self, camera: Camera): boolean
	local template = ReplicatedStorage:FindFirstChild(WindConfig.Template)
	if not (template and template:IsA("BasePart")) then
		if not self._warnedTemplate then
			self._warnedTemplate = true
			self.log:warn(("No BasePart named %q in ReplicatedStorage; no wind."):format(WindConfig.Template))
		end
		return false
	end

	local rig = template:Clone()
	rig.Name = "RaceWind"
	rig.Anchored = true
	rig.Transparency = 1
	rig.CanCollide = false
	rig.CanQuery = false
	rig.CanTouch = false
	rig.CastShadow = false
	rig.Locked = true
	rig.Size = Vector3.new(WindConfig.Box.Width, WindConfig.Box.Depth, WindConfig.Box.Height)

	--[[ BY NAME, not by `GetChildren` order. The emitters are called Layer1..Layer3 precisely so
		that the config's Layers list can be read against them in the Explorer, and GetChildren
		hands back insertion order — which for this template is Layer3, Layer1, Layer2, and would
		have quietly given Layer3 the first layer's numbers. ]]
	local emitters = {}
	for _, child in rig:GetChildren() do
		if child:IsA("ParticleEmitter") then
			table.insert(emitters, child)
		end
	end
	table.sort(emitters, function(a, b)
		return a.Name < b.Name
	end)

	local layers = {}
	for index, emitter in emitters do
		-- The two that the whole effect depends on and that are cheap enough to state rather than
		-- trust: streaks must be left behind in the world, and they must fly out of the part's +Y,
		-- which is the axis `_place` points backward down the road.
		emitter.LockedToPart = false
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Lifetime = WindConfig.Lifetime
		emitter.SpreadAngle = WindConfig.SpreadAngle
		-- How it composites. Authored for a volume seen from far away and wrong up against the
		-- camera; WindConfig's note has the whole argument.
		emitter.LightEmission = WindConfig.LightEmission
		emitter.LightInfluence = WindConfig.LightInfluence
		emitter.Enabled = false
		local def = WindConfig.Layers[((index - 1) % #WindConfig.Layers) + 1]
		table.insert(layers, { emitter = emitter, def = def })
	end

	if #layers == 0 then
		if not self._warnedTemplate then
			self._warnedTemplate = true
			self.log:warn(("%q has no ParticleEmitter under it; no wind."):format(WindConfig.Template))
		end
		rig:Destroy()
		return false
	end

	rig.Parent = camera
	self._rig = rig
	self._layers = layers
	self._applied = nil -- nothing written yet, so the first frame always applies
	return true
end

function WindController._destroy(self)
	if self._rig then
		self._rig:Destroy()
		self._rig = nil
	end
	self._layers = nil
	self._lastPos = nil
	self._t = 0
	self._applied = nil
	self._appliedFlow = nil
end

-- === Per-frame ===============================================================

--[[ Put the box `Ahead` studs down the road with its emission axis pointing back at the camera.

	Emission runs along the part's +Y (EmissionDirection.Top, as authored), so the CFrame is built
	looking DOWN the backward direction and then pitched a quarter turn, which swings that look
	axis onto +Y. The part's axes afterwards are (right, backward, up) — which is the order
	`WindConfig.Box` is written in, and the reason it is written in that order. ]]
function WindController._place(self, position: Vector3, direction: Vector3)
	local origin = position + direction * WindConfig.Ahead + Vector3.yAxis * WindConfig.Lift
	local back = -direction
	self._rig.CFrame = CFrame.lookAt(origin, origin + back) * CFrame.Angles(-math.pi / 2, 0, 0)
end

-- Write the ramp onto the emitters. Only ever called when `t` has actually moved (APPLY_EPSILON)
-- or the effect has just switched on or off.
function WindController._apply(self, t: number)
	local on = t > 0
	local flow = self._flow or 0
	local flowConfig = WindConfig.Flow
	local size = WindConfig.Size * (1 + WindConfig.SizeGrowth * t) * (1 + flowConfig.SizeBoost * flow)
	local speed = lerp(WindConfig.SpeedIdle, WindConfig.SpeedFull, t)
	local opacity = math.clamp(lerp(WindConfig.OpacityIdle, WindConfig.OpacityFull, t) + flowConfig.OpacityBoost * flow, 0, 1)
	local clear = 1 - opacity

	--[[ In and out inside the streak's own life. Both ends are fully transparent: the far one
		hides the box's near face (a streak born mid-frame with no fade is a pop), and the near
		one keeps it from vanishing while it is still the size of the screen. ]]
	local transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(WindConfig.FadeIn, clear),
		NumberSequenceKeypoint.new(WindConfig.FadeOut, clear),
		NumberSequenceKeypoint.new(1, 1),
	})

	for _, layer in self._layers do
		local emitter, def = layer.emitter, layer.def
		emitter.Enabled = on
		if on then
			emitter.Rate = def.Rate * t * (1 + flowConfig.RateBoost * flow)
			local v = speed * def.Speed
			-- A little spread on the speed too, so streaks separate on the way past instead of
			-- travelling as one sheet.
			emitter.Speed = NumberRange.new(v * 0.8, v * 1.2)
			emitter.Size = NumberSequence.new(size * def.Size)
			emitter.Transparency = transparency
		end
	end

	self._applied = t
	self._appliedFlow = flow
end

--[[ Whose velocity the band is measured against this frame, or nil when nothing is moving through
	the air we are drawing.

	TWO SUBJECTS, and the flight wins while there is one. On the road it is the car; out of the car
	it is the arc StealController is integrating, handed in through `setFlight`. Read through the
	getter every frame rather than latched, for the same reason the camera reads it that way: the
	flight advances on Heartbeat and this runs on RenderStep, so the newest state there is is the
	right one.

	AN ANCHORED CAR IS NOT A STOPPED CAR. `AssemblyLinearVelocity` is NOT cleared when a part is
	anchored — it goes on reporting whatever the assembly was doing at the instant it was frozen, for
	as long as it stays frozen, and moving it by CFrame does not disturb that either. (Measured, in a
	playtest: a part anchored while doing 100 studs/s still read 100 studs/s a tenth of a second
	later, after being teleported.) That matters here because every scripted freeze in this game is a
	car that goes on CLAIMING to be flat out — the bail anchors every part of the car it leaves
	behind (`StealController._onBail`), the whiff after a bad one leaves it that way, and so do the
	race-entry freeze and the void guard. Without this check the wind, once started, simply never
	stopped again: the whole flight, the whole wreck, the whole revive.

	Nil means "no wind, and no argument about which way it should be blowing" — an ordinary state at
	either end of a race and through all of the above, not a fault. ]]
function WindController._velocity(self): Vector3?
	local getter = self._flightGetter
	if getter then
		if not WindConfig.Flight.Enabled then
			return nil -- the hard cut: leaving the seat ends the effect, whatever you left it at
		end
		local view = getter()
		return view and view.velocity
	end

	local car = self._road and self._road:getCar()
	local primary = car and car.PrimaryPart
	if not (primary and primary.Parent) then
		return nil
	end
	if primary.Anchored then
		return nil
	end
	return primary.AssemblyLinearVelocity
end

--[[ Which way the air is going past — the axis the box is placed along and the streaks fly back
	down. Flat along the road while driving, tilted with the throw while airborne.

	THE TILT IS THE VERTICAL ONLY, and deliberately not the whole velocity. A bail's cross velocity
	is the player's own steering (`StealConfig.Flight.SteerSpeed`, 24 studs/s against 112 along the
	road), so folding it in would swing the entire box sideways every time they corrected a lane —
	the same reason the band ignores sideways speed rather than reading the nose. Up is different: it
	is the shape of the jump, and at the throw it is the same order as the road speed — 108 studs/s of
	rise against ~112 along, so about 44° off the road — decaying to nothing by the apex on its own.

	Placement and emission are the same axis on purpose — see `_place`. Tilt the streaks without
	tilting the box they are born in and they no longer fly through the camera at all: at 44° a
	streak born at the far face passes fifty studs overhead. ]]
function WindController._travel(self, forward: Vector3, velocity: Vector3?): Vector3
	local tilt = math.clamp(WindConfig.Flight.Tilt, 0, 1)
	if not (self._flightGetter and velocity and tilt > 0) then
		return forward
	end
	local along = velocity:Dot(forward)
	if along <= 0 then
		return forward -- thrown backwards, or stopped: nothing to lean the box off
	end
	local aimed = forward * along + Vector3.yAxis * (velocity.Y * tilt)
	return if aimed.Magnitude > 1e-3 then aimed.Unit else forward
end

--[[ How far into the flat-out band we are this frame, 0..1 — and the direction to point the streaks
	down, which comes back with it because both are read out of the same velocity.

	Nil for the direction means "nothing to measure": no road frame, nothing moving, or a car with no
	`MaxSpeed` to be a fraction of. All of them are ordinary states rather than faults, and all of
	them want the same answer — no wind — which the zero gives without a special case. ]]
function WindController._measure(self): (number, Vector3?)
	local road = self._road
	local info = road and road:getRoadInfo()
	if not info then
		return 0, nil
	end

	local velocity = self:_velocity()
	-- The car's own ceiling, live: a steal swaps what you are driving, and the band has to move
	-- with it rather than stay pinned to the car the race started in.
	local dial = self._drive and self._drive:getTopSpeed()
	if not (velocity and dial) then
		return 0, info.forward
	end
	local top = dial * WindConfig.StudsPerMaxSpeed
	local start = top * WindConfig.StartFraction
	local span = top * (WindConfig.FullFraction - WindConfig.StartFraction)
	if span <= 0 then
		return 0, info.forward
	end

	local speed = velocity:Dot(info.forward)
	self._speed = speed -- read by nothing; kept because it is the first thing to print when tuning
	local t = math.clamp((speed - start) / span, 0, 1) ^ WindConfig.Curve
	return t, self:_travel(info.forward, velocity)
end

function WindController._step(self, dt: number)
	local camera = workspace.CurrentCamera
	if not (camera and self._rig) then
		return
	end
	-- A respawn or a mode change can hand us a new camera; the rig follows it rather than being
	-- orphaned in the old one, which would leave it rendering nowhere.
	if self._rig.Parent ~= camera then
		self._rig.Parent = camera
	end

	local target, direction = self:_measure()
	--[[ On the road this is the road's axis, which is constant for a whole race — so it only ever
		changes on the first frame that finds one, and keeping the last is what stops a frame without
		a road frame swinging the box. In a bail it leans with the arc and moves every frame, which is
		smooth for free: the tilt is the throw's own vertical speed decaying under `RiseGravity`. ]]
	if direction then
		self._direction = direction
	end

	self._t = approach(self._t, target, if target > self._t then WindConfig.RiseTime else WindConfig.FallTime, dt)
	-- Below this the ramp is worth no particles at all, and snapping it to zero is what lets the
	-- emitters actually switch off instead of trickling forever down the tail of the fall.
	if self._t < 0.005 then
		self._t = 0
	end

	self:_place(camera.CFrame.Position, self._direction)

	local applied = self._applied
	local appliedFlow = self._appliedFlow
	if applied == nil
		or math.abs(self._t - applied) >= APPLY_EPSILON
		or appliedFlow == nil
		or math.abs(self._flow - appliedFlow) >= APPLY_EPSILON
		or (self._t == 0) ~= (applied == 0)
	then
		self:_apply(self._t)
	end
end

-- === Flight mode =============================================================

--[[ PUBLIC (StealController) — the player is out of the car and in the air; measure the wind
	against the arc rather than against the car they left. Pass nil to hand it back.

	THE CAR CANNOT BE LEFT TO ANSWER FOR THIS. A bail anchors every part of it and flies it down the
	road by CFrame, and an anchored assembly keeps reporting the speed it was frozen at (`_velocity`)
	— so a bail taken flat out used to leave the wind running at full for the whole flight, the perch
	and the mount, and a whiff left it running until the race ended. The handover is what ends it,
	and it ends it the honest way: the arc brakes to traffic pace and drops out of the band.

	The same getter and the same contract as `RaceCameraController.setFlight` — StealController hands
	both of us the one it is already keeping (`_cameraSubject`), so the air and the shot can never
	disagree about where the player is or how fast they are going. Only `velocity` is read here.
	Returning nil for a frame reads as no wind, which is the safe direction to fail in. ]]
function WindController.setFlight(self, getter: (() -> { position: Vector3, velocity: Vector3 }?)?)
	self._flightGetter = getter
end

--- PUBLIC (NearMissController) — 0..1 extra intensity for an active Flow chain. The wind still
--- decides whether speed is high enough to render anything at all.
function WindController.setFlow(self, amount: number?)
	self._flow = if type(amount) == "number" then math.clamp(amount, 0, 1) else 0
end

-- === Lifecycle ===============================================================

function WindController._onRaceStart(self)
	self:_destroy() -- idempotent: a second RaceStart rebuilds cleanly rather than stacking rigs
	if not WindConfig.Enabled then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if not self:_build(camera) then
		return
	end

	-- Facing down the camera until the first frame reads a road axis. It is already pointing that
	-- way by the time a race starts, and nothing is emitting yet either, so this is belt and braces.
	local look = camera.CFrame.LookVector * FLAT
	self._direction = if look.Magnitude > 1e-3 then look.Unit else Vector3.zAxis
	self._speed = 0
	self._t = 0

	if not self._bound then
		self._bound = true
		RunService:BindToRenderStep(RENDER_NAME, RENDER_PRIORITY, function(dt)
			self:_step(dt)
		end)
	end
end

function WindController._onRaceEnd(self)
	if self._bound then
		RunService:UnbindFromRenderStep(RENDER_NAME)
		self._bound = false
	end
	-- Dropped here as well as by StealController, because the two teardowns race: a race that ends
	-- mid-flight must not leave the next one reading a getter over a flight that no longer exists.
	self._flightGetter = nil
	self:_destroy()
end

WindController:withRemoteEvents({
	{
		RaceStart = function()
			WindController:_onRaceStart()
		end,
		--[[ No RaceWrecked and no RaceRevived, and both absences are the point. A wreck coasts to
			a stop and the wind dies with it because the camera stops moving; a revive pulls away
			again and it comes back. Neither needs telling. ]]
		RaceEnd = function()
			WindController:_onRaceEnd()
		end,
	},
})

WindController:withLifecycle({
	init = function(self)
		self._bound = false
		self._rig = nil
		self._layers = nil
		self._direction = Vector3.zAxis -- the road's forward axis once a race has one, leaned in a bail
		self._flightGetter = nil -- set for the length of a bail; see setFlight
		self._speed = 0 -- last measured along-road speed, for tuning
		self._t = 0 -- how far into the flat-out band, 0..1, smoothed
		self._applied = nil -- last `t` written to the emitters; see APPLY_EPSILON
		self._appliedFlow = nil -- last Flow strength written alongside `_applied`
		self._flow = 0 -- skill-chain accent; it cannot turn wind on below the speed band
	end,

	start = function(self)
		--[[ Both held for the session rather than looked up per frame. Neither can go away: Shard
			builds every controller once at boot, and both of these hand back nil rather than
			throwing when there is no race — which is exactly what `_measure` reads as "no wind". ]]
		self._road = Shard.get("RoadController")
		self._drive = Shard.get("DriveController")
		if not self._drive then
			self.log:warn("DriveController unavailable; nothing to read a top speed off, so no wind.")
		end
	end,
})

return WindController
