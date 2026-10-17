--[[
	IndexRewardController  (client)
	-------------------------------
	Sends claim requests and celebrates confirmed rewards. Replicated Player attributes remain the
	Index pages' source of truth; only the server's success event can trigger the popup.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local IndexRewardConfig = require(ReplicatedStorage.shared.Configs.IndexRewardConfig)
local ArcadeKit = require(ReplicatedStorage.shared.Modules.ArcadeKit)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)

local IndexRewardController = Shard.new("IndexRewardController")

function IndexRewardController.claim(self, body: string)
	self:getRemoteEvent(IndexRewardConfig.Remotes.Claim):Fire(body)
end

function IndexRewardController.claimAll(self)
	self:getRemoteEvent(IndexRewardConfig.Remotes.ClaimAll):Fire()
end

IndexRewardController:withRemoteEvents({
	IndexRewardConfig.Remotes.Claim,
	IndexRewardConfig.Remotes.ClaimAll,
	{
		[IndexRewardConfig.Remotes.Claimed] = function(body: string?, total: number, count: number)
			IndexRewardController:_celebrate(body, total, count)
		end,
	},
})

function IndexRewardController._celebrate(self, body: string?, total: number, count: number)
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local screen = playerGui and UIRoot.find(playerGui)
	if not screen then
		return
	end
	-- Replace the previous toast when claiming several cards quickly.
	if self._popup then
		self._popup:Destroy()
	end
	local popup = Instance.new("CanvasGroup")
	popup.Name = "IndexLuckReward"
	popup.BackgroundTransparency = 1
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Position = UDim2.fromScale(0.5, 0.43)
	popup.Size = UDim2.fromScale(0.55, 0.18)
	popup.ZIndex = 60
	popup.Parent = screen
	self._popup = popup
	Debris:AddItem(popup, 1.7)

	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(420, 140)
	limit.Parent = popup
	local scale = Instance.new("UIScale")
	scale.Scale = 0.65
	scale.Parent = popup

	local reward = ArcadeKit.text(popup, 0.08, 0.1, 0.84, 0.42, Color3.fromRGB(133, 255, 92), true)
	reward.ZIndex = 61
	reward.Text = string.format("+%d%% LUCK!", IndexRewardConfig.percentFor(count))
	local name = ArcadeKit.text(popup, 0.08, 0.54, 0.84, 0.19, ArcadeKit.White, true)
	name.ZIndex = 61
	name.Text = if body then GarageConfig.displayName(body) else string.format("%d CARS CLAIMED", count)
	local accumulated = ArcadeKit.text(popup, 0.08, 0.77, 0.84, 0.15, ArcadeKit.Gold, true)
	accumulated.ZIndex = 61
	accumulated.Text = string.format("INDEX BONUS: +%d%% LUCK", IndexRewardConfig.percentFor(total))

	for index = 1, 8 do
		local angle = index * math.pi / 4
		local spark = ArcadeKit.text(popup, 0.46, 0.29, 0.08, 0.18, ArcadeKit.Gold, true)
		spark.ZIndex = 62
		spark.Text = "✦"
		spark.Rotation = index * 45
		TweenService:Create(spark, TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.46 + math.cos(angle) * 0.43, 0.29 + math.sin(angle) * 0.3),
			TextTransparency = 1,
			Rotation = spark.Rotation + 90,
		}):Play()
	end
	TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(popup, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.5, 0.36),
	}):Play()
	task.delay(1.05, function()
		if popup.Parent then
			TweenService:Create(popup, TweenInfo.new(0.4), { GroupTransparency = 1 }):Play()
		end
	end)
end

return IndexRewardController
