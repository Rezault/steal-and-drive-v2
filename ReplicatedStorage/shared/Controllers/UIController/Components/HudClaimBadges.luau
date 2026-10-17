--[[ Actionable reward counts on the HUD's Index and Quest doors. Both numbers are derived from
	state those screens already trust; this component owns presentation only and sends no remotes. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local IndexRewardConfig = require(ReplicatedStorage.shared.Configs.IndexRewardConfig)
local QuestConfig = require(ReplicatedStorage.shared.Configs.QuestConfig)
local CarCatalogue = require(ReplicatedStorage.shared.Modules.CarCatalogue)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)

local GUI_WAIT = 10
local INDEX_PAGE = "Index"

local function makeBadge(button: GuiButton): TextLabel
	local badge = Instance.new("TextLabel")
	badge.Name = "ClaimBadge"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromScale(0.88, 0.12)
	badge.Size = UDim2.fromScale(0.44, 0.44)
	badge.BackgroundColor3 = Color3.fromRGB(235, 52, 62)
	badge.BorderSizePixel = 0
	badge.Font = Enum.Font.GothamBlack
	badge.TextColor3 = Color3.new(1, 1, 1)
	badge.TextScaled = true
	badge.TextStrokeColor3 = Color3.fromRGB(86, 12, 19)
	badge.TextStrokeTransparency = 0
	badge.ZIndex = button.ZIndex + 20
	badge.Visible = false

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = badge
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = badge
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.12, 0)
	padding.PaddingBottom = UDim.new(0.12, 0)
	padding.PaddingLeft = UDim.new(0.12, 0)
	padding.PaddingRight = UDim.new(0.12, 0)
	padding.Parent = badge
	local rim = Instance.new("UIStroke")
	rim.Color = Color3.fromRGB(83, 15, 23)
	rim.Thickness = 2
	rim.Parent = badge

	badge.Parent = button
	return badge
end

local function indexClaims(player: Player): number
	local found = CarCatalogue.parseFound(player:GetAttribute(CarCatalogue.FoundAttribute))
	local claimed = IndexRewardConfig.parseClaimed(player:GetAttribute(IndexRewardConfig.ClaimedAttribute))
	local count = 0
	for _, car in CarCatalogue.Roster do
		if found[car.body] and not claimed[car.body] then
			count += 1
		end
	end
	return count
end

local function questClaims(): number
	local controller = Shard.get("QuestController")
	local board = controller and controller:board()
	if not (board and type(board.quests) == "table") then
		return 0
	end
	local count = 0
	for _, quest in board.quests do
		if quest.Claimed ~= true and (tonumber(quest.Progress) or 0) >= (tonumber(quest.Target) or math.huge) then
			count += 1
		end
	end
	return count
end

return function(UIController)
	task.spawn(function()
		local mainUI = UIRoot.wait(UIController.PlayerGui, GUI_WAIT)
		local hud = mainUI and mainUI:FindFirstChild("HUD")
		if not hud then
			return
		end

		local badges = { [INDEX_PAGE] = {}, [QuestConfig.PageName] = {} }
		for _, item in hud:GetDescendants() do
			if item:IsA("GuiButton") then
				local pageBadges = badges[item:GetAttribute("Page")]
				if pageBadges then
					table.insert(pageBadges, makeBadge(item))
				end
			end
		end

		local function paint(page: string, count: number)
			for _, badge in badges[page] do
				badge.Text = tostring(count)
				badge.Visible = count > 0
			end
		end
		local function paintIndex()
			paint(INDEX_PAGE, indexClaims(UIController.Player))
		end
		local function paintQuests()
			paint(QuestConfig.PageName, questClaims())
		end

		UIController.Player:GetAttributeChangedSignal(CarCatalogue.FoundAttribute):Connect(paintIndex)
		UIController.Player:GetAttributeChangedSignal(IndexRewardConfig.ClaimedAttribute):Connect(paintIndex)
		Dispatcher:Subscribe(QuestConfig.StateEvent, paintQuests)
		paintIndex()
		paintQuests()
	end)
end
