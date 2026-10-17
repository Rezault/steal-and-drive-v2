--[[
	RaceCameraController  (client)
	------------------------------
	The race camera. It follows the car's POSITION in the road's frame and takes a PARTIAL, LAGGED
	share of its HEADING: you weave left and right, the shot slides with you and swings a little
	way into the turn, and that's all the rotation there is. Enough that steering reads as
	rotation; not enough that the road stops reading as a straight corridor you're threading.

	Why a share. This camera was fixed-orientation to begin with — the Rodeo Stampede shot, which
	is the right instinct for a runner — and it read beautifully in first person and wrong in
	third. The reason is worth writing down, because it isn't obvious from either end: in first
	person your view is bolted to the car, so the car's yaw IS the turn feedback and arrives the
	instant the rack bites. Take the rotation out of the frame and that cue is simply gone; a turn
	becomes a car pivoting inside a static shot, and all you actually feel is lateral drift
	arriving a beat later. Identical physics, and it reads as understeer. So the frame has to
	rotate some — see CameraConfig's Turning section for how much and why that much.

	What we're replacing. Sitting in a VehicleSeat makes the engine point `Camera.CameraSubject`
	at the seat, which is what the stock PlayerModule uses to switch itself over to its built-in
	VehicleCamera — a chase cam that aligns to the car's heading 1:1, which is the far end of the
	same dial and pivots the world far too hard. Setting `CameraType` to Scriptable is the
	supported way to stand that whole module down (`ActivateCameraController` bails on Scriptable
	and releases its active controller), so we don't fight it, and it takes itself back the moment
	we hand `CameraType` back on RaceEnd.

	How the shot is built. Everything happens in the ROAD's frame — `along` down the drive
	direction, `cross` across it, `y` world-up — which RoadController publishes and which is
	constant for a whole race. On the two horizontal axes we smooth the OFFSET the camera holds
	behind the car and place the shot at (car - offset); height is the one axis smoothed as an
	absolute, because it rides the deck rather than the car. See `restingLag` for why that
	distinction is the whole of this camera's smoothness. Orientation is the road's forward axis,
	swung by `_yaw` about world up, pitched down by CameraConfig.PitchDeg and banked by a couple
	of degrees. Height and pitch both come through `baseHeight`/`basePitchDeg`, which is where the
	CameraConfig.LowChase flag swaps the high chase for the low one.

	The car's CFrame reaches exactly one thing: `_yaw` (via _headingError). Everything else is the
	road frame, which is what keeps this stable while tiles recycle underneath it. Note the chase
	offset is rotated by the same `_yaw` as the orientation — so the camera orbits the car rather
	than sliding it toward the edge of frame, and a swing reads as the WORLD turning with you
	instead of the car drifting off-centre. With CameraConfig.YawFollow at 0 every one of those
	terms collapses to identity and this is bit-for-bit the fixed camera it used to be, which is
	the intended way to A/B anything in that section.

	RoadController snaps the whole world back toward the origin every RebaseThresholdStuds, and
	this camera rides it for free: the two horizontal axes keep an OFFSET rather than a position,
	so a translation that moves the car and the road together moves the shot with them and leaves
	the state untouched. Height is the one absolute left, and a road rebase only ever translates
	ALONG the road, so even that never moves. We still subscribe to `onWorldShift` — see
	_onWorldShift for what's left of it, and why it's kept.

	Two smaller things it has to do by hand, because the stock camera scripts were the ones
	doing them and they've stood down:
	  • Humanoid.CameraOffset — ObstacleController's hit shake. See _shakeOffset.
	  • CameraSubject — restored on release, because by then the seat it points at is being
	    destroyed with the car.

	And one it deliberately doesn't: there's no occlusion in the stock sense (no Popper, no
	Invisicam). The camera sits over the deck behind the car, so nothing standing ON a road tile
	gets between them. What the tiles do have is things overhead, and that is a different problem
	with its own answer: see `_stepCover`, which ducks the whole shot under a bridge instead of
	dragging it in toward the car.

	Lifecycle rides the same race remotes everything else does. RaceWrecked is NOT a release, and it
	is not a change of subject either: holding this shot on the CAR is what frames it coasting to a
	stop under the WRECKED banner, with the driver arcing out over the bonnet in front of it. There
	is a shot that swings onto the body instead (`_thrownSubject`, off an attribute rather than off
	the remote) and it is switched off — CameraConfig.Downed.FramesThrownRider says why.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shard = require(ReplicatedStorage.Packages.Shard)
--- For the first-person toggle key alone: the key is a developer's A/B switch, not a control.
--- The kit's navy, for the VIEW button's disc (`_buildViewButton`).
local ArcadeKit = require(ReplicatedStorage.shared.Modules.ArcadeKit)
local CameraConfig = require(ReplicatedStorage.shared.Configs.CameraConfig)
--- For `PositiveSteerIsLeft` alone, so the first-person look-into-turn and the cockpit's wheel read
--- the steer in road terms (+ = left) whatever sign the rig steers in. Same reading `DriveController`
--- does at its top.
local DriveConfig = require(ReplicatedStorage.shared.Configs.DriveConfig)
local RaceConfig = require(ReplicatedStorage.shared.Configs.RaceConfig)
--- The dash, wheel and arms drawn over the world while first person has the shot.
local FirstPersonCockpit = require(ReplicatedStorage.shared.Modules.FirstPersonCockpit)
--- `Cabin.DashWhenUnbaked`: a car with no baked cabin is driven behind the drawn dash (`_step`).
local CockpitConfig = require(ReplicatedStorage.shared.Configs.CockpitConfig)
--- The car's own steering wheel in the same shot: turned, hidden or left alone.
local FirstPersonWheel = require(ReplicatedStorage.shared.Modules.FirstPersonWheel)
local FirstPersonCabin = require(ReplicatedStorage.shared.Modules.FirstPersonCabin)
--- For `StudsPerMaxSpeed` alone: the chassis attribute is not in studs/s, and that
--- conversion is measured and documented there. One number, two readers (see `_step`).
local WindConfig = require(ReplicatedStorage.shared.Configs.WindConfig)
local TimeScale = require(ReplicatedStorage.shared.Modules.TimeScale)

local RaceCameraController = Shard.new("RaceCameraController"):withDependencies({ "RoadController" })

-- BindToRenderStep unbinds by name, so this is one shared name for the session.
local RENDER_NAME = "RaceCamera"
-- One past the priority the stock camera update runs at. With CameraType Scriptable that module
-- isn't writing anything anyway, but ordering after it means that on any frame where something
-- does, ours is still the write that lands.
local RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 1

--- Sign that turns `DriveController:getSteerInput()` into road terms, + = left.
local STEER_LEFT = if DriveConfig.PositiveSteerIsLeft then 1 else -1
--- How often the first-person hide re-sweeps the character and the car for parts that arrived late
--- (an accessory, a door panel streaming in), seconds.
local FP_SWEEP_SECONDS = 0.5
--- How often the first-person eye re-reads the roofline and the wheel top it is placed by, seconds.
local FP_MEASURE_SECONDS = 0.5

-- Exponential approach toward a target that is treated as STATIONARY across the step. Correct
-- for anything that settles (the swing), wrong for anything the car is carrying across the world
-- at speed — see `track`.
local function approach(current: number, target: number, dt: number, gain: number): number
	if gain <= 0 then
		return target -- 0 or negative means "no smoothing", not "never move"
	end
	return current + (target - current) * (1 - math.exp(-dt * gain))
end

--[[ How far behind the car the shot RESTS on one road axis at the speed it's doing: exactly
	v/gain studs, which is the number CameraConfig's gains are documented as producing. A gain of
	zero means welded, not infinitely loose, so it rests at nothing.

	This being a separate quantity — an offset the camera holds, rather than a position it chases —
	is the whole of why this camera is smooth, and it is not a refactor for tidiness. A part's
	RENDERED position is wherever the last PHYSICS step left it, and physics runs at 240Hz while
	frames do not. Measured on the test rig at 86 studs/s and ~130fps, the car's along-road
	position advances in exact 0.359-stud quanta — one, two or three of them per frame, depending
	only on where the frame boundary happens to fall — while `dt` varies continuously with frame
	pacing. Any filter carrying the car's ABSOLUTE position in its state carries that mismatch
	into the shot: the camera glides, the car steps, and the difference is the car creeping a
	tenth of a stud forward for a few frames and snapping back. Measured that way: 0.13 studs of
	fore-aft judder, 0.44 worst case, with no slow component at all (a 0.2s average of the gap is
	flat to 0.16 studs over 12 seconds — it is entirely per-frame).

	Smoothing the offset instead makes the car's position cancel out of the state exactly: the
	camera sits at (car - lag) every frame, so it steps WITH the car, and the only thing driving
	the filter is the car's velocity — a clean signal, 0.002 studs/s of frame-to-frame noise at
	cruise against 0.359 studs of position quantum. Same measurement afterwards: 0.008 studs, a
	17x drop, and the residue is the honest lateral lag moving. The stepping lands on the world
	instead, which is where every stock Roblox camera puts it (they are welded to a subject that
	steps the same way) and where the eye is not looking.

	It is NOT a different filter. Feeding this to `approach` at the same gain integrates
	dlag/dt = v - gain*lag, which is exactly what smoothing the position produced, so the lag
	still settles at precisely v/gain, every tuning number in CameraConfig keeps its meaning, and
	a real change of speed — a hit, the brake, boost coming on — still arrives as the same lagged
	surge in frame.

	`vel` is MEASURED, not differenced. The obvious implementation reads the car's velocity as
	(pos - lastPos)/dt, and that reintroduces exactly what this is here to remove: it is the
	quantized position divided by a small mismatched dt, which is noisier than the effect being
	corrected. The engine already knows the answer — AssemblyLinearVelocity, projected onto
	whichever axis is being followed — so we ask it instead of estimating it. ]]
local function restingLag(vel: number, gain: number): number
	return if gain > 0 then vel / gain else 0
end

--[[ The base shot, after `CameraConfig.LowChase`. Read through these two rather than rewriting the
	config at load, so `Height` and `PitchDeg` keep saying what the high chase is and flipping the
	flag off is the whole of going back to it. Everything else about the shot (distance, FOV, the
	gains, the swing) is the same either way. ]]
local function baseHeight(): number
	local low = CameraConfig.LowChase
	return if low.Enabled then low.Height else CameraConfig.Height
end

local function basePitchDeg(): number
	local low = CameraConfig.LowChase
	return if low.Enabled then low.PitchDeg else CameraConfig.PitchDeg
end

-- === Game feel springs =======================================================

--[[ One damped spring toward zero, advanced with the EXACT underdamped solution rather than an
	integrator: an Euler step bleeds energy at these frequencies (measured ~12% short of the configured
	peak), and the exact form is frame-rate independent at any dt. A punch is a velocity added to it and
	the spring brings it home. Damping is clamped under 1 so the closed form always applies. ]]
local function stepSpring(x: number, v: number, dt: number): (number, number)
	local cfg = CameraConfig.Juice.Spring
	local omega = 2 * math.pi * cfg.Frequency
	local zeta = math.clamp(cfg.Damping, 0.05, 0.99)
	local wd = omega * math.sqrt(1 - zeta * zeta)
	local h = math.min(dt, 0.1)
	local decay = math.exp(-zeta * omega * h)
	local c, s = math.cos(wd * h), math.sin(wd * h)
	local nx = decay * (x * c + (v + zeta * omega * x) / wd * s)
	local nv = decay * (v * c - (omega * omega * x + zeta * omega * v) / wd * s)
	return nx, nv
end

--[[ The velocity to hand a resting spring so that it PEAKS at `peak`. Config speaks in peaks because
	that is what anyone tuning it can see; this is the closed form for an underdamped spring released
	from rest at zero. Critically or over-damped springs fall back to a close approximation. ]]
local function impulseFor(peak: number): number
	local cfg = CameraConfig.Juice.Spring
	local omega = 2 * math.pi * cfg.Frequency
	local zeta = math.clamp(cfg.Damping, 0.05, 0.99)
	local s = math.sqrt(1 - zeta * zeta)
	local t = math.atan2(s, zeta) / (omega * s)
	local shape = math.exp(-zeta * omega * t) * math.sin(omega * s * t) / (omega * s)
	return peak / math.max(shape, 1e-6)
end

--- For the steal's punches alone (`stealPunch`). A config, so no cycle with `StealController`.
local StealJuiceConfig = require(ReplicatedStorage.shared.Configs.StealJuiceConfig)

local function juiceScale(): number
	local juice = CameraConfig.Juice
	return if juice.Enabled then math.max(juice.Scale, 0) else 0
end

-- === Heading =================================================================

--[[ The car's VehicleSeat, cached. The seat rather than the model's PrimaryPart because the seat
	is the part guaranteed to face the way the car drives — it's the same thing DriveController
	reads a heading off, so the two can't disagree about which way the nose points. Re-resolved
	whenever the cached one stops belonging to the car we're framing, which covers respawns and
	the gap between races. ]]
function RaceCameraController._seatFor(self, car: Model): VehicleSeat?
	local seat = self._seat
	if seat and seat.Parent and seat:IsDescendantOf(car) then
		return seat
	end
	seat = car:FindFirstChild("VehicleSeat", true)
	if seat and seat:IsA("VehicleSeat") then
		self._seat = seat
		return seat
	end
	self._seat = nil
	return nil
end

--[[ Signed angle between the car's nose and the road's drive direction, radians, positive = the
	nose is pointed LEFT of the road. Same quantity DriveController measures its steering cone
	against, so a swing here and a limit there are talking about the same number.

	`left` is RoadController's `cross`, which it derives as Y x forward — i.e. it already IS the
	road's left, and that's what makes the sign work out below: a positive rotation about world +Y
	turns a look vector toward the left, so a positive error and a positive swing agree without a
	correction term.

	Zero — meaning "don't swing" — whenever we can't say: no seat yet, or the nose pointed at the
	sky mid-flip. Both degrade to the fixed camera, which is the safe direction to fail in. ]]
function RaceCameraController._headingError(self, car: Model, forward: Vector3, left: Vector3): number
	local seat = self:_seatFor(car)
	if not seat then
		return 0
	end
	local look = seat.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return 0
	end
	flat = flat.Unit
	return math.atan2(flat:Dot(left), flat:Dot(forward))
end

-- === Orientation =============================================================

--[[ The camera's rotation, plus the horizontal direction it's looking along (which is also the
	direction the chase offset gets measured back down — see _step).

	Built in three steps, deliberately as separate multiplications rather than one CFrame.Angles,
	because each one has to happen in a different frame and the Euler order would decide that for
	us: swing about WORLD up, then pitch in the swung frame, then bank about the pitched LOOK axis.
	A Roblox CFrame's positive X rotation tilts the look vector UP, hence the minus on pitch.

	The bank's sign: rotating about a camera's local +Z tilts its RightVector up toward its
	UpVector, which is a head-tilt to the LEFT — so a positive angle banks into a left turn, and
	`_yaw` is already positive-is-left. CameraConfig.RollDeg documents the flip. ]]
function RaceCameraController._orient(self, forward: Vector3, extraPitchDeg: number): (CFrame, Vector3)
	-- Turn-follow yaw orbits the camera and rotates the lens together. Lane-framing yaw rotates only
	-- the lens back toward the car, preserving the opposite-side camera placement.
	local chaseSwing = CFrame.Angles(0, self._yaw, 0)
	local viewSwing = CFrame.Angles(0, self._yaw + self._frameYaw, 0)
	local basis = viewSwing * self._level * CFrame.Angles(-math.rad(basePitchDeg() + extraPitchDeg), 0, 0)

	local bank, cap = CameraConfig.RollDeg, CameraConfig.YawMaxDeg
	if bank ~= 0 and cap > 0 then
		local t = math.clamp(self._yaw / math.rad(cap), -1, 1)
		basis *= CFrame.Angles(0, 0, math.rad(bank) * t)
	end

	return basis, chaseSwing:VectorToWorldSpace(forward)
end

-- === Hit shake ===============================================================

--[[ ObstacleController's camera shake, honoured by hand.

	It writes `Humanoid.CameraOffset`, and the thing that actually APPLIES that property is the
	stock camera scripts — which have stood down while we own the camera. So a scriptable camera
	that ignored it would silently delete the shake from every obstacle hit, wall scrape and
	wreck. We apply it in camera space (+X screen-right, +Y screen-up, matching how the stock
	module reads it) and as a translation only: a rotational shake would break the one promise
	this camera makes. ]]
function RaceCameraController._shakeOffset(self, speedT: number): CFrame
	local hitOffset = Vector3.zero
	local humanoid = self._humanoid
	if not (humanoid and humanoid.Parent) then
		local character = Players.LocalPlayer.Character
		humanoid = character and character:FindFirstChildOfClass("Humanoid")
		self._humanoid = humanoid
	end
	if humanoid then
		hitOffset = humanoid.CameraOffset
	end

	local strength = self._nitroShake or 0
	local speedConfig = CameraConfig.SpeedShake
	local speedStrength = 0
	if speedConfig.Enabled then
		local span = speedConfig.FullFraction - speedConfig.StartFraction
		if span > 0 then
			speedStrength = math.clamp((speedT - speedConfig.StartFraction) / span, 0, 1)
			speedStrength = speedStrength * speedStrength * (3 - 2 * speedStrength)
		end
	end
	if hitOffset.Magnitude < 1e-3 and strength < 1e-3 and speedStrength < 1e-3 then
		return CFrame.identity
	end

	local config = CameraConfig.NitroShake
	local phase = os.clock() * config.Frequency * math.pi * 2
	local translation = config.Translation * strength
	local nitroOffset = Vector3.new(math.sin(phase) * translation, math.sin(phase * 1.37 + 0.8) * translation * 0.6, 0)
	local roll = math.rad(config.RotationDeg) * strength * math.sin(phase * 0.83 + 1.7)

	-- Separate, lower-frequency phase prevents the normal road vibration from phase-locking to
	-- nitro. Its vertical component is smaller so the horizon does not visibly bounce.
	local speedPhase = os.clock() * speedConfig.Frequency * math.pi * 2
	local speedTranslation = speedConfig.Translation * speedStrength
	local speedOffset = Vector3.new(
		math.sin(speedPhase) * speedTranslation,
		math.sin(speedPhase * 1.23 + 1.1) * speedTranslation * 0.45,
		0
	)
	local speedRoll = math.rad(speedConfig.RotationDeg) * speedStrength * math.sin(speedPhase * 0.79 + 0.4)
	return CFrame.new(hitOffset + nitroOffset + speedOffset) * CFrame.Angles(0, 0, roll + speedRoll)
end

--[[ The player has been thrown out of the car and is lying in the road (RaceService._throwRider).
	Same shape and same shot as a whiffed bail — see `setFlight` for the contract and
	CameraConfig.Downed for why the shot breaks every framing rule above.

	OFF BY DEFAULT, and the switch is the first line of the function: `CameraConfig.Downed
	.FramesThrownRider`, which is where the reasoning lives. Short version — the whiff hides the car
	for that beat and a wreck cannot, so the close shot ends up inside the wreck with the body
	clipped through it. A wreck now keeps the ordinary road shot, which is also what the lifecycle
	note at the top of this file describes.

	NO REMOTE AND NO REGISTRATION. The server sets one attribute on the character, and this pulls it
	once a frame like everything else here; a body on the road is a fact about the world rather than
	a message, and a camera that reads it is a camera that can't be left pointing at a body that
	stood up two seconds ago.

	Returning nil is the safe direction to fail in and covers the whole teardown: the moment the
	attribute goes, or the character does, the shot is back on the car with nothing to unwind. ]]
function RaceCameraController._thrownSubject(self)
	if not CameraConfig.Downed.FramesThrownRider then
		return nil
	end
	local character = Players.LocalPlayer.Character
	if not (character and character:GetAttribute(RaceConfig.RiderThrow.Attribute)) then
		return nil
	end
	local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart") and root.Parent) then
		return nil
	end
	return { position = root.Position, velocity = root.AssemblyLinearVelocity, downed = true }
end

-- === Overhead cover ==========================================================

--[[ Is there a roof over the road ahead of the car? Returns how far above the deck it sits, in
	studs, or nil for open sky.

	ONE RAY, and what makes it cheap is where it STARTS: `RoofMinStuds` above the deck rather than
	on it. Over that line the only things left are bridges, tunnel roofs and the gantries between
	them, because everything that stands ON the road is shorter than it (the tallest obstacle volume
	in the game is 8.4, which is the height TrafficController and GetawayController both probe under
	for this same reason). So the ray never has to work out what it hit, and no tile has to be
	tagged for a map to have bridges.

	The price of that trick is the one case it cannot see. A roof BELOW the line is a roof the ray
	starts inside, and Roblox reports no hit for a part containing the origin, so it would read as
	open sky. The lowest thing over a drive lane in any of the five worlds is FuturisticCity's
	bridge at 17.6 studs; CameraConfig.Cover has the rest of the measurements and the band.

	The filter is the road's own tiles, which is the right set and costs nothing to keep. Cover is
	art and art lives in the tile, so the car, the player and every traffic vehicle are out of it
	without a filter anybody has to maintain, and `getSegments` hands back the live list, so tiles
	arriving and leaving on a recycle need no bookkeeping here either. ]]
function RaceCameraController._roofAhead(self, pos: Vector3, lead: number, info): number?
	local segments = self._road and self._road:getSegments()
	if not (segments and #segments > 0) then
		return nil
	end

	local cfg = CameraConfig.Cover
	local params = self._coverParams
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.IgnoreWater = true
		self._coverParams = params
	end
	-- Re-pointed every probe rather than on a recycle: the list is nine models, and a filter built
	-- from the live one every time can never be the stale half of a tile swap.
	params.FilterDescendantsInstances = segments

	-- The car's own cross position, not the road's centre line, so a roof that only covers half the
	-- deck ducks the shot only while you are actually under it.
	local from = Vector3.new(pos.X, info.deckY + cfg.RoofMinStuds, pos.Z) + info.forward * lead
	local reach = math.max(cfg.RoofMaxStuds - cfg.RoofMinStuds, 0)
	local hit = workspace:Raycast(from, Vector3.yAxis * reach, params)
	return if hit then hit.Position.Y - info.deckY else nil
end

--[[ The duck, advanced one frame. Returns the studs the shot drops and the degrees of down-pitch
	it hands back, both already eased, and both zero on open road.

	THE RUN IS HELD AS AN ALONG-COORDINATE RATHER THAN A TIMER, and that is the whole design. The
	shot sits `Distance` studs BEHIND the car, so it is still under a bridge for that many studs
	after the car has come out the far side, and it is that distance rather than any number of
	seconds that says when the shot may rise. A timer tuned at cruise would pop the camera up
	through the slab in traffic. Each frame the probe sees a roof pushes `_coverUntil` past the far
	side of it, so a run of bridges holds one continuous duck instead of bobbing between them, and
	the rise only starts once the camera itself is out.

	The probe LEADS the car (`Cover.LeadSeconds`), because a duck that starts at the bridge is a duck
	that happens under it. Leading also means the roof the shot fits itself to is the one it is about
	to meet rather than the one it is leaving.

	SUSPENDED MID-BAIL. The flight arc goes over the road rather than under it, and the downed shot
	is already lower than any duck. It eases out rather than cutting, so a bail taken under a bridge
	hands the shot back level. ]]
function RaceCameraController._stepCover(
	self,
	dt: number,
	suspended: boolean,
	carAlong: number,
	pos: Vector3,
	alongVel: number,
	info
): (number, number)
	local cfg = CameraConfig.Cover
	local want = 0
	-- `LowChase` is already this duck, held for the whole race, so there is nothing left to duck to
	-- and a pitch change here would only unsettle the one beat it used to own.
	if cfg.Enabled and not CameraConfig.LowChase.Enabled and not suspended then
		local lead = math.max(cfg.LeadMinStuds, math.abs(alongVel) * cfg.LeadSeconds)
		local roof = self:_roofAhead(pos, lead, info)
		if roof then
			--[[ UNDER the roof, not merely lower than usual. `Cover.Height` is the shot we want and
				it clears every roof in the game as it stands; the clamp is what keeps the camera out
				of the concrete if a map ever ships a lower one, and `MinHeight` is what stops a freak
				measurement burying the shot in the deck. ]]
			local height = math.clamp(math.min(cfg.Height, roof - cfg.Clearance), cfg.MinHeight, baseHeight())
			self._coverDrop = baseHeight() - height
			self._coverUntil = math.max(self._coverUntil, carAlong + lead + CameraConfig.Distance + cfg.TrailStuds)
		end
		if carAlong < self._coverUntil then
			want = 1
		end
	end

	local gain = if want > self._coverT then cfg.EnterGain else cfg.ExitGain
	self._coverT = approach(self._coverT, want, dt, gain)
	if want == 0 and self._coverT < 1e-3 then
		-- Landed. Clearing the run as well as the ease means an exponential that never quite reaches
		-- zero cannot leave the shot a few hundredths of a stud low for the rest of the race.
		self._coverT = 0
		self._coverUntil = -math.huge
	end
	return self._coverDrop * self._coverT, cfg.ExtraPitchDeg * self._coverT
end

-- === Per-frame ===============================================================

function RaceCameraController._step(self, dt: number)
	--- Wall-clock dt, kept past the slow-mo scaling below: the first-person blend and the cockpit's
	--- own motion are beats of the camera, not of the world.
	local realDt = dt
	local camera = workspace.CurrentCamera
	local road = self._road
	local info = road and road:getRoadInfo()
	local car = road and road:getCar()
	local primary = car and car.PrimaryPart

	--[[ Nothing to frame. That's the first moments of a race (the car and the local road are
		still arriving) and the last (the car has been destroyed on the way back to the lobby).
		Both sit behind RaceUIController's fade, so we leave the camera exactly as we found it
		rather than snapping it anywhere: before we've engaged that means the stock camera is
		still running, and after we have it means holding the last shot. ]]
	if not (camera and info and primary and primary.Parent) then
		return
	end

	local forward, cross = info.forward, info.cross
	-- Degenerate only if a road tile declares a vertical ForwardAxis, which would have broken
	-- RoadController long before it got here. Warned once, then we stay out of the way.
	if cross.Magnitude < 0.5 then
		if not self._warnedBasis then
			self._warnedBasis = true
			self.log:warn("Road forward axis is vertical; cannot build a camera basis.")
		end
		return
	end

	--[[ Road-frame coordinates. (forward, cross, Y) is orthonormal — RoadController derives
		cross as Y x forward from an axis-aligned forward — so a position's dot products onto
		the three axes are its coordinates in that frame, and scaling the axes by coordinates
		reconstructs a world position exactly (see the CFrame build below). ]]
	local pos = primary.Position
	-- The car's live velocity, which `track` needs in the same frame the positions are measured
	-- in. Read once: it's the same vector every axis below projects out of.
	local velocity = primary.AssemblyLinearVelocity

	--[[ FLIGHT MODE. The player has bailed, so the subject is the flight avatar rather than the car
		— and both its position AND its velocity come from StealController, because the avatar is
		anchored and an anchored assembly reports zero velocity (see CameraConfig.Flight).

		Everything downstream of these two lines is unchanged: same road frame, same lag filter,
		same gains. That's the point — the shot doesn't become a different shot mid-bail, it just
		follows a different thing, sits a little further back and looks a little further down. ]]
	local flight = (self._flight and self._flight()) or self:_thrownSubject()
	if flight then
		pos = flight.position
		velocity = flight.velocity
	end

	-- Speed along the road, as a 0..1 ramp. Drives both cosmetic speed reactions.
	local alongVel = velocity:Dot(forward)
	--[[ How fast this car is going AS A SHARE OF WHAT IT CAN DO — see the Speed block in
		`CameraConfig` for why this is a fraction and not the stud/s constant it used to be.

		A car with no ceiling to measure against reads 0 rather than guessing one. That is the
		honest answer for the two frames before `DriveController` has resolved the rig, and it means
		the shot opens from its resting pose instead of snapping back to it once the number
		arrives. ]]
	local speedT = 0
	local speedFraction = 0
	local dial = self._drive and self._drive:getTopSpeed()
	if dial then
		--- The chassis attribute is not in studs/s; `WindConfig` owns that conversion and the note
		--- on how it was measured. Read from there rather than copied, so the streaks and the shot
		--- can never disagree about how fast "flat out" is.
		local top = dial * WindConfig.StudsPerMaxSpeed
		if top > 0 then
			speedFraction = math.clamp(alongVel / top, 0, 1)
		end
		local start = top * CameraConfig.SpeedStartFraction
		local span = top * CameraConfig.SpeedFullFraction - start
		if span > 0 then
			speedT = math.clamp((alongVel - start) / span, 0, 1)
		end
	end

	--[[ The point the shot is tracking: the CAR, in road-frame coordinates. This used to be the
		camera's own resting place (the chase distance already subtracted), which was equivalent
		while the shot couldn't rotate. It can now, and the offset has to be rotated with it — so
		we track where the car is and subtract the swung offset afterwards. Read live every frame
		and never stored: it's the follow LAG that's smoothed, not this (see `restingLag`). ]]
	local wantAlong = pos:Dot(forward)

	local carCross = pos:Dot(cross)
	local wantCross = carCross
	-- Above 1 isn't a thing, so the target is simply the car and it moves at the car's own
	-- cross-road speed; the blend below scales both the point and its velocity by the same share.
	local follow = math.min(CameraConfig.LateralFollow, 1)
	if follow < 1 then
		-- Hang back toward the road's centre line, so the car ranges across the frame instead.
		wantCross = info.driveCenter + (carCross - info.driveCenter) * follow
	end
	local crossVel = velocity:Dot(cross) * follow

	-- Aim back across the composition gap: at the left edge the camera remains closer to centre
	-- (therefore right of the car) and looks left toward it; the signs reverse on the other edge.
	-- Flight returns to a centred lens because its subject is already moving freely across the shot.
	local wantFrameYaw = 0
	if not flight then
		local framing = CameraConfig.LaneFraming
		local honest = math.atan2(carCross - wantCross, math.max(CameraConfig.Distance, 1e-3))
		local cap = math.rad(framing.MaxYawDeg)
		wantFrameYaw = math.clamp(honest * framing.AimStrength, -cap, cap)
	end

	--[[ Height rides the deck, not the car, so suspension and road noise can't jitter the shot —
		plus a capped fraction of any real air time, which keeps a jump in frame. In flight that
		share goes up hard, because there the height is the whole event rather than suspension bob.

		Downed is the exception to all of it: a body on the road has no air time worth following, so
		the shot simply sits low over the deck and looks down at it (CameraConfig.Downed). ]]
	local wantY
	if flight and flight.downed then
		wantY = info.deckY + CameraConfig.Downed.Height
	else
		local jumpFollow, maxAir = CameraConfig.JumpFollow, CameraConfig.MaxJumpFollowStuds
		if flight then
			jumpFollow, maxAir = CameraConfig.Flight.JumpFollow, CameraConfig.Flight.MaxFollowStuds
		end
		local air = math.clamp(pos.Y - info.deckY, 0, maxAir)
		wantY = info.deckY + baseHeight() + air * jumpFollow
	end

	--[[ How far into the turn the shot wants to be. Capped before it's smoothed, so the cap is a
		limit on the shot itself rather than on how fast it gets there.

		Zero in flight, and that's a decision rather than an omission: the swing exists to sell the
		CAR's heading, and mid-bail the car is hidden and pointed nowhere in particular. Easing to
		level gives the arc a stable frame to be read against, which is what the ground marker needs
		to mean anything. ]]
	local wantYaw = 0
	if not flight and CameraConfig.YawFollow > 0 and CameraConfig.YawMaxDeg > 0 then
		local cap = math.rad(CameraConfig.YawMaxDeg)
		local err = self:_headingError(car, forward, cross)
		wantYaw = math.clamp(err * CameraConfig.YawFollow, -cap, cap)
	end

	--[[ FIRST PERSON (CameraConfig.FirstPerson). Decided here, before the engage block, so a race
		that starts with the flag on starts IN the car rather than swooping in from the chase. The
		chase shot below is still computed on every frame it is not showing, which is what lets the
		blend out of the cockpit (a bail, a wreck, the toggle) land on a shot whose lags are already
		settled. ]]
	local fpWant, fpSeat = self:_firstPersonWanted(car, flight)

	if not self._engaged then
		-- First frame with a car: take the camera, and start already in position rather than
		-- flying in from wherever the stock camera left us.
		self._engaged = true
		self._savedType = camera.CameraType
		self._savedFov = camera.FieldOfView
		self._forward = forward
		self._level = CFrame.lookAt(Vector3.zero, forward)
		self._alongLag = restingLag(alongVel, CameraConfig.AlongGain)
		self._crossLag = restingLag(crossVel, CameraConfig.LateralGain)
		self._y = wantY
		self._yaw = wantYaw
		self._frameYaw = wantFrameYaw
		self._speedT = speedT
		self._speedFraction = speedFraction
		self._fpBlend = if fpWant then 1 else 0
	elseif forward ~= self._forward then
		-- A race can't change the road's axis mid-run, but rebuilding on change is cheaper than
		-- assuming it never will.
		self._forward = forward
		self._level = CFrame.lookAt(Vector3.zero, forward)
	end

	--[[ The two axes the car is actually covering ground on follow it by a smoothed LAG rather
		than a smoothed position — see `restingLag`, which is the one thing in this file worth
		reading before changing anything here. Along is where it matters most, because it's the
		fastest axis and so the one with the coarsest position quantum; cross is the same mechanism
		at a third of the speed, and running both the same way keeps CameraConfig's lateral lag
		honest as an actual distance. ]]
	--[[ Slow motion (Modules/TimeScale), applied to the smoothing only.

		The gains keep their meaning — a lag still SETTLES at v/gain studs — the shot just takes
		longer to get there, which is exactly what a slowed world should do to a camera. It goes
		here rather than at the top of `_step` on purpose: the resting targets above are computed
		from live positions and velocities, and those are already slowed at their source (the
		flight arc integrates on scaled time, and so does traffic). Scaling them twice would make
		the camera lag a world that had already stopped moving. ]]
	-- The feel springs run on REAL time, before the slow-mo scale below: a punch that landed just
	-- before a bail should finish on the beat it started on, not stretch out over the flight.
	self:_stepJuice(dt, if flight then 0 else velocity:Dot(cross))

	-- One filtered speed signal drives FOV, pullback and road vibration. Nitro retains its own
	-- asymmetric easing in NitroController, but now composes with a stable base camera.
	self._speedT = approach(self._speedT, speedT, dt, CameraConfig.SpeedResponse)
	self._speedFraction = approach(self._speedFraction, speedFraction, dt, CameraConfig.SpeedResponse)
	self._frameYaw = approach(self._frameYaw, wantFrameYaw, dt, CameraConfig.LaneFraming.YawGain)
	self._flightBlend = approach(
		self._flightBlend or 0,
		if flight and not flight.downed then 1 else 0,
		dt,
		CameraConfig.Flight.BlendResponse
	)
	speedT = self._speedT
	speedFraction = self._speedFraction

	dt *= TimeScale.get()

	self._alongLag = approach(self._alongLag, restingLag(alongVel, CameraConfig.AlongGain), dt, CameraConfig.AlongGain)
	self._crossLag =
		approach(self._crossLag, restingLag(crossVel, CameraConfig.LateralGain), dt, CameraConfig.LateralGain)

	--[[ Height and the swing are smoothed as absolutes, deliberately.

		Neither is chasing the car. `wantY` rides the DECK — a constant, plus a capped share of any
		real air time — so it carries none of the car's position quantum to begin with, and the
		softness of HeightGain exists to keep suspension bob out of the shot rather than to follow
		anything. The swing is a small bounded angle settling toward wherever the nose is, and
		YawGain's lag is the deliberate one it documents. Measured: 0.003 studs and 0.005 degrees
		of frame-to-frame jitter respectively, i.e. nothing. ]]
	self._y = approach(self._y, wantY, dt, CameraConfig.HeightGain)
	self._yaw = approach(self._yaw, wantYaw, dt, CameraConfig.YawGain)

	--[[ Bridges and tunnel roofs. The duck rides ON TOP of the height filter rather than inside it,
		and that is deliberate: `self._y` goes on meaning "where the shot rides over the deck" with
		HeightGain's softness intact, and the duck keeps its own, much more decisive ease. Feeding a
		step this size through a gain tuned to hide suspension bob would arrive under the bridge a
		beat after the bridge did. ]]
	local coverDrop, coverPitch = self:_stepCover(dt, flight ~= nil, wantAlong, pos, alongVel, info)
	local debug = CameraConfig.Debug
	local now = os.clock()
	if debug.Enabled and now >= self._debugAt then
		self._debugAt = now + debug.SampleInterval
		camera:SetAttribute("CameraDebugTargetYawDeg", math.deg(wantYaw + wantFrameYaw))
		camera:SetAttribute("CameraDebugActualYawDeg", math.deg(self._yaw + self._frameYaw))
		camera:SetAttribute("CameraDebugLaneFrameYawDeg", math.deg(self._frameYaw))
	end

	-- Re-asserted every frame rather than once on engage: this is the property that keeps the
	-- stock VehicleCamera stood down, so anything that flips it back costs us one frame instead
	-- of the rest of the race.
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	--[[ THE CINEMATIC (`setCinematic`), asked once per frame, before the lens, because it blends both
		the lens and the shot. Nil or weight 0 is the ordinary camera to the last digit. ]]
	local cine = self._cinematic and self._cinematic()
	local cineWeight = if cine then math.clamp(cine.weight or 0, 0, 1) else 0

	local baseFov = CameraConfig.FieldOfView
	--- The lens this frame, written ONCE at the bottom after first person and the cinematic have had
	--- their say. Nil leaves whatever the player had, as `FieldOfView = nil` promises.
	local fov: number? = nil
	if baseFov then
		-- Speed's own push, plus whatever anything else has asked for on top (`addFov`). Summed
		-- here rather than written by the asker, because this is the only line in the game allowed
		-- to touch FieldOfView during a race and two writers would flicker against each other at
		-- render rate.
		fov = baseFov
			+ CameraConfig.SpeedFovDeg * speedT
			+ (self._extraFov or 0)
			+ (self._flowFov or 0)
			+ self._punchFov
	end

	--[[ Place the shot: the car's live position less this frame's follow lag, then back down the
		direction the camera is looking. `chase` is horizontal (a Y-rotation of a horizontal axis),
		so the swing orbits the camera around the car without touching its height — `self._y` stays
		the only thing deciding that. ]]
	local flightBlend = self._flightBlend or 0
	local extraPitch = CameraConfig.Flight.ExtraPitchDeg * flightBlend
	local back = CameraConfig.Distance
		+ CameraConfig.SpeedPullbackStuds * speedT
		+ CameraConfig.Flight.ExtraDistance * flightBlend
	if flight and flight.downed then
		-- An absolute distance, not an adjustment: this shot is about the body, and the speed
		-- pullback would drag the camera back out to road-framing distance exactly when the point
		-- is to be close to it.
		extraPitch, back = CameraConfig.Downed.ExtraPitchDeg, CameraConfig.Downed.Distance
	end
	local basis, chase = self:_orient(forward, extraPitch + coverPitch)
	local position = forward * (wantAlong - self._alongLag)
		+ cross * (wantCross - self._crossLag)
		+ Vector3.yAxis * (self._y - coverDrop)
		- chase * back
	local live = (basis + position)
		* CFrame.Angles(-math.rad(self._punchPitch), 0, math.rad(self._punchRoll + self._laneRoll))
		* self:_shakeOffset(if flight then 0 else speedFraction)
	local final = self:_applyHold(live)

	--[[ First person rides between the chase shot and the cinematic: it replaces the chase (blended,
		so entering and leaving are a move rather than a cut) and the steal's directed shot still
		blends over the top of it exactly as it does over the chase. ]]
	local fp = CameraConfig.FirstPerson
	if fpWant and fpSeat and (not self._fpOn or self._fpCar ~= car) then
		self:_enterFirstPerson(car, fpSeat)
	elseif not fpWant and self._fpOn then
		self:_leaveFirstPerson()
	end
	self._fpBlend = approach(self._fpBlend, if fpWant then 1 else 0, realDt, fp.BlendResponse)
	if self._fpBlend < 1e-3 then
		self._fpBlend = 0
	end
	local fpBlend = self._fpBlend
	local anchorSeat = self._fpSeat
	local anchorCar = self._fpAnchorCar
	if fpBlend > 0 and anchorSeat and anchorSeat.Parent and anchorCar and anchorCar.Parent then
		if self._fpOn then
			self:_fpSweep(now)
		end
		local fpShot, fpFov = self:_firstPersonShot(anchorCar, anchorSeat, realDt, speedT, speedFraction)
		final = final:Lerp(fpShot, fpBlend)
		local from = fov or camera.FieldOfView
		fov = from + (fpFov - from) * fpBlend
	elseif fpBlend > 0 then
		-- The car went away under a fade (the ride home). Nothing to anchor to, so the chase has it.
		self._fpBlend = 0
		fpBlend = 0
	end

	if cine and cineWeight > 0 then
		--- The punches ride the directed shot too, so the landing's hit still lands in the close-up.
		local punched = cine.cframe * CFrame.Angles(-math.rad(self._punchPitch), 0, math.rad(self._punchRoll))
		final = final:Lerp(punched, cineWeight)
		if fov and type(cine.fov) == "number" then
			fov += (cine.fov + self._punchFov - fov) * cineWeight
		end
	end
	if fov and math.abs(camera.FieldOfView - fov) > 0.01 then
		camera.FieldOfView = fov
	end
	camera.CFrame = final

	--[[ The car's own wheel, read off the real part in this same render step so it cannot lag the
		lens. Decided every frame from the live config, so the overlay toggle swaps one wheel for the
		other mid-shot. ]]
	-- The rarity dash is drawn for everyone with `Cockpit` on, and for a car with no baked cabin
	-- (`CockpitConfig.Cabin.DashWhenUnbaked`); either way the car's own wheel steps aside for it.
	local cabin = self._fpCabin
	local drawDash = fp.Cockpit
		or (fp.Cabin and CockpitConfig.Cabin.DashWhenUnbaked and cabin ~= nil and not cabin:hasSkin())
	local wheel = self._fpWheel
	if wheel then
		local mode: FirstPersonWheel.Mode = if drawDash then "hide" elseif fp.TurnSteeringWheel then "turn" else "show"
		wheel:update(mode, self:_roadSteer(), realDt)
	end
	-- The black cabin, off the same live seat in the same step, for the same reason.
	if cabin and anchorSeat and anchorSeat.Parent and anchorCar and anchorCar.Parent then
		cabin:update(self:_eyeOffset(anchorCar, anchorSeat), fpBlend, fp.Cabin, fp.CabinDetail, realDt)
	end
	-- The cockpit draws the rarity dash with its wheel, or only the arms on the car's own wheel, or
	-- nothing (no overlay, and no wheel of the car's for the hands to hold).
	local drawArms = fp.Hands and (drawDash or wheel ~= nil)
	if (drawDash or drawArms) and self._fpOn and self._fpCockpitCar ~= self._fpCar then
		self:_setupCockpit(self._fpCar)
	end

	--[[ The cockpit, told where the camera ended up and where the eye is. It fades with the blend, so
		a bail pulls the camera out through a dash that is already going. It is anchored to the car's
		FULL rotation while the lens takes `TiltShare` of it: the dash is the car and the camera is
		the head. ]]
	local cockpit = self._cockpit
	if cockpit then
		local alpha = if drawDash or drawArms then fpBlend else 0
		if alpha > 0.01 and anchorSeat and anchorSeat.Parent and anchorCar and anchorCar.Parent then
			local eyeFrame = anchorSeat.CFrame * CFrame.new(self:_eyeOffset(anchorCar, anchorSeat))
			cockpit:update({
				camera = final,
				frame = eyeFrame,
				steer = self:_roadSteer(),
				speed = speedFraction,
				fov = camera.FieldOfView,
				alpha = alpha,
				dt = realDt,
				car = anchorCar,
				dash = drawDash,
				arms = drawArms,
				hold = if not drawDash and wheel then wheel:hold(eyeFrame) else nil,
			})
		else
			cockpit:hide()
		end
	end
end

-- === First person ============================================================

--[[ Is the view from the seat the shot this frame? Only with the flag on, only out of flight, and
	only while the player is actually IN the car's seat: a bail, a wreck's throw and the gap between
	leaving one car and landing in the next all hand the shot back to the chase, which is the right
	camera for all three. The seat it answers with is the one the eye is anchored to. ]]
function RaceCameraController._firstPersonWanted(self, car: Model, flight): (boolean, VehicleSeat?)
	local fp = CameraConfig.FirstPerson
	if not fp.Enabled or flight then
		return false, nil
	end
	--[[ Back to the chase shot once the run is banked (2026-10-14, the owner: "so we're not seeing
		the inside of the getaway van"): the car rides the truck out with the driver still seated, and
		the lens in the seat looks at the van's walls. The blend out is the ordinary one. ]]
	local getaway = Shard.get("GetawayController")
	if getaway and getaway:isBanked() then
		return false, nil
	end
	local seat = self:_seatFor(car)
	if not seat then
		return false, nil
	end
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid.SeatPart == seat) then
		return false, nil
	end
	return true, seat
end

--- The player's steering in road terms, + = left, for the eyes and the cockpit's wheel.
function RaceCameraController._roadSteer(self): number
	local drive = self._drive
	if not drive then
		return 0
	end
	return math.clamp(drive:getSteerInput() * STEER_LEFT, -1, 1)
end

--[[ Where the eye sits in the SEAT's frame. `CameraConfig.FirstPerson.EyeHeight`, unless the car's
	roofline is close enough that the eye would be in it, in which case it ducks to `RoofClearance`
	under the body's bounding-box top; and never less than `OverWheel` over the top of the car's own
	steering wheel, which wins over the roof because a lens under the rim sees no road. The roofline
	is only read on a frame where the car is level, because a bounding box read on a car mid-bounce
	is tilted with it. The wheel is welded to the seat's assembly, so its top in the seat's frame
	needs no such care. ]]
function RaceCameraController._eyeOffset(self, car: Model, seat: BasePart): Vector3
	local fp = CameraConfig.FirstPerson
	--[[ Both are re-read every `FP_MEASURE_SECONDS`, not once per car: a car that has just spawned
		with first person already on is measured before its body has settled on the chassis (the GT
		read its wheel top at -1.36 over the seat, 3.3 studs under where it ends up), and a reading
		taken then would hold the eye in the wrong place for the whole race. ]]
	local now = os.clock()
	local roof = self._fpRoof
	if not (roof and roof.car == car) or now - roof.at > FP_MEASURE_SECONDS then
		if seat.CFrame.UpVector.Y > 0.98 then
			local body = car:FindFirstChild("Body")
			if body and body:IsA("Model") then
				local cf, size = body:GetBoundingBox()
				roof = { car = car, top = (cf.Position.Y + size.Y / 2) - seat.Position.Y, at = now }
				self._fpRoof = roof
			end
		end
		if roof and roof.car ~= car then
			roof = nil
		end
	end
	local rim = self._fpRim
	if not (rim and rim.car == car) or now - rim.at > FP_MEASURE_SECONDS then
		local wheel = FirstPersonWheel.find(car)
		rim = { car = car, top = if wheel then FirstPersonWheel.topIn(wheel, seat) else nil, at = now }
		self._fpRim = rim
	end
	local height = fp.EyeHeight
	if roof then
		height = math.min(height, roof.top - fp.RoofClearance)
	end
	if rim.top then
		height = math.max(height, rim.top + fp.OverWheel)
	end
	height = math.max(height, fp.MinEyeHeight)
	return Vector3.new(fp.EyeSide, height, -fp.EyeForward)
end

--[[ The shot from the seat. The eye rides the seat exactly (no lag on position, or the cockpit and
	the pillars would come apart); the HEADING lags the car's by `HeadingGain`; the slow part of the
	chassis's roll and pitch comes through at `TiltShare`; the eyes turn `LookIntoTurnDeg` toward the
	steer and look down `PitchDownDeg` at the road. Then the same springs and hit-stop as the chase,
	less the lane lean, which is a third-person garnish for a roll the body is already doing in front
	of you, and the chase's shakes turned into turns of the lens (`_fpShake`).

	=== WHY EVERY FILTER HERE IS AN OFFSET OFF THE LIVE SEAT (2026-10-13) =========================

	The cabin is drawn where the LAST PHYSICS STEP left it. Physics runs at 240Hz and frames do not,
	so the car's heading advances in uneven quanta: measured through a steady lane change at ~85fps,
	0.30, 0.65, 0.50, 0.30 degrees on consecutive frames, at a constant steer. The first version of
	this shot smoothed the heading and the tilt as ABSOLUTES, so the camera glided while the cabin
	stepped, and the difference was the whole car shaking in front of the lens: 0.09 degrees of
	frame-to-frame cabin jitter on average, 0.44 peaks, in yaw and roll alike.

	The chase camera met the same thing in position and its answer is `restingLag` (read that
	header). This is the same answer in rotation: the lens is bolted to the live seat, and the head's
	lag is an OFFSET off it, computed from smooth signals (the car's angular velocity, a low-passed
	tilt) that carry none of the quantum. The cabin cannot shake against the lens because the only
	things between them are smooth; what the quantum does now is step the world a hair, exactly as
	it already does for position, which is the trade the chase made too. ]]
function RaceCameraController._firstPersonShot(
	self,
	car: Model,
	seat: BasePart,
	dt: number,
	speedT: number,
	speedFraction: number
): (CFrame, number)
	local fp = CameraConfig.FirstPerson
	local seatCF = seat.CFrame
	local eye = seatCF:PointToWorldSpace(self:_eyeOffset(car, seat))

	local look = seatCF.LookVector
	local seatFlat = Vector3.new(look.X, 0, look.Z)
	local live = if seatFlat.Magnitude > 1e-3 then seatFlat.Unit else (self._fpLook or -Vector3.zAxis)

	--[[ The head's lag behind the car's heading, as an angle off the LIVE heading. It rests at
		yawRate / HeadingGain, which is the lag the old smoothed heading settled at in a steady turn,
		so the feel is the same and the quantum is gone. An anchored car (a freeze, a hold) reports
		the velocity it had when it stopped, so it is read as not turning. ]]
	local yawRate = 0
	local root = seat.AssemblyRootPart
	if root and not root.Anchored then
		yawRate = seat.AssemblyAngularVelocity.Y
	end
	local wantLag = if fp.HeadingGain > 0 then yawRate / fp.HeadingGain else 0
	local maxLag = math.rad(fp.MaxHeadingLagDeg)
	self._fpYawLag = approach(self._fpYawLag, math.clamp(wantLag, -maxLag, maxLag), dt, fp.HeadingGain)
	local flat = CFrame.Angles(0, -self._fpYawLag, 0):VectorToWorldSpace(live)
	self._fpLook = flat

	--[[ The tilt. The body's roll and pitch off its own heading, all of it, so the cabin is steady in
		frame; then the SLOW part of it (low-passed at `TiltGain`) is taken back off by 1 - TiltShare,
		which is the head levelling a lean. Suspension wobble and the physics quantum are fast, so they
		stay with the cabin and the world takes them, as it would through a helmet. ]]
	local tilt = CFrame.identity
	if seatFlat.Magnitude > 1e-3 then
		local yawOnly = CFrame.lookAlong(Vector3.zero, live)
		local pitch, _, roll = (yawOnly:Inverse() * seatCF.Rotation):ToEulerAnglesYXZ()
		if not self._fpSlowTilt then
			self._fpSlowTilt = Vector2.new(pitch, roll)
		end
		local slow = self._fpSlowTilt
		slow = Vector2.new(approach(slow.X, pitch, dt, fp.TiltGain), approach(slow.Y, roll, dt, fp.TiltGain))
		self._fpSlowTilt = slow
		local level = 1 - math.clamp(fp.TiltShare, 0, 1)
		tilt = CFrame.fromEulerAnglesYXZ(pitch - slow.X * level, 0, roll - slow.Y * level)
	end

	self._fpLookYaw = approach(self._fpLookYaw, math.rad(fp.LookIntoTurnDeg) * self:_roadSteer(), dt, fp.LookGain)

	local shot = CFrame.lookAlong(eye, flat)
		* tilt
		* CFrame.Angles(0, self._fpLookYaw, 0)
		* CFrame.Angles(-math.rad(fp.PitchDownDeg + self._punchPitch), 0, math.rad(self._punchRoll))
		* self:_fpShake(speedFraction)
	local fov = fp.FieldOfView + fp.SpeedFovDeg * speedT + (self._extraFov or 0) + (self._flowFov or 0) + self._punchFov
	return shot, fov
end

--[[ The chase's shakes (a hit's `CameraOffset`, nitro, road speed), for the lens in the seat. They
	are written as TRANSLATIONS, which from 24 studs back is a nudge of the whole picture; in the seat
	the same move swings the eye about inside the cabin, a heavy hit's stud and a half of it straight
	through a pillar, and the near cabin moves against the far world: the car shaking, not the view. So each
	sideways or vertical offset becomes the turn of the lens that moves the world by the same angle
	it did in the chase (`ShakeAsTurnAt` studs away). The rolls pass through as they are. ]]
function RaceCameraController._fpShake(self, speedFraction: number): CFrame
	local shake = self:_shakeOffset(speedFraction)
	local offset = shake.Position
	if offset.Magnitude < 1e-5 then
		return shake
	end
	local at = math.max(CameraConfig.FirstPerson.ShakeAsTurnAt, 1)
	return CFrame.Angles(offset.Y / at, -offset.X / at, 0) * shake.Rotation
end

--- Hide `inst` for this client only, remembering what it was so `_leaveFirstPerson` can put it back.
function RaceCameraController._fpHide(self, inst: Instance)
	if not (inst:IsA("BasePart") or inst:IsA("Decal")) then
		return
	end
	local hidden = self._fpHidden
	if hidden[inst] ~= nil then
		return
	end
	hidden[inst] = inst.LocalTransparencyModifier
	inst.LocalTransparencyModifier = 1
end

--[[ Hide what the lens must not see: the player's own character (the camera is inside its head).
	`LocalTransparencyModifier` rather than `Transparency`, because the server owns `Transparency`
	(the race fade, the stock seat script's leg hiding) and this must compose with it and undo
	cleanly. Re-run every `FP_SWEEP_SECONDS` for parts that arrive late. The car's steering wheel is
	`Modules/FirstPersonWheel`'s, not this sweep's, so one owner decides whether it shows. ]]
function RaceCameraController._fpSweep(self, now: number)
	if now < self._fpSweepAt then
		return
	end
	self._fpSweepAt = now + FP_SWEEP_SECONDS
	if CameraConfig.FirstPerson.HideCharacter then
		local character = Players.LocalPlayer.Character
		if character then
			for _, inst in character:GetDescendants() do
				self:_fpHide(inst)
			end
		end
	end
end

--- The rarity cockpit for `car`, built on first use. Called on entering the shot with the overlay on,
--- and from `_step` when the overlay is switched on mid-shot.
function RaceCameraController._setupCockpit(self, car: Model)
	local cockpit = self._cockpit
	if not cockpit then
		cockpit = FirstPersonCockpit.new()
		self._cockpit = cockpit
	end
	cockpit:setCar(car)
	local character = Players.LocalPlayer.Character
	if cockpit._armsFrom ~= character then
		cockpit:setCharacter(character)
	end
	self._fpCockpitCar = car
end

function RaceCameraController._enterFirstPerson(self, car: Model, seat: VehicleSeat)
	if self._fpOn then
		self:_leaveFirstPerson()
	end
	self._fpOn = true
	self._fpCar = car
	self._fpSeat = seat
	self._fpAnchorCar = car
	self._fpLook = nil -- the first frame takes the seat's heading outright
	self._fpYawLag = 0
	self._fpSlowTilt = nil -- the first frame takes the seat's tilt outright
	self._fpSweepAt = 0
	self:_fpSweep(os.clock())
	self._fpWheel = FirstPersonWheel.new(car, seat)
	--- This car's cabin first, in case the background fetch has not reached it yet.
	FirstPersonCabin.warm(car)
	self._fpCabin = FirstPersonCabin.new(car, seat)

	if CameraConfig.FirstPerson.Cockpit then
		self:_setupCockpit(car)
	end
end

--- Put back everything `_enterFirstPerson` hid. The anchor (seat and car) is kept for the fade out;
--- `_release` clears it.
function RaceCameraController._leaveFirstPerson(self)
	if not self._fpOn then
		return
	end
	self._fpOn = false
	self._fpCar = nil
	self._fpCockpitCar = nil
	for inst, previous in self._fpHidden do
		if inst.Parent then
			inst.LocalTransparencyModifier = previous
		end
	end
	table.clear(self._fpHidden)
	local wheel = self._fpWheel
	if wheel then
		self._fpWheel = nil
		wheel:destroy()
	end
	local cabin = self._fpCabin
	if cabin then
		self._fpCabin = nil
		cabin:destroy()
	end
end

--[[ PUBLIC (StealController, 2026-09-30) — hand the shot to a director for a while. `getter` is asked
	every frame for `{ cframe, fov?, weight }` or nil; the live chase shot is computed exactly as always
	and then blended toward `cframe` by `weight`, so the director owns the SHAPE of its fade (in, cuts,
	out) and this file owns nothing about it. `StealJuiceConfig.Cinematic` has the design.

	A BLEND, NOT A TAKEOVER, and that is the safety of it: the chase shot never stops being computed —
	its lag filters, its flight blend, its lens — so when the weight comes back to 0 the camera is
	exactly where it would have been, with nothing to re-settle. Nil clears it. ]]
function RaceCameraController.setCinematic(self, getter: (() -> { cframe: CFrame, fov: number?, weight: number }?)?)
	self._cinematic = getter
end

-- === Game feel ===============================================================

--[[ Advance the punches and the lane lean. `crossVel` is the car's sideways speed, + = left, which is
	the same sign `RollDeg` banks with, so a positive lean is a lean into the move. ]]
function RaceCameraController._stepJuice(self, dt: number, crossVel: number)
	self._punchRoll, self._rollVel = stepSpring(self._punchRoll, self._rollVel, dt)
	self._punchPitch, self._pitchVel = stepSpring(self._punchPitch, self._pitchVel, dt)
	self._punchFov, self._fovVel = stepSpring(self._punchFov, self._fovVel, dt)

	local lane = CameraConfig.Juice.Lane
	local t = math.clamp(crossVel / math.max(lane.FullSpeed, 1e-3), -1, 1)
	local want = lane.RollDeg * t * juiceScale()
	self._laneRoll = approach(self._laneRoll, want, dt, lane.Gain)
end

--[[ The hit-stop: hold the last shot for `HitStop.Seconds`, then ease from it back to the live shot.
	Real time, not scaled — this is a beat of the camera, not of the world. ]]
function RaceCameraController._applyHold(self, live: CFrame): CFrame
	local held = self._holdCF
	if not held then
		return live
	end
	local cfg = CameraConfig.Juice.HitStop
	local elapsed = os.clock() - self._holdAt
	if elapsed < cfg.Seconds then
		return held
	end
	local t = (elapsed - cfg.Seconds) / math.max(cfg.BlendSeconds, 1e-3)
	if t >= 1 then
		self._holdCF = nil
		return live
	end
	local eased = 1 - (1 - t) * (1 - t)
	return held:Lerp(live, eased)
end

--[[ PUBLIC (ObstacleController.applyImpact) — the car was hit. `side` is +1 for the car's right, as
	`applyImpact` has it; `shake` is the hit kind's `Shake`, the game's one "how hard was that" number.

	Rolls toward the side that took the hit, nods down, squeezes the FOV, and on a heavy hit holds the
	shot for a beat. Ignored mid-flight: the car is hidden and the shot is about the arc. ]]
function RaceCameraController.impact(self, side: number?, shake: number?)
	local cfg = CameraConfig.Juice.Impact
	local scale = juiceScale()
	if not (self._engaged and scale > 0 and type(shake) == "number" and shake >= cfg.MinShake) then
		return
	end
	if self._flight then
		return
	end
	local span = math.max(cfg.FullShake - cfg.MinShake, 1e-3)
	local t = math.clamp((shake - cfg.MinShake) / span, 0, 1) * 0.65 + 0.35
	t *= scale
	-- Car's right is screen right, and a negative roll tilts the head right.
	local toward = if type(side) == "number" and side < 0 then 1 else -1
	self._rollVel += impulseFor(cfg.RollPeakDeg * t * toward)
	self._pitchVel += impulseFor(cfg.PitchPeakDeg * t)
	self._fovVel += impulseFor(cfg.FovPeakDeg * t)

	local stop = CameraConfig.Juice.HitStop
	local camera = workspace.CurrentCamera
	if stop.Enabled and shake >= stop.MinShake and camera and not self._holdCF then
		self._holdCF = camera.CFrame
		self._holdAt = os.clock()
	end
end

--[[ PUBLIC (NearMissController) — a clean pass. `side` is +1 when the car went past on the road's
	left (`NearMissConfig.isThread`'s convention), which is also the sign of a leftward roll, so the
	camera leans toward the car you shaved. `tier` picks the scale from `Juice.Pass`. ]]
function RaceCameraController.nearPass(self, side: number?, tier: string?)
	local cfg = CameraConfig.Juice.Pass
	local strength = (type(tier) == "string" and cfg[tier]) or 0
	local scale = juiceScale()
	if not (self._engaged and scale > 0 and type(strength) == "number" and strength > 0) or self._flight then
		return
	end
	local t = strength * scale
	if side == 1 or side == -1 then
		self._rollVel += impulseFor(cfg.RollPeakDeg * t * side)
	end
	-- Adjacent cars can award on one frame: bound the accumulated pass impulse.
	self._fovVel = math.min(self._fovVel + impulseFor(cfg.FovPeakDeg * t), impulseFor(cfg.MaxImpulsePeakDeg * scale))
end

--[[ PUBLIC (StealController, 2026-09-30) — the steal's two punches, `"Land"` and `"Takeover"`, off
	`StealJuiceConfig.Punch`. Same springs as `impact`, so they decay with the same feel.

	NOT GATED ON FLIGHT, unlike `impact` and `nearPass`, and that is the reason it is its own entry point:
	the landing happens while the flight shot is still up (the handoff has not run), and the punch is
	composed onto the flight shot as onto any other (`_step`'s final CFrame), so it lands on the avatar
	hitting the roof. ]]
function RaceCameraController.stealPunch(self, kind: string)
	local cfg = StealJuiceConfig.Punch
	local punch = cfg.Enabled and cfg[kind]
	local scale = juiceScale()
	if not (self._engaged and scale > 0 and type(punch) == "table") then
		return
	end
	self._rollVel += impulseFor(punch.RollPeakDeg * scale)
	self._pitchVel += impulseFor(punch.PitchPeakDeg * scale)
	self._fovVel += impulseFor(punch.FovPeakDeg * scale)
end

function RaceCameraController._resetCover(self)
	self._coverT = 0 -- 0..1 ease into the ducked shot
	self._coverDrop = 0 -- studs below the resting height the duck is asking for
	self._coverUntil = -math.huge -- along-coordinate the shot stays down until
end

function RaceCameraController._resetJuice(self)
	self._punchRoll, self._rollVel = 0, 0
	self._punchPitch, self._pitchVel = 0, 0
	self._punchFov, self._fovVel = 0, 0
	self._laneRoll = 0
	self._holdCF = nil
	self._holdAt = 0
end

-- === Flight mode =============================================================

--[[ PUBLIC (StealController) — frame the flight avatar instead of the car for the duration of a
	bail. Pass nil to hand the shot back.

	A GETTER rather than a part, and rather than a pushed position, for two reasons:

	  • The avatar is anchored and CFrame-driven, so the velocity on it is not the arc's — it is the
	    car's, frozen at the bail, and it never moves again (CameraConfig.Flight explains what that
	    would do to the follow lag). The getter returns both, from the state StealController is
	    already integrating, so the camera can never be looking at a position from one frame and a
	    velocity from another.
	  • This camera runs on RenderStep and the flight integrates on Heartbeat. Pulling once per
	    render frame means the shot always uses the newest state there is, rather than whatever was
	    last pushed at it.

	The getter must return `{ position = Vector3, velocity = Vector3 }` or nil; nil for a frame
	simply falls back to framing the car, which is the safe direction to fail in. ]]
function RaceCameraController.setFlight(self, getter: (() -> { position: Vector3, velocity: Vector3 }?)?)
	self._flight = getter
end

-- === Extra field of view =====================================================

--[[ PUBLIC (NitroController) — degrees of FieldOfView on top of what the shot is already doing.

	A NUMBER PUSHED AT THE CAMERA, not a property the caller writes. `_place` re-asserts the FOV
	every render frame off `CameraConfig.FieldOfView` and the speed ramp, so anything writing
	`camera.FieldOfView` directly is overwritten within a frame and reads as the effect not
	working. One owner of the property, everyone else adds to it.

	THE EASE BELONGS TO THE CALLER, not here. Nitro's push snaps in over a sixth of a second and
	falls back over half of one (`NitroConfig.Fov`), and that asymmetry is the effect: a second
	caller wanting a different shape should not have to argue with a smoothing this file chose.
	So this is a plain set, called per frame with an already-eased value.

	Survives a `_release` by being cleared there: a race that ends mid-burn must not hand the next
	one a camera pushed in by a bottle nobody is holding. ]]
function RaceCameraController.addFov(self, degrees: number?)
	self._extraFov = if type(degrees) == "number" then degrees else 0
end

--- PUBLIC (NearMissController) — a separate channel for the sustained Flow push. Nitro and Flow
--- can be active together, so sharing `addFov` would make the last controller to run erase the
--- other one's contribution.
function RaceCameraController.setFlowFov(self, degrees: number?)
	self._flowFov = if type(degrees) == "number" then math.clamp(degrees, 0, 5) else 0
end

--- PUBLIC (NitroController) — eased 0..1 vibration strength. Impact shake remains the Humanoid
--- offset channel above, so a collision during nitro naturally composes both effects.
function RaceCameraController.setNitroShake(self, amount: number?)
	self._nitroShake = if type(amount) == "number" then math.clamp(amount, 0, 1) else 0
end

-- === Rebase ==================================================================

--[[ RoadController snapped the whole world back toward the origin. Almost nothing to do: the two
	horizontal axes hold an OFFSET from the car rather than a position (see `restingLag`), so a
	translation that carries the car and the road together carries the shot with them and leaves
	the state meaning exactly what it meant before. Height is the one absolute, and a rebase only
	ever translates ALONG the road, so in practice this line never fires either.

	Kept, rather than dropped, because it costs one addition on a rare frame and it's the piece
	that would be silently wrong — a shot sliding down out of the world — if a rebase ever gained
	a vertical component. Runs inside the rebase frame, so it must not yield; it doesn't. ]]
function RaceCameraController._onWorldShift(self, shift: Vector3)
	if not self._engaged then
		return -- nothing smoothed yet; the next frame to find a car initialises from scratch
	end
	self._y += shift.Y
	-- The cover run is an along-coordinate in the same frame `wantAlong` is measured in, so a rebase
	-- has to carry it like it carries everything else. Left alone, a shift would put the far side of
	-- a bridge behind the car and stand the shot up inside it.
	if self._coverUntil > -math.huge then
		self._coverUntil += shift:Dot(self._forward)
	end
	-- A held hit-stop shot is a world CFrame, so it has to ride the rebase like the world does.
	if self._holdCF then
		self._holdCF += shift
	end
end

-- === Lifecycle ===============================================================

--- PUBLIC: chase camera <-> first person, the V key's and the VIEW button's one press.
function RaceCameraController.toggleFirstPerson(self)
	local fp = CameraConfig.FirstPerson
	fp.Enabled = not fp.Enabled
	self.log:info(string.format("First person %s.", if fp.Enabled then "ON" else "OFF"))
end

--[[ The VIEW button (`CameraConfig.FirstPerson.TouchButton`), built once at boot on EVERY device and
	shown only while a run is on and the player is on touch (`_showView`). A tap, not a hold.

	BUILT REGARDLESS OF DEVICE (2026-10-14): it used to be built only if `PreferredInput` read Touch
	at boot, and on a phone that tested it read something else until the first touch, so the button
	was never made ("on this phone I can't see the camera button"). Now the input is asked every
	time it changes. ]]
function RaceCameraController._buildViewButton(self)
	local cfg = CameraConfig.FirstPerson.TouchButton
	if not (cfg and cfg.Enabled) then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "FirstPersonView"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.Enabled = false
	--- A disc: the dark fill and blue rim of the boost button, the icon in the middle.
	local button = Instance.new("ImageButton")
	button.Name = "View"
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(cfg.Position.X, cfg.Position.Y)
	button.Size = UDim2.fromScale(cfg.Height, cfg.Height)
	button.BackgroundColor3 = ArcadeKit.Navy
	button.BackgroundTransparency = 0.35
	button.AutoButtonColor = false
	button.Parent = gui
	local square = Instance.new("UIAspectRatioConstraint")
	square.DominantAxis = Enum.DominantAxis.Height
	square.Parent = button
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = button
	local rim = Instance.new("UIStroke")
	rim.Color = Color3.fromRGB(33, 160, 255)
	rim.Thickness = 3
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = button
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.62, 0.62)
	icon.ScaleType = Enum.ScaleType.Fit
	--[[ A thumbnail URL rather than `rbxassetid://`: the id given is a DECAL, and an ImageLabel handed
		a decal's id draws nothing (the iPad showed the disc and no icon). `rbxthumb` resolves either. ]]
	icon.Image = string.format("rbxthumb://type=Asset&id=%d&w=150&h=150", cfg.Icon)
	icon.Parent = button
	button.Activated:Connect(function()
		self:toggleFirstPerson()
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self._viewGui = gui
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
		self:_showView()
	end)
	self:_showView()
end

--- Up while a run is on (`_bound`) and the player is on touch; the input is re-read on every change.
function RaceCameraController._showView(self)
	local gui = self._viewGui
	if not gui then
		return
	end
	local touch = UserInputService.PreferredInput == Enum.PreferredInput.Touch
		or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	gui.Enabled = self._bound == true and touch
end

function RaceCameraController._onRaceStart(self)
	self:_release() -- idempotent: a second RaceStart re-takes the camera cleanly
	if not CameraConfig.Enabled then
		return
	end
	if not self._road then
		self.log:warn("RoadController unavailable; cannot read a road frame. Leaving the camera stock.")
		return
	end
	self._bound = true
	RunService:BindToRenderStep(RENDER_NAME, RENDER_PRIORITY, function(dt)
		self:_step(dt)
	end)
	self:_showView()
end

function RaceCameraController._release(self)
	if self._viewGui then
		self._viewGui.Enabled = false -- before `_bound` drops below, so nothing re-reads it mid-release
	end
	-- Dropped first, so a race that ends mid-flight can't leave the next one pulling a stale
	-- getter that closes over a destroyed avatar. The extra FOV goes with it for the same reason:
	-- a race that ends mid-burn must not hand the next one a shot pushed in by a bottle nobody is
	-- holding, and the caller that pushed it may already be torn down.
	self._flight = nil
	self._cinematic = nil -- the same reason: a getter closing over a torn-down steal
	self._flightBlend = 0
	self._extraFov = 0
	self._flowFov = 0
	self._nitroShake = 0
	self:_resetJuice()
	self:_resetCover()
	-- First person lets go of the character and the car it hid things on, and the cockpit comes
	-- down with the shot. The flag itself is left alone: it is the tester's, not the race's.
	self:_leaveFirstPerson()
	self._fpBlend = 0
	self._fpSeat = nil
	self._fpAnchorCar = nil
	self._fpRoof = nil
	self._fpRim = nil
	self._fpLook = nil
	self._fpLookYaw = 0
	self._fpYawLag = 0
	self._fpSlowTilt = nil
	if self._cockpit then
		self._cockpit:hide()
	end
	if self._bound then
		RunService:UnbindFromRenderStep(RENDER_NAME)
		self._bound = false
	end
	if not self._engaged then
		return
	end
	self._engaged = false

	local camera = workspace.CurrentCamera
	if camera then
		if self._savedFov then
			camera.FieldOfView = self._savedFov
		end
		--[[ Hand the stock camera a live subject back before handing it control. The engine
			pointed CameraSubject at the VehicleSeat when we sat down, and by now that seat is
			being destroyed along with the car, which would leave the stock camera with nothing
			to frame. ]]
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
		-- Whatever we found, except never Scriptable — restoring that would mean releasing the
		-- camera into a frozen shot with nothing driving it.
		local restore = self._savedType
		if restore == nil or restore == Enum.CameraType.Scriptable then
			restore = Enum.CameraType.Custom
		end
		camera.CameraType = restore
	end

	self._savedType = nil
	self._savedFov = nil
	self._humanoid = nil
	-- Both belong to the car that's on its way out. Dropping the seat means the next race can't
	-- read a heading off a destroyed one, and zeroing the swing means it starts level.
	self._seat = nil
	self._yaw = 0
	self._frameYaw = 0
	self._speedT = 0
	self._speedFraction = 0
end

RaceCameraController:withRemoteEvents({
	{
		RaceStart = function()
			RaceCameraController:_onRaceStart()
		end,
		-- Note the absence of RaceWrecked: the wreck beat wants this camera held, framing the
		-- car as it coasts to a stop. RaceEnd follows a second or so later, behind the fade.
		RaceEnd = function()
			RaceCameraController:_release()
		end,
	},
})

RaceCameraController:withLifecycle({
	init = function(self)
		self._engaged = false
		self._bound = false
		-- Studs the shot trails the car by on each horizontal axis, and its absolute height.
		self._alongLag, self._crossLag, self._y = 0, 0, 0
		self._yaw = 0 -- radians the shot has swung into the turn; + = swung left
		self._frameYaw = 0 -- lane-position aim, separate from the turn-follow orbit
		self._speedT = 0 -- filtered 0..1 camera speed ramp
		self._speedFraction = 0 -- filtered share of the car's physical ceiling
		self._debugAt = 0
		self._flight = nil -- set while a bail is in the air; see `setFlight`
		self._flightBlend = 0
		self._extraFov = 0 -- degrees anything else has asked for on top of the shot; see `addFov`
		self._flowFov = 0 -- sustained skill-chain push, independent of nitro's channel
		self._nitroShake = 0 -- vibration strength; impact shake uses Humanoid.CameraOffset
		self:_resetCover() -- the duck under a bridge; see `_stepCover`
		-- Game feel (CameraConfig.Juice): three springs in degrees, the lane lean, and the hit-stop.
		self:_resetJuice()
		-- First person (CameraConfig.FirstPerson); see the section above `_firstPersonWanted`.
		self._fpOn = false -- hiding and the cockpit are up
		self._fpBlend = 0 -- 0 = the chase shot, 1 = the seat
		self._fpCar = nil -- the car being driven from the seat
		self._fpSeat = nil -- the seat the eye is anchored to, kept through the fade out
		self._fpAnchorCar = nil
		self._fpHidden = {} :: { [Instance]: number } -- what was hidden, and what it read before
		self._fpSweepAt = 0
		self._fpRoof = nil -- { car, top }: the body's roofline over the seat, once per car
		self._fpRim = nil -- { car, top? }: the top of the car's own wheel over the seat, once per car
		self._fpWheel = nil -- Modules/FirstPersonWheel for `_fpCar`, nil when it has no wheel
		self._fpCabin = nil -- Modules/FirstPersonCabin for `_fpCar`, the black cabin
		self._fpLook = nil -- the lagged flat heading
		self._fpYawLag = 0 -- radians the head trails the car's live heading (see `_firstPersonShot`)
		self._fpSlowTilt = nil :: Vector2? -- the body's pitch and roll, low-passed, for `TiltShare`
		self._fpLookYaw = 0 -- radians the eyes are turned into the steer
		self._cockpit = nil -- built on first use
		self._fpCockpitCar = nil -- the car the cockpit was last set up for in this shot
	end,

	start = function(self)
		self._road = Shard.get("RoadController")
		--- The car's own speed ceiling, for the speed band in `_step`. Resolved once here like
		--- `_road` is; a missing DriveController simply leaves the shot at its resting pose.
		self._drive = Shard.get("DriveController")

		-- Registered once for the session, exactly like the other world-shift listeners: the
		-- road keeps them across race teardowns on purpose.
		if self._road then
			self._road:onWorldShift(function(shift)
				self:_onWorldShift(shift)
			end)
		end

		-- Insurance, not part of the normal flow: dying in a race exits it through RaceEnd, so
		-- this only fires for a respawn we didn't cause. A fresh character resets the camera
		-- anyway, so letting go beats holding a shot of a car that no longer has a driver.
		Players.LocalPlayer.CharacterAdded:Connect(function()
			self:_release()
		end)

		--[[ The first-person key, for everyone since 2026-10-14 (it was admins only). It writes the
			same flag the admin panel's checkbox writes (`CameraConfig.FirstPerson.Enabled`) and `_step`
			reads it on the next frame, so pressing it mid-race is a blend into or out of the seat on
			the same road. A phone has the VIEW button instead (`_buildViewButton`). ]]
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if processed then
				return
			end
			--- V on a keyboard, R3 on a pad (`FirstPerson.GamepadKey`). Only those two input types, so a
			--- key that happens to share a name on some other device can never reach it.
			local fp = CameraConfig.FirstPerson
			local kind = input.UserInputType
			local pad = kind == Enum.UserInputType.Gamepad1
			if not ((kind == Enum.UserInputType.Keyboard and input.KeyCode == fp.ToggleKey)
				or (pad and input.KeyCode == fp.GamepadKey)) then
				return
			end
			self:toggleFirstPerson()
		end)
		self:_buildViewButton()
		--- Every cabin fetched in the background early in the session (`CockpitConfig.Cabin.Preload`).
		if CockpitConfig.Cabin.Preload then
			task.delay(CockpitConfig.Cabin.PreloadAfter, FirstPersonCabin.warm, nil)
		end
	end,
})

return RaceCameraController
