--[[
	EncounterService  (server — the issuer of every traffic car, and the record of the one stolen)
	----------------------------------------------------------------------------------------------
	`EncounterConfig`'s header is the design and the reason (a security review, 2026-09-28: any client
	could bank any car). This file is the three things only the server can be:

	  1. THE ROLL. Every traffic car a player's road shows is rolled HERE — rung, body, paint and
	     mutation, off the same shared odds the client used to roll itself (`TrafficConfig.rollRung` /
	     `rollBody`, `PaintConfig.roll`, `WeatherConfig.roll`) — and handed out in batches under
	     opaque, single-use, expiring tokens (`_issue`).
	  2. THE LEDGER. Which tokens this run was issued, which are spent, and which car the player is
	     driving now (`redeemSteal`, `stolenCar`, `claimNearMiss`). One entry per player, created by
	     their first request of a run and dropped when the run ends (`RaceLeft`).
	  3. THE TELEMETRY. One summary line per run, and a warning — never a punishment — when a run
	     looks implausible (`_report`, `EncounterConfig.Telemetry`).

	=== WHAT IT TRUSTS ========================================================================

	From the client: that it wants cars, roughly how far down the road it is, which of its cars have
	left the road (`_retire`, a claim that can only cost the claimant), and — on a tutorial run
	only — which rung the staged steal needs. The distance is CLAMPED to what the run's elapsed time
	allows (`_plausibleTile`); the count is capped per request, per second and in total outstanding
	(`EncounterConfig.Issue`, `MaxOutstanding`). Everything else about a car is rolled here and never
	read back off the wire. A token is a GUID with no meaning of its own, looked up in THIS player's
	ledger for THIS run — another player's token, a spent one or an expired one is simply not found.

	What is knowingly NOT closed: the server cannot see the road, so it cannot prove the player was
	next to a car when they claim it. That claim is now bounded to the few cars actually queued for
	them, at the road's real odds and arrival rate — see `EncounterConfig`, "what is still trusted".
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local EncounterConfig = require(ReplicatedStorage.shared.Configs.EncounterConfig)
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)
local PassConfig = require(ReplicatedStorage.shared.Configs.PassConfig)
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local UpgradeConfig = require(ReplicatedStorage.shared.Configs.UpgradeConfig)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

--[[ `RaceService` for "is this player racing" and the end-of-run signal. `WorldService`, `RoadService`,
	`ObstacleService` and `RewardService` are reached through `Shard.get` when needed and are optional,
	the `GetawayService` rule: a missing one degrades a clamp or a log line, never the issuing. ]]
local EncounterService = Shard.new("EncounterService"):withDependencies({ "RaceService" })

--- The pass that adds luck, read off the Player exactly as `TrafficController._refreshLuck` reads it.
local LUCKY_ROADS_ATTRIBUTE = PassConfig.ownedAttribute("LuckyRoads")

export type Car = {
	token: string,
	rung: number, -- index into `TrafficConfig.tiersFor(world)`, which the client's ladder is too
	tier: number, -- the gameplay tier (`tier.Tier`): prices the steal and the bank
	body: string,
	paint: number,
	mutation: string?,
}

type Issued = Car & {
	expiresAt: number,
	spent: boolean, -- stolen
	passed: boolean, -- a near miss has already been paid for it
}

type Ledger = {
	world: number,
	tiers: { any },
	luck: number,
	tutorial: boolean,
	startedAt: number,
	bucket: number, -- issue tokens available right now
	bucketAt: number,
	issued: { [string]: Issued },
	stolen: Car?, -- the car the player is driving, since their last redeemed steal
	steals: number,
	nearMisses: number,
	total: number, -- cars issued this run
	capped: boolean?, -- the cap warning has been logged for this run (`_onRequest`)
}

EncounterService:withRemoteEvents({
	--[[ server -> client ({ Car }): cars for your road, in the order to spawn them. Sent in answer to
		`EncounterRequest` and nothing else. ]]
	"EncounterBatch",
	{
		--[[ client -> server (tileIndex, count, rung?, retired?): "I need cars; I am about this far
			down the road." `rung` is the tutorial's staged steal asking for one particular rung, and is
			honoured on a tutorial run only. `retired` is the tokens of cars that have left this
			client's road since its last request (`_retire`). See "what it trusts". ]]
		EncounterRequest = function(player: Player, tileIndex: unknown, count: unknown, rung: unknown, retired: unknown)
			EncounterService:_onRequest(player, tileIndex, count, rung, retired)
		end,
	},
})

-- === The ledger =============================================================

--[[ This player's ledger for the run they are in, made on first use. nil for a player who is not
	racing — a request between runs is refused rather than starting a ledger nothing will end. The
	odds are captured HERE, once per run, for `TrafficController._onRaceStart`'s reason: the ladder
	and luck are what the run was built from. (Luck can rise mid-run with the Lucky Roads pass; the
	client re-reads it, and `_issue` does too, off the Player.) ]]
function EncounterService._ledger(self, player: Player): Ledger?
	local ledger = self._ledgers[player]
	if ledger then
		return ledger
	end
	local Race = Shard.get("RaceService")
	if not (Race and Race:isRacing(player)) then
		return nil
	end
	local World = Shard.get("WorldService")
	local world = WorldConfig.resolve(if World then World:worldOf(player) else nil)
	local now = os.clock()
	ledger = {
		world = world,
		tiers = TrafficConfig.tiersFor(world) or TrafficConfig.Tiers,
		luck = 1,
		tutorial = TutorialConfig.isTutorialRun(player:GetAttribute(TutorialConfig.StepAttribute)),
		startedAt = now,
		bucket = EncounterConfig.Issue.Burst,
		bucketAt = now,
		issued = {},
		stolen = nil,
		steals = 0,
		nearMisses = 0,
		total = 0,
	}
	self._ledgers[player] = ledger
	return ledger
end

--- This player's luck right now, off the same two attributes the client's roll reads.
function EncounterService._luckOf(self, player: Player): number
	return UpgradeConfig.luckFactor(
		UpgradeConfig.decode(player:GetAttribute(UpgradeConfig.Attribute)),
		player:GetAttribute(LUCKY_ROADS_ATTRIBUTE)
	)
end

--- The weather event running in this player's world right now, or nil — the client's `_liveEvent`,
--- off the same replicated schedule. A tutorial run drives an ordinary road, as it does there.
function EncounterService._event(self, ledger: Ledger): string?
	if ledger.tutorial then
		return nil
	end
	local entry = WeatherConfig.decode(workspace:GetAttribute(WeatherConfig.Attribute))[ledger.world]
	if entry and workspace:GetServerTimeNow() < entry.endsAt then
		return entry.event
	end
	return nil
end

--[[ The furthest tile this run could honestly have reached, plus the spawn-ahead slack: elapsed time
	at `EncounterConfig.MaxSpeed`, from the middle of tile 0 where every run starts. A claim past it is
	clamped, not refused — an honest client in a lag spike is still owed cars. With no RoadService the
	segment length is unknown and the claim is taken as it comes, which only ever helps honest play. ]]
function EncounterService._plausibleTile(self, ledger: Ledger, claimed: number): number
	local Road = Shard.get("RoadService")
	local segment = if Road then Road:getSegmentLength(ledger.world) else nil
	if not segment or segment <= 0 then
		return claimed
	end
	local reach = segment * 0.5 + (os.clock() - ledger.startedAt) * EncounterConfig.MaxSpeed
	return math.min(claimed, math.floor(reach / segment) + EncounterConfig.TileSlack)
end

--- Drop expired tokens and count the live, unspent ones. Cheap: a ledger holds a few dozen at most.
function EncounterService._outstanding(self, ledger: Ledger): number
	local now = os.clock()
	local live = 0
	for token, car in ledger.issued do
		if car.expiresAt <= now then
			ledger.issued[token] = nil
		elseif not car.spent then
			live += 1
		end
	end
	return live
end

--[[ Forget the cars that have left this player's road, so they stop counting against
	`MaxOutstanding`. See that config's note: without this the cap is a fuse that burns out about 40
	cars into every run and empties the road until the first batch expires.

	A SPENT TOKEN IS KEPT. It is already out of the count, and `stolen` holds its own copy of the
	car, so dropping it would change nothing; keeping it means the steal and the recycle of the same
	car can arrive in either order. (They cannot today: `StealLanded` is fired before the stolen car
	is recycled, and one client's remotes arrive in the order they were fired.)

	UNTRUSTED AND HARMLESS TO LIE ABOUT. Each entry is looked up in THIS player's ledger for THIS
	run, so a token that is not theirs, not a string, or already gone does nothing. Retiring a car
	that is still on the road only makes it unstealable and unpayable as a near miss, which costs
	the liar and nobody else, and the issue rate is still the bucket's. The walk is capped because a
	ledger never holds more unspent tokens than `MaxOutstanding`, so a longer list cannot be honest. ]]
function EncounterService._retire(self, ledger: Ledger, retired: unknown)
	if type(retired) ~= "table" then
		return
	end
	local budget = EncounterConfig.MaxOutstanding * 2
	for _, token in retired :: { any } do
		budget -= 1
		if budget < 0 then
			break
		end
		if type(token) == "string" then
			local car = ledger.issued[token]
			if car and not car.spent then
				ledger.issued[token] = nil
			end
		end
	end
end

-- === Issuing ================================================================

--- Roll one car at `tileIndex` (or on `rung`, for the tutorial). nil only for a world whose ladder has
--- no usable body, which is a config fault the client already survives as an empty road.
function EncounterService._roll(self, ledger: Ledger, luck: number, tileIndex: number, rung: number?): Issued?
	local event = self:_event(ledger)
	luck *= WeatherConfig.spawnLuckFor(event)
	local index, tier
	if rung then
		index = math.clamp(rung, 1, #ledger.tiers)
		tier = ledger.tiers[index]
	else
		index, tier = TrafficConfig.rollRung(self._rng, ledger.tiers, tileIndex, luck)
	end
	if not tier then
		return nil
	end
	local body = TrafficConfig.rollBody(self._rng, tier)
	if not body then
		return nil
	end
	return {
		token = HttpService:GenerateGUID(false),
		rung = index,
		tier = tier.Tier,
		body = body,
		paint = PaintConfig.roll(self._rng, body),
		mutation = WeatherConfig.roll(self._rng, event),
		expiresAt = os.clock() + EncounterConfig.Lifetime,
		spent = false,
		passed = false,
	}
end

--[[ A client asked for cars. Every limit in "what it trusts" is applied here, in the order that
	refuses cheapest first; a request that gets fewer cars than it asked for (or none) is answered with
	what it got, and the client asks again when its queue runs low. ]]
function EncounterService._onRequest(self, player: Player, tileIndex: unknown, count: unknown, rung: unknown, retired: unknown)
	if not EncounterConfig.Enabled then
		return
	end
	local ledger = self:_ledger(player)
	if not ledger then
		return
	end
	--- Before the room is counted, so the cars that just left the road are the room this request gets.
	self:_retire(ledger, retired)

	local want = if type(count) == "number" and count == count then math.clamp(math.floor(count), 1, EncounterConfig.BatchSize) else 1
	local tile = if type(tileIndex) == "number" and tileIndex == tileIndex then math.max(0, math.floor(tileIndex)) else 0
	tile = self:_plausibleTile(ledger, tile)
	--- A specific rung is the tutorial's staged steal, and nothing else may ask for one.
	local wantRung = if ledger.tutorial and type(rung) == "number" and rung == rung then math.floor(rung) else nil

	--- The bucket refills at `PerSecond` up to `Burst`, then pays for this request.
	local now = os.clock()
	local issue = EncounterConfig.Issue
	ledger.bucket = math.min(issue.Burst, ledger.bucket + (now - ledger.bucketAt) * issue.PerSecond)
	ledger.bucketAt = now
	local room = EncounterConfig.MaxOutstanding - self:_outstanding(ledger)
	--[[ SAID OUT LOUD, once a run. A full ledger answers with silence and the client's road simply
		drains, which is exactly how the cap burning out went unnoticed on a live server: no error on
		either side, just an empty road. An honest client that retires its cars should never get here. ]]
	if room <= 0 and not ledger.capped then
		ledger.capped = true
		self.log:warn(string.format(
			"%s's road hit the %d-car encounter cap %.0fs into the run (%d issued); no cars until some are retired or expire.",
			player.Name, EncounterConfig.MaxOutstanding, os.clock() - ledger.startedAt, ledger.total))
	end
	want = math.min(want, math.floor(ledger.bucket), room)
	if want <= 0 then
		return
	end

	local luck = self:_luckOf(player)
	local batch = {}
	for _ = 1, want do
		local car = self:_roll(ledger, luck, tile, wantRung)
		if car then
			ledger.issued[car.token] = car
			table.insert(batch, {
				token = car.token,
				rung = car.rung,
				tier = car.tier,
				body = car.body,
				paint = car.paint,
				mutation = car.mutation,
			})
		end
	end
	ledger.bucket -= #batch
	ledger.total += #batch
	if #batch > 0 then
		self:getRemoteEvent("EncounterBatch"):Fire(player, batch)
	end
end

-- === Redeeming ==============================================================

--- The issued, unexpired car behind a token on this player's current run, or nil.
function EncounterService._find(self, player: Player, token: unknown): Issued?
	local ledger = self._ledgers[player]
	if not (ledger and type(token) == "string") then
		return nil
	end
	local car = ledger.issued[token]
	if not car or car.expiresAt <= os.clock() then
		return nil
	end
	return car
end

--[[ Public (`StealService`): the player landed on the car behind `token`. Spends it and remembers it
	as the car they are now driving; answers that car, or nil for a token that is not theirs, not this
	run's, spent or expired — in which case nothing is refilled and nothing can later be banked. ]]
function EncounterService.redeemSteal(self, player: Player, token: unknown): Car?
	local car = self:_find(player, token)
	if not car or car.spent then
		return nil
	end
	car.spent = true
	local ledger = self._ledgers[player]
	ledger.steals += 1
	ledger.stolen = { token = car.token, rung = car.rung, tier = car.tier, body = car.body, paint = car.paint, mutation = car.mutation }
	return ledger.stolen
end

--- Public (`GetawayService`): the car this player is driving on this run, by the server's own record —
--- nil if they have not stolen one. The bank takes nothing else.
function EncounterService.stolenCar(self, player: Player): Car?
	local ledger = self._ledgers[player]
	return if ledger then ledger.stolen else nil
end

--[[ Public (`RewardService`): may a near miss past the car behind `token` be paid? True once per
	issued car on this run; a spent (stolen) car still counts, since you can pass one before you take
	it. So the whole near-miss bonus is bounded by cars this player's road was actually given. ]]
function EncounterService.claimNearMiss(self, player: Player, token: unknown): boolean
	local car = self:_find(player, token)
	if not car or car.passed then
		return false
	end
	car.passed = true
	self._ledgers[player].nearMisses += 1
	return true
end

-- === Telemetry ==============================================================

--[[ One summary per run, at settle, while the race is still live enough for `ObstacleService` to say
	how many hits it charged (`RunSettled`'s timing; see `ObstacleService.clearedFor`). The two
	patterns `EncounterConfig.Telemetry` names are WARNED, and that is all — the review's own advice
	is to measure how often honest runs trip them before anything acts on them. ]]
function EncounterService._report(self, player: Player, studs: number?, banked: boolean?)
	local ledger = self._ledgers[player]
	local cfg = EncounterConfig.Telemetry
	if not (ledger and cfg.Enabled) then
		return
	end
	local seconds = os.clock() - ledger.startedAt
	local Obstacles = Shard.get("ObstacleService")
	local hits = if Obstacles then Obstacles:hitCount(player) else nil

	local line = string.format(
		"[Integrity] %s: %.0fs, %s studs, %d issued, %d stolen, %d near misses, %s hits, %s.",
		player.Name,
		seconds,
		tostring(studs and math.floor(studs) or "?"),
		ledger.total,
		ledger.steals,
		ledger.nearMisses,
		tostring(hits or "?"),
		if banked then "banked" else "not banked"
	)
	local flags = {}
	if hits == 0 and seconds >= cfg.NoHitSeconds then
		table.insert(flags, "no hits on a long run")
	end
	if seconds > 0 and ledger.steals / (seconds / 60) > cfg.MaxStealsPerMinute then
		table.insert(flags, "steal rate above the plausible")
	end
	if #flags > 0 then
		self.log:warn(line .. " Worth a look: " .. table.concat(flags, "; ") .. ".")
	else
		self.log:info(line)
	end
end

-- === Lifecycle ==============================================================

EncounterService:withLifecycle({
	init = function(self)
		self._rng = Random.new()
		self._ledgers = {} :: { [Player]: Ledger }
	end,

	start = function(self)
		local Race = Shard.get("RaceService")
		if Race then
			--- The run is over: its ledger goes, spent and unspent alike, so no token outlives its run.
			Race:getSignal("RaceLeft"):Connect(function(player: Player)
				self._ledgers[player] = nil
			end)
		end
		local Reward = Shard.get("RewardService")
		if Reward then
			Reward:getSignal("RunSettled"):Connect(function(player: Player, _cash: number, studs: number, banked: boolean)
				self:_report(player, studs, banked)
			end)
		end
		Players.PlayerRemoving:Connect(function(player: Player)
			self._ledgers[player] = nil
		end)
	end,
})

return EncounterService
