--[[
	LobbyCarConfig
	--------------
	Standing in the lobby, pressing SPAWN IN LOBBY on a car in the Cars Inventory, and having that car
	appear next to
	you to drive around and show off. The showroom half of the meta game: `GarageConfig` is the six
	bays that print money, this is the one car you can actually sit in.

	FOUR THINGS TO KNOW BEFORE TUNING ANY OF IT.

	1. A LOBBY CAR IS A WHOLE ROSTER CAR, NOT A REDRESS. Every model under `Workspace.CarSystem` is a
	   complete CarBones rig — chassis, seat, `Scripts.Vehicle`, prompt GUI, all 49 of them (checked,
	   not assumed) — so spawning `Sedan12` is `CarSystem.Sedan12:Clone()` and nothing else. There is
	   no mesh graft here and there must never be one: `CarBody.swapMeshes` exists because a STEAL
	   has to change the car you are already driving without interrupting it, and none of that
	   applies to a car being created from nothing. See `LobbyCarService._prepare`.

	   The flip side is that the driving is not ours either. The stock scripts riding along in the
	   clone raise their own proximity prompt, deploy their own controls on sit, and own E for exit
	   — the same stock system `RaceService` re-deploys by hand. Nothing in this feature drives the
	   car, which is exactly what "use the stock Roblox chassis" asks for. The one addition is that
	   JUMP gets you out as well (`JumpExit`, below), through the kit's own exit.

	2. ONE CAR PER PLAYER, AND PICKING AGAIN REPLACES IT. Not a tuning knob, which is why there is no
	   config value for it: a full roster is 43 cars x ~310 instances, and "spawn them all" is a
	   server nobody can walk around in. The rule lives in `LobbyCarService.setLobbyCar`, which
	   despawns what you had before spawning what you asked for. Pressing the car you already have
	   out puts it away, so the same list is both the spawner and the despawner and there is no
	   second button to find.

	3. THE CAR IS PLACED AGAINST THE WORLD, NOT AT A PAD. There is no authored spawn point — you can
	   be anywhere in the city when you press it — so the placement raycasts for ground under a few
	   candidate spots around you and takes the first one that is also CLEAR (see `Placement`). That
	   is the opposite of the house "the map is the contract" rule everywhere else in this project,
	   and it is on purpose: a pad would mean walking to it, and the point of this feature is that
	   your car turns up where you are standing.

	   CLEAR INCLUDES OTHER PLAYERS' CARS, and it did not always. The world half of that test has
	   been there since the first version; the car half was missed because the query that looks for
	   ground has to IGNORE the cars already out (a roof is not ground) and both queries were handed
	   the same ignore list. Two cars placed in one volume is not a cosmetic overlap — it is two
	   ~400-mass assemblies interpenetrating, and the solver's answer is to fire both into the sky.
	   `LobbyCarService._ignoreList` is where the two lists part company.

	4. RACING AND SHOWING OFF ARE MUTUALLY EXCLUSIVE. Entering a race despawns your lobby car
	   (`RaceService`'s `RaceEntered` signal) and you cannot spawn one while racing. Not a technical
	   limit — the race car IS your car for the duration, and leaving a second one parked in the
	   lobby with your name on it is a state nobody asked for.
]]

local LobbyCarConfig = {}

-- Master switch. Off = the remotes still exist but every request is refused and nothing spawns.
-- The Cars Inventory is unaffected and simply never gets a car out, which is the honest thing for
-- it to show if this is switched off mid-session.
LobbyCarConfig.Enabled = true

-- === Where the cars live ====================================================

-- Workspace folder every spawned lobby car is parented to, created on demand. One folder rather
-- than one per player: the owner is on the model as an attribute, and a flat folder is what makes
-- "how many cars are out?" a single `#GetChildren()` in the Studio explorer during a playtest.
LobbyCarConfig.FolderName = "LobbyCars"

--[[ Stamped on the spawned car Model. `Owner` is the UserId (not the Player — an instance reference
	would keep a leaver's Player alive), `Body` is the roster name it was cloned from, and `Key` is
	the full CAR KEY (`GarageConfig.carKey` — "Sedan12:6") identifying WHICH of that player's copies
	of that body is out.

	BOTH, RATHER THAN THE KEY ALONE, because they answer different questions and each has a reader
	that cannot use the other: `Body` is what the roster is looked up by and what the spawn/despawn
	signals carry, while `Key` is what tells a red Camaro from a black one for the toggle and for the
	page's marker. Deriving one from the other at every use is a parse per read of a string that
	never changes. ]]
LobbyCarConfig.OwnerAttribute = "LobbyCarOwner"
LobbyCarConfig.BodyAttribute = "LobbyCarBody"
LobbyCarConfig.KeyAttribute = "LobbyCarKey"

--[[ Player attribute holding the CAR KEY currently standing in the lobby, or "" for none.

	A PLAYER ATTRIBUTE RATHER THAN A REMOTE, the same house pattern as `GarageConfig.OwnedAttribute`
	and `LotAttribute`, and for the same payoff: the Cars Inventory redraws itself from an attribute
	change, so the "SPAWNED" marker on a card is written by the one thing that actually knows —
	the server, after it has really spawned the car — instead of by the click that asked for it.
	One code path, and it cannot disagree with what is standing in the world.

	A KEY AND NOT A BODY NAME, since the page lists a card per owned car and a player can own the
	same body in several colours; marking by body would light up all of them. ]]
LobbyCarConfig.SpawnedAttribute = "LobbyCar"

-- === Talking to the server ==================================================

-- Per-player floor between accepted requests. Same shape and the same reason as
-- `RaceConfig.EnterRequestCooldown`: cloning a 310-instance rig is several frames of server work,
-- and this is a client-driven remote. Stamped on the ATTEMPT, so a refusal is as cheap as a spawn.
LobbyCarConfig.RequestCooldown = 0.75

-- === Held before it is dropped ==============================================
--[[ THE TOY. Pressing a card no longer puts the car in the street: it puts a small copy of that car
	in your HANDS, and the car turns up where you are standing when you click.

	=== WHY THE INSTANT SPAWN WAS THE PROBLEM =================================================

	The press happens with a full screen panel over the lobby, and the car arrives BEHIND it. So the
	moment the feature pays off is the one moment the player cannot see, and what they get instead is
	a screen that closed and a car somewhere off to one side of them. `PagesV2/Dealership` closing
	itself on the press (2026-09-19) was the first half of fixing that. This is the second: the
	reward is put in the player's hands on the way out of the menu, and the last step of getting it
	is an action they take, out in the world, looking at the place it will appear.

	IT IS THE SAME TOY THE BANKED CAR USES, and that is the whole point of it rather than an
	implementation note. `CarryService` already knows how to build a shrunken car, weld it into a
	hand that is posed to hold something, take it off for a race and put it back after one. This
	feature adds a SECOND REASON for that hand to be full, and nothing else: no second model, no
	second pose, no second set of rules about what a death does to it.

	=== THE TWO REASONS ARE NOT THE SAME THING, THOUGH ========================================

	A banked car in your hands is a pending PLACEMENT and it is stored in the profile: it survives a
	rejoin, and where it goes is a bay on your own lot. This one is a pending SPAWN, it lives in
	memory only, and where it goes is the ground in front of you. So they differ in three ways that
	matter, and all three fall out of that:

	  • THE BAYS DO NOT GLOW for a lobby toy, and no card is raised. `CarryController` draws both of
	    those off `CarryConfig.Attribute`, which only the garage writes, so a lobby toy is invisible
	    to that controller by construction rather than by a check.
	  • THIS ONE IS CLICKABLE and the banked one is not. `CarryService` reads that off whichever
	    source handed it the car, and the click is bound by `LobbyCarController` alone.
	  • A REJOIN DROPS IT. There is nothing to restore: the car is in the collection, the screen that
	    offers it is one press away, and a toy that survived a server restart would be a promise the
	    player did not make.

	=== IT STANDS DOWN COMPLETELY WHEN SWITCHED OFF ===========================================

	`Enabled` false and the press spawns the car exactly as it did before any of this: no toy, no
	attribute, no click. It is the honest A/B, and the question it is asking is whether holding the
	car makes players notice they got one. ]]
LobbyCarConfig.Toy = {
	Enabled = true,

	--[[ Broadcast onto the Player: the car key waiting to be dropped, or "" for empty hands. The
		same bargain `SpawnedAttribute` above makes and for the same payoff, with one addition: this
		one is also how `CarryService` is told what to build, so the model in the hand and the line
		on the screen are reading one fact rather than two.

		IT IS NOT `CarryConfig.Attribute`. That one means "a banked car is waiting for a bay" and is
		written to the profile; sharing it would light up the lot's podiums for a car that is not
		going on one. See the note above. ]]
	Attribute = "LobbyCarToy",

	--[[ client -> server (no arguments): drop what I am holding. Declared by name on both sides.

		NO CAR KEY ON THE WIRE, deliberately. The server already knows which car it handed over, so
		a forged message can only ever ask for the one the player is really holding, and the whole
		of what the client is being trusted with is the WORD "now". Where the car goes is the
		server's own `Placement` ring, which is the same arithmetic it used when the press spawned
		the car directly. ]]
	RemoteName = "RequestDropLobbyCar",

	--- Per-player floor between accepted drops, in seconds. Shorter than `RequestCooldown` because a
	--- drop that finds nowhere to go does no cloning at all, and a player who clicked into a wall
	--- should be able to turn around and click again without waiting for a spawn they never got.
	DropCooldown = 0.5,

	--[[ WHAT THE PLAYER IS TOLD, once, while the toy is in their hands. It goes away on its own
		clock and the toy does not, because the car being held is already the reminder.

		THREE STRINGS AND NOT ONE, for the reason `prompts-are-device-three-way` records the hard
		way: a phone that is told to click has been told nothing. The engine fires `Tool.Activated`
		for all three, so the CODE is one line and only the sentence changes. ]]
	Hint = {
		Enabled = true,
		Mouse = "Click to drop your car",
		Touch = "Tap to drop your car",
		Gamepad = "Press RT to drop your car",
		--- Seconds it stands. Long enough to read twice at a walk, which is what the player is doing
		--- while they look for somewhere to put a car.
		Seconds = 7,
		--[[ How far down the screen, as a fraction of it.

			BELOW THE CHARACTER AND ABOVE THE PLAY BUTTON. Measured on the shot rather than picked: at
			0.42 the line lands across the player's own head and whoever is stood behind them, which
			is the half of the screen the thing being talked about is in. 0.70 is the band between
			their feet and the Play button, clear of the kit's side rails as well. ]]
		CentreY = 0.7,
		Colour = Color3.fromRGB(255, 255, 255),
		--- The kit's PLAY gold on the verb's own rim, which is this palette's word for the thing you
		--- are meant to do next.
		StrokeColour = Color3.fromRGB(12, 16, 28),
		TextSize = 34,
	},
}

-- === Placement ==============================================================
--[[ Where the car turns up. Header note 3 covers why this is computed rather than authored.

	The candidates are tried in order and the first one with GROUND under it and NOTHING SOLID in
	the car's own volume wins. Offsets are in the player's frame: +Z is the way they are facing,
	+X is their right.

	`Ahead` is 22 because the car is 20.6 studs long (`CarBody`'s measured HitBox) and it is placed
	nose-in toward the player — so at 22 studs the far end of it is ~32 studs out and the whole car
	is comfortably in frame, while the near end is still close enough to walk to. ]]
LobbyCarConfig.Placement = {
	Ahead = 22,
	Side = 15,

	--[[ Tried in this order; each is (right, forward), scaled by `Side` / `Ahead` above and then by
		the ring. Eight compass points rather than the obvious three, because the place a player
		presses this from is usually their own PLOT — a courtyard with a building on it — and the
		first version, which only looked forward and sideways, put a car inside that building often
		enough to be the normal case rather than the edge one. Two dozen raycasts once per press is
		nothing; a car spawned in a wall is launched forty studs into the air by the solver. ]]
	Candidates = {
		{ 0, 1 }, -- straight ahead: the one you expect
		{ 1, 1 }, -- ahead-right / ahead-left, for a car park or an alley
		{ -1, 1 },
		{ 1, 0 }, -- beside you
		{ -1, 0 },
		{ 1, -1 }, -- behind-right / behind-left
		{ -1, -1 },
		{ 0, -1 }, -- straight behind, when you are facing a wall
	},

	--[[ Distance multipliers over the whole candidate ring, nearest first. A second pass further out
		is what gets a car onto the street when every spot on the plot itself is taken.

		THE THIRD RING IS ABOUT OTHER PLAYERS' CARS. Since a spot with a car in it is refused outright
		rather than used as a fallback (`_placement`), the eight-by-two ring can be used up by a
		handful of cars parked around a busy plot — and the outcome of running out is that the button
		does nothing. 24 candidates is cheap (24 raycasts and at most 24 box queries, once, on a press
		that then clones a 310-instance rig) and it is what keeps "nowhere to put it" theoretical. ]]
	Rings = { 1, 1.8, 2.8 },

	--[[ The ground probe. Starts `ProbeUp` above the candidate and runs `ProbeDown` — generous in
		both directions, because the lobby has raised plot decks and the player may be standing on
		one while the spot in front of them is the street below. A candidate with no hit inside that
		range is skipped rather than placed at the player's own height: a car dropped into open air
		falls, and a falling car reads as the button being broken. ]]
	ProbeUp = 10,
	ProbeDown = 80,

	-- Gap left between the wheels and the ground the probe found, so the suspension settles onto it
	-- instead of starting interpenetrated. Same value and the same reason as RaceConfig's.
	Clearance = 1.5,

	--[[ How much bigger than the car the clearance test volume is, per axis. The car is checked
		against the world at its intended pose before it is parented, so a spot inside a building —
		or with somebody else's car already standing in it — is rejected before anything is on screen.

		Padded rather than exact: a car that fits its own bounding box with nothing to spare is one
		that is touching a wall, and the stock suspension resolves that by shoving the car sideways
		at speed. Against another car that is worse than untidy, which is why an occupied spot is
		refused outright and never taken as a fallback; see `LobbyCarService._blockedBy`. ]]
	ClearancePad = Vector3.new(3, 1, 3),

	--[[ How far from a car's pivot a part may be and still count as part of that car, when the box
		to place is measured (`LobbyCarService._measure`).

		A LIMIT AT ALL BECAUSE FOUR ROSTER RIGS CARRY DRIFTED CHASSIS PARTS ~796 STUDS BELOW THE CAR,
		which is a place-file fault from the pack import rather than anything this feature does — but
		it is one that silently turns the clearance box into an 800-stud-tall volume that overlaps
		everything, which disables the check above rather than tripping it. 30 is nowhere near either
		side of the gap it splits: the furthest part that legitimately belongs to a car is 11.93 studs
		out, measured across all 65 rigs. ]]
	MeasureRadius = 30,
}

-- === Getting in ============================================================
--[[ The door beat, which in the lobby is OURS rather than the stock script's.

	THE STOCK ORDER IS SIT-THEN-SWING, and that is the whole reason this section exists.
	`VehicleSeating`'s prompt handler calls `seat:Sit(humanoid)` and opens the door on the next line,
	so you are already behind the wheel before the door has moved a degree — the swing plays out
	around a driver who is visibly already inside, which reads as scenery rather than as getting in.
	Putting a beat between the two means owning the trigger, which is what
	`Vehicle.DeferredEntryAttribute` and `LobbyCarService._wireEntry` are for. Everything the stock
	block did is reproduced there; these are the numbers it does it with.

	ONLY THE LOBBY. A race car is seated programmatically and never raises a prompt at all, so none
	of this is on the path that matters for a run — it is a piece of showroom polish for the one
	place in the game where you walk up to a car and get into it. ]]
LobbyCarConfig.Entry = {
	--[[ How long the door swings before the player is put in the seat. THE ONLY NUMBER IN HERE THAT
		IS ABOUT FEEL.

		0.4 lands the sit at roughly 45-50 degrees of a 55-degree swing (measured: 23 degrees at
		0.21s, 48 at 0.41s, peak near 0.5s), so the door is unmistakably open — it has stopped
		accelerating and is visibly at rest — but has not been standing there long enough to look
		like it is waiting for you. Push it past ~0.6 and the door is fully open with nothing
		happening, which reads as a hitch; drop it under ~0.25 and it is back to the stock problem of
		popping in before the door has cleared the sill. ]]
	SeatDelay = 0.4,

	-- How long the door stays open once you are in, before it swings shut. The stock
	-- `DOOR_OPEN_TIME` is 0.5 measured from the sit; this is measured from the same moment and kept
	-- shorter only because the door has already been open for `SeatDelay` by then.
	DoorHold = 0.25,

	-- The swing itself. Both match the stock `DOOR_OPEN_ANGLE` / `DOOR_OPEN_SPEED` on purpose, so a
	-- door driven from here and one driven by a stock trigger — getting OUT still is one — land in
	-- the same place at the same rate and cannot be told apart.
	DoorAngle = 55,
	DoorSpeed = 2.15,

	-- Stock `MAX_SEATING_DISTANCE`. Re-checked after `SeatDelay` as well as before the swing, since
	-- the whole point of this section is that there is now a window in which you can walk away.
	MaxDistance = 15,

	--[[ WHERE THE PILL FLOATS, measured in the DRIVER'S SEAT'S own frame: negative X is outboard
		towards the driver's door, Y is up off the seat pad, Z runs towards the back of the car.

		THE PACK AUTHORS THIS AT (-1.87, 6, 0) AND SIX IS TOO HIGH. Measured across all 65 rigs, the
		top of the body sits between 2.89 and 5.91 studs above the seat pad, so the stock pill hangs
		somewhere between 0.1 and 3.1 studs clear of the roof and on most cars reads as a sign in the
		air near the car rather than as anything belonging to it. That is the report: "put the prompt
		in the proper position".

		2.2 up is roughly the window line on every body in the roster, and 2.6 out puts it at the
		skin of the driver's door: outside a narrow car, just inside a wide one. Either way it lands
		ON the door you are about to open, which is the thing the press is about. Being inside the
		bodywork costs nothing because `ButtonGuiPrototype` is `AlwaysOnTop`, so the pill draws over
		the car instead of being swallowed by it.

		IT ALSO CENTRES THE REACH BETTER, which is a real gain and not a side effect worth ignoring.
		`MaxActivationDistance` is measured from this point while the handler measures to the SEAT,
		so the two rings agree only as far as this offset is small. The pack's offset is 6.28 studs
		off the seat and nearly all of it is straight up, where a player never is; this one is 3.41
		and it is spread across a direction players actually stand in. Worst-case disagreement
		between "the prompt is showing" and "the handler will seat you" roughly halves.

		Z STAYS AT THE SEAT, which is what makes this one offset do all four doors. It is written on
		the driver's attachment before the car is parented, and `Vehicle.raisePassengerPrompt` then
		copies it onto the other three seats with the X mirrored for the two across the car. Each
		attachment is parented to its own seat, so the same numbers land at the front-left window,
		the front-right one and both rear ones. `VehiclePromptGui` hangs the pill on whichever of
		them the press is actually for. ]]
	PromptOffset = Vector3.new(-2.6, 2.2, 0),
}

--[[ === RIDING SHOTGUN =======================================================================

	Whether a lobby car's three passenger seats are open. They are.

	IT IS NOT A NEW MECHANIC, IT IS AN UNBLOCKED ONE. Every rig in the roster has `SeatFR`, `SeatRL`
	and `SeatRR` under its chassis and has had since the packs were imported. What they were missing
	was the `PromptLocation` attachment the stock seating code reads before it connects anything, so
	the seats were inert at both ends — no way in, and no way out for anyone put in one by hand.

	ONE PROMPT DOES ALL FOUR SEATS. Not the obvious shape, and the obvious shape was tried and
	measured: a live prompt per door makes the DRIVER'S seat unreachable, because all four share E,
	the engine shows one and does not choose the nearest. `_wireEntry` carries that measurement and
	the design that replaced it — the car's one prompt puts you behind the wheel if it is free and in
	the nearest free seat if it is not. `Vehicle.PassengerEntryAttribute` covers the inert half.

	IT IS OPEN TO EVERYONE, NOT TO THE OWNER. That is the same decision the driver's seat already
	made — "an empty lobby car is open to anyone who walks past", `_despawn`'s note — and it is the
	whole point of the feature: a car standing in the street with your name on it is something to
	show off, and showing it off means somebody else gets in. The one thing that stays refused is
	taking a seat off the person in it: `AllowCarjacking` is stamped false on every car, so an
	occupied seat's prompt goes dark and the stock handler will not evict.

	AND THEY EMPTY WITH THE CAR. `_despawn` runs `Vehicle.evictOccupants`, which walks the car's own
	seats rather than looking for the owner — so putting your car away, dying, or driving off into a
	race stands your passengers up in the road rather than deleting the car around them.

	Off = the seats go back to being scenery. Nothing else in the file depends on it. ]]
LobbyCarConfig.Passengers = {
	Enabled = true,
}

--[[ Whether a spawned car survives its owner dying. It does NOT.

	A lobby car is welded to nothing and its owner respawns at their plot, which can be most of the
	city away — so a death otherwise leaves a car parked wherever it happened, with the player's name
	on it and no way to reach it except to walk. Despawning is the only outcome that leaves the
	world in a state the Cars Inventory can still describe. ]]
LobbyCarConfig.DespawnOnDeath = true

--[[ JUMP GETS YOU OUT (2026-10-13, Aleafo: "should be jump to leave ur car in the lobby").

	WHY IT DID NOT ALREADY. A seated humanoid that jumps stands up, but the jump never reaches it: the
	kit's `Keymap.Handbrake` is Space and ButtonA, and the deployed `Driver` sinks every key in its
	keymap through one `BindActionAtPriority` at `ContextActionPriority.High`. So in the driver's seat
	Space was a handbrake nobody knew about, and only E (or Y) got you out. The PASSENGER seats were
	never the problem: the stock `Passenger` script already binds Space and ButtonA to its exit.

	WHAT IT DOES. `LobbyCarController` binds `Keys` one step ABOVE the kit's priority while you sit
	in the driver's seat of a lobby car, and a press calls the car's own
	`LocalVehicleSeating.ExitSeat()`. That is the exact function E calls, so the server does the unseat and
	the anti-trip, the Driver switches itself off through its own exit hook, and the prompt comes
	back, all as before. The lobby handbrake goes with it; nothing in the lobby needed one.

	A PHONE IS NOT ON THIS LIST, MEASURED 2026-10-13 in the iPhone 14 simulator. Seated, the kit's
	`TouchControlFrame` lays its 70px `AccelerateButton` exactly over Roblox's `JumpButton` (the
	kit's `disableJumpButton` writes `JumpPower`, a no-op under `CharacterUseJumpPower = false`, so
	the jump button stays live UNDER the pedal and no tap ever reaches it). What a phone does have is
	the kit's own 44px `ExitButton`, the door just above the pedal, and it gets you out.
	Making the jump button the way out on touch means moving the kit's pedal, which is a layout call.

	LOBBY ONLY. Bound off `OwnerAttribute` on the car, which a race car never carries, so the race's
	Space (BAIL, `StealConfig.BailKeys`) and its locked-in seat (`DriveController._holdSeat`) are
	untouched.

	Off = Space is the stock handbrake again and E is the only way out. ]]
LobbyCarConfig.JumpExit = {
	Enabled = true,
	--- Gamepad A is also what activates a live GUI selection (`GamepadNav`); with a highlight up, the
	--- press goes to the button and not here, which is the right way round.
	Keys = { Enum.KeyCode.Space, Enum.KeyCode.ButtonA },
	--- Seconds after a jump-exit before another can fire: a mashed Space is one exit call.
	Cooldown = 0.5,
}

--[[ THE SPAWNER PAD (2026-10-06, Leaf: spawning a lobby car should be obvious). Header note 3 says
	there is no pad, and that still holds for the Cars Inventory: its car turns up where you stand.
	This is a second door for players who never open that screen. Every part in the map tagged `Tag`
	gets a prompt; pressing it puts your best car on the pad and you in it.

	WHICH CAR: your most valuable STARRED car if you have starred any, else your most valuable car.
	The star is the player saying "this one"; value is the fallback nobody has to configure.

	WHERE: on the pad. An Attachment named `SpotName` under the pad, if there is one, is where the
	wheels go and its LookVector is where the nose points; without it, the pad's top face, nose along
	the pad's LookVector. If another player's car is still standing on the spot, the car goes beside
	you instead (`Placement`), because two cars in one volume launch each other.

	A SECOND PRESS BRINGS IT BACK. If your car is already out, the pad puts it away and stands it on
	the pad again, rather than toggling it off the way the inventory card does: someone pressing a
	spawner wants a car in front of them.

	THE MAP IS THE CONTRACT: the tag, not a path. A map without a tagged part has no pad and nothing
	else changes. ]]
LobbyCarConfig.Pad = {
	Enabled = true,
	Tag = "LobbyCarPad",
	SpotName = "CarSpot",
	ActionText = "Spawn Car",
	ObjectText = "Your best car",
	HoldDuration = 0.3,
	MaxDistance = 12,
	--- Sit the owner in it once it lands, after this many seconds of settling (`_seatDriver`).
	Seat = true,
	SeatDelay = 0.4,
	--- Per-player floor between presses. A press clones a 310-instance rig.
	Cooldown = 2,

	--[[ === YOU PICK THE CAR — 2026-10-08 ===
		WAS: the pad chose for you (best starred, else most valuable — `_padPick`), which was right for
		a first-time player and wrong for anyone who wanted to cruise in anything else. The owner: "can
		we add a nice UI showing all of the player's owned cars and he chooses which to spawn". IS: the
		press opens the SELECT CAR screen (`PagesV2/StartCar`) in its SPAWN mode — every owned car, no
		starter card, SPAWN on every button — and the car picked lands on the pad that was pressed.

		THE PAD IS REMEMBERED ON THE SERVER, not sent back by the client: the press records which pad
		and when (`LobbyCarService._padPending`), and the pick (`RequestPadSpawn`, a car key and nothing
		else) is honoured only within `PickerSeconds` of it and only while the player is within
		`PickerReach` studs of that pad. The key is checked for ownership by `setLobbyCar` as on every
		other path. So the most a lying client gets is one of its own cars on a pad it just pressed.

		`Picker = false`: the press spawns the best car on the spot, exactly as before. ]]
	Picker = true,
	PickerObjectText = "Choose a car",
	--- Long enough to scroll a big collection and read the stats; a pick after this is a stale screen.
	PickerSeconds = 90,
	--- Studs from the pad the player may wander while choosing. Generous: the screen is up, they are
	--- not walking on purpose, but a character settling or a nudge from another player moves them.
	PickerReach = 30,
}

-- === How it drives =========================================================
--[[ LOBBY HANDLING (2026-10-08, the owner: "very stiff, cars behave weird, it's not enjoyable").
	`LobbyDriveController` has the three rig faults this fixes and how; `LobbyCarService._prepare` has
	the stats. Every number here is a TASTE CALL to be tuned by driving, not a measurement.

	  Stats          stamp the car's own `CarConfig` stats (with level and parts) on a lobby car, as the
	                 race does. Off: the raw model's authored numbers.
	  SteerRise      seconds from straight to full input when a key is held. 0.2 is quick enough that a
	                 turn starts the moment you press, slow enough that a tap is not a swerve. Raise it
	                 for lazier steering, lower toward 0 for the old snap.
	  SteerFall      seconds back to straight on letting go. Quicker than rising on purpose: a car that
	                 lingers in a turn after you release is what reads as stiff.
	  FullLockBelow  share of top speed under which the full lock is allowed (car-park manoeuvring).
	  HighSpeedLock  share of the input allowed AT top speed, before the chassis cubes it (0.7 is about
	                 a third of the wheel lock). Lower = calmer at speed, wider fast corners; 1 = no limit.

	`Enabled = false`: no handling layer and no stats — the bare rig, exactly as before.

	=== FIRST DRIVE — 2026-10-08 ===
	The owner, on the first cut: "sticking or delayed a little, bit twitchy and bouncy, won't really
	turn at speed". Each half of that has its own cause:

	  DELAYED: the ease and the chassis's cube compound. Half-way up a 0.2s ease the input is 0.5 and
	  the wheels get 0.5^3 = 12.5% — so the turn arrived late, then all at once. SteerRise 0.2 -> 0.07,
	  SteerFall 0.12 -> 0.05: still no one-frame snap, but nothing you can feel as lag.
	  WON'T TURN AT SPEED: HighSpeedLock 0.7 cubed is 0.34 of the lock. 0.7 -> 0.9 (0.73 of it), and
	  the full lock now holds to 40% of top speed (was 25%).
	  TWITCHY: the race stiffens the rack to 100 because its steering is a velocity write and the
	  wheels are cosmetic; here the rack IS the steering, and 100 slams the wheels to where they are
	  told. `RackResponsiveness` 60: above the 45 that wobbles, below the snap.
	  BOUNCY: the stats are the race's, and the race's road is flat. `DampingScale` multiplies the
	  springs' damping (struts and torsion) on a lobby car only, so the kerbs and ramps of the city
	  settle in one bounce instead of three. The race is untouched. ]]
--[[ === KNOCKABLE GREENERY — 2026-10-14 ===
	A tester: "disable collisions on the bushes, or make it so you can drive them out of the ground,
	like zoo escape", and the owner: "and they respawn after a few seconds". So the lobby's bushes and
	trees are SCENERY A CAR GOES THROUGH: a lobby car never collides with one (it would stop dead on
	a hedge), and one met above `MinSpeed` is torn out of the ground and flung, then grows back where
	it stood after `Respawn` seconds. Players on foot still bump into them as before.
	`ServerScriptService/.../KnockableService` runs it, on the server so every player sees the same hedge
	fly. WHAT COUNTS: under the map (`PlotConfig.MapName`), any Model or Part whose name contains one
	of `Names` (case blind), or that carries the `Tag`; a thing bigger than `MaxSize` studs on its
	long side is left alone, so a building called "TreeHouse" does not take off. The server logs
	what it matched at boot, which is the list to prune. `Enabled = false`: the greenery solid and
	still, exactly as before. ]]
LobbyCarConfig.Knockables = {
	Enabled = true,
	Names = { "bush", "tree", "palm", "shrub", "plant", "hedge" },
	--[[ Rocks too (same day), but by EXACT name and only loose on the map: a "Small Rock" inside some
		other Model is a piece of that model's set dressing (a rockery, a plot's decor kit) and is
		left where it is. "Loose" means no Model between it and the map; folders do not count. ]]
	LooseNames = { "Small Rock", "Medium Rock" },
	Tag = "Knockable",
	MaxSize = 40,
	--- Studs per second a car must be doing to tear one out. Below it the car just passes through.
	MinSpeed = 18,
	--- The fling: the car's velocity times `Carry`, plus `Lift` studs/s straight up and a spin.
	Carry = 1.1,
	Lift = 28,
	Spin = 8,
	--- Seconds before it grows back, and how long it takes to fade back in.
	Respawn = 6,
	FadeIn = 0.5,
	--[[ === IT ONLY FLIES FOR A MOMENT — 2026-10-15 === ("bushes are missing parts or trees are
		missing leaves after they regenerate"). WAS: every piece loose for the whole `Respawn`, so a
		piece flung off the island's edge fell past `Workspace.FallenPartsDestroyHeight`, Roblox
		DESTROYED it, and the restore had nothing to put back. IS: loose for `Flight` seconds, faded out
		over `FadeOut`, then anchored where it is, invisible, until `Respawn`. It never falls far
		enough to be destroyed, and the lobby is not left littered meanwhile. `Flight` must stay
		well under `Respawn`. ]]
	Flight = 1.2,
	FadeOut = 0.4,
	--[[ Seconds AHEAD of the car the sweep reaches (`KnockableService._sweep`, 2026-10-15): a bush is
		knocked this long before the car gets there, so neither the car nor its driver, whose
		character still collides with greenery, ever meets a standing one. 0.25 at 60 studs/s is 15
		studs: well clear of the bumper, short enough that nothing goes flying with the car nowhere
		near it. ]]
	Lookahead = 0.25,
}

LobbyCarConfig.Handling = {
	Enabled = true,
	Stats = true,
	SteerRise = 0.12,
	SteerFall = 0.08,
	FullLockBelow = 0.3,
	HighSpeedLock = 0.45,
	RackResponsiveness = 60,
	DampingScale = 1.8,
	--[[ === RIDE HEIGHT — 2026-10-14 ===
		Aleafo: "fix car driving around lobby being glitchy; the suspension was too low, at least on
		the Jesko". Every car is stamped the same default springs (`CarConfig.Defaults`, 34000 front /
		32000 rear) whatever it weighs, so a heavy body sags further on them and, in the lobby, rides
		low enough to ground on the city's kerbs and ramps; the race's road is flat and never shows it.
		`StiffnessScale` multiplies the strut and torsion stiffness on every lobby car, and
		`StiffnessByBody` again on top for a body that still sits low (sag goes as weight / stiffness,
		so 1.3 takes about a quarter off it). Damping is scaled by the square root of the same factor
		on top of `DampingScale`, which keeps the damping ratio, so stiffer does not mean bouncier.
		Both at 1: the springs as before.

		BACK AT 1, SAME DAY: the owner, after a playtest, "car suspensions are completely broken now".
		1.3 everywhere and 1.69 on the Jesko are the values that were live when it broke; they stay
		here as the record of what was tried. Raise one body at a time, small steps, if the Jesko is
		still low. ]]
	StiffnessScale = 1, -- was 1.3
	--[[ THE JESTRA ALONE, 2026-10-15 (the owner: "when I drive the Jestra it messes up, the driving
		is super glitchy"). The broken playtest above had the global 1.3 AND the knockables matching
		"Street" (cars falling through road pieces) live at once, so which broke the suspension was
		never settled; this tries the stiffening on the one heavy body that was reported, alone. If
		it is still glitchy at 1.5, take this row out and test with `Drift.Enabled = false`: that
		says whether it is the car or the drift. ]]
	--- Back to none, same day: it did not help, and the real cause was found elsewhere (the cars'
	--- own wheels had stopped colliding with their bodies, `CarCollision`'s "A CAR MUST STILL MEET
	--- ITSELF"). Kept as a dial for a body that genuinely sits low.
	StiffnessByBody = {},

	--[[ === A COMPRESSION STOP — 2026-10-15 ===
		The owner: "a lot of the lower cars, the supercars, their suspension goes inside the car and
		makes it behave weirdly". Measured in Studio on the Jesko Attack and the Civic: every car is the
		SAME rig, and its four `StrutSpring`s have `LimitsEnabled = false`, so nothing stops a wheel
		rising except the wheel meeting the body, and a low body meets the kerb first. A hard landing or
		a drift loading one corner then drove the wheel up inside the body and flipped the car.
		So while a lobby car is driven, `LobbyDriveController._limitStruts` reads each strut's length
		at rest and switches its limits on with `MinLength = rest - Travel`: a wheel can rise `Travel`
		studs above where it sits and no further. Measured per car, so low and tall bodies both get a
		stop at their own ride height. `MaxSag` caps how far below its free length "rest" may be read,
		so a car entered mid-air (strut stretched) or nose-down cannot set a silly stop. `Enabled =
		false`: the struts unlimited, exactly as before. Travel is a taste value: lower is firmer over
		kerbs, higher is softer but closer to the old problem. ]]
	Struts = { Enabled = true, Travel = 0.7, MaxSag = 1.2 },
	RackSpeed = 8,
	RackForceScale = 4,
	LockScale = 0.85,

	--[[ === THE DRIFT — 2026-10-14 ===
		The owner: "the in-lobby car driving can be a lot better; are we able to add some sort of drift
		feature? when holding shift?". Held `Keys` above `MinSpeed` (studs/s along the nose):
		  `RearGrip`   the two rear wheels' friction is multiplied by this, so the back steps out.
		  `YawRate`    radians/s of turn the assist aims for at full steer, into the steer; `YawGain` is
		               how hard it pulls the car's spin toward that (per second). Low grip ALONE gives a
		               spin or a slow slither, never a drift you can hold — this is what makes it steer.
		  full lock    `_lockFor`'s high-speed trim is skipped while drifting: a drift is steered.
		  `Smoke`      tyre smoke off the rear wheels while it slides.
		Let go and the grip comes back on the next frame. Keyboard only for now: Shift is free in a
		lobby car (bound above Roblox's shift-lock so it cannot toggle that). `Enabled = false`: no drift. ]]
	Drift = {
		Enabled = true,
		--- Shift on a keyboard; L1 on a gamepad (2026-10-14: the stock car's pedals are the triggers).
		Keys = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL1 },
		--[[ The touch button, our own (2026-10-14). The first cut used ContextActionService's built-in
			one, which lives beside Roblox's jump button — and the stock car hides those controls when you
			sit, so it never showed. Held to drift. `Position` (screen share, centre) sits between the
			hotbar (to x ~0.58) and the car's down-arrow button (from x ~0.77), at the pedals' height,
			measured off a phone screenshot; `Height` is a share of the screen's height, `Aspect` w:h.

			=== IT STANDS ON THE HOTBAR NOW — 2026-10-16 ===
			WAS: centred at `Position` (0.70, 0.90). That screenshot had a short bar; a FULL touch bar is
			9 x 42 + 8 x 4 + 8 = 418px wide and centred, i.e. x 0.25-0.75 and the bottom 60px of an
			iPhone 14 (844 x 390) — the whole button, under a gui drawn at 960 over this one's 20. Phone
			players never saw it; an iPad's wider screen left it mostly peeking out past the bar's end.
			IS: `AboveHotbar` puts its bottom edge `Gap` px above the bar's row (pixels, read off
			`CarryConfig.Hotbar`), still at `Position.X`; `Position.Y` is only read with it off. Re-tune
			with `CarryConfig.Hotbar.TouchSize`/`Margin`, which the controller reads, never alone. ]]
		TouchButton = { Enabled = true, Title = "DRIFT", Position = Vector2.new(0.70, 0.90), Height = 0.11, Aspect = 1.6, AboveHotbar = true, Gap = 8 },
		--[[ SOFTER, SAME DAY (the owner: "a bit too sensitive"). WAS RearGrip 0.3, YawRate 2.4, YawGain 5
			and full lock in a drift. NOW the back keeps half its grip, the assist aims for a third less
			turn and pulls toward it less hard, and a drift steers at `Lock` of full rather than all of it. ]]
		MinSpeed = 20,
		--- Once drifting, it holds until the car is under this share of `MinSpeed`, so it cannot flicker
		--- off and on at the threshold (that restarted the sound several times a second).
		HoldShare = 0.5,
		--- Third pass, same day ("now too insensitive, very uninteresting"): between the two, nearer the
		--- first, since the first's twitchiness was partly the on/off flicker fixed with `HoldShare`.
		RearGrip = 0.38,
		YawRate = 2.1,
		YawGain = 4.2,
		Lock = 0.92,
		Smoke = true,

		--[[ === EVERYONE SEES IT — 2026-10-14 ===
			WHAT IT WAS: the smoke, the sound and the skid marks were built by the driver's client, so the
			driver alone had them. The owner: "everyone should be able to see/hear depending how close they
			are to the car". WHAT IT IS: the driver tells the server "drifting / not" on each CHANGE
			(`LobbyCarService` `ReportLobbyDrift`), the server stamps `Attribute` on the car, and every
			client draws the effects for every lobby car carrying it (`LobbyDriveController._effects`). The
			driver's own car still goes off its own local state, so it never waits a round trip.
			NOT server-built effects: a skid strip every `Skid.Step` studs per wheel is a replicated part
			~60 times a second per drifting player. Each client lays its own from the car's replicated
			wheels instead, which costs the network nothing. The physics (grip, yaw) stays the driver's. ]]
		Attribute = "LobbyDrifting",

		--- Looped while sliding, on the car (2026-10-14, the owner's pick). Heard by everyone nearby: full
		--- volume within `FullVolumeWithin` studs, fading to silent at `SilentBeyond`. `SoundId = 0`: silent.
		--[[ `Loop` (seconds into the clip): held, the drift plays the start once and then repeats this
			stretch (2026-10-14, the owner: the clip has ~1.5-2s of ending, so it should loop before it).
			Let go and it STOPS at once — it used to play on through that ending, which the owner found
			lingered ("keeps playing for a bit"). `Loop = nil` loops the whole clip instead. ]]
		Sound = { SoundId = 123957958078380, Volume = 0.6, Loop = { 1.5, 2 }, FullVolumeWithin = 15, SilentBeyond = 160 },

		--[[ SKID MARKS (2026-10-14, the polish pass): while drifting each rear wheel lays thin dark strips
			on the ground under it — a strip every `Step` studs travelled, `Width` wide, held `Hold` seconds
			then faded over `Fade`. Laid by every client under every drifting car (`Attribute`). `Max` strips at most in the world
			at once (oldest go first), so a long session cannot fill the map. `Enabled = false`: none. ]]
		Skid = {
			Enabled = true,
			Width = 0.55,
			Step = 0.6,
			Hold = 2.5,
			Fade = 1.5,
			Max = 400,
			Color = Color3.fromRGB(25, 25, 28),
			Transparency = 0.3,
		},
	},
}

--[[ === THE RACK, NOT THE INPUT — 2026-10-08 (third cut) ===
	"It starts off steering slow for like 0.5-1 sec, then it suddenly steers more." With the rig's own
	`Chassis`/`Driver` source in hand (`LobbyDriveController` header has the walk-through): the Driver
	passes the raw key with no ramp, the chassis CUBES it into the rack target, and the rack is a servo
	that creeps to that target against the tyres' scrub and then breaks free. NOW `LobbyDriveController`
	writes the target itself, LINEAR, every frame, and the servo gets:

	  RackSpeed       studs/s the rack may travel (raised to, never lowered). 8 crosses a ~0.95 rack in
	                  ~0.12s — inside the ease, so the ease is what you feel, not the servo.
	  RackForceScale  multiplier on the authored `ServoMaxForce`, so scrub at a standstill cannot stall
	                  it. 4 is a taste call; raise it if a parked car still creeps into a turn.
	  LockScale       share of the rig's full lock (`MaxSteer`, ~0.95 from `CarConfig` against the stock
	                  0.55) the lobby uses at all, so full lock is a tight turn and not a jack-knife.

	And with the cube gone the earlier numbers meant something else, so they moved with it:
	  SteerRise 0.07 -> 0.12, SteerFall 0.05 -> 0.08   an ease you can feel now that it is not cubed
	  HighSpeedLock 0.9 -> 0.45                       0.9 CUBED was 0.73 of lock; linear 0.45 is the
	                                                  "turns at speed but does not swap ends" middle
	  FullLockBelow 0.4 -> 0.3 ]]

return LobbyCarConfig
