--[[
	QuestService  (server)
	----------------------
	The daily quest board's server half: what you have done today, and the one button that pays for
	it.

	=== 1. IT COUNTS NOTHING ITSELF ============================================================

	Every metric on the board is a signal another service already fires, because every one of them
	was already a thing that service had to know for its own reasons. This file is a subscriber and
	a ledger; it does not watch a car, poll a position, or take a client's word for anything:

	    Steal      StealService.CarStolen            +1     (fired only after the refill landed)
	    Bank       RewardService.RunSettled(banked)  +1
	    Race       RewardService.RunSettled          +1
	    Distance   RewardService.RunSettled          +studs (measured off the car by the server)
	    Dodge      RewardService.RunSettled          +ObstacleService.clearedFor
	    Collect    GarageService.CashCollected       +amount
	    Customer   CustomerService.CustomerPaid      +1
	    Tips       CustomerService.CustomerPaid      +amount   (replaces Collect without passive income)

	THERE IS NO QUEST REMOTE A CLIENT CAN COUNT WITH. The only two things a client may send are "my
	screen is up" and "I press claim on quest X", and the second one is re-checked here against a
	number the client never touched. That constraint is also what decides what may be a quest at
	all — see `QuestConfig`'s header note 2, and `ObstacleService.clearedFor` for the one metric
	that had to be derived rather than found.

	=== 2. THE BOARD IS DERIVED, THE PROGRESS IS STORED ========================================

	Which three quests today holds is `QuestConfig.dailySet(day)` — a deterministic draw from the UTC
	day number, identical for every player and recomputed on both sides of the wire. So the profile
	stores no selection, only `{ Day, Progress, Claimed }`, and the two halves cannot disagree about
	what today's board is because neither of them is remembering it.

	=== 3. ROLLOVER IS LAZY, NOT SCHEDULED =====================================================

	`_roll` runs before every read and every write, and does nothing at all unless the stored `Day`
	is not today — at which point progress and claims are wiped in one write. There is no midnight
	sweep and there is deliberately no timer, because a scheduled rollover has to answer "what about
	the servers that were down at midnight, and the players who were offline for a week?" and a lazy
	one never has to ask. A player who has not played since Tuesday rolls over once, on join.

	The one visible consequence: a player sitting on the page as the clock strikes midnight sees the
	page's own countdown hit zero and re-request, which rolls them over then. See the page's
	`_updateTimer`.

	=== 4. WHY THE CLIENT ASKS RATHER THAN THE SERVER PUSHING FIRST ============================

	Same problem `OfflineService` documents, same answer: the profile lands on the join path, which
	is well before the client's controllers have started, so a state push fired the moment it is
	known is a push nobody hears. The client pings (`QuestReady`) when its controller starts, and
	that ping doubles as "send me the board again" whenever the page is opened. Everything after
	that is pushed as it changes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local QuestConfig = require(ReplicatedStorage.shared.Configs.QuestConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local BalanceConfig = require(ReplicatedStorage.shared.Configs.BalanceConfig)
local CustomerConfig = require(ReplicatedStorage.shared.Configs.CustomerConfig)

local Data = require(script.Parent.Parent.Data)

--[[ One row as the page draws it. Every field is read by the page and there is no field for the
	pill's state — that is derived from `Progress`, `Target` and `Claimed`, which is the same
	"derived, not stored" rule the rest of this project runs on (see the page's `statusOf`). ]]
export type QuestRow = {
	Id: string,
	Name: string,
	Progress: number,
	Target: number,
	Unit: string,
	Claimed: boolean,
	Reward: { Kind: string, Amount: number },
}

export type Board = {
	quests: { QuestRow },
	resetAt: number, -- os.time() this board turns over
	period: number, -- how long a board lasts, for the drain bar's denominator
}

local QuestService = Shard.new("QuestService"):withDependencies({ "GarageService", "RewardService" })

QuestService:withSignals({
	--[[ (player: Player, id: string) — a quest just reached its target. Fired once, on the bump that
		crossed the line, NOT on every bump afterwards (progress is clamped at the target, so there
		are none). Nothing listens yet; it is here so that a toast, a sound or a badge does not have
		to diff two payloads to work out what changed. ]]
	"QuestCompleted",

	-- (player: Player, id: string, reward: number) — a quest was claimed and the cash has landed.
	"QuestClaimed",
})

QuestService:withRemoteEvents({
	-- server -> client (board): the whole board, as the page draws it. Sent on the client's ping and
	-- on every change after that.
	"QuestState",
	{
		--[[ client -> server: my screen exists — send me the board. Fired from the controller's
			`start` and again whenever the page is opened, so it is a REFRESH as well as a handshake;
			`_onReady` is safe to call any number of times. ]]
		QuestReady = function(player: Player)
			QuestService:_onReady(player)
		end,
		-- client -> server (id): they pressed the green pill on quest `id`.
		QuestClaim = function(player: Player, id: unknown)
			QuestService:_onClaim(player, id)
		end,
	},
})

-- === The profile ============================================================

--[[ NON-YIELDING, like `GarageService._profile` and `OfflineService._profile`, and for the same
	reason: this is reached from remote handlers and from other services' signals, none of which may
	stall for the seconds `Data:GetProfileAsync` can take. The handle is cached off the join path by
	`_watch`; until it lands every read here answers "not yet", which every caller handles. ]]
function QuestService._profile(self, player: Player)
	local profile = self._profiles[player]
	if profile and profile:IsActive() then
		return profile
	end
	return nil
end

--[[ The player's stored board — `{ Day, Progress, Claimed }` — or nil if there is no profile yet.

	ARRAY PATH, NEVER THE STRING FORM. `PlayerProfile:Get` treats a string as a RECURSIVE KEY SEARCH
	that returns whichever matching key it reaches first, and `Progress` and `Claimed` are exactly
	the sort of generic names another feature will one day add somewhere else in this template. The
	array walk is exact. ]]
function QuestService._board(self, player: Player): { [string]: any }?
	local profile = self:_profile(player)
	if not profile then
		return nil
	end
	local board = profile:Get({ QuestConfig.ProfileKey })
	return if type(board) == "table" then board else nil
end

--- One of the two inner maps, always a table. A profile mid-reconcile, or one written by a build
--- that stored something else here, reads as an empty board rather than erroring.
local function mapOf(board: { [string]: any }?, key: string): { [string]: any }
	local value = board and board[key]
	return if type(value) == "table" then value else {}
end

--[[ Wipe the board if the day has turned over. Returns whether it did.

	CALLED BEFORE EVERY READ AND EVERY WRITE, which is what makes rollover lazy rather than
	scheduled — see header note 3. Cheap: one integer compare in the overwhelming majority of calls.

	Written as ONE `Set` of the whole table rather than three, so a board can never exist in the
	half-rolled state where the day says today and the progress is yesterday's. ]]
function QuestService._roll(self, player: Player): boolean
	local profile = self:_profile(player)
	local board = self:_board(player)
	if not (profile and board) then
		return false
	end

	local today = QuestConfig.dayIndex()
	if tonumber(board.Day) == today then
		return false
	end

	profile:Set({ QuestConfig.ProfileKey }, { Day = today, World = WorldConfig.resolve(profile:Get(WorldConfig.ProfileKey)), Progress = {}, Claimed = {}, DistinctMetrics = true })
	return true
end

-- === Today's three ==========================================================

--[[ The catalogue entries today's board is made of, cached for the day.

	Cached because `dailySet` sorts and draws, and this is called on every bump — which for a
	`Collect` sweep is once per bay. Keyed on the day so the cache expires by itself at midnight
	with no timer to get wrong, which is the same trick the rollover uses.

	NOTE THE FIELD NAME. It is `_specsCache` and not `_specs`, because on a Shard service a parked
	value and a method share one namespace — `self._specs = <table>` would overwrite this very
	method and every call site would then be trying to call a table. That has already cost this
	project a bug once; see the note on `ReviveController._pressDecline`. ]]
function QuestService._specs(self)
	local today = QuestConfig.dayIndex()
	if self._specsDay ~= today then
		self._specsDay = today
		self._specsCache = QuestConfig.dailySet(today)
	end
	return self._specsCache
end

--- One of today's quests by id, or nil for an id that is not on today's board. This is what makes a
--- forged claim for yesterday's quest — or for a catalogue entry that was never drawn — a no-op.
function QuestService._specOf(self, id: unknown, player: Player)
	if type(id) ~= "string" then
		return nil
	end
	for _, spec in self:_specs(player) do
		if spec.Id == id then
			return spec
		end
	end
	return nil
end

-- === What the page draws ====================================================

--[[ The whole board for one player, in the page's shape.

	Progress is CLAMPED ON READ as well as on write. The write clamp is the real one; this one
	covers a target that has been tuned DOWN since the number was stored, which would otherwise
	draw a bar past the end of its track and a caption reading 40000/15000. ]]
function QuestService._payload(self, player: Player): Board
	self:_roll(player)

	local board = self:_board(player)
	local progress = mapOf(board, "Progress")
	local claimed = mapOf(board, "Claimed")

	local quests: { QuestRow } = {}
	for _, spec in self:_specs(player) do
		table.insert(quests, {
			Id = spec.Id,
			Name = QuestConfig.describe(spec),
			Progress = math.min(tonumber(progress[spec.Id]) or 0, spec.Target),
			Target = spec.Target,
			Unit = spec.Unit or "count",
			Claimed = claimed[spec.Id] == true,
			Reward = { Kind = "Cash", Amount = spec.Reward },
		})
	end

	return {
		quests = quests,
		--[[ Computed rather than stored, and computable identically on the client — `os.time()` is
			UTC epoch seconds on both sides. The page draws its own countdown from this and does not
			need another push to keep it moving. ]]
		resetAt = QuestConfig.resetAt(),
		period = QuestConfig.ResetPeriod,
	}
end

--[[ Send the board to one player, if they have said they can hear it.

	THE DIRTY FLAG IS CLEARED FIRST, before the two reasons this can return without sending. A
	client that never pinged would otherwise keep its flag forever and be retried every flush for
	the length of the session — the send is what is conditional, not the acknowledgement that we
	tried. Their board is not lost by this: it is on the profile, and the ping they eventually send
	pushes it. ]]
function QuestService._push(self, player: Player)
	self._dirty[player] = nil
	if not self._ready[player] or not self:_profile(player) then
		return
	end
	self:getRemoteEvent("QuestState"):Fire(player, self:_payload(player))
end

-- === Counting ===============================================================

--[[ Public: `amount` more of `metric` happened to `player`.

	THE ONLY WAY PROGRESS EVER MOVES, and every caller is a signal handler in `start` — nothing
	reaches this from a remote. Silently ignores an unknown metric, a non-positive amount and a
	player with no profile, because all three are ordinary: a service can fire its signal for a
	player whose profile has gone, and a run of zero studs is a real run.

	CLONE-AND-SET rather than mutating what `_board` handed back, the same shape `GarageService`
	uses for every map on the profile and for the same reason: that table is the replica's own, and
	writing into it directly changes the server's copy without telling the replica the path moved.

	A CLAIMED QUEST STOPS COUNTING. Not for tidiness — a quest that kept accruing past its claim
	would come back as claimable the moment a target was tuned upward. ]]
function QuestService.bump(self, player: Player, metric: string, amount: number)
	if not QuestConfig.Enabled then
		return
	end
	local delta = tonumber(amount)
	if not (delta and delta == delta and delta > 0) then
		return
	end
	if not QuestConfig.isMetric(metric) then
		self.log:warn(string.format("Ignoring a bump for unknown metric %q.", tostring(metric)))
		return
	end

	local profile = self:_profile(player)
	if not profile then
		return
	end
	self:_roll(player)

	local board = self:_board(player)
	if not board then
		return
	end

	local claimed = mapOf(board, "Claimed")
	local progress = table.clone(mapOf(board, "Progress"))
	local completed: { string } = {}
	local changed = false

	for _, spec in self:_specs(player) do
		if spec.Metric ~= metric or claimed[spec.Id] then
			continue
		end
		local was = math.min(tonumber(progress[spec.Id]) or 0, spec.Target)
		if was >= spec.Target then
			continue
		end
		local now = math.min(was + delta, spec.Target)
		if now ~= was then
			progress[spec.Id] = now
			changed = true
			if now >= spec.Target then
				table.insert(completed, spec.Id)
			end
		end
	end

	if not changed then
		return
	end

	profile:Set({ QuestConfig.ProfileKey, "Progress" }, progress)
	self._dirty[player] = true

	for _, id in completed do
		self:getSignal("QuestCompleted"):Fire(player, id)
		self.log:info(string.format("%s finished quest %s.", player.Name, id))
	end
end

--[[ Everything one settled run is worth to the board, in one place.

	FOUR METRICS OFF ONE SIGNAL, because they are four readings of the same event and taking them
	anywhere else would mean four subscriptions racing each other to the same profile write.

	`Dodge` is asked for HERE and nowhere else, and the timing is the whole reason: `clearedFor`
	reads the live race state, which `RaceService.leaveRace` clears — and `RunSettled` is fired by
	`settleRun`, which every ordinary ending reaches well before `leaveRace`. A run that got to
	`leaveRace` unsettled (a disconnect mid-run) answers nil and simply contributes no dodges, which
	is the honest reading rather than a zero pretending to be a measurement. ]]
function QuestService._onRunSettled(self, player: Player, studs: number, banked: boolean)
	if studs >= QuestConfig.MinRunStuds then
		self:bump(player, "Race", 1)
	end
	self:bump(player, "Distance", studs)
	if banked then
		self:bump(player, "Bank", 1)
	end

	local ObstacleService = Shard.get("ObstacleService")
	local dodged = ObstacleService and ObstacleService:clearedFor(player, studs)
	if dodged then
		self:bump(player, "Dodge", dodged)
	end
end

-- === The client's end =======================================================

--[[ "My screen exists." Also "send it again", which is what the page's own open calls it for — so
	unlike `OfflineService._onReady` this is NOT one-shot. It is a read and a send; there is nothing
	in it worth rate-limiting beyond the size of the payload, which is three rows. ]]
function QuestService._onReady(self, player: Player)
	if not QuestConfig.Enabled then
		return
	end
	self._ready[player] = true
	self:_push(player)
end

--[[ They pressed the green pill.

	WHAT THE CLIENT SENDS IS AN ID AND NOTHING ELSE — not a reward, not a progress figure. The
	target, the reward and how far along they are all come from state the client never touched, so
	the whole attack surface is "which of three rows did you press", and the worst a forged call can
	do is claim something the player could have claimed by opening the page. Same bargain
	`UpgradeService._onRequest` makes.

	THE CLAIM IS WRITTEN BEFORE THE CASH IS PAID, AND ROLLED BACK IF THE PAYMENT DOES NOT LAND —
	the same order and the same refund `UpgradeService` uses for a purchase, for the mirror-image
	reason. Paying first would mean a profile that goes away between the two leaves a player paid
	and still holding a claimable quest; this way the failure mode is a claim that visibly did not
	happen, which the next press fixes.

	The payment is CONFIRMED AGAINST THE BALANCE rather than assumed, which is the check
	`RewardService.settleRun` documents: `addCash` is a no-op for a player whose profile has not
	loaded, and a screen that says CLAIMED for money nobody has is the one failure a reward must
	not have. ]]
function QuestService._onClaim(self, player: Player, id: unknown)
	if not QuestConfig.Enabled then
		return
	end

	local profile = self:_profile(player)
	if not profile then
		return
	end
	self:_roll(player)

	local spec = self:_specOf(id, player)
	if not spec then
		return -- not on today's board
	end

	local board = self:_board(player)
	if not board then
		return
	end

	local claimed = mapOf(board, "Claimed")
	if claimed[spec.Id] then
		return -- already paid for
	end
	if (tonumber(mapOf(board, "Progress")[spec.Id]) or 0) < spec.Target then
		return -- not finished
	end

	local nextClaimed = table.clone(claimed)
	nextClaimed[spec.Id] = true
	profile:Set({ QuestConfig.ProfileKey, "Claimed" }, nextClaimed)

	local Garage = Shard.get("GarageService")
	local before = Garage and Garage:getCash(player)
	if not (before and Garage:addCash(player, spec.Reward) > before) then
		profile:Set({ QuestConfig.ProfileKey, "Claimed" }, claimed)
		self.log:warn(string.format("%s's %s reward could not be paid; the claim is back on the board.", player.Name, spec.Id))
		self:_push(player)
		return
	end

	self:_push(player)
	self:getSignal("QuestClaimed"):Fire(player, spec.Id, spec.Reward)
	self.log:info(string.format("%s claimed %s for %s.", player.Name, spec.Id, GarageConfig.formatCash(spec.Reward)))
end

-- === Lifecycle ==============================================================

--[[ Cache the profile off the join path and roll the board over if it is stale.

	Hung off `GarageService.ProfileReady` rather than `PlayerAdded` for the reason that signal
	exists: one service owns the profile cache, so one service says when a player is warm.
	`GetProfileAsync` therefore returns immediately here and is called at all so this service holds
	its own handle rather than reaching into another service's.

	The re-check after the yield is the same one `GarageService._watchProfile` and
	`OfflineService._watch` both make: a player who joins and leaves inside that window would
	otherwise be rolled over after they had gone. ]]
function QuestService._watch(self, player: Player)
	task.spawn(function()
		local ok, profile = pcall(function()
			return Data:GetProfileAsync(player)
		end)
		if not ok or not profile or player.Parent ~= Players then
			return
		end

		self._profiles[player] = profile
		if self:_roll(player) then
			self.log:info(string.format("%s's quest board rolled over to a new day.", player.Name))
		end
		-- The client may already be waiting — either order has to work, see header note 4.
		self:_push(player)
	end)
end

--[[ Push whatever changed, at most this often.

	DEBOUNCED RATHER THAN PUSHED PER BUMP, and the case that needs it is the collect sweep: AUTO
	COLLECT and the welcome-back screen both run `collectAll`, which fires `CashCollected` once per
	bay — six pushes of an identical three-row board inside one frame. One flag and one flush makes
	that one push. Nothing waits on it: the profile is already written by the time the flag is set,
	so the delay is only in when the SCREEN catches up. ]]
local PUSH_INTERVAL = 0.5

QuestService:withLifecycle({
	init = function(self)
		self._profiles = {} :: { [Player]: any }
		self._ready = {} :: { [Player]: boolean }
		self._dirty = {} :: { [Player]: boolean }
		self._specsDay = nil :: number?
		self._specsCache = nil
		self._trove = Trove.new()
	end,

	start = function(self)
		if not QuestConfig.Enabled then
			self.log:info("Disabled by config — nothing is counted and the quest page stays empty.")
			return
		end

		local Garage = Shard.get("GarageService")
		if not Garage then
			self.log:warn("No GarageService — quests cannot be stored or paid.")
			return
		end

		self._trove:Add(Garage:getSignal("ProfileReady"):Connect(function(player: Player)
			self:_watch(player)
		end))

		--[[ Catch up on anyone already warm. `GarageService` fires that signal off the join path, so
			on a hot reload — or simply if it starts first — a player can be ready before this
			connects, and would otherwise have an empty board for the rest of the session. ]]
		for _, player in Players:GetPlayers() do
			if Garage:isProfileReady(player) then
				self:_watch(player)
			end
		end

		-- === The metrics ====================================================
		--[[ Every one of these is another service's existing signal. NOTHING IS SUBSCRIBED TO THAT
			WAS ADDED FOR THIS FEATURE except `StealService.CarStolen`, which had no signal at all —
			and that one fires only after the steal was ratified, so it counts what the server
			agreed to rather than what was reported. See header note 1 for the whole table.

			Each is optional. A service that is off or failed to start costs the board its metric
			and one warning, rather than taking this service down with it. ]]
		self._trove:Add(Garage:getSignal("CashCollected"):Connect(function(player: Player, amount: number)
			self:bump(player, "Collect", amount)
		end))

		local Reward = Shard.get("RewardService")
		if Reward then
			self._trove:Add(Reward:getSignal("RunSettled"):Connect(function(player: Player, _cash: number, studs: number, banked: boolean)
				self:_onRunSettled(player, studs, banked)
			end))
		else
			self.log:warn("No RewardService — the road metrics cannot be counted.")
		end

		local Steal = Shard.get("StealService")
		if Steal then
			self._trove:Add(Steal:getSignal("CarStolen"):Connect(function(player: Player)
				self:bump(player, "Steal", 1)
			end))
		end

		local Customer = Shard.get("CustomerService")
		if Customer then
			self._trove:Add(Customer:getSignal("CustomerPaid"):Connect(function(player: Player, amount: number)
				self:bump(player, "Customer", 1)
				--- The same event is the tips quest's (2026-09-28): one customer served, and what they paid.
				self:bump(player, "Tips", amount)
			end))
		end

		--[[ The flush. Throttled off Heartbeat rather than given its own loop for the reason
			`RewardService`'s sampler and `UpgradeService`'s auto-collect both use it: it can never
			outlive the service, and it costs nothing at all while nothing is dirty. ]]
		local accumulated = 0
		self._trove:Add(RunService.Heartbeat:Connect(function(dt: number)
			accumulated += dt
			if accumulated < PUSH_INTERVAL then
				return
			end
			accumulated = 0
			for player in self._dirty do
				self:_push(player)
			end
		end))

		self._trove:Add(Players.PlayerRemoving:Connect(function(player: Player)
			self._profiles[player] = nil
			self._ready[player] = nil
			self._dirty[player] = nil
		end))
	end,
})

QuestService:withCleanup(function()
	if QuestService._trove then
		QuestService._trove:Destroy()
	end
end)

-- Approved economy balance, 2026-10-04.
function QuestService._specs(self, player: Player)
 local board = self:_board(player)
 local day = tonumber(board and board.Day) or QuestConfig.dayIndex()
 local world = WorldConfig.resolve(board and board.World or 1)
 local distinct = board and board.DistinctMetrics == true
 local key = tostring(day) .. ":" .. tostring(world) .. ":" .. tostring(distinct)
 self._balancedSpecs = self._balancedSpecs or {}
 if not self._balancedSpecs[key] then
  local scaled = {}
  local factor = BalanceConfig.firstValue(world) / 600
  for _, original in QuestConfig.dailySet(day, distinct) do
   local spec = table.clone(original)
   spec.Reward = math.round(original.Reward * factor)
   if spec.Metric == "Tips" and world > 1 then
    -- Fixed six-car reference lot: targets never move when the player upgrades or sells.
    self._tipBaselines = self._tipBaselines or {}
    if not self._tipBaselines[world] then
     local body = WorldConfig.Worlds[world].Cars[4]
     local values, indices, efficiencies = {}, {}, {}
     for i = 1, 6 do
      values[i] = BalanceConfig.Values[world][4] * CustomerConfig.tipScaleOf(body)
      indices[i] = i
      efficiencies[i] = 1
     end
     self._tipBaselines[world] = CustomerConfig.simulate(values, 2, 3600, indices, efficiencies)
    end
    local minutes = QuestConfig.TipMinutes[spec.Id]
    spec.Target = math.max(1, math.round(self._tipBaselines[world] * minutes / 60 / 1000) * 1000)
   end
   table.insert(scaled, spec)
  end
  table.clear(self._balancedSpecs)
  self._balancedSpecs[key] = scaled
 end
 return self._balancedSpecs[key]
end

return QuestService
