--[[
	SellConfig
	----------
	THE PLACE YOU SELL A CAR. A small marked square off the plaza with a wall of light round it and
	a sign behind it: drive one of your cars on, get out, and answer the question that comes up.

	         ┌──────────────┐
	         │ SELL YOUR CAR │                 <- the sign, on its pole behind the square
	         └──────────────┘
	    ┃ ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ ┃               <- the beam wall, all four edges. See `Fence`.
	    ┃ ▒                  ▒ ┃
	    ┃ ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ ┃
	              ▲
	         you drive on from the road

	IT WAS A THREE-BAY CAR PARK UNTIL 2026-08-24 and the rebuild is recorded on `Pad` and `Fence`:
	the owner asked for a smaller square rather than a lot, and for the beam wall to be the
	continuous one a tycoon draws round a button rather than a row of pickets across one end.

	=== THE GESTURE IS GETTING OUT OF THE CAR, 2026-08-31 =====================================

	THERE WAS A BUTTON ON THE BACK EDGE AND YOU HELD IT FOR 0.9 SECONDS. It is gone, and both halves
	of why are the owner's:

	  • THE HOLD WAS A THIRD STEP nobody had been taught. Drive in, get out, then walk to a specific
	    spot on the square and hold a key, with the price already on a sign over your head. The
	    player had made the decision two steps earlier and the button was ceremony.
	  • IT WAS A STOCK `ProximityPrompt` ON A SCREEN MADE OF THE KIT. Roblox's own grey capsule sat
	    in the middle of a plaza where every other surface is the artist's navy-and-blue, and it was
	    the only one in the lobby a player met head-on.

	WHAT REPLACED IT: parking a car of yours on the square and stepping out RAISES THE QUESTION
	itself — a panel, made of the kit, that names the car, prints the price and takes YES or NO. The
	sale still happens when the player says yes and never before, so nothing about this is a car sold
	by accident; the confirmation moved from a held key to a sentence with two answers.

	`Popup` below is that panel's behaviour and `SellPopupController` draws it. The rest of this file
	is unchanged, which is the point of the split: the lot, the volume, the price and the sign never
	knew what the gesture was.

	=== IT USED TO BE A SCREEN, AND MOVING IT IS THE WHOLE POINT ==============================

	Selling was a mode on the Cars Inventory: tick boxes on cards, a SELL toggle on the search row,
	a summary line, a button. That came out on 2026-08-24 (`Pages/Dealership`'s header records the
	deletion) on the owner's call, and between that pass and this one there was deliberately NO way
	for a player to sell a car. This is the other half.

	THE PANEL IS NOT THAT SCREEN COMING BACK, and the difference is the whole of it: that one sold a
	SELECTION out of a list from anywhere in the game, this one asks about the one car standing in
	front of you at the one place that buys cars. The location is still the feature.

	NOTHING ABOUT *WHAT* MAY BE SOLD CHANGED, and that is worth being explicit about because it is
	what made the move cheap. `GarageService.sellCars` is untouched — it still owns the ownership
	check, the cap, the unpark, the bay collect and the flag prune — and `GarageConfig.valueOf` is
	still the only price a car has. This file adds a LOCATION and a GESTURE. It adds no economy.

	SEVEN THINGS TO KNOW BEFORE CHANGING ANY OF IT.

	1. THE LOT IS AUTHORED, AND THE NUMBERS BELOW ARE WHAT AUTHORED IT. This is the one place in the
	   feature where the obvious rule was overruled on purpose. `CarDealConfig.Lots` derives its bays
	   from the map's own paint at run time because this map has been swapped once already
	   (`docs/MapLayout.md` §6) and a derived thing survives a swap that authored geometry does not —
	   and the first version of this file followed that. The owner asked for the lot to be a real model in the place so it can
	   be RESTYLED BY HAND, which a derived one can never be.

	   So the split is: `Modules/SellLot` draws it from these numbers, the `BuildSellLot` command
	   authors it into the place ONCE, and `SellService` binds whatever it finds there. `Lot` below
	   is therefore two things at once — the default spot the command builds at, and the fallback the
	   service builds at if the place has no lot in it at all (a swap that ate it, somebody deleting
	   it). It is not read on a normal boot.

	   WHAT THAT COSTS: a map swap can take the lot with it silently, exactly as it took the forecourt
	   billboards. What it buys: the modeller can replace every part of this with their own art and
	   nothing in code notices, because only two NAMES are the contract (`Names`, and
	   `Modules/SellLot`'s header lists them).

	2. THE LOT IS A VOLUME, AND THE SQUARE IS THAT VOLUME. What decides whether a car counts as "in"
	   is one box — the pad's own footprint, grown by `Volume` — so a car parked crooked or half over
	   the light still sells, and two players standing on it can each sell their own car with nothing
	   to arbitrate. The alternative (a marked bay per car, a car assigned to each) buys nothing a
	   player can see and costs an occupancy table that can disagree with the world. It is also why
	   the square is sized for ONE car: one box cannot tell two cars apart.

	3. THE SALE IS A REMOTE NOW, AND THE ONE GATE THE ENGINE USED TO GIVE MOVED INTO THE SERVICE.
	   Until the panel there was no client -> server remote in this feature at all: a sale arrived as
	   `ProximityPrompt.Triggered`, which the engine only fires for a player genuinely standing at the
	   button and which already carried who pressed it. A panel with a YES on it has to ask, so
	   `SellService` gained `RequestSell` — and with it `Request.Reach`, which is that check written
	   out by hand.

	   THERE IS DELIBERATELY NOTHING IN THE REQUEST: no key, no car, no price. It says "sell what I
	   have standing on the pad", the server looks up the sender's own lobby car
	   (`LobbyCarConfig.OwnerAttribute` on the model) and checks it against the box, so there is still
	   no way to name somebody else's car or a car that is not here.

	4. THE SIGN OVER THE LOT IS BUILT ON THE CLIENT, because what it says is personal: it names YOUR
	   car and YOUR price. Same split, and the same reason, as `CarDealController`'s seller — the
	   server owns the money and the geometry, the client owns the chrome that differs per player.
	   The one thing the server draws is the fixed board on its pole, which says the same thing to
	   everybody because it is an invitation rather than an offer.

	   THE SIGN AND THE PANEL SAY THE SAME THING AND ARE NOT REDUNDANT. The sign is the PRICE TAG: it
	   is up while you drive in and while you are still sitting in the car, which is when a player is
	   deciding. The panel is the QUESTION, and it only exists once the decision is due. They are
	   never on screen together — `SellController` drops the sign while the panel is up.

	5. YOU HAVE TO BE OUT OF THE CAR, and now that is the trigger rather than a rule. Selling destroys
	   the car (`LobbyCarService` puts it away on `CarsSold`) and destroying a seat somebody is sitting
	   in drops them out of it mid-physics, so a seated sale was always refused — see `Lines.GetOut`,
	   which the sign still says and the server still enforces. What changed is that stepping out is
	   no longer merely permission to sell: it is the act that asks.

	6. THE QUESTION IS A SCREEN AND IT IS MADE OF THE KIT. `Popup` is the behaviour, the layout lives
	   in `SellPopupController` next to the instances it positions, and the art is `UIAssets` — the
	   same panel, title cap, close X and pill the Welcome Back screen is assembled from. That is this
	   project's third way of drawing UI (authored pages, plain-shape code, kit-assembled code) and
	   this is the third screen on it, after `OfflineController` and the radio panel.

	7. A FAVOURITE COSTS A SECOND PRESS, AND THE PANEL IS WHERE IT IS PAID. A starred car puts a star
	   and an amber line on the panel, and SELL IT does not sell it: the title turns into ARE YOU
	   SURE? and a second SELL IT goes through. `Sell.ConfirmFavorites` is the switch and
	   `Popup.ConfirmArm` is the one detail that is not obvious — see it.

	   IT IS THE THIRD SHAPE THIS GUARD HAS HAD. A LOCK flag until 2026-08-24, which was a hard
	   refusal you had to go to another screen to lift (`InventoryConfig` header note 5 is that
	   story). Then a second HOLD at the button. Now a second press on a panel that has already named
	   the car and printed the price — same number of deliberate acts as the hold, on a screen where
	   the thing being confirmed is written down.

	   IT LIVES ENTIRELY ON THE CLIENT, and that is safe because of WHAT IT GUARDS. It is a guard on
	   a slip of the mouse, not on a cheat: a client that skipped it would sell its own starred car
	   and nobody else's, which is something that client could do anyway by pressing twice. So the
	   server holds no pending state and never has to — `SellService` sells what it is asked to.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ For `valueOf` and `carName` alone. `GarageConfig` requires `PaintConfig`, `UpgradeConfig` and
	`WorldConfig` and nothing else, so this cannot cycle — the same import, for the same reason, as
	`CarDealConfig`'s. ]]
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
--[[ For what one car is WORTH, condition and parts included. It requires `GarageConfig` and
	`CustomizeConfig` and neither of those requires this file, so this cannot cycle either. ]]
local MarketValueConfig = require(ReplicatedStorage.shared.Configs.MarketValueConfig)

local SellConfig = {}

--[[ Master switch. Off = no lot is built, the panel never opens, `RequestSell` is refused and
	there is NO way to sell a car anywhere in the game — the screen's sell mode is gone and
	`RequestSellCars` went with it, so this file is the only door. Turning it off is a deliberate
	"selling is closed", not a decoration change. ]]
SellConfig.Enabled = true

-- === Where it lives =========================================================

--[[ Workspace folder the lot Model lives in. `BuildSellLot` authors it there and the run-time
	fallback creates it on demand.

	AT THE WORKSPACE ROOT AND NOT INSIDE `Map`, which is the one placement decision that matters: the
	island has been swapped once already and the swap takes everything under it, which is how the
	forecourt billboards vanished without a word (`docs/MapLayout.md` §3.6). At the root the lot
	survives the next island. ]]
SellConfig.FolderName = "SellLot"

--[[ The tag on the lot Model, and how the CLIENT finds it.

	A TAG AND NOT THE FOLDER, for `CarDealConfig.Tag`'s reason: StreamingEnabled is on in this place,
	so `Workspace.SellLot` is not a stable thing for a client to watch — it need not exist at all on
	a client that has never walked near the plaza. `GetInstanceAddedSignal` covers arriving and
	leaving with one subscription and no polling.

	And the lot is `ModelStreamingMode.Atomic` for the other half of that note: a tag fires on the
	MODEL, which can arrive before its own subtree has replicated, and the controller walks the
	children on the frame it fires. ]]
SellConfig.Tag = "SellLot"
--[[ Names inside the lot. The client finds every one of these by name, so they are the contract
	between the service that builds the lot and the controller that dresses it. ]]
SellConfig.Names = {
	Lot = "SellLot", -- the Model
	Pad = "SellPad", -- the painted square, and THE VOLUME (note 2) — the client reads its size
	Border = "SellBorder", -- the four painted edge lines the curtain stands on
	Fence = "SellFence", -- the invisible box the curtain is hung on; see `SellConfig.Fence`
	Beam = "SellBeam", -- one bar of that curtain, and there are dozens
	Sign = "SellSign", -- the board on its pole behind the square, words only
	SignPost = "SellSignPost",
	--- An Attachment on the pad marking where the client's own sign hangs. See note 4.
	BubbleAnchor = "SellBubbleAnchor",

	--[[ TWO NAMES ARE GONE, 2026-08-31, and `SellLot.strip` deletes both off a lot authored before
		that date: `SellPrompt`, the held button, and `SellButton`, the Attachment on the back edge it
		hung from. There is no button on the square any more — getting out of the car is the gesture
		(header). Leaving them in the place would leave a live prompt on an authored lot that nothing
		in code is listening to, which is the worst of both. ]]
}

-- === Where the lot goes =====================================================

--[[ One point on the plaza, one bearing, one radius: WHERE A LOT IS BUILT WHEN ONE HAS TO BE.

	Read by `BuildSellLot` (as the spot it authors at, unless you untick KeepPlacement) and by
	`SellService`'s fallback (when the place has no lot in it). NOT read on a normal boot — the
	authored model's own position is what the game uses. See header note 1.

	=== IT FRONTS THE PLAZA ENTRY ROAD, AND THE FIRST PLACEMENT DID NOT =======================

	THE FIRST VERSION SAT ACROSS THE MOUTH OF THAT ROAD AND THE OWNER DROVE INTO IT. Bearing 90 at
	r=140 is a clear patch of asphalt by every clearance test there is, which is exactly why the
	first pass chose it — and a clearance test cannot see a ROAD, because in this map the road and
	the plaza floor are the same asphalt. What tells them apart is the MARKINGS folder:

	    Markings, 13 stripes, x 2190-2267, all at z 489, each 28 long in Z
	        -> a crosswalk, so an east-west carriageway crossing z 475-503
	    Islands  Cube.086 at x 2280, 8 wide x 98 long, with kerbs at 2272 and 2288
	        -> the north-south ring road, and the median the entry road tees off

	So there is a road running from the ring road straight into the plaza at z≈489, and the old lot
	(pad z 463-517) straddled it with the beam wall across the far end, and that wall was collidable.
	Driving in from a plot you hit it head-on, and the only way in was to go round into the plaza and
	turn back. Nothing the square builds collides any more (`Fence`), so the worst a bad placement
	can now do is look wrong rather than block a road.

	THE FIX IS NOT A NUDGE, IT IS AN ORIENTATION. A lot on a plaza should face the plaza; a lot on a
	ROAD should face the road. So the position stays polar (it survives the island moving) and
	`EntranceBearing` below is now separate from it — the lot sits BESIDE the entry road with its
	mouth open onto it, which is what a roadside lot looks like everywhere else.

	=== BEARING 101, RADIUS 206 ARE MEASURED, NOT PICKED ======================================

	That puts the square at (2243, 451), on the open apron north of the entry road's crosswalk, with
	the plaza deck 55 studs to its west and the ring road's median island 30 to its east. Probed at
	10-stud steps along both sides of the road with the footprint of the day (a 58 x 16 x 40 box
	lifted 9 studs; the square's is now 34 x 16 x 38, so every window below is wider than it needs
	to be):

	    x = 2200-2220   blocked — a street-light pole at x≈2195
	    x = 2230-2240   CLEAR, both sides (z 448-460 and z 520-532), flat at Y 51.5
	    x = 2250-2260   blocked — the ring road's median island and its kerbs

	The south side (z≈524) probes identically and is the fallback if this side is ever wanted for
	something else.

	=== WHY 206 AND NOT THE 198 THE LOT WAS BUILT AT ==========================================

	NINE STUDS EAST, AND IT IS THE SMALLER FOOTPRINT SPENDING ITS WINNINGS. At 198 the plaza's
	yellow boundary trim ran diagonally through the pad's left third: the 54-wide lot could not
	avoid it, which is why `Pad.Lift` was raised to 0.35 to bury it. The square is 30 wide, and the
	clean asphalt on this apron runs x 2228-2268 at z 436-470 — so it now fits with the trim OUTSIDE
	it altogether. What is still under the pad is one 0.32-stud paint strip at x≈2254, which the
	same lift covers.

	A HEIGHT PROFILE IS THE ONLY THING THAT CAN FIND ANY OF THIS. `Fit.Clearance` is a box lifted 9
	studs and cannot see a kerb (`Pad.Lift` carries that whole warning); the map above came from a
	raycast every 2 studs across the footprint, comparing Y. Re-run that, not the clearance test, if
	this square is ever moved.

	THE OTHER PLACEMENTS THAT WERE MEASURED AND NOT TAKEN, so nobody re-derives them:

	  • ON THE PLAZA DECK (r 125-155, the market ring's own island). Blocked: a 34-stud box is clear
	    only at bearings 85-95 and 265-275, and those two windows ARE the road corridors. The deck
	    is a raised pedestrian island ringed with lamp poles and trees, and driving a car up its kerb
	    to sell it is not what that space is for.
	  • THE SOUTH VERGE (bearing 79, z≈528). Probes identically and stays the fallback, but it puts
	    the crossing between the square and the plaza, so a player walking out of the island has to
	    cross the entry road to reach it.

	IT DOES NOT SIT IN FRONT OF ANYBODY'S SHOWROOM. The six plots bear 180, 215, 324, 0, 36 and 145
	from this same centre (`docs/MapLayout.md` §3); 101 is inside the widest gap between two of them.

	The centre is the roundabout's own centre — the same two numbers `CarDealConfig.Lots` and
	`BuildLeaderboardBoard` use, repeated rather than imported so that neither feature moves when the
	other is retuned. Y IS NOT CONFIGURED: the service raycasts for the plaza surface, for
	`PlotConfig.Fallback`'s reason — every deck height in this map is derived from mesh geometry, and
	a typed Y is the number that silently breaks if the island is ever moved. ]]
SellConfig.Lot = {
	CentreX = 2041,
	CentreZ = 490,
	Radius = 206,
	--- Degrees, measured the way `docs/MapLayout.md` measures a plot bearing: 0 = +Z, clockwise.
	--- WHERE THE LOT STANDS. Which way it FACES is `EntranceBearing`, and the two are independent.
	Bearing = 101,

	--[[ Which way the lot's MOUTH points, in the same compass degrees. 0 = the entrance faces +Z,
		which here is the plaza entry road at z≈489, and the sign is therefore at the far end.

		IT IS NOT DERIVED FROM `Bearing` AND THAT IS THE WHOLE POINT. Until 2026-08-24 the lot always
		faced radially, straight out from the plaza centre, which is right for something arranged
		AROUND the plaza (the deal ring is) and wrong for something you drive into off a road. The
		header has what that cost. Turn this 180 and the lot faces the plaza instead; turn it 90 and
		it fronts the ring road.

		A CAR ENTERS ALONG THIS BEARING AND ITS NOSE ENDS UP POINTING THE OPPOSITE WAY, at the sign.
		So the sign, which stands behind the square facing the way in, is readable from the road, and
		so is the button under it. The square itself is symmetric: this bearing decides which side
		the sign stands on and nothing else. ]]
	EntranceBearing = 0,

	--[[ Stepping the lot around the compass until it fits: the ideal bearing first, then the nearest
		clear one either side of it (+3, -3, +6, -6 ...).

		A lot that never clears is built at its ideal bearing anyway and logged: a map with
		no room on it is a map problem, and a lot standing in a tree is a better failure than no way
		to sell a car.

		THE MARKET NO LONGER SEARCHES AT ALL. Its bays are the stalls of the map's own car parks
		(`CarDealConfig.Lots`, `docs/MapLayout.md` §7), which is the better answer for something that
		wants to be found in the same place twice. It is a non-answer for this lot, because nobody has
		painted a car park for it, and it has ONE place it belongs anyway: beside the entry road,
		facing it. What this steps through is a few metres of verge, not the whole island.

		STEPPING THE BEARING NOW SLIDES THE LOT ALONG THE ROAD rather than round the plaza, which is
		the happy accident of fronting a road that runs roughly radially: at r=198 a 3-degree step is
		about 10 studs sideways, and the clear window either side of the entry road is 40 wide. So a
		blocked build shuffles down the verge, which is what you would do by hand. `EntranceBearing`
		is NOT stepped with it — a nudged lot still faces the road. ]]
	Fit = {
		StepDegrees = 3,
		MaxSteps = 10,
		--[[ The box the bearing has to be clear of: the pad (30 x 30) plus a couple of studs all
			round, 38 deep so the sign's pole and its standoff are inside the question too, and 16
			tall to clear a car, the board over it and the client's own bubble above that. ]]
		Clearance = Vector3.new(34, 16, 38),
		--- How far above the ground the clearance box is centred. Half its height plus a stud, so the
		--- test asks about the space the lot occupies and not about the asphalt it stands on.
		Lift = 9,
	},

	--[[ The ground probe. Starts `ProbeUp` above the map's own vertical extent and runs down.
		Generous, for the reason `CarDealConfig.Lots.Probe.ProbeUp` gives: the plaza is Blender geometry whose
		`MeshPart.Size` is a bounding box rather than a surface, so a lot seated on a typed Y would
		be buried in it. ]]
	ProbeUp = 60,
	ProbeDown = 160,

	--[[ How flat the footprint has to be before a bearing is accepted, in studs between the highest
		and lowest of its five ground probes (centre and four corners). The plaza is dead level, so
		this is really a guard against a lot half on a kerb after a map change. ]]
	MaxSlope = 1.5,
}

-- === The square =============================================================

--[[ The painted square, which is both the art and THE VOLUME (note 2).

	IT IS A SQUARE AND NOT A CAR PARK, AND THAT IS THE 2026-08-24 REBUILD. The first version was a
	three-bay parking lot 54 studs across, and standing on the plaza it read as one more of the
	map's own parking bays — there are two of those within a hundred studs of it, drawn in the same
	white-on-asphalt. What a player should see instead is what a tycoon uses for this job: a small
	marked square with a wall of light round it, which says "stand here" in a way a painted bay
	never will. So the bays went, the footprint dropped from 54 x 34 to 30 x 30, and the beams came
	off the back wall and went all the way round the edge (`SellConfig.Fence`).

	`CanCollide` IS FALSE AND THAT IS NOT OPTIONAL. It is a slab lying proud of the asphalt, and a
	proud slab a car can hit is a kerb across the entrance — the exact fault the world road tiles
	shipped with (memory: lane lines 0.31 studs proud, colliding). It exists to be looked at and to
	be measured against; nothing ever touches it. ]]
SellConfig.Pad = {
	--[[ Studs across and along. THEY ARE EQUAL ON PURPOSE, and nothing in the code requires it: the
		geometry below walks a rectangle, so a 30 x 40 pad builds correctly and the light still goes
		round it. It is square because the square IS the shape (see above), and because a square has
		no wrong way to drive on to it.

		30 TAKES THE LONGEST BODY ON THE ROSTER (21.7 studs) with four studs clear at each end, which
		is room to have driven on straight and stopped without hanging out of the light. It is not
		room for two cars, and that is deliberate: the volume test is one box (note 2), so a square
		that fits two cars is a square where the wrong one sells. ]]
	Width = 30,
	Depth = 30,

	Thickness = 0.4,

	--[[ Studs the slab's TOP sits above the ground it was raycast onto.

		0.35 AND NOT 0.06, AND THE REASON IS A KERB NOBODY CAN SEE. The plaza's yellow boundary trim
		runs north-south along x 2212-2230, curving, and it is RAISED 0.28 studs above the asphalt —
		measured. The old 54-wide pad could not clear it: between that kerb and the ring road's
		median island the clean window is 46 studs, at every z along the entry road. THE 30-STUD
		SQUARE FITS THAT WINDOW, so the lift is no longer the fix it was, and it is kept because a
		lot somebody drags somewhere else may well land on paint again.

		THE CLEARANCE TEST CANNOT SEE A KERB AND THAT IS WORTH KNOWING BEFORE MOVING THIS SQUARE.
		`Fit.Clearance` is a 16-stud box lifted 9, so it spans roughly ground+1 to ground+17 — it is
		asking "is there room for a car and a sign here", and anything under a stud tall is invisible
		to it. A flat plaza can therefore probe perfectly clear and still have paint, lane lines and
		kerbs all over it. The height profile that found this one is a raycast every 2 studs across
		the footprint, comparing Y; that is the tool for this question. ]]
	Lift = 0.35,

	--- Kit navy, a shade off the plaza's own asphalt so the square reads as a marked-out area rather
	--- than as a patch of different road.
	Color = Color3.fromRGB(38, 46, 64),
	Material = Enum.Material.SmoothPlastic,
	--- OPAQUE, and it is the other half of hiding that kerb: at 0.15 the yellow showed straight
	--- through the slab that was covering it, which looked exactly like a misaligned decal.
	Transparency = 0,

	--[[ The border: one painted line round each edge, in the kit blue, and the curtain stands on it.

		IT REPLACED THE BAY DIVIDERS. Three lines across a slab is a car park however small you make
		it; one line round the outside is a marked-out square, and it is also what gives the beams
		something to come out of instead of starting in mid-asphalt. ]]
	Border = {
		Width = 0.7,
		Color = Color3.fromRGB(0, 102, 255), -- #0066FF, the kit blue
	},
}

--[[ WHAT COUNTS AS "IN THE LOT", relative to the pad.

	Grown a little sideways and a lot upward. The margin is there because a player who has stopped
	with a wheel over the line has parked, and refusing that is a rule with nothing behind it; the
	height band is there because the test is against the car's HitBox centre, which sits about a
	stud and a half up, and because a car that has just been driven in may still be settling. ]]
SellConfig.Volume = {
	Margin = 2, -- studs added to the pad's half-extents, both axes
	Below = 4, -- studs under the pad's top face
	Above = 14, -- ...and over it. A car on its roof still sells.
}

-- === The wall of light ======================================================

--[[ THE BEAM WALL, AND IT GOES ALL THE WAY ROUND. One continuous white curtain standing on the
	border, along all four edges, waist-to-head high and fading out as it rises. It is the thing
	every tycoon and simulator draws round a button, and it is what the owner asked for twice: the
	first build read "a beam wall" as a wall at the BACK of the lot and produced a row of blue
	pickets across one end, which is a different object entirely.

	NOTHING ABOUT IT IS SOLID, AND THAT IS FORCED. The old wall had an invisible collidable slab
	behind it so a car driven in fast stopped rather than carrying on across the plaza; a curtain
	that surrounds the square cannot have one, because the way in is through it. So the square is
	drive-over, exactly like the button it is imitating, and a car that overshoots drives out the
	far side and comes back round. That is a better failure than an invisible wall somebody keeps
	hitting, which is what the collidable slab was already on its way to becoming — its own flag's
	note said as much before it was deleted.

	FOUR BEAMS, ONE PER EDGE, EACH AS WIDE AS ITS EDGE IS LONG. That is the owner's call and it is
	the right one: the first pass drew the wall as 109 narrow camera-facing bars packed until they
	overlapped, and however tightly you pack them they still read as slats. One quad per side is one
	sheet, and it is four instances instead of three hundred.

	EACH BEAM RUNS VERTICALLY AND IS WIDENED SIDEWAYS, which looks backwards until you know that a
	Beam's transparency gradient runs along its LENGTH. The fade this look is made of is bottom to
	top, so the beam has to BE vertical for the fade to exist at all; a beam laid along the edge
	could only fade at its ends, which is the wrong axis and reads as a wall with dark corners. So
	the beam is 7 studs long (up) and `Pad.Width` studs wide (sideways), and `Width0`/`Width1` are
	not configured here at all — they are read off the pad, so resizing the square keeps the wall
	exactly on its edge.

	`FaceCamera` IS OFF, AND IT HAS TO BE. A camera-facing quad 30 studs wide would swing to face
	you and stop lining up with the edge it is standing on; that property is only safe on bars thin
	enough that their rotation does not show. With it off, the ribbon's plane comes from how the
	ATTACHMENTS are rotated, which is the one thing about beams Roblox does not document and
	`RibbonRoll` below now records. ]]
SellConfig.Fence = {
	--- Studs. Head height on a car, which is what keeps the curtain reading as a marker you drive
	--- through rather than as a room you drive into.
	Height = 7,

	--[[ Degrees of roll on each beam's attachments, about the beam's own (vertical) axis.

		A BEAM'S WIDTH FOLLOWS ITS ATTACHMENTS' +Y AXIS. Roblox documents +X as the CURVE direction
		and stops there, so this was measured rather than read: three beams built with known
		attachment frames and photographed from straight overhead, where a vertical ribbon is a
		hairline and a flat one is a slab. Identity attachments on a vertical beam draw NOTHING,
		which is the giveaway — +Y is then parallel to the beam and the ribbon has no area.

		So the builder points +X up the beam and puts the edge's own direction on +Y, and 0 is
		correct. 90 rolls each wall to stand across its edge instead of along it, which builds a
		four-bladed pinwheel rather than a box. This stays a number rather than becoming a constant
		only because it is the one thing here an engine change could quietly invert. ]]
	RibbonRoll = 0,

	--- WHITE, per the brief. It is also the one colour `LightEmission` cannot bleach: the first
	--- build's blue curtain photographed as a wall of white bars at high emission, with the blue
	--- still sitting in the property and nothing on screen saying so.
	Color = Color3.new(1, 1, 1),

	--[[ The fade, and it is what separates a tycoon beam from a fence panel.

		`Foot` is how solid the curtain is where it meets the pad, `Head` is what it has faded to at
		the top, and `Base` is the fraction of the height held at full strength before the fade
		starts, so the light has a bright skirt rather than beginning to vanish the moment it leaves
		the ground. `Bias` is where it reaches the half-way transparency, as a fraction of the
		height: under 0.5 it keeps the light low and thick, which is the shape in the reference.

		ONE QUAD MEANS ONE LAYER, so unlike the packed-bar version this number is what you actually
		see: nothing stacks on top of it. At 0.3 the wall photographed as milky white and hid the pad
		behind it, which is a plinth rather than a beam. THE VIEW THAT DECIDES IT IS EYE HEIGHT, not a
		three-quarter one from above: a player stands under the top of this wall, so the near side is
		always between them and the pad, and anything under about 0.5 turns the navy grey. ]]
	Foot = 0.55,
	Head = 1,
	Base = 0.1,
	--- Under 0.5 keeps the light low and thick. 0.35 puts the top half of the wall in the faint
	--- half, so the box reads as a skirt of light rather than as four panels.
	Bias = 0.35,

	--[[ What makes it glow rather than sit there as a flat strip. Higher than the old blue curtain's
		0.35 could ever be, because EMISSION EATS THE COLOUR and there is no colour left to eat: the
		brief asks for white, so bleaching is the look. ]]
	LightEmission = 0.45,
}

-- === The sign ===============================================================

--[[ The board on its pole BEHIND the square: what this place is, and what to do. It says the same
	thing to everybody (note 4), so the server builds it and nothing ever rewrites it.

	IT STANDS OUTSIDE THE LIGHT AND WELL ABOVE IT. Outside by `Standoff`, so the pole does not run
	up through the curtain; above by `Rise`, FOR A REASON THAT ONLY SHOWS UP IN A SCREENSHOT and
	that the smaller square has not changed. The client's own price panel hangs over the middle of
	the pad at `Bubble.Height`, 15-odd studs nearer the viewer, and elevation on screen is an ANGLE
	rather than a height — so two signs at different depths line up the moment their angles match.
	At the first pass's 1.2 studs they did, and the price panel sat exactly over this board's
	caption line. Separating them means making this board's angle clearly bigger, which at that much
	depth costs a lot of studs of height.

	What it buys is worth having on its own: it is the only thing this feature builds that can be
	read from the far side of the plaza, which turns the square into a landmark rather than
	something you find by walking into it. Change `Rise` and re-check the pair together with a car
	parked on the pad; either number alone is not the picture.

	IT FACES THE WAY YOU DRIVE IN (`Lot.EntranceBearing`). Same reasoning as the forecourt
	billboard's facing (`docs/MapLayout.md` §3.6), and the same trap avoided: a sign turned the
	other way is a sign nobody ever sees. ]]
SellConfig.Sign = {
	Width = 16,
	--[[ 16 / 2.4221, WHICH IS THE `Upgrades.SignPanel` TEXTURE'S OWN ASPECT — 2026-08-26, up from a
		flat 5.

		The board is the kit's two-line plot sign now (`SellLot.drawSign`) rather than a navy rectangle
		with a blue bar across it, and that texture's border and inner rim come from LAYER STYLES: they
		stay 5px whatever size the art is drawn at, and so they come out uneven the moment it is
		stretched off 2.42:1. At 16 x 5 the vertical borders would have rendered at 76% of the
		horizontal ones, which is the wrongness `assets/ui/upgrades/README.md` describes as reading as
		"off" without being nameable.

		THE HEIGHT MOVED RATHER THAN THE WIDTH because 16 studs is what makes this a landmark — the
		header's whole argument for `Rise` is that this board is the one thing here readable from the
		far side of the plaza, and 5 * 2.4221 = 12.1 would have taken a fifth of that away. Going up
		costs nothing: the PART IS INVISIBLE (`buildSign`), `Rise` is measured to the BOTTOM edge, and
		the extra height lifts the caption line further clear of the player's own price bubble — which
		is the separation the header says to re-check, moved in the safe direction. ]]
	Height = 6.6,

	--- Studs behind the back edge of the pad that the pole stands, so it is outside the curtain
	--- rather than through it. Half the old board's size, because the square it labels is half the
	--- old lot.
	Standoff = 2.5,

	--- Studs from the ground to the BOTTOM of the board. See the header: this is the number that
	--- keeps the fixed board and the player's own price panel off each other on screen, and it is
	--- not a look-and-see number.
	Rise = 16.5,

	Thickness = 0.35,
	--- Degrees the board leans back toward the square, so it reads from a car's eye line rather than
	--- from directly in front of it.
	Tilt = 12,

	--- The pole under it, standing on the ground.
	PostWidth = 1,
	--- Kit panel navy, and NOT the neon blue the old end posts wore: this is 16 studs of upright
	--- standing next to a wall of light, and a neon one competes with the thing it is labelling.
	PostColor = Color3.fromRGB(54, 65, 87),
	PostMaterial = Enum.Material.SmoothPlastic,

	--- SurfaceGui density. 60 is what the plot boards use and what the kit's text was drawn against.
	PixelsPerStud = 60,

	--[[ Inside the panel, as fractions OF THE PANEL, and lifted wholesale from `BuildComingSoonSigns`
		because this is the same sign doing the same job: a title on the cap and one line under it.

		The cap is inset by the texture's own 5px border rather than run edge to edge, which is where
		the mockup puts it on every page in this kit. ]]
	Cap = { x = 0.0067, y = 0.0162, w = 0.9866, h = 0.3409 },
	Body = { y = 0.4110, h = 0.5195 },

	--[[ ONE TYPE SCALE, as fractions of the PANEL'S RENDERED HEIGHT (`Height * PixelsPerStud`, 396px
		at the numbers above), applied as `UITextSizeConstraint` ceilings with `TextScaled` left ON.

		A ceiling rather than a fixed size, so the two lines are a DECISION — `TextScaled` on its own
		sizes each row to its own box, which is how a title and a caption end up the same size — while a
		string that genuinely does not fit still shrinks rather than spilling. That is the case a fixed
		`TextSize` breaks the first time this is translated.

		The caption's ceiling is well under the title's, and that is arithmetic rather than taste. It was
		set against a 28-character caption ("DRIVE IN AND HOLD THE BUTTON") which at 51px took about
		743px of an 864px column; the caption is 20 characters now and takes about 530px, so the headroom
		it was picked for only grew. That headroom is the only thing keeping the line on one, since the
		strings no longer go through `oneLine`.

		DO NOT follow `TextScaled` with a `TextWrapped` write anywhere this feeds. Assigning
		`TextWrapped = false` after it silently clears `TextScaled`, and the label then renders at the
		default `TextSize` of 8 with nothing anywhere reporting a problem. ]]
	Type = {
		Title = 0.2013, -- 80px at this board's size
		Caption = 0.13, -- 51px
	},

	Colors = {
		--[[ The kit's face `#28334B`, painted BEHIND the panel texture rather than being the panel.
			Every navy surface in `UIAssets` is drawn at 80% so gameplay shows faintly through a page you
			have opened; this is a board on a pole in daylight standing next to a wall of white light, and
			at 80% the curtain read straight through it. The art then composites 80% of `#28334B` over
			`#28334B` and lands exactly where it was drawn. Same call as the garage-door sign's. ]]
		Face = Color3.fromRGB(40, 51, 75), -- #28334B
		Title = Color3.new(1, 1, 1),
		Caption = Color3.fromRGB(206, 214, 232),
		TextStroke = Color3.fromRGB(10, 20, 32),
	},
}

-- === The question ==========================================================

--[[ THE PANEL THAT ASKS. Raised by `SellController` when a car of yours comes to rest on the pad
	with nobody in it, drawn by `SellPopupController`, and answered with one of two pills.

	         ┌─────────────────────────────┐
	         │ ▓▓▓▓   SELL THIS CAR?   ▓▓▓ │      <- the kit's title cap
	         ├─────────────────────────────┤
	         │        RED CAMARO           │
	         │          $2,400             │
	         │    ( SELL IT ) ( KEEP IT )  │
	         └─────────────────────────────┘

	THE NUMBERS HERE ARE THE BEHAVIOUR AND NOT THE LAYOUT. Where the rows sit inside the panel lives
	in `SellPopupController` beside the instances it positions, exactly as `OfflineController` keeps
	its own — a fraction of a panel means nothing without the panel, and splitting the two across two
	files is how a screen ends up laid out by numbers nobody can see the effect of. ]]
SellConfig.Popup = {
	Enabled = true,

	--[[ Studs from the pad the player must be within for the question to be asked, and for it to stay
		up once it has been. It is the OLD BUTTON'S REACH, unchanged: the far corners of the square are
		≈33.5 studs from its back edge, so 34 covers every part of the pad and very little past it.

		IT CLOSES THE PANEL AS WELL AS OPENING IT. Walking off leaves nothing on screen to come back to
		a minute later and press by accident, and walking back is the cheapest way there is to be asked
		again after a KEEP IT. ]]
	Reach = 34,

	--[[ Seconds the car has to sit in the lot, empty, before the panel comes up. It is not a delay for
		its own sake — it is the gap between the seat letting go and the car actually being STOPPED, and
		a panel that arrives while the body is still rocking on its springs reads as having interrupted
		the player rather than waited for them.

		SHORT ENOUGH TO FEEL CAUSED BY GETTING OUT. Much past half a second and the panel stops being
		the answer to stepping out and starts being something that happened later. ]]
	Settle = 0.35,

	--[[ Studs per second the car may still be moving at when the panel is raised. A car somebody has
		just stepped out of at speed is still rolling, and it can roll off the pad — so the question is
		held until it has actually parked. Walking pace, near enough: below this the model is settling
		rather than travelling. ]]
	RestSpeed = 6,

	--- Seconds a YES leaves both pills dead while the server answers. The panel closes on the reply;
	--- this is the backstop for one that never comes, and it UNLOCKS rather than closing, because
	--- nothing has been sold and the question is still worth answering.
	AnswerTimeout = 4,

	--[[ Seconds both pills stay dead after the FIRST press on a starred car, while the panel turns
		into ARE YOU SURE? — header note 7.

		IT EXISTS FOR THE DOUBLE CLICK AND FOR NOTHING ELSE. A second question drawn on the same pixels
		as the first is a question a double click answers without ever being read, which would leave
		the guard technically present and practically absent. A quarter of a second is under a
		deliberate second press and over every double click there is (Windows' own default threshold is
		half a second, and that is the interval a double click must fit INSIDE).

		IT IS NOT A TIMEOUT. The confirm state itself never expires — the panel is the state, it is in
		front of the player, and it goes when they answer or walk away. ]]
	ConfirmArm = 0.25,

	--[[ Seconds a REFUSAL stands on the panel before it drops. Long enough to read a short line,
		short enough that it is not a screen anybody has to dismiss.

		A SALE HAS NO SUCH HOLD, and it used to: the panel stood on SOLD over the money for 0.9s. That
		came out on 2026-08-31 on the owner's call, because the receipt was drawn on top of the thing
		that IS the receipt — `CashBurstController` throws the notes out of the lot and into the
		player, and a full-screen scrim over the first second of that flight is the panel standing in
		front of its own payoff. So a sale closes the panel at once and the money is the confirmation.

		A refusal keeps the hold because it has nothing else to say it. ]]
	RefusalHold = 1.2,
}

-- === Asking the server ======================================================

--[[ WHAT THE SERVER DOES WITH A `RequestSell`. Header note 3: the panel replaced a `ProximityPrompt`
	and a prompt came with a proximity check the engine made for free. These two numbers are that
	check, and the rate limit the trigger used to carry, written out by hand. ]]
SellConfig.Request = {
	--[[ Studs from the pad the SENDER'S CHARACTER must be within for the server to consider a request
		at all. Deliberately looser than `Popup.Reach`, and the slack is not sloppiness: the panel is
		closed client-side the moment the player walks past 34, but a press that was already in flight
		when they crossed the line is honest and must not be thrown away. 60 is comfortably outside any
		plausible walk during a round trip and comfortably inside "somewhere else on the island".

		A PLAYER WITH NO CHARACTER FAILS THIS. There is no case where a car is sold at a lot by somebody
		who is not standing at it. ]]
	Reach = 60,

	--[[ Per-player floor between accepted requests. Same shape and reason as
		`GarageConfig.Picker.Cooldown`: a sale writes the profile, rebuilds a lot and republishes three
		attributes, and the request is client-driven. Stamped on the ATTEMPT, so a refusal costs the
		same as a sale — which is what stops a client hammering the remote to farm refusals. ]]
	Cooldown = 0.6,
}

-- === What the lot says to YOU ===============================================

--[[ The client's own sign, hanging over the middle of the lot: the car it can see of yours, what it
	is worth, and why it will not sell if it will not. Built by `SellController` (note 4).

	Sized in STUDS on its Scale component, so it is a physical object in the plaza that shrinks as
	you walk away, exactly like the market's bubbles. ]]
SellConfig.Bubble = {
	Enabled = true,

	--[[ Studs, and it is THE WHOLE TEXTURE — body plus tail, exactly as `CustomerConfig.Bubble`
		means it. 13 / 2.5729 is `UIAssets.Bubble.Panel`'s own 1024x398 aspect; hold that ratio if this
		is ever retuned, because the drawing's two 5px rims are painted at an even weight all the way
		round and a stretch is what puts them out of true.

		IT GREW FROM 12 x 5.2 (2.31:1) ON 2026-08-26, when the flat rounded rectangle became the kit's
		tailed bubble. The width carries the change rather than the height: the bottom fifth of the
		drawing is tail, so holding 5.2 would have left the three rows sharing 4.0 studs where they used
		to have all 5.2, and the price is the one number a player walks over here to read. ]]
	Size = Vector2.new(13, 5.05),
	--[[ Studs above the pad the panel's CENTRE floats — the billboard is adorned to an attachment
		and centred on it, so half the panel hangs below this. At 8 the bottom edge sits at 5.4,
		which is just over the roof of the tallest body on the roster, and the top at 10.6, which is
		what keeps it clear of the fixed sign (see `Sign.Rise` for that whole argument). ]]
	Height = 8,
	--- Past this many studs it is not drawn. Sized to be readable from the market ring, 50 studs in,
	--- and not from a dealership plot.
	MaxDistance = 200,

	--[[ Fractions of the panel's own height, top to bottom. Three bands: what the lot is about to
		take, the word, and the money. The name and the price are the big two — they are what a
		player is deciding on. ]]
	Rows = {
		Caption = { Y = 0.06, Height = 0.17 },
		Body = { Y = 0.24, Height = 0.3 },
		Price = { Y = 0.58, Height = 0.34 },
	},

	--[[ The `car ui.psd` kit. `Panel` and `Stroke` are gone with the flat frame they painted — the
		panel is `UIAssets.Bubble.Panel` now and draws its own face, border and rim.

		TWO OF THESE ARE THE WHOLE FEATURE'S AND NOT THE SIGN'S, 2026-08-31: `SellPopupController`
		reads `Warning` and `Refused` off this table rather than carrying its own. They are under
		`Bubble` because that is where they were first needed, and they stayed there because the sign
		and the panel saying the same thing in two different colours is exactly the drift a second
		copy causes. ]]
	Colors = {
		Caption = Color3.fromRGB(206, 214, 232),
		Price = Color3.fromRGB(13, 180, 21), -- #0DB415, the kit money green
		--- What a refusal is painted, on the panel. The kit has no red; this is the pill palette's own,
		--- dimmed to sit on navy rather than shout off it. Same colour `CarDealConfig` uses for "can't
		--- afford".
		Refused = Color3.fromRGB(226, 96, 96),
		--[[ What the favourite line is painted — header note 7. Deliberately NOT `Refused`: nothing has
			been refused and the YES under it will still sell the car, so painting it the same red as a
			no would teach the player that the panel had turned them down. Amber is the kit's caution
			ramp, one step off the money green so the two never read as the same row. ]]
		Warning = Color3.fromRGB(245, 186, 61),
	},

	--[[ What the panel fades UP to, and it is 0 rather than the old 0.1 because the bubble texture
		ships opaque and is meant to. The kit's 80% face is a property of a panel laid over a dimmed
		backdrop; this one hangs over the plaza in daylight with a wall of light behind it, and the
		first build of the customer bubble was uploaded at 80% and had to be redone for exactly that
		reason (`UIAssets.Bubble`). Leave it at 0 — the translucency is baked into the art or it is
		nowhere. The fade itself is still real: this is the value `_setShown` tweens to.

		THE `UICorner` AND `UIStroke` THAT USED TO BE HERE ARE GONE. The border, the inner rim, the
		corner and the weave are all drawn into the texture now, which is the whole point of it. ]]
	PanelTransparency = 0,

	--- Seconds the panel takes to fade in and out as a car comes and goes. Short: it is a sign
	--- turning over, not an event.
	FadeSeconds = 0.18,

	--[[ How often the client re-asks "is my car in the lot?", in seconds. It is a couple of vector
		comparisons against a box, so this is cheap — 0.2 is well under the time it takes to drive in
		and stop, and a sign that appears the frame the wheels stop moving is the whole feel of the
		thing. It only runs while the lot is streamed in and the player is inside `MaxDistance`. ]]
	PollInterval = 0.2,

	--[[ `RefusalSeconds` WAS HERE and went on 2026-08-31 with the thing it timed. The sign used to
		flash a refusal over itself for 2.5 seconds, because the only way to earn one was to hold a
		button that could fail while the sign was the only surface there was to answer on. A request now
		comes from a panel that is already open, so the answer goes to the panel and the sign is never
		interrupted. ]]
}

-- === Words ==================================================================

--[[ Every string this feature prints. No em dashes and no punctuation that needs a font: these are
	drawn in Ubuntu Bold at whatever size a 12-stud billboard gives them, on a screen that may be a
	phone. ]]
SellConfig.Lines = {
	--[[ The fixed board on its pole. THESE TWO DO NOT GO THROUGH `oneLine` any more — 2026-08-26.

		That helper laces a string with non-breaking spaces so `TextScaled` has nothing to wrap on, and
		it works. It also quietly breaks localization: `AutoLocalize` captures the source string, so what
		Roblox is asked to translate is "DRIVE<nbsp>IN<nbsp>AND<nbsp>GET<nbsp>OUT" — which no translation
		of the real sentence can match and which a human translator sees as mangled. The
		board has type CEILINGS now (`Sign.Type`), so there is nothing left to defend against and the
		strings go in exactly as written. Same call, and the same reasoning, as the upgrade board's.

		The bubble's lines below still go through it: they are per-car and have no ceiling. ]]
	SignTitle = "SELL YOUR CAR",
	--- WAS "DRIVE IN AND HOLD THE BUTTON" until 2026-08-31, and it is the only string in the game that
	--- taught the gesture. The board now says what the square actually wants you to do, in the order
	--- you do it — the second half is the trigger, not a suggestion.
	SignCaption = "CHOOSE A CAR TO SELL",

	--- The client's own sign, with a car of yours standing in the lot: this over the car's name, and
	--- the price under it. There is no "PRICE" caption because there is nothing to tell it apart
	--- from — the sign carries one number and it is money.
	SellCaption = "SELLING",

	--[[ ...and the one thing the sign still says about the player rather than the car. It is the
		caption row, over the car's name and its price, while they are sitting in it — which since
		2026-08-31 is the instruction for the whole feature rather than a refusal, because getting out
		is what raises the question.

		FOUR STRINGS WENT WITH THAT CHANGE: `NoCar` and `NoCarCaption` (a refusal for a press that can
		no longer be made — there is nothing to press when there is no car in the lot), `GetOutCaption`
		(the second line of that refusal), and `Sold` (the receipt, which is now the panel's, in
		`PopupLines`). The sign has no refusal states left at all. ]]
	GetOut = "GET OUT OF THE CAR",

	--- The star's line on the panel, header note 7. It is a WARNING and not a question: the YES under
	--- it still sells on one press, and this is the sentence that makes sure the player knows which
	--- car they starred is the one in front of them.
	Favorite = "THIS IS A FAVORITE",
}

--[[ Every string the panel prints. Split from `Lines` above because that table is the WORLD's copy —
	a board on a pole and a sign over a car, both read at a distance in a 3D scene — and this is a
	screen's, read at arm's length with the game behind it. They are tuned differently and a string
	that moves between them is almost always wrong in its new home.

	THE TITLE IS A QUESTION AND THE ANSWERS ARE VERBS. "YES" and "NO" would be shorter and would make
	the player re-read the title to find out what they were agreeing to; SELL IT and KEEP IT each say
	what happens when it is pressed, which is the one thing a two-answer panel has to get right. KEEP
	IT is also the honest name for the safe answer — nothing is lost by pressing it and the word says
	so, where CANCEL would suggest something was being abandoned. ]]
SellConfig.PopupLines = {
	Title = "SELL THIS CAR?",
	Yes = "SELL IT",
	No = "KEEP IT",

	--[[ What the title becomes after the first press on a starred car — header note 7. It replaces
		the title rather than appearing under it, because the panel has to ask ONE question at a time:
		SELL THIS CAR? and ARE YOU SURE? on screen together is two questions and one pair of buttons.

		THE TITLE IS THE SECOND-LOUDEST HALF OF THIS, and that is the owner's correction on
		2026-08-31: a player who pressed a button and got a changed HEADER reads it as the button not
		having worked, because nobody reads a header they have already read once. The signal has to be
		on the thing they just pressed, which is `YesConfirm` below and the red pill it goes on. This
		line is what tells them WHY once they look up. ]]
	Confirm = "ARE YOU SURE?",

	--[[ ...and what the SELL IT pill itself says while that question is open. The pill goes RED under
		it (`SellPopupController._setYesArt`), so the button the player just pressed has changed colour
		AND changed words — which is the difference between "it is asking me again" and "it did not
		work".

		IT KEEPS "SELL IT" AND APPENDS, rather than replacing the label with CONFIRM. The verb is what
		the button does and it has not changed; the suffix is the state. Replacing it outright would
		lose the one word that says what pressing it costs, on the exact press where that matters
		most. ]]
	YesConfirm = "SELL IT - CONFIRM",

	--- Over the price while the server is answering a YES. The pills are dead for as long as this is
	--- up, so the panel has to say why rather than simply stop reacting.
	Working = "SELLING...",

	--[[ THERE IS NO `Sold` LINE ANY MORE. The panel used to stand on SOLD over the money for a beat;
		it closes at once now and the cash burst is the receipt — `Popup.RefusalHold` has the argument.

		A refusal the server sent back still needs words. These are the two a panel can actually earn —
		the car rolled off the pad while it was up, or somebody got back in — and each one closes the
		panel after a beat rather than sitting on it, because both mean the question no longer applies
		to anything. ]]
	Gone = "SALE UNAVAILABLE",
	Seated = "GET OUT OF THE CAR FIRST",

	--[[ Under the price, on the row the favourite's star uses when the car is not starred: what a
		buyer at the dealership pays for this car, i.e. its worth. It is the answer to "why would I
		wait for a buyer?" printed next to the question, so taking the lot's lower price is a choice
		the player can see they are making. Only drawn while `LotRate` is under 1. `%s` is the money. ]]
	Buyers = "BUYERS PAY ABOUT %s",
}

-- === Asking about a sale ====================================================

--- `TextScaled` would sooner break a caption onto a second line than pick a smaller font, so every
--- one-line label this feature draws goes through here first. Same rule and same fix as
--- `CarDealConfig.oneLine` and `PlotConfig.SignNonBreakingSpace`.
local NBSP = utf8.char(0xA0)

function SellConfig.oneLine(text: string): string
	return (string.gsub(text, "%s+", NBSP))
end

--[[ Is a car standing in the lot?

	THE ONE TEST, CALLED FROM BOTH SIDES. The server asks it on a press and the client asks it to
	decide what its sign says, and they must never disagree — a sign that says SELLING over a car the
	server will refuse is worse than no sign. So the rule lives here, in the file they both already
	require, and neither of them owns a copy of it.

	IT IS A BOX AND NOT A `GetPartsInPart`, because the question is "where is this car" rather than
	"what is in this space": one point against the pad's own footprint, grown by `Volume`. A spatial
	query would answer with every wheel, mirror and number plate of every car in the lot and then
	have to work out which model each belonged to.

	`position` is the car's PIVOT — the middle of it. So a car counts as in when its middle is in,
	which is the reading a player would give standing next to it, and a car dangling half over the
	entrance line does not sell by having a bumper inside. ]]
function SellConfig.isInside(pad: BasePart?, position: Vector3?): boolean
	if not (pad and position) then
		return false
	end
	local volume = SellConfig.Volume
	local offset = pad.CFrame:PointToObjectSpace(position)
	return math.abs(offset.X) <= pad.Size.X / 2 + volume.Margin
		and math.abs(offset.Z) <= pad.Size.Z / 2 + volume.Margin
		and offset.Y >= -volume.Below
		and offset.Y <= volume.Above
end

--[[ === THE LOT PAYS LESS THAN A BUYER, 2026-10-15 ==============================================

	WHAT THE LOT PAYS, as a fraction of what the car is WORTH (`MarketValueConfig`, condition and
	parts included, the number the car's own sign prints).

	WAS 1, and a playtester said the obvious thing: "if I can just sell my cars here why am I waiting
	for customers?" Buyers average about 0.99 of worth (`BuyerConfig.Bands`), so an instant sale at
	par beat waiting for one almost every time and the buyers were a feature with no reason to use it.

	0.8 IS THE MIDDLE OF THE LOW OFFER BAND (0.72 to 0.9). So about two buyers in three (FAIR, GOOD and
	GREAT) beat the lot, a bargain hunter comes out about level with it, and the lot is the place to
	cash a spare in a hurry rather than the best price in town. Lower and nearly every buyer beats it,
	which makes the lot read as a fine. Higher and the question comes back. 0.75 to 0.85 is the range
	worth testing.

	STILL ONE PRICE TABLE. This is a rate on WORTH, not a second list of prices, so `GarageConfig`'s
	header note 3 holds: what a car is worth has one answer, and the lot pays a fixed share of it.
	It touches the lot alone. A buyer's accepted offer is priced by `BuyerService` and never comes
	through here.

	1 puts the lot back at par, which is the game exactly as it was before this note.

	NOW A THIRD, LATER THE SAME DAY (Dylan's call). The lot stops being a price at all and becomes the
	place you take a car you want rid of: a spare clogging a bay, a duplicate, a wreck. Every buyer
	band beats it by more than double (the lowest LOW OFFER is 0.72), so a car worth keeping is a car
	worth waiting for a buyer on. The 0.75 to 0.85 range above was for a lot that competes with
	buyers, which this one no longer tries to. ]]
SellConfig.LotRate = 1 / 3

--[[ What the lot pays for one car, and what that car is worth, both in whole dollars.

	`id` is the car's ID out of the collection and `record` its `Garage.CarData` record: the server
	passes `GarageService:getCarData`, and a client passes `MarketValueConfig.broadcastRecord`, which
	is the same record read off the owner's broadcasts. THE SERVER PAYS THIS NUMBER AND EVERY SELL
	LABEL PRINTS IT, so a button cannot promise a price the till does not pay.

	That is the bug this replaced. The labels used to read `GarageConfig.valueOf` (a model's price in
	perfect condition) while the server paid the car's real worth, so a Silver Granvel GT that came
	home at half HP said SELL $180.0K on the button and WORTH $136.4K on its sign, and would have paid
	the smaller one.

	A body off the roster is worth nothing and so pays nothing, and `sellCars` refuses to sell one
	for that reason: a rename that stranded a car must not also be a way to lose it for nothing. ]]
function SellConfig.lotPriceOf(id: unknown, record: { [string]: any }?): (number, number)
	if type(id) ~= "string" or id == "" then
		return 0, 0
	end
	local worth = MarketValueConfig.valueOfId(id, record)
	return math.round(worth * SellConfig.LotRate), worth
end

--- The same for a client, from the owner's broadcasts. Every screen that prints a lot price calls
--- this, so none of them can read one half of a car's record and forget the other.
function SellConfig.lotPriceForOwner(owner: Player?, id: unknown): (number, number)
	if type(id) ~= "string" or id == "" then
		return 0, 0
	end
	return SellConfig.lotPriceOf(id, MarketValueConfig.broadcastRecord(owner, id))
end

--- What the lot calls a car: the same "RED CAMARO" the inventory card uses, so the two screens
--- never disagree about what a player owns. `GarageConfig.carName` is the one copy of that rule.
function SellConfig.carNameOfKey(key: unknown): string
	local body, paint = GarageConfig.parseCarKey(key)
	if not body then
		return ""
	end
	return GarageConfig.carName(body, paint)
end

return SellConfig
