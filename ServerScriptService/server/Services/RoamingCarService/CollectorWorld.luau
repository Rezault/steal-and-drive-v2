--[[ CollectorWorld — the zones' ground, start line and gates, built from `CollectorConfig` at boot
	==========================================================================================

	BUILT IN CODE, NOT AUTHORED, so the zones are reproducible from the repo and move when the
	config moves. Everything lives in one `Workspace.CollectorWorld` folder that is destroyed and
	rebuilt on every call, so running it twice is the same as running it once, and deleting the
	folder (or `CollectorConfig.Enabled = false`) leaves the authored map exactly as it was.

	The pieces, per zone: a tinted floor overlay (on top of the authored grass and road, never
	replacing them) and a gate arch over the zone's first line naming it and its cheapest car's
	Steal Power. The barriers that stop a player walking into a zone they cannot steal in yet are
	NOT here: they are per-player, so `RoamingCarController` builds them locally. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CollectorConfig = require(ReplicatedStorage.shared.Configs.CollectorConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local CollectorWorld = {}

local FONT = Font.fromEnum(Enum.Font.FredokaOne)

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = true
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Parent = parent
	return p
end

local function sign(surface: BasePart, face: Enum.NormalId, title: string, subtitle: string, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = surface

	local main = Instance.new("TextLabel")
	main.BackgroundTransparency = 1
	main.Size = UDim2.fromScale(1, 0.62)
	main.FontFace = FONT
	main.TextScaled = true
	main.Text = title
	main.TextColor3 = Color3.new(1, 1, 1)
	main.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 6
	stroke.Color = color:Lerp(Color3.new(0, 0, 0), 0.55)
	stroke.Parent = main

	local sub = main:Clone()
	sub.Position = UDim2.fromScale(0, 0.6)
	sub.Size = UDim2.fromScale(1, 0.36)
	sub.Text = subtitle
	sub.TextColor3 = Color3.fromRGB(255, 226, 90)
	sub.Parent = gui
end

function CollectorWorld.build(): Folder?
	local existing = workspace:FindFirstChild("CollectorWorld")
	if existing then
		existing:Destroy()
	end
	if not CollectorConfig.Enabled then
		return nil
	end

	local c = CollectorConfig.Corridor
	local folder = Instance.new("Folder")
	folder.Name = "CollectorWorld"

	local width = c.HalfWidth * 2 + 60
	for index, zone in CollectorConfig.Zones do
		local z0 = c.StartZ - (index - 1) * c.ZoneLength
		local floor = part(
			folder,
			"Zone" .. index .. "Floor",
			Vector3.new(width, 0.4, c.ZoneLength),
			CFrame.new(c.CenterX, c.FloorY + 0.1, z0 - c.ZoneLength / 2),
			zone.Ground,
			zone.Material
		)
		floor:SetAttribute("Zone", index)

		-- Gate arch on the zone's first line.
		local pillarX = c.HalfWidth + 18
		local height = 34
		local color = zone.Color
		for _, side in { -1, 1 } do
			part(folder, "Zone" .. index .. "Pillar", Vector3.new(6, height, 6),
				CFrame.new(c.CenterX + side * pillarX, c.FloorY + height / 2, z0), color, Enum.Material.SmoothPlastic)
		end
		local beam = part(folder, "Zone" .. index .. "Banner", Vector3.new(pillarX * 2 + 6, 12, 2),
			CFrame.new(c.CenterX, c.FloorY + height + 6, z0), color, Enum.Material.SmoothPlastic)
		beam.CanCollide = false
		local name = string.upper(WorldConfig.displayName(index))
		local need = string.format("⚡ %s+ TO STEAL", tostring(CollectorConfig.zoneMinimum(index)))
		sign(beam, Enum.NormalId.Back, name, need, color) -- faces the hub (+Z is towards it)
		sign(beam, Enum.NormalId.Front, name, need, color)
	end

	-- START ZONE line across the corridor, just inside zone 1.
	local line = part(folder, "StartLine", Vector3.new(width, 0.45, 26),
		CFrame.new(c.CenterX, c.FloorY + 0.12, c.StartZ + 14), Color3.fromRGB(240, 226, 190), Enum.Material.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 10
	gui.LightInfluence = 0
	gui.Parent = line
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.6, 1)
	label.Position = UDim2.fromScale(0.2, 0)
	label.Rotation = 180 -- read from the hub side
	label.FontFace = FONT
	label.TextScaled = true
	label.Text = "START ZONE"
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 5
	stroke.Color = Color3.fromRGB(30, 30, 40)
	stroke.Parent = label

	folder.Parent = workspace
	return folder
end

return CollectorWorld
