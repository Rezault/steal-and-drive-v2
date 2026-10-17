--[[
	FirstPersonCabinDetail  (client)
	--------------------------------
	What goes on the black cabin: the mirrors the skin cut out (the car's own door mirrors, in its own
	paint, and a rear-view mirror of ours), gauges behind the wheel, a radio screen on the dash top,
	vents and the hazard switch. Where each piece goes in each car is `CabinSkinConfig.Detail` and
	`.Mirrors`, the look is `CockpitConfig.Cabin.Detail`, and the switch is
	`CameraConfig.FirstPerson.CabinDetail`.

	`Modules/FirstPersonCabin` owns it and moves it. Every piece here is one more of the cabin's
	pieces (a part, its full size and where it goes in the seat's frame), placed by the cabin's own
	loop in the same render step as the skin and scaled about the eye with it, so the detail can
	never sit a frame or a hair away from the dash it is on. This file builds the pieces and keeps
	the two lit faces live.

	=== THE LIT FACES ============================================================================

	The gauges and the screen are SurfaceGuis drawn unlit (`LightInfluence` 0), so at night they
	glow the way a real dash does. What they show is real: the speed needle and digits are the HUD
	speedo's own mph (`DrivingHudController.getMph`) on a numbered dial, the rev needle and gear are
	`Modules/AutomaticGearbox`, the same box the engine note and the HUD's gear read, and the screen
	is the soundtrack's own track (`MusicController.nowPlaying`), with bars that move to its
	loudness and the player's own time in the corner.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AutomaticGearbox = require(ReplicatedStorage.shared.Modules.AutomaticGearbox)
local CabinSkinConfig = require(ReplicatedStorage.shared.Configs.CabinSkinConfig)
local CockpitConfig = require(ReplicatedStorage.shared.Configs.CockpitConfig)
local DriveConfig = require(ReplicatedStorage.shared.Configs.DriveConfig)
local Shard = require(ReplicatedStorage.Packages.Shard)

local FirstPersonCabinDetail = {}
FirstPersonCabinDetail.__index = FirstPersonCabinDetail

export type Piece = { part: BasePart, size: Vector3, rel: CFrame }
--- (the loaded template or nil while it loads, and whether it failed to load)
export type Fetch = (id: number) -> (MeshPart?, boolean)
type Style = { Color: Color3, Material: Enum.Material?, Reflectance: number? }

-- Canvas pixels. The faces are drawn at a fixed canvas whatever their size in studs.
local GAUGE_CANVAS = Vector2.new(500, 180)
local SCREEN_CANVAS = Vector2.new(560, 190)
--- Seconds between asking the soundtrack what is on. A track changes every few minutes.
local POLL_SECONDS = 0.25

--- The pieces each part of `CabinSkinConfig.Detail` is made of, by mesh name.
local MESHES_FOR = {
	Cluster = { "ClusterHood", "ClusterRings" },
	Screen = { "ScreenBezel" },
	Row = { "VentBezel", "VentCore", "HazardButton", "HazardMark" },
	Vent = { "VentBezel", "VentCore" },
	Mirror = { "RearMirrorHousing", "RearMirrorGlass" },
}

local function approach(current: number, target: number, gain: number, dt: number): number
	return target + (current - target) * math.exp(-gain * dt)
end

local function style(part: BasePart, look: Style)
	part.Color = look.Color
	part.Material = look.Material or Enum.Material.SmoothPlastic
	part.Reflectance = look.Reflectance or 0
end

local function bare(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.LocalTransparencyModifier = 1
end

--- A cylinder from `a` to `b`. A cylinder's axis is its X, so the look-at frame is turned onto it.
local function rodFrame(a: Vector3, b: Vector3): CFrame
	local dir = b - a
	local up = if math.abs(dir.Unit.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	return CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.pi / 2, 0)
end

local function frame(parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in props do
		(f :: any)[k] = v
	end
	f.Parent = parent
	return f
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.FontFace = CockpitConfig.Cabin.Detail.Font
	t.TextColor3 = CockpitConfig.Cabin.Detail.Ink
	for k, v in props do
		(t :: any)[k] = v
	end
	t.Parent = parent
	return t
end

local function round(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function surface(part: BasePart, canvas: Vector2): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = canvas
	gui.LightInfluence = 0
	gui.ClipsDescendants = true
	gui.Enabled = false
	gui.Parent = part
	return gui
end

--- `path` is dotted from the car ("Body.shell_04_body"); failing that, the last name anywhere in it.
local function find(car: Model, path: string): Instance?
	local at: Instance? = car
	for name in string.gmatch(path, "[^%.]+") do
		at = at and at:FindFirstChild(name)
	end
	return at or car:FindFirstChild(string.match(path, "[^%.]+$") or path, true)
end

--[[ Public: the detail for `car`, or nil while any of its meshes is still loading (ask again next
	frame; `fetch` starts the loads). A mesh that failed to load loses its own pieces and nothing
	else. Builds every part hidden; `FirstPersonCabin` shows and places them. `mirrors` is the car's
	own door mirrors (`CabinSkinConfig.Mirrors`), drawn in the look of the live parts they are from. ]]
function FirstPersonCabinDetail.new(
	detail: CabinSkinConfig.Detail,
	mirrors: { CabinSkinConfig.CarMirror }?,
	car: Model,
	fetch: Fetch,
	parent: Instance
)
	local loading = false
	local function need(id: number)
		local from, failed = fetch(id)
		if not from and not failed then
			loading = true
		end
	end
	for key, names in MESHES_FOR do
		if (detail :: any)[key] then
			for _, name in names do
				need(CabinSkinConfig.DetailMeshes[name].Mesh)
			end
		end
	end
	for _, mirror in mirrors or {} do
		need(mirror.Mesh)
	end
	if loading then
		return nil
	end

	local self = setmetatable({}, FirstPersonCabinDetail)
	self._fetch = fetch
	self._parent = parent
	self.pieces = {} :: { Piece }
	self._guis = {} :: { SurfaceGui }
	self._visible = false
	self._faded = false

	-- The live faces' state.
	self._speedNeedle = nil :: Frame?
	self._revNeedle = nil :: Frame?
	self._speedText = nil :: TextLabel?
	self._gearText = nil :: TextLabel?
	self._rev = 0
	self._gear = 1
	self._shownMph = -1
	self._shownGear = -1
	self._track = nil :: TextLabel?
	self._clock = nil :: TextLabel?
	self._progress = nil :: Frame?
	self._barMax = 0
	self._bars = {} :: { Frame }
	self._levels = {} :: { number }
	self._sound = nil :: Sound?
	self._poll = 0
	self._clockShown = ""
	self._t = 0

	local look = CockpitConfig.Cabin.Detail
	if detail.Cluster then
		self._group = "Cluster"
		self:_cluster(detail.Cluster, look)
	end
	if detail.Screen then
		self._group = "Screen"
		self:_screen(detail.Screen, look)
	end
	if detail.Row then
		self._group = "Row"
		local at = detail.Row.At
		self:_vent(at * CFrame.new(-0.42, 0, 0), 0.3, look)
		self:_vent(at * CFrame.new(0.42, 0, 0), 0.3, look)
		self:_mesh("HazardButton", at * CFrame.new(0, 0, 0.02), 1, { Color = look.Hazard.Color })
		self:_mesh("HazardMark", at * CFrame.new(0, 0, 0.02), 1, { Color = look.Hazard.Mark })
	end
	if detail.Vent then
		self._group = "Vent"
		self:_vent(detail.Vent.At, 0.42, look)
	end
	if detail.Mirror then
		self._group = "Mirror"
		self:_rearMirror(detail.Mirror, look)
	end
	self._group = "CarMirror"
	for _, mirror in mirrors or {} do
		self:_carMirror(mirror, car)
	end
	return self
end

-- === Building ================================================================

function FirstPersonCabinDetail._add(self, part: BasePart, size: Vector3, rel: CFrame)
	bare(part)
	part.Size = size
	part.Parent = self._parent
	--- `group` is which piece this is part of, for `CockpitConfig.Cabin.Nudge`.
	table.insert(self.pieces, { part = part, size = size, rel = rel, group = self._group })
end

--- One of the Blender pieces at `at`, `k` times its modelled size.
function FirstPersonCabinDetail._mesh(self, name: string, at: CFrame, k: number, look: Style): BasePart?
	local mesh = CabinSkinConfig.DetailMeshes[name]
	local from = self._fetch(mesh.Mesh)
	if not from then
		return nil
	end
	local part = from:Clone()
	part.Name = "CabinDetail_" .. name
	style(part, look)
	self:_add(part, mesh.Size * k, at * CFrame.new(mesh.Centre * k))
	return part
end

function FirstPersonCabinDetail._block(self, name: string, shape: Enum.PartType, size: Vector3, rel: CFrame, look: Style): Part
	local part = Instance.new("Part")
	part.Name = "CabinDetail_" .. name
	part.Shape = shape
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	style(part, look)
	self:_add(part, size, rel)
	return part
end

function FirstPersonCabinDetail._rod(self, name: string, a: Vector3, b: Vector3, thickness: number, look: Style)
	local length = (b - a).Magnitude
	if length < 0.02 then
		return
	end
	self:_block(name, Enum.PartType.Cylinder, Vector3.new(length, thickness, thickness), rodFrame(a, b), look)
	-- A foot where it meets the car, so the join reads as a fixing and not a line stopping.
	self:_block(name .. "Foot", Enum.PartType.Ball, Vector3.one * thickness * 1.6, CFrame.new(b), look)
end

function FirstPersonCabinDetail._vent(self, at: CFrame, k: number, look)
	self:_mesh("VentBezel", at, k, look.Trim)
	self:_mesh("VentCore", at, k, look.VentCore)
end

function FirstPersonCabinDetail._rearMirror(self, piece: CabinSkinConfig.Piece, look)
	local k = piece.Scale or 1
	self:_mesh("RearMirrorHousing", piece.At, k, look.Housing)
	self:_mesh("RearMirrorGlass", piece.At, k, look.Glass)
	if piece.Mount then
		local knuckle = piece.At * Vector3.new(0, 0.13 * k, -0.04 * k)
		self:_rod("MirrorStalk", knuckle, piece.Mount, 0.07, look.Stalk)
	end
end

--[[ One chunk of the car's own door mirror, in the look of the live part it was cut from: its
	texture (the paint), colour and material, and any SurfaceAppearance. A part that is not there
	(a rig that changed) leaves the chunk in the cabin's black. ]]
function FirstPersonCabinDetail._carMirror(self, mirror: CabinSkinConfig.CarMirror, car: Model)
	local from = self._fetch(mirror.Mesh)
	if not from then
		return
	end
	local part = from:Clone()
	part.Name = "CabinDetail_CarMirror"
	local source = find(car, mirror.Part)
	if source and source:IsA("MeshPart") then
		part.TextureID = source.TextureID
		part.Color = source.Color
		part.Material = source.Material
		part.MaterialVariant = source.MaterialVariant
		part.Reflectance = source.Reflectance
		for _, child in source:GetChildren() do
			if child:IsA("SurfaceAppearance") then
				child:Clone().Parent = part
			end
		end
	else
		style(part, { Color = CockpitConfig.Cabin.Color, Material = CockpitConfig.Cabin.Material })
	end
	self:_add(part, from.Size, CFrame.new(mirror.Centre))
end

--[[ The binnacle: the hood, the dial rings, and behind them the face the dials are drawn on. The
	face sits on the hood's recess floor, 0.03 of its width back from the frame. ]]
function FirstPersonCabinDetail._cluster(self, piece: CabinSkinConfig.Piece, look)
	local k = piece.Scale or 1
	self:_mesh("ClusterHood", piece.At, k, look.Housing)
	self:_mesh("ClusterRings", piece.At, k, look.Trim)
	local face = self:_block(
		"ClusterFace",
		Enum.PartType.Block,
		Vector3.new(1.0 * k, 0.36 * k, 0.01),
		piece.At * CFrame.new(0, 0, -0.03 * k + 0.005),
		{ Color = look.Face }
	)
	local gui = surface(face, GAUGE_CANVAS)
	table.insert(self._guis, gui)
	local g = look.Gauges
	local root = frame(gui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = look.Face })

	-- The dial centres and radius match the rings: 0.28 of the face's width out from the middle,
	-- 0.168 of it to the ring's inner edge.
	local radius = 0.168 * GAUGE_CANVAS.X
	-- `number` is what major `i` (0 to `Ticks`) reads.
	local function dial(cx: number, red: boolean, number: (i: number) -> string): Frame
		local disc = frame(root, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx, GAUGE_CANVAS.Y / 2),
			Size = UDim2.fromOffset(radius * 2, radius * 2),
			BackgroundColor3 = look.Face:Lerp(Color3.new(1, 1, 1), 0.035),
		})
		round(disc, UDim.new(0.5, 0))
		local marks = g.Ticks * 2
		for i = 0, marks do
			local major = i % 2 == 0
			local spoke = frame(disc, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Rotation = -g.SweepDeg / 2 + g.SweepDeg * i / marks,
			})
			local isRed = red and i >= marks - g.RedTicks * 2
			frame(spoke, {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(radius, if major then 7 else 9),
				Size = UDim2.fromOffset(if major then 4 else 2, if major then 15 else 8),
				BackgroundColor3 = if isRed then look.Redline elseif major then look.Ink else look.Dim,
			})
		end
		-- The numbers stand upright inside the majors, so they are placed rather than spun.
		local inner = radius - g.NumberInset
		for i = 0, g.Ticks do
			local angle = math.rad(-g.SweepDeg / 2 + g.SweepDeg * i / g.Ticks)
			label(disc, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, math.sin(angle) * inner, 0.5, -math.cos(angle) * inner),
				Size = UDim2.fromOffset(40, g.NumberSize),
				TextSize = g.NumberSize,
				TextColor3 = if red and i >= g.Ticks - g.RedTicks then look.Redline else look.Ink,
				Text = number(i),
			})
		end
		local needle = frame(disc, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Rotation = -g.SweepDeg / 2,
			ZIndex = 3,
		})
		frame(needle, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(4, radius - 12),
			BackgroundColor3 = look.Needle,
			ZIndex = 3,
		})
		local cap = frame(disc, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(18, 18),
			BackgroundColor3 = Color3.fromRGB(40, 40, 44),
			ZIndex = 4,
		})
		round(cap, UDim.new(0.5, 0))
		return needle
	end

	local half = GAUGE_CANVAS.X / 2
	local offset = 0.28 * GAUGE_CANVAS.X
	self._speedNeedle = dial(half - offset, false, function(i)
		return tostring(math.floor(g.SpeedTop * i / g.Ticks + 0.5))
	end)
	self._revNeedle = dial(half + offset, true, tostring)
	--[[ THE SPEED IS THE BIG NUMBER, between the dials, with its unit under it. The gear used to
		be, and a big "6" between two dials reads as the speed (it was reported as "6mph at full
		speed"), so the gear is now a small labelled line under the speed. The tacho's lower half
		keeps its word. ]]
	self._speedText = label(root, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(half, GAUGE_CANVAS.Y / 2 - 14),
		Size = UDim2.fromOffset(110, 56),
		TextSize = 56,
		Text = "0",
	})
	label(root, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(half, GAUGE_CANVAS.Y / 2 + 22),
		Size = UDim2.fromOffset(80, 16),
		TextSize = 16,
		TextColor3 = look.Dim,
		Text = "MPH",
	})
	label(root, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(half + offset, GAUGE_CANVAS.Y / 2 + 44),
		Size = UDim2.fromOffset(60, 16),
		TextSize = 16,
		TextColor3 = look.Dim,
		Text = "RPM",
		ZIndex = 2,
	})
	self._gearText = label(root, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(half, GAUGE_CANVAS.Y / 2 + 52),
		Size = UDim2.fromOffset(100, 18),
		TextSize = 17,
		TextColor3 = look.Dim,
		Text = "GEAR 1",
	})
end

--[[ The radio: a bezel standing on the dash, and the screen in it. The screen sits on the bezel's
	well floor, which is the frame itself.

	DRAWN TO BE READ FROM THE SEAT, which at this lens is about a tenth of the screen's width for
	the smallest text worth drawing: the track and the clock, big, and nothing that would only be
	noise at that size. ]]
function FirstPersonCabinDetail._screen(self, piece: CabinSkinConfig.Piece, look)
	local k = piece.Scale or 1
	self:_mesh("ScreenBezel", piece.At, k, look.Housing)
	local face = self:_block(
		"ScreenFace",
		Enum.PartType.Block,
		Vector3.new(1.12 * k, 0.38 * k, 0.008),
		piece.At * CFrame.new(0, 0, 0.004),
		{ Color = look.Face }
	)
	local gui = surface(face, SCREEN_CANVAS)
	table.insert(self._guis, gui)
	local s = look.Screen
	local root = frame(gui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = look.Face })
	local inset = 24

	label(root, {
		Position = UDim2.fromOffset(inset, 10),
		Size = UDim2.fromOffset(240, 36),
		TextSize = 30,
		TextColor3 = look.Accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "FM 101.7",
	})
	self._clock = label(root, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(SCREEN_CANVAS.X - inset, 10),
		Size = UDim2.fromOffset(140, 36),
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
	})

	-- The "cover": a tile in the accent with the bars standing in it.
	local tile = 110
	local art = frame(root, {
		Position = UDim2.fromOffset(inset, 62),
		Size = UDim2.fromOffset(tile, tile),
		BackgroundColor3 = look.Accent,
		BackgroundTransparency = 0.7,
	})
	round(art, UDim.new(0, 14))
	local barWidth, gap = 7, 4
	local span = s.Bars * barWidth + (s.Bars - 1) * gap
	for i = 1, s.Bars do
		local bar = frame(art, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromOffset((tile - span) / 2 + (i - 1) * (barWidth + gap), tile - 14),
			Size = UDim2.fromOffset(barWidth, 4),
			BackgroundColor3 = look.Ink,
		})
		round(bar, UDim.new(0, 3))
		self._bars[i] = bar
		self._levels[i] = 0
	end
	self._barMax = tile - 30

	local left = inset + tile + 18
	self._track = label(root, {
		Position = UDim2.fromOffset(left, 66),
		Size = UDim2.fromOffset(SCREEN_CANVAS.X - left - inset, 56),
		TextSize = 46,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = s.Silent,
	})
	local rail = frame(root, {
		Position = UDim2.fromOffset(left, 142),
		Size = UDim2.fromOffset(SCREEN_CANVAS.X - left - inset, 6),
		BackgroundColor3 = look.Dim,
		BackgroundTransparency = 0.6,
	})
	round(rail, UDim.new(0, 3))
	self._progress = frame(rail, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = look.Accent })
	round(self._progress :: Frame, UDim.new(0, 3))
end

-- === Live ===================================================================

--- Public: whether the lit faces draw. A part's `LocalTransparencyModifier` hides the part and not a
--- SurfaceGui on it, so the cabin's show and hide come through here as well.
function FirstPersonCabinDetail.setVisible(self, visible: boolean)
	if visible == self._visible then
		return
	end
	self._visible = visible
	self:_applyGuis()
end

--- Public: the race's fades (the body's `Transparency`); the faces go with the parts past half.
function FirstPersonCabinDetail.setFaded(self, faded: boolean)
	if faded == self._faded then
		return
	end
	self._faded = faded
	self:_applyGuis()
end

function FirstPersonCabinDetail._applyGuis(self)
	for _, gui in self._guis do
		gui.Enabled = self._visible and not self._faded
	end
end

--[[ Public, once a frame while it shows.

	The speed needle is set straight from the HUD's mph, with no lag of its own: that number is
	already smoothed (it is what the HUD's digits show), and a second filter would leave the needle
	behind the digits under it. ]]
function FirstPersonCabinDetail.tick(self, dt: number)
	local look = CockpitConfig.Cabin.Detail
	local g = look.Gauges
	self._t += dt

	if self._speedNeedle then
		local hud = Shard.get("DrivingHudController")
		local mph = if hud then hud:getMph() else 0
		local box = DriveConfig.Gearbox
		local gear, through = AutomaticGearbox.sample(mph, self._gear, box.TopMph, box.Gears, box.DownshiftHysteresis)
		self._gear = gear
		local rev = if mph < 1 then g.Idle * 0.85 else g.Idle + (g.Shift - g.Idle) * through
		self._rev = approach(self._rev, rev, g.NeedleGain, dt)
		local from = -g.SweepDeg / 2
		self._speedNeedle.Rotation = from + g.SweepDeg * math.clamp(mph / g.SpeedTop, 0, 1);
		(self._revNeedle :: Frame).Rotation = from + g.SweepDeg * self._rev

		local shown = math.floor(mph + 0.5)
		if shown ~= self._shownMph then
			self._shownMph = shown;
			(self._speedText :: TextLabel).Text = tostring(shown)
		end
		if gear ~= self._shownGear then
			self._shownGear = gear;
			(self._gearText :: TextLabel).Text = "GEAR " .. gear
		end
	end

	if self._track then
		self:_tickScreen(dt, look)
	end
end

function FirstPersonCabinDetail._tickScreen(self, dt: number, look)
	local s = look.Screen
	self._poll -= dt
	if self._poll <= 0 then
		self._poll = POLL_SECONDS
		local music = Shard.get("MusicController")
		local track, sound = nil, nil
		if music then
			track, sound = music:nowPlaying()
		end
		self._sound = if track then sound else nil
		local name = if track then track.Name or "Untitled" else s.Silent
		local trackLabel = self._track :: TextLabel
		if trackLabel.Text ~= name then
			trackLabel.Text = name
		end
		-- The player's own time, like a real car's clock. The world's `ClockTime` is not a time of
		-- day here (the day and night are drawn, not clocked) and reads 12:00 at midnight.
		local now = os.date("*t")
		local text = string.format("%02d:%02d", now.hour, now.min)
		if text ~= self._clockShown then
			self._clockShown = text;
			(self._clock :: TextLabel).Text = text
		end
		local playing = self._sound
		local length = if playing and playing.TimeLength > 0 then playing.TimeLength else 0;
		(self._progress :: Frame).Size = UDim2.fromScale(
			if playing and length > 0 then math.clamp(playing.TimePosition / length, 0, 1) else 0,
			1
		)
	end

	-- The bars: the music's loudness, each bar on its own slow wobble so they do not move as one.
	local sound = self._sound
	local loud = if sound then math.clamp(sound.PlaybackLoudness / s.FullLoudness, 0, 1) else 0
	for i, bar in self._bars do
		local wobble = 0.55 + 0.45 * math.noise(i * 1.7, self._t * 3.1)
		local target = loud * math.clamp(wobble, 0.1, 1)
		local level = approach(self._levels[i], target, s.BarGain, dt)
		self._levels[i] = level
		bar.Size = UDim2.fromOffset(bar.Size.X.Offset, 4 + math.floor(level * self._barMax))
	end
end

--- Public: drop every piece.
function FirstPersonCabinDetail.destroy(self)
	for _, piece in self.pieces do
		piece.part:Destroy()
	end
	table.clear(self.pieces)
	table.clear(self._guis)
end

return FirstPersonCabinDetail
