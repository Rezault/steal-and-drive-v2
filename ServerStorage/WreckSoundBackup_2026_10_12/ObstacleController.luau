--[[
	ObstacleController  (client)
	----------------------------
	Builds the obstacle course into the driver's own local road, notices when the car
	clips something, and sells the impact.

	It lives on the client for the same reason the road does (RoadController): driving is
	solo, so every driver owns their own copy of the world and nothing here replicates.
	Obstacles are cloned from nothing — they're built from ObstacleConfig at runtime — and
	their layout comes from the race seed via ObstacleLayout, which the server can re-derive
	to police the damage. So: geometry is local, HP is server-authoritative.

	Tile bookkeeping is deliberately dumb. Each obstacle folder is parented INSIDE its road
	tile, and RoadController stamps every tile with a `TileIndex`, so:
	  • recycling a tile to the front changes its TileIndex → we rebuild its obstacles for
	    the new stretch of road,
	  • a world rebase moves the tile with Model:PivotTo → obstacles ride along for free,
	    and no coordinate bookkeeping can drift out of sync with the road.
	Every frame we just compare each tile's TileIndex against what we last built for it.

	Nothing built here collides (see ObstacleConfig's header): a hit is detected by polling
	one GetPartsInPart against the car's HitBox, and the "crash" is entirely scripted —
	speed cut, sideways shove, yaw kick, camera shake, and the thing you hit thrown or
	broken apart over the bonnet (`_smash`). That keeps the tuned CarBones physics
	untouched and makes the feel a config change.

	Impact/wreck physics lives here rather than in a HUD or road module because this is the
	one client-side place that already owns "things that happen to the car you're driving".

	IT ALSO DRAWS THE ROAD PICKUPS, and by the same logic that put everything else here: a health or
	nitro pack IS an obstacle structurally (`PickupConfig` argues this at length) — a seeded position,
	a lane, a hit volume and an id that may be claimed once — so it arrives through the layout, gets
	built by `_buildObstacle`, and is noticed by the same one-query hit poll. Three small branches
	carry it: `_buildPickup` for the glowing core and its billboard, `_updatePickups` for the bob and
	spin (held in the tile's frame, exactly like the tumbleweed's sweep), and one arm of `_onHit`.

	WHAT IT DOES NOT DO is decide what a pack is worth. That is `PickupController`'s screen and
	`ObstacleService`'s slot; this file reports the id and plays the local pop, the same division it
	already makes for damage.

	AND IT LAYS THE RAIN'S PUDDLES, the one thing here the server knows nothing about. While the sky
	`WeatherController` is drawing has `Puddles`, each tile gets a few in a folder of their own beside
	its course (`_reconcilePuddles`), placed by `ObstacleLayout.puddlesFor` and built by the same
	`_buildObstacle`. A hit is felt here and never reported (`Local`), and it is water rather than a
	crash (`_splash`). `ObstacleConfig.Puddles` has the reasoning.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local ObstacleConfig = require(ReplicatedStorage.shared.Configs.ObstacleConfig)
--- Which of the delivered collision effects to play, and whether they replace the old puff/plume.
local CrashVfxConfig = require(ReplicatedStorage.shared.Configs.CrashVfxConfig)
--- What a hit and a wreck sound like. See `_crashSound`.
local CrashSoundConfig = require(ReplicatedStorage.shared.Configs.CrashSoundConfig)
--- For its `Cause` alone: the one wreck whose car was never damaged. See `_onWrecked`.
local PoliceConfig = require(ReplicatedStorage.shared.Configs.PoliceConfig)
--- For the pack BODY and its collect beat only. What a pack is worth, and the slot it goes into,
--- are `PickupController`'s and the server's; this file only draws one and notices you drove
--- through it.
local PickupConfig = require(ReplicatedStorage.shared.Configs.PickupConfig)
local ObstacleLayout = require(ReplicatedStorage.shared.Modules.ObstacleLayout)
local TimeScale = require(ReplicatedStorage.shared.Modules.TimeScale)
--- For `puddlesOf` alone: whether the weather this run is being driven in leaves water on the road.
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local ObstacleController = Shard.new("ObstacleController"):withDependencies({ "RoadController" })

-- How fast the camera shake bleeds off (magnitude per second). The biggest hit is ~1.6,
-- so ~5 puts every shake under a third of a second.
local SHAKE_DECAY = 5
-- Wrecked cars coast to a stop: horizontal velocity is multiplied by e^(-dt*this) each
-- frame (framerate-independent), so ~1s to standstill. Vertical is left to gravity.
local WRECK_DAMP = 3

--- A `{ min, max }` pair or one number, as the range an emitter wants. The same reading
--- `CarMutation` gives a spec's `Speed`. For the puddle's ripples and spray.
local function rangeOf(value: unknown, fallback: number): NumberRange
	if type(value) == "table" and type(value[1]) == "number" and type(value[2]) == "number" then
		return NumberRange.new(math.min(value[1], value[2]), math.max(value[1], value[2]))
	end
	return NumberRange.new(if type(value) == "number" then value else fallback)
end

--- A `{ birth, death }` pair or one number, as a sequence across a particle's life.
local function sequenceOf(value: unknown, fallback: number): NumberSequence
	if type(value) == "table" and type(value[1]) == "number" and type(value[2]) == "number" then
		return NumberSequence.new(value[1], value[2])
	end
	return NumberSequence.new(if type(value) == "number" then value else fallback)
end

--[[ Dress a puddle's art parts in a sky's `Water` look (`WeatherConfig`'s `Puddles` block), or back in
	the art's own when `water` is nil. `parts` is the record `_dressPuddle` took of each part as it was
	delivered, so going back is exact rather than a guess at what the prop looked like. ]]
local function styleWater(parts: { any }, water: any)
	for _, rec in parts do
		local part = rec.part
		part.Material = if water and water.Material then water.Material else rec.material
		part.Color = if water and water.Color then water.Color else rec.color
		part.Transparency = if water and water.Transparency then water.Transparency else rec.transparency
		part.Reflectance = if water and water.Reflectance then water.Reflectance else rec.reflectance
	end
end

-- === Building ===============================================================

--[[ This world's published prop for a kind, or nil to build the kind from primitives instead.

	Resolved per race rather than at boot because the folder is per MAP and the map is per player
	(see WorldConfig): the answer changes when the driver picks a different world. Cached per kind
	for the race — including the misses, as `false`, since a kind with no art is the common case
	while the art lands one world at a time and it would otherwise re-walk the folder for every
	cone on every tile. ]]
function ObstacleController._prop(self, kindName: string): Model?
	local folder = self._propFolder
	if not folder then
		return nil
	end
	local cached = self._props[kindName]
	if cached == nil then
		-- The folder is the whole answer: it is rebuilt every server startup and only ever holds
		-- kinds that have art, each named for its kind.
		cached = folder:FindFirstChild(kindName) or false
		self._props[kindName] = cached
	end
	return cached or nil
end

--[[ One obstacle: an invisible query volume (the only part that answers the hit poll) plus
	either this world's prop art or the purely decorative parts from the kind's `Build` list.

	`base` is the obstacle's frame on the deck, with local +X across the road, +Y up and
	+Z down the road, so config offsets/sizes read the way they're written. It is handed back
	alongside the model because a kind with `Roll` has to be re-placed against it every frame
	(see `_updateRollers`), and re-deriving it there would mean re-deriving the whole lane. ]]
function ObstacleController._buildObstacle(self, parent: Instance, item, info, basePos: Vector3): (Model?, CFrame?)
	local kind = ObstacleConfig.Kinds[item.kind]
	if not kind then
		self.log:warn(string.format("Course '%s' wants unknown obstacle kind '%s'.", item.course, tostring(item.kind)))
		return nil
	end

	local rootPos = info.cross * (info.driveCenter + item.laneOffset)
		+ Vector3.yAxis * basePos.Y
		+ info.forward * (basePos:Dot(info.forward) + item.along)
	local base = CFrame.fromMatrix(rootPos, info.cross, Vector3.yAxis)

	local model = Instance.new("Model")
	model.Name = "Obstacle_" .. item.id

	local volume = Instance.new("Part")
	volume.Name = "Hit"
	volume.Size = kind.HitSize
	volume.CFrame = base * CFrame.new(0, kind.HitSize.Y * 0.5, 0)
	volume.Anchored = true
	volume.Transparency = 1
	volume.CastShadow = false
	volume.CanCollide = false -- never fights the car's physics
	volume.CanTouch = false -- we poll instead of using Touched
	volume.CanQuery = true -- ...so this is the one thing the poll can see
	volume:SetAttribute("ObstacleId", item.id)
	volume:SetAttribute("ObstacleKind", item.kind)
	volume.Parent = model
	model.PrimaryPart = volume

	--[[ The prop is published pivoted on the centre of its own footprint (ObstacleService
		._fitProp), so `base` — which is that same point on the deck — places it with one call and
		no per-kind offset. It arrives already anchored, inert and welded into one assembly, which
		is what lets `_smash` throw it as a single object — or, for a kind that asks to break, cut
		those welds and throw its pieces separately.

		Note this falls THROUGH to the shared `model.Parent` below rather than returning early:
		an obstacle that never gets attached to its tile folder is invisible, unhittable, and
		silent — the poll only ever queries those folders. ]]
	--[[ A PACK IS DRAWN HERE AND NOWHERE ELSE, and it takes neither branch below: it has no
		delivered art (and must not — see `PickupConfig`, a pack looks the same in every world so
		the glyph means one thing everywhere) and no primitive `Build` recipe either, because what
		it is made of is a nested `Cage` model — a tinted cube, a frame derived from that cube's own
		size, and a `BillboardGui` — none of which the flat `Build` offset list can express.
		Registered for the bob-and-spin on the way out; the hit volume above is already built and is
		what the poll sees, exactly as for any other kind. ]]
	if kind.Pickup then
		if not self:_buildPickup(model, base, kind.Pickup) then
			--- Dropped WHOLE rather than left as its bare hit volume, exactly as a kind with no art
			--- and no fallback is below: a volume with nothing inside it is an invisible thing that
			--- fills your pickup slot, which is worse than a gap in the course.
			model:Destroy()
			return nil
		end
		model.Parent = parent
		return model, base
	end

	local prop = self:_prop(item.kind)
	if prop then
		local clone = prop:Clone()
		clone:PivotTo(base)
		clone.Parent = model
	elseif not kind.Build then
		--[[ NOTHING TO DRAW. From world 2 on, a kind is authored against delivered art alone and
			carries no primitive recipe (ObstacleConfig's Kinds header), so this is what a missing
			or unpublished model looks like: no prop, no fallback.

			The obstacle is dropped whole rather than left as its bare hit volume, because a volume
			with nothing inside it is an invisible thing that takes 30 HP off you — far worse than
			a gap in the course. The server still has it in the layout and will still price a hit
			on it, but no hit can ever be reported for something that was never built.

			Warned once per kind: this fires per obstacle, and a missing wall kind is a dozen a
			tile. ]]
		if not self._warnedMissing[item.kind] then
			self._warnedMissing[item.kind] = true
			self.log:warn(
				string.format(
					"Obstacle kind '%s' has no art for this world and no primitive fallback; skipping it.",
					tostring(item.kind)
				)
			)
		end
		model:Destroy()
		return nil
	else
		--[[ Collected as they are made so they can be WELDED below. See the weld block for why a
			loose recipe is not good enough. ]]
		local built: { BasePart } = {}
		local root: BasePart? = nil
		for _, spec in kind.Build do
			local part = Instance.new("Part")
			part.Shape = Enum.PartType[spec.Shape or "Block"]
			part.Size = spec.Size
			local cf = base * CFrame.new(spec.Offset)
			if spec.Rotation then
				cf = cf
					* CFrame.fromOrientation(
						math.rad(spec.Rotation.X),
						math.rad(spec.Rotation.Y),
						math.rad(spec.Rotation.Z)
					)
			end
			part.CFrame = cf
			part.Color = spec.Color
			part.Material = spec.Material
			part.Transparency = spec.Transparency or 0
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			part.Parent = model
			table.insert(built, part)
			if not root or part.Size.Magnitude > root.Size.Magnitude then
				root = part
			end
		end

		--[[ ONE ASSEMBLY, exactly as `ObstacleService._fitProp` makes of a delivered prop, and for
			the same reason: `_smash` throws a hit obstacle by writing ONE velocity and ONE spin,
			and a spin only means "tumble this object" if the parts it is written on are a single
			body. Written on loose parts it means "spin each of these about its OWN centre", so any
			recipe whose parts sit at different offsets visibly separates as it flies -- the crate's
			dark band drifting out of its box, and before it the barrel's two hoops sliding off.

			WELDED WHILE ANCHORED, which costs nothing: anchored parts do not simulate, the joints
			just sit there until `_smash` unanchors the lot (and `Smash.Break` cuts them first for a
			kind that WANTS to come apart, so breaking still breaks). A star onto the biggest part
			rather than a chain, so the assembly survives any one piece being edited out of the
			recipe. ]]
		if root then
			for _, part in built do
				if part ~= root then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = root
					weld.Part1 = part
					weld.Parent = root
				end
			end
		end
	end

	model.Parent = parent
	return model, base
end

--[[ The body of a health or nitro pack: a transparent cube with glowing edges and the pack's glyph
	suspended inside it. `PickupConfig.Body` has the reasoning for that shape, for why the faces and
	the edges are both needed, and for why the colour painted on is not the pack's own.

	IT IS ITS OWN NESTED MODEL, named `Cage`, and that is what lets the float move it. The pack now
	has thirteen parts that must stay rigid to each other while `_updatePickups` re-poses them every
	frame; one `Model:PivotTo` on a nested model does that in a single call, where writing thirteen
	CFrames would cost twelve more per pack per frame and welding them would put an unanchored
	assembly on a tile that gets recycled underneath it.

	The HIT VOLUME IS NOT IN THE CAGE, deliberately -- it stays a direct child of the obstacle model,
	standing still on the deck, for the reason `_updatePickups` gives.

	Everything is parented under the obstacle Model that already holds the hit volume, so the pack is
	destroyed, recycled and rebased with its tile exactly like any other obstacle, and `_smash` can
	never be reached for it (`Pass` is checked before smashing).

	CanQuery FALSE on every part, like every other decorative part in this file: the hit poll is an
	Include query over the obstacle folders, and the one thing in there it is allowed to come back
	with is the `Hit` volume. A bar that answered the poll would report a hit with no `ObstacleId` on
	it -- and there are now twelve of them per pack, so this is twelve times as easy to get wrong as
	it was.

	Returns whether it drew anything, so the caller can drop an unbuildable pack whole. ]]
function ObstacleController._buildPickup(self, model: Model, base: CFrame, packName: string): boolean
	local pack = PickupConfig.pack(packName)
	if not pack then
		--[[ A kind naming a pack that is not in `PickupConfig.Packs` — an authoring slip, and one
			worth shouting about rather than swallowing: the hit volume is already built, so what is
			left standing is an INVISIBLE thing that fills your slot. That is the reward-side twin of
			the "invisible thing that takes 30 HP off you" the missing-art branch below refuses to
			ship, and it gets the same treatment for the same reason.

			Warned once per name, because this fires per pack and a broken kind is one on every
			other tile. ]]
		if not self._warnedMissing[packName] then
			self._warnedMissing[packName] = true
			self.log:warn(
				string.format(
					"Obstacle kind names pickup pack '%s', which is not in PickupConfig.Packs; skipping it.",
					tostring(packName)
				)
			)
		end
		return false
	end
	local body = PickupConfig.Body
	--- The colour that GLOWS as this pack's hue; see `PickupConfig.burn`. The light below takes the
	--- raw colour instead, because a light does not bloom.
	local glow = PickupConfig.burn(pack.Color)

	local cage = Instance.new("Model")
	cage.Name = "Cage"

	local core = Instance.new("Part")
	core.Name = "Core"
	core.Shape = Enum.PartType.Block
	core.Size = body.CoreSize
	core.CFrame = base * CFrame.new(0, body.Height, 0)
	core.Color = glow
	core.Material = body.CoreMaterial
	core.Transparency = body.CoreTransparency
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.CastShadow = false
	core.TopSurface = Enum.SurfaceType.Smooth
	core.BottomSurface = Enum.SurfaceType.Smooth
	core.Parent = cage
	cage.PrimaryPart = core

	--[[ The twelve edges. Four bars along each axis, each one held at the two half-extents of the
		other two axes — which is the whole of "a cube's edges" written as a loop rather than as a
		table of twelve offsets nobody could check by eye.

		Each bar is EdgeThickness LONGER than the side it runs along, so the three sets overlap at
		the corners and the frame closes. Bars exactly the side's length leave eight visible notches
		at the corners, which at distance is the difference between a box and a dashed outline. ]]
	local t = body.EdgeThickness
	if t > 0 then
		local half = core.Size * 0.5
		local long = core.Size + Vector3.new(t, t, t)
		local axes = {
			{ Vector3.new(long.X, t, t), 0 },
			{ Vector3.new(t, long.Y, t), 1 },
			{ Vector3.new(t, t, long.Z), 2 },
		}
		for _, axis in axes do
			local size, skip = axis[1], axis[2]
			for _, a in { -1, 1 } do
				for _, b in { -1, 1 } do
					--- The bar runs along `skip`, so it is centred on that axis and pushed to a
					--- corner on the other two.
					local off
					if skip == 0 then
						off = Vector3.new(0, a * half.Y, b * half.Z)
					elseif skip == 1 then
						off = Vector3.new(a * half.X, 0, b * half.Z)
					else
						off = Vector3.new(a * half.X, b * half.Y, 0)
					end
					local bar = Instance.new("Part")
					bar.Name = "Edge"
					bar.Size = size
					bar.CFrame = core.CFrame * CFrame.new(off)
					bar.Color = glow
					bar.Material = Enum.Material.Neon
					bar.Anchored = true
					bar.CanCollide = false
					bar.CanQuery = false
					bar.CanTouch = false
					bar.CastShadow = false
					bar.TopSurface = Enum.SurfaceType.Smooth
					bar.BottomSurface = Enum.SurfaceType.Smooth
					bar.Parent = cage
				end
			end
		end
	end

	if body.LightBrightness > 0 then
		local light = Instance.new("PointLight")
		light.Color = pack.Color
		light.Brightness = body.LightBrightness
		light.Range = body.LightRange
		--- Shadows off: the pack is one of up to two per tile and a shadow-casting light on a road
		--- already carrying traffic and a full obstacle course is the cheapest thing here to cut.
		light.Shadows = false
		light.Parent = core
	end

	--[[ The glyph, RIDING IN THE CUBE — no lift, which is the whole point of the shape: the icon is
		the box's contents rather than a decal hovering over it.

		Sized in SCALE, which on a BillboardGui is STUDS, off the cube's own width — so the icon is a
		physical object that fills the same fraction of its box for everyone, rather than a
		screen-space overlay that would be a different fraction of the road on every aspect ratio.

		`StudsOffset` FLOATS IT TOWARD THE CAMERA, and that offset is the reason the icon is
		readable. It is applied in the billboard's own screen-facing frame rather than in world
		space (which is `StudsOffsetWorldSpace`, and would tip the glyph out of the box as the cube
		turned), so the glyph sits in front of the near face and the near bars at EVERY spin angle
		while still being framed by the far ones. Without it a bar crosses the icon through most of
		the turn, and no amount of clearing the faces helps, because the faces were never what was
		covering it. `PickupConfig.Body.IconFloat` has the measurements.

		It renders through the cube's faces because they are `ForceField`; every other transparent
		material in the engine hides it. See `PickupConfig.Body.CoreMaterial`, which is where that
		will be looked for when someone tries to make this glass.

		`AlwaysOnTop` comes from config and is OFF: on, the glyph draws through the traffic and
		barricades between you and it, so a pack behind a wall would look collectable. It is also
		what keeps a pack visible in a playtest capture at all. ]]
	local studs = core.Size.X * body.IconScale
	local gui = Instance.new("BillboardGui")
	gui.Name = "Icon"
	gui.Adornee = core
	gui.Size = UDim2.fromScale(studs, studs)
	gui.StudsOffset = Vector3.new(0, 0, body.IconFloat)
	gui.AlwaysOnTop = body.AlwaysOnTop
	gui.MaxDistance = body.MaxDistance
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false

	local icon = Instance.new("ImageLabel")
	icon.Name = "Glyph"
	icon.Size = UDim2.fromScale(1, 1)
	icon.BackgroundTransparency = 1
	--- Never tinted: `ImageColor3` multiplies, and the pack's colour is the cage around it. See
	--- `UIAssets.Pickups` for why the two glyphs already arrive in the right colours.
	icon.Image = "rbxassetid://" .. tostring(pack.Icon)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = gui

	gui.Parent = core
	cage.Parent = model
	return true
end

--[[ The float: every pack bobs on its lane and spins about the world's up axis.

	Held in the TILE's frame and re-posed from it every frame, which is the same treatment — and the
	same reason — as the desert's tumbleweed in `_updateRollers`: RoadController recycles a tile to
	the front and rebases the whole road under the car, so an absolute frame captured at build time
	would leave a pack bobbing around a stretch of road that has moved on.

	ONE `PivotTo` ON THE CAGE MODEL rather than a CFrame write per part. The cube is thirteen parts
	that have to stay rigid to each other (`_buildPickup`), and this runs every frame for every pack
	on nine live tiles — so the cost of getting this wrong is twelve extra CFrame writes per pack per
	frame, which is the whole reason the cage is a nested Model at all.

	The HIT VOLUME DOES NOT MOVE WITH IT, deliberately, and being outside the cage is what keeps it
	still. `_buildObstacle` stands the volume on the deck and this leaves it there: it is 14 studs
	tall (see the kind), so it already covers the whole band the cube bobs through, and a volume that
	chased a bobbing target would make whether you collect a pack depend on where in its cycle you
	met it. What moves is what you look at. ]]
function ObstacleController._updatePickups(self, dt: number)
	self._pickupClock += dt
	local clock = self._pickupClock
	local body = PickupConfig.Body
	local spin = math.rad(body.SpinSpeed) * clock
	local tilt = CFrame.fromOrientation(
		math.rad(body.CoreTilt.X),
		math.rad(body.CoreTilt.Y),
		math.rad(body.CoreTilt.Z)
	)

	for tile, list in self._pickups do
		if not tile.Parent then
			continue
		end
		-- One pivot read per tile, as `_updateRollers` does: it is the same answer for every pack
		-- on it and there can be two.
		local pivot = tile:GetPivot()
		for _, p in list do
			if self._consumed[p.id] or not (p.cage and p.cage.Parent) then
				continue
			end
			-- Phase off the id, not the clock, so two packs on one tile never bob in lockstep — and
			-- so a rebuilt tile puts each one back on its own phase rather than reshuffling them
			-- under the player.
			local bob = math.sin(clock * (2 * math.pi / body.BobPeriod) + p.phase) * body.BobHeight
			p.cage:PivotTo(
				pivot * p.rel * CFrame.new(0, body.Height + bob, 0) * CFrame.Angles(0, spin, 0) * tilt
			)
		end
	end
end

-- (Re)build the obstacles for whatever stretch of road this tile currently represents.
--[[ Open a tile's course. Answers the job `_stepCourse` runs down, or nil for a tile that wants no
	obstacles at all.

	The old whole-course version of this is now split across these two functions for the reason
	`ObstacleConfig.BuildBudget` gives: ~25 obstacles and a course-sized `Destroy` on the one frame a
	tile recycled was a periodic spike, on exactly the frames the road builder works to keep clear.
	Everything here is the cheap half — one destroy, one layout roll, one Folder — and the ~25
	`prop:Clone()` calls that were the actual cost are what gets sliced. ]]
function ObstacleController._beginCourse(self, tile: Model, index: number, info)
	local existing = tile:FindFirstChild(ObstacleConfig.TileFolderName)
	if existing then
		existing:Destroy()
	end

	--[[ The map is what decides WHICH obstacle set this tile is built from — the city's cones or
		the desert's cacti (ObstacleLayout's header). It arrived with RaceStart and is nil for a
		race started without a world, which falls back to world 1's set exactly as it always
		did. ]]
	local layout = ObstacleLayout.forTile(self._seed, index, info.segmentLength, self._map, self._bench)
	if #layout == 0 then
		return nil
	end

	local folder = Instance.new("Folder")
	folder.Name = ObstacleConfig.TileFolderName
	return {
		tile = tile,
		index = index,
		info = info,
		layout = layout,
		folder = folder,
		--- Read once, here, and not per obstacle: the tile does not move while its course is being
		--- laid (a rebase moves the tile AND the part-built folder's contents alike, because
		--- `_stepCourse` places everything in world space off this same origin).
		basePos = tile:GetPivot().Position,
		cursor = 1,
		rollers = nil,
		pickups = nil,
	}
end

--[[ One frame's worth of a course. True when the tile is dressed and the job is finished with.

	THE FOLDER IS PARENTED LAST, which is what makes slicing this safe rather than merely cheaper:
	until that line runs the course is off-tree, so it is not drawn, and — the half that matters —
	`_refreshQueryFilter` skips it (`folder.Parent` is nil), so the hit poll cannot see a course that
	is only part laid. A player cannot be charged for half a course, and there is no frame on which
	an obstacle's volume exists without its art. ]]
function ObstacleController._stepCourse(self, job, budget: number): boolean
	local tile, info = job.tile, job.info

	--[[ The tile recycled again underneath us. Its course is for a stretch of road that is no longer
		there, so it is dropped whole rather than finished — `_reconcileTiles` has already queued the
		replacement, and finishing this one would parent a wrong course onto a right tile. ]]
	if not tile.Parent or tile:GetAttribute("TileIndex") ~= job.index then
		job.folder:Destroy()
		return true
	end

	local layout = job.layout
	local built = 0
	while job.cursor <= #layout and built < budget do
		local item = layout[job.cursor]
		job.cursor += 1
		built += 1
		self:_placeObstacle(job, item, info)
	end

	if job.cursor <= #layout then
		return false
	end

	job.folder.Parent = tile -- attach last: everything above is built off-tree
	self._folders[tile] = job.folder
	self._rollers[tile] = job.rollers
	self._pickups[tile] = job.pickups
	--- The course is queryable from this frame, so the poll's filter has to learn about it now.
	self:_refreshQueryFilter()
	return true
end

--- One obstacle into a course being laid. The body of the old `_buildTile` loop, unchanged.
function ObstacleController._placeObstacle(self, job, item, info)
	local folder, basePos = job.folder, job.basePos
	local tile = job.tile
	local rollers = job.rollers
	local pickups = job.pickups
	do
		local model, base = self:_buildObstacle(folder, item, info, basePos)
		local kind = ObstacleConfig.Kinds[item.kind]
		if model and base and kind and kind.Pickup then
			--[[ Same bookkeeping shape as a roller, and held in the tile's frame for the same
				reason (see `_updatePickups`). The cage is looked up rather than returned from the
				build because `_buildObstacle`'s contract is (model, base) for every kind, and
				growing a third return for one of them would put a pickup-shaped hole in every
				other caller. ]]
			pickups = pickups or {}
			table.insert(pickups, {
				id = item.id,
				cage = model:FindFirstChild("Cage"),
				rel = tile:GetPivot():Inverse() * base,
				-- Decorrelates the bob, off the id rather than the RNG — a rebuilt tile then puts
				-- each pack back on its own phase instead of reshuffling the pair.
				phase = item.id * 1.3,
			})
		elseif model and base and kind and kind.Roll then
			--[[ Held in the TILE's frame, not the world's. RoadController recycles a tile to the
				front and rebases the whole road with Model:PivotTo, and an absolute frame captured
				here would leave the weed sweeping around a patch of road that has moved on. Taken
				off the tile's own pivot, it rides both for free — the same reason the obstacle
				folder lives inside the tile in the first place. ]]
			rollers = rollers or {}
			table.insert(rollers, {
				id = item.id,
				volume = model.PrimaryPart,
				-- The published art, which is the only thing that is allowed to ROTATE. Nil for a
				-- kind built from primitives, which then only translates.
				prop = model:FindFirstChildOfClass("Model"),
				rel = tile:GetPivot():Inverse() * base,
				roll = kind.Roll,
				-- Where a volume standing on the deck has its centre. `_updateRollers` re-poses the
				-- volume from the deck frame rather than nudging it by a delta, so it has to
				-- re-apply the offset `_buildObstacle` built it with.
				lift = kind.HitSize.Y * 0.5,
				-- Decorrelates the sweeps so a course of them never moves as one body. Off the id
				-- rather than the RNG so a rebuilt tile puts every weed back on its own phase
				-- instead of reshuffling the whole course under the player.
				phase = item.id * 0.7,
			})
		end
	end
	--- Back onto the job: these two lists are accumulated across the frames the course takes, and
	--- `_stepCourse` hands them to `_rollers`/`_pickups` once the whole thing is down.
	job.rollers = rollers
	job.pickups = pickups
end

-- Compare every live tile's TileIndex against what we built for it; rebuild the ones that
-- changed and forget the ones that are gone. Cheap enough to run every frame (9 tiles).
function ObstacleController._reconcileTiles(self)
	local road = self._road
	local info = road and road:getRoadInfo()
	if not info then
		return
	end

	local changed = false
	local live = {}
	for _, tile in road:getSegments() do
		if tile.Parent then
			live[tile] = true
			local index = tile:GetAttribute("TileIndex")
			if type(index) == "number" and self._built[tile] ~= index then
				--[[ Marked as built BEFORE it is built, which is what stops this queueing the same
					tile again on every frame until the course finishes. The tile's course is now
					this controller's promise rather than its fact; `_stepCourse` re-checks the
					index when it lands, so a tile that recycles again mid-build drops the stale
					course and takes the fresh one this line has already queued. ]]
				self._built[tile] = index
				--- Its previous course, if any, stops being queryable the moment a new one is
				--- promised: `_beginCourse` destroys it, and until then this is what keeps the poll
				--- from charging the player for obstacles belonging to a stretch of road they have
				--- already driven past.
				self._folders[tile] = nil
				table.insert(self._courseQueue, { tile = tile, index = index })
				changed = true
			end
		end
	end
	for tile in self._built do
		if not live[tile] then
			self._built[tile] = nil
			self._folders[tile] = nil
			self._rollers[tile] = nil
			self._pickups[tile] = nil
			changed = true
		end
	end

	if changed then
		self:_refreshQueryFilter()
	end
end

--[[ One frame's worth of the courses waiting to be laid. The obstacle twin of RoadController's
	prefetch, and paced by `ObstacleConfig.BuildBudget` for the reasons given there.

	ONE JOB AT A TIME rather than a budget split across all of them, because a course only becomes
	real when its folder is parented: spreading the budget over three part-built courses would leave
	all three landing later than finishing them in turn, and the one the car reaches first is the one
	that matters. The queue is ordered by when each tile recycled, which is the order the car will
	meet them in. ]]
function ObstacleController._stepCourses(self)
	local job = self._courseJob
	if not job then
		local entry = table.remove(self._courseQueue, 1)
		if not entry then
			return
		end
		local info = self._road and self._road:getRoadInfo()
		if not (info and entry.tile.Parent) then
			return -- road gone, or the tile went with it; `_reconcileTiles` will re-queue if not
		end
		--- nil for a tile whose layout asks for nothing — a legitimate answer, and one that costs
		--- no further frames.
		self._courseJob = self:_beginCourse(entry.tile, entry.index, info)
		return
	end

	if self:_stepCourse(job, math.max(1, ObstacleConfig.BuildBudget)) then
		self._courseJob = nil
	end
end

--[[ The hit poll is an Include query over the obstacle FOLDERS rather than the individual
	volumes: the list stays at one entry per tile instead of one per obstacle, and it only
	has to change when tiles do. Decorative parts inside those folders are CanQuery=false,
	so the query can only ever come back with hit volumes. ]]
function ObstacleController._refreshQueryFilter(self)
	local list = {}
	for _, folder in self._folders do
		if folder.Parent then
			table.insert(list, folder)
		end
	end
	-- The rain's puddles, which live in a folder of their own beside each tile's course.
	for _, entry in self._puddled do
		if entry.folder and entry.folder.Parent then
			table.insert(list, entry.folder)
		end
	end
	self._overlapParams.FilterDescendantsInstances = list

	-- Piggyback the road-edge filter on the same hook: whole tiles, because the two edges are
	-- built out of different models (see ObstacleConfig.Wall) and RespectCanCollide is what
	-- narrows it to things that can actually stop the car. Re-read rather than cached because a
	-- recycled tile is REPLACED when the world's segment progression moves on (RoadController),
	-- so the tile set changes during a race — a cached list would leave the scrape check querying
	-- destroyed geometry and silently stop firing.
	local tiles = {}
	for _, tile in (self._road and self._road:getSegments() or {}) do
		table.insert(tiles, tile)
	end
	self._wallParams.FilterDescendantsInstances = tiles
end

-- === The rain's puddles =====================================================

--[[ The `Puddles` spec this run should be laying right now, or nil for a dry road.

	Asked of `WeatherController`, which is what draws the sky: its answer already has the race's world
	and the tutorial's always-clear run folded in, so the road cannot be wet under a dry sky. A bench is
	always dry, because a bench is "this hazard and nothing else". ]]
function ObstacleController._puddleSpec(self)
	if self._bench then
		return nil
	end
	local weather = self._weatherController or Shard.get("WeatherController")
	self._weatherController = weather
	local key = weather and weather.currentEvent and weather:currentEvent()
	return WeatherConfig.puddlesOf(key)
end

--[[ Lay, keep and dry the rain's puddles. Once a frame, beside `_reconcileTiles`, and cheap in the
	common frame: nine tiles and a number compared on each.

	A TILE'S PUDDLES LIVE AND DIE WITH ITS INDEX, in their own folder beside its course, and nothing
	about them is part of the course. So a course is never rebuilt for the weather, and the rain
	arriving is not a tile recycling:

	  • a tile whose index moved on drops its puddles, wet or dry (the water dries with the tile),
	  • while it is wet, any tile with no puddles for its current index gets them, which covers both a
	    tile recycling to the front in the rain and every tile already standing when the rain begins,
	  • when the rain stops, nothing is taken away, and the ripples stop,
	  • when the SKY changes (rain to storm, storm to clear), every puddle on the road re-dresses in
	    the new sky's `Water` look or its own. A puddle belongs to the road, not to the sky it was
	    laid under, and the storm's night sheen would glow in daylight while the rain's Glass would
	    vanish at night.

	Laid whole in one frame rather than sliced like a course: a tile carries two puddles at most, a
	fraction of what `ObstacleConfig.BuildBudget` exists to spread. ]]
function ObstacleController._reconcilePuddles(self)
	local road = self._road
	local info = road and road:getRoadInfo()
	if not info then
		return
	end
	local spec = self:_puddleSpec()
	local wet = spec ~= nil

	local changed = false
	local live = {}
	for _, tile in road:getSegments() do
		if not tile.Parent then
			continue
		end
		live[tile] = true
		local index = tile:GetAttribute("TileIndex")
		if type(index) ~= "number" then
			continue
		end
		local entry = self._puddled[tile]
		if entry and entry.index ~= index then
			if entry.folder then
				entry.folder:Destroy()
				changed = true
			end
			self._puddled[tile] = nil
			entry = nil
		end
		if wet and not entry then
			entry = self:_layPuddles(tile, index, info, spec)
			self._puddled[tile] = entry
			changed = changed or entry.folder ~= nil
		end
	end
	for tile, entry in self._puddled do
		if not live[tile] then
			if entry.folder then
				entry.folder:Destroy()
				changed = true
			end
			self._puddled[tile] = nil
		end
	end

	-- The spec is the event's own table, so identity is "the sky changed", wet to dry included.
	if spec ~= self._dressedFor then
		self._dressedFor = spec
		local water = spec and spec.Water
		for _, entry in self._puddled do
			styleWater(entry.water, water)
			for _, emitter in entry.ripples do
				emitter.Enabled = wet
			end
		end
	end
	if changed then
		self:_refreshQueryFilter()
	end
end

--[[ One tile's puddles, for the index it is carrying now. Always answers an entry, even an empty one,
	because "this tile has been looked at" is what stops it being looked at again every frame.

	Its OBSTACLES ARE RE-DERIVED here rather than read off the course folder, because `puddlesFor`
	wants the list (lanes and positions), not the models, and `forTile` is pure and cheap: the same
	answer `_beginCourse` got, whether or not that course has finished landing.

	`Puddles.Ahead` is the one filter, and it is what lets the rain start mid-run without a puddle
	blinking into existence on the road in front of you. ]]
function ObstacleController._layPuddles(self, tile: Model, index: number, info, spec)
	local entry = {
		index = index,
		folder = nil :: Folder?,
		ripples = {} :: { ParticleEmitter },
		water = {} :: { any }, -- each art part and the look it was delivered in (`styleWater`)
	}
	local items = ObstacleLayout.forTile(self._seed, index, info.segmentLength, self._map, self._bench)
	local puddles = ObstacleLayout.puddlesFor(self._seed, index, info.segmentLength, items, spec)
	if #puddles == 0 then
		return entry
	end

	local basePos = tile:GetPivot().Position
	local tileAlong = basePos:Dot(info.forward)
	local primary = self._car and self._car.PrimaryPart
	local carAlong = primary and primary.Position:Dot(info.forward)
	local ahead = ObstacleConfig.Puddles.Ahead

	local folder = Instance.new("Folder")
	folder.Name = ObstacleConfig.Puddles.FolderName
	local laid = 0
	for _, item in puddles do
		if carAlong and tileAlong + item.along - carAlong < ahead then
			continue
		end
		local model, base = self:_buildObstacle(folder, item, info, basePos)
		if model and base then
			self:_dressPuddle(model, base, item, entry, spec)
			laid += 1
		end
	end
	if laid == 0 then
		folder:Destroy()
		return entry
	end
	folder.Parent = tile -- attached last, like a course: nothing is queryable half laid
	entry.folder = folder
	return entry
end

--[[ What makes one puddle this puddle: its turn, its size, its water and its ripples.

	`_buildObstacle` has already stood the hit volume and the art on the deck, both on `base`. The art
	is TURNED and SIZED about its own footprint centre, which `ObstacleService._fitProp` put at its
	pivot on the ground, so it stays lying flat on the same spot. The hit volume is sized with it on
	the ground plane but never turned: it is an axis-aligned box the poll overlaps, and the ripples are
	kept inside its footprint, which a pool about half again as wide contains at any angle.

	The primitive fallback is a round sheet, so it is neither turned nor sized, but it does take the
	sky's `Water` like the art. ]]
function ObstacleController._dressPuddle(self, model: Model, base: CFrame, item, entry, spec)
	local kind = ObstacleConfig.Kinds[item.kind]
	if not kind then
		return
	end
	local scale = item.scale or 1
	local volume = model.PrimaryPart

	local prop = model:FindFirstChildOfClass("Model")
	if prop then
		prop:PivotTo(base * CFrame.Angles(0, math.rad(item.yaw or 0), 0))
		if scale ~= 1 then
			prop:ScaleTo(prop:GetScale() * scale)
		end
	end

	-- The look each art part was delivered in, taken before any sky's `Water` goes on over it.
	local parts = {}
	for _, part in (prop or model):GetDescendants() do
		if part:IsA("BasePart") and part ~= volume then
			local rec = {
				part = part,
				material = part.Material,
				color = part.Color,
				transparency = part.Transparency,
				reflectance = part.Reflectance,
			}
			table.insert(parts, rec)
			table.insert(entry.water, rec)
		end
	end
	styleWater(parts, spec and spec.Water)

	local footprint = Vector3.new(kind.HitSize.X * scale, kind.HitSize.Y, kind.HitSize.Z * scale)
	if volume then
		volume.Size = footprint
		volume.CFrame = base * CFrame.new(0, footprint.Y * 0.5, 0)
	end

	local ripples = kind.Ripples
	if not ripples then
		return
	end
	local share = ripples.Footprint or 1
	local carrier = Instance.new("Part")
	carrier.Name = "Ripples"
	carrier.Size = Vector3.new(footprint.X * share, 0.05, footprint.Z * share)
	carrier.CFrame = base * CFrame.new(0, ripples.Lift or 0.3, 0)
	carrier.Anchored = true
	carrier.Transparency = 1
	carrier.CastShadow = false
	carrier.CanCollide = false
	-- The one rule every decorative part in these folders keeps: only the `Hit` volume answers the poll.
	carrier.CanQuery = false
	carrier.CanTouch = false

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Ripples"
	emitter.Texture = ripples.Texture
	emitter.Rate = ripples.Rate or 6
	emitter.Lifetime = rangeOf(ripples.Lifetime, 0.8)
	emitter.Size = sequenceOf(ripples.Size, 1.5)
	emitter.Transparency = sequenceOf(ripples.Transparency, 0.4)
	emitter.Color = ColorSequence.new(ripples.Color or Color3.new(1, 1, 1))
	emitter.LightEmission = ripples.Glow or 0
	--[[ FLAT ON THE WATER: a ring travelling straight up, drawn perpendicular to its travel, lies in
		the surface. The speed is only there to give it a direction to lie across; `WeatherController`'s
		"Flat" facing is the same trick. ]]
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	emitter.Speed = NumberRange.new(0.05)
	emitter.SpreadAngle = Vector2.zero
	emitter.Acceleration = Vector3.zero
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	-- Pinned to the carrier, so a rebase or a recycle, which move the tile, carry the rings with it.
	emitter.LockedToPart = true
	emitter.Parent = carrier
	carrier.Parent = model
	table.insert(entry.ripples, emitter)
end

--[[ THE TUMBLEWEED SWEEP — the one thing on the road that moves on its own.

	Everything else in this layer is built once and then only ever moved BY the road (a tile
	recycle, a world rebase). A kind with `Roll` (ObstacleConfig.Tumbleweed) is re-posed every
	frame instead: it sweeps across the road on a sine, hops, and rolls at the rate it is
	travelling, which is what turns a static prop into something wind-blown.

	IT IS DECORATION OVER A HIT THE SERVER STILL PRICES FROM THE AUTHORED LANE, so this never
	touches the layout: the id, the lane and the damage are what they always were, and the only
	concession the server makes is widening its lane check by the sway (`_laneIsPlausible`).
	Nothing here replicates and nothing here is seeded — two clients would draw the same weed at
	different points of its sweep, and neither one is more right than the other, because the
	server never asks where it was.

	THE VOLUME AND THE PROP ARE POSED SEPARATELY and that split is the whole implementation. The
	hit volume must stay an axis-aligned box standing on the deck — it is what the hit poll
	overlaps, and rolling it would change the footprint the player is being charged against. So
	the volume only ever translates, and the ROLL is applied to the prop alone, about the ball's
	centre (`Roll.Radius` up from the deck) rather than about its pivot, which sits on the ground:
	spinning it about the pivot would make it pirouette on the spot instead of rolling.

	Rolling direction: the base frame's +X is across the road, so a ball travelling +X has to turn
	the short way about +Z, which is a NEGATIVE angle — hence the sign. Getting it backwards is
	not subtle; it reads instantly as a ball skidding sideways.

	Smashed weeds are skipped by their consumed flag: `_smash` has already unparented the model
	into the debris folder and handed it to the physics engine, and posing it from here would drag
	it back to the road mid-flight. ]]
function ObstacleController._updateRollers(self, dt: number, poseVisuals: boolean)
	self._rollClock += dt
	local clock = self._rollClock
	for tile, list in self._rollers do
		if not tile.Parent then
			continue
		end
		-- One pivot read per tile rather than per weed: it is the same answer for all of them and
		-- a course can put five on one tile.
		local pivot = tile:GetPivot()
		for _, r in list do
			if self._consumed[r.id] or not (r.volume and r.volume.Parent) then
				continue
			end
			local roll = r.roll
			local t = clock * roll.Speed + r.phase
			local sway = math.sin(t) * roll.Sway
			local hop = math.abs(math.sin(t * roll.HopRate)) * roll.Hop
			-- The patch of deck the weed is standing on this frame.
			local ground = pivot * r.rel * CFrame.new(sway, hop, 0)
			r.volume.CFrame = ground * CFrame.new(0, r.lift, 0)
			if poseVisuals and r.prop then
				local radius = roll.Radius
				r.prop:PivotTo(
					ground * CFrame.new(0, radius, 0) * CFrame.Angles(0, 0, -sway / radius) * CFrame.new(0, -radius, 0)
				)
			end
		end
	end
end

-- === Hits ===================================================================

function ObstacleController._checkHits(self)
	local hitBox = self._hitBox
	if not (hitBox and hitBox.Parent) then
		return
	end
	for _, volume in workspace:GetPartsInPart(hitBox, self._overlapParams) do
		local id = volume:GetAttribute("ObstacleId")
		if type(id) == "number" and not self._consumed[id] then
			self:_onHit(volume, id, volume:GetAttribute("ObstacleKind"))
		end
	end
end

function ObstacleController._onHit(self, volume: BasePart, id: number, kindName: any)
	local kind = ObstacleConfig.Kinds[kindName]
	if not kind then
		return
	end

	-- One obstacle can only ever cost you HP once — locally (so grinding along a barrier
	-- doesn't chip you every frame) and on the server (which tracks the same thing).
	self._consumed[id] = true
	volume.CanQuery = false

	--[[ A kind the car goes THROUGH runs no impact beat at all. Two of them today and they are
		opposite in intent: a boost pad, which rewards you, and a hologram, which is not there.
		Both still consume the id — driving through either is correctly not a dodge — and neither
		may shove, shake, smoke or report a police strike. `Boost` implies `Pass`; see the Kinds
		legend in ObstacleConfig.

		The shake is the one piece of the beat a pad keeps, because a kick in the back with a
		perfectly still camera reads as a bug rather than as a boost. A hologram carries Shake 0
		and so gets nothing, which is the whole idea. ]]
	if kind.Boost or kind.Pass then
		if kind.Boost then
			self:_boost(kind.Boost)
		end
		--[[ A PACK. `Pass` already spared it the impact beat above; this is the local half of
			collecting one — the core pops, the toast goes up, the glyph flies to the slot. None of
			it is the PAYOUT: the server derives that from the id we are about to report, exactly as
			it derives an obstacle's damage, and the slot it fills is the server's record. So a
			client that skipped this line would get the pack anyway and just not see it happen.

			Resolved lazily and tolerated missing, on `_boost`'s reasoning about `NitroController`:
			`PickupConfig.Enabled` off means there is no controller to tell, and the road should
			still behave. ]]
		if kind.Pickup then
			local pickups = Shard.get("PickupController")
			if pickups then
				--- The HitBox goes with it because that is where Health lives (`ObstacleConfig
				--- .HitBoxName`), and the toast has to predict whether the server will bank the pack
				--- or spend it. Handing the part over means both sides read the same attributes off
				--- the same instance rather than each finding their own.
				pickups:collected(kind.Pickup, self._hitBox)
			end
			self:_popPickup(volume.Parent)
		end
		self._shake = math.max(self._shake, kind.Shake or 0)
	elseif kind.Splash then
		-- Water, not a wall: no impact beat and no police strike. See `_splash`.
		self:_splash(volume, kind)
	else
		self:_react(volume, kind)
	end
	--[[ A slick kind takes the car's GRIP rather than its HP, and grip is DriveController's to give
		away: in direct steering the cross-road velocity is a value that controller writes every frame
		from the player's input, so a hazard that wants the car to stop answering the wheel has to say
		so there. Measured on a live car, the alternative -- pushing the assembly around from here --
		buys about a stud of travel before the lane ease erases it. See DriveController.applySlick. ]]
	if kind.Slick then
		local drive = Shard.get("DriveController")
		if drive then
			drive:applySlick(kind.Slick.Duration, kind.Slick.Grip, kind.Slick.Wobble)
		end
	end
	-- ...and nothing the car passed through may be knocked away by it. A kind with both is an
	-- authoring mistake rather than a state to support, so this reads as the guard it is.
	if kind.Smash and not (kind.Boost or kind.Pass) then
		self:_smash(volume.Parent, volume, kind.Smash)
	end

	-- The server decides the damage; we only say which obstacle it was. A `Local` kind (the rain's
	-- puddle) is one the server has no layout for, so there is nothing to say.
	if not kind.Local then
		self:getRemoteEvent("ObstacleHit"):Fire(id)
	end
end

--[[ THROUGH WATER: the puddle's beat, in place of `applyImpact`'s.

	`applyImpact` is the one door every hit goes through, and a puddle deliberately does not use it:
	that door puffs smoke, punches the camera and takes a bite of the police bar, and a car that ran
	through a puddle has crashed into nothing. What is left is small and physical.

	THE PULL POINTS AT THE WATER, the one kick in this file aimed at what you touched rather than
	away from it: the tyres on the wet side drag. It scales with how far off centre the puddle is
	across the car, so one taken dead centre pulls nothing (both sides drag alike) and one clipped at
	its rim pulls the full `SideKick`. A velocity write on the car we own, as in `applyImpact`, which
	`DriveController._lane` then absorbs as an outside shove and eases back out at the slick's grip.

	Then a nudge of shake and the spray (`_spray`). The slick itself is `_onHit`'s, the same call oil
	makes. ]]
function ObstacleController._splash(self, volume: BasePart, kind)
	local primary = self._car and self._car.PrimaryPart
	if not primary then
		return
	end
	local cf = primary.CFrame
	local across = (volume.Position - cf.Position):Dot(cf.RightVector)
	local rim = math.max(volume.Size.X * 0.5, 1e-3)
	local pull = kind.SideKick * math.clamp(across / rim, -1, 1)
	primary.AssemblyLinearVelocity = primary.AssemblyLinearVelocity * kind.SpeedKeep + cf.RightVector * pull
	self._shake = math.max(self._shake, kind.Shake or 0)
	self:_spray(kind.Splash, primary)
end

--[[ The spray: water thrown out of both flanks at road height, the one thing a puddle draws on contact.

	TWO EMITTERS ON THE CAR'S HITBOX, one per flank, each on an Attachment at deck level turned so its
	emission axis leans `Tilt` out from straight up. On the hit box because that is where the car's
	velocity is, which `Inherit` needs (a part of our own, anchored and moved each frame, has none),
	and on Attachments rather than parts because nothing may be welded into a car's assembly for a
	visual. Built on first use and rebuilt if the hit box changes; `_teardown` drops them.

	A BURST, NOT A STREAM: `Emit` on contact, `Count` per flank scaled by the speed you hit it at, so
	the size of the splash is something the player did. ]]
function ObstacleController._spray(self, spec, primary: BasePart)
	local hitBox = self._hitBox
	if not (spec and hitBox and hitBox.Parent) then
		return
	end
	local rig = self._sprayRig
	-- On THIS hit box, which a different car and a torn-down one both fail.
	if not (rig and rig.left:IsDescendantOf(hitBox) and rig.right:IsDescendantOf(hitBox)) then
		self:_dropSpray()
		rig = self:_buildSpray(spec, hitBox)
		self._sprayRig = rig
	end

	local speed = primary.AssemblyLinearVelocity.Magnitude
	local count = math.round(spec.Count * math.clamp(speed / math.max(spec.CountAtSpeed or 85, 1), 0.3, 1.4))
	if count > 0 then
		rig.left:Emit(count)
		rig.right:Emit(count)
	end

	if spec.Sound then
		local sounds = Shard.get("SoundController")
		if sounds then
			sounds:PlayRandomAt(spec.Sound, hitBox)
		end
	end
end

function ObstacleController._buildSpray(self, spec, hitBox: BasePart)
	local rig = {}
	local half = hitBox.Size * 0.5
	--- The deck, in the hit box's frame: it rides `Smash.Floor` above the road.
	local deck = -half.Y - ObstacleConfig.Smash.Floor
	for _, side in { -1, 1 } do
		local attachment = Instance.new("Attachment")
		attachment.Name = if side < 0 then "PuddleSprayL" else "PuddleSprayR"
		-- About Z, so +Y (the emission axis) leans out toward this flank's own side.
		attachment.CFrame = CFrame.new(side * half.X, deck + 0.3, 0)
			* CFrame.Angles(0, 0, -side * math.rad(spec.Tilt or 45))

		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Spray"
		emitter.Enabled = false
		emitter.Texture = spec.Texture
		emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
		-- OneShot, or a short particle shows the sheet's first frame and nothing else (CarMutation).
		emitter.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.SpreadAngle = Vector2.new(spec.Spread or 25, spec.Spread or 25)
		emitter.Speed = rangeOf(spec.Speed, 12)
		emitter.Lifetime = rangeOf(spec.Lifetime, 0.6)
		emitter.Size = sequenceOf(spec.Size, 3)
		emitter.Transparency = sequenceOf(spec.Transparency, 0.4)
		emitter.Color = ColorSequence.new(spec.Color or Color3.new(1, 1, 1))
		emitter.Acceleration = Vector3.new(0, -(spec.Gravity or 0), 0)
		emitter.Drag = spec.Drag or 0
		emitter.VelocityInheritance = spec.Inherit or 0.8
		emitter.Orientation = Enum.ParticleOrientation.FacingCamera
		emitter.Rotation = NumberRange.new(-180, 180)
		emitter.RotSpeed = NumberRange.new(-60, 60)
		emitter.LightEmission = spec.Glow or 0
		emitter.Parent = attachment
		attachment.Parent = hitBox
		rig[if side < 0 then "left" else "right"] = emitter
	end
	return rig
end

--- Take the spray rig off the car, if it is still on one.
function ObstacleController._dropSpray(self)
	local rig = self._sprayRig
	self._sprayRig = nil
	if not rig then
		return
	end
	for _, key in { "left", "right" } do
		local emitter = rig[key]
		local attachment = emitter and emitter.Parent
		if attachment and attachment:IsA("Attachment") then
			attachment:Destroy()
		end
	end
end

--[[ PUBLIC — the whole "crash", and the ONE path every hazard's feel goes through: obstacle
	clips, wall scrapes, and TrafficController's car clips. A velocity edit on the car we own,
	plus camera shake and a smoke puff. Writing velocity (never CFrame) on an owned, simulated
	assembly is safe; CFrame writes are what synthesise the reconciliation-velocity runaway
	RoadController's rebase has to work around.

	It lives here rather than in a shared module because everything it needs — the car we're
	driving, its bounding box, the rider's camera, the reusable puff emitter — is state this
	controller already owns for the whole race. A new hazard should call this, not grow its own.

	`side` says which side of the car the thing is on: +1 = the car's right, so the shove always
	comes back the other way. `yawTowards` picks which way the nose gets kicked: +1 rotates it
	toward the hit, which is the obstacle feel (a clip destabilises you into the hazard), and -1
	rotates it away, which is what a wall needs — nose-in against a solid rail would just hold
	the car there. `kind` is any table carrying SpeedKeep/SideKick/Yaw/Shake: an entry from
	`Kinds`, ObstacleConfig.Wall, or TrafficConfig.Clip.

	IT IS ALSO WHERE THE POLICE FIND OUT YOU CRASHED, and that is not a side effect bolted on: it
	is here precisely BECAUSE this is the one door every hazard already goes through. During a
	chase, an impact takes a bite out of the wanted bar sized by how hard it was, and two bites
	close together are an arrest (PoliceConfig.Strikes). Wiring that per hazard would mean every
	new hazard needing to remember the police; wiring it here means one that calls this is priced
	for free, and one that doesn't is invisible to the police for exactly the same reason it is
	invisible to the camera shake. `Shake` is the severity that travels, for reasons the config
	gives at length. ]]
function ObstacleController.applyImpact(self, side: number, kind, yawTowards: number, hitDir: Vector3?, source: string?)
	local primary = self._car and self._car.PrimaryPart
	if not primary then
		return
	end

	-- Before the velocity edit, so a hit that busts the player is reported off the speed they were
	-- doing when they hit rather than off what the crash left them with. The police refuse
	-- everything that isn't a live chase, so this is a no-op on the great majority of impacts.
	local police = self._police or Shard.get("PoliceController")
	if police then
		self._police = police
		police:reportStrike(kind.Shake)
	end

	local right = primary.CFrame.RightVector
	-- The speed the car met it at, for the crash sound: read before the edit below takes it away.
	local into = hitDir or right * side
	local impactSpeed = kind.ImpactSpeed
		or (if into.Magnitude > 1e-3 then math.max(primary.AssemblyLinearVelocity:Dot(into.Unit), 0) else 0)
	primary.AssemblyLinearVelocity = primary.AssemblyLinearVelocity * kind.SpeedKeep
		- right * (side * kind.SideKick)
	primary.AssemblyAngularVelocity = primary.AssemblyAngularVelocity
		+ Vector3.new(0, -side * yawTowards * kind.Yaw, 0)

	self._shake = math.max(self._shake, kind.Shake)
	-- The camera's punch and hit-stop (CameraConfig.Juice), sized by the same `Shake`. Looked up lazily
	-- for the same reason the police are above.
	local camera = self._raceCamera or Shard.get("RaceCameraController")
	if camera and camera.impact then
		self._raceCamera = camera
		camera:impact(side, kind.Shake)
	end
	-- The shove only needs left/right, but the smoke needs to know front from flank — so callers
	-- hand over the full direction the hit came from. Falling back to the flank keeps any future
	-- caller that only knows a side working, just less precisely placed.
	--[[ THE DELIVERED EFFECTS (`CrashVfxConfig`, 2026-09-30): sparks and smoke at the contact point,
		picked by what was hit (`source` — every caller names itself: "Car", "Wall", "Obstacle"). The
		old grey puff below still plays when they do not (no folder yet, or `ReplaceHitSmoke` off). ]]
	if not self:_crashBurst(source or "Car", kind, hitDir or right * side) or not CrashVfxConfig.ReplaceHitSmoke then
		self:_emitHitSmoke(kind, hitDir or right * side)
	end
	self:_crashSound(source or "Car", kind, impactSpeed)
end

--[[ The hit's sound (`CrashSoundConfig`), on the car so it pans with the contact. Louder and a little
	lower the harder the hit, by `Shake` or by the speed score, whichever says harder; the heavy layer
	joins from `Heavy.MinShake` or `Speed.HeavyAt`, the dramatic one from `Speed.DramaticAt`. ]]
function ObstacleController._crashSound(self, source: string, kind, impactSpeed: number)
	local cfg = CrashSoundConfig
	local shake = kind.Shake or 0
	local primary = self._car and self._car.PrimaryPart
	local sounds = Shard.get("SoundController")
	if not (cfg.Enabled and primary and sounds) or shake < cfg.MinShake then
		return
	end
	local now = os.clock()
	local speedCfg = cfg.Speed
	local score = 0
	if speedCfg.Enabled then
		local solidity = if kind.Solid then 1 else math.clamp(shake / speedCfg.SolidShake, 0, 1)
		score = math.clamp((impactSpeed - speedCfg.Slow) / math.max(speedCfg.Fast - speedCfg.Slow, 1e-3), 0, 1) * solidity
	end
	local t = math.max(math.clamp((shake - cfg.MinShake) / math.max(cfg.FullShake - cfg.MinShake, 1e-3), 0, 1), score)
	local pitch = cfg.Pitch[1] + (cfg.Pitch[2] - cfg.Pitch[1]) * t
	local volume = cfg.Volume[1] + (cfg.Volume[2] - cfg.Volume[1]) * t
	local jitter = 1 + (math.random() * 2 - 1) * cfg.PitchJitter

	if now - (self._crashSoundAt or 0) >= cfg.Cooldown then
		self._crashSoundAt = now
		sounds:PlayRandomAt(cfg.OnHit[source] or cfg.OnHit.Car, primary, pitch * jitter, volume, cfg.RollOffMin, cfg.RollOffMax)
	end
	if shake >= cfg.Heavy.MinShake or score >= speedCfg.HeavyAt then
		sounds:PlayRandomAt(cfg.Heavy.Group, primary, pitch * jitter, volume, cfg.RollOffMin, cfg.RollOffMax)
	end
	if score >= speedCfg.DramaticAt and now - (self._dramaticSoundAt or 0) >= cfg.DramaticCooldown then
		self._dramaticSoundAt = now
		sounds:PlayRandomAt(cfg.Dramatic.Group, primary, pitch * jitter, volume * cfg.Dramatic.Volume, cfg.RollOffMin, cfg.RollOffMax)
	end
end

--[[ Hand a collision to `CrashVfxController`, at the same point on the car's skin the old puff uses
	(`_puffCFrame`). Returns whether the new effects are in play at all, which is what decides whether
	the old puff still has to carry the hit. ]]
function ObstacleController._crashBurst(self, source: string, kind, hitDir: Vector3): boolean
	local vfx = self._crashVfx or Shard.get("CrashVfxController")
	local primary = self._car and self._car.PrimaryPart
	if not (CrashVfxConfig.Enabled and vfx and primary) then
		return false
	end
	self._crashVfx = vfx
	local localDir = primary.CFrame:VectorToObjectSpace(hitDir)
	local flat = Vector3.new(localDir.X, 0, localDir.Z)
	if flat.Magnitude < 1e-3 then
		return false
	end
	local cframe = self:_puffCFrame(flat.Unit)
	if not cframe then
		return false
	end
	vfx:impact(source, cframe, kind.Shake or 0)
	return ReplicatedStorage:FindFirstChild(CrashVfxConfig.FolderName) ~= nil
end

--[[ The car's bounding box, cached in the chassis root's own frame.

	Cached because `GetBoundingBox` walks every descendant and the puff re-places itself each
	frame while it emits; the box is a constant per car, only the frame moves. Verified aligned
	with the root on the test rig, so the half-extents really are the car's width and length —
	and the root sits 0.59 studs off the car's true centre, which is why the centre is stored
	rather than assumed to be the origin. ]]
function ObstacleController._carBox(self)
	if self._carBoxCache then
		return self._carBoxCache
	end
	local car = self._car
	local primary = car and car.PrimaryPart
	if not primary then
		return nil
	end
	local bbCF, bbSize = car:GetBoundingBox()
	if bbSize.X < 1e-3 or bbSize.Z < 1e-3 then
		return nil
	end
	self._carBoxCache = {
		centre = primary.CFrame:PointToObjectSpace(bbCF.Position),
		half = bbSize * 0.5,
	}
	return self._carBoxCache
end

--[[ Where the impact puff sits: on the car's skin at the point the hit came from — nose for a
	head-on, flank for a side-swipe, corner for a corner — then a little further out into open
	air, lifted clear of the sill.

	`localDir` is the hit direction in the CAR's frame, so the puff stays put on the bodywork as
	the car turns underneath it. Walking it out to the bounding box (rather than a fixed radius)
	is what makes one number work for a 5.18-stud half-width and a 10.92-stud half-length.

	Measured off the bounding box and NOT the HitBox — see ObstacleConfig.HitSmoke for why that
	distinction is what made the first two versions invisible. ]]
function ObstacleController._puffCFrame(self, localDir: Vector3): CFrame?
	local hitBox = self._hitBox
	local primary = self._car and self._car.PrimaryPart
	local box = self:_carBox()
	if not (hitBox and hitBox.Parent and primary and box) then
		return nil
	end

	local cfg = ObstacleConfig.HitSmoke
	-- Distance from the car's centre to where this direction leaves the bounding box.
	local reach = 1 / math.max(math.abs(localDir.X) / box.half.X, math.abs(localDir.Z) / box.half.Z)
	local world = primary.CFrame:PointToWorldSpace(box.centre + localDir * (reach + cfg.SurfaceOffset))
	return CFrame.new(world.X, hitBox.Position.Y + cfg.HeightOffset, world.Z)
end

--[[ A small version of the wreck plume, fired from the flank that got hit. Severity comes off
	the kind's `Shake` — already the config's "how big does this feel" dial — so a cone barely
	puffs and concrete throws a real cloud, with no second severity number to keep in sync.

	The emitter TRACKS the car while it runs (see _loop). Particles stay in world space once
	emitted, so you still drive out of your own smoke — but the emission keeps happening beside
	the car instead of all landing on one point the car immediately leaves behind, which is the
	difference between a trail you can see and a wisp you can't. Emission is stopped by the main
	loop rather than a task.delay, so a teardown mid-puff can't race it. ]]
function ObstacleController._emitHitSmoke(self, kind, hitDir: Vector3)
	local cfg = ObstacleConfig.HitSmoke
	local smoke, puff = self._puffSmoke, self._puff
	local primary = self._car and self._car.PrimaryPart
	if not (cfg.Enabled and smoke and puff and primary) then
		return
	end

	-- Store the direction in the car's own frame so the puff stays on the same patch of
	-- bodywork while the car turns under it.
	local localDir = primary.CFrame:VectorToObjectSpace(hitDir)
	local flat = Vector3.new(localDir.X, 0, localDir.Z)
	if flat.Magnitude < 1e-3 then
		return -- hit came from straight above or below; nothing sensible to place against
	end
	self._puffDir = flat.Unit

	local cframe = self:_puffCFrame(self._puffDir)
	if not cframe then
		return
	end

	local severity = math.clamp((kind.Shake or 0) / math.max(cfg.ShakeForFullPuff, 1e-3), 0, 1)
	smoke.Size = cfg.MinSize + (cfg.MaxSize - cfg.MinSize) * severity
	puff.CFrame = cframe

	smoke.Enabled = true
	self._puffUntil = os.clock() + cfg.MinTime + (cfg.MaxTime - cfg.MinTime) * severity
end

--[[ THE PADS — the one thing on the road that gives the car something instead of taking it.

	`ObstacleConfig.BoostPad` and `GravityLift` (the futuristic city's, and authored against a map
	nothing points at yet). Everything else in this file funnels into `applyImpact`; this is the
	one path that deliberately does not, because being rewarded must not feel like being hit —
	no shove, no yaw, no smoke, and above all no police strike, which would otherwise have a boost
	pad counting toward an arrest in the middle of a chase.

	THE SPEED IS ADDED AND THE LIFT IS SET, and the asymmetry is the point. Speed adds because the
	chassis pulls it back to the car's own top speed over the next second, so a second pad taken
	while the first is still bleeding off is still worth something. Lift SETS, because vertical
	velocity has nothing pulling it back but gravity: adding it would let two lifts taken close
	together stack into a launch nobody authored, and `math.max(0, ...)` means a pad taken while
	already rising faster than it asks for is simply a no-op rather than a brake.

	THE LANDING NEEDS THE SETTLE GRACE. `_checkWall` overlaps a widened HitBox against the road
	itself, so a suspension bottoming out on touchdown reads as a guardrail scrape — the exact
	false positive `Wall.SettleTime` exists for after `RaceService` sets a car down. A launch is
	the only other thing in the game that produces it, so it books the same grace: the flight time
	it just bought (2v/g for a symmetric arc), plus the settle. Reads `workspace.Gravity` rather
	than assuming 196.2, because a place that changes it would otherwise silently lose the guard.

	Velocity writes only, on an assembly we own — never a CFrame; see `applyImpact`. ]]
function ObstacleController._boost(self, boost)
	local primary = self._car and self._car.PrimaryPart
	if not primary then
		return
	end
	local velocity = primary.AssemblyLinearVelocity
	local add = Vector3.zero

	local speed = boost.Speed or 0
	if speed > 0 then
		local info = self._road and self._road:getRoadInfo()
		-- Down the ROAD, not down the car's nose: the car crabs in direct steering (DriveController
		-- ._lane), so a nose-relative push would send a car mid-lane-change sideways.
		if info then
			add += info.forward * speed
		end
	end

	local lift = boost.Lift or 0
	if lift > 0 then
		add += Vector3.yAxis * math.max(0, lift - velocity.Y)
		local gravity = workspace.Gravity
		if gravity > 0 then
			self._settleUntil = math.max(
				self._settleUntil,
				os.clock() + 2 * lift / gravity + ObstacleConfig.Wall.SettleTime
			)
		end
	end

	if add.Magnitude > 0 then
		primary.AssemblyLinearVelocity = velocity + add
	end

	--[[ The bottle, in the currency `NearMissController` already pays out in — a fraction of a
		FULL tank, so a pad is worth the same whether you are nearly empty or nearly full. Resolved
		lazily and tolerated missing: `NitroConfig.Enabled` off means there is no controller to
		reward, and a pad should still shove you. ]]
	local nitro = boost.Nitro or 0
	if nitro > 0 then
		local controller = Shard.get("NitroController")
		if controller then
			controller:reward(nitro)
		end
	end
end

--[[ The pack going away: the box comes apart over a fifth of a second. The tinted core swells, the
	twelve edge bars fly straight out from the centre, and everything — bars, core, glyph and light —
	fades on the same clock. Purely local dressing on something that has already happened.

	THE FRAME HAS TO GO WITH IT. Swelling the core alone was the old single-part pop and on a caged
	cube it reads as a mistake rather than as an effect: the frame stays exactly where it is, at
	exactly its size, while something grows out through it. Sending the bars outward is what makes
	the object burst instead of one part of it dissolving inside the rest. See
	`PickupConfig.Collect`'s `PopScale`/`PopBurst` for why the two multipliers differ.

	It TWEENS THE PARTS RATHER THAN DESTROYING THE MODEL, and the model is left in place afterwards
	at full transparency rather than cleaned up. Two reasons, both about who owns this instance: the
	obstacle Model is the tile's, and the tile rebuilds its whole `Obstacles` folder the moment its
	`TileIndex` changes — so a pack collected on a tile you are still driving down is cleaned up by
	the recycle a few seconds later, for free, and one destroyed here would leave `_updatePickups`
	and the roller bookkeeping holding a reference to a dead part. `_consumed[id]` already stops the
	float touching it — which is also what stops the float fighting these tweens for the cage's
	pivot — and the volume's `CanQuery` was cleared by `_onHit`, so it is inert either way. ]]
function ObstacleController._popPickup(self, model: Instance?)
	if not (model and model:IsA("Model")) then
		return
	end
	local cage = model:FindFirstChild("Cage")
	local core = cage and cage:FindFirstChild("Core")
	if not (cage and cage:IsA("Model") and core and core:IsA("BasePart")) then
		return
	end
	local collect = PickupConfig.Collect
	local info = TweenInfo.new(collect.PopTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local centre = core.Position
	for _, part in cage:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		if part == core then
			TweenService:Create(part, info, {
				Size = part.Size * collect.PopScale,
				Transparency = 1,
			}):Play()
		else
			--[[ Outward along the bar's OWN offset from the centre, so the frame opens up like a box
				rather than drifting one way: every bar keeps its direction and only its radius
				grows. Multiplying the offset is what does that, and it is why this needs the
				centre rather than each bar's own facing. ]]
			TweenService:Create(part, info, {
				CFrame = part.CFrame + (part.Position - centre) * (collect.PopBurst - 1),
				Transparency = 1,
			}):Play()
		end
	end

	local light = core:FindFirstChildOfClass("PointLight")
	if light then
		TweenService:Create(light, info, { Brightness = 0 }):Play()
	end
	local gui = core:FindFirstChild("Icon")
	local glyph = gui and gui:FindFirstChild("Glyph")
	if glyph and glyph:IsA("ImageLabel") then
		TweenService:Create(glyph, info, { ImageTransparency = 1 }):Play()
	end
end

-- Clipped an obstacle on our right → get shoved (and spun) to the left, and vice versa. The full
-- offset goes through too, so the smoke can tell a head-on from a side-swipe.
function ObstacleController._react(self, volume: BasePart, kind)
	local primary = self._car and self._car.PrimaryPart
	if not primary then
		return
	end
	local cf = primary.CFrame
	local delta = volume.Position - cf.Position
	local side = if delta:Dot(cf.RightVector) >= 0 then 1 else -1
	self:applyImpact(side, kind, 1, delta, "Obstacle")
end


--[[ Riding the guardrail. The rails are solid, so the road itself already stops the car going
	through them — all this adds is the cost of being out there: the same chip damage and impact
	feel an obstacle gives, ticking on a cooldown for as long as the scrape lasts.

	Detected by overlapping a query-only sensor volume — the car's HitBox, widened by
	`Wall.Margin` on each flank — against the whole road tile, with RespectCanCollide doing the
	narrowing. NOT a distance from the road edge, and NOT the guardrails specifically: read the
	ObstacleConfig.Wall header before touching this, because both of those were tried and both
	failed on real geometry (a nominal `DriveWidth` put the threshold inside solid parts, and the
	two road edges are built out of different models, so a rails-only query fired on one side).
	Querying live geometry also gets tile recycling and world rebasing for free.

	The cooldown is checked BEFORE the query, so the common frame costs nothing. It's also
	deliberately not cleared when the car comes off the edge: bouncing along it — exactly what
	the shove below produces — would otherwise tick on every touch and cost far more than the
	configured HP/second. Letting it run down on its own caps the rate, and a first touch after
	any real stretch of clean road still bites immediately. ]]
function ObstacleController._checkWall(self, dt: number)
	local wall = ObstacleConfig.Wall
	if not wall.Enabled then
		return
	end
	--- Not in the truck's shelter (`GetawayConfig.Shelter`, 2026-10-09).
	local getaway = Shard.get("GetawayController")
	if getaway and getaway:isSheltered() then
		return
	end
	self._wallCooldown = math.max(0, self._wallCooldown - dt)
	if self._wallCooldown > 0 then
		return
	end
	-- The car is still coming down off the drop that put it on the road, and a bottomed-out
	-- suspension puts this sensor inside the deck. See Wall.SettleTime and `_watchSettle`.
	if os.clock() < self._settleUntil then
		return
	end

	local sensor = self._wallSensor
	local hitBox = self._hitBox
	local primary = self._car and self._car.PrimaryPart
	if not (sensor and hitBox and hitBox.Parent and primary) then
		return
	end

	-- Ride the HitBox exactly, just wider. Sizing from the live hull each time (rather than once
	-- at creation) means a redressed car with a different hull gets the right sensor for free.
	local size = hitBox.Size + Vector3.new(wall.Margin * 2, 0, 0)
	if sensor.Size ~= size then
		sensor.Size = size
	end
	sensor.CFrame = hitBox.CFrame

	if not workspace:GetPartsInPart(sensor, self._wallParams)[1] then
		return
	end
	self._wallCooldown = wall.Cooldown

	-- Which edge we're pinned against, in car-relative terms. The car's own cross offset is the
	-- signal to trust: what we hit can be a road-length slab whose Position is nowhere near us.
	local info = self._road and self._road:getRoadInfo()
	local towardEdge = primary.CFrame.RightVector
	if info then
		local offset = primary.Position:Dot(info.cross) - info.driveCenter
		towardEdge = if offset >= 0 then info.cross else -info.cross
	end
	local side = if towardEdge:Dot(primary.CFrame.RightVector) >= 0 then 1 else -1
	-- A rail is always a flank hit, so the edge direction doubles as the smoke's hit direction.
	self:applyImpact(side, wall, -1, towardEdge, "Wall")

	-- The server prices it and owns the HP, exactly like an obstacle. No payload: there's
	-- nothing to identify, and the server verifies the car really is at the edge itself.
	self:getRemoteEvent("WallHit"):Fire()
end

--[[ The top of an axis-aligned box around a part, whatever way round the part is turned.

	`Position.Y + Size.Y/2` is only the top of a part that is level, and a delivered prop's pieces
	are turned however the modeller left them. Each local axis contributes its half-extent times
	how much of that axis points up, which is exact and cheaper than walking eight corners. ]]
local function topOf(part: BasePart): number
	local cf, half = part.CFrame, part.Size * 0.5
	return cf.Position.Y
		+ math.abs(cf.RightVector.Y) * half.X
		+ math.abs(cf.UpVector.Y) * half.Y
		+ math.abs(cf.LookVector.Y) * half.Z
end

--[[ WHAT HAPPENS TO THE THING YOU HIT. See ObstacleConfig.Smash for the dials and the argument;
	this is the two shapes they select between.

	WITHOUT `Break` the prop leaves as ONE body: the whole model is thrown, on a single shared
	velocity and spin. That is literally what it is on both threads -- the delivered art is welded
	into one assembly by ObstacleService._fitProp, the primitive fallbacks by `_buildObstacle` --
	and it has to be, because a shared spin written onto LOOSE parts turns each of them about its
	own centre and pulls the object apart in the air.

	WITH `Break` every joint in the prop is cut and each piece is thrown on its own. Only the
	pieces the car could actually have REACHED go — a piece whose top sits under the HitBox's own
	lower edge was under the car rather than in front of it — which is what lets an oil slick lose
	its drum and keep its two flat sheets of spill. That is also why a broken model STAYS in its
	tile: the pieces that didn't move still belong to the road, and the tile's next rebuild is
	what clears them. Only the pieces that fly are reparented out, because a recycle or a world
	rebase moves the tile with Model:PivotTo and would teleport them mid-flight.

	Local instances throughout, so this costs nothing anyone else can see. ]]
function ObstacleController._smash(self, model: Instance?, volume: BasePart, smash)
	if not (model and model:IsA("Model") and self._debris) then
		return
	end

	local base = ObstacleConfig.Smash
	local force = smash.Force or 1
	local primary = self._car and self._car.PrimaryPart
	local carVelocity = primary and primary.AssemblyLinearVelocity or Vector3.zero
	local away = Vector3.zero
	if primary then
		local delta = volume.Position - primary.Position
		local flat = Vector3.new(delta.X, 0, delta.Z)
		if flat.Magnitude > 0.01 then
			away = flat.Unit
		end
	end
	local launch = (carVelocity * base.Carry + Vector3.yAxis * base.Lift + away * base.Push) * force

	local function spin(): Vector3
		return Vector3.new(
			self._rng:NextNumber(-base.Spin, base.Spin),
			self._rng:NextNumber(-base.Spin, base.Spin),
			self._rng:NextNumber(-base.Spin, base.Spin)
		)
	end
	local function loosen(part: BasePart)
		part.CanQuery = false
		part.CanTouch = false
		part.CanCollide = false
		part.Anchored = false
	end

	if not smash.Break then
		model.Parent = self._debris
		--[[ UNANCHOR EVERYTHING BEFORE ANY VELOCITY IS WRITTEN, in two passes rather than one.
			A part still welded to an anchored one belongs to an ANCHORED assembly, and a velocity
			written to an anchored assembly is silently dropped -- the same trap the `Break` path
			below cuts its joints to avoid. One pass would leave the throw resting on the loop
			happening to reach the last part last. ]]
		local parts: { BasePart } = {}
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				loosen(part)
				table.insert(parts, part)
			end
		end
		local tumble = spin()
		for _, part in parts do
			part.AssemblyLinearVelocity = launch
			part.AssemblyAngularVelocity = tumble
		end
		Debris:AddItem(model, base.Life)
		return
	end

	--[[ Cut first, throw second. A WeldConstraint still holding a piece to an ANCHORED one keeps
		the whole assembly anchored, so a velocity written before the cuts is silently dropped —
		and a constraint left behind stays live across the reparent (it holds instance references,
		not a parent relationship), which would tow one piece of the debris back to the road. ]]
	for _, joint in model:GetDescendants() do
		if joint:IsA("WeldConstraint") or joint:IsA("JointInstance") then
			joint:Destroy()
		end
	end

	-- The volume's own bottom face IS the deck: it is built sitting on it.
	local floor = volume.Position.Y - volume.Size.Y * 0.5 + base.Floor
	local scatter = base.Scatter * (smash.Spread or 0) * force
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= volume and topOf(part) > floor then
			part.Parent = self._debris
			loosen(part)
			part.AssemblyLinearVelocity = launch
				+ Vector3.new(
					self._rng:NextNumber(-1, 1),
					self._rng:NextNumber(-0.35, 1),
					self._rng:NextNumber(-1, 1)
				) * scatter
			part.AssemblyAngularVelocity = spin()
			Debris:AddItem(part, base.Life)
		end
	end
end

-- `Humanoid.CameraOffset` is a request, not a transform: something has to read it and move the
-- camera. In a race that's RaceCameraController (its camera is Scriptable, so the stock camera
-- scripts that would normally apply this have stood down) — see _shakeOffset there.
function ObstacleController._updateShake(self, dt: number)
	local humanoid = self._humanoid
	if not (humanoid and humanoid.Parent) then
		return
	end
	if self._shake <= 0.01 then
		if self._shakeApplied then
			humanoid.CameraOffset = Vector3.zero
			self._shakeApplied = false
		end
		return
	end
	self._shake = math.max(0, self._shake - dt * SHAKE_DECAY)
	self._shakeClock += dt
	local t = self._shakeClock
	humanoid.CameraOffset =
		Vector3.new(math.sin(t * 46) * self._shake, math.cos(t * 61) * self._shake * 0.6, 0)
	self._shakeApplied = true
end

-- === Wreck ==================================================================

--[[ Server says the car is dead. It has already torn the driver's control GUI down, which
	kills the stock Driver script — so the four chassis motors are frozen at whatever they
	were last told, and zeroing them here is the last word. Then we coast the car to a stop
	over ~1s while the server holds the wreck beat and fades us back to spawn.

	`cause` distinguishes the ways a run can end, and the difference is entirely about what is on
	screen. An ordinary death is ABOUT THE CAR: it coasts, it smokes, you watch it die. The other two
	have no car worth looking at, so they take the shake and nothing else:

	  • "badLanding" (StealController's whiff) is ABOUT THE PLAYER — they're face down on the tarmac
	    with the camera looking at them, and the car has been deliberately left hidden and anchored
	    underneath so nothing competes with that shot.
	  • "fell" is a car that has dropped out of the world (RaceService's void guard). It is frozen
	    tens of studs below the deck and nowhere near the frame.

	Either way a plume would be smoke in the middle of the shot with no visible source. ]]
function ObstacleController._onWrecked(self, cause: string?)
	if self._wrecked or not self._active then
		return
	end
	self._wrecked = true
	self._shake = math.max(self._shake, 2)
	self._silentWreck = cause == "badLanding" or cause == "fell"

	local car = self._car
	if not car or self._silentWreck then
		return
	end
	for _, inst in car:GetDescendants() do
		if inst:IsA("CylindricalConstraint") then
			inst.MotorMaxTorque = 0
			inst.AngularVelocity = 0
		end
	end

	--[[ ...AND THE ENDING THAT COASTS BUT DOES NOT SMOKE. A police bust (`PoliceConfig.Cause`) is a
		car being pulled over, not a car that has come apart: cutting the motors above is right,
		because it is what makes the car roll to a stop under the cruisers closing in on it, but the
		engine plume is a statement about damage and no damage happened. The car ran out of ROAD,
		not out of HP.

		It is deliberately below the motor cut rather than folded into `_silentWreck`, which is the
		flag for "there is no car in this shot at all". There very much is one here, and it is the
		thing the shot is of. ]]
	if cause == PoliceConfig.Cause then
		return
	end

	--[[ The delivered wreck set (`CrashVfxConfig.Wreck`: fire, black smoke, the big smoke) on the
		car's hood, replacing the plain plume below while `ReplaceWreckSmoke` is on and the effects were
		found. Anything else keeps the plume, so a wreck never goes up without smoke. ]]
	local wreckSound = CrashSoundConfig.Wreck
	local sounds = Shard.get("SoundController")
	if CrashSoundConfig.Enabled and sounds and car.PrimaryPart then
		sounds:PlayRandomAt(wreckSound.Group, car.PrimaryPart, wreckSound.Pitch, wreckSound.Volume, CrashSoundConfig.RollOffMin, CrashSoundConfig.RollOffMax)
	end

	local vfx = Shard.get("CrashVfxController")
	local burning = vfx ~= nil and vfx:wreck(car)
	local anchor = self._hitBox or car.PrimaryPart
	if anchor and not (burning and CrashVfxConfig.ReplaceWreckSmoke) then
		local smoke = Instance.new("Smoke")
		smoke.Name = "WreckSmoke"
		smoke.Color = Color3.fromRGB(38, 38, 42)
		smoke.Opacity = 0.35
		smoke.RiseVelocity = 12
		smoke.Size = 8
		smoke.Parent = anchor
		self._smoke = smoke
	end

	--[[ ...and hand the car to the results screen while it still exists, which is the last moment it
		does: `RaceService` teleports the player home behind the return fade and destroys the car on
		the way, several seconds before the screen that shows it goes up. `GetawayController._bank`
		hands the BANKED car in for exactly this reason, and this is the other half of that.

		IT IS DELIBERATELY DOWN HERE, PAST BOTH OF THE RETURNS ABOVE, and the placement is the
		contract rather than a convenience. Everything they filter out is either an ending with no
		car worth looking at (a bail face down on the tarmac, a car frozen out of the world) or one
		with a better picture to show (a bust puts the cruiser in the slot instead). So the results
		screen shows a wreck for exactly the endings the WORLD showed a wreck for, and it does that
		because it is the SAME test rather than a second one written to agree with this one. ]]
	local results = self._results or Shard.get("RaceUIController")
	self._results = results
	if results then
		results:setWreck(car)
	end
end

--[[ The wreck was paid out of (`ReviveService`): the car is going back on the road, so stop killing
	it. The exact inverse of `_onWrecked`, and only of `_onWrecked` — the obstacle course, the tiles
	it is built on and the set of ids already consumed are all untouched, because none of them
	changed. The road the player is about to drive is the road they were already on.

	THE MOTORS ARE NOT PUT BACK, and that is not an omission. `_onWrecked` zeroes `MotorMaxTorque` as
	the last word after the driver GUI has gone, but the chassis re-asserts that value from its own
	tuning attributes every frame the stock Driver script runs — so re-deploying the controls (which
	`RaceService.reviveRace` does a beat after this arrives) restores them by itself. Writing a guess
	here would be a guess overwritten on the next frame.

	The plume is destroyed rather than merely disabled, because `_teardown` does not track it and a
	disabled Smoke welded to a car that survives the run is a plume waiting to be switched back on by
	the next wreck's `_onWrecked` creating a second one beside it. ]]
function ObstacleController._onRevived(self)
	if not self._wrecked then
		return
	end
	self._wrecked = false
	self._silentWreck = false
	self._shake = 0
	--- The results screen drops the wreck it was holding, on the same terms as the plume below.
	--- `RaceService.reviveRace` states the rule: a `RaceWrecked` reaction with no inverse here is a
	--- reaction that never comes back off, and this one is a wreck of the car they are still driving.
	local results = self._results or Shard.get("RaceUIController")
	self._results = results
	if results then
		results:clearWreck()
	end

	if self._smoke then
		self._smoke:Destroy()
		self._smoke = nil
	end
	--- ...and the delivered wreck fire (`CrashVfxController.wreck`), on the same terms as the plume.
	local vfx = Shard.get("CrashVfxController")
	if vfx then
		vfx:revived()
	end
end

function ObstacleController._dampWreck(self, dt: number)
	local primary = self._car and self._car.PrimaryPart
	if not primary then
		return
	end
	local factor = math.exp(-dt * WRECK_DAMP)
	local velocity = primary.AssemblyLinearVelocity
	-- Horizontal only: let gravity keep doing its thing if we're mid-air.
	primary.AssemblyLinearVelocity = Vector3.new(velocity.X * factor, velocity.Y, velocity.Z * factor)
	primary.AssemblyAngularVelocity = primary.AssemblyAngularVelocity * factor
end

-- === Loop / lifecycle =======================================================

-- Our car and rider, pulled from RoadController (which already resolves the car from the
-- seat we're welded to). Cheap to re-check, and it self-heals if either arrives late.
function ObstacleController._resolveCar(self)
	local car = self._road and self._road:getCar()
	if car ~= self._car then
		self._car = car
		self._hitBox = nil
		self._carBoxCache = nil -- re-measured per car; a redress can be any size
	end
	-- The car Model replicates piecemeal, so the HitBox can arrive a beat after the Model
	-- does. Keep asking until it shows up instead of latching the first (nil) answer —
	-- getting this wrong silently disables every hit for the whole race.
	if car and not (self._hitBox and self._hitBox.Parent) then
		self._hitBox = car:FindFirstChild(ObstacleConfig.HitBoxName, true)
	end
	if not (self._humanoid and self._humanoid.Parent) then
		local character = Players.LocalPlayer.Character
		self._humanoid = character and character:FindFirstChildOfClass("Humanoid")
	end
end

--[[ The car has just been set down on the road: hold the scrape check off until it has stopped
	bouncing on its suspension.

	`RaceService` anchors a car while it is being placed and unanchors it to hand it over, so that
	transition is the one signal meaning "this car is being dropped onto its springs right now" —
	and it is the same signal for entering a race, being revived, and landing a steal. Only the
	wall check needs it: a vertical dip cannot produce an obstacle or traffic clip (those are query
	volumes standing on the deck, and both spots are cleared before a car is set down), but the
	wall check works by overlapping the road itself, so a car inside the deck reads as a rail.

	See ObstacleConfig.Wall.SettleTime for the measurement. ]]
function ObstacleController._watchSettle(self)
	local primary = self._car and self._car.PrimaryPart
	if not primary then
		self._wasAnchored = true -- no car yet; whatever turns up is turning up anchored
		return
	end
	if self._wasAnchored and not primary.Anchored then
		self._settleUntil = os.clock() + ObstacleConfig.Wall.SettleTime
	end
	self._wasAnchored = primary.Anchored
end

function ObstacleController._loop(self, dt: number)
	if not self._active then
		return
	end
	-- Slow motion, if a steal is running one (Modules/TimeScale). Applied once, at the top, so
	-- everything below — the shake decay, the wall cooldown, the wreck coast — stretches together
	-- rather than each having to remember. 1.0 whenever no flight is in progress, which makes this
	-- line a no-op in every other frame the game will ever run.
	dt *= TimeScale.get()
	self:_resolveCar()
	-- Above every early return below it: the car is set down while suspended (a steal landing) and
	-- while wrecked (a revive), and both of those drops need the same grace an entry does.
	self:_watchSettle()
	self:_reconcileTiles()
	--- Immediately after the reconcile that queues them, so a course opens on the same frame its
	--- tile recycled and only the ~25 `prop:Clone()` calls are spread out behind it.
	--- See `ObstacleConfig.BuildBudget`.
	self:_stepCourses()
	-- The rain's puddles, on the same frame's tile indices. Above the wreck branch with the rest of the
	-- road: a wrecked car still sits on a road the player is looking at.
	self:_reconcilePuddles()
	--[[ After the reconcile, so a tile rebuilt this frame draws its weeds in the right place
		immediately rather than one frame behind the road. Above the wreck branch for the reason
		the impact puff is: a wrecked car is still sitting on a road the player is looking at, and
		freezing every tumbleweed on it the instant you die is a very visible seam. ]]
	self._visualAccumulator += dt
	local visualInterval = math.max(0, ObstacleConfig.VisualInterval or 0)
	local poseVisuals = visualInterval == 0 or self._visualAccumulator >= visualInterval
	local visualDt = self._visualAccumulator
	if poseVisuals then
		self._visualAccumulator = 0
	end

	-- Collision/query volumes remain full-rate; only the visible prop transform is decimated.
	self:_updateRollers(dt, poseVisuals)
	-- Beside the sweeps and for their reasons: after the reconcile so a tile rebuilt this frame
	-- floats its packs in the right place immediately, and above the wreck branch so a road the
	-- player is still looking at does not freeze solid the instant they die.
	if poseVisuals then
		self:_updatePickups(visualDt)
	end
	self:_updateShake(dt)
	-- Drive the impact puff here rather than on a timer, so it can't outlive a teardown. Sits
	-- above the wreck branch on purpose: a hit puff still needs closing out if that hit was
	-- the fatal one, and the wreck grows its own (much bigger) plume from _onWrecked.
	if self._puffSmoke and self._puffSmoke.Enabled then
		if os.clock() >= self._puffUntil then
			self._puffSmoke.Enabled = false
		else
			-- Keep emitting beside the car as it moves, laying a trail instead of a single
			-- point the car is already 50 studs past.
			local cframe = self:_puffCFrame(self._puffDir)
			if cframe then
				self._puff.CFrame = cframe
			end
		end
	end
	if self._wrecked then
		-- Nothing to coast on a bad landing: the car is anchored and hidden where the bail left it,
		-- and writing velocity onto an anchored assembly is thrown away anyway.
		if not self._silentWreck then
			self:_dampWreck(dt)
		end
		return -- a wreck takes no further damage
	end
	-- Airborne (StealController). YOU CANNOT BE CLIPPED IN MID-AIR: the car is hidden, anchored and
	-- being flown along the deck under the flight avatar, so it is still physically inside the
	-- course it was about to hit — and every barrier it passes through would charge HP for a
	-- collision nobody can see. The wall sensor is suspended for the same reason.
	if self._suspended then
		return
	end
	self:_checkHits()
	self:_checkWall(dt)
end

--[[ PUBLIC (StealController) — stop and restart hit reporting for a flight.

	Not a teardown: the shake, the impact puff and the tile reconciliation all keep running, because
	a hit taken a moment before the bail still has to finish selling itself and the road still has to
	stream. Only the two things that could COST HP are switched off.

	Resuming drops the cached bounding box, because a steal can hand us a differently proportioned
	car and that box is what the impact puff is placed against — a stale one puts the smoke inside
	the new bodywork. (One body in the roster today, so this is insurance rather than a live fix;
	`_resolveCar` already clears it when the car MODEL changes, and a steal deliberately keeps the
	same model.) ]]
function ObstacleController.setSuspended(self, suspended: boolean)
	self._suspended = suspended
	if not suspended then
		self._carBoxCache = nil
	end
end

function ObstacleController._onRaceStart(self, seed: any, world: any, bench: any)
	self:_teardown()
	--- Either layer is reason to build: with the course off the layout still carries the health and
	--- nitro packs (`ObstacleLayout.forTile`, 2026-09-28), and this is what puts them on the road.
	if not (ObstacleConfig.Enabled or PickupConfig.Enabled) then
		return
	end
	if type(seed) ~= "number" then
		self.log:warn("Race started without an obstacle seed; running this race obstacle-free.")
		return
	end
	if not self._road then
		self.log:warn("RoadController unavailable; cannot build obstacles.")
		return
	end

	self._seed = seed
	self._active = true
	--[[ The world arrives with RaceStart for the same reason RoadController's does: it is a
		property of the run being started, not of the player as they are right now, and this is
		the first authoritative word the client has about which road it is on. Nil (an older
		server, or a race started without one) simply means no prop art, so every kind builds
		from primitives — the pre-art behaviour, intact. ]]
	--[[ THE ADMIN BENCH, or nil for every ordinary run (`ObstacleConfig.Bench`). Read through the
		same sanitiser the server ran it through, which is idempotent and so cannot move a field:
		what that buys is a table this file can index without checking a type, and a printed promise
		that the two sides are building from the same thing.

		Kept for the length of the race like the map is, and for the same reason: `_beginCourse`
		re-derives a tile's list every time a tile is recycled, long after this has returned. ]]
	self._bench = ObstacleLayout.sanitizeBench(bench)
	if self._bench then
		self.log:info(string.format(
			"Obstacle bench: %s every %d studs, first at %d. This road is not the ramp.",
			self._bench.course or self._bench.kind or "?",
			self._bench.spacing,
			self._bench.lead
		))
	end

	local map = world ~= nil and WorldConfig.mapFor(world) or nil
	--[[ Kept, because the map now decides the LAYOUT and not just the art: which obstacle set this
		road is built from is `ObstacleConfig.TiersByMap[map]`, and `_beginCourse` re-derives a tile's
		course list every time a tile is recycled — long after this handler has returned. ]]
	self._map = map
	local props = ReplicatedStorage:FindFirstChild(ObstacleConfig.PropFolderName)
	self._propFolder = map and props and props:FindFirstChild(map) or nil

	local debris = Instance.new("Folder")
	debris.Name = ObstacleConfig.DebrisFolderName
	debris.Parent = workspace
	self._debris = debris

	-- Query-only volume that shadows the car's HitBox but reaches further out each side, so a
	-- scrape registers just before the car is physically stopped. Client-local like everything
	-- else here; _checkWall poses and sizes it from the live hull each time it runs.
	local sensor = Instance.new("Part")
	sensor.Name = "WallSensor"
	sensor.Anchored = true
	sensor.Transparency = 1
	sensor.CastShadow = false
	sensor.CanCollide = false
	sensor.CanTouch = false
	sensor.CanQuery = true -- it IS the query shape; nothing here runs an unfiltered query
	sensor.Parent = workspace
	self._wallSensor = sensor

	-- One reusable impact-smoke emitter for the whole race (see _emitHitSmoke). Kept disabled
	-- until a hit fires it; a second hit mid-puff just repositions it and restarts the timer,
	-- and already-emitted particles carry on independently.
	if ObstacleConfig.HitSmoke.Enabled then
		local puff = Instance.new("Part")
		puff.Name = "HitSmoke"
		puff.Size = Vector3.one * 0.2
		puff.Anchored = true
		puff.Transparency = 1
		puff.CastShadow = false
		puff.CanCollide = false
		puff.CanQuery = false
		puff.CanTouch = false
		puff.Parent = workspace

		local smoke = Instance.new("Smoke")
		smoke.Color = ObstacleConfig.HitSmoke.Color
		smoke.Opacity = ObstacleConfig.HitSmoke.Opacity
		smoke.RiseVelocity = ObstacleConfig.HitSmoke.RiseVelocity
		smoke.Size = ObstacleConfig.HitSmoke.MinSize
		smoke.Enabled = false
		smoke.Parent = puff

		self._puff = puff
		self._puffSmoke = smoke
	end

	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_loop(dt)
	end)
end

function ObstacleController._teardown(self)
	self._active = false
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	if self._smoke then
		self._smoke:Destroy()
		self._smoke = nil
	end
	if self._debris then
		self._debris:Destroy()
		self._debris = nil
	end
	if self._wallSensor then
		self._wallSensor:Destroy()
		self._wallSensor = nil
	end
	if self._puff then
		self._puff:Destroy()
		self._puff = nil
	end
	self._puffSmoke = nil
	self._puffUntil = 0
	self._puffDir = Vector3.xAxis
	self._carBoxCache = nil
	-- The folders normally die with the tiles when RoadController drops the local road;
	-- clearing them here too keeps this correct whichever order the RaceEnd handlers run in.
	for _, folder in self._folders do
		if folder.Parent then
			folder:Destroy()
		end
	end
	table.clear(self._folders)
	table.clear(self._built)
	--[[ The course in flight is built off-tree, so unlike everything else here it is NOT carried
		away by the tile folders dying above — nothing else references it and nothing else would
		ever collect it. Destroyed explicitly, and the queue behind it dropped: its tiles belong to
		a race that is over. ]]
	if self._courseJob then
		self._courseJob.folder:Destroy()
		self._courseJob = nil
	end
	table.clear(self._courseQueue)
	-- The puddle folders are inside tiles that die with the road, but a race can end in either order.
	for _, entry in self._puddled do
		if entry.folder then
			entry.folder:Destroy()
		end
	end
	table.clear(self._puddled)
	self._dressedFor = nil
	self:_dropSpray()
	table.clear(self._consumed)
	table.clear(self._rollers)
	table.clear(self._pickups)
	table.clear(self._warnedMissing)
	self._rollClock = 0
	self._pickupClock = 0
	self._visualAccumulator = 0
	self._overlapParams.FilterDescendantsInstances = {}
	self._wallParams.FilterDescendantsInstances = {}
	-- Cleared with the race, not kept: the next one can be in a different world (see `_prop`).
	self._propFolder = nil
	self._map = nil
	--- Same reason as the map: the next race is armed separately, and a bench left standing here
	--- would have the run after this one built from a road nobody asked for.
	self._bench = nil
	table.clear(self._props)

	if self._humanoid and self._humanoid.Parent then
		self._humanoid.CameraOffset = Vector3.zero
	end
	self._shake = 0
	self._shakeApplied = false
	self._wallCooldown = 0
	self._settleUntil = 0
	self._wasAnchored = true
	self._seed = nil
	self._car = nil
	self._hitBox = nil
	self._humanoid = nil
	self._wrecked = false
	self._silentWreck = false
	self._suspended = false
end

ObstacleController:withRemoteEvents({
	{
		RaceStart = function(seed, world, _laneOffset, bench)
			ObstacleController:_onRaceStart(seed, world, bench)
		end,
		RaceWrecked = function(cause)
			ObstacleController:_onWrecked(cause)
		end,
		RaceRevived = function()
			ObstacleController:_onRevived()
		end,
		RaceEnd = function()
			ObstacleController:_teardown()
		end,
	},
	"ObstacleHit",
	"WallHit",
})

ObstacleController:withLifecycle({
	init = function(self)
		self._built = {} -- [tile Model] = TileIndex we last built obstacles for
		self._folders = {} -- [tile Model] = that tile's Obstacles folder (only once fully laid)
		--- Courses waiting to be laid, and the one being laid right now. See `_stepCourses`.
		self._courseQueue = {}
		self._courseJob = nil
		self._consumed = {} -- [obstacleId] = true, for this race
		self._props = {} -- [kind] = this world's published prop, or false for "no art"
		self._propFolder = nil -- ReplicatedStorage.ObstacleProps.<map>, resolved at RaceStart
		self._map = nil -- this race's map name; picks both the prop folder and the obstacle set
		--- The admin bench this race is being driven on, or nil for the seeded ramp. Arrives with
		--- `RaceStart` for the same reason the map does: it is what the road is BUILT from.
		self._bench = nil
		self._rollers = {} -- [tile Model] = that tile's `Roll` obstacles (see _updateRollers)
		self._rollClock = 0 -- seconds of race time driving the sweeps; reset with the race
		self._pickups = {} -- [tile Model] = that tile's health/nitro packs (see _updatePickups)
		self._pickupClock = 0 -- ...and their own clock, so the bob and the sweeps never share a phase
		--- [tile Model] = { index, folder, ripples } for the rain's puddles on it (`_reconcilePuddles`).
		self._puddled = {}
		--- The `Puddles` spec the road's puddles are dressed for, nil when dry. A change of sky is a
		--- change of this, and it re-dresses every puddle and switches the ripples (`_reconcilePuddles`).
		self._dressedFor = nil
		self._weatherController = nil -- WeatherController, resolved lazily in `_puddleSpec`
		self._sprayRig = nil -- the puddle spray's two emitters on the car's hit box (`_spray`)
		self._visualAccumulator = 0 -- accumulated race time for 30 Hz cosmetic obstacle poses
		self._warnedMissing = {} -- [kind] = true once we've said it has no art and no fallback
		self._active = false
		self._police = nil -- PoliceController, for the strike report in `applyImpact`
		self._results = nil -- RaceUIController, for the wreck it shows on the way home
		self._wrecked = false
		self._silentWreck = false -- a bad landing: no plume, no coast — see _onWrecked
		self._suspended = false -- true while airborne (StealController); no HP may move
		self._shake = 0
		self._shakeClock = 0
		self._shakeApplied = false
		self._wallCooldown = 0 -- seconds until the road edge can chip us again
		self._settleUntil = 0 -- os.clock() until which a scrape can't register (Wall.SettleTime)
		self._wasAnchored = true -- a car arrives anchored; the release is what starts the settle
		self._puffUntil = 0 -- os.clock() at which the impact puff stops emitting
		self._puffDir = Vector3.xAxis -- car-local direction the puff is trailing from
		self._carBoxCache = nil -- cached bounding box; the puff is placed on its surface
		self._rng = Random.new()

		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = {}
		params.RespectCanCollide = false -- our volumes are deliberately non-colliding
		params.MaxParts = 8 -- plowing a wall can legitimately clip a few at once
		self._overlapParams = params

		-- Separate params for the road-edge contact test. RespectCanCollide is ON here (the
		-- opposite of the obstacle query above) because it's what reduces a whole road tile to
		-- just the things that can physically stop the car; one part is all we need.
		local wallParams = OverlapParams.new()
		wallParams.FilterType = Enum.RaycastFilterType.Include
		wallParams.FilterDescendantsInstances = {}
		wallParams.RespectCanCollide = true
		wallParams.MaxParts = 1
		self._wallParams = wallParams
	end,

	start = function(self)
		self._road = Shard.get("RoadController")
		--[[ Resolved here AND lazily in `applyImpact`, because `Shard`'s `start` runs off a hash
			table and is not ordered by `withDependencies` (which orders `init` only). Either half
			on its own would work in practice; the pair costs one field and cannot be the thing that
			makes a chase silently stop noticing crashes. ]]
		self._police = Shard.get("PoliceController")
	end,
})

return ObstacleController
