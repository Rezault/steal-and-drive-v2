--[[
	CarDealConfig
	-------------
	THE MARKET. A car parked in each of the island's car parks, a seller beside it and a
	price over its head, rotating every few minutes. Walk up, hold the button, and the car is yours.
	Then you get into it where it stands and drive it away.

	It is the answer to the one thing the game had no verb for: CASH BUYING A CAR. Every other route
	into the collection goes through a run — you steal a car, you get away with it, it banks — and
	the money that run pays out had nowhere to go but upgrades. `bug-fixes-context.md` records three
	separate players finding the imported Market screen and pressing a button that did nothing; this
	is what that screen was supposed to be, out in the world where the cars are.

	SIX THINGS TO KNOW BEFORE TUNING ANY OF IT.

	1. THE OFFERS ARE THE SERVER'S, THE SELLER IS YOURS. Everybody in the server sees the same cars
	   at the same prices in the same lots on the same clock — that is what makes it a market and not a
	   shop menu. What is NOT shared is the person standing next to the car: `Dealer.Friends` builds
	   them out of the local player's own friends list on the client, so the car you are looking at
	   is being sold to you by somebody you know, and to the player beside you by somebody they know.
	   Same trick, same reason, as `CustomerConfig.Friends` and `StealConfig.Driver.Friends`.

	2. BUYING IS BANKING. A bought car goes through `GarageService.awardCar`, the same call a car
	   that survived a run goes through, and every branch of it applies: the catalogue ticks, a free
	   bay parks it, a better car pushes your worst one back into the collection. There is
	   deliberately no second set of rules for a car you paid for — the moment "bought" and "stolen"
	   produce different cars, every screen in the game has two cases to draw.

	   The one thing that IS different is the refusal: a car already in your collection cannot be
	   bought (`Offer.RefuseOwned`). Banking a duplicate sells it back at `SellSeconds`, and since a
	   deal costs `Price.Markup` times that, buying one would be handing the game money for nothing.

	3. THE PRICE FLOOR IS NOT A TASTE CALL. `Price.Markup` may never go to 1 or below. A car sells
	   for `GarageConfig.Income.SellSeconds` of its own income; price a deal under that and buying it
	   and banking the duplicate is a money printer with no run involved. Everything else about the
	   number is tuning; that part is arithmetic. See `Price`.

	4. THE BAYS ARE THE MAP'S OWN CAR PARKS AND THEY NEVER MOVE. There are four painted lots on this
	   island, one off each of the plaza's four spokes, and a deal stands in the same END stall of
	   every one of them for the life of the server. What rotates is the car standing in the stall,
	   not where the stall is.

	   That is a change from what this file used to do, which was to find its own bays anywhere along
	   the island's kerbs and move all three of them every rotation. `Lots` has the argument at
	   length; the short version is that an address a player can drive back to is worth more than a
	   surprise, and "check the four lots for a good deal" is a lap somebody can decide to take.

	5. THE CAR IN A BAY IS SCENERY; THE ONE YOU BUY IS NOT. What is parked in a bay is a stripped
	   `Modules/CarDisplay` clone: no chassis, no seat, no scripts, anchored and query-blind. That is
	   the podium cars' reason applied here, because three drivable CarBones rigs parked around the
	   island would be 900 instances of working vehicle doing nothing, and the first player to find
	   one would drive it away without paying for it.

	   The moment somebody DOES pay, that clone is thrown away and `LobbyCarService` stands a real
	   rig in the same bay with the buyer already in the driver's seat (`Handover`). Parking these on
	   the road rather than on a plinth is what makes that possible, and it is the whole argument for
	   the change: you do not receive a car, you get into one and drive off in it.

	6. THE COUNTDOWN IS THE ECONOMY'S BRAKE. How fast cash turns into income is capped by how many
	   cars are on sale and how often they change, rather than by the price. A player with unlimited
	   money can still only buy one car per LOT per `Offer.Interval`, which on this map is four. If
	   the market ever feels like it is outrunning the run loop, that is what to move — and it moves
	   by painting a lot on the map or taking one away, rather than by editing a number in here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ For `valueOf` alone — the sell price a deal is marked up from. `GarageConfig` requires
	`PaintConfig`, `UpgradeConfig` and `WorldConfig` and nothing else, so this cannot cycle. ]]
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local CarDealConfig = {}

--[[ Master switch. Off = no stands are built, no offers are rolled, nothing is bought and the
	plaza is exactly the empty roundabout it was before this file existed. It is also the A/B for
	what the market is worth: nothing else in the economy reads any of this.

	=== OFF FOR THE SELLER AT YOUR KERB — 2026-10-15 ===
	The plaza stands are replaced by `SellerConfig`: a seller pulls up at your own dealership
	instead of you driving out to theirs. Off rather than deleted, so `true` here plus
	`SellerConfig.Enabled = false` is the old market, exactly. `SellerService` still reads
	`rollBody`, `Car` and `Handover` from this file whichever way this is set. ]]
CarDealConfig.Enabled = false

-- === Where they live ========================================================

-- Workspace folder every stand is parented to, created on demand. One flat folder rather than one
-- per stand, so "what is on sale right now?" is a single `GetChildren()` in the explorer.
CarDealConfig.FolderName = "CarDeals"

--[[ The tag on every stand Model, and how the CLIENT finds them.

	A TAG AND NOT THE FOLDER, because StreamingEnabled is on in this place and the client's copy of
	`Workspace.CarDeals` is not a stable thing to watch: a stand appears and disappears as the player
	walks in and out of range, and the folder itself need not exist on a client that has never been
	near the plaza. `CollectionService:GetInstanceAddedSignal` answers all of that with one
	subscription and no polling.

	It is also why every stand is `ModelStreamingMode.Atomic`: a tag fires on the MODEL, which can
	arrive before its own subtree has streamed in, and a controller that walked the children on that
	frame would bind nothing. Atomic makes the whole stand arrive as one piece. ]]
CarDealConfig.Tag = "CarDeal"

-- Names inside one stand. The client finds every one of these by name, so they are the contract
-- between the service that builds a stand and the controller that dresses it.
CarDealConfig.Names = {
	Stand = "CarDeal", -- the Model, with its index appended: `CarDeal1`
	--- The bay's floor: an invisible, collision-free, query-blind slab filling the whole stall. It is
	--- the stand's PrimaryPart, the part the prompt hangs off, and the part both attachments below
	--- are parented to. See `Bay` for why there is nothing painted on it.
	Base = "Base",
	Car = "DealCar", -- the display clone
	Prompt = "BuyPrompt",
	--- An Attachment on `Base`, above where the seller stands. The bubble is adorned to THIS and
	--- never to the seller's head — see `Bubble`.
	BubbleAnchor = "BubbleAnchor",
	--- An Attachment on `Base` marking where the seller stands, in world space, so the client does
	--- not have to re-derive the stand's frame to place a rig.
	DealerStand = "DealerStand",
}

--[[ Attributes stamped on the stand Model. The whole offer travels as attributes rather than as a
	remote, which is this project's house pattern for anything a screen has to redraw itself from
	(`GarageConfig.OwnedAttribute`, `LobbyCarConfig.SpawnedAttribute`): the client rebuilds its
	bubble from an attribute change, so what is drawn is written by the one thing that actually
	knows — the server, after the car is really standing there.

	`Body` AND `Paint` AND `Tier` AND `Price`, rather than a key the client unpacks: three of the
	four are read by something that cannot derive them (the bubble prints the price, the rarity is
	looked up by body, the purchase is checked against the tier), and a parse per read of a string
	that changes every five minutes is work for nothing. ]]
CarDealConfig.Attributes = {
	Index = "DealIndex",
	Body = "DealBody",
	Paint = "DealPaint",
	Tier = "DealTier",
	Price = "DealPrice",
}

--[[ Written on `Workspace`, not on a stand: the server time the CURRENT offers expire at, from
	`workspace:GetServerTimeNow()`.

	ON WORKSPACE BECAUSE IT IS ONE CLOCK, NOT THREE. Every stand rotates on the same beat, so the
	deadline belongs to the market rather than to any one bay. StreamingEnabled is also on in this
	place, so a stand a client would have read it off may not be replicated to that client at all. An
	attribute on Workspace is one write per rotation and is always there to read.

	`GetServerTimeNow` AND NOT `os.time`: it is the one clock that reads the same on the server and
	on every client, so the countdown a player sees is the countdown the rotation actually runs on
	and no drift correction is needed anywhere. ]]
CarDealConfig.NextRotationAttribute = "CarDealNextRotation"

-- === Where the bays are =====================================================

--[[ THE MARKET IS THE MAP'S OWN CAR PARKS, ONE DEAL IN EACH, ALWAYS THE SAME STALL OF IT.

	The island has four painted lots on it, one off each of the plaza's four spokes: a rank of white
	stall lines with a kerbed grass median closing the head of them, drawn by the modeller as part of
	the map. A deal stands in the END stall of each — the same end of every one — and it stays there
	for the life of the server. Every `Offer.Interval` the CAR changes; the address does not.

	=== WHY THIS IS FIXED, WHEN IT USED TO BE SCATTERED ======================================

	This file used to find its own bays: a grid sweep over the whole island, keep the road cells with
	a non-road neighbour, back a painted bay onto that edge, put a car on it, and move all three of
	them somewhere else every rotation. It worked, and what killed it is the loop it asked for. Bays
	that move every five minutes are bays nobody can go and check: the only way to learn what is for
	sale is to sweep the island and hope, and a player who saw a car they wanted five minutes ago has
	nowhere to go back to. The lap it was meant to be worth driving was a lap with nothing on it.

	Four fixed addresses invert that (the user's call, 2026-08-26). The lap is still the loop —
	nothing tells you what is in a lot until you can see it — but it is a lap with four known stops
	on it, which is a ROUTE rather than a search, and it is driven in a car the player already owns.
	"Is there a good deal on one of the lots today?" is now a question with an answer.

	It also puts every deal somewhere a car belongs. A bay found on a kerb is a legal parking spot by
	construction and still reads, half the time, as a car that stopped in an odd place; a car in a
	painted stall in a car park reads as a car for sale, and it costs no code to say so.

	=== A LOT IS RECOGNISED BY ITS PAINT, NOT BY ITS NAME =====================================

	Nothing in the map identifies a car park. The stall lines are unnamed `Part`s sharing a folder
	with every lane dash and crosswalk stripe on the island, and the map is a builder's export that
	the next swap can rename wholesale (`docs/MapLayout.md` §6, and the naming contract every other
	map-reading feature in this game leans on). So a lot is found by the one thing that MAKES it a
	lot: a rank of parallel lines, all the same length, evenly spaced about a car's width apart.

	  1. every flat, thin part under `Paint.Roots` whose long side is `MinLength`..`MaxLength` and
	     whose short side is under `MaxWidth` is a candidate stall line;
	  2. candidates that are parallel, the same length, at the same height, and offset from one
	     another only ACROSS their own length, are one rank;
	  3. a rank is cut into RUNS wherever a gap is too small to be a stall or too big to be one lot,
	     and a run of at least `MinLines` lines is a car park;
	  4. the closed end is the end with a kerb behind it, found by probing the ground past both ends;
	  5. the stall taken is the one on `Stall.Side` of the rank, and the car in it faces out.

	STEP 3 IS WHAT SEPARATES A CAR PARK FROM A CROSSWALK, and it is not a formality: this island's
	crossings are twelve 27.5-stud stripes in a dead-parallel rank seven studs apart, which passes
	every other test on the list. A stall a car cannot fit across is not a stall. Measured on this
	map the rule leaves exactly the four lots, at 25 to 30 studs a stall, and throws away both
	crossings, all 56 lane dashes and every pavement edge.

	IT CUTS RATHER THAN REFUSES, and that is the difference between one lot losing itself and two
	losing each other. Two car parks either side of a street are one rank by every test above — same
	bearing, same length, same height, side by side — and a rule that failed the rank on its widest
	gap would delete both of them. `CarDealService._runsOf` has the three cases.

	STEP 4 IS WHY NOTHING HERE NAMES A DIRECTION. The head of a stall is where the kerb is, and the
	kerb is the one part of a lot that stands up: the medians these lots back onto are 5.2 studs
	proud of the asphalt, against 0.1 for paint and 0.4 for a verge (`docs/MapLayout.md` §7 has the
	radial scan). Two rays either side answer it, so a lot drawn the other way round on a future map
	is still parked in correctly, and a lot with no kerb at either end falls back to facing away from
	the middle of the island. ]]
CarDealConfig.Lots = {
	--[[ The middle of the island: the roundabout's own centre, the same two numbers
		`BuildLeaderboardBoard` seats the global leaderboard on. It is the ONLY authored coordinate in
		this file and it is no longer load-bearing — it numbers the lots (by bearing, so stand 1 is
		the same lot in every server) and it breaks the tie for a lot with no kerb at either end. Y is
		deliberately absent, for `PlotConfig.Fallback`'s reason: every deck height in this map comes
		out of mesh geometry, and a typed Y is the number that silently breaks if the island moves. ]]
	CentreX = 2041,
	CentreZ = 490,

	--[[ === HAND-PLACED SPOTS — 2026-10-15 ===
		The paint reader below found the old island's car parks. The new map has no stall lines it
		recognises, so the market turned itself off with a warning. WHAT IT IS NOW: any BasePart in
		Workspace tagged with this tag IS a stall. When at least one exists, the paint reader does not
		run at all, because two sources disagreeing about where the bays are is worse than either one.

		How a marker reads, so it can be laid out in Studio without opening this file:
		  * sit it ON the ground: its BOTTOM face is the deck the car parks on;
		  * its FRONT face (LookVector) is where the car's nose points, out towards the road;
		  * Size.X is the stall's width and Size.Z its depth (about 12 x 22 fits every car).
		The marker is made invisible, non-colliding and unqueryable at start-up, so it can stay bright
		in Studio. With no tagged parts at all, the paint reader runs exactly as before. ]]
	SpotTag = "CarDealSpot",

	--- How a rank of stall lines is told apart from every other white line on the island.
	Paint = {
		--[[ Where to look, as folder paths under `Workspace.<PlotConfig.MapName>`. Both of this map's
			line kinds are in here: the stall lines are in `Markings` beside the lane paint, and
			`Pavement` is included because the head lines that close these lots live in there and a
			future lot may be drawn entirely out of one folder or the other.

			A path that does not resolve is skipped, and a lot with NOTHING resolved falls back to
			scanning the whole map. That is one `GetDescendants` over 43,000 parts, once, at start-up,
			and it is the right direction to fail in: a slower boot rather than no market at all. It
			is also the branch a map swap lands in, and the warning it logs is the thing to go and
			fix. ]]
		Roots = {
			{ "City", "Roads", "Markings" },
			{ "City", "Roads", "Pavement" },
		},

		--[[ What one stall line looks like, in studs. Long enough that a car parked between two of
			them is inside its own paint, short enough that a lane line down a carriageway cannot be
			mistaken for one, and thin enough that only paint qualifies.

			35 IS WHAT THIS MAP DRAWS and the window around it is wide deliberately: `MaxLength` is the
			number that decides how DEEP a stall may be, and a deeper stall is only ever more room for
			the car. `MinLength` at 20 sits just under the longest body on the roster (`NewSports37`
			at 25.62) — a stall shorter than the car in it is a car hanging out of the lot. ]]
		MinLength = 20,
		MaxLength = 60,
		MaxWidth = 4,
		MaxThickness = 1.5,

		--[[ How far apart two lines have to be to have a stall between them, and how far apart they
			may be before they are two different things that happen to be parallel.

			`MinStall` IS THE CROSSWALK TEST (see the header) and it is also the honest question about
			the car: the widest body in the game is `Sian` at 12.90 studs, so 14 is the narrowest gap
			a car could stand in at all. Every stall on this map is 25 to 30.

			`MaxStall` is a sanity bound rather than a design one: two lines 40 studs apart are the
			two sides of something that is not a parking space. ]]
		MinStall = 14,
		MaxStall = 40,

		--[[ How many lines a rank needs before it is a car park. Three, which is two stalls: a pair
			of parallel lines is every kerb, gutter and median edge on the island, and one stall is
			not a lot. This map's lots draw five. ]]
		MinLines = 3,

		--[[ How parallel two lines must be to be in the same rank, as the dot of their long axes.
			0.996 is about five degrees, which holds a rank together around the slight curve a builder
			draws these on and still refuses two lines meeting at a junction. ]]
		Parallel = 0.996,

		--- Studs two lines may differ in length, and in height, and still be in the same rank. Both
		--- are slop for a builder's export rather than design: the lines of one lot here are the same
		--- part duplicated, so they agree exactly, and a lot drawn by hand would not.
		SameLength = 2,
		SameHeight = 1,

		--[[ How far a line may sit ALONG its own axis from the first line of its rank and still be
			part of it. A rank is a row of lines side by side; a line that is also shifted lengthwise
			is a different row that happens to point the same way, which is what a second car park
			across the road looks like. ]]
		Skew = 3,

		--[[ Under this many studs apart, two lines in a rank are the same line drawn twice and the
			second is dropped rather than read as a stall nobody could park in.

			IT IS NOT HYPOTHETICAL: the lot at the west spoke has two lines two tenths of a stud apart
			(z 438.4 and 438.6), a builder's duplicate that nothing in the map shows. Left in, the
			rank has a "stall" 0.2 studs wide in it and the whole lot fails `MinStall`. ]]
		Duplicate = 1,

		--- Studs taken off a stall's line-centre-to-line-centre width to get what a car actually has
		--- between the paint. The lines on this map are 2 wide, and this only sizes the fit, so being
		--- a little pessimistic costs nothing.
		Inset = 2,
	},

	--- Which stall of a lot the deal stands in.
	Stall = {
		--[[ "Left" or "Right", AS SEEN FROM THE ROAD LOOKING INTO THE LOT — which is how a driver
			arriving at one sees it, and the way the user pointed at it.

			LEFT, AND THE SELLER IS THE REASON IT IS NOT AN ARBITRARY CHOICE. `Dealer.SideMargin`
			stands the seller off the car's RIGHT-hand side, and a car facing out of a stall has its
			right-hand side on the viewer's LEFT. So the left-hand stall is the one whose seller
			stands on open tarmac at the end of the rank; the right-hand stall would stand them in the
			middle of the next stall along, half behind its paint. Flipping this to "Right" flips the
			seller with it and both still work — it is a choice of which END, not of geometry.

			AN END STALL EITHER WAY. The whole point is that it is the same stall in every lot, so a
			player learns where to look once and then knows where to look in all four. ]]
		Side = "Left",

		--[[ Studs from the middle of the stall within which somebody else's car counts as PARKED IN
			IT, which stops the market building a new deal around a car that is already standing
			there (`CarDealService._stallTaken`).

			12 IS JUST OVER HALF A STALL, measured to the other car's pivot. It has to be generous
			enough to catch the car the buyer is sitting in the moment they buy it — which is parked
			dead centre — and tight enough that a car in the NEXT stall along, 25 studs away, is
			somebody else's business. Anything between about 8 and 20 does that here. ]]
		ClearRadius = 12,
	},

	--[[ The two rays that find the closed end of a lot, and the ground probe they are fired with.

		`Reach` is how far past the end of a stall line the ground is sampled and `Steps` how many
		samples are taken on the way out; the HIGHEST ground found on each side is what the two ends
		are compared on. Sampling outward rather than at one distance is what stops the answer
		depending on how big a gap the builder left between the last line and the kerb: this map
		leaves 4.9 studs, and a single probe at the wrong distance either lands short on asphalt or
		overshoots the median entirely.

		`KerbRise` is how much higher one end has to be before it counts as the head. 1.2 sits well
		above every honest step between two surfaces a car can use here (asphalt to pavement 0.1,
		asphalt to verge 0.4) and well under the medians that close these lots (5.2).

		`ProbeUp` and `ProbeDown` are the ray itself, anchored on the map's own bounding box rather
		than on a typed altitude — `PlotConfig`'s rule, and generous downward because the island is
		Blender geometry whose `MeshPart.Size` is a bounding box rather than a surface. ]]
	Probe = {
		Reach = 12,
		Steps = 4,
		KerbRise = 1.2,
		ProbeUp = 60,
		ProbeDown = 160,
	},
}

-- === The bay ================================================================

--[[ ONE STALL OF ONE LOT: the map's paint, the car standing in it, and an invisible slab holding
	everything that hangs off the two.

	THERE IS NOTHING TO DRAW HERE ANY MORE. This used to paint its own bay — a darkened floor with
	three white stall lines on it — because the market stood on open asphalt where nothing said "this
	is a parking space". The map says it now, in its own paint, at its own width, and a second set of
	white lines drawn inside the first would be two bays disagreeing about where the stall is.

	WHAT IS LEFT IS `Base`: a slab filling the stall, invisible, and the only reason it exists is
	that everything else needs somewhere to live. It is the model's `PrimaryPart`, the part the
	prompt hangs off, and the parent of the seller's mark and the bubble's anchor.

	IT IS STILL ANCHORED, UNCOLLIDABLE, QUERY-BLIND AND UNTOUCHABLE, which matters more than an
	invisible part suggests: a bay stands exactly where a car parks, and `LobbyCarService`'s
	placement asks "is anything solid here?" about exactly that spot. A slab that answered would make
	the stall unusable to the car being sold on it. ]]
CarDealConfig.Bay = {
	--- Studs the slab sits above the road, and its own thickness. Thin enough that nothing can catch
	--- on it, thick enough to have a top face for the prompt to be measured from.
	Slab = 0.08,

	--[[ Studs between the car's back end and the head of the stall.

		A CAR IS PARKED AGAINST THE HEAD, NOT FLOATING IN THE MIDDLE OF THE PAINT. These stalls are
		34.9 deep and a typical body is 21.7 long, so a car centred in one sits with six studs of
		empty paint behind it, which reads as somebody who stopped short. Backed up, the slack is all
		in front of it, which is where a parked car keeps its slack and where the buyer needs it: the
		handover seats them in the car where it stands and they drive straight out (`Handover`).

		THE NOSE STILL POINTS OUT, which is not how anybody parks nose-first, and it is the one thing
		this feature will not trade. A buyer dropped into a car facing a kerb has to find reverse
		before the game has taught them there is one. ]]
	HeadGap = 3,
}

-- === The car on it ==========================================================

CarDealConfig.Car = {
	--[[ Turn the car off square, degrees. A CEILING, exactly like `GarageConfig.Display.Yaw`, with
		the fit stepping down from it per body (`CarDisplay.fitYaw`).

		ZERO, AND IT USED TO BE 22. On a plinth the car was a single object in the open with a player
		walking a circle around it, so it was posed at the three-quarter angle every press photo of a
		car is taken from. In a bay it is a car that somebody parked, and a car parked at 22 degrees
		across two white lines is a car parked badly. Square is the pose that reads as deliberate
		here, and it is also the pose the buyer has to drive out of. ]]
	Yaw = 0,

	--- Studs the lowest bodywork is lifted above the paint. Zero, for `GarageConfig.Display.Lift`'s
	--- reason: there is no suspension to settle and nothing is handed to the solver, so a clearance
	--- would just be a car hovering.
	Lift = 0,

	--[[ Shadows. ON here, unlike the podium cars, and it is the one place in this game where a
		display car casts one: this car stands alone on open asphalt under the skybox, where the
		shadow is most of what tells you it is a solid object rather than a decal. Six of them in a
		glass showroom was the case that was not worth paying for. ]]
	CastShadow = true,
}

-- === What is on sale ========================================================

--[[ Rolling an offer.

	=== THE WHOLE ROSTER IS ON THE TABLE, WEIGHTED TOWARD THE BOTTOM ==========================

	A deal is drawn from every car in every world, not from the world the buyer happens to be in —
	because the offers are SHARED (header note 1) and "the world the buyer is in" is a different
	answer for every player looking at the same stand. What shapes the draw instead is `WorldWeights`.

	The weights lean hard on world 1 for a reason that is about the new player rather than about the
	rich one: a market whose every lot holds a world-4 supercar is a market that says "not for you"
	to everybody who has not bought world 4, and that is most of the server most of the time. A
	world-4 car turning up in one lot is aspiration; one in all four is a locked door.

	It is NOT gated on what the player has unlocked, and that is deliberate: the collection is not
	the world ladder. A car you bought out of world 3 is a car you own, park and drive, exactly like
	one you stole — you simply have not driven the road it comes from yet. ]]
CarDealConfig.Offer = {
	--[[ Seconds an offer stands before it is replaced. Five minutes, which is the reference card's
		own countdown and lands where the two pressures cross: long enough that a player who sees a
		car they want can finish what they are doing, walk over and still find it there, and short
		enough that "check the plaza" is a thing worth doing more than once a session.

		IT IS ALSO THE ECONOMY'S BRAKE (header note 6). Cash can become income at no more than
		one car per LOT per interval, whatever anybody's balance is. ]]
	Interval = 300,

	--[[ Seconds after the server starts before the FIRST roll. Short, not zero: `Workspace.CarSystem`
		is what a display car is cloned out of and the place is still settling in the first moment of
		a server's life. Nobody has walked to the plaza by then. ]]
	FirstDelay = 3,

	--[[ Relative chance of each world's cars, indexed by world. Normalised at roll time, so these
		are ratios and not percentages and a fifth world can be added without rebalancing the other
		four. Within a world every car is equally likely. ]]
	WorldWeights = { 1, 0.4, 0.15, 0.05 },

	--[[ No two stands may offer the same BODY at once. Not the same key: two colours of one Camaro
		parked on opposite sides of the island is a market with a choice in it, and that is fine. The
		same body twice in four lots reads as the roll being broken. Bounded re-rolls, then whatever
		comes out, because a roster smaller than the number of lots must not spin forever. ]]
	MaxRerolls = 12,

	--[[ Refuse to sell a car the buyer already owns (body AND colour — `GarageConfig.carKey`).

		THE ONLY RULE HERE THAT IS NOT SHARED WITH BANKING, and it exists to stop the game taking
		money for nothing: `awardCar` sells a duplicate back at `SellSeconds` of its income, so a
		player who bought one would pay `Price.Markup` times that and get a fraction of it back. The
		bubble says so rather than the press failing silently — see `Lines.Owned`. ]]
	RefuseOwned = true,
}

-- === What it costs ==========================================================

--[[ The price of one deal.

	    price = round( GarageConfig.valueOf(tier) * Markup * jitter )

	`valueOf` is what that car SELLS for — `SellSeconds` (240) of its own parked income — so the
	markup is expressed against the one number the rest of the economy already prices cars in. There
	is deliberately no second price table; that is `GarageConfig`'s header note 3, and it holds here
	for the same reason it holds for a customer's tip: the moment what a car costs is set
	independently of what it earns, "which car is worth buying" stops having one answer.

	=== WHY 3, AND WHY IT MAY NEVER BE 1 =====================================================

	The floor is arithmetic (header note 3). At a markup of 1 or less, buy-then-bank-the-duplicate
	returns more than it cost and the game is a money printer. `Offer.RefuseOwned` closes that door
	from the other side, but a price below the sell value would still mean a deal is worth more
	broken up than kept, which is not a market anybody should be able to notice.

	Above the floor it is a payback question. A bought car that lands on a free bay earns its tier's
	rate, so it pays for itself in `Markup * SellSeconds` seconds — twelve minutes at 3. That is
	fast enough that buying is obviously worth doing and slow enough that it is an investment rather
	than a trade: the alternative use of the money is an upgrade, and the upgrade ladder's own
	paybacks are the thing this has to sit next to. Under about 2 the market starts to beat running
	for cars outright; over about 6 nobody buys anything and the stands are scenery.

	AND MOST BUYS DO NOT PAY BACK AT ALL. A full lot only takes a new car if it beats the worst one
	parked (`GarageConfig.Banking.UpgradeWorstBay`), so once a player's six bays are good the deals
	they buy earn nothing and are bought for the collection. That is the intended shape and it is
	why the markup can afford to be this generous. ]]
CarDealConfig.Price = {
	Markup = 3,

	--[[ Plus or minus, rolled per offer, so the same car is not the same price twice and walking
		past a stand is worth doing. At 0.18 the effective markup runs 2.46 to 3.54, which never
		approaches the floor above — check that again if either number moves.

		THERE IS NO "DEAL!" BADGE and there should not be one: the player has no way to know what
		the un-jittered price would have been, so a badge would be the game asserting a bargain
		rather than showing one. What the jitter is for is that two Chargers a rotation apart are
		visibly different offers. ]]
	Jitter = 0.18,

	--[[ Round the final number to this many significant figures, so a price reads as a price. Four
		gives "$2,351,000" rather than "$2,350,617" — a number a player can hold in their head and
		compare against their balance at a glance, which is the whole job of the label. Whole dollars
		below the point where that matters, because `formatCash` prints those exactly. ]]
	SignificantFigures = 4,
}

-- === Driving it away =======================================================

--[[ WHAT HAPPENS IN THE SECOND AFTER THE MONEY LEAVES.

	The old answer was nothing. The car you bought was banked, the display clone stayed on its plinth
	with ALREADY YOURS written over it until the next rotation, and the thing you had actually
	acquired was a row on a screen you had to walk home to look at. That is a purchase confirmation,
	not a purchase.

	The new answer is that you get in and drive off. The display clone is destroyed, `LobbyCarService`
	stands a real CarBones rig in the same bay, and the buyer is put in the driver's seat of it. The
	same car, in the same colour, on the same square of road, one second later and now with an engine
	in it.

	=== THIS IS THE LOBBY-CAR PATH AND NOT A SECOND ONE =======================================

	Nothing here spawns a car. It calls `LobbyCarService:setLobbyCar` with a placement override, and
	everything that service already guarantees applies unchanged: one car per player (so buying a
	second deal puts the first one away), the paint and the plate and the doors and the weather, the
	collision group, the deferred entry beat, and the despawn on death or on entering a race.

	The one thing the override changes is WHERE. `setLobbyCar` normally rings the placement around
	the player who asked; here it is told the exact frame instead, because the bay was already probed
	for ground, flatness, clearance and room to pull out of when it was chosen. That is a stronger
	claim about the spot than the ordinary placement search can make about the ground beside a player
	who might be standing anywhere.

	=== WHY THE SALE ALSO MOVES THE BAY =======================================================

	It has to. The bought car is now standing in that bay under its own physics, so leaving the stand
	there would mean rolling a fresh display clone straight into the middle of a real car. Re-rolling
	the stand to a new spot is what empties the square for the car that was just sold, and it has the
	side effect the market wanted anyway: the deal you bought is gone from where it was, and the
	replacement is somewhere else on the island. ]]
CarDealConfig.Handover = {
	--[[ Master switch for the drive-away. Off, a purchase is exactly the old one: the money moves,
		`awardCar` banks the car, the display clone stays where it is until the stand re-rolls, and
		the buyer walks home. It is the A/B for whether this is worth what it costs, which is a
		310-instance rig clone on the accepted path of a prompt. ]]
	Enabled = true,

	--[[ Put the buyer in the driver's seat, rather than leaving the car standing there with its own
		entry prompt lit for them to walk round to.

		SEATED, AND IT IS THE WHOLE POINT. `Seat:Sit` welds the character in from wherever they are
		standing, which is at most `Prompt.MaxDistance` away, so there is no walk and no teleport to
		write. A player who wanted the walk still has it: getting out is stock, and the car is theirs
		and standing right there.

		The one case this deliberately does not special-case is a buyer already sitting in something.
		`Sit` takes them out of whatever they are in and puts them in this, which is the answer that
		needs no extra rule and is what somebody who just bought a car meant. ]]
	SeatBuyer = true,

	--[[ Seconds to wait after the car is parented before sitting the buyer in it.

		NOT ZERO, AND THE REASON IS PHYSICS RATHER THAN REPLICATION. A rig arrives unanchored and
		spends its first frames settling onto its suspension; sitting somebody into a seat inside that
		window welds them to an assembly that is still resolving, which on this rig reads as the car
		twitching under the driver as they appear. A tenth of a second is enough for the wheels to
		take the weight and is under the threshold where the player notices a gap at all. ]]
	SeatDelay = 0.1,

	--[[ Roll this stand a fresh car in a fresh bay as soon as the sale completes, rather than leaving
		an empty square of paint until the next rotation.

		IMMEDIATELY, BECAUSE THE ALTERNATIVE IS A BAY WITH A REAL CAR IN IT and a stand claiming to
		be selling it. The delay is what stops the new car appearing in the same frame the old one
		vanishes, which reads as the sign flickering rather than as the market moving on. ]]
	RerollOnSale = true,
	RerollDelay = 0.6,

	--[[ ...but not until the buyer has driven out of the stall.

		THIS IS THE ONE THING A FIXED BAY COSTS. The handover seats the buyer in their new car where
		it stands, which is in the middle of the stall the deal was in, and the stand no longer moves
		away from it. So the restock waits for the stall to be clear, asking every `RestockWait`
		seconds and giving up after `RestockFor`.

		3 SECONDS IS A CHECK NOBODY CAN SEE and it is a walk over one model per player, so the poll
		is not worth being clever about. 120 is long enough for somebody to buy a car, sit in it,
		read the sign and pull away, and short enough that a stall somebody parked in and abandoned
		is back in the market within the same session — the next rotation restocks it as soon as
		they are gone. ]]
	RestockWait = 3,
	RestockFor = 120,
}

-- === Who is selling =========================================================

--[[ THE SELLER IS ONE OF YOUR OWN FRIENDS — their real avatar, built from their real
	`HumanoidDescription`, with their name on the bubble over their head.

	CLIENT-SIDE, UNLIKE A DEALERSHIP CUSTOMER, and the split is the same one `StealController` makes:
	the only friends list a client needs is its own, and nothing about the seller is authoritative.
	`CustomerService` builds its rigs on the server because a customer HANDS OVER CASH and stands in
	a showroom other players walk through; a seller does neither. The money moves on a prompt the
	server owns, and the person beside the car is chrome.

	The payoff is bigger here than it is for a customer, too: one stand per lot means at most one
	face on screen at a time, standing still next to a car with a price over it. A player who
	recognises the face is a player who is about to tell that friend about it.

	A player with no friends, or a friends endpoint having a bad day, gets `Fallback` and nothing
	else about the market changes. ]]
CarDealConfig.Dealer = {
	Enabled = true,

	Friends = {
		Enabled = true,
		--[[ How many faces the session has. Rigs are templates and get one clone per stand, so this
			wants to be at least one per LOT for nobody to see the same friend twice, which on this map
			is four. Built once, at start-up, and reused for every rotation — the friends list behind
			them is not going to have changed by the next one. ]]
		Count = 4,
		--- How deep into the friends list to read before choosing. The choice is a shuffle over
		--- everything read rather than the first `Count`, or a player with 200 friends gets the same
		--- three sellers for the entire session.
		Scan = 60,
	},

	--[[ The stranger who turns up when the friends list has nothing for us: a nameless dealer in one
		of three colourways.

		COLOURED RATHER THAN LEFT EMPTY. An empty `HumanoidDescription` builds a BLACK avatar, which
		reads as a bug rather than as a person — the trap `StealController.NOOB_COLORS` and
		`CustomerConfig.Fallback` both document.

		NO NAME, deliberately, and the bubble drops to "SELLING" rather than inventing one. A made-up
		seller is a person this game made up, and the same three of them would be standing in every
		server. ]]
	Fallback = {
		Palettes = {
			{ Head = Color3.fromRGB(255, 204, 51), Body = Color3.fromRGB(17, 17, 17), Limbs = Color3.fromRGB(27, 42, 53) },
			{ Head = Color3.fromRGB(204, 142, 105), Body = Color3.fromRGB(13, 105, 172), Limbs = Color3.fromRGB(23, 25, 28) },
			{ Head = Color3.fromRGB(215, 197, 154), Body = Color3.fromRGB(107, 50, 124), Limbs = Color3.fromRGB(17, 17, 17) },
		},
	},

	--[[ Where they stand, in the bay's own frame: +X is across the bay to the right, +Z is the way
		the car's nose points, which is out of the bay and into the road.

		BESIDE THE BAY AND SLIGHTLY FORWARD OF IT, which is where the reference card puts them and
		where a person selling a car actually stands: far enough to the side that they are not hidden
		behind the car from any approach, far enough forward that they are between the player and the
		car rather than behind it.

		`SideMargin` IS A MARGIN AND NOT A DISTANCE, which is what changed when the bays became the
		map's own stalls. It used to be a flat 12 studs — the old painted bay's half-width plus three
		— and a fixed number is now wrong twice over: these stalls are 25 to 30 wide rather than 16,
		so 12 would stand the seller INSIDE the paint beside the car, and the next map's lot may be
		wider again. The service adds this to the stall's own half-width, so they stand three studs
		clear of the line whatever the lot measures.

		WHICH SIDE that lands on is `Lots.Stall.Side`'s note: the deal takes the LEFT-hand stall of a
		lot precisely so that the car's right-hand side, which is where this puts them, is the open
		end of the rank rather than the middle of the next stall along. ]]
	SideMargin = 3,
	Ahead = 6,

	--[[ Which way they face, degrees off "straight out of the bay". Turned back toward the car they
		are selling, because a seller facing dead ahead reads as somebody waiting for a bus, and 25
		degrees is enough to be a stance without turning their back on the buyer. ]]
	FaceDegrees = -25,

	--[[ How high the seller's root sits above the pavement, WHEN THE RIG CANNOT SAY.

		THE RIG USUALLY CAN. A real avatar is placed at `Humanoid.HipHeight + HumanoidRootPart.Size.Y/2`,
		which is the only expression that puts FEET on the floor for every body scale — measured on
		three live friend rigs, the root ranges from 2.6 to 3.4 studs up depending on how tall that
		person's avatar is, and a fixed number floats the short ones and sinks the tall ones. This is
		the fall-back for a rig with no Humanoid, and it is also what the SERVER uses to place the
		bubble's anchor, which has no rig to ask (`CarDealService._buildStand`). ]]
	RootHeight = 3,

	--[[ The idle clip, played through `Modules/RigAnimator`.

		A rig built from a `HumanoidDescription` DOES NOT ANIMATE ITSELF — the `Animate` script that
		makes a character move is a LocalScript belonging to a player's own character, and an NPC
		nobody spawned as a player has nobody to run one. Without this the seller stands in an
		A-pose, which reads as a broken model rather than as a person. The id is Roblox's own stock
		R15 idle, which is also why the rig is forced to R15 whatever the friend actually wears. ]]
	Animations = {
		Enabled = true,
		Clips = {
			Idle = { Id = 507766666, Length = 10, Looped = true },
		},
	},
}

-- === The button =============================================================

--[[ The buy prompt: a `ProximityPrompt` on the bay's floor, drawn by us rather than by Roblox.

	A PROMPT AND NOT A REMOTE FROM A BUTTON, which is the house pattern (`GarageConfig.Picker` raises
	one on every podium) and buys three things that a billboard button would each have to be given
	separately: it works on a keyboard, a gamepad and a touchscreen without a line of per-device
	code; it is the server that decides you are close enough; and `Triggered` arrives on the server
	already carrying which player pressed it, so there is no request to validate.

	`Style = Custom` because the kit draws its own everything (`CustomerConfig.Bubble` has the
	argument at length) — `CarDealController` builds the green pill out of `UIAssets.Pill.Green` and
	hangs it under the price. The one thing Custom costs is the touch tap target, which Roblox stops
	providing: the controller puts a transparent `TextButton` over the pill and drives
	`InputHoldBegin`/`InputHoldEnd` from it, exactly as Roblox's own reference implementation does. ]]
CarDealConfig.Prompt = {
	ActionText = "Buy Car",
	Key = Enum.KeyCode.E,
	GamepadKey = Enum.KeyCode.ButtonX,

	--[[ HELD, NOT TAPPED, AND THIS IS A SAFETY RAIL RATHER THAN A FLOURISH. There is no confirmation
		screen between the press and the money leaving — a tap-to-buy on a stand a player walks past
		while pressing E to get into their lobby car would cost them millions and there is no undo.
		0.6s is long enough that it cannot be an accident and short enough that it never feels like
		the game is arguing with you. The pill fills left to right for the duration, which is the
		same bar language the nitro and HP gauges use. ]]
	HoldDuration = 0.6,

	--[[ Studs, measured from the middle of the bay. Comfortably past where the seller stands (about
		16 from the bay's centre on this map's stalls) so the prompt is up while you are looking at the
		person, and nowhere near the 380 studs between the two closest lots, so it can never be up for
		two deals at once. ]]
	MaxDistance = 24,

	--- Off: the car itself stands between the prompt's part and most of the places a player can
	--- approach from, so a line-of-sight test would hide the prompt from anybody at the back of the
	--- bay. Roblox excludes the prompt's own parent from the check, not its siblings.
	RequiresLineOfSight = false,

	--[[ Per-player floor between accepted presses. Same shape and reason as
		`GarageConfig.Picker.Cooldown`: a purchase writes the profile, rebuilds a lot and republishes
		four attributes, and the trigger is client-driven. Stamped on the ATTEMPT, so a refusal costs
		the same as a sale. ]]
	Cooldown = 0.5,
}

-- === What the stand says ====================================================

--[[ The bubble over the seller: what is for sale, what it costs, and the button.

	OUR OWN BILLBOARD, adorned to an ATTACHMENT ON THE BAY rather than to the seller's head. That is
	not a shortcut, it is what makes the sign independent of the person. Building a friend's
	avatar is three web calls deep and any of them can fail; a bubble pinned to a head would then be
	a market with no prices on it. Pinned to the stand, the seller is free to arrive late, fail to
	arrive at all, or be replaced at the next rotation, and the sign never moves.

	Sized in STUDS on its Scale component, so it is a physical object standing over a car that gets
	smaller as you walk away. `MaxDistance` is what stops one being legible from across the island. ]]
CarDealConfig.Bubble = {
	Enabled = true,

	--[[ Studs, and it is the size of the PANEL rather than of the whole billboard: `Clock` hangs
		another strip underneath it. The pill row is included here, and it is empty until the prompt
		is up — see `Rows`.

		11 / 1.5882 IS `UIAssets.Page.Panel`'S OWN 1023x644 — 2026-08-26, up from a flat 6.4. The panel
		is that texture now rather than a `#364157` Frame with a `UICorner` on it, and this kit's
		borders and inner rims come from LAYER STYLES: they stay 5px whatever size the art is drawn at,
		so they come out uneven the moment it is stretched off its own aspect. At 11 x 6.4 the top and
		bottom borders would have rendered at 92% of the sides.

		The height carries the change rather than the width, and it is 0.53 studs — the sign grows by
		about a twelfth and everything inside it is a fraction of this, so nothing else moves. Widening
		instead would have pushed the sign out past the stand it belongs to. ]]
	Size = Vector2.new(11, 6.926),
	--[[ Studs of clear air between the top of the seller and the BOTTOM of the sign. The anchor the
		server plants is at head height (feet + `Dealer.RootHeight` x 2) and the client adds this plus
		half the bubble, so the number means what it says at any bubble size.

		1.2 was set against a playtest: at 2.6 the sign floated a seller's own height above them and
		read as belonging to the stand rather than to the person. It has to clear a tall hat, not a
		flagpole. ]]
	HeadOffset = 1.2,
	--- Past this many studs it is not drawn. Sized so a bay is legible from most of the way across a
	--- carriageway, and so a deal on the far side of the island is not a sign floating over the map.
	MaxDistance = 220,

	--[[ === THE BUYER'S SIGN — 2026-10-15 ===
		WAS: the kit's navy page panel with five free-floating rows (`Rows` below). IS: the buyer
		offer's own billboard, `MainUIV2.Screens.BuyerSign` via `BuyerOfferSign.buildKit` (the blue
		header, the white body, the money tint). That makes a car on sale and an offer on your car
		read as one family. The buyer's Comparison and Rating lines are hidden, and the BUY CAR pill
		takes their band. It was cut for this exact `Size`, so nothing here is re-measured.
		Off, or in a place without the template: the navy panel, exactly as before. ]]
	KitStyle = true,

	--[[ Fractions of the bubble's own height, top to bottom. Five bands: who is selling, what it is,
		the word PRICE, the number, and the pill. The name and the price are the two big ones because
		they are the two things a player is deciding between. ]]
	Rows = {
		Seller = { Y = 0.02, Height = 0.15 },
		Body = { Y = 0.16, Height = 0.26 },
		PriceCaption = { Y = 0.42, Height = 0.13 },
		Price = { Y = 0.54, Height = 0.22 },
		Pill = { Y = 0.775, Height = 0.2 },
	},

	--- The `car ui.psd` kit. `Panel` and `Stroke` are gone with the flat frame they painted — the
	--- panel is `UIAssets.Page.Panel` now and draws its own face, border, rim and corners.
	Colors = {
		--[[ The kit's face `#28334B`, painted BEHIND the panel texture rather than being the panel.
			Every navy surface in `UIAssets` is drawn at 80% so gameplay shows faintly through a page you
			have opened; this is a sign standing in a plaza in daylight, and at 80% the showroom behind it
			read through the price. The art composites 80% of `#28334B` over `#28334B` and lands exactly
			where it was drawn. Same call as the garage-door sign's and the speech bubble's. ]]
		Face = Color3.fromRGB(40, 51, 75), -- #28334B
		Caption = Color3.fromRGB(206, 214, 232),
		Price = Color3.fromRGB(13, 180, 21), -- #0DB415, the kit money green
		--- What the price turns when you cannot afford it. The kit has no red; this is the pill
		--- palette's own red, dimmed to sit on navy rather than shout off it.
		PriceShort = Color3.fromRGB(226, 96, 96),
		--- ...and what the whole sign turns when the car is already yours.
		Owned = Color3.fromRGB(158, 176, 204),
		PillText = Color3.new(1, 1, 1),
	},

	--- Seconds the bubble takes to fade in when a stand streams in, and to cross-fade when the
	--- offer under it changes. Short: this is a sign turning over, not an event.
	FadeSeconds = 0.2,
	SwapSeconds = 0.3,

	--[[ NEW CAR IN 4:32 — a strip hanging UNDER the sign, and the one piece of this feature that
		used to live on the player's screen.

		IT WAS A HUD CARD AND IT IS NOT ONE ANY MORE (the user's call, 2026-08-24). A lobby screen
		already carries the rail, the cash pill and the Play button; it does not need a shop clock
		pinned to a corner of it as well, and a market's clock is exactly the sort of chrome that
		turns a HUD into a dashboard. So it moved to where the market is — a physical strip in the
		plaza, hanging off the sign it is actually about.

		AND IT ARRIVES ON APPROACH, not at the bubble's full `MaxDistance`. Past `NearDistance` a
		sign is a car and a price; inside it the deadline fades in under the price. Three gold clocks
		ticking away across the island's skyline would be the card's clutter one step further off,
		and at that range the number is unreadable anyway.

		THE TRADE, SAID OUT LOUD: a player standing at their own plot now has no idea a rotation is
		coming. That is what taking it off the screen costs and it is accepted deliberately. If the
		plaza ever needs pulling at range, the answer is a landmark that can be seen from there — a
		clock on something tall in the middle of the ring — and not the card coming back. ]]
	Clock = {
		Enabled = true,

		--- Studs, ADDED under `Size`: the billboard ends up `Size.Y + Gap + Height` tall and the
		--- panel keeps exactly `Size.Y` of it, so every row fraction above is untouched by this.
		Height = 1.15,
		--- Studs of clear air between the bottom of the panel and the top of the strip. It is what
		--- makes this a tag hanging off the sign rather than a sixth row of it.
		Gap = 0.35,
		--- Fraction of the bubble's WIDTH, for the same reason.
		Width = 0.62,

		--[[ Studs from the sign at which the strip appears, and the extra it takes to lose it again.
			The two differ because a player standing exactly on one line would otherwise get a clock
			that flickers in time with their idle animation. Measured to the bubble's own anchor, so
			it is a distance to the SIGN rather than to a stand's origin.

			100 IS MEASURED OFF THE BAY, not picked, and what it measures changed when the deals
			stopped sharing a plaza. The four lots are 380 studs apart at the very closest, so this can
			never be the radius that lights two at once. What it is instead is APPROACH: a hundred studs is about four
			seconds of driving, which is long enough to read a countdown and decide whether the car
			you are looking at is worth stopping for. Outside it there is nothing ticking on the
			skyline, which is the same thing this number always bought. ]]
		NearDistance = 100,
		Hysteresis = 10,

		PanelColor = Color3.fromRGB(20, 27, 45),
		PanelTransparency = 0.2,
		CaptionColor = Color3.fromRGB(206, 214, 232),
		--- The kit's PLAY gold, which in this palette is what "the thing you are heading toward" is
		--- painted. Same colour, and the same meaning, as the getaway card's bar.
		ClockColor = Color3.fromRGB(255, 198, 0),

		--[[ The last few seconds, when the clock turns over. It pulses once a second below this,
			which is the restrained version of a countdown going loud: a few ticks that grow 8% and
			settle, not a flashing sign. ]]
		UrgentSeconds = 5,
		UrgentColor = Color3.fromRGB(255, 138, 0),
		PulseScale = 1.08,
		PulseTime = 0.18,

		FadeSeconds = 0.25,
	},
}

--[[ Everything the bubble says. Every line goes through `oneLine` before it is drawn — `TextScaled`
	maximises font size subject to the laid-out text FITTING, which means it wraps in preference to
	shrinking, so a two-word caption becomes two tiny lines unless its spaces are non-breaking. Same
	rule and same fix as `PlotConfig.SignNonBreakingSpace` and `CustomerConfig.lineFor`.

	NO EM DASHES AND NO PUNCTUATION THAT NEEDS A FONT. These are drawn in Ubuntu Bold at whatever
	size a 11-stud billboard gives them, on a screen that may be a phone. ]]
CarDealConfig.Lines = {
	--- `%s` is the friend's display name.
	SellerNamed = "%s IS SELLING",
	--- ...and what a nameless fallback dealer says instead.
	SellerAnonymous = "SELLING",
	PriceCaption = "PRICE",
	Buy = "BUY CAR",
	--- Shown in place of the price caption and the price when the buyer already owns this exact car.
	Owned = "ALREADY YOURS",
	--- ...and under it, so the refusal is explained rather than just enforced.
	OwnedCaption = "IN YOUR COLLECTION",
	--- The clock strip's caption, with `Bubble.Clock`'s countdown drawn after it. NEW CAR rather
	--- than NEW OFFER: what turns over is the car parked in front of them, and a player reading this
	--- is looking straight at the thing about to be replaced.
	NewCar = "NEW CAR IN",
}

-- === Asking about a deal ====================================================

--- `TextScaled` would sooner break a caption onto a second line than pick a smaller font. Every
--- one-line label this feature draws goes through here first. See `Lines`.
local NBSP = utf8.char(0xA0)

function CarDealConfig.oneLine(text: string): string
	return (string.gsub(text, "%s+", NBSP))
end

--[[ Round to `Price.SignificantFigures`, so a price reads as a price rather than as a measurement.
	Numbers small enough that every digit is already meaningful are left exactly as they are — the
	bottom of the ladder is a Tier 1 car at 1,440, and rounding that to 1,440 changes nothing. ]]
local function roundSignificant(value: number, figures: number): number
	if value <= 0 then
		return 0
	end
	local magnitude = math.floor(math.log10(value))
	local step = 10 ^ math.max(0, magnitude - (figures - 1))
	return math.max(1, math.round(value / step) * step)
end

--[[ What one deal costs, in whole dollars. `roll` is the jitter for THIS offer, in -1..1, so the
	caller owns the generator (the server rolls it once and stamps it on the stand) and this stays a
	pure function that the client could check the same way if it ever needed to.

	A tier off the ladder prices at 0, which every caller treats as "not for sale" — the same safe
	direction `GarageConfig.valueOfCollection` takes for a body no world has. ]]
function CarDealConfig.priceFor(tier: unknown, roll: number?): number
	local value = GarageConfig.valueOf(if type(tier) == "number" then tier else nil)
	if value <= 0 then
		return 0
	end
	local jitter = 1 + math.clamp(roll or 0, -1, 1) * CarDealConfig.Price.Jitter
	return roundSignificant(value * CarDealConfig.Price.Markup * jitter, CarDealConfig.Price.SignificantFigures)
end

--[[ Roll one body off the whole roster, weighted by `Offer.WorldWeights`.

	`taken` is a set of body names already on a stand this rotation; a draw that lands on one of them
	is retried up to `Offer.MaxRerolls` and then accepted anyway. Bounded rather than looped to
	exhaustion for the reason `Offer.MaxRerolls` gives: a roster smaller than the number of lots must
	not spin forever, and a repeated car is a worse-looking market rather than a broken one. ]]
function CarDealConfig.rollBody(rng: Random, taken: { [string]: boolean }?): (string?, number?)
	local weights = CarDealConfig.Offer.WorldWeights
	local total = 0
	for index in WorldConfig.Worlds do
		total += math.max(0, weights[index] or 0)
	end
	if total <= 0 then
		return nil, nil
	end

	local function draw(): (string?, number?)
		local pick = rng:NextNumber() * total
		for index, world in WorldConfig.Worlds do
			pick -= math.max(0, weights[index] or 0)
			if pick <= 0 then
				local cars = world.Cars
				if #cars == 0 then
					return nil, nil
				end
				local body = cars[rng:NextInteger(1, #cars)]
				return body, WorldConfig.TierOfBody[body]
			end
		end
		return nil, nil
	end

	for _ = 1, math.max(1, CarDealConfig.Offer.MaxRerolls) do
		local body, tier = draw()
		if body and tier and not (taken and taken[body]) then
			return body, tier
		end
	end
	return draw()
end

--[[ Seconds remaining, as `M:SS`. Rounded UP, so the last second reads "0:01" for a whole second
	and the strip never sits on a zero it has not acted on — the same rounding, for the same reason,
	as `GetawayConfig.Hud.Card.SecondsFormat`. ]]
function CarDealConfig.formatCountdown(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

local function hexOf(colour: Color3): string
	return string.format(
		"%02X%02X%02X",
		math.round(colour.R * 255),
		math.round(colour.G * 255),
		math.round(colour.B * 255)
	)
end

--[[ The clock strip's whole line, as ONE piece of rich text: the caption in the label's own colour
	and the number in `Bubble.Clock.ClockColor`, or `UrgentColor` over the last few seconds.

	ONE LABEL AND NOT TWO, because `TextScaled` sizes each label to its own box — a caption and a
	number sitting in boxes of different widths come out at two different font sizes, which is the
	one thing a two-part line must not do. Rich text colours a span inside a single box instead.

	THE SEPARATOR IS NON-BREAKING like every other space this feature draws (`oneLine`): a plain one
	there is exactly where `TextScaled` would break the line rather than shrink the font. The spaces
	inside the tag are ordinary ones — they are markup, they are never drawn, and an NBSP in there
	would not parse. ]]
function CarDealConfig.clockLine(seconds: number): string
	return CarDealConfig.clockLineFor(CarDealConfig.Lines.NewCar, seconds)
end

--[[ The same line with any caption — 2026-09-28, for the buyers' signs (`BuyerController`), which are
	this bubble the other way round and wear this clock with "OFFER ENDS IN" on it. Lifted out rather
	than copied so the two strips cannot drift on the urgent colour, the rounding or the markup. ]]
function CarDealConfig.clockLineFor(caption: string, seconds: number): string
	local clock = CarDealConfig.Bubble.Clock
	local colour = if seconds <= clock.UrgentSeconds then clock.UrgentColor else clock.ClockColor
	return CarDealConfig.oneLine(caption)
		.. NBSP
		.. string.format('<font color="#%s">%s</font>', hexOf(colour), CarDealConfig.formatCountdown(seconds))
end

-- Approved economy balance, 2026-10-04.
--- 4 since 2026-10-08 (was 2.5): at 2.5x a bought car repaid itself in tips in ~7 minutes, so buying
--- beat stealing. Still repays inside a session; see `CustomerConfig.Tip.ByWorld` for the tip side.
CarDealConfig.Price.Markup = 4
CarDealConfig.Price.Jitter = 0.10
CarDealConfig.Offer.WorldWeights = {1, 0.4, 0.15, 0.05, 0.02}

-- Unlocked-world dealer stock, 2026-10-04.
CarDealConfig.StockPrefix = "PersonalStock"
function CarDealConfig.stockAttribute(attribute: string, highest: number): string
 return CarDealConfig.StockPrefix .. tostring(highest) .. attribute
end
function CarDealConfig.rollBody(rng: Random, taken: {[string]: boolean}?, highest: number?): (string?, number?)
 local Traffic = require(script.Parent.TrafficConfig)
 local Balance = require(script.Parent.BalanceConfig)
 local top = math.clamp(math.floor(highest or 1), 1, #WorldConfig.Worlds)
 local total = 0
 for world = 1, top do total += Balance.WorldWeightsByAge[top - world + 1] end
 for _ = 1, CarDealConfig.Offer.MaxRerolls do
  local roll, world = rng:NextNumber() * total, top
  for index = top, 1, -1 do
   roll -= Balance.WorldWeightsByAge[top - index + 1]
   if roll <= 0 then world = index; break end
  end
  local tiers = Traffic.tiersFor(world)
  local _, tier = Traffic.rollRung(rng, tiers, Traffic.topTileFor(world) or 6, 1)
  local available = {}
  for _, body in tier.Bodies do available[body] = not (taken and taken[body]) end
  local body = Traffic.rollBody(rng, tier, available)
  if body then return body, WorldConfig.TierOfBody[body] end
 end
 return nil, nil
end

return CarDealConfig
