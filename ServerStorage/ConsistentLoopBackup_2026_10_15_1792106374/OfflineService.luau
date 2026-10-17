--[[
	OfflineService  (server)
	------------------------
	The WELCOME BACK screen's server half: how long the player was gone, what their lot is holding,
	and the one button that hands it over.

	=== WITHOUT PASSIVE INCOME IT PAYS SIMULATED TIPS — 2026-09-28 ============================

	WHAT IT WAS: everything under the next heading — the screen showed what the bays held and its
	button swept them. WHAT IT IS, with `GarageConfig.Income.Passive` off: the bays hold nothing, so
	the number is what the showroom's customers would have tipped while the player was away
	(`_simulate`, over `CustomerConfig.simulate`), and it is BANKED WHEN THE OFFER IS MADE rather than
	on the press, because nothing but this server's memory is holding it (`_evaluate` has why). The
	boost, the prompt and the one-screen-per-session rules below are unchanged. The next heading is
	still exactly true with passive income on.

	=== IT ADDS NO ECONOMY. NOT ONE LINE — EXCEPT THE BOOST, WHICH IS ARITHMETIC ==============

	`GarageConfig`'s header is explicit that offline income needed no code — a bay stores the
	`os.time()` it was last collected and owes `min(now - that, cap) * rate`, so the clock ran while
	the player was logged out and the money has been right since the day that formula was written.
	This service does not compute a payout, does not add cash, and does not touch a `Collected`
	stamp. It asks `GarageService.getPending` what the lot is holding, and its claim button calls
	`GarageService.collectAll` — the AUTO COLLECT sweep, which is a loop over the same `_collect` a
	foot on a mat runs.

	That is the whole design constraint. Every payout in this game goes through one function, so
	"collected on the welcome screen" and "collected by walking" can never disagree about what a bay
	was worth.

	THE BOOST IS THE ONE EXCEPTION AND IT IS DELIBERATELY A NARROW ONE. `_pay` still runs exactly one
	`collectAll`, and the boost multiplies THE NUMBER THAT CAME BACK — one `addCash` for the
	difference, on a figure this service did not compute. So the bays are still asked once, still by
	the same function, and there is still no second answer to "what was the lot holding". The rule to
	keep is not "no `addCash`", it is: NOTHING HERE MAY EVER ASK THE BAYS A SECOND TIME.

	=== THE BOOST IS BANKED, NEVER APPLIED OUT OF THE RECEIPT ==================================

	`OfflineConfig.Boost.ProfileKey` holds boosts bought and not yet spent, the same shape
	`ReviveConfig.ProfileKey` holds lives in and for the same reason: a receipt lands when it lands.
	`grantBoost` therefore always banks first and pays second, and it only pays at all when the
	player is demonstrably sitting in front of the screen they bought it for (`_awaiting`, set when
	this service opened the prompt and cleared when the prompt closes unbought). Every other
	receipt — a retry from two sessions ago, a purchase whose screen has already been dismissed —
	leaves a boost on the profile that the next WELCOME BACK screen offers back for free.

	A BOOST IS ONLY SPENT ON A LOT THAT HAD SOMETHING ON IT. `_pay` sweeps before it spends, so a
	multiplier can never be burnt on an empty lot — which is the one way a player could pay Robux
	and watch the number not move.

	=== THE ONE PIECE OF STATE IT OWNS =========================================================

	`LastSeen`, a top-level `os.time()` on the profile, written on join, on a slow timer, and on the
	way out. It answers "how long were you gone" and nothing else; the payout does not read it. That
	split is what makes it safe for the stamp to be wrong — a server that dies without writing it
	makes the next session's headline wrong by a session's length, and the money still correct to
	the second.

	=== WHY THE CLIENT ASKS RATHER THAN THE SERVER PUSHING =====================================

	The profile lands on the join path, which is comfortably before the client's controllers have
	finished starting — so a remote fired the moment the answer is known is a remote nobody hears.
	The offer is therefore PARKED and the client pings when its screen is built (`OfflineReady`),
	which resolves both orders with no timer: whichever of the two happens second does the sending.
	`OfflineConfig.ReadyTimeout` drops an offer nobody ever asked for, and dropping one costs
	nothing at all — the money is still standing on the bays.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local OfflineConfig = require(ReplicatedStorage.shared.Configs.OfflineConfig)
--[[ The crowd's own numbers, for simulating it while the player is away (`_simulate`). A CONFIG and
	not `CustomerService`: what is needed is pure arithmetic over the lot, and that service's state is
	rigs walking a plot this player is not standing on. ]]
local CustomerConfig = require(ReplicatedStorage.shared.Configs.CustomerConfig)
--[[ A CONFIG, NOT `UpgradeService`. All this needs is "how long does a bay hold cash for this
	player", which is a pure function of the upgrade table `GarageService` already hands out. Taking
	the service would add a dependency edge for a lookup. ]]
local UpgradeConfig = require(ReplicatedStorage.shared.Configs.UpgradeConfig)

local Data = require(script.Parent.Parent.Data)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

--[[ Everything the screen draws, in one table.

	ONE PAYLOAD RATHER THAN FIVE ARGUMENTS, the same call `ReviveService._offerPayload` makes and for
	the same reason: every field is drawn by one screen at one moment, and a positional list of five
	is a list nobody can add a sixth to safely. ]]
type Offer = {
	amount: number, -- whole dollars the lot is holding
	bays: number, -- how many bays are holding some of it
	away: number, -- seconds since we last saw them
	capped: boolean, -- were they away longer than a bay can hold?
	cap: number, -- ...and how long a bay holds for THIS player, seconds
	--[[ The boost, as three numbers the button draws itself from. `canBoost` is false when the feature
		is off OR when rbxsync has never been run, which reads as "there is no second button" rather
		than as "it is free" — an offer nobody can buy is worse than no offer, exactly as
		`ReviveService._tierFor` argues about a rung with no product behind it. ]]
	canBoost: boolean,
	multiplier: number, -- what it multiplies by, so the caption spells no number of its own
	price: number, -- Robux, for a player who owns none
	boosts: number, -- ...and how many they already own, which makes the button free
	buyers: number, -- buyers waiting on the lot right now, offline arrivals included (`BuyerService.catchUp`)
}

local OfflineService = Shard.new("OfflineService"):withDependencies({ "GarageService" })

--[[ For `AnalyticsService` (2026-10-15): what coming back is worth, which is a retention number, and
	the offline tips as a cash source (they were the known gap in its economy view). ]]
OfflineService:withSignals({
	--- (player, amount, away: number, buyers: number, banked: boolean) : the WELCOME BACK screen's
	--- offer was made. `banked` is whether `amount` was paid here (no passive income) or waits on the press.
	"Welcomed",
	--- (player, extra: number) : the 2x boost was applied; `extra` is the top-up over the 1x.
	"Boosted",
})

OfflineService:withRemoteEvents({
	-- server -> client (offer): put the WELCOME BACK screen up. Fired at most once per session.
	"OfflineEarnings",
	--[[ server -> client (amount, multiplier): the claim landed, and this is what actually changed
		hands. It is the real `collectAll` total rather than the offered figure, which is the same
		number plus however many seconds the player spent reading the screen.

		The multiplier rides along so the screen can say WHY the number is bigger than the one it was
		drawn with. 1 on an ordinary claim, including one where a boost was held but the lot turned
		out to be empty — the screen must never claim a multiplier that was not applied. ]]
	"OfflineCollected",
	--[[ server -> client (boosts): a purchase landed but there was nothing to spend it on right now,
		so it has been banked. Repaints the boost button as owned and unlocks it — which is what turns
		a slow receipt from a locked panel into a button the player can simply press. ]]
	"OfflineBoostState",
	{
		--[[ client -> server: my screen exists, so a remote sent now will be heard. Fired once, from
			the controller's `start`. It carries nothing — the player is the whole message. ]]
		OfflineReady = function(player: Player)
			OfflineService:_onReady(player)
		end,
		--[[ client -> server: they pressed one of the two collect buttons. `boost` is the ONLY thing
			the client is trusted with here and it is trusted with it as a request, not a fact — the
			server decides whether that means spending a stored boost, opening a Robux prompt, or
			nothing at all, and reads the count off the profile to do it. ]]
		OfflineClaim = function(player: Player, boost: unknown)
			OfflineService:_onClaim(player, boost == true)
		end,
	},
})

-- === The profile ============================================================

--[[ NON-YIELDING, like `GarageService._profile` and `ReviveService._profile`, and for the same
	reason: this is reached from a remote handler and from a Heartbeat loop, neither of which may
	stall for the seconds `Data:GetProfileAsync` can take. The handle is cached by `_watch` off the
	join path; until it lands every read here answers "not yet", which every caller handles. ]]
function OfflineService._profile(self, player: Player)
	local profile = self._profiles[player]
	if profile and profile:IsActive() then
		return profile
	end
	return nil
end

--- Stamp "we saw them at" onto the profile. Cheap and idempotent; the datastore write is the Data
--- layer's own autosave, not one of ours.
function OfflineService._touch(self, player: Player)
	local profile = self:_profile(player)
	if profile then
		profile:Set(OfflineConfig.ProfileKey, os.time())
	end
end

-- === The boost ==============================================================

--- Is there a boost to sell? False when the feature is off or rbxsync has never been run, and
--- the screen draws one button instead of two — see the note on `Offer.canBoost`.
function OfflineService._canBoost(self): boolean
	return OfflineConfig.Boost.Enabled and OfflineConfig.Boost.ProductId ~= 0
end

--- How many boosts this player owns and has not spent. 0 for a profile that has not landed yet,
--- which every caller treats as "they are buying one", never as "they cannot".
function OfflineService.getBoosts(self, player: Player): number
	local profile = self:_profile(player)
	local count = profile and profile:Get(OfflineConfig.Boost.ProfileKey)
	return if type(count) == "number" then math.max(0, count) else 0
end

--[[ Take one off the count. Returns whether there was one to take.

	CALLED AFTER THE SWEEP, NEVER BEFORE — see `_pay`. Spending first and multiplying second reads
	more naturally and is wrong: it burns a purchase on a lot that turned out to have nothing on it,
	which is the one outcome a player who has just paid Robux would rightly call theft. ]]
function OfflineService._spendBoost(self, player: Player): boolean
	local profile = self:_profile(player)
	if not profile or self:getBoosts(player) <= 0 then
		return false
	end
	profile:Decrement(OfflineConfig.Boost.ProfileKey, 1)
	return true
end

--[[ PUBLIC (`DevProductsHandler`): a boost was bought. Bank it, then spend it if — and only if — the
	player is sitting in front of the screen it was bought for.

	THE ONE PLACE IN THIS SERVICE THAT IS ALLOWED TO YIELD FOR A PROFILE, and the only one that must,
	for `ReviveService.grantLife`'s reason exactly: this is called from inside `ProcessReceipt`, which
	is a yielding context by construction, and dropping the grant because the cache had not been
	filled yet would be a player charged for nothing. The race is narrow but real — a receipt
	processed on the frame the player joined can reach here before `_watch` has written the cache —
	and awaiting the same call resolves instantly in every other case.

	`_awaiting` is what separates "they just pressed the button" from every other way a receipt can
	arrive. Set when this service opened the prompt, cleared when the prompt closes unbought, and
	dropped with the player. Without it, a retried receipt from two sessions ago would sweep a lot
	nobody is looking at and pay double into a screen that is not on the screen. ]]
--- RETURNS WHETHER THE BOOST WAS BANKED (2026-09-28), for `DevProductsHandler` to raise on — the
--- same fix, and the same reason, as `ReviveService.grantLife`.
function OfflineService.grantBoost(self, player: Player, count: number?): boolean
	local profile = self:_profile(player)
	if not profile then
		local ok, resolved = pcall(function()
			return Data:GetProfileAsync(player)
		end)
		if ok and resolved and resolved:IsActive() then
			self._profiles[player] = resolved
			profile = resolved
		end
	end
	if not profile then
		self.log:warn(string.format("%s bought a boost with no live profile; the receipt will be retried.", player.Name))
		return false
	end

	profile:Increment(OfflineConfig.Boost.ProfileKey, count or 1)
	self.log:info(string.format("%s now holds %d offline boost(s).", player.Name, self:getBoosts(player)))

	--[[ The flag comes down HERE, whichever way this goes. It means "they are in front of the modal
		we opened", and by this line that is over — leaving it up would let a receipt Roblox retries
		later in the same session sweep a lot nobody is looking at. ]]
	local applyNow = self._awaiting[player] and self._claimable[player]
	self._awaiting[player] = nil

	--[[ They bought it from the screen and the screen is still armed: apply it now, which is the
		whole of what they paid for. `_pay` consumes the boost itself, and only if the sweep found
		something — so this cannot spend one on an empty lot even here. ]]
	if applyNow then
		self._claimable[player] = nil
		self:_pay(player, true)
		return true
	end

	--[[ Otherwise it stays banked and the client is told, which repaints its button as owned and
		unlocks it. For a screen that is still up that is one press away from the same outcome; for
		one that is gone it is a boost waiting on the next WELCOME BACK. ]]
	self:_publishBoosts(player)
	return true
end

--- Tell the client how many it owns, so the boost button can stop asking for Robux. A remote rather
--- than an attribute — unlike `ReviveConfig.LivesAttribute` — because exactly one screen ever reads
--- this number and it reads it at most twice a session.
function OfflineService._publishBoosts(self, player: Player)
	if player.Parent == Players then
		self:getRemoteEvent("OfflineBoostState"):Fire(player, self:getBoosts(player))
	end
end

-- === Working out what they missed ===========================================

--[[ Build the offer for a player whose profile has just arrived, and stamp the new `LastSeen`.

	THE STAMP IS READ BEFORE IT IS WRITTEN and written unconditionally — including in every branch
	that decides there is no screen worth showing. A session that produced no offer is still a
	session we saw them in, and skipping the write there would make the NEXT rejoin measure its gap
	from two sessions ago. ]]
function OfflineService._evaluate(self, player: Player)
	local profile = self:_profile(player)
	if not profile then
		return
	end

	local lastSeen = tonumber(profile:Get(OfflineConfig.ProfileKey)) or 0
	self:_touch(player)

	--[[ Never seen them leave: a first session, or a profile written before `LastSeen` existed. No
		screen rather than one measured from the epoch — which would read "away for 20794d". ]]
	if lastSeen <= 0 then
		return
	end

	--[[ A stamp in the FUTURE is a clock that moved under us (a machine with a bad clock, a save
		restored out of order). Treated as "no gap" rather than clamped to something invented. ]]
	local away = os.time() - lastSeen
	if away < OfflineConfig.MinAwaySeconds then
		return
	end

	local Garage = Shard.get("GarageService")
	if not Garage then
		return
	end

	--[[ TWO SOURCES FOR ONE NUMBER, picked by `GarageConfig.Income.Passive`. With passive income it is
		what the bays are holding, exactly as it always was. Without it (2026-09-28) it is what the
		customers would have tipped while the player was away (`_simulate`), and `bays` carries the
		VISITOR count instead — the screen's foot line reads it as such (`OfflineConfig`). ]]
	local amount, bays
	if GarageConfig.Income.Passive then
		amount, bays = Garage:getPending(player)
	else
		amount, bays = self:_simulate(player, Garage, away)
	end

	--[[ THE BUYERS WHO CAME WHILE THEY WERE GONE (2026-09-28), made before the gate below so a lot
		whose tips were too small to show a screen for still gets its buyers — they stand on the lot
		either way. `buyers` is then how many are waiting, for the foot line. ]]
	local Buyers = Shard.get("BuyerService")
	local buyers = if Buyers then Buyers:catchUp(player, away) else 0

	if (amount < OfflineConfig.MinAmount or bays <= 0) and buyers <= 0 then
		return
	end

	--[[ BANKED NOW, NOT ON THE PRESS — the one place this service writes cash for the base amount, and
		only without passive income. The bays used to HOLD the money until it was collected, so a
		screen that was dismissed, timed out (`ReadyTimeout`) or never drawn cost nothing. A simulated
		figure is held by nothing but this server's memory, so waiting for a press would make every one
		of those paths a loss. The press still happens and still counts up and still applies the boost
		(`_pay`); it just no longer decides whether the tips arrive. ]]
	if not GarageConfig.Income.Passive then
		--- The 2x Cash pass on the offline tips (`GarageService.incomeMultiplier`).
		amount *= Garage:incomeMultiplier(player)
		Garage:addCash(player, amount)
		self._owed[player] = amount
	end

	--[[ How long a bay holds for THIS player — the base two hours widened by whatever STORAGE they
		have bought. Read here rather than sent as a config constant because the whole point of the
		capped line is to name an upgrade the player owns some of. ]]
	local cap = if GarageConfig.Income.Passive
		then UpgradeConfig.bankSeconds(Garage:getUpgrades(player), GarageConfig.Income.MaxBankedSeconds)
		else CustomerConfig.Offline.CapSeconds

	self._offers[player] = {
		amount = amount,
		bays = bays,
		away = away,
		capped = away > cap,
		cap = cap,
		canBoost = self:_canBoost() and amount > 0 and amount * OfflineConfig.Boost.Multiplier <= self:_claimCap(player),
		multiplier = OfflineConfig.Boost.Multiplier,
		price = OfflineConfig.Boost.Price,
		--[[ Read at offer time rather than published continuously: this is a modal that opens once on
			join, and the only thing that can change the count while it is up is a purchase — which
			has its own message (`OfflineBoostState`). ]]
		boosts = self:getBoosts(player),
		buyers = buyers,
	} :: Offer

	self.log:info(
		string.format("%s was away %s; their lot is holding %s across %d bays.", player.Name, OfflineConfig.formatAway(away), GarageConfig.formatCash(amount), bays)
	)
	self:getSignal("Welcomed"):Fire(player, amount, away, buyers, not GarageConfig.Income.Passive)

	-- The client may already be waiting — see the header on why either order has to work.
	self:_flush(player)
end

--- Send the parked offer if there is one and the client has said it can hear it. Idempotent: the
--- offer is consumed on send, so a second ping (a rejoin into the same slot, a hot reload) is a
--- no-op rather than a second screen.
function OfflineService._flush(self, player: Player)
	local offer = self._offers[player]
	if not offer or not self._ready[player] then
		return
	end
	self._offers[player] = nil
	--[[ The claim remote is armed HERE and only here, and `_onClaim` consumes it — so it is ONE
		SWEEP PER SCREEN, only for a client that was actually shown one.

		It stays armed if they dismiss instead of collecting, and that is deliberate rather than an
		oversight: the client does not tell us it closed the panel, and adding a remote so it could
		would be a round trip to close a hole that is not one. Everything on the far side of this
		is the player's own money out of their own bays, by the identical `_collect` the AUTO COLLECT
		upgrade and a foot on a mat both run — a sweep they could have walked over and taken. What
		the arming actually buys is that a client which was never offered anything cannot fire it at
		all, and that a double press is worth one payout rather than two. ]]
	self._claimable[player] = true
	self:getRemoteEvent("OfflineEarnings"):Fire(player, offer)
end

-- === The client's end =======================================================

function OfflineService._onReady(self, player: Player)
	if not OfflineConfig.Enabled or self._ready[player] then
		return
	end
	self._ready[player] = true
	self:_flush(player)
end

--[[ They pressed one of the two buttons. One sweep, one answer, whichever it was.

	NOTHING HERE TRUSTS THE CLIENT WITH ANYTHING BUT THE PRESS, the same rule `ReviveService._onAccept`
	is written to: `boost` says which button, and everything that follows from it — whether there is a
	stored boost to spend, what it costs, whether it can be sold at all — is read off state the server
	owns. A player firing this with no offer open is a no-op.

	THE THREE OUTCOMES:

	  plain COLLECT      sweep, pay, done.
	  2x with one owned  sweep, pay double, spend the boost. Costs nothing and prompts nothing.
	  2x with none       open Roblox's prompt and DO NOT DISARM. Nothing is collected and nothing is
	                     lost; the receipt comes back through `grantBoost`, or it does not and the
	                     player still has both buttons in front of them. ]]
function OfflineService._onClaim(self, player: Player, boost: boolean)
	if not OfflineConfig.Enabled or not self._claimable[player] then
		return
	end

	if boost and self:_canBoost() and (self._owed[player] or 0) * OfflineConfig.Boost.Multiplier <= self:_claimCap(player) and self:getBoosts(player) <= 0 then
		return self:_prompt(player)
	end

	self._claimable[player] = nil
	self:_pay(player, boost and self:_canBoost())
end

--[[ What the customers would have tipped while this player was away: `(tips, visitors)`, whole
	numbers, both 0 for a lot with nothing on show or a feature that is off.

	THE LIVE CROWD'S NUMBERS, RUN AS ARITHMETIC. The bays' tip values come from the same
	`GarageService.getBayTip` the live customers price a look off, the crowd size from the same
	`CustomerConfig.countFor` capped by cars on show, and the simulation is `CustomerConfig.simulate`,
	whose header has the formula. So nothing here can make an offline lot out-earn an online one
	except `Offline.Efficiency`, which is set to make sure it does not. ]]
function OfflineService._simulate(self, player: Player, Garage, away: number, live: boolean?): (number, number)
	if not CustomerConfig.Enabled then
		return 0, 0
	end
	local values, indices, efficiencies = {}, {}, {}
	for _, bay in Garage:getBays(player) do
		local car, _id, value = Garage:getBayTip(player, bay.index)
		if car then
			table.insert(values, value)
			table.insert(indices, bay.index)
			local world = WorldConfig.WorldOfBody[car.Body] or 1
			--- `live`: the lot as it earns with the player in it (the HUD's rate line), not the offline share.
			table.insert(efficiencies, if live then 1 else CustomerConfig.offlineEfficiencyFor(world))
		end
	end
	local slots = math.min(CustomerConfig.countFor(Garage:getUpgrades(player)), #values)
	local amount, visitors = CustomerConfig.simulate(values, slots, away, indices, efficiencies)
	local passes = Shard.get("PassService")
	if passes and passes:owns(player, "VIP") then
		amount = math.floor(amount * CustomerConfig.vipIncomeMultiplier())
	end
	return amount, visitors
end

--[[ Sweep the lot, then multiply what came back.

	IT PAYS `collectAll` AND REPORTS WHAT THAT RETURNED, not the figure the offer carried. The two
	differ by however long the screen was up, always in the player's favour, and the screen counts
	to the number that actually landed rather than to the one it was drawn with — so the cash pill
	and the panel agree, which they would not if this reported the offer back.

	THE ORDER IS SWEEP, THEN SPEND, THEN TOP UP, and every step of it is load-bearing:

	  • The sweep is the ONLY question asked of the bays, so the boosted and unboosted claims cannot
	    disagree about what the lot was worth. The multiplier is arithmetic on one number.
	  • The boost is spent AFTER the sweep and only if the sweep found something, so a purchase can
	    never be burnt on an empty lot.
	  • ...and only if the spend succeeded is the difference paid, so a profile that went inactive
	    between the two pays 1x rather than paying double for free.

	The multiplier goes back to the client so the screen can say why the number grew — and it goes
	back as 1 in every case where one was not applied. ]]
function OfflineService._pay(self, player: Player, boost: boolean?)
	local Garage = Shard.get("GarageService")
	--[[ Without passive income the base amount was banked when the offer was made (`_evaluate`), so
		this reads it back rather than paying it again; with passive income it is the sweep it always
		was. Either way `amount` is the 1x figure and everything below is unchanged. ]]
	local amount
	if GarageConfig.Income.Passive then
		amount = if Garage then Garage:collectAll(player) else 0
	else
		amount = self._owed[player] or 0
		self._owed[player] = nil
	end

	local multiplier = 1
	if boost and amount > 0 and Garage and amount * OfflineConfig.Boost.Multiplier <= self:_claimCap(player) and self:_spendBoost(player) then
		multiplier = math.max(1, math.floor(OfflineConfig.Boost.Multiplier))
		--[[ The DIFFERENCE, not the total: `collectAll` has already banked the 1x. This is the one
			`addCash` in the file and it is deliberately written as a top-up rather than as a payout,
			so it reads as what it is — the bays were asked once and this is the bonus on top. ]]
		Garage:addCash(player, amount * (multiplier - 1))
		self:getSignal("Boosted"):Fire(player, amount * (multiplier - 1))
	end

	local paid = amount * multiplier
	self:getRemoteEvent("OfflineCollected"):Fire(player, paid, multiplier)

	if paid > 0 then
		self.log:info(
			string.format(
				"%s collected %s off the welcome screen%s.",
				player.Name,
				GarageConfig.formatCash(paid),
				if multiplier > 1 then string.format(" (%dx of %s)", multiplier, GarageConfig.formatCash(amount)) else ""
			)
		)
	end
end

--[[ Open Roblox's purchase prompt for the boost.

	`_awaiting` IS SET BEFORE THE PROMPT, not after, because `PromptProductPurchase` can return before
	the player has seen anything — and a receipt that beats the flag would be banked instead of
	applied, which is the exact failure this flag exists to prevent. `ReviveService._onAccept` sets
	its own clock-holding flag in the same order and for the same reason.

	The offer stays ARMED across the prompt. Nothing has been collected, so there is nothing to
	protect against a second press: the panel is locked client-side while the modal is up, and a
	press that somehow lands here again simply re-prompts. ]]
function OfflineService._prompt(self, player: Player)
	self._awaiting[player] = true

	--[[ Report the prompt being SHOWN, which is the half of the conversion a receipt cannot tell you:
		a receipt says somebody bought, and only the pair says how many were asked. Fired before the
		prompt rather than after, so a prompt that throws below is still counted as offered — that
		failure is exactly the one worth seeing in the funnel. ]]
	local Analytics = Shard.get("AnalyticsService")
	if Analytics then
		Analytics:PromptShown(player, OfflineConfig.Boost.ProductId)
	end

	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, OfflineConfig.Boost.ProductId)
	end)
	if not ok then
		self._awaiting[player] = nil
		--- Unlocks the client, which is locked waiting on a modal that never opened.
		self:_publishBoosts(player)
		self.log:warn(string.format("Could not prompt %s for the offline boost: %s", player.Name, tostring(err)))
	end
end

-- === Admin ==================================================================

--[[ Public (AdminService, 2026-09-28): run the welcome-back check as if this player had just come
	back from `seconds` away. Answers `(ok, sentence)` for the panel.

	IT REWINDS `LastSeen` AND CALLS `_evaluate`, the join path's own function, rather than building an
	offer by hand — so the simulated tips, the buyers who turned up meanwhile (`BuyerService.catchUp`),
	the cash banked and the screen are all exactly what a real rejoin produces. The alternative was
	actually leaving for an hour, which is also the only other way to see this screen at all.

	THE TIPS ARE REAL MONEY, banked at `_evaluate` as they are for a real return. This is a grant, the
	way every AdminService action is.

	A screen still up from before is disarmed first (`_claimable`), so the one this sends is the one a
	press claims; its money was already banked when it was made, so nothing is lost by it. ]]
function OfflineService.pretendAway(self, player: Player, seconds: number): (boolean, string)
	local profile = self:_profile(player)
	if not OfflineConfig.Enabled then
		return false, "OfflineConfig.Enabled is false, so there is no welcome-back screen"
	end
	if not profile then
		return false, "their profile is not loaded yet"
	end
	--- Floored at the screen's own threshold, since anything under it is a check that is refused by
	--- design and would read as the button being broken.
	local away = math.max(math.floor(seconds), OfflineConfig.MinAwaySeconds)
	profile:Set(OfflineConfig.ProfileKey, os.time() - away)
	self._claimable[player] = nil
	self:_evaluate(player)
	if self._claimable[player] then
		return true, string.format("welcome-back screen sent for %s away", OfflineConfig.formatAway(away))
	end
	if self._offers[player] then
		return true, string.format("screen made for %s away, waiting on the client to say it is ready", OfflineConfig.formatAway(away))
	end
	return false, string.format(
		"%s away earned nothing worth a screen: no car on a bay, or tips under %s and no buyers",
		OfflineConfig.formatAway(away),
		GarageConfig.formatCash(OfflineConfig.MinAmount)
	)
end

-- === Lifecycle ==============================================================

--[[ Cache the profile off the join path, then work out what they missed.

	It hangs off `GarageService.ProfileReady` rather than off `PlayerAdded` because the offer needs
	the LOT as well as the profile — `getPending` walks the bays this player was assigned — and that
	signal is precisely "the profile has arrived and everything derived from it has been published".
	`GetProfileAsync` therefore returns immediately here; it is called at all so this service holds
	its own handle rather than reaching into another service's cache.

	The re-check after the yield is the same one `GarageService._watchProfile` makes and is not
	paranoia: a player who joins and leaves inside that window would otherwise have their stamp
	written after they had gone. ]]
function OfflineService._watch(self, player: Player)
	task.spawn(function()
		local ok, profile = pcall(function()
			return Data:GetProfileAsync(player)
		end)
		if not ok or not profile or player.Parent ~= Players then
			return
		end

		self._profiles[player] = profile
		self:_evaluate(player)

		--[[ An offer nobody ever came to collect. Dropped rather than kept, so a client that never
			started cannot leave a live claim remote behind it for the length of the session. The
			money is untouched by this — it is standing on the bays either way. ]]
		if OfflineConfig.ReadyTimeout > 0 then
			task.delay(OfflineConfig.ReadyTimeout, function()
				if self._offers[player] then
					self._offers[player] = nil
					self.log:info(string.format("%s's welcome-back offer expired unclaimed — the cash is still on the bays.", player.Name))
				end
			end)
		end
	end)
end

--[[ Refresh every live player's `LastSeen`.

	A DELIBERATE EXCEPTION to `GarageService`'s "only writes a player caused" rule, and the reason is
	the crash case: join-and-leave writes alone are enough right up until the server dies without
	running the leave one, at which point the stamp still says "joined four hours ago" and the next
	session opens with a screen claiming they were away for a session they actually played. A minute
	of granularity removes the class. `OfflineConfig.TouchInterval = 0` turns it off. ]]
function OfflineService._touchLoop(self)
	local accumulator = 0
	return RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < OfflineConfig.TouchInterval then
			return
		end
		accumulator = 0
		for player in self._profiles do
			self:_touch(player)
		end
	end)
end

--[[ Publish what this player's lot would earn offline per `OfflineConfig.Label.PerSeconds`, for the
	top-of-screen label. `_simulate` is the WELCOME BACK payout's own arithmetic, so the label and the
	payout cannot disagree. With passive income back on (`GarageConfig.Income.Passive`) there are no
	simulated tips to quote, so it publishes 0 and the label shows its empty line. ]]
function OfflineService._publishLabelRate(self, player: Player)
	if not OfflineConfig.Label.Enabled or player.Parent ~= Players then
		return
	end
	local Garage = Shard.get("GarageService")
	local rate, live = 0, 0
	if Garage and not GarageConfig.Income.Passive then
		rate = self:_simulate(player, Garage, OfflineConfig.Label.PerSeconds)
		--- The HUD's income line (`GarageConfig.Hud.TipRate`), an hour of the lot at full strength.
		--- Cached by the simulation like the offline figure, so this costs nothing while the lot is still.
		live = self:_simulate(player, Garage, 3600, true)
		local multiplier = Garage:incomeMultiplier(player)
		rate = math.floor(rate * multiplier)
		live = math.floor(live * multiplier)
	end
	player:SetAttribute(OfflineConfig.Label.Attribute, rate)
	player:SetAttribute(GarageConfig.Hud.TipRate.Attribute, live)
end

OfflineService:withLifecycle({
	init = function(self)
		self._profiles = {} :: { [Player]: any }
		self._offers = {} :: { [Player]: Offer }
		self._ready = {} :: { [Player]: boolean }
		self._claimable = {} :: { [Player]: boolean }
		--- [Player] = the simulated tips already banked for this session's offer, which `_pay` reads
		--- back as the 1x figure for the screen and the boost. Only used without passive income.
		self._owed = {} :: { [Player]: number }
		--- "This player pressed the boost and is sitting in front of the modal we opened." See
		--- `grantBoost` on why a receipt with no flag behind it is banked instead of applied.
		self._awaiting = {} :: { [Player]: boolean }
		self._trove = Trove.new()
	end,

	start = function(self)
		if not (OfflineConfig.Enabled and GarageConfig.Enabled) then
			self.log:info("Disabled by config — no welcome-back screen. The bays still accrue and still pay out.")
			return
		end

		local Garage = Shard.get("GarageService")
		if not Garage then
			self.log:warn("No GarageService — there is nothing to report earnings from.")
			return
		end

		self._trove:Add(Garage:getSignal("ProfileReady"):Connect(function(player: Player)
			self:_watch(player)
			self:_publishLabelRate(player)
		end))

		--[[ The top-of-screen label's figure (`OfflineConfig.Label`): re-priced on every lot change,
			which is what moves it, and on a slow ticker for the customers upgrade, which does not touch
			the lot. ]]
		if OfflineConfig.Label.Enabled then
			self._trove:Add(Garage:getSignal("LotChanged"):Connect(function(player: Player)
				self:_publishLabelRate(player)
			end))
			local ticker = task.spawn(function()
				while true do
					task.wait(OfflineConfig.Label.RefreshSeconds)
					for _, player in Players:GetPlayers() do
						if Garage:isProfileReady(player) then
							self:_publishLabelRate(player)
						end
					end
				end
			end)
			self._trove:Add(function()
				task.cancel(ticker)
			end)
		end

		--[[ Catch up on anyone already ready. `GarageService` fires that signal off the join path, so
			on a hot reload — or simply if it starts first — a player can already be warm by the time
			this connects, and would otherwise never be looked at. ]]
		for _, player in Players:GetPlayers() do
			if Garage:isProfileReady(player) then
				self:_watch(player)
			end
		end

		if OfflineConfig.TouchInterval > 0 then
			self._trove:Add(self:_touchLoop())
		end

		--[[ A prompt that closed WITHOUT a purchase. The flag has to come down or a receipt retried
			from some other session would be treated as "they are looking at the screen right now".

			The client is told either way, which is what unlocks its panel: on a cancel the count is
			unchanged and the button repaints to exactly what it already said, and on a purchase this
			fires BEFORE the receipt does — so `wasPurchased` is deliberately not used to pay
			anything. Money only ever moves on a receipt. ]]
		if self:_canBoost() then
			self._trove:Add(MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, wasPurchased)
				if productId ~= OfflineConfig.Boost.ProductId then
					return
				end
				local player = Players:GetPlayerByUserId(userId)
				if not player then
					return
				end
				if not wasPurchased then
					self._awaiting[player] = nil
					self:_publishBoosts(player)
				end
			end))
		end

		--[[ The stamp that matters most: written on the way out, while the profile is still active,
			so an ordinary session leaves an accurate mark and the timer above is only insurance. ]]
		self._trove:Add(Players.PlayerRemoving:Connect(function(player: Player)
			self:_touch(player)
			self._profiles[player] = nil
			self._offers[player] = nil
			self._ready[player] = nil
			self._claimable[player] = nil
			self._awaiting[player] = nil
			self._owed[player] = nil -- already in their balance; this only forgets the figure
		end))
	end,
})

OfflineService:withCleanup(function()
	if OfflineService._trove then
		OfflineService._trove:Destroy()
	end
end)

-- Approved economy balance, 2026-10-04.
function OfflineService._claimCap(self, player: Player): number
 -- No per-world dollar ceiling. Each car uses its own world's offline efficiency.
 return math.huge
end

return OfflineService
