--[[ CollectorHudController — the collector's HUD, laid out after the reference
	==========================================================================

	  bottom-left   ⚡ STEAL POWER pill (above the authored cash readout) with a green +, which opens
	                the power upgrade card: current → next, the car the next level unlocks, price, BUY.
	  top-centre    the ZONE STRIP: one tile per zone in its colour, dimmed until your power reaches
	                it, a marker for where you are and how far you are from the start line.
	  top-left      "IT'S YOURS!" toast for each steal and the N SECURED tray of this trip's cars,
	                cleared when you walk back into the hub.
	  top-centre    ANNOUNCEMENTS (resets, secret spawns, rushes, secret steals), stacked under the strip.
	  bottom-right  the countdown to the next reset, and the rush timer when one is on.
	  bottom-centre one-line hints (from `RoamingCarController` via Dispatcher "CollectorHint").

	Built in code with the house font and kit colours (`ArcadeKit`), in its own ScreenGui, so it
	never fights the Studio-authored MainUIV2 for layout and `InterfaceController` hides it with the
	rest. Purchases go through the existing `RequestUpgrade` remote — the server prices and checks
	everything; this card only shows what the config says the server will charge. ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local CollectorConfig = require(ReplicatedStorage.shared.Configs.CollectorConfig)
local UpgradeConfig = require(ReplicatedStorage.shared.Configs.UpgradeConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local CarNameConfig = require(ReplicatedStorage.shared.Configs.CarNameConfig)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)
local Feedback = require(ReplicatedStorage.shared.Modules.GameplayFeedback)

local FONT = Font.fromEnum(Enum.Font.FredokaOne)
local NAVY = Color3.fromRGB(2, 30, 56)
local GOLD = Color3.fromRGB(255, 205, 50)
local GREEN = Color3.fromRGB(70, 200, 60)

local Controller = Shard.new("CollectorHudController"):withDependencies({ "RoamingCarController" })

Controller:withRemoteEvents({
	"RequestUpgrade",
	{
		[CollectorConfig.Remotes.Announce] = function(payload)
			Controller:_onAnnounce(payload)
		end,
		-- The SECURED tray is per run on the road: a new run starts it empty.
		RaceStart = function()
			if Controller._secured and #Controller._secured > 0 then
				table.clear(Controller._secured)
				Controller:_refreshTray()
			end
		end,
	},
})

-- === Small builders ==========================================================

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(radius or 0.25, 0)
	c.Parent = parent
end

local function stroke(parent: Instance, thickness: number, color: Color3?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or NAVY
	s.ApplyStrokeMode = if parent:IsA("TextLabel") or parent:IsA("TextButton") then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function text(parent: Instance, value: string, color: Color3?, props: { [string]: any }?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.FontFace = FONT
	t.TextScaled = true
	t.Text = value
	t.TextColor3 = color or Color3.new(1, 1, 1)
	t.Size = UDim2.fromScale(1, 1)
	for k, v in props or {} do
		(t :: any)[k] = v
	end
	local s = Instance.new("UIStroke")
	s.Thickness = 2
	s.Color = NAVY
	s.Parent = t
	t.Parent = parent
	return t
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

local function button(parent: Instance, label: string, color: Color3, props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BackgroundColor3 = color
	b.FontFace = FONT
	b.TextScaled = true
	b.Text = label
	b.TextColor3 = Color3.new(1, 1, 1)
	for k, v in props do
		(b :: any)[k] = v
	end
	corner(b, 0.3)
	stroke(b, 3)
	local s = Instance.new("UIStroke")
	s.Thickness = 2
	s.Color = NAVY
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = b
	b.Parent = parent
	return b
end

local function nameOf(body: string): string
	return CarNameConfig.nameOf(body) or body
end

local function zoneName(zone: number): string
	return string.upper(WorldConfig.displayName(zone))
end

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return if seconds >= 60 then string.format("%dm %02ds", seconds // 60, seconds % 60) else string.format("%ds", seconds)
end

-- === Power ===================================================================

function Controller._level(self): number
	local upgrades = UpgradeConfig.decode(self._player:GetAttribute(UpgradeConfig.Attribute))
	return UpgradeConfig.levelOf(upgrades, CollectorConfig.Trainer.UpgradeKey)
end

function Controller._buildPower(self)
	local pill = frame(self._gui, {
		Name = "Power",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.013, 0, 0.86, 0),
		Size = UDim2.fromScale(0.16, 0.065),
		BackgroundColor3 = NAVY,
		BackgroundTransparency = 0.25,
	})
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 3.6
	aspect.Parent = pill
	corner(pill, 0.35)
	stroke(pill, 2.5, GOLD)
	self._powerText = text(pill, "⚡ 10", GOLD, {
		Position = UDim2.fromScale(0.05, 0.1),
		Size = UDim2.fromScale(0.68, 0.8),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local plus = button(pill, "+", GREEN, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.97, 0.5),
		Size = UDim2.fromScale(0.24, 0.84),
	})
	plus.Activated:Connect(function()
		self:_togglePanel()
	end)
end

function Controller._buildPanel(self)
	local panel = frame(self._gui, {
		Name = "PowerPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.34, 0.36),
		BackgroundColor3 = Color3.fromRGB(16, 70, 140),
		Visible = false,
	})
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.45
	aspect.Parent = panel
	corner(panel, 0.08)
	stroke(panel, 4, NAVY)
	text(panel, "⚡ KIDDIE RIDE", GOLD, { Position = UDim2.fromScale(0.05, 0.04), Size = UDim2.fromScale(0.9, 0.15) })
	self._panelFrom = text(panel, "", Color3.new(1, 1, 1), { Position = UDim2.fromScale(0.05, 0.22), Size = UDim2.fromScale(0.9, 0.16) })
	self._panelUnlock = text(panel, "", Color3.new(1, 1, 1), { Position = UDim2.fromScale(0.05, 0.4), Size = UDim2.fromScale(0.9, 0.11) })
	self._panelZone = text(panel, "", GOLD, { Position = UDim2.fromScale(0.05, 0.52), Size = UDim2.fromScale(0.9, 0.09) })
	local buy = button(panel, "BUY", GREEN, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.66),
		Size = UDim2.fromScale(0.62, 0.2),
	})
	buy.Activated:Connect(function()
		self:getRemoteEvent("RequestUpgrade"):Fire(CollectorConfig.Trainer.UpgradeKey)
	end)
	self._buy = buy
	local close = button(panel, "X", Color3.fromRGB(230, 60, 60), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.97, 0.03),
		Size = UDim2.fromScale(0.12, 0.17),
	})
	close.Activated:Connect(function()
		panel.Visible = false
	end)
	self._panel = panel
end

function Controller._togglePanel(self)
	self._panel.Visible = not self._panel.Visible
	self:_refreshPower()
end

--- The cheapest-tier body a level unlocks, for "Unlocks: <car>".
local function bodyOfTier(tier: number): string?
	local world = (tier - 1) // 10 + 1
	local entry = WorldConfig.Worlds[world]
	return entry and entry.Cars[(tier - 1) % 10 + 1]
end

function Controller._refreshPower(self)
	local level = self:_level()
	local power = CollectorConfig.powerOf(self._player)
	self._powerText.Text = "⚡ " .. CollectorConfig.formatPower(power)
	if not self._panel.Visible then
		return
	end
	-- The next car your ⚡ has not reached yet: what training is for.
	local nextTier
	for tier = 1, 50 do
		if CollectorConfig.requiredFor(tier) > power then
			nextTier = tier
			break
		end
	end
	local body = nextTier and bodyOfTier(nextTier)
	self._panelUnlock.Text = if body
		then string.format("Next: %s at ⚡%s", nameOf(body), CollectorConfig.formatPower(CollectorConfig.requiredFor(nextTier)))
		else "Every car in the game is yours to steal"
	self._panelZone.Text = "Sit on the kiddie ride at your plot to train"
	local rate = CollectorConfig.rateAt(level)
	local cost = UpgradeConfig.costOf(CollectorConfig.Trainer.UpgradeKey, level)
	if not cost then
		self._panelFrom.Text = string.format("+%.1f ⚡/s  MAXED", rate)
		self._buy.Visible = false
		return
	end
	self._panelFrom.Text = string.format("+%.1f ⚡/s  →  +%.1f ⚡/s", rate, CollectorConfig.rateAt(level + 1))
	self._buy.Visible = true
	local cash = self._player:GetAttribute(GarageConfig.CashAttribute) or 0
	self._buy.Text = GarageConfig.formatCash(cost)
	self._buy.BackgroundColor3 = if cash >= cost then GREEN else Color3.fromRGB(120, 130, 150)
end

-- === Zone strip ==============================================================

function Controller._buildStrip(self)
	local strip = frame(self._gui, {
		Name = "ZoneStrip",
		AnchorPoint = Vector2.new(0.5, 0),
		-- Pixels, under the offline line (OfflineConfig.Label: Top 6 + Height 30), which owns top-centre.
		Position = UDim2.new(0.5, 0, 0, 42),
		Size = UDim2.fromScale(0.36, 0.05),
		BackgroundTransparency = 1,
	})
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 10
	aspect.Parent = strip
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0.006, 0)
	layout.Parent = strip
	self._tiles = {}
	local n = #CollectorConfig.Zones
	for zone, spec in CollectorConfig.Zones do
		local tile = frame(strip, {
			Name = "Zone" .. zone,
			Size = UDim2.fromScale(1 / n - 0.006, 1),
			BackgroundColor3 = spec.Color,
			LayoutOrder = zone,
		})
		corner(tile, 0.2)
		stroke(tile, 2)
		text(tile, WorldConfig.shortName(zone), Color3.new(1, 1, 1), { Size = UDim2.fromScale(0.92, 0.8), Position = UDim2.fromScale(0.04, 0.1) })
		self._tiles[zone] = tile
	end
	local marker = frame(self._gui, {
		Name = "ZoneMarker",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.05, 0.03),
		BackgroundTransparency = 1,
	})
	self._markerText = text(marker, "", Color3.new(1, 1, 1))
	self._strip, self._marker = strip, marker
end

function Controller._refreshStrip(self)
	if not self._strip then
		return -- the corridor strip is the Roaming mode's; the road has its own progress bar
	end
	local power = CollectorConfig.powerOf(self._player)
	for zone, tile in self._tiles do
		tile.BackgroundTransparency = if power >= CollectorConfig.zoneMinimum(zone) then 0 else 0.65
	end
	local character = self._player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local c = CollectorConfig.Corridor
	if not (root and root:IsA("BasePart")) then
		return
	end
	local into = c.StartZ - root.Position.Z
	local inCorridor = into >= 0 and math.abs(root.Position.X - c.CenterX) < c.HalfWidth + 60
	self._marker.Visible = inCorridor
	if inCorridor then
		local share = math.clamp(into / (c.ZoneLength * #CollectorConfig.Zones), 0, 1)
		local abs = self._strip.AbsolutePosition
		local size = self._strip.AbsoluteSize
		local guiSize = self._gui.AbsoluteSize
		self._marker.Position = UDim2.fromScale(
			(abs.X + size.X * share) / math.max(guiSize.X, 1),
			(abs.Y + size.Y) / math.max(guiSize.Y, 1)
		)
		self._markerText.Text = string.format("▲ %d m", math.floor(into / CollectorConfig.StudsPerMeter))
	end
	-- The SECURED tray is per trip: walking back into the hub clears it.
	if into < -20 and #self._secured > 0 then
		table.clear(self._secured)
		self:_refreshTray()
	end
end

-- === Toast + SECURED tray ====================================================

function Controller._buildToast(self)
	local toast = frame(self._gui, {
		Name = "Toast",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(-0.4, 0.2),
		Size = UDim2.fromScale(0.28, 0.12),
		BackgroundColor3 = Color3.fromRGB(32, 120, 60),
	})
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 3.4
	aspect.Parent = toast
	corner(toast, 0.2)
	stroke(toast, 4, Color3.fromRGB(140, 255, 150))
	local holder = frame(toast, {
		Position = UDim2.fromScale(0.03, 0.08),
		Size = UDim2.fromScale(0.3, 0.84),
		BackgroundTransparency = 1,
	})
	self._toastViewport = CarViewport.new(holder, "Car")
	text(toast, "IT'S YOURS!", Color3.new(1, 1, 1), { Position = UDim2.fromScale(0.36, 0.06), Size = UDim2.fromScale(0.6, 0.42) })
	self._toastName = text(toast, "", GOLD, { Position = UDim2.fromScale(0.36, 0.5), Size = UDim2.fromScale(0.6, 0.28), RichText = true })
	self._toastSub = text(toast, "Keep going!", Color3.new(1, 1, 1), { Position = UDim2.fromScale(0.36, 0.78), Size = UDim2.fromScale(0.6, 0.18) })
	self._toast = toast

	local tray = frame(self._gui, {
		Name = "Secured",
		Position = UDim2.fromScale(0.013, 0.34),
		Size = UDim2.fromScale(0.22, 0.12),
		BackgroundTransparency = 1,
		Visible = false,
	})
	self._trayTitle = text(tray, "", Color3.fromRGB(120, 255, 130), { Size = UDim2.fromScale(1, 0.28), TextXAlignment = Enum.TextXAlignment.Left })
	local list = frame(tray, { Position = UDim2.fromScale(0, 0.32), Size = UDim2.fromScale(1, 0.68), BackgroundTransparency = 1 })
	local grid = Instance.new("UIListLayout")
	grid.FillDirection = Enum.FillDirection.Horizontal
	grid.Padding = UDim.new(0.02, 0)
	grid.Parent = list
	self._tray, self._trayList = tray, list
	self._secured = {}
end

function Controller._refreshTray(self)
	for _, child in self._trayList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local count = #self._secured
	self._tray.Visible = count > 0
	self._trayTitle.Text = string.format("%d SECURED", count)
	local shown = CollectorConfig.Toast.TrayMax
	for i = math.max(1, count - shown + 1), count do
		local entry = self._secured[i]
		local _, colour = CarRarity.labelOf(entry.body)
		local chip = frame(self._trayList, {
			Size = UDim2.fromScale(1 / shown - 0.02, 1),
			BackgroundColor3 = colour,
			LayoutOrder = i,
		})
		corner(chip, 0.2)
		stroke(chip, 2)
		local holder = frame(chip, { Size = UDim2.fromScale(1, 0.72), BackgroundTransparency = 1 })
		local viewport = CarViewport.new(holder, "Car")
		CarViewport.set(viewport, entry.body, { paint = entry.paint, mutation = entry.mutation })
		text(chip, nameOf(entry.body), Color3.new(1, 1, 1), { Position = UDim2.fromScale(0, 0.7), Size = UDim2.fromScale(1, 0.3) })
	end
end

function Controller._onCaptured(self, result: { [string]: any })
	local body = result.body
	local rarity, colour = CarRarity.labelOf(body)
	local mutation = WeatherConfig.mutationOf(result.mutation)
	local prefix = if result.secret then "SECRET " elseif mutation then mutation.Name .. " " else ""
	self._toastName.Text = string.format('%s<font color="#%s">%s</font>', prefix, colour:ToHex(), nameOf(body))
	self._toastSub.Text = if result.outcome == "sold"
		then "Garage full — sold for " .. GarageConfig.formatCash(result.amount or 0)
		else string.format("%s · Keep going!", rarity)
	CarViewport.set(self._toastViewport, body, { paint = result.paint, mutation = result.mutation })

	self._toastSerial = (self._toastSerial or 0) + 1
	local serial = self._toastSerial
	local toast = self._toast
	toast.Position = UDim2.fromScale(-0.4, 0.2)
	TweenService:Create(toast, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.013, 0.2),
	}):Play()
	task.delay(CollectorConfig.Toast.Seconds, function()
		if self._toastSerial == serial then
			TweenService:Create(toast, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromScale(-0.4, 0.2),
			}):Play()
		end
	end)

	table.insert(self._secured, { body = body, paint = result.paint, mutation = result.mutation })
	self:_refreshTray()
end

-- === Announcements, countdown, hints =========================================

function Controller._buildBanner(self)
	local banner = frame(self._gui, {
		Name = "Announce",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.19),
		Size = UDim2.fromScale(0.6, 0.24),
		BackgroundTransparency = 1,
		Visible = false,
	})
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = banner
	self._banner = banner

	local timer = frame(self._gui, {
		Name = "ResetTimer",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(0.99, 0.985),
		Size = UDim2.fromScale(0.2, 0.09),
		BackgroundTransparency = 1,
	})
	self._timerText = text(timer, "", Color3.new(1, 1, 1), { Size = UDim2.fromScale(1, 0.5), Position = UDim2.fromScale(0, 0.5), TextXAlignment = Enum.TextXAlignment.Right })
	self._rushText = text(timer, "", GOLD, { Size = UDim2.fromScale(1, 0.45), TextXAlignment = Enum.TextXAlignment.Right })

	self._hint = text(self._gui, "", Color3.new(1, 1, 1), {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.8),
		Size = UDim2.fromScale(0.5, 0.04),
		Visible = false,
	})
end

function Controller._show(self, lines: { string }, seconds: number)
	local banner = self._banner
	if not banner then
		return -- an announcement that beat the HUD's build at join; nothing to show it on yet
	end
	for _, child in banner:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	for i, line in lines do
		local label = text(banner, line, Color3.new(1, 1, 1), {
			Size = UDim2.fromScale(1, if i == 1 then 0.3 else 0.17),
			RichText = true,
			LayoutOrder = i,
		})
		label.TextTransparency = 1
		TweenService:Create(label, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
	end
	banner.Visible = true
	self._bannerSerial = (self._bannerSerial or 0) + 1
	local serial = self._bannerSerial
	task.delay(seconds, function()
		if self._bannerSerial == serial then
			banner.Visible = false
		end
	end)
end

local function coloured(zone: number): string
	local spec = CollectorConfig.Zones[zone]
	return string.format('<font color="#%s">%s</font>', (spec and spec.Color or Color3.new(1, 1, 1)):ToHex(), zoneName(zone))
end

function Controller._onAnnounce(self, payload: { [string]: any })
	if type(payload) ~= "table" then
		return
	end
	if payload.kind == "reset" then
		local lines = { "ALL CARS RESET!" }
		for _, secret in payload.secrets or {} do
			table.insert(lines, string.format("A Secret %s spawned in %s!", nameOf(secret.body), coloured(secret.zone)))
		end
		self:_show(lines, 7)
		Feedback.play("EventStarted")
	elseif payload.kind == "rush" then
		self:_show({ "MUTATION RUSH!", string.format("Mutated cars are flooding %s for 60s!", coloured(payload.zone)) }, 6)
		Feedback.play("EventStarted")
	elseif payload.kind == "stolen" then
		self:_show({ string.format("%s stole the Secret %s!", tostring(payload.player), nameOf(payload.body)) }, 4)
	end
end

function Controller._refreshTimers(self)
	local t = workspace:GetServerTimeNow()
	local nextReset = workspace:GetAttribute(CollectorConfig.NextResetAttribute)
	self._timerText.Text = if type(nextReset) == "number" then "🌙 Reset in " .. clock(nextReset - t) else ""
	local rush = workspace:GetAttribute(CollectorConfig.RushAttribute)
	local zone, endsAt
	if type(rush) == "string" then
		zone, endsAt = rush:match("^(%d+)|([%d%.]+)$")
	end
	if zone and tonumber(endsAt) and tonumber(endsAt) > t then
		self._rushText.Text = string.format("RUSH: %s %s", string.upper(WorldConfig.shortName(tonumber(zone))), clock(tonumber(endsAt) - t))
	else
		self._rushText.Text = ""
	end
end

function Controller._onHint(self, message: string)
	self._hint.Text = message
	self._hint.Visible = true
	self._hintSerial = (self._hintSerial or 0) + 1
	local serial = self._hintSerial
	task.delay(3, function()
		if self._hintSerial == serial then
			self._hint.Visible = false
		end
	end)
end

-- === Lifecycle ===============================================================

Controller:withLifecycle({
	init = function(self)
		self._player = Players.LocalPlayer
	end,

	start = function(self)
		if not CollectorConfig.Enabled then
			return
		end
		local gui = Instance.new("ScreenGui")
		gui.Name = "CollectorHud"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 20
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.Parent = self._player:WaitForChild("PlayerGui")
		self._gui = gui

		self:_buildPower()
		self:_buildPanel()
		if CollectorConfig.Roaming then
			self:_buildStrip()
		end
		self:_buildToast()
		self:_buildBanner()

		local function refresh()
			self:_refreshPower()
		end
		self._player:GetAttributeChangedSignal(UpgradeConfig.Attribute):Connect(function()
			local before = self._lastLevel
			refresh()
			local level = self:_level()
			if before and level > before then
				Feedback.play("LuckRaised")
			end
			self._lastLevel = level
		end)
		self._player:GetAttributeChangedSignal(GarageConfig.CashAttribute):Connect(refresh)
		self._player:GetAttributeChangedSignal(CollectorConfig.Power.Attribute):Connect(refresh)
		self._lastLevel = self:_level()
		refresh()

		Dispatcher:Subscribe("CollectorCaptured", function(result)
			self:_onCaptured(result)
		end)
		Dispatcher:Subscribe("CollectorHint", function(message)
			self:_onHint(message)
		end)

		local acc = 0
		RunService.Heartbeat:Connect(function(dt)
			acc += dt
			if acc < 0.2 then
				return
			end
			acc = 0
			self:_refreshStrip()
			self:_refreshTimers()
		end)
	end,
})

return Controller
