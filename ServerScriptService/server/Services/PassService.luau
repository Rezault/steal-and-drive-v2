--[[
	PassService  (server)
	---------------------
	THE ONE THING IN THE GAME THAT ANSWERS "DOES THIS PLAYER HAVE THAT PASS". Every seam behind
	every game pass asks this and nothing else, and the reason it exists as a service rather than as
	a two-line `UserOwnsGamePassAsync` at each site is that the answer now comes from TWO PLACES.

	=== OWNERSHIP IS A UNION, AND THAT IS THE WHOLE DESIGN ======================================

	    owns(player, key)  ==  bought it on Roblox   OR   was given it by another player

	`RadioConfig`'s header, `ShopConfig` note 5 and `rbxsync.toml`'s Game Passes section all state
	the older rule: a pass is owned on Roblox, `UserOwnsGamePassAsync` is the only copy that counts,
	and nothing about a pass belongs on a profile. That rule was right and is still right for every
	pass anybody BUYS.

	GIFTING BREAKS IT IN EXACTLY ONE DIRECTION AND THERE IS NO WAY AROUND IT. Roblox has no API for
	attaching a pass to an account someone else paid for: `PromptGamePassPurchase` charges the player
	it prompts and grants to that same player. So a gifted pass is a developer product whose receipt
	grants the entitlement itself, and the only place an entitlement can be recorded is the
	recipient's profile (`PassConfig.ProfileKey`).

	SO THERE ARE TWO SOURCES AND EXACTLY ONE READER OF BOTH, which is this file. That is the same
	bargain `GarageService` makes with `Cash` — many writers would mean many opinions — applied to a
	number that is now genuinely stored in two systems. No seam anywhere should read the profile key
	or call `UserOwnsGamePassAsync` itself; both are wrong on their own, in opposite cases.

	=== FAILURE IS NOT "NO" ====================================================================

	`RadioService` established this and it matters more here, because five passes now depend on it: a
	`UserOwnsGamePassAsync` that throws is Roblox having a bad minute, and caching that as false
	takes a paid pass away from its owner for the rest of their session AND offers to sell it to them
	again. A throw therefore leaves the cache exactly as it was — unknown on a join, whatever it was
	before otherwise — and `owns` answers false for unknown while `known` says the difference out
	loud for the one caller (a shop card) that should draw "checking" rather than a price.

	THE GIFT HALF NEVER FAILS THAT WAY, which is a quiet advantage of storing it: a gifted pass is
	read out of a profile that is already in memory, so a player whose Roblox lookup is failing still
	gets everything they were given.

	=== IT ASKS ROBLOX TWICE PER SESSION, NOT PER PRESS =========================================

	Once on the join, and again for one key when `PromptGamePassPurchaseFinished` says that key was
	just bought. Nothing polls, because a pass cannot be lost mid-session in any way this server
	would want to react to. A gift arriving mid-session comes in through `grant` and needs no web
	call at all.

	=== WHAT IT DOES NOT DO ====================================================================

	It sells nothing, prompts nothing and knows what none of the five passes actually DO. A seam asks
	one question and gets a boolean; whether that boolean means double HP or a swept lot is entirely
	the asking service's business. The one thing it broadcasts is the boolean itself, on
	`PassConfig.ownedAttribute(key)`, and that attribute decides nothing — see `PassConfig` note 4.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data = require(script.Parent.Parent.Data)
local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local PassConfig = require(ReplicatedStorage.shared.Configs.PassConfig)

local PassService = Shard.new("PassService")

PassService:withSignals({
	--[[ (player: Player, key: string, source: "bought" | "gifted") — this player now has a pass they
		did not have a moment ago. Fired AFTER the cache and the attribute are written, so a listener
		reading `owns` from inside the handler gets true.

		IT EXISTS FOR THE MID-SESSION PURCHASE, which is the moment a pass is most likely to look
		broken. Every seam reads `owns` when it next runs — the next spawn, the next sweep — and for
		most of them "next" is soon enough. It is not soon enough for a player who bought 2x Car HP
		while sitting in a car, so `ObstacleService` listens to this and re-stamps the ceiling on the
		spot. Anything with a similar "already running" state should do the same rather than polling.

		NOT FIRED ON THE JOIN REFRESH. A pass the player already had is not news, and a signal that
		also means "we have finished checking" would have every listener re-running its seam once per
		join for nothing. ]]
	"PassGranted",
})

-- === Reading ================================================================

--[[ PUBLIC, AND THE ONLY ANSWER. Does this player have this pass, bought or gifted?

	NON-YIELDING, so it is safe anywhere — inside a Touched handler, inside a physics step, on the
	spawn path. Every web call happens off the join path in `_refresh`; this only ever reads what
	that left behind.

	FALSE FOR UNKNOWN, which is the safe direction for a SEAM: a player whose lookup has not landed
	yet drives a normal car for a few seconds rather than the game handing out a pass it has not
	confirmed. A screen that wants to tell "no" from "not yet" asks `known` as well. ]]
function PassService.owns(self, player: Player, key: unknown): boolean
	if not PassConfig.Enabled then
		return false
	end
	local pass = PassConfig.get(key)
	if not (pass and pass.Live) then
		--[[ A pass whose seam is not written answers false even to a player who owns it on Roblox.
			That is deliberate: `Live` is this project's record of whether the behaviour exists, and
			a seam that has not been written cannot be switched on by somebody buying the pass. ]]
		return false
	end

	local cache = self._owned[player]
	if cache and cache[pass.Key] then
		return true
	end
	return self._gifted[player] ~= nil and self._gifted[player][pass.Key] == true
end

--[[ Has Roblox actually answered about this pass for this player yet?

	FOR SCREENS ONLY, and there is one: a shop card that shows a price to somebody who owns the pass
	is the failure `RadioService`'s header describes, so a card whose answer has not arrived draws
	"checking" instead. No seam should ever branch on this — a seam that behaves differently while a
	lookup is in flight is a seam with two behaviours. ]]
function PassService.known(self, player: Player, key: unknown): boolean
	local pass = PassConfig.get(key)
	if not pass then
		return false
	end
	local cache = self._owned[player]
	return cache ~= nil and cache[pass.Key] ~= nil
end

--- Every live pass key this player has, in `PassConfig.Passes` order. For the log and for the admin
--- panel; nothing in the game branches on the whole list.
function PassService.ownedKeys(self, player: Player): { string }
	local out = {}
	for _, pass in PassConfig.Passes do
		if self:owns(player, pass.Key) then
			table.insert(out, pass.Key)
		end
	end
	return out
end

-- === Writing ================================================================

--[[ PUBLIC (`DevProductsHandler`, `AdminService`). Give this player a pass outright.

	THIS IS THE GIFT HALF OF THE UNION AND IT IS THE ONLY WRITER OF `PassConfig.ProfileKey`. It
	writes the profile, warms the cache and broadcasts, in that order — the profile first because it
	is the durable copy and the one that has to survive the player leaving mid-call.

	IDEMPOTENT, AND THAT IS LOAD BEARING RATHER THAN TIDY. Roblox re-delivers a receipt it is not
	sure landed, so this runs twice for one purchase more often than anyone would like. Granting a
	pass twice has to be indistinguishable from granting it once, and a set keyed by pass key is
	exactly that — which is most of why `Passes` is a set and not a list (`Settings.TEMPLATE`).

	IT DOES NOT CARE WHETHER THEY ALREADY BOUGHT IT ON ROBLOX. Somebody can be gifted a pass they
	own, because the gifter cannot see what the recipient owns and should not be able to. The entry
	is written anyway and the union answers true either way; the alternative — refusing the grant —
	would turn a Robux purchase into nothing at all on a race the buyer could not have avoided.

	Returns whether it landed. False means no profile, which is a caller's cue to retry rather than
	to report success — see `DevProductsHandler`. ]]
function PassService.grant(self, player: Player, key: unknown): boolean
	local pass = PassConfig.get(key)
	if not pass then
		self.log:warn(string.format("Refused to grant %s an unknown pass '%s'.", player.Name, tostring(key)))
		--[[ TRUE, not false, and it is the only place in this file that answers that way for a
			failure. An unknown key is a message from a newer build or a typo, and neither is fixed
			by a retry — answering false would leave a gift receipt replaying on every join this
			player ever makes. Dropped and logged is the same call `GarageService`'s posted-cash
			handler makes about a malformed amount. ]]
		return true
	end

	local profile = Data:GetProfileAsync(player)
	if not profile then
		return false
	end

	local passes = profile:Get(PassConfig.ProfileKey)
	if type(passes) ~= "table" then
		passes = {}
	end
	if passes[pass.Key] ~= true then
		--[[ A fresh table rather than a mutation, because `Set` goes through the Replica and what is
			written has to be the whole value. Mutating the table in place and setting it back would
			work today and would silently stop replicating the day anything reads it from the client. ]]
		local next_ = table.clone(passes)
		next_[pass.Key] = true
		profile:Set(PassConfig.ProfileKey, next_)
	end

	local already = self._gifted[player] and self._gifted[player][pass.Key] == true
	self._gifted[player] = self._gifted[player] or {}
	self._gifted[player][pass.Key] = true
	self:_publish(player, pass.Key)

	if not already then
		self.log:info(string.format("%s was given the %s pass.", player.Name, pass.Key))
		self:getSignal("PassGranted"):Fire(player, pass.Key, "gifted")
	end
	return true
end

-- === The lookup =============================================================

--- Mirror the union onto the Player for whatever is drawing a card. See `PassConfig` note 4.
function PassService._publish(self, player: Player, key: string)
	if player.Parent ~= Players then
		return
	end
	player:SetAttribute(PassConfig.ownedAttribute(key), self:owns(player, key))
end

--[[ Ask Roblox about one pass and cache it. YIELDS.

	A THROW LEAVES THE CACHE ALONE — see the header. `nil` stays `nil` on a join, and a `true` from
	earlier in the session stays `true`, so the worst a bad minute at Roblox can do is delay an
	answer rather than revoke one.

	Returns whether the answer changed to true, so `_refresh` can tell a first read from a purchase
	without comparing tables. ]]
function PassService._ask(self, player: Player, key: string): boolean
	local id = PassConfig.idOf(key)
	if id == 0 then
		return false
	end

	local ok, owned = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
	end)
	if not ok then
		self.log:warn(string.format("Could not read %s's %s pass: %s", player.Name, key, tostring(owned)))
		return false
	end
	if player.Parent ~= Players then
		return false
	end

	local cache = self._owned[player]
	if not cache then
		return false -- they left and were cleaned up while the call was in flight
	end
	local was = cache[key]
	cache[key] = owned == true
	self:_publish(player, key)
	return owned == true and was ~= true
end

--[[ The join path: read the gift set out of the profile, then ask Roblox about every live pass.

	THE PROFILE FIRST AND THE WEB CALLS SECOND, because the profile read is the one that can be
	trusted to finish. A player whose Roblox lookups are all failing still gets everything they were
	gifted, and gets it before their first spawn rather than after six timeouts.

	THE WEB CALLS ARE SEQUENTIAL, not spawned in parallel. There are three live passes today and
	`UserOwnsGamePassAsync` is cached hard by the engine after the first hit per player; firing them
	together would save perhaps a hundred milliseconds on a path nothing is waiting on, and would
	make a rate limit at Roblox arrive as three failures instead of one. ]]
function PassService._refresh(self, player: Player)
	local profile = Data:GetProfileAsync(player)
	if player.Parent ~= Players then
		return
	end
	if profile then
		local passes = profile:Get(PassConfig.ProfileKey)
		local gifted = {}
		if type(passes) == "table" then
			for key, on in passes do
				if on == true and type(key) == "string" then
					gifted[key] = true
				end
			end
		end
		self._gifted[player] = gifted
	end

	self._owned[player] = self._owned[player] or {}
	for _, key in PassConfig.sellableKeys() do
		self:_ask(player, key)
	end

	--[[ Published once more at the end, for the gifted-only passes. `_ask` publishes the keys it
		asked about, but a pass that was gifted and never bought has nothing to ask — and its
		attribute has to be true all the same. ]]
	for _, pass in PassConfig.Passes do
		self:_publish(player, pass.Key)
	end

	local owned = self:ownedKeys(player)
	if #owned > 0 then
		self.log:info(string.format("%s has %s.", player.Name, table.concat(owned, ", ")))
	end
end

-- === Lifecycle ==============================================================

PassService:withLifecycle({
	init = function(self)
		--- [player][key] = true | false | nil. nil is "we have not asked Roblox yet", which is a
		--- different answer from false — see `known`.
		self._owned = {} :: { [Player]: { [string]: boolean } }
		--- [player][key] = true. The gift half, read off the profile on the join and written by
		--- `grant`. Never false: absent is the only way to not have been given something.
		self._gifted = {} :: { [Player]: { [string]: boolean } }
		self._trove = Trove.new()
	end,

	start = function(self)
		if not PassConfig.Enabled then
			self.log:info("Disabled by config, so every pass answers false and every seam behaves as if unbought.")
			return
		end

		local live = PassConfig.sellableKeys()
		if #live == 0 then
			--[[ Declared but never synced, or every seam still unwritten. Every `owns` answers false,
				which leaves all five seams doing exactly what they did before their pass existed —
				the same honest degradation `CashService` describes for a missing product id. ]]
			self.log:warn("No live pass ids. Run `rbxsync sync` to create them; every pass reads as unowned.")
		else
			self.log:info(string.format("Live passes: %s.", table.concat(live, ", ")))
		end

		for _, player in Players:GetPlayers() do
			task.spawn(function()
				self:_refresh(player)
			end)
		end

		self._trove:Add(Players.PlayerAdded:Connect(function(player: Player)
			task.spawn(function()
				self:_refresh(player)
			end)
		end))

		self._trove:Add(Players.PlayerRemoving:Connect(function(player: Player)
			self._owned[player] = nil
			self._gifted[player] = nil
		end))

		--[[ Somebody just bought a pass from the shop, or from the Roblox store page while standing
			in the game.

			`wasPurchased` IS DELIBERATELY NOT TRUSTED and the answer is re-read from Roblox instead
			— the same rule `RadioService._prompt` states and the same one every product follows
			("money only ever moves on a receipt"). It fires for a cancel too, and a cancel that
			granted a pass would be the worst bug this file could have. ]]
		self._trove:Add(MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, _wasPurchased: boolean)
			local key = PassConfig.keyOf(passId)
			if not (key and player and player.Parent == Players) then
				return
			end
			task.spawn(function()
				if self:_ask(player, key) then
					self.log:info(string.format("%s bought the %s pass.", player.Name, key))
					self:getSignal("PassGranted"):Fire(player, key, "bought")
				end
			end)
		end))
	end,
})

PassService:withCleanup(function()
	if PassService._trove then
		PassService._trove:Destroy()
	end
end)

return PassService
