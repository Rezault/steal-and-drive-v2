--[[
	RandomCarService  (server)
	--------------------------
	Sells the random car pull, banks it, rolls it, and hands the winner to `GarageService.awardCar`.

	=== THE WHOLE SERVICE IN FOUR LINES ========================================================

	    the card is pressed  ->  hold a pull?  yes: roll it   no: open Roblox's prompt
	    a receipt lands      ->  bank a pull, and roll it now if they are still at the card
	    a roll happens       ->  RandomCarConfig.roll  ->  GarageService.awardCar
	    the award returns    ->  read the bay back off the lot, fire the reveal

	NOTHING ELSE IS THIS SERVICE'S BUSINESS. It does not price a car, park one, decide what a
	duplicate is worth, or know what a bay pays — `awardCar` has owned all of that since the day the
	getaway truck banked the first car, and `RandomCarConfig`'s header says at length why a second
	path into a collection is the one thing this feature must not become.

	=== THE ROLL IS THE PRODUCT, WHICH IS WHY IT IS NOT IN THE RECEIPT =========================

	`DevProductsHandler` calls `grantPull` and that is ALL it does — it banks a counter. The obvious
	shortcut is to roll inside the receipt: one line, the car lands in the profile correctly, done.
	It is wrong, and not for the usual durability reason the other two products have.

	A late revive still revives. A late boost still multiplies the next claim. A car rolled inside a
	receipt on a server the player is not looking at is a car that simply APPEARS in their lot, and
	the appearing is most of what 99 Robux bought — the sunburst, the shape that turns into a
	Mustang. So the receipt banks the RIGHT to a roll and the reveal spends it, which means a player
	who bought one and left owns a pull, and the next screen they open rolls it in front of them.

	`_awaiting` is what separates "they just pressed the card" from every other way a receipt can
	arrive, exactly as it does in `OfflineService`: set when this service opened the prompt, cleared
	when the prompt closes, dropped with the player. Without it a receipt Roblox retries two sessions
	later would roll a car at somebody standing in a lobby with no card on screen.

	=== THE CLIENT IS TRUSTED WITH THE PRESS AND NOTHING ELSE =================================

	`RandomCarBuy` carries no arguments. It cannot: the only thing the client is entitled to say is
	"I pressed it", and every other fact in this transaction — do they hold a pull, which world are
	they in, what did the roll produce — is read on this side. A client that could name a car would
	name a good one; a client that could name a world would name the last one.

	THE SEED IS THE SERVER'S TOO, and is logged with the outcome. `RandomCarConfig.roll` takes a
	`Random` rather than reaching for `math.random` so a pull is a stream this call owns and so a
	support ticket can be re-run rather than argued about — its header has the long version.

	=== ONE ROLL AT A TIME, PER PLAYER ========================================================

	`_rolling` is a per-player latch held across `awardCar`, which yields (it writes the profile and
	rebuilds the lot). Without it, two presses a frame apart both pass the "do they hold a pull"
	check before either has decremented, and the player gets two cars for one purchase. That is the
	single most expensive bug this file could contain, and it is one boolean.

	=== SOME PLAYERS MAY NOT BE SOLD A PULL AT ALL (2026-10-15) ===============================

	Roblox's paid random items policy: where `PolicyService` reports `ArePaidRandomItemsRestricted`,
	the player may not buy a random item or open one. `_checkPolicy` asks once per player on join and
	`_allowed` holds the answer. Until it is true the card is reported as not sellable (which takes it
	off their screen), a press opens no prompt, and a banked pull is not rolled. Every one of those is
	decided HERE, so a client that ignores its card's state still gets nothing. A receipt is still
	banked if one ever arrives: the player has paid, and refusing the grant would only make Roblox
	retry it. `RandomCarConfig.Policy` has the retry and fail-closed rules.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local InventoryConfig = require(ReplicatedStorage.shared.Configs.InventoryConfig)
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)
local RandomCarConfig = require(ReplicatedStorage.shared.Configs.RandomCarConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local Data = require(script.Parent.Parent.Data)

--[[ Everything the reveal draws, in one table — the same call `OfflineService`'s `Offer` and
	`ReviveService._offerPayload` make, and for the same reason: every field is drawn by one screen
	at one moment, and a positional list of eight is a list nobody can add a ninth to safely. ]]
type Pull = {
	body: string, -- the roster body name, which is what `CarViewport` wants
	tier: number,
	paint: number, -- the palette index it was rolled in; part of what the car IS
	rarity: string, -- the band word off `TrafficConfig.Bands` ("Supercar"), for the line under it
	--[[ What `awardCar` did with it: "parked", "upgraded", "collected" or "sold". Passed through
		verbatim rather than collapsed into a boolean, because the reveal has a different sentence
		for each and the player deserves to be told which one happened. ]]
	outcome: string,
	bay: number?, -- which podium it is standing on, for "parked" and "upgraded"; nil otherwise
	cash: number, -- what a duplicate sold for; 0 on every other outcome
	rate: number, -- what the car earns per second, so the reveal can show what was won
	pulls: number, -- how many are still banked after this one, so the card repaints itself
}

local RandomCarService = Shard.new("RandomCarService"):withDependencies({ "GarageService" })

RandomCarService:withRemoteEvents({
	--[[ server -> client (pulls, sellable): how many pulls they hold and whether there is anything
		to sell at all. Drives the card's face — a player holding one sees OPEN instead of a price,
		which is what stops a banked pull looking like a second charge. Fired on ready, on a grant,
		and after every roll. ]]
	"RandomCarState",
	--[[ server -> client (Pull): the roll landed and the car is already theirs. Everything the
		reveal draws is in it — see the type above. ]]
	"RandomCarRolled",
	{
		--[[ client -> server: my card exists, so a remote sent now will be heard. Fired once from
			the controller's `start`; it carries nothing, because the player is the whole message. ]]
		RandomCarReady = function(player: Player)
			RandomCarService:_onReady(player)
		end,
		--[[ client -> server: they pressed the card. NO ARGUMENTS, deliberately — see the header.
			The server decides whether that means spending a banked pull or opening a Robux prompt,
			and reads the count off the profile to do it. ]]
		RandomCarBuy = function(player: Player)
			RandomCarService:_onBuy(player)
		end,
	},
})

-- === The profile ============================================================

--[[ NON-YIELDING, like `GarageService._profile` and `OfflineService._profile`, and for the same
	reason: this is reached from remote handlers that may not stall for the seconds
	`Data:GetProfileAsync` can take. The handle is cached off the join path by `_watch`; until it
	lands every read here answers "not yet", which every caller handles. ]]
function RandomCarService._profile(self, player: Player)
	local profile = self._profiles[player]
	if profile and profile:IsActive() then
		return profile
	end
	return nil
end

-- === Pulls ==================================================================

--[[ How many pulls this player owns and has not rolled. 0 for a profile that has not landed yet,
	which every caller treats as "they are buying one", never as "they cannot". ]]
function RandomCarService.getPulls(self, player: Player): number
	local profile = self:_profile(player)
	local count = profile and profile:Get(RandomCarConfig.ProfileKey)
	return if type(count) == "number" then math.max(0, count) else 0
end

--- Tell the client what its card should say. A remote rather than an attribute, for
--- `OfflineService._publishBoosts`'s reason: one screen reads this number, a handful of times a
--- session. "Sellable" is per player: false for a player the policy check has not cleared.
function RandomCarService._publish(self, player: Player)
	if player.Parent == Players then
		self:getRemoteEvent("RandomCarState"):Fire(player, self:getPulls(player), self:canPull(player))
	end
end

-- === Eligibility ============================================================

--[[ PUBLIC: may this player buy or open a random car pull? True only once PolicyService has said
	paid random items are allowed for them. False while the answer is pending, when it said they are
	restricted, and when it could not be reached. See the header. ]]
function RandomCarService.canPull(self, player: Player): boolean
	return RandomCarConfig.sellable() and self._allowed[player] == true
end

--[[ Ask PolicyService about one player, off the join path. `GetPolicyInfoForPlayerAsync` yields and
	can throw, so it is retried (`RandomCarConfig.Policy`) and a player it never answers for stays
	restricted. The client is told the moment there is an answer, which is what puts the card on an
	eligible player's screen. ]]
function RandomCarService._checkPolicy(self, player: Player)
	task.spawn(function()
		local policy = RandomCarConfig.Policy
		local info, err
		for attempt = 1, policy.Attempts do
			local ok, result = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
			if ok and type(result) == "table" then
				info = result
				break
			end
			err = result
			if player.Parent ~= Players then
				return
			end
			if attempt < policy.Attempts then
				task.wait(policy.RetrySeconds)
			end
		end
		if player.Parent ~= Players then
			return
		end

		if not info then
			self._allowed[player] = false
			self.log:warn(string.format("No policy answer for %s (%s); random car pulls stay off for them this session.", player.Name, tostring(err)))
		elseif info.ArePaidRandomItemsRestricted == false then
			self._allowed[player] = true
		else
			--- Anything but an explicit false is restricted, including a field Roblox stops sending.
			self._allowed[player] = false
			self.log:info(string.format("%s may not buy paid random items where they are; the random car card is hidden for them.", player.Name))
		end
		self:_publish(player)
	end)
end

--[[ PUBLIC (`DevProductsHandler`): a pull was bought. Bank it, then roll it if — and only if — the
	player is sitting in front of the card they bought it from.

	THE ONE PLACE IN THIS SERVICE ALLOWED TO YIELD FOR A PROFILE, and the only one that must, for
	`OfflineService.grantBoost`'s reason exactly: this is called from inside `ProcessReceipt`, which
	is a yielding context by construction, and dropping the grant because the cache had not been
	filled yet would be a player charged for nothing. The race is narrow but real — a receipt
	processed on the frame the player joined can reach here before `_watch` has written the cache —
	and awaiting the same call resolves instantly in every other case. ]]
--[[ Public (`DevProductsHandler`): bank a paid pull. RETURNS WHETHER IT WAS BANKED (2026-09-28): the
	receipt handler raises on false so Roblox re-delivers, rather than acknowledging a purchase that
	was never written — which is what a nothing-returning grant used to let happen. ]]
function RandomCarService.grantPull(self, player: Player, count: number?): boolean
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
		self.log:warn(string.format("%s bought a random car pull with no live profile; the receipt will be retried.", player.Name))
		return false
	end

	profile:Increment(RandomCarConfig.ProfileKey, count or 1)
	self.log:info(string.format("%s now holds %d random car pull(s).", player.Name, self:getPulls(player)))

	--[[ The flag comes down HERE, whichever way this goes. It means "they are in front of the modal
		we opened", and by this line that is over — leaving it up would let a receipt Roblox retries
		later in the same session roll a car at a player who is no longer looking at a card. ]]
	local rollNow = self._awaiting[player] == true
	self._awaiting[player] = nil

	--[[ The roll is spawned, not awaited: the pull is already in the save, which is all the receipt
		has to know, and a reveal that yields or errors must not turn a banked purchase into a retry
		that banks it twice. ]]
	if rollNow then
		task.spawn(self._roll, self, player)
		return true
	end

	--[[ Otherwise it stays banked and the client is told, which repaints the card as OPEN. For a
		player still in the lobby that is one press away from the same outcome; for one who has gone
		it is a pull waiting on their next session. ]]
	self:_publish(player)
	return true
end

-- === The roll ===============================================================

--[[ Which bay a car ended up on, or nil if it is not standing on the lot.

	READ BACK RATHER THAN PREDICTED. `awardCar` returns the OUTCOME and not the bay, and this
	service must not work the bay out for itself: "which bay was free" and "which bay was worst" are
	that function's rules, and a copy of them here would be a second answer that disagrees the first
	time either moves. So the award happens, and then the lot is asked where the car went — which is
	a fact rather than a re-derivation.

	MATCHED ON THE CAR ID `awardCar` HANDED BACK, not on the body and not on the key. It was the key
	(body and colour) until 2026-09-28, which was enough while a player could only own one copy of a
	model; once two red Camaros can both be kept, a key match finds whichever was parked first and
	could celebrate the wrong podium. `locationOf` answers for exactly the car just rolled. ]]
function RandomCarService._bayOf(self, Garage, player: Player, id: string): number?
	local where, bay = Garage:locationOf(player, id)
	return if where == "Bay" then bay else nil
end

--[[ Spend one pull and roll it. Everything in here is the server's: the world, the seed, the car,
	the colour and what happens to it.

	=== THE ORDER IS DECREMENT, THEN AWARD, AND THAT IS DELIBERATE ============================

	The opposite order reads better — award the car, and only take the pull once it worked — and it
	is the wrong risk. `awardCar` yields (it writes the profile and rebuilds the lot), so between an
	award and a decrement there is a window in which the player still holds the pull they have just
	spent; a second press inside it rolls again for free. Decrementing first inverts the failure: the
	bad case is a pull consumed by an award that then failed, which is one car owed to one player and
	shows up in the log below, rather than an unbounded free-roll window.

	`_rolling` closes the same window from the other side and is the real guard — see the header.
	Both, because the latch is per-server state and the decrement is durable. ]]
function RandomCarService._roll(self, player: Player)
	if self._rolling[player] then
		return
	end
	--- Opening a pull is "interacting with a paid random item" too, so a restricted player's banked
	--- pull stays banked. Checked here rather than at each caller so no path can skip it.
	if not self:canPull(player) then
		self:_publish(player)
		return
	end

	local profile = self:_profile(player)
	if not profile or self:getPulls(player) <= 0 then
		self:_publish(player)
		return
	end

	local Garage = Shard.get("GarageService")
	if not Garage then
		self.log:warn("No GarageService — a pull cannot be awarded, so it has not been spent.")
		return
	end

	--[[ The world they are STANDING in, off the attribute `WorldService` owns — never off anything
		the client sent. `WorldConfig.resolve` makes an unwritten attribute (the first frames of a
		session) into world 1 rather than into nothing. ]]
	local world = WorldConfig.resolve(player:GetAttribute(WorldConfig.WorldAttribute))

	--[[ A stream this roll owns. Seeded off the clock and the player so two players pulling on the
		same frame cannot get the same car, and LOGGED with the outcome so a "I paid and got a
		beater" ticket can be re-run rather than argued about — `RandomCarConfig.roll`'s header. ]]
	local seed = os.clock() * 1e6 + player.UserId
	local rng = Random.new(seed)

	local entry = RandomCarConfig.roll(world, rng)
	if not entry then
		self.log:warn(string.format("World %d has no cars to roll — %s's pull has not been spent.", world, player.Name))
		return
	end

	self._rolling[player] = true

	profile:Decrement(RandomCarConfig.ProfileKey, 1)

	--[[ The colour is rolled too, and it is not decoration: `GarageConfig.Banking` makes body AND
		colour the identity of a car, so a red Camaro is genuinely a car you do not have when you own
		the black one. Rolling it off the body's own pool is what makes a second pull of a body you
		already own still able to be a new car rather than an automatic duplicate. ]]
	local paint = PaintConfig.roll(rng, entry.Name)

	--[[ No mutation. Weather mutations are something the WORLD did to a car while it was being
		stolen (`WeatherService.couldHaveSpawned` bounds them against the schedule), and a car handed
		over at a shop counter was never out in any weather. Selling one for Robux would also make
		the rarest thing in the game purchasable, which is a different product than this one. ]]
	local outcome, cash, id = Garage:awardCar(player, entry.Tier, entry.Name, paint, nil)

	self._rolling[player] = nil

	if outcome == "rejected" then
		--[[ The garage refused it — no profile, or a body that is not on the roster. The pull is
			already spent, so this is the one branch that owes the player something; it is put back
			rather than logged and forgotten. ]]
		profile:Increment(RandomCarConfig.ProfileKey, 1)
		self.log:warn(string.format("%s's pull rolled a %s the garage refused; the pull has been returned.", player.Name, entry.Name))
		self:_publish(player)
		return
	end

	--- A pulled car starts off sale (`GarageConfig.Banking.PaidCarsNotForSale`).
	if id and GarageConfig.Banking.PaidCarsNotForSale then
		Garage:setCarFlag(player, id, InventoryConfig.Keys.NotForSale, true)
	end

	local bay = if id and (outcome == "parked" or outcome == "upgraded") then self:_bayOf(Garage, player, id) else nil

	local pull: Pull = {
		body = entry.Name,
		tier = entry.Tier,
		paint = paint,
		rarity = entry.Rarity,
		outcome = outcome,
		bay = bay,
		cash = cash,
		rate = GarageConfig.rateOf(entry.Tier, nil),
		pulls = self:getPulls(player),
	}

	self.log:info(
		string.format(
			"%s pulled a %s %s (Tier %d, %s) in world %d — %s. seed=%d",
			player.Name,
			PaintConfig.nameOf(paint),
			entry.Name,
			entry.Tier,
			tostring(entry.Rarity),
			world,
			outcome,
			seed
		)
	)

	self:getRemoteEvent("RandomCarRolled"):Fire(player, pull)
	self:_publish(player)
end

-- === The card ===============================================================

--- The client's "my card exists, what should it say" ping. One publish; the card draws itself from
--- it and from config, and needs nothing else until something changes.
function RandomCarService._onReady(self, player: Player)
	self._ready[player] = true
	self:_publish(player)
end

--[[ They pressed the card. Two answers and the server picks:

	HOLDING A PULL -> roll it, and charge nothing. That is the whole reason a receipt banks rather
	than rolls: a purchase made on a session that ended is a pull they still own, and the press that
	spends it must not open a second Robux prompt. `OfflineConfig.Boost`'s owned-state button makes
	the identical bargain and its header says why a struck-through price would read as a double
	charge.

	HOLDING NONE -> open Roblox's prompt. Money only ever moves on a RECEIPT, which arrives at
	`grantPull` — nothing here pays out, and `PromptProductPurchaseFinished` below is used only to
	take the flag down. ]]
function RandomCarService._onBuy(self, player: Player)
	--- Restricted, or not yet cleared: no prompt and no roll. The publish repaints a card that should
	--- not have been pressable, which only a client ignoring its state could have done.
	if not self:canPull(player) then
		self:_publish(player)
		return
	end

	if self:getPulls(player) > 0 then
		self:_roll(player)
		return
	end

	self:_prompt(player)
end

function RandomCarService._prompt(self, player: Player)
	self._awaiting[player] = true

	--[[ Report the prompt being SHOWN, which is the half of the conversion a receipt cannot tell
		you: a receipt says somebody bought, and only the pair says how many were asked. Fired before
		the prompt rather than after, so a prompt that throws below is still counted as offered —
		that failure is exactly the one worth seeing in the funnel. ]]
	local Analytics = Shard.get("AnalyticsService")
	if Analytics then
		Analytics:PromptShown(player, RandomCarConfig.ProductId)
	end

	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, RandomCarConfig.ProductId)
	end)
	if not ok then
		self._awaiting[player] = nil
		--- Unlocks the client, which is locked waiting on a modal that never opened.
		self:_publish(player)
		self.log:warn(string.format("Could not prompt %s for a random car: %s", player.Name, tostring(err)))
	end
end

-- === Lifecycle ==============================================================

--[[ Cache the profile off the join path.

	It hangs off `GarageService.ProfileReady` rather than `PlayerAdded` for the reason
	`OfflineService._watch` gives: that signal is precisely "the profile has arrived and everything
	derived from it has been published", so `GetProfileAsync` returns immediately here. It is called
	at all so this service holds its own handle rather than reaching into another service's cache.

	A player holding a pull from a previous session is told about it here — that is the other half
	of banking, and the reason `_publish` runs on a join that bought nothing. ]]
function RandomCarService._watch(self, player: Player)
	task.spawn(function()
		local ok, profile = pcall(function()
			return Data:GetProfileAsync(player)
		end)
		if not ok or not profile or player.Parent ~= Players then
			return
		end
		if not profile:IsActive() then
			return
		end
		self._profiles[player] = profile

		--- Only if the client has already said it is listening; otherwise `_onReady` does it, and a
		--- remote fired at a client whose controllers have not started is a remote nobody hears.
		if self._ready[player] then
			self:_publish(player)
		end
	end)
end

RandomCarService:withLifecycle({
	init = function(self)
		self._profiles = {} :: { [Player]: any }
		self._ready = {} :: { [Player]: boolean }
		--- "This player pressed the card and is sitting in front of the modal we opened." See
		--- `grantPull` on why a receipt with no flag behind it is banked instead of rolled.
		self._awaiting = {} :: { [Player]: boolean }
		--- Held across `awardCar`, which yields. One boolean against a double-roll — see the header.
		self._rolling = {} :: { [Player]: boolean }
		--- PolicyService's answer per player: true may buy and open pulls. Absent is "not yet asked or
		--- not yet answered", which `canPull` treats as no.
		self._allowed = {} :: { [Player]: boolean }
		self._trove = Trove.new()
	end,

	start = function(self)
		if not (RandomCarConfig.Enabled and GarageConfig.Enabled) then
			self.log:info("Disabled by config — no random car card and no pulls are sold.")
			return
		end

		if RandomCarConfig.ProductId == 0 then
			--[[ Declared but never synced. The card comes off the client's screen (`sellable` is
				false in the state it is sent), which is the honest outcome — an offer nobody can buy
				is worse than no offer, the same call `ReviveService._tierFor` makes about a rung with
				no product behind it. ]]
			self.log:warn("No product id — run `rbxsync sync` to create it. The card will not be shown.")
		end

		--[[ The eligibility check, before anything that could sell. Asked on join rather than on the
			press so the card is already right when it first slides in, and so the press itself never
			waits on a web call. ]]
		self._trove:Add(Players.PlayerAdded:Connect(function(player: Player)
			self:_checkPolicy(player)
		end))
		for _, player in Players:GetPlayers() do
			self:_checkPolicy(player)
		end

		local Garage = Shard.get("GarageService")
		if not Garage then
			self.log:warn("No GarageService — there is nowhere to put a car that was pulled.")
			return
		end

		self._trove:Add(Garage:getSignal("ProfileReady"):Connect(function(player: Player)
			self:_watch(player)
		end))

		--[[ Catch up on anyone already ready, for `OfflineService`'s reason: `GarageService` fires
			that signal off the join path, so on a hot reload — or simply if it starts first — a
			player can already be warm by the time this connects. ]]
		for _, player in Players:GetPlayers() do
			if Garage:isProfileReady(player) then
				self:_watch(player)
			end
		end

		--[[ A prompt that closed WITHOUT a purchase. The flag has to come down or a receipt retried
			from some other session would be treated as "they are looking at the card right now".

			The client is told either way, which unlocks its card: on a cancel the count is unchanged
			and the card repaints to exactly what it already said, and on a purchase this fires
			BEFORE the receipt does — so `wasPurchased` is deliberately not used to roll anything.
			A car only ever moves on a receipt. ]]
		if RandomCarConfig.sellable() then
			self._trove:Add(MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, wasPurchased)
				if productId ~= RandomCarConfig.ProductId then
					return
				end
				local player = Players:GetPlayerByUserId(userId)
				if not player then
					return
				end
				if not wasPurchased then
					self._awaiting[player] = nil
					self:_publish(player)
				end
			end))
		end

		self._trove:Add(Players.PlayerRemoving:Connect(function(player: Player)
			self._profiles[player] = nil
			self._ready[player] = nil
			self._awaiting[player] = nil
			self._rolling[player] = nil
			self._allowed[player] = nil
		end))
	end,
})

RandomCarService:withCleanup(function()
	if RandomCarService._trove then
		RandomCarService._trove:Destroy()
	end
end)

return RandomCarService
