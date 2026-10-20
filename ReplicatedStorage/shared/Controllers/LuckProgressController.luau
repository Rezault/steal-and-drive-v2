--[[
	LuckProgressController  (client)
	-------------------------------
	2026-10-12: Celebrate the road sections already improving rare-car odds. These are the same
	road progression as RaceUIController, capped at TrafficConfig.topTileFor.
	Six visible milestones now cover twelve tiles, so the first tile earns no popup. This is a
	readout of the existing TrafficConfig.rungWeight ramp, never an extra luck multiplier.

	TileIndex survives road rebases and stealing into another car; accumulated position deltas
	would mistake either teleport for progress. Each milestone appears once per run, including
	across revives. A jump over several tiles shows only the latest, rather than queueing spam.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GameplayFeedback = require(ReplicatedStorage.shared.Modules.GameplayFeedback)
local Shard = require(ReplicatedStorage.Packages.Shard)
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local ArcadeKit = require(ReplicatedStorage.shared.Modules.ArcadeKit)

local LuckProgressController = Shard.new("LuckProgressController")

-- A short slide/fade makes the milestone noticeable without covering the driving view for long.
local ENTER = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local LEAVE = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
--[[ Pixels of clear space round the card inside the fading CanvasGroup. A CanvasGroup clips to its
	own rectangle, and the kit card's navy rim draws OUTSIDE the face, so a group the card's exact
	size cut the rim off and left dark square corners (Dylan, 2026-10-17: "it might not be rounded").
	The rim is 0.02 of the card's height, under 2px at the 92px cap. ]]
local RIM_ROOM = 4
local SHOWN = UDim2.fromOffset(-RIM_ROOM, -RIM_ROOM)

function LuckProgressController._build(self)
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoadLuckProgress"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 905
	gui.Enabled = false
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0, 0)
	holder.Position = TrafficConfig.LuckProgress.Position
	holder.Size = UDim2.fromScale(0.30, 0.09)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local bounds = Instance.new("UISizeConstraint")
	bounds.MinSize = Vector2.new(240, 74)
	bounds.MaxSize = Vector2.new(340, 92)
	bounds.Parent = holder
	local group = Instance.new("CanvasGroup")
	group.Position = SHOWN
	group.Size = UDim2.new(1, RIM_ROOM * 2, 1, RIM_ROOM * 2)
	group.BackgroundTransparency = 1
	group.Parent = holder
	local card = Instance.new("Frame")
	card.Position = UDim2.fromOffset(RIM_ROOM, RIM_ROOM)
	card.Size = UDim2.new(1, -RIM_ROOM * 2, 1, -RIM_ROOM * 2)
	card.BackgroundTransparency = 1
	card.Parent = group
	-- No fixed aspect: the size constraint makes the card anywhere from 3.7 to 4.6 wide, so the
	-- checker is fitted to the shape it actually has.
	local face = ArcadeKit.card(card, { face = ArcadeKit.Faces.Green, sunray = false })
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Image = "rbxassetid://" .. UIAssets.Upgrades.Icons.Luck
	icon.Size = UDim2.fromScale(0.16, 0.7)
	icon.Position = UDim2.fromScale(0.035, 0.12)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 4
	icon.Parent = face
	self._title = ArcadeKit.text(face, 0.21, 0.08, 0.75, 0.32, ArcadeKit.White, true)
	self._detail = ArcadeKit.text(face, 0.21, 0.42, 0.75, 0.22, ArcadeKit.White, true)
	local pips = Instance.new("Frame")
	pips.BackgroundTransparency = 1
	pips.Position = UDim2.fromScale(0.23, 0.73)
	pips.Size = UDim2.fromScale(0.71, 0.12)
	pips.ZIndex = 4
	pips.Parent = face
	self._pips = pips
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self._gui, self._group = gui, group
end

function LuckProgressController._hide(self)
	if self._hideTask then
		task.cancel(self._hideTask)
		self._hideTask = nil
	end
	if self._tween then
		self._tween:Cancel()
		self._tween = nil
	end
	if self._gui then self._gui.Enabled = false end
end

function LuckProgressController._show(self, reached: number, top: number)
	self:_hide()
	self._title.Text = if reached == top then "MAX ROAD LUCK!" else "LUCK INCREASED!"
	self._detail.Text = if reached == top then "Best rare-car odds on this road!" else "Better odds of rare cars ahead!"
	for _, pip in self._pips:GetChildren() do pip:Destroy() end
	for index = 1, top do
		local pip = Instance.new("Frame")
		pip.Size = UDim2.fromScale(0.9 / top, 1)
		pip.Position = UDim2.fromScale((index - 1) / top, 0)
		pip.BackgroundColor3 = if index <= reached then ArcadeKit.Gold else ArcadeKit.Navy
		pip.BorderSizePixel = 0
		pip.ZIndex = 4
		pip.Parent = self._pips
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.3, 0)
		corner.Parent = pip
	end
	self._gui.Enabled = true
	self._group.GroupTransparency = 1
	self._group.Position = SHOWN - UDim2.fromOffset(0, 12)
	self._tween = TweenService:Create(self._group, ENTER, {
		GroupTransparency = 0, Position = SHOWN,
	})
	self._tween:Play()
	self._hideTask = task.delay(TrafficConfig.LuckProgress.Hold, function()
		self._hideTask = nil
		self._tween = TweenService:Create(self._group, LEAVE, { GroupTransparency = 1 })
		self._tween:Play()
	end)
end

--- Public (PoliceHudController): the card's bottom edge in `AbsolutePosition` space while it is up
--- (or still fading out), else nil. The heat stars share its corner and slide under it.
function LuckProgressController.bottom(self): number?
	if not (self._gui and self._gui.Enabled and self._group.GroupTransparency < 0.95) then
		return nil
	end
	return self._group.AbsolutePosition.Y + self._group.AbsoluteSize.Y
end

-- Reversing or a revive must not celebrate a tile twice.
function LuckProgressController._advance(self, tile: number, top: number)
	if top <= 0 then return end
	local steps = math.max(1, math.floor(TrafficConfig.LuckProgress.Steps or 6))
	local reached = math.clamp(math.floor(math.max(tile, 0) / top * steps), 0, steps)
	if reached <= self._reached then return end
	self._reached = reached
	GameplayFeedback.play("LuckRaised")
	self:_show(reached, steps)
end

function LuckProgressController._step(self)
	if not (self._racing and self._live and self._gui and self._road) then return end
	local road = self._road
	local info, car = road:getRoadInfo(), road:getCar()
	if not (info and info.segmentLength > 0 and car and car.Parent and car.PrimaryPart) then return end
	local top = TrafficConfig.topTileFor(info.world)
	local steps = math.max(1, math.floor(TrafficConfig.LuckProgress.Steps or 6))
	if not top or self._reached >= steps then return end
	local along = road:along(car.PrimaryPart.Position)
	for _, tile in road:getSegments() do
		if tile.Parent then
			local start = road:along(tile:GetPivot().Position)
			if along >= start and along < start + info.segmentLength then
				local index = tile:GetAttribute("TileIndex")
				if type(index) == "number" then self:_advance(index, top) end
				return
			end
		end
	end
end

function LuckProgressController._pause(self)
	self._live = false
	self:_hide()
end

LuckProgressController:withRemoteEvents({ {
	RaceStart = function()
		LuckProgressController:_pause()
		LuckProgressController._reached = 0
		-- The tutorial deals scripted cars instead of rolling the distance odds ramp.
		LuckProgressController._racing = not TutorialConfig.isTutorialRun(
			Players.LocalPlayer:GetAttribute(TutorialConfig.StepAttribute)
		)
	end,
	RaceLive = function() LuckProgressController._live = LuckProgressController._racing end,
	RaceRevived = function() LuckProgressController._live = LuckProgressController._racing end,
	RaceWrecked = function() LuckProgressController:_pause() end,
	RaceEndPanel = function() LuckProgressController:_pause() end,
	RaceEnd = function()
		LuckProgressController._racing = false
		LuckProgressController:_pause()
	end,
} })

LuckProgressController:withLifecycle({
	init = function(self)
		self._racing, self._live, self._reached = false, false, 0
	end,
	start = function(self)
		if not TrafficConfig.LuckProgress.Enabled then return end
		self._road = Shard.get("RoadController")
		task.spawn(function() self:_build() end)
		-- Five checks per second over the small live tile ring, never a workspace scan.
		local elapsed = 0
		self._conn = RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed < 0.2 then return end
			elapsed = 0
			self:_step()
		end)
	end,
})

LuckProgressController:withCleanup(function()
	LuckProgressController:_pause()
	if LuckProgressController._conn then LuckProgressController._conn:Disconnect() end
	if LuckProgressController._gui then LuckProgressController._gui:Destroy() end
end)

return LuckProgressController
