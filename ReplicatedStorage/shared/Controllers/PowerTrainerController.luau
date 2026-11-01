--[[ PowerTrainerController — the kiddie ride's bounce and the "+⚡" pops

	`PowerTrainerService` builds the rides and pays the ⚡; this is the cosmetic half. A ride with somebody
	on it bobs and rocks like a coin-op car (its `Car` model only, moved locally every frame: anchored
	parts, so nothing replicates and the rider, welded to the seat, goes along). While YOU ride, each
	gain floats up as "+0.2 ⚡" over your head. ]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local CollectorConfig = require(ReplicatedStorage.shared.Configs.CollectorConfig)

local Controller = Shard.new("PowerTrainerController")

local TAG = "KiddieRide"
local BOB_HEIGHT = 0.35 -- studs
local BOB_RATE = 2.2 -- bounces a second
local ROCK = math.rad(5)

type Ride = { car: Model, rest: CFrame, seat: Seat, moved: boolean? }

function Controller._track(self, model: Instance)
	local car = model:WaitForChild("Car", 10)
	local seat = car and car:FindFirstChild("Seat")
	if car and car:IsA("Model") and seat and seat:IsA("Seat") then
		self._rides[model] = { car = car, rest = car:GetPivot(), seat = seat }
	end
end

function Controller._pop(self, amount: number)
	local character = self._player.Character
	local head = character and character:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(4, 1.4)
	gui.StudsOffsetWorldSpace = Vector3.new(math.random(-10, 10) / 10, 2.5, 0)
	gui.LightInfluence = 0
	gui.Adornee = head
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 220, 60)
	label.Text = string.format("+%s ⚡", if amount >= 10 then tostring(math.floor(amount)) else string.format("%.1f", amount))
	Instance.new("UIStroke", label).Thickness = 2
	label.Parent = gui
	gui.Parent = self._player:WaitForChild("PlayerGui")
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffsetWorldSpace = gui.StudsOffsetWorldSpace + Vector3.new(0, 2.5, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	task.delay(1, function()
		gui:Destroy()
	end)
end

function Controller._riding(self): boolean
	local character = self._player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	return seat ~= nil and seat:IsDescendantOf(workspace) and seat.Parent ~= nil
		and seat.Parent.Parent ~= nil and CollectionService:HasTag(seat.Parent.Parent, TAG)
end

Controller:withLifecycle({
	init = function(self)
		self._player = Players.LocalPlayer
		self._rides = {} :: { [Instance]: Ride }
	end,

	start = function(self)
		if not CollectorConfig.Enabled then
			return
		end
		CollectionService:GetInstanceAddedSignal(TAG):Connect(function(model)
			task.spawn(self._track, self, model)
		end)
		CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(model)
			self._rides[model] = nil
		end)
		for _, model in CollectionService:GetTagged(TAG) do
			task.spawn(self._track, self, model)
		end

		local last = CollectorConfig.powerOf(self._player)
		self._player:GetAttributeChangedSignal(CollectorConfig.Power.Attribute):Connect(function()
			local now = CollectorConfig.powerOf(self._player)
			if now > last and self:_riding() then
				self:_pop(now - last)
			end
			last = now
		end)

		RunService.RenderStepped:Connect(function()
			local t = os.clock()
			for model, ride in self._rides do
				if not ride.car.Parent then
					self._rides[model] = nil
				elseif ride.seat.Occupant then
					local phase = t * BOB_RATE * math.pi * 2
					local lift = math.abs(math.sin(phase)) * BOB_HEIGHT
					ride.car:PivotTo(ride.rest * CFrame.new(0, lift, 0) * CFrame.Angles(math.sin(phase * 0.5) * ROCK, 0, 0))
					ride.moved = true
				elseif ride.moved then
					ride.car:PivotTo(ride.rest)
					ride.moved = nil
				end
			end
		end)
	end,
})

return Controller
