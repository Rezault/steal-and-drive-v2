--[[
	GetawayService  (server — truck PROVIDER + bank ratification)
	-------------------------------------------------------------
	The getaway truck is client-sided for the same reason the road, the obstacles and the traffic
	are: driving is solo, so each driver owns their own copy of the world and none of it needs to
	replicate (see RoadController). This service therefore runs no truck. It does two things:

	  1. PUBLISHES the authored `Workspace.Truck` into `ReplicatedStorage.GetawayTruck` so every
	     client has something to clone, and stashes the original into ServerStorage so nothing
	     truck-shaped sits in the live world. Exactly what RoadService does with the road tile.
	  2. RATIFIES A BANK. The client says "I drove into the truck"; the server ends that player's
	     run through `RaceService.bankRun`.

	ON TRUST, and what it costs. This is the same accepted gap `StealService` documents one step
	further along: the truck exists only on the client, so there is no truck on the server to check
	a claim against — no id, no position, nothing. The server can bound the claim (the player is
	actually racing, at a bounded rate) and nothing more. Today a client that lies gets to end its
	own run early, which is self-harm in the same direction every other report in this game is
	exploitable in.

	IT STOPS BEING ACCEPTABLE NOW THAT A BANK PAYS OUT, and this is where that gap actually sits.
	The fix is the one already designed for the steal (plan §4, S20): the client asks the server for
	each traffic spawn, the server rolls the tier and returns an opaque token, and a steal redeems
	it — at which point the server knows what car you are driving and a bank is priced from ITS
	record instead of from the client's word.

	=== CLOSED — 2026-09-28 =================================================================

	That fix shipped (`EncounterConfig`, `EncounterService`), after a security review showed the gap
	was worse than this header said — "cannot bank without a stolen car" was only true of an honest
	client, since an executor fires the remote directly. With encounters on, `_onBanked` takes no car
	identity from the client at all. What follows describes the path `EncounterConfig.Enabled = false`
	still restores.

	WHAT THE PAYOUT DOES NARROW IN THE MEANTIME. The bank now carries the BODY NAME as well as the
	tier, and `GarageService` throws the pair out unless they agree with its own copy of the roster.
	So the remaining hole is "claim a car you did not steal", not "claim any payout you like": a
	client cannot name a Tier 5 price for a hatchback, and it cannot bank at all without a stolen
	car, because the starter `Sedan06` is spawned with neither attribute set.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
--- Whether a bank takes the server's record of the stolen car (`_onBanked`'s dated block).
local EncounterConfig = require(ReplicatedStorage.shared.Configs.EncounterConfig)
local GetawayConfig = require(ReplicatedStorage.shared.Configs.GetawayConfig)
local StealConfig = require(ReplicatedStorage.shared.Configs.StealConfig)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)

--[[ `WeatherService` and `WorldService` are deliberately NOT dependencies. Both are reached through
	`Shard.get` at the moment a bank lands and both are optional there: a server running without
	either still banks cars, it just cannot bound a mutation claim and therefore drops it. Declaring
	them would make this service refuse to start over a feature that is allowed to be off. ]]
local GetawayService = Shard.new("GetawayService"):withDependencies({ "RaceService", "GarageService", "RewardService" })

--[[ Floor on how often a run can be banked, seconds.

	Not an abuse number — a legitimate bank ends the run, so there is no second one to rate-limit.
	This is a duplicate-message guard: `bankRun` is already idempotent, and this keeps a client that
	fires twice in the same frame from putting two lines in the log for one getaway. ]]
local BANK_COOLDOWN = 3

GetawayService:withRemoteEvents({
	{
		--[[ client -> server: "I drove the car I'm in into the truck."

			ALL THREE parts of the car's identity ride along, and the first two being a PAIR is the
			point: the tier prices the payout, the body says which car goes on the podium, and
			`GarageService` refuses the bank unless its own roster agrees the two belong together.
			Neither is trusted on its own — see the header.

			The paint is the third, and is checked on its own terms: `PaintConfig.sanitize` bounds it
			to a colour that body is allowed to be, and anything else becomes the stock livery. It
			prices nothing, so it needs no pairing.

			THE MUTATION IS THE FOURTH AND IT IS THE ONE THAT PRICES ITSELF. A weather mutation
			multiplies the whole run payout and then multiplies that car's income for as long as it
			is parked (`WeatherConfig`), so it cannot be waved through the way a colour can. It gets
			two checks rather than one: `WeatherConfig.sanitize` for "is this a mutation at all", and
			`WeatherService.couldHaveSpawned` for "could the road this player was actually driving
			have produced it". The second is the real one, and it is only answerable because the
			weather schedule is the server's — see that service's header. ]]
		GetawayBanked = function(player: Player, tier: unknown, body: unknown, paint: unknown, mutation: unknown)
			GetawayService:_onBanked(player, tier, body, paint, mutation)
		end,
	},
})

--[[ Publish a clone of the authored truck and take the original out of the live world.

	Non-destructive: an edit session reverts on stop, so the truck stays exactly where the modeller
	left it in the place file. Reuses an already-published clone from a prior run rather than
	rebuilding one, same as RoadService does with its tile. ]]
function GetawayService._publishTruck(self): boolean
	local published = ReplicatedStorage:FindFirstChild(GetawayConfig.TemplateName)
	-- Parked in ServerStorage on 2026-10-13; Workspace still wins if dragged back.
	local source = workspace:FindFirstChild(GetawayConfig.SourceName)
		or ServerStorage:FindFirstChild(GetawayConfig.SourceName)

	if not published then
		if not source then
			self.log:warn(string.format(
				"No '%s' model in Workspace or ServerStorage to publish; races will have no exit.",
				GetawayConfig.SourceName
			))
			return false
		end
		published = source:Clone()
		published.Name = GetawayConfig.TemplateName
		--[[ The bay volume goes QUERY-BLIND on the published copy, and this is the one edit the
			publish makes rather than a tidy-up.

			`LoadZone` spans the whole interior of the bay, floor to roof. The stock CarBones
			suspension raycasts run as "Default" and are not ours to filter, so a query-visible box
			filling the space the car is being asked to drive into is something those rays would try
			to stand the car on. The client tests the bay with point-in-box arithmetic instead
			(GetawayController._inBay), which needs no query at all. ]]
		local zone = published:FindFirstChild(GetawayConfig.Parts.LoadZone)
		if zone and zone:IsA("BasePart") then
			zone.CanQuery = false
			zone.CanTouch = false
		end
		published.Parent = ReplicatedStorage
	end

	if source then
		local stash = ServerStorage:FindFirstChild(GetawayConfig.StashName)
		if not stash then
			stash = Instance.new("Folder")
			stash.Name = GetawayConfig.StashName
			stash.Parent = ServerStorage
		end
		source.Parent = stash
	end

	self.log:info(string.format(
		"Getaway truck published (%.1f studs long, %.1f-stud bay). The truck is client-streamed.",
		published:GetAttribute("Length") or 0,
		published:GetAttribute("BayLength") or 0
	))
	return true
end

--[[ A bank landed. The run is over and the player keeps the car.

	Two halves, in this order and not the other one:

	  1. `RaceService.bankRun` ends the run — the same cut-controls / hold / fade / go-home beat a
	     wreck runs, so a successful run and a failed one exit through one path.
	  2. Only if that took, `GarageService.awardCar` puts the car in the Cars Inventory (it parked
	     or sold it until 2026-09-28; `GarageConfig.Banking`), and its condition is stamped on it.

	One read comes BEFORE both halves: the car's HP, which step 1 destroys. See the note at the
	`getHealthFraction` call.

	THE ORDER IS THE GUARD. `bankRun` returns whether it actually ended a run, and it is idempotent
	against the shared "this run is already ending" flag a wreck sets — so a bank message arriving
	for a player who is not racing, or whose car blew up in the same frame, ends nothing and
	therefore pays nothing. Awarding first would hand out a car for a run that never ended. ]]
function GetawayService._onBanked(self, player: Player, tier: unknown, body: unknown, paint: unknown, mutation: unknown)
	if not GetawayConfig.Enabled then
		return
	end
	local now = os.clock()
	if now - (self._lastBank[player] or 0) < BANK_COOLDOWN then
		return
	end

	local RaceService = Shard.get("RaceService")
	if not RaceService then
		return
	end

	--[[ NO GETAWAY WITH THE POLICE ON YOU, ON THE SERVER TOO (`GetawayConfig.PoliceLock`, Aleafo punch
		list B2, 2026-10-12). The client already shuts the truck through a chase; this is the same rule
		where the bank is accepted, read off `PoliceService`'s own record rather than off this message.
		The shelter grace is kept there, so a car already on the ramp when the chase armed still gets
		in. A refused bank stamps no cooldown, for the reason given at `bankRun` below.

		`Shard.get`, not a dependency: a server without police banks exactly as it did before. ]]
	if GetawayConfig.PoliceLock.Enabled and not self._bankHeldOut[player] then
		local PoliceService = Shard.get("PoliceService")
		if PoliceService and PoliceService:isChased(player) then
			--[[ HELD, NOT DROPPED (2026-10-15, "the police showed up while I was in the getaway van,
				it wouldn't let me bank, and after they left I was stuck in that van"). The client
				only sends this once, from a car it has already shut in the truck (its shelter grace
				lets a car on the ramp finish boarding), so a plain refusal left the player riding in
				the van for good. Now the bank waits for the chase to end and then goes through. If
				the chase outlasts `PoliceLock.HoldSeconds`, it is let through anyway: the car is in
				the truck, which is what a getaway IS.

				TRUST: this lets a client that fires the remote mid-chase bank after the hold rather
				than never. That costs the chase its last `HoldSeconds`, not the car's checks (the
				whole message still runs through everything below), and a stuck van is the worse
				failure. ]]
			if not self._bankHeld[player] then
				self._bankHeld[player] = true
				self.log:info(string.format("%s banked with the police on them; holding the bank until the chase ends.", player.Name))
				task.spawn(function()
					local deadline = os.clock() + GetawayConfig.PoliceLock.HoldSeconds
					while player.Parent and RaceService:isRacing(player)
						and PoliceService:isChased(player) and os.clock() < deadline do
						task.wait(0.5)
					end
					self._bankHeld[player] = nil
					if player.Parent and RaceService:isRacing(player) then
						self._bankHeldOut[player] = true
						self:_onBanked(player, tier, body, paint, mutation)
						self._bankHeldOut[player] = nil
					end
				end)
			end
			return
		end
	end

	--[[ === THE CAR IS THE SERVER'S RECORD, NOT THE CLIENT'S WORD — 2026-09-28 ====================

		The gap this file's header describes, closed (`EncounterConfig`): a security review showed any
		client could start a run and fire this remote with the best body on the roster. With encounters
		on, ALL FOUR ARGUMENTS ARE IGNORED — the car banked is whichever one `EncounterService` recorded
		this player redeeming a token for, or none at all. A run that stole nothing banks nothing, as it
		always did for the starter car. The checks below still run over the server's own values, where
		they cost nothing and keep one path for both settings. ]]
	if EncounterConfig.Enabled then
		local Encounters = Shard.get("EncounterService")
		local car = Encounters and Encounters:stolenCar(player)
		tier = if car then car.tier else nil
		body = if car then car.body else nil
		paint = if car then car.paint else nil
		mutation = if car then car.mutation else nil
	end

	-- Same reading `StealService._readTier` does, and for the same reason: a tier that isn't a whole
	-- number we have stats for is reported as unknown rather than defaulted, so the log never claims
	-- a car the player wasn't driving.
	local index = nil
	if type(tier) == "number" and tier == tier and tier % 1 == 0 and StealConfig.TierStats[tier] then
		index = tier
	end

	--[[ THE MUTATION, RESOLVED BEFORE THE BANK AND NOT AFTER IT, and the ordering is load-bearing:
		`bankRun` is what settles the run's cash, so the multiplier has to be in hand by the time it
		is called. Everything below it — the garage, the XP — happens a step later and could not
		reach back into a payout that has already been paid.

		Two checks, doing two different jobs. `sanitize` answers "is this a mutation this build has",
		which is the soft-deploy and hand-edited-profile case. `couldHaveSpawned` answers "could the
		road this player was driving have produced it", which is the money case — see this file's
		header and `WeatherService`. A claim that fails either is dropped to nil and the bank goes
		through as an ordinary car, because refusing the whole bank would punish the player for a
		client bug far more often than it would catch anybody.

		`getRunStart` bounds the window it is checked against. A nil (no RewardService, or a run that
		was never measured) is read leniently by `couldHaveSpawned` — its own note says why. ]]
	local claimed = WeatherConfig.sanitize(mutation)
	if claimed then
		local WeatherService = Shard.get("WeatherService")
		local WorldService = Shard.get("WorldService")
		local RewardServiceForRun = Shard.get("RewardService")
		local world = if WorldService then WorldService:worldOf(player) else nil
		local since = if RewardServiceForRun then RewardServiceForRun:getRunStart(player) else nil
		if WeatherService and not WeatherService:couldHaveSpawned(world, claimed, since) then
			self.log:warn(string.format(
				"%s banked a %s car that world %s's weather never produced — mutation dropped.",
				player.Name,
				tostring(claimed),
				tostring(world)
			))
			claimed = nil
		end
	end

	--[[ THE CONDITION THE CAR ARRIVED IN, READ BEFORE THE BANK AND NOT AFTER IT — the same ordering
		constraint as the mutation above, for a different reason: `bankRun` ends the race, and ending
		the race drops the state `getHealthFraction` reads (see that function). Read after, this is
		always nil and every car banks in perfect condition.

		SERVER-MEASURED, NOT CLAIMED. HP only ever moves inside `ObstacleService`, so unlike the tier
		and the body there is nothing here a client told us. A cheating client can still avoid being
		hit — the obstacle reports are the accepted gap that service documents — but it cannot bank a
		wreck as mint by saying so. nil (no ObstacleService, no live car) stores nothing, which
		`MarketValueConfig` reads as full condition: the generous reading, and the one that matches a
		car handed over rather than driven home. ]]
	local ObstacleService = Shard.get("ObstacleService")
	local condition = if ObstacleService then ObstacleService:getHealthFraction(player) else nil

	-- Only stamp the cooldown when the run actually ends, so a report from someone who isn't racing
	-- can't shadow a real bank a moment later. Same pattern as TrafficService's clip.
	if not RaceService:bankRun(player, index, claimed) then
		return
	end
	self._lastBank[player] = now

	--[[ Hand the car to the garage. It does its own reading of the pair rather than taking this
		service's `index`, because the two checks are asking different questions: `index` is "is this
		a tier the run has stats for", and the garage's is "do this body and this tier belong
		together in the roster". Passing the raw values keeps the garage's answer its own. ]]
	local GarageService = Shard.get("GarageService")
	if not GarageService then
		self.log:warn(string.format("%s banked a car with no GarageService — nothing awarded.", player.Name))
		return
	end

	--[[ THE SIXTH ARGUMENT IS WHO IS ASKING, and it is the whole of this service's part in the car
		going into the player's HANDS rather than onto a podium. `CarryConfig.Sources` is what decides
		what "Bank" means; this file only says which of the four ways to get a car this one is, so the
		day the pull or a bought car also carries, nothing here changes. ]]
	-- Condition must reach awardCar before its capacity check, so an overflow sale uses the same
	-- market price as a kept car. Mint condition stays implicit, avoiding an unnecessary record.
	local outcome, amount = GarageService:awardCar(player, tier, body, paint, claimed, "Bank", if condition and condition < 1 then condition else nil)

	--[[ XP for the car, and THIS is the earliest point it can be awarded honestly.

		`RaceService.bankRun` has already settled the run's distance cash, because that half needs to
		know nothing but that the run ended. XP needs to know WHICH BODY, and the only name worth
		trusting is one the garage has just matched against its own roster — which is exactly what a
		non-"rejected" outcome means. Awarding it off the raw wire value instead would let a client
		level a car it never drove.

		`RewardService` supplies the amount from the distance it measured itself, so the two payouts
		can never disagree about the same run. ]]
	if outcome ~= "rejected" then
		local RewardService = Shard.get("RewardService")
		if RewardService then
			RewardService:awardCarXp(player, body)
		end
	end

	self.log:info(string.format(
		"%s got away with a %s%s — %s%s.",
		player.Name,
		if claimed then WeatherConfig.nameOf(claimed) .. " " else "",
		if index then string.format("Tier %d car", index) else "car of unknown tier",
		outcome,
		if amount > 0 then string.format(" for %d", amount) else ""
	))
end

GetawayService:withLifecycle({
	init = function(self)
		self._lastBank = {} -- [Player] = os.clock() of the last bank we ratified
		--- A bank refused for a chase and waiting for it to end (`_onBanked`), and the one re-run of it
		--- after, which skips the police check it already waited out.
		self._bankHeld = {} :: { [Player]: boolean }
		self._bankHeldOut = {} :: { [Player]: boolean }
	end,

	start = function(self)
		if not GetawayConfig.Enabled then
			return
		end
		self:_publishTruck()

		Players.PlayerRemoving:Connect(function(player)
			self._lastBank[player] = nil
			self._bankHeld[player] = nil
			self._bankHeldOut[player] = nil
		end)
	end,
})

return GetawayService
