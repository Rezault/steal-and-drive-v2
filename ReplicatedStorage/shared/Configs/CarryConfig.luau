--[[
	CarryConfig
	-----------
	THE CAR YOU GOT AWAY WITH IS IN YOUR HANDS, and where it stands is your decision. A banked run
	used to end with the car already on a podium: `GarageService.awardCar` took the first free bay,
	or swapped the worst one, and the player found out by walking round their own forecourt. It now
	ends with the car held in front of them, shrunk to something a person can carry, and a prompt on
	every bay of their own lot that parks it.

	=== WHY THE AUTOMATIC PARK WAS THE PROBLEM ================================================

	The complaint that produced this feature was not "the car went to the wrong bay". It was that a
	player could not tell they had been given anything. The car is the whole reward for the whole
	run, and the moment it landed, it landed somewhere behind them. A full lot was worse: the car
	went into the collection, which is a screen nobody had open.

	So the reward is put where it cannot be missed, and the last step of getting it is an action the
	player takes.

	=== THE THREE THINGS TO UNDERSTAND BEFORE TUNING ANY OF IT =================================

	1. CARRYING IS NOT OWNERSHIP, AND NOTHING IS AT RISK IN IT. `awardCar` puts the car in the
	   collection (`Garage.Owned`) exactly as it always did, BEFORE any of this is reached. What is
	   carried is a pending PLACEMENT, not the car itself. A player who never places it, who leaves
	   mid-carry, or who banks a second car on top of it has lost nothing: the car is theirs, it is
	   on the Cars Inventory screen, and it can be parked from there whenever they like. Read that
	   twice before adding any rule that "protects" a carried car, because there is nothing to
	   protect it from.

	2. ONE CAR IS CARRIED AT A TIME, AND THE NEW ONE WINS. Banking again while holding one replaces
	   what is in your hands. The alternative (a queue) would mean a player owing the game four
	   placement rituals before they can play, which is the feature turning into homework.

	3. IT IS PER SOURCE, AND ONLY THE BANK IS ON. `Sources` below is what decides, and a car that
	   does not carry parks itself exactly as it did before this file existed. Switching the whole
	   feature off with `Enabled` restores the old behaviour everywhere, including for a player who
	   is holding one at the time: nothing is lost by that, for the reason note 1 gives.

	The player-facing half is `CarryService` (the record, the model in the hands, the placement) and
	`CarryController` (the hint, and the glow on the bays you can put it on).

	=== THE BANK NO LONGER HANDS YOU THE CAR — 2026-09-28 =====================================

	WHAT IT WAS. `Sources.Bank` was on: every run ended with the car in the player's hands, and the
	carry was the step between a bank and a parked car.

	WHAT IT IS. Every car banked goes to the Cars Inventory and stays there (`GarageConfig.Banking`,
	same date). The carry is now something the player ASKS for: the CARRY button on a car in the
	inventory (`FromInventory`, removed 2026-09-30) put that car in their hands, and the podium prompt parks it
	exactly as it always did. Everything in the three notes above is still true of a carry; only
	what starts one changed.

	WHY. The dealership rework makes the lot a showroom the player curates, and most banks are no
	longer cars they want on a podium — a duplicate, a beater, something they mean to sell. Handing
	every one of them over as a placement ritual is the "feature turning into homework" note 2
	warned about, at the scale of every run.

	THE FIRST-CAR FUNNEL (`FirstCarService`) STILL COUNTS, BUT IT COUNTS SOMETHING NARROWER. `Carried`
	now latches the first time a player chooses to carry a car, not the first time they bank one, so
	its gap to `Placed` measures whether players who pick the carry finish it — not whether new
	players find their first car. The tutorial's PLACE beat teaches the podium picker instead.

	`Sources.Bank = true` puts the old flow back, exactly.

	=== AND IT DOES AGAIN, WITH A HOTBAR — 2026-09-28 (later the same day) ====================

	WHAT IT WAS. The block above: the bank went to the inventory, and a carry was only ever asked for.

	WHAT IT IS. The owner's reference is the inventory of a game in the same genre, and it works the
	other way round: a bank lands IN YOUR HANDS and in a one-slot HOTBAR at the bottom of the screen
	(`Hotbar` below, `CarryHotbarController`). Clicking the hotbar slot puts the car away into the
	inventory; clicking a car in the inventory and pressing PICK UP puts it
	back in your hands. So `Sources.Bank` is on again, and everything in the three numbered notes at
	the top is true once more — one car at a time, the new one wins, nothing is at risk.

	WHAT THE BLOCK ABOVE STILL GETS RIGHT: a car on a bay is not picked up, and the tutorial's PLACE
	beat is back to teaching the drop (`TutorialConfig`, the "place" beat).

	=== NINE SLOTS, AND THE HOTBAR IS A PLACE — 2026-09-30 ======================================

	The one-slot bar and the inventory's PICK UP button (`FromInventory`, now gone) were replaced by a
	nine-slot hotbar that is a real place a car lives, beside the bays and the inventory. The whole
	design is at `Hotbar` below. Of the numbered notes at the top, "one car at a time" still holds for
	the HANDS; what changed is that a bank now lands in a slot as well as in them.
]]

local CarryConfig = {}

--[[ Master switch. Off = `awardCar` parks everything itself, no model is ever built, no prompt ever
	changes its text, and the client draws nothing. It is the A/B: the question this feature exists
	to answer is whether players place their cars and keep playing, and the honest comparison is
	against the build that parked them automatically. ]]
CarryConfig.Enabled = true

--[[ WHICH WAYS OF GETTING A CAR HAND IT TO YOU, by the source name `GarageService.awardCar` is
	called with. A source that is missing or false parks the car the way it always did.

	    Bank   the getaway truck. The run's whole reward, and the case this was built for.
	    Pull   the random car product (`RandomCarService`). OFF, and not because it would not work:
	           that pull already has a moment of its own, a reveal panel that says PARKED IN BAY 3
	           over a sunburst. Turning it on means writing the carried outcome into
	           `RandomCarConfig` beside the other four lines, or that panel says nothing at all.
	    Buy    a car bought off a plaza stand (`CarDealService`). OFF, and this one is a design call
	           rather than a missing string: you drive that car away from the stand, so being handed
	           a toy copy of it at the same time reads as a bug.
	    Admin  a granted car (`AdminService`). OFF. A grant is a tool, and a tool that makes the
	           person holding it perform a placement ritual is a worse tool.
	    Seller a car bought off the seller at your own kerb (`SellerService`). ON since 2026-10-15,
	           the owner: "make it so the player equips it if they buy it". Unlike `Buy` there is
	           no real car to drive off in (the display car fades with the seller), so the car in
	           your hands IS the purchase arriving. Not passed with `SellerConfig.Sold.Handover`,
	           which seats you in the real car and so is `Buy`'s case. ]]
CarryConfig.Sources = {
	Bank = true, -- off for part of 2026-09-28, back on the same day; the header's last two blocks
	Pull = false,
	Buy = false,
	Admin = false,
	Seller = true,
}

--[[ THE HOTBAR: up to `Slots` cars kept at the bottom of the screen, drawn by `CarryHotbarController`.
	Roblox's own hotbar is down for good (`Hold.Tool.HideBackpack`); this one is ours because what a
	slot holds is a CAR the save knows about, not a Tool the engine does.

	=== IT IS A PLACE NOW, NOT A PICTURE OF YOUR HANDS — 2026-09-30 ============================

	WHAT IT WAS. One slot showing the car in your hands, and every car you owned that was not on a bay
	listed in the Cars Inventory — "the inventory" was simply everything else, by elimination, with a
	PICK UP button to get a car into your hands.

	WHAT IT IS (the owner's design, modelled on a reference game in the genre). Every car you own is in
	exactly ONE place, and the hotbar is one of them:

	    Bay / Workshop   standing on a podium (the lot entry)
	    Hotbar           one of your `Slots` hotbar cars (`ProfileKey`, an ordered list)
	    Inventory        stored — only because YOU put it there, or the hotbar was full

	  • A new car goes to the HOTBAR if there is a free slot, else to the inventory. A bank also puts it
	    in your hands (`Sources`), as it always has.
	  • Clicking a hotbar car HOLDS it, or puts it back down into its slot if it is the one held.
	  • With the Cars Inventory open, clicking a hotbar car MOVES it into the inventory, and a car's
	    TO HOTBAR button moves it back out — "Stored in Inventory <-> In Use / Hotbar with one click".
	    The caption `Text.MoveHint` says so over the bar while the inventory is open.
	  • A car taken off a bay (swapped out, or the bay cleared) goes back to the hotbar if there is room,
	    else the inventory — the bank's rule, so a car never vanishes into a list you did not choose.
	  • THE HELD CAR IS ALWAYS A HOTBAR CAR. `ProfileKey` above is still the car in your hands, and it
	    only ever names a car in this list; `GarageService.getCarriedCar` enforces it on read.

	Nothing is migrated on disk: a save written before this has an empty list, so every unparked car
	reads as Inventory — the one place it could honestly have been — except the car in the player's
	hands, which is folded into the hotbar on read (`GarageService._hotbarList`).

	`Enabled = false` draws no bar. The server rules stay, so it is a display switch, not a revert. ]]
CarryConfig.Hotbar = {
	Enabled = true,
	--[[ How many cars the hotbar holds. 9 is the owner's number, and it is also the keyboard's: one
		slot per digit key, the same count Roblox's own backpack bar shows. Moving it needs nothing
		else changed — the bar lays itself out from this — but a save that had more than a new, lower
		number keeps the first `Slots` and the rest read as Inventory. ]]
	Slots = 9,
	--- The profile key inside `Garage`, an ordered list of car IDs, slot 1 first. `GarageService` owns
	--- every write; `Data/Components/Settings` has the template entry.
	ProfileKey = "Hotbar",
	--- Broadcast onto the Player as the IDs comma-joined, slot order, for the bar and the inventory.
	Attribute = "CarHotbar",
	--[[ Where the bar sits: bottom centre. `Lift` is a share of the screen's height and `Margin` pixels
		on top of it, off the bottom edge.

		=== AT THE BOTTOM, UNDER PLAY — 2026-09-30 ==============================================
		WAS `Lift = 0.14`: the bar floated above the Play button, which owned the very bottom centre.
		The owner swapped them: the bar sits on the bottom edge and Play is moved up in Studio to stand
		on top of it (MainUIV2's Play, authored, not code — `RaceEntryController.PLAY_DROP` follows it,
		since it reads the button's home off the button). The MOVE IN / OUT caption still rides above
		the bar, which is now Play's spot: fine, because Play is suppressed whenever a page is open
		(`UIController`'s `SuppressPlayButton`), and the caption only shows with the inventory open.
		On a screen too short for Play's authored spot to clear these pixels, Play is lifted onto
		the bar at runtime (`RaceEntryController._playRest`). ]]
	Lift = 0,
	Margin = 10,
	--[[ One slot's size and the gap between two, in pixels — an icon, and an icon that grows with a
		monitor reads as zoomed. 64 because ten tiles (the backpack and nine cars) plus gaps is ~700px,
		which clears the HUD rail down the left on a 1280-wide screen; the single slot was 84. ]]
	Size = 64,
	Gap = 6,
	--[[ The same two on a phone or tablet, while `PreferredInput` is Touch (Leaf, 2026-10-06: "too
		large"). At 64 a full bar took ~700 of an iPhone 14's 844 points and ran under the movement
		stick; at 42 it is ~450, between the stick and the jump button. ]]
	TouchSize = 42,
	TouchGap = 4,
	--[[ Hidden while a menu is up (Leaf, 2026-10-06: it "interferes with world menu"), meaning any
		`UIController` page or the radio panel. Except these pages, where the bar is part of the screen:
		the Cars Inventory, where a click on a tile moves that car in or out. ]]
	ShowOverPages = { Dealership = true },
	--[[ Set true on a ScreenGui drawn ABOVE the bar that is only a notice (INVENTORY FULL), so the
		bar does not take it for a modal and refuse its own buttons. See `_modalUp`. ]]
	NoticeAttribute = "HotbarNotice",
	Text = {
		--- Over the bar while the Cars Inventory is open, because a click means something else then.
		MoveHint = "CLICK TO MOVE IN / OUT INVENTORY",
		--[[ The same caption on a controller, which cannot click a tile (2026-10-15). The bumpers pick
			the car in your hands as they always do, and Y moves THAT car in; its glyph is drawn beside
			these words. The second line is for a bar with cars on it and nothing held yet. ]]
		PadMoveHint = "MOVE THE CAR IN YOUR HANDS INTO INVENTORY",
		PadPickHint = "PICK A CAR WITH THE BUMPERS TO MOVE IT IN",
	},
	--[[ THE BACKPACK TILE (2026-09-30, the owner's ask): tile 1 of the bar, always there in the lobby,
		opening and closing the Cars Inventory — the other end of every "move in / out". It takes the
		1 key, so the cars sit on 2..9 and 0, Roblox's own backpack numbering for ten tiles. The image
		is the owner's upload, used as given. ]]
	BackpackImage = 91216847938226,
	--[[ Keys that do what the backpack tile does, besides its digit 1. Backquote is the key under Esc,
		Roblox's own backpack key, which players reach for out of habit (Aleafo, 2026-10-15). ]]
	BackpackKeys = { Enum.KeyCode.Backquote },
}

--[[ Does a car from this source go into the player's hands?

	Nil and unknown source names answer false, which is what keeps every existing caller of
	`awardCar` on the behaviour it had: only a caller that names itself can opt in. ]]
function CarryConfig.carries(source: unknown): boolean
	if not CarryConfig.Enabled then
		return false
	end
	return type(source) == "string" and CarryConfig.Sources[source] == true
end

-- === Where it is stored =====================================================

--[[ The profile key, inside the `Garage` table `GarageService` owns every read and write of. It
	holds ONE CAR KEY ("Camaro:6", "Camaro:6:Charged") or the empty string for empty hands.

	IT LIVES IN THIS FILE RATHER THAN IN `GarageConfig.Keys` for the reason `UpgradeConfig.ProfileKey`
	does: what the key MEANS is decided here, and a key name written in two configs is a key name
	that eventually disagrees with itself. `GarageConfig.Keys` has a note pointing at this line, and
	`Data/Components/Settings` has the template entry.

	A CAR KEY AND NOT A RECORD, because a key is everything about which car this is (body, colour and
	mutation, see `GarageConfig.carKey`) and nothing about where it stands or what it has earned. The
	tier comes off `GarageConfig.TierOfBody` and the `Collected` stamp starts when it is parked, both
	of which is what makes a placed car indistinguishable from a car that reached a bay any other
	way. ]]
CarryConfig.ProfileKey = "Carrying"

--[[ Broadcast onto the Player, so the client can draw the hint and light up the bays with no remote
	and no round trip. The same bargain `GarageConfig.CashAttribute` makes, and it replicates to
	every client on purpose: a visitor can see that the person stood next to them is holding a car
	they have not parked yet, which is the small social half of this.

	It is the CAR KEY, so a client that wants to say WHICH car is in somebody's hands already has it,
	and the empty string means empty hands. ]]
CarryConfig.Attribute = "CarryingCar"

-- === The car in your hands ==================================================
--[[ A stripped display car (`Modules/CarDisplay`), scaled down and welded to the character. It is
	the same clone the podiums and the plaza stands use, so a carried car is the car the player is
	about to park, in its own colour, down to the number plate.

	IT IS BUILT ON THE SERVER, and it has to be: the roster is relocated into ServerStorage as the
	server boots, so a client has nothing to clone. It replicates like any other model, which is what
	makes it visible to everyone rather than only to the person holding it. ]]
CarryConfig.Hold = {
	--- What the model is called under the character. Fixed, so a rebuild can find and destroy the
	--- last one rather than leaving two cars in one pair of hands.
	ModelName = "CarriedCar",

	--[[ === THE CAR WAITS UNTIL YOU ARE HOME — 2026-09-30 =====================================

		WHAT IT WAS: a banked car was built and equipped on `RaceService.RaceLeft`, which fires while
		the trip home is still running — the rider still leaving the seat of a car about to be
		destroyed, then anchored whole, teleported across the map and unanchored by the server.

		WHY THAT HAD TO GO: the dead-bay-prompt trace (`GarageConfig.Picker.DebugPrompts`) caught the
		SERVER's copy of the character pinned on the spawn pad for the rest of the session while the
		client walked freely — same parts, nothing anchored, the player still the network owner on
		both sides — so every podium prompt measured the player as ~49 studs away and dropped the
		press. It always began at the landing and always with a banked car in hand. Welding sixty-odd
		parts onto a character in the middle of the server's freeze-teleport-release is the one thing
		that happened at that moment and nowhere else.

		WHAT IT IS: the car reaches the hands on `RaceService.ReturnedHome`, once the beat has let go.
		It costs the car appearing a fraction of a second later, behind the results screen anyway.
		False puts the old timing back, exactly — the honest A/B for whether this was the cause. ]]
	AfterReturn = true,

	--[[ THE PART IT HANGS OFF on the weld path, which is the path `Tool.Enabled` below turns off.

		A car welded to `RightHand` with no animation playing sits wherever the idle pose leaves that
		hand: down by the thigh, where it clips the leg on every step. The root part is the one part
		of a character whose pose is the character's own facing, so a car hung off it holds its place
		beside the shoulder at any animation, on any avatar.

		Which is exactly why it looked like a car floating next to somebody rather than a car being
		carried, and why the tool below exists. This is what is left if that is switched off. ]]
	PartName = "HumanoidRootPart",

	--[[ === HELD AS A TOOL, WHICH IS WHAT PLAYS THE POSE ====================================

		A `Tool` with the car's hub as its `Handle`, equipped on the character. Roblox's own `Animate`
		script plays its tool animation for as long as anything is equipped, which raises the arm and
		holds it out, and the engine welds the handle into the hand: the car is in a hand that is
		posed to be holding something, on every rig, with no animation of ours to load, keep playing
		or stop.

		OFF PUTS THE CAR BACK BESIDE THE SHOULDER on `PartName` above, with `Offset` and `Yaw`, which
		is what this feature shipped with. Nothing else changes.

		WHAT A TOOL BRINGS WITH IT, and what is done about each:

		  • A HOTBAR SLOT. `HideBackpack` takes Roblox's backpack UI down for good on the client.
		    This game has no other tools, so there is nothing else in it to lose, and the slot would
		    land on the Play button.
		  • UNEQUIPPING, by the hotbar keys or by dropping. `CanBeDropped` is false and `CarryService`
		    puts it straight back on any `Unequipped`, so the car cannot be taken off by accident.
		  • ACTIVATION, the click. `Enabled` false and `ManualActivationOnly` make the tool inert: it
		    is a thing being held, not a thing to use.
		  • DEATH. Roblox moves an equipped tool back to the backpack when a character dies, so the
		    one in there is last life's. `_refresh` sees a model that is not under the new character
		    and rebuilds, which is the same path a respawn already took. ]]
	Tool = {
		Enabled = true,
		HideBackpack = true,

		--[[ WHERE THE CAR SITS, in the CHARACTER's own frame rather than the hand's: studs right, up
			and forward of the root, of the plane the car's wheels stand on. Local -Z is forward.

			THIS IS NOT WHAT THE ENGINE WANTS, and that is the point. `Tool.Grip` is measured from
			the hand's grip point, and the hand's pose is whatever the tool animation is holding it
			at, so a grip written by hand is inside out and measured from a moving thing. Nobody can
			read one and say where the car will be. `CarryConfig.toolGrip` below turns these two
			numbers into that grip, so what is written here is the answer rather than the working.

			1.6 right, 0.55 up, 2.1 forward is the end of the outstretched arm with the wheels just
			over the palm, and the car tucked against the forearm rather than floating clear of it.

			IT WENT OUT TO 1.95 AND CAME BACK, which is worth knowing before moving it again. 1.95
			was chosen against a nose-forward car (`Yaw` 0), where the body runs straight away from
			the camera and most of its length hides behind the player's own hair, so it had to be
			pushed out to be seen at all. At the 30 degrees `Yaw` settled on, the car's mass swings
			clear on its own and only the nose passes behind the head, so the extra reach bought
			nothing and cost the read of a thing being HELD rather than floating beside somebody.
			Dylan asked for it back in on 18 Sep 2026, looking at the top down lobby camera, which is
			the view the gap was plainest in. ]]
		Pose = CFrame.new(1.6, 0.55, -2.1),

		--[[ Degrees the car is turned about its own vertical, so 0 is NOSE FORWARD: the car points
			the way its owner is walking, which is the way a person carries a thing.

			30 IS THAT, TURNED FAR ENOUGH OFF SQUARE TO READ AS A CAR. Dead ahead is the one angle
			that shows the owner nothing, because their camera is behind their own back and a car
			pointing directly away from it is three and a half studs of bumper: photographed at 0,
			and the car was a sliver beside the head. 30 keeps it facing forward and gives the rear
			three quarter, so the roof, one flank, the lights and the plate are all in shot.

			IT USED TO BE 200, which pointed the nose back at the camera. That is a better photograph
			of a car and a worse picture of somebody carrying one, which is what this is. ]]
		Yaw = 30,

		--[[ THE HAND, WHILE THE TOOL ANIMATION IS HOLDING IT: `RightHand` in the root's own frame,
			measured in game rather than derived, because it belongs to Roblox's tool-hold animation
			and not to anything in this repository.

			IT IS WHAT MAKES `Pose` AND `Yaw` MEAN ANYTHING. The engine's weld is
			`Handle.CFrame = hand * RightGrip.C0 * Grip:Inverse()`, so going from a pose in the
			character's frame to a grip in the hand's needs to know where the hand is, and the hand
			is only in that place once the animation has blended in. A grip cannot be solved live at
			equip time for exactly that reason: the arm is still on its way up.

			MEASURED 18 Sep 2026, R15, idle, averaged over 24 samples to take the breathing out. It
			moves by well under a degree across the idle cycle. Re-measure it if a car in the hands
			ever looks tilted rather than misplaced, since that is the one symptom of this being
			stale, with a car in your hands in a playtest:

			    local rel = character.HumanoidRootPart.CFrame:Inverse() * character.RightHand.CFrame
			    print(rel:GetComponents())

			AN AVATAR THAT IS NOT DEFAULT SIZED DOES NOT NEED IT RE-MEASURED. The grip this solves
			into is hand-relative, so the car sits in the same place in the same hand whoever is
			holding it; a taller player's hand is simply further from their own root than the number
			above says, and the car goes with the hand, which is the half that matters. ]]
		HandAtRest = CFrame.new(
			1.409215,
			0.536249,
			-1.775345,
			0.997821,
			0.063509,
			-0.017858,
			-0.016038,
			-0.029053,
			-0.999449,
			-0.063993,
			0.997558,
			-0.027971
		),

		--[[ The hand's own grip point, used only when the character has no `RightGripAttachment` to
			read it off. R15's, measured from the same character, and the engine's `RightGrip.C0` is
			that attachment's CFrame exactly. R6 puts a differently posed one on `Right Arm`, which
			is why the live read is preferred and this is the floor rather than the value. ]]
		HandGripC0 = CFrame.new(0, -0.15, 0) * CFrame.Angles(-math.pi / 2, 0, 0),
	},

	--[[ How far down the car is scaled: a big toy against a five stud character, which is exactly the
		read the design conversation asked for.

		Much smaller and the body stops being recognisable, which defeats the point of showing the
		real car rather than an icon. Much larger and the player cannot see past their own reward.

		MEASURED RATHER THAN GUESSED. A roster body is about 20 studs long and 9.8 wide (the showroom
		decks are 12.7 x 24.6 and a car has a stud and a half of margin a side), so the 0.22 this was
		first written with produced a 4.65 stud car: longer than the character is wide and closer to
		furniture than to a toy. 0.17 measures 3.6 x 1.5 x 1.1, which reads as something a person
		could pick up. ]]
	Scale = 0.17,

	--[[ Where it sits, in the anchor part's own frame: 1.7 studs to the RIGHT, a little up, a little
		forward. Local -Z is the direction the character faces and +X is their right.

		OUT TO THE SIDE, AND THAT IS THE ONE PLACEMENT THE OWNER CAN SEE. Held in front of the chest
		(0, 1.05, -1.7, which is what this was) the car is perfectly visible to everybody else and
		completely hidden from the person holding it, because their own camera sits behind their own
		back: photographed, and the car did not appear on screen at all. Beside the shoulder it clears
		the body from behind, and it is still in front of the player at every other angle.

		THE CAR'S WHEELS SIT ON THIS PLANE rather than its middle being centred on it, so raising `Y`
		raises the car by exactly that much whatever body is in the hands. Bodies differ by nearly a
		stud in height, and centring would make a truck ride higher than a hatchback. ]]
	Offset = CFrame.new(1.7, 0.45, -0.6),

	--[[ Degrees the car is turned about its own vertical, after the offset.

		180 would point its nose straight back at the person holding it, which is the view that
		matters (your own camera is behind your character, and this is your car). 160 is that, turned
		far enough off square to read as a car rather than as a grille: a three quarter view, which is
		the angle every showroom in this game already uses for the same reason. ]]
	Yaw = 160,

	--- Shadows off. It is one small model that is always moving and always near the camera, and the
	--- roster's bodies are authored with shadows off anyway.
	CastShadow = false,

	--[[ Dress a mutated car as mutated (`Modules/CarMutation`)? OFF, and it is the one piece of the
		car's identity this model deliberately does not show.

		A mutation is a skin AND a particle layer, and particles do not scale: `WeatherConfig`'s
		flames and sparks are authored in studs for a ten stud car, so a Molten car at 0.22 is a two
		stud toy inside a full sized bonfire, held at chest height, on the client of everybody stood
		near them. The skin alone would be worth having and there is no call that applies one without
		the other today. The car on the podium is dressed correctly the moment it is placed. ]]
	Mutation = false,
	--[[ === THE SKIN, WITHOUT THE PARTICLES — 2026-10-14 ===
		The owner: "when I hold a ghost car, it's not ghost". The skin was only held back because no
		call applied it without the particles; `CarMutation.apply` now takes `skinOnly`. So the held
		car wears its mutation's skin (ghost, rust, molten...) and outline, and none of the
		full-size particles `Mutation` above warns about. `MutationSkin = false`: a plain car in the
		hands, as before. `Mutation = true` still means the whole look, particles included. ]]
	MutationSkin = true,
}

--[[ `Tool.Pose` and `Tool.Yaw`, turned into the `Tool.Grip` the engine actually welds by.

	The engine holds a tool with `Handle.CFrame = hand * RightGrip.C0 * Grip:Inverse()`, and the
	`C0` in that is the hand's `RightGripAttachment`. Rearranged for the grip that lands the handle
	at a pose in the CHARACTER's frame, with the hand where the tool animation holds it:

	    Grip = (HandAtRest:Inverse() * want):Inverse() * C0

	`gripC0` is that attachment read off the live hand, which is the honest source and is readable
	BEFORE the tool is equipped, so the car arrives where it belongs rather than being moved there a
	frame later in front of everybody. Nil falls back to `Tool.HandGripC0`. ]]
function CarryConfig.toolGrip(gripC0: CFrame?): CFrame
	local tool = CarryConfig.Hold.Tool
	local want = tool.Pose * CFrame.Angles(0, math.rad(tool.Yaw), 0)
	return (tool.HandAtRest:Inverse() * want):Inverse() * (gripC0 or tool.HandGripC0)
end

-- === Placing it =============================================================
--[[ THE BAY PROMPT IS THE ONLY WAY IN, which is the decision `CarDealService` documents for buying:
	the engine only fires a `ProximityPrompt` for a player who is really standing at that podium, and
	it already carries who pressed it. There is no client to server message here at all, so there is
	no request shape to validate and no way to park a car onto a lot you are not standing on.

	It is the SAME prompt the picker screen opens from, re-lettered while your hands are full, rather
	than a second prompt on the same part. Two prompts sharing one key on one podium is the exact
	failure `LobbyCarService._wireEntry` measured on the car doors: the engine draws one of them and
	does not pick the nearest.

	WHICH MAKES `GarageConfig.Picker.Enabled` A REQUIREMENT AND NOT A NEIGHBOUR. With the picker off
	there is no prompt on a podium to re-letter, and `setBayCar` (which a placement IS) refuses
	everything, so a carried car would have nowhere to go. Switch this feature off before that one. ]]
CarryConfig.Prompt = {
	--- What the podium prompt says while you are holding a car. `GarageConfig.Picker.PromptActionText`
	--- is what it goes back to saying.
	ActionText = "Place Car",

	--[[ Seconds between one player's placements. The same shape and the same reason as
		`GarageConfig.Picker.Cooldown`: a placement rebuilds a lot, which clones a car body per bay,
		so a held prompt is real server work. ]]
	Cooldown = 0.35,
}

-- === What the player is told ================================================
--[[ THE HINT. A toast at the top of the screen, for as long as it takes to read twice.

	ON THE NEW UI IT IS THE KIT'S CARD, cut from the same `PromptUI` the weather notice is cut from
	(`BuildCarryNoticeV2`, `MainUIV2.Screens.CarryNotice`) and shown the same way: it slides down from
	above the screen, holds, and slides back. The values under `Kit` below are that card's; everything
	from `CentreY` to `FadeOut` belongs to the shipping card, which is what a place with the flag off,
	or with no template built, still draws. The copy and the clock are shared, so there is one place
	to change what it says and how long it says it for.

	TOP CENTRE IS THE ONE FREE BAND. The tutorial's objective card owns the top left, the near miss
	toast the upper middle of a run, the Play button the bottom centre, and the kit's rails both
	sides. This sits above all of it and over nothing.

	IT IS RAISED WHEN THE SCREEN HAS GONE, not when the run ends. `RaceConfig.ReturnedEvent` is the
	last frame of the results fade, which is the first moment the player is stood on their own island
	able to see the car in their hands. `RaceEnd` lands five seconds earlier, at the top of the
	results hold, and a card raised there spends its whole life behind them.

	IT GOES AWAY ON ITS OWN AND THE CAR DOES NOT. A hint that stayed up until the car was placed
	would be a hint the player is being nagged by, and the car in their hands is already the
	reminder: it is in shot at all times, in the middle of the screen, attached to them. ]]
CarryConfig.Hint = {
	Enabled = true,

	--[[ Stay down while the tutorial is unfinished (2026-10-06, Leaf: "information overload and
		overlapping"). On the PLACE beat this card, the tutorial's chip ("PARK YOUR NEW CAR") and the
		tutorial's card all said the same thing at once. The tutorial is the one that knows what comes
		next, so it keeps the screen. Off = the card is raised during the tutorial as before. ]]
	YieldToTutorial = true,

	--[[ Only until the profile has parked a car (2026-10-13, Aleafo: "we do not need this popup more
		then once"). The card was raised for every car banked and every car lifted off a bay, which is
		twenty readings of a sentence that teaches nothing after the first. Gated on the saved
		`FirstCar.Placed` latch (`Guide.ParkedBeforeAttribute`), so it stays gone across rejoins. The
		guide's own faces (Parked, Customize) are once-per-profile already and are not touched by this.
		Off = the card is raised for every car, as before. ]]
	FirstTimeOnly = true,

	Title = "YOUR NEW CAR",
	--- The same heading in the kit's own case. The Cartoony Kit sets its headings in title case
	--- ("Settings", "Prompt Request"), and a shouted one on its cap reads as a different pack.
	KitTitle = "Your New Car",
	--- No key is named on purpose. The prompt on the bay draws the right button for the device being
	--- held, and a line that said "press E" is wrong on two of the three.
	Text = "Park it in a bay on your lot",

	--[[ Does the kit card name the car ("RED CAMARO", `GarageConfig.carName`)? The shipping card has
		no row for it and ignores this.

		ON, because the card is announcing a prize and the prize has a name. The player is looking at
		the car as they read it, so the line is not carrying the information on its own: it is what
		turns "a car" into "that car", which is the whole difference between a reward and a chore. ]]
	CarName = true,

	--[[ Seconds after the results screen has finished lifting before the card slides in.

		A BEAT RATHER THAN A FRAME. The lobby re-streams around the player as they land (the island's
		instances arrive under the results beat), and a card that starts moving on the same frame the
		screen goes is a card whose slide can stutter. It is also simply better staging: the player
		gets to see their own character holding a car, and then gets told about it. ]]
	Delay = 0.4,

	--[[ How long after a run ends to give up waiting for that screen and raise the card anyway.

		A FENCE, NOT A TIMER. Every way home goes through the results screen, and that screen drops
		itself after twelve seconds whatever else happens (`RaceUIController`'s safety timeout), so
		nothing should ever reach this. What it buys is the failure being a late hint rather than no
		hint at all: a run that somehow ends with no screen up publishes nothing to wait for, and the
		car in the player's hands would otherwise never be explained. ]]
	Fallback = 14,

	--- Fractions of the screen, so the card is the same shape on a phone and on a monitor.
	CentreY = 0.09,
	Size = Vector2.new(0.3, 0.1),

	--- The kit's navy panel and border, at the weight the driving HUD's cards wear them.
	PanelColor = Color3.fromRGB(20, 27, 45),
	PanelTransparency = 0.35,
	StrokeColor = Color3.fromRGB(12, 18, 34),
	StrokeThickness = 2,
	--- As a fraction of the card's own height, so it is one curve at every viewport.
	CornerRadius = 0.3,

	TitleColor = Color3.fromRGB(255, 198, 0), -- the kit's PLAY gold: the thing you are meant to do
	TextColor = Color3.fromRGB(238, 242, 255),

	--- Seconds it stands before fading. Long enough to read twice at a walk, short enough that a
	--- player who already knows the drill is not reading it for the twentieth time.
	Seconds = 9,
	FadeIn = 0.25,
	FadeOut = 0.5,

	--[[ THE KIT CARD (the new UI). The art is authored rather than built: `BuildCarryNoticeV2` cuts
		it out of the kit's `PromptUI` onto the hidden `MainUIV2.Screens` shelf, and the controller
		clones it. Nothing here is a colour, because none of it is ours to pick: the panel, the cap
		and the type are the kit's own.

		THE SAME NUMBERS AS THE WEATHER NOTICE, which is the other toast on this shelf and sits in
		the same band. Two toasts that arrive at different speeds from different heights read as two
		different games, and they can be on screen together: an event starting in the world a player
		just came home from lands in the same few seconds as this. ]]
	Kit = {
		--- Where its top edge rests, as a fraction of the viewport, so the margin grows with the
		--- screen. The kit's space has the topbar taken out already, so 0 is under it.
		ShownY = 0.022,
		SlideIn = 0.4,
		SlideOut = 0.35,
	},
}

--[[ THE GLOW ON THE BAYS YOU CAN USE. A `Highlight` on the deck of every empty podium on your own
	lot, and nothing else: no arrows, no beams, no floating words. (The line from the player to the
	nearest of these decks is `GuideTrailConfig`'s, added 2026-10-16 when the funnel showed 44% of
	first cars never reaching one. It ends where this glow is, in the same gold.)

	EMPTY ONES ONLY, BY DEFAULT. Every bay accepts a car, and placing onto a full one swaps the car
	that was there back into the collection, which is a perfectly good thing to do and is what a
	player does once their lot fills up. But lighting all six teaches nothing on the run that matters
	most, which is the first one, where five of them are empty and the only question is "where does
	this go". Turn `OccupiedToo` on once a full lot is the common case.

	IT IS DRAWN CLIENT SIDE, per player, which is why there is no budget problem: the ~31 highlight
	ceiling is per client, and a client only ever lights its OWN lot. ]]
CarryConfig.Glow = {
	Enabled = true,

	--[[ The kit's PLAY gold (#FFC600), not its blue.

		Blue is what "you can press this" is painted in everywhere else in this game, and it was the
		first choice here for exactly that reason. It is the wrong choice in this one place: a plot is
		blue, its floor is blue, its podiums are blue, and a blue wash over a blue deck was measured
		on screen as barely telling the lit bays from the unlit ones. Gold is the same colour the
		hint's own title wears and the same one the Play button wears, which is this palette's word
		for the thing you are meant to do next. ]]
	Color = Color3.fromRGB(255, 198, 0),
	FillTransparency = 0.82,
	OutlineTransparency = 0.05,

	OccupiedToo = false,

	--- Only drawn within this many studs of the bay. A lot glowing from across the plaza is signage;
	--- the point is to answer the question at the moment it is asked, which is when you arrive.
	Studs = 90,

	--- Seconds between distance checks. A walking player covers about four studs in that time, and
	--- the threshold is ninety.
	Interval = 0.25,

	--[[ The breath. The fill alone moves, by this much, over this period, and the outline is left
		alone: a pulsing outline reads as a warning, while a deck that gently fills and empties reads
		as a place to put something. Set `Pulse` to 0 for a flat glow. ]]
	Pulse = 0.1,
	PulsePeriod = 1.6,
}

-- === The first one ==========================================================
--[[ THE WALKTHROUGH FOR A PLAYER'S FIRST CAR, and it runs once in a profile's life.

	Everything above this line assumes somebody who knows what a bay is. The first time is the one
	time that is not true. The run has just ended, there is a car in their hands they did not ask
	for, and there are three things to work out: where their own lot is, that a car goes on a
	podium, and that a parked car is the thing that pays them. The hint answers the middle one, for
	nine seconds, and then goes away.

	WHAT THE GUIDE ADDS IS THREE THINGS, AND NONE OF THEM IS A SECOND TUTORIAL:

	  1. The card wears first-time copy and stands for longer. The same card, in the same band,
	     with the same slide: a first-timer gets a better sentence, not a different screen.
	  2. The pin over their own lot keeps pointing at it until the bays are close enough to glow,
	     instead of switching off while they are still a plaza away. That half is
	     `PlotConfig.Marker.Carry` and it is on for EVERY carry, because a waypoint is not a lesson
	     and nobody outgrows one.
	  3. A card once the car is finally down, saying the thing this game has never said out loud:
	     a parked car earns while it sits, and the mat in front of it is how you take the money.

	IT HAS NO ARROW OF ITS OWN, and the tutorial's `place` beat already wrote the reason down: every
	empty bay on the lot is lit while a car is in your hands, and a lot the player chooses from is a
	better instruction than one bay with a chip nailed over it. The guide does not second-guess that.
	(Every carry now draws a line to the nearest of those bays, `GuideTrailConfig`, 2026-10-16. It is
	the carry's, not this walkthrough's, and it re-picks as the player walks, so the choice stands.)

	IT STANDS DOWN FOR THE TUTORIAL. A player on the `place` beat has an objective card up saying
	the same sentence in the same seconds, and two cards saying one thing is worse than either of
	them on its own. `FirstCarService` is what decides, and it decides by simply not publishing the
	attribute. The funnel is counted either way, because what the funnel is asking about is every
	player's first car rather than this card. ]]
CarryConfig.Guide = {
	--- Off = the attribute is never published, the card keeps its ordinary face, and no follow-up is
	--- ever raised. The funnel is a separate switch in `FirstCarService`, so the measurement survives
	--- the copy being pulled and the copy survives the measurement being pulled.
	Enabled = true,

	--[[ Where the profile remembers, as a TOP-LEVEL key for the reason `Tutorial` is one:
		`PlayerProfile`'s string path is a recursive key search, and a key nested inside `Garage`
		would be reachable only by array path.

		    { Carried = true, Placed = true }

		TWO BOOLEANS AND NOT ONE, because the gap between them is the whole measurement. `Carried`
		is "a car has been in this player's hands at least once" and `Placed` is "and they put one
		on a bay". A profile with the first and not the second is a player the reward flow lost,
		which is exactly the question `CarryConfig.Enabled` says this feature exists to answer.

		They are also what makes the funnel once-per-PROFILE rather than once-per-session. Analytics
		dedupes per session (`AnalyticsService.DesignOnce`), so without these a player who rejoined
		still holding their first car would report reaching step one twice.

		Absent is a player who has never had a car, which is the right answer for every profile
		written before this existed: the guide is offered once to everybody, including the people
		who were here first. ]]
	ProfileKey = "FirstCar",

	--[[ Broadcast onto the Player, the same bargain `CarryConfig.Attribute` makes and for the same
		reason: the client draws the card off an attribute, with no remote and no round trip.

		A STRING AND NOT A BOOLEAN, because there are three states and the middle one is not "on":

		    ""          nothing to say. Not a first car, or the tutorial is saying it instead.
		    "Carrying"  their first car is in their hands and the card wears its first-time face.
		    "Parked"    they have just put it down, which is when the follow-up is raised.

		The server clears `Parked` after `ParkedHold`, so the client holds no state of its own and a
		rejoin cannot replay a card that has already been read. ]]
	Attribute = "CarryGuide",
	Carrying = "Carrying",
	Parked = "Parked",

	--[[ THE FIRST CAR PARKS ITSELF (2026-10-19). The `FirstCar` funnel showed 31.6% of players who got
		their first car into their hands never put it on a podium: the results screen, the NEW BEST
		cutscene, then a walk across the island holding a car, right after the best moment of the
		session. So the first car ever banked goes straight onto the lowest free showroom podium
		(`FirstCarService._autoPark`), through the same `GarageService.placeCarried` a press would
		use, and the player comes home to it already standing there; the `Parked` card says what it
		is for. The carry is still taught, by the second car, when there is something to care about.

		A FULL LOT (only possible on a profile that sold everything) falls back to the carry as
		before. `false`: the walkthrough exactly as it was, card and all. ]]
	--- 2026-10-19: OFF (Aleafo: "players should learn to press and place it down, it's a movement taught
	--- in other games with the format"). The carry-and-place beat teaches it again.
	AutoParkFirst = false,
	--[[ ...AND THE PLAYER COMES HOME TO IT (2026-10-19). A run returns everybody to their lot's spawn
		pad, which left a first-timer at the gate while their car and the tutorial's first buyer were
		at a podium across the showroom. So the trip home after the auto-park ends in front of that
		podium instead, facing the car (`FirstCarService._standAtCar`), this many studs out from the
		podium's FRONT EDGE along the aisle it faces (`GarageService` Bay `base`), and `AutoParkSide`
		studs to their LEFT as they face it (negative: right). Off to the side because the tutorial's
		buyer stands square in front of the car (`BuyerConfig.Stand.Front`): straight out, the player
		landed in the buyer (2026-10-19, "make me stand like over there", at the podium's front left
		corner). Once only, for that one homecoming. `AutoParkStand` 0 or nil: home to the spawn pad
		as before. ]]
	AutoParkStand = 6,
	AutoParkSide = 9,

	--- A boolean on the Player mirroring the profile's `Placed` latch: true once any car of theirs has
	--- reached a bay. Published whether or not the guide is on, because `Hint.FirstTimeOnly` reads it.
	ParkedBeforeAttribute = "FirstCarParked",

	--[[ THE FIRST CARD. Same geometry, same colours and same clock shape as `Hint` above; only the
		words and the length change.

		IT NAMES THE LOT AND NOT THE BAY. "Your lot" is a place they can walk towards from anywhere
		on the island; "a glowing bay" is only true once they are near enough for one to be glowing,
		which is the state this card is usually NOT raised in. The glow is what says which bay, at
		the moment there is a bay to say it about. ]]
	Title = "YOUR FIRST CAR",
	--- Title case on the kit's cap, for `Hint.KitTitle`'s reason: the pack sets its headings that
	--- way and a shouted one reads as a different pack bolted on.
	KitTitle = "Your First Car",
	Text = "Carry it back to your lot and park it",

	--[[ AND IT FITS ON ONE ROW, which is a measurement rather than a preference. The kit card's body
		label is capped by a `UITextSizeConstraint` (see `KitPage.scaleTextCaps`), so a line too long
		for the row does not shrink gracefully: it WRAPS, and both halves come back at half the size.
		Measured on the live card at 1080p, the break is at about 38 characters. Every string in this
		table is under it, and a longer one should be re-written rather than squeezed. ]]

	--[[ Seconds it stands, against the nine an ordinary carry gets.

		LONG ENOUGH TO BE READ WHILE WALKING, which is what a first-timer is doing: the ordinary
		hint is read by somebody who already knows what it is going to say and is checking which car
		they got. This one is the instruction, and the walk from where the results screen drops a
		player to their own forecourt is most of it. ]]
	Seconds = 15,

	--[[ THE SECOND CARD, raised when the first car is finally standing on a podium.

		IT IS THE ONLY PLACE OUTSIDE THE TUTORIAL THAT SAYS WHAT A PARKED CAR IS FOR. Everything up
		to here has taught a player to collect cars; nothing has told them that the lot is the
		income and the mat is the till. A player who parks their first car and walks away has done
		the last step of the reward and not been paid for it.

		IT DOES NOT NAME THE CAR. The name row belongs to the card that is announcing a prize, and
		by now the prize is behind them on a podium they are looking at. ]]
	ParkedTitle = "PARKED",
	KitParkedTitle = "Parked",
	ParkedText = "Customers admire it and tip you while it sits on your lot",
	ParkedSeconds = 11,

	--[[ Seconds after the car lands on the podium before the card slides in.

		THE PLACEMENT HAS ITS OWN MOMENT FIRST. Putting the car down rebuilds the lot and drops a
		full-size car onto the deck in front of the player, and a card sliding over the top of that
		is a card competing with the thing it is congratulating them for. ]]
	ParkedDelay = 1.2,

	--[[ How long the server leaves `Parked` published before clearing it back to "".

		IT HAS TO OUTLAST THE CARD, and by enough that a slow client still gets the whole of it:
		`ParkedDelay` plus `ParkedSeconds` plus the slide either side is about 13 seconds, so this
		is that with room. Cleared rather than left standing so that nothing in the game is still
		reading "this player just parked their first car" ten minutes later. ]]
	ParkedHold = 18,

	--[[ THE CUSTOMIZE POINTER (2026-10-06, Leaf: show customization "after second car is stolen").
		Nothing in the tutorial teaches the workshop, and the first car is kept off it on purpose (the
		PLACE beat sends it to a showroom bay, where it earns). So the next car banked after that, once
		the tutorial is done, comes home with this face on the card, a gold glow on the CUSTOMIZE
		podium's deck and a chip over it. Once per profile (`FirstCar.Pointed`); it goes when the
		hands are empty, wherever the car went.

		`PointCustomize = false`: no customize face, glow or chip, and the latch is never written. ]]
	PointCustomize = true,
	Customize = "Customize",
	CustomizeTitle = "CUSTOMIZE IT",
	KitCustomizeTitle = "Customize It",
	--- Under the kit card's 38-character row (see the note above `Seconds`).
	CustomizeText = "Paint it on the CUSTOMIZE podium",
	CustomizeSeconds = 12,
	--- The chip over the podium. Same pill and arrow as the tutorial's chip.
	CustomizeChip = "CUSTOMIZE",
	--- How soon after a banked run the car must land in the hands to count as that run's car.
	--- `GetawayService` settles the run and then awards the car in the same breath; this is slack.
	CustomizeBankWindow = 10,
}

-- === What the player hears ==================================================
--[[ A GRAB WHEN A CAR LANDS IN YOUR HANDS AND A THUNK WHEN IT LEAVES THEM (2026-10-12, Aleafo: "need
	a place and pickup sound"). Played for the carrier alone by `CarryController`, out of
	`SoundService.<Group>.<Name>` like `UpgradeConfig.Celebrate.Sound`; a missing clip is silence.

	THE HANDS ARE THE TRIGGER, NOT THE BUTTON. Both attributes the hands are drawn from
	(`CarryConfig.Attribute` for a hotbar car, `LobbyCarConfig.Toy.Attribute` for a toy) are watched,
	so every way in and out makes the same sound with no caller having to remember it:

	    Pickup   empty hands fill (a bank, a hotbar slot, a car lifted off a bay, a toy off the Cars
	             screen), or one car is swapped for another
	    Place    full hands empty (a bay, the street, back into its slot, into the inventory)

	Silent while a run has the car (`RaceStart` to `RaceEnd`): the bank lands it in your hands under
	the getaway, and the race start empties a toy, and neither is the player handling anything. The
	bay's own "Parked" chime (`FeedbackAudioConfig`) still plays over Place; this is the car touching
	down under it, and is kept short and low so the two read as one moment.

	Short, physical and at the UI clicks' level: both clips are Pro Sound Effects foley that start on
	frame one, because `PlayNamed` cannot skip a lead-in. ]]
CarryConfig.Sound = {
	Enabled = true,
	Pickup = { Group = "Carry", Name = "Pickup" },
	Place = { Group = "Carry", Name = "Place" },
}

return CarryConfig
