--[[
	RoadService  (server — road PROVIDER)
	-------------------------------------
	The road is client-sided (see RoadController): each driver builds and streams their own local
	copy, so the road never replicates and segment movement costs zero network. This service
	therefore does NO streaming. It only:

	  1. Publishes the ROAD ART every client needs to clone — the authored world folders from
	     `Workspace.Worlds` into `ReplicatedStorage.WorldRoads`, plus the legacy single tile
	     template for a world that has no map of its own.
	  2. Publishes the RACE ORIGIN: the one CFrame every world's road is laid at, so that both
	     sides agree on where the race is without either of them measuring it.
	  3. Stashes the authored `Workspace.RoadSegments` (and anything left in `Workspace.Worlds`)
	     into ServerStorage at runtime, so there is no live or duplicated road replicating,
	     rendering, or standing visibly through the lobby. Non-destructive: the edit session
	     reverts on stop and the tiles stay editable in the place file.
	  4. Answers the road-frame questions the server has to be able to ask about a race it cannot
	     see — where to drop a car, where lane centre is, how wide the corridor is — PER WORLD.
	  5. Flattens the stud texture on the drivable surface of every published tile when
	     `RoadStudsConfig.RoadStuds` is off, before any client clones one. See that config.

	=== WHY THE ORIGIN EXISTS ==================================================================

	A world's tiles cannot be streamed where they are authored. They are parked wherever the
	modeller left them and two of them run straight through the lobby, so every road is laid at ONE
	place instead — the pivot of the authored `RoadSegments` tile, which is where the race already
	happened before there were worlds. What survives that move is `DriveCenterOffset`, the lane
	centre measured FROM the tile's pivot rather than in absolute X; `DriveCenterX` is only true
	while a tile sits where it was built. See WorldConfig's "The maps".

	The origin is forced to identity rotation. `ForwardAxis` is a WORLD axis by contract, so an
	axis-aligned road is what every consumer of `along`/`cross` already assumes; a tile authored on
	a diagonal would otherwise silently skew the whole race.

	=== EVERY FRAME QUESTION TAKES A WORLD =====================================================

	Lane centre differs by world (City sits 15 studs off its deck centre, Arctic a quarter of a
	stud), so `getDriveCenter()` with no argument is only ever right by luck. The accessors take an
	optional world index and fall back to the default world for the callers that legitimately have
	no player in hand. Anything holding a player must pass `WorldService:worldOf(player)`.

	Deck height is the exception and is deliberately world-independent: a tile's pivot sits ON the
	deck, so laying any tile at the origin puts its deck at the origin's Y.
]]

local CollectionService = game:GetService("CollectionService")
local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local RaceConfig = require(ReplicatedStorage.shared.Configs.RaceConfig)
local RoadStudsConfig = require(ReplicatedStorage.shared.Configs.RoadStudsConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local RoadService = Shard.new("RoadService")

local function axisVector(letter: string): Vector3
	letter = string.upper(letter or "Z")
	if letter == "X" then
		return Vector3.xAxis
	elseif letter == "Y" then
		return Vector3.yAxis
	end
	return Vector3.zAxis
end

--- The numbered tile Models in a world folder, in order. Anything else in there is scenery the
--- modeller parked beside the road and is not part of the library.
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

--- How far a part reaches along a world axis, rotation included (its world AABB on that axis).
local function extentAlong(part: BasePart, axis: Vector3): number
	local cf, size = part.CFrame, part.Size
	return math.abs(cf.RightVector:Dot(axis)) * size.X
		+ math.abs(cf.UpVector:Dot(axis)) * size.Y
		+ math.abs(cf.LookVector:Dot(axis)) * size.Z
end

function RoadService.along(self, position: Vector3): number
	return position:Dot(self._forwardWorld)
end

--[[ The authored road containers, Workspace first. Both were parked in ServerStorage on 2026-10-13
	to clear the edit view; dragging one back into Workspace to edit it still works, because
	Workspace is asked first. Only the top-level folder in ServerStorage counts, never `StashedRoad`
	or a backup that happens to carry a tagged tile. ]]
local function authoredFolder(name: string): Instance?
	return workspace:FindFirstChild(name) or ServerStorage:FindFirstChild(name)
end

-- First tagged RoadSegment Model in Workspace or the parked folder (robust to accidental nesting).
function RoadService._findAuthoredTile(self): Model?
	local parked = ServerStorage:FindFirstChild(RaceConfig.RoadSegmentsFolderName)
	for _, inst in CollectionService:GetTagged(RaceConfig.RoadSegmentTag) do
		if inst:IsA("Model") and (inst:IsDescendantOf(workspace) or (parked and inst:IsDescendantOf(parked))) then
			return inst
		end
	end
	return nil
end

function RoadService._stash(self): Folder
	local stash = ServerStorage:FindFirstChild("StashedRoad")
	if not stash then
		stash = Instance.new("Folder")
		stash.Name = "StashedRoad"
		stash.Parent = ServerStorage
	end
	return stash
end

-- === Publishing =============================================================

--[[ Move the authored world folders out to ReplicatedStorage, and everything else in the library
	into the stash. Reuses an already-published folder from a prior run in the same edit session,
	exactly as the tile template does.

	MOVED, NOT CLONED: a copy would leave the originals in Workspace rendering and replicating,
	which is half of what this is for. The place file is untouched — a playtest's reparenting
	reverts when it stops. See `RaceConfig.WorldRoadsName` for why all of them go at once. ]]
function RoadService._publishWorldRoads(self): Folder
	local published = ReplicatedStorage:FindFirstChild(RaceConfig.WorldRoadsName)
	if not published then
		published = Instance.new("Folder")
		published.Name = RaceConfig.WorldRoadsName
		published.Parent = ReplicatedStorage
	end

	local library = authoredFolder(WorldConfig.RoadFolderName)
	if library then
		for _, child in library:GetChildren() do
			if child:IsA("Folder") and #tilesOf(child) > 0 then
				child.Parent = published
			end
		end
		-- Whatever is left is not a road (the modeller's loose obstacle art, at the time of
		-- writing). It has no business in Workspace and no business replicating either.
		library.Parent = self:_stash()
	end

	return published
end

--[[ Re-point one tile's drivable surface at the flat MaterialVariant twins. See RoadStudsConfig for
	which parts count as road and why the twin keeps the physics.

	The corridor is read off the tile's own attributes rather than the world's measured frame, so a
	tile is judged where it actually sits: the published tiles have not moved to the race origin
	(clients do that when they clone them), and the legacy template only carries the absolute
	`DriveCenterX`. `twins` caches the MaterialService lookup per variant name across tiles, with
	`false` meaning no usable twin. Returns how many parts were re-pointed. ]]
function RoadService._flattenTile(self, tile: Model, twins: { [string]: MaterialVariant | false }): number
	local width = tile:GetAttribute("DriveWidth")
	if type(width) ~= "number" then
		self.log:warn(string.format("%s has no DriveWidth, so its road keeps the stud texture.", tile:GetFullName()))
		return 0
	end

	local pivot = tile:GetPivot().Position
	local offset = tile:GetAttribute("DriveCenterOffset")
	if type(offset) ~= "number" then
		local driveCenterX = tile:GetAttribute("DriveCenterX")
		offset = if type(driveCenterX) == "number" then driveCenterX - pivot:Dot(self._crossWorld) else 0
	end
	local centre = pivot:Dot(self._crossWorld) + offset
	local half = width / 2
	local deckY = pivot.Y

	local count = 0
	for _, bucketName in RoadStudsConfig.Buckets do
		local bucket = tile:FindFirstChild(bucketName)
		if not bucket then
			continue
		end
		for _, part in bucket:GetDescendants() do
			if not part:IsA("BasePart") or part.MaterialVariant == "" then
				continue
			end

			-- A flat slab lying on the deck, not a kerb or a bank...
			local height = extentAlong(part, Vector3.yAxis)
			local top = part.Position.Y + height / 2
			if height > RoadStudsConfig.MaxThickness
				or top < deckY - RoadStudsConfig.TopBelowDeck
				or top > deckY + RoadStudsConfig.TopAboveDeck
			then
				continue
			end

			-- ...that reaches into the corridor between the guardrails.
			local along = part.Position:Dot(self._crossWorld)
			local reach = extentAlong(part, self._crossWorld) / 2
			if along + reach < centre - half or along - reach > centre + half then
				continue
			end

			local name = part.MaterialVariant
			local twin = twins[name]
			if twin == nil then
				local found = MaterialService:FindFirstChild(name .. RoadStudsConfig.FlatSuffix)
				twin = if found and found:IsA("MaterialVariant") then found else false
				twins[name] = twin
			end
			-- No twin, or a part whose Material cannot bind it (the Neon strips wear a vestigial name).
			if twin and twin.BaseMaterial == part.Material then
				part.MaterialVariant = twin.Name
				count += 1
			end
		end
	end
	return count
end

--[[ Flatten the road on every tile a client can clone: the published worlds and the legacy
	template. Runs before any player is in, so the flat names ship in the first replication. ]]
function RoadService._flattenRoads(self, published: Folder, template: Model)
	local twins = {} :: { [string]: MaterialVariant | false }
	local tiles = { template }
	for _, folder in published:GetChildren() do
		for _, tile in tilesOf(folder) do
			table.insert(tiles, tile)
		end
	end

	local count = 0
	for _, tile in tiles do
		count += self:_flattenTile(tile, twins)
	end

	local missing = {}
	for name, twin in twins do
		if not twin then
			table.insert(missing, name .. RoadStudsConfig.FlatSuffix)
		end
	end
	if #missing > 0 then
		table.sort(missing)
		self.log:warn(string.format(
			"No %s in MaterialService, so that road keeps its stud texture. Run the BuildFlatMaterials command in Studio.",
			table.concat(missing, ", ")
		))
	end
	self.log:info(string.format("Race road flattened: %d part(s) across %d tile(s).", count, #tiles))
end

--[[ Measure one world: the numbers a road built from its tiles will have once it is laid at the
	origin. Read off tile 1 and asserted against the rest, because `NormalizeRoadSegments` forces
	one drive frame per world and a tile that disagrees is a tile that will jog the corridor
	sideways at a seam — a bug that reads as "the car drifts into the rail on tile 3". ]]
function RoadService._measure(self, name: string, tiles: { Model }): { [string]: any }?
	local first = tiles[1]
	if not first then
		return nil
	end

	local segmentLength = first:GetAttribute("SegmentLength")
	if type(segmentLength) ~= "number" then
		local _, size = first:GetBoundingBox()
		segmentLength = size:Dot(self._forwardWorld)
	end

	--[[ Lane centre relative to the pivot. The attribute is what a normalised tile carries; the
		subtraction is the fallback for a tile that predates it (the authored `RoadSegments` tile
		is one), and it is the same quantity — `DriveCenterX` is absolute only because the tile has
		not moved yet. ]]
	local offset = first:GetAttribute("DriveCenterOffset")
	if type(offset) ~= "number" then
		local driveCenterX = first:GetAttribute("DriveCenterX")
		offset = if type(driveCenterX) == "number"
			then driveCenterX - first:GetPivot().Position:Dot(self._crossWorld)
			else 0
	end

	local driveWidth = first:GetAttribute("DriveWidth")

	for index = 2, #tiles do
		local tile = tiles[index]
		local theirs = tile:GetAttribute("DriveCenterOffset")
		if type(theirs) == "number" and math.abs(theirs - offset) > 0.05 then
			self.log:warn(string.format(
				"%s/%s sits %.2f studs off the rest of its world's lane centre — re-run NormalizeRoadSegments.",
				name, tile.Name, theirs - offset
			))
		end
		local theirLength = tile:GetAttribute("SegmentLength")
		if type(theirLength) == "number" and math.abs(theirLength - segmentLength) > 0.01 then
			self.log:warn(string.format("%s/%s is %.2f studs long, not %.2f — its seams will not meet.",
				name, tile.Name, theirLength, segmentLength))
		end
	end

	return {
		segmentLength = segmentLength,
		driveCenterOffset = offset,
		driveWidth = if type(driveWidth) == "number" then driveWidth else nil,
		variants = #tiles,
	}
end

-- === Road frame accessors ===================================================
-- Read off what was published, so they describe exactly the road a client builds. ObstacleService
-- uses these to sanity-check reported hits without owning any geometry.

--[[ Everything the server can say about one world's road. Never nil once the service has started:
	an unknown or map-less world falls back to the frame measured off the published tile template,
	which is the road that world will actually get (RoadController makes the same substitution). ]]
function RoadService.frameFor(self, world: unknown)
	local map = WorldConfig.mapFor(world)
	return (map and self._frames[map]) or self._fallbackFrame
end

function RoadService.getSegmentLength(self, world: unknown): number?
	local frame = self:frameFor(world)
	return frame and frame.segmentLength
end

function RoadService.getForward(self): Vector3?
	return self._forwardWorld
end

-- The road's cross axis, chosen so that `cross:Cross(Vector3.yAxis) == forward`. Lane
-- offsets in ObstacleConfig are measured along this axis.
function RoadService.getCross(self): Vector3?
	return self._crossWorld
end

--[[ Cross-axis coordinate of the lane centre between the guardrails — the road contract's
	`DriveCenterX`, except derived rather than read, because the tiles have been moved to the race
	origin and the authored absolute is no longer where they are. ]]
function RoadService.getDriveCenter(self, world: unknown): number?
	local frame = self:frameFor(world)
	if not (frame and self._origin) then
		return nil
	end
	return self._origin.Position:Dot(self._crossWorld) + frame.driveCenterOffset
end

--[[ Y of the road surface every client builds its local road at.

	The one number the server can state about a road that only exists on clients, and it holds for
	the whole race AND for every world: a normalised tile's pivot sits on its deck, every road is
	laid at the origin, and both recycling and rebasing only ever translate ALONG the road. So this
	is not an estimate of where a given client's deck is — it is where it is.

	Which makes it the only sane floor for `RaceService`'s void guard. The server has no road under
	the car it owns, so "has this car fallen out of the world" cannot be asked of the geometry; it
	has to be asked of this number. ]]
function RoadService.getDeckY(self): number?
	return self._origin and self._origin.Position.Y
end

-- Width of the drivable corridor between the guardrails, centred on the drive centre. nil if the
-- world's tiles don't declare one — there's no sane fallback (a tile's bounding box takes in
-- scenery far outside the road), so callers opt out rather than guess an edge.
function RoadService.getDriveWidth(self, world: unknown): number?
	local frame = self:frameFor(world)
	return frame and frame.driveWidth
end

--[[ Public: where to drop a fresh car in a given world. A CFrame on the deck surface, centred
	between the guardrails and facing the drive direction. Built from the published origin, so it
	matches exactly where that world's client-side road gets laid. The caller lifts the car by its
	bounding box so the wheels rest on this surface. ]]
function RoadService.getSpawnCFrame(self, world: unknown): CFrame?
	local frame = self:frameFor(world)
	if not (frame and self._origin) then
		return nil
	end
	-- Spawn on the origin tile, at its middle (+ optional SpawnAlong nudge).
	local along = self:along(self._origin.Position) + frame.segmentLength * 0.5 + RaceConfig.SpawnAlong
	local pos = self._forwardWorld * along
		+ self._crossWorld * (self._origin.Position:Dot(self._crossWorld) + frame.driveCenterOffset)
		+ Vector3.yAxis * self._origin.Position.Y
	return CFrame.lookAt(pos, pos + self._forwardWorld)
end

RoadService:withLifecycle({
	init = function(self)
		self._frames = {} :: { [string]: any } -- by MAP NAME, not world index: two worlds may share one
	end,

	start = function(self)
		-- Reuse an already-published template (e.g. a prior run) or clone a fresh one.
		local template = ReplicatedStorage:FindFirstChild(RaceConfig.RoadTemplateName)
		if not template then
			local tile = self:_findAuthoredTile()
			if not tile then
				self.log:warn("No RoadSegment tile found in Workspace or ServerStorage; road provider disabled.")
				return
			end
			template = tile:Clone()
			template.Name = RaceConfig.RoadTemplateName
			template.Parent = ReplicatedStorage
		end
		self._template = template

		self._forwardWorld = axisVector(tostring(template:GetAttribute("ForwardAxis") or "Z"))
		self._crossWorld = Vector3.yAxis:Cross(self._forwardWorld)

		--[[ The race origin: where tile 0 of every world's road is laid. Position from the authored
			tile (so dragging the road in Studio still moves the race), rotation forced to identity
			(so a tile nudged off-axis in the Explorer cannot skew every world at once). ]]
		local authored = template.PrimaryPart and template.PrimaryPart.CFrame or template:GetPivot()
		local rx, ry, rz = authored:ToOrientation()
		if math.abs(rx) + math.abs(ry) + math.abs(rz) > 1e-3 then
			self.log:warn("The authored road tile's pivot is rotated; the race origin ignores that (ForwardAxis is a world axis).")
		end
		self._origin = RaceConfig.RaceOriginOverride or CFrame.new(authored.Position)

		-- Publish the worlds, then measure each of them.
		local published = self:_publishWorldRoads()
		published:SetAttribute("RaceOrigin", self._origin)
		published:SetAttribute("ForwardAxis", tostring(template:GetAttribute("ForwardAxis") or "Z"))

		if not RoadStudsConfig.RoadStuds then
			self:_flattenRoads(published, template)
		end

		for _, folder in published:GetChildren() do
			local frame = self:_measure(folder.Name, tilesOf(folder))
			if frame then
				self._frames[folder.Name] = frame
			end
		end

		-- The road a world with no map (or a missing folder) gets: the single authored tile,
		-- repeated. Measured the same way so nothing downstream has to know the difference.
		self._fallbackFrame = self:_measure(RaceConfig.RoadTemplateName, { template })
		self._segmentLength = self._fallbackFrame and self._fallbackFrame.segmentLength

		-- Stash the authored road out of Workspace so nothing replicates or moves on the
		-- server. Move the whole container, plus any stray tagged tiles left behind.
		local stash = self:_stash()
		local folder = authoredFolder(RaceConfig.RoadSegmentsFolderName)
		if folder then
			folder.Parent = stash
		end
		for _, inst in CollectionService:GetTagged(RaceConfig.RoadSegmentTag) do
			if inst:IsDescendantOf(workspace) then
				inst.Parent = stash
			end
		end

		local names = {}
		for map, frame in self._frames do
			table.insert(names, string.format("%s x%d", map, frame.variants))
		end
		table.sort(names)
		self.log:info(string.format(
			"Road provider ready — %d world road(s) published (%s), race origin %s, SegmentLength %.1f. Road is client-streamed.",
			#names, #names > 0 and table.concat(names, ", ") or "none",
			tostring(self._origin.Position), self._segmentLength or -1
		))
	end,
})

return RoadService
