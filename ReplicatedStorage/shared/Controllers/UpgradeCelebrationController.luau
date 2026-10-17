--[[
	UpgradeCelebrationController  (client)
	--------------------------------------
	Draws the upgrade moment (`UpgradeConfig.Celebrate` has the running order and why it is client-side)
	wherever `UpgradeService._celebrate` drops a marker: shockwaves across the floor, a pulse of gold
	light, a fountain and a burst of sparkles, and the UPGRADED! banner slamming in over a turning
	sunburst. Everything is local, tweened at the client's own frame rate, parented to one invisible
	holder that is destroyed when the show ends — the server's marker only says where and what level.

	The banner is the kit's own parts since 2026-10-12 (`Modules/ArcadeKit`; Dylan: "the vfx is good
	but take a look at the ui"): UPGRADED! is the kit's gold heading, whose outline is ScaledSize and
	so keeps its weight at every distance where the old 4px stroke went fat far away and thin up
	close, and the level sits on a kit day card instead of a navy pill with a gold rim. The sunburst
	is still the results screen's own (`UIAssets.Results.Sunburst`).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local UpgradeConfig = require(ReplicatedStorage.shared.Configs.UpgradeConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local ArcadeKit = require(ReplicatedStorage.shared.Modules.ArcadeKit)

local UpgradeCelebrationController = Shard.new("UpgradeCelebrationController")

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
--- Studs from the camera past which a celebration is not drawn at all: nobody across the map needs it.
local MAX_DISTANCE = 220

local function tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?, delay: number?)
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out, 0, false, delay or 0)
	local t = TweenService:Create(instance, info, goal)
	t:Play()
	return t
end

local function invisiblePart(name: string, cframe: CFrame, size: Vector3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size
	part.CFrame = cframe
	part.Parent = parent
	return part
end

local function sparkles(parent: Instance, colour: ColorSequence, size: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Color = colour
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-200, 200)
	emitter.Rate = 0
	emitter.Parent = parent
	return emitter
end

--- A flat neon ring racing out across the floor from `at`, fading as it goes.
local function shockwave(parent: Instance, at: Vector3, colour: Color3, radius: number, seconds: number, delay: number)
	task.delay(delay, function()
		if not parent.Parent then
			return
		end
		local flat = CFrame.new(at + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
		local ring = invisiblePart("Wave", flat, Vector3.new(0.1, 1, 1), parent)
		ring.Shape = Enum.PartType.Cylinder
		ring.Material = Enum.Material.Neon
		ring.Color = colour
		ring.Transparency = 0.15
		tween(ring, seconds, { Size = Vector3.new(0.1, radius * 2, radius * 2), Transparency = 1 }, Enum.EasingStyle.Quart)
	end)
end

--[[ The banner: a turning sunburst behind UPGRADED! in the kit's gold heading, slamming in (overshoot
	and a tilt that rights itself), the level on a kit card under it, then a float up and fade. On a
	BillboardGui drawn over the world, so nothing on the lot hides it. ]]
local LEVEL_W, LEVEL_H = 0.44, 0.27

local function banner(holder: BasePart, level: number)
	local cfg = UpgradeConfig.Celebrate
	local b = cfg.Banner
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(b.Width, b.Height)
	gui.StudsOffsetWorldSpace = Vector3.new(0, b.Above, 0)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	gui.MaxDistance = MAX_DISTANCE
	--- The kit's parts are layered for Sibling; a new BillboardGui defaults to Global.
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = holder

	local root = Instance.new("Frame")
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Rotation = -10
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = root

	local burst = Instance.new("ImageLabel")
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.42)
	burst.Size = UDim2.fromScale(0.95, 1.9)
	burst.BackgroundTransparency = 1
	burst.Image = UIAssets.url(UIAssets.Results.Sunburst)
	burst.ImageColor3 = cfg.Gold
	burst.ImageTransparency = 0.25
	burst.ScaleType = Enum.ScaleType.Fit
	burst.Parent = root

	local title = ArcadeKit.heading(root, 0, 0.1, 1, 0.56)
	title.Text = cfg.Title
	title.ZIndex = 3

	--- The level, on a kit card: its shape is the billboard's, cut to `LEVEL_W` x `LEVEL_H`.
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.fromScale(0.5, 0.68)
	card.Size = UDim2.fromScale(LEVEL_W, LEVEL_H)
	card.BackgroundTransparency = 1
	card.ZIndex = 3
	card.Parent = root
	--- Purple, the kit's card face furthest from the gold over it and the blue sky behind it.
	local face = ArcadeKit.card(card, { aspect = LEVEL_W * b.Width / (LEVEL_H * b.Height), sunray = false, face = ArcadeKit.Faces.Purple })
	local levelText = ArcadeKit.text(face, 0.07, 0.1, 0.86, 0.8, Color3.new(1, 1, 1), true)
	levelText.Text = "▲ " .. string.format(cfg.LevelFormat, level)

	--- In: a slam past full size with the tilt righting itself, then the settle.
	tween(scale, 0.22, { Scale = 1.25 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0.05)
	tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 0.27)
	tween(root, 0.45, { Rotation = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0.05)
	--- The sunburst turns the whole time it is up, and swells in behind the words.
	burst.Size = UDim2.fromScale(0.3, 0.6)
	tween(burst, 0.5, { Size = UDim2.fromScale(0.95, 1.9) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0.05)
	tween(burst, cfg.Seconds, { Rotation = 140 }, Enum.EasingStyle.Linear)

	--- Out: float up and fade, everything together.
	local outAt = b.Hold
	local outFor = cfg.Seconds - b.Hold
	tween(gui, outFor, { StudsOffsetWorldSpace = Vector3.new(0, b.Above + b.Rise, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, outAt)
	ArcadeKit.fade(root, outFor, outAt)
end

--- One whole celebration at `marker` (`UpgradeService._celebrate`), unless it is too far away to matter.
function UpgradeCelebrationController._play(self, marker: Instance)
	if not marker:IsA("BasePart") then
		return
	end
	local cfg = UpgradeConfig.Celebrate
	local at = marker.Position
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - at).Magnitude > MAX_DISTANCE then
		return
	end
	local level = tonumber(marker:GetAttribute("Level")) or 1

	local holder = invisiblePart("UpgradeShow", CFrame.new(at), Vector3.one * 0.2, workspace)

	--- The light: a gold pulse up and away.
	local light = Instance.new("PointLight")
	light.Color = cfg.Gold
	light.Range = cfg.Light.Range
	light.Brightness = 0
	light.Shadows = false
	light.Parent = holder
	tween(light, 0.12, { Brightness = cfg.Light.Brightness })
	tween(light, 0.9, { Brightness = 0 }, nil, nil, 0.12)

	--- The shockwaves, gold then white.
	for i = 1, cfg.Wave.Count do
		shockwave(holder, at, if i % 2 == 1 then cfg.Gold else Color3.new(1, 1, 1), cfg.Wave.Radius, cfg.Wave.Seconds, (i - 1) * cfg.Wave.Gap)
	end

	--- The fountain: straight up off a pad the size of a bay, gold to white.
	local pad = invisiblePart("Fountain", CFrame.new(at + Vector3.new(0, 0.3, 0)), Vector3.new(6, 0.2, 6), holder)
	local fountain = sparkles(pad, ColorSequence.new(cfg.Gold, Color3.new(1, 1, 1)), 1.1)
	fountain.EmissionDirection = Enum.NormalId.Top
	fountain.Speed = NumberRange.new(cfg.Fountain.Speed[1], cfg.Fountain.Speed[2])
	fountain.SpreadAngle = Vector2.new(12, 12)
	fountain.Acceleration = Vector3.new(0, -30, 0)
	fountain.Lifetime = NumberRange.new(0.9, 1.5)
	fountain.Shape = Enum.ParticleEmitterShape.Box
	fountain:Emit(cfg.Fountain.Count)

	--- The burst: a sphere of sparkles out from where the banner lands.
	local centre = Instance.new("Attachment")
	centre.Position = Vector3.new(0, cfg.Banner.Above, 0)
	centre.Parent = holder
	local burst = sparkles(centre, ColorSequence.new(cfg.Gold, cfg.Orange), 1.3)
	burst.Speed = NumberRange.new(14, 26)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Drag = 2.5
	burst.Acceleration = Vector3.new(0, -10, 0)
	burst.Lifetime = NumberRange.new(0.7, 1.3)
	burst:Emit(cfg.Burst.Count)

	banner(holder, level)

	if marker:GetAttribute("Buyer") == Players.LocalPlayer.UserId then
		local sounds = Shard.get("SoundController")
		if sounds then
			sounds:PlayNamed(cfg.Sound.Group, cfg.Sound.Name)
		end
	end

	task.delay(cfg.Seconds + 0.5, function()
		holder:Destroy()
	end)
end

UpgradeCelebrationController:withLifecycle({
	start = function(self)
		local cfg = UpgradeConfig.Celebrate
		if not cfg.Enabled then
			return
		end
		CollectionService:GetInstanceAddedSignal(cfg.Tag):Connect(function(marker)
			self:_play(marker)
		end)
	end,
})

return UpgradeCelebrationController
