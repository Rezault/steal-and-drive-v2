--[[
	WeatherService  (server — the clock, and the only thing that says what the weather is)
	--------------------------------------------------------------------------------------
	Nothing here draws anything, and — since the schedule became a grid — nothing here DECIDES
	anything either. `WeatherConfig.scheduledAt` is the schedule: one event per world every fifteen
	minutes, each world offset so they cannot all fire at once, and the answer is pure arithmetic on
	the server clock. This service reads that once a second, notices when it has changed, and turns
	the change into the two things the rest of the game consumes:

	  • `WeatherConfig.Attribute` on the Workspace, holding every world's state at once;
	  • one notice per start, fired at THE PLAYERS IN THAT WORLD (see `WeatherConfig.StartedEvent`).

	It also keeps the two things arithmetic cannot: the HISTORY a payout claim is bounded against,
	and the ADMIN OVERRIDE that outranks the grid while it lasts.

	=== WHY THE SERVER OWNS THIS AT ALL ========================================================

	Everything about a race is client-built: the road, the traffic, the obstacles and the truck (see
	RoadController's header). A client could therefore run its own weather and nobody would ever
	know. It is done this way round for the same reason `TipsService` is, and one more:

	  • EVERYONE IN THE SERVER HAS TO AGREE. "World 2 is having a thunderstorm" is a thing players
	    tell each other and go and do together. Per-client weather would make that a lie half the
	    time, and the first bug report would be two friends in the same world seeing different skies.
	  • IT IS WORTH MONEY. A mutation multiplies a payout, so the question "could this player have
	    seen a Molten car" has to have an answer that the player did not write. `couldHaveSpawned`
	    below is that answer, and it only exists because this schedule is not the client's.

	=== WHAT IT DOES NOT DO ====================================================================

	It does not roll mutations. Which cars are mutated is decided per spawn on the client that spawns
	them (`TrafficController._spawn` -> `WeatherConfig.roll`), because that is where the cars are and
	because a per-spawn round trip for a cosmetic-plus-multiplier roll would be forty remotes a
	minute per player. What this service bounds is the CLAIM at the end (see the trust note in
	`WeatherConfig`), which is the half that matters.

	It also does not touch Lighting. `WeatherController` does, on each client, for its own race.

	=== THE HISTORY ============================================================================

	Every event that has run in a world is kept, with the window it ran in, up to `HISTORY_LIMIT`
	entries. That is what `couldHaveSpawned` reads: "did this mutation's event overlap the window
	this player was actually driving in". It is a few dozen small tables per server for the whole
	uptime, and it is the only defence the payout has.

	HOUSE RULE: no wiki-style double-bracket links in this comment — the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Admins = require(ReplicatedStorage.shared.Configs.Admins)
local Shard = require(ReplicatedStorage.Packages.Shard)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local WeatherService = Shard.new("WeatherService")

--[[ How many past events per world to remember. Twenty at a floor of ~six minutes an event is two
	hours of history, which is longer than any single run and longer than most servers live. A run
	that somehow outlasted it would have its mutation refused rather than trusted, which is the
	direction to fail in. ]]
local HISTORY_LIMIT = 20

--[[ A grace window, in seconds, added to both ends of an event when checking a claim.

	It exists because the three clocks involved do not tick together: the event ends on this server,
	the client's copy of the state arrives a replication hop later, and the car it spawned in that
	window is still on the road for a while afterwards. Without the grace, a player who stole a
	Charged car in the last second of a storm and drove another minute to the truck would have the
	bank refused — which is a real player being told their jackpot did not happen.

	Sized at a minute because that is comfortably longer than the replication hop plus the time a
	spawned car stays alive, and short enough that it buys a liar nothing they could not have had by
	waiting. ]]
local CLAIM_GRACE = 60

--[[ Bounds on a hand-forced event's length, in seconds. The panel's slider is bounded to the same
	range, so this is the second copy — and the one that counts, because the first is on the client.

	The top of the range is a whole `Schedule.Period`, which is the longest an override can run
	without the world's next scheduled event having been swallowed while it was up. ]]
local ADMIN_DURATION = { 10, 900 }

--- The least time between one admin's requests. A button held down on a bad frame is the thing this
--- stops; an admin who wants two events in two seconds is not, and gets them.
local ADMIN_COOLDOWN = 0.25

WeatherService:withRemoteEvents({
	--[[ server -> client `(world, eventKey, endsAt)`: an event has just STARTED. Sent only to the
		players in that world (`_flush`), and carrying keys rather than sentences for the reason
		`TipsConfig` gives at length — the copy has one home, and a client one deploy behind shows
		nothing rather than a blank notice.

		The STATE is not sent here. It rides the attribute, which replicates on its own and which a
		late joiner reads without asking; this is the notification only, and a client that misses it
		has missed one toast and nothing else. ]]
	WeatherConfig.StartedEvent,
	{
		--[[ client -> server: the F2 panel's Weather tab. See `WeatherConfig.AdminEvent` for the
			shape and for why the admin check below is not optional. ]]
		[WeatherConfig.AdminEvent] = function(player: Player, action: unknown, world: unknown, key: unknown, seconds: unknown)
			WeatherService:_onAdmin(player, action, world, key, seconds)
		end,
	},
})

-- === Rolling ================================================================
--[[ Pick an event for one world, weighted, refusing an immediate repeat.

	THE SCHEDULE NO LONGER CALLS THIS. A world's next event is whatever its queue says
	(`WeatherConfig.queuedEvent`), which is a rotation and cannot repeat; this is the admin panel's
	Roll button and nothing else, which is what `Events.Weight` is still for.

	The refusal is a re-roll rather than a filtered pool, and deliberately: filtering would mean
	rebuilding the weighted list per call, and with six events a re-roll converges instantly. It is
	capped anyway, so a config with one event (or with `NoImmediateRepeat` on and every event but one
	weighted to zero) returns that one rather than spinning. ]]
function WeatherService._pick(self, world: number): string?
	local events = WeatherConfig.Events
	if #events == 0 then
		return nil
	end

	local total = 0
	for _, event in events do
		total += math.max(0, event.Weight or 0)
	end
	if total <= 0 then
		return nil
	end

	local last = self._last[world]
	for _ = 1, 8 do
		local roll = self._random:NextNumber() * total
		for _, event in events do
			roll -= math.max(0, event.Weight or 0)
			if roll <= 0 then
				if not (WeatherConfig.Schedule.NoImmediateRepeat and #events > 1 and event.Key == last) then
					return event.Key
				end
				break
			end
		end
	end

	-- Eight rolls all came back as the repeat. Give it to them: a repeated event is a much smaller
	-- problem than a world whose weather quietly stops.
	return last
end

-- === Publishing =============================================================

--[[ Write the whole schedule onto the Workspace, if it has changed.

	COMPARED BEFORE WRITING, which is what `WeatherConfig.encode` sorts its worlds for. Setting an
	attribute to the value it already holds still fires `GetAttributeChangedSignal` on every client,
	and this is called from every tick — so without the comparison a clear server would be waking
	every client's weather controller once a second to tell it nothing. ]]
function WeatherService._publish(self)
	local encoded = WeatherConfig.encode(self._state)
	if encoded == self._encoded then
		return
	end
	self._encoded = encoded
	workspace:SetAttribute(WeatherConfig.Attribute, encoded)
end

--[[ Send the notices queued by `_open`, and ONLY to the players whose world they are about — see
	`WeatherConfig.StartedEvent` for why that is the whole design of the notification now.

	QUEUED RATHER THAN FIRED AT THE SITE, so that every notice goes out AFTER `_publish` has written
	the attribute. A client told "rush hour has started" that then read a Workspace attribute still
	saying otherwise would have one frame in which its own notice contradicted its own road, and the
	order is free to get right here.

	A MISSING WORLD ATTRIBUTE IS NOT WORLD 1 HERE, which is the one place in this feature that does
	not lean on `WorldConfig.resolve`. Absent means the profile has not loaded yet (`WorldConfig`'s
	note on it), and resolving that to the default would fire a City notice at everybody who happened
	to be mid-join. No attribute, no notice; they get the replay in `start` a moment later. ]]
function WeatherService._flush(self)
	local pending = self._pending
	if #pending == 0 then
		return
	end
	self._pending = {}

	local remote = self:getRemoteEvent(WeatherConfig.StartedEvent)
	for _, notice in pending do
		for _, player in Players:GetPlayers() do
			if player:GetAttribute(WorldConfig.WorldAttribute) == notice.world then
				remote:Fire(player, notice.world, notice.event, notice.endsAt)
			end
		end
	end
end

-- === The schedule ===========================================================

--[[ Start `key` in `world`, running until `endsAt`.

	Neither publishes nor notifies: both are done once per tick by the caller, in that order, for the
	reason `_flush` gives. What this does own is the HISTORY, which is the only part of the feature
	arithmetic cannot reproduce — `couldHaveSpawned` reads it, and a payout is bounded by it. ]]
function WeatherService._open(self, world: number, key: string, endsAt: number, now: number)
	self._state[world] = { event = key, endsAt = endsAt }
	self._last[world] = key

	local history = self._history[world]
	table.insert(history, { event = key, startedAt = now, endsAt = endsAt })
	while #history > HISTORY_LIMIT do
		table.remove(history, 1)
	end

	table.insert(self._pending, { world = world, event = key, endsAt = endsAt })

	self.log:info(string.format(
		"%s: %s for %ds.",
		WorldConfig.displayName(world),
		key,
		math.floor(endsAt - now)
	))
end

--[[ End whatever is running in `world`.

	The history entry is trimmed to the time it ACTUALLY ended rather than the time it was scheduled
	to. Those are the same for an event that ran its whole window and are NOT the same for one an
	admin stopped early, and the difference is exactly the window `couldHaveSpawned` would otherwise
	go on honouring claims in for minutes after the sky went back to normal. ]]
function WeatherService._close(self, world: number, now: number)
	local running = self._state[world]
	if not running then
		return
	end
	local history = self._history[world]
	local latest = history[#history]
	if latest and latest.event == running.event then
		latest.endsAt = math.min(latest.endsAt, now)
	end
	self._state[world] = nil
end

--[[ WHAT `world` SHOULD BE RUNNING AT `now`: the grid's answer, unless an admin has overridden it.

	Two overrides, and they are opposites of each other:

	  • `_manual[world]` is an event forced by hand, and it WINS until its own deadline. It is
	    cleared here rather than by a timer, so exactly one thing can end it.
	  • `_skip[world]` is a slot an admin STOPPED, remembered by slot index rather than as a boolean.
	    That distinction is the whole reason the index exists: a boolean would either need something
	    else to clear it (another timer) or would swallow the next event too, where a slot number
	    stops being equal to the current slot on its own, fifteen minutes later. ]]
function WeatherService._desired(self, world: number, now: number): { event: string, endsAt: number }?
	local manual = self._manual[world]
	if manual then
		if now < manual.endsAt then
			return manual
		end
		self._manual[world] = nil
	end

	local slot = WeatherConfig.scheduledAt(world, now)
	if not slot or self._skip[world] == slot.slot then
		return nil
	end
	return { event = slot.event, endsAt = slot.endsAt }
end

--[[ Bring one world's published state into line with what it should be. Idempotent, which is what
	lets the tick below stay a poll rather than a state machine: the overwhelmingly common answer is
	"already right", and that costs one comparison. ]]
function WeatherService._sync(self, world: number, now: number)
	local desired = self:_desired(world, now)
	local running = self._state[world]

	if running and desired and running.event == desired.event and math.abs(running.endsAt - desired.endsAt) < 1 then
		return
	end

	if running then
		self:_close(world, now)
	end
	if desired then
		self:_open(world, desired.event, desired.endsAt, now)
	end
end

--[[ One tick of every world's schedule. Polled rather than run off a chain of `task.delay`s per
	world, for the reason `TipsService._loop` gives in reverse: this is four independent timers that
	would all have to be cancellable together at teardown, and one poll is a great deal less to get
	wrong than four sleeping threads and their cancellation. With the grid it is less than that
	again — nothing is being timed at all, only read.

	Once a second is coarse because the thing it measures is minutes long: a second of slop on the
	end of a three-and-a-half-minute event is invisible, and `CLAIM_GRACE` covers it for the one
	thing that is not cosmetic.

	PUBLISH ONCE, THEN NOTIFY. Two worlds can change in the same tick — the offsets keep their
	scheduled windows apart, but nothing keeps a hand-forced event off a scheduled one — and the
	attribute is one string holding both, so writing it per world would hand the first client a state
	that is already out of date. ]]
function WeatherService._tick(self)
	local now = workspace:GetServerTimeNow()
	for _, world in self._worlds do
		self:_sync(world, now)
	end
	self:_publish()
	self:_flush()
end

-- === The admin override =====================================================

--- Say what happened, to the one panel that asked. Its own function so that every exit below is one
--- line and none of them can forget to answer.
function WeatherService._reply(self, player: Player, ok: boolean, message: string)
	self:getRemoteEvent(WeatherConfig.AdminEvent):Fire(player, ok, message)
end

--[[ The F2 panel's Weather tab, asking for an event by hand: start one, stop one, or roll the next
	one early. `WeatherConfig.AdminEvent` has the wire shape.

	THIS IS A REAL EVENT AND NOT A PREVIEW, and that is the whole point of routing it through here
	rather than letting the panel paint its own sky: it writes the state every client reads, fires
	the same chat broadcast a scheduled event fires, and — the part that matters — writes the same
	history window `couldHaveSpawned` bounds a payout against. What an admin tests with this is the
	shipping path, not a lookalike.

	Which is also why the admin check is HERE and re-done on every call, rather than being taken on
	trust from the panel that will not open for a non-admin: the panel is a client, its gate is a
	convenience, and this remote can otherwise be fired by anything with a network tab open to hand
	itself a five-minute thunderstorm and the x3.5 that rides on one.

	A REFUSAL FOR A NON-ADMIN IS SILENT. Every other failure answers with a sentence, because every
	other failure is an admin who needs to know why nothing happened; a stranger firing this gets
	nothing back that confirms the remote does anything at all. It is logged either way. ]]
function WeatherService._onAdmin(self, player: Player, action: unknown, world: unknown, key: unknown, seconds: unknown)
	if not Admins.isAdmin(player) then
		self.log:warn(string.format(
			"%s (%d) asked for weather '%s' and is not an admin.",
			player.Name,
			player.UserId,
			tostring(action)
		))
		return
	end

	--[[ Keyed by UserId rather than by the Player, so a rejoin does not leave the instance behind in
		here for the life of the server. It is one number per admin who has ever pressed a button. ]]
	local now = os.clock()
	if now < (self._adminAt[player.UserId] or 0) then
		-- Answered rather than dropped: a silent drop leaves the panel showing "asked..." for a press
		-- that never went anywhere, which reads as a broken remote rather than as a fast finger.
		self:_reply(player, false, "Too fast — try that again.")
		return
	end
	self._adminAt[player.UserId] = now + ADMIN_COOLDOWN

	--[[ Refused rather than honoured with the feature off, because `start` alone would not be enough
		to make it work: with `Enabled` false there is no tick loop to end the event, no controller
		bound to draw it and no mutation that would roll under it. It would be a string on the
		Workspace and nothing else, which is a worse answer than "no". ]]
	if not WeatherConfig.Enabled then
		self:_reply(player, false, "Weather is switched off in WeatherConfig — nothing is scheduled.")
		return
	end

	local index = WorldConfig.resolve(world)
	local name = WorldConfig.displayName(index)
	local now = workspace:GetServerTimeNow()
	local running = self._state[index]

	--[[ The window between this remote being bound (require time) and `start` building the per-world
		history that `_open` writes into. Nothing should be able to press a button inside it — the
		client bootstrapper waits on `ShardServerStarted` — but the failure if anything did would be
		an indexing error inside the schedule rather than a refusal, which is the wrong way to fail. ]]
	if not self._history[index] then
		self:_reply(player, false, "The schedule has not started yet.")
		return
	end

	if action == "stop" then
		if not running then
			self:_reply(player, false, string.format("%s has no weather to stop.", name))
			return
		end
		--[[ Both overrides are cleared, and both have to be. Dropping the manual event alone would
			leave the grid free to re-open the slot the manual one was covering on the very next
			tick; suppressing the slot alone would do nothing at all while a manual event outranks
			it. Between them they mean "nothing in this world until the next fifteen minutes". ]]
		self._manual[index] = nil
		self._skip[index] = WeatherConfig.slotAt(index, now)
		self:_close(index, now)
		self:_publish()

		self.log:info(string.format("%s stopped %s in %s.", player.Name, running.event, name))
		self:_reply(player, true, string.format("Stopped %s in %s.", running.event, name))
		return
	end

	local wanted: string?
	if action == "start" then
		local event = WeatherConfig.eventOf(key)
		if not event then
			self:_reply(player, false, string.format("No event named '%s'.", tostring(key)))
			return
		end
		wanted = event.Key
	elseif action == "roll" then
		wanted = self:_pick(index)
		if not wanted then
			self:_reply(player, false, "Nothing is rollable — every event is weighted to zero.")
			return
		end
	else
		self:_reply(player, false, string.format("Unknown action '%s'.", tostring(action)))
		return
	end

	--[[ Close the running one first rather than writing over it. `_close` trims its history entry to
		the second it actually stopped, which is the difference between an overwritten storm leaving
		a claim window open behind it and it closing when the sky changed. ]]
	if running then
		self:_close(index, now)
	end

	--[[ Clamped rather than trusted: `seconds` arrives off a remote, and a forced event writes the
		history window `couldHaveSpawned` reads — so "one second" and "the rest of the server's life"
		are both answers this must not accept. A press with no length gets the scheduled one. ]]
	local length = if type(seconds) == "number" and seconds == seconds
		then math.clamp(seconds, ADMIN_DURATION[1], ADMIN_DURATION[2])
		else WeatherConfig.Schedule.Duration

	--[[ Recorded as a MANUAL override rather than opened directly, so that `_desired` keeps agreeing
		with what is published. Opened directly it would be un-published by the very next tick, which
		would find the grid saying "clear" and dutifully take the admin's storm down again. ]]
	self._manual[index] = { event = wanted, endsAt = now + length }
	self._skip[index] = nil
	self:_open(index, wanted, now + length, now)
	self:_publish()
	self:_flush()

	self.log:info(string.format("%s started %s in %s by hand.", player.Name, wanted, name))
	self:_reply(player, true, string.format(
		"%s in %s for %ds.",
		WeatherConfig.eventOf(wanted).Name,
		name,
		math.floor(length + 0.5)
	))
end

-- === Public =================================================================

--- The event running in `world` right now, by key, or nil. The one question the rest of the server
--- ever asks about live weather.
function WeatherService.activeEventFor(self, world: unknown): string?
	local index = WorldConfig.resolve(world)
	local running = self._state[index]
	if not running then
		return nil
	end
	return if workspace:GetServerTimeNow() < running.endsAt then running.event else nil
end

--[[ Public (GetawayService): COULD this player have found this mutation on the road?

	THE ONLY CHECK STANDING BETWEEN A CLIENT AND A FIVE-TIMES PAYOUT. Traffic is client-sided, so
	nothing can verify that a particular car was mutated — see `WeatherConfig`'s trust note. What can
	be bounded is whether the road that player was driving was capable of producing it, and that is
	entirely a fact about this service's own schedule.

	Two ways to pass:

	  1. THE MUTATION SPAWNS NATURALLY. `AllowNatural` mutations turn up on a clear day by design, so
	     there is nothing to check and a claim costs the game what the roll was already worth.
	  2. ITS EVENT OVERLAPPED THE RUN. The window the player was driving in, widened by
	     `CLAIM_GRACE` at both ends, against every event this world has actually run.

	`since` is when the run began, in server time. A nil or nonsense value is treated as "the whole
	of the remembered history", which is the LENIENT reading and is chosen on purpose: the failure
	mode of a missing timestamp is a run that legitimately happened and cannot prove when, and
	refusing those would take real jackpots off real players to close a hole that `AllowNatural`
	already leaves half open. ]]
function WeatherService.couldHaveSpawned(self, world: unknown, mutationKey: unknown, since: number?): boolean
	local mutation = WeatherConfig.mutationOf(mutationKey)
	if not mutation then
		return false
	end
	if mutation.AllowNatural then
		return true
	end

	local index = WorldConfig.resolve(world)
	local now = workspace:GetServerTimeNow()
	local from = if type(since) == "number" and since == since and since > 0 then since else -math.huge
	from -= CLAIM_GRACE
	local to = now + CLAIM_GRACE

	for _, entry in self._history[index] or {} do
		-- Interval overlap, the honest way round: two windows miss each other only if one ends
		-- before the other starts.
		if entry.event == mutation.Event and entry.startedAt <= to and entry.endsAt >= from then
			return true
		end
	end
	return false
end

-- === Lifecycle ==============================================================

WeatherService:withLifecycle({
	init = function(self)
		self._state = {} :: { [number]: { event: string, endsAt: number } }
		self._history = {} :: { [number]: { { event: string, startedAt: number, endsAt: number } } }
		--- An event forced by the F2 panel, which outranks the grid until its deadline. See `_desired`.
		self._manual = {} :: { [number]: { event: string, endsAt: number } }
		--- A scheduled slot the panel STOPPED, by slot index. See `_desired` for why an index.
		self._skip = {} :: { [number]: number }
		--- Notices waiting to go out, so that every one of them lands after `_publish`. See `_flush`.
		self._pending = {} :: { { world: number, event: string, endsAt: number } }
		self._last = {} :: { [number]: string }
		self._worlds = {} :: { number }
		self._encoded = nil :: string?
		--- `UserId` -> the `os.clock()` before which that admin's next panel press is ignored.
		self._adminAt = {} :: { [number]: number }
		--[[ Its own `Random`, and it now seeds NOTHING that a player can see: the schedule is
			arithmetic (`WeatherConfig.scheduledAt`) and this is only the admin panel's Roll button.
			Kept unseeded so two admins rolling in two servers do not get the same event. ]]
		self._random = Random.new()
	end,

	start = function(self)
		--[[ The attribute is written even with the feature OFF, and written EMPTY. A client that
			joins a server where weather is disabled must find "no weather" rather than nothing at
			all: `WeatherController` treats a missing attribute as "not published yet" and keeps
			waiting, which would leave it holding whatever the last build left on the Workspace. ]]
		workspace:SetAttribute(WeatherConfig.Attribute, "")
		self._encoded = ""

		if not WeatherConfig.Enabled then
			self.log:info("Weather is switched off; no schedule is running.")
			return
		end

		for world in WorldConfig.Worlds do
			table.insert(self._worlds, world)
			self._history[world] = {}
		end

		--[[ THE FIRST TICK IS IMMEDIATE and it is not the same thing as the loop's first pass.

			The grid does not start when the server does — a server opening at 7 minutes past the
			quarter hour opens into the middle of world 2's event — so the attribute has to be right
			before the first player can read it rather than a second later. It also back-dates
			nothing: the history entry this writes starts NOW, so a claim is bounded by the part of
			the event this server actually saw. ]]
		self:_tick()

		--[[ A plain spawned loop with no teardown, and that is not an oversight: `Shard` services
			have `init` and `start` and no `stop` (see ShardService:withLifecycle), so a server-long
			schedule has nothing to be torn down BY. The pcall is what stands in for it — one bad
			tick logs and the schedule carries on, rather than the world's weather stopping forever
			because something threw once. ]]
		task.spawn(function()
			while true do
				task.wait(1)
				local ok, err = pcall(function()
					self:_tick()
				end)
				if not ok then
					self.log:warn(string.format("Weather tick errored: %s", tostring(err)))
				end
			end
		end)

		--[[ A player who joins mid-event gets the notice for whatever is running in THEIR world,
			once. Without it the feature is invisible to anybody who was not online at the moment it
			started, which for a three-and-a-half-minute event is most of the server.

			ONLY THEIR OWN WORLD, exactly as `_flush` does — the other three are on the world-select
			cards, and a join is the worst possible moment to open with a list of places you are not.
			Deferred a beat so their profile has loaded (the attribute is written on load) and their
			client has bound its own remote handler before we fire at it. ]]
		Players.PlayerAdded:Connect(function(player)
			task.delay(6, function()
				if player.Parent ~= Players then
					return
				end
				local world = player:GetAttribute(WorldConfig.WorldAttribute)
				local running = if type(world) == "number" then self._state[world] else nil
				if running and workspace:GetServerTimeNow() < running.endsAt then
					self:getRemoteEvent(WeatherConfig.StartedEvent):Fire(player, world, running.event, running.endsAt)
				end
			end)
		end)
	end,
})

return WeatherService
