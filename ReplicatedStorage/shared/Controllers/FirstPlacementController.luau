-- Fixed, touch-friendly action for the server-assigned first showroom bay.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local CAS = game:GetService("ContextActionService")
local Dispatcher = require(RS.Packages.Dispatcher)
local Shard = require(RS.Packages.Shard)
local Trove = require(RS.Packages.Trove)
local Config = require(RS.shared.Configs.FirstPlacementConfig)
local GarageConfig = require(RS.shared.Configs.GarageConfig)
local RaceConfig = require(RS.shared.Configs.RaceConfig)
local Controller = Shard.new("FirstPlacementController"):withDependencies({ "CarryController" })
local ACTION = "FirstCarPlace"

local function slotIndex(deck)
	local node = deck
	while node and node ~= workspace do
		local index = node:GetAttribute(GarageConfig.SlotIndexAttribute)
		if index ~= nil then return index end
		node = node.Parent
	end
	return nil
end

function Controller._input(self)
	local preferred = UIS.PreferredInput
	if preferred == Enum.PreferredInput.Touch then return "Touch" end
	if preferred == Enum.PreferredInput.Gamepad then return "Gamepad" end
	return "Keyboard"
end

function Controller._deck(self, index)
	local carry = Shard.get("CarryController")
	if not carry then return nil end
	-- Resolve fresh each update, so streaming out/in never leaves a stale target part.
	for _, deck in carry:_decks(true, true) do
		if slotIndex(deck) == index then return deck end
	end
	return nil
end

function Controller._blocked(self)
	if not self._ready then return true end
	local results = Shard.get("RaceUIController")
	if results and results:isLoading() then return true end
	local ui = Shard.get("UIController")
	for _, page in if ui then ui.pages or {} else {} do
		if page.PageUI and page.PageUI.Visible then return true end
	end
	return false
end

function Controller._build(self)
	local gui = Instance.new("ScreenGui")
	gui.Name = "FirstPlacementUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 45
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local frame = Instance.new("Frame")
	frame.Name = "Action"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.fromScale(0.5, 0.76)
	frame.Size = UDim2.new(0.58, 0, 0, 108)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = gui
	local cap = Instance.new("UISizeConstraint")
	cap.MinSize = Vector2.new(180, 108)
	cap.MaxSize = Vector2.new(340, 108)
	cap.Parent = frame
	local caption = Instance.new("TextLabel")
	caption.Name = "Status"
	caption.Size = UDim2.new(1, 0, 0, 42)
	caption.BackgroundColor3 = Color3.fromRGB(5, 31, 55)
	caption.BackgroundTransparency = 0.12
	caption.TextColor3 = Color3.new(1, 1, 1)
	caption.TextSize = 17
	caption.Font = Enum.Font.FredokaOne
	caption.TextWrapped = true
	caption.Text = "Park your car here"
	caption.Parent = frame
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 12)
	round.Parent = caption
	local button = Instance.new("TextButton")
	button.Name = "PlaceCar"
	button.Position = UDim2.fromOffset(0, 48)
	button.Size = UDim2.new(1, 0, 0, 60)
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	button.TextColor3 = Color3.fromRGB(4, 25, 44)
	button.TextStrokeColor3 = Color3.fromRGB(4, 25, 44)
	button.TextStrokeTransparency = 1
	button.Font = Enum.Font.FredokaOne
	button.TextSize = 25
	button.Text = "PLACE CAR"
	button.AutoButtonColor = true
	button.Parent = frame
	local curve = Instance.new("UICorner")
	curve.CornerRadius = UDim.new(0, 13)
	curve.Parent = button
	local outline = Instance.new("UIStroke")
	outline.Thickness = 4
	outline.Color = Color3.fromRGB(4, 25, 44)
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outline.Parent = button
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(255, 225, 0), Color3.fromRGB(55, 214, 0))
	gradient.Rotation = 90
	gradient.Parent = button
	self._gui, self._frame, self._caption, self._button, self._gradient = gui, frame, caption, button, gradient
	self._trove:Add(gui)
	self._trove:Add(button.Activated:Connect(function() self:_request() end))
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function Controller._request(self)
	if not self._canPlace or self._pendingAt then return end
	self._pendingAt = os.clock()
	self:getRemoteEvent("FirstPlacementRequest"):Fire(self:_input())
	self:_step()
end

function Controller._bind(self, on)
	if on == self._bound then return end
	self._bound = on
	if not on then CAS:UnbindAction(ACTION) return end
	CAS:BindActionAtPriority(ACTION, function(_, state)
		if not self._canPlace then return Enum.ContextActionResult.Pass end
		if state == Enum.UserInputState.Begin then self:_request() end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 1000, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
end

function Controller._result(self, ok, reason, bay)
	self._pendingAt = nil
	if ok then
		self._successUntil = os.clock() + 2
		self._message = "PARKED! Your car is on display"
		local deck = self:_deck(bay)
		if deck then
			local highlight = Instance.new("Highlight")
			highlight.Name = "FirstPlacementSuccess"
			highlight.Adornee = deck
			highlight.FillColor = Color3.fromRGB(100, 255, 40)
			highlight.FillTransparency = 0.45
			highlight.OutlineColor = Color3.new(1, 1, 1)
			highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			highlight.Parent = deck
			task.delay(1.5, function() highlight:Destroy() end)
		end
	elseif reason ~= "cooldown" then
		self._message = Config.Messages[reason] or Config.Messages.internal
		self._messageUntil = os.clock() + 3
	end
	self:_step()
end

function Controller._step(self)
	if not self._frame then return end
	local now = os.clock()
	local player = Players.LocalPlayer
	local active = player:GetAttribute(Config.ActiveAttribute) == true
	local success = now < (self._successUntil or 0)
	local notice = now < (self._messageUntil or 0)
	local blocked = self:_blocked()
	self._frame.Visible = not blocked and (active or success or notice)
	local deck = self:_deck(player:GetAttribute(Config.BayAttribute))
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local close = deck and root and (deck.Position - root.Position).Magnitude <= Config.MaxDistance
	self._canPlace = active and not blocked and close == true and not success
	if self._pendingAt and now - self._pendingAt > Config.RequestTimeout then
		self._pendingAt = nil
		self._message, self._messageUntil = Config.Messages.timeout, now + 3
		notice = true
	end
	self._caption.Text = if success or notice then self._message
		elseif self._pendingAt then "Waiting for placement confirmation..."
		elseif not deck then "Finding your empty showroom bay..."
		elseif not close then "Walk to the highlighted bay"
		else "Park your car here"
	self._button.Visible = active and close == true and not success
	self._button.Active = self._canPlace and not self._pendingAt
	self._button.Selectable = self._button.Active
	local input = self:_input()
	self._button.Text = if self._pendingAt then "PLACING..."
		elseif input == "Keyboard" then "[E] PLACE CAR"
		elseif input == "Gamepad" then "[X] PLACE CAR" else "PLACE CAR"
	self:_bind(self._canPlace)
	if self._canPlace then
		local flow = player:GetAttribute(Config.FlowAttribute)
		if flow and self._shownFlow ~= flow then
			self._shownFlow = flow
			self:getRemoteEvent("FirstPlacementPromptShown"):Fire(input)
		end
	end
end

Controller:withRemoteEvents({ "FirstPlacementRequest", "FirstPlacementPromptShown", {
	FirstPlacementResult = function(ok, reason, bay) Controller:_result(ok, reason, bay) end,
	RaceStart = function() Controller._ready = false Controller:_step() end,
} })
Controller:withLifecycle({
	init = function(self) self._trove = Trove.new() self._ready = true end,
	start = function(self)
		if not Config.Enabled then return end
		self:_build()
		Dispatcher:Subscribe(RaceConfig.ReturnedEvent, function() self._ready = true self:_step() end)
		local elapsed = 0
		self._trove:Add(RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed < 0.1 then return end
			elapsed = 0 self:_step()
		end))
	end,
})
Controller:withCleanup(function()
	CAS:UnbindAction(ACTION)
	if Controller._trove then Controller._trove:Destroy() end
end)
return Controller
