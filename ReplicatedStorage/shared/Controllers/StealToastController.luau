--[[
	StealToastController  (client)
	-------------------------------
	The STOLEN! toast: on the frame a steal's handoff lands, "STOLEN!" over the car's rarity and its name,
	in the rarity's colour, sized and held by how rare it is. `StealJuiceConfig.Toast` has the design and
	the numbers; `StealController._notifyStolen` publishes `CarStolen` (body, paint, mutation, tier)
	off the car's own stamps.

	ONE TOAST, REPLACED RATHER THAN QUEUED. Steals can come faster than a Supercar's hold (1.6s apart is
	legal, `StealService`), and a queue would still be announcing the car before last while the player
	drives the next one. A new steal restarts the toast on the new car.

	Its ScreenGui only exists during races in practice, and it clears on `RaceEnd` so a toast raised on
	the last steal of a run never survives into the results screen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local StealJuiceConfig = require(ReplicatedStorage.shared.Configs.StealJuiceConfig)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local NoticeLane = require(ReplicatedStorage.shared.Modules.NoticeLane)

local StealToastController = Shard.new("StealToastController")

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Heavy)
local STROKE = Color3.fromRGB(10, 10, 18)
--- Over the driving HUD (the speed-trap readout is 900), under the race fade (1000).
local DISPLAY_ORDER = 905
--- The rarest band `CarRarity` colours; band 1..this lerps the toast's scale and hold.
local TOP_BAND = #CarRarity.Colours

local function line(parent: Instance, name: string, y: number, height: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, y)
	label.Size = UDim2.new(1, 0, 0, height)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.TextScaled = true
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = STROKE
	stroke.Thickness = 3
	stroke.Parent = label
	return label
end

function StealToastController._build(self)
	local cfg = StealJuiceConfig.Toast
	local gui = Instance.new("ScreenGui")
	gui.Name = "StealToast"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = DISPLAY_ORDER
	gui.Enabled = false

	local root = Instance.new("Frame")
	root.Name = "Toast"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(cfg.Position.X, cfg.Position.Y)
	root.Size = UDim2.fromOffset(cfg.Width, cfg.TitleHeight + cfg.LineHeight * 2)
	root.BackgroundTransparency = 1
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = root

	local title = line(root, "Title", 0, cfg.TitleHeight)
	title.TextColor3 = cfg.TitleColor
	title.Text = cfg.Title
	local rarity = line(root, "Rarity", cfg.TitleHeight, cfg.LineHeight)
	local name = line(root, "Name", cfg.TitleHeight + cfg.LineHeight, cfg.LineHeight)
	name.TextColor3 = Color3.new(1, 1, 1)

	--[[ The rarity flash's four edges (`StealJuiceConfig.RarityFlash`): a frame along each side with a
		gradient running clear toward the middle, so the colour washes in from the rim. ]]
	local flash = StealJuiceConfig.RarityFlash
	local edges = {}
	for _, side in { { "Left", 0, 0, flash.Width, 1, 0 }, { "Right", 1 - flash.Width, 0, flash.Width, 1, 180 }, { "Top", 0, 0, 1, flash.Width, 90 }, { "Bottom", 0, 1 - flash.Width, 1, flash.Width, 270 } } do
		local edge = Instance.new("Frame")
		edge.Name = "Flash" .. side[1]
		edge.Position = UDim2.fromScale(side[2], side[3])
		edge.Size = UDim2.fromScale(side[4], side[5])
		edge.BorderSizePixel = 0
		edge.BackgroundTransparency = 1
		edge.ZIndex = 0
		edge.Parent = gui
		local ramp = Instance.new("UIGradient")
		ramp.Rotation = side[6]
		ramp.Transparency = NumberSequence.new(0, 1)
		ramp.Parent = edge
		table.insert(edges, edge)
	end
	self._edges = edges

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self._gui, self._scale, self._root = gui, scale, root
	self._labels = { title, rarity, name }
	self._rarity, self._name = rarity, name
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		local maxScale = self:_fit()
		self._scale.Scale = math.min(self._scale.Scale, maxScale)
	end)
end

function StealToastController._fit(self): number
	local cfg = StealJuiceConfig.Toast
	local compact = NoticeLane.compact()
	local viewport = workspace.CurrentCamera.ViewportSize
	local narrowLandscape = compact and viewport.X < 700 and viewport.Y <= viewport.X
	local width = if narrowLandscape then viewport.X * 0.45 else if compact then math.min(280, viewport.X - 24) else cfg.Width
	local titleHeight, lineHeight = if compact then 26 else cfg.TitleHeight, if compact then 18 else cfg.LineHeight
	self._root.Size = UDim2.fromOffset(width, titleHeight + lineHeight * 2)
	-- Keep the short receipt beside the road and below the rare-car card, clear of the chase gauge (2026-10-12).
	self._root.AnchorPoint = if compact then Vector2.new(1, 0) else Vector2.new(0.5, 0.5)
	self._root.Position = if compact then UDim2.new(1, -12, 0, if viewport.X < 700 then 182 else 140)
		else UDim2.fromScale(cfg.Position.X, cfg.Position.Y)
	if narrowLandscape then
		self._root.AnchorPoint = Vector2.new(0, 0)
		self._root.Position = UDim2.fromOffset(12, 112)
	end
	for index, label in self._labels do
		local y = if index == 1 then 0 else titleHeight + (index - 2) * lineHeight
		label.Position = UDim2.new(0.5, 0, 0, y)
		label.Size = UDim2.new(1, 0, 0, if index == 1 then titleHeight else lineHeight)
	end
	return if compact then 1 else cfg.Scale[2]
end

--- Lerp one { Beater, Supercar } pair by band.
local function byBand(pair: { number }, band: number): number
	local t = math.clamp((band - 1) / math.max(TOP_BAND - 1, 1), 0, 1)
	return pair[1] + (pair[2] - pair[1]) * t
end

--- The rarity flash (`StealJuiceConfig.RarityFlash`): the edges wash in `colour` and fade out.
function StealToastController._flash(self, colour: Color3, band: number)
	local cfg = StealJuiceConfig.RarityFlash
	if not (cfg.Enabled and band >= cfg.MinBand and self._edges) then
		return
	end
	local fade = TweenInfo.new(cfg.Seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, edge in self._edges do
		edge.BackgroundColor3 = colour
		edge.BackgroundTransparency = cfg.Strength
		TweenService:Create(edge, fade, { BackgroundTransparency = 1 }):Play()
	end
end

--- The rarity burst (`StealJuiceConfig.RarityBurst`): one spray of sparkles off the player's car.
function StealToastController._burst(self, colour: Color3, band: number)
	local cfg = StealJuiceConfig.RarityBurst
	if not (cfg and cfg.Enabled and band >= cfg.MinBand) then
		return
	end
	local road = Shard.get("RoadController")
	local car = road and road:getCar()
	local root = car and car.PrimaryPart
	if not root then
		return
	end
	-- Epic -> Legendary, so the top band gets the top of each range.
	local t = math.clamp((band - cfg.MinBand) / math.max(TOP_BAND - cfg.MinBand, 1), 0, 1)
	local attachment = Instance.new("Attachment")
	attachment.Name = "RarityBurst"
	attachment.Position = Vector3.new(0, 2, 0)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(colour:Lerp(Color3.new(1, 1, 1), 0.35), colour)
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(cfg.Lifetime * 0.6, cfg.Lifetime)
	local speed = cfg.Speed[1] + (cfg.Speed[2] - cfg.Speed[1]) * t
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 3
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, cfg.Size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Rate = 0
	emitter.Parent = attachment
	attachment.Parent = root
	emitter:Emit(math.round(cfg.Count[1] + (cfg.Count[2] - cfg.Count[1]) * t))
	task.delay(cfg.Lifetime + 0.5, function()
		attachment:Destroy()
	end)
end

function StealToastController._show(self, body: unknown, paint: unknown, mutation: unknown)
	if type(body) ~= "string" or not self._gui then
		return
	end
	local cfg = StealJuiceConfig.Toast
	local word, band = CarRarity.of(body)
	local colour = CarRarity.colourOf(band)
	self:_flash(colour, band)
	self:_burst(colour, band)
	local tag = if type(mutation) == "string" then string.upper(WeatherConfig.nameOf(mutation)) .. " " else ""
	self._rarity.Text = tag .. string.upper(word)
	self._rarity.TextColor3 = colour
	self._name.Text = GarageConfig.carName(body, if type(paint) == "number" then paint else nil)

	self._token = (self._token or 0) + 1
	local token = self._token
	for _, label in self._labels do
		label.TextTransparency = 0
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0
		end
	end
	self._gui.Enabled = true
	local maxScale = self:_fit()
	self._scale.Scale = 0.4
	TweenService:Create(
		self._scale,
		TweenInfo.new(cfg.PopTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = math.min(byBand(cfg.Scale, band), maxScale) }
	):Play()

	task.delay(cfg.PopTime + byBand(cfg.Hold, band), function()
		if self._token ~= token then
			return -- a newer steal took the toast over
		end
		local fade = TweenInfo.new(cfg.FadeTime)
		for _, label in self._labels do
			TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
			end
		end
		task.delay(cfg.FadeTime, function()
			if self._token == token then
				self._gui.Enabled = false
			end
		end)
	end)
end

function StealToastController._clear(self)
	self._token = (self._token or 0) + 1
	if self._gui then
		self._gui.Enabled = false
	end
end

StealToastController:withRemoteEvents({
	{
		RaceEnd = function()
			StealToastController:_clear()
		end,
	},
})

StealToastController:withLifecycle({
	init = function(self)
		self._token = 0
	end,

	start = function(self)
		if not StealJuiceConfig.Toast.Enabled then
			return
		end
		self:_build()
		Dispatcher:Subscribe("CarStolen", function(body, paint, mutation)
			self:_show(body, paint, mutation)
		end)
	end,
})

return StealToastController
