--[[
	RarityBadgeConfig
	-----------------
	WHAT A TRAFFIC CAR IS, WRITTEN OVER IT IN ITS OWN COLOUR. The band's word in the band's colour,
	the odds of the road giving you one underneath, and nothing else: no plate, no rim, no panel.
	Type on the sky.

	It answers the one question the road never used to. A player who has not memorised 29 silhouettes
	cannot tell a Coupe from a Sports at two hundred studs, so every car looks equally worth jumping
	at and the steal stops being a decision. The colour is the tell at distance, the word is what
	teaches the colour, and the number is the reason to take the risk.

	=== IT INVENTS NOTHING. BOTH HALVES ALREADY EXIST =========================================

	This file sizes and colours some text. It does not decide what is rare, and it must never learn
	how, for the reason `RandomCarConfig`'s header gives about its own odds:

	  • THE WORD AND THE COLOUR are `Modules/CarRarity`, which is the same lookup the collection
	    index and the cars inventory print. A band retinted there moves the road with it.
	  • THE NUMBER is `TrafficConfig.chancesFor`, which reads the very weights `_pickTier` rolls a
	    spawn with, the variant split `_pickBody` uses, and this player's luck. So the road cannot
	    quote odds it does not actually run, which is the failure that makes a rarity display worse
	    than none at all.

	A second table of odds here would drift from the roll inside a month, and the drift would surface
	as "the game says 1 in 43 and I have seen four this run", which is a bug report nobody can act on.

	=== THERE IS NO BOX, AND THAT IS THE DESIGN (Dylan, 2026-09-19) ===========================

	This was first built as the Cartoony Kit's index card shrunk onto a billboard: rounded plate,
	navy rim, band-coloured face, sunburst, white type. It worked and it was rejected, and the reason
	generalises past this marker.

	A BOX IS FURNITURE AND THERE ARE TWENTY OF THEM. One mutated car can afford a panel over its roof
	because there are two or three a race. A rarity marker is on every car on the road, so a panel is
	twenty opaque rectangles between the player and the traffic they are threading, and the road is
	the thing they need to see. Bare type sits in front of the road without covering it.

	IT ALSO PUTS THE COLOUR WHERE IT IS READ. On a card the colour is the FACE and the word is white
	on top of it, so at distance the thing that survives is a coloured rectangle that says nothing.
	With no face the colour is in the LETTERS, so the same pixels carry the band and the word at
	once, and the marker degrades into a coloured smear of roughly the right shape rather than into a
	blank chip.

	WHAT PAYS FOR IT IS THE OUTLINE, and there is only one that works here. See `TextStroke`.

	=== IT IS NOT GATED ON THE NEW UI FLAG ====================================================

	`NewUIConfig.Enabled` swaps which SCREEN the client boots. This is a marker in the world, it has
	no old-UI twin to swap with, and a tester forced onto the old UI still wants to see rarity on the
	road. The type is Fredoka One so it is still the kit's voice, which is all the kit is owed by
	something with no kit art on it.
]]

local RarityBadgeConfig = {}

--[[ Master switch. Off means no billboard is built on a pooled shell at all, so the cost is zero
	rather than hidden. It is read per spawn, so flipping it in a playtest takes effect on the next
	car the road produces rather than on a rejoin. ]]
RarityBadgeConfig.Enabled = true

-- === Who gets one ===========================================================

--[[ The lowest band that earns a marker, as an index into `TrafficConfig.Bands`:
	1 Beater, 2 Sedan, 3 Coupe, 4 Sports, 5 Supercar.

	SHIPPING AT 1, WHICH IS EVERY CAR, and that is a real decision rather than the lazy default.
	A marker only on the rare cars is a louder signal, and it is the wrong one: it teaches "writing
	means take it" instead of teaching the ladder, so a player never learns that the green cars are
	worth more than the grey ones and the whole ramp collapses into two states.

	Every car also means the colour does the work at distance and the number only has to be read
	once the player is close enough to be deciding. Raise this to 3 if the road ever starts reading
	as busy; that is the knob, and it is the first one to reach for. It is cheaper than it was when
	this was a panel, because bare type does not occlude the road.

	PHONES HAVE THEIR OWN, in `Touch.MinBand` below, and it is 2. A car under the band is QUIET rather
	than bare: the collection cue can still bring its marker back. ]]
RarityBadgeConfig.MinBand = 1

--[[ THERE IS NO SWITCH FOR PUTTING ONE ON THE PLAYER'S OWN CAR, and there deliberately is not.

	`TrafficController` is the only caller, so a marker exists on road shells and nowhere else. The
	chase camera sits behind and above the car, so anything floating over its own roof is parked in
	the middle of the screen for the rest of the run, and a key here would only invite somebody to
	find that out. The mutation badge makes the same split for the same reason, and `CarMutation`'s
	`setBadge` is where it is argued out. ]]

-- === The block of type ======================================================

--[[ The billboard's size in STUDS. On a `BillboardGui` the Scale component of `Size` is studs, so
	this is a physical object that stays the same at every resolution and field of view, and shrinks
	with distance on its own. It is a BOX THE TYPE IS FITTED INTO and not a drawn shape: nothing
	paints it, so this is really "how big is the writing".

	BIGGER THAN THE PANEL IT REPLACED (11 x 3.8), because there is no longer any reason not to be.
	A panel had to stay near one car width or twenty of them tiled into a wall; type does not tile,
	it just gets easier to read, so the ceiling is now "before the word is wider than the car it is
	about" rather than anything to do with clutter.

	The arithmetic is worth keeping because it is what sets the reading range: a billboard 13 studs
	wide draws about 175 pixels across at 100 studs on a 1080p screen and about 88 at 200. The word
	survives well past the point the number stops being legible, which is the whole point of the
	colour being in the letters. ]]
RarityBadgeConfig.Size = Vector2.new(13, 4.2)

--[[ THE PHONE OVERRIDES (punch list M2, 2026-10-13). Rezault on a phone: "it's impossible to tell
	what cars are in front of me", and Aleafo's clip showed why. A billboard is sized in studs, so it
	takes the same FRACTION of every screen, and the same fraction of a six inch phone is a quarter of
	the physical size it is on a monitor. The PC numbers above were tuned at a desk.

	Read per spawn off `UserInputService.PreferredInput`, so a tablet that picks up a keyboard switches
	on the next car the road produces, and the device simulator switches with it.

	  `Scale`    multiplies `Size`. The type is fitted to the box's HEIGHT long before its width, so
	             this is how much bigger the letters get. The lift above the roof follows on its own.
	  `MinBand`  the phone's own `MinBand`. Common cars go quiet, because twenty grey words on a small
	             screen are what buried the rare ones. A quiet car is NOT unmarked: the moment the
	             collection cue has something to say about it (NEW, FASTER, or it is the car you are
	             lined up on) its marker comes back with the cue under it, so the car you are about
	             to jump still tells you what it is, and grey still gets taught. ]]
RarityBadgeConfig.Touch = {
	Scale = 1.5,
	MinBand = 2,
}

--[[ A DROP SHADOW UNDER EVERY LINE, in the outline navy, and it is what "stronger contrast" bought.

	The legacy stroke is the only outline a billboard can carry (see `TextStroke`) and it is thin, so
	a grey or gold word against a pale road had a hairline between it and the tarmac. The shadow is a
	second copy of the same text, offset by a fraction of its OWN box, so it is Scale like everything
	else here and stays the same proportion of the letters at every range. Up close it reads as the
	kit's chunky dropped outline; at distance it merges into the stroke and thickens it.

	`Offset` is a fraction of the label's width and height. The X is small because the box is far
	wider than the word it holds. Set `Enabled` false to go back to the bare stroke. ]]
RarityBadgeConfig.Shadow = {
	Enabled = true,
	Colour = Color3.fromRGB(2, 30, 56),
	Offset = Vector2.new(0.012, 0.1),
}

--[[ Studs of clear air between the top of the car's own bounding box and the BOTTOM of the type.

	Measured off the model rather than fixed, because one pooled shell is one body but the ladder is
	29 of them and an M5 is not a Civic. Note that the mutation badge's `Clearance` is a gap to its
	CENTRE rather than to its edge; the two are written differently on purpose and the arithmetic in
	`Modules/CarRarityBadge` keeps them apart. ]]
RarityBadgeConfig.Clearance = 0.9

--[[ Studs between the top of the MUTATION badge and the bottom of this, for a car wearing both.

	The rarity type stacks ABOVE the mutation badge rather than under it. Two reasons, and the second
	is the one that decided it: a mutation is the louder and rarer news so it belongs nearest the car
	it is about, and stacking this way means only this file has to know the other badge exists.
	`CarMutation` is untouched and cannot be broken by anything here. ]]
RarityBadgeConfig.Stack = 0.4

--[[ Past this many studs the engine stops drawing the type entirely.

	The mutation badge's number, and they want to match: two markers over one car that vanish at
	different ranges read as one of them being broken. It is also about right for the decision this
	is feeding, since a steal cannot be called off once it is launched and the player has to have
	read the car well before they are on it. ]]
RarityBadgeConfig.MaxDistance = 340

--[[ Drawn through whatever is in front of it. True for the mutation badge's reason: a marker you
	cannot see is not a marker, and on an open road with a car in every lane one that hides behind
	the van in front is missing exactly when the player is choosing between two cars.

	It is also what stops bare type being eaten by the car it belongs to on a rise in the road. ]]
RarityBadgeConfig.AlwaysOnTop = true

-- === What it says ===========================================================

--[[ Which lines the marker carries:

	`"Both"`   the band's word over the odds. The shipping answer, because the word is what teaches
	           the colour and the number is what makes a rare car feel rare, and a player who has
	           learned the colours stops reading the word without losing anything.
	`"Odds"`   the number alone, in the band's colour. Bigger type, less to read.
	`"Rarity"` the word alone. What to set if the odds ever start reading as a spreadsheet. ]]
-- Road labels emphasize collection decisions. Detailed odds remain available in the index/world UI.
RarityBadgeConfig.Lines = "Rarity"

--[[ How the number is written. `%s` is the N in "one in N", already grouped with commas by
	`Modules/CarRarityBadge`.

	"1 IN 43" rather than "1/43" or "2.3%". The world-select card prints percentages and is right to
	(it is a table of five worlds being compared), but a single car on the road is not being compared
	with anything: "1 in 43" is the sentence a player says out loud, and it is the one that survives
	being read in half a second at sixty studs a second. ]]
RarityBadgeConfig.OddsFormat = "1 IN %s"

--[[ Whether the number includes the player's LUCK (both upgrade ladders and the Lucky Roads pass).

	TRUE, and it has to be: luck genuinely changes what the road rolls, so a marker quoting the base
	odds would be wrong for every player who has bought any. The world-select card includes it for
	the same reason. It also means the numbers visibly improve after a purchase, which is the only
	place in the game that shows what luck bought. ]]
RarityBadgeConfig.Luck = true

--[[ Shown instead of the odds for a body on no ladder: a car from a build that renamed it, or a
	hand-edited profile. An empty string drops the line rather than printing a lie, and the word
	re-centres over the car on its own. ]]
RarityBadgeConfig.UnknownOdds = ""

-- === How it is drawn ========================================================

--[[ Fredoka One, the Cartoony Kit's face, and a `Font` object rather than an `Enum.Font` so the
	weight is explicit. It ships with Roblox, so nothing is uploaded and nothing can fail to load on
	a cold client.

	IT IS THE ONLY PIECE OF THE KIT LEFT ON THIS MARKER now the panel is gone, which makes it the
	thing that keeps the road and the menus speaking with one voice. Do not swap it for Ubuntu: that
	is the OTHER kit's face, and the two side by side is most of what "looks like a prototype" means. ]]
RarityBadgeConfig.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular)

--[[ THE RARITY WORD IS DRAWN IN THE BAND'S OWN COLOUR, which is the whole advert, so there is no
	colour for it here: `CarRarity.colourOf` is asked per car. The ramp is the one every screen in
	the game already prints, grey through green, blue and purple to gold.

	THE NUMBER IS WHITE, deliberately not the band colour too. Two lines in one colour read as one
	block and the eye has to parse the whole thing; white under colour separates them into "what it
	is" and "how rare", which is the order they are wanted in. White is also the only value that is
	equally legible under all five bands. ]]
RarityBadgeConfig.OddsColour = Color3.new(1, 1, 1)

--[[ THE OUTLINE, and with no panel behind the type it is the only thing making any of this legible.
	The kit's outline navy, `#021E38`, at full strength.

	IT IS ROBLOX'S OWN TEXT STROKE RATHER THAN A `UIStroke`, and that is forced rather than chosen. A
	`UIStroke`'s thickness is SCREEN PIXELS and a billboard's contents shrink with range, so an
	outline that looks right on a car twenty studs away swallows the letters whole on one at three
	hundred. That is the distance this marker exists for. The built-in stroke is rendered with the
	glyphs, so it holds its proportion at every range for free. It is thinner than the kit draws its
	outlines, which is the price of the marker working at the far end.

	`RichText` is on for both lines, so copy can carry its own `<font color>` or `<b>` if a future
	line wants two colours in it. Nothing writes markup today. ]]
RarityBadgeConfig.TextStroke = Color3.fromRGB(2, 30, 56)
RarityBadgeConfig.TextStrokeTransparency = 0
RarityBadgeConfig.RichText = true

--[[ The two lines, as fractions of the billboard: centre line and height.

	THE WORD IS THE BIG ONE, which is the reverse of how the panel version was laid out, and the box
	going away is what flipped it. On a coloured face the number was the only thing the face was not
	already saying. With the colour in the letters, the word is both the label AND the carrier of the
	band, so it wants the area: a big coloured word is readable as a colour at ranges where a small
	one is a speck.

	They sit high in the box with air under them. That air is not padding, it is the gap between the
	number and the roof of the car, and it stops the odds reading as a decal on the bodywork. ]]
RarityBadgeConfig.RarityRow = { Centre = 0.32, Height = 0.46 }
RarityBadgeConfig.OddsRow = { Centre = 0.755, Height = 0.31 }

--- ...and the single line a one-line marker uses, centred and taller than either of them.
RarityBadgeConfig.SoloRow = { Centre = 0.5, Height = 0.6 }

--- How much of the width a line of type may use. Almost all of it: there are no rounded ends to
--- crowd any more, and `TextScaled` will not overflow it.
RarityBadgeConfig.TextWidth = 0.98

-- === Motion =================================================================

--[[ Studs the type floats, and seconds for a full cycle. ZERO BY DEFAULT, which is the opposite of
	the mutation badge's call, and the difference is how many of them there are: a bob separates one
	marker from the car under it, and twenty bobbing out of phase is a road that will not sit still.
	It is also twenty tweens.

	Set it to 0.35 to match a mutated car if static type ever reads as a decal on the roof. ]]
RarityBadgeConfig.Bob = 0
RarityBadgeConfig.BobPeriod = 1.9

return RarityBadgeConfig
