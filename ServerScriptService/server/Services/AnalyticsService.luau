--[[
	AnalyticsService
	----------------
	The GameAnalytics SDK's server half, and every event this game sends.

	=== WHY THIS IS ONE SERVICE AND NOT A SPRINKLING OF CALLS =====================================

	Almost everything below is a subscription to a signal some other service already fires. Nothing
	was added to `GarageService`, `RewardService`, `StealService`, `UpgradeService`, `WorldService`
	or `QuestService` for analytics — they were already announcing what they do, and this listens.

	That is worth defending, because the usual shape is an `Analytics:Track(...)` line dropped into
	each of those services. Three things go wrong when you do that: the taxonomy ends up scattered
	across a dozen files where nobody can read it as a whole, a service that gets refactored quietly
	loses its event, and every one of those services grows a dependency on analytics being up. Here
	the taxonomy is one table of connections you can read top to bottom, and a service that is off
	costs one `warn` rather than an error in somebody else's file.

	THE THREE EXCEPTIONS, and why each has to be a call site:

	    TutorialService   the beats are a funnel, and a funnel needs to know a step was REACHED as
	                      well as COMPLETED. Only that service knows the difference.
	    ReviveService     it owns the Robux prompt, and the interesting event is the prompt being
	                      SHOWN, which is not a signal because nothing else cares.
	    DevProductsHandler  receipts. `ProcessReceiptCallback` is the SDK's own hook and has to run
	                      where the receipt is.

	=== THE READY GATE, WHICH IS NOT OPTIONAL =====================================================

	The SDK DROPS any per-player event fired between a player joining and that player's GA session
	starting — an HTTP round trip — with "Player initialization queue already cleared" and nothing
	else. Since half of what this game reports happens in the first seconds of a session (the
	tutorial's first beats, a rejoin's profile load), an ungated port would lose exactly the events
	the tutorial funnel exists to count.

	`OnPlayerReadyEvent` is the SDK's post-session-start signal. Everything goes through `_submit`,
	which runs now if that has fired and buffers if it has not. Custom dimensions cannot buffer at
	all — the SDK rejects them pre-ready — so they are set on ready and refreshed after.

	Learned the hard way in Needoh Escape; this is the same architecture, and the comment is here so
	the next port does not have to relearn it.

	=== THE TAXONOMY ==============================================================================

	Design events are `Category:Thing:Detail`, at most five segments, `[A-Za-z0-9_-.]` only:

	    Tutorial:Step<N>:<Beat>              reached beat N       -- the onboarding funnel
	    Tutorial:Step<N>:<Beat>:Complete     finished beat N
	    Tutorial:Complete / Tutorial:Skip:Step<N>:<Beat>
	    FirstCar:Carried|Placed|Abandoned    the first car a profile is ever handed
	    Run:Start:<World> / Run:Banked / Run:Wrecked
	    Steal:Complete                       value = the Nth steal of that run
	    Car:Parked|Sold:<Body>               value = tier
	    Car:Leveled:<Body>                   value = new level
	    World:Unlocked|Changed:<World>
	    Quest:Completed|Claimed:<Id>
	    Monetization:Prompt:Product:<Name>

	Cash is a RESOURCE event, not a design event, so the dashboard's economy view balances sources
	against sinks by itself. Robux is a BUSINESS event via the receipt hook.

	Two custom dimensions, both chosen because they segment every other number usefully and neither
	can go stale: `01` is which world the player is in, `02` is whether they have finished the
	tutorial.

	=== GAMEBEAST, THE SECOND SINK (added 2026-10-08) =============================================

	Every event above also goes to Gamebeast as a MARKER, from the same handler, so the two dashboards
	can never disagree about what was counted. Markers are not GA ids: the marker type is the THING
	and the detail rides as properties, because Gamebeast funnels, filters and breakdowns all work on
	properties. `Car:Sold:GolfGTI` would be one marker type per body; `CarSold {body = "Golf GTI"}`
	is one type with a breakdown. Raw names are kept (no `clean`), since properties allow any string.

	    TutorialStep      {step, beat, stage = "Reached" | "Completed"}   the onboarding funnel
	    TutorialCompleted / TutorialSkipped {step, beat}
	    FirstCarCarried / FirstCarPlaced / FirstCarAbandoned   {guideStyle}   the trail A/B's arm
	    RunStarted        {world, runNumber}       runNumber counts this SESSION's runs, so a funnel
	    RunEnded          {world, banked, distance, cash, runNumber}  can ask "did their first run bank"
	    CarStolen         {index}                  the Nth steal of that run
	    CarParked / CarSold / CarLeveled / CarBought   {body, tier | level, cash | price}
	    UpgradeBought     {upgrade, level, cost, bay?}
	    WorldUnlocked {world, cost} / WorldChanged {world}
	    QuestCompleted {quest} / QuestClaimed {quest, reward}
	    CashPackBought    {pack, cash}
	    PurchasePrompted  {product, productId}
	    PassiveIncome     {tips, tipCount, collects, collectCount}   ONE per session, on leave

	PassiveIncome is a summary rather than a marker per tip because tips are the highest-frequency
	thing in the game (a crowd pays every few seconds) and Gamebeast bills by marker volume. GA still
	gets every tip as a resource event; Gamebeast gets the session total.

	The SDK sends Login, Logout, Purchase (game passes on its own, dev products via
	`ReportGrantedPurchase`), Chat and session length by itself. Nothing here duplicates those.

	NO READY GATE IS NEEDED for Gamebeast. Its per-player markers hold themselves until that player's
	session data resolves (`EngagementMarkers` pending queue), which is the job `_submit` does for GA.

=== THE 2026-10-15 PASS: THE SYSTEMS THAT CAME AFTER THE FIRST ONE ==========================

	The sellers replaced the plaza market (`CarDealConfig.Enabled = false`), so `CarBought` and
	`Deal:FirstBuy` stopped firing, and the buyers had become how cars get sold with nothing counting
	them. This pass subscribes to both, and to the cash flows the economy view was missing. Same rule
	as the rest of the file: every source below is a SIGNAL its own service fires.

	    SellerArrived     {body, tier, band, price, first}   a seller pulled up (`first` = the onboarding arrow)
	    SellerResolved    {outcome, body, tier, band, price, first, viewed, shortCash}
	                      outcome = Bought | Declined | Ignored | Gone
	    CarBought         {body, tier, price, source = "Seller" | "Market", band?}   cash spent on a car
	    BuyerOffer        {body, tier, amount, value, ratio, kind, source}   source = Live | Offline | Tutorial | Admin
	    BuyerOfferResolved {outcome, body, tier, amount, kind, source, viewed}
	                      outcome = Accepted | Declined | Expired | Withdrawn
	    CarSold           ...plus {source = Buyer | Lot | Full | Duplicate}
	    RunStarted        ...plus {car}
	    RunEnded          ...plus {car, cause, wrecks, revives, steals, nearMisses, rubs, bonus,
	                      speedTraps, trapCash}   cause = banked | health | thrown | fell | badLanding | busted | quit
	    PurchasePrompted  ...plus {context} on a cash top-up: what they were short for
	    PageOpened        {page}   a screen opened (client, via `AnalyticsPageOpened`; rate limited)
	    RunEndChoice      {choice = RaceAgain | Home, how = press | auto, panel = revive | bank | wreck,
	                      runNumber, tutorial, beat}   the end panel's answer (client, `AnalyticsEndChoice`)
	    DailyRewardClaimed {day, kind, amount, body?}   CodeRedeemed {code, cash}
	    OfflineEarnings   {cash, awayMinutes, buyers}   OfflineBoosted {cash}
	    WorkshopBought    {kind, body, part?, level?, cost}   IndexRewardClaimed {body, total}

	GA gets the matching resources (`Seller`, `Workshop` sinks; `Daily`, `Code`, `Offline`,
	`SpeedTrap` sources) and a few design ids, named where they are sent. Speed traps get no marker of
	their own: they are several a run, so they ride on `RunEnded` as a count and a total, the same
	volume trade `PassiveIncome` makes.

=== THE JOIN FUNNEL (2026-10-20) ==============================================================

	Asked for by Aleafo: joins were reported slow, and some low-end phones crash before they reach the
	game, and nothing measured either. `ReplicatedFirst.JoinScreen` reports each of its phases over
	`JoinProgress`, a PLAIN RemoteEvent this service parents to ReplicatedStorage in `init`, because
	that script runs before any module (Shard included) can be required and has to find it by name.
	Step 1 is the server seeing the player arrive, so a client that dies before it can send anything
	still counts as a join that stopped at step 1.

	    Roblox funnel "Join"  Joined > Loaded > Started > Spawned > Playing, one funnel session per
	                      join (a GUID), so a rejoin is a second run through it. Filter by Platform.
	    JoinFinished      {seconds, character, screen, loaded, started, spawned, assets, assetCount,
	                      assetsFetched, slowest, slowestSeconds, memoryMb, textureMb, meshMb,
	                      partsMb, soundMb, luaMb, recovered, onboarded}   the overlay lifted.
	                      `seconds` is server time since PlayerAdded and `character` the server's
	                      own time to a character (profile, plot, LoadCharacter); `screen` and the
	                      phase fields are the screen's laps; `slowest` is the slowest controller
	                      phase (`Modules/BootGuard`), e.g. "OfflineController.start"
	    JoinFailed        {stage, lastPhase, seconds, character, memoryMb}   the screen said
	                      COULDN'T LOAD; stage = boot | controllers | spawn | timeout
	    JoinAbandoned     {lastPhase, step, seconds, character, memoryMb, failed}   left before the
	                      overlay lifted: a quit, a crash or a disconnect, which a server cannot
	                      tell apart

	GA gets `Join:Finished` (value = seconds), `Join:Failed:<Stage>` and `Join:Abandoned:<Phase>`.
	`memoryMb` is the client's own total (`Stats:GetTotalMemoryUsageMb`) at its latest report: the
	number to read beside the Creator Dashboard's "Unexpected out of memory exits". The `...Mb`
	fields are its `DeveloperMemoryTag`s as the game appears.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
--- Roblox's own, for the "Join" funnel; `FirstCarService` names it the same way.
local RobloxAnalytics = game:GetService("AnalyticsService")

local GameAnalytics = require(ReplicatedStorage.Packages["gameanalytics-sdk"])
local Gamebeast = require(ReplicatedStorage:WaitForChild("Gamebeast"))
local GameIds = require(ReplicatedStorage.shared.GameIds)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
--- For `Remote` and `Style`, the guide trail A/B the first-car markers are tagged with.
local GuideTrailConfig = require(ReplicatedStorage.shared.Configs.GuideTrailConfig)
local PoliceConfig = require(ReplicatedStorage.shared.Configs.PoliceConfig)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

--[[ Created 2026-08-20 under Aleafo Games / Dragonstar Games, game 350433 ("My Car Got Stolen").

	KEYS IN SOURCE IS DELIBERATE AND IS WHAT THE SDK EXPECTS. `src/server` never replicates to
	clients, so a player cannot read these out of a running game. If this repo is ever made public,
	rotate them in the GA dashboard rather than trying to hide them here. ]]
local GAME_KEY = "4f45b72e01e170b491f513eb7084067e"
local SECRET_KEY = "b3827dfa3392d341abc1183a558c3ae6a7f9ffeb"

--[[ Gamebeast SDK key, created 2026-10-08 on dashboard.gamebeast.gg (org 441 "First To Finish",
	project 829 "Steal a Car"). Gamebeast documents this as a PUBLIC key scoped to one project and
	safe to ship, but it lives here beside the GA keys anyway. The dashboard shows a key only once:
	a lost key is replaced by creating a new one in Project Settings, not recovered.

	Studio sessions are filed under the dashboard's "Studio" environment and live servers under
	"Production" by the SDK itself (`GBRequests` sends `IsStudio` as a header), so a playtest never
	pollutes the live numbers. ]]
local GAMEBEAST_KEY = "gb_pk_j2rxUQv7Tn-CL8zErB_YOXAVB18CwPQTqGYl99xAyVo"

--[[ Which build the numbers get filed under.

	NOT read off `Settings.PRODUCTION_PLACE_ID`, which is the obvious source and is wrong twice: it
	names one place only, and it is the switch that picks the DATASTORE SUFFIX. Coupling a build
	label to it would mean that labelling analytics correctly one day silently moves every save file
	to a different key. A Studio session is "dev" and a live server is its place version, which is
	all the label has to say. ]]
local function buildString(): string
	if RunService:IsStudio() then
		return "dev"
	end
	return "v" .. game.PlaceVersion
end

--[[ Event-id segments allow `[A-Za-z0-9_-.]` only, and this game's names break that constantly:
	car bodies have spaces ("Golf GTI"), and so does a world ("Forest Mountains"). Stripping rather
	than substituting, so "Golf GTI" and "GolfGTI" can never both appear as separate events. ]]
local function clean(name: unknown): string
	if type(name) ~= "string" then
		return "Unknown"
	end
	local stripped = (name:gsub("[^%w_%-%.]", ""))
	return if stripped ~= "" then stripped else "Unknown"
end

--- A beat id as it appears in an event id: `bail` -> `Bail`. The ids are lowercase in the config
--- because they are keys; the funnel reads better capitalised.
local function beatLabel(id: unknown): string
	local text = clean(id)
	return text:sub(1, 1):upper() .. text:sub(2)
end

--- Resource amounts must be finite and positive — the SDK rejects anything else, and one rejected
--- event is a hole in the economy chart rather than an error anybody sees.
local function toAmount(amount: unknown): number?
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return nil
	end
	return math.floor(amount)
end

local function toUserId(target: Player | number | nil): number?
	if typeof(target) == "Instance" then
		return (target :: Player).UserId
	end
	if type(target) == "number" then
		return target
	end
	return nil
end

--- Every world name, sanitised, as the allowed values of custom dimension 01. Derived rather than
--- typed: a world added to `WorldConfig` becomes a segment without anybody remembering to come here.
local function worldDimensions(): { string }
	local names = {}
	for index in WorldConfig.Worlds do
		table.insert(names, clean(WorldConfig.displayName(index)))
	end
	return names
end

--- The dev products this game sells, as `id -> readable name`, for prompt event ids. `GameIds` is
--- generated by rbxsync, so this follows whatever is declared in `rbxsync.toml`.
local productNames: { [number]: string } = {}
for key, id in GameIds do
	local name = key:match("^products%.(.+)$") or key:match("^passes%.(.+)$")
	productNames[id] = clean(name or tostring(id))
end

--[[ The GAME PASSES this game sells, as ids, for `availableGamepasses` below. DERIVED FROM
	`GameIds` rather than typed, exactly as `productNames` and `worldDimensions` are — a pass added
	to `rbxsync.toml` and synced becomes a declared pass here without anybody remembering to come
	back. Sorted so the list a build reports is stable between servers. ]]
local function passIds(): { number }
	local ids = {}
	for key, id in GameIds do
		if key:match("^passes%.") then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

--[[ The screens worth a `PageOpened` marker: every page module the UI has, by name (the name
	`UIController` keys pages by), so a page added later is counted without anybody coming back here.
	It is also the whitelist the remote is checked against, so a client cannot invent page names.

	TELEPORT AND STARTCAR ARE LEFT OUT. They are the road to every run, which `RunStarted` already
	counts, and they would be most of the volume. ]]
local UNTRACKED_PAGES = { Teleport = true, StartCar = true }
local function trackedPages(): { [string]: boolean }
	local out = {}
	local shared = ReplicatedStorage:FindFirstChild("shared")
	local controllers = shared and shared:FindFirstChild("Controllers")
	local ui = controllers and controllers:FindFirstChild("UIController")
	for _, folderName in { "Pages", "PagesV2" } do
		local folder = ui and ui:FindFirstChild(folderName)
		if folder then
			for _, module in folder:GetChildren() do
				if module:IsA("ModuleScript") and not UNTRACKED_PAGES[module.Name] then
					out[module.Name] = true
				end
			end
		end
	end
	return out
end

--- One screen opening counts once per this many seconds per player, and a session counts at most
--- `PAGE_CAP` in all. A toggled button or a misbehaving client must not turn into a marker bill.
local PAGE_COOLDOWN = 20
local PAGE_CAP = 150

--[[ The join funnel (see the header). Step 1 is `PlayerAdded`; the rest are `JoinScreen`'s phases,
	spelled as it reports them, so keep the two in step. ]]
local JOIN_FUNNEL = "Join"
local JOIN_REMOTE = "JoinProgress"
local JOIN_STEPS = { joined = 1, loaded = 2, started = 3, spawned = 4, playing = 5 }
local JOIN_STEP_NAMES = { "Joined", "Loaded", "Started", "Spawned", "Playing" }
--- Why a screen said COULDN'T LOAD (`JoinScreen`'s `showError`). Anything else reads "unknown".
local JOIN_FAIL_STAGES = { boot = true, controllers = true, spawn = true, timeout = true }

--- A number a client sent: finite, inside `0..limit`, to one decimal. Anything else is nil, which
--- leaves the field off the marker rather than charting a lie.
local function clientNumber(value: unknown, limit: number): number?
	if type(value) ~= "number" or value ~= value or value < 0 or value > limit then
		return nil
	end
	return math.floor(value * 10 + 0.5) / 10
end

--[[ What a cash top-up was FOR, from the sentence each `CashService:offerTopUp` caller hands it (the
	callers are `SellerService`, `UpgradeService` twice, `WorldService`, `WorkshopService` and
	`CarDealService`). Matched in order, so the bay upgrade is caught before the generic upgrade. A
	caller whose sentence matches none of these reads "Other", which is the cue to add a line here. ]]
local TOP_UP_CONTEXTS = {
	{ "from a seller$", "Seller" },
	{ "^bay %d+'s upgrade$", "BayUpgrade" },
	{ "upgrade$", "Upgrade" },
	{ "^world %d+$", "World" },
	{ "^a repair on ", "Workshop" },
	{ "^a repaint of ", "Workshop" },
	{ " level %d+ on ", "Workshop" },
	{ " on bay %d+$", "Market" },
}
local function topUpContext(reason: unknown): string?
	if type(reason) ~= "string" then
		return nil
	end
	for _, rule in TOP_UP_CONTEXTS do
		if reason:find(rule[1]) then
			return rule[2]
		end
	end
	return "Other"
end

--- A car key's body and tier, for markers about a car the player owns (`"Camaro:6#17"`).
local function bodyAndTier(carId: unknown): (string, number)
	local body = if type(carId) == "string" then GarageConfig.parseCarKey(carId) else nil
	local tier = body and GarageConfig.TierOfBody[body]
	return if type(body) == "string" then body else "Unknown", if type(tier) == "number" then tier else 0
end

local AnalyticsService = Shard.new("AnalyticsService")

AnalyticsService:withRemoteEvents({
	{
		--[[ client -> server (pageName): a screen opened (`AnalyticsController`, off `UIController`'s
			own `PageOpened`). TRUST: only a name, checked against `trackedPages` and rate limited in
			`_onPageOpened`; nothing is paid or changed on it. ]]
		AnalyticsPageOpened = function(player: Player, page: unknown)
			AnalyticsService:_onPageOpened(player, page)
		end,
		--[[ client -> server (answer, how, panel): the end panel was answered, RACE AGAIN ("replay") or
			HOME ("home"), by a press or the countdown ("press" / "auto"), on the "revive", "bank" or
			"wreck" panel. TRUST: checked against those words and once per run in `_onEndChoice`. ]]
		AnalyticsEndChoice = function(player: Player, answer: unknown, how: unknown, panel: unknown)
			AnalyticsService:_onEndChoice(player, answer, how, panel)
		end,
	},
})

AnalyticsService:withLifecycle({
	init = function(self)
		self._trove = Trove.new()
		--- [userId] = { [eventId] = true } — the per-session dedup behind `DesignOnce`.
		self._once = {}
		--- [userId] = true once the SDK's per-player session has actually started. See the header.
		self._ready = {}
		--- [userId] = { () -> () } — events raised before that, replayed on ready.
		self._pending = {}

		GameAnalytics:initialize({
			gameKey = GAME_KEY,
			secretKey = SECRET_KEY,
			build = buildString(),
			enableInfoLog = RunService:IsStudio(),
			reportErrors = true,
			--[[ Robux gamepass purchases are hooked by the SDK itself; dev products come through
				`ReportReceipt`.

				A PASS NOT IN THIS LIST IS SILENTLY NOT REPORTED, which is the same trap
				`availableResourceItemTypes` below carries and is worth the same warning: the SDK
				accepts the purchase, nothing appears on the dashboard, and nothing warns. That is
				why the list is derived from `GameIds` rather than typed — see `passIds`. ]]
			automaticSendBusinessEvents = true,
			availableGamepasses = passIds(),
			availableResourceCurrencies = { "Cash" },
			--[[ AN ITEM TYPE NOT DECLARED HERE IS SILENTLY DROPPED, which is the whole reason this list
				is worth reading before adding a `Resource` call anywhere: the event is accepted by the
				SDK, never appears on the dashboard, and nothing warns. `Deal` is `CarDealService`'s
				market. ]]
			-- `Tip` since 2026-09-28: customers are the dealership's income now (`_watchEconomy`).
			-- The last six since 2026-10-15 (`_watchMarket`, `_watchRewards`, `_watchRuns`).
			availableResourceItemTypes = {
				"Run", "Collect", "Sale", "Quest", "Upgrade", "World", "Deal", "Product", "Tip",
				"Seller", "Workshop", "Daily", "Code", "Offline", "SpeedTrap",
			},
			availableCustomDimensions01 = worldDimensions(),
			availableCustomDimensions02 = { "New", "Onboarded" },
		})

		--- [userId] = runs started this session, the `runNumber` on run markers.
		self._runs = {}
		--- [userId] = { tips, tipCount, collects, collectCount }, flushed as one marker on leave.
		self._passive = {}
		--- [userId] = the run in progress, for `RunEnded`'s extra fields. Reset on `RaceEntered`.
		self._run = {}
		--- [userId] = { [carId] = { source, viewed } }, for `BuyerOfferResolved`. Session memory only:
		--- an offer made last session resolves with `source = "Unknown"`.
		self._offerMeta = {}
		--- [userId] = { count, at = { [page] = os.clock() } }, the `PageOpened` rate limit.
		self._pages = {}
		self._trackedPages = trackedPages()
		--- [userId] = the guide trail look last read for them, for a marker sent as they leave.
		self._guideStyles = {}

		--- [userId] = { at, session, step, phase, character?, slowest?, memoryMb?, failed?, done? },
		--- this join's funnel run.
		self._joins = {}
		--[[ Here and not in `start`, so the screen of a player who joins while the server is still
			booting finds it, and so their arrival is timed from as early as this server can see it. ]]
		local joinRemote = Instance.new("RemoteEvent")
		joinRemote.Name = JOIN_REMOTE
		joinRemote.Parent = ReplicatedStorage
		self._trove:Add(joinRemote)
		self._trove:Add(joinRemote.OnServerEvent:Connect(function(player: Player, phase: unknown, data: unknown)
			self:_onJoinProgress(player, phase, data)
		end))
		self._trove:Add(Players.PlayerAdded:Connect(function(player: Player)
			self:_onJoined(player)
		end))
		for _, player in Players:GetPlayers() do
			self:_onJoined(player)
		end

		--[[ pcall because a Gamebeast outage or a bad key must cost the Gamebeast markers and nothing
			else; `Marker` checks `_gamebeast` and goes quiet when this failed. ]]
		local ok, err = pcall(function()
			Gamebeast:Setup({ key = GAMEBEAST_KEY })
			self._gamebeast = Gamebeast:GetService("Markers")
		end)
		if not ok then
			self.log:warn("Gamebeast did not start, its markers are off: " .. tostring(err))
		end

		--[[ What this build can show an experiment, as a Gamebeast server property the experiment
			targets: the tutorial's RACE AGAIN A/B enrols only players on a server that says it has the
			switch (`TutorialConfig.RaceAgain`). Its own pcall, so a failure here costs that test and
			not the markers. ]]
		if self._gamebeast and TutorialConfig.RaceAgain.Remote.Enabled then
			local propOk, propErr = pcall(function()
				Gamebeast:GetService("Experiments"):SetServerProperty(TutorialConfig.RaceAgain.ServerProperty, true)
			end)
			if not propOk then
				self.log:warn("Gamebeast server property not set, the RACE AGAIN test enrols nobody here: " .. tostring(propErr))
			end
		end
	end,

	start = function(self)
		self._trove:Add(Players.PlayerRemoving:Connect(function(player: Player)
			local userId = player.UserId
			self:_onJoinLeft(player)
			self:_flushPassive(player)
			self._once[userId] = nil
			self._ready[userId] = nil
			self._pending[userId] = nil
			self._runs[userId] = nil
			self._run[userId] = nil
			self._offerMeta[userId] = nil
			self._pages[userId] = nil
			--- Later, not now: `FirstCarAbandoned` is sent from another service's handler for this same
			--- event, which is not ordered against this one.
			task.delay(10, function()
				if not Players:GetPlayerByUserId(userId) then
					self._guideStyles[userId] = nil
				end
			end)
		end))

		--[[ The SDK's post-session-start signal — see the header on why nothing per-player may be
			sent before it. `WaitForChild` because the SDK creates it during its own init, which is
			not ordered against this service's `start`. ]]
		local ready = ReplicatedStorage:WaitForChild("OnPlayerReadyEvent", 30)
		if ready then
			self._trove:Add(ready.Event:Connect(function(player: Player)
				self:_onReady(player)
			end))
		else
			self.log:warn("No OnPlayerReadyEvent — the SDK did not initialise; every event will buffer.")
		end

		self:_watchEconomy()
		self:_watchRuns()
		self:_watchCollection()
		self:_watchMarket()
		self:_watchRewards()
	end,
})

AnalyticsService:withCleanup(function()
	if AnalyticsService._trove then
		AnalyticsService._trove:Destroy()
	end
end)

-- === The gate ===============================================================

function AnalyticsService._onReady(self, player: Player)
	local userId = player.UserId
	self._ready[userId] = true

	local pending = self._pending[userId]
	self._pending[userId] = nil
	if pending then
		for _, fn in pending do
			task.spawn(fn)
		end
	end

	task.spawn(function()
		self:RefreshDimensions(player)
	end)
end

--[[ Run now if this player's GA session is live, else hold it until it is.

	CAPPED, because a player whose session never starts — an SDK init failure, a server with HTTP
	off — must not grow a list forever. Past the cap the events are dropped, which is the right
	trade: analytics is the thing that gives way, never the server. ]]
local PENDING_LIMIT = 64
function AnalyticsService._submit(self, userId: number, fn: () -> ())
	if self._ready[userId] then
		fn()
		return
	end
	local pending = self._pending[userId]
	if not pending then
		pending = {}
		self._pending[userId] = pending
	end
	if #pending < PENDING_LIMIT then
		table.insert(pending, fn)
	end
end

-- === The four event kinds ===================================================

function AnalyticsService.Design(self, target: Player | number | nil, eventId: string, value: number?)
	local userId = toUserId(target)
	if not userId then
		return
	end
	self:_submit(userId, function()
		GameAnalytics:addDesignEvent(userId, { eventId = eventId, value = value })
	end)
end

--- ...and the same thing at most once per session per player, which is the form a FUNNEL step wants:
--- a player who does something twice is still one player who reached that step.
function AnalyticsService.DesignOnce(self, target: Player | number | nil, eventId: string, value: number?)
	local userId = toUserId(target)
	if not userId then
		return
	end
	local seen = self._once[userId]
	if not seen then
		seen = {}
		self._once[userId] = seen
	end
	if seen[eventId] then
		return
	end
	seen[eventId] = true
	self:Design(userId, eventId, value)
end

function AnalyticsService.Resource(
	self,
	target: Player | number | nil,
	flow: "Source" | "Sink",
	amount: unknown,
	itemType: string,
	itemId: string
)
	local userId = toUserId(target)
	local clamped = toAmount(amount)
	if not (userId and clamped) then
		return
	end
	self:_submit(userId, function()
		GameAnalytics:addResourceEvent(userId, {
			flowType = GameAnalytics.EGAResourceFlowType[flow],
			currency = "Cash",
			amount = clamped,
			itemType = itemType,
			itemId = itemId,
		})
	end)
end

function AnalyticsService.Progression(
	self,
	target: Player | number | nil,
	status: "Start" | "Complete" | "Fail",
	p1: string,
	p2: string?,
	p3: string?,
	score: number?
)
	local userId = toUserId(target)
	if not userId then
		return
	end
	self:_submit(userId, function()
		GameAnalytics:addProgressionEvent(userId, {
			progressionStatus = GameAnalytics.EGAProgressionStatus[status],
			progression01 = p1,
			progression02 = p2,
			progression03 = p3,
			score = score,
		})
	end)
end

--[[ A Gamebeast marker for one player. See the header for the taxonomy.

	Players only: every marker in this game is about somebody, and a userId whose player has left
	would be resolved by the SDK to nothing. A dropped marker is the right failure, so it is quiet. ]]
function AnalyticsService.Marker(self, player: Player?, markerType: string, data: { [string]: any }?)
	if not (self._gamebeast and typeof(player) == "Instance" and player:IsA("Player")) then
		return
	end
	pcall(function()
		self._gamebeast:SendPlayerMarker(player, markerType, data or {})
	end)
end

--- Tips and bay collections, summed per session. See `PassiveIncome` in the header.
function AnalyticsService._addPassive(self, player: Player, field: "tips" | "collects", amount: unknown)
	local clamped = toAmount(amount)
	if not clamped then
		return
	end
	local totals = self._passive[player.UserId]
	if not totals then
		totals = { tips = 0, tipCount = 0, collects = 0, collectCount = 0 }
		self._passive[player.UserId] = totals
	end
	totals[field] += clamped
	if field == "tips" then
		totals.tipCount += 1
	else
		totals.collectCount += 1
	end
end

function AnalyticsService._flushPassive(self, player: Player)
	local totals = self._passive[player.UserId]
	self._passive[player.UserId] = nil
	if totals then
		self:Marker(player, "PassiveIncome", totals)
	end
end

--[[ PUBLIC (DevProductsHandler) - a dev product that was just GRANTED, for Gamebeast's revenue view.

	Called from inside the grant, after it succeeded, so a receipt Roblox re-delivers for a purchase
	already in the profile's cache is never counted twice. That is the opposite trade to GA's
	`ReportReceipt` below, and on purpose: GA dedupes on its side, Gamebeast's docs say to call this
	only for a NEW grant. Game passes need nothing; the SDK hooks those itself. ]]
function AnalyticsService.ReportGrantedPurchase(self, receiptInfo)
	if not self._gamebeast then
		return
	end
	pcall(function()
		self._gamebeast:SendNewPurchaseGrantedMarker(receiptInfo)
	end)
end

--[[ PUBLIC (DevProductsHandler) — a receipt, as a Robux business event.

	`task.spawn` because the SDK's handler calls `GetProductInfo`, which yields and can fail, and
	the caller is inside `ProcessReceipt` where a yield delays granting somebody something they have
	already paid for. ]]
function AnalyticsService.ReportReceipt(self, receiptInfo)
	task.spawn(function()
		pcall(function()
			GameAnalytics:ProcessReceiptCallback(receiptInfo)
		end)
	end)
end

--[[ dim01 = which world, dim02 = tutorial done or not. Both are re-read rather than remembered, and
	both are skipped until the session is live — dimensions are the one thing `_submit` cannot buffer,
	because the SDK rejects them outright before ready rather than queueing them.

	NOT the SDK's own `isPlayerReady`, which returns true before the session start it appears to
	guard. ]]
function AnalyticsService.RefreshDimensions(self, player: Player?)
	if not (player and player.Parent and self._ready[player.UserId]) then
		return
	end

	local World = Shard.get("WorldService")
	if World then
		GameAnalytics:setCustomDimension01(player.UserId, clean(WorldConfig.displayName(World:worldOf(player))))
	end

	local Tutorial = Shard.get("TutorialService")
	local done = Tutorial ~= nil and Tutorial:isFinished(player)
	GameAnalytics:setCustomDimension02(player.UserId, if done then "Onboarded" else "New")
end

-- === The tutorial funnel ====================================================
-- Called by TutorialService, which is the only place that can tell "reached" from "finished".

--- Reached beat `index`. Once per session per beat: a player who rejoins mid-tutorial resumes onto a
--- beat they have already been counted on, and re-reporting it would inflate that step against the
--- ones after it — the one distortion that makes a drop-off chart lie in a direction somebody acts on.
function AnalyticsService.TutorialReached(self, player: Player, index: number, stepId: string)
	local id = string.format("Tutorial:Step%d:%s", index, beatLabel(stepId))
	if not (self._once[player.UserId] and self._once[player.UserId][id]) then
		self:Marker(player, "TutorialStep", { step = index, beat = tostring(stepId), stage = "Reached" })
	end
	self:DesignOnce(player, id)
end

--- ...and finished it. A separate event, because "reached" only proves they SAW the step; the gap
--- between the two is exactly what the board card asked to be able to see.
function AnalyticsService.TutorialFinished(self, player: Player, index: number, stepId: string)
	local id = string.format("Tutorial:Step%d:%s:Complete", index, beatLabel(stepId))
	if not (self._once[player.UserId] and self._once[player.UserId][id]) then
		self:Marker(player, "TutorialStep", { step = index, beat = tostring(stepId), stage = "Completed" })
	end
	self:DesignOnce(player, id)
end

function AnalyticsService.TutorialComplete(self, player: Player)
	if not (self._once[player.UserId] and self._once[player.UserId]["Tutorial:Complete"]) then
		self:Marker(player, "TutorialCompleted")
	end
	self:DesignOnce(player, "Tutorial:Complete")
	self:Progression(player, "Complete", "Tutorial")
	task.spawn(function()
		self:RefreshDimensions(player)
	end)
end

--- Where they gave up. The step index is on the event so the skip chart lines up against the funnel.
function AnalyticsService.TutorialSkipped(self, player: Player, index: number?, stepId: string?)
	self:Marker(player, "TutorialSkipped", { step = index or 0, beat = if stepId then tostring(stepId) else "none" })
	if index and stepId then
		self:DesignOnce(player, string.format("Tutorial:Skip:Step%d:%s", index, beatLabel(stepId)))
	else
		self:DesignOnce(player, "Tutorial:Skip")
	end
	self:Progression(player, "Fail", "Tutorial", nil, nil, index)
	task.spawn(function()
		self:RefreshDimensions(player)
	end)
end

-- === The first car ==========================================================
--[[ Called by `FirstCarService`, which is the only thing that knows a car is somebody's FIRST.

	WHY THIS IS A FUNNEL OF ITS OWN AND NOT THREE MORE TUTORIAL STEPS. `CarryConfig`'s header sets
	out the question the carry feature exists to answer: does a player who is handed a car actually
	put it on a bay, or does the extra step lose them. Nothing was measuring it. The tutorial funnel
	cannot, because it only counts players who are IN the tutorial, and the interesting half of that
	question is everybody else: the skippers, the returning players, and anybody who arrives when a
	future build ships with the onboarding off.

	THREE EVENTS AND THE GAP BETWEEN THE FIRST TWO IS THE ANSWER. `Carried` is the car landing in
	their hands, `Placed` is it reaching a bay, and `Abandoned` is the session ending with it still
	held. Carried minus Placed is the size of the problem; Abandoned says how much of that is people
	who left rather than people who are still walking.

	ONCE PER PROFILE, NOT PER SESSION, and the profile is what enforces that (`CarryConfig.Guide`'s
	`ProfileKey`). `DesignOnce` dedupes within a session only, so a player who logged off holding
	their first car and came back to it would otherwise report step one twice and make the drop-off
	look smaller than it is. ]]

--[[ The guide trail look this player is assigned, for `guideStyle` on the three markers below: the
	A/B of Modern against Classic is read off the gap between Carried and Placed, per look
	(`GuideTrailConfig.Remote`).

	The same value the client draws from (Gamebeast applies the player's group to both), and the same
	fallback when there is none. Never yields: before the configs have loaded it answers with the
	fallback, as the client would. Remembered per player because `Abandoned` fires as they leave,
	when the SDK may already have dropped their view. ]]
function AnalyticsService._guideStyle(self, player: Player): string
	local remote = GuideTrailConfig.Remote
	local value: unknown = nil
	if remote.Enabled then
		pcall(function()
			local configs = Gamebeast:GetService("Configs")
			if configs:IsReady() then
				value = configs:GetForPlayer(player, remote.Path)
			end
		end)
	end
	if value == "Modern" or value == "Classic" or value == "Off" then
		self._guideStyles[player.UserId] = value :: string
		return value :: string
	end
	return self._guideStyles[player.UserId] or GuideTrailConfig.Style
end

--[[ A car is in this player's hands for the first time.

	`Placed` is deliberately NOT implied by this one. A player can be handed a car, walk away, and
	come back to it three sessions later; the funnel has to be able to say that happened. ]]
function AnalyticsService.FirstCarCarried(self, player: Player)
	self:Marker(player, "FirstCarCarried", { guideStyle = self:_guideStyle(player) })
	self:DesignOnce(player, "FirstCar:Carried")
	self:Progression(player, "Start", "FirstCar")
end

--- ...and it reached a bay. The end of the flow, and the number the A/B against automatic parking
--- is read from.
function AnalyticsService.FirstCarPlaced(self, player: Player)
	self:Marker(player, "FirstCarPlaced", { guideStyle = self:_guideStyle(player) })
	self:DesignOnce(player, "FirstCar:Placed")
	self:Progression(player, "Complete", "FirstCar")
end

--[[ They left still holding it.

	A FAIL AND NOT A NEUTRAL EXIT, even though nothing was lost: the car is in their collection
	either way (`CarryConfig` note 1) and they can park it off the Cars Inventory screen whenever
	they like. It is scored as a failure because what is being measured is whether the REWARD
	LANDED, and a player who logged off with the prize still in their hands did not see it land.

	It is the one event of the three that can fire more than once across a profile's life, because
	the session can end mid-carry more than once before the car ever reaches a bay. Within a
	session `DesignOnce` still holds it to one. ]]
function AnalyticsService.FirstCarAbandoned(self, player: Player)
	self:Marker(player, "FirstCarAbandoned", { guideStyle = self:_guideStyle(player) })
	self:DesignOnce(player, "FirstCar:Abandoned")
	self:Progression(player, "Fail", "FirstCar")
end

-- === PUBLIC (ReviveService) =================================================

--- A Robux prompt was SHOWN. Deliberately not deduped: a second prompt in a session is conversion
--- signal, not noise, and this game only ever prompts from one place.
---
--- `reason` (2026-10-15) is `CashService`'s top-up sentence, turned into `context` on the marker: what
--- the player was short for (`TOP_UP_CONTEXTS`). Absent for every prompt that is not a top-up.
function AnalyticsService.PromptShown(self, player: Player, productId: number, reason: string?)
	local name = productNames[productId] or clean(tostring(productId))
	self:Design(player, "Monetization:Prompt:Product:" .. name)
	self:Marker(player, "PurchasePrompted", { product = name, productId = productId, context = topUpContext(reason) })
end

-- === Subscriptions ==========================================================

--- One optional dependency, fetched and warned about in one line, so a service being off costs its
--- own events and nothing else.
function AnalyticsService._need(self, name: string, why: string)
	local service = Shard.get(name)
	if not service then
		self.log:warn(string.format("No %s — %s cannot be counted.", name, why))
	end
	return service
end

--[[ A service's signal, or a stand-in that connects to nothing (2026-10-15). `getSignal` answers nil
	for a name the service never declared, and `:Connect` on that nil would end this service's `start`
	and take every event after it down too. Used for the signals added in the 2026-10-15 pass, which
	live in other people's files: one of them out of step with this one (a half-synced edit, a rename)
	costs its own events and one warning. ]]
local NO_SIGNAL = {
	Connect = function()
		return { Disconnect = function() end }
	end,
}
function AnalyticsService._signal(self, service, name: string)
	local signal = service and service:getSignal(name)
	if signal then
		return signal
	end
	self.log:warn(string.format("No %s signal to listen to, so it cannot be counted.", name))
	return NO_SIGNAL
end

--- Cash in and out, as resource events, so the dashboard's economy view balances by itself.
function AnalyticsService._watchEconomy(self)
	local Garage = self:_need("GarageService", "collections and sales")
	if Garage then
		self._trove:Add(Garage:getSignal("CashCollected"):Connect(function(player: Player, amount: number, bay: number)
			self:Resource(player, "Source", amount, "Collect", "Bay" .. tostring(bay))
			self:_addPassive(player, "collects", amount)
		end))
		self._trove:Add(
			Garage:getSignal("CarSold"):Connect(function(player: Player, body: string, tier: number, amount: number, source: string?)
				self:Resource(player, "Source", amount, "Sale", clean(body))
				self:Design(player, "Car:Sold:" .. clean(body), tier)
				--- `source` since 2026-10-15: a buyer, the sell lot, a full inventory, or a duplicate.
				self:Marker(player, "CarSold", {
					body = tostring(body),
					tier = tier,
					cash = toAmount(amount) or 0,
					source = if type(source) == "string" then source else "Unknown",
				})
			end)
		)
	end

	--[[ TIPS, the dealership's income since the bays stopped earning (2026-09-28;
		`GarageConfig.Income.Passive`). Without this the economy view would lose its biggest source
		the day `Collect` stopped firing, and the whole lot would read as money leaving. Keyed by the
		body the customer admired, the same way a sale is, so the dashboard can see which cars pull a
		crowd. The OFFLINE tips (`OfflineService`) are not a signal and are not in here — a known gap,
		small next to the live crowd, and closing it would mean a signal on that service for one event. ]]
	local Customer = self:_need("CustomerService", "customer tips")
	if Customer then
		self._trove:Add(Customer:getSignal("CustomerPaid"):Connect(function(player: Player, amount: number, _bay: number, body: string)
			self:Resource(player, "Source", amount, "Tip", clean(body))
			self:_addPassive(player, "tips", amount)
		end))
	end

	--[[ CASH BOUGHT WITH ROBUX (`CashService`). Booked as a SOURCE like any other way money enters
		the game, which is the only thing that keeps the economy view balancing: a pack that paid in
		without an event here would show up as a lot of spend with no matching income and read as a
		duping bug on the dashboard.

		The Robux side of the same purchase is already reported by `DevProductsHandler` as a business
		event, so this is the dollars and that is the Robux. They are two currencies and GA wants
		both. `Product` is declared in `availableResourceItemTypes` above, and an item type missing
		from that list is silently dropped. ]]
	local Cash = self:_need("CashService", "cash pack purchases")
	if Cash then
		self._trove:Add(
			Cash:getSignal("CashGranted"):Connect(function(player: Player, amount: number, packKey: string)
				self:Resource(player, "Source", amount, "Product", clean(packKey))
				self:Design(player, "Monetization:Bought:Cash:" .. clean(packKey))
				self:Marker(player, "CashPackBought", { pack = tostring(packKey), cash = toAmount(amount) or 0 })
			end)
		)
	end

	local Upgrade = self:_need("UpgradeService", "upgrade spend")
	if Upgrade then
		self._trove:Add(
			Upgrade:getSignal("UpgradeBought"):Connect(function(player: Player, key: string, level: number, cost: number)
				self:Resource(player, "Sink", cost, "Upgrade", clean(key))
				self:Design(player, "Upgrade:Bought:" .. clean(key), level)
				self:Marker(player, "UpgradeBought", { upgrade = tostring(key), level = level, cost = toAmount(cost) or 0 })
			end)
		)
		self._trove:Add(
			Upgrade
				:getSignal("BayUpgradeBought")
				:Connect(function(player: Player, index: number, level: number, cost: number)
					self:Resource(player, "Sink", cost, "Upgrade", "Bay")
					self:Design(player, "Upgrade:Bought:Bay", level)
					self:Marker(player, "UpgradeBought", { upgrade = "Bay", bay = index, level = level, cost = toAmount(cost) or 0 })
					--[[ The bay number rides as a second event rather than in the id above, so the
						headline "how much bay upgrading happens" stays one line on the chart.

						MILESTONES ONLY, AND THAT IS A CARDINALITY LIMIT RATHER THAN A TASTE CALL.
						This fired on every level while the ladder had eleven rungs — twelve bays x
						eleven levels is 132 distinct design ids, comfortably inside GameAnalytics'
						per-game cap. `UpgradeConfig.Bay.MaxLevel` went to 100 on 2026-08-21, which
						would have made it 1,200, and a design hierarchy over the cap does not warn:
						the surplus ids are simply dropped, so the funnel would have gone quietly
						wrong rather than loudly. Bucketing to the first purchase and then every
						tenth level puts it back at 132 and keeps the shape of the funnel, which was
						never going to be read a level at a time anyway.

						Every level is bought singly, so no boundary can be stepped over. ]]
					if level == 2 or level % 10 == 0 then
						self:DesignOnce(player, string.format("Upgrade:Bay%d:Level%d", index, level))
					end
				end)
		)
	end

	--[[ The plaza market. It is the ONLY cash sink in the game that buys a car rather than a number,
		which is exactly why it wants its own item type rather than riding on `Sale`: the dashboard
		question it answers is "is anybody using the market, and on what?", and folding it into the
		garage's sales would net a sink against a source and show neither. ]]
	local Deals = self:_need("CarDealService", "market purchases")
	if Deals then
		self._trove:Add(
			Deals:getSignal("CarBought"):Connect(function(player: Player, body: string, tier: number, _paint, price: number)
				self:Resource(player, "Sink", price, "Deal", clean(body))
				--- The TIER is the value, so the chart answers "how far up the ladder are people
				--- buying?" rather than just "how often". Same shape as `Car:Sold`.
				self:Design(player, "Deal:Bought:" .. clean(body), tier)
				--- ...and the first purchase ever, which is the funnel step that matters: a player who
				--- has bought once has understood that the plaza is a shop.
				self:DesignOnce(player, "Deal:FirstBuy")
				self:Marker(player, "CarBought", { body = tostring(body), tier = tier, price = toAmount(price) or 0, source = "Market" })
			end)
		)
	end

	local Quest = self:_need("QuestService", "quest rewards")
	if Quest then
		self._trove:Add(Quest:getSignal("QuestCompleted"):Connect(function(player: Player, id: string)
			self:Design(player, "Quest:Completed:" .. clean(id))
			self:Marker(player, "QuestCompleted", { quest = tostring(id) })
		end))
		self._trove:Add(
			Quest:getSignal("QuestClaimed"):Connect(function(player: Player, id: string, reward: number)
				self:Design(player, "Quest:Claimed:" .. clean(id))
				self:Marker(player, "QuestClaimed", { quest = tostring(id), reward = toAmount(reward) or 0 })
				self:Resource(player, "Source", reward, "Quest", clean(id))
			end)
		)
	end
end

--- A run, start to finish, plus what happened on the road.
function AnalyticsService._watchRuns(self)
	local Race = self:_need("RaceService", "runs")
	local World = Shard.get("WorldService")
	if Race then
		self._trove:Add(Race:getSignal("RaceEntered"):Connect(function(player: Player)
			local world = if World then clean(WorldConfig.displayName(World:worldOf(player))) else "Unknown"
			self:Design(player, "Run:Start:" .. world)
			self:Progression(player, "Start", world)
			local runs = (self._runs[player.UserId] or 0) + 1
			self._runs[player.UserId] = runs
			local car = self:_startCar(player)
			--- What `RunEnded` reports beyond the payout (header, the 2026-10-15 pass). Filled by the
			--- wreck, revive, steal and speed-trap subscriptions below.
			self._run[player.UserId] = { car = car, wrecks = 0, revives = 0, steals = 0, traps = 0, trapCash = 0 }
			--- `heat`: the player's A/B arm (`PoliceConfig.Heat.Remote`), so the run funnel splits by it.
			self:Marker(player, "RunStarted", { world = world, runNumber = runs, car = car, heat = PoliceConfig.heatOn(player) })
		end))

		--[[ WHAT ENDED IT. Every wreck is counted, revived or not, and the last one's cause is the
			run's ending unless it banked. nil from `wreckRace` is the health bar running out, which is
			traffic and obstacles. ]]
		self._trove:Add(self:_signal(Race, "RaceWrecked"):Connect(function(player: Player, cause: string?)
			local label = if type(cause) == "string" and cause ~= "" then cause else "health"
			local run = self._run[player.UserId]
			if run then
				run.wrecks += 1
				run.cause = label
			end
			self:Design(player, "Run:Wreck:" .. clean(label))
		end))
		self._trove:Add(self:_signal(Race, "RaceRevived"):Connect(function(player: Player)
			local run = self._run[player.UserId]
			if run then
				run.revives += 1
			end
		end))
	end

	--- Speed traps: GA gets each one as a source; Gamebeast gets the run's count and total on `RunEnded`.
	local Traps = Shard.get("SpeedTrapService")
	if Traps then
		self._trove:Add(self:_signal(Traps, "TrapPaid"):Connect(function(player: Player, cash: number, rating: string)
			self:Resource(player, "Source", cash, "SpeedTrap", clean(rating))
			local run = self._run[player.UserId]
			if run then
				run.traps += 1
				run.trapCash += toAmount(cash) or 0
			end
		end))
	end

	local Reward = self:_need("RewardService", "run outcomes")
	if Reward then
		self._trove:Add(
			Reward
				:getSignal("RunSettled")
				:Connect(function(player: Player, cash: number, studs: number, banked: boolean, bonus: number?, misses: number?, rubs: number?)
					local world = if World then clean(WorldConfig.displayName(World:worldOf(player))) else "Unknown"
					local distance = math.max(math.floor(studs), 0)
					local run = self._run[player.UserId] or {}

					--[[ Banked or wrecked is THE number this game lives on — it is the difference
						between a run that paid and a run that did not, and the whole getaway-truck
						design turns on it. Distance rides as the value on both, so the dashboard can
						show "how far do people get before they die" against "how far when they win"
						without a second event. ]]
					self:Design(player, if banked then "Run:Banked" else "Run:Wrecked", distance)
					self:Progression(player, if banked then "Complete" else "Fail", world, nil, nil, distance)
					self:Resource(player, "Source", cash, "Run", world)
					self:Marker(player, "RunEnded", {
						world = world,
						banked = banked == true,
						distance = distance,
						cash = toAmount(cash) or 0,
						runNumber = self._runs[player.UserId] or 0,
						heat = PoliceConfig.heatOn(player),
						--- The 2026-10-15 fields. `cause` "quit" is a run that neither banked nor
						--- wrecked: a leave, a death in the seat, an entry that fell over.
						car = run.car or "Unknown",
						cause = if banked then "banked" else (run.cause or "quit"),
						wrecks = run.wrecks or 0,
						revives = run.revives or 0,
						steals = run.steals or 0,
						nearMisses = if type(misses) == "number" then misses else 0,
						rubs = if type(rubs) == "number" then rubs else 0,
						bonus = toAmount(bonus) or 0,
						speedTraps = run.traps or 0,
						trapCash = run.trapCash or 0,
					})
				end)
		)
		self._trove:Add(
			Reward:getSignal("CarLeveled"):Connect(function(player: Player, body: string, level: number)
				self:Design(player, "Car:Leveled:" .. clean(body), level)
				self:Marker(player, "CarLeveled", { body = tostring(body), level = level })
			end)
		)
	end

	local Steal = self:_need("StealService", "steals")
	if Steal then
		self._trove:Add(Steal:getSignal("CarStolen"):Connect(function(player: Player, index: number)
			self:Design(player, "Steal:Complete", index)
			self:Marker(player, "CarStolen", { index = index })
			local run = self._run[player.UserId]
			if run and type(index) == "number" then
				run.steals = math.max(run.steals, index)
			end
		end))
	end
end

--- What ends up on the forecourt, and where they play.
function AnalyticsService._watchCollection(self)
	local Garage = Shard.get("GarageService")
	if Garage then
		self._trove:Add(
			Garage:getSignal("CarParked"):Connect(function(player: Player, body: string, tier: number)
				self:Design(player, "Car:Parked:" .. clean(body), tier)
				self:Marker(player, "CarParked", { body = tostring(body), tier = tier })
			end)
		)
	end

	local World = self:_need("WorldService", "world unlocks")
	if World then
		self._trove:Add(World:getSignal("WorldUnlocked"):Connect(function(player: Player, index: number, cost: number)
			local name = clean(WorldConfig.displayName(index))
			self:DesignOnce(player, "World:Unlocked:" .. name)
			self:Resource(player, "Sink", cost, "World", name)
			self:Marker(player, "WorldUnlocked", { world = name, cost = toAmount(cost) or 0 })
		end))
		self._trove:Add(World:getSignal("WorldChanged"):Connect(function(player: Player, index: number)
			self:Design(player, "World:Changed:" .. clean(WorldConfig.displayName(index)))
			self:Marker(player, "WorldChanged", { world = clean(WorldConfig.displayName(index)) })
			--- dim01 IS the world, so it moves with this or every later event is filed under the
			--- one they happened to join in.
			task.spawn(function()
				self:RefreshDimensions(player)
			end)
		end))
	end
end

--[[ The body a run starts in: the car picked on the SELECT CAR screen, the answer `SpeedTrapService`
	falls back on too. "Unknown" rather than nil, so the property is never missing from a marker. ]]
function AnalyticsService._startCar(self, player: Player): string
	local StartCar = Shard.get("StartCarService")
	if not StartCar then
		return "Unknown"
	end
	local World = Shard.get("WorldService")
	local ok, body = pcall(function()
		return (StartCar:carFor(player, if World then World:worldOf(player) else nil))
	end)
	return if ok and type(body) == "string" then body else "Unknown"
end

--- Sellers and buyers: the two halves of the lot's market since the plaza closed (header).
function AnalyticsService._watchMarket(self)
	local Seller = Shard.get("SellerService")
	if Seller then
		self._trove:Add(self:_signal(Seller, "SellerArrived"):Connect(function(player: Player, info)
			self:Marker(player, "SellerArrived", {
				body = tostring(info.body),
				tier = info.tier,
				band = tostring(info.band),
				price = toAmount(info.price) or 0,
				first = info.first == true,
			})
		end))

		--[[ ONE MARKER PER VISIT, whatever happened, so "how many sellers end in a sale" is one
			breakdown of one event. A purchase is also a `CarBought`, the marker the plaza used, so a
			board card built on it carries on counting with only the source changed. ]]
		self._trove:Add(
			self:_signal(Seller, "SellerResolved")
				:Connect(function(player: Player, info, outcome: string, viewed: boolean, shortCash: boolean)
					local body = tostring(info.body)
					self:Marker(player, "SellerResolved", {
						outcome = tostring(outcome),
						body = body,
						tier = info.tier,
						band = tostring(info.band),
						price = toAmount(info.price) or 0,
						first = info.first == true,
						viewed = viewed == true,
						shortCash = shortCash == true,
					})
					self:Design(player, "Seller:" .. clean(outcome))
					if outcome == "Bought" then
						self:Resource(player, "Sink", info.price, "Seller", clean(body))
						self:Design(player, "Seller:Bought:" .. clean(body), info.tier)
						self:DesignOnce(player, "Seller:FirstBuy")
						self:Marker(player, "CarBought", {
							body = body,
							tier = info.tier,
							price = toAmount(info.price) or 0,
							source = "Seller",
							band = tostring(info.band),
						})
					end
				end)
		)
	end

	local Buyer = Shard.get("BuyerService")
	if Buyer then
		local function meta(player: Player, carId: string)
			local byCar = self._offerMeta[player.UserId]
			return byCar and byCar[carId]
		end

		--[[ BOTH ENDS OF AN OFFER, and the source rides from one to the other in session memory, so
			the tutorial's buyer and the live ones can be told apart at the answer too. ]]
		local function resolved(player: Player, carId: string, offer, outcome: string)
			local body, tier = bodyAndTier(carId)
			local known = meta(player, carId)
			self:Marker(player, "BuyerOfferResolved", {
				outcome = outcome,
				body = body,
				tier = tier,
				amount = toAmount(type(offer) == "table" and offer.Amount) or 0,
				kind = if type(offer) == "table" and type(offer.Kind) == "string" then offer.Kind else "Regular",
				source = if known then known.source else "Unknown",
				--- Answering is done on the offer screen, so an answer was always viewed.
				viewed = outcome == "Accepted" or outcome == "Declined" or (known ~= nil and known.viewed == true),
			})
			self:Design(player, "Buyer:" .. outcome)
			local byCar = self._offerMeta[player.UserId]
			if byCar then
				byCar[carId] = nil
			end
		end

		self._trove:Add(self:_signal(Buyer, "OfferMade"):Connect(function(player: Player, carId: string, offer, source: string)
			local body, tier = bodyAndTier(carId)
			local Garage = Shard.get("GarageService")
			local value = if Garage then (Garage:marketValueOf(player, carId) or 0) else 0
			local amount = toAmount(offer.Amount) or 0
			local byCar = self._offerMeta[player.UserId]
			if not byCar then
				byCar = {}
				self._offerMeta[player.UserId] = byCar
			end
			byCar[carId] = { source = tostring(source), viewed = false }
			self:Marker(player, "BuyerOffer", {
				body = body,
				tier = tier,
				amount = amount,
				value = toAmount(value) or 0,
				--- The offer against the car's market value, to two places: what the "is it a good
				--- offer" question is answered from.
				ratio = if value > 0 then math.floor(amount / value * 100 + 0.5) / 100 else 0,
				kind = if type(offer.Kind) == "string" then offer.Kind else "Regular",
				source = tostring(source),
			})
			self:Design(player, "Buyer:Offer:" .. clean(source))
		end))
		self._trove:Add(self:_signal(Buyer, "OfferViewed"):Connect(function(player: Player, carId: string)
			local known = meta(player, carId)
			if known then
				known.viewed = true
			end
		end))
		self._trove:Add(self:_signal(Buyer, "OfferAnswered"):Connect(function(player: Player, carId: string, accepted: boolean, offer)
			resolved(player, carId, offer, if accepted then "Accepted" else "Declined")
		end))
		self._trove:Add(self:_signal(Buyer, "OfferDropped"):Connect(function(player: Player, carId: string, offer, reason: string)
			resolved(player, carId, offer, tostring(reason))
		end))
	end
end

--- The cash and rewards that had no events: daily rewards, codes, coming back, the workshop, the index.
function AnalyticsService._watchRewards(self)
	local Daily = Shard.get("DailyRewardService")
	if Daily then
		self._trove:Add(
			self:_signal(Daily, "Claimed"):Connect(function(player: Player, day: number, kind: string, amount: number?, body: string?)
				self:Marker(player, "DailyRewardClaimed", {
					day = day,
					kind = tostring(kind),
					amount = if type(amount) == "number" then amount else 0,
					body = if type(body) == "string" then body else nil,
				})
				self:DesignOnce(player, string.format("Daily:Claimed:Day%d", tonumber(day) or 0))
				if kind == "Cash" then
					self:Resource(player, "Source", amount, "Daily", string.format("Day%d", tonumber(day) or 0))
				end
			end)
		)
	end

	local Codes = Shard.get("CodesService")
	if Codes then
		self._trove:Add(self:_signal(Codes, "Redeemed"):Connect(function(player: Player, code: string, amount: number)
			self:Marker(player, "CodeRedeemed", { code = tostring(code), cash = toAmount(amount) or 0 })
			self:DesignOnce(player, "Code:Redeemed:" .. clean(code))
			self:Resource(player, "Source", amount, "Code", clean(code))
		end))
	end

	--[[ The WELCOME BACK screen. Without passive income its amount is paid when it is offered, so it
		is booked here; with passive income the bays pay it through `CashCollected` and only the marker
		is new. ]]
	local Offline = Shard.get("OfflineService")
	if Offline then
		self._trove:Add(
			self:_signal(Offline, "Welcomed")
				:Connect(function(player: Player, amount: number, away: number, buyers: number, banked: boolean)
					self:Marker(player, "OfflineEarnings", {
						cash = toAmount(amount) or 0,
						awayMinutes = math.floor((tonumber(away) or 0) / 60),
						buyers = tonumber(buyers) or 0,
					})
					if banked then
						self:Resource(player, "Source", amount, "Offline", "Tips")
					end
				end)
		)
		self._trove:Add(self:_signal(Offline, "Boosted"):Connect(function(player: Player, extra: number)
			self:Marker(player, "OfflineBoosted", { cash = toAmount(extra) or 0 })
			self:Resource(player, "Source", extra, "Offline", "Boost")
		end))
	end

	local Workshop = Shard.get("WorkshopService")
	if Workshop then
		self._trove:Add(self:_signal(Workshop, "Bought"):Connect(function(player: Player, cost: number, info)
			local kind = tostring(info.kind)
			local body = bodyAndTier(info.carId)
			self:Marker(player, "WorkshopBought", {
				kind = kind,
				body = body,
				part = if type(info.part) == "string" then info.part else nil,
				level = if type(info.level) == "number" then info.level else nil,
				cost = toAmount(cost) or 0,
			})
			self:Resource(player, "Sink", cost, "Workshop", clean(kind))
			self:Design(player, "Workshop:" .. clean(kind))
		end))
	end

	local Index = Shard.get("IndexRewardService")
	if Index then
		self._trove:Add(self:_signal(Index, "Claimed"):Connect(function(player: Player, body: string, total: number)
			self:Marker(player, "IndexRewardClaimed", { body = tostring(body), total = tonumber(total) or 0 })
		end))
	end
end

--[[ The end panel's answer (`AnalyticsEndChoice`): RACE AGAIN or HOME, after a run.

	ASKED FOR BY NAME (2026-10-15): how many players press RACE AGAIN on their first run, and how many
	go HOME, because whether that button stays on the panel during the tutorial is being decided on
	it. `tutorial` and `beat` are what pick the first run out: a tutorial run cannot be lost, so it
	ends on the bank beat and the panel answers with the player standing on `place`. `how` matters as
	much as `choice`, because in the tutorial the countdown goes HOME on its own and only a press of
	RACE AGAIN is a decision.

	ONE PER RUN, and only after a run this service saw start, which is also the whole of the rate
	limit on a remote a client could otherwise fire at will. ]]
local END_CHOICES = { replay = "RaceAgain", home = "Home" }
local END_HOWS = { press = true, auto = true }
local END_PANELS = { revive = true, bank = true, wreck = true }
function AnalyticsService._onEndChoice(self, player: Player, answer: unknown, how: unknown, panel: unknown)
	local choice = type(answer) == "string" and END_CHOICES[answer]
	if not (choice and type(how) == "string" and END_HOWS[how]) then
		return
	end
	local run = self._run[player.UserId]
	if not run or run.choice then
		return
	end
	run.choice = choice

	local Tutorial = Shard.get("TutorialService")
	local inTutorial = Tutorial ~= nil and TutorialConfig.isOn() and not Tutorial:isFinished(player)
	local beat = player:GetAttribute(TutorialConfig.StepAttribute)
	self:Marker(player, "RunEndChoice", {
		choice = choice,
		how = how,
		panel = if type(panel) == "string" and END_PANELS[panel] then panel else "unknown",
		runNumber = self._runs[player.UserId] or 0,
		tutorial = inTutorial,
		beat = if inTutorial and type(beat) == "string" and beat ~= "" then beat else "none",
	})
	self:Design(player, string.format("Run:Choice:%s:%s", choice, if how == "auto" then "Auto" else "Press"))
	if inTutorial then
		self:DesignOnce(player, "Tutorial:RunChoice:" .. choice)
	end
end

--- A screen opened on a client (`AnalyticsPageOpened`). Whitelisted and rate limited; see the constants.
function AnalyticsService._onPageOpened(self, player: Player, page: unknown)
	if type(page) ~= "string" or not self._trackedPages or not self._trackedPages[page] then
		return
	end
	local userId = player.UserId
	local seen = self._pages[userId]
	if not seen then
		seen = { count = 0, at = {} }
		self._pages[userId] = seen
	end
	local now = os.clock()
	if seen.count >= PAGE_CAP or (seen.at[page] and now - seen.at[page] < PAGE_COOLDOWN) then
		return
	end
	seen.at[page] = now
	seen.count += 1
	self:Marker(player, "PageOpened", { page = page })
	self:DesignOnce(player, "UI:Opened:" .. clean(page))
end

-- === The join funnel ========================================================

local function joinSeconds(join): number
	return math.floor((os.clock() - join.at) * 10 + 0.5) / 10
end

--[[ Logs Roblox funnel steps up to `step` for this join, including any between: a screen that
	recovered from COULDN'T LOAD goes straight to `playing`, and it did pass the steps it skipped
	reporting. `pcall` for `TutorialService._funnel`'s reason: Roblox analytics may be off or
	rate limited, and that must never reach the join. ]]
function AnalyticsService._joinStep(self, player: Player, join, step: number)
	for index = join.step + 1, step do
		pcall(function()
			RobloxAnalytics:LogFunnelStepEvent(player, JOIN_FUNNEL, join.session, index, JOIN_STEP_NAMES[index])
		end)
	end
	join.step = math.max(join.step, step)
end

function AnalyticsService._onJoined(self, player: Player)
	if self._joins[player.UserId] then
		return
	end
	local join = { at = os.clock(), session = HttpService:GenerateGUID(false), step = 0, phase = "joined" }
	self._joins[player.UserId] = join
	self:_joinStep(player, join, JOIN_STEPS.joined)
	--- The server's half of the wait, stamped once: `PlotService` loads the character only after the
	--- profile and the plot, so this is how long the client had nothing to stand on.
	player.CharacterAdded:Once(function()
		join.character = joinSeconds(join)
	end)
end

--[[ A phase from `JoinScreen` (`JoinProgress`). TRUST: a phase name checked against `JOIN_STEPS`,
	only ever forward and once each, plus numbers that only ride on the markers; nothing is paid or
	changed on it, and a join sends at most six. ]]
function AnalyticsService._onJoinProgress(self, player: Player, phase: unknown, data: unknown)
	local join = self._joins[player.UserId]
	if not join or join.done or type(phase) ~= "string" then
		return
	end
	local payload = if type(data) == "table" then data else {}
	join.memoryMb = clientNumber(payload.memoryMb, 100000) or join.memoryMb
	local seconds = joinSeconds(join)

	if phase == "failed" then
		if join.failed then
			return
		end
		join.failed = true
		local stage = if type(payload.stage) == "string" and JOIN_FAIL_STAGES[payload.stage] then payload.stage else "unknown"
		self:Marker(player, "JoinFailed", {
			stage = stage,
			lastPhase = join.phase,
			seconds = seconds,
			character = join.character,
			memoryMb = join.memoryMb,
		})
		self:Design(player, "Join:Failed:" .. beatLabel(stage), seconds)
		return
	end

	local step = JOIN_STEPS[phase]
	if not step or step <= join.step then
		return
	end
	join.phase = phase
	self:_joinStep(player, join, step)
	if phase == "started" then
		--- A module name and a phase, nothing else (`BootGuard.timings` keys), capped for the dashboard.
		local slowest = payload.slowest
		if type(slowest) == "string" and #slowest <= 64 and slowest:match("^[%w_]+%.%a+$") then
			join.slowest = slowest
			join.slowestSeconds = clientNumber(payload.slowestSeconds, 900)
		end
	end
	if phase ~= "playing" then
		return
	end

	join.done = true
	local Tutorial = Shard.get("TutorialService")
	self:Marker(player, "JoinFinished", {
		seconds = seconds,
		character = join.character,
		screen = clientNumber(payload.screen, 900),
		loaded = clientNumber(payload.loaded, 900),
		started = clientNumber(payload.started, 900),
		spawned = clientNumber(payload.spawned, 900),
		assets = clientNumber(payload.assets, 900),
		assetCount = clientNumber(payload.assetCount, 100000),
		assetsFetched = clientNumber(payload.assetsFetched, 100000),
		slowest = join.slowest,
		slowestSeconds = join.slowestSeconds,
		memoryMb = join.memoryMb,
		textureMb = clientNumber(payload.textureMb, 100000),
		meshMb = clientNumber(payload.meshMb, 100000),
		partsMb = clientNumber(payload.partsMb, 100000),
		soundMb = clientNumber(payload.soundMb, 100000),
		luaMb = clientNumber(payload.luaMb, 100000),
		recovered = join.failed == true,
		onboarded = Tutorial ~= nil and Tutorial:isFinished(player),
	})
	self:Design(player, "Join:Finished", seconds)
end

--- Left before the overlay lifted. Sent from `PlayerRemoving`, where the Player still resolves.
function AnalyticsService._onJoinLeft(self, player: Player)
	local join = self._joins[player.UserId]
	self._joins[player.UserId] = nil
	if not join or join.done then
		return
	end
	local seconds = joinSeconds(join)
	self:Marker(player, "JoinAbandoned", {
		lastPhase = join.phase,
		step = join.step,
		seconds = seconds,
		character = join.character,
		memoryMb = join.memoryMb,
		failed = join.failed == true,
	})
	self:Design(player, "Join:Abandoned:" .. beatLabel(join.phase), seconds)
end

return AnalyticsService
