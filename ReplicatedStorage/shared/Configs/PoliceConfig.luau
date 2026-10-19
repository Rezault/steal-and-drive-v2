--[[
	PoliceConfig
	------------
	THE POLICE CHASE. You drive past the city's police section, the sirens start, and for the next
	forty seconds two cruisers ride your rear quarters with a helicopter overhead. The rule while
	they are on you is one rule: DON'T MAKE TWO MISTAKES IN A ROW. Every crash takes a bite out of
	the bar and every second on the brake bleeds it, and they close as it falls; empty it and they
	PIT you off the road, and the run ends as a wreck with a different word on it (`Cause` below,
	"BUSTED").

	Five things to know before editing.

	1. THE PRESSURE GAUGE IS THE CRUISERS THEMSELVES, not the bar on screen. Every offset in this
	   file is interpolated by ONE number, so a player who never looks at the HUD still reads their
	   situation out of the window. The bar exists to make that legible on the frame where it
	   matters, not to be the only place the state lives. If you retune one, look at the other.

	   THAT NUMBER RUNS 0 TO 2 AND HAS FOUR THINGS IN IT (`PoliceConfig.station` is the only reader,
	   `PoliceController._stationValue` the only composer):

	       the BAR        0..1, the gauge above. Drains on the brake, bitten by a crash.
	       the LEAD       +0..1, how far you are pulling away (`Lead`). Only above a full bar.
	       the SWOOP      a decaying dive in on the frame of a crash (`Strikes.Swoop`).
	       the ARRIVAL    a ceiling for the first seconds of a chase (`Entry`).

	   So one chase is four different shots out of the same window: they sweep up level with your
	   door as the sirens start, settle back into a pursuit, sink out of the bottom corners while you
	   are driving it clean, and dive back onto you the instant you touch anything. Under `Lineup.From`
	   one of them stops holding station at all and starts setting the arrest up.

	2. A CRASH IS WHAT COSTS YOU, and the rule is the endless runner's: one mistake is survivable,
	   two on top of each other are not. Every impact the road can hand you (an obstacle, a traffic
	   car, a scrape down the guardrail) takes an immediate BITE out of the bar sized by how hard it
	   was, and a bite landing inside `Strikes.Chain.Window` of the last one is MULTIPLIED. So a
	   sideswipe on its own is a wobble you drive off, and a sideswipe followed by a barrier a second
	   and a half later is an arrest. The bar refills on its own once you have been clean for a beat,
	   which is the whole of what makes "too close together" mean anything.

	   BRAKING IS THE OTHER HALF, and it is a drain rather than a bite: hold the brake, settle under
	   `Floor`, and the bar bleeds for as long as you are down there. A dab costs a tenth of it and
	   the cruisers come level; leaning on it for eight seconds is an arrest. One number, two ways to
	   spend it, and the player can watch both out of the window.

	   THE BOTTLE IS THE ONE THING THAT BUYS IT BACK FASTER. Burning nitro while the car is over the
	   floor runs the chase's clock down faster, refills the bar faster after a crash and carries the
	   cruisers off you sooner (`Nitro`). It never changes what a crash costs.

	   THE POLICE THEMSELVES ARE STILL NOT SOLID. Every part of every pursuer is `CanCollide = false`
	   and `CanQuery = false`, so a cruiser cannot hit you by accident, cannot be hit, cannot take
	   your HP and cannot be steered around by traffic. The one contact in the whole feature is the
	   PIT that ends a chase (`Pit`), and that is not a collision either: it is a scripted impulse on
	   a car whose run is already over.

	3. IT IS CLIENT SIDED, like the road, the traffic, the obstacles and the truck. Driving is solo,
	   so each player owns their own copy of the world and none of this replicates
	   (see `RoadController`). `PoliceService` publishes the two vehicles and ratifies the bust, and
	   that is all the server does. What it costs in trust is the same accepted gap
	   `GetawayService` documents, pointing the same way: a client that lies about this ends its own
	   run early.

	4. THE SECTION IS AN ATTRIBUTE ON A ROAD TILE, NOT A TAG. `RoadController` builds most of its
	   tiles through an incremental builder that creates a fresh `Model` and copies the variant's
	   ATTRIBUTES onto it (see its `_stepPrefetch`). CollectionService tags are not copied by that
	   path, so a tagged tile would arm the chase on the frames a whole clone happened to be used
	   and on no others, which is the worst kind of bug to be handed. `Sections` below is the
	   record of which tiles are police sections; `PoliceService` stamps `SectionAttribute` onto
	   them at publish, and honours one a modeller has set by hand.

	5. VEHICLE GEOMETRY IS MEASURED, NOT GUESSED. Both models ship as ONE anchored MeshPart each,
	   nose along local -Z once placed by `CFrame.lookAt`, and every offset below was raycast off
	   the mesh rather than read off `MeshPart.Size` (which is a box that can be much bigger than
	   the geometry inside it). The numbers are recorded beside the fields that use them so a new
	   model can be fitted by re-taking the same measurements.

	HOUSE RULE: no wiki-style double-bracket links in this comment. The closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ For the ladder a stolen car sits on, and for nothing else. `StealHeat` below is a RUNG test,
	and a rung only means something against the world the car belongs to. `WorldConfig` requires
	nothing itself, so this cannot cycle. ]]
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local PoliceConfig = {}

--- Master switch. Off = no chase ever arms, no vehicle is published, and the police section is a
--- stretch of scenery you drive past. Nothing is left half live.
PoliceConfig.Enabled = true

-- === Names ==================================================================

--- The authored `Workspace` folder the modeller shipped, and what the two models are called inside
--- it. `Model` is the helicopter's shipped name and is deliberately reproduced rather than fixed in
--- the place: the place file is the modeller's, and renaming their instances is how a re-import
--- quietly breaks a lookup.
PoliceConfig.SourceFolderName = "PoliceVehicles"
PoliceConfig.SourceNames = { Car = "PoliceCar", Heli = "Model" }

--- Where the publish lands, in ReplicatedStorage, and what each vehicle is called there. Clients
--- clone from these. Named properly on the way out, because from here on the name is code's.
PoliceConfig.TemplateFolderName = "PoliceVehicles"
PoliceConfig.TemplateNames = { Car = "Cruiser", Heli = "Helicopter" }

--- ServerStorage folder the authored models are parked in for the session, shared with the getaway
--- truck's. Non destructive: an edit session reverts on stop, so they stay where the modeller left
--- them in the place file.
PoliceConfig.StashName = "StashedProps"

--- Client only Workspace folder the live chase lives in. Deliberately NOT inside a road tile: a
--- pursuer holds station relative to the PLAYER and would be dragged nine tiles by the next recycle
--- of whichever tile it happened to be over. It keeps its own road-frame position instead and rides
--- `RoadController:onWorldShift` through a rebase, exactly as traffic does.
PoliceConfig.FolderName = "PoliceChase"

-- === Where a chase starts ===================================================

--[[ The boolean attribute that makes a world tile a police section. Set on the authored tile, and
	therefore carried onto every copy of it the road lays (note 4).

	Read on the LIVE tile rather than looked up per map, so a modeller can mark a new tile in Studio
	and have it arm a chase without touching this file. ]]
PoliceConfig.SectionAttribute = "PoliceSection"

--[[ Which tiles of which maps are police sections, as `[map] = { tile names }`.

	`City/4` is the one that exists today: the tile carrying `Props.Polices` (sixteen parked
	cruisers), plus the tape, the light cones and the jersey barriers that go with them. It is the
	only stretch of any of the five authored maps that has police art on it.

	This is the RECORD, not the mechanism (note 4). Deleting an entry here does not un-mark a tile
	that has already been stamped in the place file, and adding one to a map the modeller has not
	built police art for gives you a siren over ordinary scenery. ]]
PoliceConfig.Sections = {
	City = { "4" },
}

--[[ The tile index a world with NO marked section arms at instead, or nil for "this world has no
	police".

	nil is the shipped answer and it is not a placeholder. Three of the four worlds are greybox
	passes with no police art anywhere in them (`WorldConfig`'s "The maps"), and a chase that
	arrives out of empty desert is a siren with nothing behind it. When those worlds are themed,
	the tile they put a police section on gets the attribute and this stays nil.

	It exists because the alternative is worse: without it, testing the chase in any world but the
	City means editing the City's art. Set it to a small number to arm a chase early in every
	world, which is what a tuning pass wants. ]]
PoliceConfig.FallbackTile = nil

--[[ How far BEFORE the section's leading edge the sirens start, in studs.

	The section is a whole tile long (1,173 studs on the City) and the point of arming off the art
	is that the art is the cause: the player should hear it as they come up on the police station,
	not a quarter of a minute after driving past it. 260 is a little over three seconds at cruise,
	which puts the first siren about where the tape and the light cones come out of the fog.

	Measured against the tile's START, so it is unaffected by how long a tile is. ]]
PoliceConfig.ArmLead = 260

--[[ NO CHASE WITH THE TRUCK IN REACH (2026-10-14, Aleafo: "police just appeared when I was like 50
	studs from the truck; make it not spawn if you are x studs from a truck"). While a getaway truck
	is on the road within `TruckClearance` studs of the player's car, a chase may not START: the road
	triggers wait and a steal's call-in is held, not spent, so it can still fire once the truck is
	gone. A chase already running is untouched, and `GetawayConfig.PoliceLock` still governs that one.
	300 is a few seconds at cruise: the truck is in plain view by then, and a siren arriving with
	the ramp already in sight reads as the game snatching the bank away. 0: chases start as before.
	Once the car is IN the truck nothing arms at all, whatever this is (`PoliceController.onBanked`). ]]
PoliceConfig.TruckClearance = 300

--[[ Tiles of further progress before the police come back, once they have been met.

	THIS EXISTS BECAUSE A SECTION IS REACHED EXACTLY ONCE. The road's segments are a progression,
	not a shuffle (`RoadController`'s "Which road"): with a `SegmentHold` of 3 the City's six tiles
	run 1,1,1,2,2,2,...,6,6,6 and then hold on 6 for the rest of the run, so tile 4 is on the road
	while the tile index is 9 to 11 and never again. Without a repeat the answer to "can the police
	come back?" would be no, in the only world that has police at all.

	It only starts counting AFTER a chase has happened, so the police section is still the thing
	that introduces them. What it says after that is that you are a car they are looking for. Six
	tiles is about 7,000 studs, or roughly eighty seconds at cruise, which lands comfortably outside
	`Cooldown` and makes a four minute run two or three chases rather than one.

	nil or 0 turns it off, and the chase becomes the single scripted event the section triggers. ]]
PoliceConfig.RepeatTiles = 6

--[[ How long a chase lasts once armed, in seconds, rolled per chase.

	Forty seconds is about six hundred studs of holding your nerve at cruise, which is long enough
	to be a stretch of the run rather than an incident and short enough that the answer to it is
	"drive", not "endure". The band is there so two chases in one run do not feel like the same
	scripted event twice.

	It is REAL seconds and not scaled ones. A chase that could be paused by a slow-motion bail would
	be a chase a player could sit out.

	Nitro is the one thing that shortens it, and by no more than `Nitro.MaxCut`. ]]
PoliceConfig.Duration = { 30, 38 }

--[[ Seconds after a chase ends before another one can arm.

	Long enough that the second half of a long run is not one continuous siren, short enough that a
	four minute run gets two or three chases. It is measured from the END of the last one, so a
	player who loses the police right on top of a second police section gets a beat of quiet first.

	It also covers the case the section-based trigger cannot: a rebase or a recycle can put the same
	marked tile in front of the player again within seconds, and without a cooldown that is an
	instant re-arm. ]]
PoliceConfig.Cooldown = 70

--[[ THE OTHER WAY A CHASE STARTS: TAKING A CAR WORTH COMING FOR.

	Everything above arms off the ROAD, either the police section itself or the repeat that brings
	them back once you have met them. This arms off the PLAYER. Land a steal on one of the best
	cars in your world's ladder and it gets called in, and the sirens follow a beat later.

	IT IS THE TOP OF *YOUR* LADDER AND NOT A GLOBAL TIER, which is the whole reason this is a rung
	test rather than a price. Every world restarts its ladder (`WorldConfig` note 3): world 1's best
	car is tier 8 and world 4's worst is tier 23, so any single tier or dollar figure would fire on
	every steal in the late worlds and on none at all in the first. `TopRungs` is read against the
	world the STOLEN CAR belongs to, so "the good stuff" means the same thing in all four.

	IT NEEDS NO TIMING OF ITS OWN, because the ladder already gates itself. The top rungs join the
	traffic pool at the far end of `TrafficConfig.Bands` (the best car from tile 10), so there is no
	such thing as a high value steal in the opening minute, and nothing here has to know about the
	tutorial or about where the police art is. What it does instead is scale the danger with GREED
	rather than with distance, which is the one thing the two road triggers cannot do: a player who
	trades up as hard as they can is a player who gets chased, and a player content in a beater
	drives the same road untouched.

	A CALLED-IN CHASE IS AN ORDINARY CHASE. Same rolled `Duration`, same bar, same rules, same
	`StealGrace` covering the handoff it arrives on top of, and it counts toward `RepeatTiles` like
	any other. The only difference the player is shown is the alert line (`Hud.Alert.StealSubText`),
	because a chase that starts for a reason should say the reason. ]]
PoliceConfig.StealHeat = {
	--- Off = a steal buys grace and nothing else, which is all it did before this existed.
	Enabled = true,

	--[[ How many rungs at the top of a world's ladder are worth chasing. The shipping worlds are 7
		and 8 cars, so 3 is the last third of one: world 1's Challenger, Mustang and M5.

		2 makes it something you see once or twice in a good run. 1 is the top car alone, which is
		one spawn in 43 once the whole ladder is unlocked and can go a session unseen. Anything at
		or above a world's car count would arm on its beater, so it is clamped one rung short. ]]
	TopRungs = 3,

	--[[ Seconds between the handoff and the sirens. It is a dispatch beat rather than a delay: the
		mount lands, the player has the car for a moment, and then it gets called in. On the same
		frame it reads as a chase that was already coming, and much past a second it reads as
		unrelated to the steal. ]]
	Delay = 1.1,

	--[[ How long that call stays live if it cannot be answered at once, in seconds.

		A steal landed during a chase, during the peel-off or during an arrest stamps the call just
		the same, and this is what decides what becomes of it. The peel-off is 2.4s and sits inside
		the window, so police who have just given up turn straight back round for a car that is
		worth it. A chase that runs its full forty seconds does not, so surviving one is never
		answered by a second one arriving on the frame it ends. ]]
	Window = 8,

	--[[ Whether a call ignores `Cooldown`. True, and deliberately: the cooldown exists to stop the
		ROAD re-arming off a tile that came round again and off the repeat counter, and neither of
		those is what happened here. The player did something, and the answer to it has to be the
		same every time or it is not a rule they can learn.

		The one thing it never ignores is a run that is already ending. `_onWrecked` drops the call
		outright rather than leaning on this. ]]
	IgnoreCooldown = false,
}

--[[ HEAT (2026-10-19, Aleafo: "u steal an egg u get chased by guard immediately ... u do something
	and there is a direct consequence, for us there isnt one"). EVERY steal now calls the police, not
	only a top-rung one (`StealHeat`), and every steal raises the heat:

	    a steal              +`PerSteal` stars (+`HighValueBonus` for a top-rung car), up to `Max`
	    a steal mid-chase    the chase runs `ExtendOnSteal` seconds longer, and the heat still rises
	    more stars           a longer chase (`DurationPerStar`), the second cruiser at `SecondCruiserAt`
	                         and the helicopter at `HeliAt`
	    losing the cops      the live heat clears ("LOST THEM")
	    banking              pays 1 + `PayoutPerStar` x the stars EARNED this run (capped at `Max`)

	THE TRUCK ALREADY WAITS FOR AN ESCAPE (`GetawayConfig.PoliceLock`): no truck while a chase is on.
	So the loop becomes steal, escape, bank, and the greed question is "one more steal, or bank now
	while it is quiet?": the next car is more money at the bank and another chase to survive first.

	THE PAYOUT IS THE SERVER'S. `RewardService` counts the stars off `StealService.CarStolen`, the
	steals it verified against its own encounter tokens, with the same `heatOfSteal`; the HUD's count
	is the client's own tally of the same rule and only draws it.

	A ROAD CHASE IS AS BEFORE: the full pair and the helicopter, as if at `RoadStars`. The tutorial's
	run gets no heat at all, the same exemption `StealHeat` makes for it.

	`Enabled = false`: a steal calls the police only for a top-rung car, no stars, no bonus, exactly as
	before. This is the switch an A/B test flips. ]]
PoliceConfig.Heat = {
	Enabled = true,
	Max = 5,
	PerSteal = 1,
	HighValueBonus = 1,
	--- Seconds added to the rolled `Duration` per star past the first.
	DurationPerStar = 5,
	ExtendOnSteal = 8,
	SecondCruiserAt = 2,
	HeliAt = 3,
	RoadStars = 3,
	--- 0.15 a star: an escape from a five-star run banks 1.75x. A taste call to start from: it has to
	--- beat banking early on a quiet road, and stay under a weather mutation's jackpot (`WeatherConfig`).
	PayoutPerStar = 0.15,
	--[[ The HUD's readout: its top-left corner and the stars' height, as screen shares, and its words.
		TOP LEFT, under Roblox's topbar (0.02..0.09) where the rail stood before a run took it away
		(`RaceConfig.HideRailDuringRace`). WAS centred at 0.16 (2026-10-19), inside the band the speed
		trap warning and the chase bar's caption share (`Hud.Alert`'s measured survey), and the three
		drew over each other. ]]
	HudX = 0.02,
	HudY = 0.11,
	HudHeight = 0.04,
	Star = "★",
	EmptyStar = "☆",
	BonusFormat = "x%s CASH",
	LostSubText = "Heat cleared. Bank it for x%s",
}

--- Stars one steal adds (`Heat`). 0 with heat off. Shared, so the HUD and the payout count alike.
function PoliceConfig.heatOfSteal(tier: unknown): number
	local heat = PoliceConfig.Heat
	if not (PoliceConfig.Enabled and heat.Enabled) then
		return 0
	end
	return heat.PerSteal + (if PoliceConfig.isHighValueSteal(tier) then heat.HighValueBonus else 0)
end

--- What a bank pays for `stars` earned this run: 1 + `PayoutPerStar` a star, capped at `Max`.
function PoliceConfig.heatMultiplier(stars: unknown): number
	local heat = PoliceConfig.Heat
	if not (PoliceConfig.Enabled and heat.Enabled) or type(stars) ~= "number" or stars ~= stars then
		return 1
	end
	return 1 + heat.PayoutPerStar * math.clamp(stars, 0, heat.Max)
end

--- Seconds the pursuers take to peel off after the chase is survived, and how far they go while
--- doing it. The cruisers fall back and the helicopter climbs away, both under their own easing, so
--- the end of a chase is something you watch happen rather than a set of vehicles blinking out.
PoliceConfig.PullAway = { Time = 2.4, Studs = 190, Rise = 120 }

-- === Being caught ===========================================================

--[[ The speed you have to hold, as a FRACTION OF WHAT YOUR OWN CAR CRUISES AT.

	A fraction and not a number of studs per second, because a Tier 1 Civic cruises at 73 and a
	Charger at 85 and the ladder goes further than that: any absolute floor is either free in a
	fast car or unsurvivable in a slow one. The reference is the car's base `MaxSpeed` dial
	converted through `WindConfig.StudsPerMaxSpeed`, which is the same conversion the wind effect
	uses and the one place that measurement is kept.

	0.68 lands at about 50 studs/s in the starter Civic, against a 73 studs/s cruise: ordinary
	driving clears it by a third and no amount of steering, threading or lifting off comes near it.
	What it is sized against is THE BRAKE. `DriveConfig.MinSpeedFraction` settles a held brake at
	45% of the run's peak, which after any boost at all is about 44 studs/s, so a player leaning on
	the brake is under this floor and is on a clock. That is the one thing this beat has to make
	true, and it is why the number is a hair above the brake floor rather than a hair below it.

	Nudge it up and the chase becomes a boost-holding test. Nudge it down past 0.60 and you can
	brake your way through one, at which point the whole beat is decoration. ]]
PoliceConfig.Floor = 0.62

--[[ Seconds at a DEAD STOP to go from a full bar to an empty one.

	Three and a half seconds of being genuinely stopped is a long time on this road, and it is sized
	so the recoverable case (a shunt, a bad line through a course) and the unrecoverable one (wedged
	against debris, facing the wrong way) come apart on their own without anything having to
	classify them. ]]
PoliceConfig.DrainTime = 5

--[[ ...and what fraction of that rate applies the instant you are under the floor AT ALL.

	THIS IS THE SHAPE OF THE LEEWAY, and getting it wrong in either direction ruins the beat.

	A purely proportional drain (rate scaling with how far under the floor you are, from nothing) was
	the first version and it was far too soft: a car dawdling at 88% of the floor drained at a
	fiftieth of a bar a second, so holding the brake for a whole chase cost about a quarter of one.
	Half of what the player is being taught here is KEEP MOVING, and a half you can ignore for forty
	seconds is not a half.

	A flat rate is the other failure. It makes a lift off the throttle exactly as expensive as a
	full stop, which is what makes a system feel arbitrary: two very different mistakes, one
	punishment. (What a CRASH costs is `Strikes`, and it is not measured here at all.)

	So the rate is this fraction plus the rest scaled by how far under you are. At 0.35 and a drain
	time of 3.5 the two ends are TEN SECONDS for hanging just below the floor and THREE AND A HALF
	for being stopped, with everything in between sitting on a straight line between them. Ten
	seconds is long enough to recover from and short enough that a chase spent under the floor ends
	in an arrest. ]]
PoliceConfig.MinDrain = 0.25

--[[ === WHAT THE BRAKE HALF ACTUALLY ADDS UP TO, MEASURED =====================================

	Taken on the road in the starter Civic (cruise 73 studs/s, floor 49.6), because the shape of this
	half of the beat is not obvious from the constants and the next person to retune it should not
	have to find this out again:

	    a dead stop back over the floor      0.61 s, costing about 0.13 of the bar
	    a traffic clip (SpeedKeep 0.86)      73 -> 63, never reaches the floor at all
	    the harshest obstacle (SpeedKeep 0.5) 73 -> 37, under the floor for about 0.4 s
	    a held brake (DriveConfig floor ~44) under the floor indefinitely, 8.3 s to an arrest
	    genuinely stopped                    3.5 s to an arrest

	SO THE DRAIN PUNISHES BEING STOPPED, not being slow, and the two crash rows above are why it is
	not the whole beat. The chassis accelerates hard enough that an impact is over as a SPEED event
	before the bar has noticed it happened: the harshest obstacle in the game buys four tenths of a
	second under the floor, which is a twentieth of a bar. A chase that only measured speed would let
	a player plough through a barrier, a traffic car and a second barrier and lose almost nothing,
	which is exactly the beat that was there before `Strikes` and exactly why it did not read.

	So the crash is priced where the crash happens (`Strikes` below), and the drain is left to do the
	one thing it was always good at: pricing the brake, and pricing the case the road had no answer
	for, which is wedged against debris and going nowhere.

	IF THE BRAKE HALF EVER FEELS TOOTHLESS, `Floor` is the lever and not `DrainTime`. At 0.68 the
	margin between cruise and the floor is a third, so ordinary driving is never at risk; raising it
	toward 0.80 narrows that until lifting off for a corner costs real bar. Do not go past about
	0.85, which is where a car that brakes for a slalom is arrested for it. ]]

--[[ Seconds above the floor to refill an empty bar.

	SLOWER THAN THE DRAIN, which is a reversal of what this number used to be and the single most
	load-bearing change in the strike model. At the old 1.6 the bar was back to full about two thirds
	of a second after a barrier took a third of it, so "hit two things close together" was a rule
	with nothing behind it: the bar had already forgiven the first one. A chase where the cost of a
	mistake evaporates faster than the player can make a second one is a chase with no memory.

	At 5.0 a full barrier's bite (0.42) takes just over two seconds of clean driving to pay off, so
	the seconds after a crash are seconds in which the cruisers are visibly closer than they were.
	That is the pressure. `Strikes.Chain` is the teeth; this is the memory that makes the teeth
	reachable.

	It is deliberately not slower still. Past about 7 a run that took one bad corner early spends the
	rest of the chase in the red however well it is driven, which is the failure the old note
	described from the other direction: a chase that is unwinnable once it has started to go wrong. ]]
PoliceConfig.RefillTime = 5.0

--[[ === GETTING AWAY: WHAT DRIVING WELL LOOKS LIKE OUT OF THE WINDOW =========================

	The bar answers "how close am I to being caught" and it STOPS AT FULL, so every clean second
	after the one that topped it up looks exactly like the one before it: two cruisers parked on
	your quarters, forever. That is the half of the beat this section adds. `Lead` is a SECOND 0..1
	that only exists once the bar is already full, and it carries every station one notch further
	out again, to the `Lead` end of the `{ Far, Near, Lead }` triples further down. Drive cleanly
	and quickly and the cruisers sink out of the bottom corners of the frame and the helicopter
	climbs away; make one mistake and they are back inside a second.

	IT IS THE ENDLESS RUNNER'S SHAPE AND IT IS THE POINT OF THE WHOLE FILE. A pursuer that is
	always exactly where it was has nothing left to say after the first five seconds of a chase. One
	that drops out of the shot while you are running well is what makes it ARRIVING mean something.

	WHY IT IS A SECOND NUMBER AND NOT AN OVERFLOW OF THE BAR. An overflow would be tidier and it
	would be wrong in one specific way: a crash would have to eat the overflow before it touched the
	bar, so the first mistake after a good run would cost the player nothing the HUD could show, and
	the bar is the thing they are being marked on. Kept apart, a strike zeroes this outright
	(`reportStrike`) AND takes its full bite out of the bar, which is both halves of what a mistake
	is supposed to do: the punishment lands, and the reward for not having made one is withdrawn.

	IT CHANGES NO RULE. Nothing here can bust a player, save a player, or move the bar. It is the
	distance between the cars and nothing else, which is why it is safe to retune on feel alone. ]]
PoliceConfig.Lead = {
	--- Off = the cruisers hold the `Far` station for the whole of a clean chase, which is what
	--- shipped before this. Worth switching once to feel what it was doing.
	Enabled = true,

	--[[ Seconds of clean driving AT CRUISE to go from the ordinary chase station all the way out to
		the `Lead` one.

		Longer than `RefillTime`, deliberately. Getting the bar back is recovering from a mistake and
		this is what you get for having recovered and then held it, so it must not be reachable
		inside the beat that pays the last crash off or the two read as one thing. At 6.5 a player
		who crashes once mid-chase never sees a full lead again in that chase, and a player who
		drives it clean watches them drop away at about the ten second mark. ]]
	Gain = 6.5,

	--[[ ...and seconds to come all the way back in when the bar comes off full or the car drops
		under the floor.

		MUCH FASTER THAN IT BUILT, because closing is what the police are for. A lead that leaked
		away at the rate it accumulated would make lifting off weightless: the whole read is that
		ground is slow to take and instantly given back. ]]
	Drop = 1.6,

	--[[ How much faster the lead may build than it does at the car's own unboosted cruise.

		The gain is scaled by where the car sits between `Floor` and cruise, so easing off slows the
		lead down long before it costs any bar, and holding boost pushes the scale past 1 up to this
		cap. `DriveConfig.BoostSpeedScale` is 1.35, so 1.5 is comfortably above anything the car can
		actually reach and the cap is a guard rather than a tuning knob: it is here so a chassis
		change that doubles the top speed cannot halve the length of the beat.

		Nitro rides on top of this rather than through it (`Nitro.LeadScale`), because this cap is
		exactly why a bottle used to buy nothing here that a held pedal did not. ]]
	Max = 1.5,
}

--[[ === STRIKES: WHAT A CRASH COSTS =========================================================

	THE ENDLESS-RUNNER RULE, and the reason this section exists at all. One mistake is survivable and
	two on top of each other are not: a sideswipe is a wobble the player drives off, and a sideswipe
	followed by a barrier a second later is an arrest. Everything below is that sentence in numbers.

	EVERY HAZARD FEEDS THIS THROUGH ONE DOOR. `ObstacleController.applyImpact` is the single path
	every impact in the game already goes through (obstacle clips, guardrail scrapes and
	`TrafficController`'s car clips all call it), so the strike is taken there and nothing has to be
	wired per hazard. A hazard added tomorrow that calls `applyImpact` is priced by the police for
	free, and one that does not call it is invisible to the police for exactly the same reason it is
	invisible to the camera shake.

	SEVERITY IS READ OFF `Shake`, WHICH IS NOT AN ARBITRARY CHOICE. The obvious field is `SpeedKeep`
	and it does not work: with `TrafficConfig.Collision.Enabled` the real contact supplies the shove,
	so a traffic clip's `ClipFeel.SpeedKeep` is exactly 1 and every car in the game would read as a
	graze. `Shake` is the one field every hazard sets, it is literally the "how much did that hurt"
	dial, and `TrafficController._scaleKind` already scales it by the clip's own measured severity,
	so a graze and a T-bone arrive here already told apart. ]]
PoliceConfig.Strikes = {
	--- Off = crashes cost the bar nothing directly and the chase is the speed drain alone, which is
	--- what shipped before this. Worth switching once to feel the difference the beat is built on.
	Enabled = true,

	--[[ The `Shake` band severity is measured across: at or under `Graze` a hit is severity 0, at or
		over `Full` it is 1, and it is linear between them.

		WHERE EVERY HAZARD IN THE GAME LANDS ON IT, so a retune can be checked rather than guessed:

		    traffic, lightest graze   0.225   ->  0.00
		    a cone                    0.35    ->  0.13
		    an oil slick              0.4     ->  0.20
		    a guardrail scrape        0.5     ->  0.33
		    a barrel                  0.7     ->  0.60
		    traffic, square hit       0.75    ->  0.67
		    a crate                   0.8     ->  0.73
		    a barrier                 1.2     ->  1.00
		    a concrete block          1.6     ->  1.00

		A barrier reading the same as a concrete block is intended: both are "you hit the worst thing
		on this road", and the bar has nowhere further to go. ]]
	Shake = { Graze = 0.25, Full = 1.0 },

	--[[ ...and what a strike takes out of the bar, at severity 0 and at severity 1.

		`Min` IS NOT ZERO ON PURPOSE. A contact light enough to register no severity at all still
		registered as a contact: the smoke puff came out, the camera shook, and a player who felt all
		of that and watched the bar not move learns that the police are not really watching. A tenth
		is small enough to drive off and large enough to see.

		`Max` at 0.42 makes the worst single hit in the game cost a little under half the bar, which
		is the number the whole beat balances on. Much lower and two hard hits are survivable, which
		is the old toothless chase back again; much higher and one is fatal, which removes the
		decision the beat is made of. Half a bar per crash, two crashes per arrest, is the shape. ]]
	Bite = { Min = 0.06, Max = 0.24 },

	--[[ THE CHAIN: what makes "too close together" different from "twice".

		A strike landing within `Window` seconds of the last one is multiplied by `Scale`, and one
		landing inside the window of THAT is multiplied again, up to `MaxLinks` deep. So the price of
		a crash is not only what you hit, it is when you hit it.

		WORKED THROUGH, in the starter Civic against a full bar, hitting a barrier (bite 0.42):

		    one barrier, then clean road      1.00 -> 0.58, back to full in 3.1 s
		    a second 1.5 s later              0.68 -> BUSTED   (0.42 x 1.9 = 0.80)
		    a second 3.0 s later              0.98 -> 0.18     (still 0.80, and they are on your door)
		    a second 5.0 s later              1.00 -> 0.58     (outside the window: a fresh mistake)
		    two traffic clips 1.5 s apart     1.00 -> 0.19     (0.31, then 0.59)
		    three traffic clips inside 3 s    BUSTED on the third

		1.9 is the number that makes the second row land where it does, and the second row is the
		feature. `Window` at 3.5 is about the time the refill needs to pay one bite off, so the window
		closing and the bar recovering happen at roughly the same moment: the player has one clear
		signal for "you are clean again" rather than two that disagree.

		`MaxLinks` caps the depth at 3 so a chain cannot run away into a bite of four bars, which
		matters for nothing the player will ever see and everything a tuning pass will. ]]
	Chain = { Window = 2.5, Scale = 1.35, MaxLinks = 2, MaxBite = 0.4 },

	--[[ Seconds after a strike before the bar starts refilling again.

		A bite that began healing on the next frame reads as a bar that bounced rather than one that
		was taken from, and it costs the player the one moment they had to see what the crash cost.
		A second of hold is long enough to read the new level off the screen and off the mirror, and
		short enough that it is not a second punishment stacked on the first.

		It holds the REFILL only. The drain is untouched, so a player who crashes and then sits there
		under the floor goes on losing bar through it. ]]
	Settle = 1.0,

	--[[ THERE IS NO LUNGE HERE ANY MORE, AND THE FIELD IS GONE RATHER THAN ZEROED.

		There used to be one: on the frame of a hit the cruisers were moved 75% of the way to the
		station the new bar asked for, outright, so that the crash and the closing read as one event
		rather than two. It solved a real problem and it solved it by teleporting a car, and that is
		exactly what it looked like. A cruiser that changes position without ever having a speed
		does not read as a driver reacting; it reads as the model being picked up and put down, and
		because the heading is composed out of the car's own cross rate (`PoliceController._placeCar`)
		it also read as a PIVOT: the nose swung over on the frame after the jump and swung back.

		WHAT REPLACED IT IS `Cruisers.Lag`, which is now a critically damped spring rather than an
		exponential ease. That is the whole fix and it is worth understanding, because the two look
		the same in a graph of position and are opposites in a graph of speed. An exponential ease
		starts at its FASTEST and slows down all the way in, so a station that steps hands the car
		its top speed on frame one, which is the same "suddenly there" the lunge was buying and is
		why the lunge could sit on top of it without looking any worse. A critically damped spring
		starts at zero and accelerates, which is what a car does. Same arrival, and the first tenth
		of a second is a car pulling out rather than a car appearing.

		The connection the lunge existed to make is now made by `Swoop` below, which is a bigger and
		longer dive than it used to be for exactly this reason: the theatre moved out of the frame
		of the hit and into the second after it. ]]

	--[[ THE SWOOP. How far PAST the station the new bar asks for a strike drives the cruisers, on
		the same 0..2 scale everything else here is placed against, how long it holds there at full,
		and how long the whole dive lasts before they are back on what the bar actually says.

		IT IS THE WHOLE OF THE REACTION NOW that the lunge is gone (above), which is why it is bigger
		and longer than it was: 0.30 over 1.6 seconds with a hard snap under it has become 0.40 over
		2.0 with a spring under it. The bite a light hit takes is small, and a station that moves by
		the width of that bite is a station the player cannot see move; the swoop is what makes a
		graze visible. They drive up, sit on you for a beat, and drift back out.

		`Hold` IS WHAT MAKES THE SPRING AND THE DIVE AGREE, and it is new. The dive used to decay from
		its full value on the frame it started, which was fine against an ease that covered most of
		the ground immediately. A spring takes about a second to arrive, so a target that starts
		retreating at once is a target the car never reaches: the dive would be soft in a way none of
		the numbers admitted to. Half a second at full is roughly the spring's own trip, so the car
		gets all the way in before the station starts giving it back.

		SCALED BY THE BITE AND THEREFORE BY THE CHAIN. `Amount` is what the worst single hit in the
		game gets (`Bite.Max`); a cone gets a quarter of it, and a chained hit is already over `Max` and
		clamps to the full swoop. So the second mistake in three seconds brings them in harder than the
		first did, which is the chain rule stated in position rather than in numbers.

		IT IS PLACEMENT ONLY. Nothing reads it but the stations: the bar, the bust and the HUD are
		untouched, so it can be retuned to taste without moving the difficulty an inch.

		`Hold` + the ramp out want to land near the `Settle` above and the `Chain.Window` after it.
		All of them are the beat in which the player is meant to be looking at what the crash cost.

		The ramp out is smoothstepped rather than linear, so they leave gently and are gone by the
		end rather than sliding out at a constant rate and stopping. ]]
	Swoop = { Amount = 0.40, Hold = 0.5, Time = 2.0 },
}

--[[ === NITRO: SHAKING THEM OFF ==============================================================

	The one thing a player can DO about a chase besides not crashing. Everything above prices a
	mistake; this pays for a decision, and the decision is spending the bottle (`NitroConfig`). While
	it burns, four things that were already happening happen faster:

	    the CLOCK     the rolled `Duration` counts down faster, so LOST THEM comes sooner
	    the REFILL    the bar climbs back faster after a crash (`RefillTime`)
	    the SWOOP     the dive a crash put on the cruisers lets go sooner (`Strikes.Swoop`)
	    the LEAD      they drop away faster once the bar is full (`Lead`)

	THE TWO HALVES OF A CHASE SPEND IT DIFFERENTLY, which is what keeps it fair both ways. On a full
	bar the refill and the swoop have nothing to do, so the bottle goes into the lead and the clock:
	the cruisers slide out of the corners of the frame and give up sooner. Straight after a crash the
	lead has been zeroed and cannot build, so the same bottle goes into the refill and the swoop: they
	fall off your door instead of sitting on it. The clock runs in both.

	NONE OF IT TOUCHES WHAT A CRASH COSTS. A strike during a burn takes full price, chains exactly as
	it would have, and zeroes the lead the burn was building. That is the counterweight and it is a
	real one: nitro is the fastest thing on the car, and the fastest thing on the car is the likeliest
	to put you into the back of a traffic car.

	IT HAS TO BE MOVING YOU. Every term is gated on the car being over `Floor`, so a player wedged
	against debris with the button held is still going nowhere, and the clock does not run down for
	them. ]]
PoliceConfig.Nitro = {
	--- Off = a bottle buys a chase nothing a held accelerate does not, which is what shipped before
	--- this.
	Enabled = true,

	--[[ How fast the chase's clock runs while burning. 2 is a second of burn counting as two seconds
		of chase.

		WORKED THROUGH against the 34 to 44 second `Duration`. A bottle is 2.6 seconds of burn on a
		world's beater and 4.2 on its best car, and it refills in about eleven (`NitroConfig.Tank`), so
		a player who spends every bottle they get burns two or three per chase. Simulated at 240Hz
		that takes 6 to 8 seconds off in the beater and 8 to 10 in the best car, the top of which is
		`MaxCut`: about a fifth shorter, which is a chase you got out of faster rather than a
		different beat. ]]
	ClockScale = 2,

	--[[ The most one chase can be shortened by, in seconds. A guard more than a tuning knob: it is
		what stops a long near-miss chain feeding a bottle that never empties from turning a chase into
		a formality. At 10 the shortest a chase can ever be is 24 seconds. ]]
	MaxCut = 10,

	--[[ How much faster the bar refills while burning, over `RefillTime`.

		SIZED AGAINST THE CHAIN, because that is the rule this could quietly break. Two barriers 1.5
		seconds apart is an arrest (`Strikes.Chain`'s worked table) and it has to stay one with the
		button held. After the first the bar is at 0.58 and held for `Strikes.Settle`, and the second
		costs 0.80, so the refill has half a second to find 0.22 and must not. At 1.8 it finds 0.18.
		What it does buy is the second barrier at TWO seconds, which is an arrest on a dry bottle and
		a close call on a lit one, and one barrier paid off in 2.2 seconds instead of 3.1.

		IT DOES NOT SKIP THE SETTLE. The second after a crash is the second the player reads what it
		cost, and a bar that started climbing on the next frame because a key was held would read as
		bouncing rather than as taken from. The swoop below is what makes that second look different. ]]
	RefillScale = 1.8,

	--[[ How much faster the crash swoop ages while burning (`Strikes.Swoop`). 2 halves both its hold
		and its release, so a barrier's dive is over in about a second instead of two.

		PLACEMENT ONLY, like the swoop itself, and it is what makes the press read out of the window in
		the first second after a crash, before the settle lets the refill start. The cruisers dive for
		your door, you light the bottle, and they fall short and drift back. Without it that second
		looks the same lit or dry, and it is the exact second the player pressed the button to change. ]]
	SwoopScale = 2,

	--[[ How much faster the lead builds while burning, on top of whatever speed is already earning it
		(`Lead`).

		The speed scale cannot tell nitro from boost on its own: `Lead.Max` caps it at 1.5 and a held
		accelerate already reaches that. At 2 a full lead comes up in a little over two seconds of burn,
		inside one beater's bottle, against four and a third on boost. ]]
	LeadScale = 2,
}

--[[ Seconds of a full bar the chase opens with, and reopens with after a revive.

	The arm is not under the player's control, so the frame it lands on can be any frame: mid-crash,
	mid-course, halfway through a lane change with the brake down. Without this, a chase that armed
	on a bad second would be a bust the player was never given a chance at. It is also what makes a
	revive out of a bust a second wind rather than a re-run of the last two seconds. ]]
PoliceConfig.Grace = 2.5

--[[ === THE ARRIVAL: WHERE THE FIRST TWO SECONDS PUT THEM ====================================

	A chase that opens on the station it is going to hold for the next forty seconds has no opening.
	The sirens start, two cars fade up in the mirror at the distance they will be sitting at when
	nothing is happening, and the most dangerous thing on the road has introduced itself by doing
	nothing. So they come up LEVEL WITH THE DOOR first, hold there for as long as the alert is on
	screen, and only then fall back to whatever the bar is asking for.

	It is one number and two clocks: a ceiling on the station value (`Station`, on the same 0..1..2
	scale as everything else in this file, so 0.3 sits between the arrest station and the ordinary
	one), held for `Hold` and then released over `Release`.

	A CEILING AND NOT A WRITE, which is the whole of why it composes. It can only ever bring them
	NEARER than the bar would, never further away, so a player who crashes during their own arrival
	still gets the closing the crash asked for, and one who does not is handed back to the bar the
	moment the ramp finishes. There is no state to unwind and no way for it to fight anything.

	`Hold` + `Release` are meant to land on `Grace`, above. The arrival finishing and the player
	starting to be marked are the same beat and they should look like it: they pull level, they sit
	there while the alert says what the rule is, and they drop back as the rule starts applying. ]]
PoliceConfig.Entry = {
	--- Off = they come straight onto the bar's station out of `Cruisers.EntryStuds`, which is what
	--- shipped before this.
	Enabled = true,

	--- The station value they arrive on. 0 is the arrest station and 1 the ordinary one, so this is
	--- most of the way in: door to door, a little behind, unmistakably there.
	Station = 0.3,

	--- Seconds they hold it for...
	Hold = 1.0,

	--- ...and seconds to give it back. Eased out rather than dropped, so the release reads as the
	--- police settling into a pursuit rather than as a station change.
	Release = 2.2,
}

--[[ Seconds of grace a landed STEAL buys, on top of whatever the arm above gave.

	THE HANDOFF PUTS YOU UNDER THE FLOOR ON PURPOSE. `StealConfig.Handoff.InheritVelocity` is 1, so
	you come out of a steal doing exactly what the car you took was doing, and traffic runs 24 to 44
	studs/s against a floor of about 50 in the starter car and more in a faster one. EVERY steal in
	the game therefore lands under the floor, in a state the player did not choose and cannot drive
	out of any faster than the throttle allows. Charging bar for that is charging for the mechanic.

	MEASURED ON THE ROAD, so the next person to move this number does not have to find it again:
	knocked down to 27 studs/s the starter car is back over its 49.6 floor in 0.40s, and the drain
	across that window costs about 0.06 of the bar. That is the ORDINARY case and it was never the
	complaint. The complaint is the handoff that arrives STOPPED - wedged on the rail, dropped into
	the getaway truck, shoved by its own landing sweep - which drains at the full rate and, on a bar
	already down to a third, is an arrest inside a second with the player holding full throttle and
	nothing available to them that helps. Reported as "caught by police immediately after switching
	cars".

	2.0 is five times the measured spool. An ordinary handoff clears the floor with 1.6s to spare, a
	handoff that arrives badly gets a real chance to sort itself out, and a player who steals and then
	simply stops is still arrested well inside the chase. It deliberately does NOT stretch to cover
	`DriveConfig.Stuck.After` (2.5s, the un-wedge rescue): a car still going nowhere when this runs
	out is going nowhere for a reason the police are the right answer to, and papering over the wedge
	from here would be the wrong lever on somebody else's bug.

	IT WAIVES THE DRAIN AND NOTHING ELSE, which is the whole of why it is a separate number from
	`Grace` rather than a longer one. The refill still runs the moment the car is back over the floor,
	so a steal taken on an almost empty bar is a genuine way out rather than a stay of execution; and
	a CRASH after the handoff still costs full price, because the crash is priced where the crash
	happens (`Strikes`) and the handoff is not what put you into it.

	THE FLIGHT ITSELF NEEDS NO GRACE and never did. The car is anchored while `StealController` flies
	it, `DriveController.isDriving` reads false, and the bar does not move at all - measured across a
	live bail, frozen for the whole 1.8s arc. This covers the frames AFTER the mount. ]]
PoliceConfig.StealGrace = 3.0

--[[ The `cause` string this ends a run with, as `RaceService.wreckRace` takes it.

	Everything downstream keys off this one word: `ReviveConfig.RevivableCauses` decides whether the
	respawn screen is offered for it, `CarHudController` swaps the banner, `RaceUIController` swaps
	the results headline, `RaceService` skips throwing the rider through the windscreen and
	`ObstacleController` skips the engine plume. A car that has been pulled over is not a car that
	has blown up. ]]
PoliceConfig.Cause = "busted"

--- What the player is told they have been. Kept beside the cause so the word and the reason for the
--- word live together, and read by both places that print it.
PoliceConfig.BustedWord = "BUSTED"

--[[ === THE TELL: ONE CRUISER SETTING THE ARREST UP =========================================

	The PIT below takes 0.55 seconds out of an ordinary station, which means the first the player
	knows about it is the contact. This is the warning, and it is made of POSITION rather than of
	anything on screen: under `From` on the bar the cruiser that is going to do it stops holding
	station, drops onto the back quarter it needs to hit from, and works the gap open and shut while
	it waits for the bar to run out.

	THE OTHER CRUISER GOES ON CLOSING, and that contrast is the whole shot: one car cutting across
	your nose at the `Near` station and one sitting in your blind spot jockeying for an angle. A pair
	that both did the same thing would just be a pair, and a pair that both lined up would leave
	nobody in front of you at the moment the frame is supposed to be at its most crowded.

	IT IS THE SAME CAR THE ARREST USES. Both pick the outside cruiser by the same rule
	(`PoliceController._pitSide`), so the approach starts from where the tell already put it and the
	arrest reads as the end of something rather than as a car teleporting into position. Cross the
	centre line while it is lining up and the OTHER cruiser takes the job over, which is correct and
	looks it: a PIT always comes from the outside so the spin goes toward the middle of the deck. ]]
PoliceConfig.Lineup = {
	--- Off = an arrest arrives with no warning, which is what shipped before this.
	Enabled = true,

	--[[ Bar value the tell starts at, ramping to fully lined up at an empty bar. Above this the
		chosen cruiser is holding an ordinary station and there is nothing to see.

		It wants to be low. This is not a "you are in trouble" signal, which is what the vignette and
		the bar are for; it is the last beat before the arrest, and a tell that started at half a bar
		would spend most of a chase saying something it was not going to follow through on. At 0.32
		it is about one barrier's worth of bar away from the bust. ]]
	From = 0.32,

	--[[ Where it sits while it waits.

		`Behind` is further back than `Pit.Behind` (13), so the arrest's own approach still has
		somewhere to come FROM: a tell that parked the car on the contact point would make the PIT
		itself a sideways twitch. `Side` is just outside touching (half the player's widest ordinary
		body plus half a scaled cruiser is 9.4 - the arithmetic is on `Cruisers.Lateral`), because a
		tell that clipped the player would be a collision the player did not earn. ]]
	Behind = 17,
	Side = 9.8,

	--[[ The jockeying: studs of gap it CLOSES from `Behind` while it waits, and how many times a
		second it does it.

		ALONG THE ROAD RATHER THAN ACROSS IT, and not for looks: across it at this offset is the
		player's door. Along it the car surges up to the quarter and drops back, which is both safe
		and the thing a pursuit driver is actually doing while they wait for the angle.

		IT ONLY EVER CLOSES. `Behind` is the far end of the swing rather than its middle, so the car
		works between 17 and 12.5 studs back and never further away than where it settled. A
		symmetric feint spent half its time dropping the cruiser toward the bottom edge of the frame,
		which is a tell that periodically hides. ]]
	Feint = { Studs = 4.5, Hz = 0.62 },

	--- How fast it takes the lineup station up, blended over BOTH of `Cruisers.Lag`'s axes as the
	--- tell comes on. It is a spring rate like they are, and it is above both of them: the tell is
	--- the one moment in a chase where a cruiser is supposed to look decisive. Rebased from the 4.4
	--- it was under the old exponential ease, which settled in about the time 6.0 does here.
	Lag = 6.0,
}

--[[ === THE PIT: HOW AN ARREST LOOKS ========================================================

	THE BAR REACHING ZERO NO LONGER ENDS THE RUN ON THAT FRAME. A cruiser comes off its station,
	puts its nose into your back quarter, and spins you off the road; the bust is reported when the
	car is already sideways. The old ending was the banner arriving over a car still driving in a
	straight line, which read as the game deciding rather than the police doing something.

	IT IS THE SAME MANOEUVRE THE PLAYER CAN PERFORM ON TRAFFIC, built the same way, and the shared
	construction is the point. `TrafficController._knock` hands a clipped car to physics and puts an
	impulse in AT THE CONTACT POINT, so the lever arm decides the spin and nothing scripts it. This
	does exactly that to the player's own car. Catch the back quarter and it comes round; the shape
	of the spin is the geometry's answer, not a curve in this file.

	THE ONE THING THAT IS DIFFERENT is that the player's car is being steered. `DriveController`
	writes `AssemblyLinearVelocity` and `AssemblyAngularVelocity` EVERY FRAME from the player's
	input, so an impulse landing on it is erased within about a stud of travel (the same wall
	`ObstacleConfig`'s slick hazards ran into, and why they take grip through `applySlick` rather
	than pushing the car around). So the PIT suspends the shim for the length of the spin, which is
	the same lever `StealController` pulls to fly a bailed car. The run is over at that point; there
	is nothing left for the player to steer.

	NOTHING HERE IS SOLID EITHER. The cruiser is still `CanCollide = false` throughout: it is moved
	onto the quarter by the same station composition it has used all chase, and the impulse is
	applied when it ARRIVES rather than when it touches. A collision would be at the mercy of a
	closing speed the chase does not control, and would occasionally miss. ]]
PoliceConfig.Pit = {
	--- Off = an empty bar reports the bust on the frame it empties, which is what shipped before
	--- this. Everything downstream is unchanged either way: the same `Cause`, the same banner, the
	--- same revive offer. This is the second and a half in front of them.
	Enabled = true,

	--[[ Seconds the chosen cruiser takes to come off its station and reach the quarter.

		Short, because the bar is already empty and the player already knows. Much over a second and
		the arrest becomes a thing they watch approaching with the controls still live, which invites
		them to try to drive out of it; at 0.55 it is a car that was beside you and is now into you. ]]
	Approach = 0.55,

	--[[ Where the cruiser sits at the moment of the hit: studs BEHIND the player's car and studs to
		the SIDE, both CENTRE TO CENTRE exactly as `Cruisers.Standoff` and `Cruisers.Lateral` are.

		13 back is the nose on the quarter, not the gap between them. The cruiser's nose is 12 studs
		in front of its own centre at `Cruisers.Scale`, so 13 puts it a stud behind the player's
		centre, which on a 21-stud body is the back door. That is where a PIT goes: any further
		forward and it is a T-bone, any further back and it is a rear-end shunt that pushes rather
		than turns.

		7.5 across is INSIDE the player's bodywork. Half-widths sum to 9.4 (see `Cruisers.Lateral`),
		so this is about two studs of overlap, and the cruiser is not solid so it simply passes in.
		Held at a respectful gap the shot is two cars near each other and a player who spins for no
		visible reason; leaning in is what makes them read as touching from a camera 28 studs back.

		BOTH ARE A MOVE, not a place. At an empty bar the cruiser is already at `Standoff.Near` (-4,
		a nose ahead and cutting in) and `Lateral.Near` (10.2), so the approach drops it BACK and
		leans it IN, which is the setup a real one makes. ]]
	Behind = 13,
	Side = 7.5,

	--[[ Studs per second of impulse, and how far up the car's own long axis the contact is taken.

		`Push` is denominated the way `TrafficConfig.Knock.Push` is: it is multiplied by the car's
		assembly mass at the moment it is applied, so it stays a change in velocity rather than an
		impulse whose effect depends on which body the player happens to be driving. The roster runs
		from a 421-mass Civic to something a good deal heavier and a PIT has to look the same on both.

		`Quarter` is the fraction of the car's half-length BACK from centre the impulse goes in at,
		which is the whole mechanism: at 0 it is a push and the car slides, at 1 it is off the end of
		the bumper and the car pirouettes. 0.8 is a real PIT, which catches the back wheel arch.

		`Lift` is a fraction of `Push` added straight up, the same unstick `Knock.Lift` gives a
		traffic car. Small. This is not a launch, and it is NOT what breaks traction: that is
		`TyreGrip` below, and the note on it is the one to read before touching either.

		MEASURED, at `TyreGrip` 1.3 on a 367-mass car doing 70 studs/s: 26 brings it round to about
		172 degrees in 0.6 s, which is backwards. On stock tyres 19 reaches 34 degrees and 14 reaches
		25, both of which are a car that got shoved rather than a car that got spun. ]]
	Push = 26,
	Quarter = 0.8,
	Lift = 0.12,

	--[[ Seconds the car is left spinning before the bust is reported.

		The report is what ends the run, and the run ending cuts the controls, stops the motors and
		coasts the car to a halt (`ObstacleController._onWrecked`). So this is how much of the spin
		happens while the car still has its own momentum, and it wants to be about a full rotation:
		1.1 seconds at this push lands between one and one and a half turns depending on what was
		caught, which is a car that has been spun rather than a car that has been nudged.

		Do not raise it far. Every tenth here is a tenth the player spends with the run already
		decided and nothing to do, and the wreck beat behind it is not short. ]]
	Spin = 1.1,

	--[[ WHAT THE TYRES ARE WORTH FOR THE LENGTH OF THE SPIN, as an absolute `Friction` and
		`FrictionWeight` written onto the chassis's four `Suspension*.Wheel` parts, or nil to leave
		them alone.

		THE SINGLE MOST IMPORTANT NUMBER IN THIS SECTION, and it is not obvious that it should exist
		at all, so here is what was measured on a live car (mass 367, doing 71 studs/s down the road,
		the impulse above unchanged at every step):

		    stock tyres (2.0 / 3.0)   snaps to 110 degrees in 0.5 s and STOPS DEAD, 71 -> 0
		    1.3 / 1.3                 round to 172 degrees in 0.6 s and HOLDS IT, sliding, 70 -> 26
		    0.9 / 0.9                 keeps turning: 333 degrees in 1.5 s, still moving at 15
		    0.6 / 0.6                 a full donut and out the far side, 360+ degrees, 75 -> 49
		    0.25 / 0.25               spins two and a half times in 1.6 s and never stops, 71 -> 53

		The stock row is the problem. This chassis has enormous lateral grip, so a car yawed past
		about twenty five degrees scrubs its entire speed off in half a second: 71 studs/s to a
		standstill is nearly five g, and it reads as the car hitting an invisible wall rather than
		as the car being spun. No value of `Push` avoids it, because the harder the impulse the more
		broadside the car gets and the harder it digs in. Push and grip are not two dials for the
		same thing: `Push` decides how hard it is hit, and this decides what the road does about it.

		The bottom rows are the other failure and it is the ice rink: with too little to scrub
		against the car keeps every bit of the spin, goes all the way round and drives out the far
		side still pointing forwards. A PIT that the player emerges from facing the right way is a
		stunt, not an arrest.

		1.3 is a car that has been spun: round to backwards in a little over half a second, HELD
		there rather than carrying on, and sliding down the road losing speed the whole time. Which
		is also the last thing the player sees, because the bust lands while it is still sliding
		(`Spin`).

		THE NUMBER IS SPEED-SENSITIVE, so retune it against a car at cruise and not against a slow
		one. Every row above was taken at 70 to 75 studs/s; the same grip at half that speed turns
		further, because there is less lateral load to scrub against.

		THEY ARE PUT BACK BY `_endPit`, WHICH IS THE PART TO BE CAREFUL WITH, and not by the bust
		report: re-gripping a car that is sideways at 30 studs/s stops it on that frame, so the
		tyres stay slippery through the wreck beat and `ObstacleController`'s coast brings it to
		rest instead. What that costs is one more thing a revive has to undo, which is why every
		exit from the arrest goes through one function. ]]
	TyreGrip = { Friction = 1.3, Weight = 1.3 },

	--- Camera shake at the moment of contact, on `ObstacleController`'s own scale, where the harshest
	--- obstacle in the game is 1.6 and a wreck is 2. A PIT sits between them: it is the last thing
	--- that happens to this car under its own power.
	Shake = 1.8,

	--[[ Which side the cruiser comes in on, or nil to let the road decide.

		nil is the shipped answer and it is doing real work: it picks the cruiser on the side AWAY
		from the road edge, so the spin goes toward the middle of the deck rather than off it. A PIT
		that regularly put the player over the edge would turn an arrest into a fall, which is a
		different wreck with a different cause. Set to 1 or -1 to force it for a photograph. ]]
	FromSide = nil,
}

-- === The cruisers ===========================================================

--[[ THE TWO ON THE ROAD.

	They ride the road frame the way a traffic car does: an `along` coordinate and a `cross` offset,
	composed into a world CFrame every frame. Unlike traffic they are not a population and they do
	not drive themselves anywhere. They hold station on the player, and the station is what moves.

	=== WHY THEY ARE BESIDE YOU AND NOT BEHIND YOU ==========================================

	Because the camera is behind you. `CameraConfig` puts it 28 studs back and 13 up, so a cruiser
	directly astern is either inside your car or behind the lens. Two numbers settle it: a police
	car at this scale is 21 studs long and the player's car is 21 studs long, so bumper to bumper is
	already 21 studs of separation, which is 7 studs in front of a camera looking 17 degrees DOWN.
	It is off the bottom of the frame at the exact moment it is supposed to be most frightening.

	A rear quarter works and is the shot anyway. A cruiser one car's width out and a few studs back
	sits in the lower corner of the frame, gets bigger as it closes, and finishes level with the
	door. That is a police chase; a pair of headlights nobody can see is a HUD element. ]]
PoliceConfig.Cruisers = {
	--- How many. One per side, alternating, so an odd count puts the extra one on the left. Two is
	--- the shot above; three is the same shot with one of them buried behind another.
	Count = 2,

	--[[ Uniform scale applied to the published model.

		Measured: the shipped mesh is 26.74 long, 10.50 wide and 9.49 tall against a Tier 1 Civic's
		21.26 x 9.36 x 6.43. At 0.9 the cruiser comes out 24.1 x 9.5 x 8.5, which is about three
		studs longer than the player's car and a head taller: an interceptor beside a hatchback,
		which is the read the beat wants.

		IT WAS 0.8, AND 0.8 WAS A CAR LENGTH WITH THE PLAYER'S. That was correct as arithmetic and
		wrong on screen. A cruiser riding the rear quarter is seen edge-on, half of it behind the
		player's own bodywork, so matching the player's dimensions makes it read as SMALLER than the
		car it is chasing; the thing that is supposed to be closing in looks like traffic. A tenth of
		scale is barely a change in the numbers and is the whole difference in the shot.

		DO NOT GO MUCH PAST THIS WITHOUT MOVING `Lateral.Near` WITH IT. The two are tied: `Near` is
		half the player's widest ordinary body plus half of a scaled cruiser, so a wider cruiser at
		the same offset puts its flank inside the player's car at the closed-up end of the bar. The
		note on `Lateral` carries the arithmetic. ]]
	Scale = 0.9,

	--[[ Half the WIDTH of a cruiser at that scale, which is the margin `PoliceController._placeCar`
		keeps between one of them and the edge of the deck.

		The unscaled mesh measures 10.50 across (the same raycast pass `Bar` further down came out
		of), so this is 10.50 / 2 * `Scale` and it MOVES WITH `Scale` exactly as `Lateral.Near` does.
		It is stated rather than measured off the model at runtime because a `MeshPart.Size` is a box
		that can be much bigger than the geometry inside it, which is the whole reason every number
		in this section was raycast in the first place. ]]
	EdgeMargin = 4.73,

	--[[ Degrees of yaw that turn the model's own nose onto the -Z that `CFrame.lookAt` aims.

		ART KNOWLEDGE, MEASURED RATHER THAN ASSUMED. The cruiser's mesh has its nose along its
		part's local +X (established by rendering it head on from both ends and looking at which
		one has the tail lights), which is a quarter turn away from -Z. A model re-exported facing
		a different way is fixed by re-taking that render and changing this number, and nothing
		else in the feature has to know. ]]
	NoseYawDeg = 90,

	--[[ How far behind its opening station a cruiser starts, in studs.

		It is the arrival: the station spring takes it from here to where it belongs, so a chase
		begins with two cars closing out of the fog rather than two cars appearing. 150 at `Lag.Along`
		3.4 is about a second and a half of approach, which is about how long the HUD's alert is up
		for. Those two are meant to finish together.

		A SPRING IS THE RIGHT CURVE FOR THIS ONE TOO, and it was worth the change on its own: the
		cars now come out of the fog accelerating from the player's own speed instead of arriving
		with their fastest frame first. ]]
	EntryStuds = 150,

	--[[ Studs BEHIND the player's car, at a full bar and at an empty one. Negative is in front.

		THREE ANCHORS ON ONE SCALE, and `PoliceConfig.station` is the only thing that reads them:
		`Near` at an empty bar, `Far` at a full one, `Lead` at a full one you are pulling away from
		(`PoliceConfig.Lead`).

		Near (-4) has the cruiser a nose ahead of you, cutting in, and it has not moved: that end of
		the scale is the crash landing and it should be as close as it ever was.

		FAR IS WHAT MOVED, 11 to 14, AND THE POINT OF IT IS THE RANGE BETWEEN THE TWO. At 11 the
		cruiser sat 17 studs in front of the lens and spanned most of the frame, at every moment of
		every chase, whether anything was happening or not; the beat had no quiet half to make its
		loud half mean anything. At 14 it is 14 studs in front of the lens and around 50 degrees off
		axis, which is the frame edge: present in the corner of your eye, and not sitting on you.
		A crash still takes it all the way to `Near`, and now that is a journey you can watch.

		LEAD IS ONLY THREE STUDS FURTHER BACK THAN FAR, AND THAT IS THE WHOLE FINDING OF THIS PASS.
		A CAR THAT DROPS BACK GETS BIGGER. The camera is BEHIND the player (`CameraConfig`: 28 back,
		13 up, 17 degrees down), so distance down the road from the player is distance TOWARD the
		lens: a cruiser at `Far` is 23 studs from the camera and one nineteen studs back is 12, which
		is twice the size on screen. Photographed side by side, the falling-back station was the more
		threatening of the two. The obvious way to say "they are losing you" says the opposite.

		    station 1.0, 11 back, 14 out    23 studs from the lens, 28% and 69% across the frame
		    station 2.0, 19 back, 16 out    12 studs from the lens, and enormous in the corner
		    station 2.0, 14 back, 22 out    22 studs from the lens: the same size, at the edges

		So the lead is spent almost entirely ACROSS the road (`Lateral` below) and barely at all along
		it. The three studs that are here are what keeps the motion diagonal rather than a pure slide
		sideways, which would read as a lane change. What the player actually sees is the cruisers
		leaving the middle of the frame for its edges at a constant size, and the road ahead opening
		up - and the HELICOPTER doing the shrinking, because it is the one pursuer in front of the
		lens and the only one that can (`Helicopter.Ahead`).

		DO NOT PUT THE LEAD BACK INTO THIS PAIR, and be careful pushing `Far` much past this either.
		The camera is 28 studs back, so a cruiser at 17 is already inside 11 studs of the lens, and
		every stud of "falling back" buys a stud of looking closer right up until it passes behind
		the camera altogether. What saves both numbers here is `Lateral`: they are far enough OUT
		that they leave the frame sideways before they get close enough to loom. Move one of the
		pair without the other and that stops being true. ]]
	Standoff = { Far = 14, Near = -4, Lead = 17 },

	--[[ ...and studs to the side, same three ends.

		Near (10.2) is the closest two cars of these widths can be without overlapping: half of the
		player's widest ordinary body (9.36 / 2) plus half of a cruiser scaled to 0.9 (9.45 / 2) is
		9.4, and the rest is daylight. It moved with `Scale` and it has to keep moving with it.

		FAR (17) IS A LANE AND A BIT OVER, and it is the other half of the hang-back `Standoff` just
		described. The two are one move: 14 back and 17 out puts a resting cruiser right on the edge
		of a 70 degree frame, so an ordinary second of a chase is a light bar in your peripheral
		vision rather than a car filling a third of the screen. It was 14, which is just inside one
		lane over, and one lane over is where a car sits when it is ALREADY on you.

		LEAD (23) IS WHERE THE WHOLE OF "THEY ARE LOSING YOU" IS SPENT, for the reason `Standoff`
		spells out at length: sideways is the only direction a pursuer can leave in without getting
		bigger. It is most of a lane further out again than the new `Far`, which takes a cruiser from
		the edge of the frame to outside it: on screen they slide out of the corners and the road
		opens up between them.

		IT IS CLAMPED TO THE DECK AT PLACEMENT TIME (`PoliceController._placeCar`), and it has to be:
		this is an offset from the PLAYER, so a player hugging the outer lane at 30 would otherwise
		put the outside cruiser at 52 on a deck that is 73 wide. The clamp is not new behaviour for
		the sake of this number - `Far` had the same hole - but this is the number that made it worth
		closing, because it is the one that reaches the edge on its own. ]]
	Lateral = { Far = 17, Near = 10.2, Lead = 23 },

	--[[ LOSING YOU MEANS GONE: once the caption says it (`Hud.Bar.LeadFrom`), the cruisers brake
		and drop out of the bottom of the frame, past the lens, instead of only sliding wide.

		Dylan asked for it after the wide-only lead (2026-10-01): at 17 back and 23 out a cruiser was
		still in the corner of the shot, so the caption and the window disagreed. The looming the
		`Standoff` note warns about is real but brief here, because by `LeadFrom` the pair is already
		most of the way out to `Lateral.Lead` and a car that wide leaves the frame at the bottom
		corner as it drops, rather than filling it.

		`Studs` is ON TOP of `Standoff.Lead`. The camera sits 28 back plus up to 8 of speed pullback
		(`CameraConfig.SpeedPullbackStuds`), and a cruiser is about 19 long, so 17 + 40 = 57 puts its
		nose well behind the lens at any speed. `Span` is how much more lead (0..1) past `LeadFrom`
		it takes to get all the way back, smoothstepped; the gap spring (`Lag.Along`) rounds it off.

		A strike zeroes the lead, so a crash brings them in from behind the camera, out of the bottom
		corners, which is the "they are back" read. `_lose` keeps whatever gap they already have, so
		a chase that ends with them gone does not pull them forward into shot to wave goodbye.

		Set to nil to go back to the wide-only lead. ]]
	Shaken = { Studs = 40, Span = 0.25 },

	--[[ The wander on top of that station, so two cruisers holding identical offsets do not read as
		one object mirrored. Studs of cross-axis sway and how many times a second it cycles; each
		car gets its own phase. Small, because this is life and not driving. ]]
	Weave = { Studs = 2.4, Hz = 0.29 },

	--- ...and a matching bob along the road, so they are not welded to a fixed gap either.
	Surge = { Studs = 3.2, Hz = 0.19 },

	--[[ How fast a cruiser takes up a station that has moved. TWO RATES, ONE PER AXIS, and they are
		the rate of a CRITICALLY DAMPED SPRING rather than of an exponential ease.

		THAT DISTINCTION IS THE WHOLE OF WHY A CRASH NO LONGER READS AS A PIVOT, and it is the one
		thing to understand before retuning either number. Both curves start apart and finish
		together and look identical plotted as position. Plotted as SPEED they are opposites:

		    an exponential ease   fastest on frame one, slowing all the way in
		    a critical spring     stopped on frame one, accelerating, then settling

		A station steps when the player crashes (the bar drops in one frame, the lead is spent in one
		frame, the swoop arms in one frame), and under an ease that step handed the car its top
		closing speed instantly. Two things came out of that and both were the complaint. The car
		APPEARED to close rather than closing, and because the heading is composed out of the car's
		own cross rate (`PoliceController._placeCar` aims each cruiser at where it is going, not down
		the road) the nose swung over on the same frame and swung back a second later: a pivot, from
		a car that never turned a wheel. Under a spring the cross rate ramps up from nothing, so the
		nose comes round as the car comes round, which is the same thing a driver looks like.

		THEY ARE NOT THE OLD NUMBER AND THEY ARE NOT MEANT TO BE. A spring settles in about 4.7/rate
		seconds against an ease's 3/rate, so matching the old 3.2 for total trip time would take
		about 5. `Across` is that, near enough: lane following is the target that moves CONSTANTLY
		rather than in steps, it was correct before, and nothing about it wanted to be slower.
		`Along` is deliberately under it, because closing the gap is the axis the player is being
		asked to watch and 3.4 is about a second and a third of visible approach.

		Slower than the bar moves, on both axes, deliberately. The bar can jump on one bad frame and
		a car that teleported with it would read as a rendering fault. ]]
	Lag = { Along = 3.4, Across = 5.0 },

	--[[ THE LIGHT BAR, in the UNSCALED mesh's own local frame, nose at +X.

		Measured by raycast: the bar occupies local x -2.0..-0.75 and z -3.5..+3.5, standing 1.1
		studs off a roof at y 3.66, with its top at 4.75. The mesh paints it red on the -Z half and
		blue on the +Z half (verified with probe parts, viewed from the nose), so the two lamps are
		coloured to match rather than chosen: a blue lamp glowing over red paintwork reads as a bug
		in the art.

		The lamps are built slightly PROUD of the bar on every axis. A neon block flush inside a
		solid mesh is a neon block you cannot see, and 0.1 studs of overhang is invisible at any
		distance this is looked at from. ]]
	Bar = {
		--- Centre of each lamp in the mesh's local frame, and the size of one. `Z` is the magnitude;
		--- the red lamp takes the negative side and the blue one the positive.
		X = -1.375,
		Y = 4.42,
		Z = 2.35,
		Size = Vector3.new(1.45, 1.05, 2.5),
		Red = Color3.fromRGB(255, 40, 40),
		Blue = Color3.fromRGB(50, 90, 255),
		--- What an unlit lamp fades to. Not black: an unlit bar lamp on a real car is still a
		--- coloured lens, and going to black makes the bar flicker between two shapes instead of
		--- two brightnesses.
		OffTransparency = 0.55,
	},

	--[[ THE FLASH. Seconds one side stays lit before the other takes over.

		A real light bar runs far faster than this. 0.16 is slow enough to survive being watched at
		30fps on a phone and fast enough to read as an emergency light rather than an indicator, and
		it is the one number here to look at if the chase reads as sleepy.

		Every cruiser flashes on the SAME clock and out of phase with each other by half a period,
		so two of them together alternate rather than blinking in unison. Unison reads as one light
		source; alternation reads as two cars. ]]
	FlashTime = 0.16,

	--[[ The lamp's own spill light: a touch of colour thrown onto the road and onto the side of the
		player's car, and nothing more than that.

		SMALLER AND DIMMER THAN THE FIRST GUESS BY A LONG WAY, and this is the number to be careful
		with. Range 26 at brightness 3.2 was the opening pass and it tinted the ENTIRE VISIBLE ROAD
		red and then blue, twice a second, from four lights: the road is a flat deck seen almost
		edge on, so a light a few studs above it rakes an enormous area of what is on screen. It
		read as a full-screen colour filter rather than as two cars with their lights on, and it was
		the single worst thing in the first playtest photograph.

		At 16 and 0.9 the wash reaches about a car's length around each cruiser, which is the pool a
		light bar actually makes, and the flashing reads on the CARS. Turn it up only against a
		photograph, never against a description.

		Set `Enabled = false` to keep the neon and drop the lights, which is the first thing to try
		if a chase costs frames on low-end devices: these are the only dynamic lights anything in a
		race adds. ]]
	Light = { Enabled = true, Range = 16, Brightness = 0.9 },
}

-- === The helicopter =========================================================

--[[ THE ONE OVERHEAD, and it flies AHEAD of you rather than behind.

	Same reason the cruisers ride your quarters, applied to the other axis. The chase camera looks
	17 degrees DOWN with a 70 degree vertical field, so the top of the frame is about 18 degrees
	above the camera's own horizontal: anything directly overhead is out of shot, and a helicopter
	nobody can see is an expensive sound effect. Held ahead and above, it sits in the upper third of
	the frame with the road running underneath it, which is the shot the beat is for and also the
	one a player recognises. It descends and closes as the bar drains.

	It is not an obstacle and cannot be flown into: like the cruisers it is `CanCollide = false`
	throughout, and its heights below clear the tallest obstacle volume (8.4 studs) and the road's
	overhead cables (measured at 44 to 52 studs above the deck on every City tile) with room either
	side. ]]
PoliceConfig.Helicopter = {
	--- One is the right number and this is a switch, not a count: a second helicopter has nowhere
	--- to be that the first one is not.
	Enabled = true,
	Scale = 1,

	--- Degrees of yaw onto `CFrame.lookAt`'s -Z, as the cruiser's `NoseYawDeg`. The helicopter mesh
	--- already faces -Z (rendered head on to check), so it needs none.
	NoseYawDeg = 0,

	--- How far ahead of its opening station it starts, and how much higher, in studs. It flies IN
	--- from in front and above rather than up from behind, because in front and above is where it
	--- is going to be: entering from the other side would have it overtake the player backwards.
	EntryStuds = 190,
	EntryRise = 55,

	--[[ Studs AHEAD of the player's car and studs above the deck, at the three ends of the one scale
		everything in this file is placed against: an empty bar, a full one, and a full one you are
		pulling away from (`PoliceConfig.Lead`).

		SIZED BY PHOTOGRAPH, not by arithmetic. The first pass held it at 74 studs and 38 up, which
		put it 98 studs from the camera and 14 per cent of the way down the frame: correctly placed,
		clearly a helicopter, and far too small to be menacing. Pulled in to 56 and 31 it sits about
		a third of the way down with the road running under it, which is the shot.

		THE AIRCRAFT IS THE ONE PURSUER THAT CAN ACTUALLY SHRINK, and that is why it earns a `Lead`
		end of its own. It flies IN FRONT of the camera rather than behind it, so distance from the
		player is distance from the lens: at 74 and 40 it is 90 studs out and near the top of the
		frame, plainly smaller and plainly higher than it was. The cruisers can only slide out of the
		corners; this one visibly climbs away, and between them the player gets the same sentence
		twice in two different words.

		Every height here stays under the City's overhead cables, measured at 44 to 52 studs above
		the deck on every tile, and well over the tallest obstacle volume (8.4). The near end is
		deliberately not closer than this: at 36 studs the aircraft's tail is already only about
		seven studs in front of the player's bumper, and any nearer reads as something they are
		about to hit even though nothing here can be hit. ]]
	Ahead = { Far = 56, Near = 36, Lead = 74 },
	Height = { Far = 31, Near = 22, Lead = 40 },

	--- The slow side-to-side drift, so it reads as a machine holding position in air rather than a
	--- sprite pinned to the car. Studs either side of the player's own cross position, and cycles
	--- per second.
	Drift = { Studs = 17, Hz = 0.105 },
	--- ...and the bob, which is the same idea on the vertical.
	Bob = { Studs = 3.4, Hz = 0.16 },

	--[[ How far it rolls INTO the drift, in degrees at full lateral speed. A helicopter banks to
		move sideways, and one that slides flat is the single thing that makes a flying model read
		as a prop being dragged. Derived from the drift's own rate rather than tracked, so it is
		always correct for whatever the drift is retuned to. ]]
	BankDeg = 15,

	--- ...and how much it noses down, degrees, at the near end of the chase. It is diving at you.
	PitchDeg = 7,

	--- An exponential ease toward the station, and slower than either of the cruisers': an aircraft
	--- has more mass to it. Deliberately NOT the critically damped spring `Cruisers.Lag` is now. The
	--- spring is there to stop a step in the station reading as a car being teleported sideways, and
	--- the helicopter is a hundred studs out in front of the lens where no step in the station is
	--- readable as anything at all. What it would buy here is lag, and only lag.
	Lag = 1.8,

	--[[ THE MAIN ROTOR, and why there is a disc at all.

		The helicopter is one MeshPart, so its rotor is modelled into the same geometry as its
		fuselage and cannot turn. A static rotor on a hovering aircraft is the first thing anyone
		notices. So a thin, mostly transparent disc is spun on top of the modelled blades at the
		hub, which is how a rotor reads at speed anyway: the blades supply the shape and the disc
		supplies the blur.

		Measured by raycast in the unscaled mesh's local frame (nose at -Z): the blades reach the
		full half-width of the model, 8.5 studs, and the hub sits at y 5.15 about 9 studs back from
		the nose end of the cabin. ]]
	Rotor = {
		Offset = Vector3.new(0, 5.15, -9),
		Radius = 8.5,
		Thickness = 0.2,
		--- Radians per second. Fast enough to be a blur, and deliberately not a multiple of any
		--- likely frame rate: a disc that lands on the same angle every frame stands still.
		Speed = 27.3,
		Color = Color3.fromRGB(28, 30, 36),
		Transparency = 0.82,
	},

	--[[ THE SEARCHLIGHT, aimed down the belly at the player's car.

		A `SpotLight` rather than a beam or a cone of parts, because the only thing that reads at
		this distance in daylight is the pool it throws on the road, and a mesh cone in bright sun
		reads as a solid object hanging off the aircraft. `Angle` is the full cone; `Range` has to
		reach the deck from the far height above plus the along-road gap, which is about 84 studs at
		the far end, so it is set past that and the falloff does the rest.

		KEPT DIM ON PURPOSE, for the reason `Cruisers.Light` gives at length: this game is played on
		a flat deck under a bright sky, and a light aimed down at that deck rakes a huge share of
		what is on screen. A searchlight bright enough to be obvious in daylight is a searchlight
		that has washed the road out. What this is for is a soft pool that follows the player's car,
		noticed rather than seen.

		Off is a legitimate setting and costs nothing but atmosphere. ]]
	Search = { Enabled = true, Angle = 42, Range = 90, Brightness = 1.1, Color = Color3.fromRGB(255, 250, 224) },

	--- The belly beacon, flashing on the cruisers' clock so the whole chase blinks together. Dim for
	--- the same reason, and dimmer still because it is much higher up and therefore rakes more road.
	Beacon = { Enabled = true, Offset = Vector3.new(0, -5.4, -9), Size = 1.6, Range = 12, Brightness = 0.8 },
}

-- === Sound ==================================================================

--[[ THE SIREN LIVES IN THE PLACE, NOT IN SOURCE, exactly as every other sound in this game does.

	`SoundService` is not Rojo synced, so the group below is authored in Studio with its `Sound`
	child created and its `SoundId` left blank, waiting for an id to be pasted in. A blank id is not
	an error: the group is found, the sound is cloned onto the cruiser, and Roblox plays silence.
	Wiring works today and becomes audible the moment an id lands, with no code change.
	`SoundController`'s header is where this convention is written down.

	It is cloned per cruiser and parented to that cruiser's root, so it is POSITIONAL: two cars in
	different places sound like two cars in different places, and the siren pans as one draws level
	with you. That is most of what sells the beat. ]]
PoliceConfig.Sound = {
	GroupName = "PoliceSiren",
	Volume = 0.55,
	RollOffMin = 24,
	RollOffMax = 260,
}

-- === The HUD ================================================================

--[[ WHAT THE PLAYER IS TOLD, and the short answer is: as little as the beat can survive.

	The cruisers are the gauge (note 1). What the screen adds is the two things a mirror cannot
	give you: the news that a chase has started, and a legible reading of how close to caught you
	are on the frames where the cruisers are behind your own car.

	Every number here is layout. The behaviour is `PoliceHudController`. ]]
PoliceConfig.Hud = {
	--- Off = no overlay at all, and the chase is entirely something you see out of the window. Worth
	--- trying once: it is a better beat than it sounds, and it is how the tuning was checked.
	Enabled = true,

	--[[ THE ALERT ------------------------------------------------------------------------------

		A word across the middle of the screen on the arm, and again when the chase is survived. It
		is the one moment this layer is allowed to be loud, because it is the one moment the player
		has to change what they are doing. ]]
	Alert = {
		--[[ === WHERE THERE IS ROOM ON THE RACE SCREEN, MEASURED ============================

			Every band of the driving screen is spoken for, so both of the numbers below come off a
			dump of every visible HUD box during a live race rather than out of anybody's head.
			These are fractions of the screen, top to bottom, as they are actually SEEN:

			    0.02..0.09    Roblox's own topbar, the music and settings buttons  (x 0.00..0.25)
			    0.09..0.12    the near-miss flow streak bar                        (x 0.39..0.61)
			    0.14..0.17    the speed trap warning                               (x 0.37..0.63)
			    0.18..0.22    THE CHASE BAR and its caption                        (x 0.39..0.61)
			    0.19..0.28    the near-miss toast                                  (x 0.36..0.64)
			    0.26..0.36    the speed trap result                                (x 0.33..0.67)
			    0.35..0.45    the getaway countdown card                           (x 0.80..0.98)
			    0.39..0.45    the WRECKED banner                                   (x 0.10..0.90)
			    0.44..0.63    THE PLAYER'S OWN CAR
			    0.74..0.96    the speedometer cluster                              (x 0.39..0.61)
			    0.79..0.93    the nitro column, standing beside the dial           (x 0.62..0.65)
			    0.51..0.72    the Jump and Nitro buttons, TOUCH ONLY               (x 0.73..0.94)
			    0.68..0.96    the pedals and the steering arrows, TOUCH ONLY, both edges

			TWO ROWS THE FIRST SURVEY HAD AND THIS ONE DOES NOT, both of which were load-bearing here.
			The car's HP is no longer a pill in the top strip: it is a billboard over the roof of the car
			(`CarHudController`, which hides `CarHud.HPBar` and `CarHud.Health` on the PlayerGui copy), and
			that is what freed the band this bar sits in. And the horizontal nitro bar under the car is not
			drawn either: `NitroConfig.Layout` is "Vertical", so the nitro is the column beside the dial.
			The rows above come off the configs that draw each of these plus one photograph of a live
			chase, which is why they are fractions of the screen rather than of anybody's viewport.

			READ THAT LIST BEFORE MOVING ANYTHING, and take the numbers from here rather than from a
			fresh `AbsolutePosition` dump unless you also apply the correction below. Two bands in
			particular do not look occupied and are: the middle of the screen is the CAR, and there
			is nothing under the speedometer because it runs to within a fortieth of the bottom edge.
			Both of those cost a photograph to find out.

			THE CORRECTION. `AbsolutePosition` is NOT screen pixels: it is reported relative to the
			Roblox top bar's inset, which is 58px in Studio, so every box reads 58px HIGHER than it
			draws. The list above already has that added back (0.094 of a 620px viewport). A layout
			checked against a raw dump lands a tenth of a screen too high, which is exactly how the
			first version of this bar ended up drawn across the face of the speedometer twice.

			=== AND WHERE EACH OF THESE TWO GOES ===============================================

			The alert is loud and lives for two seconds, so it takes the middle: 0.36 to 0.44, over
			the car, which is the right place for the one message on this screen that has to
			interrupt. It clears the getaway card horizontally without being told to, because
			`TextScaled` fills a box's HEIGHT and one short word at this size is about 0.15 of the
			screen wide whatever its box says. ]]
		--- 2026-10-19: WAS 0.4, over the car. Now the STOLEN! toast's spot (0.24), nudged down to clear
		--- the chase bar that comes up with it (caption+bar end at ~0.224): the alert takes over the toast.
		CentreY = 0.265,
		--- 2026-10-19: WAS 0.085, and the word covered the road ahead ("too big when it starts, I can
		--- barely see in front of me"). About 40% smaller: still the loudest thing on screen.
		Height = 0.05,
		ArmText = "POLICE",
		--- BOTH HALVES OF THE RULE IN ONE LINE, and it has to be both: a player told only about their
		--- speed learns the wrong lesson from the crash that busts them. Short enough to read in the
		--- two seconds it is up, which is the constraint that keeps it from being a sentence.
		ArmSubText = "DON'T CRASH, DON'T STOP",
		--[[ ...and what that second line says when the chase was CALLED IN rather than driven into
			(`StealHeat`). It costs the player the rule for that one arm and buys the thing the rule
			cannot say, which is that this is happening because of the car they just took. Any
			second chase in the run prints the rule.

			Kept SHORTER than the line above on purpose: `TextScaled` fills a box's height, and it
			answers a line too long for the width by wrapping it rather than by shrinking it. ]]
		--- 2026-10-19: a steal's banner has its own headline too, "POLICE ALERT / VEHICLE REPORTED STOLEN".
		StealText = "POLICE ALERT",
		StealSubText = "VEHICLE REPORTED STOLEN",
		LostText = "LOST THEM",
		LostSubText = "",
		--- Seconds the alert holds at full before it goes. The arm's is longer because it carries a
		--- line of instruction under it that has to be read.
		ArmHold = 2.1,
		LostHold = 1.5,
		FadeTime = 0.4,
		--- It springs in off a `UIScale`, the same construction the WRECKED banner uses, so the two
		--- announcements in this game move alike.
		PopFrom = 0.78,
		PopTime = 0.34,
		ArmColor = Color3.fromRGB(255, 76, 76),
		LostColor = Color3.fromRGB(126, 217, 87),
		SubColor = Color3.fromRGB(226, 232, 245),
	},

	--[[ THE BAR --------------------------------------------------------------------------------

		Top centre, under the speed trap warning and above the horizon, which is the one strip a
		gauge can hold without standing in the road. It is only on screen while a chase is live, and
		it only turns red when there is something to be red about, so a clean chase is a bar the
		player barely registers.

		Same pill-with-a-stroke-and-no-track-art construction as the getaway card's bar, the nitro
		bar and the car's HP bar. Four bars in this game, one construction. ]]
	Bar = {
		--[[ IN THE STRIP UNDER THE SPEED TRAP WARNING, which is the highest a persistent gauge can
			sit on this screen. It took three photographs and two moves to establish that, and every
			rejected answer is worth recording because all of them look right in the table above:

			  • 0.885, under the speedometer. There is nothing under the speedometer. The dial runs
			    to 0.96, a fortieth of a screen off the bottom edge, and what looked like clear space
			    was the inset correction the table's note describes.
			  • 0.545, above the nitro bar. The middle of a driving screen is THE CAR, and this drew
			    a bar straight across the roof of the thing the player is steering.
			  • 0.30, and then 0.28. Both legal, both in the way, and photographed twice before that
			    was believed: it is the HORIZON. The road the player is reading runs out at about 0.23,
			    which is where the traffic and the props they are about to hit first appear, and a gauge
			    parked on that line is in the middle of the shot whatever a layout table says.

			0.215 puts the caption's top at 0.18, a hundredth of a screen under the speed trap warning,
			and leaves the road clear from the horizon all the way down to the car.

			IT IS AS HIGH AS THIS CLUSTER GOES while it stays one thing. The caption rides ABOVE the
			bar, so the pair's top is `CentreY` less half the bar, less `LabelGap`, less `LabelHeight`,
			and the next band up is the speed trap's. The only band above THAT is 0.02..0.09, over the
			flow streak bar, where the centre column is clear on a desktop and is Roblox's own topbar on
			a phone. That is a decision about the whole screen rather than a nudge, so it is not taken
			here.

			WHAT IT STILL SHARES A BAND WITH is the near-miss toast, 0.19..0.28 and centred, which is up
			for about a second at a time and overlapped the two older positions just as squarely. If that
			ever reads badly, move the TOAST, which is transient, rather than the gauge, which is not. ]]
		CentreY = 0.215,
		Size = Vector2.new(0.22, 0.017),
		CornerRadius = 0.5, -- a fraction of the bar's SHORTER side, so 0.5 is a full pill at any viewport
		StrokeColor = Color3.fromRGB(12, 18, 34),
		StrokeThickness = 2,
		--- The fill is the bar, drained right to left. Green while there is room and red once there
		--- is not, crossing over at `Warn`; the colour is the alarm, so the bar itself does not have
		--- to flash while everything is fine.
		SafeColor = Color3.fromRGB(126, 217, 87),
		WarnColor = Color3.fromRGB(255, 76, 76),
		Warn = 0.55,
		TroughDarken = 0.32, -- the trough is the fill dimmed, so the two cannot disagree about hue
		Label = "CATCHING UP",

		--[[ ...and what the caption says once the player is actually pulling away, with the lead it
			swaps at (`PoliceConfig.Lead`, 0..1).

			THE ONE THING THE BAR CANNOT SAY ON ITS OWN. It stops at full, so the difference between
			holding them off and losing them is invisible to a gauge and visible only out of the
			window, where the cruisers are sliding out to the edges of the frame. Two words put the
			same sentence where the player is already looking.

			`LeadFrom` is deliberately not near zero. The lead flickers on and off at the bottom of
			its range every time the player lifts for a corner, and a caption that changed with it
			would be a strobe; a third of the way in, it swaps once, on the way to somewhere.

			Set `LeadLabel = nil` to have the caption never change, which is what shipped before the
			lead existed. ]]
		LeadLabel = "LOSING YOU",
		LeadFrom = 0.35,
		--- The caption above the bar, and the gap between the two. The pair has to fit in the strip
		--- between the speed trap warning's bottom edge (0.17) and the bar itself, which is why both
		--- are small: 0.215 minus half the bar minus the gap minus the height lands the caption's top
		--- at 0.18, a hundredth of a screen clear of it. Growing either one pushes into it.
		LabelHeight = 0.019,
		LabelGap = 0.008,
		LabelColor = Color3.fromRGB(226, 232, 245),
		--- Seconds the bar takes to fade in and out at the ends of a chase.
		FadeTime = 0.3,

		--[[ THE STRIKE FLASH. What a crash does to the bar on the frame it lands.

			The bite is instant and the bar is small, so without this the most important event in the
			beat is a pill getting shorter by a fifth of an inch under a speedometer nobody is looking
			away from. `Scale` is how much bigger the whole bar swells for a moment and `Time` is how
			long it takes to come back down; `Colour` is what the fill flashes to on the way.

			It is a PUNCH, not an animation: the swell is applied on the frame of the hit and decays,
			so it is over before the player has finished reacting to the crash itself. Anything longer
			competes with the thing it is reporting. ]]
		StrikeFlash = { Scale = 0.35, Time = 0.28, Colour = Color3.fromRGB(255, 255, 255) },
	},

	--[[ THE VIGNETTE ---------------------------------------------------------------------------

		Red and blue washing the edges of the screen in time with the light bars. It is the same
		flash, drawn where the player is definitely looking.

		IT IS TIED TO THE BAR AND NOT TO THE CHASE. At a full bar it is not drawn at all, and it
		comes up as the bar falls, so a player who is holding their speed gets a clean screen and a
		player who is losing one gets the lights closing in. A vignette that ran for the whole chase
		would be forty seconds of flashing over the thing the player is trying to see through, which
		is the fastest way to make a good beat unbearable.

		`Max` is the peak alpha at an empty bar. Keep it low. This is edge tint, not a filter. ]]
	Vignette = {
		Enabled = true,
		Max = 0.42,
		--- Where the tint starts appearing, as a bar value. Above this the screen is untouched.
		From = 0.7,
		Red = Color3.fromRGB(255, 30, 30),
		Blue = Color3.fromRGB(40, 90, 255),
		--- Fraction of the screen's short side the tint reaches in from each edge.
		Reach = 0.34,
		--[[ THE HEARTBEAT (2026-10-19, "a small red border flash during a police chase, to make it
			more thrilling"). The wash above is tied to the bar and is NOT there at a full one, which is
			right for "you are in trouble" but leaves a clean chase looking calm. So for as long as a
			chase is live, all four edges also pulse a faint red between `Min` and `Max`, once every
			`Period` seconds. The bar's wash wins wherever it is stronger, in its own red and blue, so
			trouble still looks like trouble. `Enabled = false`: the bar's wash alone, as before. ]]
		Pulse = { Enabled = true, Min = 0.04, Max = 0.2, Period = 0.9 },
	},

	--[[ THE BUST LIGHTS -----------------------------------------------------------------------

		What the police leave on the RESULTS screen. A bust is the one ending that settles as a
		wreck and is not one (see `BustedWord`), and the screen that reports it used to say so with
		a single word over the same black rectangle every crash gets. This is the rest of that
		sentence: the lights are still going when the numbers come up.

		IT IS DRAWN BY `RaceUIController`, and it lives here anyway, because it is the third place
		in this game that flashes red and blue and the three must not disagree about what that
		looks like. It takes `Vignette`'s two colours verbatim rather than declaring a pair of its
		own — the chase wash and this are the same lights seen ten seconds apart — and the pattern
		below is the light bar the cruisers are running (`Cruisers.FlashTime`) slowed down and given
		the double-blink a stationary car actually makes.

		=== WHY IT IS A STROBE HERE AND AN ALTERNATION DURING THE CHASE ========================

		The chase vignette never goes dark: two colours trade places about the middle, which reads
		as a bar going round without ever taking the road away from the player driving on it. There
		is nothing to see through on the results screen, so this can do the thing the chase version
		is not allowed to — go out entirely between pulses. Dark gaps are most of what makes a
		strobe read as a strobe, and on a screen made of black and two lines of type they cost
		nothing at all.

		=== IT IS ALSO BOUND BY MORE THAN TASTE ================================================

		Flashing red and blue across a whole screen is the exact shape of thing photosensitive
		epilepsy guidance is written about, and this one is watched every time a run ends badly by
		people who never asked for it. `THE PATTERN` below carries the arithmetic and the limit it
		is held under; the short version is that the RATE is the safety number, it is 2 flashes a
		second against a limit of 3, and it must not be raised to make the effect livelier. The
		peaks are tuned quiet on top of that, which is a separate and much softer argument.

		=== AND WHY IT CALMS DOWN ==============================================================

		It is hard for `Hold` seconds, which is the word landing and the bar wiping open, and then
		eases to `Rest` over `Settle`. What comes next on this screen is a payout counting up and
		two receipts under it, and a light hammering at full over a figure the player is trying to
		read is the fastest way to turn a nice beat into one they sit through. Loud where the news
		is, quiet where the reading is.

		=== IT IS ALSO THE SWITCH FOR THE CAR =================================================

		A bust puts the cruiser itself in the slot the results screen keeps for the stolen car, with
		this pattern driving its light bar so the model and the wash around it flash together. That
		is `RaceUIController._showBustCar`, and it is gated on the `Enabled` below rather than on a
		switch of its own: the car and the lights are one picture, and half of it is not an
		arrangement anybody would choose deliberately.

		So `Enabled = false` puts a bust back to being a wreck with a different word on it, and
		`Hud.Enabled = false` takes this with it — the master switch above turns off everything the
		police draw on a screen, and this is one of those things even though it is not the chase. ]]
	Bust = {
		Enabled = true,

		--[[ Peak alpha of an edge band at the height of a pulse, and how far in from its own edge
			it reaches as a fraction of the screen's WIDTH (there are only two of these and they are
			the left and right edges; the chase vignette's four are a different shape).

			Reaching further than the chase vignette on purpose. There it is deliberately confined
			to the edges because the middle of the screen is the game; here the middle is empty — a
			bust shows no trophy — so the falloff is allowed to carry properly into the frame rather
			than being cut off at a third of the way in. What actually crosses the middle is the
			wash below; these two only have to make the sides brighter than it. ]]
		Max = 0.4,
		Reach = 0.46,

		--[[ ...and how much harder each side is drawn than the other, which exists because of the
			ONE thing that is different about drawing these lights here rather than over a race.

			The chase vignette puts the same two colours over a sunlit road, where both of them tint
			what is already there. This puts them over near-black, where alpha is the only thing
			carrying either — and `Vignette.Blue` has about half the luminance of `Vignette.Red`, so
			the two drawn at one strength come out as a hard red flash answered by a soft navy one.
			Photographed side by side it does not read as a bar alternating; it reads as the red
			lamp working and the blue lamp being broken.

			So the blue side is drawn harder to land at the same APPARENT brightness. This is a
			display correction and not a second opinion about the colour: the colours stay the
			cruisers' own, which is the whole reason they are taken from `Vignette` and not
			redeclared here. `Max * Gain` is clamped where it is drawn, so raising either past
			what alpha can express costs nothing but the headroom. ]]
		Gain = { Red = 1, Blue = 1.45 },

		--[[ The whole-screen wash under the bands, as its own peak alpha.

			THIS IS THE ELEMENT THAT MAKES IT LIGHT RATHER THAN GRAPHICS, and it is the one to keep
			small. Two coloured bars blinking at the sides of a screen are two coloured bars; the
			same two with about a tenth of a tint crossing the whole frame with them is a room with
			something flashing in it. Past about 0.15 it stops being a room and starts being a
			colour filter, which is the note `Cruisers.Light` makes at length about the spill
			lights and is the same mistake in a different medium.

			IT IS ALSO THE ELEMENT THAT COSTS THE WASH ITS AREA EXEMPTION, which is why it came down
			with `Max` when the rate did. The thresholds `THE PATTERN` describes let a flash off if
			it covers little enough of the view; a tint across the whole frame never can, whatever
			its alpha. Rate is what makes this safe — but there is no reason for it to be loud as
			well, and a screen the player did not ask to see should err quiet. ]]
		Flood = 0.06,

		--[[ === THE PATTERN, AND THE ONE NUMBER ON THIS SCREEN THAT IS A SAFETY QUESTION =======

			One side owns `HalfPeriod` seconds and fires a pulse at each offset in `Pulse` (seconds
			from the start of its half), then the other side takes over.

			READ THIS BEFORE CHANGING ANY OF THE THREE. The flash RATE these produce is bounded by
			photosensitive-epilepsy guidance, not by taste. WCAG 2.3.1 allows no more than three
			flashes in any one-second window, and the pair of thresholds under it has an escape for
			flashes that are small or dim — which this cannot use twice over. The wash crosses the
			whole frame, so it is not small; and `Vignette.Red` is a SATURATED RED by that standard's
			own test (R/(R+G+B) = 0.81, and the line is 0.8), which is the case the guidance singles
			out and the one where dimming buys nothing at all. Rate is the only lever there is.

			WHAT IS HERE IS 2 FLASHES A SECOND: one pulse per side, sides alternating every half
			second. That is a third under the limit, and the margin is deliberate — a limit is not a
			target, and this screen is watched thirty times an hour by people who did not opt into
			it.

			THE FIRST VERSION OF THIS WAS 4.5 A SECOND AND WAS WRONG. It ran the wig-wag double
			flash — two pulses per side at a 0.44 half period — because that is the pattern everyone
			recognises as an emergency light. It is also, at that rate, exactly the pattern the
			guidance exists to prevent. The double flash is not recoverable by slowing it down
			either: two pulses inside a quarter of a second is a local rate of seven a second
			however long the gap after them is, and the standard measures ANY one-second window.
			So it is one pulse per side, and the police read comes from the alternation and the
			colour rather than from the stutter.

			IF YOU ADD AN OFFSET TO `Pulse`, YOU HAVE DOUBLED THE RATE. Count it: flashes per second
			is `#Pulse / HalfPeriod`. Keep that product at or under 3, and preferably at 2. ]]
		HalfPeriod = 0.5,
		Pulse = { 0 },
		PulseTime = 0.34,

		--[[ The SHAPE of one pulse, and the second half of the same argument. What the guidance
			counts is an opposing TRANSITION — a step from dark to light and back — so a lamp that
			snaps on is worth more than one that swells, at the same peak and the same rate.

			`Rise` is the fraction of the pulse spent coming up and `Decay` the exponent on the fall
			after it. A short rise and a front-loaded fall is what a real lamp does; taking the rise
			to zero is the hard edge this is here to avoid, and it is what the first version had.

			At 0.34 seconds long this is a much slower light than the first pass — closer to a beacon
			turning than to a strobe, which is what the rate above wants it to be anyway. ]]
		Rise = 0.18,
		Decay = 1.3,

		--- The envelope: seconds at full, seconds easing down, and the fraction of `Max` it rests
		--- at once it has. See the note above for why it does not simply stay loud.
		Hold = 1.1,
		Settle = 1,
		Rest = 0.34,

		--[[ THE END PANEL'S CRUISER GLOWS, and that is all the panel gets of the lights above
			(2026-10-01). The kit's end panel shows the cruiser in its corner box (`RaceUIController
			._bustShot`) with no wash at the edges, and its neon lamps alone are a few pixels and read
			as paint. So each lamp gets a soft blob of its own colour over it, on the same pattern and
			the same clock as the lamps, so the light bar blooms instead of the screen flashing.

			`Size` is the blob's diameter as a fraction of the box's height and `Max` its peak alpha,
			scaled by the same envelope as everything else here, so it rests at `Rest` of this once the
			news has landed (0.7 peaks at 0.24 by then). Dylan asked for a little, not a lot.
			`Enabled = false` leaves the panel with the bare lamps it had before. ]]
		PanelGlow = { Enabled = true, Size = 0.9, Max = 0.7 },
	},
}

--- Clamp a value to 0..1 the way every reader of the bar below wants it, so no caller has to.
local function unit(value: number): number
	return math.clamp(value, 0, 1)
end

--[[ Interpolate one of the `{ Far = , Near = , Lead = }` triples above against the chase's one
	number, and it really is one number: five different offsets are driven off it and they must not
	drift apart in how they read it, so this is the only place any of them is read.

	THE SCALE RUNS 0 TO 2 AND THE THREE KEYS ARE THREE ANCHORS ON IT.

	    0   `Near`   an empty bar. They are on your door and cutting in.
	    1   `Far`    a full bar. The ordinary chase station.
	    2   `Lead`   a full bar you are pulling away from (`PoliceConfig.Lead`).

	`PoliceController._stationValue` is what composes that number out of the bar, the lead, the swoop
	a crash puts on it (`Strikes.Swoop`) and the arrival ceiling (`PoliceConfig.Entry`). Nothing else
	may.

	THE CLOSING HALF IS EASED AND THE LEAVING HALF IS NOT, and the asymmetry is deliberate. A linear
	station makes the last third of the bar - the third the player is actually fighting for - the
	third where the cruisers move least, so squaring the closing fraction front-loads the approach:
	they come up quickly and then hang there, which is what a pursuit driver would do and what makes
	the last second feel long. Above 1 the travel is a several-second drift over four or five studs,
	and an ease on that would spend almost all of it in the first half second and then look stuck.

	A PAIR WITH NO `Lead` KEY SIMPLY STOPS AT `Far`, so a station that has no business falling back
	needs no entry and gets none, and an old two-key pair goes on working unchanged. ]]
function PoliceConfig.station(pair: { Far: number, Near: number, Lead: number? }, value: number): number
	local at = math.clamp(value, 0, 2)
	if at <= 1 then
		local closing = 1 - at
		return pair.Far + (pair.Near - pair.Far) * (closing * closing)
	end
	local lead = pair.Lead
	if not lead then
		return pair.Far
	end
	return pair.Far + (lead - pair.Far) * (at - 1)
end

--[[ How fast the lead is building right now, as a fraction of a full lead per second, from the
	car's speed and the two speeds that bracket it. Negative means it is falling back in.

	`gaining` is every condition that is not about speed already answered by the caller: a live
	chase, a full bar, no strike settling, the arrival over, the player actually driving. False
	answers the collapse rate outright, because there is exactly one of those and it does not depend
	on how fast you were going when you stopped earning it.

	Above the floor the gain is scaled by where the car sits between the floor and its own unboosted
	cruise, which is what makes easing off cost ground before it costs any bar, and boost carries it
	past 1 to `Lead.Max`. A `cruise` at or under the floor means the chassis has not declared a
	`MaxSpeed` yet (the first frames of a race); it answers the collapse, which is the safe way to
	fail for the same reason `drainRate` fails toward refilling: a chase that cannot measure the
	player must never be allowed to reward them for it either. ]]
function PoliceConfig.leadRate(speed: number, floorSpeed: number, cruise: number, gaining: boolean): number
	local lead = PoliceConfig.Lead
	local drop = -1 / math.max(lead.Drop, 1e-3)
	if not (gaining and lead.Enabled) then
		return drop
	end
	local span = cruise - floorSpeed
	if span <= 0 or speed < floorSpeed then
		return drop
	end
	local over = math.clamp((speed - floorSpeed) / span, 0, lead.Max)
	return over / math.max(lead.Gain, 1e-3)
end

--[[ How fast the bar is draining right now, as a fraction of a full bar per second, from the car's
	speed and the floor it has to hold. Negative means it is refilling.

	Under the floor the rate runs from `MinDrain` of the full rate up to all of it, on how far under
	the car is (see `MinDrain` for the argument behind that shape). Above it the bar refills flat,
	because "you are driving properly again" has no degrees to it: a player back at cruise and a
	player back at double cruise have both answered the question.

	`floorSpeed` of zero or less means we could not work out what this car cruises at, which happens
	for the first frames of a race before the chassis has declared a `MaxSpeed`. It answers
	"refilling", which is the only safe direction to fail in: a chase that cannot measure the player
	must never be allowed to bust them. ]]
function PoliceConfig.drainRate(speed: number, floorSpeed: number): number
	local refill = -1 / math.max(PoliceConfig.RefillTime, 1e-3)
	if floorSpeed <= 0 or speed >= floorSpeed then
		return refill
	end
	local under = unit((floorSpeed - speed) / floorSpeed)
	local share = PoliceConfig.MinDrain + (1 - PoliceConfig.MinDrain) * under
	return share / math.max(PoliceConfig.DrainTime, 1e-3)
end

--[[ How hard a hit was, 0..1, from the `Shake` the hazard asked `applyImpact` for.

	The single place the `Shake` band is read, because two readers of it would be two ladders of
	hazard severity that could drift apart, and the ladder is the thing this beat is tuned against.
	See `Strikes.Shake` for why `Shake` and not `SpeedKeep`, and for where every hazard in the game
	lands on the scale this returns. ]]
function PoliceConfig.strikeSeverity(shake: number?): number
	local band = PoliceConfig.Strikes.Shake
	local span = band.Full - band.Graze
	if span <= 0 then
		return 1
	end
	return unit(((tonumber(shake) or 0) - band.Graze) / span)
end

--[[ ...and what that costs the bar, given how many strikes already in the chain this one is.

	`links` is 0 for a strike arriving on clean road and counts up for each one inside
	`Strikes.Chain.Window` of the last. The multiplier is `Scale` to that power, so the second hit in
	a chain is worth 1.9 of the first and the third 3.6 of it, capped at `MaxLinks` (see the worked
	table in `Strikes.Chain` for what those come out as against a real bar).

	Returns a POSITIVE fraction of a full bar. The caller subtracts it. ]]
function PoliceConfig.strikeBite(severity: number, links: number): number
	local strikes = PoliceConfig.Strikes
	local bite = strikes.Bite.Min + (strikes.Bite.Max - strikes.Bite.Min) * unit(severity)
	local depth = math.clamp(links or 0, 0, strikes.Chain.MaxLinks)
	return math.min(bite * strikes.Chain.Scale ^ depth, strikes.Chain.MaxBite)
end

--- Which tiles of `map` this file says are police sections, as a set keyed by tile NAME. Empty for
--- a map with none, so a caller can walk it without checking first.
function PoliceConfig.sectionsFor(map: unknown): { [string]: boolean }
	local names = type(map) == "string" and PoliceConfig.Sections[map]
	local set = {}
	if names then
		for _, name in names do
			set[tostring(name)] = true
		end
	end
	return set
end

--[[ Where a global tier sits on its OWN world's ladder, as `(rung, that world's rung count)`, or
	nil for a tier no world has.

	The ladders are laid end to end (`WorldConfig` note 3: world 1 is tiers 1 to 8 and world 2 opens
	at 9), so this is a walk of the offsets rather than a lookup. It lives here rather than in
	`WorldConfig` because `StealHeat` is the only thing that has ever needed to ask. ]]
function PoliceConfig.rungOfTier(tier: unknown): (number?, number?)
	if type(tier) ~= "number" or tier ~= tier or tier % 1 ~= 0 then
		return nil, nil
	end
	for index, world in WorldConfig.Worlds do
		local first = (WorldConfig.RungOffset[index] or 0) + 1
		local count = #world.Cars
		if tier >= first and tier < first + count then
			return tier - first + 1, count
		end
	end
	return nil, nil
end

--[[ ...and whether taking that car is worth a chase (`StealHeat`).

	A tier that is not a number, one off every ladder, and the feature switched off all answer
	false, so a caller can hand it whatever the steal reported without checking it first. The steal
	arrives over a client boundary in one place and off a traffic record in another, and neither is
	somewhere a malformed tier should be able to arm a chase.

	`TopRungs` is clamped one rung short of the world it is measured against. A ladder shorter than
	the knob would otherwise make every car in it high value, which no shipping world is (they are 7
	and 8 cars) but which a greybox one could easily be. ]]
function PoliceConfig.isHighValueSteal(tier: unknown): boolean
	local heat = PoliceConfig.StealHeat
	if not (PoliceConfig.Enabled and heat.Enabled) then
		return false
	end
	local rung, count = PoliceConfig.rungOfTier(tier)
	if not (rung and count) then
		return false
	end
	local top = math.clamp(math.floor(heat.TopRungs or 0), 0, math.max(count - 1, 1))
	return rung > count - top
end

--[[ THE BUST LIGHTS, at `t` seconds into the results screen: how hard the red side is lit and how
	hard the blue one is, each 0..1, and never both at once.

	IT ANSWERS THE PATTERN AND NOT THE PAINT. `Max`, `Flood` and `Reach` are not applied here — the
	same lit fraction is drawn twice at two different strengths (an edge band and a wash across the
	whole frame) and it would have to be divided back out of one of them if this scaled it. So this
	owns the clock and the shape of a pulse, and the screen owns how bright that reads.

	One function rather than two because the two sides are one lamp assembly and they are computed
	from one phase: the caller draws what it is handed and owns nothing about the pattern. That is
	also what lets the whole thing be retuned in `Hud.Bust` without opening the screen that draws
	it, which is the point of it living here at all.

	`t` IS MEASURED FROM THE MOMENT THE SCREEN IS BLACK, not from when it was asked for. Anything
	before that is playing under a half-transparent overlay with the race still showing through —
	the exact mistake `RaceUIController.BEAT_START` exists to document — so a negative `t` answers
	darkness rather than being clamped into the pattern.

	Nothing here has any state in it: hand it the same `t` twice and it answers the same twice,
	which is what makes it safe to drive off a render loop that can miss frames. ]]
function PoliceConfig.bustFlash(t: number): (number, number)
	local cfg = PoliceConfig.Hud.Bust
	if not (PoliceConfig.Hud.Enabled and cfg.Enabled) or t < 0 then
		return 0, 0
	end

	--- The envelope. Full while the news is landing, then down to `Rest` for the reading.
	local envelope = 1
	if t > cfg.Hold then
		local settled = unit((t - cfg.Hold) / math.max(cfg.Settle, 1e-3))
		envelope = 1 + (cfg.Rest - 1) * settled
	end

	--- Which side owns this half of the cycle, and how far into its half we are.
	local half = math.max(cfg.HalfPeriod, 1e-3)
	local phase = t % (half * 2)
	local redLit = phase < half
	local within = if redLit then phase else phase - half

	--[[ ...and the lamp itself: the brightest pulse covering this instant, or nothing between them.
		`max` rather than a sum, so overlapping offsets (a `Pulse` table tuned tighter than
		`PulseTime`) blend into one longer flash instead of stacking past full and clipping.

		UP OVER `Rise` AND DOWN OVER THE REST, never a step. The rise is the half of this that is
		not cosmetic: an instant edge is the transition photosensitivity guidance counts, and it is
		free to avoid. `Rise` is clamped rather than trusted because a value of 1 would divide the
		fall by zero, and a config that can crash the results screen is not a config. ]]
	local lamp = 0
	local width = math.max(cfg.PulseTime, 1e-3)
	local rise = math.clamp(cfg.Rise, 0, 0.9)
	for _, at in cfg.Pulse do
		local since = within - at
		if since >= 0 and since < width then
			local x = since / width
			local level = if x < rise then x / rise else ((1 - x) / (1 - rise)) ^ cfg.Decay
			lamp = math.max(lamp, level)
		end
	end

	local lit = lamp * envelope
	return (if redLit then lit else 0), (if redLit then 0 else lit)
end

return PoliceConfig
