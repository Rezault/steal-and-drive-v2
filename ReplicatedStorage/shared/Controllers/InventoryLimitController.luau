--[[
	InventoryLimitController  (client)
	---------------------------------
	2026-10-12: A persistent backpack-capacity warning, hidden during runs. The replicated owned,
	hotbar and lot lists decide visibility, so selling or moving a car clears it without waiting
	for another award. InventoryAutoSold adds the latest paid receipt; it does not set capacity.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shard = require(ReplicatedStorage.Packages.Shard)
local ArcadeKit = require(ReplicatedStorage.shared.Modules.ArcadeKit)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local CarryConfig = require(ReplicatedStorage.shared.Configs.CarryConfig)
local InventoryConfig = require(ReplicatedStorage.shared.Configs.InventoryConfig)
local NoticeLane = require(ReplicatedStorage.shared.Modules.NoticeLane)

local InventoryLimitController = Shard.new("InventoryLimitController")

function InventoryLimitController._build(self)
	local gui = Instance.new("ScreenGui")
	gui.Name = "InventoryFull"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- The random-pull and daily-reward modals must not cover the explanation for a missing car.
	gui.DisplayOrder = 1101
	gui.Enabled = false
	--- A notice, not a modal: the hotbar's buttons stay live under it (`CarryConfig.Hotbar.NoticeAttribute`).
	gui:SetAttribute(CarryConfig.Hotbar.NoticeAttribute, true)
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.fromScale(0.5, 0.08)
	holder.Size = UDim2.fromScale(0.6, 0.16)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local bounds = Instance.new("UISizeConstraint")
	bounds.MinSize = Vector2.new(300, 105)
	bounds.MaxSize = Vector2.new(650, 145)
	bounds.Parent = holder
	local face = ArcadeKit.card(holder, { face = ArcadeKit.Faces.Gold, sunray = false })
	local title = ArcadeKit.text(face, 0.04, 0.06, 0.92, 0.25, ArcadeKit.White, true)
	local receipt = ArcadeKit.text(face, 0.04, 0.34, 0.92, 0.24, ArcadeKit.White, true)
	local hint = ArcadeKit.text(face, 0.04, 0.64, 0.92, 0.29, ArcadeKit.White, true)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self._gui, self._holder, self._bounds = gui, holder, bounds
	self._title, self._receipt, self._hint = title, receipt, hint
	self:_fit()
	table.insert(self._connections, workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		self:_fit()
		self:_refresh()
	end))
	self:_refresh()
end

function InventoryLimitController._fit(self)
	self._compact = NoticeLane.compact()
	if self._compact then
		local viewport = workspace.CurrentCamera.ViewportSize
		local width = math.clamp(viewport.X * 0.35, 240, 360)
		self._bounds.MinSize = Vector2.new(240, 72)
		self._bounds.MaxSize = Vector2.new(420, 72)
		self._holder.Size = UDim2.fromOffset(width, 72)
		local portrait = viewport.Y > viewport.X
		self._holder.AnchorPoint = Vector2.new(if portrait then 1 else 0, 0)
		self._holder.Position = if portrait then UDim2.new(1, -12, 0, 280) else UDim2.fromOffset(12, 70)
		-- A persistent status must not cover a menu's close/confirm controls (2026-10-12).
		self._gui.DisplayOrder = 20
	else
		self._holder.AnchorPoint = Vector2.new(0.5, 0)
		self._bounds.MinSize = Vector2.new(300, 105)
		self._bounds.MaxSize = Vector2.new(650, 145)
		self._holder.Size = UDim2.fromScale(0.6, 0.16)
		self._holder.Position = UDim2.fromScale(0.5, 0.08)
		self._gui.DisplayOrder = 1101
	end
end

-- Match GarageService._inventoryCount: hotbar and parked cars occupy separate spaces.
function InventoryLimitController._refresh(self)
	if not self._gui then return end
	local player = Players.LocalPlayer
	local elsewhere = {}
	for _, id in GarageConfig.split(player:GetAttribute(CarryConfig.Hotbar.Attribute)) do
		elsewhere[id] = true
	end
	for _, entry in GarageConfig.split(player:GetAttribute(GarageConfig.LotAttribute)) do
		local id = string.match(entry, "^%d+:(.+)$")
		if id then elsewhere[id] = true end
	end
	local count = 0
	for _, id in GarageConfig.split(player:GetAttribute(GarageConfig.OwnedAttribute)) do
		if not elsewhere[id] then count += 1 end
	end
	local full = count >= InventoryConfig.MaxCars
	if not full then self._sale = nil end
	self._gui.Enabled = full and not self._racing
	self._title.Text = string.format(if self._compact then "BACKPACK FULL (%d / %d)" else "BACKPACK FULL (%d CAR LIMIT)",
		InventoryConfig.MaxCars, InventoryConfig.MaxCars)
	self._receipt.Text = if self._sale then string.format("%s auto-sold for %s",
		GarageConfig.displayName(self._sale.body), GarageConfig.formatCash(self._sale.amount))
		else if self._compact then "Sell cars to free space." else "Sell cars to make room in your backpack."
	self._hint.Text = if self._compact then "New cars auto-sell while hotbar is full."
		else "New cars are auto-sold when backpack and hotbar are full."
end

function InventoryLimitController._show(self, body: string, amount: number, _limit: number)
	self._sale = if body ~= "" then { body = body, amount = amount } else nil
	-- Ownership, hotbar and bay attributes may be written together; read their settled state.
	task.defer(function() self:_refresh() end)
end

InventoryLimitController:withRemoteEvents({
	{
		RaceStart = function()
			InventoryLimitController._racing = true
			InventoryLimitController:_refresh()
		end,
		RaceEnd = function()
			InventoryLimitController._racing = false
			InventoryLimitController:_refresh()
		end,
		InventoryFull = function(limit: number)
			InventoryLimitController:_show("", 0, limit)
		end,
		InventoryAutoSold = function(body: string, amount: number, limit: number)
			InventoryLimitController:_show(body, amount, limit)
		end,
	},
})

InventoryLimitController:withLifecycle({
	start = function(self)
		self._connections = {}
		for _, attribute in { GarageConfig.OwnedAttribute, GarageConfig.LotAttribute, CarryConfig.Hotbar.Attribute } do
			table.insert(self._connections, Players.LocalPlayer:GetAttributeChangedSignal(attribute):Connect(function()
				task.defer(function() self:_refresh() end)
			end))
		end
		task.spawn(function() self:_build() end)
	end,
})

InventoryLimitController:withCleanup(function()
	for _, connection in InventoryLimitController._connections or {} do connection:Disconnect() end
	if InventoryLimitController._gui then InventoryLimitController._gui:Destroy() end
	InventoryLimitController._gui = nil
end)

return InventoryLimitController
