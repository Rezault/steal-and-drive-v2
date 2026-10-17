--[[
	LeaderboardService  (server)
	----------------------------
	The global all-time boards on the world leaderboard: six rankings, one snapshot, broadcast to
	everybody on a slow timer.

	=== 1. WHAT IT DOES, IN ORDER ==============================================================

	    every WriteInterval   every online player's six stats -> six OrderedDataStores
	    every ReadInterval    top-N back out of each store -> usernames resolved -> one snapshot
	                          -> broadcast to every client

	The client holds ALL SIX BOARDS and draws one, so switching tab costs nothing and asks nothing.
	See `LeaderboardConfig` header note 1 — that is why the catalogue is a shared file.

	=== 2. IT COUNTS ALMOST NOTHING ITSELF =====================================================

	Same rule `QuestService` runs on. Four of the boards read a number the profile already stores
	and two are derived from the collection — its size and its worth; the two counters that had to
	be invented are fed from signals other services were already firing for their own reasons:

	    Stats.Steals     StealService.CarStolen             +1
	    Stats.Distance   RewardService.RunSettled           +studs (measured off the car by the server)
	    Stats.TimePlayed accrued here                       see note 3

	THERE IS NO LEADERBOARD REMOTE A CLIENT CAN SUBMIT A SCORE TO. The only thing a client may send
	is "my board exists, send me the snapshot", and the reply is the same snapshot everyone else
	already got.

	`TimePlayed` is the one thing with no other home — nothing in this game had ever needed to know
	how long somebody had played — so it is accrued here: stamped on join, and the elapsed delta
	added on every write tick, on the way out, and at shutdown.

	=== 3. WHY THE COUNTERS ARE SEPARATE FROM THE QUEST METRICS ================================

	`QuestService` already counts steals and distance, off the same two signals. It would be less
	code to read its numbers — and wrong, because a quest metric is wiped at midnight by design. The
	two subscribe independently to the same signal and neither depends on the other's bookkeeping,
	which is the only shape in which "today" and "ever" cannot corrupt each other.

	=== 4. STUDIO SHOWS A REAL BOARD, MADE OF THE PEOPLE IN THE SERVER ========================

	Real ordered-store I/O is skipped in Studio, so a playtest can never write into the live
	rankings — but a board that renders empty in Studio is a board nobody can build a UI against.
	So in Studio the snapshot is assembled from the ONLINE PLAYERS' live profile values instead,
	ranked the same way and formatted through the same path. A solo playtest shows a one-row board
	with your own numbers on it, which is exactly enough to see that the page binds.

	The counters still accrue in Studio (they are profile writes, not datastore writes), so a steal
	in a playtest moves the number the Studio board draws. Note `Settings.DEBUG_MOCK` wipes the
	profile between playtests, so those numbers start from zero each run.

	=== 5. THE COST OF A ROW IS A USERNAME ====================================================

	A rank is a userId; a row needs a name. `UserService:GetUserInfosByUserIdsAsync` resolves them
	a hundred at a time rather than one call per row, and the result is cached for the life of the
	server — the same handful of names sit on several boards at once and on every refresh after.
	That batching is what makes `LeaderboardConfig.TopN` a number worth raising; see its note.

	DISPLAY NAMES ARE DRAWN, not usernames. It is the name the rest of this game shows (the
	dealership sign, the name tags), and a board that calls somebody something different from every
	other surface reads as a different person.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local UserService = game:GetService("UserService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
-- For `Keys.Found` alone — the catalogue the BIGGEST COLLECTION board counts. See `READERS.Collection`.
local InventoryConfig = require(ReplicatedStorage.shared.Configs.InventoryConfig)
local LeaderboardConfig = require(ReplicatedStorage.shared.Configs.LeaderboardConfig)

local Data = require(script.Parent.Parent.Data)

local STUDIO = RunService:IsStudio()

--[[ One row as the board draws it. `Value` is RAW — the amount cell is formatted on the client
	through `LeaderboardConfig.format`, see that file's header note 5. `Id` is here so a row can
	carry a headshot (`rbxthumb://type=AvatarHeadShot&id=%d&w=420&h=420`, the format the dealership
	sign already uses) without a second lookup. ]]
export type Row = {
	Id: number,
	Name: string,
	Value: number,
}

--- The whole broadcast: every board at once, keyed by `LeaderboardConfig` `Key`.
export type Snapshot = { [string]: { Row } }

local LeaderboardService = Shard.new("LeaderboardService"):withDependencies({ "GarageService", "RewardService" })

LeaderboardService:withRemoteEvents({
	-- server -> client (snapshot): every board, ranked. Sent on each refresh and on a client's ping.
	"LeaderboardState",
	{
		--[[ client -> server: my board exists — send me the snapshot.

			Fired from the controller's `start` and again whenever the board streams back in, so it
			is a REFRESH as well as a handshake and is safe to call any number of times. It exists
			for the reason `QuestService._onReady` does: the first broadcast after a player joins can
			be a minute away, and a board that sits empty for that minute looks broken. ]]
		LeaderboardReady = function(player: Player)
			LeaderboardService:_onReady(player)
		end,
	},
})

-- === Reading a player's stats ===============================================

--[[ NON-YIELDING, like `QuestService._profile` and for the same reason: this is reached from other
	services' signals and from the write tick, neither of which may stall for the seconds
	`Data:GetProfileAsync` can take. The handle is cached off the join path by `_watch`. ]]
function LeaderboardService._profile(self, player: Player)
	local profile = self._profiles[player]
	if profile and profile:IsActive() then
		return profile
	end
	return nil
end

--[[ The readers for boards that are `Derived` rather than a plain `Path` — see `LeaderboardConfig`
	header note 2. Keyed by the config's `Derived` string.

	Add a board that needs one by adding an entry here and naming it in the config; a `Derived` name
	with no reader is warned about once at start rather than every tick. ]]
local READERS: { [string]: (any, Player, any) -> number? } = {}

--[[ How many of the roster this player has EVER banked, counted in DISTINCT BODIES.

	=== IT READS THE CATALOGUE, NOT THE COLLECTION, AND THAT IS THE WHOLE POINT ==================

	`Garage.Found` is body names and never shrinks; `Garage.Owned` is car keys and now DOES shrink,
	because the Cars Inventory lets a player sell a car. This board asks how much of the roster
	somebody has seen, so it has to read the list that cannot go backwards — a rank that fell because
	a player cashed in a spare Camaro would be punishing them for using a feature. The MOST VALUABLE
	board below is the one that should move on a sale, and it does, because it reads `Owned`.

	`InventoryConfig.Keys.Found` names the key and `GarageService._foundList` owns every write to it.

	THE UNION OF BOTH, not just the catalogue, and only for one case: a profile written before `Found`
	existed has an empty one until `GarageService._migrateFound` runs on load, and this reader can be
	handed such a profile before then. The union is what that migration will produce anyway, so the
	board never reads low and never has to know whether the seed has happened yet.

	A NAME THAT IS NOT ON THE ROSTER DOES NOT COUNT, which is the same call the Index page makes.
	The car is not deleted by this (nothing here writes), it simply is not a car the collection has
	a slot for; renaming a body in `WorldConfig` and renaming it back restores the count. ]]
READERS.Collection = function(_self, _player: Player, profile): number?
	local bodies = {}
	local count = 0

	local function add(body: unknown)
		if type(body) == "string" and not bodies[body] and GarageConfig.TierOfBody[body] then
			bodies[body] = true
			count += 1
		end
	end

	local found = profile:Get({ GarageConfig.Keys.Garage, InventoryConfig.Keys.Found })
	if type(found) == "table" then
		for _, body in found do
			add(body)
		end
	end

	local owned = profile:Get({ GarageConfig.Keys.Garage, GarageConfig.Keys.Owned })
	if type(owned) == "table" then
		for _, entry in owned do
			add((GarageConfig.parseCarKey(entry)))
		end
	end

	return count
end

--[[ What this player's whole collection would sell for — the MOST VALUABLE board.

	THE SUM ITSELF IS `GarageConfig.valueOfCollection` AND IS NOT REPEATED HERE, which matters more
	than it looks: the same function is what `GarageService._publishOwned` writes onto the player's
	`DealershipValue` attribute. A board that computed its own total would be a second definition of
	what a dealership is worth, and the two would disagree the first time either the sell price or
	the "is a colour a car?" rule moved — with the leaderboard being the one place nobody would
	notice, because a rank has nothing to check itself against.

	It reads the profile rather than the attribute for the reason every reader here does: this runs
	on the write tick against players whose attribute may not have been published yet, and the
	profile is the source of truth either way. ]]
READERS.Value = function(_self, _player: Player, profile): number?
	local owned = profile:Get({ GarageConfig.Keys.Garage, GarageConfig.Keys.Owned })
	if type(owned) ~= "table" then
		return 0
	end
	return GarageConfig.valueOfCollection(owned)
end

--[[ One board's value for one player, or nil if it cannot be ranked right now.

	nil rather than zero for every failure — no profile yet, an unknown `Derived` reader, a stored
	value that is not a number — because zero is a RANK and "we do not know" is not. `_writePlayer`
	skips a nil, so a player mid-load never overwrites a real ranking with a placeholder. ]]
function LeaderboardService._read(self, board, player: Player): number?
	local profile = self:_profile(player)
	if not profile then
		return nil
	end

	local value
	if board.Derived then
		local reader = READERS[board.Derived]
		if not reader then
			return nil
		end
		value = reader(self, player, profile)
	else
		value = profile:Get(board.Path)
	end

	local number = tonumber(value)
	-- NaN and infinity would both be written into an ordered store as something unrecoverable, and
	-- neither can arrive from an honest path — so they are dropped rather than clamped.
	if not number or number ~= number or number == math.huge then
		return nil
	end
	return math.max(0, math.floor(number))
end

-- === The counters ===========================================================

--[[ Add `amount` to one of the lifetime counters. The ONLY way any of them ever moves, and every
	caller is a signal handler in `start` — nothing reaches this from a remote.

	Reads with an `or 0` guard rather than using `PlayerProfile:Increment`, which adds to whatever
	`Get` returned and errors on a nil: `Reconcile` fills the template in for every profile, but a
	profile caught mid-reconcile, or one whose `Stats` was written as something else by a build that
	no longer exists, must cost this feature a counter and not the player their session. ]]
function LeaderboardService._bump(self, player: Player, stat: string, amount: number)
	local delta = tonumber(amount)
	if not (delta and delta == delta and delta > 0 and delta ~= math.huge) then
		return
	end
	local profile = self:_profile(player)
	if not profile then
		return
	end

	--[[ The PARENT is checked before the leaf is written. `Replica:Set` walks the path and indexes
		every hop, so a `Stats` that is missing — or that some past build wrote as something other
		than a table — is not a write that fails, it is an error thrown out of a signal handler on a
		path that runs on every single steal. `Reconcile` makes that unreachable for an ordinary
		profile; this is for the one caught mid-reconcile, and it costs one table read. ]]
	local key = LeaderboardConfig.ProfileKey
	if type(profile:Get({ key })) ~= "table" then
		local fresh = {}
		for name in LeaderboardConfig.Stats do
			fresh[name] = 0
		end
		profile:Set({ key }, fresh)
	end

	local path = { key, stat }
	local current = tonumber(profile:Get(path)) or 0
	profile:Set(path, current + delta)
end

--[[ Add the seconds since the last flush to `TimePlayed` and re-stamp, so a write immediately after
	this sees the current total.

	RE-STAMPED RATHER THAN CLEARED, which is what makes this safe to call on a timer as well as on
	the way out — every second is counted once, whichever of the two callers gets there first. ]]
function LeaderboardService._flushTime(self, player: Player)
	local last = self._sessionStart[player]
	if not last then
		return
	end
	local now = os.time()
	self._sessionStart[player] = now
	if now > last then
		self:_bump(player, "TimePlayed", now - last)
	end
end

-- === Writing the rankings ===================================================

--[[ Push one player's stats into the ordered stores.

	SKIPS A VALUE THAT HAS NOT MOVED SINCE THE LAST WRITE, which is most of them: a player who spent
	the last two minutes driving has not changed their collection size or their cash, and an ordered
	store that already holds the right number does not need telling again. That is what keeps this
	well inside the request budget as a server fills up.

	SKIPS ZERO AS WELL. A stat nobody has any of is not a rank, and writing it would fill the bottom
	of every board with names that have done nothing.

	Each `SetAsync` is spawned and `pcall`ed independently: a throttled or failed write costs that
	board that player's rank until the next tick, and must not take the other four down with it. ]]
function LeaderboardService._writePlayer(self, player: Player)
	if STUDIO then
		return -- header note 4: never write live rankings from a playtest
	end
	local written = self._written[player]
	if not written then
		return
	end

	local userId = tostring(player.UserId)
	for _, board in LeaderboardConfig.List do
		local value = self:_read(board, player)
		if value and value > 0 and written[board.Key] ~= value then
			local store = self._stores[board.Key]
			if store then
				written[board.Key] = value
				task.spawn(function()
					local ok, err = pcall(function()
						store:SetAsync(userId, value)
					end)
					if not ok then
						-- Forget what we thought we wrote, so the next tick retries rather than
						-- believing a rank that never landed.
						if self._written[player] then
							self._written[player][board.Key] = nil
						end
						self.log:warn(string.format("Could not rank %s on %s: %s", player.Name, board.Key, tostring(err)))
					end
				end)
			end
		end
	end
end

--- The write tick: everybody's time flushed, then everybody's stats ranked.
function LeaderboardService._writeAll(self)
	for _, player in Players:GetPlayers() do
		self:_flushTime(player) -- keeps accruing in Studio, where the write below is a no-op
		self:_writePlayer(player)
	end
end

-- === Names ==================================================================

--[[ userId -> display name for a batch of ids, cached for the life of the server.

	BATCHED, one call per hundred ids rather than one per row — see header note 5. An id the batch
	could not resolve (a deleted account, a throttled call) is cached as a placeholder rather than
	retried every refresh, because the alternative is a board that spends its whole request budget
	on the same failing lookup. ]]
function LeaderboardService._resolveNames(self, userIds: { number })
	local missing = {}
	for _, userId in userIds do
		if self._nameCache[userId] == nil then
			self._nameCache[userId] = false -- claimed, so one id is never in two chunks
			table.insert(missing, userId)
		end
	end

	for start = 1, #missing, 100 do
		local chunk = table.move(missing, start, math.min(start + 99, #missing), 1, {})
		local ok, infos = pcall(function()
			return UserService:GetUserInfosByUserIdsAsync(chunk)
		end)
		if ok and type(infos) == "table" then
			for _, info in infos do
				local name = info.DisplayName
				if type(name) ~= "string" or name == "" then
					name = info.Username
				end
				if type(name) == "string" and name ~= "" then
					self._nameCache[info.Id] = name
				end
			end
		else
			self.log:warn(string.format("Could not resolve %d usernames: %s", #chunk, tostring(infos)))
		end
	end
end

--- The cached name, or the placeholder a row draws while an id has no name. Never nil — a board
--- with a blank cell in it looks broken in a way a board saying "Player" does not.
function LeaderboardService._nameOf(self, userId: number): string
	local cached = self._nameCache[userId]
	return if type(cached) == "string" then cached else "Player"
end

-- === Building the snapshot ==================================================

--[[ The Studio board: everyone in this server, ranked against each other. Header note 4.

	It reads the same values through the same `_read` and hands back the same shape, so a page bound
	against this is bound against the live one — the only difference is where the ranking came from. ]]
function LeaderboardService._localSnapshot(self): Snapshot
	local snapshot: Snapshot = {}
	for _, board in LeaderboardConfig.List do
		local rows: { Row } = {}
		for _, player in Players:GetPlayers() do
			local value = self:_read(board, player)
			if value and value > 0 then
				table.insert(rows, { Id = player.UserId, Name = player.DisplayName, Value = value })
			end
		end
		table.sort(rows, function(a, b)
			return a.Value > b.Value
		end)
		snapshot[board.Key] = rows
	end
	return snapshot
end

--[[ Pull the top-N off every ordered store and assemble the broadcast.

	YIELDS, and is only ever called from a spawned thread guarded by `_refreshing` — five
	`GetSortedAsync` calls plus the name batch is comfortably longer than the gap between two joining
	players pinging, and two refreshes racing would double the request cost to produce the same
	table twice.

	A board whose read failed keeps its PREVIOUS rows rather than becoming empty. A transient
	throttle is not news that everybody lost their rank, and an empty tab is the one state a player
	reads as "this feature is broken". ]]
function LeaderboardService._build(self): Snapshot
	local previous = self._snapshot or {}
	local snapshot: Snapshot = {}
	local pending: { number } = {}

	for _, board in LeaderboardConfig.List do
		local store = self._stores[board.Key]
		local ok, pages = pcall(function()
			return store:GetSortedAsync(false, LeaderboardConfig.TopN) -- false = descending
		end)
		if not (ok and pages) then
			self.log:warn(string.format("Could not read the %s board: %s", board.Key, tostring(pages)))
			snapshot[board.Key] = previous[board.Key] or {}
			continue
		end

		local rows: { Row } = {}
		for _, entry in pages:GetCurrentPage() do
			local userId = tonumber(entry.key)
			local value = tonumber(entry.value)
			if userId and value then
				table.insert(rows, { Id = userId, Name = "", Value = value })
				table.insert(pending, userId)
			end
		end
		snapshot[board.Key] = rows
	end

	self:_resolveNames(pending)
	for _, rows in snapshot do
		for _, row in rows do
			if row.Name == "" then
				row.Name = self:_nameOf(row.Id)
			end
		end
	end

	return snapshot
end

--[[ Rebuild and broadcast. Guarded so only one runs at a time — see `_build`.

	SKIPPED ON AN EMPTY SERVER once there is a snapshot to keep: nobody is looking, and the request
	budget an idle server spends is budget a busy one does not have. A joining player's ping runs
	one on demand if there is nothing to send them. ]]
function LeaderboardService._refresh(self, force: boolean?)
	if self._refreshing then
		return
	end
	if not force and #Players:GetPlayers() == 0 and self._snapshot then
		return
	end

	self._refreshing = true
	task.spawn(function()
		local ok, result = pcall(function()
			return if STUDIO then self:_localSnapshot() else self:_build()
		end)
		self._refreshing = false
		if not ok then
			self.log:warn(string.format("Leaderboard refresh failed: %s", tostring(result)))
			return
		end
		self._snapshot = result
		self:getRemoteEvent("LeaderboardState"):FireAll(result)
	end)
end

-- === The client's end =======================================================

--[[ "My board exists." Also "send it again", so unlike a one-shot handshake this may be called
	whenever the board streams back in.

	The refresh it can trigger is the empty-server case: the first player into a server that has
	been idle has nothing to be sent, and waiting up to a full `ReadInterval` for a board to appear
	is the difference between a feature and a bug report. `_refreshing` makes ten simultaneous
	joiners cost one rebuild. ]]
function LeaderboardService._onReady(self, player: Player)
	if not LeaderboardConfig.Enabled then
		return
	end
	if self._snapshot then
		self:getRemoteEvent("LeaderboardState"):FireClient(player, self._snapshot)
		return
	end
	self:_refresh(true)
end

-- === Lifecycle ==============================================================

--[[ Cache the profile off the join path, exactly as `QuestService._watch` does and for the same
	reason: one service owns the profile cache and says when a player is warm, so `GetProfileAsync`
	returns immediately here.

	The session stamp is set HERE rather than on `PlayerAdded`, so the seconds spent waiting for a
	profile that never arrived are not banked against a player who was kicked for it. ]]
function LeaderboardService._watch(self, player: Player)
	task.spawn(function()
		local ok, profile = pcall(function()
			return Data:GetProfileAsync(player)
		end)
		if not ok or not profile or player.Parent ~= Players then
			return
		end
		self._profiles[player] = profile
		self._written[player] = {}
		self._sessionStart[player] = os.time()
	end)
end

--- Everything one leaving player owes: their session time, one last ranking, then forget them.
function LeaderboardService._release(self, player: Player)
	self:_flushTime(player)
	self:_writePlayer(player)
	self._profiles[player] = nil
	self._written[player] = nil
	self._sessionStart[player] = nil
end

LeaderboardService:withLifecycle({
	init = function(self)
		self._profiles = {} :: { [Player]: any }
		self._stores = {} :: { [string]: OrderedDataStore }
		self._written = {} :: { [Player]: { [string]: number } } -- last value ranked, per board
		self._sessionStart = {} :: { [Player]: number } -- os.time() of this player's last time flush
		self._nameCache = {} :: { [number]: string | false } -- false = looked up and unresolved
		self._snapshot = nil :: Snapshot?
		self._refreshing = false
		self._trove = Trove.new()
	end,

	start = function(self)
		if not LeaderboardConfig.Enabled then
			self.log:info("Disabled by config — nothing is ranked and the board stays empty.")
			return
		end

		--[[ The dev/prod suffix goes on the STORE NAME, the same isolation the profile keys get from
			the same call. A Studio playtest therefore cannot see the live rankings even if the
			Studio guard above it were ever removed. ]]
		local suffix = Data:GetSuffix()
		for _, board in LeaderboardConfig.List do
			self._stores[board.Key] = DataStoreService:GetOrderedDataStore(board.Store .. suffix)
			if board.Derived and not READERS[board.Derived] then
				self.log:warn(string.format("Board %s wants a %q reader that does not exist.", board.Key, board.Derived))
			end
		end

		local Garage = Shard.get("GarageService")
		if not Garage then
			self.log:warn("No GarageService — nothing can be ranked.")
			return
		end

		self._trove:Add(Garage:getSignal("ProfileReady"):Connect(function(player: Player)
			self:_watch(player)
		end))

		--[[ Catch up on anyone already warm. `GarageService` fires that signal off the join path, so
			a player can be ready before this connects — on a hot reload, or simply if it starts
			first — and would otherwise never accrue a second of this session. ]]
		for _, player in Players:GetPlayers() do
			if Garage:isProfileReady(player) then
				self:_watch(player)
			end
		end

		-- === The counters ===================================================
		--[[ Both are another service's existing signal; nothing was added anywhere for this feature.
			See header note 2 for the table, and note 3 for why these are counted separately from the
			identical-looking quest metrics.

			Each is optional: a service that is off or failed to start costs one board its numbers and
			one warning, rather than taking this service down with it. ]]
		local Reward = Shard.get("RewardService")
		if Reward then
			self._trove:Add(Reward:getSignal("RunSettled"):Connect(function(player: Player, _cash: number, studs: number)
				self:_bump(player, "Distance", studs)
			end))
		else
			self.log:warn("No RewardService — distance cannot be counted.")
		end

		local Steal = Shard.get("StealService")
		if Steal then
			self._trove:Add(Steal:getSignal("CarStolen"):Connect(function(player: Player)
				self:_bump(player, "Steals", 1)
			end))
		else
			self.log:warn("No StealService — steals cannot be counted.")
		end

		self._trove:Add(Players.PlayerRemoving:Connect(function(player: Player)
			self:_release(player)
		end))

		self._trove:Add(task.spawn(function()
			while true do
				task.wait(LeaderboardConfig.WriteInterval)
				self:_writeAll()
			end
		end))

		--[[ The read loop refreshes FIRST and then waits, so a server that has just come up has a
			board to hand the first player who asks for one instead of a minute of nothing. ]]
		self._trove:Add(task.spawn(function()
			while true do
				self:_refresh()
				task.wait(LeaderboardConfig.ReadInterval)
			end
		end))

		--[[ Last call. Roblox kicks every player before `BindToClose` runs, so `PlayerRemoving` has
			normally already settled everyone — this is the belt for a shutdown that outruns it.

			The wait is for the spawned `SetAsync` calls inside `_writePlayer`, which are detached by
			design (see its note) and would otherwise be killed with the server. ]]
		game:BindToClose(function()
			if STUDIO then
				return
			end
			for _, player in Players:GetPlayers() do
				self:_release(player)
			end
			task.wait(2)
		end)
	end,
})

LeaderboardService:withCleanup(function()
	if LeaderboardService._trove then
		LeaderboardService._trove:Destroy()
	end
end)

return LeaderboardService
