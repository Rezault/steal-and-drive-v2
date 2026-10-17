--[[
	PlaytesterService  (server)
	---------------------------
	The testing-session attendance report: on a testing server's shutdown, ONE Discord embed listing
	everybody who turned up, how long they stayed, and how far they got — posted to the tester
	channel so a playtest leaves a record without anybody having to write one.

	Modelled on the same report in Needoh Escape, with this game's numbers in place of that one's
	Level / Rebirths / Wins.

	=== 1. WHAT ONE ROW SAYS ==================================================================

	    🥇 **Someone** · 🛣️ 82.4K studs · 🚔 14 steals · 🚗 9/29 cars · 🌍 Desert · ⏱️ `42:10`

	THREE OF THE FIVE ARE THIS SESSION, AND TWO ARE NOT, which is the whole design of the row and
	the only part worth arguing about:

	  • `studs`, `steals` and the time are SESSION TOTALS — what this person did today. They are the
	    honest answer to "who actually played" for the same reason the lifetime numbers are the wrong
	    one: a returning tester whose profile says 4M studs drove twenty thousand of them this
	    afternoon, and an attendance report that printed the 4M would be reporting a different day.

	  • `cars` and the world are WHERE THEY GOT TO, which is a position and not an activity — nobody
	    wants "gained 2 cars", they want to know whether anyone reached the desert. So those two are
	    read off the profile as it stands when the player leaves.

	The session halves are accumulated from other services' EXISTING signals, exactly as
	`LeaderboardService` accumulates its lifetime counters and for the same reason — nothing was
	added anywhere for this feature, and nothing here can disagree with the game about what happened:

	    RewardService.RunSettled   runs, getaways, studs driven, cash earned
	    StealService.CarStolen     steals

	Both are optional. A service that is off or failed to start costs this report one column and one
	warning, not the report.

	`cars` is DISTINCT BODIES out of `Garage.Found` union `Garage.Owned`, which is deliberately the
	same count the Index page draws and the BIGGEST COLLECTION board ranks — see
	`LeaderboardService.READERS.Collection`, which this mirrors. A report that disagreed with the
	player's own collection screen would read as a bug whichever number was right.

	=== 2. WHEN IT RUNS =======================================================================

	`TESTING_PLACE_IDS` only, or a Studio playtest with `ENABLE_IN_STUDIO` on (which is how you
	verify the webhook without waiting for a testing day). Everywhere else `start` registers nothing
	at all — no signals, no `BindToClose`, no HTTP.

	=== 3. WHY THE CAPTURE IS WHERE IT IS =====================================================

	Progress is snapshotted in the `observePlayer` CLEANUP, so a tester who leaves halfway through is
	still reported with their final numbers — their profile handle is released shortly after they go,
	and by shutdown it is long gone. Everybody still connected is captured in `BindToClose`.

	`_capture` is idempotent: folding the elapsed segment clears `joinedAt`, so the two paths cannot
	double-count a second. It re-reads the profile on a second call, which is free and means the
	later of the two callers always wins.

	A REJOIN KEEPS THE RECORD. Records are keyed by userId, so somebody who crashes and comes back is
	one row with their whole afternoon on it rather than two half-rows.

	=== 4. THE WEBHOOK LIVES HERE, ON THE SERVER ==============================================

	Never in `ReplicatedStorage` — a URL a client can read is a URL a client can spam. Roblox blocks
	`discord.com` / `discordapp.com` outright, so `proxyUrl` rewrites the host to the lewisakura
	proxy, which accepts the same webhook path unchanged; a URL already pointing at the proxy is left
	alone. Paste either form into `WEBHOOK_URL`.

	HTTP REQUESTS MUST BE ON for any of this to leave the server (`HttpService.HttpEnabled`, or
	Game Settings -> Security in Studio). It is off by default in a fresh place and the failure is a
	`pcall` that warns and nothing else, which is why `start` says so up front.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Promise = require(ReplicatedStorage.Packages.Promise)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Observers = require(ReplicatedStorage.Packages.Observers)

local Admins = require(ReplicatedStorage.shared.Configs.Admins)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local InventoryConfig = require(ReplicatedStorage.shared.Configs.InventoryConfig)
local LeaderboardConfig = require(ReplicatedStorage.shared.Configs.LeaderboardConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local Data = require(script.Parent.Parent.Data)

-- === What to post, and where ================================================

--[[ The tester channel's webhook — #tester-attendance, WHICH NEEDOH ESCAPE ALSO POSTS TO. Two games
	share one channel, which is why `EMBED_AUTHOR` below names this one: the report has to say which
	game it is from the first line, because the row format is the only other thing telling them apart.

	Either a raw `discord.com/api/webhooks/...` URL or one already pointing at the proxy —
	`proxyUrl` normalises both. EMPTY MEANS OFF: `start` warns once and registers nothing, so a fresh
	clone of this repo cannot post a report into somebody's channel by accident.

	It is a constant rather than a config entry on purpose. Everything in `shared/Configs` is
	replicated to every client, and this is the one string in this feature that must not be. ]]
local WEBHOOK_URL =
	"https://webhook.lewisakura.moe/api/webhooks/1365454481915117588/Mwpq3E0GNtrW6vrDjRle5ZUj84JGuH2yxGOFd-Y_9P8wPISvONLx3J52YPP0CVKBx4QG"

--- Places this is allowed to run in. The TS place (universe 10771147148); never Main, which is
--- production and would post a report for every live server that closes.
local TESTING_PLACE_IDS = { 135909936139468 }

--[[ Post on a Studio playtest stop. The way to verify the webhook without waiting for a testing
	day — set it, stop a playtest, look at the channel. Leave it FALSE otherwise: with it on, every
	playtest anybody runs puts a one-line report in the tester channel. ]]
local ENABLE_IN_STUDIO = false

--- Hide devs/admins (`Configs.Admins`) from the report. Turn it off to see yourself in a Studio test.
local EXCLUDE_ADMINS = true

--- Sessions under this are not attendance — someone who joined, saw the lobby and left.
local MIN_SECONDS = 60

-- === Sending ================================================================

local MAX_RETRIES = 2 -- extra attempts after the first
local RETRY_DELAY = 2 -- seconds between them
local SEND_TIMEOUT = 10 -- hard cap on the whole send, so a dead webhook never hangs shutdown
local FLUSH_WAIT = 2 -- let the request leave the machine before the server dies

-- === The embed ==============================================================

local EMBED_COLOR = 0x0066FF -- the UI kit's title-bar blue, so the report looks like the game
local EMBED_AUTHOR = "TESTING SESSION - My Car Got Stolen 🚗"
local DESCRIPTION_LIMIT = 3900 -- under Discord's 4096, leaving room for the overflow note
local MEDALS = { "🥇", "🥈", "🥉" } -- top-three time rank icons

--- How many bodies the roster has, for the `9/29` cell. Counted once — `TierOfBody` is a map.
local ROSTER = 0
for _ in GarageConfig.TierOfBody do
	ROSTER += 1
end

-- === Helpers ================================================================

local function shouldRun(): boolean
	if RunService:IsStudio() then
		return ENABLE_IN_STUDIO
	end
	return table.find(TESTING_PLACE_IDS, game.PlaceId) ~= nil
end

--- Roblox refuses `discord.com` / `discordapp.com`; the proxy takes the same path. A URL already on
--- the proxy passes through untouched.
local function proxyUrl(url: string): string
	return (url:gsub("discordapp%.com", "webhook.lewisakura.moe"):gsub("discord%.com", "webhook.lewisakura.moe"))
end

--[[ How a tester is named on their row.

	THE DISPLAY NAME, PLUS THE USERNAME WHEN THE TWO DIFFER. Everywhere else in this game draws the
	display name alone (the dealership sign, the name tags, the leaderboard) because that is what a
	player calls themselves — but this report is read by a human matching testers up against Discord
	afterwards, and a display name is not an identity: two people can share one, and anybody can
	change theirs between sessions. The username is the handle that survives that.

	It only appears when it adds something, so a tester who has never set a display name gets one
	name rather than the same string written twice. ]]
local function nameOf(player: Player): string
	if player.DisplayName ~= "" and player.DisplayName ~= player.Name then
		return string.format("%s (@%s)", player.DisplayName, player.Name)
	end
	return player.Name
end

--- seconds -> "MM:SS", minutes uncapped ("125:30"). The attendance format the other games use.
local function formatTime(totalSeconds: number): string
	local s = math.max(0, math.floor(totalSeconds))
	return string.format("%02d:%02d", math.floor(s / 60), s % 60)
end

--- Anything that arrives off a signal, as a non-negative integer. NaN and infinity are dropped
--- rather than clamped — neither can come from an honest path, and both poison a running total.
local function amount(value: unknown): number
	local number = tonumber(value)
	if not number or number ~= number or number == math.huge then
		return 0
	end
	return math.max(0, math.floor(number))
end

--[[ Distinct bodies this player has ever banked, out of the catalogue AND the collection.

	The union rather than either alone, mirroring `LeaderboardService.READERS.Collection` — `Found`
	never shrinks and is the right list, but a profile written before `Found` existed has an empty
	one until `GarageService._migrateFound` runs, and the union is what that migration produces
	anyway. A name that is not on the roster does not count, which is the call the Index page makes.

	Deliberately NOT factored out of the leaderboard's copy: that one is a private reader inside a
	service this must not depend on, and the two are eight lines answering the same question for
	different audiences. If a third caller ever wants it, it belongs on `GarageConfig`. ]]
local function collectionSize(profile): number
	local bodies, count = {}, 0

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

-- === The service ============================================================

--[[ `RewardService` and `StealService` are what the session columns are counted from, and
	`GarageService` is what puts a profile on a player. All three are soft — see the header — but
	naming them means `init` runs after theirs, so the signals exist by the time `start` looks. ]]
local PlaytesterService =
	Shard.new("PlaytesterService"):withDependencies({ "GarageService", "RewardService", "StealService" })

--[[ One tester's whole afternoon.

	  player/name  who; `player` goes stale once they leave and is only read before that
	  joinedAt     os.time() of the open segment, or nil once it has been folded into `seconds`
	  seconds      time attended, summed over every segment (a rejoin is a second segment)
	  studs        distance driven this session, off `RunSettled`
	  steals       cars taken off the road this session, off `CarStolen`
	  runs         runs finished this session, and how many of them `banked` (got away)
	  earned       cash paid out by those runs
	  cars/world   snapshotted from the profile at capture; see header note 1 ]]
type Record = {
	player: Player?,
	name: string,
	joinedAt: number?,
	seconds: number,
	studs: number,
	steals: number,
	runs: number,
	getaways: number,
	earned: number,
	cars: number?,
	world: number?,
}

-- === Accumulating ===========================================================

--[[ The record for a player who is being tracked, or nil for one who is not — an admin, or anybody
	at all when this service is dormant. Every signal handler goes through here, so a report that is
	not running costs one table lookup per run. ]]
function PlaytesterService._recordOf(self, player: Player): Record?
	return if player then self._records[player.UserId] else nil
end

--- One finished run: its distance, its payout, and whether it ended with the car in the garage.
function PlaytesterService._onRunSettled(self, player: Player, cash: unknown, studs: unknown, banked: unknown)
	local record = self:_recordOf(player)
	if not record then
		return
	end
	record.runs += 1
	record.studs += amount(studs)
	record.earned += amount(cash)
	if banked then
		record.getaways += 1
	end
end

--- One ratified steal.
function PlaytesterService._onCarStolen(self, player: Player)
	local record = self:_recordOf(player)
	if record then
		record.steals += 1
	end
end

--[[ Cache the profile handle off the join path so `_capture` never yields — it is called from a
	leave handler and from `BindToClose`, and neither may stall for the seconds
	`Data:GetProfileAsync` can take on a cold join.

	Spawned rather than awaited: the yield belongs to this thread, and a profile that never arrives
	(a player kicked on load) simply leaves the two profile columns unset. ]]
function PlaytesterService._watch(self, player: Player)
	task.spawn(function()
		local ok, profile = pcall(function()
			return Data:GetProfileAsync(player)
		end)
		if ok and profile and self._records[player.UserId] then
			self._profiles[player.UserId] = profile
		end
	end)
end

--[[ Fold the open segment into the record and snapshot the profile columns.

	IDEMPOTENT. Clearing `joinedAt` means a second call — leave then shutdown, or the other way
	round — re-reads the profile but adds no time. See header note 3. ]]
function PlaytesterService._capture(self, userId: number)
	local record = self._records[userId]
	if not record then
		return
	end

	if record.joinedAt then
		record.seconds += math.max(0, os.time() - record.joinedAt)
		record.joinedAt = nil
	end

	local profile = self._profiles[userId]
	if profile and profile:IsActive() then
		-- pcall'd because this runs on the shutdown path: a profile caught mid-reconcile, or one
		-- whose `Garage` a past build wrote as something else, must cost two columns rather than
		-- the whole report.
		local ok, err = pcall(function()
			record.cars = collectionSize(profile)
			record.world = tonumber(profile:Get({ WorldConfig.UnlockProfileKey }))
		end)
		if not ok then
			self.log:warn(string.format("Could not read %s's progress: %s", record.name, tostring(err)))
		end
	end
end

-- === The report =============================================================

--[[ Build the payload from every record over the threshold, ranked by time. Returns nil when nobody
	qualifies, which is a testing server nobody showed up to and is not worth a post. ]]
function PlaytesterService._buildPayload(self)
	local rows: { Record } = {}
	for _, record in self._records do
		if record.seconds >= MIN_SECONDS then
			table.insert(rows, record)
		end
	end
	if #rows == 0 then
		return nil
	end

	table.sort(rows, function(a, b)
		return a.seconds > b.seconds
	end)

	--[[ The session at a glance, above the roster. TOTALS RATHER THAN AVERAGES: "39 runs, 22 got
		away" is a wreck rate anybody can read off it, and a mean would hide the one tester who did
		half of them. ]]
	local studs, steals, runs, getaways, earned = 0, 0, 0, 0, 0
	for _, record in rows do
		studs += record.studs
		steals += record.steals
		runs += record.runs
		getaways += record.getaways
		earned += record.earned
	end

	local lines = {
		string.format(
			"**%s studs driven · %s steal%s · %d run%s (%d got away) · %s earned**",
			LeaderboardConfig.abbreviate(studs),
			LeaderboardConfig.group(steals),
			steals == 1 and "" or "s",
			runs,
			runs == 1 and "" or "s",
			getaways,
			GarageConfig.formatCash(earned)
		),
		"",
	}

	local length = #lines[1] + 2
	local dropped = 0
	for index, record in rows do
		-- 🥇🥈🥉 for the top three by time, `#4`, `#5`, ... below them.
		local rank = MEDALS[index] or string.format("`#%d`", index)
		local line = string.format(
			"%s **%s** · 🛣️ %s studs · 🚔 %s steal%s · 🚗 %d/%d cars · 🌍 %s · ⏱️ `%s`",
			rank,
			record.name,
			LeaderboardConfig.abbreviate(record.studs),
			LeaderboardConfig.group(record.steals),
			record.steals == 1 and "" or "s",
			record.cars or 0,
			ROSTER,
			WorldConfig.displayName(record.world or 1),
			formatTime(record.seconds)
		)
		if length + #line + 1 > DESCRIPTION_LIMIT then
			dropped = #rows - index + 1
			break
		end
		table.insert(lines, line)
		length += #line + 1
	end
	if dropped > 0 then
		table.insert(lines, string.format("_+ %d more_", dropped))
	end

	local count = #rows
	return {
		embeds = {
			{
				color = EMBED_COLOR,
				author = { name = EMBED_AUTHOR },
				description = table.concat(lines, "\n"),
				footer = { text = string.format("%d tester%s this session", count, count == 1 and "" or "s") },
				timestamp = DateTime.now():ToIsoDate(),
			},
		},
	}
end

--- POST the payload with a bounded retry; resolves on the first success. The caller awaits it under
--- `SEND_TIMEOUT`, so a webhook that hangs can never hold the shutdown open.
function PlaytesterService._send(self, payload)
	local url = proxyUrl(WEBHOOK_URL)
	local body = HttpService:JSONEncode(payload)

	return Promise.retryWithDelay(function()
		return Promise.new(function(resolve, reject)
			task.spawn(function()
				local ok, err = pcall(function()
					HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson)
				end)
				if ok then
					resolve()
				else
					reject(err)
				end
			end)
		end)
	end, MAX_RETRIES, RETRY_DELAY)
end

--- Everybody still connected, then the post. Called once, from `BindToClose`.
function PlaytesterService._report(self)
	for _, player in Players:GetPlayers() do
		self:_capture(player.UserId)
	end

	local payload = self:_buildPayload()
	if not payload then
		return
	end

	-- `await` returns (ok, ...) rather than raising, so the status is checked directly.
	local ok, err = self:_send(payload):timeout(SEND_TIMEOUT):await()
	if not ok then
		self.log:warn(string.format("Attendance webhook failed: %s", tostring(err)))
	end

	task.wait(FLUSH_WAIT)
end

-- === Lifecycle ==============================================================

PlaytesterService:withLifecycle({
	init = function(self)
		self._records = {} :: { [number]: Record }
		self._profiles = {} :: { [number]: any }
		self._trove = Trove.new()
	end,

	start = function(self)
		if not shouldRun() then
			return -- not a testing context: nothing is tracked and nothing is posted
		end
		if WEBHOOK_URL == "" then
			self.log:warn("No WEBHOOK_URL — attendance is not being tracked. Paste the tester channel's webhook in.")
			return
		end
		if not RunService:IsStudio() and not HttpService.HttpEnabled then
			-- Warned rather than aborted: HttpEnabled can be turned on while a server is up, and the
			-- report is only built at shutdown anyway.
			self.log:warn("HttpService.HttpEnabled is off — the attendance report cannot be posted.")
		end

		self._trove:Add(Observers.observePlayer(function(player: Player)
			if EXCLUDE_ADMINS and Admins.isAdmin(player) then
				return
			end

			local userId = player.UserId
			local existing = self._records[userId]
			if existing then
				-- Rejoin: keep everything accumulated, restamp the new segment. See header note 3.
				existing.player = player
				existing.name = nameOf(player)
				existing.joinedAt = os.time()
			else
				self._records[userId] = {
					player = player,
					name = nameOf(player),
					joinedAt = os.time(),
					seconds = 0,
					studs = 0,
					steals = 0,
					runs = 0,
					getaways = 0,
					earned = 0,
				}
			end
			self:_watch(player)

			return function()
				self:_capture(userId)
				self._profiles[userId] = nil
			end
		end))

		--[[ The session columns, off signals two other services were already firing for their own
			reasons — header note 1. Each is optional and costs one column if it is missing. ]]
		local Reward = Shard.get("RewardService")
		if Reward then
			self._trove:Add(Reward:getSignal("RunSettled"):Connect(function(player: Player, cash, studs, banked)
				self:_onRunSettled(player, cash, studs, banked)
			end))
		else
			self.log:warn("No RewardService — distance and runs cannot be counted.")
		end

		local Steal = Shard.get("StealService")
		if Steal then
			self._trove:Add(Steal:getSignal("CarStolen"):Connect(function(player: Player)
				self:_onCarStolen(player)
			end))
		else
			self.log:warn("No StealService — steals cannot be counted.")
		end

		game:BindToClose(function()
			self:_report()
		end)
	end,
})

PlaytesterService:withCleanup(function()
	if PlaytesterService._trove then
		PlaytesterService._trove:Destroy()
	end
end)

return PlaytesterService
