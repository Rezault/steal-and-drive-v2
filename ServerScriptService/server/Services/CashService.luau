--[[
	CashService  (server)
	---------------------
	Opens the cash pack modal when a player presses a price they cannot meet, and pays the receipt
	into their balance when they buy one.

	=== THE WHOLE SERVICE IN THREE LINES =======================================================

	    a purchase site is short  ->  offerTopUp(player, gap)  ->  CashConfig.packFor(gap)  ->  modal
	    a receipt lands           ->  grantCash  ->  GarageService.addCash
	    nothing else

	`CashConfig`'s header is where the economics live: why there are six rungs, why the rung is
	picked off the SHORTFALL rather than off the price, and why this is the one product in the game
	that banks nothing. This file is the plumbing for that and holds no opinions of its own.

	=== IT IS CALLED FROM FOUR PLACES AND IT CHANGES NOTHING ABOUT THEM =========================

	`CarDealService` (a dealer bay), `UpgradeService` (a bay kiosk and the forecourt billboard) and
	`WorldService` (a world tile) each had one line that read "you cannot afford this, return". Every
	one of those lines is still there and still refuses. All this service adds is a call BEFORE the
	return, so the refusal has an offer attached to it.

	THAT ORDERING IS THE WHOLE SAFETY ARGUMENT AND IT MUST NOT BE REVERSED. Nothing here grants a
	car, a level or a world, nothing here retries the purchase the player was refused, and nothing
	here is authoritative about anything. A player who buys a pack gets cash and has to press the
	thing again, which is one extra press and is worth it: the alternative is a service that holds a
	pending purchase across a modal and completes it against a world, a price or a bay that may all
	have moved while the window was open. `CarDealService._onTriggered` re-checks every gate from
	scratch on the second press, and it is right to.

	=== ONE MODAL AT A TIME, AND NOT MANY OF THEM ==============================================

	`_awaiting` and `_cooldowns` are the two guards, and neither is optional.

	A DEALER BAY IS A HELD PROXIMITY PROMPT and a kiosk is a button somebody can lean on. Those
	sites throttle at 0.35 to 0.5 seconds because that is the right size for a profile write. Firing
	Roblox's purchase window at that rate is not a rough edge, it is the worst thing this feature
	could do to a player whose only problem is being poor. `CashConfig.PromptCooldown` is eight
	seconds and `_awaiting` shuts the door completely while a window is already up.

	`_awaiting` COMES DOWN ON `PromptProductPurchaseFinished`, which fires on a cancel and on a buy
	alike. `CashConfig.PromptTimeout` is the backstop for the client that crashed with the window
	open, because a flag that only ever goes up is a feature that stops working for that session.

	=== THE GRANT WAITS, AND IF IT CANNOT IT THROWS ============================================

	`GarageService.addCash` is a silent no op against a profile that service has not cached yet, and
	a receipt can land on the same frame as the join. So `grantCash` waits for `isProfileReady`
	rather than testing it, and running out of `CashConfig.GrantWait` ERRORS.

	The error is deliberate and it is the good outcome. `DevProductsHandler.PurchaseIdCheckAsync`
	wraps every grant in a `pcall` and answers `NotProcessedYet` when it fails, so Roblox holds the
	receipt and re-delivers it later. A warn and a silent return, which is what the other three
	products do with an unreachable profile, would mark this receipt granted and drop the money.
	Cash is the one grant where that distinction is free to get right, so it is got right here.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local CashConfig = require(ReplicatedStorage.shared.Configs.CashConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)

local CashService = Shard.new("CashService"):withDependencies({ "GarageService" })

CashService:withSignals({
	--[[ (player: Player, amount: number, packKey: string) - a cash pack receipt has been paid into
		the balance. Fired AFTER `addCash`, so a subscriber reading the profile sees the money.

		`AnalyticsService._watchEconomy` is the only listener today and it books the amount as a
		resource SOURCE, which is what keeps the dashboard's economy view balancing: every other way
		cash enters the game already fires one of these. ]]
	"CashGranted",
})

CashService:withRemoteEvents({
	--[[ server -> client (shortfall): a press this player could not afford, and by how much
		(`GarageConfig.Hud.Short`, 2026-10-08). Purely a display cue: the refusal itself already
		happened at the caller, and the number is the server's own arithmetic. ]]
	"CashShort",
})

-- === The offer ==============================================================

--[[ PUBLIC. Somebody pressed a price they are short of. Returns whether a modal was opened, which
	every caller today ignores: the refusal happens either way and this is the offer stapled to it.

	`shortfall` IS THE GAP AND NOT THE PRICE. Passing the price would offer a billion to a player
	who was a dollar short, and `CashConfig`'s header says at more length why that single argument is
	what makes an uninvited purchase window defensible. Every call site computes it the same way,
	`cost - getCash(player)`, off numbers it has already read.

	`reason` is for the log only. It never reaches the player and it never picks the pack. ]]
function CashService.offerTopUp(self, player: Player, shortfall: number, reason: string?): boolean
	if type(shortfall) == "number" and shortfall == shortfall and shortfall > 0 and player.Parent == Players then
		--- The cue (`CashShort`) goes out even with packs off: the press still deserves an answer.
		if not CashConfig.sellable() then
			self:getRemoteEvent("CashShort"):Fire(player, shortfall)
		end
	end
	if not CashConfig.sellable() then
		return false
	end
	if type(shortfall) ~= "number" or shortfall ~= shortfall or shortfall <= 0 then
		--- Not short after all. A caller that got here with a gap of zero has a bug, but it is not
		--- one worth opening a purchase window over.
		return false
	end
	if player.Parent ~= Players then
		return false
	end
	--- Told first, before any reason the top-up itself might not open (cooldown, a window already up,
	--- packs off): the player pressed something and should see why nothing happened.
	self:getRemoteEvent("CashShort"):Fire(player, shortfall)

	local now = os.clock()

	--- A window is already up in front of this player. See the header: the flag comes down on
	--- `PromptProductPurchaseFinished`, and `PromptTimeout` is the backstop for when it does not.
	local openedAt = self._awaiting[player]
	if openedAt and now - openedAt < CashConfig.PromptTimeout then
		return false
	end

	local last = self._cooldowns[player]
	if last and now - last < CashConfig.PromptCooldown then
		return false
	end

	--- What each rung pays THIS player (`CashConfig.cashFor`), so the offer still closes their gap.
	local pack = CashConfig.packFor(shortfall, player)
	if not pack then
		return false
	end

	self._cooldowns[player] = now
	self._awaiting[player] = now

	--[[ Report the prompt being SHOWN, which is the half of the conversion a receipt cannot tell
		you: a receipt says somebody bought, and only the pair says how many were asked. Fired before
		the prompt rather than after, so a prompt that throws below is still counted as offered,
		which is exactly the failure worth seeing in the funnel. `RandomCarService._prompt` makes the
		same call for the same reason. ]]
	local Analytics = Shard.get("AnalyticsService")
	if Analytics then
		--- `reason` says what they were short for, which is the question a top-up funnel asks.
		Analytics:PromptShown(player, pack.ProductId, reason)
	end

	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, pack.ProductId)
	end)
	if not ok then
		--- Nothing is on screen, so nothing should be waiting on it.
		self._awaiting[player] = nil
		self.log:warn(string.format("Could not offer %s a cash pack: %s", player.Name, tostring(err)))
		return false
	end

	self.log:info(string.format(
		"%s is %s short at %s, so %s (%d R$) was offered.",
		player.Name,
		GarageConfig.formatCash(shortfall),
		reason or "a purchase",
		pack.Key,
		pack.Price
	))
	return true
end

-- === The receipt ============================================================

--[[ PUBLIC (`DevProductsHandler`). A cash pack was bought. Pay it in.

	IT YIELDS AND IT MAY THROW, both on purpose, both argued in the header. The caller is
	`ProcessReceipt`, which is a yielding context by construction, and a throw there is turned into
	`NotProcessedYet` so Roblox re-delivers rather than the player losing the money. ]]
function CashService.grantCash(self, player: Player, pack: CashConfig.Pack)
	local GarageService = Shard.get("GarageService")
	if not GarageService then
		error("No GarageService, so a cash pack receipt cannot be paid in.")
	end

	--[[ WAIT, DO NOT TEST. `addCash` writes nothing against a profile `GarageService` has not cached
		yet and returns the old balance without complaining, so a receipt that beats the join path
		here would be money taken for nothing. Both this and `_watchProfile` resume off the same
		`GetProfileAsync`, in whatever order the scheduler picks, so the race is narrow and real. ]]
	local deadline = os.clock() + CashConfig.GrantWait
	while not GarageService:isProfileReady(player) do
		if player.Parent ~= Players then
			error(string.format("%s left before their cash pack could be paid in.", player.Name))
		end
		if os.clock() > deadline then
			error(string.format("%s's profile never arrived, so their cash pack was not paid in.", player.Name))
		end
		task.wait()
	end

	--[[ The amount is worked out HERE, at the receipt, for the player being paid (`CashConfig.cashFor`,
		2026-10-15): their income and world as the server itself published them, so nothing a client
		says can move it. A gift pays the RECIPIENT's figure, since this runs for the recipient. A
		receipt that lands before the income attributes are up (a rejoin replaying a pending one) pays
		the pack's floor, never less. ]]
	local amount = CashConfig.cashFor(pack, player)
	local balance = GarageService:addCash(player, amount)
	self:getSignal("CashGranted"):Fire(player, amount, pack.Key)
	self.log:info(string.format(
		"%s bought %s and was paid %s. Balance is now %s.",
		player.Name,
		pack.Key,
		GarageConfig.formatCash(amount),
		GarageConfig.formatCash(balance)
	))
end

-- === Lifecycle ==============================================================

CashService:withLifecycle({
	init = function(self)
		--- When this player's last offer was opened, so a held prompt cannot machine-gun modals.
		self._cooldowns = {} :: { [Player]: number }
		--- When a modal was opened and not yet closed. A timestamp rather than a boolean so
		--- `PromptTimeout` has something to measure against.
		self._awaiting = {} :: { [Player]: number }
		self._trove = Trove.new()
	end,

	start = function(self)
		if not CashConfig.Enabled then
			self.log:info("Disabled by config, so a purchase you cannot afford refuses silently.")
			return
		end

		if not CashConfig.sellable() then
			--[[ Declared but never synced. Every call to `offerTopUp` answers false, which leaves
				all four purchase sites doing exactly what they did before this service existed. That
				is the honest degradation, and it is the same call `RandomCarService` makes about a
				card with no product behind it. ]]
			self.log:warn("No cash pack product ids. Run `rbxsync sync` to create them; no top up will be offered.")
			return
		end

		--[[ The window closed. On a cancel this is all that happens, and on a purchase this fires
			BEFORE the receipt does, which is why `wasPurchased` is deliberately not read: money only
			ever moves in `grantCash`, off a receipt, and a service that paid out here would pay out
			for a purchase Roblox later failed to charge for.

			Both cases take the flag down and neither touches the cooldown. A player who cancels
			should not be offered another window for `PromptCooldown` seconds, and a player who
			bought does not need one. ]]
		self._trove:Add(MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, _wasPurchased)
			if not CashConfig.packOf(productId) then
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

CashService:withCleanup(function()
	if CashService._trove then
		CashService._trove:Destroy()
	end
end)

return CashService
