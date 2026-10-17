--[[
	OfflineConfig
	-------------
	The WELCOME BACK screen: what your dealership was holding for you while you were gone.

	=== READ THIS FIRST: THE MONEY ALREADY WORKED ==============================================

	Offline income is not a thing this feature adds. `GarageConfig`'s header is explicit about it —
	a parked car stores one number, the `os.time()` it was last collected, and what it owes is

	    pending = min(now - collectedAt, cap) * rate(tier) * multiplier

	The clock kept running while the player was logged out, so a bay that was earning when they left
	is still earning when they come back and the money has been correct since the day that formula
	was written. What was missing was that NOBODY EVER SAW IT HAPPEN. You rejoined, walked past six
	mats that happened to be holding more than usual, and the single most reliable reason to come
	back tomorrow was invisible.

	So this feature adds no economy at all. It is a screen and a claim button, and the claim button
	calls `GarageService.collectAll` — the same sweep the AUTO COLLECT upgrade uses, which is itself
	a loop over the same `_collect` a foot on a mat runs. THERE IS NO SECOND PAYOUT PATH and there
	must never be one: the moment "collected offline" and "collected by walking" are computed
	separately they drift, and the number on this screen stops being the number in your pocket.

	=== ...AND THE BOOST DOES NOT BREAK THAT ==================================================

	`Boost` below sells a Robux multiplier on this one claim, and it is the only thing on this screen
	that hands over money the bays were not holding. It still does not compute a payout: it runs the
	SAME `collectAll` and multiplies the single number that came back. So there is one answer to
	"what was on the lot" and the boost is arithmetic applied on top of it — which is why the screen
	can promise a figure before the sweep runs and still be right afterwards.

	The rule that survives, and the one to keep: NOTHING HERE MAY EVER ASK THE BAYS A SECOND TIME.

	=== WHAT THE SCREEN IS HONEST ABOUT ========================================================

	The amount is WHAT THE BAYS ARE HOLDING, not a separate offline ledger. For the player who
	collected on their way out — which is everyone, because the mats are on the path to the truck —
	those are the same number. For the player who logged off mid-lot it is slightly more than the
	time they were away, never less, so nobody is ever shown less than they earned. The copy below
	is written to match: the headline is the TIME AWAY and the number is what is waiting, rather
	than a claim that the two multiply out.

	`LastSeen` exists only to answer "how long were you gone" and to decide whether to show the
	screen at all. It is not part of the payout, which is why a profile that has never had one — a
	player who last played before this shipped — just gets no screen on that first rejoin instead of
	a wrong one.

	=== THE CAP IS THE POINT, NOT A DISAPPOINTMENT =============================================

	A bay holds two hours (`GarageConfig.Income.MaxBankedSeconds`), eight with STORAGE maxed. Come
	back after a night's sleep and most of that night paid nothing, and the screen would be lying by
	omission if it did not say so. `CappedFormat` is that line, and it names the upgrade that fixes
	it — which is the one place in the game where the STORAGE tile can be sold at the exact moment
	the player feels its absence.

	`OfflineConfig.Enabled = false` takes the whole thing out. The money is untouched by that: the
	bays keep accruing and keep paying out under a foot, exactly as they did before this file.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- The rbxsync-generated id table. The boost is a Robux product and its id is resolved out of
--- here by KEY, never pasted — see `Boost` below and the header on `shared/GameIds`.
local GameIds = require(ReplicatedStorage.shared.GameIds)

local OfflineConfig = {}

--- Master switch. Off = no screen, no claim remote, and no `LastSeen` is written. The economy is
--- unaffected either way — see the header.
OfflineConfig.Enabled = true

-- === The profile ============================================================

--[[ Where "the last time we knew this player was in the game" lives, as an `os.time()`.

	TOP-LEVEL, for the same reason `ReviveConfig.ProfileKey` is: `PlayerProfile`'s string path is a
	recursive key search, so a key nested inside `Garage` would be reachable only by array path from
	the two places that touch it. It is also not a garage fact — it is a session fact, and the
	garage would be the wrong owner even if the lookup were free.

	Absent (or zero) means "we have never seen this player leave", which is a first session and a
	profile written before this feature existed. Both get no screen rather than a made-up one. ]]
OfflineConfig.ProfileKey = "LastSeen"

--[[ Seconds between refreshes of that stamp while the player is sitting in the game.

	IT IS WRITTEN ON A TIMER AND THAT IS A DELIBERATE EXCEPTION to `GarageService`'s "the only writes
	to the profile are ones a player caused". Join and leave alone would be enough in the happy
	path; they are not enough when the SERVER dies, because then the leave write never happens and
	the stamp still says "joined four hours ago" — so the next session opens with a screen claiming
	they were away for a session they actually played. A minute of granularity costs one in-memory
	`Set` per player per minute (the datastore write is the Data layer's own autosave, not ours) and
	removes the whole class of it.

	Set to 0 to write only on join and leave. ]]
OfflineConfig.TouchInterval = 60

-- === When the screen is worth showing =======================================

--[[ How long the player has to have been gone before there is anything to tell them.

	FIVE MINUTES, because the failure mode is not "we missed one" — it is a screen in the player's
	face every time they rejoin after a disconnect, a Studio restart or a server hop, which is
	exactly the population most likely to be rejoining. Five minutes of a starting lot is single
	digits of cash; five minutes of a good one is worth a screen. ]]
OfflineConfig.MinAwaySeconds = 5 * 60

--[[ ...and how much has to be waiting. Below this the screen is a popup that interrupts a player to
	hand them nothing, which reads worse than never showing it — a lot with nothing parked on it is
	the common case for a new player and should be silent. ]]
OfflineConfig.MinAmount = 25

--[[ Seconds the client's "my screen is up, what did I miss?" ping is honoured for.

	The offer is computed the moment the profile lands and then WAITS for the client to say it is
	ready, because a remote fired at a player whose controllers have not started yet is a remote
	nobody hears. This is the far end of that wait: a client that never pings has probably gone, and
	the offer is dropped rather than kept forever against a player who might come back to the same
	server slot. Nothing is lost when it expires — the money is still on the bays. ]]
OfflineConfig.ReadyTimeout = 60

-- === The boost ==============================================================

--[[ THE PAID MULTIPLIER on this one claim. Off is the whole feature gone: the screen draws one
	button, `OfflineService` registers no product function and nothing prompts for Robux.

	=== WHY A DEVELOPER PRODUCT AND NOT A PASS =================================================

	A pass is bought once and pays forever, and a permanent multiplier on the thing this game hands
	you for logging in is not a boost, it is a different economy. This is a consumable: one purchase
	buys one claim, and the player who wants it every morning buys it every morning. That also makes
	the price answerable: `rbxsync.toml` is where the same number is written for Roblox to charge.

	=== WHY IT IS BANKED ON THE PROFILE ========================================================

	`ProfileKey` holds boosts bought and not yet spent, exactly as `ReviveConfig.ProfileKey` holds
	lives, and for the identical reason: a Robux receipt can land when there is no screen to apply
	it to. They closed the panel behind the purchase modal, they left, the server restarted, Roblox
	retried the receipt two sessions later. Applying the multiplier straight out of the receipt makes
	every one of those a player who paid and got nothing.

	Banked, all of them are a player who owns a boost — spent automatically the instant the purchase
	lands if their screen is still up, and waiting on the next WELCOME BACK screen if it is not,
	where the button says so and costs them nothing to press.

	=== WHAT IT MULTIPLIES =====================================================================

	The claim, once. `OfflineService` sweeps the lot exactly as an unboosted claim does and pays the
	difference on top of what that returned, so the boost is worth double whatever was standing on
	the bays at the moment of the press, not double a number this file remembers. A lot with
	nothing on it is worth nothing boosted, which is why the boost cannot be spent on one: see
	`OfflineService._pay`. ]]
OfflineConfig.Boost = {
	Enabled = true,

	--[[ Ties this to its `[products.<key>]` block in `rbxsync.toml`. The id is filled in below from
		the rbxsync-generated `GameIds` and is 0 only if the sync has not been run — which reads
		downstream as "this cannot be sold" and takes the button off the screen, never as "it is
		free". ]]
	Key = "OfflineBoost",

	--[[ TWO. It was TEN until 2026-09-17, and it came down because of what a day away actually pays
		on a lot that is running: a playtester's screen offered $90,720, and ten times that for one
		press is not a good morning, it is a week of the game sold for 49 Robux.

		It is still sized against the thing it multiplies rather than against a taste for big numbers.
		The claim is capped by `GarageConfig.Income.MaxBankedSeconds` (two hours of lot, eight with
		STORAGE maxed), so doubling it is a good morning and nothing more. A player cannot stack it
		either; one purchase is one claim, and the lot is empty behind it.

		Change it and the button changes with it: every caption below takes it as an argument rather
		than spelling it out, so this is the only place the number lives IN LUAU. `rbxsync.toml` also
		names it, in the product title and description Roblox holds, and that copy is only true again
		after a sync. `Price` below is the other half of the same contract, and it did not move with
		this: 49 Robux buys a fifth of what it used to. ]]
	Multiplier = 2,

	--[[ What the BUTTON says, in Robux. Roblox charges what the product is priced at, so this is a
		display value that has to be kept honest against `rbxsync.toml` by hand — the same contract
		`ReviveConfig.Tiers[n].Price` has, and the same one-line failure if it is broken. ]]
	Price = 49,

	--[[ Boosts bought and not yet spent. TOP-LEVEL on the profile for the reason `ProfileKey` above
		is: `PlayerProfile`'s string path is a recursive key search, so a key nested inside `Garage`
		would be reachable only by array path from the two places that touch it.

		Absent is zero, so no profile written before this line needs migrating. ]]
	ProfileKey = "OfflineBoosts",
}

OfflineConfig.Boost.ProductId = GameIds["products." .. OfflineConfig.Boost.Key] or 0

-- === What it says ===========================================================
--[[ Copy lives here rather than in the controller for the usual reason: every one of these is a
	sentence somebody who is not me will want to rewrite, and none of them should need a diff of a
	layout file to find. Everything is upper-cased by the screen, which is the kit's voice. ]]

OfflineConfig.Title = "WELCOME BACK"

--- Above the number. `%s` is `formatAway` below.
OfflineConfig.AwayFormat = "AWAY FOR %s"

--- Under the number, when the bays did NOT fill up. `%d` is how many bays are holding cash.
OfflineConfig.BaysFormat = "WAITING ON %d BAYS"
OfflineConfig.OneBayText = "WAITING ON 1 BAY"

--[[ Under the number when the lot hit its ceiling, which is the whole reason `Storage` exists.
	`%s` is how long a bay holds for this player — NOT how long they were away, which is already
	standing in the line above it and would be the same sentence twice. ]]
OfflineConfig.CappedFormat = "BAYS FILLED UP AFTER %s. UPGRADE STORAGE"

--[[ THE SAME TWO LINES WITHOUT PASSIVE INCOME (2026-09-28). The number on this screen stopped being
	what the bays held and became what customers tipped while the player was away
	(`OfflineService._simulate`), so "waiting on 3 bays" would describe money that no longer exists.
	The foot counts the people instead, and the cap line names the one rule left — the showroom only
	counts `CustomerConfig.Offline.CapSeconds` of absence — rather than an upgrade (`Storage`) that no
	longer does anything. `%d` is visitors; `%s` is the cap, through `formatAway`. ]]
OfflineConfig.VisitorsFormat = "%d CUSTOMERS STOPPED BY"
OfflineConfig.OneVisitorText = "1 CUSTOMER STOPPED BY"
OfflineConfig.ShowroomClosedFormat = "YOUR SHOWROOM CLOSED AFTER %s"

--[[ Appended to the visitors line when buyers are waiting on the lot (`BuyerService.catchUp`). On the
	foot line and not a line of its own, because the panel has one foot and the kit's layout is not
	this file's to add rows to; the separator is non-breaking like every other space here. ]]
OfflineConfig.BuyersSuffixFormat = " · %d BUYERS WAITING"
OfflineConfig.OneBuyerSuffix = " · 1 BUYER WAITING"

OfflineConfig.CollectText = "COLLECT"

--[[ The boost button, in its three states. All of them take the multiplier as an argument so
	`Boost.Multiplier` stays the one place the number is written.

	`BoostBuyFormat` is `(multiplier, price)` and is what a player who owns none sees — the price is
	on the button rather than in a line under it because a button that opens a Robux prompt has to
	say what it costs on the face that gets pressed.

	`BoostOwnedText` is `(multiplier)`, for a player holding exactly one — the price is GONE, not
	greyed, because they are not being sold anything and a struck-through number on a button they
	already paid for is the one thing on this screen that could read as a double charge.
	`BoostOwnedFormat` is `(multiplier, count)` and only appears above one, where the count is
	worth saying. ReviveController's caption makes the same two-state split for the same reason. ]]
OfflineConfig.BoostBuyFormat = "COLLECT %dx   R$%d"
OfflineConfig.BoostOwnedText = "COLLECT %dx"
OfflineConfig.BoostOwnedFormat = "COLLECT %dx   (%d)"

--[[ Replaces the bays/capped line for the length of a boosted payout, so the screen says WHY the
	number it just counted to is bigger than the one it was drawn with. `%d` is the multiplier.

	It only ever appears on a claim the server confirmed a multiplier for — the screen never writes
	this off the button it thinks was pressed, because the boost is spent server-side and can decline
	(an empty lot, a profile that went inactive), and a line claiming 2x over a 1x payout is worse
	than no line at all. ]]
OfflineConfig.BoostAppliedFormat = "%dx APPLIED"

-- === Formatting =============================================================

--[[ "2d 4h" / "3h 12m" / "12m" — two units, biggest first, and never three.

	NON-BREAKING SPACES between the parts, and the reason is written up in `RaceUIController`: a
	`TextScaled` label would sooner break "3h 12m" onto a second line than pick a smaller font, and
	this is a one-line label.

	SECONDS ARE NEVER SHOWN. `MinAwaySeconds` is five minutes, so the smallest thing this can ever
	be handed is "5m" — a seconds field would only ever be noise on a screen about having been away
	long enough to matter.

	A ZERO SECOND UNIT IS DROPPED, not printed. This also formats the STORAGE cap for the capped
	line, and that number is whole hours by construction (`UpgradeConfig.Upgrades.Storage` steps the
	two-hour base by halves), so without this every one of them would read "2h 0m". ]]
function OfflineConfig.formatAway(seconds: number): string
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))

	local days = seconds // 86400
	local hours = (seconds % 86400) // 3600
	local minutes = (seconds % 3600) // 60

	if days > 0 then
		return if hours > 0 then string.format("%dd\u{00A0}%dh", days, hours) else string.format("%dd", days)
	elseif hours > 0 then
		return if minutes > 0 then string.format("%dh\u{00A0}%dm", hours, minutes) else string.format("%dh", hours)
	end
	return string.format("%dm", math.max(1, minutes))
end

-- === The label at the top of the screen ======================================================
--[[ "Your cars earn $X/hr offline!" across the top of the lobby (2026-09-30, the partner's ask, off a
	reference game in the genre), drawn by `OfflineLabelController`.

	THE NUMBER IS THE REAL ONE: `OfflineService` runs `CustomerConfig.simulate` — the same function
	the WELCOME BACK payout is — over `PerSeconds` of absence and publishes it (`Attribute`). So the
	label can never promise more than a player comes back to, boost aside.

	PER HOUR, NOT PER DAY, AND THAT IS THE HONEST UNIT HERE. The reference shows a daily figure, but
	offline tips stop counting after `CustomerConfig.Offline.CapSeconds` (four hours): a "/day" number
	would be twelve times what anybody is ever paid. Per hour is exactly true for the first two.

	`Enabled = false` draws nothing and publishes nothing. ]]
OfflineConfig.Label = {
	Enabled = true,
	Attribute = "OfflineRate",
	--- How much absence the figure is for. 3600 = per hour; must stay <= `CustomerConfig.Offline.CapSeconds`.
	PerSeconds = 60 * 60,
	--[[ How often the server re-prices it, seconds, on top of every lot change. The lot is what moves
		it most and is caught the moment it changes; the ticker is for the customers upgrade, which
		changes the crowd size without touching the lot. ]]
	RefreshSeconds = 15,
	--- RichText; `%s` is the amount. The colour is the HUD's cash green.
	Format = 'Your cars earn about <font color="#5BFF5B">%s</font>/hr offline! 😈',
	--- With nothing on a bay nothing is earned, so the line says how to start instead.
	EmptyText = "Put cars on your bays to earn while you're offline!",
	--- Pixels below the top bar. A TASTE CALL; the one number to move if it meets another top widget.
	Top = 6,
	Height = 30,
	--- Of the screen's width. The text is scaled, so this only matters when the line is long.
	Width = 0.6,
	--[[ THE SAME LINE ON A PHONE (2026-10-06, Leaf: "huge on mobile, unnecessarily big"). `Height` is
		pixels, and 30 of them are 3% of a 1080p monitor but 8% of a landscape phone, where it read as a
		headline. These apply while `PreferredInput` is Touch, which is what the steal prompt asks too. ]]
	TouchHeight = 18,
	TouchWidth = 0.5,
	--[[ IN THE NOTICE LANE (`NoticeLaneConfig`, 2026-10-06) the line is the lane's width, about half
		the old one, so it wraps at a fixed size instead of scaling into one line: these, in pixels. The
		touch size is the old touch line's type, near enough. ]]
	LaneTextSize = 20,
	LaneTouchTextSize = 14,
	--[[ THE SCREENS IT STEPS ASIDE FOR (2026-09-30: it read through the carry card's "Parked" panel,
		"pretty ugly"). Every one of these drops a card into the top centre of the screen, so while any
		of them is switched on the label is hidden, and it comes back when they go. ScreenGui names:
		the carry hint (`CarryController`), the weather notice (`WeatherController`), the tutorial's
		card (`TutorialController`). NOT the street car's hint (`LobbyCarToyHint`): it sits mid-screen,
		and its ScreenGui stays switched on and fades its text instead, so it would hide the label for
		good. A new top-centre card needs its name added here. ]]
	YieldTo = { "CarryHint", "WeatherNotice", "Tutorial" },
	--[[ ...and the list while the line is in the left-side notice lane (`NoticeLaneConfig.Enabled`,
		2026-10-06). The carry card now stacks under it and the weather notice stays top-centre, so
		neither covers it any more. The tutorial is kept: its card rests just above the lane, and a
		player in the tutorial has enough to read. ]]
	LaneYieldTo = { "Tutorial" },

	--[[ WHETHER THIS LINE JOINS THE NOTICE LANE AT ALL. OFF since 2026-10-06, the owner, seeing it in
		the lane: "this text was moved to the side, can you move it back to the top". Off, it is the
		top-centre line it was before the lane (`Top`, `Height`, `Width`, the touch sizes, `YieldTo`),
		and the rest of the lane is untouched — its cards simply stack without this one above them.
		`true` (with `NoticeLaneConfig.Enabled`) puts it back in the lane exactly as Leaf built it. ]]
	InLane = false,
}

return OfflineConfig
