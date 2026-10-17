--[[
	GiftService  (server)
	---------------------
	Buying something for somebody else. `GiftConfig` is the catalogue and the limits; this is the
	three-step machine that gets Robux from one player into an entitlement on another.

	    press GIFT   ->  record who it is for on the BUYER's profile  ->  open Roblox's prompt
	    the receipt  ->  read that record back  ->  deliver to the recipient  ->  clear the record
	    delivery     ->  they are here: grant now.  they are not: post it to their save key.

	=== WHERE THE RECIPIENT IS KEPT, AND WHY IT IS THE HARD PART ================================

	A Roblox receipt names a product and a buyer. It cannot carry a recipient, a note, or any other
	payload — there is no field for one and no API to attach one. So the ONE fact a gift depends on
	is the one fact the payment system will not carry, and it has to be written down before the
	prompt opens and read back when the receipt lands.

	IT IS WRITTEN TO THE BUYER'S PROFILE AND NOT TO A TABLE IN THIS SERVER. A receipt arrives when
	Roblox feels like delivering it: on this server a second later, or on a different server, in a
	different session, days after the one that took the money died mid-purchase. That is the same
	fact `DevProductsHandler`'s header opens with, and every product in this game already banks a
	counter because of it. This banks an intent for exactly the same reason, and the failure it
	prevents is worse than the ones they prevent: an intent held in memory is not merely lost, it
	pays the gift out to the person who bought it for somebody else.

	IT IS KEYED BY GIFT AND AGES OUT. Both are guards against the same shape of bug — a receipt for
	purchase A landing after the player has started purchase B. Keyed by gift, A's receipt cannot
	find B's recipient. Aged out at `GiftConfig.IntentLifetime`, an intent left behind by a purchase
	nobody ever completed cannot be spent by an unrelated receipt for the same product a month later.

	=== DELIVERY IS THE POST, NOT A HANDSHAKE ==================================================

	`AdminService.cashOffline` already established the pattern and this uses the same one: a
	ProfileStore message against the recipient's save key, applied by a handler registered at REQUIRE
	TIME (a session replays its queue the instant it opens, so a handler registered in `init` is one
	that can miss the first delivery). It lands on whichever server has them next — this one, if they
	are standing here and it simply had not been noticed.

	SO A RECIPIENT NEED NOT BE ONLINE, IN THIS SERVER, OR EVEN HAVE PLAYED TODAY. The direct grant
	for somebody standing here is an OPTIMISATION on top of the post, not a separate path: it exists
	so the toast can fire while they are looking, and it falls back to the post the moment anything
	about the direct grant does not hold.

	=== WHAT HAPPENS WHEN IT GOES WRONG ========================================================

	A RECEIPT WITH NO INTENT PAYS THE BUYER. It is the one outcome here that is nobody's design, and
	the alternatives are worse: refusing the receipt makes Roblox retry it forever, and granting it
	to nobody is Robux taken for nothing. So the buyer gets the thing they paid for, at the price
	they paid, and the log says loudly that a gift became a purchase. Reachable only by an intent
	that aged out or a profile that lost a write.

	A GRANT THAT CANNOT LAND THROWS, and that is deliberate in the same way `CashService.grantCash`
	is: `PurchaseIdCheckAsync` wraps every grant in a pcall and answers `NotProcessedYet`, so Roblox
	holds the receipt and re-delivers it. A warn-and-return would mark the receipt granted and drop
	somebody's gift.

	=== WHAT IT IS NOT ========================================================================

	It is not a trade. Nothing leaves the buyer's account, nothing is negotiated, nothing can be
	scammed out of anybody: the only thing that moves is Robux, from the buyer to Roblox, exactly as
	if they had bought it for themselves. A player who receives a gift cannot lose anything by
	receiving it and cannot be tricked into sending one, because sending one is a Robux prompt with
	the recipient's name on it.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data = require(script.Parent.Parent.Data)
local PlayerProfile = require(script.Parent.Parent.Data.Components.PlayerProfile)
local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local GiftConfig = require(ReplicatedStorage.shared.Configs.GiftConfig)

local GiftService = Shard.new("GiftService")

GiftService:withRemoteEvents({
	{
		--[[ client -> server: open the prompt for this gift, for this player. The client names a
			gift key and a user id and nothing else — see `GiftConfig.RequestName`. ]]
		[GiftConfig.RequestName] = function(player: Player, giftKey: unknown, userId: unknown)
			GiftService:_onRequest(player, giftKey, userId)
		end,
	},
	GiftConfig.ReplyName,
	GiftConfig.ReceivedName,
})

GiftService:withSignals({
	--[[ (recipient: Player, giftKey: string, fromName: string) — a gift has landed on somebody who
		is in this server. Fired after the grant, so a listener reading the profile sees it.

		`AnalyticsService` is the intended listener: a gift is the only purchase in this game where
		the account that pays and the account that benefits are different, and a funnel that books it
		against the recipient would read as free cash appearing from nowhere. ]]
	"GiftDelivered",
})

-- === The intent =============================================================

--[[ Everything this player has started buying and not yet had a receipt for. Always a table.

	READ DEFENSIVELY because it is a saved key: a profile written by a newer build, or hand-edited,
	can hold anything at all here, and a malformed entry must read as "no intent" rather than take
	the service down on a receipt path. ]]
function GiftService._pending(self, profile): { [string]: { To: number, Name: string, At: number } }
	local pending = profile:Get(GiftConfig.PendingKey)
	return if type(pending) == "table" then pending else {}
end

--[[ Write the recipient down before the prompt opens. See the header.

	A FRESH TABLE RATHER THAN A MUTATION, for the reason `PassService.grant` gives: `Set` goes
	through the Replica and what is written has to be the whole value.

	IT DROPS ANYTHING OLDER THAN `IntentLifetime` ON THE WAY PAST, which is the whole of the ageing
	policy — no timer, no sweep, no join-time pass. The table is only ever read and written on a
	purchase path, so the purchase path is the only place ageing can matter. ]]
function GiftService._remember(self, profile, giftKey: string, userId: number, name: string, at: number?)
	local pending = self:_pending(profile)
	local now = os.time()
	local next_ = {}
	for key, entry in pending do
		if type(entry) == "table" and type(entry.At) == "number" and now - entry.At < GiftConfig.IntentLifetime then
			next_[key] = entry
		end
	end
	--[[ `at` EXISTS FOR ONE CALLER: `grantGift` putting an intent back after a failed post. It has to
		go back carrying its ORIGINAL timestamp, or a gift that fails to post repeatedly would keep
		renewing its own lifetime and never age out. Every other caller omits it and means "now". ]]
	next_[giftKey] = { To = userId, Name = name, At = at or now }
	profile:Set(GiftConfig.PendingKey, next_)
end

--[[ Read the recipient back and take the entry out, in one step. Returns nil for a receipt with no
	intent behind it, which the caller pays to the buyer — see the header.

	THE CLEAR AND THE READ ARE ONE OPERATION on purpose. Two calls means a window where a re-delivered
	receipt reads an intent the first delivery has already spent, and Roblox re-delivers receipts it
	is not sure about. The dedup in `PurchaseIdCheckAsync` is the real guard against a double grant;
	this is the second one, and it costs a line. ]]
function GiftService._takeIntent(self, profile, giftKey: string): { To: number, Name: string, At: number }?
	local pending = self:_pending(profile)
	local entry = pending[giftKey]
	if type(entry) ~= "table" or type(entry.To) ~= "number" then
		return nil
	end
	if os.time() - (if type(entry.At) == "number" then entry.At else 0) >= GiftConfig.IntentLifetime then
		return nil
	end

	local next_ = table.clone(pending)
	next_[giftKey] = nil
	profile:Set(GiftConfig.PendingKey, next_)
	return entry
end

-- === The request ============================================================

--- The status line under the gift picker. `ok` picks the colour at the other end.
function GiftService._say(self, player: Player, ok: boolean, message: string)
	if player.Parent ~= Players then
		return
	end
	self:getRemoteEvent(GiftConfig.ReplyName):Fire(player, ok, message)
end

--[[ Somebody pressed GIFT. Validate, record, prompt.

	EVERY GATE REFUSES WITH A SENTENCE, because this is a screen the player opened deliberately and
	a button that does nothing is indistinguishable from a broken one. The exception is a request
	whose gift key does not resolve, which no honest client can send.

	NOTHING IS GRANTED HERE AND NOTHING IS CHARGED HERE. This opens Roblox's window; the money and
	the grant both happen on the receipt, which is the same rule `CashService` states at length and
	the reason that service can be called from four places without any of them trusting it. ]]
function GiftService._onRequest(self, player: Player, giftKey: unknown, userId: unknown)
	if not GiftConfig.Enabled then
		return
	end

	local gift = GiftConfig.get(giftKey)
	if not gift then
		self.log:warn(string.format("%s asked to gift '%s', which is not a gift.", player.Name, tostring(giftKey)))
		return
	end
	if not GiftConfig.isSellable(gift) then
		self:_say(player, false, "That gift is not available right now.")
		return
	end

	if type(userId) ~= "number" or userId ~= userId or userId <= 0 or userId % 1 ~= 0 then
		self:_say(player, false, "Pick somebody to send it to first.")
		return
	end
	if userId == player.UserId then
		--- `GiftConfig` note 3: it would work, and every one of them is a mis-tap.
		self:_say(player, false, "That is you. Buy it from the shop instead and it costs the same.")
		return
	end

	--[[ THE RECIPIENT HAS TO BE IN THIS SERVER TO BE PICKED, WHICH IS NOT THE SAME AS HAVING TO BE
		HERE TO RECEIVE ONE. Delivery works against any user id (`GiftConfig` note 2); this check is
		about the PICKER, which today offers exactly the people the buyer can see
		(`GiftConfig.PickFrom`). It is here rather than only on the client because a client can send
		any number it likes, and a gift posted to a user id somebody typed is a gift to a stranger. ]]
	local recipient = Players:GetPlayerByUserId(userId)
	if not recipient then
		self:_say(player, false, "They have left the server. Pick somebody else.")
		return
	end

	local now = os.clock()
	local openedAt = self._awaiting[player]
	if openedAt and now - openedAt < GiftConfig.PromptTimeout then
		self:_say(player, false, "Finish the purchase that is already open first.")
		return
	end
	local last = self._cooldowns[player]
	if last and now - last < GiftConfig.PromptCooldown then
		return -- silent: this is a double press, not a decision
	end

	local profile = Data:GetProfileAsync(player)
	if not profile then
		self:_say(player, false, "Your save is still loading. Try again in a moment.")
		return
	end
	if player.Parent ~= Players then
		return
	end

	--[[ RECORDED BEFORE THE PROMPT OPENS, NEVER AFTER. A player can complete a purchase faster than
		a second write lands, and an intent written after the prompt is an intent that can lose a
		race with its own receipt. ]]
	self:_remember(profile, gift.Key, userId, recipient.Name)

	self._cooldowns[player] = now
	self._awaiting[player] = now

	--- The half of the funnel a receipt cannot tell you — see `CashService.offerTopUp`.
	local Analytics = Shard.get("AnalyticsService")
	if Analytics then
		Analytics:PromptShown(player, gift.ProductId)
	end

	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, gift.ProductId)
	end)
	if not ok then
		self._awaiting[player] = nil
		self.log:warn(string.format("Could not open %s's gift prompt: %s", player.Name, tostring(err)))
		self:_say(player, false, "The Robux prompt could not open. Try again in a moment.")
		return
	end

	self.log:info(string.format("%s is buying %s for %s (%d).", player.Name, gift.Key, recipient.Name, userId))
end

-- === Delivery ===============================================================

--[[ Put a gift into a player who is standing in this server. Returns whether it landed.

	FALSE IS AN ORDINARY ANSWER AND THE CALLER POSTS INSTEAD. It means the profile is not ready, the
	service that grants this kind is not up, or they left between the receipt and this line — none of
	which is worth failing a receipt over when the post handles every one of them.

	IT YIELDS. Reached only from `grantGift`, which is a receipt path and yields by construction. ]]
function GiftService._deliverHere(self, recipient: Player, gift: GiftConfig.Gift, fromName: string): boolean
	if gift.Kind == "cash" then
		--[[ THROUGH `CashService`, NOT STRAIGHT INTO THE BALANCE, and the reason is the signal rather
			than the arithmetic. `grantCash` fires `CashGranted`, which is what `AnalyticsService`
			books cash entering the game from; `CashService`'s header notes that every other way cash
			enters already fires one, and a gift that wrote `addCash` itself would be the first that
			did not. The dashboard's economy view would then under-count sources by exactly the
			amount players gift each other, which is the hardest kind of gap to notice.

			WRAPPED, BECAUSE `grantCash` THROWS BY DESIGN. It waits for the profile and raises when
			the wait runs out — right for a receipt path, where a raise becomes `NotProcessedYet` and
			Roblox re-delivers. Here it is one of two delivery routes and a failure means "post it
			instead", so the throw is caught and turned back into the false this function promises. ]]
		local CashService = Shard.get("CashService")
		local pack = GiftConfig.packOf(gift)
		if not (CashService and pack) then
			return false
		end
		local paid = pcall(function()
			CashService:grantCash(recipient, pack)
		end)
		if not paid then
			return false
		end
	else
		local PassService = Shard.get("PassService")
		if not PassService then
			return false
		end
		if not PassService:grant(recipient, gift.Target) then
			return false
		end
	end

	self:getRemoteEvent(GiftConfig.ReceivedName):Fire(recipient, fromName, gift.Title)
	self:getSignal("GiftDelivered"):Fire(recipient, gift.Key, fromName)
	self.log:info(string.format("%s received %s from %s, in this server.", recipient.Name, gift.Key, fromName))
	return true
end

--[[ Post a gift to somebody who is not here. Returns whether the datastore took it.

	THE MESSAGE CARRIES THE GIFT KEY AND THE SENDER'S NAME, and nothing else — not the amount, not
	the pass id, not the price. Everything else is looked up from the key on the server that
	delivers it, so a message queued today and delivered after a retune pays what the game pays now
	rather than what it paid when it was sent. That is the same reasoning `GarageService`'s income is
	derived rather than accumulated. ]]
function GiftService._post(self, userId: number, gift: GiftConfig.Gift, fromName: string): boolean
	local store = Data:GetProfileStore()
	local key = Data:GetKeyFromUserId(userId)
	if not (store and key) then
		return false
	end
	return store:MessageAsync(key, { "Gift", gift.Key, fromName }) == true
end

--[[ PUBLIC (`DevProductsHandler`). A gift product was bought. Work out who it was for and give it
	to them.

	IT YIELDS AND IT MAY THROW, both on purpose and both for the reason `CashService.grantCash` gives:
	the caller turns a throw into `NotProcessedYet`, so Roblox re-delivers rather than the gift being
	lost. The one thing that must NOT throw is a gift that has already been delivered — that is what
	`PurchaseIdCheckAsync`'s dedup and `_takeIntent`'s read-and-clear are both for. ]]
function GiftService.grantGift(self, buyer: Player, gift: GiftConfig.Gift)
	local profile = Data:GetProfileAsync(buyer)
	if not profile then
		error(string.format("%s's profile never arrived, so their gift could not be sent.", buyer.Name))
	end

	local intent = self:_takeIntent(profile, gift.Key)
	if not intent then
		--[[ NOBODY TO SEND IT TO, SO THE BUYER GETS IT. The header explains why this beats both
			alternatives. Loud, because it should be unreachable in normal play and it is the one
			outcome in this file that nobody designed. ]]
		self.log:warn(string.format(
			"%s bought %s with no recipient recorded, so it was paid to them instead.",
			buyer.Name,
			gift.Key
		))
		if not self:_deliverHere(buyer, gift, buyer.Name) then
			error(string.format("%s bought %s with no recipient, and could not be paid it either.", buyer.Name, gift.Key))
		end
		return
	end

	local recipient = Players:GetPlayerByUserId(intent.To)
	if recipient and self:_deliverHere(recipient, gift, buyer.Name) then
		self:_say(buyer, true, string.format("Sent %s to %s.", gift.Title, recipient.Name))
		return
	end

	if self:_post(intent.To, gift, buyer.Name) then
		self.log:info(string.format("%s sent %s to user %d by post.", buyer.Name, gift.Key, intent.To))
		self:_say(buyer, true, string.format("Sent %s to %s. It lands the next time they play.", gift.Title, intent.Name))
		return
	end

	--[[ THE INTENT HAS ALREADY BEEN TAKEN OFF THE PROFILE BY HERE, so it has to go back before this
		throws — otherwise Roblox's retry finds no intent and pays the buyer for a gift that was
		never delivered. Put back with its ORIGINAL timestamp so the retry is measured against when
		the player actually pressed the button. ]]
	self:_remember(profile, gift.Key, intent.To, intent.Name, intent.At)
	error(string.format("Could not post %s to user %d — the datastore refused it.", gift.Key, intent.To))
end

-- === Delivery by post =======================================================

--[[ A gift posted from another server, arriving on this one.

	EVERYTHING ABOUT THIS MIRRORS `GarageService`'s posted-cash handler and the reasoning there
	applies word for word: registered at REQUIRE TIME because a session replays its queue as it
	opens; it WAITS for the player to be wired up rather than testing, because a message is replayed
	before the services that apply it have finished with the join; a malformed message is DISCARDED
	rather than replayed, because a retry does not fix a typo and a message that never processes is
	replayed on every join this player ever makes.

	THE ONE DIFFERENCE IS THAT IT DOES NOT TOAST. A gift that arrives by post arrives on a join, and
	`GiftConfig.ReceivedName` explains why a popup competing with the WELCOME BACK screen is the
	wrong way to tell somebody about it. ]]
local POST_TIMEOUT = 60 -- seconds to wait for a joining player's profile before leaving it queued

PlayerProfile.OnMessage("Gift", function(profile, message: { any }): boolean
	local giftKey = message[2]
	local fromName = if type(message[3]) == "string" then message[3] else "another player"

	local gift = GiftConfig.get(giftKey)
	if not gift then
		GiftService.log:warn(string.format("Dropped a posted gift of '%s', which is not a gift.", tostring(giftKey)))
		return true
	end

	local player = profile:GetPlayer()
	if not player then
		return false
	end

	local deadline = os.clock() + POST_TIMEOUT
	while true do
		if player.Parent ~= Players or os.clock() > deadline then
			return false -- still queued; it lands on a join that gets far enough
		end
		local ready = if gift.Kind == "cash"
			then (function()
				local GarageService = Shard.get("GarageService")
				return GarageService ~= nil and GarageService:isProfileReady(player)
			end)()
			else Shard.get("PassService") ~= nil
		if ready then
			break
		end
		task.wait()
	end

	if not GiftService:_deliverHere(player, gift, fromName) then
		return false -- leave it queued rather than eating it
	end
	GiftService.log:info(string.format("%s received %s from %s, in the post.", player.Name, gift.Key, fromName))
	return true
end)

-- === Lifecycle ==============================================================

GiftService:withLifecycle({
	init = function(self)
		--- When this player's last gift prompt was opened, so a held button cannot stack windows.
		self._cooldowns = {} :: { [Player]: number }
		--- When a window was opened and not yet closed. A timestamp so `PromptTimeout` has something
		--- to measure against; see `CashService._awaiting`.
		self._awaiting = {} :: { [Player]: number }
		self._trove = Trove.new()
	end,

	start = function(self)
		if not GiftConfig.Enabled then
			self.log:info("Disabled by config, so nothing can be gifted.")
			return
		end

		local sellable = GiftConfig.sellableGifts()
		if #sellable == 0 then
			--[[ Declared but never synced, or every target still unwired. The shop draws no GIFT
				toggle and every request is refused — the same honest degradation `CashService`
				describes for a missing product id. ]]
			self.log:warn("No gift product ids. Run `rbxsync sync` to create them; gifting stays off.")
		else
			self.log:info(string.format("%d gift(s) available.", #sellable))
		end

		--[[ The window closed, on a buy or on a cancel alike. `wasPurchased` is deliberately not
			read: money only ever moves on a receipt, and a service that acted here would act on a
			purchase Roblox later failed to charge for. Same rule as `CashService`. ]]
		self._trove:Add(MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, _wasPurchased: boolean)
			if not GiftConfig.ofProduct(productId) then
				return
			end
			local player = Players:GetPlayerByUserId(userId)
			if player then
				self._awaiting[player] = nil
			end
		end))

		self._trove:Add(Players.PlayerRemoving:Connect(function(player: Player)
			self._cooldowns[player] = nil
			self._awaiting[player] = nil
		end))
	end,
})

GiftService:withCleanup(function()
	if GiftService._trove then
		GiftService._trove:Destroy()
	end
end)

return GiftService
