--[[
	RaceConfig
	----------
	Shared tunables for the Rodeo-Stampede-style driving loop: the "enter race"
	trigger, the car that gets spawned, and the RoadService streaming / world-rebase
	behaviour. Server-only for now, but lives in shared/Configs to match Admins/Framework.

	See the road-segment / car-system memory docs for the underlying contract these
	values ride on (SegmentLength, DriveCenterX, ForwardAxis, the tagged Car, etc.).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- For `CarTemplateName` only: the car a run starts in is a rung on the live world's ladder, not a
-- name this file gets to pick. See `WorldConfig.StartRung`.
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local RaceConfig = {
	-- === Entering a race =====================================================
	-- CollectionService tag on the trigger part(s). Note: the in-world part is
	-- literally tagged "EnterRace" (no space), even though it's *named* EnterRacePart.
	EnterRaceTag = "EnterRace",

	-- The HUD's Play button is the OTHER way in, and unlike the pad it is a remote a client
	-- can call from anywhere at any rate, so it gets its own cooldown. `enterRace` already
	-- refuses a player who is mid-race; this covers the gap either side of that — the seconds
	-- between the click and the car existing, and a player mashing Play the instant a run ends.
	-- One second matches the pad trigger's own debounce, and is under the time the entry fade
	-- takes anyway, so nobody who is not scripting it can feel this.
	EnterRequestCooldown = 1,
	-- Value published on Dispatcher's `UIAction` by the Play button's `Action` attribute. The
	-- attribute in the place file has to read exactly this.
	EnterRaceAction = "EnterRace",

	--[[ PLAY IS TWO CLICKS: it opens the world-select screen (`WorldConfig.PageName`) and the world
		you press THERE is the one you drive. Boss's call — "when they click play, they choose a
		world" — and it is what makes the four worlds visible to a player who never found the
		teleport button on the rail.

		The world still comes from the player's attribute, not from the button: the card's press
		sends its index with the entry request and the server sets it before the run starts (see
		`RaceService._onEnterRequest`), so there is still exactly one read of "which world" per run.

		Set false to go back to one click into the world you are already in — the pad in the lobby
		always was and still is that, so this only changes the HUD button. ]]
	PlayOpensWorldSelect = true,

	-- Take the Play button off screen for the length of a run. The driving HUD owns the screen
	-- then, and a live Play button during a race is a button that cannot do anything.
	HidePlayDuringRace = true,

	--[[ ...and the rail with it — the column of page buttons down the left of `MainUI.HUD`
		(INDEX, QUESTS, SHOP, SPAWN CARS, TELEPORT).

		Same argument as the Play button and one stronger. None of those five screens says anything
		about the run you are in the middle of: they spend cash you cannot spend, show a collection
		you cannot change, and TELEPORT would move you between worlds while you are driving through
		one. They are also the only remaining way to put a full-screen panel over the road, since
		there is no other door into a page.

		The pair is two switches rather than one because they are two different claims on the screen
		— a place could reasonably want the rail gone and Play left up, or the reverse — and both are
		read only inside `RaceEntryController._onRaceStart`/`_onRaceEnd`, so flipping either off
		leaves that element exactly where it was authored. ]]
	HideRailDuringRace = true,

	--[[ PLAY CALLS FOR ITS NEXT PRESS once the tutorial is done (2026-10-15). The owner: "make the
		Play Button kinda flash or grow or something, make it feel like oh i gotta click it again".

		`Event` is a Dispatcher REQUEST, like `SuppressPlayButton`: whoever wants the player sent back
		out publishes it, and `RaceEntryController` (the one owner of Play) runs `Modules/ButtonBeckon`
		until Play is pressed. The finish card publishes it as it lands, so "Keep stealing cars" and
		the button it means are on screen together. It pauses while Play is away for a page or a run,
		and ends for the session on the first press.

		Restrained by default, per the house taste. Each part has its own off switch: `Pop = 1`,
		`Rock = 0`, `Shine = false`. ]]
	PlayBeckon = {
		Enabled = true,
		Event = "BeckonPlay",
		--- Seconds from one beat to the next, and before the first.
		Interval = 2.4,
		FirstDelay = 1.2,
		--- The swell's peak, on the hover's own `HoverScale` (hover is 1.04).
		Pop = 1.08,
		--- The rock's first swing in degrees; each swing after it is smaller.
		Rock = 4,
		--- The sheen across the face. White has little contrast on Play's yellow-green, so it needs
		--- most of its opacity to read at all; 0.6 was measured and barely showed.
		Shine = true,
		ShineTime = 0.5,
		ShineAlpha = 0.85,
		--[[ THE TUTORIAL'S ARROW, BACK OVER PLAY (2026-10-19, "make the play arrow show again after
			the tutorial ends"). The tutorial's own green arrow (`UIAssets.Tutorial.Arrow`), bobbing
			over Play for exactly as long as the beckon runs, so it pauses for a page or a run and is
			gone for the session after the press. Parented to Play, so it rides the swell. `ArrowSize`
			is its side as a share of Play's height, `ArrowBob` how far it bobs in the same unit, once
			per `ArrowBobPeriod` seconds. `Arrow = false`: the beckon alone, as before. ]]
		Arrow = true,
		ArrowSize = 0.7,
		ArrowBob = 0.12,
		ArrowBobPeriod = 1,
	},

	--[[ Published on Dispatcher the moment the ENTRY's loading screen starts to lift off a run
		(`RaceUIController._hide`), which is the first frame the player can see the road. `RaceStart`
		is no good for this: it lands while that screen is still black.

		The soundtrack is what keys off it. `MusicController` keeps the lobby music playing under the
		loading screen and crossfades to the road's music here, so the music changes when the picture
		does.

		ONLY THE ENTRY. The way home, the results beat and an aborted entry lifting back onto the
		lobby all come down through the same `_hide` and none of them fire this. ]]
	RevealedEvent = "RaceRevealed",

	--[[ THE OTHER END: published on Dispatcher when a screen that was NOT an entry has finished
		lifting (`RaceUIController._hide`, on the fade's last frame). The way home, the results beat
		and an aborted entry all come down through that one path, and every one of them leaves the
		player stood in the lobby looking at their own plot.

		WHY IT IS THE LANDING RATHER THAN THE START OF THE FADE, which is where `RevealedEvent` above
		is fired. That one announces a picture appearing; this one announces a screen being gone, and
		anything that draws on it wants the second. A toast raised as the results start to fade is a
		toast that spends most of its life behind them.

		`RaceEnd` is no good for this either, for the same reason `RaceStart` is no good for the
		reveal: it lands at the top of the results hold, five seconds before the screen moves.

		`CarryController` is what keys off it: the car a player banked is in their hands by then, and
		this is the first moment they can be told what to do with it. ]]
	ReturnedEvent = "RaceReturned",

	--[[ THE START OF THAT SAME LIFT (2026-09-29): published on Dispatcher the moment a screen that was
		NOT an entry starts fading off the lobby — the fade's FIRST frame, where `ReturnedEvent` is its
		last. It exists for the one subscriber that must cover the screen before the lobby shows
		through: the NEW BEST cutscene (`ShowcaseController`), which follows the results directly
		rather than cutting back to the plot first. Anything that wants to draw ON the lobby still
		wants `ReturnedEvent`, for the reason given there. ]]
	LiftingEvent = "RaceLifting",

	--[[ === RACE AGAIN: the one-press way back out ==============================================

		The results screen is the last thing between a finished run and the lobby, and until now the
		only thing a player could do with it was watch it. Going again from there meant landing on the
		plot, finding Play, picking a world and picking a car — four presses and two screens to repeat a
		run they had just decided they wanted to repeat. RACE AGAIN is that whole trip as one button,
		in the world and the car they were already in (the server has both stored from the last entry,
		so a replay names neither and re-reads the same two values a lobby press would).

		IT DOES NOT MAKE THE SCREEN MODAL, and that is the constraint the rest of these numbers are
		solved for. Doing nothing still goes home exactly as it always did; the button is an offer with
		a clock on it, drawn the way the revive question draws its own (`ReviveController`: the clock is
		a bar, not a number). A player who wants to read their payout and walk away is charged nothing
		for the feature existing.

		`RaceUIController` draws it and `RaceEntryController` sends the request; `ReplayEvent` is the
		one wire between them, and it is a Dispatcher topic rather than a direct call for the reason
		every other cross-controller message here is one — the screen should not have to know which
		controller owns entering a race. ]]
	Replay = {
		Enabled = true,

		--[[ How long the button stands before the screen lifts on its own, measured from the moment it
			has finished arriving.

			FOUR SECONDS IS TWO DECISIONS' WORTH. The numbers land at about 1.5s (`BEAT_LEVEL` and the
			crash split just after it), so the player reads the run, then sees the button, then chooses.
			Under about three the button is a reflex test; much over five and every run in the game ends
			with a screen you are waiting out, which is the exact thing `RESULTS_HOLD_TIME`'s note argues
			against.

			THE RESULTS HOLD IS DERIVED FROM THIS, not the other way round: `RaceUIController` books
			`BEAT_REPLAY + Window` as a floor on the screen, so raising this lengthens the screen and
			nothing else has to be touched. Dropping `Enabled` puts the old 3.2s/5.2s holds straight
			back. ]]
		Window = 4,

		--[[ ...and how long the black is held after a press before giving up on the entry and going
			home the ordinary way.

			THE SCREEN DOES NOT LIFT ON A PRESS. It stays opaque and the entry's own loading screen takes
			it over (`RaceUIController._playReplay`), so a replay never flashes the lobby between two
			runs — which is the whole reason it reads as "again" rather than as "go home, then go out".
			The cost of that is a screen with nobody left to hand it to if the request is refused, and
			this is the fence under it.

			Sized past the worst honest wait: the server defers an entry that arrives while the return
			beat still owns the character (`RaceService._onEnterRequest`), and that beat's own worst case
			is about 2.5s. Eight leaves room for the round trip either side of it and is still short
			enough that a refused press reads as a hiccup rather than as a hang. ]]
		Timeout = 8,
	},

	--- Published on Dispatcher when the results screen's RACE AGAIN is pressed. `RaceEntryController`
	--- is what answers it, with the same request the Play button eventually sends and with neither a
	--- world nor a car named. See `Replay` above.
	ReplayEvent = "RaceReplay",

	--[[ Published by `ReviveController` when the one-screen wreck (`NewUIConfig.WreckPanel`) is
		answered with anything but a revive: `"home"` for END RUN, `"replay"` for a countdown that ran
		out. The panel has already shown the run, so `RaceUIController` skips its results beat for the
		return that follows, and on `"replay"` holds the black and asks for the next race itself. ]]
	WreckAnsweredEvent = "RaceWreckAnswered",

	--[[ The END PANEL (`NewUIConfig.EndPanel`): every ending that has no revive offer shows the
		one-screen wreck's panel over the scene instead of going straight to the black, and the server
		holds the return until it is answered (`RaceService.holdEndPanel`).

		`Seconds` is the countdown under the panel, after which it races again for the player (or
		goes home, if nobody has touched anything since the last time it did). The same eight the
		revive offer gives, so every ending reads the same. `Grace` is the server's slack on top:
		the client answers at zero on its own, and this is only the fence for one that never does,
		which then gets the old results screen. ]]
	EndPanel = {
		Seconds = 8,
		Grace = 4,
	},

	--[[ The set-up car to clone per racer. Resolved by name under Workspace.CarSystem, falling back
		to the first instance tagged CarTag. Kept pristine — we always clone.

		DERIVED, NOT NAMED. It is `WorldConfig.StartRung` of the DEFAULT world — the `Civic`, rung
		1 of world 1 — so the car you start in is always a car on the ladder you are climbing, and
		changing worlds changes it with nothing else to update. Hardcoding a name here was how this
		value went stale: it read `Sedan06` long after the roster was renamed car by car, and every
		race silently fell through to "the first tagged Car in the place".

		THE DEFAULT IS NOT THE ANSWER FOR A PLAYER. A world is per player now, so `RaceService` asks
		`WorldConfig.startBodyFor` with the racer's own world and only falls back to this when it
		has nobody to ask.

		Every car on the roster is the same CarBones chassis under the dress, so which rung this is
		changes how the car LOOKS and what `StealConfig.TierStats` does to it, never how it drives. ]]
	CarTemplateName = WorldConfig.StartBody,
	CarTag = "Car",

	-- Folder (created under Workspace at runtime) that holds spawned, in-race cars.
	RaceCarsFolderName = "RaceCars",

	-- === Road streaming ======================================================
	-- The road is CLIENT-SIDED: driving is solo, so each player builds and streams
	-- their OWN local copy of the road (client-only instances that never replicate).
	-- The server keeps no live road — it only publishes a single tile template and
	-- stashes the authored road out of Workspace so nothing replicates or churns.
	RoadSegmentsFolderName = "RoadSegments", -- authored road container in Workspace (stashed at runtime)
	RoadSegmentTag = "RoadSegment",
	RoadTemplateName = "RoadSegmentTemplate", -- the single tile the server publishes to ReplicatedStorage
	LocalRoadFolderName = "LocalRoad", -- client-only Workspace folder the streamed road lives in

	--[[ === The worlds' roads =================================================
		`Workspace.Worlds` is the authored tile library (see WorldConfig's "The maps"); at startup
		RoadService moves every world folder in it to `ReplicatedStorage.<WorldRoadsName>`, which is
		where clients clone their tiles from.

		MOVED, AND MOVED WHOLESALE, and both halves are deliberate. Moved, because those tiles are
		parked around the lobby — two worlds sit straight through it — so leaving them in Workspace
		means the player can see Arctic through the dealership wall. Wholesale, because
		ReplicatedStorage is one folder for the entire server: there is no per-player copy of it, so
		"publish the world this player picked" is not a thing that exists, and the only honest
		options are all of them or a lazy publish with a readiness handshake the client has no way
		to do safely (a Folder replicates before its 5,000 descendants do). All of them it is.

		THE COST IS REAL AND IT IS THE FIRST THING TO REVISIT: ~16k parts reach every client at
		join whether or not they ever drive those worlds. It is fine for a greybox and it is not
		fine for ship. The fix when it matters is one place per world (TeleportService), which is
		also what makes the teleport screen's name literally true.

		REVISITED 2026-10-20 (`WorldRoadsPerPlayer` below): it was 25k instances, the biggest thing
		in ReplicatedStorage, all of it landing before `game.Loaded` on every join. ]]
	WorldRoadsName = "WorldRoads",

	--[[ === EACH PLAYER IS SENT THEIR OWN WORLD'S ROAD, AFTER THE JOIN (2026-10-20) ==============

		The worlds stay on the server (`ServerStorage.<WorldRoadsName>`) and `ReplicatedStorage`
		keeps only an empty folder carrying the race origin. A client asks for a world's road
		(`RoadController._requestRoad`): once the join screen has lifted, again whenever its world
		changes, and at a race entry that finds it missing. `RoadService` clones that world's tiles
		into the player's PlayerGui, which replicates to that one player and nobody else, a tile a
		frame because a whole City is ~80 ms of cloning.

		THE "FOLDER BEFORE ITS DESCENDANTS" PROBLEM the note above calls unsolvable is solved by a
		count: the folder carries `WorldRoadCountAttribute`, the number of instances the server is
		about to put in it, and the client does not touch it until it holds that many.

		THE SERVER KEEPS NO COPY. Once the client has the whole road it moves it into its own
		`ReplicatedStorage.<WorldRoadsName>` (a client-side child, which `_tileSource` reads exactly
		where it always did) and says so; the server then unparents its copy. Measured in Studio on
		2026-10-20: the client's copy survives that, is parented to nil rather than destroyed, and
		can be re-parented and cloned. So a full server costs one world's clone per join, briefly,
		rather than a world per player for the whole session.

		A race into a world whose road has not arrived waits up to `WorldRoadWait` for it, behind the
		entry's loading screen, and then builds the default road rather than no road. Set this false
		to go back to every world in ReplicatedStorage for everybody. ]]
	WorldRoadsPerPlayer = true,
	WorldRoadCountAttribute = "Instances",
	--- On the public folder: every map the server can send, as "|City|Desert|", so a client never
	--- waits on a road for a world the server has no art for.
	WorldRoadMapsAttribute = "Maps",
	--- Seconds a race entry waits for its world's road. Inside `EnterReadyTimeout` with room left
	--- for the car to arrive and the ring to be laid, or the entry is aborted instead.
	WorldRoadWait = 6,

	--[[ Where the race is built, for every world.

		A world's tiles cannot be streamed where they are authored — `WorldConfig` note on
		`DriveCenterOffset` — so every road is laid at ONE origin instead: the pivot of the authored
		`RoadSegments` tile, published by RoadService and read by both sides. Deriving it from the
		place rather than typing a CFrame here keeps "drag the road somewhere else in Studio and the
		race follows" true, which is how it already behaved.

		Set this to a CFrame to override that (identity rotation, on the deck, +Z down the road). ]]
	RaceOriginOverride = nil :: CFrame?,

	--[[ Fail-safe: how long the server waits for the client to ack that its local road is built
		before giving up and ABORTING the entry (`RaceService._abortEntry` — read its note; the old
		behaviour was to unanchor the car anyway, which dropped it through an empty world).

		RAISED FROM 5 BECAUSE THE TIMEOUT IS NO LONGER DANGEROUS, only disappointing. At 5 a phone
		that was still streaming lost its race; the reason 5 was ever defensible is that the thing on
		the other side of it used to be "go live", which nobody wanted to wait longer for. Now that
		running out of time means a clean bounce back to the lobby, waiting longer is strictly better
		than bouncing sooner, so this is sized to let a slow device finish instead.

		THE CEILING IS THE CLIENT'S OWN FADE SAFETY, which is 12s (`RaceUIController.SAFETY_TIMEOUT`)
		and drops the black overlay whatever the server is doing. Anything at or above that leaves the
		player looking at the lobby with no car and no explanation while this timer is still running,
		so this must stay meaningfully below it — 10 leaves room for the return beat (`_returnToSpawn`
		yields for the seat to release) to finish behind the fade. Raise them together or not at all.

		THE GAP ALSO HAS TO FIT THE ABORT MESSAGE. `RaceAborted` fires the moment this expires and the
		screen says why (`RaceUIController._onAborted`), booking a hold of its own; measured, the
		screen goes at 12.6s off a timeout at 10.06s, which is past the safety on purpose — the safety
		asks for a hide and a hold that is still owed wins. Shrink this gap and the sentence the
		player is reading gets shorter, not the screen. ]]
	EnterReadyTimeout = 10,

	-- Keep this many recycled tiles *behind* the lead car. Anything further back than
	-- this gets moved to the front (moving is cheaper than instantiating — see the
	-- user's note). With N tiles total this leaves N - SegmentsBehind - 1 ahead.
	SegmentsBehind = 2,

	--[[ How many tiles a world's numbered segment is shown for before the road moves on to the
		next one. A world's tiles are a PROGRESSION, not a shuffle: you drive segment 1 for a while,
		then the road becomes segment 2, then 3, and the last one holds for the rest of the run.

		THREE TILES IS ~3,500 STUDS OF THE SAME LOOK, which is a couple of minutes at cruising
		speed — long enough that arriving somewhere new reads as progress rather than as scenery
		churn. City has six segments so its full progression spans 18 tiles; the four-tile worlds
		span 12. Turn this down to see a world's whole road inside a shorter run.

		WHY THIS IS ITS OWN NUMBER AND NOT THE CAR LADDER'S. The obvious idea is to advance the road
		whenever the traffic ladder unlocks a rung, and it does not work: that curve is deliberately
		front-loaded (`TrafficConfig.Bands`), so world 1's first three rungs all arrive inside the
		first two tiles and the road would flick through three looks before you had gone 2,500
		studs. The ladder gives you something to trade up to immediately; the road wants to change
		slowly. Same intent, different clock.

		COSTS ONE TILE CLONE PER RECYCLE while a world still has segments left to reach. The ring is
		nine tiles deep, so any hold shorter than that means a recycled tile is always wanted as a
		different segment than it currently is and has to be replaced rather than moved — about one
		~900-part clone every 1,170 studs, off-screen, two tiles behind the car. It stops entirely
		once the last segment is reached. ]]
	SegmentHold = 3,

	-- If the folder holds fewer tiles than this, RoadService clones up to this many
	-- ONCE at startup (a one-time cost, never per-frame). The SeedRoad command usually
	-- pre-seeds these already.
	DesiredSegmentCount = 9,

	--[[ How much of a road tile one frame may build or tear down, counted in instances.

		THE ROAD'S ONE VISIBLE HITCH USED TO LIVE HERE. A recycle that has to REPLACE a tile rather
		than move it (see `SegmentHold`) does three expensive things — clone ~1,300 instances, insert
		them into the workspace, and destroy the tile that left — and on a live City race those
		measured 24 ms, 19 ms and 20 ms. All three landed on ONE frame, which came out at 63-77 ms
		against a 7 ms median: a tenfold frame every ~1,170 studs for the first two to four minutes
		of every run, which is most of one. Testers reported it as a stutter while driving, and it is
		the spike in the MicroProfiler trace filed with it, labelled `Script_RoadController` over a
		`Clone`. Deferring the destroy did not split it: `RoadController._loop` runs inside a
		deferred Heartbeat handler, and `task.defer` from there resumes in the SAME frame.

		So the replacement is built across the frames BEFORE it is wanted and the retired tile is
		destroyed across the frames after, this many instances at a time. Same total work, spread
		over ~30 of the ~800 frames a recycle interval gives us. Same race, same ring: a 2.3 ms
		worst frame.

		SIZED AGAINST THE SLOWEST FRAME, NOT THE FASTEST BUILD. A tile costs ~25 us per instance to
		clone and place, and about half that to destroy, so this number times 25 us is roughly what
		it adds to a frame — 60 buys ~1.5 ms. There is no reason to raise it: the build has fifteen
		seconds of lead and needs half of one. Lower it if a frame budget gets tighter.

		IT IS A TARGET, NOT A CEILING, because some units cannot be split. `RoadController` opens
		Models and Folders and clones everything else whole, and it will not split a subtree that
		legacy `Weld` joints reach across — the road art has ~87 of them inside one `RoadSurface`
		model, and cloning half of that group would leave the other half's joints pointing back at
		ReplicatedStorage. That group is 116 instances, so ~2.9 ms is the real worst frame here. ]]
	TileBuildBudget = 60,

	-- === Car spawn placement =================================================
	-- Where along the road (forward-axis coordinate) a fresh car is dropped. Every race in
	-- every world starts on the origin tile — see `Lanes` for what keeps two of them apart.
	SpawnAlong = 0,
	-- Studs to lift the car above the deck before letting physics/suspension settle it.
	SpawnClearance = 1.5,

	--[[ === Private race lanes ================================================
		A RACE IS SINGLE-PLAYER, AND THIS IS WHAT MAKES THAT TRUE IN SPACE.

		Everything a run is made of is already client-local — the road (RoadController), the
		traffic (TrafficController), the obstacle course (ObstacleController), the getaway truck
		(GetawayController). None of it replicates, and every driver builds their own copy AT THE
		SAME RACE ORIGIN. The one thing that is NOT client-local is the car itself: it is a server
		model so the server can own the run, which means it replicates to everybody.

		So before this, two players pressing Play landed on the same stretch of road, in each
		other's cars. They collided (both cars are in `PlayerGroup`, which collides with itself),
		each one's local traffic clipped the other's replicated car (`TrafficConfig.Collision`
		predicted exactly this — "if racers ever share one stretch of road visibly, this is the
		seam"), and the stock CarBones suspension raycasts — which run as "Default" and are not
		ours to filter — happily drove one car up over the roof of the other.

		The fix is to stop sharing the stretch of road. Each live race is handed a SLOT, and the
		slot is a storey: slot 0 is the race origin exactly as before, slot 1 is `Spacing` studs
		directly above it, and so on. The server spawns the car there and tells the client to lay
		its road there, so the whole race — road, traffic, obstacles, camera, deck height — moves
		up as one piece and reads identically from inside. Nobody can reach anybody else's storey,
		so there is nothing to collide with, nothing for a suspension ray to find, and (at this
		spacing, past the streaming radius) usually nothing even replicated in to see.

		STRAIGHT UP RATHER THAN SIDEWAYS, for two reasons. Everything in the live Workspace fits
		inside Y ∈ [-163, 217] and the deck is at ~18, so one storey up is provably empty — the
		cross axis is not: the race origin has `Assets` ~500 studs to one side and `CarArt` ~300
		to the other, and the island itself 2,400 studs further on. And a purely vertical offset
		leaves the CROSS coordinate untouched, which is what `ObstacleService._laneIsPlausible`
		and `._nearWall` check a client's damage claims against — they keep working, unchanged and
		still correct, for a player racing on storey 9.

		Slots are claimed on entry and released on every exit, smallest free first, so a one- or
		two-player session only ever uses the bottom storeys and the first racer is at the origin
		on the ground exactly as they always were. ]]
	Lanes = {
		-- Off = every race back at the shared origin, i.e. the behaviour this replaced.
		Enabled = true,

		--[[ Studs between storeys. Has to clear four things at once, and 1,200 clears all of them
			with room to spare: the tallest thing in the map (towers at Y 217, deck at 18), the
			height of the road tiles themselves (~190 of buildings above the deck), `VoidDropStuds`
			below (so a car falling out of storey N is frozen long before it reaches N-1), and the
			default streaming radius (~1,024) — which is the part that means another racer's car
			does not merely look tiny, it usually never reaches this client at all. ]]
		Spacing = 1200,

		--[[ How many storeys exist. Past this, the overflow shares storey 0, which is the old
			behaviour for those players rather than a failure — worth knowing, but out of reach in
			practice: the hub has six plots, so `Players.MaxPlayers` should be six (PlotService
			warns when it isn't) and this is a factor of two above that even before you count how
			many of them are racing at the same instant. Raising it is free apart from the altitude
			the top storey sits at (slot × Spacing). ]]
		Count = 16,
	},

	-- === The rider (seated character) ========================================
	-- The stock SeatWeld plants the character on the seat *surface* at full standing
	-- torso height, so in a low-slung car the head pokes out through the roof. This
	-- offset (seat-local studs, applied to the weld's C0) sinks the rider into the
	-- cabin instead: -Y is down, +Z is toward the back of the car. Their legs end up
	-- inside the opaque floor, which nobody can see.
	-- Set to Vector3.zero to sit exactly where the stock weld puts them.
	--
	-- -0.9 measured against TestCar_FirstTestCar (a very low Aventador body) with a default
	-- R15 rider: stock puts the head top 0.62 studs *through* the roof; -0.9 lands it 0.28
	-- below the roof skin while the feet (0.47) still sit above the body underside (0.44),
	-- so nothing pokes out either end. There's only ~0.2 studs of slack in this car, so a
	-- taller body redress may want its own value.
	--
	-- Re-verified in a playtest on the `Lambo` default (2026-07-27): head top clears the roof
	-- skin by 0.404 studs, so -0.9 carries over unchanged. It carried over because the two
	-- bodies are the same Aventador fitted to the same chassis by wheelbase — their visible
	-- bodywork measures identically (21.849 x 10.358 x 5.258). A redress from a DIFFERENT
	-- vehicle will not inherit that and has to be re-measured with a rider actually seated.
	--
	-- LEAVE THE Z AT ZERO. Fore/aft is not a global any more: since 2026-08-19 each rig in
	-- `Workspace.CarSystem` has its two front seats placed against ITS OWN steering wheel
	-- (`CommandRunnerScripts/RigCarBody`'s `fitSeats`, which new rigs also run). The roster's
	-- wheels sit anywhere from z -0.4 to -3.8, so one number here cannot be right for all of
	-- them, and any value would stack on top of a seat that is already fitted. This offset is
	-- now only about HEIGHT — and it only applies in a race, not to a lobby or garage car.
	RiderSeatOffset = Vector3.new(0, -0.9, 0),

	-- Fallback / alternative: hide the character outright while they're in the car.
	-- Cleaner than any offset, but it rules out the planned "animate out of the car"
	-- exit, so it's off by default — flip this if a redressed car has no headroom.
	HideRiderInCar = false,

	-- === Coming out of the car the hard way ==================================
	--[[ You are out of the seat and you did not choose to be: the car died under you, or something
		prised you out of it mid-race. Either way you go through the windscreen and land on the road
		as a body rather than staying bolt upright in a car that is no longer being driven.

		THE MOMENTUM IS THE EFFECT AND IT IS FREE. Breaking the seat weld hands the body whatever the
		car was doing, so a wreck at 20 studs/s tips you out onto the tarmac and one at boosted cruise
		throws you a long way down it — severity for nothing, out of physics, with no severity term
		anywhere in the code. `Kick` is the small addition on top that stops it reading as a sack
		dropped on the road: enough lift to arc, and enough forward to clear the bonnet of the car
		that is coasting to a stop behind you.

		THE PLAYER'S OWN CHARACTER IS THE RIG HERE, which is what makes this different from the other
		two ragdolls in the game — those are throwaway clones, this one has to stand back up at the
		other end (`Ragdoll.collapse`/`stand`, `RaceService._standRider`). It also has to not DIE on
		the way: see the `RequiresNeck` note in Modules/Ragdoll, and remember `CharacterAutoLoads` is
		off in this place, so a humanoid that kills itself here strands the player for the session. ]]
	RiderThrow = {
		Enabled = true,

		--[[ Attribute set on the character while they are a body, so the client can react without a
			remote of its own. RaceCameraController watches it, and can swing onto the close shot that
			looks at the player instead of the car (CameraConfig.Downed) — the same shot a whiffed bail
			gets. That is currently OFF, because a whiff hides the car for its beat and a wreck cannot:
			see `CameraConfig.Downed.FramesThrownRider`. The attribute is still set and still read;
			what it means today is "the camera knows this is a wreck", not "point at the body". ]]
		Attribute = "RaceRagdoll",

		--[[ Fraction of the car's velocity the body leaves with. 1 is the physical answer and the
			one to keep: the weld break already conserves it, so anything below 1 is actively taking
			momentum OFF a body mid-crash, which reads as hitting an invisible wall. ]]
		VelocityKeep = 1,

		--[[ Studs/s added to that, IN THE SEAT'S OWN FRAME — so -Z is out over the bonnet and +Y is
			up, the same axis convention as `StealConfig.Driver.Kick` (which throws the OTHER driver
			out, sideways through a door, at roughly twice this). Deliberately much smaller than that
			one: this is a body carried out by a crash it was already travelling with, not one
			launched by a thief, and the inherited speed above is doing the work. ]]
		Kick = Vector3.new(0, 15, -6),
		-- Random tumble, radians/s per axis, so no two wrecks throw you out the same way. Under the
		-- whiff's 9: that one is a comedy splat you earned by mistiming a jump, this one is a crash.
		Spin = 7,

		-- Joint limits, degrees. The same pair as the other two ragdolls — loose enough to look
		-- boneless, tight enough that a limb can't invert through the torso. FALLBACK ONLY: a modern
		-- Roblox character is a constraint rig whose ball sockets are already limited per joint, and
		-- much better than one number for all of them, so these are only reached for on a Motor6D
		-- rig. See Modules/Ragdoll's header.
		JointAngle = 50,
		TwistAngle = 40,
	},

	-- === Wrecking out (HP gone → back to spawn) ==============================
	-- Obstacle damage and HP itself live in ObstacleConfig; these are just the beats of the
	-- exit RaceService plays when the car dies.
	--
	-- How long the wrecked car stays on screen (smoking, coasting to a stop, WRECKED banner
	-- up) before the screen starts fading. Long enough to read what killed you, short enough
	-- that you're not waiting to try again.
	WreckHoldTime = 1.5,
	-- The same beat for a whiffed bail, which is a different shot and wants longer: the driver is
	-- ragdolling onto the tarmac with the camera down at road level looking at them (see
	-- CameraConfig.Downed), and the body needs time to actually land and settle before the fade —
	-- cut at 1.5 and you fade out mid-tumble, which reads as the game giving up rather than as you
	-- having missed. Chosen against the ragdoll settling, not against patience; if runs start
	-- feeling padded, this is a fine dial to pull back.
	BadLandingHoldTime = 2.4,
	-- === Banking out (drove into the getaway truck → back to spawn) ==========
	-- The same beat for the run's OTHER ending (GetawayService → RaceService.bankRun). Sized off
	-- what the client is playing rather than off patience: it slides the car into its berth (up to
	-- `GetawayConfig.Bank.DockTimeMax`, 0.9), and only then shuts the ramp and doors behind it — the
	-- ramp lifting off the road, retracting into the bay, and the doors following it in, over
	-- `RampTiltCloseTime + 0.65 * RampSlideCloseTime + DoorCloseTime`. Worst case that is
	-- 0.63 + 0.4 + 0.36 + 0.75 = 2.14, so anything under about 2.2 fades out while the doors are
	-- still swinging — which reads as the getaway being cut short rather than as having made it.
	-- The rest is a shut truck driving off.
	BankHoldTime = 2.4,
	-- Beat between raising the fade and actually teleporting, so the move happens unseen.
	-- Should be >= RaceUIController's FADE_IN_TIME.
	ReturnFadeTime = 0.5,
	-- Optional Workspace child (BasePart) to return players to. nil = use any SpawnLocation.
	ReturnSpawnName = nil,

	-- === Falling out of the world ============================================
	--[[ Studs below the deck at which a car (or its rider) is declared to have left the world, and
		the run is ended for them instead of being allowed to keep falling.

		THE RACE ROAD ONLY EXISTS ON CLIENTS. `RoadController` builds it locally, so on the server
		there is no floor under the race car at all — it stays up purely because the driver owns it
		and simulates it against their own tiles. Anything that punches it through that deck (a
		handoff resolving an overlap at speed, a bad contact with a knocked traffic car, plain
		tunnelling at tier speed) drops it into open space with nothing anywhere to notice.

		And falling used to be FATAL TO THE SESSION rather than to the run. At about 2.3 seconds the
		car passes `Workspace.FallenPartsDestroyHeight`, Roblox deletes every part of the character
		welded into it, the Humanoid enters Dead, and — see PlotConfig.RespawnOnDeath — nothing ever
		gave them a new one. The player was left looking at a camera locked to a body that no longer
		existed. Both halves are fixed; this is the half that keeps it a wreck.

		25 studs cannot false-positive. There is nothing below the deck to legitimately be on, and
		the guard only ever looks DOWN — a car launched off an obstacle is above the deck, not below
		it. Detection therefore lands about half a second into a fall, which leaves most of two
		seconds to freeze the car and play the ordinary wreck beat before anything is destroyed. ]]
	VoidDropStuds = 25,
	-- How often the guard sweeps live races. A fall needs ~0.5s to reach the threshold and ~2.3s to
	-- become unrecoverable, so this is nowhere near tight — it is a poll, not a physics step.
	VoidCheckInterval = 0.1,
	-- The wreck beat for a fall, and much shorter than the other two because there is nothing to
	-- hold ON. Both of those beats buy time to watch something — the car dying, the driver landing.
	-- Here the car is frozen below the deck with the camera following it underground, so the beat is
	-- only long enough for the WRECKED banner to register before the fade covers it.
	VoidHoldTime = 0.35,

	--[[ How long after a car is handed to its driver a fall is read as a FAILED HANDOFF rather than
		as a wreck (`RaceService._catchFall`).

		A fall inside this window is not something the player did. Going live is the one moment the
		car changes hands — the server stops simulating it, and the client only starts once it has
		the assembly — and everything that can go wrong with that handoff goes wrong immediately and
		looks identical to driving off the world: the car is simply below the deck, with the run's
		distance still at zero. Treating that as a wreck is the same mistake `_abortEntry` was written
		to undo, one beat later in the entry: it charges the player a run, a payout and a WRECKED
		banner for their own loading time, and then offers to sell them a revive out of it.

		3 SECONDS CANNOT FALSE-POSITIVE ON A REAL WRECK, because a real one cannot happen yet. The car
		starts stationary at lane centre between the guardrails, and three seconds of full throttle is
		~100 studs down a 1,172-stud tile. Nothing a player can do in that window puts them under the
		deck; the only way down there is through it. ]]
	HandoffGraceTime = 3,

	--[[ === The spawn shield ==================================================

		NOTHING MAY COST THIS PLAYER HP UNTIL THEY CAN ACTUALLY DRIVE.

		The bug this exists for: press PLAY on a slow device, get Roblox's "Gameplay Paused — please
		wait while the game content loads" over the road, and the overlay clears onto WRECKED / no
		payout / kept 25%. The run was simulated while the client was still streaming in, so the car
		took its whole HP bar in hits the player never had a chance to steer around, and was then
		charged the loss for it.

		Why it happens is worth writing down, because it is not that the car is fragile. The engine's
		streaming pause halts the LOCAL SIMULATION — the player's car stops — but it does not halt
		the client's SCRIPTS, and traffic is scripted: `TrafficController` keeps driving its shells
		down the road at cruise while the car sits there unable to move. They arrive at a parked
		target every `TrafficConfig.ClipCooldown` (0.4s) for 5-24 HP a time (`TrafficConfig.Clip`),
		so a 100 HP car is gone in a handful of seconds of somebody else's loading screen. Obstacles
		do the same thing a moment later. That is also exactly why it is a low-end-device bug and why
		"every time I record it starts working": it is timing, and recording changes the timing.

		SO THE SHIELD IS HELD UNTIL THE CAR IS DEMONSTRABLY DRIVING, NOT FOR A FIXED TIME. A timer
		cannot answer this — the whole failure is that we do not know how long that client needs —
		so the server watches the car instead (`RaceService._checkShields`). The car is network-owned
		by its driver, so the position the server holds IS that client's simulation: a paused client
		sends no updates and the car does not move on the server either. Movement is therefore the
		first moment "loaded" and "not loaded" are distinguishable, it costs no remote, and it does
		not depend on the drive shim being installed. `MaxTime` is the backstop for a car that never
		moves at all, not the mechanism.

		IT IS A SHIELD ON THE HIT AND NOT A FLOOR ON THE RESULT, which is the opposite of the
		tutorial's `HealthFloor` (see `ObstacleService._damageFloor`) and the difference is
		deliberate. The tutorial wants damage to LAND so that the eight seconds of traffic teach
		something; this wants the hits not to have happened at all, because the player was not there
		for them. Both go through `ObstacleService._applyDamage`, which is the one place HP moves. ]]
	SpawnShield = {
		Enabled = true,

		--[[ Seconds of shield if the client never reports that it is driving.

			This is a BACKSTOP, and it is set against the thing that actually goes wrong rather than
			against a healthy entry: a healthy entry drops the shield in well under a second, because
			the car is moving. What has to fit inside it is a bad one — the "Gameplay Paused" overlay
			the clips show, which on the reported devices sat over the road for several seconds. 15
			covers that with room over, and it is bounded by something stronger than itself anyway:
			`EnterReadyTimeout` (10s) has already aborted an entry whose client never acked, so the
			only run that can still be here at 15 is one that went live and then stalled. ]]
		MaxTime = 15,

		--[[ Extra seconds of shield after the client says it is driving.

			Not padding. `RaceDriving` is fired the moment the car has moved, which is the moment the
			pause LIFTED — and a car that has spent the pause parked in the middle of the road is
			very often already inside a traffic shell by then. Without this it would take that clip
			on its first unshielded frame, which is the same unearned hit one beat later. Long enough
			to clear the queue that piled up, short enough that it is over before the first real
			obstacle at `ObstacleConfig.SpawnGraceStuds` (260 studs). ]]
		SettleTime = 1.25,

		--[[ What the sweep has to see before it calls this car driving.

			Studs from where the car was handed over, and a floor on how fast it is going right now —
			BOTH, because either alone is a way to be wrong. Speed alone accepts the single frame a
			traffic shell shoves a parked car; distance alone accepts the slow drift of one settling
			off a kerb. Together they mean the car is pulling away.

			8 studs is under a car length and 12 studs/s is about 8 MPH: this is "pulling away", not
			"up to speed". Both have to stay small, because every frame of shield after the player
			has control is a frame of free hits — and the shield is only ever meant to cover the
			window in which there was nobody home to take them. ]]
		DriveStuds = 8,
		DriveSpeed = 12,
	},

	-- === World rebase (keep coordinates near origin) =========================
	-- When the lead car's forward-axis coordinate passes this many studs from origin,
	-- the whole race world (tiles + car assemblies + seated riders) is translated back
	-- toward 0 by a whole number of SegmentLengths, in one atomic step, so nothing moves
	-- relative to anything else. Kept large so rebases are rare; lower it to stress-test.
	--
	-- 25,000 rather than the 8,000 this shipped with, and the ceiling was never precision: float32
	-- still resolves ~0.0015 studs this far out, orders below anything the physics or the camera
	-- can show. It was the cost of the snap, and `RoadController._moveTile` has since taken that
	-- from ~61 ms to ~10 ms. Raising it on top turns a rebase every ~94 s at cruise (~85 studs/s)
	-- into one every ~294 s, which is longer than most runs last: the snap is both much cheaper
	-- and one most players never meet. Lower it to stress-test; the lanes stack vertically (see
	-- `Lanes`), so raising it costs no horizontal room.
	RebaseThresholdStuds = 25000,
}

--[[ The world-space offset of a race lane (see `Lanes`). `nil` and 0 both mean the race origin
	itself, which is what a lane-less race — the feature switched off, a slot that could not be
	claimed — has always used.

	One function, on the shared config, deliberately: the server places the car with it and the
	client lays its road with it, and a storey the two disagreed about is a car spawned in mid-air
	over somebody else's road. (The server still sends the answer rather than the slot, so there is
	one evaluation per race and not two — this is here so the two ends cannot drift.) ]]
function RaceConfig.laneOffset(slot: number?): Vector3
	if not (RaceConfig.Lanes.Enabled and slot and slot > 0) then
		return Vector3.zero
	end
	return Vector3.yAxis * (slot * RaceConfig.Lanes.Spacing)
end

return RaceConfig
