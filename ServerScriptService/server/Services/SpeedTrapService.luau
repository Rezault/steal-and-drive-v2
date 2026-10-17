--[[
	SpeedTrapService  (server — prices a speed trap, and keeps the best)
	--------------------------------------------------------------------
	The speed traps pay (2026-09-28). `SpeedTrapConfig`'s dated block is the design; this is the half
	only the server can do. The client builds the gantry and says "I crossed one" — nothing else. The
	server then:

	  1. CHECKS THE RUN HAS EARNED A TRAP: far enough since the last paid one, by `RewardService`'s own
	     measured distance (`_spacingOk`). That is what caps a run at the trap density honest play
	     sees, whatever the client reports.
	  2. MEASURES THE SPEED ITSELF off the race car (`RewardService.getCar`), and works out that car's
	     top speed from the same numbers the client's rating uses (`_topSpeed`), then rates it.
	  3. PAYS seconds of the car's tier rate (`SpeedTrapConfig.Ratings[].Seconds`), and the same again
	     for a new best in this world, which it saves.
	  4. ANSWERS with the rating, the mph, the cash and whether it was a best, so the toast shows the
	     server's word and not the client's guess.

	=== WHAT IT TRUSTS ========================================================================

	That a trap was crossed at all — the gantries are the client's, placed by its own dice, so there
	is nothing to check a crossing against. The speed is the car's physics as the owning client
	simulated it and replicated it: a cheater can report any speed, which is why it is capped
	(`Pay.MaxFraction`) and why the most it can ever buy is GOLD, once per ~2,000 studs of distance the
	server itself measured. The body is the server's (`EncounterService.stolenCar`, else the run's
	starting car from `StartCarService`), so the price cannot be inflated by claiming a better car.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local CarConfig = require(ReplicatedStorage.shared.Configs.CarConfig)
local DriveConfig = require(ReplicatedStorage.shared.Configs.DriveConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local RewardConfig = require(ReplicatedStorage.shared.Configs.RewardConfig)
local SpeedTrapConfig = require(ReplicatedStorage.shared.Configs.SpeedTrapConfig)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local WindConfig = require(ReplicatedStorage.shared.Configs.WindConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local Data = require(script.Parent.Parent.Data)

--[[ `RaceService` for "is this player racing" and the end-of-run signal; `GarageService` for cash,
	levels and the moment a profile is ready. The rest (`RewardService`, `EncounterService`,
	`StartCarService`, `WorldService`) are reached through `Shard.get` and a missing one refuses the
	payout rather than failing the service. ]]
local SpeedTrapService = Shard.new("SpeedTrapService"):withDependencies({ "RaceService", "GarageService" })

--- (player: Player, cash: number, rating: string, newBest: boolean) : a crossing that PAID, `cash` as
--- banked (the 2x Cash pass included). For `AnalyticsService` (2026-10-15): the economy view and the
--- run's own totals.
SpeedTrapService:withSignals({ "TrapPaid" })

SpeedTrapService:withRemoteEvents({
	--[[ server -> client (ratingName?, mph, cash, newBest): what the trap you just crossed was worth.
		`ratingName` nil is too slow; `cash` 0 is a crossing that was not paid (too slow, or too soon
		after the last paid one). ]]
	"SpeedTrapResult",
	{
		--- client -> server (): "I went under a trap." Nothing else is believed — see the header.
		SpeedTrapCrossed = function(player: Player)
			SpeedTrapService:_onCrossed(player)
		end,
	},
})

-- === The profile ============================================================

function SpeedTrapService._profile(self, player: Player)
	local profile = self._profiles[player]
	return if profile and profile:IsActive() then profile else nil
end

--- This player's saved bests, as a fresh table: world index string -> mph.
function SpeedTrapService._bests(self, player: Player): { [string]: number }
	local profile = self:_profile(player)
	local stored = profile and profile:Get(SpeedTrapConfig.Pay.ProfileKey)
	return if type(stored) == "table" then table.clone(stored) else {}
end

--- Mirror the bests onto the Player, "1=142,2=160", sorted so the string does not churn.
function SpeedTrapService._publish(self, player: Player)
	if player.Parent ~= Players then
		return
	end
	local parts = {}
	for world, mph in self:_bests(player) do
		table.insert(parts, string.format("%s=%d", world, mph))
	end
	table.sort(parts)
	player:SetAttribute(SpeedTrapConfig.Pay.Attribute, table.concat(parts, ","))
end

-- === Pricing ================================================================

--[[ The car the player is driving right now, as a body name: the one they stole on this run
	(`EncounterService`), else the run's starting car — the same answer `RaceService` spawned them in. ]]
function SpeedTrapService._bodyOf(self, player: Player, world: number): string?
	local Encounters = Shard.get("EncounterService")
	local stolen = Encounters and Encounters:stolenCar(player)
	if stolen then
		return stolen.body
	end
	local StartCar = Shard.get("StartCarService")
	if StartCar then
		return (StartCar:carFor(player, world))
	end
	return nil
end

--[[ The car's boosted top speed in studs/s — the client's `DriveController.getTopSpeed` x
	`WindConfig.StudsPerMaxSpeed`, from the same inputs: the body's `MaxSpeed`, its level's scale, and
	the free boost. Computed rather than asked for, because asking the client is the gap the header of
	`SpeedTrapConfig` said must not be how a trap is priced. ]]
function SpeedTrapService._topSpeed(self, player: Player, body: string): number
	local Garage = Shard.get("GarageService")
	local level = if Garage then Garage:getCarLevel(player, body) else 1
	local boost = if DriveConfig.AllowBoost then DriveConfig.BoostSpeedScale else 1
	local parts = nil
	local Encounters = Shard.get("EncounterService")
	local StartCar = Shard.get("StartCarService")
	if Garage and StartCar and not (Encounters and Encounters:stolenCar(player)) then
		local key = StartCar:selectionOf(player)
		local valid = StartCar:canDrive(player, key)
		if valid and GarageConfig.parseCarKey(key) == body and Garage:owns(player, key) then
			parts = Garage:getCarData(player, key).Parts
		end
	end
	return CarConfig.statsFor(body, level, parts).MaxSpeed * boost * WindConfig.StudsPerMaxSpeed
end

--- Has this run driven far enough since its last paid trap (or its start) to be owed another?
function SpeedTrapService._spacingOk(self, player: Player, studs: number): boolean
	local last = self._lastPaid[player]
	local slack = SpeedTrapConfig.Pay.SpacingSlack
	if last == nil then
		return studs >= SpeedTrapConfig.FirstAt * slack
	end
	return studs - last >= SpeedTrapConfig.SpacingMin * slack
end

--[[ A crossing. Every exit answers the client (0 cash) except the ones that are not a trap at all —
	not racing, feature off — so the toast is never left waiting on a word that is not coming. ]]
function SpeedTrapService._onCrossed(self, player: Player)
	local pay = SpeedTrapConfig.Pay
	if not (SpeedTrapConfig.Enabled and pay.Enabled) then
		return
	end
	local Race = Shard.get("RaceService")
	local Reward = Shard.get("RewardService")
	local Garage = Shard.get("GarageService")
	if not (Race and Race:isRacing(player) and Reward and Garage) then
		return
	end
	if TutorialConfig.isTutorialRun(player:GetAttribute(TutorialConfig.StepAttribute)) then
		return
	end

	local studs = Reward:getDistance(player)
	local car = Reward:getCar(player)
	local primary = car and car.PrimaryPart
	if not (studs and primary) then
		return
	end
	local answer = self:getRemoteEvent("SpeedTrapResult")
	if not self:_spacingOk(player, studs) then
		self.log:info(string.format("%s reported a speed trap %d studs into the run, too soon after the last; unpaid.", player.Name, math.floor(studs)))
		answer:Fire(player, nil, 0, 0, false)
		return
	end
	self._lastPaid[player] = studs

	local World = Shard.get("WorldService")
	local world = WorldConfig.resolve(if World then World:worldOf(player) else nil)
	local body = self:_bodyOf(player, world)
	if not body then
		return
	end
	local top = self:_topSpeed(player, body)
	--- Horizontal only: a car cresting a ramp is not going faster down the road for it.
	local velocity = primary.AssemblyLinearVelocity
	local speed = math.min(Vector3.new(velocity.X, 0, velocity.Z).Magnitude, top * pay.MaxFraction)
	local rating = SpeedTrapConfig.ratingFor(speed, top)
	local mph = SpeedTrapConfig.mph(speed)

	local cash = 0
	local newBest = false
	if rating then
		local tier = GarageConfig.TierOfBody[body]
		cash = math.floor(GarageConfig.rateOf(tier, nil) * rating.Seconds + 0.5)

		local bests = self:_bests(player)
		local key = tostring(world)
		if mph > (bests[key] or 0) then
			newBest = true
			cash += math.floor(cash * pay.NewBest + 0.5)
			bests[key] = mph
			local profile = self:_profile(player)
			if profile then
				profile:Set(pay.ProfileKey, bests)
				self:_publish(player)
			end
		end
		if cash > 0 then
			local paid = cash * Garage:incomeMultiplier(player) -- the 2x Cash pass
			Garage:addCash(player, paid)
			self:getSignal("TrapPaid"):Fire(player, paid, rating.Name, newBest)
		end
	end

	answer:Fire(player, if rating then rating.Name else nil, mph, cash, newBest)
	self.log:info(string.format(
		"%s crossed a speed trap at %d mph in a %s: %s, %s%s.",
		player.Name,
		mph,
		body,
		if rating then rating.Name else "too slow",
		GarageConfig.formatCash(cash),
		if newBest then ", NEW BEST" else ""
	))
end

-- === Lifecycle ==============================================================

SpeedTrapService:withLifecycle({
	init = function(self)
		self._profiles = {} :: { [Player]: any }
		--- [Player] = run distance (studs) at the last PAID trap of the current run; nil before one.
		self._lastPaid = {} :: { [Player]: number }
	end,

	start = function(self)
		local Garage = Shard.get("GarageService")
		--- The profile handle, off the moment `GarageService` says it is warm — `ReviveService`'s
		--- pattern, and why: a second, independent idea of when a player is ready is a race.
		Garage:getSignal("ProfileReady"):Connect(function(player: Player)
			task.spawn(function()
				local ok, profile = pcall(function()
					return Data:GetProfileAsync(player)
				end)
				if ok and profile and player.Parent == Players then
					self._profiles[player] = profile
					self:_publish(player)
				end
			end)
		end)
		local Race = Shard.get("RaceService")
		Race:getSignal("RaceLeft"):Connect(function(player: Player)
			self._lastPaid[player] = nil
		end)
		Players.PlayerRemoving:Connect(function(player: Player)
			self._profiles[player] = nil
			self._lastPaid[player] = nil
		end)
	end,
})

return SpeedTrapService
