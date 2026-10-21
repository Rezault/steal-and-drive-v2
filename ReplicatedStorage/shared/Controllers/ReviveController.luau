--[[
	ReviveController  (client)
	--------------------------
	The RESPAWN SCREEN: the one decision this game ever puts in front of a player mid-run.

	It goes up when `ReviveService` says so — a beat and a half after the wreck, once the car has
	finished coasting and smoking and the player has watched what happened — and it asks one
	question with a clock on it. Yes puts them back on the road in the same car; no, or letting the
	clock run out, ends the run the way a wreck has always ended it.

	=== IT IS A SCRIM, NOT A CURTAIN ==========================================================

	Every other full-screen moment in this game goes to near-black (`RaceUIController`), because
	those cover a teleport and there is deliberately nothing to see. This one is the opposite: the
	wrecked car IS the argument. It is sitting there smoking, thirty studs of road you just paid for
	behind it, and the whole reason the offer works is that the player can still see the run they are
	about to lose. So the overlay settles at `SCRIM_REST` and never gets darker — enough to make
	white text legible over a bright road, nowhere near enough to hide the car.

	=== THE HEADLINE IS THE QUESTION, NOT THE NEWS ============================================

	"WRECKED" is already on screen (`CarHudController`'s banner) and the smoking car says it again.
	Spending this screen's biggest line on news the player already has would waste the one moment
	they are reading it — and `RaceUIController` says WRECKED at the other end anyway, on the results
	screen, which is where the news belongs. So the split is: this screen ASKS, that screen REPORTS.

	Under it goes the distance, which is the actual stake. "Keep going?" is a button; "2,140m
	driven — keep going?" is a run worth not throwing away, and it is the same figure, from the same
	server-side measurement, that the results screen would print if they said no.

	=== THE CLOCK IS DRAWN, NOT COUNTED =======================================================

	The countdown is a bar that drains along the bottom edge of the REVIVE button, and there is no
	number anywhere. A ticking digit turns a decision into a test; a bar that is visibly emptying
	says the same thing in peripheral vision, while the player is reading the price. It also cannot
	disagree with itself: the width IS the remaining fraction of the offer.

	THE BAR IS NOT THE DEADLINE. The server sends how many seconds are left at the moment it sends,
	and this file turns that into a local deadline on arrival — so the bar lags the real one by a
	single trip, and empties a fraction of a second before the server gives up. That direction is the
	only one that is safe: a bar that emptied AFTER the offer closed would have the player pressing a
	button that had already stopped working. `ReviveConfig`'s own `OFFER_GRACE` is what leaves room
	for the lag at the other end, and the button locks itself at zero so the gap is never pressable.

	=== NOTHING HERE DECIDES ANYTHING =========================================================

	The button reports a press and nothing else. Which revive of the run this is, what it costs,
	whether there is a stored life to spend instead of prompting, and whether the offer is even still
	open are all the server's, and they arrive on the payload. This file draws what it is told and
	sends one empty message back.

	=== WITH THE NEW UI, THE PANEL IS THE KIT'S PROMPT ========================================

	With `UIRoot.isNewUI()` the screen is not built here. `BuildReviveV2` authors it from the Cartoony
	Kit's `PromptUI` onto the hidden `MainUIV2.Screens` shelf, and `_buildKit` clones that template
	into this file's own `RespawnScreen` ScreenGui, which keeps its name, its `DisplayOrder` under the
	race fade and everything else below. Every argument above still holds and every wire below is
	shared: the header is the question, the card holds the stake, the green button carries the price
	and the drain, and the pink one is the way out. What changes is only where the art comes from, and
	the handful of writes that differ are fenced on `self._panel`. See the notes, "Revive question".

	The flag off runs the shipping screen exactly as it was.

	=== AND WITH `NewUIConfig.WreckPanel`, IT IS THE WHOLE ENDING ==============================

	Aleafo's reference (2026-09-30): the question and the results screen after it were two screens
	for one moment, and the results one was too dark. So the kit panel grows into both. It clones
	`Screens.WreckRevive` instead of `Revive` and draws the run on the card (WRECKED or BUSTED, the
	ladder bar, what the run pays and keeps, the distance, the near-miss tally), the crashed car in the
	corner (`RaceUIController.buildWreckShot`), and a COUNTDOWN LINE under the panel in place of the
	drain. The figures are the server's preview of the settlement (`RewardService.previewRun`), on the
	offer itself.

	THREE WAYS OUT, AND DOING NOTHING IS NOW "AGAIN". REVIVE is unchanged. END RUN goes home and the
	results screen is skipped (`RaceConfig.WreckAnsweredEvent`, "home"). The countdown running out
	answers for the player: this side declines at zero rather than waiting out the server's grace, and
	`RaceUIController` holds the black and asks for the next race ("replay"). Not while a purchase
	prompt is open (`_accepted`), which the server is already holding the clock for.

	ONE GUARD ON THE "AGAIN". A player who has pressed nothing since the last automatic replay is
	sent home instead ("Heading home in"), so an empty chair cannot loop runs for ever.

=== AND WITH `NewUIConfig.EndPanel`, EVERY OTHER ENDING TOO ================================

Dylan (2026-10-01): the getaway, the bad landing, a fall, and a wreck or bust with no revive left all
went to the old dark results screen. They now get this panel, in its RESULTS MODE (`_ending` set,
"bank" or "wreck"): `RaceService.holdEndPanel` holds the return over the scene and sends
`RaceEndPanel`, the panel paints the SETTLED run (`RaceUIController.lastRun`), the buttons read HOME
and RACE AGAIN, and the same countdown races again. Except after a getaway, where home is the win:
there HOME wears the green and the countdown heads home (`SECONDARY_RAMP`). Every answer publishes the same
`WreckAnsweredEvent` and then tells the server (`RaceEndAnswer`), which runs the return. The corner is
`RaceUIController.buildEndShot`: the getaway car turning on its sunburst, the cruiser, the wreck, or
your ragdoll. While the tutorial is running the countdown goes home, because its next beat is there,
and in one arm of an A/B a getaway there offers HOME and nothing else (`TutorialConfig.RaceAgain`).

This client says it draws the panel (`RaceEndOptIn`) once the template is in hand; until then the
server ends runs the old way, with no wait.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local GamepadConfig = require(ReplicatedStorage.shared.Configs.GamepadConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local NearMissConfig = require(ReplicatedStorage.shared.Configs.NearMissConfig)
local NewUIConfig = require(ReplicatedStorage.shared.Configs.NewUIConfig)
local PoliceConfig = require(ReplicatedStorage.shared.Configs.PoliceConfig)
local RaceConfig = require(ReplicatedStorage.shared.Configs.RaceConfig)
local ReviveConfig = require(ReplicatedStorage.shared.Configs.ReviveConfig)
local RewardConfig = require(ReplicatedStorage.shared.Configs.RewardConfig)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local GamepadInput = require(ReplicatedStorage.shared.Modules.GamepadInput)
local LivePrice = require(ReplicatedStorage.shared.Modules.LivePrice)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)

local ReviveController = Shard.new("ReviveController")

--[[ === The controller's answer =============================================================

	A AND B, BOUND FOR THE LENGTH OF THE SCREEN, and both are also just the two buttons the mouse
	presses — the bindings call the same two functions the `Activated` handlers do, so there is one
	definition of what accepting is and the lock below guards all of it.

	NO SELECTION IS SEEDED HERE, deliberately, and it is the one screen in the game that does it this
	way. Everywhere else the highlight is the point (`Components/GamepadNav`); here there are two
	answers, they never move, and the clock is running — asking the player to drive a highlight onto
	one of them first is a step charged in seconds they can least afford. Binding the buttons
	outright is the same press with the step removed, which is also how a console game would have
	drawn it: A to accept, B to back out.

	Which is exactly why the screen raises `GamepadConfig.ModalAttribute` while it is up: B is the
	navigation component's back key the rest of the time, and the wreck window is not inside the
	"racing" span it stands down for (the driving HUD goes away on `RaceWrecked`). The attribute is
	what stops both of them owning the same button.

	ABOVE THE BAIL'S PRIORITY on purpose. `StealConfig.BindPriority` is High + 500 and takes ButtonA
	for the bail; a wreck should have torn that down, but this screen is a decision with money on it
	and it does not want to be the thing that finds out otherwise. ]]
local PAD_ACCEPT = "RevivePadAccept"
local PAD_DECLINE = "RevivePadDecline"
local PAD_PRIORITY = Enum.ContextActionPriority.High.Value + 600

--[[ === Look & feel =========================================================================

	EVERY SIZE AND POSITION IS A SCALE and every label is TextScaled, for the same reason
	`RaceUIController` is built that way: nothing here is authored in the place, so there is no PSD
	geometry to honour, and it has to read identically on a phone in portrait and on a 4K monitor. ]]

-- The kit, from `car ui.psd`. Only the two colours the text and the drain are drawn in are named
-- here now; the button's own colour arrives as art (see `PILL` below).
local PANEL_NAVY = Color3.fromRGB(40, 51, 75) -- #28334B, the kit's card face
local WHITE = Color3.fromRGB(255, 255, 255)
--[[ The crash colour, and it is deliberately the SAME amber `RaceUIController` pays a wreck out in.
	These are the two halves of one ending seen four seconds apart, and a player who declines should
	watch this screen's colour walk onto that one rather than meet a new palette. ]]
local CRASH_AMBER = Color3.fromRGB(240, 178, 74)

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

local SCRIM_COLOR = Color3.fromRGB(6, 8, 12)
local SCRIM_REST = 0.42 -- see the header: dark enough to read over, light enough to leave the car
local RAISE_TIME = 0.28 -- the screen coming up. Quick — the clock is already running.
local DROP_TIME = 0.22 -- ...and going away, quicker still, because something else follows it

--[[ === THE BUTTON IS THE KIT'S PILL ========================================================

	It was a hand-coloured `TextButton` until 2026-08-08, on the reasoning that the artist drew a
	shop and a dealership but never a wreck screen. That was half right: there is no wreck-screen
	MOCKUP, but the button shape this game presses everywhere else IS in the kit — `UIAssets.Pill`,
	one pill in seven colours with a real idle/hover/pressed set — and a screen asking for Robux is
	the last place to draw a lookalike of it by hand. Blue is the kit's action colour, the same one
	PLAY and the dealership's DONE wear.

	WHICH BRINGS THE STATES WITH IT. Hover and press are now `HoverImage`/`PressedImage`, swapped by
	the engine, so this file no longer owns what a press LOOKS like — note the pill's own state
	language in `UIAssets`: its pressed face is geometric (it drops 6px and loses 6px of height),
	NOT the opacity trick the navy panels use. The 3% scale dip stays on top of that, because it is
	the one thing the art cannot do: this is the one button in the game a player taps in a hurry, on
	a phone, with a countdown running, and it has to answer the finger before the server has
	answered anything.

	IT IS ASPECT-LOCKED, and that is the constraint the old box did not have. The art is 463x119
	(3.89:1); asked to fill the old 0.42x0.085 box it came out at 9:1, which reads as a smeared gloss
	between two cap curves scaled to the wrong height. So the WIDTH is authored and the height
	follows the art.

	AND BECAUSE IT IS ASPECT-LOCKED IT IS STRETCHED, NOT SLICED. It was sliced until 2026-08-16, on
	the reasoning that 9-slice is what protects a rounded corner — which is backwards for a box that
	only ever shrinks UNIFORMLY. Slice pins the corners at 1:1 texture pixels while the middle band
	takes all the shrink, so this button's 22px corner curve stayed ~19px on a 74px-tall render where
	the artist's proportion wants 14px, and the pill read as a lozenge. `Stretch` reproduces the
	drawing exactly. See `UIAssets.Slice.Pill`. ]]
local PILL = UIAssets.Pill.Blue
--[[ ...AND THE WAY OUT IS THE SAME PILL IN THE KIT'S RED.

	IT WAS SILVER TINTED TO NAVY UNTIL 2026-09-07, and that argument is worth keeping in full because
	it was right about the problem and wrong about the fix.

	The problem: silver's face is `#B9CAEC`, and every other pill in the game sits on a navy card
	while this one sits on a dark scrim over a lit road — so as drawn it came out the BRIGHTEST thing
	on the screen, brighter than the blue it is supposed to defer to. `ImageColor3` MULTIPLIES the
	texture, so a tint was solved for that landed the face on `#37455E`, the kit's own navy at its
	hover level, which also multiplied the kit's checker overlay down to about three units of swing.

	THE FIX IS WHAT FAILED, in the one way that matters on a screen asking for money: a desaturated
	fill at barely more luminance than the scrim behind it IS the disabled idiom. Every interface a
	player has ever used greys a control out to say it cannot be pressed. So the way out read as
	unavailable — which is worse than the brightness it was correcting, and is the same failure the
	bare-text version had before 2026-08-28. A screen that hides its decline is a screen that looks
	like it is hiding its decline, whichever way it was meant.

	SO THE ANSWER IS HUE, NOT VALUE. Red is fully saturated, so it cannot read as greyed out at any
	luminance, and it is WARM against a cool blue — the two can never blur into each other the way
	two blue-greys can. It is the artist's own drawn colour taken UNTINTED, which is how every other
	pill in this project is used and why there is no longer a tint constant here at all.

	THE ARGUMENT AGAINST RED, RECORDED because it is a real cost and not a strawman: ending a run is
	the ordinary way a run ends, not a destructive act, and red is the colour of destructive acts —
	so this button now asks for a beat of hesitation on the answer most players give most of the time.
	That was judged the cheaper mistake. A player who hesitates still has the clock and can still let
	it run out; a player who cannot tell the button is pressable is stuck on a screen with money on
	it. If playtesters do hesitate, `UIAssets.Pill.Orange` is the same shape one step down in urgency
	and the swap is this one line.

	THE HIERARCHY IS UNAFFECTED, which is the thing to check when reading this. It was never carried
	by the decline being DIM: the offer is a pill nearly twice the area, it holds the price and the
	drain, and it sits above rather than below. Red does not outrank any of that. ]]
local DECLINE_PILL = UIAssets.Pill.Red
local PILL_TEXTURE = UIAssets.Size.Pill -- 463x119, the STORED texture; the aspect comes out of it
local PILL_ASPECT = PILL_TEXTURE.X / PILL_TEXTURE.Y

local function pillAsset(id: number): string
	return "rbxassetid://" .. id
end

--[[ The layout, top to bottom. It sits in the LOWER half of the screen on purpose: the wrecked car
	is in the middle of the frame with the camera behind it, and a decision drawn over the top of it
	would be a decision with a car behind every letter.

	NONE OF IT IS A HAND-PICKED Y ANY MORE. Both answers are pills now, a pill takes its height from
	the art's aspect, and that aspect is answered against the SCREEN's: so the two buttons grow
	together as a viewport gets wider. A column of fixed Y values tuned at 16:9 had them touching at
	21:9. `_layout` works the whole column out from the numbers in this block instead, once per
	viewport size, and at 16:9 it lands within a percent of the geometry this screen shipped with.

	THE BLOCK HANGS FROM ITS BOTTOM EDGE. The pair of buttons is what the player is aiming at, so it
	is what gets pinned to a known place; the question and the stake are then stood on top of it.
	Growing upward is what keeps the lower button off the bottom of the screen on every aspect, which
	is the edge a thumb cannot reach past. ]]
local STACK_BOTTOM = 0.895 -- the underside of the lower button, in screen scale

--[[ EACH PILL IS AUTHORED AS A HEIGHT, WITH A WIDTH IT MAY NOT EXCEED, and `_layout` takes
	whichever of the two comes out smaller.

	THE HEIGHT IS THE HONEST CONSTANT of the two. It is what makes a button the same physical size to
	a thumb whatever screen the thumb is on, and it is what stops a wider window being answered with
	a wider button: at 21:9 an authored WIDTH would have drawn the offer nearly a metre across a
	desk. The cap is the other end of the range and only the other end. A phone held upright is
	narrow enough that the width a height implies would run off both sides of it, so below about 6:5
	the cap binds and the pills get shorter instead. Everywhere this game is actually played, the
	height is what wins.

	The heights are a fraction of screen HEIGHT, the caps a fraction of screen WIDTH. ]]
local BUTTON_HEIGHT = 0.155
local BUTTON_WIDTH_MAX = 0.5
--[[ The way out, at a little under three fifths of the offer, and the cap is the same fraction so
	the pair stays in proportion at the narrow end too. That ratio IS the hierarchy, together with the
	colour: unmistakably a button, unmistakably the smaller of the two.

	IT WAS TWO THIRDS UNTIL 2026-09-07 and read as oversized, which is worth separating from the
	reason it did: a 266px pill holding a 100px word is not a big button, it is an EMPTY one, and the
	fix is two-part. This end of it takes the pill down to where the pair reads as primary and
	secondary at a glance; `DECLINE_CAPTION_SIZE` fills what is left. Shrinking alone would have made
	a smaller empty pill. ]]
local DECLINE_HEIGHT = 0.088
local DECLINE_WIDTH_MAX = 0.284
--[[ Between them, as a fraction of the SMALLER pill, so the gap grows with what it separates.

	IT IS DELIBERATELY LESS THAN HALF OF `HEADLINE_GAP` MEASURES OUT TO, and that ratio is the only
	thing on this screen that says the two pills are one thing. It was not: both gaps landed on the
	same 31px at 16:9, so the column read as three evenly spaced strips — stake-and-question, offer,
	way out — rather than as a question with a pair of answers under it. Even spacing is what a list
	looks like, and this screen is not a list; it is one decision with two ends. Tightening the pair
	and standing the question further off it is the whole of the grouping. ]]
local BUTTON_GAP = 0.34
--[[ ...WITH A FLOOR IN SCREEN SCALE, because the fraction above is a fraction of a pill that does
	not keep its height everywhere. Past the `pillSize` crossover (about 6:5) the width cap binds and
	both pills get SHORTER, so a gap measured off the smaller one collapses with it: at 9:19 portrait
	it came out at ten pixels between two tap targets. Mis-tap risk is an ABSOLUTE distance on a
	screen, not a proportion of the thing being tapped, and the one screen in this game that charges
	Robux for a press is the last place to let two answers sit a thumb's width apart.

	The floor is set to bind only below square — every landscape device, which is everywhere this
	game is actually played, takes the proportional gap untouched. ]]
local BUTTON_GAP_MIN = 0.024 -- of screen height

--[[ THE HEADLINE IS THE BIGGEST LINE ON THE SCREEN, which sounds like it goes without saying and
	did not hold: at 0.062 it came out at font 42 against a REVIVE caption that `TextScaled` also
	solved to 42, so the question and the answer were set in the SAME size and the question lost —
	it is white on a scrim, the caption is white on a saturated blue. A screen whose whole argument
	is that it ASKS something (see the header) cannot have its question tie with a button label.

	Both ends moved, because closing a tie by growing one side alone would have pushed the block into
	the wrecked car: the headline goes up about a fifth and `CAPTION_SIZE` comes down about a tenth,
	which lands them at roughly 4:3 and leaves the column the height it already had.

	The stake goes up with it, by the same proportion, so the text group keeps its own internal
	ranking rather than the distance shrinking away under a bigger question. ]]
local STAKE_SIZE = UDim2.fromScale(0.5, 0.033)
local HEADLINE_SIZE = UDim2.fromScale(0.8, 0.074)
-- Stood off the block's top edge, and off each other, in screen scale. See `BUTTON_GAP` for why
-- this one is the LOOSE gap of the two: it is what separates the question from the answers.
local HEADLINE_GAP = 0.058
local STAKE_GAP = 0.025

--[[ A 16:9 starting size for each pill, so the screen is never wrong even for the frame before
	`_layout` first runs. Both axes of both are overwritten there. ]]
local BUTTON_SIZE = UDim2.fromScale(BUTTON_WIDTH_MAX, BUTTON_HEIGHT)
local DECLINE_SIZE = UDim2.fromScale(DECLINE_WIDTH_MAX, DECLINE_HEIGHT)

local CAPTION_SIZE = UDim2.fromScale(0.84, 0.355) -- of the button, inside the art's own margins
local CAPTION_Y = 0.44 -- the pill's face is not its centre: it has a lip along the bottom
--[[ A LARGER FRACTION OF ITS PILL THAN THE OFFER'S CAPTION IS OF ITS OWN, which is the opposite of
	what this constant used to say and is not a change of mind about the hierarchy.

	The pill is 3.89:1 whatever size it is drawn at (`PILL_ASPECT`), and the two captions are not the
	same LENGTH: "REVIVE   R$25" is thirteen characters and filled 63% of the offer's width, while
	"END RUN" is seven and filled 38% of its own. Same fraction of height, wildly different fraction
	of width — so the way out read as a slab with a word rattling around inside it, which is what
	made it look oversized even though it was already the smaller of the two.

	So the fraction is solved for the FILL rather than copied from the offer, and the three signals
	that actually carry the hierarchy do the work they always did: the pill is smaller, the type is
	smaller in absolute terms (about seven tenths of the offer's), and the face is navy under a
	saturated blue. None of those is weakened by the word inside it sitting properly. ]]
local DECLINE_CAPTION_SIZE = UDim2.fromScale(0.72, 0.44)

local PRESS_SCALE = 0.97

--[[ The hover nudge `Components/Button` puts on every tagged button, tuned down from its 1.05
	default for the reason that file gives: the art already carries a hover of its own, and two
	full-strength reactions to one hover reads as the UI flinching. Both answers take about the same
	amount now that both wear the same art; the smaller one takes a touch more so the nudge is worth
	the same number of pixels on screen. ]]
local BUTTON_HOVER_SCALE = 1.03
local DECLINE_HOVER_SCALE = 1.04

--[[ The drain. A strip along the bottom of the button's FACE whose WIDTH is the fraction of the
	offer left — see the header on why there is no number beside it.

	IT IS INSET RATHER THAN CLIPPED. The old face was a rectangle with a `UICorner`, so the bar could
	run the full width and let the corner cut its square ends off. The art's rounded caps are pixels,
	not geometry — `ClipsDescendants` clips to the rect and would leave the bar's end poking over the
	curve — so the lane stops short of them instead, and the button no longer clips anything. ]]
local DRAIN_WIDTH = 0.78 -- of the button, centred: clear of both cap curves
local DRAIN_HEIGHT = 0.075
local DRAIN_Y = 0.755 -- on the face, above the lip the pressed art drops into
local DRAIN_REST = 0.25
--[[ Under this fraction remaining the drain goes amber and the button breathes, which is the whole
	of the urgency treatment. A fifth of eight seconds is about a second and a half — long enough to
	still act on, short enough that the change means something. ]]
local URGENT_AT = 0.2
local URGENT_PULSE = 2.6 -- Hz of the breath
--[[ THE BREATH IS THE KIT'S OWN HOVER, CROSS-FADED IN. The face used to breathe on opacity, which
	is the navy panels' state language and expressly not the pill's — a pill fading toward the scrim
	is a pill going away, the opposite of what urgency should say. So the lit frame is the artist's
	`Hover` image, which is the same crop recoloured (`UIAssets.Pill`: "the geometry is
	byte-identical to idle, the swap cannot jitter"), laid over the idle one at an animated
	transparency. The button gets BRIGHTER as the clock runs out, and it does it in a colour the
	artist already chose. ]]
local URGENT_LIT = 0.85 -- how far the breath gets toward the lit face; never quite all of it

local NBSP = utf8.char(0xA0) -- TextScaled wraps rather than shrinks; see RaceUIController's note

--[[ Where the two glyphs sit: beside their answer, on the scrim rather than inside the thing they
	describe, because a badge parented to a button would ride that button's press dip and hover swell
	and read as part of the face. This is the gap between a pill's own left edge and its badge, and
	`_layout` is what turns it into a position, off the same measurement it sizes the pills with.

	Both are measured the same way now. They were not while END RUN was a line of text: its x had to
	be guessed against the WORDS, because the box around them was a bare target several times wider
	than anything visible in it. A pill has an edge you can point at. ]]
local ICON_GAP = 0.02

--[[ === The kit panel (the new UI) ==========================================================

	Only read with `UIRoot.isNewUI()`. The geometry is the template's (`BuildReviveV2`); these are
	the few things the template cannot hold because they move. ]]

-- Where the template lives, and how long to wait for it. `MainUIV2` arrives with the character
-- rather than with this script, so the wait is real, and a place that never ran the build command
-- falls back to the shipping screen with a warning rather than losing the offer.
local KIT_SHELF = "Screens"
local KIT_TEMPLATE = "Revive"
local KIT_WAIT = 10

--[[ The panel's entrance and exit, which are the kit pages' own (`UIController`'s open and close
	tweens): a small swell from nine tenths on the way in, a quick settle back to it on the way out.
	The scrim still fades on `RAISE_TIME` and `DROP_TIME`, so the two answers are pressable exactly
	when they were. ]]
local KIT_START_SCALE = 0.9

--[[ The urgency colour on the kit's green face is the kit's own RED, the far end of the way out's
	gradient. The shipping amber is a warm yellow on a blue pill; on a yellow-to-green button it is
	barely a change at all. ]]
local KIT_URGENT = Color3.fromRGB(217, 8, 12)
--- How much of the white wash the breath reaches. The green face is already bright, so a little is a lot.
local KIT_LIT_SHARE = 0.35

--[[ The badges sit on each button's OUTER top corner, hung off the slot, so neither overlaps the
	neighbouring button and neither rides the hover swell (that is the button's own `UIScale`). ]]
local KIT_ACCEPT_ICON_AT = UDim2.fromScale(1, 0)
local KIT_ACCEPT_ICON_ANCHOR = Vector2.new(0.65, 0.35)
local KIT_DECLINE_ICON_AT = UDim2.fromScale(0, 0)
local KIT_DECLINE_ICON_ANCHOR = Vector2.new(0.35, 0.35)

-- The kit's own Robux mark, from the private use area; see the notes, "Shop".
local ROBUX = utf8.char(0xE002)

--[[ What the card says when there is no distance worth naming. The shipping screen draws nothing
	there, which on a white card is a hole above the buttons; this names the offer instead, and never
	names the wreck (see the header: the screen ASKS). ]]
local KIT_NO_STAKE = "Back" .. NBSP .. "on" .. NBSP .. "the" .. NBSP .. "road" .. NBSP .. "in" .. NBSP .. "the" .. NBSP .. "same" .. NBSP .. "car"

--[[ === The one-screen wreck (`NewUIConfig.WreckPanel`) ======================================

	See the header. Every geometry is the template's (`BuildReviveV2`, `WreckRevive`); these are the
	words, the colours the controller writes, and the timings of the two things that move. ]]
local WRECK_TEMPLATE = "WreckRevive"
local WRECK_HEADLINE = "WRECKED"
local DOT = NBSP .. NBSP .. "·" .. NBSP .. NBSP
--- The heat bonus's stamp on the getaway's payout line (`_stampHeat`). `%s` is the multiplier.
local HEAT_STAMP = {
	text = "★" .. NBSP .. "HEAT" .. NBSP .. "x%s",
	colour = Color3.fromRGB(235, 60, 60),
	ink = Color3.fromRGB(70, 0, 0),
	rotation = -8,
	from = 2.6, -- its size before it lands, as a scale of its resting size
	stampTime = 0.16,
	delay = 0.3, -- after the first count lands, before the stamp
	countTime = 0.6, -- the climb from the run's figure to the paid one
}
--- The countdown line, by what running out will do. `%d` is whole seconds left, never below 1.
local COUNT_REPLAY = "Racing" .. NBSP .. "again" .. NBSP .. "in" .. NBSP .. "%d"
local COUNT_HOME = "Heading" .. NBSP .. "home" .. NBSP .. "in" .. NBSP .. "%d"
--[[ Lighter than the question's own scrim. The panel now fills the middle of the screen and carries
	the car itself, so the road behind only has to read as a road; the old results screen was turned
	down for being too dark, and this is the screen that replaces it. ]]
local WRECK_SCRIM = 0.72
--- The bar drives out and the money counts up on one clock, a beat after the panel lands.
local LADDER_DELAY = 0.15
local LADDER_TIME = 0.7
--- Rungs the run reached are gold, the rest the track's slate lifted a step so they read on it.
local RUNG_REACHED = Color3.fromRGB(255, 203, 31)
local RUNG_AHEAD = Color3.fromRGB(150, 156, 172)
local RUNG_WIDTH = 0.006 -- of the bar
local RUNG_HEIGHT = 1.9 -- of the track, so they stand proud of it like the reference's
--- The bonus figure inside the pale strip. Darker than the card's gold, which is lost on a pale fill.
local STRIP_BONUS = "#D98E00"
--- What the crashed car's shot is composited against: the header's blue, which is behind it.
local SHOT_BACKDROP = Color3.fromRGB(57, 146, 254)
--[[ ...and its smoke: the results screen's own plume (Dylan, 2026-09-30: the cartoon discs were too
	cartoony), re-pitched for a bright ground. A mid grey rather than that screen's light one, weighted
	up per puff and each puff stacked five deep, because the texture is soft enough to vanish over a lit
	sky (`RaceUIController.buildWreckShot`). Chosen by eye in a held wreck. ]]
local SHOT_SMOKE = Color3.fromRGB(150, 154, 164)
local SHOT_SMOKE_STRENGTH = 2.4
local SHOT_SMOKE_LAYERS = 5
--[[ The end panel's words (`NewUIConfig.EndPanel`). The template is authored with the revive's
	(KEEP GOING?, REVIVE, END RUN), so `_paint` writes both sets every time: the two modes share one
	panel and neither may inherit the other's. ]]
local KEEP_GOING = "KEEP" .. NBSP .. "GOING?"
local END_RUN = "END" .. NBSP .. "RUN"
local END_HEADERS = { bank = "GOT" .. NBSP .. "AWAY!", wreck = "RUN" .. NBSP .. "OVER" }
local BANK_HEADLINE = "STOLEN!"
local BAIL_HEADLINE = "WIPED" .. NBSP .. "OUT" -- a bad landing: you, face down on the tarmac
local AGAIN_CAPTION = "RACE" .. NBSP .. "AGAIN"
local HOME_CAPTION = "HOME"
--[[ ON A GETAWAY, HOME IS THE WIN (Dylan, 2026-10-01). The template paints RACE AGAIN in the kit's
	green and HOME in its red, which is right after a wreck, where going home is the giving-up answer.
	After a getaway it read as "oh no, I lost" on the button you came for: you got your car, and home is
	where it is going. So a bank swaps the faces: HOME takes the green, and RACE AGAIN takes the kit's
	blue secondary ramp (the sell screen's NO button, `Screens.SellCar.Main.Btns.NoBtn`), still friendly
	but plainly the second choice. The countdown goes home too (see `_show`). A wreck keeps the template's. ]]
local SECONDARY_RAMP = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(59, 235, 255)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(57, 146, 254)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(19, 93, 253)),
})
local NO_TALLY = "No" .. NBSP .. "near" .. NBSP .. "misses" .. NBSP .. "this" .. NBSP .. "run"
--- The level-up on the distance row, in the card's gold.
local LEVEL_COLOR = "#FFCB1F"
--[[ The getaway's background blur (Dylan, 2026-10-01): a little, so the truck driving off behind the
	panel still reads as a truck (`GetawayConfig.ExitShot` is the camera on it). A BlurEffect under the
	camera, which touches the world and never the UI. ]]
local GETAWAY_BLUR = 12
local BLUR_IN = 0.6
--- How many frames to wait on `RunSettled` if the panel's own message beats it here.
local SUMMARY_WAIT_FRAMES = 30

--- Input that counts as "somebody is here" for the replay guard. Movement and focus do not.
local IDLE_INPUTS = {
	[Enum.UserInputType.MouseMovement] = true,
	[Enum.UserInputType.MouseWheel] = true,
	[Enum.UserInputType.Focus] = true,
	[Enum.UserInputType.None] = true,
}

function ReviveController._build(self)
	local gui = Instance.new("ScreenGui")
	gui.Name = "RespawnScreen"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	--[[ UNDER `RaceTransition`'s 1000, deliberately. Declining fires the return fade a beat later and
		that fade has to come down OVER this screen, not behind it — the whole point of the fade is
		that the teleport home happens unseen, and a respawn screen still fading out in front of it
		would be a hole in the curtain. ]]
	gui.DisplayOrder = 999
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	local scrim = Instance.new("Frame")
	scrim.Name = "Scrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = SCRIM_COLOR
	scrim.BackgroundTransparency = 1
	scrim.BorderSizePixel = 0
	scrim.Parent = gui

	--[[ The new UI clones its panel here instead of building one, and stops. With no template in
		the place it warns and carries on below, because a question with money on it that is never
		asked is worse than one asked in the old art. ]]
	if UIRoot.isNewUI() then
		local template = self._kitSource
		if template and self:_buildKit(gui, scrim, template) then
			return
		end
		self.log:warn("No MainUIV2.Screens.Revive to clone; the revive question is drawn in the old art. Run BuildReviveV2.")
	end

	local stake = Instance.new("TextLabel")
	stake.Name = "Stake"
	stake.AnchorPoint = Vector2.new(0.5, 0.5)
	stake.Size = STAKE_SIZE -- the Y of both this and the headline is `_layout`'s
	stake.BackgroundTransparency = 1
	stake.FontFace = FONT
	stake.Text = ""
	stake.TextColor3 = CRASH_AMBER
	stake.TextTransparency = 1
	stake.TextScaled = true
	stake.Parent = scrim

	local headline = Instance.new("TextLabel")
	headline.Name = "Headline"
	headline.AnchorPoint = Vector2.new(0.5, 0.5)
	headline.Size = HEADLINE_SIZE
	headline.BackgroundTransparency = 1
	headline.FontFace = FONT
	headline.Text = "KEEP" .. NBSP .. "GOING?"
	headline.TextColor3 = WHITE
	headline.TextTransparency = 1
	headline.TextScaled = true
	headline.Parent = scrim

	--[[ THE OFFER. See the header block on `PILL`: it is the kit's own pill, stretched rather than
		sliced, and the two other faces of it are handed to the engine to swap rather than driven from
		here. Its shape now comes from `_layout` instead of from an aspect constraint.

		EACH ANSWER IS A SLOT WITH A BUTTON IN IT, and the extra Frame is not decoration.

		Only ONE `UIScale` on an instance takes effect (`Components/Button` measured it and says so at
		the `HoverScale` block). This screen's press dip was a UIScale on the button itself, which spoke
		for that channel, so the tag fell back to its old path and tweened the button's `Size` on hover
		off a copy it took when the tag landed. That was harmless while the size was authored once and
		never touched. It stopped being harmless the moment `_layout` started rewriting the size on
		every viewport change: the first hover after a resize would have snapped the button back to the
		size it had before it.

		So the two reactions get a channel each. The SLOT holds the position, the size and the press
		dip; the BUTTON fills it at 1x1 and keeps its own scale channel free, which is the one the tag
		claims. They multiply rather than fight, and `_layout` owns the size outright.

		The Frame is inert: transparent, and `Active` left false so it consumes no input on its way
		through to the button. ]]
	local buttonSlot = Instance.new("Frame")
	buttonSlot.Name = "ReviveSlot"
	buttonSlot.AnchorPoint = Vector2.new(0.5, 0.5)
	buttonSlot.Size = BUTTON_SIZE -- ...until `_layout` runs, which owns both axes and the Y
	buttonSlot.BackgroundTransparency = 1
	buttonSlot.BorderSizePixel = 0
	buttonSlot.Parent = scrim

	local button = Instance.new("ImageButton")
	button.Name = "Revive"
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.5)
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.AutoButtonColor = false -- the art is the press; Roblox's automatic darkening is not
	button.Image = pillAsset(PILL.Idle)
	button.HoverImage = pillAsset(PILL.Hover)
	button.PressedImage = pillAsset(PILL.Pressed)
	button.ImageTransparency = 1
	button.ScaleType = Enum.ScaleType.Stretch
	button.Parent = buttonSlot

	--[[ The press dip, on the slot rather than on `Size`: `Size` belongs to `_layout` now, and a
		press that wrote it would be a press that had to put the layout back afterwards. Scaling leaves
		the laid-out size the single source of truth, so a press interrupted by the screen coming down
		has nothing to restore. See the slot's own block above for why it is not on the button. ]]
	local scale = Instance.new("UIScale")
	scale.Parent = buttonSlot

	--[[ The urgency breath, dark until the last fifth of the clock — see `URGENT_LIT`. It is the same
		image drawn the same way at the same size, so it lands exactly on top of the idle face;
		`Active` is left false so every press falls straight through it to the button. ]]
	local lit = Instance.new("ImageLabel")
	lit.Name = "Lit"
	lit.Size = UDim2.fromScale(1, 1)
	lit.BackgroundTransparency = 1
	lit.Image = pillAsset(PILL.Hover)
	lit.ImageTransparency = 1
	lit.ScaleType = Enum.ScaleType.Stretch
	lit.ZIndex = 1
	lit.Parent = button

	--[[ The caption is its own label rather than the button's `Text`, because the button is now an
		image and its text would sit under the lit frame above. ]]
	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.AnchorPoint = Vector2.new(0.5, 0.5)
	caption.Position = UDim2.fromScale(0.5, CAPTION_Y)
	caption.Size = CAPTION_SIZE
	caption.BackgroundTransparency = 1
	caption.FontFace = FONT
	caption.Text = ""
	caption.TextColor3 = WHITE
	caption.TextTransparency = 1
	caption.TextScaled = true
	caption.ZIndex = 2
	caption.Parent = button

	local drainTrack = Instance.new("Frame")
	drainTrack.Name = "DrainTrack"
	drainTrack.AnchorPoint = Vector2.new(0.5, 0.5)
	drainTrack.Position = UDim2.fromScale(0.5, DRAIN_Y)
	drainTrack.Size = UDim2.fromScale(DRAIN_WIDTH, DRAIN_HEIGHT)
	drainTrack.BackgroundColor3 = PANEL_NAVY
	drainTrack.BackgroundTransparency = 1
	drainTrack.BorderSizePixel = 0
	drainTrack.ZIndex = 2
	drainTrack.Parent = button

	-- Anchored to the LEFT end rather than centred: time runs out from one side, and a bar closing
	-- in from both ends reads as a thing being loaded rather than a thing being lost.
	local drain = Instance.new("Frame")
	drain.Name = "Drain"
	drain.AnchorPoint = Vector2.new(0, 0.5)
	drain.Position = UDim2.fromScale(0, 0.5)
	drain.Size = UDim2.fromScale(1, 1)
	drain.BackgroundColor3 = WHITE
	drain.BackgroundTransparency = 1
	drain.BorderSizePixel = 0
	drain.Parent = drainTrack

	--[[ "END RUN", AND IT IS A BUTTON.

		It was a line of text on a transparent target until 2026-08-28, on the reasoning that one of
		these two answers is the offer and the other is the way out of it, and drawing them as equals
		would make the player choose between two buttons instead of answering a question. The reasoning
		holds; the drawing did not. Dim white words with no face under them, over a lit road, with a
		clock running, do not read as a control at all. They read as a caption, and the one thing a
		player must never have to hunt for on a screen that is asking them for money is the way to say
		no. A screen that hides its decline is a screen that looks like it is hiding its decline,
		whichever way it was meant.

		So the asymmetry stays and moves into the vocabulary the kit already has for it: SIZE and HUE,
		not presence. The same pill at a little under three fifths of the height, in the kit's red beside
		a saturated blue. The offer is still obviously the loud one — it is nearly twice the area and it
		is the one carrying a price and a clock. The way out is now obviously pressable, which is the
		only thing this half has to achieve. `DECLINE_PILL` has the colour argument, which is its own
		decision and a longer one.

		One instance, not the old two: the pill IS the target, so there is no longer a box to keep
		apart from the word inside it. The caption is a child only because the pressed art moves and
		the text should not go with it. ]]
	local declineSlot = Instance.new("Frame")
	declineSlot.Name = "DeclineSlot"
	declineSlot.AnchorPoint = Vector2.new(0.5, 0.5)
	declineSlot.Size = DECLINE_SIZE
	declineSlot.BackgroundTransparency = 1
	declineSlot.BorderSizePixel = 0
	declineSlot.Parent = scrim

	local decline = Instance.new("ImageButton")
	decline.Name = "Decline"
	decline.AnchorPoint = Vector2.new(0.5, 0.5)
	decline.Position = UDim2.fromScale(0.5, 0.5)
	decline.Size = UDim2.fromScale(1, 1)
	decline.BackgroundTransparency = 1
	decline.BorderSizePixel = 0
	decline.AutoButtonColor = false
	decline.Image = pillAsset(DECLINE_PILL.Idle)
	decline.HoverImage = pillAsset(DECLINE_PILL.Hover)
	decline.PressedImage = pillAsset(DECLINE_PILL.Pressed)
	decline.ImageTransparency = 1
	decline.ScaleType = Enum.ScaleType.Stretch
	decline.Parent = declineSlot

	-- Its own slot and its own dip, for the same reasons the offer has them.
	local declineScale = Instance.new("UIScale")
	declineScale.Parent = declineSlot

	local declineLabel = Instance.new("TextLabel")
	declineLabel.Name = "Label"
	declineLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	declineLabel.Position = UDim2.fromScale(0.5, CAPTION_Y)
	declineLabel.Size = DECLINE_CAPTION_SIZE
	declineLabel.BackgroundTransparency = 1
	declineLabel.FontFace = FONT
	declineLabel.Text = "END" .. NBSP .. "RUN"
	declineLabel.TextColor3 = WHITE
	declineLabel.TextTransparency = 1
	declineLabel.TextScaled = true
	declineLabel.Parent = decline

	self._gui = gui
	self._scrim = scrim
	self._stake = stake
	self._headline = headline
	self._button = button
	self._buttonSlot = buttonSlot
	self._buttonScale = scale
	self._lit = lit
	--[[ `_captionLabel`, NOT `_caption` — `_caption` is the method three screens down that works out
		what this label should say, and parking an instance on that name would shadow it exactly the
		way `_decline` shadows its own (see `_pressDecline`). Same trap, same file, second time. ]]
	self._captionLabel = caption
	self._drain = drain
	self._drainTrack = drainTrack
	self._decline = decline
	self._declineSlot = declineSlot
	self._declineScale = declineScale
	self._declineLabel = declineLabel

	--[[ === BOTH ANSWERS ARE `UIButton`s ======================================================

		Which is how every other pressable thing in this game is declared (`Components/Button`), and
		it is the tag rather than this file that then owns the hover nudge, the hover sound and the
		click sound — including the ones that do not exist yet, since `SoundController` no-ops on a
		group with no sounds in it and starts working the day somebody drops one in.

		THE TAG BRINGS NO BEHAVIOUR WITH IT HERE, deliberately: neither button carries a `Page` or an
		`Action` attribute, so a press through `ButtonPress` plays its sound and does nothing else.
		What accepting and declining MEAN stays in this file, on the `Activated` wires below, because
		both are answers to an offer that is still open — a state the UI layer knows nothing about.

		It also does not hand this screen to `Components/GamepadNav`: that only ever looks inside
		`MainUI`, and this is its own ScreenGui. The A and B bindings below remain the whole of the
		controller story here, which is what `GamepadConfig.ModalAttribute` is raised to protect. ]]
	button:SetAttribute("Scale", BUTTON_HOVER_SCALE)
	decline:SetAttribute("Scale", DECLINE_HOVER_SCALE)

	self:_wire()

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui.Parent = playerGui

	--[[ AFTER THE PARENTING, because that is when the ScreenGui first has a size to measure. A phone
		rotated, a window dragged wider or a device emulator switched mid-playtest all arrive here as a
		change to that size, and every one of them changes where the two buttons belong. ]]
	self:_layout()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_layout()
	end)

	-- LAST, and after the parenting: the component reads the button's authored `Size` the moment the
	-- tag lands and tweens the hover off it, so the tag goes on once everything it measures is final.
	CollectionService:AddTag(button, "UIButton")
	CollectionService:AddTag(decline, "UIButton")
end

--[[ === THE KIT PANEL ======================================================================

	`_awaitKit` finds the template and `_buildKit` stands it in the ScreenGui `_build` has just made.

	THE WAIT IS SEPARATE FROM THE BUILD, AND SPAWNED, because `MainUIV2` is a StarterGui clone that
	arrives with the character while this controller starts before it, and `Shard.start` is the
	client's boot barrier. Every step of it is bounded and the miss is named in a warning. ]]
function ReviveController._awaitKit(self)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", KIT_WAIT)
	local root = playerGui and UIRoot.wait(playerGui :: PlayerGui, KIT_WAIT)
	local shelf = root and root:WaitForChild(KIT_SHELF, KIT_WAIT)
	--[[ The one-screen wreck first, when it is switched on. A place that has not re-run
		`BuildReviveV2` since it grew the second template falls back to the plain question, with a
		warning, rather than losing the offer. ]]
	if shelf and NewUIConfig.WreckPanel then
		local wreck = shelf:WaitForChild(WRECK_TEMPLATE, KIT_WAIT)
		if wreck and wreck:IsA("GuiObject") then
			self._kitSource = wreck
			return
		end
		self.log:warn(string.format("No MainUIV2.%s.%s; the wreck falls back to the plain revive question. Run BuildReviveV2.", KIT_SHELF, WRECK_TEMPLATE))
	end
	local template = shelf and shelf:WaitForChild(KIT_TEMPLATE, KIT_WAIT)
	if not (template and template:IsA("GuiObject")) then
		self.log:warn(
			string.format(
				"Waited %ds for MainUIV2.%s.%s and it did not arrive; the revive question falls back to the old art.",
				KIT_WAIT,
				KIT_SHELF,
				KIT_TEMPLATE
			)
		)
		return
	end
	self._kitSource = template
end

--[[ Clone the template in and bind the same fields `_build` binds, so every method below this one
	works on either screen. Answers false, having left nothing behind, if the template is not the
	shape `BuildReviveV2` makes.

	THE SCRIM IS `Active` HERE AND WAS NOT IN THE SHIPPING SCREEN. A white panel over a lit HUD reads
	as a dialog, and a dialog whose background can still be clicked is a trap: the Phase 4 contract
	asks for it on every screen. It changes nothing during a race, where the HUD is already down. ]]
function ReviveController._buildKit(self, gui: ScreenGui, scrim: Frame, template: GuiObject): boolean
	local panel = template:Clone()
	--- The kit's text caps are pixels for a 1080-tall screen; this keeps them in proportion above it.
	require(script.Parent.UIController.KitPage).scaleTextCaps(panel)
	local main = panel:FindFirstChild("Main")
	local header = panel:FindFirstChild("Header")
	-- On the card in `Revive`, on the blue under it in `WreckRevive`.
	local btns = panel:FindFirstChild("Btns") or (main and main:FindFirstChild("Btns"))
	local buttonSlot = btns and btns:FindFirstChild("ReviveSlot")
	local declineSlot = btns and btns:FindFirstChild("DeclineSlot")
	local button = buttonSlot and buttonSlot:FindFirstChild("Revive")
	local decline = declineSlot and declineSlot:FindFirstChild("Decline")
	local drainTrack = button and button:FindFirstChild("DrainTrack")
	local found = {
		stake = main and main:FindFirstChild("Stake"),
		headline = header and header:FindFirstChild("Title"),
		lit = button and button:FindFirstChild("Lit"),
		caption = button and button:FindFirstChild("Caption"),
		drain = drainTrack and drainTrack:FindFirstChild("Drain"),
		declineLabel = decline and decline:FindFirstChild("Label"),
	}
	-- By a list of names rather than over the table: a lookup that came back nil is not a key in it.
	for _, name in { "stake", "headline", "lit", "caption", "drain", "declineLabel" } do
		if not found[name] then
			self.log:warn(string.format("MainUIV2.%s.%s has no `%s`. Re-run BuildReviveV2.", KIT_SHELF, KIT_TEMPLATE, name))
			panel:Destroy()
			return false
		end
	end
	if not (button and button:IsA("GuiButton") and decline and decline:IsA("GuiButton")) then
		self.log:warn(string.format("MainUIV2.%s.%s has no Revive and Decline buttons. Re-run BuildReviveV2.", KIT_SHELF, KIT_TEMPLATE))
		panel:Destroy()
		return false
	end

	--[[ The one-screen wreck's extra rows. All or nothing: a template missing one of them is drawn as
		the plain question, which still has everything it needs. ]]
	if panel.Name == WRECK_TEMPLATE then
		local ladder = main and main:FindFirstChild("Ladder")
		local track = ladder and ladder:FindFirstChild("Track")
		local strip = main and main:FindFirstChild("Strip")
		local rows = {
			headline = main and main:FindFirstChild("Headline"),
			cash = main and main:FindFirstChild("Cash"),
			ladder = ladder,
			fill = track and track:FindFirstChild("Fill"),
			ticks = ladder and ladder:FindFirstChild("Ticks"),
			marker = ladder and ladder:FindFirstChild("Marker"),
			strip = strip,
			stripText = strip and strip:FindFirstChild("Text"),
			carSlot = panel:FindFirstChild("CarSlot"),
			countdown = panel:FindFirstChild("Countdown"),
		}
		local whole = true
		for _, name in { "headline", "cash", "ladder", "fill", "ticks", "marker", "strip", "stripText", "carSlot", "countdown" } do
			if not rows[name] then
				whole = false
				self.log:warn(string.format("MainUIV2.%s.%s has no `%s`; drawn as the plain question. Re-run BuildReviveV2.", KIT_SHELF, WRECK_TEMPLATE, name))
				break
			end
		end
		self._wreck = if whole then rows else nil
		-- The end panel's level-up rides on the distance row in gold.
		if whole and found.stake:IsA("TextLabel") then
			found.stake.RichText = true
		end
	end

	scrim.Active = true
	panel.Visible = false -- `_show` raises it
	panel.Parent = scrim

	local panelScale = Instance.new("UIScale")
	panelScale.Name = "OpenScale"
	panelScale.Scale = KIT_START_SCALE
	panelScale.Parent = panel

	-- The press dips, one per slot, for the reason `BuildReviveV2` gives for the slots.
	local scale = Instance.new("UIScale")
	scale.Parent = buttonSlot
	local declineScale = Instance.new("UIScale")
	declineScale.Parent = declineSlot

	self._gui = gui
	self._scrim = scrim
	self._panel = panel
	self._panelScale = panelScale
	self._stake = found.stake
	self._headline = found.headline
	self._button = button
	self._buttonSlot = buttonSlot
	self._buttonScale = scale
	self._lit = found.lit
	self._captionLabel = found.caption -- see `_build` on why not `_caption`
	self._drain = found.drain
	self._drainTrack = drainTrack
	self._decline = decline
	self._declineSlot = declineSlot
	self._declineScale = declineScale
	self._declineLabel = found.declineLabel
	-- The two faces as authored, so a getaway can swap them and the next wreck can put them back.
	self._acceptRamp = button:FindFirstChildOfClass("UIGradient")
	self._declineRamp = decline:FindFirstChildOfClass("UIGradient")
	self._acceptRampColor = self._acceptRamp and self._acceptRamp.Color
	self._declineRampColor = self._declineRamp and self._declineRamp.Color

	-- The same hover nudges the shipping answers take, for the same reason.
	button:SetAttribute("Scale", BUTTON_HOVER_SCALE)
	decline:SetAttribute("Scale", DECLINE_HOVER_SCALE)

	self:_wire()

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- The kit arrives tagged (`PrepKitTemplate`); asserted after the parenting all the same, which is
	-- the order the contract asks for and a no-op on a tag that is already there.
	CollectionService:AddTag(button, "UIButton")
	CollectionService:AddTag(decline, "UIButton")
	return true
end

--[[ === WORKING THE COLUMN OUT =============================================================

	Both pills, both gamepad badges, the question and the stake, out of the block of numbers up top
	and one measurement off the viewport. See the note above `STACK_BOTTOM` for why any of this is
	arithmetic rather than four authored Y values.

	IT WRITES BOTH AXES OF EACH SIZE, which is why neither button carries a `UIAspectRatioConstraint`
	any more. Authoring the width and letting a constraint answer with the height would put two
	things in charge of the geometry, and only one of them would know where the other button was:
	that split is precisely what let a screen wide enough push the two pills into each other.

	IT WRITES THE SLOTS, NOT THE BUTTONS, which is what keeps the size to itself. Both reactions a
	button has to a pointer ride a `UIScale` (the hover's belongs to `Components/Button`, the press
	dip's to the slot), so nothing else on this screen ever writes a `Size` and there is no version
	of it to go stale. The `buttonSlot` block in `_build` has the whole of that argument. ]]
local function pillSize(height: number, widthCap: number, ratio: number): (number, number)
	-- `ratio` is the viewport's own aspect. Width implied by the authored height, then capped, then
	-- the height read back off whichever of the two won.
	local width = math.min(widthCap, height * PILL_ASPECT / ratio)
	return width, width * ratio / PILL_ASPECT
end

function ReviveController._layout(self)
	-- The kit panel's geometry is authored (`BuildReviveV2`) and its badges hang off its slots, so
	-- there is nothing here for it to work out.
	if self._panel then
		return
	end
	local view = self._gui.AbsoluteSize
	if view.X <= 0 or view.Y <= 0 then
		return
	end
	local ratio = view.X / view.Y

	local buttonW, buttonH = pillSize(BUTTON_HEIGHT, BUTTON_WIDTH_MAX, ratio)
	local declineW, declineH = pillSize(DECLINE_HEIGHT, DECLINE_WIDTH_MAX, ratio)
	local gap = math.max(declineH * BUTTON_GAP, BUTTON_GAP_MIN)

	local declineY = STACK_BOTTOM - declineH / 2
	local buttonY = declineY - declineH / 2 - gap - buttonH / 2

	self._buttonSlot.Size = UDim2.fromScale(buttonW, buttonH)
	self._buttonSlot.Position = UDim2.fromScale(0.5, buttonY)
	self._declineSlot.Size = UDim2.fromScale(declineW, declineH)
	self._declineSlot.Position = UDim2.fromScale(0.5, declineY)

	-- Stood on the block, in the order they are read: the stake, then the question, then the answers.
	local headlineY = buttonY - buttonH / 2 - HEADLINE_GAP - HEADLINE_SIZE.Y.Scale / 2
	self._headline.Position = UDim2.fromScale(0.5, headlineY)
	self._stake.Position = UDim2.fromScale(
		0.5,
		headlineY - HEADLINE_SIZE.Y.Scale / 2 - STAKE_GAP - STAKE_SIZE.Y.Scale / 2
	)

	--[[ ...and the two badges, one gap outside each pill's left edge. They are latched for `_bindPad`
		to place a badge that does not exist yet, and written straight onto any that does, so a resize
		with the screen already up moves them with the buttons they belong to. ]]
	self._acceptIconAt = UDim2.fromScale(0.5 - buttonW / 2 - ICON_GAP, buttonY)
	self._declineIconAt = UDim2.fromScale(0.5 - declineW / 2 - ICON_GAP, declineY)
	local acceptIcon = GamepadInput.getIcon(PAD_ACCEPT)
	if acceptIcon then
		acceptIcon.Position = self._acceptIconAt
	end
	local declineIcon = GamepadInput.getIcon(PAD_DECLINE)
	if declineIcon then
		declineIcon.Position = self._declineIconAt
	end
end

--[[ Both presses answer the server and then LOCK THE SCREEN, rather than waiting to be told to come
	down.

	The lock is the whole of it. A revive is a purchase prompt away and a decline is a round trip, so
	between the press and the screen closing there are frames in which the button is still live —
	and a player with a second and a half left on the clock will press it again. Locking on the press
	means the second press does nothing, which is what the server would have done with it anyway
	(`_onAccept` reads state the client cannot forge), but without the flicker of a button that looks
	like it is still asking.

	The DRAIN keeps running under the lock, deliberately: the clock genuinely is still going while a
	purchase prompt is open behind this screen, and freezing it would be the screen lying about the
	one thing it is for. ]]
function ReviveController._wire(self)
	-- Both answers dip, and both are wired the same way, because both are the same pill now.
	for _, pair in { { self._button, self._buttonScale }, { self._decline, self._declineScale } } do
		local press, scale = pair[1], pair[2]
		press.MouseButton1Down:Connect(function()
			if not self._locked then
				self:_press(true, scale)
			end
		end)
		press.MouseButton1Up:Connect(function()
			self:_press(false)
		end)
		--[[ A press dragged off a button is a press cancelled, and the dip has to come back up with it.
			The FACE needs no such handling — `HoverImage`/`PressedImage` are the engine's, and it puts
			them back by itself. ]]
		press.MouseLeave:Connect(function()
			self:_press(false)
		end)
	end
	--[[ ...and the backstop for the release that neither of the two above ever sees: a finger that
		goes down on the button and comes up somewhere else raises `MouseButton1Up` on nothing (it
		only fires over the button) and `MouseLeave` only if the pointer actually crossed the edge on
		its way — which a touch drag does not always report. Left to those two the dip sticks at 97%
		for the rest of the offer. Cheap to answer here: any mouse or touch release, anywhere, ends
		a press this screen thinks is still down. ]]
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if not self._pressed then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			self:_press(false)
		end
	end)
	self._button.Activated:Connect(function()
		self:_pressAccept()
	end)

	self._decline.Activated:Connect(function()
		self:_pressDecline()
	end)
end

--[[ The two answers, once each. A press with a mouse, a tap with a thumb and ButtonA on a
	controller all arrive here; the lock is what makes a second one of any of them a no-op.

	NAMED `_pressAccept` / `_pressDecline` AND NOT `_accept` / `_decline`, which is not fussiness:
	`self._decline` is already the END RUN *TextButton* (`_build` parks it there), so a method of
	that name is shadowed by the instance and `self:_decline()` calls a TextButton — "attempt to
	call an Instance value", every press, silently until you try one. `UIController` has the same
	hazard written down for `Open`/`Close`; this is the same trap one file over. ]]
function ReviveController._pressAccept(self)
	-- `_homeOnly`: RACE AGAIN is not on the panel, so ButtonA has nothing to press (see `_show`).
	if self._locked or not self._open or self._homeOnly then
		return
	end
	if self._ending then
		return self:_answerEnd("replay", "press")
	end
	self._locked = true
	--[[ Held until the server answers: a stored life closes the offer, a purchase prompt hands the
		clock back with a fresh offer (`_show` clears this). Until then the countdown must not answer
		for the player, because the server is holding the offer open for the prompt. ]]
	self._accepted = true
	self:_press(false)
	self:getRemoteEvent("ReviveAccept"):Fire()
end

function ReviveController._pressDecline(self)
	if self._locked or not self._open then
		return
	end
	if self._ending then
		return self:_answerEnd("home", "press")
	end
	self._locked = true
	self:_press(false)
	--[[ The screen goes down on the press rather than on the server's `ReviveClosed`. Declining is
		the one answer with nothing to wait for — the run is over and the return fade is a beat behind
		this — so holding the screen up for the round trip would be a screen that ignored the only
		press it was ever going to get. ]]
	-- The one-screen wreck has shown the run already, so the return skips its results. See the header.
	-- The last two arguments are for `AnalyticsController` (how it was answered, and on which panel).
	if self._wreck then
		Dispatcher:Publish(RaceConfig.WreckAnsweredEvent, "home", "press", "revive")
	end
	self:_hide()
	self:getRemoteEvent("ReviveDecline"):Fire()
end

--[[ The countdown ran out on the one-screen wreck: answer for the player. Again, unless nobody has
	touched anything since the last time this answered for them (`_idle`, decided at `_show`). The
	answer is published BEFORE the decline goes, so it is in `RaceUIController`'s hands before the
	return it applies to can arrive. ]]
function ReviveController._autoAnswer(self)
	local answer = if self._idle then "home" else "replay"
	if answer == "replay" then
		self._autoReplayedAt = os.clock()
	end
	if self._ending then
		return self:_answerEnd(answer, "auto")
	end
	self._locked = true
	self:_press(false)
	Dispatcher:Publish(RaceConfig.WreckAnsweredEvent, answer, "auto", "revive")
	self:_hide()
	self:getRemoteEvent("ReviveDecline"):Fire()
end

--[[ The end panel's answer, whichever way it came. Same order as the wreck's: published first, so
	`RaceUIController` has it before the return it applies to, then the panel, then the server, which
	runs that return the moment this lands.

	`how` is "press" or "auto" (the countdown answered), and rides on the event with the panel's mode
	("bank" or "wreck") for `AnalyticsController`: whether a player chooses RACE AGAIN or HOME,
	in the tutorial above all, is a question the team is deciding the button's future on (2026-10-15). ]]
function ReviveController._answerEnd(self, answer: string, how: string?)
	self._locked = true
	self:_press(false)
	Dispatcher:Publish(RaceConfig.WreckAnsweredEvent, answer, how or "press", self._ending)
	self:_hide()
	self:getRemoteEvent("RaceEndAnswer"):Fire()
end

--[[ `RaceEndPanel`: the server is holding this run's return for the end panel. Paint it from the
	settled run and put it up, in results mode.

	THE SUMMARY RIDES ANOTHER REMOTE (`RunSettled`, RewardService's), fired before this one but with
	no ordering promise across the two, so a frame or two is waited for it. A client with no panel to
	draw on answers at once, which lets the server go on to the old ending. ]]
function ReviveController._showEnd(self, payload)
	if not (self._wreck and NewUIConfig.EndPanel) or type(payload) ~= "table" then
		self:getRemoteEvent("RaceEndAnswer"):Fire()
		return
	end
	local results = Shard.get("RaceUIController")
	local summary, leveled
	for _ = 1, SUMMARY_WAIT_FRAMES do
		if results then
			summary, leveled = results:lastRun()
		end
		if summary then
			break
		end
		task.wait()
	end
	-- A revive question still up (a server timeout lands here) goes first; this takes its place.
	if self._open then
		self:_hide()
	end
	self:_show({
		seconds = if type(payload.seconds) == "number" then payload.seconds else RaceConfig.EndPanel.Seconds,
		ending = if payload.kind == "bank" then "bank" else "wreck",
		cause = payload.cause,
		run = summary,
		leveled = leveled,
		studs = if summary then summary.studs else 0,
		lives = 0,
	})
end

--[[ === RACE AGAIN IN THE TUTORIAL, PER PLAYER (`TutorialConfig.RaceAgain`) ===============

	Gamebeast's value for this player, followed for the session: `Observe` calls back once the configs
	have loaded and again on every change, which includes their experiment group arriving a few
	seconds in, long before anybody has finished a first run. Anything that is not a boolean is the
	build's `Offered`, so a failure here costs the test and nothing else. ]]
function ReviveController._observeRaceAgain(self)
	local remote = TutorialConfig.RaceAgain.Remote
	if not remote.Enabled then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			local Gamebeast = require(ReplicatedStorage:WaitForChild("Gamebeast"))
			Gamebeast:GetService("Configs"):Observe(remote.Path, function(value)
				self._remoteRaceAgain = if type(value) == "boolean" then value else nil
			end)
		end)
		if not ok then
			self.log:warn("Gamebeast config unavailable, the tutorial offers RACE AGAIN as built: " .. tostring(err))
		end
	end)
end

--- Does a getaway in the tutorial offer RACE AGAIN to this player? Gamebeast's answer, else the build's.
function ReviveController._offersRaceAgain(self): boolean
	if self._remoteRaceAgain ~= nil then
		return self._remoteRaceAgain
	end
	return TutorialConfig.RaceAgain.Offered
end

--[[ The controller's two buttons, live only while the screen is.

	The badges are parented to the scrim at a measured position rather than to the buttons (see
	`ICON_GAP`, and `_layout` for the arithmetic), and they are faded in and out with everything else,
	because a glyph that snapped on while the screen behind it was still arriving would be the one
	element on this screen that did not respect the entrance.

	`_padIcons` is read back off the bindings rather than kept in a field: `GamepadInput.unbind`
	destroys them, so the module is the only thing that can honestly answer whether they still
	exist. ]]
function ReviveController._bindPad(self, on: boolean)
	GamepadInput.setModal("ReviveController", on)

	if not on then
		GamepadInput.unbind(PAD_ACCEPT)
		GamepadInput.unbind(PAD_DECLINE)
		return
	end

	-- Where each badge hangs: beside its pill on the scrim, or on its button's outer corner on the
	-- kit panel (see `KIT_ACCEPT_ICON_AT`).
	local kit = self._panel ~= nil
	GamepadInput.bind({
		actionName = PAD_ACCEPT,
		keyCode = Enum.KeyCode.ButtonA,
		callback = function()
			self:_pressAccept()
		end,
		parent = if kit then self._buttonSlot else self._scrim,
		iconPosition = if kit then KIT_ACCEPT_ICON_AT else self._acceptIconAt,
		iconAnchor = if kit then KIT_ACCEPT_ICON_ANCHOR else Vector2.new(1, 0.5),
		priority = PAD_PRIORITY,
	})
	GamepadInput.bind({
		actionName = PAD_DECLINE,
		keyCode = Enum.KeyCode.ButtonB,
		callback = function()
			self:_pressDecline()
		end,
		parent = if kit then self._declineSlot else self._scrim,
		iconPosition = if kit then KIT_DECLINE_ICON_AT else self._declineIconAt,
		iconAnchor = if kit then KIT_DECLINE_ICON_ANCHOR else Vector2.new(1, 0.5),
		-- A little smaller, like the answer it belongs to, and by about the ratio the two pills are
		-- drawn at. It was 0.72 while END RUN was bare text and the badge was the loudest thing near it.
		iconSize = GamepadConfig.Icon.Size * 0.85,
		priority = PAD_PRIORITY,
	})
end

function ReviveController._padIcons(self): { ImageLabel }
	local icons = {}
	for _, action in { PAD_ACCEPT, PAD_DECLINE } do
		local icon = GamepadInput.getIcon(action)
		if icon and icon.Parent then
			table.insert(icons, icon)
		end
	end
	return icons
end

-- Fade the badges with the screen. `visible` is the resting state — the badge is a filled disc, so
-- its own background goes with the image rather than being left as a solid dot behind a fading glyph.
function ReviveController._fadePad(self, time: number, visible: boolean)
	local transparency = if visible then 0 else 1
	for _, icon in self:_padIcons() do
		self:_tween(icon, time, { ImageTransparency = transparency, BackgroundTransparency = transparency })
		local stroke = icon:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			self:_tween(stroke, time, { Transparency = transparency })
		end
	end
end

--[[ The dip, and only the dip: the art the engine swaps under it is the rest of the press.

	A PRESS NAMES ITS BUTTON AND A RELEASE DOES NOT, which is not sloppiness. Going down is always a
	press on one of the two pills, so it dips that one; coming up arrives from three places that
	cannot say which (a finger lifted anywhere in `InputEnded`, a pointer that left, a mouse released
	over the button it started on), so it lifts both. Lifting a button that was never down costs a
	write of the value it already holds. ]]
function ReviveController._press(self, down: boolean, scale: UIScale?)
	self._pressed = down
	if down then
		if scale then
			scale.Scale = PRESS_SCALE
		end
		return
	end
	self._buttonScale.Scale = 1
	self._declineScale.Scale = 1
end

--[[ What the button says, which is the only part of this screen that changes between offers.

	TWO STATES, AND THE FREE ONE COMES FIRST. A player holding a stored life — one they bought on a
	run that ended before they could spend it, or a receipt that only landed on this session — is not
	being sold anything, so the button must not show a price it is not going to charge. That case is
	rare and it is exactly the case where getting it wrong looks like a double charge.

	The price is written `R$25` rather than as a Robux icon because there is no Robux glyph in this
	kit and an ImageLabel of one would be the only asset on a screen that otherwise needs none. ]]
--[[ What Roblox says this player pays for the offer's rung (`Modules/LivePrice`). The server sends
	`ReviveConfig.Tiers[n].Price`, which is the config's figure and not what the window charges; it
	shows until Roblox answers, and stays if the call fails. `start` asks for every rung up front so
	an eight-second offer never waits on it. ]]
local function priceOf(offer): number
	local tier = ReviveConfig.Tiers[tonumber(offer.tier) or 0]
	return (tier and LivePrice.peek(tier.ProductId)) or offer.price or 0
end

function ReviveController._caption(self, offer): string
	if offer.ending then
		return AGAIN_CAPTION
	end
	--[[ The kit panel prices in the kit's own Robux mark rather than `R$`: the kit HAS the glyph,
		which is the thing the paragraph above says this kit lacked. Everything else is the same words
		in the same capitals, the call every other Phase 4 prompt made. ]]
	if self._panel and not (offer.lives and offer.lives > 0) then
		return string.format("REVIVE%s%s%d", NBSP .. NBSP, ROBUX, priceOf(offer))
	end
	if offer.lives and offer.lives > 0 then
		-- LIVES, not "LIFES" — the plural was built by bolting an S on the singular, and two stored
		-- lives printed it on the button.
		local word = if offer.lives == 1 then "LIFE" else "LIVES"
		return string.format("REVIVE%s(%d%s%s)", NBSP .. NBSP, offer.lives, NBSP, word)
	end
	return string.format("REVIVE%sR$%d", NBSP .. NBSP .. NBSP, priceOf(offer))
end

--[[ Draw an offer. Called for a fresh one AND for a repaint — a purchase prompt closing restarts
	the clock, a purchase landing changes the caption — so everything it touches is written
	unconditionally rather than assumed to be at rest.

	`_span` is latched beside the deadline because the drain is a FRACTION and a fraction needs to
	know what full was. A repaint that hands back a fresh eight seconds has to redraw a full bar; one
	that only changes the caption must not touch the bar at all, which is what `keepClock` is for. ]]
function ReviveController._paint(self, offer, keepClock: boolean?)
	if not keepClock then
		local seconds = math.max(0, tonumber(offer.seconds) or 0)
		self._deadline = os.clock() + seconds
		self._span = math.max(seconds, 0.001)
		self._drain.Size = UDim2.fromScale(1, 1)
		self._drain.BackgroundColor3 = WHITE
		self._urgent = false
		self:_light(0)
	end

	self._offer = offer
	self._captionLabel.Text = self:_caption(offer)

	local distance = RewardConfig.formatDistance(offer.studs)
	--[[ A run with no distance worth naming gets NO stake line rather than a zero. The offer still
		stands — you can wreck in the first fifty studs and still want your car back — but "0m driven"
		is an argument against paying, and printing it is the screen talking the player out of the
		thing it is asking them to do. ]]
	self._stake.Text = if distance then distance .. NBSP .. "driven" elseif self._panel and not self._wreck then KIT_NO_STAKE else ""

	--[[ The words the two modes do not share, written both ways every time. The end panel names the
		ending in its header, offers HOME for the way out, and adds a level-up to the distance row. ]]
	if self._wreck then
		self._headline.Text = if offer.ending then END_HEADERS[offer.ending] else KEEP_GOING
		self._declineLabel.Text = if offer.ending then HOME_CAPTION else END_RUN
		-- Written both ways every time, like the words: the next offer may be a wreck. See `SECONDARY_RAMP`.
		local won = offer.ending == "bank"
		if self._acceptRamp and self._declineRamp then
			self._acceptRamp.Color = if won then SECONDARY_RAMP else self._acceptRampColor
			self._declineRamp.Color = if won then self._acceptRampColor else self._declineRampColor
		end
		local leveled = offer.leveled
		if offer.ending and type(leveled) == "table" and leveled.body and leveled.level then
			local level = string.gsub(string.format("%s reached Level %d", GarageConfig.displayName(tostring(leveled.body)), leveled.level), " ", NBSP)
			local tail = string.format('<font color="%s">%s</font>', LEVEL_COLOR, level)
			self._stake.Text = if self._stake.Text ~= "" then self._stake.Text .. DOT .. tail else tail
		end
	end
end

--[[ === THE RUN, ON THE ONE-SCREEN WRECK ====================================================

	Painted once per offer, on the first show; a repaint (a purchase prompt closing) leaves it alone.
	Every figure is the offer's `run`, the server's preview of the crash settlement, worded the way
	the results screen words it (`RaceUIController._paintPayout`): the payout with its split, the
	distance, and the tally with what it kept. ]]
function ReviveController._paintRun(self, offer)
	local rows = self._wreck
	local run = if type(offer.run) == "table" then offer.run else nil
	--[[ What the payout line carries after the figure: the crash split on a wreck, the mutation on a
		getaway that had one (the reason a bank can pay five times over), nothing on a plain getaway.
		`RaceUIController._paintPayout` has the argument for each. ]]
	local kept = string.format("%skept%s%d%%", DOT, NBSP, math.round(RewardConfig.Crash.CashFraction * 100))
	local banked = run ~= nil and run.banked == true
	if banked then
		kept = if run.mutation and WeatherConfig.multiplierOf(run.mutation) > 1
			then string.format(
				"%s%s%s%s",
				DOT,
				WeatherConfig.nameOf(run.mutation),
				NBSP,
				WeatherConfig.formatMultiplier(WeatherConfig.multiplierOf(run.mutation))
			)
			else ""
	end

	rows.headline.Text = if offer.ending == "bank"
		then BANK_HEADLINE
		elseif offer.cause == PoliceConfig.Cause then PoliceConfig.BustedWord
		elseif offer.cause == "badLanding" then BAIL_HEADLINE
		else WRECK_HEADLINE

	local cash = if run and type(run.cash) == "number" then run.cash else 0
	--[[ THE 2X CASH PASS, SAID (2026-10-15, the owner: "it's not showing me that I got double cash").
		This panel is the one a getaway lands on (and a wreck's offer), so it says so the way the
		results screen does (`RaceUIController`'s `DOUBLE`): "· 2x CASH" after the figure, which is
		already the doubled one (`RewardService` doubles both the settlement and its preview). ]]
	if cash > 0 then
		local PassConfig = require(game:GetService("ReplicatedStorage").shared.Configs.PassConfig)
		if game:GetService("Players").LocalPlayer:GetAttribute(PassConfig.ownedAttribute("CashDouble")) == true then
			kept ..= DOT .. "2x" .. NBSP .. "CASH"
		end
	end
	self._cashTo = cash
	self._cashTail = kept
	--[[ THE HEAT BONUS (`PoliceConfig.Heat`, 2026-10-19). The figure counts to what the run made before
		it, the HEAT pill stamps onto the line, then it climbs to what was paid (`_stepRun`). `cash` is
		already the paid one (`RaceUIController`'s summary carries the multiplier), so the run's own
		figure is worked back out. ]]
	local heat = if banked and cash > 0 and type(run.heat) == "number" and run.heat > 1 then run.heat else nil
	self._heatMult = heat
	self._cashBase = if heat then math.round(cash / heat) else nil
	self._heatStamped = false
	if self._heatPill then
		self._heatPill.Visible = false
	end
	rows.cash.Text = if cash > 0 then "+" .. GarageConfig.formatCash(0) .. kept else "No" .. NBSP .. "payout" .. kept

	--[[ The tally, with the bonus it kept in gold. A run with none of either gets the offer's own
		pitch instead, so the strip is never an empty box. ]]
	local tally = run and NearMissConfig.tallyLabel(run.nearMisses, run.rubs)
	if tally then
		local line = (string.gsub(tally, " ", NBSP))
		local bonus = if run and type(run.bonus) == "number" then run.bonus else 0
		if bonus > 0 then
			-- The split rides here too on a wreck (see `_paintPayout`); a getaway's mutation is
			-- already on the payout line, and saying it twice is just longer.
			local tail = if banked then "" else kept
			line ..= string.format('%s<font color="%s">+%s</font>%s', NBSP .. NBSP, STRIP_BONUS, GarageConfig.formatCash(bonus), tail)
		end
		rows.stripText.Text = line
	else
		rows.stripText.Text = if offer.ending then NO_TALLY else KIT_NO_STAKE
	end

	-- The ladder, measured off the road that is still standing under the wreck.
	for _, tick in rows.ticks:GetChildren() do
		tick:Destroy()
	end
	local results = Shard.get("RaceUIController")
	local plan = if results and run then results:planLadder(run.studs or 0) else nil
	self._plan = plan
	rows.ladder.Visible = plan ~= nil
	rows.fill.Size = UDim2.fromScale(0, 1)
	rows.marker.Position = UDim2.fromScale(0, rows.marker.Position.Y.Scale)
	if plan then
		for index, at in plan.marks do
			local tick = Instance.new("Frame")
			tick.Name = "Tick" .. index
			tick.AnchorPoint = Vector2.new(0.5, 0.5)
			tick.Position = UDim2.fromScale(at, 0.5)
			tick.Size = UDim2.fromScale(RUNG_WIDTH, RUNG_HEIGHT)
			tick.BackgroundColor3 = if index <= plan.reached then RUNG_REACHED else RUNG_AHEAD
			tick.BorderSizePixel = 0
			local round = Instance.new("UICorner")
			round.CornerRadius = UDim.new(1, 0)
			round.Parent = tick
			tick.Parent = rows.ticks
		end
	end

	-- The corner: the car you kept, the cruiser, the wreck or your ragdoll (`buildEndShot`).
	self:_dropShot()
	self._shot = if results
		then results:buildEndShot(rows.carSlot, {
			ending = offer.ending or "wreck",
			cause = offer.cause,
			backdrop = SHOT_BACKDROP,
			smoke = SHOT_SMOKE,
			strength = SHOT_SMOKE_STRENGTH,
			layers = SHOT_SMOKE_LAYERS,
		})
		else nil
	self._runShownAt = os.clock()
end

--- The bar and the money, one clock: both are driven from `_tick` off `_runShownAt`.
function ReviveController._stepRun(self, now: number)
	local rows = self._wreck
	local t = math.clamp((now - (self._runShownAt or now) - LADDER_DELAY) / LADDER_TIME, 0, 1)
	local eased = 1 - (1 - t) ^ 3
	local plan = self._plan
	if plan then
		local at = plan.progress * eased
		rows.fill.Size = UDim2.fromScale(at, 1)
		rows.marker.Position = UDim2.fromScale(at, rows.marker.Position.Y.Scale)
	end
	if (self._cashTo or 0) > 0 then
		local shown = self._cashTo * eased
		if self._heatMult then
			--- First to the run's own figure, then the stamp, then up to the paid one (`_paintRun`).
			local since = now - (self._runShownAt or now) - LADDER_DELAY - LADDER_TIME - HEAT_STAMP.delay
			if since < 0 then
				shown = self._cashBase * eased
			else
				if not self._heatStamped then
					self._heatStamped = true
					self:_stampHeat(self._heatMult)
				end
				local climb = 1 - (1 - math.clamp(since / HEAT_STAMP.countTime, 0, 1)) ^ 3
				shown = self._cashBase + (self._cashTo - self._cashBase) * climb
			end
		end
		rows.cash.Text = "+" .. GarageConfig.formatCash(math.round(shown)) .. self._cashTail
	end
	if self._shot then
		self._shot.step(now - (self._runShownAt or now))
	end
end

--[[ The HEAT pill, stamped beside the headline (STOLEN!): big, then down with a tilt, the way a
	rubber stamp lands. Built once, inside the headline, and placed off the text's measured width.
	2026-10-19: WAS on the payout line's right end, where it covered "2x CASH". ]]
function ReviveController._stampHeat(self, heat: number)
	local line = self._wreck.headline
	local pill = self._heatPill
	if not pill then
		pill = Instance.new("TextLabel")
		pill.Name = "HeatPill"
		pill.AnchorPoint = Vector2.new(0, 0.5)
		pill.Size = UDim2.fromScale(0.26, 0.75)
		pill.Rotation = HEAT_STAMP.rotation
		pill.BackgroundColor3 = HEAT_STAMP.colour
		pill.Font = Enum.Font.FredokaOne
		pill.TextScaled = true
		pill.TextColor3 = WHITE
		pill.ZIndex = line.ZIndex + 2
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = pill
		local rim = Instance.new("UIStroke")
		rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rim.Color = HEAT_STAMP.ink
		rim.Thickness = 2
		rim.Parent = pill
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.08, 0)
		pad.PaddingRight = UDim.new(0.08, 0)
		pad.Parent = pill
		Instance.new("UIScale").Parent = pill
		pill.Parent = line
		self._heatPill = pill
	end
	local multiplier = string.format("%.2f", heat):gsub("0+$", ""):gsub("%.$", "")
	pill.Text = string.format(HEAT_STAMP.text, multiplier)
	--- Just right of the centred word, wherever it ends.
	pill.Position = UDim2.new(0.5, line.TextBounds.X * 0.5 + 12, 0.5, 0)
	pill.Visible = true
	local scale = pill:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = HEAT_STAMP.from
	TweenService:Create(scale, TweenInfo.new(HEAT_STAMP.stampTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 1 }):Play()
end

function ReviveController._dropShot(self)
	if self._shot then
		self._shot.destroy()
		self._shot = nil
	end
end

--[[ How lit the offer's face is, 0 to 1 of the way to the most the breath ever reaches. The one write
	the two screens do differently: the shipping pill cross-fades the artist's hover IMAGE in, and the
	kit button has no hover image, so its `Lit` is a white wash capped at `KIT_LIT_SHARE`. ]]
function ReviveController._light(self, amount: number)
	if self._panel then
		self._lit.BackgroundTransparency = 1 - amount * KIT_LIT_SHARE
	else
		self._lit.ImageTransparency = 1 - amount
	end
end

--[[ The countdown, and the urgency. One connection for the life of the screen, and the ONLY thing
	on this controller that runs per frame.

	The drain's width is `remaining / span` and nothing else — no easing, no smoothing — because it
	is a clock, and a clock that eases is a clock that is wrong in the middle. What DOES ease is the
	urgency breath under `URGENT_AT`, which moves the face's opacity and never its size: this button
	is being aimed at, and a target that changes size while a thumb is travelling toward it is a
	target that gets missed. ]]
function ReviveController._tick(self)
	if not self._open then
		return
	end
	local remaining = math.max(0, (self._deadline or 0) - os.clock())
	local fraction = math.clamp(remaining / (self._span or 1), 0, 1)
	self._drain.Size = UDim2.fromScale(fraction, 1)

	--[[ The one-screen wreck's clock is a line of type, and at zero it answers for the player unless
		a purchase is in flight. Hidden while one is: the server has stopped the clock for the prompt,
		so a number still falling would be the screen lying about it. ]]
	if self._wreck then
		self:_stepRun(os.clock())
		local countdown = self._wreck.countdown
		countdown.Visible = not self._accepted
		countdown.Text = string.format(if self._idle then COUNT_HOME else COUNT_REPLAY, math.max(1, math.ceil(remaining)))
		if remaining <= 0 and not self._accepted then
			self:_autoAnswer()
			return
		end
	end

	--[[ At zero the button stops taking presses, and it does so HERE rather than waiting for the
		server's `ReviveClosed`. The bar runs a trip ahead of the server's own deadline (see the
		header), so there is a sliver in which the offer is drawn as expired but is technically still
		open — and a press landing in it would be honoured, charging Robux for a revive the player
		had already watched run out. Locking is not the same as hiding: the screen stays up until the
		server closes it, so nothing flickers. ]]
	if remaining <= 0 then
		self._locked = true
	end

	--[[ THE LIT FRAME IS ONLY WRITTEN ONCE THE OFFER IS URGENT, and outside that window this loop does
		not touch it at all. That was load-bearing when the breath moved the FACE's opacity — the
		entrance tweens that very property, and a per-frame write would have beaten it to the target
		and made the screen snap on instead of fade. The breath has its own instance now, so the two
		can no longer collide at all; leaving it alone until it is needed is what keeps the fade-out
		below able to own it.

		Leaving urgency is possible — a purchase prompt closing hands the whole clock back — so the
		last write is undone explicitly rather than left where the breath happened to stop. ]]
	if fraction <= URGENT_AT then
		self._urgent = true
		self._drain.BackgroundColor3 = if self._panel then KIT_URGENT else CRASH_AMBER
		-- A half-cosine, so it rests on the idle face and only ever breathes TOWARD the lit one: the
		-- artist's own hover colour, driven by a clock instead of by a cursor.
		local breath = 0.5 - 0.5 * math.cos(os.clock() * URGENT_PULSE * math.pi * 2)
		self:_light(breath * URGENT_LIT)
	elseif self._urgent then
		self._urgent = false
		self._drain.BackgroundColor3 = WHITE
		self:_light(0)
	end
end

function ReviveController._show(self, offer)
	if not self._gui then
		self:_build()
	end
	--[[ A repaint of a screen already up must not replay the entrance: the player is looking at it,
		and fading the whole thing back in because a purchase prompt closed would read as the offer
		having restarted rather than as it having been given its time back. ]]
	local wasOpen = self._open
	self._open = true
	self._locked = false
	self._accepted = false -- a fresh offer, or the one a closed purchase prompt handed back
	self._ending = offer.ending -- nil for a revive offer; "bank" or "wreck" on the end panel
	self:_paint(offer)
	if wasOpen then
		return
	end
	self._pressed = false
	self._homeOnly = false
	if self._wreck then
		--[[ The replay guard (see the header): idle when this answered for the player last time and
			nothing has been pressed since. Decided once per offer so the line cannot change its mind. ]]
		self._idle = self._autoReplayedAt ~= nil and (self._lastInputAt or 0) < self._autoReplayedAt
		--- A getaway counts down to home, not to the next race: you won the car, and home is where it went.
		if offer.ending == "bank" then
			self._idle = true
		end
		--- ...and the end panel goes home while the tutorial is running: its next beat is there.
		if offer.ending then
			local tutorial = Shard.get("TutorialController")
			if tutorial and tutorial.isActive and tutorial:isActive() then
				self._idle = true
				--- ...and in one arm of the A/B a getaway's panel offers home and nothing else.
				self._homeOnly = offer.ending == "bank" and not self:_offersRaceAgain()
			end
		end
		self:_paintRun(offer)
	end
	--[[ Written every time, like the words: the next panel may offer RACE AGAIN again. The kit's row
		is a centred list, so HOME moves to the middle on its own. ]]
	if self._buttonSlot then
		self._buttonSlot.Visible = not self._homeOnly
	end

	self._gui.Enabled = true
	if self._panel then
		self:_raiseKit()
	else
		-- ...and only now is there a viewport to measure: `AbsoluteSize` is what `_layout` reads.
		self:_layout()
		self._buttonScale.Scale = 1
		self._declineScale.Scale = 1
		self:_tween(self._scrim, RAISE_TIME, { BackgroundTransparency = SCRIM_REST })
		self:_tween(self._button, RAISE_TIME, { ImageTransparency = 0 })
		self:_tween(self._captionLabel, RAISE_TIME, { TextTransparency = 0 })
		self:_tween(self._drainTrack, RAISE_TIME, { BackgroundTransparency = DRAIN_REST })
		self:_tween(self._drain, RAISE_TIME, { BackgroundTransparency = 0 })
		self:_tween(self._headline, RAISE_TIME, { TextTransparency = 0 })
		self:_tween(self._stake, RAISE_TIME, { TextTransparency = 0.25 })
		--[[ THE WAY OUT COMES UP SOLID, both the face and the word on it. It used to rest at 0.3 of
			transparency, which was the whole of what made it secondary once it had no button face to be
			secondary WITH, and a half-faded control is the kit's language for a control that is switched
			off. Silver against blue, and two thirds the size, says "not the loud one" without ever saying
			"not available". See the `decline` block in `_build`. ]]
		self:_tween(self._decline, RAISE_TIME, { ImageTransparency = 0 })
		self:_tween(self._declineLabel, RAISE_TIME, { TextTransparency = 0 })
	end

	-- Bound before the fade so a controller can answer during the entrance — the clock is already
	-- running, and 0.28s of an eight-second offer is not free.
	self:_bindPad(true)
	for _, icon in self:_padIcons() do
		icon.ImageTransparency = 1
		icon.BackgroundTransparency = 1
		local stroke = icon:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			stroke.Transparency = 1
		end
	end
	self:_fadePad(RAISE_TIME, true)

	if not self._tickConn then
		self._tickConn = RunService.RenderStepped:Connect(function()
			self:_tick()
		end)
	end
end

function ReviveController._hide(self)
	if not (self._gui and self._open) then
		return
	end
	self._open = false
	local token = (self._token or 0) + 1
	self._token = token

	local last
	if self._panel then
		last = self:_lowerKit()
	else
		self:_tween(self._scrim, DROP_TIME, { BackgroundTransparency = 1 })
		self:_tween(self._button, DROP_TIME, { ImageTransparency = 1 })
		self:_tween(self._captionLabel, DROP_TIME, { TextTransparency = 1 })
		-- The breath goes with it, and it has to be tweened rather than dropped: `_tick` has already
		-- stood down (`_open` is false above), so a screen that closed mid-breath would otherwise fade
		-- out with a lit face still sitting on top of the idle one.
		self:_tween(self._lit, DROP_TIME, { ImageTransparency = 1 })
		self:_tween(self._drainTrack, DROP_TIME, { BackgroundTransparency = 1 })
		self:_tween(self._drain, DROP_TIME, { BackgroundTransparency = 1 })
		self:_tween(self._headline, DROP_TIME, { TextTransparency = 1 })
		self:_tween(self._stake, DROP_TIME, { TextTransparency = 1 })
		self:_tween(self._decline, DROP_TIME, { ImageTransparency = 1 })
		last = self:_tween(self._declineLabel, DROP_TIME, { TextTransparency = 1 })
	end
	self:_fadePad(DROP_TIME, false)

	last.Completed:Once(function()
		-- Fenced on the token, so a second offer opened inside the fade-out (a wreck immediately
		-- after a revive is entirely possible) is not switched off by the last one's tail.
		if self._token == token and not self._open then
			if self._panel then
				self._panel.Visible = false
			end
			self:_dropShot()
			self._gui.Enabled = false
			-- ...and the bindings go with it. They are held through the fade so the badges have
			-- something to fade OUT; the answers themselves are already dead, because both check
			-- `_open` and this screen set it false on the way in here.
			self:_bindPad(false)
			if self._tickConn then
				self._tickConn:Disconnect()
				self._tickConn = nil
			end
		end
	end)
end

--[[ The kit panel's entrance: the scrim settles as it always did, and the panel swells in from
	`KIT_START_SCALE` the way every kit page opens. Nothing on it fades, because nothing on it was
	ever transparent: the buttons are pressable from the first frame, which on an eight-second offer
	is the point. The press dips are put back first, for the reason the shipping path does it. ]]
function ReviveController._raiseKit(self)
	self._buttonScale.Scale = 1
	self._declineScale.Scale = 1
	self._panel.Visible = true
	self._panelScale.Scale = KIT_START_SCALE
	self:_tween(self._scrim, RAISE_TIME, { BackgroundTransparency = if self._wreck then WRECK_SCRIM else SCRIM_REST })
	self:_tween(self._panelScale, RAISE_TIME, { Scale = 1 }, Enum.EasingStyle.Back)
	self:_setBlur(self._ending == "bank")
end

--- The world behind the panel, a little out of focus (`GETAWAY_BLUR`); off fades it out and drops it.
function ReviveController._setBlur(self, on: boolean)
	if on then
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local blur = self._blur
		if not (blur and blur.Parent) then
			blur = Instance.new("BlurEffect")
			blur.Name = "EndPanelBlur"
			blur.Size = 0
			blur.Parent = camera
			self._blur = blur
		end
		self:_tween(blur, BLUR_IN, { Size = GETAWAY_BLUR })
	elseif self._blur then
		local blur = self._blur
		self._blur = nil
		self:_tween(blur, DROP_TIME, { Size = 0 }).Completed:Once(function()
			blur:Destroy()
		end)
	end
end

--[[ ...and its exit, the kit pages' close: a quick settle back to `KIT_START_SCALE`, with the panel
	hidden once it lands (`_hide`'s own callback does that). The wash goes on the same clock for the
	reason the shipping path tweens its breath out. Answers the tween `_hide` waits on. ]]
function ReviveController._lowerKit(self)
	self:_setBlur(false)
	self:_tween(self._scrim, DROP_TIME, { BackgroundTransparency = 1 })
	self:_tween(self._lit, DROP_TIME, { BackgroundTransparency = 1 })
	return self:_tween(self._panelScale, DROP_TIME, { Scale = KIT_START_SCALE }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
end

function ReviveController._tween(self, inst, time: number, props, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local info = TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local tween = TweenService:Create(inst, info, props)
	tween:Play()
	return tween
end

--[[ The stored count moved, and with a screen up that means A PURCHASE HAS JUST LANDED: the caption
	is repainted so the button stops asking for Robux the instant it stops needing them.

	THE CLOCK IS NOT TOUCHED (`keepClock`) — this is not a new offer, it is the same one with a
	different price on it, and handing back time nobody asked for would make a purchase look like it
	had restarted the decision.

	With no screen up — which is most of them, since this also fires on join — there is nothing to
	repaint and nothing worth remembering: an offer carries its own count, so this is never the
	source the screen reads from. ]]
function ReviveController._onLives(self, lives: number)
	if type(lives) ~= "number" then
		return
	end
	if self._open and self._offer then
		self._offer.lives = lives
		self:_paint(self._offer, true)
	end
end

ReviveController:withRemoteEvents({
	{
		ReviveOffer = function(offer)
			if type(offer) == "table" and type(offer.seconds) == "number" then
				ReviveController:_show(offer)
			end
		end,
		-- The offer is over, whichever way it went. What happens next — the return fade, or the car
		-- appearing back under the camera — belongs to somebody else's remote.
		ReviveClosed = function()
			-- Never the end panel's: a revive that closed hands over to it, not the other way round.
			if not ReviveController._ending then
				ReviveController:_hide()
			end
		end,
		ReviveLives = function(lives)
			ReviveController:_onLives(lives)
		end,
		RaceEndPanel = function(payload)
			ReviveController:_showEnd(payload)
		end,
		--[[ The server stopped holding without an answer from here (its own timeout, or the run ended
			some other way). Down it comes, unanswered, so the old results screen is what follows. ]]
		RaceEndPanelClosed = function()
			if ReviveController._ending and ReviveController._open then
				ReviveController._locked = true
				ReviveController:_hide()
			end
		end,
	},
	"ReviveAccept",
	"ReviveDecline",
	"RaceEndAnswer",
	"RaceEndOptIn",
})

ReviveController:withLifecycle({
	init = function(self)
		self._open = false
		self._locked = false
		self._pressed = false
		self._urgent = false
		self._token = 0
		self._accepted = false -- REVIVE pressed and not yet answered; see `_pressAccept`
		self._autoReplayedAt = nil -- when the countdown last raced again for the player
		self._lastInputAt = 0 -- ...and the last press of anything, for the replay guard
		self._homeOnly = false -- this panel has no RACE AGAIN (`_show`)
		self._remoteRaceAgain = nil -- Gamebeast's `TutorialConfig.RaceAgain` for this player, once known
	end,

	start = function(self)
		self:_observeRaceAgain()

		UserInputService.InputBegan:Connect(function(input: InputObject)
			if not IDLE_INPUTS[input.UserInputType] then
				self._lastInputAt = os.clock()
			end
		end)

		--- Every rung's real price, asked now (`priceOf`). One landing while an offer is up redraws
		--- only the caption, so the countdown is left alone.
		for _, tier in ReviveConfig.Tiers do
			LivePrice.fetch(tier.ProductId, nil, function(price)
				if price and self._open and self._offer and self._captionLabel then
					self._captionLabel.Text = self:_caption(self._offer)
				end
			end)
		end

		--[[ The new UI has to wait for its template (`_awaitKit`), and `start` is the boot barrier,
			so it waits on a thread of its own. An offer cannot arrive inside that wait (it takes a
			race and a wreck), and if one somehow did, `_show` builds the screen itself and this
			thread finds it built. ]]
		if UIRoot.isNewUI() then
			task.spawn(function()
				self:_awaitKit()
				if not self._gui then
					self:_build()
				end
				-- The end panel is this panel, so it is offered only once it is in hand.
				if self._wreck and NewUIConfig.EndPanel then
					self:getRemoteEvent("RaceEndOptIn"):Fire()
				end
			end)
			return
		end
		self:_build()
	end,
})

-- HitchProbe (2026-10-06, temporary: Leaf's spike at the getaway truck; see `Modules/HitchProbe`).
ReviveController._showEnd = require(ReplicatedStorage.shared.Modules.HitchProbe).wrap("ReviveController._showEnd", ReviveController._showEnd)

return ReviveController
