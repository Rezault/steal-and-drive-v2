--[[
	RareCarBannerController  (client)
	---------------------------------
	The rare-car announcement (`TrafficConfig.Announce` has the design): a banner that drops in at the
	top of the screen when `TrafficController` puts a top-rarity or weather car on the road, holds, and
	slides back up. Only during a run; a run ending takes it down at once.

	=== THE KIT'S CARD, WITH THE CAR ON IT, 2026-10-12 ========================================
	WAS: one long sentence on the hand-made arcade strip. IS: the kit's own day card
	(`Modules/ArcadeKit`) faced in the kit gradient for the car's rarity (gold for the top band), so
	the colour says how good it is before the words are read; the car turning on the left over the
	card's sunray; `Kicker` ("LEGENDARY ON THE ROAD!") over the car's name, which is the big line.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local ArcadeKit = require(ReplicatedStorage.shared.Modules.ArcadeKit)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)
local NoticeLane = require(ReplicatedStorage.shared.Modules.NoticeLane)

local RareCarBannerController = Shard.new("RareCarBannerController")

--- Over the driving HUD and its toasts' layer, under every modal.
local DISPLAY_ORDER = 906
--- The card: a share of the screen's height, its width held to `ASPECT`.
local HEIGHT = 0.1
local ASPECT = 4
local HIDDEN_Y = -0.1
--- The car's window on the left of the card, as shares of it.
local CAR_X, CAR_W = 0.03, 0.34
local SLIDE = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local LEAVE = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

function RareCarBannerController._build(self)
	local gui = Instance.new("ScreenGui")
	gui.Name = "RareCarBanner"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = DISPLAY_ORDER
	--- The kit's parts are layered for Sibling; a new ScreenGui defaults to Global.
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Size = UDim2.fromScale(HEIGHT * ASPECT, HEIGHT)
	holder.Position = UDim2.fromScale(0.5, HIDDEN_Y)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = ASPECT
	ratio.DominantAxis = Enum.DominantAxis.Height
	ratio.Parent = holder
	local face = ArcadeKit.card(holder, { aspect = ASPECT, sunrayX = CAR_X + CAR_W / 2 })

	local view = CarViewport.new(face, "RareCar")
	view.Position = UDim2.fromScale(CAR_X, 0.04)
	view.Size = UDim2.fromScale(CAR_W, 0.92)
	view.ZIndex = 4
	local textX = CAR_X + CAR_W + 0.02
	local kicker = ArcadeKit.text(face, textX, 0.1, 0.96 - textX, 0.33, ArcadeKit.White, true)
	kicker.TextXAlignment = Enum.TextXAlignment.Left
	local name = ArcadeKit.text(face, textX, 0.42, 0.96 - textX, 0.48, ArcadeKit.White, true)
	name.TextXAlignment = Enum.TextXAlignment.Left

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self._gui, self._holder, self._face, self._view, self._kicker, self._name = gui, holder, face, view, kicker, name
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		local shown = self:_fit()
		if self._gui.Enabled then
			self._holder.Position = shown
		end
	end)
end

function RareCarBannerController._fit(self): UDim2
	if NoticeLane.compact() then
		local viewport = workspace.CurrentCamera.ViewportSize
		self._holder.AnchorPoint = Vector2.new(1, 0)
		self._holder.Size = UDim2.fromOffset(240, 60)
		return UDim2.new(1, -12, 0, if viewport.Y > viewport.X then 112 else 70)
	end
	self._holder.AnchorPoint = Vector2.new(0.5, 0.5)
	self._holder.Size = UDim2.fromScale(HEIGHT * ASPECT, HEIGHT)
	return UDim2.fromScale(0.5, TrafficConfig.Announce.Y)
end

function RareCarBannerController._show(self, body: unknown, mutation: unknown, band: unknown)
	if type(body) ~= "string" or not self._gui or not self._racing then
		return
	end
	local cfg = TrafficConfig.Announce
	local word = CarRarity.of(body)
	local lead = if type(mutation) == "string" then string.upper(WeatherConfig.nameOf(mutation)) else string.upper(word)
	self._kicker.Text = string.format(cfg.Kicker, lead)
	self._name.Text = string.upper(GarageConfig.displayName(body))
	ArcadeKit.paint(self._face, ArcadeKit.rarityFace(band))
	CarViewport.set(self._view, body, { aspect = CAR_W * ASPECT / 0.92 })

	self._token += 1
	local token = self._token
	self._gui.Enabled = true
	local shown = self:_fit()
	self._holder.Position = UDim2.fromScale(0.5, HIDDEN_Y)
	TweenService:Create(self._holder, SLIDE, { Position = shown }):Play()
	local sounds = Shard.get("SoundController")
	if sounds then
		sounds:PlayNamed(cfg.Sound.Group, cfg.Sound.Name)
	end
	task.delay(cfg.Hold, function()
		if token ~= self._token then
			return
		end
		local out = TweenService:Create(self._holder, LEAVE, { Position = UDim2.fromScale(0.5, HIDDEN_Y) })
		out.Completed:Once(function()
			if token == self._token then
				self._gui.Enabled = false
			end
		end)
		out:Play()
	end)
end

RareCarBannerController:withRemoteEvents({
	{
		RaceStart = function()
			RareCarBannerController._racing = true
		end,
		RaceEnd = function()
			RareCarBannerController._racing = false
			RareCarBannerController._token += 1
			if RareCarBannerController._gui then
				RareCarBannerController._gui.Enabled = false
			end
		end,
	},
})

RareCarBannerController:withLifecycle({
	init = function(self)
		self._racing = false
		self._token = 0
	end,

	start = function(self)
		if not TrafficConfig.Announce.Enabled then
			return
		end
		--- Built off the start path: the kit's parts arrive with the UI, after the join screen.
		task.spawn(function()
			self:_build()
		end)
		Dispatcher:Subscribe(TrafficConfig.Announce.Event, function(body, mutation, band)
			self:_show(body, mutation, band)
		end)
	end,
})

return RareCarBannerController
