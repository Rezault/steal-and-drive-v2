--[[
	BuyerConfig
	-----------
	THE PEOPLE WHO WANT TO BUY YOUR CAR. A buyer walks onto a dealership, picks one car that is on
	show and for sale, stands beside it and waits, with an offer over their head. Press them and the
	offer screen says what they will pay, what the car is worth, and how good a deal that is. ACCEPT
	sells that exact car for that exact money; DECLINE sends them away. Nothing is ever sold without
	the press. `BuyerService` is the machine, `CustomerService` builds and stands the rig, and
	`BuyerController` draws the sign and the screen. Added 2026-09-28 with the dealership rework.

	=== FIVE THINGS TO KNOW BEFORE TUNING ANY OF IT ============================================

	1. AN OFFER IS A SAVED FACT, NOT A PERSON. It lives in the profile (`Garage.Offers`, car ID ->
	   amount, deadline, name), so it survives a run, a rejoin and a server hop; the rig standing next
	   to the car is DRAWN from it, and is rebuilt from it whenever it is missing. That is what lets a
	   buyer arrive while the owner is out on a run and still be there when they come home.

	2. THE CLOCK IS REAL TIME, and the five minutes is the market's (`CarDealConfig.Offer.Interval`),
	   on the owner's call: a buyer is the plaza's seller the other way round, and one waits exactly as
	   long as the other. A long run can therefore outlast an offer. That was chosen over pausing the
	   clock while the owner is away, knowingly — the waiting line on the run summary and the Welcome
	   Back screen is what makes a lapse visible rather than silent.

	3. ONE BUYER PER CAR, `MaxWaiting` PER LOT. A second buyer on the same car would be two offers the
	   player has to compare for a decision about one car, and a lot of six buyers is a queue, not a
	   showroom.

	4. ONLY A CAR ON A BAY AND FOR SALE IS OFFERED FOR. Moving the car off its podium, taking it off
	   sale or selling it at the lot cancels its offer and sends its buyer away (`BuyerService._validate`,
	   off `GarageService.LotChanged`). A car only in the inventory is never offered for — buyers look
	   at the lot, and nobody can see the inventory.

	5. THE OFFER IS A MULTIPLE OF MARKET VALUE, and market value is what the sell lot pays. So "Fair" is
	   the sell lot's price with the walk to the lot taken away, "Good" and "Great" beat it, and "Low"
	   is a buyer the player should turn down. The bands below ARE the rating: an offer is rolled into a
	   band and then priced inside it, so the word on the screen can never disagree with the number.

	`Enabled = false`: no buyer ever arrives, saved offers are left untouched, and the lot behaves
	exactly as it did before this file existed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ The market's offer length, for header note 2. A CONFIG requiring a config: `CarDealConfig`
	requires nothing that reaches back here. ]]
local CarDealConfig = require(ReplicatedStorage.shared.Configs.CarDealConfig)

local BuyerConfig = {}

BuyerConfig.Enabled = true

-- === When they come =========================================================

--- The profile key, inside `Garage`. A MAP of car ID -> offer, string-keyed for the datastore reason
--- every other per-car table there is.
BuyerConfig.ProfileKey = "Offers"

--- Seconds an offer stands before the buyer gives up. The market's rotation, exactly (note 2).
BuyerConfig.Lifetime = CarDealConfig.Offer.Interval

--- Buyers waiting on one lot at once. See note 3.
BuyerConfig.MaxWaiting = 3

--[[ Mean seconds between buyers arriving on a lot that has room for one. Rolled as a chance per
	`CheckSeconds`, so arrivals are memoryless — a lot does not get a buyer on a metronome.

	75 against a 300-second lifetime keeps a lot with for-sale cars near its `MaxWaiting` without ever
	parking it there: about four arrive per offer lifetime, so a player who answers them keeps seeing
	fresh ones, and one who ignores them sees the line fill and then turn over. A TASTE CALL, not a
	measurement; the one number to move if offers feel spammy or scarce. ]]
BuyerConfig.MeanArrivalSeconds = 75

--- Seconds between passes of the service's loop: expiry, arrivals and the rig check. Cheap.
BuyerConfig.CheckSeconds = 2

--[[ THE TUTORIAL'S BUYER (2026-10-06, Leaf: "guarantee a car sale quicker on the onboarding"). While
	a player's tutorial is unfinished, no random buyer comes for them. Once they reach `Beat` (right
	after they park their first car), one is sent `Delay` seconds later to the car they parked
	(`TutorialService.pointedBay`), priced inside the `Band` band, and sent again if they leave
	unanswered. The tutorial's chip rides that buyer. A player on that beat with no car on a bay for sale has no
	buyer to wait for, so the beat is passed for them (`TutorialService.passBeat`).

	`Band` is a `Bands` key. "Good" (1.05 to 1.2x value) so that accepting beats the sell lot without
	the first sale setting an expectation the market rarely meets. Leaf may want "Great".

	`Enabled = false`: the tutorial gets no buyer of its own and random arrivals run as normal. ]]
BuyerConfig.Tutorial = {
	Enabled = true,
	Beat = "sell",
	Delay = 3,
	Band = "Good",
}

-- === What they offer ========================================================

--[[ THE BANDS, in order. `Weight` is how often a buyer lands in the band, `Min`/`Max` the offer as a
	multiple of the car's market value inside it. Contiguous on purpose, so every ratio a buyer can
	offer has exactly one word.

	WEIGHTED TOWARD THE MIDDLE AND UNDER IT: about a third of buyers lowball, a third are fair, and a
	third beat the sell lot — one in ten by a lot. That is what makes DECLINE a real decision rather
	than a button nobody presses: the player waits for a Great deal on the car they care about and
	takes a Fair one on a spare. The mean ratio, band midpoints by weight:

	    0.32 x 0.81 + 0.36 x 0.975 + 0.22 x 1.125 + 0.10 x 1.30  =  ~0.99

	(0.987 over 20,000 rolls), so buyers as a whole pay about what the sell lot does and the edge is
	entirely in choosing. Move a weight and re-run that sum: much above 1 and accepting everything
	beats thinking; much below and there is no reason to put a car out at all. ]]
BuyerConfig.Bands = {
	{ Key = "Low", Label = "LOW OFFER", Weight = 0.32, Min = 0.72, Max = 0.9, Color = Color3.fromRGB(226, 96, 96) },
	{ Key = "Fair", Label = "FAIR DEAL", Weight = 0.36, Min = 0.9, Max = 1.05, Color = Color3.fromRGB(206, 214, 232) },
	{ Key = "Good", Label = "GOOD DEAL", Weight = 0.22, Min = 1.05, Max = 1.2, Color = Color3.fromRGB(13, 180, 21) },
	{ Key = "Great", Label = "GREAT DEAL", Weight = 0.1, Min = 1.2, Max = 1.4, Color = Color3.fromRGB(255, 198, 0) },
}

--[[ Roll one offer ratio: a band by weight, then uniform inside it. `weights` (a buyer kind's `Bands`,
	band key -> weight) replaces each band's own `Weight` when given; a band it does not name weighs 0. ]]
function BuyerConfig.rollRatio(rng: Random, weights: { [string]: number }?): number
	local function weightOf(band): number
		return if weights then (weights[band.Key] or 0) else band.Weight
	end
	local total = 0
	for _, band in BuyerConfig.Bands do
		total += weightOf(band)
	end
	local roll = rng:NextNumber() * total
	for _, band in BuyerConfig.Bands do
		roll -= weightOf(band)
		if roll <= 0 then
			return rng:NextNumber(band.Min, band.Max)
		end
	end
	local last = BuyerConfig.Bands[#BuyerConfig.Bands]
	return rng:NextNumber(last.Min, last.Max)
end

--[[ The band an offer falls in, from the amount and the value it is measured against. Reads the SAME
	table the roll used (note 5), so the rating is a fact about the number rather than a second opinion.
	A value of 0 (a body off the roster) is read as a Fair offer: there is nothing to compare against,
	and a word that shouts GREAT for an unpriceable car would be a lie. ]]
function BuyerConfig.bandFor(amount: number, value: number)
	if value <= 0 then
		return BuyerConfig.Bands[2]
	end
	local ratio = amount / value
	for _, band in BuyerConfig.Bands do
		if ratio < band.Max then
			return band
		end
	end
	return BuyerConfig.Bands[#BuyerConfig.Bands]
end

--- "+12% ABOVE VALUE" / "-8% BELOW VALUE" / "AT VALUE". Whole percent, rounded toward the truth.
function BuyerConfig.percentText(amount: number, value: number): string
	if value <= 0 then
		return "AT VALUE"
	end
	local percent = math.round((amount / value - 1) * 100)
	if percent > 0 then
		return string.format("+%d%% ABOVE VALUE", percent)
	elseif percent < 0 then
		return string.format("%d%% BELOW VALUE", percent)
	end
	return "AT VALUE"
end

-- === Who they are ===========================================================

--[[ BUYER KINDS (2026-10-06). Until now every buyer was the same person rolling the same dice, so
	the only thing that told one offer from another was the number. A kind is a personality the
	player can READ off the sign before opening it — "COLLECTOR FEMMY WANTS TO BUY" — and learn to
	play: a bargain hunter is a buyer to turn down, a collector is worth waiting for.

	    Regular      no title. The bands exactly as above, and most buyers.
	    Bargain      BARGAIN HUNTER. Lowballs; the one to decline.
	    Hurry        IN A HURRY. Pays well, but waits `Lifetime` x the usual — answer now or lose it.
	    Enthusiast   CAR ENTHUSIAST. Only comes for cars of rarity band `MinBand` (3) and up.
	    Collector    COLLECTOR. Only for band 4 and up — and a WEATHER car counts one band higher,
	                 because a mutation is exactly what a collector is after. The best payer.

	RARITY DRAWS BETTER BUYERS, AND THAT IS THE WHOLE ECONOMIC EFFECT. Kinds are drawn by `Weight`
	among those whose `MinBand` the car meets, so a common car only ever sees the first three and a
	rare one sees all five. Mean offer ratio, band midpoints by weight (BuyerConfig.Bands):

	    Regular 0.99   Bargain 0.88   Hurry 1.10   Enthusiast 1.05   Collector 1.14
	    common car (bands 1-2)   (50 x 0.99 + 18 x 0.88 + 8 x 1.10) / 76    = ~0.98
	    band 3                   ...+ 14 x 1.05, over 90                     = ~0.99
	    band 4-5                 ...+ 10 x 1.14, over 100                    = ~1.00

	So buyers as a whole still pay about what the sell lot does (the bands' own note), commons a
	shade under and the rarest at par — the edge stays in CHOOSING, and what rarity buys is the
	chance of the big offer, not a higher average. Re-run those sums if a weight moves.

	THE KIND IS SAVED ON THE OFFER (`Kind`, absent = Regular), so a buyer keeps being who they were
	through a rejoin. An old save's offers have no kind and read as Regular.

	`Enabled = false`: every buyer is a Regular, which is the game exactly as before this block. ]]
BuyerConfig.Kinds = {
	Enabled = true,
	List = {
		{ Key = "Regular", Title = nil, Weight = 50, MinBand = 1 },
		{ Key = "Bargain", Title = "BARGAIN HUNTER", Weight = 18, MinBand = 1, Bands = { Low = 0.6, Fair = 0.35, Good = 0.05, Great = 0 } },
		{ Key = "Hurry", Title = "IN A HURRY", Weight = 8, MinBand = 1, Lifetime = 0.5, Bands = { Low = 0.05, Fair = 0.3, Good = 0.45, Great = 0.2 } },
		{ Key = "Enthusiast", Title = "CAR ENTHUSIAST", Weight = 14, MinBand = 3, Bands = { Low = 0.15, Fair = 0.35, Good = 0.35, Great = 0.15 } },
		{ Key = "Collector", Title = "COLLECTOR", Weight = 10, MinBand = 4, Bands = { Low = 0.05, Fair = 0.2, Good = 0.4, Great = 0.35 } },
	},
}

--- The kind saved under `key`, or nil (absent, unknown, or kinds switched off: a Regular).
function BuyerConfig.kindOf(key: unknown)
	if not BuyerConfig.Kinds.Enabled or type(key) ~= "string" then
		return nil
	end
	for _, kind in BuyerConfig.Kinds.List do
		if kind.Key == key then
			return kind
		end
	end
	return nil
end

--- Draw a kind for a car of rarity `band` (1..5, a weather car one higher). nil = Regular.
function BuyerConfig.pickKind(rng: Random, band: number)
	if not BuyerConfig.Kinds.Enabled then
		return nil
	end
	local pool, total = {}, 0
	for _, kind in BuyerConfig.Kinds.List do
		if band >= kind.MinBand and kind.Weight > 0 then
			table.insert(pool, kind)
			total += kind.Weight
		end
	end
	local roll = rng:NextNumber() * total
	for _, kind in pool do
		roll -= kind.Weight
		if roll <= 0 then
			return if kind.Key == "Regular" then nil else kind
		end
	end
	return nil
end

--- Seconds an offer from this kind stands (`Lifetime` x a kind's own share; nil kind = the full one).
function BuyerConfig.lifetimeFor(kind): number
	return math.max(30, math.round(BuyerConfig.Lifetime * (if kind and kind.Lifetime then kind.Lifetime else 1)))
end

-- === The big ones ===========================================================

--[[ THE GREAT-DEAL MOMENT (2026-10-06). One buyer in ten is a GREAT DEAL and some are COLLECTORS,
	and until now they arrived exactly like a lowball: a sign switching on. The exciting offers should
	look exciting, so when one ARRIVES at the car (`BuyerController._excite`):

	  • its sign breathes — swelling to `Pulse` x its size and back every `PulseSeconds`, for as long
	    as it stands, so a Great offer is the one sign on the lot that moves;
	  • a burst of `Sparkles` gold sparkles goes up off the buyer;
	  • the OWNER hears `Sound` (`SoundService.<Group>.<Name>`; missing = silent, so it works before
	    the sound is added).

	`Bands`/`Kinds` say which offers count. `Enabled = false` is every buyer arriving as before. ]]
BuyerConfig.Excite = {
	Enabled = true,
	Bands = { Great = true },
	Kinds = { Collector = true },
	Pulse = 1.08,
	PulseSeconds = 0.6,
	Sparkles = 40,
	SparkleColor = Color3.fromRGB(255, 214, 80),
	Sound = { Group = "Buyer", Name = "GreatOffer" },
}

--[[ THE SOLD MOMENT (2026-10-06, the polish pass). Accepting an offer used to close the screen and
	that was all — the payoff of the whole sell loop had no beat. Now, where the buyer stood: a big
	SOLD! with the price under it pops up over the car and floats off, a burst of sparkles goes up,
	the banknotes fly into the player (`CashBurstController`), and `Sound` plays if it exists
	(`SoundService.<Group>.<Name>`; missing = silent). All client-side and after the server has
	already sold the car, so none of it is on the money path. `Enabled = false` is the old close. ]]
BuyerConfig.Sold = {
	Enabled = true,
	Text = "SOLD!",
	Color = Color3.fromRGB(80, 230, 90),
	--- Studs: the stamp's size, how high over the buyer's head it starts, how far it floats up.
	Width = 9,
	Height = 4,
	Above = 2,
	Rise = 4,
	Seconds = 1.8,
	Sparkles = 60,
	Sound = { Group = "Buyer", Name = "Sold" },
}

-- === Where they stand =======================================================

BuyerConfig.Stand = {
	--[[ Studs out from the side of the podium's base, tried from `Side` to `MaxSide`, left then
		right, until a spot is clear — the same fitted-not-fixed search `CustomerConfig.View` does for
		the viewing spot, and for the same reason: one side of some bays is a column.

		BESIDE AND NOT IN FRONT, because in front is where customers stand to look (`_standFor`). A
		buyer parked on that spot would stop the car it is buying from earning tips for five minutes,
		which is a cost the offer never mentions. Only if neither side fits does the buyer take the
		front spot, and then customers skip that bay until the buyer goes. ]]
	Side = 2,
	MaxSide = 8,

	--[[ === IN FRONT OF THE CAR NOW — 2026-09-28 ==============================================

		WHAT IT WAS. Beside the podium (the paragraph above), so customers kept the front spot and the
		car kept earning tips while it had a buyer.

		WHAT IT IS. In front, where anybody looking at a car stands — the owner's partner, on seeing
		the side placement: a buyer off to one side of the podium reads as someone waiting for a
		different car. The cost the paragraph above names is taken knowingly: while a buyer stands
		there that bay is HELD (`CustomerService.placeBuyer`), so no customer stacks on the same car and
		it draws no tips until the buyer is answered or gives up. The sides are still tried when the
		front will not fit.

		`false` puts buyers back beside the podium, exactly as before. ]]
	Front = true,

	--[[ === BUYERS WALK IN NOW — 2026-09-28 =================================================

		WHAT IT WAS. A buyer appeared beside the car, already standing, the moment the offer was made.

		WHAT IT IS. A buyer whose offer was made THIS pass spawns on the forecourt, where customers
		arrive (`CustomerConfig.Arrival`), and walks to the car on the customers' own pathfinding
		(`CustomerService._walkTo`) at the customers' pace. Only then do they face the car, plant their
		feet and take the prompt — so an owner cannot answer somebody still mid-stride.

		ONLY FRESH ARRIVALS WALK. A buyer rebuilt from the save — after a rejoin, a plot swap, or one
		who turned up while the owner was logged out (`BuyerService.catchUp`) — has by definition been
		waiting a while, and is stood in place. Walking those in would be the lot re-enacting arrivals
		nobody is there to see, and making a returning player wait for buyers they already have.

		A WALK THAT FAILS STILL ENDS AT THE CAR. A blocked path or a timed-out leg places the buyer on
		their spot, for the same reason a customer's failed walk still ends at the exit: there is no
		branch that leaves a rig lost on somebody's forecourt.

		`false` puts every buyer in place instantly, exactly as before. ]]
	WalkIn = true,

	--[[ THE OFFER STARTS AT THE CAR — 2026-09-28. A walking buyer shows no sign and has no prompt
		until they are standing beside the car, and their `Lifetime` counts from that moment rather
		than from the spawn (`BuyerService._startClock`). Before this, the sign and its clock walked
		in with them, so a buyer spent the first stretch of their five minutes crossing the lot with
		an offer nobody could answer yet.

		`false`: the sign is still held until arrival, but the clock runs from the spawn, so the
		walk comes out of the five minutes as it did before. ]]
	ClockOnArrival = true,
}

-- === Words ==================================================================

--- The billboard. `%s` is the buyer's name; a nameless fallback rig says `Anonymous`.
BuyerConfig.Bubble = {
	-- 2026-10-04: the world sign now matches the bold blue/white offer screen. False restores
	-- the original market-style sign; offer logic and the screen itself are unchanged.
	ArcadeStyle = true,
	-- 2026-10-06: on the new UI the sign is the Cartoony Kit's own PromptUI, cloned from
	-- `MainUIV2.Screens.BuyerSign` (BuildBuyerOfferV2). False, the old UI, or a place without the
	-- template falls back to `ArcadeStyle` above. It is drawn at `ArcadeScale` too.
	KitStyle = true,
	-- The market's full-sized board obscured the car up close. 70% on each axis halves its
	-- screen area; BuyerOfferSign keeps its text scaled to the rows instead of fixed-size.
	ArcadeScale = 0.7,
	Named = "%s WANTS TO BUY",
	Anonymous = "A BUYER WANTS TO BUY",
	--- With a kind (`Kinds`): its title, then the name. "COLLECTOR FEMMY WANTS TO BUY".
	NamedKind = "%s %s WANTS TO BUY",
	AnonymousKind = "A %s WANTS TO BUY",
	Caption = "OFFER",
	--- The clock strip's caption, before the countdown (`CarDealConfig.clockLineFor`).
	Clock = "OFFER ENDS IN",
}

--- The prompt over a buyer, owner-only (`BuyerController` hides it for everybody else).
BuyerConfig.Prompt = {
	ActionText = "See Offer",
	HoldDuration = 0,
	MaxDistance = 12,
}

--- The offer screen. Placeholder UI built in code; see `BuyerController`.
BuyerConfig.Screen = {
	Title = "OFFER FOR YOUR %s",
	Offered = "THEY OFFER",
	Value = "MARKET VALUE",
	Accept = "ACCEPT",
	Decline = "DECLINE",
	--[[ The new UI's header (`BuildBuyerOfferV2`, 2026-09-30): who is asking, since the car's name
		has its own line over the car. `Title` above stays the old screen's. ]]
	From = "OFFER FROM %s",
	FromAnonymous = "BUYER OFFER",
	--- Seconds between presses of either answer. Courtesy on top of the server's own check.
	Cooldown = 0.5,
}

-- Approved economy balance, 2026-10-04.
--[[ BACK ON (2026-10-05). This block had put buyers beside the podium again, which on a row of bays
	stands them in the gap BETWEEN two cars — the playtest showed a buyer for the white car standing by
	the green one. In front is the owner's partner's call of 2026-09-28 (`Stand.Front`'s own note). ]]
BuyerConfig.Stand.Front = true

return BuyerConfig
