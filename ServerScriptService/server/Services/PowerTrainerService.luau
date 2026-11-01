--[[
	PowerTrainerService  (server)
	-----------------------------
	⚡ Steal Power, the stat every car is gated on (`CollectorConfig.Power`), and the KIDDIE RIDE that
	trains it: a coin-op bouncing car at each plot. Sit on it and ⚡ rises by
	`CollectorConfig.rateAt(trainer level)` every second, AFK included — the reference's toy horse.

	OWNS THE NUMBER. Loaded off the profile on `ProfileReady` (absent = `Power.Start`, so an old
	profile simply starts there), written back on every tick it changes, and published as the
	`StealPower` attribute that everything else reads (`CollectorConfig.powerOf`). Nothing else writes
	it, and nothing a client sends can: the only input is "is this player's humanoid in a ride seat",
	which the server sees for itself.

	The ride is built here, server-side and anchored, so everybody sees everybody riding. The bounce is
	the client's (`PowerTrainerController`), because a per-frame CFrame on six rides is replication
	traffic for a purely cosmetic wobble.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local CollectorConfig = require(ReplicatedStorage.shared.Configs.CollectorConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local UpgradeConfig = require(ReplicatedStorage.shared.Configs.UpgradeConfig)
local Data = require(script.Parent.Parent.Data)

local Service = Shard.new("PowerTrainerService"):withDependencies({ "GarageService" })

local TAG = "KiddieRide"
--- Where the ride stands in a plot's own frame (`Origin`): measured clear on every lot, ~20 studs
--- from the spawn pad so a new player sees it on arrival (Studio overlap check, 2026-11-01).
local LOCAL_SPOT = CFrame.new(20, 1.43, -25)

-- === The ride ================================================================

local function part(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new(props.Shape and "Part" or (props.ClassName or "Part"))
	props.ClassName = nil
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

--[[ A cartoon car on a spring over a round coin-op base, all parts. Built in the ride's own frame
	(nose along -Z) and placed with `at`. The car's parts sit in a `Car` model, the one thing the client
	bounces; the seat is inside it so the rider bounces too. ]]
function Service._buildRide(self, at: CFrame, plotName: string): Model
	local model = Instance.new("Model")
	model.Name = "KiddieRide"
	model:SetAttribute("Plot", plotName)

	local function place(p: BasePart, offset: CFrame)
		p.CFrame = at * offset
	end

	local base = part(model, { Name = "Base", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 11, 11),
		Color = Color3.fromRGB(255, 196, 40) })
	place(base, CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)))
	local rim = part(model, { Name = "Rim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.1, 9.4, 9.4),
		Color = Color3.fromRGB(235, 64, 64) })
	place(rim, CFrame.new(0, 0.52, 0) * CFrame.Angles(0, 0, math.rad(90)))

	-- The coin box at the front, with the slot and a ⚡ sign.
	local box = part(model, { Name = "CoinBox", Size = Vector3.new(2.4, 3.6, 1.6), Color = Color3.fromRGB(60, 120, 255) })
	place(box, CFrame.new(0, 2.8, -4.4))
	local slot = part(model, { Name = "Slot", Size = Vector3.new(0.9, 0.18, 0.2), Color = Color3.fromRGB(20, 20, 30),
		Material = Enum.Material.Metal })
	place(slot, CFrame.new(0, 3.6, -5.22))

	local car = Instance.new("Model")
	car.Name = "Car"
	car.Parent = model
	local spring = part(car, { Name = "Spring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 0.8, 0.8),
		Color = Color3.fromRGB(180, 180, 190), Material = Enum.Material.Metal })
	place(spring, CFrame.new(0, 1.7, 0.4) * CFrame.Angles(0, 0, math.rad(90)))
	local body = part(car, { Name = "Body", Size = Vector3.new(3.6, 1.6, 6.4), Color = Color3.fromRGB(235, 52, 70) })
	place(body, CFrame.new(0, 3.1, 0.4))
	local hood = part(car, { Name = "Hood", Size = Vector3.new(3.4, 0.5, 2), Color = Color3.fromRGB(255, 90, 100) })
	place(hood, CFrame.new(0, 4.1, -1.7))
	local windscreen = part(car, { Name = "Windscreen", Size = Vector3.new(3.2, 1.3, 0.25), Color = Color3.fromRGB(150, 220, 255),
		Material = Enum.Material.Glass, Transparency = 0.25 })
	place(windscreen, CFrame.new(0, 4.6, -0.6) * CFrame.Angles(math.rad(-20), 0, 0))
	for _, x in { -1.9, 1.9 } do
		for _, z in { -1.8, 2.6 } do
			local wheel = part(car, { Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 1.6, 1.6),
				Color = Color3.fromRGB(30, 30, 36) })
			place(wheel, CFrame.new(x, 2.4, z))
		end
	end
	for _, x in { -1.2, 1.2 } do
		local lamp = part(car, { Name = "Headlight", Size = Vector3.new(0.7, 0.5, 0.2), Color = Color3.fromRGB(255, 240, 150),
			Material = Enum.Material.Neon })
		place(lamp, CFrame.new(x, 3.3, -2.85))
	end
	local seat = part(car, { ClassName = "Seat", Name = "Seat", Size = Vector3.new(2.4, 0.4, 2.2),
		Color = Color3.fromRGB(40, 40, 50) })
	place(seat, CFrame.new(0, 4.1, 1.4))

	-- A ProximityPrompt as well as touch-to-sit: on a phone, walking into a small seat is fiddly.
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Ride"
	prompt.ObjectText = "Train ⚡ Steal Power"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = seat
	prompt.Triggered:Connect(function(player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and not (seat :: Seat).Occupant then
			(seat :: Seat):Sit(humanoid)
		end
	end)
	;(seat :: Seat):GetPropertyChangedSignal("Occupant"):Connect(function()
		prompt.Enabled = (seat :: Seat).Occupant == nil
	end)

	-- The sign: what it is and that sitting is the whole instruction.
	local sign = Instance.new("BillboardGui")
	sign.Name = "Sign"
	sign.Size = UDim2.fromScale(9, 3)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0)
	sign.MaxDistance = 90
	sign.LightInfluence = 0
	sign.Adornee = box
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.55)
	title.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 220, 60)
	title.Text = "⚡ KIDDIE RIDE"
	Instance.new("UIStroke", title).Thickness = 2.5
	title.Parent = sign
	local sub = title:Clone()
	sub.Position = UDim2.fromScale(0, 0.58)
	sub.Size = UDim2.fromScale(1, 0.38)
	sub.TextColor3 = Color3.new(1, 1, 1)
	sub.Text = "Sit to train Steal Power"
	sub.Parent = sign
	sign.Parent = box

	model.PrimaryPart = base
	CollectionService:AddTag(model, TAG)
	return model
end

function Service._buildAll(self)
	local folder = workspace:FindFirstChild("KiddieRides")
	if folder then
		folder:ClearAllChildren()
	else
		folder = Instance.new("Folder")
		folder.Name = "KiddieRides"
		folder.Parent = workspace
	end
	local plots = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Plots")
	local built = 0
	for _, plot in if plots then plots:GetChildren() else {} do
		local origin = plot:FindFirstChild("Origin")
		if origin and origin:IsA("BasePart") then
			local ride = self:_buildRide(origin.CFrame * LOCAL_SPOT, plot.Name)
			ride.Name = "KiddieRide_" .. plot.Name
			ride.Parent = folder
			built += 1
		end
	end
	self.log:info(string.format("%d kiddie ride(s) built.", built))
end

-- === ⚡ ========================================================================

function Service._profile(self, player: Player)
	local profile = self._profiles[player]
	return if profile and profile:IsActive() then profile else nil
end

--- Read once at load: a number, or `Start` for a profile that has never trained (every old one).
function Service._load(self, player: Player)
	local profile = self:_profile(player)
	if not profile then
		return
	end
	local stored = profile:Get({ GarageConfig.Keys.Garage, CollectorConfig.Power.ProfileKey })
	local value = if type(stored) == "number" and stored == stored and stored >= 0 then stored else CollectorConfig.Power.Start
	self._power[player] = math.max(value, CollectorConfig.Power.Start)
	player:SetAttribute(CollectorConfig.Power.Attribute, self._power[player])
end

--- Public: add ⚡. The ride is the only caller today; an admin command or a reward could be next.
function Service.addPower(self, player: Player, amount: number)
	local current = self._power[player]
	local profile = self:_profile(player)
	if not (current and profile) or not (amount > 0) then
		return
	end
	local value = current + amount
	self._power[player] = value
	profile:Set({ GarageConfig.Keys.Garage, CollectorConfig.Power.ProfileKey }, value)
	player:SetAttribute(CollectorConfig.Power.Attribute, value)
end

--- The rider of a ride seat, if it is a player.
local function riderOf(seat: Seat): Player?
	local humanoid = seat.Occupant
	local character = humanoid and humanoid.Parent
	return character and Players:GetPlayerFromCharacter(character)
end

function Service._tick(self)
	local Garage = Shard.get("GarageService")
	for _, ride in CollectionService:GetTagged(TAG) do
		local seat = ride:FindFirstChild("Seat", true)
		local player = seat and seat:IsA("Seat") and riderOf(seat)
		if player then
			local level = UpgradeConfig.levelOf(Garage:getUpgrades(player), CollectorConfig.Trainer.UpgradeKey)
			self:addPower(player, CollectorConfig.rateAt(level) * CollectorConfig.Trainer.TickSeconds)
		end
	end
end

-- === Lifecycle ===============================================================

Service:withLifecycle({
	init = function(self)
		self._profiles = {}
		self._power = {} :: { [Player]: number }
	end,

	start = function(self)
		if not CollectorConfig.Enabled then
			return
		end
		self:_buildAll()

		local Garage = Shard.get("GarageService")
		-- The profile handle, off `ProfileReady` — `DailyRewardService`'s pattern.
		Garage:getSignal("ProfileReady"):Connect(function(player: Player)
			task.spawn(function()
				local ok, profile = pcall(function()
					return Data:GetProfileAsync(player)
				end)
				if ok and profile and player.Parent == Players then
					self._profiles[player] = profile
					self:_load(player)
				end
			end)
		end)
		Players.PlayerRemoving:Connect(function(player)
			self._profiles[player] = nil
			self._power[player] = nil
		end)

		local acc = 0
		RunService.Heartbeat:Connect(function(dt)
			acc += dt
			if acc >= CollectorConfig.Trainer.TickSeconds then
				acc -= CollectorConfig.Trainer.TickSeconds
				self:_tick()
			end
		end)
	end,
})

return Service
