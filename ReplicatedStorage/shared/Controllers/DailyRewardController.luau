--[[
	DailyRewardController  (client)
	-------------------------------
	Holds the daily reward calendar the server sends (`DailyRewardService`), republishes it for the
	page (`DailyRewardConfig.StateEvent`), opens the page once a session when there is something to
	claim, and plays the payout when a claim comes back. It DECIDES nothing: a press is a request, and
	only the calendar that comes back changes what is drawn — the same rule the quest board keeps.

	THE CELEBRATION IS FIRED BY THE REPLY, NOT THE PRESS. The server's answer to a claim carries
	`claimed`, and that is the only thing that throws banknotes; a refused claim celebrates nothing.

	The clock is the server's `nextAt`; at that moment this asks for a fresh calendar, so a player
	sitting in the lobby across midnight sees the next day light up without rejoining.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local GameplayFeedback = require(ReplicatedStorage.shared.Modules.GameplayFeedback)
local Shard = require(ReplicatedStorage.Packages.Shard)
local DailyRewardConfig = require(ReplicatedStorage.shared.Configs.DailyRewardConfig)
local GamepadConfig = require(ReplicatedStorage.shared.Configs.GamepadConfig)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)

local DailyRewardController = Shard.new("DailyRewardController")

local REMOTES = DailyRewardConfig.Remotes

--- Public: the last calendar, or nil before the first lands.
function DailyRewardController.state(self)
	return self._state
end

--- Public (the page's CLAIM): ask for today's. Nothing is drawn until the reply.
function DailyRewardController.claim(self)
	self:getRemoteEvent(REMOTES.Claim):Fire()
end

--- Public (the page, on open): ask for a fresh calendar, so a stale price is never on screen long.
function DailyRewardController.refresh(self)
	self:getRemoteEvent(REMOTES.Refresh):Fire()
end

--- Public: open the screen. False when it is not built in this place (`BuildDailyRewardsV2`).
function DailyRewardController.open(self): boolean
	local UIController = Shard.get("UIController")
	if not (UIController and UIController.pages and UIController.pages[DailyRewardConfig.PageName]) then
		if not self._warnedMissing then
			self._warnedMissing = true
			warn("[DailyRewardController] No MainUIV2.Pages.DailyRewards in this place; run BuildDailyRewardsV2.")
		end
		return false
	end
	UIController:openPage(DailyRewardConfig.PageName)
	return true
end

function DailyRewardController._onState(self, payload: unknown)
	if type(payload) ~= "table" or type((payload :: any).days) ~= "table" then
		return
	end
	local state = payload :: any
	self._state = state
	Dispatcher:Publish(DailyRewardConfig.StateEvent, state)

	if type(state.claimed) == "number" then
		self:_celebrate(state)
	end
	self:_armMidnight(state.nextAt)
	if state.claimable and not self._autoOpened then
		self._autoOpened = true
		task.spawn(self._autoOpen, self)
	end
end

--[[ The payout's feedback: banknotes from the player into the counter for cash (the collect mats'
	effect); revive and car rewards already have an unmistakable card and share the confirmation sound. ]]
function DailyRewardController._celebrate(self, state)
	local day = state.days[state.claimed]
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if day and day.Kind == "Cash" and root then
		local burst = Shard.get("CashBurstController")
		if burst then
			burst:burst(day.Amount, (root :: BasePart).Position + Vector3.new(0, 3, 0))
		end
	end
	GameplayFeedback.play("DailyClaimed")
end

--- At the next UTC midnight, ask for the new day. One timer at a time; a newer `nextAt` replaces it.
function DailyRewardController._armMidnight(self, nextAt: unknown)
	if type(nextAt) ~= "number" or nextAt == self._armedFor then
		return
	end
	self._armedFor = nextAt
	task.delay(math.max(1, nextAt - os.time() + 2), function()
		if self._armedFor == nextAt then
			self:refresh()
		end
	end)
end

--[[ `DailyRewardConfig.AutoOpen`: once a session, after `Delay`, never in the tutorial or a run, and
	only once no other screen is up — waiting up to `MaxWait` for one (the Welcome Back screen opens
	on the same join) to close. Gives up quietly if the moment never comes; the topbar button stays. ]]
function DailyRewardController._autoOpen(self)
	local cfg = DailyRewardConfig.AutoOpen
	if not cfg.Enabled then
		return
	end
	task.wait(cfg.Delay)
	self:_openWhenFree(cfg.MaxWait)
end

--[[ Open the page the first second nothing else is in the way: no run, no tutorial, no page, no modal
	and no NEW BEST stage. Up to `maxWait` seconds, then quietly not at all. Only with a claim. ]]
function DailyRewardController._openWhenFree(self, maxWait: number, anyway: boolean?)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local deadline = os.clock() + maxWait
	local why = "never free"
	while os.clock() < deadline do
		local step = player:GetAttribute(TutorialConfig.StepAttribute)
		local inTutorial = type(step) == "string" and step ~= ""
		local UIController = Shard.get("UIController")
		local pageOpen = UIController and UIController.currentPage ~= nil
		local modal = playerGui:GetAttribute(GamepadConfig.ModalAttribute) == true
		local showcase = Shard.get("ShowcaseController")
		local staged = showcase ~= nil and showcase:busy()
		if not (self._racing or inTutorial or pageOpen or modal or staged) then
			if self._state and (anyway or self._state.claimable) then
				self:open()
			end
			return
		end
		why = if self._racing then "racing"
			elseif inTutorial then "in the tutorial"
			elseif pageOpen then "page " .. tostring(UIController.currentPage)
			elseif modal then "a modal"
			else "the NEW BEST stage"
		task.wait(1)
	end
	if anyway then
		self.log:info("Daily rewards did not open after the tutorial run: " .. why)
	end
end

--[[ `DailyRewardConfig.AfterTutorialRun`: the tutorial ended this session (its step attribute went
	from a beat to nothing), so the run it ended on is the one that brings this screen up. ]]
function DailyRewardController._onTutorialStep(self)
	local step = Players.LocalPlayer:GetAttribute(TutorialConfig.StepAttribute)
	local inTutorial = type(step) == "string" and step ~= ""
	if self._sawTutorial and not inTutorial and not self._afterTutorialDone then
		self._afterTutorialArmed = true
	end
	self._sawTutorial = inTutorial
end

function DailyRewardController._afterRun(self)
	local cfg = DailyRewardConfig.AfterTutorialRun
	if not (cfg.Enabled and self._afterTutorialArmed) then
		return
	end
	self._afterTutorialArmed = false
	self._afterTutorialDone = true
	self._autoOpened = true -- this is the session's one open
	task.spawn(function()
		task.wait(cfg.Delay)
		--- Even with nothing to claim: the point is that they learn the screen exists.
		self:_openWhenFree(cfg.MaxWait, true)
	end)
end

DailyRewardController:withRemoteEvents({
	{
		[REMOTES.State] = function(payload: unknown)
			DailyRewardController:_onState(payload)
		end,
		RaceStart = function()
			DailyRewardController._racing = true
		end,
		RaceEnd = function()
			DailyRewardController._racing = false
			DailyRewardController:_afterRun()
		end,
	},
	REMOTES.Claim,
	REMOTES.Refresh,
})

DailyRewardController:withLifecycle({
	init = function(self)
		self._state = nil
		self._autoOpened = false
		self._racing = false
		self._armedFor = nil :: number?
		--- `AfterTutorialRun`: seen in the tutorial this session, armed once it ends, done once shown.
		self._sawTutorial = false
		self._afterTutorialArmed = false
		self._afterTutorialDone = false
	end,

	start = function(self)
		local player = Players.LocalPlayer
		player:GetAttributeChangedSignal(TutorialConfig.StepAttribute):Connect(function()
			self:_onTutorialStep()
		end)
		self:_onTutorialStep()
	end,
})

return DailyRewardController
