--[[
	GarageConfig
	------------
	The meta game (GDD §4): a car you got away with is parked in a bay on your dealership plot, and
	that bay prints money until you walk over and collect it.

	FIVE THINGS TO KNOW BEFORE TUNING ANY OF IT.

	1. PENDING CASH IS DERIVED, NEVER ACCUMULATED. There is no income loop adding to a counter. Each
	   parked car stores one number — the `os.time()` it was last collected — and what it owes you is

	       pending = min(now - collectedAt, MaxBankedSeconds) * rate(tier) * Multiplier

	   That is the whole economy. It falls out of it that offline income needs no extra code (the
	   clock kept running while you were gone), that a server crash cannot lose a partial tick, and
	   that nothing has to be flushed to the profile on a timer. The only loop in `GarageService`
	   redraws the labels; delete it and the money still works.

	2. THE TIER LADDER IS GEOMETRIC, AND 2.5 IS THE WHOLE BALANCE. `Income.Growth` is the one number
	   that decides whether the run is worth pushing. See the block on `Income` for the derivation —
	   it is the only value here chosen against anything other than taste.

	3. A CAR IS WORTH `SellSeconds` OF ITS OWN INCOME. There is no second price table, and there
	   should never be one: the moment sale price and income are set independently they drift, and
	   "is this worth keeping" stops having an answer you can compute. See `Income.SellSeconds`.

	4. BANKING IS NEVER WASTED. Driving into the truck ENDS THE RUN (GDD §3.5's design guard), so a
	   bank that pays nothing is a minute of play thrown away and reads as a bug even when it isn't.
	   Every outcome pays: a new car parks, a duplicate sells, a full lot either upgrades and sells
	   the car it displaced, or sells the new one. See `Banking`.

	5. THE MAP IS THE CONTRACT, exactly as it is for the road, the truck and the plots. `GarageService`
	   finds bays by walking each plot's `CarSlots` folder and reading the `SlotIndex` the map already
	   carries — it never builds a podium and never assumes there are six. Add a seventh slot to a
	   plot with the right attribute and it becomes usable with no code change. The podiums themselves
	   are authored (`docs/MapLayout.md` §4) and propagated by the `PropagateCarSlots` command.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ The roster, and only the roster. This file used to derive its ladder from `TrafficConfig` —
	it now takes it from `WorldConfig`, one step further up, because the garage prices every car in
	the game and traffic only spawns the live world's. That also drops a require: pricing no longer
	depends on the file that decides how fast a car drives. ]]
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
--[[ For `StockIndex` alone, and so the one place that spells out "a car with no colour recorded"
	spells it the same way `PaintConfig` does. It requires nothing itself, so this cannot cycle. ]]
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)
--- The game name each body is shown as (`displayName`). A config requiring a config; it requires
--- nothing back.
local CarNameConfig = require(ReplicatedStorage.shared.Configs.CarNameConfig)
--[[ For the mutation half of a car key, and for what a mutated car is worth parked. Like
	`PaintConfig` above it requires nothing itself, so this cannot cycle — which is worth keeping
	true: this file is required by half the codebase, so anything it pulls in is effectively pulled
	in everywhere. ]]
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)

local GarageConfig = {}

-- Master switch. Off = no bays are bound, banking pays nothing and the HUD stays hidden. The race
-- loop is untouched, which is also how you A/B whether the meta is pulling its weight.
GarageConfig.Enabled = true

-- === Finding the bays =======================================================

-- Folder inside each plot Model holding the podiums, and the tag every real podium carries.
--
-- TAG *AND* PATH, for the same reason `PlotConfig` scopes plots that way: the `RoughSlot_*` demo
-- cars carried the identical `Floor`/`SlotIndex` attributes the real podiums do and differed only by
-- tag, and `workspace.Plot7` is a full tagged copy of Plot1 parked off the island.
GarageConfig.SlotsFolderName = "CarSlots"
GarageConfig.SlotTag = "CarSlot"

-- Attributes the map stamps on each podium. `Floor` gates which deck a bay is on.
GarageConfig.SlotIndexAttribute = "SlotIndex"
GarageConfig.SlotFloorAttribute = "Floor"

--[[ The storey every plot has before anybody buys anything, and the floor of the range
	`_discoverBays` will accept a podium on.

	IT USED TO BE A SET OF UNLOCKED FLOORS AND IT IS NOW A FLOOR, because "which decks exist" stopped
	being a global fact the day `UpgradeConfig.Floor2` made it a purchase. A plot in its locked state
	has one deck; a plot whose owner has paid for the second has two, and the difference is real
	geometry standing in Workspace. So the live answer is the `TopFloor` attribute on the PLOT
	(see `UpgradeConfig.PlotFloorsAttribute`), and this is only what a plot nobody has upgraded
	reads as. Setting it to 2 would put every lot on two decks for free — which is a perfectly good
	way to test the upstairs bays, and a terrible default to ship. ]]
GarageConfig.BaseFloor = 1

-- === What a bay is worth ====================================================
--[[ THE INCOME LADDER.

	    rate(tier) = Base * Growth^(tier - 1)      dollars per second, per car

	`Growth` is the load-bearing number and it was picked against this game's shape rather than
	copied off a curve. Idle-game math (Pecorella's *The Math of Idle Games*, and every AdVenture-
	Capitalist-derived economy since) is geometric in exactly this way — production goes up by a
	fixed ratio per generator tier while costs go up by their own, and the whole feel of the genre is
	which ratio wins. What that literature does NOT settle is the ratio itself, because it depends on
	how many of the thing you can hold and how hard each one is to get. Here:

	  • THE LOT HOLDS SIX. So the question a player actually asks is "is one tier up worth more than
	    the bay I'd give up?", not "how many can I stack". A world's top car (78/s) out-earns an
	    entire lot of six of that world's bottom car (12/s) six times over, which is an unmistakable
	    answer, while the bottom car is still 2/s of real money on an empty lot.
	  • THE RISK IS NOT LINEAR IN TIER. The top car does not spawn until tile 10 (`TrafficConfig`),
	    so a run that lands one is several times longer than one that lands a beater and every extra
	    second is a chance to wreck and lose the lot of it. 39x the income for maybe 6x the exposure
	    is generous on purpose: the downside is total (a wreck banks nothing at all), and a gamble
	    whose upside is merely proportional to its risk is one nobody takes twice.
	  • TOO STEEP KILLS THE BOTTOM OF THE LADDER. Widen the span much past 39x within a world and
	    banking a beater — which is most of what a new player can reach — stops registering as
	    progress at all. Flatten it and there is no reason to push past the first truck.

	=== WHY THE RATIO IS 1.688 AND NOT 2.5 =====================================================

	It is the same ladder; it has more rungs. A tier used to be a band of nine cars and there were
	five of them, so 2.5 per step spanned 2/s to 78/s. A tier is now ONE car (`WorldConfig`), world 1
	holds eight of them, and the span is unchanged — so the per-step ratio is whatever crosses it in
	seven steps, (78/2)^(1/7). Every number this file was tuned against still lands where it did:
	the bottom car is 2/s, the top is 78/s, a full lot of six top cars is 468/s.

	WORLDS STACK, SO THE LADDER KEEPS CLIMBING. Rungs are global — world 2 starts at tier 9 — and
	the curve is not re-based per world, which is the whole point of it: world 2's cheapest car
	(132/s) is worth more than world 1's dearest, and world 4's F5 lands around 4.6M/s. That is the
	progression, and it is why `TotalRungs` and not the live world's size sizes the table below.

	Rounded to whole dollars at the bottom of this file, because every one of these ends up in a
	label a player reads and "12.50/s" reads as a spreadsheet. Hand-edit `GarageConfig.Income.PerTier`
	after it is built if a tier wants a value the curve does not give it — nothing re-derives it. ]]
GarageConfig.Income = {
	--[[ === A PARKED CAR NO LONGER EARNS — 2026-09-28 ==========================================

		WHAT IT WAS. Every bay paid `rate(tier)` per second into a pending pot capped at
		`MaxBankedSeconds`, a mat in front of it paid the pot out, the HUD printed the lot's $/s, the
		AUTO COLLECT pass and upgrade swept the mats on a timer, and the WELCOME BACK screen paid what
		the bays held.

		WHAT IT IS. None of that runs. The dealership's income is its CUSTOMERS: people walk the lot,
		and a car they like earns a tip (`CustomerConfig.Tip`, priced off the car's market value).
		They keep coming while the owner is out driving, and the welcome screen pays a simulation of
		the tips missed while offline (`OfflineService`). The mats are hidden, the $/s line is gone,
		and AUTO COLLECT is off the shop (`PassConfig`).

		THE LADDER BELOW STAYS, AND IT IS STILL LOAD-BEARING. `rateOf` stopped being a payout and is
		now a VALUE SCALE: a car's sale price (`valueOf` = `SellSeconds` of it), the market's shelf
		prices and a tip are all still multiples of this curve, which is why none of them had to be
		re-tuned against a new one. Read "income" below as "value per second of it" where it matters.

		WHY. The rework turns the lot into a showroom that buyers make offers on, and a podium that
		prints money by itself makes every other decision about it — which car to put out, which to
		sell, whether to take an offer — worse than doing nothing.

		`Passive = true` puts every piece of the old income back, exactly: accrual, mats, labels, the
		sweeps, the HUD line and the welcome-back payout. ]]
	--[[ ON WHEN THE COLLECTOR IS (2026-11). The open-world rework's base is the reference's pen: cars
		on display print $/s and the number over each podium IS the reward for having stolen it.
		Customers stay, tipping off the bay's rate (`CustomerService` already reads both modes).
		`CollectorConfig` requires nothing at its top, so this cannot cycle. ]]
	Passive = require(ReplicatedStorage.shared.Configs.CollectorConfig).Enabled,

	Base = 2, -- tier 1 — the bottom car of world 1 — in dollars per second
	--[[ The top of world 1, i.e. what `Base` grows to over that world's eight rungs. Not read
		anywhere but `Growth` below; it is here because it is the number a designer actually holds an
		opinion about, and deriving the ratio from it is safer than the reverse. ]]
	WorldTop = 78,
	-- Set immediately after this table, from the two numbers above and world 1's rung count. A
	-- table constructor cannot read its own fields, and duplicating them here to spell the ratio
	-- out is exactly how the two drift apart.
	Growth = 1,

	--[[ Global multiplier over every bay. The home for the GDD §7 "2x Cash" gamepass and, later,
		for rebirth. Left at 1 and read on every payout rather than baked in, so switching it on is
		a live change and not a migration. ]]
	Multiplier = 1,

	--[[ A car sells for this many seconds of its own income.

		ONE NUMBER, NOT A SECOND TABLE — see header note 3. Four minutes is chosen so the two
		decisions it governs both come out right:

		  • KEEPING ALWAYS BEATS SELLING when you have a free bay. You are back to even in four
		    minutes and in profit forever after, so there is never a reason to sell a car you could
		    park, and the game never has to explain one.
		  • A FORCED SALE STILL PAYS. Bank a duplicate, or a worse car into a full lot, and four
		    minutes of that car's income is a real payout rather than a consolation — a Tier 5
		    duplicate is 18,750, which is more than most of a lot earns in that time.

		Push it past ~10 minutes and selling starts to beat parking for the low tiers, which turns
		the garage into a vending machine. ]]
	SellSeconds = 240,

	--[[ How much unclaimed income a bay will hold, seconds. 2 hours, straight out of GDD §4.

		It is the offline cap AND the online one, deliberately as one rule: "a bay holds two hours"
		is something a player can learn, and two rules that differ only by whether you were logged in
		is something they will discover as a bug. It is also the only thing making collection a verb —
		with no cap there is no reason to ever walk to a mat. ]]
	MaxBankedSeconds = 2 * 60 * 60,
}

--[[ The ratio, derived: whatever takes `Base` to `WorldTop` across world 1's rungs. Eight cars is
	seven steps, so it lands at ~1.688. Sized off WORLD 1 specifically and not the live world,
	because world 1 is what anchors the bottom of a ladder every later world extends upward. ]]
GarageConfig.Income.Growth = (GarageConfig.Income.WorldTop / GarageConfig.Income.Base)
	^ (1 / math.max(1, #WorldConfig.Worlds[1].Cars - 1))

-- === Banking a car ==========================================================
--[[ What happens to the car you just drove into the truck. Every branch pays out — header note 4.

	=== THE IDENTITY OF A CAR IS ITS BODY *AND* ITS COLOUR ====================================

	`Sedan12:6` — a red Sedan12 — is a different car to own than `Sedan12:3`, the black one. It used
	to be the body alone, and the change is worth understanding because it is the one modelling
	decision the whole collection hangs off:

	  • TWO CAMAROS IN DIFFERENT COLOURS ARE TWO CARS. That is the point. A player who likes a body
	    wants the set of it, and the palette is the only thing that distinguishes one steal of it
	    from the next, so making colour part of the identity is what turns a 43-car roster into a
	    collection worth going back out for.
	  • TWO CAMAROS IN THE SAME COLOUR ARE STILL ONE CAR. An exact repeat is indistinguishable on a
	    podium, so it sells (`SellDuplicates`). That keeps the sale branch — the only one that turns
	    a bank into cash — alive, and it caps the collection at 43 bodies x 15 colours rather than
	    letting it grow without limit.
	  • A LIVERIED BODY HAS EXACTLY ONE FORM. `PaintConfig.KeepLivery` locks those to `Stock`, so
	    every steal of one sanitises to the same key and the second is always a sale. That falls out
	    of the palette rather than needing a rule here.

	Tier is NOT part of it: two Tier 3s that are different models were always two different cars,
	and `Tier` only rides along because it is what the income is priced off.

	=== …AND ITS MUTATION, WHICH IS THE THIRD PART ==============================================

	`Camaro:6:Charged` is a different car to own than `Camaro:6`, by exactly the argument colour made
	above and one more that colour could not make: a mutated car is not merely a different-looking
	Camaro, it EARNS MORE (`rateOf`). Folding it into the plain key would mean banking a Charged
	Camaro when you already own a plain one sold the rare car for a duplicate's price, which is the
	worst possible ending for the rarest thing on the road.

	Two consequences fall out of that and both are intended:

	  • A MUTATED DUPLICATE IS STILL A DUPLICATE. Bank a second Charged Camaro in the same colour and
	    it sells, at the mutated price. The exact repeat is indistinguishable on a podium whether the
	    weather touched it or not.
	  • THE COLLECTION IS BIGGER THAN THE ROSTER, AGAIN. It was 43 bodies x 15 colours; it is now
	    that times six forms (plain, plus five mutations). The Index page still counts BODIES, which
	    is what keeps "how much of the roster have you seen" a question with a finite answer — see
	    `valueOfCollection` on why that number and the valuation deliberately disagree. ]]
GarageConfig.Banking = {
	--[[ === EVERY CAR GOES TO THE INVENTORY NOW — 2026-09-28 ===================================

		WHAT IT WAS. A banked car parked itself: the first free bay, or the worst bay if the new car
		out-earned it, or — for an exact repeat of a car already owned — straight to cash. The lot ran
		itself and the collection was where the overflow went.

		WHAT IT IS. Every car, from every source, is stored in the Cars Inventory under its own ID
		(`GarageConfig.carId`) and stops there. Duplicates are kept: two red Camaros are two cars, each
		with its own condition and its own place on the lot. The bays are a display the player
		arranges — from a podium's picker, or by carrying a car there from the inventory.

		WHY. The dealership rework turns the lot from an income machine into a showroom that buyers
		walk through and make offers on, and an offer is about ONE car the player chose to put out.
		A lot that rearranged itself behind the player's back, or a duplicate that turned into cash
		before anyone could sell it for more, would take that choice away.

		`SellDuplicates = true` and `AutoPark = true` together are the old behaviour, exactly. ]]

	--[[ Bank a car already in your COLLECTION and it sells instead, at `SellSeconds` of its rate.
		OFF SINCE 2026-09-28 (see above). Off now means the duplicate is KEPT as a car of its own —
		not, as it did before IDs, "collected" as nothing: an exact repeat stopped being
		indistinguishable the day each car got an ID and a condition of its own. The paragraphs below
		are what the flag does when it is on, and the last one is what "off" meant before IDs.

		"Already in your collection" means the body AND the colour, per the block above — a Camaro in
		a colour you do not have is new even when you own three other Camaros.

		Matched against the collection, not against the six bays: once a car you own can be sitting
		unparked, "already parked" stopped being the same question as "already owned", and the lot
		was the wrong one to ask. This is the only branch that still turns a car into cash.

		Off = an exact duplicate is a no-op that pays nothing. It cannot mean "parks in a second bay"
		— that is what owning the same body in two COLOURS now does, and two identical cars on two
		podiums is a lot the dealership screen cannot tell apart. ]]
	SellDuplicates = false,

	--[[ Park a new car on the lot by itself: the first free bay, or — with `UpgradeWorstBay` — the
		worst one. OFF SINCE 2026-09-28 (the block at the top of this table): every car stops in the
		inventory and the player places it. On = the old self-arranging lot, exactly, which is also
		why `UpgradeWorstBay` is left as it was rather than switched off with it — it only ever runs
		behind this flag, so turning this back on restores both halves together.

		IT DOES NOT TOUCH THE CARRY. A source that `CarryConfig.carries` still goes into the player's
		hands whatever this says; since the same date the bank is no longer one of those sources. ]]
	AutoPark = false,

	--[[ Full lot, and the new car is a HIGHER tier than the worst one parked: the new one takes that
		bay and the car it displaces goes BACK TO THE COLLECTION. Off = the new car just joins the
		collection unparked, and the lot only ever changes from the dealership screen.

		Leaving it on is what keeps the meta working for a player who never opens that screen: a lot
		of Tier 1s still becomes a lot of Tier 5s on its own. What changed with the collection is that
		the displaced car is no longer SOLD — you keep it, so this branch pays no cash. That is the
		one deliberate economy nerf here; if banking starts to feel thin, this is the first number to
		look at.

		Ties do not swap. Trading a Tier 3 for a different Tier 3 gains nothing, and shuffling the
		lot for no income change reads as the game losing your car.

		Only consulted while `AutoPark` is on; see that flag. ]]
	UpgradeWorstBay = true,
}

-- === The car on the podium ==================================================
--[[ The display car is a STRIPPED CLONE OF THE ROSTER BODY, not a car.

	`Workspace.CarSystem.<Body>` is a full CarBones rig — 311 instances of chassis, constraints,
	seats, sounds and the whole stock vehicle script suite. Six of those on each of six plots is
	11,000 instances of working vehicle standing perfectly still. So only the `Body` model is cloned
	(about 50 parts: the dress, the four wheel groups), every joint and constraint in it is destroyed,
	and every part is anchored.

	DESTROYING THE JOINTS IS NOT OPTIONAL AND IS NOT TIDINESS. A weld cloned out of a rig still points
	at the ORIGINAL car's part — the clone is welded to the donor, across the map — so writing a CFrame
	on it drags the pristine template instead of moving the copy. That is a bug this repo has already
	paid for once; see the memory note on weld references surviving unparenting.

	NOT SCALED. The podiums are placed at `ScaleTo(0.85)` because six full-size bays do not fit on
	floor 1, but the CAR is 1:1 — a 9.82 x 21.67 body on the 12.70 x 24.60 top deck it actually stands
	on, which is 1.44/side and 1.47/end. (`docs/MapLayout.md` §4.1 quotes 1.99/2.40; that is measured
	off the 13.94 x 26.32 BASE slab, which is the podium's footprint and not the surface under the
	wheels.) Scaling the car too would leave it rattling around in the middle of its own podium. ]]
GarageConfig.Display = {
	-- The roster's NAME rather than its place: it is relocated to ServerStorage as the server boots
	-- (`RelocationService`), so it never reaches a client at all, and `Modules/CarRoster` is what
	-- resolves it. Fine either way, because the server builds the display cars and Roblox replicates
	-- the result like any other Workspace geometry.
	RosterFolderName = "CarSystem",
	-- The child of a roster car holding the visual dress.
	BodyFolderName = "Body",
	-- Stripped from the clone: it is the invisible physics hull, and a parked car has no physics.
	HitBoxName = "HitBox",

	-- Name given to the display car under its podium, so the bay can be found and cleared again.
	CarName = "DisplayCar",

	--[[ Studs the car's lowest bodywork is lifted above the podium's top deck.

		Zero: the wheels sit ON the deck. Unlike `RaceConfig.SpawnClearance` there is no suspension
		to settle here and nothing is ever handed to the solver, so a clearance would just be a car
		hovering. Kept as a dial because a redress whose wheel wells are modelled tight can read as
		sunk, and lifting one body by 0.05 is cheaper than re-rigging it. ]]
	Lift = 0,

	--[[ Turn the parked car off square, degrees. A CEILING, NOT A SETTING — see below.

		The bays run in two straight lines against the walls (`MapLayout` §4.2) and a showroom of cars
		all facing dead ahead reads like a car park. A few degrees of yaw is the standard dealership
		trick: you see a corner of the car rather than its nose, which is the angle every press photo
		of a car is ever taken from.

		WHAT ACTUALLY GETS APPLIED IS PER CAR. The deck is 12.70 x 24.60 at the authored 0.85 scale
		and the roster is not one size, so `CarDisplay.fitYaw` steps down from this value until the
		rotated footprint fits, and this is the most any car will be turned rather than the amount
		every car is turned. Set it to 0 to park the whole showroom square.

		FIVE, BECAUSE THE CEILING HAS TO BE ONE THE WHOLE ROSTER CAN REACH. This was 12, and against
		the real deck that fits out to 48 of the 49 bodies at 12, 11, 10, 9, 8, 7 and 6 degrees
		depending on how wide each one is — a row of podiums where every car is crooked by a different
		amount, which reads as sloppy placement rather than as a pose. At 5 every body but one takes
		the full angle, so the line is uniform, and the widest of them (`Pantera GT5`, 10.48) still
		leaves 0.21 studs of deck a side. Six is the last angle that is also uniform and leaves 0.04,
		which is not enough to survive the next redress. The exception either way is the 12.90-wide
		`Sian`, which is wider than the deck and parks square at any ceiling. ]]
	Yaw = 5,

	-- Shadows off. A parked car casting six shadows into a glass showroom is a real cost for
	-- something nobody looks at, and the roster's bodies are authored with CastShadow off anyway.
	CastShadow = false,
}

-- === The Not For Sale sign ==================================================
--[[ What stands over a car its owner has taken off sale (`InventoryConfig.Keys.NotForSale`), so that
	anyone walking the lot — the owner, a visitor, and soon a buyer — can see which cars are on offer
	without opening anything.

	A PLACEHOLDER, deliberately (2026-09-28: "use placeholders"). A red board with white words in
	the kit's typeface, built in code, on a BillboardGui hung off the display car. It is a
	BillboardGui and not a SurfaceGui on a prop so that it reads from any side of a podium without
	anybody having to decide which way a sign faces on bays the map authors at every angle — the
	question a real prop will have to answer when the art arrives.

	HUNG OFF THE DISPLAY CAR, so it goes when the car goes: `_clearBay` destroys the car and the
	sign with it on every rebuild, and there is no second thing to keep in step.

	`Enabled = false` hides the sign and nothing else — the car is still off sale, which is the
	honest A/B for whether players can read the lot without it. ]]
GarageConfig.NotForSaleSign = {
	Enabled = true,
	Text = "NOT FOR SALE",
	--- Studs. Wide and short: one line of text a car's width across, so it reads as a sign on the
	--- car and not a banner over the bay.
	Size = Vector2.new(7, 1.6),
	--- Studs above the top of the deck. Clears the roof of the tallest body on the roster (~5.5)
	--- with room for the sign's own height; measured by eye against the SUV bodies, not derived.
	Height = 7.5,
	--- Past this it is not drawn: a lot you are not standing on does not need its signs legible.
	MaxDistance = 90,
	Panel = Color3.fromRGB(196, 44, 44),
	TextColor = Color3.new(1, 1, 1),
}

-- === Collecting =============================================================
--[[ Walk onto the mat in front of a bay and that bay's pending cash is yours.

	The mat is AUTHORED, like the dealership sign and the spawn pad: `Collect/CashButton` and its
	`CashButtonGui/CollectedCash` label are built into every podium. This service only writes text
	into it and watches it for a foot. Same split, same reason — nothing on a hot path should be
	constructing UI it could instead be filling in.

	PER BAY RATHER THAN ONE LOT-WIDE BUTTON, because the geometry already says so: there is a mat in
	front of every podium, in the aisle, facing the car. Walking your own showroom collecting from
	each car in turn is the verb the map was built for. ]]
GarageConfig.Collect = {
	-- Names inside the authored podium. Changing one means changing it in the CarSlot source model
	-- too — they are the two halves of one contract.
	ButtonName = "CashButton",
	GuiName = "CashButtonGui",
	LabelName = "CollectedCash",

	--[[ Seconds between one player's collections from the SAME bay.

		Not an anti-exploit — the payout is `now - collectedAt` so a second collection a frame later
		is worth a frame of income, and spamming it gains nothing. It exists so the label does not
		flicker to $0 and back while you stand on the mat, and so the collect effect has time to
		read. ]]
	Cooldown = 0.5,

	-- Below this, standing on the mat does nothing at all — no payout, no label flash. Stops a bay
	-- you collected two seconds ago from firing again as you walk off it.
	MinPayout = 1,

	-- Text on a mat whose bay is empty. Deliberately an invitation rather than a dash: an empty bay
	-- is the thing the whole run loop is trying to fill.
	EmptyText = "EMPTY BAY",

	--[[ THE AUTO COLLECT GAME PASS (`passes.AutoCollect`, `ShopConfig`, `PassService`).

		WHAT IT ACTUALLY DEFEATS IS `Income.MaxBankedSeconds`, NOT THE WALKING, and that is worth
		being precise about because the walking is what the store description sells. Income is
		derived from a per-bay collect stamp and capped at two hours of it, so a lot left alone stops
		earning at the two hour mark however many bays are on it. Tapping every podium is the chore;
		losing everything past the cap is the cost. A sweep on a short interval removes both, and it
		needs no new economy maths at all because it is the same `_collect` a foot on the mat runs.

		THE SWEEP IS A LOOP OVER `collectAll` AND NOTHING ELSE. No second payout path, no second
		formula, no separate rate. An automatic payout and a manual one are therefore worth exactly
		the same by construction rather than by two pieces of arithmetic agreeing — which is the same
		argument `getPending` makes about the WELCOME BACK screen's number.

		`Interval` IS FAR UNDER THE CAP AND THAT IS THE ONLY THING IT HAS TO BE. Thirty seconds
		against a two hour ceiling means a bay is never within two hundred sweeps of filling up, so
		the cap can never bite an owner while they are online. It is not a payout RATE — the money is
		derived from elapsed time either way, so a slower sweep pays exactly as much in larger
		lumps — which means this number is chosen entirely for feel and for cost: often enough that
		the cash counter visibly ticks up while the player is stood on their forecourt, rare enough
		that six bays are not writing the profile every frame.

		WHAT IT DOES NOT DO IS BEAT THE CAP WHILE THE PLAYER IS OFFLINE. There is no server running a
		sweep for somebody who is not in a session, so an owner who logs off still banks at most
		`MaxBankedSeconds` before their next join. That is deliberate rather than missed: uncapping
		offline income is the thing `products.OfflineBoost` sells a multiple of, and a pass that
		quietly did it would gut a product two rungs cheaper. The store description says "out on a
		run" for this reason.

		BAYS ARE STILL COLLECTED ONE AT A TIME AND STILL FLOOR AT `MinPayout`, so a sweep of six
		untouched bays writes nothing and pays nothing. An owner standing still on a lot of empty
		bays costs one table walk per interval and no profile write at all. ]]
	Auto = {
		--- The `PassConfig` key. `PassService:owns(player, Key)` is the whole ownership question.
		Key = "AutoCollect",
		--- Seconds between sweeps. See above: chosen for feel, not for rate.
		Interval = 30,
	},
}

-- === The HUD ================================================================
--[[ The cash counter, bottom left.

	NOTHING ABOUT HOW IT LOOKS IS IN HERE. The pill is authored art — `MainUI.HUD.Cash`, an
	ImageButton with the coin baked in — and its two readouts are TextLabels over the top of it
	(`TextLabel` for the balance, `Rate` for the income line). Position, size, colour and font all
	live in the place, where they can be dragged in the Explorer; this block is only the timings and
	the behaviour switches `GarageHudController` reads. Anything visual you want to change, change it
	on the instance.

	It used to be drawn in code, kit colours and pixel offsets and all, as a stand-in until the art
	landed. It has landed, so those keys are gone rather than left here to be edited by someone who
	then wonders why nothing moved.

	TEXT OVER ART, NOT BAKED INTO IT: the number changes and a PNG cannot. `UIAssets` states that
	rule for the whole kit, and the driving HUD makes the same split with `GaugeBase.png`.

	READ OFF A PLAYER ATTRIBUTE, NOT A REMOTE. `GarageService` mirrors the profile's cash onto the
	Player, Roblox replicates it, and the label watches it change. Same reasoning `PlotConfig` gives
	for plot ownership: the profile stays the source of truth, the attribute is the broadcast. ]]
GarageConfig.Hud = {
	Enabled = true,

	-- Hidden during a race. The driving HUD owns the screen then, and a cash counter is noise on a
	-- beat where the player is reading traffic.
	HideDuringRace = true,

	--[[ Seconds the counter takes to roll from its old value to its new one.

		It rolls rather than snapping because a collection is the payoff for a whole run and a number
		that changes between frames is a number nobody saw change. Kept short and eased per the
		effect-intensity note — the drama belongs to the size of the number, not to how long it takes
		to arrive. ]]
	RollTime = 0.45,

	--[[ The punch the BALANCE NUMBER gives when cash arrives: how long the whole thing takes (out and
		back), and how far it grows at the top of it.

		Larger than the 1.06 this was while the whole pill punched. That figure was set against the
		1.05 a button gives a hover — fair when the pulse moved the plate the cursor touches, but now
		only the digits move, and 6% of a ~35px number is 2px nobody sees. 15% of the same number is
		still less travel than the old 6% of the pill. One knob if it wants dialling back. ]]
	PulseTime = 0.22,
	PulseScale = 1.15,
}

-- === Profile keys ===========================================================
--[[ Where a garage lives in the player profile. Mirrored into `Data/Components/Settings` TEMPLATE —
	these names and that template are the two halves of one contract.

	`Cars` IS AN ARRAY, and that is a datastore decision rather than a modelling one: a table keyed by
	bay number with a gap in it (bays 1, 2 and 5 filled) round-trips through JSON as a dictionary with
	string keys, and comes back as something the code that wrote it does not recognise. A dense array
	always survives. Which bay an entry stands on is the `Bay` FIELD, never its array position, so
	removing a car shifts array indices and moves nothing. ]]
GarageConfig.Keys = {
	Cash = "Cash",
	Garage = "Garage",
	--[[ array of { Body: string, Tier: number, Paint: number, Mutation: string?, Collected: number,
		Bay: number }

		`Mutation` is absent on an ordinary car and on every entry written before the weather existed,
		which are the same thing as far as anything reading this is concerned — see `carKey`. ]]
	Cars = "Cars",

	--[[ Array of CAR IDS — `"Sedan12:6#4"` — one per car the player owns. See "Car ids" below: an
	entry with no `#serial` is a car banked before IDs existed, and its key IS its ID. What follows
	was written when this held keys, and still describes how the key part of each ID reads.

	Array of CAR KEYS — `"Sedan12:6"`, body and colour — one per car ever banked, never removed.

		It held bare body names until colour became part of a car's identity (see `Banking`). An entry
		with no `:<paint>` on it is one of those, and is read as its colour out of `Paints` below; see
		`GarageConfig.parseCarKey`. Nothing rewrites old profiles — they are read correctly for as long
		as they exist, and pick up the new spelling the first time anything writes the collection. ]]
	Owned = "Owned",

	--[[ Car XP: a MAP of body name -> total XP, not an array.

		The array rule two paragraphs up is about SPARSE arrays specifically — a table keyed by
		number with a gap in it comes back from the datastore as a dictionary with string keys. A
		table that was always keyed by string round-trips unchanged, so the natural shape is the safe
		one here: `{ Sedan12 = 4820 }`.

		XP is stored and LEVEL is derived (`RewardConfig.levelFor`), the same split as the garage's
		own income — one number is state, everything else is a function of it, so a ladder that gets
		retuned re-levels every existing profile instead of stranding it. ]]
	Levels = "Levels",

	--[[ LEGACY, AND READ-ONLY FROM HERE ON. A MAP of body name -> `PaintConfig` palette index,
		`{ Charger = 6 }`, from when a player could own one Charger and it had one colour.

		Colour is now part of the car's identity and rides in the `Owned` key and on the `Cars` entry
		(`"Charger:6"`), so there is nowhere for a second colour of the same body to go in a table
		shaped like this — which is exactly why it stopped being the store. NOTHING WRITES IT ANY
		MORE. It is kept because it is the only place an already-saved profile records what colour its
		cars are, and `GarageService` reads it to fill in the paint of an entry written before the key
		carried one. Deleting this key repaints every existing player's collection to stock.

		AN INDEX, NOT A COLOUR, because a `Color3` cannot go in a datastore at all — PaintConfig's
		header has the rest of that reasoning, including why the palette is append-only the moment
		anything is written here. ]]
	Paints = "Paints",

	--[[ What is true of ONE car and not of every copy of its model: a MAP of car ID -> record,
		`{ ["Camaro:6#17"] = { Condition = 0.62 } }`. See "Car ids" below for what an ID is.

		A MAP, and string-keyed for the datastore reason `Levels` is. ABSENT MEANS DEFAULTS, and that
		is load-bearing: every car banked before this key existed has no record, and has to read as a
		car in full condition that is for sale — which is what `GarageService.getCarData` answers for
		a missing one. So a record is only ever written when a field departs from its default, and an
		old save needs no migration to be read correctly.

		`GarageService` owns every write, and prunes a car's record in the same call that sells it. ]]
	CarData = "CarData",

	--[[ The next serial `GarageService` will mint a car ID with. A counter and not "one more than the
		highest ID in the collection", because the collection shrinks: a serial derived from what is
		left would hand a new car the ID of one just sold, and anything still holding that ID — a
		`CarData` record, a favourite, a buyer's offer — would quietly attach itself to the wrong car.
		Only ever goes up. Absent reads as 1. ]]
	NextCarSerial = "NextCarSerial",

	--[[ THREE KEYS IN THIS TABLE ARE NOT LISTED HERE ON PURPOSE, and all for the same reason: what
		each one MEANS is decided entirely in another config, and a key name repeated in two configs
		is a key name that eventually disagrees with itself.

		    Garage.Upgrades   UpgradeConfig.ProfileKey       the four tiles on the forecourt billboard
		    Garage.BayLevels  UpgradeConfig.Bay.ProfileKey   the upgrade kiosk on each podium
		    Garage.Carrying   CarryConfig.ProfileKey         the car in the player's hands, unparked

		`GarageService` reads and stores all three (`_upgrades`, `_bayLevels`, `getCarriedCar`) because
		it owns the profile's `Garage` table. What may CHANGE one of them lives elsewhere: an upgrade
		is `UpgradeService`'s to sell, and a carry is begun by a bank and ended by a podium press. ]]
}

-- The Player attributes the HUD reads. `Cash` mirrors `Keys.Cash`; the profile stays authoritative.
--
-- `Rate` is the whole lot's dollars per second, published alongside it. It is not needed to make the
-- money work — the HUD could not compute it, though, because a client has no idea what is parked on
-- its own podiums — and it is the one number that makes the ladder legible while it is being tuned:
-- park a Tier 5 and watch it jump. One extra attribute write per change to the lot.
GarageConfig.CashAttribute = "Cash"
GarageConfig.RateAttribute = "CashPerSecond"

--[[ DEALERSHIP VALUE: what everything this player owns would sell for, whole dollars.

	`GarageConfig.valueOfCollection` is the sum and its comment is where the definition lives — the
	short version is that it values EVERY CAR KEY, so it is not the number the Index page counts.

	AN ATTRIBUTE AND NOT A REMOTE, for the reason the block above gives for `Rate`: a client cannot
	compute it. The collection is on `OwnedAttribute` and a client could in principle sum it itself,
	but only by holding its own copy of the price ladder and agreeing with the server about every
	rung forever — and the first time those drifted, the number on the screen would be wrong in a
	way nothing would catch. One write per change to the collection is cheaper than that contract.

	Published for EVERY player rather than just the local one, deliberately: attributes replicate, so
	a visitor standing on somebody else's forecourt can read what that lot is worth. That is the
	whole point of a valuation — it is a number you show people. ]]
GarageConfig.ValueAttribute = "DealershipValue"

--[[ THE CONDITION OF EVERY CAR THAT IS NOT IN PERFECT SHAPE, as "Camaro:6#17=0.62,Civic:1#3=0.4"
	(2026-09-28). A car missing from it is in full condition, which is nearly all of them.

	IT EXISTS SO A SCREEN CAN PRICE A CAR, and for no other reason: a car's market value multiplies
	in its condition (`MarketValueConfig`), the condition lives in `Garage.CarData` on the server, and
	a client that printed the model's price for a battered car would be advertising a number the
	sell lot then refuses to pay. `GarageConfig.decodeConditions` is the one reader.

	`=` because an ID already uses the colon and the hash, and the comma splits entries. ]]
GarageConfig.ConditionAttribute = "CarConditions"

--- The other half of `ConditionAttribute`: car ID -> condition, for the cars that have one recorded.
function GarageConfig.decodeConditions(raw: unknown): { [string]: number }
	local out = {}
	for _, entry in GarageConfig.split(raw) do
		local id, value = string.match(entry, "^(.+)=([%d%.]+)$")
		local number = tonumber(value)
		if id and number then
			out[id] = number
		end
	end
	return out
end

--[[ The other two broadcasts, both strings because attributes cannot hold tables, and both
	comma-separated rather than JSON because they stay readable in the Explorer while this is being
	built (43 car keys is about 500 characters).

	`OwnedAttribute` is the collection — "Sedan06:1,Sedan12:6,Sedan12:3", i.e. car KEYS, so the two
	Sedan12s in it are the red one and the black one. Its name and its comma format are not new: the
	Index page has been reading exactly this attribute since before anything wrote it.

	`LotAttribute` is which bay each parked car is on — "1:Sedan12:6,4:Sports16:1" — so the dealership
	screen can mark a car as already parked, and mark WHICH bay, without a round trip. The world
	already shows this (the car is standing on the podium); the attribute is for the screen.

	=== A COMMA IS THE ONLY SEPARATOR, AND WHITESPACE IS NOT ONE ===============================

	READ THIS BEFORE WRITING A PARSER FOR EITHER. Body names contain SPACES — `Golf GTI` and
	`Model 3` are both world 1 cars — so the obvious `string.gmatch(raw, "[^,%s]+")` splits half the
	roster into two entries each and quietly loses them. Split on "," and trim; `GarageConfig.split`
	below is that, and every reader should use it rather than spelling a pattern out again.

	It also means a body name may never contain a comma or a colon. Nothing on the roster does, and
	`carKey` would be ambiguous if one did. ]]
GarageConfig.OwnedAttribute = "CarsFound"
GarageConfig.LotAttribute = "GarageLot"

--[[ The third, and the only one a client reads to change how the game PLAYS rather than to draw a
	screen: car levels, as "Sedan12:3,Sports16:2".

	`StealController` reads it the moment a steal lands, to scale the top speed of the body it just
	took (`RewardConfig.speedScaleFor`). That is why it is an attribute and not a remote — the answer
	has to be already on the client when the car changes under the player, not a round trip later.

	Only bodies above level 1 appear, so a fresh player's is the empty string; the encoding lives in
	`RewardConfig` beside the ladder that defines what a level is. ]]
GarageConfig.LevelsAttribute = "CarLevels"

-- === Choosing what goes on a bay ============================================
--[[ The dealership screen (`UIController/Pages/Dealership`), opened from a podium.

	IT IS OPENED FROM THE WORLD, NOT FROM THE HUD, which is why there is a prompt here and no button
	attribute anywhere. The bays are already the thing you walk around collecting from; pressing E on
	the one you are standing at means the screen never has to ask which bay you meant, and the answer
	can never be wrong. ]]
GarageConfig.Picker = {
	Enabled = true,

	--[[ === A TRACE FOR THE DEAD-PROMPT BUG — 2026-09-28 ======================================

		The podium prompts sometimes stop answering — neither a place nor a pick-up — with nothing in
		any log, and `ProximityPromptService.Enabled` reads true while it happens, so it is not the
		Driver-script leak `DriveController._guardPrompts` repairs. What is left are three things
		that fail silently: another prompt winning the E key (one prompt per key is drawn), the key
		press being eaten before any prompt sees it (a focused TextBox, a leaked input binding), or
		the press arriving and being dropped by a quiet early return.

		On, this logs enough to tell those apart: every prompt shown, hidden and triggered on the
		client; on every E press, whether the engine had already processed it, which TextBox had
		focus and which prompts were on screen (`DealershipController._tracePrompts`); and which
		branch every podium press took on the server (`GarageService._claim`) and every picker open
		on the client. A DIAGNOSTIC, NOT A FEATURE: off once the cause is found. ]]
	DebugPrompts = true,

	--[[ THE DESYNC HEAL (2026-09-30, `GarageService._onBayPromptPressed` has the whole story): a podium
		press the server's frozen copy of the character is too far away for re-syncs network ownership
		to where the client is and runs the press. False = the press is simply lost, as before. ]]
	HealDesync = true,

	-- The ProximityPrompt raised on each podium deck. `ObjectText` gets " <n>" appended per bay.
	PromptActionText = "Change Car",
	PromptObjectText = "Bay",
	PromptHoldDuration = 0,
	--[[ Studs from the podium's CENTRE. 16 since 2026-10-07 (was 22): the kit prompt card is big and
		opaque, and at 22 it came up over the car while you were still stepping back to look at it.
		The podiums measure 13.8 to 14.9 studs from centre to far corner, so 16 still reaches from
		anywhere along a podium's edge. ]]
	--- 2026-10-20: WAS 16 ("increase the prompts at the bays ... by a little"). Not measured against the gap
	--- between neighbouring podiums: if two bays' prompts light from one spot, bring this back down.
	PromptMaxDistance = 20,

	--- E at an EMPTY bay, where it opens the picker to choose what goes there.
	EmptyActionText = "Park a Car",

	--[[ === BACK TO ONE PLAIN E PROMPT — 2026-10-08 ===========================================
		WAS the glass card (`GlassPromptController`): three rows on one podium — E Pick Up (a hold),
		F Change Car, X Take Off Sale. Leaf, on seeing it: "this isn't good, the normal E prompt is
		better", and the owner's call: Roblox's own prompt, one key, and E does the obvious thing —
		holding a car, it PLACES it; at an empty bay it opens the PICKER; at a car it PICKS IT UP, a
		plain press, no menu. Changing the car is pick up then place; the workshop's screen is on its
		kiosk sign; on/off sale is in the inventory screen. So `Glass = false` builds one stock prompt
		per podium and no `Option` or `Sale` prompt at all, and other players' podium prompts are
		switched off on each client (`DealershipController`, off `OwnerAttribute`). `true` is the glass
		card with its three rows, exactly as it was. ]]
	Glass = false,
	--- Who a podium's prompt belongs to, as a UserId; every other client switches it off.
	OwnerAttribute = "BayOwner",
	--- Tag on every podium prompt, so the clients can find them as they stream in.
	PromptTag = "BayPrompt",

	--[[ HOLD E TO PICK UP (2026-10-07). Taking a car off a podium used to be three steps: press the
		podium, CHANGE CAR, CLEAR BAY ("should just be e to place and hold e to pickup"). Now E at a
		car with empty hands is a HOLD, and the car comes off the bay into your hands (its hotbar slot,
		or the inventory when the bar is full). The menu it used to open moved to `Option`. ]]
	PickUp = {
		Enabled = true,
		--- 0 since 2026-10-08 (was 0.5): "clicking E just picks it up". See `Glass`.
		HoldDuration = 0,
		ActionText = "Pick Up",
	},

	--[[ THE SECOND PROMPT on every podium: the menu for the car standing there (Customize in the
		workshop, `PromptActionText` elsewhere), shown under E on the same glass card while E is Pick
		Up. Its own key because two prompts sharing one key on one podium is the failure
		`LobbyCarService._wireEntry` measured: the engine draws one of them.

		THE PAD KEY IS R2 BECAUSE EVERY FACE BUTTON ON FOOT IS SPOKEN FOR: A jumps, X is every
		proximity prompt (E's pad key), B is back, and Y presses Play from anywhere
		(`MainUI.HUD.Play`'s `GamepadKey`), so Y here would start a race from a podium. R2 is the
		throttle only while seated, and L1/R1 cycle the hotbar. ]]
	Option = {
		Name = "BayOptionPrompt",
		KeyboardKey = Enum.KeyCode.F,
		GamepadKey = Enum.KeyCode.ButtonR2,
	},

	--[[ THE THIRD ROW (2026-10-08, the owner): put the car on this podium on or off sale without opening
		a screen. X on a keyboard; L2 on a pad, which on foot is free for the reason `Option` gives
		(it is only the brake while seated). Shown only with a car on a showroom podium and empty hands
		— never in the workshop, where nothing is ever for sale. The caption says what a press DOES:
		`TakeOffText` while the car is for sale, `PutOnText` while it is not. The press is the same
		`setCarFlag` the inventory's star row uses, so the NOT FOR SALE sign and any buyer waiting on the
		car follow exactly as they do from there. `Enabled = false`: no third row. ]]
	Sale = {
		Enabled = true,
		Name = "BaySalePrompt",
		KeyboardKey = Enum.KeyCode.X,
		GamepadKey = Enum.KeyCode.ButtonL2,
		PutOnText = "Put On Sale",
		TakeOffText = "Take Off Sale",
	},

	--[[ Seconds between one player's bay changes. Same shape and same reason as
		`RaceConfig.EnterRequestCooldown`: the remote is a client caller, and a rebuild of the lot
		clones a car body per bay, so a mashed picker is real server work. Well under how long the
		page's open tween takes, so nobody who is not scripting it can feel it. ]]
	Cooldown = 0.35,
}

-- Seconds between label redraws. Purely cosmetic — the money is derived from a clock, so this only
-- decides how often a mat's number ticks up. One second is what a per-second income wants to look
-- like; faster just costs more property writes for a digit nobody reads.
GarageConfig.LabelInterval = 1

-- === Derived ================================================================
--[[ The per-tier rate table, built from the curve above so the two can never disagree — same
	pattern, and the same reason, as `TrafficConfig.Bodies` being assembled at the bottom of its file.

	EVERY RUNG IN EVERY WORLD IS PRICED, not just the live world's. It used to be built from
	`TrafficConfig.Tiers`, which is now the live world alone — and a garage full of world 1 cars does
	not empty out the day world 2 goes live. A parked car has to keep paying whatever world you are
	driving in, so the table is sized by `WorldConfig.TotalRungs` (29 today) and the live world only
	decides which of those rungs you can currently ADD to.

	Rounded to whole dollars: every one of these ends up in a label. ]]
GarageConfig.Income.PerTier = {}
do
	for tier = 1, WorldConfig.TotalRungs do
		GarageConfig.Income.PerTier[tier] =
			math.max(1, math.round(GarageConfig.Income.Base * GarageConfig.Income.Growth ^ (tier - 1)))
	end
end

--[[ Which tier a body belongs to, by name. The steal reports both, and this is what checks the pair
	is real — a client claiming an `M5` payout for a `Civic`, or a body on no ladder at all, is
	rejected rather than paid.

	ALL FOUR WORLDS, for the same reason `PerTier` prices all 29 rungs: a car you own is a car whose
	tier has to resolve forever, and the collection outlives the world it was caught in. It is a
	straight alias of `WorldConfig.TierOfBody` — the roster is authored once, there.

	It bounds the claim; it cannot verify it. Traffic is entirely client-sided, so there is no car on
	the server to check against — the same accepted gap `StealService` documents, and the same fix
	(server-rolled spawn tokens) closes both. What this DOES stop is the cheap version: you can no
	longer name a top-tier payout while parking whatever body you like on the podium. ]]
GarageConfig.TierOfBody = WorldConfig.TierOfBody

-- === Car keys ===============================================================
--[[ A car is a body and a colour, and this is how the pair travels: through the datastore, along an
	attribute, and over the remote the dealership screen fires. See `Banking` for why colour is part
	of the identity at all.

	ONE STRING RATHER THAN A TABLE, for three separate reasons that happen to agree: a dense array of
	strings is the shape the datastore round-trips without surprises (the same rule `Keys.Cars`
	follows), an attribute cannot hold a table at all, and a key can be compared with `==` — which is
	what makes "do I already own this?" a set lookup instead of a two-field scan. ]]

--- ("Sedan12", 6) -> "Sedan12:6". A nil or unusable paint is recorded as the authored livery.
function GarageConfig.carKey(body: string, paint: number?, mutation: string?): string
	local index = tonumber(paint)
	if not index or index ~= index or index % 1 ~= 0 or index < 1 then
		index = PaintConfig.StockIndex
	end

	--[[ THE MUTATION IS A SUFFIX AND ONLY WHEN THERE IS ONE, which is what makes this change cost no
		migration at all: an ordinary car's key is byte-for-byte what it was before mutations existed,
		so every profile ever written still parses, still matches and still values the same. Only a
		car the weather touched grows a third field.

		Sanitised through `WeatherConfig`, so a key can never name a mutation this build does not have
		— which would be a car nothing in the game could price, park or sell. An unknown one falls
		back to the plain two-field key, i.e. to the same car without its weather. ]]
	local mark = WeatherConfig.sanitize(mutation)
	if mark then
		return string.format("%s:%d:%s", body, index, mark)
	end
	return string.format("%s:%d", body, index)
end

--[[ The other half. Returns `(body, paint, mutation)`, or nil for anything that is not a key at all.

	A KEY WITH NO COLOUR ON IT IS A LEGACY ENTRY, not an error: `Owned` held bare body names before
	colour was part of a car's identity, and those come back as `("Sedan12", nil, nil)` so the caller
	can fill the paint in from `Keys.Paints`. That is the whole of the migration and it happens on
	read, so a profile nobody touches again is still read correctly.

	A KEY WITH NO MUTATION ON IT IS AN ORDINARY CAR, which is nearly all of them, and needs no
	migration of any kind — see `carKey` on why the third field is a suffix rather than a slot.

	=== THE THREE-FIELD FORM IS TRIED FIRST, AND IT HAS TO BE =================================

	The two-field pattern's body capture is GREEDY, so it splits at the LAST colon: run it against
	"Camaro:6:Charged" and it does not match at all (the tail is not digits) — but run the greedy
	pattern against a hypothetical "Camaro:6:12" and it would happily return `("Camaro:6", 12)`, a
	body that does not exist. Matching the mutation form first, and anchoring its third field to
	`%w` rather than to anything, is what keeps the two unambiguous.

	The trailing capture is `[%w_]`, which is exactly what a mutation key is allowed to be — see the
	warning on `WeatherConfig.Mutations.Key`. Anything else falls through to the two-field read and
	the car keeps its colour and loses its weather, which is the safe direction. ]]
function GarageConfig.parseCarKey(key: unknown): (string?, number?, string?)
	if type(key) ~= "string" or key == "" then
		return nil, nil, nil
	end
	-- A car ID parses as the car it is a copy of; see `splitCarId` for why the serial is a suffix.
	key = GarageConfig.splitCarId(key)

	local body, paint, mutation = string.match(key, "^(.*):(%d+):([%w_]+)$")
	if body and body ~= "" then
		return body, tonumber(paint), WeatherConfig.sanitize(mutation)
	end

	body, paint = string.match(key, "^(.*):(%d+)$")
	if body and body ~= "" then
		return body, tonumber(paint), nil
	end
	return key, nil, nil
end

-- === Car ids ================================================================
--[[ A KEY SAYS WHAT A CAR IS; AN ID SAYS WHICH ONE. `"Camaro:6"` is a red Camaro, and
	`"Camaro:6#17"` is the seventeenth car this player was handed, which happens to be a red Camaro.

	=== IT WAS THE KEY ALONE UNTIL 2026-09-28 ===================================================

	WHAT IT WAS. The key was the identity, so an exact repeat (same body, colour and mutation) could
	not exist: `Banking.SellDuplicates` cashed it in at the truck because there was nowhere to put it.

	WHAT IT IS. The dealership rework keeps every banked car in the inventory, duplicates included,
	and gives each car state of its own (`Keys.CarData`: the condition it banked in, whether it is for
	sale). Both need a name for ONE car, which a key cannot be — two red Camaros share it.

	WHY A SUFFIX AND NOT A FRESH UUID. Some thirty files pass these strings around: attributes the
	pages split on commas, a remote per screen, `==` comparisons and `parseCarKey` calls on both
	sides of the wire. With the serial as a suffix, every one of those keeps working unchanged:
	`parseCarKey` strips it before it reads anything, and an ID compares with `==` as exactly the
	car it names. It is the same trick the mutation suffix used, for the same reason, and it buys the
	same thing — NO MIGRATION. Every key already sitting in a save is a valid ID as it stands (a car
	with no serial is the one copy of itself the old rules allowed), so a profile nobody touches again
	is still read correctly, and only a car handed over after this change grows a `#`.

	The only callers that must NOT compare IDs are the ones asking about the MODEL — "do you already
	own a red Camaro?" — and those go through `modelKeyOf`. `GarageService.ownsModel` is that question.

	A body name may therefore never contain `#`, joining the comma and the colon (`OwnedAttribute`).
	Nothing on the roster does. ]]
local ID_SEPARATOR = "#"

--[[ `(key, serial)` → `"Camaro:6#17"`. A nil serial is the legacy ID, which is the key itself. The
	serial comes from `Keys.NextCarSerial` and only `GarageService` mints one. ]]
function GarageConfig.carId(key: string, serial: number?): string
	if serial == nil then
		return key
	end
	return string.format("%s%s%d", key, ID_SEPARATOR, serial)
end

--[[ The other half: `"Camaro:6#17"` → `("Camaro:6", 17)`, and an ID with no serial →
	`("Camaro:6", nil)`. Anything that is not a string comes back as nil, nil.

	Anchored to digits at the very END, so a `#` anywhere else (a hand-edited save, a future key
	format) is left in the key rather than cut in half. A key that fails to parse is still a key that
	fails to parse; this never makes one out of nothing. ]]
function GarageConfig.splitCarId(id: unknown): (string?, number?)
	if type(id) ~= "string" then
		return nil, nil
	end
	local key, serial = string.match(id, "^(.*)" .. ID_SEPARATOR .. "(%d+)$")
	if key and key ~= "" then
		return key, tonumber(serial)
	end
	return id, nil
end

--- The model a car ID is a copy of. See the block above for which callers want this over the ID.
function GarageConfig.modelKeyOf(id: unknown): string?
	return (GarageConfig.splitCarId(id))
end

--[[ Split one of the comma-separated broadcasts. Trimmed, and empty entries dropped.

	SPLIT ON THE COMMA ONLY — see `OwnedAttribute`. Half a dozen roster bodies have a space in their
	name, and a pattern that treats whitespace as a separator turns `Golf GTI` into two cars that do
	not exist. Shared from here so the three pages that read these attributes cannot each get it
	wrong in their own way. ]]
function GarageConfig.split(raw: unknown): { string }
	local out = {}
	if type(raw) ~= "string" then
		return out
	end
	for entry in string.gmatch(raw, "[^,]+") do
		local trimmed = string.match(entry, "^%s*(.-)%s*$")
		if trimmed ~= "" then
			table.insert(out, trimmed)
		end
	end
	return out
end

--[[ Dollars per second one parked car of this tier earns, multiplier included. nil tier = 0.

	`mutation` is the weather key the car carries, and it multiplies the lot — see
	`WeatherConfig.valueMultiplierOf`, and note that it is a DIFFERENT and much smaller number than
	the one a mutated bank pays out at. Income compounds over a session and a payout does not, so the
	two cannot be the same figure without one of them being wrong.

	It goes through `rateOf` rather than being applied by the callers for the reason this function
	exists at all: three places integrate this expression — the mat, the HUD's per-second line and
	the customer who pays for a look — and a multiplier applied in two of them is a lot whose income
	disagrees with its own sign. nil, an unknown key and the feature switched off all answer 1. ]]
function GarageConfig.rateOf(tier: number?, mutation: string?): number
	local rate = tier and GarageConfig.Income.PerTier[tier]
	if not rate then
		return 0
	end
	return rate * GarageConfig.Income.Multiplier * WeatherConfig.valueMultiplierOf(mutation)
end

-- What that car sells for, as a whole number of dollars. A mutated car is worth more to sell for
-- exactly the same reason it earns more: `SellSeconds` of its own rate, whatever that rate is.
function GarageConfig.valueOf(tier: number?, mutation: string?): number
	return math.round(GarageConfig.rateOf(tier, mutation) * GarageConfig.Income.SellSeconds)
end

--[[ DEALERSHIP VALUE: what a whole collection is worth, from a list of car keys.

	`keys` is whatever `OwnedAttribute` holds, already split — every car this player has ever banked,
	as "Sedan12:6" pairs. Returns whole dollars.

	=== IT COUNTS EVERY KEY, NOT EVERY BODY, AND THAT IS THE DIFFERENCE FROM THE INDEX ==========

	The Index page and the BIGGEST COLLECTION board both count DISTINCT BODIES, because those two
	answer "how much of the roster have you seen?" and four colours of one Camaro is one entry in a
	catalogue. This is the other question. A colour you own is a car standing in your dealership that
	you could park or sell (header note 3, and `Banking` on why colour is identity), so four Camaros
	are four cars and this counts four.

	The two numbers therefore disagree on purpose and by a lot for a mature collection. If a screen
	ever shows both, they need labelling as what they are — a count of the roster, and a valuation of
	the lot — because a player reading "23 cars, worth 41 cars' money" would be right to file a bug.

	=== A BODY OFF THE ROSTER IS WORTH NOTHING =================================================

	`TierOfBody` is the price list, so a key naming a body no world has — a car from a build that
	renamed it, a hand-edited profile — contributes zero rather than erroring or guessing a tier.
	The same call the Index page and the collection board make, and it is not destructive: nothing
	here writes, so renaming the body back restores its value.

	A DUPLICATE KEY IS COUNTED ONCE. `Owned` is a set by construction (`_addOwned` appends only what
	`_owns` says is new), so this should never fire — it is here because a valuation that could be
	inflated by a repeated string is the kind of thing a leaderboard makes worth doing. ]]
function GarageConfig.valueOfCollection(keys: { string }?): number
	if type(keys) ~= "table" then
		return 0
	end

	local seen = {}
	local total = 0
	for _, key in keys do
		if type(key) == "string" and not seen[key] then
			seen[key] = true
			-- The mutation is valued along with the tier: a Charged Camaro is worth more than a plain
			-- one, and a valuation that ignored that would disagree with the price the car actually
			-- sells for. It is also why two keys for the same body and colour can be worth different
			-- amounts, which is the same thing colour did to this sum when it arrived.
			local body, _paint, mutation = GarageConfig.parseCarKey(key)
			total += GarageConfig.valueOf(body and GarageConfig.TierOfBody[body], mutation)
		end
	end
	return total
end

--[[ Format money for a label: comma groups up to five figures, then a suffix.

	The switch is at 100,000 rather than at 1,000 because the PSD's own readout is "$67,890" — under
	six figures the exact number is both readable and worth reading, and "$67.9K" throws away the
	digits a player is actually watching tick over. Past that the width stops fitting the pill and the
	precision stops mattering. ]]
local SUFFIXES = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e5, "K" } }

function GarageConfig.formatCash(amount: number): string
	amount = math.max(0, math.floor(amount or 0))
	for _, step in SUFFIXES do
		if amount >= step[1] then
			-- Divided by 1e3 for the K band specifically: the band starts at 100,000, so this is
			-- "100.0K" rather than "1.0K", which is the point at which the suffix earns its place.
			local scale = if step[2] == "K" then 1e3 else step[1]
			return string.format("$%.1f%s", amount / scale, step[2])
		end
	end

	local text = tostring(amount)
	local grouped, count = text, 0
	repeat
		grouped, count = string.gsub(grouped, "^(-?%d+)(%d%d%d)", "%1,%2")
	until count == 0
	return "$" .. grouped
end

--[[ Format a PER-SECOND rate for a label. The same money as `formatCash`, one digit finer while the
	number is small enough to need it.

	IT IS DELIBERATELY NOT `formatCash`, AND THE REASON IS THAT THE BOTTOM OF THIS LADDER LIVES IN
	THE FRACTION. `formatCash` floors to whole dollars, which is right for a balance — nobody wants
	"$1,204.7" ticking over on a mat — and wrong for a rate. Tier 1 is 2/s and a bay level buys +25%
	of the base (`UpgradeConfig.Bay.Step`), so the first upgrade a player ever buys takes 2.0/s to
	2.5/s, and floored, the sign they just paid 500 for reads "$2/s" both before and after.

	That is not a cosmetic complaint; it is the bug this function was written for. In the playtest
	that found it, an upgraded LEVEL 2 bay read "$2/s" next to an untouched LEVEL 1 bay reading
	"$3/s" — because the neighbour's car was one tier up, and 2.5 floored below 3 while 500 had just
	changed hands. Two signs, both floored, and the purchase looked like it had landed on the wrong
	one. The sign has to print the number the bay actually pays.

	THE THRESHOLD IS WHERE ONE LEVEL BECOMES WORTH A WHOLE DOLLAR. The finest step either ladder
	buys is the bay's +25% of base, so under 4/s a level is worth less than $1 and whole dollars
	cannot show it at all; the lot-wide `Income` ladder is +15%, which wants ~7. Ten clears both, and
	it is the first tier (tier 4, at 10/s) whose every step is already a whole dollar — so nothing
	above the threshold gives anything up by being floored, and the suffix bands never see a decimal.

	ONE DECIMAL, AND ALWAYS ONE BELOW THE THRESHOLD rather than only when there is a fraction. The
	kiosk prints this number twice on one sign — what the bay earns now and what the next level buys
	— and two labels that disagree about their width read as two different kinds of number rather
	than as a before and after. ]]
GarageConfig.RateDecimalsBelow = 10

function GarageConfig.formatRate(amount: number): string
	amount = math.max(0, amount or 0)
	if amount >= GarageConfig.RateDecimalsBelow then
		return GarageConfig.formatCash(amount)
	end
	-- Floored to the digit shown, the same direction `formatCash` rounds, so a rate is never
	-- advertised a notch above what the bay will actually pay out.
	return string.format("$%.1f", math.floor(amount * 10) / 10)
end

-- === What a car is called ===================================================
--[[ A body name as a label says it: "Sedan20B" -> "SEDAN 20B", "Golf GTI" -> "GOLF GTI",
	"M5" -> "M5".

	THE BREAK IS ONLY INSERTED FOR A WORD RUNNING STRAIGHT INTO DIGITS, and the roster is why it has
	to be that narrow. It holds two kinds of name: placeholder bodies like `Sedan12`, which want the
	break to be readable, and real ones like `Golf GTI`, `Model 3` and `M5`, which already read
	correctly and must be left alone. A blanket letters/rest split — which is what this was — turned
	`M5` into "M 5" and `Model 3` into "MODEL  3", a double space, because the remainder already
	began with one.

	So: at least three leading letters (a word, not a designation like `M5` or `X5`), and a
	remainder that starts with a digit (not one that already carries its own separator).

	THE SPACES COME BACK NON-BREAKING, because every caller draws this with `TextScaled`, which would
	sooner break "GOLF GTI" onto two tiny lines than pick a smaller font. Same rule, same fix, as
	`CarDealConfig.oneLine`.

	=== THE GAME NAME FIRST — 2026-09-28 ======================================================

	Every real car on the roster now has a game name (`CarNameConfig`, for trademark reasons), and
	this is the one door every label goes through, so it is where the swap happens. The spacing rule
	above still applies to whatever comes out — a game name, or the internal name of a body that has
	none (the placeholder traffic cars). ]]
function GarageConfig.displayName(body: string): string
	local renamed = CarNameConfig.nameOf(body)
	local source = renamed or body
	local word, rest = string.match(source, "^(%a%a%a+)(%d.*)$")
	local name = if word then word .. " " .. rest else source
	return (string.gsub(string.upper(name), " ", "\u{00A0}"))
end

--[[ What one car is called: "RED CAMARO", or just "CAMARO" for a car in its authored livery.

	THE COLOUR IS IN THE NAME BECAUSE THE COLOUR IS PART OF THE CAR. A player can own the same body
	several times over, and a list would otherwise show two rows reading CAMARO with no way to tell
	which is which — the one thing the inventory exists to let them do. Stock takes no prefix: it is
	the car's own look rather than a colour choice, and "STOCK CAMARO" reads as a trim level.

	IT LIVES HERE RATHER THAN ON THE SCREEN THAT FIRST NEEDED IT (the Cars Inventory, where it was a
	local until the sell lot arrived) for the reason `carKey` gives about identity: a car is a body
	and a colour, and there must be exactly one place that turns that pair into words. Two copies is
	how a lot ends up offering to buy a "CAMARO" the inventory calls a "RED CAMARO".

	A BODY THAT COMES IN ONE COLOUR takes no prefix either (2026-10-22, "WHITE FLOATER"): the colour
	tells two of them apart from nothing, since every one is that colour (`PaintConfig.poolFor`). ]]
function GarageConfig.carName(body: string, paint: number?): string
	local name = GarageConfig.displayName(body)
	if paint == nil or paint == PaintConfig.StockIndex or #PaintConfig.poolFor(body) <= 1 then
		return name
	end
	return string.upper(string.gsub(PaintConfig.nameOf(paint), " ", "\u{00A0}")) .. "\u{00A0}" .. name
end

-- Approved economy balance, 2026-10-04.
local Balance = require(script.Parent.BalanceConfig)
for world, ladder in Balance.Values do
 for rung, value in ladder do
  GarageConfig.Income.PerTier[WorldConfig.firstTierFor(world) + rung - 1] = value / GarageConfig.Income.SellSeconds
 end
end
--[[ OFF (2026-10-05). On, every banked car is written NOT FOR SALE the moment it is awarded
	(`GarageService.awardCar`), so every car the owner parked came up with the red sign over it and no
	buyer could make an offer on it. FOR SALE is the default the rest of the game is built around
	(`GarageService.isForSale`); a player takes a car off sale themselves. Cars already banked while
	this was on had theirs dropped by versioning `InventoryConfig.Keys.NotForSale` (2026-10-06). ]]
GarageConfig.Banking.DefaultNotForSale = false
--[[ ON (2026-10-15, "for any cars that you buy with a pack or maybe the random car, can you make it
	not for sale by default"). A car paid for in Robux, a shop bundle's (`BundleService.grantBundle`) or
	a random pull's (`RandomCarService`), arrives with the NotForSale flag already set, so parking it
	does not put it in front of buyers until the owner turns FOR SALE on. Stolen and reward cars keep
	the default above. Only the moment of the grant: a car already owned is not touched. ]]
GarageConfig.Banking.PaidCarsNotForSale = true


-- === The podium glow ========================================================
--[[ RARITY YOU CAN SEE FROM THE DOOR (2026-10-06, the polish pass). A car on a podium said what it
	was worth only to somebody close enough to read a sign. Now its podium does: a disc of light in the
	car's rarity colour (`CarRarity.colourOf`) under it, a light that tints the car and the floor, and
	for the top band a column of light straight up — so a showroom visibly gets fancier as the cars in
	it get better, with no new building art. `GarageService._dressPodium` builds it beside the car (not
	inside it, so nothing that measures the car's bounding box sees it) and `_clearBay` takes it away.

	`MinBand`: commons stay plain on purpose, so the first glow is something a player earns. The
	light's brightness climbs with the band (`Brightness` + `PerBand` x (band - MinBand)).

	`Enabled = false` is the podiums exactly as before. ]]
GarageConfig.PodiumGlow = {
	Enabled = true,
	MinBand = 2,
	--- The disc: studs inside the deck's edge, its thickness, how see-through.
	Inset = 1.2,
	Thickness = 0.12,
	Transparency = 0.55,
	Brightness = 1.2,
	PerBand = 0.6,
	Range = 16,
	--[[ The column of light, for `Beam.MinBand` and up. OFF since the first look (2026-10-06, the
		owner: "that beam looks ugly") — a solid neon tube read as a yellow pole through the car's
		roof, not as light. `Enabled = true` brings it back as it was. ]]
	Beam = { Enabled = false, MinBand = 5, Height = 45, Width = 2.6, Transparency = 0.82 },
	--[[ ...what marks the top cars instead: sparkles drifting slowly up off the disc, in its colour,
		for `Aura.MinBand` and up. Light that MOVES around the car rather than a solid shape through it,
		so it reads as the car being special instead of as geometry. `Rate` a second. ]]
	Aura = { Enabled = true, MinBand = 4, Rate = 8, Size = 0.8, Rise = 3 },
}


--[[ THE GAIN POP (2026-10-07, the polish pass). The counter already rolls up and punches when money
	arrives (`Hud.RollTime`, `PulseScale`), but it never said HOW MUCH arrived — a tip, a sale and a
	collect all looked like the same twitch. Now every gain throws a green "+$350" up off the counter
	that floats and fades over `Seconds`. Gains landing within `MergeSeconds` of each other (a stream
	of tips, a collect sweep) add into the one pop rather than stacking a column of them. Only on an
	increase, for the punch's reason: a balance going down is a purchase. `Enabled = false`: no pop. ]]
GarageConfig.Hud.GainPop = { Enabled = true, Seconds = 1.1, MergeSeconds = 0.5 }


--[[ THE INCOME LINE OVER THE CASH, BACK (2026-10-08). The small green rate above the balance read the
	passive income rate (`RateAttribute`), and with passive income off the lot earns through TIPS, so
	that rate is zero and the line stayed hidden ("there also used to be a green small text on top of
	the cash that said like 1,000/hr"). With `Income.Passive` off it now reads THIS instead: what the
	customers on your lot tip per hour, estimated by the same simulation the offline payout uses, at
	full live strength rather than the offline share (`OfflineService._publishLabelRate`). Per hour,
	because a tip economy in dollars per second is mostly zeros. ]]
GarageConfig.Hud.TipRate = { Attribute = "TipRatePerHour", Format = "~%s/hr" }


--[[ "NOT ENOUGH CASH", SAID (2026-10-08, the polish pass). Pressing something you cannot afford
	opened a Robux top-up at best, and at worst — inside the offer's cooldown, or with packs off — did
	nothing you could see. Now every such press (`CashService.offerTopUp`, which every refusal calls)
	also tells the client the gap, and the money counter answers it: the pill shakes, the balance
	flashes red, and "NEED $1,200 MORE" pops off it in red. `Enabled = false`: silent as before. ]]
GarageConfig.Hud.Short = {
	Enabled = true,
	Format = "NEED %s MORE",
	Color = Color3.fromRGB(255, 80, 80),
	Seconds = 1.3,
	--- Degrees the pill swings each way, and how many swings.
	Shake = 7,
	Swings = 4,
	Sound = { Group = "UI", Name = "Denied" },
}

--[[ THE CLICKABLE SALE TAG (2026-10-08, `SaleTagController` has the design): the pill over each of the
	owner's cars that shows FOR SALE / NOT FOR SALE and flips it on a tap. `Size` is studs (the
	billboard's own scale), `Height` studs above the deck — the server sign's `NotForSaleSign.Height`, so
	the tag sits where the sign did. The two colour pairs are the pill's gradient, top then bottom.
	`Enabled = false`: no tag, and the owner sees the server's red sign again. ]]
GarageConfig.SaleTag = {
	Enabled = true,
	Size = Vector2.new(5.2, 1.9),
	Height = 7.5,
	MaxDistance = 60,
	ForSaleText = "FOR SALE",
	NotForSaleText = "NOT FOR SALE",
	ClickHint = "click to change",
	TouchHint = "tap to change",
	--- The kit's own button faces (its green claim, its pink-to-red decline), top to bottom.
	ForSaleColors = { Color3.fromRGB(255, 217, 0), Color3.fromRGB(17, 211, 6) },
	NotForSaleColors = { Color3.fromRGB(251, 0, 255), Color3.fromRGB(217, 8, 12) },
}


--[[ THE CAR INFO TAG (2026-10-14, `Modules/CarInfoTag` has the design): name, rarity and value over a
	parked car and over a held one. Sizes are studs. `ParkedHeight` is over the deck, ABOVE the sale
	sign and tag (7.5, `NotForSaleSign.Height` / `SaleTag.Height`) so the two stack instead of
	overlapping. `HeldLift` is over the held car's roof. `Enabled = false`: no tags. ]]
GarageConfig.InfoTag = {
	Enabled = true,
	ParkedHeight = 10.5,
	ParkedSize = Vector2.new(7, 2.6),
	HeldLift = 1.5,
	HeldSize = Vector2.new(4.5, 1.7),
	MaxDistance = 60,
	--- The value line (was a "%s/s" cash rate on the first cut; see `Modules/CarInfoTag`).
	ValueFormat = "WORTH %s",
}

return GarageConfig
