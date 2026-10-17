--[[
	ShowroomSummaryController  (client)
	-----------------------------------
	"While you were driving": one card, after a run, saying how many customers walked the lot and what
	they tipped. The server counts (`CustomerService`, "While you were driving") and sends the three
	numbers once per run; this draws them and gets out of the way. Every word and timing is
	`CustomerConfig.Summary`.

	IT EXISTS BECAUSE THE MONEY IS OTHERWISE INVISIBLE. Since 2026-09-28 the showroom's customers are
	the dealership's only income, and they keep tipping while the owner is out on a run — into a cash
	counter the driving HUD hides for the whole of it. Without this the lot's best work happens where
	nobody can see it, and the reason to put a good car on a podium never lands.

	BUILT IN CODE, in the kit's arcade style since 2026-10-08 (the note above `_build`); it was a plain
	navy placeholder before. Nothing else reads it, so replacing it with authored UI is this one file.

	IT TAKES NO INPUT AND BLOCKS NOTHING. The run's results panel is what a returning player is reading;
	this is a line beside it, not a second modal to dismiss. A new summary arriving while one is still
	up replaces it rather than queueing, because the newer run is the only one worth reading.

	IN THE NOTICE LANE (2026-10-06) rather than top-centre, when `NoticeLaneConfig.Enabled`: the
	bottom slot of the left-side lane, sliding in from the left, and waiting its turn when the lane is
	full (`NoticeLaneConfig.MaxVisible`).

	=== ONE LINE, AND NOT ALWAYS, 2026-10-13 ==================================================
	WAS: a tall card of three lines (tips, customers, buyers) after every run. Aleafo, looking at
	"+$62 in tips, 6 customers stopped by, 1 buyer waiting" stacked with the carry card: "this is
	excessive af". IS: the header and ONE line, the tips on the left and one detail on the right (a
	waiting buyer if there is one, as that is the thing to go and act on, else the customer count).
	And a run whose tips are small next to the player's balance, with nobody waiting, shows nothing
	(`CustomerConfig.Summary.SkipUnderTips`, `SkipUnderCashShare`): the cash counter already moved.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local CustomerConfig = require(ReplicatedStorage.shared.Configs.CustomerConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local RaceConfig = require(ReplicatedStorage.shared.Configs.RaceConfig)
local NoticeLaneConfig = require(ReplicatedStorage.shared.Configs.NoticeLaneConfig)
local NoticeLane = require(ReplicatedStorage.shared.Modules.NoticeLane)

local ShowroomSummaryController = Shard.new("ShowroomSummaryController")

--[[ === ON THE KIT'S PROMPT PANEL, 2026-10-12 ==============================================
	WAS (2026-10-08) the hand-made arcade card: a flat cyan gradient, a checker of white Frames, pixel
	strokes, white and gold pills. Dylan, after a playtest: "the UI that shows how much you made needs
	polish". IS the kit's own prompt panel (`Modules/ArcadeKit`), the one the "Your New Car" card above
	it in the notice lane is cut from, so the lane reads as one family: the title in the header strip,
	and in the white body the customers line beside the kit's Add Player icon, the tips beside the
	HUD's banknote in the kit's green reward gradient (its quest rows set money that way), and waiting
	buyers in the kit's gold heading gradient beside them, the one thing on the card the player can go
	and act on. No pills: on this kit a pill reads as a button. ]]

local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local ArcadeKit = require(ReplicatedStorage.shared.Modules.ArcadeKit)

--[[ Card size as a fraction of the screen, and where it rests when the notice lane is off. The
	width is the carry card's rule (`Modules/CarryNoticeLayout`), a share clamped to pixels, so the two
	cards in the lane are one width on any screen; the height follows from `ASPECT`. ]]
local CARD_SIZE = UDim2.fromScale(0.22, 1)
local MIN_WIDTH, MAX_WIDTH = 220, 360
--- Pixels wide per pixel high: a header strip over one line (2026-10-13, was 3 for three lines).
local ASPECT = 4.2
local SHOWN = UDim2.fromScale(0.5, 0.04)
local HIDDEN = UDim2.fromScale(0.5, -0.25)
local SLIDE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
--- The header strip's share of the panel's height.
local HEADER = 0.42

--[[ Build the card once, hidden: the panel and its title over one line, the tips on the left and
	one detail on the right (customers, or waiting buyers when there are any). ]]
function ShowroomSummaryController._build(self)
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShowroomSummary"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	--- The kit's parts are layered for Sibling; a new ScreenGui defaults to Global.
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	--- The card is the transparent holder the lane positions; the panel fills it.
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Size = CARD_SIZE
	card.Position = HIDDEN
	card.BackgroundTransparency = 1
	card.Visible = false
	card.Parent = gui
	--- The height follows the width, so the width rule (`CARD_SIZE`) sizes the whole card.
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

	--[[ One row across the body. The money is the headline, so it takes the left, after the
		banknote; the detail sits right-aligned in the rest. Both are the same height so their type
		agrees unless one runs out of width. ]]
	local ROW_Y, ROW_H = 0.2, 0.6
	self._cashIcon = ArcadeKit.icon(body, UIAssets.Page.CashIcon, 0.07, 0.5, ROW_H * 0.95, 256 / 153)
	self._cashIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	self._money = ArcadeKit.text(body, 0.15, ROW_Y, 0.36, ROW_H, ArcadeKit.White, true)
	self._money.TextXAlignment = Enum.TextXAlignment.Left
	local moneyGradient = Instance.new("UIGradient")
	moneyGradient.Rotation = 90
	moneyGradient.Color = ColorSequence.new(ArcadeKit.Faces.Green[1], ArcadeKit.Faces.Green[2])
	moneyGradient.Parent = self._money

	self._visitors = ArcadeKit.text(body, 0.53, ROW_Y, 0.44, ROW_H, ArcadeKit.White, true)
	self._visitors.TextXAlignment = Enum.TextXAlignment.Right

	--- Waiting buyers, in the kit's gold heading, in the detail's place: the thing to go and act on.
	self._buyers = ArcadeKit.heading(body, 0.53, ROW_Y, 0.44, ROW_H)
	self._buyers.TextXAlignment = Enum.TextXAlignment.Right
	self._buyers.Visible = false

	self._gui = gui
	self._card = card
	if NoticeLaneConfig.Enabled then
		self._lane = NoticeLane.join(card, NoticeLaneConfig.Order.ShowroomSummary, true, ASPECT)
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

--[[ Show one summary. `summary` is the server's `{ visitors, tips, buyers }`; anything missing or not
	a number reads as 0, because a malformed field should cost a line of text, not the card. ]]
function ShowroomSummaryController._show(self, summary: unknown)
	local cfg = CustomerConfig.Summary
	if not (cfg.Enabled and self._card) or type(summary) ~= "table" then
		return
	end
	local function count(value: unknown): number
		return if type(value) == "number" and value == value then math.max(0, math.floor(value)) else 0
	end
	local visitors, tips, buyers = count(summary.visitors), count(summary.tips), count(summary.buyers)

	--- Small tips and nobody waiting: not worth a card (header). The balance already shows them.
	local cash = tonumber(Players.LocalPlayer:GetAttribute(GarageConfig.CashAttribute)) or 0
	if buyers == 0 and tips < math.max(cfg.SkipUnderTips, cash * cfg.SkipUnderCashShare) then
		return
	end

	self._title.Text = cfg.Title
	self._money.Text = "+" .. string.format(cfg.TipsFormat, GarageConfig.formatCash(tips))
	--- One detail: a waiting buyer beats the customer count.
	local waiting = buyers > 0
	self._buyers.Visible = waiting
	self._visitors.Visible = not waiting
	if waiting then
		self._buyers.Text = if buyers == 1 then cfg.OneBuyerText else string.format(cfg.BuyersFormat, buyers)
	else
		self._visitors.Text = if visitors == 1 then cfg.OneVisitorText else string.format(cfg.VisitorsFormat, visitors)
	end

	--[[ A token per show, so a summary that replaces one still on screen cannot be put away by the
		first one's timer running out halfway through the second. ]]
	self._token += 1
	self._busy = true
	Dispatcher:Publish("ShowroomSummaryStarted")
	local token = self._token
	local card = self._card
	task.delay(cfg.Delay, function()
		if token ~= self._token then
			return
		end
		if self._lane then
			card.Visible = true
			--- The hold starts when it is really up: a full lane makes it wait its turn.
			self._lane:show(function()
				task.delay(cfg.Hold, function()
					if token == self._token then
						self._lane:hide(function()
							if token == self._token then
								card.Visible = false
								self:_finished()
							end
						end)
					end
				end)
			end)
			return
		end
		card.Position = HIDDEN
		card.Visible = true
		TweenService:Create(card, SLIDE, { Position = SHOWN }):Play()
		task.delay(cfg.Hold, function()
			if token ~= self._token then
				return
			end
			local out = TweenService:Create(card, SLIDE, { Position = HIDDEN })
			out.Completed:Connect(function()
				if token == self._token then
					card.Visible = false
					self:_finished()
				end
			end)
			out:Play()
		end)
	end)
end

function ShowroomSummaryController.busy(self): boolean
	return CustomerConfig.Summary.Enabled and (self._busy == true or self._held ~= nil)
end

function ShowroomSummaryController._finished(self)
	self._busy = false
	Dispatcher:Publish("ShowroomSummaryEnded")
end

--[[ A summary from the server: held until the lobby is on screen (`CustomerConfig.Summary.Delay` has
	the why). Summaries that pile up across a RACE AGAIN chain are ADDED — visitors and tips are each
	run's own, so they sum; buyers is a count of who is waiting NOW, so the latest one wins. ]]
function ShowroomSummaryController._onSummary(self, summary: unknown)
	if type(summary) ~= "table" then
		return
	end
	local function count(value: unknown): number
		return if type(value) == "number" and value == value then math.max(0, value) else 0
	end
	local held = self._held
	self._held = {
		visitors = count(summary.visitors) + (if held then held.visitors else 0),
		tips = count(summary.tips) + (if held then held.tips else 0),
		buyers = count(summary.buyers),
	}
	if not self._away then
		self:_release()
	end
end

--- Show what is held, if anything. Called on the lobby coming back, or straight away off the lobby.
function ShowroomSummaryController._release(self)
	local held = self._held
	self._held = nil
	if held then
		self:_show(held)
	end
end

--- A run is starting: the card cannot be read under it, so a card on screen goes away now.
function ShowroomSummaryController._leave(self)
	self._away = true
	self._token += 1
	self._busy = false
	if not self._card then
		return
	end
	if self._lane then
		local card = self._card
		local token = self._token
		self._lane:hide(function()
			if token == self._token then
				card.Visible = false
			end
		end)
	else
		self._card.Visible = false
		self._card.Position = HIDDEN
	end
end

ShowroomSummaryController:withRemoteEvents({
	{
		ShowroomSummary = function(summary: unknown)
			ShowroomSummaryController:_onSummary(summary)
		end,
		RaceStart = function()
			ShowroomSummaryController:_leave()
		end,
	},
})

ShowroomSummaryController:withLifecycle({
	init = function(self)
		self._token = 0
		--- Out on the road (`RaceStart` until `ReturnedEvent`), when a summary waits instead of showing.
		self._away = false
		self._held = nil :: { visitors: number, tips: number, buyers: number }?
	end,

	start = function(self)
		if not CustomerConfig.Summary.Enabled then
			return
		end
		--- Built off the start path: the kit's parts arrive with the UI, after the join screen.
		task.spawn(function()
			self:_build()
		end)
		Dispatcher:Subscribe(RaceConfig.ReturnedEvent, function()
			self._away = false
			self:_release()
		end)
	end,
})

return ShowroomSummaryController
