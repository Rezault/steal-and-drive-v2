--[[
	SellerConfig
	------------
	Sellers who come to YOU (2026-10-15). Every few minutes, while you are in the lobby, a car pulls up
	at the kerb in front of your dealership with a seller beside it, honks, and waits a while with a
	price on it. Buy it and it goes into your hands (and a hotbar slot) as the seller celebrates
	(`Sold`, `CarryConfig.Sources.Seller`); ignore it and it drives off.

	IT REPLACED THE PLAZA MARKET (`CarDealConfig`, now `Enabled = false`). Stands on the far side of
	the map were a shop you had to remember to visit; a seller at your own door is a decision put in
	front of you, on the lot you already stand on between runs, which is what makes it part of the
	core loop rather than a detour from it. Turn this off and the market back on for the old game.

	THE PRICE IS ROLLED AND RATED, the buyer offer in reverse: a band by weight, uniform inside it, and
	the band's word on the sign (`Bands`). A player can tell a STEAL from a RIP-OFF without doing sums,
	and that is the decision. Server-rolled and server-checked (`SellerService` has the trust note).

	=== THE ONE NUMBER THAT IS NOT A TASTE CALL ==============================================

	`Bands` are fractions of the USUAL price, `Price.Usual` x the car's value, and the cheapest band
	times `Usual` MUST stay above 1. A car sells for exactly its value (`GarageConfig.valueOf`), so a
	seller under that is a money printer: buy, sell, repeat at every visit. This is the same floor, for
	the same reason, as `CarDealConfig`'s header note 3. `SellerService` refuses to start if it is
	broken, rather than trusting this comment.

	The sign compares against `Usual` too ("40% BELOW USUAL"), not against value. Value is what a car
	SELLS for, and a sign saying every seller wants more than it is worth would be true and useless.

	=== PRICED AROUND WORTH NOW — 2026-10-15 ===
	"It says usual price 1800 but when I put it in my bay it says worth 600." The usual price was 3x
	worth, the old plaza market's markup, and nothing else in the game shows that number, so the sign
	contradicted the bay. IS: `Price.Usual = 1`, so prices are measured against the car's WORTH, the
	same number the bay prints, and the sign says "WORTH $600" and "25% BELOW WORTH".

	AND THE FLOOR ABOVE IS RELAXED, on purpose: a STEAL is now genuinely under worth (`Bands`). The
	printer argument was about the plaza, a shop you could buy from over and over. A seller is ONE
	offer per `Visit.Interval`, 12% of them a STEAL, so flipping every STEAL straight to the sell lot
	earns about 0.12 x 0.175 = 2% of one car's worth per visit, a few seconds of its own income every
	four minutes. That is noise. `Price.Floor` is the new line `floorHolds` defends: no band may go
	under it, so a typo in `Bands` still cannot hand cars out for nothing.
]]

local SellerConfig = {}

SellerConfig.Enabled = true

--[[ The part each plot template carries to say where the car pulls up. Placed once in the plot
	template, and every plot gets it because plots are clones. How it reads:
	  * its BOTTOM face is the road the car stands on;
	  * its FRONT face (LookVector) is the way the car drives, so it arrives from behind the part
	    and leaves out the front (`Drive`);
	  * its size is not read: the car is centred on the part, whatever it measures.
	Made invisible and query-blind at start-up. A plot without one simply never gets a seller, and
	that is logged once. ]]
SellerConfig.SpotName = "SellerSpot"

--- The tag on a seller's car model, which is how every client finds one to draw.
SellerConfig.Tag = "SellerCar"

-- === When ===================================================================

SellerConfig.Visit = {
	--[[ Seconds between one seller leaving and the next arriving, plus or minus `Jitter`. Four
		minutes sits beside the buyer offers and the customers' tips without crowding them: one
		thing to decide about at a time. Lower and the kerb is never empty, so it stops being news.
		Higher and a short session might never see one. ]]
	Interval = 240,
	Jitter = 60,
	--- The first seller of a session comes sooner, so a new player meets one before they leave.
	FirstDelay = 75,
	--[[ How long a seller waits before driving off. 90 seconds is time to finish what you were
		doing, walk out and decide, and short enough that a seller ignored for a run is gone when
		you get back rather than still waiting there. ]]
	WaitSeconds = 90,
	--- Seconds before trying again when a visit could not happen (mid-run, tutorial, no spot).
	RetrySeconds = 15,
	--- Rolls before giving up on a car this player does not already own (the owned ones are skipped).
	MaxRerolls = 12,
}

--[[ === ITS OWN RARITY ODDS — 2026-10-15 ===
	WAS: the road's odds (`CarDealConfig.rollBody`), where about 97% of cars are common or uncommon
	and a legendary is 1 in ~1,500. The road rolls hundreds of cars a run, so that works there. A
	seller is ONE roll every four minutes, so a legendary at that rate was about 100 hours away, and
	a seller was nearly always a car the road already hands out for free.

	IS: the chance per visit of each rarity band, 1 Common to 5 Legendary (`TrafficConfig.Bands`).
	Within a band the road's own weights still pick the car. At one visit per ~`Visit.Interval`:

	    Legendary  1.5%  ~1 in 67 visits   ~4.5 hours
	    Epic       4.5%  ~1 in 22          ~1.5 hours
	    Rare        12%  ~1 in 8           ~30 minutes

	That is not a better source than the road: these are PAID for, at the price bands' prices, and
	the price floor (header) holds whatever the car. `Enabled = false` is the road's odds, exactly. ]]
SellerConfig.Rarity = {
	Enabled = true,
	Weights = { 50, 32, 12, 4.5, 1.5 },
}

-- === How it looks ==========================================================

SellerConfig.Drive = {
	--[[ Studs the car travels to pull in and to pull away, and the seconds each takes. A tween on
		every client, not physics: the car is a display car (`CarDisplay`), so there is nothing to
		simulate, and a server-moved model would stutter at replication rate. The server only
		says WHEN (`Attributes.ArriveAt` / `LeaveAt`). ]]
	Distance = 70,
	ArriveSeconds = 2.4,
	LeaveSeconds = 2.2,
	--[[ The fade on the way out (2026-10-15): fraction of `LeaveSeconds` after which the car and its
		driver start fading, reaching nothing at the end. Without it a car that drove off was
		simply deleted 70 studs down the road, still in plain sight. 0.4 lets it read as leaving
		before it starts going. 1 turns the fade off. ]]
	FadeFrom = 0.4,
	--[[ === IT PARKS ON THE FORECOURT NOW — 2026-10-15 ===
		WAS: a spot on the road out front, arriving from behind it and driving off forwards. IS: the
		spot is on the dealership's own forecourt, reached straight in through the entrance, where a
		seller is in plain view of the showroom. There is a wall ahead of it, so it LEAVES BACKWARDS,
		reversing out along the line it came in on. `false` drives off forwards again, for a spot with
		a clear road ahead of it. ]]
	LeaveBackwards = true,

	--[[ === IT USES THE ROAD — 2026-10-15 ===
		WAS: one straight line (`Distance`), in and back out. IS: a route (`route` below). The car
		comes along the road, turns into the entrance and pulls straight in. Leaving, it reverses back
		out the same way, its tail swinging onto the road, then drives off forwards the other way and
		fades. `Path = false` is the straight line above, exactly; `Distance` and `LeaveBackwards`
		only matter then.

		All distances are in the SPOT's frame, which is the frame the car is parked in: its nose is
		the spot's front, so "behind" is out the way it drove in. The route is flat at the spot's
		height, so a road a few studs lower than the forecourt shows the car hovering over it; that
		is a map fact to keep in mind, not something to fix here. ]]
	Path = true,
	--- Studs straight behind the spot to the middle of the lane the car drives along.
	RoadDistance = 58,
	--- Radius of the turn between the road and the driveway. Must stay under `RoadDistance`.
	TurnRadius = 12,
	--- Which side of the entrance it comes from: 1 is the spot's right, -1 its left.
	RoadSide = 1,
	--- Studs of road driven before the turn, and after the reverse when it leaves.
	RoadRun = 80,
	AwayRun = 90,
	--[[ Of `LeaveSeconds`, the share spent reversing out; the rest is driving away, which is
		where the fade happens (`FadeFrom` is then a fraction of the driving away). Reversing is
		slower than driving, hence over half. ]]
	ReverseShare = 0.55,
}

--[[ Arrive and leave take longer with the road in them: about 140 studs in over 6 seconds, eased to
	a stop, and 60 reversing plus 90 driving off over 6. Only applies with `Drive.Path`; the straight
	line keeps its own shorter times. ]]
if SellerConfig.Drive.Path then
	SellerConfig.Drive.ArriveSeconds = 6
	SellerConfig.Drive.LeaveSeconds = 6
end

--[[ === THE SELLER DRIVES — 2026-10-15 ===
	WAS: the car rolled up empty and the seller appeared beside it once it stopped, and on a decline
	the person vanished and an empty car drove off. IS: the seller sits in the driver's seat for both
	drives, steps out when the car stops, and climbs back in before it pulls away.

	The seat is the roster car's OWN `VehicleSeat`, read in the same frame `CarDisplay.build` takes
	its offsets in, so every body puts its driver where its seat is. A body with no seat uses
	`Fallback`. `Offset` lifts the rig's root off the seat pan: `StealConfig.Driver.SeatOffset`'s
	number and reason (an R15 root is about waist height on a seated body). Nudge it, not the clip,
	if a seller sits in the floor or through the roof. `Enabled = false` is the old empty car. ]]
SellerConfig.Seat = {
	Enabled = true,
	Offset = CFrame.new(0, 1.2, 0),
	--- Roblox's own R15 sit pose, the one the default `Animate` script plays in a seat.
	Clip = { Id = 2506281703, Length = 1, Looped = true },
	--[[ No seat on the roster body: the driver's side (local -X, `StealConfig`'s note on `SIDES`)
		at this fraction of the half-width, with the seat pan `PanHeight` studs over the ground. ]]
	Fallback = { Side = 0.45, PanHeight = 1 },
}

--[[ === HOW IT ENDS — 2026-10-15 ===
	WAS: BUY put the owner straight into the car on the spot (`CarDealConfig.Handover`'s beat), and
	DECLINE sent the seller off at once. IS: the buyer offer's endings, read the other way round.

	SOLD. The car goes straight into the buyer's hands, equipped, as a bank does (`awardCar` with the
	`Seller` source, `CarryConfig.Sources`; a full hotbar leaves it in the inventory), and the seller CELEBRATES: a cheer
	(`Emote`), a 😄 over their head, the SOLD! stamp and sparkles (`BuyerController.stamp`, the
	buyer's own effect, with the car's name where the money would be). Then the car and the seller
	fade away together (`FadeSeconds`). If the car is a NEW BEST, that screen plays FIRST: the owner's
	client says when it is clear (`SellerShowReady`), and the server waits for it, at most
	`MaxWaitSeconds`, so a client that never answers cannot leave a car on the kerb.

	DECLINED. A 😠 over the seller's head (`BuyerConfig.Declined`'s emoji), a beat (`DeclineHold`),
	then back in the car and away, as before.

	`Handover = true` is the old BUY: seated in the car on the spot, no show. ]]
SellerConfig.Sold = {
	Handover = false,
	Emoji = "😄",
	--- Roblox's stock R15 cheer. A clip that will not load just leaves the seller standing there happy.
	Emote = { Id = 507770677, Length = 2, Looped = false },
	--- Seconds from the cheer to the fade starting: the stamp's own life, so the two end together.
	HoldSeconds = 2,
	FadeSeconds = 0.8,
	MaxWaitSeconds = 20,
	--- Seconds the 😠 hangs before the seller gets back in the car.
	DeclineHold = 2.5,
}

--[[ === HEARD, NOT ONLY SEEN — 2026-10-15 ===
	Aleafo: "can we add a HEY! sfx when it pulls up, or like a driving in sfx; I never heard it, I
	never looked in that direction." The honk below was never given a clip, so a seller arrived in
	silence. Two sounds now:
	  * `Engine`: the car's own engine pack (`EngineSoundConfig.packFor`) on the drive in and out,
	    positional on the car, so it is heard coming down the road. Off = silent drives.
	  * `ArrivalCue`: when it stops, for the OWNER only and NOT positional, so it reaches them
	    whichever way they face. A `GameplayFeedback` cue: drop a Sound named `SellerArrived` (the
	    "HEY!") into `SoundService.GameplayFeedback` and it plays. Until then `FallbackCue`, the
	    buyer's own arrival sound, does. ]]
SellerConfig.Sound = {
	Engine = true,
	--[[ === LOUDER, AND IT IDLES — 2026-10-15 === ("SFX for the dealer is still too quiet"). WAS the
		pack at its in-car volume, full within 30 studs, and silent once parked. IS `EngineVolume` times
		the pack while driving and `IdleVolume` times it while parked (the engine left running until the
		seller drives off or the sale fades the car), full within `EngineFullWithin`. The packs are mixed
		for a driver sitting in the car; a car across the forecourt needs a few times that. ]]
	EngineVolume = 2.5,
	IdleVolume = 1.5,
	--- Studs of full volume around the car before the engine starts to fall off.
	EngineFullWithin = 80,
	ArrivalCue = "SellerArrived",
	FallbackCue = "OfferArrived",
}

--[[ The honk on arrival, played on each client when its tween ends so it lands on the stop. Empty
	`SoundId`: no honk, everything else unchanged.

	=== IT HAS A SOUND NOW — 2026-10-15 ===
	Aleafo: "can we add a HEY! sfx to this when it pulls up... i never heard it i never looked in that
	direction". The id was blank, so a seller arrived in silence. It is ProSoundEffects' "Vehicle Horn
	Short Long Honks 3", picked by measurement out of 36 horn clips: the only clean BEEP BEEP (two
	blasts, at 0.02 s and 0.24 s, done by 0.4 s), and it sounds on its first frame, so it lands on the
	stop. The Dodge doubles were the other candidates and each has a 0.3 s lead-in.

	`RollOffMinDistance` is what makes it reach you: at the engine's default of 10 it was down to a
	fifth by 50 studs, which is a player across their own lot. Full volume out to this, then tapered
	to nothing at `RollOffMaxDistance`. ]]
SellerConfig.Honk = {
	SoundId = "rbxassetid://9120385635",
	--- 2026-10-15: was 0.9, full within 30 and gone at 160 ("the honk is good, make it louder").
	Volume = 2.5,
	RollOffMinDistance = 80,
	--- Past this many studs it is inaudible. Enough to reach across the lot from the far side.
	RollOffMaxDistance = 300,
}

--[[ First-time onboarding: an outline on the car and a bobbing arrow over it, on every visit UNTIL the
	player has bought from a seller once (`ProfileKey`). That is contextual: it shows up the first
	time the thing is actually there to be used, not in a tutorial before it exists. ]]
SellerConfig.Onboarding = {
	Enabled = true,
	ProfileKey = "SellerBought",
	OutlineColor = Color3.fromRGB(255, 220, 60),
	--- Studs, of the arrow billboard, and how far over the sign it floats.
	ArrowSize = 4,
	ArrowLift = 2.5,
	BobStuds = 0.6,
	BobPeriod = 0.9,
}

-- === What it costs ==========================================================

SellerConfig.Price = {
	--[[ What prices are measured against, as a multiple of the car's worth (`GarageConfig.valueOf`).
		1 since 2026-10-15 (header): the worth the bay shows. WAS 3, the old plaza market's
		`CarDealConfig.Price.Markup`. The bands below are fractions of this. ]]
	Usual = 1,
	--[[ The lowest any price may go, as a fraction of worth (`floorHolds`). 0.7 sits under the
		STEAL band's 0.75, so the bands as written pass and a typo taking a band toward zero does
		not. ]]
	Floor = 0.7,
	--- Price is rounded to this many significant figures so the sign reads like a price tag.
	SignificantFigures = 3,
}

--[[ The rating bands, cheapest first, as fractions of worth (`Price.Usual` is 1, header).

	=== WAS, against a usual price of 3x worth: 0.36-0.5 / 0.5-0.7 / 0.7-1.0 / 1.0-1.15, so even a
	STEAL was 1.08x worth and the average ~2.3x. ===

	=== THE LABELS SAY WHAT THE SIGN SAYS — 2026-10-21 ===
	Aleafo: "i keep buying cars that are listed as fair but its like +30% or +44% above the average
	price, how is that a fair price". WAS Good 0.9-1.15 (w 0.30), Fair 1.15-1.5 (w 0.38), RipOff
	1.5-2.0 (w 0.20), so FAIR was always +15% to +50% and a GOOD DEAL could be +15%. IS: a STEAL and
	a GOOD DEAL are BELOW worth, FAIR is at worth to +15% (Aleafo, same night: "lets make fair 15
	then"; was +20% for an hour), and anything past that is a RIP-OFF. Same four keys, because the
	sign's badge ramps are authored per `Key`.

	Mean by weight:

	    0.10 x 0.825 + 0.25 x 0.95 + 0.35 x 1.075 + 0.30 x 1.575  =  ~1.17x worth

	WAS ~1.26x, so sellers are ~7% cheaper on average. A car on a free bay earns its worth back in
	`SellSeconds` (`GarageConfig.Income`), so even a RIP-OFF pays for itself in under ten minutes. Move
	a weight and redo that sum. Much under 1 and buying everything beats thinking; much over 1.6 and
	nobody buys. ]]
SellerConfig.Bands = {
	{ Key = "Steal", Label = "STEAL!", Weight = 0.10, Min = 0.75, Max = 0.9, Color = Color3.fromRGB(255, 198, 0) },
	{ Key = "Good", Label = "GOOD DEAL", Weight = 0.25, Min = 0.9, Max = 1.0, Color = Color3.fromRGB(13, 180, 21) },
	{ Key = "Fair", Label = "FAIR PRICE", Weight = 0.35, Min = 1.0, Max = 1.15, Color = Color3.fromRGB(150, 160, 180) },
	{ Key = "RipOff", Label = "RIP-OFF", Weight = 0.30, Min = 1.15, Max = 2.0, Color = Color3.fromRGB(226, 96, 96) },
}

-- === Words and wiring ======================================================

SellerConfig.Text = {
	Named = "%s IS SELLING",
	Anonymous = "FOR SALE",
	Caption = "PRICE",
	--- `%d` is the whole percent against the car's worth.
	Below = "%d%% BELOW WORTH",
	Above = "%d%% ABOVE WORTH",
	AtUsual = "AT WORTH",
	Clock = "LEAVES IN <font color=\"#FFD84A\">%s</font>",
	--[[ === IT OPENS THE OFFER SCREEN NOW — 2026-10-15 ===
		WAS: hold E and the car was bought on the spot. IS: E opens the buyer offer screen
		(`BuyerController.openSeller`) showing the car, the price and the rating, with BUY and
		DECLINE, so a car is never bought by a key press meant for something else. DECLINE sends
		the seller away (`SellerService._answer`). ]]
	ActionText = "See Offer",
	--- The offer screen's accept button, and the line under the price.
	Buy = "BUY",
	UsualLabel = "WORTH",
}

--[[ === THE SIGN IS THE BUYER'S NEW CARD, IN GOLD — 2026-10-15 ===
	WAS: the old kit sign (`BuyerOfferSign.buildKit`, "HALT_CEO IS SELLING" over a white panel and a
	separate clock strip), left behind when the buyer's sign moved to design B the same day. Dylan:
	"make it just slightly different so that you know that he's selling a car".
	IS: design B's card, off `MainUIV2.Screens.SellerSigns` (`BuildBuyerSignDesigns`): the seller's
	face and FOR SALE BY in the header, the seller's rating band on the badge, and a pill that is
	GREEN under worth, the buyer's colours the other way round, because a low price is good news
	when you are the one paying it. Four variations were photographed (Blue, Green, Gold, and a
	FOR SALE tag on B's blue) and Dylan picked GOLD the same day: a warm header against the
	buyer's blue, so the two tell apart before any word on them can be read.
	nil, or a key the place does not have, keeps the old kit sign. ]]
SellerConfig.Bubble = {
	Design = "Gold",
	--- Studs tall; the buyer's `DesignHeight`. The width follows the card's own `Aspect`.
	DesignHeight = 5.8,
	--- The header's small line over the name.
	From = "FOR SALE BY",
	AnonymousName = "A SELLER",
	--- The value pill per direction, for the BUYER of the car: under worth is the good one.
	Pill = {
		Below = { Fill = Color3.fromRGB(214, 247, 206), Rim = Color3.fromRGB(96, 200, 84), Arrow = Color3.fromRGB(52, 196, 60), Ink = Color3.fromRGB(22, 118, 30) },
		Above = { Fill = Color3.fromRGB(255, 218, 218), Rim = Color3.fromRGB(236, 104, 104), Arrow = Color3.fromRGB(232, 57, 58), Ink = Color3.fromRGB(160, 22, 30) },
		At = { Fill = Color3.fromRGB(226, 233, 246), Rim = Color3.fromRGB(150, 166, 198), Ink = Color3.fromRGB(40, 51, 75) },
	},
}

SellerConfig.Prompt = {
	--- A tap, as a buyer's See Offer is: the screen is the confirmation now, not the hold.
	HoldDuration = 0,
	MaxDistance = 14,
	--- Seconds between two presses from one player that the server will act on.
	Cooldown = 1,
}

--[[ Attributes on the car model. Written by the server in one go before the model is parented, so a
	client never draws a half-described seller. ]]
SellerConfig.Attributes = {
	Owner = "SellerOwner",
	Body = "SellerBody",
	Tier = "SellerTier",
	Paint = "SellerPaint",
	Price = "SellerPrice",
	Usual = "SellerUsual",
	Name = "SellerName",
	--- The friend whose avatar the seller wears, for the face on the sign (`Bubble`). Absent on a stock rig.
	UserId = "SellerUserId",
	--- Server time (`GetServerTimeNow`) the car started pulling in, and the one it starts leaving.
	ArriveAt = "SellerArriveAt",
	LeaveAt = "SellerLeaveAt",
	ExpiresAt = "SellerExpiresAt",
	--- Where the car stands, so a client can tween in from behind it and away in front of it.
	Frame = "SellerFrame",
	--- True while this player has never bought from a seller (`Onboarding`).
	First = "SellerFirst",
	--- The seated rig root relative to `Frame`, which the client carries along with the car (`Seat`).
	Seat = "SellerSeat",
	--- True while the seller stands beside the car. While it is, the client leaves the rig alone.
	Out = "SellerOut",
	--- Bought: the offer is over, the sign comes down, and the owner's client checks for a NEW BEST.
	Sold = "SellerSold",
	--- Server time the celebration started (the stamp), and the one the fade started.
	SoldAt = "SellerSoldAt",
	FadeAt = "SellerFadeAt",
	--- Turned down: the owner hears the huff.
	Declined = "SellerDeclined",
}

--- Names of the pieces inside the car model that the client looks for.
SellerConfig.Names = {
	Model = "SellerCar",
	Car = "Car",
	Anchor = "SignAnchor",
	Prompt = "SellerPrompt",
	Rig = "Seller",
}

--[[ Roll a price for a car of this value: a band by weight, uniform inside it, rounded. Returns the
	price and the usual price it was measured against. `forced` (a band `Key`, the admin panel's)
	skips the weighted pick and rolls inside that band; anything else is a normal roll. Pure:
	server-only in practice, because the roll is the product. ]]
function SellerConfig.rollPrice(rng: Random, value: number, forced: unknown?): (number, number)
	local usual = value * SellerConfig.Price.Usual
	local total = 0
	for _, band in SellerConfig.Bands do
		total += band.Weight
	end
	local roll = rng:NextNumber() * total
	local chosen = SellerConfig.Bands[#SellerConfig.Bands]
	for _, band in SellerConfig.Bands do
		roll -= band.Weight
		if roll <= 0 then
			chosen = band
			break
		end
	end
	for _, band in SellerConfig.Bands do
		if band.Key == forced then
			chosen = band
		end
	end
	local raw = usual * rng:NextNumber(chosen.Min, chosen.Max)
	local figures = SellerConfig.Price.SignificantFigures
	local step = if raw > 0 then 10 ^ math.max(0, math.floor(math.log10(raw)) + 1 - figures) else 1
	--- Rounded UP, so rounding can never carry the cheapest band under the floor (header).
	return math.ceil(raw / step) * step, usual
end

--- The band a price falls in against its usual price. Reads the same table the roll did.
function SellerConfig.bandFor(price: number, usual: number)
	if usual <= 0 then
		return SellerConfig.Bands[3]
	end
	local ratio = price / usual
	for _, band in SellerConfig.Bands do
		if ratio < band.Max then
			return band
		end
	end
	return SellerConfig.Bands[#SellerConfig.Bands]
end

--- "40% BELOW USUAL" and its siblings.
function SellerConfig.compareText(price: number, usual: number): string
	if usual <= 0 then
		return SellerConfig.Text.AtUsual
	end
	local percent = math.round((price / usual - 1) * 100)
	return if percent < 0 then string.format(SellerConfig.Text.Below, -percent)
		elseif percent > 0 then string.format(SellerConfig.Text.Above, percent)
		else SellerConfig.Text.AtUsual
end

--[[ The drive, as poses in the SPOT's frame (identity is parked: nose along -Z, so behind is +Z),
	each oriented the way the car's NOSE points, whichever way it is moving. With s = `RoadSide`,
	D = `RoadDistance`, r = `TurnRadius`:

	    road    (s(r + RoadRun), D) -> (s r, D)            heading -s along X
	    turn    a quarter circle about (s r, D - r)        heading -s X turning to -Z
	    drive   (0, D - r) -> (0, 0)                       heading -Z, into the spot

	`arrive` is those three. `reverse` is the turn and the drive run backwards (same poses, nose
	unchanged), which swings the tail onto the road with the nose pointing -s. `away` carries on
	forwards from there. That is "back out and head the other way", and it is why the away leg needs
	no second turn. Pure, so the Studio preview draws the same route the clients drive. ]]
function SellerConfig.route(): { arrive: { CFrame }, reverse: { CFrame }, away: { CFrame } }
	local drive = SellerConfig.Drive
	local s, d, r = drive.RoadSide, drive.RoadDistance, drive.TurnRadius
	local function at(x: number, z: number, hx: number, hz: number): CFrame
		local p = Vector3.new(x, 0, z)
		return CFrame.lookAt(p, p + Vector3.new(hx, 0, hz))
	end
	--- One sample every ~2 studs on the straights and every ~5 degrees round the turn: smooth at any
	--- speed this drives, and a few dozen poses in all.
	local function line(out: { CFrame }, x0: number, z0: number, x1: number, z1: number, hx: number, hz: number)
		local steps = math.max(1, math.ceil(math.max(math.abs(x1 - x0), math.abs(z1 - z0)) / 2))
		for i = 0, steps do
			local k = i / steps
			table.insert(out, at(x0 + (x1 - x0) * k, z0 + (z1 - z0) * k, hx, hz))
		end
	end

	local turn = {}
	local arrive = {}
	line(arrive, s * (r + drive.RoadRun), d, s * r, d, -s, 0)
	for i = 1, 18 do
		local phi = i / 18 * math.pi / 2
		table.insert(turn, at(s * r - s * r * math.sin(phi), d - r + r * math.cos(phi), -s * math.cos(phi), -math.sin(phi)))
	end
	for _, pose in turn do
		table.insert(arrive, pose)
	end
	local inward = {}
	line(inward, 0, d - r, 0, 0, 0, -1)
	for _, pose in inward do
		table.insert(arrive, pose)
	end

	--- The turn and the drive, backwards: from the spot to the end of the road run.
	local reverse = {}
	for i = #inward, 1, -1 do
		table.insert(reverse, inward[i])
	end
	for i = #turn, 1, -1 do
		table.insert(reverse, turn[i])
	end
	table.insert(reverse, at(s * r, d, -s, 0))

	local away = {}
	line(away, s * r, d, s * r - s * drive.AwayRun, d, -s, 0)
	return { arrive = arrive, reverse = reverse, away = away }
end

--[[ The pose `u` (0..1) of the way along `poses` BY DISTANCE, not by index, so the car keeps one
	speed through the samples whatever their spacing. Pure. ]]
function SellerConfig.sample(poses: { CFrame }, u: number): CFrame
	local total = 0
	for i = 2, #poses do
		total += (poses[i].Position - poses[i - 1].Position).Magnitude
	end
	local want = math.clamp(u, 0, 1) * total
	for i = 2, #poses do
		local length = (poses[i].Position - poses[i - 1].Position).Magnitude
		if want <= length or i == #poses then
			return poses[i - 1]:Lerp(poses[i], if length > 0 then math.clamp(want / length, 0, 1) else 1)
		end
		want -= length
	end
	return poses[#poses] or CFrame.identity
end

--- Is the price floor intact (`Price.Floor`, the header's 2026-10-15 note)? `SellerService` refuses to run when it is not.
function SellerConfig.floorHolds(): boolean
	return SellerConfig.Bands[1].Min * SellerConfig.Price.Usual >= SellerConfig.Price.Floor
end

return SellerConfig
