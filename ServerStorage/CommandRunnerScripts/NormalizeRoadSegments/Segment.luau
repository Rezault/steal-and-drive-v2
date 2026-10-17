--[[
	Segment — the road-tile contract, as code
	-----------------------------------------
	Turns a raw imported road tile (a Model full of loose parts, straight out of the modeller's
	file) into a tile the streaming road can use: the same shape `Workspace.RoadSegments`' tile —
	the default map — already has, because that one is the reference and every other tile has to
	be interchangeable with it.

	WHAT A TILE HAS TO BE. `RoadController` clones ONE tile and lays copies end to end along the
	drive axis, moving each by `SegmentLength` from the last, and it does that with `PivotTo` —
	so a tile is defined entirely by its own pivot:

	    Gameplay/OriginMarker  the PrimaryPart, and therefore the pivot. Sits ON the deck surface
	                           at the tile's ENTRY end, centred across the deck. Everything else
	                           in the contract is measured from it.
	    SegmentLength          how far the next tile starts along the drive axis. Read off the
	                           deck slab, which is exactly one tile long by construction.
	    ForwardAxis            "Z" everywhere here; the road runs down +Z.
	    DriveCenterX           cross-axis centre of the corridor BETWEEN THE GUARDRAILS, absolute.
	                           Not the deck's own centre — the two differ by up to a stud, and
	                           obstacles/spawns ride this one.
	    DriveWidth             nominal corridor width, rail line to rail line. Nominal is
	                           load-bearing: it is NOT where the car stops (see ObstacleConfig.Wall).
	    DriveCenterOffset      DriveCenterX relative to the OriginMarker. The absolute one only
	                           holds while a tile is streamed at the X it was authored at; this one
	                           survives being streamed anywhere, which is what world-switching needs.
	    EntryZ / ExitZ         the authored world Z of the tile's two ends. Reference only —
	                           nothing reads them at runtime — but they make a mis-set pivot
	                           obvious at a glance in the Properties pane.

	WHAT THE BUCKETS ARE FOR. Nothing in the game reads the child names; they exist so a human can
	find things, and so every tile in every world reads the same way. The classifier below sorts a
	raw tile's children into the default map's five:

	    RoadSurface   the deck, its aprons, and the verge terrain either side of it
	    LaneLines     the paint on the deck
	    Guardrails    the rail line, which is real collidable geometry and the thing that actually
	                  keeps the car on the road
	    Buildings     the big masses that make the skyline — city blocks, mountains, tunnels
	    Props         everything scattered on top: trees, rocks, poles, cables, signs, neon

	plus `Gameplay`, which is not art at all: the OriginMarker and the two invisible walls that
	back up the guardrails.

	HOW THE CLASSIFIER KNOWS. Every world here was built on the same base road kit — the same deck
	slabs, the same aprons, the same verge rocks, down to identical part sizes — and then dressed
	differently. So the kit is harvested from the default map's own `RoadSurface` as a set of part
	SIZES, and anything matching it is road. What is left is dressing, and gets sorted by name
	first (the modeller named things well: `Snowpile`, `Cactus`, `Mountain`) and by silhouette
	second. Name rules beat geometry rules on purpose — a mountain is a mountain even when it
	happens to be the size of a building.
]]

local CollectionService = game:GetService("CollectionService")

local Segment = {}

-- Every tile in every world measures exactly this along Z (verified: all 22 authored tiles carry
-- a deck slab of this length). It is the tiling offset, so it is a constant of the road, not a
-- per-tile measurement — but each tile is still checked against it and complains if it differs.
Segment.SEGMENT_LENGTH = 1172.796142578125
Segment.FORWARD_AXIS = "Z"
Segment.TAG = "WorldRoadSegment"

-- Buckets, in the order they should appear under the tile.
Segment.BUCKETS = { "Gameplay", "RoadSurface", "LaneLines", "Guardrails", "Buildings", "Props" }

-- The invisible backstop walls, copied off the default map: 1 stud thick, 60 tall, standing on the
-- deck this far outboard of the nominal rail line. CanQuery is FALSE on them for a reason — the
-- guardrail-scrape sensor overlaps the whole tile, and a query-able wall would report a scrape
-- from a stud outside the rail the car never touched.
Segment.WALL_HEIGHT = 60
Segment.WALL_THICKNESS = 1
Segment.WALL_OUTBOARD = 2.02

-- Corridor sanity bound. Guardrail models also appear on bridges and overpasses well off to the
-- side (City/3, FuturisticCity/3-4), and those must not widen the corridor — nothing here is
-- anywhere near 60 studs from the centre line.
local CORRIDOR_LIMIT = 60

-- Named dressing. Matched case-insensitively as substrings, so `Boulder3`, `SnowBarrier` and
-- `BuildingConstruction2` all land where they should (note the last one is scaffolding, i.e. a
-- prop, and is caught here BEFORE the "building" mass rule below).
local DRESSING = {
	"snowpile", "icewall", "snowbarrier", "trunk", "ice", "tree", "boulder", "cactus",
	"rock", "sanddune", "ball", "water", "tornado", "signneon", "gravity", "laser",
	"holo", "portal", "cone", "barrier", "plank", "brick", "police", "tape", "jersey",
	"pole", "cable", "sign", "light", "buildingconstruction", "pad", "mine", "energymine",
}
local MASS = { "mountain", "tunnel", "bridge", "building" }

local function hasWord(name: string, list: { string }): boolean
	local lower = string.lower(name)
	for _, key in list do
		if string.find(lower, key, 1, true) then
			return true
		end
	end
	return false
end

local function sizeSignature(part: BasePart): string
	return string.format("%.1f|%.1f|%.1f", part.Size.X, part.Size.Y, part.Size.Z)
end

local function partsOf(inst: Instance): { BasePart }
	local parts = {}
	if inst:IsA("BasePart") then
		table.insert(parts, inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

-- World-space extents, corner-accurate so a rotated part counts for what it actually occupies
-- (the long centre line is a 1170-stud part turned 90 degrees — take its Size at face value and
-- it looks like it crosses the road rather than running down it).
local function extentsOf(parts: { BasePart })
	local mn, mx
	for _, p in parts do
		local half = p.Size * 0.5
		for i = 0, 7 do
			local corner = p.CFrame * Vector3.new(
				if i % 2 == 0 then -half.X else half.X,
				if math.floor(i / 2) % 2 == 0 then -half.Y else half.Y,
				if math.floor(i / 4) % 2 == 0 then -half.Z else half.Z
			)
			if not mn then
				mn, mx = corner, corner
			else
				mn = Vector3.new(math.min(mn.X, corner.X), math.min(mn.Y, corner.Y), math.min(mn.Z, corner.Z))
				mx = Vector3.new(math.max(mx.X, corner.X), math.max(mx.Y, corner.Y), math.max(mx.Z, corner.Z))
			end
		end
	end
	return mn, mx
end

--[[ The tile's own frame, measured off its geometry rather than trusted from an attribute.

	The deck is found by length: a slab exactly `SEGMENT_LENGTH` long can only be the deck, and the
	WIDEST such slab is the driving surface (the narrower ones beside it are raised shoulders whose
	tops sit most of a stud higher — take those for the deck and every car spawns buried).

	The corridor comes off the guardrails, not the deck, because they are what the car is actually
	contained by; the two centres differ by up to a stud. ]]
function Segment.frameOf(tile: Model)
	local slabs = {}
	for _, d in tile:GetDescendants() do
		if d:IsA("BasePart") and math.abs(d.Size.Z - Segment.SEGMENT_LENGTH) < 1 and d.Size.X > 20 then
			table.insert(slabs, d)
		end
	end
	if #slabs == 0 then
		return nil, "no deck slab (no part is one segment long)"
	end

	local widest = slabs[1]
	for _, s in slabs do
		if s.Size.X > widest.Size.X then
			widest = s
		end
	end
	-- The deck can be one wide slab (City, FuturisticCity) or three strips side by side
	-- (Arctic, Desert, Forest Mountains) — same width each, so match on width and take the span.
	local minX, maxX = math.huge, -math.huge
	local alongs, tops = {}, {}
	for _, s in slabs do
		if math.abs(s.Size.X - widest.Size.X) < 0.5 then
			minX = math.min(minX, s.Position.X - s.Size.X / 2)
			maxX = math.max(maxX, s.Position.X + s.Size.X / 2)
			table.insert(alongs, s.Position.Z)
			table.insert(tops, s.Position.Y + s.Size.Y / 2)
		end
	end
	--[[ MEDIAN, not "whichever slab came back first". The three strips are not laid perfectly
		square — in Forest Mountains the western one sits a fifth of a stud further down the road
		than its neighbours — and the strip this lands on decides where the whole tile's pivot goes.
		Pick by iteration order and two variants of the same world can disagree by that fifth of a
		stud, which is a visible jog in the road at the seam between them. The median always lands
		on the alignment the majority of the deck agrees with. ]]
	table.sort(alongs)
	table.sort(tops)
	local deckTop = tops[math.ceil(#tops / 2)]
	local deckCentreX = (minX + maxX) / 2
	local entryZ = alongs[math.ceil(#alongs / 2)] - Segment.SEGMENT_LENGTH / 2

	local railMin, railMax = math.huge, -math.huge
	for _, d in tile:GetDescendants() do
		if d:IsA("Model") and hasWord(d.Name, { "guardrail" }) then
			for _, p in partsOf(d) do
				if math.abs(p.Position.X - deckCentreX) <= CORRIDOR_LIMIT then
					railMin = math.min(railMin, p.Position.X)
					railMax = math.max(railMax, p.Position.X)
				end
			end
		end
	end
	local haveRails = railMin < railMax

	return {
		deckTop = deckTop,
		deckCentreX = deckCentreX,
		entryZ = entryZ,
		exitZ = entryZ + Segment.SEGMENT_LENGTH,
		driveCenterX = if haveRails then (railMin + railMax) / 2 else deckCentreX,
		driveWidth = if haveRails then railMax - railMin else nil,
	}
end

-- Part sizes that make up the shared base road kit, harvested from a reference tile's RoadSurface.
function Segment.harvestKit(reference: Model): { [string]: boolean }
	local kit = {}
	local surface = reference:FindFirstChild("RoadSurface")
	for _, p in partsOf(surface or reference) do
		kit[sizeSignature(p)] = true
	end
	return kit
end

-- Which bucket one direct child of a tile belongs in.
function Segment.classify(child: Instance, frame, kit: { [string]: boolean }): string
	local parts = partsOf(child)
	if #parts == 0 then
		return "Props"
	end

	if hasWord(child.Name, { "guardrail" }) then
		return "Guardrails"
	end
	if hasWord(child.Name, DRESSING) then
		return "Props"
	end
	if hasWord(child.Name, MASS) then
		return "Buildings"
	end

	-- Anything a full tile long is either the deck or the line painted down the middle of it.
	for _, p in parts do
		local full = math.abs(p.Size.Z - Segment.SEGMENT_LENGTH) < 2 or math.abs(p.Size.X - Segment.SEGMENT_LENGTH) < 3
		if full then
			local painted = p.Size.Y <= 1.4 and math.min(p.Size.X, p.Size.Z) <= 8
			return if painted then "LaneLines" else "RoadSurface"
		end
	end

	-- Paint: thin, flat, lying on the deck, and narrow in one direction (the dashes).
	local allPaint = true
	for _, p in parts do
		local top = p.Position.Y + p.Size.Y / 2
		if not (p.Size.Y <= 1.4 and top <= frame.deckTop + 0.6 and math.min(p.Size.X, p.Size.Z) <= 3.5) then
			allPaint = false
			break
		end
	end
	if allPaint then
		return "LaneLines"
	end

	-- The base kit: deck aprons and the verge terrain, identical part-for-part across worlds.
	local kitHits = 0
	for _, p in parts do
		if kit[sizeSignature(p)] then
			kitHits += 1
		end
	end
	if kitHits / #parts >= 0.8 then
		return "RoadSurface"
	end

	-- Aprons the kit match missed. A slab lying flat at deck height is paving whatever size it
	-- happens to be; the ceiling is a stud above the deck so the neon strips inlaid in
	-- FuturisticCity's pavement (1.5 up, and each carrying a SurfaceLight) stay with the lights.
	local allPaving = true
	for _, p in parts do
		local top = p.Position.Y + p.Size.Y / 2
		if not (p.Size.Y <= 2 and top <= frame.deckTop + 1 and top >= frame.deckTop - 3) then
			allPaving = false
			break
		end
	end
	if allPaving then
		return "RoadSurface"
	end

	--[[ The verge. Every world flanks the road with the same cliff-and-bank terrain, but the
		modeller resized pieces to fit, so a good third of it misses the kit's exact sizes. What it
		can't miss is the shape of the job: it stands outside the corridor and it comes UP OUT OF
		THE GROUND. Buildings do not — the city blocks are stacked models whose lowest part starts
		twenty studs above the deck — so this catches the terrain and leaves the skyline alone. ]]
	local halfCorridor = (frame.driveWidth or 73) / 2 + 5
	local mn, mx = extentsOf(parts)
	local outsideCorridor = mn.X > frame.driveCenterX + halfCorridor or mx.X < frame.driveCenterX - halfCorridor
	local rooted = mn.Y <= frame.deckTop + 2 -- grows out of the ground rather than floating over it
	if outsideCorridor and rooted and mx.Y - mn.Y <= 50 then
		return "RoadSurface"
	end

	-- Left over: call it skyline if it is genuinely big and tall, otherwise it is scatter.
	if mx.Y - mn.Y >= 25 and mx.Y >= frame.deckTop + 30 then
		return "Buildings"
	end
	return "Props"
end

--[[ Work out what normalising a tile would do, without doing any of it. Returns a plan the caller
	can print (dry run) or hand straight to `Segment.apply`.

	`overrides` lets the caller impose one drive frame on a whole world — every tile in a world has
	to agree on the corridor or they are not interchangeable, so the command measures them all,
	takes the consensus, and passes it back down here. ]]
function Segment.plan(tile: Model, kit: { [string]: boolean }, overrides: { [string]: number }?)
	local frame, why = Segment.frameOf(tile)
	if not frame then
		return nil, why
	end
	if overrides then
		for key, value in overrides do
			frame[key] = value
		end
	end

	local moves, counts, issues = {}, {}, {}
	for _, child in tile:GetChildren() do
		-- Already-normalised tiles keep their buckets; only loose children get sorted.
		if table.find(Segment.BUCKETS, child.Name) then
			continue
		end
		local bucket = Segment.classify(child, frame, kit)
		table.insert(moves, { child = child, bucket = bucket })
		counts[bucket] = (counts[bucket] or 0) + 1
	end

	local unanchored = 0
	for _, p in partsOf(tile) do
		if not p.Anchored then
			unanchored += 1
		end
	end
	if unanchored > 0 then
		table.insert(issues, string.format("%d unanchored part(s) — they would fall out of a streamed tile", unanchored))
	end
	if not frame.driveWidth then
		table.insert(issues, "no guardrails found; corridor fell back to the deck centre")
	end
	if tile:FindFirstChild("Obstacles") then
		table.insert(issues, "a child named 'Obstacles' clashes with the runtime obstacle folder")
	end

	return {
		frame = frame,
		moves = moves,
		counts = counts,
		issues = issues,
		unanchored = unanchored,
	}
end

local function ensureBucket(tile: Model, name: string): Instance
	local existing = tile:FindFirstChild(name)
	if existing then
		return existing
	end
	local container = if name == "Gameplay" then Instance.new("Folder") else Instance.new("Model")
	container.Name = name
	container.Parent = tile
	return container
end

local function ensurePart(parent: Instance, name: string): BasePart
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("BasePart") then
		return existing
	end
	local part = Instance.new("Part")
	part.Name = name
	part.Parent = parent
	return part
end

-- "Boulder3" and "Boulder1" are the same thing twice; "Cables" is already its own family name.
local function familyOf(name: string): string
	local base = string.gsub(name, "%d+$", "")
	base = string.match(base, "^%s*(.-)%s*$") or base
	return if base == "" then name else base
end

--[[ Second pass inside a bucket, so 77 loose `Tree`s read as one `Trees` and not as a wall of
	Explorer rows. Only Props gets this: the default map groups its scatter (`Poles`, `Cables`) and
	leaves the other buckets flat, and grouping `Guardrails` would just nest a Guardrails inside a
	Guardrails. Idempotent — a family whose group already exists is moved into the existing one. ]]
local function groupProps(bucket: Instance)
	local families: { [string]: { Instance } } = {}
	for _, child in bucket:GetChildren() do
		local family = familyOf(child.Name)
		families[family] = families[family] or {}
		table.insert(families[family], child)
	end
	for family, members in families do
		if #members < 4 then
			continue
		end
		local groupName = family
		if string.sub(family, -1) == "y" and not string.find("aeiou", string.sub(family, -2, -2)) then
			groupName = string.sub(family, 1, -2) .. "ies"
		elseif string.sub(family, -1) ~= "s" then
			groupName = family .. "s"
		end
		local group = bucket:FindFirstChild(groupName)
		if not (group and group:IsA("Model")) then
			group = Instance.new("Model")
			group.Name = groupName
			group.Parent = bucket
		end
		for _, member in members do
			if member ~= group then
				member.Parent = group
			end
		end
	end
end

local function ensureGroup(parent: Instance, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Model") then
		return existing
	end
	local group = Instance.new("Model")
	group.Name = name
	group.Parent = parent
	return group
end

--[[ The default map splits its city blocks into `East` and `West`, which is worth keeping: it is
	the one bucket where "which side of the road" is the only question anyone asks of it. Anything
	that straddles the road — a tunnel, an overpass — belongs to neither and is left at the top of
	the bucket where it reads as the exception it is. ]]
local function splitBuildings(bucket: Instance, frame)
	local children = bucket:GetChildren()
	if #children < 8 then
		return
	end
	local half = (frame.driveWidth or 73) / 2
	local sides = {}
	for _, child in children do
		if child.Name == "East" or child.Name == "West" then
			continue
		end
		local mn, mx = extentsOf(partsOf(child))
		if mn then
			local centre = (mn.X + mx.X) / 2
			if math.abs(centre - frame.driveCenterX) > half then
				sides[child] = if centre > frame.driveCenterX then "East" else "West"
			end
		end
	end
	for child, side in sides do
		child.Parent = ensureGroup(bucket, side)
	end
end

--[[ The verge — the cliffs and banks that run either side of the road — is road, but it is also
	most of the parts in a tile, and in the worlds whose verge came in as loose parts (Forest
	Mountains: 130 of them) it buries the deck it is supposed to be flanking. One `Verge` group
	puts the deck back at the top of the bucket where you can find it.

	Runs over the bucket's whole contents, not just what this pass moved, so it is idempotent and
	still tidies a tile that was sorted by hand. ]]
local function groupVerge(bucket: Instance, frame)
	local half = (frame.driveWidth or 73) / 2 + 5
	local moving = {}
	for _, child in bucket:GetChildren() do
		if child.Name == "Verge" then
			continue
		end
		local parts = partsOf(child)
		local isDeck = false
		for _, p in parts do
			if math.abs(p.Size.Z - Segment.SEGMENT_LENGTH) < 2 then
				isDeck = true
				break
			end
		end
		if isDeck then
			continue
		end
		local mn, mx = extentsOf(parts)
		if not mn then
			continue
		end
		local outside = mn.X > frame.driveCenterX + half or mx.X < frame.driveCenterX - half
		if outside and mn.Y <= frame.deckTop + 2 and mx.Y - mn.Y <= 50 then
			table.insert(moving, child)
		end
	end
	if #moving < 4 then
		return
	end
	local verge = ensureGroup(bucket, "Verge")
	for _, child in moving do
		child.Parent = verge
	end
end

-- Paint reads as `Dashes` and `Line` rather than as thirty parts called Part.
local function tidyLaneLines(bucket: Instance)
	--[[ PAINT IS NOT GEOMETRY. Lane lines are authored as 1.31-stud-tall slabs sunk into the deck,
		standing 0.31 proud of it, and every world's tiles arrived with them CanCollide — a kerb
		down every lane boundary of every world. The reference tile (Workspace.RoadSegments) had
		been switched off by hand at some point and this pass, which only ever SORTED and RENAMED,
		never carried that to the 21 imported tiles. So the one tile anybody would check against
		read correct while the tiles players actually race on did not.

		Owned here rather than fixed on the tiles alone, because an import is the moment it comes
		back: the modeller's files still carry it. ]]
	for _, d in bucket:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end

	local dashes = {}
	for _, child in bucket:GetChildren() do
		if child.Name == "Dashes" then
			continue
		end
		local parts = partsOf(child)
		local full = false
		for _, p in parts do
			if math.abs(p.Size.X - Segment.SEGMENT_LENGTH) < 3 or math.abs(p.Size.Z - Segment.SEGMENT_LENGTH) < 3 then
				full = true
				break
			end
		end
		if child:IsA("BasePart") then
			child.Name = if full then "Line" else "Dash"
			if not full then
				table.insert(dashes, child)
			end
		elseif #parts >= 4 and not full then
			child.Name = "Dashes"
		end
	end
	if #dashes >= 4 then
		local group = ensureGroup(bucket, "Dashes")
		for _, dash in dashes do
			dash.Parent = group
		end
	end
end

-- Apply a plan: sort the children, build the Gameplay parts, set the pivot and the contract.
function Segment.apply(tile: Model, plan, world: string?, variant: number?)
	local frame = plan.frame

	for _, move in plan.moves do
		move.child.Parent = ensureBucket(tile, move.bucket)
	end

	local props = tile:FindFirstChild("Props")
	if props then
		groupProps(props)
	end
	local buildings = tile:FindFirstChild("Buildings")
	if buildings then
		splitBuildings(buildings, frame)
	end
	local surface = tile:FindFirstChild("RoadSurface")
	if surface then
		groupVerge(surface, frame)
	end
	local lanes = tile:FindFirstChild("LaneLines")
	if lanes then
		tidyLaneLines(lanes)
	end

	local gameplay = ensureBucket(tile, "Gameplay")

	local marker = ensurePart(gameplay, "OriginMarker")
	marker.Size = Vector3.one * 2
	marker.Anchored = true
	marker.Transparency = 1
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.CastShadow = false
	marker.CFrame = CFrame.new(frame.deckCentreX, frame.deckTop, frame.entryZ)
	tile.PrimaryPart = marker

	local halfWidth = (frame.driveWidth or 73) / 2 + Segment.WALL_OUTBOARD
	for _, side in { { name = "WallEast", dir = 1 }, { name = "WallWest", dir = -1 } } do
		local wall = ensurePart(gameplay, side.name)
		wall.Size = Vector3.new(Segment.WALL_THICKNESS, Segment.WALL_HEIGHT, Segment.SEGMENT_LENGTH)
		wall.Anchored = true
		wall.Transparency = 1
		wall.CanCollide = true
		wall.CanQuery = false
		wall.CanTouch = true
		wall.CastShadow = false
		wall.CFrame = CFrame.new(
			frame.driveCenterX + side.dir * halfWidth,
			frame.deckTop + Segment.WALL_HEIGHT / 2,
			frame.entryZ + Segment.SEGMENT_LENGTH / 2
		)
		-- Nothing reads this; the default map's walls carry it, so these do too. It is the one
		-- thing that tells a person poking at an invisible part what it is for.
		wall:SetAttribute("IsBoundary", true)
	end

	-- Anything loose would fall the moment a tile is cloned into a race.
	for _, p in partsOf(tile) do
		if not p.Anchored then
			p.Anchored = true
		end
	end

	-- The deck comes out of the import unnamed in some worlds and called `Part` in the rest, which
	-- makes the one part of a tile everything else is measured from the hardest thing in it to
	-- find. Anything a full tile long and wide enough to drive on is the deck, and says so.
	for _, p in partsOf(tile) do
		if math.abs(p.Size.Z - Segment.SEGMENT_LENGTH) < 1 and p.Size.X > 20 then
			p.Name = "Deck"
		elseif p.Name == "" then
			p.Name = "Part"
		end
	end

	tile:SetAttribute("SegmentLength", Segment.SEGMENT_LENGTH)
	tile:SetAttribute("ForwardAxis", Segment.FORWARD_AXIS)
	tile:SetAttribute("DriveCenterX", frame.driveCenterX)
	tile:SetAttribute("DriveCenterOffset", frame.driveCenterX - frame.deckCentreX)
	tile:SetAttribute("DriveWidth", frame.driveWidth)
	tile:SetAttribute("EntryZ", frame.entryZ)
	tile:SetAttribute("ExitZ", frame.exitZ)
	if world then
		tile:SetAttribute("World", world)
	end
	if variant then
		tile:SetAttribute("Variant", variant)
	end

	CollectionService:AddTag(tile, Segment.TAG)
end

return Segment
