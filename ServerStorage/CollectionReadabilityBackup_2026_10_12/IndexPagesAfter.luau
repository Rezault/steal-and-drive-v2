--[[
	Index page  (client)
	--------------------
	The collection screen, in two tabs. CARS is one slot per car in the game, browsed a world at a
	time, with a search field over the grid and "n/m STOLEN" along the bottom. MAPS is one card per
	world showing how far down that road you have ever got.

	THIRTEEN THINGS TO KNOW BEFORE CHANGING ANY OF IT.

	1. THE FOUR SLOTS IN THE PLACE ARE A LAYOUT SAMPLE, NOT THE GRID, and they stay that way. The
	   real grid is built at runtime in PlayerGui: the first sample slot is cloned once per car into
	   a UIGridLayout and `Slots` is emptied. StarterGui keeps its readable four-slot mock-up, the
	   panel still reads right in the Explorer, and nothing structural has to be authored twice.

	   Nothing in this page edits the place. That is deliberate while three terminals share one
	   Studio: a runtime clone can't collide with anybody's Explorer work and can't be half-applied.

	2. THE GRID METRICS ARE MEASURED OFF THAT SAMPLE, NOT TYPED IN. Cell size, card SHAPE, column
	   gap and the grid's left/top all come from the sample slots; the viewport's bottom is the
	   panel's inner edge inset by the same margin the artist left between the search bar and the
	   first row. Nudge a sample slot in the Explorer and the real grid follows it, and there is no
	   second copy of the PSD's numbers in here to drift out of step with the art.

	   The row gap is the COLUMN gap converted through the page's aspect ratio, so the gaps are
	   square in pixels rather than square in scale.

	   THE COLUMN COUNT IS THE ONE EXCEPTION, and it is deliberate — see `GRID_COLUMNS`. The samples
	   still say how WIDE the row is and what SHAPE a card in it is; the constant says how many ways
	   that row is cut, and a cell's height is derived from its own width so the shape survives it.

	   Cells are laid out in OFFSET, recomputed from the viewport's AbsoluteSize. Scale would be
	   ambiguous inside a ScrollingFrame (canvas or window?) and circular against an automatic
	   canvas; offsets are neither, and they let the canvas height be computed exactly rather than
	   waited on for a frame.

	3. THE ROSTER IS EVERY CAR IN EVERY WORLD, LISTED A WORLD AT A TIME. It is assembled at load by
	   walking `WorldConfig.Worlds` and taking each one's `TrafficConfig.bodiesFor` — the same lists
	   the road rolls its traffic off — so a car added to a world appears here with no edit, and every
	   slot remembers which world it came from. It is deliberately the roster rather than the player's
	   lot: this screen is what there IS to steal, and the lot holds six.

	   ONE SLOT IS BUILT PER CAR, ONCE, AND THE WORLD IS A FILTER. All 29 exist from the first frame
	   and the pager only changes which of them are `Visible` — exactly what the search box does,
	   which is why paging costs a layout pass rather than a rebuild and why the two compose without
	   either knowing about the other. Both tests are the one line in `_applyFilter`.

	   THIS USED TO BE ONE WORLD'S EIGHT, and the note here said that choosing was a design call
	   rather than a bug to quietly fix. It has been made: the collection is the whole game, because
	   a collection screen that hides three quarters of the collection cannot do the thing it is for.
	   What survives of the other half of that call is the COUNT, which is still per world — four
	   ladders to finish rather than one long one, and the world you are in is the one the screen
	   opens on.

	4. OWNERSHIP IS REAL NOW, AND THIS PAGE DID NOT HAVE TO CHANGE FOR IT. It was written against a
	   Player attribute that nothing wrote — the house pattern for replicated player state
	   (`GarageConfig.CashAttribute` / `RateAttribute`, read the same way by GarageHudController)
	   rather than a remote — and said the name belonged in GarageConfig the day a service filled it
	   in. `GarageService` now keeps `Garage.Owned`, every body ever banked, and mirrors it onto
	   `GarageConfig.OwnedAttribute`. So the only edit here was deleting a local constant.

	   Note what it is NOT: the profile's `Garage.Cars` is the six-bay dealership LOT, whose
	   `Collected` field is the os.time() a bay's income was last collected. A car can be owned and
	   parked nowhere — that is the ordinary case once the collection outgrows six bays, and it is
	   what the Dealership page exists to sort out.

	5. A CAR YOU HAVE NOT STOLEN IS A LOCKED SLOT: a flat black cut-out of the right shape where the
	   car goes, `???` where its name goes, and the authored art faded behind both. The frame's own
	   fade is the kit's state language (the slot art is an 80%-opacity fill already, so a car you
	   have is the slot exactly as authored); the cut-out and the question marks are what make the
	   slot a thing to go and get rather than a thing you have not got.

	   THE CUT-OUT IS NOT FADED. Everything else on a locked slot is, and the shape is deliberately
	   not: a faded silhouette on a faded panel is a smudge, and the one thing this state has to do is
	   show a shape clearly enough to be recognised later. `Modules/CarViewport` draws it — see its
	   note on why it is flat rather than merely dark.

	   THE SEARCH STILL MATCHES THE REAL NAME, which is the one loose end in this. The name used to
	   stay legible so you could search for a car you had not got; now it is hidden, and typing it
	   still finds it. That is deliberate — a player who knows a car exists can check whether they
	   have it, and note 10's cross-world hint leans on it — but it does mean the box will tell you a
	   name the slot will not. If that ever wants closing, it is the `search` field in `_buildGrid`.

	6. THE SCROLLBAR IS THE AUTHORED IMAGE, DRIVEN — the native bar is off and `ScrollBar` is resized
	   and moved from the scroll position, hiding itself when everything fits (a short search result).
	   It can also be dragged. It is the page's one piece of authored art that would otherwise be
	   decoration next to a list that really scrolls.

	7. A CAR YOU HAVE IS DRAWN IN ITS STOCK LIVERY, which is the same decision as `parseOwned`
	   throwing the colour away, wearing another hat. One slot is one BODY: a player owning a Camaro
	   in four colours has ticked one slot as far as this screen counts, so there is no single colour
	   to draw it in and the artist's own is the honest answer. The dealership and spawn screens are
	   the ones that list a card per copy, and they are where a colour means something.

	8. THE CARS ARE A VIRTUALISED LIST, and `Modules/CarViewportGrid` is the whole of it. Each is a
	   real 25-mesh model, so a roster drawn all at once is hundreds of meshes rendering behind a
	   panel showing eight of them — and note 3 is a change of one line away from making that roster
	   a good deal longer. What exists is the rows the window is over plus one either side; read that
	   module's header for how. This page's half is two calls: `_applyLayout` hands over the cell
	   geometry it has just worked out, and `_applyFilter` hands over the slots that are showing, in
	   the order the grid will lay them out. The scroll, and the page opening and closing, are watched
	   in there.

	9. THE WORLD PAGER SHARES THE SEARCH ROW, AND IT BROWSES — IT DOES NOT TELEPORT. Pressing an
	   arrow changes which cars this screen lists and nothing else; where you are actually driving
	   is the Teleport page's business and is never written from here. That separation is the whole
	   reason the pager can exist on a screen you open mid-session, and it is why the world's NAME is
	   a label and only the arrows are buttons — there is no press on this page that can move you.

	   THE PAGE OPENS ON THE WORLD YOU ARE IN, every time, and follows you if the attribute changes
	   while it is open. So "which world is this?" is answered before anybody touches the pager, which
	   was the first half of what the pager is for; the second half is that four world names and a
	   pair of arrows say "there are other worlds" without a word of tutorial.

	   IT SITS BESIDE THE SEARCH BOX BECAUSE IT IS THE SAME KIND OF THING. Both narrow the grid, both
	   are meaningless on a screen of five map cards and go away together, and `_applyFilter` is the one
	   line that tests both. It used to be the TITLE BAR's left half, opposite the tabs — which put
	   three clusters of white Ubuntu Bold on one orange strip, every one of them the same colour and
	   the same stroke and all three within a fifth of each other's size. That is the whole reason
	   nobody could tell the page's NAME from its two CONTROLS at a glance. The bar now carries one
	   label and one control; the row under it carries the two filters, together. The title moved to
	   the bar's left edge to take the half the pager vacated — see `_buildTabs`, which owns that.

	   IT IS BUILT AND PLACED AT RUNTIME, measured off the authored search bar and wearing that bar's
	   own art: the chip takes the row's left end and the search bar gives up exactly the chip's width
	   plus the gap, from its left edge. Nudge SearchBar in the Explorer and the whole row follows it.

	   IT CLAMPS RATHER THAN WRAPS. The worlds are a ladder, worst to best, and a pager that loops
	   round hides where the ends of it are — so the arrow at either end goes dead and fades instead.

	10. THE WORDS ARE THE OTHER HALF OF THE FEATURE, because a per-world list creates exactly one new
	   way to be confused: you search for a car, the box says nothing matched, and the car is real
	   and two worlds away. Every string on this page is picked against that.

	   The search placeholder NAMES THE WORLD it will search, so the scope is stated before you type
	   rather than explained after you fail. When a query matches nothing here but does match
	   somewhere else, the empty line says where — one world by name, or "another world" when it is
	   several. And the bottom bar says STOLEN, not "Found": this screen has a search box on it, and a
	   counter reading "4/8 FOUND" next to a search field reads as a result count. STOLEN is also the
	   verb that fills the slot, which is the one thing the caption should teach.

	11. THE TABS ARE THE TITLE BAR'S RIGHT HALF, and switching them swaps the whole middle of the
	   panel. What belongs to CARS goes away entirely on MAPS — the search bar, the grid, the
	   scrollbar and the pager — rather than being greyed out, because none of them has a meaning on
	   a screen of map cards, and a search field that cannot search is worse than no search field.

	   THE LIVE TAB WEARS A CHIP, which is the second half of note 9's change and the reason the two
	   of them are now told apart at a glance. They used to differ by TEXT TRANSPARENCY plus a rule
	   two pixels tall, and the kit's opacity language does not work on this bar: fading white toward
	   a bright orange barely darkens it, so `MAPS` at 42% still read as white. A filled chip is a
	   different SHAPE rather than a different shade of the same one, which is the half of that fix
	   that was right and has not moved.

	   BOTH TABS ARE THE ARTIST'S OWN PILL NOW, AND THE LIVE ONE IS COLOURED — 2026-08-24. The chip
	   went through two shapes before this one. It was the kit's navy button face, which made the
	   live tab the darkest thing on the brightest strip in the UI, so it read as a hole punched in
	   the bar; then it was white, which fixed that and left the two tabs telling you only WHICH is
	   on, never which is WHICH. Both tabs now wear `UIAssets.Pill` — the seven-colour button the
	   artist parked in a palette beside this very panel — and the live one wears its own COLOUR
	   while the idle one wears Silver.

	   SO THE STRIP CARRIES TWO SIGNALS AT ONCE. The shape says both are controls, the colour says
	   which tab you are looking at (cars are one colour and maps another, before you read a word),
	   and colour-versus-silver says which is live. That is the differential the first two passes
	   were missing: they could say "this one is on" and could not say "these are two different
	   places". See `TAB_PILL`.

	   BOTH VIEWS SHARE THE BOTTOM BAR, which is the reason the page reads as one screen with two
	   halves rather than two screens: it is the same fill and the same caption, counting cars on one
	   tab and roads on the other. Every other page in the kit has one bottom bar and so does this.

	   THE MAPS VIEW IS BUILT ONCE AND KEPT. One card per world is not worth virtualising, and they
	   hold no models — the ViewportFrame machinery notes 8 documents is the CARS tab's alone.

	   EACH CARD WEARS ITS OWN ROAD, 2026-09-08, and it is the Teleport page's picture of that road
	   rather than a second set — see "The maps" for the crop that gets a portrait onto a card and
	   for why the card art had to go flat first. Five navy slabs with a number on each told you
	   nothing about WHICH place you had driven; a wash of sand, pines, ice or neon does it before a
	   word is read.

	   AND THE CARDS ARE SQUARE, later the same day, which is the change that made the picture worth
	   having. Three columns instead of two is the whole edit: the room the tab gets is fixed, so the
	   column count decides the shape, and two across could only ever draw a letterbox with a photo
	   cropped to a slot in it. Everything inside a card is a fraction of the card, so all four boxes
	   were re-cut against the new one rather than carried over — "The maps" has the numbers.

	   PROGRESS IS A DISTANCE, NOT A COLLECTION, and that is what makes this tab worth having next to
	   the other one. The percentage is the furthest you have ever driven that road as a fraction of
	   the tile past which it has nothing new to show — `TrafficConfig.topTileFor`, the same full
	   scale the results screen's ladder bar uses, so the bar at the end of a run and the card on
	   this screen can never disagree about what 100% is. `WorldService` keeps the best and
	   broadcasts the percentage; see `WorldConfig.ProgressAttribute` for why it arrives already
	   worked out.

	   A MAP WITH NO ENTRY IN THE BROADCAST IS ONE THAT CANNOT BE SCORED — an unbuilt road, or a
	   ladder with no top rung — and it says so instead of showing 0%. Not reachable today; it is one
	   line cheaper than finding out the hard way when a fifth world is stubbed in.

	12. EVERY SLOT NAMES ITS RARITY, in the band's own colour, and that word is CONFIG rather than
	   anything decided here. `TrafficConfig` already resamples its five hand-tuned bands onto
	   however many rungs a world has and records the nearest one as `Rarity` on the tier — it says
	   in as many words that it exists because a shop wants a rarity to print rather than a model
	   name. This screen is the first thing to print it. So there is no second ladder to keep in
	   step: move a car in `WorldConfig` and its rarity here moves with it, and re-tuning the bands
	   is still five lines in one file.

	   THE WORD AND ITS COLOUR BOTH COME OUT OF `Modules/CarRarity` — they were both private to this
	   file until the Cars Inventory needed the same two on its own cards. That module's header
	   carries the rest: why the ramp is keyed to the band's INDEX rather than its name, why a band
	   past the end of it clamps to the top colour rather than drawing white, and which five colours
	   it is. Nothing about this page's behaviour changed when they moved.

	   IT IS NOT A COLOUR ON THE CAR. `TrafficConfig` records at length why a tier stopped owning a
	   paint pool — paint is per car and per spawn now, and a colour that meant "supercar" made two
	   Chargers look like two different rungs. This is a colour on a WORD, in a panel, and it says
	   what the word says. Nothing here reaches the road.

	   THE LOCKED SLOT KEEPS ITS RARITY. The name goes to `???` and this does not, which is the
	   whole point of it being on the screen: note 5 wants a locked slot to read as a thing to go
	   and get, and "there is a SUPERCAR you have not found in this world" is that in one word. It
	   fades with everything else, colour intact — a faded gold is still gold.

	   RARITY ORDER IS THE ORDER THE GRID WAS ALREADY IN. A world's ladder runs cheapest to dearest
	   and the bands are resampled onto it, so bands ascend down the grid by construction and no
	   sort was added; sorting by rarity here would be re-deriving the ladder from a word that came
	   out of it. What the line adds is that the grouping is now VISIBLE — four across, the rows
	   read as bands.

	13. A SLOT YOU HAVE STOLEN SAYS WHAT THAT CAR PAYS, at the far end of the line the rarity is on.
	   The two are siblings and that is why they share a line: the rarity says what KIND of car this
	   is and the rate says what it is WORTH, and the second one is the sentence the dealership is
	   actually played for.

	   IT WAS A HOVER TIP UNTIL 2026-08-24 — a chip that appeared over whichever slot the pointer was
	   on. Three things were wrong with that and only the last is about taste. A hover does not exist
	   on a phone, so the number was unreachable for most of the players who have it. The chip sat
	   over the row above the one it was about, so reading one card cost you the sight of another.
	   And it made the one number on this screen worth acting on the only thing you had to go looking
	   for. On the slot it is on the screen for every car at once, which is what a collection screen
	   is for.

	   IT IS THE REWARD FOR HAVING THE CAR, which is the one thing that changed with the move. The
	   tip quoted a locked slot too, on the argument that "there is a SUPERCAR in this world and it
	   pays $47/s" is what gets somebody back in a car. On the slot that argument loses to a plainer
	   one: a locked slot is already a `???` over a cut-out, and a price under those two is a fact
	   about a car the player cannot look at. The RARITY still shows on a locked slot (note 12),
	   because a band is what makes one worth chasing; the money arrives with the car.

	   THE NUMBER IS THE DEALERSHIP CARD'S, to the character: `GarageConfig.rateOf` off the body's
	   tier, printed through `formatRate`, which is the same call and the same format string the
	   Dealership page's price line makes. Two screens quoting one car cannot disagree, because
	   there is nothing here to disagree with.

	   IT IS THE BASE RATE — no bay level, no lot-wide income upgrade. Both of those are per PLAYER
	   and per BAY, and a car on this screen is in neither: it is a car that exists, not a car parked
	   somewhere earning. So the line is what the CAR is worth, and the podium's own kiosk is what
	   YOUR bay pays for it. Quoting an upgraded number here would be quoting a bay this car has
	   never stood on.

	   `/S` IS THE WHOLE CAPTION. The tip had a chip to put two lines in and wrote CASH PER SECOND
	   over the number; a slot has not got the room, and the suffix is what the dealership's own
	   cards print. A body missing from `GarageConfig.TierOfBody` prints NOTHING rather than `$0.0/s`
	   — that is a config gap, and quoting nothing for it is worse than saying nothing about it.

HOUSE RULE, PAID FOR ONCE ALREADY: no wiki-style double-bracket links in this comment. The
	closing pair ends the block comment early and the parse error it throws points at the wrong line
	— which is exactly what broke this module, and with it every page the controller loads.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UIControllerTypes = require(script.Parent.Parent.UIControllerTypes)
local UIGeom = require(script.Parent.Parent.UIGeom)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local RewardConfig = require(ReplicatedStorage.shared.Configs.RewardConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local CarCatalogue = require(ReplicatedStorage.shared.Modules.CarCatalogue)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)
local CarViewportGrid = require(ReplicatedStorage.shared.Modules.CarViewportGrid)

local PAGE_NAME = "Index"

--[[ The two tabs, up here rather than beside the code that draws them because `Page.new` names one
	and Luau scopes a local from its declaration DOWNWARD — a constant declared below a function is
	not an upvalue of it, it is a nil global read from inside it, and that reads as a page that
	quietly starts on neither tab. See "The tabs" for everything else about them. ]]
local TAB_CARS = "Cars"
local TAB_MAPS = "Maps"

--[[ See header note 4. Names that are not on the roster are ignored, so the server can write whatever
	it likes without this screen mis-counting.

	=== IT IS THE CATALOGUE, NOT THE COLLECTION, AND THAT CHANGED WITH SELLING ===================

	`InventoryConfig.FoundAttribute` ("CarsSeen") is every BODY this player has ever banked and never
	shrinks. `GarageConfig.OwnedAttribute` — which this page read until the Cars Inventory shipped —
	is the collection as it stands, and it now GETS SHORTER when a player sells a car.

	This page is a catalogue of the roster ("23/29 Stolen"), so it has to read the list that cannot
	go backwards. Reading the other one would un-tick a slot the moment somebody cashed in their only
	Camaro, which is a completion meter that punishes you for using a feature. The two names are
	confusingly close and that is history: the old attribute has always been SPELLED "CarsFound"
	while meaning "owned", and renaming it would have been an edit to four screens and a valuation.

	The name now comes out of `Modules/CarCatalogue`, which both index pages read, so the new UI's
	collection cannot count off the other list by mistake. ]]
local OWNED_ATTRIBUTE = CarCatalogue.FoundAttribute

-- Header note 5: how far a slot the player has not found is faded past the authored art. The car in
-- it is NOT faded — see the note; the cut-out is the one thing on a locked slot that stays solid.
local UNOWNED_IMAGE_TRANSPARENCY = 0.6
local UNOWNED_TEXT_TRANSPARENCY = 0.45

--[[ Where the car stands on a slot, in fractions of it. The authored slot is a plain square and the
	name label runs across it from 0.70 down, so the car takes the room above that — which is what the
	label's own comment has been holding open for a portrait since this page was written.

	The two numbers are the box; the shape it comes out is not typed anywhere, because a slot's pixel
	size is worked out from the panel at runtime. `_applyLayout` divides the live cell dimensions and
	hands the result to the grid. It is CONSTANT all the same: the page carries a
	UIAspectRatioConstraint, so the panel, the scroll inside it and every cell in that keep their
	shape at any window size. ]]
--[[ HOW MANY CARDS ACROSS — note 2's one exception, and the only grid number in this file that is
	typed rather than measured.

	The artist drew four sample slots and the grid ran four across for as long as a card held a car
	and a name. It now holds a car, a name, a rarity and a price (note 13), and four across is a card
	too small to read the last two on a phone. Three is the same panel, the same margins, the same
	gaps and the same authored square: the row is cut three ways instead of four, so a card comes out
	a third bigger in both directions with no art resized and nothing in the place moved.

	WHAT IT COSTS IS A ROW. The viewport held two rows and a sliver of the third and now holds one
	and most of the second — still the "there is more below" cue the taller cell was chosen against,
	and a world's ladder is seven or eight cars, so the scroll was always going to be used.

	Set it to 0 to go back to "however many samples the artist drew". ]]
local GRID_COLUMNS = 3

local VIEW_WIDTH = 0.90
local VIEW_HEIGHT = 0.62
local VIEW_CENTRE = 0.36

--[[ THE RARITY LINE — header note 12. The strip under the name, in fractions of the slot.

	IT TAKES THE ROOM THE SLOT ALREADY HAD and moves nothing: the car runs to 0.67, the name from
	0.70 to 0.87, and the bottom eighth of the authored square was empty. Neither of the other two
	is nudged to make space, which matters more than it sounds — the name's rect is the one the
	artist drew and the car's is the aspect `_applyLayout` hands the viewport grid.

	SHORTER THAN THE NAME, and that is the whole hierarchy. These are TextScaled labels, so the box
	IS the type size: a rarity in the name's box would be a second title, and the slot would have
	two things on it competing to be read first. The car's name is what the slot is; the rarity is
	what KIND it is.

	IT DOES NOT SIT FLUSH UNDER THE NAME, and the first pass did. A TextScaled label's glyph box IS
	its rect, so a rarity starting at the name's bottom edge is two lines of type touching — it
	survives today only because `caption` uppercases both and capitals have no descenders, which is
	a thing that is true of the strings rather than of the layout. The band under the name is 0.13
	of the slot; this takes the middle of it and leaves air at both ends, more below than above
	because the bottom one is measured against the slot's own border. ]]
local RARITY_LEFT = 0.08
local RARITY_TOP = 0.885
local RARITY_WIDTH = 0.84
local RARITY_HEIGHT = 0.086

--[[ THE PRICE SHARES THAT LINE — header note 13. On a car you have, the rarity takes the left end
	of the strip and the rate the right, with air between them; on one you have not there is no
	price, and the rarity keeps the whole line, centred exactly as it was.

	TWO STATES RATHER THAN ONE LAYOUT WITH A GAP IN IT, because a lone word ranged left under a
	centred name reads as a row that lost something. `_refreshOwnership` is the only place that
	swaps between them, and it is the same pass that swaps the name for `???`.

	NEITHER BOX MAKES ITS TYPE SMALLER. These are TextScaled, so a box is a type size only when the
	string is too long for it: `SUPERCAR` is the longest rarity and `$1.2K/s` the longest rate, and
	in these widths both are limited by the strip's HEIGHT rather than by them. So the two ends of
	the line render at the same size as each other and as the full-width word they replace. ]]
local RARITY_SHARED_WIDTH = 0.44
local RATE_LEFT = 0.54
local RATE_WIDTH = 0.38

--[[ `#0DB415`, the kit's money green — the one colour in the palette that means cash, and the
	reason this line needs no word on it saying so. It is the only other colour on the strip and it
	sits at the opposite end from the rarity's, which is what keeps two tinted words on one line
	from reading as one word in a gradient. ]]
local RATE_COLOUR = Color3.fromRGB(13, 180, 21)

--[[ THE RARITY RAMP MOVED TO `Modules/CarRarity` — 2026-08-16. It was one private table and one
	private roster walk in this file until the Cars Inventory needed the same word and the same
	colour on its own cards, and a second private copy would have been a second ladder to keep in
	step with `TrafficConfig.Bands`. Header note 12 is still the reasoning; the table itself, and
	why it is keyed by band INDEX rather than by name, is now in that module's header.

	Nothing about this page changed with the move: `CarRarity.of` walks the tiers in exactly the
	order the loop here did and returns the same `(word, band)` the local `ROSTER` recorded. ]]

-- Fallback page aspect (PSD page box, 1798 x 1224) if the page ever loses its aspect constraint.
local PAGE_ASPECT = 1798 / 1224

-- Shortest the scroll thumb is allowed to get, as a fraction of its track. A 43-car canvas would
-- otherwise put it at ~19% of the track and a filtered one lower still.
local MIN_THUMB = 0.08

--[[ THE WORDS. Header note 10 is the reasoning; these are the strings, and they are built through
	`caption` below rather than written with the non-breaking spaces in them.

	`{world}` is substituted with the world's own name — "City", "Desert" — never "World 2". A place
	name tells a player where they are and a number tells them nothing; `WorldConfig.displayName`
	already made that call for the teleport cards and this follows it. ]]
local TEXT = {
	-- The two tabs. Nouns, because they name what you are looking at rather than what pressing does.
	TabCars = "Cars",
	TabMaps = "Maps",
	-- The bottom bar on the CARS tab. Not "Found": see note 10.
	Progress = "{found}/{total} Stolen",
	--[[ The bottom bar on the MAPS tab: the cards averaged. "Explored" pairs with "Stolen" the
		way the tabs pair — both are things the player did, one per tab, and neither is a word about
		the UI. It is also the honest verb for a progress that is a distance driven rather than a set
		completed. ]]
	MapsProgress = "{percent}% Explored",
	-- One card. Floored, so 99.6% is not allowed to read as finished.
	MapPercent = "{percent}%",
	-- ...and a card for a world whose road has not been built, or whose ladder has no top rung to
	-- measure against. Note 11. Not "0%", which would be a lie about the player rather than the map.
	MapUnbuilt = "Not built yet",
	-- The search field's own label, which is the only place the search's SCOPE can be stated before
	-- somebody trips over it.
	SearchHint = "Search {world}",
	-- A slot you have not stolen yet. Three marks, not one per letter — see below.
	Locked = CarCatalogue.LockedText,
	-- The query matched nothing anywhere on the roster.
	NoMatch = "No cars match that",
	-- ...matched in exactly one other world, which is worth naming: it turns a dead end into a
	-- direction. It leans on the search matching a locked car's real name (note 5).
	NoMatchHere = "Not in {world}, try {other}",
	-- ...matched in several. Naming three of them is a wall of text; the arrows are right there.
	NoMatchAnywhereHere = "Not in {world}, try another world",
	-- A world with no cars on its ladder yet. Not reachable today (every world has seven or eight)
	-- and one line cheaper than finding out the hard way when a fifth world is stubbed in.
	NoCars = "No cars in {world} yet",
	--[[ The pager's arrows. GUILLEMETS, NOT ANGLE BRACKETS, and that is the second attempt: `<` and
		`>` are what a breadcrumb is drawn with, so "CITY > INDEX" read as a path down into the page
		rather than as a control — worse still at world 1, where the back arrow is faded out and only
		the `>` is left. These say "page", and nothing else on a screen says it with them.

		Latin-1, so this is safe rather than lucky: a chevron or a triangle out of the higher blocks
		is a glyph the font may simply not carry, and Roblox draws a missing one as a box with no
		error anywhere to say why. ]]
	Back = "\u{00AB}",
	Forward = "\u{00BB}",
}

--[[ One of the strings above, filled in and made fit to print. `caption` also uppercases, which is
	the kit's voice everywhere except inside the search field — the artist wrote that placeholder in
	sentence case and it is greyed-back hint text rather than a label, so `hint` leaves the case
	alone.

	THE NBSP IS NOT COSMETIC, and both do it. These are TextScaled labels, and TextScaled would
	rather wrap to a second line and halve the type than shrink it — so "NOT IN CITY, TRY FOREST
	MOUNTAINS" comes out as two lines of nothing unless the spaces are unbreakable. ]]
local function hint(template: string, fields: { [string]: string | number }?): string
	local filled = template
	for key, value in fields or {} do
		-- `%` is the escape in a gsub REPLACEMENT, and a world name is data. No name carries one
		-- today; this is here so that adding one is a rename and not a crash.
		local replacement = string.gsub(tostring(value), "%%", "%%%%")
		filled = string.gsub(filled, "{" .. key .. "}", replacement)
	end
	return (string.gsub(filled, "%s+", "\u{00A0}"))
end

local function caption(template: string, fields: { [string]: string | number }?): string
	return string.upper(hint(template, fields))
end

--- A world's name for printing: the map it is driven on ("Forest Mountains"), never "World 3".
local function worldName(index: number): string
	return WorldConfig.displayName(index)
end

--[[ `TEXT.Locked` again, as a constant, because it is the one string here with a reason of its own.
	Header note 5.

	THREE MARKS RATHER THAN ONE PER LETTER. Matching the name's length would leak it — a four-mark
	slot next to a ten-mark one is most of the way to naming both against a roster this small — and it
	would draw at a different size on every locked slot, because these labels are TextScaled and a
	short string is limited by the box's height rather than its width. Three is a word, not a
	redaction of one. ]]
local LOCKED_TEXT = TEXT.Locked

--- Strip everything but letters and digits so "sports 27", "Sports27" and "SPORTS-27" all match.
local function normalize(text: string?): string
	return (string.gsub(string.lower(text or ""), "%W", ""))
end

--[[ "Sedan20B" -> "SEDAN 20B", on one line.

	THE PATTERN WANTS AT LEAST THREE LEADING LETTERS AND THEN A DIGIT — a word followed by a number,
	not a designation. `Sedan20B` is a word and a number and reads better split; `M5`, `C7`, `i8`,
	`RX7` and `190E` are single tokens and splitting them is how this used to print "M 5". The
	remainder has to START with the digit for the same reason: `Model 3` and `Golf GTI` already have
	their space and inserting a second one printed "MODEL  3".

	This is the Dealership page's `displayName`, character for character. Two copies rather than a
	shared helper is deliberate for now — they are four lines and they answer to different pages'
	art — but they must not be allowed to drift, because a car printed two ways on two screens is a
	car the player has to work out is the same car. ]]
local function displayName(body: string): string
	local word, rest = string.match(body, "^(%a%a%a+)(%d.*)$")
	local name = if word then word .. " " .. rest else body
	return (string.gsub(string.upper(name), " ", "\u{00A0}"))
end

--[[ EVERY CAR IN THE GAME, in world order and then ladder order, each tagged with the world it
	belongs to. Header note 3. Built once at load, because it is a fact about the config and cannot
	change while a session is running.

	DEDUPED ACROSS WORLDS, FIRST WORLD WINS. No body appears twice today (8 + 7 + 7 + 7 = 29, and
	`TrafficConfig.AllBodies` agrees), but nothing stops a designer putting one car on two ladders,
	and two slots for one car would double-count it in whichever world's total it was in.

	IT WALKS THE TIERS RATHER THAN `bodiesFor`, which is where the rarity used to come from — header
	note 12. The two lists are the same list: `BodiesByWorld` is built by flattening exactly this
	loop's `tier.Bodies` in exactly this order, so nothing about the grid's contents or its order
	changed when this moved up a level.

	THE RARITY ITSELF IS NOW `CarRarity`, which walks these same tiers in this same order and is
	shared with the Cars Inventory. This loop kept the WORLD, because that is the one thing about a
	car this page needs and no other screen does — which tab-full of slots it belongs in.

	THE LOOP ITSELF IS NOW `Modules/CarCatalogue.Roster`, unchanged, because the new UI's collection
	screen lists the same cars and has to agree with this one about which and in what order. ]]
local ROSTER: { { body: string, world: number } } = CarCatalogue.Roster

--[[ The attribute's comma-separated list as a set of BODIES. Anything unparseable reads as "nothing
	found".

	THE CATALOGUE IS ALREADY BODIES, so this mostly just builds a set — but it still goes through
	`parseCarKey`, and deliberately. That function reads a name with no `:colour` on it as the body
	itself, so this is correct against `CarsSeen` (bodies) AND against a car key, which is what the
	attribute this page used to read held. One line that cannot be wrong about which list it was
	handed is worth more than the branch it saves.

	THE COLOUR, IF ONE ARRIVES, IS THROWN AWAY. The index is the roster — one slot per car the game
	has, ticked when you have found it — so a Camaro in four colours is still one slot filled, and
	the completion count would otherwise read past 100%. Where the colours matter is the Cars
	Inventory, which lists one card per copy; this one is about the set of cars that exist.

	The parse lives in `Modules/CarCatalogue.parseFound` now, for the same reason the roster does. ]]
local function parseOwned(raw: any): { [string]: boolean }
	return CarCatalogue.parseFound(raw)
end

local Page = {}
Page.__index = Page

function Page.new(UIController: UIControllerTypes.UIController)
	local self = setmetatable({}, Page)
	self.UIController = UIController
	self.Player = UIController.Player or Players.LocalPlayer

	local mainUI = UIController.PlayerGui:WaitForChild("MainUI")
	self.PageUI = mainUI:WaitForChild("Pages"):WaitForChild(PAGE_NAME)

	self.Panel = self.PageUI:WaitForChild("Panel")
	self.TitleBar = self.PageUI:WaitForChild("TitleBar")
	self.Title = self.PageUI:WaitForChild("Title")
	self.SearchBar = self.PageUI:WaitForChild("SearchBar")
	self.SearchPlaceholder = self.PageUI:WaitForChild("SearchPlaceholder")
	self.Slots = self.PageUI:WaitForChild("Slots")
	self.ScrollBar = self.PageUI:WaitForChild("ScrollBar")
	self.ProgressTrack = self.PageUI:WaitForChild("BottomBarTrack")
	self.ProgressFill = self.PageUI:WaitForChild("BottomBarFill")
	self.ProgressLabel = self.PageUI:WaitForChild("BottomBarLabel")
	-- Optional: the artist's magnifier. Found rather than waited on, because it is decoration and a
	-- page that hangs on a missing one takes every other page down with it.
	self.SearchIcon = self.PageUI:FindFirstChild("SearchIcon")

	-- A LOCAL, never `self.Close`: the controller treats a `Close` field on a page as that page's
	-- custom close ROUTINE and calls it, so parking the button there makes closing throw. The tabs
	-- are measured against it all the same — see `_buildTabs`.
	local close = self.PageUI:WaitForChild("Close")
	close.MouseButton1Click:Connect(function()
		self.UIController:closePage(PAGE_NAME)
	end)

	self._entries = {}
	self._query = ""
	self._visibleCount = 0
	self._owned = {}
	self._progress = {}
	-- Which tab. Cars, always, on a page that has just been built — see `StartOpenThread` for why
	-- reopening does NOT reset it.
	self._tab = TAB_CARS
	-- The world being LISTED, which starts as the world being driven. Header note 9. Set before the
	-- grid is built, because the first filter pass already asks which world it is showing.
	self._world = self:_currentWorld()

	--[[ THE PAGER GOES FIRST because it narrows the search bar, and two passes below measure that
		bar after it: `_buildSearch` derives the text box's rect and padding from it, and `_measure`
		takes the grid's top margin off its bottom edge. Neither is wrong about a bar that has already
		been resized; both would be wrong about one resized underneath them. ]]
	self:_buildWorldPager()
	self:_buildGrid()
	self:_buildSearch()
	self:_buildMaps()
	self:_buildTabs(close)
	self:_watchOwnership()
	self:_watchWorld()
	self:_watchProgress()
	self:_repaintWorld()
	self:_setTab(TAB_CARS)

	return self
end

function Page.initialize(_self) end

--[[ Opening the page. Two resets, both because a collection screen is somewhere you come back to
	and it should not be showing you where you left off half an hour ago:

	  • it snaps to the world you are actually in, which is what makes the pager an answer to "which
	    world is this" rather than a thing you have to read; and
	  • it clears the search, because a filtered grid you did not type looks like a broken one.

	Clearing the box publishes through the box's own Text signal, so the filter pass below is the
	same one a real edit takes.

	THE TAB IS NOT RESET, and that is the difference between the two kinds of state on this page. The
	world and the query are filters — a narrowed view of one thing, and reopening onto somebody
	else's leftovers reads as broken. The tab is WHICH THING, and a player who was looking at maps
	when they closed this meant to be looking at maps. ]]
function Page.StartOpenThread(self)
	if self._search and self._search.Text ~= "" then
		self._search.Text = ""
	end
	self:_setWorld(self:_currentWorld())
	self:_refreshProgress()
end

-- === Layout =================================================================

--[[ Read the authored sample back as grid metrics — header note 2. Everything downstream of this
	is in PAGE scale (the page frame is the coordinate space every element in the mock-up was
	positioned in), converted to viewport-relative fractions at the end. ]]
function Page:_measure(template: GuiObject, samples: { GuiObject })
	local aspectConstraint = self.PageUI:FindFirstChildOfClass("UIAspectRatioConstraint")
	local aspect = aspectConstraint and aspectConstraint.AspectRatio or PAGE_ASPECT

	local slotWidth = template.Size.X.Scale
	local slotHeight = template.Size.Y.Scale
	-- Edges, not raw Position: the samples are centre-anchored like the rest of the kit, so their
	-- Position is a centre. See UIGeom.
	local left, top = UIGeom.topLeft(template)
	--[[ How many slots the artist drew, which is how wide the ROW is — and no longer how many cards
		go in it. `GRID_COLUMNS` is that, and everything below still measures off the samples. ]]
	local sampleColumns = math.max(#samples, 1)
	local columns = if GRID_COLUMNS > 0 then GRID_COLUMNS else sampleColumns

	-- Column gap straight off the sample's pitch; row gap is that gap made square in pixels.
	local gapX = if samples[2] then UIGeom.left(samples[2]) - left - slotWidth else 0
	gapX = math.max(gapX, 0)
	local gapY = gapX * aspect

	local width = sampleColumns * slotWidth + (sampleColumns - 1) * gapX

	--[[ The viewport runs from the first row down to the panel's inner edge, inset by the same
		margin the artist left above the first row. Two rows and a sliver of the third are visible,
		which is both what fits and the cue that there is more below. ]]
	local margin = top - UIGeom.bottom(self.SearchBar)
	local panelBottom = UIGeom.bottom(self.Panel)
	local height = panelBottom - math.max(margin, 0) - top
	if height <= slotHeight then
		-- The panel is somehow shorter than a row: fall back to two rows rather than draw nothing.
		height = 2 * slotHeight + gapY
	end

	--[[ THE AUTHORED CARD'S PIXEL SHAPE, which is what lets the column count change without the card
		changing shape. `slotWidth` is a fraction of the page's WIDTH and `slotHeight` of its HEIGHT,
		so the ratio between the two is only a shape once the page's own aspect is in it. Every cell's
		height is derived from its width through this — see `_applyLayout`. ]]
	local cellAspect = if slotHeight > 0 then (slotWidth / slotHeight) * aspect else 1

	return {
		left = left,
		top = top,
		width = width,
		height = height,
		columns = columns,
		slotHeight = slotHeight,
		cellAspect = cellAspect,
		-- Cell and padding as fractions of the viewport, which is all the offset pass needs.
		cellWidth = slotWidth / width,
		cellHeight = slotHeight / height,
		padX = gapX / width,
		padY = gapY / height,
	}
end

function Page:_buildGrid()
	local samples = {}
	for _, child in self.Slots:GetChildren() do
		if child:IsA("GuiObject") then
			table.insert(samples, child)
		end
	end
	table.sort(samples, function(a, b)
		return UIGeom.left(a) < UIGeom.left(b)
	end)

	if #samples == 0 then
		warn(`[{PAGE_NAME}] no sample slot under Slots — the grid needs one to clone. Page left empty.`)
		return
	end

	--[[ A DETACHED copy, kept for the life of the page — the authored samples are destroyed three
		lines down and a destroyed instance cannot be cloned. The maps tab clones it too, which is
		what keeps the two tabs made of the same piece of the artist's panel. ]]
	local template = samples[1]:Clone()
	self._slotTemplate = template
	local grid = self:_measure(samples[1], samples)
	self._grid = grid

	for _, child in self.Slots:GetChildren() do
		child:Destroy()
	end

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Grid"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ClipsDescendants = true
	scroll.Position = UDim2.fromScale(grid.left, grid.top)
	scroll.Size = UDim2.fromScale(grid.width, grid.height)
	scroll.ZIndex = self.Slots.ZIndex
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 0 -- the authored ScrollBar image stands in; see _updateScrollBar
	scroll.ScrollBarImageTransparency = 1
	scroll.CanvasSize = UDim2.new()
	scroll.Active = true
	scroll.Parent = self.Slots
	self._scroll = scroll

	-- Header note 8. Made before the first layout pass, which is what hands it the cell geometry.
	self._views = CarViewportGrid.new(scroll, self.PageUI)

	local layout = Instance.new("UIGridLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.FillDirectionMaxCells = grid.columns
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Parent = scroll
	self._layout = layout

	for index, car in ROSTER do
		local body = car.body
		local slot = template:Clone()
		slot.Name = body
		slot.LayoutOrder = index

		local label = Instance.new("TextLabel")
		label.Name = "CarName"
		label.BackgroundTransparency = 1
		-- Along the bottom of the square. The room it leaves above is the car's, and was left for it
		-- from the start. Centre-anchored to match the authored text, and placed by its top-left so
		-- the rect is still the one written here.
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Size = UDim2.fromScale(0.84, 0.17)
		UIGeom.place(label, 0.08, 0.70)
		label.ZIndex = slot.ZIndex + 1
		label.FontFace = self.ProgressLabel.FontFace
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextScaled = true
		-- A default only: `_refreshOwnership` owns this line from here on, and swaps it for `???` on
		-- a slot the player has not found. Header note 5.
		label.Text = displayName(body)

		local sourceStroke = self.ProgressLabel:FindFirstChildOfClass("UIStroke")
		if sourceStroke then
			sourceStroke:Clone().Parent = label
		end

		label.Parent = slot

		--[[ The rarity, under the name, in its band's colour — header note 12. Built here and then
			never rewritten: a car's band is a fact about the config and cannot change while a
			session is running, so `_refreshOwnership` only ever fades this rather than setting it.

			IT KEEPS THE NAME'S STROKE and drops the name's colour, which is the whole reason the
			line is legible: the dark outline is what holds type off the slot art whatever the type
			is, and the fill is the one thing on the slot allowed to be a colour. ]]
		local rarityWord, rarityTint = CarRarity.labelOf(body)
		local rarityLabel = Instance.new("TextLabel")
		rarityLabel.Name = "CarRarity"
		rarityLabel.BackgroundTransparency = 1
		rarityLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		rarityLabel.Size = UDim2.fromScale(RARITY_WIDTH, RARITY_HEIGHT)
		UIGeom.place(rarityLabel, RARITY_LEFT, RARITY_TOP)
		rarityLabel.ZIndex = slot.ZIndex + 1
		rarityLabel.FontFace = self.ProgressLabel.FontFace
		rarityLabel.TextColor3 = rarityTint
		rarityLabel.TextScaled = true
		rarityLabel.Text = caption(rarityWord)
		-- A band with no word behind it draws nothing rather than an empty coloured gap. Not
		-- reachable while every tier carries a `Rarity`; one line cheaper than finding out later.
		rarityLabel.Visible = rarityWord ~= ""

		if sourceStroke then
			sourceStroke:Clone().Parent = rarityLabel
		end

		rarityLabel.Parent = slot

		--[[ What this car pays parked, worked out ONCE — header note 13. A tier is a fact about the
			config and the rate is a function of it, so there is nothing here that can change while a
			session is running and no reason to format the same string twice.

			`TierOfBody` RATHER THAN THE ROSTER'S OWN TIER, because it is the list the SERVER prices a
			parked car off (`GarageService`) and the one the Dealership card reads. A body it does not
			know is worth nothing rather than a guess, and prints nothing at all. ]]
		-- The whole line, already printed. EMPTY on a car with no price, which is the "no rate"
		-- signal rather than a second flag saying the same thing. `Modules/CarCatalogue` prints it,
		-- so both index pages quote a car the same way.
		local rateText = CarCatalogue.rateText(body)

		--[[ ...at the other end of the rarity's strip — header note 13. Built on every slot and shown
			on the ones the player has; `_refreshOwnership` owns `Visible` and the strip's two layouts
			from here on.

			IT KEEPS THE NAME'S STROKE, for the reason the rarity does: the dark outline is what holds
			a coloured word off whatever art is behind it. IT IS NEVER FADED, because it is only ever
			drawn on a car the player has, and everything that fades on this slot fades for the one
			reason that the player has not. ]]
		local rateLabel = Instance.new("TextLabel")
		rateLabel.Name = "CarRate"
		rateLabel.BackgroundTransparency = 1
		rateLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		rateLabel.Size = UDim2.fromScale(RATE_WIDTH, RARITY_HEIGHT)
		UIGeom.place(rateLabel, RATE_LEFT, RARITY_TOP)
		rateLabel.ZIndex = slot.ZIndex + 1
		rateLabel.FontFace = self.ProgressLabel.FontFace
		rateLabel.TextColor3 = RATE_COLOUR
		-- Ranged against the slot's own right edge, the way the rarity is ranged against its left, so
		-- the strip reads as two ends of one line rather than as two labels that happen to be near
		-- each other. Not `caption`: the string is a number and uppercasing it would print `$47/S`.
		rateLabel.TextXAlignment = Enum.TextXAlignment.Right
		rateLabel.TextScaled = true
		rateLabel.Text = rateText
		rateLabel.Visible = false

		if sourceStroke then
			sourceStroke:Clone().Parent = rateLabel
		end

		rateLabel.Parent = slot

		--[[ The car's own frame, empty for now: `CarViewportGrid` fills it in — and empties it again
			— as the list scrolls past. Under the name rather than over it, which is one number because
			the GUI is `ZIndexBehavior.Sibling`: ZIndex orders a child against its SIBLINGS only, and a
			descendant always draws over its ancestor whatever it is set to. So the slot's own ZIndex
			puts the car below the label and above the slot art.

			NO PAINT IS PASSED — one slot is one body, in its artist's livery. Header note 7. ]]
		local viewport = CarViewport.new(slot, "CarView")
		viewport.AnchorPoint = Vector2.new(0.5, 0.5)
		viewport.Position = UDim2.fromScale(0.5, VIEW_CENTRE)
		viewport.Size = UDim2.fromScale(VIEW_WIDTH, VIEW_HEIGHT)
		viewport.ZIndex = slot.ZIndex

		slot.Parent = scroll

		--[[ The entry IS the grid's cell — `viewport`, `body` and `silhouette` are the fields
			`CarViewportGrid` reads, and it keeps its own bookkeeping alongside them. One table rather
			than two, so there is no pairing to keep in step. No `fade`: on this page a car is either
			the real thing or a cut-out and both are drawn solid, so the grid's default of 0 is right
			for every slot. `silhouette` is left unset here and settled by `_refreshOwnership`, which
			runs before the page is ever visible and therefore before anything is built. ]]
		local entry = {
			body = body,
			world = car.world,
			search = normalize(body),
			slot = slot,
			label = label,
			rarityLabel = rarityLabel,
			rateLabel = rateLabel,
			viewport = viewport,
			rate = rateText,
		}
		table.insert(self._entries, entry)
	end

	-- Shown when the grid has nothing in it, so the panel is never a blank well. Its wording is the
	-- interesting half and it changes with the world and the query — see `_emptyText`.
	local empty = Instance.new("TextLabel")
	empty.Name = "NoMatches"
	empty.BackgroundTransparency = 1
	empty.AnchorPoint = Vector2.new(0.5, 0.5)
	empty.Size = UDim2.fromScale(grid.width, grid.slotHeight * 0.5)
	UIGeom.place(empty, grid.left, grid.top + grid.height * 0.35)
	empty.ZIndex = self.Slots.ZIndex + 1
	empty.FontFace = self.ProgressLabel.FontFace
	empty.TextColor3 = self.SearchPlaceholder.TextColor3
	empty.TextScaled = true
	empty.Text = caption(TEXT.NoMatch)
	empty.Visible = false
	local emptyStroke = self.ProgressLabel:FindFirstChildOfClass("UIStroke")
	if emptyStroke then
		emptyStroke:Clone().Parent = empty
	end
	empty.Parent = self.Slots
	self._empty = empty

	-- Not `_applyLayout` directly: the filter pass is what hands the grid its list of slots, and with
	-- an empty query it is the same layout call plus that.
	self:_applyFilter()

	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_applyLayout()
	end)
	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:_updateScrollBar()
	end)

	self:_bindScrollBarDrag()
end

--[[ Cell geometry in offset, from the viewport's live pixel size — header note 2.

	The cell WIDTH is derived from the padding rather than measured alongside it, so a row always
	adds up to exactly the viewport width no matter how the fractions round. ]]
function Page:_applyLayout()
	local scroll, grid, layout = self._scroll, self._grid, self._layout
	if not (scroll and grid and layout) then
		return
	end

	local size = scroll.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return -- not laid out yet; the AbsoluteSize signal brings us back
	end

	local padX = grid.padX * size.X
	local padY = grid.padY * size.Y
	local cellWidth = (size.X - padX * (grid.columns - 1)) / grid.columns
	--[[ ...and the HEIGHT off that width rather than off the viewport, so a card keeps the shape the
		artist drew it at whatever `GRID_COLUMNS` says. Measuring both against the viewport — which is
		what this did while the count was the samples' own — ties the two together only by
		coincidence: change the count and the cards go landscape while the art stays square. The
		viewport measure is kept as the fallback for a template with no height to divide by. ]]
	local cellHeight = if grid.cellAspect > 0 then cellWidth / grid.cellAspect else grid.cellHeight * size.Y

	layout.CellSize = UDim2.fromOffset(cellWidth, cellHeight)
	layout.CellPadding = UDim2.fromOffset(padX, padY)

	--[[ The same geometry, handed to the viewport grid so its window test runs against the numbers the
		slots are actually laid out with rather than a second copy that can disagree — row N's top edge
		in canvas coordinates is `N * (cellHeight + padY)`, from 0 because this scroll is built here
		and has no padding of its own. Header note 8. ]]
	self._views:setLayout(
		grid.columns,
		cellHeight + padY,
		cellHeight,
		0,
		(VIEW_WIDTH * cellWidth) / (VIEW_HEIGHT * cellHeight)
	)

	local rows = math.ceil(self._visibleCount / grid.columns)
	local canvas = if rows > 0 then rows * cellHeight + (rows - 1) * padY else 0
	scroll.CanvasSize = UDim2.fromOffset(0, canvas)

	self:_updateScrollBar()
end

-- === The world pager ========================================================
--[[ Header note 9. `\u{00AB} CITY \u{00BB}` at the left end of the SEARCH ROW: which world's cars are
	on the screen, and the two presses that change it.

	NOTHING HERE TELEPORTS. `_setWorld` writes one field on this page and redraws; the player
	attribute that says where you are driving is read, never written. ]]

--- The world the player is actually in. Resolved, so it is a real index from the first frame of the
--- session — before the server has written the attribute at all.
function Page:_currentWorld(): number
	return WorldConfig.resolve(self.Player:GetAttribute(WorldConfig.WorldAttribute))
end

--[[ THE CHIP, in fractions of the PAGE: how much of the search row it takes and the gap it leaves
	before the search box. The search bar gives up exactly `PAGER_WIDTH + PAGER_GAP` from its left
	edge, so these two numbers are the only place the row's split is decided.

	WIDE ENOUGH FOR THE LONGEST WORLD, which is what sets it. These are TextScaled labels: a name
	that does not fit shrinks rather than wrapping, so a chip sized for "CITY" would draw "FOREST
	MOUNTAINS" at half the type of every other world. 0.30 fits the longest at about a tenth off the
	shortest, and leaves the search box two thirds of the row — three times the width of the
	placeholder that has to sit in it. ]]
local PAGER_WIDTH = 0.30
local PAGER_GAP = 0.016

--[[ ...and the cluster INSIDE the chip, in the CHIP's scale rather than the page's. That is what
	makes the pager one object: the arrows and the name are children of the chip, so they move when
	it moves, and `_repaintWorld` hides all three by hiding it.

	THE NAME IS THE ONLY THING HERE WITH ROOM TO SPARE. The arrows are glyphs and want a square-ish
	box; everything left over after them and the insets goes to the name, which is the piece that has
	to hold a two-word world. ]]
--[[ How far a pager arrow and a tab swell under a cursor, read off the `Scale` attribute by
	`Components/Button`. Both are bare glyphs and words with no art behind them, so unlike the kit's
	pills there is no image reaction for the swell to sit on top of — but both are also SMALL, and a
	small thing needs a larger fraction before the movement is visible at all. Hence the arrow's, which
	is the biggest number in the UI: it is a 20-pixel guillemet. ]]
local ARROW_HOVER_SCALE = 1.12
local TAB_HOVER_SCALE = 1.03

local ARROW_WIDTH = 0.11
local ARROW_INSET = 0.045
local ARROW_HEIGHT = 0.62 -- of the chip's height; the guillemets are small glyphs in a tall box
local NAME_GAP = 0.02
local NAME_HEIGHT = 0.60
-- The least the tabs may keep clear of the page title and the close button. Note 11.
local TITLE_CLEARANCE = 0.020

--[[ Opacity is the state, which is the kit's own language (every navy surface in `UIAssets` is an
	80% fill whose pressed variant is the same colour at 100%). Idle sits a touch back so hover has
	somewhere to go; an end of the ladder goes most of the way out without vanishing, because an
	arrow that disappears takes the fact that there IS an end with it. ]]
local ARROW_IDLE = 0.15
local ARROW_HOVER = 0
local ARROW_DEAD = 0.70
-- Whether the pointer is on an arrow, kept on the arrow itself. See `_makeArrow`.
local HOVER_ATTRIBUTE = "PointerOver"

--- How far the world's name fades when it is not the world you are driving. Small: the name
--- changing is the loud signal, this is only the reminder underneath it.
local ELSEWHERE_FADE = 0.30

--[[ One arrow. A TextButton because the kit has no chevron art, and a glyph over a transparent box
	is the same "text over art" bargain every caption on this page already makes.

	SIZED IN THE CHIP'S SCALE, because that is what it is parented to — and its ZIndex is a
	formality for the same reason: a descendant draws over its ancestor whatever it is set to
	(`ZIndexBehavior.Sibling`), so the number only orders it against the name label beside it. ]]
function Page:_makeArrow(name: string, glyph: string, step: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false -- there is no background for it to tint
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Size = UDim2.fromScale(ARROW_WIDTH, ARROW_HEIGHT)
	button.ZIndex = self.SearchBar.ZIndex + 1
	button.FontFace = self.Title.FontFace
	button.TextColor3 = self.Title.TextColor3
	button.TextScaled = true
	button.Text = glyph
	button.TextTransparency = ARROW_IDLE

	local stroke = self.Title:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke:Clone().Parent = button
	end

	--[[ The pointer's state is REMEMBERED, not inferred, because the press moves the world and
		`_repaintWorld` then rewrites this transparency — under a cursor that has not gone anywhere.
		Without the flag, paging leaves the arrow you are still pointing at looking un-hovered until
		you move off it and back, which is every press of a pager. ]]
	button:SetAttribute(HOVER_ATTRIBUTE, false)
	button.MouseEnter:Connect(function()
		button:SetAttribute(HOVER_ATTRIBUTE, true)
		if button.Active then
			button.TextTransparency = ARROW_HOVER
		end
	end)
	button.MouseLeave:Connect(function()
		button:SetAttribute(HOVER_ATTRIBUTE, false)
		button.TextTransparency = if button.Active then ARROW_IDLE else ARROW_DEAD
	end)
	-- `Active` is what `_repaintWorld` turns off at the ends of the ladder, and Roblox stops firing
	-- the click on an inactive button — so the guard here is belt to that braces.
	button.MouseButton1Click:Connect(function()
		if button.Active then
			self:_setWorld(self._world + step)
		end
	end)

	--[[ The hover scale the tag will read. The TAG ITSELF goes on at the call site rather than here,
		because this returns an unparented button and the rule everywhere else in this project is that
		it lands last, once the instance is where it is going to live. ]]
	button:SetAttribute("Scale", ARROW_HOVER_SCALE)

	return button
end

--[[ Build the pager and give it the left end of the search row.

	THE CHIP IS THE SEARCH BAR'S OWN ART, RE-SLICED — the same trick `_buildMaps` plays on the slot
	square, and for the same reason. The authored bar is wired to `ScaleType.Stretch`, so its rounded
	caps squash the moment it is any width but the one it was drawn at; both it and the clone are
	switched to `Slice` here, against the `SliceCenter` already on the instance. It is correct for the
	stored texture (23,23,985,33 on a 1008x56 upload), which is the thing `UIAssets.Slice` warns has
	to be checked rather than assumed.

	Using the search bar's own art rather than something new is most of what makes the row read as
	one row. The pager and the search are two fields of the same kind — both narrow the grid, both go
	away on the maps tab — and drawing them out of the same material is what says so.

	THE ROW IS MEASURED, NOT TYPED. The chip takes the search bar's authored left edge, its authored
	height and its authored vertical position; the bar keeps its authored RIGHT edge and gives up the
	difference. So the row still ends exactly where the artist put it, at any chip width, and nudging
	SearchBar in the Explorer moves both halves together.

	ONE WORLD IN THE CONFIG BUILDS NO PAGER AT ALL, and the search bar keeps its full width — a chip
	holding a dead arrow either side of a name that cannot change is worse than no chip, and it would
	be taking a third of the row to say nothing. ]]
function Page:_buildWorldPager()
	local bar = self.SearchBar
	if not bar then
		return -- an un-authored search row: no pager rather than a page that throws in `new`
	end
	if #WorldConfig.Worlds < 2 then
		return
	end

	local left, top = UIGeom.topLeft(bar)
	local height = bar.Size.Y.Scale
	local shift = PAGER_WIDTH + PAGER_GAP
	if bar.Size.X.Scale - shift <= PAGER_WIDTH then
		-- The chip would leave the search box narrower than itself. Better a page with no pager than
		-- a search field there is no room to read what you typed in.
		warn(`[{PAGE_NAME}] no room on the search row for the world pager. Page left without one.`)
		return
	end

	local chip = bar:Clone()
	--[[ GuiObjects only. The bar carries no children today, but a UIStroke or a UICorner the artist
		adds to it later is part of the LOOK and the chip should wear it too — that is the whole point
		of cloning rather than building. A label or an icon dropped inside the bar is CONTENT, and a
		second copy of it riding on the chip is the one thing this could go wrong as. ]]
	for _, child in chip:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	chip.Name = "WorldChip"
	-- SIZE BEFORE PLACE, both here and on the bar below: `UIGeom.place` corrects against the rect's
	-- current size, so a resize afterwards positions by the old width. See UIGeom.
	chip.Size = UDim2.fromScale(PAGER_WIDTH, height)
	UIGeom.place(chip, left, top)
	if chip:IsA("ImageLabel") or chip:IsA("ImageButton") then
		chip.ScaleType = Enum.ScaleType.Slice
	end
	chip.Visible = true
	chip.Parent = self.PageUI

	bar.Size = UDim2.fromScale(bar.Size.X.Scale - shift, height)
	UIGeom.place(bar, left + shift, top)
	if bar:IsA("ImageLabel") or bar:IsA("ImageButton") then
		bar.ScaleType = Enum.ScaleType.Slice
	end

	--[[ The artist's magnifier and placeholder ride along by the same shift, which keeps them where
		they were INSIDE the bar. That matters to more than the look: `_buildSearch` derives the text
		box's padding from the gap between the placeholder and the bar's left edge, so moving both by
		one number leaves that gap alone and the field's text lands on the authored line. It is also
		why this runs BEFORE `_buildSearch` — see `Page.new`. ]]
	for _, gui in { self.SearchIcon, self.SearchPlaceholder } do
		if gui then
			UIGeom.place(gui, UIGeom.left(gui) + shift, UIGeom.top(gui))
		end
	end

	local back = self:_makeArrow("WorldBack", TEXT.Back, -1)
	UIGeom.place(back, ARROW_INSET, (1 - ARROW_HEIGHT) * 0.5)
	back.Parent = chip
	CollectionService:AddTag(back, "UIButton")

	local label = Instance.new("TextLabel")
	label.Name = "WorldName"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	-- Everything the two arrows and their insets leave behind, which is the widest a two-word world
	-- can be drawn without shrinking further than the shortest one does.
	label.Size = UDim2.fromScale(1 - 2 * (ARROW_INSET + ARROW_WIDTH + NAME_GAP), NAME_HEIGHT)
	label.ZIndex = bar.ZIndex + 1
	label.FontFace = self.Title.FontFace
	label.TextColor3 = self.Title.TextColor3
	label.TextScaled = true
	label.Text = ""
	UIGeom.place(label, ARROW_INSET + ARROW_WIDTH + NAME_GAP, (1 - NAME_HEIGHT) * 0.5)

	local stroke = self.Title:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke:Clone().Parent = label
	end
	label.Parent = chip

	local forward = self:_makeArrow("WorldForward", TEXT.Forward, 1)
	UIGeom.place(forward, 1 - ARROW_INSET - ARROW_WIDTH, (1 - ARROW_HEIGHT) * 0.5)
	forward.Parent = chip

	--[[ Both arrows are `UIButton`s, for the SOUNDS above all: the pager is the most-pressed control
		on this page and it was the one that made no noise. The swell comes with them, and the three
		transparency states in `_makeArrow` stay exactly as they are — those are what say "this arrow
		is dead", and the tag does not touch them.

		AN ARROW AT THE END OF THE LADDER STAYS SILENT, which is why `Components/Button` grew a
		`live()` check on the day this tag went on: `_repaintWorld` kills a spent arrow with
		`Active = false`, and a dead control that still chirps and swells is worse than one that never
		reacted at all. TAGGED AFTER PARENTING, the project's rule everywhere. ]]
	CollectionService:AddTag(forward, "UIButton")

	self._worldChip = chip
	self._worldBack = back
	self._worldLabel = label
	self._worldForward = forward
end

--[[ Everything that says which world is on the screen: the name, the two arrows, and the search
	field's placeholder. Called on build, on every page, and whenever the player's own world changes.

	THE PLACEHOLDER IS IN HERE and not in `_buildSearch` because it names the world — "Search City" —
	which is the one place the search's SCOPE can be stated before somebody trips over it rather than
	after. Header note 10. ]]
function Page:_repaintWorld()
	local worlds = #WorldConfig.Worlds
	local here = self._world == self:_currentWorld()
	--[[ THE TAB IS PART OF THIS, and it has to be: the pager belongs to the cars list and has nothing
		to page on a screen of map cards, but this runs from the world attribute changing and from
		every page open as well as from `_setTab`. Hiding it in the tab switch alone left the arrows
		reappearing over the maps the next time the page was opened. One owner of the flag. ]]
	local cars = self._tab == TAB_CARS

	--[[ ONE FLAG HIDES ALL THREE, because the arrows and the name are children of the chip. There is
		no longer a way for the cluster to half-disappear, and the "is there more than one world"
		half of the old test is gone with it: a chip that would have nothing to page is never built
		(`_buildWorldPager`), so its absence says the same thing. ]]
	if self._worldChip then
		self._worldChip.Visible = cars
	end

	if self._worldLabel then
		self._worldLabel.Text = caption(worldName(self._world))
		-- Faded when you are browsing somewhere you are not: quiet, because the name changing under
		-- your own press is the signal and this is only what is left of it a moment later.
		self._worldLabel.TextTransparency = if here then 0 else ELSEWHERE_FADE
		local stroke = self._worldLabel:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = self._worldLabel.TextTransparency
		end
	end

	local function paintArrow(button: TextButton?, live: boolean)
		if not button then
			return
		end
		-- Visibility is the chip's, above. This owns only which END of the ladder an arrow is at.
		button.Active = live
		button.TextTransparency = if not live
			then ARROW_DEAD
			elseif button:GetAttribute(HOVER_ATTRIBUTE) then ARROW_HOVER
			else ARROW_IDLE
	end
	paintArrow(self._worldBack, self._world > 1)
	paintArrow(self._worldForward, self._world < worlds)

	if self.SearchPlaceholder then
		self.SearchPlaceholder.Text = hint(TEXT.SearchHint, { world = worldName(self._world) })
	end
end

--[[ List a different world. The one write, and it writes nothing outside this page.

	The order matters: the filter decides what is on screen and hands the viewport grid its new list,
	and the count is taken afterwards against the world that is now showing. ]]
function Page:_setWorld(index: number)
	local resolved = WorldConfig.resolve(index)
	local changed = resolved ~= self._world
	self._world = resolved
	self:_repaintWorld()
	if changed then
		self:_applyFilter()
		self:_updateProgress()
	end
end

--[[ Follow the player. Teleporting while this screen is open moves the screen with you — you are
	somewhere else and the collection you are working on is the one in front of you. ]]
function Page:_watchWorld()
	self.Player:GetAttributeChangedSignal(WorldConfig.WorldAttribute):Connect(function()
		self:_setWorld(self:_currentWorld())
	end)
end

-- === The tabs ===============================================================
--[[ Header note 11. `CARS | MAPS` in the title bar's right half, with the page title to their left.
	The two names themselves are declared at the top of the file, because `Page.new` names one and a
	local declared below a function is not in that function's scope.

	EVERY TAB WEARS A PILL AND THE LIVE ONE IS COLOURED. That is not the kit's usual opacity language,
	because that language was written for the navy surfaces in `UIAssets` and this is the one bar in
	the UI that is bright orange: fading white toward orange barely darkens it. The first treatment
	was transparency plus a rule six thousandths of the page tall — about two pixels — and it lost. A
	pill is a different SHAPE, which survives any amount of colour underneath it, and a COLOURED pill
	against a silver one is a second signal on top of that.

	THE PILL IS THE ARTIST'S, WHICH IT COULD NOT BE BEFORE. `UIAssets` says a chip tall enough to
	hold tab-sized type comes out a quarter of the bar wide and that two of them do not fit — and
	that was true while the page TITLE sat in the middle of the bar. Note 9 moved it to the left
	edge, which is what freed the room: two pills at the pill's own 463x119 and the tabs' own height
	come to about 250px of a 565px bar, and they sit in the 400 the title left behind. So the one
	place this page had to depart from the kit is closed, and the tabs press the same button every
	other screen presses.

	IT IS `Stretch` WITH AN ASPECT CONSTRAINT, NOT `Slice` — the house rule for this art, recorded at
	length in `UIAssets.Slice`: the pill's rim is painted for its own proportion and 9-slicing it
	pins that rim at 1:1 texture pixels, which fattens it on anything smaller than the texture. The
	geometry here is worked out so the rendered aspect IS the texture's, and the constraint is the
	guard rather than the mechanism. ]]
local TAB_GAP = 0.030
local TAB_HEIGHT_RATIO = 0.86 -- of the page title's, so a tab reads as a peer of it and not a rival

--[[ THERE IS NO WIDTH CAP ANY MORE, and there was one for as long as a tab was a word with a rect
	behind it: tabs stretched to fill the bar left `INDEX CARS MAPS` evenly spaced across it, which
	read as three tabs one of which does nothing, so the pair was capped and the air either side of
	it is what made it a pair. The art settles that now — a pill is 463x119 and cannot be widened
	without going oval, so the only width a tab can have is the one its height gives it. ]]

--[[ THE PILL'S OWN PROPORTION, and the reason the tab strip is laid out from the pill inward rather
	than from the word outward the way it used to be. The art is 463x119 and must render at that
	aspect (see the note above), so the pill's WIDTH is not a free number — fix its height and its
	width follows. Everything else on the strip is then measured off the pill. ]]
local PILL_ASPECT = UIAssets.Size.Pill.X / UIAssets.Size.Pill.Y

--[[ How tall a pill is against the tab's own text box, and how much of it the word takes. These are
	the two numbers the drawn chip used, kept: the word renders at exactly the size it did before the
	art arrived, which is what stops "the tabs got a pill" also meaning "the tabs got bigger type".

	THE WORD'S WIDTH IS ITS OWN, because the pill is now four times as wide as it is tall and a text
	box that filled it would let `CARS` grow until the strip's two words were the loudest thing in
	the title bar. It is a cap and nothing more — the words are short and land well inside it, so
	both are limited by the box's HEIGHT and render at the same size as each other. ]]
local PILL_HEIGHT_RATIO = 1.30
local TAB_TEXT_HEIGHT = 1 / 1.30
local TAB_TEXT_WIDTH = 0.62
--[[ ONE PILL COLOUR PER TAB — keys of `UIAssets.Pill`, and the whole of what makes the two tabs
	tell you WHICH they are rather than only which is on.

	NEITHER IS ORANGE, and that is the one hard rule in here: the title bar these sit on is
	`TitleBar.Orange`, and the kit's orange pill on it is a pill-shaped smudge. Nor red, which is a
	warm neighbour of the same and is also what the CLOSE button two inches to the right is drawn in.

	BLUE IS THE BRAND and it is deliberately kept out of the Market's rarity ramp (see that page's
	note 4), so it is the one colour in the palette that is free to mean something structural rather
	than something about a car. It takes CARS, which is this page's own subject and the tab it opens
	on. PURPLE takes MAPS: after blue it is the cleanest of the seven against the orange, and it is
	as far from blue as the palette goes while keeping both tabs cool against a warm bar.

	GREEN WAS THE FIRST ANSWER AND IT LOST TO A CLASH IT DID NOT CAUSE. A tab reading "roads, and how
	much of each you have driven" wants to be green, and it renders slightly olive against the orange
	— but the deciding reason is the other tab: every card on CARS now prints its rate in the kit's
	money green (`RATE_COLOUR`, note 13), and a green MAPS pill directly above a grid of green
	numbers spends the one colour this page uses to mean CASH on a thing that is not cash. Purple
	means nothing anywhere else in this UI, which is exactly what a tab wants.

	NEITHER IS ORANGE OR RED, which is the same rule as above wearing its strongest hat: those two
	are the bar itself and the close button eight pixels to the right of them. ]]
local TAB_PILL = {
	[TAB_CARS] = "Blue",
	[TAB_MAPS] = "Purple",
}

--[[ ...and what a tab that is NOT live wears. Silver is the kit's own secondary button — the same
	pairing `RenameController` makes when it puts Blue on Save and Silver on Reset — so an idle tab
	is not a faded live one or a hole where a pill should be, it is the button the kit draws for a
	thing you can press but are not pressing. ]]
local TAB_PILL_IDLE = "Silver"

--[[ The word on the pill. White on a saturated live pill, which is what the kit puts on every
	coloured button it has; `#151D2D`, the kit's outline navy, on the light silver one, where white
	would be the one combination on this strip that cannot be read at all.

	THE STROKE FOLLOWS THE WHITE, not the state. It is the dark outline that holds white type off
	whatever is behind it, so it is on under white and off under navy — left on under the dark word
	it thickens into a smudge, which is the failure the very first tab treatment had. ]]
local TAB_LIVE_TEXT = Color3.new(1, 1, 1)
local TAB_IDLE_TEXT = Color3.fromRGB(21, 29, 45)

--[[ How much air the pair keeps off the close button. MORE THAN THE TITLE'S, because a tab is now
	wider than its own word — a pill is nearly four times its own height — so the clearance
	that used to be measured off the edge of `MAPS` is measured off the edge of nothing. ]]
local CLOSE_CLEARANCE = 0.026

--[[ Build the strip, and settle the bar's whole layout while we are here. `close` is the authored
	close button, passed in rather than found again because this page must not keep it on `self`
	(see `Page.new`).

	THE TITLE MOVES TO THE LEFT EDGE, which is this page's one departure from the kit — every other
	screen centres its title, and this is the only one with anything else in the bar. Moving the
	pager down to the search row (note 9) left the bar's left half empty and everything else crowded
	into its right, so the title has taken the empty half: the two ends of the bar carry something
	and the space between them reads as air rather than as a hole. It lines up with the pager chip
	directly underneath it, which is the same margin the artist set for the row.

	IT IS THE ROW'S LEFT EDGE, NOT THE SEARCH BAR'S. By the time this runs the search bar has already
	given its left end to the chip (`_buildWorldPager`, which `Page.new` runs first), so the bar's own
	left edge has moved and the chip's is the artist's. On a build with no pager the search bar still
	starts where it was drawn, which is why either one answers.

	THE TABS ARE RIGHT-ALIGNED against the close button rather than centred in what is left over.
	Centred was right while the title sat in the middle and the pair had a defined gap to sit in; with
	the title at the far left that gap is most of the bar, and a pair floating in the middle of it
	reads as neither the title's nor the button's. Nudge Close in the Explorer and they follow it. ]]
function Page:_buildTabs(close: GuiObject)
	local title = self.Title
	if not title then
		return
	end

	local row = self._worldChip or self.SearchBar
	if row then
		UIGeom.place(title, UIGeom.left(row), UIGeom.top(title))
	end

	local _, centreY = UIGeom.centre(title)
	local from = UIGeom.right(title) + TITLE_CLEARANCE
	local to = UIGeom.left(close) - CLOSE_CLEARANCE

	--[[ THE PILL IS SIZED FIRST AND EVERYTHING ELSE FOLLOWS IT, which is the layout turned round
		from the way it ran while the chip was a drawn rect. Its height is the tab's, its width is
		whatever that height makes it at the art's own aspect, and the WORD is then a box inside it.

		`aspect` converts the pill's pixel proportion into the page's scale space: `Size` on a GuiObject
		is a fraction of the parent on each axis independently, so a shape is only a shape once the
		page's own width-over-height is divided out of it. ]]
	local aspectConstraint = self.PageUI:FindFirstChildOfClass("UIAspectRatioConstraint")
	local aspect = aspectConstraint and aspectConstraint.AspectRatio or PAGE_ASPECT

	local pillHeight = title.Size.Y.Scale * TAB_HEIGHT_RATIO * PILL_HEIGHT_RATIO
	local pillWidth = pillHeight * PILL_ASPECT / aspect

	--[[ ...and shrunk to fit if the bar is narrower than the pair, rather than overlapped or
		overflowed. Both axes scale together so the art keeps its aspect at any size the bar leaves
		it — which is the whole reason a fit is a scale here and not a clamp on the width. ]]
	local room = to - from
	if 2 * pillWidth + TAB_GAP > room then
		local fit = (room - TAB_GAP) / (2 * pillWidth)
		if fit <= 0 then
			warn(`[{PAGE_NAME}] no room in the title bar for the tabs. Page left on cars only.`)
			return
		end
		pillWidth *= fit
		pillHeight *= fit
	end

	--[[ The word's own box is a fraction of the PILL and always was, but it is spent inside the
		button now rather than beside it — see the loop. A cap on the type, not a fill. ]]
	from = to - (2 * pillWidth + TAB_GAP)
	self._tabs = {}

	for index, tab in { TAB_CARS, TAB_MAPS } do
		--[[ THE BUTTON IS THE PILL, NOT THE WORD — 2026-08-26. It was the text box until then, with
			the art laid behind it as a sibling, and that made the hover and the click things that
			only existed over the LETTERS: the pointer crossed the pill, nothing lit, and the tab
			read as dead everywhere except the four characters in the middle of it. The pill is the
			button now and the art and the word are both inside it, so anywhere on the shape is on
			the tab — and the tag's swell lifts the pill and its word together instead of growing
			the word out of a chip that stayed where it was. ]]
		local button = Instance.new("TextButton")
		button.Name = `Tab{tab}`
		button.BackgroundTransparency = 1
		button.AutoButtonColor = false
		-- The word is a child now (see below), so the button carries none of its own.
		button.Text = ""
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Size = UDim2.fromScale(pillWidth, pillHeight)
		-- One above the title. The art and the word order themselves inside it.
		button.ZIndex = title.ZIndex + 1
		local pillLeft = from + (index - 1) * (pillWidth + TAB_GAP)
		UIGeom.place(button, pillLeft, centreY - pillHeight * 0.5)

		--[[ The guard, not the mechanism — the geometry above already renders this at the texture's
			own proportion. It is here for the day somebody nudges Close or the title and the fit
			branch starts firing: the pill loses width rather than going oval, which is the failure
			`UIAssets.Slice` records for every other way of stretching this art. ON THE BUTTON rather
			than on the chip, because the button is the pill's box now — constraining the art alone
			would letterbox it inside a hit area that had stopped matching what you can see. ]]
		local pillAspect = Instance.new("UIAspectRatioConstraint")
		pillAspect.AspectRatio = PILL_ASPECT
		pillAspect.DominantAxis = Enum.DominantAxis.Height
		pillAspect.Parent = button

		--[[ The chip. A CHILD of the button now, which it could not be while the button was the word:
			a descendant draws over its ancestor whatever its ZIndex (`ZIndexBehavior.Sibling`), so a
			chip parented to a button that PRINTED the word would have covered it. With the word moved
			out to a label of its own the two are siblings under the button and the ZIndex between them
			means what it says — art under, word over, both riding the button's box. ]]
		local chip = Instance.new("ImageLabel")
		chip.Name = `Tab{tab}Chip`
		chip.BackgroundTransparency = 1
		chip.BorderSizePixel = 0
		chip.ScaleType = Enum.ScaleType.Stretch
		chip.AnchorPoint = Vector2.new(0.5, 0.5)
		chip.Position = UDim2.fromScale(0.5, 0.5)
		chip.Size = UDim2.fromScale(1, 1)
		chip.ZIndex = button.ZIndex
		-- `_paintTabs` fills in the image; it runs before the page is ever visible.
		chip.Image = ""
		chip.Parent = button

		--[[ The word, over the chip and concentric with it — the same two numbers the drawn chip used,
			read as fractions of the pill, which is exactly what they were when they were multiplied
			out against it. So the type renders at the size it always did. ]]
		local label = Instance.new("TextLabel")
		label.Name = `Tab{tab}Label`
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.fromScale(TAB_TEXT_WIDTH, TAB_TEXT_HEIGHT)
		label.ZIndex = button.ZIndex + 1
		label.FontFace = title.FontFace
		label.TextColor3 = title.TextColor3
		label.TextScaled = true
		label.Text = caption(if tab == TAB_CARS then TEXT.TabCars else TEXT.TabMaps)

		local stroke = title:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke:Clone().Parent = label
		end
		label.Parent = button

		button:SetAttribute(HOVER_ATTRIBUTE, false)
		button.MouseEnter:Connect(function()
			button:SetAttribute(HOVER_ATTRIBUTE, true)
			self:_paintTabs()
		end)
		button.MouseLeave:Connect(function()
			button:SetAttribute(HOVER_ATTRIBUTE, false)
			self:_paintTabs()
		end)
		button.MouseButton1Click:Connect(function()
			self:_setTab(tab)
		end)

		button.Parent = self.PageUI

		--[[ Tagged, again for the sounds first: the chip is what says which tab is live and what says
			the pointer is on one, and both stay `_paintTabs`'s. What the tag adds is the small swell
			and the click the rest of the UI makes. No `Page` attribute — a tab does not open a page,
			it changes what THIS one is listing. After the parenting, the project's rule. ]]
		button:SetAttribute("Scale", TAB_HOVER_SCALE)
		CollectionService:AddTag(button, "UIButton")

		self._tabs[tab] = { button = button, chip = chip, label = label }
	end
end

--- Which tab is live, and which one the pointer is on. Split out because hovering repaints too.
function Page:_paintTabs()
	for tab, entry in self._tabs or {} do
		local live = tab == self._tab
		local hovered = entry.button:GetAttribute(HOVER_ATTRIBUTE) == true

		--[[ TWO LOOKUPS AND NOTHING ELSE. Which SET of pill art this tab is drawn from is the state —
			its own colour when live, the kit's Silver when not — and which image out of that set is
			the pointer. So hovering the tab you are already on lifts the colour it already wears
			instead of putting a different colour under it, which is the difference between a press
			being previewed and a tab appearing to change. ]]
		local set = UIAssets.Pill[if live then TAB_PILL[tab] else TAB_PILL_IDLE]
		if set then
			entry.chip.Image = UIAssets.url(if hovered then set.Hover else set.Idle)
		end
		entry.chip.Visible = true

		-- White on the saturated live pill, navy on the light silver one. The pill decides, and the
		-- pill is decided by `live` — so this is the same test wearing a second hat.
		entry.label.TextColor3 = if live then TAB_LIVE_TEXT else TAB_IDLE_TEXT
		entry.label.TextTransparency = 0

		local stroke = entry.label:FindFirstChildOfClass("UIStroke")
		if stroke then
			--[[ The stroke is the dark outline that holds white type off whatever is behind it, so it
				is on for exactly as long as the word is white. Under the navy word it would be a dark
				rim around dark type, which thickens it into a smudge — the failure the very first tab
				treatment had, in the one place it could still happen. ]]
			stroke.Transparency = if live then 0 else 1
		end
	end
end

--[[ Switch views. Everything that belongs to one tab and not the other is hidden rather than
	disabled — header note 11.

	SAFE TO CALL WITH THE TAB IT IS ALREADY ON, and `Page.new` does exactly that to put the page into
	its starting state through the same code path that every press takes. There is no separate
	"first draw" to keep in step with this. ]]
function Page:_setTab(tab: string)
	self._tab = if tab == TAB_MAPS then TAB_MAPS else TAB_CARS
	local cars = self._tab == TAB_CARS

	if self._scroll then
		self._scroll.Visible = cars
	end
	if self._maps then
		self._maps.Visible = not cars
	end
	-- The empty line belongs to the search, so it goes with it. `_applyFilter` owns whether it is
	-- showing at all; this only stops it surviving a tab switch.
	if self._empty then
		self._empty.Visible = self._empty.Visible and cars
	end

	for _, gui in { self.SearchBar, self.SearchIcon, self.SearchPlaceholder, self._search } do
		if gui then
			gui.Visible = cars
		end
	end
	-- The placeholder is only ever shown over an EMPTY field, so the search's own rule wins over the
	-- tab's when we come back to it.
	if cars and self.SearchPlaceholder and self._search then
		self.SearchPlaceholder.Visible = self._search.Text == ""
	end

	if self.ScrollBar and not cars then
		self.ScrollBar.Visible = false
	elseif cars then
		self:_updateScrollBar()
	end

	-- The pager is a filter on the cars list and has nothing to page on a screen of map cards.
	-- `_repaintWorld` owns whether it is showing — it reads `self._tab`, which this has just set.
	self:_repaintWorld()

	--[[ Nothing here tells the viewport grid anything. It watches the scroll's own `Visible`, so
		leaving this tab empties every car and coming back rebuilds the ones on screen — see note 5
		of `CarViewportGrid`, which is where that is arranged so a page with tabs does not have to
		know the module exists. ]]
	self:_paintTabs()
	if cars then
		self:_updateProgress()
	else
		self:_refreshProgress()
	end
end

-- === The maps ===============================================================
--[[ Header note 11. One card per world: its name, how far down that road you have ever got as a
	percentage, a bar of the same, and the distance itself underneath.

	ONE CARD PER WORLD, THREE ACROSS, filling the room the cars grid uses PLUS the search bar's row
	— the search goes away on this tab, and leaving a strip of empty panel where it was would read
	as something failing to load. Three across and not the grid's own four is what gives a card room
	for a number you can read across a room; the four-across cell is sized for a car and a name.

	AND THE COLUMN COUNT IS THE ASPECT, 2026-09-08. The room is fixed and the cards fill it, so
	choosing how many go across chooses how tall each one is: five worlds two across is three rows of
	245x92, and three across is two rows of 157x148, both measured in the same frame. A card at
	2.7:1 is what made everything on it look stretched out — the name, the number and the bar were
	sharing a strip five eighths the height they have now, and the road behind them was cropped to a
	slot. A SHORT LAST ROW IS CENTRED rather than left-ragged, so five cards read as a deliberate
	3-and-2 rather than as a grid with a card missing out of the corner.

	THE CARD ART IS THE CARS TAB'S SLOT, RE-SLICED. The authored slot is a square wired to
	`ScaleType.Stretch`, which ignores `SliceCenter`. On the letterbox card that turned the corner
	radius into an oval; on this one it would shrink the whole frame with the card, because 330x332
	of texture drawn at 157x148 takes the artist's 5px border down to 2 and the corners with it, and
	a rectangle whose border thins as it gets smaller stops matching every other rectangle in the
	kit. The artist's slice rect is already on the instance and is correct for the stored texture,
	so switching the clone to `Slice` is all it takes.

	...AND THE ONE THING SLICE CANNOT SAVE IS THE WEAVE, so the texture itself changed on 2026-09-08.
	9-slice holds the corners at 1:1 and stretches the MIDDLE, and the middle is where the checker
	lives. A square card's comes out square; the card was 2.7:1 that morning, so the band kept about
	two thirds of its width and an eighth of its height and the kit's 25px cells arrived as wide
	flat bars. That read as banding across the face rather than as the texture it is on every other
	surface in the kit, and it got worse the smaller the card. `UIAssets.Page.MapCard` is the
	identical export with the pattern layer hidden and nothing else touched, at the identical
	330x332, so the authored `SliceCenter` still measures true against it and only the face went
	flat. The cars tab keeps the weave: its slots render square, where a checker survives.

	THE SQUARE CARD COULD CARRY THE WEAVE AGAIN, AND STILL DOES NOT. The middle band is 282x284 of
	texture, and three across draws it at 109x100 — 0.39 by 0.35, near enough uniform that the 25px
	cells would arrive about 10 by 9 and read as cells. Two across drew the same band at 197x44,
	which is 0.70 by 0.155 and is where the flat bars came from, so the paragraph above stopped being
	the argument the same afternoon it was written. What keeps the flat print is the picture below:
	this face is a backdrop for a photograph now, and a weave showing through a road is dirt on the
	lens. Same texture, different reason for it.

	AND THE FLAT FACE IS WHAT THE PICTURE GOES ON, 2026-09-08. Each card carries the shot of its own
	road behind the numbers — `UIAssets.Worlds`, the same five pictures the Teleport page's cards
	wear, looked up by MAP and not by world index for the reason that block gives. Two things make
	it a reuse rather than a fifth aspect of the same art:

	  • `ScaleType.Crop` fills the box and centre-crops the overflow, so a 433x620 portrait lands on
	    the card with no new export and no distortion. What survives is a centred band of each shot
	    — the road running to the horizon with the skyline either side of it, which is the part that
	    says which world this is. THE SQUARER CARD KEEPS MORE OF IT: cropping a 0.70 portrait to a
	    1.07 box holds about two thirds of the picture's height where the old strip held a fifth, so
	    the same five uploads got better by a layout change.
	  • it is faded most of the way back to the navy (`MAP_PHOTO_FADE`), because this is a card with
	    a number on it and not a postcard. The picture is there to tell the five apart at a glance
	    by colour before anything is read.

	A WORLD WITH NO SHOT GETS NO PICTURE, deliberately. `UIAssets.worldThumb` answers the artist's
	`PlaceImage` for an unphotographed map, which is a flat white rect — right on the Teleport card,
	which is drawn around it, and a white blob behind a number here. So this reads `UIAssets.Worlds`
	directly and leaves the face plain when there is nothing to show. ]]
local MAP_COLUMNS = 3
--[[ Where the four pieces sit inside a card, in fractions of it: name across the top, the number
	big through the middle, the bar under that, and the distance last. Centred, all of them — a card
	with everything ranged left has a hole in it.

	EVERY ONE OF THESE IS A FRACTION OF A CARD THAT CHANGED SHAPE, so they were all re-cut when the
	grid went three across. The card gained three fifths of its height and lost a third of its width,
	and carrying the old fractions over would have scaled all four of these up by that three fifths:
	a bar as fat as the panel's own bottom bar, which is not a detail on a card. The rule they are
	cut to is that the NUMBER is the one thing meant to grow with the card. It did, 29 rendered
	pixels to 47. Everything else keeps about the size it had and spends the new room on air.

	THE NAME'S BOX IS THE SHORTEST OF THE FOUR ON THE TALLEST CARD IT HAS EVER HAD, which looks
	backwards until you watch five of them at once. `TextScaled` maximises each label on its own, so
	a box taller than the longest name can use is a box where the SHORT names come out bigger: at
	0.13 the same row read CITY at 19 pixels and FOREST MOUNTAINS at 14, because only the long one
	was still bounded by the card's width. Cutting the box to just under that width bound puts every
	card's name on the same 14, and five cards drawn to one type scale is the thing that stops them
	looking like five unrelated cards. It holds at any resolution: both bounds are fractions of the
	same card, so their order cannot change with the render size.

	It is also why the name is not `TextWrapped`'s problem here. A box tall enough to let two lines
	beat one is a box where the long names wrap, and this one is nowhere near it. ]]
local MAP_NAME = { y = 0.16, height = 0.095, width = 0.86 }
--- 0.86 keeps the longest name inside the picture: the well is 10 pixels in from each edge, which
--- is 0.87 of a card this size and more of a bigger one, so the name never reaches the rim.
local MAP_PERCENT = { y = 0.44, height = 0.32, width = 0.86 }
--[[ The bar went 0.075 to 0.12 to 0.08 in one day and came out the same bar it started as. Measured
	in one frame, so the three numbers are comparable: 0.075 of the old 92-pixel card drew 7 pixels,
	which is a pencil line under the number rather than a meter, and the fill it exists to show has
	to read at a few percent. 0.12 took it to 11. Then the card grew to 148 under a fraction that
	had just been set against the old one, and 0.08 is what draws 11 pixels there. The page's own
	bottom bar is the yardstick, since it is the same art doing the same job one panel down: 26
	pixels in that frame, so the card's bar is a bit under half of it.

	WIDTH WENT UP IN THE SAME EDIT AND THE BAR STILL GOT SHORTER, because the card lost a third of
	its width: 0.78 of 157 is 122 pixels against the 177 that 0.72 of 245 drew. That is the trade a
	square card makes, and the raised fraction is what stops it also reading as a stub — a progress
	bar reads as one by spanning the thing it is measuring. ]]
local MAP_BAR = { y = 0.71, height = 0.08, width = 0.78 }
local MAP_DISTANCE = { y = 0.855, height = 0.09, width = 0.80 }

--[[ How far inside the card the picture sits, in PIXELS — the art's 5px `#151D2D` border plus its
	5px `#384769` rim, which is the well the artist drew for something to go in.

	PIXELS AND NOT A FRACTION, because those two bands are not a fraction of the card: 9-slice holds
	the corner and edge regions at 1:1 texture pixels, so they stay 5 and 5 whatever size the card
	renders at. Measured in a real frame rather than assumed — the border came back exactly 5 screen
	pixels wide and the rim exactly 5, which is also the proof that `SliceScale` is still 1. ]]
local MAP_PHOTO_INSET = 10

--[[ How far the road picture is faded back toward the card's own navy face. The number is the whole
	argument for putting a picture there at all: at 0 it is a photograph with a percentage written
	across it, and the big white number stops being the thing you see first. This is a card in a
	catalogue, so the picture is a WASH of the world's colour — sand, pines, ice, neon — under type
	that still reads as type. ]]
local MAP_PHOTO_FADE = 0.55

--- How far the whole card fades when its road cannot be scored. It is not a locked state — there is
--- nothing to unlock — so this is lighter than the cars tab's, and it applies to the art as well.
local MAP_UNBUILT_FADE = 0.45

--[[ Build the cards, one per world, once.

	THE TEMPLATE IS `_buildGrid`'S DETACHED COPY, kept on the page for exactly this. The authored
	samples are destroyed the moment that pass has measured them (header note 1), and a destroyed
	instance cannot be cloned — so this could not go and find its own. ]]
function Page:_buildMaps()
	local grid, template = self._grid, self._slotTemplate
	if not (grid and template) then
		return
	end

	--[[ The maps view runs from the SEARCH BAR's top edge, not the grid's — the search bar is not on
		this tab, so its row is the maps' to use. `_measure` already worked out where the grid ends;
		this only moves the top up. ]]
	local top = math.min(UIGeom.top(self.SearchBar), grid.top)
	local height = grid.top + grid.height - top

	local frame = Instance.new("Frame")
	frame.Name = "Maps"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Position = UDim2.fromScale(grid.left, top)
	frame.Size = UDim2.fromScale(grid.width, height)
	frame.ZIndex = self.Slots.ZIndex
	frame.Visible = false
	frame.Parent = self.Slots
	self._maps = frame

	-- The grid's own gaps, converted out of its viewport fractions and back into the page's, so the
	-- two tabs are spaced by the same numbers the artist drew between the slots.
	local gapX = grid.padX * grid.width
	local gapY = grid.padY * grid.height
	local gapWidth = gapX / grid.width
	local gapHeight = gapY / height
	local count = #WorldConfig.Worlds
	local rows = math.ceil(count / MAP_COLUMNS)
	local cellWidth = (1 - gapWidth * (MAP_COLUMNS - 1)) / MAP_COLUMNS
	local cellHeight = (1 - gapHeight * (rows - 1)) / rows

	self._mapCards = {}

	for index = 1, count do
		local column = (index - 1) % MAP_COLUMNS
		local row = math.floor((index - 1) / MAP_COLUMNS)
		--[[ How many cards are on THIS row, and how far in the row starts because of it. A full row
			indents by zero and this is the identity; the block header's 3-and-2 is the case it is
			here for. Worked from the row's own width rather than from a spare-columns count so it
			stays right for any number of worlds against any column count. ]]
		local onRow = math.min(MAP_COLUMNS, count - row * MAP_COLUMNS)
		local indent = (1 - (onRow * cellWidth + (onRow - 1) * gapWidth)) / 2

		local card = template:Clone()
		card.Name = `Map{index}`
		card.AnchorPoint = Vector2.new(0, 0)
		card.Size = UDim2.fromScale(cellWidth, cellHeight)
		card.Position = UDim2.fromScale(
			indent + column * (cellWidth + gapWidth),
			row * (cellHeight + gapHeight)
		)
		card.ZIndex = frame.ZIndex
		if card:IsA("ImageLabel") or card:IsA("ImageButton") then
			-- See the block header: the authored square is `Stretch`, and a stretched slice rect is
			-- no slice rect at all.
			card.ScaleType = Enum.ScaleType.Slice
			--[[ ...and the weave-free print of that same square, which is the other half of the same
				note. Set here rather than authored, so the CARS tab keeps the artist's slot exactly
				as it is: the two textures are the same crop of the same group and the only thing
				this one drops is the pattern layer the stretch cannot carry. `SliceCenter` is left
				alone deliberately — both are stored 330x332, so the authored rect is already right
				for this one. ]]
			card.Image = UIAssets.url(UIAssets.Page.MapCard)
		end

		--[[ The road, in the well the card art draws — see the block header. It goes in FIRST so
			every label built below lands on top of it: these all sit at `card.ZIndex + 1` and this
			one at the card's own, and a child draws over its parent at equal ZIndex. ]]
		local shot = UIAssets.Worlds[WorldConfig.mapFor(index) or ""]
		local photo: ImageLabel? = nil
		if shot then
			photo = Instance.new("ImageLabel")
			photo.Name = "Thumb"
			photo.BackgroundTransparency = 1
			photo.BorderSizePixel = 0
			photo.AnchorPoint = Vector2.new(0.5, 0.5)
			photo.Position = UDim2.fromScale(0.5, 0.5)
			photo.Size = UDim2.new(1, -2 * MAP_PHOTO_INSET, 1, -2 * MAP_PHOTO_INSET)
			photo.Image = UIAssets.url(shot)
			-- Fills the strip and crops what will not fit, rather than squashing a portrait into it.
			photo.ScaleType = Enum.ScaleType.Crop
			photo.ImageTransparency = MAP_PHOTO_FADE
			photo.ZIndex = card.ZIndex
			photo.Parent = card
		end

		-- `MapName` and not `Name`: a child called Name can never be reached by dot access, because
		-- the Instance property of that name shadows it. It matches the cars tab's `CarName` anyway.
		local name = self:_mapLabel(card, "MapName", MAP_NAME)
		name.Text = caption(worldName(index))

		local percent = self:_mapLabel(card, "Percent", MAP_PERCENT)

		--[[ The bar is the bottom bar's own two images, cloned. Both are 9-sliced art whose rects are
			measured against the stored texture (`UIAssets.Slice`), and the track is authored
			`Stretch` for the same reason the slot is — so both clones are switched to `Slice` here.
			The fill lives INSIDE the track and is sized as a fraction of it, which is what makes an
			empty bar an empty track rather than a stray cap floating at the left. ]]
		local bar = (self.ProgressTrack or self.ProgressFill):Clone()
		bar:ClearAllChildren()
		bar.Name = "Bar"
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, MAP_BAR.y)
		bar.Size = UDim2.fromScale(MAP_BAR.width, MAP_BAR.height)
		bar.ZIndex = card.ZIndex + 1
		bar.Visible = true
		if bar:IsA("ImageLabel") then
			bar.ScaleType = Enum.ScaleType.Slice
			bar.ImageTransparency = 0
		end
		bar.Parent = card

		local fill = self.ProgressFill:Clone()
		fill:ClearAllChildren()
		fill.Name = "Fill"
		fill.AnchorPoint = Vector2.new(0, 0.5)
		fill.Position = UDim2.fromScale(0, 0.5)
		fill.Size = UDim2.fromScale(0, 1)
		fill.ZIndex = bar.ZIndex + 1
		fill.Visible = false
		if fill:IsA("ImageLabel") then
			fill.ScaleType = Enum.ScaleType.Slice
			fill.ImageTransparency = 0
		end
		fill.Parent = bar

		local distance = self:_mapLabel(card, "Distance", MAP_DISTANCE)
		distance.TextColor3 = self.SearchPlaceholder.TextColor3

		card.Parent = frame
		table.insert(self._mapCards, {
			world = index,
			card = card,
			photo = photo,
			name = name,
			percent = percent,
			bar = bar,
			fill = fill,
			distance = distance,
		})
	end
end

--- One centred line on a card, in the page's font. The three of them differ only by their box.
function Page:_mapLabel(card: GuiObject, name: string, box: { y: number, height: number, width: number }): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, box.y)
	label.Size = UDim2.fromScale(box.width, box.height)
	label.ZIndex = card.ZIndex + 1
	label.FontFace = self.ProgressLabel.FontFace
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Text = ""

	local stroke = self.ProgressLabel:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke:Clone().Parent = label
	end

	label.Parent = card
	return label
end

--[[ Re-read the broadcast and repaint the cards, plus the bottom bar when this tab is up.

	A MAP WITH NO ENTRY CANNOT BE SCORED — note 11, and `WorldService._publishProgress` is the other
	half of that contract: it publishes a measurable world at 0 and omits an unmeasurable one, so
	absent here really does mean "there is no road", not "you have not driven it". ]]
function Page:_refreshProgress()
	self._progress = WorldConfig.decodeProgress(self.Player:GetAttribute(WorldConfig.ProgressAttribute))

	local total, scored = 0, 0
	for _, entry in self._mapCards or {} do
		local best = self._progress[entry.world]
		local fade = if best then 0 else MAP_UNBUILT_FADE

		if best then
			total += best.fraction
			scored += 1
			-- FLOORED, so a road you are one tile short of the top of does not congratulate you.
			entry.percent.Text = caption(TEXT.MapPercent, { percent = math.floor(best.fraction * 100) })
			entry.fill.Size = UDim2.fromScale(best.fraction, 1)
			-- A zero-width 9-slice still draws its own two caps; nothing driven should show nothing.
			entry.fill.Visible = best.fraction > 0
			entry.bar.Visible = true
			entry.distance.Text = RewardConfig.formatDistance(best.studs) or ""
		else
			entry.percent.Text = caption(TEXT.MapUnbuilt)
			entry.fill.Visible = false
			entry.bar.Visible = false
			entry.distance.Text = ""
		end

		if entry.card:IsA("ImageLabel") or entry.card:IsA("ImageButton") then
			entry.card.ImageTransparency = fade
		end
		--[[ The picture fades WITH the card rather than to the same number: it is already sitting at
			`MAP_PHOTO_FADE`, so the two are composed as alphas — what is left of it after the card's
			own fade. Assigning `fade` here would make an unbuilt world's picture the SOLIDEST thing
			on the tab. ]]
		if entry.photo then
			entry.photo.ImageTransparency = 1 - (1 - MAP_PHOTO_FADE) * (1 - fade)
		end
		for _, label in { entry.name, entry.percent, entry.distance } do
			label.TextTransparency = fade
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = fade
			end
		end
	end

	if self._tab == TAB_MAPS then
		--[[ The bar averages the maps that CAN be scored, not all of them. Averaging an unbuilt world in
			as a zero would let adding a world to the config knock every existing player's number
			down, which is a lie about them told by a config edit. ]]
		local mean = if scored > 0 then total / scored else 0
		self.ProgressFill.Size = UDim2.fromScale(mean * 0.9944, self.ProgressFill.Size.Y.Scale)
		self.ProgressFill.Visible = mean > 0
		self.ProgressLabel.Text = caption(TEXT.MapsProgress, { percent = math.floor(mean * 100) })
	end
end

--- The server setting a new record while the screen is open. Same house pattern as ownership.
function Page:_watchProgress()
	self.Player:GetAttributeChangedSignal(WorldConfig.ProgressAttribute):Connect(function()
		self:_refreshProgress()
	end)
	self:_refreshProgress()
end

-- === The authored scrollbar =================================================

--- Size and place `ScrollBar` from the scroll position, and hide it when there is nothing to scroll.
function Page:_updateScrollBar()
	local scroll, bar, grid = self._scroll, self.ScrollBar, self._grid
	if not (scroll and bar and grid) then
		return
	end

	local window = scroll.AbsoluteWindowSize.Y
	local canvas = scroll.AbsoluteCanvasSize.Y
	if window <= 0 or canvas <= window + 1 then
		bar.Visible = false
		return
	end

	local track = grid.height
	local thumb = math.max(track * (window / canvas), track * MIN_THUMB)
	local progress = math.clamp(scroll.CanvasPosition.Y / (canvas - window), 0, 1)

	bar.Visible = true
	-- Size first: `place` corrects against the bar's current height, so a thumb resized afterwards
	-- would be positioned by the old one.
	bar.Size = UDim2.fromScale(bar.Size.X.Scale, thumb)
	UIGeom.place(bar, UIGeom.left(bar), grid.top + progress * (track - thumb))
end

--[[ Dragging the thumb. Worked from the DELTA since the grab rather than from where the pointer is:
	AbsolutePosition and the pointer's own coordinates disagree by the Gui inset, and a delta cannot
	be wrong about an offset that is the same at both ends. ]]
function Page:_bindScrollBarDrag()
	local scroll, bar = self._scroll, self.ScrollBar
	if not (scroll and bar) then
		return
	end

	bar.Active = true
	local drag: { pointer: number, canvas: number }? = nil

	local function isDragInput(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end

	bar.InputBegan:Connect(function(input)
		if isDragInput(input) then
			drag = { pointer = input.Position.Y, canvas = scroll.CanvasPosition.Y }
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not drag then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		local scrollable = scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y
		local travel = scroll.AbsoluteSize.Y - bar.AbsoluteSize.Y
		if scrollable <= 0 or travel <= 0 then
			return
		end

		local moved = (input.Position.Y - drag.pointer) * (scrollable / travel)
		scroll.CanvasPosition = Vector2.new(0, math.clamp(drag.canvas + moved, 0, scrollable))
	end)

	UserInputService.InputEnded:Connect(function(input)
		if isDragInput(input) then
			drag = nil
		end
	end)
end

-- === Search =================================================================

--[[ The search field is art plus a placeholder label; the TextBox over it is built here.

	It covers the WHOLE bar so the click target is the bar, and carries a UIPadding that puts its
	scaled text on exactly the line the authored placeholder sits on — the placeholder's own box is
	a third of the bar's height, and TextScaled reads the box it is given. ]]
function Page:_buildSearch()
	local bar = self.SearchBar
	local placeholder = self.SearchPlaceholder

	local inset = (UIGeom.left(placeholder) - UIGeom.left(bar)) / bar.Size.X.Scale
	local vertical = (bar.Size.Y.Scale - placeholder.Size.Y.Scale) / 2 / bar.Size.Y.Scale

	local box = Instance.new("TextBox")
	box.Name = "SearchInput"
	box.BackgroundTransparency = 1
	-- The box IS the bar's rect, so it copies the bar's anchor along with its Position and Size.
	-- Taking the Position without the anchor is how it would land half a bar off-centre.
	box.AnchorPoint = bar.AnchorPoint
	box.Position = bar.Position
	box.Size = bar.Size
	box.ZIndex = placeholder.ZIndex + 2
	box.FontFace = placeholder.FontFace
	box.TextColor3 = Color3.new(1, 1, 1)
	box.TextScaled = true
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Center
	box.ClearTextOnFocus = false
	box.PlaceholderText = "" -- the authored label is the placeholder; see below
	box.Text = ""

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(math.max(inset, 0), 0)
	padding.PaddingRight = UDim.new(math.max(inset, 0), 0)
	padding.PaddingTop = UDim.new(math.max(vertical, 0), 0)
	padding.PaddingBottom = UDim.new(math.max(vertical, 0), 0)
	padding.Parent = box

	local stroke = placeholder:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke:Clone().Parent = box
	end

	box.Parent = self.PageUI
	self._search = box

	box:GetPropertyChangedSignal("Text"):Connect(function()
		-- The authored label IS the placeholder, so it is driven rather than replaced: visible only
		-- while the field is empty, focused or not.
		placeholder.Visible = box.Text == ""
		self:_setQuery(box.Text)
	end)
	placeholder.Visible = true
end

function Page:_setQuery(text: string)
	local query = normalize(text)
	if query == self._query then
		return -- punctuation-only edits don't change the result set
	end
	self._query = query
	self:_applyFilter()
end

function Page:_applyFilter()
	if not self._scroll then
		return
	end

	local visible = 0
	--[[ The slots that are showing, in the order the grid will lay them out — which is what the
		viewport grid takes, and is not the same list as `_entries`: a UIGridLayout lays out visible
		children only, so a search moves every slot behind the query up into the rows the window is
		over. `_entries` is built in LayoutOrder order, so collecting it in order collects the grid. ]]
	local cells = {}
	--[[ Which OTHER worlds this query would have found something in, as a set. It costs one table
		insert on a pass this loop was making anyway, and it is what turns "no cars match that" into
		"try Desert" — header note 10. It leans on the search matching a locked car's real name, which
		note 5 records as deliberate. ]]
	local elsewhere = {}
	for _, entry in self._entries do
		local hit = self._query == "" or string.find(entry.search, self._query, 1, true) ~= nil
		local matches = hit and entry.world == self._world
		entry.slot.Visible = matches
		if matches then
			visible += 1
			table.insert(cells, entry)
		elseif hit then
			elsewhere[entry.world] = true
		end
	end

	self._visibleCount = visible
	if self._empty then
		self._empty.Visible = visible == 0
		if visible == 0 then
			self._empty.Text = self:_emptyText(elsewhere)
		end
	end

	-- A narrowed list is a different list; leaving it scrolled halfway down reads as empty.
	self._scroll.CanvasPosition = Vector2.new(0, 0)
	self:_applyLayout()
	-- After the layout, so the grid tests the new list against the new canvas rather than the old one.
	self._views:setCells(cells)
end

--[[ What an empty grid says. Three different things, because an empty grid means three different
	things and only one of them is "there is nothing to find" — header note 10.

	`elsewhere` is the set of other worlds the query DID match in. One of them gets named, because a
	name is a direction and the arrows to follow it are on the screen; several get "another world",
	because listing three is a wall of text on a line that is one line of type tall. ]]
function Page:_emptyText(elsewhere: { [number]: boolean }): string
	local here = worldName(self._world)
	if self._query == "" then
		-- Not reachable while every world has a ladder; see `TEXT.NoCars`.
		return caption(TEXT.NoCars, { world = here })
	end

	local only, count = nil, 0
	for index in elsewhere do
		only = if count == 0 then index else only
		count += 1
	end

	if count == 0 then
		return caption(TEXT.NoMatch)
	elseif count == 1 then
		return caption(TEXT.NoMatchHere, { world = here, other = worldName(only :: number) })
	end
	return caption(TEXT.NoMatchAnywhereHere, { world = here })
end

-- === Ownership ==============================================================

--[[ Re-read the owned set and repaint every slot. Cheap enough to do wholesale — it is one loop over
	the roster and a handful of property writes.

	EVERY SLOT, NOT EVERY VISIBLE ONE. The worlds you are not looking at are repainted too, so paging
	to one is a filter pass and never a state pass; that is what keeps `_setWorld` down to a layout.
	Twenty-nine slots is nothing, and the alternative is two code paths that have to agree.

	THE ONE EXPENSIVE THING IS DONE ONLY WHEN IT HAS TO BE. A slot going from locked to stolen needs a
	different MODEL, not a different colour — a cut-out has been flattened, and there is no putting
	that back — so the grid is told to drop it and build the car instead. That is compared against the
	last state rather than done every pass, because this runs on every write of the owned attribute
	and rebuilding a world of cars each time one is stolen is a world's work for one car's worth of
	change. ]]
function Page:_refreshOwnership()
	local owned = parseOwned(self.Player:GetAttribute(OWNED_ATTRIBUTE))
	-- Kept, because the count along the bottom is per world and is re-taken every time the pager
	-- moves — at which point the attribute has not changed and there is nothing to re-parse.
	self._owned = owned

	for _, entry in self._entries do
		local has = owned[entry.body] == true
		local locked = not has
		if entry.silhouette ~= locked then
			entry.silhouette = locked
			self._views:invalidate(entry)
		end
		entry.label.Text = if locked then LOCKED_TEXT else displayName(entry.body)
		-- Guarded rather than assumed: an authored slot that stopped being an image would otherwise
		-- throw inside Page.new, and a page that throws there takes the other pages down with it.
		if entry.slot:IsA("ImageLabel") or entry.slot:IsA("ImageButton") then
			entry.slot.ImageTransparency = if has then 0 else UNOWNED_IMAGE_TRANSPARENCY
		end
		--[[ BOTH LINES FADE TOGETHER, and the rarity's COLOUR is untouched by this — header note 12.
			The name is swapped for `???` above and this one is not: what kind of car is sitting in a
			slot you have not filled is the thing that makes it worth filling, and a faded gold still
			reads as gold. ]]
		local fade = if has then 0 else UNOWNED_TEXT_TRANSPARENCY
		for _, label in { entry.label, entry.rarityLabel } do
			label.TextTransparency = fade
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = fade
			end
		end

		--[[ ...AND THE PRICE, which is the one thing on the slot that is not faded on a locked car
			but REMOVED from it — header note 13. A car you have not got has no price on this screen,
			and a car with no tier has none on any screen.

			THE RARITY MOVES WITH IT. It has the strip to itself when there is no price beside it and
			takes the left end when there is, so the line is either centred or ranged at both ends and
			never one word hanging off the left of an empty row. Re-placed rather than just resized:
			these are centre-anchored, so a box that changes width changes where its middle is. ]]
		local priced = has and entry.rate ~= ""
		entry.rateLabel.Visible = priced
		entry.rarityLabel.Size = UDim2.fromScale(
			if priced then RARITY_SHARED_WIDTH else RARITY_WIDTH,
			RARITY_HEIGHT
		)
		entry.rarityLabel.TextXAlignment = if priced
			then Enum.TextXAlignment.Left
			else Enum.TextXAlignment.Center
		UIGeom.place(entry.rarityLabel, RARITY_LEFT, RARITY_TOP)
	end

	-- The invalidations above dropped models; this is what puts the replacements in the queue.
	self._views:refresh()
	self:_updateProgress()
end

--[[ The bottom bar, counted over THE WORLD ON SCREEN — header note 3. Four ladders to finish rather
	than one out of twenty-nine, which is also what makes the bar move at a rate a player can feel:
	one car in eight is a visible step and one car in twenty-nine is not. ]]
function Page:_updateProgress()
	local owned = self._owned
	local found, total = 0, 0
	for _, entry in self._entries do
		if entry.world == self._world then
			total += 1
			if owned[entry.body] then
				found += 1
			end
		end
	end
	self:setProgress(found, total)
end

function Page:_watchOwnership()
	self.Player:GetAttributeChangedSignal(OWNED_ATTRIBUTE):Connect(function()
		self:_refreshOwnership()
	end)
	self:_refreshOwnership()
end

-- === Bottom bar =============================================================

--- Drive the bottom bar. `found`/`total` also set the caption.
function Page:setProgress(found: number, total: number)
	local ratio = total > 0 and math.clamp(found / total, 0, 1) or 0
	-- The track is the full page width, so the fill's own scale is the ratio of it.
	self.ProgressFill.Size = UDim2.fromScale(ratio * 0.9944, self.ProgressFill.Size.Y.Scale)
	-- A zero-width 9-slice still draws its own corners; nothing stolen should show nothing.
	self.ProgressFill.Visible = ratio > 0
	-- "STOLEN", not "Found" — header note 10.
	self.ProgressLabel.Text = caption(TEXT.Progress, { found = found, total = total })
end

return Page
