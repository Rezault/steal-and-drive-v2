--[[
	GuideTrailModern
	----------------
	A STRIP OF RACING TRACK PAINTED ON THE FLOOR from the player to the bay, along the route a person
	can actually walk: dark asphalt between red and white kerbs, gold chevrons flowing down the middle
	towards the bay, and a chequered finish line across it where it reaches the deck. `GuideTrailConfig`
	has the why and the numbers; `GuideTrailController` decides when it is drawn and at which bay.

	=== HOW THE ROUTE BECOMES A STRIP ==========================================================

	  1. `PathfindingService` plans the walk from the player's root to the top of the deck.
	  2. Corner cutting (`Smoothing` passes) rounds pathfinding's elbows into bends.
	  3. The route is cut where it first crosses into the deck's footprint, which is where the finish
	     line goes. The strip stops at the bay's edge instead of climbing onto the slab.
	  4. It is resampled to equal segments (`Segment`, rounded so they divide it exactly), and each
	     sample is dropped onto the floor by a ray, so it follows steps and thresholds.
	  5. Each segment is two flat Beams between a pair of attachments: the track, and the chevron on
	     top of it.

	=== WHY EVERY SEGMENT IS THE SAME LENGTH ===================================================

	It is what makes forty separate Beams read as one strip. Each beam's texture is STRETCHED to fit it
	exactly once (`TextureLength` 1), so equal segments mean equal kerb blocks and equal chevrons, and a
	chevron that scrolls off the end of one segment is met by the next one's scrolling on, on the same
	frame, because every chevron beam is put back in phase (`SetTextureOffset`) whenever the strip is
	laid. Unequal segments would show as a chevron stuttering at every joint.

	THE JOINTS ARE CURVES, NOT CORNERS. Every attachment's +X is the route's tangent at that point and
	each beam's curve sizes are a third of its length, which makes the chain a smooth spline through
	the samples rather than a polyline: the beams meet edge to edge with no wedge-shaped gap on a bend.

	THE WIDTH LIES FLAT because a Beam's width runs along its attachments' +Y, and +Y is laid sideways
	across the route here. See the `beam-width-follows-attachment-y` note: with +Y pointing up the strip
	would stand on its edge and be invisible from above.

	=== IT IS EATEN FROM THE NEAR END, NOT RECOMPUTED ==========================================

	A player walking along the strip never causes a new path. Each frame finds how far along the strip
	they are and fades it in from there (`FadeStuds`), so what is behind them is gone and what is ahead
	of them stays put. A route is only planned again when the bay changes or the player strays more than
	`OffPath` studs off it, and never more often than `Recompute`. A strip that re-planned while you
	followed it would shiver under your feet.
]]

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GuideTrailConfig = require(ReplicatedStorage.shared.Configs.GuideTrailConfig)

local GuideTrailModern = {}
GuideTrailModern.__index = GuideTrailModern

--[[ Opacity is written in this many steps per segment end. A NumberSequence is an allocation, so a
	segment only gets a new one when one of its two ends crosses a step, and the sequences themselves
	are made once per pair of steps and shared (`_sequence`). ]]
local LEVELS = 8

--- How far above a sample the floor ray starts, and how far it looks down.
local RAY_UP = 2.5
local RAY_DOWN = 8

--- How far the finish line is pulled back out of the deck's footprint, so its floor ray lands on
--- the paving in front of the bay and not on the edge of the slab.
local FINISH_BACK = 0.35

--- Halvings when finding where the route crosses into the deck.
local EDGE_STEPS = 12

--- How many segments behind the last known position the "how far along" search starts. A little
--- backtracking is followed; a lot reads as off the route and plans a new one.
local SEARCH_BACK = 3

local function horizontal(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

--- Is `point` over the deck's footprint, grown by `margin` studs a side? Height is ignored.
local function overDeck(deck: BasePart, point: Vector3, margin: number): boolean
	local localPoint = deck.CFrame:PointToObjectSpace(point)
	return math.abs(localPoint.X) <= deck.Size.X / 2 + margin and math.abs(localPoint.Z) <= deck.Size.Z / 2 + margin
end
GuideTrailModern.overDeck = overDeck

--- One pass of Chaikin's corner cutting, keeping both ends where they are.
local function chaikin(points: { Vector3 }): { Vector3 }
	if #points < 3 then
		return points
	end
	local out = { points[1] }
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		table.insert(out, a:Lerp(b, 0.25))
		table.insert(out, a:Lerp(b, 0.75))
	end
	table.insert(out, points[#points])
	return out
end

--[[ Cut the route where it first crosses into the deck's footprint. Returns the route up to that edge
	and whether it got there at all: a route that ends short of the deck (a partial path, or the
	straight fallback) is drawn to wherever it ends, with no finish line. ]]
local function cutAtDeck(points: { Vector3 }, deck: BasePart): ({ Vector3 }, boolean)
	for i = 2, #points do
		if overDeck(deck, points[i], 0) then
			local a, b = points[i - 1], points[i]
			if overDeck(deck, a, 0) then
				--- The route starts on the deck: the player is already there.
				return { a }, true
			end
			local lo, hi = 0, 1
			for _ = 1, EDGE_STEPS do
				local mid = (lo + hi) / 2
				if overDeck(deck, a:Lerp(b, mid), 0) then
					hi = mid
				else
					lo = mid
				end
			end
			local edge = a:Lerp(b, lo)
			local back = horizontal(a - edge)
			if back.Magnitude > 1e-3 then
				edge += back.Unit * math.min(FINISH_BACK, back.Magnitude)
			end
			local out = table.move(points, 1, i - 1, 1, {})
			table.insert(out, edge)
			return out, true
		end
	end
	return points, false
end

--- The route resampled to equal steps, the nearest length to `segment` that divides it exactly.
local function resample(points: { Vector3 }, segment: number): { Vector3 }
	local total = 0
	for i = 2, #points do
		total += (points[i] - points[i - 1]).Magnitude
	end
	if total < 1e-3 then
		return { points[1] }
	end

	local count = math.max(1, math.floor(total / segment + 0.5))
	local step = total / count
	local out = { points[1] }
	local index, walked = 2, 0
	for k = 1, count - 1 do
		local want = k * step
		while index <= #points do
			local length = (points[index] - points[index - 1]).Magnitude
			if walked + length >= want then
				break
			end
			walked += length
			index += 1
		end
		local a, b = points[index - 1], points[index]
		local length = (b - a).Magnitude
		table.insert(out, if length > 1e-6 then a:Lerp(b, (want - walked) / length) else a)
	end
	table.insert(out, points[#points])
	return out
end

local function flatBeam(name: string, texture: string, width: number, zOffset: number): Beam
	local beam = Instance.new("Beam")
	beam.Name = name
	beam.FaceCamera = false
	beam.Texture = texture
	beam.TextureMode = Enum.TextureMode.Stretch
	beam.TextureLength = 1
	beam.TextureSpeed = 0
	beam.Width0 = width
	beam.Width1 = width
	beam.LightInfluence = 0
	beam.LightEmission = 0
	beam.Segments = 6
	beam.ZOffset = zOffset
	beam.Enabled = false
	return beam
end

function GuideTrailModern.new()
	local cfg = GuideTrailConfig.Modern
	local self = setmetatable({}, GuideTrailModern)

	self._path = PathfindingService:CreatePath(cfg.Agent)
	--- Attachments on Terrain, one per sample, grown as routes get longer and never shrunk.
	self._joints = {} :: { Attachment }
	--- Per segment: the track beam and the chevron beam, between joints i and i + 1.
	self._track = {} :: { Beam }
	self._chevrons = {} :: { Beam }
	--- Per segment: the opacity step pair it was last written with, so unchanged ones are skipped.
	self._written = {} :: { number }
	self._sequences = {} :: { [number]: NumberSequence }

	--- The route as laid: samples, the distance along it at each, and the segment count drawn.
	self._points = {} :: { Vector3 }
	self._along = {} :: { number }
	self._segments = 0
	self._reached = false

	self._deck = nil :: BasePart?
	self._token = 0
	self._computing = false
	self._dirty = false
	self._lastPlan = -math.huge
	--- Index of the segment the player was last nearest, for the forward search.
	self._near = 1
	--- How far out the strip has drawn itself since it last appeared. Huge = fully drawn.
	self._reveal = 0
	self._shown = false

	local finishA = Instance.new("Attachment")
	finishA.Name = "GuideFinishA"
	finishA.Parent = workspace.Terrain
	local finishB = Instance.new("Attachment")
	finishB.Name = "GuideFinishB"
	finishB.Parent = workspace.Terrain
	local finish = flatBeam("GuideFinish", cfg.Textures.Finish, cfg.FinishDepth, 0.08)
	finish.Attachment0 = finishA
	finish.Attachment1 = finishB
	finish.Parent = finishA
	self._finishA, self._finishB, self._finish = finishA, finishB, finish

	return self
end

-- === Planning ===============================================================

function GuideTrailModern._rayParams(self): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	--- Characters (and the car in somebody's hands) are not floor.
	local skip = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(skip, player.Character)
		end
	end
	params.FilterDescendantsInstances = skip
	return params
end

--- Ask for a new route, from `root` to `deck`. Runs on its own thread; a newer ask wins.
function GuideTrailModern._plan(self, root: Vector3, deck: BasePart)
	if self._computing then
		self._dirty = true
		return
	end
	self._computing = true
	self._dirty = false
	self._lastPlan = os.clock()
	self._token += 1
	local token = self._token

	task.spawn(function()
		local goal = deck.Position + Vector3.yAxis * (deck.Size.Y / 2)
		local ok = pcall(self._path.ComputeAsync, self._path, root, goal)
		if self._token ~= token or self._destroyed then
			return
		end
		self._computing = false
		--- The bay changed while this was planning. `_dirty` is already up, so the next frame asks again.
		if deck ~= self._deck then
			return
		end

		local route = {}
		if ok and self._path.Status == Enum.PathStatus.Success then
			for _, waypoint in self._path:GetWaypoints() do
				table.insert(route, waypoint.Position)
			end
		end
		--[[ No route a person could walk: draw it straight, because a wrong turn is still a direction,
			and keep asking (`_straight`), because the usual cause is passing, like a jump in progress
			putting the start in mid air. ]]
		self._straight = #route < 2
		if self._straight then
			route = { root, goal }
		end
		self:_lay(route, deck)
	end)
end

--- Turn a planned route into the strip. See the header for the five steps.
function GuideTrailModern._lay(self, route: { Vector3 }, deck: BasePart)
	local cfg = GuideTrailConfig.Modern

	for _ = 1, cfg.Smoothing do
		route = chaikin(route)
	end
	local reached
	route, reached = cutAtDeck(route, deck)
	local samples = resample(route, cfg.Segment)

	local params = self:_rayParams()
	for i, point in samples do
		local hit = workspace:Raycast(point + Vector3.yAxis * RAY_UP, Vector3.yAxis * -RAY_DOWN, params)
		samples[i] = Vector3.new(point.X, (if hit then hit.Position.Y else point.Y) + cfg.Lift, point.Z)
	end

	local along = { 0 }
	for i = 2, #samples do
		along[i] = along[i - 1] + (samples[i] - samples[i - 1]).Magnitude
	end
	self._points, self._along, self._reached = samples, along, reached
	self._segments = #samples - 1
	self._near = 1

	local count = #samples
	for i = 1, count do
		local before = samples[math.max(1, i - 1)]
		local after = samples[math.min(count, i + 1)]
		local tangent = after - before
		if tangent.Magnitude < 1e-3 then
			tangent = Vector3.zAxis
		end
		tangent = tangent.Unit
		local side = tangent:Cross(Vector3.yAxis)
		side = if side.Magnitude > 1e-3 then side.Unit else Vector3.xAxis
		self:_joint(i).CFrame = CFrame.fromMatrix(samples[i], tangent, side)
	end

	--[[ ONE RATE FOR EVERY CHEVRON, off the average segment. The floor rays make each segment's true
		length differ by a hair, and a rate per segment would let them drift out of step within a minute. ]]
	local cycles = if self._segments > 0 then cfg.Speed / math.max(along[count] / self._segments, 1e-3) else 0
	for i = 1, self._segments do
		local track, chevron = self:_segment(i)
		local third = (along[i + 1] - along[i]) / 3
		track.CurveSize0, track.CurveSize1 = third, third
		chevron.CurveSize0, chevron.CurveSize1 = third, third
		chevron.TextureSpeed = cycles
		self._written[i] = -1
	end
	for i = self._segments + 1, #self._track do
		self._track[i].Enabled = false
		self._chevrons[i].Enabled = false
	end
	--- Every chevron back in step, so the flow is unbroken across the joints. See the header.
	for i = 1, self._segments do
		self._chevrons[i]:SetTextureOffset(0)
	end

	self:_layFinish()
end

function GuideTrailModern._layFinish(self)
	local cfg = GuideTrailConfig.Modern
	local count = #self._points
	if not (cfg.Finish and self._reached and count >= 2) then
		self._finish.Enabled = false
		return
	end
	local last, prev = self._points[count], self._points[count - 1]
	local tangent = horizontal(last - prev)
	tangent = if tangent.Magnitude > 1e-3 then tangent.Unit else Vector3.zAxis
	local side = tangent:Cross(Vector3.yAxis).Unit
	local centre = last - tangent * (cfg.FinishDepth / 2)
	local reach = cfg.Width / 2 + cfg.FinishOverhang
	--- Running ACROSS the route (+X along `side`), with its width along the route (+Y the tangent).
	self._finishA.CFrame = CFrame.fromMatrix(centre - side * reach, side, tangent)
	self._finishB.CFrame = CFrame.fromMatrix(centre + side * reach, side, tangent)
end

function GuideTrailModern._joint(self, i: number): Attachment
	local joint = self._joints[i]
	if not joint then
		joint = Instance.new("Attachment")
		joint.Name = "GuideJoint"
		joint.Parent = workspace.Terrain
		self._joints[i] = joint
	end
	return joint
end

function GuideTrailModern._segment(self, i: number): (Beam, Beam)
	local track = self._track[i]
	if not track then
		local cfg = GuideTrailConfig.Modern
		local a, b = self:_joint(i), self:_joint(i + 1)
		track = flatBeam("GuideTrack", cfg.Textures.Track, cfg.Width, 0)
		track.Attachment0, track.Attachment1 = a, b
		track.Parent = a
		local chevron = flatBeam("GuideChevron", cfg.Textures.Chevron, cfg.ChevronWidth, 0.04)
		chevron.Color = ColorSequence.new(cfg.ChevronColor)
		chevron.Attachment0, chevron.Attachment1 = a, b
		chevron.Parent = a
		self._track[i] = track
		self._chevrons[i] = chevron
	end
	return track, self._chevrons[i]
end

-- === Drawing ================================================================

--- The shared sequence for one segment whose two ends are at opacity steps `a` and `b`.
function GuideTrailModern._sequence(self, a: number, b: number): NumberSequence
	local key = a * (LEVELS + 1) + b
	local sequence = self._sequences[key]
	if not sequence then
		sequence = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1 - a / LEVELS),
			NumberSequenceKeypoint.new(1, 1 - b / LEVELS),
		})
		self._sequences[key] = sequence
	end
	return sequence
end

--[[ How far along the strip the player's feet are, and how far off it. Searched forward from where
	they were last, so a route that bends back on itself is not jumped along. ]]
function GuideTrailModern._locate(self, feet: Vector3): (number, number)
	local points, along = self._points, self._along
	local bestAlong, bestOff, bestIndex = 0, math.huge, self._near
	for i = math.max(1, self._near - SEARCH_BACK), self._segments do
		local a, b = points[i], points[i + 1]
		local ab = b - a
		local lengthSquared = ab:Dot(ab)
		local t = if lengthSquared > 1e-6 then math.clamp((feet - a):Dot(ab) / lengthSquared, 0, 1) else 0
		local off = (feet - (a + ab * t)).Magnitude
		if off < bestOff then
			bestOff, bestIndex = off, i
			bestAlong = along[i] + (along[i + 1] - along[i]) * t
		end
	end
	self._near = bestIndex
	return bestAlong, bestOff
end

--[[ Draw the strip from a character at `root` / `feet` to `deck`, at overall opacity `alpha`. Called
	every frame while it is up; `hide` takes it down. ]]
function GuideTrailModern.draw(self, root: Vector3, feet: Vector3, deck: BasePart, alpha: number, dt: number)
	local cfg = GuideTrailConfig.Modern

	if deck ~= self._deck then
		self._deck = deck
		self._segments = 0
		self._finish.Enabled = false
		for i = 1, #self._track do
			self._track[i].Enabled = false
			self._chevrons[i].Enabled = false
		end
		self._lastPlan = -math.huge
	end

	local now = os.clock()
	local due = now - self._lastPlan >= cfg.Recompute
	if self._segments == 0 then
		if due or self._dirty then
			self:_plan(root, deck)
		end
		return
	end

	local here, off = self:_locate(feet)
	if (off > cfg.OffPath or self._dirty or self._straight) and due then
		self:_plan(root, deck)
	end

	if not self._shown then
		--[[ Coming back up somewhere the kept route does not start (home from a run, a respawn): wait
			for the new one rather than drawing the old one for a frame. ]]
		if off > cfg.OffPath then
			return
		end
		self._shown = true
		self._reveal = here
	end
	self._reveal += cfg.DrawSpeed * dt

	local along = self._along
	for i = 1, self._segments do
		local from, to = along[i], along[i + 1]
		local track, chevron = self._track[i], self._chevrons[i]
		local visible = to > here and from < self._reveal
		if not visible then
			if track.Enabled then
				track.Enabled = false
				chevron.Enabled = false
				self._written[i] = -1
			end
			continue
		end
		local a = math.floor(alpha * math.clamp((from - here) / cfg.FadeStuds, 0, 1) * LEVELS + 0.5)
		local b = math.floor(alpha * math.clamp((to - here) / cfg.FadeStuds, 0, 1) * LEVELS + 0.5)
		local key = a * (LEVELS + 1) + b
		if self._written[i] ~= key then
			self._written[i] = key
			local sequence = self:_sequence(a, b)
			track.Transparency = sequence
			chevron.Transparency = sequence
		end
		if not track.Enabled then
			track.Enabled = true
			chevron.Enabled = true
		end
	end

	local finishShown = cfg.Finish and self._reached and self._reveal >= along[#along]
	if finishShown then
		local level = math.floor(alpha * LEVELS + 0.5)
		local key = level * (LEVELS + 1) + level
		if self._finishWritten ~= key then
			self._finishWritten = key
			self._finish.Transparency = self:_sequence(level, level)
		end
	end
	self._finish.Enabled = finishShown
end

--- Take it down. The route is kept, so coming straight back up (a flicker of the hands) is free; the
--- draw-out plays again because it is a new appearance.
function GuideTrailModern.hide(self)
	self._shown = false
	self._finish.Enabled = false
	self._finishWritten = nil
	for i = 1, #self._track do
		self._track[i].Enabled = false
		self._chevrons[i].Enabled = false
		self._written[i] = -1
	end
end

function GuideTrailModern.destroy(self)
	self._destroyed = true
	self._token += 1
	for _, joint in self._joints do
		joint:Destroy()
	end
	self._finishA:Destroy()
	self._finishB:Destroy()
	self._path:Destroy()
end

return GuideTrailModern
