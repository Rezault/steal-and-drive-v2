--[[
	DailyRewardService  (server)
	----------------------------
	Owns the daily reward record and pays it out. `DailyRewardConfig` has the design: a seven-day
	streak on the quest board's UTC day, reset by a missed day, cash scaled to the player's own lot.

	TRUST. The client sends two messages and both are bare: "claim" and "send me the calendar". It
	cannot name a day, a reward or an amount. Every claim is checked against the server's own clock and
	the saved record — `LastDay` must be before today — and the record is WRITTEN BEFORE THE REWARD IS
	PAID, so a double press, or a press racing a second server, is one reward: the second claim finds
	today already taken. ProfileStore's session lock is what makes "a second server" impossible in the
	first place; this ordering is the belt to its braces. A payout that fails after the write (a service
	missing) costs the player that one reward and is logged; it can never cost the game a duplicate.

	What is knowingly NOT closed: the day comes from `os.time()` on the server, so nothing a client does
	moves it. Nothing else is open.

	Day 7's body is also server-owned: `DailyRewardConfig.Days` names the Mk5 Supra, its tier is looked
	up from the canonical garage roster, and the same `GarageService.awardCar` path as every other car
	writes it. The viewport beside the claim is presentation, never evidence of what should be paid.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local DailyRewardConfig = require(ReplicatedStorage.shared.Configs.DailyRewardConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
--- The day boundary, shared so quests and rewards turn over together (`DailyRewardConfig` note 1).
local QuestConfig = require(ReplicatedStorage.shared.Configs.QuestConfig)
--- Only for the attribute the lot's hourly earnings are published on (`DailyRewardConfig` note 3).
local OfflineConfig = require(ReplicatedStorage.shared.Configs.OfflineConfig)
--- The VIP tip boost, to take back off the daily cash (`_rewardFor`): a CONFIG, not `CustomerService`.
local CustomerConfig = require(ReplicatedStorage.shared.Configs.CustomerConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local Data = require(script.Parent.Parent.Data)

local DailyRewardService = Shard.new("DailyRewardService"):withDependencies({ "GarageService" })

--- (player: Player, day: number, kind: string, amount: number?, body: string?) : a day's reward was
--- claimed AND paid. For `AnalyticsService` (2026-10-15): streak depth is a retention number.
DailyRewardService:withSignals({ "Claimed" })

--- Seconds between two messages from one player that are acted on. A claim is once a day; a refresh is
--- an open or a midnight. Anything faster is a held key or a script, and is dropped.
local MESSAGE_COOLDOWN = 1

type Record = { Day: number, LastDay: number }

DailyRewardService:withRemoteEvents({
	DailyRewardConfig.Remotes.State,
	{
		[DailyRewardConfig.Remotes.Claim] = function(player: Player)
			DailyRewardService:_claim(player)
		end,
		[DailyRewardConfig.Remotes.Refresh] = function(player: Player)
			if DailyRewardService:_throttled(player) then
				return
			end
			DailyRewardService:_send(player)
		end,
	},
})

-- === The record ===============================================================

function DailyRewardService._profile(self, player: Player)
	local profile = self._profiles[player]
	return if profile and profile:IsActive() then profile else nil
end

--- The saved record, shape-checked. A fresh or malformed one is "never claimed".
function DailyRewardService._record(self, player: Player): Record?
	local profile = self:_profile(player)
	if not profile then
		return nil
	end
	local stored = profile:Get(DailyRewardConfig.ProfileKey)
	local day = type(stored) == "table" and stored.Day
	local last = type(stored) == "table" and stored.LastDay
	return {
		Day = if type(day) == "number" then math.clamp(math.floor(day), 0, #DailyRewardConfig.Days) else 0,
		LastDay = if type(last) == "number" then math.floor(last) else -1,
	}
end

--[[ Where this player stands today: which day of the week a claim would be (or was, if today is
	taken), and whether it can be claimed. Pure. A record claimed yesterday continues the streak; one
	older than that starts over at day 1 (`ResetOnMiss`); day 7 wraps to day 1. ]]
function DailyRewardService._standing(self, record: Record, today: number): (number, boolean)
	if record.LastDay >= today then
		return math.max(1, record.Day), false
	end
	local continuing = record.Day >= 1 and (record.LastDay == today - 1 or not DailyRewardConfig.ResetOnMiss)
	return if continuing then record.Day % #DailyRewardConfig.Days + 1 else 1, true
end

--- What day `index` pays this player right now. Cash is scaled; a car keeps its server-owned body.
function DailyRewardService._rewardFor(self, player: Player, index: number): (string, number, string?)
	return self:priceSpec(player, DailyRewardConfig.Days[index])
end

--[[ PUBLIC (2026-10-19, `PlaytimeRewardService`): what one reward spec pays this player right now,
	in `DailyRewardConfig.Days`' shape (`Kind`, `Floor`/`Hours`, `Amount`, `Body`, `FromTop`). The
	playtime gifts are priced by this same function, so a playtime $ and a daily $ are one formula
	and cannot drift apart as the economy is retuned. ]]
function DailyRewardService.priceSpec(self, player: Player, spec): (string, number, string?)
	if spec.Kind == "Car" and type(spec.FromTop) == "number" then
		--- The car scales with the player (`DailyRewardConfig.Days`' day 7 note): their world's ladder.
		local cars = WorldConfig.carsFor(WorldConfig.highestUnlocked(player))
		local body = cars[#cars - spec.FromTop]
		return spec.Kind, spec.Amount or 1, body or spec.Body
	end
	if spec.Kind ~= "Cash" then
		return spec.Kind, spec.Amount or 1, spec.Body
	end
	local label = OfflineConfig.Label
	local rate = player:GetAttribute(label.Attribute)
	local perHour = if type(rate) == "number" and rate > 0 then rate * 3600 / label.PerSeconds else 0
	-- The offline label includes both CashDouble and VIP. Remove each pass bonus once.
	local passes = Shard.get("PassService")
	if passes and passes:owns(player, "CashDouble") then
		perHour /= 2
	end
	if passes and passes:owns(player, "VIP") then
		perHour /= CustomerConfig.vipIncomeMultiplier()
	end
	return "Cash", DailyRewardConfig.roundCash(math.max(spec.Floor, perHour * (spec.Hours or 0)))
end

-- === Telling the client =======================================================

--[[ The calendar, everything the page draws:

	    days         { { Kind, Amount, Body?, Big } x 7 } — what each card pays, priced for this player now
	    current      the day a claim is (or was today) for
	    claimable    whether today's is still there to take
	    claimedThrough  how many cards to draw as taken (0 when the streak has just reset)
	    nextAt       os.time() of the next UTC midnight, for the clock
	    claimed      set only on the reply to a successful claim: the day just paid, for the celebration ]]
function DailyRewardService._payload(self, player: Player, record: Record, claimed: number?)
	local today = QuestConfig.dayIndex()
	local current, claimable = self:_standing(record, today)
	local days = {}
	for index, spec in DailyRewardConfig.Days do
		local kind, amount, body = self:_rewardFor(player, index)
		days[index] = { Kind = kind, Amount = amount, Body = body, Big = spec.Big == true }
	end
	return {
		days = days,
		current = current,
		claimable = claimable,
		claimedThrough = if claimable then current - 1 else current,
		nextAt = QuestConfig.resetAt(),
		claimed = claimed,
	}
end

function DailyRewardService._send(self, player: Player, claimed: number?)
	local record = self:_record(player)
	if record then
		self:getRemoteEvent(DailyRewardConfig.Remotes.State):Fire(player, self:_payload(player, record, claimed))
	end
end

function DailyRewardService._throttled(self, player: Player): boolean
	local now = os.clock()
	if now - (self._lastMessage[player] or -math.huge) < MESSAGE_COOLDOWN then
		return true
	end
	self._lastMessage[player] = now
	return false
end

-- === Claiming =================================================================

--[[ PUBLIC (2026-10-19, shared with `PlaytimeRewardService`): pay one priced reward. Answers whether
	it landed. `source` names the car's origin on `awardCar` ("DailyReward", "Playtime"). Moved out of
	`_claim` unchanged, so the daily payout is exactly what it was; the caller has already WRITTEN its
	own record (header "TRUST"), which is what makes a double press one reward. ]]
function DailyRewardService.pay(self, player: Player, kind: string, amount: number, body: string?, source: string): boolean
	if kind == "Cash" then
		local Garage = Shard.get("GarageService")
		return Garage ~= nil and (Garage:addCash(player, amount) or 0) >= 0
	elseif kind == "Revive" then
		local Revive = Shard.get("ReviveService")
		return Revive ~= nil and Revive:grantLife(player, amount)
	elseif kind == "Car" and body then
		local Garage = Shard.get("GarageService")
		local tier = GarageConfig.TierOfBody[body]
		if Garage and tier then
			return Garage:awardCar(player, tier, body, nil, nil, source) ~= "rejected"
		end
	end
	return false
end

--- Header "TRUST", in order: throttle, check, WRITE, then pay.
function DailyRewardService._claim(self, player: Player)
	if not DailyRewardConfig.Enabled or self:_throttled(player) then
		return
	end
	local profile = self:_profile(player)
	local record = self:_record(player)
	if not (profile and record) then
		return
	end
	local today = QuestConfig.dayIndex()
	local day, claimable = self:_standing(record, today)
	if not claimable then
		self:_send(player)
		return
	end

	local kind, amount, body = self:_rewardFor(player, day)
	profile:Set(DailyRewardConfig.ProfileKey, { Day = day, LastDay = today })

	local paid = self:pay(player, kind, amount, body, "DailyReward")
	if paid then
		self.log:info(string.format("%s claimed daily reward day %d: %s %s.", player.Name, day, kind, body or tostring(amount)))
		self:getSignal("Claimed"):Fire(player, day, kind, amount, body)
	else
		self.log:warn(string.format("%s claimed daily reward day %d (%s %s) but it could not be paid; the day is still marked taken.", player.Name, day, kind, body or tostring(amount)))
	end
	self:_send(player, day)
end

-- === Lifecycle ================================================================

DailyRewardService:withLifecycle({
	init = function(self)
		self._profiles = {} :: { [Player]: any }
		self._lastMessage = {} :: { [Player]: number }
	end,

	start = function(self)
		if not DailyRewardConfig.Enabled then
			return
		end
		local Garage = Shard.get("GarageService")
		--- The profile handle, off `ProfileReady` — `ShowcaseService`'s pattern, for its reason.
		Garage:getSignal("ProfileReady"):Connect(function(player: Player)
			task.spawn(function()
				local ok, profile = pcall(function()
					return Data:GetProfileAsync(player)
				end)
				if ok and profile and player.Parent == Players then
					self._profiles[player] = profile
					self:_send(player)
				end
			end)
		end)
		Players.PlayerRemoving:Connect(function(player)
			self._profiles[player] = nil
			self._lastMessage[player] = nil
		end)
	end,
})

return DailyRewardService
