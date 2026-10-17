--[[
	ReviveService  (server)
	-----------------------
	The paid continue. Owns the window between "you wrecked" and "the run is over", and is the only
	thing that closes it.

	THE ONE IDEA: A WRECK NO LONGER ENDS A RUN BY ITSELF. `RaceService.wreckRace` hands this service
	first refusal on every wreck; where it accepts (`offerRevive`), it takes ownership of the whole
	ending — the run is NOT settled, the fade is NOT raised, and the respawn screen goes up instead
	once the wreck beat has been watched. From there exactly one of three things happens, and every
	one of them goes back through RaceService:

	  • They pay (or spend a life they already own) → `RaceService.reviveRace`. Same car, back on the
	    lane where it died, full HP, still counting the distance it already had.
	  • They decline, or the clock runs out → the run settles as the crash it was, and
	    `RaceService.endWreckedRun` raises the fade and sends them home. Exactly the old behaviour,
	    eight seconds later.
	  • Something goes wrong — they leave, they die, the car is destroyed under us → `_giveUp`, which
	    is the same path as declining and is armed from the moment the offer is accepted.

	THE THIRD ONE IS WHY THIS SERVICE IS SHAPED THE WAY IT IS. Everything about a live offer is a
	pause in a beat that would otherwise have run to completion on a `task.delay`, and a pause with
	no owner is a player parked on a wrecked car with no fade and no way home — the worst outcome
	this feature can have, and much worse than never having offered. So the offer is armed with its
	own hard timeout in the same call that creates it, `_close` is idempotent and unconditional, and
	`PlayerRemoving` drops the state. There is no path that leaves an offer open.

	=== THE LIFE IS A THING YOU OWN, NOT A TRANSACTION ==========================================

	Buying a revive does not revive anybody. It increments `ExtraLives` on the profile
	(`DevProductsHandler` → `grantLife`), and reviving SPENDS one. The screen therefore has two
	states — "REVIVE  R$25" and "REVIVE  (2 left)" — and the second one costs nothing and needs no
	prompt.

	That indirection is the whole robustness story. A receipt can land at a moment when there is
	nothing to revive: the offer timed out while Roblox's purchase modal was still up, the player
	left, the server restarted mid-purchase, Roblox retried the receipt on their next session. Every
	one of those, reviving straight out of the receipt, is a player who paid and got nothing. Stored,
	all of them are a player who owns a life — and the very next wreck spends it for free.

	`grantLife` therefore also tries to spend it immediately, which is what makes the ordinary case
	(prompt accepted while the screen is still up) feel like a direct purchase rather than like
	buying a token and then using it.

	=== THE CLOCK STOPS FOR THE PURCHASE PROMPT ================================================

	`ReviveConfig.OfferTime` is eight seconds, which is a decision, not a transaction. Roblox's
	purchase prompt is a modal the player has to read and confirm, and a countdown that expires
	behind it is a run ending with a thumb on the buy button. So the deadline is pushed out while a
	prompt is open and restored when it closes — see `_onPromptFinished`. What the player is being
	timed on is deciding, never paying.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local ReviveConfig = require(ReplicatedStorage.shared.Configs.ReviveConfig)

local Data = require(script.Parent.Parent.Data)

--[[ Slack on top of `OfferTime` before the offer is closed no matter what the client says.

	THE COUNTDOWN IS A CLIENT-SIDE ANIMATION AND THIS IS THE REAL DEADLINE. The screen draws its own
	ring from a deadline the server sends, which is the only way it can be smooth; but a client that
	never answers — a tab that lost focus at the wrong moment, a player who alt-tabbed, a hung
	renderer — must not be able to hold a run open forever. Generous, because it is a fail-safe
	rather than the timer anybody is meant to hit: the client normally declines on its own well
	inside it, and a live purchase prompt pushes it out with everything else. ]]
local OFFER_GRACE = 3

--[[ How long a purchase prompt may hold the clock open before it is treated as abandoned. Roblox
	does not tell us a prompt was dismissed by the player closing the window rather than by
	cancelling, so this is what stops a prompt that never reports back from being an open run. ]]
local PROMPT_GRACE = 45

local ReviveService = Shard.new("ReviveService"):withDependencies({ "RaceService", "ObstacleService", "RewardService" })

ReviveService:withRemoteEvents({
	--[[ server -> client (offer): put the respawn screen up — or repaint one already up.

		ONE TABLE, not six arguments, because every field of it is drawn by the same screen at the
		same moment and a positional list of six is a list nobody can add a seventh to safely. See
		`_offerPayload` for what is in it and why each field is there rather than asked for.

		Fired again, unchanged in shape, whenever the countdown is restarted (a purchase prompt
		closing) — so the client's handler is "draw this offer", not "start an offer", and there is no
		second remote for the second case. ]]
	"ReviveOffer",
	-- server -> client: the offer is over, whichever way. The screen comes down; what happens next
	-- (the return fade, or the car appearing back on the road) is somebody else's remote.
	"ReviveClosed",
	--[[ server -> client (lives): how many stored lives this player has, mirrored to the screen so a
		purchase that lands while it is up repaints the button. Also written to the Player as an
		attribute for anything that wants it without a listener; the remote is what makes it prompt. ]]
	"ReviveLives",
	{
		-- client -> server: "yes" — spend a stored life if there is one, otherwise open the prompt.
		ReviveAccept = function(player: Player)
			ReviveService:_onAccept(player)
		end,
		-- client -> server: "no" — end the run now rather than waiting the clock out.
		ReviveDecline = function(player: Player)
			ReviveService:_giveUp(player, "declined")
		end,
	},
})

-- === Stored lives ===========================================================

--[[ NON-YIELDING, like `GarageService._profile` and for the same reason: this is reached from a
	remote handler and from the middle of a wreck beat, so it has to answer "not yet" rather than
	block. `Data:GetProfileAsync` yields until the profile loads, which can be seconds — so the
	handle is cached by `_watchProfile` off the join path and read cold from here. ]]
function ReviveService._profile(self, player: Player)
	local profile = self._profiles[player]
	if profile and profile:IsActive() then
		return profile
	end
	return nil
end

--[[ Wait for the profile off the join path, then publish the stored count. Same shape and same
	reasoning as `GarageService._watchProfile`: the yield can be seconds long, so it gets its own
	thread, and the re-check after it catches a player who joined and left inside that window. ]]
function ReviveService._watchProfile(self, player: Player)
	task.spawn(function()
		local ok, profile = pcall(function()
			return Data:GetProfileAsync(player)
		end)
		if not ok or not profile or player.Parent ~= Players then
			return
		end
		self._profiles[player] = profile
		self:_publishLives(player)
	end)
end

function ReviveService.getLives(self, player: Player): number
	local profile = self:_profile(player)
	local lives = profile and profile:Get(ReviveConfig.ProfileKey)
	return if type(lives) == "number" then math.max(0, math.floor(lives)) else 0
end

-- Broadcast the count both ways: an attribute for anything that wants to read it cold, a remote for
-- the screen, which has to REPAINT the instant a purchase lands rather than on its next poll.
function ReviveService._publishLives(self, player: Player)
	local lives = self:getLives(player)
	player:SetAttribute(ReviveConfig.LivesAttribute, lives)
	self:getRemoteEvent("ReviveLives"):Fire(player, lives)
	return lives
end

--[[ Public (DevProductsHandler): a revive was paid for. Bank it, then try to use it.

	BANKED FIRST, UNCONDITIONALLY, and spent second on a best-effort basis. The order is the promise:
	whatever the state of the world when this receipt arrives — mid-offer, back in the lobby, a fresh
	session days later — the player owns the thing they paid for before anything is attempted with
	it. `_spendLife` puts it back if the revive doesn't land. ]]
--[[ RETURNS WHETHER THE LIFE WAS BANKED (2026-09-28). `DevProductsHandler` raises on false so the
	receipt is NOT acknowledged and Roblox re-delivers it; this used to return nothing, and a receipt
	that landed with no live profile was consumed for a life that was never written. ]]
function ReviveService.grantLife(self, player: Player, count: number?): boolean
	--[[ THE ONE PLACE THAT IS ALLOWED TO YIELD FOR A PROFILE, and the only place that must.

		Everywhere else in this service reads the cache and answers "not yet", because everywhere
		else is a remote handler or the middle of a wreck beat. This one is Robux: it is called from
		inside `ProcessReceipt`, which is a yielding context by construction (it saves and waits on
		the save), and dropping the grant because a cache had not been filled yet would be a player
		charged for nothing.

		THE RACE IS REAL, IF NARROW. `ProcessReceipt` awaits `Data:GetProfileAsync` and so does
		`_watchProfile`; both resume in whatever order the scheduler picks, so a receipt processed on
		the same frame the player joined can reach here before the cache is written. Awaiting the
		same call resolves against the profile that is already loaded by then rather than waiting on
		anything, so this costs nothing in every other case. ]]
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
		self.log:warn(string.format("%s bought a revive with no live profile; the receipt will be retried.", player.Name))
		return false
	end
	profile:Increment(ReviveConfig.ProfileKey, count or 1)
	self:_publishLives(player)
	self.log:info(string.format("%s now has %d revive(s) in hand.", player.Name, self:getLives(player)))

	-- The ordinary case: they are looking at the respawn screen right now and this is the purchase
	-- they just made. Spending it here is what makes the prompt feel like a revive button rather
	-- than like buying a token and then having to use it.
	if self._offers[player] then
		self:_useLife(player)
	end
	return true
end

--[[ Take one off the count. Returns whether there was one to take.

	Deliberately NOT folded into `_useLife`: the spend has to happen before the revive is attempted
	(so a second click inside the same frame cannot spend the same life twice) and has to be undone
	if the revive doesn't land, which is two call sites for one operation. ]]
function ReviveService._spendLife(self, player: Player): boolean
	local profile = self:_profile(player)
	if not profile or self:getLives(player) <= 0 then
		return false
	end
	profile:Decrement(ReviveConfig.ProfileKey, 1)
	self:_publishLives(player)
	return true
end

-- === The offer ==============================================================

--[[ Which rung of the ladder this run is on, given how many revives it has already taken. nil once
	the ladder is spent, which is what caps revives per run — `#ReviveConfig.Tiers` of them.

	A rung with no product id behind it (rbxsync never run, a key renamed) is treated as the end of
	the ladder rather than as a free revive: an offer nobody can buy is worse than no offer, because
	the player spends their eight seconds on a button that does nothing. ]]
function ReviveService._tierFor(self, used: number)
	local tier = ReviveConfig.Tiers[used + 1]
	if not (tier and tier.ProductId and tier.ProductId ~= 0) then
		return nil
	end
	return tier
end

--[[ Public (RaceService.wreckRace): first refusal on this wreck.

	Returns true when this service has TAKEN OWNERSHIP OF THE ENDING — which means the caller must
	not settle the run and must not raise the fade, because one of `reviveRace` / `endWreckedRun` is
	now this service's to call. False means "not my problem", and the wreck runs exactly as it did
	before revives existed.

	Every reason to say no is checked here rather than later, because a screen that comes up and then
	has nothing to sell is worse than no screen. In order: the feature is on; this ending is one that
	can be revived at all (`ReviveConfig.RevivableCauses` — see its note on the two that can't); the
	ladder has a rung left; and there is a live rider to put back in the car, because a revive that
	cannot seat anybody is a purchase that would refund itself.

	`hold` is the wreck beat's own length, handed over rather than re-derived: the screen goes up
	when the crash has finished being watched, and that moment is the caller's to define. ]]
function ReviveService.offerRevive(self, player: Player, car: Model, cause: string?, hold: number): boolean
	if not ReviveConfig.Enabled or self._offers[player] then
		return false
	end
	if not ReviveConfig.RevivableCauses[cause or ReviveConfig.OrdinaryCause] then
		return false
	end

	local used = self._used[player] or 0
	local tier = self:_tierFor(used)
	if not tier then
		return false
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid.Health > 0) then
		return false
	end

	--[[ The deadline is set when the SCREEN goes up, not now — the wreck beat is a second and a half
		of watching the car die and it would be pure theft to count it against the decision. Until
		then the entry exists only so a second wreck can't open a second offer over this one. ]]
	local offer = {
		car = car,
		tier = tier,
		used = used,
		deadline = nil :: number?,
		-- 2026-10-12: `_show` may fail before setting the real deadline; its safety timer must stay finite.
		fallbackDeadline = os.clock() + hold + ReviveConfig.OfferTime,
		promptUntil = nil :: number?, -- set while Roblox's purchase modal is up; see `_deadline`
		shown = false,
		-- How the run ended, for the panel's headline (WRECKED or BUSTED). Never nil on the wire.
		cause = cause or ReviveConfig.OrdinaryCause,
	}
	self._offers[player] = offer

	task.delay(hold, function()
		if self._offers[player] == offer then
			self:_show(player, offer)
		end
	end)

	--[[ THE FAIL-SAFE IS ARMED IN THE SAME CALL THAT ACCEPTS THE OFFER, before the screen exists and
		regardless of whether it ever does. Everything between here and the player answering is a run
		that has been told not to settle itself; if the show above never runs, this is the only thing
		left that can end it. Re-armed by `_show` against the real deadline. ]]
	self:_armTimeout(player, offer, hold + ReviveConfig.OfferTime + OFFER_GRACE)
	return true
end

--[[ Everything the screen draws, so it never has to ask a question back.

	SECONDS REMAINING RATHER THAN THE DEADLINE ITSELF, because `os.clock()` is a per-machine
	monotonic clock with an arbitrary origin — the server's number means nothing on a client, and
	there is no shared epoch to convert it through. So the client turns this into its own local
	deadline on arrival, and its bar therefore runs one network trip behind the real one. That is the
	safe direction and `OFFER_GRACE` is sized for it: the drawn countdown empties slightly BEFORE the
	offer actually closes, never after, so there is never a moment where the screen still looks live
	and the server has stopped listening.

	THE DISTANCE IS SENT TOO, because it is the pitch. "Keep going?" with nothing under it is a
	button; with `2,140m` under it, it is the run the player is being asked not to throw away. The
	client cannot work it out for itself — `RewardService` measures forward travel with rebases
	discarded, server-side, and the number on the results screen comes from the same place. ]]
function ReviveService._offerPayload(self, player: Player, offer)
	local RewardService = Shard.get("RewardService")
	local studs = RewardService and RewardService:getDistance(player)
	return {
		seconds = math.max(0, (offer.deadline or os.clock()) - os.clock()),
		tier = offer.used + 1, -- which revive of the run this would be, 1-based
		tiers = #ReviveConfig.Tiers,
		price = offer.tier.Price,
		--[[ 0 means "this costs Robux", more means "this is free". Read rather than re-published:
			`_publishLives` fires a remote of its own, and firing it a frame before the offer that
			already carries the number is one message saying the same thing twice. ]]
		lives = self:getLives(player),
		studs = if type(studs) == "number" then studs else 0,
		cause = offer.cause,
		--[[ What the run would pay if this offer is turned down: the panel that asks the question now
			reports the run as well (`NewUIConfig.WreckPanel`), so the results screen after it can be
			skipped. A preview, not a payment; `_endRun` settles the same held run for the same sum. ]]
		run = RewardService and RewardService:previewRun(player),
	}
end

-- Put the screen up and start the clock. Everything the screen draws is on this one message.
function ReviveService._show(self, player: Player, offer)
	local RaceService = Shard.get("RaceService")
	if not (RaceService and RaceService:isRacing(player) and offer.car.Parent) then
		return self:_giveUp(player, "the race ended before the offer could be made")
	end

	offer.shown = true
	offer.deadline = os.clock() + ReviveConfig.OfferTime
	self:getRemoteEvent("ReviveOffer"):Fire(player, self:_offerPayload(player, offer))
	self:_armTimeout(player, offer, ReviveConfig.OfferTime + OFFER_GRACE)
end

--[[ The real deadline, in server clock: the countdown, pushed out for as long as a purchase prompt
	is open. `_armTimeout` re-checks against this rather than firing blind, which is what lets the
	prompt extend an offer that was already armed to close. ]]
function ReviveService._deadline(self, offer): number
	local deadline = (offer.deadline or offer.fallbackDeadline) + OFFER_GRACE
	if offer.promptUntil then
		deadline = math.max(deadline, offer.promptUntil)
	end
	return deadline
end

--[[ Close this offer at `seconds` from now unless the deadline has moved on by then, in which case
	re-arm against wherever it moved to.

	A LOOP RATHER THAN A CANCELLED TIMER because `task.delay` has nothing to cancel: opening a
	purchase prompt pushes the deadline out, and the timer already in flight has no way to be told.
	Re-checking and re-arming is the same thing without a handle to keep. The offer identity is the
	fence — a stale timer finds a different table (or none) and does nothing. ]]
function ReviveService._armTimeout(self, player: Player, offer, seconds: number)
	task.delay(seconds, function()
		if self._offers[player] ~= offer then
			return
		end
		local remaining = self:_deadline(offer) - os.clock()
		if remaining > 0 then
			return self:_armTimeout(player, offer, remaining)
		end
		self:_giveUp(player, "timed out")
	end)
end

-- === Answering it ===========================================================

--[[ "Yes". Spend a life if they have one; otherwise open Roblox's prompt for this rung's product.

	NOTHING HERE TRUSTS THE CLIENT WITH ANYTHING BUT THE CLICK. Which rung this is, what it costs and
	whether there is a life to spend are all read from state the server owns — the message carries no
	payload at all, and a player firing it with no offer open is a no-op. ]]
function ReviveService._onAccept(self, player: Player)
	local offer = self._offers[player]
	if not (offer and offer.shown) then
		return
	end
	if self:getLives(player) > 0 then
		return self:_useLife(player)
	end

	--[[ Hold the clock open across the modal. Set BEFORE the prompt, because `PromptProductPurchase`
		can return before the player has seen anything and the window between the two is a window in
		which the countdown is still running against a decision that has already been made. ]]
	offer.promptUntil = os.clock() + PROMPT_GRACE

	--[[ Report the prompt being SHOWN, which is the half of the conversion the receipt cannot tell
		you: a receipt says somebody bought, and only the pair says how many were asked. Fired before
		the prompt rather than after, so a prompt that throws below is still counted as offered —
		that failure is exactly the one worth seeing in the funnel. ]]
	local Analytics = Shard.get("AnalyticsService")
	if Analytics then
		Analytics:PromptShown(player, offer.tier.ProductId)
	end

	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, offer.tier.ProductId)
	end)
	if not ok then
		offer.promptUntil = nil
		self.log:warn(string.format("Could not prompt %s for a revive: %s", player.Name, tostring(err)))
	end
end

--[[ Spend one stored life on the run in hand.

	SPENT BEFORE THE REVIVE IS ATTEMPTED, and put back if it doesn't land. Doing it the other way
	round leaves the window in which two clicks — or a click and a receipt arriving in the same
	frame — both find a life and both revive, which is one life for two continues.

	The offer is closed FIRST for the same reason. `reviveRace` seats the player, and seating fires
	the seat watcher and the deploy toggle; anything still holding an open offer through that is
	something that can be answered twice. ]]
function ReviveService._useLife(self, player: Player)
	local offer = self._offers[player]
	if not offer then
		return
	end
	if not self:_spendLife(player) then
		return
	end

	self._offers[player] = nil
	self:getRemoteEvent("ReviveClosed"):Fire(player)

	local RaceService = Shard.get("RaceService")
	local revived = RaceService ~= nil and RaceService:reviveRace(player)
	if not revived then
		--[[ The revive could not happen — no car, no live rider, no road frame. Hand the life back
			(they paid for one and have not had one) and end the run the ordinary way, which is the
			same thing that would have happened had they declined. ]]
		local profile = self:_profile(player)
		if profile then
			profile:Increment(ReviveConfig.ProfileKey, 1)
			self:_publishLives(player)
		end
		self.log:warn(string.format("%s's revive could not be applied; the life was returned.", player.Name))
		return self:_endRun(player, offer.car)
	end

	self._used[player] = offer.used + 1
	self.log:info(string.format("%s used revive %d of %d.", player.Name, offer.used + 1, #ReviveConfig.Tiers))
end

--[[ "No", or the clock ran out, or something went wrong. Close the offer and let the run end.

	IDEMPOTENT AND UNCONDITIONAL. Every failure path in this service arrives here, including ones
	that arrive twice, so it drops the offer before it does anything that could re-enter. ]]
function ReviveService._giveUp(self, player: Player, why: string)
	local offer = self._offers[player]
	if not offer then
		return
	end
	self._offers[player] = nil
	self:getRemoteEvent("ReviveClosed"):Fire(player)
	self.log:info(string.format("%s's revive offer closed (%s).", player.Name, why))
	--[[ A decline was answered on the one-screen wreck, which has shown the run already. Anything
		else (a timeout nobody answered, a purchase prompt that never came back) has not, so it gets
		the end panel on the way out (`RaceService.holdEndPanel`) rather than the old dark screen. ]]
	self:_endRun(player, offer.car, if why ~= "declined" then offer.cause else nil)
end

--[[ The run is genuinely over now. Settle it and hand the ending back to RaceService.

	SETTLED HERE RATHER THAN IN `wreckRace`, and this is the one thing to keep straight about the
	whole feature: `wreckRace` skipped its own settlement precisely because this call might never
	come — a revived run must not have been paid out as a crash halfway through. So this is the first
	moment the run is over, and it is the only place a revivable wreck is ever settled.

	`settleRun` is idempotent per run, so the belt-and-braces case (a run that somehow reached
	`leaveRace` first) pays once and only once. ]]
function ReviveService._endRun(self, player: Player, car: Model, panelCause: string?)
	local RewardService = Shard.get("RewardService")
	if RewardService then
		RewardService:settleRun(player, false)
	end
	local RaceService = Shard.get("RaceService")
	if not RaceService then
		return
	end
	if panelCause then
		RaceService:holdEndPanel(player, car, "wreck", panelCause, function()
			RaceService:endWreckedRun(player, car)
		end)
	else
		RaceService:endWreckedRun(player, car)
	end
end

--[[ Roblox says the modal closed. Give the player the rest of their countdown back either way.

	`wasPurchased` is deliberately NOT acted on. A true here means the prompt reported success, not
	that the receipt has been processed — `ProcessReceipt` is what actually grants, and it is what
	calls `grantLife`, which spends the life for them. Reviving off this signal would be reviving off
	the client's word about a purchase the server has not yet been paid for.

	The countdown is RESTARTED rather than resumed, and that is a small kindness rather than an
	oversight: a player who spent twenty seconds in the purchase modal and cancelled should not come
	back to a screen with half a second left on it. ]]
function ReviveService._onPromptFinished(self, player: Player, _wasPurchased: boolean)
	local offer = self._offers[player]
	if not (offer and offer.promptUntil) then
		return
	end
	offer.promptUntil = nil
	offer.deadline = os.clock() + ReviveConfig.OfferTime
	self:getRemoteEvent("ReviveOffer"):Fire(player, self:_offerPayload(player, offer))
	self:_armTimeout(player, offer, ReviveConfig.OfferTime + OFFER_GRACE)
end

-- Public (RaceService.leaveRace, and anything else that ends a run): this player's run is over, so
-- the ladder resets. Safe for a player who never wrecked.
function ReviveService.endRun(self, player: Player)
	self._used[player] = nil
	if self._offers[player] then
		self:_giveUp(player, "the run ended")
	end
end

ReviveService:withLifecycle({
	init = function(self)
		-- [Player] = { car, tier, used, deadline, promptUntil, shown } while an offer is open. The
		-- table's IDENTITY is the fence every timer in here checks against, so it is replaced rather
		-- than mutated when an offer ends.
		self._offers = {}
		-- [Player] = how many revives THIS RUN has taken. Not on the profile: the ladder is per run
		-- and resets with it, which is the whole reason the price can climb without ever being a
		-- permanent tax on a player who has wrecked a lot.
		self._used = {}
		self._profiles = {} -- [Player] = PlayerProfile, latched off the join path by `_watchProfile`
	end,

	start = function(self)
		if not ReviveConfig.Enabled then
			self.log:info("Disabled by config — a wreck ends the run outright.")
			return
		end

		MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, _productId, wasPurchased)
			local player = Players:GetPlayerByUserId(userId)
			if player then
				self:_onPromptFinished(player, wasPurchased)
			end
		end)

		-- Latch the profile on join so the screen never opens on a stale zero. Already-present players
		-- are covered too, so a hot reload of this service picks the session back up.
		Players.PlayerAdded:Connect(function(player)
			self:_watchProfile(player)
		end)
		for _, player in Players:GetPlayers() do
			self:_watchProfile(player)
		end

		--[[ Drop everything keyed on a Player. The offer is dropped rather than given up: `_giveUp`
			settles the run and teleports them home, which for a player who has already gone is a
			write against a profile that is being closed. `RaceService`'s own `PlayerRemoving` runs
			`leaveRace`, and `RewardService.endRun` inside it settles the unsettled run — so the
			payout is not lost by dropping this, it is banked by the path that always banked it. ]]
		Players.PlayerRemoving:Connect(function(player)
			self._offers[player] = nil
			self._used[player] = nil
			self._profiles[player] = nil
		end)
	end,
})

return ReviveService
