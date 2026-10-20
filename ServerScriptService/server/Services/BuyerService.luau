--[[
	BuyerService  (server)
	----------------------
	The offers NPC buyers make on the cars a player puts out for sale. It decides when a buyer turns
	up, which car they want, what they offer, and what happens when the owner answers. `BuyerConfig`
	has the design and every number; `CustomerService` stands the rig beside the car; `BuyerController`
	draws the sign over them and the offer screen. Added 2026-09-28 with the dealership rework.

	=== THE ONE IDEA: THE OFFER IS THE SAVE, THE BUYER IS A DRAWING OF IT ======================

	An offer is a row in the profile (`Garage.Offers`, car ID -> `{ Amount, ExpiresAt, Name }`), and
	every pass of `_tick` makes the world agree with it: rows past their deadline, or whose car is no
	longer on a bay and for sale, are dropped; rows with no rig beside their car get one. So a buyer
	who arrived while the owner was out on a run is still standing there when they come home, a rejoin
	rebuilds them on whichever lot the player lands on, and nothing about a buyer needs remembering
	between passes except the row.

	=== WHAT IT TRUSTS ========================================================================

	Nothing the client sends except WHICH car it is answering and WHETHER it said yes. The amount is
	the saved row's — a client cannot name a price — and ACCEPT re-checks, at the moment of the press,
	that the offer still stands, has not expired, and that its car is still on a bay, still for sale
	and still owned. The sale itself goes through `GarageService.sellCars` with the row's amount as an
	agreed price, so a car sold to a buyer leaves the save by the one path every sale uses. The row is
	removed BEFORE the sale is attempted, so a double press is one sale and never two.

	What is knowingly NOT closed: nothing here verifies the buyer was ever near the car or the player
	near the buyer beyond the ProximityPrompt that opened the screen. The screen could be answered from
	anywhere once open — which costs nothing, since the only thing it can do is the thing the owner was
	already offered.

	=== NEVER SOLD WITHOUT THE PRESS ==========================================================

	There is no path in this file that sells a car except `_answer` with `accept == true`, and that
	path is only reached from the owner's `OfferAnswer` remote. Expiry, For Sale switched off, the car
	moved, the car sold at the lot: every one of those DROPS the offer and sells nothing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local BuyerConfig = require(ReplicatedStorage.shared.Configs.BuyerConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
--- A car's rarity band, which decides which buyer kinds may come for it (`BuyerConfig.Kinds`).
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)

local BuyerService = Shard.new("BuyerService"):withDependencies({ "GarageService", "CustomerService" })

type Offer = {
	Amount: number,
	ExpiresAt: number, -- os.time(); an offer at or past this is gone, whatever the rig shows
	Name: string?, -- the buyer's display name once a rig has stood for it; absent until then
	Kind: string?, -- `BuyerConfig.Kinds` key; absent = a Regular (and every offer saved before kinds)
}

BuyerService:withRemoteEvents({
	--[[ server -> client (offer): open the offer screen on this car. `{ carId, body, paint, amount,
		value, expiresAt, name }` — the VALUE is the server's (`GarageService.marketValueOf`), so the
		percentage and the rating the screen draws are measured against the same number the sell lot
		would pay. ]]
	"OfferOpen",
	--[[ server -> client (carId, result, amount): the answer landed. `result` is "sold", "declined" or
		"gone" (expired, cancelled, or the car no longer qualifies). The screen closes on any of them. ]]
	"OfferResolved",
	{
		--[[ client -> server (carId, accept): the owner answered. See the trust note in the header:
			the car and the yes/no are all the client is believed about. ]]
		OfferAnswer = function(player: Player, carId: unknown, accept: unknown)
			BuyerService:_answer(player, carId, accept == true)
		end,
	},
})

-- === The rows ===============================================================

--- Is this car one a buyer may want right now? On a bay and for sale (`BuyerConfig` note 4).
function BuyerService._eligible(self, player: Player, carId: string): boolean
	local Garage = Shard.get("GarageService")
	if not Garage then
		return false
	end
	local where = Garage:locationOf(player, carId)
	return where == "Bay" and Garage:isForSale(player, carId)
end

--- The rows, as a table this file may edit and write back. Only well-formed rows survive the read,
--- so a hand-edited or half-written save cannot put a buyer on the lot for a nonsense amount.
function BuyerService._offers(self, player: Player): { [string]: Offer }
	local Garage = Shard.get("GarageService")
	local out = {}
	for carId, offer in (if Garage then Garage:getOffers(player) else {}) do
		if type(carId) == "string" and type(offer) == "table" and type(offer.Amount) == "number" and type(offer.ExpiresAt) == "number" then
			out[carId] = offer
		end
	end
	return out
end

function BuyerService._write(self, player: Player, offers: { [string]: Offer })
	local Garage = Shard.get("GarageService")
	if Garage then
		Garage:setOffers(player, offers)
	end
end

--- Public: how many buyers are waiting on this player's cars. Read by the run summary and the
--- Welcome Back screen. Counts rows that have not expired; the rigs are not consulted.
function BuyerService.waitingCount(self, player: Player): number
	local now = os.time()
	local count = 0
	for _, offer in self:_offers(player) do
		if offer.ExpiresAt > now then
			count += 1
		end
	end
	return count
end

--[[ Make one new offer on `carId`. The amount is a band roll over the car's market value
	(`BuyerConfig.rollRatio`), rounded to whole dollars; a car worth nothing gets no buyer, because an
	offer of $0 is not an offer. `expiresAt` defaults to a full lifetime from now — the offline
	catch-up passes a shorter one for a buyer who arrived while the player was away. `ratio` is the
	admin panel's (`forceOffer`); everybody else rolls. ]]
function BuyerService._make(self, player: Player, carId: string, expiresAt: number?, ratio: number?): Offer?
	local Garage = Shard.get("GarageService")
	local value = if Garage then Garage:marketValueOf(player, carId) else 0
	if value <= 0 then
		return nil
	end
	--- A forced ratio (the admin panel, the tutorial's buyer) is a Regular: its price is already chosen.
	local kind = if ratio then nil else BuyerConfig.pickKind(self._rng, self:_bandOf(carId))
	return {
		Amount = math.max(1, math.round(value * (ratio or BuyerConfig.rollRatio(self._rng, kind and kind.Bands)))),
		ExpiresAt = expiresAt or (os.time() + BuyerConfig.lifetimeFor(kind)),
		Kind = kind and kind.Key,
	}
end

--[[ The rarity band buyer kinds read for this car (`BuyerConfig.Kinds`): the body's own band, one
	higher for a weather car, capped at 5. 1 for anything unreadable, which only ever narrows the
	kinds to the common three. Pure. ]]
function BuyerService._bandOf(self, carId: string): number
	local body, _paint, mutation = GarageConfig.parseCarKey(carId)
	if not body then
		return 1
	end
	local _, band = CarRarity.of(body)
	band = if type(band) == "number" then band else 1
	return math.min(5, band + (if mutation then 1 else 0))
end

--- Every car that could take a buyer and does not have one yet, in no particular order.
function BuyerService._candidates(self, player: Player, offers: { [string]: Offer }): { string }
	local Garage = Shard.get("GarageService")
	local out = {}
	for _, bay in (if Garage then Garage:getBays(player) else {}) do
		local car, carId = Garage:getBayTip(player, bay.index)
		if car and carId and not offers[carId] and self:_eligible(player, carId) then
			table.insert(out, carId)
		end
	end
	return out
end

-- === The pass ===============================================================

--[[ One pass over one player: drop what no longer stands, maybe add a buyer, and make the rigs match
	the rows. Header "the one idea". Writes the profile only when a row actually changed. ]]
function BuyerService._tick(self, player: Player, allowArrival: boolean)
	local Garage = Shard.get("GarageService")
	local Customers = Shard.get("CustomerService")
	if not (Garage and Garage:isProfileReady(player)) then
		return
	end

	local offers = self:_offers(player)
	local now = os.time()
	local changed = false
	--- Offers made on THIS pass, whose buyers walk in (`BuyerConfig.Stand.WalkIn`). Everybody else is
	--- rebuilt from the save and stood in place.
	local fresh: { [string]: boolean } = {}

	for carId, offer in offers do
		if offer.ExpiresAt <= now or not self:_eligible(player, carId) then
			offers[carId] = nil
			changed = true
			if Customers then
				Customers:removeBuyer(player, carId)
			end
			self:getSignal("OfferDropped"):Fire(player, carId, offer, if offer.ExpiresAt <= now then "Expired" else "Withdrawn")
		end
	end

	--[[ AN ARRIVAL IS A CHANCE PER PASS, `CheckSeconds / MeanArrivalSeconds`, which is what makes the
		gaps between buyers memoryless (`BuyerConfig.MeanArrivalSeconds`). Only while the lot has room
		and a car worth wanting. ]]
	if allowArrival then
		local waiting = 0
		for _ in offers do
			waiting += 1
		end
		if waiting < BuyerConfig.MaxWaiting and self._rng:NextNumber() < BuyerConfig.CheckSeconds / BuyerConfig.MeanArrivalSeconds then
			local candidates = self:_candidates(player, offers)
			if #candidates > 0 then
				local carId = candidates[self._rng:NextInteger(1, #candidates)]
				local offer = self:_make(player, carId)
				if offer then
					offers[carId] = offer
					fresh[carId] = true
					changed = true
					self.log:info(string.format("A buyer offered %s %s for %s.", player.Name, GarageConfig.formatCash(offer.Amount), carId))
					self:getSignal("OfferMade"):Fire(player, carId, offer, "Live")
				end
			end
		end
	end

	--[[ THE RIGS. Every row gets a buyer standing by its car; `placeBuyer` is idempotent and answers
		nil while it cannot build one yet (no lot claimed, faces still loading), which the next pass
		simply retries. The buyer's name is copied into the row the first time one stands for it, so
		the offer screen can say who it is from. ]]
	if Customers then
		for carId, offer in offers do
			local _, bay = Garage:locationOf(player, carId)
			if bay then
				local name = Customers:placeBuyer(player, bay, carId, offer, fresh[carId])
				if name and name ~= "" and offer.Name ~= name then
					offer.Name = name
					changed = true
				end
			end
		end
	end

	if changed then
		self:_write(player, offers)
	end
end

--[[ Public (OfflineService): the buyers who would have turned up while this player was logged out,
	made now. Returns how many are waiting afterwards, for the Welcome Back screen.

	REAL-TIME CLOCK, SO ONLY THE LAST LIFETIME COUNTS (`BuyerConfig` note 2). A buyer who arrived three
	hours ago left two hours and fifty-five minutes ago, so absence past one lifetime adds nobody. Each
	one made here is given the deadline it would really have: arrived somewhere in that window, gone a
	lifetime after that. The count is the expected number of arrivals, rounded by a coin toss, and
	capped by `MaxWaiting` and by the cars there are to want. ]]
function BuyerService.catchUp(self, player: Player, away: number): number
	if not BuyerConfig.Enabled or away <= 0 then
		return self:waitingCount(player)
	end
	local offers = self:_offers(player)
	local window = math.min(away, BuyerConfig.Lifetime)
	local expected = window / BuyerConfig.MeanArrivalSeconds
	local arrivals = math.floor(expected + self._rng:NextNumber())
	local now = os.time()

	local waiting = 0
	for _ in offers do
		waiting += 1
	end
	local made = 0
	for _ = 1, arrivals do
		if waiting >= BuyerConfig.MaxWaiting then
			break
		end
		local candidates = self:_candidates(player, offers)
		if #candidates == 0 then
			break
		end
		local carId = candidates[self._rng:NextInteger(1, #candidates)]
		local arrivedAgo = self._rng:NextNumber() * window
		local offer = self:_make(player, carId, now + math.max(1, math.floor(BuyerConfig.Lifetime - arrivedAgo)))
		if offer then
			offers[carId] = offer
			waiting += 1
			made += 1
			self:getSignal("OfferMade"):Fire(player, carId, offer, "Offline")
		end
	end
	if made > 0 then
		self:_write(player, offers)
		self.log:info(string.format("%d buyer(s) turned up for %s while they were away.", made, player.Name))
	end
	--- Stand them now rather than on the next pass, so the lot the player spawns onto already has them.
	self:_tick(player, false)
	return self:waitingCount(player)
end

--[[ A walked-in buyer has reached the car: the offer's five minutes start NOW (`BuyerConfig.Stand.
	ClockOnArrival`). The row was written at the spawn with a full lifetime from then, so it could never
	lapse mid-walk; this pushes the deadline on by however long the walk took, and moves the rig's
	attribute with it so the sign counts from the same number the save holds.

	A rejoin mid-walk rebuilds the buyer in place on the spawn-time deadline, a few seconds short.
	Accepted: it is one walk's worth of clock, on a rare path, and never in the owner's disfavour
	by more than that. ]]
function BuyerService._startClock(self, player: Player, carId: string)
	if not BuyerConfig.Stand.ClockOnArrival then
		return
	end
	local offers = self:_offers(player)
	local offer = offers[carId]
	if not offer then
		return
	end
	--- The kind's own length: an IN A HURRY buyer's half-length clock starts at the car too.
	offer.ExpiresAt = os.time() + BuyerConfig.lifetimeFor(BuyerConfig.kindOf(offer.Kind))
	self:_write(player, offers)
	local Customers = Shard.get("CustomerService")
	if Customers then
		Customers:setBuyerDeadline(player, carId, offer.ExpiresAt)
	end
end

-- === Answering ==============================================================

--- The owner pressed a buyer: send them the offer screen, if the offer still stands.
function BuyerService._open(self, player: Player, carId: string)
	local offer = self:_offers(player)[carId]
	if not (offer and offer.ExpiresAt > os.time() and self:_eligible(player, carId)) then
		self:getRemoteEvent("OfferResolved"):Fire(player, carId, "gone", 0)
		self:_tick(player, false)
		return
	end
	local Garage = Shard.get("GarageService")
	local body, paint = GarageConfig.parseCarKey(carId)
	self:getRemoteEvent("OfferOpen"):Fire(player, {
		carId = carId,
		body = body,
		paint = paint,
		amount = offer.Amount,
		value = if Garage then Garage:marketValueOf(player, carId) else 0,
		expiresAt = offer.ExpiresAt,
		name = offer.Name,
		kind = offer.Kind,
	})
	self:getSignal("OfferViewed"):Fire(player, carId)
end

--[[ The owner's answer. Header "what it trusts" and "never sold without the press" are the rules;
	this is them in order: rate limit, read the row, REMOVE the row, then act on it. Removing first is
	what makes a double press one sale — the second finds no row and is told the offer is gone. ]]
function BuyerService._answer(self, player: Player, carId: unknown, accept: boolean)
	if not BuyerConfig.Enabled or type(carId) ~= "string" then
		return
	end
	local now = os.clock()
	if now < (self._cooldowns[player] or 0) then
		return
	end
	self._cooldowns[player] = now + BuyerConfig.Screen.Cooldown

	local offers = self:_offers(player)
	local offer = offers[carId]
	local Customers = Shard.get("CustomerService")
	if not offer then
		self:getRemoteEvent("OfferResolved"):Fire(player, carId, "gone", 0)
		return
	end

	offers[carId] = nil
	self:_write(player, offers)
	if Customers then
		--- A turned-down buyer walks off in a huff (`BuyerConfig.Declined`); a paying one just goes.
		if accept then
			Customers:removeBuyer(player, carId)
		else
			Customers:sendBuyerAway(player, carId)
		end
	end

	if not accept then
		self:getRemoteEvent("OfferResolved"):Fire(player, carId, "declined", 0)
		self:getSignal("OfferAnswered"):Fire(player, carId, false, offer)
		self.log:info(string.format("%s turned down %s for %s.", player.Name, GarageConfig.formatCash(offer.Amount), carId))
		return
	end

	if offer.ExpiresAt <= os.time() or not self:_eligible(player, carId) then
		self:getRemoteEvent("OfferResolved"):Fire(player, carId, "gone", 0)
		--- The row is already removed above, so `_tick` will never see it to drop it.
		self:getSignal("OfferDropped"):Fire(player, carId, offer, if offer.ExpiresAt <= os.time() then "Expired" else "Withdrawn")
		return
	end

	local Garage = Shard.get("GarageService")
	local sold = if Garage then Garage:sellCars(player, { carId }, { [carId] = offer.Amount }) else 0
	if sold <= 0 then
		--- The row is already gone and nothing was sold, which is the safe way round: the car stays
		--- with the player. Logged, because a refused sale here means the eligibility check and
		--- `sellCars` disagree about something.
		self.log:warn(string.format("%s accepted %s for %s but the sale was refused; the car stays theirs.", player.Name, GarageConfig.formatCash(offer.Amount), carId))
		self:getRemoteEvent("OfferResolved"):Fire(player, carId, "gone", 0)
		self:getSignal("OfferDropped"):Fire(player, carId, offer, "Withdrawn")
		return
	end

	self:getSignal("OfferAccepted"):Fire(player, carId, offer.Amount)
	self:getSignal("OfferAnswered"):Fire(player, carId, true, offer)
	self:getRemoteEvent("OfferResolved"):Fire(player, carId, "sold", offer.Amount)
	self.log:info(string.format("%s sold %s to a buyer for %s.", player.Name, carId, GarageConfig.formatCash(offer.Amount)))
end

-- === The tutorial's buyer ==================================================

--[[ `BuyerConfig.Tutorial`: the SELL beat's buyer. Runs after `_tick` on every pass for a player
	whose tutorial is unfinished (random arrivals are held for them meanwhile).

	ONE AT A TIME, AND ONLY WHEN NONE IS WAITING. Any standing offer is one the player can answer to
	finish the beat, so a second would only be clutter. A buyer who goes unanswered (expired, or the
	car moved) leaves no row, and the next pass sends another.

	NO CAR TO SELL PASSES THE BEAT. A player whose only car went back to the inventory or is marked
	NOT FOR SALE would otherwise wait on this beat for a buyer who can never come.

	NOT UNTIL THEY ARE HOME AND WATCHING (2026-10-19). The beat now starts at the bank, on the road
	(the car parks itself, `TutorialConfig.AutoPark`), so the clock waits for the trip home to end and
	then for the client to say the card is up with nothing over it (`TutorialService.watchingSince`).
	`Fallback` seconds after they are home the buyer comes anyway. ]]
function BuyerService._tutorialTick(self, player: Player)
	local tutorial = BuyerConfig.Tutorial
	if player:GetAttribute(TutorialConfig.StepAttribute) ~= tutorial.Beat then
		self._tutorialSince[player] = nil
		return
	end
	local Race = Shard.get("RaceService")
	if Race and (Race:isRacing(player) or Race:isReturning(player)) then
		self._tutorialSince[player] = nil
		return
	end
	local Tutorial = Shard.get("TutorialService")
	--- When they were first seen home on the beat; the `Fallback` counts from here.
	local since = self._tutorialSince[player]
	if not since then
		self._tutorialSince[player] = os.clock()
		return
	end
	local watching = Tutorial and Tutorial:watchingSince(player, tutorial.Beat)
	local due = (watching ~= nil and os.clock() - watching >= tutorial.Delay) or os.clock() - since >= tutorial.Fallback
	if not due or next(self:_offers(player)) ~= nil then
		return
	end

	local Garage = Shard.get("GarageService")
	--- An unloaded profile has no bays, which would read below as "nothing to sell".
	if not (Garage and Garage:isProfileReady(player)) then
		return
	end
	local prefer: string? = nil
	local bay = Tutorial and Tutorial:pointedBay(player)
	if Garage and bay then
		prefer = select(2, Garage:getBayTip(player, bay))
	end

	local ok, why = self:forceOffer(player, tutorial.Band, prefer)
	if ok then
		self.log:info(string.format("Tutorial buyer for %s: %s.", player.Name, why))
		return
	end
	if #self:_candidates(player, {}) == 0 and Tutorial then
		Tutorial:passBeat(player, tutorial.Beat, why)
	end
end

--[[ `BuyerConfig.Tutorial.OpenOnArrival`: the tutorial's buyer has walked up to the car, so open their
	offer for the player `OpenDelay` later, through `_open`, the same call their prompt makes. Re-checked
	after the wait: still on the beat, still home, and the offer still standing (`_open` answers "gone"
	otherwise, which closes nothing that was open). ]]
function BuyerService._openForTutorial(self, player: Player, carId: string)
	local tutorial = BuyerConfig.Tutorial
	if not (tutorial.Enabled and tutorial.OpenOnArrival) then
		return
	end
	if player:GetAttribute(TutorialConfig.StepAttribute) ~= tutorial.Beat then
		return
	end
	task.delay(tutorial.OpenDelay, function()
		if player.Parent ~= Players or player:GetAttribute(TutorialConfig.StepAttribute) ~= tutorial.Beat then
			return
		end
		local Race = Shard.get("RaceService")
		if Race and (Race:isRacing(player) or Race:isReturning(player)) then
			return
		end
		if self:_offers(player)[carId] then
			self:_open(player, carId)
		end
	end)
end

-- === Admin ==================================================================
--[[ THE PANEL'S LEVERS (2026-09-28), for `AdminService` and nothing else. Each answers
	`(ok, sentence)` for the panel to print. They exist because every question worth asking about
	buyers is otherwise a wait: seventy-five seconds for one to turn up, a one-in-ten roll for a Great
	one, five minutes to watch one give up. They go through the same rows, `_make`, `placeBuyer` and
	`_tick` a real buyer does, so what is being looked at is the real thing arriving early, not a
	lookalike. ]]

--[[ A buyer now, on a random car that could take one, walking in exactly as a fresh arrival does.
	`bandKey` names a `BuyerConfig.Bands` entry to price inside; anything else rolls as normal.

	IT IGNORES `MaxWaiting` and nothing else. The cap is a tuning of how often buyers ARRIVE, and an
	admin asking for one more is the arrival; one buyer per car still holds, because that is a rule
	about the offer screen, not about pacing. ]]
function BuyerService.forceOffer(self, player: Player, bandKey: unknown, prefer: string?): (boolean, string)
	local Garage = Shard.get("GarageService")
	local Customers = Shard.get("CustomerService")
	if not BuyerConfig.Enabled then
		return false, "BuyerConfig.Enabled is false, so no buyer can come."
	end
	if not (Garage and Garage:isProfileReady(player)) then
		return false, "their profile is not loaded yet"
	end

	local offers = self:_offers(player)
	local candidates = self:_candidates(player, offers)
	if #candidates == 0 then
		return false, "no car on a bay is for sale without a buyer already on it"
	end
	local carId = candidates[self._rng:NextInteger(1, #candidates)]
	--- The tutorial names the car the player just parked (`_tutorialTick`), so the buyer goes to it.
	if prefer and table.find(candidates, prefer) then
		carId = prefer
	end

	local ratio, word = nil, "a rolled"
	for _, band in BuyerConfig.Bands do
		if band.Key == bandKey then
			ratio, word = self._rng:NextNumber(band.Min, band.Max), "a " .. band.Key
		end
	end
	local offer = self:_make(player, carId, nil, ratio)
	if not offer then
		return false, string.format("%s has no market value, so nobody offers for it", carId)
	end

	offers[carId] = offer
	self:_write(player, offers)
	local source = if player:GetAttribute(TutorialConfig.StepAttribute) == BuyerConfig.Tutorial.Beat then "Tutorial" else "Admin"
	self:getSignal("OfferMade"):Fire(player, carId, offer, source)
	--- Placed here rather than left to the next pass, because only a buyer placed in the pass that
	--- made them walks in (`_tick`'s `fresh`); left to `_tick` they would appear already standing.
	local _, bay = Garage:locationOf(player, carId)
	if Customers and bay then
		local name = Customers:placeBuyer(player, bay, carId, offer, true)
		if name and name ~= "" then
			offer.Name = name
			self:_write(player, offers)
		end
	end
	return true, string.format("%s offer of %s on %s is walking in", word, GarageConfig.formatCash(offer.Amount), carId)
end

--[[ Every standing offer, set to run out `seconds` from now — the rows AND the signs, so the clock
	on screen is the one the server expires against. The way to watch a lapse without waiting the
	five minutes out. A buyer still walking in has their clock restarted on arrival
	(`_startClock`), so press this after they are standing. ]]
function BuyerService.hurryOffers(self, player: Player, seconds: number): (boolean, string)
	local Customers = Shard.get("CustomerService")
	local offers = self:_offers(player)
	local expiresAt = os.time() + math.max(1, math.floor(seconds))
	local count = 0
	for carId, offer in offers do
		offer.ExpiresAt = expiresAt
		count += 1
		if Customers then
			Customers:setBuyerDeadline(player, carId, expiresAt)
		end
	end
	if count == 0 then
		return false, "no buyers waiting"
	end
	self:_write(player, offers)
	return true, string.format("%d offer(s) now end in %ds", count, math.floor(seconds))
end

--- Every offer dropped and every buyer sent away, selling nothing — the same outcome as each one
--- being declined, without the screen.
function BuyerService.clearOffers(self, player: Player): (boolean, string)
	local Customers = Shard.get("CustomerService")
	local count = 0
	for carId in self:_offers(player) do
		count += 1
		if Customers then
			Customers:removeBuyer(player, carId)
		end
	end
	self:_write(player, {})
	return true, string.format("sent %d buyer(s) away", count)
end

BuyerService:withSignals({
	--- (player: Player, carId: string, amount: number) — a buyer's offer was accepted and the car sold.
	--- Fired after the sale has landed. For whatever wants to count or celebrate it.
	"OfferAccepted",
	--[[ (player: Player, carId: string, accepted: boolean, offer: Offer) - the owner answered an offer,
		either way, and it counted: a sale that landed, or a buyer turned down. Not fired for an offer
		that had already gone. The tutorial's SELL beat advances on it (`TutorialConfig.Steps`). `offer`
		is the row as it stood (2026-10-15, for `AnalyticsService`). ]]
	"OfferAnswered",

	--[[ THE REST OF AN OFFER'S LIFE, for `AnalyticsService` (2026-10-15). Buyers are how cars get
		sold and the SELL beat is built on them, so an offer has to be countable from made to answered,
		including the ones nobody answered. Each carries the row (`Offer`) so a subscriber needs no
		read of the save. ]]
	--- (player, carId, offer, source) : a buyer made an offer. `source` is "Live" (`_tick`),
	--- "Offline" (`catchUp`), "Tutorial" (the SELL beat's) or "Admin" (`forceOffer` otherwise).
	"OfferMade",
	--- (player, carId) : the owner opened the offer screen on a standing offer (`_open`).
	"OfferViewed",
	--- (player, carId, offer, reason) : an offer went without an answer. `reason` is "Expired" or
	--- "Withdrawn" (the car left its bay, came off sale, or was sold another way).
	"OfferDropped",
})

-- === Lifecycle ==============================================================

BuyerService:withLifecycle({
	init = function(self)
		self._rng = Random.new()
		self._trove = Trove.new()
		self._cooldowns = {} :: { [Player]: number }
		--- When each player was first seen on the SELL beat, by `os.clock()`. See `_tutorialTick`.
		self._tutorialSince = {} :: { [Player]: number }
	end,

	start = function(self)
		if not BuyerConfig.Enabled then
			return
		end
		local Garage = Shard.get("GarageService")
		local Customers = Shard.get("CustomerService")

		--[[ THE LOT CHANGED: re-check the rows at once rather than on the next pass, so turning For
			Sale off, moving the car or selling it at the lot sends its buyer away in the same beat
			(`BuyerConfig` note 4) instead of up to `CheckSeconds` later. No arrivals on this path —
			a buyer turning up because you moved a car would be a buyer summoned by a button. ]]
		if Garage then
			self._trove:Add(Garage:getSignal("LotChanged"):Connect(function(player: Player)
				self:_tick(player, false)
			end))
		end
		if Customers then
			self._trove:Add(Customers:getSignal("BuyerPressed"):Connect(function(player: Player, carId: string)
				self:_open(player, carId)
			end))
			self._trove:Add(Customers:getSignal("BuyerArrived"):Connect(function(player: Player, carId: string, walked: boolean)
				if walked then
					self:_startClock(player, carId)
					self:_openForTutorial(player, carId)
				end
			end))
		end

		local accumulator = 0
		self._trove:Add(RunService.Heartbeat:Connect(function(dt)
			accumulator += dt
			if accumulator < BuyerConfig.CheckSeconds then
				return
			end
			accumulator = 0
			for _, player in Players:GetPlayers() do
				--- A first-timer's buyers are the tutorial's to send. See `_tutorialTick`.
				local tutorial = BuyerConfig.Tutorial.Enabled
					and TutorialConfig.isUnfinished(player:GetAttribute(TutorialConfig.StepAttribute))
				self:_tick(player, not tutorial)
				if tutorial then
					self:_tutorialTick(player)
				else
					self._tutorialSince[player] = nil -- so a Replay's SELL beat waits its `Delay` again
				end
			end
		end))

		self._trove:Add(Players.PlayerRemoving:Connect(function(player: Player)
			self._cooldowns[player] = nil
			self._tutorialSince[player] = nil
		end))
	end,
})

BuyerService:withCleanup(function()
	if BuyerService._trove then
		BuyerService._trove:Destroy()
	end
end)

return BuyerService
