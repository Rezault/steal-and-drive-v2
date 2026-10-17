--[[
	LeaderboardConfig
	-----------------
	The world board's catalogue: which stats are ranked, what each tab is called, and how a raw
	number becomes the string on a row.

	=== 1. ONE SNAPSHOT, EVERY TAB =============================================================

	`LeaderboardService` polls all six boards on one timer and broadcasts them together, keyed by
	`Key`. So switching tab is a LOCAL operation — the client already holds every board and draws a
	different one, with no remote, no spinner and no round trip. That is the whole reason the boards
	are declared in a shared file rather than server-side: the tab strip, the page it reveals and the
	rows in it are all derived from this list, so adding a board is one entry here plus (if it needs
	a counter that does not exist yet) one line in the service.

	`Key` IS THE BINDING CONTRACT. It is the snapshot key, and it is what the authored page Frame and
	its tab button must be NAMED on the imported board's SurfaceGui. Renaming one means renaming all
	three.

	=== 2. WHAT MAY BE A BOARD =================================================================

	Same constraint `QuestConfig` puts on a quest: a board ranks something the SERVER already knows
	for its own reasons. There is no leaderboard remote a client can submit a score to — the only
	thing a client may send is "my board exists, send me the snapshot".

	Four of the six read a number the profile already stores (`Path`, an array path). Two are
	`Derived` — computed from profile state that is not a scalar, by a named reader in the service.
	The rest are lifetime counters the service itself keeps; see `Stats` below.

	=== 3. TWO OF THESE ARE NOT ALL-TIME, AND THAT IS THE CHOICE =============================

	`Cars`, `Value`, `Distance`, `Steals` and `Time` only ever go up, so those five boards are a
	record of what somebody has done and a name leaves the top of one only by being passed.

	`Cash` IS A BALANCE, NOT A TOTAL. It falls every time the player buys an upgrade, so the richest
	board ranks hoarding as much as earning and a player can drop off it by playing well. That is a
	known and accepted property — it is the number players actually compare, and "cash ever earned"
	is a stat nothing in this game stores today. If it ever wants to be a true all-time board, add an
	`Earned` counter to `Stats` and repoint `Path`; the ordered store's `_vN` suffix is how the old
	rankings get thrown away when that happens.

	=== 4. THE STORE NAMES ARE VERSIONED ======================================================

	`Store` ends in `_vN`. Bump it to wipe a board that has bad data in it — a rank written by a
	broken encode, or a stat whose meaning changed. The service also appends the dev/prod suffix
	(`Data:GetSuffix()`), exactly as the profile keys do, so a Studio playtest can never write into
	the live rankings.

	=== 5. FORMATTING HAPPENS HERE, ON THE CLIENT =============================================

	The service sends RAW NUMBERS and the board formats them through `LeaderboardConfig.format`.
	Written that way round on purpose: the payload is smaller, and the wording of a row can change
	without a server deploy, in the one file that also owns the tab it sits under.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)

local LeaderboardConfig = {}

--- Master switch. False = `LeaderboardService` does not start: nothing is counted, nothing is
--- ranked and the board draws whatever its "no data" state is.
LeaderboardConfig.Enabled = true

-- === The lifetime counters ==================================================

--[[ Where the counters this feature had to invent live: a TOP-LEVEL `Stats` table on the profile.

	    Stats = { Steals = 0, Distance = 0, TimePlayed = 0 }

	Nested rather than three top-level keys, unlike `ExtraLives` / `LastSeen` / `World`, and it is
	worth knowing why the template's usual advice is being declined here. That advice exists because
	`PlayerProfile:Get(string)` is a RECURSIVE KEY SEARCH, so a nested key is reachable only by array
	path — and these are only ever read by array path anyway, from one file. What the grouping buys
	is that `Distance` and `Steals` are exactly the sort of generic names another feature will one
	day want somewhere else in this template, and a recursive search that finds the wrong `Distance`
	is a bug with no error in it.

	THESE ARE LIFETIME AND MONOTONIC. Nothing decrements them, nothing resets them at midnight (that
	is `Quests`), and they are not the same numbers as any of the daily metrics — a quest counts what
	you did today, these count what you have ever done.

	Absent is zero, so no profile written before this feature existed needs migrating; those players
	simply start accruing from their next steal, run and session. ]]
LeaderboardConfig.ProfileKey = "Stats"

--[[ The counter names, so nothing spells one out twice. The VALUE is what one unit means, in the
	same spirit as `QuestConfig.Metrics` — two things writing `Distance` have to agree it is studs. ]]
LeaderboardConfig.Stats = {
	Steals = "cars stolen off the road, ever",
	Distance = "studs driven, over every run ever",
	TimePlayed = "seconds spent in the game, over every session",
}

-- === Cadence ================================================================

--[[ How often every online player's stats are written into the ordered stores. Slow on purpose:
	this is six `SetAsync` calls per player per tick, and a rank that is two minutes stale is a rank
	nobody can tell is stale. ]]
LeaderboardConfig.WriteInterval = 120

--- How often the top-N is polled back and broadcast. One `GetSortedAsync` per board per tick.
LeaderboardConfig.ReadInterval = 60

--[[ How many rows a board holds. This is the payload size AND the number of usernames that have to
	be resolved, so it is the one knob worth thinking about before raising: the service batches name
	lookups through `UserService`, but 100 rows across six boards is still up to 600 ids on a cold
	server. 50 is a board somebody might actually scroll to the bottom of.

	Hard ceiling is 100 — `GetSortedAsync` will not return a larger page. ]]
LeaderboardConfig.TopN = 50

-- === The boards =============================================================

--[[ One entry per tab, in tab order.

	  Key      the snapshot key, AND the name the authored page Frame and its tab button must carry
	  Title    the heading drawn on the page, exactly as written here
	  Short    the tab button's label
	  Store    OrderedDataStore name; `_vN` is the wipe lever (header note 4)
	  Unit     how `format` turns the stored number into the string on the row
	  Path     array path into the profile, for a stat the profile already stores
	  Derived  name of a reader in `LeaderboardService.READERS`, for a stat that is not a scalar

	`Path` and `Derived` are alternatives — an entry has exactly one. ]]
LeaderboardConfig.List = {
	{
		Key = "Cash",
		Title = "RICHEST",
		Short = "Cash",
		Store = "LB_Cash_v1_R20261014_01",
		Unit = "cash",
		Path = { "Cash" },
	},
	{
		--[[ HOW MANY OF THE ROSTER THEY HAVE, not how many cars they have taken — that is `Steals`
			below, and the two are deliberately different boards. `Garage.Owned` holds one entry per
			(body, colour), so the count here is of DISTINCT BODIES: four colours of one Camaro is one
			car on this board, which is the same thing the Index page's "{found}/{total} Stolen"
			counts. A leaderboard that disagreed with the player's own collection screen would read as
			a bug whichever number was right. ]]
		Key = "Cars",
		Title = "BIGGEST COLLECTION",
		Short = "Cars",
		Store = "LB_Cars_v1_R20261014_01",
		Unit = "count",
		Derived = "Collection",
	},
	{
		--[[ WHAT THE COLLECTION IS WORTH, which is a different question from the board above it and
			will read as a much larger number. `Cars` counts distinct BODIES; this values every CAR
			KEY, so a player with four colours of one Camaro is one car up there and four cars' money
			down here. `GarageConfig.valueOfCollection` is the sum and carries the full reasoning.

			IT IS NOT A BALANCE, unlike `Cash` — nothing a player buys reduces it, and selling a
			duplicate cannot (a duplicate was never in `Owned` to begin with). So this is the
			all-time wealth board `Cash` deliberately is not; header note 3 has that distinction.

			SAT NEXT TO `Cars` RATHER THAN APPENDED, because the two are both about the collection and
			a tab strip that separated them would be sorted by nothing. Position is only position: the
			page and the tab are bound by `Key`, so this reordered nothing — but the strip is six wide
			now, which is worth knowing before the board is authored. ]]
		Key = "Value",
		Title = "MOST VALUABLE",
		Short = "Value",
		Store = "LB_Value_v1_R20261014_01",
		Unit = "cash",
		Derived = "Value",
	},
	{
		Key = "Distance",
		Title = "MOST DRIVEN",
		Short = "Distance",
		Store = "LB_Distance_v1_R20261014_01",
		Unit = "distance",
		Path = { "Stats", "Distance" },
	},
	{
		Key = "Steals",
		Title = "MOST STEALS",
		Short = "Steals",
		Store = "LB_Steals_v1_R20261014_01",
		Unit = "count",
		Path = { "Stats", "Steals" },
	},
	{
		Key = "Time",
		Title = "MOST PLAYED",
		Short = "Time",
		Store = "LB_TimePlayed_v1_R20261014_01",
		Unit = "duration",
		Path = { "Stats", "TimePlayed" },
	},
}

-- === The board in the world =================================================

--[[ The physical board: what the `BuildLeaderboardBoard` command authors and what
	`LeaderboardController` binds. These names are the contract between those two files, exactly as
	`PlotConfig.Sign*` is between `BuildDealershipSigns` and `PlotService` — renaming one here means
	renaming it in both.

	=== THE BOARD IS ART. ONLY WHAT IS ON IT IS BUILT. =========================================

	It used to be two Parts the command stood up itself. Since 2026-08-26 it is the modeller's model
	— a stone-footed timber frame around a white backing plane — and the command only dresses its
	plate. Two things follow, and both of them are why the names below are worth reading before
	touching the board:

	  * THE PLATE IS PORTRAIT (roughly 19.6 x 26.6 studs, against the old 30 x 15). Six tabs across
	    that would be six slivers, so the strip WRAPS over `TabColumns` — two rows of three today.
	  * THERE IS NO PANEL FILL TO AUTHOR. The art's backing plane is the background, so `Panel` and
	    every page under it are transparent and the rows are translucent cards over the art.

	=== THE PAGES AND TABS ARE NAMED BY `Key`, NOT LISTED HERE =================================

	Header note 1 says it: a page Frame is named for the board it draws and so is its tab button. So
	there is no `PageNames` table below and there must never be one — the moment the page names live
	somewhere other than `List`, adding a board means editing two lists that can disagree, and the
	symptom is a tab that switches to nothing.

	=== TWO FACES, ONE STATE ===================================================================

	The board stands in the middle of the roundabout with plots on both sides of it, so the plate
	carries a SurfaceGui on its Front AND its Back — otherwise half the map reads the back of a
	billboard. The controller binds every SurfaceGui under the tagged Model and drives them from one
	selected tab, so the two faces can never disagree and a tab pressed on either one moves both. ]]
LeaderboardConfig.Board = {
	--- CollectionService tag on the board Model. The controller finds it by this and nothing else.
	Tag = "LeaderboardBoard",

	--- What the art model is renamed to once it has been dressed, and where it is moved to.
	ModelName = "LeaderboardBoard",

	--[[ The plate the SurfaceGuis sit on: the framed panel inside the timber, NOT the white backing
		plane behind it and not one of the posts. The command renames whichever part it finds to this
		on the first run, so on an imported model it is a name that does not exist yet — see its
		"WHICH PART IS THE PLATE" note for how it works that out. ]]
	ScreenName = "Screen",

	--[[ The SurfaceGuis, one per face, named `GuiName .. face`: `BoardFront`, `BoardBack`.

		LISTED RATHER THAN DISCOVERED, and that is not fussiness. The controller used to find faces by
		sweeping the plate's children for SurfaceGuis, which loses a face to the exact race its own
		header warns about — a tagged Model arrives before its descendants replicate, so a sweep run
		on the first frame can see one gui, or none, and bind a board that is half dead. Named faces
		can be waited for individually.

		The strings are `Enum.NormalId` names, because that is what the command builds each one on. ]]
	GuiName = "Board",
	Faces = { "Front", "Back" },

	PanelName = "Panel",
	TitleBarName = "TitleBar",
	TitleName = "Title", -- reads the ACTIVE board's `Title`
	TabsName = "Tabs",
	PagesName = "Pages",

	--[[ How many tabs a row of the strip holds; the strip wraps to as many rows as that needs.

		THREE, BECAUSE THE PLATE IS PORTRAIT. Six tabs in one row across a 19.6-stud board is a strip
		of slivers with "Distance" shrunk to nothing in one of them; two rows of three are targets you
		can read and hit from across the roundabout. It is derived, not listed: the command computes
		the rows and the cell height off `#List`, so a seventh board becomes three rows of three
		rather than one tab hanging off the bottom of the strip. ]]
	TabColumns = 3,

	--[[ The refresh bar under the rows, from the modeller's own mockup: a trough with a `Fill` that
		empties over `ReadInterval` and refills when a snapshot lands.

		CUT WITH A GRADIENT, NOT RESIZED — `TimerRampName` is the UIGradient on the fill and the
		controller writes its `Offset`. A rounded fill sized in scale flattens its own corners as it
		shrinks and leaks past the ends of the trough; the pill bars needed the same fix. ]]
	TimerName = "Timer",
	TimerFillName = "Fill",
	TimerRampName = "Ramp",

	--[[ Inside one page: `RowsShown` row Frames named `Row1`..`RowN`, plus one label that stands in
		for the lot of them when the board has nothing to rank. ]]
	RowName = "Row",
	EmptyName = "Empty",

	-- Inside one row.
	RankName = "Rank",
	HeadshotName = "Headshot",
	PlayerName = "PlayerName",
	AmountName = "Amount",

	--[[ How many rows the board actually draws, out of the `TopN` the server sends.

		TEN, AND NOT `TopN`. This is a sign read on foot from a few studs away, not a screen anybody
		scrolls: a scrolling frame on a SurfaceGui has to be dragged with the mouse ray and is
		miserable, and 50 rows at a readable type size would be a board four storeys tall. The
		snapshot still carries all 50 — raising this draws more of what already arrives, with no
		server change. ]]
	RowsShown = 10,

	--- Shown in place of the rows when a board has nobody on it. A fresh universe, mostly.
	EmptyText = "NO RANKINGS YET",

	--[[ `rbxthumb` resolves client-side with no web call and does not yield — the same source the
		dealership sign uses, and the reason `Row.Id` is on the wire at all. ]]
	HeadshotFormat = "rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150",
}

--[[ The medal colours for the first three rows, then everybody else.

	ON THE RANK NUMBER AND NOT THE ROW, deliberately: a gold ROW would make the top entry a different
	kind of object from the rest of the list, and the eye then reads the board as "the winner, and
	some other stuff". Colouring the numeral keeps one list with three notable positions in it. ]]
LeaderboardConfig.RankColors = {
	Color3.fromRGB(255, 197, 61), -- gold
	Color3.fromRGB(200, 210, 232), -- silver
	Color3.fromRGB(208, 139, 74), -- bronze
}
LeaderboardConfig.RankColor = Color3.fromRGB(168, 179, 208) -- #A8B3D0, the kit's muted copy

--- Rank -> its colour. Anything past the podium is the muted one.
function LeaderboardConfig.rankColor(rank: number): Color3
	return LeaderboardConfig.RankColors[rank] or LeaderboardConfig.RankColor
end

--- Key -> entry, with a 1-based `Order` stamped on so the tab strip and the page carousel agree
--- about position without either of them counting the list itself.
LeaderboardConfig.ByKey = {}
for index, board in LeaderboardConfig.List do
	board.Order = index
	LeaderboardConfig.ByKey[board.Key] = board
end

function LeaderboardConfig.isBoard(key: unknown): boolean
	return type(key) == "string" and LeaderboardConfig.ByKey[key] ~= nil
end

-- === Formatting =============================================================

--[[ Comma groups up to five figures, then a suffix — the bands `GarageConfig.formatCash` uses,
	without the dollar sign, so a distance and a balance of the same magnitude are the same width in
	the same column. Its header has the reasoning for the 100,000 switch. ]]
local SUFFIXES = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e5, "K" } }

function LeaderboardConfig.abbreviate(amount: number): string
	amount = math.max(0, math.floor(tonumber(amount) or 0))
	for _, step in SUFFIXES do
		if amount >= step[1] then
			local scale = if step[2] == "K" then 1e3 else step[1]
			return string.format("%.1f%s", amount / scale, step[2])
		end
	end
	return LeaderboardConfig.group(amount)
end

--- 1204830 -> "1,204,830". No suffix, no rounding — for counts small enough to read exactly.
function LeaderboardConfig.group(amount: number): string
	local text = tostring(math.max(0, math.floor(tonumber(amount) or 0)))
	local grouped, count = text, 0
	repeat
		grouped, count = string.gsub(grouped, "^(-?%d+)(%d%d%d)", "%1,%2")
	until count == 0
	return grouped
end

--[[ Seconds -> "99d 23h" / "5h 12m" / "8m" / "9s".

	TWO UNITS AT MOST, and the larger one is never dropped: a row is a fixed-width cell on a sign
	read from across a lobby, and "4d 7h 12m 09s" is not a thing anybody reads from there. ]]
function LeaderboardConfig.duration(seconds: number): string
	local s = math.max(0, math.floor(tonumber(seconds) or 0))
	local days = math.floor(s / 86400)
	local hours = math.floor((s % 86400) / 3600)
	local minutes = math.floor((s % 3600) / 60)
	if days > 0 then
		return string.format("%dd %dh", days, hours)
	elseif hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	elseif minutes > 0 then
		return string.format("%dm", minutes)
	end
	return string.format("%ds", s)
end

--[[ The amount cell for one row. The board calls this and nothing else; an unknown `Unit` falls
	back to a grouped integer rather than erroring, so a board added to `List` with a typo in it
	draws a slightly plain number instead of taking the page down. ]]
function LeaderboardConfig.format(board: { [string]: any }, value: number): string
	local unit = board and board.Unit
	if unit == "cash" then
		return GarageConfig.formatCash(value)
	elseif unit == "duration" then
		return LeaderboardConfig.duration(value)
	elseif unit == "distance" then
		return LeaderboardConfig.abbreviate(value)
	end
	return LeaderboardConfig.group(value)
end

return LeaderboardConfig
