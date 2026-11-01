-- Manual first-car handoff and bounded diagnostics. Server owns bay, distance and success.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local RobloxAnalytics = game:GetService("AnalyticsService")
local Shard = require(RS.Packages.Shard)
local Trove = require(RS.Packages.Trove)
local Config = require(RS.shared.Configs.FirstPlacementConfig)
local CarryConfig = require(RS.shared.Configs.CarryConfig)
local GarageConfig = require(RS.shared.Configs.GarageConfig)

local Service = Shard.new("FirstPlacementService"):withDependencies({ "GarageService", "FirstCarService" })

function Service._garage(self)
	return Shard.get("GarageService")
end

function Service._eligible(self, player)
	local first = Shard.get("FirstCarService")
	local record = first and first:_record(player)
	return Config.Enabled and record ~= nil and not record.Placed
end

function Service._away(self, player)
	local race = Shard.get("RaceService")
	return self._awayPlayers[player] == true or (race ~= nil and (race:isRacing(player) or race:isReturning(player)))
end

function Service._event(self, player, state, stage, extra)
	local data = {
		stage = stage, flowId = state.flowId, placementVersion = Config.Version,
		elapsedSeconds = math.round((os.clock() - state.startedAt) * 100) / 100,
		homeSeconds = if state.readyAt then math.round((os.clock() - state.readyAt) * 100) / 100 else -1,
		attempts = state.attempts, bay = state.bay or 0, resumed = state.resumed,
		inputMethod = state.inputMethod or "Unknown",
		placeVersion = game.PlaceVersion,
		tutorialStep = tostring(player:GetAttribute("TutorialStep") or ""),
	}
	for key, value in extra or {} do data[key] = value end
	-- Keep a bounded in-memory ledger in Studio for verification; no credentials or profile copies.
	if RunService:IsStudio() then
		table.insert(self._diagnostics, data)
		if #self._diagnostics > 100 then table.remove(self._diagnostics, 1) end
	end
	local analytics = Shard.get("AnalyticsService")
	if analytics then
		pcall(function() analytics:Marker(player, "FirstPlacement", data) end)
	end
end

function Service._stage(self, player, state, number, name)
	if state.funnel[number] then return end
	state.funnel[number] = true
	pcall(function()
		RobloxAnalytics:LogFunnelStepEvent(player, Config.FunnelName, state.flowId, number, name)
	end)
end

function Service._publish(self, player, state, active)
	local bay = if state then state.bay else nil
	player:SetAttribute(Config.BayAttribute, bay)
	player:SetAttribute(Config.FlowAttribute, if state then state.flowId else nil)
	player:SetAttribute(Config.ActiveAttribute, active == true)
end

function Service._selectBay(self, player, state)
	local garage = self:_garage()
	local chosen, lowest
	for _, bay in garage:getBays(player) do
		if bay.deck and bay.deck.Parent and not garage:isWorkshopBay(bay.index)
			and not garage:getBayCar(player, bay.index) then
			if bay.index == state.bay then chosen = bay end
			if not lowest or bay.index < lowest.index then lowest = bay end
		end
	end
	chosen = chosen or lowest
	local nextBay = if chosen then chosen.index else nil
	if state.bay and state.bay ~= nextBay then
		self:_event(player, state, "TargetChanged", { reason = "occupiedOrRemoved", nextBay = nextBay or 0 })
	end
	state.bay = nextBay
	return chosen
end

function Service._faceBay(self, player, state, bay)
	if state.positioned or self:_away(player) then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local human = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and human and human.Health > 0 and not human.SeatPart and not root.Anchored) then return end
	local base = bay.base
	local spot = (base.CFrame * CFrame.new(0, base.Size.Y / 2 + 3, -(base.Size.Z / 2 + Config.StandFromFront))).Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, bay.model }
	params.RespectCanCollide = true
	local floor = workspace:Raycast(spot + Vector3.new(0, 5, 0), Vector3.new(0, -25, 0), params)
	if not floor then
		if not state.unsafeReported then
			state.unsafeReported = true
			self:_event(player, state, "PositionSkipped", { reason = "noSafeFloor" })
		end
		state.positioned = true
		return -- Guidance still works; never move a player over a void.
	end
	spot = Vector3.new(spot.X, floor.Position.Y + human.HipHeight + root.Size.Y / 2, spot.Z)
	character:PivotTo(CFrame.lookAt(spot, Vector3.new(base.Position.X, spot.Y, base.Position.Z)))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	state.positioned = true
	self:_event(player, state, "Positioned")
end

function Service._sync(self, player)
	if player.Parent ~= Players then return end
	local garage = self:_garage()
	if not garage or not garage:isProfileReady(player) then return end
	local state = self._flows[player]
	if not self:_eligible(player) then
		self:_publish(player, nil, false)
		return
	end
	local key = garage:getCarriedCar(player)
	if not key then
		self:_publish(player, state, false)
		return
	end
	if not state then
		state = {
			flowId = HttpService:GenerateGUID(false), startedAt = os.clock(), attempts = 0,
			resumed = self._resumed[player] == true, funnel = {}, key = key,
		}
		self._flows[player] = state
		self:_event(player, state, "Carried")
		self:_stage(player, state, 1, "Carried")
	end
	if state.done then return end
	local bay = self:_selectBay(player, state)
	local home = not self:_away(player)
	if home and not state.readyAt then
		state.readyAt = os.clock()
		self:_event(player, state, "ReturnedHome")
	end
	if home and bay then
		self:_faceBay(player, state, bay)
		if not state.guideReady then
			state.guideReady = true
			self:_event(player, state, "GuideReady")
			self:_stage(player, state, 2, "GuideReady")
		end
	elseif home and not state.noBayReported then
		state.noBayReported = true
		self:_event(player, state, "WaitingForBay")
	end
	self:_publish(player, state, home)
end

function Service._reply(self, player, ok, reason, bay)
	self:getRemoteEvent("FirstPlacementResult"):Fire(player, ok, reason, bay)
end

-- Called by GarageService for BOTH the normal podium and the fixed placement button.
function Service.beforePlace(self, player, bayIndex)
	self:_sync(player)
	local state = self._flows[player]
	if not state or state.done or not self:_eligible(player) then return true end
	local now = os.clock()
	if now < (state.nextAttempt or 0) then return false, "cooldown" end
	state.nextAttempt = now + Config.RequestCooldown
	state.attempts += 1
	local source = state.requestSource or "podium"
	state.requestSource = nil
	state.lastSource = source
	local garage = self:_garage()
	local bay
	for _, entry in garage:getBays(player) do if entry.index == bayIndex then bay = entry break end end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local reason
	if self:_away(player) then reason = "racing"
	elseif not bay or garage:isWorkshopBay(bayIndex) then reason = "badBay"
	elseif not root then reason = "noCharacter"
	elseif (root.Position - bay.deck.Position).Magnitude > Config.MaxDistance then reason = "tooFar"
	elseif garage:getBayCar(player, bayIndex) then reason = "occupied" end
	local distance = if root and bay then math.round((root.Position - bay.deck.Position).Magnitude) else -1
	-- Bound telemetry under repeated valid input. Attempts remains an accurate running counter.
	if state.attempts <= 20 then self:_event(player, state, "Attempt", { source = source, requestedBay = bayIndex, distance = distance }) end
	if reason then
		self:failed(player, reason)
		return false, reason
	end
	return true
end

function Service.failed(self, player, reason)
	local state = self._flows[player]
	if not state or state.done then return end
	if state.attempts <= 20 then self:_event(player, state, "Failed", { reason = reason, source = state.lastSource or "podium" }) end
	self:_selectBay(player, state)
	self:_publish(player, state, not self:_away(player))
	self:_reply(player, false, reason, state.bay)
end

function Service._parked(self, player, bayIndex)
	local state = self._flows[player]
	if not state or state.done then return end
	state.done = true
	state.bay = bayIndex
	self._protected[player] = { bay = bayIndex, untilAt = os.clock() + Config.PickupProtection }
	self:_event(player, state, "Placed", { source = state.lastSource or "inventory" })
	self:_stage(player, state, 3, "Placed")
	self:_publish(player, nil, false)
	self:_reply(player, true, "parked", bayIndex)
end

function Service.canPickUp(self, player, bayIndex)
	local protected = self._protected[player]
	if protected and protected.bay == bayIndex and os.clock() < protected.untilAt then
		self:_reply(player, false, "protected", bayIndex)
		return false
	end
	return true
end

function Service._request(self, player, inputMethod)
	self:_sync(player)
	local state = self._flows[player]
	if not state or state.done or not self:_eligible(player) then
		self:_reply(player, false, "notCarrying")
		return
	end
	if type(inputMethod) == "string" and ({ Touch = true, Keyboard = true, Gamepad = true })[inputMethod] then
		state.inputMethod = inputMethod
	end
	if not state.bay then self:_reply(player, false, "noBay") return end
	state.requestSource = "button"
	local ok, reason = self:_garage():placeCarried(player, state.bay)
	state.requestSource = nil
	if not ok and reason == "cooldown" then self:_reply(player, false, reason, state.bay) end
end

-- Explicit audit stream: an existing completed profile is not a new tutorial entrant.
-- Completion retains the game's definition: finish 'again' by entering the second race.
function Service.tutorialEvent(self, player, stage, beat, funnelStep)
	local audit = self._tutorial[player]
	if not audit then
		audit = { flowId = HttpService:GenerateGUID(false), startedAt = os.clock(), seen = {},
			cohort = if stage == "ExistingDone" then "existingDone" elseif beat == "" then "new" else "resumed" }
		self._tutorial[player] = audit
	end
	local key = stage .. ":" .. tostring(beat)
	if audit.seen[key] then return end
	audit.seen[key] = true
	local data = {
		stage = stage, beat = tostring(beat), funnelStep = tonumber(funnelStep) or 0,
		flowId = audit.flowId, cohort = audit.cohort, schemaVersion = 1,
		placementVersion = Config.Version, placeVersion = game.PlaceVersion,
		elapsedSeconds = math.round((os.clock() - audit.startedAt) * 100) / 100,
		completionDefinition = "again:RaceEntered",
	}
	if RunService:IsStudio() then
		table.insert(self._diagnostics, data)
		if #self._diagnostics > 100 then table.remove(self._diagnostics, 1) end
	end
	local analytics = Shard.get("AnalyticsService")
	if analytics then pcall(function() analytics:Marker(player, "TutorialAudit", data) end) end
end

Service:withRemoteEvents({ "FirstPlacementResult", {
	FirstPlacementRequest = function(player, inputMethod) Service:_request(player, inputMethod) end,
	FirstPlacementPromptShown = function(player, inputMethod)
		local state = Service._flows[player]
		if not state or state.done or state.promptShown or not state.guideReady or Service:_away(player) then return end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local bay = Service:_selectBay(player, state)
		if not root or not bay or (root.Position - bay.deck.Position).Magnitude > Config.MaxDistance + 2 then return end
		state.promptShown = true
		local input = if type(inputMethod) == "string" and ({ Touch = true, Keyboard = true, Gamepad = true })[inputMethod] then inputMethod else "Unknown"
		state.inputMethod = input
		Service:_event(player, state, "PromptShown", { inputMethod = input, clientReported = true })
	end,
} })

Service:withLifecycle({
	init = function(self)
		self._flows, self._protected, self._awayPlayers, self._diagnostics = {}, {}, {}, {}
		self._tutorial, self._resumed = {}, {}
		self._trove = Trove.new()
	end,
	start = function(self)
		if not Config.Enabled then return end
		local garage = self:_garage()
		self._trove:Add(garage:getSignal("ProfileReady"):Connect(function(player)
			self._resumed[player] = garage:getCarriedCar(player) ~= nil
			task.defer(function() self:_sync(player) end)
		end))
		for _, player in Players:GetPlayers() do
			if garage:isProfileReady(player) then self._resumed[player] = garage:getCarriedCar(player) ~= nil end
		end
		self._trove:Add(garage:getSignal("CarryChanged"):Connect(function(player)
			task.defer(function() self:_sync(player) end)
		end))
		self._trove:Add(garage:getSignal("CarParked"):Connect(function(player, _body, _tier, bay)
			self:_parked(player, bay)
		end))
		local race = Shard.get("RaceService")
		if race then
			self._trove:Add(race:getSignal("RaceEntered"):Connect(function(player)
				self._awayPlayers[player] = true
				self:_publish(player, self._flows[player], false)
			end))
			self._trove:Add(race:getSignal("ReturnedHome"):Connect(function(player)
				self._awayPlayers[player] = nil
				task.defer(function() self:_sync(player) end)
			end))
		end
		self._trove:Add(Players.PlayerRemoving:Connect(function(player)
			local state = self._flows[player]
			if state and not state.done then self:_event(player, state, "LeftBeforePlacement", { carrying = garage:getCarriedCar(player) ~= nil }) end
			self._flows[player], self._protected[player], self._awayPlayers[player] = nil, nil, nil
			self._tutorial[player], self._resumed[player] = nil, nil
		end))
		local accumulated = 0
		self._trove:Add(RunService.Heartbeat:Connect(function(dt)
			accumulated += dt
			if accumulated < 0.5 then return end
			accumulated = 0
			for _, player in Players:GetPlayers() do self:_sync(player) end
		end))
	end,
})
Service:withCleanup(function() if Service._trove then Service._trove:Destroy() end end)
return Service

