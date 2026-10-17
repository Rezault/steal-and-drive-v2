--[[
	UIAssets
	--------
	Every image the UI is built from, sliced out of `car ui (2).psd` and uploaded 2026-08-01.

	THREE THINGS TO KNOW BEFORE YOU ADD TO THIS.

	1. THESE ARE IMAGE IDS, NOT THE IDS THE UPLOAD HANDED BACK. Open Cloud's asset endpoint is
	   called with `assetType = "Decal"`, and what it returns is a *Decal* asset id. Putting a
	   Decal id in `ImageLabel.Image` fails SILENTLY — nothing renders, `IsLoaded` stays false,
	   and no error appears anywhere. Every id below has already been run through

	       InsertService:LoadAsset(decalId)  ->  the child Decal's .Texture

	   to get the underlying Image id. If you upload more art the same way, do that step too, or
	   you will spend an afternoon on a blank screen. (The `ROBLOSECURITY` cookie path returns
	   Image ids directly and skips this, but it is a whole-account credential — not worth it.)

	2. THE ART IS TRANSLUCENT ON PURPOSE. Every navy surface — panel, inner frame, item slots,
	   the idle/hover button faces — is an 80%-opacity fill, so gameplay shows faintly through
	   the UI. The *pressed* variant of anything is the same colour at 100%. That is the kit's
	   whole state language and it is consistent across the PSD, so don't "fix" a button that
	   looks see-through. It does mean the pressed read inverts over a very dark backdrop; if
	   that ever bites, the fix is to darken the pressed FILL rather than to make idle opaque.

	3. TEXT IS NEVER BAKED IN. Titles, prices, counters, quest names and button captions were all
	   hidden before export, so every image here is art only. Anything with words on it is a
	   TextLabel over the top — see `Slice` for the insets that let these stretch cleanly.

	4. THE GLYPHS ARE NOT THIS ARTIST'S ANY MORE — 2026-08-13. Every ICON in the game was swapped to
	   the Gvesster pack (`H:\RobloxDevNVME\UIPacks\Gvesster Plus (April 2026)`, `[DEV] v6`). The
	   FRAMES are untouched: each swapped button is the artist's own frame re-rendered out of
	   `car ui (3).psd` with the glyph replaced, so notes 1-3 above still describe everything the
	   art is made of. `assets/ui/gvesster/README.md` is the full account, including the three
	   scripts that produced the PNGs — regenerate from those rather than editing a PNG.

	   Only the icons moved. PLAY keeps its gold face (no glyph to swap), and every panel, bar, pill
	   and title cap below is exactly as it was.

	   THE CAR CAUGHT UP A DAY LATER — 2026-08-14. SpawnCar was the one rail button the pass left
	   flat white, because the pack has no car icon in any of its 14 sets (checked). The owner
	   supplied one drawn in the same language, so the rail is full-colour all the way across and
	   `build_rail.py` builds all five. The results-screen car (`Results.CarMarker`) is still the
	   artist's, and has to be: it is a white silhouette the controller tints per ending.
]]

local UIAssets = {}

--- `rbxassetid://` for any id in this module.
function UIAssets.url(id: number): string
	return "rbxassetid://" .. tostring(id)
end

--[[ === THE KIT'S GLOSS, AS A GRADIENT =======================================================

	The PLAY button and all seven pills are shaded the same way and it runs the direction people
	guess wrong: **deeper at the TOP, brighter at the BOTTOM**. Measured off the stored textures
	2026-08-16, as a multiplier against each face's own brightest row:

	    PLAY          0.884 -> 1.000   (+18% bottom to top of face)
	    Pill Orange   0.842 -> 1.000   near-linear, very slightly bowed
	    Pill Blue     0.683 -> 1.000
	    TitleBar      0.941 -> 1.000   <- the caps are nearly FLAT, which is the odd one out

	That flatness is why a title bar reads as bland next to a pill or the PLAY button sitting on
	the same screen. This gradient makes up the difference: it is `pill / titlebar` at each point,
	so a cap wearing it lands on the pill's ramp rather than on a ramp somebody picked by eye.

	NEUTRAL GREY ON PURPOSE, AND ONLY EVER DARKENING. A `UIGradient` MULTIPLIES what is under it,
	so a coloured ramp shifts hue — the trap `UIGradient` already cost this project once, where a
	ramp ending on pure green zeroed the red out of an amber bar. Luma-only keypoints move the
	LEVEL and leave the artist's colour alone. And because the multiplier cannot exceed 1, the
	bottom keypoint is white (the face's own colour, untouched) and the ramp works by sinking the
	top — which is the same shape as the art, so nothing has to be brightened. ]]
local GLOSS_TOP = 0.895 -- 0.842 / 0.941, the pill's top against the cap's own
local GLOSS_MID = 0.940 -- ...and the pill's slight bow, which a straight line would miss by ~1%

--- Give an ImageLabel/ImageButton the kit's top-to-bottom gloss. Idempotent: a second call
--- updates the gradient it already made rather than stacking a second one over it.
function UIAssets.gloss(image: GuiObject): UIGradient
	local gradient = image:FindFirstChild("Gloss") :: UIGradient?
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Name = "Gloss"
	end
	--[[ 90 degrees, because a `UIGradient` runs LEFT TO RIGHT at rotation 0 and offset 0 is the
		start of that direction — so this puts offset 0 at the top, where the dark end belongs. ]]
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(GLOSS_TOP, GLOSS_TOP, GLOSS_TOP)),
		ColorSequenceKeypoint.new(0.5, Color3.new(GLOSS_MID, GLOSS_MID, GLOSS_MID)),
		ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
	})
	gradient.Parent = image
	return gradient
end

--[[ The persistent HUD: the PLAY call-to-action plus the left-hand icon rail.
	Idle / Hover / Pressed, wired to ImageButton.Image / .HoverImage / .PressedImage.

	THE RAIL'S PRESS IS TWO THINGS, NOT ONE. Note 2 in the header covers the face (same colour at
	100%); the other half is that the GLYPH TILTS CLOCKWISE. That was measured off the artist's own
	three buttons rather than guessed — each icon layer was rendered out of `car ui (2).psd` in both
	the idle and pressed columns and fitted for the rotation+scale mapping one onto the other:

	    Index  -5.9 deg, scale 1.055     (IoU 0.944, against 0.870 untransformed)
	    Quest  -8.1 deg, scale 1.005     (IoU 0.972)
	    Shop   -5.8 deg, scale 1.015     (IoU 0.947)

	The rotation is systematic in sign and roughly in size; the SCALE IS NOT (1.005 to 1.055), which
	is why only the rotation is reproduced. The centroid moves under 1.1px in all three, so it is a
	pure spin about the glyph's own centre, not a nudge. `SpawnCar` and `Teleport` below were given
	**6 deg clockwise** on 2026-08-07 to match — the median of the three, applied in Photoshop to the
	vector shape layer so the edges are re-rasterised rather than resampled.

	THE TILT SURVIVED THE GVESSTER SWAP (header note 4) and is still 6 deg clockwise about the
	glyph's own centroid. It had to be RE-DERIVED rather than copied, because the artist's tilt lived
	inside a PSD shape layer and a Gvesster icon is a PNG. The reproduction was checked against the
	one rail button that did not change: PIL's `rotate(-6)` about the alpha centroid recovers
	`RailCar_Pressed.png` from `RailCar_Idle.png` at IoU 0.962 (0.702 untransformed) with 0.28px of
	centroid drift. So "spin the source art 6 deg CW about its centroid, then scale it down" is the
	same operation the artist's own buttons already perform, and the rail still presses as one. ]]
UIAssets.HudButtons = {
	Play  = { Idle = 72523604931172, Hover = 92133201742524,  Pressed = 110582068327842 },

	--[[ GVESSTER GLYPHS ON THE ARTIST'S OWN FRAMES, 2026-08-13 — ONLY the glyph is new. Each button
		is rebuilt on ITS OWN frame group out of `car ui (3).psd` (`New Buttons/Group 53|51|52`,
		matched to a button by the glyph each one carries, not guessed: 92x111 upright book = Index,
		152x82 tilted book = Quest, 120x118 basket = Shop). All five frames in this kit are the same
		drawing and differ only in the phase of a 10%-opacity weave, so one frame for all four would
		have looked identical — using each button's own is what keeps the diff to the glyph alone.

		THE RE-RENDER WAS PROVED BEFORE ANYTHING WAS BUILT ON IT: outside the glyph it reproduces
		`RailCar_Idle.png` to ONE RGB level over 22,947 pixels, with alpha differing on 26 of them by
		at most 5. Two things make that render non-obvious and both are in
		`assets/ui/gvesster/README.md` — `Rectangle 1 copy 6`/`copy 7` are CLIPPED to the face layer,
		and `psd_tools`' own group compositing renders these groups solid white.

		Previous ids, if this ever wants reverting — the place also carries them per button on
		`OldImage`/`OldHoverImage`/`OldPressedImage` next to a `GvessterIcons` flag, which is the
		same way back the blue-HUD experiment used:
		    Index 79593739403934 / 77129958723109  / 73461633625079
		    Quest 93758041570021 / 118905340778860 / 71147567132458
		    Shop  77291594873447 / 76806076913452  / 100054722983044 ]]
	Index = { Idle = 95969414871826, Hover = 83057052713860, Pressed = 76933264054187 },   -- Items/Book
	Quest = { Idle = 83487725874659, Hover = 97248731641615, Pressed = 130291233724709 },  -- Items/Scroll
	Shop  = { Idle = 71915628139012, Hover = 93282127501776, Pressed = 112553694836941 },  -- Main/Shopping Cart

	--[[ The fourth rail button. It is still called `SpawnCar` and it opens the CARS INVENTORY now
		(2026-08-16): the SPAWN CARS page was folded into the dealership screen, which asked the same
		question off the same attribute with a different verb attached, and the rail button's `Page`
		attribute in the place was repointed at `Dealership`. The car glyph is still the right glyph
		for it, so nothing about the art moved and the key is left alone.

		THE ONLY ONE OF THESE THAT IS NOT OUT OF `car ui (2).psd` — the artist drew no car icon
		there, so the frame and the glyph both come from the older mockup's `Buttons` palette
		(`car ui.psd`, `Buttons/Group 32`).

		THAT IS SAFE, AND IT WAS CHECKED RATHER THAN ASSUMED. That palette holds the same button in
		three rows, and row 2's border shape composites BYTE-IDENTICAL in alpha to the shape the
		three buttons above are built on (203x201, same 209x207 crop) — so this is the same button,
		not a lookalike. Row 1 is a sharp-cornered variant and would NOT have matched; row 3 is the
		blue selected face, which this kit does not use for a rail. See `assets/ui/spawncar/`.

		PRESSED WAS RE-CUT 2026-08-07 to add the glyph tilt the block header describes; it had been
		face-only, which made this the one rail button that did not react to a click the way its
		neighbours do. Nothing else about it moved — the re-render was proved against the shipped
		art first (my untilted idle AND pressed came out byte-identical to `RailCar_Idle.png` /
		`RailCar_Pressed.png`, alpha and RGB, over the whole 209x207), so the tilt is the only
		difference. Alpha is byte-identical to the old pressed, so the swap cannot jitter.
		Previous id, if this ever wants reverting: `100092292019357`.

		THE RAIL IS NOW FULL-COLOUR ALL THE WAY ACROSS — 2026-08-14. This button sat out the Gvesster
		pass because the pack has no car or vehicle icon in ANY of its fourteen sets (searched for
		car/vehicle/truck/wheel/steering — `Main/Wheel` is a rainbow colour wheel), so for a day it
		was the one flat white glyph among four full-colour ones. The owner then supplied a car drawn
		in the same language — flat facets, a dark navy outline — and it is checked in at
		`assets/ui/gvesster/car-icon-transparent.png`.

		NOTHING ABOUT THE BUILD IS SPECIAL-CASED FOR IT. `build_rail.py` grew one row: the same 0.70
		of the 203px shape rect and the same 6 deg clockwise press tilt the other four take. Being a
		wide icon (1.389) it lands at 142x102 rather than their ~142x139, which is within 4% of
		Teleport's drawn area — so it carries the same weight without being scaled by hand.

		BUILT ON THIS BUTTON'S OWN FRAME, `Old/Buttons/Group 32` — the row-2 car button the shipped
		`RailCar_*.png` was cut from, matched by the 127x86 car glyph it carries. Proved before use,
		the same way every other button in the pass was: rendered empty it reproduces
		`RailCar_Idle.png` outside the glyph to ONE level in RGB and in alpha (17 px of 24,861), and
		`RailCar_Pressed.png`'s alpha is exact. Stored at 209x207, checked with
		`CreateEditableImageAsync`, so the aspect the five rail slots are authored at is unchanged.

		THE RESULTS-SCREEN CAR IS DELIBERATELY STILL THE ARTIST'S — see `UIAssets.Results.CarMarker`.
		It is a pure-white silhouette that `RaceUIController` tints per ending (`ImageColor3`, and it
		tweens to `CRASH_COLOR` on a wreck), so a full-colour car cannot go there: the tint would
		multiply into it. That is the one place the rail car and the results car stop being the same
		drawing, and it is a constraint of the marker, not an oversight.

		Previous ids, if this ever wants reverting — the place also carries them on the button's
		`OldImage`/`OldHoverImage`/`OldPressedImage` next to a `GvessterIcons` flag, the same as its
		four neighbours: `133198585988280` / `132023400531861` / `130978304639899`. ]]
	SpawnCar = { Idle = 113117793577955, Hover = 120568617528860, Pressed = 125047153812021 },

	--[[ The fifth rail button, opening TELEPORT — the world-select screen. Same story as SpawnCar
		above and built the same way: the pin glyph and its frame are `car ui.psd`,
		`Buttons/Group 35` (row 2, column 3), because `car ui (2).psd` has no pin.

		All three states were DERIVED from that one row rather than drawn, using the kit's own
		language exactly as note 2 describes — idle `#28334B` at 80%, pressed the same colour at
		100%, hover `#37455E` at 80%. All six crops (these three and the blue three below) came out
		of one 201x199 box, so nothing jitters under the cursor whichever set is live. (That box is
		the alpha bbox, `(1270,1516)-(1471,1715)` in psd space — a pixel tighter each side than
		SpawnCar's, which pads the shape rect by 3. Hence 201x199 here and 209x207 there.)

		PRESSED WAS RE-CUT 2026-08-07 for the glyph tilt, same pass and same 6 deg as SpawnCar above.
		There is no local copy of the original to diff against, so the crop was pinned against the
		LIVE texture instead: `AssetService:CreateEditableImageAsync` on the idle id reports exactly
		201x199 and a 144-point luminance+alpha grid over it matches this re-render with zero
		difference, which is what proves the new pressed lands on the same box. Alpha is byte-
		identical to the old pressed. Previous id: `135051457508275`.

		GVESSTER 2026-08-13 — `UI/Mapmark`, on THIS button's own frame: `Old/Buttons/Group 35/Setting
		frame copy 6` in `car ui (3).psd`, which is the group the README above already names. Proved
		before use, the same way everything else in this pass was: rendered at Teleport's own 201x199
		crop it matches `RailPin_Idle.png` outside the pin to ONE level in both alpha (17 px) and RGB
		(1139 px) over 29,689 pixels.

		THE ONE SWAP THAT CHANGED THE CANVAS TOO — 201x199 to 209x207, and that is a fix rather than
		a side effect. Same 203x201 button shape either way; only the padding round it changed, from
		-1px to 3px. All five rail slots are authored at aspect 1.00966, which is 209/207 — the OTHER
		four buttons' crop — so the old 201x199 texture was being stretched to fill a box cut for a
		padded one, and this button has been drawing its shape ~3% larger than its neighbours. It now
		matches them. Previous ids: `79058427846885` / `97049808069502` / `117114374281290`. ]]
	Teleport = { Idle = 74004780452552, Hover = 126313712069102, Pressed = 132319160726415 },
}

--[[ THE BLUE HUD VARIANT — a feature test, uploaded 2026-08-05, TRIED IN THE PLACE AND REVERTED
	the same day. `HudButtons` above is the canonical navy set and is what the place wears; this is
	the same five buttons plus Teleport with the face recoloured and nothing else touched. Kept
	because the art is uploaded and paid for, and this table is now the only record of the ids.

	IT IS A RECOLOUR, NOT NEW ART. The artist's blue button (`car ui.psd`, `Buttons` row 3) is a
	different icon set — cart, car, pin, gear, players, spray, cloth — and only the car overlaps our
	rail, so swapping to it would have changed what the buttons MEAN. Instead each button's own
	glyph was kept and only `Rectangle 1 copy 5` / `Rectangle 3 copy` was refilled, at the layer
	opacities the states already had. So the state language is untouched and only the hue moves:

	    idle    #0066FF @80    (the kit brand blue, same as every Title Bar)
	    pressed #0066FF @100
	    hover   #1F78FF @80    -- HSV(h, s * 0.88, min(1, v * 1.25)) of #0066FF, the same transform
	                              the Pill block below documents. Derived, never eyeballed.

	PLAY keeps its own @100 throughout, because gold was never translucent.

	HOW IT WAS SWITCHED, AND HOW TO DO IT AGAIN. The swap was made in the PLACE, not here — nothing
	in code has ever read this table, so editing it changes nothing on its own. Each swapped button
	carried `OldImage` / `OldHoverImage` / `OldPressedImage` attributes holding its navy id plus a
	`BlueVariant` flag; the revert restored the three images from those and then DELETED all four,
	so `StarterGui.MainUI.HUD` is back to the plain authored state and carries no trace of the test.
	To try blue again, write these ids onto `.Image` / `.HoverImage` / `.PressedImage` of
	`HUD.Play` and `HUD.Rail.<name>`, and leave the same four attributes behind if you want the
	one-step way back. ]]
UIAssets.HudButtonsBlue = {
	Play     = { Idle = 94414203800931,  Hover = 75471629929550,  Pressed = 99901334185627 },
	Index    = { Idle = 78961079293046,  Hover = 124167191359848, Pressed = 87498031283378 },
	Quest    = { Idle = 124021601996440, Hover = 72258873624137,  Pressed = 76688564498499 },
	Shop     = { Idle = 108195499124120, Hover = 83019425062028,  Pressed = 120969729429409 },
	SpawnCar = { Idle = 112046487243672, Hover = 121501085604677, Pressed = 94215327533982 },
	Teleport = { Idle = 78763015704928,  Hover = 91011620482142,  Pressed = 105121870280297 },
}

--[[ === THE ROBLOX TOPBAR ===================================================================

	The music mute button, and the first thing in this file that is NOT part of the artist's kit.

	IT WEARS NO FRAME, and that is what makes it the odd one out. Every other button here is a
	Gvesster glyph composited onto the artist's own panel out of `car ui (3).psd` — see
	`assets/ui/gvesster/README.md`. TopbarPlus draws its own rounded backing plate, sized and
	themed by the topbar rather than by us, so putting a second frame inside it would be a button
	drawn twice. These two are therefore the bare 256x256 pack files, uploaded as they came.

	Still the pack's `* Outline` variants, for the reason the README gives at length: the outline
	carries the same dark stroke the artist's glyphs do, so it reads as one set with the rail even
	with nothing behind it. PixFixed before upload like everything else — a glyph this small
	fringes visibly without it — and both stored at the full 256x256 (checked with
	`CreateEditableImageAsync`, so under the 1024 cap and untouched by Roblox's resampler).

	Gvesster v6 `UI/Music ON` and `UI/Music OFF`, uploaded 2026-08-20. Sources are
	`assets/ui/gvesster/MusicOn.png` / `MusicOff.png`; regenerate by re-copying from the pack, not
	by editing the PNGs.

	`On` is what the button shows while music is PLAYING — a plain note, "there is music" — and
	`Off` is the same note struck through, shown while it is muted. That is the state the icon
	names, not the action the press performs: a struck-through note on a silent game reads right,
	and it is the convention every media player already taught the player. ]]
UIAssets.Topbar = {
	MusicOn  = 125978132869233,  -- 256x256 note
	MusicOff = 118940650725498,  -- 256x256 note, struck through

	--[[ RADIO, 2026-08-24 — the car radio panel's button (`RadioPanelController`), and the second
		icon to live in the strip. Gvesster `UI/Sound ON Outline`, 256x256, uploaded and PixFixed
		exactly as the two above were (`assets/ui/gvesster/Radio.png`, and that folder's README's
		"The topbar joined" note describes the whole treatment — bare pack file, no frame, because
		TopbarPlus draws its own backing plate).

		A SPEAKER RATHER THAN A NOTE, and the pack's `UI/Music ON` was the obvious file and is
		wrong: it is already the mute button's glyph, a hand's width away in the same strip, and two
		pink notes side by side read as one control drawn twice. The speaker is blue-and-yellow
		against that note's pink, so the two are told apart at topbar size by colour before shape —
		and "sound coming out of a thing" is what this button is about, where the note is about the
		soundtrack. Same reasoning as the driving HUD rejecting `UI/Arrow Up` for JUMP.

		ONE IMAGE, NOT A PAIR. The mute button is a state (`MusicOn`/`MusicOff`); this is a panel
		opener, so TopbarPlus's selected/deselected is the PANEL being open or shut and the glyph
		does not change. What the radio is actually playing is on the caption. ]]
	Radio = 118683803226370,

	--[[ SETTINGS, 2026-08-27, and the icon that replaced the mute in the strip. Gvesster
		`Main/Settings Outline`, 256x256, the fourth bare pack file here and treated exactly as the
		three above were (`assets/ui/gvesster/Settings.png`: copied out of the pack, PixFixed, no
		frame, because TopbarPlus draws its own backing plate).

		A GEAR, WHICH IS THE ONE GLYPH IN THIS WHOLE PACK NOBODY HAS TO BE TAUGHT. It is worth
		saying out loud because the other two icons in the strip were both picked to be told apart
		from each other at topbar size, and this one was not picked at all: there is no second
		candidate for settings and no player who has to work out what it opens.

		It is pale blue against the radio speaker's blue and yellow, which is the weakest colour
		separation in the strip. That is survivable where it would not have been for the music note
		and the speaker: those two were both about SOUND and could be confused for one control drawn
		twice, where a gear and a speaker are different shapes doing different jobs.

		ONE IMAGE, NOT A PAIR, like the radio. This is a panel opener, so TopbarPlus's selected and
		deselected is the panel being open or shut and the glyph does not change.

		THE MUTE'S TWO ICONS ABOVE ARE STILL LIVE. The music button moved into the radio panel and
		is drawn there as a pill rather than a glyph, but the topbar still builds it in the one case
		the panel cannot be reached (see `TopbarController`), so neither id is dead. ]]
	Settings = 120096252161503,

	--[[ SHOP, 2026-09-02 — the door onto the Robux shop page (`Pages/Shop`), and the third real icon
		in the strip. Gvesster `Main/Shopping Bag Green Outline`, 256x256, the fifth bare pack file here
		and treated exactly as the four above were (`assets/ui/gvesster/Shop.png`: copied out of the
		pack, PixFixed, no frame, because TopbarPlus draws its own backing plate).

		A BAG RATHER THAN A CART, AND THE CART WAS THE OBVIOUS FILE AND IS WRONG. `Main/Shopping Cart`
		is already `HudButtons.Shop`, the rail button one row down, and that button opens the MARKET —
		the in-game car shop that spends dollars. Two carts a hand's width apart meaning two different
		shops is the same mistake the radio block above avoided with the note and the speaker, and it is
		worse here because both really are shops and only the currency differs.

		GREEN, WHICH IS WHAT THIS KIT PAYS MONEY OUT IN (`#0DB415`, the same green as the sell payout
		and every buy pill). It also separates from the strip's other two at topbar size by colour
		before shape: the radio speaker is blue and yellow and the settings gear is pale blue, so green
		is the one hue not yet spent up there.

		ONE IMAGE, NOT A PAIR, like the radio and the gear. This is a panel opener, so TopbarPlus's
		selected and deselected is the page being open or shut and the glyph does not change.

		DECAL 139042869588831 -> IMAGE 139251952224553, resolved through `InsertService:LoadAsset` as
		note 1 at the top of this file requires, because `upload_asset` returned a null `imageId` again.
		`CreateEditableImageAsync` reports 256x256, so this one was NOT downscaled. ]]
	Shop = 139251952224553,
}

-- The page chassis. All three pages are the same panel with a different accent title bar,
-- which is why TitleBar is keyed by colour rather than by page.
UIAssets.Page = {
	Panel      = 87386751097816,   -- 1794x1128 navy body + border
	InnerFrame = 121556514060745,  -- the inset content well (Quest row / Market detail)
	ScrollBar  = 89430632875544,
	SlotSquare = 137794441290319,  -- 326x328, the empty Index collection slot

	--[[ THE SAME SQUARE WITH THE WEAVE OFF, 2026-09-08 — what the Index page's MAPS tab draws its
		cards on, and the one place in this kit where the checker is a defect rather than the finish.

		A CHECKER SURVIVES A UNIFORM SCALE AND NOTHING ELSE. The cars tab renders `SlotSquare` at very
		nearly its drawn 1:1 square, so the weave stays a weave. A map card was the same art at 2.7:1
		the morning this was uploaded, and 9-slice answers that by stretching the middle band alone —
		which is where the checker is. The band is 282x284 of texture and the card drew it at 197x44,
		so the 25px cells arrived as 17x4 bars: banding on the face rather than texture, and worse the
		smaller the card. It is the same failure the pill block below describes ("the squashed middle
		band also moirés the art's checker overlay into vertical banding"), turned on its side.

		THE CARD WENT SQUARE THE SAME DAY AND THIS TEXTURE STAYED. Three columns instead of two makes
		it 157x148, the band draws at 0.39 by 0.35, and the cells would come out about 10x9 — the
		paragraph above no longer describes anything. What keeps the flat print is that each card now
		carries a photograph of its world behind the numbers, so the face is a backdrop for a picture
		and a weave under a road is dirt on the lens. Drop the picture and `SlotSquare` is honest for
		this again; the two ids are the same crop of the same group.

		DERIVED, NOT DRAWN. It is `Index/Group 2 copy 11` of `assets/ui/car ui (3).psd` exported at
		the identical 330x332 crop with one layer hidden — `Rectangle 1 copy 6`, the checkerboard
		Pattern fill at Overlay 10%. Every other pixel is byte-identical to the shipped square: same
		2px transparent margin, same 5px `#151D2D` border at full alpha, same 5px `#384769` rim and
		`#28334B` face at the kit's 204/255. Stored 330x332, no downscale, so `Slice.SlotSquare` and
		`Size.SlotSquare` below describe this one exactly as they describe that one.

		PixFix WAS needed here where the upgrades pass could skip it: this crop has a transparent
		margin, and Photoshop leaves white under it. The 2632 transparent pixels carry `#151D2D`
		after the pass, which is what the artist's own square carries. See `assets/ui/index/`. ]]
	MapCard    = 84431925757427,   -- 330x332, SlotSquare minus the checker
	ItemSquare = 117665260716576,  -- 383x384, the Market item portrait
	RewardFrame = 85313478243973,  -- 190x192, the Quest reward chip

	--[[ 124x74, the green banknote that goes INSIDE that chip — what a quest pays, drawn rather
		than left as an empty square.

		IT IS THE HUD CASH COUNTER'S OWN ICON, not a new drawing: the counter at the bottom-left is
		one baked image (`121983931468614`, plaque + note + nothing else), so the note could not be
		reused from there and was cut out of the mockup instead — `Old/Currency Holder/Group 15` in
		`car ui (3).psd`, which is the group that counter was flattened from. Same artwork, so the
		two cannot drift apart. See `assets/ui/quest/`.

		GVESSTER 2026-08-13 — `Currency/Cash`, and THE TWO STILL CANNOT DRIFT APART, which is the
		only reason this swap is one line. The counter had to be rebuilt anyway (it is the artist's
		upload, so its pixels cannot be read back — `CreateEditableImageAsync` refuses it), and the
		rebuild is that same `Old/Currency Holder` group re-rendered with the new note dropped into
		the exact rect `Group 15` occupied. So both are the same Gvesster art in the same slot, as
		before. The canvas went 124x74 -> 256x153 to keep the source resolution; aspect 1.676 ->
		1.673, which is what lets `Size.CashIcon` below keep driving the chip's aspect unchanged.
		Previous id: `75854101907144`. ]]
	CashIcon   = 103055187362280,

	SearchBar  = 140289194583420,
	-- Gvesster `UI/Magnifying Glass`, 2026-08-13. Square before and after, so the authored 53x53
	-- box is untouched; only the resolution rose (57x57 -> 256x256). Previous: `99014559182564`.
	SearchIcon = 118161838017358,

	--[[ Hover was DERIVED, not drawn — same story as `Pill` below, same transform, and it is the
		artist's own idle face re-exported through the identical crop, so its alpha is byte-for-byte
		the live idle's and the swap cannot jitter. `#FD4A4A -> #FF6060`. See `assets/ui/close/`.

		GVESSTER 2026-08-13 — `UI/Close Button`, which turns the kit's rounded SQUARE into a disc.
		Hover and pressed are still derived and still through the identical transform this file uses
		everywhere (`HSV(h, s*0.88, v*1.25)` up, the same line run backwards down), applied per pixel
		with the alpha channel untouched — asserted byte-identical across all three at build time,
		which is what stops the swap jittering under the cursor. Still square-canvas (98x98 ->
		256x256), so the six authored close buttons and the two code-built ones are unaffected.
		Previous ids: `115695081488850` / `111294021287789` / `111554648973635`. ]]
	Close = { Idle = 86144554047441, Hover = 127351455924011, Pressed = 133046877609540 },

	-- The three accents. GREEN IS WORN BY TWO SCREENS, not one: the Market page in the rail, and the
	-- code-built WELCOME BACK panel (`OfflineController`), which takes this chassis whole — panel,
	-- cap, Close and a green `Pill` — because green is what this kit pays money out in. Worth knowing
	-- before recolouring it; the two are never on screen together, so they can share.
	TitleBar = {
		Orange = 109630763386236,  -- INDEX
		Red    = 111111154970607,  -- QUESTS
		Green  = 90678838580855,   -- MARKET, and WELCOME BACK
	},

	-- Progress / timer bars. Track is full width; the fill is a separate image you resize.
	Bar = {
		Track      = 123747414839191,
		FillOrange = 87030206250251,  -- Index "55/80 Found"
		FillBlue   = 104512845184211, -- Quest "Time Left" and the inline quest progress
	},
}

--[[ THE CASH PACK LADDER, one glyph per rung. The SHOP page's Currency tab and nothing else.

	WHY A LADDER AND NOT ONE ICON. All six cash products share a single icon on Roblox
	(`rbxsync.lock.toml` has `88963008124478` six times, Roblox's own default), so the product art
	cannot tell the rungs apart, and the tab shipped 2026-09-03 with `Page.CashIcon` repeated on all
	six tiles. Six identical chips over a ladder that spans FIVE ORDERS OF MAGNITUDE ($15,000 to
	$1,500,000,000) is the one thing a currency shelf must not do: the whole page is a comparison,
	and the picture was the only part of a tile taking no part in it.

	GVESSTER `[DEV] Tiers Icon Pack v2`, Default Style / Cash / green, the OUTLINE variants. It is a
	different pack from the `Icon Pack v6` the rest of the game's glyphs come from, but it is the
	same artist and the same drawing language, which is why the tiles still read as a set with the
	HUD counter they top up. Default Style and not Premium (glossed) or Stud (blocky), because
	Default is the style every other glyph in this game is already in. See
	`assets/ui/gvesster/tiers/`.

	THE PACK SHIPS TWELVE STEPS AND WE USE SIX OF THEM, spread rather than taken off the bottom:

	    rung 1  $15,000        pack "Cash 1"    a single note
	    rung 2  $150,000       pack "Cash 3"    a banded brick
	    rung 3  $1,500,000     pack "Cash 5"    a stepped pile
	    rung 4  $15,000,000    pack "Cash 6"    a red sack
	    rung 5  $150,000,000   pack "Cash 9"    a silver case
	    rung 6  $1,500,000,000 pack "Cash 12"   a gold throne of money

	SILHOUETTE FIRST, THEN COLOUR. Steps 1 to 5 of the pack are all green cash in growing heaps, and
	three of those in a row is as far as "more of the same" carries. From rung 4 the OBJECT changes
	and so does its colour (green, green, green, red, silver, gold), which is what makes the ladder
	readable at the 78px these render at rather than only when you read the amount under it.

	INDEXED BY POSITION ON `CashConfig.Packs`, not by amount and not by draw order. A rung that was
	never synced is filtered out of the shelf, and the rungs that remain have to keep their own
	glyphs rather than sliding up into them. `Pages/Shop` clamps past the end, so a seventh rung
	would wear the throne until a seventh glyph is uploaded; the pack has six more steps ready.

	IMAGE IDS, RESOLVED FROM THE DECALS Open Cloud handed back. Same trap as `Pickups` below, and
	the pairs are in `assets/ui/gvesster/tiers/README.md`. All six stored 256x256, no downscale. ]]
UIAssets.CashTiers = {
	76693993929101,  -- rung 1, $15K
	96888474132701,  -- rung 2, $150K
	100775055150216, -- rung 3, $1.5M
	131621967425879, -- rung 4, $15M
	115279262385526, -- rung 5, $150M
	77022626116135,  -- rung 6, $1.5B
}

--[[ THE CAR DEALERSHIP PANEL AS IT SHIPS, 2026-08-06 — and the first block in this file that is
	NOT ours. The panel was authored whole in the Assets place (`StarterGui.UI.Car Dealership`) and
	imported into `MainUI.Pages`, so `BG` / `Slot` are the artist's own uploads and this table is a
	record of them rather than a shopping list. `Done` was the artist's too until 2026-09-02: see
	the checker note at the bottom. It supersedes `UIAssets.Dealer`, which is kept below because its
	title bar is still live — see the note there.

	WHY THE IDS ARE WORTH WRITING DOWN AT ALL, given no code reads them: they exist nowhere else
	except inside a `.Image` string in the place file. That is exactly the position the blue HUD
	variant was in, and this table is the only reason those ids still exist.

	THE HEADER IS OURS, NOT THE ARTIST'S. The imported `BG` bakes its own title cap in and drew it
	FLAT — every other page in the kit wears the woven bar. `Dealer.TitleBar` below is that woven
	bar, and it is laid straight over the flat one at the top 4.286% of the panel: the cap measures
	rows 0..29 of the 700px-tall BG render, square-cornered and edge to edge, and the woven bar is
	square-ended too, so the overlay covers it exactly with nothing peeking at the corners.

	THE TWO DONE STATES WERE DERIVED, NOT DRAWN, the same way `Pill` and `Page.Close` were and
	through the identical transform:

	    hover   = HSV(h, s * 0.88, min(1, v * 1.25))     -- the face lifts
	    pressed = HSV(h, min(1, s / 0.88), v * 0.80)     -- the same line run backwards; it sinks

	applied PER PIXEL, so the artist's weave and rim survive and only the level moves
	(`#31364A` -> `#41465D` / `#24293B` at the centre). ALPHA IS UNTOUCHED and was asserted
	byte-identical across all three, which is what stops the swap jittering under the cursor.

	Pressed is a darken rather than the "same colour at 100%" the header's note 2 describes, because
	that rule has nowhere to go here: this art is ALREADY opaque. The artist's new-kit button
	language is opacity on one face layer (`car ui (3).psd`, `New Buttons` vs `Hover Buttons`: the
	same four shapes, all filled `#28334B`, differing only in `Rectangle 1 copy 5` at 80 vs 100) —
	so on an opaque face, lift and sink are the honest translation of that language.

	THE CHECKER WAS PUT BACK 2026-09-02, and that is why all three ids changed. Every kit button
	wears a Pattern fill. In `car ui (3).psd` it is `/Old/Car dealership/Done/Rectangle 3 copy 2`:
	a 200x200 black-and-transparent checkerboard, Scale 40%, Angle 7 degrees, blend OVERLAY at
	38/255 (15%), clipped to the inner face so the rim stays clean. The artist's upload carried the
	same pattern at the same geometry, fitted out of the shipped 700x210 idle as cell 45.3px, angle
	-7 degrees, phase (22.65, 5.66), which is that 40px square scaled by 700/624. What it did not
	carry was the strength: 0.56 luminance of swing where the spec asks for 4.4, about a sixth. On
	screen the button read flat next to the PSD, which is the whole complaint.

	OVERLAY BLACK ON A DARK FACE IS A STRAIGHT MULTIPLY. For base < 0.5 the blend is `2 * b * s`,
	so an `s` of zero at opacity `a` lands on `b * (1 - a)`: the dark squares want `base * 0.85`
	and were sitting at `base * 0.981`, so ONE extra multiply of 0.867 on the dark phase put them
	on spec and nothing else in the art was touched. Measured back out of what Roblox stored,
	dark/light is 0.846 against the 0.85 asked for, a swing of 9.0 / 11.6 / 7.0 luminance units
	across idle / hover / pressed, stored 700x210 with no downscale.

	GETTING THE PIXELS TO WORK ON. The artist's idle cannot be read at all: our own uploads open in
	`CreateEditableImageAsync` and anything else answers "no permission to load asset". It came out
	of the thumbnails API instead, at 700x700, which is a FIT, so a 3.33:1 button lands on exactly
	700x210 with alpha intact. Hover and pressed were then re-derived from the NEW idle through the
	transform above rather than patched, which is what keeps the three in step; the transform was
	checked against the old pair first and reproduced them to a maximum of 3/255. The route is
	written up as note 5 of the `ui-image-upload-pipeline` memory.

	THE SUPERSEDED IDS, since this file is the only place they exist: idle `90510239170514`, hover
	`124002153928246`, pressed `128582185077693`. That is the artist's art with its own faint
	checker, and nothing draws it now. ]]
UIAssets.DealerPanel = {
	BG   = 85254101149282, -- the artist's portrait panel, title cap baked in
	Slot = 95066818637112, -- one car's card
	--- The artist's face with the kit checker restored to the PSD's Overlay 15%. See above.
	Done = { Idle = 87564436945284, Hover = 119035148020701, Pressed = 138502216343035 },
	-- The woven brand-blue cap, laid over BG's flat one. Shared with `Dealer.TitleBar` below.
	TitleBar = 139381162039442,
}

--[[ THE CARS INVENTORY's own mark — the star on a favourited card (Trello: "Lock and Favorite
	buttons").

	IT IS NOT A NEW UPLOAD. The star is `Dealer.Badge` below, the gold Gvesster star that had been
	uploaded since 2026-08-13 and that nothing had ever drawn: its own comment records that no `Badge`
	in the place has a text child and that it is decoration on a car card. It is the favourite mark on
	a car card now, which is the job it was always shaped for, and reusing it is one fewer texture to
	keep in step with the rest of the Gvesster set.

	THE MARK AND THE BUTTON ARE THE SAME GLYPH and never share a card: the mark is the STATE, drawn
	small in the corner; the chip on the card's edge is the verb, drawn lit or unlit. See the page's
	own header.

	`Lock` IS KEPT AND NOTHING DRAWS IT. It was the padlock on a locked card until 2026-08-24, when
	the lock flag was dropped and the favourite's second hold at the sell lot took over the job
	(`InventoryConfig` header note 5). The id stays for the reason every superseded id in this file
	stays — this line is the only record of it anywhere in the project, and re-uploading a texture
	nobody could find again costs more than a line of config. It is Gvesster `Main/Lock` (outline),
	letterboxed square at 256 like every other standalone icon here, Pixfixed, and stored at exactly
	what was uploaded — checked with `CreateEditableImageAsync`, which is the only honest check (see
	the note on `UIAssets.Size`). Source PNG and the script that built it are in `assets/ui/inventory/`. ]]
UIAssets.Inventory = {
	Favorite = 132265017916297, -- = Dealer.Badge, the gold star. One upload, two jobs.
	--- SUPERSEDED 2026-08-24, kept as the only record of the id. Nothing draws it; see above.
	Lock = 140084430820037, -- 256x256, Gvesster Main/Lock Outline
	--[[ The new UI's LEAVE EMPTY card (`PagesV2/Dealership`), in place of the kit's bunny (Dylan,
		2026-09-17). Gvesster v7 `UI/Blocked Outline`: "no car here", where a trash can would read as
		selling the car. Cropped flush and squared like the kit's icons, PixFixed, stored 238x238.
		Decal 116912267630119. Source PNG is `assets/ui/inventory/ClearBay.png`. ]]
	ClearBay = 71322509882887,
}

--[[ The CAR DEALERSHIP panel, sliced out of `car ui.psd` (the older, bigger mockup — NOT the
	`car ui (2).psd` everything above came from) and uploaded 2026-08-01.

	SUPERSEDED by `DealerPanel` above as of 2026-08-06 — the page now wears the imported art, and
	the frame these were positioned against is parked in the place as `Pages.DealershipOld`. Two
	reasons this block stays. `TitleBar` is still live (it is the header texture the imported panel
	was missing), and the rest is the only record of ids that are otherwise nowhere in the project.

	A DIFFERENT SHAPE FROM THE OTHER PAGES, which is the one thing to know before laying anything
	out against it: `Page.Panel` is landscape (1798x1132) and this one is PORTRAIT — 1525x2661, a
	tall column. It is a list of cars two abreast rather than a grid of many, so it does not reuse
	the page chassis above and its own metrics live in `DealerBox` below.

	The panel has no close button of its own; it has a `Done` button, which the PSD parks well
	OUTSIDE the panel (x 1971 against a panel starting at 3010). Its Y is right and its X is not,
	so the authored page centres it and keeps the artist's height. ]]
UIAssets.Dealer = {
	Panel     = 119653881900510, -- 1525x2661 navy column
	TitleBar  = 139381162039442, -- 1515x116, the #0066FF cap
	SearchBar = 121578074480385, -- 1331x113
	Card      = 131945404137107, -- 693x487, one car's frame
	--[[ Gvesster `Main/Star`, 2026-08-13 — one gold star where the artist drew a cluster of three
		grey ones. Nothing reads this, and nothing ever drew a tier INTO it either (the comment this
		replaces said so, but no `Badge` in the place has a text child), so it is decoration on a car
		card and the swap is safe. Canvas holds the old 86:77 rather than going square, because these
		are `ScaleType.Stretch` into an authored box — matching the aspect is what makes the swap
		invisible to every layout. 86x77 -> 286x256. Previous id: `96674869179624`. ]]
	Badge     = 132265017916297,
	Done      = 81375156438272,  -- 625x196
	-- Byte-for-byte the same 20x372 art as `Page.ScrollBar`, so it is the same upload rather than
	-- a second copy of one image.
	ScrollBar = 89430632875544,
}

-- Uploaded-texture sizes, with the same 1024 caveat as `UIAssets.Size` — and this panel is the
-- worst case in the file, because it is PORTRAIT, so the cap bit on HEIGHT and squeezed it to 38%.
UIAssets.DealerSize = {
	Panel = Vector2.new(586, 1023),    -- psd: 1525x2661, capped on height (x0.384)
	TitleBar = Vector2.new(1019, 78),  -- psd: 1515x116
	SearchBar = Vector2.new(1013, 86), -- psd: 1331x113
	-- Under the cap; stored as uploaded.
	Card = Vector2.new(693, 487),
	Badge = Vector2.new(286, 256), -- Gvesster; the artist's 86x77 aspect, at source resolution
	Done = Vector2.new(625, 196),
	ScrollBar = Vector2.new(20, 372),
}

UIAssets.DealerSlice = {
	Panel = 12,     -- was 32 in PSD px (x0.384)
	TitleBar = 13,  -- was 20 (x0.673)
	SearchBar = 29, -- was 38 (x0.761)
	Card = 24,
	Done = 30,
	ScrollBar = 9,
}

--[[ The dealership page container in PSD pixels: the `Main Frame` rect, which for this page is the
	whole page (nothing hangs below it the way the other pages' bottom bar does). Child positions
	are `(psdXY - Origin) / Extent`, the same convention `PageBox` sets for the landscape pages. ]]
UIAssets.DealerBox = {
	Origin = Vector2.new(3010, 24),
	Extent = Vector2.new(1521, 2657),
}

--[[ The SPAWN CARS page — the showroom list you pick a car out of to stand it in the lobby.
	Sliced out of the `Spawn Cars` group of `car ui.psd` (the older mockup, same file the dealership
	panel came from) and uploaded 2026-08-03.

	THAT PAGE IS GONE AND THIS BLOCK IS STILL LIVE — 2026-08-16. The screen was folded into the Cars
	Inventory (it asked the same question off the same attribute with a different verb attached), and
	its frame is parked in the place as `Pages.SpawnCarOld`, hidden, the same way `DealershipOld` is.
	Nothing binds it: a page is bound by having a module under `Pages` with its name, and no module
	is called that any more.

	`Panel`, `TitleBar`, `Card_*` and `ScrollBar` below are all STILL DRAWN, because the START CAR
	page wears this exact art — `UIAssets.Teleport` and the StartCar frame reuse these ids rather
	than holding a second copy (see the note under `Teleport`). Deleting this block deletes that
	page's chassis.
	`RailCar_*` was already superseded on 2026-08-14; see the `HudButtons` note above.

	THREE THINGS THAT ARE DIFFERENT FROM EVERY BLOCK ABOVE.

	1. NONE OF IT IS 9-SLICED. Every element here is exported at the exact aspect it is drawn at and
	   wired to `ScaleType.Stretch`, so the art and the box it lives in are the same shape and the
	   stretch is identity. That sidesteps the whole class of bug the `Slice` block below documents
	   — a `SliceCenter` measured in PSD pixels against a texture Roblox silently downscaled — by
	   never having a `SliceCenter` at all. It is also why there are no `Slice` entries for these.

	2. THE TWO BIG ONES WERE DOWNSCALED BEFORE UPLOAD, not after. `Panel` and `TitleBar` are wider
	   than Roblox's 1024px ceiling in the mockup, so they were resampled to 1024 locally (Lanczos)
	   and the sizes below are what was uploaded AND what Roblox stored — verified through
	   `AssetService:CreateEditableImageAsync`, which reports exactly these. Nothing here was
	   resampled behind our back.

	3. THE CARD'S THREE STATES ARE THE KIT'S OWN LANGUAGE, applied rather than invented: idle is the
	   `#28334B` face at 80%, pressed is the same colour at 100%, and hover is `#37455E` at 80% —
	   the recorded navy hover the close button and the pills already use. Idle and hover share a
	   byte-identical alpha channel (asserted at export), so the swap under the cursor cannot jitter;
	   pressed's alpha necessarily differs, because on this button opacity IS the state. ]]
UIAssets.SpawnCar = {
	Panel    = 119116996940140, -- 1794x1106 in the psd, stored 1024x633
	TitleBar = 137047383295367, -- 1787x115 in the psd, stored 1024x68 (the #0066FF cap)
	Card     = { Idle = 128844586735317, Hover = 94202734619609, Pressed = 85047121068372 },
}

-- Uploaded-texture sizes, for aspect ratios. The two capped ones carry their pre-resample size.
UIAssets.SpawnCarSize = {
	Panel = Vector2.new(1024, 633),   -- psd: 1801x1113
	TitleBar = Vector2.new(1024, 68), -- psd: 1791x119
	Card = Vector2.new(560, 490),     -- under the cap; stored as uploaded
}

--[[ The SPAWN CARS page container in PSD pixels: the `Main Frame` rect. Child positions are
	`(psdXY - Origin) / Extent`, the same convention `PageBox` and `DealerBox` set. ]]
UIAssets.SpawnCarBox = {
	Origin = Vector2.new(1382, 798),
	Extent = Vector2.new(1797, 1109),
}

--[[ The TELEPORT page — the world-select screen, three place cards wide. Sliced out of the
	`Teleport` group of `car ui.psd` (the older mockup, same file the dealership and spawn-cars
	panels came from) and uploaded 2026-08-05.

	THE CHASSIS IS NOT A SECOND COPY — `Panel` and `TitleBar` below are `SpawnCar`'s ids, reused.
	That is not an assumption: every page in the old mockup draws its `Main Frame` at the identical
	rect (1382,798)-(3179,1907) and its title bar at (1387,803)-(3174,918), so the Teleport chassis
	exported byte-for-byte the same art at the same size. Both were re-exported and compared before
	pointing these at SpawnCar's uploads, the same way `Dealer.ScrollBar` shares `Page.ScrollBar`.
	`TeleportBox` is likewise identical to `SpawnCarBox`.

	NONE OF IT IS 9-SLICED, for the reason the SpawnCar block gives: exported at the aspect it is
	drawn at and wired to `ScaleType.Stretch`, so there is no `SliceCenter` to be measured against a
	silently-downscaled texture.

	THE CARD BUTTON HAS NO PRESSED STATE. The artist drew one gold face and no press variant, and
	the PLAY button's press is positional rather than a colour — geometry this file cannot invent.
	So `Idle`/`Hover` only (`#FFC600` -> `#FFD11F`, the recorded PLAY pair), and the ImageButton is
	left with a blank `PressedImage`, which Roblox renders as `Image`.

	`PlaceImage` IS A PLACEHOLDER — the flat white rounded rect the artist parked in the card to
	reserve the thumbnail slot. Since 2026-08-28 it is the FALLBACK rather than what ships: the
	real pictures are in `UIAssets.Worlds` below, and this is what a map nobody has photographed
	still gets. ]]
UIAssets.Teleport = {
	Panel    = 119116996940140, -- shared with SpawnCar; 1794x1106 in the psd, stored 1024x633
	TitleBar = 137047383295367, -- shared with SpawnCar; 1787x115 in the psd, stored 1024x68
	Card     = 138897572859734, -- 554x925, one place's frame
	PlaceImage = 120375796193981, -- 542x776, the thumbnail placeholder
	CardButton = { Idle = 87791437057799, Hover = 139631286011831 }, -- 443x125
}

-- Uploaded-texture sizes, same 1024 caveat as `UIAssets.Size`. Only the two shared chassis pieces
-- were over the cap, and they were downscaled locally (Lanczos) before upload as SpawnCar's were.
UIAssets.TeleportSize = {
	Panel = Vector2.new(1024, 633),
	TitleBar = Vector2.new(1024, 68),
	-- Under the cap; stored as uploaded.
	Card = Vector2.new(554, 925),
	PlaceImage = Vector2.new(542, 776),
	CardButton = Vector2.new(443, 125),
}

--[[ The Teleport page container in PSD pixels: the `Main Frame` rect. Child positions are
	`(psdXY - Origin) / Extent`, the same convention `PageBox`, `DealerBox` and `SpawnCarBox` set.
	Identical to `SpawnCarBox` — see the note above. ]]
UIAssets.TeleportBox = {
	Origin = Vector2.new(1382, 798),
	Extent = Vector2.new(1797, 1109),
}

--[[ === THE WORLD THUMBNAILS, 2026-08-28 =====================================================

	What sits in the `Thumb` slot of each card on the Teleport page, replacing the artist's flat
	white `PlaceImage` rect. One per MAP, and that is the whole point of the key.

	KEYED BY MAP FOLDER NAME, NOT BY WORLD INDEX. A picture of a road is a fact about the ROAD, and
	`WorldConfig` binds a ladder to a map by folder name precisely so that swapping which road a
	ladder is driven on is a one-word change. Keying these by index would quietly break that: move
	world 3's ladder onto the arctic road and the card would still show pines. So the page looks
	this up through `WorldConfig.mapFor`, and a ladder with no map (or a map with no picture yet)
	falls back to `Teleport.PlaceImage` — the placeholder is still the honest answer for a world
	nobody has photographed.

	`FuturisticCity` GOT ITS LADDER ON 2026-08-28 (`WorldConfig` world 5) and its shot with it,
	taken by exactly the recipe below off tile 4 — the one carrying the arch over the road, which is
	the only landmark on that map and lands at 35-50% of the crop, clear of everything the card
	draws over it.

	=== HOW THEY WERE TAKEN ====================================================================

	Studio EDIT-MODE viewport grabs of the authored world tiles under `Workspace.Worlds`, not
	renders and not playtest captures. The recipe, so the next one matches:

	  • Camera at the road's `DriveCenterX`, ~35 studs above the surface (road Y is -89), looking
	    down +Z at a point ~800 studs ahead and ~20 studs lower. Default `FieldOfView` of 70 —
	    50 was tried and reads flat at card size.
	  • `StarterGui.MainUI` and `StarterGui.CarHud` disabled for the shot, or the live HUD (PLAY
	    button, cash plaque, icon rail) is baked into the picture. PUT THEM BACK.
	  • Cropped to the CENTRE of the 1230x620 viewport at 542:776, the placeholder's aspect, which
	    is 433x620. Uploaded at that size and stored at it — under the 1024 cap, so no downscale
	    (measured with `CreateEditableImageAsync` — see the note on `UIAssets.Size`).
	  • GRADED +15% saturation, +5% contrast before upload, and no further. A raw viewport grab is
	    flat next to the kit's painted plates — the game's own atmosphere hazes the far end of every
	    road — and that much lifts it without changing what the world looks like. It was worth
	    checking at the size the card actually draws (about 106x152 real pixels at four worlds):
	    +30/+12 was tried there and the skies go neon while the city goes murky.

	COMPOSE FOR THE TOP 60%. The card covers its own thumbnail three times over (measured
	2026-09-14): the band of cars and their odds sits on 63-78% of the `Thumb` and `TeleportButton`
	on 79-96%, always, and the weather pill lands across 45-61% of it when an event is running. So
	the horizon and whatever names the world (the mesas, the pines, the ice tunnel) belong above
	that, ideally above 45%, and the empty foreground road is the part that is meant to be covered.
	The card also shows the picture a few pixels narrower than it used to, `Crop`ped, to make room
	for the rims `Pages/Teleport` frames it with.

	THE SOURCE PNGs ARE IN THE REPO at `assets/ui/worlds/`, which is what makes a re-shoot a crop
	away rather than a re-hunt for the camera position. ]]
UIAssets.Worlds = {
	City = 132594818289036,
	Desert = 94884770876040,
	["Forest Mountains"] = 121581814471658,
	Arctic = 130586115203321,
	--- The IMAGE id, not the Decal id `upload_asset` hands back first (80208243501578) — that one
	--- binds to `.Image` without error and renders nothing. See the note at the top of this file.
	FuturisticCity = 111324522200463,
}

--- Uploaded-texture sizes. All five are under the 1024 cap and stored exactly as uploaded
--- (measured with `CreateEditableImageAsync`, which reports what Roblox actually kept).
UIAssets.WorldsSize = Vector2.new(433, 620)

--- The picture for a world's road, or the artist's placeholder for a map with no shot yet (and for
--- a ladder with no map at all — `WorldConfig.mapFor` returns nil for that, which is a real answer).
function UIAssets.worldThumb(map: string?): number
	return (map and UIAssets.Worlds[map]) or UIAssets.Teleport.PlaceImage
end

--[[ === THE WORLD CARDS, 2026-09-30 ==========================================================

	What the new UI's worlds page (`PagesV2/Teleport`) wears on each row: Aleafo's five painted
	cards (Discord, 2026-09-29, with a mockup of the page), cut into the two pictures the row
	draws inside its own rims.

	  Thumb      the road, 480x320. The row's picture, in place of the viewport shot above, which
	             the V1 carousel still uses.
	  Backdrop   the world's panorama at the ROW's aspect (1024x149), with a mirrored pad on its
	             left that sits under the thumbnail, so the painting starts where the road ends.
	             The page washes it out so the row's type reads over it.

	Keyed by MAP, like `Worlds`, and for the same reason. Built by `assets/ui/worlds/cards/`
	(`make_cards.py`, with Aleafo's originals in `source/`); all stored exactly as uploaded,
	checked by downloading each Image id back and diffing it against the file. ]]
UIAssets.WorldCards = {
	City = { Thumb = 90738540888404, Backdrop = 135570610504643 },
	Desert = { Thumb = 122479947536422, Backdrop = 80618739492182 },
	["Forest Mountains"] = { Thumb = 139966991457519, Backdrop = 113900402825866 },
	Arctic = { Thumb = 134160415366214, Backdrop = 128698009367153 },
	FuturisticCity = { Thumb = 104656217649609, Backdrop = 86362065296755 },
}

--[[ The worlds page's glyphs, from the Gvesster Free Icon Pack v3.1 (`make_icons.py`, PixFixed).
	`Pin` is the pack's Location Pin turned to the kit green, because it sits in front of green
	type; `Lock` is Lock White with the kit navy grown round it; `Play` is drawn, the pack has no
	triangle. `Cash` is the quest chip's banknote, so the price and the reward are one drawing. ]]
UIAssets.WorldsPage = {
	Globe = 96102056801764,
	Pin = 112872558216579,
	Lock = 89067716038082,
	Play = 116588596716318,
	Cash = UIAssets.Page.CashIcon,
}

--[[ === THE CAROUSEL ARROWS, 2026-08-28 =====================================================

	The two discs that page the world-select row (`Pages/Teleport`), and the only entry in this file
	that is not a new upload: THEY ARE THE DRIVING HUD'S OWN STEER ARROWS. Same six ids, bound the
	same way, listed here because that HUD is authored in `StarterGui.DrivingHud` and this page is
	built in code, so a code-built button needs somewhere to read them from.

	REUSED RATHER THAN DRAWN, and the reasons are the whole entry:

	  • THE KIT HAS NO OTHER ARROW. `car ui (3).psd` points at things with rings and carets and
	    contains no arrow at all (which is why `Tutorial.Arrow` had to be built from a path). These
	    two are the only arrows in the game that came out of the artist's own frame — a navy disc
	    with the kit's rim, carrying a Gvesster `UI/Arrow Left`/`Right` glyph, composited by
	    `assets/ui/gvesster/build_icons.py` against a frame proved to one RGB level.

	  • THEY ARE NEVER ON SCREEN TOGETHER. `assets/ui/gvesster/README.md` rejected `UI/Arrow Up` for
	    the driving HUD's JUMP because a third arrow in the same language a hand's width from the two
	    steering arrows reads as a third steering control. That argument is about the DRIVING HUD and
	    does not reach here: the world-select screen is a lobby menu and the driving HUD only exists
	    inside a run, so no player ever sees both at once.

	  • THREE STATES ARE ALREADY DRAWN, so the carousel gets idle/hover/pressed for free and presses
	    with the same lift-and-sink as every other button in the kit.

	348x340 rather than square — very slightly wider than tall — which is why anything that sizes one
	should read `UIAssets.ArrowSize` and not assume 1:1. Sources are `assets/ui/gvesster/Arrow*.png`;
	regenerate with that folder's script rather than editing a PNG. ]]
UIAssets.Arrow = {
	Left  = { Idle = 97764154498044, Hover = 84685682194249, Pressed = 90098463044293 },
	Right = { Idle = 92058709411173, Hover = 98910564048238, Pressed = 82730045240463 },
}

--- What Roblox stored, both faces identical. Under the 1024 cap, so no downscale to correct for.
UIAssets.ArrowSize = Vector2.new(348, 340)

--[[ THE WEATHER BADGES, one per event in `WeatherConfig.Events`, worn by the world cards on this
	same Teleport page. `WeatherConfig` names which id belongs to which event; this is where the ids
	live, because this file is the registry and a config that held its own asset numbers would be the
	second place to look for them.

	NOT OUT OF EITHER PSD. Four are Gvesster pack glyphs and two are those glyphs recoloured, built
	by `assets/ui/gvesster/build_weather.py` — which is the art, the same way `make_sunburst.py` is
	the art for the burst below. Regenerate from the script rather than editing a PNG, and Pixfix
	afterwards; the README in that folder has the whole account and the licence position on the two
	recolours.

	ALL SIX ARE 256 SQUARE, on the nose and well under the 1024 cap, so Roblox stored what was
	uploaded and there is no downscale for anything to be measured against. Square because the badge
	is a square plate drawn in code — a glyph letterboxed into a square canvas cannot shift a layout
	however tall or wide the drawing inside it is.

	THEY ARE FULL COLOUR AND ARE NEVER TINTED. `ImageColor3` multiplies (see `Results.CarMarker` for
	what that costs), and the event's own colour is expressed by the plate BEHIND the icon rather
	than by staining it. So adding a seventh event means one more PNG and one more id, and no
	decision about what colour it has to be drawn in. ]]
UIAssets.Weather = {
	Rain = 128452250548788,
	Fog = 130054821341003,
	Thunderstorm = 130249822961263,
	MeteorShower = 86906563504986,
	Sandstorm = 112655911011604,
	RushHour = 113669591569433,
}

--[[ THE ROAD PICKUPS — the glyph on the health pack and the nitro pack that float over the lanes
	(`PickupConfig`). Worn by a `BillboardGui` out in the world AND by the HUD slot the pack banks
	into, which is one image doing both jobs on purpose: a player learns the glyph off the road at
	speed, and the slot has to be the same drawing or the connection between the two is something
	they have to be told rather than something they see.

	NOT OUT OF EITHER PSD, for the weather badges' reason and by the same route: both are Gvesster
	pack glyphs, letterboxed into a square canvas by `assets/ui/pickups/build_pickups.py`, which IS
	the art. Regenerate from the script rather than editing a PNG, and Pixfix afterwards.

	NEITHER IS RECOLOURED. The pack has a red heart and a blue bolt already, and blue is the colour
	`NitroConfig` burns its flame and fills its bar in — so the two packs arrive already carrying the
	colours the rest of the game uses for those two resources, and there was no decision to make.

	Note the blue bolt is NOT the yellow one on the driving HUD's nitro BUTTON. That is deliberate
	and it is the one place two drawings of the same object are doing different jobs: the button is a
	control you press, the pack is a resource you collect, and a player holding a nitro pack while
	looking at a nitro button needs to be able to tell that those are two different things.

	BOTH ARE 256 SQUARE and full colour, never tinted — `ImageColor3` multiplies, and the pack's
	colour is expressed by the plate behind the glyph (`PickupConfig.Packs.<name>.Color`) rather than
	by staining it. So a third pack is one more PNG and one more id, with no decision about what
	colour it has to be drawn in.

	THE IDS BELOW ARE IMAGE IDS, RESOLVED FROM THE DECALS Open Cloud handed back — a Decal id fails
	SILENTLY in `.Image` (no warning, no error, just a blank square that reads as a layout bug), so
	the two are recorded separately in `assets/ui/pickups/README.md` and a re-upload can be told from
	a re-resolve:

	    Health   decal 86148967570440  ->  image 138027379444463
	    Nitro    decal 78521291474872  ->  image 128064286928984 ]]
UIAssets.Pickups = {
	Health = 138027379444463,
	Nitro = 128064286928984,
	--- `Main/Star` (Yellow Star Outline), 2026-10-13. Decal 105149672491526 resolves to this Image.
	Star = 71935112378638,
}

--[[ THE RUN-RESULTS SCREEN. One image, and the only one in this file that is not out of a mockup at
	all — neither PSD has a burst, so it was DRAWN, the way `HpTrack`/`HpTicks` were
	(`assets/ui/driving/README.md`). Its source is a script rather than a layer:
	`assets/ui/results/make_sunburst.py`, which is the art — re-run it with different constants
	instead of editing the PNG.

	PURE WHITE, so `ImageLabel.ImageColor3` picks the colour. That is the same convention the two
	gauge needles use, and it is what lets `RaceUIController` tint the burst without a second upload
	if the results screen ever wants a colour per ending.

	NEEDS NO PIXFIX PASS, unlike everything else here. The alpha-bleed fix exists because Photoshop
	writes white into fully-transparent pixels and Roblox's re-encode drags that into the edges; this
	image is white in EVERY pixel by construction, transparent ones included, so there is nothing for
	a fringe to be made of. It is also exactly 1024 square — on the cap, not over it — so Roblox
	stored it at the size it was drawn (see the `Size` warning below).

	THE MARKER IS NOT NEW ART AND MUST NOT BECOME ANY. It is the artist's own car glyph, lifted back
	out of the finished SPAWN CARS rail button (`assets/ui/spawncar/RailCar_Idle.png`) rather than
	redrawn or re-exported: the glyph is pure white on that button's navy face and every other element
	of it is dark, so it separates on brightness alone, antialiasing intact. That keeps the car on the
	results bar and the car on the rail the SAME DRAWING — which is the whole point of it being a car
	icon at all, and something a redraw would quietly break the first time the kit moved.

	THE RAIL CAR MOVED AND THIS ONE DID NOT — 2026-08-14, and that is forced rather than lazy. The
	rail now wears a full-colour car (`HudButtons.SpawnCar`), but this marker is WHITE BY DESIGN so
	`RaceUIController` can pick its colour: `_paintPayout` writes `ImageColor3` per ending and the
	wreck beat tweens it to `CRASH_COLOR`. `ImageColor3` MULTIPLIES, so a blue car under a red tint
	goes near-black — a full-colour marker cannot express an ending at all. Redrawing this one as a
	white silhouette of the new car would not help either: the new art is opaque edge to edge, so
	its silhouette is a featureless car-shaped blob where the artist's glyph has windows and wheels
	reading through. So the two cars are no longer the same drawing, on purpose. If the results
	screen ever stops tinting the marker, this is the moment to revisit it.

	It is cut to the glyph's own aspect rather than to a square canvas — see `ResultsSize`. The
	needles' square convention exists so `Rotation` pivots without offset maths, and this one never
	rotates; a square would only leave the layout dividing the visible car out of an oversized box. ]]
UIAssets.Results = {
	Sunburst = 112192466987787, -- 1024x1024, 20 rays
	CarMarker = 127499410859293, -- 256x169, the car riding the tier bar
}

-- Both under the 1024 cap, so these are what was uploaded AND what Roblox stored. `CarMarker`'s
-- aspect is what its `UIAspectRatioConstraint` is set from, so the drawn car is never squashed.
UIAssets.ResultsSize = {
	Sunburst = Vector2.new(1024, 1024),
	CarMarker = Vector2.new(256, 169),
}

--[[ THE ONBOARDING POINTER, and the one image in this file the artist did not draw.

	Nothing in `car ui (3).psd` is an arrow — the kit points at things with rings and carets — so
	this was built in Photoshop from a path and uploaded 2026-08-20, then recoloured and re-uploaded
	2026-08-26. `assets/ui/tutorial/Arrow.png` is the export and `assets/ui/tutorial/build_arrow.jsx`
	is the script that draws it; change the drawing there and re-run it rather than editing the PNG,
	the same rule the Gvesster set follows — and that script now writes `Arrow.png` directly.

	THREE THINGS ABOUT IT ARE LOAD-BEARING, because `TutorialController` rotates this image to point
	down, left, right or up depending on which side of a button it fits:

	    SQUARE, AND THE ARROW FILLS IT. 1024x1024 with the shape spanning 946 of that, so
	    `Arrow.Size` (a fraction of the viewport's short side) is the size you actually get and
	    the standoff maths in `_aimArrow` measures from a box edge the art reaches.

	    CENTRED ON THE CANVAS, so rotating the image about its own centre rotates the arrow about
	    its own and the four aims land where the geometry says they will.

	    LIT ALONG ITS OWN AXIS, not from above — dark at the tail, brightest at the tip, and the
	    contact shadow is a centred HALO rather than a drop. A drop shadow would swing round with
	    the rotation and read as a pointer lit from below the moment it pointed up. The ramp runs
	    that way for two reasons that agree: it is the direction every other shaded face in the kit
	    runs (see the gloss note at the top of this file), and it puts the brightest part of the
	    pointer on the end that is doing the pointing.

	=== IT IS GREEN, AND THAT IS NOT A TASTE CALL ============================================

	It was drawn in the brand blue first, which is the obvious choice — blue is the kit's "here"
	colour and every panel and title bar is in it. On screen it vanished. THE GAME'S GROUND IS
	CYAN: the lobby forecourt, the road, the sky. Composited against the four things this arrow
	actually gets drawn over — lobby road, navy panel, the gold PLAY face and open sky — blue
	survives one of them.

	THE DECIDING CELL IS THE GOLD ONE, and it is what rules out the whole warm half of the wheel.
	The PLAY button is `#FFC600` and it is what this pointer stands on for its first beat; an
	orange arrow over it is two warm yellows with a border between them, and a yellow one is the
	button's own colour with a border and nothing else. Both were built and composited (they are
	still in `build_arrow.jsx`) and both fail that cell on sight.

	Red passed all four and shipped 2026-08-20. Green passes all four as well and is the better
	of the two on the gold: red against `#FFC600` is a hue step, green against it is a hue step
	AND a temperature flip, so the pointer separates from the button rather than sitting in it.
	It also costs this kit nothing to say — green is already what the game pays money out in.

	The tones are the kit's own `Pill.Green` — hue and saturation sampled off the stored texture
	(`#1E7B09` core, `#3AB812` gloss) rather than picked by eye, over the same `#101B2D` border
	the red wore — with the VALUE lifted off the pill, because a pill is a button face carrying
	text and this is a pointer that has to be found from across the screen. So it sits in the
	same family as the Market page and the payout line and reads as one system with them.

	`build_arrow.jsx` still builds red, orange and yellow into a scratch folder for the next time
	this argument comes up; only the green build writes into the repo. ]]
UIAssets.Tutorial = {
	--- The IMAGE id, not the Decal id `upload_asset` also hands back (124155132333261) — that one
	--- binds to `.Image` without error and renders nothing. See the note at the top of this file.
	Arrow = 120735765341308, -- 1024x1024, points DOWN at rotation 0
}

--- Square, and what Roblox stored — measured, not assumed: this one came back at the authored
--- 1024 rather than halved like most of the kit. The controller sizes the arrow off the viewport
--- rather than off this, but a `UIAspectRatioConstraint` would read it from here.
UIAssets.TutorialSize = {
	Arrow = Vector2.new(1024, 1024),
}

--[[ THE GETAWAY TRUCK GLYPH, and the third thing in this file drawn rather than exported from the
	artist's PSD — after `Tutorial.Arrow` and the derived hover states.

	It is worn twice by `GetawayHudController` and by nothing else: once in the countdown card on
	the right of the driving screen, and again on the marker that floats over the truck itself once
	one is on the road. Both at around 40-60px, which is the size the drawing is tuned for.

	WHY IT IS WHITE AND NOT THE BRAND BLUE, which every other vehicle glyph in this kit is (see
	`Rail.SpawnCar`): the truck in the game IS white, so this is the honest drawing of it — and the
	marker is shown semi-transparent over tarmac, sky and traffic, where the kit's off-white inside
	the icon-pack's near-black outline is the highest-contrast pair this palette can make. A blue
	truck would be one more blue shape on a blue road.

	The outline navy (#0F0F3B) and the windscreen blue (#1797FD) are the rail car icon's OWN
	colours, sampled off `car-icon-transparent.png` rather than picked by eye, so the two vehicles
	in this kit are demonstrably drawn with the same pencils.

	Source and the argument for every proportion: `assets/ui/getaway/build_truck.jsx`, which is
	`assets/ui/tutorial/build_arrow.jsx`'s geometry toolkit with a truck on the end of it. Re-run it
	to change the drawing; it writes `assets/ui/getaway/Truck.png`. ]]
UIAssets.Getaway = {
	--- 1024x548, side view, facing RIGHT. Uploaded 2026-08-24; `imageId`, not the Decal id the
	--- upload also hands back — see the Decal-vs-Image trap in the project's upload notes.
	Truck = 137658412902290,
}

--- What Roblox actually STORED, checked with `CreateEditableImageAsync` rather than assumed: at
--- 1024 on the long edge it is exactly under the downscale cap, so this is the upload untouched.
--- The aspect (1.869) is what the marker's `UIAspectRatioConstraint` is driven from.
UIAssets.GetawaySize = {
	Truck = Vector2.new(1024, 548),
}

--[[ The one pill button shape in seven colours. The PSD parks these in a palette outside the Index
	panel, which is a strong hint they're meant to be picked by rarity/state at runtime rather than
	hard-assigned per screen.

	THE PILL'S STATE LANGUAGE IS NOT THE PANEL'S. Note 2 above describes the navy surfaces, where
	pressed is the same colour at full opacity. The pill does it differently and both of its states
	came out of the mockup that way: idle and pressed are the SAME colour at the same opacity, and
	pressed is purely geometric — the face drops 6px and loses 6px of height. Don't reach for the
	opacity trick here.

	HOVER WAS DERIVED, NOT DRAWN — the artist never made one, and these seven are the only images in
	this file that aren't straight out of the PSD. They are the idle faces recoloured in Photoshop
	and re-exported through the same crop, so the geometry is byte-identical to idle and the swap
	cannot jitter. The recolour is the transform the artist's own two hovers already use:

	    hover = HSV(h, s * 0.88, min(1, v * 1.25))     -- lift, and shed a little saturation

	which reproduces the recorded navy `#28334B -> #37455E` and PLAY `#FFC600 -> #FFD11F` to within
	a few units of 255. An eighth pill colour should be run through that same line rather than
	eyeballed, or it will hover a different amount from its neighbours. ]]
--[[ THE GIFT BUTTON, on every giftable SHOP card beside its price pill (`Pages/Shop._wireGift`).

	IT IS A RAIL BUTTON, AND THAT WAS FORCED RATHER THAN CHOSEN. The thing it stands next to is a
	`Pill`, and the block under `Slice` below says a pill is only ever drawn at the art's own 3.89:1
	— so a pill-shaped neighbour at the price pill's height would be most of the width of the card it
	sits on. The one SQUARE button this kit owns is the HUD rail's, and it arrives with three states
	and the 6 degree press tilt already worked out, so the gift button is one of those with a
	different glyph on it. 209x207 like all five of its neighbours, stored at what was uploaded.

	Built by `assets/ui/gvesster/build_gift.py`, which is `build_rail.py` pointed at another icon and
	writing another name: same frame render, same three state transforms, same three assertions. It
	is built on the SHOP rail button's own frame (`New Buttons/Group 52`), which is a free choice —
	all five frames in the kit are the same drawing at a different weave phase — and taken only
	because this button lives on the shop page.

	Gvesster `Free Icon Pack v3.1 (Basic)`, `Item/Gift/256px/Green Gift 1st Outline`. The OUTLINE
	variant for the reason note 4's pass gives and this file repeats everywhere: the plain files sink
	into navy. GREEN rather than the pack's blue gift — `StarterBundle`'s icon already took the blue
	one, and a green parcel on the navy face is what reads at the ~30px this renders at.

	THE BARE UN-FRAMED GLYPH IS UPLOADED TOO (`96056021769209`) AND NOTHING READS IT. It was the
	first answer to this and is recorded here rather than lost, the same way `HudButtonsBlue` keeps
	its ids: a glyph with no frame under it does not read as pressable on a card that is otherwise
	all painted buttons, and the source PNG (`assets/ui/gvesster/Gift.png`, PixFixed) is what the
	framed button is composited from anyway. ]]
UIAssets.GiftButton = { Idle = 80724985620736, Hover = 111638358986406, Pressed = 73998345702672 }

--[[ ...AND THE BARE GLYPH FOUND ITS JOB (2026-10-08): the topbar's daily reward button. The topbar draws
	its own round plate under every icon (`Topbar` above: "bare pack file, no frame"), so the framed
	`GiftButton.Idle` showed its navy square inside that circle — a plate on a plate. This is the same
	green gift with nothing under it. ]]
UIAssets.GiftGlyph = 96056021769209

UIAssets.Pill = {
	Blue   = { Idle = 105422062127555, Hover = 113077658651318, Pressed = 106495930646044 },
	Silver = { Idle = 90929760244764,  Hover = 71981963827079,  Pressed = 100917385797993 },
	Orange = { Idle = 128562412847803, Hover = 77968783436056,  Pressed = 108954042785479 },
	Sky    = { Idle = 88779436181116,  Hover = 101537520743378, Pressed = 100925546412142 },
	Red    = { Idle = 89149072709668,  Hover = 100750892892082, Pressed = 135422574092703 },
	Purple = { Idle = 136106448710116, Hover = 77887045034856,  Pressed = 94228386766275 },
	Green  = { Idle = 137803438531465, Hover = 106178988911760, Pressed = 106810705668357 },
}

--[[ 9-slice insets. `SliceCenter = Rect.new(n, n, w - n, h - n)` where `w`/`h` come from
	`UIAssets.Size` BELOW — read the warning there first, because it is the whole reason these
	numbers changed on 2026-08-02.

	ROBLOX DOWNSCALES ANY UPLOAD OVER 1024px, so a slice inset measured in PSD pixels is wrong for
	every large asset by that asset's own downscale factor. These are in UPLOADED-TEXTURE pixels,
	which is the space `SliceCenter` actually works in. The PSD-pixel value each was derived from is
	in the comment, so re-deriving from the mockup stays possible.

	Verify a change rather than trusting it — the texture is the authority, not the PSD:

	    local img = AssetService:CreateEditableImageAsync(Content.fromAssetId(id))
	    print(img.Size)   -- the number SliceCenter is measured against ]]
UIAssets.Slice = {
	Panel = 18,       -- was 32 in PSD px (x0.569)
	InnerFrame = 14,  -- was 24 (x0.603)
	TitleBar = 11,    -- was 20 (x0.573)
	SearchBar = 23,   -- was 38 (x0.596)
	BarTrack = 17,    -- was 30 (x0.566)
	BarFill = 22,     -- was 25 (x0.863)
	-- Uploaded under the cap, so these are unchanged PSD pixels...
	SlotSquare = 24,
	ItemSquare = 24,
	RewardFrame = 24,
	ScrollBar = 9,
	--[[ ...and the pill, which is here for reference and IS NOT USED, because NOTHING IN THIS GAME
		SLICES A PILL — see the block under this table. The number is the honest one if a pill ever
		has to be: the corner curve reaches 24px in from the art edge (the outer radius is 22, on a
		2px margin), so 21 cut the curve and leaked its tail into the stretched middle band. ]]
	Pill = 28,
}

--[[ === WHY NO PILL IS EVER 9-SLICED ==========================================================

	Every pill in the game was `ScaleType.Slice` until 2026-08-16, and every one of them rendered as
	a fat lozenge instead of the rounded rectangle in the mockup. The art is not a lozenge: at
	463x119 its corners are a 22px radius, about a fifth of the height.

	9-SLICE HOLDS THE CORNERS AT 1:1 TEXTURE PIXELS. That is the whole point of it, and it is exactly
	wrong for a pill, because every pill in this UI is aspect-locked to the art's own 3.89:1 and so
	only ever shrinks UNIFORMLY. The rename screen's SAVE renders 185x47 — a 0.40x scale — and Slice
	answered by keeping a ~19px corner on a 47px-tall button: a radius of 0.39 of the height where
	the drawing says 0.19. It reads as a different shape, not as a slightly-off one, and it gets
	worse the smaller the button: the dealership's flag pills render 83x21 (0.18x) and were arriving
	at very nearly a semicircle. The squashed middle band also moirés the art's checker overlay into
	vertical banding, which is the other half of what looks wrong.

	`Stretch` reproduces the artist's proportion exactly whenever the rendered aspect matches the
	texture's — which is the case the aspect constraint guarantees. Slice only earns its keep when
	the aspect changes at RUNTIME, and in this UI that is `BarFill` (0 to full width) and the
	ScrollBar thumb, nothing else. The same audit moved 27 instances back to Stretch on 2026-08-02;
	the pills were missed then only because they are built in code rather than authored.

	So: pill art goes on an `ImageButton` with a `UIAspectRatioConstraint` at
	`Size.Pill.X / Size.Pill.Y` and `ScaleType.Stretch`. A sliced-looking neighbour is not a
	precedent to copy. The authored `QuestRow.StatusButton` and the Market buy buttons still carry a
	dead `SliceCenter` from before the 2026-08-02 audit; it is inert under Stretch and left alone.

	=== ...AND A TITLE BAR HAS NOTHING TO SLICE EITHER =========================================

	Measured 2026-08-16 by reading the stored textures back: `Page.TitleBar` in all three colours
	(1024x79) and `DealerPanel.TitleBar` (1024x68) have a **corner radius of ZERO**. Their alpha is a
	plain rectangle, corner to corner. The rounding you see at the top of a page belongs to the
	PANEL, not to the cap laid over it.

	So the only thing 9-slice could do to one is pin the artist's thin painted rim at 1:1 texture
	pixels, which is a bug with no upside. The tutorial card is where it showed: its bar renders
	327x21, a 0.27x scale, and the two 11px border strips did not even fit in 21px — Roblox shrank
	them to ~10px each, leaving about one pixel of actual bar between two fat yellow bands. The
	header read as a chunky badge glued to the card instead of its cap. `Stretch` puts the rim back
	to the hairline it is drawn as. `Slice.TitleBar` below is kept as reference and, like
	`Slice.Pill`, is now read by nothing. ]]

--[[ Dimensions of the uploaded textures, so SliceCenter rects and aspect ratios can be computed
	without opening the PSD again.

	THESE ARE WHAT ROBLOX STORED, NOT WHAT WAS UPLOADED. Anything wider or taller than 1024px was
	resampled down on ingest, silently — `Panel` went in at 1798x1132 and came back 1023x644. The
	old table recorded the PSD sizes, so every derived `SliceCenter` for a large asset pointed
	outside its own image; Roblox clamped it and the far cap rendered squared while the near one
	stayed round. If you upload new art over 1024px, measure the stored texture before writing a
	size here, or downscale it yourself in Photoshop (Bicubic Sharper) so the resample is a choice
	rather than a surprise — `assets/ui/driving/README.md` did the latter for `GaugeBase`.

	The `-- psd:` note is the pre-resample size, kept because layout maths elsewhere is in PSD
	space (see `PageBox`, `DealerBox`). ]]
UIAssets.Size = {
	Panel = Vector2.new(1023, 644),    -- psd: 1798x1132
	InnerFrame = Vector2.new(1021, 298), -- psd: 1692x494
	TitleBar = Vector2.new(1024, 79),  -- psd: 1788x138
	SearchBar = Vector2.new(1008, 56), -- psd: 1692x94
	BarTrack = Vector2.new(1017, 43),  -- psd: 1798x76
	BarFill = Vector2.new(1012, 57),   -- psd: 1172x66
	-- Under the cap; stored at the size they were uploaded.
	SlotSquare = Vector2.new(330, 332),
	ItemSquare = Vector2.new(387, 388),
	RewardFrame = Vector2.new(194, 196),
	--[[ The three Gvesster swaps in this table, 2026-08-13. Each one HOLDS THE OLD ASPECT and only
		raises the resolution, because these feed `UIAspectRatioConstraint`s (`Quest` builds the
		reward chip's icon from `CashIcon`; `OfflineController` and `RenameController` size their
		close button from `Close`) — so the aspect is the contract and the pixel count is not.
		Was: CashIcon 124x74, SearchIcon 57x57, Close 98x98. ]]
	CashIcon = Vector2.new(256, 153), -- 1.673, against the artist's 1.676
	SearchIcon = Vector2.new(256, 256),
	-- The Cars Inventory's padlock. Square, under the cap, stored at what was uploaded.
	Lock = Vector2.new(256, 256),
	Pill = Vector2.new(463, 119),
	Close = Vector2.new(256, 256),
	ScrollBar = Vector2.new(20, 372),
	PlayButton = Vector2.new(455, 137),
	IconButton = Vector2.new(209, 207),
	--- The rail button's canvas again, because `GiftButton` is one. See its block above.
	GiftButton = Vector2.new(209, 207),
}

-- The page container in PSD pixels: the panel plus the bottom bar that hangs below it.
-- Every page lays out inside this box, so child positions are (psdXY - Origin) / Extent.
UIAssets.PageBox = {
	Origin = Vector2.new(1382, 778),
	Extent = Vector2.new(1798, 1224),
}

--[[ THE DEALERSHIP UPGRADES BILLBOARD, 2026-08-23 — the forecourt sign's own two textures.

	ONLY TWO OF THE SIX THINGS ON THAT BOARD ARE NEW ART. The blue woven cap is `SpawnCar.TitleBar`,
	the level bar is `Bar.Track` + `Bar.FillBlue`, and the UPGRADE button is a `Pill` — all reused as
	they are, because the board is a page of this kit and should be made of the kit's own parts.
	What the kit could not supply is a PANEL and a CARD at this board's proportions, and that is the
	whole reason these two exist.

	WHY AN ASPECT NEEDED ITS OWN EXPORT rather than stretching one of the pages'. Every rectangle in
	this kit is drawn with SQUARE corners and gets its 5px `#151D2D` border and 5px `#384769` inner
	rim from LAYER STYLES, not from the fill — all three shapes in the stack are the same `#28334B`.
	Layer styles do not scale with a transform, so the artist's own shapes can be resized to any
	proportion and the border stays 5px on all four sides. Stretching the UPLOADED page panel
	instead (1.62 -> 1.19) would have thinned its left and right borders to 73% of its top and
	bottom, which is the kind of wrongness that reads as "off" without being nameable.

	So each was rebuilt in Photoshop from the artist's own group, scaled to the board's real
	geometry, and exported: the panel from `car ui (3).psd` `Market/Main Frame`, the tile from
	`Index/Group 2 copy 11`. Both keep the checkerboard weave (Overlay @10%, 25px cell) and the 80%
	face that every navy surface in this kit wears.

	NEITHER IS 9-SLICED, for the reason the `SpawnCar` block gives: each is exported at the exact
	aspect it is drawn at and wired to `ScaleType.Stretch`, so the stretch is identity and there is
	no `SliceCenter` to be measured against a texture Roblox silently downscaled.

	PIXFIX WAS DELIBERATELY SKIPPED. Its job is repairing the RGB Photoshop leaves under
	fully-transparent pixels, and these two have none — the alpha histogram is 0 at level 0, because
	both are opaque rectangles that fill their own canvas. Checked rather than assumed. ]]
UIAssets.Upgrades = {
	Panel = 124092571615299, -- 1544x1296 as built, stored 1024x859 (downscaled locally, Lanczos)
	Tile  = 130944492670017, -- 720x508, under the cap; stored as uploaded

	--[[ The wide two-line plot sign, added 2026-08-23 for the GARAGE / COMING SOONsign on every
		plot's garage door. Same recipe and the same reason for its own export: at 2.42:1 it is a
		third aspect the kit did not have, and stretching either of the two above into it would have
		put its side borders at twice the weight of its top and bottom.

		It lives in this table rather than a new one because it is the same drawing serving the same
		family of plot signage, and because the coming-soon sign is now the only other thing on a plot
		wearing the kit chassis. ]]
	SignPanel = 133773155106243, -- 746x308, under the cap; stored as uploaded
	--[[ The entrance banner over each plot's gate. Fourth aspect off the same drawing, and the one
		that needed no stretch at all: the sign's canvas is exactly 1080x264.

		IT IS THE ONE ROUNDED PANEL IN THIS KIT, and that is the host geometry's call rather than a
		drift from the artist. The banner is bolted to a CHAMFERED beam whose ends slope away, and a
		square corner runs straight into that slope; the sign wore a 26px `UICorner` for exactly this
		reason before it ever had real art. The billboard stays square because it sits in a square
		neon aperture, and the garage-door sign stays square because a flat door has no shape to
		answer to. Roundness here follows the mesh, not the mockup.

		A `UICorner` could NOT do this. It clips the element, so it would slice straight through the
		5px border drawn into the texture and leave four bare corners of face colour. The radius is
		drawn INTO the art instead: the border and the inner rim each follow the curve, which is what
		the artist's own square version does along a straight edge. Built by
		`assets/ui/upgrades/make_rounded_banner.py` from the square export — regenerate from that
		rather than editing the PNG.

		The Panel still needs a matching `UICorner` on top of this, for its opaque BACKGROUND only:
		see the note in `BuildDealershipSigns`. Square export kept at 119612830769310 in case the
		beam is ever re-modelled flat. ]]
	BannerPanel = 125179874570896, -- 1080x264 as built, stored 1024x250; rounded at 26px

	--[[ The billboard's pictures, added 2026-09-17 when the board was redrawn off Dylan's mockup
		(a picture per upgrade, left of its copy). Keyed by `UpgradeConfig` key so both faces look
		them up the same way.

		Gvesster `Free Icon Pack v3.1 (Basic)`, the `1st Outline` variants, cropped flush to their
		art and PixFixed: `assets/ui/upgrades/icons/prep_icons.py` names each source. Image ids,
		resolved from the Decal uploads and checked by downloading them back (alpha byte-identical).
		The header's car is the HUD rail's own bare car, `BuildHudV2`'s Cars cell. ]]
	Icons = {
		Luck = 125712722863083, -- Clover, 240x254
		Customers = 137870583603198, -- Add Player, 253x236
		Jump = 127937623868998, -- Red Coil, 174x254
		Floor2 = 80905697288694, -- Blue House, 256x225
	},
	HeaderIcon = 91216847938226, -- car-icon-transparent, PixFixed, 1024x741
}

-- Uploaded-texture sizes, same 1024 caveat as `UIAssets.Size`. Verified through
-- `AssetService:CreateEditableImageAsync`, which reports what Roblox actually stored.
UIAssets.UpgradesSize = {
	Panel = Vector2.new(1024, 859),
	Tile  = Vector2.new(720, 508),
	SignPanel = Vector2.new(746, 308),
	BannerPanel = Vector2.new(1024, 250),
}

--[[ === THE WORKSHOP'S ROW ICONS, 2026-09-30 ==================================================

	A picture at the left of each row of the workshop (`BuildWorkshopV2`'s `RowTemplate.Icon`),
	the same idea as the upgrade board's `UIAssets.Upgrades.Icons`. Keyed by row: `Repair`, `Paint`,
	and each part by its `CustomizeConfig.Parts` `Key`. A part with no entry here shows no icon.

	Gvesster, the navy-outlined variants so all five share one rim: `Free Icon Pack v3.1` Hammer,
	Fire (`Fire 1st Outline_1`, the one with the navy rim) and Settings 1, and `Icon Pack v7` Artist
	Palette. THE TYRE IS NOT THE PACK'S: no set has a tyre (its two `Wheel`s are prize wheels), so
	`assets/ui/workshop/icons/draw_tires.py` draws one in the pack's style, off its gear. Cropped
	flush by `prep_icons.py`, PixFixed, and each Image id downloaded back and checked (alpha
	byte-identical). Drawn bare, no well behind them (`kit-dark-well-needs-its-blue-strip`). ]]
UIAssets.Workshop = {
	Icons = {
		Repair = 123842627176221, -- Hammer, 252x254
		Paint = 70533259748262, -- Artist Palette, 252x208
		Engine = 132958750401220, -- Fire, 220x250
		Transmission = 101887741754404, -- Gear, 253x247
		Tires = 105733223242792, -- drawn tyre, 240x240
	},
}

--[[ === THE WORKSHOP'S CARD LAYOUT, 2026-09-30 ================================================

	The art for `BuildWorkshopCards`, the layout behind `NewUIConfig.WorkshopCards` (Aleafo's
	reference: a navy card per option with a coloured icon tile). `Glyphs` go on the tiles, the header
	and CHANGE CAR: white with a navy rim, so one drawing reads on every tile colour, which the kit
	paints (the tiles are its square button, recoloured). Keyed like `Workshop.Icons`: `Repair` and
	`Paint` by row, each part by its `CustomizeConfig.Parts` `Key`, plus the header's `Wrench` and
	CHANGE CAR's `Car`. `Platform` is the glowing turntable the car stands on.

	Drawn, not from a pack (no pack has these): `assets/ui/workshop/glyphs/draw_glyphs.py`, PixFixed,
	each Image id downloaded back and checked (alpha byte-identical). Platform's transparent pixels are
	the glow's cyan, not black, because its glow fades out and PixFix finds no edge to bleed from. ]]
UIAssets.WorkshopCards = {
	Glyphs = {
		Wrench = 75626913536253, -- 190x189
		Repair = 75626913536253,
		Paint = 79788895373292, -- spray can, 186x246
		Engine = 130715719814696, -- 237x169
		Transmission = 131294087298466, -- gear, 254x254
		Tires = 74612628937012, -- 256x256
		Car = 112358761366998, -- 252x168
	},
	Platform = 112335372711851, -- 1024x320
}

--[[ === THE NPC SPEECH BUBBLE, 2026-08-25 ====================================================

	What a customer in a dealership says it in (`CustomerService._say`). Before this it was a flat
	`#364157` Frame with a `UICorner` and a `#0066FF` `UIStroke` round it, which is the same
	rounded-rect-and-neon-outline every other game draws and the reason the plot signage was
	rebuilt in the first place.

	IT IS ONE TEXTURE, BODY AND TAIL TOGETHER, and the tail is the whole point of it. A bubble
	with no tail is a sign that happens to be near somebody; the tail is what makes the sentence
	belong to the person under it, and it cannot be a second instance laid under the panel because
	the border has to run round the join rather than across it.

	NOT AN EXPORT OF THE KIT GROUP, and this is the one place the upgrades recipe does not carry
	over. That pass leaned on "layer styles do not scale, so the border stays 5px at any aspect" —
	true of the `#384769` inner rim, which IS a style, and NOT true of the `#151D2D` outer border,
	which is geometry: `Market/Main Frame`'s `Rectangle 1` is simply drawn 5px larger than the three
	shapes stacked on it. At the page's 1.59:1 the difference does not show. At this bubble's
	3.34:1 it does — a straight resize lands that border at 2.5px on the sides against 1.2px top
	and bottom. So `assets/ui/bubble/make_bubble.py` paints both rims onto a distance transform of
	the silhouette instead, at an even 5 + 5 pixels all the way round the tail included, and lifts
	the FACE straight out of the artist's own export at a whole weave period's offset so the
	checker and the fill are still his pixels. Regenerate from that script, not by hand.

	IT SHIPS OPAQUE, which is the one value in it that is not the artist's. The kit's 80% face is a
	property of a panel laid over a DIMMED BACKDROP; this one is laid over the game in daylight, and
	at 80% the dealership billboard behind a customer read straight through the sentence they were
	saying — the first upload was at 80% and had to be redone. The kit's own answer is already on
	the plot (`BuildDealershipSigns` puts an opaque `BackgroundColor3` behind the entrance banner
	for this reason); that needs a rectangle to sit behind, and this shape has a tail, so it is
	baked in. Only the alpha moved: the export is unpremultiplied, so the colour underneath is still
	`#28334B`.

	`BodyFraction` is the part of the texture the text lays out in — everything below it is tail.
	It lives here rather than in `CustomerConfig` because it is a property of the drawing. ]]
UIAssets.Bubble = {
	Panel = 108741017295090, -- 1024x398, stored as uploaded
}

UIAssets.BubbleSize = {
	Panel = Vector2.new(1024, 398),
}

--- Rows 0..306 of the 398 are the body; the remaining 91 are the tail.
UIAssets.BubbleBodyFraction = 307 / 398

--[[ === THE STEAL FLIGHT'S GROUND RETICLE, 2026-08-25 =========================================

	Where the arc says you are coming down (`StealController._updateMarker`). It replaces a 16-stud
	`Neon` cylinder — a filled disc of flat colour laid on the road — and the shape changed for a
	reason rather than for a coat of paint: a filled circle hides the roof you are steering onto at
	the exact moment you are reading it, and an outline says the same thing without covering the
	target.

	WHITE ON TRANSPARENT, TINTED AT RUNTIME. `StealConfig.Marker` has three states and they are one
	upload with `ImageColor3` written on it, not three textures to keep in step.

	Built by `assets/ui/steal/make_marker.py`. Four arcs rather than a ring, gapped on the
	diagonals, with a tick on each cardinal so a reticle passing over the next lane's car reads as
	off to one side rather than merely near. ]]
UIAssets.Steal = {
	Marker = 118791634483673, -- 1024x1024, stored as uploaded
}

UIAssets.StealSize = {
	Marker = Vector2.new(1024, 1024),
}

--[[ === THE DEALERSHIP WAYPOINT PIN, 2026-08-31 ===============================================

	The marker that hangs over YOUR lot once you have driven away from it
	(`DealershipMarkerController`, `PlotConfig.Marker`). One texture, carrying three things: the
	plate, the ring the headshot sits in, and the tail that points at the ground.

	IT IS A NEW SHAPE RATHER THAN THE SPEECH BUBBLE, which is the first question to ask before any
	upload. The bubble was tried and it is the wrong drawing for this job: it is 3.34:1 landscape,
	built to hold a sentence, and this holds a FACE. A face in a landscape bubble is a small circle
	with a lot of empty panel beside it, at the one moment the marker is competing with a whole
	city for the player's attention.

	NOTHING IS BAKED IN BUT THE RING. The headshot is an `ImageLabel` the controller points at
	`rbxthumb`, and the distance under it is a `TextLabel`, which is note 3 above holding. What the
	texture draws is the `#0066FF` ring around the socket, so the pin reads as a miniature of the
	dealership sign it is pointing at rather than as an unrelated widget.

	Built by `assets/ui/marker/make_pin.py`, out of the same kit face the speech bubble is cut
	from. `assets/ui/marker/README.md` is the account of it. ]]
UIAssets.Marker = {
	Pin = 73570943842158, -- 700x1024, stored as uploaded
}

UIAssets.MarkerSize = {
	Pin = Vector2.new(700, 1024),
}

--[[ Where the two live things sit inside `Marker.Pin`, in fractions of the texture.

	Here rather than in `PlotConfig` for `BubbleBodyFraction`'s reason: these are properties of the
	drawing, so they change when the drawing does, and `make_pin.py` is the file they are measured
	off. The socket's drawn ring is 274px at its outer edge and 14px thick, so the headshot is
	520px across and the ring shows all the way round it at every size the marker draws at.

	THE CAPTION BAND IS WIDE AND SHORT ON PURPOSE, and that is the whole guard against `TextScaled`
	putting "412 studs" on two lines. Wrapping only wins when a second line can be drawn taller
	than the single line the box's width allows, which needs a box that is tall relative to its
	text; at 0.886 by 0.146 of a 104px marker it is not. No non-breaking spaces are needed here,
	and none are wanted: they poison the string Roblox captures for translation. ]]
UIAssets.MarkerBox = {
	--- Centre and diameter of the headshot. The diameter is given on both axes because the socket
	--- is a circle and the texture is not square.
	HeadshotCentre = Vector2.new(0.5, 352 / 1024),
	HeadshotSize = Vector2.new(520 / 700, 520 / 1024),
	--- Centre and size of the distance line, in the face between the socket and the plate's
	--- bottom rim.
	CaptionCentre = Vector2.new(0.5, 732 / 1024),
	CaptionSize = Vector2.new(620 / 700, 150 / 1024),
}

--[[ === THE BUYER SIGN'S THREE PIECES, 2026-10-15 ==============================================

	The redesigned offer sign (`BuyerConfig.Bubble.Design`, built by `BuildBuyerSignDesigns`) is kit
	parts throughout, and these are the three things the Cartoony Kit does not draw. Made by
	`assets/ui/buyer/build_buyer_sign.py`, PixFixed, Image ids (not the Decal ids).

	`ArrowTint` is WHITE so one upload serves both directions: `ImageColor3` tints it red under value
	and green over it, and a rotation of 180 points it up. `Person` is the avatar seat's fallback for a
	buyer with no Roblox user behind them; a friend's face is an `rbxthumb` headshot instead. `Clock`
	is the footer's, the Gvesster v6 "Clock Outline" (`assets/ui/gvesster/Clock.png`), which Dylan
	asked for in place of the kit's red timer. (A chevron, 107589686218362, went with design A.) ]]
UIAssets.BuyerSign = {
	ArrowTint = 119554516263030, -- 160x160, points DOWN at rotation 0
	Person = 91850622972732, -- 256x256
	Clock = 87525150759633, -- 256x256, PixFixed (decal 97872919022693)
}

return UIAssets
