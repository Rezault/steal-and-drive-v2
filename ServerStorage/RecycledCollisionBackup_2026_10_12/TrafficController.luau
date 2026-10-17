--[[
	TrafficController  (client)
	---------------------------
	The cars you drive past. Keeps a population of NPC cars alive in a window around the
	driver — spawn ahead, cull behind, top up on a timer — driving them forward, moving them
	between lanes, steering them around the obstacle course, and charging you for clipping one.

	It lives on the client for the same reason the road and the obstacles do (RoadController):
	driving is solo, so every driver owns their own copy of the world and nothing here
	replicates. Traffic is cloned from the stripped shells TrafficService publishes, which are
	visuals welded to one anchored root — no chassis, no suspension, no scripts — so a car is
	one CFrame write per frame rather than a physics simulation.

	WHY THIS ISN'T KEYED TO ROAD TILES, unlike ObstacleController. An obstacle is static, so it
	can live inside its tile and let `Model:PivotTo` carry it through recycles and rebases for
	free. A traffic car MOVES: within a minute it has driven clean off the tile it spawned on,
	so parenting it to that tile would hand it to that tile's next recycle — a nine-tile
	teleport. So traffic keeps its own position in the ROAD FRAME instead:

	  • `along` — the forward-axis coordinate, advanced by `speed * dt` every frame, where
	    `speed` eases off whatever is in front of the car (`_headway`) rather than being the
	    constant it was rolled at
	  • `cross` — studs from the drive centre, eased toward the target lane

	and the world CFrame is composed from those two plus the deck height, exactly the way
	ObstacleController composes an obstacle's. That makes recycling a non-event (traffic
	doesn't belong to a tile), and leaves a rebase as the one thing that can move the road out
	from under it — which is what `RoadController:onWorldShift` exists for.

	A traffic car is SOLID to the car you're driving and to nothing else (TrafficConfig.Collision):
	its `Hit` volume sits in its own collision group, so it physically blocks you while ignoring
	other traffic, the road, the obstacles and every other player's car. On top of that contact a
	clip is detected by polling one GetPartsInPart against a sensor volume shadowing the driver's
	HitBox, and the crash runs through `ObstacleController.applyImpact` — the same yaw kick, shake
	and smoke every other hazard uses. The server prices it; the client only says that one happened.

	That sensor reaches slightly PAST the HitBox, and the poll runs before the cars are advanced,
	because between them the bare HitBox and the tail end of the frame could barely see a head-on
	hit: an overlap query needs penetration, and the solver's job on a flat face-to-face contact is
	to leave none. Sideswipes never showed it, because steering and lane changes keep driving the
	two boxes together. See TrafficConfig.Collision.ClipMargin and `_loop` — both halves are needed.

	And the car you hit REACTS BY BECOMING A RIGIDBODY. Above a severity threshold, `_knock` seeds the
	shell with the velocity it was already carrying, unanchors it, moves it into the debris collision
	group and applies one impulse at the contact point — from then on the physics engine owns it
	entirely and `_trackPhysical` only reads where it ended up (TrafficConfig.Knock). Below that
	threshold it's a scrape: a nudge, and the car drives on.

	That hand-off is also what keeps traffic solid for its whole life. An anchored shell can't be
	pushed, so wedging against one let the contact rotate the player's car round (see DriveConfig's
	backstop section); a car that MOVES when you hit it can't wedge you, so nothing has to stop
	colliding to keep the road honest.

	AND THE OTHER HALF OF A CONTACT IS THE ONE THAT DOESN'T HAPPEN. The same per-frame pass that
	charges you for touching a car measures how close you came to the ones you didn't
	(`_checkNearMisses`, NearMissConfig) — the road's only reward for driving WELL rather than far.
	It costs two dot products per car and no queries at all, because the road frame already holds
	every number it needs.

	The one thing to keep in mind when touching this file: `physical` records are outside almost every
	invariant the rest of it assumes. They aren't placed, aren't steered, don't ride the road frame,
	and are moved rather than recomputed on a rebase.

	Note the clip poll runs as the PLAYER'S collision group, not the default one. A query carries
	a group like a contact does, and "Default" is precisely what traffic no longer collides with —
	leave that at its default and the poll comes back empty every frame while the cars still block
	you, which reads as damage having broken.

	Where the steal flow plugs in (GDD §3.4): each car is a Model carrying `Tier`/`TrafficId`
	attributes with one query-visible `Hit` volume, and `getCars()` hands out the live list.
	Landing on one should swap the shell for a real rigged car — the shell is deliberately not
	drivable, so there's nothing to unpick when that happens.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local NearMissConfig = require(ReplicatedStorage.shared.Configs.NearMissConfig)
local ObstacleConfig = require(ReplicatedStorage.shared.Configs.ObstacleConfig)
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)
local PassConfig = require(ReplicatedStorage.shared.Configs.PassConfig)
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
--- Whether cars are issued by the server rather than rolled here (`_takeEncounter`'s block).
local EncounterConfig = require(ReplicatedStorage.shared.Configs.EncounterConfig)
local BrakeLightConfig = require(ReplicatedStorage.shared.Configs.BrakeLightConfig)
local UpgradeConfig = require(ReplicatedStorage.shared.Configs.UpgradeConfig)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local CarBlinkers = require(ReplicatedStorage.shared.Modules.CarBlinkers)
local CarBrakeLights = require(ReplicatedStorage.shared.Modules.CarBrakeLights)
local CarCollision = require(ReplicatedStorage.shared.Modules.CarCollision)
local CarMutation = require(ReplicatedStorage.shared.Modules.CarMutation)
local CarPaint = require(ReplicatedStorage.shared.Modules.CarPaint)
local CarRarityBadge = require(ReplicatedStorage.shared.Modules.CarRarityBadge)
--- The rare shine's band and colour (`TrafficConfig.RareShine`).
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
--- The rare-car announcement's event (`TrafficConfig.Announce`); the banner is another controller's.
local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local TimeScale = require(ReplicatedStorage.shared.Modules.TimeScale)

local TrafficController = Shard.new("TrafficController")
	:withDependencies({ "RoadController", "ObstacleController", "NearMissController", "DriveController" })

-- Resolve the artist-authored lane indicator. The normal case is a MeshPart named
-- `IndicateArrow` directly in ReplicatedStorage; accepting a Model with a BasePart inside also
-- supports a dressed replacement without changing this controller.
local function laneWarningTemplate(): BasePart?
	local named = ReplicatedStorage:FindFirstChild(TrafficConfig.LaneChangeWarning.AssetName, true)
	if named and named:IsA("BasePart") then
		return named
	end
	if named then
		return named:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

-- The Player attribute the LUCKY ROADS pass is broadcast on. Resolved once rather than per read:
-- `ownedAttribute` is a concatenation and this is on a signal connection made every race.
local LUCKY_ROADS_ATTRIBUTE = PassConfig.ownedAttribute("LuckyRoads")
--[[ Seconds before an unanswered car request may be sent again. The server answers nothing when its
	issue limits say no (`EncounterConfig.Issue`), so this is what turns silence into a retry rather
	than a road that waits forever; long enough that a slow round trip is not asked twice. ]]
local ENCOUNTER_RETRY = 2
-- How fast a car's visual heading catches up to the lane change it's making (per second).
-- The cross-axis easing is a hard clamp, so its rate is a step function; blending it is what
-- keeps a car from snapping to an angle the instant it decides to move over.
local HEADING_BLEND = 6
-- Height of the box the obstacle lookahead sweeps, studs above the deck. The tallest obstacle
-- volume is Concrete's 8.4, so 9 covers everything without reaching the bridges overhead.
local PROBE_HEIGHT = 9
-- Studs of the lookahead box that sit BEHIND the car rather than in front of it. Covers the
-- case the lookahead alone can't see: something the car is already standing in. That happens
-- at race start, when the fleet is primed onto a road whose obstacle courses may not have been
-- built yet — the first avoid check has to be able to notice and move the car out.
local PROBE_BACKSET = 16
--[[ Seconds the landing spot is held clear after a revive (see `_onRevived`).

	Not read from `ReviveConfig.ReviveHoldTime`, deliberately, even though that is the beat it is
	covering. This clock starts when the REMOTE lands on this client and has to outlast three things
	the server's number knows nothing about: the teleport replicating to us, the hold itself, and the
	control deploy that follows it. A number of our own, comfortably longer than all three, is honest
	about that; borrowing the server's would look exact and be short. ]]
local REVIVE_CLEAR_TIME = 1.5
--[[ Studs of clear road, front and back, a `shoveCar` destination needs from any other car.

	Deliberately far tighter than `TrafficConfig.SpawnGap` (70), which is the rule for introducing a
	car to the road and is generous because a spawn that lands in someone's mirror reads as pop-in.
	A shove is not a spawn: the car is already here and already visible, and all the destination has
	to be is somewhere it does not intersect anybody. A car is ~22 long, so this is a car length and
	a bit — enough that the shove cannot swap one overlap for another, loose enough that it does not
	reject every destination on a busy road and fall back to deleting the car. ]]
local SHOVE_GAP = 30

-- === Road frame =============================================================

--[[ World position of a point in the road frame.

	`forward`, `cross` and `yAxis` are the three world axes (the road contract's ForwardAxis is
	X, Y or Z), so this composition is exact rather than approximate — the same one
	ObstacleController._buildObstacle uses to place a course. ]]
function TrafficController._worldPos(self, alongCoord: number, crossOffset: number): Vector3
	local info = self._info
	return info.forward * alongCoord
		+ info.cross * (info.driveCenter + crossOffset)
		+ Vector3.yAxis * info.deckY
end

-- Which stretch of road a forward-axis coordinate falls on, or nil if it's off the live road.
-- Tile pivots sit at the START of a tile (RoadController lays them out that way, and
-- ObstacleLayout measures `along` from the same place), so this is a straight range test.
function TrafficController._tileIndexAt(self, alongCoord: number): number?
	local road, info = self._road, self._info
	for _, tile in road:getSegments() do
		if tile.Parent then
			local start = road:along(tile:GetPivot().Position)
			if alongCoord >= start and alongCoord < start + info.segmentLength then
				local index = tile:GetAttribute("TileIndex")
				return if type(index) == "number" then index else nil
			end
		end
	end
	return nil
end

-- === Lane choice ============================================================

--[[ Is there room in this lane, front and back, for a car that isn't `skip`? Compared on cross
	OFFSETS rather than lane indices, so a car halfway through a lane change blocks both of the
	lanes it's between instead of only the one it's aiming at.

	A COMMITTED LANE COUNTS AS AN OCCUPIED ONE, which is the second half of that and was missing.
	Testing `cross` alone asks where a car IS, and a lane change takes the better part of a second
	to travel: a car that has just decided to leave lane 2 for lane 3 does not come within
	`SideClearance` of lane 3 until it has crossed 3 studs, ~0.27s at `LaneChangeSpeed`. For that
	whole window lane 3 read as empty to a car on the far side, which could claim it too — and
	then both of them arrived. `targetCross` closes the window by asking where a car is GOING.

	Skipped for a `physical` record, and it has to be: a wreck's `targetCross` is whatever it was
	steering for before the crash and it is never updated again (`_trackPhysical` re-derives
	`along` and `cross` from the solver and deliberately nothing else), so honouring it would
	fence off a lane the debris left long ago. ]]
function TrafficController._laneFree(self, alongCoord: number, crossOffset: number, gap: number, skip): boolean
	local clearance = TrafficConfig.SideClearance
	for _, rec in self._cars do
		if rec ~= skip and math.abs(rec.along - alongCoord) < gap then
			if math.abs(rec.cross - crossOffset) < clearance then
				return false
			end
			if not rec.physical and math.abs(rec.targetCross - crossOffset) < clearance then
				return false
			end
		end
	end
	return true
end

--[[ Is the obstacle course going to be in the way of a car running down this lane?

	One box query over the obstacle folders, from `alongCoord` forward by `distance`. Traffic
	and obstacles share a road that neither layer knows about, and a car serenely driving
	through a concrete barrier reads as broken on sight — this is what stops that.

	Note this uses GetPartBoundsInBox where the road-edge test in ObstacleController pointedly
	does NOT. That warning (see ObstacleConfig.Wall) is about querying whole road TILES, whose
	diagonal cable props have enormous bounding boxes. Here the filter is only the obstacle
	folders, whose volumes are axis-aligned blocks and upright cylinders — their bounds are
	their shape — and everything decorative inside them is CanQuery=false. ]]
function TrafficController._obstacleAhead(self, alongCoord: number, crossOffset: number, distance: number, rec): boolean
	if self:_avoidAhead(alongCoord, crossOffset, distance, rec) then
		return true
	end
	if #self._obstacleParams.FilterDescendantsInstances == 0 then
		return false
	end
	local info = self._info
	local span = distance + PROBE_BACKSET
	local centre = self:_worldPos(alongCoord + (distance - PROBE_BACKSET) * 0.5, crossOffset)
		+ Vector3.yAxis * (PROBE_HEIGHT * 0.5)
	-- Local +X across the road, +Y up, +Z down it: cross x up == forward, same basis the
	-- obstacle builder uses, so the size below reads as (across, up, along).
	local frame = CFrame.fromMatrix(centre, info.cross, Vector3.yAxis)
	local size = Vector3.new(TrafficConfig.AvoidHalfWidth * 2, PROBE_HEIGHT, span)
	return workspace:GetPartBoundsInBox(frame, size, self._obstacleParams)[1] ~= nil
end

--[[ Is the `setAvoid` truck going to be in the way of a car running down this lane?

	Measured off the footprint the truck reports rather than box-queried, and both halves of that
	were the "everyone moves at once" bug. The box query reached 200 studs for every car, so the
	frame a truck appeared, every car behind it swerved inside the same 0.3s check. And the box is
	`AvoidHalfWidth` wide, which overlaps a 17.8-stud truck's mirrors from lanes +/-15 by 0.4 studs:
	three lanes reacted, not one, and the middle lane had nowhere to go but the far edges.

	With `rec` (the forced check in `_steer`) a car reacts on its own clock: when its time to reach
	the truck's tail drops under the `TrafficConfig.AvoidTruck.ReactSeconds` it rolled at spawn.
	Distance and closing speed differ car to car, so the swerves arrive one at a time. Without
	`rec` (choosing a lane, placing a spawn) it stays the plain `distance` test, so nobody moves
	INTO the truck's lane or appears behind it. ]]
function TrafficController._avoidAhead(self, alongCoord: number, crossOffset: number, distance: number, rec): boolean
	local footprint = self._avoidFootprint
	if not (footprint and self._avoidExtra and self._avoidExtra.Parent) then
		return false
	end
	local cfg = TrafficConfig.AvoidTruck
	local rear, front, cross, halfWidth, speed = footprint()
	if math.abs(crossOffset - cross) >= halfWidth + cfg.CarHalfWidth then
		return false
	end
	if alongCoord - cfg.CarHalfLength > front then
		return false -- already past it
	end
	local gap = rear - (alongCoord + cfg.CarHalfLength)
	if gap <= 0 then
		return true -- alongside it, or in it
	end
	if not rec then
		return gap < distance
	end
	local reach = math.max(cfg.MinReach, (rec.speed - speed) * rec.truckReact)
	return gap < math.min(reach, distance)
end

-- Rebuild the obstacle Include list from whatever the road is carrying right now. Cheap (nine
-- FindFirstChild calls) and re-derived rather than cached against tile identity, so it can't
-- go stale after a recycle — throttled only because it has no reason to run every frame.
function TrafficController._refreshObstacleFilter(self)
	local list = {}
	for _, tile in self._road:getSegments() do
		local folder = tile.Parent and tile:FindFirstChild(ObstacleConfig.TileFolderName)
		if folder then
			table.insert(list, folder)
		end
	end
	-- A thing with a footprint is tested on that instead (`_avoidAhead`), never box-queried.
	if self._avoidExtra and self._avoidExtra.Parent and not self._avoidFootprint then
		table.insert(list, self._avoidExtra)
	end
	self._obstacleParams.FilterDescendantsInstances = list
end

--[[ PUBLIC (GetawayController) — one more thing on the road that traffic must not drive through.

	The lookahead this feeds is an Include filter over the obstacle folders, so anything registered
	here is treated as course furniture: cars swerve out of the lane it occupies and won't spawn in
	front of it. That is the whole integration a getaway truck needs — it is a 54-stud solid object
	sitting in the middle lane, and traffic sailing through it is the first thing anyone would notice.

	nil clears it. Re-read on the filter's own throttle rather than applied immediately, so it costs
	nothing while no truck is out; parented-ness is re-checked there too, so a truck that despawns
	without clearing itself can't leave a phantom obstacle on the road.

	`footprint` (2026-10-01) is how the truck actually registers now: a function returning its
	(rear, front, cross, halfWidth, speed) in road coordinates. Given one, the instance stays out of
	the box query and `_avoidAhead` times each car's reaction instead; the instance is then only
	the "is it still on the road" check. ]]
function TrafficController.setAvoid(self, instance: Instance?, footprint: (() -> (number, number, number, number, number))?)
	self._avoidExtra = instance
	self._avoidFootprint = if instance then footprint else nil
	self._filterAt = 0 -- pick it up on the next frame rather than up to a quarter-second later
end

-- === The pool ===============================================================

-- Turn a published shell into a live record. Pooled by body name, which is what stops a Tier 5
-- request being handed a recycled hatchback now that each tier names its own bodies.
function TrafficController._buildRecord(self, template: Model)
	local model = template:Clone()
	local root = model.PrimaryPart or model:FindFirstChild("Root")
	local hit = model:FindFirstChild("Hit")
	if not (root and root:IsA("BasePart") and hit and hit:IsA("BasePart")) then
		self.log:warn(string.format("Traffic body '%s' has no Root/Hit; skipping it.", template.Name))
		model:Destroy()
		return nil
	end

	-- Promote the query volume to a solid one, in the group that only the player's car collides
	-- with. Done per shell rather than baked into the published template because the group is a
	-- client-side concern and the server has no use for a solid traffic car.
	if self._solid then
		CarCollision.applyTraffic(hit)
	end

	--[[ Shadows are stripped HERE rather than in the published template, and it matters which: the
		published shell is also the dress a steal grafts onto the player's car (Modules/CarBody), so
		stripping shadows there would make `TrafficConfig.CastShadows = false` quietly stop every
		stolen car casting one too. Stripped on the clone, the lever means what it says. ]]
	if not TrafficConfig.CastShadows then
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") then
				part.CastShadow = false
			end
		end
	end

	--[[ The paintwork, resolved ONCE per pooled record and remembered along with the livery it
		arrived in.

		Resolved once because the answer cannot change: a record is one body's meshes for the whole
		race, and `CarPaint.parts` is a walk of ~30 parts with a texture tally in it — cheap, but not
		cheap enough to repeat on every spawn out of the pool.

		CAPTURED because painting is ONE-WAY on the part. `CarPaint` clears the MeshPart's TextureID,
		which is where this roster's colour actually lives, so a record that has once been painted red
		has no way back to its authored livery on its own — and `Stock` is a palette entry a car can
		roll at any time. The capture is what makes rolling it mean something. ]]
	local paintParts = CarPaint.parts(model)

	-- One real 3D arrow per pooled shell. It remains an independently anchored, non-queryable visual
	-- OUTSIDE the car Model: rarity and mutation billboards measure `Model:GetExtentsSize()`, so making
	-- this elevated BasePart a descendant would make them mistake the indicator for the car's roof.
	-- `_place` carries it above the shell and the pool manages its parent alongside the Model.
	local source = self._warningTemplate or laneWarningTemplate()
	self._warningTemplate = source
	local warning: BasePart
	if source then
		warning = source:Clone()
	else
		-- Missing art must not stop traffic spawning. A later-built record can still pick up an
		-- asset that replicated late, while this invisible placeholder keeps the record shape stable.
		warning = Instance.new("Part")
		warning.Size = Vector3.one * 0.05
		if not self._warnedMissingIndicator then
			self._warnedMissingIndicator = true
			self.log:warn(string.format(
				"ReplicatedStorage.%s is missing; traffic lane indicators will be hidden.",
				TrafficConfig.LaneChangeWarning.AssetName
			))
		end
	end
	warning.Name = "LaneChangeWarning"
	warning.Anchored = true
	warning.CanCollide = false
	warning.CanTouch = false
	warning.CanQuery = false
	warning.CastShadow = false
	warning.LocalTransparencyModifier = 1

	-- The turn signals ride on the same beat as the arrow (`_signalSide`). Built after the paint
	-- capture above, so the lamp twins are never part of what a repaint or its restore walks.
	local blinkers = CarBlinkers.build(model, root, TrafficConfig.Blinkers)
	-- The stop lamps, off the same twin recipe and the same lamp rules, lit from `_braking`.
	local brakes = if BrakeLightConfig.Traffic.Enabled
		then CarBrakeLights.build(model, root, BrakeLightConfig, BrakeLightConfig.Traffic.Hold)
		else nil

	--[[ The rarity plate, built once per pooled shell for the same reason the warning above is: it
		is hidden for most of the car's life, it costs no allocation at spawn, and `_spawn` only ever
		repaints it. Built HERE rather than at spawn also means it measures the roof once, off a body
		that cannot change for as long as this record lives.

		Nil when the feature is switched off, and every call into the module tolerates that, so a
		disabled plate costs a shell nothing at all. ]]
	CarRarityBadge.build(model)

	return {
		body = template.Name,
		model = model,
		root = root,
		hit = hit,
		paintParts = paintParts,
		authored = CarPaint.capture(paintParts),
		--[[ This body's detail map, if it has one — the authored `SurfaceAppearance` that keeps a
			car's grille and trim out of the paint when they share a mesh with its panels. Resolved
			here for the same reason `paintParts` is: a record is one body for the whole race, so the
			answer cannot change, and nil (almost every car) costs nothing per spawn. ]]
		detail = CarPaint.detailFor(template.Name),
		warning = warning,
		warningVisible = false,
		blinkers = blinkers,
		brakes = brakes,
		braking = false, -- written by _headway, read through _braking
	}
end

-- === Issued cars ============================================================
--[[ THE SERVER DECIDES WHAT EACH CAR IS (2026-09-28, `EncounterConfig` — a security review found any
	client could bank any car, because this file rolled every car and the steal and the bank just
	reported what it rolled). With encounters on, `_spawn` draws from a small queue of cars the server
	issued — rung, body, paint, mutation and an opaque token each — instead of rolling its own. Speed,
	lane and every other part of how a car DRIVES is still decided here; only what it IS moved.

	THE QUEUE IS FILLED AHEAD so a spawn never waits on the network (`EncounterConfig.BatchSize` /
	`RefillBelow`). If it does run dry, `_spawn` simply answers nil, which every caller already treats
	as "try again next tick" — the road thins for a moment rather than stalling. ]]

--- Ask the server for cars, unless a request is already in flight. `rung` is the tutorial's staged
--- steal asking for one particular rung (honoured by the server on a tutorial run only).
function TrafficController._requestEncounters(self, rung: number?)
	local now = os.clock()
	if rung then
		if now < (self._rungPendingUntil or 0) then
			return
		end
		self._rungPendingUntil = now + ENCOUNTER_RETRY
		self._rungWanted = rung
	else
		if now < (self._encounterPendingUntil or 0) then
			return
		end
		self._encounterPendingUntil = now + ENCOUNTER_RETRY
	end
	--[[ The race's FIRST request goes out as the race goes live, before the road has been measured
		(`_info` is nil until it is), and the player is at the start of the road then anyway — so no
		road yet is tile 0 rather than a lookup into a road that does not exist. ]]
	local measured = self._info ~= nil and type(self._playerAlong) == "number"
	local tile = if measured then self:_tileIndexAt(self._playerAlong) or 0 else 0
	--[[ ...and every car that has left this road since the last ask rides along (`_retire`). They go
		with the REQUEST because that is the moment the server counts its room: a car handed back
		here is a slot for the batch this same call is asking for. ]]
	local retired = self._retired
	self._retired = {}
	self:getRemoteEvent("EncounterRequest"):Fire(tile, if rung then 1 else EncounterConfig.BatchSize, rung, retired)
end

--[[ This car has left the road for good, so its token goes back to the server with the next request
	(`EncounterService._retire`).

	WITHOUT THIS THE ROAD EMPTIES about 40 cars into every run. The server caps how many unspent cars
	one player may hold (`EncounterConfig.MaxOutstanding`), and only a steal spends one, so a car that
	was driven past and recycled kept its slot until its token expired, 150 seconds after it was
	issued. The cap filled 35 to 45 seconds in, the server went silent, `_spawn` answered nil every
	tick, and the rest of the run was a bare road until the first batch expired (Aleafo, 2026-09-28).

	Cleared off the record as it is taken, so a shell released twice, or pooled and reused, can never
	hand back a token it no longer carries. A stolen car's token goes back too, which is harmless: the
	server has already spent it and keeps spent tokens (`StealLanded` is fired before the recycle). ]]
function TrafficController._retire(self, token: string?)
	if token then
		table.insert(self._retired, token)
	end
end

--- The server's answer. Cars answering the tutorial's rung request are held back for it (`reserved`)
--- so the ordinary spawner cannot take the one car the staged steal is waiting for.
function TrafficController._onEncounters(self, batch: unknown)
	if not (self._active and type(batch) == "table") then
		return
	end
	for _, car in batch do
		if type(car) == "table" and type(car.token) == "string" then
			car.reserved = self._rungWanted ~= nil and car.rung == self._rungWanted
			table.insert(self._encounters, car)
		end
	end
	self._encounterPendingUntil = 0
	self._rungPendingUntil = 0
end

--[[ The next issued car to spawn, removed from the queue, or nil (and a request made) when there is
	none. `rung` asks for one on that rung, which only the tutorial does. The queue is topped up as it
	drains, so the next batch is on its way long before it is needed. ]]
function TrafficController._takeEncounter(self, rung: number?)
	local queue = self._encounters
	local found = nil
	for index, car in queue do
		if (rung == nil and not car.reserved) or (rung ~= nil and car.rung == rung) then
			found = table.remove(queue, index)
			break
		end
	end
	if rung and not found then
		self:_requestEncounters(rung)
	elseif rung and found then
		self._rungWanted = nil
	end
	if #queue < EncounterConfig.RefillBelow then
		self:_requestEncounters(nil)
	end
	return found
end

--- A published shell in this race's world by body name, or nil.
function TrafficController._templateNamed(self, name: string): Model?
	for _, template in self._worldTemplates do
		if template.Name == name then
			return template
		end
	end
	return nil
end

--[[ The rare shine (`TrafficConfig.RareShine`) on or off for this shell: on, in the band's colour,
	when `body` is rare enough; off for nil or anything below. The emitter is made the first time a
	shell needs one and kept with it through the pool. ]]
local function setShine(model: Model, body: string?)
	local cfg = TrafficConfig.RareShine
	local primary = model.PrimaryPart
	if not primary then
		return
	end
	local emitter = primary:FindFirstChild("RareShine")
	local _, band = CarRarity.of(body)
	local on = cfg.Enabled and body ~= nil and band >= cfg.MinBand
	if not on then
		if emitter then
			(emitter :: ParticleEmitter).Enabled = false
		end
		return
	end
	if not emitter then
		local made = Instance.new("ParticleEmitter")
		made.Name = "RareShine"
		made.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		made.LightEmission = 1
		made.LightInfluence = 0
		made.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, cfg.Size), NumberSequenceKeypoint.new(1, 0) })
		made.Lifetime = NumberRange.new(0.6, 1.1)
		made.Speed = NumberRange.new(1, 3)
		made.SpreadAngle = Vector2.new(180, 180)
		made.VelocityInheritance = 0.9
		made.Rate = cfg.Rate
		made.Parent = primary
		emitter = made
	end
	local shine = emitter :: ParticleEmitter
	shine.Color = ColorSequence.new(CarRarity.colourOf(band))
	shine.Enabled = true
end

--[[ Tell the banner a rare car just took the road (`TrafficConfig.Announce`): top band, or a weather
	car from `MutationMinBand`, never on the tutorial's run, at most once per `Cooldown`. ]]
function TrafficController._announceRare(self, rec)
	local cfg = TrafficConfig.Announce
	if not cfg.Enabled or self._tutorialRun then
		return
	end
	local _, band = CarRarity.of(rec.body)
	if not (band >= cfg.MinBand or (rec.mutation ~= nil and band >= cfg.MutationMinBand)) then
		return
	end
	local now = os.clock()
	if now - (self._lastAnnounce or -math.huge) < cfg.Cooldown then
		return
	end
	self._lastAnnounce = now
	Dispatcher:Publish(cfg.Event, rec.body, rec.mutation, band)
end

function TrafficController._acquire(self, template: Model)
	local pool = self._pool[template.Name]
	if pool and #pool > 0 then
		return table.remove(pool)
	end
	return self:_buildRecord(template)
end

function TrafficController._release(self, rec)
	--- First, so the slot is handed back even if something below throws on a shell the engine has
	--- already destroyed (debris that fell past `FallenPartsDestroyHeight`).
	self:_retire(rec.token)
	rec.token = nil
	self._byPart[rec.hit] = nil
	rec.plannedLane = nil
	rec.laneCommitAt = nil
	rec.warningMoving = false
	self:_setWarningVisible(rec, false)
	CarBlinkers.signal(rec.blinkers, 0, 0)
	CarBrakeLights.off(rec.brakes)
	rec.braking = false
	rec.warning.Parent = nil
	rec.model.Parent = nil
	rec.hit.CanQuery = true -- a clipped car goes query-blind; it gets its volume back here
	rec.hit.CanCollide = self._solid
	-- Undo the hand-off to physics, so a recycled shell comes back out of the pool as a scripted
	-- anchored car. Zeroing the velocities matters: the physics state persists on a pooled part, and
	-- re-anchoring a part that still remembers 40 studs/s hands that straight back the next time
	-- something unanchors it.
	-- ...and with it whatever a live freeze was holding for this shell (`setFrozen`). A record that
	-- goes back to the pool mid-hold must not come out of it carrying a velocity to restore: the
	-- next car built on these parts is a scripted anchored one that never had that velocity.
	rec.holdVel, rec.holdSpin, rec.holdAnchored = nil, nil, nil
	if rec.physical then
		rec.root.Anchored = true
		rec.hit.AssemblyLinearVelocity = Vector3.zero
		rec.hit.AssemblyAngularVelocity = Vector3.zero
		CarCollision.setTrafficPhysical(rec.hit, false)
		rec.physical = false
	end
	rec.clipped = false
	rec.leanFor = 0
	-- The mass a shove talked down (`_give`), for the same pooling reason as everything else here: a
	-- shell that came back out of the pool still light would be punted across the road by the first
	-- thing that touched it, several cars after the one anybody actually leaned on.
	if rec.give and rec.give > 0 then
		self:_setGive(rec, 0)
	end
	-- ...and the pass we may have been measuring against it (`_checkNearMisses`). Cleared for the
	-- same pooling reason as everything else here, and it matters in both directions: a shell that
	-- came back out still holding a 0.4-stud `nearGap` would pay a close call for the first car it
	-- happened to draw level with, and one still flagged `nearAwarded` would never pay again.
	rec.nearGap = nil
	rec.nearAwarded = false
	rec.whooshed = false
	rec.visualAt = 0 -- pooled records must pose immediately at their new spawn.
	--[[ ...and the weather's mark on it. Same pooling reason again, and this one is visible from the
		road: a shell that went back to the pool still wearing a Molten highlight and a x5 badge would
		come out of it as the next ordinary Civic, still glowing and still promising five times the
		money. `CarMutation.apply(model, nil)` clears the attribute as well as the look, which matters
		because the attribute is what a steal actually reads. ]]
	if rec.mutation then
		rec.mutation = nil
		CarMutation.apply(rec.model, nil)
	end
	--[[ ...and the rarity plate, for exactly that reason one line up. A shell that reached the pool
		still showing SUPERCAR / 1 IN 43 would come back out of it as the next ordinary Civic wearing
		a gold plate, and it would keep it until something happened to repaint it. `_spawn` does
		repaint it, but only when the feature is on: switch the plate off mid-race and this is the
		call that takes the ones already on the road away. ]]
	CarRarityBadge.hide(rec.model)
	setShine(rec.model, nil)
	-- Cleared here and nowhere else, because RECORDS ARE POOLED AND REUSED: a shell that reached the
	-- pool still flagged as a steal target would come back out immune to despawn and unable to
	-- change lane, forever, for the rest of the race. Same class of bug the `physical` reset above
	-- exists to prevent, and the same one the flee state will have to respect when it lands (plan §5).
	rec.frozen = false
	local pool = self._pool[rec.body]
	if not pool then
		pool = {}
		self._pool[rec.body] = pool
	end
	table.insert(pool, rec)
end

-- === Spawning ===============================================================

--[[ Weighted roll over every tier unlocked at this point in the run. Low tiers never drop out of
	the pool on purpose: trading *up* is the whole fantasy, so there has to be junk to trade up from.

	=== LUCK ==================================================================================

	The player's LUCK and MYTHICAL LUCK levels arrive here as one number (`UpgradeConfig.luckFactor`)
	and are applied as an EXPONENT over the ladder rather than as a bonus handed to the good cars:

	    weight x luck ^ ((rung - 1) / (rungs - 1))

	so the bottom rung is multiplied by 1, the top rung by the whole factor, and everything between by
	the geometric slide across. Two consequences worth knowing before retuning it:

	  * IT NEVER EMPTIES THE ROAD OF JUNK. Measured on world 1 with everything unlocked: no luck is
	    23/21/19/14/9/7/5/2 percent bottom-to-top, and the maximum factor of 12.5 is
	    8/11/13/15/14/15/14/10. The ladder FLATTENS, it does not invert — the beater is still 1 in 12.
	    That is the intent: luck should mean "there is something worth chasing out there", not
	    "everything is a supercar", because a road with nothing bad on it has nothing to trade up FROM
	    and the steal stops being a decision.
	  * IT IS WORTH ALMOST NOTHING EARLY IN A RUN. The normalisation is against the FULL ladder and
	    not the unlocked pool, so at tile 1 — where only two cars exist — the better of the two gets
	    `luck^(1/7)`, not `luck`. Distance still does the work of unlocking rungs; luck only changes
	    what happens once they are unlocked. Dividing by `#pool` instead would turn maxed luck into a
	    first-ten-seconds power, which is the opposite of the curve this game is built on.

	`_luck` is read ONCE PER RACE in `_onRaceStart` rather than here: it cannot change mid-run (the
	board is a thing you walk to) and this function runs for every car that appears.

	=== THE FLOOR ============================================================================

	`TrafficConfig.MinChoices` opens the bottom rungs whatever the tile is, which is what stops the
	first stretch of a run being one car repeating. It is applied HERE and not by editing the
	`FromTile` curve deliberately: the curve is the tuned shape of a run and is shared by five
	worlds of different lengths, while this is a floor on how few things the road may be showing at
	once — a statement about variety rather than about difficulty. That file's note on it is the
	argument for why opening the BOTTOM rungs specifically cannot leak a good car early. ]]
function TrafficController._pickTier(self, tileIndex: number)
	--[[ The arithmetic above lives in `TrafficConfig.rollRung` since 2026-09-28, so the server can roll
		the same ladder when it issues cars (`EncounterConfig`). This is the client's own roll, used
		only with that switched off. ]]
	local _, tier = TrafficConfig.rollRung(self._rng, self._tiers or TrafficConfig.Tiers, tileIndex, self._luck or 1)
	return tier
end

--[[ `_worldTemplates` and not `_templates` is the whole of what this function learned from worlds.
	Every world's shells are published into one folder — ReplicatedStorage has no per-player half —
	so the full list now spans all 29 cars, and the "don't go silent" fallback below would answer a
	missing desert car with an arctic one. Falling back within the world keeps the wrong answer at
	least wearing the right number plate. ]]
function TrafficController._pickBody(self, tier): Model?
	local allowed = tier.Bodies
	local pool = self._worldTemplates
	--[[ Parallel to `pool`, or nil for an even roll. A rung can carry VARIANTS now
		(`WorldConfig.Variants`) and they are not meant to be as common as the car the rung is named
		after, so `TrafficConfig` hands the tier a weight per body — see `VariantShare` there. ]]
	local weights = nil
	if allowed then
		pool = {}
		--[[ WALKS `allowed` RATHER THAN THE TEMPLATES, which is the one thing that changed here and
			is the reason it changed: `BodyWeights` is parallel to `Bodies`, so the pool has to be
			built in `Bodies` order or a weight lands on the wrong car. It also skips a body the
			world does not publish without leaving a hole in the weights. ]]
		local bodyWeights = tier.BodyWeights
		for slot, name in allowed do
			for _, template in self._worldTemplates do
				if template.Name == name then
					table.insert(pool, template)
					if bodyWeights then
						weights = weights or {}
						table.insert(weights, math.max(0, bodyWeights[slot] or 1))
					end
					break
				end
			end
		end
		if #pool == 0 then
			pool = self._worldTemplates -- the tier names bodies that aren't published; don't go silent
			weights = nil -- ...and the weights described the list we just threw away
		end
	end
	if #pool == 0 then
		return nil
	end

	if weights then
		local total = 0
		for _, weight in weights do
			total += weight
		end
		--- A tier whose weights are all zero is a hand-edit rather than a state to honour; an even
		--- roll over the same cars is the harmless answer and keeps the road full.
		if total > 0 then
			local roll = self._rng:NextNumber() * total
			for index, template in pool do
				roll -= weights[index]
				if roll <= 0 then
					return template
				end
			end
			--- Floating-point crumbs, same as `_pickTier`'s tail: the last entry is the answer.
			return pool[#pool]
		end
	end

	return pool[self._rng:NextInteger(1, #pool)]
end

-- A lane with room for a new car, tried in a random order so traffic doesn't stripe itself into
-- the same lane every time. nil = the road is too busy right here; the caller retries later.
function TrafficController._pickLane(self, alongCoord: number): number?
	local lanes = TrafficConfig.Lanes
	local order = table.create(#lanes)
	for i = 1, #lanes do
		order[i] = i
	end
	for i = #order, 2, -1 do
		local j = self._rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end

	for _, index in order do
		local offset = lanes[index]
		if
			self:_laneFree(alongCoord, offset, TrafficConfig.SpawnGap, nil)
			and not self:_obstacleAhead(alongCoord, offset, TrafficConfig.AvoidLookahead)
		then
			return index
		end
	end
	return nil
end

--[[ Put one car on the road at `alongCoord`, and hand back the record.

	`laneWant` and `tierWant` are the TUTORIAL'S doors in (see `placeCar`) and are nil for every
	ordinary spawn, which is what keeps the shipped behaviour bit-for-bit what it was. Both are
	REQUESTS rather than instructions:

	  • a requested lane is still tested for room, and a full one falls back to the roll rather than
	    dropping a car on top of something. A staged road that stacked two cars would be a worse
	    first impression than one that put the car a lane over.
	  • a requested tier is clamped into the ladder this world actually has, so a beat asking for
	    "one better than the starter" in a world whose ladder is shorter gets the top of it instead
	    of an index error.

	Returns the record now rather than a boolean; every existing caller ignored the boolean and the
	tutorial needs the car back so it can hold a landing clear around it. ]]
function TrafficController._playerCruise(self): number
	local cruise = self._drive and self._drive:getCruiseSpeed()
	return if type(cruise) == "number" and cruise > 0 then cruise else TrafficConfig.FallbackPlayerCruise
end

function TrafficController._tierSpeed(self, tier): number
	local fractions = tier.SpeedFraction
	if fractions then
		return self._rng:NextNumber(fractions[1], fractions[2]) * self:_playerCruise()
	end
	-- Compatibility for authored per-car overrides that still use absolute studs/s.
	return self._rng:NextNumber(tier.Speed[1], tier.Speed[2])
end

function TrafficController._spawn(
	self,
	alongCoord: number,
	laneWant: number?,
	tierWant: number?,
	lookahead: number?,
	speedScale: number?,
	paceFraction: number?
)
	if #self._cars >= self:_maxCars() then
		return nil
	end
	local lane = nil
	if laneWant and TrafficConfig.Lanes[laneWant] then
		--[[ `lookahead` OVERRIDES `AvoidLookahead` FOR A REQUESTED LANE, and it exists for one caller.
			`AvoidLookahead` is 200 studs because an ordinary traffic car is going to be driving this
			lane for the next ten seconds and a spawn that has to swerve immediately reads badly. The
			tutorial's steal target is not going to be driving anywhere: it is taken about two seconds
			later, which is sixty-odd studs. Vetoed on an obstacle 200 studs away, it was pushed out of
			the driver's lane and into whichever one happened to be free.

			=== AND WHEN IT CANNOT HAVE THE LANE IT ASKED FOR, IT GETS THE NEAREST ONE ==============

			The fallback used to be `_pickLane` straight away, which rolls a lane out of everything
			free — so a request that could not be met came back, most of the time, TWO OR MORE LANES
			away. That is the one answer that is no use to anybody: lanes are 15 studs apart, so one
			over is a jump that lands and two over is thirty studs of sideways, which no arc covers.
			A caller that names a lane has a reason for naming it, and the honest way to refuse is to
			give it the closest thing to what it asked for.

			Nearest-first, alternating outward. `_pickLane` still catches the case where nothing at
			this coordinate is usable at all. ]]
		local order = { laneWant }
		for step = 1, #TrafficConfig.Lanes - 1 do
			table.insert(order, laneWant - step)
			table.insert(order, laneWant + step)
		end
		for _, try in order do
			local offset = TrafficConfig.Lanes[try]
			if
				offset
				and self:_laneFree(alongCoord, offset, TrafficConfig.SpawnGap, nil)
				and not self:_obstacleAhead(alongCoord, offset, lookahead or TrafficConfig.AvoidLookahead)
			then
				lane = try
				break
			end
		end
	end
	lane = lane or self:_pickLane(alongCoord)
	if not lane then
		return nil
	end

	--[[ WHAT THIS CAR IS: the server's, off the issued queue (`_takeEncounter`, header block above
		`_acquire`), or rolled here with encounters off — the old path, exactly. ]]
	local tier, template, encounter
	if EncounterConfig.Enabled then
		local rung = if tierWant and #self._tiers > 0 then math.clamp(math.floor(tierWant), 1, #self._tiers) else nil
		encounter = self:_takeEncounter(rung)
		if not encounter then
			return nil
		end
		tier = self._tiers[encounter.rung]
		template = self:_templateNamed(encounter.body)
		if not (tier and template) then
			--- Issued a car this client cannot draw (a body the place does not publish for this
			--- world). Dropped, and said once: it is a config fault, not something the player did.
			if not self._warnedUndrawable then
				self._warnedUndrawable = true
				self.log:warn(string.format("Issued a %s on rung %s that this world cannot draw; skipped.", tostring(encounter.body), tostring(encounter.rung)))
			end
			--- Never going to be on the road, so its slot goes straight back (`_retire`).
			self:_retire(encounter.token)
			return nil
		end
	else
		tier = self:_pickTier(self:_tileIndexAt(self._playerAlong) or 0)
		if tierWant and #self._tiers > 0 then
			tier = self._tiers[math.clamp(math.floor(tierWant), 1, #self._tiers)] or tier
		end
		template = self:_pickBody(tier)
		if not template then
			return nil
		end
	end
	local rec = self:_acquire(template)
	if not rec then
		--- Nothing was spent, so the issued car goes back to the front of the queue for the next try.
		if encounter then
			table.insert(self._encounters, 1, encounter)
		end
		return nil
	end
	--- The token a steal and a near miss past this car will name (`EncounterConfig`); nil with it off.
	rec.token = if encounter then encounter.token else nil

	local now = os.clock()
	rec.tier = tier
	-- Rolled ONCE and kept, because `speed` is no longer a constant: `_headway` eases it down
	-- behind slower cars and back up when the road clears, and `cruise` is the number it comes
	-- back to. Both are set here rather than only `cruise`, so a car recycled out of the pool
	-- starts at its own pace instead of inheriting the last driver's brake.
	--[[ ...times whatever the weather is doing to the pace, which is 1 everywhere except rush hour.
		Baked into `cruise` at spawn rather than applied per frame, so a car keeps the speed it was
		born with: an event that ends mid-run leaves the cars already out there driving at rush-hour
		pace until they recycle, which is a jam clearing rather than every car on the road changing
		speed on one frame. ]]
	local rolledSpeed = if paceFraction then self:_playerCruise() * paceFraction else self:_tierSpeed(tier)
	rec.cruise = rolledSpeed * self:_weatherTraffic().Speed * (speedScale or 1)
	rec.speed = rec.cruise
	rec.along = alongCoord
	rec.lane = lane
	rec.cross = TrafficConfig.Lanes[lane]
	rec.targetCross = rec.cross
	rec.lateral = 0
	rec.plannedLane = nil
	rec.laneCommitAt = nil
	rec.warningMoving = false
	self:_setWarningVisible(rec, false)
	rec.clipped = false
	rec.nearGap = nil
	rec.nearAwarded = false
	-- `physical` and the anchoring that goes with it are undone in _release, which every recycled
	-- record passes through. This is the belt to that braces: a shell that reached the pool still
	-- unanchored would spawn falling through the road.
	rec.physical = false
	rec.frozen = false
	rec.root.Anchored = true
	if rec.smoke then
		rec.smoke.Enabled = false
	end
	self:_armLaneTimer(rec, now)
	-- Stagger the first lookahead across the fleet so a primed road doesn't fire ten box
	-- queries on the same frame, every AvoidCheckInterval, forever.
	rec.avoidAt = now + self._rng:NextNumber(0, TrafficConfig.AvoidCheckInterval)
	-- Seconds out from the getaway truck this driver notices it (`_avoidAhead`). Rolled per spawn,
	-- so a recycled car is a different driver.
	local react = TrafficConfig.AvoidTruck.ReactSeconds
	rec.truckReact = self._rng:NextNumber(react[1], react[2])

	self._nextId += 1
	rec.model:SetAttribute("Tier", tier.Tier)
	rec.model:SetAttribute("TrafficId", self._nextId)
	rec.hit.CanQuery = true

	--[[ This car's colour, rolled per spawn out of the body's own pool (`PaintConfig`), remembered on
		the record rather than only applied to it.

		REMEMBERED BECAUSE THE INDEX IS THE THING THAT TRAVELS. A steal reads it back off the car it
		landed on and stamps it on the player's own car (`StealController._applyTier`), a bank sends it
		to the server, and the garage writes it into the save file — so the Charger you drove into the
		truck is the Charger standing on your podium. A `Color3` would do none of that: it cannot be
		stored and cannot be checked. See PaintConfig's header.

		PER SPAWN AND NOT PER BODY, which is the whole point of the feature: two of the same model on
		one stretch of road should not be two copies of the same car. Rolled off the controller's own
		`_rng`, so seeding that seeds the road's colours too and nothing here has to own a seed.

		`Stock` restores rather than paints, because the record is POOLED — see `_buildRecord`. ]]
	rec.paint = if encounter then encounter.paint else PaintConfig.roll(self._rng, rec.body)
	local color = PaintConfig.colorOf(rec.paint)
	if color then
		CarPaint.paint(rec.paintParts, color, rec.detail)
	else
		CarPaint.restore(rec.authored)
	end

	--[[ …and whatever the WEATHER has done to this one. Rolled per spawn and remembered on the record
		for the same reason the paint above is: the index is the thing that travels. A steal reads it
		back off the car it landed on (`StealController._applyTier`), the truck sends it, and the
		garage writes it into the save file — so the Charged M5 standing on your podium is the one you
		actually took out of the storm.

		ROLLED AGAINST `self._event`, which is the event running in THIS player's world right now and
		nil on a clear day — see `_refreshWeather`. A clear day still mutates the occasional car, by
		design; `WeatherConfig.roll` owns that rule and this call site does not need to know it.

		Off the controller's own `_rng`, so seeding that seeds the road's mutations along with its
		colours and nothing here has to own a seed.

		WITH THE BADGE, and that argument is the whole difference between this call and the one the
		steal makes: a marker over a car you are deciding whether to jump at is the point, and the
		same marker over the car you are sitting in would hang in the middle of the chase camera for
		the rest of the run. ]]
	-- ...and no mutated cars on it either, clear-day ones included.
	--- An issued car's mutation is the server's, rolled against the same schedule (and nil on a
	--- tutorial run there too).
	rec.mutation = if encounter
		then encounter.mutation
		elseif self._tutorialRun then nil
		else WeatherConfig.roll(self._rng, self:_liveEvent())
	CarMutation.apply(rec.model, rec.mutation, true)

	--[[ What this car IS, said out loud over its roof: the band's word, the odds of the road giving
		you one, and the band's colour under both. `Modules/CarRarityBadge` is all of it.

		AFTER THE MUTATION AND NOT BEFORE IT, which is the one ordering rule here. A mutated car wears
		two markers and the rarity plate stacks on top of the mutation badge, so it has to be placed
		once the mutation attribute is already stamped. Run the other way round and the two sit inside
		each other on every mutated car.

		THE TIER AND THE BODY ARE BOTH PASSED because they answer different halves. The band is the
		rung's (a variant shares the band of the car it stands beside) and the odds are the body's (a
		variant is rarer than that car). `self._weatherWorld` is this run's world and `self._luck` the
		factor `_pickTier` just rolled with, so the number over the car is the number that produced
		it. ]]
	CarRarityBadge.set(rec.model, tier, rec.body, self._weatherWorld, self._luck)
	setShine(rec.model, rec.body)
	self:_announceRare(rec)

	-- Parent BEFORE placing — see `_place`. The welds only bind once the model is in the
	-- workspace, and they bake whatever offset they find at that moment.
	rec.model.Parent = self._folder
	rec.warning.Parent = self._folder
	self:_place(rec)
	self._byPart[rec.hit] = rec
	table.insert(self._cars, rec)
	return rec
end

--[[ Spawn ordinary LIVE traffic outside the player's immediate decision window.

	Formation slots are stored as absolute road coordinates. While a pack is being emitted the
	player keeps moving, so a later slot can otherwise become much closer than SpawnAheadMin even
	though its anchor was valid when the pack was planned. Clamp at the last possible moment rather
	than trusting every caller or formation offset. Race-start priming and TutorialDirector's
	explicit placement intentionally call `_spawn` directly and are therefore unaffected. ]]
function TrafficController._spawnLive(
	self,
	alongCoord: number,
	laneWant: number?,
	tierWant: number?,
	lookahead: number?,
	speedScale: number?,
	paceFraction: number?
)
	local minimumAlong = self._playerAlong + TrafficConfig.SpawnAheadMin
	return self:_spawn(math.max(alongCoord, minimumAlong), laneWant, tierWant, lookahead, speedScale, paceFraction)
end

--[[ Fill the road at race start instead of letting it trickle in.

	Without this the population takes MaxCars x SpawnInterval — around thirty seconds — to build
	up, which is most of a run (the GDD targets 60-120s) spent on an empty road. Priming across a
	wider band than a live spawn uses reads as traffic that was already out there. ]]
function TrafficController._prime(self)
	--[[ ...unless the spawner is CLOSED, in which case there is nothing to fill the road with.

		`_noSpawn` is checked here and not only at `_maybeSpawn`, because the prime is a spawn: it
		is the same `_spawn` call, it just makes several at once and across a wider band. Without
		this a road closed to traffic still opened with six cars on it and then never received a
		seventh, which is the one outcome neither caller of `setSpawning` wants. The tutorial's
		director closes it to deal the road itself, and the obstacle bench closes it so that a
		hazard can be driven into without one arriving three studs before it.

		`_primed` is set by the caller either way, so a run that starts closed starts empty and
		stays that way rather than priming later when the spawner reopens. That is the honest
		reading of "the road was primed at the start of this run". ]]
	if self._noSpawn then
		return
	end

	local band = TrafficConfig.PrimeBand
	-- ...and more of them under an event that wants a busier road, so a run STARTED in rush hour
	-- opens into the jam rather than filling up over its first half-minute. `_spawn` still refuses
	-- anything over the cap, so this can ask for more than fits without checking.
	local count = math.floor(TrafficConfig.PrimeCount * self:_weatherTraffic().Prime)
	--[[ Booked rather than spawned. The band and the count are decided here, on the one frame that
		can read the weather for this run, but the CARS are built a couple a frame by `_stepPrime` —
		see `TrafficConfig.PrimeBudget` for why ten clones on the RaceStart frame was the wrong place
		for them. The band is stashed with the count so a weather change mid-prime cannot re-roll the
		road out from under a fill that is already half done. ]]
	self._primeLeft = count
	self._primeBand = band
end

--- A couple of the booked prime's cars. No-op once the road is full or the booking is spent.
function TrafficController._stepPrime(self)
	local left = self._primeLeft
	if left <= 0 then
		return
	end
	--[[ Waiting on the server's first batch (`EncounterConfig`): hold the booking rather than spend it
		on spawns that would all come back empty — otherwise a round trip longer than the prime takes
		would start every run on a bare road. It resumes on the frame the batch lands. ]]
	if EncounterConfig.Enabled and #self._encounters == 0 then
		return
	end
	local band = self._primeBand or TrafficConfig.PrimeBand
	--- `_spawn` refuses anything over the cap on its own, exactly as it did when this was a loop, so
	--- a booking bigger than the road can hold simply runs out against it.
	for _ = 1, math.min(left, math.max(1, TrafficConfig.PrimeBudget)) do
		self:_spawn(self._playerAlong + self._rng:NextNumber(band[1], band[2]))
	end
	self._primeLeft = math.max(0, left - math.max(1, TrafficConfig.PrimeBudget))
end

-- === Driving ================================================================

--[[ Put a car where its road-frame scalars say it is.

	`Model:PivotTo` rather than `root.CFrame = ...`, and that is NOT interchangeable here. The
	shell is one anchored Root with everything welded to it, and a WeldConstraint only holds
	while both parts are in the workspace — it re-captures the offset it sees the moment the
	model is parented back in. Move the Root while the model is out of the workspace (freshly
	cloned, or idle in the pool) and that bogus offset is what gets baked: the first build of
	this shipped the car's body and its `Hit` volume three thousand studs adrift of the wheels,
	permanently, because the spawn placed before it parented.

	The parent-then-place order below is the actual fix; `PivotTo` is the belt to its braces.
	It transforms every part, so even a weld that failed to take can't leave a car visibly in
	pieces — and with the welds intact it's still one transform for the whole assembly. ]]
function TrafficController._place(self, rec)
	local info = self._info
	local pos = self:_worldPos(rec.along, rec.cross)
	-- Point the car at where it's actually going, so a lane change reads as one. Composing the
	-- direction from the two rates (rather than tracking a yaw angle) keeps it exact and
	-- self-correcting at any speed.
	local dir = info.forward * rec.speed + info.cross * rec.lateral
	if dir.Magnitude < 1e-3 then
		dir = info.forward
	end
	rec.model:PivotTo(CFrame.lookAt(pos, pos + dir))
	self:_placeLaneWarning(rec)
end

--[[ A car physics now owns. Nothing here moves it — the whole point is that the engine does — so
	this only keeps the bookkeeping the rest of the controller depends on in sync with where the car
	has actually ended up: its road-frame coordinates, for the despawn window and for `_laneFree`,
	so spawns and lane changes treat a wreck as something to steer around.

	Deriving `along`/`cross` from the live position rather than integrating them is also what makes a
	rebase almost free for debris: move the CFrame and these follow on the next frame. ]]
function TrafficController._trackPhysical(self, rec, now: number)
	local info = self._info
	local pos = rec.root.Position
	rec.along = pos:Dot(info.forward)
	rec.cross = pos:Dot(info.cross) - info.driveCenter
	-- On a timer, not by watching it settle: physics debris grinds against the deck at a speed that
	-- never quite reaches zero, so a plume waiting for stillness would follow it down the road.
	if rec.smoke and rec.smoke.Enabled and now >= rec.smokeUntil then
		rec.smoke.Enabled = false
	end
end

--[[ How hard a hit was, 0..1, from the CLOSING SPEED between the two cars along the line between
	them — not from the mere fact of a contact. Everything about the reaction hangs off this: a
	contact is an event, but only a speed can tell a graze from a ram, and treating those alike is
	what made the first version read as weightless (see TrafficConfig.Knock).

	The traffic car's velocity is composed from its own road-frame scalars rather than read off the
	part, because the shell is anchored — physics reports zero for it however fast it's "going". ]]
function TrafficController._severity(self, rec, delta: Vector3): (number, number?)
	local knock = TrafficConfig.Knock
	local primary = self._playerCar and self._playerCar.PrimaryPart
	local info = self._info
	if not (primary and info) then
		return 1 -- can't measure it; price it as the worst case rather than the cheapest
	end

	local flat = Vector3.new(delta.X, 0, delta.Z)
	if flat.Magnitude < 1e-3 then
		return 1
	end
	local theirs = info.forward * rec.speed + info.cross * rec.lateral
	-- Positive = we are closing on them along the contact line. Negative means they ran into us,
	-- or we're already separating, and neither deserves a reaction.
	local closing = (primary.AssemblyLinearVelocity - theirs):Dot(flat.Unit)

	local span = math.max(knock.FullSpeed - knock.ScrapeSpeed, 1e-3)
	--- The raw closing speed too (studs/s), for the crash sound. See `_scaleKind`.
	return math.clamp((closing - knock.ScrapeSpeed) / span, 0, 1), closing
end

--[[ Scale an impact `kind` by severity, so the player's own jolt matches the hit that caused it
	instead of being the same every time. Floored at `MinScale` — a contact that produces no shake
	and no puff at all reads as the collision being broken, not as a gentle one.

	`closing` rides along as `ImpactSpeed` for the crash sound (`CrashSoundConfig.Speed`): the shake
	is capped by the kind, the closing speed is how fast the two cars actually met. ]]
function TrafficController._scaleKind(self, kind, severity: number, closing: number?)
	local scale = TrafficConfig.Collision.MinScale
	scale += (1 - scale) * severity
	return {
		-- SpeedKeep is a fraction retained, so it scales from 1 (keep everything) downward.
		SpeedKeep = 1 - (1 - kind.SpeedKeep) * scale,
		SideKick = kind.SideKick * scale,
		Yaw = kind.Yaw * scale,
		Shake = kind.Shake * scale,
		ImpactSpeed = closing,
		--- A car is always something solid to hit, whatever its scaled `Shake` says.
		Solid = true,
	}
end

--[[ You hit this car. Either it twitches and drives on, or it breaks traction and is out.

	`side` is +1 when the car we hit is on our RIGHT. The road frame's cross axis points LEFT
	(`cross x up == forward` — RoadController's own comment warns not to trust the name), so
	shoving it further right means moving it in the NEGATIVE cross direction: hence `away = -side`,
	which is what makes a car move away from the wing that clipped it rather than into it.

	NOTHING HERE DECIDES HOW IT ROTATES, which is the whole reason this is better than the two
	scripted versions it replaces. The impulse goes in at the CONTACT POINT, so the lever arm — and
	therefore the spin — is whatever the geometry says it is: catch a rear quarter and it pivots,
	T-bone the door and it slides, hit it square from behind and it's shoved up the road. Those used
	to be a hand-derived `foreAft` term and a leverage curve. Now they're a consequence. ]]
function TrafficController._knock(self, rec, side: number, severity: number)
	local knock = TrafficConfig.Knock
	if not knock.Enabled then
		return
	end
	-- The steal target is off limits. Handing it to physics mid-mount would drop the car out from
	-- under the player and leave the handoff teleporting them onto a tumbling wreck.
	if rec.frozen then
		return
	end
	local info = self._info
	local primary = self._playerCar and self._playerCar.PrimaryPart

	-- A light contact never costs the car its life: it's nudged out of shape and its own lane easing
	-- straightens it back out over the next half second. No state to enter, so none to leave.
	if severity < knock.MinSeverity then
		rec.cross += -side * knock.ScrapeShove
		rec.speed *= knock.ScrapeSpeedKeep
		return
	end
	if not (primary and info) then
		return -- no contact geometry to push along; leave it driving rather than guess
	end

	--[[ Hand it to physics. All three steps below are order-sensitive:

		1. GROUP FIRST. Live traffic deliberately doesn't collide with the road, so a simulated car
		   left in that group falls straight through the world.
		2. UNANCHOR BEFORE SEEDING THE VELOCITY, not after. An anchored assembly doesn't hold a
		   velocity — writing one while it's still anchored is thrown away, and the car would go
		   physical at a standstill.
		3. SEED THE VELOCITY AT ALL. An anchored shell is moved by CFrame writes, so its velocity
		   property is zero however fast it looks like it's going. Without this a car doing 30
		   studs/s stops dead in mid-road, and you rear-end something that teleported to a
		   standstill — which reads as the game breaking rather than as a crash.

		No physics step runs between these lines, so the car never exists in a half-converted state. ]]
	self:_goPhysical(rec, info)

	local push = knock.Push[1] + (knock.Push[2] - knock.Push[1]) * severity
	-- Along the contact normal — centre to centre, flattened — which is what makes a rear-end shove
	-- the car forward and a sideswipe shove it sideways without either being a special case.
	local delta = rec.hit.Position - primary.Position
	local flat = Vector3.new(delta.X, 0, delta.Z)
	local dir = if flat.Magnitude > 1e-3 then flat.Unit else info.cross * -side
	dir += Vector3.yAxis * knock.Lift

	-- Read AFTER unanchoring: an anchored assembly reports no mass. Multiplying by it here is what
	-- keeps `Push` denominated in studs/s instead of in impulse units — see TrafficConfig.Knock.Push.
	local impulse = dir * (push * rec.hit.AssemblyMass)
	rec.hit:ApplyImpulseAtPosition(impulse, self:_contactPoint(rec, primary))

	self:_setSkidSmoke(rec, severity)
end

-- The hand-off itself, the three order-sensitive steps `_knock` explains. Shared with `ram`.
function TrafficController._goPhysical(self, rec, info)
	rec.physical = true
	self:_setWarningVisible(rec, false)
	CarCollision.setTrafficPhysical(rec.hit, true)
	rec.root.Anchored = false
	rec.hit.AssemblyLinearVelocity = info.forward * rec.speed + info.cross * rec.lateral
end

--[[ PUBLIC (GetawayController, 2026-10-01) — something that is not the player hit this car hard: hand
	it to physics, shoved by `velocity` (studs/s) applied at `at`, the way `_knock` hands over a car
	the player hit. The getaway truck uses it to plough through traffic on its way out behind the end
	panel. Refuses a car already physical or frozen (the steal target), and answers whether it took. ]]
function TrafficController.ram(self, rec, velocity: Vector3, at: Vector3): boolean
	local info = self._info
	if rec.physical or rec.frozen or not (info and rec.hit and rec.root) or not TrafficConfig.Knock.Enabled then
		return false
	end
	self:_goPhysical(rec, info)
	rec.hit:ApplyImpulseAtPosition(velocity * rec.hit.AssemblyMass, at)
	self:_setSkidSmoke(rec, 1)
	return true
end

--[[ The point on the hit car's body closest to us — the nearest point on its box, in its own frame.

	This is what makes the impulse produce rotation, so an approximation is fine but a centre is not:
	applied at the centre, any impulse is pure translation and every car would slide without turning.
	Clamping our position into the box's half-extents is the cheap exact answer for a box. ]]
function TrafficController._contactPoint(self, rec, primary: BasePart): Vector3
	local hit = rec.hit
	local localPos = hit.CFrame:PointToObjectSpace(primary.Position)
	local half = hit.Size * 0.5
	return hit.CFrame:PointToWorldSpace(Vector3.new(
		math.clamp(localPos.X, -half.X, half.X),
		math.clamp(localPos.Y, -half.Y, half.Y),
		math.clamp(localPos.Z, -half.Z, half.Z)
	))
end

--[[ Tyre smoke off a car that's breaking traction. One emitter per pooled shell, built on that
	shell's first knock and reused for the session, so a full fleet is at most `MaxCars` Smokes and
	they're disabled almost all of the time. `_trackPhysical` switches it off on a timer. ]]
function TrafficController._setSkidSmoke(self, rec, severity: number)
	local cfg = TrafficConfig.Knock.Smoke
	if not cfg.Enabled then
		return
	end
	local smoke = rec.smoke
	if not smoke then
		smoke = Instance.new("Smoke")
		smoke.Color = cfg.Color
		smoke.Opacity = cfg.Opacity
		smoke.RiseVelocity = cfg.RiseVelocity
		smoke.Parent = rec.root
		rec.smoke = smoke
	end
	smoke.Size = cfg.MinSize + (cfg.MaxSize - cfg.MinSize) * severity
	smoke.Enabled = true
	rec.smokeUntil = os.clock() + cfg.Duration[1] + (cfg.Duration[2] - cfg.Duration[1]) * severity
end

-- Seconds until this car next reconsiders its lane. Rolled from its tier, so higher tiers move
-- around more (the GDD's "harder to land on"). Pushed forward after every change, forced or not,
-- so a car that has just swerved doesn't immediately swerve back.
function TrafficController._armLaneTimer(self, rec, now: number)
	rec.laneAt = now + self._rng:NextNumber(rec.tier.LaneChange[1], rec.tier.LaneChange[2])
end

--[[ Is this car on its brakes right now, for its stop lamps (`CarBrakeLights`)?

	`braking` is written by `_headway`, the only thing in this layer that slows a car on purpose,
	and it is stale on any car `_steer` no longer runs for: a frozen one is the steal target and a
	physical one is a wreck, and neither has a foot on anything. ]]
function TrafficController._braking(self, rec): boolean
	return rec.braking == true and not rec.frozen and not rec.physical
end

--[[ Which way this car's turn signal and 3D arrow point right now: -1 left, 1 right, 0 off.

	Read off the same two states the arrow is: a planned change still in its warning beat, then the
	crossing itself. One source of truth prevents the mesh and the lamps disagreeing about direction.

	A frozen car is the steal target and a physical one is a wreck; neither is changing lane any
	more, whatever its plan still says.

	THE SIGN FLIPS on the way out. `cross` is measured along `yAxis:Cross(forward)`
	(RoadController), and a car's own right is `forward:Cross(yAxis)` because `_place` aims it with
	`CFrame.lookAt`. So a car heading for a LARGER cross is turning to ITS left. ]]
function TrafficController._signalSide(self, rec): number
	if rec.frozen or rec.physical then
		return 0
	end
	local target = if rec.plannedLane
		then TrafficConfig.Lanes[rec.plannedLane]
		elseif rec.warningMoving then rec.targetCross
		else nil
	if not target or target == rec.cross then
		return 0
	end
	return if target > rec.cross then -1 else 1
end

-- Toggle intent rather than transparency directly. `_placeLaneWarning` combines this flashing
-- state with the distance cutoff; unlike the old BillboardGui, a MeshPart has no MaxDistance.
function TrafficController._setWarningVisible(self, rec, visible: boolean)
	rec.warningVisible = visible
	local closeEnough = math.abs(rec.along - self._playerAlong) <= TrafficConfig.LaneChangeWarning.MaxDistance
	rec.warning.LocalTransparencyModifier = if visible and closeEnough then 0 else 1
end

-- Carry the authored arrow above the shell and aim its LookVector across the road toward the lane
-- being requested. This uses the road frame instead of world X/Z, so rotated road layouts and the
-- earlier left/right sign correction both remain correct.
function TrafficController._placeLaneWarning(self, rec)
	local side = self:_signalSide(rec)
	if side == 0 then
		self:_setWarningVisible(rec, false)
		return
	end
	local cfg = TrafficConfig.LaneChangeWarning
	local position = rec.root.Position + Vector3.yAxis * cfg.Height
	local direction = self._info.cross * -side
	local correction = CFrame.Angles(
		math.rad(cfg.MeshRotationDeg.X),
		math.rad(cfg.MeshRotationDeg.Y),
		math.rad(cfg.MeshRotationDeg.Z)
	)
	rec.warning.CFrame = CFrame.lookAt(position, position + direction, Vector3.yAxis) * correction
	self:_setWarningVisible(rec, rec.warningVisible)
end

function TrafficController._cancelLanePlan(self, rec)
	rec.plannedLane = nil
	rec.laneCommitAt = nil
	rec.warningMoving = false
	self:_setWarningVisible(rec, false)
end

-- Choose without moving. Routine changes use this to reserve a readable warning beat before the
-- crossing starts; forced obstacle avoidance calls `_changeLane` and still commits immediately.
function TrafficController._pickAdjacentLane(self, rec): number?
	local lanes = TrafficConfig.Lanes
	local candidates = {}
	if rec.lane > 1 then
		table.insert(candidates, rec.lane - 1)
	end
	if rec.lane < #lanes then
		table.insert(candidates, rec.lane + 1)
	end
	if #candidates == 2 and self._rng:NextNumber() < 0.5 then
		candidates[1], candidates[2] = candidates[2], candidates[1]
	end

	for _, index in candidates do
		local offset = lanes[index]
		if
			self:_laneFree(rec.along, offset, TrafficConfig.LaneChangeGap, rec)
			and not self:_obstacleAhead(rec.along, offset, TrafficConfig.AvoidLookahead)
		then
			return index
		end
	end
	return nil
end

function TrafficController._commitLane(self, rec, index: number, now: number): boolean
	local offset = TrafficConfig.Lanes[index]
	if
		self:_laneFree(rec.along, offset, TrafficConfig.LaneChangeGap, rec)
		and not self:_obstacleAhead(rec.along, offset, TrafficConfig.AvoidLookahead)
	then
		rec.lane = index
		rec.targetCross = offset
		self:_cancelLanePlan(rec)
		rec.warningMoving = true
		self:_setWarningVisible(rec, true)
		self:_armLaneTimer(rec, now)
		return true
	end
	self:_cancelLanePlan(rec)
	return false
end

function TrafficController._planLane(self, rec, now: number): boolean
	local index = self:_pickAdjacentLane(rec)
	if not index then
		return false
	end
	rec.plannedLane = index
	rec.laneCommitAt = now + TrafficConfig.LaneChangeWarning.Seconds
	self:_setWarningVisible(rec, true)
	return true
end

-- Move over if the lane beside us is worth having. Adjacent lanes only — a car crossing three
-- lanes at once reads as a teleport — picked in random order, so left/right is a coin flip and
-- a car on the outside edge simply comes back in.
function TrafficController._changeLane(self, rec, now: number): boolean
	self:_cancelLanePlan(rec)
	local index = self:_pickAdjacentLane(rec)
	return index ~= nil and self:_commitLane(rec, index, now)
end

--[[ Something is in this car's lane. Get out of the way.

	The polite adjacent-lane move is tried first, and for a cone or a crate that's the end of it.
	It is NOT enough on its own, though, and the reason is the courses: `gate`, `chicane`,
	`heavyGate` and the two `wallGap`s block FOUR of the five lanes, so for a car on the wrong
	side the lane next door is part of the same wall and the adjacent-only search just fails.
	Measured before this fallback existed, traffic spent ~1% of its life standing inside an
	obstacle — with a dozen cars on screen, something is visibly inside a barrier most of the time.

	So the fallback walks toward the nearest lane that IS clear, one lane per decision, and
	deliberately drops the traffic-clearance test on the way: overlapping another traffic car for
	a moment is a much smaller sin than driving through concrete, and neither one collides.

	THAT TRADE IS STILL THE RULE, but it is now the second choice rather than the only one. The
	search runs twice over the same candidates: once for a clear lane nobody else is in or heading
	for, and only if there is no such lane at all does it fall back to the nearest clear one
	whatever is standing in it. On a `chicane` (two lanes open) or an ordinary cone that is a free
	win. On a `gate` it changes nothing, because there is exactly ONE lane open and both cars have
	to have it — which is why `TrafficConfig.Headway` exists: the merge those two cars cannot
	avoid ACROSS the road is resolved along it instead, one of them easing off to take the gap
	second. Fixing this here alone would not have fixed the reported bug. ]]
function TrafficController._avoid(self, rec, now: number): boolean
	if self:_changeLane(rec, now) then
		return true
	end

	local lanes = TrafficConfig.Lanes
	local best, bestDist -- nearest lane clear of obstacles, occupied or not
	local free, freeDist -- ...and the nearest one that is also clear of traffic
	for index, offset in lanes do
		if index ~= rec.lane and not self:_obstacleAhead(rec.along, offset, TrafficConfig.AvoidLookahead) then
			local dist = math.abs(index - rec.lane)
			if not bestDist or dist < bestDist then
				best, bestDist = index, dist
			end
			if
				(not freeDist or dist < freeDist)
				and self:_laneFree(rec.along, offset, TrafficConfig.LaneChangeGap, rec)
			then
				free, freeDist = index, dist
			end
		end
	end
	best = free or best
	if not best then
		return false -- every lane is blocked; keep the line and clip through
	end

	rec.lane += if best > rec.lane then 1 else -1
	rec.targetCross = lanes[rec.lane]
	self:_cancelLanePlan(rec)
	rec.warningMoving = true
	self:_setWarningVisible(rec, true)
	self:_armLaneTimer(rec, now)
	return true
end

--[[ How fast a record is ACTUALLY going down the road.

	For a driving car that is just `speed`. For a `physical` one it is not: `speed` is the number it
	was doing before the crash and it is never written again, so a wreck that has been spun round and
	is sliding backwards still claims 38 studs/s. The solver owns that car, so ask the solver — one
	dot product, and only for the handful of records that are debris. ]]
function TrafficController._roadSpeed(self, rec): number
	if rec.physical then
		return rec.root.AssemblyLinearVelocity:Dot(self._info.forward)
	end
	return rec.speed
end

--[[ Are these two cars each other's problem — in one lane now, or converging on one?

	The COMMITTED lanes are half of this and they are the half that decides whether the fix is
	visible, for the same reason `_laneFree` had to learn about them. Two cars funnelled into a
	gate's one gap spend the better part of a second crossing into it (`LaneChangeSpeed`), and
	comparing only where they ARE means neither reacts to the other until they are already on top of
	each other — which leaves the overlap to be undone in public, over the seconds after it
	happens, instead of never occurring. Measured on a staged merge: on current positions alone the
	pair went from 6 studs apart to 19.3 over three seconds and were still inside each other at the
	end of it; opening the gap from the moment they both commit, they arrive in the lane already
	strung out.

	`physical` records are compared on position only. A wreck's `targetCross` is the lane it was
	steering for before the crash and it is never written again, so it would fence off a lane the
	debris has nothing to do with (the same trap `_laneFree` documents at length). ]]
function TrafficController._sharesLane(self, rec, other): boolean
	local clearance = TrafficConfig.SideClearance
	if math.abs(other.cross - rec.cross) < clearance then
		return true
	end
	return not (rec.physical or other.physical)
		and math.abs(other.targetCross - rec.targetCross) < clearance
end

--[[ Ease off the car in front. The only thing in this layer that acts ALONG the road rather than
	across it, and the reason two cars can no longer occupy the same stretch of lane.

	Everything else here resolves a conflict by moving sideways, and at a wall course there is
	nowhere sideways to go: `gate`, `heavyGate` and both `wallGap`s leave one lane open out of five,
	so every car in the four walled lanes is steered into the same gap and `_avoid` is under orders
	not to care who is already in it. Two cars abreast approaching that gap have no lane answer at
	all — one of them simply has to take it second. That is this.

	It reads the whole fleet rather than a cached neighbour, which is 12x12 scalar comparisons in the
	worst case and cheaper than the near-miss pass that already runs beside it. The alternative is a
	per-car "who is in front of me" cache, and a cache would have to be invalidated by every lane
	change, spawn, recycle, knock, shove and rebase in the file.

	WHICH OF A PAIR GIVES WAY is decided by nothing more than which is behind, so both cars reach the
	same answer from opposite sides and exactly one of them brakes. An exact dead heat would leave
	neither yielding; it is not a state that can hold, because `cruise` is rolled from a continuous
	range and no two cars carry the same one, so any pair drifts off level within a frame or two and
	the one that ends up behind takes the gap. A tie-break here would be code for a case that cannot
	persist.

	The leader may be a wreck (`physical`) or the steal target (`frozen`) — both are still things it
	looks broken to drive through, and both are already tracked in the road frame. ]]
function TrafficController._headway(self, rec, dt: number)
	local cfg = TrafficConfig.Headway
	local target = rec.cruise

	if cfg.Enabled then
		local leader, leaderGap
		for _, other in self._cars do
			if other ~= rec and self:_sharesLane(rec, other) then
				local gap = other.along - rec.along
				if gap > 0 and gap < cfg.LookAhead and (not leaderGap or gap < leaderGap) then
					leader, leaderGap = other, gap
				end
			end
		end
		if leader then
			-- Match its speed, minus whatever it takes to open the gap back up to `MinGap`. The
			-- second term is what makes an overlap resolve rather than merely stop getting worse:
			-- matching speeds inside somebody's boot would hold the two cars merged forever.
			local encroach = math.max(cfg.MinGap - leaderGap, 0)
			target = math.min(target, self:_roadSpeed(leader) - encroach * cfg.GapGain)
			target = math.max(target, rec.cruise * cfg.MinSpeedFactor)
		end
	end

	-- The stop lamps read this (`_braking`). A deadband, because the target chases a moving
	-- leader and a lamp that answered every fractional correction would strobe.
	rec.braking = target < rec.speed - BrakeLightConfig.Traffic.MinDrop
	local rate = if target < rec.speed then cfg.Brake else cfg.Recover
	rec.speed += math.clamp(target - rec.speed, -rate * dt, rate * dt)
end

function TrafficController._steer(self, rec, dt: number, now: number)
	-- Forced: something is in the way. Checked on its own (short) clock, because reacting to a
	-- barrier can't wait for a lane-change timer that might be ten seconds out.
	if now >= rec.avoidAt then
		rec.avoidAt = now + TrafficConfig.AvoidCheckInterval
		if self:_obstacleAhead(rec.along, rec.targetCross, TrafficConfig.AvoidLookahead, rec) then
			self:_avoid(rec, now)
		end
	end

	local zone = TrafficConfig.PlayerLaneChangeZone
	local delta = rec.along - self._playerAlong
	local protected = delta >= -zone.Behind and delta <= zone.Ahead
	if rec.plannedLane then
		-- A car that enters the player's decision window while warning abandons the routine move. A
		-- stale arrow is worse than a cancelled maneuver, and the timer gives it a long cooldown.
		if protected or self._stealLaneChangesLocked then
			self:_cancelLanePlan(rec)
			self:_armLaneTimer(rec, now)
		elseif now >= rec.laneCommitAt then
			if not self:_commitLane(rec, rec.plannedLane, now) then
				self:_armLaneTimer(rec, now)
			end
		else
			local phase = (rec.laneCommitAt - now) * TrafficConfig.LaneChangeWarning.FlashHz
			self:_setWarningVisible(rec, math.floor(phase * 2) % 2 == 0)
		end
	end

	-- Routine: personality, on the tier's own cadence. Most of those ticks are meant to come to
	-- nothing (`RoutineLaneChangeChance`), and the timer is re-armed either way, so a boxed-in car
	-- isn't left retrying every frame.
	if not self._stealLaneChangesLocked and not rec.plannedLane and now >= rec.laneAt then
		local allowed = self._rng:NextNumber() < TrafficConfig.RoutineLaneChangeChance
			and (not protected or self._rng:NextNumber() < zone.Chance)
		if not allowed or not self:_planLane(rec, now) then
			self:_armLaneTimer(rec, now)
		end
	end

	local step = TrafficConfig.LaneChangeSpeed * dt
	local move = math.clamp(rec.targetCross - rec.cross, -step, step)
	rec.cross += move
	if rec.warningMoving then
		if math.abs(rec.targetCross - rec.cross) <= 0.01 then
			rec.warningMoving = false
			self:_setWarningVisible(rec, false)
		else
			self:_setWarningVisible(rec, math.floor(now * TrafficConfig.LaneChangeWarning.FlashHz * 2) % 2 == 0)
		end
	end
	local rate = if dt > 1e-5 then move / dt else 0
	rec.lateral += (rate - rec.lateral) * (1 - math.exp(-dt * HEADING_BLEND))

	-- Last, so it measures the cross positions this frame's lane easing has already produced: a
	-- car is inside somebody else's lane band from the first frame it moves into it, not the one
	-- after. `_place` reads `speed` straight after this to aim the shell, so the heading follows
	-- the braking for free.
	self:_headway(rec, dt)
end

function TrafficController._updateCars(self, dt: number)
	local now = os.clock()
	local behind = self._playerAlong - TrafficConfig.DespawnBehind
	local ahead = self._playerAlong + TrafficConfig.DespawnAhead

	for i = #self._cars, 1, -1 do
		local rec = self._cars[i]
		-- A physical car's position is the engine's to set, so we only read it. Everything else is
		-- still driven from road-frame scalars.
		if rec.physical then
			self:_trackPhysical(rec, now)
			-- ...and let the player shove it out of the way if they are stuck against it (`_give`),
			-- or recycle it outright once they have been stuck on it too long to be shoving.
			if self:_give(rec, dt) then
				table.remove(self._cars, i)
				self:_release(rec)
				continue
			end
		else
			rec.along += rec.speed * dt
		end

		-- Before the branches below, so a car released by them is switched off after this rather
		-- than left lit by it.
		CarBlinkers.signal(rec.blinkers, self:_signalSide(rec), now)
		CarBrakeLights.set(rec.brakes, self:_braking(rec), now)

		--[[ A frozen car is the steal target: somebody is standing on its roof. It keeps DRIVING —
			the mount is on a moving car and that's the whole shot — but it stops being traffic:
			no despawn window, no lane change, no avoid swerve. The promise the landing made has to
			survive the beat between landing and taking the wheel, and a target that recycled or
			changed lane under the player's feet would break it in the most confusing way possible.

			(`_knock` refuses one too, so being rear-ended mid-steal can't hand your prize to physics.) ]]
		if rec.frozen then
			self:_place(rec)
		elseif rec.along < behind or rec.along > ahead then
			table.remove(self._cars, i)
			self:_release(rec)
		elseif not rec.physical then
			self:_steer(rec, dt, now)
			local debug = TrafficConfig.Debug
			if debug.Enabled and now >= (rec.debugAt or 0) then
				rec.debugAt = now + debug.SampleInterval
				local playerSpeed = self._playerCar.PrimaryPart.AssemblyLinearVelocity:Dot(self._info.forward)
				rec.model:SetAttribute("TrafficDebugTargetSpeed", rec.cruise)
				rec.model:SetAttribute("TrafficDebugClosingSpeed", playerSpeed - rec.speed)
			end
			local visual = TrafficConfig.VisualUpdate
			local fullRate = math.abs(rec.along - self._playerAlong) <= visual.FullRateDistance
			if fullRate or now >= (rec.visualAt or 0) then
				self:_place(rec)
				rec.visualAt = now + visual.FarInterval
			end
		end
	end
end

function TrafficController._queueFormation(self)
	local waves = TrafficConfig.DensityWaves
	local formations = waves.Formations
	if #formations == 0 then
		return
	end
	local formation = formations[self._rng:NextInteger(1, #formations)]
	local minLane, maxLane = 0, 0
	for _, slot in formation.Slots do
		minLane = math.min(minLane, slot.Lane)
		maxLane = math.max(maxLane, slot.Lane)
	end
	local first = 1 - minLane
	local last = #TrafficConfig.Lanes - maxLane
	if first > last then
		return -- malformed formation; config tests catch it, runtime fails open to random traffic
	end
	local center = self._rng:NextInteger(first, last)
	local anchor = self._playerAlong + self._rng:NextNumber(TrafficConfig.SpawnAheadMin, TrafficConfig.SpawnAheadMax)
	self._formationQueue = {}
	for _, slot in formation.Slots do
			table.insert(self._formationQueue, {
			along = anchor + slot.Along,
			lane = center + slot.Lane,
			speedScale = slot.SpeedScale,
			paceFraction = slot.PaceFraction,
		})
	end
end

function TrafficController._maybeSpawn(self, now: number)
	local target = self:_targetCarsAhead()
	local aheadCount = self:_carsAhead()
	if aheadCount >= target or #self._cars >= self:_maxCars() then
		return
	end
	local refill = TrafficConfig.Refill
	local urgent = aheadCount <= target - refill.UrgentDeficit
	if now < self._spawnAt then
		-- A formation's intentional breathing room is valid only while the forward road is healthy.
		-- Once it is visibly depleted, pull that deadline closer without spawning every frame.
		if urgent and self._spawnAt - now > refill.UrgentInterval then
			self._spawnAt = now + refill.UrgentInterval
		end
		return
	end
	local weather = self:_weatherTraffic()
	local waves = TrafficConfig.DensityWaves
	if waves.Enabled and #self._formationQueue > 0 then
		local slot = table.remove(self._formationQueue, 1)
		local spawned = self:_spawnLive(slot.along, slot.lane, nil, nil, slot.speedScale, slot.paceFraction)
		if not spawned then
			self._spawnAt = now + refill.FailedRetry
		elseif #self._formationQueue > 0 then
			self._spawnAt = now + self._rng:NextNumber(waves.PackInterval[1], waves.PackInterval[2])
		else
			self._spawnAt = now + self._rng:NextNumber(waves.BreathingRoom[1], waves.BreathingRoom[2])
		end
		return
	end
	--[[ Scaled, and it has to be scaled as well as the cap raised: the cap alone would take rush
		hour most of a run to reach, because a road nine cars short of its new ceiling still only
		fills at one car every couple of seconds. `Spawn` is the seconds BETWEEN attempts, so it is
		the one multiplier here that is below 1 for a busier road. ]]
	local interval = TrafficConfig.SpawnInterval
	self._spawnAt = now
		+ if urgent then refill.UrgentInterval else self._rng:NextNumber(interval[1], interval[2]) * weather.Spawn
	if waves.Enabled and self._rng:NextNumber() < waves.FormationChance then
		self:_queueFormation()
		if #self._formationQueue > 0 then
			local slot = table.remove(self._formationQueue, 1)
			local spawned = self:_spawnLive(slot.along, slot.lane, nil, nil, slot.speedScale, slot.paceFraction)
			self._spawnAt = now
				+ if spawned then self._rng:NextNumber(waves.PackInterval[1], waves.PackInterval[2]) else refill.FailedRetry
			return
		end
	end
	local spawned = self:_spawnLive(self._playerAlong + self._rng:NextNumber(TrafficConfig.SpawnAheadMin, TrafficConfig.SpawnAheadMax))
	if not spawned then
		self._spawnAt = now + refill.FailedRetry
	end
end

-- === Clipping ===============================================================

--[[ Poll for a clip against a sensor volume that SHADOWS the car's HitBox and reaches
	`Collision.ClipMargin` studs past it on every horizontal side — not against the HitBox itself,
	which is what this was and what only ever worked from the side.

	The HitBox is the part that physically stops the car against a solid traffic car, and an
	overlap query needs real penetration rather than contact, so a head-on hit was hidden by the
	solver's own resolution of it: the tidier the contact, the less there was to find. Full
	derivation and the measurements behind the 0.5 are in TrafficConfig.Collision.ClipMargin.

	Sized from the live hull on every poll, exactly like ObstacleController's wall sensor, so a
	redressed car with a different hull gets the right volume without anything being re-measured. ]]
function TrafficController._checkClips(self)
 local hitBox, sensor = self._hitBox, self._clipSensor
 if not (hitBox and hitBox.Parent and sensor) then
  self._clipPrevious, self._clipPreviousBox = nil, nil
  return
 end
 local margin = if self._solid then TrafficConfig.Collision.ClipMargin else 0
 local size = hitBox.Size + Vector3.new(margin * 2, 0, margin * 2)
 sensor.Size = size
 sensor.CFrame = hitBox.CFrame

 -- Query real contact before applying the controlled impact. No anchored hull can stop the car.
 for _, part in workspace:GetPartsInPart(sensor, self._clipParams) do
  local rec = self._byPart[part]
  if rec and not rec.clipped then self:_onClip(rec) end
 end

 -- Sweep the space crossed between frames so fast driving cannot skip a whole car.
 -- Large discontinuities are road rebases/teleports, not collisions.
 local previous = if self._clipPreviousBox == hitBox then self._clipPrevious else nil
 local current = hitBox.CFrame
 self._clipPrevious, self._clipPreviousBox = current, hitBox
 if previous then
  local displacement = current.Position - previous.Position
  if displacement.Magnitude > 0.01 and displacement.Magnitude <= TrafficConfig.Collision.SweepMaxDistance then
   local params = self._clipSweepParams
   if not params then params = RaycastParams.new();self._clipSweepParams = params end
   params.FilterType = Enum.RaycastFilterType.Include
   params.FilterDescendantsInstances = self._clipParams.FilterDescendantsInstances
   params.CollisionGroup = self._clipParams.CollisionGroup
   params.RespectCanCollide = false
   for _ = 1, 4 do
    local result = workspace:Blockcast(previous, size, displacement, params)
    if not result then break end
    local rec = self._byPart[result.Instance]
    if not rec or rec.clipped then break end
    self:_onClip(rec)
   end
  end
 end
end


--[[ Sideswiped a traffic car. Charged once per car — its volume goes query-blind until the car
	is recycled — so grinding down the side of one isn't a bleed. Query-blind, note, not
	ghostly: `CanCollide` is untouched, so a car you've already been charged for goes on
	physically blocking you for the rest of its life. It stops costing HP; it doesn't stop being
	a car.

	The centre-to-centre vector is the right hit direction here precisely BECAUSE this fires on
	first contact: at that instant the two boxes have only just touched, so the vector points at
	the corner of the car that actually made contact — nose for a rear-end, flank for a drift-in,
	diagonal for a corner. (Sampled later in the overlap it would be meaningless: these volumes
	are 22 studs long.) applyImpact walks that direction out to the bodywork for the smoke. ]]
function TrafficController._onClip(self, rec)
	rec.clipped = true
	rec.hit.CanQuery = false
	--- Not charged in the truck's shelter (`GetawayConfig.Shelter`, 2026-10-09): a car caught at the
	--- ramp is not to be rear-ended into a wreck. Marked clipped all the same, so it is never charged.
	local getaway = self._getaway or Shard.get("GetawayController")
	self._getaway = getaway
	if getaway and getaway:isSheltered() then
		return
	end

	local primary = self._playerCar and self._playerCar.PrimaryPart
	local delta = if primary then rec.hit.Position - primary.Position else nil

	-- +1 = the car we hit is on our RIGHT. Without a car to measure against there's no side to
	-- speak of, so the knock picks one — a spin in an arbitrary direction still beats none.
	local side
	if primary and delta then
		side = if delta:Dot(primary.CFrame.RightVector) >= 0 then 1 else -1
	else
		side = if self._rng:NextNumber() < 0.5 then 1 else -1
	end

	-- How hard, measured once and used for all three of: what the car does, what we feel, and what
	-- it costs. One number keeps those three consistent — a hit that looks light has to be light.
	local severity, closing = 1, nil
	if delta then
		severity, closing = self:_severity(rec, delta)
	end

	self:_knock(rec, side, severity)
	-- One hit still pays damage; release live scrape contact until this shell is recycled.
	if not rec.physical and not rec.frozen then rec.hit.CanCollide = false end

	if primary and delta and self._obstacles then
		-- When the car is solid the real contact has already shoved us, so only the feel is
		-- scripted; `Clip`'s full shove is for the non-colliding fallback. See Collision.ClipFeel.
		local kind = if TrafficConfig.Collision.Enabled then TrafficConfig.Collision.ClipFeel else TrafficConfig.Clip
		-- yawTowards = 1: a clip destabilises you INTO the thing you hit, same as an obstacle.
		-- (The wall is the exception, for reasons in ObstacleConfig.Wall.)
		self._obstacles:applyImpact(side, self:_scaleKind(kind, severity, closing), 1, delta, "Car")
	end

	-- The server prices it and owns the HP. Severity is the one thing it can't measure for itself
	-- (only this client has both cars), so we send that and nothing else — there's still no id for
	-- it to look anything up in. See TrafficConfig.ClipCooldown for what trusting this does and
	-- doesn't cost.
	self:getRemoteEvent("TrafficHit"):Fire(severity)

	--[[ …and the one contact that is worth something as well as costing something: a rub the other car
		shrugged off is TRADING PAINT, the bottom rung of the near-miss ladder (NearMissConfig). The
		ceiling is checked there, so a real crash reaching this line is a no-op.

		A SECOND REPORT RATHER THAN A RIDER ON THE ONE ABOVE, and the two are not interchangeable. That
		one is priced in HP by TrafficService behind a 0.4s cooldown; this one is priced in cash by
		RewardService with no cooldown, because it shares a chain with the near misses and the client
		prices that same chain for the toast. A report the server refused for a cooldown the client
		cannot see is precisely the desync that would have the screen promise money the results screen
		does not pay. One event, two resources, two owners, two channels. ]]
	if self._nearMiss then
		self._nearMiss:registerContact(severity, rec.token)
	end
end

-- === Near misses ============================================================

--[[ Half-extent of an oriented box along one world axis: the box's own reach measured in the
	direction we care about.

	CONSERVATIVE FOR A ROTATED BOX, which is the right direction to be wrong in here. Both cars yaw
	constantly — the player is steering and the traffic car is easing between lanes — so treating
	either as axis-aligned would under-state its width exactly when it is most turned across the
	road. Summing the three projected half-extents is the enclosing box, so a yawed car measures
	WIDER and the gap it leaves measures TIGHTER, which is what a player looking at a car crossing
	their bonnet would say too. Same composition RaceUIController frames the trophy with. ]]
local function reachAlong(cf: CFrame, size: Vector3, axis: Vector3): number
	local half = size * 0.5
	return math.abs(cf.XVector:Dot(axis)) * half.X
		+ math.abs(cf.YVector:Dot(axis)) * half.Y
		+ math.abs(cf.ZVector:Dot(axis)) * half.Z
end

--[[ Lean on a wreck and it gives. The other half of `_knock`, and the reason a rear-end is no
	longer a dead end — TrafficConfig.Knock.Give carries the measurements and the argument.

	A knocked shell masses 985-1269 against the player car's 421 and stops within a stud of where it
	was hit, so the ordinary end of a rear-end is a player parked against something three times their
	weight that no other path in this file can shift: `_onClip` charges a car once for life so it can
	never be re-knocked, `_headway` skips `physical` records, and the despawn window is measured from
	a player who is no longer moving. This is what breaks that, by talking the mass down for as long
	as somebody is leaning on it.

	IT LIVES DOWN HERE, next to `reachAlong`, rather than up with `_trackPhysical` where it belongs by
	subject. The contact test IS that helper, and a function defined earlier in the chunk cannot see a
	local declared later in it — the name would resolve as a global and be nil, silently. Placement is
	the whole reason these two are neighbours; there is nothing else joining them.

	THE TEST IS DELIBERATELY QUERY-FREE. A clipped car's volume is `CanQuery = false` for the rest of
	its life, so `GetPartsInPart` cannot see the very cars this exists for, and switching that back on
	would put debris in front of every other query in the game — the steal's landing probe first among
	them. Projecting both boxes' half-extents onto the road's own axes is the same measurement
	`_checkNearMisses` makes a few lines below, in the same pass, for the same reason. ]]
function TrafficController._give(self, rec, dt: number): boolean
	local cfg = TrafficConfig.Knock.Give
	if not (cfg and cfg.Enabled) then
		return false
	end
	local hitBox, info = self._hitBox, self._info
	local primary = self._playerCar and self._playerCar.PrimaryPart
	if not (hitBox and hitBox.Parent and primary and info) then
		return false
	end

	local theirs = rec.hit
	local forward, cross = info.forward, info.cross
	local delta = theirs.Position - hitBox.Position
	local alongGap = math.abs(delta:Dot(forward))
		- (reachAlong(hitBox.CFrame, hitBox.Size, forward) + reachAlong(theirs.CFrame, theirs.Size, forward))
	local crossGap = math.abs(delta:Dot(cross))
		- (reachAlong(hitBox.CFrame, hitBox.Size, cross) + reachAlong(theirs.CFrame, theirs.Size, cross))

	local give = rec.give or 0
	local stalled = false
	if alongGap <= cfg.Gap and crossGap <= cfg.Gap then
		--[[ Touching AND stalled is the whole "I am pushing on this" signal, and it needs no throttle
			plumbed through from DriveController: the only reason to be stationary against a wreck is
			to be driving into one. Holding what has been earned for as long as the contact lasts —
			rather than recovering the moment the car starts to roll — is what keeps a shove from
			becoming a stutter. ]]
		stalled = math.abs(primary.AssemblyLinearVelocity:Dot(forward)) < cfg.Speed
		if stalled and cfg.Time > 0 then
			give = math.min(give + dt / cfg.Time, 1)
		end
	elseif cfg.Recover > 0 then
		give = math.max(give - dt / cfg.Recover, 0)
	else
		give = 0
	end
	self:_setGive(rec, give)

	--[[ AND IF LIGHTENING IT WAS NOT ENOUGH, IT GOES (2026-10-07). A wreck knocked into the side can
		end up pinned between your car and the rail, or simply inside your hull, and then no mass is
		light enough: the "hit it into the side and you're stuck" report. Stalled against the same
		wreck for `ClearAfter` seconds straight answers true and the caller recycles it. Any frame
		not stalled against it starts the count again. ]]
	rec.leanFor = if stalled then (rec.leanFor or 0) + dt else 0
	return cfg.ClearAfter ~= nil and cfg.ClearAfter > 0 and rec.leanFor >= cfg.ClearAfter
end

--[[ PUBLIC (DriveController's pinned reset) — recycle every KNOCKED car within `radius` studs of
	`position`. Live traffic is left alone: it drives off on its own, and only a wreck can sit in the
	spot the reset is about to put the car back into. ]]
function TrafficController.clearWrecksNear(self, position: Vector3, radius: number)
	for i = #self._cars, 1, -1 do
		local rec = self._cars[i]
		if rec.physical and rec.root and (rec.root.Position - position).Magnitude <= radius then
			table.remove(self._cars, i)
			self:_release(rec)
		end
	end
end

-- The mass a shove has talked down: 0 is the car as it was knocked, 1 is `Give.MinDensityFactor` of
-- it. Written through one function so the ramp and the pool reset cannot disagree about what "back
-- to normal" means, and skipped when nothing has changed — this runs per stuck car per frame, and
-- `CustomPhysicalProperties` is a rebuild of the part's mass every time it is assigned.
function TrafficController._setGive(self, rec, give: number)
	if rec.give == give then
		return
	end
	rec.give = give
	local knock = TrafficConfig.Knock
	local floor = knock.Give.MinDensityFactor
	rec.hit.CustomPhysicalProperties = PhysicalProperties.new(
		knock.Density * (1 - give * (1 - floor)),
		knock.Friction,
		knock.Elasticity
	)
end

--[[ How close you came to every car you DIDN'T hit, and the moment to say so.

	Run once per frame, immediately after the clip poll and before the cars are advanced — the same
	frame ordering, for the same reason, as the poll itself (see `_loop`): physics has already
	resolved the player's car against each traffic car's current position, so this is the one moment
	in the frame where the two are where the solver last agreed they were.

	AFTER THE CLIP POLL SPECIFICALLY, so a car that has just been charged for is already flagged
	`clipped` and disqualified below. That ordering is the whole of "you cannot be paid for touching
	it": the gap thresholds sit clear above the clip sensor's margin (NearMissConfig.Gap), so a
	contact and a near miss are different bands of the same measurement, and the flag settles the
	frame where both could fire.

	=== THE THREE THINGS A PASS HAS TO BE =====================================================

	  1. SIDE BY SIDE. `alongGap <= 0` means the two boxes overlap on the road's forward axis, i.e.
	     the cars are level with each other to some degree. Until that is true there is no gap worth
	     measuring — a car 40 studs ahead in the next lane is not a near miss however narrow the
	     lane is.
	  2. YOURS. You have to be closing on it at `MinPassSpeed` along the road. A car that overtakes
	     YOU pays nothing, and neither does drifting along beside one at matched speed.
	  3. CLOSE. The narrowest cross-axis gap seen while (1) and (2) hold is what gets priced, so a
	     pass is scored on its tightest moment rather than on wherever it happened to be when the
	     award fired.

	=== AND IT FIRES WHEN THE CARS DRAW LEVEL ==================================================

	`dAlong <= 0` is the first frame the traffic car's centre is BEHIND ours: the instant of the
	pass. That is deliberately not the end of the overlap, which is where the obvious implementation
	puts it — two 22-stud cars closing at 25 studs/s take about 1.8 seconds to slide past each other
	completely, so awarding on separation would land the toast and the sound the better part of a
	second after the whoosh they belong to, which reads as lag rather than as feedback.

	It also gets the "did I actually overtake it?" test for free, because the sign can only reach
	`<= 0` by our having gone past: a car cannot arrive behind us any other way (spawns are at least
	`SpawnAheadMin` studs ahead, and a car we never caught keeps a positive sign until it recycles).

	ONE PER CAR, for the same reason a clip is charged once per car: without it, easing off and
	drawing level again pays twice, and a player who worked out that oscillating beside one car beats
	driving would be right. `nearAwarded` is cleared in `_release`, so a recycled shell is a fresh
	car — which is the same reset, in the same place, that `clipped` and `frozen` depend on. ]]
function TrafficController._checkNearMisses(self)
	if not (NearMissConfig.Enabled and self._nearMiss) then
		return
	end
	local hitBox = self._hitBox
	local primary = self._playerCar and self._playerCar.PrimaryPart
	local info = self._info
	if not (hitBox and hitBox.Parent and primary and info) then
		return
	end

	local forward, cross = info.forward, info.cross
	local mineCF, mineSize = hitBox.CFrame, hitBox.Size
	local minePos = mineCF.Position
	local myReachAlong = reachAlong(mineCF, mineSize, forward)
	local myReachCross = reachAlong(mineCF, mineSize, cross)
	-- Our own speed DOWN THE ROAD, not our speed: a car sliding sideways at 40 studs/s is not
	-- overtaking anything. Read once for the whole fleet.
	local mySpeed = primary.AssemblyLinearVelocity:Dot(forward)

	for _, rec in self._cars do
		--[[ Three kinds of car this can never be about. A `physical` one is debris you have already
			hit and handed to physics — it is tumbling, not driving, and being paid for passing your
			own wreckage is being paid twice for the same mistake. A `frozen` one is the car you are
			landing on mid-steal, which you are about to be standing on rather than passing. And a
			`clipped` one you have already been billed for. ]]
		if not (rec.physical or rec.frozen or rec.clipped or rec.nearAwarded) then
			local theirs = rec.hit
			local delta = theirs.Position - minePos
			local dAlong = delta:Dot(forward)
			local alongGap = math.abs(dAlong) - (myReachAlong + reachAlong(theirs.CFrame, theirs.Size, forward))

			if alongGap <= 0 then
				local closing = mySpeed - rec.speed
				local crossDelta = delta:Dot(cross)
				local gap = math.abs(crossDelta) - (myReachCross + reachAlong(theirs.CFrame, theirs.Size, cross))
				if closing >= NearMissConfig.MinPassSpeed then
					rec.nearGap = if rec.nearGap then math.min(rec.nearGap, gap) else gap
				end
				-- The pass-by whoosh, once per car on the frame it draws level. See `_whoosh`.
				if dAlong <= 0 and not rec.whooshed then
					rec.whooshed = true
					self:_whoosh(rec, gap, closing)
				end
				--[[ ...and this is the first frame past their centre, i.e. the pass. Whatever it got
					down to by now is what it was worth; `tierFor` answers nil for anything that was
					never close enough, and a pass that has not qualified YET is left open rather than
					closed off — cutting back in front of a car you went past wide is a real close call,
					and it happens a beat after this test first runs. The overlap ending is what ends the
					measurement, because this whole branch is inside it. ]]
				if dAlong <= 0 and rec.nearGap then
					local tier = NearMissConfig.tierFor(rec.nearGap)
					if tier then
						rec.nearAwarded = true
						-- Which side it went past on, for threading (`NearMissConfig.isThread`).
						self._nearMiss:register(tier, rec.nearGap, if delta:Dot(cross) >= 0 then 1 else -1, rec.token)
					end
				end
			end
		end
	end
end

--[[ The pass-by: a positional whoosh on the car we just drew level with, so it pans to its side
	(`NearMissConfig.Whoosh`). Louder and higher the faster we closed on it; nothing for a car we only
	crept past or passed a lane and more away. ]]
function TrafficController._whoosh(self, rec, gap: number, closing: number)
	local cfg = NearMissConfig.Whoosh
	if not (cfg.Enabled and self._sounds) or gap > cfg.MaxGap or closing < cfg.MinClosing then
		return
	end
	local t = math.clamp((closing - cfg.MinClosing) / math.max(cfg.FullClosing - cfg.MinClosing, 1e-3), 0, 1)
	self._sounds:PlayRandomAt(
		cfg.Group,
		rec.hit,
		cfg.PitchMin + (cfg.PitchMax - cfg.PitchMin) * t,
		cfg.VolumeMin + (cfg.VolumeMax - cfg.VolumeMin) * t,
		cfg.RollOffMinDistance,
		cfg.RollOffMaxDistance
	)
end

-- === Loop / lifecycle =======================================================

-- Our car and its hull, via RoadController (which already resolves the car from the seat we're
-- welded to). The Model replicates piecemeal, so the HitBox can arrive a beat after it — keep
-- asking rather than latching the first (nil) answer, which would silently disable every clip
-- for the whole race.
function TrafficController._resolveCar(self): boolean
	local car = self._road:getCar()
	if car ~= self._playerCar then
		self._playerCar = car
		self._hitBox = nil
	end
	if car and not (self._hitBox and self._hitBox.Parent) then
		self._hitBox = car:FindFirstChild(ObstacleConfig.HitBoxName, true)
	end
	return car ~= nil and car.Parent ~= nil and car.PrimaryPart ~= nil
end

function TrafficController._loop(self, dt: number)
	if not self._active then
		return
	end
	local info = self._road:getRoadInfo()
	if not (info and self:_resolveCar()) then
		return -- road or car not up yet; nothing to position traffic against
	end
	self._info = info
	self._playerAlong = self._road:along(self._playerCar.PrimaryPart.Position)

	local now = os.clock()
	if now >= self._filterAt then
		self._filterAt = now + 0.25
		self:_refreshObstacleFilter()
	end

	-- A revive is being set down somewhere in this road; keep the spot empty until it has landed.
	if now < self._clearUntil then
		self:_clearAround(self._playerAlong)
	end

	if not self._primed then
		self._primed = true
		self:_prime()
	end

	--[[ Clips are polled BEFORE the cars are advanced, and that order is load-bearing rather than
		incidental. Physics has already run by the time Heartbeat fires, so the player's car sits
		where the solver left it against each traffic car's CURRENT position — advance them first
		and the poll compares it against a position nothing has been simulated against yet, opening
		a `speed * dt` gap (half a stud at 60fps, more as the frame rate drops) in precisely the
		case it exists to catch. Measured on its own, that ordering alone halved what the old poll
		could see of a head-on contact; the sensor margin in TrafficConfig.Collision.ClipMargin is
		the other half of why rear-ending a car used to register almost nothing.

		A wreck freezes the road's *interaction* but not the road: traffic keeps driving past while
		the car coasts to a stop, which is what makes the beat land. ]]
	if not (self._wrecked or self._suspended) then
		self:_checkClips()
		-- Second, and only ever second — see `_checkNearMisses`. Gated by the same two flags as the
		-- poll above it, and for the same reasons: you cannot shave past a car while coasting to a
		-- stop in a wreck, and you certainly cannot while flying over the road with your car hidden
		-- and anchored underneath you.
		self:_checkNearMisses()
	else
		self._clipPrevious, self._clipPreviousBox = nil, nil
	end
	-- ...and a frozen road does not receive cars either. The spawn cadence is the one thing in here
	-- that runs on the real clock rather than the scaled one, so it is the one thing a hold has to
	-- be told about explicitly. See `setFrozen`.
	if not (self._wrecked or self._frozen or self._noSpawn) then
		--- Before the ordinary spawner and behind the same three gates: the prime IS a spawn (see
		--- `_prime`), so a road closed to traffic must not go on filling itself from a booking made
		--- before it closed.
		self:_stepPrime()
		self:_maybeSpawn(now)
	end
	-- Slow motion (Modules/TimeScale). This is where most of the EFFECT of slow-mo actually lives:
	-- the whole population is scripted off this dt, so scaling it here slows every car on the road
	-- at once. 1.0 whenever no flight is in progress. Applied here rather than at the top of the
	-- loop so the spawn cadence and the clip poll keep running on real time — a flight is short,
	-- and a road that stopped topping itself up during one would read as traffic thinning out.
	self:_updateCars(dt * TimeScale.get())
end

--[[ A rebase moved the road out from under us (RoadController._shiftWorld). Our positions are
	road-frame scalars, so correcting them is one addition each — and re-placing inside the
	callback keeps the rebase atomic for traffic too, instead of leaving a frame where the cars
	sit at the old coordinates. ]]
function TrafficController._onWorldShift(self, shift: Vector3)
	if not (self._active and self._info) then
		return
	end
	local delta = shift:Dot(self._info.forward)
	if delta == 0 then
		return
	end
	self._playerAlong += delta
	for _, rec in self._cars do
		if rec.physical then
			-- Physics owns this one's CFrame, so the rebase has to move it rather than recompute it.
			-- `PivotTo` leaves the assembly's velocity alone, which is what we want: the car should
			-- carry on tumbling exactly as it was, just somewhere else. Its `along`/`cross` are read
			-- back off the new position on the next frame, so there's nothing else to correct.
			rec.model:PivotTo(rec.model:GetPivot() + shift)
		else
			rec.along += delta
			self:_place(rec)
		end
	end
end

-- Public: the live traffic, for the steal flow to pick a target out of. Each record's `model`
-- carries `Tier` / `TrafficId` attributes and its `hit` is the volume to land on.
function TrafficController.getCars(self)
	return self._cars
end

--[[ PUBLIC (StealController) — stop and restart charging for clips.

	Suspended for the duration of a flight: the player's car is hidden, anchored and being flown
	along the deck under the flight avatar, so it is still driving through every traffic car it was
	about to reach. You cannot be clipped in mid-air (plan §6, Phase 1).

	Only the poll stops. Traffic keeps driving, keeps spawning and keeps being solid, so the world
	the player is falling into is exactly the world they bailed out of. ]]
function TrafficController.setSuspended(self, suspended: boolean)
	self._suspended = suspended
end

--[[ PUBLIC (StealController) — pause only ROUTINE lane-change decisions during a flight.

	A car already crossing continues to its advertised lane, and forced obstacle avoidance remains
	functional. What stops is a fresh random plan that the flight predictor cannot account for. The
	window is normally under two seconds and affects presentation only; traffic speed, headway,
	spawning and recycling all continue. ]]
function TrafficController.setStealLaneChangesLocked(self, locked: boolean)
	self._stealLaneChangesLocked = locked == true
	if not self._stealLaneChangesLocked then
		return
	end
	local now = os.clock()
	for _, rec in self._cars do
		if rec.plannedLane then
			self:_cancelLanePlan(rec)
			self:_armLaneTimer(rec, now)
		end
	end
end

--[[ PUBLIC (TutorialDirector) — stop and restart the automatic spawner, leaving everything else
	about the population alone.

	The tutorial's run is CHOREOGRAPHED (`TutorialConfig.Rig.Stage`): for the length of its in-race
	beats the director decides what is on the road, and a spawner topping up underneath it would be
	dealing a second hand into the first. Cars already out keep driving, keep being solid and keep
	being stealable — this only closes the door.

	A DIFFERENT SWITCH FROM `setFrozen`, which also stops spawning: that one is part of stopping the
	world and comes off with it, and this one outlives several freezes. Two flags rather than one
	because they are turned off by different things, and a shared flag would have the end of a freeze
	handing the road back to the spawner in the middle of a staged beat. ]]
function TrafficController.setSpawning(self, on: boolean)
	self._noSpawn = not on
end

--[[ PUBLIC (TutorialDirector) — recycle every scripted car within `studs` AHEAD of the driver.

	Ahead only, and that is the point: a beat that is teaching a key wants the road in front of the
	player empty, and cars BEHIND them are both invisible and harmless. Recycling those too would
	cost the population for nothing and would be visible in a mirror the game does not have.

	PHYSICAL SHELLS ARE LEFT, for the reason they are left everywhere else in this file: one is
	debris the solver owns, it is behind the player by definition (it was hit), and taking it away
	mid-tumble is the disappearing-car bug `shoveCar`'s note describes. ]]
function TrafficController.clearAhead(self, studs: number)
	for i = #self._cars, 1, -1 do
		local rec = self._cars[i]
		local delta = rec.along - self._playerAlong
		if not rec.physical and not rec.frozen and delta >= 0 and delta <= studs then
			table.remove(self._cars, i)
			self:_release(rec)
		end
	end
end

--[[ PUBLIC (TutorialDirector) — is there a scripted car within `studs` AHEAD of the driver?

	The exact inverse of `clearAhead` and deliberately filtered the same way, so "I cleared it" and
	"there is nothing there" can never disagree: debris is not a car you can take, and a car already
	being stolen is not one that is still on offer.

	ASKED RATHER THAN REMEMBERED, and that is the whole reason this exists as a query. The director
	used to answer it by holding on to the record it placed, which cannot work: records are POOLED
	(`_release`), so a target that was recycled and its shell handed to a different car leaves the
	holder pointing at a live record for a car it never placed. `rec.hit.Parent` does not catch it
	either — releasing unparents the MODEL and leaves the part inside it, so the field stays truthy
	for the whole time the record is back in the pool.

	Whether anything is out there is also the honest question. What the steal beat needs is not its
	own car back; it is a car, any car, close enough to be worth jumping at. ]]
function TrafficController.hasCarAhead(self, studs: number): boolean
	for _, rec in self._cars do
		local delta = rec.along - self._playerAlong
		if not rec.physical and not rec.frozen and delta >= 0 and delta <= studs then
			return true
		end
	end
	return false
end

--[[ PUBLIC (TutorialDirector) — put one car on the road, here, in this lane, off this tier.

	The staged road's only way in. Everything about the car — its body, its colour, its speed, its
	lane-change timer — is rolled exactly as an ordinary spawn's would be, because a tutorial car
	the player is about to steal has to be a real car: it is the one they keep.

	`alongCoord` is ABSOLUTE in the road frame, not relative to the driver, so a caller composing
	several of them at a spacing gets a spacing rather than a drift.

	`lookahead` is how far past the mark the requested LANE has to be free of obstacles, and it is
	optional because only the steal target needs a different answer than the road does — see
	`_spawn`. ]]
function TrafficController.placeCar(self, alongCoord: number, lane: number?, tier: number?, lookahead: number?)
	return self:_spawn(alongCoord, lane, tier, lookahead)
end

--- PUBLIC (TutorialDirector) — how many lanes there are to ask for. The director alternates across
--- them so four cars read as a slalom rather than as a queue.
function TrafficController.laneCount(self): number
	return #TrafficConfig.Lanes
end

--[[ PUBLIC (TutorialDirector) — roughly how fast a car off this tier will be driving, studs/s.

	The MIDPOINT of the band `_spawn` rolls from, and the caller has to know it is a midpoint: the
	tutorial places its steal target by aiming AHEAD of where the car will be when the player comes
	down on it, and that lead is the car's own speed times the airtime. Half a band of error over a
	two-second flight is about six studs, which is inside what `StealController._reach` forgives.

	Off `self._tiers` rather than `TrafficConfig.Tiers`, because a ladder is per-WORLD — a tier 2 in
	the Arctic is not a tier 2 in the City, and a director reading the global table would aim a
	desert-paced lead at an arctic-paced car. Nil before a race has set one. ]]
function TrafficController.tierSpeed(self, tier: number): number?
	local tiers = self._tiers
	local spec = tiers and tiers[math.clamp(math.floor(tier), 1, math.max(#tiers, 1))]
	if not spec then
		return nil
	end
	-- Times the weather's own pace, or the lead would be aimed at a car driving a fifth faster than
	-- the one rush hour actually put there. Same multiplier `_spawn` bakes into `cruise`.
	local speed = if spec.SpeedFraction
		then (spec.SpeedFraction[1] + spec.SpeedFraction[2]) * 0.5 * self:_playerCruise()
		else (spec.Speed[1] + spec.Speed[2]) * 0.5
	return speed * self:_weatherTraffic().Speed
end

--[[ PUBLIC (TutorialDirector): the cruise every fraction in this file is a share of, in measured
	studs/s, falling back to `TrafficConfig.FallbackPlayerCruise` exactly as the spawner does.

	The tutorial's steal beat authors its own dials as shares of the same number (`StealTarget` in
	TutorialConfig), and it has to be THIS one rather than a second reading of the car: a director
	that resolved its own cruise would lead a target at one pace while the tier it asked for was
	rolled at another, which is a car placed for a jump nobody is making. ]]
function TrafficController.playerCruise(self): number
	return self:_playerCruise()
end

--- PUBLIC (TutorialDirector) — where the driver is in the road frame, which is the coordinate every
--- `placeCar` is measured from.
function TrafficController.playerAlong(self): number
	return self._playerAlong
end

--[[ PUBLIC (TutorialDirector) — which lane the driver is in RIGHT NOW, as an index into
	`TrafficConfig.Lanes`, or nil if the road frame is not up yet.

	=== WHY A CAR HAS TO BE PLACED IN THIS LANE AND NOT JUST "AHEAD" ==========================

	The lanes are `{-30, -15, 0, 15, 30}` — five of them, fifteen studs apart — and a steal only
	happens if the falling rider passes within `StealConfig.Prompt.Range` (18 studs, measured to the
	car's box surface) of something. One lane over is about eleven studs of surface and works. TWO
	lanes over is twenty-six and cannot, however well-aimed the jump is.

	So a target dropped into a lane picked at random is a coin flip, and it read exactly like one:
	the tutorial's steal beat worked first try once and then whiffed, with the player arcing over an
	empty lane while the car they were supposed to take sat thirty studs to the side. The flight has
	no candidate, so `TutorialController._watchFreeze` correctly never freezes — and the whole beat
	fails silently, ending in a wreck rather than a steal.

	The cross axis is projected out of the player's own car rather than tracked, because nothing else
	needed it: `_worldPos` composes `along`/`cross` into world space, and this is that inverse. ]]
function TrafficController.playerLane(self): number?
	local car = self._playerCar
	local info = self._info
	if not (car and car.PrimaryPart and info) then
		return nil
	end

	local cross = car.PrimaryPart.Position:Dot(info.cross) - info.driveCenter
	local best, bestGap = nil, math.huge
	for index, offset in TrafficConfig.Lanes do
		local gap = math.abs(offset - cross)
		if gap < bestGap then
			best, bestGap = index, gap
		end
	end
	return best
end

--[[ PUBLIC (RaceFreezeController) — the world has been stopped; stop being a population.

	A DIFFERENT THING FROM `setSuspended`, and the pair is worth keeping straight because they read
	alike and overlap in exactly one caller:

	    setSuspended  stop CHARGING for contact. A flight. The road keeps moving underneath it.
	    setFrozen     stop MOVING and stop ARRIVING. A hold. The road is not moving at all.

	Most of what a freeze wants is already free: `_updateCars` is driven off `dt * TimeScale.get()`,
	so a hold on the time scale stops every scripted car in the population without this being called
	at all. What is left is the two things that do not run on that dt —

	  • SPAWNING, which is deliberately on the real clock (see `_loop`) so a brief flight does not
	    read as traffic thinning out. A hold is not brief: the tutorial can sit at zero for as long
	    as it takes somebody to find a key, and a road that kept topping itself up through one would
	    come back with a wall of cars that all arrived while nothing was moving.
	  • PHYSICAL SHELLS. A knocked car belongs to the solver, and the solver has no time scale
	    (Modules/TimeScale). So debris is the one thing on this road that would carry on tumbling
	    through a frozen world, and it is anchored for the length of the hold and put back exactly
	    as it was found — velocity included, because anchoring does not clear it and a shell that
	    resumed from a stale one would jump.

	Idempotent, and it restores rather than assumes: a shell that was already anchored when the hold
	landed is left anchored on release. ]]
function TrafficController.setFrozen(self, frozen: boolean)
	frozen = frozen == true
	if frozen == (self._frozen == true) then
		return
	end
	self._frozen = frozen

	if frozen then
		--[[ Remembered per record rather than in one table keyed by part, because a record can be
			released back to the pool mid-hold (a despawn) and its parts reused for a different car.
			Hanging the memory off the record means it goes when the record does. ]]
		for _, rec in self._cars do
			if rec.physical and rec.root and rec.root.Parent then
				rec.holdVel = rec.root.AssemblyLinearVelocity
				rec.holdSpin = rec.root.AssemblyAngularVelocity
				rec.holdAnchored = rec.root.Anchored
				rec.root.Anchored = true
			end
		end
		return
	end

	for _, rec in self._cars do
		if rec.holdVel ~= nil then
			local root = rec.root
			if root and root.Parent then
				root.Anchored = rec.holdAnchored == true
				if not root.Anchored then
					-- Put back explicitly. Anchoring never cleared these, but the assembly may have
					-- been re-rooted while it was held, and a re-rooted assembly reports the velocity
					-- of whatever it joined rather than the one it arrived with.
					root.AssemblyLinearVelocity = rec.holdVel
					root.AssemblyAngularVelocity = rec.holdSpin
				end
			end
			rec.holdVel, rec.holdSpin, rec.holdAnchored = nil, nil, nil
		end
	end
end

--[[ PUBLIC (TutorialDirector) — how fast this car drives, from now on.

	BOTH FIELDS, and that is the whole subtlety. `speed` is what the car is doing and `cruise` is what
	it comes BACK to: `_headway` eases one toward the other every frame, so writing only `speed` is a
	nudge that has worn off a second later, and writing only `cruise` is a change that takes a second
	to arrive. The tutorial needs it now and needs it to stay.

	ONE CALLER, and its reason is worth knowing before this grows a second one. The tutorial's steal
	target has to be CATCHABLE: a bail closes the difference between the player's speed and the
	target's, over about two seconds, so a player who arrives at the beat slow — rear-ended during
	SURVIVE, say — cannot catch a car running at its own tier's pace no matter where it is placed.
	There is no distance that fixes that, because the gap is opening. So the car drives slower.

	It is only ever used to SLOW one (see `_placeStealTarget`), which matters: a rig that sped a car
	up would be making the game's signature move harder to land on the one run that has to land. ]]
function TrafficController.paceCar(self, rec, speed: number)
	if not rec then
		return
	end
	rec.cruise = speed
	rec.speed = speed
end

--[[ PUBLIC (StealController) — this car is being stolen; hold it still in every sense that isn't
	its speed. See `_updateCars` for what freezing actually withholds, and `_release` for why
	clearing it is not optional.

	Deliberately does NOT touch `rec.speed`. The mount happens on a moving car, and the handoff
	inherits that speed — freezing the motion would make the steal a full stop. ]]
function TrafficController.freezeCar(self, rec)
	if rec then
		rec.frozen = true
	end
end

--[[ PUBLIC (StealController) — move this car sideways by `delta` studs, right now. Returns whether
	it went.

	The handoff's alternative to deleting a car out of the landing spot. A car only marginally inside
	the space the player is about to occupy does not have to leave the ROAD to stop being a problem —
	it only has to not be there when the solver next looks, and a few studs sideways does that.
	Recycling it was the first version of `_clearLanding` and it reads to players as a bug: they watch
	a car in the next lane blink out of existence, at the most-watched moment in the game. See
	StealConfig.Handoff.MaxNudge for which overlaps get this and which still get recycled.

	A DELTA RATHER THAN AN ABSOLUTE CROSS, because the caller does not measure in this coordinate.
	`_clearLanding` works off `hit.Position`, and a shell's `Hit` box is offset from its Root by the
	bodywork's own centre (`TrafficService._buildShell`), so its cross and `rec.cross` need not agree.
	A displacement is the same number in both frames; a destination is not.

	WRITTEN STRAIGHT INTO `cross`, not into `targetCross`, and that is the point. `_steer` eases
	toward `targetCross` at `LaneChangeSpeed` — the better part of a second — and the overlap has to
	be gone before the next physics step. So this moves the car and re-places it inside the same
	no-physics-step window `_clearLanding` already runs in. `targetCross` follows so the car holds its
	new line rather than immediately steering back into the player, and `lateral` is zeroed so the
	shell is not left pointing across the road on the frame after (`_place` aims it down its own
	velocity).

	Refuses three cars. A PHYSICAL one's position belongs to the solver and `_place` would be fighting
	it; a FROZEN one is the steal target, which the ordering already handles and which must not move
	under the player's feet; and one whose destination is occupied, because swapping an overlap with
	the player for an overlap with another car fixes nothing. The caller recycles whatever it is
	handed back a `false` for. ]]
function TrafficController.shoveCar(self, rec, delta: number): boolean
	if not rec or rec.physical or rec.frozen then
		return false
	end
	local target = rec.cross + delta
	if not self:_laneFree(rec.along, target, SHOVE_GAP, rec) then
		return false
	end
	rec.cross = target
	rec.targetCross = target
	rec.lateral = 0

	--[[ Re-home it to whichever lane it is now nearest. Without this the shove is undone: `rec.lane`
		still names the lane it was heading for, and the next `_steer` decision sets `targetCross`
		back to `lanes[rec.lane]` and eases it straight into the space we just moved it out of —
		which would read as the car swerving INTO the player a second after the steal, a worse bug
		than the one this is fixing. Nearest rather than "the next one over" because the shove is a
		few studs, so the honest answer is usually the lane it was already crossing into. ]]
	local lanes = TrafficConfig.Lanes
	local nearest, best = rec.lane, math.huge
	for index, offset in lanes do
		local distance = math.abs(offset - target)
		if distance < best then
			nearest, best = index, distance
		end
	end
	rec.lane = nearest

	self:_place(rec)
	return true
end

--[[ PUBLIC (StealController) — the steal is complete (or was abandoned): put this shell back.

	Straight into the pool rather than destroyed, which is what every other car that leaves the road
	does. `_release` unfreezes it, un-does any hand-off to physics, gives its query volume back and
	nil-parents it, so the next spawn can hand it straight out again. ]]
function TrafficController.releaseCar(self, rec)
	local index = table.find(self._cars, rec)
	if not index then
		return
	end
	table.remove(self._cars, index)
	self:_release(rec)
end

-- HP is gone. Stop spawning and stop charging for clips, but leave the traffic driving: the
-- world carrying on around a car coasting to a stop is what makes the wreck beat land.
function TrafficController._onWrecked(self)
	self._wrecked = true
end

--[[ …and the wreck was paid out of (`ReviveService`): start topping the road up again, and get out
	of the way of the car being put back.

	TWO THINGS, AND THE SECOND IS THE ONE THAT BITES. The flag gates SPAWNING as well as clips, so
	leaving it set does not merely make the player un-clippable — it quietly empties the road ahead
	of them. A few seconds after a revive there is no traffic left to hit, to overtake, or to steal,
	and the rest of the run is a bare road.

	AND THE LANDING HAS TO BE CLEARED, because nothing else can clear it. `RaceService` sets the car
	down at a road coordinate it works out from the road's own axes — it has no idea what is standing
	there, and it cannot have one: traffic is client-local, so there is no traffic car on the server
	to test against. Get it wrong and the revive drops the player's car ON TOP of one, which is not a
	near miss — the car ends up balanced on a roof with its wheels spinning in the air, going nowhere,
	looking exactly like the revive is broken. (Photographed doing precisely that.)

	Kept up for a WINDOW rather than done once, because "once" has no correct moment: the remote can
	arrive before or after the teleport replicates, and a car that was clear when we looked can drive
	into the spot during the hold. The window covers the freeze, the deploy and the replication of
	both, and the whole thing happens behind the respawn screen — so nothing is ever seen to vanish. ]]
function TrafficController._onRevived(self)
	self._wrecked = false
	self._clearUntil = os.clock() + REVIVE_CLEAR_TIME
end

-- Recycle every car within `ReviveClearStuds` of a point on the road, in every lane. All lanes
-- rather than just the drive centre: the car is put back at rest and a neighbour close enough to
-- sideswipe it before it has moved is the same unfair ending as the one directly underneath.
function TrafficController._clearAround(self, along: number)
	local reach = TrafficConfig.ReviveClearStuds
	for i = #self._cars, 1, -1 do
		local rec = self._cars[i]
		if math.abs(rec.along - along) <= reach then
			table.remove(self._cars, i)
			self:_release(rec)
		end
	end
end

--[[ WHAT THE WEATHER IS DOING IN THE WORLD THIS RACE IS IN, cached on `self._event` as an event key
	or nil for clear.

	Cached rather than asked per spawn because the answer is a string parse of a Workspace attribute
	(`WeatherConfig.decode`) and a spawn happens every couple of seconds — but NOT read once at race
	start, because unlike the world, the ladder and the luck, this one genuinely does change under a
	moving car: a run is a minute or two and an event is a few minutes, so a storm starting or
	stopping mid-race is an ordinary thing rather than an edge case. That is why there is a signal
	connection below and not just a call in `_onRaceStart`.

	IT EXPIRES ON ITS OWN CLOCK TOO. The attribute is written when an event starts and when it ends,
	so an ending is a change and this does hear about it — but a server that dropped a write, or a
	client that joined mid-event, would otherwise hold a stale event forever. Comparing `endsAt`
	against server time costs nothing and closes that, which is why the deadline is on the wire at
	all (see `WeatherConfig.Attribute`).

	`_weatherWorld` and not `self._world`: this controller has never needed to remember which world
	it is in, and one field that exists for one feature is easier to follow than a general one. ]]
function TrafficController._refreshWeather(self)
	local state = WeatherConfig.decode(workspace:GetAttribute(WeatherConfig.Attribute))
	local entry = state[self._weatherWorld or 0]
	-- The tutorial's run drives on an ordinary road: no event traffic (`TutorialConfig.isTutorialRun`).
	if entry and not self._tutorialRun and workspace:GetServerTimeNow() < entry.endsAt then
		self._event, self._eventEndsAt = entry.event, entry.endsAt
	else
		self._event, self._eventEndsAt = nil, 0
	end
end

--[[ This player's luck, off the two upgrade ladders and the LUCKY ROADS pass. `_onRaceStart` calls
	it once and the pass's attribute signal calls it again if the pass is bought mid-run.

	IT ASKS `UpgradeConfig.luckFactor` FOR THE WHOLE ANSWER rather than adding the pass on here,
	which is that function's own instruction and matters more than it looks: `_pickTier` raises luck
	to a power, so a term added on this side of the call would land outside the exponent and be
	normalised straight back out. A pass applied to the final weights would do literally nothing. ]]
function TrafficController._refreshLuck(self)
	local player = Players.LocalPlayer
	if not player then
		self._luck = 1
		return
	end
	self._luck = UpgradeConfig.luckFactor(
		UpgradeConfig.decode(player:GetAttribute(UpgradeConfig.Attribute)),
		player:GetAttribute(LUCKY_ROADS_ATTRIBUTE)
	)
end

--- The event key to roll a spawn against, expiry checked. One comparison, which is why this is what
--- `_spawn` calls rather than `_refreshWeather` (a string decode and a table per spawn).
function TrafficController._liveEvent(self): string?
	if self._event and workspace:GetServerTimeNow() >= self._eventEndsAt then
		self._event, self._eventEndsAt = nil, 0
	end
	return self._event
end

--[[ HOW MUCH TRAFFIC THIS WEATHER WANTS: four multipliers on `TrafficConfig`'s own numbers, all of
	them 1 under every event but `RushHour`. `WeatherConfig.trafficFor` has the contract.

	ASKED FRESH RATHER THAN CACHED AT RACE START, because the whole point of the field is that it can
	change under a moving car: rush hour starting mid-run has to fill the road it is already on, and
	rush hour ENDING has to let it drain again. It is a table index off an already-cached key, which
	is cheap enough to do per spawn attempt and per priming pass.

	NOTHING WRITES TO WHAT THIS RETURNS — see that function's note; the clear-weather answer is a
	shared constant. ]]
function TrafficController._weatherTraffic(self)
	return WeatherConfig.trafficFor(self:_liveEvent())
end

--[[ The hard live-model cap for right now: the useful forward target plus a small allowance for
	cars recently passed but not yet culled. `_spawn` uses this bound, so forward refill can never
	grow the model count without limit. ]]
function TrafficController._maxCars(self): number
	return self:_targetCarsAhead() + math.max(0, TrafficConfig.TrailingAllowance)
end

-- Useful population target. Weather scales the road ahead; the small trailing allowance above is
-- deliberately not multiplied, because passed shells cost the same during rush hour or clear sky.
function TrafficController._targetCarsAhead(self): number
	return math.max(1, math.floor(TrafficConfig.MaxCars * self:_weatherTraffic().Cars))
end

-- Count only cars the player can still make a decision about. This is the distinction the old
-- total-population cap lacked: a car hundreds of studs behind is live for cleanup, not gameplay.
function TrafficController._carsAhead(self): number
	local count = 0
	for _, rec in self._cars do
		if rec.along >= self._playerAlong then
			count += 1
		end
	end
	return count
end

function TrafficController._onRaceStart(self, world: number?, bench: unknown)
	self:_teardown()

	--[[ THE ADMIN BENCH CAN CLOSE THE SPAWNER for the length of one run (`ObstacleConfig.Bench`). A
		bench exists so that one hazard can be driven into over and over, and a traffic car arriving
		three studs before it makes that a different test every time.

		The same flag the tutorial's director uses (`setSpawning`), so nothing else about the
		population changes and cars already out would keep driving. At `RaceStart` there are none, so
		what this actually produces is an empty road.

		Read off the bench rather than off a switch of its own because it IS part of the bench: it
		arrives with `RaceStart`, it lasts exactly as long as the run does, and the `_teardown` above
		has already put the flag back for the next one. Set before the guards below so it lands even
		on a race that ends up traffic-free for some other reason. ]]
	self._noSpawn = type(bench) == "table" and bench.traffic ~= true

	if not TrafficConfig.Enabled then
		return
	end
	if not (self._road and self._obstacles) then
		self.log:warn("RoadController/ObstacleController unavailable; this race runs traffic-free.")
		return
	end
	if #self._templates == 0 then
		self.log:warn("No traffic bodies were published; this race runs traffic-free.")
		return
	end

	--[[ Narrow the published roster to THIS world's ladder, once, here.

		The world arrives with `RaceStart` rather than being read off the road or the player, for the
		same reason RoadController's does: it is what the run was BUILT from, and the car on the road
		and the road under it have to have come from the same answer. Filtered by name against the
		config rather than by anything on the shell, because the shells are stripped visuals and the
		ladder is the config's business.

		An empty result is a config naming cars the place doesn't have. Warned about and then
		ignored — the roster falls back to everything published, so the race runs with the wrong
		cars instead of with none, which is much easier to notice and much less annoying to hit. ]]
	self._tiers = TrafficConfig.tiersFor(world)

	--[[ The weather this run is being driven in. `world` rather than the player attribute for exactly
		the reason the ladder above uses it: it is what the run was BUILT from, and the sky, the cars
		on the road and the road under them all have to have come from the same answer.

		The connection is made here and dropped in `_teardown` with everything else, so nothing is
		listening to the weather while nobody is racing. ]]
	local localPlayer = Players.LocalPlayer
	self._weatherWorld = WorldConfig.resolve(world)
	self._tutorialRun = TutorialConfig.isTutorialRun(Players.LocalPlayer:GetAttribute(TutorialConfig.StepAttribute))
	self:_refreshWeather()
	self._weatherConn = workspace:GetAttributeChangedSignal(WeatherConfig.Attribute):Connect(function()
		self:_refreshWeather()
	end)

	--[[ And this run's LUCK, off the player's own replicated attributes — see `_pickTier` for what it
		does to the roll and `UpgradeConfig.Luck` for what a level is worth.

		READ HERE AND NOT PER SPAWN, because `_pickTier` runs for every car that appears and this is a
		string decode and a table. Reading attributes rather than asking the server is the point of
		`UpgradeConfig.Attribute` existing — the values are already on the Player, and a round trip at
		race start would be one more thing for the first spawn to wait on.

		THE LADDERS CANNOT MOVE MID-RACE AND THE PASS CAN, which is the whole reason there is a
		connection here and not just a call. `Luck` and `MythicalLuck` are bought at a billboard
		standing on a forecourt and you are on a road; `LuckyRoads` is bought on the SHOP page, which
		opens over a race. A player who buys it mid-run and watches the road carry on unchanged has
		been sold nothing they can see. Re-reading costs one connection and is safe to do at any
		moment, because `_luck` is a value `_pickTier` reads fresh per car rather than something
		already applied to the cars on the road — no running state is scaled, so there is nothing to
		double.

		Missing attributes (profile still loading, upgrades switched off, pass never bought) decode to
		nothing and `luckFactor` answers 1, which is exactly the roll this had before luck existed. ]]
	self:_refreshLuck()
	self._luckConn = localPlayer
		and localPlayer:GetAttributeChangedSignal(LUCKY_ROADS_ATTRIBUTE):Connect(function()
			self:_refreshLuck()
		end)

	local wanted = TrafficConfig.bodiesFor(world)
	self._worldTemplates = {}
	for _, template in self._templates do
		if table.find(wanted, template.Name) then
			table.insert(self._worldTemplates, template)
		end
	end
	if #self._worldTemplates == 0 then
		self.log:warn(string.format(
			"None of world %s's %d cars are published (%s); this race runs on whatever else is.",
			tostring(world), #wanted, table.concat(wanted, ", ")
		))
		self._worldTemplates = self._templates
	end

	local folder = Instance.new("Folder")
	folder.Name = TrafficConfig.FolderName
	folder.Parent = workspace
	self._folder = folder
	self._clipParams.FilterDescendantsInstances = { folder }

	--[[ Solid or not is decided ONCE, here, and both halves of it read this one answer.

		They have to agree. The clip poll must query AS the player's car — the one group solid
		traffic collides with — because a poll left in "Default" comes back empty for every car on
		the road (see the header). So a race that started non-solid and then made its cars solid
		anyway would have cars that block you and charge you nothing, which reads exactly like the
		damage having broken. Asking each half separately is what would allow that. ]]
	self._solid = CarCollision.ensure()
	self._clipParams.CollisionGroup = if self._solid then TrafficConfig.Collision.PlayerGroup else "Default"

	-- The volume the clip poll is run against: the car's HitBox, reaching `ClipMargin` studs
	-- further out on every horizontal side. Built empty because `_checkClips` poses and sizes it
	-- from the live hull each time it runs. CanQuery stays FALSE, unlike the wall sensor's: a
	-- part only needs it to be FOUND by someone else's query, not to be the shape of its own, and
	-- an anchored query-visible box riding the car is exactly what the stock CarBones suspension
	-- rays (which run as "Default" and aren't ours to filter) would trip over.
	local sensor = Instance.new("Part")
	sensor.Name = "ClipSensor"
	sensor.Anchored = true
	sensor.Transparency = 1
	sensor.CastShadow = false
	sensor.CanCollide = false
	sensor.CanTouch = false
	sensor.CanQuery = false
	sensor.Parent = workspace
	self._clipSensor = sensor

	self._active = true
	--[[ The first batch of issued cars, asked for the moment the race goes live so it is in hand by
		the time the road is built and priming starts. Priming that runs first simply finds the queue
		empty and fills the road a beat later, as the answer lands (`_takeEncounter`). ]]
	if EncounterConfig.Enabled then
		self:_requestEncounters(nil)
	end
	self._primed = false
	self._spawnAt = 0
	self._filterAt = 0
	self._clearUntil = 0
	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_loop(dt)
	end)
end

--[[ Run down the shells a finished race left behind, a few a frame.

	SIMPLER THAN `RoadController`'S DRAIN AND DELIBERATELY SO. A road tile is ~1,000 instances and
	has to be sliced from the inside; a traffic shell is ~25 and is the natural unit, so this counts
	MODELS rather than instances and destroys each whole. Same shape otherwise: session-scoped
	connection (the work outlives the race that made it, so it cannot hang off `_conn`), started on
	demand, and it stops itself the moment the queue is empty.

	Everything in the queue is already out of the scene — the pooled shells were nil-parented by
	`_release` and the folder is unparented by `_teardown` before it queues it — so nothing here is
	visible and the pace is free. A race starting mid-drain is fine: `_onRaceStart` builds a new
	folder and a new pool, and this goes on quietly finishing the old ones. ]]
function TrafficController._startDrain(self)
	if self._drainConn or #self._drain == 0 then
		return
	end
	self._drainConn = RunService.Heartbeat:Connect(function()
		self:_stepDrain()
	end)
end

function TrafficController._stepDrain(self)
	local budget = math.max(1, TrafficConfig.DrainBudget)
	for _ = 1, budget do
		local instance = table.remove(self._drain)
		if not instance then
			if self._drainConn then
				self._drainConn:Disconnect()
				self._drainConn = nil
			end
			return
		end
		instance:Destroy()
	end
end

function TrafficController._teardown(self)
	self._active = false
	self._wrecked = false
	self._primed = false
	--- Issued cars belong to the run they were issued for; the server drops its ledger at the same
	--- moment (`EncounterService`, `RaceLeft`), so a leftover token here would name nothing.
	table.clear(self._encounters)
	table.clear(self._retired)
	self._encounterPendingUntil = 0
	self._rungPendingUntil = 0
	self._rungWanted = nil
	--- A booking the race never got round to paying off. Dropped with everything else rather than
	--- left standing: `_prime` sets it again for the next run, and a leftover count is a road that
	--- would start filling itself before that run had rolled its own weather.
	self._primeLeft = 0
	self._primeBand = nil
	table.clear(self._formationQueue)
	self._clearUntil = 0
	self._solid = false
	self._suspended = false
	self._stealLaneChangesLocked = false
	-- A hold that outlives its race must not leave the next one unable to spawn. `setFrozen` is
	-- refcounted by its caller, not here, so this is the unconditional way out — the same reason
	-- `TimeScale.reset` clears its holds rather than balancing them.
	self._frozen = false
	-- ...and the same for the tutorial's hand on the spawner: a staged run that ended without the
	-- director getting to let go must not leave the next race unable to populate itself.
	self._noSpawn = false
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	--[[ Stop listening to the weather, and forget what it was doing. Both halves matter: the
		connection would otherwise re-arm `_event` from the lobby for a race that is over, and the
		cached key would be handed to the FIRST SPAWN OF THE NEXT RACE — which could easily be in a
		different world, so the next run would open with a handful of cars mutated by somebody else's
		storm. `_onRaceStart` sets them both again before anything spawns. ]]
	if self._weatherConn then
		self._weatherConn:Disconnect()
		self._weatherConn = nil
	end
	--- Same reason as the weather connection: a live signal from a race that is over would refresh
	--- `_luck` for nobody, and `_onRaceStart` sets it again before the next race spawns anything.
	if self._luckConn then
		self._luckConn:Disconnect()
		self._luckConn = nil
	end
	self._event, self._eventEndsAt, self._weatherWorld = nil, 0, nil

	--[[ The pooled shells and the live folder, handed to `_stepDrain` rather than destroyed here.

		THE POOL IS THE BIG ONE AND IT IS NEVER TRIMMED DURING A RUN. `_release` parks every recycled
		shell under its body name and nothing empties it until this line, so by the end of a long
		race it holds close to one shell per body the tier ladder reached — up to 33 of them at ~25
		meshes each. Destroying that, plus the twelve cars still on the road, plus the folder, is
		~800 instances on the same frame every other controller is tearing down on. It is the same
		mistake `RoadController._onRaceEnd` used to make with the road, one order of magnitude down.

		Nil-parented already, in the pool's case, so nothing here is visible and the drain can take
		as long as it likes. The folder is unparented for the same reason the road's husk is: one
		cheap call takes the twelve live cars out of the scene now, and the destroy follows behind. ]]
	for _, pool in self._pool do
		for _, rec in pool do
			table.insert(self._drain, rec.model)
			table.insert(self._drain, rec.warning)
		end
	end
	table.clear(self._pool)
	table.clear(self._cars)
	table.clear(self._byPart)

	if self._folder then
		self._folder.Parent = nil
		table.insert(self._drain, self._folder)
		self._folder = nil
	end
	self:_startDrain()
	if self._clipSensor then
		self._clipSensor:Destroy()
		self._clipSensor = nil
	end
	self._clipParams.FilterDescendantsInstances = {}
	self._obstacleParams.FilterDescendantsInstances = {}
	self._avoidExtra = nil
	self._avoidFootprint = nil
	self._playerCar = nil
	self._hitBox = nil
	self._info = nil
end

TrafficController:withRemoteEvents({
	{
		RaceStart = function(_seed, world, _laneOffset, bench)
			TrafficController:_onRaceStart(world, bench)
		end,
		RaceWrecked = function()
			TrafficController:_onWrecked()
		end,
		RaceRevived = function()
			TrafficController:_onRevived()
		end,
		RaceEnd = function()
			TrafficController:_teardown()
		end,
		--- The server's answer to `EncounterRequest`: cars for this road (`EncounterConfig`).
		EncounterBatch = function(batch)
			TrafficController:_onEncounters(batch)
		end,
	},
	"TrafficHit",
	"EncounterRequest",
})

TrafficController:withLifecycle({
	init = function(self)
		self._cars = {} -- live records, in no particular order
		self._encounters = {} -- cars the server has issued and this road has not spawned yet (`_takeEncounter`)
		self._retired = {} -- tokens of cars that have left the road, sent with the next request (`_retire`)
		self._pool = {} -- [body name] = { idle records }
		self._byPart = {} -- [Hit part] = record, for the clip poll
		self._templates = {} -- published shells (every world's), resolved in start()
		self._worldTemplates = {} -- the subset this race's world can spawn, narrowed in _onRaceStart
		self._warningTemplate = nil -- ReplicatedStorage IndicateArrow, cached after its first record
		self._warnedMissingIndicator = false
		self._tiers = TrafficConfig.Tiers -- this race's ladder, likewise
		self._luck = 1 -- LUCK + MYTHICAL LUCK + the LuckyRoads pass; see _refreshLuck
		self._active = false
		self._wrecked = false
		self._primed = false
		self._suspended = false -- true while airborne (StealController); clips stop being charged
		self._stealLaneChangesLocked = false -- routine lane decisions pause during a steal flight
		self._frozen = false -- true while the world is held at a stop (RaceFreezeController)
		self._noSpawn = false -- true while the tutorial is dealing the road itself (TutorialDirector)
		self._solid = false -- traffic collides with our car this race; set in _onRaceStart
		self._avoidExtra = nil -- one non-obstacle thing to steer around; see `setAvoid`
		self._avoidFootprint = nil -- ...and where it is, when it says (`_avoidAhead`)
		self._nextId = 0
		--- The opening fill, booked by `_prime` and paid off a couple a frame by `_stepPrime`.
		self._primeLeft = 0
		self._primeBand = nil
		--- Shells a finished race left behind, destroyed a few a frame — see `_stepDrain`.
		--- Session-scoped, because its contents outlive by design the race that filled it.
		self._drain = {}
		self._drainConn = nil
		self._spawnAt = 0
		self._filterAt = 0
		self._playerAlong = 0
		self._clearUntil = 0 -- os.clock() until which a revive's landing spot is kept empty
		self._formationQueue = {} -- density-director slots waiting to be spawned
		self._rng = Random.new()

		-- Obstacle lookahead. Include over the tiles' Obstacles folders; their decorative parts
		-- are CanQuery=false, so this can only ever come back with hit volumes.
		local obstacleParams = OverlapParams.new()
		obstacleParams.FilterType = Enum.RaycastFilterType.Include
		obstacleParams.FilterDescendantsInstances = {}
		obstacleParams.RespectCanCollide = false -- obstacle volumes are deliberately non-colliding
		obstacleParams.MaxParts = 1 -- "is anything there", never "what and how many"
		self._obstacleParams = obstacleParams

		-- Clip poll. Include over the traffic folder; only each car's `Hit` answers queries.
		local clipParams = OverlapParams.new()
		clipParams.FilterType = Enum.RaycastFilterType.Include
		clipParams.FilterDescendantsInstances = {}
		clipParams.RespectCanCollide = false
		clipParams.MaxParts = 4 -- threading a gap can legitimately touch two cars at once
		self._clipParams = clipParams
	end,

	start = function(self)
		self._road = Shard.get("RoadController")
		self._obstacles = Shard.get("ObstacleController")
		self._drive = Shard.get("DriveController") -- per-car cruise reference for relative traffic pace
		--[[ Where a measured pass goes. This file finds the near miss and says nothing about what one
			is WORTH — the chain, the money, the toast and the report to the server all live in one
			controller (`NearMissController`) precisely because the streak has to be counted in exactly
			one place on this client, and this loop is the wrong shape to hold state that outlives a
			traffic record. ]]
		self._nearMiss = Shard.get("NearMissController")
		self._sounds = Shard.get("SoundController") -- the pass-by whoosh; optional

		-- Registered once for the session, like a remote handler — the road's rebase is a
		-- property of the world, not of any one race.
		if self._road then
			self._road:onWorldShift(function(shift)
				self:_onWorldShift(shift)
			end)
		end

		--[[ Resolve the published shells off the critical path: RaceStart arrives long after this,
			and blocking client boot on a folder the server may not have built would be worse than
			one warned-about traffic-free race.

			`ChildAdded` MATTERS NOW THAT THE ROSTER IS 33 BODIES. A folder replicates its children
			incrementally, so the frame it appears is not the frame it is complete — and a short
			`_templates` is not a small problem: `_pickBody` falls back to the WHOLE list when a tier's
			named bodies aren't published yet, so a Tier 1 roll would quietly hand out a supercar for
			the first stretch of a race. One body arriving late used to be invisible; thirty-two
			arriving late would not be. ]]
		task.spawn(function()
			local folder = ReplicatedStorage:WaitForChild(TrafficConfig.TemplateFolderName, 20)
			if not folder then
				self.log:warn("No traffic bodies were published; roads will run empty.")
				return
			end
			local function add(child: Instance)
				if child:IsA("Model") and not table.find(self._templates, child) then
					table.insert(self._templates, child)
				end
			end
			folder.ChildAdded:Connect(add)
			for _, child in folder:GetChildren() do
				add(child)
			end
		end)
	end,
})

-- HitchProbe (2026-10-06, temporary: Leaf's spike at the getaway truck; see `Modules/HitchProbe`).
TrafficController.ram = require(ReplicatedStorage.shared.Modules.HitchProbe).wrap("TrafficController.ram", TrafficController.ram)

return TrafficController
