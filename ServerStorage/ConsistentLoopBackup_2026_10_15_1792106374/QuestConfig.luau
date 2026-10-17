--[[
	QuestConfig
	-----------
	The daily quest board: three things to do today, a reward for each, and a clock. Claim one and it
	leaves the board, so the list is something a player empties rather than a list they scroll.

	=== 1. THE SET IS THE SAME FOR EVERYBODY, AND IT IS DERIVED FROM THE DATE ===================

	Today's three are `dailySet(dayIndex)` — a deterministic draw from `Catalogue` seeded on the UTC
	day number. Nobody's three are rolled for them and nothing about WHICH quests you got is stored,
	which is the whole reason this shape was picked over a per-player roll:

	  • There is no selection to save, so there is no selection to lose, migrate, or disagree with.
	    The profile stores PROGRESS and nothing else; the list itself is recomputed from the date on
	    every read, on both sides of the wire, forever.
	  • Two players can talk about today's quests. A daily that is different for everyone is a daily
	    nobody can help you with.
	  • Adding a quest to `Catalogue` changes what tomorrow draws and cannot corrupt what today is
	    already counting — the draw is by ID, and an ID that is no longer in the catalogue simply
	    stops being drawn.

	The cost is that a player who dislikes today's three waits a day. That is what a daily is.

	=== 2. EVERY TARGET IS SOMETHING THE SERVER ALREADY WATCHES ================================

	`Metrics` is the closed list of countable verbs, and each one is wired to a signal a service
	already fires — see `QuestService`'s header for the table of which. THERE IS NO CLIENT COUNTER
	ANYWHERE IN THIS FEATURE. That is a deliberate constraint on what may be a quest at all: a
	metric the server cannot see for itself does not go in this file, however good the quest would
	be, because the alternative is a remote whose whole payload is "trust me, I did the thing".

	`Dodge` is the one that had to be earned rather than found. Nothing in the game had ever
	counted an obstacle you got PAST — `ObstacleService` only ever hears about the ones you hit —
	so it is derived at settlement from the race seed and the distance driven, which the server
	owns both of (`ObstacleService.clearedFor`). The mockup asked for "Clear 10 obstacles" and this
	is that quest, with no new trust surface.

	=== 3. WHAT A QUEST IS =====================================================================

	One entry in `Catalogue`:

	    { Id = "steal_5", Metric = "Steal", Target = 5, Name = "Steal %s cars",
	      Unit = "count", Reward = 750 }

	`Name` is a FORMAT STRING and `Target` fills it in. Written that way so that retuning a target
	cannot leave the row lying about what it wants — a quest called "Steal 5 cars" with a target of
	8 is the kind of bug nobody looks for, and it is impossible to write here.

	`Id` IS STORED IN THE PROFILE and is the one field that must never be reused for a different
	quest. Progress is keyed by it. Renaming an ID is retiring one quest and adding another, which
	is fine and costs a day; POINTING an existing ID at a different target is what corrupts a day
	in flight.

	=== 4. THE CLOCK ===========================================================================

	`ResetPeriod` seconds, aligned to the UTC epoch rather than to when the player joined, so the
	board turns over for everyone at the same instant and the deadline is computable from `os.time()`
	alone on either side of the wire. That is what lets the page draw its own countdown without the
	server pushing one, and why the countdown survives a page left open, a rejoin and a server that
	never ticked. See the Quest page's header note 3.

	`QuestConfig.Enabled = false` takes the whole board out: no service, no counting, no claims. The
	page falls back to saying so rather than drawing a stale list.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)

local QuestConfig = {}

--- Master switch. Off = `QuestService` does not start, nothing is counted and the page is empty.
QuestConfig.Enabled = true

-- === The profile ============================================================

--[[ Where the day's progress lives. TOP-LEVEL, for the same reason `ReviveConfig.ProfileKey` and
	`OfflineConfig.ProfileKey` are: `PlayerProfile`'s string path is a recursive key search, so a
	key nested inside `Garage` would be reachable only by array path — and this is not a garage
	fact anyway.

	The table under it is `{ Day = <number>, Progress = { [id] = n }, Claimed = { [id] = true } }`.

	BOTH INNER TABLES ARE STRING-KEYED MAPS, which is the datastore rule `Garage.BayLevels` and
	`Garage.Levels` both document: quest IDs are names, so these round-trip through the save
	unchanged. `Day` is the UTC day number the other two belong to — see `_roll` in the service.

	Absent is a fresh board, so no profile written before this feature existed needs migrating. ]]
QuestConfig.ProfileKey = "Quests"

-- === The clock ==============================================================

--[[ How long a board lasts. A day, aligned to the UTC epoch (see header note 4).

	It is used as the denominator of the drain bar on the page as well as the length of the period,
	so shortening it for a test shortens both and the bar stays honest. ]]
QuestConfig.ResetPeriod = 24 * 60 * 60

--- Which day we are in. The seed for today's draw, and what the profile stores to know when the
--- board it is holding has expired.
function QuestConfig.dayIndex(now: number?): number
	return math.floor((now or os.time()) / QuestConfig.ResetPeriod)
end

--- When today's board turns over, as an `os.time()`. The page counts down to this.
function QuestConfig.resetAt(now: number?): number
	return (QuestConfig.dayIndex(now) + 1) * QuestConfig.ResetPeriod
end

-- === The countable verbs ====================================================

--[[ The closed list of things a quest may ask for. Every one is wired to a signal the server
	already fires; `QuestService`'s header has the table of which signal feeds which.

	The VALUE is what one unit of the metric means, and it is here rather than in the catalogue
	because it is a property of the verb and not of any one quest: two quests counting `Collect`
	must agree that it is measured in dollars. ]]
QuestConfig.Metrics = {
	Steal = "cars stolen off the road, mid-run",

	--[[ Cars driven into the getaway truck. BANKING A CAR AND GETTING AWAY ARE ONE EVENT in this
		game — the truck is what ends a run successfully, and you bring exactly one car to it — so
		there is one metric and not two, however differently a quest chooses to word it. It is fed
		from `RewardService.RunSettled(banked = true)` rather than from `GarageService.CarParked`,
		because that signal also fires when the DEALERSHIP screen moves a car onto a bay, which is
		not a bank and must not count as one. ]]
	Bank = "cars driven into the getaway truck",

	Dodge = "obstacles passed without hitting them",
	Distance = "studs driven, over any number of runs",
	Race = "runs finished, however they ended",
	Collect = "dollars taken off the collect mats",
	Customer = "customers served on the forecourt",
	--[[ Dollars customers tipped (`CustomerService.CustomerPaid`'s amount). THE LOT'S MONEY QUEST SINCE
		2026-09-28, when the mats stopped paying and `Collect` could never move again — see the two
		`Group = "lot"` rows below, which swap on `GarageConfig.Income.Passive`. ]]
	Tips = "dollars customers tipped on the forecourt",
}

function QuestConfig.isMetric(metric: unknown): boolean
	return type(metric) == "string" and QuestConfig.Metrics[metric] ~= nil
end

-- === Formatting =============================================================

--[[ 12345 -> "12,345". Used for every target and every progress figure that is not cash.

	Grouped rather than raw because the distance quests run to five digits and "Progress: 18450/30000"
	is a number nobody reads. The gsub loop is the standard one; it walks right to left until a pass
	changes nothing. ]]
function QuestConfig.formatCount(amount: number): string
	local text = tostring(math.floor(math.max(0, tonumber(amount) or 0)))
	local runs
	repeat
		text, runs = string.gsub(text, "^(-?%d+)(%d%d%d)", "%1,%2")
	until runs == 0
	return text
end

--[[ One number, in the unit its quest counts. `cash` goes through the project's own formatter so a
	quest about money reads the same as the number on a collect mat. ]]
function QuestConfig.formatAmount(amount: number, unit: string?): string
	if unit == "cash" then
		return GarageConfig.formatCash(amount)
	end
	return QuestConfig.formatCount(amount)
end

--- The row's headline: the quest's own `Name` with its target filled in.
function QuestConfig.describe(spec: QuestSpec): string
	return string.format(spec.Name, QuestConfig.formatAmount(spec.Target, spec.Unit))
end

-- === The catalogue ==========================================================

--[[ Everything a day can draw from.

	SIZED SO THAT CONSECUTIVE DAYS LOOK DIFFERENT. Twelve entries drawing three means a day shares on
	average well under one quest with the day before it, which is variety without a board that feels
	random. Adding entries is safe at any time (see header note 1); the only rule is that an `Id`
	is never reused for a different quest.

	The spread across metrics is deliberate and is the actual design here: two of the three are
	things you do on the ROAD and one is something you do in the LOT. A board that is three driving
	quests is a board a player who logged in to collect their money cannot touch, and vice versa —
	so the draw is stratified rather than uniform. See `dailySet`.

	REWARDS are flat cash, and small on purpose relative to a lot's income: a day's board pays
	roughly what a mid-game lot earns in a minute or two. Quests here are a reason to do the
	thing, not an income stream — the lot is the income stream, and a board that out-earns it would
	quietly turn the game into a chore list. ]]
export type QuestSpec = {
	Id: string,
	Metric: string,
	Target: number,
	Name: string, -- a format string; `%s` is the formatted target
	Unit: string?, -- "count" (default) or "cash"
	Reward: number, -- cash
	Group: string, -- "road" | "lot" — what the stratified draw uses; see `dailySet`
}

QuestConfig.Catalogue = {
	-- === On the road ========================================================
	{ Id = "steal_5", Metric = "Steal", Target = 5, Name = "Steal %s cars", Reward = 750, Group = "road" },
	{ Id = "steal_12", Metric = "Steal", Target = 12, Name = "Steal %s cars", Reward = 2000, Group = "road" },
	{ Id = "bank_3", Metric = "Bank", Target = 3, Name = "Bank %s cars", Reward = 2500, Group = "road" },
	-- Same metric as `bank_3`, worded the other way round — see the note on `Metrics.Bank`.
	{ Id = "getaway_5", Metric = "Bank", Target = 5, Name = "Get away %s times", Reward = 3000, Group = "road" },
	--[[ MEASURED OFF THE LAYOUT, NOT GUESSED — and the measurement is the interesting part.

		OBSTACLE DENSITY RISES WITH DISTANCE, because `ObstacleConfig.Tiers` hands later tiles busier
		course pools. It is not a constant you can multiply, which is the trap these two targets were
		first set in. Counted off `ObstacleLayout` itself, averaged over six seeds on world 1:

		     3,000 studs ->   14 obstacles     20,000 studs ->  245
		     6,000 studs ->   44               30,000 studs ->  395
		    10,000 studs ->   93               40,000 studs ->  550
		    15,000 studs ->  169               60,000 studs ->  855

		So 150 is about 13,500 studs and 400 is about 30,000 — deliberately alongside the two
		distance quests below, meaning roughly the same amount of driving. The difference is that
		hitting things costs you here and does not there, which is the whole point of a dodge quest.

		The first draft said 25 and 60, which a player cleared inside 2,300 studs without noticing
		they had a quest. If the course density is ever retuned, re-derive against `ObstacleLayout`
		rather than nudging these. ]]
	{ Id = "dodge_150", Metric = "Dodge", Target = 150, Name = "Dodge %s obstacles", Reward = 1200, Group = "road" },
	{ Id = "dodge_400", Metric = "Dodge", Target = 400, Name = "Dodge %s obstacles", Reward = 3000, Group = "road" },
	{ Id = "drive_15k", Metric = "Distance", Target = 15000, Name = "Drive %s studs", Reward = 1500, Group = "road" },
	{ Id = "drive_40k", Metric = "Distance", Target = 40000, Name = "Drive %s studs", Reward = 4000, Group = "road" },
	{ Id = "race_6", Metric = "Race", Target = 6, Name = "Finish %s runs (500+ studs)", Reward = 900, Group = "road" },

	-- === In the lot =========================================================
	{ Id = "collect_10k", Metric = "Collect", Target = 10000, Name = "Collect %s", Unit = "cash", Reward = 1000, Group = "lot" },
	{ Id = "collect_50k", Metric = "Collect", Target = 50000, Name = "Collect %s", Unit = "cash", Reward = 3500, Group = "lot" },
	--[[ The same two rungs, counted in tips. Same targets on purpose: the tip is sized so a lot's
		crowd earns in the region its podiums used to (`CustomerConfig.Tip`), so $10k of tips is about
		the afternoon $10k of collecting was, and the rewards need no re-deriving. NEW IDS rather than
		the old ones re-pointed, so a board drawn before the change keeps its collect quests as retired
		ids (`byId` answers nil) instead of silently re-counting them in a different verb. ]]
	{ Id = "tips_10k", Metric = "Tips", Target = 10000, Name = "Earn %s in tips", Unit = "cash", Reward = 1000, Group = "lot" },
	{ Id = "tips_50k", Metric = "Tips", Target = 50000, Name = "Earn %s in tips", Unit = "cash", Reward = 3500, Group = "lot" },
	{ Id = "customers_20", Metric = "Customer", Target = 20, Name = "Receive %s tips", Reward = 1400, Group = "lot" },
} :: { QuestSpec }

--[[ Dodge quests are disabled while roads have only traffic; restore them when obstacles return.
	Exactly one of the two money verbs is live, by `GarageConfig.Income.Passive`: a quest counting
	a verb that can no longer happen is a quest that can never be finished, which is worse than no
	quest. Filtered once, at load, so the board never draws the dead pair. ]]
do
	local dead = if GarageConfig.Income.Passive then "Tips" else "Collect"
	for index = #QuestConfig.Catalogue, 1, -1 do
		if QuestConfig.Catalogue[index].Metric == dead or QuestConfig.Catalogue[index].Metric == "Dodge" then
			table.remove(QuestConfig.Catalogue, index)
		end
	end
end

--- One entry by id, or nil for an id that has been retired out of the catalogue.
function QuestConfig.byId(id: unknown): QuestSpec?
	if type(id) ~= "string" then
		return nil
	end
	for _, spec in QuestConfig.Catalogue do
		if spec.Id == id then
			return spec
		end
	end
	return nil
end

-- === Today's three ==========================================================

--[[ How many quests a board holds. THREE, and the number is a finishability decision rather than a
	layout one: a claimed quest LEAVES the board (see `AllClaimedText` and the page's `_outroRow`),
	so the list is something a player empties rather than a list they scroll. Four was what the
	mockup drew and it was one more than anybody cleared in a session, which left every board
	looking half-done at logout. Three is a set a good session finishes.

	The well shows about two and a bit rows, so a full board still scrolls by one — which is what
	keeps the scroll indicator a real thing rather than decoration — and the moment the first quest
	is claimed the remaining two fit with nothing cut off. ]]
QuestConfig.DailyCount = 3

--[[ The guaranteed split. Two road quests and one lot quest, so no board is unplayable for
	somebody who only came to do one of the two things this game is.

	The numbers must sum to `DailyCount` or the remainder is drawn from everything, which is a
	silent softening of the rule rather than a break — see `dailySet`. ]]
QuestConfig.DailyGroups = {
	road = 2,
	lot = 1,
}

--[[ Draw `count` distinct entries out of `pool`, deterministically, using `rng`.

	A partial Fisher-Yates over a COPY of the pool. Copied because the pool is a slice of the
	catalogue and shuffling the catalogue in place would make the next call's answer depend on this
	one — the exact thing "deterministic from the day index" must not do. ]]
local function drawFrom(pool: { QuestSpec }, count: number, rng: Random): { QuestSpec }
	local bag = table.clone(pool)
	local drawn = {}
	for _ = 1, math.min(count, #bag) do
		local pick = rng:NextInteger(1, #bag)
		table.insert(drawn, bag[pick])
		-- Swap-remove: the order of what is left does not matter, only that it stays deterministic.
		bag[pick] = bag[#bag]
		bag[#bag] = nil
	end
	return drawn
end

--[[ Today's board, as catalogue entries in a stable order.

	DETERMINISTIC FROM THE DAY ALONE, which is what lets the server and the page agree without the
	list ever being sent — and what lets a server that restarts mid-day serve the same four it was
	serving before it went down.

	STRATIFIED BY GROUP first (see `DailyGroups`), then topped up from whatever is left if the
	groups could not fill the board — a catalogue edited down to two lot quests must still produce
	four rows rather than three. The final sort is by ID so the rows land in the same order for
	everybody, rather than in the order the draw happened to produce.

	`Random.new(day)` rather than a hash of it: the seed only has to be the same everywhere, not
	unpredictable. Nobody gains anything by knowing tomorrow's quests. ]]
function QuestConfig.dailySet(dayIndex: number?, distinctMetrics: boolean?): { QuestSpec }
	local day = dayIndex or QuestConfig.dayIndex()
	local rng = Random.new(day)

	local byGroup: { [string]: { QuestSpec } } = {}
	for _, spec in QuestConfig.Catalogue do
		local group = byGroup[spec.Group] or {}
		table.insert(group, spec)
		byGroup[spec.Group] = group
	end

	local drawn: { QuestSpec } = {}
	local taken: { [string]: boolean } = {}

	--[[ Groups are walked in a FIXED ORDER, not in `pairs` order. `DailyGroups` is a dictionary and
		Lua's iteration order over one is not defined — draw in a different order and the same day
		produces a different board on a different machine, which is the one property this whole
		function exists to have. ]]
	local groupNames = {}
	for name in QuestConfig.DailyGroups do
		table.insert(groupNames, name)
	end
	table.sort(groupNames)

	for _, name in groupNames do
		for _, spec in drawFrom(byGroup[name] or {}, QuestConfig.DailyGroups[name], rng) do
			table.insert(drawn, spec)
			taken[spec.Id] = true
		end
	end

	if #drawn < QuestConfig.DailyCount then
		local rest = {}
		for _, spec in QuestConfig.Catalogue do
			if not taken[spec.Id] then
				table.insert(rest, spec)
			end
		end
		for _, spec in drawFrom(rest, QuestConfig.DailyCount - #drawn, rng) do
			table.insert(drawn, spec)
		end
	end

	-- Existing boards retain their original draw; fresh boards opt into varied objectives.
	if distinctMetrics then
		local used = {}
		for i, spec in drawn do
			if used[spec.Metric] then
				local alternatives = {}
				for _, candidate in QuestConfig.Catalogue do
					if candidate.Group == spec.Group and not used[candidate.Metric] and not taken[candidate.Id] then
						table.insert(alternatives, candidate)
					end
				end
				if #alternatives > 0 then
					local replacement = alternatives[rng:NextInteger(1, #alternatives)]
					drawn[i] = replacement
					taken[replacement.Id] = true
					spec = replacement
				end
			end
			used[spec.Metric] = true
		end
	end

	table.sort(drawn, function(a, b)
		return a.Id < b.Id
	end)
	return drawn
end

-- === The screen =============================================================

--[[ `PageName` is the screen: the module under `UIController/Pages` and the Frame under
	`MainUI.Pages`, which have to agree.

	`StateEvent` is how `QuestController` tells that page a new board has arrived — the same
	Dispatcher pattern `WorldConfig.StateEvent` uses, and for the same reason: the page redraws off
	an event rather than polling, and the controller does not need to know the page exists. ]]
QuestConfig.PageName = "Quest"
QuestConfig.StateEvent = "QuestBoard"

-- === The tabs ===============================================================
--[[ The kit's four category buttons (V2 page only), left to right, and which of them has a board.

	ONLY DAILY IS LIVE. Dylan wanted the strip back ahead of the boards (2026-09-16): Weekly, Monthly
	and All Time can be pressed and say `ComingSoonText`, with the clock hidden, because there is no
	deadline for a clock to count down to. Giving one a real board is `Live = true` plus a service
	that sends it.

	`Button` is the kit's instance name under `Main.CategoryBtns`. The caption is the kit's own
	`Title` on that button, so it is not repeated here. ]]
QuestConfig.Tabs = {
	{ Id = "Daily", Button = "DailyBtn", Live = true },
	{ Id = "Weekly", Button = "WeeklyBtn", Live = false },
	{ Id = "Monthly", Button = "MonthlyBtn", Live = false },
	{ Id = "AllTime", Button = "AllTimeBtn", Live = false },
}

--- The tab the page opens on, every time it opens.
QuestConfig.DefaultTab = "Daily"

--[[ What an unpicked tab's face is multiplied by. The kit gives each tab its own colour and draws no
	picked state, so the picked tab keeps the artist's colour and the other three go darker. The face
	is a white fill under a `UIGradient`, and a gradient multiplies the fill, so each tab keeps its
	own hue on the way down. ]]
QuestConfig.TabDimColor = Color3.fromRGB(150, 150, 150)

--- The tabs table as a lookup by `Id`.
function QuestConfig.tabOf(id: unknown)
	for _, tab in QuestConfig.Tabs do
		if tab.Id == id then
			return tab
		end
	end
	return nil
end

-- === Copy ===================================================================
--[[ Everything the page says that is not a quest name. Here rather than in the page for the usual
	reason: these are sentences somebody who is not me will want to rewrite, and none of them should
	need a diff of a layout file to find. ]]

--- The countdown along the bottom of the page. `%s` is the formatted remainder.
QuestConfig.TimeLeftFormat = "Time Left: %s"

--- The row's progress caption. `%s` is done, then target — both already formatted for their unit.
QuestConfig.ProgressFormat = "Progress: %s/%s"

--- What the pill says in each of its three states. See the page's `PILL_STATE` for the colours.
QuestConfig.InProgressText = "IN-PROGRESS"
QuestConfig.ClaimText = "CLAIM"
QuestConfig.ClaimedText = "CLAIMED"

--- What the list says when there is nothing to draw — the board off in config, or a client that
--- has not been sent one yet. Never seen in a normal session.
QuestConfig.EmptyText = "No quests today"

--[[ What the list says once every quest on it has been claimed, which IS a normal session and is the
	whole reason a claimed card leaves the board: an empty list with nothing written on it reads as
	something that failed to load, and a board you finished should say so.

	A SEPARATE STRING FROM `EmptyText` because the two are different facts. "No quests today" is the
	server having nothing to give; this is the player having taken all of it, and it is the only one
	of the two that is worth feeling good about. The page picks between them by whether the board it
	was sent had any quests on it at all — see `_updateEmptyState`. ]]
QuestConfig.AllClaimedText = "All quests claimed! Come back tomorrow."

--- What a tab with no board behind it says (see `Tabs`).
QuestConfig.ComingSoonText = "Coming soon!"

-- === Claiming ===============================================================

--[[ The beats of a claim, in seconds and multiples. `Quest`'s `_outroRow` and `_flyReward` are the
	mechanism; this is the tuning, and it is here for the same reason the copy above is: it is the
	part somebody will want to dial without reading a layout file.

	WHAT IT IS. The reward chip's banknote leaves the card and flies to the cash counter in the
	corner, and the card itself pops once and then folds away, taking its row with it so the list
	closes up behind it. Restrained on purpose, per the house note on effect intensity: one note and
	not a spray, and the whole thing is over in about three quarters of a second.

	THE FLIGHT IS THE ONLY PART THAT IS NOT LITERAL. The money landed in the profile before the
	board that triggered this even reached the client, so the counter has usually finished rolling
	by the time the note arrives — the note is the *explanation* of a number that already moved, not
	its cause. That is why the flight is short and why nothing waits on it. ]]
QuestConfig.ClaimEffect = {
	-- The banknote's flight, corner to corner. `Lift` is how far above the straight line the arc
	-- bows, as a fraction of the distance travelled: it is what makes the note lob rather than
	-- slide, and it is a fraction so a claim on a phone arcs like a claim on a monitor.
	FlightTime = 0.5,
	Lift = 0.28,
	-- The note leaves the chip bigger than it sat in it and arrives small, which reads as depth
	-- without a single extra instance.
	FlightStartScale = 1.35,
	FlightEndScale = 0.55,

	--[[ The card's own beats. It punches first (the press landed), holds a moment so the punch is
		legible, then folds: the card fades and shrinks in place, and the ROW's height collapses
		under it so everything below slides up into the space.

		`HoldTime` IS ALSO HOW LONG THE REWARD CHIP SITS EMPTY, because the note leaves on the press
		and the chip is not repainted after it. A short beat reads as "you took it"; a long one
		reads as a missing image. It is the one number here that should not be raised without
		looking at the screen. ]]
	PunchTime = 0.12,
	PunchScale = 1.04,
	HoldTime = 0.1,
	FadeTime = 0.24,
	FadeScale = 0.86,
	CollapseTime = 0.2,
}

QuestConfig.MinRunStuds = 500
QuestConfig.TipMinutes = { tips_10k = 5, tips_50k = 15 }

return QuestConfig
