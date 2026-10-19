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
	oldest gift that is due, WRITES the new count, then pays. A double press is one gift, because the
	second press finds the count already moved.

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
	if session.day == today then
		return false
	end
	session.day, session.base, session.since, session.claimed = today, 0, os.clock(), 0
	return true
end

function PlaytimeRewardService._save(self, player: Player)
	local session = self._sessions[player]
	local profile = self:_profile(player)
	if session and profile then
		profile:Set({ PlaytimeRewardConfig.ProfileKey }, {
			Day = session.day,
			Seconds = math.floor(self:_seconds(session)),
			Claimed = session.claimed,
		})
	end
end

-- === Telling the client =====================================================

--[[ Everything the panel draws: when each gift comes due, how many are taken, and the seconds played
	so far. The client counts on from `seconds` with its own clock, so the countdown needs no further
	messages until a gift comes due.

	WHAT IS INSIDE A GIFT IS SENT ONLY ONCE IT IS OPENED (2026-10-19). The panel shows wrapped gifts
	and reveals each on its claim, and a reveal the client could read ahead of time out of this table
	is not a surprise. So an unclaimed gift is just its `Minutes`; a claimed one carries what it paid
	(priced now, which for a car is the body it was priced at today). ]]
function PlaytimeRewardService._payload(self, player: Player, session: Session, justClaimed: number?)
	local Daily = Shard.get("DailyRewardService")
	local gifts = {}
	for index, spec in PlaytimeRewardConfig.Gifts do
		local gift: { [string]: any } = { Minutes = spec.Minutes }
		if index <= session.claimed then
			local kind, amount, body = spec.Kind, spec.Amount or 0, spec.Body
			if Daily then
				kind, amount, body = Daily:priceSpec(player, spec)
			end
			gift.Kind, gift.Amount, gift.Body = kind, amount, body
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

--- Header TRUST, in order: throttle, check, WRITE, then pay.
function PlaytimeRewardService._claim(self, player: Player)
	local now = os.clock()
	if not PlaytimeRewardConfig.Enabled or now - (self._lastMessage[player] or -math.huge) < MESSAGE_COOLDOWN then
		return
	end
	self._lastMessage[player] = now
	local session = self._sessions[player]
	local Daily = Shard.get("DailyRewardService")
	if not (session and Daily and self:_profile(player)) then
		return
	end
	self:_rollDay(session)
	local index = session.claimed + 1
	local spec = PlaytimeRewardConfig.Gifts[index]
	if not spec or self:_seconds(session) < spec.Minutes * 60 then
		self:_send(player)
		return
	end

	local kind, amount, body = Daily:priceSpec(player, spec)
	session.claimed = index
	self:_save(player)
	local paid = Daily:pay(player, kind, amount, body, "Playtime")
	if paid then
		self.log:info(string.format("%s claimed playtime gift %d: %s %s.", player.Name, index, kind, body or tostring(amount)))
		local Analytics = Shard.get("AnalyticsService")
		if Analytics then
			Analytics:Design(player, "Playtime:Claimed:" .. index, spec.Minutes)
		end
	else
		self.log:warn(string.format("%s claimed playtime gift %d but it could not be paid; it is still marked taken.", player.Name, index))
	end
	self:_send(player, index)
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
		self._profiles[player] = profile
		local stored = profile:Get({ PlaytimeRewardConfig.ProfileKey })
		local today = QuestConfig.dayIndex()
		local sameDay = type(stored) == "table" and stored.Day == today
		self._sessions[player] = {
			day = today,
			base = if sameDay and type(stored.Seconds) == "number" then math.max(0, stored.Seconds) else 0,
			since = os.clock(),
			claimed = if sameDay and type(stored.Claimed) == "number" then math.clamp(math.floor(stored.Claimed), 0, #PlaytimeRewardConfig.Gifts) else 0,
		}
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
