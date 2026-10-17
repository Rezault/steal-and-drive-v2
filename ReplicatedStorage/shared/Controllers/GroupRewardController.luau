--[[
	GroupRewardController  (client)
	-------------------------------
	The viewer's side of the group reward stand (`GroupRewardConfig`): their OWN character dancing on
	`AvatarSpot`, the sign, and the claim. `GroupRewardService` parks the car and decides the claim.

	THE DANCER IS YOU, ON YOUR SCREEN ONLY. Every viewer builds a clone of their own character, so
	the stand says "this could be you" to everyone at once. The clone is the NEW BEST stage's
	(`ShowcaseController.buildDancer`): same strip, same dance. It is rebuilt when the character
	respawns or the avatar finishes loading, so it wears what the player is wearing.

	THE CLAIM OPENS ROBLOX'S OWN JOIN POPUP FIRST (`GroupService:PromptJoinAsync`), then asks the
	server. Joining or not, the server is what checks, so dismissing the popup just gets "join the
	group first". A failed popup (no such API on an old client, a web error) still asks, and the
	server's answer says what to do. The answer is shown on the stand's own sign, where the player
	is looking.
]]

local CollectionService = game:GetService("CollectionService")
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local GroupRewardConfig = require(ReplicatedStorage.shared.Configs.GroupRewardConfig)

local GroupRewardController = Shard.new("GroupRewardController")

local TEXT = GroupRewardConfig.Text
local PARTS = GroupRewardConfig.Parts
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
local GOOD = Color3.fromRGB(91, 255, 91)
local BAD = Color3.fromRGB(255, 110, 110)
--- Seconds the server's answer stays on the sign before the usual lines come back.
local STATUS_SECONDS = 4

type Stand = {
	model: Model,
	gui: BillboardGui,
	title: TextLabel,
	ask: TextLabel,
	like: TextLabel,
	status: TextLabel,
	dancer: Model?,
	connections: { RBXScriptConnection },
}

GroupRewardController:withRemoteEvents({
	GroupRewardConfig.Remotes.Claim,
	{
		[GroupRewardConfig.Remotes.Result] = function(ok: unknown, message: unknown)
			GroupRewardController:_showStatus(ok == true, tostring(message))
		end,
	},
})

local function claimed(): boolean
	return Players.LocalPlayer:GetAttribute(GroupRewardConfig.ClaimedAttribute) == true
end

local function line(parent: Instance, y: number, h: number, colour: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, y)
	label.Size = UDim2.fromScale(1, h)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.TextColor3 = colour
	label.TextScaled = true
	label.Text = ""
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(20, 12, 30)
	stroke.Parent = label
	label.Parent = parent
	return label
end

--- The sign's lines for the current claimed state. The status line is the server's answer, if any.
function GroupRewardController._paint(self, stand: Stand)
	local done = claimed()
	stand.title.Text = if done then TEXT.Claimed else TEXT.Title
	stand.ask.Text = if done then TEXT.ClaimedAsk else TEXT.Ask
	stand.like.Text = TEXT.Like
	stand.like.Visible = not done
	--- No claim button once it is yours: the server would only say "already claimed".
	local prompt = stand.model:FindFirstChild("GroupRewardPrompt", true)
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = not done
	end
end

--- The server's answer, on every stand's sign for `STATUS_SECONDS`.
function GroupRewardController._showStatus(self, ok: boolean, message: string)
	self._statusToken += 1
	local token = self._statusToken
	for _, stand in self._stands do
		stand.status.Text = message
		stand.status.TextColor3 = if ok then GOOD else BAD
		self:_paint(stand)
	end
	task.delay(STATUS_SECONDS, function()
		if self._statusToken ~= token then
			return
		end
		for _, stand in self._stands do
			stand.status.Text = ""
		end
	end)
end

--- (Re)build this viewer's dancer on the stand's `AvatarSpot`. No spot or no character: no dancer.
function GroupRewardController._dance(self, stand: Stand)
	if stand.dancer then
		stand.dancer:Destroy()
		stand.dancer = nil
	end
	local spot = stand.model:FindFirstChild(PARTS.Avatar)
	local Showcase = Shard.get("ShowcaseController")
	if not (spot and spot:IsA("BasePart") and Showcase) then
		return
	end
	local feet = spot.Position - Vector3.yAxis * (spot.Size.Y / 2)
	local look = spot.CFrame.LookVector * Vector3.new(1, 0, 1)
	stand.dancer = Showcase:buildDancer(self._folder, feet, feet + (if look.Magnitude > 1e-3 then look.Unit else Vector3.zAxis))
end

--- Press: the join popup, then the claim. Already claimed does nothing (the prompt is off anyway).
function GroupRewardController._press(self)
	if claimed() or self._pressing then
		return
	end
	self._pressing = true
	task.spawn(function()
		--- Yields until the popup closes; its answer is not trusted either way (header).
		pcall(function()
			GroupService:PromptJoinAsync(GroupRewardConfig.GroupId)
		end)
		self:getRemoteEvent(GroupRewardConfig.Remotes.Claim):Fire()
		self._pressing = false
	end)
end

function GroupRewardController._bind(self, model: Instance)
	if not model:IsA("Model") or self._stands[model] then
		return
	end
	local signPart = model:FindFirstChild(PARTS.Sign)
	local carSpot = model:FindFirstChild(PARTS.Car)
	local adornee = if signPart and signPart:IsA("BasePart") then signPart else carSpot
	if not (adornee and adornee:IsA("BasePart")) then
		return
	end

	local cfg = GroupRewardConfig.Sign
	local gui = Instance.new("BillboardGui")
	gui.Name = "GroupRewardSign"
	gui.Adornee = adornee
	gui.Size = UDim2.fromScale(cfg.Size.X, cfg.Size.Y)
	gui.StudsOffset = if adornee == carSpot then Vector3.new(0, cfg.Lift, 0) else Vector3.zero
	gui.MaxDistance = cfg.MaxDistance
	gui.LightInfluence = 0
	gui.Parent = self._folder

	local stand: Stand = {
		model = model,
		gui = gui,
		title = line(gui, 0, 0.38, Color3.fromRGB(255, 220, 60)),
		ask = line(gui, 0.4, 0.2, Color3.new(1, 1, 1)),
		like = line(gui, 0.62, 0.15, Color3.fromRGB(200, 220, 255)),
		status = line(gui, 0.8, 0.18, GOOD),
		dancer = nil,
		connections = {},
	}
	self._stands[model] = stand
	self:_paint(stand)
	self:_dance(stand)

	--- The prompt is the server's and may arrive after the stand; wire it whenever it does.
	local function wire(child: Instance)
		if child:IsA("ProximityPrompt") and child.Name == "GroupRewardPrompt" then
			child.Enabled = not claimed()
			table.insert(stand.connections, child.Triggered:Connect(function()
				self:_press()
			end))
		end
	end
	for _, child in model:GetDescendants() do
		wire(child)
	end
	table.insert(stand.connections, model.DescendantAdded:Connect(wire))
end

function GroupRewardController._unbind(self, model: Instance)
	local stand = self._stands[model :: Model]
	if not stand then
		return
	end
	self._stands[model :: Model] = nil
	for _, connection in stand.connections do
		connection:Disconnect()
	end
	stand.gui:Destroy()
	if stand.dancer then
		stand.dancer:Destroy()
	end
end

GroupRewardController:withLifecycle({
	init = function(self)
		self._stands = {} :: { [Model]: Stand }
		self._statusToken = 0
		self._pressing = false
	end,

	start = function(self)
		if not GroupRewardConfig.Enabled then
			return
		end
		--- The dancers and signs live here, on this client only.
		local folder = Instance.new("Folder")
		folder.Name = "GroupRewardLocal"
		folder.Parent = workspace
		self._folder = folder

		CollectionService:GetInstanceAddedSignal(GroupRewardConfig.Tag):Connect(function(model)
			self:_bind(model)
		end)
		CollectionService:GetInstanceRemovedSignal(GroupRewardConfig.Tag):Connect(function(model)
			self:_unbind(model)
		end)
		for _, model in CollectionService:GetTagged(GroupRewardConfig.Tag) do
			self:_bind(model)
		end

		local player = Players.LocalPlayer
		player:GetAttributeChangedSignal(GroupRewardConfig.ClaimedAttribute):Connect(function()
			for _, stand in self._stands do
				self:_paint(stand)
			end
		end)
		--- A new body or a finished avatar load: dance in what they are wearing now.
		local function redress()
			for _, stand in self._stands do
				self:_dance(stand)
			end
		end
		player.CharacterAppearanceLoaded:Connect(redress)
		player.CharacterAdded:Connect(function()
			task.wait(1)
			redress()
		end)
	end,
})

return GroupRewardController
