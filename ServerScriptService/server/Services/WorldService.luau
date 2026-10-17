--[[
	WorldService  (server)
	----------------------
	Which world each player is in. That is the whole service, and it is small on purpose: a world
	is a road and a car ladder (see `WorldConfig`), and BOTH of those are read from an index — so
	the only thing that has to be owned centrally is the index itself.

	=== WHY THIS IS PER PLAYER AND NOT A SERVER SETTING ========================================

	Driving is solo and the road is client-built (`RoadController`), so two players in one server
	can be racing two different worlds with nothing to reconcile: neither one's road exists on the
	other's machine, and neither one's traffic is simulated anywhere but locally. The server's only
	stake is the car it spawns and the frame it validates hits against, and both of those already
	take a player. Making the world global would therefore have bought nothing and cost the
	teleport screen its meaning.

	=== THE ATTRIBUTE IS THE BROADCAST, THE PROFILE IS THE TRUTH ===============================

	`player:GetAttribute(WorldConfig.WorldAttribute)` is how every client and every other service
	reads this — the same house pattern as cash, ownership and the lot. Nothing sends a remote to
	ask, and nothing but this service writes it. The value that survives a rejoin lives in the
	profile under `WorldConfig.ProfileKey`.

	The attribute is written IMMEDIATELY on join, from the default, and then again when the profile
	arrives. That ordering is deliberate: a race can start before a profile has loaded (the Play
	button is on screen from the first frame), and an absent world attribute would send that run to
	`WorldConfig.resolve`'s fallback anyway — so publishing the default up front means the value is
	never missing, only sometimes not yet the player's own. It cannot be wrong for a run in
	progress either, because…

	=== YOU CANNOT CHANGE WORLDS MID-RACE ======================================================

	…`setWorld` refuses while `RaceService:isRacing`. The road under the car was built from this
	index at `RaceStart` and there is no way to swap it out from under a moving car: the client
	would have to tear down and rebuild nine tiles while the player is driving on them. Refusing is
	not a limitation to work around later, it is what "the run you are in is the world you are in"
	means. The teleport screen greys itself out during a run for the same reason.

	=== AND HOW FAR YOU HAVE GOT DOWN EACH ONE =================================================

	The second thing this owns, added when the collection screen grew a MAPS tab: the furthest each
	player has ever driven on each world's road. Same shape as the index above and for the same
	reasons — the profile is the truth (`WorldConfig.ProgressKey`, in studs) and an attribute is the
	broadcast (`WorldConfig.ProgressAttribute`, as a percentage).

	IT LIVES HERE BECAUSE A WORLD IS THE THING BEING PROGRESSED THROUGH, and this service already
	owns "which world". `RewardService` measures a run's distance and hands it over at settle; it
	does not know or care that anything keeps a best.

	THE PERCENTAGE IS COMPUTED HERE AND NOT ON THE CLIENT because it needs the road's authored
	`SegmentLength`, which lives on the tiles and is `RoadService`'s to know. Recomputed on every
	publish rather than stored, so retuning a ladder or re-authoring a road re-derives every profile
	that already exists — see `WorldConfig.encodeProgress`.

	=== AND WHETHER YOU HAVE EARNED IT ==========================================================

	The third thing this owns: worlds are bought. `WorldConfig` holds the rule (a price, and from
	world 3 on a demand that you have finished the world before it) and this owns the money, the
	storage and the one function allowed to say yes — `unlockWorld`. Same split as everywhere else:
	the profile keeps the number, an attribute broadcasts it, and `WorldConfig.isUnlocked` reads the
	attribute so the card and the guard are answering off the same fact.

	THE SECOND WAY IN IS `setUnlocked`, AND IT IS NOT A PURCHASE. The F2 panel's Maps tab hands a
	world over (or takes it back) with no price and no previous road asked for, so a course can be
	driven before the ladder that leads to it exists. It is a separate function precisely so that
	nothing about the transaction above can be skipped by an argument, and it is reached only through
	`AdminService`, which re-checks `Admins` on its own side.

	BOTH CONDITIONS ARE CHECKED ONCE, AT THE TILL. Owning a world is a fact about the player from
	then on — `isUnlocked` asks nothing but ownership — so retuning the traffic bands (which moves
	every player's map percentage) cannot take back a world that was already paid for.

	THE SAVED WORLD IS CLAMPED ON LOAD, and that is a change of position worth knowing about. This
	used to say that taking a place away from someone standing in it is a migration and not a guard,
	which was right while every world was open. It is not right now: `setWorld` answers "you are
	already there" before it checks anything (it must — that is what makes it idempotent), and the
	lobby pad enters whatever world you are in without naming one. So a profile that names a world
	you do not own would be a permanent free pass to it. Loading such a profile drops the player to
	the best world they DO own rather than refusing them a world entirely.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data = require(script.Parent.Parent.Data)
local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local WorldService = Shard.new("WorldService")

WorldService:withSignals({
	--[[ (player: Player, index: number, previous: number) — this player is now in a different
		world. Nothing listens yet; it exists so that whatever eventually has to react to the move
		(a lobby that re-dresses itself, a quest board) does not have to poll the attribute. ]]
	"WorldChanged",

	--[[ (player: Player, index: number, cost: number) — this player just bought a world.
		`AnalyticsService` counts it. The buyer's own client hears about it through the `WorldBought`
		remote below, which is what plays the unlock sound. ]]
	"WorldUnlocked",
})

WorldService:withRemoteEvents({
	{
		--[[ client -> server (index: number, offerOnly: boolean?): buy me this world, or with
			`offerOnly` just offer me the cash for it. Every guard is in `unlockWorld`; this is only the
			untrusted front door, and it answers nothing — the unlock attribute replicating IS the
			answer, the same bargain `RequestSetWorld` makes below. ]]
		RequestUnlockWorld = function(player: Player, index: unknown, offerOnly: unknown)
			WorldService:unlockWorld(player, index, offerOnly == true)
		end,

		--[[ client -> server (index: number): move me, without racing. Every guard is in `setWorld`;
			this is only the untrusted front door.

			NOTHING FIRES IT TODAY. The world screen's cards ask for a RACE in a world now
			(`RaceService._onEnterRequest`, which moves the player first), so the two halves that
			used to be two presses are one. Kept because "move a player without starting a run" is
			a real thing to want — an admin command, a lobby that walks you somewhere — and this is
			where that already is. ]]
		RequestSetWorld = function(player: Player, index: unknown)
			WorldService:setWorld(player, index)
		end,
	},

	--[[ server -> client (index: number, cost: number): you just bought this world. Purely cosmetic
		and fired LAST, after the money and the unlock have both been stored, so a client that misses
		it loses nothing but the sound (`WorldConfig.UnlockSound`). Not fired for an admin grant. ]]
	"WorldBought",
})

-- === Reading ================================================================

--[[ Which world this player is in. Never nil and never out of range: an unwritten attribute (the
	first frames of a session) and a junk one (nothing writes those, but this is read on paths that
	also serve remotes) both come back as the default. ]]
function WorldService.worldOf(self, player: Player): number
	return WorldConfig.resolve(player:GetAttribute(WorldConfig.WorldAttribute))
end

--- The profile, or nil if it has not loaded yet. Non-yielding, same contract as GarageService's.
function WorldService._profile(self, player: Player)
	local profile = self._profiles[player]
	if profile and profile:IsActive() then
		return profile
	end
	return nil
end

-- === Writing ================================================================

--- Put the index on the player and (if their profile is here) in it. The single write path.
function WorldService._publish(self, player: Player, index: number, persist: boolean)
	player:SetAttribute(WorldConfig.WorldAttribute, index)
	if persist then
		local profile = self:_profile(player)
		if profile then
			profile:Set(WorldConfig.ProfileKey, index)
		end
	end
end

--[[ Public: move a player to a world. Returns whether they moved, and why not if they didn't —
	the reason is for the log and for a future "you need X first" line on the card, not for the
	client, which is told nothing beyond the attribute changing.

	Idempotent: asking for the world you are already in succeeds and writes nothing. ]]
function WorldService.setWorld(self, player: Player, index: unknown): (boolean, string?)
	local wanted = tonumber(index)
	--[[ Validated rather than resolved. `WorldConfig.resolve` exists to make a stale or missing
		READ safe; silently rounding a bad REQUEST to world 1 would answer "teleport me to 9" with
		a teleport, which is the one thing a request must never do. ]]
	if not wanted or wanted ~= wanted or wanted % 1 ~= 0 or not WorldConfig.Worlds[wanted] then
		return false, "no such world"
	end

	if self:worldOf(player) == wanted then
		return true
	end

	local RaceService = Shard.get("RaceService")
	if RaceService and RaceService:isRacing(player) then
		return false, "mid-race"
	end

	if not WorldConfig.isUnlocked(wanted, player) then
		return false, "locked"
	end

	local previous = self:worldOf(player)
	self:_publish(player, wanted, true)
	self.log:info(string.format("%s -> world %d (%s).", player.Name, wanted, WorldConfig.displayName(wanted)))
	self:getSignal("WorldChanged"):Fire(player, wanted, previous)
	return true
end

-- === Buying a world =========================================================

--- The highest world this player owns. Read off the attribute — the same value the client reads,
--- so a card and this service can never disagree about what is owned.
function WorldService.highestUnlocked(self, player: Player): number
	return WorldConfig.highestUnlocked(player)
end

--- Put the number on the player and (if their profile is here) in it. The single write path, and
--- the mirror of `_publish` above.
function WorldService._publishUnlocked(self, player: Player, highest: number, persist: boolean)
	if player.Parent ~= Players then
		return
	end
	player:SetAttribute(WorldConfig.UnlockAttribute, highest)
	if persist then
		local profile = self:_profile(player)
		if profile then
			profile:Set(WorldConfig.UnlockProfileKey, highest)
		end
	end
end

--[[ Public: buy a world. Returns whether it was bought and why not if it wasn't — the reason is
	for the log, not for the client, which is told nothing beyond the attribute changing.

	SHAPED LIKE `UpgradeService._onRequest` because it is the same transaction — cooldown, eligible,
	afford, take, store, refund if the store failed — and that file is where the reasoning for each
	step is written down. The one thing added here is that eligibility has TWO halves and the money
	is only the second: a player who has not finished the previous map is refused before their
	balance is ever looked at, so they can never be charged for a world they were not offered.

	`WorldConfig.unlockStateFor` is what decides both halves, and it is the SAME call the card
	paints itself from. That is deliberate — a screen offering a purchase the server would refuse is
	the failure this shares one function to prevent — but it is not trust: the cash it is handed here
	is the profile's, never the client's.

	`offerOnly` IS THE PRESS OF A PLAYER WHO IS SHORT (2026-09-30, Aleafo: the Buy button is green
	always, and pressing it without the money prompts a cash pack). That press skips the card's
	CONFIRM? step, because all it can do is open Roblox's own purchase window. So it must never be
	able to BUY: the client decided it was short off a replicated balance that can be a hop behind
	this one, and a press that landed the moment a grant made the world affordable would otherwise
	spend the money with no confirm at all. Short, it gets the offer like any other short press;
	not short after all, it gets nothing, and the card turns into an ordinary Buy as the cash
	replicates. ]]
function WorldService.unlockWorld(self, player: Player, index: unknown, offerOnly: boolean?): (boolean, string?)
	local wanted = tonumber(index)
	-- Validated rather than resolved, exactly as `setWorld` documents: rounding a bad REQUEST to
	-- world 1 would answer "buy me world 9" with a purchase.
	if not wanted or wanted ~= wanted or wanted % 1 ~= 0 or not WorldConfig.Worlds[wanted] then
		return false, "no such world"
	end

	local now = os.clock()
	if now - (self._purchaseCooldowns[player] or 0) < WorldConfig.PurchaseCooldown then
		return false, "too soon"
	end
	self._purchaseCooldowns[player] = now

	local GarageService = Shard.get("GarageService")
	if not (GarageService and GarageService:isProfileReady(player)) then
		return false, "no profile"
	end

	local cash = GarageService:getCash(player)
	local state, detail = WorldConfig.unlockStateFor(wanted, player, cash)
	if state == "open" then
		-- Already owned, or free. Idempotent and silent, the same answer `setWorld` gives for the
		-- world you are already in: nothing was bought and nothing went wrong.
		return true
	end
	if state ~= "buy" then
		return false, state
	end
	if not detail.affordable then
		--[[ The one refusal in this function with an answer to it. `CashService` offers the cheapest
			cash pack that covers what is MISSING rather than what the world is priced at, and the
			request is still refused: nothing is held pending across a modal, so a player who buys
			presses the tile again and comes back through every gate above. `CashConfig`'s header
			argues why the gap and not the price is what makes that offer defensible. ]]
		local CashService = Shard.get("CashService")
		if CashService then
			CashService:offerTopUp(player, detail.cost - cash, string.format("world %d", wanted))
		end
		return false, "too dear"
	end
	--- Affordable, but this press only ever asked for the offer. See `offerOnly` above.
	if offerOnly then
		return false, "offer only"
	end

	local cost = detail.cost
	GarageService:addCash(player, -cost)
	--[[ ASSERT THE FULL PRICE CAME OUT. `addCash` clamps at zero, so if the affordability test above
		and this charge ever disagreed about the balance, the clamp would quietly hand over the world
		for whatever the player happened to have. Nothing yields between the two today — this cannot
		fire as the code stands — and it is here anyway, because the thing it is protecting is a
		price and the cost of being wrong about it is a world given away.

		Refuse and refund rather than sell it short. The player is out nothing and can press again. ]]
	if GarageService:getCash(player) > cash - cost then
		GarageService:addCash(player, cost)
		self.log:warn(string.format(
			"%s's balance did not move by the full price of world %d; refunded.", player.Name, wanted))
		return false, "balance moved"
	end

	local profile = self:_profile(player)
	if not profile then
		-- The profile went away between the check and the write. Give the money back rather than
		-- charging for a world that was never stored — `UpgradeService` makes the same trade.
		GarageService:addCash(player, cost)
		return false, "no profile"
	end

	self:_publishUnlocked(player, wanted, true)
	self.log:info(string.format(
		"%s unlocked world %d (%s) for %d.", player.Name, wanted, WorldConfig.displayName(wanted), cost))
	self:getSignal("WorldUnlocked"):Fire(player, wanted, cost)
	self:getRemoteEvent("WorldBought"):Fire(player, wanted, cost)
	return true
end

--[[ Public (AdminService): give a player worlds 1..index outright, or take them back down to it.

	THE ONE WAY IN THAT IS NOT A TILL, and deliberately a second function rather than a `free` flag
	on `unlockWorld`: the price, the previous road, the charge and the refund if the write failed are
	that function's entire body, and an argument that skipped all four would have been a branch
	through every step of a transaction. This writes the number, and nothing above it applies.

	IT GOES DOWN AS WELL AS UP, because what it is for is testing and a gate you cannot put back is a
	gate you can only walk through once. Going down RE-CLAMPS WHERE THE PLAYER IS STANDING, exactly
	as `_onPlayerAdded` clamps a saved world and for the reason the header gives: what you own and
	where you are are two numbers, and leaving them disagreeing is the permanent free pass.

	Refused mid-race when it would move somebody, for the reason `setWorld` refuses: the road under
	the car was built from that index at `RaceStart` and cannot be swapped out from under it.

	NO `WorldUnlocked` SIGNAL. `AnalyticsService` counts that signal as a world EARNED, and a world
	an admin handed over is not something a player did — the same reading `AdminService.cash` takes
	of its own missing resource event. The audit line there is the record. ]]
function WorldService.setUnlocked(self, player: Player, index: unknown): (boolean, string?)
	local wanted = tonumber(index)
	-- Validated rather than resolved, for `unlockWorld`'s reason: rounding a bad request to world 1
	-- would answer "unlock world 9" by silently locking everything.
	if not wanted or wanted ~= wanted or wanted % 1 ~= 0 or not WorldConfig.Worlds[wanted] then
		return false, "no such world"
	end

	--[[ Refused rather than granted for this session only. `_publishUnlocked` would happily write the
		attribute and drop the profile write on the floor, and an unlock that quietly disappears on
		the next join is the one answer a debug tool cannot afford to give. Same call `unlockWorld`
		makes at the same point. ]]
	if not self:_profile(player) then
		return false, "no profile"
	end

	local standing = self:worldOf(player)
	local moving = standing > wanted
	if moving then
		local RaceService = Shard.get("RaceService")
		if RaceService and RaceService:isRacing(player) then
			return false, "mid-race"
		end
	end

	self:_publishUnlocked(player, wanted, true)
	self.log:info(string.format(
		"%s now owns worlds 1-%d (up to %s), by admin.", player.Name, wanted, WorldConfig.displayName(wanted)))

	if moving then
		self:_publish(player, wanted, true)
		self.log:info(string.format(
			"%s was standing in world %d, which they no longer own; moved to %d.", player.Name, standing, wanted))
		self:getSignal("WorldChanged"):Fire(player, wanted, standing)
	end

	return true
end

-- === How far down each road ==================================================

--- The stored bests, world index -> studs. Always a table; a profile that has not loaded (or a
--- player who has never driven) is an empty one, which reads as 0% everywhere downstream.
function WorldService._bests(self, player: Player): { [number]: number }
	local profile = self:_profile(player)
	local stored = profile and profile:Get(WorldConfig.ProgressKey)
	local bests = {}
	if type(stored) ~= "table" then
		return bests
	end
	-- String keys on the way in — see the profile template's note on why they are stored that way.
	for key, studs in stored do
		local index = tonumber(key)
		if index and WorldConfig.Worlds[index] and type(studs) == "number" and studs == studs then
			bests[index] = math.max(studs, 0)
		end
	end
	return bests
end

--[[ Turn the stored studs into the percentages the client reads, and put them on the player.

	PRESENT MEANS MEASURABLE, ABSENT MEANS THE MAP CANNOT BE SCORED YET — a world with no published
	road has no `SegmentLength`, and a one-rung ladder has no top tile, so neither has a denominator.
	A world that IS measurable and has never been driven is published at 0, so the screen can tell
	"you have not been there" from "there is nothing there yet" and say the honest one. 0% for a map
	that does not exist would be a lie about the player rather than about the map.

	The stored best is kept either way, so the day a road lands the number is already there. ]]
function WorldService._publishProgress(self, player: Player)
	local bests = self:_bests(player)
	local RoadService = Shard.get("RoadService")
	local progress = {}

	for index = 1, #WorldConfig.Worlds do
		local segment = RoadService and RoadService:getSegmentLength(index)
		local top = WorldConfig.MapCompletionTiles
		if segment and segment > 0 and top then
			local studs = bests[index] or 0
			progress[index] = { fraction = math.clamp(studs / segment / top, 0, 1), studs = studs }
		end
	end

	player:SetAttribute(WorldConfig.ProgressAttribute, WorldConfig.encodeProgress(progress))
end

--[[ Public (RewardService): a run on `world` reached `studs`. Keeps the best and republishes.

	A BEST, NOT A TOTAL. This is "how far down this road have you got", so a short run after a long
	one takes nothing away — and it is why a wrecked run counts exactly as much as a banked one, the
	way the results screen's ladder bar already treats them. Returns whether it was a new record, so
	a caller that wants to celebrate one can.

	Writes nothing for a player whose profile has not arrived. That is a real case (a run can finish
	before a slow load) and it is the same answer `GarageService.addCash` gives: losing one run's
	record is better than a yield on the settle path or a write into a profile that is not there. ]]
function WorldService.recordDistance(self, player: Player, world: unknown, studs: unknown): boolean
	local index = WorldConfig.resolve(world)
	if type(studs) ~= "number" or studs ~= studs or studs <= 0 then
		return false
	end

	local profile = self:_profile(player)
	if not profile then
		return false
	end

	local bests = self:_bests(player)
	if (bests[index] or 0) >= studs then
		return false -- not a record; nothing to write and nothing to republish
	end

	--[[ CLONE-AND-SET rather than a mutation, the same shape `GarageService._addOwned` uses: the
		table handed back by `Get` is the profile's own, and editing it in place writes a change the
		profile never saw and cannot save. ]]
	local stored = profile:Get(WorldConfig.ProgressKey)
	local next_ = {}
	if type(stored) == "table" then
		for key, value in stored do
			next_[key] = value
		end
	end
	next_[tostring(index)] = math.floor(studs)
	profile:Set(WorldConfig.ProgressKey, next_)

	self:_publishProgress(player)
	self.log:info(string.format(
		"%s set a new best on %s: %d studs.", player.Name, WorldConfig.displayName(index), math.floor(studs)))
	return true
end

-- === Joining ================================================================

--[[ Publish the default now, the saved world when it arrives.

	The re-check after the yield is the same one GarageService documents: `GetProfileAsync` can take
	seconds, and a player who joins and leaves inside that window must not have an attribute written
	onto a Player instance that has already been destroyed. ]]
function WorldService._onPlayerAdded(self, player: Player)
	self:_publish(player, WorldConfig.ActiveIndex, false)
	-- An empty string, not nothing: the collection screen reads this the frame it is built, and
	-- "nobody has driven anywhere" is an answer while a missing attribute is a question.
	player:SetAttribute(WorldConfig.ProgressAttribute, "")
	--[[ World 1 up front, for the same reason the world index is published before the profile
		arrives: the world screen is reachable from the first frame, and "you own the free world"
		is the honest answer for a player whose save has not landed yet. It can only go UP when it
		does — nothing here can strand a player below what they paid for. ]]
	self:_publishUnlocked(player, 1, false)

	task.spawn(function()
		local ok, profile = pcall(function()
			return Data:GetProfileAsync(player)
		end)
		if not ok or not profile or player.Parent ~= Players then
			return
		end
		self._profiles[player] = profile

		--[[ What they own, before where they are — the clamp below reads it. Resolved through the
			same helper the client uses so both sides agree, and floored at 1 because world 1 is
			free and a profile written before this key existed has nothing to say. ]]
		local owned = math.clamp(
			math.floor(tonumber(profile:Get(WorldConfig.UnlockProfileKey)) or 1),
			1,
			#WorldConfig.Worlds)
		self:_publishUnlocked(player, owned, false)

		--[[ Resolved, not trusted. A profile can name a world that no longer exists — the list is
			hand-edited and worlds have already been added to it once — and a save that points off
			the end of it should cost the player their choice, not their session. ]]
		local saved = WorldConfig.resolve(profile:Get(WorldConfig.ProfileKey))

		--[[ CLAMPED TO WHAT THEY OWN, which is the guard the header explains. `setWorld` cannot do
			this job: it answers "you are already there" before it checks anything, and the lobby pad
			enters whatever world you are standing in without naming one — so a save pointing at an
			unowned world would be a permanent free pass to it. Falling back to the best world they
			DO own (rather than refusing, or dropping to world 1) is the reading that costs a player
			nothing they earned.

			It bites exactly one population: saves written while every world was open. Nothing is
			taken from anybody who bought their way there. ]]
		if not WorldConfig.isUnlocked(saved, player) then
			self.log:info(string.format(
				"%s's saved world %d is not unlocked (owns %d); dropping them to it.",
				player.Name, saved, owned))
			saved = owned
		end
		self:_publish(player, saved, false)
		-- Derived here rather than stored, so a retuned ladder or a re-authored road re-prices an
		-- existing save on the next join instead of leaving it on the scale it was set against.
		self:_publishProgress(player)
	end)
end

WorldService:withLifecycle({
	init = function(self)
		self._profiles = {} :: { [Player]: any }
		self._purchaseCooldowns = {} :: { [Player]: number }
		self._trove = Trove.new()
	end,

	start = function(self)
		self._trove:Add(Players.PlayerAdded:Connect(function(player)
			self:_onPlayerAdded(player)
		end))
		self._trove:Add(Players.PlayerRemoving:Connect(function(player)
			self._profiles[player] = nil
			self._purchaseCooldowns[player] = nil
		end))
		-- Anyone already in (Studio's own player joins before services start).
		for _, player in Players:GetPlayers() do
			self:_onPlayerAdded(player)
		end
	end,
})

return WorldService
