--[[
	RewardService  (server — what a run pays)
	----------------------------------------
	The run's payout, and the one number in this game the server measures for itself.

	Four things happen here, in this order, once per run:

	  1. MEASURE THE DISTANCE. `beginRun` starts watching a live race car; a slow poll accumulates
	     how far it has moved down the road. Nothing is reported by anyone — see below.
	  2. BANK THE NEAR MISSES. `addNearMiss` takes the one thing on this screen the server cannot
	     see for itself — how close the player got to a car, and whether they touched it — and turns
	     it into bonus cash on the run (`NearMissConfig`). This is the exception to everything the
	     next section says, and it is bounded by the number above it.
	  3. SETTLE. `settleRun(player, banked)` turns those studs — plus that bonus — into cash and
	     hands it to `GarageService.addCash`, in full for a getaway and at
	     `RewardConfig.Crash.CashFraction` for every way a run ends badly. Idempotent per run, so a
	     bank and a wreck landing in the same frame pay once.
	  4. AWARD XP, on a bank only, to the body that was banked (`awardCarXp`, called by
	     GetawayService once the garage has agreed the (tier, body) pair is real). A levelled body
	     is faster the next time the player is in one.

	=== WHY THE SERVER MEASURES THE DISTANCE ITSELF ============================================

	Everything else about a run is the client's word, and has to be: the road, the traffic, the
	obstacles and the getaway truck are all client-built, so there is nothing on the server to check
	a claim against (RoadController's header explains why the world is local; ObstacleService,
	StealService and GetawayService each document their end of the resulting trust gap).

	Distance is the exception, and it is worth being explicit about why. THE SERVER OWNS THE CAR. It
	spawns it, it parents it, and it can read its position at any time — the client only holds
	network ownership, which moves the car but does not hide it. So the payout that pays out on
	EVERY run, including the ones that end in a wreck, is the one reward here with no trust gap at
	all. A client that lies about its tier gets a car it did not earn; it cannot lie about how far
	it drove.

	The one hand-off that remains is WHICH BODY the XP lands on, which is the client's claim about
	what it stole — the same accepted gap `GetawayService` documents, closed by the same fix (the
	server-rolled traffic spawn token, plan §4/S20). The AMOUNT is measured here regardless, so a
	false claim can only ever misdirect XP, never inflate it.

	=== …AND THE ONE THING THAT BREAKS THAT RULE ===============================================

	Near misses do — and trading paint, which is the same ladder's bottom rung. A near miss is a gap
	between the player's car and a traffic car, and traffic is client-local — there is no traffic car on
	this side to measure a gap against, and there cannot be one — so the only machine that can see one
	is the one that made it. `addNearMiss` is therefore the first client-reported term this service has
	ever paid out on, and it is worth being as explicit about that as the section above is about the
	opposite.

	WHAT KEEPS IT HONEST IS THE NUMBER THIS FILE DOES MEASURE. The bonus is capped at settle as a
	multiple of the run's own distance cash (`NearMissConfig.cap`), and distance comes off the car the
	server owns. So the ceiling on lying is "the run you actually drove, paid a few times over" rather
	than any number a client cares to send, and there is no version of this that pays for standing
	still. On top of that: reports are refused outright unless the player is in a live, unsettled,
	unheld run, rate-limited to stop a flood, capped in COUNT per run, and priced here from config —
	the wire carries a measured gap or a measured severity, and never an amount. NearMissConfig's header has the rest of the
	argument, including why the client is allowed to price the same near miss for its own toast.

	=== THE REBASE IS THE ONLY SUBTLETY =========================================================

	The client shifts its whole local world — and the car it owns — thousands of studs back toward
	the origin every `RaceConfig.RebaseThresholdStuds` (RoadController._shiftWorld). That replicates
	as the car teleporting, so a sample bigger than `RewardConfig.Sample.MaxStudsPerSecond` is not
	travel and is thrown away rather than counted or clamped. See that config's header for why
	discarding is the right treatment and what it costs (about seven studs, once per eight thousand).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local NearMissConfig = require(ReplicatedStorage.shared.Configs.NearMissConfig)
--- The heat a bank is multiplied by (`PoliceConfig.Heat`), and the tutorial run's exemption from it.
local PoliceConfig = require(ReplicatedStorage.shared.Configs.PoliceConfig)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
--- Whether a near miss must name an issued car (`addNearMiss`'s dated block).
local EncounterConfig = require(ReplicatedStorage.shared.Configs.EncounterConfig)
local RewardConfig = require(ReplicatedStorage.shared.Configs.RewardConfig)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local RewardService = Shard.new("RewardService"):withDependencies({ "RoadService", "GarageService" })

RewardService:withRemoteEvents({
	--[[ server -> client (cash, studs, banked, bonus, nearMisses, rubs, bonusEarned, mutation): the run is
		settled. Drives the payout lines on the return fade (RaceUIController). Carries no Instances,
		like every other race remote. `bonus`/`nearMisses`/`rubs` are the near-miss tally — the
		AUTHORITATIVE version of the numbers the toasts have already been showing during the run, which
		is why the results screen draws them from here rather than from anything the client counted.

		`bonusEarned` is that same bonus BEFORE the crash split, and it is sent for one reason: so the
		results screen can land on the figure the toasts added up to and count DOWN to what was kept,
		instead of asserting a number four times smaller than the fifteen receipts the player just
		watched. Zero means "nothing to count down from" — see where it is set. Sent rather than
		derived on the client because `payoutFor` floors and clamps, and a screen that recovered the
		starting figure by dividing would disagree with this file by a dollar or two on some runs.

		`mutation` is the weather key the banked car carried, or nil — the thing that multiplied
		everything above it (`WeatherConfig`). It is on the wire so the screen can NAME what happened:
		a payout five times the size of the last one with nothing on screen explaining it reads as a
		bug, and the player has to be able to connect the jackpot to the car they chased. ]]
	"RunSettled",
	-- server -> client (body, level): the car you banked just reached a new level.
	"CarLeveled",
	{
		--[[ client -> server (gap: number?, severity: number?): "I got this close to a car", or — with
			the second argument instead of the first — "I rubbed one this gently". The one report in this
			service, and the only client-reported term in the payout; see the header for what bounds it.
			A MEASUREMENT rather than an amount, so the pricing stays here. ]]
		--- The fourth is the passed car's encounter token (`EncounterConfig`), since 2026-09-28.
		NearMiss = function(player: Player, gap: unknown, severity: unknown, side: unknown, token: unknown)
			RewardService:addNearMiss(player, gap, severity, side, token)
		end,
	},
})

RewardService:withSignals({
	"RunSettled", -- (player, cash, studs, banked, bonus, nearMisses, rubs, bonusEarned)
	"CarLeveled", -- (player, body, level)
})

--[[ Where the car is, measured along the road.

	The forward axis comes from `RoadService` rather than from the car's own facing, and that is the
	whole reason this reads as travel rather than as wandering: the road runs one way for a whole
	race, so a car that swerves across three lanes has moved sideways, not forward, and only its
	progress DOWN the road counts. It is the same projection `RoadController` steers its recycling by
	and `ObstacleService` bounds its hit checks with, so all three agree about which way is on. ]]
function RewardService._alongOf(self, car: Model, forward: Vector3): number?
	local primary = car.PrimaryPart
	if not (primary and primary.Parent) then
		return nil
	end
	local along = primary.Position:Dot(forward)
	if along ~= along or math.abs(along) == math.huge then
		return nil
	end
	return along
end

--[[ Public (RaceService): start measuring. Called the moment the car exists, not when it goes live.

	Starting early is deliberate and costs nothing: the car is anchored on the deck until the
	driver's local road is built, so every sample until then is a zero. Starting LATE would be the
	risk — the first tile of road is the one every run has in common. ]]
function RewardService.beginRun(self, player: Player, car: Model)
	if not RewardConfig.Enabled then
		return
	end
	local RoadService = Shard.get("RoadService")
	local forward = RoadService and RoadService:getForward()
	if not forward then
		self.log:warn(string.format("No road frame; %s's run pays nothing.", player.Name))
		return
	end

	self._runs[player] = {
		car = car,
		world = WorldConfig.resolve(player:GetAttribute(WorldConfig.WorldAttribute)),
		wrecked = false,
		forward = forward,
		last = self:_alongOf(car, forward),
		studs = 0,
		settled = false,
		--[[ WHEN THIS RUN BEGAN, in server time. Nothing about the payout reads it — the distance is
			measured in studs and does not care how long they took. It exists for `WeatherService`,
			which bounds a mutation claim by asking whether that mutation's weather was running in
			this player's world WHILE THEY WERE DRIVING, and cannot ask that without a window.

			`workspace:GetServerTimeNow()` and not `os.clock()`, because the thing it is compared
			against is the weather schedule, and that is published to clients on the server clock. Two
			monotonic clocks that never meet would be worse than one shared one that drifts. ]]
		startedAt = workspace:GetServerTimeNow(),
		-- The near-miss tally, per run and nowhere else: nothing about a chain outlives the race it
		-- was driven in, so there is no profile key here and nothing to migrate. `misses` is clean
		-- passes and `paint` is rubs, counted apart because the results screen names them apart.
		bonus = 0,
		misses = 0,
		paint = 0,
		--- The stars this run has earned (`PoliceConfig.Heat`), off the steals `StealService` verified.
		heat = 0,
		nearStreak = 0,
		nearAt = nil, -- os.clock() of the last ACCEPTED near miss; drives both guards below
		-- The open half of a possible thread: the side of the last clean pass that has not threaded
		-- yet, and when it landed (`NearMissConfig.isThread`).
		threadSide = nil,
		threadAt = nil,
		threads = 0,
	}
end

--[[ Public (the `NearMiss` remote): an encounter with a traffic car, reported by the only machine
	that could see it — a clean pass (`gap`) or a rub (`severity`).

	Every guard here is doing a different job, and the order is cheapest-first:

	  • A LIVE RUN, UNSETTLED AND UNHELD. No run means nothing to pay into, and it is what stops this
	    being farmable from the lobby. `held` is a revivable wreck waiting on its offer (`holdRun`) —
	    the car is stationary behind a screen, so nothing can be passed, and a report arriving then is
	    either a straggler from the frame the HP ran out or a lie.
	  • A COUNT CAP, which bounds the bookkeeping rather than the money. No real run produces
	    `MaxPerRun` of these.
	  • A RATE FLOOR, and a deliberately tiny one. It is not a cooldown: threading the gap between two
	    cars in adjacent lanes is two genuine near misses on nearly the same frame, and refusing one of
	    them would refuse the most skilful thing a player can do on this road. See
	    NearMissConfig.Guard.
	  • A TIER THE ROAD COULD HAVE PRODUCED. `tierFor` is the same function the client resolved its
	    toast from, so anything that is not one of the three rungs — nil, NaN, 40 studs of daylight, a
	    severity that says the other car was flung across two lanes — buys nothing. Note which way the
	    "malformed" default points here: a clip prices garbage at the MAXIMUM because the only
	    exploitable direction there is downward (TrafficService), and this pays garbage NOTHING for
	    exactly the mirrored reason.

	The stamp is only taken when a report is ACCEPTED, so a refused one cannot shadow a real near miss
	a frame later — the same reasoning, and the same shape, as `TrafficService._onTrafficHit`. ]]
function RewardService.addNearMiss(self, player: Player, gap: unknown, severity: unknown, side: unknown, token: unknown)
	if not (RewardConfig.Enabled and NearMissConfig.Enabled) then
		return
	end
	local state = self._runs[player]
	if not state or state.settled or state.held then
		return
	end
	if state.misses + state.paint >= NearMissConfig.Guard.MaxPerRun then
		return
	end

	local tier = NearMissConfig.tierFor(gap, severity)
	if not tier then
		return
	end

	local now = os.clock()
	local since = if state.nearAt then now - state.nearAt else nil
	--[[ THREADING. Asked before the flood floor, because a genuine thread is two passes that can land
		in the same server frame, and the floor would refuse the second one — the most skilful pass on
		the road. A thread consumes its pair (`threadSide` is cleared below), so this exemption can be
		used once per two reports and cannot be turned into a flood. ]]
	local clean = tier ~= "Paint"
	local threads = clean
		and NearMissConfig.isThread(
			state.threadSide,
			side,
			if state.threadAt then now - state.threadAt else nil,
			NearMissConfig.Thread.ServerSlack
		)
	if not threads and since and since < NearMissConfig.Guard.MinInterval then
		return
	end

	--[[ === ONE CAR, ONE NEAR MISS — 2026-09-28 =================================================

		A security review found this could be farmed: the gap, severity and side are all the client's
		measurements, so a modified client could report perfect passes until the bonus hit its cap on
		every banked run. With encounters on (`EncounterConfig`), a report must name the token of a car
		the SERVER put on this player's road, and each token pays once (`EncounterService.
		claimNearMiss`) — so the bonus is bounded by the cars really issued, at the road's real rate,
		not by how fast a script can fire. The measurements still decide which rung of the ladder a
		pass is; what they can no longer do is invent passes. Claimed LAST, after every other refusal
		above, so a report turned away for another reason does not burn the car's one pass. ]]
	if EncounterConfig.Enabled then
		local Encounters = Shard.get("EncounterService")
		if not (Encounters and Encounters:claimNearMiss(player, token)) then
			return
		end
	end

	--[[ The chain, advanced from the same rule the client's toast advanced its own from — one shared
		function, one input (the seconds since the last one), so the number on screen and the number in
		the ledger are the same number without either side being told what the other decided. That
		includes the part where trading paint KEEPS a chain without building it, which is `advancesStreak`
		and is deliberately not a rule this file knows: it asks. ]]
	state.nearStreak =
		NearMissConfig.nextStreak(state.nearStreak, since, NearMissConfig.advancesStreak(tier))
	state.nearAt = now
	if tier == "Paint" then
		state.paint += 1
	else
		state.misses += 1
	end
	state.bonus += NearMissConfig.cashFor(tier, state.nearStreak, state.world)

	if threads then
		state.threads += 1
		state.bonus += NearMissConfig.cashFor("Thread", state.nearStreak, state.world)
		state.threadSide, state.threadAt = nil, nil
	elseif clean then
		state.threadSide, state.threadAt = NearMissConfig.sideOf(side), now
	end
end

-- Clean passes, what the tally is worth so far, and rubs. nil when they aren't in a run. For a
-- readout or a check; the payout reads the state directly.
function RewardService.getNearMisses(self, player: Player): (number?, number?, number?)
	local state = self._runs[player]
	if not state then
		return nil, nil, nil
	end
	return state.misses, state.bonus, state.paint
end

--[[ One sample of one run. Returns nothing — it only ever adds to `studs`.

	Backwards movement is never counted (reversing over road you were already paid for is not
	distance), and neither is a jump too big to be travel. Both fall out of one comparison. ]]
function RewardService._sample(self, state, elapsed: number)
	local car = state.car
	if not (car and car.Parent) then
		return
	end
	local along = self:_alongOf(car, state.forward)
	if not along then
		return
	end

	local previous = state.last
	state.last = along
	if not previous then
		return -- first sample of the run: nothing to measure against yet
	end

	local delta = along - previous
	if delta <= 0 then
		return
	end
	if delta > RewardConfig.Sample.MaxStudsPerSecond * elapsed then
		return -- a rebase (or a teleport), not travel — see the header
	end
	state.studs += delta
end

-- How far this player has driven in the current run. nil when they aren't in one.
function RewardService.getDistance(self, player: Player): number?
	local state = self._runs[player]
	return state and state.studs
end

--[[ Public (SpeedTrapService, 2026-09-28): the race car this run's distance is measured off, or nil.
	The same model a steal re-bodies, so it is the car the player is in whatever they have stolen —
	which is what makes it the right thing to read a trap's speed from on the server. ]]
function RewardService.getCar(self, player: Player): Model?
	local state = self._runs[player]
	return state and state.car
end

--[[ Public (GetawayService): when the current run began, in server time. nil when they aren't in one.

	NOT A REWARD NUMBER. It is here because this service is the only one that already keeps a record
	per live run, and the one thing that wants it — bounding a weather mutation claim against the
	schedule that was running while the player was driving (`WeatherService.couldHaveSpawned`) — has
	no business owning a second run registry to answer it. See `beginRun` for the choice of clock. ]]
function RewardService.getRunStart(self, player: Player): number?
	local state = self._runs[player]
	return state and state.startedAt
end

--[[ Public (RaceService): stop measuring for a moment, without ending the run.

	EXACTLY ONE CALLER AND ONE REASON: a wreck that is being offered a revive (`ReviveService`).
	Settling used to be what froze the distance — the sampler skips a settled run, and `wreckRace`
	settled the instant it cut the controls, so "the distance is final when the controls are cut" was
	true as a side effect. A revivable wreck cannot settle there (the run may not be over), so
	without this the run goes on being measured through the wreck beat and the whole offer window:
	the car's coast to a stop is added to the total, and a car wrecked at speed banks whatever it
	slides while the player reads the screen. Small, but it is distance nobody drove.

	Held, `state.last` goes stale by however far the car moves meanwhile — which is exactly what the
	resume wants. `_sample` discards a backwards delta, and a revive sets the car DOWN the road from
	where it died (`ReviveConfig.SetBackStuds`), so the first sample after the hold re-anchors on the
	new position rather than booking the teleport as travel.

	The set-back is then driven a second time and paid for a second time, which is correct rather
	than merely tolerated: this measures FORWARD TRAVEL, and the car does travel it twice. It is
	about six metres on a run measured in thousands, and the alternative — docking the total on
	revive — would be the meter disagreeing with the road. ]]
function RewardService.holdRun(self, player: Player, held: boolean)
	local state = self._runs[player]
	if state then
		state.held = held
	end
end

--[[ What a run is worth right now, as `settleRun` would pay it: the cash, the bonus half of it after
	the crash split, and the capped bonus before it. One place for the arithmetic, so the preview below
	and the real payout cannot drift apart. `settleRun` has the argument for the cap. ]]
function RewardService._payoutOf(self, state, banked: boolean, multiplier: number): (number, number, number)
	local bonus = NearMissConfig.cap(state.bonus, RewardConfig.cashFor(state.studs, true, state.world))
	local cash, bonusPaid = RewardConfig.payoutFor(state.studs, bonus, banked, multiplier, state.world)
	return cash, bonusPaid, bonus
end

--[[ Public (ReviveService): what this run would pay if it ended as a crash NOW, without settling it.

	The revive question carries the run's results (`NewUIConfig.WreckPanel`), and it is up while the
	run is deliberately still open, so the real figures do not exist yet. The meter is held for the
	whole offer (`holdRun`), so the crash this previews is the crash `settleRun` pays a moment later.
	Same fields as the `RunSettled` remote; nil when there is no unsettled run. ]]
function RewardService.previewRun(self, player: Player)
	local state = self._runs[player]
	if not state or state.settled then
		return nil
	end
	local Encounters = Shard.get("EncounterService")
	local stolen = if Encounters then Encounters:stolenCar(player) else nil
	local cash, bonusPaid, bonus = self:_payoutOf(state, false, WeatherConfig.multiplierOf(if stolen then stolen.mutation else nil))
	--- The 2x Cash pass, exactly as the settlement applies it, so the panel quotes what will be paid.
	local Garage = Shard.get("GarageService")
	local earned = if Garage then Garage:incomeMultiplier(player) else 1
	cash, bonusPaid, bonus = cash * earned, bonusPaid * earned, bonus * earned
	return {
		cash = cash,
		studs = math.floor(state.studs),
		bonus = bonusPaid,
		nearMisses = state.misses,
		rubs = state.paint,
		-- `settleRun`'s rule for a crash: the figure before the split, or 0 when there is no drop.
		bonusEarned = if bonusPaid <= 0 or bonus <= bonusPaid then 0 else bonus,
	}
end

--[[ Public: the run is over — pay for the distance. Returns the cash awarded.

	`banked` is the whole difference between the two endings: a getaway pays the lot, and every
	other way out pays `RewardConfig.Crash.CashFraction` of it. There is no third case on purpose —
	running out of HP, whiffing a bail onto the tarmac, falling out of the world, dying in the seat
	and disconnecting mid-run all arrive here as "not banked", so no ending can quietly pay
	differently from the one next to it.

	IDEMPOTENT PER RUN, and that guard is load-bearing rather than defensive: `RaceService` runs a
	shared "this run is already ending" flag precisely because a bank and a wreck can land in the
	same frame, and `leaveRace` settles anything that reached the end without either. Whichever
	arrives first decides what the run was worth. ]]
function RewardService.settleRun(self, player: Player, banked: boolean, mutation: string?): number
	local state = self._runs[player]
	if not state or state.settled then
		return 0
	end
	state.settled = true
	state.banked = banked
	--[[ THE WEATHER'S CUT. `mutation` is a key that `GetawayService` has already sanitised AND bounded
		against the schedule (`WeatherService.couldHaveSpawned`) — this service takes it on trust
		precisely because that check has happened, and re-checking it here would put the bound in two
		places that have to agree forever.

		nil on every ending but a bank: a wreck awards no car, so there is nothing for a mutation to
		be on. `multiplierOf` answers 1 for a nil, so nothing below needs a branch. ]]
	local Encounters = Shard.get("EncounterService")
 local stolen = if Encounters then Encounters:stolenCar(player) else nil
 mutation = WeatherConfig.sanitize(if stolen then stolen.mutation else mutation)
 state.mutation = mutation
 if not banked and state.wrecked and stolen then
  local Garage = Shard.get("GarageService")
  if Garage then Garage:tryStarterInsurance(player, stolen, state.world) end
 end
	local multiplier = WeatherConfig.multiplierOf(mutation)
	--[[ HEAT PAYS ON A BANK ONLY (`PoliceConfig.Heat`, 2026-10-19). It is the price of the escape the
		truck waited for (`GetawayConfig.PoliceLock`); a wreck escaped nothing. Counted here off the
		server's own verified steals (the `CarStolen` hook in `start`), never off the client. ]]
	local heatMultiplier = if banked then PoliceConfig.heatMultiplier(state.heat) else 1
	multiplier *= heatMultiplier

	--[[ THE PAYOUT IS CONFIRMED AGAINST THE BALANCE, not assumed from the call.

		`GarageService.addCash` is a no-op for a player whose profile has not loaded — it is reached
		from a Touched handler and from here, so it answers "not yet" rather than yielding (see its
		`_profile`). Reporting the number we asked for would then put "+$57" on the return fade for
		money nobody has, which is the one failure mode a results screen must not have: the player
		would go and look for it. Comparing the balance is exact, because a positive amount always
		moves it when there is a profile to move. ]]
	local studs = state.studs
	--[[ THE BONUS IS FENCED HERE, at the one moment the distance is final, and against the distance
		itself. That is the whole security model for the only client-reported money in the game (see the
		header and `NearMissConfig.cap`), and settle is the right place for it precisely BECAUSE it is
		late: capping mid-run would mean refusing reports a player had already been shown a toast for,
		and the run's own denominator isn't known until it ends. ]]
	--[[ THE CAP IS MEASURED AGAINST THE UNMULTIPLIED RUN, deliberately. `NearMissConfig.cap` exists to
		stop the one client-reported number in the game from outgrowing the one the server measured
		itself, and that relationship is about DRIVING — how much bonus a given distance may be worth.
		Letting a mutation raise the ceiling would mean a lucky car made the client's own claim more
		valuable, which is exactly the wrong direction for a fence. The multiplier is applied to both
		halves afterwards, inside `payoutFor`, so a mutated run still pays more bonus; it just cannot
		claim more of it. ]]
	local cash, bonusPaid, bonus = self:_payoutOf(state, banked, multiplier)
	--- The 2x Cash pass on the run's payout, both halves alike so the results screen adds up.
	local Garage = Shard.get("GarageService")
	local earned = if Garage then Garage:incomeMultiplier(player) else 1
	cash, bonusPaid, bonus = cash * earned, bonusPaid * earned, bonus * earned
	if cash > 0 then
		local GarageService = Shard.get("GarageService")
		local before = if GarageService then GarageService:getCash(player) else nil
		if not (before and GarageService:addCash(player, cash) > before) then
			self.log:warn(string.format("%s's %d could not be paid (no garage or no profile).", player.Name, cash))
			-- Nothing landed, so nothing may be REPORTED as having landed — including the bonus half.
			-- The results screen draws what it is sent, and a bonus line over money nobody has is the
			-- one failure a payout screen must not have (see the note above).
			cash, bonusPaid = 0, 0
		end
	end
	state.cash = cash
	state.bonusPaid = bonusPaid

	--[[ What the near misses were worth before the crash split took its share, for the results screen
		to count down FROM. Zero is the signal for "no countdown, just show the figure", and it covers
		the three cases where an animated drop would be a lie:

		  • a BANKED run — there is no split, `bonusPaid` is the whole of it, and a line that ticked
		    down from itself would invent a loss the player did not take;
		  • a payout that could not be PAID (above) — nothing landed, so nothing may be reported as
		    having landed, and a number the screen animates away from is still a number it showed;
		  • anything where the fence or the clamp left the two equal, which has no drop to draw.

		This is the capped figure (`NearMissConfig.cap`), not the raw sum of the toasts, and that is
		the honest starting point: the cap is what the run's near misses were actually worth. On the
		runs measured so far it never bound, so in practice this IS the toast total. ]]
	local bonusEarned = if banked or bonusPaid <= 0 or bonus <= bonusPaid then 0 else bonus

	--[[ THE ROAD WAS DRIVEN EITHER WAY, so the map's personal best is recorded on both endings —
		the same reasoning the results screen's ladder bar is drawn for a wreck. What this run was
		WORTH depends on `banked`; how far it got does not.

		`worldOf` is read here rather than captured at the start of the run because it cannot have
		moved: `WorldService.setWorld` refuses while `RaceService:isRacing`, which is what "the run
		you are in is the world you are in" means. ]]
	local WorldService = Shard.get("WorldService")
	if WorldService then
		WorldService:recordDistance(player, state.world, studs)
	end

	--[[ The mutation rides along to the SCREEN but not to the SIGNAL. The screen wants to name what
		multiplied the payout, because a number five times bigger than the last one with nothing
		explaining it reads as a bug. The signal's existing subscribers — quests, the leaderboard,
		analytics, the tutorial — are all counting runs and studs, and appending a ninth positional
		argument to a signal four services unpack by position is a cost with no buyer. When one of
		them wants it, it should go on as a named field rather than as argument nine. ]]
	self:getRemoteEvent("RunSettled")
		:Fire(player, cash, math.floor(studs), banked, bonusPaid, state.misses, state.paint, bonusEarned, mutation, heatMultiplier)
	self:getSignal("RunSettled"):Fire(player, cash, studs, banked, bonusPaid, state.misses, state.paint, bonusEarned)
	self.log:info(string.format(
		"%s drove %d studs and %s%s — paid %d%s.",
		player.Name,
		math.floor(studs),
		if banked then "got away" else "wrecked",
		if mutation then string.format(" with a %s car (%s)", WeatherConfig.nameOf(mutation), WeatherConfig.formatMultiplier(multiplier)) else "",
		cash,
		if state.misses + state.paint > 0
			then string.format(
				" (%d of it from %d near miss(es) and %d rub(s))",
				bonusPaid,
				state.misses,
				state.paint
			)
			else ""
	))
	--- The heat that went into it (`PoliceConfig.Heat`), so a missing results stamp can be traced here.
	self.log:info(string.format("%s's heat: %d star(s), arm %s, paid x%.2f.", player.Name, state.heat, tostring(PoliceConfig.heatOn(player)), heatMultiplier))
	return cash
end

--[[ Public (GetawayService): the bank was real and the garage has taken the car — give the body
	its XP for the run.

	SEPARATE FROM `settleRun` BECAUSE THE TWO KNOW DIFFERENT THINGS. Cash is settled by RaceService
	the instant the run ends, which is what makes the wreck path and the bank path one path. The
	BODY is not known there: `RaceService.bankRun` is handed a tier and nothing else, and the name
	of the car only becomes trustworthy one step later, after `GarageService` has agreed the (tier,
	body) pair exists on its own roster. So XP is awarded from there, against the distance this
	service already measured.

	Reads the run state rather than taking a distance argument, so there is exactly one measurement
	behind both payouts and no way for them to disagree about the same run. ]]
function RewardService.awardCarXp(self, player: Player, body: unknown): (number, boolean)
	local state = self._runs[player]
	if not (state and RewardConfig.Enabled) then
		return 1, false
	end
	if type(body) ~= "string" or body == "" then
		return 1, false
	end

	local xp = RewardConfig.xpFor(state.studs)
	if xp <= 0 then
		return 1, false
	end

	local GarageService = Shard.get("GarageService")
	if not GarageService then
		return 1, false
	end

	local level, leveled = GarageService:addCarXp(player, body, xp)
	if leveled then
		self:getRemoteEvent("CarLeveled"):Fire(player, body, level)
		self:getSignal("CarLeveled"):Fire(player, body, level)
	end
	self.log:info(string.format(
		"%s earned %d XP in their %s%s.",
		player.Name,
		xp,
		body,
		if leveled then string.format(" — now level %d", level) else ""
	))
	return level, leveled
end

--[[ Public (RaceService): stop measuring, settling first if nothing else did.

	The unsettled case is every ending that is not a wreck and not a bank: a rider who died in the
	seat, a player who left mid-run, an entry that fell over before the car went live. They settle as
	crashes, which is the honest reading — the car is gone and they did not drive it into a truck —
	and it means there is no way out of a race that skips the payout entirely. ]]
function RewardService.endRun(self, player: Player)
	local state = self._runs[player]
	if not state then
		return
	end
	if not state.settled then
		self:settleRun(player, false)
	end
	self._runs[player] = nil
end

RewardService:withLifecycle({
	init = function(self)
		-- [Player] = { car, forward, last, studs, settled, held?, banked?, cash?,
		--              bonus, misses, paint, nearStreak, nearAt?, bonusPaid? }
		self._runs = {}
	end,

	start = function(self)
		if not RewardConfig.Enabled then
			self.log:info("Disabled by config — runs pay nothing.")
			return
		end
		if not GarageConfig.Enabled then
			self.log:warn("GarageConfig is off, so there is nowhere to pay a run into.")
		end

		--[[ The distance poll. Throttled off Heartbeat rather than given its own loop for exactly the
			reason RaceService's void guard is: it can never outlive the service, and it costs nothing
			at all while nobody is racing. One dot product per live race car per tenth of a second. ]]
		local sinceSample = 0
		RunService.Heartbeat:Connect(function(dt)
			sinceSample += dt
			if sinceSample < RewardConfig.Sample.Interval then
				return
			end
			local elapsed = sinceSample
			sinceSample = 0
			for _, state in self._runs do
				-- `held` is a revivable wreck waiting on its offer: the run is not over, but nothing
				-- happening to the car right now is being driven. See `holdRun`.
				if not (state.settled or state.held) then
					self:_sample(state, elapsed)
				end
			end
		end)

		--[[ `RaceService.leaveRace` already settles a player who leaves mid-run, and PlayerRemoving
			reaches it — but the two connections run in whichever order they were made, and clearing
			the state first would silently drop the payout. So this settles rather than discards, and
			`endRun` is idempotent, so whichever of the two arrives first is the one that pays. ]]
		Players.PlayerRemoving:Connect(function(player)
			self:endRun(player)
		end)

		--[[ HEAT, counted off the steals the server verified (`StealService.CarStolen`, which only fires
			for a redeemed encounter token), with the same rule the HUD draws by
			(`PoliceConfig.heatOfSteal`). The tutorial's run earns none, the client's exemption read off
			the same attribute the server publishes. ]]
		local Steals = Shard.get("StealService")
		if Steals then
			Steals:getSignal("CarStolen"):Connect(function(player: Player, tier: number)
				local state = self._runs[player]
				if not state or state.settled then
					return
				end
				local tutorial = TutorialConfig.isTutorialRun(player:GetAttribute(TutorialConfig.StepAttribute))
				if (tutorial and not PoliceConfig.Heat.Tutorial.Enabled) or not PoliceConfig.heatOn(player) then
					return
				end
				state.heat = math.min(PoliceConfig.Heat.Max, state.heat + PoliceConfig.heatOfSteal(tier))
			end)
		end

		--[[ THE A/B ARM (`PoliceConfig.Heat.Remote`): each player's Gamebeast value, stamped on them so
			the client's police and this file's payout read the same thing. Only a boolean is written;
			until one arrives `heatOn` answers with the fallback, on both sides alike. ]]
		local remote = PoliceConfig.Heat.Remote
		if remote.Enabled then
			local function observe(player: Player)
				task.spawn(function()
					local ok, err = pcall(function()
						local Gamebeast = require(ReplicatedStorage:WaitForChild("Gamebeast"))
						Gamebeast:GetService("Configs"):ObserveForPlayer(player, remote.Path, function(value)
							if type(value) == "boolean" and player.Parent then
								player:SetAttribute(remote.Attribute, value)
							end
						end)
					end)
					if not ok then
						self.log:warn("Gamebeast config unavailable, heat uses its fallback: " .. tostring(err))
					end
				end)
			end
			Players.PlayerAdded:Connect(observe)
			for _, player in Players:GetPlayers() do
				observe(player)
			end
		end
	end,
})

-- Approved economy balance, 2026-10-04.
function RewardService.markWreck(self, player: Player, wrecked: boolean)
 local state = self._runs[player]
 if state and not state.settled then state.wrecked = wrecked end
end

return RewardService
