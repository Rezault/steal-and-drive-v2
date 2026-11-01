--[[
	PlaytimeRewardService  (server)
	-------------------------------
	Owns the playtime gifts (`PlaytimeRewardConfig`): how long each player has played today, which
	gifts they have taken, and the payout. The gifts are priced and paid by `DailyRewardService`
	(`priceSpec`, `pay`), so this file is a clock and a counter and nothing else.

	THE CLOCK IS THE SERVER'S. Played time is `os.clock()` on this server since the player joined,
	on top of what today's record already held, so nothing a client sends moves it. It is written to
	the profile every `SaveInterval`, on every claim and on leaving; a crash loses at most one
	interval of progress, and never a gift already paid.

	TRUST, the daily calendar's rule: the client says "claim" and nothing else. The server picks the
	oldest gift that is due. A per-session lock covers yielding payouts. The payout commits the
	count and exact receipt immediately after ownership is written, before presentation work.
	Failed grants remain claimable; presentation errors after a grant cannot grant it again.

	A NEW DAY MID-SESSION starts the ladder again at zero from that moment, and the client is told.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local PlaytimeRewardConfig = require(ReplicatedStorage.shared.Configs.PlaytimeRewardConfig)
--- The day boundary, shared with the quests and the daily calendar (`PlaytimeRewardConfig` note 1).
local QuestConfig = require(ReplicatedStorage.shared.Configs.QuestConfig)

local Data = require(script.Parent.Parent.Data)

local PlaytimeRewardService = Shard.new("PlaytimeRewardService"):withDependencies({ "GarageService", "DailyRewardService" })

--- A claim or a refresh faster than this is a held key or a script, and is dropped.
local MESSAGE_COOLDOWN = 1

type Session = {
	day: number,
	--- Seconds played today before this session (or before the day turned over during it).
	base: number,
	--- `os.clock()` the current stretch began.
	since: number,
	claimed: number,
	receipts: { [string]: { [string]: any } },
	claiming: boolean?,
}

local REMOTES = PlaytimeRewardConfig.Remotes

PlaytimeRewardService:withRemoteEvents({
	REMOTES.State,
	{
		[REMOTES.Claim] = function(player: Player)
			PlaytimeRewardService:_claim(player)
		end,
	},
})

-- === The record =============================================================

function PlaytimeRewardService._profile(self, player: Player)
	local profile = self._profiles[player]
	return if profile and profile:IsActive() then profile else nil
end

--- Seconds this player has played today, right now.
function PlaytimeRewardService._seconds(self, session: Session): number
	return session.base + (os.clock() - session.since)
end

--- Start the ladder over if the UTC day has turned since this session last looked. Answers whether it did.
function PlaytimeRewardService._rollDay(self, session: Session): boolean
	local today = QuestConfig.dayIndex()
	-- A yielding payout belongs to the day it started on.
	if session.day == today or session.claiming then return false end
	session.day, session.base, session.since, session.claimed = today, 0, os.clock(), 0
	session.receipts = {}
	return true
end

-- These profile writes must not yield between ownership and the receipt.
function PlaytimeRewardService._record(self, session: Session)
	return {
		Day = session.day, Seconds = math.floor(self:_seconds(session)),
		Claimed = session.claimed, Receipts = table.clone(session.receipts),
	}
end

-- Old claims keep their count. Their original prizes cannot be reconstructed.
function PlaytimeRewardService._restore(self, stored, today: number): Session
	local sameDay = type(stored) == "table" and stored.Day == today
	local seconds = sameDay and stored.Seconds
	local claimed = sameDay and stored.Claimed
	local session: Session = {
		day = today,
		base = if type(seconds) == "number" and seconds == seconds and seconds < math.huge then math.max(0, seconds) else 0,
		since = os.clock(),
		claimed = if type(claimed) == "number" and claimed == claimed then math.clamp(math.floor(claimed), 0, #PlaytimeRewardConfig.Gifts) else 0,
		receipts = {},
	}
	local receipts = sameDay and stored.Receipts
	if type(receipts) == "table" then
		for index = 1, session.claimed do
			local receipt = receipts[tostring(index)]
			if type(receipt) == "table" then
				local kind, amount, body = receipt.Kind, receipt.Amount, receipt.Body
				if (kind == "Cash" or kind == "Revive" or (kind == "Car" and type(body) == "string"))
					and type(amount) == "number" and amount == amount and amount >= 0 and amount < math.huge then
					session.receipts[tostring(index)] = {
						Kind = kind, Amount = amount, Body = if kind == "Car" then body else nil,
						ConvertedFrom = if kind == "Cash" and type(receipt.ConvertedFrom) == "string" then receipt.ConvertedFrom else nil,
						Reason = if receipt.Reason == "Full" or receipt.Reason == "Duplicate" then receipt.Reason else nil,
						ClaimId = tostring(today) .. ":" .. tostring(index),
					}
				end
			end
		end
	end
	return session
end

function PlaytimeRewardService._save(self, player: Player)
	local session = self._sessions[player]
	local profile = self:_profile(player)
	if session and profile then
		profile:Set({ PlaytimeRewardConfig.ProfileKey }, self:_record(session))
	end
end

-- === Telling the client =====================================================

--[[ Everything the panel draws: when each gift comes due, how many are taken, and the seconds played
	so far. The client counts on from `seconds` with its own clock, so the countdown needs no further
	messages until a gift comes due.

	WHAT IS INSIDE A GIFT IS SENT ONLY ONCE IT IS OPENED (2026-10-19). The panel shows wrapped gifts
	and reveals each on its claim, and a reveal the client could read ahead of time out of this table
	is not a surprise. So an unclaimed gift is just its `Minutes`; a claimed one carries what it paid
	from the saved grant receipt. Legacy claims without receipts say CLAIMED. ]]
function PlaytimeRewardService._payload(self, player: Player, session: Session, justClaimed: number?)
	local gifts = {}
	for index, spec in PlaytimeRewardConfig.Gifts do
		local gift: { [string]: any } = { Minutes = spec.Minutes }
		if index <= session.claimed then
			local receipt = session.receipts[tostring(index)]
			if receipt then
				gift.Kind, gift.Amount, gift.Body = receipt.Kind, receipt.Amount, receipt.Body
				gift.ConvertedFrom, gift.Reason = receipt.ConvertedFrom, receipt.Reason
			else
				gift.Kind = "Legacy"
			end
		end
		gifts[index] = gift
	end
	return { gifts = gifts, claimed = session.claimed, seconds = self:_seconds(session), justClaimed = justClaimed }
end

function PlaytimeRewardService._send(self, player: Player, justClaimed: number?)
	local session = self._sessions[player]
	if session and player.Parent == Players then
		self:getRemoteEvent(REMOTES.State):Fire(player, self:_payload(player, session, justClaimed))
	end
end

-- === Claiming ===============================================================

--- Commit on the payout backend's profile write, never on its return alone.
function PlaytimeRewardService._claim(self, player: Player)
	local now = os.clock()
	if not PlaytimeRewardConfig.Enabled or now - (self._lastMessage[player] or -math.huge) < MESSAGE_COOLDOWN then return end
	self._lastMessage[player] = now
	local session = self._sessions[player]
	local Daily = Shard.get("DailyRewardService")
	local profile = self:_profile(player)
	if not (session and Daily and profile) or session.claiming then return end
	self:_rollDay(session)
	local index = session.claimed + 1
	local spec = PlaytimeRewardConfig.Gifts[index]
	if not spec or self:_seconds(session) < spec.Minutes * 60 then
		self:_send(player)
		return
	end

	-- The lock also covers a backend that waits for its profile.
	session.claiming = true
	local committed = false
	local receipt
	local ok, result = pcall(function()
		local kind, amount, body = Daily:priceSpec(player, spec)
		receipt = { Kind = kind, Amount = amount, Body = body, ClaimId = tostring(session.day) .. ":" .. tostring(index) }
		return Daily:pay(player, kind, amount, body, "Playtime", function(delivered)
			-- Called immediately after the reward's profile mutation, before UI/signals.
			-- No yielding work may be added between that mutation and this receipt.
			if committed then return end
			if delivered then
				receipt.Kind, receipt.Amount, receipt.Body = delivered.Kind, delivered.Amount, delivered.Body
				receipt.ConvertedFrom, receipt.Reason = delivered.ConvertedFrom, delivered.Reason
			end
			committed = true
			session.claimed = index
			session.receipts[tostring(index)] = receipt
			-- PlayerRemoving may have removed the session while the backend waited.
			profile:Set({ PlaytimeRewardConfig.ProfileKey }, self:_record(session))
		end)
	end)
	session.claiming = false

	if not committed then
		self.log:warn(string.format("%s's playtime gift %d was not granted; it remains claimable (%s).", player.Name, index, tostring(result)))
		self:_send(player)
		return
	end
	-- Presentation errors after the confirmed write must never re-arm a gift.
	if not ok then
		self.log:warn(string.format("%s's playtime gift %d was granted, but its notification failed: %s.", player.Name, index, tostring(result)))
	end
	self:_send(player, index)
	self.log:info(string.format("%s claimed playtime gift %d: %s %s.", player.Name, index, receipt.Kind, receipt.Body or tostring(receipt.Amount)))
	local Analytics = Shard.get("AnalyticsService")
	if Analytics then Analytics:Design(player, "Playtime:Claimed:" .. index, spec.Minutes) end
end

-- === Lifecycle ==============================================================

--- Resume today's record (or start one), off `ProfileReady` like every service that reads a profile.
function PlaytimeRewardService._watch(self, player: Player)
	task.spawn(function()
		local ok, profile = pcall(function()
			return Data:GetProfileAsync(player)
		end)
		if not (ok and profile) or player.Parent ~= Players then
			return
		end
		if self._sessions[player] then return end
		self._profiles[player] = profile
		local stored = profile:Get({ PlaytimeRewardConfig.ProfileKey })
		self._sessions[player] = self:_restore(stored, QuestConfig.dayIndex())
		self:_send(player)
	end)
end

PlaytimeRewardService:withLifecycle({
	init = function(self)
		self._profiles = {} :: { [Player]: any }
		self._sessions = {} :: { [Player]: Session }
		self._lastMessage = {} :: { [Player]: number }
	end,

	start = function(self)
		if not PlaytimeRewardConfig.Enabled then
			return
		end
		local Garage = Shard.get("GarageService")
		if not Garage then
			return
		end
		Garage:getSignal("ProfileReady"):Connect(function(player: Player)
			self:_watch(player)
		end)
		for _, player in Players:GetPlayers() do
			if Garage:isProfileReady(player) then
				self:_watch(player)
			end
		end
		--- Written on the way out, before `Data` ends the session (its leave waits a frame for this).
		Players.PlayerRemoving:Connect(function(player: Player)
			self:_save(player)
			self._profiles[player] = nil
			self._sessions[player] = nil
			self._lastMessage[player] = nil
		end)

		local accumulator = 0
		RunService.Heartbeat:Connect(function(dt)
			accumulator += dt
			if accumulator < PlaytimeRewardConfig.SaveInterval then
				return
			end
			accumulator = 0
			for player, session in self._sessions do
				if self:_rollDay(session) then
					self:_send(player)
				end
				self:_save(player)
			end
		end)
	end,
})

return PlaytimeRewardService
