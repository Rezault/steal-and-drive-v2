--[[
	StealService  (server)
	----------------------
	Ratifies a steal. Two messages, both from the one client that can see what happened.

	  StealLanded(tier)  — "I landed on a Tier N car and took it." We re-stamp MaxHealth from
	                       `StealConfig.TierStats` and refill the car to it. That's the reward, and
	                       it's the only heal in the game.
	  StealFailed()      — "I landed on tarmac." Runs the normal wreck-and-return beat with a cause,
	                       so the client can play a splat instead of an engine plume.

	WHY THE CLIENT IS TRUSTED WITH THE TIER, AND WHAT THAT COSTS. Traffic is entirely client-sided
	(TrafficController), for the same reason the road and the obstacles are: driving is solo, so
	every driver owns their own copy of the world and none of it replicates. So there is no traffic
	car on the server to check a claim against — no id, no position, nothing. The server can bound
	the claim (a real tier, at a bounded rate, only while actually racing) and nothing more.

	That is the SAME accepted gap `ObstacleService` and `TrafficService` already document, one step
	further: a cheating client can hand itself a Tier 5's stats without earning them, and the only
	person cheated is the cheater, because nobody else is on their road. It stops being acceptable
	the moment a steal PAYS INTO A GARAGE — and the fix is already designed (plan §4, S20 / handoff
	doc §6.7): the client asks the server for each traffic spawn, the server rolls the tier and
	returns an opaque token, and a steal redeems that token. About one remote every 2.5 seconds.
	Sequenced late on purpose — the token has to exist before banking ships, not before the mechanic
	is fun. IT SHIPPED 2026-09-28 (`EncounterConfig`, `EncounterService`), after a security review
	showed banking had in fact shipped first; `_onLanded`'s dated block has what changed here.

	HP still only ever moves inside ObstacleService. This service prices the reward from config and
	hands it over; it never writes Health itself. Same split as TrafficService's clip pricing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local StealConfig = require(ReplicatedStorage.shared.Configs.StealConfig)
local CarConfig = require(ReplicatedStorage.shared.Configs.CarConfig)
--- Whether a steal redeems a server-issued token (`_onLanded`'s dated block).
local EncounterConfig = require(ReplicatedStorage.shared.Configs.EncounterConfig)

local StealService = Shard.new("StealService"):withDependencies({ "ObstacleService", "RaceService" })

StealService:withSignals({
	--[[ (player: Player, tier: number) — a steal was ratified. Fired from `_onLanded` only after the
		refill has actually landed, so it carries exactly the steals the server agreed to and never
		one it refused for a bad tier, a cooldown, or a player who was not racing.

		It exists for `QuestService`, which counts steals; it is a signal rather than a call into that
		service because the dependency only makes sense in that direction — a steal is the game, and a
		quest is a note somebody is keeping about it. ]]
	"CarStolen",
})

--[[ Floor on how often a steal can be banked, seconds.

	Sized off the mechanic rather than off a guess at abuse: a bail takes ~0.12s of launch, ~1.2s of
	arc and a ~0.3s mount, so two legitimate steals cannot be less than about 1.6s apart. 1.2 leaves
	headroom for a shorter arc after tuning while still making a refill spam-loop pointless. ]]
local STEAL_COOLDOWN = 1.2

StealService:withRemoteEvents({
	{
		--- The car's encounter TOKEN (a tier with `EncounterConfig` off). See `_onLanded`.
		StealLanded = function(player: Player, tokenOrTier: unknown)
			StealService:_onLanded(player, tokenOrTier)
		end,
		StealFailed = function(player: Player)
			StealService:_onFailed(player)
		end,
		StealMissed = function(player: Player)
			StealService:_onMissed(player)
		end,
	},
})

--[[ Read a tier off the wire.

	nil for anything that isn't a whole number naming a tier we actually have stats for — NaN is
	tested explicitly, because it fails every comparison and would sail through a range check into
	`TierStats[nan]`. Unlike TrafficService's severity there is no "price it at the maximum" fallback
	here, because the generous reading of a malformed tier would be to hand out the BEST stats. A
	malformed steal is simply not banked; the client has still done the visual half locally, so the
	player sees the car they took and just doesn't get the refill. ]]
function StealService._readTier(self, tier: unknown): number?
	if type(tier) ~= "number" or tier ~= tier or tier % 1 ~= 0 then
		return nil
	end
	return if StealConfig.TierStats[tier] then tier else nil
end

--[[ === THE TOKEN IS IN — 2026-09-28 =========================================================

	The fix the header describes landed, prompted by a security review that found the refill could be
	farmed (a client-chosen tier, refilled every `STEAL_COOLDOWN`) and, worse, that the bank trusted the
	car it was handed. With `EncounterConfig.Enabled` the wire carries the TOKEN of the car landed on,
	not a tier: `EncounterService.redeemSteal` spends it — once — and answers the car the SERVER rolled,
	and the refill is priced from that. A token that is not this player's, not this run's, spent or
	expired refills nothing, and leaves nothing for `GetawayService` to bank. With it off, the argument
	is the tier and everything below is the old path, exactly. ]]
function StealService._onLanded(self, player: Player, tier: unknown)
	if not StealConfig.Enabled then
		return
	end
	local index
	local body: string?
	if EncounterConfig.Enabled then
		local Encounters = Shard.get("EncounterService")
		local car = Encounters and Encounters:redeemSteal(player, tier)
		if not car then
			self.log:warn(string.format("%s reported a steal with no valid encounter token; nothing refilled.", player.Name))
			return
		end
		index = self:_readTier(car.tier)
		body = car.body -- Only the server-issued token decides which body refills health.
	else
		index = self:_readTier(tier)
	end
	if not index then
		self.log:warn(string.format("%s reported a steal with an unusable tier (%s).", player.Name, tostring(tier)))
		return
	end

	local now = os.clock()
	if now - (self._lastSteal[player] or 0) < STEAL_COOLDOWN then
		return
	end

	local ObstacleService = Shard.get("ObstacleService")
	if not ObstacleService then
		return
	end

	-- Only stamp the cooldown when the refill actually lands, so a report from someone who isn't
	-- racing can't shadow a real steal a moment later. Same pattern as TrafficService's clip.
	local stats = StealConfig.TierStats[index]
	-- Economy aliases may have different health (the Floater is priced as M5, but still has 130 HP).
	local maxHealth = if body then CarConfig.maxHealthOf(body) else stats.MaxHealth
	if ObstacleService:refillHealth(player, maxHealth) then
		self._lastSteal[player] = now
		self:getSignal("CarStolen"):Fire(player, index)
		self.log:info(string.format("%s stole a Tier %d.", player.Name, index))
	end
end

--[[ Landed on the road. Straight into the normal death, with a cause so the client knows which
	failure it was.

	Deliberately not rate-limited and deliberately not verified. A client that lies about this is
	wrecking its own run, which is the same self-harm direction every other report in this game is
	exploitable in (see ObstacleService's header) — and `wreckRace` is idempotent and already
	re-checks that the race it's ending is still the one it started. ]]
function StealService._onFailed(self, player: Player)
	if not StealConfig.Enabled then
		return
	end
	local RaceService = Shard.get("RaceService")
	if RaceService then
		RaceService:wreckRace(player, "badLanding")
	end
end

--[[ A TUTORIAL miss (`TutorialConfig.Unlosable.Catch`): the client called the flight off and the
	player is driving again, so there is no wreck to run — only the beat to rewind, AIRBORNE back to
	BAIL. Unverified, like `_onFailed`, and safe for the same reason: the most a forged one can do is
	put the sender's own tutorial back one beat, and `rewindAttempt` does nothing on any other beat. ]]
function StealService._onMissed(self, player: Player)
	local TutorialService = Shard.get("TutorialService")
	if TutorialService then
		TutorialService:rewindAttempt(player)
	end
end

StealService:withLifecycle({
	init = function(self)
		self._lastSteal = {} -- [Player] = os.clock() of the last steal we banked
	end,

	start = function(self)
		Players.PlayerRemoving:Connect(function(player)
			self._lastSteal[player] = nil
		end)
	end,
})

return StealService
