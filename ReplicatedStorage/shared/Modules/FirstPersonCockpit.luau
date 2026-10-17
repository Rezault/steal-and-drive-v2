--[[
	FirstPersonCockpit  (client)
	----------------------------
	The dash, the wheel and the driver's own arms, drawn over the world in a full-screen ViewportFrame
	while `RaceCameraController` has the first-person shot. `CockpitConfig` is the art and the reasons
	for the viewport; this file builds it and moves it.

	=== HOW IT STAYS GLUED TO THE CAR ===========================================================

	Everything in here is built ONCE in EYE SPACE: origin at the driver's eye, +X right, +Y up, -Z
	ahead, with the rotation of the car's seat. Nothing in the model moves after that except the
	wheel, the needle, the HP bar and the arms. What moves every frame is the VIEWPORT'S CAMERA, which
	is set to where the real camera is relative to the real eye frame
	(`eyeFrame:ToObjectSpace(camera.CFrame)`). So when the view lags the car's yaw a degree, or a hit
	nods the lens, or nitro shakes it, the cockpit slides in frame by exactly as much as the real
	pillars do, because both are being looked at by the same camera from the same place. One CFrame
	write a frame instead of two hundred.

	=== THE ARMS ARE THE PLAYER'S =============================================================

	The six R15 arm parts are cloned off the live character (the live ones are hidden, the camera is
	inside the head). A two-bone solve per arm puts the shoulder where a seated shoulder is, the hand
	on the rim where that hand holds it, and bends the elbow down and out; the rim turns with the
	steering and the hands go round with it. An R6 character gets one-bone arms, and a character with
	no usable arms gets plain ones in a skin colour. The joints are solved by hand because a viewport
	solves nothing: no physics, no Motor6D, no constraint rig (and this place has no Motor6Ds anyway;
	see `RaceUIController`'s end shot for the same lesson).

	Their clothes come with them: the arms sit in a model with a Humanoid and a copy of the character's
	Shirt, which is all the engine needs to wrap a classic shirt's sleeves round them, in a viewport as
	in the world. Short sleeves and bare arms stay bare. The hands can wear `Arms.Gloves`, which is
	what tells a hand from the forearm it is on when both are one skin colour; they are off, so the
	hands are the character's own.

	=== THE HANDS CAN HOLD THE CAR'S OWN WHEEL ================================================

	With the dash off (`view.dash = false`) and a `view.hold`, only the arms are drawn, and the hands
	hold the car's real steering wheel in the world instead of the drawn one: same solve, same grips,
	on the real rim, turned by `Modules/FirstPersonWheel`. A viewport draws over the world, so the arms
	are always in front of that wheel, which is where arms on a wheel are. The arms are refitted (the
	stretch below) whenever the wheel they hold moves, so a car with a bigger wheel is still reached.

	=== WHAT IT READS =========================================================================

	`update(view)` once a frame from the camera controller, with the camera and eye frames, the road
	steer (+ = left), the car's speed as a share of its ceiling, the lens, a fade, the car (for the
	HP bar off the HitBox attributes) and what to draw. It never reaches for the camera itself and it
	never decides whether it should be showing; the controller owns both.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CockpitConfig = require(ReplicatedStorage.shared.Configs.CockpitConfig)
local ObstacleConfig = require(ReplicatedStorage.shared.Configs.ObstacleConfig)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local CarStats = require(ReplicatedStorage.shared.Modules.CarStats)

local FirstPersonCockpit = {}
FirstPersonCockpit.__index = FirstPersonCockpit

--- A wheel for the hands to hold that this file did not draw: the car's own (`Modules/FirstPersonWheel`).
--- `frame` is the wheel at rest in EYE space, hub at the origin, rim in its XY plane, +X the driver's
--- right and +Z toward the driver, which is the same frame `wheelBase` gives the drawn wheel.
export type Hold = {
	frame: CFrame,
	radius: number,
	--- Radians turned, + = anticlockwise as the driver sees it. Already smoothed by its owner.
	angle: number,
}

export type View = {
	camera: CFrame,
	frame: CFrame,
	steer: number,
	speed: number,
	fov: number,
	alpha: number,
	dt: number,
	car: Model?,
	--- Draw the rarity dash and wheel. False with a `hold` is the car's own cabin with only the
	--- arms drawn over it.
	dash: boolean?,
	--- Draw the arms.
	arms: boolean?,
	--- The wheel the hands hold when it is not the drawn one.
	hold: Hold?,
}

local WHITE = Color3.new(1, 1, 1)

-- === Small helpers ===========================================================

local function approach(current: number, target: number, dt: number, gain: number): number
	if gain <= 0 then
		return target
	end
	return current + (target - current) * (1 - math.exp(-dt * gain))
end

--- An anchored, decorative part. Everything in the cockpit is one of these.
local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function cylinder(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local p = part(parent, name, size, cframe, color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

--- A rotation-only CFrame whose Y axis is `y` and whose X axis is `ref` made perpendicular to it.
--- The one building block of every "point this part from here to there" below.
local function basis(y: Vector3, ref: Vector3): CFrame
	y = y.Unit
	local x = ref - y * ref:Dot(y)
	if x.Magnitude < 1e-3 then
		x = Vector3.xAxis - y * y.X
		if x.Magnitude < 1e-3 then
			x = Vector3.zAxis - y * y.Z
		end
	end
	x = x.Unit
	local z = x:Cross(y)
	return CFrame.fromMatrix(Vector3.zero, x, y, z)
end

--[[ Place a part so that its local point `fromLocal` lands on `fromWorld` and its local point
	`toLocal` points at `toWorld`, with the roll chosen so the part's local `refLocal` direction leans
	toward the world direction `refWorld`. This is how a limb part is posed off two joint positions. ]]
local function pose(
	fromLocal: Vector3,
	toLocal: Vector3,
	fromWorld: Vector3,
	toWorld: Vector3,
	refLocal: Vector3,
	refWorld: Vector3
): CFrame
	local boneLocal = toLocal - fromLocal
	local boneWorld = toWorld - fromWorld
	if boneLocal.Magnitude < 1e-4 or boneWorld.Magnitude < 1e-4 then
		return CFrame.new(fromWorld)
	end
	local rotation = basis(boneWorld, refWorld) * basis(boneLocal, refLocal):Inverse()
	return rotation + (fromWorld - rotation:VectorToWorldSpace(fromLocal))
end

--- Two-bone IK: where the elbow goes for a shoulder at `s`, a hand at `t`, bone lengths `l1`/`l2`
--- and an elbow that bends toward `pole`. Clamped to the arm's reach rather than stretched.
local function solveElbow(s: Vector3, t: Vector3, l1: number, l2: number, pole: Vector3): Vector3
	local d = t - s
	local dist = d.Magnitude
	if dist < 1e-4 then
		return s + pole.Unit * l1
	end
	local dir = d / dist
	local reach = math.clamp(dist, math.abs(l1 - l2) + 1e-3, l1 + l2 - 1e-3)
	local a = (l1 * l1 - l2 * l2 + reach * reach) / (2 * reach)
	local h = math.sqrt(math.max(l1 * l1 - a * a, 0))
	local side = pole - dir * pole:Dot(dir)
	if side.Magnitude < 1e-3 then
		side = Vector3.new(0, -1, 0) - dir * -dir.Y
		if side.Magnitude < 1e-3 then
			side = Vector3.xAxis
		end
	end
	return s + dir * a + side.Unit * h
end

--[[ Where a named rig attachment sits along the part's own long axis, or the fallback. ON THE AXIS,
	deliberately: the R15 shoulder rig attachment is at the upper arm's inner top corner (x = 0.5),
	and a bone drawn corner-to-elbow is diagonal across the part, which posed the whole arm 35 degrees
	off its own length and swung it up into the lens on the first try. Each limb's length is its Y
	axis; the attachments only say where along it the joints are. ]]
local function attachmentAt(source: BasePart?, name: string, fallback: Vector3): Vector3
	local attachment = source and source:FindFirstChild(name)
	if attachment and attachment:IsA("Attachment") then
		return Vector3.new(0, attachment.Position.Y, 0)
	end
	return fallback
end

--- The wheel's own frame in eye space: hub at the origin, rim in the XY plane, +Z toward the driver,
--- leaned back by `TiltDeg`. Used by the build and by the arm fit, so they cannot disagree.
local function wheelBase(): CFrame
	local Wh = CockpitConfig.Wheel
	return CFrame.new(Wh.Offset) * CFrame.Angles(-math.rad(Wh.TiltDeg), 0, 0)
end

-- === Construction ============================================================

function FirstPersonCockpit.new()
	local self = setmetatable({}, FirstPersonCockpit)

	local gui = Instance.new("ScreenGui")
	gui.Name = "FirstPersonCockpit"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = CockpitConfig.DisplayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Viewport"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.Active = false
	viewport.Ambient = CockpitConfig.Light.MinAmbient
	viewport.LightColor = CockpitConfig.Light.Color
	viewport.LightDirection = CockpitConfig.Light.Direction
	viewport.Parent = gui

	local camera = Instance.new("Camera")
	camera.Name = "CockpitCamera"
	camera.CFrame = CFrame.identity
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local root = Instance.new("Model")
	root.Name = "Cockpit"
	root.Parent = viewport

	self._gui = gui
	self._viewport = viewport
	self._camera = camera
	self._root = root
	self._band = nil :: number?
	self._theme = nil :: any
	self._accent = CarRarity.Colours[1]
	self._dash = nil :: Model?
	self._wheel = nil :: Model?
	self._wheelBase = CFrame.identity
	self._wheelAngle = 0
	--- The wheel the hands are on this frame, in eye space (the drawn one's base, or a `Hold`'s frame),
	--- its radius and how far it is turned. `_holdFit` is the frame and radius the arms were last
	--- stretched for, so a new wheel refits them and a turning one never does.
	self._holdFrame = wheelBase()
	self._holdRadius = CockpitConfig.Wheel.Radius
	self._holdAngle = 0
	self._holdFit = nil :: { frame: CFrame, radius: number }?
	self._dashShown = true
	self._armsShown = true
	self._needle = nil :: Part?
	self._needleLength = 0
	self._dialFrame = CFrame.identity
	self._speed = 0
	self._bar = nil :: Part?
	self._barFrame = CFrame.identity
	self._arms = {} :: { any }
	self._armsFrom = nil :: Model?
	self._armsModel = nil :: Model?
	self._car = nil :: Model?
	self._hitBox = nil :: BasePart?
	self._lightAt = 0

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return self
end

--- The rarity theme for `band`, clamped to the table like `CarRarity.colourOf` clamps its colours.
local function themeFor(band: number): any
	local themes = CockpitConfig.Themes
	return themes[math.clamp(band, 1, #themes)]
end

function FirstPersonCockpit._clearDash(self)
	-- By reference as well as off the root: a hidden dash is parented to nil (see `_showDash`).
	for _, model in { self._dash, self._wheel } do
		if model then
			model:Destroy()
		end
	end
	for _, child in self._root:GetChildren() do
		if child.Name ~= "Arms" then
			child:Destroy()
		end
	end
	self._dash = nil
	self._wheel = nil
	self._needle = nil
	self._bar = nil
end

--- Materials a ViewportFrame draws flat: Neon reads as a bright flat colour, which is what we want.
local function accentMaterial(theme): Enum.Material
	return if theme.Neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
end

function FirstPersonCockpit._buildDash(self, theme, accent: Color3)
	local root = self._root
	local D = CockpitConfig.Dash
	local W = CockpitConfig.DashWidth
	local cx = CockpitConfig.CabinCentreX

	local dash = Instance.new("Model")
	dash.Name = "Dash"

	-- The cowl: the dash top, running from just beyond the wheel to the windscreen, nose-down a touch.
	local cowlY = -D.TopDrop - D.Thickness / 2
	local cowlZ = D.NearZ - D.Depth / 2
	part(
		dash,
		"Cowl",
		Vector3.new(W, D.Thickness, D.Depth),
		CFrame.new(cx, cowlY, cowlZ) * CFrame.Angles(-math.rad(D.TiltDeg), 0, 0),
		theme.Dash,
		theme.DashMaterial
	)
	-- The face under it, down past the bottom of the frame.
	local faceTop = -D.TopDrop - D.Thickness
	part(
		dash,
		"Face",
		Vector3.new(W, D.FaceHeight, 0.3),
		CFrame.new(cx, faceTop - D.FaceHeight / 2, D.NearZ - 0.15),
		theme.Face,
		theme.DashMaterial
	)
	-- Trim where the two meet, and the accent line along the cowl's near edge.
	part(
		dash,
		"Trim",
		Vector3.new(W, 0.08, 0.34),
		CFrame.new(cx, faceTop, D.NearZ - 0.15),
		theme.Trim,
		theme.TrimMaterial
	)
	part(
		dash,
		"Strip",
		Vector3.new(W - 0.4, D.StripThickness, D.StripThickness),
		CFrame.new(cx, -D.TopDrop + D.StripThickness / 2, D.NearZ + 0.02),
		accent,
		accentMaterial(theme)
	)

	-- The instrument pod behind the wheel, standing on the cowl in front of the driver.
	local H = D.Hood
	local podZ = D.NearZ - 0.12 - H.Depth / 2
	part(
		dash,
		"Pod",
		Vector3.new(H.Width, H.Height, H.Depth),
		CFrame.new(0, -D.TopDrop + H.Height / 2 - 0.02, podZ),
		theme.Face,
		theme.DashMaterial
	)
	part(
		dash,
		"PodTrim",
		Vector3.new(H.Width + 0.08, 0.06, H.Depth + 0.08),
		CFrame.new(0, -D.TopDrop + H.Height - 0.02, podZ),
		theme.Trim,
		theme.TrimMaterial
	)

	-- The dial on the pod's near face, tilted up toward the eye.
	local C = CockpitConfig.Cluster
	local dialCentre = Vector3.new(0, -D.TopDrop + H.Height / 2 - 0.02, D.NearZ - 0.12 + 0.03)
	local dialFrame = CFrame.new(dialCentre)
	local dialR = math.min(C.Radius, H.Height / 2 - 0.04)
	cylinder(
		dash,
		"DialRim",
		Vector3.new(0.05, dialR * 2 + 0.08, dialR * 2 + 0.08),
		dialFrame * CFrame.Angles(0, math.rad(90), 0),
		theme.Trim,
		theme.TrimMaterial
	)
	cylinder(
		dash,
		"Dial",
		Vector3.new(0.05, dialR * 2, dialR * 2),
		dialFrame * CFrame.new(0, 0, 0.012) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(14, 14, 16),
		Enum.Material.SmoothPlastic
	)
	local from, to = C.NeedleFromDeg, C.NeedleToDeg
	for index = 0, C.Ticks - 1 do
		local angle = math.rad(from + (to - from) * index / math.max(C.Ticks - 1, 1))
		local major = index % 2 == 0
		part(
			dash,
			"Tick",
			Vector3.new(if major then 0.07 else 0.045, 0.025, 0.02),
			dialFrame * CFrame.new(0, 0, 0.045) * CFrame.Angles(0, 0, angle) * CFrame.new(dialR - 0.06, 0, 0),
			if major then accent else Color3.fromRGB(200, 200, 205),
			accentMaterial(theme)
		)
	end
	local needleLength = dialR - 0.05
	local needle = part(
		dash,
		"Needle",
		Vector3.new(needleLength, 0.035, 0.02),
		dialFrame,
		Color3.fromRGB(240, 80, 70),
		Enum.Material.Neon
	)
	cylinder(
		dash,
		"NeedleCap",
		Vector3.new(0.03, 0.12, 0.12),
		dialFrame * CFrame.new(0, 0, 0.055) * CFrame.Angles(0, math.rad(90), 0),
		theme.Trim,
		theme.TrimMaterial
	)
	self._needle = needle
	self._needleLength = needleLength
	self._dialFrame = dialFrame * CFrame.new(0, 0, 0.05)

	-- The steering column, from the hub down into the face.
	local Wh = CockpitConfig.Wheel
	local hub = Wh.Offset
	local columnEnd = Vector3.new(hub.X, hub.Y - 0.45, D.NearZ - 0.1)
	local columnMid = (hub + columnEnd) / 2
	local columnLen = (columnEnd - hub).Magnitude
	cylinder(
		dash,
		"Column",
		Vector3.new(columnLen + 0.2, 0.26, 0.26),
		CFrame.lookAt(columnMid, columnEnd) * CFrame.Angles(0, math.rad(90), 0),
		theme.Face,
		Enum.Material.SmoothPlastic
	)

	-- The centre stack: a screen with the HP bar on it, and two vents.
	local Co = CockpitConfig.Console
	local S = Co.Screen
	local screenFrame = CFrame.new(cx + S.Offset.X, S.Offset.Y, S.Offset.Z) * CFrame.Angles(math.rad(S.TiltDeg), 0, 0)
	part(
		dash,
		"ScreenBezel",
		S.Size + Vector3.new(0.12, 0.12, 0),
		screenFrame * CFrame.new(0, 0, -0.01),
		theme.Trim,
		theme.TrimMaterial
	)
	part(dash, "Screen", S.Size, screenFrame, Color3.fromRGB(10, 10, 12), Enum.Material.SmoothPlastic)
	if theme.Screen then
		-- A lit frame line on the screen, in the accent, so a Rare's cabin glows a little blue.
		part(
			dash,
			"ScreenGlow",
			Vector3.new(S.Size.X - 0.1, 0.03, 0.02),
			screenFrame * CFrame.new(0, S.Size.Y / 2 - 0.08, S.Size.Z / 2 + 0.01),
			accent,
			accentMaterial(theme)
		)
	end
	local B = C.Bar
	local barFrame = screenFrame * CFrame.new(-B.Width / 2, -S.Size.Y / 2 + B.Drop * S.Size.Y, S.Size.Z / 2 + 0.015)
	part(
		dash,
		"BarTrack",
		Vector3.new(B.Width + 0.04, B.Height + 0.04, 0.01),
		barFrame * CFrame.new(B.Width / 2, 0, -0.005),
		Color3.fromRGB(40, 40, 46),
		Enum.Material.SmoothPlastic
	)
	local bar = part(
		dash,
		"HealthBar",
		Vector3.new(B.Width, B.Height, 0.015),
		barFrame * CFrame.new(B.Width / 2, 0, 0.005),
		accent,
		-- Unlit below Rare: a neon bar in Common's near-white read as a stray white stripe.
		accentMaterial(theme)
	)
	self._bar = bar
	self._barFrame = barFrame
	for index = 1, Co.Vents do
		local side = if index % 2 == 1 then -1 else 1
		local x = cx + side * (S.Size.X / 2 + 0.45)
		part(
			dash,
			"Vent",
			Co.VentSize,
			CFrame.new(x, S.Offset.Y + 0.15, D.NearZ + 0.02),
			Color3.fromRGB(22, 22, 26),
			Enum.Material.SmoothPlastic
		)
		part(
			dash,
			"VentTrim",
			Co.VentSize + Vector3.new(0.08, 0.08, -0.02),
			CFrame.new(x, S.Offset.Y + 0.15, D.NearZ + 0.01),
			theme.Trim,
			theme.TrimMaterial
		)
	end

	dash.Parent = if self._dashShown then root else nil
	self._dash = dash
end

function FirstPersonCockpit._buildWheel(self, theme, accent: Color3)
	local Wh = CockpitConfig.Wheel
	local wheel = Instance.new("Model")
	wheel.Name = "Wheel"

	local base = wheelBase()
	local R, N = Wh.Radius, Wh.Segments
	local segLen = 2 * math.pi * R / N * 1.1
	local flat = theme.FlatBottom and Wh.FlatBottomDeg or 0
	for index = 0, N - 1 do
		local deg = 360 * (index + 0.5) / N
		if flat > 0 and math.abs(((deg - 270 + 180) % 360) - 180) < flat then
			continue
		end
		local a = math.rad(deg)
		local isStripe = theme.TopStripe and math.abs(deg - 90) < 360 / N / 2 + 0.01
		cylinder(
			wheel,
			"Rim",
			Vector3.new(segLen, Wh.RimThickness, Wh.RimThickness),
			base * CFrame.new(R * math.cos(a), R * math.sin(a), 0) * CFrame.Angles(0, 0, a + math.pi / 2),
			if isStripe then accent else theme.Wheel,
			if isStripe then accentMaterial(theme) else theme.WheelMaterial
		)
	end
	if flat > 0 then
		local half = R * math.sin(math.rad(flat))
		local y = -R * math.cos(math.rad(flat))
		part(
			wheel,
			"FlatBottom",
			Vector3.new(half * 2 + Wh.RimThickness * 0.6, Wh.RimThickness * 0.9, Wh.RimThickness),
			base * CFrame.new(0, y, 0),
			theme.Wheel,
			theme.WheelMaterial
		)
	end

	-- Spokes: three (9, 3 and 6 o'clock) or four (two horizontal pairs). Each is the wheel's own
	-- colour with a thin trim inlay down its face, which reads as a trimmed spoke rather than a slab
	-- of trim colour; the inlay stops short of both ends so the rim and the pad stay unbroken.
	local spokeDegs = if theme.Spokes >= 4 then { 20, 160, 200, 340 } else { 0, 180, 270 }
	local Sp = Wh.Spoke
	local Hb = Wh.Hub
	for _, deg in spokeDegs do
		local a = math.rad(deg)
		local len = R - Hb.Radius + 0.05
		local mid = Hb.Radius - 0.05 + len / 2
		local spoke = base * CFrame.Angles(0, 0, a) * CFrame.new(mid, 0, 0)
		part(wheel, "Spoke", Vector3.new(len, Sp.Width, Sp.Thickness), spoke, theme.Wheel, theme.WheelMaterial)
		part(
			wheel,
			"SpokeInlay",
			Vector3.new(len - Sp.InlayInset * 2, Sp.InlayWidth, 0.02),
			spoke * CFrame.new(0, 0, Sp.Thickness / 2 + 0.005),
			theme.Trim,
			theme.TrimMaterial
		)
	end

	-- The pad: a squat cylinder in the wheel's colour sat in a trim ring a size up, and a small badge
	-- in the accent on its face. Lit on the neon themes, plain trim on the rest.
	cylinder(
		wheel,
		"HubRing",
		Vector3.new(Hb.Thickness * 0.6, Hb.Radius * 2 + Hb.Ring * 2, Hb.Radius * 2 + Hb.Ring * 2),
		base * CFrame.new(0, 0, -Hb.Thickness * 0.2) * CFrame.Angles(0, math.rad(90), 0),
		theme.Trim,
		theme.TrimMaterial
	)
	cylinder(
		wheel,
		"Hub",
		Vector3.new(Hb.Thickness, Hb.Radius * 2, Hb.Radius * 2),
		base * CFrame.Angles(0, math.rad(90), 0),
		theme.Wheel,
		theme.WheelMaterial
	)
	cylinder(
		wheel,
		"Badge",
		Vector3.new(0.03, Hb.Badge * 2, Hb.Badge * 2),
		base * CFrame.new(0, 0, Hb.Thickness / 2 + 0.01) * CFrame.Angles(0, math.rad(90), 0),
		if theme.Neon then accent else theme.Trim,
		if theme.Neon then accentMaterial(theme) else theme.TrimMaterial
	)

	wheel.WorldPivot = base
	wheel.Parent = if self._dashShown then self._root else nil
	self._wheel = wheel
	self._wheelBase = base
end

--[[ Build (or rebuild) the dash and wheel for a rarity band. Cheap enough to do on a steal: a
	couple of hundred parts, once. The arms survive it; they are the player's, not the car's. ]]
function FirstPersonCockpit._build(self, band: number)
	self._band = band
	local theme = themeFor(band)
	local accent = theme.Accent or CarRarity.colourOf(band)
	self._theme = theme
	self._accent = accent
	self:_clearDash()
	self:_buildDash(theme, accent)
	self:_buildWheel(theme, accent)
	self:_placeWheel()
end

-- === The arms ================================================================

local function cleanLimb(clone: BasePart)
	for _, child in clone:GetDescendants() do
		if
			child:IsA("Constraint")
			or child:IsA("JointInstance")
			or child:IsA("BaseScript")
			or child:IsA("Sound")
			or child:IsA("WrapLayer")
			or child:IsA("WrapTarget")
		then
			child:Destroy()
		end
	end
	clone.Anchored = true
	clone.CanCollide = false
	clone.CanQuery = false
	clone.CanTouch = false
	clone.CastShadow = false
	clone.Massless = true
	clone.Transparency = 0
	clone.LocalTransparencyModifier = 0
end

--- A plain limb part for a character we cannot borrow from.
local function plainLimb(name: string, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	cleanLimb(p)
	return p
end

--[[ One arm's record: the parts (cloned off the character or built), the joint points in each part's
	own space, the two bone lengths, and the grip and pole for the solve. `side` is "Left" or "Right". ]]
function FirstPersonCockpit._buildArm(self, character: Model?, side: string, folder: Instance)
	local A = CockpitConfig.Arms
	local F = A.Fallback
	local upperSrc = character and character:FindFirstChild(side .. "UpperArm")
	local lowerSrc = character and character:FindFirstChild(side .. "LowerArm")
	local handSrc = character and character:FindFirstChild(side .. "Hand")
	local r6Src = character and character:FindFirstChild(side .. " Arm")

	local upper: BasePart, lower: BasePart?, hand: BasePart?
	local uShoulder, uElbow, lElbow, lWrist, hWrist, hGrip

	if upperSrc and upperSrc:IsA("BasePart") and lowerSrc and lowerSrc:IsA("BasePart") then
		-- R15: three parts, joints read off the rig attachments so a scaled avatar still lines up.
		upper = upperSrc:Clone()
		lower = lowerSrc:Clone()
		hand = if handSrc and handSrc:IsA("BasePart") then handSrc:Clone() else nil
		uShoulder = attachmentAt(upperSrc, side .. "ShoulderRigAttachment", Vector3.new(0, upperSrc.Size.Y / 2, 0))
		uElbow = attachmentAt(upperSrc, side .. "ElbowRigAttachment", Vector3.new(0, -upperSrc.Size.Y / 2, 0))
		lElbow = attachmentAt(lowerSrc, side .. "ElbowRigAttachment", Vector3.new(0, lowerSrc.Size.Y / 2, 0))
		lWrist = attachmentAt(lowerSrc, side .. "WristRigAttachment", Vector3.new(0, -lowerSrc.Size.Y / 2, 0))
		if hand then
			hWrist =
				attachmentAt(handSrc, side .. "WristRigAttachment", Vector3.new(0, (handSrc :: BasePart).Size.Y / 2, 0))
			hGrip =
				attachmentAt(handSrc, side .. "GripAttachment", Vector3.new(0, -(handSrc :: BasePart).Size.Y / 4, 0))
		end
	elseif r6Src and r6Src:IsA("BasePart") then
		-- R6: one part per arm, shoulder at the top, hand at the bottom.
		upper = r6Src:Clone()
		uShoulder = Vector3.new(0, r6Src.Size.Y / 2, 0)
		uElbow = Vector3.new(0, -r6Src.Size.Y / 2, 0)
	else
		upper = plainLimb(side .. "UpperArm", F.UpperSize, F.Color)
		lower = plainLimb(side .. "LowerArm", F.LowerSize, F.Color)
		hand = plainLimb(side .. "Hand", F.HandSize, F.Color)
		uShoulder = Vector3.new(0, F.UpperSize.Y / 2, 0)
		uElbow = Vector3.new(0, -F.UpperSize.Y / 2, 0)
		lElbow = Vector3.new(0, F.LowerSize.Y / 2, 0)
		lWrist = Vector3.new(0, -F.LowerSize.Y / 2, 0)
		hWrist = Vector3.new(0, F.HandSize.Y / 2, 0)
		hGrip = Vector3.new(0, 0, -F.HandSize.Z / 2)
	end

	for _, limb in { upper, lower, hand } do
		if limb then
			cleanLimb(limb)
			limb.Parent = folder
		end
	end

	-- Gloves, over whatever the hand was. Set before the sleeves go on, which composite over the
	-- part's own colour.
	local G = if A.Gloves and A.Gloves.Enabled then A.Gloves else nil
	if G and hand then
		hand.Color = G.Color
		hand.Material = G.Material
	end

	local isLeft = side == "Left"
	local shoulder = Vector3.new(if isLeft then -A.Shoulder.X else A.Shoulder.X, A.Shoulder.Y, A.Shoulder.Z)
	local gripDeg = if isLeft then A.LeftGripDeg else A.RightGripDeg

	-- The viewmodel share, once. The stretch to reach the rim is `fitArm`'s, per wheel.
	local share = A.Scale or Vector3.one
	if type(share) == "number" then
		share = Vector3.one * share
	end
	local sizes = {}
	for _, limb in { upper, lower, hand } do
		if limb then
			limb.Size = limb.Size * share
			sizes[limb] = limb.Size
		end
	end
	-- The glove's cuff: a band a hair proud of the glove, round the wrist end, so the glove reads as
	-- something worn rather than a dark hand. Its length is fixed; the stretch only lengthens limbs.
	local cuff: Part? = nil
	if G and G.Cuff and hand then
		cuff = plainLimb(side .. "GloveCuff", Vector3.new(
			hand.Size.X + G.Cuff.Proud * 2,
			G.Cuff.Length,
			hand.Size.Z + G.Cuff.Proud * 2
		), G.Cuff.Color)
		cuff.Material = G.Material
		cuff.Parent = folder
	end
	local function scaled(v: Vector3?): Vector3?
		return if v then v * share else nil
	end

	return {
		side = side,
		upper = upper,
		lower = lower,
		hand = hand,
		cuff = cuff,
		shoulder = shoulder,
		gripDeg = gripDeg,
		pole = if isLeft then A.LeftPole else A.RightPole,
		--- The joints and sizes before any stretch, so a refit starts from the arm and not from the last fit.
		base = {
			sizes = sizes,
			uShoulder = scaled(uShoulder),
			uElbow = scaled(uElbow),
			lElbow = scaled(lElbow),
			lWrist = scaled(lWrist),
			hWrist = scaled(hWrist),
			hGrip = scaled(hGrip),
		},
	}
end

--[[ Stretch an arm along its bone so its hand reaches `restGrip` (eye space) from its shoulder with
	`ReachMargin` to spare, up to `MaxStretch`: an R15 arm is 1.77 studs and the rim is further than
	that from a shoulder sat where a shoulder sits. Joint points scale with the parts, so the solve is
	still exact. Run when the arms are built and when the wheel they hold changes, never as it turns,
	so the arms do not breathe. ]]
local function fitArm(arm, restGrip: Vector3)
	local A = CockpitConfig.Arms
	local b = arm.base
	local function reachOf(stretch: number): number
		local total = (b.uElbow - b.uShoulder).Magnitude * stretch
		if arm.lower then
			total += (b.lWrist - b.lElbow).Magnitude * stretch
			if arm.hand and b.hWrist then
				-- The hand's centre is what sits on the rim, so the wrist-to-centre run is part of the bone.
				total += b.hWrist.Magnitude * stretch
			end
		end
		return total
	end
	local stretch = math.clamp(
		(restGrip - arm.shoulder).Magnitude * (A.ReachMargin or 1) / math.max(reachOf(1), 1e-3),
		1,
		A.MaxStretch or 1
	)
	local along = Vector3.new(1, stretch, 1)
	for limb, size in b.sizes do
		limb.Size = size * along
	end
	local function joint(v: Vector3?): Vector3?
		return if v then v * along else nil
	end
	arm.uShoulder, arm.uElbow = joint(b.uShoulder), joint(b.uElbow)
	arm.lElbow, arm.lWrist = joint(b.lElbow), joint(b.lWrist)
	arm.hWrist, arm.hGrip = joint(b.hWrist), joint(b.hGrip)
	arm.l1 = (arm.uElbow - arm.uShoulder).Magnitude
	arm.l2 = reachOf(stretch) - arm.l1
end

--- Where a hand holds the rim at `angle` radians of turn, in eye space, and the hub it holds on to.
function FirstPersonCockpit._gripAt(self, gripDeg: number, angle: number): (Vector3, Vector3)
	local turned = self._holdFrame * CFrame.Angles(0, 0, angle)
	local a = math.rad(gripDeg)
	local r = self._holdRadius
	return turned:PointToWorldSpace(Vector3.new(r * math.cos(a), r * math.sin(a), 0)), turned.Position
end

--- Fit the arms to the wheel they are on now, if it is not the one they were last fitted to.
function FirstPersonCockpit._fitArms(self)
	local fit = self._holdFit
	if
		fit
		and fit.radius == self._holdRadius
		and fit.frame.Position:FuzzyEq(self._holdFrame.Position, 1e-3)
		and fit.frame.LookVector:FuzzyEq(self._holdFrame.LookVector, 1e-3)
	then
		return
	end
	self._holdFit = { frame = self._holdFrame, radius = self._holdRadius }
	for _, arm in self._arms do
		fitArm(arm, (self:_gripAt(arm.gripDeg, 0)))
	end
end

--- Public: (re)build the arms from this character. Nil clears them.
function FirstPersonCockpit.setCharacter(self, character: Model?)
	-- By reference: hidden arms are parented to nil (see `_showArms`).
	if self._armsModel then
		self._armsModel:Destroy()
		self._armsModel = nil
	end
	self._arms = {}
	self._armsFrom = character
	self._holdFit = nil
	if not CockpitConfig.Arms.Enabled then
		return
	end
	local folder = Instance.new("Model")
	folder.Name = "Arms"
	for _, side in { "Left", "Right" } do
		table.insert(self._arms, self:_buildArm(character, side, folder))
	end
	--[[ The sleeves. A Humanoid and the character's classic Shirt in the same model is what makes the
		engine wrap the shirt round R15 limbs by their names, and it does that inside a viewport too
		(checked 2026-10-13 with a whole character clone). No BodyColors: it would paint over the
		gloves when they are on. The Humanoid is told to draw nothing of its own. ]]
	local shirt = character and character:FindFirstChildOfClass("Shirt")
	if shirt and #self._arms > 0 and self._arms[1].lower then
		local humanoid = Instance.new("Humanoid")
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.Parent = folder
		local copy = shirt:Clone()
		if copy then
			copy.Parent = folder
		end
	end
	folder.Parent = if self._armsShown then self._root else nil
	self._armsModel = folder
	self:_fitArms()
	self:_placeArms()
end

function FirstPersonCockpit._placeArms(self)
	-- The hands go round with the rim up to `GripFollowDeg`, then the rim slides under them, the way
	-- a palm lets a wheel run: past it the upper forearm would cross the whole frame.
	local follow = math.rad(CockpitConfig.Arms.GripFollowDeg or 180)
	local angle = math.clamp(self._holdAngle, -follow, follow)
	for _, arm in self._arms do
		local target, hub = self:_gripAt(arm.gripDeg, angle)
		local s = arm.shoulder
		local toHub = hub - target
		--- The side of the limb that faces the body when the arm hangs; it faces the hub on a wheel.
		local inward = if arm.side == "Left" then Vector3.xAxis else -Vector3.xAxis
		if arm.lower then
			local elbow = solveElbow(s, target, arm.l1, arm.l2, arm.pole)
			-- Upper arm: shoulder to elbow, its front facing the way the forearm goes.
			arm.upper.CFrame = pose(arm.uShoulder, arm.uElbow, s, elbow, -Vector3.zAxis, target - elbow)
			-- Forearm: elbow toward the hand, inside face toward the hub.
			local dir = (target - elbow)
			dir = if dir.Magnitude > 1e-4 then dir.Unit else -Vector3.zAxis
			local lowerLen = (arm.lWrist - arm.lElbow).Magnitude
			local wrist = elbow + dir * lowerLen
			arm.lower.CFrame = pose(arm.lElbow, arm.lWrist, elbow, wrist, inward, toHub)
			if arm.hand then
				-- Hand: wrist on, centre on the rim, palm toward the hub.
				arm.hand.CFrame = pose(arm.hWrist, Vector3.zero, wrist, target, inward, toHub)
				if arm.cuff then
					-- Centred on the wrist end (the hand's +Y), half over the forearm.
					arm.cuff.CFrame = arm.hand.CFrame * CFrame.new(0, arm.hand.Size.Y / 2, 0)
				end
			end
		else
			-- One bone: point the arm from the shoulder at the rim; it ends where it ends.
			local d = target - s
			local reach = math.min(d.Magnitude, arm.l1)
			local tip = s + (if d.Magnitude > 1e-4 then d.Unit else -Vector3.zAxis) * reach
			arm.upper.CFrame = pose(arm.uShoulder, arm.uElbow, s, tip, inward, toHub)
		end
	end
end

-- === Per frame ===============================================================

--- Show or hide the dash and the drawn wheel together, by parenting, only when it changes.
function FirstPersonCockpit._showDash(self, shown: boolean)
	if shown == self._dashShown then
		return
	end
	self._dashShown = shown
	for _, model in { self._dash, self._wheel } do
		if model then
			model.Parent = if shown then self._root else nil
		end
	end
end

function FirstPersonCockpit._showArms(self, shown: boolean)
	if shown == self._armsShown then
		return
	end
	self._armsShown = shown
	if self._armsModel then
		self._armsModel.Parent = if shown then self._root else nil
	end
end

function FirstPersonCockpit._placeWheel(self)
	local wheel = self._wheel
	if wheel then
		wheel:PivotTo(self._wheelBase * CFrame.Angles(0, 0, self._wheelAngle))
	end
end

function FirstPersonCockpit._health(self, car: Model?): number
	if car ~= self._car then
		self._car = car
		self._hitBox = nil
	end
	if not car then
		return 1
	end
	local hitBox = self._hitBox
	if not (hitBox and hitBox.Parent) then
		hitBox = car:FindFirstChild(ObstacleConfig.HitBoxName, true)
		self._hitBox = hitBox
	end
	if not hitBox then
		return 1
	end
	local health = hitBox:GetAttribute("Health")
	local max = hitBox:GetAttribute("MaxHealth")
	if type(health) ~= "number" or type(max) ~= "number" or max <= 0 then
		return 1
	end
	return math.clamp(health / max, 0, 1)
end

--- Public: the car being driven. Picks the cockpit for its rarity; a change of band rebuilds.
function FirstPersonCockpit.setCar(self, car: Model?)
	local band = 1
	if car then
		local _, found = CarRarity.of(CarStats.bodyOf(car))
		band = found or 1
	end
	if band ~= self._band then
		self:_build(band)
	end
	self._car = car
	self._hitBox = nil
end

function FirstPersonCockpit.update(self, view: View)
	local gui = self._gui
	if not self._band then
		self:_build(1)
	end
	if view.alpha <= 0.01 then
		if gui.Enabled then
			gui.Enabled = false
		end
		return
	end
	if not gui.Enabled then
		gui.Enabled = true
	end

	local viewport = self._viewport
	viewport.ImageTransparency = 1 - view.alpha
	-- The whole trick: look at the fixed cockpit from where the real camera is relative to the eye.
	self._camera.CFrame = view.frame:ToObjectSpace(view.camera)
	self._camera.FieldOfView = view.fov

	local now = os.clock()
	local L = CockpitConfig.Light
	if now >= self._lightAt then
		self._lightAt = now + L.Resample
		local ambient = Lighting.OutdoorAmbient:Lerp(WHITE, L.AmbientLift)
		local floor = L.MinAmbient
		viewport.Ambient =
			Color3.new(math.max(ambient.R, floor.R), math.max(ambient.G, floor.G), math.max(ambient.B, floor.B))
	end

	-- What is drawn: the dash and its wheel, the arms, or both.
	self:_showDash(view.dash ~= false)
	self:_showArms(view.arms ~= false and #self._arms > 0)

	-- The wheel follows the steer, and the hands follow the wheel: the drawn one, or the car's own.
	local Wh = CockpitConfig.Wheel
	local wantAngle = math.rad(Wh.MaxDeg) * math.clamp(view.steer, -1, 1)
	self._wheelAngle = approach(self._wheelAngle, wantAngle, view.dt, Wh.Gain)
	self:_placeWheel()
	local hold = view.hold
	if hold then
		self._holdFrame, self._holdRadius, self._holdAngle = hold.frame, hold.radius, hold.angle
	else
		self._holdFrame, self._holdRadius, self._holdAngle = self._wheelBase, Wh.Radius, self._wheelAngle
	end
	if self._armsShown then
		self:_fitArms()
		self:_placeArms()
	end

	-- The needle, on a soft follow so a gear's worth of speed change reads as a sweep.
	local C = CockpitConfig.Cluster
	self._speed = approach(self._speed, math.clamp(view.speed, 0, 1), view.dt, C.NeedleGain)
	local needle = self._needle
	if needle then
		local angle = math.rad(C.NeedleFromDeg + (C.NeedleToDeg - C.NeedleFromDeg) * self._speed)
		needle.CFrame = self._dialFrame * CFrame.Angles(0, 0, angle) * CFrame.new(self._needleLength / 2 - 0.03, 0, 0)
	end

	-- The HP bar shortens from the right and goes red on the way down.
	local bar = self._bar
	if bar then
		local hp = self:_health(view.car)
		local B = C.Bar
		local width = math.max(B.Width * hp, 0.01)
		bar.Size = Vector3.new(width, B.Height, 0.015)
		bar.CFrame = self._barFrame * CFrame.new(width / 2, 0, 0.005)
		bar.Color = C.Low:Lerp(self._accent, hp)
	end
end

--- Public: take it off screen without tearing it down. The next `update` with alpha puts it back.
function FirstPersonCockpit.hide(self)
	if self._gui.Enabled then
		self._gui.Enabled = false
	end
end

function FirstPersonCockpit.destroy(self)
	-- Hidden models are parented to nil, so the gui going does not take them with it.
	for _, model in { self._dash, self._wheel, self._armsModel } do
		if model then
			model:Destroy()
		end
	end
	self._gui:Destroy()
	self._arms = {}
	self._armsModel = nil
	self._dash = nil
	self._wheel = nil
	self._needle = nil
	self._bar = nil
end

return FirstPersonCockpit
