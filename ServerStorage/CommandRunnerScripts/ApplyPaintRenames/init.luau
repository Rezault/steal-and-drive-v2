--[[
	ApplyPaintRenames, a Command Runner command

	Renames the roster parts the paint audit found on the wrong side of `CarPaint`'s rule, so a
	repainted car stops losing the black the artist drew on it. The list is `RENAMES` below and it
	is the whole command; everything else here is checking and reporting.

	=== WHY THIS IS A COMMAND AND NOT A NOTE IN A DOC ==========================================

	These renames live in the PLACE. `Workspace.CarSystem` is not in git, so a rename applied by
	hand in the Explorer exists only in whichever .rbxl the person who did it happened to save, and
	the next person to open an older file silently has the bug back. That is exactly what happened
	to the two M5 mirror renames, which sat unsaved in one Studio session for a day.

	Putting the list in a module makes the change reproducible: it is reviewable in a diff, it can
	be re-run against any copy of the place, and re-running it on a place that already has the
	renames is a no-op that says so. Treat `RENAMES` as the record and the place as the cache.

	=== WHY A RENAME FIXES ANYTHING ============================================================

	`CarPaint` paints a part if (1) its name carries a `body` TOKEN, or (2) it shares the shell
	panels' `TextureID`, unless (3) the name carries a hardware token. Read its header for the
	full rule. Both directions of that rule fail on parts the artist drew in a colour that happens
	to match, and the failure is invisible until the car is repainted:

	  • A part that is 100% authored black, say a splitter or a valance or a wing or a grille
	    lattice, carrying a `body` token gets painted whole, and the car loses its face.
	  • A part the artist drew in the body colour but named with a hardware token keeps its
	    original colour and reads as a wrong-coloured fleck on a repainted car.

	DROPPING `_body` IS NOT ENOUGH, and this is the trap that makes the list worth writing down.
	Most of these cars put the entire vehicle on ONE texture, so rule 2 sweeps a de-`body`-ed name
	straight back into the painted set. So nearly every `to` below carries a hardware token:
	`grille` and `interior` already existed, `matte` was added with the C7 for exposed black aero
	parts that are neither a mouth nor a cabin.

	ALL OF THAT IS DIRECTION A. A DIRECTION B ROW IS THE MIRROR IMAGE and wants the opposite token:
	the part is real bodywork wearing a hardware name, so it is being SKIPPED and needs to start being
	painted, which means the new name has to carry a `body` token. Rule 1 fires on `body` and
	`continue`s before the hardware check ever runs, so `light_01_body` paints even though `light`
	would otherwise veto it. That is why the RX7 row below adds a token rather than removing one, and
	it is the only kind of row here that makes a car paint MORE parts than before.

	THE OTHER EXCEPTION IS AN UNTEXTURED PART, and the Camaro's `detail_03_body` is the case. Rule 2
	only ever matches a MeshPart whose `TextureID` EQUALS the body texture, so a part carrying no
	texture at all cannot be swept back in and needs no token: dropping `_body` is the whole fix,
	and it puts the part back in the `detail_01`/`detail_02`/`detail_05`/`detail_06` family it was
	always meant to belong to. Check `TextureID` before deciding a row needs a token, because
	inventing one for a part that does not need it puts a lie in the Explorer for the next reader.

	=== WHAT IT TOUCHES ========================================================================

	`Workspace.CarSystem` and nothing else. That folder is the master roster. The lobby car, the
	garage podium, the dealership viewports, the published traffic shells and the rig a race spawns
	are all cloned from it, so renaming there IS renaming everywhere. `ReplicatedStorage.TrafficCars`
	is rebuilt from these rigs at runtime and needs no separate pass.

	IDEMPOTENT. A rig already carrying the new name is reported `already` and skipped. A rig where
	BOTH names exist is refused and reported `collision`, because that is a rig somebody has half
	edited by hand and guessing which one is the real part would be worse than stopping.

	`body` IS A RIG NAME AND THE LOOKUP IS CASE SENSITIVE, which matters more than it sounds
	because the roster holds `SUPRA MK4` and `Supra MK4` as two different cars. The all-caps one is
	the orange F&F rig in `PaintConfig.KeepLivery` and is never repainted; the mixed-case one is the
	tier 16 car every row here means. `WorldConfig` says the same thing next to the world 3 ladder.
	A row whose `body` is spelled differently from the rig reports `missing`, not `already`, so read
	the state column rather than the total: a run that says 34 already has matched 34 real rigs.

	=== READING THE REPORT =====================================================================

	The `painted` column is the proof, not the rename itself. After the pass the command loads a
	FRESH copy of `CarPaint`, because the plugin VM caches `require` and a stale copy from before
	the `matte` token existed would report the old answer and look like the rename had failed. It
	then asks that copy which parts it would paint on each touched rig. A part named in `RENAMES`
	still showing up in that list means the new name did not carry a veto after all, and the
	command warns.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(script.Types)

-- The master roster. See the header: these are the rigs everything else is cloned from.
local ROSTER = "CarSystem"

--[[ The renames, from `docs/paint-audit-2026-09-01.md`.

	`why` is not decoration. A name is the only record of what a mesh actually is, and every one of
	these was identified by rendering the part's mask over the stock car rather than by reading its
	name, and the names are precisely what was wrong. Keep the note when adding a row.

	ADD A ROW ONLY FOR A PART SOMEBODY HAS LOOKED AT. The audit lists 23 ownable parts in this
	class, but most are marked "not individually confirmed": the measurement proves the part is not
	body-coloured, which is enough to say the repaint is wrong about it, and not enough to pick the
	right new name.

	AND THE AUDIT CANNOT SEE INTERIORS, so its list is not the whole list. It scored every part by
	photographing the car and counting how many of that part's pixels came back the body colour, so a
	cabin tub sitting behind glass inside the shell scores almost no pixels and never reaches the
	table. `EVO` `shell_01_body` is exactly that: a dash, a console, two seats, a rear bench and the
	door cards, the most obviously wrong thing on the car once it is repainted, and absent from the
	audit entirely. A player looking through the windscreen found it. Expect more of these, and do
	not read "not in the audit" as "not broken".

	AND IT CANNOT SEE A CAR WHOSE STOCK PAINT IS BLACK, which is the Camaro, the 190E, the Pantera
	GT5, the GNX, NewSports05 and NewSports35. Authored black detail and black bodywork photograph
	identically, so every part on those six measures 100% black and the measurement means nothing.
	THE WAY THROUGH IS THE SIBLINGS, not the camera. Texture `97212220316378` is one pack's shared
	BLACK TRIM SHEET, and nine rigs use it: Charger, Challenger, Model 3, Golf GTI, M4, Senna,
	MK5 Supra, Mustang and the Camaro. On the first eight it holds only the `trim_*` parts while
	the bodywork sits on a body sheet of its own, so `bodyTextureOf` picks the body sheet and the
	trim is never painted. The Camaro is the single rig whose `shell_*_body` panels were authored
	onto the trim sheet as well, so `bodyTextureOf` resolves to the TRIM sheet and rule 2 matches
	every trim part on the car. That is why it painted 12 parts where its siblings paint 3 to 6,
	and it is why the target state below is not a judgement call: Challenger, Model 3, Golf GTI and
	Mustang all paint exactly `shell_01_body` through `shell_05_body` and nothing else.

	So when a car cannot be photographed, find the rigs that share its texture and read the rule off
	them. It is better evidence than a render, not worse: a convention held by eight cars is harder
	to misread than one car's pixels. ]]
local RENAMES: { { body: string, from: string, to: string, why: string } } = {
	{
		body = "C7",
		from = "shell_04_body",
		to = "grille_01",
		why = "grille lattice, bonnet louvre, fender vents and the quad exhaust tips, one black insert mesh",
	},
	{
		body = "C7",
		from = "bumper_01_body",
		to = "bumper_01_matte",
		why = "front lower splitter lip, 8 studs across the nose, drawn flat black",
	},
	{
		body = "GT",
		from = "shell_02_body",
		to = "interior_01",
		why = "the inner black shell: two bucket seats, dash and centre tunnel, plus both sets of light bezels, the two exhaust tips and the rear diffuser fins, one mesh",
	},

	-- The Camaro. Every `trim_*` on the rig, because its body panels share the pack's black trim
	-- sheet and rule 2 therefore matched the lot. See the header for why the siblings settle this.
	{
		body = "Camaro",
		from = "trim_03",
		to = "trim_03_matte",
		why = "the black trim layer, and the biggest single defect on the car: window surrounds, A-pillars, roof drip rail, bonnet crease, headlight bezels, both bumper apertures, all four wheel arch lips, the rocker sills and the fender vent, one mesh drawn 100% flat black",
	},
	{
		body = "Camaro",
		from = "trim_04",
		to = "trim_04_matte",
		why = "black window frame on one door",
	},
	{
		body = "Camaro",
		from = "trim_05",
		to = "trim_05_matte",
		why = "black window frame on the other door",
	},
	{
		body = "Camaro",
		from = "trim_01",
		to = "trim_01_matte",
		why = "a black trim sliver, tiny, renamed with the rest of its family so the rig reads consistently",
	},
	{
		body = "Camaro",
		from = "trim_02",
		to = "trim_02_matte",
		why = "the mirrored pair of trim_01",
	},
	{
		body = "Camaro",
		from = "detail_03_body",
		to = "detail_03",
		why = "a chrome sliver low on the body, UNTEXTURED and left at the default grey, so dropping the token is the whole fix and it rejoins detail_01/02/05/06 which were never painted",
	},
	{
		body = "Camaro",
		from = "detail_04_body",
		to = "detail_04",
		why = "the mirrored pair of detail_03_body, same reasoning",
	},

	-- Reported by a player on 2026-09-02, five cars in one batch. Each identity below was confirmed
	-- by rendering the part alone against a ghosted car, and each composition by keying the part and
	-- histogramming the stock render at those pixels. See the audit for the numbers.
	{
		body = "MK5 Supra",
		from = "grille_01_body",
		to = "grille_01",
		why = "the light grey lower intake: three big panels across the front bumper plus the crescent vent slit on each front fender, one mesh, 100% #a9a8ab and not one pixel of body colour. It is the only part on this rig that is not either bodywork or already vetoed, and it carries NO texture, so dropping the `body` token alone is enough: rule 2 needs a TextureID equal to the shell sheet and this mesh has none",
	},
	{
		body = "BRZ/FRS/GT86",
		from = "shell_05_body",
		to = "interior_01",
		why = "the inner black shell: both bucket seats, the floor and centre tunnel and the dash top, plus a front bumper canard and one fender vent. 100% black measured, so the two exterior pieces lose nothing by being called interior, and this is the same shape of mesh as the GT row above",
	},
	{
		body = "S15",
		from = "shell_02_body",
		to = "interior_01",
		why = "seats, floor, tunnel and dash, plus a front bumper lip and a fender vent. 100% black, the same mesh shape as the BRZ and the GT",
	},
	{
		body = "S15",
		from = "spoiler_01_body",
		to = "spoiler_01_matte",
		why = "the black GT rear wing, the single biggest wrongly painted part in the whole audit at 2609 measured pixels and 0.00 body fraction. `matte` rather than `interior` because it is the most exposed part on the car and calling a rear wing interior would be a lie",
	},
	{
		body = "M600",
		from = "shell_01_body",
		to = "interior_01",
		why = "the cabin: seats, dash and tunnel seen through the windscreen, plus a black vertical sliver behind the door. 100% black. This is the reported defect on the M600, a repainted car showing a body coloured interior through its own glass",
	},
	{
		body = "F40",
		from = "shell_02_body",
		to = "interior_01",
		why = "seats, floor and dash, plus both tail light bezel rings and a rear side strake. 100% black",
	},

	--[[ Worlds 3 to 5, swept 2026-09-02 rather than reported. Every row was measured the same way:
		render the car stock, key each painted mesh a flat colour, render again from the same camera,
		and histogram the stock frame under each key's mask. A mesh at 0% body colour is a rename and
		nothing else. Identity was then confirmed by lighting the mesh red on a ghosted car.

		NINE OF THE FIRST TEN ARE THE SAME MESH, which is the finding worth carrying forward: both
		seats, the floor and centre tunnel and the dash, sometimes with a small exterior black piece
		attached. It is the GT / BRZ / S15 / F40 / M600 mesh again and it takes the same name. ]]
	{
		body = "Supra MK4",
		from = "shell_03_body",
		to = "interior_01",
		why = "seats, floor, tunnel and dash, plus a black strip on the rear wing. 100% authored, 0% body colour",
	},
	{
		body = "C63 AMG",
		from = "shell_03_body",
		to = "interior_01",
		why = "the inner black shell: cabin seen through the glass, plus the grille and the rear valance, one mesh. Measured 0% body colour on a White car, which is the easiest possible case to be sure about",
	},
	{
		body = "C63 AMG",
		from = "spoiler_01_body",
		to = "spoiler_01_matte",
		why = "the black boot-lid spoiler, 100% black. `matte` and not `interior` because it is an exterior part",
	},
	{
		body = "F1 LM",
		from = "shell_01_body",
		to = "interior_01",
		why = "seats, floor, tunnel and dash. 98% black and no body colour at all",
	},
	{
		body = "F5",
		from = "shell_01_body",
		to = "interior_01",
		why = "seats, floor, tunnel and dash. 94% black",
	},
	{
		body = "720S",
		from = "shell_01_body",
		to = "shell_01_matte",
		why = "the rear diffuser and lower rear valance, an exterior part and nothing else, so `matte` rather than `interior`. 93% black, 0% body colour",
	},
	{
		body = "Gemera",
		from = "shell_01_body",
		to = "interior_01",
		why = "seats, floor, tunnel and dash. 100% black",
	},
	{
		body = "Jesko Attack",
		from = "shell_01_body",
		to = "interior_01",
		why = "seats, floor, tunnel and dash. 100% black over 4106 measured pixels, the largest wholly-authored painted mesh in worlds 3 to 5",
	},
	{
		body = "Roadster 2.0",
		from = "shell_03_body",
		to = "interior_01",
		why = "seats, floor, tunnel and dash. Not visible from the sweep's camera angle, so this row rests on the original audit measurement of 496 pixels at #070807 plus the ghosted identity render",
	},
	{
		body = "Huyara BC",
		from = "shell_01_body",
		to = "interior_01",
		why = "seats, floor, tunnel and dash, and this car's are RED rather than black. That is why it is worth naming: 0% body colour, so a repaint currently turns a red interior into the paint colour",
	},
	{
		body = "Huyara BC",
		from = "spoiler_01_body",
		to = "spoiler_01_matte",
		why = "the big rear wing, 100% black across 1704 pixels",
	},
	{
		body = "Huyara BC",
		from = "shell_04_body",
		to = "shell_04_matte",
		why = "one wing mirror: black housing with the pack's pale mint glass in it, 0% body colour. Renaming keeps both halves, which no repaint of this mesh could",
	},
	{
		body = "Huyara BC",
		from = "shell_06_body",
		to = "shell_06_matte",
		why = "the mirrored pair of shell_04_body",
	},
	{
		body = "DeLorean",
		from = "shell_03_body",
		to = "shell_03_matte",
		why = "the rear engine louvres, exterior and 98% black",
	},
	{
		body = "DeLorean",
		from = "tuning_01_body",
		to = "tuning_01_matte",
		why = "the lower valance and sill band, full length of the car, 100% black",
	},

	--[[ Worlds 3 to 5 again, 2026-09-02, this time off a player's screenshots rather than a sweep.
		The sweep could only close cars the render could measure. This is one of the two it had to
		leave open, and the fix came from being told what the answer was rather than measuring it. ]]
	{
		body = "Pantera GT5",
		from = "shell_03_body",
		to = "interior_01",
		why = "the inner shell: both seats, the dash and centre tunnel, the engine deck vents and the rear valance the exhaust sits in, all one mesh. This is the fifteenth rig carrying it. The audit could not measure this car, because 97% of it renders as one near black and authored black is then indistinguishable from paint, so identity came from ghosting the mesh red over the stock car instead. A player asked for exactly what that mesh holds: interior and exhaust keeping the stock colour",
	},

	-- DIRECTION B. These parts are bodywork and are currently NOT painted, so the `to` ADDS a `body`
	-- token instead of adding a hardware one. The first two are one defect on two rigs, a headlight
	-- part the artist drew in the car's own paint; the third is a side blade wearing a `lens` name.
	-- All three were found the same way: render the part alone over the stock car and find nothing
	-- but the body colour underneath it.
	{
		body = "S15",
		from = "light_01",
		to = "light_01_body",
		why = "the eyelid strip along the top of each headlight, one mesh. Rendered flat it is the stock car's own #d1a300 yellow and nothing else, so a repainted S15 keeps two bright yellow slashes across its nose. Reported on a White S15, where they are the only colour left on the car",
	},
	{
		body = "RX7",
		from = "light_01",
		to = "light_01_body",
		why = "both pop-up headlight LIDS, one mesh: the panel that wraps each lamp on the raised pod. Rendered flat it is 211 pixels of (128,0,0) and nothing else, which is exactly the RX7's stock body colour, so it is bodywork wearing a hardware name and a repainted RX7 keeps two dark red patches on its nose",
	},
	{
		body = "720S",
		from = "lens_clear_01",
		to = "lens_clear_01_body",
		why = "the side blade on each flank, the strake running into the rear intake. Not a lens: keyed over the stock car it is 88 pixels across four views and every one of them is the body orange (219,92,21), 100%, so a repainted 720S wears two stock orange slashes down its sides. Reported on a Lime car. The detail map is NOT the culprit and widening its cut would not have helped, because the part is never painted at all",
	},
	{
		body = "BRZ/FRS/GT86",
		from = "lens_clear_02",
		to = "lens_clear_02_body",
		why = "the row of small sockets and the round cover low on each end of the front bumper, drawn as recesses in the car's own paint. Section 2 of the audit measured it at 24 px of #091868 long before anyone reported it, and inverting the render curve puts that at atlas (26,44,106), which is the BRZ's body swatch (27,45,107) to within 3. Invisible on the stock blue car, which is the point: the artist meant these to disappear into the paint, and on a Bronze car they read as a scatter of blue dots",
	},
	{
		body = "Sian",
		from = "lens_clear_01",
		to = "lens_clear_01_body",
		why = "a sliver on each flank behind the front wheel, the same shape of defect as the 720S blade one row above. Keyed on a White car it is 70 px and all of it the body olive. Found only because the splitter strake report forced a LOW render of this car, which the top down sweep never did",
	},

	--[[ Found 2026-09-17 while adding traffic turn signals (`Modules/CarBlinkers`), which light the
		lamps on one side of a car. The BRZ looked as if it had no rear lamp per side at all, because
		its tail lamps were named as bodywork. Keyed over the stock car from behind, `shell_06_body`
		and `shell_01_body` are exactly the two round red lenses, rendered alone they are red and
		nothing else, and a White BRZ drew both of them white. `light` vetoes rule 2.

		THE BEZEL IS NOT HERE, and it looked like it belonged. `shell_03_body` is the black ring
		around both lamps and a White BRZ paints it white too, but rendered alone it carries a small
		body blue flap at the inner top of each ring, where the bezel meets the boot. Renaming it
		would trade white rings for blue flecks on every repainted BRZ. It is a detail map job. ]]
	{
		body = "BRZ/FRS/GT86",
		from = "shell_06_body",
		to = "light_red_01",
		why = "the LEFT tail lamp lens, round and dark red. A repainted BRZ drew it in the body colour, so the car lost its tail lamp, and the blinker had no left rear lamp to light",
	},
	{
		body = "BRZ/FRS/GT86",
		from = "shell_01_body",
		to = "light_red_02",
		why = "the RIGHT tail lamp lens, the mirror of the row above",
	},

}

--[[ THE ROWS THAT ARE NOT HERE. Two were applied on 2026-09-01, photographed, and reverted the
	same minute. They are written down because both looked obviously right on the evidence available
	before the picture was taken, and the next person will find that same evidence.

	=== `M5` `lens_clear_01_body` and `lens_clear_02_body` =====================================

	The turn-signal repeaters on the door mirrors. `lens_clear_NN` without `_body` is the roster
	convention on more than a hundred parts across forty rigs, and these two plus the F40's
	`lens_clear_02_body` are the only three anywhere carrying the token, so they read exactly like a
	typo somebody made once. THE NAMING ARGUMENT IS NOT ENOUGH, because a name says nothing about
	what colour the artist actually drew. Rendered flat, the M5's repeater is (0, 33, 84) and its
	body panels are (9, 33, 93): the same navy to the eye. The artist drew this lens body-coloured,
	so painting it is CORRECT, and freeing it would put a small navy fleck on every red, white or
	silver M5. That is the audit's own direction B, traded for nothing.

	Compare the WRX's `lens_clear_01`, which carries NO texture and sits at the default grey. That
	is a lens drawn as a lens. The M5's is not. A convention is a hint about intent; the render is
	the evidence, and where the two disagree the render wins.

	The M5 mirror IS wrong, just not here. The pale mint mirror GLASS is drawn on `shell_01_body`
	and `shell_06_body` together with the body-coloured cap and the black surround, so no rename can
	separate them. FIXED 2026-09-02 in the M5's detail map, which used to punch the mint because its
	rule kept only neutral swatches and mint is chromatic. The map now keys on distance from the
	car's own body colour instead, so the glass survives a repaint. Detail-map work, not a rename,
	and `assets/paint/README.md` is the account.

	=== `EVO` `shell_01_body` -> `interior_01`, applied 2026-09-01 and REMOVED 2026-09-02 =======

	This one was in the list, was correct about the thing it was aiming at, and still had to come
	out. The mesh is the EVO's cabin tub and renaming it did stop a repainted EVO having a
	body-coloured dash and seats. What the check missed is that the same mesh carries a small piece
	of EXTERIOR bodywork, a horizontal sliver at the base of the rear quarter window. Rendered alone
	the mesh is 88% (27,28,27) and 11% (22,22,22) authored black against 0.39% body yellow, and that
	0.39% is the sliver. Taking the mesh out of the paint left every repainted EVO wearing a stock
	yellow dash on its flank, which is how it was reported.

	THE FIX IS THE DETAIL MAP, WHICH DID NOT EXIST WHEN THE ROW WAS WRITTEN. The EVO has one now, so
	the mesh can go back to `shell_01_body` and be painted: the map keeps the 99% authored black and
	punches the 0.39%, so the cabin stays dark AND the sliver takes the paint. Both halves right,
	which no rename could manage. The place was renamed back on 2026-09-02 and the row deleted
	rather than inverted, because a row and its inverse in the same list would flip-flop on every
	other run.

	THE GENERAL SHAPE OF THIS: a rename is the right tool only when the mesh is ENTIRELY one thing.
	The moment a mesh is part bodywork and part authored art, a name can only ever pick the lesser
	defect, and the detail map is the tool that stops making the choice. `GT` `interior_01` was
	measured the same way and is 99.6% authored black with NO body colour at all, so it stays.

	=== `WRX STI` `shell_03_body` ==============================================================

	The mesh really is the cabin, it passes the steering-wheel test, and
	measured side-on it came back 91% authored black against a (9,24,103) navy car, which is a better
	number than some rows above. It is still wrong, because the other 9% is THE REAR WING: the whole
	blade, both uprights and the endplates sit on the same mesh as the seats. Renaming it fixes a
	silver dashboard and gives every repainted WRX a navy spoiler, which is the more visible defect on
	the car whose spoiler is the point of it.

	TWO RULES COME OUT OF THAT, and they cost nothing to follow:

	  • MEASURE FROM MORE THAN ONE ANGLE, and make one of them the rear. A wing is edge-on in a side
	    view, so it contributed almost nothing to the 9% and the number read like rounding. From
	    behind it is one of the largest painted surfaces on the car. A single orthogonal view can
	    understate a whole panel by an order of magnitude.
	  • A PART CAN BE A CABIN AND STILL NOT BE RENAMEABLE. The test asks whether a mesh wraps the
	    steering wheel, which it answers correctly; it cannot see what ELSE the artist welded into
	    the same mesh. Key the candidate over the stock car and look at the whole vehicle before
	    writing the row, not just the part you went looking for. The GT was re-checked this way and
	    is clean, all black hardware. THE EVO WAS RE-CHECKED THE SAME WAY AND PASSED, AND THE CHECK
	    WAS STILL WRONG: the wing really is its own `spoiler_01_body`, but the cabin mesh also holds
	    a sliver of EXTERIOR bodywork at the base of the rear quarter window, 0.39% of the mesh and
	    far too small to see in a keyed side view. A player found it on a white car. Measuring the
	    mesh part by part beats looking at it: render the candidate alone and histogram it against
	    the atlas, and a fraction of a percent of body colour is a number rather than a squint.

	The WRX's cabin is real and was still broken when that was written. FIXED 2026-09-02 by giving
	the WRX a detail map, which is the only tool that can hold both halves of one mesh: the cabin
	keeps its authored black AND the rear wing takes the paint, which is exactly the trade the
	rename could not make. The C7, the GT, the EVO, the RX7 and the M5 went the same way on the same
	day. That is every car anyone has REPORTED, and not the whole of the audit's second list, which
	still holds a dozen ownable cars losing more than these were. ]]

-- The dress container on a rigged car; `CarPaint` uses the same one.
local BODY_FOLDER = "Body"

--[[ Is this row trying to make the part painted, rather than to stop it being painted?

	Read off the NEW name the same way `CarPaint` reads it: a `body` word token means rule 1 fires
	and the part is painted whatever else the name says. Tokens are whole words, not substrings, so
	`bumper_01_matte` is not a match and `light_01_body` is. ]]
local function wantsPaint(name: string): boolean
	for word in string.gmatch(string.lower(name), "%a+") do
		if word == "body" then
			return true
		end
	end
	return false
end

local function dressOf(folder: Instance, bodyName: string): (Instance?, string?)
	local rig = folder:FindFirstChild(bodyName)
	if not rig then
		return nil, "no rig named " .. bodyName
	end
	local dress = rig:FindFirstChild(BODY_FOLDER)
	if not dress then
		return nil, bodyName .. " has no " .. BODY_FOLDER .. " folder"
	end
	return dress, nil
end

--[[ A copy of `CarPaint` that is definitely not the one the plugin VM cached earlier in the
	session. Requiring the module directly hands back whatever was loaded first, which on a session
	that ran before this command's token existed is a module that answers the OLD rule, and the
	report would then show the rename doing nothing. Cloning forces a fresh chunk. ]]
local function freshCarPaint(): any?
	local source = ReplicatedStorage:FindFirstChild("shared")
	source = source and source:FindFirstChild("Modules")
	source = source and source:FindFirstChild("CarPaint")
	if not source then
		return nil
	end
	local copy = source:Clone()
	copy.Parent = ReplicatedStorage
	local ok, module = pcall(require, copy)
	copy:Destroy()
	return if ok then module else nil
end

return {
	Description = "Applies the paint-audit renames to the roster, so a repaint stops eating authored detail.",
	Tags = { "cars", "art", "roster", "paint" },
	AutoRecordChanges = true,

	Arguments = {
		Body = {
			Type = "string",
			Default = "",
			Description = "Only touch this body (blank = every body in the list).",
			PlaceholderText = "blank for all",
			ClearTextOnFocus = true,
			LayoutOrder = 1,
		},
		DryRun = {
			Type = "boolean",
			Default = false,
			Description = "Report what would change without renaming anything.",
			LayoutOrder = 2,
		},
	} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()
		out:clear()

		-- The roster was parked in ServerStorage on 2026-10-13; Workspace still wins if dragged back.
		local folder = workspace:FindFirstChild(ROSTER) or game:GetService("ServerStorage"):FindFirstChild(ROSTER)
		if not folder then
			out:error(string.format("No %s in Workspace or ServerStorage.", ROSTER))
			return
		end

		local only = if type(arguments.Body) == "string" and arguments.Body ~= "" then arguments.Body else nil
		local dry = arguments.DryRun == true

		local rows, touched = {}, {}
		for _, entry in RENAMES do
			if only and entry.body ~= only then
				continue
			end
			local dress, why = dressOf(folder, entry.body)
			if not dress then
				table.insert(rows, { body = entry.body, from = entry.from, to = entry.to, state = "missing", note = why })
				continue
			end

			local src = dress:FindFirstChild(entry.from)
			local dst = dress:FindFirstChild(entry.to)

			if src and dst then
				table.insert(rows, {
					body = entry.body,
					from = entry.from,
					to = entry.to,
					state = "collision",
					note = "both names exist, refusing to guess",
				})
			elseif not src and dst then
				table.insert(rows, { body = entry.body, from = entry.from, to = entry.to, state = "already", note = entry.why })
			elseif not src then
				table.insert(rows, {
					body = entry.body,
					from = entry.from,
					to = entry.to,
					state = "missing",
					note = "no part named " .. entry.from,
				})
			else
				if not dry then
					src.Name = entry.to
				end
				touched[entry.body] = true
				table.insert(rows, {
					body = entry.body,
					from = entry.from,
					to = entry.to,
					state = if dry then "would" else "renamed",
					note = entry.why,
				})
			end
		end

		if #rows == 0 then
			out:warn(if only then string.format("Nothing in the list for %q.", only) else "The rename list is empty.")
			return
		end

		out:print(string.format("%-14s %-18s %-20s %-10s %s", "body", "from", "to", "state", "what it is"))
		local counts = {}
		for _, row in rows do
			counts[row.state] = (counts[row.state] or 0) + 1
			out:print(string.format("%-14s %-18s %-20s %-10s %s", row.body, row.from, row.to, row.state, row.note or ""))
		end

		--[[ The proof: ask a FRESH CarPaint what it would paint on every rig we touched.

			WHICH ANSWER IS "RIGHT" DEPENDS ON THE ROW'S DIRECTION, so the check reads it off the new
			name rather than assuming. A direction A row is trying to STOP a part being painted, so
			finding it still in the painted set means the new name failed to carry a veto. A
			direction B row is trying to START painting a part, so the same finding is the row
			working. A `body` token in `to` is the tell, because that is exactly what rule 1 keys on
			and it is the only way a row makes a car paint more than before. Getting this wrong once
			printed a scary warning about the RX7 row doing precisely what it was written to do. ]]
		local CarPaint = freshCarPaint()
		if CarPaint and next(touched) then
			out:print("")
			local stillWrong, didNotTake = {}, {}
			for body in touched do
				local rig = folder:FindFirstChild(body)
				local names, painted = {}, {}
				for _, part in CarPaint.parts(rig) do
					table.insert(names, part.Name)
					painted[part.Name] = true
				end
				for _, entry in RENAMES do
					if entry.body ~= body then
						continue
					end
					local label = string.format("%s.%s", body, entry.to)
					if wantsPaint(entry.to) then
						if not painted[entry.to] then
							table.insert(didNotTake, label)
						end
					elseif painted[entry.to] then
						table.insert(stillWrong, label)
					end
				end
				table.sort(names)
				out:print(string.format("%s now paints %d: %s", body, #names, table.concat(names, ", ")))
			end
			if #stillWrong > 0 then
				out:warn(
					string.format(
						"STILL PAINTED after the rename: %s. The new name does not carry a hardware token. See CarPaint's HARDWARE table.",
						table.concat(stillWrong, ", ")
					)
				)
			end
			if #didNotTake > 0 then
				out:warn(
					string.format(
						"STILL NOT PAINTED after the rename: %s. A direction B row needs a `body` token in the new name, and nothing else in the name can prevent rule 1 firing.",
						table.concat(didNotTake, ", ")
					)
				)
			end
		elseif next(touched) then
			out:warn("Renamed, but could not load CarPaint to verify the painted set.")
		end

		local summary = {}
		for state, n in counts do
			table.insert(summary, string.format("%d %s", n, state))
		end
		table.sort(summary)
		out:print("")
		out:print(
			string.format(
				"%s %s.%s",
				if dry then "Would apply:" else "Applied:",
				table.concat(summary, ", "),
				if dry then " Nothing was changed." else " Save the place, the roster is not in git."
			)
		)
	end,
} :: Types.ScriptModule
