--[[
	WorldProgressController  (client)
	---------------------------------
	"How far down this road you are, and what its end gets you" (2026-10-20, the owner: "to unlock next
	worlds you need to travel through the entire world to get 100% progression right but a player
	wouldnt really know that"). `WorldConfig.ProgressCard` has the words and the timing.

	WHEN: back in the lobby after a run that RAISED your best in the world you drove, when the next
	world asks for that road (`WorldConfig.requiredProgressFor`) and you do not own it yet. A run that
	did not beat your best says nothing: the card is about progress, and the same number twice is noise.

	WHAT: a card in the left notice lane, "DESERT: 62% DRIVEN" over "Drive to the END of Desert to
	unlock Forest" and a bar. The run that reaches the requirement gets "DESERT COMPLETE!" instead.
	Takes no input and goes by itself after `Hold`.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local NoticeLaneConfig = require(ReplicatedStorage.shared.Configs.NoticeLaneConfig)
local RaceConfig = require(ReplicatedStorage.shared.Configs.RaceConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local ArcadeKit = require(ReplicatedStorage.shared.Modules.ArcadeKit)
local NoticeLane = require(ReplicatedStorage.shared.Modules.NoticeLane)

local WorldProgressController = Shard.new("WorldProgressController")

--- The showroom summary's card rule, so the lane's cards are one width (`ShowroomSummaryController`).
local CARD_SIZE = UDim2.fromScale(0.22, 1)
local MIN_WIDTH, MAX_WIDTH = 220, 360
local ASPECT = 3.4
local HEADER = 0.4
local BAR_BACK = Color3.fromRGB(2, 30, 56)

function WorldProgressController._build(self)
	local gui = Instance.new("ScreenGui")
	gui.Name = "WorldProgress"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Size = CARD_SIZE
	card.Position = UDim2.fromScale(0.5, 0.04)
	card.BackgroundTransparency = 1
	card.Visible = false
	card.Parent = gui
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = ASPECT
	ratio.DominantAxis = Enum.DominantAxis.Width
	ratio.Parent = card
	local bounds = Instance.new("UISizeConstraint")
	bounds.MinSize = Vector2.new(MIN_WIDTH, 0)
	bounds.MaxSize = Vector2.new(MAX_WIDTH, math.huge)
	bounds.Parent = card

	local _, title, body = ArcadeKit.panel(card, HEADER, ASPECT)
	self._title = title
	self._line = ArcadeKit.text(body, 0.05, 0.06, 0.9, 0.46, ArcadeKit.White, true)

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.fromScale(0.08, 0.6)
	track.Size = UDim2.fromScale(0.84, 0.24)
	track.BackgroundColor3 = BAR_BACK
	track.BorderSizePixel = 0
	track.ZIndex = self._line.ZIndex
	track.Parent = body
	Instance.new("UICorner", track).CornerRadius = UDim.new(0.5, 0)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = ArcadeKit.Faces.Green[1]
	fill.BorderSizePixel = 0
	fill.ZIndex = track.ZIndex + 1
	fill.Parent = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0.5, 0)
	self._fill = fill

	self._gui, self._card = gui, card
	if NoticeLaneConfig.Enabled then
		self._lane = NoticeLane.join(card, NoticeLaneConfig.Order.WorldProgress, true, ASPECT)
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

--[[ The card for the run that just ended, or nothing. `before` is the world's fraction when the run
	started; the server writes the new best when the run settles, which is before the lobby is back. ]]
function WorldProgressController._afterRun(self, world: number, before: number)
	local cfg = WorldConfig.ProgressCard
	local player = Players.LocalPlayer
	local nextWorld = world + 1
	local required = WorldConfig.Worlds[nextWorld] and WorldConfig.requiredProgressFor(nextWorld)
	if not (required and self._card) or WorldConfig.highestUnlocked(player) >= nextWorld then
		return
	end
	local now = WorldConfig.progressOf(player, world)
	if now <= before then
		return
	end

	local here, there = WorldConfig.displayName(world), WorldConfig.displayName(nextWorld)
	local done = now >= required - WorldConfig.ProgressEpsilon
	if done then
		self._title.Text = string.format(cfg.DoneTitle, string.upper(here))
		self._line.Text = string.format(cfg.DoneText, there)
	else
		self._title.Text = string.format(cfg.Title, string.upper(here), string.format("%d%%", math.floor(now * 100)))
		self._line.Text = string.format(cfg.Text, here, there)
	end
	self._fill.Size = UDim2.fromScale(math.clamp(now / required, 0, 1), 1)

	self._token += 1
	local token = self._token
	local card = self._card
	local function hide()
		if token ~= self._token then
			return
		end
		if self._lane then
			self._lane:hide(function()
				if token == self._token then
					card.Visible = false
				end
			end)
		else
			card.Visible = false
		end
	end
	if self._lane then
		--- The hold starts when it is really up: a full lane makes it wait its turn.
		self._lane:show(function()
			card.Visible = true
			task.delay(cfg.Hold, hide)
		end)
	else
		card.Visible = true
		task.delay(cfg.Hold, hide)
	end
end

WorldProgressController:withRemoteEvents({
	{
		RaceStart = function()
			local self = WorldProgressController
			local world = WorldConfig.resolve(Players.LocalPlayer:GetAttribute(WorldConfig.WorldAttribute))
			self._run = { world = world, before = WorldConfig.progressOf(Players.LocalPlayer, world) }
			--- A run starting takes a card on screen away; it cannot be read under the road.
			self._token += 1
			if self._card then
				if self._lane then
					local card = self._card
					self._lane:hide(function()
						card.Visible = false
					end)
				else
					self._card.Visible = false
				end
			end
		end,
	},
})

WorldProgressController:withLifecycle({
	init = function(self)
		self._token = 0
		self._run = nil :: { world: number, before: number }?
	end,

	start = function(self)
		if not WorldConfig.ProgressCard.Enabled then
			return
		end
		task.spawn(function()
			self:_build()
		end)
		Dispatcher:Subscribe(RaceConfig.ReturnedEvent, function()
			local run = self._run
			self._run = nil
			if not run then
				return
			end
			task.delay(WorldConfig.ProgressCard.Delay, function()
				self:_afterRun(run.world, run.before)
			end)
		end)
	end,
})

return WorldProgressController
