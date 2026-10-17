--[[
	CarDealService  (server)
	------------------------
	THE MARKET, WHICH IS ONE CAR PARKED IN EACH OF THE ISLAND'S CAR PARKS. A stall of the map's own
	paint, a car standing in it, a price over its head, and a different car in every stall every five
	minutes. Hold the button and the car is yours: the display clone is thrown away, a real rig takes
	its place in the same stall, and you are in the driver's seat of it.

	`CarDealConfig` has the design and every number; this file is the geometry, the clock and the
	till. It is the only place in the game where cash turns into a car.

	=== WHAT IT OWNS AND WHAT IT DELIBERATELY DOES NOT ========================================

	It owns finding the lots, the bays and the purchase. It does NOT own:

	  • THE SELLER. The person standing next to the car is built on the CLIENT out of that player's
	    own friends list (`CarDealController`), so nothing here knows or cares who is beside a bay.
	    See `CarDealConfig.Dealer` for why that split falls the opposite way to `CustomerService`'s.
	  • WHAT HAPPENS TO A BOUGHT CAR. That is `GarageService.awardCar`, unchanged, the same call a
	    car that survived a run goes through. This file takes the money and hands over a tier and a
	    body; every branch after that is the garage's.
	  • THE CAR YOU DRIVE AWAY IN. That is `LobbyCarService.setLobbyCar`, also unchanged apart from
	    the placement override it grew for this. One car per player, the paint, the plate, the doors,
	    the entry beat and the despawn rules are all its, exactly as they are for a car spawned off
	    the Cars Inventory screen. `_handover` is thirty lines of asking, not a second spawner.
	  • THE COUNTDOWN. It writes one attribute (`NextRotationAttribute`) and the client draws
	    whatever it likes from it, which is a strip hanging under each sign (`CarDealConfig.Bubble`).

	=== THE SIX THINGS THAT ARE NOT OBVIOUS ===================================================

	1. THE BAYS ARE THE MAP'S OWN STALLS, AND THEY ARE FOUND RATHER THAN NAMED. `_findLots` reads
	   every flat, thin part in the map's paint folders, sorts them into ranks of parallel
	   same-length lines evenly spaced a car's width apart, and takes one stall out of each rank.
	   Nothing in the map has to be named, tagged or moved for that to work, which is the property
	   that survives the next map swap (`docs/MapLayout.md` §6): paint a fifth car park and a fifth
	   deal stands in it with no change here. `CarDealConfig.Lots` has every rule and the argument
	   for each.

	2. WHICH END OF A STALL IS CLOSED IS ASKED OF THE GROUND, NOT OF A COMPASS. The four lots on this
	   island back onto kerbed grass medians standing 5.2 studs proud of the asphalt, against a tenth
	   of a stud for paint and four tenths for a verge. So `_stallOf` probes the ground past both
	   ends of a rank and points the car away from the higher one. A lot drawn the other way round on
	   a future map is parked in correctly without a line changing, and nothing in this file names a
	   direction.

	3. A ROTATION DOES NOT MOVE ANYTHING ANY MORE. The stands are built once and stay where they are
	   for the life of the server; a roll swaps the car standing in each one, and that is all it
	   does. It is the change this file was rewritten for (`CarDealConfig` header note 4): four fixed
	   addresses a player can drive between beat three that move every five minutes, because the
	   second kind cannot be gone back to.

	4. A STALL'S SIZE COMES OFF THE PAINT AND TRAVELS WITH THE STAND. `Stand.width` and `Stand.depth`
	   are what the map measured rather than what a config declared, and they are what the car is
	   fitted to and what the seller is stood off. The stalls here are 25 to 30 wide and 34.9 deep,
	   two lots need not agree about either, and on a future map they will not.

	5. THE PROMPT IS THE ONLY WAY IN. There is no client -> server remote in this file: a purchase
	   arrives as `ProximityPrompt.Triggered`, which the engine only fires for a player who is really
	   within `Prompt.MaxDistance` of the bay and which already carries who pressed it. A client
	   cannot ask to buy a car it is not standing next to, and there is no request shape to validate.

	6. EVERY REFUSAL IS SILENT ON THE SERVER AND LOUD ON THE CLIENT. The bubble already says whether
	   you can afford it and whether you own it (`CarDealController` reads both off replicated
	   attributes), so a press that gets here and fails is a race or a lie, and neither deserves a
	   round trip. The one exception is a successful buy, which fires `DealBought` so the client can
	   celebrate the thing it just paid for.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local CarDealConfig = require(ReplicatedStorage.shared.Configs.CarDealConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local LobbyCarConfig = require(ReplicatedStorage.shared.Configs.LobbyCarConfig)
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)
local PlotConfig = require(ReplicatedStorage.shared.Configs.PlotConfig)
local CarDisplay = require(ReplicatedStorage.shared.Modules.CarDisplay)

--[[ One built bay, resolved once at start-up.

	A STAND NEVER MOVES AGAIN, which is what this record is for: everything about where it is comes
	off the map's paint one time, and a rotation is then straight-line property writes. ]]
type Stand = {
	index: number,
	model: Model,
	base: BasePart,
	prompt: ProximityPrompt,
	--- The frame the car, the seller and the slab are all placed against: origin on the ROAD at the
	--- middle of the stall, LookVector pointing the way the car's nose points, which is out of the
	--- stall and into the road.
	frame: CFrame,
	--- The stall's own size, measured off the paint that drew it: `width` between its two lines,
	--- `depth` along them. Carried per stand rather than read out of a config, because these are the
	--- MAP's numbers and two lots need not agree about them.
	width: number,
	depth: number,
	body: string?, -- what is on it right now, nil before the first roll and after a sale
}

local CarDealService = Shard.new("CarDealService"):withDependencies({ "GarageService", "LobbyCarService" })

CarDealService:withSignals({
	--[[ (player, body, tier, paint, price, standIndex) — a car was bought off a bay. The cash is
		gone and `awardCar` has already run by the time this fires, so a subscriber reading the
		profile sees the purchase done. Here for whatever wants to count it: a quest, an analytics
		funnel, a server-wide feed. ]]
	"CarBought",
})

CarDealService:withRemoteEvents({
	--[[ server -> client (standIndex, body, price): you bought that one. Purely cosmetic and fired
		LAST, after the money and the car have both moved, so a client that ignores it or is not
		listening loses nothing — the same bargain `GarageService`'s `CashBurst` makes. ]]
	"DealBought",
})

--[[ One candidate stall line, as this file reads it off the map.

	`axis` IS THE LINE'S LONG SIDE IN WORLD SPACE and which way along it points is arbitrary: the
	builder drew some of these mirrored, so nothing here may assume that two lines of one rank agree
	about their own direction. Every question asked of it is either symmetrical (are these two
	parallel, how far apart across it are they) or is asked of BOTH ends (which end is the kerb). ]]
type Line = {
	part: BasePart,
	axis: Vector3,
	length: number,
	at: Vector3,
}

--- One lot's chosen stall, before a stand is built on it. Same three numbers a `Stand` carries.
type Stall = { frame: CFrame, width: number, depth: number }

-- === Finding the car parks ==================================================

--[[ The folders `Lots.Paint.Roots` resolves to, or the whole map when none of them do.

	THE FALLBACK IS THE WHOLE MAP RATHER THAN NOTHING, and it is the same direction the road search
	this replaced took, for the same reason: a map swap that renames a folder should cost a slower
	scan and a warning somebody can act on, not a market that silently stops existing. ]]
function CarDealService._paintRoots(self): { Instance }
	local roots: { Instance } = {}
	for _, path in CarDealConfig.Lots.Paint.Roots do
		local at: Instance? = self._map
		for _, step in path do
			at = at and at:FindFirstChild(step)
		end
		if at then
			table.insert(roots, at)
		end
	end
	if #roots == 0 then
		self.log:warn("No paint folders resolved from Lots.Paint.Roots; scanning the whole map for stall lines.")
		table.insert(roots, self._map :: Instance)
	end
	return roots
end

--[[ The ground height under a point, or nil where the map has none.

	FIRED FROM ABOVE THE MAP'S OWN BOUNDING BOX rather than from a typed altitude, which is
	`PlotConfig`'s rule and `Lots.Probe`'s note, and filtered to the map so that a car parked in the
	lot, a player standing in it or one of this service's own display clones cannot answer a question
	about the road.

	IT IS ALLOWED TO HIT PAINT, unlike the road probe this replaced, and that is because both of its
	callers are asking something a tenth of a stud does not change: how high the ground is in the
	middle of a stall, and whether the ground past the end of a rank is a KERB. Paint lies flush;
	the medians these lots back onto stand 5.2 studs proud. ]]
function CarDealService._groundAt(self, x: number, z: number): number?
	local probe = CarDealConfig.Lots.Probe
	local top = self._mapTopY + probe.ProbeUp
	local reach = (self._mapTopY - self._mapBottomY) + probe.ProbeUp + probe.ProbeDown
	local hit = workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, -reach, 0), self._roadParams)
	return if hit then hit.Position.Y else nil
end

--[[ Every part under the paint roots that could be a stall line: flat, thin, and the right length.

	ONE PASS AND NO GEOMETRY QUERIES. This is a size test on a few thousand parts, which is cheap
	enough to run over the whole map in the fall-back branch above; everything expensive (the ground
	probes) happens later and only on ranks that already look like car parks. ]]
function CarDealService._paintLines(self): { Line }
	local paint = CarDealConfig.Lots.Paint
	local lines: { Line } = {}
	for _, root in self:_paintRoots() do
		for _, part in root:GetDescendants() do
			if not part:IsA("BasePart") or part.Size.Y > paint.MaxThickness then
				continue
			end
			local long = math.max(part.Size.X, part.Size.Z)
			local short = math.min(part.Size.X, part.Size.Z)
			if long < paint.MinLength or long > paint.MaxLength or short > paint.MaxWidth then
				continue
			end

			--- The long side in world space: a part's `RightVector` is its own +X and its
			--- `LookVector` its own -Z, so whichever side measured longer names the axis.
			local axis = if part.Size.X >= part.Size.Z then part.CFrame.RightVector else part.CFrame.LookVector
			local flat = Vector3.new(axis.X, 0, axis.Z)
			--- A line standing on its end is a post, not paint, and has no horizontal axis to rank.
			if flat.Magnitude < 0.1 then
				continue
			end
			table.insert(lines, { part = part, axis = flat.Unit, length = long, at = part.Position })
		end
	end
	return lines
end

--[[ Sort candidate lines into ranks: parallel, the same length, at the same height, and offset from
	one another only ACROSS their own length.

	THE LAST TEST IS THE ONE THAT DOES THE WORK. Parallel same-length lines at one height describe
	half the paint on a road: the two sides of a carriageway, a lane line and its neighbour, the
	kerbs of two different streets running the same way. What makes a rank a RANK is that its lines
	sit side by side on one line of their own — a row of stalls — rather than one behind the other.
	`Paint.Skew` is how much of that a builder's export is allowed to be out by.

	QUADRATIC IN THE NUMBER OF RANKS AND THAT IS FINE: this map yields 45 candidate lines and six
	ranks. It is bounded by the paint, not by the map. ]]
function CarDealService._ranks(self, lines: { Line }): { { Line } }
	local paint = CarDealConfig.Lots.Paint
	local ranks: { { Line } } = {}
	for _, line in lines do
		local placed = false
		for _, rank in ranks do
			local head = rank[1]
			if math.abs(head.axis:Dot(line.axis)) < paint.Parallel then
				continue
			end
			if math.abs(head.length - line.length) > paint.SameLength then
				continue
			end
			if math.abs(head.at.Y - line.at.Y) > paint.SameHeight then
				continue
			end
			if math.abs((line.at - head.at):Dot(head.axis)) > paint.Skew then
				continue
			end
			table.insert(rank, line)
			placed = true
			break
		end
		if not placed then
			table.insert(ranks, { line })
		end
	end
	return ranks
end

--[[ Split one rank into the RUNS of lines that are stalls standing side by side.

	THE GAPS DECIDE, AND EACH OF THE THREE ANSWERS IS A REAL SHAPE ON A REAL MAP:

	  • under `Duplicate` is one line drawn twice, and the second is dropped. A builder's export has
	    them: the west lot on this island carries two lines two tenths of a stud apart, and read
	    literally that is a stall nobody could park in, sitting in the middle of a perfectly good lot.
	  • under `MinStall` means these are STRIPES rather than stalls, and the run ends. A crosswalk is
	    twelve parallel same-length lines seven studs apart and passes every other test this file
	    makes; no part of one is a car park, and each of its lines ends up alone in a run of one.
	  • over `MaxStall` is two different things that happen to line up, and the run also ends — but
	    both halves survive. Two lots facing each other across a street would otherwise take each
	    other down, which is the sort of failure that turns up on the map after next and is silent.

	The sort is what makes any of this meaningful: `GetDescendants` hands lines over in creation
	order, and "the gap to the previous line" only means anything once they are in line order. ]]
function CarDealService._runsOf(self, rank: { Line }): { { Line } }
	local paint = CarDealConfig.Lots.Paint
	local across = Vector3.yAxis:Cross(rank[1].axis).Unit
	table.sort(rank, function(a: Line, b: Line): boolean
		return a.at:Dot(across) < b.at:Dot(across)
	end)

	local runs: { { Line } } = {}
	local run: { Line } = { rank[1] }
	for index = 2, #rank do
		local gap = (rank[index].at - run[#run].at):Dot(across)
		if gap < paint.Duplicate then
			continue
		end
		if gap < paint.MinStall or gap > paint.MaxStall then
			table.insert(runs, run)
			run = { rank[index] }
			continue
		end
		table.insert(run, rank[index])
	end
	table.insert(runs, run)
	return runs
end

--[[ Turn one run of lines into the stall a deal stands in, or nil if the run is not a car park.

	The gaps were settled by `_runsOf`; what is left is the rest of `CarDealConfig.Lots`' header. The
	run has to be long enough to be a lot, the closed end is found by probing past both ends, and the
	stall taken is the one on `Stall.Side`.

	IT RETURNS THE STALL'S SIZE ALONG WITH ITS FRAME because nothing else can measure it. The stalls
	on this map are 25 to 30 studs apart and 34.9 deep; a future lot drawn to different numbers fits
	its car the same way, because the car is fitted to what was measured rather than to a constant. ]]
function CarDealService._stallOf(self, kept: { Line }): Stall?
	local lots = CarDealConfig.Lots
	local paint = lots.Paint
	local axis = kept[1].axis
	--- Across the run: stall to stall. Horizontal by construction, because `axis` is.
	local across = Vector3.yAxis:Cross(axis).Unit

	if #kept < paint.MinLines then
		return nil
	end

	local depth = kept[1].length
	local mid = Vector3.zero
	for _, line in kept do
		mid += line.at
	end
	mid /= #kept

	--[[ Which end of the stalls is closed: the one with the kerb behind it.

		SAMPLED OUTWARD RATHER THAN AT ONE DISTANCE, and the highest ground found on each side is
		what the two ends are compared on. The gap a builder leaves between the last line and the
		kerb is not a number this file can know — it is 4.9 studs on this map — so a single probe at
		a fixed distance either lands short on the asphalt inside the lot or steps clean over the
		median and reports the road on the far side of it. ]]
	local probe = lots.Probe
	local steps = math.max(1, probe.Steps)
	local function highestPast(direction: Vector3): number?
		local best: number? = nil
		for step = 1, steps do
			local at = mid + direction * (depth / 2 + probe.Reach * step / steps)
			local ground = self:_groundAt(at.X, at.Z)
			if ground and (not best or ground > best) then
				best = ground
			end
		end
		return best
	end

	local behind, ahead = highestPast(-axis), highestPast(axis)
	local nose: Vector3
	if behind and ahead and math.abs(behind - ahead) >= probe.KerbRise then
		--- Nose away from the kerb, out into the lot.
		nose = if behind > ahead then axis else -axis
	elseif behind and not ahead then
		--- No ground past that end at all: a drop is not somewhere to drive out to either.
		nose = -axis
	elseif ahead and not behind then
		nose = axis
	else
		--[[ Neither end is a kerb, so nothing about the lot itself says which way it faces. Point
			the car away from the middle of the island, which is where this map's open road is, and
			which is the one thing `Lots.CentreX`/`CentreZ` are still here for. ]]
		local away = Vector3.new(mid.X - lots.CentreX, 0, mid.Z - lots.CentreZ)
		nose = if away:Dot(axis) >= 0 then axis else -axis
	end

	--[[ Left as seen from the road looking INTO the lot, which is how a driver arriving at one sees
		it (`Lots.Stall.Side`).

		`up × inward` IS THAT LEFT HAND, and it is also the parked car's own RIGHT, because the car
		faces the other way. That is not a coincidence to be tidied up: it is exactly why the LEFT
		stall is the one worth taking, since the seller stands off the car's right and lands on the
		open tarmac at the end of the rank rather than in the next stall along. ]]
	local left = Vector3.yAxis:Cross(-nose).Unit
	local want = if string.lower(lots.Stall.Side) == "right" then -left else left

	local chosen: Vector3? = nil
	local width = 0
	local furthest = -math.huge
	for index = 2, #kept do
		local centre = (kept[index - 1].at + kept[index].at) / 2
		local along = centre:Dot(want)
		if along > furthest then
			furthest = along
			chosen = centre
			width = math.abs((kept[index].at - kept[index - 1].at):Dot(across))
		end
	end
	if not chosen then
		return nil
	end

	--- The ROAD at the middle of the stall, not the height the paint was drawn at: the paint is a
	--- tenth of a stud proud of the asphalt and the car's tyres belong on the asphalt.
	local ground = self:_groundAt(chosen.X, chosen.Z) or mid.Y
	local origin = Vector3.new(chosen.X, ground, chosen.Z)
	return {
		frame = CFrame.lookAt(origin, origin + nose, Vector3.yAxis),
		--- What the car has BETWEEN the paint rather than between the two line centres.
		width = math.max(1, width - paint.Inset),
		depth = depth,
	}
end

--[[ Find every car park in the map and take one stall out of each. Runs once, at start-up, and is
	the whole of this feature's geography.

	COMING UP EMPTY IS SURVIVABLE AND LOUD. `_build` warns and the market is off for the server,
	which is the honest outcome for a map with nothing painted on it: there is no scatter to fall
	back to any more, and inventing bays on open asphalt is the thing this replaced. ]]
function CarDealService._findLots(self)
	local lots = CarDealConfig.Lots
	local started = os.clock()

	--- Authored markers win outright when there are any (`Lots.SpotTag` has the rules).
	for _, spot in CollectionService:GetTagged(lots.SpotTag) do
		if spot:IsA("BasePart") and spot:IsDescendantOf(workspace) then
			local nose = spot.CFrame.LookVector * Vector3.new(1, 0, 1)
			local origin = spot.Position - Vector3.yAxis * (spot.Size.Y / 2)
			spot.Transparency, spot.CanCollide, spot.CanQuery, spot.CanTouch = 1, false, false, false
			if nose.Magnitude > 1e-3 then
				table.insert(self._stalls, {
					frame = CFrame.lookAt(origin, origin + nose.Unit, Vector3.yAxis),
					width = spot.Size.X,
					depth = spot.Size.Z,
				})
			else
				self.log:warn(string.format("Car deal spot %s faces straight up or down; skipped, so that stall has no dealer.", spot:GetFullName()))
			end
		end
	end
	local lines = if #self._stalls > 0 then {} else self:_paintLines()
	local ranks = self:_ranks(lines)
	local runs = 0
	for _, rank in ranks do
		for _, run in self:_runsOf(rank) do
			runs += 1
			local stall = self:_stallOf(run)
			if stall then
				table.insert(self._stalls, stall)
			end
		end
	end

	--[[ NUMBERED BY BEARING around the middle of the island, so stand 1 is the same lot in every
		server, in every log line and in every `DealBought` the client ever gets. Left alone the
		order is `GetDescendants`'s, which is stable enough to look deliberate and not stable enough
		to be. ]]
	table.sort(self._stalls, function(a: Stall, b: Stall): boolean
		return math.atan2(a.frame.Position.Z - lots.CentreZ, a.frame.Position.X - lots.CentreX)
			< math.atan2(b.frame.Position.Z - lots.CentreZ, b.frame.Position.X - lots.CentreX)
	end)

	self.log:info(string.format(
		"%d car parks found: %d candidate stall lines in %d ranks and %d runs, read in %.0f ms.",
		#self._stalls,
		#lines,
		#ranks,
		runs,
		(os.clock() - started) * 1000
	))
end

-- === Building a bay =========================================================

--[[ The bay: an invisible slab filling one of the map's stalls, with the prompt, the bubble's
	anchor and the seller's mark hanging off it.

	BUILT ONCE AND NEVER MOVED OR REBUILT (header note 4), so this runs once per car park in a
	server's life and nothing in a rotation touches it. That is the whole shape of the change: what
	used to be a bay that was painted, moved, and re-measured every five minutes is now a fixture
	standing on paint somebody else drew.

	THERE IS NOTHING TO DRAW. `CarDealConfig.Bay` has the argument; the short version is that the map
	already paints this stall, at its own width, and a second set of lines inside the first would be
	two bays disagreeing about where the car goes.

	IT IS STILL ANCHORED, NON-COLLIDING, UNQUERYABLE AND UNTOUCHABLE. A bay stands exactly where a
	car parks and `LobbyCarService` asks "is anything solid here?" about exactly that spot, so a slab
	that answered would make the stall unusable to the car being sold on it. ]]
function CarDealService._buildStand(self, index: number, stall: Stall): Stand
	local bay = CarDealConfig.Bay
	local names = CarDealConfig.Names
	local frame = stall.frame

	local model = Instance.new("Model")
	model.Name = string.format("%s%d", names.Stand, index)
	--- Header note in `CarDealConfig.Tag`: the whole bay arrives on a client as one piece, so the
	--- controller's tag handler can walk its children on the frame it fires.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local base = Instance.new("Part")
	base.Name = names.Base
	base.Anchored = true
	base.CanCollide = false
	base.CanQuery = false
	base.CanTouch = false
	base.CastShadow = false
	base.Transparency = 1
	base.TopSurface = Enum.SurfaceType.Smooth
	base.BottomSurface = Enum.SurfaceType.Smooth
	--- The stall's own footprint, so an explorer shows the space this deal claims even though a
	--- player never sees it.
	base.Size = Vector3.new(stall.width, bay.Slab, stall.depth)
	base.CFrame = frame * CFrame.new(0, bay.Slab / 2, 0)
	base.Parent = model
	model.PrimaryPart = base

	--[[ The seller's mark and the bubble's anchor, both Attachments on `base` so the client does not
		have to re-derive this frame from the model's pivot. The seller's is at their FOOT height;
		the bubble hangs above their head.

		`SideMargin` IS ADDED TO THE STALL'S OWN HALF WIDTH rather than being a distance in itself
		(`CarDealConfig.Dealer`): these stalls are 25 to 30 studs wide against the old painted bay's
		16, so the flat 12 this used to be would stand the seller inside the paint, beside the car
		they are meant to be standing clear of. ]]
	local dealer = CarDealConfig.Dealer
	local mark = Instance.new("Attachment")
	mark.Name = names.DealerStand
	--[[ PARENTED BEFORE `WorldCFrame` IS WRITTEN, and the order is load-bearing rather than tidy.
		`Attachment.WorldCFrame` is derived from the parent part's frame, so on an unparented
		attachment it is simply the LOCAL CFrame under another name. Write a world pose first and
		parenting it re-reads that pose as an offset from the base, which lands the seller a thousand
		studs off the island. Measured: it put stand 1's mark at (6.8, 106.5, 1109.5). ]]
	mark.Parent = base
	--- `Ahead` is toward the nose, so it is negated: a CFrame's `LookVector` is its negated Z axis,
	--- and every offset in this file that means "toward the nose" is written that way.
	mark.WorldCFrame = frame
		* CFrame.new(stall.width / 2 + dealer.SideMargin, 0, -dealer.Ahead)
		* CFrame.Angles(0, math.rad(dealer.FaceDegrees), 0)

	--[[ HEAD HEIGHT, NOT BUBBLE HEIGHT. The attachment marks the top of the seller and nothing more;
		how far above it a bubble floats, and how tall that bubble is, are the client's business
		(`CarDealController` sets `StudsOffset` from `Bubble.HeadOffset` and the bubble's own half
		height). Splitting it that way means retuning the sign never means moving a world instance. ]]
	local anchor = Instance.new("Attachment")
	anchor.Name = names.BubbleAnchor
	anchor.Parent = base
	anchor.WorldPosition = mark.WorldPosition + Vector3.new(0, dealer.RootHeight * 2, 0)

	local prompt = Instance.new("ProximityPrompt")
	local promptCfg = CarDealConfig.Prompt
	prompt.Name = names.Prompt
	prompt.ActionText = promptCfg.ActionText
	prompt.ObjectText = ""
	prompt.KeyboardKeyCode = promptCfg.Key
	prompt.GamepadKeyCode = promptCfg.GamepadKey
	prompt.HoldDuration = promptCfg.HoldDuration
	prompt.MaxActivationDistance = promptCfg.MaxDistance
	prompt.RequiresLineOfSight = promptCfg.RequiresLineOfSight
	--- Ours to draw. `CarDealConfig.Prompt` has the argument, and the touch tap target it costs.
	prompt.Style = Enum.ProximityPromptStyle.Custom
	--- Off until there is something in the bay to sell. `_setOffer` is what switches it on.
	prompt.Enabled = false
	prompt.Parent = base

	model:SetAttribute(CarDealConfig.Attributes.Index, index)
	model:AddTag(CarDealConfig.Tag)
	model.Parent = self._folder

	local record: Stand = {
		index = index,
		model = model,
		base = base,
		prompt = prompt,
		frame = frame,
		width = stall.width,
		depth = stall.depth,
		body = nil,
	}

	self._trove:Add(prompt.Triggered:Connect(function(player: Player)
		self:_onTriggered(record, player)
	end))

	return record
end

-- === Putting a car in one ===================================================

--[[ Park a body in a bay, replacing whatever was there.

	The clone comes back finished but unparented (`CarDisplay.build`), so the swap is: build the new
	one off screen, destroy the old one, place and parent the new one. A rotation therefore never
	shows an empty bay, and never shows a car sliding into place from the roster master's own world
	pose.

	STOOD ON THE ROAD RATHER THAN ON THE PAINT. The bay is two tenths of a stud thick and the car's
	tyres belong on the asphalt, with the paint passing under them the way paint does.

	Returns false for a body the roster has no rig for, which is the one case the caller has to
	handle: it re-rolls. ]]
function CarDealService._placeCar(self, stand: Stand, body: string, paint: number): boolean
	local carCfg = CarDealConfig.Car
	local bay = CarDealConfig.Bay
	local clone, offsets, extents = CarDisplay.build(body, paint, {
		rosterFolder = GarageConfig.Display.RosterFolderName,
		bodyFolder = GarageConfig.Display.BodyFolderName,
		hitBoxName = GarageConfig.Display.HitBoxName,
		name = CarDealConfig.Names.Car,
		castShadow = carCfg.CastShadow,
	})
	if not clone then
		return false
	end

	--- The stall's own measurements, not a config's: `_stallOf` read them off the map's paint.
	local carWidth = extents.maxX - extents.minX
	local carLength = extents.maxZ - extents.minZ

	--[[ A body that does not fit the stall is refused and the caller rolls again.

		IT DOES THE HONEST JOB IT LOOKS LIKE IT DOES — a lot painted too small for the biggest bodies
		on the roster never gets offered one, rather than getting one that hangs over its own paint —
		AND IT CATCHES A BROKEN RIG, which is what actually made it necessary. Three cars in this
		place file (`Charger`, `Golf GTI`, `Senna`) have panels sitting hundreds of studs off their
		own chassis. The clone measures hundreds of studs across, and parked without this check one
		of them is a car in a stall with three body panels hanging in the sky above the plaza.

		Those three also fall out of the world and take their masters with them a second or two into
		every session, so the same roll a moment later simply finds no rig and fails at `build`
		above. This is the window in between, and it is only reachable because the first rotation now
		happens seconds into a server rather than after a fifteen-second search. ]]
	if carWidth > stand.width or carLength > stand.depth then
		clone:Destroy()
		self.log:warn(string.format(
			"%s measures %.1f x %.1f and does not fit bay %d's %.1f x %.1f stall; rolling again.",
			body,
			carWidth,
			carLength,
			stand.index,
			stand.width,
			stand.depth
		))
		return false
	end

	local yaw = CarDisplay.fitYaw(carWidth, carLength, stand.width, stand.depth, carCfg.Yaw)
	local facing = stand.frame * CFrame.Angles(0, math.rad(yaw), 0)

	--[[ Backed up against the head of the stall rather than left floating in the middle of it, which
		is `Bay.HeadGap`'s note: a 21-stud car centred in a 35-stud stall reads as somebody who
		stopped short, and the slack belongs in front of it where the buyer drives out.

		THE FOOTPRINT IS MEASURED ALONG THE STALL AND NOT ALONG THE CAR, because `fitYaw` may have
		turned it and a car at an angle reaches further down a stall than its own length. At the
		square pose these deals use (`Car.Yaw` is 0) the two are the same number; the expression is
		here so that turning them on again does not quietly bury a boot in the kerb.

		POSITIVE Z IS TOWARD THE HEAD. A CFrame's `LookVector` is its NEGATED Z axis, and this
		frame's LookVector is the way the nose points, so backing the car up is a POSITIVE offset. It
		is the sign that produces working, plausible geometry facing the wrong way if it is wrong. ]]
	local radians = math.rad(yaw)
	local alongStall = math.abs(carLength * math.cos(radians)) + math.abs(carWidth * math.sin(radians))
	local backOff = math.max(0, stand.depth / 2 - alongStall / 2 - bay.HeadGap)
	local centre = (stand.frame * CFrame.new(0, 0, backOff)).Position

	CarDisplay.place(offsets, CarDisplay.standOn(extents, centre, stand.frame.Position.Y, facing, carCfg.Lift))

	local existing = stand.model:FindFirstChild(CarDealConfig.Names.Car)
	if existing then
		existing:Destroy()
	end
	clone.Parent = stand.model
	return true
end

--[[ Put one offer in one bay: the car, the four attributes and the prompt's own label.

	THE ATTRIBUTES ARE WRITTEN AFTER THE CAR IS PARENTED, so a client redrawing its bubble from an
	attribute change is redrawing it for a car that is already standing there. The order is the same
	one `GarageService._publishOwned` follows and for the same reason. ]]
function CarDealService._setOffer(self, stand: Stand, body: string, tier: number, paint: number, price: number)
	if not self:_placeCar(stand, body, paint) then
		return false
	end

	local attrs = CarDealConfig.Attributes
	stand.body = body
	stand.model:SetAttribute(attrs.Body, body)
	stand.model:SetAttribute(attrs.Paint, paint)
	stand.model:SetAttribute(attrs.Tier, tier)
	stand.model:SetAttribute(attrs.Price, price)

	--[[ The prompt's own text is set even though nothing draws it: `Style = Custom` means Roblox
		renders none of this, but the strings are what an explorer shows during a playtest and what
		a fallback to `Style = Default` would print if this feature ever needs one in a hurry. ]]
	stand.prompt.ObjectText = string.format("%s  %s", GarageConfig.displayName(body), GarageConfig.formatCash(price))
	stand.prompt.Enabled = true
	return true
end

--[[ Take a bay off the market: the car goes, the sign goes dark and the button stops answering.

	THE ATTRIBUTES ARE CLEARED RATHER THAN LEFT STALE, and that is what draws the blank: the client's
	`_redraw` hides the whole panel for a stand with no `Body` on it, so one write is the difference
	between an empty bay with a price floating over it and an empty bay. ]]
function CarDealService._clearOffer(self, stand: Stand)
	local attrs = CarDealConfig.Attributes
 local templates = ReplicatedStorage:FindFirstChild("CarDealDisplayTemplates")
 if templates then
  for highest = 1, #WorldConfig.Worlds do
   local template = templates:FindFirstChild(tostring(stand.index) .. "_" .. tostring(highest))
   if template then template:Destroy() end
  end
 end
 for highest = 1, #WorldConfig.Worlds do
  for _, attribute in {attrs.Body, attrs.Paint, attrs.Tier, attrs.Price} do
   stand.model:SetAttribute(CarDealConfig.stockAttribute(attribute, highest), nil)
  end
 end
 local existing = stand.model:FindFirstChild(CarDealConfig.Names.Car)
	if existing then
		existing:Destroy()
	end
	stand.body = nil
	stand.prompt.Enabled = false
	stand.prompt.ObjectText = ""
	stand.model:SetAttribute(attrs.Body, nil)
	stand.model:SetAttribute(attrs.Paint, nil)
	stand.model:SetAttribute(attrs.Tier, nil)
	stand.model:SetAttribute(attrs.Price, nil)
end

-- === The clock ==============================================================

--[[ Is somebody's car standing in this stall?

	IT IS THE ONE QUESTION A FIXED BAY HAS TO ASK AND A MOVING ONE DID NOT. A stand used to leave
	the bay it sold a car in and go somewhere else, so the buyer sitting in their new car was never
	in the way of anything. A stand that stays would restock the stall around them 0.6 seconds after
	the sale — a second car materialising inside the one they just paid for, every single purchase.

	ASKED OF `Workspace.LobbyCars` RATHER THAN OF THE WORLD. Every real car a player has out is in
	that folder with its owner stamped on it (`LobbyCarConfig`), so this is a walk over at most one
	model per player and a distance check, rather than an overlap query against a 43,000-part island.
	It also answers the RIGHT question: a player standing in the stall, a bag of leaves or this
	service's own display clone are not cars parked in a parking space and must not hold up the
	market. `Lots.Stall.ClearRadius` is the distance and the argument for it. ]]
function CarDealService._stallTaken(self, stand: Stand): boolean
	local folder = workspace:FindFirstChild(LobbyCarConfig.FolderName)
	if not folder then
		return false
	end
	local here = stand.frame.Position
	local reach = CarDealConfig.Lots.Stall.ClearRadius
	for _, car in folder:GetChildren() do
		if car:IsA("Model") then
			local at = car:GetPivot().Position
			--- Flat, because a car on a ramp above the lot is not in the lot.
			if (Vector3.new(at.X - here.X, 0, at.Z - here.Z)).Magnitude < reach then
				return true
			end
		end
	end
	return false
end

--[[ Put a fresh car in one stand. The stand does not move: it is a stall of the map's own car park
	and it is where it is for the life of the server (header note 4).

	`taken` is the set of bodies already on a stand this pass, threaded through rather than being per
	stand, because "no two bays offer the same body" is a fact about the market and not about a bay.

	IT IS ALLOWED TO FAIL and the caller keeps the old offer if it does, which is the right way
	round: a bay holding a five-minute-old car is a worse market than a fresh one and a much better
	one than an empty stall with a sign over it. ]]
function CarDealService._rollStand(self, stand: Stand, taken: { [string]: boolean }): boolean
	for _ = 1, math.max(1, CarDealConfig.Offer.MaxRerolls) do
		local body, tier = CarDealConfig.rollBody(self._rng, taken)
		if not (body and tier) then
			break
		end
		local paint = PaintConfig.roll(self._rng, body)
		local price = CarDealConfig.priceFor(tier, self._rng:NextNumber(-1, 1))
		if price > 0 and self:_setOffer(stand, body, tier, paint, price) then
			taken[body] = true
			return true
		end
	end
	return false
end

--- What is standing on every OTHER stand right now: the set `_rollStand` needs, built from the
--- world rather than carried around between rotations.
function CarDealService._marketState(self, except: Stand?): { [string]: boolean }
	local taken: { [string]: boolean } = {}
	for _, stand in self._stands do
		if stand ~= except and stand.body then
			taken[stand.body] = true
		end
	end
	return taken
end

--[[ Roll a fresh car into every stand. The lots do not change; what is parked in them does.

	NO TWO STANDS SHARE A BODY (`CarDealConfig.Offer`). A roll that lands on a body the roster has no
	rig for — a name in `WorldConfig` that nobody has built yet — re-rolls rather than leaving a bare
	stall, bounded the same way.

	THE DEADLINE IS WRITTEN LAST, after every stand has its car, so a client that reacts to the
	attribute finds a market that is already dressed. ]]
function CarDealService._roll(self)
	local taken = self:_marketState()

	for _, stand in self._stands do
		if self:_stallTaken(stand) then
			--[[ Somebody has parked in this lot's deal stall. Leave the stand exactly as it is
				rather than building a new car around theirs: whatever is on it now is at worst a
				five-minute-old offer, and the next rotation asks again. ]]
			self.log:info(string.format("Bay %d has a car parked in it; its offer stands.", stand.index))
			continue
		end
		if not self:_rollStand(stand, taken) then
			--[[ Nothing could be parked in this bay. It keeps whatever it had rather than being
				blanked: a stale offer is a worse market than a fresh one and a much better one than
				an empty bay with a sign over it, and the next rotation tries again. ]]
			self.log:warn(string.format("Stand %d could not be given a car this rotation.", stand.index))
		end
	end

	local deadline = workspace:GetServerTimeNow() + CarDealConfig.Offer.Interval
	workspace:SetAttribute(CarDealConfig.NextRotationAttribute, deadline)

	local sold = {}
	for _, stand in self._stands do
		table.insert(sold, tostring(stand.body))
	end
	self.log:info(string.format("Car deals rolled: %s.", table.concat(sold, ", ")))
end

--[[ The rotation loop. `task.wait` in a spawned thread rather than a Heartbeat accumulator, the
	same shape and the same reason as `TipsService._loop`: this fires every five MINUTES, and sixty
	comparisons a second to measure that is work for nothing.

	The flag rather than `task.cancel`, because the thread is almost always parked inside the wait
	when a teardown lands and cancelling a thread mid-wait is how a Trove throws during cleanup. ]]
function CarDealService._loop(self)
	local running = true

	task.spawn(function()
		task.wait(CarDealConfig.Offer.FirstDelay)
		while running do
			self:_roll()
			task.wait(CarDealConfig.Offer.Interval)
		end
	end)

	return function()
		running = false
	end
end

-- === Buying =================================================================

--[[ Hand the buyer the car they just paid for, in the bay it was standing in, with them in it.

	IT IS ONE CALL AND EVERYTHING ELSE IS `LobbyCarService`'S. The rig, the paint, the plate, the
	doors, the collision group, the one-car-per-player rule and the despawn on death are the same
	code path a car spawned off the Cars Inventory screen goes down; the only thing this asks for
	that a screen does not is WHERE, and WHO to put in it.

	THE FRAME IS THE BAY'S OWN, and that is a stronger claim about the ground than the ordinary
	placement search could make: this spot was probed for road, flatness, clearance and room to pull
	out of before a car was ever parked on it, whereas the search rings candidates around a player
	who might be standing anywhere.

	THE DISPLAY CLONE GOES FIRST. It is anchored and query-blind so it would not block anything, but
	two cars occupying one bay for even a frame is a screenshot nobody wants to explain.

	A REFUSAL COSTS THE BUYER NOTHING. The car is already banked by the time this runs — `awardCar`
	returned before it — so a player whose lobby car could not be spawned still owns what they
	bought and finds it on their dealership screen. That is why this warns rather than trying to
	unwind anything: there is nothing here that can leave the purchase half done. ]]
function CarDealService._handover(self, player: Player, stand: Stand, key: string)
	local handover = CarDealConfig.Handover
	local LobbyCarService = Shard.get("LobbyCarService")
	if not LobbyCarService then
		self.log:warn("No LobbyCarService, so the car was banked but nobody drove it away.")
		return
	end

	local bay = stand.frame
	self:_clearOffer(stand)

	local ok, reason = LobbyCarService:setLobbyCar(player, key, {
		ground = bay,
		seat = handover.SeatBuyer,
		seatDelay = handover.SeatDelay,
	})
	if not ok then
		self.log:warn(string.format("%s bought %s but could not be put in it (%s).", player.Name, key, reason))
	end
end

--[[ Restock this one stall, on its own, after a sale.

	DELAYED, so the sign does not turn over on the same frame the buyer appears in the car they just
	bought. `Handover.RerollDelay` is what that beat is worth.

	RE-READS THE MARKET RATHER THAN CARRYING IT. Five minutes may have passed and the other stands
	may have rotated since; `_marketState` asks the stands what they are actually holding, so this
	cannot re-offer a body that is already out there in another lot.

	AND IT WILL NOT RE-OFFER WHAT WAS JUST SOLD. `sold` is the body that came off this bay a moment
	ago, and it is barred for the same reason no two bays may share one: a Golf GTI replaced by
	another Golf GTI one second later reads as the market being broken. It is barred for this roll
	only, so the next rotation may put it back out. ]]
function CarDealService._rerollAfterSale(self, stand: Stand, sold: string?)
	--[[ AND IT WAITS FOR THE BUYER TO DRIVE OFF. They are sitting in the car they just bought, in
		this stall, because that is what the handover does; restocking on top of them is the one
		thing a bay that no longer moves gets wrong for free. So the restock is held until the stall
		is empty, checked every `RestockWait` seconds and given up on after `RestockFor` — a stall
		somebody has parked in and walked away from is left dark until the next rotation, which reads
		as a bay whose car has gone rather than as two cars in one space. ]]
	local handover = CarDealConfig.Handover
	local deadline = os.clock() + handover.RestockFor
	while self:_stallTaken(stand) do
		if not stand.model.Parent then
			return
		end
		if os.clock() > deadline then
			self.log:info(string.format("Bay %d is still occupied; it waits for the next rotation.", stand.index))
			return
		end
		task.wait(handover.RestockWait)
	end

	local taken = self:_marketState(stand)
	if sold then
		taken[sold] = true
	end
	if not self:_rollStand(stand, taken) then
		self.log:warn(string.format("Stand %d could not be restocked after a sale.", stand.index))
	end
end

--[[ Somebody held the button on a bay.

	EVERY GATE IS HERE AND NONE OF THEM IS ON THE CLIENT. The bubble draws what it can (it greys the
	price when you cannot afford it and says ALREADY YOURS when you own it), but that is a courtesy:
	a press that arrives here is checked from scratch against the profile, and the attributes it is
	checked against are the server's own.

	THE ORDER MATTERS AND IT IS: check, take the money, hand over the car, then put them in it. By
	the time the money moves, `awardCar` has nothing left to reject on — it refuses only a body/tier
	pair the roster does not have, a profile that has not loaded, or a disabled garage, and all three
	are gates above. So there is no window in which cash has left and no car arrived. Reversing the
	two would leave the opposite window, which is the one that costs the player nothing and the game
	everything.

	AND THE DRIVE-AWAY IS LAST, AFTER THE SIGNALS. Everything above it is the purchase and everything
	below it is chrome, however good the chrome is: a quest counting a buy, an analytics funnel and
	the client's own celebration all fire off a car that is already in the collection, whether or not
	the rig that was about to be parked in the bay ever appears.

	Refusals are silent (header note 6). ]]
function CarDealService._onTriggered(self, stand: Stand, player: Player)
	--[[ `GarageConfig.Enabled` IS CHECKED HERE AS WELL AS THE MARKET'S OWN SWITCH, and it is not
		belt-and-braces: with the garage off, `addCash` still moves money while `awardCar` returns
		"rejected" — which is the one ordering in this whole file that could take a payment and hand
		back nothing. One line, at the top, where it cannot be reordered into a hole. ]]
	if not (CarDealConfig.Enabled and GarageConfig.Enabled) then
		return
	end

	local now = os.clock()
	local last = self._cooldowns[player]
	if last and now - last < CarDealConfig.Prompt.Cooldown then
		return
	end
	self._cooldowns[player] = now

	local GarageService = Shard.get("GarageService")
	if not (GarageService and GarageService:isProfileReady(player)) then
		return
	end

	local attrs = CarDealConfig.Attributes
	local body = stand.model:GetAttribute(CarDealConfig.stockAttribute(attrs.Body, WorldConfig.highestUnlocked(player)))
	local tier = stand.model:GetAttribute(CarDealConfig.stockAttribute(attrs.Tier, WorldConfig.highestUnlocked(player)))
	local paint = stand.model:GetAttribute(CarDealConfig.stockAttribute(attrs.Paint, WorldConfig.highestUnlocked(player)))
	local price = stand.model:GetAttribute(CarDealConfig.stockAttribute(attrs.Price, WorldConfig.highestUnlocked(player)))
	if type(body) ~= "string" or type(tier) ~= "number" or type(price) ~= "number" or price <= 0 then
		return
	end
	if GarageConfig.TierOfBody[body] ~= tier then
		--- The bay is mid-rotation, or somebody has edited it live. Either way this is not the car
		--- the player pressed on.
		return
	end

	if not WorldConfig.isUnlocked(WorldConfig.WorldOfBody[body], player) then return end
	local key = GarageConfig.carKey(body, PaintConfig.sanitize(body, paint))
	if CarDealConfig.Offer.RefuseOwned and GarageService:ownsModel(player, key) then
		return
	end

	--[[ TOO POOR IS THE ONE REFUSAL WITH AN ANSWER, so it is the one refusal that is not silent
		(header note 6 covers the rest, which stay silent because they are all "this is not the car
		you pressed on"). `CashService` opens Roblox's own purchase window for the cheapest cash pack
		that closes THIS GAP, and the press is still refused: nothing is held pending across a modal,
		and a player who buys presses the bay again. `CashConfig`'s header argues both halves.

		THE GAP AND NOT THE PRICE. Somebody a dollar short of a supercar is offered the smallest pack
		in the game, which is the entire reason an uninvited modal is defensible here. ]]
	local cash = GarageService:getCash(player)
	if cash < price then
		local CashService = Shard.get("CashService")
		if CashService then
			CashService:offerTopUp(player, price - cash, string.format("a %s on bay %d", body, stand.index))
		end
		return
	end

	GarageService:addCash(player, -price)
	local outcome, _, awardedId = GarageService:awardCar(player, tier, body, paint)
 if outcome == "rejected" or (not awardedId and outcome ~= "sold") then
  GarageService:addCash(player, price)
  return
 end
 key = awardedId

	self.log:info(string.format(
		"%s bought a %s %s (Tier %d) off stand %d for %d: %s.",
		player.Name,
		PaintConfig.nameOf(paint),
		body,
		tier,
		stand.index,
		price,
		outcome
	))

	self:getSignal("CarBought"):Fire(player, body, tier, paint, price, stand.index)
	self:getRemoteEvent("DealBought"):Fire(player, stand.index, body, price)

	if not CarDealConfig.Handover.Enabled then
		return
	end
	if awardedId then self:_handover(player, stand, awardedId) end
	if CarDealConfig.Handover.RerollOnSale then
		task.delay(CarDealConfig.Handover.RerollDelay, function()
			if stand.model.Parent then
				self:_rerollAfterSale(stand, body)
			end
		end)
	end
end

-- === Lifecycle ==============================================================

--[[ Stand the market up: find the island, read its car parks off the paint, build one bay in each,
	start the clock.

	IT RUNS ONCE AND IT IS NOT RETRIED. A map that could not be found is a place without the island
	in it, which is a much bigger problem than a missing market, and a retry loop against a
	`FindFirstChild` that will never succeed is a warning nobody reads repeated forever. ]]
function CarDealService._build(self)
	local map = workspace:FindFirstChild(PlotConfig.MapName)
	if not map then
		self.log:warn(string.format("No %s in Workspace, so no car deals will be built.", PlotConfig.MapName))
		return
	end
	self._map = map
	if map:IsA("Model") then
		local mapCF, mapSize = map:GetBoundingBox()
		self._mapTopY = mapCF.Position.Y + mapSize.Y / 2
		self._mapBottomY = mapCF.Position.Y - mapSize.Y / 2
	else
		--- `Map` is a Model today and `docs/MapLayout.md` §2 says why it stays one (so the island can
		--- be moved as a unit). A Folder has no bounding box, so the sweep falls back to one that
		--- covers any plausible island altitude rather than to a raycast that starts underground.
		self._mapTopY, self._mapBottomY = 1000, -1000
	end

	--[[ The ground probe's params, built once rather than per shot.

		INCLUDED ON THE MAP RATHER THAN EXCLUDING THINGS, so that a player standing in a lot, a car
		somebody parked in one, or this service's own display clone cannot be the answer to "how high
		is the ground here". Everything the two probes want to hit is a part of the map. ]]
	self._roadParams = RaycastParams.new()
	self._roadParams.FilterType = Enum.RaycastFilterType.Include
	self._roadParams.FilterDescendantsInstances = { map }
	self._roadParams.IgnoreWater = true

	local folder = Instance.new("Folder")
	folder.Name = CarDealConfig.FolderName
	folder.Parent = workspace
	self._folder = folder
	self._trove:Add(folder)

	self:_findLots()
	if #self._stalls == 0 then
		--[[ Nothing painted on this map that reads as a car park, so there is nowhere for a deal to
			stand. IT DOES NOT FALL BACK TO SCATTERING BAYS ON OPEN ASPHALT: that is exactly what
			this replaced, and a market that quietly reverts to the thing the user asked to be rid of
			is worse than a market that says it is off. `CarDealConfig.Lots` names what to paint. ]]
		self.log:warn("No car parks found in the map and no parts tagged CarDealSpot, so the market is off for this server. See CarDealConfig.Lots.SpotTag.")
		return
	end

	--- ONE STAND PER LOT, in the order `_findLots` numbered them, and each stays where it is built.
	for index, stall in self._stalls do
		table.insert(self._stands, self:_buildStand(index, stall))
	end
	self.log:info(string.format("%d car deal bays built, one per car park.", #self._stands))

	self._trove:Add(self:_loop())
end

CarDealService:withLifecycle({
	init = function(self)
		self._stands = {} :: { Stand }
		--- One stall per car park, found once in `_build` and never added to: the frame a stand is
		--- built on and the size of the paint around it.
		self._stalls = {} :: { Stall }
		self._folder = nil :: Folder?
		self._map = nil :: Instance?
		--- The map's own vertical extent, measured once in `_build`. See `_groundAt`.
		self._mapTopY = 0
		self._mapBottomY = 0
		self._roadParams = nil :: RaycastParams?
		--- Per player, so one person mashing the button cannot cost anybody else their press.
		self._cooldowns = {} :: { [Player]: number }
		--[[ Its own generator rather than the global `math.random`, so the market's draw can neither
			be perturbed by — nor perturb — anything else rolling in this server. Unseeded, i.e.
			seeded from the clock: two servers starting together stand different cars in the same
			four lots, which is the only variety left now that the lots themselves are fixed. ]]
		self._rng = Random.new()
		self._trove = Trove.new()
	end,

	start = function(self)
		if not CarDealConfig.Enabled then
			self.log:info("Disabled by config; no car deals.")
			return
		end

		self._trove:Add(Players.PlayerRemoving:Connect(function(player: Player)
			self._cooldowns[player] = nil
		end))

		--[[ Spawned rather than awaited: `Shard.start()` is the server's boot barrier and nothing
			else waits on the market existing. `_build` is much cheaper than the search it replaced —
			a size test over the paint and a handful of rays — but it still walks a folder of a
			43,000-part map, and boot is not the place to make anything wait for that. ]]
		task.spawn(function()
			self:_build()
		end)
	end,
})

CarDealService:withCleanup(function()
	if CarDealService._trove then
		CarDealService._trove:Destroy()
	end
	for _, tagged in CollectionService:GetTagged(CarDealConfig.Tag) do
		tagged:Destroy()
	end
end)

-- Unlocked-world dealer stock, 2026-10-04.
function CarDealService._rollStand(self, stand: Stand, taken: {[string]: boolean}): boolean
 local attrs = CarDealConfig.Attributes
 local valid = false
 -- Five independent unlock cohorts. A joining beginner never restricts a veteran's stock.
 -- All purchase inputs remain server attributes; client display writes replicate nowhere.
 for highest = 1, #WorldConfig.Worlds do
  local used = {}
  for _, other in self._stands do
   if other ~= stand then
    local body = other.model:GetAttribute(CarDealConfig.stockAttribute(attrs.Body, highest))
    if body then used[body] = true end
   end
  end
  local offer = nil
  for _ = 1, CarDealConfig.Offer.MaxRerolls do
   local body, tier = CarDealConfig.rollBody(self._rng, used, highest)
   if not body then break end
   local paint = PaintConfig.roll(self._rng, body)
   local model, displayOffsets, extents = CarDisplay.build(body, paint, {
    rosterFolder = GarageConfig.Display.RosterFolderName,
    bodyFolder = GarageConfig.Display.BodyFolderName,
    hitBoxName = GarageConfig.Display.HitBoxName,
    name = CarDealConfig.Names.Car,
    castShadow = CarDealConfig.Car.CastShadow,
   })
   if model then
    if extents.maxX - extents.minX <= stand.width and extents.maxZ - extents.minZ <= stand.depth then
     offer = {body = body, tier = tier, paint = paint, price = CarDealConfig.priceFor(tier, self._rng:NextNumber(-1, 1))}
     local templates = ReplicatedStorage:FindFirstChild("CarDealDisplayTemplates")
     if not templates then templates = Instance.new("Folder"); templates.Name = "CarDealDisplayTemplates"; templates.Parent = ReplicatedStorage; self._trove:Add(templates) end
     local name = tostring(stand.index) .. "_" .. tostring(highest)
     local previous = templates:FindFirstChild(name)
     if previous then previous:Destroy() end
     -- Publish only the finished, anchored dress. The full roster stays in ServerStorage.
     local width, length = extents.maxX - extents.minX, extents.maxZ - extents.minZ
     local yaw = CarDisplay.fitYaw(width, length, stand.width, stand.depth, CarDealConfig.Car.Yaw)
     local radians = math.rad(yaw)
     local along = math.abs(length * math.cos(radians)) + math.abs(width * math.sin(radians))
     local backOff = math.max(0, stand.depth / 2 - along / 2 - CarDealConfig.Bay.HeadGap)
     local centre = (stand.frame * CFrame.new(0, 0, backOff)).Position
     -- Re-express the anchored parts; no chassis, scripts or source-roster joints replicate.
     -- The retained model must use its own part-offset map, supplied by the build above.
     CarDisplay.place(displayOffsets, CarDisplay.standOn(extents, centre, stand.frame.Position.Y, stand.frame * CFrame.Angles(0, radians, 0), CarDealConfig.Car.Lift))
     model.Name = name
     model:SetAttribute("StockBody", body); model:SetAttribute("StockPaint", paint)
     model:SetAttribute("StandFrame", stand.frame)
     model.Parent = templates
     break
    end
    model:Destroy()
   end
  end
  for _, pair in {{attrs.Body, "body"}, {attrs.Tier, "tier"}, {attrs.Paint, "paint"}, {attrs.Price, "price"}} do
   stand.model:SetAttribute(CarDealConfig.stockAttribute(pair[1], highest), if offer then offer[pair[2]] else nil)
  end
  if offer then
   valid = true
   if highest == 1 then
    stand.body = offer.body
    -- Legacy attributes support inspection. Each client paints its cohort car locally.
    stand.model:SetAttribute(attrs.Body, offer.body)
    stand.model:SetAttribute(attrs.Paint, offer.paint)
    stand.model:SetAttribute(attrs.Tier, offer.tier)
    stand.model:SetAttribute(attrs.Price, offer.price)
   end
  end
 end
 local old = stand.model:FindFirstChild(CarDealConfig.Names.Car)
 if old then old:Destroy() end
 stand.prompt.Enabled = valid
 return valid
end

return CarDealService
