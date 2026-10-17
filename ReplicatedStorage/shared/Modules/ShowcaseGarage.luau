--[[
	ShowcaseGarage  (client)
	------------------------
	THE NEW BEST CUTSCENE'S GARAGE (2026-10-02). A dark concrete garage built from plain parts round
	the car and the avatar: square pillars, a roller door, crates in the back corners, downlights
	washing the back wall, a lit frame in the ceiling and a ring of light on the floor round the
	pair, with every strip of neon in the car's rarity colour. `ShowcaseController` builds it in place
	of the round room when `ShowcaseConfig.Stage.Room` is "Garage"; every number is in
	`ShowcaseConfig.Garage`.

	FIVE THINGS TO KNOW BEFORE TOUCHING THIS.

	  1. THE ROOM IS LAID OUT ROUND THE SHOT. It is centred on the point the camera looks at, the
	     camera rests on +Z looking down -Z like the rest of the stage, and the front wall sits
	     `FrontMargin` behind the camera's resting distance. A long car pushes the camera out, so it
	     gets a deeper room rather than a lens through a wall.
	  2. THE FLOOR IS A WINDOW, NOT A MIRROR. Roblox reflects the sky and never a part, so every part
	     of the room is built a second time upside down under the floor, and the floor is part
	     see-through (`Gloss`): what shows through it IS the reflection. Only boxes and cylinders are
	     flipped, because a flipped box is still a box. A car or an avatar cannot be flipped that way
	     (a mesh would come out inside out), so `reflect` rolls a copy over onto its back instead,
	     which is the same picture for anything that is the same on its left and its right.
	  3. THE NEON IS ON A DIAL. Every strip and every light that colours the room is recorded with its
	     lit value, and `setPower` / `powerOn` run it between an unlit grey (`Dim`) and the rarity
	     colour. That is what lets the reveal hold the room dark and switch it on at the hit, so the
	     colour that tells the rarity arrives with the car and not before it.
	  4. THE WORLD'S SKY AND HAZE ARE KEPT OUT WHILE IT DRAWS (`holdWorld`). The room stands inside
	     whatever world the player is in, and that world's sky light and Atmosphere reach through any
	     wall: left in, the dark garage came out a washed-out blue-grey. They are swapped out for the
	     render only, so no other script ever sees the swap.
	  5. NOTHING HERE COLLIDES, IS QUERIED OR IS TOUCHED. The stage is a picture.

	Soft light on the walls (the glow round a strip, the wash under a downlight) is PAINTED, on
	SurfaceGuis (`glowPanel`), not lit: the place's lighting is too coarse for a light a stud off a
	wall to draw anything but a smear.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ShowcaseConfig = require(ReplicatedStorage.shared.Configs.ShowcaseConfig)

local ShowcaseGarage = {}

local WHITE = Color3.new(1, 1, 1)

--[[ One thing on the power dial (header note 3): where it is, how to set it to a power from 0 to 1,
	and the power it never drops below (`Garage.Standby` for the neutral lights, 0 for the rest). ]]
type Dial = { at: Vector3, floor: number, set: (number) -> () }

export type Room = {
	model: Model,
	floorY: number,
	dials: { Dial },
}

--- A neon part on the dial: the unlit grey at 0, `lit` at 1.
local function neonDial(p: BasePart, lit: Color3, floor: number): Dial
	local dim = ShowcaseConfig.Garage.Dim
	return {
		at = p.Position,
		floor = floor,
		set = function(power)
			p.Color = dim:Lerp(lit, power)
		end,
	}
end

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

--[[ `cf` reflected through the floor plane at `floorY`. The rotation is M·R·M with M the Y flip, which
	is a proper rotation (no mirror in it), so it is a CFrame Roblox will take; on a box or a cylinder
	it draws exactly the box's reflection, because flipping a box along its own axis changes nothing. ]]
local function flip(cf: CFrame, floorY: number): CFrame
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return CFrame.new(x, 2 * floorY - y, z, r00, -r01, r02, -r10, r11, -r12, r20, -r21, r22)
end

--- `count` points spread evenly along `from`..`to`, each in the middle of its own share of the run.
local function along(from: number, to: number, spacing: number): { number }
	local count = math.max(1, math.floor((to - from) / spacing + 0.5))
	local points = {}
	for i = 1, count do
		points[i] = from + (to - from) * (i - 0.5) / count
	end
	return points
end

--- A NumberSequence's value at `t` (0 to 1), straight-line between its keypoints.
local function sample(sequence: NumberSequence, t: number): number
	local points = sequence.Keypoints
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if t <= b.Time then
			local span = b.Time - a.Time
			return if span > 0 then a.Value + (b.Value - a.Value) * (t - a.Time) / span else b.Value
		end
	end
	return points[#points].Value
end

--[[ Build the garage into `parent`. `floorTop` is the floor's height (only its Y is used), `focus` the
	point on the floor the camera looks over, `reach` the camera's resting distance from it,
	`ringRadius` the floor ring's, and `accent` the rarity colour. Built LIT; call `setPower(room, 0)`
	to hold it dark. ]]
function ShowcaseGarage.build(parent: Instance, floorTop: Vector3, focus: Vector3, reach: number, ringRadius: number, accent: Color3): Room
	local cfg = ShowcaseConfig.Garage
	local colors = cfg.Colors
	local floorY = floorTop.Y
	local base = CFrame.new(focus.X, floorY, focus.Z)

	local model = Instance.new("Model")
	model.Name = "Garage"
	local room: Room = { model = model, floorY = floorY, dials = {} }
	-- Every neon part with its lit colour and its dial floor, kept for the reflection.
	local neonLit: { [BasePart]: { lit: Color3, floor: number } } = {}
	--[[ The neutral lights (the downlights, their lenses and washes) stay at this through the hold,
		so the room keeps its shape round the dancing avatar while every rarity colour waits. ]]
	local standby = cfg.Standby

	--[[ The room in its own terms: x across the shot, z toward the camera, y up off the floor. The
		side walls clear the opening sweep, which starts about 0.63 of the resting distance out to the
		side. ]]
	local halfW = math.max(cfg.Width / 2, reach * 0.7 + 5)
	local zBack = -cfg.Back
	local zFront = reach + cfg.FrontMargin
	local depth = zFront - zBack
	local zMid = (zBack + zFront) / 2
	local height = cfg.Height
	local pillar = cfg.PillarSize
	local inner = halfW - pillar -- the back wall's clear half-width, between the corner pillars
	local stripY = cfg.StripHeight

	local function box(name: string, size: Vector3, at: CFrame, color: Color3, material: Enum.Material?): Part
		return part(model, { Name = name, Size = size, CFrame = base * at, Color = color, Material = material or Enum.Material.SmoothPlastic })
	end
	local function glow(name: string, size: Vector3, at: CFrame, color: Color3): Part
		local p = part(model, { Name = name, Size = size, CFrame = base * at, Color = color, Material = Enum.Material.Neon })
		neonLit[p] = { lit = color, floor = 0 }
		return p
	end
	-- The rarity colour as neon draws it (`NeonDepth`).
	local neon = accent:Lerp(Color3.new(0, 0, 0), cfg.NeonDepth)

	--[[ A soft patch of light painted on a wall (`Glow`): an unlit SurfaceGui on an invisible slab,
		faded top to bottom by a gradient (`vertical`). A patch that also fades at its sides
		(`horizontal`) is cut into `Glow.Slices` upright strips, each carrying the same gradient and its
		own share of the side fade as its transparency; a UIGradient can only run one way, and a
		CanvasGroup's gradient (the obvious second axis) is not drawn on a SurfaceGui. This is the glow
		round a strip and the wash under a downlight. Neither can be a light: the place's lighting is
		too coarse to draw a light 1 stud off a wall as anything but a faint smear, and see-through
		neon draws a hard-edged band. `face` is the slab's side that looks into the room.

		`vertical` may instead be a function of how far out a strip is (0 the middle, 1 an edge),
		which is how a downlight's wash spreads into a cone: the outer strips start lower down.

		Each strip keeps its lit transparency as its `Base` attribute, which is what the power dial
		scales (`build`'s dials). ]]
	local function glowPanel(size: Vector3, at: CFrame, face: Enum.NormalId, color: Color3, vertical: NumberSequence | ((number) -> NumberSequence), horizontal: NumberSequence?, floor: number?)
		local holder = part(model, { Name = "Glow", Size = size, CFrame = base * at, Transparency = 1 })
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Glow"
		gui:SetAttribute("Standby", floor or 0)
		gui.Face = face
		gui.LightInfluence = 0
		gui.Brightness = cfg.Glow.Brightness
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = cfg.Glow.PixelsPerStud
		gui.Parent = holder
		local slices = if horizontal then cfg.Glow.Slices else 1
		for i = 1, slices do
			local u = (i - 0.5) / slices
			local baseT = if horizontal then sample(horizontal, u) else 0
			local fill = Instance.new("Frame")
			fill.Name = "Fill"
			fill.Position = UDim2.fromScale((i - 1) / slices, 0)
			fill.Size = UDim2.fromScale(1 / slices, 1)
			fill.BorderSizePixel = 0
			fill.BackgroundColor3 = color
			fill.BackgroundTransparency = baseT
			fill:SetAttribute("Base", baseT)
			local down = Instance.new("UIGradient")
			down.Rotation = 90
			down.Transparency = if type(vertical) == "function" then vertical(math.abs(u - 0.5) * 2) else vertical
			down.Parent = fill
			fill.Parent = gui
		end
	end
	--[[ A gradient that is opaque to `strength` at `peak` (0 the top or left edge, 1 the bottom or
		right) and fades to nothing either side, through 30% of the peak halfway out. ]]
	local function falloff(peak: number, strength: number): NumberSequence
		local low, mid = 1 - strength, 1 - strength * 0.3
		local points = { NumberSequenceKeypoint.new(0, if peak <= 0 then low else 1) }
		if peak > 0 then
			table.insert(points, NumberSequenceKeypoint.new(peak * 0.5, mid))
			table.insert(points, NumberSequenceKeypoint.new(peak, low))
		end
		if peak < 1 then
			table.insert(points, NumberSequenceKeypoint.new(peak + (1 - peak) * 0.5, mid))
			table.insert(points, NumberSequenceKeypoint.new(1, 1))
		end
		return NumberSequence.new(points)
	end
	local function lamp(light: Light, at: CFrame, floor: number?)
		local holder = part(model, { Name = "Lamp", Size = Vector3.one * 0.2, CFrame = base * at, Transparency = 1 })
		light.Parent = holder
		local lit = light.Brightness
		table.insert(room.dials, {
			at = holder.Position,
			floor = floor or 0,
			set = function(power)
				light.Brightness = lit * power
			end,
		})
	end
	--- The coloured light a strip throws round itself (`Spill`).
	local function spill(at: Vector3, scale: number?)
		local light = Instance.new("PointLight")
		light.Color = accent
		light.Brightness = cfg.Spill.Brightness * (scale or 1)
		light.Range = cfg.Spill.Range
		lamp(light, CFrame.new(at))
	end

	-- === The shell ===
	part(model, {
		Name = "Floor",
		Size = Vector3.new(halfW * 2 + 2, 1, depth + 2),
		CFrame = base * CFrame.new(0, -0.5, zMid),
		Color = colors.Floor,
		Material = Enum.Material.SmoothPlastic,
		Transparency = cfg.Gloss,
	})
	--[[ The shell is `SHELL` thick. One stud of wall is thinner than the engine's lighting grid, and
		the sky leaked through it: the room came out lit like a porch. ]]
	local SHELL = 4
	box("Ceiling", Vector3.new(halfW * 2 + SHELL * 2, SHELL, depth + SHELL * 2), CFrame.new(0, height + SHELL / 2, zMid), colors.Ceiling)
	for _, z in { zBack - SHELL / 2, zFront + SHELL / 2 } do
		box("Wall", Vector3.new(halfW * 2 + SHELL * 2, height, SHELL), CFrame.new(0, height / 2, z), colors.Wall, Enum.Material.Concrete)
	end
	for _, side in { -1, 1 } do
		box("Wall", Vector3.new(SHELL, height, depth), CFrame.new(side * (halfW + SHELL / 2), height / 2, zMid), colors.Wall, Enum.Material.Concrete)
	end

	-- === The back wall: panel seams, the neon line under its ledge, the downlights, the base line ===
	local panels = math.max(2, math.floor(inner * 2 / cfg.PanelWidth + 0.5))
	for i = 1, panels - 1 do
		box("Seam", Vector3.new(0.25, height, 0.2), CFrame.new(-inner + i * (inner * 2 / panels), height / 2, zBack + 0.1), colors.Seam)
	end
	box("Ledge", Vector3.new(inner * 2, 0.8, 0.9), CFrame.new(0, stripY + 0.6, zBack + 0.45), colors.Trim)
	glow("Strip", Vector3.new(inner * 2, 0.4, 0.3), CFrame.new(0, stripY, zBack + 0.25), neon)
	glow("BaseStrip", Vector3.new(inner * 2, 0.3, 0.3), CFrame.new(0, 0.25, zBack + 0.15), neon)
	-- The line's glow hangs below it (the ledge is above); the base line's rises off the floor.
	local glowH, strength = cfg.Glow.Height, cfg.Glow.Strength
	local back = Enum.NormalId.Back -- an unturned slab's +Z side, which faces the camera
	glowPanel(Vector3.new(inner * 2, glowH, 0.05), CFrame.new(0, stripY - glowH * 0.25, zBack + 0.06), back, accent, falloff(0.25, strength))
	glowPanel(Vector3.new(inner * 2, glowH * 0.6, 0.05), CFrame.new(0, glowH * 0.3, zBack + 0.06), back, accent, falloff(1, strength))
	for _, x in along(-inner, inner, cfg.Spill.Spacing) do
		spill(Vector3.new(x, stripY - 0.6, zBack + 1.4))
		spill(Vector3.new(x, 0.8, zBack + 1.2), 0.7)
	end

	--[[ Downlights under the line, a little off the wall and tipped into it (a holder turned +X about
		its own X points its -Y face toward -Z), so each throws the bright scallop down the wall. ]]
	local downlights = cfg.Downlights
	for i = 1, downlights.Count do
		local x = (i - (downlights.Count + 1) / 2) * downlights.Spacing
		local y = stripY - 1.3
		local z = zBack + 1.3
		local upright = CFrame.Angles(0, 0, math.rad(90))
		part(model, {
			Name = "Downlight",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, 1.5, 1.5),
			CFrame = base * CFrame.new(x, y, z) * upright,
			Color = colors.Trim,
			Material = Enum.Material.SmoothPlastic,
		})
		local lens = part(model, {
			Name = "DownlightLens",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, 1.1, 1.1),
			CFrame = base * CFrame.new(x, y - 0.33, z) * upright,
			Color = colors.Lamp,
			Material = Enum.Material.Neon,
		})
		neonLit[lens] = { lit = colors.Lamp, floor = standby }
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Bottom
		spot.Color = colors.Lamp
		spot.Brightness = downlights.Brightness
		spot.Range = downlights.Range
		spot.Angle = downlights.Angle
		lamp(spot, CFrame.new(x, y - 0.5, z) * CFrame.Angles(math.rad(downlights.Tilt), 0, 0), standby)
		-- The scallop itself, painted: the light above does the room, this is the shape on the wall.
		local wash = downlights.Wash
		glowPanel(
			Vector3.new(wash.Width, wash.Height, 0.05),
			CFrame.new(x, y - 0.6 - wash.Height / 2, zBack + 0.07),
			back,
			colors.Lamp,
			function(out)
				return falloff(0.08 + wash.Spread * out, wash.Strength)
			end,
			falloff(0.5, wash.Strength),
			standby
		)
	end

	-- === The pillars, two bars of neon on the faces toward the middle and toward the camera ===
	local pillarZs = {}
	local pz = zBack + pillar / 2
	while pz <= zFront - pillar / 2 + 0.01 do
		table.insert(pillarZs, pz)
		pz += cfg.PillarSpacing
	end
	for _, side in { -1, 1 } do
		local px = side * (halfW - pillar / 2)
		for _, z in pillarZs do
			box("Pillar", Vector3.new(pillar, height, pillar), CFrame.new(px, height / 2, z), colors.Pillar)
			for _, y in { stripY, 2.2 } do
				glow("PillarBar", Vector3.new(0.25, 0.4, pillar - 1), CFrame.new(px - side * (pillar / 2 + 0.1), y, z), neon)
				glow("PillarBar", Vector3.new(pillar - 1, 0.4, 0.25), CFrame.new(px, y, z + pillar / 2 + 0.1), neon)
			end
		end
	end

	-- === The roller door, on the left wall between the first two pillars ===
	local doorW, doorH = 15, 11
	local doorZ = (pillarZs[1] + (pillarZs[2] or zFront)) / 2
	local wallX = -halfW
	for _, s in { -1, 1 } do
		box("DoorPost", Vector3.new(0.8, doorH + 0.8, 0.8), CFrame.new(wallX + 0.4, (doorH + 0.8) / 2, doorZ + s * (doorW / 2 + 0.4)), colors.Trim)
	end
	box("DoorHead", Vector3.new(1.2, 1.4, doorW + 1.6), CFrame.new(wallX + 0.6, doorH + 0.7, doorZ), colors.Trim)
	local slats = math.floor(doorH / 0.75)
	local pitch = doorH / slats
	for i = 1, slats do
		box(
			"Slat",
			Vector3.new(0.3, pitch - 0.1, doorW),
			CFrame.new(wallX + 0.15 + (i % 2) * 0.08, (i - 0.5) * pitch, doorZ),
			if i % 2 == 0 then colors.Door else colors.DoorAlt,
			Enum.Material.Metal
		)
	end
	box("DoorFoot", Vector3.new(0.6, 0.45, doorW), CFrame.new(wallX + 0.3, 0.22, doorZ), colors.Trim)

	-- === The side walls: a neon line under a ledge along the top, and one along the floor ===
	for _, side in { -1, 1 } do
		local x = side * (halfW - 0.15)
		box("SideLedge", Vector3.new(0.9, 0.8, depth), CFrame.new(side * (halfW - 0.45), height - 1, zMid), colors.Trim)
		glow("SideStrip", Vector3.new(0.3, 0.4, depth), CFrame.new(x, height - 1.6, zMid), neon)
		-- The left wall's slab looks into the room through its +X side, the right wall's through -X.
		local inward = if side < 0 then Enum.NormalId.Right else Enum.NormalId.Left
		local wallFace = side * (halfW - 0.06)
		glowPanel(Vector3.new(0.05, glowH, depth), CFrame.new(wallFace, height - 1.6 - glowH * 0.25, zMid), inward, accent, falloff(0.25, strength))
		-- The floor line stops either side of the door rather than running across it.
		local runs = if side < 0 then { { zBack, doorZ - doorW / 2 - 0.8 }, { doorZ + doorW / 2 + 0.8, zFront } } else { { zBack, zFront } }
		for _, run in runs do
			glow("SideBase", Vector3.new(0.3, 0.3, run[2] - run[1]), CFrame.new(x, 0.25, (run[1] + run[2]) / 2), neon)
			glowPanel(Vector3.new(0.05, glowH * 0.6, run[2] - run[1]), CFrame.new(wallFace, glowH * 0.3, (run[1] + run[2]) / 2), inward, accent, falloff(1, strength))
		end
		for i = 1, #pillarZs - 1 do
			local z = (pillarZs[i] + pillarZs[i + 1]) / 2
			spill(Vector3.new(side * (halfW - 1.4), height - 2.2, z))
			spill(Vector3.new(side * (halfW - 1.2), 0.8, z), 0.7)
		end
	end

	-- === Crates: a dark metal box, proud edges, an X across the front and neon down its front corners ===
	local function crate(at: CFrame, size: Vector3)
		local c = at * CFrame.new(0, size.Y / 2, 0)
		box("Crate", size - Vector3.new(0.3, 0.3, 0.3), c, colors.Crate, Enum.Material.Metal)
		local hx, hy, hz = size.X / 2 - 0.2, size.Y / 2 - 0.2, size.Z / 2 - 0.2
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				box("CrateEdge", Vector3.new(0.4, size.Y, 0.4), c * CFrame.new(sx * hx, 0, sz * hz), colors.CrateEdge, Enum.Material.Metal)
			end
		end
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				box("CrateEdge", Vector3.new(size.X, 0.4, 0.4), c * CFrame.new(0, sy * hy, sz * hz), colors.CrateEdge, Enum.Material.Metal)
			end
			for _, sx in { -1, 1 } do
				box("CrateEdge", Vector3.new(0.4, 0.4, size.Z), c * CFrame.new(sx * hx, sy * hy, 0), colors.CrateEdge, Enum.Material.Metal)
			end
		end
		local w, h = size.X - 0.8, size.Y - 0.8
		for _, s in { -1, 1 } do
			box("CrateBrace", Vector3.new(math.sqrt(w * w + h * h), 0.35, 0.2), c * CFrame.new(0, 0, size.Z / 2 - 0.05) * CFrame.Angles(0, 0, s * math.atan2(h, w)), colors.CrateEdge, Enum.Material.Metal)
			glow("CrateGlow", Vector3.new(0.2, size.Y - 0.9, 0.2), c * CFrame.new(s * (hx - 0.4), 0, size.Z / 2 + 0.05), neon)
		end
	end
	crate(CFrame.new(-inner + 5, 0, zBack + 3.4), Vector3.new(7, 5, 5))
	crate(CFrame.new(inner - 5, 0, zBack + 3.4), Vector3.new(7, 5, 5))
	-- Turned to face the middle of the room (its front, +Z, swung round to -X).
	crate(CFrame.new(halfW - pillar - 3.2, 0, zBack + 11) * CFrame.Angles(0, math.rad(-90), 0), Vector3.new(5, 4, 4.5))

	-- === The lit frame in the ceiling ===
	local ceiling = accent:Lerp(WHITE, cfg.CeilingWhiten)
	local cx = halfW - cfg.CeilingInset
	local cz0, cz1 = zBack + cfg.CeilingInset * 0.6, zFront - cfg.CeilingInset
	local cy = height - 0.12
	for _, z in { cz0, cz1 } do
		glow("CeilingFrame", Vector3.new(cx * 2 + 0.8, 0.25, 0.8), CFrame.new(0, cy, z), ceiling)
	end
	for _, s in { -1, 1 } do
		glow("CeilingFrame", Vector3.new(0.8, 0.25, cz1 - cz0), CFrame.new(s * cx, cy, (cz0 + cz1) / 2), ceiling)
	end

	-- === The ring on the floor round the pair ===
	local ring = cfg.Ring
	local ringColor = neon:Lerp(WHITE, ring.Whiten)
	local chord = 2 * ringRadius * math.sin(math.pi / ring.Segments)
	for i = 1, ring.Segments do
		local a = (i / ring.Segments) * math.pi * 2
		local at = Vector3.new(math.cos(a) * ringRadius, 0.05, math.sin(a) * ringRadius)
		glow("Ring", Vector3.new(ring.Width, 0.1, chord + 0.06), CFrame.lookAt(at, at + Vector3.new(-math.sin(a), 0, math.cos(a))), ringColor)
	end
	for i = 1, 4 do
		local a = (i - 0.5) / 4 * math.pi * 2
		spill(Vector3.new(math.cos(a) * ringRadius, 0.6, math.sin(a) * ringRadius), 0.6)
	end

	--[[ === The reflection: every visible part but the floor, flipped through it ===
		Not the ceiling frame. Its far edge reflects right along the bottom of the resting shot, a hard
		white bar across the foreground that read as a mistake rather than as a shine. ]]
	local unreflected = { Floor = true, CeilingFrame = true }
	local reflection = Instance.new("Model")
	reflection.Name = "Reflection"
	for _, child in model:GetChildren() do
		if not (child:IsA("BasePart") and not unreflected[child.Name]) then
			continue
		end
		local gui = child:FindFirstChildOfClass("SurfaceGui")
		if gui then
			--[[ A glow slab is invisible, but its picture is not. Flipped like a box it would keep its
				gradient the right way up, so it is also turned half round its own facing, which turns
				the picture upside down (and across, which no glow here can show). ]]
			local copy = child:Clone()
			copy.CFrame = flip(child.CFrame, floorY) * CFrame.fromAxisAngle(Vector3.FromNormalId(gui.Face), math.pi)
			copy.Parent = reflection
		elseif child.Transparency < 1 then
			local copy = child:Clone()
			copy.CFrame = flip(child.CFrame, floorY)
			copy.Parent = reflection
			local lit = neonLit[child]
			if lit then
				neonLit[copy] = lit
			end
		end
	end
	reflection.Parent = model

	-- Everything that lights up goes on the dial: the neon (and its reflections), then the glows.
	for p, entry in neonLit do
		table.insert(room.dials, neonDial(p, entry.lit, entry.floor))
	end
	for _, d in model:GetDescendants() do
		if d:IsA("SurfaceGui") and d.Name == "Glow" then
			local fills = {}
			for _, fill in d:GetChildren() do
				if fill:IsA("Frame") then
					table.insert(fills, fill)
				end
			end
			table.insert(room.dials, {
				at = (d.Parent :: BasePart).Position,
				floor = d:GetAttribute("Standby") or 0,
				set = function(power)
					for _, fill in fills do
						fill.BackgroundTransparency = 1 - (1 - (fill:GetAttribute("Base") or 0)) * power
					end
				end,
			})
		end
	end

	model.Parent = parent
	return room
end

--[[ Everything on the dial at `power`: 0 is the hold (grey tubes, the downlights at `Standby`, no
	rarity colour anywhere), 1 the rarity colour at full. ]]
function ShowcaseGarage.setPower(room: Room, power: number)
	for _, dial in room.dials do
		dial.set(dial.floor + (1 - dial.floor) * power)
	end
end

--[[ Switch the room on from `from` outward: each strip and light comes up over `PowerFade` once a
	ring growing at `PowerSpeed` reaches it. Runs on its own frame loop and stops itself when
	everything is lit or the room has been taken down. ]]
function ShowcaseGarage.powerOn(room: Room, from: Vector3)
	local cfg = ShowcaseConfig.Garage
	local steps: { { at: number, set: (number) -> () } } = {}
	for _, dial in room.dials do
		table.insert(steps, {
			at = (dial.at - from).Magnitude / cfg.PowerSpeed,
			set = function(p)
				dial.set(dial.floor + (1 - dial.floor) * p)
			end,
		})
	end
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		if not room.model.Parent then
			connection:Disconnect()
			return
		end
		local t = os.clock() - started
		local pending = false
		for _, step in steps do
			local p = math.clamp((t - step.at) / cfg.PowerFade, 0, 1)
			if p < 1 then
				pending = true
			end
			if p > 0 then
				step.set(1 - (1 - p) * (1 - p))
			end
		end
		if not pending then
			connection:Disconnect()
		end
	end)
end

--[[ `pivot` rolled over onto its back about its own forward line on the floor at `floorY`: where a
	model's reflection stands. Expects a pivot turned about Y only, which is how the stage stands
	everything. ]]
function ShowcaseGarage.rolled(pivot: CFrame, floorY: number): CFrame
	local foot = CFrame.new(pivot.X, floorY, pivot.Z) * pivot.Rotation
	return foot * CFrame.Angles(0, 0, math.pi) * foot:ToObjectSpace(pivot)
end

--[[ A reflection of `model` under the floor at `floorY` (header note 2), unparented. Lights, particles,
	trails, beams, highlights, billboards and sounds are taken off it: a reflection that lit the room
	or played a sound would be a second car, not a picture of the first. ]]
function ShowcaseGarage.reflect(model: Model, floorY: number): Model
	local twin = model:Clone()
	for _, d in twin:GetDescendants() do
		if
			d:IsA("Light")
			or d:IsA("ParticleEmitter")
			or d:IsA("Beam")
			or d:IsA("Trail")
			or d:IsA("Fire")
			or d:IsA("Smoke")
			or d:IsA("Sparkles")
			or d:IsA("Highlight")
			or d:IsA("BillboardGui")
			or d:IsA("Sound")
		then
			d:Destroy()
		end
	end
	twin.Name = model.Name .. "Reflection"
	twin:PivotTo(ShowcaseGarage.rolled(model:GetPivot(), floorY))
	return twin
end

--[[ Take the world's light out of the room for as long as `room` stands (`ShowcaseConfig.Garage.World`
	has which settings and why). Returns the function that ends it; ending it twice is harmless.

	THE STAGE'S VALUES EXIST FOR THE DRAW AND NOWHERE ELSE. They go in at the very end of the frame's
	render step (`Last`, after every camera and every other binding) and the world's own values go
	straight back at the start of the next simulation step, before any other script runs. Two reasons
	it is done that way rather than set once and put back at the end:
	  - `DayNightController` writes the Lighting half eight times a second. Written once, the sky
	    would be back within an eighth of a second; written every frame, the day/night cycle and the
	    stage would be two writers on one property.
	  - `WeatherController` SAVES the Atmosphere when a run starts and puts back what it saved when
	    the run ends, and a run starting is exactly what aborts this cutscene. Whichever of the two
	    heard `RaceStart` first, a value held across frames could be the one it saved, leaving the
	    world without its haze for the rest of the session. Swapped back every frame, nothing outside
	    the render ever reads anything but the world's own value.
	Whatever another script writes in between is what goes back, so the cycle carries on underneath. ]]
local HOLD_STEP = "ShowcaseGarageWorld"
function ShowcaseGarage.holdWorld(room: Room): () -> ()
	local spec = ShowcaseConfig.Garage.World
	if not spec then
		return function() end
	end
	local Lighting = game:GetService("Lighting")
	local swaps: { { inst: Instance, prop: string, ours: any, theirs: any } } = {}
	for prop, value in spec.Lighting or {} do
		table.insert(swaps, { inst = Lighting, prop = prop, ours = value, theirs = nil })
	end
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		for prop, value in spec.Atmosphere or {} do
			table.insert(swaps, { inst = atmosphere, prop = prop, ours = value, theirs = nil })
		end
	end

	local swapped = false
	local function swapOut()
		if not swapped then
			return
		end
		swapped = false
		for _, s in swaps do
			if s.theirs ~= nil then
				(s.inst :: any)[s.prop] = s.theirs
			end
		end
	end
	local stopped = false
	local after: RBXScriptConnection
	local function stop()
		if stopped then
			return
		end
		stopped = true
		RunService:UnbindFromRenderStep(HOLD_STEP)
		after:Disconnect()
		swapOut()
	end
	RunService:BindToRenderStep(HOLD_STEP, Enum.RenderPriority.Last.Value, function()
		-- A stage taken down without this being ended must not keep repainting the world.
		if not room.model.Parent then
			stop()
			return
		end
		if swapped then
			return
		end
		for _, s in swaps do
			s.theirs = (s.inst :: any)[s.prop]
			;(s.inst :: any)[s.prop] = s.ours
		end
		swapped = true
	end)
	after = RunService.PreSimulation:Connect(swapOut)
	return stop
end

return ShowcaseGarage
