--[[
	ObstacleService  (server — authoritative HP)
	-------------------------------------------
	Owns the two things the client is not allowed to own: the race's obstacle seed, and the
	car's Health.

	How a hit travels:
	  1. RaceService calls `beginRace(player, car)` on entry. We mint a seed, stamp the car's
	     HitBox back to full Health, and hand the seed back so RaceService can ship it with
	     RaceStart. The client builds its obstacles from that seed (ObstacleLayout).
	  2. The client owns the car AND the road, so it is the only side that can see a
	     collision. It reports one number: the obstacle id it hit.
	  3. We re-derive the layout from the seed, look the id up, and decide the damage from
	     ObstacleConfig — the client never sends an amount. Damage lands on the HitBox's
	     `Health` attribute, which replicates to the owner for free (that's what the HP bar
	     reads — no extra net traffic).
	  4. Health hits 0 → `RaceService:wreckRace(player)` runs the wreck-and-return beat.

	Hazards this service doesn't own price themselves and come in through `applyHazardDamage`
	(TrafficService's car clips today). HP still only ever moves in `_applyDamage`, and the rate
	cap still spans every hazard, so adding one can't widen what a client is able to do.

	IT ALSO OWNS THE ROAD PICKUPS, and that is not scope creep — it is the same three things this
	file already owns. A health pack is (a) an entry in the seeded layout, (b) a claim a client makes
	by id and the server validates, and (c) a write to Health. There is nowhere else all three of
	those live. `PickupConfig` has the design; what is here is the slot (one pack, in the race
	state, mirrored to a player attribute for the HUD), `_applyHeal` — the mirror of `_applyDamage`,
	and the only other place HP moves by an amount — and the rule that a repair collected while you
	are already hurt spends itself instead of banking.

	The nitro pack is the one payout this service does NOT apply, because the tank is a client-owned
	number; it clears the slot and fires `PickupUsed`. See `_spend`.

	On trust: an exploiting client can under-report its own hits, and no amount of server
	code changes that while the road it drives on is client-built. That's an accepted
	trade (driving is solo, so the only person cheated is the cheater — see RoadController
	for why the road is local at all). What the server DOES guarantee is that HP only ever
	moves by a configured amount, for an obstacle that really exists in the layout, once
	each, at a lane the car was actually near, at a bounded rate. If the planned car-theft
	flow ever puts two players on one shared road, this is the module that has to grow real
	position replay — noted deliberately.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local ObstacleConfig = require(ReplicatedStorage.shared.Configs.ObstacleConfig)
local ObstacleLayout = require(ReplicatedStorage.shared.Modules.ObstacleLayout)
--[[ For the onboarding's staged first run, and for nothing else — see `_damageFloor`. It is a config
	require and not a dependency on `TutorialService`: what this needs is one string off the player,
	and taking the service would be a start-order edge for a lookup. ]]
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
--- For the spawn shield's timings only (`RaceConfig.SpawnShield`). A config require rather than a
--- dependency on `RaceService`, for the same reason `TutorialConfig` is one: this needs two numbers.
local RaceConfig = require(ReplicatedStorage.shared.Configs.RaceConfig)
--- The road pickups: what a pack pays and whether it banks. A config require rather than a service,
--- because a pack has no server behaviour of its own — the slot lives in this file's race state,
--- next to the HP it spends, for the reason `PickupConfig`'s header gives.
local PickupConfig = require(ReplicatedStorage.shared.Configs.PickupConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local ObstacleService = Shard.new("ObstacleService"):withDependencies({ "RoadService" })

ObstacleService:withRemoteEvents({
	--[[ server -> client: a pack just left the slot. Carries the pack's NAME and nothing else — the
		client already has `PickupConfig` and can read the payout out of it, and a server that sent
		an amount would be inventing a second copy of a number that is already shared.

		It exists for the one payout this service cannot apply itself: nitro lives in
		`NitroController._tank`, which is client-owned (see `PickupConfig`'s header for why that is
		the honest split rather than a hole). The heal has already landed by the time this fires, so
		for a health pack this is purely the cue to play the beat. ]]
	"PickupUsed",
	{
		-- client -> server: "I hit obstacle <id>". Payload is one number, on purpose.
		ObstacleHit = function(player: Player, id: any)
			ObstacleService:_onObstacleHit(player, id)
		end,
		-- client -> server: "I'm scraping the guardrail". No payload at all — there's nothing
		-- to identify, and unlike an obstacle we can verify this one from the car's position.
		WallHit = function(player: Player)
			ObstacleService:_onWallHit(player)
		end,
		--[[ client -> server: "spend what's in my slot". No payload either, and that is the whole
			trust story for the heal: the client cannot name a pack, an amount or a target — it can
			only ask the server to act on the record the server itself wrote when it validated the
			pickup. See `_usePickup`. ]]
		UsePickup = function(player: Player)
			ObstacleService:_usePickup(player)
		end,
	},
})

-- The part that owns Health: the chassis's mid-height hull (handoff doc §5). Falls back to
-- the car Model so a car rigged without one still tracks HP instead of silently ignoring it.
function ObstacleService._healthHolder(self, car: Model): Instance
	local hitBox = car:FindFirstChild(ObstacleConfig.HitBoxName, true)
	return hitBox or car
end

function ObstacleService.getMaxHealth(self, car: Model): number
	local holder = self:_healthHolder(car)
	local max = holder:GetAttribute("MaxHealth") or car:GetAttribute("MaxHealth")
	if type(max) ~= "number" or max <= 0 then
		max = ObstacleConfig.DefaultMaxHealth
	end
	return max
end

-- Write Health everywhere a reader might look: the HitBox (what the HP bar watches) and
-- the car Model (what the handoff doc mirrors it onto).
function ObstacleService._setHealth(self, car: Model, health: number)
	local holder = self:_healthHolder(car)
	holder:SetAttribute("Health", health)
	if car ~= holder then
		car:SetAttribute("Health", health)
	end
end

--[[ The 2x Car HP pass, as a factor (`ObstacleConfig.HealthPass`). 1 for everybody without it.

	NON-YIELDING, because it is on the spawn path and `PassService.owns` reads a cache the join
	already warmed. A player whose Roblox lookup has not landed answers 1 and drives a normal car
	for a few seconds — see `PassService.owns` on why false is the safe direction for a seam, and
	`applyHealthPass` for what closes that window when the answer does arrive.

	A MISSING `PassService` ANSWERS 1 RATHER THAN THROWING. This service starts whether or not the
	entitlement layer did, and a race that refuses to begin because a pass could not be read is a
	worse outcome than a race that begins un-doubled. ]]
function ObstacleService._healthFactor(self, player: Player?): number
	if not player then
		return 1
	end
	local PassService = Shard.get("PassService")
	if PassService and PassService:owns(player, ObstacleConfig.HealthPass.Key) then
		return ObstacleConfig.HealthPass.Multiplier
	end
	return 1
end

--[[ The same two places, for the CEILING. Ignores anything that isn't a usable number so a caller
	with nothing to say can just pass nil and get the car's authored value.

	BOTH PLACES MATTER, and it is the HitBox that bites: `getMaxHealth` reads the holder FIRST, and
	every rig in `Workspace.CarSystem` has `MaxHealth = 100` authored on its HitBox. Write only the
	Model and the read comes back 100 no matter what the car is — which is exactly the bug that hid
	inside `refillHealth` until this was pulled out of it.

	IT TAKES THE PLAYER BECAUSE IT IS WHERE THE 2X CAR HP PASS LANDS. Being the only writer of the
	ceiling is what makes this the right place for it: the pass covers the spawn, the steal and the
	revive without any of the three learning it exists, exactly as `GarageConfig.rateOf` folds the
	income multiplier in for every caller at once. `ObstacleConfig.HealthPass` has the argument for
	why the pass multiplies the ceiling rather than dividing the damage.

	THE PASS IS APPLIED TO WHAT THE CALLER ASKED FOR, NOT TO WHAT IS ALREADY ON THE CAR, which is
	the reason a nil still returns early rather than re-reading and re-multiplying. A revive passes
	nil deliberately — "leave the ceiling where it is" — and that ceiling was doubled by the spawn
	that wrote it. Doubling it again on every revive is the bug this early return prevents. ]]
function ObstacleService._setMaxHealth(self, player: Player?, car: Model, maxHealth: number?)
	if type(maxHealth) ~= "number" or maxHealth ~= maxHealth or maxHealth <= 0 then
		return
	end
	local factor = self:_healthFactor(player)
	maxHealth *= factor
	local holder = self:_healthHolder(car)
	holder:SetAttribute("MaxHealth", maxHealth)
	if car ~= holder then
		car:SetAttribute("MaxHealth", maxHealth)
	end
	--[[ Remember WHICH factor is baked into the number just written, because `applyHealthPass` has
		no other way to tell a doubled ceiling from an authored one — 160 is a legitimate authored
		ceiling as well as a doubled 80. Being the only writer is what makes this the only place
		that can honestly answer it. ]]
	local state = player and self._races[player]
	if state then
		state.healthFactor = factor
	end
end

function ObstacleService.getHealth(self, player: Player): number?
	local state = self._races[player]
	if not (state and state.car.Parent) then
		return nil
	end
	return self:_healthHolder(state.car):GetAttribute("Health")
end

--[[ Public: how much of its HP the run car has left, as a fraction in [0, 1], or nil for a player
	who is not racing (or a car with no usable ceiling).

	It exists for the bank (2026-09-28): a banked car keeps the condition it arrived in
	(`MarketValueConfig.Condition`), and a FRACTION is the only reading that means the same thing
	across the roster — 40 HP is a scratch on a supercar and a wreck on a beater, because the ceiling
	moves with the car (`getMaxHealth`, `_healthFactor`).

	THE CALLER MUST ASK BEFORE THE RUN ENDS. `endRace` drops the state this reads, and
	`RaceService.bankRun` ends the race — so `GetawayService` reads this first and banks second. ]]
function ObstacleService.getHealthFraction(self, player: Player): number?
	local state = self._races[player]
	if not (state and state.car.Parent) then
		return nil
	end
	local health = self:getHealth(player)
	local max = self:getMaxHealth(state.car)
	if type(health) ~= "number" or type(max) ~= "number" or max <= 0 then
		return nil
	end
	return math.clamp(health / max, 0, 1)
end

--[[ Public (RaceService): start tracking a race. Returns the obstacle seed to hand the
	client with RaceStart. Cars are cloned fresh per race so Health starts at the template
	value anyway — we stamp it explicitly so a template edited mid-session can't ship a
	car that starts pre-damaged.

	`maxHealth` is the car's ceiling from `CarConfig`, resolved by the caller because it is the one
	that knows which car this is. Optional: nil leaves whatever the rig was authored with, which is
	the old behaviour and still what a car spawned by anything but RaceService would get. ]]
function ObstacleService.beginRace(
	self,
	player: Player,
	car: Model,
	world: number?,
	maxHealth: number?
): (number, ObstacleLayout.Bench?)
	local seed = self._rng:NextInteger(1, 2147483646)
	self._races[player] = {
		seed = seed,
		car = car,
		--[[ The admin bench, if one is armed (`setBench`). Copied into the run rather than read
			back off `_bench` on every hit, for the same reason the world beside it is: it decides
			what the layout SAYS, and a bench changed or cleared mid-run would have the server
			pricing hits against a road the client is not driving. Armed once, driven once. ]]
		bench = self._bench[player],
		--[[ The world this run is in, kept HERE rather than re-read off the player when a hit
			arrives. The two checks below measure a reported hit against the road's lane centre,
			and lane centre is a per-world number — so reading it fresh would price a hit against
			whatever world the player is in NOW. They cannot change worlds mid-race, so today those
			are the same answer; the day a run can outlive a switch, this is already correct. ]]
		world = world,
		consumed = {}, -- [obstacleId] = true — an obstacle can only ever cost you HP once
		--[[ How many of those consumed ids were PACKS rather than hazards (`PickupConfig`). Counted
			rather than derived, because `clearedFor` would otherwise have to resolve every id in
			`consumed` back through the layout to tell the two apart — and it needs the number to
			subtract the right thing: collecting a health pack is not "an obstacle you failed to
			dodge". ]]
		pickupsTaken = 0,
		--- Hazards charged through `applyHazardDamage` (traffic clips and the like). Only counted, for
		--- `hitCount`'s integrity telemetry (`EncounterConfig.Telemetry`); nothing is priced off it.
		hazards = 0,
		--- The pack this player is carrying, or nil. THE authority; `PickupConfig.SlotAttribute` on
		--- the Player is a mirror of it for the HUD. Written only through `_setSlot`.
		slot = nil :: string?,
		windowStart = os.clock(),
		windowCount = 0,
		wallAt = 0, -- os.clock() of the last guardrail scrape we charged for
		wrecked = false,
		--- os.clock() deadline of a lit Star (`_spend`); 0 when none. Read by `_applyDamage`.
		starUntil = 0,
		--[[ The spawn shield (`RaceConfig.SpawnShield`), armed HERE rather than by RaceService
			calling in a moment later, because this is the line the run becomes damageable on: the
			car has HP from the `_setHealth` below and the seed goes back to the caller on the next
			one. A shield armed after that is a shield with a hole in it exactly where the bug is.

			An absolute deadline rather than a countdown, so nothing has to tick it: every read is
			`os.clock() < shieldUntil`, and a run whose client never reports in simply runs out. ]]
		shieldUntil = if RaceConfig.SpawnShield.Enabled
			then os.clock() + RaceConfig.SpawnShield.MaxTime
			else 0,
	}
	-- Ceiling first, then fill to it — `_setHealth` reads the ceiling back through `getMaxHealth`,
	-- so doing these the other way round would start the car on the previous number.
	self:_setMaxHealth(player, car, maxHealth)
	self:_setHealth(car, self:getMaxHealth(car))
	--- The bench goes back with the seed and for the same reason: it is something the client has to
	--- BUILD from, so it rides with the seed in `RaceStart` rather than being asked for later.
	return seed, self._races[player].bench
end

--[[ Public (RaceService): stop tracking. Safe to call for a player who was never racing.

	The slot goes with the run, and the ATTRIBUTE has to be cleared explicitly: the state table is
	dropped on the next line, but the mirror lives on the Player and would otherwise outlive the race
	that filled it — leaving a lobby player wearing a pack, and the next run starting with one in the
	slot it never collected. Unconditional, so a run that ended any way at all lands here. ]]
--[[ Public (`EncounterService`'s integrity telemetry, 2026-09-28): how many times this run has been
	charged for hitting something — obstacles (packs excluded) and hazards. nil once the race is gone,
	so ask while it is live (`RunSettled` is, for `clearedFor`'s reason). A COUNT OF REPORTS THAT
	ARRIVED: a client that sends none shows zero, which is exactly what the telemetry is looking for. ]]
function ObstacleService.hitCount(self, player: Player): number?
	local state = self._races[player]
	if not state then
		return nil
	end
	local consumed = 0
	for _ in state.consumed do
		consumed += 1
	end
	return consumed - state.pickupsTaken + state.hazards
end

function ObstacleService.endRace(self, player: Player)
	player:SetAttribute(PickupConfig.SlotAttribute, nil)
	self._races[player] = nil
end

--[[ Public: is this run still inside its spawn shield? (`RaceConfig.SpawnShield`.)

	Read by `_applyDamage` on every hit, and by `RaceService._catchFall` to decide whether a car that
	has left the world is a failed handoff or a wreck — a shielded run has by definition not had a
	chance to earn either.

	False for a player who is not racing, which is the honest answer and also the safe one: every
	caller is asking "may I skip charging this?", so the fallback has to be "no". ]]
function ObstacleService.isShielded(self, player: Player): boolean
	local state = self._races[player]
	return state ~= nil and os.clock() < state.shieldUntil
end

--[[ Public (RaceService): the client says it is genuinely driving — start the shield's last beat.

	NOT "drop the shield", and the difference is the whole of `SettleTime`: the moment the pause
	lifts is the moment a car that spent it parked in the road is most likely to be sitting inside a
	traffic shell, so cutting the shield here would hand back the same unearned hit one beat later.
	The deadline is pulled IN to `SettleTime` from now, never pushed out, so a client that reports
	late (or twice, or is lying to buy itself a longer shield) can only ever shorten its own cover.

	A no-op for a run that is not shielded any more, and for a player who is not racing — both are
	ordinary: the report arrives on a timer the client owns, and the run it names may have ended. ]]
function ObstacleService.reportDriving(self, player: Player)
	local state = self._races[player]
	if not state then
		return
	end
	state.shieldUntil = math.min(state.shieldUntil, os.clock() + RaceConfig.SpawnShield.SettleTime)
end

--[[ Public (RaceService): re-arm the shield for a car being handed back mid-run — a revive.

	A revive is an entry: the car is set down stationary on the lane and the client has to pick it
	up again, and everything the shield exists to stop at a spawn can happen here too (`reviveRace`
	holds the car for `ReviveConfig.ReviveHoldTime` behind the respawn screen, and the road it is
	being put back on is a road with traffic already on it). Charging a player HP for that window is
	how a paid revive becomes a second wreck.

	Pushes the deadline OUT, unlike `reportDriving`, because this is the server re-opening the
	window rather than a client reporting on it. ]]
function ObstacleService.rearmShield(self, player: Player)
	local state = self._races[player]
	if not (state and RaceConfig.SpawnShield.Enabled) then
		return
	end
	state.shieldUntil = math.max(state.shieldUntil, os.clock() + RaceConfig.SpawnShield.MaxTime)
end

--[[ Public (StealService): the player just took a car, so give them its HP.

	HP GOES UP IN EXACTLY ONE PLACE, for the same reason it only goes down in one: every reader
	(the HP bar, the wreck check, the plausibility checks) has to agree with every writer, and the
	cheapest way to guarantee that is for there to be one of each. The caller decides the amount
	from its own config — `StealConfig.TierStats` — exactly the way `applyHazardDamage` lets
	TrafficService price a clip. This service still owns the number that lands.

	`maxHealth` re-stamps the ceiling first, because a steal changes which car you're in and a
	Tier 5 is meant to be tougher than the beater you started in. Written to the same two places
	`_setHealth` writes Health, so `getMaxHealth` and the HUD can't disagree about it.

	Refuses a wrecked race outright: the wreck beat is already running and handing a dead car its
	HP back would leave a player driving a car the server has finished with. Returns whether it
	landed, so the caller can hold its cooldown until it did. ]]
function ObstacleService.refillHealth(self, player: Player, maxHealth: number?): boolean
	local state = self._races[player]
	if not state or state.wrecked then
		return false
	end
	local car = state.car
	if not (car and car.Parent) then
		return false
	end

	self:_setMaxHealth(player, car, maxHealth)

	--[[ Consumed obstacles are deliberately NOT cleared. They're keyed to this race's seed and the
		stretch of road they sit on, and that road is behind the player now — an id can only ever be
		claimed again by a client replaying an old hit, which is the one direction worth closing.
		A steal moves you forward; it doesn't rewind the course. ]]
	self:_setHealth(car, self:getMaxHealth(car))
	return true
end

--[[ Public (ReviveService): the run is going again — take the wreck flag off and fill the car back
	up. The exact inverse of the `health <= 0` branch in `_applyDamage`.

	IT IS ITS OWN FUNCTION RATHER THAN `refillHealth` BECAUSE OF THE ORDER. `refillHealth` refuses a
	wrecked race outright, and for a good reason — handing a dead car its HP back while the wreck
	beat is running leaves a player driving a car the server has finished with. A revive is the one
	caller for which that is not true, because it is the thing that stops the beat; so it clears the
	flag FIRST and fills second, and every other caller keeps the refusal.

	Nothing else about the race is reset. The seed, the course and the set of obstacles already
	CONSUMED all still describe the road this player is standing on — the same reasoning
	`refillHealth` gives for keeping them through a steal. A revive moves you backwards a car length,
	not to the start line, and an obstacle you already paid HP for is not owed a second charge.

	`maxHealth` EXISTS TO BE OMITTED. Every other caller knows which car it just gave the player and
	says so; a revive is handing back the car they already had, whatever it has become since, so nil
	— "leave the ceiling where it is" — is the correct answer rather than a lazy one. The number the
	car carries is the last one `_setMaxHealth` wrote, which is the spawn's or the steal's, and a
	revive has no business re-litigating either. See the note at the call site in `reviveRace`.

	Returns whether there was a wrecked race to bring back, so the caller can tell "revived" from
	"there was nothing there" instead of assuming. ]]
function ObstacleService.clearWreck(self, player: Player, maxHealth: number?): boolean
	local state = self._races[player]
	if not state then
		return false
	end
	local car = state.car
	if not (car and car.Parent) then
		return false
	end

	state.wrecked = false
	--[[ The rate-limit window goes back to now as well. A wreck is very often the end of a burst of
		hits, and leaving the old window in place means the first few frames of the revived run are
		charged against a budget the crash already spent — which reads to the player as an obstacle
		that did no damage. ]]
	state.windowStart = os.clock()
	state.windowCount = 0

	self:_setMaxHealth(player, car, maxHealth)
	self:_setHealth(car, self:getMaxHealth(car))
	return true
end

--[[ Public (`PassService.PassGranted`): this player just got the 2x Car HP pass, and they are
	sitting in a car that was stamped before they had it. Re-stamp it.

	IT EXISTS BECAUSE THE PURCHASE MOMENT IS THE ONE THAT HAS TO WORK. Every other reader of the
	pass picks it up on its own next beat — the next spawn, the next steal — and for those "next" is
	soon enough. Not here: the shop is reachable from the topbar mid-run, so a player can buy this,
	look straight at their HP bar and see the number they just paid 299 Robux for not move. That is
	the whole reason `PassService` fires a signal at all rather than letting seams poll.

	THE DELTA IS ADDED TO CURRENT HEALTH, NOT LEFT BEHIND, and the alternative is worse than it
	sounds. Raising the ceiling alone turns 40/100 into 40/200 — the bar HALVES at the instant of
	purchase, which reads as the pass having damaged the car. Adding the difference makes it 140/200,
	which is what "your car now has double the health" actually means.

	IT IS STILL NOT A HEAL. Filling to the new ceiling would make this a full repair for 299 Robux
	bought from inside a wreck-in-progress, which is the revive's job and is priced as such
	(`ReviveConfig`). The player keeps exactly the damage they had taken.

	REFUSES A WRECKED RACE, for the reason `refillHealth` gives: the wreck beat is already running
	and topping up a dead car leaves somebody driving a car the server has finished with. A player
	who buys the pass on the respawn screen gets it on their next spawn, through `beginRace`, which
	is the ordinary path and needs nothing from here. ]]
function ObstacleService.applyHealthPass(self, player: Player)
	local state = self._races[player]
	if not state or state.wrecked then
		return
	end
	local car = state.car
	if not (car and car.Parent) then
		return
	end

	--[[ SCALED BY WHAT IS NEW, not by the whole factor, and skipping this is a live bug rather
		than a theoretical one. `PassGranted` fires once per SOURCE — once when a gift lands and
		once when Roblox reports a purchase — so a player who already owned the pass and is then
		GIFTED it mid-run arrives here with a ceiling that was already doubled at `beginRace`, and
		a straight `before * factor` would take an 80 HP car to 320. The shop offers exactly that
		press on purpose: `Pages/Shop._wirePill` keeps a gift pill on a card the buyer already owns,
		because the gifter cannot see what the recipient owns. Comparing against the factor the
		ceiling was written with turns the second grant into the no-op it should be. ]]
	local applied = state.healthFactor or 1
	local factor = self:_healthFactor(player)
	if factor <= applied then
		return
	end

	local before = self:getMaxHealth(car)
	local after = before * (factor / applied)
	--[[ Written straight rather than through `_setMaxHealth`, and this is the one place that is
		correct. That function multiplies what a CALLER asked for; this is scaling what is already on
		the car, and routing it through would apply the factor twice. ]]
	local holder = self:_healthHolder(car)
	holder:SetAttribute("MaxHealth", after)
	if car ~= holder then
		car:SetAttribute("MaxHealth", after)
	end

	state.healthFactor = factor

	local health = holder:GetAttribute("Health")
	if type(health) == "number" and health > 0 then
		self:_setHealth(car, math.min(health + (after - before), after))
	end

	self.log:info(string.format("%s bought 2x Car HP mid-run; their ceiling went %d -> %d.", player.Name, before, after))
end

function ObstacleService.getSeed(self, player: Player): number?
	local state = self._races[player]
	return state and state.seed
end

--[[ Public (AdminService): arm the obstacle bench for this player's next run, or clear it.

	A bench replaces the seeded ramp with one hazard laid at a fixed distance and repeated, so a
	kind can be driven into on purpose instead of waited for. `ObstacleConfig.Bench` has the design
	and `ObstacleLayout.sanitizeBench` is the only thing that decides what a spec means: whatever
	the panel sent, what is stored here is a clamped table naming a kind or a course this build
	really has, or nothing at all.

	IT TAKES EFFECT AT `beginRace` AND NOWHERE ELSE. A run already under way keeps the road it was
	dealt, because the client built that road from what it was handed at `RaceStart` and the server
	prices hits against the same thing; swapping either half mid-run is how a hit stops matching an
	obstacle. So arming this while somebody is driving is a promise about their next run, and the
	caller is the one that has to say so.

	Answers the bench it stored (or nil), so the caller can report what it actually armed rather
	than what it asked for. ]]
function ObstacleService.setBench(self, player: Player, spec: unknown): ObstacleLayout.Bench?
	local bench = ObstacleLayout.sanitizeBench(spec)
	self._bench[player] = bench
	--- The read-out, for the panel (`ObstacleConfig.Bench.Attribute`). Written here rather than by
	--- the caller because this is the only thing that changes what is armed, and a mirror written
	--- anywhere else is a mirror that can be wrong.
	player:SetAttribute(ObstacleConfig.Bench.Attribute, bench and (bench.course or bench.kind) or nil)
	return bench
end

--- Public: the bench armed for this player's next run, or nil. The one a run is actually being
--- driven on lives in `_races[player].bench` and is a copy, taken at `beginRace`.
function ObstacleService.benchFor(self, player: Player): ObstacleLayout.Bench?
	return self._bench[player]
end

--[[ Ceiling on how many tiles `clearedFor` will walk in one call.

	Purely a bound on a loop whose length comes from a measured distance — 2000 tiles is a run about
	two orders of magnitude longer than the longest anyone has driven, so it is unreachable in play
	and stops a corrupt distance from turning one settlement into a freeze. ]]
local MAX_TILES_SCANNED = 2000

--[[ Public (QuestService): how many obstacles this player got PAST without hitting, over a run that
	covered `studs`.

	=== THE ONE COUNTER IN THIS GAME THAT NOBODY REPORTS ======================================

	Nothing had ever counted a dodge, and there was no obvious place to put one: obstacles are
	client-built (the road is local — see RoadController), so the only side that can see you miss
	one is the side we do not trust, and a `Dodged` remote would be a message whose entire payload
	is "trust me". So this counts them from two things the SERVER already owns outright:

	  • the race SEED, which this service minted and never sent to anyone but the driver, and from
	    which `ObstacleLayout` re-derives the exact obstacle list for any tile, and
	  • the DISTANCE, which `RewardService` measures off the car's own position for the same reason
	    it is the one payout in the game with no trust gap.

	Obstacles behind you, minus the ones you hit, is obstacles you dodged. A client cannot inflate
	it: under-reporting hits (the one direction it CAN lie in) is already how it steals HP, and
	doing so would raise this count — which is why the quest targets are set where a full run
	clears them honestly, and why nothing here is worth cheating for.

	`reached` is where the car got to in the layout's own frame: `ObstacleLayout.forTile` places
	tile 0's obstacles well past the spawn because the car starts at the MIDDLE of tile 0, so the
	half-tile is part of the coordinate rather than a fudge.

	=== IT MUST BE CALLED WHILE THE RACE IS STILL ALIVE =======================================

	It reads `_races[player]`, which `RaceService.leaveRace` clears. Every ordinary ending settles
	first — `wreckRace` and `bankRun` both call `settleRun` well before `leaveRace` runs — so the
	`RunSettled` signal is a safe place to ask from and is where QuestService asks. The exception is
	a run that reached `leaveRace` without settling (a disconnect mid-run, a rider who died in the
	seat): there `endRace` has already run, this returns nil, and that run's dodges are not counted.
	Returning nil rather than 0 is what lets the caller tell "no dodges" from "cannot say". ]]
function ObstacleService.clearedFor(self, player: Player, studs: number): number?
	local state = self._races[player]
	if not (state and ObstacleConfig.Enabled) then
		return nil
	end
	if type(studs) ~= "number" or studs ~= studs or studs <= 0 then
		return 0
	end

	local RoadService = Shard.get("RoadService")
	local segmentLength = RoadService and RoadService:getSegmentLength(state.world)
	if not segmentLength or segmentLength <= 0 then
		return nil
	end

	local reached = segmentLength * 0.5 + studs
	local topTile = math.min(math.floor(reached / segmentLength), MAX_TILES_SCANNED)

	-- Same map the client built the course from. Without it the desert's run would be counted
	-- against the city's course list, which is a different number of obstacles per tile.
	local map = WorldConfig.mapFor(state.world)

	local passed = 0
	for tileIndex = 0, topTile do
		local base = tileIndex * segmentLength
		for _, obstacle in ObstacleLayout.forTile(state.seed, tileIndex, segmentLength, map, state.bench) do
			--[[ PACKS ARE NOT OBSTACLES AND MUST NOT BE COUNTED. The layout carries the road's
				health and nitro pickups in the same list (`PickupConfig`), and left in here they
				would be counted twice over in opposite directions: a pack you drove past would be
				a dodge you were paid for, and one you collected would be a hazard you were charged
				for missing. Neither is a thing that happened. ]]
			if base + obstacle.along <= reached and not ObstacleLayout.isPickup(obstacle.kind) then
				passed += 1
			end
		end
	end

	--[[ `consumed` is the set of obstacles that actually cost HP — written in `_onObstacleHit` only
		after the id, the layout and the lane have all checked out, so a spammed or malformed report
		never lands in here and never inflates the subtraction.

		Minus the packs, which share that set for the dedupe (a pack may only be collected once, for
		the same reason an obstacle may only be charged once) but were never in `passed`. Subtracting
		them here rather than keeping two sets is what stops the two halves of this sum disagreeing
		about what an id means. ]]
	local hits = -state.pickupsTaken
	for _ in state.consumed do
		hits += 1
	end

	return math.max(0, passed - hits)
end

-- Fixed one-second window. Only exists to bound a malformed or spamming client; a real
-- run peaks well under the cap even when plowing straight through a wall of barriers.
function ObstacleService._rateLimited(self, state): boolean
	local now = os.clock()
	if now - state.windowStart >= 1 then
		state.windowStart = now
		state.windowCount = 0
	end
	state.windowCount += 1
	return state.windowCount > ObstacleConfig.MaxHitsPerSecond
end

--[[ Rebase-proof plausibility check.

	The client shifts its whole local world back toward the origin as it drives (see
	RoadController._shiftWorld), so an obstacle's ALONG coordinate on the server is
	meaningless without replaying every rebase. Its CROSS coordinate isn't: rebases only
	ever translate along the forward axis, so `DriveCenterX + laneOffset` stays true for
	the entire race. Cheap, and it's the check that actually matters — it's what stops a
	client claiming a hit from an obstacle on the far side of the road. ]]
function ObstacleService._laneIsPlausible(self, car: Model, obstacle, world: number?): boolean
	local primary = car.PrimaryPart
	local RoadService = Shard.get("RoadService")
	if not (primary and RoadService) then
		return true -- can't check; don't punish
	end
	local cross = RoadService:getCross()
	local driveCenter = RoadService:getDriveCenter(world)
	if not (cross and driveCenter) then
		return true
	end

	local kind = ObstacleConfig.Kinds[obstacle.kind]
	local holder = self:_healthHolder(car)
	local carHalf = if holder:IsA("BasePart") then holder.Size.X * 0.5 else 5
	local tolerance = (kind and kind.HitSize.X or 4) * 0.5 + carHalf + ObstacleConfig.LaneCheckSlack
	--[[ A ROLLING KIND IS NOT WHERE THE LAYOUT PUT IT. The desert's tumbleweed sweeps across the
		road while it sits there (ObstacleConfig.Tumbleweed.Roll, drawn by the client), so its lane
		is the centre of a band rather than a position and a legitimate hit can be reported from
		anywhere in that band. Widening by the sway is what keeps this check as tight as it can
		honestly be: it stays a real bound on how far away a hit may be claimed from, it just
		bounds the right thing. Nil for every kind that stands still, which is all but one. ]]
	if kind and kind.Roll then
		tolerance += kind.Roll.Sway
	end

	local carCross = primary.Position:Dot(cross)
	return math.abs(carCross - (driveCenter + obstacle.laneOffset)) <= tolerance
end

function ObstacleService._onObstacleHit(self, player: Player, id: any)
	--[[ Either layer can have put the id there. With the course off the layout holds only packs
		(`ObstacleLayout.forTile`, 2026-09-28), so a report can only ever resolve to a pack — the
		`byId` lookup below is what guarantees it, not this line. ]]
	if not (ObstacleConfig.Enabled or PickupConfig.Enabled) then
		return
	end
	local state = self._races[player]
	if not state or state.wrecked then
		return
	end
	if type(id) ~= "number" or id ~= id or id % 1 ~= 0 or id < 0 then
		return
	end
	if state.consumed[id] then
		return -- already paid for this one
	end
	if self:_rateLimited(state) then
		self.log:warn(string.format("%s exceeded the obstacle hit rate cap; ignoring.", player.Name))
		return
	end

	local car = state.car
	if not (car and car.Parent) then
		return
	end

	local RoadService = Shard.get("RoadService")
	local segmentLength = RoadService and RoadService:getSegmentLength(state.world)
	if not segmentLength then
		return
	end

	local obstacle = ObstacleLayout.byId(state.seed, id, segmentLength, WorldConfig.mapFor(state.world), state.bench)
	if not obstacle then
		return -- no such obstacle in this race's layout
	end
	local kind = ObstacleConfig.Kinds[obstacle.kind]
	if not kind then
		return
	end
	if not self:_laneIsPlausible(car, obstacle, state.world) then
		return
	end

	state.consumed[id] = true

	--[[ A PACK, not a hazard. It arrived down this path — and had to — because every guarantee this
		function makes is exactly the guarantee a reward needs: the id is really in this race's
		layout, the car was really near that lane, it has not been claimed before, and the whole lot
		is rate-capped. The client reported one number and no amount, same as ever.

		Counted separately from `consumed` so `clearedFor` can subtract the right thing: an
		obstacle you hit is a dodge you missed, and a pack you collected is neither. ]]
	if kind.Pickup then
		state.pickupsTaken += 1
		self:_onPickup(player, state, kind.Pickup)
		return
	end

	--[[ A kind can legitimately cost nothing -- the oil slick takes your grip instead of your HP
		(ObstacleConfig.Oil). It still consumes the id, because driving through a slick is not a
		dodge and `clearedFor` counts it as such, but there is nothing to charge for it: writing a
		zero subtraction back through `_setHealth` would republish Health to every reader watching
		it for a change that did not happen. ]]
	if kind.Damage > 0 then
		self:_applyDamage(player, state, kind.Damage)
	end
end

--[[ Public: charge a racer's car HP for a hazard owned by ANOTHER service — TrafficService's
	car clips today, the theft flow later.

	The split is deliberate. The hazard's own service prices it, from its own config, because
	that's where the tuning lives; this service owns HP, so it stays the only thing that ever
	writes it. The global rate cap applies here too, so no amount of new hazards can widen the
	ceiling on how fast a client can talk HP down.

	Returns whether the damage actually landed, so a caller can hold its cooldown until it did
	(a report from someone who isn't racing shouldn't shadow a real hit a moment later). ]]
function ObstacleService.applyHazardDamage(self, player: Player, amount: number): boolean
	-- Deliberately NOT gated on ObstacleConfig.Enabled: that switch turns the obstacle course
	-- off, and traffic clips have no business disappearing with it. Each hazard's own master
	-- switch is its own service's to check.
	local state = self._races[player]
	if not state or state.wrecked then
		return false
	end
	if not (state.car and state.car.Parent) then
		return false
	end
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return false
	end
	if self:_rateLimited(state) then
		self.log:warn(string.format("%s exceeded the hit rate cap; ignoring hazard damage.", player.Name))
		return false
	end

	state.hazards += 1
	self:_applyDamage(player, state, amount)
	return true
end

-- The one place HP goes down: clamp, mirror it to every reader, and hand off to the wreck beat
-- at zero. Callers have already decided the amount from config — nothing here trusts a client.
--
-- Being the only such place is what lets ObstacleConfig.Invulnerable cover every hazard from one
-- line. It returns before the write, not before the caller, so a hit still counts as consumed and
-- still costs its rate-limit budget — the test switch must not change which reports get accepted,
-- only what they do to HP.
--[[ The lowest HP a hit is allowed to leave this player on, or 0 for "no floor".

	THE ONBOARDING'S "not invincible, but cannot die", in one number. The board card asks for both
	halves and they are genuinely different things: damage has to LAND, or the eight seconds of
	traffic teach that nothing matters, and a player who wrecks eight seconds into their first ever
	run has been shown none of the game. So the bar drops by the real amount and stops.

	IT IS A FLOOR ON THE RESULT AND NOT A SHIELD ON THE HIT. Every clip is priced exactly as it
	would be for anybody else and the HP that reaches the client is the real remainder — right up
	until it would go under the floor, at which point it sits on it. Nothing about the reaction, the
	shake, the smoke or the near-miss economy is touched.

	READ OFF A PLAYER ATTRIBUTE, live, every hit. No cached flag and nothing to unsubscribe: the
	tutorial publishes its live beat on the player (`TutorialConfig.StepAttribute`), so the floor
	appears when the staged beats start and disappears the instant they end — which is at the steal,
	so the truck beat, the first part of the run the player drives unaided, is played for real. ]]
function ObstacleService._damageFloor(self, player: Player, car: Model): number
	--[[ ...and since 2026-10-05 for the WHOLE tutorial run, truck beat included, while
		`TutorialConfig.Unlosable.Floor` is on — see that note for why a first run may not be lost.
		Off, it is the staged beats only, exactly as described above. ]]
	local step = player:GetAttribute(TutorialConfig.StepAttribute)
	local floored = TutorialConfig.isStaged(step)
		or (TutorialConfig.Unlosable.Floor and TutorialConfig.isUnlosable(step))
	if not floored then
		return 0
	end
	return self:getMaxHealth(car) * TutorialConfig.Rig.Stage.HealthFloor
end

function ObstacleService._applyDamage(self, player: Player, state, amount: number)
	if ObstacleConfig.Invulnerable then
		return
	end
	--[[ ...and the same switch for one run only, when that run is an admin bench (`setBench`). It
		sits beside the global one because it means exactly what the global one means: the hit is
		still accepted, still consumed and still costs its rate-limit budget, and only the write to
		HP is skipped. A bench exists to be driven into repeatedly, and four hits is the whole run
		on most kinds. ]]
	if state.bench and state.bench.invuln then
		return
	end
	--[[ The spawn shield (`RaceConfig.SpawnShield`), and it sits HERE — beside `Invulnerable`, above
		the write — for the reason that comment gives for that switch: this is the only place HP goes
		down, so one line covers every hazard there is and every hazard there will be. An obstacle, a
		wall scrape and a traffic clip are all already through their own service's pricing and this
		service's rate cap by the time they arrive, and that is deliberately left alone: a hit taken
		during the shield still COUNTS as consumed and still costs its rate-limit budget, so the
		shield changes what a report does to HP and not which reports are accepted.

		Returning before the write also means `_setHealth` is never called, so the HP bar does not
		flicker down and back for hits the player is not taking. ]]
	if os.clock() < state.shieldUntil then
		return
	end
	--- A lit Star (`PickupConfig.Packs.Star`): the same "accepted, consumed, not charged" as the
	--- shield above, for as long as `_spend` armed it.
	if os.clock() < (state.starUntil or 0) then
		return
	end
	local car = state.car
	local max = self:getMaxHealth(car)
	local current = self:_healthHolder(car):GetAttribute("Health")
	if type(current) ~= "number" then
		current = max
	end
	local health = math.max(0, math.min(max, current) - amount)
	--[[ ...and never below the tutorial's floor. Applied after the subtraction rather than to the
		amount, so the hit is priced normally and only its RESULT is held up — a player already
		sitting on the floor takes a hit that changes nothing rather than one that was made small. ]]
	health = math.max(health, self:_damageFloor(player, car))
	self:_setHealth(car, health)

	if health <= 0 then
		state.wrecked = true
		local RaceService = Shard.get("RaceService")
		if RaceService then
			RaceService:wreckRace(player)
		end
	end
end

--[[ HP GOING UP BY AN AMOUNT — the mirror of `_applyDamage`, and the second and last writer of
	Health in this service. `refillHealth` and `clearWreck` also raise it, but both of those set it
	to the ceiling; this is the only one that moves it by a number.

	It is a separate function rather than `_applyDamage(-amount)` because almost every guard on that
	path is wrong in this direction, and quietly so:

	  THE SPAWN SHIELD AND `Invulnerable` MUST NOT APPLY. Both exist to stop HP falling — a shielded
	  or invulnerable run that also cannot be healed is one where a pack the player collected did
	  nothing, which reads as the pack being broken. `Invulnerable` in particular is the switch for
	  measuring DRIVING, and it would be actively misleading for it to disable a reward.

	  THE TUTORIAL'S DAMAGE FLOOR MUST NOT APPLY. It is a floor on a subtraction; against an
	  addition it is a no-op at best and a cap at worst.

	  THERE IS NO WRECK BRANCH. Healing cannot reach zero, and a wrecked race is refused by the
	  caller before it gets here.

	Clamped to the ceiling, so a pack collected at full health is worth nothing rather than banking
	overheal — which is exactly the case `PickupConfig.Packs.Health.AutoUseBelow` exists to keep a
	player out of. Returns the HP actually restored, so the caller can tell a real heal from a
	wasted one. ]]
function ObstacleService._applyHeal(self, state, amount: number): number
	local car = state.car
	local max = self:getMaxHealth(car)
	local current = self:_healthHolder(car):GetAttribute("Health")
	if type(current) ~= "number" then
		current = max
	end
	local health = math.clamp(current + amount, 0, max)
	local gained = health - math.min(current, max)
	if gained <= 0 then
		-- Nothing to write. Republishing an unchanged Health would wake every reader watching it
		-- for a change that did not happen — the same reasoning `_onObstacleHit` gives for not
		-- writing a zero subtraction.
		return 0
	end
	self:_setHealth(car, health)
	return gained
end

--[[ What is in this player's pickup slot, mirrored where the HUD can read it.

	The state is the authority and the attribute is the copy — never the other way round — because
	the attribute is writable by nothing but this line and readable by everyone, which is what makes
	it a safe mirror and an unsafe record. `_usePickup` reads `state.slot`.

	Cleared with nil rather than an empty string so "no pack" is the absence of the attribute, which
	is what a client reading it before the first pickup of a run sees anyway. ]]
function ObstacleService._setSlot(self, player: Player, state, name: string?)
	state.slot = name
	player:SetAttribute(PickupConfig.SlotAttribute, name)
end

--[[ A validated pickup: the client drove through a pack that really is in this race's layout, at a
	lane it could plausibly have reached, and has not claimed before. All of that happened in
	`_onObstacleHit` — this only decides what the pack does.

	BANKED, EXCEPT WHEN YOU NEEDED IT. The owner's rule, and the HEALTH half of it: a health pack
	collected at or under `AutoUseBelow` of the car's ceiling spends itself here and never reaches the
	slot, because a repair sitting unspent while the player is on their last legs is the feature
	arguing with them. Everything else banks, replacing whatever the slot held — see `PickupConfig`
	for why replacing beats refusing.

	ONLY THE HEALTH HALF, and the `pack.Heal` guard is what says so rather than an accident of which
	packs exist. Every pack now carries an `AutoUseBelow` and it is a fraction of that pack's OWN
	resource, so reading the nitro pack's against this car's HP would be comparing a tank level to a
	health bar. The tank is a client-owned number this service cannot read at all (`PickupConfig`'s
	header), so the nitro rule is enforced in `PickupController._autoUse`, which spends it back
	through `_usePickup` like any other press. Nothing changes on this side for it.

	The threshold is read against `getMaxHealth` every time rather than cached, because MaxHealth is
	restamped on every steal: the car you are in when you collect a pack is very often not the car
	you started the run in.

	RETURNS WHETHER IT BANKED, so a caller can say which of the two happened. The road does not care
	(`_onObstacleHit` ignores it), but `grantPickup` prints it, and the answer cannot be read back off
	the slot afterwards: a pack that auto-used onto a slot ALREADY holding the same pack leaves that
	slot looking exactly like a pack that just banked. ]]
function ObstacleService._onPickup(self, player: Player, state, name: string): boolean
	local pack = PickupConfig.pack(name)
	if not pack then
		return false
	end

	if PickupConfig.InstantUse then
		-- Contact has already passed `_onObstacleHit`'s server-side layout, id, lane, duplicate and
		-- rate checks. Spend only the configured pack name from that validated layout; no client
		-- amount or target crosses this boundary.
		if state.slot then
			self:_setSlot(player, state, nil)
		end
		self:_spend(player, state, name)
		return false
	end

	--- A star is never banked: it is spent on contact whatever `InstantUse` says (`PickupConfig`).
	if pack.Star then
		self:_spend(player, state, name)
		return false
	end

	if pack.Heal and pack.AutoUseBelow > 0 then
		local max = self:getMaxHealth(state.car)
		local current = self:_healthHolder(state.car):GetAttribute("Health")
		if type(current) ~= "number" then
			current = max
		end
		if current <= max * pack.AutoUseBelow then
			-- Straight through the slot. `_spend` fires the same `PickupUsed` a keypress would, so
			-- the client plays one beat for "you got it and it went in" rather than needing a
			-- second one for the auto case.
			self:_spend(player, state, name)
			return false
		end
	end

	self:_setSlot(player, state, name)
	return true
end

--[[ Apply one pack and tell the client. The single exit for both ways a pack can be spent — the
	keypress and the auto-use above — so the two can never drift apart in what they pay or announce.

	The heal lands HERE, server side, and the nitro does not: the tank is a client-owned number
	(`NitroController._tank`) and this service has no way to write it, so `PickupUsed` carries the
	name and the client tops its own bottle up. `PickupConfig`'s header argues that this is the
	honest split rather than a hole, and the argument is that an exploiting client could already set
	its own tank every frame — where HP it can only ever ask this service to move. ]]
function ObstacleService._spend(self, player: Player, state, name: string)
	local pack = PickupConfig.pack(name)
	if not pack then
		return
	end
	--[[ NOT ONTO A WRECKED CAR, and this is a backstop rather than a formality — it is the same rule
		`refillHealth` refuses on and states at length: handing a dead car its HP back while the wreck
		beat is running leaves a player driving a car the server has finished with.

		Both callers already refuse a wrecked race a step earlier — `_usePickup` checks it directly
		and `_onPickup` is only ever reached through `_onObstacleHit`, which checks it first — so
		nothing in the live flow reaches this line. It is here because this became the SHARED exit
		for two paths, and a bench test calling `_onPickup` directly did heal a car at 0 HP through
		it. The invariant belongs to the function that writes the HP, not to each of its callers
		remembering.

		No `PickupUsed` either: the pack is simply not spent. Refusing after announcing it would
		leave the client playing a payout that never landed. ]]
	if state.wrecked then
		return
	end
	if pack.Heal then
		self:_applyHeal(state, self:getMaxHealth(state.car) * pack.Heal)
	end
	--[[ The star's immunity, and the only part of the star this side owns: HP is ours, so "nothing can
		hurt you" is a deadline `_applyDamage` reads. Pushed out rather than overwritten, so a second star
		collected mid-star extends the run instead of cutting it short. The client's own clock starts
		when `PickupUsed` lands, a one-way trip later, which is what `ServerGrace` covers. ]]
	if pack.Star then
		local star = pack.Star
		state.starUntil = math.max(state.starUntil or 0, os.clock() + star.Duration + (star.ServerGrace or 0))
	end
	self:getRemoteEvent("PickupUsed"):Fire(player, name)
end

--[[ client -> server: "spend what's in my slot."

	The client names nothing. Every refusal below is a state this can legitimately be in rather than
	an attack — a key pressed with an empty slot, a key pressed on the frame a wreck lands, a key
	pressed by somebody not racing — so none of them warn; they just do nothing, which is what an
	empty slot should do.

	The slot is cleared BEFORE the pack is applied, so a burst of presses in one frame cannot spend
	the same pack twice: the second read finds nothing there. That ordering is the whole rate limit
	this needs, which is why it doesn't take a budget out of `_rateLimited` — that cap exists to
	bound how fast HP can be talked DOWN, and spending is bounded by there being something to
	spend. ]]
function ObstacleService._usePickup(self, player: Player)
	local state = self._races[player]
	if not state or state.wrecked then
		return
	end
	if not (state.car and state.car.Parent) then
		return
	end
	local name = state.slot
	if not name then
		return
	end
	self:_setSlot(player, state, nil)
	self:_spend(player, state, name)
end

--[[ Public (AdminService): hand somebody a pack without them having to find one on the road.

	IT GOES THROUGH `_onPickup`, which is the function `_onObstacleHit` reaches once a report has been
	validated — so the OWNER'S RULE still applies here: a health pack handed to a player already under
	`PickupConfig.Packs.Health.AutoUseBelow` spends itself on contact and never reaches the slot. That
	is the whole reason this routes through there rather than writing `state.slot` itself. The panel
	exists to test this feature, and a grant that skipped the one branch worth testing would be
	testing something else.

	A GRANTED NITRO PACK GETS ITS HALF OF THAT RULE TOO, and not from here: it banks, the slot lands
	on the client, and `PickupController._autoUse` spends it back if the bottle is depleted. So the
	sentence below can say "is carrying" for a pack the player is about to be told they used, which is
	correct at the moment it is written — this side has no way to know the tank is empty, which is the
	whole reason that half lives over there. Watch the player's slot rather than the reply to see it.

	`spendNow` is the other end of the same slot: it applies the pack immediately, exactly as the
	keypress does (`_usePickup` -> `_spend`), so the payout can be watched landing on a player whose
	keyboard the admin does not have. It is deliberately NOT "press their Q" — it does not care what
	is in the slot and does not empty it, because what it is for is seeing what one named pack pays.

	Every refusal is a sentence rather than a bare `false`, because the panel prints it: "nothing
	happened" and "they are not in a race" look identical from the other side of a button. ]]
function ObstacleService.grantPickup(self, player: Player, name: unknown, spendNow: boolean?): (boolean, string)
	if type(name) ~= "string" then
		return false, string.format("was not named a real pack ('%s').", tostring(name))
	end
	local pack = PickupConfig.pack(name)
	if not pack then
		return false, string.format("was not named a real pack ('%s').", name)
	end

	local state = self._races[player]
	if not state then
		return false, "is not in a race, so there is no slot to put it in."
	end
	if state.wrecked then
		return false, "is wrecked, and nothing lands on a dead car."
	end
	if not (state.car and state.car.Parent) then
		return false, "has no car."
	end

	if spendNow then
		self:_spend(player, state, name)
		return true, string.format("was paid a %s pack on the spot.", name)
	end

	--[[ `_onPickup` owns the auto-use decision and reports which way it went, and that report is the
		only honest source: the slot afterwards cannot tell the two apart, because a pack that auto-used
		onto a slot already holding the same pack looks identical to one that banked. Reading the slot
		back reports "banked" for that case, which is exactly what a second press of one button does. ]]
	if self:_onPickup(player, state, name) then
		return true, string.format("is carrying a %s pack.", name)
	end
	if PickupConfig.InstantUse or pack.Star then
		return true, string.format("used the %s pack instantly on contact.", name)
	end
	--- Only the health rule can return false above (`_onPickup` guards on `pack.Heal`), so this
	--- sentence is safe to phrase in HP.
	return true, string.format(
		"used the %s pack on contact, being at or under %d%% health.",
		name,
		math.floor(pack.AutoUseBelow * 100 + 0.5)
	)
end

--[[ Public (AdminService): put the car's HP at a fraction of its ceiling.

	IT IS HERE FOR THE PACKS. A health pack collected at full health banks and then pays nothing, and
	the auto-use rule (`AutoUseBelow`) only fires under half — so both halves of that feature are
	unreachable from a panel that cannot move the HP bar, and reaching them by driving into barricades
	until the number looks right is not a test, it is a wait.

	NO NEW WRITER OF HEALTH. It reaches for the two public calls that already move it — `refillHealth`
	up and `applyHazardDamage` down — rather than `_setHealth`, so the spawn shield, the tutorial's
	damage floor, `ObstacleConfig.Invulnerable` and the rate cap all still get their say. THAT MEANS
	THIS CAN LEGITIMATELY DO NOTHING: an invulnerable or freshly-spawned run refuses the damage and
	the bar does not move. It is reported rather than hidden — the sentence carries the HP before and
	after, so a press that changed nothing says so in numbers instead of claiming success.

	The floor is deliberately above zero. Wrecking is a thing to test, but it is the revive product's
	test and it has its own tab; a health slider that can end the run at the bottom of its travel is a
	slider that ends runs by accident. ]]
function ObstacleService.setRaceHealth(self, player: Player, fraction: unknown): (boolean, string)
	local state = self._races[player]
	if not state then
		return false, "is not in a race."
	end
	if state.wrecked then
		return false, "is wrecked."
	end
	local car = state.car
	if not (car and car.Parent) then
		return false, "has no car."
	end

	if type(fraction) ~= "number" or fraction ~= fraction then
		return false, "was given no health to set."
	end

	local max = self:getMaxHealth(car)
	local want = math.clamp(fraction, 0.05, 1) * max
	local before = self:getHealth(player) or max

	-- Up first, then down, so one call covers both directions: asking for more than the car has fills
	-- it and asking for less takes the difference off whatever it is holding after that.
	if want > before then
		self:refillHealth(player)
	end
	local now = self:getHealth(player) or max
	if now > want + 0.5 then
		self:applyHazardDamage(player, now - want)
	end

	local after = self:getHealth(player) or max
	--[[ Every sentence this function can return starts as a continuation of the player's name, so the
		panel prints "Dylan is on 168 of 420 HP" and "Dylan is not in a race" from one format string
		rather than branching on which it got. `grantPickup` above answers in the same voice. ]]
	return true, string.format(
		"is on %d of %d HP (%d%%), from %d.%s",
		math.floor(after + 0.5),
		math.floor(max + 0.5),
		math.floor(after / max * 100 + 0.5),
		math.floor(before + 0.5),
		if math.abs(after - want) > 1
			then " The drop was refused: the spawn shield, Invulnerable or the rate cap is holding it."
			else ""
	)
end

--[[ Is the car actually out at the edge of the road?

	This is the one hit report the server can genuinely *verify* rather than sanity-check. The
	drivable corridor's cross-axis position is fixed for a whole race — rebases only ever
	translate along the road, the same reasoning `_laneIsPlausible` rests on — so the server's
	own copy of the car position is enough to confirm the claim. Slack is generous because that
	copy lags the owner by a frame or two and the client's shove is already pushing the car back
	off the rail by the time this arrives, but it's still far tighter than the ~73-stud corridor,
	so a scrape can't be claimed from the middle of the road. ]]
function ObstacleService._nearWall(self, car: Model, world: number?): boolean
	local primary = car.PrimaryPart
	local RoadService = Shard.get("RoadService")
	if not (primary and RoadService) then
		return true -- can't check; don't punish
	end
	local cross = RoadService:getCross()
	local driveCenter = RoadService:getDriveCenter(world)
	local driveWidth = RoadService:getDriveWidth(world)
	if not (cross and driveCenter and driveWidth) then
		return true
	end

	local holder = self:_healthHolder(car)
	local carHalf = if holder:IsA("BasePart") then holder.Size.X * 0.5 else 5
	local offset = math.abs(primary.Position:Dot(cross) - driveCenter)
	return offset + carHalf >= driveWidth * 0.5 - ObstacleConfig.WallCheckSlack
end

function ObstacleService._onWallHit(self, player: Player)
	local wall = ObstacleConfig.Wall
	if not (ObstacleConfig.Enabled and wall.Enabled) then
		return
	end
	local state = self._races[player]
	if not state or state.wrecked then
		return
	end
	local car = state.car
	if not (car and car.Parent) then
		return
	end

	-- Our own cooldown, independent of the client's: HP only ever moves at the configured rate
	-- no matter what cadence the reports arrive at.
	local now = os.clock()
	if now - state.wallAt < wall.Cooldown then
		return
	end
	if self:_rateLimited(state) then
		self.log:warn(string.format("%s exceeded the hit rate cap; ignoring wall scrape.", player.Name))
		return
	end
	if not self:_nearWall(car, state.world) then
		return
	end

	state.wallAt = now
	self:_applyDamage(player, state, wall.Damage)
end

-- === Prop art ===============================================================
--[[ The modeller's obstacle props, fitted once at startup and published to ReplicatedStorage for
	the client — which is the side that actually builds the road — to clone. See ObstacleConfig's
	"Prop art" block for the authoring contract; this is the pass that enforces it.

	WHY THE SERVER DOES THIS AT ALL, when no obstacle it produces will ever exist on the server.
	The art is authored in Workspace and StreamingEnabled is on, so a client mid-race has no
	guarantee the authoring folder is anywhere near it — `Workspace.CarSystem` already goes nil
	on the client exactly this way. ReplicatedStorage is the one place both sides can count on,
	and fitting here means it happens once per server rather than once per client per race.

	WHAT THE PASS ACTUALLY FIXES, in the order it matters:
	  1. SCALE. Uniform, from the prop's own width to the kind's `Art.Width`, so the road's sense
	     of scale is a config number rather than whatever the model was drawn at.
	  2. PIVOT. `_buildObstacle` places an obstacle by its footprint centre standing on the deck.
	     A delivered model pivots wherever the modeller left it (world 1's cone pivots in the
	     middle of its own mesh, 4.7 studs up), so it would sink half-way into the road.
	  3. ONE ASSEMBLY. `ObstacleController._smash` throws a hit prop, and welds are what decide
	     whether it leaves as the object you just hit or as a cloud of unrelated meshes. A kind
	     that WANTS to come apart says so with `Smash.Break`, which cuts these at the moment of
	     the hit — so the welds are the default and breaking is the deliberate exception.
	  4. INERT. Nothing an obstacle is built from may collide, and only the `Hit` volume the
	     client adds may answer a query — the same rule the primitive `Build` path follows.

	Rebuilt from scratch every startup rather than reused (which is what `TrafficService` does
	with its car shells): these are a handful of props, they are being iterated on daily, and a
	stale one is silent — it just keeps shipping last week's art. ]]

--[[ World-space AABB over every part in a model.

	NOT `Model:GetBoundingBox`, which measures along the model's PIVOT axes — and the pivot of a
	delivered prop is arbitrary, which is the very thing this pass is here to fix. Walking the
	eight corners of each part is orientation-proof, and these models are a handful of parts. ]]
local function worldBounds(model: Model): (Vector3?, Vector3?)
	local min, max
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local half = part.Size * 0.5
			for x = -1, 1, 2 do
				for y = -1, 1, 2 do
					for z = -1, 1, 2 do
						local corner = part.CFrame * Vector3.new(half.X * x, half.Y * y, half.Z * z)
						min = min and min:Min(corner) or corner
						max = max and max:Max(corner) or corner
					end
				end
			end
		end
	end
	return min, max
end

-- One delivered prop -> one publishable prop. Returns nil (having warned) for anything the
-- fitting can't be done to, so a bad model costs its own kind and not the whole world's set.
function ObstacleService._fitProp(self, source: Model, kindName: string, art): Model?
	local prop = source:Clone()
	--[[ Cleared BEFORE the pivot is set, not after: a Model with a PrimaryPart reports that
		PART's frame as its pivot and ignores `WorldPivot` entirely, so leaving one in place
		would silently throw away the footprint origin established below. ]]
	prop.PrimaryPart = nil

	--[[ Turned FIRST, before anything is measured, so that `Art.Width` always means the same
		thing: the across-the-road span of the prop AS IT WILL STAND on the road. World 1's props
		are all authored yawed 90 degrees, so measuring first would fit the barricade by its
		2.9-stud depth and blow it up to five times its length.

		Pre-multiplied rather than `pivot * CFrame.Angles(...)`, which would turn the prop about
		the pivot's OWN axes — and a delivered pivot carries whatever rotation it was left with.
		This is a world-Y turn whatever the pivot says; it also swings the prop around the world
		origin, which costs nothing because the next two lines re-place it there anyway. ]]
	if art.Yaw then
		prop:PivotTo(CFrame.fromOrientation(0, math.rad(art.Yaw), 0) * prop:GetPivot())
	end

	local min, max = worldBounds(prop)
	if not (min and max) or (max.X - min.X) < 1e-3 then
		self.log:warn(string.format("Obstacle prop '%s' has no geometry to fit; skipping it.", kindName))
		prop:Destroy()
		return nil
	end

	-- Pivot at the centre of the footprint, ON the ground. Both halves of that earn their place:
	-- `ScaleTo` scales about the pivot, so a ground pivot is what keeps a shrinking prop standing
	-- on the deck instead of sinking into it, and `_buildObstacle` then places it with a single
	-- `PivotTo` onto the deck.
	prop.WorldPivot = CFrame.new((min.X + max.X) * 0.5, min.Y, (min.Z + max.Z) * 0.5)
	-- Relative to the CURRENT size (which is what was just measured), so this composes with a
	-- model that already carries a scale from having been resized in Studio.
	prop:ScaleTo(prop:GetScale() * (art.Width / (max.X - min.X)))
	prop:PivotTo(CFrame.new())

	local root: BasePart? = nil
	local parts = {}
	for _, part in prop:GetDescendants() do
		--[[ A prop is art and nothing else. A LocalScript left inside a delivered model is inert
			sitting in ReplicatedStorage and RUNS the moment the client clones it into Workspace,
			once per obstacle — so it is dropped here rather than trusted to be harmless. ]]
		if part:IsA("LuaSourceContainer") then
			part:Destroy()
		elseif part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false -- an obstacle may never fight the tuned car physics
			part.CanQuery = false -- the client's `Hit` volume is the only thing the poll may see
			part.CanTouch = false
			table.insert(parts, part)
			if not root or part.Size.Magnitude > root.Size.Magnitude then
				root = part
			end
		end
	end
	if not root then
		prop:Destroy()
		return nil
	end
	-- Welded to the biggest part rather than in a chain, so the assembly survives any one part
	-- being edited out, and a star of constraints is also what `Smash.Break` can cut cleanly.
	for _, part in parts do
		if part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = root
		end
	end

	prop.Name = kindName
	return prop
end

--[[ The authoring folder for one world's props: by the world's map name first, by `World<n>`
	second. See ObstacleConfig's "Prop art" block for why both names resolve.

	LOOKED UP IN SERVERSTORAGE BEFORE WORKSPACE, and that order is the important half. The art
	folder is authored in Workspace and tagged `RelocateObject`, so `RelocationService` has already
	moved it to ServerStorage by the time anything's `start` runs — a Workspace-only lookup finds
	nothing at all on a live server and every kind silently falls back to primitives. Workspace is
	still tried second, for a session where the tag has been taken off and for the plugin command
	runner, which reads this file in edit mode where no relocation has happened.

	Ordering is guaranteed rather than hoped for: Shard runs every service's `init` before any
	service's `start`, and RelocationService does its sweep synchronously in `init` precisely so
	that this kind of read cannot race it. ]]
function ObstacleService._propSource(self, index: number): Instance?
	local name = ObstacleConfig.PropSourceFolderName
	local assets = ServerStorage:FindFirstChild(name) or workspace:FindFirstChild(name)
	if not assets then
		return nil
	end
	local map = WorldConfig.mapFor(index)
	return (map and assets:FindFirstChild(map)) or assets:FindFirstChild("World" .. index)
end

--[[ The art the WEATHER lays, shared by every world (`ObstacleConfig.Puddles.SourceFolderName`), from
	the same place `_propSource` looks and in the same order, for the same relocation reason. ]]
function ObstacleService._weatherPropSource(self): Instance?
	local assets = ServerStorage:FindFirstChild(ObstacleConfig.PropSourceFolderName)
		or workspace:FindFirstChild(ObstacleConfig.PropSourceFolderName)
	return assets and assets:FindFirstChild(ObstacleConfig.Puddles.SourceFolderName)
end

function ObstacleService._publishProps(self)
	local stale = ReplicatedStorage:FindFirstChild(ObstacleConfig.PropFolderName)
	if stale then
		stale:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = ObstacleConfig.PropFolderName

	--[[ THE KINDS THE WEATHER LAYS, which no map's ramp names. The rain can fall on any road, so their
		art is published into EVERY map's folder: from the map's own art folder if it has one by that
		name (a world may theme its puddle), and from the shared weather folder otherwise. ]]
	local weatherKinds = ObstacleLayout.weatherKinds()
	local weatherSource = self:_weatherPropSource()

	local published, missing = 0, 0
	for index, world in WorldConfig.Worlds do
		local source = self:_propSource(index)
		if not (source or weatherSource) then
			continue
		end
		--[[ Keyed by MAP and not by world index, because the art is themed to the road: two
			ladders pointed at one map want one set of props, not two copies of it. ]]
		local folder = root:FindFirstChild(world.Map)
		--[[ ONLY THE KINDS THIS MAP CAN ACTUALLY PLACE. Every world used to be offered every kind,
			which was right while there was one obstacle set and the only question was whether its
			art had landed yet. Now that a map has its own set (ObstacleConfig.TiersByMap), walking
			the whole table would ask the desert for a traffic cone and the city for a cactus and
			report both as art that has gone missing — so the set is derived from the map's own
			ramp, and `missing` goes back to meaning what it says. ]]
		local used = ObstacleLayout.kindsFor(world.Map)
		for kindName, kind in ObstacleConfig.Kinds do
			local art = kind.Art
			local weather = weatherKinds[kindName] == true
			-- A world with no art folder of its own still gets the weather's, and nothing else: its
			-- own kinds build from primitives exactly as they did before, uncounted.
			if not (art and ((source and used[kindName]) or weather)) then
				continue
			end
			local name = art.Model or kindName
			local model = source and source:FindFirstChild(name)
			if not model and weather and weatherSource then
				model = weatherSource:FindFirstChild(name)
			end
			if not (model and model:IsA("Model")) then
				missing += 1
				continue
			end
			local prop = self:_fitProp(model, kindName, art)
			if prop then
				if not folder then
					folder = Instance.new("Folder")
					folder.Name = world.Map
					folder.Parent = root
				end
				prop.Parent = folder
				published += 1
			end
		end
	end

	root.Parent = ReplicatedStorage -- attached last: everything above is built off-tree
	if published > 0 then
		self.log:info(string.format("Published %d obstacle prop(s).", published))
	end
	-- Not a warning: a kind with no art for a world falls back to its primitive `Build`, which is
	-- a supported state for as long as the art is still landing one world at a time.
	if missing > 0 then
		self.log:info(string.format("%d obstacle kind(s) have no art yet and will build from primitives.", missing))
	end
end

ObstacleService:withLifecycle({
	init = function(self)
		self._races = {} -- [Player] = { seed, car, bench, consumed, windowStart, windowCount, wallAt, wrecked }
		--- [Player] = the bench their NEXT run builds from, or nil for the real ramp. Outlives a
		--- race on purpose: a hazard is looked at over several runs, and re-arming it after every
		--- wreck is the panel getting in the way of the thing it is for. See `setBench`.
		self._bench = {}
		-- Seeds only need to be unpredictable per race, not cryptographic.
		self._rng = Random.new(os.time())
	end,

	start = function(self)
		Players.PlayerRemoving:Connect(function(player)
			self:endRace(player)
			--- Not in `endRace`, which every ordinary wreck goes through: the bench is armed for a
			--- PLAYER and not for a run. It goes when they do.
			self._bench[player] = nil
		end)
		self:_publishProps()

		--[[ The 2x Car HP pass, bought while already sitting in a car. `applyHealthPass` has the
			whole argument for why this one seam cannot wait for its next natural beat.

			CONNECTED HERE RATHER THAN DEPENDED ON, so a build with the entitlement layer switched
			off (`PassConfig.Enabled`) starts this service exactly as before instead of failing to
			start at all. A missing `PassService` is a game where nobody owns the pass, which is a
			state this service already handles on every other path. ]]
		local PassService = Shard.get("PassService")
		if PassService then
			PassService:getSignal("PassGranted"):Connect(function(player: Player, key: string)
				if key == ObstacleConfig.HealthPass.Key then
					self:applyHealthPass(player)
				end
			end)
		end
	end,
})

return ObstacleService
