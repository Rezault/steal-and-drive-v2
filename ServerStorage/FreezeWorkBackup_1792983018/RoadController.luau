--[[
	RoadController  (client)
	------------------------
	The road is client-sided: driving is solo, so each player builds and streams their OWN
	local copy of the road. These tiles are client-only instances (cloned from
	ReplicatedStorage.RoadSegmentTemplate) — they never replicate, so segment movement
	costs zero network. A network-owned car collides with client-local geometry (verified),
	so the server-spawned, driver-owned car drives on this local road just fine.

	Flow (driven by RaceService's remotes):
	  - RaceStart  → build the local road for the world the server sent, wait until this client
	                 can actually HOLD the car (see "THE ACK IS A PROMISE" below), ack RaceReady,
	                 then run the Heartbeat streaming loop against our own car (found via seat).
	  - RaceEnd    → stop and destroy the local road.

	=== THE ACK IS A PROMISE ==================================================================

	`RaceReady` is not "I have finished building"; it is "let go of the car, I have got it". The
	server is holding an anchored car over a deck THAT ONLY EXISTS ON THIS MACHINE, and the ack is
	the single thing that makes releasing it safe (`RaceService._abortEntry` has the measurement of
	what releasing it early costs: a clean fall through an empty world and a WRECKED the player
	never earned). So the ack has to be a promise this client can keep, and there are two things
	beyond "the tiles exist" that it takes to keep it:

	  1. WE HAVE THE CAR. Network ownership of an assembly this client has not received yet is
	     ownership of nothing: the server stops simulating the moment it hands over, and we cannot
	     start until the parts arrive, so the car is held by NOBODY for the length of that gap.
	     Measured at ~0.5s on a warm desktop Studio client — the model arrives via the seat, and
	     its PrimaryPart lands half a second later — and the whole point of this file's caution is
	     the device where "still loading" makes it much longer.

	  2. THERE IS SOMETHING SOLID UNDER IT. Cheap to ask (one ray) and it is the only question that
	     covers every reason the deck might not be there yet — art that has not finished arriving, a
	     world whose folder came up empty, a lane laid at the wrong storey. Ask it with
	     `RespectCanCollide`: the first version of this probe passed on a LANE LINE, which is a
	     `CanCollide = false` decal part sitting a stud above the deck it is painted on. A ray that
	     stops on scenery proves nothing about what will catch a car.

	If either never comes true we simply DO NOT ACK, and the server's own fail-safe ends the entry
	the safe way at `RaceConfig.EnterReadyTimeout`. A player put back in the lobby with a line
	explaining why has lost a press of Play; a player whose car is released into a world that cannot
	hold it is shown WRECKED for their loading time.

	=== WHICH ROAD ============================================================================

	A world is a folder of NUMBERED SEGMENTS in `ReplicatedStorage.WorldRoads`, and they are a
	PROGRESSION, not a shuffle: you drive segment 1 for `RaceConfig.SegmentHold` tiles, then the
	road becomes segment 2, then 3, and the world's last segment holds for the rest of the run. How
	far in you are is the tile's own `TileIndex`, so the road advances with the run the same way the
	traffic ladder does — see `SegmentHold` for why it does not advance ON the traffic ladder.

	THAT IS WHY RECYCLING CAN NO LONGER JUST MOVE A TILE. The ring is nine tiles deep and a hold is
	shorter than that, so the stretch of road a recycled tile is about to become usually wants a
	different segment than the tile currently is — and it gets replaced with a clone of that segment
	instead of moved. It happens two tiles behind the car, off screen, and stops entirely once a
	world has no segments left to reach.

	AND WHY REPLACING ONE CANNOT HAPPEN IN A SINGLE FRAME. Nine tiles deep with a hold of three means
	the rear tile is always exactly three segments stale, so the fast path above is not merely rare
	while a world still has segments left — it is unreachable, and EVERY recycle is a replacement
	until the last segment is reached. That is the first two to four minutes of a run, which is most
	of one, and a whole replacement on one frame measured 63-77 ms against a 7 ms median. So a
	replacement is built across the frames before it is wanted and the tile it displaces is destroyed
	across the frames after — see `RaceConfig.TileBuildBudget` for the numbers and the incremental
	builder below for how.

	IT ALL HAPPENS AT THE PUBLISHED RACE ORIGIN, never where the tiles are authored — two worlds are
	parked straight through the lobby. `DriveCenterOffset` is what survives that move (lane centre
	measured from the tile's own pivot); the authored `DriveCenterX` is an absolute and is only true
	while a tile has not been moved, which after this it always has been. RoadService publishes the
	origin so both sides agree on it without either measuring.

	...OFFSET BY OUR RACE'S LANE, which is the one thing that is not the same for every driver. Every
	client building at one origin is exactly what made two players share a stretch of road and crash
	into each other's replicated cars, so the server now stacks each live race on a storey of its own
	(`RaceConfig.Lanes`) and sends the offset with `RaceStart`. `_buildRoad` adds it to the origin and
	stops there: everything else here is derived from that one CFrame, so the whole race moves with
	it and nothing downstream of this file knows a lane exists. Slot 0 is the bare origin, so a solo
	run builds precisely the road it always did.

	THE WORLD ARRIVES WITH `RaceStart` rather than being read off the player, because it is a build
	argument: the server already picked a car and a spawn point from it, and a road built from a
	second, later read of the same attribute is a road the car might not be standing on. The lane is
	a build argument of exactly the same kind, and rides along for exactly the same reason.

	Streaming loop, entirely local:
	  - Recycle: as the car drives forward, the rearmost tile is moved to the front — or, when the
	             road wants a different segment there, swapped for one the builder has been
	             assembling in the background since the last recycle.
	  - Rebase:  when the car wanders past RebaseThresholdStuds from origin, shift the whole
	             local road + our (owned) car back toward 0 by whole SegmentLengths, in one
	             frame, velocity preserved — keeps coordinates precise and is seamless.
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local RaceConfig = require(ReplicatedStorage.shared.Configs.RaceConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local RoadController = Shard.new("RoadController")

local function axisVector(letter: string): Vector3
	letter = string.upper(letter or "Z")
	if letter == "X" then
		return Vector3.xAxis
	elseif letter == "Y" then
		return Vector3.yAxis
	end
	return Vector3.zAxis
end

--- The numbered tile Models in a world folder, in order.
local function tilesOf(folder: Instance): { Model }
	local tiles = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and tonumber(child.Name) then
			table.insert(tiles, child)
		end
	end
	table.sort(tiles, function(a, b)
		return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0)
	end)
	return tiles
end

function RoadController.along(self, position: Vector3): number
	return position:Dot(self._forwardWorld)
end

function RoadController._sortSegments(self)
	table.sort(self._segments, function(a, b)
		return self:along(a:GetPivot().Position) < self:along(b:GetPivot().Position)
	end)
end

--[[ The tiles this world's road is built out of, and the origin they are laid at.

	Falls back to the single published tile template — the shipping city road — for a world with no
	map, a map folder that never made it out of Workspace, or an empty one. That is a real case and
	not an error path: a ladder without a road yet is the normal state for a world the modeller has
	not delivered, and it should read as "you drove the default road" rather than as a race that
	fails to start. ]]
function RoadController._tileSource(self, world: number?): ({ Model }, CFrame?, string)
	local roads = ReplicatedStorage:WaitForChild(RaceConfig.WorldRoadsName, 10)
	local origin = roads and roads:GetAttribute("RaceOrigin")
	local map = WorldConfig.mapFor(world)
	local folder = map and roads and (self._roads[map] or roads:FindFirstChild(map))
	--[[ Not here yet. With `RaceConfig.WorldRoadsPerPlayer` that is a road still on its way rather
		than one that does not exist, so ask for it and wait (`_awaitRoad`), behind the entry's own
		loading screen. One that does not land in time is warned about there, and this run gets the
		default road, which is what a world with no map has always driven. ]]
	if map and roads and not folder and self:_serverHasRoad(map) then
		folder = self:_awaitRoad(world, map)
		if not folder then
			map = nil
		end
	end
	if folder then
		local tiles = tilesOf(folder)
		if #tiles > 0 then
			return tiles, origin, map
		end
		self.log:warn(string.format("World road '%s' has no numbered tiles; falling back to the default road.", map))
	elseif map then
		self.log:warn(string.format("No published world road called '%s'; falling back to the default road.", map))
	end

	local template = ReplicatedStorage:WaitForChild(RaceConfig.RoadTemplateName, 10)
	if not template then
		return {}, origin, "none"
	end
	-- No published origin (an older RoadService, or none at all) means the template still sits
	-- where it was authored, which is exactly where the road used to be built.
	return { template }, origin or template:GetPivot(), template.Name
end

--[[ Which of the world's segments a given stretch of road is.

	Clamped at both ends, and both ends mean something. Below: the two tiles BEHIND the spawn are
	index -2 and -1, and they are segment 1 — the road you would have driven in on. Above: once a
	world's last segment is reached it holds forever, because the run does not, and there is nothing
	after "the end of what this world looks like" to move on to. ]]
function RoadController._segmentFor(self, tileIndex: number): number
	local hold = math.max(1, RaceConfig.SegmentHold)
	return math.clamp(math.floor(tileIndex / hold) + 1, 1, #self._variants)
end

--[[ === MOVING A TILE IS THE HOT PATH ==========================================================

	A tile is 400-1300 anchored MeshParts and the road moves them constantly: one tile on every
	recycle (~1,170 studs) and all nine at once on a rebase. `Model:PivotTo` writes EVERY one of
	those parts, and in a live race on the City ring that measured 61 ms for the nine — four
	dropped frames, and the snap you can see when the world comes back to the origin.

	So each tile's art is welded into ONE anchored assembly around an invisible root part laid at
	the tile's pivot, and moving a tile is a write to that root: the engine carries the other
	thousand parts as a single rigid body. Same nine tiles, same race, same camera: 10 ms.

	MEASURE THIS IN A RACE, NOT ON A BENCH. Tiles parked off-screen move far more cheaply than
	tiles being drawn (32 ms vs 61 ms for the `PivotTo` arm), so a bench both understates the
	problem and flatters whatever you replace it with. Welding alone is not the fix either —
	`PivotTo` still walks part by part on a welded model. The root write is the fix.

	WHAT IT COSTS, so the trade stays visible: the welds ride the clone, and `_advanceRear` clones
	whenever the segment changes, which takes that branch from 21 ms to 29 ms every ~41 s. Against
	~50 ms off each rebase and ~5.6 ms off each of the ~14 recycles in the same window, it is worth
	it — but that 29 ms is now the biggest hitch in the loop, and pre-cloning the next segment
	across the frames before it is needed is the thing to do about it.

	Welded on the VARIANTS, once, so the clones `_makeTile` makes inherit it and no weld is ever
	built at runtime. That ordering is also the trap: a WeldConstraint captures its offset when
	both parts reach the workspace, so a clone must be PARENTED BEFORE IT IS PLACED. Place first
	and the root moves alone, the offsets bake against a road the art never left, and the tile
	arrives in pieces scattered across the map. ]]

local TILE_ROOT_NAME = "__RoadRoot"
-- Marks the children that were welded into the assembly, so `_moveTile` can tell them from
-- anything parented into the tile AFTERWARDS (an obstacle course) which it has to carry itself.
local TILE_WELDED_ATTR = "RoadWelded"

--[[ Weld a tile's art into one anchored assembly. Idempotent, and cheap to ask twice: a tile that
	already has a root has already been done, which is what makes calling this on every variant at
	the start of every race free after the first. ]]
local function weldTile(tile: Model): BasePart
	local existing = tile:FindFirstChild(TILE_ROOT_NAME)
	if existing and existing:IsA("BasePart") then
		return existing
	end

	local root = Instance.new("Part")
	root.Name = TILE_ROOT_NAME
	root.Size = Vector3.one
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false -- inert to every raycast the road, the suspension and the obstacles run
	root.CanTouch = false
	root.CastShadow = false
	root.Massless = true
	root.Anchored = true -- the one anchor; everything welded to it is static because of it
	-- AT the pivot, which is what lets `_moveTile` write the target pivot straight onto the root
	-- with no delta arithmetic — and what keeps the two in step for `GetPivot` afterwards.
	root.CFrame = tile:GetPivot()

	for _, child in tile:GetChildren() do
		child:SetAttribute(TILE_WELDED_ATTR, true)
	end
	root.Parent = tile

	for _, part in tile:GetDescendants() do
		if part:IsA("BasePart") and part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part -- travels with the part, so destroying the part cleans up the weld
			-- An anchored part is its own static body no matter what it is welded to, so the
			-- assembly only becomes one rigid body once the art lets go of its own anchors.
			part.Anchored = false
		end
	end
	return root
end

--[[ Put a tile at `pivot`. One write for the whole assembly — see the block above.

	`WorldPivot` is written by hand because moving a part does not move the model's pivot with it
	the way `PivotTo` would, and the pivot is the road's coordinate system: `_sortSegments`,
	`_recycle` and every obstacle course are measured from it. Setting it moves nothing, so the
	two stay exactly in step at no cost.

	Falls back to `PivotTo` for a tile that was never welded (art published without a pivot to
	build a root at, say). Slower, identical result — the road works either way. ]]
function RoadController._moveTile(self, tile: Model, pivot: CFrame)
	local root = tile:FindFirstChild(TILE_ROOT_NAME)
	if not (root and root:IsA("BasePart")) then
		tile:PivotTo(pivot)
		return
	end

	local delta = pivot * tile:GetPivot():Inverse()
	root.CFrame = pivot
	tile.WorldPivot = pivot

	--[[ Anything parented into the tile after it was welded is not in the assembly and does not
		ride the root: ObstacleController's course folder is the one that matters, and it is
		carried here rather than by a listener so that a recycle and a rebase move a tile and its
		obstacles as one indivisible thing, exactly as `PivotTo` used to. Those parts are anchored
		— each its own static body — so a per-part write is the correct one and cannot double-move
		anything. It is ~40 parts a tile against the thousand in the assembly. ]]
	local moved: { BasePart }, targets: { CFrame } = nil, nil
	for _, child in tile:GetChildren() do
		if child ~= root and not child:GetAttribute(TILE_WELDED_ATTR) then
			local parts = if child:IsA("BasePart") then { child } else child:GetDescendants()
			for _, part in parts do
				if part:IsA("BasePart") then
					moved = moved or {}
					targets = targets or {}
					table.insert(moved, part)
					table.insert(targets, delta * part.CFrame)
				end
			end
		end
	end
	if moved then
		workspace:BulkMoveTo(moved, targets, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

--- A fresh tile for `tileIndex`, laid at `pivot`, stamped with everything that keys off it.
function RoadController._makeTile(self, tileIndex: number, pivot: CFrame): Model
	local segment = self:_segmentFor(tileIndex)
	--- On demand rather than for every variant up front — see the note in `_buildRoad`. Idempotent
	--- and near-free once done, so asking on every tile costs nothing after the first of a segment.
	weldTile(self._variants[segment])
	local tile = self._variants[segment]:Clone()
	-- Which stretch of road this tile currently *is*. Tile 0 is the one the car spawns on, and the
	-- number only ever grows as tiles are recycled forward, so anything that decorates the road
	-- (obstacles) can key off it and re-derive itself when a tile is reused. See ObstacleController.
	tile:SetAttribute("TileIndex", tileIndex)
	-- Which segment it is DRAWN from, so `_recycle` can tell whether moving this tile forward would
	-- put the wrong stretch of the world in front of the player.
	tile:SetAttribute("Segment", segment)
	-- PARENTED BEFORE IT IS PLACED, and that order is load-bearing — see the block above `weldTile`.
	-- No frame passes between the two lines, so the tile is never seen where it was authored.
	tile.Parent = self._folder
	-- Identity-rotated tiles: local offset == world offset.
	self:_moveTile(tile, pivot)
	return tile
end

--[[ === BUILDING A TILE ACROSS FRAMES ==========================================================

	`_makeTile` above is the whole thing on one frame, and on the map that costs the most it is 64 ms
	of it. Everything below is the same work, sliced: the tile a recycle is going to want is built
	over the frames leading up to it, and the tile a recycle displaces is destroyed over the frames
	after. `RaceConfig.TileBuildBudget` is the size of a slice and carries the measurements.

	A PLAN IS A FLAT LIST OF UNITS, cached per segment, and replaying it in order reproduces the
	variant exactly — verified part by part against the source, 1,037 of them, to 0.001 studs:

	  root        the tile's anchored `__RoadRoot`, cloned FIRST and put in the workspace on its own.
	              Everything after it is unanchored art that binds to the root as it lands, so a root
	              that arrived late would be a tile falling through the world in pieces.
	  open/close  a container too big to clone whole: shallow-copied (class, name, attributes) and
	              made the parent for the units between them.
	  clone       a subtree small enough to take in one bite, cloned with `Instance:Clone`.

	PLACED BEFORE IT IS PARENTED — the inverse of the rule `_makeTile` obeys, for the same underlying
	reason. A WeldConstraint captures its offset the moment both its parts are in the workspace, and
	here the root is already there and already AT the target pivot, so a unit must arrive at its final
	world position or its offset bakes against the authored road and the tile assembles itself
	scattered across the map. `_makeTile` gets to parent first and place after precisely because
	nothing of it is in the workspace yet when it does.

	TWO KINDS OF SUBTREE ARE NEVER OPENED. Anything that is not a Model or a Folder, because a shallow
	copy of an arbitrary class is not something this can get right blind. And any subtree a legacy
	`Weld` reaches across: `Instance:Clone` re-points a joint at the copy only when BOTH its parts are
	inside what was cloned, so splitting such a group would leave half its joints pointing back at the
	variant in ReplicatedStorage. The road art has ~87 of them inside one `RoadSurface` model, all
	within one 116-instance group, which is why the worst frame here is ~2.9 ms and not the budget.
	A world whose joints reach across its top-level children cannot be sliced at all; `_planFor`
	detects that and hands the segment back to `_makeTile`, whole. ]]

--- Instance count of every node under `node`, memoised into `sizes`. One walk of the tile.
local function measureTree(node: Instance, sizes: { [Instance]: number }): number
	local total = 1
	for _, child in node:GetChildren() do
		total += measureTree(child, sizes)
	end
	sizes[node] = total
	return total
end

--[[ Mark the lowest subtree each legacy joint lives entirely inside, so the planner can refuse to
	split it. False if any joint has no such subtree short of the whole tile — either because it
	reaches outside the variant, or because its two ends sit in different top-level children — which
	is the signal that this variant cannot be built incrementally at all. ]]
local function markJointGroups(variant: Model, blocked: { [Instance]: boolean }): boolean
	for _, joint in variant:GetDescendants() do
		if not joint:IsA("JointInstance") then
			continue
		end
		local part0, part1 = joint.Part0, joint.Part1
		if not (part0 and part1) then
			continue -- a joint holding nothing cannot be broken by moving things around it
		end
		local above: { [Instance]: boolean } = {}
		local node: Instance? = part0
		while node and node ~= variant do
			above[node] = true
			node = node.Parent
		end
		if node ~= variant then
			return false -- Part0 is not ours; any slice of this leaves the joint dangling
		end
		node = part1
		while node and node ~= variant and not above[node] do
			node = node.Parent
		end
		if node == nil or node == variant then
			return false
		end
		blocked[node] = true
	end
	return true
end

--[[ The same split in the other direction: nodes to destroy, children before their container.

	No joint or class rule here — nothing is being rebuilt, so a container can always be opened, and
	anything at or below `budget` goes whole. ]]
local function planTeardown(node: Instance, sizes, budget: number, out: { any })
	local size = sizes[node] or 1
	if size > budget then
		for _, child in node:GetChildren() do
			planTeardown(child, sizes, budget, out)
		end
		table.insert(out, { node = node, size = 1 }) -- ...and the container, empty by now
		return
	end
	table.insert(out, { node = node, size = size })
end

--- Emit `child` as one unit, or open it and emit its children, so no unit exceeds `budget`.
local function emitUnit(child: Instance, sizes, blocked, budget: number, out: { any })
	local size = sizes[child] or 1
	if size <= budget or blocked[child] or not (child:IsA("Model") or child:IsA("Folder")) then
		table.insert(out, { kind = "clone", src = child, size = size })
		return
	end
	table.insert(out, { kind = "open", src = child, size = 1 })
	for _, grandchild in child:GetChildren() do
		emitUnit(grandchild, sizes, blocked, budget, out)
	end
	table.insert(out, { kind = "close", size = 1 })
end

--[[ Move a freshly cloned unit into the road frame and bind its welds to the tile being built.

	ONLY WELDS THAT HELD THE VARIANT'S ROOT are re-pointed. A `Clone` keeps a live reference to
	anything outside what it copied, which is exactly how `weldTile`'s constraints arrive still naming
	the variant — and exactly why a weld naming anything else must be left alone: that one is art the
	modeller joined, and `Clone` has already re-pointed it if both its ends came along.

	The constraint is a CHILD of the part it holds, so a bare part's own weld is reached by the same
	descendant walk as a container's and there is no second case for it. ]]
local function placeUnit(copy: Instance, delta: Vector3, root: BasePart, sourceRoot: BasePart)
	if copy:IsA("BasePart") then
		copy.CFrame += delta
	end
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CFrame += delta
		elseif descendant:IsA("WeldConstraint") and descendant.Part0 == sourceRoot then
			descendant.Part0 = root
		end
	end
end

--[[ The build plan for one of this world's segments. Cached: it is a function of art that cannot
	change inside a session, and the walk that produces it is the most expensive thing here.

	THE PRIMARYPART IS CARRIED BY PATH, NOT BY NAME. A road tile's PrimaryPart is the authored
	`OriginMarker`, and it is what `Model:GetPivot` answers from — so a tile that finished without one
	would answer from `WorldPivot` instead, and every `along()` reading taken off it would be measured
	against a different thing than the rest of the ring's. Finding it by name would work today and
	break the first time a modeller names a prop `OriginMarker`, so the plan remembers which unit it
	rides in and which child indices lead to it inside that unit — an ordering `Clone` preserves. ]]
function RoadController._planFor(self, segment: number)
	local cached = self._plans[segment]
	if cached ~= nil then
		return cached or nil
	end

	local variant = self._variants[segment]
	--- Same on-demand weld `_makeTile` does, and for the same reason: this is the other way a
	--- segment first gets used, and the plan below is written against the welded root.
	if variant then
		weldTile(variant)
	end
	local root = variant and variant:FindFirstChild(TILE_ROOT_NAME)
	local blocked: { [Instance]: boolean } = {}
	if not (root and root:IsA("BasePart")) or not markJointGroups(variant, blocked) then
		--[[ Remembered as `false` rather than left nil, so art this cannot slice is diagnosed once
			and then costs nothing on every recycle after. `_advanceRear` falls back to `_makeTile`,
			which is what the road did before any of this and still works. ]]
		self.log:warn(string.format(
			"Road segment %d cannot be built across frames (no welded root, or a joint reaching outside its own subtree); it will be cloned whole, which is a dropped frame per recycle.",
			segment))
		self._plans[segment] = false
		return nil
	end

	local budget = math.max(1, RaceConfig.TileBuildBudget)
	local sizes: { [Instance]: number } = {}
	measureTree(variant, sizes)

	local units = { { kind = "root", src = root, size = 1 } }
	for _, child in variant:GetChildren() do
		if child ~= root then
			emitUnit(child, sizes, blocked, budget, units)
		end
	end

	local primaryUnit, primaryPath = nil, nil
	local primary = variant.PrimaryPart
	if primary then
		local chain: { Instance } = {}
		local node: Instance? = primary
		while node and node ~= variant do
			table.insert(chain, 1, node)
			node = node.Parent
		end
		for index, unit in units do
			local at = if unit.kind == "clone" then table.find(chain, unit.src) else nil
			if at then
				local steps = {}
				for depth = at + 1, #chain do
					local step = chain[depth]
					table.insert(steps, table.find(step.Parent:GetChildren(), step))
				end
				primaryUnit, primaryPath = index, steps
				break
			end
		end
	end

	local plan = { units = units, primaryUnit = primaryUnit, primaryPath = primaryPath, root = root }
	self._plans[segment] = plan
	return plan
end

--[[ Start building the tile the next recycle will want, if it is going to want one.

	Called every frame and built to be cheap when there is nothing to do: two attribute reads and a
	compare. Called from `_loop` rather than from the end of `_advanceRear` on purpose — `_recycle`
	sorts the ring AFTER advancing it, so inside `_advanceRear` the array's first and last entries are
	not yet the rear and the front. ]]
function RoadController._beginPrefetch(self)
	if not (self._active and self._folder and self._segmentLength) then
		return
	end
	local rear, front = self._segments[1], self._segments[#self._segments]
	if not (rear and front) then
		return
	end

	local segment = self:_segmentFor(self._nextIndex)
	-- The next recycle moves the rear tile instead of replacing it: there is nothing to build, and
	-- anything half-built for a segment the road has moved past is now road nobody will drive.
	if rear:GetAttribute("Segment") == segment then
		self:_abandonPrefetch()
		return
	end
	local job = self._pending
	if job and job.segment == segment then
		return -- already building the right thing
	end
	self:_abandonPrefetch()

	local plan = self:_planFor(segment)
	if not plan then
		return
	end

	--[[ Built AT the place it is going to stand, because its parts have to arrive at their final
		world positions (see the block above). The prediction is exact in the ordinary case — this
		runs after a recycle and `_advanceRear` is the only thing that moves the front — and where it
		is not, adoption re-places it for the 0.3 ms a root write costs. ]]
	local pivot = front:GetPivot() * CFrame.new(self._forwardWorld * self._segmentLength)
	self._pending = {
		segment = segment,
		plan = plan,
		pivot = pivot,
		delta = pivot.Position - self._variants[segment]:GetPivot().Position,
		cursor = 1,
		ready = false,
	}
end

--- Give up on a part-built tile, at the same pace it was built at.
function RoadController._abandonPrefetch(self)
	local job = self._pending
	self._pending = nil
	if job and job.tile then
		self:_retire(job.tile)
	end
end

--- One frame's worth of the tile being built ahead.
function RoadController._stepPrefetch(self)
	local job = self._pending
	if not job or job.ready then
		return
	end
	self:_runTileJob(job, math.max(1, RaceConfig.TileBuildBudget))
end

--[[ One frame's worth of ONE tile's construction, replaying its plan's units in order. Sets
	`job.ready` when the tile is finished.

	SHARED BY THE PREFETCH ABOVE AND THE OPENING BUILD (`_stepBuild`), for the reason `_sliceTile`
	is shared by the two teardown queues: the ordering rules in here are correctness, not style.
	The root must land first and alone, units must be PLACED before they are parented so a
	WeldConstraint bakes its offset against the final world position, and the PrimaryPart must be
	assigned last. A second replay written to the same spec is a second replay free to drift from
	it, and the failure mode is a tile that assembles itself scattered across the map. ]]
function RoadController._runTileJob(self, job, budget: number)
	local units = job.plan.units
	local spent = 0

	while job.cursor <= #units and spent < budget do
		local unit = units[job.cursor]
		local at = job.cursor
		job.cursor += 1
		spent += unit.size

		if unit.kind == "root" then
			local variant = self._variants[job.segment]
			local tile = Instance.new("Model")
			tile.Name = variant.Name
			-- The tile inherits the variant's attributes exactly as a `Clone` would, and everything
			-- that measures the road (`SegmentLength`, `DriveCenterOffset`, `ForwardAxis`) is one.
			for key, value in variant:GetAttributes() do
				tile:SetAttribute(key, value)
			end
			local root = unit.src:Clone()
			root.CFrame = job.pivot
			root.Parent = tile
			tile.WorldPivot = job.pivot
			--[[ Into the workspace holding nothing but its anchored root. The art that follows binds
				to it as it lands, and the tile stands one segment beyond the front one — 8,000 studs
				of fog ahead of the car, on the spot it is going to occupy anyway. ]]
			tile.Parent = self._folder
			job.tile, job.root, job.stack = tile, root, { tile }
		elseif unit.kind == "open" then
			local container = Instance.new(unit.src.ClassName)
			container.Name = unit.src.Name
			for key, value in unit.src:GetAttributes() do
				container:SetAttribute(key, value)
			end
			container.Parent = job.stack[#job.stack]
			table.insert(job.stack, container)
		elseif unit.kind == "close" then
			table.remove(job.stack)
		else
			local copy = unit.src:Clone()
			placeUnit(copy, job.delta, job.root, job.plan.root)
			if at == job.plan.primaryUnit then
				local node: Instance = copy
				for _, step in job.plan.primaryPath do
					node = node:GetChildren()[step]
				end
				job.primary = node
			end
			copy.Parent = job.stack[#job.stack]
		end
	end

	if job.cursor > #units then
		job.ready = true
		-- Last, and only now: until it is set, `GetPivot` answers from the `WorldPivot` written with
		-- the root, which is the same CFrame. Nothing moves when it lands.
		if job.primary and job.primary:IsA("BasePart") then
			job.tile.PrimaryPart = job.primary
		end
	end
end

--[[ === LAYING THE OPENING ROAD ACROSS FRAMES ==================================================

	The race-start twin of the prefetch above, and it exists for the same measurement. `_makeTile` is
	~64 ms on the heaviest world, and the opening road is `DesiredSegmentCount` of them — so building
	the ring in a loop was ~9 tiles of clone on the single frame `RaceStart` arrives, on top of
	whatever the variant welds cost. It is the recycle spike again, at the one moment nothing was
	spreading it.

	ONLY TILE 0 IS BUILT WHOLE, and it has to be: the server is holding the car anchored until this
	client acks `RaceReady`, and the ack is gated on there being collidable ground under the car
	(`_hasGroundUnder`). Tile 0 is that ground. One 64 ms frame is the floor on what entry can cost
	and it lands under a fade; the other eight tiles are road the player cannot reach yet.

	THE ACK MACHINERY ALREADY TOLERATES THIS. `_onRaceStart` polls for ground every 0.05s up to
	`EnterReadyTimeout - 0.5`, so a road that finishes arriving over the next couple of seconds is a
	case it was already written for — nothing there needed changing.

	AHEAD BEFORE BEHIND, because the player is pointed forwards and `SegmentsBehind` is scenery in
	the mirror. Variant welds are queued last, after every tile, so the road is complete before the
	pump spends a frame pre-warming a segment the run has not reached. ]]
function RoadController._startBuild(self)
	if self._buildConn then
		return
	end
	self._buildConn = RunService.Heartbeat:Connect(function()
		self:_stepBuild()
	end)
end

--- Finished tile joins the ring. Sorted rather than appended: tiles land in queue order, which is
--- ahead-then-behind, and every reader of `_segments` takes rear-to-front ordering as given.
function RoadController._adoptBuilt(self, tile: Model)
	table.insert(self._segments, tile)
	self:_sortSegments()
end

function RoadController._stepBuild(self)
	local job = self._buildJob
	if not job then
		local entry = table.remove(self._buildQueue, 1)
		if not entry then
			--- Ring complete: stop costing a connection. `_loop` starts recycling on the next frame.
			if self._buildConn then
				self._buildConn:Disconnect()
				self._buildConn = nil
			end
			return
		end
		--- A variant pre-warm, one per frame: ~20 ms of welding taken off whichever recycle would
		--- otherwise have been the first to reach this segment.
		if entry.weld then
			weldTile(entry.weld)
			return
		end
		local segment = self:_segmentFor(entry.index)
		local plan = self:_planFor(segment)
		if not plan then
			--- Art this cannot slice, diagnosed and remembered by `_planFor`. Whole, exactly as the
			--- opening build always did it — one dropped frame beats no road.
			self:_adoptBuilt(self:_makeTile(entry.index, entry.pivot))
			return
		end
		self._buildJob = {
			index = entry.index,
			segment = segment,
			plan = plan,
			pivot = entry.pivot,
			delta = entry.pivot.Position - self._variants[segment]:GetPivot().Position,
			cursor = 1,
			ready = false,
		}
		return
	end

	self:_runTileJob(job, math.max(1, RaceConfig.TileBuildBudget))
	if job.ready then
		--- The attributes `_makeTile` would have set. Everything that decorates the road keys off
		--- them, so they land with the tile rather than a frame later.
		job.tile:SetAttribute("TileIndex", job.index)
		job.tile:SetAttribute("Segment", job.segment)
		self:_adoptBuilt(job.tile)
		self._buildJob = nil
	end
end

--- Drop the opening build, wherever it got to. The part-built tile is parented in the road folder
--- and so leaves with it; this only clears the bookkeeping that points at it.
function RoadController._cancelBuild(self)
	self._buildJob = nil
	table.clear(self._buildQueue)
	if self._buildConn then
		self._buildConn:Disconnect()
		self._buildConn = nil
	end
end

--[[ Hand a tile that has left the road to the teardown queue.

	NOT `Destroy`, and not a deferred `Destroy` either. Destroying a tile is ~20 ms of the ~64 ms that
	used to land on a recycle frame, and deferring it bought nothing: `_loop` runs inside a deferred
	Heartbeat handler, and `task.defer` from there resumes at the end of the SAME resumption cycle,
	not on the next frame. The MicroProfiler trace this was diagnosed from shows the clone and the
	destroy inside one `deferredThreads` block, which is what that looks like from the outside. ]]
function RoadController._retire(self, tile: Model)
	table.insert(self._graveyard, { tile = tile })
end

--[[ One frame's worth of ONE tile's teardown. Answers true when the tile is gone and its job is
	finished with.

	SHARED BY BOTH TEARDOWN QUEUES — the in-race graveyard below and the end-of-race drain
	(`_stepDrain`) — deliberately, and not merely to save the lines. The two run at different
	moments against tiles in different states, and a second planner written to the same spec is a
	second planner free to drift from it: the `TILE_ROOT_NAME` skip, the children-before-container
	ordering and the "queue on a frame of its own" beat are all correctness, not style, and a
	divergence in any of them shows up as a dangling weld or a double destroy rather than as a
	visible bug. One planner, two callers. ]]
function RoadController._sliceTile(self, job, budget: number): boolean
	local tile = job.tile
	if not tile.Parent then
		return true -- a race ended under us and took the folder with it
	end

	--[[ Planned on a frame of its own, and planned off the TILE rather than off the variant it was
		cloned from: by the time a tile is retired it may be carrying an obstacle course the variant
		never had. Children are queued before the container that holds them, so a container is always
		empty by the time its own turn comes — and anything parented in after the plan was made still
		dies with it, in one bite, because it is a course-sized thing and not a tile-sized one. ]]
	if not job.queue then
		local sizes: { [Instance]: number } = {}
		measureTree(tile, sizes)
		local queue = {}
		for _, child in tile:GetChildren() do
			if child.Name ~= TILE_ROOT_NAME then
				planTeardown(child, sizes, budget, queue)
			end
		end
		job.queue, job.cursor = queue, 1
		return false
	end

	local spent = 0
	while job.cursor <= #job.queue and spent < budget do
		local unit = job.queue[job.cursor]
		job.cursor += 1
		if unit.node.Parent then
			spent += unit.size
			unit.node:Destroy()
		end
	end
	if job.cursor > #job.queue then
		tile:Destroy() -- the root, and the shell it all hung off
		return true
	end
	return false
end

--- One frame's worth of the oldest tile waiting to be destroyed.
function RoadController._stepGraveyard(self)
	local job = self._graveyard[1]
	if not job then
		return
	end
	if self:_sliceTile(job, math.max(1, RaceConfig.TileBuildBudget)) then
		table.remove(self._graveyard, 1)
	end
end

--[[ The end-of-race drain: the graveyard's twin, for the road a finished race left behind.

	IT IS A SEPARATE CONNECTION FROM `_conn` ON PURPOSE, and that is the whole point of it rather
	than an implementation detail. `_conn` is the race's loop and dies with the race; this work is
	*produced* by the race ending, so a pump hung off `_conn` would be disconnected on the exact
	frame it acquired its queue and the tiles would leak. It is owned by the session, started on
	demand, and it stops itself the moment the queue is empty — so a client sitting in the lobby
	between runs is not paying for a connection with nothing to do.

	A SECOND RACE STARTING MID-DRAIN IS FINE, and it needs exactly one interlock: `_onRaceStart`
	calls `_finishEvict`, because until the eviction below has run the husk is still IN the scene and
	a new race would build this run's road straight through last run's. Past that point nothing in it
	is in `_segments` and `_onWorldShift` (which walks `_graveyard`, not this) cannot reach it, so a
	new race builds into a brand new folder and the drain goes on quietly finishing the old one
	underneath it. If a run somehow ends again before the previous drain finished, its jobs simply
	queue up behind, because `_startDrain` is idempotent. ]]
function RoadController._startDrain(self)
	if self._drainConn then
		return
	end
	self._drainConn = RunService.Heartbeat:Connect(function()
		self:_stepDrain()
	end)
end

function RoadController._stepDrain(self)
	--[[ THE ROAD LEAVES THE SCENE BEFORE ANY OF IT IS DESTROYED, and it gets the frame to itself.
		Eviction is the half a player can see (see `_startEvict`) and destroying is the half nobody
		can, so a frame spends itself on one or the other rather than paying for both at once. ]]
	if self._evict then
		self:_stepEvict()
		return
	end

	local job = self._drain[1]
	if not job then
		--- Nothing left to run down: stop costing a connection until the next race ends.
		if self._drainConn then
			self._drainConn:Disconnect()
			self._drainConn = nil
		end
		return
	end

	--[[ A shell marker, queued behind every tile by `_onRaceEnd`. Reaching one means every tile
		ahead of it has already gone, so this is an empty Folder and `Destroy` on it is one call: no
		budget needed and nothing to slice. ]]
	if job.shell then
		job.shell:Destroy()
		table.remove(self._drain, 1)
		return
	end

	if self:_sliceTile(job, math.max(1, RaceConfig.TileBuildBudget)) then
		table.remove(self._drain, 1)
	end
end

--[[ === THE EVICTION: the finished road leaving the SCENE, one tile per frame =================

	`husk.Parent = nil` was one call, and that one call was ~150 ms of one frame: a tile is 1,800 to
	2,600 instances, taking one out of the render and physics scene costs ~7 us apiece, and the ring
	is `DesiredSegmentCount` deep. It landed half a second into the results screen, measured at
	+0.51 s against a `BEAT_START` of 0.35, which is the exact frame the wreck drops into its box and
	the ladder bar wipes open. The one hitch left on that screen once the lobby stopped re-streaming
	into it, and the one place on it that could least afford one.

	So the ring leaves a tile at a time instead: ~12 to 20 ms a frame for about ten frames, and the
	road is still out of the scene inside a sixth of a second. Nothing watches it go, because the
	player is behind a black overlay being teleported home, but the frames it is spread over are the
	frames the beat is playing on.

	A TILE IS THE QUANTUM AND NOTHING SMALLER, because a job in `_drain` is keyed to its tile and
	`_sliceTile` plans off that tile's own children: moving a tile's insides out from under a
	half-torn job would leave its cursor walking a tree that had changed shape. Ten frames of 15 ms
	is already a frame cost nobody can see.

	THE TILES MOVE TO AN UNPARENTED HOLDER RATHER THAN TO NIL, and that is `_sliceTile`'s first line
	rather than tidiness: it reads a parentless tile as one a race teardown has already taken and
	answers "done", so a tile evicted to nil would be skipped by the drain and leaked rather than
	destroyed. Both shells are queued behind the tiles and go when they are empty. ]]
function RoadController._startEvict(self, husk: Folder, tiles: { Model })
	--- Whatever the last race left standing goes now, in one call, rather than being interleaved
	--- with this one's. Two evictions at once is two shells' worth of bookkeeping for no gain.
	self:_finishEvict()

	local holder = Instance.new("Folder")
	holder.Name = husk.Name .. "Leaving"
	self._evict = { husk = husk, holder = holder, tiles = tiles, cursor = 1 }
	table.insert(self._drain, { shell = husk })
	table.insert(self._drain, { shell = holder })
	self:_startDrain()
end

--- One frame of it: the next tile out of the scene, and the shell itself once they have all gone.
function RoadController._stepEvict(self)
	local evict = self._evict
	local tile = evict.tiles[evict.cursor]
	evict.cursor += 1
	if tile then
		--- Guarded because a tile can have gone on its own: `_retire` hands half-torn tiles over to
		--- the drain with their cursors intact, and writing `Parent` on a destroyed one throws.
		if tile.Parent then
			tile.Parent = evict.holder
		end
		return
	end

	--- Every tile has left, so the husk is an empty Folder and taking it off the scene is one cheap
	--- call. Its own `Destroy` waits for the shell marker, behind the tiles it used to hold.
	evict.husk.Parent = nil
	self._evict = nil
end

--[[ Take whatever is left of a finished road out of the scene NOW, in one call.

	This is the old one-frame cost, paid on purpose and in the one place it is free: `_onRaceStart`,
	behind the entry's own loading screen, where a dropped frame is already expected and covered. The
	alternative is building this run's road through the ten tiles of last run's that have not been
	evicted yet, which is a solid ring of collidable geometry in exactly the wrong place.

	One unparent covers every tile still standing, because the ones that have not moved yet are all
	still children of the husk. ]]
function RoadController._finishEvict(self)
	local evict = self._evict
	if not evict then
		return
	end
	self._evict = nil
	evict.husk.Parent = nil
end

--[[ Clone the world's tiles into a client-only Workspace folder, tiled along from the race origin.

	`laneOffset` shifts that origin to the storey the server put our car on (`RaceConfig.Lanes`) —
	the one thing about a race that is not the same for every driver. Applied to the origin and
	nowhere else on purpose: the deck height, the drive centre, every tile pivot and therefore every
	obstacle, every traffic car and the camera are all derived from it below, so one addition here
	moves the entire race and nothing downstream has to know a lane exists. ]]
function RoadController._buildRoad(self, world: number?, laneOffset: Vector3?, token: number?): boolean
	local variants, origin, map = self:_tileSource(world)
	--- `_tileSource` can wait for a road to arrive, and the race can end while it does.
	if token and token ~= self._raceToken then
		return false
	end
	local first = variants[1]
	if not (first and origin) then
		self.log:warn("No road art published; cannot build local road.")
		return false
	end
	origin += laneOffset or Vector3.zero
	self._world = world
	self._map = map
	self._variants = variants
	self._plans = {} -- keyed by segment, and a segment means a different tile in a different world
	self._origin = origin

	self._segmentLength = first:GetAttribute("SegmentLength")
	if type(self._segmentLength) ~= "number" then
		local _, size = first:GetBoundingBox()
		self._segmentLength = size.Z
	end
	self._forwardWorld = axisVector(tostring(first:GetAttribute("ForwardAxis") or "Z"))
	-- Cross axis chosen so that cross:Cross(up) == forward. Note that makes +cross the
	-- road's LEFT when looking down the drive direction, not its right: a Roblox CFrame
	-- has right:Cross(up) == -look. Obstacle lanes ride on this axis, and they're
	-- symmetric about the centre, so the direction only decides which way a course
	-- reads — but anything that cares about left vs. right must not trust the name.
	self._crossWorld = Vector3.yAxis:Cross(self._forwardWorld)

	--[[ Lane centre, measured FROM THE PIVOT and then re-anchored to the origin the road is
		actually built at. `DriveCenterX` is the same quantity as an absolute, and is a fallback
		only for a tile that predates the offset attribute (the authored default-road tile is one);
		trusting it after the move would put lane centre wherever the artist happened to park the
		world, which for two of them is inside the lobby. ]]
	local offset = first:GetAttribute("DriveCenterOffset")
	if type(offset) ~= "number" then
		local driveCenterX = first:GetAttribute("DriveCenterX")
		offset = if type(driveCenterX) == "number"
			then driveCenterX - first:GetPivot().Position:Dot(self._crossWorld)
			else 0
	end
	self._driveCenter = origin.Position:Dot(self._crossWorld) + offset

	-- NOMINAL width of the drivable corridor. Part of the road contract, and the one attribute
	-- with no sane fallback — a tile's bounding box takes in buildings and scenery well outside
	-- the road — so it's published as nil rather than guessed, and callers opt out.
	--
	-- "Nominal" is load-bearing: it measures to the outer rail line, NOT to the surfaces the car
	-- actually stops against, which differ per side (see the ObstacleConfig.Wall header). Use it
	-- for generous tolerances only — never to decide whether the car has reached an edge.
	local driveWidth = first:GetAttribute("DriveWidth")
	self._driveWidth = if type(driveWidth) == "number" then driveWidth else nil

	-- Y of the deck surface. Constant for a whole race and the same in every world: a normalised
	-- tile's pivot sits ON its deck, every tile is laid at the origin, and both recycling and
	-- rebasing only ever translate ALONG the forward axis — so nothing that rides the road ever
	-- has to re-measure its height. Same expression RoadService uses for the car spawn, so the
	-- two agree by construction.
	self._deckY = origin.Position.Y

	--[[ Weld the VARIANTS, not the tiles — every clone below and every clone `_advanceRear` makes
		later inherits it, so no weld is ever built during a race. ~20 ms per variant, paid once for
		the whole session: the variants live in ReplicatedStorage and outlive the race, so a second
		run through the same world skips it entirely.

		NO LONGER DONE FOR EVERY VARIANT HERE. ~20 ms each is fine as a one-off and ruinous as a set:
		City has six segments, so the old loop was up to 120 ms of welding on the RaceStart frame,
		before a single tile had been cloned. `_makeTile` and `_planFor` now weld the variant they
		are about to use — both are idempotent calls into the same `weldTile` — and `_buildRoad`
		queues the segments nothing has reached yet as pre-warm jobs behind the tiles, so the cost
		is spread instead of removed. A second run through the same world still skips all of it. ]]

	local folder = Instance.new("Folder")
	folder.Name = RaceConfig.LocalRoadFolderName
	folder.Parent = workspace
	self._folder = folder

	self._segments = {}
	self:_cancelBuild()
	local behind = RaceConfig.SegmentsBehind
	local ahead = math.max(1, RaceConfig.DesiredSegmentCount - behind - 1)
	local function pivotFor(i: number): CFrame
		return origin * CFrame.new(self._forwardWorld * (self._segmentLength * i))
	end

	--[[ Tile 0 whole and now: it is the ground the car spawns on and the ack is gated on it being
		there. Everything else is queued — see the `_startBuild` header for why that is safe and why
		the order is ahead-first. ]]
	table.insert(self._segments, self:_makeTile(0, pivotFor(0)))
	for i = 1, ahead do
		table.insert(self._buildQueue, { index = i, pivot = pivotFor(i) })
	end
	for i = -1, -behind, -1 do
		table.insert(self._buildQueue, { index = i, pivot = pivotFor(i) })
	end
	--- Behind every tile: a segment the run has not reached costs nothing until it does.
	for _, variant in variants do
		if not variant:FindFirstChild(TILE_ROOT_NAME) then
			table.insert(self._buildQueue, { weld = variant })
		end
	end

	self._nextIndex = ahead + 1
	self:_startBuild()
	return true
end

-- === Road frame accessors (for anything that decorates the local road) =======

--[[ Is the local road finished, rather than merely started?

	THE ACK IS NOT THIS QUESTION, and the difference is the whole reason this exists. `RaceReady`
	means "there is ground under the car and the server may let go" — one tile's worth, which is
	deliberately all it needs to be (see `_startBuild`). The ring behind and ahead of that tile is
	still being laid for a couple of seconds afterwards.

	That was invisible while `_buildRoad` cloned all nine tiles in one frame: the road existed before
	the ack could possibly happen. Now that it is spread, anything that treats the ack as "the world
	is up" drops its cover early and shows the player the road assembling — which is exactly what
	`RaceUIController`'s loading screen is for, so it asks this instead.

	False before a race and after one, because a road that is not being built is not a built road:
	callers want "ready to be looked at", and an empty world is not that. ]]
function RoadController.isWorldReady(self): boolean
	return self._active and self._folder ~= nil and self._buildJob == nil and #self._buildQueue == 0
end

function RoadController.getSegments(self): { Model }
	return self._segments
end

function RoadController.getCar(self): Model?
	return self._car
end

-- nil until the local road has been built.
function RoadController.getRoadInfo(self)
	if not self._segmentLength then
		return nil
	end
	return {
		segmentLength = self._segmentLength,
		forward = self._forwardWorld,
		cross = self._crossWorld,
		driveCenter = self._driveCenter,
		driveWidth = self._driveWidth, -- nil if the tile doesn't declare one
		deckY = self._deckY,
		-- Which world this road IS. Anything that has to match the road's cars to the road's look
		-- (traffic) takes it from the RaceStart it was given rather than from here; this is for
		-- anything that only wants to know after the fact.
		world = self._world,
		map = self._map,
	}
end

--[[ Be told when the world gets rebased. Returns a disconnect function.

	Obstacles don't need this — they live inside their road tile, so `Model:PivotTo` carries
	them for free. Anything that keeps client-local objects in the road frame WITHOUT living
	inside a tile does need it, because a rebase moves the road out from under it. Traffic is
	the first such thing: a traffic car drives off the tile it spawned on, so parenting it to
	one would hand it to that tile's next recycle (a 9-tile teleport). It tracks its own
	along-coordinate instead and shifts that here.

	Listeners are called inside the rebase frame, after everything else has moved, so they must
	not yield. One that throws is warned about and skipped rather than being allowed to leave
	the road half-shifted. ]]
function RoadController.onWorldShift(self, fn: (Vector3) -> ()): () -> ()
	self._shiftListeners[fn] = true
	return function()
		self._shiftListeners[fn] = nil
	end
end

-- Find our own car via the seat we're sitting in (StreamingEnabled-safe — no remote arg).
function RoadController._findCar(self): Model?
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if not seat then
		return nil
	end
	local model = seat:FindFirstAncestorOfClass("Model")
	while model and model.Parent and model.Parent:IsA("Model") do
		model = model.Parent
	end
	return model
end

--[[ Put the rearmost tile at the front, as the next stretch of road.

	MOVED IF IT CAN BE, REPLACED IF IT CANNOT. Moving is much cheaper than instantiating and was the
	only thing this did while every tile in a race was the same art. Now that a world's segments are
	a progression, the stretch this tile is about to become usually belongs to a LATER segment than
	the one it was built as — nine indices further on, and a hold is shorter than nine — so keeping
	the geometry would mean the road never advanced. When that happens the tile is replaced by a
	clone of the right segment and the old one destroyed.

	Both paths end with the same `TileIndex` on the tile at the front, which is all anything
	downstream keys off: obstacles reconcile per frame against the tile MODEL, so a replaced tile is
	simply one they have not built for yet and the one that left is forgotten.

	NEITHER PATH INSTANTIATES ANYTHING, in the ordinary case. Replacing takes the tile `_beginPrefetch`
	has been assembling in the background since the last recycle and the tile it displaces goes to the
	teardown queue, so both paths cost one root write — 0.3 ms — and the two expensive halves are paid
	a slice at a time on frames either side. ]]
function RoadController._advanceRear(self)
	local rear = self._segments[1]
	local front = self._segments[#self._segments]
	local pivot = front:GetPivot() * CFrame.new(self._forwardWorld * self._segmentLength)
	local index = self._nextIndex
	self._nextIndex += 1
	local segment = self:_segmentFor(index)

	if rear:GetAttribute("Segment") == segment then
		self:_moveTile(rear, pivot)
		-- It's a different stretch of road now. Anything keyed to TileIndex (obstacles)
		-- notices the change and rebuilds itself for the new stretch.
		rear:SetAttribute("TileIndex", index)
		return
	end

	local job = self._pending
	if job and job.ready and job.segment == segment then
		self._pending = nil
		local tile = job.tile
		tile:SetAttribute("TileIndex", index)
		tile:SetAttribute("Segment", segment)
		-- Where the build predicted it, in all but a rebase — and a root write either way.
		self:_moveTile(tile, pivot)
		self._segments[1] = tile
	else
		--[[ The build did not get there in time, so the whole tile at once, exactly as this always
			did. Reachable and not an error: the first recycle of a race has no lead-in worth the
			name, and a car quick enough to cross a segment in fewer frames than the plan needs
			outruns the builder by arithmetic. Counted rather than warned per occurrence, because
			the interesting number is how many there were, not that there was one. ]]
		self._builtInline += 1
		self._segments[1] = self:_makeTile(index, pivot)
	end
	self:_retire(rear)
end

-- Recycle rear tiles to the front until only SegmentsBehind remain behind the car.
function RoadController._recycle(self, leadAlong: number)
	local segLen = self._segmentLength
	local behindWanted = RaceConfig.SegmentsBehind
	for _ = 1, #self._segments do
		local behind = 0
		for _, seg in self._segments do
			if self:along(seg:GetPivot().Position) + segLen < leadAlong then
				behind += 1
			end
		end
		if behind <= behindWanted then
			break
		end
		self:_advanceRear()
		self:_sortSegments()
	end
end

-- Snap the whole local world + our owned car back toward origin when it drifts too far.
function RoadController._maybeRebase(self, leadAlong: number)
	if math.abs(leadAlong) <= RaceConfig.RebaseThresholdStuds then
		return
	end
	local segLen = self._segmentLength
	local shiftAlong = -math.floor(leadAlong / segLen) * segLen
	if shiftAlong == 0 then
		return
	end
	self:_shiftWorld(self._forwardWorld * shiftAlong)
end

--[[ Translate the local road + the car assembly + the seated rider by `shift`, in one
	frame. We own the car, so writing its CFrame is authoritative (the server won't fight
	it) — BUT writing CFrames on an unanchored, physics-simulated assembly makes the engine
	synthesise a huge reconciliation velocity (Δpos/Δt), which flings the car and compounds
	into a float-overflow runaway. So we FREEZE the assembly for the teleport exactly like
	the server does: snapshot velocity, anchor it (no synthesised velocity while anchored),
	offset it, then restore anchor state and the real velocity. The net Anchored change is
	zero, so the server never sees a conflicting property.

	Everything below works in ASSEMBLIES, never in parts — see the block above the freeze. ]]
function RoadController._shiftWorld(self, shift: Vector3)
	for _, seg in self._segments do
		self:_moveTile(seg, seg:GetPivot() + shift)
	end

	--[[ The tile being built ahead and the ones being torn down behind live in the same folder but
		not in `_segments`, so the loop above does not reach them. They are welded assemblies like
		any other tile and cost one root write each — and the pending job's `delta` has to move too,
		or every unit still to be cloned would arrive a whole rebase away from the ones already in. ]]
	local job = self._pending
	if job then
		job.pivot += shift
		job.delta += shift
		if job.tile then
			self:_moveTile(job.tile, job.pivot)
		end
	end
	for _, dying in self._graveyard do
		if dying.tile.Parent then
			self:_moveTile(dying.tile, dying.tile:GetPivot() + shift)
		end
	end

	local car = self._car
	if not (car and car.PrimaryPart) then
		self:_notifyShift(shift) -- still a rebase, even if we never found our car
		return
	end

	--[[ ONE FREEZE PER ASSEMBLY, NOT ONE PER PART, and the distinction is the whole cost of this
		half of a rebase. A rigidly welded assembly IS one rigid body: anchor its root, write that
		root's CFrame, and every part welded to it comes along in a single engine-side transform.
		A car and its seated rider are one such body plus four wheels (spring-mounted, so each is
		its own assembly) — six writes, where walking the descendants was a hundred and twenty.

		Note this is why the old per-part version had to anchor EVERY part before moving any of
		them: with the assembly still whole, `p.CFrame = p.CFrame + shift` drags its welded
		neighbours along, so the next part in the loop would shift an already-shifted body a
		second time. Anchoring each part individually broke the body into independent statics and
		made the per-part arithmetic add up. Keying off `AssemblyRootPart` removes the need for
		the trick rather than re-implementing it — but the two must not be mixed.

		`AssemblyRootPart` is also what makes the rider correct without a special case. Welded
		into the seat they resolve to the CAR's root and cost nothing extra; thrown out of a wreck
		(RaceService._throwRider) they are a dozen SEPARATE assemblies, each of which surfaces its
		own root here and gets its own freeze. That second case is the one this has to get right:
		writing CFrames onto loose ragdoll limbs synthesises exactly the reconciliation velocity
		this function's header is about, except it fires the player's body off the road rather
		than flinging the car. ]]
	local roots: { BasePart } = {}
	local seen: { [BasePart]: boolean } = {}
	local function collect(p: BasePart)
		local root = p.AssemblyRootPart or p
		if not seen[root] then
			seen[root] = true
			table.insert(roots, root)
		end
	end

	for _, p in car:GetDescendants() do
		if p:IsA("BasePart") then
			collect(p)
		end
	end
	local character = Players.LocalPlayer.Character
	if character then
		for _, p in character:GetDescendants() do
			if p:IsA("BasePart") then
				collect(p)
			end
		end
	end

	--[[ Snapshotted PER ROOT rather than off the car alone. The car's own root speaks for
		everything welded to it and nothing else: the wheels are separate assemblies, so a
		one-root snapshot restored the chassis and handed the wheels back to physics stopped
		dead — a spin reset, and a suspension re-settle, on every rebase. ]]
	local lin = table.create(#roots)
	local ang = table.create(#roots)
	local wasAnchored = table.create(#roots)
	for i, root in roots do
		lin[i] = root.AssemblyLinearVelocity
		ang[i] = root.AssemblyAngularVelocity
		wasAnchored[i] = root.Anchored
		root.Anchored = true -- no synthesised velocity while anchored
	end

	for _, root in roots do
		root.CFrame += shift
	end

	for i, root in roots do
		if root.Parent then
			root.Anchored = wasAnchored[i]
			-- Order matters: an anchored part ignores a velocity write, so the momentum can only
			-- go back once the part is loose again. A root that was already anchored has no
			-- momentum to restore.
			if not wasAnchored[i] then
				root.AssemblyLinearVelocity = lin[i]
				root.AssemblyAngularVelocity = ang[i]
			end
		end
	end

	self:_notifyShift(shift)
end

-- Tell everything that tracks its own road-frame position (see `onWorldShift`) how far the
-- world just moved. Last thing in the rebase, so listeners see a settled world.
function RoadController._notifyShift(self, shift: Vector3)
	for fn in self._shiftListeners do
		local ok, err = pcall(fn, shift)
		if not ok then
			self.log:warn(string.format("A world-shift listener errored: %s", tostring(err)))
		end
	end
end

function RoadController._loop(self)
	--[[ Nothing that reasons about the RING may run while the opening road is still being laid.

		`_recycle`, `_maybeRebase` and `_beginPrefetch` all read `_segments[1]` and `_segments[#]` as
		the rear and front of a COMPLETE ring; during the build they are merely the lowest and
		highest of the tiles that have landed so far, so a recycle here would advance a front that
		is not the front and drop a tile on a pivot the build queue still owes a tile to. A rebase
		is worse: it would move the road out from under every pivot left in that queue.

		Nothing is lost by waiting. The build finishes in a couple of seconds and there are
		`DesiredSegmentCount - SegmentsBehind - 1` tiles of road in front of the car — thousands of
		studs — so there is no recycling to do yet even in principle. The graveyard is deliberately
		still stepped: it is per-tile work that reads none of the ring's ordering, and the opening
		build can retire a tile through `_planFor`'s whole-clone fallback. ]]
	if self._buildJob or #self._buildQueue > 0 then
		self:_stepGraveyard()
		return
	end

	local car = self._car
	if car and car.Parent and car.PrimaryPart then
		local leadAlong = self:along(car.PrimaryPart.Position)
		if leadAlong == leadAlong and math.abs(leadAlong) ~= math.huge then
			self:_recycle(leadAlong)
			self:_maybeRebase(leadAlong)
		end
	end

	--[[ OUTSIDE the car check, and after the recycle rather than before it. Outside, because a tile
		caught half-built or half-destroyed when the car goes away — a wreck, a steal in mid-air, a
		frame where the assembly has not landed — still has to be finished, and both are bounded work
		that ends by itself. After, because `_recycle` sorts the ring as it advances it and
		`_beginPrefetch` reads the rear and the front off that order. ]]
	self:_beginPrefetch()
	self:_stepPrefetch()
	self:_stepGraveyard()
end

--[[ Tell the entry screen where the build has got to, if it is up.

	THE THREE STEPS THIS FILE OWNS ARE THE SLOW ONES, which is why the reporting is here at all: the
	road build and the wait for our own car to arrive are most of what a player is looking at a black
	screen for on a phone, and `RaceUIController` cannot see either of them from where it stands (see
	its `setLoadPhase`). Pushed rather than polled, and pushed from the two lines either side of the
	work rather than from anywhere convenient — a step reported late is a step that never showed.

	Nothing here is load-bearing for the road. The screen may be down already (a fast client is
	driving before the bar is ever revealed) or gone entirely, and `setLoadPhase` decides that for
	itself — this end only has to say what happened. ]]
function RoadController._reportLoad(self, key: string, world: number?)
	local ui = Shard.get("RaceUIController")
	if ui then
		ui:setLoadPhase(key, world)
	end
end

--[[ Wait for our own car to arrive on THIS machine — the model, and the part physics will actually
	be handed to. Nil if it never came inside `deadline`.

	`_findCar` reads it off the seat we are sitting in, so this is really a wait on two separate
	replications landing: the humanoid's `SeatPart`, and then the car's parts streaming in behind it.
	PrimaryPart is the one to test because it is the one the engine hands the assembly over on — a
	model whose PrimaryPart is still nil is a car this client cannot be given. ]]
function RoadController._awaitCar(self, deadline: number): Model?
	while self._active and os.clock() < deadline do
		local car = self:_findCar()
		local primary = car and car.PrimaryPart
		if primary and primary.Parent then
			return car
		end
		task.wait(0.05)
	end
	return nil
end

--[[ Is there collidable road under `car` right now? One ray, straight down, against our own local
	road and nothing else.

	`RespectCanCollide` is the whole point — see "THE ACK IS A PROMISE". Without it the ray stops on
	the first lane line and reports a deck that may not be there.

	The reach is generous on purpose. It is not measuring anything; it only has to distinguish "road"
	from "no road", and a fresh car sits `RaceConfig.SpawnClearance` above the deck plus however much
	of the body hangs below its PrimaryPart. Anything this ray can find inside the local road folder
	is, by construction, a surface laid at the deck. ]]
local GROUND_PROBE_UP = 5 -- start above the car, so a wheel resting ON the deck can't shadow it
local GROUND_PROBE_DOWN = 60

function RoadController._hasGroundUnder(self, car: Model): boolean
	local primary = car.PrimaryPart
	local folder = self._folder
	if not (primary and primary.Parent and folder and folder.Parent) then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	params.RespectCanCollide = true
	local from = primary.Position + Vector3.yAxis * GROUND_PROBE_UP
	return workspace:Raycast(from, Vector3.yAxis * -(GROUND_PROBE_UP + GROUND_PROBE_DOWN), params) ~= nil
end

function RoadController._onRaceStart(self, world: number?, laneOffset: Vector3?)
	if self._active then
		return
	end
	self._active = true
	self._raceToken += 1
	local token = self._raceToken
	--- Taken before the build rather than after it, because the build can now wait for this world's
	--- road to arrive, and the server's clock started when it sent `RaceStart`. See the ack below.
	local deadline = os.clock() + math.max(1, RaceConfig.EnterReadyTimeout - 0.5)

	--- Last run's road out of the scene first, if any of it is still leaving: this run's ring is
	--- about to be built where it is standing. See `_finishEvict` for why here is where it is free.
	self:_finishEvict()

	-- The world rides along: this is the first authoritative word the client has about where it is
	-- going, and the screen has been guessing from a replicated attribute until now.
	self:_reportLoad("road", world)
	if not self:_buildRoad(world, laneOffset, token) then
		if token == self._raceToken then
			self._active = false
		end
		return
	end

	--[[ Everything from here to the ack is the promise being made good on (see the header). Giving up
		is the correct ending, not a failure to handle: the server's own fail-safe ends the entry
		safely at `EnterReadyTimeout`, and that is what this is deliberately failing towards rather
		than acking anyway.

		A HAIR INSIDE THE SERVER'S TIMEOUT, so that when an entry does die, the log says why. The two
		sides start their clocks at the same event and the server's abort fires `RaceEnd` — which
		clears `_active` and unwinds this thread — so a deadline of exactly `EnterReadyTimeout` loses
		the race to it every time, and the only line left is the server's "never acked", which knows
		that it happened and not which half of the promise failed. ]]
	self:_reportLoad("stream")
	task.spawn(function()
		local car = self:_awaitCar(deadline)
		if not (car and self._active) then
			if self._active then
				self.log:warn("Entered race but our car never arrived on this client; not acking — the server will abort the entry.")
			end
			return
		end

		-- ...and that we have somewhere to put it. Re-checked per frame rather than once, because
		-- the thing we are waiting on is art still landing: the answer is expected to change.
		while self._active and not self:_hasGroundUnder(car) do
			if os.clock() >= deadline then
				self.log:warn("Entered race but no collidable road ever appeared under our car; not acking — the server will abort the entry.")
				return
			end
			task.wait(0.05)
		end
		if not self._active then
			return
		end

		--[[ ...and the third thing, which the ack did not used to have to wait for: the rest of the
			road.

			THE ACK IS THE RELEASE. `RaceService._onRaceReady` unanchors the car and hands this
			client network ownership, so the instant this fires the player is DRIVING. That was
			harmless while `_buildRoad` cloned the whole ring in one frame — the road existed before
			the ack could happen — and stopped being harmless the moment the build was spread: the
			car went live with one tile down and eight still landing, behind a loading screen the
			player could not see past. They arrived at the first corner already damaged, having
			never been shown the road they hit.

			Covering it on the UI side alone was the wrong fix and made it worse: holding the SCREEN
			longer just extends how long the car drives unwatched. The car must not move until there
			is a road to move along, so the gate belongs here, on the one event that releases it.

			The build runs on its own connection (`_startBuild`), not on `_conn`, so waiting here
			cannot deadlock it — `_conn` is not even connected yet. And giving up is still the
			correct ending: no ack means the server's own fail-safe ends the entry at
			`EnterReadyTimeout`, which is the same safe path the two waits above fail into. ]]
		if not self:isWorldReady() then
			self:_reportLoad("world")
			while self._active and not self:isWorldReady() do
				if os.clock() >= deadline then
					self.log:warn(
						"Entered race but the local road never finished building; not acking — the server will abort the entry."
					)
					return
				end
				task.wait(0.05)
			end
			if not self._active then
				return
			end
		end

		-- All three halves of the promise hold. Let the car go.
		self:getRemoteEvent("RaceReady"):Fire()

		self._car = car
		self:_reportLoad("live")
		self._conn = RunService.Heartbeat:Connect(function()
			self:_loop()
		end)
	end)
end

function RoadController._onRaceEnd(self)
	self._active = false
	self._raceToken += 1
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	self._car = nil
	--- Before the folder goes: a part-built tile is parented inside it and rides to the drain with
	--- everything else, so all this has to drop is the bookkeeping that still points at it.
	self:_cancelBuild()
	if self._folder then
		--[[ NOT `self._folder:Destroy()`, which is what this was and what the end-of-race hitch was.

			Destroying a tile costs ~20 ms (see `_retire`), and the ring is `DesiredSegmentCount`
			deep — so the old line was nine tiles and ~9,000 instances of teardown on ONE frame, at
			the exact moment the fade back to the lobby is running. It is the same spike
			`RaceConfig.TileBuildBudget` was introduced to kill on a recycle, simply moved to the one
			frame that had no budget applied to it.

			NOR `husk.Parent = nil`, WHICH IS WHAT REPLACED IT, for the same reason one step down:
			taking the ring out of the scene is itself ~150 ms of one frame, and it is the frame the
			results beat opens on. `THE EVICTION` has the measurements and the argument; the ring
			leaves a tile per frame now, and only the ten frames it is spread over changed.

			The DESTROY is deferred either way, and a destroy is invisible by definition once nothing
			can see the thing being destroyed. So the husk is handed to `_stepDrain`, which runs it
			down at the same per-frame budget a recycle uses, off-scene, across the lobby beat.
			~9,000 instances at `TileBuildBudget` clears in a couple of seconds and nothing is
			watching for any of them. ]]
		local husk = self._folder
		self._folder = nil

		--[[ Every live tile joins the queue, and `_graveyard`'s half-torn jobs are carried over
			WITH THEIR CURSORS INTACT rather than restarted — they are the same job objects, their
			`node` references still point inside the husk, and `_sliceTile` picks each one up exactly
			where the race left it. Restarting them would re-plan a tree that is already part gone
			and re-walk units whose nodes have no parent; correct, but wasted work on the one frame
			that cannot afford it. Order does not matter now that none of it is visible. ]]
		local queued: { [Instance]: boolean } = {}
		for _, dying in self._graveyard do
			queued[dying.tile] = true
			table.insert(self._drain, dying)
		end
		--[[ `queued` is not tidiness. `_retire` does NOT unparent — a tile being torn down stays a
			child of the road folder and is found by the scan below — so without this every job the
			graveyard was already part-way through would be enqueued a second time, as a FRESH job
			with no cursor. `_sliceTile`'s `not tile.Parent` guard makes that harmless rather than a
			double destroy, but harmless costs a frame apiece and, worse, hides the aliasing from
			anyone reading it later. Skip what is already spoken for. ]]
		local tiles: { Model } = {}
		for _, tile in husk:GetChildren() do
			if tile:IsA("Model") then
				--- Every tile has to LEAVE, including the ones the graveyard is already part-way
				--- through: a half-torn tile is still standing in the scene until it is moved.
				table.insert(tiles, tile)
				if not queued[tile] then
					table.insert(self._drain, { tile = tile })
				end
			end
		end
		--- ...and then the ring comes out of the scene a tile at a time, which is what queues the two
		--- shell markers behind the jobs above. See `THE EVICTION`.
		self:_startEvict(husk, tiles)
	end
	--[[ Both queues held instances inside the folder that just went, so there is nothing left to
		build or destroy — only bookkeeping pointing at dead things. Dropped before the segment list
		for the same reason it is: a race that starts again must not inherit a tile from the last.

		`_graveyard` is emptied rather than run down because the drain now OWNS those jobs (they were
		copied into it above); clearing the field here is what stops the next race's `_loop` from
		stepping a queue somebody else is already stepping. ]]
	if self._builtInline > 0 then
		self.log:warn(string.format(
			"%d road tile(s) were built whole rather than across frames, one dropped frame each. Expected for the first recycle of a race; more than that means the car is outrunning RaceConfig.TileBuildBudget.",
			self._builtInline
		))
	end
	self._builtInline = 0
	self._pending = nil
	self._graveyard = {}
	self._plans = {}
	self._segments = {}
	self._variants = {}
	self._origin = nil
	self._world = nil
	self._map = nil
end

-- === Getting this player's world road =======================================
--[[ The client half of `RaceConfig.WorldRoadsPerPlayer`; `RoadService._sendRoad` is the other.

	A world's road arrives in `PlayerGui.<WorldRoadsName>` as a folder carrying the number of
	instances it will hold. `_adoptRoad` waits for all of them, moves the folder into this client's
	own `ReplicatedStorage.<WorldRoadsName>` (where `_tileSource` has always read worlds from) and
	tells the server, which then lets go of its copy. That arrives here as the folder's parent going
	nil, and the folder is put straight back. ]]

--- Seconds a road may take to land before this client gives up on it. A City on a slow phone is a
--- few seconds; past this the connection is not really there, and a race entry has its own fallback.
local ROAD_ARRIVAL_CAP = 90
--- Seconds without an answer before asking for a road again. The server sends each world once, so a
--- repeat only matters if the first ask landed before the server was ready to answer it.
local ROAD_ASK_AGAIN = 15
--- Longest the first ask waits for the join screen to lift, for a join screen that never says so.
local PREFETCH_CAP = 60

--- Can the server send this map? False with the feature off, which means every world is already in
--- ReplicatedStorage for everybody.
function RoadController._serverHasRoad(self, map: string): boolean
	if not RaceConfig.WorldRoadsPerPlayer then
		return false
	end
	local roads = ReplicatedStorage:FindFirstChild(RaceConfig.WorldRoadsName)
	local maps = roads and roads:GetAttribute(RaceConfig.WorldRoadMapsAttribute)
	return type(maps) == "string" and string.find(maps, "|" .. map .. "|", 1, true) ~= nil
end

--- Ask for a world's road, unless it is here already, was asked for recently, or is not the
--- server's to send.
function RoadController._requestRoad(self, world: unknown)
	local index = WorldConfig.resolve(world)
	local map = WorldConfig.mapFor(index)
	if not map or self._roads[map] or not self:_serverHasRoad(map) then
		return
	end
	local asked = self._asked[map]
	if asked and os.clock() - asked < ROAD_ASK_AGAIN then
		return
	end
	self._asked[map] = os.clock()
	self:getRemoteEvent("RequestWorldRoad"):Fire(index)
end

--- Wait for the road a race entry needs, asking for it first. Nil if it does not land in time.
function RoadController._awaitRoad(self, world: number?, map: string): Instance?
	self:_requestRoad(world)
	local giveUp = os.clock() + RaceConfig.WorldRoadWait
	while not self._roads[map] and os.clock() < giveUp do
		task.wait(0.1)
	end
	if not self._roads[map] then
		self.log:warn(string.format(
			"The road for '%s' had not finished arriving after %ds; racing the default road this once.",
			map, RaceConfig.WorldRoadWait
		))
	end
	return self._roads[map]
end

--- Take a delivered road once every instance of it is here. See the block above.
function RoadController._adoptRoad(self, folder: Instance)
	local expected = folder:GetAttribute(RaceConfig.WorldRoadCountAttribute)
	if not folder:IsA("Folder") or type(expected) ~= "number" then
		return
	end
	local map = folder.Name
	local began = os.clock()
	while #folder:GetDescendants() < expected do
		if not folder.Parent or os.clock() - began > ROAD_ARRIVAL_CAP then
			self.log:warn(string.format(
				"The road for '%s' never finished arriving (%d of %d instances).",
				map, #folder:GetDescendants(), expected
			))
			-- So the next race into it asks straight away (the server will send a lost one again).
			self._asked[map] = nil
			return
		end
		task.wait(0.25)
	end

	local home = ReplicatedStorage:FindFirstChild(RaceConfig.WorldRoadsName) or ReplicatedStorage
	folder.Parent = home
	self._roads[map] = folder
	folder.AncestryChanged:Connect(function(_, parent)
		if parent == nil and self._roads[map] == folder then
			-- Deferred: the engine refuses a re-parent from inside an ancestry change.
			task.defer(function()
				if folder.Parent == nil then
					folder.Parent = home
				end
			end)
		end
	end)
	self.log:info(string.format("Road for '%s' arrived: %d instances in %.1fs.", map, expected, os.clock() - began))
	self:getRemoteEvent("WorldRoadReceived"):Fire(map)
end

--[[ Watch the PlayerGui for roads being delivered, for the whole session.

	EVERY INBOX, NOT ONLY THE FIRST. The server's inbox is a ScreenGui that survives a respawn
	(`RoadService._inbox` has why a Folder did not), but if one is ever lost the server makes a new
	one, and a watcher that stopped looking after the first would never see a road again. ]]
function RoadController._watchRoadInbox(self)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local function watch(inbox: Instance)
		if inbox.Name ~= RaceConfig.WorldRoadsName then
			return
		end
		for _, child in inbox:GetChildren() do
			task.spawn(self._adoptRoad, self, child)
		end
		inbox.ChildAdded:Connect(function(child)
			self:_adoptRoad(child)
		end)
	end
	playerGui.ChildAdded:Connect(watch)
	for _, child in playerGui:GetChildren() do
		watch(child)
	end
end

--[[ Ask for this player's world once the join is over, and for every world they move to after it.

	AFTER THE JOIN ON PURPOSE. The join is the client's worst few seconds (the lobby is still streaming
	in) and a road is no use to anybody until they press Play. `JoinScreenRunning` is the join screen's
	own flag, cleared as it lifts. ]]
function RoadController._prefetchRoads(self)
	if not RaceConfig.WorldRoadsPerPlayer then
		return
	end
	local player = Players.LocalPlayer
	local giveUp = os.clock() + PREFETCH_CAP
	while ReplicatedFirst:GetAttribute("JoinScreenRunning") == true and os.clock() < giveUp do
		task.wait(0.5)
	end
	self:_requestRoad(player:GetAttribute(WorldConfig.WorldAttribute))
	player:GetAttributeChangedSignal(WorldConfig.WorldAttribute):Connect(function()
		self:_requestRoad(player:GetAttribute(WorldConfig.WorldAttribute))
	end)
end

RoadController:withRemoteEvents({
	{
		RaceStart = function(_seed, world, laneOffset)
			RoadController:_onRaceStart(world, laneOffset)
		end,
		RaceEnd = function()
			RoadController:_onRaceEnd()
		end,
	},
	"RaceReady",
	"RequestWorldRoad",
	"WorldRoadReceived",
})

RoadController:withLifecycle({
	init = function(self)
		self._segments = {}
		self._active = false
		self._nextIndex = 0
		self._variants = {} -- this world's numbered segments, in order, resolved per race
		self._plans = {} -- [segment] = build plan, or false for art that cannot be sliced
		self._pending = nil -- the tile being built for the next recycle
		self._graveyard = {} -- tiles that have left the road, being destroyed a slice at a time
		--[[ The same, for the road a FINISHED race left behind — see `_stepDrain`. Session-scoped
			rather than race-scoped, because its contents outlive by design the race that filled it. ]]
		self._drain = {}
		self._drainConn = nil
		--- The ring of a finished race on its way out of the scene, a tile per frame. See `THE
		--- EVICTION`; nil whenever there is nothing leaving, which is almost always.
		self._evict = nil
		--[[ The opening road, laid across frames — see `_startBuild`. Race-scoped in content but
			declared here like the rest: `_buildRoad` refills the queue and `_onRaceEnd` cancels it. ]]
		self._buildQueue = {} -- tiles (and variant pre-warms) still to build for this race's ring
		self._buildJob = nil -- the one being built right now
		self._buildConn = nil
		self._builtInline = 0 -- recycles the builder did not get ahead of; reported at race end
		-- Survives a race teardown on purpose: controllers register once at start and stay
		-- registered across every race, exactly like their remote handlers do.
		self._shiftListeners = {} -- [fn] = true
		--- Bumped by every race start and end, so a build that waited for its road can tell it is stale.
		self._raceToken = 0
		self._roads = {} :: { [string]: Instance } -- [map] = this client's copy of a delivered world road
		self._asked = {} :: { [string]: number } -- [map] = when it was last asked for
	end,

	start = function(self)
		task.spawn(self._watchRoadInbox, self)
		task.spawn(self._prefetchRoads, self)
	end,
})

return RoadController
