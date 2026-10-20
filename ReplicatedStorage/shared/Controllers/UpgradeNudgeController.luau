--[[
	UpgradeNudgeController  (client)
	--------------------------------
	A contextual tutorial for the first upgrade (2026-10-20, Aleafo: "after a player earns 5k can we do a
	contextual tutorial which shows players hey go to upgrades and spend ur money (if they haven't gone to
	upgrades yet)"). `UpgradeConfig.Nudge` has the numbers and the words.

	WHEN: the tutorial is over, the player holds at least `Nudge.Cash`, has never bought an upgrade (every
	level on `UpgradeConfig.Attribute` is 0), is in the lobby, and is not carrying a car (the carry has
	its own card and its own line to a bay). Asked once a second.

	WHAT: a card in the left notice lane saying what to do, and the green guide line from the player to
	their own Upgrades cabinet (`GuideTrailController.pointAt`, the line the tutorial points at its buyer
	with). Upgrades have no HUD button: the cabinet's prompt is the only door (`UpgradeConfig.Machine`).

	UNTIL: the Upgrades page opens, which ends it for the session; buying anything ends it for good,
	because the levels stop being all zero. Nothing is saved for it, and nothing needs to be.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local CarryConfig = require(ReplicatedStorage.shared.Configs.CarryConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local NoticeLaneConfig = require(ReplicatedStorage.shared.Configs.NoticeLaneConfig)
local PlotConfig = require(ReplicatedStorage.shared.Configs.PlotConfig)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local UpgradeConfig = require(ReplicatedStorage.shared.Configs.UpgradeConfig)
local ArcadeKit = require(ReplicatedStorage.shared.Modules.ArcadeKit)
local NoticeLane = require(ReplicatedStorage.shared.Modules.NoticeLane)

local UpgradeNudgeController = Shard.new("UpgradeNudgeController")

--- The showroom summary's card rule, so the lane's cards are one width (`ShowroomSummaryController`).
local CARD_SIZE = UDim2.fromScale(0.22, 1)
local MIN_WIDTH, MAX_WIDTH = 220, 360
local ASPECT = 3.4
local HEADER = 0.4

function UpgradeNudgeController._build(self)
	local gui = Instance.new("ScreenGui")
	gui.Name = "UpgradeNudge"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

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
	title.Text = UpgradeConfig.Nudge.Title
	local line = ArcadeKit.text(body, 0.05, 0.12, 0.9, 0.76, ArcadeKit.White, true)
	self._line = line

	self._gui, self._card = gui, card
	if NoticeLaneConfig.Enabled then
		self._lane = NoticeLane.join(card, NoticeLaneConfig.Order.UpgradeNudge, true, ASPECT)
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

--[[ This player's own Upgrades cabinet, as a part to point the line at: their plot under `Plots` (the
	one carrying their `OwnerUserId`), its `Upgrades` model by name (`UpgradeConfig.Machine.ModelName`),
	and that model's PrimaryPart or its first part. WAS found through the tagged prompt, which sits on an
	attachment inside the model, not on a part, so it came back empty (2026-10-20: "no Upgrades machine
	found on your plot", with the machine right there). ]]
function UpgradeNudgeController._machine(self): BasePart?
	local me = Players.LocalPlayer.UserId
	--- Anywhere under the workspace: the place keeps it at `workspace.Map.Plots`, not at the top.
	local plots = workspace:FindFirstChild(PlotConfig.PlotsFolderName, true)
	if not plots then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute(PlotConfig.OwnerUserIdAttribute) == me then
			--- A direct child first (where the place keeps it), then anywhere, so a same-named part deeper
			--- in the building cannot be picked ahead of the cabinet.
			local name = UpgradeConfig.Machine.ModelName
			local machine = plot:FindFirstChild(name) or plot:FindFirstChild(name, true)
			if not machine then
				return nil
			end
			if machine:IsA("BasePart") then
				return machine
			end
			if machine:IsA("Model") and machine.PrimaryPart then
				return machine.PrimaryPart
			end
			return machine:FindFirstChildWhichIsA("BasePart", true)
		end
	end
	return nil
end

--- Has this player ever bought an upgrade? Any level above 0 on the attribute the server publishes.
local function hasUpgraded(): boolean
	local levels = UpgradeConfig.decode(Players.LocalPlayer:GetAttribute(UpgradeConfig.Attribute))
	for _, level in levels do
		if type(level) == "number" and level > 0 then
			return true
		end
	end
	return false
end

--[[ Should the nudge be up, and if not, why not (the reason is logged when it changes, so a nudge that
	never appears says what held it). ORDER (2026-10-20): for a player who crossed `Cash` inside the
	tutorial, after the run the tutorial sends them on and the daily rewards screen that run ends with
	(`DailyRewardController.afterTutorialPending`), and never over any open page. ]]
function UpgradeNudgeController._wanted(self): (boolean, string)
	local player = Players.LocalPlayer
	local cfg = UpgradeConfig.Nudge
	if self._done then
		return false, "the Upgrades page was opened this session"
	end
	if self._racing then
		return false, "on a run"
	end
	local step = player:GetAttribute(TutorialConfig.StepAttribute)
	if type(step) == "string" and step ~= "" then
		return false, "the tutorial is still on (" .. step .. ")"
	end
	local daily = Shard.get("DailyRewardController")
	if daily and daily.afterTutorialPending and daily:afterTutorialPending() then
		return false, "the after-tutorial daily rewards screen comes first"
	end
	local UIController = Shard.get("UIController")
	if UIController and UIController.currentPage ~= nil then
		return false, "a page is open (" .. tostring(UIController.currentPage) .. ")"
	end
	if (player:GetAttribute(CarryConfig.Attribute) or "") ~= "" then
		return false, "carrying a car" -- the carry card and its line to a bay come first
	end
	local cash = tonumber(player:GetAttribute(GarageConfig.CashAttribute)) or 0
	if cash < cfg.Cash then
		return false, "under the cash threshold"
	end
	if hasUpgraded() then
		return false, "already bought an upgrade"
	end
	return true, "showing"
end

function UpgradeNudgeController._step(self)
	if not self._card then
		return
	end
	local UIController = Shard.get("UIController")
	if UIController and UIController.currentPage == UpgradeConfig.Machine.PageName then
		self._done = true -- they found it; the nudge has done its job for this session
	end

	local want, why = self:_wanted()
	local machine = if want then self:_machine() else nil
	if want and not machine then
		want, why = false, "no Upgrades machine found on your plot"
	end
	--- Said once per change of reason, and only past the threshold, so the log is not a heartbeat.
	local cash = tonumber(Players.LocalPlayer:GetAttribute(GarageConfig.CashAttribute)) or 0
	if why ~= self._lastWhy and cash >= UpgradeConfig.Nudge.Cash then
		self._lastWhy = why
		self.log:info("Upgrade nudge: " .. why)
	end
	local guide = Shard.get("GuideTrailController")
	if want and machine then
		if not self._up then
			self._up = true
			self._line.Text = string.format(UpgradeConfig.Nudge.Text, GarageConfig.formatCash(UpgradeConfig.Nudge.Cash))
			self._gui.Enabled = true
			if self._lane then
				self._lane:show(function()
					self._card.Visible = true
				end)
			else
				self._card.Visible = true
			end
		end
		if guide and guide.pointAt then
			guide:pointAt(machine)
		end
	elseif self._up then
		self._up = false
		if guide and guide.pointAt then
			guide:pointAt(nil)
		end
		if self._lane then
			self._lane:hide(function()
				self._card.Visible = false
				self._gui.Enabled = false
			end)
		else
			self._card.Visible = false
			self._gui.Enabled = false
		end
	end
end

UpgradeNudgeController:withRemoteEvents({
	{
		RaceStart = function()
			UpgradeNudgeController._racing = true
		end,
		RaceEnd = function()
			UpgradeNudgeController._racing = false
		end,
	},
})

UpgradeNudgeController:withLifecycle({
	init = function(self)
		self._racing = false
		self._done = false
		self._up = false
	end,

	start = function(self)
		if not UpgradeConfig.Nudge.Enabled then
			return
		end
		task.spawn(function()
			self:_build()
			while true do
				task.wait(1)
				self:_step()
			end
		end)
	end,
})

return UpgradeNudgeController
