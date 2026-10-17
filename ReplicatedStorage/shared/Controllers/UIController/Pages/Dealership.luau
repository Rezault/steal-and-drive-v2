--[[
	Dealership page — THE CARS INVENTORY  (client)
	----------------------------------------------
	"Everything I own, and one gesture that does something with it." A full-height column of cards
	down the right of the screen, the way a car game lays out a garage: the list is the UI, the world
	behind it is the car. Trello: "Cars Inventory".

	2026-08-24 REWRITE — WHAT WENT AND WHY, because most of this file used to be the other half.

	  • THE DETAIL PANE IS GONE. It was a second panel in the empty left column holding a car
	    viewport, six bars, a rate line and five buttons, and the price of it was that every verb on
	    this screen took TWO taps: pick a card, read the pane, press the button. The pane's own empty
	    state said "PICK A CAR" out loud, which is the tell — a screen whose first job is to make you
	    choose a row before it will do anything is a menu in front of a menu. The stats it carried
	    are now a TOOLTIP (see below) and the verb it carried is now the press itself.

	  • A PRESS COMMITS. Tap a card and the car goes out into the street; tap it again and it comes
	    back in; in bay mode a tap parks it on the bay you walked up to. There is no selection state
	    on this page any more and no primary button — `_press` is the whole of it.

	  • SELLING LEFT THE SCREEN ENTIRELY, on the owner's call: it is a location you drive to. Sell
	    mode, the tick boxes, the SELL toggle on the search row and the sell summary are all deleted.
	    `InventoryConfig.Sell` and `GarageService.sellCars` are intact and are what the lot was built
	    on — `SellService` is the only path a player can reach that takes a car away from them.

	  • FAVOURITE IS A CHIP ON THE CARD. One small round button on the card's right edge. On a mouse
	    it is tucked off the edge and slides in when you point at the card; on a touch device it is
	    always out, because there is no hover to reveal it with. See `_setChips`.

	  • THE LOCK IS GONE, later the same day. It was the second chip and it was a RULE — the server
	    refused to sell a locked car — and the owner's call is that one flag is enough. The job it was
	    doing has moved to the sell lot, where a favourite costs a SECOND PRESS rather than leaving a
	    car unsellable until you remember to unlock it: the panel that asks marks a starred car with
	    this same gold star and an amber line, and its SELL IT asks once more (`SellPopupController`).
	    NOTHING READS `Garage.Locked` ANY MORE, so a profile written before this keeps a list nobody
	    looks at and no car of anybody's is stranded.

	NINE THINGS TO KNOW BEFORE CHANGING ANY OF IT.

	1. IT HAS TWO MODES AND THE WAY IT WAS OPENED IS WHAT PICKS ONE.

	       podium prompt -> DealershipBay(n) -> OpenPage   = BAY MODE, "which car stands here"
	       the HUD rail  ->                     OpenPage   = INVENTORY MODE, "my cars"

	   `setBay` ARMS the bay and `Open` consumes it — see note 2 — so the page never has
	   to ask which bay you meant and can never be wrong about it. What changes between the modes is
	   the title, the caption over the list, whether the LEAVE EMPTY card exists, what a press
	   publishes, and what the tooltip's last line says a press will do. Nothing else.

	2. THE MODE ARBITRATION IS AN ARMED FLAG, AND IT HAS TO BE. `DealershipController` publishes
	   `DealershipBay` and then `OpenPage` on the same frame; `UIController` calls this page's `Open`
	   after that. So an open that was NOT preceded by a bay is a rail open, and the flag is the only
	   thing that can tell them apart — the page has no other way to see which button was pressed.

	   IT LIVES IN `Open`/`Close` AND NOT IN `StartOpenThread`, which is a reversal — until
	   2026-08-24 this page deliberately used the `Start*Thread` pair so that `UIController` would
	   still run the kit's shared scale tween over it, and the note here said not to "simplify" it
	   into `Open`. That reason is now the reason against: this page has an entrance of its own (note
	   10) and the shared 0.9-to-1 scale over the top of a column sliding in from the edge is two
	   animations on one object. `UIController` documents `Open`/`Close` as exactly this escape
	   hatch. THE ONE THING THAT COMES WITH IT is the `UIScale` — it parks every page's at 0.9 at
	   boot expecting its own tween to put it back, so `Open` has to do that by hand or the whole
	   column renders at 90%.

	3. THE SAMPLE SLOT IN THE PLACE IS A LAYOUT SAMPLE, NOT THE LIST. The first is cloned once per
	   owned car and `ScrollingFrame` is emptied at runtime. Everything the card carries beyond the
	   artist's three labels — the level chip, the two flag marks, the status line, the two chips and
	   the press flash — is built onto the clone here, because the authored card is a blank navy slab
	   with three TextLabels on it and always was.

	4. THE LIST IS REBUILT IN OFFSET, AND THAT IS NOT A STYLE PREFERENCE. The artist sized the slots
	   in SCALE inside a `ScrollingFrame` whose canvas is itself scale — and a scale-sized child of a
	   scrolling frame resolves against the CANVAS, not the window, so every row added would grow the
	   canvas, which would grow the rows, which would grow the canvas. That is the runaway that once
	   turned a 167px authored row into 10,584px. Offset cell sizes and a canvas this module computes
	   itself are the only shape that cannot feed back on itself. `AutomaticCanvasSize` is not the
	   way out either: it lands a few px short and clips the last row.

	   COLUMN COUNT AND THE COLUMN GAP ARE STILL MEASURED off the authored sample, because both are
	   fractions of the WIDTH and the width is honest. `CARD_ASPECT` is the one number typed in
	   rather than read, and note 5 is why.

	5. `CARD_ASPECT` IS A CONSTANT ON PURPOSE. The obvious move is to read the sample's live
	   `AbsoluteSize` and keep its shape, and it is wrong here: the sample's height resolves against
	   `AbsoluteCanvasSize`, which the wrapped list expands to fit its own contents. So the "authored"
	   aspect is partly an accident of there being exactly two samples in the Explorer, and it would
	   shift the moment somebody added a third. The value below was measured off the authored panel
	   once (179.88 x 116.59 px) and is a design number from here on — change it to reshape the card,
	   and the rows follow.

	6. THE PAGE IS THE WHOLE SCREEN AND THE PANEL IS A COLUMN ON THE RIGHT OF IT. That is a place
	   edit, not a code one: `Pages.Dealership` is a full-bleed transparent frame (no aspect
	   constraint) and `Main` is anchored to its right edge at full height, under an aspect
	   constraint of its own so the column's WIDTH tracks the screen's HEIGHT and it stays the same
	   physical column on an ultrawide as on a laptop. Two things depend on that and would need
	   moving with it: `Done` is positioned in SCREEN fractions (note 7), and the tooltip is placed
	   in pixels relative to this frame, so a page frame that is not the viewport puts the tooltip in
	   the wrong place.

	7. `Done` STANDS WHERE `Play` STANDS, AND `Play` GETS OUT OF ITS WAY. The two are the same pill
	   in the same place at the bottom centre, so opening the inventory swaps one for the other
	   rather than putting a second button on screen. The page does NOT write `Play.Visible` itself:
	   it publishes `SuppressPlayButton` and `RaceEntryController` — which already owns that property
	   for the race — decides. That is what keeps a page close during a race from putting the Play
	   button back up over the road. The restore is delayed past `UIController`'s close tween, or the
	   real Play button would appear underneath the shrinking `Done` for a sixth of a second.

	8. FIVE PLAYER ATTRIBUTES FEED IT AND NOT ONE REMOTE DOES.

	       GarageConfig.OwnedAttribute      "Sedan06:1,Sedan12:6"       the collection
	       GarageConfig.LotAttribute        "1:Sedan12:6,4:Sports16:1"  which bay each parked car is on
	       GarageConfig.LevelsAttribute     "Camaro:3,M5:2"             car levels, bodies above 1 only
	       InventoryConfig.FavoritesAttribute "Camaro:6"                starred cars
	       LobbyCarConfig.SpawnedAttribute  "Camaro:6"                  what is standing in the street

	   Same house pattern as cash and rate, and it means this page redraws itself the instant the
	   server writes any of them — including while it is open and you are watching the car change on
	   the podium behind it.

	   EVERY ENTRY IN THE FIRST FOUR IS A CAR KEY — body AND colour, "Sedan12:6". A player can own
	   the same body in several colours and they are different cars, so one card is one KEY and
	   nothing on this page may key off the body alone. Split them with `GarageConfig.split`, never
	   with a whitespace pattern: body names have spaces in them. The one exception is LEVEL, which
	   is per BODY because XP is (`RewardConfig`) — your two Camaros are the same level and always
	   will be.

	   NOTHING HERE DECIDES ANYTHING. Every action publishes an event and stops. The server owns
	   whether you own that car, whether that is a real bay and whether the flag may be flipped —
	   `GarageService.setBayCar`, `GarageService.setCarFlag`, `LobbyCarService.setLobbyCar`. This
	   page does not optimistically repaint either: the attribute write comes back a frame later and
	   repaints it for real, which is one code path instead of two and cannot disagree with the
	   podium. The COOLDOWN in `_press` is courtesy on top of that, not a permission check — both
	   services re-check their own.

	9. THE CARS ON THE CARDS ARE A VIRTUALISED LIST, and `Modules/CarViewportGrid` is the whole of it.
	   Each one is a real 25-mesh model of the body in the player's own colour, so a collection of
	   forty cards drawn at once would be a thousand meshes rendering behind a panel that shows six.
	   What exists at any moment is the cars for the rows inside the scroll window plus one either
	   side; read that module's header for how, and for why builds are queued rather than done where
	   they are asked for.

	   THIS PAGE'S HALF IS TWO CALLS. `_applyLayout` hands over the cell geometry it has just worked
	   out, and `_applyFilter` hands over the cards that are showing, in the order the grid will lay
	   them out. Everything else — the scroll, the page opening and closing — the grid watches for
	   itself.

	   THERE IS DELIBERATELY NO CAR IN THE TOOLTIP. The old detail pane had one and could afford it:
	   it rebuilt on a CLICK. A tooltip rebuilds on every card a cursor crosses, and `CarViewport.set`
	   clones a 25-mesh body each time — a sweep down the list would be a dozen clones a second on
	   top of the grid's own. The card the tooltip is describing is directly under the cursor showing
	   that exact car, so the picture would be the one thing on screen twice.

	   THE "LEAVE EMPTY" CARD IS PASSED ALONG WITH THE REST even though it has no car on it. It holds
	   a real place in the grid, and a list that skipped it would put every car after it one slot too
	   early and fill the wrong rows.

	10. THE ENTRANCE IS A SEQUENCE, NOT A FADE, and it is spread across two files.

	        t 0.00  the column slides in from the right edge  (here, `_slideColumn`)
	        t 0.00  Play drops off the bottom                 (`RaceEntryController`, over
	                                                           `SuppressPlayButton`)
	        t 0.18  `Done` rises into the pixels Play left    (here, `_slideDone`)

	    ...and the close is the same three beats backwards: `Done` drops, the column leaves, and
	    Play comes back up once `Done` is out of its way. The staggering is the whole point — the
	    two buttons occupy the SAME rectangle (note 7), so playing both at once is two pills
	    crossing through each other rather than one handing over to the other.

	    THE TIMINGS ARE PAIRED ACROSS THE TWO FILES AND NEITHER OWNS BOTH. `DONE_IN_DELAY` here is
	    set just past `PLAY_OUT_TWEEN`'s duration there, and `PLAY_RESTORE_DELAY` here is set just
	    past `DONE_OUT_TWEEN`'s. Retune one and read the other; they are commented as a pair at both
	    ends. What is NOT shared is a config entry for them, because these are two different numbers
	    that happen to be adjacent rather than one number used twice.

	    EVERY TWEEN IS TOKENED (`_anim`). A page can be closed and reopened faster than 0.44s, and a
	    delayed beat from the previous transition landing in the middle of the next one is how an
	    entrance ends with the panel off screen and the button gone.

	HOUSE RULE: no wiki-style double-bracket links in this comment — the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UIControllerTypes = require(script.Parent.Parent.UIControllerTypes)
local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local MarketValueConfig = require(ReplicatedStorage.shared.Configs.MarketValueConfig)
local InventoryConfig = require(ReplicatedStorage.shared.Configs.InventoryConfig)
local LobbyCarConfig = require(ReplicatedStorage.shared.Configs.LobbyCarConfig)
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local RewardConfig = require(ReplicatedStorage.shared.Configs.RewardConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)
local CarViewportGrid = require(ReplicatedStorage.shared.Modules.CarViewportGrid)

local PAGE_NAME = "Dealership"
local TEXT = InventoryConfig.Text

-- Header note 5. Width over height, in pixels, of one authored card.
local CARD_ASPECT = 179.88 / 116.59

--[[ Where the car stands on the card, in fractions of it. The authored panel is blank art with its
	three labels laid across the top third, so the car takes most of what is left — and stops short
	of the bottom edge rather than sitting on it, because the bottom eighth is now the level chip,
	the two flag marks and the status line.

	`VIEW_ASPECT` is what the viewport's camera is framed for, and it is worth reading off the two
	numbers above it rather than typing: a card is half again as wide as it is tall and the car takes
	three fifths of its height, so the picture is a letterbox better than 2:1 and a camera framed for
	a square would crop the car's nose and tail off. Reshape the box and the framing follows. ]]
local VIEW_WIDTH = 0.94
local VIEW_HEIGHT = 0.60
local VIEW_CENTRE = 0.60
local VIEW_ASPECT = CARD_ASPECT * VIEW_WIDTH / VIEW_HEIGHT

--[[ The bottom strip of a card, in fractions of it: level on the left, status in the middle, the
	favourite mark on the right. All three sit OVER the car rather than pushing it up, which is the
	only way three more things fit on a card this size without the picture becoming a thumbnail.

	They do not overlap and that was arithmetic, not eyeballing: 0.02..0.24, 0.28..0.72, 0.72..0.98. ]]
local STRIP_Y = 0.895
local STRIP_HEIGHT = 0.105
local LEVEL_LEFT, LEVEL_WIDTH = 0.02, 0.22
local STATUS_LEFT, STATUS_WIDTH = 0.28, 0.44
local MARK_SIZE = 0.115 -- square, in fractions of the card's WIDTH

-- A car parked on some OTHER bay is dimmed this far — pickable, but visibly spoken for.
local ELSEWHERE_TRANSPARENCY = 0.35

-- === The favourite chip =====================================================
--[[ FAVOURITE, as one button on the card's right edge. There was a padlock under it until the
	rewrite above; the header's third bullet is where that went.

	SQUARE IN PIXELS, WHICH IS WHY THE HEIGHT BELOW CARRIES `CARD_ASPECT`. The card is 1.54 times
	wider than it is tall, so a chip sized `fromScale(n, n)` comes out half again as wide as it is
	high — the same trap the mark under it documents. Everything here is stated as a fraction of the
	card's WIDTH and converted on the way to a Y.

	IT IS ON THE RIGHT EDGE AND VERTICALLY CENTRED, which is the one region of the card with nothing
	in it: the `$` line ends at y 0.16, the status strip starts at 0.895, and the car between them is
	a letterbox whose right end is empty road. The chip spans 0.435..0.665 and touches neither. ]]
local CHIP_SIZE = 0.15 -- the chip, in fractions of the card's width
local CHIP_HEIGHT = CHIP_SIZE * CARD_ASPECT
local CHIP_CENTRE_Y = 0.55
local CHIP_REST_X = 0.975
--[[ Where the column parks when it is not wanted: entirely off the card's right edge. The card
	clips its descendants (`_makeCard`), so a tucked chip is neither drawn nor clickable, and it is
	the tween between these two x's that reads as the row sliding in from the side. ]]
local CHIP_TUCK_X = CHIP_REST_X + CHIP_SIZE + 0.05
local CHIP_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CHIP_HOVER_SCALE = 1.12
local CHIP_ICON_INSET = 0.22 -- the glyph's padding inside its own chip, per side

-- === The stats tooltip ======================================================
--[[ The panel that follows the cursor. Sized in PIXELS off the page's live viewport rather than in
	scale, because it is positioned in pixels too (`_placeTip` works in the cursor's own units) and
	one box described in two coordinate systems is a box that disagrees with itself at the screen
	edges.

	`TIP_HEIGHT` is the fraction of the SCREEN HEIGHT it wants to be and `TIP_MAX_WIDTH` is the
	fraction of the width it may never exceed; the smaller wins, which is exactly what a
	`UIAspectRatioConstraint` on `FitWithinMaxSize` would compute and is written out here so the
	placement maths can know the answer before the frame is laid out. ]]
local TIP_ASPECT = 1.30 -- width over height
local TIP_HEIGHT = 0.34
local TIP_MAX_WIDTH = 0.34
local TIP_GAP = 18 -- px between the pointer and the nearest corner of the panel
local TIP_EDGE = 10 -- px it is never allowed closer than to the edge of the screen
--[[ How far the opaque backing is inset from the panel's edge, in px. `Slice` draws the border at
	1:1 texture pixels at any frame size, so this is a pixel number for the same reason the border
	is — see `_buildTooltip`. `UIAssets.Slice.Panel` is 18; 14 keeps the backing inside it. ]]
local TIP_BORDER = 14

--[[ Everything inside the tooltip, in fractions of IT. A vertical budget rather than a grid: the
	rows are different heights and a single pitch would make the type sizes disagree.

	THE BUDGET IS THE OPAQUE BODY'S, NOT THE PANEL'S. `TIP_BORDER` is inset off every edge, so the
	usable band is roughly 0.07..0.93 at the size this draws at — a row centred at 0.945 has its
	lower half on the artist's border, which reads as the last line being clipped rather than as an
	arithmetic slip. Every number below is inside that band with its own half-height to spare. ]]
local TIP = {
	NameY = 0.115,
	NameHeight = 0.085,
	RarityY = 0.213,
	MetaY = 0.285,
	StatTop = 0.395,
	StatPitch = 0.112,
	StatHeight = 0.050,
	RateY = 0.822,
	HintY = 0.902,
}

-- Widths inside a stat row, in fractions of the tooltip. Label, then the track, then the rating.
local STAT_LABEL_LEFT, STAT_LABEL_WIDTH = 0.06, 0.36
local STAT_TRACK_LEFT, STAT_TRACK_WIDTH = 0.45, 0.36
local STAT_RATING_LEFT, STAT_RATING_WIDTH = 0.84, 0.11
local STAT_BAR_HEIGHT = 0.028

-- === Pressing ===============================================================
--[[ How long a finger has to stay down before the press becomes a PREVIEW instead of a spawn, and
	how far it may wander first. A hold is the only gesture a touch screen has spare here: the tap is
	the verb, so the stats have to hang off something else.

	`PRESS_BLOCK` is the window after a hold fires in which a tap is ignored — a long press ends in a
	release like any other and Roblox raises `MouseButton1Click` for it, so without this every
	preview would also spawn the car it was previewing. A time window rather than a flag because the
	release's two events (`InputEnded` and the click) have no guaranteed order between them. ]]
local HOLD_SECONDS = 0.28
local HOLD_DRAG_PX = 12
local PRESS_BLOCK = 0.3

--[[ The white flash over a card that has just been pressed. The press itself is answered by the
	server a frame or two later (the car appears, the status line changes), and this is what covers
	that gap — without it a tap on a card is silent until the world catches up. ]]
local FLASH_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLASH_PEAK = 0.72

-- The blue outline on the card this screen is currently about, in pixels. `_decorateCard` insets
-- the frame that carries it by this much on every side, so the stroke lands flush inside the card.
local ACTIVE_THICKNESS = 3

-- === The entrance ===========================================================
--[[ Header note 10. The column comes from the right edge and `Done` comes up from the bottom, on a
	stagger, against `RaceEntryController`'s matching slide on the Play button.

	THE COLUMN'S TRAVEL IS STATED IN THE PANEL'S OWN WIDTH rather than measured off `AbsoluteSize`,
	and that is deliberate: on the very first open the page has never been laid out and its absolute
	size is not trustworthy yet. `Main.Size.X.Scale` is the CAP the aspect constraint fits inside
	(note 6), so the panel is never wider than that and sliding by it always clears the screen. The
	extra travel on a window where the constraint binds is a few hundredths of a second at the head
	of a Quint, which is the part of the curve nothing can see.

	QUINT OUT ON THE WAY IN, NOT THE KIT'S `Back`. A Back overshoot on a panel that is flush to the
	screen edge overshoots PAST the edge and comes back, which draws a gap down the right of the
	screen for two frames. The buttons keep Back, because they have somewhere to overshoot into. ]]
local COLUMN_IN_TWEEN = TweenInfo.new(0.30, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local COLUMN_OUT_TWEEN = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local COLUMN_CLEAR = 0.02 -- a sliver past the panel's own width, so no edge is ever left showing

local DONE_IN_TWEEN = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local DONE_OUT_TWEEN = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
--[[ How far below its home `Done` parks, in fractions of the SCREEN. Its box is centre-anchored at
	y 0.91 and 0.075 tall, so its top edge is at 0.8725 and 0.1275 is the exact drop that clears the
	bottom of the screen. The margin above that is for the two windows this is not exact on: a
	`FitWithinMaxSize` aspect constraint can leave the box taller than it renders, and a device with
	a bottom safe-area inset moves the edge up. Same number and same reasoning as
	`RaceEntryController.PLAY_DROP`, because it is the same rectangle. ]]
local DONE_DROP = 0.16

--[[ When `Done` starts rising, measured from the open. `RaceEntryController.PLAY_OUT_TWEEN` runs
	0.14s from the same instant, so this is the moment just after Play is off screen — the two pills
	share one rectangle and must never be in it together. Read the two together. ]]
local DONE_IN_DELAY = 0.18

--[[ ...and its mirror: when Play is asked back, measured from the close. `DONE_OUT_TWEEN` is 0.14s,
	so Play starts up just after `Done` is out of the way. Header notes 7 and 10. ]]
local PLAY_RESTORE_DELAY = 0.16

--[[ How far the page's pressables swell under a cursor, read off the `Scale` attribute by
	`Components/Button`. Under that component's 1.05 default: a card is a big object where 5% is a
	lurch rather than a nudge. ]]
local CARD_HOVER_SCALE = 1.02

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)
local WHITE = Color3.fromRGB(255, 255, 255)
-- The kit's muted caption grey, taken off the artist's own `Rating` label.
local MUTED = Color3.fromRGB(123, 133, 169)
-- ...and the green the `$` line is drawn in, which is the kit's money colour.
local CASH_GREEN = Color3.fromRGB(13, 180, 21)
-- The brand blue, which marks the car this screen is currently doing something about.
local BRAND_BLUE = Color3.fromRGB(0, 102, 255)
-- The kit's darkest navy, which is what an unset chip and an unticked box are filled with.
local DEEP_NAVY = Color3.fromRGB(21, 29, 45)
-- The brand blue washed out to something readable on the panel — the tooltip's instruction line.
local HINT_BLUE = Color3.fromRGB(142, 178, 246)

--[[ The stat tooltip and the favourite chip are the whole of what `InventoryConfig.Enabled`
	switches off. With it off this is a plain picker again, which is what that flag has always
	promised. ]]
local INVENTORY_ON = InventoryConfig.Enabled

local function url(id: number): string
	return UIAssets.url(id)
end

local function slice(image: ImageLabel | ImageButton, size: Vector2, inset: number)
	image.ScaleType = Enum.ScaleType.Slice
	image.SliceCenter = Rect.new(inset, inset, size.X - inset, size.Y - inset)
end

--[[ Fill a template out of `InventoryConfig.Text` and make it safe for a TextScaled label.

	EVERY SPACE COMES OUT NON-BREAKING, and that is the whole reason this exists rather than a bare
	`gsub`: TextScaled would rather wrap to a second line than shrink, so "PARK ON BAY 2" on a pill
	becomes three stacked words at a readable size instead of one line at a smaller one. Fixing it
	with `TextWrapped = false` does not work — the label clips instead — and `MinTextSize` needs
	`TextScaled` off. A space it cannot break on is the only thing that has ever worked here. ]]
local function fill(template: string, fields: { [string]: string | number }?): string
	local text = template
	if fields then
		text = (string.gsub(text, "{(%w+)}", function(name)
			local value = fields[name]
			return if value ~= nil then tostring(value) else "{" .. name .. "}"
		end))
	end
	return (string.gsub(text, " ", "\u{00A0}"))
end

local function normalize(text: string?): string
	return (string.gsub(string.lower(text or ""), "%W", ""))
end

--[[ What one card is called: "RED CAMARO", or just "CAMARO" for a car in its authored livery.

	IT MOVED TO `GarageConfig.carName` on 2026-08-24 and this is a call, not a copy. The rule (and
	the roster's two traps — `M5` must not become "M 5", the spaces have to come back non-breaking)
	is documented there. The sell lot names the same cars on a sign in the plaza, and a car the lot
	calls "CAMARO" while this list calls it "RED CAMARO" is two screens disagreeing about which of
	your cars is about to be sold. ]]
local function cardName(body: string, paint: number): string
	return GarageConfig.carName(body, paint)
end

--[[ "1:Sedan12:6,4:Sports16:1" -> { [carKey] = bay }. Anything unparseable is skipped, not fatal.

	The bay is the leading digits and EVERYTHING AFTER THE FIRST COLON IS THE KEY — which is why the
	pattern is `(%d+):(.+)` and not a split. A key has a colon of its own in it, and body names have
	spaces in them (`Golf GTI`), so neither a colon nor whitespace can be treated as a field break
	here. ]]
local function parseLot(raw: any): { [string]: number }
	local out = {}
	for _, entry in GarageConfig.split(raw) do
		local bay, key = string.match(entry, "^(%d+):(.+)$")
		if bay and key then
			out[key] = tonumber(bay)
		end
	end
	return out
end

--- A comma-separated attribute as a set of car keys.
local function parseSet(raw: any): { [string]: boolean }
	local out = {}
	for _, key in GarageConfig.split(raw) do
		out[key] = true
	end
	return out
end

--- Is this input type a finger? The one question the page asks about the device, and it asks it of
--- the LAST input rather than of `TouchEnabled`, which lies at boot on a machine with both.
local function isTouch(inputType: Enum.UserInputType): boolean
	return inputType == Enum.UserInputType.Touch
end

local Page = {}
Page.__index = Page

function Page.new(UIController: UIControllerTypes.UIController)
	local self = setmetatable({}, Page)
	self.UIController = UIController
	self.Player = UIController.Player or Players.LocalPlayer

	local mainUI = UIController.PlayerGui:WaitForChild("MainUI")
	self.PageUI = mainUI:WaitForChild("Pages"):WaitForChild(PAGE_NAME)

	self.Main = self.PageUI:WaitForChild("Main")
	self.Title = self.Main:WaitForChild("Title")
	-- `SerachBar` is the artist's spelling and it is load-bearing: renaming the instance in the
	-- Explorer without changing this line is a WaitForChild that never returns, which is a page
	-- that never builds and a screen that never opens. Left as authored on purpose.
	self.SearchBar = self.Main:WaitForChild("SerachBar")
	self.SearchBox = self.SearchBar:WaitForChild("TextBox")
	--[[ The artist's section caption, repurposed. It is the one free label above the list, and it
		carries whichever of the two things this screen most needs to say — which bay you are
		editing, or how many cars you have. ]]
	self.Caption = self.Main:WaitForChild("Dealership Tier")
	self.Scroll = self.Main:WaitForChild("ScrollingFrame")
	self.Done = self.PageUI:WaitForChild("Done")

	self._entries = {}
	self._query = ""
	self._visibleCount = 0

	--[[ BAY MODE UNTIL THE FIRST OPEN SAYS OTHERWISE. `_bay` is only meaningful in bay mode and
		`_bayArmed` is the one-shot that carries a podium press through to `Open` —
		header note 2. ]]
	self._mode = "inventory"
	self._bay = 1
	self._bayArmed = false

	-- The press guards. `_nextPressAt` is the spam floor (header note 8); `_noPressUntil` is the
	-- window after a long press in which the release's own click is not a tap. See `PRESS_BLOCK`.
	self._nextPressAt = 0
	self._noPressUntil = 0

	--[[ The entrance, header note 10. Both homes are read HERE — before the page has ever opened and
		therefore before anything has moved either of them — because every tween below is written as
		"back to where the artist put it" and a home latched mid-slide is a panel that never quite
		arrives. `_anim` tokens the whole transition; see the note on `_slideColumn`. ]]
	self._columnHome = self.Main.Position
	self._doneHome = self.Done.Position
	self._anim = 0

	-- Whether the CHIPS are permanently out, which is true on a touch screen and false under a
	-- cursor. Re-read on every input change rather than once at boot.
	self._touchUI = isTouch(UserInputService:GetLastInputType())

	self.Done.MouseButton1Click:Connect(function()
		self.UIController:closePage(PAGE_NAME)
	end)

	-- Header note 9. Built before the grid, because `_buildGrid` lays out immediately and the layout
	-- pass hands its geometry straight to this.
	self._views = CarViewportGrid.new(self.Scroll, self.PageUI)

	self:_buildTooltip()
	self:_buildGrid()
	self:_buildSearch()
	self:_watchState()

	-- The bay arrives just before the page opens; see header notes 1 and 2.
	Dispatcher:Subscribe("DealershipBay", function(bay: number)
		self:setBay(bay)
	end)

	--[[ A device change repaints every card, because it decides whether the chips are out. Nothing
		else on the page cares which device is driving it. The latch is only for THAT repaint —
		`_touchDevice` is what every decision reads, and it asks the engine live. ]]
	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		local touch = isTouch(inputType)
		if touch == self._touchUI then
			return
		end
		self._touchUI = touch
		for _, entry in self._entries do
			self:_setChips(entry, touch, true)
		end
	end)

	return self
end

function Page.initialize(_self) end

--[[ Header note 2: the mode arbitration, and the only place either mode is entered. Header note 10:
	the entrance, which is why this is `Open` and not the `StartOpenThread` the rest of the kit uses.

	THE ORDER IN HERE IS THE SEQUENCE. `_rebuild` first, because it runs while the page is still
	hidden and building forty cards on the frame the panel starts moving would stutter the slide.
	Then Play is asked to leave, so its 0.14s runs under the column's arrival rather than after it.
	`Done` is last and delayed, because it is moving into a space Play has not vacated yet. ]]
function Page:Open(_data: any?)
	if self._bayArmed then
		self._bayArmed = false
		self._mode = "bay"
	else
		self._mode = "inventory"
	end

	self:_applyMode()
	self:_rebuild()

	--[[ `UIController` parks every page's `UIScale` at 0.9 at boot and tweens it back to 1 as its
		own entrance. This page has one of its own, so that tween never runs and the scale would sit
		at 0.9 for the life of the session — the whole column rendered at 90% with a gap down the
		right edge. Header note 2. ]]
	if self._pageScale then
		self._pageScale.Scale = 1
	end

	self._anim += 1
	local token = self._anim

	self.PageUI.Visible = true
	self:_slideColumn(true, token)
	-- Header note 7: the two pills share a rectangle, so one leaves before the other arrives.
	Dispatcher:Publish("SuppressPlayButton", true)
	self:_slideDone(true, token)
end

--- ...and the same three beats backwards. Header note 10.
function Page:Close()
	self:_hideTip()

	self._anim += 1
	local token = self._anim

	self:_slideDone(false, token)
	self:_slideColumn(false, token)

	--[[ Play is asked back once `Done` is out of its rectangle, not when the close was requested.
		Tokened for the same reason every other beat is: a reopen inside this window would otherwise
		have the stale timer raise the Play button underneath the page that had just come back. ]]
	task.delay(PLAY_RESTORE_DELAY, function()
		if self._anim == token then
			Dispatcher:Publish("SuppressPlayButton", false)
		end
	end)
end

--[[ The column, on and off the right edge of the screen.

	IT IS TOKENED RATHER THAN GUARDED ON THE TWEEN, and the difference matters on the beat that ends
	the close: `Visible = false` fires from a `Completed` handler, and a page reopened inside those
	0.20s would have the old handler blank the page that had just been rebuilt. Cancelling the tween
	is not enough by itself — `Cancel` raises `Completed` with a `Cancelled` state, which this does
	check, but a tween that finished a frame before the reopen has already fired it. The token is
	the only thing that can tell those two apart. ]]
function Page:_slideColumn(inward: boolean, token: number)
	local main = self.Main
	if self._columnTween then
		self._columnTween:Cancel()
		self._columnTween = nil
	end

	local home = self._columnHome
	-- Anchored to its own right edge (note 6), so one panel-width past `home` is entirely off screen.
	local away = UDim2.new(
		home.X.Scale + main.Size.X.Scale + COLUMN_CLEAR,
		home.X.Offset,
		home.Y.Scale,
		home.Y.Offset
	)

	if inward then
		main.Position = away
		self._columnTween = TweenService:Create(main, COLUMN_IN_TWEEN, { Position = home })
		self._columnTween:Play()
		return
	end

	self._columnTween = TweenService:Create(main, COLUMN_OUT_TWEEN, { Position = away })
	self._columnTween:Play()
	self._columnTween.Completed:Once(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed and self._anim == token then
			self.PageUI.Visible = false
			-- Put back on its home while nothing can see it, so anything that shows this page
			-- without going through `Open` finds the panel where the artist left it.
			main.Position = home
		end
	end)
end

--- `Done`, up out of the bottom edge and back down into it. Delayed on the way in — header note 10.
function Page:_slideDone(inward: boolean, token: number)
	local done = self.Done
	if self._doneTween then
		self._doneTween:Cancel()
		self._doneTween = nil
	end

	local home = self._doneHome
	local away = UDim2.new(home.X.Scale, home.X.Offset, home.Y.Scale + DONE_DROP, home.Y.Offset)

	if inward then
		-- Parked off screen for the length of the delay rather than hidden for it: one property
		-- write instead of two, and there is nothing to see either way.
		done.Position = away
		done.Visible = true
		task.delay(DONE_IN_DELAY, function()
			if self._anim ~= token then
				return
			end
			self._doneTween = TweenService:Create(done, DONE_IN_TWEEN, { Position = home })
			self._doneTween:Play()
		end)
		return
	end

	self._doneTween = TweenService:Create(done, DONE_OUT_TWEEN, { Position = away })
	self._doneTween:Play()
	self._doneTween.Completed:Once(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed and self._anim == token then
			done.Visible = false
			done.Position = home
		end
	end)
end

-- === Which bay ==============================================================

function Page:setBay(bay: number)
	self._bay = bay
	self._bayArmed = true
	-- Applied here as well as on open, so a bay changed while the page is already up (pressing a
	-- second podium without closing the first) redraws rather than waiting for a reopen.
	if self._mode == "bay" then
		self:_applyMode()
		self:_rebuild()
	end
end

--- Title, caption and the LEAVE EMPTY card's existence — the whole of what the mode changes.
function Page:_applyMode()
	self.Title.Text = fill(if self._mode == "bay" then TEXT.TitleBay else TEXT.TitleInventory)
	self:_refreshCaption()
end

function Page:_refreshCaption()
	if self._mode == "bay" then
		self.Caption.Text = fill(TEXT.CaptionBay, { bay = self._bay })
	else
		-- Cars, not cards: the LEAVE EMPTY card is not one and never appears in inventory mode anyway.
		local count = 0
		for _, entry in self._entries do
			if entry.key then
				count += 1
			end
		end
		self.Caption.Text = fill(TEXT.CaptionInventory, { count = count, limit = InventoryConfig.MaxCars })
	end
end

-- === Layout =================================================================

--[[ Tear the authored list down to a template plus a grid this module drives. Header notes 3-5. ]]
function Page:_buildGrid()
	local samples = {}
	for _, child in self.Scroll:GetChildren() do
		if child:IsA("GuiObject") then
			table.insert(samples, child)
		end
	end

	if #samples == 0 then
		warn(`[{PAGE_NAME}] no sample Slot under ScrollingFrame — the list needs one to clone. Page left empty.`)
		return
	end

	self._template = samples[1]:Clone()

	--[[ Both of these are fractions of the WIDTH, which is the axis that does not feed back on the
		canvas, so they are read off the art rather than typed here — nudge the sample slot in the
		Explorer and the real list follows it. ]]
	local cardWidth = samples[1].Size.X.Scale
	local authoredLayout = self.Scroll:FindFirstChildOfClass("UIListLayout")
	local gap = if authoredLayout then authoredLayout.Padding.Scale else 0
	local columns = math.max(math.floor((1 + gap) / (cardWidth + gap) + 0.001), 1)

	self._gap = gap
	self._columns = columns

	for _, child in self.Scroll:GetChildren() do
		if child:IsA("GuiObject") or child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	-- The canvas is computed in `_applyLayout`; a scale canvas is half of the runaway in note 4.
	self.Scroll.CanvasSize = UDim2.new()
	self.Scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	self.Scroll.ScrollingDirection = Enum.ScrollingDirection.Y

	local layout = Instance.new("UIGridLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.FillDirectionMaxCells = columns
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Parent = self.Scroll
	self._layout = layout

	-- Shown when the collection is empty or a search matches nothing, so the panel is never a well.
	local empty = Instance.new("TextLabel")
	empty.Name = "NoCars"
	empty.BackgroundTransparency = 1
	empty.AnchorPoint = Vector2.new(0.5, 0.5)
	empty.Position = UDim2.fromScale(0.5, 0.28)
	empty.Size = UDim2.fromScale(0.9, 0.06)
	empty.ZIndex = self.Scroll.ZIndex + 1
	empty.FontFace = self.Caption.FontFace
	empty.TextColor3 = self.SearchBox.PlaceholderColor3
	empty.TextScaled = true
	empty.Text = fill(TEXT.NoCars)
	empty.Visible = false
	-- Outside the ScrollingFrame: a child of it would scroll away with the list and be sized
	-- against the canvas, which is exactly what note 4 is about.
	empty.Parent = self.Main
	self._empty = empty

	self.Scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_applyLayout()
	end)
	self:_applyLayout()
end

--[[ Cell geometry in offset, from the viewport's live pixel size.

	The cell WIDTH is derived from the gap rather than measured alongside it, so a row always adds up
	to exactly the viewport width no matter how the fractions round. ]]
function Page:_applyLayout()
	local scroll, layout = self.Scroll, self._layout
	if not (scroll and layout) then
		return
	end

	local size = scroll.AbsoluteWindowSize
	if size.X <= 0 or size.Y <= 0 then
		return -- not laid out yet; the AbsoluteSize signal brings us back
	end

	--[[ The authored `UIPadding` insets the content but NOT the window: `AbsoluteWindowSize` is the
		viewport, padding and all. Sizing a row to the full window therefore overflows it by exactly
		the inset and shaves the last column — 1.6px of it, which reads as the right-hand cards being
		clipped against the panel edge rather than as an arithmetic slip. Its scale resolves against
		`AbsoluteSize` (the frame including its scrollbar gutter), not the window. ]]
	local inset = 0
	local top = 0
	local padding = scroll:FindFirstChildOfClass("UIPadding")
	if padding then
		local frame = scroll.AbsoluteSize.X
		inset = padding.PaddingLeft.Scale * frame + padding.PaddingLeft.Offset
			+ padding.PaddingRight.Scale * frame + padding.PaddingRight.Offset
		top = padding.PaddingTop.Scale * scroll.AbsoluteSize.Y + padding.PaddingTop.Offset
	end

	local columns = self._columns
	local available = math.max(size.X - inset, 1)
	local padX = self._gap * available
	local cellWidth = (available - padX * (columns - 1)) / columns
	local cellHeight = cellWidth / CARD_ASPECT

	layout.CellSize = UDim2.fromOffset(cellWidth, cellHeight)
	-- Square gaps in PIXELS. Equal scale on both axes is three times taller than it is wide on a
	-- panel this shape.
	layout.CellPadding = UDim2.fromOffset(padX, padX)

	--[[ The same geometry, handed to the viewport grid so its window test runs against the numbers the
		cards are actually laid out with rather than a second copy that can disagree — row N's top edge
		in canvas coordinates is `top + N * (cellHeight + padX)`. Header note 9. ]]
	self._views:setLayout(columns, cellHeight + padX, cellHeight, top, VIEW_ASPECT)

	local rows = math.ceil(self._visibleCount / columns)
	local canvas = if rows > 0 then rows * cellHeight + (rows - 1) * padX else 0
	-- The vertical inset is real canvas too; without it the last row loses its own height off the
	-- bottom, which is the same clipping AutomaticCanvasSize is rejected for in note 4.
	if padding and canvas > 0 then
		local frame = scroll.AbsoluteSize.Y
		canvas += padding.PaddingTop.Scale * frame + padding.PaddingTop.Offset
			+ padding.PaddingBottom.Scale * frame + padding.PaddingBottom.Offset
	end
	scroll.CanvasSize = UDim2.fromOffset(0, canvas)
end

-- === Search =================================================================

function Page:_buildSearch()
	local box = self.SearchBox
	box:GetPropertyChangedSignal("Text"):Connect(function()
		self:_setQuery(box.Text)
	end)
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
	local visible = 0
	--[[ The cards that are showing, in the order the grid will lay them out — which is what the
		viewport grid takes, and is not the same list as `_entries`: a UIGridLayout lays out visible
		children only, so searching moves every card behind the query up into the rows the window is
		over. `_entries` is built in LayoutOrder order, so collecting it in order collects the grid.
		The "leave empty" card goes in with the rest; header note 9. ]]
	local cells = {}
	for _, entry in self._entries do
		-- The "leave empty" card is not a car and is never filtered out — clearing a bay has to
		-- stay reachable no matter what is typed in the box.
		local matches = entry.key == nil or self._query == "" or string.find(entry.search, self._query, 1, true) ~= nil
		entry.card.Visible = matches
		if matches then
			visible += 1
			table.insert(cells, entry)
		end
	end

	self._visibleCount = visible
	if self._empty then
		local cars = 0
		for _, entry in self._entries do
			if entry.key then
				cars += 1
			end
		end
		local shownCars = if self._mode == "bay" then visible - 1 else visible
		self._empty.Visible = shownCars <= 0
		self._empty.Text = fill(if cars <= 0 then TEXT.NoCars else TEXT.NoMatch)
	end

	self.Scroll.CanvasPosition = Vector2.new(0, 0)
	self:_applyLayout()
	-- After the layout, so the grid tests the new list against the new canvas rather than the old one.
	self._views:setCells(cells)
end

-- === The card ===============================================================

--[[ Everything the authored card does not have: a level chip, the favourite mark, a status line,
	the favourite chip and the press flash. Built onto the clone rather than authored, because the
	card in the place is a blank navy slab with three TextLabels on it — header note 3.

	ALL OF THEM SIT OVER THE CAR. That is what makes them fit: the picture is the biggest thing on a
	card this size, and pushing it up to make a bottom bar would leave a thumbnail. The car is
	letterboxed and its lower corners are empty road, so a chip in each of them costs nothing that
	was being looked at.

	ZINDEX +1 THROUGHOUT, which is one number and not a stack, because the GUI is
	`ZIndexBehavior.Sibling`: ZIndex orders a child against its SIBLINGS only, and a descendant
	always draws over its ancestor whatever it is set to. So +1 puts all of them over the viewport
	(which is at 0) and beside the artist's three labels, and nothing here can end up behind the
	card's own art. The flash is the one exception at +2, because it is meant to cover them. ]]
function Page:_decorateCard(card: ImageButton)
	local z = card.ZIndex + 1

	local function label(name: string, left: number, width: number, colour: Color3): TextLabel
		local text = Instance.new("TextLabel")
		text.Name = name
		text.BackgroundTransparency = 1
		text.AnchorPoint = Vector2.new(0, 0)
		text.Position = UDim2.fromScale(left, STRIP_Y)
		text.Size = UDim2.fromScale(width, STRIP_HEIGHT)
		text.ZIndex = z
		text.FontFace = FONT
		text.TextColor3 = colour
		text.TextScaled = true
		text.Text = ""
		text.Parent = card
		return text
	end

	local level = label("Level", LEVEL_LEFT, LEVEL_WIDTH, WHITE)
	level.TextXAlignment = Enum.TextXAlignment.Left
	local status = label("Status", STATUS_LEFT, STATUS_WIDTH, WHITE)

	--[[ The star, right-aligned and square. `MARK_SIZE` is a fraction of the card's WIDTH and the
		`CARD_ASPECT` on its height is what keeps it square — a `fromScale(n, n)` on a card 1.54 times
		wider than it is tall would draw a star half again as wide as it is high.

		IT IS THE AT-REST STATE and the chip below is the verb. Both draw the same glyph, so they are
		never on screen together: `_setChips` hides this one while the chip is out. ]]
	local star = Instance.new("ImageLabel")
	star.Name = "Favorite"
	star.BackgroundTransparency = 1
	star.AnchorPoint = Vector2.new(1, 1)
	star.Position = UDim2.fromScale(0.98, 1)
	star.Size = UDim2.fromScale(MARK_SIZE, MARK_SIZE * CARD_ASPECT)
	star.ZIndex = z
	star.Image = url(UIAssets.Inventory.Favorite)
	star.Visible = false
	star.Parent = card

	--[[ The blue outline, which marks THE CAR THIS SCREEN IS CURRENTLY ABOUT: the one standing in
		the street in inventory mode, the one on the bay you walked up to in bay mode. It was the
		selection highlight until selection stopped existing, and it is worth keeping pointed at
		something — a list of forty cards with no marker at all is a list where the car you just
		spawned is indistinguishable from the thirty-nine you did not.

		A STROKE AND NOT A FACE COLOUR, because the card's face is the artist's art and there is only
		one of it; the kit's own state language is opacity, and opacity is already spoken for here as
		the mark for a car parked on some other bay.

		IT IS DRAWN INSIDE THE CARD, on a frame inset by its own thickness, and not as a `UIStroke`
		on the card itself. A stroke on the card draws entirely OUTSIDE the card's rectangle, and the
		top row of the grid sits about a pixel below the `ScrollingFrame`'s own edge — the authored
		`PaddingTop` is 0.2% of the viewport, which is 1px at this size against a 3px stroke. The
		window clips what leaves it, so on row 0 the top edge went and the marked car read as a
		three-sided box. Inset, the outline cannot leave its cell and no row or column is a special
		case. It costs the outermost 3px of the card's art, which is the artist's border. ]]
	local outline = Instance.new("Frame")
	outline.Name = "ActiveOutline"
	outline.AnchorPoint = Vector2.new(0.5, 0.5)
	outline.Position = UDim2.fromScale(0.5, 0.5)
	outline.Size = UDim2.new(1, -ACTIVE_THICKNESS * 2, 1, -ACTIVE_THICKNESS * 2)
	outline.BackgroundTransparency = 1
	outline.BorderSizePixel = 0
	outline.ZIndex = z
	outline.Parent = card

	local active = Instance.new("UIStroke")
	active.Name = "ActiveStroke"
	active.Color = BRAND_BLUE
	active.Thickness = ACTIVE_THICKNESS
	active.Enabled = false
	active.Parent = outline

	--[[ The press flash, over everything. Transparent at rest and never interactive — a `Frame` with
		`Active` left false does not consume input, so the card underneath it still hears the press
		that lit it. ]]
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.BackgroundColor3 = WHITE
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = z + 1
	flash.Parent = card

	return { level = level, status = status, star = star, active = active, flash = flash }
end

--[[ The favourite chip, which slides in off the card's right edge. The note on `CHIP_SIZE` has the
	geometry; `_setChips` owns when it is out.

	IT IS A BUTTON INSIDE A BUTTON, and that is the whole reason it can live on the card's face at
	all: a press that lands on a child GuiButton is consumed by it, so tapping the star stars the car
	and does not also put it in the street. The only path that can confuse the two is the TOUCH one,
	which reads raw `InputBegan` rather than a click — `_touchOver` is the guard there.

	IT IS STILL A STRIP WITH ONE THING IN IT rather than a bare button on the card, and that is worth
	a line now that there is only one chip: the frame is what `_setChips` tweens and hides, so the
	slide, the clip and the `Visible` latch stay one object's business whatever ends up inside it. ]]
function Page:_buildChips(card: ImageButton, entry)
	local strip = Instance.new("Frame")
	strip.Name = "Chips"
	strip.BackgroundTransparency = 1
	strip.AnchorPoint = Vector2.new(1, 0.5)
	strip.Position = UDim2.fromScale(CHIP_TUCK_X, CHIP_CENTRE_Y)
	strip.Size = UDim2.fromScale(CHIP_SIZE, CHIP_HEIGHT)
	strip.ZIndex = card.ZIndex + 1
	strip.Visible = false
	strip.Parent = card

	local button = Instance.new("ImageButton")
	button.Name = "Favorite"
	button.BackgroundColor3 = DEEP_NAVY
	button.BackgroundTransparency = 0.2
	button.Image = ""
	button.AutoButtonColor = false
	button.Size = UDim2.fromScale(1, 1)
	button.ZIndex = strip.ZIndex
	button.Parent = strip

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = WHITE
	stroke.Thickness = 1.5
	stroke.Transparency = 0.55
	stroke.Parent = button

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(1 - CHIP_ICON_INSET * 2, 1 - CHIP_ICON_INSET * 2)
	icon.Image = url(UIAssets.Inventory.Favorite)
	icon.ZIndex = strip.ZIndex
	icon.Parent = button

	button:SetAttribute("Scale", CHIP_HOVER_SCALE)
	CollectionService:AddTag(button, "UIButton")
	button.MouseButton1Click:Connect(function()
		self:_toggleFavorite(entry)
	end)

	return { strip = strip, favorite = { button = button, icon = icon, stroke = stroke } }
end

--- One card, for one owned car. `key = nil` builds the "leave empty" card at the head of the list.
function Page:_makeCard(key: string?, order: number)
	local card = self._template:Clone()
	card.Name = key or "LeaveEmpty"
	card.LayoutOrder = order
	-- So a tucked chip column is neither drawn nor clickable off the card's right edge. See
	-- `CHIP_TUCK_X`; everything else on the card lives inside 0..1 on both axes already.
	card.ClipsDescendants = true

	-- The artist's names, kept: `Dealership Tier` is the car's name line and `$` is the money line.
	local name = card:FindFirstChild("Dealership Tier") :: TextLabel
	local price = card:FindFirstChild("$") :: TextLabel
	--[[ `Rating` is the artist's own small line under the name — it was drawn holding "5.7" and it
		held "TIER 3" until this page grew a stats tooltip to put the tier in. It is now the RARITY,
		in the band's colour, which is the thing a collection screen most wants under a car's name
		(Trello: "Add the rarity text label with different color on the car in the menu"). ]]
	local rarity = card:FindFirstChild("Rating") :: TextLabel

	-- Two statements, not an `if` expression: that form yields a single value, so the paint of every
	-- card would silently come back nil and every car would draw as stock.
	local body, paint, mutation = nil, nil, nil
	if key then
		body, paint, mutation = GarageConfig.parseCarKey(key)
	end

	local extras = self:_decorateCard(card)

	if key and body then
		local tier = GarageConfig.TierOfBody[body]
		local word, colour = CarRarity.labelOf(body)
		name.Text = cardName(body, paint or PaintConfig.StockIndex)
		--[[ THE RATE IS THE MUTATED ONE. `rateOf` multiplies by the weather (`WeatherConfig`), and a
			card that quoted the plain rate would be telling the player a Charged Camaro earns what an
			ordinary one does — on the exact screen they use to decide which car to park. It is the
			one number on this card that is a promise about money. ]]
		price.Text = string.format("%s/s", GarageConfig.formatRate(GarageConfig.rateOf(tier, mutation)))

		--[[ The mutation takes over the RARITY line rather than getting a slot of its own, and takes
			its colour with it. That is the honest home for it: a mutation IS a rarity — it is the
			rarest thing about a car that has one — and the band word ("SPORTS") is still there
			behind it, so nothing is lost. A second label would also have to be authored, and this
			screen's cards are the artist's, not this file's.

			The band word survives as the tail because two Charged cars can be different rungs, and
			the rung is what the card's other numbers are priced off. ]]
		local mutated = WeatherConfig.mutationOf(mutation)
		if mutated then
			rarity.Text = fill(string.upper(mutated.Name .. (if word ~= "" then " " .. word else "")))
			rarity.TextColor3 = mutated.Color
			rarity.Visible = true
		else
			rarity.Text = fill(string.upper(word))
			rarity.TextColor3 = colour
			-- A body on no ladder has no rarity word; the line hides rather than drawing an empty rect.
			rarity.Visible = word ~= ""
		end
	else
		name.Text = fill(TEXT.ClearBay)
		price.Text = ""
		rarity.Visible = false
	end

	--[[ The car's own frame, empty for now: `CarViewportGrid` fills it in — and empties it again — as
		the list scrolls past, and header note 9 is why. The "leave empty" card gets none and goes into
		the grid as a spacer, because there is no car to show on it. ]]
	local viewport = nil
	if key and body then
		viewport = CarViewport.new(card, "CarView")
		viewport.AnchorPoint = Vector2.new(0.5, 0.5)
		viewport.Position = UDim2.fromScale(0.5, VIEW_CENTRE)
		viewport.Size = UDim2.fromScale(VIEW_WIDTH, VIEW_HEIGHT)
		viewport.ZIndex = 0
	end

	card.Parent = self.Scroll

	--[[ The entry IS the grid's cell — `viewport`, `body`, `paint` and `fade` are the fields
		`CarViewportGrid` reads, and it keeps its own bookkeeping alongside them. One table rather
		than two, so there is no pairing to keep in step. ]]
	local entry = {
		key = key,
		body = body,
		paint = paint,
		viewport = viewport,
		fade = 0,
		--[[ Searchable by BODY, by COLOUR and by RARITY, so "red" narrows the list to your red cars,
			"camaro" to every Camaro you own and "supercar" to the top of every ladder. All three are
			normalised into the same haystack rather than searched separately: the box is one field
			and a player typing "red camaro" means the intersection, which a single `find` over
			"redcamaro" gives for free. ]]
		search = if body
			then normalize(PaintConfig.nameOf(paint or PaintConfig.StockIndex) .. body .. (CarRarity.of(body)))
			else "",
		card = card,
		name = name,
		price = price,
		rarity = rarity,
		level = extras.level,
		status = extras.status,
		star = extras.star,
		active = extras.active,
		flash = extras.flash,
		favorited = false,
		chipsIn = false,
	}

	-- The LEAVE EMPTY card is not a car and has nothing to favourite.
	if key and INVENTORY_ON then
		entry.chips = self:_buildChips(card, entry)
	end

	--[[ A CARD IS A BUTTON LIKE ANY OTHER, so it carries the tag and gets the swell and the two
		sounds. It could not before 2026-08-19 and the reason is worth keeping: the swell was written
		to `Size`, and a cell is drawn at the `UIGridLayout`'s CellSize whatever its own `Size` says —
		the tween was written and then ignored, so the nudge simply never happened. It rides a UIScale
		now, which multiplies the cell after the grid has placed it, so nothing else in the list moves
		when one card lifts. See `Components/Button`. ]]
	card:SetAttribute("Scale", CARD_HOVER_SCALE)
	CollectionService:AddTag(card, "UIButton")

	self:_wireCard(entry)

	return entry
end

--[[ THE FOUR WAYS A CARD IS POINTED AT, and they are four because the devices genuinely differ.

	  mouse   MouseEnter/Leave show the tooltip and slide the chips in; the click spawns.
	  touch   the tap spawns and a HOLD shows the tooltip instead — see `HOLD_SECONDS`. The chips
	          are permanently out on this device, so nothing has to reveal them.
	  gamepad the selection landing on a card is the hover (`Components/Button` treats it the same
	          way), and `Activated` filtered to a controller input is the press. Without that filter
	          it would double every mouse click, because the engine raises `Activated` for those too.

	MOUSEENTER FIRES ON A TAP AS WELL, which is why the mouse path asks `_touchDevice` before doing
	anything: without it a tap would flash the cursor-following tooltip at wherever the pointer
	happens to be parked. ]]
function Page:_wireCard(entry)
	local card = entry.card

	--[[ A RELEASE ONLY COUNTS IF ITS PRESS BEGAN ON THIS CARD — the same guard `Pages/StartCar` now
		carries, and put here for the reason header note 1 of that file gives: these two are the same
		authored card wired to two different verbs, so a press bug in one is a press bug in both.

		The trap is that this page is opened by a rail button, and every tagged `UIButton` presses on
		the way DOWN (`Components/Button`) while `UIController:openPage` draws the page in the same
		frame. On a touch screen that leaves the release homeless: the engine gives it to whatever is
		under the finger by then, which is one of these cards, and the card spawns a car nobody asked
		for. `Pages/StartCar` has the 24 Aug clip of the same thing starting a whole race.

		THE RELEASE STAYS THE VERB HERE and is not moved to `MouseButton1Down`, for two reasons
		rather than StartCar's one: these cards are in a scrolling grid (a down would spawn a car
		every time somebody scrolled), and the tap is only half the gesture — a HOLD previews instead
		of spawning, and a hold is not knowable until the finger has been down a while. See
		`HOLD_SECONDS`.

		`InputBegan` below is the only event that says the press STARTED here, so it is what arms
		this. Gamepad has no `InputBegan` to arm with and keeps coming in on `Activated`. ]]
	local armed = false

	card.MouseButton1Click:Connect(function()
		if not armed then
			return
		end
		armed = false
		self:_press(entry)
	end)

	card.MouseEnter:Connect(function()
		if self:_touchDevice() then
			return -- a tap raises this too; there is no cursor to hang a cursor tooltip off
		end
		self:_setChips(entry, true)
		self:_showTip(entry, "mouse")
	end)
	card.MouseLeave:Connect(function()
		if self:_touchDevice() then
			return
		end
		self:_setChips(entry, false)
		self:_hideTip(entry)
	end)

	card.SelectionGained:Connect(function()
		self:_setChips(entry, true)
		self:_showTip(entry, "select")
	end)
	card.SelectionLost:Connect(function()
		self:_setChips(entry, self:_touchDevice())
		self:_hideTip(entry)
	end)

	card.Activated:Connect(function(inputObject: InputObject?)
		-- Controller only; the pointer's own press already came in on `MouseButton1Click`.
		if not inputObject or inputObject.UserInputType.Name:sub(1, 7) ~= "Gamepad" then
			return
		end
		self:_press(entry)
	end)

	-- === The touch hold ===
	card.InputBegan:Connect(function(input: InputObject)
		-- Arms the click above, and it is armed for a press that lands on a chip too: the chip eats
		-- the click itself, and a finger that slides off one onto the card is still a press that
		-- began here.
		if input.UserInputType == Enum.UserInputType.MouseButton1 or isTouch(input.UserInputType) then
			armed = true
		end
		if not isTouch(input.UserInputType) then
			return
		end
		-- A finger that came down on the chip is asking to favourite, not to preview.
		if self:_touchOver(entry, input.Position) then
			return
		end
		self:_holdBegan(entry, input)
	end)
	card.InputChanged:Connect(function(input: InputObject)
		if isTouch(input.UserInputType) then
			self:_holdMoved(entry, input)
		end
	end)
	card.InputEnded:Connect(function(input: InputObject)
		if isTouch(input.UserInputType) then
			self:_holdEnded(entry)
		end
	end)
end

--[[ Is a finger driving this screen? Asked of the engine on every read rather than of the latched
	flag alone, and the first tap on a phone is why: `LastInputTypeChanged` and the GUI's own
	`MouseEnter` both fire off that one touch and their order is not guaranteed, so a page that
	trusted only the latch would flash a cursor tooltip once per session at wherever the pointer
	happens to be parked. The latch stays because the repaint it drives has to happen once, not per
	read. ]]
function Page:_touchDevice(): boolean
	return self._touchUI or isTouch(UserInputService:GetLastInputType())
end

--- Is this screen point inside `entry`'s chip? A rect rather than the input system, because
--- `InputBegan` on a GuiObject fires for a press its own child has already taken.
function Page:_touchOver(entry, position: Vector3): boolean
	local chips = entry.chips
	if not (chips and chips.strip.Visible) then
		return false
	end
	local inset = GuiService:GetGuiInset()
	local x, y = position.X - inset.X, position.Y - inset.Y
	local topLeft = chips.favorite.button.AbsolutePosition
	local size = chips.favorite.button.AbsoluteSize
	return x >= topLeft.X and x <= topLeft.X + size.X and y >= topLeft.Y and y <= topLeft.Y + size.Y
end

function Page:_holdBegan(entry, input: InputObject)
	self._holdEntry = entry
	self._holdFrom = Vector2.new(input.Position.X, input.Position.Y)

	task.delay(HOLD_SECONDS, function()
		if self._holdEntry ~= entry then
			return -- lifted, dragged away, or another finger took over
		end
		--[[ The release that ends this hold still raises `MouseButton1Click`, so the tap path has to
			be told to sit this one out. See `PRESS_BLOCK`. ]]
		self._noPressUntil = os.clock() + PRESS_BLOCK
		self:_showTip(entry, "touch", self._holdFrom)
	end)
end

--- A finger that wanders is scrolling the list, not holding a card. Cancels both the pending hold
--- and a preview that has already opened, and blocks the tap the release would otherwise be.
function Page:_holdMoved(entry, input: InputObject)
	if self._holdEntry ~= entry or not self._holdFrom then
		return
	end
	local moved = (Vector2.new(input.Position.X, input.Position.Y) - self._holdFrom).Magnitude
	if moved < HOLD_DRAG_PX then
		return
	end
	self._holdEntry = nil
	self._noPressUntil = os.clock() + PRESS_BLOCK
	self:_hideTip(entry)
end

function Page:_holdEnded(entry)
	if self._holdEntry == entry then
		self._holdEntry = nil
	end
	-- The preview lives exactly as long as the finger does.
	if self._tipMode == "touch" then
		self:_hideTip(entry)
	end
end

--[[ Rebuild the list from the collection.

	SORTED FAVOURITES FIRST, then by TIER best first, then by the key itself. The middle term is the
	one that was always here and its reasoning is unchanged — the question this screen answers is
	"what is the most valuable thing I own", and acquisition order buries the answer under whatever
	you happened to steal last. The favourite term is on top of it because that is the entire point
	of a favourite: it is a marker whose only job is putting a car where you can find it again.

	SORTING BY THE KEY LAST, rather than by the body, is what keeps several copies of one body
	adjacent: the key begins with the body name, so "Camaro:3" and "Camaro:6" land next to each other
	and the colours read as a set of one car rather than as two unrelated cards that happen to share
	a silhouette. ]]
function Page:_rebuild()
	if not self._template then
		return
	end

	self:_hideTip()

	-- Emptied BEFORE the cards go, so the grid lets go of viewports that still exist rather than of
	-- ones it has to reason about the destruction of. `_applyFilter` hands it the new list.
	self._views:clear()
	for _, entry in self._entries do
		entry.card:Destroy()
	end
	table.clear(self._entries)

	local favorites = parseSet(self.Player:GetAttribute(InventoryConfig.FavoritesAttribute))
	local owned = GarageConfig.split(self.Player:GetAttribute(GarageConfig.OwnedAttribute))
	table.sort(owned, function(a, b)
		local fa, fb = favorites[a] == true, favorites[b] == true
		if fa ~= fb then
			return fa
		end
		local ta = GarageConfig.TierOfBody[(GarageConfig.parseCarKey(a))] or 0
		local tb = GarageConfig.TierOfBody[(GarageConfig.parseCarKey(b))] or 0
		if ta ~= tb then
			return ta > tb
		end
		return a < b
	end)

	--[[ THE LEAVE EMPTY CARD EXISTS IN BAY MODE ONLY. In inventory mode there is no bay to clear,
		and putting a car away is what pressing the card that is already out does — so a card whose
		whole job is "none of these" would be a card with nothing to do. ]]
	if self._mode == "bay" then
		table.insert(self._entries, self:_makeCard(nil, 0))
	end
	for index, key in owned do
		table.insert(self._entries, self:_makeCard(key, index))
	end

	self._visibleCount = #self._entries
	self:_applyFilter()
	self:_refreshCaption()
	self:_refresh()
end

--[[ Repaint every card's state without rebuilding: which bay each car is on, what is in the street,
	the levels, the star and the blue outline. Runs on every attribute change and on every open,
	so it is the one that has to be cheap; the collection only changes when a car is banked or sold. ]]
function Page:_refresh()
	local lot = parseLot(self.Player:GetAttribute(GarageConfig.LotAttribute))
	local favorites = parseSet(self.Player:GetAttribute(InventoryConfig.FavoritesAttribute))
	local levels = RewardConfig.decodeLevels(self.Player:GetAttribute(GarageConfig.LevelsAttribute))
	local inLobby = self.Player:GetAttribute(LobbyCarConfig.SpawnedAttribute)

	local occupied = false
	for _, bay in lot do
		if bay == self._bay then
			occupied = true
			break
		end
	end

	for _, entry in self._entries do
		--[[ The "leave empty" card is the current state when nothing is parked here, and it says so
			in the same words a car does. Without this an empty bay is the one case the screen shows
			no marker at all, which reads as the page having failed to load rather than as the bay
			being empty on purpose. ]]
		if not entry.key then
			entry.status.Text = if occupied then "" else fill(TEXT.ParkedHere)
			entry.active.Enabled = not occupied
			continue
		end

		--[[ Looked up by the whole KEY. By body it would mark every colour of a body as parked the
			moment one of them was, which is the exact confusion owning two Camaros exists to avoid. ]]
		local bay = lot[entry.key]
		local here = bay == self._bay and self._mode == "bay"
		local out = entry.key == inLobby

		--[[ Opacity is the kit's own state language, so "parked on some OTHER bay" is a fade rather
			than a badge colour. The card stays pressable — pressing it moves the car here.

			IT ONLY MEANS ANYTHING IN BAY MODE, and forgetting that dimmed six cards out of ten on
			the first playtest of the inventory. "Spoken for" is a statement about the bay you are
			editing; open the same list from the HUD rail and there is no bay, so every parked car
			read as unavailable when in fact the whole lot is available. In inventory mode the bay is
			just something a card SAYS (the status line), never something it is dimmed for. ]]
		local fade = if bay and not here and self._mode == "bay" then ELSEWHERE_TRANSPARENCY else 0
		entry.card.ImageTransparency = fade
		entry.name.TextTransparency = fade
		entry.price.TextTransparency = fade
		entry.rarity.TextTransparency = fade
		-- The car fades with the card it is on. `ImageTransparency` on a ViewportFrame is the
		-- RENDERED SCENE's transparency, so this one write dims the whole model rather than 25 parts.
		-- Latched as well as applied, because a car built later has to arrive already dimmed.
		entry.fade = fade
		if entry.viewport then
			entry.viewport.ImageTransparency = fade
		end

		--[[ LEVEL IS PER BODY, not per key — XP is earned in a body and both your Camaros carry it
			(`RewardConfig`). Hidden at level 1, which is every car nobody has driven far in: the
			chip is there to say "this one is worth more than it looks", and printing it on all
			forty cards says nothing at all. ]]
		local level = levels[entry.body] or 1
		entry.level.Text = if level > 1 then fill(TEXT.LevelShort, { level = level }) else ""
		entry.level.TextTransparency = fade

		entry.favorited = favorites[entry.key] == true
		self:_paintFlags(entry)

		--[[ ONE STATUS LINE AND THREE THINGS IT COULD SAY, in this order: the bay this screen is
			about, the street, then any other bay. A car can be parked and out at the same time only
			for an instant (the server despawns it), so the ordering only ever decides which of two
			true things is worth the space — and the one the screen was opened for wins. ]]
		if here then
			entry.status.Text = fill(TEXT.ParkedHere)
		elseif out then
			entry.status.Text = fill(TEXT.InTheLobby)
		elseif bay then
			entry.status.Text = fill(TEXT.OnBay, { bay = bay })
		else
			entry.status.Text = ""
		end
		entry.status.TextTransparency = fade

		-- The blue outline follows the mode: the car on THIS bay, or the car in the street.
		entry.active.Enabled = if self._mode == "bay" then here else out
	end

	-- The tooltip is describing one of the cards that just changed underneath it.
	self:_refreshTip()
end

--[[ The star, in whichever of its two homes is showing. The MARK is the resting state and is drawn
	only when the flag is ON; the CHIP is the verb and is drawn either way, lit or unlit. They are the
	same picture, so never more than one of them is on screen at a time. ]]
function Page:_paintFlags(entry)
	local chipsIn = entry.chipsIn and entry.chips ~= nil
	entry.star.Visible = entry.favorited and not chipsIn
	entry.star.ImageTransparency = entry.fade

	if not entry.chips then
		return
	end
	local chip = entry.chips.favorite
	local on = entry.favorited
	chip.button.BackgroundColor3 = if on then BRAND_BLUE else DEEP_NAVY
	chip.button.BackgroundTransparency = if on then 0.05 else 0.25
	chip.icon.ImageTransparency = if on then 0 else 0.4
	chip.stroke.Transparency = if on then 0.25 else 0.6
end

--[[ Slide the favourite chip in or out. `instant` skips the tween, which is what a device change
	wants — a player who has just put the mouse down and picked the screen up should find the chip
	already there rather than watching forty of them animate.

	THE STRIP IS HIDDEN AT THE FAR END rather than left parked off the edge. The card clips, so an
	invisible chip out there is already unclickable; `Visible` is belt and braces and it also keeps
	the tucked chip out of `_touchOver`'s rect test. ]]
function Page:_setChips(entry, on: boolean, instant: boolean?)
	local chips = entry.chips
	if not chips then
		return
	end
	on = on or self:_touchDevice()
	if entry.chipsIn == on and not instant then
		return
	end
	entry.chipsIn = on

	if entry.chipTween then
		entry.chipTween:Cancel()
		entry.chipTween = nil
	end

	local goal = UDim2.fromScale(if on then CHIP_REST_X else CHIP_TUCK_X, CHIP_CENTRE_Y)
	if on then
		chips.strip.Visible = true
	end

	if instant then
		chips.strip.Position = goal
		chips.strip.Visible = on
	else
		local tween = TweenService:Create(chips.strip, CHIP_TWEEN, { Position = goal })
		entry.chipTween = tween
		if not on then
			tween.Completed:Once(function(state: Enum.PlaybackState)
				if state == Enum.PlaybackState.Completed and not entry.chipsIn then
					chips.strip.Visible = false
				end
			end)
		end
		tween:Play()
	end

	self:_paintFlags(entry)
end

-- === Pressing a card ========================================================

--[[ WHAT A PRESS MEANS, and since 2026-08-24 it means the thing itself rather than "select this".

	    bay mode        park this car on the bay you walked up to (or clear it, on LEAVE EMPTY)
	    inventory mode  put this car in the street — or, if it is already out, put it away, which
	                    `LobbyCarService.setLobbyCar` reads out of the same publish

	TWO GUARDS AND THEY GUARD DIFFERENT THINGS. `_noPressUntil` is the long press's — a preview ends
	in a release and a release is a click, so the tap that opened the stats must not also spawn the
	car. `_nextPressAt` is the spam floor the owner asked for: both services do real work per request
	(a lot rebuild, a 310-instance clone) and both re-check their own cooldown, so this one exists to
	stop the mash at the source rather than to pay a round trip to be told no. Its length is READ
	FROM THE SERVICE'S OWN CONFIG rather than typed, so the two can never drift apart.

	AND IN INVENTORY MODE A SPAWN CLOSES THE SCREEN (Dylan, 2026-09-19). The car arrives in the
	street behind this panel, so a page left standing is one the player shuts by hand to look at what
	they pressed for. A PUT-AWAY DOES NOT close it: the press is a toggle, and clearing the street is
	usually the first half of picking something else out of the same list. Bay mode never closes — a
	lot is a list you work down. The same rule, and the same reasoning, as `PagesV2/Dealership`. ]]
function Page:_press(entry)
	local now = os.clock()
	if now < self._noPressUntil then
		return -- that was a hold, not a tap
	end
	if now < self._nextPressAt then
		return
	end

	local key = entry.key
	local spawning = false

	if self._mode == "bay" then
		self._nextPressAt = now + GarageConfig.Picker.Cooldown
		Dispatcher:Publish("DealershipPick", self._bay, key)
	else
		if not key then
			return -- the LEAVE EMPTY card only exists in bay mode, but a stale one is not a spawn
		end
		self._nextPressAt = now + LobbyCarConfig.RequestCooldown
		Dispatcher:Publish("SpawnCarPick", key)

		--- WHICH HALF OF THE TOGGLE THIS WAS, read off the attribute `_refresh` paints the verb
		--- from so the page cannot close on a press whose button said PUT AWAY.
		spawning = key ~= self.Player:GetAttribute(LobbyCarConfig.SpawnedAttribute)
	end

	self:_flash(entry)

	--[[ The close, and it is the LAST thing so that the flash above is still the one acknowledgement
		this page makes — on a spawn it simply plays over a panel already tweening out, which costs
		nothing and keeps the two presses that do not close identical to the one that does. ]]
	if spawning then
		self.UIController:closePage(PAGE_NAME)
	end
end

--- The acknowledgement. See `FLASH_TWEEN` — it covers the round trip, nothing more.
function Page:_flash(entry)
	local flash = entry.flash
	flash.BackgroundTransparency = FLASH_PEAK
	TweenService:Create(flash, FLASH_TWEEN, { BackgroundTransparency = 1 }):Play()
end

--- Ask the server to star or unstar this car. Header note 8 — it publishes and stops.
function Page:_toggleFavorite(entry)
	local key = entry.key
	if not (key and INVENTORY_ON) then
		return
	end
	local on = parseSet(self.Player:GetAttribute(InventoryConfig.FavoritesAttribute))[key] ~= true
	Dispatcher:Publish("InventoryFlag", key, InventoryConfig.Keys.Favorites, on)
end

-- === The stats tooltip ======================================================

--[[ Header note 9. One panel, built once, that follows whatever is pointing at the list.

	IT IS A SIBLING OF `Main` rather than a child of it, so it can hang off the LEFT of the column
	and out over the world — a tooltip clipped to the panel it describes would have nowhere to go on
	a screen whose list already hugs the right edge.

	IT IS MADE OF THE KIT'S OWN PARTS and nothing was drawn for it: `Page.Panel` nine-sliced for the
	body and `Bar.Track` / `Bar.FillBlue` for the four bars, which is what the deleted detail pane
	used for the same four numbers. ]]
function Page:_buildTooltip()
	local tip = Instance.new("ImageLabel")
	tip.Name = "Stats"
	tip.BackgroundTransparency = 1
	tip.AnchorPoint = Vector2.new(0, 0)
	tip.Position = UDim2.fromOffset(0, 0)
	tip.Size = UDim2.fromOffset(10, 10) -- `_placeTip` owns this; see the note on TIP_HEIGHT
	tip.Image = url(UIAssets.Page.Panel)
	slice(tip, UIAssets.Size.Panel, UIAssets.Slice.Panel)
	--[[ Over everything else on the page. `ZIndexBehavior.Sibling` means this only has to beat its
		own siblings — `Main` and `Done` — and a descendant of either can never come out on top of
		it whatever ZIndex it carries. ]]
	tip.ZIndex = 50
	tip.Visible = false
	tip.Parent = self.PageUI
	self._tip = tip

	--[[ THE ONE OPAQUE PANEL IN THE KIT, and it has to be. Every other panel here is the artist's
		80%: `Page.Panel`'s body is `(40,51,75)` at alpha 204, which is right for a screen you look
		AT — the world showing faintly through a menu is what makes it feel like a menu. It is wrong
		for a panel that sits ON TOP of the list it is describing: at 80% the card names and prices
		underneath came straight through it and the stats were unreadable over them.

		SO THE BODY IS BACKED RATHER THAN THE TEXTURE REPLACED. A rect of the texture's own colour
		goes underneath it, inset far enough to stay inside the nine-sliced border, and the artist's
		border and corners still draw. Nothing was re-uploaded and nothing else on the page changes.

		The inset is in PIXELS because the border is: `ScaleType.Slice` pins the corner art at 1:1
		texture pixels whatever size the frame is, so a scale inset would be right at one size only. ]]
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundColor3 = Color3.fromRGB(40, 51, 75)
	body.BorderSizePixel = 0
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.Size = UDim2.new(1, -TIP_BORDER * 2, 1, -TIP_BORDER * 2)
	body.ZIndex = tip.ZIndex
	body.Parent = tip

	-- Everything else draws over it. One number above the backing, and a descendant always draws
	-- over its ancestor, so this is the whole of the stacking on this panel.
	local content = tip.ZIndex + 1

	local function text(name: string, y: number, width: number, height: number, colour: Color3): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, y)
		label.Size = UDim2.fromScale(width, height)
		label.ZIndex = content
		label.FontFace = FONT
		label.TextColor3 = colour
		label.TextScaled = true
		label.Text = ""
		label.Parent = tip
		return label
	end

	self._tipName = text("CarName", TIP.NameY, 0.88, TIP.NameHeight, WHITE)
	self._tipRarity = text("Rarity", TIP.RarityY, 0.84, 0.052, MUTED)
	self._tipMeta = text("Meta", TIP.MetaY, 0.84, 0.048, MUTED)

	--[[ The four stat rows. Built from `InventoryConfig.Stats` rather than written out, so adding a
		fifth stat is one entry in that file and no edit here — and so the ORDER on screen is the
		order declared there, which is the only place it should be decided. ]]
	self._tipStats = {}
	if INVENTORY_ON then
		for index, stat in InventoryConfig.Stats do
			local y = TIP.StatTop + (index - 1) * TIP.StatPitch

			local caption = Instance.new("TextLabel")
			caption.Name = stat.Key .. "Label"
			caption.BackgroundTransparency = 1
			caption.AnchorPoint = Vector2.new(0, 0.5)
			caption.Position = UDim2.fromScale(STAT_LABEL_LEFT, y)
			caption.Size = UDim2.fromScale(STAT_LABEL_WIDTH, TIP.StatHeight)
			caption.ZIndex = content
			caption.FontFace = FONT
			caption.TextColor3 = MUTED
			caption.TextScaled = true
			caption.TextXAlignment = Enum.TextXAlignment.Left
			caption.Text = fill(stat.Label)
			caption.Parent = tip

			local bar = self:_makeBar(tip, y, STAT_TRACK_WIDTH, UIAssets.Page.Bar.FillBlue, STAT_TRACK_LEFT, content)

			local rating = Instance.new("TextLabel")
			rating.Name = stat.Key .. "Rating"
			rating.BackgroundTransparency = 1
			rating.AnchorPoint = Vector2.new(0, 0.5)
			rating.Position = UDim2.fromScale(STAT_RATING_LEFT, y)
			rating.Size = UDim2.fromScale(STAT_RATING_WIDTH, TIP.StatHeight)
			rating.ZIndex = content
			rating.FontFace = FONT
			rating.TextColor3 = WHITE
			rating.TextScaled = true
			rating.TextXAlignment = Enum.TextXAlignment.Right
			rating.Text = ""
			rating.Parent = tip

			table.insert(self._tipStats, { stat = stat, bar = bar, rating = rating })
		end
	end

	self._tipRate = text("Rate", TIP.RateY, 0.70, 0.062, CASH_GREEN)
	--[[ The last line is the VERB, and it is the whole reason this tooltip has to exist on a screen
		with no buttons left on it: a card that spawns a car on a tap has to say so somewhere, and
		the panel the player is already reading is the only place with room.

		IT IS NOT DRAWN IN `MUTED` LIKE THE OTHER TWO CAPTIONS. Those are labels on facts; this is
		the one instruction on the screen, and at the caption grey it read as fine print on a panel
		that has no other call to action anywhere. A pale brand blue puts it in the kit's own accent
		without making it as loud as the car's name. ]]
	self._tipHint = text("Hint", TIP.HintY, 0.88, 0.046, HINT_BLUE)
end

--[[ One progress bar: the kit's track with a fill laid over its left edge.

	THE FILL IS ANCHORED LEFT AND THE TRACK IS NOT. That is the whole trick, and it is the one place
	on this UI where the house 0.5,0.5 anchor is wrong: a bar grows from its left edge, so a
	centre-anchored fill would grow in both directions out of the middle. `UIGeom`'s header calls
	this out as the exception it is. ]]
function Page:_makeBar(parent: GuiObject, y: number, width: number, fillId: number, left: number?, z: number?)
	local layer = z or parent.ZIndex
	local track = Instance.new("ImageLabel")
	track.Name = "Track"
	track.BackgroundTransparency = 1
	track.AnchorPoint = Vector2.new(if left then 0 else 0.5, 0.5)
	track.Position = UDim2.fromScale(left or 0.5, y)
	track.Size = UDim2.fromScale(width, STAT_BAR_HEIGHT)
	track.ZIndex = layer
	track.Image = url(UIAssets.Page.Bar.Track)
	slice(track, UIAssets.Size.BarTrack, UIAssets.Slice.BarTrack)
	track.Parent = parent

	local fill_ = Instance.new("ImageLabel")
	fill_.Name = "Fill"
	fill_.BackgroundTransparency = 1
	fill_.AnchorPoint = Vector2.new(0, 0.5)
	fill_.Position = UDim2.fromScale(0.012, 0.5)
	fill_.Size = UDim2.fromScale(0, 0.72)
	fill_.ZIndex = layer
	fill_.Image = url(fillId)
	slice(fill_, UIAssets.Size.BarFill, UIAssets.Slice.BarFill)
	fill_.Parent = track

	return { track = track, fill = fill_ }
end

--[[ Show the panel for one card. `mode` is which pointer asked for it and decides where it goes:

	    "mouse"   it follows the cursor, on the LEFT of it and clear of the column — the list is up
	              against the right edge of the screen, so a panel drawn to the right of the pointer
	              would be off it and one drawn under the pointer would be over the cards.
	    "touch"   the same side, vertically centred on the finger. ABOVE it is the conventional
	              answer and it is the wrong one here: the list is a column against the right edge,
	              so a panel centred over the touch lands on top of the cards. Beside the column,
	              the panel is over the world and clear of both the finger and the list. Placed once
	              and left there for as long as the hold lasts.
	    "select"  a gamepad highlight; it hangs off the left of the card itself and tracks it, so a
	              list scrolled with the stick carries the panel with it.

	The LEAVE EMPTY card has no stats and gets no panel. ]]
function Page:_showTip(entry, mode: string, at: Vector2?)
	if not (self._tip and entry.key) then
		return
	end

	self._tipEntry = entry
	self._tipMode = mode
	if at then
		self._tipAt = at
	end

	if not self:_refreshTip() then
		return
	end

	self._tip.Visible = true
	self:_trackTip(true)
	self:_placeTip()
end

--- Put it away. `entry` is what the caller thinks it is describing; a leave/release that arrives
--- after the pointer has already moved on to another card must not blank the new one's panel.
function Page:_hideTip(entry)
	if entry and self._tipEntry ~= entry then
		return
	end
	self._tipEntry = nil
	self._tipMode = nil
	self._tipAt = nil
	self:_trackTip(false)
	if self._tip then
		self._tip.Visible = false
	end
end

--[[ The follow. One RenderStepped while a panel is up and none at all when it is not — a tooltip
	that costs a frame connection when nothing is hovered is a tooltip that costs it all session. ]]
function Page:_trackTip(on: boolean)
	if on then
		if self._tipConn then
			return
		end
		self._tipConn = RunService.RenderStepped:Connect(function()
			self:_placeTip()
		end)
	elseif self._tipConn then
		self._tipConn:Disconnect()
		self._tipConn = nil
	end
end

--[[ Fill the panel from the card it is describing. Returns false when there is nothing to describe,
	which is what makes it safe to call from `_refresh` — the attributes change while a panel is up
	(you spawned the car it is about) and the line that says what a press will do has to follow. ]]
function Page:_refreshTip(): boolean
	local entry = self._tipEntry
	if not (self._tip and entry and entry.key and entry.body) then
		return false
	end

	local body = entry.body
	local tier = GarageConfig.TierOfBody[body]
	local levels = RewardConfig.decodeLevels(self.Player:GetAttribute(GarageConfig.LevelsAttribute))
	local level = levels[body] or 1
	local word, colour = CarRarity.labelOf(body)

	self._tipName.Text = cardName(body, entry.paint or PaintConfig.StockIndex)
	self._tipRarity.Text = fill(string.upper(word))
	self._tipRarity.TextColor3 = colour
	self._tipMeta.Text = fill(TEXT.Meta, { tier = tier or "?", level = fill(TEXT.Level, { level = level }) })

	local stats = InventoryConfig.statsFor(body, level, MarketValueConfig.broadcastRecord(self.Player, entry.key).Parts)
	for _, row in self._tipStats do
		local _, fraction = InventoryConfig.readStat(row.stat, stats)
		row.bar.fill.Size = UDim2.fromScale(fraction * 0.976, 0.72)
		row.rating.Text = InventoryConfig.formatRating(fraction)
	end

	self._tipRate.Text = fill(TEXT.RateLine, { rate = GarageConfig.formatRate(GarageConfig.rateOf(tier)) })

	--[[ THE VERB, spelled for the device that is asking. A gamepad is told to CLICK, which is wrong
		in the letter and right in the spirit — there is no house word for "press A" and the only
		device that ever reads a "select"-mode panel already knows what it pressed to get here. ]]
	local press = fill(if self._tipMode == "touch" then TEXT.PressTouch else TEXT.PressMouse)
	local lot = parseLot(self.Player:GetAttribute(GarageConfig.LotAttribute))
	if self._mode == "bay" then
		if lot[entry.key] == self._bay then
			self._tipHint.Text = fill(TEXT.HintParked)
		else
			self._tipHint.Text = fill(TEXT.HintPark, { press = press, bay = self._bay })
		end
	elseif self.Player:GetAttribute(LobbyCarConfig.SpawnedAttribute) == entry.key then
		self._tipHint.Text = fill(TEXT.HintPutAway, { press = press })
	else
		self._tipHint.Text = fill(TEXT.HintSpawn, { press = press })
	end

	return true
end

--[[ Where it goes. Everything here is in PIXELS in the page frame's own space, which is the whole
	screen (header note 6) — and the page frame is the parent, so an offset position needs no
	conversion beyond subtracting its corner.

	THE POINTER IS IN A DIFFERENT SPACE FROM THE GUI AND THE INSET IS THE DIFFERENCE.
	`GetMouseLocation` and `InputObject.Position` are in true viewport pixels; every
	`AbsolutePosition` under `MainUI` is measured from BELOW the topbar, because that ScreenGui
	carries `ScreenInsets = DeviceSafeInsets` (which supersedes its `IgnoreGuiInset`). Subtracting
	`GetGuiInset` is what puts them in the same units — a panel placed without it sits 58px low and
	reads as the tooltip lagging the cursor.

	THE SIZE IS COMPUTED HERE RATHER THAN LEFT TO A CONSTRAINT, because the placement has to know it
	before the frame has been laid out: an aspect constraint's answer only shows up in `AbsoluteSize`
	a frame later, and a panel placed against last frame's size jumps on the one where it appears. ]]
function Page:_placeTip()
	local tip = self._tip
	local entry = self._tipEntry
	if not (tip and entry) then
		return
	end

	local area = self.PageUI.AbsoluteSize
	local origin = self.PageUI.AbsolutePosition
	if area.X <= 0 or area.Y <= 0 then
		return
	end

	local height = math.min(TIP_HEIGHT * area.Y, TIP_MAX_WIDTH * area.X / TIP_ASPECT)
	local width = height * TIP_ASPECT
	if self._tipW ~= width or self._tipH ~= height then
		self._tipW, self._tipH = width, height
		tip.Size = UDim2.fromOffset(width, height)
	end

	local inset = GuiService:GetGuiInset()
	local anchorX, anchorY
	if self._tipMode == "select" then
		-- Off the card's left edge, vertically centred on it.
		local cardPos, cardSize = entry.card.AbsolutePosition, entry.card.AbsoluteSize
		anchorX = cardPos.X - origin.X
		anchorY = cardPos.Y + cardSize.Y * 0.5 - origin.Y - height * 0.5
	else
		local point = self._tipAt
		if self._tipMode ~= "touch" then
			local mouse = UserInputService:GetMouseLocation()
			point = Vector2.new(mouse.X, mouse.Y)
		end
		if not point then
			return
		end
		anchorX = point.X - inset.X - origin.X
		anchorY = point.Y - inset.Y - origin.Y
	end

	--[[ LEFT OF WHATEVER IS POINTING, ALWAYS, WHICH IS ONE RULE AND NOT THREE. The list is a column
		against the right edge of the screen, so the room is always on that side; only the vertical
		differs by device, and only because what has to be cleared differs — a cursor covers nothing,
		a finger covers the card under it, and a gamepad highlight is the card. ]]
	local x = anchorX - width - TIP_GAP
	local y
	if self._tipMode == "touch" then
		y = anchorY - height * 0.5
	elseif self._tipMode == "select" then
		y = anchorY
	else
		y = anchorY + TIP_GAP
	end

	--[[ ...AND NEVER OVER THE LIST. Off the pointer alone the panel lands on the cards whenever the
		pointer is in the list's LEFT column — a stats panel covering the four cards either side of
		the one it describes is worse than one a few pixels further out. So the right edge is pinned
		to the column's left edge whenever there is room for the whole panel outside it, which on any
		window this game is playable on there is. The flip to the pointer's other side survives
		underneath as the last resort for a window too narrow for even that. ]]
	local columnLeft = self.Main.AbsolutePosition.X - origin.X
	local outside = columnLeft - width - TIP_GAP
	if outside >= TIP_EDGE then
		x = math.min(x, outside)
	elseif x < TIP_EDGE then
		x = anchorX + TIP_GAP
	end

	--[[ ...AND NEVER OVER `Done`, which is the same rule again for the same reason. It is the only
		way off this screen a player who does not think to press the rail button twice will find, and
		it sits at the bottom centre — exactly where a panel hanging off a pointer low in the list
		gets clamped to. Above it when there is room for the whole panel there, and the plain screen
		clamp underneath for when there is not. ]]
	local floor = area.Y - height - TIP_EDGE
	local aboveDone = self.Done.AbsolutePosition.Y - origin.Y - height - TIP_GAP
	if aboveDone >= TIP_EDGE then
		floor = math.min(floor, aboveDone)
	end

	x = math.clamp(x, TIP_EDGE, math.max(area.X - width - TIP_EDGE, TIP_EDGE))
	y = math.clamp(y, TIP_EDGE, math.max(floor, TIP_EDGE))
	tip.Position = UDim2.fromOffset(x, y)
end

-- === Watching ===============================================================

function Page:_watchState()
	self:_rebuild()

	--[[ A rebuild for the two lists that change the CARDS, a repaint for the three that change what a
		card SAYS. Favourites are in the first group because they are a sort key — starring a car
		moves it to the top, which is a new order and therefore new cards. ]]
	for _, attribute in { GarageConfig.OwnedAttribute, InventoryConfig.FavoritesAttribute } do
		self.Player:GetAttributeChangedSignal(attribute):Connect(function()
			self:_rebuild()
		end)
	end
	for _, attribute in {
		GarageConfig.LotAttribute,
		GarageConfig.LevelsAttribute,
		LobbyCarConfig.SpawnedAttribute,
	} do
		self.Player:GetAttributeChangedSignal(attribute):Connect(function()
			self:_refresh()
		end)
	end
end

return Page
