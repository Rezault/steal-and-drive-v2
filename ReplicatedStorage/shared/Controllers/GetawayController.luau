--[[
	GetawayController  (client)
	---------------------------
	The way OUT of a run. Some seconds after a steal a transport truck rolls onto the road ahead of
	you, opens its rear doors and drops its ramp; drive up into the bay and the run banks — you leave
	with the car you took instead of eventually wrecking it (GDD §3.4, `docs/GetawayTruck_Prep.md`).

	    (steal) --Spawn.Delay--> Waiting --> Live --in range--> opening --hull in the bay--> Banked
	                               ^                                   |
	                               \-------- driven past, despawns -----/

	It lives on the client for the same reason the road, the obstacles and the traffic do
	(RoadController): driving is solo, so every driver owns their own copy of the world and none of
	it replicates. `GetawayService` publishes the model and ratifies the bank; it never runs a truck.

	THE TRUCK IS A TRAFFIC CAR THAT YOU DRIVE INTO. It keeps its position in the ROAD FRAME — an
	`along` coordinate advanced by `Speed * dt`, a fixed lane across — exactly the way
	TrafficController keeps its cars, and for exactly the same reason: it drives off the tile it
	spawned on within seconds, so parenting it to a road tile would hand it to that tile's next
	recycle. A rebase is `RoadController:onWorldShift`, one addition.

	WHY IT ROLLS INSTEAD OF PARKING. The ramp is 26.7 degrees, and what a ramp does to a car is
	decided by the CLOSING speed at its foot, not by the road speed. Parked, it meets a cruise at 52
	studs/s and launches; rolling at 30 it meets one at 22 and is climbed. See GetawayConfig's header.

	THE MECHANISM IS POSED, NOT SIMULATED. Every part of the truck is anchored and jointless (prep
	doc §4) — welding would mean a CFrame write on a door dragged the whole truck with it — so the
	doors and ramp are moved about their hinge Attachments by hand, each frame, from a REST POSE
	captured in the truck's own object space when the model was prepared. Absolute, never
	incremental: `Model:PivotTo` preserves a child's offset rather than resetting it, so a pose
	composed onto the part's live CFrame would compound a little further every frame and read as
	flicker. `_pose` composes onto `rest` and nothing else.

	The doors are one rotation each. THE RAMP IS A SLIDE-OUT IN TWO LEGS — the plate travels straight
	back out of the bay flat, and only then tilts down onto the road about its own inboard end, which
	by then is resting on the rear sill. Both legs are derived from the rig rather than configured;
	`_prepare` has the geometry and the argument for it.

	The bank test is POINT-IN-BOX, in the truck's object space, and not a spatial query. `LoadZone`
	is published query-blind on purpose (see GetawayService) so the stock CarBones suspension rays —
	which run as "Default" and are not ours to filter — cannot try to drive up the inside of the bay.
	A box test needs no query, so it can't be defeated by a collision group either, which is the trap
	TrafficController's header warns about.

	What banking actually does here is the LOCAL half: the car slides the last few studs into a berth
	(`_planBerth`), squares up, and rides the truck out while the mechanism shuts behind it. The
	berth is not decoration — the bank fires with the tail still outside the sill, so without it the
	doors shut through the car. Ending the run is the server's (GetawayService -> RaceService.bankRun),
	and GetawayService awards the server's recorded car. Assisted entry (GetawayConfig.Boarding)
	can own the climb before the bank, but does not send that request until the hull is in the bay.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameplayFeedback = require(ReplicatedStorage.shared.Modules.GameplayFeedback)
local Shard = require(ReplicatedStorage.Packages.Shard)
local GetawayConfig = require(ReplicatedStorage.shared.Configs.GetawayConfig)
--- The bank flash's colour and size (`GetawayConfig.BankFlash`).
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
--- The getaway's two sounds live in the steal's bank (`StealJuiceConfig.Sounds`); a config, no cycle.
local StealJuiceConfig = require(ReplicatedStorage.shared.Configs.StealJuiceConfig)
local ObstacleConfig = require(ReplicatedStorage.shared.Configs.ObstacleConfig)
--[[ For the onboarding's gently rigged first run, and for nothing else — see `_timing` below. It is
	a config require and not a dependency on `TutorialController`: what this needs is one string off
	the player, and taking the controller would be a start-order edge for a lookup. ]]
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local TimeScale = require(ReplicatedStorage.shared.Modules.TimeScale)
local GetawayBoarding = require(ReplicatedStorage.shared.Modules.GetawayBoarding)

local GetawayController = Shard.new("GetawayController"):withDependencies({
	"RoadController",
	"TrafficController",
	"StealController",
})

-- Height of the box the spawn-clearance sweep uses, studs above the deck. Same 9 TrafficController
-- probes with, and for the same reason: the tallest obstacle volume is 8.4, and reaching higher
-- starts finding the bridges that pass over the road.
local PROBE_HEIGHT = 9
-- Extra studs either side of the truck the clearance sweep asks for, so it isn't declared clear by
-- a barrier standing exactly on the mirror line.
local CLEAR_MARGIN = 6

-- === The onboarding's numbers ===============================================

--[[ THE TRUCK IS THE ONE THING THE TUTORIAL CHANGES ABOUT A RUN, and this is the whole of that
	change: three timings, read through one gate.

	The shipped cadence (`GetawayConfig.Spawn`) is tuned for somebody who knows what a truck is.
	A first-timer does not — they will not recognise the thing sliding past them as the exit, and
	"bank it or push on" (GDD §3.5, the decision this game is built around) is therefore the beat
	they are most likely to finish their first run never having seen. So while they are on the
	tutorial's in-race steps the truck comes sooner, comes back sooner, and waits longer before it
	gives up on them.

	NOTHING ELSE IS TOUCHED. Not damage, not the steal, not traffic. The run is the real run; it
	just gets its exit offered earlier. `TutorialConfig.Rig` has the argument for each number, and
	`Rig.Enabled = false` puts this back on the shipped ones.

	IT IS READ OFF A PLAYER ATTRIBUTE, live, every time. No cached flag, no signal to subscribe to,
	nothing to unsubscribe on teardown — the server publishes the step on the player
	(`TutorialConfig.StepAttribute`), so a step that advances mid-run takes effect on the next read
	and a tutorial that finishes stops rigging by itself. ]]
function GetawayController._rigged(self): boolean
	local player = Players.LocalPlayer
	return player ~= nil and TutorialConfig.isRigged(player:GetAttribute(TutorialConfig.StepAttribute))
end

--- Seconds until the next truck: the tutorial's band if this is a first run, the shipped one
--- otherwise. `retry` picks the after-a-miss pair, which is the longer of the two in both sets.
function GetawayController._timing(self, retry: boolean): number
	local band = if retry then GetawayConfig.Spawn.RetryDelay else GetawayConfig.Spawn.Delay
	if self:_rigged() then
		band = if retry then TutorialConfig.Rig.TruckRetryDelay else TutorialConfig.Rig.TruckDelay
	end
	return self._rng:NextNumber(band[1], band[2])
end

--- Studs behind the driver at which a missed truck gives up. Wider during the tutorial, so a player
--- who drives past the ramp and only then works out what it was can still get back to it.
function GetawayController._despawnBehind(self): number
	if self:_rigged() then
		return TutorialConfig.Rig.DespawnBehind
	end
	return GetawayConfig.DespawnBehind
end

--[[ PUBLIC (TutorialController) — the truck, if there is one on the road right now.

	ONE FACT AND NO CONTROL, the same shape `StealController.getFlight` is. The onboarding's BANK
	beat changes what it says when the exit actually turns up ("a truck is coming" becomes "the
	truck is here") and floats its pointer over it, and neither of those may touch the truck.

	"live" AND NOT "waiting", deliberately. A truck that has been armed but not spawned is not a
	thing anybody can see, and a card announcing it would be announcing an empty road.

	Returns the part to point AT rather than the model, because that is what every caller wants and
	because the model's own pivot is not on the bodywork. ]]
function GetawayController.getTruck(self): BasePart?
	if self._state ~= "live" then
		return nil
	end
	local model = self._model
	if not (model and model.Parent) then
		return nil
	end
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

--[[ PUBLIC (StealController) — the whole truck, hull and ramp and doors together, while it is a
	solid thing standing on the road. nil at every other moment.

	THE MODEL RATHER THAN A PART, unlike `getTruck` above, and the difference is the ramp. A pointer
	only ever wants somewhere to float and the hull answers that. A steal landing beside the truck
	has to miss ALL of it — and the part it actually wedges inside is the RAMP, which lies flat on
	the road several studs behind the hull. Handing out the PrimaryPart would test the one piece of
	the truck the reported wedge does not happen in.

	SOLIDITY IS LEFT TO THE CALLER'S QUERY, which is why this hands back the model rather than a
	filtered list. `_pose` keeps the ramp and the doors non-collidable for the whole of their travel
	and only makes them solid at the two ends of it, so a caller asking with `RespectCanCollide` gets
	precisely the parts that could wedge a car and none of the ones sweeping through the air.

	"live" ONLY, and that gate is what makes this safe to push a car out of. Once the run is `banked`
	the player's car is being put INSIDE the bay deliberately (`_freezeCarIntoBay`), and a caller
	clearing them out of the truck then would be undoing the bank they had just earned. ]]
function GetawayController.getObstacle(self): Model?
	if self._state ~= "live" then
		return nil
	end
	local model = self._model
	return if model and model.Parent then model else nil
end

-- === Road frame =============================================================

-- World position of a point in the road frame. `forward`, `cross` and `yAxis` are the three world
-- axes, so this composition is exact — the same one TrafficController._worldPos uses.
function GetawayController._worldPos(self, alongCoord: number, crossOffset: number): Vector3
	local info = self._info
	return info.forward * alongCoord
		+ info.cross * (info.driveCenter + crossOffset)
		+ Vector3.yAxis * info.deckY
end

-- === Preparing the model ====================================================

--[[ Half-extents of a box along the axes of the frame it is measured in.

	The bay volume is authored square to the truck, so this is exact for it; for anything rotated it
	is the conservative enclosing box, which is the right way to be wrong about a volume you are
	testing "is the car safely inside" against. ]]
local function projectHalf(cf: CFrame, size: Vector3): Vector3
	local h = size * 0.5
	local x, y, z = cf.XVector, cf.YVector, cf.ZVector
	return Vector3.new(
		math.abs(x.X) * h.X + math.abs(y.X) * h.Y + math.abs(z.X) * h.Z,
		math.abs(x.Y) * h.X + math.abs(y.Y) * h.Y + math.abs(z.Y) * h.Z,
		math.abs(x.Z) * h.X + math.abs(y.Z) * h.Y + math.abs(z.Z) * h.Z
	)
end

--[[ Capture everything about the truck that never changes again, in the truck's OWN object space,
	so nothing downstream has to re-measure a model it didn't build.

	Object space is what makes the rest of this file simple. The truck moves every frame, so a hinge
	remembered as a world position would be wrong by `Speed * dt` immediately; remembered as an
	offset from `Root` it is correct forever, and posing a door is one composition against the
	truck's current frame. ]]
function GetawayController._prepare(self, model: Model): boolean
	local names = GetawayConfig.Parts
	local root = model.PrimaryPart
	if not (root and root:IsA("BasePart")) then
		self.log:warn("The getaway truck has no PrimaryPart; it can't be placed.")
		return false
	end
	local rootCF = root.CFrame

	local zone = model:FindFirstChild(names.LoadZone)
	if not (zone and zone:IsA("BasePart")) then
		self.log:warn(string.format("The getaway truck has no '%s' volume; there'd be no way to bank.", names.LoadZone))
		return false
	end
	local zoneLocal = rootCF:ToObjectSpace(zone.CFrame)
	self._zoneCentre = zoneLocal.Position
	self._zoneHalf = projectHalf(zoneLocal, zone.Size)

	--[[ One mover = one part that swings about one hinge. `rest` is its shut pose and `pos`/`axis`
		are its hinge, all in the truck's object space; the Attachment's PrimaryAxis (its X axis) is
		the rotation axis, which is how a HingeConstraint would read the same attachment. ]]
	local movers = {}
	local function addMover(part: Instance?, hinge: Attachment?, target: number, style, direction)
		if not (part and part:IsA("BasePart") and hinge) then
			return nil
		end
		local m = {
			part = part,
			pos = rootCF:PointToObjectSpace(hinge.WorldPosition),
			axis = rootCF:VectorToObjectSpace(hinge.WorldAxis),
			rest = rootCF:ToObjectSpace(part.CFrame),
			target = target,
			-- The ramp swings on its own curve; the doors keep the snappier one. See GetawayConfig.
			style = style or GetawayConfig.Open.Style,
			direction = direction or GetawayConfig.Open.Direction,
			-- Whether this part is solid when it is fully open or fully shut. It stops being solid
			-- for the swing itself: mid-travel the doors stick 7 studs straight out the back and the
			-- ramp sweeps a 207-degree arc up over the sill, and a car catching either of those
			-- reads as the truck attacking you.
			solid = part.CanCollide,
		}
		table.insert(movers, m)
		return m
	end

	local fallback = GetawayConfig.Fallback
	local doorAngle = model:GetAttribute("DoorOpenAngleDeg")
	if type(doorAngle) ~= "number" then
		doorAngle = fallback.DoorOpenAngleDeg
	end

	--[[ THE RAMP IS A SLIDE-OUT: stowed it lies flat on the bay floor, and it deploys in two legs —
		straight back out of the bay on its rails, then a tilt down onto the road about its own
		inboard end, which by then is sitting on the rear sill. `slide`, `sink` and `target` below are
		one leg each; `_pose` composes them.

		IT USED TO BE A SINGLE 207-DEGREE FLIP up through the doorway and over the sill, and this
		lands in exactly the same place — the deployed pose is measured against a real car on the real
		road (prep doc §6.4) and the slide reproduces it to the 0.001 stud. What it does not
		reproduce is the travel: the flip stood the plate vertically in the open doorway and swept it
		through both door leaves for a third of its swing. Sampled 41 frames of each against the
		truck's own geometry, the slide's contact set is a strict subset of the flip's. It also keeps
		the plate's treaded face up, where the flip turned it under.

		THREE NUMBERS, ALL READ OFF THE RIG rather than written down here, because they are not
		choices — a slide-out that stops short leaves its tip in the air:

		  reach     how far it has to travel to clear the sill = the plate's own length. It slides
		            out the truck's local +Z, which is its tail (a CFrame's LookVector is its -Z).
		  sink      the plate tips over the sill LIP, not about its own underside, so it settles by
		            its own thickness as it goes over. That is what puts the driving surface flush
		            with the bay floor at the top and with the road at the bottom, instead of a
		            plate-thickness lip proud of both.
		  target    the only tilt that puts the tip on the road: asin(hinge height / reach). The
		            hinge sits at bay-floor height, so the drop and the length are both already here.

		WHICH WAY THE TILT TURNS is read off the rig too. The old code hard-coded a sign after a bug
		where the plate rotated down through the chassis rails, the air tanks and all four rear wheels
		and dipped eight studs under the road on its way to a deployed pose that looked correct.
		Rotating a test tip both ways and keeping the one that ends up lower cannot get that wrong. ]]
	local ramp = model:FindFirstChild(names.Ramp)
	-- Held on to by identity rather than by index: it is the one mover on its own clock, and a truck
	-- whose ramp lost its Hinge would otherwise silently promote a door into the ramp's place.
	self._ramp = addMover(
		ramp,
		ramp and ramp:FindFirstChild(names.HingeName),
		0, -- filled in below, from the geometry
		GetawayConfig.Open.RampStyle,
		GetawayConfig.Open.RampDirection
	)
	if self._ramp then
		local m = self._ramp
		-- Half-extents along the TRUCK's axes, so this holds however the plate itself is oriented.
		local half = projectHalf(m.rest, ramp.Size)
		local reach, thickness = half.Z * 2, half.Y * 2
		m.slide = Vector3.new(0, 0, reach)
		m.sink = Vector3.new(0, -thickness, 0)

		local drop = m.pos.Y -- the hinge is at bay-floor height; that is the whole fall
		local angle
		if drop < reach then
			angle = math.deg(math.asin(drop / reach))
			local stamped = model:GetAttribute("RampDeployAngleDeg")
			if type(stamped) == "number" and math.abs(stamped - angle) > 0.5 then
				self.log:warn(string.format(
					"The truck's RampDeployAngleDeg says %.2f but its geometry says %.2f — the model's "
						.. "attribute has drifted from its ramp. Going with the geometry.",
					stamped,
					angle
				))
			end
		else
			-- A plate shorter than the bay floor is high cannot reach the road at any angle.
			angle = fallback.RampDeployAngleDeg
			self.log:warn(string.format(
				"The truck's ramp is %.1f studs long but its hinge is %.1f studs up, so it can't reach "
					.. "the road; deploying at the fallback %.1f degrees and leaving the tip in the air.",
				reach,
				drop,
				angle
			))
		end
		m.target = if (CFrame.fromAxisAngle(m.axis, math.rad(angle)) * m.slide).Y < 0 then angle else -angle
	end

	local doors = model:FindFirstChild(names.Doors)
	local doorL = doors and doors:FindFirstChild(names.DoorL)
	local doorR = doors and doors:FindFirstChild(names.DoorR)
	addMover(doorL, doorL and doorL:FindFirstChild(names.HingeName), -doorAngle)
	addMover(doorR, doorR and doorR:FindFirstChild(names.HingeName), doorAngle)
	-- The handle is one bar straddling the seam between the leaves, so it cannot belong to either
	-- one. It rides DoorL by fiat until the modeller splits it (prep doc §5.1) — invisible at 270
	-- degrees, where both leaves end up flat against the same box side anyway.
	addMover(doors and doors:FindFirstChild(names.DoorHandle), doorL and doorL:FindFirstChild(names.HingeName), -doorAngle)

	self._movers = movers
	if not self._ramp then
		self.log:warn("The getaway truck has no posable Ramp; you'll only be able to bank by jumping in.")
	end

	-- Read off the model rather than measured, so a re-scale or a re-import changes these in one
	-- place. Falls back to the bounding box for a truck that arrived without its contract.
	local _, size = model:GetBoundingBox()
	self._length = model:GetAttribute("Length") or size.Z
	self._width = model:GetAttribute("WidthOverall") or size.X
	--[[ How much road the ramp needs behind the truck, for the spawn-clearance sweep. Taken from the
		slide rather than from the model's `RampReach`, and it is the bigger of the two on purpose:
		`RampReach` is 13.24, the DEPLOYED footprint, but the plate is momentarily 14.81 studs out flat
		between the two legs, and that is the moment a barrier would be standing in. ]]
	self._rampReach = (self._ramp and self._ramp.slide.Z) or model:GetAttribute("RampReach") or 0
	return true
end

-- === Posing =================================================================

--[[ Put one mover at `frac` of its travel, 0 = shut, 1 = open. A mover with a `slide` (the ramp, and
	only the ramp) is two-legged: `slideFrac` runs its extension and `frac` runs the tilt that follows.

	Composed onto `rest` — the pose the part was authored in — and NEVER onto its live CFrame. That
	is the whole reason this is stable: the truck is re-pivoted every frame, and `Model:PivotTo`
	carries a child at whatever offset it currently has instead of resetting it, so a rotation
	applied to the live CFrame would add to the previous frame's rotation forever. ]]
function GetawayController._pose(self, rootCF: CFrame, m, frac: number, extraDeg: number?, slideFrac: number?)
	local eased = TweenService:GetValue(math.clamp(frac, 0, 1), m.style, m.direction)
	local spin = CFrame.fromAxisAngle(m.axis, math.rad(m.target * eased + (extraDeg or 0)))
	-- The extension and the settle are both pure translations in the truck's frame, so they add
	-- rather than compose; both happen BEFORE the tilt, which then swings the whole lot about the
	-- hinge. (Order matters the other way round: rotating first would carry the slide off-axis.)
	local offset = CFrame.identity
	if m.slide then
		local out = TweenService:GetValue(math.clamp(slideFrac or 0, 0, 1), m.style, m.direction)
		offset = CFrame.new(m.slide * out + m.sink * eased)
	end
	m.part.CFrame = rootCF * (CFrame.new(m.pos) * spin * CFrame.new(-m.pos) * offset * m.rest)

	-- Solid only at the two ENDS of the whole travel. For the ramp that means BOTH legs home or both
	-- deployed: half-way through, the plate is a slab sticking out of the bay at deck height, and a
	-- car meeting that is a car meeting a wall. `slideFrac or frac` collapses this to the old
	-- single-fraction test for the doors.
	local other = slideFrac or frac
	local settled = math.max(frac, other) <= 0.001 or math.min(frac, other) >= 0.999
	local solid = m.solid and settled

	--[[ ...but never turn solid ON TOP OF THE CAR, which is the one way this beat could hurt you.

		The failure: drive up close while the ramp is still deploying — legal, and what a fast car
		naturally does — and be overlapping the plate on the frame its travel runs out. This line
		then flips an ANCHORED part to `CanCollide` inside a dynamic assembly, and the solver's only
		way out of an interpenetration it cannot push the anchored half of is to eject the car. At
		road speed that reads as being swallowed by the truck, which is exactly what was reported.

		DEFERRED, NOT CANCELLED: the plate stays a pure query volume only while the car's centre is
		inside it, and goes solid the moment it is not — which for a car driving up the ramp is
		immediately, because a car ON the plate has its centre above it. `_blockedByCar` carries the
		derivation, and the bug that comes of testing this with an overlap instead.

		ONLY ON THE WAY IN, and that asymmetry is a second belt on the same trousers. The test is
		guarded on the part not already being solid, so nothing that has gone solid can be talked
		back into a hole by a car that later drives into it. Once solid, ordinary collision takes
		over and this never runs again for that part.

		The closing beat needs none of this: by then `_freezeCarIntoBay` has anchored the car, and an
		anchored assembly is not something the solver can eject. ]]
	if solid and not m.part.CanCollide and self:_blockedByCar(m.part) then
		solid = false
	end

	if m.part.CanCollide ~= solid then
		m.part.CanCollide = solid
	end
end

--[[ Would this mover be turning solid INSIDE the car? See `_pose` for what it is guarding.

	THE TEST IS THE HULL'S CENTRE AGAINST THE MOVER'S BOX, and picking that over an overlap query is
	the whole substance of this function — the first version asked `GetPartsInPart` and was wrong in
	a way worth writing down, because it looked obviously right.

	AN OVERLAP CANNOT TELL THE TWO CASES APART. Driving up the ramp IS overlapping the ramp, and
	permanently: the plate is what the wheels are resting on. So an overlap test defers forever, the
	ramp never goes solid, and the car drives straight through the thing it is supposed to be driving
	up. That is a worse bug than the ejection this guard exists to prevent, and it is the one that
	got reported second.

	THE CENTRE SEPARATES THEM CLEANLY, because the two cases differ in exactly one way: where the car
	IS relative to the plate. Resting on it, the hull's centre sits a couple of studs ABOVE the top
	face — outside the box — so the plate goes solid and you drive up it. Being landed on, the centre
	is inside the plate's own volume, which is the geometric statement of "this part is about to
	materialise inside the car" and the only case the solver cannot resolve without throwing you.

	IT IS THE SAME TEST FOR THE DOORS and does not need to be a different one. A car alongside a
	swinging leaf brushes its edge — centre well outside, so the leaf stays solid and ordinary
	collision applies. A car the leaf would close around has its centre inside it. Same question,
	same answer, no per-mover special case.

	CONSERVATIVE AT THE NOSE, deliberately. A long car whose centre is clear but whose bonnet is deep
	in the plate reads as "not blocked" and takes a nudge. That is the right way to be wrong: a shove
	at the nose against a thin plate is a bump, where the case this rejects is being thrown across
	the road. ]]
function GetawayController._blockedByCar(self, part: BasePart): boolean
	local hull = self._hitBox or (self._playerCar and self._playerCar.PrimaryPart)
	if not (hull and hull.Parent) then
		return false
	end
	local p = part.CFrame:PointToObjectSpace(hull.Position)
	local half = part.Size * 0.5
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

--[[ Degrees of rebound to add to the ramp just after it touches down, so a heavy steel ramp
	arrives with some weight instead of stopping dead the instant its travel runs out.

	RECTIFIED, NOT A PLAIN SINE, and that is the whole correctness of it: `abs` makes every hump
	negative, so the rebound can only ever take angle OFF the deploy — the tip lifts off the road
	and falls back onto it. A raw sine alternates, and the positive half-cycles drove the ramp
	0.11 studs INTO the tarmac, which is both wrong and the one frame anybody is looking at it.
	A bouncing object only ever leaves the surface, so one-sided is also what the physics says.

	Each hump is one bounce, hence `Cycles` counting bounces rather than wavelengths. Squared decay
	so the second is a fraction of the first and the whole thing is visibly over rather than
	trailing off. Returns exactly 0 outside the window, so this costs nothing for the rest of the
	run. ]]
function GetawayController._rampSettle(self): number
	local landed = self._rampLandedAt
	if not landed then
		return 0
	end
	local settle = GetawayConfig.Open.Settle
	local t = os.clock() - landed
	if t >= settle.Time then
		return 0
	end
	local decay = 1 - t / settle.Time
	return -settle.AngleDeg * decay * decay * math.abs(math.sin(t / settle.Time * math.pi * settle.Cycles))
end

--[[ How much faster than its authored pace the deploy has to run to be down before the car arrives.
	1 at any ordinary approach; see `GetawayConfig.Open.Deadline` for the whole argument.

	    remaining = the rest of the deploy at 1x, counting only what the bank waits for
	    eta       = (ramp foot - car nose) / (car speed - truck speed)
	    rate      = remaining / (eta - Margin), clamped to [1, MaxRate]

	"WHAT THE BANK WAITS FOR" is the doors up to the ramp's cue, then the slide, then the tilt — the
	doors finishing their swing after the cue is not on the critical path, so it is not counted.

	A car not closing on the truck (slower, or braking) has no ETA and gets 1: nothing is coming. A
	car already at or past the deadline gets `MaxRate`, which is the pop the config describes.

	Pure: it reads the rig's state and the car's velocity and writes nothing, so calling it every
	frame of an open costs a handful of arithmetic and cannot drift. ]]
function GetawayController._deployRate(self): number
	local open = GetawayConfig.Open
	local deadline = open.Deadline
	if not (deadline and deadline.Enabled) then
		return 1
	end
	local car = self._playerCar
	local hull = car and car.PrimaryPart
	if not (hull and self._info) then
		return 1
	end

	local closing = hull.AssemblyLinearVelocity:Dot(self._info.forward) - GetawayConfig.Speed
	if closing <= 0 then
		return 1
	end

	local remaining = math.max(0, open.RampAfterDoors - self._doorRaw) * open.DoorTime
		+ (1 - self._slideRaw) * open.RampSlideTime
		+ (1 - self._tiltRaw) * open.RampTiltTime
	if remaining <= 0 then
		return 1
	end

	local foot = self._along - self._length * 0.5 - self._rampReach
	local gap = foot - (self._playerAlong + deadline.NoseStuds)
	local budget = math.max(0, gap) / closing - deadline.Margin
	if budget <= 0 then
		return deadline.MaxRate
	end
	return math.clamp(remaining / budget, 1, deadline.MaxRate)
end

--[[ Advance the three legs of the mechanism toward whatever `_openGoal` is now: the doors, the ramp's
	slide, and the ramp's tilt.

	They are STRICTLY SEQUENCED, and the whole order reverses on the way shut — doors, then slide,
	then tilt going out; tilt, then slide, then doors coming back. Each leg gates the next because
	each one is physically in the next one's way: the plate leaves through the doorway, and it cannot
	tilt down over the sill until it is out past it.

	Nothing here interpolates. The legs are raw 0..1 travel and `_pose` eases them, so a paused frame
	and a 200ms hitch both land in the same place. ]]
function GetawayController._stepMechanism(self, dt: number)
	local open = GetawayConfig.Open
	local bank = GetawayConfig.Bank
	if self._openGoal >= 1 then
		--- Only the OPENING is hurried; see `_deployRate`. Closing happens with the car already in
		--- the bay, and nothing is racing it.
		dt *= self:_deployRate()
		self._doorRaw = math.min(1, self._doorRaw + dt / open.DoorTime)
		if self._doorRaw >= open.RampAfterDoors then
			self._slideRaw = math.min(1, self._slideRaw + dt / open.RampSlideTime)
		end
		if self._slideRaw >= 1 then
			self._tiltRaw = math.min(1, self._tiltRaw + dt / open.RampTiltTime)
			-- Touchdown, once, on the frame the travel runs out. `_rampSettle` reads the clock.
			if self._tiltRaw >= 1 and not self._rampLandedAt then
				self._rampLandedAt = os.clock()
			end
		end
	else
		-- Off the road first, then back inside. Per-leg budgets because 27 degrees of lift and 14.8
		-- studs of retraction are not the same job; see GetawayConfig.Bank.
		self._tiltRaw = math.max(0, self._tiltRaw - dt / bank.RampTiltCloseTime)
		self._rampLandedAt = nil -- it is off the road again; a re-open earns a fresh landing
		if self._tiltRaw <= 0 then
			self._slideRaw = math.max(0, self._slideRaw - dt / bank.RampSlideCloseTime)
		end
		if self._slideRaw <= open.RampAfterDoors then
			--[[ The bank's sound is the doors SHUTTING, so it waits for the doors' first frame of travel
				rather than playing at the bank itself (2026-10-03: at the bank it rang out ~1s early,
				over the berth and the ramp, before a door had moved). Armed by `_bank`, played once. ]]
			if self._bankSfxArmed and self._doorRaw > 0 then
				self._bankSfxArmed = false
				self:_sfx("GetawayBank")
			end
			self._doorRaw = math.max(0, self._doorRaw - dt / bank.DoorCloseTime)
		end
	end
end

-- Put the truck where its road-frame scalars say it is, then pose the mechanism onto that frame.
-- `PivotTo` moves all forty-odd parts in one transform (the movers included, at their stale
-- offsets); `_pose` then overwrites the four that swing, absolutely.
function GetawayController._place(self)
	local info = self._info
	local pos = self:_worldPos(self._along, self._cross)
	-- Heading follows the truck's own velocity, so a weave (`_stepWeave`) yaws it into the lane change;
	-- at every other moment `_crossVel` is 0 and this is straight down the road, as it always was.
	local rootCF = CFrame.lookAt(pos, pos + info.forward * math.max(self:_speedNow(), 1) + info.cross * self._crossVel)
	if self._roll ~= 0 then
		-- The body leans off the turn: top toward the outside, which is opposite the sideways push.
		local outside = -info.cross * self._roll
		rootCF *= CFrame.Angles(0, 0, -math.rad(GetawayConfig.Exit.Weave.RollDeg) * outside:Dot(rootCF.RightVector))
	end
	self._model:PivotTo(rootCF)
	for _, m in self._movers do
		if m == self._ramp then
			self:_pose(rootCF, m, self._tiltRaw, self:_rampSettle(), self._slideRaw)
		else
			self:_pose(rootCF, m, self._doorRaw)
		end
	end
	self._rootCF = rootCF
end

-- === Spawning ===============================================================

-- Rebuild the obstacle Include list from whatever the road is carrying right now — nine
-- FindFirstChild calls, re-derived rather than cached so a tile recycle can't leave it stale. Same
-- shape as TrafficController._refreshObstacleFilter.
function GetawayController._refreshObstacleFilter(self)
	local list = {}
	for _, tile in self._road:getSegments() do
		local folder = tile.Parent and tile:FindFirstChild(ObstacleConfig.TileFolderName)
		if folder then
			table.insert(list, folder)
		end
	end
	self._obstacleParams.FilterDescendantsInstances = list
end

--[[ Is there room to put a 54-stud truck here, with its ramp behind it and a run-up in front?

	A truck materialising inside a concrete barrier is the most visible failure this layer has, and
	the approach matters as much as the footprint — a truck placed legally on the far side of a gate
	is one you cannot reach. One box query over the obstacle folders covers both.

	`GetPartBoundsInBox` is safe here for the reason TrafficController spells out: the filter is only
	the obstacle folders, whose volumes are axis-aligned blocks and upright cylinders, so their
	bounds are their shape. The warning about bounding boxes is about querying whole road tiles. ]]
function GetawayController._clearAt(self, alongCoord: number): boolean
	if #self._obstacleParams.FilterDescendantsInstances == 0 then
		return true -- no course built here yet; nothing to be standing in
	end
	local info = self._info
	local half = self._length * 0.5
	local back = alongCoord - half - self._rampReach
	local front = alongCoord + half + GetawayConfig.Spawn.ClearAhead
	local centre = self:_worldPos((back + front) * 0.5, GetawayConfig.Lane) + Vector3.yAxis * (PROBE_HEIGHT * 0.5)
	-- Local +X across the road, +Y up, +Z down it: cross x up == forward, so the size below reads
	-- as (across, up, along). Same basis the obstacle builder and the traffic lookahead use.
	local frame = CFrame.fromMatrix(centre, info.cross, Vector3.yAxis)
	local size = Vector3.new(self._width + CLEAR_MARGIN * 2, PROBE_HEIGHT, front - back)
	return workspace:GetPartBoundsInBox(frame, size, self._obstacleParams)[1] == nil
end

--- One getaway beat's clip out of the steal's sound bank (`StealJuiceConfig.Sounds`, 2026-09-30).
function GetawayController._sfx(self, beat: string)
	local cfg = StealJuiceConfig.Sounds
	local name = cfg.Enabled and cfg[beat]
	local sounds = Shard.get("SoundController")
	if type(name) == "string" and sounds then
		sounds:PlayNamed(cfg.Group, name)
	end
end

function GetawayController._spawn(self): boolean
	self._boardingPrevious = nil
	local spawn = GetawayConfig.Spawn
	for _ = 1, spawn.Tries do
		local hull = self._playerCar and self._playerCar.PrimaryPart
		local closing = if hull and self._info then hull.AssemblyLinearVelocity:Dot(self._info.forward) - GetawayConfig.Speed else 0
		local alongCoord = self._playerAlong + GetawayConfig.approachAhead(closing, self._rng:NextNumber())
		if self:_clearAt(alongCoord) then
			self._along = alongCoord
			self:_resetWeave()
			self._doorRaw = 0
			self._slideRaw = 0
			self._tiltRaw = 0
			self._rampLandedAt = nil
			self._openGoal = 0
			self._state = "live"
			self:_place()
			self._model.Parent = self._folder
			-- Tell the traffic layer this is in the way, so cars steer round it instead of driving
			-- through it. Registered on spawn and cleared on despawn, so it costs nothing the rest
			-- of the time.
			if self._traffic then
				self._traffic:setAvoid(self._model, function()
					return self:_avoidFootprint()
				end)
			end
			--- The truck is on the road (`StealJuiceConfig.Sounds.GetawayArrive`).
			self:_sfx("GetawayArrive")
			return true
		end
	end
	return false
end

--- Where the truck is, for traffic to steer round (`TrafficController.setAvoid`): rear and front
--- along the road, its lane, half its width, and its speed. The rear counts the ramp's reach,
--- since a car that dodges the box and hits the plate has not dodged anything.
function GetawayController._avoidFootprint(self): (number, number, number, number, number)
	local half = self._length * 0.5
	return self._along - half - self._rampReach, self._along + half, self._cross, self._width * 0.5, self:_speedNow()
end

function GetawayController._despawn(self, retry: boolean)
	self._state = "off"
	self._model.Parent = nil
	if self._traffic then
		self._traffic:setAvoid(nil)
	end
	if retry then
		self:_arm(self:_timing(true))
	end
end

-- Start the clock on the next truck. Ignored once one is on the road or the run is already banked —
-- a second steal shouldn't queue a second truck behind the one you're chasing.
function GetawayController._arm(self, delay: number)
	if not self._active or self._wrecked or self._state ~= "off" then
		return
	end
	self._state = "waiting"
	self._spawnAt = os.clock() + delay
	--- Kept only so the countdown on screen has a denominator; nothing in the mechanism reads it.
	--- See `getCountdown`.
	self._armWait = delay
end

--[[ PUBLIC (GetawayHudController) — how long until the next truck, and how long the whole wait was.

	Both nil at every moment there is nothing to count down to: no race, a wreck, a truck already on
	the road, a run already banked. The caller draws nothing rather than drawing a zero.

	REAL SECONDS, NOT SCALED ONES, and that is not an oversight — it is the same call `_loop` makes
	when it applies `TimeScale` BELOW the spawn arm rather than above it. The wait for a truck runs
	on the wall clock so that holding the world (the tutorial's freeze, a slow-motion beat) cannot
	silently stretch the gap between one truck and the next. A countdown drawn off anything else
	would disagree with the thing it is counting down to.

	THE REMAINDER CAN EXCEED THE TOTAL, and a caller has to expect it. When every candidate spot for
	a truck is standing inside the obstacle course `_loop` pushes `_spawnAt` out by a second and
	tries again, which it may do more than once — so the wait genuinely got longer than it was
	advertised as. Correcting for that here would mean either lying about the remainder or rewriting
	the denominator mid-count; both are worse than letting the display clamp, which is where a stale
	readout belongs (DriveController's speedo makes the same argument). ]]
function GetawayController.getCountdown(self): (number?, number?)
	if not self._active or self._wrecked or self._state ~= "waiting" then
		return nil, nil
	end
	return math.max(self._spawnAt - os.clock(), 0), self._armWait
end

-- === Banking ================================================================

--[[ Is the car far enough into the bay to call this a getaway?

	Tested in the TRUCK'S object space, where the bay is an axis-aligned box and the geometry is
	trivial: local +Z is the truck's tail (a CFrame's LookVector is its -Z), so driving in means
	DECREASING Z, and `Bank.Depth` is how far past the rear sill the hull centre has to get. ]]
function GetawayController._inBay(self): boolean
	local hull = self._hitBox or (self._playerCar and self._playerCar.PrimaryPart)
	if not (hull and hull.Parent and self._rootCF) then
		return false
	end
	local bank = GetawayConfig.Bank
	local d = self._rootCF:PointToObjectSpace(hull.Position) - self._zoneCentre
	local h = self._zoneHalf
	return math.abs(d.X) <= h.X - bank.Margin
		and math.abs(d.Y) <= h.Y - bank.Margin
		and d.Z <= h.Z - bank.Depth
		and d.Z >= -h.Z
end

--[[ Freeze the car onto the bay floor so it rides out with the truck.

	It has to be frozen, and the reason is that the truck is scripted rather than simulated: an
	anchored floor moved by CFrame writes does not push a car resting on it, so a car left to physics
	would simply be left behind — the truck would drive out from under it and it would drop out of
	the back of its own getaway.

	The rider needs nothing remembered and nothing carried: the seat weld takes them along with every
	`PivotTo` the ride makes, anchored or not. `_rideBay` has the measurement and the bug that came
	of assuming otherwise. ]]
function GetawayController._freezeCarIntoBay(self)
	local car = self._playerCar
	-- BEFORE anything is anchored, because anchoring is what zeroes it: how fast the car was
	-- actually closing on the truck is what `_planBerth` times the slide against.
	local hull = self._hitBox or car.PrimaryPart
	local entrySpeed = hull.AssemblyLinearVelocity:Dot(self._info.forward) - GetawayConfig.Speed
	self:_anchorCar()
	self._bayOffset = self._rootCF:ToObjectSpace(car:GetPivot())
	self:_planBerth(hull, entrySpeed)
end

-- An anchored car can still be moving under this controller. The speedometer must use the
-- scripted climb speed instead of showing a false stop; TimeScale still makes a paused climb 0.
function GetawayController.getBoardingSpeed(self, seat: BasePart): number?
	local b = self._boarding
	if b and seat:IsDescendantOf(b.car) then
		return (self:_speedNow() + b.speed) * TimeScale.get()
	end
	return nil
end

-- Both ramp capture and ordinary bay entry must remember the ORIGINAL anchors. Re-anchoring
-- during their handoff would remember true and leave the car frozen after teardown.
function GetawayController._anchorCar(self)
	if self._carAnchors then
		return
	end
	local car = self._playerCar
	-- Anchor each rigid assembly once. Writing Anchored on every visual panel repeatedly rebuilds
	-- the same assembly's physics state and is the main-thread spike that used to land on entry.
	local anchors = {}
	for _, p in car:GetDescendants() do
		if p:IsA("BasePart") then
			local root = p.AssemblyRootPart or p
			if anchors[root] == nil then
				anchors[root] = root.Anchored
			end
		end
	end
	for root in anchors do
		if root.Parent then
			root.Anchored = true
		end
	end
	self._carAnchors = anchors
end

--[[ Where the car comes to rest aboard, and how long it takes to get there.

	`Bank.Depth` deliberately fires while the car is still half out of the bay — that is the right
	trigger, because a bank that waited for the whole car inside would fire against the bulkhead
	instead of on the way in. It is the wrong place to STOP, though: on the real model the hull
	centre gets 6 studs past the sill with 4.29 studs of tail still hanging out, so freezing the car
	on the spot shuts the doors through its own boot lid.

	The berth is therefore computed rather than taken from where the bank happened, and it squares
	the car up as well as pushing it in — pitch and roll off the ramp lip, the lane it drifted in on,
	and any yaw all resolve to sitting straight in the bay, which is the pose a loaded car should be
	found in. Everything is in the truck's object space, where the bay is axis-aligned and local +Z
	is the tail, so "further in" is smaller Z.

	THE TIME IS SOLVED, NOT CHOSEN. `_stepDock` eases Quad/Out, which leaves at `2 * distance / time`;
	solving that for `time` starts the slide at exactly the speed the car arrived with, so the
	instant physics is taken away is not an instant you can see. The clamp covers the two ends the
	maths doesn't: crawling in at nothing, and the boosted approach that lands most of the way in
	already. ]]
function GetawayController._planBerth(self, hull: BasePart, entrySpeed: number)
	local bank = GetawayConfig.Bank
	local from = self._bayOffset
	local hullLocal = self._rootCF:ToObjectSpace(hull.CFrame)
	-- The hull's rigid offset from the car's pivot. The berth is expressed as a HULL pose, because
	-- the hull is what the bay was measured against; this converts it back to a pivot to ride at.
	local hullFromPivot = from:ToObjectSpace(hullLocal)

	-- Square to the truck (identity rotation here IS square: both face down the road), centred
	-- across the bay, at the Y the car is already resting at — it drove in on the floor, so that
	-- height is measured rather than guessed. Clamped off BOTH end faces so a body longer than the
	-- bay can never be pushed through the bulkhead to satisfy the clearance.
	local halfLen = hull.Size.Z * 0.5
	local near = self._zoneCentre.Z + self._zoneHalf.Z - halfLen - bank.DockClearance
	local far = self._zoneCentre.Z - self._zoneHalf.Z + halfLen + bank.DockClearance
	-- near < far means the car is longer than the bay minus its clearances; centre it and take the
	-- best available rather than honouring one end face at the other's expense.
	local z = if near >= far then near else self._zoneCentre.Z
	local to = CFrame.new(self._zoneCentre.X, hullLocal.Y, z) * hullFromPivot:Inverse()

	self._dockFrom, self._dockTo, self._dockT = from, to, 0
	local distance = (to.Position - from.Position).Magnitude
	self._dockTime = math.clamp(
		if entrySpeed > 0.1 then 2 * distance / entrySpeed else bank.DockTimeMax,
		bank.DockTimeMin,
		bank.DockTimeMax
	)
end

-- Advance the berth, and release the mechanism to shut once the tail is safely inside.
function GetawayController._stepDock(self, dt: number)
	if self._dockT >= 1 then
		return
	end
	local bank = GetawayConfig.Bank
	self._dockT = math.min(1, self._dockT + dt / self._dockTime)
	if self._dockT >= 1 then GameplayFeedback.play("Docked") end
	local eased = TweenService:GetValue(self._dockT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	self._bayOffset = self._dockFrom:Lerp(self._dockTo, eased)
	if self._dockT >= bank.CloseAfterDock then
		self._openGoal = 0
	end
end

-- Give the car back to physics. Idempotent — the table is cleared as it goes — and safe on parts
-- the race has already destroyed.
function GetawayController._thawCar(self)
	local boarding = self._boarding
	self._boarding = nil
	self._boardingPrevious = nil
	for part, canCollide in self._boardingCollisions or {} do
		if part.Parent then
			part.CanCollide = canCollide
		end
	end
	self._boardingCollisions = nil
	local car = self._boardingCar
	self._boardingCar = nil
	if car and car.Parent then
		car:SetAttribute(GetawayConfig.Boarding.Attribute, nil)
	end
	local anchors = self._carAnchors
	self._carAnchors = nil
	for part, wasAnchored in anchors or {} do
		if part.Parent then
			part.Anchored = wasAnchored
		end
	end
	-- A cancelled climb returns a moving car, not a zero-speed obstacle under the truck. Resume
	-- clears the steering shim's previous velocity sample before physics gets this new one.
	local drive = self._boardingDrive
	self._boardingDrive = nil
	if drive then
		drive:resume()
	end
	if boarding and car and car.Parent and car.PrimaryPart and self._info then
		car.PrimaryPart.AssemblyLinearVelocity = self._info.forward * (self:_speedNow() + boarding.speed)
		car.PrimaryPart.AssemblyAngularVelocity = Vector3.zero
	end
end

--[[ Hold the car (and the driver in it) at the pose it banked in, in the truck's frame.

	THE DRIVER RIDES ALONG ON THE `PivotTo`, with nothing else doing. The stock `SeatWeld` joins
	their `HumanoidRootPart` to the `VehicleSeat`, so moving the model moves the rider with it,
	exactly, on the same frame — anchored or not (measured: car 4.00, rider 4.00, the rider's offset
	from the car's pivot unchanged by 0.00).

	This used to carry them by hand, writing `delta * part.CFrame` over a list of their parts. A
	CHARACTER IS ONE RIGID ASSEMBLY, so each of those writes moved the WHOLE body — 19 BaseParts,
	so `delta` was applied nineteen times, EVERY FRAME OF THE RIDE, dragging the `VehicleSeat` out of
	the car with them. `StealController._finish` and `DriveController._resetUpright` carried the same
	step for the same stated reason; all three are gone. If a rider ever genuinely does need
	carrying, move the MODEL once, or dedupe on `AssemblyRootPart` the way
	`RoadController._shiftWorld` does. Never per part. ]]
function GetawayController._rideBay(self)
	local car = self._playerCar
	if not (car and car.Parent) then
		return
	end
	car:PivotTo(self._rootCF * self._bayOffset)
end

--[[ You're in. Berth the car, shut the mechanism behind it, and tell the server.

	The server is told IMMEDIATELY rather than after the doors close, because the first thing it does
	is cut the driving controls — leaving them live through the beat would let you drive out of your
	own getaway. The beat itself is covered by `RaceConfig.BankHoldTime` on the far side, which is
	what the fade waits for.

	THE MECHANISM IS NOT TOLD TO SHUT HERE, which it used to be. The bank fires with the car's tail
	still outside the sill (see `_planBerth`), so starting the doors on this frame closed them
	through the car. `_stepDock` releases them once the berth is far enough along. ]]
--[[ The bank flash (`GetawayConfig.BankFlash`): light, a column of it and sparkles out of the bay, in
	the banked car's rarity colour and bigger the rarer it is. An anchored, invisible, non-colliding
	holder at the bay's centre, gone after `Seconds`. ]]
function GetawayController._bankFlash(self)
	local cfg = GetawayConfig.BankFlash
	if not (cfg.Enabled and self._rootCF and self._playerCar) then
		return
	end
	local _, band = CarRarity.of(self._playerCar:GetAttribute("Body"))
	local colour = CarRarity.colourOf(band)
	local up = band - 1
	local at = self._rootCF:PointToWorldSpace(self._zoneCentre)

	local holder = Instance.new("Part")
	holder.Name = "BankFlash"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.CFrame = CFrame.new(at)
	holder.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = colour
	light.Brightness = cfg.Brightness + cfg.PerBand * up
	light.Range = cfg.Range
	light.Shadows = false
	light.Parent = holder
	local fade = TweenInfo.new(cfg.Seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(light, fade, { Brightness = 0 }):Play()

	local height = cfg.BeamHeight + cfg.BeamPerBand * up
	local beam = Instance.new("Part")
	beam.Name = "BankBeam"
	beam.Shape = Enum.PartType.Cylinder
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = colour
	beam.Transparency = 0.35
	beam.Size = Vector3.new(height, cfg.BeamWidth, cfg.BeamWidth)
	beam.CFrame = CFrame.new(at + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	beam.Parent = holder
	TweenService:Create(beam, fade, { Transparency = 1, Size = Vector3.new(height, cfg.BeamWidth * 0.2, cfg.BeamWidth * 0.2) }):Play()

	local attachment = Instance.new("Attachment")
	attachment.Parent = holder
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(colour)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.7, 1.3)
	emitter.Speed = NumberRange.new(12, 26)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, -14, 0)
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(cfg.Sparkles + cfg.SparklesPerBand * up)

	task.delay(cfg.Seconds + 1.4, function()
		holder:Destroy()
	end)
end

function GetawayController._bank(self)
	self._state = "banked"
	local boarding = self._boarding
	if boarding then
		self._boarding = nil
		-- Already anchored and level on the floor. Keep its original restore table and pass the
		-- scripted closing speed, since an anchored hull cannot report that speed itself.
		self:_planBerth(boarding.hull, boarding.speed)
	else
		self:_freezeCarIntoBay()
	end
	--- Played when the doors start to shut, not now (`_stepMechanism`).
	self._bankSfxArmed = true
	self:_bankFlash()

	--[[ Sent as-is, nils included. All three attributes are stamped by `StealController._finish` and by
		nothing else, so a car carrying none was never stolen — only reachable with
		`Spawn.RequireSteal` off, i.e. while testing the truck — and inventing a tier here would put a
		car the player never earned into their garage.

		THE BODY GOES WITH IT because the tier alone cannot say which car to park: a tier is nine
		different models. The server checks the pair against its own roster and refuses a mismatch,
		so sending both is what lets it reject a hatchback claiming a supercar's price.

		THE PAINT GOES WITH IT so the car on your podium is the one you actually stole, down to the
		colour (`PaintConfig`). It is the one value of the three that is purely cosmetic, so the
		server checks it differently: it cannot be verified — nothing about this run can, traffic
		being client-sided — but it CAN be bounded to a colour that body's pool allows, which is all a
		colour needs. A lie buys a paint the road would have handed out anyway. ]]
	local tier = self._playerCar:GetAttribute("Tier")
	local body = self._playerCar:GetAttribute("Body")
	local paint = self._playerCar:GetAttribute("Paint")
	--[[ THE FOURTH, and the only one of the four that is worth money on its own: the weather's mark
		on this car (`WeatherConfig`). It multiplies the run's whole payout and then rides into the
		save file, so unlike the paint it cannot simply be bounded to something harmless — the server
		asks `WeatherService` whether the road this player was driving could have produced it at all,
		which is the one check standing between a client and a five-times bank. See that service's
		`couldHaveSpawned`.

		nil for an ordinary car, which is nearly all of them. ]]
	local mutation = self._playerCar:GetAttribute("Mutation")
	--- The police stand down first (`PoliceController.onBanked`): nothing arms on a car in the van,
	--- and the server hears it ahead of the bank, so it does not hold the bank for a chase.
	local police = Shard.get("PoliceController")
	if police then
		police:onBanked()
	end
	self:getRemoteEvent("GetawayBanked"):Fire(tier, body, paint, mutation)

	--[[ Hand the car to the results screen while it still exists. THIS IS THE LAST MOMENT IT DOES:
		the remote above starts `RaceService.bankRun`, which destroys the car once the return fade has
		run — several seconds before the screen that wants to show it goes up. `RaceUIController` takes
		a stripped copy of the dress here and shows it turning above the payout (see its header). ]]
	local results = self._results or Shard.get("RaceUIController")
	if results then
		results:setTrophy(self._playerCar)
	end
	self.log:info(string.format(
		"Got away with %s — drove it into the truck.",
		if type(tier) == "number" then string.format("a Tier %d %s", tier, tostring(body)) else "a car of no tier"
	))
end

-- === The exit shot ==========================================================

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

--[[ The end panel is up over a getaway (`RaceEndPanel`): hand the camera the shot of the truck
	driving off with you in it (`GetawayConfig.ExitShot`). The race camera clears it at the race's
	end, which is after the fade home, so nothing here has to take it back. ]]
function GetawayController._directExit(self)
	if self._state ~= "banked" then
		return
	end
	local cam = Shard.get("RaceCameraController")
	if not (cam and cam.setCinematic) then
		return
	end
	self._exitAt = os.clock()
	self._weaveAt = self._exitAt + GetawayConfig.Exit.Weave.StartAfter
	-- The shot's two soft followers start on the truck, so the blend in has nothing to catch up.
	self._camCross, self._lookCross = self._cross, self._cross
	-- The box it rams with, measured once in its own frame (doors and ramp are stowed by now).
	local _, size = self._model:GetBoundingBox()
	self._truckHalf = size / 2
	cam:setCinematic(function()
		return self:_exitShot()
	end)
	-- The run for it (`GetawayConfig.Exit`): traffic stops getting out of the way.
	if self._traffic then
		self._traffic:setAvoid(nil)
	end
end

--- How fast the truck is going: the cruise, until the panel opens and it makes its run.
function GetawayController._speedNow(self): number
	local base = GetawayConfig.Speed
	if not self._exitAt then
		return base
	end
	local cfg = GetawayConfig.Exit
	return base + (cfg.Speed - base) * smoothstep((os.clock() - self._exitAt) / cfg.Accel)
end

--[[ Any traffic car the running truck reaches goes flying (`TrafficController.ram`). Measured in the
	truck's own frame: within its width (plus the car's) and from its tail to `Exit.Reach` past its
	nose. Cars already thrown are physical and skipped by `ram` itself. ]]
function GetawayController._ramTraffic(self)
	local traffic, root, info = self._traffic, self._rootCF, self._info
	if not (traffic and root and info and self._exitAt and self._truckHalf) then
		return
	end
	local cfg = GetawayConfig.Exit
	local cars = traffic:getCars()
	if not cars then
		return
	end
	local halfWidth, halfLength = self._truckHalf.X, self._truckHalf.Z
	local speed = self:_speedNow()
	for _, rec in cars do
		local car = rec.hit
		if rec.physical or not (car and car.Parent) then
			continue
		end
		local p = root:PointToObjectSpace(car.Position)
		-- A shell's Hit box is not authored on one axis order, so its narrow side is its width.
		local carWidth = math.min(car.Size.X, car.Size.Z)
		local carLength = math.max(car.Size.X, car.Size.Z)
		local reachSide = halfWidth + carWidth / 2
		local nose = -(halfLength + carLength / 2 + cfg.Reach)
		if math.abs(p.X) < reachSide and p.Z > nose and p.Z < halfLength then
			local side = if p.X >= 0 then 1 else -1
			local shove = info.forward * (speed + cfg.Ram.Ahead - rec.speed)
				+ root.RightVector * (side * cfg.Ram.Side)
				+ Vector3.yAxis * cfg.Ram.Lift
			local at = root:PointToWorldSpace(Vector3.new(p.X - side * carWidth / 2, 0, nose + cfg.Reach))
			traffic:ram(rec, shove, at)
		end
	end
end

-- === The weave ==============================================================

-- Exponential ease toward `target`: frame-rate independent, settles at `gain` per second.
local function approach(current: number, target: number, dt: number, gain: number): number
	return target + (current - target) * math.exp(-gain * dt)
end

-- Back in the lane it spawns in, straight and level. Called on every spawn, so a truck re-used for
-- the next appearance never carries the last run's lean or lane.
function GetawayController._resetWeave(self)
	self._cross = GetawayConfig.Lane
	self._targetCross = GetawayConfig.Lane
	self._crossVel = 0
	self._roll = 0
	self._weaveAt = math.huge
end

--[[ Studs of clear road ahead of the truck's nose in the lane centred at `laneCross`, capped at the
	lookahead. Traffic counts if either where it IS or where it is steering to is in the lane, so a
	car halfway through its own lane change blocks both. Cars already thrown are physics now and
	skipped; the steal target never moves and the ram refuses it, but it is still in the way.

	The obstacle course is one box query over the same folders the spawn check uses. `MaxParts = 1`
	means it reports A part rather than the nearest one, which errs toward calling the lane blocked
	earlier than it is, the safe way round. ]]
function GetawayController._laneClear(self, laneCross: number): number
	local cfg = GetawayConfig.Exit.Weave
	local info = self._info
	local nose = self._along + self._length * 0.5
	local clear = cfg.Lookahead
	local cars = self._traffic and self._traffic:getCars()
	if cars then
		for _, rec in cars do
			if rec.physical then
				continue
			end
			local ahead = rec.along - nose
			-- A little behind the nose still counts: a car beside the cab is a car you'd swerve into.
			if ahead > -6 and ahead < clear then
				local off = math.min(math.abs(rec.cross - laneCross), math.abs((rec.targetCross or rec.cross) - laneCross))
				if off < cfg.LaneHalf then
					clear = math.max(ahead, 0)
				end
			end
		end
	end
	if #self._obstacleParams.FilterDescendantsInstances > 0 then
		local centre = self:_worldPos(nose + clear * 0.5, laneCross) + Vector3.yAxis * (PROBE_HEIGHT * 0.5)
		local frame = CFrame.fromMatrix(centre, info.cross, Vector3.yAxis)
		local hit = workspace:GetPartBoundsInBox(frame, Vector3.new(cfg.LaneHalf * 2, PROBE_HEIGHT, clear), self._obstacleParams)[1]
		if hit then
			clear = math.clamp(hit.Position:Dot(info.forward) - nose, 0, clear)
		end
	end
	return clear
end

--[[ Can the exit shot follow the truck into this lane? The camera ends `sin(To.Angle) * To.Distance`
	studs to one side of the truck and may not leave the road (`ExitShot.MaxCross`), so a lane on the
	camera's side of the road would drag it over the barrier. The truck simply never goes there: a
	director keeps the action where the camera is. ]]
function GetawayController._laneShootable(self, laneCross: number): boolean
	local shot = GetawayConfig.ExitShot
	local side = math.sin(math.rad(shot.To.Angle)) * shot.To.Distance
	return math.abs(laneCross + side) <= shot.MaxCross
end

--[[ Pick a lane every `Reconsider` seconds and drive the truck toward it (`GetawayConfig.Exit.Weave`).

	ONE LANE AT A TIME, and only once the last move has finished, so it reads as a driver taking gaps
	rather than as a truck sliding about. Staying is the default: a neighbour has to offer `Better`
	studs more road to be worth the swerve, which is also what keeps two equally clear lanes from
	trading the truck back and forth.

	The sideways motion is a capped spring: a wanted speed proportional to the distance left, eased
	toward at `LateralAccel`, so every lane change leaves gently, cruises, and arrives gently. `_roll`
	is that sideways ACCELERATION as a -1..1 share, smoothed, which is what a body actually leans on. ]]
function GetawayController._stepWeave(self, dt: number)
	local cfg = GetawayConfig.Exit.Weave
	if not (cfg.Enabled and self._exitAt and self._info) or dt <= 0 then
		return
	end
	local lanes = ObstacleConfig.Lanes
	local now = os.clock()
	if now >= self._weaveAt and math.abs(self._targetCross - self._cross) < 1 then
		self._weaveAt = now + cfg.Reconsider
		local index, best = 1, math.huge
		for i, offset in lanes do
			local d = math.abs(offset - self._targetCross)
			if d < best then
				index, best = i, d
			end
		end
		local stay = self:_laneClear(lanes[index])
		if stay < cfg.Lookahead then
			local pick, pickClear = nil, stay + cfg.Better
			for _, i in { index - 1, index + 1 } do
				if lanes[i] and self:_laneShootable(lanes[i]) then
					local c = self:_laneClear(lanes[i])
					-- Ties go to the lane nearer the middle of the road, which keeps it off the verge.
					if c > pickClear or (pick and c == pickClear and math.abs(lanes[i]) < math.abs(lanes[pick])) then
						pick, pickClear = i, c
					end
				end
			end
			if pick then
				self._targetCross = lanes[pick]
			end
		end
	end

	local want = math.clamp((self._targetCross - self._cross) * cfg.Gain, -cfg.MaxLateral, cfg.MaxLateral)
	local step = math.clamp(want - self._crossVel, -cfg.LateralAccel * dt, cfg.LateralAccel * dt)
	self._crossVel += step
	self._cross += self._crossVel * dt
	self._roll = approach(self._roll, step / (cfg.LateralAccel * dt), dt, cfg.RollGain)
end

-- The shot's soft followers across the road (`ExitShot.CrossGain` / `LookGain`). Road-frame scalars,
-- so a rebase cannot strand them.
function GetawayController._stepExitCam(self, dt: number)
	if not (self._exitAt and self._camCross) then
		return
	end
	local cfg = GetawayConfig.ExitShot
	-- Followed at the NOSE, not the centre: mid-swerve the truck is yawed, so its front sits
	-- `tan(yaw) * half length` across from its centre, and the shot is framed on the front. Tracking
	-- the centre let the cab swing from 26% to 41% across, under the panel.
	local nose = self._cross + self._crossVel / math.max(self:_speedNow(), 1) * self._length * 0.5
	self._camCross = approach(self._camCross, nose, dt, cfg.CrossGain)
	self._lookCross = approach(self._lookCross, nose, dt, cfg.LookGain)
end

--- This frame's exit shot for `RaceCameraController`, or nil once the truck is gone.
function GetawayController._exitShot(self)
	local root, info, since = self._rootCF, self._info, self._exitAt and os.clock() - self._exitAt
	if not (self._state == "banked" and root and info and since and self._camCross) then
		return nil
	end
	local cfg = GetawayConfig.ExitShot
	local u = smoothstep(since / cfg.Sweep)
	local function at(key: string): number
		return cfg.From[key] + (cfg.To[key] - cfg.From[key]) * u
	end
	-- Placed in the road frame off the truck's along, but across the road off the soft followers, so
	-- the truck can weave inside the frame instead of the frame weaving round the truck.
	local angle = math.rad(at("Angle"))
	local distance = at("Distance")
	-- Held over the road. The weave already keeps to lanes the camera can follow (`_laneShootable`), so
	-- this only catches a truck that was somewhere else when the shot began.
	local camCross = math.clamp(self._camCross + math.sin(angle) * distance, -cfg.MaxCross, cfg.MaxCross)
	local eye = self:_worldPos(self._along - math.cos(angle) * distance, camCross) + Vector3.yAxis * at("Up")
	--[[ The lens: aimed at the cab, then turned away from it by `turn * u` in the horizontal plane.
		Angles here are measured from looking straight back down the road (-forward), positive toward
		the truck's side of the camera. `turn` is the gap between the cab and the final lens AT THE
		FINAL POSE, so u = 1 lands on exactly `LensYaw`, and since it is an angle off the aim rather
		than a blend toward the road axis, the truck never leaves the frame on the way round. ]]
	local look = self:_worldPos(self._along + cfg.LookAhead, self._lookCross) + Vector3.yAxis * cfg.LookUp
	local side = if math.sin(angle) >= 0 then 1 else -1
	local toward = -info.cross * side -- from the camera's side of the road toward the truck
	local to = look - eye
	local flat = to - Vector3.yAxis * to.Y
	local aim = math.atan2(flat:Dot(toward), flat:Dot(-info.forward))
	local finalAngle = math.rad(cfg.To.Angle)
	local finalAim = math.atan2(
		math.abs(math.sin(finalAngle)) * cfg.To.Distance,
		-math.cos(finalAngle) * cfg.To.Distance - cfg.LookAhead
	)
	local turned = aim - (finalAim - math.rad(cfg.LensYaw)) * u
	local dir = (-info.forward * math.cos(turned) + toward * math.sin(turned)) * flat.Magnitude
		+ Vector3.yAxis * to.Y
	return {
		cframe = CFrame.lookAt(eye, eye + dir),
		fov = cfg.Fov,
		weight = smoothstep(since / cfg.BlendIn),
	}
end

-- === Loop / lifecycle =======================================================

--[[ === THE CLIMB IS OWNED BEFORE THE BANK — 2026-10-04 =========================

	The old handoff waited until the car was six studs inside the bay. Until then a dynamic car
	fought both a CFrame-moved ramp and DriveController's world-level pitch correction. A valid
	approach now hands off at the foot, with the original pose preserved on that frame. Nothing
	is awarded until _inBay succeeds at the far end of the climb.

	The capture uses the actual ramp's top plane and projected width, not a second authored
	trigger. A missing/unsuitable ramp falls back to the original physical entry. ]]
--[[ `rescue` (2026-10-09, `GetawayConfig.Rescue`): the same capture from wherever the car already is
	on the ramp, with the entry tests that only make sense for a clean approach dropped — the sweep
	across the foot, the closing speed, the doorway margin, the ramp having gone solid — and a wider
	yaw allowance. The climb itself is unchanged and centres the car, so a capture from the plate's
	edge still ends square in the bay. ]]
function GetawayController._tryBoard(self, rescue: boolean?): boolean
	local cfg = GetawayConfig.Boarding
	local car, hull, ramp = self._playerCar, self._hitBox, self._ramp
	local drive = Shard.get("DriveController")
	local steal = Shard.get("StealController")
	local seat = car and car:FindFirstChildWhichIsA("VehicleSeat", true)
	if not cfg.Enabled or self._wrecked or TimeScale.get() <= 0 or self._tiltRaw < 1 or self._slideRaw < 1
		or not hull or not ramp or (not rescue and not ramp.part.CanCollide)
		or not seat or not seat.Occupant or seat.Occupant.Health <= 0
		or not drive or not drive:isDriving() or car.PrimaryPart.Anchored
		or (steal and select(1, steal:getFlight()) ~= "idle") then
		self._boardingPrevious = nil
		return false
	end
	local root = self._rootCF
	local localHull = root:ToObjectSpace(hull.CFrame)
	local half = projectHalf(localHull, hull.Size)
	local sample = {
		x = localHull.X, y = localHull.Y, nose = localHull.Z - half.Z,
		halfWidth = half.X, halfHeight = half.Y,
	}
	local previous = self._boardingPrevious
	self._boardingPrevious = sample
	local closing = hull.AssemblyLinearVelocity:Dot(root.LookVector) - self:_speedNow() * TimeScale.get()
	local look = localHull.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local maxYaw = if rescue then GetawayConfig.Rescue.MaxYawDeg else cfg.MaxYawDeg
	if (not rescue and closing < cfg.MinClosingSpeed)
		or flatLook.Magnitude < 0.01
		or -flatLook.Unit.Z < math.cos(math.rad(maxYaw))
		or localHull.UpVector.Y < math.cos(math.rad(cfg.MaxTiltDeg)) then
		self._boardingPrevious = nil
		return false
	end

	local frame = self:_rampFrame()
	if not frame then
		return false
	end
	local nearZ, farZ, height = frame.nearZ, frame.farZ, frame.height
	if not rescue and not GetawayBoarding.enters(previous, sample, farZ, frame.x, frame.halfWidth, cfg) then
		return false
	end
	-- Require the hull to fit the doorway as well as the ramp; their centres need not coincide. A
	-- rescue only asks that it FITS at all — the climb centres it on the way up.
	local offCentre = if rescue then 0 else math.abs(localHull.X - self._zoneCentre.X)
	if offCentre + half.X > self._zoneHalf.X - cfg.SideMargin then
		return false
	end
	local wheelbase = hull.Size.Z * cfg.WheelbaseFraction
	local bank = GetawayConfig.Bank
	local endZ = math.min(self._zoneCentre.Z + self._zoneHalf.Z - bank.Depth - 0.1, nearZ - wheelbase * 0.5)
	-- Do not guide an oversized rig into the bulkhead or capture a car already beyond the climb.
	if endZ - hull.Size.Z * 0.5 <= self._zoneCentre.Z - self._zoneHalf.Z or localHull.Z <= endZ then
		return false
	end
	local nearY, farY = height(nearZ), height(farZ)
	-- The crossing's resting height is measured on the road, before the ramp can compress the
	-- suspension. Keeping it relative to the road also avoids inheriting the ramp's thickness.
	--- A rescue's last sample is already ON the ramp, so it uses the height last measured on the road
	--- behind it (`_loop`), or half the hull for a car that was never seen there.
	local clearance = if rescue then (self._roadClearance or half.Y) elseif previous then previous.y else localHull.Y
	local endY = nearY + clearance
	if math.abs(endY - self._zoneCentre.Y) > self._zoneHalf.Y - bank.Margin then
		return false
	end
	local supportY = GetawayBoarding.support(localHull.Z, wheelbase, nearZ, farZ, nearY, farY)
	self._boarding = {
		car = car, hull = hull, seat = seat, rider = seat.Occupant, from = localHull,
		hullFromPivot = car:GetPivot():ToObjectSpace(hull.CFrame),
		z = localHull.Z, endZ = endZ, wheelbase = wheelbase,
		nearZ = nearZ, farZ = farZ, nearY = nearY, farY = farY,
		clearance = clearance, correction = localHull.Y - supportY - clearance,
		speed = math.clamp(closing, cfg.MinSpeed, cfg.MaxSpeed),
	}
	self._boardingDrive = drive
	self._boardingCar = car
	GameplayFeedback.play("RampCaptured")
	car:SetAttribute(cfg.Attribute, true)
	drive:suspend()
	self:_anchorCar()
	-- The ramp and the car are both posed during the climb. Suppress contact until release so
	-- their intersection cannot kick a passing physical car or the rider's chassis assemblies.
	self._boardingCollisions = {}
	for _, part in car:GetDescendants() do
		if part:IsA("BasePart") then
			self._boardingCollisions[part] = part.CanCollide
			part.CanCollide = false
		end
	end
	self._bayOffset = root:ToObjectSpace(car:GetPivot())
	return true
end

--[[ Truck-local offsets survive RoadController's rebases without accumulating error. The
	first pose is the incoming pose exactly; over BlendDistance it settles onto front/rear axle
	support heights. Both axles reach the flat floor before the ordinary bank/dock handoff. ]]
function GetawayController._stepBoard(self, dt: number)
	local b = self._boarding
	if not b then
		return
	end
	if self._wrecked or b.car ~= self._playerCar or not b.car.Parent or not b.hull.Parent
		or not b.seat.Parent or b.seat.Occupant ~= b.rider or b.rider.Health <= 0 then
		self:_thawCar()
		return
	end
	b.z = math.max(b.endZ, b.z - b.speed * dt)
	local distance = b.from.Z - b.z
	local t = math.clamp(distance / GetawayConfig.Boarding.BlendDistance, 0, 1)
	local blend = t * t * (3 - 2 * t)
	local y, pitch = GetawayBoarding.support(b.z, b.wheelbase, b.nearZ, b.farZ, b.nearY, b.farY)
	local x = b.from.X + (self._zoneCentre.X - b.from.X) * blend
	local rotation = b.from.Rotation:Lerp(CFrame.Angles(pitch, 0, 0), blend)
	local pose = CFrame.new(x, y + b.clearance + b.correction * (1 - blend), b.z) * rotation
	self._bayOffset = pose * b.hullFromPivot:Inverse()
	self:_rideBay()
	if b.z <= b.endZ then
		--- The loose test as well (`GetawayConfig.Stranded`): a climb that ends visibly aboard banks.
		if self:_inBay() or (GetawayConfig.Stranded.Enabled and self:_inBayLoose()) then
			self:_bank()
		else
			-- A changed/malformed bay must never leave an anchored car waiting forever or award
			-- a bank merely because an animation timer finished.
			self:_thawCar()
		end
	end
end

-- === Never stuck on the ramp (`GetawayConfig.Rescue` / `Stranded` / `Shelter`) =================

--[[ The deployed ramp plate in the truck's object space: its near (sill) and far (foot) Z, its centre
	X and usable half-width, and the height of its top face at any Z. nil for a missing or degenerate
	plate. Pure. Shared by the ordinary capture, the rescue and the shelter, so all three agree on
	where the ramp IS. The authored plate can have any local axis pointing through its thickness, so
	the face most upward in the truck frame is picked rather than assuming the part's Y. ]]
function GetawayController._rampFrame(self)
	local ramp, root = self._ramp, self._rootCF
	if not (ramp and ramp.part and ramp.part.Parent and root) then
		return nil
	end
	local plate = root:ToObjectSpace(ramp.part.CFrame)
	local size = ramp.part.Size
	local extent = projectHalf(plate, size)
	local normal, thickness = plate.UpVector, size.Y
	if math.abs(plate.RightVector.Y) > math.abs(normal.Y) then
		normal, thickness = plate.RightVector, size.X
	end
	if math.abs(plate.LookVector.Y) > math.abs(normal.Y) then
		normal, thickness = plate.LookVector, size.Z
	end
	if normal.Y < 0 then
		normal = -normal
	end
	local nearZ, farZ = plate.Z - extent.Z, plate.Z + extent.Z
	if normal.Y < 0.5 or farZ - nearZ < 1 then
		return nil
	end
	local face = plate.Position + normal * (thickness * 0.5)
	return {
		nearZ = nearZ,
		farZ = farZ,
		x = plate.X,
		halfWidth = math.min(extent.X, self._zoneHalf.X),
		height = function(z: number): number
			return face.Y - (z - face.Z) * normal.Z / normal.Y
		end,
	}
end

--- The hull's centre in the truck's object space, or nil.
function GetawayController._hullLocal(self): Vector3?
	local hull = self._hitBox or (self._playerCar and self._playerCar.PrimaryPart)
	if not (hull and hull.Parent and self._rootCF) then
		return nil
	end
	return self._rootCF:PointToObjectSpace(hull.Position)
end

--[[ How high the hull rides over the road, measured while the car is plainly on the road behind the
	ramp and level — the rescue's stand-in for the entry sample it never got (`_tryBoard`). ]]
function GetawayController._measureRoadClearance(self)
	local frame = self._ramp and self:_rampFrame()
	local hull = self._hitBox or (self._playerCar and self._playerCar.PrimaryPart)
	if not (frame and hull and hull.Parent) then
		return
	end
	local localHull = self._rootCF:ToObjectSpace(hull.CFrame)
	if localHull.Z > frame.farZ + hull.Size.Z and localHull.UpVector.Y > 0.97 then
		self._roadClearance = localHull.Y
	end
end

--[[ Is the hull centre ON the deployed ramp — over its footprint (or `Reach` behind its foot), within
	`SideSlack` of its edges, and no more than `Above` over its surface? The rescue's question. Pure. ]]
function GetawayController._onRamp(self): boolean
	local cfg = GetawayConfig.Rescue
	if not cfg.Enabled or self._wrecked or self._tiltRaw < 1 or self._slideRaw < 1 then
		return false
	end
	local p, frame = self:_hullLocal(), self:_rampFrame()
	if not (p and frame) then
		return false
	end
	if p.Z < frame.nearZ - 0.5 or p.Z > frame.farZ + cfg.Reach then
		return false
	end
	if math.abs(p.X - frame.x) > frame.halfWidth + cfg.SideSlack then
		return false
	end
	local surface = frame.height(math.clamp(p.Z, frame.nearZ, frame.farZ))
	return p.Y <= surface + cfg.Above and p.Y >= surface - 3
end

--- The bay test WITHOUT its margins: centre inside the bay box at all. `Stranded`'s question. Pure.
function GetawayController._inBayLoose(self): boolean
	local p = self:_hullLocal()
	if not p then
		return false
	end
	local d = p - self._zoneCentre
	local h = self._zoneHalf
	return math.abs(d.X) <= h.X and math.abs(d.Y) <= h.Y and d.Z <= h.Z - 1 and d.Z >= -h.Z
end

--[[ `condition` held for `cfg.Dwell` seconds in a row, tracked in `self[field]`. The dwell is what
	lets the ordinary path act first: a clean approach is caught by `_tryBoard` or banked by `_inBay`
	on its own frame, and only a car that is STILL there after that is the fallback's business. ]]
function GetawayController._dwelt(self, field: string, cfg, condition: boolean): boolean
	if not (cfg.Enabled and condition) then
		self[field] = nil
		return false
	end
	local now = os.clock()
	self[field] = self[field] or now
	return now - self[field] >= cfg.Dwell
end

--- PUBLIC (`TestEngineController`, `RaceCameraController`): has this run banked? From the bank until the race tears down.
function GetawayController.isBanked(self): boolean
	return self._active == true and self._state == "banked"
end

--[[ PUBLIC (TrafficController, ObstacleController, PoliceController) — is the player in the truck's
	shelter, where nothing may punish them for being slow or for touching anything
	(`GetawayConfig.Shelter`)? True while climbing or banked, and while the open truck's ramp is down
	with the hull in the box behind it. Pure. ]]
function GetawayController.isSheltered(self): boolean
	local cfg = GetawayConfig.Shelter
	if not (cfg.Enabled and self._active) then
		return false
	end
	if self._boarding or self._state == "banked" then
		return true
	end
	if self._state ~= "live" or self._openGoal < 1 or self._tiltRaw < 1 then
		return false
	end
	local p, frame = self:_hullLocal(), self:_rampFrame()
	if not (p and frame) then
		return false
	end
	return math.abs(p.X - self._zoneCentre.X) <= self._zoneHalf.X + cfg.Side
		and p.Z >= self._zoneCentre.Z - self._zoneHalf.Z
		and p.Z <= frame.farZ + cfg.Behind
end

--[[ Is the getaway shut because the police are on the player (`GetawayConfig.PoliceLock`)? Latched
	once a frame by `_loop`. A chase that is peeling off ("leaving") has been survived and does not
	count. The lock only CLOSES on a frame the player is outside the shelter, which is the config's
	one grace: a car already committed to the ramp when the chase armed is let in. A soft
	`Shard.get`, because PoliceController already reads this controller and a place without police
	should cost the getaway nothing. ]]
function GetawayController._stepPoliceLock(self)
	local chased = false
	if GetawayConfig.PoliceLock.Enabled then
		local police = Shard.get("PoliceController")
		local chase = police and police:getChase()
		chased = chase ~= nil and chase.state ~= "leaving"
	end
	if not chased then
		self._policeLocked = false
	elseif not self._policeLocked and not self:isSheltered() then
		self._policeLocked = true
	end
end

--- PUBLIC (GetawayHudController) - is the truck refusing the car because of a chase? Pure.
function GetawayController.isPoliceLocked(self): boolean
	return self._active and self._policeLocked
end

-- Our car and its hull, via RoadController (which resolves the car from the seat we're welded to).
-- The Model replicates piecemeal, so the HitBox can arrive a beat after it — keep asking rather than
-- latching the first (nil) answer. Same shape as TrafficController._resolveCar.
function GetawayController._resolveCar(self): boolean
	local car = self._road:getCar()
	if car ~= self._playerCar then
		if self._boarding then
			self:_thawCar()
		end
		self._boardingPrevious = nil
		self._playerCar = car
		self._hitBox = nil
	end
	if car and not (self._hitBox and self._hitBox.Parent) then
		self._hitBox = car:FindFirstChild(ObstacleConfig.HitBoxName, true)
	end
	local valid = car ~= nil and car.Parent ~= nil and car.PrimaryPart ~= nil
	if not valid and self._boarding then
		self:_thawCar()
	end
	return valid
end

function GetawayController._loop(self, dt: number)
	if not self._active then
		return
	end
	local info = self._road:getRoadInfo()
	if not (info and self:_resolveCar()) then
		return -- road or car not up yet; nothing to place a truck against
	end
	self._info = info
	self._playerAlong = self._road:along(self._playerCar.PrimaryPart.Position)

	local now = os.clock()
	if now >= self._filterAt then
		self._filterAt = now + 0.25
		self:_refreshObstacleFilter()
	end

	self:_stepPoliceLock()

	if self._state == "waiting" then
		if self._policeLocked then
			-- Hold the wait where it is (`GetawayConfig.PoliceLock`), so the countdown on screen
			-- stops instead of running out into a truck that would not take the car.
			self._spawnAt = math.max(self._spawnAt, now) + dt
			return
		end
		if now >= self._spawnAt and not self:_spawn() then
			-- Every candidate was standing in the obstacle course. Try again shortly rather than
			-- giving up on the run's exit entirely.
			self._spawnAt = now + 1
		end
		return
	end
	if self._state == "off" then
		return
	end

	--[[ Slow motion, and the tutorial's full stop (Modules/TimeScale). Everything below this line
		MOVES the truck — its road coordinate, its door, its ramp, the dock it pulls the player's car
		through — so scaling here scales the whole vehicle at once, the way TrafficController scales
		its population in `_loop`.

		Applied BELOW the spawn arm above rather than at the top, for TrafficController's reason: the
		wait for a truck runs on real time, so a hold does not silently extend the gap between one
		blowing past and the next being offered. Only a truck that exists is stopped.

		This used to be raw `dt`, which showed up the moment the world could be held for longer than
		a flight: the beat that tells a first-timer to wait for the truck freezes the road and the
		traffic, and a truck that carried on driving through a stopped world would arrive, open, dock
		and bank the run while the card was still asking them to look at it. ]]
	dt *= TimeScale.get()

	self._along += self:_speedNow() * dt

	if self._state == "live" then
		-- Open up once the driver is close enough to watch it happen.
		local hull = self._playerCar and self._playerCar.PrimaryPart
		local closing = if hull and self._info then hull.AssemblyLinearVelocity:Dot(self._info.forward) - GetawayConfig.Speed else 0
		-- A chase shuts it (`GetawayConfig.PoliceLock`); a climb already under way is left to finish.
		local locked = self._policeLocked and not self._boarding
		--- Off the road and a fresh (held) wait, rather than shut in front of the chase.
		if locked and GetawayConfig.PoliceLock.Vanish then
			self:_despawn(true)
			return
		end
		if locked then
			self._openGoal = 0
		elseif self._openGoal < 1 and self._along - self._playerAlong <= GetawayConfig.openRange(closing) then
			self._openGoal = 1
		end
		self:_stepMechanism(dt)
		self:_place()
		if self._boarding then
			self:_stepBoard(dt)
			return
		end
		-- The tilt being home is the whole test: it is the last leg out, so a deployed tilt means the
		-- plate is out, down and on the road.
		self:_measureRoadClearance()
		if locked then
			-- Nothing below may take the car. Forget any half-measured approach so the reopened
			-- truck judges a fresh one.
			self._boardingPrevious = nil
			self._onRampSince = nil
			self._strandedSince = nil
			if self._along < self._playerAlong - self:_despawnBehind() then
				self:_despawn(true)
			end
		elseif not self._wrecked and self._tiltRaw >= 1 and self:_inBay() then
			self:_bank()
		elseif self:_tryBoard() then
			return
		elseif self:_dwelt("_onRampSince", GetawayConfig.Rescue, self:_onRamp()) and self:_tryBoard(true) then
			self._onRampSince = nil
			return
		elseif not self._wrecked and self:_dwelt("_strandedSince", GetawayConfig.Stranded, self:_inBayLoose()) then
			self._strandedSince = nil
			self:_bank()
		elseif self._along < self._playerAlong - self:_despawnBehind() then
			self:_despawn(true) -- driven past. That was a choice; taking it away is the cost.
		end
		return
	end

	-- Banked: the car settles into its berth, the truck shuts up behind it and drives on carrying it.
	-- RaceService is running the exit beat in parallel and will tear this down on RaceEnd.
	self:_stepDock(dt)
	self:_stepMechanism(dt)
	self:_stepWeave(dt)
	self:_place()
	self:_rideBay()
	self:_ramTraffic()
	self:_stepExitCam(dt)
end

--[[ A rebase moved the road out from under us (RoadController._shiftWorld). Our position is a
	road-frame scalar, so correcting it is one addition — and re-placing inside the callback keeps
	the rebase atomic for the truck too, instead of leaving a frame where it sits at the old
	coordinate. The car riding in the bay is re-placed with it. ]]
function GetawayController._onWorldShift(self, shift: Vector3)
	if not (self._active and self._info and (self._state == "live" or self._state == "banked")) then
		return
	end
	local delta = shift:Dot(self._info.forward)
	if delta == 0 then
		return
	end
	self._playerAlong += delta
	self._along += delta
	self:_place()
	if self._state == "banked" or self._boarding then
		self:_rideBay()
	end
end

-- PUBLIC (StealController) — a steal just landed, so a way out is now worth offering.
function GetawayController.onSteal(self)
	--[[ Recorded BEFORE the early return below, and recorded at all only because of the revive: a
		run can now be interrupted by a wreck and carry on, and `_onRevived` has to know whether this
		run had ever qualified for a truck. Without it, a player who stole a car, wrecked, and paid to
		keep going would have no way to bank for the rest of the run — the steal that earned them an
		exit having been forgotten by the wreck that cancelled it. ]]
	self._earned = true
	if not GetawayConfig.Spawn.RequireSteal then
		return -- already armed at race start; a steal doesn't queue a second truck
	end
	self:_arm(self:_timing(false))
end

function GetawayController._onRaceStart(self)
	self:_teardown()
	if not GetawayConfig.Enabled then
		return
	end
	if not self._road then
		self.log:warn("RoadController unavailable; there's no way out of this race.")
		return
	end
	local template = self._template
	if not template then
		self.log:warn("No getaway truck was published; this race has no exit.")
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = GetawayConfig.FolderName
	folder.Parent = workspace
	self._folder = folder

	-- One clone for the whole race, parked out of the workspace between appearances rather than
	-- rebuilt — it's a forty-part model, and a missed truck is followed by another one.
	local model = template:Clone()
	if not self:_prepare(model) then
		model:Destroy()
		return
	end
	self._model = model

	self._active = true
	self._wrecked = false
	self._state = "off"
	self._filterAt = 0
	-- "This run has qualified for a truck at least once" — true from the off when a truck is not
	-- something you have to steal for. Only `_onRevived` reads it; see `onSteal` for the why.
	self._earned = not GetawayConfig.Spawn.RequireSteal
	if not GetawayConfig.Spawn.RequireSteal then
		self:_arm(self:_timing(false))
	end

	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_loop(dt)
	end)
end

-- HP is gone. A truck already on the road keeps driving — the world carrying on is what makes the
-- wreck beat land — but it stops being an exit, and no further one is armed.
function GetawayController._onWrecked(self)
	self._wrecked = true
	if self._boarding then
		self:_thawCar()
	end
	if self._state == "waiting" then
		self._state = "off"
	end
end

--[[ ...and the wreck was paid out of (`ReviveService`): the run is going again, so there has to be
	a way out of it again.

	NOT `_onRaceStart`, which is the obvious call and the wrong one: it tears the whole thing down
	and re-clones a forty-part truck, which is a hitch in the middle of a revive and — worse — throws
	away a truck that may be on the road right now. The wreck did not touch the truck; it only
	stopped this controller treating one as an exit and cancelled the next one. So only those two
	things are undone.

	The next truck is armed on the ORDINARY delay rather than the retry's, because from the player's
	side this is the start of a stretch of driving, not the tail of a missed one — and `_arm` refuses
	anyway if a truck is already out there, so the case where one survived the wreck needs no test
	here.

	IT IS ARMED ONLY IF THE RUN HAD EARNED ONE, which under the default `RequireSteal` means a steal
	has landed at some point in it (`_earned`, set by `onSteal`). Re-testing `RequireSteal` directly
	instead — which is what this did first — is the version with the bug in it: in that mode the flag
	is true for the whole run, so a player who stole a car, wrecked, and PAID to keep going would
	come back to a run with no way out of it, their steal having been forgotten by the wreck. ]]
function GetawayController._onRevived(self)
	if not self._active then
		return
	end
	self._wrecked = false
	if self._earned then
		self:_arm(self:_timing(false))
	end
end

function GetawayController._teardown(self)
	self._active = false
	self._wrecked = false
	self._earned = false -- a steal earns an exit for THIS run only; see `onSteal`
	self._state = "off"
	self._policeLocked = false
	self._exitAt = nil
	self._camCross, self._lookCross = nil, nil
	self:_resetWeave()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end

	-- Before the folder goes: the car outlives this controller by a frame or two and must not be
	-- handed back to the race still anchored.
	self:_thawCar()
	self._dockT = 1

	if self._traffic then
		self._traffic:setAvoid(nil)
	end
	if self._folder then
		self._folder:Destroy()
		self._folder = nil
	end
	if self._model then
		self._model:Destroy()
		self._model = nil
	end
	self._movers = {}
	self._ramp = nil
	self._rootCF = nil
	self._obstacleParams.FilterDescendantsInstances = {}
	self._playerCar = nil
	self._hitBox = nil
	self._info = nil
end

GetawayController:withRemoteEvents({
	{
		RaceStart = function()
			GetawayController:_onRaceStart()
		end,
		RaceWrecked = function()
			GetawayController:_onWrecked()
		end,
		RaceRevived = function()
			GetawayController:_onRevived()
		end,
		RaceEnd = function()
			GetawayController:_teardown()
		end,
		RaceEndPanel = function(payload)
			if type(payload) == "table" and payload.kind == "bank" then
				GetawayController:_directExit()
			end
		end,
	},
	"GetawayBanked",
})

GetawayController:withLifecycle({
	init = function(self)
		self._active = false
		self._wrecked = false
		self._earned = false -- has this run qualified for a truck? Read only by `_onRevived`.
		self._policeLocked = false -- the getaway shut by a chase; see `_stepPoliceLock`
		self._state = "off" -- "off" | "waiting" | "live" | "banked"
		self._along = 0
		self._playerAlong = 0
		self._spawnAt = 0
		self._armWait = 0 -- the denominator the on-screen countdown divides by; see `getCountdown`
		self._filterAt = 0
		self._doorRaw = 0 -- linear 0..1 travel; `_pose` eases it
		self._slideRaw = 0 -- the ramp's two legs: out of the bay, then down onto the road
		self._tiltRaw = 0
		self._rampLandedAt = nil -- os.clock() of touchdown, for the landing rebound
		self._openGoal = 0
		self._bankSfxArmed = false
		self._boarding = nil
		self._boardingPrevious = nil
		self._boardingCar = nil
		self._boardingDrive = nil
		self._boardingCollisions = nil
		self._dockT = 1 -- 0..1 into the berth; 1 = nothing to settle, which is the un-banked state
		self._dockTime = GetawayConfig.Bank.DockTimeMax
		self._dockFrom, self._dockTo = CFrame.identity, CFrame.identity
		self._movers = {}
		self._zoneCentre = Vector3.zero
		self._zoneHalf = Vector3.zero
		self._length, self._width, self._rampReach = 0, 0, 0
		self:_resetWeave() -- `_cross`, `_crossVel`, `_roll`: the lane and lean `_place` reads
		self._rng = Random.new()

		-- Spawn clearance. Include over the tiles' Obstacles folders; their decorative parts are
		-- CanQuery=false, so this can only ever come back with hit volumes.
		local obstacleParams = OverlapParams.new()
		obstacleParams.FilterType = Enum.RaycastFilterType.Include
		obstacleParams.FilterDescendantsInstances = {}
		obstacleParams.RespectCanCollide = false -- obstacle volumes are deliberately non-colliding
		obstacleParams.MaxParts = 1 -- "is anything there", never "what and how many"
		self._obstacleParams = obstacleParams
	end,

	start = function(self)
		self._road = Shard.get("RoadController")
		self._traffic = Shard.get("TrafficController")
		-- The results screen, so a bank can hand it the car it just took. Not a hard dependency: a
		-- missing one costs the trophy on the return fade and nothing else, so `_bank` re-asks rather
		-- than assuming this resolved.
		self._results = Shard.get("RaceUIController")

		-- Registered once for the session, like a remote handler: the road's rebase is a property of
		-- the world rather than of any one race, and so is a steal.
		if self._road then
			self._road:onWorldShift(function(shift)
				self:_onWorldShift(shift)
			end)
		end
		local steal = Shard.get("StealController")
		if steal then
			steal:onStolen(function()
				self:onSteal()
			end)
		end

		-- Resolve the published truck off the critical path: RaceStart arrives long after this, and
		-- blocking client boot on a model the server may not have built would be worse than one
		-- warned-about exitless race.
		task.spawn(function()
			self._template = ReplicatedStorage:WaitForChild(GetawayConfig.TemplateName, 20)
			if not self._template then
				self.log:warn("No getaway truck was published; races will have no exit.")
			end
		end)
	end,
})

-- === HitchProbe (2026-10-06, Leaf's: the spike at the getaway truck — see `Modules/HitchProbe`) ===
local HitchProbe = require(ReplicatedStorage.shared.Modules.HitchProbe)
do
	--[[ 2026-10-06, Leaf: a spike "when I go to the truck", before the bank. The truck's arrival and
		the frame it takes the car each open their own window, so a long frame in the approach is
		reported with whatever of ours ran in it. ]]
	local spawn = HitchProbe.wrap("GetawayController._spawn", GetawayController._spawn)
	GetawayController._spawn = function(...)
		HitchProbe.mark("truck")
		return spawn(...)
	end
	--- Runs every approach frame and only does work on the one that takes the car, so it is timed
	--- here rather than wrapped: the window has to open on that frame, which is after the work.
	local tryBoard = GetawayController._tryBoard
	GetawayController._tryBoard = function(...)
		local started = os.clock()
		local took = tryBoard(...)
		if took and HitchProbe.Enabled then
			HitchProbe.mark("board")
			print(string.format("[HitchProbe] GetawayController._tryBoard took the car in %.1fms", (os.clock() - started) * 1000))
		end
		return took
	end
end

return GetawayController
