-- Developer and VIP presentation for everyone in the server. Developer uses the existing admin
-- roster; VIP ownership is replicated by PassService. Tags grant no permissions or income perks.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local PassConfig = require(ReplicatedStorage.shared.Configs.PassConfig)
local Admins = require(ReplicatedStorage.shared.Configs.Admins)

local VIPController = Shard.new("VIPController")
local OWNED_ATTRIBUTE = PassConfig.ownedAttribute("VIP")
local TAG_NAME = "PlayerVIPTag"

local function roleOf(player: Player): string?
	if Admins.isAdmin(player) then
		return "Developer"
	end
	return if player:GetAttribute(OWNED_ATTRIBUTE) == true then "VIP" else nil
end

function VIPController._tag(self, player: Player, character: Model)
	local head = character:WaitForChild("Head", 10)
	if not (head and head:IsA("BasePart") and player.Character == character and player.Parent == Players) then
		return
	end
	local existing = head:FindFirstChild(TAG_NAME)
	local role = roleOf(player)
	if not role then
		if existing then
			existing:Destroy()
		end
		return
	end
	if existing then
		existing:Destroy()
	end
	local tag = Instance.new("BillboardGui")
	tag.Name = TAG_NAME
	tag.Archivable = false -- Avatar copies (group reward dancer, showcases) must not inherit player tags.
	tag.Enabled = not self._racing
	tag.Adornee = head
	tag.Size = UDim2.fromOffset(if role == "Developer" then 150 else 80, 28)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	tag.AlwaysOnTop = true
	tag.MaxDistance = 100
	tag.LightInfluence = 0
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	text.TextScaled = true
	text.Text = role
	text.TextColor3 = if role == "Developer" then Color3.fromRGB(75, 225, 255) else Color3.fromRGB(255, 214, 58)
	local outline = Instance.new("UIStroke")
	outline.Color = if role == "Developer" then Color3.fromRGB(2, 30, 56) else Color3.fromRGB(68, 42, 3)
	outline.Thickness = 2
	outline.Parent = text
	text.Parent = tag
	tag.Parent = head
end

function VIPController._setRacing(self, racing: boolean)
	self._racing = racing
	for player in self._players do
		local head = player.Character and player.Character:FindFirstChild("Head")
		local tag = head and head:FindFirstChild(TAG_NAME)
		if tag then
			tag.Enabled = not racing
		end
	end
end

VIPController:withRemoteEvents({
	{
		RaceStart = function()
			VIPController:_setRacing(true)
		end,
		RaceEnd = function()
			VIPController:_setRacing(false)
		end,
	},
})

function VIPController._watch(self, player: Player)
	if self._players[player] then
		return
	end
	local trove = Trove.new()
	self._players[player] = trove
	local function tag(character: Model)
		task.spawn(function()
			self:_tag(player, character)
		end)
	end
	trove:Add(player.CharacterAdded:Connect(tag))
	trove:Add(player:GetAttributeChangedSignal(OWNED_ATTRIBUTE):Connect(function()
		if player.Character then
			tag(player.Character)
		end
	end))
	if player.Character then
		tag(player.Character)
	end
end

VIPController:withLifecycle({
	init = function(self)
		self._racing = false
		self._players = {}
		self._trove = Trove.new()
	end,
	start = function(self)
		self._trove:Add(Players.PlayerAdded:Connect(function(player)
			self:_watch(player)
		end))
		self._trove:Add(Players.PlayerRemoving:Connect(function(player)
			local trove = self._players[player]
			if trove then
				trove:Destroy()
				self._players[player] = nil
			end
		end))
		for _, player in Players:GetPlayers() do
			self:_watch(player)
		end
		if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
			TextChatService.OnIncomingMessage = function(message: TextChatMessage)
				local source = message.TextSource
				local player = source and Players:GetPlayerByUserId(source.UserId)
				local role = player and roleOf(player)
				if role then
					local properties = Instance.new("TextChatMessageProperties")
					local colour = if role == "Developer" then "#4BE1FF" else "#FFD63A"
					properties.PrefixText = string.format('<font color="%s">[%s]</font> ', colour, role) .. message.PrefixText
					return properties
				end
				return nil
			end
		end
	end,
})

VIPController:withCleanup(function()
	VIPController._trove:Destroy()
	for _, trove in VIPController._players do
		trove:Destroy()
	end
end)

return VIPController
