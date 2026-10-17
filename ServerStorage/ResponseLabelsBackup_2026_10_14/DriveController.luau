--[[
	DriveController  (client)
	-------------------------
	The arcade drive layer. Two rules, both straight out of the mobile traffic-racer playbook:

	  1. The car is ALWAYS on the throttle. Nobody ever presses accelerate.
	  2. The player only changes LANE. The car can never point far off the road, spin out, or
	     U-turn back up its own road.

	Rule 2 has two implementations and `DriveConfig.DirectSteering` picks one. They are different
	ideas about what steering is, so know which one you're reading:

	  • DIRECT (the default). Input is a request to be somewhere else across the road. We write
	    the car's cross-road VELOCITY straight onto the assembly, eased in and out, and hold the
	    nose at a few cosmetic degrees of lean into that movement with a yaw servo. The lane
	    change causes the rotation. Nothing winds up, so it answers the frame you press — the
	    highway lane-change feel of Mr Racer / Traffic Racer, which is the game's reference.

	    This is the one place the layer stops reshaping inputs and takes the wheel: the tuned
	    steering rack no longer decides where the car goes sideways (it still turns the front
	    wheels for show — `RackSteerVisual`). Signed off deliberately, scoped to steering, and
	    reversible with one boolean. Everything else about the rig is untouched.

	    Its two numbers — how fast the car slides and how fast that eases in — are scaled up when a
	    FINGER is steering (`DriveConfig.Touch`, `_touchSteering`). Not a second steering model and
	    not a difficulty dial: an on-screen button publishes the same full ±1 a key does but can't
	    hold it as precisely, so the ease-in swallows a short press and mobile reads as unresponsive.
	    Touch gets the identical lane change, answered quicker.

	  • CONE. Input goes to the tuned rack, the nose swings up to 30°, and grip converts that
	    into sideways movement. The rotation causes the lane change, so it has to come first and
	    be big — which is exactly why it read as understeer in third person. Kept as the honest
	    physical baseline and a one-line A/B.

	Where it hooks in. Driving is the stock CarBones rig and per the handoff doc (§1) we do
	not re-tune it, so this is a thin shim over the two *inputs* that rig takes. The car's
	`Scripts.Chassis` ModuleScript exposes `UpdateThrottle(speed, throttle)` and
	`UpdateSteering(steer, speed)`, and the stock `Driver` LocalScript calls exactly those,
	once per input frame, with the player's raw -1..1 values. The deployed Driver requires
	the module instance *inside the car* (`Car.Scripts.Chassis`), and `require` is cached per
	client — so requiring that same instance here hands us the very table the Driver is
	calling into. We wrap the two functions, reshape the numbers, and let the untouched stock
	code do all the physics.

	ONE THING HERE IS NOT AN INPUT. `_stiffenRack` writes `LinearResponsiveness` onto the car's
	steering rack servo at install and puts it back on teardown. The shipped value is soft enough
	that the rack self-oscillates and waggles the front wheels ±5° at ~6Hz on a dead-straight road,
	which is the body wobble — it is a defect in the rig, not a tuning preference, and it is one
	property with a measured justification (DriveConfig.SteerRackResponsiveness). It lives here for
	exactly the reason the wrapping below does: the car is place-side, so anything authored onto the
	model is undone by the next redress.

	Why wrap rather than edit the stock scripts: Driver/Chassis live in the place, inside each
	car, not in this repo. An edit there is invisible to git and has to be re-applied to every
	car redressed off CarBones. Wrapping keeps the whole rule set in one version-controlled
	file and it applies to any car that spawns. The cost is that it depends on those two
	function names; if a future CarBones drops them, `_install` warns and the race falls back
	to stock controls rather than breaking.

	Both models write velocity, never a CFrame — see _recover for why that distinction is not
	negotiable — and both only ever touch the assembly we own. Per-frame `AssemblyLinearVelocity`
	writes on the car's PrimaryPart are the same thing ObstacleController's shove and wreck coast
	already do, so the suspension is known to tolerate them.

	The cone is enforced on the steering input, so the tuned rack and suspension do the actual
	work and nothing fights them:
	  • inside FreeYawDeg        — no-op, full authority
	  • FreeYawDeg → MaxYawDeg   — steering that points you further out fades to zero
	  • past MaxYawDeg           — the shim countersteers for you, back toward the road
	  • past RecoverYawDeg       — backstop: nothing steerable gets here, so we take the heading
	                               back directly by blending the owned assembly's yaw rate. That's
	                               the same tool ObstacleController uses for its hit kicks — never
	                               a CFrame write, which is what synthesises the runaway velocity
	                               RoadController's rebase has to work around.
	  • past HardYawDeg         — the blend is a negotiation, and a collision with a solid traffic
	                               car sustains enough torque to win it while denying the rack the
	                               traction to countersteer. So past here the yaw rate is SET, not
	                               blended. With MaxYawRate capping the spin rate underneath it,
	                               that pair is what makes a full U-turn unreachable.

	AND ONE BACKSTOP THAT ISN'T ABOUT YAW AT ALL. Everything above is about where the nose points,
	because that's all steering can affect; roll and pitch were left to the suspension, which is
	right until a collision puts the car on its roof and nothing anywhere brings it back. `_upright`
	is that — a righting servo past a generous deadband, and a placed reset if the servo loses. It
	writes the two rotation axes the steering models don't, so it composes with either of them
	rather than being a third model (DriveConfig.Upright).

	All of it is tuned in DriveConfig. Lifecycle rides the same race remotes everything else
	does, and the shim is inert whenever `_active` is false, so a wreck or a leave hands the
	car straight back to stock behaviour.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local RoadEdgeGuard = require(ReplicatedStorage.shared.Modules.RoadEdgeGuard)
local Shard = require(ReplicatedStorage.Packages.Shard)
local DriveConfig = require(ReplicatedStorage.shared.Configs.DriveConfig)
--- For `StudsPerMaxSpeed` alone — the chassis attribute is not in studs/s and that conversion is
--- measured and documented there. Same one number `RaceCameraController` reads. See `_engineAudio`.
local WindConfig = require(ReplicatedStorage.shared.Configs.WindConfig)
local AutomaticGearbox = require(ReplicatedStorage.shared.Modules.AutomaticGearbox)
local Vehicle = require(ReplicatedStorage.shared.Modules.Vehicle)

local DriveController = Shard.new("DriveController"):withDependencies({ "RoadController" })

-- Sign of a `steer` value that turns the car left (see DriveConfig.PositiveSteerIsLeft).
-- Heading error below is also signed "+ = pointed left", so the two share one convention:
-- steering is pushing the nose further out exactly when `steer * STEER_LEFT * err > 0`.
local STEER_LEFT = if DriveConfig.PositiveSteerIsLeft then 1 else -1

--[[ Studs/s of cross-road velocity change, between two of our own writes, that counts as somebody
	else's doing rather than chassis noise — see _lane. Sized against ObstacleConfig's smallest
	SideKick (Cone, 3 studs/s in one frame) and one 60Hz frame of the chassis pushing back against
	the crab (a few tenths). A noise floor, not a taste dial, which is why it isn't in DriveConfig. ]]
local EXTERNAL_LATERAL_FLOOR = 1.5

--[[ A device that cannot steer with anything BUT a finger — no keyboard, so the on-screen arrows and
	the stock touch slider are the only two inputs it has and both are the ones DriveConfig.Touch
	exists for. Read once: a player does not grow a keyboard mid-session, and the arrows are latched
	separately (see _touchSteering) so Studio's device emulator — which keeps KeyboardEnabled true —
	still exercises the touch path the moment you click one. ]]
local TOUCH_ONLY_DEVICE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Stock CarBones speedometer conversion. The audio gearbox consumes the same mph scale as the
-- dashboard, which keeps what the player hears synchronized with the visible gear change.
local MPH_PER_STUD = 0.6263

-- How long to wait for the car and its deployed driver controls before giving up on a race.
-- Generously past RaceConfig.EnterReadyTimeout — going live is the server's slow path.
local INSTALL_TIMEOUT = 15

--[[ How long a deployed Driver is allowed to look switched-off before we count it as a fault and
	put it back (`_reviveDriver`). Not zero, and the wait is the whole guard: a REAL get-out disables
	that script on purpose, and the seat it is leaving clears a moment after the exit reaches this
	client — the stock `LocalVehicleSeating` fires its exit handlers off a remote that is deliberately
	sent BEFORE the server unseats the body. Repair on the same frame and an ordinary get-out would
	re-arm the keys of a car nobody is in; a quarter of a second later the seat has spoken. ]]
local DRIVER_REVIVE_DELAY = 0.25

--- ...and how many times per race, because a Driver that switches itself off the instant it is
--- switched on is a fault we cannot fix from here, and a repair loop against it would spin for the
--- length of the run. Four is past any plausible burst of stale exits and nowhere near a loop.
local DRIVER_REVIVE_LIMIT = 4

-- === Heading =================================================================

--[[ Signed angle between the car's nose and the road's drive direction, radians.
	Positive = the nose is pointed LEFT of the road direction.

	`Vector3.yAxis:Cross(forward)` is the road's LEFT: a Roblox CFrame has
	right x up = -look, so up x look = -right. (RoadController exposes the same vector as
	`cross`; we derive it here so this file's sign convention can't drift from a label.)

	nil when we can't say — no road frame yet, or the nose is pointed at the sky mid-flip.
	Callers treat nil as "don't intervene", which degrades to stock controls. ]]
function DriveController._headingError(self): number?
	local info = self._road and self._road:getRoadInfo()
	local seat = self._seat
	if not (info and seat and seat.Parent) then
		return nil
	end

	local look = seat.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return nil
	end
	flat = flat.Unit

	local forward = info.forward
	local left = Vector3.yAxis:Cross(forward)
	return math.atan2(flat:Dot(left), flat:Dot(forward))
end

-- === Input shaping (what the wrappers hand the stock chassis) ================

--[[ Forward speed along the car's own nose, studs/s. Negative means we're travelling backwards,
	which the heading cone should make impossible — but the brake logic below leans on the sign,
	so it's read honestly rather than clamped. ]]
function DriveController._forwardSpeed(self): number
	local seat = self._seat
	if not (seat and seat.Parent) then
		return 0
	end
	return seat.CFrame.LookVector:Dot(seat.AssemblyLinearVelocity)
end

--[[ How much of the brake the player gets right now, 0..1.

	Full authority at speed, easing to nothing as the car approaches `MinSpeedFraction` of this
	run's peak, so holding the brake *settles onto a floor* rather than stopping. The floor is
	the point: the stock `UpdateThrottle` treats a held brake at a standstill as reverse (its
	`abs(currentSpeed) < 0.5` branch drives the motor target negative), which would undo the one
	rule this controller exists to enforce.

	The fade band is what keeps it smooth — snapping between full brake and full throttle at the
	floor would chatter. Inside the band the shaped throttle falls under the chassis's own 0.1
	idle threshold, so the car coasts onto the floor instead of fighting itself. ]]
function DriveController._brakeAllowance(self): number
	local peak = self._peakSpeed
	if peak <= 0 then
		return 0 -- no reference yet (first moments of a run); fail toward "always forward"
	end
	local floor = peak * DriveConfig.MinSpeedFraction
	local fade = math.max(peak * DriveConfig.BrakeFadeFraction, 1e-3)
	return math.clamp((self:_forwardSpeed() - floor) / fade, 0, 1)
end

--[[ Hold-to-go-faster. The lever is the car's own `MaxSpeed` attribute, which the stock Chassis
	already watches — `updateFromConfiguration` installs an AttributeChanged listener that re-reads
	it and re-runs InitializeDrivingValues — so this is the rig's supported speed dial rather than
	a poke at its internals.

	It has to be MaxSpeed and NOT the motors' target velocity. The stock throttle damps driving
	torque by exp(-3r²) with r = speed / MaxSpeed, and the car settles where that torque dies, far
	short of the target the motors were ever asked for — it is torque-limited, not target-limited.
	Raising the target alone does nothing; scaling MaxSpeed drags the torque curve up with it.

	Only acts on a change, so holding the key doesn't re-run the chassis setup every frame. ]]
function DriveController._setBoost(self, on: boolean)
	if self._boosting == on then
		return
	end
	self._boosting = on
	self:_applySpeedDial()
end

--[[ THE SPEED DIAL HAS TWO CLAIMANTS AND THEY ARE RESOLVED WITH `math.max`.

	Boost is held accelerate (`BoostSpeedScale`, free and forever). Nitro is `setNitro` below, a
	bigger scale bought out of a tank that runs out. Both want the same `MaxSpeed` attribute, so
	something has to say what happens when both are live.

	The highest wins; they are NOT multiplied. Multiplied, a player firing nitro would be at one
	speed with accelerate held and a different one without, off a button they are not thinking
	about, and the two would compound to well past anything the road was tuned for. Taken at the
	highest, nitro means one speed whatever else is held, and it always beats boost because
	`NitroConfig` asserts at load that every nitro scale is above the boost one.

	Note this is also why nothing here has to sequence the two: either claimant can change in any
	order, and the dial is always whatever the pair currently add up to.

	A THIRD CLAIMANT SINCE 2026-10-13: the Star pickup (`setStar`, `PickupConfig.Packs.Star`). Same
	rule, highest wins, so a star and a nitro burn together are whichever is faster rather than the
	two compounded. ]]
function DriveController._speedDial(self): number
	local boost = if self._boosting then DriveConfig.BoostSpeedScale else 1
	return math.max(boost, self:_surge())
end

--- The bought part of the dial: nitro or the star, whichever is higher. The acceleration limiter and
--- the post-burn settle both ask "is the car being surged right now", and either claimant counts.
function DriveController._surge(self): number
	return math.max(self._nitroScale or 1, self._starScale or 1)
end

--[[ Write the resolved dial onto the car, if it has moved.

	The guard is what keeps the stock chassis's `AttributeChanged` listener from re-running
	`InitializeDrivingValues` on frames where nothing changed. It has to compare the WRITTEN VALUE
	rather than a flag, because two different claimants can ask for the same number. ]]
function DriveController._applySpeedDial(self)
	local base = self._baseMaxSpeed
	if not base then
		return -- the car declared no MaxSpeed; the stock fallback is not ours to invent
	end
	local car = self._car
	if not (car and car.Parent) then
		return
	end
	local want = base * self:_speedDial()
	if self._dialWritten == want then
		return
	end
	self._dialWritten = want
	car:SetAttribute("MaxSpeed", want)
end

--[[ PUBLIC (NitroController) — light or cut the bottle.

	`scale` is a multiplier over the car's base `MaxSpeed`, or nil/1 for off, and it goes through
	the same dial resolution boost does. `kick` is studs/s of instant forward speed, applied ONCE
	on the frame the bottle lights and ignored on every later call with the same scale.

	The kick is the whole reason nitro answers the press. The chassis is torque limited, so raising
	the dial only moves where the car will eventually settle, and the climb takes longer than a
	bottle lasts (`NitroConfig.Power.Kick` has the argument). One velocity write is what turns a
	promise into a shove.

	Refused while the shim is suspended or inactive, rather than queued: mid-flight the car is
	anchored and StealController is flying it by CFrame, so a velocity write would either be
	discarded or, worse, survive to the handoff as a stale value the car inherits the instant it is
	unanchored. That is the same rule `_lane` obeys and for the same reason. ]]
function DriveController.setNitro(self, scale: number?, kick: number?)
	local want = if type(scale) == "number" and scale > 1 then scale else 1
	if want > 1 and not (self._active and not self._suspended) then
		want = 1
	end
	if self._nitroScale == want then
		return
	end
	local previous = self._nitroScale or 1
	local lighting = want > 1 and previous <= 1
	if previous > 1 and want <= 1 then
		self._nitroRecoveryUntil = os.clock() + DriveConfig.NitroRecovery.Seconds
	end
	self._nitroScale = want
	self:_applySpeedDial()
	if lighting and os.clock() - (self._lastNitroKickAt or -math.huge) >= DriveConfig.NitroRecovery.KickCooldown then
		self._lastNitroKickAt = os.clock()
		self:_nitroKick(kick)
	end
end

--[[ PUBLIC (StarController) — the Star pickup's claim on the speed dial. The same contract as
	`setNitro`: a scale over base `MaxSpeed` (nil/1 for off) and a one-off kick on the rising edge,
	refused while suspended. Its own field rather than a second caller of `setNitro`, because a nitro
	burn ending mid-star would otherwise write the dial back down under a star that is still lit.

	Ending it starts the same settle a nitro burn's end does (`_settleNitro`), so the car eases down
	to cruise instead of coasting on star speed for as long as the chassis takes to bleed it. ]]
function DriveController.setStar(self, scale: number?, kick: number?)
	local want = if type(scale) == "number" and scale > 1 then scale else 1
	if want > 1 and not (self._active and not self._suspended) then
		want = 1
	end
	if self._starScale == want then
		return
	end
	local previous = self._starScale or 1
	self._starScale = want
	if previous > 1 and want <= 1 and (self._nitroScale or 1) <= 1 then
		self._nitroRecoveryUntil = os.clock() + DriveConfig.NitroRecovery.Seconds
	end
	self:_applySpeedDial()
	if want > 1 and previous <= 1 then
		self:_nitroKick(kick)
	end
end

--[[ The one-off shove, along the ROAD rather than along the nose.

	Along the road because that is the axis the whole layer is measured against, and because the
	car genuinely crabs in direct mode (see `_lane`): a nose-relative kick would push a lane change
	sideways as well as forward, which is a shove the player did not ask for.

	`_lane` needs no telling. It swaps the CROSS component of the velocity every frame and infers
	an outside shove from the gap in that one axis, and this adds nothing to it: forward, cross and
	Y are orthonormal. That is the same argument `_lane`'s own header makes about staying out of
	the throttle's business, read from the other side. ]]
function DriveController._nitroKick(self, studs: number?)
	if type(studs) ~= "number" or studs <= 0 then
		return
	end
	local primary = self._car and self._car.PrimaryPart
	if not (primary and primary.Parent) or primary.Anchored then
		return -- an anchored assembly silently discards the write and keeps it for the unanchor
	end
	if not (self._seat and self._seat.Occupant) then
		return
	end
	local info = self._road and self._road:getRoadInfo()
	if not info then
		return
	end
	primary.AssemblyLinearVelocity += info.forward * studs
	-- Adopt the intentional activation kick so the next acceleration-limit step preserves it.
	self._lastForwardSpeed = primary.AssemblyLinearVelocity:Dot(info.forward)
end

--[[ PUBLIC (NitroController) — is the car live and under the player's own control right now?

	Three different "no"s behind one question, because every caller that has to stop spending a
	resource has to stop for all three: the shim is not installed (no race, or a wreck), the car is
	suspended (mid-bail, StealController owns it), or the world is held still (a tutorial beat, the
	race-entry freeze). A tank that kept draining through any of them would empty while the player
	could not possibly be using it. ]]
function DriveController.isDriving(self): boolean
	return self._active == true and not self._suspended and not self._frozen
end

--[[ Stiffen the steering rack's servo so it holds the position it is told to hold.

	This is the wobble fix, and it is the one thing in here that writes to the rig rather than to
	an input. See DriveConfig.SteerRackResponsiveness for the measurements: the shipped servo is
	soft enough to self-oscillate, which waggles the front wheels ±5° at ~6Hz on a dead-straight
	road and rocks the body through the tie rods.

	It goes here rather than onto the car model because the car lives in the place, not in git —
	the same reason this whole file wraps the stock chassis instead of editing it. A car rigged
	without the constraint just doesn't get the fix; that's a redress that steers some other way,
	and warning about it once is more use than failing the install. ]]
function DriveController._stiffenRack(self, car: Model)
	local value = DriveConfig.SteerRackResponsiveness
	if not value then
		return
	end
	local constraints = car:FindFirstChild("Constraints")
	local rack = constraints and constraints:FindFirstChild("SteeringPrismatic")
	if not (rack and rack:IsA("PrismaticConstraint")) then
		self.log:warn("Car has no Constraints.SteeringPrismatic to stiffen; leaving the rack as authored.")
		return
	end
	self._rack = rack
	self._rackResponsiveness = rack.LinearResponsiveness
	rack.LinearResponsiveness = value
end

-- Put the authored responsiveness back. Same contract as _restoreSpeedDial: runs on teardown and
-- again before any re-install, so the car can never be left on a value we chose.
function DriveController._restoreRack(self)
	local rack = self._rack
	if rack and rack.Parent and self._rackResponsiveness then
		rack.LinearResponsiveness = self._rackResponsiveness
	end
	self._rack = nil
	self._rackResponsiveness = nil
end

function DriveController._shapeThrottle(self, throttle: number): number
	if not self._active then
		return throttle
	end

	--[[ The on-screen pedals (DrivingHudController), folded in before anything reads the value, so
		they land on exactly the same three states the keyboard does. Summed rather than substituted
		because both input sources are legitimately live at once on a touch device with a keyboard —
		and because a sum needs no notion of which one has priority. ]]
	throttle = math.clamp(throttle + self._hudThrottle, -1, 1)

	--[[ Stash the player's raw throttle, unconditionally and BEFORE the suspend check below — the
		exact shape, and the exact reason, that `_shapeSteer` stashes `_steerInput` a few lines into
		itself.

		The tutorial reads it through `getThrottleInput` to know whether the accelerate control is
		being held, and the one moment it needs to know is a moment when this shim is suspended: its
		opening beat FREEZES the world and waits for the player to hold accelerate, and a freeze
		suspends the car (`setFrozen`). Stashed after the fold rather than before it so the answer is
		device-agnostic — a phone's pedal and a keyboard's W arrive on different channels and mean
		the same thing.

		Stashing rather than accumulating is safe because the stock Driver calls UpdateThrottle every
		input frame with the player's current value, including 0 when nothing is held. ]]
	self._throttleInput = throttle

	-- Airborne (StealController), or held still by a freeze. The stock Driver's input loop keeps
	-- running and keeps calling this every frame — it has no idea anything happened — so the shim
	-- answers with a dead pedal rather than trying to stop it. See `suspend`.
	if self._suspended then
		return 0
	end

	-- Three states off the one axis the stock Driver already gives us: accelerate held is boost,
	-- brake held is a dab, neither is the default cruise. Both ends are hold-only, so releasing
	-- either lands back on the middle with no extra bookkeeping.
	self:_setBoost(DriveConfig.AllowBoost and throttle > 0.1)

	-- A brake is the only thing allowed to override the auto-throttle, and only as far as
	-- _brakeAllowance permits. Everything else — including no input at all — is full gas, which
	-- is also what makes releasing the brake wind the car straight back up to speed.
	if DriveConfig.AllowBrake and throttle < -0.1 then
		local allowance = self:_brakeAllowance()
		if allowance > 0 then
			return -DriveConfig.BrakeStrength * allowance
		end
	end
	return DriveConfig.AutoThrottle
end

function DriveController._shapeSteer(self, steer: number): number
	if not self._active then
		return steer
	end

	--[[ Hand the lane tuning back to the desktop numbers the moment a real steering device produces
		a value. This is the only channel that can carry one — a key, a stick or the stock touch
		slider — because the on-screen arrows arrive through `setHudSteer` instead, so a non-zero here
		is unambiguously "not the arrows". Read before the fold below for exactly that reason.
		Sampling rather than latching would be wrong on a device with no keyboard, where the slider
		produces raw values too; _touchSteering keeps those on the touch tuning regardless. ]]
	if steer ~= 0 then
		self._hudDriven = false
	end

	--[[ Stash the player's raw steering, unconditionally and before anything else looks at it.

		Direct mode needs it for `_lane` (which runs on Heartbeat, where the physics writes belong),
		and StealController's AIR CONTROL reads it through `getSteerInput` — which is why it's
		stashed even while suspended and even in cone mode. That's the whole reason air control needs
		no keybind of its own: it inherits the steering the player already has, on every input device
		the car already supports, including the touch slider.

		Stashing rather than accumulating is safe because the stock Driver calls UpdateSteering
		every input frame with the player's current value, including 0 when nothing is held —
		that's the same behaviour _shapeThrottle already relies on to keep the auto-throttle
		applied, so a held key stays held and a released one lands on zero by itself. ]]
	--[[ The on-screen arrows (DrivingHudController) fold in BEFORE the stash, which is what makes
		air control inherit them too — the steal gets the touch buttons for free, exactly as it
		already gets the touch slider. `_hudSteer` is +1 = LEFT in road terms and STEER_LEFT converts
		that into this rig's steering sign, so DriveConfig.PositiveSteerIsLeft stays known to this
		file alone. ]]
	steer = math.clamp(steer + self._hudSteer * STEER_LEFT, -1, 1)

	self._steerInput = math.clamp(steer, -1, 1)

	-- Airborne: the wheels are not the player's to turn. Zero rather than a pass-through, so the
	-- rack sits still under a hidden car instead of sawing away at nothing.
	if self._suspended then
		return 0
	end

	-- Direct mode: the rack isn't steering the car, so all this call does is hand it a fraction of
	-- the stashed input, enough that the front wheels turn into the lane change.
	if DriveConfig.DirectSteering then
		return self._steerInput * DriveConfig.RackSteerVisual
	end

	local err = self:_headingError()
	if not err then
		return steer
	end

	local off = math.abs(err)
	local free = math.rad(DriveConfig.FreeYawDeg)
	local limit = math.rad(math.max(DriveConfig.MaxYawDeg, DriveConfig.FreeYawDeg))

	-- Fade out steering that points us further off the road. Steering back toward it is
	-- never touched, at any angle, so the player can always save themselves.
	if off > free and steer * STEER_LEFT * err > 0 then
		local t = math.clamp((off - free) / math.max(limit - free, 1e-3), 0, 1)
		steer *= 1 - t
	end

	-- Past the limit, steer back for them. `-math.sign(err)` is the inward direction in
	-- heading terms; STEER_LEFT converts it into an input the chassis understands.
	if off > limit then
		local ramp = math.max(math.rad(DriveConfig.CounterSteerRampDeg), 1e-3)
		local u = math.clamp((off - limit) / ramp, 0, 1)
		steer += -math.sign(err) * STEER_LEFT * u * DriveConfig.CounterSteerStrength
	end

	return math.clamp(steer, -1, 1)
end

-- === Direct steering (the lane change) ======================================

--[[ Clear direct mode's per-car state, so a race starts dead centre with nothing held and the
	first lane change eases in from a standstill rather than inheriting the last car's.

	`_written` matters most: _lane infers an outside shove from the gap between what it last wrote
	and what it finds, so a value left over from a destroyed car would read as one enormous shove
	on the first frame of the next race. ]]
function DriveController._resetLane(self)
	self._steerInput = 0 -- the player's raw -1..1, stashed by _shapeSteer
	self._lateral = 0 -- eased cross-road speed, studs/s, + = toward the road's left
	--- How fast `_lateral` is itself changing: the spring's velocity term (`DriveConfig.LaneWeight`).
	--- Zeroed with `_lateral`, so a fresh car never inherits the settle of the one before it.
	self._lateralVel = 0
	self._written = nil -- the cross velocity we set last frame; nil = "no reading yet"
	self._targetYaw = 0 -- road-relative yaw requested by the hybrid steering model, radians
	self._visualSteer = 0 -- smoothed road-relative input used only by yaw/body presentation
	self._assistTarget = 0 -- cross-road velocity requested before the spring, studs/s
	self._debugAt = 0
	self._bodyAlong = nil -- previous forward-speed sample for acceleration squat
	-- Grip too: a slick is a thing happening to ONE car on ONE stretch of road, so it must not
	-- survive the boundary that hands the player a different car (a steal) or a different race.
	self._slick = nil -- an active `applySlick` window, or nil for full grip
end

--[[ Is a finger doing the steering right now?

	True on a device with no keyboard, and on ANY device while the on-screen arrows are what steered
	last. The latch is what makes this testable — Studio's device emulator leaves KeyboardEnabled
	true, so without it the mobile tuning could only ever be felt on a real phone — and it's also the
	honest answer for a desktop player who chooses to click the arrows: they have exactly the same
	un-feathered input the tuning exists for.

	Latched rather than sampled so it survives the release: `_hudSteer` drops to 0 the instant the
	finger lifts, and the ease-OUT that follows is half the point of DriveConfig.Touch. It flips back
	the moment a key, stick or the stock touch slider produces a raw value (see _shapeSteer), so a
	player switching devices mid-race switches feel with them. ]]
function DriveController._touchSteering(self): boolean
	return TOUCH_ONLY_DEVICE or self._hudDriven == true
end

--[[ Lane speed and ease rate for the input that's driving, studs/s and per second.

	One multiply each on top of the shared numbers, which is the whole of the mobile handling pass:
	touch gets the same lane change answered faster, never a second steering model. Everything else
	`_lane` does reads these two, including the lean's `share`, so the car still leans fully at ITS
	full lane speed rather than at the desktop one. ]]
--[[ How far through an active slick we are: `amount` counting 1 down to 0 across the window, and
	the `elapsed` seconds that produced it. Nil when the road is dry.

	Expires itself on read -- there is no timer to leak, and a car that stops asking (a wreck, a
	bail, a race that ended) just never sees the rest of the window. Everything a slick does hangs
	off this one reading so the grip and the fishtail can never disagree about how much slick is
	left, which they would the moment either of them got its own clock. ]]
function DriveController._slickPhase(self): (number?, number?)
	local slick = self._slick
	if not slick then
		return nil, nil
	end
	local elapsed = os.clock() - slick.at
	local t = elapsed / slick.duration
	if t >= 1 then
		self._slick = nil
		return nil, nil
	end
	return 1 - t, elapsed
end

--[[ How much of the steering the car is answering right now: 1 on dry road, less on something
	slippery. See `applySlick`.

	Recovers LINEARLY across the window rather than snapping back at the end of it, so the car finds
	its grip again over a beat instead of the steering suddenly working. ]]
function DriveController._grip(self): number
	local amount = self:_slickPhase()
	if not amount then
		return 1
	end
	return 1 - (1 - self._slick.grip) * amount
end

--[[ The fishtail: extra heading, in radians, laid on top of the lean while a slick is live.

	WHY THE BACK STEPPING OUT HAS TO BE A SERVO TARGET AND NOT A KICK. `ObstacleConfig.Oil` carries
	`Yaw = 0`, and the comment on it is blunt about why -- an external angular-velocity write is
	overwritten inside one frame by the lean servo in `_lane`, measured at 0.0 degrees of lasting
	rotation from a sustained 2 rad/s. So a slick cannot make the car wag by pushing on it. What it
	CAN do is move the angle the servo is holding, which is this: the nose genuinely wanders, the
	servo genuinely chases it, and nothing overwrites anything.

	It is the same argument `applySlick` makes about grip, one axis over, and it is the half that
	was missing. Grip alone is INVISIBLE -- the car looks completely normal and simply stops
	answering, which reads as the controls having broken rather than as the road being slippery.
	Testers reported exactly that, as a handling regression rather than as a hazard. The wag is what
	says "you are still on it", and it is the only thing on screen that does.

	Decays with `amount` rather than running flat and stopping, so the tail settles as the grip
	comes back and the two halves of the slick end together on the same frame. Purely a rotation --
	`_lateral` is untouched, so the fishtail never moves the car off the line the player is holding,
	it only makes the car look like it is fighting for it. ]]
function DriveController._slickWobble(self): number
	local wobble = DriveConfig.Slick
	if not wobble or wobble.WobbleDeg <= 0 then
		return 0
	end
	local amount, elapsed = self:_slickPhase()
	if not amount then
		return 0
	end
	-- `scale` is the slick's own share of the full wag (`applySlick`), 1 for everything but a puddle.
	local peak = math.rad(wobble.WobbleDeg) * self._slick.scale
	return peak * amount * math.sin(elapsed * 2 * math.pi * wobble.WobbleHz)
end

--[[ PUBLIC (ObstacleController) -- the car is on something slippery for `duration` seconds, and
	answers `grip` (0..1) of its usual steering while it is.

	THIS IS THE ONLY HONEST WAY TO EXPRESS A SLICK IN THIS GAME, and the reason is `_lane` below:
	in direct mode the cross-road velocity is not a thing the tyres negotiate, it is a value this
	controller WRITES every frame from the player's input. So the road cannot take grip away by
	making the car slide -- measured, a 14 studs/s shove buys about one stud of travel before the
	lane ease pulls it back, and an external yaw is overwritten within a single frame. What it can
	do is make the car answer the wheel slowly, which is the same experience from the driver's seat
	and the one the model can actually represent: measured on the bench, a player fighting a shove
	at grip 0.15 recovers 2.9 studs of the 18.8 they would recover on dry road.

	Scales the lane ACCEL and deliberately not LaneSpeed: the car can still reach the same lane, it
	just takes most of a second to start going there. Dropping the speed instead would read as a car
	that had been slowed down, which is a different (and much duller) idea.

	Latest call wins rather than stacking -- driving the length of a spill is one slick, not five.

	EXCEPT THAT A GENTLER ONE CANNOT CUT A HARSHER ONE SHORT. The rain's puddles
	(`ObstacleConfig.Kinds.Puddle`) are the first slick that can land in the middle of a much worse one,
	and "latest wins" would have let a puddle a second after an oil slick hand the player most of their
	steering back. So a new slick only takes over if it grips no better than the road already does at
	this moment. Oil after oil is unchanged by this: a fresh window is always at least as bad as the
	tail of an old one with the same numbers.

	`wobble` scales `DriveConfig.Slick`'s fishtail for this slick alone, 1 when left out, so every
	slick before the puddle wags exactly as it did. ]]
function DriveController.applySlick(self, duration: number, grip: number, wobble: number?)
	if type(duration) ~= "number" or duration ~= duration or duration <= 0 then
		return
	end
	grip = math.clamp(grip or 1, 0, 1)
	if self:_grip() < grip then
		return
	end
	self._slick = {
		at = os.clock(),
		duration = duration,
		grip = grip,
		scale = math.clamp(if type(wobble) == "number" then wobble else 1, 0, 2),
	}
end

function DriveController._laneTuning(self): (number, number)
	local speed, accel = DriveConfig.LaneSpeed, DriveConfig.LaneAccel
	local car = self._car
	if car then
		speed *= car:GetAttribute("LaneSpeedScale") or 1
		accel *= car:GetAttribute("LaneAccelScale") or 1
	end
	local touch = DriveConfig.Touch
	if touch and self:_touchSteering() then
		speed *= touch.LaneSpeedScale
		accel *= touch.LaneAccelScale
	end
	-- Read here rather than in `_lane` because this is the one place both the ease and the lean's
	-- share agree about which tuning they are on, and a slick has to move them together.
	return speed, accel * self:_grip()
end

--[[ Degrees of lean the car gets at full input for the speed it's actually doing, `along` being
	speed down the ROAD (not the nose — the crab means those differ by the lean itself, and the
	road is what everything else in here is measured against).

	LeanDeg, plus a fade up to LeanTopDeg across the top of the speed range. The caller still
	scales the result across a lower speed band, so this is the second, narrower ramp on top:
	the first says "a moving car leans, a stationary one doesn't", this one says "a car at full
	chat turns in harder than one at cruise". Purely angle — sideways speed doesn't change. ]]
function DriveController._speedFraction(self, along: number): number
	local dial = self:getTopSpeed()
	if not dial then
		return 0
	end
	local top = dial * WindConfig.StudsPerMaxSpeed
	return if top > 0 then math.max(0, along) / top else 0
end

local function fractionBand(value: number, first: number, last: number): number
	local span = last - first
	return if span > 0 then math.clamp((value - first) / span, 0, 1) else (if value >= last then 1 else 0)
end

function DriveController._leanDeg(self, along: number): number
	local deg, top = DriveConfig.LeanDeg, DriveConfig.LeanTopDeg
	if top == deg then
		return deg
	end
	local t = fractionBand(
		self:_speedFraction(along),
		DriveConfig.LeanTopStartFraction,
		DriveConfig.LeanTopFullFraction
	)
	return deg + (top - deg) * t
end

--[[ Hybrid direct mode: input asks for a bounded turn-in first, while a reduced cross-road
	velocity assist supports that trajectory. Runs on Heartbeat and replaces _recover entirely.

	Two writes, on the assembly we own (RaceService hands the driver network ownership):

	  1. THE CROSS-ROAD COMPONENT OF LINEAR VELOCITY, set to an eased-in target. Only that
	     component — along-road speed stays the throttle's business and vertical stays gravity's
	     and the suspension's, which is what keeps this compatible with boost, braking, jumps and
	     ObstacleController's speed cuts. Because (forward, cross, Y) is orthonormal, adding
	     `cross * (target - velocity:Dot(cross))` swaps that one axis and provably disturbs
	     nothing else.

	  2. YAW RATE, servoed toward a small lean angle. A servo rather than the cone's staged blend
	     because it pulls toward the target from ANY heading — so it subsumes the countersteer and
	     both RecoverYaw* stages, and a collision spin unwinds on its own. DriveConfig.MaxYawRate
	     stays the ceiling on that, which is what keeps a hit reading as a hit rather than being
	     erased the instant it lands.

	The assist is intentionally incomplete. It keeps keyboard/touch precision and collision recovery,
	while the speed-shaped 9–12° yaw makes visible heading agree more closely with travel. ]]
function DriveController._lane(self, dt: number)
	local primary = self._car and self._car.PrimaryPart
	if not (primary and primary.Parent) then
		return
	end
	-- Only ever drive a car someone is actually in, same as _recover.
	if not (self._seat and self._seat.Occupant) then
		return
	end
	local info = self._road and self._road:getRoadInfo()
	if not info then
		return -- no road frame yet; leave the car to the stock chassis for a frame
	end
	local forward, cross = info.forward, info.cross
	if cross.Magnitude < 0.5 then
		return -- vertical ForwardAxis; RoadController would have broken long before this
	end

	local velocity = primary.AssemblyLinearVelocity
	local along = velocity:Dot(forward)

	-- Scaled for touch, which cannot hold an input the way a key can — see _laneTuning. Read once a
	-- frame so the target, the ease below and the lean's share can't disagree about which they're on.
	local laneSpeed, laneAccel = self:_laneTuning()

	-- === Where the player is asking to be ===
	-- `cross` is the road's LEFT (Y x forward), and STEER_LEFT maps the rig's steering sign onto
	-- that, so a left input and a positive offset agree on which way is left.
	local offset = primary.Position:Dot(cross) - info.driveCenter
	local input = self._steerInput * STEER_LEFT
	local hybrid = DriveConfig.HybridSteering
	local visualRate = hybrid.VisualInputResponse
	if math.abs(input) < 1e-3 then
		visualRate = hybrid.VisualReleaseResponse
	elseif input * self._visualSteer < 0 then
		visualRate = hybrid.VisualReversalResponse
	end
	self._visualSteer += (input - self._visualSteer) * (1 - math.exp(-dt * visualRate))
	local trajectoryWant = input * laneSpeed
	local want = trajectoryWant * hybrid.LateralAssist
	-- An opposite request first has to cancel the existing cross-road motion. This is deliberately
	-- a scale, not a lockout: keyboard and touch remain responsive, while the spring makes the
	-- left-to-right handoff visible instead of reversing the write in one frame.
	if want * self._lateral < -hybrid.ReversalThreshold then
		want *= hybrid.ReversalLateralScale
	end

	--[[ Fade outward input out before the edge. Under the cone this wasn't needed — the tyres
		simply wouldn't take the car anywhere it couldn't go — but a velocity write will happily
		drive into a wall and grind along it. Steering back toward the centre is never restricted
		at any position, so a car that's been shoved out by a hit can always recover. ]]
	local hull = self._edgeHitBox
	if not (hull and hull:IsDescendantOf(self._car)) then
		hull = self._car:FindFirstChild("HitBox",true)
		self._edgeHitBox = hull
	end
	local half = if hull and hull:IsA("BasePart")
		then RoadEdgeGuard.limit(hull.CFrame,hull.Size,cross,info.driveWidth,DriveConfig.LaneHalfWidth)
		else DriveConfig.LaneHalfWidth
	if half > 0 and want * offset > 0 then
		local fade = math.max(DriveConfig.LaneEdgeFade, 1e-3)
		want *= math.clamp((half - math.abs(offset)) / fade, 0, 1)
	end
	self._assistTarget = want

	local actual = velocity:Dot(cross)

	--[[ Adopt sideways movement that isn't ours before we overwrite it. Setting the cross velocity
		outright would otherwise ERASE every sideways shove in the game on the following frame —
		ObstacleController's SideKick, a traffic clip, a wall — and hits would land with no weight
		at all. Absorbed into `_lateral`, a shove instead lands in full and then eases back under
		the player's control at LaneAccel, which is what a hit knocking you off your line should do.
		It also leans the car, because the lean reads off the same value.

		The floor is what separates a shove from ordinary physics. Because we hard-set this axis
		every frame, the chassis only ever gets ONE frame to push back — tyre scrub against the
		crab, the RackSteerVisual steer, drag — which is a few tenths of a stud/s at 60Hz. The
		smallest kind in ObstacleConfig (Cone) shoves 3 in a single frame, so anything past 1.5 is
		unambiguously external. ]]
	local external = actual - (self._written or actual)
	if math.abs(external) > EXTERNAL_LATERAL_FLOOR then
		self._lateral += external
	end

	--[[ Toward the commanded cross speed, with or without mass — see `DriveConfig.LaneWeight`.

		The spring is integrated SEMI-IMPLICITLY (velocity first, then position off the NEW velocity),
		which is stable where the plain explicit form of the same equation is marginal, and the step
		is clamped on top of that so a dropped frame under-moves instead of overshooting. ]]
	local weight = DriveConfig.LaneWeight
	if weight.Enabled then
		local omega = laneAccel
		local step = math.min(dt, weight.MaxStep)
		local accel = (want - self._lateral) * omega * omega
			- self._lateralVel * (2 * weight.Damping * omega)
		self._lateralVel += accel * step
		self._lateral += self._lateralVel * step
	else
		self._lateral += (want - self._lateral) * (1 - math.exp(-dt * laneAccel))
		--- Kept in step even while unused, so flipping `Enabled` mid-session cannot resume the
		--- spring with a velocity left over from a lane change that finished minutes ago.
		self._lateralVel = 0
	end

	primary.AssemblyLinearVelocity = velocity + cross * (self._lateral - actual)
	self._written = self._lateral

	-- === The turn-in ===
	-- Start with the trajectory's honest angle, then clamp it into a deliberately narrow arcade
	-- envelope. The forward-speed floor prevents atan2 exploding while the car is pulling away;
	-- the cap grows modestly into boost so high-speed cuts stay readable without becoming drifts.
	local speedFraction = self:_speedFraction(along)
	local yawT = fractionBand(
		speedFraction,
		hybrid.YawSpeedStartFraction,
		hybrid.YawSpeedFullFraction
	)
	local yawCapDeg = hybrid.NormalYawDeg + (hybrid.TopYawDeg - hybrid.NormalYawDeg) * yawT
	yawCapDeg = math.min(yawCapDeg, hybrid.AbsoluteYawDeg)
	local visualWant = self._visualSteer * hybrid.VisualTrajectorySpeed * hybrid.LateralAssist
	-- Preserve edge and reversal shaping in the visual trajectory while release eases back to zero.
	if math.abs(input) > 1e-3 then
		local unshapedWant = math.abs(input * laneSpeed * hybrid.LateralAssist)
		visualWant *= math.clamp(math.abs(want) / math.max(unshapedWant, 1e-3), 0, 1)
	end
	local honestYaw = math.atan2(visualWant, math.max(math.abs(along), hybrid.MinForwardSpeed))
	local target = math.clamp(honestYaw, -math.rad(yawCapDeg), math.rad(yawCapDeg))
	local alignedShare = 0
	if input * self._lateral > 0 and math.abs(want) > 1e-3 then
		alignedShare = math.clamp(math.abs(self._lateral / want), 0, 1)
	end
	if math.abs(want) > 1e-3 then
		target += self._visualSteer * math.rad(hybrid.TurnInYawBoostDeg) * (1 - alignedShare)
	end
	target = math.clamp(target, -math.rad(hybrid.AbsoluteYawDeg), math.rad(hybrid.AbsoluteYawDeg))
	self._targetYaw = target

	--[[ ...plus the fishtail, if we are on something slippery. ADDED rather than blended, and it is
		deliberately independent of `share`: the whole job of the wag is to be visible when the
		player is NOT steering, because that is the moment they need telling why the car has stopped
		answering. Steering while it runs simply leans against it. See `_slickWobble`. ]]
	target += self:_slickWobble()

	local av = primary.AssemblyAngularVelocity
	local yaw = av.Y
	local err = self:_headingError()
	if err then
		local gain = hybrid.YawResponse
		if math.abs(input) < 1e-3 then
			gain = hybrid.YawReleaseResponse
		elseif target * err < 0 then
			gain = hybrid.YawReversalResponse
		end
		yaw = (target - err) * gain
	end
	local cap = DriveConfig.MaxYawRate
	if cap > 0 then
		yaw = math.clamp(yaw, -cap, cap)
	end
	if yaw ~= av.Y then
		primary.AssemblyAngularVelocity = Vector3.new(av.X, yaw, av.Z)
	end

	local debug = DriveConfig.Debug
	local now = os.clock()
	if debug.Enabled and now >= self._debugAt then
		self._debugAt = now + debug.SampleInterval
		local car = self._car
		car:SetAttribute("DriveDebugForwardSpeed", along)
		car:SetAttribute("DriveDebugCrossSpeed", actual)
		car:SetAttribute("DriveDebugSteerInput", input)
		car:SetAttribute("DriveDebugTargetYawDeg", math.deg(target))
		car:SetAttribute("DriveDebugYawErrorDeg", math.deg(target - (err or 0)))
		car:SetAttribute("DriveDebugLateralAssist", want)
		car:SetAttribute("DriveDebugLateralVelocity", self._lateral)
		car:SetAttribute("DriveDebugBraking", (self._throttleInput or 0) < -0.1)
	end
end

--[[ Backstop for angles the steering rack can't unwind quickly — see the header. Three stages on
	one yaw value, cheapest first:

	  1. CAP the rotation rate, at any heading (DriveConfig.MaxYawRate). Steering never reaches it,
	     so this is dormant in normal play; ramming a solid traffic car is what it's for. Capping
	     the rate rather than the angle is what keeps a hit feeling like a hit — you still get spun,
	     you just can't get spun arbitrarily fast.
	  2. Past RecoverYawDeg, BLEND toward a turn-in rate, so the recovery reads as the car fighting
	     for grip rather than a snap.
	  3. Past HardYawDeg, SET it. The blend is a negotiation and a sustained contact wins that
	     negotiation, so at the far end we stop negotiating.

	All three write angular velocity and never a CFrame. We own this assembly (RaceService hands
	the driver network ownership) so the write is authoritative, whereas a CFrame write is what
	synthesises the runaway velocity RoadController's rebase has to work around.

	One known cosmetic edge: `_headingError` comes off atan2, so its sign flips as the car passes
	through exactly 180°, and the unwind can pick the other way round for a frame. Both directions
	unwind, so it self-corrects — and stage 3 means a car should never get there at all. ]]
function DriveController._recover(self, dt: number)
	local primary = self._car and self._car.PrimaryPart
	if not (primary and primary.Parent) then
		return
	end
	-- Only ever touch a car someone is actually driving. Cheap insurance against holding a
	-- heading on an abandoned car if a race ever unwinds without firing RaceEnd.
	if not (self._seat and self._seat.Occupant) then
		return
	end

	local av = primary.AssemblyAngularVelocity
	local yaw = av.Y

	local cap = DriveConfig.MaxYawRate
	if cap > 0 and math.abs(yaw) > cap then
		yaw = math.sign(yaw) * cap
	end

	-- Yaw rate about world +Y shares its sign with `err` (both are positive toward the
	-- road's left), so unwinding a positive error means driving the rate negative.
	local err = self:_headingError()
	if err then
		local off = math.abs(err)
		local target = -math.sign(err) * DriveConfig.RecoverRate
		if off > math.rad(DriveConfig.HardYawDeg) then
			yaw = target
		elseif off > math.rad(DriveConfig.RecoverYawDeg) then
			yaw += (target - yaw) * (1 - math.exp(-dt * DriveConfig.RecoverGain))
		end
	end

	-- Only write when we actually changed something, so an ordinary frame doesn't poke the
	-- assembly's velocity at all.
	if yaw ~= av.Y then
		primary.AssemblyAngularVelocity = Vector3.new(av.X, yaw, av.Z)
	end
end

-- === Upright (the flip backstop) =============================================

--[[ Radians the car's roof is away from straight up. 0 is level, pi/2 is on its side, pi is fully
	inverted — and being a single angle off vertical it says nothing about WHICH way, which is
	exactly right: roll and pitch are the same problem here and the axis below finds itself.

	Read off the PrimaryPart rather than the seat, because this is about the assembly the writes
	below land on. ]]
function DriveController._tilt(self, primary: BasePart): number
	return math.acos(math.clamp(primary.CFrame.UpVector.Y, -1, 1))
end

function DriveController._bodyMotion(self, primary: BasePart, dt: number, tilt: number): boolean
	local cfg = DriveConfig.BodyMotion
	if not cfg.Enabled or tilt > math.rad(cfg.MaxTiltDeg) then
		self._bodyAlong = nil
		return false
	end
	local info = self._road and self._road:getRoadInfo()
	if not info then
		return false
	end
	local along = primary.AssemblyLinearVelocity:Dot(info.forward)
	local acceleration = if self._bodyAlong and dt > 1e-4 then (along - self._bodyAlong) / dt else 0
	self._bodyAlong = along
	local assistMax = math.max(DriveConfig.LaneSpeed * DriveConfig.HybridSteering.LateralAssist, 1e-3)
	local lateralShare = math.clamp((self._lateral or 0) / assistMax, -1, 1)
	local inputShare = math.clamp(self._visualSteer or 0, -1, 1)
	local loadShare = lateralShare * (1 - cfg.InputRollShare) + inputShare * cfg.InputRollShare
	local roll = -math.rad(cfg.RollDeg) * math.clamp(loadShare, -1, 1)
	local brake = (self._throttleInput or 0) < -0.1
	local accelShare = math.clamp(acceleration / math.max(cfg.AccelForFull, 1e-3), 0, 1)
	local pitch = if brake then -math.rad(cfg.BrakeDiveDeg) else math.rad(cfg.AccelSquatDeg) * accelShare
	local desiredUp = (Vector3.yAxis + info.cross * math.tan(roll) + info.forward * math.tan(pitch)).Unit
	local axis = primary.CFrame.UpVector:Cross(desiredUp)
	local want = axis * cfg.Response
	if want.Magnitude > cfg.MaxRate then
		want = want.Unit * cfg.MaxRate
	end
	local av = primary.AssemblyAngularVelocity
	local horizontal = Vector3.new(av.X, 0, av.Z)
	local blend = 1 - math.exp(-dt * cfg.Response)
	local nextHorizontal = horizontal + (want - horizontal) * blend
	primary.AssemblyAngularVelocity = Vector3.new(nextHorizontal.X, av.Y, nextHorizontal.Z)
	return true
end

--[[ Keep the car on its wheels. Runs every frame under both steering models — a flip is not a
	steering problem — and touches only the two rotation axes neither model has any opinion about.

	See DriveConfig.Upright for the design and the numbers. In short: past `FreeTiltDeg` an
	angular-velocity servo rotates the car back toward level, ramping in over `EngageDeg`; past
	`FlippedDeg` it also holds a small upward velocity so the roll happens clear of the deck
	instead of grinding through it; and if it is STILL flipped `ResetAfter` seconds later the
	servo has demonstrably lost and `_resetUpright` places the car back on the road.

	THE AXIS IS `up x Y`. That is the rotation that carries the roof back toward vertical by the
	shortest path, and being a cross product with Y it is horizontal by construction — so writing
	it into X and Z and leaving Y alone cannot disturb the yaw `_lane` and `_recover` own. The two
	passes write disjoint components of the same vector and neither has to know about the other.

	Its magnitude is sin(tilt), which vanishes at BOTH ends: level (where we don't act anyway) and
	dead inverted (where every horizontal axis is equally correct and the shortest path is a
	coin flip). The second one matters — a car resting flat on its roof sits right on it — so
	that sliver falls back to rolling the car about its own long axis, which is how a car rights
	itself anyway. Everywhere in between, `.Unit` is well conditioned. ]]
function DriveController._upright(self, dt: number)
	local cfg = DriveConfig.Upright
	if not cfg.Enabled then
		return
	end
	local primary = self._car and self._car.PrimaryPart
	if not (primary and primary.Parent) then
		return
	end
	-- Only ever right a car someone is actually in, same guard as _lane and _recover. A wreck
	-- coasting to a stop on its roof is a beat, not a fault.
	if not (self._seat and self._seat.Occupant) then
		return
	end

	local tilt = self:_tilt(primary)
	if self:_bodyMotion(primary, dt, tilt) then
		self._flippedFor = 0
		return
	end
	local free = math.rad(cfg.FreeTiltDeg)
	if tilt <= free then
		self._flippedFor = 0
		return
	end

	if tilt >= math.rad(cfg.FlippedDeg) then
		self._flippedFor += dt
		if self._flippedFor >= cfg.ResetAfter then
			self:_resetUpright()
			return
		end
		-- Hold a floor under the vertical speed rather than adding to it, so this can't compound
		-- into a launch across the frames the roll takes.
		if cfg.Lift > 0 then
			local v = primary.AssemblyLinearVelocity
			if v.Y < cfg.Lift then
				primary.AssemblyLinearVelocity = Vector3.new(v.X, cfg.Lift, v.Z)
			end
		end
	else
		self._flippedFor = 0
	end

	local up = primary.CFrame.UpVector
	local axis = up:Cross(Vector3.yAxis)
	if axis.Magnitude < 1e-3 then
		-- Dead inverted: no shortest path to pick. Roll it about its own long axis.
		local right = primary.CFrame.RightVector
		axis = Vector3.new(right.X, 0, right.Z)
		if axis.Magnitude < 1e-3 then
			return -- nose-down vertical AND inverted; nothing sane to rotate about
		end
	end

	local rate = math.min((tilt - free) * cfg.LevelGain, cfg.MaxLevelRate)
	local want = axis.Unit * rate
	local engage = math.clamp((tilt - free) / math.max(math.rad(cfg.EngageDeg), 1e-3), 0, 1)

	local av = primary.AssemblyAngularVelocity
	local horizontal = Vector3.new(av.X, 0, av.Z)
	local blended = horizontal + (want - horizontal) * engage
	primary.AssemblyAngularVelocity = Vector3.new(blended.X, av.Y, blended.Z)
end

--[[ The guarantee behind the servo: put the car back on the road, upright and square to it.

	Reached only when the servo has been given `ResetAfter` seconds and the car is still past
	`FlippedDeg`, which in practice means it is wedged — against the guardrail, or on a roof the
	Lift can't get out from under.

	ANCHORED FOR THE WRITE, and that is the one line here that isn't negotiable. Setting a CFrame
	on a live assembly makes the engine synthesise a reconciliation velocity (delta-position over
	delta-time) and hand it to the solver, which is the runaway RoadController's rebase exists to
	work around and the reason every other write in this file is a velocity. Anchored there is
	nothing to synthesise, so this is the identical recipe StealController's handoff uses, down to
	the order: freeze, place, unfreeze, THEN seed the velocity (an anchored assembly does not hold
	one — write it first and the car comes back at a dead stop).

	POSITION IS KEPT, HEADING IS NOT. Where the player ended up is theirs; which way they are
	pointed after a roll is meaningless, and the whole drive layer exists to make sure the answer
	is "down the road". The cross-road offset is clamped into `LaneHalfWidth` on the way, because
	the most common way to get properly stuck is to slide into the guardrail — putting the car back
	exactly where it wedged would just wedge it again. ]]
function DriveController._resetUpright(self, reason: string?)
	self._flippedFor = 0
	self._pinnedFor = 0

	local car = self._car
	local primary = car and car.PrimaryPart
	local info = self._road and self._road:getRoadInfo()
	if not (car and car.Parent and primary and info) then
		return
	end
	local cfg = DriveConfig.Upright

	-- Sampled before the freeze: an anchored assembly reports no velocity at all.
	local speed = math.max(primary.AssemblyLinearVelocity:Dot(info.forward), 0) * cfg.KeepSpeed

	local anchors = {}
	for _, part in car:GetDescendants() do
		if part:IsA("BasePart") then
			anchors[part] = part.Anchored
			part.Anchored = true
		end
	end

	-- Where we are on the road, minus the roll, minus the wall.
	local pos = car:GetPivot().Position
	local offset = pos:Dot(info.cross) - info.driveCenter
	if DriveConfig.LaneHalfWidth > 0 then
		offset = math.clamp(offset, -DriveConfig.LaneHalfWidth, DriveConfig.LaneHalfWidth)
	end
	local deckPoint = info.forward * pos:Dot(info.forward)
		+ info.cross * (info.driveCenter + offset)
		+ Vector3.yAxis * info.deckY

	-- Place at the deck, then lift by the car's own bodywork, so a redress with a different ride
	-- height lands right without anything being re-measured. Same recipe as RaceService._spawnCar
	-- and StealController._finish.
	local surface = CFrame.lookAt(deckPoint, deckPoint + info.forward)
	car:PivotTo(surface)
	local bbCF, bbSize = car:GetBoundingBox()
	local belowDeck = info.deckY - (bbCF.Position.Y - bbSize.Y * 0.5)
	car:PivotTo(surface + Vector3.new(0, belowDeck + cfg.Clearance, 0))

	--[[ THE RIDER IS ALREADY HANDLED, and the step that used to sit here is what turned this
		recovery into the fault it exists to recover from.

		The `PivotTo` above carries the seated character on its own — the stock `SeatWeld` joins
		their `HumanoidRootPart` to the `VehicleSeat`, so the whole rider moves with the model, on
		the same frame, exactly (measured: car 4.00, rider 4.00, offset unchanged by 0.00).

		What was here instead wrote `delta * part.CFrame` on every one of the character's parts. A
		CHARACTER IS ONE RIGID ASSEMBLY, so each of those writes moved the WHOLE body — 19 BaseParts,
		so `delta` landed NINETEEN TIMES. The unanchor below then handed the solver a rider hundreds
		of studs from the seat they are welded into; it resolved that by throwing the car, the car
		came to rest past `FlippedDeg` again, and `ResetAfter` later this ran again. Observed: 77
		consecutive "Righted a flipped car" at ~1.3s intervals, from one steal to the end of the run.
		That loop is what a player reports as the car flinging around, and the steal only started it
		— this is what would not let go. `StealController._finish` had the same step, from the same
		reasoning, and has had it removed too. ]]

	for part, anchored in anchors do
		if part.Parent then
			part.Anchored = anchored
		end
	end
	primary.AssemblyLinearVelocity = info.forward * speed
	primary.AssemblyAngularVelocity = Vector3.zero

	--[[ Load-bearing, for the same reason `resume` calls it after a steal: `_lane` infers an
		outside shove from the gap between the cross velocity it last WROTE and the one it finds,
		and we have just moved the car and zeroed that axis. Left stale, the next frame reads the
		difference as one enormous sideways hit and flings the car off the line we just put it on. ]]
	self:_resetLane()
	--[[ NAMED, because there are now two ways in and they mean opposite things about the car. A
		flip is a collision that went badly; "pinned" is a car that was never able to leave the spot
		it started in, which is a bug report waiting to happen (`DriveConfig.Pinned`) and wants to be
		greppable in a log as its own thing. ]]
	self.log:info(if reason == "pinned" then "Freed a pinned car." else "Righted a flipped car.")
end

-- === Suspension (the steal) ==================================================

--[[ PUBLIC (StealController) — hand the car back to nobody for the duration of a flight.

	The player is still seated, the stock `Driver` LocalScript is still deployed and still running
	its input loop, and the car is still the one assembly we own — all of that is the point of the
	steal's spine (plan §2: no unseat, no re-deploy, no handshake). So suspending is not tearing
	anything down; it's the two input wrappers answering "nothing is being pressed" and `_step`
	keeping its hands off an assembly StealController has anchored and is flying by CFrame.

	That last part is not optional. `_lane` writes `AssemblyLinearVelocity` and `AssemblyAngularVelocity`
	every frame, and both are silently discarded on an anchored assembly — so the car would fly
	correctly and then, the instant it was unanchored at the handoff, inherit whatever the last
	write happened to be. Nothing here writes while suspended.

	Boost is dropped explicitly rather than left to the throttle wrapper, because `_setBoost` only
	acts on a CHANGE: a player who bailed with accelerate held would otherwise spend the whole
	flight on the raised speed dial and land already boosting with the key long since released.
	Nitro is dropped for the same reason and one more: NitroController stops the burn on its own
	when the drive goes away, but the order those two land in is not ours to depend on, and the
	dial has to be down before the handoff either way. ]]
function DriveController.suspend(self)
	if self._suspended then
		return
	end
	self._suspended = true
	self._lastForwardSpeed = nil
	self._nitroScale = 1
	self._starScale = 1
	self:_setBoost(false)
	-- Unconditional, because `_setBoost` above returns early when boost was already off and the
	-- nitro line would then never reach the attribute.
	self:_applySpeedDial()
end

--[[ PUBLIC (StealController) — the flight is over, drive again.

	`_resetLane` is the load-bearing line. `_lane` infers an outside shove from the gap between the
	cross velocity it last WROTE and the one it finds (see EXTERNAL_LATERAL_FLOOR), and a steal
	teleports the car to a different lane and re-seeds its velocity from the car it stole — so the
	stale `_written` from before the bail would read as one enormous external shove on the first
	frame back, and the car would be flung sideways by its own bookkeeping. Same class of bug the
	reset already exists to prevent between races; a steal is just a race boundary that doesn't
	destroy the car. ]]
function DriveController.resume(self)
	if not self._suspended then
		return
	end
	self._suspended = false
	self._lastForwardSpeed = nil
	-- The flip timer is only ever advanced by `_upright`, which doesn't run while suspended — so a
	-- player who bailed out of a car that was already going over would come back holding a stale
	-- count and trip the reset on their first tilted frame. Cleared with the lane state, for the
	-- same reason: a steal is a boundary this car crosses without being destroyed.
	self._flippedFor = 0
	-- ...and the pinned timer with it, and this one matters MORE across a steal: the car you land in
	-- is a different car in a different place, and a flight spent holding accelerate would otherwise
	-- hand it a timer already most of the way to a reset on its first frame.
	self._pinnedFor = 0
	self:_resetLane()
end

--[[ PUBLIC (RaceFreezeController) — hold the car still, or let it go again.

	THE SOLVER'S HALF OF A PAUSE. `Modules/TimeScale` stops every scripted per-frame system in the
	game with one number, and the player's car is the one thing on the road it cannot touch: the
	car is a physics assembly, physics runs at 240Hz on real time, and there is no lever on it. So a
	held world with an unheld car is a car that coasts, steers and rear-ends a frozen queue of
	traffic while the tutorial is asking somebody to read a sentence.

	Anchoring is the lever there is, and it is the same one `StealController._onBail` reaches for
	when it takes the car over to fly it, for the same underlying reason: an anchored assembly is
	one nothing is being simulated on.

	SUSPEND COMES WITH IT, and not as a nicety. `_lane` writes `AssemblyLinearVelocity` and
	`AssemblyAngularVelocity` every frame; both are silently DISCARDED on an anchored assembly and
	then inherited whole the instant it is unanchored. A car frozen without being suspended would
	sit still for the length of the hold and then be launched by whatever the last discarded write
	happened to be. That is the documented flinging bug, arrived at from a different direction.

	WHAT IT REMEMBERS AND PUTS BACK, per part rather than per assembly:

	  • `Anchored`, so a freeze that lands DURING a flight — the tutorial pauses a steal mid-air,
	    which is one of its beats — finds every part already anchored, records that, and releases
	    to exactly the state the flight still expects. A freeze must never be the thing that hands
	    a car back to the solver.
	  • the assembly velocities, restored on release. Anchoring does not clear them, so this is
	    belt-and-braces for one case that does come up: the assembly can be re-rooted while it is
	    held (a steal's handoff re-parents), and a re-rooted assembly reports whatever it joined.

	Idempotent, and safe to call when there is no car — a hold can outlive a race, and the release
	on the far side of that has nothing to put back. ]]
--[[ PUBLIC (StealController) — what `Anchored` this part had before the freeze took it, or nil if
	this controller is not holding the car.

	TWO SYSTEMS ANCHOR THE SAME CAR AND EACH REMEMBERS WHAT IT FOUND, which works perfectly for
	whichever of them goes first and is poison for the second. The tutorial's BAIL beat is exactly
	that collision: the pause anchors all 83 parts and remembers `false`, the player jumps, and
	`StealController._onBail` anchors the same 83 parts and remembers — correctly, and uselessly —
	`true`. At the handoff the flight restores what it remembered, and the car the player has just
	stolen is nailed to the road with the objective card telling them to drive to the truck.

	So the second one to arrive asks the first what was really there. This is that question, and
	`setFrozen` asks the mirror of it (see the flight guard in it). One of the two is always nil,
	because only one of them can be holding the car first. ]]
function DriveController.frozenAnchor(self, part: BasePart): boolean?
	local anchors = self._freezeAnchors
	return if anchors then anchors[part] else nil
end

function DriveController.setFrozen(self, frozen: boolean)
	frozen = frozen == true
	if frozen == (self._frozen == true) then
		return
	end
	self._frozen = frozen

	local car = self._car
	if frozen then
		self._freezeAnchors = {}
		if car and car.Parent then
			local primary = car.PrimaryPart
			if primary then
				self._freezeVel = primary.AssemblyLinearVelocity
				self._freezeSpin = primary.AssemblyAngularVelocity
			end
			--[[ ANCHOR, AND DO NOT TOUCH THE VELOCITY. Anchoring stops the solver integrating it and
				leaves the number alone, which is exactly right: a held car resumes at the speed it
				was doing, and every consumer that asks what this car is doing gets the truth.

				=== THE VERSION THAT ZEROED IT, AND WHY IT WAS WRONG ================================

				A frozen car goes on REPORTING its speed, so the first playtest of the pause showed a
				still road under a speedometer reading 32 MPH. The obvious fix — zero the velocity
				here — was tried twice and is wrong both times:

				    ONE WRITE TO THE PRIMARY DOES ALMOST NOTHING. Anchoring SPLITS THE ASSEMBLY, so
				    after the loop the car is thirty assemblies and that write clears one of them.
				    It measures clean while being wrong, because the part you measure is the part
				    you zeroed. The speedometer reads the VEHICLE SEAT, which kept its 61.

				    PER PART CLEARS THE READING AND BREAKS THE BAIL. `StealController` seeds a
				    flight's forward carry from `primary.AssemblyLinearVelocity` AT THE MOMENT OF THE
				    JUMP (`Launch.ForwardKeep`), and the tutorial's bail beat jumps from inside a
				    freeze. Zeroed, the rider leaves with no forward speed at all, the car they were
				    aiming at drives away from under them, and the steal beat whiffs every time.

				A stale readout is a DISPLAY problem and belongs in the display: `DrivingHudController`
				reads 0 off an anchored seat. Nothing else has to lie for the gauge to be right. ]]
			--[[ ...UNLESS A FLIGHT ALREADY OWNS THE ANCHORS, in which case there is nothing here to do
				and recording anything is the mistake. `StealController._onBail` has anchored every
				part and holds the real pre-flight values; every `Anchored` this loop could read is a
				`true` it wrote. Recorded, they would be restored on the way out — re-anchoring a car
				the flight had just correctly handed back — which is the same collision `frozenAnchor`
				above exists for, in the other order.

				The release path already declines to restore while a flight is up; this is what makes
				it safe for the flight to END first, which is precisely what a whiff does. ]]
			local steal = Shard.get("StealController")
			local flying = steal and (select(1, steal:getFlight())) ~= "idle"
			if not flying then
				for _, part in car:GetDescendants() do
					if part:IsA("BasePart") then
						self._freezeAnchors[part] = part.Anchored
						part.Anchored = true
					end
				end
			end
		end

		--[[ After the anchor, never before: suspending first would leave one frame in which the car is
			live and the shim has stopped correcting it.

			WHOSE SUSPENSION IT IS, is recorded — because `suspend`/`resume` are a latch rather than a
			count and StealController is the other caller. A freeze that lands mid-flight finds the
			car already suspended, and a release that called `resume` unconditionally would hand
			`_lane` back its per-frame writes while the flight is still flying the car by CFrame. So
			the freeze only ever undoes a suspension it put on itself. ]]
		self._freezeSuspended = not self._suspended
		self:suspend()
		return
	end

	--[[ ...UNLESS A FLIGHT HAS TAKEN THE CAR OVER SINCE THE HOLD WENT ON, in which case every
		value this remembers is stale and writing any of it back is actively destructive.

		That is not a corner case, it is the tutorial's BAIL beat exactly: the world is held still,
		the card asks for the jump, the player jumps, and the hold is released so the arc can play.
		In between, `StealController._onBail` has anchored the car for its own reasons and recorded
		its own `Anchored` values — finding the parts already anchored, because we anchored them.
		Restoring ours on the way out would unanchor a car that is mid-flight and being positioned
		by CFrame, which is the documented reconciliation-velocity fling the steal's own freeze
		exists to prevent. The velocity would be just as wrong: the flight has its own.

		So a freeze that ends inside a flight simply lets go of its bookkeeping. The flight owns the
		anchors, the suspension and the velocity, and restores all three at the handoff. ]]
	local steal = Shard.get("StealController")
	if steal and (select(1, steal:getFlight())) ~= "idle" then
		self._freezeAnchors = nil
		self._freezeVel, self._freezeSpin, self._freezeSuspended = nil, nil, nil
		return
	end

	for part, wasAnchored in self._freezeAnchors or {} do
		if part.Parent then
			part.Anchored = wasAnchored
		end
	end
	self._freezeAnchors = nil

	--[[ `resume` before the velocity is put back, because it is `_resetLane` that clears the stale
		`_written` cross-velocity — and `_lane` reads the gap between what it last wrote and what it
		finds as an outside shove. Restoring the velocity into a shim still holding pre-freeze
		bookkeeping is the flung-sideways bug `resume`'s own note describes. ]]
	if self._freezeSuspended then
		self:resume()
	end
	self._freezeSuspended = nil

	if car and car.Parent and car.PrimaryPart and self._freezeVel then
		car.PrimaryPart.AssemblyLinearVelocity = self._freezeVel
		car.PrimaryPart.AssemblyAngularVelocity = self._freezeSpin or Vector3.zero
	end
	self._freezeVel, self._freezeSpin = nil, nil
end

--- Is the car currently held still by a freeze? Read by the tutorial's director, which has beats
--- that must not arm until the world is moving again.
function DriveController.isFrozen(self): boolean
	return self._frozen == true
end

--[[ PUBLIC (StealController) — the car you're driving now has a different top speed.

	`_baseMaxSpeed` is latched at install, and boost scales off it, so a steal that wrote the
	attribute directly would leave the shim boosting off a stale base and — worse — putting the OLD
	car's value back on teardown. This is the supported way to move the dial mid-race: it re-writes
	the attribute through the same path `_setBoost` uses, preserving whatever boost state is live.

	Ignored when the car never declared a MaxSpeed, for the same reason boost is: the stock fallback
	lives inside the Chassis module's own defaults and isn't ours to invent. ]]
function DriveController.setBaseMaxSpeed(self, value: number)
	if type(value) ~= "number" or value <= 0 then
		return
	end
	local car = self._car
	if not (car and car.Parent and self._baseMaxSpeed) then
		return
	end
	self._baseMaxSpeed = value
	-- Through the dial rather than straight at the attribute, so a steal taken mid-boost or
	-- mid-nitro lands on the new car's base with whichever of the two is live still applied.
	self:_applySpeedDial()
end

--[[ PUBLIC (WindController) — the highest this car's speed dial ever goes, in the `MaxSpeed`
	attribute's own units, or nil when the car never declared one.

	It is the BASE times the boost scale, which is a different thing from the attribute's live
	value: `_setBoost` writes the scaled figure while accelerate is held and the base back when it
	is released, so anything reading the attribute directly gets a number that means "the ceiling
	right now" rather than "the ceiling this car has". Callers asking whether the player is flat out
	want the second one.

	The attribute is NOT studs per second — the rig's units disagree with the world's by a factor
	the config header warns about — so a caller comparing this against a measured speed has to
	convert (see `WindConfig.StudsPerMaxSpeed`, which owns the measurement).

	NITRO IS DELIBERATELY LEFT OUT OF IT. A bottle raises the dial past this number, so a car under
	nitro measures over 1 against it and the one caller (`WindController`) clamps to a fully-open
	effect. That is the right answer and the reason this getter does not follow: "flat out" should
	mean the fastest the player can go WITHOUT SPENDING ANYTHING, so ordinary boost still reaches
	the top of the band. Fold nitro in here and boost would stop paying out the wind at all, and
	the effect would only ever appear for a few seconds a minute. ]]
function DriveController.getTopSpeed(self): number?
	local base = self._baseMaxSpeed
	if not base then
		return nil
	end
	return base * (if DriveConfig.AllowBoost then DriveConfig.BoostSpeedScale else 1)
end

--[[ PUBLIC (TrafficController) — this car's ordinary no-input cruise in measured studs/s.

	Traffic is authored as fractions of this number, so swapping from a starter car to a faster one
	does not turn the road into stationary obstacles. The conversion is the same measured chassis
	scale used by wind; unlike `getTopSpeed`, this deliberately excludes free boost. ]]
function DriveController.getCruiseSpeed(self): number?
	local base = self._baseMaxSpeed
	return if base then base * WindConfig.StudsPerMaxSpeed else nil
end

--[[ PUBLIC (TutorialController) — the player's raw throttle, -1..1, positive being accelerate.

	Kept current even while suspended, for the reason `_shapeThrottle`'s stash gives: the tutorial's
	opening beat holds the world still and waits for this to go positive, and a held world is a
	suspended shim. Nothing else reads it — the car itself does not need to, because the shaped
	value is what the chassis is handed. ]]
function DriveController.getThrottleInput(self): number
	return self._throttleInput or 0
end

-- PUBLIC (StealController) — the player's raw steering, -1..1, + = the direction STEER_LEFT means.
-- Kept current even while suspended (see _shapeSteer), which is what air control flies on.
function DriveController.getSteerInput(self): number
	return self._steerInput or 0
end

-- === On-screen controls (the driving HUD) ====================================

--[[ PUBLIC (DrivingHudController) — what the on-screen arrows and pedals are holding right now.

	Both are plain -1..1 values folded into the two input wrappers above, which is the entire
	integration: the buttons become just another device feeding the same shim the keyboard and the
	stock touch stick already feed, and every rule built on top of those inputs — boost, the brake
	floor, the lane-change easing, the heading cone, air control — applies to them untouched.

	Steering is stated in ROAD terms (+1 = left) rather than in the rig's steering sign, so the HUD
	never has to know about DriveConfig.PositiveSteerIsLeft; _shapeSteer converts it.

	These are stored, not consumed, because the stock Driver re-calls both wrappers every input
	frame — so a value written once stays applied until the HUD writes a different one. That also
	means a stale value is a stuck pedal, which is why DrivingHudController zeroes both whenever the
	controls stop being live, and why `_teardown` does too. ]]
function DriveController.setHudSteer(self, value: number)
	self._hudSteer = math.clamp(value, -1, 1)
	-- An arrow is being held: this player is steering with a finger, so `_lane` runs on the touch
	-- tuning (DriveConfig.Touch) until something else steers. Latched on the press and never on the
	-- release, because the eased stop after the release is half of what that tuning is for.
	if self._hudSteer ~= 0 then
		self._hudDriven = true
	end
end

function DriveController.setHudThrottle(self, value: number)
	self._hudThrottle = math.clamp(value, -1, 1)
end

-- === Install / teardown ======================================================

--[[ The deployed stock Driver LocalScript for `car`, once the server has handed the player
	its control GUI. RaceService names that GUI "<car>_<guid>_ClientControls" and matches on
	the Driver's CarValue; we do the same so a leftover GUI from a previous car can't fool us.

	We wait for this before requiring the Chassis module rather than requiring it as soon as the
	car exists, because if a module errors mid-body Roblox caches the *error* and every later
	require re-raises it — so being the first to require a half-replicated car could poison the
	module for the stock Driver too, and the car would never drive at all. By the time the
	server has deployed these controls the car is fully live on this client (we're welded to its
	seat and own its physics), so the module body has everything it reads. Note that's a
	strong ordering, not a hard guarantee that Driver required it first: the require is still
	wrapped in pcall so the worst case is a warn and stock controls.

	`ScriptsReference` is the last thing the stock `onEnterSeat` puts in that GUI, so testing for it
	is what distinguishes a finished deploy from one that died partway and left a Driver that will
	never get past its first require. Same test, same reason, as `RaceService._hasDriverControls` —
	and here it matters twice over, because the `task.wait()` our caller spends "letting the
	Driver's own require(Chassis) finish" is meaningless against a Driver that is never going to
	finish it. ]]
function DriveController._findDeployedDriver(self, car: Model): LocalScript?
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	for _, gui in playerGui:GetChildren() do
		if string.find(gui.Name, "_ClientControls", 1, true) then
			local driver = gui:FindFirstChild("Driver")
			local carValue = driver and driver:FindFirstChild("CarValue")
			if driver and driver:IsA("LocalScript") and not driver.Disabled then
				if carValue and carValue:IsA("ObjectValue") and carValue.Value == car then
					if gui:FindFirstChild("ScriptsReference") then
						return driver
					end
				end
			end
		end
	end
	return nil
end

--[[ THE DEPLOYED DRIVER THAT SWITCHED ITSELF OFF, PUT BACK — and the reason this repair lives on the
	client rather than beside the deploy that owns it.

	The stock Driver LocalScript disables ITSELF at the end of a drive: its `onExitSeat` unbinds the
	keys, hands the proximity prompts back and writes `script.Disabled = true`. That handler is a
	plain entry in `LocalVehicleSeating.OnExitFunctions`, called for every `Remotes.ExitSeat` the
	server fires at this client — and it does not ask WHICH seat was left or whether this player is
	still sitting in one. So a seat exit that is followed by a re-entry can kill the controls the
	re-entry just deployed: the remote is sent before the re-sit, the fresh Driver registers its
	handler after it, and if the two land in that order (a hitching client during the first road
	build is exactly when they do) the new script switches itself off on the frame it starts.
	MEASURED, on a live playtest: one `ExitSeat:FireClient` with the rider still seated → the Driver
	disabled, `OnExitFunctions` emptied, `VehicleChassisRawInput` unbound and every prompt back on.

	What that leaves is a car nobody can drive and nothing can see. `RaceService._hasDriverControls`
	cannot: `Disabled` was written by the CLIENT, so it does not replicate and the server goes on
	reading `false` — the repair loop in `_deployDriving` is blind to it, by construction, and no
	server-side test can be made to see it. This controller's own `_findDeployedDriver` does see it
	(it tests `not driver.Disabled`) and used to answer by timing out into "racing with stock
	controls" — which read as a stuck car with no error against it, and, on the tutorial's BOOST
	beat, as a world frozen forever waiting for a throttle input that can no longer be made.

	STILL SEATED IS THE WHOLE TEST. A real get-out disables that script deliberately, and putting it
	back there would rebind the driving keys and re-hide every prompt for a player standing in the
	lobby. Sitting in THIS car's seat with its controls switched off is not a state the stock kit can
	produce on purpose, so it is a fault, and it is one line to undo: re-enabling a LocalScript re-runs
	it from the top, which re-requires the chassis, rebinds the inputs and re-registers the exit
	handler. Verified live — bindings and prompts came back on the same frame. ]]
function DriveController._reviveDriver(self, car: Model?): boolean
	if not (car and car.Parent) then
		return false
	end
	local player = Players.LocalPlayer
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return false
	end

	-- See the header: the seat is the discriminator between a fault and an ordinary get-out.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if not (seat and seat:IsDescendantOf(car)) then
		return false
	end

	for _, gui in playerGui:GetChildren() do
		if string.find(gui.Name, "_ClientControls", 1, true) then
			local driver = gui:FindFirstChild("Driver")
			local carValue = driver and driver:FindFirstChild("CarValue")
			--- The same completeness test `_findDeployedDriver` runs, minus the `Disabled` it is
			--- looking for: a deploy that never finished is not this fault and must not be restarted
			--- here — its Driver would only yield on the `ScriptsReference` that never arrived.
			if
				driver
				and driver:IsA("LocalScript")
				and driver.Disabled
				and carValue
				and carValue:IsA("ObjectValue")
				and carValue.Value == car
				and gui:FindFirstChild("ScriptsReference")
			then
				if self._driverRevives >= DRIVER_REVIVE_LIMIT then
					return false
				end
				self._driverRevives += 1
				driver.Disabled = false
				self.log:warn(string.format(
					"The car's deployed Driver had switched itself off with the rider still seated (a stale seat-exit); switched it back on (%d/%d this race).",
					self._driverRevives,
					DRIVER_REVIVE_LIMIT
				))
				return true
			end
		end
	end
	return false
end

--[[ Watch the Driver we shimmed for the rest of the race, because the stale exit above can arrive at
	any point in it — a revive re-deploys the controls the same way an entry does, and every one of
	those re-deploys fires the same remote at this client.

	The install poll only covers the first `INSTALL_TIMEOUT` seconds and would not see a Driver that
	dies at minute two. One property signal covers the rest of the run for nothing, and `_reviveDriver`
	holds every guard, so this only has to decide WHEN to ask. ]]
function DriveController._watchDriver(self, driver: LocalScript)
	if self._driverConn then
		self._driverConn:Disconnect()
	end
	self._driver = driver
	self._driverConn = driver:GetPropertyChangedSignal("Disabled"):Connect(function()
		if not driver.Disabled then
			return
		end
		--- Deliberately late: see `DRIVER_REVIVE_DELAY`. A genuine exit clears the seat inside this
		--- window, and `_reviveDriver` then declines.
		task.delay(DRIVER_REVIVE_DELAY, function()
			if self._driver ~= driver or not self._active then
				return
			end
			self:_reviveDriver(self._car)
		end)
	end)
end

function DriveController._install(self, car: Model): boolean
	local scripts = car:FindFirstChild("Scripts")
	local module = scripts and scripts:FindFirstChild("Chassis")
	if not (module and module:IsA("ModuleScript")) then
		self.log:warn("Car has no Scripts.Chassis module; racing with stock controls.")
		return false
	end

	local ok, chassis = pcall(require, module)
	if not (ok and type(chassis) == "table") then
		self.log:warn(string.format("Could not require the car's Chassis module: %s", tostring(chassis)))
		return false
	end
	if type(chassis.UpdateThrottle) ~= "function" or type(chassis.UpdateSteering) ~= "function" then
		self.log:warn("Chassis module has no UpdateThrottle/UpdateSteering to wrap; racing with stock controls.")
		return false
	end

	local seat = car:FindFirstChild("VehicleSeat", true)
	if not (seat and seat:IsA("VehicleSeat")) then
		self.log:warn("Car has no VehicleSeat to read a heading from; racing with stock controls.")
		return false
	end

	-- Never wrap our own wrapper: capturing one as "stock" would recurse forever. Any live
	-- shim is undone first, so a double install is idempotent rather than fatal.
	self:_restoreStock()
	self:_restoreSpeedDial()
	self:_restoreRack()

	--[[ The car's speed dial, which stays the default cruise; boost scales off it. Cars that don't
		declare one just don't boost — the stock fallback lives inside the Chassis module's own
		defaults and isn't ours to guess at.

		STILL READ OFF THE ATTRIBUTE, and deliberately, even though the number now comes from
		`CarConfig`: the attribute is what the chassis is actually running on, and reading it back
		is the only thing that stays correct if a car reaches a race by a path that never stamped
		one. Reading `CarConfig` here instead would be this controller ASSERTING a speed the
		physics might not have. ]]
	local baseMaxSpeed = car:GetAttribute("MaxSpeed")
	if type(baseMaxSpeed) ~= "number" or baseMaxSpeed <= 0 then
		if DriveConfig.AllowBoost then
			self.log:warn("Car has no MaxSpeed attribute to scale; boost is off for this race.")
		end
		baseMaxSpeed = nil
	end
	self._baseMaxSpeed = baseMaxSpeed
	self._boosting = false
	-- Both claimants down and nothing written yet, so the first thing either of them asks for is a
	-- change. `_restoreSpeedDial` above has already done this; repeated here because the install
	-- is the one place a stale claim would ride into a fresh race.
	self._nitroScale = 1
	self._starScale = 1
	self._dialWritten = nil

	self._car = car
	self._seat = seat
	self._chassis = chassis
	self._stock = {
		UpdateThrottle = chassis.UpdateThrottle,
		UpdateSteering = chassis.UpdateSteering,
		EnableHandbrake = chassis.EnableHandbrake,
	}
	local stock = self._stock

	-- Called with `.`, not `:`, by the stock Driver — plain functions, no self.
	chassis.UpdateThrottle = function(currentSpeed, throttle)
		return stock.UpdateThrottle(currentSpeed, self:_shapeThrottle(throttle))
	end
	chassis.UpdateSteering = function(steer, currentVel)
		return stock.UpdateSteering(self:_shapeSteer(steer), currentVel)
	end
	if type(stock.EnableHandbrake) == "function" then
		chassis.EnableHandbrake = function(...)
			if self._active and not DriveConfig.AllowHandbrake then
				return
			end
			return stock.EnableHandbrake(...)
		end
	end

	self:_stiffenRack(car)

	self._active = true
	self._peakSpeed = 0
	self._flippedFor = 0
	self._pinnedFor = 0
	self:_resetLane()
	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_step(dt)
	end)
	return true
end

--[[ Per-frame work: track the run's peak speed (the reference the brake floor is measured
	against — see _brakeAllowance) and run the heading backstop.

	The peak deliberately never decays. Obstacle hits and wall scrapes scrub speed hard, and a
	floor that sagged with them would let a chain of hits walk the car down to a crawl. ]]
--[[ Hold the kit's engine RPM up where the speed says it should be. See `DriveConfig.EngineAudio`
	for the curve this replaces and why replacing it is the only way to stop the engine droning.

	RESOLVED LAZILY AND CACHED PER CAR, because `Scripts` is deployed onto the car a beat after the
	race starts (`RaceService._deployDriving`) and is gone with it at the end. `false` is the
	remembered "this car has no kit audio", so a rig without the module is asked once rather than
	every frame for the length of a race. ]]
function DriveController._engineAudio(self, car: Model, dt: number)
	local cfg = DriveConfig.EngineAudio
	if not cfg.Enabled then
		return
	end

	local effects = self._effects
	if effects == nil then
		local scripts = car:FindFirstChild("Scripts")
		local module = scripts and scripts:FindFirstChild("Effects")
		if not (module and module:IsA("ModuleScript")) then
			return -- not deployed yet; ask again next frame
		end
		--- Guarded: this is kit code being required out of its own context, and a module that
		--- errors on load must cost the engine note rather than the race.
		local ok, result = pcall(require, module)
		effects = (ok and type(result) == "table" and result) or false
		self._effects = effects
		if effects then
			self:_wrapThrottle(effects)
		end
	end
	if not effects then
		return
	end

	local gearbox = DriveConfig.Gearbox
	local oldGear = self._audioGear
	local seat = self._seat
	local velocity = if seat and seat.Parent and not seat.Anchored then seat.AssemblyLinearVelocity else Vector3.zero
	local speedMph = Vector3.new(velocity.X, 0, velocity.Z).Magnitude * MPH_PER_STUD
	local gear, through = AutomaticGearbox.sample(
		speedMph,
		oldGear,
		if self._baseMaxSpeed then self._baseMaxSpeed * WindConfig.StudsPerMaxSpeed * MPH_PER_STUD * DriveConfig.BoostSpeedScale else gearbox.TopMph,
		gearbox.Gears,
		gearbox.DownshiftHysteresis
	)
	self._audioGear = gear

	-- The sawtooth is the gear sound: climb to redline, then fall to the bottom of the next RPM
	-- band. Holding the load off for one short beat keeps the kit's smoothed RPM model from
	-- rounding that corner back into a continuous drone.
	if gear > oldGear then
		self._audioShiftFor = cfg.ShiftPause
	end
	local gain = cfg.MinGain + (1 - cfg.MinGain) * through
	if self._audioShiftFor > 0 then
		self._audioShiftFor = math.max(0, self._audioShiftFor - dt)
		gain = math.min(gain, cfg.ShiftGain)
	end

	self:_stepRev(dt)

	--- `true` unconditionally: the throttle IS always full (`AutoThrottle`), so the engine is always
	--- under load. What changes is how hard, and that is the gain.
	pcall(function()
		effects:SetThrottleEnabled(true, gain)
	end)
end

--[[ PUBLIC (StealController) — rev this engine once. See `DriveConfig.EngineAudio.Rev`.

	Timed off `_engineAudio`'s own frames rather than the clock, because the steal calls this a
	moment BEFORE the drive resumes (`_notifyStolen` runs ahead of `_endFlight`), and a rev that
	counted suspended frames would be half over before the engine could play any of it. ]]
function DriveController.rev(self)
	local cfg = DriveConfig.EngineAudio
	if cfg.Enabled and cfg.Rev and cfg.Rev.Enabled and self._active then
		self._revClock = 0
	end
end

--[[ Advance the rev and say which gain it is holding, or nil once it is over.

	THE GAIN IS NOT HANDED TO THE CALL BELOW, IT IS WRAPPED INTO THE KIT (`_wrapThrottle`). The kit's
	own Driver writes the same setting at ~30Hz and its client forwards at most five a second, so a
	rev written only from here would lose some of those five sends to the kit's normal gain and come
	out as half a rev. While `_revGain` is set every writer sends it.

	The edge into each phase is sent at once (the off/on pair below) instead of waiting out the
	kit's 0.2s send window, which would otherwise eat half of the rise. ]]
function DriveController._stepRev(self, dt: number)
	local clock = self._revClock
	if clock == nil then
		return
	end
	local rev = DriveConfig.EngineAudio.Rev
	clock += dt
	self._revClock = clock
	local gain = nil
	if clock <= rev.RiseTime then
		gain = rev.RiseGain
	elseif clock <= rev.RiseTime + rev.FallTime then
		gain = rev.FallGain
	else
		self._revClock = nil
	end
	if gain == self._revGain then
		return
	end
	self._revGain = gain
	local send = self._throttleSend
	if send and gain then
		--- An off then an on: the kit forwards immediately whenever the on/off state CHANGES, so
		--- this is the one way to put a new gain on the wire this frame. The server reads both
		--- inside one frame and only the second survives to its next heartbeat.
		pcall(send, self._effects, false)
		pcall(send, self._effects, true, gain)
	end
end

--[[ Let `_revGain` override whatever gain anyone asks the kit for while a rev is running.

	Wrapped on the MODULE table for the reason the header of `DriveConfig.EngineAudio` gives: that is
	the table the kit's Chassis calls through, so one wrapper covers its writes and ours. Installed
	once per car, when `_engineAudio` first resolves the module, and unwound in `_teardown` (the
	module is cached by the client for as long as the car exists). ]]
function DriveController._wrapThrottle(self, effects)
	local original = rawget(effects, "SetThrottleEnabled")
	if type(original) ~= "function" then
		return
	end
	self._throttleSend = original
	effects.SetThrottleEnabled = function(this, toggle, gain, ...)
		local override = self._revGain
		if override and toggle then
			gain = override
		end
		return original(this, toggle, gain, ...)
	end
end

function DriveController._settleNitro(self, dt: number)
	if self:_surge() > 1 or os.clock() >= (self._nitroRecoveryUntil or 0) or self._frozen then return end
	local primary = self._car and self._car.PrimaryPart
	local info = self._road and self._road:getRoadInfo()
	if not (primary and primary.Parent and not primary.Anchored and info and self._seat and self._seat.Occupant and self._baseMaxSpeed) then return end
	local ceiling = self._baseMaxSpeed * self:_speedDial() * WindConfig.StudsPerMaxSpeed * DriveConfig.NitroRecovery.CruiseHeadroom
	local velocity = primary.AssemblyLinearVelocity
	local drop = DriveConfig.nitroRecoveryDelta(velocity:Dot(info.forward), ceiling, dt)
	if drop > 0 then primary.AssemblyLinearVelocity = velocity - info.forward * drop end
end

-- Limit positive forward speed gains only. Braking and collision slowdowns land immediately.
-- Lateral/vertical velocity and the existing speed ceiling remain owned by their current paths.
function DriveController._limitForwardAcceleration(self, dt: number)
 local primary = self._car and self._car.PrimaryPart
 local info = self._road and self._road:getRoadInfo()
 local cfg = DriveConfig.ForwardAcceleration
 if not (cfg.Enabled and primary and primary.Parent and not primary.Anchored
  and self._seat and self._seat.Occupant and info and dt > 0) then
  self._lastForwardSpeed = nil
  return
 end
 local forward = info.forward
 local velocity = primary.AssemblyLinearVelocity
 local speed = velocity:Dot(forward)
 local previous = self._lastForwardSpeed
 if previous then
  local rate = if self:_surge() > 1 then cfg.NitroStudsPerSecondSquared else cfg.StudsPerSecondSquared
  local ceiling = previous + rate * dt
  if speed > ceiling then
   velocity -= forward * (speed - ceiling)
   primary.AssemblyLinearVelocity = velocity
   speed = ceiling
  end
 end
 self._lastForwardSpeed = speed
end

-- Run before physics, after steering/impact writes from the previous frame.
-- Restrict only the road-cross component; forward speed, height and inward steering survive.
function DriveController._guardRoadEdges(self, dt: number)
 if not self._active or self._suspended or self._frozen then return end
 local car=self._car
 local primary=car and car.PrimaryPart
 if not (primary and primary.Parent and not primary.Anchored and self._seat and self._seat.Occupant) then return end
 local info=self._road and self._road:getRoadInfo()
 if not info then return end
 local hull=self._edgeHitBox
 if not (hull and hull:IsDescendantOf(car)) then hull=car:FindFirstChild("HitBox",true);self._edgeHitBox=hull end
 if not (hull and hull:IsA("BasePart")) then return end
 local cross=info.cross
 local limit=RoadEdgeGuard.limit(hull.CFrame,hull.Size,cross,info.driveWidth,DriveConfig.LaneHalfWidth)
 local offset=hull.Position:Dot(cross)-info.driveCenter
 local velocity=primary.AssemblyLinearVelocity
 local actual=velocity:Dot(cross)
 local want=RoadEdgeGuard.constrain(offset,actual,limit,dt)
 if math.abs(want-actual)>1e-4 then
  primary.AssemblyLinearVelocity=velocity+cross*(want-actual)
  self._lateral=want
  self._written=want
  self._lateralVel=0
 end
end

function DriveController._step(self, dt: number)
	-- Airborne: the car is anchored and StealController is flying it. Every write below would be
	-- discarded now and inherited at the handoff — see `suspend`. The peak is skipped with it:
	-- an anchored assembly reports zero speed, and while the peak never decays (so a zero could
	-- not lower it), sampling a number that means nothing is worse than not sampling.
	if self._suspended then
		return
	end

	self:_settleNitro(dt)
	self:_limitForwardAcceleration(dt)
	local speed = self:_forwardSpeed()
	if speed > self._peakSpeed then
		self._peakSpeed = speed
	end

	--- The engine note uses the same flat speed as the dashboard so its shifts agree with the gear
	--- label. Before the handling work because it reads nothing that work writes, and stale audio
	--- is more noticeable than lane ease being one frame behind.
	if self._car and self._car.Parent then
		self:_engineAudio(self._car, dt)
	end
	-- One or the other, never both: _lane's servo already does everything _recover exists to do,
	-- and the two would be writing the same yaw value from different targets.
	if DriveConfig.DirectSteering then
		self:_lane(dt)
	else
		self:_recover(dt)
	end
	-- Under both, and after both. A flip is not a steering problem, and this writes the two
	-- rotation axes neither of the above touches — but it can also RESET the car outright, and
	-- doing that after the frame's velocity writes rather than before means they land on the car
	-- we're throwing away instead of on the pose we just placed.
	self:_upright(dt)
	--[[ ...and last of all, the car that is stuck WITHOUT being over. `_upright` is gated on tilt
		and answers nothing for a car pinned flat against the median, which is the state three
		testers reported in one session. Below it rather than above, because a car that is both
		flipped AND stopped is a flip: that recovery is gentler, it is already running, and letting
		it have its `ResetAfter` first means the reset only ever happens once. ]]
	self:_pinned(dt)
end

--[[ The last-resort recovery for a car that is stuck upright — see `DriveConfig.Pinned`.

	Throttle held, going nowhere, for `Pinned.After` seconds: put it back on the lane. Everything
	this needs is already in `_resetUpright`, including the cross-road clamp that is the actual cure
	for a car welded to the guardrail, so this function is only the trigger.

	THE THREE STATES IT MUST NOT FIRE IN are all states where a stationary car is correct, and each
	is excluded by the thing that made it stationary rather than by a flag this would have to be
	told about:

	  • suspended — StealController is flying the car; `_step` has already returned above this.
	  • frozen — `RaceFreezeController` is holding the world for a tutorial beat, and the beat that
	    does that is the one asking the player to HOLD ACCELERATE. That is throttle with no speed by
	    construction, and resetting the car out from under the card teaching them to drive would be
	    the worst possible false positive.
	  • anchored for any other reason — belt to the two braces above, and free. An anchored assembly
	    reports no velocity, so anything holding the car that this file does not know about would
	    otherwise read as pinned. ]]
function DriveController._pinned(self, dt: number)
	local cfg = DriveConfig.Pinned
	if not cfg.Enabled or self._frozen then
		self._pinnedFor = 0
		return
	end
	local primary = self._car and self._car.PrimaryPart
	-- Only ever unstick a car someone is actually in, the same guard `_upright` opens with: a wreck
	-- coasting to a stop is a beat, not a fault.
	if not (primary and primary.Parent and not primary.Anchored and self._seat and self._seat.Occupant) then
		self._pinnedFor = 0
		return
	end

	-- Asking to go, and not going. Both halves, every frame — a single frame of either answer being
	-- "no" is enough to say this car is not stuck, so the timer starts again rather than pausing.
	--[[ UNDER AUTOTHROTTLE, NOT BRAKING IS ASKING TO GO (2026-10-07). This used to want the raw
		throttle positive, which here means HOLDING BOOST: the pedal is always down on its own, so a
		player who knocked a car into the side and then just steered never tripped the timer and sat
		wedged for the rest of the run. A phone player who never touches the boost pedal could not
		be rescued at all. Only a held brake still counts as wanting to stop. ]]
	local raw = self:getThrottleInput()
	local asking = if DriveConfig.AutoThrottle > 0 then raw > -0.1 else raw > 0
	if not asking or self:_forwardSpeed() >= cfg.Speed then
		self._pinnedFor = 0
		return
	end

	self._pinnedFor += dt
	if self._pinnedFor < cfg.After then
		return
	end
	self._pinnedFor = 0
	--[[ Clear the wreck first. A car knocked into the side stops within a stud of where it was hit
		(`TrafficConfig.Knock`), and the reset keeps our place on the road, so putting the car back
		without moving the wreck just puts it back inside the thing it was stuck on. ]]
	local traffic = Shard.get("TrafficController")
	if traffic and cfg.ClearWrecks > 0 then
		traffic:clearWrecksNear(primary.Position, cfg.ClearWrecks)
	end
	self:_resetUpright("pinned")
end

-- Hand the stock functions back. The car is usually being destroyed anyway (which takes the
-- module and its require cache entry with it), but restoring keeps this correct if a race
-- ends without the car going away — and it's what makes a re-install safe.
-- Undo a live boost or nitro, so a car can never be left on the raised speed dial. Paired with
-- _restoreStock: both run on teardown and again before any re-install. The test is what we last
-- WROTE rather than which claimant was up, because either of them raising the dial leaves the same
-- job to do and a car we never wrote to must not be handed a number we invented.
function DriveController._restoreSpeedDial(self)
	if self._dialWritten and self._baseMaxSpeed and self._car and self._car.Parent then
		self._car:SetAttribute("MaxSpeed", self._baseMaxSpeed)
	end
	self._boosting = false
	self._nitroScale = 1
	self._starScale = 1
	self._nitroRecoveryUntil = nil
	self._lastNitroKickAt = nil
	self._dialWritten = nil
	self._baseMaxSpeed = nil
end

--[[ LET OFF THE GAS BEFORE HANDING THE CHASSIS BACK.

	Ending a race CUTS THE INPUT, and that is not the same thing as telling the car to stop.
	`RaceService._cleanupDriverControls` destroys the ScreenGui the stock `Driver` LocalScript lives
	in, which ends the loop calling `UpdateThrottle` every frame — but the wheel motors keep whatever
	`Chassis.SetMotorVelocity` last wrote to their `AngularVelocity`, so the car carries on under
	power with nothing left to govern it. Measured on a Charger whose controls were cut at 73
	studs/s: it climbed to 86 over the next two seconds, PAST the ~52 the stock throttle's per-frame
	exp(-3r^2) damping normally holds it to — because that damping is exactly what stopped running.

	Both endings only looked right because something else happened to be stopping the car:
	ObstacleController coasts a wreck, and the getaway freezes a bank onto the bay floor. Neither of
	those is the drive being switched off, so any path that reaches neither — or a client where one
	of them errors — is left with a driverless car at full throttle.

	`UpdateThrottle(speed, 0)` is the stock idle branch: target motor velocity 0 and a light 2000 of
	torque, which is a driver lifting off rather than a handbrake, and so does not fight the coast.
	`UpdateSteering(0, speed)` centres the rack so it runs out straight instead of holding the last
	lock. THE STOCK FUNCTIONS, not the wrapped ones — the shim's job is shaping a live input and
	there is no longer one to shape.

	This is the client's call to make: it owns the car's physics (RaceService hands the driver
	network ownership) and it is the side the stock Driver was calling from anyway. The server half
	of this already exists for an ordinary get-out — `Modules/Vehicle`'s `onExitSeat` calls
	`Chassis.Reset` — and it is precisely what a race skips by destroying the GUI directly. ]]
function DriveController._neutraliseDrive(self)
	local chassis, stock = self._chassis, self._stock
	if not (chassis and stock) then
		return -- never installed, or already restored
	end
	local car = self._car
	if not (car and car.Parent) then
		return -- the car is gone; there are no motors left to command
	end
	-- Wrapped in a pcall because this runs on the way out of a race that may already be half torn
	-- down, and a throw here would skip the restores below it in `_teardown`.
	local ok, err = pcall(function()
		local speed = if type(chassis.GetAverageVelocity) == "function" then chassis.GetAverageVelocity() else 0
		if stock.UpdateSteering then
			stock.UpdateSteering(0, speed)
		end
		if stock.UpdateThrottle then
			stock.UpdateThrottle(speed, 0)
		end
	end)
	if not ok then
		self.log:warn(string.format("Could not neutralise the drive on teardown: %s", tostring(err)))
	end
end

function DriveController._restoreStock(self)
	local chassis, stock = self._chassis, self._stock
	if chassis and stock then
		chassis.UpdateThrottle = stock.UpdateThrottle
		chassis.UpdateSteering = stock.UpdateSteering
		if stock.EnableHandbrake then
			chassis.EnableHandbrake = stock.EnableHandbrake
		end
	end
	self._chassis = nil
	self._stock = nil
end

function DriveController._teardown(self)
	self._edgeHitBox = nil
	self._lastForwardSpeed = nil
	self._active = false
	self._suspended = false -- a race that ended mid-flight must not leave the next one dead-pedalled
	--- The kit's audio module, cached per car by `_engineAudio`. It is deployed onto the car and
	--- dies with it, so a handle kept across races would point at a destroyed script — and, worse,
	--- `false` kept across races would remember "this car has no engine audio" about a car that is
	--- not this one.
	local effects = self._effects
	if effects and self._throttleSend then
		effects.SetThrottleEnabled = self._throttleSend
	end
	self._throttleSend = nil
	self._revClock, self._revGain = nil, nil
	self._effects = nil
	self._audioGear = 1
	self._audioShiftFor = 0
	--[[ ...and a race that ended mid-HOLD must not leave the next one anchored. The parts this was
		holding are going away with the car, so there is nothing to put back — only the flags, which
		would otherwise make the next `setFrozen(true)` a no-op and the tutorial's first pause do
		nothing at all. Cleared unconditionally for `TimeScale.reset`'s reason: a hold is strong
		enough to be worth a way out that does not depend on its owner still being alive. ]]
	self._frozen = false
	self._freezeAnchors = nil
	self._freezeVel, self._freezeSpin, self._freezeSuspended = nil, nil, nil
	-- Same reasoning one line up: a race that ended with a pedal held must not carry that pedal
	-- into the next one. DrivingHudController clears these too; this is the backstop for a race
	-- that unwinds without it (no HUD in the place, a warn during binding, a mid-race error).
	self._hudSteer = 0
	self._hudThrottle = 0
	self._installing += 1 -- invalidates any install poll still in flight
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	--[[ ...and stop watching the Driver. A race ends by that script being destroyed with its GUI or
		disabling itself on the way out, and both are exactly what `_reviveDriver` exists to undo —
		so the watch has to go before the teardown produces the state it reacts to. ]]
	if self._driverConn then
		self._driverConn:Disconnect()
		self._driverConn = nil
	end
	self._driver = nil
	self:_neutraliseDrive() -- command the motors to stop BEFORE we give the chassis back
	self:_restoreSpeedDial() -- before we let go of the car below
	self:_restoreRack()
	self:_restoreStock()
	self._car = nil
	self._seat = nil
	self._peakSpeed = 0
	self._flippedFor = 0
	self._pinnedFor = 0
	self:_resetLane()
end

--[[ Undo the client-side state the stock Driver LocalScript sets up and never gets to undo.

	The client half of the gap `_cleanupDriverControls` and `_restoreRiderAvatar` cover on the
	server: entering a race deploys that script inside a ScreenGui, leaving destroys the GUI
	outright, so the script's own `onExitSeat` — and the car-removed fallback behind it — never
	run. What it leaves behind lives on *services*, not on the car or the character, so it also
	survives respawning:

	  • Its ContextActionService bindings. The raw-input one is bound at ContextActionPriority
	    .High, above the PlayerModule's own movement actions, and its handler sinks every key it
	    doesn't hand back — so the leaked binding quietly eats WASD and jump, and the player is
	    left standing at spawn unable to walk. Nothing errors; they just can't move.
	  • ProximityPromptService.Enabled, which it switches off for the duration of a drive. Left
	    off, every prompt in the game is dead — including the "Enter Race" prompt, so a wrecked
	    player can't start another run either.

	Restoring the switch to `true` outright (rather than to a captured value) is deliberate: it's
	exactly what the stock `onExitSeat` does, so this behaves identically to a normal get-out.

	Runs on RaceEnd only, NOT RaceWrecked. By RaceEnd the car and that script are gone for
	certain; at RaceWrecked the GUI's destruction is still in flight, and unbinding first would
	freeze the script's last input values — a held W would keep throttling, because the key
	release it's waiting on would never arrive — and fight the coast-to-a-stop. Deliberately
	outside the DriveConfig.Enabled gate too: the stock script deploys these whether or not our
	shim is running. ]]
function DriveController._releaseVehicleInput(self)
	for _, action in Vehicle.DriverActionNames do
		ContextActionService:UnbindAction(action)
	end
	ProximityPromptService.Enabled = true
end

--- Seconds after leaving a seat before the prompt switch is checked. Long enough for the stock
--- exit (`onExitSeat`, the door swing) to have run and put it back itself when it is going to.
local PROMPT_GUARD_DELAY = 1

--[[ THE SAME LEAK OUTSIDE A RACE (2026-09-28). `_releaseVehicleInput` repairs the prompt switch at
	RaceEnd, which covers the race — but the stock Driver script is deployed for EVERY driver's seat,
	lobby cars included, and a lobby car put away with somebody in it (`LobbyCarService._despawn`)
	loses its GUI the same way a race car does. Reported as bay prompts that "sometimes" could not be
	pressed, with nothing in any log: the press never left the client, because every prompt in the
	game was switched off.

	So whenever the character leaves its seat outside a race, and is still out of every seat a moment
	later, the switch is put back on — the stock exit's own `true`, for `_releaseVehicleInput`'s
	reason. A WARNING WHEN IT HAD TO, so the next time this happens the log says so instead of
	nothing. Skipped while `_active`: a race re-seats its driver several times while deploying
	(`RaceService._deployDriving`), and RaceEnd owns the repair there. ]]
function DriveController._guardPrompts(self)
	local player = Players.LocalPlayer
	local function watch(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not (humanoid and humanoid:IsA("Humanoid")) then
			return
		end
		local function check()
			task.delay(PROMPT_GUARD_DELAY, function()
				if self._active or humanoid.SeatPart ~= nil or ProximityPromptService.Enabled then
					return
				end
				ProximityPromptService.Enabled = true
				self.log:warn("Every prompt was left switched off after leaving a seat (bays, sell lot, buyers could not be pressed); switched back on.")
			end)
		end
		humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
			if humanoid.SeatPart == nil then
				check()
			end
		end)
		--- A respawn is the other way out of a seat, and the switch lives on a service, so it outlives
		--- the character (the header note on `_releaseVehicleInput`).
		check()
	end
	if player.Character then
		task.spawn(watch, player.Character)
	end
	player.CharacterAdded:Connect(watch)
end

-- === Staying in the car ======================================================

-- Our swallow of the stock exit keys. ContextActionService unbinds by name, so one shared name
-- for the session (see `_holdSeat`).
local HOLD_SEAT_ACTION = "RaceHoldSeat"
-- The stock kit's touch "get out" button, deployed inside the car's control GUI. Same problem as
-- the key and the same fix — see `_holdSeat`.
local STOCK_EXIT_BUTTON = "ExitButton"

--[[ Hold the player in their seat for the length of a race (DriveConfig.HoldSeatDuringRace).

	SWALLOWED, NOT UNBOUND, and that difference is the whole reason this works. The obvious fix is
	`UnbindAction("VehicleChassisExitVehicle")` — but the deployed `Driver` LocalScript binds that
	action as one of the first things it does, and the server re-deploys it per race and re-seats
	the player several times while doing so (`_deployDriving`). An unbind is therefore a race
	against a bind we do not control the timing of, and losing it silently reopens the hole. A
	higher-priority action that sinks the key cannot lose that race: it does not care whether the
	stock binding exists yet, or at all.

	TWO INPUT PATHS, because hiding only the key would leave the bug live on phones: the kit also
	deploys a touch `ExitButton` that calls the same `LocalVehicleSeating.ExitSeat()`. It is latched
	rather than hidden once, for exactly the reason DrivingHudController._suppressStockSpeedo
	latches the speedo — `VehicleGui` sets its own visibility during setup, after the frame is
	parented, so a single hide loses to it.

	Race-scoped on purpose. A car driven anywhere but a race keeps its ordinary get-out; this is
	bound on RaceStart and dropped on RaceEnd. ]]
function DriveController._holdSeat(self)
	if self._seatHeld or not DriveConfig.HoldSeatDuringRace then
		return
	end
	self._seatHeld = true

	ContextActionService:BindActionAtPriority(HOLD_SEAT_ACTION, function()
		return Enum.ContextActionResult.Sink
	end, false, DriveConfig.ExitLockPriority, table.unpack(DriveConfig.ExitKeys))

	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local function claim(inst: Instance)
		if inst.Name ~= STOCK_EXIT_BUTTON or not inst:IsA("GuiObject") then
			return
		end
		self._exitButtons[inst] = inst.Visible
		inst.Visible = false
		table.insert(
			self._seatConns,
			inst:GetPropertyChangedSignal("Visible"):Connect(function()
				if inst.Visible and self._seatHeld then
					inst.Visible = false
				end
			end)
		)
	end
	for _, descendant in playerGui:GetDescendants() do
		claim(descendant)
	end
	-- The controls GUI is deployed a beat after RaceStart, and again on every re-seat, so the
	-- button we have to hide usually does not exist yet when this runs.
	table.insert(self._seatConns, playerGui.DescendantAdded:Connect(claim))
end

-- Give the seat back: the keys, the latch, and any exit button still alive. Buttons are restored
-- to what they were rather than to `true`, so a race that ends on a device where the kit never
-- showed one does not leave one behind.
function DriveController._releaseSeat(self)
	if not self._seatHeld then
		return
	end
	self._seatHeld = false
	ContextActionService:UnbindAction(HOLD_SEAT_ACTION)

	for _, conn in self._seatConns do
		conn:Disconnect()
	end
	table.clear(self._seatConns)

	for button, wasVisible in self._exitButtons do
		if button.Parent then
			button.Visible = wasVisible
		end
	end
	table.clear(self._exitButtons)
end

--[[ Wait for the car (RoadController resolves it from the seat we're welded to) and for the
	server to deploy its driver controls, then wrap. Both arrive a beat after RaceStart, and
	RaceService may re-seat the player a few times while deploying, so polling is simpler and
	more forgiving than trying to catch the one right event. ]]
function DriveController._onRaceStart(self)
	self:_teardown()
	if not DriveConfig.Enabled then
		return
	end
	if not self._road then
		self.log:warn("RoadController unavailable; cannot read a road heading. Racing with stock controls.")
		return
	end

	self._installing += 1
	local token = self._installing
	self._driverRevives = 0 -- a fresh budget per race; see DRIVER_REVIVE_LIMIT

	task.spawn(function()
		local t0 = os.clock()
		while self._installing == token and os.clock() - t0 < INSTALL_TIMEOUT do
			local car = self._road:getCar()
			--[[ A deploy that landed and then switched itself off is the one failure this poll
				cannot wait out — it would spin here for the full timeout against a Driver that is
				never coming back on its own. `_reviveDriver` is a no-op in every other case, so it
				costs a walk of PlayerGui's children per pass. ]]
			if car and car.Parent then
				self:_reviveDriver(car)
			end
			local driver = car and car.Parent and self:_findDeployedDriver(car)
			if driver then
				task.wait() -- let the Driver's own require(Chassis) finish first
				if self._installing ~= token then
					return
				end
				-- Either way we're done: _install explains its own failures, and spinning on
				-- a car that can't be shimmed would just repeat them.
				if self:_install(car) then
					self:_watchDriver(driver) -- ...and keep it alive for the rest of the race
				end
				return
			end
			task.wait(0.05)
		end
		if self._installing == token then
			self.log:warn("Never got a drivable car to shim; racing with stock controls.")
		end
	end)
end

DriveController:withRemoteEvents({
	{
		-- `_holdSeat` is deliberately OUTSIDE `_onRaceStart`, which returns early when the shim is
		-- switched off or there is no road to read. Not being able to get out mid-race is a rule of
		-- the race, not a feature of our steering — it has to hold even when the car is running on
		-- stock controls.
		RaceStart = function()
			DriveController:_holdSeat()
			DriveController:_onRaceStart()
		end,
		-- HP is gone. RaceService has already torn the driver GUI down (so nothing calls the
		-- wrappers any more) and ObstacleController is coasting the car to a stop — the yaw
		-- backstop must not fight that.
		RaceWrecked = function()
			DriveController:_teardown()
		end,
		--[[ ...and the wreck was paid out of (`ReviveService`): re-install the shim on the car that
			is going back on the road.

			`_onRaceStart` is the right call and `_holdSeat` deliberately is NOT beside it, unlike at
			race start. The seat hold and the player's own movement keys are released on `RaceEnd`,
			not on `RaceWrecked` — precisely so a player cannot unseat themselves into the wreck beat
			— so they were never given up and re-taking them would be a second claim on the same
			bindings. Only the shim was torn down, and only the shim comes back.

			It polls for a deployed Driver for `INSTALL_TIMEOUT`, which is 15s against the
			`ReviveConfig.ReviveHoldTime` + deploy this is waiting on. Room to spare, and the poll is
			the same one that already covers a slow entry. ]]
		RaceRevived = function()
			DriveController:_onRaceStart()
		end,
		-- The race is over and the car is gone: drop the shim, hand the player's own movement keys
		-- back (see _releaseVehicleInput — without this they can't walk), and give the exit back so
		-- the next car they sit in outside a race behaves normally.
		--
		-- RaceEnd and not RaceWrecked, for the same reason `_releaseVehicleInput` waits: the wreck
		-- beat still has the player sitting in the car while it coasts and the fade comes up, and
		-- handing E back inside that window would let them unseat themselves into it.
		RaceEnd = function()
			DriveController:_teardown()
			DriveController:_releaseVehicleInput()
			DriveController:_releaseSeat()
		end,
	},
})

DriveController:withLifecycle({
	init = function(self)
		self._active = false
		self._suspended = false -- true while StealController owns the car (mid-flight)
		self._frozen = false -- true while the world is held at a stop (RaceFreezeController)
		self._installing = 0 -- bumped per race; stale install polls compare against it
		self._driverRevives = 0 -- stale-exit repairs made this race; see DRIVER_REVIVE_LIMIT
		self._peakSpeed = 0 -- fastest forward speed this run; the brake floor's reference
		self._flippedFor = 0 -- seconds continuously past Upright.FlippedDeg; see _upright
		self._pinnedFor = 0 -- seconds continuously on the throttle without moving; see _pinned
		self._boosting = false
		self._nitroScale = 1 -- the other claimant on the speed dial; see _speedDial / setNitro
		self._starScale = 1 -- the Star pickup's claim on the same dial; see setStar
		self._dialWritten = nil -- the last MaxSpeed we wrote, so a re-write is only ever a change
		self._hudSteer = 0 -- the on-screen arrows, +1 = left (DrivingHudController)
		self._hudThrottle = 0 -- the on-screen pedals, +1 = accelerate, -1 = brake
		self._hudDriven = false -- were the arrows the last thing to steer? see _touchSteering
		self._audioGear = 1 -- simulated gearbox state shared in shape with the dashboard
		self._audioShiftFor = 0 -- seconds left in the brief upshift load cut
		self._revClock = nil -- seconds into a running steal rev, nil when none; see rev
		self._revGain = nil -- the gain that rev is holding the kit at; see _stepRev
		self._throttleSend = nil -- the kit's own SetThrottleEnabled, under our wrapper

		self._seatHeld = false -- is the race's "you can't get out" swallow live? see _holdSeat
		self._seatConns = {} -- connections it owns (the exit-button latch)
		self._exitButtons = {} -- [GuiObject] = the Visible we found it with, to put back

		self:_resetLane() -- direct mode's steering state; see _resetLane
	end,

	start = function(self)
		self._road = Shard.get("RoadController")
		self:_guardPrompts()
		self._edgeConn = RunService.PreSimulation:Connect(function(dt) self:_guardRoadEdges(dt) end)
	end,
})

DriveController:withCleanup(function()
 if DriveController._edgeConn then DriveController._edgeConn:Disconnect();DriveController._edgeConn=nil end
end)

return DriveController
