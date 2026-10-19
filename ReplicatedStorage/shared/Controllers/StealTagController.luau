--[[
	StealTagController  (client)
	----------------------------
	The price tag that pops up over a car you just stole: what it is worth, on a small pill in the
	kit's gradient for its rarity, and nothing else. `StealTagConfig` has the design and every number;
	`StealController._notifyStolen` publishes `CarStolen` (body, paint, mutation, tier) on the frame
	the handoff lands.

	ONE TAG, REBUILT PER STEAL. Steals are seconds apart at the fastest, so building the pill fresh
	costs nothing worth pooling, and it means a fade never has to be undone: the kit's parts carry
	authored transparencies (the checker's tint, the rims) that a fade-in would have to remember.

	IT IS A BILLBOARD ON THE CAR'S HITBOX, parented to PlayerGui so it belongs to this client and
	dies with nothing but this file. The lift is measured off the car each time, the way
	`CarHudController` measures the HP bar's, because a steal changes the body under you and the
	bodies run 6.1 to 7.0 studs tall. `StudsOffset` is camera space, so the tag stays upright on the
	screen while the car leans into a lane change.

	Hide UI (`InterfaceConfig.Attribute` on PlayerGui) only hides ScreenGuis, so this checks it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local InterfaceConfig = require(ReplicatedStorage.shared.Configs.InterfaceConfig)
local MarketValueConfig = require(ReplicatedStorage.shared.Configs.MarketValueConfig)
--- Whether the toast has taken the price over (`StealJuiceConfig.OneMoment.MergeValue`).
local StealJuiceConfig = require(ReplicatedStorage.shared.Configs.StealJuiceConfig)
local StealTagConfig = require(ReplicatedStorage.shared.Configs.StealTagConfig)
local ArcadeKit = require(ReplicatedStorage.shared.Modules.ArcadeKit)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)

local StealTagController = Shard.new("StealTagController")

local NAME = "StealTag"

--- The car's HitBox, or nil while it has not replicated (it lands after the model, see the HP bar).
local function hitBoxOf(car: Model?): BasePart?
	local box = car and car:FindFirstChild("HitBox", true)
	return if box and box:IsA("BasePart") then box else nil
end

--- Studs from the HitBox's centre to the roof, projected onto world up (see `CarHudController._liftFor`).
local function roofOf(car: Model, hitBox: BasePart): number
	local ok, cf, size = pcall(function()
		return car:GetBoundingBox()
	end)
	if not (ok and typeof(cf) == "CFrame" and typeof(size) == "Vector3") then
		return hitBox.Size.Y * 0.5
	end
	local top = cf.Position + cf.UpVector * (size.Y * 0.5)
	return math.max((top - hitBox.Position):Dot(Vector3.yAxis), 0)
end

--- `StealTagConfig.PhoneScale` on a small screen, else 1.
local function screenScale(): number
	local viewport = workspace.CurrentCamera.ViewportSize
	return if math.min(viewport.X, viewport.Y) < StealTagConfig.PhoneBelow then StealTagConfig.PhoneScale else 1
end

function StealTagController._build(self, car: Model, hitBox: BasePart, body: string)
	local cfg = StealTagConfig
	local width = cfg.Width * screenScale()
	local height = width / cfg.Aspect

	local gui = Instance.new("BillboardGui")
	gui.Name = NAME
	gui.Adornee = hitBox
	gui.Size = UDim2.fromScale(width, height)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	--- The kit's parts are layered for Sibling; a new BillboardGui defaults to Global.
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local lift = roofOf(car, hitBox) + cfg.Clearance + height * 0.5
	gui.StudsOffset = Vector3.new(0, lift - cfg.Rise, 0)

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local pop = Instance.new("UIScale")
	pop.Scale = 0.5
	pop.Parent = holder

	--- The rarity is the pill's colour and nothing more: the value is the one thing to read.
	local _, band = CarRarity.of(body)
	local face = ArcadeKit.card(holder, { aspect = cfg.Aspect, face = ArcadeKit.rarityFace(band), corner = 0.5, sunray = false })

	local price = ArcadeKit.text(face, 0.1, 0.16, 0.8, 0.68, ArcadeKit.White, true)
	price.Name = "Value"
	price.Text = GarageConfig.formatCash(0)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui, pop, price, lift
end

function StealTagController._show(self, body: unknown, mutation: unknown)
	if type(body) ~= "string" then
		return
	end
	self:_clear()
	local token = self._token
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui and playerGui:GetAttribute(InterfaceConfig.Attribute) then
		return
	end
	local road = Shard.get("RoadController")
	local car = road and road:getCar()
	local hitBox = hitBoxOf(car)
	if not (car and hitBox) then
		return
	end

	local cfg = StealTagConfig
	local mutationKey = if type(mutation) == "string" and mutation ~= "" then mutation else nil
	--- Priced off `TierOfBody`, the same lookup the sell lot makes (`SellConfig.lotPriceOf`).
	local value = MarketValueConfig.valueOf(GarageConfig.TierOfBody[body], mutationKey)
	local gui, pop, price, lift = self:_build(car :: Model, hitBox :: BasePart, body)
	self._gui = gui

	TweenService:Create(pop, TweenInfo.new(cfg.PopTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(gui, TweenInfo.new(cfg.PopTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, lift, 0),
	}):Play()

	--- The value counts up to its figure: a beat to read it land rather than a number that is just there.
	local counter = Instance.new("NumberValue")
	counter.Changed:Connect(function(current)
		price.Text = GarageConfig.formatCash(math.round(current))
	end)
	TweenService:Create(counter, TweenInfo.new(cfg.CountTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, cfg.PopTime * 0.5), {
		Value = value,
	}):Play()

	task.delay(cfg.PopTime + cfg.Hold, function()
		if self._token ~= token then
			counter:Destroy()
			return -- a newer steal or the end of the run took it
		end
		ArcadeKit.fade(gui, cfg.FadeTime)
		TweenService:Create(pop, TweenInfo.new(cfg.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.85 }):Play()
		task.delay(cfg.FadeTime, function()
			counter:Destroy()
			if self._token == token then
				self:_clear()
			end
		end)
	end)
end

function StealTagController._clear(self)
	self._token += 1
	if self._gui then
		self._gui:Destroy()
		self._gui = nil
	end
end

StealTagController:withRemoteEvents({
	{
		RaceEnd = function()
			StealTagController:_clear()
		end,
	},
})

StealTagController:withLifecycle({
	init = function(self)
		self._token = 0
	end,

	start = function(self)
		if not StealTagConfig.Enabled then
			return
		end
		Dispatcher:Subscribe("CarStolen", function(body, _paint, mutation)
			--- The toast carries the price now (`StealJuiceConfig.OneMoment.MergeValue`): one card, not two.
			if StealJuiceConfig.oneMoment("MergeValue") then
				return
			end
			--- Spawned: the kit's shelf can still be on its way in, and `ArcadeKit.shelf` waits for it.
			task.spawn(function()
				self:_show(body, mutation)
			end)
		end)
	end,
})

return StealTagController
