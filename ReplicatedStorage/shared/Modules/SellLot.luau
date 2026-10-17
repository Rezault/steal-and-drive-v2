--[[
	SellLot  (shared)
	-----------------
	HOW THE SELL LOT IS MADE. One copy of the geometry, called from two places that must never
	disagree about it:

	    BuildSellLot (Command Runner)  -> authors a lot into the place, for the artist to edit
	    SellService                    -> binds the authored one; builds one only if there is none

	=== WHY THIS IS A MODULE AND NOT JUST THE SERVICE'S PRIVATE FUNCTIONS =====================

	The lot was derived-at-run-time first, which made it immune to a map swap and impossible to
	restyle. The owner asked for it to be authored so it can be changed by hand, and the honest way
	to do that is to build it ONCE with this code, save it in the place, and let the service adopt
	whatever it finds. What it must not become is two builders — one that authors and one that
	falls back — because they drift, and the day they drift is the day a lot somebody dragged looks
	nothing like the lot a fresh server builds.

	So: this file draws it, `SellConfig` has every number, and nothing else builds any of it.

	=== WHAT THE AUTHORED MODEL OWES THE SERVICE =============================================

	Two things, by NAME (`SellConfig.Names`), and everything else is the artist's:

	  • `SellPad`   — THE VOLUME. Whether a car is "in the lot" is a point-in-box test against this
	                  part's own CFrame and Size, so moving or resizing the pad moves the sell area
	                  with it and nothing has to be re-derived. Delete it and the lot cannot work.
	  • `SellBubbleAnchor` — an Attachment on the pad the client's price sign adorns to. Optional:
	                  the service re-creates it from `Bubble.Height` if it has gone.

	IT WAS THREE UNTIL 2026-08-31. `SellButton`, the Attachment the held prompt hung from, is gone
	with the prompt — `strip` takes both back off a lot authored before that date.

	Everything else — the curtain of light, the border, the sign, the paint — can be replaced with
	the modeller's own art and nothing in code will notice or care.

	=== 2026-08-24: IT IS A SQUARE NOW =======================================================

	It was a three-bay car park 54 studs across with a beam wall at one end. The owner asked for
	something smaller that does not read as a parking bay, and for the beam wall to be the
	continuous one a tycoon draws round a button rather than a row of pickets across the back. So:
	a 30 x 30 pad, a border instead of bay lines, the curtain walked all the way round the edge, the
	sign moved onto a pole behind it, and the collidable back slab deleted outright. `SellConfig`'s
	`Pad` and `Fence` carry the reasoning; nothing about WHAT may be sold changed.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotConfig = require(ReplicatedStorage.shared.Configs.PlotConfig)
local SellConfig = require(ReplicatedStorage.shared.Configs.SellConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)

local SellLot = {}

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

-- === Finding a spot =========================================================

--[[ The island's vertical extent, for the ground probe to start above.

	`Workspace.Map` is a FOLDER in this place, and a Folder has no bounding box — so this falls back
	to a sweep that covers any plausible island altitude rather than to a raycast that starts
	underground. Returns nil for the map when there is no island at all, which every caller treats as
	"there is nothing to build on". ]]
local function mapExtent(): (Instance?, number, number)
	local map = workspace:FindFirstChild(PlotConfig.MapName)
	if not map then
		return nil, 0, 0
	end
	if map:IsA("Model") then
		local frame, size = map:GetBoundingBox()
		return map, frame.Position.Y + size.Y / 2, frame.Position.Y - size.Y / 2
	end
	return map, 1000, -1000
end

--[[ Where the floor is under a point, in world space, or nil if there is nothing under it.

	SCOPED TO THE MAP, which is what makes it an answer about the island rather than about whatever
	happens to be standing there — a player, a lobby car parked on the roundabout, or the lot's own
	pad would all otherwise read as ground. ]]
local function groundAt(map: Instance, topY: number, bottomY: number, x: number, z: number): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { map }

	local lot = SellConfig.Lot
	local origin = Vector3.new(x, topY + lot.ProbeUp, z)
	local reach = lot.ProbeUp + lot.ProbeDown + (topY - bottomY)
	local hit = workspace:Raycast(origin, Vector3.new(0, -reach, 0), params)
	return if hit then hit.Position.Y else nil
end

--[[ Is there room for the lot here?

	`GetPartsInPart` AND NOT `GetPartBoundsInBox`, and the difference is the whole test: the plaza's
	ground is Blender geometry whose bounding box covers the entire island, so a bounds query reports
	every candidate as blocked by the floor it is standing on. `GetPartsInPart` uses real collision
	geometry, and the probe is lifted `Fit.Lift` clear of the asphalt so the floor cannot answer.

	NOT CAPPED. `MaxParts` truncates the QUERY rather than the result list, so a cap on a test whose
	whole answer is "is this empty?" would be answering a different question. ]]
local function clearAt(probe: BasePart, ignore: { Instance }, position: Vector3, facing: CFrame): boolean
	local fit = SellConfig.Lot.Fit
	local centre = position + Vector3.new(0, fit.Lift, 0)
	probe.Size = fit.Clearance
	probe.CFrame = CFrame.lookAt(centre, centre + facing.LookVector, Vector3.yAxis)

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore

	return #workspace:GetPartsInPart(probe, params) == 0
end

--[[ Where the lot goes: its frame, whether the bearing it landed on was actually clear, and a line
	saying what happened.

	POSITION AND FACING ARE SEPARATE, and that separation is the fix for the first placement.
	`Bearing`/`Radius` say WHERE on the plaza the lot stands; `EntranceBearing` says which way its
	mouth points, and nothing derives one from the other. The frame's LookVector is the OPPOSITE of
	the entrance bearing — forward is into the lot, where the wall is — so a car drives in along the
	entrance bearing and comes to rest nose-first at the wall with the sign in front of it.

	Until 2026-08-24 the frame always looked radially outward, which put the wall across the mouth of
	the plaza entry road. `SellConfig.Lot`'s header has that whole story.

	Stepped both ways alternately (+3, -3, +6, -6 ...) when the ideal bearing is blocked, so a nudged
	lot lands as close as possible to where it was wanted. A bearing with no ground under any of the
	footprint's five probes, or a footprint that is not flat, is not a candidate at all — a lot half
	on a kerb passes an overlap test and still looks broken, because the pad is one flat slab and the
	ground under it is not.

	`ignore` is whatever must not count as an obstruction: on a re-run that is the lot already
	standing there. ]]
function SellLot.findPose(bearing: number?, radius: number?, ignore: { Instance }?): (CFrame?, boolean, string)
	local cfg = SellConfig.Lot
	local map, topY, bottomY = mapExtent()
	if not map then
		return nil, false, string.format("No %s in Workspace — there is no island to put a lot on.", PlotConfig.MapName)
	end

	local wantBearing = if type(bearing) == "number" then bearing else cfg.Bearing
	local wantRadius = if type(radius) == "number" and radius > 0 then radius else cfg.Radius
	local centre = Vector2.new(cfg.CentreX, cfg.CentreZ)

	--- One part, reused for every test and parented outside the lot so it can never be its own
	--- answer. It is the SUBJECT of the query, never a candidate for one.
	local probe = Instance.new("Part")
	probe.Name = "SellLotProbe"
	probe.Anchored = true
	probe.CanCollide = false
	probe.CanQuery = false
	probe.CanTouch = false
	probe.Transparency = 1
	probe.Size = cfg.Fit.Clearance
	probe.Parent = workspace

	local skip: { Instance } = { probe }
	for _, instance in ignore or {} do
		table.insert(skip, instance)
	end

	local function poseAt(degrees: number): (CFrame?, boolean)
		local radians = math.rad(degrees)
		local x = centre.X + math.sin(radians) * wantRadius
		local z = centre.Y + math.cos(radians) * wantRadius
		local groundY = groundAt(map, topY, bottomY, x, z)
		if not groundY then
			return nil, false
		end

		local position = Vector3.new(x, groundY, z)
		--- Forward is INTO the lot, i.e. against the way a car drives in. `EntranceBearing` is a
		--- compass bearing in the same convention as everything else here: 0 = +Z, clockwise.
		local entrance = math.rad(cfg.EntranceBearing or 0)
		local inward = Vector3.new(-math.sin(entrance), 0, -math.cos(entrance))
		local frame = CFrame.lookAt(position, position + inward, Vector3.yAxis)

		local lowest, highest = groundY, groundY
		local halfX, halfZ = SellConfig.Pad.Width / 2, SellConfig.Pad.Depth / 2
		for _, offset in { Vector3.new(-halfX, 0, -halfZ), Vector3.new(halfX, 0, -halfZ), Vector3.new(-halfX, 0, halfZ), Vector3.new(halfX, 0, halfZ) } do
			local corner = frame * offset
			local cornerY = groundAt(map, topY, bottomY, corner.X, corner.Z)
			if not cornerY then
				return nil, false
			end
			lowest = math.min(lowest, cornerY)
			highest = math.max(highest, cornerY)
		end
		if highest - lowest > cfg.MaxSlope then
			return frame, false
		end

		return frame, clearAt(probe, skip, position, frame)
	end

	local frame, clear = poseAt(wantBearing)
	local nudged: number? = nil
	if not (frame and clear) then
		local fallback = frame
		for step = 1, math.max(0, cfg.Fit.MaxSteps) do
			for _, sign in { 1, -1 } do
				local tried, ok = poseAt(wantBearing + sign * step * cfg.Fit.StepDegrees)
				if tried then
					fallback = fallback or tried
					if ok then
						frame, clear, nudged = tried, true, wantBearing + sign * step * cfg.Fit.StepDegrees
						break
					end
				end
			end
			if clear then
				break
			end
		end
		if not clear then
			frame = fallback
		end
	end

	probe:Destroy()

	if not frame then
		return nil, false, string.format("No ground under bearing %d at r=%d, or any bearing near it.", wantBearing, wantRadius)
	end
	if not clear then
		return frame,
			false,
			string.format(
				"Nothing within %d degrees of bearing %d at r=%d is clear — placed at the ideal bearing anyway. Check the plaza there.",
				cfg.Fit.MaxSteps * cfg.Fit.StepDegrees,
				wantBearing,
				wantRadius
			)
	end
	if nudged then
		return frame, true, string.format("Bearing %d was blocked; the lot moved to %d.", wantBearing, nudged)
	end
	return frame, true, string.format("Bearing %d at r=%d was clear.", wantBearing, wantRadius)
end

-- === Building it ============================================================

--- One anchored, uncollidable, unqueryable slab in the lot's frame. EVERYTHING the lot is made of
--- goes through here, with no exceptions since the collidable back wall was deleted, so "is any of
--- this in the way of a car?" has one answer for the whole model: no.
local function slab(name: string, size: Vector3, cframe: CFrame, colour: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = material
	part.Color = colour
	part.Size = size
	part.CFrame = cframe
	return part
end

--[[ The floor: one painted square, with a line painted round its edge.

	THE SLAB IS THE VOLUME — the server and the client both measure against exactly this part, so its
	size and CFrame are a contract and not just a look. Move it in Studio and the sell area moves.

	THE BORDER REPLACED THE BAY DIVIDERS on 2026-08-24. Three lines across a slab is a car park at
	any size; one line round the outside is a marked-out square, and it is also what the curtain
	stands on, so the light comes out of something instead of starting in mid-asphalt.

	The lines are separate parts sitting a fraction proud of the slab rather than decals on it,
	because a decal on a part that is itself a third of a stud off the asphalt is two coplanar
	surfaces fighting for the same pixels.

	NOTHING HERE COLLIDES. A slab standing proud of the road with collision on is a kerb across the
	entrance, which is the exact fault the world road tiles shipped with. ]]
local function buildFloor(model: Model, frame: CFrame): BasePart
	local cfg = SellConfig.Pad
	local border = cfg.Border

	local pad = slab(
		SellConfig.Names.Pad,
		Vector3.new(cfg.Width, cfg.Thickness, cfg.Depth),
		frame * CFrame.new(0, cfg.Lift - cfg.Thickness / 2, 0),
		cfg.Color,
		cfg.Material
	)
	pad.Transparency = cfg.Transparency
	pad.Parent = model

	--[[ Four lines, mitred: the pair across the square run its full width and the pair along it stop
		short of them, so the corners meet cleanly instead of stacking two slabs in the same place
		(two coplanar slabs z-fight, and at this size the flicker is the first thing you see). ]]
	local top = cfg.Lift + 0.05
	local width = border.Width
	for _, side in { -1, 1 } do
		local across = slab(
			SellConfig.Names.Border,
			Vector3.new(cfg.Width, cfg.Thickness, width),
			frame * CFrame.new(0, top - cfg.Thickness / 2, side * (cfg.Depth / 2 - width / 2)),
			border.Color,
			Enum.Material.SmoothPlastic
		)
		across.Parent = model

		local along = slab(
			SellConfig.Names.Border,
			Vector3.new(width, cfg.Thickness, cfg.Depth - width * 2),
			frame * CFrame.new(side * (cfg.Width / 2 - width / 2), top - cfg.Thickness / 2, 0),
			border.Color,
			Enum.Material.SmoothPlastic
		)
		along.Parent = model
	end

	return pad
end

--[[ The wall of light: one invisible box the curtain hangs on, and FOUR beams, one per edge, each
	as wide as its edge is long.

	NOTHING HERE COLLIDES, WHICH IS THE POINT OF THE SHAPE. The old wall stood across the back of the
	lot with an invisible collidable slab behind it; a curtain that surrounds the square cannot have
	one, because the way in is through it. `SellConfig.Fence`'s header has what that costs.

	EACH BEAM IS VERTICAL AND WIDENED SIDEWAYS, which is the shape that gets both things this look
	needs out of one instance. A Beam's transparency gradient runs along its LENGTH, so the beam has
	to run bottom-to-top for the fade to exist; its WIDTH is then free to span the whole edge. Seven
	studs long, `Pad.Width` studs wide, and the width is read off the pad rather than configured, so
	resizing the square keeps the wall on its edge.

	`FaceCamera` IS OFF and the attachments' rotation is therefore what decides the ribbon's plane.
	A BEAM'S WIDTH FOLLOWS ITS ATTACHMENTS' +Y, which is measured rather than documented (see
	`Fence.RibbonRoll`), so the frames below point +X up the beam and put the edge's own direction on
	+Y. Identity attachments on a vertical beam draw nothing at all, which is the fastest way to
	confirm it. ]]
local function buildFence(model: Model, frame: CFrame): BasePart
	local cfg = SellConfig.Fence
	local pad = SellConfig.Pad

	--[[ One invisible box the size of the square. It exists so the attachments have somewhere to
		live that is NOT the pad: the pad is the volume contract and the client measures against its
		size, and burying 160 attachments in it makes the one part everybody reads unreadable. ]]
	local host = slab(
		SellConfig.Names.Fence,
		Vector3.new(pad.Width, cfg.Height, pad.Depth),
		frame * CFrame.new(0, cfg.Height / 2, 0),
		cfg.Color,
		Enum.Material.SmoothPlastic
	)
	host.Transparency = 1
	host.Parent = model

	--[[ The fade, bottom to top. Four keypoints: full strength off the ground, held for `Base` of
		the height so the light has a skirt, half way to `Head` at `Bias`, and gone at the top. ]]
	local foot = math.clamp(cfg.Foot, 0, 1)
	local head = math.clamp(cfg.Head, 0, 1)
	local base = math.clamp(cfg.Base, 0, 0.4)
	local bias = math.clamp(cfg.Bias, base + 0.05, 0.95)
	local transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, foot),
		NumberSequenceKeypoint.new(base, foot),
		NumberSequenceKeypoint.new(bias, foot + (head - foot) / 2),
		NumberSequenceKeypoint.new(1, head),
	})

	--- The four edges in the host's own frame: where the middle of each one is, which way it runs,
	--- and how long it is. A rectangle works as well as a square; nothing here assumes they are equal.
	local halfX, halfZ = pad.Width / 2, pad.Depth / 2
	local edges = {
		{ middle = Vector3.new(0, 0, -halfZ), run = Vector3.xAxis, length = pad.Width },
		{ middle = Vector3.new(0, 0, halfZ), run = Vector3.xAxis, length = pad.Width },
		{ middle = Vector3.new(-halfX, 0, 0), run = Vector3.zAxis, length = pad.Depth },
		{ middle = Vector3.new(halfX, 0, 0), run = Vector3.zAxis, length = pad.Depth },
	}

	--- Rolled about the beam's own axis, which after the matrix below is the attachment's +X, i.e.
	--- straight up. `Fence.RibbonRoll` is 0 and its note says why; 90 builds a pinwheel.
	local roll = CFrame.Angles(math.rad(cfg.RibbonRoll or 0), 0, 0)

	for _, edge in edges do
		--[[ +X UP THE BEAM, +Y ALONG THE EDGE, which puts the ribbon in the wall's own plane.
			`CFrame.fromMatrix` takes those two columns in that order and derives the third. ]]
		local facing = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, edge.run) * roll

		--- Parented BEFORE their CFrames are written. These are local to the host rather than world,
		--- so the trap the project's notes record (a `WorldCFrame` written on an unparented
		--- attachment being re-read as a local offset) cannot bite, but the order is kept anyway
		--- because it is the one that is always right.
		local footPoint = Instance.new("Attachment")
		footPoint.Name = "Foot"
		footPoint.Parent = host
		footPoint.CFrame = CFrame.new(edge.middle - Vector3.new(0, cfg.Height / 2, 0)) * facing

		local headPoint = Instance.new("Attachment")
		headPoint.Name = "Head"
		headPoint.Parent = host
		headPoint.CFrame = CFrame.new(edge.middle + Vector3.new(0, cfg.Height / 2, 0)) * facing

		local sheet = Instance.new("Beam")
		sheet.Name = SellConfig.Names.Beam
		sheet.Attachment0 = footPoint
		sheet.Attachment1 = headPoint
		sheet.Color = ColorSequence.new(cfg.Color)
		sheet.Transparency = transparency
		sheet.LightEmission = cfg.LightEmission
		--- As wide as the edge is long, read off the pad so a resize takes the wall with it.
		sheet.Width0 = edge.length
		sheet.Width1 = edge.length
		--- Straight: a curve between a floor point and the point directly above it is a bulge.
		sheet.CurveSize0 = 0
		sheet.CurveSize1 = 0
		--- OFF. A 30-stud quad that turns to face you stops standing on the edge it belongs to.
		sheet.FaceCamera = false
		--- The transparency sequence has four keypoints and a beam needs one segment per transition.
		sheet.Segments = 8
		sheet.Parent = host
	end

	return host
end

--[[ What the board says, on both faces. Fixed text, written once, never rewritten — it is an
	invitation rather than an offer, so it says the same thing to everybody.

	IT IS THE KIT'S TWO-LINE PLOT SIGN — 2026-08-26. Before this it was a `#364157` Frame with a
	`UICorner`, a `#0066FF` `UIStroke` and a second blue Frame across the top pretending to be a
	title bar, which is the rounded-rect-and-neon-outline every other game draws and the exact thing
	the plot signage was rebuilt to get away from (`assets/ui/upgrades/README.md`).

	It is now made of the same two textures the GARAGE / COMING SOON board on every garage door is
	made of, laid out to the same fractions, because it is the same sign doing the same job: a title
	on a woven cap and one line of instruction under it. See `BuildComingSoonSigns` — if that layout
	is ever retuned, this is the other place it lives.

	NOTHING HERE IS 9-SLICED. Both textures are exported at the aspect they are drawn at and
	`Sign.Height` is set from the panel's, so every stretch is the identity. `UIAssets.Slice` has the
	long version of why a slice inset is the wrong tool for almost everything in this kit. ]]
local function drawSign(board: BasePart)
	local cfg = SellConfig.Sign
	local lines = SellConfig.Lines

	for _, existing in board:GetChildren() do
		if existing:IsA("SurfaceGui") then
			existing:Destroy()
		end
	end

	--- One of the kit's textures on a label. `Stretch` and no `SliceCenter`, per the header.
	local function image(parent: Instance, name: string, id: number): ImageLabel
		local l = Instance.new("ImageLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.BorderSizePixel = 0
		l.Image = UIAssets.url(id)
		l.ScaleType = Enum.ScaleType.Stretch
		l.Parent = parent
		return l
	end

	--[[ One row of type, with its size CAPPED rather than left to `TextScaled` alone.

		`TextScaled` maximises, so on its own it sizes each row to its own box and the two lines come
		out at whatever their boxes happen to be — which is how a title and a caption end up the same
		size. One ceiling each, both measured against the panel's height, makes the pair a decision.

		The ceiling is also what keeps a long line on ONE line: `TextScaled` reaches for a second row
		only when growing is otherwise impossible, and a ceiling under that threshold stops it. Do
		NOT reach for `TextWrapped = false` instead — it silently clears `TextScaled` and drops the
		label to the default 8px with nothing reporting a problem. ]]
	local function label(parent: Instance, name: string, text: string, colour: Color3, fraction: number, panelH: number): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.BackgroundTransparency = 1
		l.BorderSizePixel = 0
		l.FontFace = FONT
		l.Text = text
		l.TextColor3 = colour
		l.TextScaled = true

		local ceiling = Instance.new("UITextSizeConstraint")
		ceiling.MinTextSize = 8
		ceiling.MaxTextSize = math.max(1, math.round(panelH * fraction))
		ceiling.Parent = l

		l.Parent = parent
		return l
	end

	local function stroke(parent: Instance, thickness: number, transparency: number)
		local st = Instance.new("UIStroke")
		st.Color = cfg.Colors.TextStroke
		st.Thickness = thickness
		st.Transparency = transparency
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		st.Parent = parent
	end

	--[[ THE PANEL IS INSCRIBED IN THE BOARD AT THE TEXTURE'S OWN ASPECT rather than stretched over
		it, which is the one piece of arithmetic in here and the reason this survives an artist.

		`Upgrades.SignPanel` gets its 5px border and 5px inner rim from LAYER STYLES, so they stay 5px
		whatever size the art is drawn at — and come out uneven the moment it is stretched off 2.4221:1.
		`Sign.Height` is set from that ratio, so on a lot this code built the panel fills the board and
		the margins below are zero. On the two lots AUTHORED IN THE PLACE, whose boards are still the
		old 16 x 5, it centres a 12.1 x 5 panel instead and leaves the rest bare — which costs nothing,
		because THE PART IS INVISIBLE (`buildSign`) and the screen is the sign. Either way the border is
		true, and an artist who drags the board to some third shape gets a correct sign rather than a
		smeared one.

		Done as arithmetic and not with a `UIAspectRatioConstraint` on purpose: this runs in EDIT MODE
		out of the Command Runner, where nothing has been laid out yet and `AbsoluteSize` is zero, so a
		constraint would resolve to nothing and the type ceilings below would be measured against it. ]]
	local canvasW = board.Size.X * cfg.PixelsPerStud
	local canvasH = board.Size.Y * cfg.PixelsPerStud
	local aspect = UIAssets.UpgradesSize.SignPanel.X / UIAssets.UpgradesSize.SignPanel.Y
	local panelH = math.min(canvasH, canvasW / aspect)
	local panelW = panelH * aspect
	local panelScale = UDim2.fromScale(panelW / canvasW, panelH / canvasH)

	local gui = Instance.new("SurfaceGui")
	gui.Name = "SellSignGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = cfg.PixelsPerStud
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = board

	local panel = image(gui, "Panel", UIAssets.Upgrades.SignPanel)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = panelScale
	panel.BackgroundColor3 = cfg.Colors.Face
	panel.BackgroundTransparency = 0

	local cap = image(panel, "TitleBar", UIAssets.SpawnCar.TitleBar)
	cap.Position = UDim2.fromScale(cfg.Cap.x, cfg.Cap.y)
	cap.Size = UDim2.fromScale(cfg.Cap.w, cfg.Cap.h)

	local title = label(cap, "Title", lines.SignTitle, cfg.Colors.Title, cfg.Type.Title, panelH)
	title.Position = UDim2.fromScale(0.5, 0.5)
	title.Size = UDim2.fromScale(0.9, 0.62)
	stroke(title, 2, 0.55)

	local caption = label(panel, "Caption", lines.SignCaption, cfg.Colors.Caption, cfg.Type.Caption, panelH)
	caption.Position = UDim2.fromScale(0.5, cfg.Body.y + cfg.Body.h / 2)
	caption.Size = UDim2.fromScale(0.9, cfg.Body.h)

	--[[ A blank panel on the back, so the board is a solid object from behind rather than a picture
		floating in the air. Same trick the podium kiosk uses — and it is the SAME TEXTURE as the
		front now rather than a rounded plate imitating it, so the two faces agree on what the board
		is made of and a player walking round it sees one board. ]]
	local back = Instance.new("SurfaceGui")
	back.Name = "SellSignBack"
	back.Face = Enum.NormalId.Back
	back.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	back.PixelsPerStud = cfg.PixelsPerStud
	back.LightInfluence = 0
	back.Active = false
	back.Parent = board

	local plate = image(back, "BackPlate", UIAssets.Upgrades.SignPanel)
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	plate.Size = panelScale
	plate.BackgroundColor3 = cfg.Colors.Face
	plate.BackgroundTransparency = 0
end

--- Public, so the Command Runner can redraw an authored sign after a copy change without rebuilding
--- the lot around it.
SellLot.drawSign = drawSign

--[[ The board on its pole behind the square. The words only, and there is nothing pressable on it
	or anywhere else on the lot — see `strip`.

	THE PART IS INVISIBLE AND THE SCREEN IS THE SIGN — the same shape as the podium kiosk and the
	forecourt billboard, and for the same reason: a `Part` cannot have rounded corners, this UI kit
	rounds everything, and an opaque board sticks a square silhouette out past the rounded rim.
	`CastShadow` is off for the other half of that (transparency does not stop a part casting, and
	the shadow is the square outline coming back on the floor).

	`CanQuery` MUST STAY TRUE here, unlike everything else in this file: a `SurfaceGui` takes a click
	only where the mouse ray hits the part under it, and turning it off makes a sign unpressable in a
	way that looks exactly like an unbound controller. It is on so this board can ever grow a button —
	it has never had one, and the square's own button was deleted rather than moved here.

	IT STANDS BEHIND THE CURTAIN, not in it. `Sign.Standoff` studs past the back edge, so the pole
	never runs up through the light — a pole inside a translucent white sheet reads as a smear rather
	than as a post, and the sheet is the thing the rebuild exists to get right.

	IT FACES THE WAY IN. `CFrame.Angles(0, pi, 0)` turns the frame's inward look back out along the
	entrance bearing, which is the direction everybody arrives from. Behind it is whatever the lot
	backs on to. The tilt is negative so the face leans DOWN toward a reader standing under it. ]]
local function buildSign(model: Model, frame: CFrame): BasePart
	local cfg = SellConfig.Sign
	local pad = SellConfig.Pad
	local backZ = -(pad.Depth / 2 + cfg.Standoff)

	--- It stops at the board's BOTTOM EDGE and does not run up behind it. The board is tilted, so a
	--- pole carried up to its centre comes out through the front of the sign.
	local post = slab(
		SellConfig.Names.SignPost,
		Vector3.new(cfg.PostWidth, cfg.Rise, cfg.PostWidth),
		frame * CFrame.new(0, cfg.Rise / 2, backZ),
		cfg.PostColor,
		cfg.PostMaterial
	)
	post.Parent = model

	local board = Instance.new("Part")
	board.Name = SellConfig.Names.Sign
	board.Anchored = true
	board.CanCollide = false
	board.CanTouch = false
	board.CanQuery = true
	board.CastShadow = false
	board.Transparency = 1
	board.Size = Vector3.new(cfg.Width, cfg.Height, cfg.Thickness)
	board.CFrame = frame
		* CFrame.new(0, cfg.Rise + cfg.Height / 2, backZ)
		* CFrame.Angles(0, math.pi, 0)
		* CFrame.Angles(math.rad(-cfg.Tilt), 0, 0)
	board.Parent = model

	drawSign(board)
	return board
end

--[[ The Attachment the client's price sign adorns to, created on the pad if it is not already there.

	AN ATTACHMENT RATHER THAN A TYPED OFFSET, so retuning `Bubble.Height` is a number in a config and
	not a second place that has to agree with this one — and so an artist who drags the pad takes the
	sign's anchor with it for free.

	IT DOES NOT MOVE AN EXISTING ONE. On an authored lot the attachment is part of the artist's
	layout: if they have nudged the sign to clear something, a re-run must not undo that. Delete it
	and re-run to get the config's height back. ]]
function SellLot.anchorOn(pad: BasePart): Attachment
	local existing = pad:FindFirstChild(SellConfig.Names.BubbleAnchor)
	if existing and existing:IsA("Attachment") then
		return existing
	end

	local anchor = Instance.new("Attachment")
	anchor.Name = SellConfig.Names.BubbleAnchor
	anchor.Parent = pad
	anchor.Position = Vector3.new(0, SellConfig.Bubble.Height, 0)
	return anchor
end
--[[ Take the old held button off a lot that still has one. 2026-08-31.

	THIS IS A MIGRATION AND IT IS EXPECTED TO DO NOTHING. The button was a `ProximityPrompt` named
	`SellPrompt` hanging on an Attachment named `SellButton` on the pad's back edge, and both were
	AUTHORED INTO THE PLACE by whoever last ran `BuildSellLot`. The gesture is getting out of the car
	now (`SellConfig`'s header) and nothing in code listens to that prompt any more — so a lot saved
	before today would carry a live, stock-styled, perfectly pressable button that does nothing at
	all, which is a worse state than either having it or not.

	IT RUNS ON EVERY LOT, EVERY BOOT, and that is deliberate rather than lazy: the place is the thing
	that remembers, so this cannot be "run once and tick it off" until somebody re-authors and saves.
	It is two `FindFirstChild`s on a part when there is nothing to find.

	THE ATTACHMENT GOES TOO, not just the prompt. An empty `SellButton` left on the pad is a name in
	the place that the contract no longer mentions, and the next person to open the lot in Studio
	would reasonably wonder what hangs from it.

	RETURNS whether it removed anything, so the caller can say so once rather than silently. ]]
function SellLot.strip(lot: Model): boolean
	local removed = false
	--- Searched from the LOT rather than the pad: an artist may have moved either one, and the point
	--- is that neither survives anywhere under this model.
	for _, name in { "SellPrompt", "SellButton" } do
		local found = lot:FindFirstChild(name, true)
		while found do
			found:Destroy()
			removed = true
			found = lot:FindFirstChild(name, true)
		end
	end
	return removed
end

--[[ Build the whole lot at `frame`, tagged and ready to parent.

	RETURNED UNPARENTED, which is what lets the caller decide: the Command Runner drops it into
	Workspace inside a change recording, and the service's fallback parents it into a folder it owns.

	THERE IS NOTHING PRESSABLE IN IT. There was until 2026-08-31 — see `strip`, which takes the old
	button back off a lot authored before then. What a player does at this square now happens on the
	client, in a panel, and the square's whole job is to be a marked place with a volume. ]]
function SellLot.build(frame: CFrame): Model
	local model = Instance.new("Model")
	model.Name = SellConfig.Names.Lot
	--- The whole lot arrives on a client as one piece, so a tag handler can walk its children on the
	--- frame the tag fires.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local pad = buildFloor(model, frame)
	buildFence(model, frame)
	buildSign(model, frame)
	SellLot.anchorOn(pad)

	model.PrimaryPart = pad
	model:AddTag(SellConfig.Tag)
	return model
end

--- Every lot standing in the place right now, authored or not. One is the expected answer; the tag
--- does not promise it.
function SellLot.existing(): { Model }
	local found = {}
	for _, tagged in CollectionService:GetTagged(SellConfig.Tag) do
		if tagged:IsA("Model") and tagged:IsDescendantOf(workspace) then
			table.insert(found, tagged)
		end
	end
	-- Authored SellLot/SellLot1 may predate the tag. Adopt it rather than building another lot.
	local folder = workspace:FindFirstChild(SellConfig.FolderName)
	if folder then
		for _, lot in folder:GetChildren() do
			if lot:IsA("Model") and lot:FindFirstChild(SellConfig.Names.Pad, true) and not table.find(found, lot) then
				lot:AddTag(SellConfig.Tag)
				table.insert(found, lot)
			end
		end
	end
	return found
end

return SellLot
