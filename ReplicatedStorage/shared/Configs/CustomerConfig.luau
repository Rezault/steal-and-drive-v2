--[[
	CustomerConfig
	--------------
	The people who walk into your dealership, look at what is parked, say something and pay you for
	the privilege. Polish.md's "Customers: walk around, look at cars, say a chat bubble then give
	cash", and the one thing on a dealership plot that moves on its own.

	THEY ARE YOUR ACTUAL FRIENDS. `Friends` below builds each customer from a real Roblox avatar off
	the plot owner's friends list, with their username over its head — which is the whole reason this
	is worth more than a crowd of blocky extras, and the same trick `StealConfig.Driver.Friends`
	plays with the motorist you throw out of a car. A player with no friends, or a friends endpoint
	having a bad day, gets the blocky extras and nothing else changes.

	FOUR THINGS TO KNOW BEFORE TUNING ANY OF IT.

	1. A TIP IS SECONDS OF THE BAY'S OWN INCOME. There is no second price table, and there should
	   never be one — that is `GarageConfig`'s header note 3, made for the sale price, and it holds
	   here for the same reason: the moment what a customer pays is set independently of what the car
	   earns, "which car is worth parking" stops having one answer. See `Tip`.

	2. THEY ONLY LOOK AT BAYS WITH CARS ON THEM, and a lot with nothing parked gets no customers at
	   all. That is not an optimisation. An empty bay is the thing the whole run loop is trying to
	   fill (`GarageConfig.Collect.EmptyText` says as much), and a customer admiring an empty podium
	   would be the game telling the player it does not matter whether they fill it.

	3. THE PICK IS WEIGHTED BY WHAT A BAY EARNS, so a crowd gathers around your best car. This is the
	   one behaviour here that is load-bearing rather than flavour, and `Visit.RateBias` has the
	   argument: chosen uniformly, adding a cheap car to a spare bay would LOWER the average tip, so
	   filling your lot would cost you money. Weighted, it never can.

	4. NOTHING HERE IS AUTHORED IN THE MAP. Unlike the collect mats, the race pads and the upgrade
	   boards, a customer needs no instance in the place: where they stand is derived from the bay
	   podium they are looking at (`View`), and where they come in is one plot-local point (`Arrival`)
	   in the frame `docs/MapLayout.md` §3.3 defines. Six identical plots, so one point serves all
	   six — the same reasoning `PlotConfig.Fallback` uses for the spawn pad.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ For `levelOf` alone, and for the non-breaking space. It requires nothing itself, so this
	cannot cycle — the same reason `GarageConfig` can require `PaintConfig`. ]]
local UpgradeConfig = require(ReplicatedStorage.shared.Configs.UpgradeConfig)
--[[ For `Income.Passive` alone: which of the two tip prices is live (`Tip`). A config requiring a
	config; GarageConfig requires only the world, paint and weather configs, none of which reach back
	here, so the order cannot cycle. ]]
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local CarNameConfig = require(ReplicatedStorage.shared.Configs.CarNameConfig)
--- For `tipScaleOf`'s body -> world lookup. Requires only `BalanceConfig`, so it cannot cycle back here.
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local CustomerConfig = {}

-- Master switch. Off = no rigs are built and no crowd is bound, so a lot behaves exactly as it did
-- before this file existed. It is also the A/B for what the customers are worth: the passive income
-- is untouched by any of this.
CustomerConfig.Enabled = true

-- === Who they are ===========================================================

--[[ THE CUSTOMER IS ONE OF THE PLOT OWNER'S FRIENDS — their real avatar, built from their real
	`HumanoidDescription`, wearing their username on the name tag.

	SERVER-SIDE, UNLIKE THE THROWN MOTORIST. `StealController` builds its friend rigs on the client
	because the only friends list it needs is the local player's own; a customer stands in a
	showroom that OTHER players walk through, so it has to exist for everyone, and the cash it hands
	over has to be written by the only thing allowed to write cash. That makes it three web calls
	deep on the server — the friends list, one description per friend, one rig per description — and
	every one of them can fail. All of it happens once per plot claim, in its own thread, and every
	failure degrades to the blocky extra below rather than to no customer.

	`Count` IS HOW MANY FACES A LOT HAS, not how many friends are read. Rigs are templates and get
	cloned per customer, so three covers a crowd of three without anybody seeing themselves twice.

	`Scan` is how deep into the friends list we read before choosing, and the choice is a shuffle
	over everything read rather than the first `Count` — otherwise a player with 200 friends gets the
	same three visitors for the entire session. ]]
--[[ === MORE FACES, AND THEY CHANGE — 2026-10-11 ===
	The owner: "it's only the same 3 ones over and over; maybe make it choose a wider variety from
	your friends list, maybe even the whole friend list". WAS `Count = 3` faces built once at claim
	from the first 60 friends read, and those three for the whole session. NOW:

	  `Count` 8      faces on hand at once — still templates cloned per customer, so 8 rigs held in
	                 memory per lot, built one after another (the first visitor need not wait for all
	                 eight: the pool is used as it fills).
	  `Scan` 200     the whole list: Roblox caps friends at 200, and `MAX_FRIEND_PAGES` (4 x 50) is
	                 the same number, so every friend is a candidate.
	  `Rotate`       every `Every` customers who leave a lot, ONE face nobody is wearing right now is
	                 retired and a friend not yet seen this session built in its place; the retired
	                 friend goes to the back of the queue. So over a session the showroom works its way
	                 through the whole friends list, and memory stays at `Count` rigs. Two web calls per
	                 swap, which at `Every = 2` is a couple a minute — nothing.

	`Rotate.Enabled = false` with `Count = 3, Scan = 60` is the old crowd exactly. ]]
CustomerConfig.Friends = {
	Enabled = true,
	Count = 8,
	Scan = 200,
	Rotate = { Enabled = true, Every = 2 },
}

--[[ The extra who turns up when the friends list has nothing for us: a nameless shopper in one of
	four colourways.

	COLOURED RATHER THAN LEFT EMPTY. An empty `HumanoidDescription` builds a BLACK avatar, which
	reads as a bug rather than as a person — the same trap `StealController.NOOB_COLORS` documents.

	NO NAME TAG, deliberately. A friend's customer carries their username because that is the point
	of them; giving a made-up name to a stranger would mean inventing a person, and a player who
	looked twice would notice the same four "people" visiting every dealership in the server. ]]
CustomerConfig.Fallback = {
	-- One rig per entry. Four is enough that a crowd is not obviously one model repeated, and every
	-- one of them is a web call at start-up.
	Palettes = {
		{ Head = Color3.fromRGB(255, 204, 51), Body = Color3.fromRGB(13, 105, 172), Limbs = Color3.fromRGB(245, 205, 48) },
		{ Head = Color3.fromRGB(255, 204, 51), Body = Color3.fromRGB(196, 40, 28), Limbs = Color3.fromRGB(40, 127, 71) },
		{ Head = Color3.fromRGB(204, 142, 105), Body = Color3.fromRGB(75, 151, 75), Limbs = Color3.fromRGB(35, 71, 100) },
		{ Head = Color3.fromRGB(215, 197, 154), Body = Color3.fromRGB(107, 50, 124), Limbs = Color3.fromRGB(17, 17, 17) },
	},
}

-- === How many ===============================================================

--[[ How big the crowd on one lot is, and how quickly it refills.

	TWO, because two is the smallest number that reads as a crowd rather than as an NPC. One customer
	is a lone figure the player watches; two is a showroom with people in it, and the difference is
	worth the second humanoid.

	CAPPED BY WHAT IS PARKED, in `CustomerService._wantedCount` rather than here: a lot with one car
	gets one customer, because two people jostling in front of the same podium is what a crowd of
	strangers actually looks like and it is not what anybody wants from their own dealership. ]]
CustomerConfig.Crowd = {
	Base = 2,

	--[[ Polish.md's "+1 Customer" upgrade, read through `UpgradeConfig.levelOf`.

		ON THE BOARD SINCE 2026-08-09 and it needed no code here when it arrived, which was the point:
		`levelOf` answers 0 for a key it has never heard of, so this read the upgrade for weeks while
		nothing sold it and every player sat on the base count. Adding `Customers` to
		`UpgradeConfig.Upgrades` was the entire feature. ]]
	UpgradeKey = "Customers",

	--[[ Hard ceiling whatever the upgrade says. Twelve bays on a fully upgraded lot could feed a
		bigger crowd than this; six humanoids per plot across six plots is already 36 walking rigs on
		the server, and the crowd is meant to be life in the showroom rather than a queue.

		`UpgradeConfig.Upgrades.Customers.MaxLevel` IS PINNED TO `Max - Base` (4) so that the last
		level bought is the one that reaches this ceiling. Raising the ladder without raising this
		sells a level that `countFor` clamps straight back off — a tile that charges and buys nothing.
		Raise this first. ]]
	Max = 6,

	-- Seconds between one customer leaving and the next arriving, randomised so six lots do not
	-- breathe in step. The gap is why a lot is not permanently full: a showroom nobody ever leaves
	-- reads as a diorama.
	ArrivalGap = { Min = 4, Max = 11 },

	-- Seconds between passes of the top-up loop. Purely how often the service ASKS whether a lot is
	-- short a customer; it is not the arrival rate and lowering it does not make customers come
	-- faster.
	CheckInterval = 1.5,
}

-- === Where they come in =====================================================

--[[ Where a customer walks in from, and where they walk back out to, in the PLOT-LOCAL frame
	(`docs/MapLayout.md` §3.3: origin at the ground centre of the plot, local +X across the
	frontage, local +Z DEEPER INTO the showroom — so the forecourt is negative Z).

	ONE POINT FOR ALL SIX PLOTS, because the six are rigid copies of one building — the same
	construction `PlotConfig.Fallback` and the `PropagateCarSlots` command both rely on.

	X = +18 IS NOT A FREE CHOICE, and it is worth the line because two other things are already
	standing on this forecourt:

	  • THE SPAWN PAD IS AT LOCAL (0, -30) and the race pad at (0, -52) with an 18-stud touch zone
	    around it (`MapLayout` §3.5). Arriving at X 0 would mean customers materialising on top of
	    the player every time they respawn, and walking through the pad that starts a race.
	  • THE FACADE IS ONLY OPEN ON THIS HALF. Measured on Plot1: the front of the building is solid
	    from local X -58 to -22 and open from -18 to +38, so a customer arriving on the left half
	    would have to walk the length of the frontage to find the way in.

	Y IS NOT CONFIGURED. `CustomerService` raycasts for the forecourt surface and stands them on it,
	for the same reason `PlotConfig.Fallback` does: every deck height in this map is derived from the
	floor mesh, and a hardcoded Y is the one number that silently breaks if the slab ever moves. ]]
CustomerConfig.Arrival = {
	LocalX = 18,
	LocalZ = -30,

	-- Studs either side of that point a customer may arrive at or leave from, so a crowd does not
	-- file in and out of one footprint. Small: the clearance either side of it was measured, not
	-- assumed.
	Spread = 5,
}

--[[ GETTING UPSTAIRS (2026-10-06). A `Floor2` lot's second storey is reached by a vertical ladder
	(the `Stair` models), and a pathfinding agent cannot climb one. Measured on Plot1 with Floor 2
	bought: every floor-1 viewing spot paths from the forecourt, every floor-2 one comes back NoPath,
	and the floor-2 deck's own navmesh is in pieces. Before this, a customer who picked an upstairs
	car walked a straight line at a point 24 studs over their head, stood under it until the leg timed
	out, and ended their whole trip there. Income is tips (`GarageConfig.Income.Passive` is false), so
	the cars upstairs earned nothing at all.

	So a leg that changes floor is a HOP: the customer walks to the foot of the ladder, fades out, and
	fades back in at the car upstairs (coming down is the same in reverse). A leg along floor 2 walks
	when there is a real path and hops when there is not, because the straight-line fallback a floor-1
	leg uses could walk them into the stairwell. Buyers walking in to an upstairs car do the same.

	`LadderFoot` is PLOT-LOCAL X/Z, like `Arrival`: the plots are rigid clones, so one point serves all
	six. Y is raycast. `SplitY` is plot-local too: a spot above it is upstairs (floor 1 stands at about
	1.5, floor 2 at about 26). `false` for `Enabled` puts back the old straight walk. ]]
CustomerConfig.Upstairs = {
	Enabled = true,
	SplitY = 12,
	LadderFoot = { LocalX = 39.3, LocalZ = 37.5 },
	--- Each half of a hop: out where they are, in where they are going.
	FadeSeconds = 0.3,
}

-- === Where they stand =======================================================

--[[ The viewing spot: where a customer stands to look at one bay.

	DERIVED FROM THE PODIUM, NEVER AUTHORED. Every `CarSlot`'s base slab faces down the aisle at its
	own collect mat (`GarageService._platforms` — the mat measures at base-local Z -15.7, and -Z is a
	part's look direction), so "stand in front of this bay, facing the car" is the base's own frame
	pushed out along its LookVector. That holds for all 36 podiums on all six plots, at whatever
	scale they were placed at, with nothing to keep in sync.

	`Standoff` IS MEASURED FROM THE EDGE OF THE BASE SLAB, not from its centre, so it does not change
	when the podium does. The mat sticks out about 4.8 studs past that edge at the authored 0.85
	scale, so 6 puts the customer just past it — close enough to be looking at the car, far enough
	that they are not standing on the mat the owner walks onto to collect.

	=== AND IT STEPS OUT UNTIL IT FITS ======================================================

	A FIXED STANDOFF PUTS ONE CUSTOMER INSIDE A COLUMN. `Cube.168`, the inner corner column, stands
	at plot-local (-23.6, 12.0) — which is dead in front of bay 2, at every standoff from 5 to 9.
	Probed across all six bays on Plot1: every other bay is clear from 5 studs out, and bay 2 is
	clear from 10.

	So the standoff is FITTED per bay rather than applied per bay, stepping out a stud at a time
	until the customer's own footprint is clear of the building — the same shape (and the same
	reason) as `CarDisplay.fitYaw` stepping the showroom angle down until the car fits its deck.
	A bay that never clears is left at the base standoff and simply is not visited; that is a podium
	somebody has walled in, not a case worth inventing behaviour for. ]]
CustomerConfig.View = {
	Standoff = 6,
	MaxStandoff = 16,

	-- The box a standoff has to be clear of: roughly a person, with a stud of elbow room. Only the
	-- PLOT is tested against it, so another customer standing there, or the player, never counts as
	-- the spot being blocked.
	Clearance = Vector3.new(4, 5, 4),
}

-- === How they move ==========================================================

--[[ Walking. `CustomerService._walkTo` computes a path and follows it a waypoint at a time.

	PATHFINDING RATHER THAN A STRAIGHT `MoveTo`, because the thing they are walking to is a spot in
	front of a 26-stud podium and the room is full of them. A straight line from the door to bay 2
	crosses two other bays. Every path is checked to be reachable at all before a customer commits to
	the trip, and a leg that cannot be walked ends the visit rather than leaving somebody pressed
	against a wall — see `BlockSeconds`.

	`AgentCanJump = false` on purpose: a customer who jumps is a customer who ends up on a podium. ]]
CustomerConfig.Walk = {
	-- Studs per second. A browsing pace, not a commute — the walk between two bays is most of what
	-- the player actually watches, and 16 (the Roblox default) reads as somebody late for a train.
	Speed = 9,

	Agent = {
		Radius = 2.5,
		Height = 5,
		CanJump = false,
		-- Studs between waypoints. Short legs make the follow loop's per-leg timeout tight enough to
		-- notice a customer who is stuck, which is the whole reason not to leave it at the default.
		Spacing = 8,
	},

	-- How close counts as arrived, measured flat (Y is ignored — the floor under the aisle is not
	-- perfectly level and a 3D distance would never close on a slope).
	ArriveRadius = 3,

	-- Seconds between polls of the follow loop, and between re-issues of `MoveTo`. Re-issuing is not
	-- redundant: `Humanoid:MoveTo` gives up on its own after 8 seconds, and a customer squeezing past
	-- the player can easily spend that long on one leg.
	PollSeconds = 0.15,
	ReissueSeconds = 0.5,

	--[[ How long one leg is allowed to take: `distance / speed * Factor + Grace`. Generous, because
		the cost of being wrong in one direction is a customer who gives up in front of the player,
		and in the other is one who takes an extra second to get somewhere. ]]
	TimeoutFactor = 3,
	TimeoutGrace = 2.5,

	--[[ A bay whose viewing spot could not be walked to is left alone for this long.

		It is the answer to the one failure this system can produce on its own: an unreachable bay is
		unreachable EVERY TIME, so without this the crowd would spend the rest of the session walking
		at it, failing, and leaving. Sixty seconds is long enough that a genuinely blocked bay stops
		costing anything and short enough that a one-off — the owner standing in the doorway — costs
		one visit.

		The first thing it will catch is the upstairs bays a `Floor2` lot has: whether the ramp is
		navigable is untested, and if it is not, this is what stops six customers queueing at the
		bottom of it. ]]
	BlockSeconds = 60,
}

-- === What a visit looks like ================================================

CustomerConfig.Visit = {
	-- Bays looked at before they leave, inclusive. Never more than there are cars to look at, and
	-- never the same bay twice in one trip — a customer doubling back reads as a broken state
	-- machine even when it is random.
	PerBay = { Min = 2, Max = 4 },

	-- Seconds spent standing in front of one car. The beat the whole feature is made of: too short
	-- and they bounce off the podium, too long and the lot looks frozen.
	LookSeconds = { Min = 2.5, Max = 4.5 },

	-- Seconds to turn and face the car after arriving. Short, and eased rather than snapped —
	-- a rig that changes facing between two frames reads as a teleport.
	TurnSeconds = 0.35,

	-- Seconds they stay put after saying something, so the bubble is read before they walk off.
	ReactSeconds = 1.4,

	--[[ The chance one look ends in a tip. Half, so a visit of three bays pays about one and a half
		times — which is what makes the payment feel like an opinion rather than an entry fee, and is
		half of the arithmetic in `Tip.Seconds`. ]]
	LikeChance = 0.5,

	-- ... and the chance a look that pays nothing still says something. Low: the bubble is how the
	-- player learns money just arrived, and a browsing line every time would dilute that to noise.
	BrowseChance = 0.25,

	--[[ How hard the bay pick leans toward the better car. 1 = in proportion to what the bay earns,
		0 = every occupied bay equally likely, 2 = the best car gets almost everybody.

		IN PROPORTION IS THE ONE VALUE WITH AN ARGUMENT BEHIND IT, and it is a real economy bug in
		the alternative. Picked uniformly, the expected tip is the AVERAGE of what the lot's bays
		earn — so parking a beater in your spare bay drags that average down and the customers pay
		you less than they did with five cars. Filling your lot would cost you money, which is the
		exact opposite of what the meta game is for. Weighted by rate, the expected tip is
		sum(r^2)/sum(r), which cannot go down when a car is added, whatever tier it is. ]]
	RateBias = 1,

	-- A trip that has taken this long is abandoned and the customer is removed wherever they are.
	-- Nothing should reach it — every leg already has its own timeout — and it exists so that
	-- nothing CAN leave a rig standing on somebody's forecourt for the rest of the session.
	MaxSeconds = 240,
}

-- === What they pay ==========================================================

--[[ THE TIP IS SECONDS OF THAT BAY'S OWN INCOME (header note 1), so it is priced by the same ladder
	as everything else the dealership does: the car's tier, the bay's kiosk level and the lot-wide
	`Income` upgrade are all already in the number `GarageService` hands over, and none of them can
	drift out of step with a table kept here.

	=== WHY FIFTEEN SECONDS ==================================================================

	Work out what one customer is worth per second and the answer has to sit next to the passive
	income, which is the thing this must not replace:

	    a trip is about 3 looks x (3.5s looking + 3s walking) + 5s in + 5s out + a 7s gap
	                             ~ 37 seconds per customer slot
	    each trip pays LikeChance x 3 looks                = 1.5 tips
	    so one slot earns  1.5 x 15 x r / 37   ~  0.6 x r  dollars per second

	where `r` is the rate of the bay they picked — and because the pick is weighted by rate, `r` is
	close to the best car on the lot. Two slots is therefore worth a bit more than your single best
	bay, against a full lot of six. On an even lot that is around a fifth of the passive income; on a
	lot with one supercar and five beaters it is comparable to the supercar itself, which is the
	right shape: customers reward the car you are proud of.

	Push `Seconds` past about 40 and the crowd out-earns the podiums, at which point the run loop is
	competing with an idle timer and the game stops being about stealing cars. ]]
--[[ === THE TIP IS THE INCOME NOW, AND IT IS PRICED OFF VALUE — 2026-09-28 ===================

	WHAT IT WAS. Fifteen seconds of the bay's own income per tip (the note above), sized to sit
	BESIDE the passive income at about a fifth of it, and warned against growing past ~40 seconds
	because the crowd would then out-earn the podiums.

	WHAT IT IS. The podiums earn nothing (`GarageConfig.Income.Passive`), so the crowd is the whole
	of the dealership's income and that warning's premise is gone. A tip is a FRACTION OF WHAT THE
	CAR IS WORTH — its market value, condition included, times its bay's kiosk multiplier
	(`GarageService.getBayTip`) — so a battered car draws smaller tips than a clean copy of the model.

	WHY 0.2. Worth re-deriving, since it replaces the old number. Market value is `SellSeconds` (240)
	of the car's rate, so a fraction f of it is 240f seconds of rate; 0.2 is 48 seconds, 3.2x the old
	15. Carried through the trip arithmetic above:

	    one customer slot earns ~ 1.5 tips / 37s x 48 x r   ~  1.95 x r  dollars per second

	The base crowd is two slots, so a lot earns about 3.9 x its best car's rate — against the 6 x
	average-rate an even lot of six used to pay passively. A little under, on purpose: the
	`Customers` upgrade takes the crowd to six slots (capped by cars on show), which is ~11.7 x the
	best rate and comfortably past the old ceiling, and the buyers' offers (the next card) are money
	on top. Base play earns a bit less than it did; investing in the showroom earns a lot more.

	`Seconds` above is kept for `Income.Passive = true`, where the old sizing is the right one; the
	two cannot both be live, and `tipFor` picks whichever matches the income mode. ]]
CustomerConfig.Tip = {
	--- Fraction of a car's market value one tip is worth. Only read without passive income.
	ValueFraction = 0.2,

	Seconds = 15,

	-- Plus or minus, so two customers admiring the same car do not hand over the same number twice
	-- running. Small enough that nobody can tell it from taste; large enough that the readout on the
	-- bubble is never a repeat.
	Variance = 0.15,

	-- Nothing pays zero. A tier 1 car on a level 1 bay is 2/s, so the floor is only ever reached by
	-- a rate the ladder cannot currently produce.
	Minimum = 1,
}

-- === What they say ==========================================================

--[[ The bubble lines.

	SHORT, AND ONE LINE EACH. The label is `TextScaled` inside a bubble about nine studs wide, and
	every space in it becomes a non-breaking one before it is drawn (`lineFor`) — because TextScaled
	maximises text size subject to the laid-out text FITTING, which means it wraps in preference to
	shrinking. That is the same rule, and the same fix, as `PlotConfig.SignNonBreakingSpace` and
	`UpgradeConfig.oneLine`. Keep a line under about 26 characters or it will be legible only from
	inside the bubble.

	`%s` IS THE BODY NAME, and only a couple of lines use it on purpose. Half the roster is named
	like a person would name a car (`Golf GTI`, `Charger`) and half like a spreadsheet would
	(`Sedan12`, `Sports16`), so a set of lines that all name the car reads well for one half of the
	collection and like debug output for the other.

	THEY ADMIRE, THEY DO NOT BUY. Nothing here may read as a purchase — the car is still standing on
	the podium after they leave, and a customer who says "I'll take it!" and walks out empty-handed
	is the game promising something it did not do. What they are paying for is the look. ]]
CustomerConfig.Lines = {
	Liked = {
		"That %s is gorgeous.",
		"Best %s I've seen.",
		"Worth every penny.",
		"Take my money!",
		"Can I get a photo?",
		"Wow. Just wow.",
		"My dream car.",
		"Clean, real clean.",
		"Sitting pretty.",
		"Now THAT'S a car.",
	},

	Browsing = {
		"Just looking, thanks.",
		"Nice showroom.",
		"Hmm... maybe.",
		"Not my colour.",
		"I'll think about it.",
	},

	-- Substituted for `%s` when the car has no body name to give, which nothing should be able to
	-- produce — a bay either has a car with a name or is not looked at.
	UnknownBody = "one",
}

-- === The bubble =============================================================

--[[ What they say it in.

	OUR OWN BILLBOARD, NOT ROBLOX'S BUBBLE CHAT, and the reason is that `TextChatService:DisplayBubble`
	is a CLIENT call — a server-spawned customer could only get one by firing a remote at every
	client to have each of them draw it, and bubble chat is off by default anyway
	(`BubbleChatConfiguration.Enabled`), so switching it on to serve six NPCs would change how every
	player's own chat is presented. A BillboardGui in Workspace replicates to everybody for free,
	looks like the rest of the game, and can carry the money — which is the half of this the player
	actually cares about and the half a chat bubble cannot show.

	=== IT IS DRAWN ON REAL ART NOW — 2026-08-25 ==============================================

	It was a flat `#364157` Frame with a `UICorner` on it and a 3px `#0066FF` `UIStroke` round the
	outside, and the two things wrong with that are the two things that were wrong with every plot
	sign before `assets/ui/upgrades/README.md`'s pass rebuilt them: a rounded rectangle with a neon
	outline round it is what every game draws, and none of it was made of this kit.

	`UIAssets.Bubble.Panel` is the replacement and it carries the kit's own `#151D2D` border,
	`#384769` inner rim, 80% `#28334B` face and checker weave — AND A TAIL, which is the part no
	amount of `Color3` was ever going to do. The tail is not decoration: a bubble without one is a
	sign that happens to be near somebody, and these rigs deliberately wear no name tag (`_face`)
	precisely so this can own the space over their head. Now it points at them.

	SO THERE ARE NO PANEL COLOURS IN HERE ANY MORE. `Colors.Panel` and `Colors.Stroke` were deleted
	rather than left unread — the same clean-up `BuildDealershipSigns` made when its banner went onto
	real art, and for its reason: a palette that no longer paints anything is a palette somebody will
	come back and tune. ]]
CustomerConfig.Bubble = {
	Enabled = true,

	--[[ Studs, and it is THE WHOLE TEXTURE — body plus tail. The `Size` of a BillboardGui is in
		studs on its Scale component, so this is a physical object in the showroom rather than a
		fixed lump of screen: it gets smaller as you walk away, which is what stops a crowd of them
		covering the lot.

		IT HAS TO MATCH `UIAssets.BubbleSize.Panel`'s ASPECT or the tail comes out sheared, and a
		sheared tail is the one thing on this bubble a player would actually notice. 9 x 3.5 is
		2.571 against the texture's 2.573. The body inside it is the 9 x 2.7 the old flat panel was,
		so nothing about how much sentence fits has changed. ]]
	Size = Vector2.new(9, 3.5),

	--[[ Studs of clear air between the TOP OF THE HEAD and the TIP OF THE TAIL.

		NOT "studs above the head", which is what the old number meant and is a thing you cannot
		reason about once a bubble has a tail on it: it was the offset to the billboard's CENTRE, so
		it silently moved the gap every time the panel's height changed. `_say` derives the centre
		offset from the anchor's own size, this, and half of `Size` — so this number means what it
		says at any bubble size and on any head, which is the property that matters when the heads
		are real avatars and no two of them are the same. ]]
	TailClearance = 0.5,

	--- Added to the same sum when there is no `Head` to pin to and the root is standing in for it:
	--- roughly head-top above root-top on an R15. A rig that far gone is a rig that failed to
	--- build, so this is a fallback that keeps the bubble in the air rather than a number to tune.
	RootLift = 1.2,

	-- Past this many studs it is not drawn at all. Sized to the plot rather than to the plaza: a
	-- bubble you can read from another dealership is one more thing on a crowded skyline.
	MaxDistance = 110,

	--[[ Fractions of the BODY's own height, top to bottom — of the body and not of the texture, so
		a change to how much of the drawing is tail cannot walk the text down into it.

		TWO LAYOUTS, NOT ONE WITH A ROW HIDDEN. `Solo` is what a customer who says "Just looking,
		thanks." and pays nothing gets, and it is deliberately taller and centred: one sentence has
		to carry the whole bubble, and leaving it up at `Line` would hang it over the empty band
		where the money would have been. ]]
	Rows = {
		Solo = { Y = 0.30, Height = 0.40 },
		Line = { Y = 0.15, Height = 0.28 },
		Money = { Y = 0.51, Height = 0.32 },
	},

	--[[ The tip, drawn as the kit's cash icon with the number beside it rather than as a bare green
		figure. It is one more instance and it is worth it: this is the only moment in the game where
		money arrives without the player pressing anything, and the icon is the same one the quest
		reward chip and the topbar counter wear, so what just happened is legible before the number
		is read.

		THE PAIR IS MIRRORED ABOUT THE CENTRE RATHER THAN LAID OUT, and that is not laziness — it is
		the only arrangement that stays centred. Centring a group needs the RENDERED width of a
		`TextScaled` label, and nothing on a server can ask for that: `GetTextBoundsAsync` is a
		client call and `AutomaticSize` is exactly what `TextScaled` overrides. A `UIListLayout` would
		therefore centre the icon against the number's BOX and lean the visible pair left by however
		much shorter than its box the number happened to be. So the icon's centre sits `MoneyOffset`
		left of the row's centre and the number is centred `MoneyOffset` right of it: whatever the
		amount, the two inks balance.

		WHAT IT COSTS IS THE GAP BETWEEN THEM, which grows as the number gets shorter — "+$412" sits
		further from the icon than "+$100.0K" does. That is the honest half of this trade and it is
		worth taking: a gap that breathes reads as spacing, a pair that slides off centre reads as
		broken.

		`MoneyTextWidth` is where `TextScaled` stops growing, so it sets the number's size as much as
		the row's height does — wide enough that four figures fill the row and only the six-figure
		amounts shrink to fit. The three numbers have to hold `4 x MoneyOffset > iconWidth +
		MoneyTextWidth` — the two boxes are each HALF a width from their own centre, so the offset
		buys twice what it looks like — or the longest amount `GarageConfig.formatCash` can print
		runs into the icon. They clear by about a hundredth as set, which is not much room to widen
		either. ]]
	MoneyOffset = 0.125,
	MoneyTextWidth = 0.34,
	MoneyIconHeight = 0.92, --- of the money row's own height; the other two are of its width

	--[[ Seconds it holds before fading, and the two short beats either side of it.

		THE POP GROWS OUT OF THE TAIL. A `UIScale` scales its object about that object's own
		`AnchorPoint`, so the bubble is anchored at bottom-centre — which is where the tail is — and
		the whole thing blooms out of the speaker's head instead of inflating around its own middle.
		Same two frames of work either way; only the pivot moved.

		Per `effect-intensity-taste` the pop itself is the restrained kind: it eases in from
		`PopScale` and settles. A bubble that springs 30% oversized is a cartoon, and the money is
		supposed to be the thing that lands. ]]
	PopSeconds = 0.14,
	PopScale = 0.82,
	HoldSeconds = 3.2,
	FadeSeconds = 0.25,

	Colors = {
		Text = Color3.new(1, 1, 1),
		Amount = Color3.fromRGB(13, 180, 21), -- #0DB415, the kit money green
	},
}

-- === Leaving ================================================================

-- Seconds a customer takes to fade out once they are back on the forecourt. Zero removes them
-- instantly, which is a perfectly good look and one property write instead of a few dozen.
CustomerConfig.FadeSeconds = 0.35

-- === Animation ==============================================================

--[[ Two clips, played through `Modules/RigAnimator` — the same module the steal's rigs use, which
	is why the awkward parts of animation (the asset's own Loop flag, one `Animation` instance per
	id, a rig with no Animator) are already solved here.

	THEY ARE THE STOCK R15 ANIMATIONS. A rig built from a `HumanoidDescription` arrives with no
	`Animate` script that a server can run — that script is a LocalScript and belongs to a player's
	own character — so a server-side NPC does not animate itself, and without these two ids a
	customer slides around the showroom in an A-pose. The ids are Roblox's own default set.

	`WalkPlaybackSpeed` IS A LOOK, NOT A CONVERSION. The clip is authored against the default
	WalkSpeed of 16 and these customers stroll at 9, so playing it at 1.0 over-strides slightly; the
	honest ratio (0.56) is a shuffle. Somewhere in between is what a browsing pace looks like. ]]
CustomerConfig.Animations = {
	Enabled = true,
	WalkPlaybackSpeed = 0.8,

	Clips = {
		Idle = { Id = 507766666, Length = 10, Looped = true },
		Walk = { Id = 507777826, Length = 1, Looped = true },
	},
}

-- === Asking about a crowd ===================================================

--[[ How many customers this player's lot should hold, from the same raw `Upgrades` table
	`UpgradeConfig`'s accessors take — anything in, a real number out, for the same reason: the
	caller has a table straight off a profile that may be nil, may be stale and may hold keys that no
	longer exist. ]]
function CustomerConfig.countFor(upgrades: unknown): number
	local crowd = CustomerConfig.Crowd
	local bought = UpgradeConfig.levelOf(upgrades, crowd.UpgradeKey)
	return math.clamp(crowd.Base + bought, 0, crowd.Max)
end

--[[ What one look is worth, in dollars. `basis` is what `CustomerService` priced the bay at: the bay's
	per-second RATE under passive income, or the car's tip VALUE (market value x kiosk) without it —
	see `Tip`. `perLook` below is the same number without the jitter. ]]
function CustomerConfig.tipFor(basis: number, rng: Random): number
	if type(basis) ~= "number" or basis ~= basis or basis <= 0 then
		return 0
	end
	local jitter = 1 + rng:NextNumber(-CustomerConfig.Tip.Variance, CustomerConfig.Tip.Variance)
	return math.max(CustomerConfig.Tip.Minimum, math.floor(CustomerConfig.perLook(basis) * jitter))
end

--- The expected tip for one liked look at a bay priced at `basis`, before jitter and the floor.
function CustomerConfig.perLook(basis: number): number
	if GarageConfig.Income.Passive then
		return basis * CustomerConfig.Tip.Seconds
	end
	return basis * CustomerConfig.Tip.ValueFraction
end

-- === Who walks in ===========================================================

--[[ CUSTOMER KINDS (2026-10-06), the customers' half of `BuyerConfig.Kinds`. Every customer used to
	be the same person, so a lot full of them read as a crowd, not as people. A kind changes three
	things and only three, all on numbers that already exist:

	    `Like`      x `Visit.LikeChance` — how often a look ends in a tip (capped at 0.95)
	    `Tip`       x the tip, when there is one
	    `RateBias`  + `Visit.RateBias` — how hard they head for the best car on the lot

	    Regular        no tag. Exactly the customer as before.
	    BIG SPENDER    rare; likes more and tips 2.5x — the one you hope walks in
	    WINDOW SHOPPER common; looks, rarely tips
	    CAR NERD       makes a beeline for your best car (`RateBias` +1.5)

	A kind with a `Title` wears it as a small tag over the head for the whole visit (hidden while a
	speech bubble is up, so the two never stack), coloured `Color`.

	THE TIP ECONOMY IS KEPT LEVEL, because tips ARE the dealership's income. Expected tip per look,
	relative to a Regular, weighted by `Weight` (out of 100):

	    Regular 58 x 1.0 x 1.0   +   Big Spender 7 x 1.25 x 2.5   +   Window Shopper 22 x 0.35 x 1.0
	    +   Car Nerd 13 x 1.0 x 1.0      =  58 + 21.9 + 7.7 + 13  =  100.6  ->  ~+1%

	...plus a little from the Car Nerd's pull toward the best car (a higher-value look tips more), a
	few percent at most on a lot with one standout car. Re-run that sum if a weight moves. The offline
	estimate (`simulate`) does not model kinds; at ~+1-3% the two stay in step.

	`Enabled = false`: every customer is a Regular, the game exactly as before.

	=== ONE KIND: THE VIP — 2026-10-06, same day ====================================
	Leaf, on the first cut: "only do a big spender and call them VIP, and make them wear gold outfits;
	remove window shopper, it's dumb". WAS the four kinds above. NOW a Regular and a VIP, and the VIP is
	dressed in gold (`VipOutfit`) as well as tagged, so they are spotted across the lot before the tag
	is readable. The sum above no longer holds — the window shopper was what paid for the big spender —
	so it is levelled on the Regular instead, a tenth off their tip:

	    Regular 95 x 1.0 x 0.9  +  VIP 5 x 1.2 x 2.5   =   85.5 + 15   =   100.5  ->  level

	The point of the VIP is that a quarter of the tips on a lot come from one in twenty customers:
	the money is unchanged and it arrives in moments rather than drips. ]]
CustomerConfig.Kinds = {
	Enabled = true,
	List = {
		{ Key = "Regular", Weight = 95, Tip = 0.9 },
		{ Key = "VIP", Title = "VIP", Color = Color3.fromRGB(255, 205, 40), Weight = 5, Like = 1.2, Tip = 2.5, Outfit = true },
	},
	--[[ HOW A VIP LOOKS.

		=== NOT PAINTED GOLD ANY MORE — 2026-10-06 ==============================================
		WAS every body part but the head turned gold Foil with the clothes stripped off. On a blocky
		avatar that is a flat yellow block (the owner: "the gold looks really bad"): a body colour has
		no folds, seams or shading to read as fabric, so it reads as paint. NOW they keep their own
		avatar and are marked by LIGHT instead — a gold outline (`Outline`, a `Highlight` with no fill)
		and a slow gold sparkle around them (`Sparkle`) — which reads as "special" on any avatar shape.

		`Clothing` is a list of CATALOGUE item ids put on over their own avatar — classic shirts and
		pants, layered clothing, or accessories; `CustomerService._wear` asks each one's type once and
		puts it on through the rig's `HumanoidDescription`, the way Roblox dresses a real avatar. The
		gold bodysuit is the owner's pick (2026-10-06). An id that will not load (deleted, off-sale,
		moderated) is skipped and the VIP keeps the outline and sparkle. ]]
	VipOutfit = {
		--- The gold bodysuit, and (2026-10-06, the owner) a hat. Any catalogue item type works here.
		Clothing = { 12780523103, 128622639915870 },
		Outline = { Enabled = true, Color = Color3.fromRGB(255, 205, 40), Transparency = 0.15 },
		Sparkle = { Enabled = true, Color = Color3.fromRGB(255, 214, 80), Rate = 5, Size = 0.5 },
	},
	--- The tag over a titled customer's head: studs wide/tall, studs above the head, and how far away
	--- it is still drawn (short — a lot full of tags from across the map is noise).
	--[[ === A NAME TAG NOW — 2026-10-07 ==========================================================
		WAS a bare "VIP" in gold text a fixed stud over the head, which a tall hat swallowed whole (the
		VIP's own hat included). NOW a name tag: a gold VIP badge with the customer's name under it,
		placed `Above` studs over the TOP OF WHATEVER THEY ARE WEARING (re-measured once their outfit
		lands, `_wear`), and drawn over the world so nothing they wear can cover it. Studs. ]]
	--[[ === EVERYONE WEARS ONE — 2026-10-08 ===
		WAS VIPs only; `CustomerService._buildRig`'s "NOBODY WEARS A NAME TAG" note is why the rest went
		without (the tag stood where the speech bubble goes). The owner: "give all NPCs a nametag with
		their name not just the VIPs". The tag has sat over the top of the outfit and over the world
		since 2026-10-07, so a plain one now is the NAME LINE ALONE, `NameHeight` studs tall — about
		half a VIP's, so the bubble keeps its room and the VIP's badge still reads as the special one.
		A nameless rig gets no tag. `Everyone = false`: VIPs only, as before. ]]
	Tag = { Width = 5.5, Height = 1.8, Above = 0.6, MaxDistance = 90, Everyone = true, NameHeight = 0.8 },
}

--[[ CUSTOMERS REACT, AND TIPS LAND ON YOU (2026-10-06, the polish pass). Two small things that make
	a lot read as people reacting rather than as numbers:

	  `Emoji`  a face pops beside the head as they finish looking: `Loved` for a VIP's tip, `Liked`
	           for anyone else's, `Unsure` when they only browsed. Beside the speech bubble, not over
	           it, and gone in `Seconds`.
	  `Burst`  the tip's banknotes fly from the customer into the owner (`CashBurstController`, the
	           collect mats' effect), so a tip is money you SEE arrive, not only a number in a bubble.

	Both purely visual; `Enabled = false` on either is that half gone and nothing else. ]]
CustomerConfig.Reactions = {
	Emoji = { Enabled = true, Liked = "😍", Loved = "🤩", Unsure = "🤔", Seconds = 1.6, Size = 2.2, Side = 2.4 },
	Burst = { Enabled = true },
}

--- Draw a kind for a new customer. Always returns one (a Regular when kinds are off).
CustomerConfig.VIP = { TipMultiplier = 1.35, CustomerChanceMultiplier = 2 }

local function kindWeight(kind, vip: boolean?): number
	if not vip then
		return kind.Weight
	end
	local total, vipWeight = 0, 0
	for _, entry in CustomerConfig.Kinds.List do
		total += entry.Weight
		if entry.Key == "VIP" then
			vipWeight += entry.Weight
		end
	end
	-- Preserve total weight so doubling VIP means 5% -> 10%, rather than 5% -> 9.52%.
	local boosted = math.min(total, vipWeight * CustomerConfig.VIP.CustomerChanceMultiplier)
	if kind.Key == "VIP" then
		return if vipWeight > 0 then kind.Weight * boosted / vipWeight else 0
	end
	return if total > vipWeight then kind.Weight * (total - boosted) / (total - vipWeight) else 0
end

function CustomerConfig.pickKind(rng: Random, vip: boolean?)
	local list = CustomerConfig.Kinds.List
	if not CustomerConfig.Kinds.Enabled then
		return list[1]
	end
	local total = 0
	for _, kind in list do
		total += kindWeight(kind, vip)
	end
	local roll = rng:NextNumber() * total
	for _, kind in list do
		roll -= kindWeight(kind, vip)
		if roll <= 0 then
			return kind
		end
	end
	return list[1]
end

-- The existing offline estimator assumes regular traffic; apply VIP's relative expected gain.
function CustomerConfig.vipIncomeMultiplier(): number
	if not CustomerConfig.Kinds.Enabled then
		return CustomerConfig.VIP.TipMultiplier
	end
	local function average(vip: boolean): number
		local total, weighted = 0, 0
		for _, kind in CustomerConfig.Kinds.List do
			local weight = kindWeight(kind, vip)
			total += weight
			weighted += weight * math.min(0.95, CustomerConfig.Visit.LikeChance * (kind.Like or 1)) * (kind.Tip or 1)
		end
		return if total > 0 then weighted / total else 0
	end
	local baseline = average(false)
	return CustomerConfig.VIP.TipMultiplier * (if baseline > 0 then average(true) / baseline else 1)
end

-- === The run summary ========================================================
--[[ "While you were driving": the card that says what the showroom did during a run
	(`CustomerService._sendSummary`, drawn by `ShowroomSummaryController`). The Welcome Back screen is
	the same summary for time spent logged out.

	A PLACEHOLDER CARD, built in code in the kit's navy and typeface, top-centre, that slides in, holds
	and goes. It is not a modal and takes no input — the run results panel is the screen a player is
	reading as they come home, and this is the line underneath it that says the lot kept working.

	`Enabled = false` sends nothing and draws nothing; the tips still arrive, silently, which is the
	behaviour before this card existed.

	=== OFF — 2026-10-02 ======================================================================
	The owner: remove it, "it gets hidden under another frame". Top-centre is the busiest strip on
	the screen after a run (the results panel, then the NEW BEST cutscene and the offline-earnings
	label all live up there), and a card nobody can read is worse than no card. Switched off rather
	than deleted: the tips still land either way, and `true` brings the card back exactly as it was
	if it ever gets a spot of its own. ]]
CustomerConfig.Summary = {
	--[[ BACK ON (2026-10-08). Leaf: "there used to be a notification when you come back from a drive,
		it said how many new offers you got... should add it back, it was a good idea." The reason it
		went (2026-10-02: it sat under another top-centre frame) is gone too — it is a card in the
		left-side notice lane now (`NoticeLaneConfig`, `ShowroomSummaryController`), which stacks
		cards instead of overlapping them. ]]
	Enabled = true,
	--[[ Seconds after the LOBBY IS BACK (`RaceConfig.ReturnedEvent`) before the card appears.

		=== FROM THE LOBBY, NOT FROM THE RUN'S END — 2026-10-08 ===
		WAS 2.5s after the server's `ShowroomSummary`, which is sent as the run ends. RACE AGAIN never
		goes home — the results stay black straight into the next entry — so the card slid in over the
		next run's road (the owner: "clicking race again makes the while you were driving pop up show
		up, we dont want that"). IS: the client holds the summary until the lobby is actually on screen,
		and a chain of RACE AGAIN runs adds up into one card for the whole trip
		(`ShowroomSummaryController._onSummary`). Short now, because the wait for the fade is the
		event's job and no longer this number's. ]]
	Delay = 0.6,
	--- Seconds it stays up. One line now (2026-10-13, was 6 for three).
	Hold = 4,
	--[[ NOT SHOWN for small tips with nobody waiting (2026-10-13, Aleafo: "this is excessive af" over
		"+$62 in tips"): under the larger of a flat floor and a share of the player's balance. The
		share is what keeps it meaning "small" as the economy grows; the floor covers a fresh profile
		with next to nothing in the bank, for whom the first tips are the news. A waiting buyer always
		shows: it is the one line the player can act on. ]]
	SkipUnderTips = 50,
	SkipUnderCashShare = 0.05,
	--- Title case: it sits in the kit panel's header strip, which sets headings that way (2026-10-12).
	Title = "While You Were Driving",
	--- The right half of the one line, so short: the header already says what they did.
	VisitorsFormat = "%d CUSTOMERS",
	OneVisitorText = "1 CUSTOMER",
	TipsFormat = "%s TIPS",
	--- In the customers' place when anybody is waiting.
	BuyersFormat = "%d BUYERS WAITING",
	OneBuyerText = "1 BUYER WAITING",
}

-- === While nobody is watching ===============================================
--[[ THE CROWD, SIMULATED (2026-09-28). The WELCOME BACK screen used to pay what the bays held; with
	no passive income it pays what the customers WOULD have tipped while the owner was logged out.
	No rigs walk for a player who is not in a server, so this is arithmetic over the same numbers the
	live crowd runs on — which is the point: the offline figure is the online one with a clock, not
	a second economy to balance.

	    tips per second = slots x LikeChance x looks / TripSeconds x E[tip per look]
	    E[tip per look] = sum(v^2) / sum(v) x perLook(1)       -- the RateBias = 1 weighting

	where `slots` is the crowd size the lot would get (`countFor`, capped by cars on show) and `v`
	each bay's tip value. The weighting is the same one `_pickBay` uses live, so a lot with one
	supercar and five beaters earns offline what it earns online, not the average of its bays. ]]
CustomerConfig.Offline = {
	--[[ Seconds one customer slot spends per visit, arrival to arrival. The trip estimate in the
		`Tip` note: ~3 looks x 6.5s + 5s in + 5s out + a 7s gap. MEASURED BY ARITHMETIC OFF THE
		CONFIG, not stopwatched on a live lot; if the walk or look timings move, move this with them. ]]
	TripSeconds = 37,

	--[[ Share of the simulated figure actually paid. A TASTE CALL: an owner who is online, with the
		lot in front of them, should out-earn one who is not, and a showroom that earned the same
		asleep would make logging off the optimal strategy. Half, which also leaves the offline boost
		product (2x) something worth buying. ]]
	Efficiency = 0.5,

	--[[ How much absence counts, seconds. Two hours, the ceiling the bays used to hold — kept as the
		one rule a returning player already learned ("the lot fills up in two hours"), now phrased as
		the showroom closing for the night. Past it, time away earns nothing more. ]]
	CapSeconds = 2 * 60 * 60,
}

--[[ What `seconds` of absence earned a lot whose bays are priced at `values`, with `slots` customers.
	Returns `(tips, visitors)`, whole numbers, AFTER `Efficiency` and the cap.

	Pure — it reads config and its arguments only, so `OfflineService` can run it on join and a test
	can run it on a table. An empty lot, or no slots, earns `(0, 0)`: nobody comes to see nothing. ]]
function CustomerConfig.simulate(values: { number }, slots: number, seconds: number): (number, number)
	local offline = CustomerConfig.Offline
	local visit = CustomerConfig.Visit
	if #values == 0 or slots <= 0 or seconds <= 0 then
		return 0, 0
	end

	local sum, sumSquares = 0, 0
	for _, value in values do
		local v = math.max(value, 0)
		sum += v
		sumSquares += v * v
	end
	if sum <= 0 then
		return 0, 0
	end

	local counted = math.min(seconds, offline.CapSeconds)
	local looks = math.min((visit.PerBay.Min + visit.PerBay.Max) / 2, #values)
	local perSecond = slots * visit.LikeChance * looks / offline.TripSeconds * CustomerConfig.perLook(sumSquares / sum)
	local visitors = slots * counted / offline.TripSeconds

	return math.floor(perSecond * counted * offline.Efficiency), math.floor(visitors)
end

--[[ One line out of a pool, ready to be written to a label: the car's name substituted in and every
	space already replaced with a non-breaking one.

	THE NBSP IS PART OF THE LINE, NOT A DECORATION THE CALLER ADDS — see `Lines` for what TextScaled
	does to a sentence that is allowed to wrap. Doing it here is what stops the two places that draw
	a bubble from disagreeing about it. ]]
function CustomerConfig.lineFor(pool: { string }, rng: Random, body: string?): string?
	if #pool == 0 then
		return nil
	end
	local text = pool[rng:NextInteger(1, #pool)]
	if string.find(text, "%%s") then
		--- The game name ("Challent"), never the real one: the roster is renamed for trademarks (`CarNameConfig`).
		local name = if body and body ~= "" then CarNameConfig.nameOf(body) or body else CustomerConfig.Lines.UnknownBody
		text = string.format(text, name)
	end
	return UpgradeConfig.oneLine(text)
end

--- A number of seconds out of a `{ Min, Max }` pair. Every duration in this file is one of those,
--- so the sanity check lives in one place rather than at each of the four call sites.
function CustomerConfig.rollRange(range: { Min: number, Max: number }, rng: Random): number
	local low, high = range.Min, range.Max
	if high <= low then
		return low
	end
	return rng:NextNumber(low, high)
end

-- Approved economy balance, 2026-10-04.
CustomerConfig.Visit.LikeChance = 0.60
--- 2026-10-20: tips are paid as the customer reacts, a better car later paying the difference, the
--- visit's total unchanged (`CustomerService._react`). False: one tip at checkout, as before.
CustomerConfig.Visit.PayOnLike = true
CustomerConfig.Tip.ValueFraction = 0.16
--[[ RAISED (2026-10-08, the owner: "make the offline earnings earn more"). WAS 0.25% of the live
	rate in world 1 falling to 0.1% in world 5 — which the HUD showed side by side as "$25/hr offline"
	against "+$10,345/hr" live, an offer to come back that argued against itself. NOW 25% falling to
	15%. With `Offline.CapSeconds` (2h of absence counted), the most a return can pay is 2h x 25% =
	about half an hour of live play in world 1: worth logging back in for, never worth more than
	playing. Still lower per world, as the balance pass had it, so later worlds lean more on playing. ]]
CustomerConfig.Offline.Efficiency = 0.25
CustomerConfig.Offline.EfficiencyByWorld = { 0.25, 0.22, 0.2, 0.18, 0.15 }
function CustomerConfig.offlineEfficiencyFor(world: number?): number
 local index = math.clamp(math.floor(world or 1), 1, #CustomerConfig.Offline.EfficiencyByWorld)
 return CustomerConfig.Offline.EfficiencyByWorld[index]
end
--- Two-hour cap restored for the modest economy reduction, 2026-10-16.
CustomerConfig.Offline.CapSeconds = 2 * 60 * 60
--- Back on 2026-10-08 — see `Summary.Enabled`'s note. (It was switched off here on 2026-10-05.)
CustomerConfig.Summary.Enabled = true
local ShowroomEconomy = require(script.Parent.Parent.Modules.ShowroomEconomy)
function CustomerConfig.simulate(values: {number}, slots: number, seconds: number, bayIndices: {number}?, efficiencies: {number}?): (number, number)
 return ShowroomEconomy.estimate(CustomerConfig, values, slots, seconds, bayIndices, efficiencies)
end


-- === The balance pass of 2026-10-08 ===========================================
--[[ === TIPS SCALE DOWN BY THE CAR'S WORLD — 2026-10-08 ===

	WHAT WAS WRONG, measured with a Python port of `ShowroomEconomy` (calibrated against a live lot:
	it predicted 2.5M/hr for a lone MK5 Supra, a playtester saw 2.2M). At a flat `ValueFraction` of
	0.16 a parked car earns about TWENTY TIMES ITS OWN VALUE AN HOUR, and a lot about 70-80x its
	average car. Stealing that car pays its value once. So an hour on the podium was worth twenty
	steals, the showroom was ~80% of income, and every price in the game — upgrades, parts, the dealer
	— is set in car values, which made all of it read as pocket change. Worlds 2-4 took 60 / 82 / 104
	minutes; the whole game was ~4.7 hours.

	WHAT IT IS: the fraction is per world of the CAR (`ByWorld`, via `WorldConfig.WorldOfBody`).
	World 1 keeps 0.16, because world 1 was already on target — Aleafo's brief is 18-30 minutes to
	world 2 and the same simulation puts it at ~30 (an empty lot of $600 cars is slow to start, and
	cutting tips there pushed it to an hour). Each later world tips less, so the same sim now reads
	W2 ~88m, W3 ~160m, W4 ~246m: each world about 1.6x the last, ~9 hours to world 5, and stealing is
	a real share of income again rather than a fifth of it. The sim ASSUMES ~2-minute runs banking 70%
	of the time; if real runs are much longer or shorter, re-run it before moving these.

	`tipScaleOf` is applied ONCE, in `GarageService.getBayTip`, which every tip reader prices off
	(the live crowd, `OfflineService`, the HUD's `TipRatePerHour`) — so live, offline and the HUD
	cannot disagree. A body with no world (a stray rig) tips at world 1's rate.
	`ScaleByWorld = false`: 0.16 for every car, the old economy exactly. ]]
CustomerConfig.Tip.ScaleByWorld = true
--[[ === DOWN A FURTHER 37.5% — 2026-10-09 ===
	The owner after a test: "decrease tips, they're too much". WAS { 0.16, 0.08, 0.05, 0.04, 0.035 };
	NOW every world x0.625. Chosen against the world 1 clock rather than by feel alone: with the rarer
	road of the same day (`BalanceConfig.RungWeights`) the calibrated model puts world 2 at ~22 minutes
	on the old tips, ~28 on these (0.12 would be ~26, 0.08 ~32 — past Aleafo's 30). If world 1 drags,
	world 1's share is the one to give back; the later worlds can stay down. ]]
CustomerConfig.Tip.ByWorld = { 0.1, 0.05, 0.031, 0.025, 0.022 }

--- The multiplier on a car's tip basis that turns `ValueFraction` into its world's own fraction.
--- Pure. 1 when switched off or for a body no world lists.
function CustomerConfig.tipScaleOf(body: string?): number
	local tip = CustomerConfig.Tip
	if not tip.ScaleByWorld or type(body) ~= "string" or tip.ValueFraction <= 0 then
		return 1
	end
	local world = WorldConfig.WorldOfBody[body]
	local fraction = world and tip.ByWorld[world]
	return if fraction then fraction / tip.ValueFraction else 1
end

--[[ === OFFLINE, SEMI-WEAK — 2026-10-08 ===
	WAS 0.25 falling to 0.15 by world (raised the same morning from 0.25%..0.1%, when the HUD showed
	"$25/hr offline" against "$10k/hr" live). Aleafo: "offline earnings should be semi-weak too". NOW
	0.12 falling to 0.06: a return after the two-hour cap pays ~15 minutes of live tips in world 1 and
	~7 in world 5 — a welcome back, never a reason to log off. On top of the lower world tips above,
	so a late-world absence pays far less than it did. ]]
CustomerConfig.Offline.Efficiency = 0.12
CustomerConfig.Offline.EfficiencyByWorld = { 0.12, 0.1, 0.08, 0.07, 0.06 }


-- Approved consistent tip economy, Oct15. One checkout for the favourite liked car.
-- World 5 only: 1.5% per favourite-car checkout; car values retained, 2026-10-17.
CustomerConfig.Tip.ByWorld = { 0.09, 0.09, 0.09, 0.09, 0.015 }
CustomerConfig.Crowd.Max = 8
CustomerConfig.Crowd.UpstairsVisitors = 2
function CustomerConfig.floorForBay(index: number): number
 return if index > 6 then 2 else 1
end
function CustomerConfig.capacityForFloor(upgrades: unknown, floor: number): number
 if floor == 2 then
  return if UpgradeConfig.levelOf(upgrades, "Floor2") >= 1 then CustomerConfig.Crowd.UpstairsVisitors else 0
 end
 return math.clamp(CustomerConfig.Crowd.Base + UpgradeConfig.levelOf(upgrades, CustomerConfig.Crowd.UpgradeKey), 0, 6)
end
function CustomerConfig.countFor(upgrades: unknown): number
 return CustomerConfig.capacityForFloor(upgrades, 1) + CustomerConfig.capacityForFloor(upgrades, 2)
end
function CustomerConfig.simulate(values: {number}, slots: number, seconds: number, indices: {number}?, efficiencies: {number}?, floorSlots: {number}?, vip: boolean?): (number, number)
 return ShowroomEconomy.estimate(CustomerConfig, values, slots, seconds, indices, efficiencies, floorSlots, vip)
end

--[[ === PLACING A CAR NEVER LOWERS THE LOT'S INCOME — 2026-10-21 ===============================

	WAS: the money was whatever the crowd happened to do. Each floor has a capped crowd (`Crowd.Base`
	+ the Customers upgrade downstairs, `UpstairsVisitors` up), each customer looks at 2-4 cars and
	tips ONCE, for the best one they liked. Past the cap a new car brings nobody new; it only spends
	their looks and lengthens their visits, so a car below the floor's average LOWERED the lot (a
	playtest: $683.5M/hr to $636.8M/hr on placing a $45.3M car; the same car on bay 8 vs bay 9 read
	$18.2M vs $17.6M, walking distance plus the 8-run estimate's ±3% noise). The owner: "placing down
	another car should never make the income go down", and "do not change the economy so players earn
	a crazy amount more money".

	IS: a formula, per floor, paid as a rate (`ShowroomEconomy.estimate`, `CustomerService._bank`):

	    per second = perLook(b1 + Decay*b2 + Decay^2*b3 + ...) x Pace[floor] x customers^CrowdPower

	`b` are the floor's tip bases (`GarageService.getBayTip`) best first, and `customers` is the
	floor's crowd as the live lot spawns it, min(capacity, cars). Every term only grows when a car is
	added: the ranking can only move up, and the crowd only grows. Decay makes a big lot level off the
	way the crowd did, so a full lot earns a little more than before, not the sum of every car.

	EVERY CAR VISIBLY ADDS (the owner, same day: "a player should see that his income goes up if he
	places a car"). WAS Decay 0.2 / CrowdPower 0.5, the closest fit to the old crowd (rms 13%), where a
	4th car added under 1%. Then 0.8 / 0.1 for an hour (a 6th car +10%, but lots of 1-2 cars -16% and
	lots of 5-6 +26%); the owner: "leave early game progression the same, if anything make late game a
	little less". IS 0.5 / 0.1: a similar car adds +50% as the 2nd, +17% 3rd, +7% 4th, +3% 5th, +1.6%
	6th, so every car still moves the number. Against the old simulation: lots of 1-2 cars x1.00, 3-4
	x0.97, 5-6 x1.16. Higher Decay makes later cars count more and full lots earn more.

	FITTED, NOT GUESSED: `Pace` is set so lots of 1-2 cars earn exactly what the old simulation paid
	(geometric mean over 160 random lots: 1-6 cars, 2-6 customers, both floors, a 12x spread of car
	values, the real customer kinds). The live crowd still walks and reacts exactly as before; a liked look
	pays out what the lot has earned since the last one, so the bubbles and bursts are unchanged and
	the total is the formula's. The HUD's ~$/hr, the offline label and the WELCOME BACK payout all
	read this same function, so they cannot disagree, and nothing is random any more.

	`Ranked = false`: the crowd simulation and per-look tips, exactly as before this note. ]]
CustomerConfig.Income = {
	Ranked = true,
	Decay = 0.5,
	CrowdPower = 0.1,
	--- Liked looks per second the formula pays for, downstairs and upstairs (the stairs walk is why
	--- upstairs is lower). Multiplies `perLook`, so `Tip.ValueFraction` and `ByWorld` still tune it.
	Pace = { 0.0329, 0.0208 },
}
return CustomerConfig


