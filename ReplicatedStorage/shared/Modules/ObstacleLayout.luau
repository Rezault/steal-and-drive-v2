--[[
	ObstacleLayout  (shared, pure)
	------------------------------
	The single source of truth for "what obstacles are on road tile N of this race".

	A race gets one integer seed. `forTile(seed, tileIndex, segmentLength)` turns that seed
	plus a tile index into the exact obstacle list for that tile — same inputs, same output,
	on every machine. That's the whole trick behind this layer:

	  • the CLIENT calls it to build the geometry into its own local road tile, and
	  • the SERVER calls it to check that a reported hit corresponds to an obstacle that
	    really exists at a lane the car could plausibly have been in,

	so obstacles are never replicated, never network-owned, and never cost a byte to move.
	(The road is client-sided for the same reason — see RoadController.)

	Determinism rules if you edit this file:
	  • Only ever draw randomness from the passed-in `Random` object, in a fixed order.
	    Any `math.random`, `os.clock`, or player state here desynchronises the two sides.
	  • Only use bit32 ops / small integer multiplies in the seed mix — a product past
	    2^53 silently loses low bits, which is where "works in Studio, not in game" lives.

	Obstacle ids: `tileIndex * IdsPerTile + n`. One number identifies an obstacle for the
	whole race (tile indices only ever increase, so ids are never reused), and the server
	can recover the tile from the id alone — no lookup table to keep in sync.

	THE LAYOUT IS PER MAP as well as per seed. Each world's road has its own obstacle set —
	the city has cones and barricades, the desert has cacti and boulders — and which set a
	tile is built from is decided by the `map` argument every entry point takes
	(`WorldConfig.mapFor` of the race's world). Nil means world 1's, which is what an older
	caller and a race started without a world both get.

	That argument is part of the determinism contract, not a convenience: the client passes
	the map it was handed with RaceStart and the server passes the map of the world it
	recorded at `beginRace`, so the two sides derive the same list. Add a call site and it
	has to pass one too, or that side will silently price a desert run against city
	obstacles.

	THE BENCH IS A FIFTH ARGUMENT OF EXACTLY THAT KIND. An admin can ask for one hazard, laid at a
	fixed distance and repeated, instead of the seeded ramp; it travels the same way the map does
	and it has to be passed the same way, or the server will price a benched run against a road the
	player never drove. See "THE BENCH" below.

	THE RAIN'S PUDDLES ARE HERE BUT NOT IN `forTile`, and that is the one exception to "both sides
	derive the same list". `puddlesFor` is a pass the CLIENT runs over a tile when it is raining on it,
	and the server never calls it; see "THE WEATHER'S PASS" below and `ObstacleConfig.Puddles`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ObstacleConfig = require(ReplicatedStorage.shared.Configs.ObstacleConfig)
local PickupConfig = require(ReplicatedStorage.shared.Configs.PickupConfig)
--- For `weatherKinds` alone: which kinds an event can lay. A leaf config (it requires `UIAssets` and
--- nothing gameplay-shaped), so it cannot cycle back through here.
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)

local ObstacleLayout = {}

-- Hard ceiling on obstacles per tile. Also the id stride, so don't shrink it below what
-- the busiest tier can emit (~25 today) or ids from neighbouring tiles would collide.
ObstacleLayout.IdsPerTile = 64

--[[ How many ids at the TOP of each tile's band are reserved for pickups.

	Obstacles number UP from 0 and pickups number DOWN from `IdsPerTile - 1`, so the two only meet
	if a tile emits more than `IdsPerTile - PickupIds` obstacles. The busiest tier emits about 25
	against a 60-id floor, and the obstacle loop caps itself at `IdsPerTile` anyway — but the whole
	point of an id is that it identifies ONE thing for the length of a race, so this is enforced
	rather than assumed: `_placePickups` refuses to place a pack on an id an obstacle already took.

	Reserving from the top rather than widening the stride is what keeps every id a run has ever
	issued meaning exactly what it meant before this feature existed. A wider stride would renumber
	the lot. ]]
local PickupIds = 4

--[[ Salt for the pickup pass's own RNG, so it draws from a stream the obstacle pass cannot move.

	Without it the pass would have to share `rng` and read it after the course loop, which makes
	pack placement a function of how many courses happened to fit — so retuning a single course
	length would silently reshuffle every pack in the game, and an existing seed would stop
	describing the road it used to. Salted, the two layers are independent: `PickupConfig.Spawn` and
	`ObstacleConfig.Tiers` can each be retuned without touching the other's output.

	A bit32 xor of the tile seed, which keeps it inside the 32-bit discipline the header demands. ]]
local PickupSalt = 0x5A17F00D

export type Obstacle = {
	id: number,
	kind: string,
	lane: number, -- index into ObstacleConfig.Lanes
	laneOffset: number, -- studs from the road's drive centre, on the cross axis (lane + Nudge)
	along: number, -- studs from the tile's own pivot, along the forward axis
	course: string, -- which named course placed it (debugging / future scoring)
	yaw: number?, -- degrees the art is turned on the deck; only the weather's pass sets it
	scale: number?, -- size factor on the art and the hit footprint; ditto
}

-- Which tile an obstacle id belongs to. Works for the negative tiles behind the spawn too.
function ObstacleLayout.tileIndexOfId(id: number): number
	return math.floor(id / ObstacleLayout.IdsPerTile)
end

-- Decorrelate (seed, tileIndex) into a tile seed. Kept inside 32 bits the whole way:
-- tileIndex * 374761393 stays exact for any tile index we could ever reach, and every
-- other step is a bit32 op, so client and server land on the same number bit for bit.
local function tileSeed(seed: number, tileIndex: number): number
	local h = bit32.bxor(seed, tileIndex * 374761393 % 4294967296)
	h = bit32.bxor(h, bit32.rshift(h, 15))
	h = bit32.bxor(h, bit32.lshift(h, 7))
	h = bit32.bxor(h, bit32.rshift(h, 11))
	return h
end

--[[ The difficulty ramp for one map, falling back to world 1's for any map that doesn't
	name its own (ObstacleConfig.TiersByMap). Public because ObstacleService walks it to work
	out which props a map actually needs published. ]]
function ObstacleLayout.tiersFor(map: string?)
	return (map and ObstacleConfig.TiersByMap[map]) or ObstacleConfig.Tiers
end

--[[ Every obstacle kind a map can ever place, as a set. Derived from the ramp rather than
	declared, so a kind is "used by the desert" exactly when a desert course names it and there
	is no second list to keep in step. ]]
function ObstacleLayout.kindsFor(map: string?): { [string]: boolean }
	local kinds = {}
	for _, tier in ObstacleLayout.tiersFor(map) do
		for _, name in tier.Pool do
			local course = ObstacleConfig.Courses[name]
			if course then
				for _, item in course.Items do
					kinds[item.Kind] = true
				end
			end
		end
	end
	return kinds
end

--[[ Is this kind a pickup rather than a hazard? One lookup, in one place, because four callers ask
	it and three of them are on the far side of a network boundary from this file: the client's
	build, the server's hit handler and `ObstacleService.clearedFor`'s dodge count all have to agree
	about which entries in a tile's list are rewards.

	`clearedFor` is the one that would go wrong silently. It counts obstacles passed minus obstacles
	hit, and a pack sitting unclaimed on the road would otherwise count as an obstacle you dodged —
	so a player would be paid for driving past a health pack. ]]
function ObstacleLayout.isPickup(kindName: unknown): boolean
	local kind = type(kindName) == "string" and ObstacleConfig.Kinds[kindName]
	return kind ~= nil and kind.Pickup ~= nil
end

--[[ The pickup pass: the second, independent placement over a tile that has already had its
	obstacle courses laid. `PickupConfig`'s header has the whole argument for why this is a pass and
	not a course in the tier pools; the short version is that a pass reaches every map for free, has
	its own density dial, and cannot destabilise a single obstacle.

	`items` is the tile's obstacle list, complete, and is appended to in place. `taken` is how many
	ids the obstacle loop used, so a pack can never be given one of them.

	DETERMINISM: every draw comes from `rng`, in a fixed order, and the reject-retry loop below is a
	function of `items` alone — which both sides derived identically before this ran. So the retries
	are not a source of divergence even though how MANY of them happen varies by tile. ]]
local function placePickups(items, seed: number, tileIndex: number, segmentLength: number, taken: number)
	if not PickupConfig.Enabled then
		return
	end

	local rng = Random.new(bit32.bxor(tileSeed(seed, tileIndex), PickupSalt))
	local spawn = PickupConfig.Spawn

	--[[ How many packs this tile gets, decided BEFORE any placement is attempted. Both draws happen
		unconditionally so the RNG advances by the same amount on every tile regardless of the
		outcome — a stream whose position depends on its own results is one that is very easy to
		desynchronise later by adding an early return. ]]
	local firstRoll, secondRoll = rng:NextNumber(), rng:NextNumber()
	local want = 0
	if firstRoll < spawn.ChancePerTile then
		want = 1
		if secondRoll < spawn.ChanceOfSecond then
			want = 2
		end
	end
	want = math.min(want, spawn.MaxPerTile, PickupIds)

	--[[ The band a pack may sit in. Wider margins than the obstacle course's own, because a pack is
		something you have to SPOT, decide about and steer to, where a cone only has to be missed.
		A tile too short to hold the band gets no packs rather than a squeezed one. ]]
	local from = spawn.LeadIn
	local to = segmentLength - spawn.TailOut
	--- Tile 0 starts the player at its MIDDLE, so a pack behind the spawn is one nobody can reach.
	--- Same correction the obstacle loop makes, and for the same reason.
	if tileIndex == 0 then
		from = math.max(from, segmentLength * 0.5 + ObstacleConfig.SpawnGraceStuds)
	end
	if to <= from then
		return
	end

	for n = 1, want do
		--[[ Numbered DOWN from the top of the tile's id band while obstacles number up, so the two
			cannot collide — see `PickupIds`. Guarded anyway rather than trusted: an id issued twice
			is an obstacle and a pack that consume each other's hit, which is the kind of bug that
			only shows up on the one tile in a thousand that is full. ]]
		local slot = ObstacleLayout.IdsPerTile - n
		if slot < taken then
			break
		end

		--[[ Draw a position, then reject it if it lands on top of an obstacle, up to `Attempts`
			times.

			HOW MANY ATTEMPTS A TILE TAKES VARIES, and that is not a determinism problem: both sides
			run this loop over an `items` list they derived identically a moment ago, from a stream
			seeded identically, so they reject and accept the same candidates in the same order and
			leave the RNG in the same place. What would break it is drawing from anything that is
			not `rng` — see the file header. ]]
		local placed = nil
		for _ = 1, spawn.Attempts do
			local laneIndex = spawn.Lanes[rng:NextInteger(1, #spawn.Lanes)]
			local along = rng:NextNumber(from, to)
			local name = PickupConfig.draw(rng)
			local laneOffset = ObstacleConfig.Lanes[laneIndex]
			if not laneOffset then
				continue
			end

			local clear = true
			for _, other in items do
				if
					math.abs(other.along - along) < spawn.ClearAlong
					and math.abs(other.laneOffset - laneOffset) < spawn.ClearCross
				then
					clear = false
					break
				end
			end
			if clear then
				placed = {
					id = tileIndex * ObstacleLayout.IdsPerTile + slot,
					-- The kind is named for the pack because that is what ties the two files
					-- together: `ObstacleConfig.Kinds[kind].Pickup` is the pack's name in
					-- `PickupConfig.Packs`, and every consumer resolves it that way.
					kind = name .. "Pack",
					lane = laneIndex,
					laneOffset = laneOffset,
					along = along,
					-- Not a course. Named so anything debugging a tile's list can tell at a glance
					-- which pass put an entry there, without resolving the kind.
					course = "pickup",
				}
				break
			end
		end

		if not placed then
			-- A tile packed wall to wall with obstacles has no honest room for a reward on it. The
			-- right failure is no pack, not a pack buried in a barricade.
			break
		end
		table.insert(items, placed)
	end
end

--[[ === THE BENCH ============================================================================

	One kind (or one authored course), laid at a fixed distance and repeated forever, with
	nothing else on the tile. `ObstacleConfig.Bench` has the argument for why it exists and what
	the numbers mean; what lives here is the layout it produces, because a bench is not a second
	road but the same `forTile` answering a different question.

	IT DRAWS NO RANDOMNESS AT ALL, which is what makes it safe next to everything above: the tile
	seed is never touched, so nothing about an ordinary race is moved by this existing, and the
	two sides agree because arithmetic on the same numbers agrees. The pickup pass is skipped for
	the same reason the tier ramp is: the bench is "this hazard and nothing else", and a health
	pack sitting beside the thing under test is something else.

	The spec crosses two boundaries before it gets here (the panel to `AdminService`, then
	`RaceStart` to the client), so `sanitizeBench` is what every call site runs it through: it
	answers nil for anything that does not name a real kind or course, and clamps the rest.
	Nothing else in this file trusts a field on it. ]]

export type Bench = {
	kind: string?, -- one kind, in `lane` (or in every lane, with `row`)
	course: string?, -- ...or one whole course from `ObstacleConfig.Courses`, laid as authored
	lane: number, -- index into ObstacleConfig.Lanes; ignored by a course, which names its own
	row: boolean, -- one in every lane instead of one in `lane`
	lead: number, -- studs of clear road between the spawn and the first one
	spacing: number, -- studs between repeats
	invuln: boolean, -- read by ObstacleService: HP does not move for this run
	traffic: boolean, -- read by TrafficController: whether the road still populates
}

local function clampTo(value: unknown, range: { number }, fallback: number): number
	if type(value) ~= "number" or value ~= value then
		return fallback
	end
	return math.clamp(value, range[1], range[2])
end

--[[ Read a bench spec off the wire, or nil for "no bench, drive the real ramp".

	The two BOOLEANS fall back to false rather than to their `ObstacleConfig.Bench` value, and
	that is not the same kind of default as the numbers above them: the config's booleans are what
	the tab's checkboxes start ON, and the wire then always carries what the checkbox actually
	says. A missing one here is a malformed spec, and false is the direction that leaves the run
	behaving like a real one. ]]
function ObstacleLayout.sanitizeBench(spec: unknown): Bench?
	if type(spec) ~= "table" then
		return nil
	end
	local defaults = ObstacleConfig.Bench
	local kind = if type(spec.kind) == "string" and ObstacleConfig.Kinds[spec.kind] then spec.kind else nil
	local course = if type(spec.course) == "string" and ObstacleConfig.Courses[spec.course] then spec.course else nil
	if not (kind or course) then
		return nil -- names nothing this build has; there is no honest bench to build
	end

	return {
		--- A course wins if both arrive somehow. A course names its own kinds and its own lanes,
		--- so a kind beside it would be a second answer to a question that already has one.
		kind = if course then nil else kind,
		course = course,
		lane = math.floor(clampTo(spec.lane, { 1, #ObstacleConfig.Lanes }, defaults.Lane) + 0.5),
		row = spec.row == true,
		lead = clampTo(spec.lead, defaults.LeadRange, defaults.Lead),
		spacing = clampTo(spec.spacing, defaults.SpacingRange, defaults.Spacing),
		invuln = spec.invuln == true,
		traffic = spec.traffic == true,
	}
end

--[[ What one repeat of the bench puts on the road, in the tile-local shape `forTile` emits: one
	entry per obstacle, with `along` measured from the repeat's own point.

	A course keeps its authored lanes, nudges and spacing, so benching `boomGate` is the gate as
	the ramp would have dealt it rather than an approximation of it. ]]
local function benchPattern(bench: Bench)
	local entries = {}
	if bench.course then
		local course = ObstacleConfig.Courses[bench.course]
		if not course then
			return entries
		end
		for _, item in course.Items do
			local laneOffset = ObstacleConfig.Lanes[item.Lane]
			if laneOffset then
				-- The same fold the tier path does, and it has to be the same one: `laneOffset` is
				-- the single number the client build, the server's lane check and traffic avoidance
				-- all read (see `forTile`).
				table.insert(entries, {
					kind = item.Kind,
					lane = item.Lane,
					laneOffset = laneOffset + (item.Nudge or 0),
					along = item.Along,
				})
			end
		end
		return entries
	end

	local kind = bench.kind
	if not kind then
		return entries
	end
	if bench.row then
		for lane, laneOffset in ObstacleConfig.Lanes do
			table.insert(entries, { kind = kind, lane = lane, laneOffset = laneOffset, along = 0 })
		end
	else
		local laneOffset = ObstacleConfig.Lanes[bench.lane]
		if laneOffset then
			table.insert(entries, { kind = kind, lane = bench.lane, laneOffset = laneOffset, along = 0 })
		end
	end
	return entries
end

--[[ The bench's answer for one tile.

	Repeats are numbered from the SPAWN and not from the tile, which is what keeps the spacing even
	across a tile seam: a repeat sits at `half a tile + lead + k * spacing` down the whole road, and
	this walks the k's whose items could land inside this tile and keeps the ones that do. A course
	that runs over a seam is therefore split between two tiles rather than dropped, which is the
	opposite of what the tier path does and is right for the opposite reason: there is no recycling
	story to protect here, only a thing somebody asked to see.

	Ids are the ordinal within the tile, exactly as they are above, so both sides number the same
	list the same way without any of it being sent. ]]
local function benchTile(bench: Bench, tileIndex: number, segmentLength: number): { Obstacle }
	local items: { Obstacle } = {}
	local entries = benchPattern(bench)
	if #entries == 0 then
		return items
	end

	--- How far past its own point a repeat reaches, so the walk below starts far enough back to
	--- catch a course that began in the tile before this one.
	local reach = 0
	for _, entry in entries do
		reach = math.max(reach, entry.along)
	end

	--- The car spawns at the MIDDLE of tile 0, so that is what "lead studs down the road" is
	--- measured from. Same correction the tier path makes, for the same reason.
	local first = segmentLength * 0.5 + bench.lead
	local from = tileIndex * segmentLength
	local to = from + segmentLength

	local n = 0
	local k = math.max(0, math.floor((from - reach - first) / bench.spacing))
	while n < ObstacleLayout.IdsPerTile do
		local point = first + k * bench.spacing
		if point > to then
			break
		end
		for _, entry in entries do
			local along = point + entry.along
			if along >= from and along < to and n < ObstacleLayout.IdsPerTile then
				table.insert(items, {
					id = tileIndex * ObstacleLayout.IdsPerTile + n,
					kind = entry.kind,
					lane = entry.lane,
					laneOffset = entry.laneOffset,
					along = along - from,
					-- Not a course, and named so anything reading a tile's list can see at a glance
					-- that this road is not the one the ramp would have built.
					course = "bench",
				})
				n += 1
			end
		end
		k += 1
	end

	return items
end

local function tierFor(tileIndex: number, map: string?)
	local tiers = ObstacleLayout.tiersFor(map)
	for _, tier in tiers do
		if tileIndex <= tier.UntilTile then
			return tier
		end
	end
	return tiers[#tiers]
end

--[[ The obstacle list for one tile, in the order they appear down the road.

	Courses are laid end to end from the tile's lead-in to its tail-out, with a random
	tier gap between them, and a course that wouldn't fit before the tail-out is dropped
	rather than clipped — that's what keeps every course whole inside one tile. ]]
function ObstacleLayout.forTile(
	seed: number,
	tileIndex: number,
	segmentLength: number,
	map: string?,
	bench: Bench?
): { Obstacle }
	local items: { Obstacle } = {}
	if tileIndex < 0 then
		return items -- tiles behind the spawn stay clear
	end

	--[[ THE PACKS NO LONGER NEED THE COURSE — 2026-09-28. With the course switched off this used to
		return an empty list before either pass ran, which took every health and nitro pack off the
		road with it (`PickupConfig.Enabled`'s dated note). The course is still skipped, whole, and the
		pickup pass runs over the empty road with no obstacle ids taken. ]]
	if not ObstacleConfig.Enabled then
		placePickups(items, seed, tileIndex, segmentLength, 0)
		return items
	end

	--[[ The admin bench (`ObstacleConfig.Bench`) answers instead of the ramp, for every tile of the
		run. Above the two guards rather than below them, because a bench is a road to be driven and
		not an addition to one: the master switch still turns it off, and the tiles behind the spawn
		are still clear. ]]
	if bench then
		return benchTile(bench, tileIndex, segmentLength)
	end

	local rng = Random.new(tileSeed(seed, tileIndex))
	local tier = tierFor(tileIndex, map)
	local limit = segmentLength - ObstacleConfig.TailOut

	-- The car spawns at the middle of tile 0, so that tile only gets obstacles well past
	-- the spawn point; every later tile starts at its lead-in.
	local cursor = ObstacleConfig.LeadIn
	if tileIndex == 0 then
		cursor = segmentLength * 0.5 + ObstacleConfig.SpawnGraceStuds
	end
	cursor += rng:NextNumber(0, 60) -- so tiles never look phase-locked to each other

	local n = 0
	while cursor < limit and n < ObstacleLayout.IdsPerTile do
		local name = tier.Pool[rng:NextInteger(1, #tier.Pool)]
		local course = ObstacleConfig.Courses[name]
		if not course then
			break -- tier names a course that no longer exists; stop rather than guess
		end
		if cursor + course.Length > limit then
			break
		end

		for _, item in course.Items do
			if n >= ObstacleLayout.IdsPerTile then
				break
			end
			local laneOffset = ObstacleConfig.Lanes[item.Lane]
			if laneOffset then
				-- An item's optional `Nudge` is its off-grid tweak across the road. Lanes are a
				-- coarse 15-stud grid and some pairs need a gap the grid cannot cut, so it is
				-- folded into `laneOffset` right here: every consumer (the client build, the
				-- server hit check, traffic avoidance) reads that one number and stays in step.
				laneOffset += item.Nudge or 0
				table.insert(items, {
					id = tileIndex * ObstacleLayout.IdsPerTile + n,
					kind = item.Kind,
					lane = item.Lane,
					laneOffset = laneOffset,
					along = cursor + item.Along,
					course = name,
				})
				n += 1
			end
		end

		cursor += course.Length + rng:NextNumber(tier.Gap[1], tier.Gap[2])
	end

	--[[ ...and then the rewards, over the top of the finished course. It runs LAST because it reads
		`items` to keep a pack out of a barricade, and it draws from its own salted stream so that
		nothing it does here can reach back and move an obstacle. `n` is how many ids the loop above
		issued, which is the floor a pack's id must stay above. ]]
	placePickups(items, seed, tileIndex, segmentLength, n)

	return items
end

--[[ === THE WEATHER'S PASS ===================================================================

	The rain's puddles, over a tile whose obstacles and pickups are already known. `ObstacleConfig
	.Puddles` has the whole argument; the part that belongs here is what makes this pass different from
	the other two:

	  THE SERVER NEVER RUNS IT. `forTile` does not call it and neither does `byId`, so nothing the
	  server derives (the hit check, `clearedFor`'s dodge count) can change with the weather. Only the
	  client, which is the one side that knows it is raining, lays puddles.

	  ITS IDS ARE NEGATIVE: `-(tileIndex * IdsPerTile + n)` for the n-th puddle, n from 1. Tiles
	  behind the spawn carry nothing, so no real obstacle id is ever below zero, and a puddle can never
	  share an id (and so a `_consumed` entry) with anything the server knows about. The server's hit
	  handler also drops a negative id before it reads anything else, so even a report that went
	  astray would be inert.

	It is still SEEDED rather than random, off its own salted stream like the pickup pass. Nothing
	requires that of a pass the server never checks, but it costs nothing and it means a given seed's
	puddles are a fact about that road: the same run, driven twice, gets them in the same places, and
	a retune of the courses or the packs cannot move one. ]]

--- Salt for the weather pass's stream, for `PickupSalt`'s reason.
local PuddleSalt = 0x3E7A1D5B

--[[ Every kind any weather event can lay, as a set. `ObstacleService._publishProps` reads it to publish
	those kinds' art into EVERY map's folder, because a kind the rain lays is not in any map's ramp and
	`kindsFor` would never ask for it. ]]
function ObstacleLayout.weatherKinds(): { [string]: boolean }
	local kinds = {}
	for _, event in WeatherConfig.Events do
		local puddles = WeatherConfig.puddlesOf(event)
		if puddles and type(puddles.Kind) == "string" and ObstacleConfig.Kinds[puddles.Kind] then
			kinds[puddles.Kind] = true
		end
	end
	return kinds
end

--[[ The puddles one tile gets under an event's `Puddles` spec (`WeatherConfig`), in `forTile`'s shape
	plus the two fields only this pass sets: `yaw` and `scale`. `items` is that tile's `forTile` list,
	read to keep a puddle off every obstacle and pack on it and never written to. Empty for a tile
	behind the spawn, a spec that names nothing real, or the obstacle layer switched off. ]]
function ObstacleLayout.puddlesFor(
	seed: number,
	tileIndex: number,
	segmentLength: number,
	items: { Obstacle },
	spec: any
): { Obstacle }
	local placed: { Obstacle } = {}
	local rules = ObstacleConfig.Puddles
	if not (ObstacleConfig.Enabled and rules and type(spec) == "table") or tileIndex < 0 then
		return placed
	end
	local kind = spec.Kind
	if type(kind) ~= "string" or not ObstacleConfig.Kinds[kind] then
		return placed
	end

	local rng = Random.new(bit32.bxor(tileSeed(seed, tileIndex), PuddleSalt))
	-- Both rolls unconditionally, for `placePickups`' reason: the stream's position must not depend on
	-- its own results.
	local firstRoll, secondRoll = rng:NextNumber(), rng:NextNumber()
	local want = 0
	if firstRoll < (tonumber(spec.ChancePerTile) or 0) then
		want = 1
		if secondRoll < (tonumber(spec.ChanceOfSecond) or 0) then
			want = 2
		end
	end
	want = math.min(want, rules.MaxPerTile)

	local from = rules.LeadIn
	local to = segmentLength - rules.TailOut
	-- Tile 0 starts the car at its middle, so nothing is laid behind the spawn or inside its grace.
	if tileIndex == 0 then
		from = math.max(from, segmentLength * 0.5 + ObstacleConfig.SpawnGraceStuds)
	end
	if to <= from then
		return placed
	end

	local function clearOf(list: { Obstacle }, along: number, laneOffset: number): boolean
		for _, other in list do
			if
				math.abs(other.along - along) < rules.ClearAlong
				and math.abs(other.laneOffset - laneOffset) < rules.ClearCross
			then
				return false
			end
		end
		return true
	end

	for n = 1, want do
		for _ = 1, rules.Attempts do
			-- Every draw for a candidate is made before it is judged, so a rejection leaves the stream
			-- exactly where an acceptance would have.
			local lane = rules.Lanes[rng:NextInteger(1, #rules.Lanes)]
			local along = rng:NextNumber(from, to)
			local nudge = rng:NextNumber(-rules.Nudge, rules.Nudge)
			local yaw = rng:NextNumber(0, 360)
			local scale = rng:NextNumber(rules.Scale[1], rules.Scale[2])
			local laneOffset = ObstacleConfig.Lanes[lane]
			if laneOffset then
				laneOffset += nudge
				-- Off the course, off the packs, and off the puddle already laid, which would otherwise
				-- be free to land on top of this one.
				if clearOf(items, along, laneOffset) and clearOf(placed, along, laneOffset) then
					table.insert(placed, {
						id = -(tileIndex * ObstacleLayout.IdsPerTile + n),
						kind = kind,
						lane = lane,
						laneOffset = laneOffset,
						along = along,
						course = "weather",
						yaw = yaw,
						scale = scale,
					})
					break
				end
			end
		end
	end
	return placed
end

-- Single obstacle by id — the server's path when validating a reported hit.
function ObstacleLayout.byId(seed: number, id: number, segmentLength: number, map: string?, bench: Bench?): Obstacle?
	local tileIndex = ObstacleLayout.tileIndexOfId(id)
	for _, item in ObstacleLayout.forTile(seed, tileIndex, segmentLength, map, bench) do
		if item.id == id then
			return item
		end
	end
	return nil
end

return ObstacleLayout
