--[[
	OfflineLabelController  (client)
	--------------------------------
	"Your cars earn $X/hr offline!" across the top of the lobby (2026-09-30). `OfflineConfig.Label` has
	the design and why the unit is per hour; the figure is the server's (`OfflineService` publishes it
	off the WELCOME BACK payout's own arithmetic), so this file only draws a number it is handed.

	Hidden for the length of a run (`RaceStart` / `RaceEnd`): it is a lobby line, and the road has its
	own HUD across the top. And hidden while any card that lands in the same top-centre spot is up
	(`OfflineConfig.Label.YieldTo`) — it showed through the carry card's panel, and a line of text
	through a panel reads as a rendering bug.

	IN THE NOTICE LANE SINCE 2026-10-06 (Leaf: "we have to stop spamming everything on the top"): the
	line is the top slot of the left-side lane (`NoticeLaneConfig`), left-aligned at the lane's width,
	and the cards that used to land on it stack under it instead, so it only yields to the tutorial
	(`OfflineConfig.Label.LaneYieldTo`). BACK AT THE TOP the same day, on the owner's call — behind
	`OfflineConfig.Label.InLane`, which is off.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local NoticeLaneConfig = require(ReplicatedStorage.shared.Configs.NoticeLaneConfig)
local OfflineConfig = require(ReplicatedStorage.shared.Configs.OfflineConfig)
local NoticeLane = require(ReplicatedStorage.shared.Modules.NoticeLane)

local OfflineLabelController = Shard.new("OfflineLabelController")

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)
--- Over the ordinary HUD, under every modal (the hotbar is 870, the results far above).
local DISPLAY_ORDER = 860

--- In the left-side notice lane, or the old top-centre line (`OfflineConfig.Label.InLane`).
local function inLane(): boolean
	return NoticeLaneConfig.Enabled and OfflineConfig.Label.InLane == true
end

function OfflineLabelController._build(self)
	local label = OfflineConfig.Label
	local gui = Instance.new("ScreenGui")
	gui.Name = "OfflineEarnings"
	gui.ResetOnSpawn = false
	--- NOT ignoring the inset: the line sits under Roblox's top bar, never behind it.
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = DISPLAY_ORDER

	local text = Instance.new("TextLabel")
	text.Name = "Line"
	text.AnchorPoint = Vector2.new(0.5, 0)
	text.Position = UDim2.new(0.5, 0, 0, label.Top)
	text.BackgroundTransparency = 1
	text.FontFace = FONT
	text.RichText = true
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Text = ""
	text.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(20, 20, 30)
	stroke.Parent = text

	if inLane() then
		text.TextXAlignment = Enum.TextXAlignment.Left
		--[[ A fixed size that wraps, rather than scaled type: the lane is half the old line's width,
			and the empty-lot sentence scaled down to fit one line of it was 8 pixels tall. Two lines
			at a readable size instead, and the box grows to fit (the lane restacks on that). ]]
		text.TextScaled = false
		text.TextWrapped = true
		text.AutomaticSize = Enum.AutomaticSize.Y
		--- Quiet: it is simply there in the lobby, so it takes its slot without a slide.
		self._lane = NoticeLane.join(text, NoticeLaneConfig.Order.OfflineLabel, false)
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			self:_fit()
		end)
	end

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self._gui = gui
	self._text = text

	self:_fit()
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
		self:_fit()
	end)
end

--- A smaller line on a phone (`OfflineConfig.Label.TouchHeight`). Re-asked when the device changes
--- its mind, the way a touchscreen laptop can.
function OfflineLabelController._fit(self)
	local label = OfflineConfig.Label
	local touch = UserInputService.PreferredInput == Enum.PreferredInput.Touch
	local width = if touch then label.TouchWidth else label.Width
	local height = if touch then label.TouchHeight else label.Height
	if self._lane then
		--- The lane's width, in pixels, so the line lines up with the cards stacked under it.
		self._text.Size = UDim2.fromOffset(NoticeLane.width(), 0)
		self._text.TextSize = if touch then label.LaneTouchTextSize else label.LaneTextSize
		return
	end
	self._text.Size = UDim2.new(width, 0, 0, height)
end

function OfflineLabelController._apply(self)
	if not self._gui then
		return
	end
	local label = OfflineConfig.Label
	local rate = Players.LocalPlayer:GetAttribute(label.Attribute)
	--- Nothing published yet is nothing drawn, rather than an empty-lot line that flickers to a figure.
	local shown = type(rate) == "number" and not self._racing and not self:_yielding()
	if self._lane then
		if shown then
			self._gui.Enabled = true
			if not self._lane:isUp() then
				self._lane:show()
			end
		else
			self._lane:hide(function()
				self._gui.Enabled = false
			end)
		end
	else
		self._gui.Enabled = shown
	end
	if type(rate) ~= "number" then
		return
	end
	self._text.Text = if rate > 0 then string.format(label.Format, GarageConfig.formatCash(rate)) else label.EmptyText
end

--- Is one of the top-centre cards (`OfflineConfig.Label.YieldTo`) switched on right now?
function OfflineLabelController._yielding(self): boolean
	for gui in self._rivals do
		if gui.Parent and gui.Enabled then
			return true
		end
	end
	return false
end

--- Follow one rival screen's `Enabled`, so the label steps aside the moment it comes up.
function OfflineLabelController._watchRival(self, inst: Instance)
	local names = if inLane() then OfflineConfig.Label.LaneYieldTo else OfflineConfig.Label.YieldTo
	if not (inst:IsA("ScreenGui") and table.find(names, inst.Name)) or self._rivals[inst] then
		return
	end
	self._rivals[inst] = true
	inst:GetPropertyChangedSignal("Enabled"):Connect(function()
		self:_apply()
	end)
	inst.AncestryChanged:Connect(function()
		self:_apply()
	end)
	self:_apply()
end

OfflineLabelController:withRemoteEvents({
	{
		RaceStart = function()
			OfflineLabelController._racing = true
			OfflineLabelController:_apply()
		end,
		RaceEnd = function()
			OfflineLabelController._racing = false
			OfflineLabelController:_apply()
		end,
	},
})

OfflineLabelController:withLifecycle({
	init = function(self)
		self._racing = false
		self._rivals = {} :: { [ScreenGui]: boolean }
	end,

	start = function(self)
		if not (OfflineConfig.Enabled and OfflineConfig.Label.Enabled) then
			return
		end
		self:_build()
		--- The rival cards are built by their own controllers, some only when first needed.
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		for _, inst in playerGui:GetChildren() do
			self:_watchRival(inst)
		end
		playerGui.ChildAdded:Connect(function(inst)
			self:_watchRival(inst)
		end)
		Players.LocalPlayer:GetAttributeChangedSignal(OfflineConfig.Label.Attribute):Connect(function()
			self:_apply()
		end)
		self:_apply()
	end,
})

return OfflineLabelController
