--[[
	TutorialController  (client)
	----------------------------
	The onboarding's screen and its hands: a giant arrow at whatever the current beat is talking
	about, a card naming that beat WHEN THE ARROW CANNOT SAY IT ALONE, and — on three of the eight —
	the whole world held still until the player makes the input being asked for.

	THE ARROW IS THE PRIMARY AND THE CARD IS THE FALLBACK, which is the opposite of how this started.
	A beat that points at a button is a beat whose instruction is "press the thing with the enormous
	red arrow bouncing on it", and a panel repeating that in words is a second instruction for a
	decision already made — so those beats are POINTER ONLY (`Card = false` in `TutorialConfig`, and
	`_setCardShown` here). The card survives on the beats no arrow can draw: which key, which
	direction, what is about to hit you. All of those happen at speed on the road.

	IT DECIDES WHAT IS DRAWN, NEVER WHAT COMES NEXT. The sequence is `TutorialService`'s, it arrives
	over `TutorialState`, and this file draws it. What this file DOES own, which the old tracker
	version did not, is the two things that only a client can witness:

	  • the INPUT beats — held accelerate, two lane changes, eight seconds survived, the jump. It
	    watches for them and reports them over `TutorialBeat`; the server checks the report names
	    the live beat and advances. See `TutorialService`'s header for why that boundary is safe.
	  • the FREEZE and the GATE — the two ways this feature stops the player doing anything except
	    the thing it is teaching.

	=== THE FREEZE ============================================================================

	Three of the eight stop the world: BOOST, BAIL and AIRBORNE. All three ask for a key the player has
	never pressed, and two of them ask for it at 50 studs/s in traffic.

	The stopping is `RaceFreezeController`'s and nothing about it lives here — this file decides
	WHEN, that one knows HOW (time scale for the scripts, anchors for the solver). What is here is
	the discipline around it, which is the part that bites:

	  • ONE HOLD NAME, `FREEZE_KEY`, for every beat. Beats abut — AIRBORNE arms while BAIL's own
	    hold is still coming off — and a name that varied per beat would leave two holds counting
	    against each other with no single release.
	  • RELEASED FROM EVERY EXIT, not just from the beat completing. A wreck, a race ending, the
	    card being suppressed, the server closing the tutorial and the controller tearing down all
	    drop it. A frozen world with nothing on screen explaining it is the worst bug this feature
	    could ship, so the release is unconditional and repeated rather than balanced.
	  • AND IT TIMES OUT ON ITS OWN (`FREEZE_TIMEOUT`), which matters more than it used to. The card
	    carried a SKIP word until this pass and that was the stuck player's way out; with the word
	    gone the timeout is the only one, so it is a real backstop rather than a formality.
	  • NEVER APPLIED IN THE LOBBY. `Where` says which half of the game a beat is in and only the
	    race half may freeze; there is no motion in a lobby to stop, and a hold there would anchor a
	    car that is not in a race.

	=== THE GATE ==============================================================================

	The lobby's version of the same idea, and it is INPUT rather than time. A beat with `Gate =
	"Input"` makes the button it is pointing at the only one that does anything: every other tagged
	`UIButton` press is refused, and the arrow bumps to say where to go instead.

	IT IS REFUSED AT THE ACTION, NOT AT THE INPUT. `ButtonPress.press` — the one place a tagged
	press means anything, for a mouse, a touch and a gamepad alike — asks `blocksPress` before it
	does anything, and this file answers. Nothing is made inactive, nothing is covered, and no
	property on anybody else's button is written or has to be put back.

	The version before it turned `Active` off on every other button, which refused the press
	correctly and then had nowhere to say so: an inactive GuiButton does not pass the click on to
	whatever is behind it, so a catcher underneath never heard a thing. Measured, not assumed.

	IT BUMPS RATHER THAN DOING NOTHING, which is the whole difference between a tutorial and a bug.
	A press that is silently eaten reads as a broken button; a press that throws the arrow at the
	right button reads as being redirected. Same refusal, opposite conclusion.

	=== THE ARROW =============================================================================

	Big, red, and a real arrow: `UIAssets.Tutorial.Arrow`, drawn in Photoshop for this because the
	kit has none. It was a chevron built from three rounded bars first and it read as a BRACKET
	— this thing's whole job is being recognised by somebody who is not yet looking for it, and a
	shape you have to resolve before you can follow it fails at exactly that.

	RED RATHER THAN THE BRAND BLUE, because this game's ground is cyan — forecourt, road, sky — and
	a blue pointer over it is a pointer nobody finds. It is the one hue that differs from everything
	the game puts behind it, the gold PLAY face included. See `UIAssets`.

	IT IS ONE OBJECT THAT TRAVELS. The board card asks for the arrow to "animate to the play button
	on world 1" rather than cut, and that is not decoration: a pointer that moves carries the eye to
	the next press, where one that teleports makes the player find it again. So the arrow is built
	once, and every retarget is a tween of the same instance.

	It also BOBS toward what it is naming, which is what makes it findable in peripheral vision by
	somebody who is not yet looking for it. That is the whole reason the old version — a thin ring
	drawn around the button — was replaced: a ring is legible only once you have already found the
	button it is around.

	And the target PULSES underneath it, a six percent scale breath. Deliberately small: the arrow
	is the thing doing the finding, and a button pumping hard next to it reads as two things
	competing rather than one thing being named.

	=== WHERE THE CARD SITS ===================================================================

	When there is one. Top-LEFT whenever it has nothing on screen to sit above, and beside whatever
	it is naming when it does. `_place` has the full argument and the candidate order.

	It was top-RIGHT until 2026-10-06, on the argument that Roblox owns the top-left (logo, hamburger,
	chat toggle, and the chat window that drops out of it). Leaf's playtest overruled that: on the
	right the card sat over the road on the BOOST and GET AWAY WITH IT beats ("def on the left cuz
	this is annoying"). It still rests UNDER Roblox's bar (`topGuard`), so only an open chat window
	can overlap it. `TutorialConfig.CardSide` = "Right" puts it back.

	=== ON THE NEW UI, THE CARD IS THE KIT'S ==================================================

	With `UIRoot.isNewUI()` the card is not built here. It is cloned off the `MainUIV2.Screens`
	shelf (`TutorialCard`, made by the `BuildTutorialCardV2` command out of the kit's `TutorialUI`)
	into this same gui, and it is the ONLY thing that moved: the dim, the arrow, the world chip, the
	freeze, the gate and every beat are this file's exactly as before, and `_place` places the kit's
	card by the same `AbsoluteSize` it placed the old one by. See `_useKitCard`.

	The kit's card wears the objective on the rim, where the kit put a speaker's name, and the hint
	in the white body. It fades as one CanvasGroup rather than label by label, because its labels
	are outlined and an outline outlasts its letters (`_fadeText`), and its hint rests at full
	strength rather than dimmed, for the same reason. So four methods branch on `_kit`, and only for
	how things fade: `_show`, `_hide`, `_rest` and `_stamp`.

	A place with no template on the shelf gets the code-built card and a warning, not no card: this
	is the new player funnel, and an old-looking card is a much smaller failure than a silent one.

	HOUSE RULE: no wiki-style double-bracket links in these comments — the closing pair ends the
	block comment early and the parse error points at the wrong line.
]]

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

--- For one event: the screen a run ended on having finished lifting. See `_boot`.
local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local GameplayFeedback = require(ReplicatedStorage.shared.Modules.GameplayFeedback)
local Shard = require(ReplicatedStorage.Packages.Shard)
--- For the boost ceiling the BOOST meter's target may not pass. See `_barTarget`.
local DriveConfig = require(ReplicatedStorage.shared.Configs.DriveConfig)
local GamepadConfig = require(ReplicatedStorage.shared.Configs.GamepadConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local PlotConfig = require(ReplicatedStorage.shared.Configs.PlotConfig)
--- ...and for that event's name, which is the only thing read out of it here.
local RaceConfig = require(ReplicatedStorage.shared.Configs.RaceConfig)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
--- The finish card's confetti: the NEW BEST reveal's paper and its tuning. See `_paintFinish`.
local ScreenConfetti = require(ReplicatedStorage.shared.Modules.ScreenConfetti)
local ShowcaseConfig = require(ReplicatedStorage.shared.Configs.ShowcaseConfig)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)
--- Turns the camera toward the tutorial's buyer as they walk in. See `_stepLook`.
local CameraFacing = require(ReplicatedStorage.shared.Modules.CameraFacing)

local TutorialController = Shard.new("TutorialController")

-- === Look & feel ============================================================

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)
local WHITE = Color3.fromRGB(255, 255, 255)
-- The pointer's red and the dark border that carries it over road, sky, a gold PLAY button or a navy
-- panel are baked into the arrow ART now rather than mixed here -- see `UIAssets.Tutorial`. Nothing
-- in this file draws a shape by hand any more.
-- ...and the payout green, borrowed for one word: DONE.
local CASH_GREEN = Color3.fromRGB(126, 217, 87)

--[[ The card. Wider than it is tall, and NOT on the panel's own aspect — `Page.Panel` is 9-sliced
	(see `UIAssets.Slice`), so it stretches to any box without the corners deforming, and an
	objective card at the panel's 1.59:1 would be a quarter of the screen deep.

	SHORTER THAN IT WAS by the height of the title bar it no longer carries (0.145). The two lines
	are the whole card now, so the panel is sized to them rather than to them plus a cap — and the
	fractions below give each line back the share the bar was taking, which keeps the words the same
	number of pixels tall as before rather than shrinking them with the box. ]]
local CARD_SIZE = UDim2.fromScale(0.27, 0.125)

--[[ How far down Roblox's own bar reaches, and the daylight kept under it. BOTH ARE PIXELS, because
	the bar is: a guard written as a fraction of the viewport clears the bar on a tall window and
	sits under it on a short one. `GuiService:GetGuiInset()` is asked for the real number with
	`TOPBAR_MIN` as a floor, since the reported inset is the legacy 36px on clients whose bar draws
	taller than that. ]]
local TOPBAR_MIN = 54
local TOPBAR_PAD = 10
local EDGE_MARGIN = 0.017 -- the margin at the sides and the bottom
--- Which side the card rests on (`TutorialConfig.CardSide`). See the header's WHERE THE CARD SITS.
local CARD_LEFT = TutorialConfig.CardSide ~= "Right"
--[[ Between the card and the thing it is naming, as a fraction of the viewport's height — plus,
	live, whatever the arrow currently sticks out by. The arrow is much bigger than the ring it
	replaced, so a fixed gap that cleared the old pointer lands the card inside the new one. ]]
local CARD_GAP = 0.018
--- Seconds a NEW target is given to finish opening before the card picks a spot by it, and the share of the
--- way to that spot the card moves each frame (`_place`, 2026-10-20).
local PLACE_SETTLE = 0.3 -- a page scales open over about 0.25s
local PLACE_GLIDE = 0.22

--[[ How far down THIS GUI'S OWN SPACE Roblox's bar reaches, in pixels.

	`GetGuiInset` is measured against the raw viewport; `originY` — `_root.AbsolutePosition.Y` — is
	how far this gui has already been pushed down by that same inset. Subtracting one from the other
	is correct either way round: a gui that ignores the inset reports origin 0 and has to clear the
	whole bar here, and one that respects it is already past the bar and has only the padding left
	to add. ]]
local function topGuard(originY: number): number
	local inset = GuiService:GetGuiInset()
	return math.max(math.max(inset.Y, TOPBAR_MIN) + TOPBAR_PAD - originY, 0)
end

--[[ Fractions of the CARD, top to bottom, and there are only two things in it.

	CENTRED AS A BLOCK rather than each line placed against an edge: the objective's box runs 0.17 to
	0.45 and the hint's 0.51 to 0.83, which puts the pair's middle on 0.5 with matched daylight above
	and below. That is the whole layout — a plain panel with the words in the middle of it.

	THE HINT GETS THE TALLER BOX of the two even though it is the smaller text, because it is the one
	that WRAPS: `TextScaled` on a wrapping label would sooner take a second line than pick a smaller
	font, and on a phone the hint names two keys. Room for that second line is room the objective,
	which is written through `oneLine`, can never need. ]]
local TITLE_Y = 0.31
local TITLE_H = 0.28
local HINT_Y = 0.67
local HINT_H = 0.32

--[[ THE KIT'S CARD, on the new UI. Where the template is and what its three labels are called, which
	is the whole contract with `BuildTutorialCardV2`: the labels are found by NAME anywhere in the
	card, so the art can be rearranged in the Explorer without a line changing here. ]]
local KIT_SHELF = "Screens"
local KIT_TEMPLATE = "TutorialCard"
local KIT_OBJECTIVE = "Objective"
local KIT_HINT = "Hint"
local KIT_DONE = "Done"
--- Seconds to wait for each of the two hops. Both arrive with `MainUIV2` itself, so this only ever
--- runs out in a place that does not have the template, and then the old card is drawn instead.
local KIT_WAIT = 5

--[[ The hint's type, at most this fraction of the objective's band.

	`TextScaled` makes the BIGGEST text that fits, and the kit's body is three times the band's height
	once its buttons are gone, so a short hint ("Catch it and drive up the ramp") would be set larger
	than the objective above it. The hint's `UITextSizeConstraint.MaxTextSize` is the ceiling, and it
	is worked out from the band's rendered height so it holds at every screen size. ]]
local KIT_HINT_SCALE = 0.8

--[[ How much of a fade a text OUTLINE takes when the text is leaving. A `UIStroke` is drawn under
	the whole glyph, so a half-faded letter shows its own dark outline through it and reads grey, and
	the dark ring outlasts the white letter on a bright background. The outline goes in the first
	half and the letter takes the whole time. ]]
local KIT_STROKE_FADE = 0.5

--[[ THE METERS UNDER THE CARD, in the kit's progress bar colours: a navy track with a dark outside
	border, a blue pill of fill and an outlined label across both, the same bar the Flow meter is
	built from (`NearMissConfig.Flow` has the measurements). A finished meter steps to the kit's
	orange rather than blending, because every point between blue and orange is grey.

	The two ratios are the mockup's: a 60px bar with a 5px outside stroke and a 27px corner. ]]
local BAR_TRACK = Color3.fromRGB(35, 39, 53) -- #232735
local BAR_STROKE = Color3.fromRGB(21, 29, 45) -- #151D2D
local BAR_FILL = Color3.fromRGB(0, 102, 255) -- #0066FF
local BAR_FULL = Color3.fromRGB(255, 162, 0) -- #FFA200
local BAR_STROKE_RATIO = 5 / 60
local BAR_CORNER_RATIO = 27 / 60

--- The world chip's bob, in studs, and its period. Slower than the screen arrow's: a thing in the
--- world is read from further away, where a fast bob reads as a jitter.
local BOB_STUDS = 0.6
local BOB_PERIOD = 1.6

--[[ How many studs the mid-air arc has to start OPENING again before the AIRBORNE beat calls it the
	closest approach and stops the world. See `_watchFreeze`.

	Small, because the arc is scripted rather than simulated and its distance to a car is therefore a
	smooth curve with no noise in it at all — this is a guard against a frame landing exactly on the
	turn, not against jitter. Big enough to be more than a float's worth, small enough that at the
	~0.3 studs a frame the descent moves near touchdown it costs at most a frame of lateness. ]]
local AIR_TURN = 0.05

--[[ Where the chip floats, and it is NOT one height — it is derived from how big the thing is,
	which was found the hard way in a playtest, twice. A fixed height above the part's centre is
	right for the collect mat (a flat pad) and wrong for anything tall, where it lands above its own
	roofline and off the top of the screen for somebody standing in front of it.

	So a SHORT target gets its chip overhead, and a TALL one gets it hung under its bottom edge,
	clear of whatever is written on the face. Both read as "here"; only the short one can afford to
	be read as "up there".

	...UNLESS THE TARGET SAYS `Above`, which is the truck and only the truck. That rule is a
	NEAR-FIELD one — it is about a thing you are standing under — and the truck is the one world
	target you are never near: it turns up three hundred studs out and you spend the whole beat
	behind it. Hung under its bottom edge it lands in the middle of the windscreen, over the road
	you are steering down, which is exactly what it looked like in a playtest. Overhead it sits in
	the empty sky above the trailer and points down at the roof. ]]
local CHIP_TALL = 5 -- half-height past which a target counts as something you stand AT, not under
local CHIP_CLEAR = 4 -- studs above a short target's top
local CHIP_DROP = 1.5 -- ...and below a tall one's bottom edge

--- How big the chip is, at the reference distance below. Offset rather than scale, so the size is
--- ours to set per frame rather than the projection's — see `CHIP_REF_STUDS`.
local CHIP_SIZE = UDim2.fromOffset(240, 132)

--[[ HOW THE CHIP SHRINKS WITH DISTANCE, and why it does it by hand.

	A billboard sized in OFFSET is a constant number of pixels at every range, which is right for a
	thing you walk up to and wrong for the truck: at three hundred studs the truck is a smudge on
	the horizon and a full-size chip is a banner across the middle of the screen, with no relation
	to the thing it is naming. Sized in SCALE it would be honest — studs, projected — but then it is
	unreadable at the far end and fills the screen at the near one.

	So it is neither: full size at `CHIP_REF_STUDS` from the camera, smaller as the target pulls
	away, and never past the two ends. `CHIP_MIN_SCALE` is a LEGIBILITY floor rather than a taste
	one — the title is scaled text in a box under a third of this wide, and below about this it
	stops being a word and starts being a smudge of its own. The ceiling is 1 because the size
	authored here is already the biggest the chip has any business being.

	Measured from the CAMERA and not from the character, because apparent size is a camera fact; the
	distance the chip PRINTS is the character's, because that is the one the player is driving. ]]
local CHIP_REF_STUDS = 80
local CHIP_MIN_SCALE = 0.6

--[[ The outline under the distance line, and that line is the only thing in the chip that wants
	one: the title rides an orange pill and the arrow is a solid shape of its own, but the distance
	is bare white text hanging in the world with nothing behind it.

	Over tarmac or sky it reads on its own. Over the TRUCK it does not — the truck is white, and the
	truck is what the chip points at for the whole chase, so the one beat that prints a distance for
	hundreds of studs is also the one that prints it onto a white trailer.

	DELIBERATELY THIN. This is the small print under the title, and an outline heavy enough to be
	noticed on its own would make it compete with the thing it is annotating; all it has to do is
	give the glyphs an edge where they meet a pale background. `Contextual` for the same reason —
	the stroke then meets the glyph only at the background rather than fattening the letterforms,
	which at the far end of the shrink is the difference between text and a smudge.

	Thickness is quoted at the FULL chip size and scaled down with the rest of it in `_chipRide`, so
	the outline stays the same fraction of the text at every distance instead of thickening into it
	as the chip pulls away. The colour is the near-black the near-miss toasts outline with, so
	world-facing text is edged the same way wherever it turns up. ]]
local CHIP_STROKE = 1.5
local CHIP_STROKE_COLOR = Color3.fromRGB(6, 8, 12)

--[[ The tangent of the angle above the eye an overhead chip may sit at — see `_chipRide`, and it is
	a good deal tighter than "inside the frame" for two reasons that stack.

	THE RACE CAMERA LOOKS DOWN. `CameraConfig` pitches it 17 degrees under a 70-degree field, so the
	top of the frame is only 18 degrees above horizontal rather than the 35 a level camera would
	give — barely half the headroom the number looks like it has.

	AND THE CHIP IS NOT A POINT. Its anchor is the middle of a box whose top edge is half a chip
	higher, which is about another 8 degrees at the full size and at a typical viewport.

	Eight degrees for the anchor, then, which leaves the box's top edge inside the frame with room
	to spare at any window shape a player is likely to have. ]]
local CHIP_RISE = 0.14
--[[ The pill's share of that box, DERIVED from the art rather than typed, so the chip's one image
	keeps the 3.89:1 the artist drew it at. It is stretched, not sliced (see `UIAssets.Slice.Pill`),
	and a stretch is only honest while the box holds the aspect. ]]
local CHIP_PILL_HEIGHT = (CHIP_SIZE.X.Offset / (UIAssets.Size.Pill.X / UIAssets.Size.Pill.Y)) / CHIP_SIZE.Y.Offset
--[[ A chip over a BUYER (`OverSign`) gives way to the offer sign over their head once it shows: the
	sign is sized in studs and the chip in pixels, and stacking the chip above it put the chip off the
	top of a phone screen at 32 studs (measured 2026-10-06). The sign is the bigger marker anyway, and
	`BUYER_GLOW` keeps the customer outlined for the whole beat. ]]
local BUYER_TAG = "Buyer"
local BUYER_OWNER = "BuyerOwner"
local BUYER_SIGN = "BuyerSign"
--- True once the buyer is standing at the car (`CustomerService`'s `BUYER_ATTRIBUTES.Arrived`).
local BUYER_ARRIVED = "BuyerArrived"
--- The kit's PLAY gold, the colour the bay glow wears for "this is the thing to go to".
local BUYER_GLOW = Color3.fromRGB(255, 198, 0)
--[[ The outline's fill breathes between these two transparencies on `TutorialConfig.Pulse.Period`
	(2026-10-19, Dylan: "highlight the npc so they open the offer"): a still outline in a lot full of
	cars read as part of the scene. The outline itself stays solid. ]]
local BUYER_GLOW_FILL = { 0.85, 0.5 }

--[[ One name for every hold this feature places on the world, whichever beat placed it. Beats abut
	— AIRBORNE arms while BAIL's hold is still coming off — and a name per beat would leave two
	holds counting against each other with no single release. See the header. ]]
local FREEZE_KEY = "Tutorial"

--[[ How long a freeze may last before it lets go on its own, in seconds.

	A BACKSTOP AND NOT A TIMER. Every beat has a real release — the input arrives, the beat is
	skipped, the race ends — and this is what covers the case none of those reach: a player who
	alt-tabs, a device with no way to send the input the card is naming, a bug in the arming
	condition. It can only ever fire on a genuinely stuck player, and what it does then is give them
	their game back rather than leave them staring at a stopped road.

	IT LATCHES, AND UNTIL IT DID IT WAS NOT A BACKSTOP AT ALL. `_watchFreeze` re-applies a frozen
	beat's hold on every frame it is not held, so the release this fires was undone on the next one
	and all the player got was a warning in a log they cannot see. Measured in a playtest: the same
	warning three minutes apart, twice, with the world still stopped between them. So the forfeit is
	remembered per beat (`_freezeForfeit`) and that beat may not freeze again — it stays up, and its
	input still completes it, but it no longer holds the world to ask.

	AND IT IS MUCH SHORTER THAN THE THREE MINUTES IT WAS. Three minutes was chosen as "longer than
	any beat has ever taken", which is the right shape for a timer nobody is waiting on — but a
	player whose input cannot reach the card IS waiting on it, at a dead stop, with nothing on screen
	admitting anything is wrong. Half a minute is still several times the longest a beat has taken.

	=== A MINUTE NOW — 2026-10-16 ===
	WAS 30. A young phone playtester spent ~30s on JUMP OUT looking for the button, so the backstop
	was letting go on a player who was still working it out, and the car drove off under a card
	still asking for the jump. With the arrow on the thumb button (`TutorialConfig` `bail`'s
	`Target`) they find it sooner, and 60 still frees a genuinely stuck player inside a minute. ]]
local FREEZE_TIMEOUT = 60

--- How long before a world target that could not be found is looked for again. See `_retryPoint`.
local POINT_RETRY = 0.5

--[[ A `Follow` target (see `TutorialConfig`'s vocabulary) is one whose answer can become a DIFFERENT
	OBJECT while the beat is up, so it is asked again on this interval rather than resolved once.

	IT IS NOT FREE — a re-resolve walks the lot's podiums — so it runs three times a second rather
	than sixty, which is far finer than a walking player can outpace and cheap enough not to think
	about.

	`FOLLOW_MARGIN` is the hysteresis, and without it this flickers. A player stood midway between
	two podiums crosses the tie every few frames, and each crossing is a billboard destroyed and
	rebuilt on the other slab. So the bay already being named keeps the chip until another is
	properly closer, which means the answer only changes once the player has clearly committed to
	walking at a different one. ]]
local FOLLOW_INTERVAL = 0.35
local FOLLOW_MARGIN = 6

-- Non-breaking, because `TextScaled` would sooner break a caption onto a second line than pick a
-- smaller font. Every one-line label on this card is written through this.
local NBSP = utf8.char(0xA0)

local function oneLine(text: string): string
	return (string.gsub(string.upper(text), "%s+", NBSP))
end

--[[ Would anything cut off something drawn outside `object`? Walks up to the ScreenGui, because the
	clipper is rarely the button itself — on the SELECT CAR screen it is the `ScrollingFrame` two
	hops above the card, which clips because a scroll window has to. ]]
local function clipped(object: GuiObject): boolean
	local node: Instance? = object.Parent
	while node and not node:IsA("ScreenGui") do
		if node:IsA("GuiObject") and node.ClipsDescendants then
			return true
		end
		node = node.Parent
	end
	return false
end

--- 9-slice from the recorded texture size and inset, both out of `UIAssets` — which is measured
--- against what Roblox STORED rather than against the PSD. See the warning on `UIAssets.Size`.
local function slice(image: ImageLabel | ImageButton, size: Vector2, inset: number)
	image.ScaleType = Enum.ScaleType.Slice
	image.SliceCenter = Rect.new(inset, inset, size.X - inset, size.Y - inset)
end

-- === Building ===============================================================

function TutorialController._build(self)
	local gui = Instance.new("ScreenGui")
	gui.Name = "Tutorial"
	gui.ResetOnSpawn = false
	--[[ Matched to `MainUI` so this card, the arrow and the HUD they point at are laid out in the
		same space. It matters more than it did when the pointer was parented to its target: the
		arrow is positioned in THIS gui against an `AbsolutePosition` read out of that one, and two
		overlays that disagree about where the top of the screen is will not line up. ]]
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	--[[ Above the driving HUD (895) and the HP bar (900) so it is readable mid-race, and BELOW the
		welcome-back panel (998), the respawn screen (999) and the race fade (1000). Those three own
		the moments they are up, and this stands down for all of them anyway — the ordering makes
		that true by construction rather than by timing. ]]
	gui.DisplayOrder = 950
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	--[[ A full-screen root everything is positioned INSIDE, so placement can work in one space.
		The arrow and the card both read a target button's `AbsolutePosition`, which is a screen-space
		number out of a DIFFERENT ScreenGui — subtracting this frame's own `AbsolutePosition` converts
		it exactly, whatever the safe-area insets did to either. ]]
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Parent = gui

	--[[ THE DIM, first and therefore underneath. One flat sheet at low opacity, shown only while a
		beat is holding the world still.

		NOT `Active`, and that is deliberate even though this is the one thing on the card that could
		argue for it. The freeze already stops everything a stray press could affect, and a sheet
		that ate input would also eat the press this beat is waiting for on a touch device — where
		the accelerate pedal is a button under exactly this rectangle.

		=== ITS OWN SCREENGUI, UNDER THE DRIVING HUD — 2026-10-16 ===
		WAS a child of `root`, so it lay over everything below this gui's 950, the race's thumb
		buttons (`DrivingHud`, 895) included: the JUMP button the arrow points at was dimmed with the
		road. IS a gui at 890, so the order is dim, then the driving HUD, then the card and the arrow.
		The thumb buttons the beat is not asking for still recede, through
		`TutorialControlHighlight`'s own fade. Always enabled: `Visible`, through `_dimTo`, is what
		shows it, and every hide of the card releases the freeze and so the dim with it. ]]
	local dimGui = Instance.new("ScreenGui")
	dimGui.Name = "TutorialDim"
	dimGui.ResetOnSpawn = false
	dimGui.IgnoreGuiInset = true
	dimGui.ScreenInsets = Enum.ScreenInsets.None
	dimGui.DisplayOrder = 890
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Visible = false
	dim.ZIndex = 0
	dim.Parent = dimGui
	dimGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	--[[ THE ARROW, built once and moved for the rest of the session — see the header on why it
		travels rather than cuts. A square box that gets rotated; the art inside it points DOWN, so
		a rotation of 0 is an arrow pointing at whatever is below it.

		ONE IMAGE, NOT A STACK OF FRAMES. This was a chevron assembled from three rounded bars while
		there was no arrow in the kit, and it read as a bracket rather than as a pointer — the thing
		it is for is being recognised instantly by somebody who is not looking for it, and a shape
		you have to resolve first fails at exactly that. `UIAssets.Tutorial.Arrow` is a real arrow
		drawn for this; the note there covers why it is square, centred, and lit along its own axis.

		`Stretch` is safe here where it usually is not: the art is square, `_aimArrow` only ever
		hands this a square box, and nothing about it is 9-sliced. ]]
	local arrow = Instance.new("ImageLabel")
	arrow.Name = "Arrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.BackgroundTransparency = 1
	arrow.BorderSizePixel = 0
	arrow.Image = UIAssets.url(UIAssets.Tutorial.Arrow)
	arrow.ScaleType = Enum.ScaleType.Stretch
	arrow.Visible = false
	arrow.ZIndex = 3
	arrow.Parent = root

	--- Where the arrow rests, and which way it points at what it is naming. The bob and the travel
	--- tween both write `Position`, so the bob rides as an offset from `_arrowHome` along
	--- `_arrowAxis` rather than fighting the tween. See `_aimArrow`.
	self._arrowHome = Vector2.zero
	self._arrowAxis = Vector2.new(0, 1)
	--- `os.clock()` at which the travel tween is over and the bob may take `Position` back...
	self._arrowRestAt = 0
	--- ...and the clock the bob's SINE is measured from, which is that same moment. Anchored rather
	--- than free-running so the swing is zero on the frame the bob takes over — see `_ensureLoop`.
	self._bobFrom = 0
	--- The CENTRE of the box the arrow was last aimed at, in `_root`'s space. What the frame loop
	--- compares against to notice a target that has moved under it, and it has to be the target
	--- rather than the arrow -- see the note in `_ensureLoop`.
	self._aimAt = nil

	self._gui = gui
	self._root = root
	self._dim = dim
	self._arrow = arrow

	--- Before the card, and outside it: the kit's card is a CanvasGroup, which clips anything hung
	--- past its own edge. See `_buildMeters`.
	self:_buildMeters(root)

	--[[ THE CARD. On the new UI it is the kit's, cloned off the shelf, and everything after this
		branch is the code-built one: the old UI's card, and the new UI's fallback when the template is
		not in the place. See `_useKitCard` and the header. ]]
	if UIRoot.isNewUI() and self:_useKitCard(root) then
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		return
	end

	--[[ NOT `Active`, and nothing under it is either. Every other panel this project builds swallows
		input behind itself; this one must not. It is a card sitting over a live game — during a race
		there is a car being steered underneath it — and a card that ate a touch would be a card that
		occasionally cost somebody a steal. With SKIP gone there is no longer anything on it that
		takes a press at all, which is the version of that rule with nothing to get wrong. ]]
	local card = Instance.new("ImageLabel")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0, 0)
	-- The resting spot, written in scale for the one frame before `_place` has an `AbsoluteSize` to
	-- work from. It is invisible then; this only keeps it from being invisible in the wrong corner.
	card.Position = UDim2.fromScale(if CARD_LEFT then EDGE_MARGIN else 1 - EDGE_MARGIN - CARD_SIZE.X.Scale, 0.1)
	card.Size = CARD_SIZE
	card.BackgroundTransparency = 1
	card.Image = UIAssets.url(UIAssets.Page.Panel)
	card.ImageTransparency = 1
	card.ZIndex = 5
	slice(card, UIAssets.Size.Panel, UIAssets.Slice.Panel)
	card.Parent = root

	--[[ NO TITLE BAR. The card used to open with the kit's orange cap across the top, carrying
		"GETTING STARTED 3/8" on the left and SKIP on the right, and both of those went at once
		because the bar was the only reason either had a place to live. `TutorialConfig`'s copy block
		has the argument; what is left here is a plain panel with two lines centred in it. ]]

	local title = Instance.new("TextLabel")
	title.Name = "Objective"
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, TITLE_Y)
	title.Size = UDim2.fromScale(0.9, TITLE_H)
	title.BackgroundTransparency = 1
	title.FontFace = FONT
	title.Text = ""
	title.TextColor3 = WHITE
	title.TextTransparency = 1
	title.TextScaled = true
	title.Parent = card

	--- Punched when a new objective arrives, so a beat changing is something that happens.
	local titleScale = Instance.new("UIScale")
	titleScale.Parent = title

	--[[ The how-to line. WRAPS where the objective does not: it is a sentence rather than a
		headline, and `TextScaled` on a wrapping label shrinks to fit two lines, which is what is
		wanted for a hint that names two keys on a phone. ]]
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0.5, 0.5)
	hint.Position = UDim2.fromScale(0.5, HINT_Y)
	hint.Size = UDim2.fromScale(0.86, HINT_H)
	hint.BackgroundTransparency = 1
	hint.FontFace = FONT
	hint.Text = ""
	hint.TextColor3 = WHITE
	hint.TextTransparency = 1
	hint.TextScaled = true
	hint.TextWrapped = true
	hint.Parent = card

	--[[ The DONE stamp, over the objective it replaces rather than beside it. Hidden at rest and
		never faded with the card — it is a beat, not a field, and it owns its own timing. ]]
	local done = Instance.new("TextLabel")
	done.Name = "Done"
	done.AnchorPoint = Vector2.new(0.5, 0.5)
	done.Position = UDim2.fromScale(0.5, TITLE_Y)
	done.Size = UDim2.fromScale(0.9, TITLE_H)
	done.BackgroundTransparency = 1
	done.FontFace = FONT
	done.Text = oneLine(TutorialConfig.DoneText)
	done.TextColor3 = CASH_GREEN
	done.TextTransparency = 1
	done.TextScaled = true
	done.Visible = false
	done.Parent = card

	local doneScale = Instance.new("UIScale")
	doneScale.Parent = done

	self._card = card
	self._title = title
	self._titleScale = titleScale
	self._hint = hint
	self._done = done
	self._doneScale = doneScale

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

--[[ Clone the kit's card off `MainUIV2.Screens` into `root`, and give it the six fields the rest of
	this file draws through. False, with a warning, when there is no template to clone, and then
	`_build` carries on and builds the old card.

	THE SAME SIX FIELDS, SO NOTHING ELSE HAS TO KNOW. `_paint`, `_writeHint`, `_place`, `_bump` and
	`_setCardShown` write `Text`, `Visible`, `Position` and a `UIScale` and read `AbsoluteSize`, all of
	which a CanvasGroup and three TextLabels have. `_kit` is set only here, and it is what the four
	fade methods ask.

	WHAT IS ASSERTED RATHER THAN AUTHORED: the top-left anchor (`_place` writes the card's corner in
	pixels), the ZIndex the old card sat at (over the arrow and the dim), and a card that starts
	invisible. The template is authored fully opaque so it reads correctly in the Explorer.

	NOTHING ON IT IS PRESSABLE, and a template that has grown a button since is told about rather
	than stripped: a press the card cannot honour is a design question, and deleting somebody's edit
	at runtime would hide it. ]]
function TutorialController._useKitCard(self, root: Frame): boolean
	local shelf = self._mainUI and self._mainUI:WaitForChild(KIT_SHELF, KIT_WAIT)
	local template = shelf and shelf:WaitForChild(KIT_TEMPLATE, KIT_WAIT)
	if not (template and template:IsA("CanvasGroup")) then
		self.log:warn(
			string.format(
				"The new UI is on but there is no %s.%s CanvasGroup (run BuildTutorialCardV2). The tutorial draws its old card instead.",
				KIT_SHELF,
				KIT_TEMPLATE
			)
		)
		return false
	end

	local card = template:Clone() :: CanvasGroup
	local title = card:FindFirstChild(KIT_OBJECTIVE, true)
	local hint = card:FindFirstChild(KIT_HINT, true)
	local done = card:FindFirstChild(KIT_DONE, true)
	if not (title and title:IsA("TextLabel") and hint and hint:IsA("TextLabel") and done and done:IsA("TextLabel")) then
		self.log:warn(
			string.format(
				"%s.%s has no `%s`, `%s` or `%s` TextLabel. The tutorial draws its old card instead.",
				KIT_SHELF,
				KIT_TEMPLATE,
				KIT_OBJECTIVE,
				KIT_HINT,
				KIT_DONE
			)
		)
		card:Destroy()
		return false
	end
	for _, object in card:GetDescendants() do
		if object:IsA("GuiButton") then
			self.log:warn(
				string.format("%s.%s holds a button (%s); nothing on this card may take a press.", KIT_SHELF, KIT_TEMPLATE, object.Name)
			)
		end
	end

	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0, 0)
	-- The resting spot, for the frame before `_place` has a size to work from. See the old card's.
	card.Position = UDim2.fromScale(if CARD_LEFT then EDGE_MARGIN else 1 - EDGE_MARGIN - card.Size.X.Scale, 0.1)
	card.ZIndex = 5
	card.Visible = true
	card.GroupTransparency = 1

	title.Text = ""
	hint.Text = ""
	done.Text = oneLine(TutorialConfig.DoneText)
	done.Visible = false

	--- The punch reuses a `UIScale` the art already has, for `_pulseOn`'s reason: Roblox honours only
	--- the first one on an object.
	local function scaleOn(label: TextLabel): UIScale
		local scale = label:FindFirstChildOfClass("UIScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Parent = label
		end
		return scale
	end

	local hintCap = hint:FindFirstChildOfClass("UITextSizeConstraint")
	if not hintCap then
		hintCap = Instance.new("UITextSizeConstraint")
		hintCap.Parent = hint
	end

	card.Parent = root

	self._card = card
	self._title = title
	self._titleScale = scaleOn(title)
	self._hint = hint
	self._done = done
	self._doneScale = scaleOn(done)
	self._kit = { hintCap = hintCap }

	--- The band is laid out again on every resize, and a disabled gui has no size at all, so the
	--- ceiling is re-derived whenever the band's own size moves. See `KIT_HINT_SCALE`.
	title:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_fitKitHint()
	end)
	self:_fitKitHint()

	--[[ SMALLER ON A PHONE (2026-10-13, punch list M3: "tutorial looks shit", on a phone screenshot).
		The template's scale size is a third of a landscape phone's width, its title spills over the
		top edge and the meters hung under it run down the left side. One `UIScale` on the card
		(`TutorialConfig.TouchCardScale`); the meters and `_place` are measured off the card's
		AbsoluteSize, so they shrink with it. Re-read live, so a paired keyboard gets full size back. ]]
	local cardScale = scaleOn(card)
	local function fitTouch()
		cardScale.Scale = if UserInputService.PreferredInput == Enum.PreferredInput.Touch
			then TutorialConfig.TouchCardScale
			else 1
	end
	fitTouch()
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
		fitTouch()
		--- The words name keys off the same answer (`_keys`), so they are rewritten for the new device.
		self:_refresh()
	end)
	return true
end

--- Cap the kit hint's type under the objective's. See `KIT_HINT_SCALE`.
function TutorialController._fitKitHint(self)
	local kit = self._kit
	local band = self._title and self._title.AbsoluteSize.Y or 0
	if not kit or band <= 0 then
		return -- not laid out yet; the size signal brings us back
	end
	--- ...or under the objective's own ceiling, if the art gives it a lower one than its band.
	local titleCap = self._title:FindFirstChildOfClass("UITextSizeConstraint")
	if titleCap then
		band = math.min(band, titleCap.MaxTextSize)
	end
	kit.hintCap.MaxTextSize = math.max(1, math.floor(band * KIT_HINT_SCALE))
end

--[[ Fade one of the kit card's outlined labels, outline and all. Leaving, the outline goes in the
	first half (`KIT_STROKE_FADE`); arriving, both take the whole time. Returns the letter's tween. ]]
function TutorialController._fadeText(self, label: TextLabel, time: number, to: number)
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		self:_tween(stroke, if to >= 1 then time * KIT_STROKE_FADE else time, { Transparency = to })
	end
	return self:_tween(label, time, { TextTransparency = to })
end

--- ...and set one outright, outline and all.
local function setTextTransparency(label: TextLabel, value: number)
	label.TextTransparency = value
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = value
	end
end

-- === The meters =============================================================

--[[ The live feedback hung under the card on a race beat (`TutorialConfig.Meters`), and there are
	three widgets behind the five kinds: Speed, Timer and Chase all draw on the one bar, Steer has
	two arrows, and Key has a key cap.

	EACH WIDGET IS ONE CANVASGROUP, so it fades as one picture like the kit's card does, and each is
	parented to the root rather than the card for the reason `_build` gives. `_hang` places it under
	the card in pixels every frame it is up, because the card is placed every frame too. ]]

--- Which widget draws each kind.
local WIDGET_OF = { Speed = "bar", Timer = "bar", Chase = "bar", Steer = "arrows", Key = "key" }

--- An unfilled steer arrow: the art multiplied down to near-navy and let through a little, so it
--- reads as an empty slot the same shape as the green that will fill it. A lighter slate was tried
--- first and read as a second, darker green rather than as empty.
local ARROW_EMPTY = Color3.fromRGB(38, 42, 56)
local ARROW_EMPTY_ALPHA = 0.3

local function widgetGroup(name: string, root: Frame): CanvasGroup
	local group = Instance.new("CanvasGroup")
	group.Name = name
	group.AnchorPoint = Vector2.new(0, 0)
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.GroupTransparency = 1
	group.Visible = false
	group.ZIndex = 5
	group.Parent = root
	return group
end

--- White type in the kit's dark outline. The outline's thickness is set by whoever lays it out.
local function outlinedLabel(name: string, parent: Instance): (TextLabel, UIStroke)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.Text = ""
	label.TextColor3 = WHITE
	label.TextScaled = true
	label.ZIndex = 2
	label.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = BAR_STROKE
	stroke.Thickness = 1.5
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	return label, stroke
end

--- UICorner's scale is taken against the SHORTER side, so a ratio is the mockup's radius at any size.
local function rounded(object: GuiObject, ratio: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(ratio, 0)
	corner.Parent = object
end

local function padded(label: TextLabel, vertical: number, horizontal: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(vertical, 0)
	padding.PaddingBottom = UDim.new(vertical, 0)
	padding.PaddingLeft = UDim.new(horizontal, 0)
	padding.PaddingRight = UDim.new(horizontal, 0)
	padding.Parent = label
end

--- The tutorial's arrow art, turned. It points DOWN at rotation 0.
local function arrowImage(parent: Instance, rotation: number): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = "Arrow"
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Image = UIAssets.url(UIAssets.Tutorial.Arrow)
	image.ScaleType = Enum.ScaleType.Stretch
	image.Rotation = rotation
	image.Parent = parent
	return image
end

function TutorialController._buildMeters(self, root: Frame)
	self._widgets = {
		bar = self:_buildBar(root),
		arrows = self:_buildArrows(root),
		key = self:_buildKey(root),
	}
	self:_resetMeters()
end

--[[ The bar: the kit's progress bar (`NearMissConfig.Flow` has the measurements), a navy track with
	a dark outside border, a pill of fill over its left end and an outlined label across both. The
	track sits inset in its group because the border is drawn OUTSIDE the track and the group clips
	whatever falls past its edge. ]]
function TutorialController._buildBar(self, root: Frame)
	local group = widgetGroup("MeterBar", root)

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.fromScale(0.5, 0.5)
	track.BackgroundColor3 = BAR_TRACK
	track.BorderSizePixel = 0
	track.Parent = group
	rounded(track, BAR_CORNER_RATIO)

	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color = BAR_STROKE
	trackStroke.Thickness = 1.5
	trackStroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = BAR_FILL
	fill.BackgroundTransparency = 1
	fill.BorderSizePixel = 0
	fill.Parent = track
	rounded(fill, BAR_CORNER_RATIO)

	local label, labelStroke = outlinedLabel("Label", track)
	label.Size = UDim2.fromScale(1, 1)
	--- Capitals about half the bar tall, which is the mockup's "Time Left".
	padded(label, 0.09, 0.06)

	return {
		group = group,
		on = false,
		token = 0,
		track = track,
		trackStroke = trackStroke,
		fill = fill,
		label = label,
		labelStroke = labelStroke,
	}
end

--[[ The steer arrows: the pointer's own art turned to face left and right, each captioned with the
	key for its direction.

	THE FILL IS A SECOND ARROW BEHIND A GROWING MASK. The empty arrow is the art multiplied down to
	slate; over it sits a CanvasGroup anchored at the arrow's TAIL that widens toward the tip, holding
	the full-colour arrow at the tile's size, so the green sweeps along the arrow the way the car
	moves. A CanvasGroup and not a clipping Frame, because a rotated image escapes `ClipsDescendants`.

	`side` is `DriveController:getSteerInput`'s sign: positive is left. ]]
function TutorialController._buildArrows(self, root: Frame)
	local group = widgetGroup("SteerArrows", root)
	local tiles = {}

	for _, spec in { { side = 1, x = 0.27, rotation = 90, tail = 1 }, { side = -1, x = 0.73, rotation = -90, tail = 0 } } do
		local tile = Instance.new("Frame")
		tile.Name = if spec.side == 1 then "Left" else "Right"
		tile.AnchorPoint = Vector2.new(0.5, 0)
		tile.Position = UDim2.fromScale(spec.x, 0)
		tile.Size = UDim2.fromScale(1, 0.72)
		tile.BackgroundTransparency = 1
		tile.Parent = group

		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = 1
		aspect.DominantAxis = Enum.DominantAxis.Height
		aspect.Parent = tile

		local scale = Instance.new("UIScale")
		scale.Parent = tile

		local empty = arrowImage(tile, spec.rotation)
		empty.Size = UDim2.fromScale(1, 1)
		empty.ImageColor3 = ARROW_EMPTY
		empty.ImageTransparency = ARROW_EMPTY_ALPHA

		local mask = Instance.new("CanvasGroup")
		mask.Name = "Fill"
		mask.AnchorPoint = Vector2.new(spec.tail, 0)
		mask.Position = UDim2.fromScale(spec.tail, 0)
		mask.Size = UDim2.fromScale(0, 1)
		mask.BackgroundTransparency = 1
		mask.BorderSizePixel = 0
		mask.ZIndex = 2
		mask.Parent = tile

		--- Sized in pixels by `_layoutArrows`, so it stays the tile's size while the mask grows.
		local lit = arrowImage(mask, spec.rotation)
		lit.AnchorPoint = Vector2.new(spec.tail, 0)
		lit.Position = UDim2.fromScale(spec.tail, 0)

		local caption, captionStroke = outlinedLabel("Key", group)
		caption.AnchorPoint = Vector2.new(0.5, 1)
		caption.Position = UDim2.fromScale(spec.x, 1)
		caption.Size = UDim2.fromScale(0.42, 0.25)

		tiles[spec.side] = {
			scale = scale,
			mask = mask,
			lit = lit,
			caption = caption,
			captionStroke = captionStroke,
			shown = -1,
		}
	end

	return { group = group, on = false, token = 0, tiles = tiles }
end

--[[ The key cap: a kit-blue key on a dark lip, the key's name across it. It breathes while it waits
	and sinks onto the lip, orange, when the press lands. Blue rather than the bar's navy track
	because it is drawn over the freeze's dim, where navy all but disappears. Sized in pixels by `_layoutKey`, since how
	wide it is depends on whether it says E or SPACE. ]]
function TutorialController._buildKey(self, root: Frame)
	local group = widgetGroup("KeyPrompt", root)

	local holder = Instance.new("Frame")
	holder.Name = "Key"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.BackgroundTransparency = 1
	holder.Parent = group

	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local function face(name: string, color: Color3, y: number): (Frame, UIStroke)
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.Position = UDim2.fromScale(0, y)
		frame.Size = UDim2.fromScale(1, 0.86)
		frame.BackgroundColor3 = color
		frame.BorderSizePixel = 0
		frame.Parent = holder
		rounded(frame, 0.22)
		local stroke = Instance.new("UIStroke")
		stroke.Color = BAR_STROKE
		stroke.Thickness = 1.5
		stroke.Parent = frame
		return frame, stroke
	end

	local lip, lipStroke = face("Lip", BAR_STROKE, 0.14)
	local cap, capStroke = face("Cap", BAR_FILL, 0)
	cap.ZIndex = 2

	local label, labelStroke = outlinedLabel("Label", cap)
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 3
	padded(label, 0.17, 0.14)

	return {
		group = group,
		on = false,
		token = 0,
		holder = holder,
		scale = scale,
		lip = lip,
		lipStroke = lipStroke,
		cap = cap,
		capStroke = capStroke,
		label = label,
		labelStroke = labelStroke,
		text = nil,
	}
end

--[[ Back to a fresh attempt: the numbers a beat counts with, and `_meterStep` cleared so the next
	frame that shows a widget repaints it from empty. The widgets' LOOKS are not touched here,
	because a beat arms while the last one's widget may still be fading out showing its finish.
	`_resetWidget` does that, at the moment a widget is shown for a new beat. ]]
function TutorialController._resetMeters(self)
	self._barGoal = nil
	self._barShown = 0
	self._barMph = 0
	self._barHeld = 0
	self._barText = nil
	self._chaseFrom = nil
	self._steerHold = { [-1] = 0, [1] = 0 }
	self._meterStep = nil
	self._meterDone = false
end

function TutorialController._resetWidget(self, name: string)
	local widget = self._widgets and self._widgets[name]
	if not widget then
		return
	end
	if name == "bar" then
		self._barShown = 0
		self._barText = nil
		widget.fill.BackgroundColor3 = BAR_FILL
		widget.fill.Size = UDim2.fromScale(0, 1)
		widget.fill.BackgroundTransparency = 1
		widget.label.Text = ""
	elseif name == "arrows" then
		for _, tile in widget.tiles do
			tile.mask.Size = UDim2.fromScale(0, 1)
			tile.shown = 0
			tile.scale.Scale = 1
		end
	elseif name == "key" then
		widget.cap.BackgroundColor3 = BAR_FILL
		widget.cap.Position = UDim2.fromScale(0, 0)
		widget.scale.Scale = 1
	end
end

--- Which meter a beat shows, or nil. Off as a whole or per kind puts the beat back on its old rule,
--- which is why the beat logic asks this rather than reading `step.Meter` itself.
function TutorialController._meterOf(self, step): string?
	local meters = TutorialConfig.Meters
	local kind = step and step.Meter
	if not (kind and meters.Enabled) then
		return nil
	end
	local config = meters[kind]
	return if config and config.Enabled then kind else nil
end

--- Fade one widget in or out. Fenced on a token so the tail of a fade-out cannot hide a widget that
--- has since come back.
function TutorialController._showWidget(self, widget, on: boolean, instant: boolean?)
	if widget.on == on then
		return
	end
	widget.on = on
	widget.token += 1
	local token = widget.token
	if on then
		widget.group.Visible = true
		self:_tween(widget.group, TutorialConfig.Timing.Raise, { GroupTransparency = 0 })
	elseif instant then
		--- Another meter is taking the same spot under the card: gone now, not crossfaded over it.
		widget.group.GroupTransparency = 1
		widget.group.Visible = false
	else
		self:_tween(widget.group, TutorialConfig.Timing.Drop, { GroupTransparency = 1 }).Completed:Once(function()
			if widget.token == token then
				widget.group.Visible = false
			end
		end)
	end
end

--- Bring up the widget for `kind` and take every other one down; nil takes them all down. A widget
--- shown for a beat it was not last showing starts from empty.
function TutorialController._showMeter(self, kind: string?, step)
	local widgets = self._widgets
	if not widgets then
		return
	end
	local want = if kind then WIDGET_OF[kind] else nil
	if want and step ~= self._meterStep then
		self._meterStep = step
		self:_resetWidget(want)
	end
	for name, widget in widgets do
		--- Instant when another meter is coming in (2026-10-13, M3): the two share one spot, and the old
		--- bar crossfading over the new arrows read as a broken stack. A beat with no meter still fades.
		self:_showWidget(widget, name == want, want ~= nil)
	end
	self._meterKind = if want then kind else nil
end

--[[ Hang a widget's group under the card, centred on it, and hand back the inner width and height
	in pixels (nil before the card has a size). `pad` is room round the edge for an outside stroke,
	which the group would otherwise clip.

	OVER the card instead when under it would run off the bottom of the screen, which only happens
	if a metered card is ever given a target to sit above. ]]
function TutorialController._hang(self, group: CanvasGroup, heightShare: number, widthShare: number, gapShare: number, pad: number): (number?, number?)
	local card, root = self._card, self._root
	local size = card.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return nil, nil
	end
	local height = size.Y * heightShare
	local width = size.X * widthShare
	local at = card.AbsolutePosition - root.AbsolutePosition
	local x = at.X + (size.X - width) * 0.5
	local y = at.Y + size.Y + height * gapShare
	if y + height + pad > root.AbsoluteSize.Y then
		y = at.Y - height * (1 + gapShare)
	end
	group.Position = UDim2.fromOffset(math.round(x - pad), math.round(y - pad))
	group.Size = UDim2.fromOffset(math.round(width + pad * 2), math.round(height + pad * 2))
	return width, height
end

--- The bar's strokes and the narrowest its fill may get have no scale form; resolved here.
function TutorialController._layoutBar(self)
	local bar = self._widgets.bar
	local shape = TutorialConfig.Meters.Bar
	local stroke = math.max(1, self._card.AbsoluteSize.Y * shape.Height * BAR_STROKE_RATIO)
	local pad = math.ceil(stroke) + 1
	local width, height = self:_hang(bar.group, shape.Height, shape.Width, shape.Gap, pad)
	if not (width and height) then
		return
	end
	bar.track.Size = UDim2.new(1, -pad * 2, 1, -pad * 2)
	bar.trackStroke.Thickness = stroke
	bar.labelStroke.Thickness = stroke
	self._barFloor = height / width
end

function TutorialController._layoutArrows(self)
	local arrows = self._widgets.arrows
	local config = TutorialConfig.Meters.Steer
	local _, height = self:_hang(arrows.group, config.Height, config.Width, config.Gap, 0)
	if not height then
		return
	end
	local side = math.round(height * 0.72)
	local stroke = math.max(1, height * 0.25 * 0.09)
	for _, tile in arrows.tiles do
		tile.lit.Size = UDim2.fromOffset(side, side)
		tile.captionStroke.Thickness = stroke
	end
end

--- Sized off its own text: a cap is about square for one letter and widens for a word.
function TutorialController._layoutKey(self, text: string)
	local key = self._widgets.key
	local config = TutorialConfig.Meters.Key
	local stroke = math.max(1, self._card.AbsoluteSize.Y * config.Height * BAR_STROKE_RATIO)
	local pad = math.ceil(stroke) + 1
	local _, height = self:_hang(key.group, config.Height, 0.9, config.Gap, pad)
	if not height then
		return
	end
	local capHeight = height * 0.86
	local width = capHeight * math.max(1.15, 0.42 * utf8.len(text) + 0.5)
	key.holder.Size = UDim2.fromOffset(math.round(width), math.round(height))
	key.capStroke.Thickness = stroke
	key.lipStroke.Thickness = stroke
	key.labelStroke.Thickness = stroke
end

--[[ The bar's fill, as a share of the track. It is a pill of its own, so it may not get narrower
	than it is tall: past that its rounded end curves tighter than the track's and pokes out through
	the border. It stops as a round cap in the track's left end and fades out from there, the same
	rule as the Flow meter's. ]]
function TutorialController._paintBarFill(self, share: number)
	local bar = self._widgets.bar
	local floor = self._barFloor or 0
	bar.fill.Size = UDim2.fromScale(math.max(share, floor), 1)
	bar.fill.BackgroundTransparency = if floor > 0 and share < floor then 1 - share / floor else 0
end

--- Ease the fill toward `share` and paint it.
function TutorialController._easeBar(self, share: number, dt: number)
	local rate = TutorialConfig.Meters.Bar.Lerp
	self._barShown += (share - self._barShown) * (1 - math.exp(-rate * dt))
	self:_paintBarFill(self._barShown)
end

--- Write the label, but only when it changes. A `Text` write is a layout pass either way.
function TutorialController._writeBarLabel(self, text: string)
	if text ~= self._barText then
		self._barText = text
		self._widgets.bar.label.Text = text
	end
end

--[[ The speed this car has to reach, in the speedo's MPH. See `TutorialConfig.Meters`.

	LATCHED ONLY ONCE THERE IS A CAR TO ASK. BOOST arrives before the car is installed, so the
	fallback is handed back unlatched and the real answer replaces it on a later frame, which is
	always inside the grace and before anybody has read it. ]]
function TutorialController._barTarget(self): number
	if self._barGoal then
		return self._barGoal
	end
	local config = TutorialConfig.Meters.Speed
	local drive = Shard.get("DriveController")
	local hud = Shard.get("DrivingHudController")
	local cruise = drive and drive:getCruiseSpeed()
	if not (cruise and hud) then
		return config.FallbackMph
	end
	local round = config.RoundTo
	local goal = math.floor(hud:toMph(cruise * config.TargetOverCruise) / round + 0.5) * round
	local boost = if DriveConfig.AllowBoost then DriveConfig.BoostSpeedScale else 1
	local ceiling = hud:toMph(cruise * boost * config.CeilingShare)
	if goal > ceiling then
		goal = math.floor(ceiling / round) * round
	end
	self._barGoal = math.max(goal, round)
	return self._barGoal
end

--[[ One frame of the live beat's meter: which widget is up, and what it says.

	UP ONLY ON THE BEAT'S OWN FACES, on a road, with the card on screen. The lobby face of a race
	beat says "hit PLAY", and a meter under that is a gauge for a car that is not there. BANK's
	second face (`Arrived`) is still its own. ]]
function TutorialController._stepMeter(self, step, dt: number)
	local kind = self:_meterOf(step)
	local face = self:_face(step)
	local own = face == step or (step.Arrived ~= nil and face == step.Arrived)
	local want = kind ~= nil and self._widgets ~= nil and self._cardOn == true and own and self:_inRace()
	self:_showMeter(if want then kind else nil, step)
	if not want then
		return
	end

	if kind == "Speed" then
		local hud = Shard.get("DrivingHudController")
		local mph = if hud then hud:getMph() else 0
		self._barMph = mph
		local goal = self:_barTarget()
		self:_layoutBar()
		self:_easeBar(math.clamp(mph / goal, 0, 1), dt)
		self:_writeBarLabel(string.format(TutorialConfig.Meters.Speed.LabelFormat, math.floor(mph + 0.5), goal))
	elseif kind == "Timer" then
		local seconds = step.Advance.Seconds or 0
		local survived = math.clamp(self._beatTime - (step.Grace or 0), 0, seconds)
		self:_layoutBar()
		self:_easeBar(if seconds > 0 then survived / seconds else 1, dt)
		self:_writeBarLabel(string.format(TutorialConfig.Meters.Timer.LabelFormat, math.floor(survived), seconds))
	elseif kind == "Chase" then
		self:_layoutBar()
		self:_stepChase(dt)
	elseif kind == "Steer" then
		self:_layoutArrows()
		self:_stepArrows()
	elseif kind == "Key" then
		self:_stepKey(face)
	end
end

--[[ BANK on the bar, in two halves. Before the truck is on the road the bar DRAINS with the
	countdown to it; once it is, the bar fills as the gap closes, measured from the gap there was when
	it first turned up. So the bar empties, the truck arrives, and the bar fills back up as the player
	catches it, with no jump in between.

	The distance is the character's, the same number the chip over the truck prints. ]]
function TutorialController._stepChase(self, dt: number)
	local config = TutorialConfig.Meters.Chase
	local truck = self:_truck()
	if truck then
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			return
		end
		local studs = (truck.Position - root.Position).Magnitude
		self._chaseFrom = self._chaseFrom or math.max(studs, 1)
		self:_easeBar(math.clamp(1 - studs / self._chaseFrom, 0, 1), dt)
		self:_writeBarLabel(string.format(config.DistanceFormat, math.floor(studs)))
		return
	end

	local getaway = Shard.get("GetawayController")
	local left, total = nil, nil
	if getaway then
		left, total = getaway:getCountdown()
	end
	if left and total and total > 0 then
		self:_easeBar(math.clamp(left / total, 0, 1), dt)
		self:_writeBarLabel(string.format(config.CountdownFormat, math.ceil(left)))
	else
		self:_easeBar(0, dt)
		self:_writeBarLabel(config.ComingText)
	end
end

--- Each arrow at its direction's held share, and captioned with this device's key for it.
function TutorialController._stepArrows(self)
	local arrows = self._widgets.arrows
	local keys = self:_keys()
	local hold = TutorialConfig.Meters.Steer.HoldSeconds
	for side, tile in arrows.tiles do
		local share = if self._steerSeen and self._steerSeen[side]
			then 1
			else math.clamp((self._steerHold[side] or 0) / math.max(hold, 0.01), 0, 1)
		if share ~= tile.shown then
			tile.shown = share
			tile.mask.Size = UDim2.fromScale(share, 1)
		end
		local text = (if side == 1 then keys.SteerLeft else keys.SteerRight) or ""
		if tile.caption.Text ~= text then
			tile.caption.Text = text
		end
	end
end

--- An arrow has just filled. A small punch, so the moment it counts is something that happens.
function TutorialController._arrowFilled(self, side: number)
	local tile = self._widgets and self._widgets.arrows.tiles[side]
	if tile then
		self:_punch(tile.scale, 1.15)
	end
end

--- The key cap names `face.Fill`'s first key on this device, and breathes until it is pressed.
function TutorialController._stepKey(self, face)
	local key = self._widgets.key
	local name = face.Fill and face.Fill[1]
	local text = (name and (self:_keys()[name] or TutorialConfig.Keys.Keyboard[name])) or "?"
	if key.text ~= text then
		key.text = text
		key.label.Text = text
	end
	--[[ NONE ON TOUCH (2026-10-16). On a phone the cap names an on-screen button, and a blue rounded
		key under the card read as that button: playtesters tapped it. A bare word was tried the same
		day and dropped too; the card's hint already names the button and the tutorial arrow points
		at the real one (`bail`'s `Target`). A keyboard or pad keeps the cap, where it pictures a
		physical key. Per frame, so a device switch follows. ]]
	key.holder.Visible = UserInputService.PreferredInput ~= Enum.PreferredInput.Touch
	self:_layoutKey(text)
	if not self._meterDone then
		local config = TutorialConfig.Meters.Key
		local phase = (math.sin(os.clock() * math.pi * 2 / config.PulsePeriod) + 1) * 0.5
		key.scale.Scale = 1 + (config.PulseScale - 1) * phase
	end
end

--[[ The beat this meter belongs to is over: show it finished, and hold that under the DONE stamp
	until the next beat's paint takes it down. Called from `_beatDone` for the beats this client
	closes and from `_onState` for the ones the server closes, and only acts once.

	The bar reads its finished number rather than the live one: the speed may already be past the
	target by the frame this lands, and "57 / 55" under a DONE reads like a sum that does not add up. ]]
function TutorialController._completeMeter(self)
	local kind = self._meterKind
	local widgets = self._widgets
	if not (kind and widgets) or self._meterDone then
		return
	end
	self._meterDone = true
	local meters = TutorialConfig.Meters

	if WIDGET_OF[kind] == "bar" then
		local text
		if kind == "Speed" then
			local goal = self:_barTarget()
			text = string.format(meters.Speed.LabelFormat, goal, goal)
		elseif kind == "Timer" then
			local seconds = (self._meterStep and self._meterStep.Advance.Seconds) or 0
			text = string.format(meters.Timer.LabelFormat, seconds, seconds)
		else
			text = meters.Chase.DoneText
		end
		self._barShown = 1
		self:_paintBarFill(1)
		widgets.bar.fill.BackgroundColor3 = BAR_FULL
		self:_writeBarLabel(text)
	elseif kind == "Steer" then
		for _, tile in widgets.arrows.tiles do
			tile.shown = 1
			tile.mask.Size = UDim2.fromScale(1, 1)
		end
	elseif kind == "Key" then
		local key = widgets.key
		key.scale.Scale = 1
		key.cap.BackgroundColor3 = BAR_FULL
		key.cap.Position = UDim2.fromScale(0, 0.14)
		self:_punch(key.scale, 1.12)
	end
end

-- === Drawing ================================================================

--[[ Which row of `TutorialConfig.Keys` this player is on, asked FRESH every time the card is
	painted rather than latched at boot.

	That is not caution, it is a known trap in this codebase: `UserInputService.TouchEnabled` reads
	false for the first moments of a session on devices that do have a touchscreen, so anything that
	decides its control scheme once, early, decides it wrong. A repaint is cheap and a card that
	names the wrong key is the single worst thing this feature can do.

	THE DEVICE IN USE, NOT THE DEVICES PRESENT (2026-10-15). It read `GamepadEnabled and not
	KeyboardEnabled`, which is a console and nothing else: a PC player holding a pad has a keyboard
	plugged in too, so they were told "HOLD W" and "SPACE" on the beats that freeze the world until
	that very input. `PreferredInput` is the engine's answer to which one is being used, it moves when
	they switch, and `_useKitCard` repaints the card when it does. ]]
function TutorialController._keys(self)
	local preferred = UserInputService.PreferredInput
	if preferred == Enum.PreferredInput.Touch then
		return TutorialConfig.Keys.Touch
	end
	if preferred == Enum.PreferredInput.Gamepad then
		return TutorialConfig.Keys.Gamepad
	end
	return TutorialConfig.Keys.Keyboard
end

--[[ Fill a line's `%s` directives with the keys the beat named in `Fill`.

	Guarded on there being a directive at all, so copy with no key in it cannot be broken by a
	`string.format` it never asked for — and so a writer can take a key out of a hint without
	touching this file. Extra names are harmless: `string.format` ignores arguments it has no
	directive for, which is what lets one `Fill` list serve a title and a hint that name different
	numbers of keys.

	A MISSING NAME FALLS BACK TO THE KEYBOARD ROW rather than erroring, because the failure mode of
	a typo here is a card that reads "HOLD nil TO BOOST" — which is worse than a card that names the
	wrong device's key by a wide margin. ]]
function TutorialController._fill(self, text: string?, fill): string
	text = text or ""
	if not string.find(text, "%%s") then
		return text
	end
	local keys = self:_keys()
	local args = {}
	for index, name in fill or {} do
		args[index] = keys[name] or TutorialConfig.Keys.Keyboard[name] or "?"
	end
	local ok, filled = pcall(string.format, text, table.unpack(args, 1, math.max(#args, 1)))
	return if ok then filled else text
end

--[[ Which FACE of a beat is the live one, and there are only ever two.

	A race beat seen from the lobby shows `TutorialConfig.Offroad` — the same one for all five of
	them — because the objective is still true and the words are not. Everything else shows itself.

	ASKED FRESH EVERY TIME rather than latched when the beat arrives, because the answer changes
	underneath a beat that does not: entering a race, wrecking out of one and coming home all move
	it without the server sending anything. `_refresh` is what re-asks it at those three moments. ]]
function TutorialController._face(self, step)
	if not step then
		return step
	end
	if step.Where == "Race" and not self:_inRace() then
		return TutorialConfig.Offroad
	end
	--[[ ...and the thing the beat is waiting for has turned up. One beat has this — BANK, when the
		getaway truck spawns — and it is asked of the truck itself rather than of a remote, so the
		words and the road cannot disagree. ]]
	--- A chase outranks the truck: none can come until it is over (`step.Chased`, BANK only).
	if step.Chased and self:_chased() then
		return step.Chased
	end
	if step.Arrived and self:_arrived(step) then
		return step.Arrived
	end
	return step
end

--- Are the police on this run right now (live, or the arrest)? Asked of the police, like the truck.
function TutorialController._chased(self): boolean
	local police = Shard.get("PoliceController")
	local chase = police and police:getChase()
	return chase ~= nil and (chase.state == "live" or chase.state == "pit")
end

--[[ Has the thing this beat waits for turned up? BANK's is the getaway truck; SELL's
	(`ArrivedWhen = "Buyer"`) is this player's own buyer on the lot, walking in or standing. ]]
function TutorialController._arrived(self, step): boolean
	if step.ArrivedWhen == "Buyer" then
		return self:_buyer() ~= nil
	end
	return self:_truck() ~= nil
end

--- This player's buyer's head, or nil. Asked of the rig's tag, like the truck is asked of the road.
function TutorialController._buyer(self): BasePart?
	local userId = Players.LocalPlayer.UserId
	for _, model in CollectionService:GetTagged(BUYER_TAG) do
		if model:GetAttribute(BUYER_OWNER) == userId then
			local head = model:FindFirstChild("Head")
			if head and head:IsA("BasePart") then
				return head
			end
		end
	end
	return nil
end

--[[ A `Watched` beat (SELL): tell the server, once per arrival of the beat, that its card is up with
	nothing over it, which is when the tutorial's buyer is sent (`BuyerConfig.Tutorial`). "Nothing over
	it" is the card drawn (`_open` is already true here, so no modal and no race transition) and no NEW
	BEST stage up or waiting, which holds every screen off while it plays (`ShowcaseController.busy`). ]]
function TutorialController._stepWatched(self, step)
	if not step.Watched or self._pinged == step.Id or not self._cardOn then
		return
	end
	local showcase = Shard.get("ShowcaseController")
	if showcase and showcase:busy() then
		return
	end
	self._pinged = step.Id
	self:getRemoteEvent("TutorialWatching"):Fire(step.Id)
end

--[[ A face with `Look` (SELL's, once the buyer is on the lot): turn the camera to the buyer while they
	walk to the car, then let go `TutorialConfig.Look.Linger` after they are standing there. Once per
	arrival of the beat; a buyer already standing when the face comes up (a rejoin) is not watched,
	since there is no walk to see. Stopped early by `_hide` and by the next state. ]]
function TutorialController._stepLook(self, step)
	local cfg = TutorialConfig.Look
	if not cfg.Enabled or self._looked == step.Id then
		return
	end
	local face = self:_face(step)
	if not (face and face.Look) then
		return
	end
	local head = self:_buyer()
	local model = head and head.Parent
	if not (head and model) then
		return
	end
	self._looked = step.Id
	if model:GetAttribute(BUYER_ARRIVED) == true then
		return
	end
	local stoodAt: number? = nil
	self:_stopLook()
	self._lookStop = CameraFacing.watch(function(): Vector3?
		if not (head.Parent and model.Parent) then
			return nil
		end
		if model:GetAttribute(BUYER_ARRIVED) == true then
			stoodAt = stoodAt or os.clock()
			if os.clock() - stoodAt >= cfg.Linger then
				return nil
			end
		end
		return head.Position
	end, cfg)
end

--- Hand the camera back if `_stepLook` has it. Idempotent.
function TutorialController._stopLook(self)
	local stop = self._lookStop
	self._lookStop = nil
	if stop then
		stop()
	end
end

--[[ A face with `Guide` (SELL's, once the buyer is on the lot): the green guide line from the player
	to the buyer, from the moment they are standing at the car (their See Offer prompt only exists
	from then, `CustomerService` adds it on arrival) until the card goes. `GuideTrailController` draws
	it; `GuideTrailConfig.Person` has its numbers. Asked every frame, and a buyer sent away and
	replaced is simply pointed at again. ]]
function TutorialController._stepGuide(self, step)
	local face = self:_face(step)
	local head = if face and face.Guide then self:_buyer() else nil
	local model = head and head.Parent
	local root = model and model:FindFirstChild("HumanoidRootPart")
	local standing = model ~= nil and model:GetAttribute(BUYER_ARRIVED) == true
	self:_pointGuide(if standing and root and root:IsA("BasePart") then root else nil)
end

--- Hand `part` to the guide line, or nil to take it back. Only tells it when the answer moved.
function TutorialController._pointGuide(self, part: BasePart?)
	if part == self._guided then
		return
	end
	self._guided = part
	local guide = Shard.get("GuideTrailController")
	if guide then
		guide:pointAt(part)
	end
end

--- The getaway truck, when there is one on the road. nil at every other moment, including while one
--- is armed but not yet spawned — see `GetawayController.getTruck`.
function TutorialController._truck(self): BasePart?
	local getaway = Shard.get("GetawayController")
	return if getaway then getaway:getTruck() else nil
end

--[[ Re-draw the live beat against whatever the face resolver now says, without the ceremony a new
	beat gets — no DONE stamp, no token bump, no punch unless the words actually changed.

	Called from the three places the FACE can change while the beat does not: a run going live, a
	run ending, and the card being allowed back on screen after a transition. ]]
function TutorialController._refresh(self)
	local step = self._step
	if not (step and self._open) then
		return
	end
	local face = self:_face(step)
	local changed = face ~= self._drawnFace
	self._drawnFace = face
	self:_paint(step, changed)
	self:_repoint()
	self:_applyGate()
end

--[[ Everything the card says, written unconditionally.

	`punch` is the one thing a caller may turn off, and it exists for the TALLY: a counted beat
	repaints every time the count moves, and punching the title on each lane change would make the
	card twitch at the player while they are steering. ]]
function TutorialController._paint(self, step, punch: boolean?)
	--[[ Through `_face`, so the pointer and the words can never name two different things — the
		off-road face says "hit PLAY" and has to point at PLAY. ]]
	local face = self:_face(step)
	self._drawnFace = face

	--[[ ...and WHETHER there are words at all, which the face decides too. A pointer-only face keeps
		its copy and simply is not drawn (see `TutorialConfig.showsCard`), so everything below runs
		either way and the card is correct the instant the face changes back. ]]
	self:_setCardShown(TutorialConfig.showsCard(face))
	--- A beat with no meter takes the last one down. `_stepMeter` brings a beat's own one up.
	if not self:_meterOf(step) then
		self:_showMeter(nil)
	end

	self._title.Text = oneLine(self:_fill(face.Title, face.Fill))
	self._title.RichText = face.Id == "boost" and self:_keys().Accelerate == "W"
	if self._title.RichText then
		self._title.Text = self._title.Text:gsub("%f[%w]W%f[%W]", '<font color="#FFD84D">W</font>')
	end

	self:_writeHint(step, face)

	self:_rest()
	if punch ~= false then
		self:_punch(self._titleScale, 1.08)
	end
end

--[[ Show the panel, or take it away and leave the arrow doing the teaching.

	`Visible` ON THE CARD ITSELF, which takes the two labels and the DONE stamp with it — rather than
	a transparency, which would have to be undone by every one of the four places that write one and
	would be one missed line away from a ghost card. The transparencies underneath go on being
	whatever `_show`, `_rest` and the stamp last wrote, so a face that gets its card back is drawn
	correctly on the same frame with nothing to restore.

	IT IS NOT `_hide`, and the difference is the whole point: the gui stays enabled, the arrow stays
	up, the gate stays on and the beat goes on being watched. The only thing that stops is the
	panel. ]]
function TutorialController._setCardShown(self, shown: boolean)
	local was = self._cardOn
	self._cardOn = shown
	if self._card then
		self._card.Visible = shown
	end
	if not shown then
		self:_showMeter(nil)
	end
	--- Coming back needs a placement, because `_place` does not run for a hidden card and the last
	--- one it did run may be several targets old. Deferred so the card has a laid-out size again.
	if shown and not was and self._open then
		task.defer(function()
			if self._cardOn and self._open then
				self:_place(self._placeBox)
			end
		end)
	end
end

--[[ Write the resting transparencies. Called by every paint, and NOT merely by `_show`, which is
	the bug this exists to close: the DONE stamp fades the objective and the hint out on its way in,
	so a card that was already up would paint the next objective into two invisible labels — and
	`_show` returns early on an open card, so nothing would ever have brought them back.

	NOT WHILE THE STAMP IS UP, which is the other half of the same bug: a repaint that lands inside
	the DONE hold would un-fade the objective straight back under the word. ]]
function TutorialController._rest(self)
	if not self._open or (self._done and self._done.Visible) then
		return
	end
	--[[ The kit's hint rests at FULL strength. Its outline is drawn under the glyph, so a dimmed hint
		reads as grey type rather than as quieter type; on this card the band and the size ceiling
		already say which line is the objective. ]]
	if self._kit then
		setTextTransparency(self._title, 0)
		setTextTransparency(self._hint, 0)
		return
	end
	self._title.TextTransparency = 0
	-- The hint rests dimmer than the objective: it is how, not what.
	self._hint.TextTransparency = 0.25
end

--[[ The finish card. ALWAYS DRAWN, whatever the beat before it was: a pointer-only last beat (as
	`collect` once was) would otherwise swallow the tutorial's last word with its own flag. It is the one card here that is not an objective — nothing is being asked for and
	there is no arrow to defer to — which is exactly why it survives the rule. ]]
function TutorialController._paintFinish(self)
	GameplayFeedback.play("TutorialComplete")
	self:_setCardShown(true)
	self._title.Text = oneLine(TutorialConfig.FinishTitle)
	self._hint.Text = TutorialConfig.FinishHint
	self:_rest()
	self:_punch(self._titleScale, 1.12)
	self:_confetti()
end

--[[ The finish card's celebration (`TutorialConfig.FinishConfetti`). On its own full-screen layer in
	this gui, under the card (ZIndex 4 against its 5) so the words stay readable. ]]
function TutorialController._confetti(self)
	local cfg = TutorialConfig.FinishConfetti
	if not (cfg.Enabled and self._root) then
		return
	end
	local layer = self._root:FindFirstChild("Confetti")
	if not layer then
		layer = Instance.new("Frame")
		layer.Name = "Confetti"
		layer.Size = UDim2.fromScale(1, 1)
		layer.BackgroundTransparency = 1
		layer.ZIndex = 4
		layer.Parent = self._root
	end
	if self._paper then
		self._paper.stop()
	end
	local paper = table.clone(ShowcaseConfig.Reveal.Confetti)
	paper.Burst = cfg.Burst
	paper.RainPerSecond = cfg.RainPerSecond
	self._paper = ScreenConfetti.start(layer :: Frame, paper, cfg.RainSeconds)
end

--- A short punch on a UIScale. Scale only, and small — the drama belongs to what the words say,
--- which is the note this project's effects are tuned to.
function TutorialController._punch(self, scale: UIScale, to: number)
	scale.Scale = 1
	local up = TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = to })
	up:Play()
	up.Completed:Once(function()
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end)
end

--[[ Stamp DONE over the objective, hold, and hand back. The caller does the next paint in the
	callback, so the new objective can never be drawn before the beat that says the old one is over.

	=== TWO TOKENS, BECAUSE CLEARING THE STAMP IS NOT THE SAME AS DRAWING THE NEXT CARD ==========

	This used to fence the whole hold on `_token`, and the bug that hid in it was a DONE stamped
	permanently over a live objective. The path: a beat completes and starts the stamp, then a
	second state lands for the NEXT beat and bumps `_token`; the hold then fired, saw a token that
	was no longer its own, and returned — abandoning `Visible = true` on the way out.

	So the two things the hold does are fenced separately:

	    `_stampToken`   the CLEANUP. Only a newer stamp may skip it; a new beat may not, because a
	                    superseded stamp is still a stamp on the screen.
	    `_token`        the HANDBACK. Drawing a card for a beat that has been overtaken is exactly
	                    what that fence is for.

	The general shape of the mistake is worth naming: a cancellation token may guard pending WORK,
	never pending CLEANUP. ]]
function TutorialController._stamp(self, andThen: () -> ())
	local token = self._token
	self._stampToken += 1
	local stampToken = self._stampToken

	self._done.Visible = true
	self._doneScale.Scale = 1
	if self._kit then
		--- Outlined type, so the outlines fade with their letters. See `_fadeText`.
		setTextTransparency(self._done, 1)
		self:_fadeText(self._done, 0.12, 0)
		self:_fadeText(self._title, 0.12, 1)
		self:_fadeText(self._hint, 0.12, 1)
	else
		self._done.TextTransparency = 1
		self:_tween(self._done, 0.12, { TextTransparency = 0 })
		self:_tween(self._title, 0.12, { TextTransparency = 1 })
		self:_tween(self._hint, 0.12, { TextTransparency = 1 })
	end
	self:_punch(self._doneScale, 1.18)

	task.delay(TutorialConfig.Timing.DoneHold, function()
		if self._stampToken ~= stampToken then
			return
		end
		self._done.Visible = false
		self._done.TextTransparency = 1

		if self._token ~= token then
			--[[ Overtaken. The stamp is cleared above, but the labels it faded out are still
				invisible and the paint that would have restored them has already run — so put them
				back rather than leaving a blank card. ]]
			self:_rest()
			return
		end
		andThen()
	end)
end

-- === Show / hide ============================================================

--[[ Whether the card may be on screen at all, independently of whether there is a beat.

	THREE REASONS TO STAND DOWN, and the first two are somebody else owning the screen:

	  • A MODAL is up — the respawn question or the welcome-back panel, flagged on the PlayerGui by
	    `GamepadConfig.ModalAttribute`. Read rather than tracked, so a modal added later inherits
	    this for free, exactly as the gamepad navigation does.
	  • A RACE TRANSITION is running — the entry fade, a wreck, or the trip home with the results
	    screen on it. Those are driven by the race remotes below.
	  • ...and A LOBBY BEAT WHILE THERE IS STILL A ROAD, which is the third and is about the beat
	    rather than about the screen.

	THE LOBBY RULE IS THE MIRROR OF `Offroad` AND IT WAS THE HALF THAT WAS MISSING. A race beat seen
	from the lobby has said the right thing since this feature shipped — it wears a face telling you
	to hit PLAY, because a card naming a car to steal on somebody's own forecourt is the tutorial
	talking about a world that is not there. The other direction had nothing.

	And it is not a corner case: PLACE is entered off `RewardService.RunSettled`, which fires at the
	BANK — `RaceConfig.BankHoldTime + ReturnFadeTime` before the trip home even begins. So "PARK YOUR
	NEW CAR / It is in your hands" was landing while the player was still in the seat, riding a truck
	whose doors were closing, a good two seconds before the fade that takes them home.

	There is nothing a lobby beat can usefully say to somebody on a road, so it says nothing and
	waits. `_suppressed` covers the trip itself; this covers the stretch before it. ]]
function TutorialController._allowed(self): boolean
	local step = self._step
	if not step and not self._finishing then
		return false
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui and playerGui:GetAttribute(GamepadConfig.ModalAttribute) == true then
		return false
	end
	if (self._finishing or (step and step.Where == "Lobby")) and self:_inRace() then
		return false
	end
	return not self._suppressed
end

--- Bring the card to whatever `_allowed` currently says, with the arrow following it.
function TutorialController._sync(self)
	if self:_allowed() then
		self:_show()
		--- A finish that arrived while the screen was taken lands now. See the finished branch of
		--- the state handler.
		local pending = self._finishPending
		if pending then
			pending()
		end
		--- ...and a `Celebrate` beat's confetti, once, on the card's first moment on screen.
		if self._celebrate and self._celebrate == self._token and self._step and self._step.Celebrate then
			self._celebrate = nil
			GameplayFeedback.play("TutorialComplete")
			self:_punch(self._titleScale, 1.12)
			self:_confetti()
		end
	else
		self:_hide()
	end
end

function TutorialController._show(self)
	if not self._gui or self._open then
		return
	end
	self._open = true
	self._gui.Enabled = true

	local time = TutorialConfig.Timing.Raise
	if self._kit then
		--- One picture, faded as one. The labels are put at rest underneath it rather than tweened,
		--- since the group already carries them in. See the header.
		self:_tween(self._card, time, { GroupTransparency = 0 })
		self:_rest()
	else
		self:_tween(self._card, time, { ImageTransparency = 0 })
		self:_tween(self._title, time, { TextTransparency = 0 })
		-- The hint rests dimmer than the objective: it is how, not what.
		self:_tween(self._hint, time, { TextTransparency = 0.25 })
	end

	self:_repoint()
	--[[ ...and once more after a frame. `_place` needs the card's `AbsoluteSize`, and the gui was
		disabled until a moment ago — a card placed against a zero size would land in the corner and
		stay there. ]]
	task.defer(function()
		if self._open then
			self:_place(self._placeBox)
		end
	end)
end

function TutorialController._hide(self)
	if not (self._gui and self._open) then
		return
	end
	self._open = false
	local token = self._token
	local time = TutorialConfig.Timing.Drop

	local last
	if self._kit then
		last = self:_tween(self._card, time, { GroupTransparency = 1 })
	else
		self:_tween(self._card, time, { ImageTransparency = 1 })
		self:_tween(self._title, time, { TextTransparency = 1 })
		last = self:_tween(self._hint, time, { TextTransparency = 1 })
	end

	self:_clearPointer()
	self:_showMeter(nil)
	--[[ AND EVERY HOLD THIS FEATURE HAS ON THE GAME, because a hidden card is a card that cannot be
		read and a frozen world with nothing on screen explaining it is the worst thing here could
		ship. Both of these are idempotent, so calling them on every hide costs nothing. ]]
	self:_freeze(false)
	self:_setGate(nil)
	--- ...and the camera, which the buyer's walk-in may have (`_stepLook`): the offer screen opening
	--- over it is the end of that walk. The guide line to them goes with it (`_stepGuide`).
	self:_stopLook()
	self:_pointGuide(nil)

	last.Completed:Once(function()
		-- Fenced on the token: nothing should be switched off by the tail of a card that has already
		-- been replaced.
		if self._token == token and not self._open then
			self._gui.Enabled = false
		end
	end)
end

function TutorialController._tween(self, inst, time: number, props)
	local tween = TweenService:Create(inst, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

--[[ The hint line on its own, because it moves without the rest of the card doing so.

	A target chain hands each of its links an optional `Hint`, and the live one wins — so the line
	under the title tracks the pointer through the WORLDS and SELECT CAR screens while the title
	goes on naming the objective. `_repoint` calls this after it resolves, which is the moment the
	answer can have changed; `_paint` calls it because a fresh beat has to write the whole card.

	The TALLY is appended here rather than stored in the text, so a counted beat can repaint its
	number without the rest of the line being rebuilt. ]]
function TutorialController._writeHint(self, step, face)
	if not self._hint then
		return
	end
	local leg = if face.Target then self:_leg(face.Target) else nil
	local hint = self:_fill((leg and leg.Hint) or face.Hint, face.Fill)
	--- The tally belongs to the objective, so it is not drawn on a face that is not naming it, and
	--- not under a meter, which already shows the same count as it fills (STEER's two arrows).
	if step.Count and face == step and not self:_meterOf(step) then
		hint ..= string.format(TutorialConfig.CountFormat, self._count or 0, step.Count)
	end
	self._hint.RichText = face.Id == "boost" and self:_keys().Accelerate == "W"
	if self._hint.RichText then
		hint = hint:gsub("%f[%w]W%f[%W]", '<font color="#FFD84D">W</font>')
	end
	self._hint.Text = hint
end

-- === The pointer ============================================================

--[[ Resolve the live target and draw it. Called whenever anything that could change the answer
	moves: a new beat, a page opening or closing, the card coming up.

	A TARGET THAT CANNOT BE FOUND IS NOT AN ERROR. The plot may not have streamed in yet, the page
	may not be open, the bay may be empty — all ordinary. The pointer is simply absent and the card
	carries the objective on its own. It is retried on the next thing that moves. ]]
function TutorialController._repoint(self)
	--- Any retry still pending from an earlier resolve is stale: this call is the live answer.
	self._pointToken += 1
	--- ...and so is any standing instruction to keep asking. Only the branch that draws a chip for a
	--- `Follow` target puts it back, so every other outcome leaves it off. See `FOLLOW_INTERVAL`.
	self._follow = nil
	if not (self._open and self._step) then
		self:_clearPointer()
		return
	end
	local face = self:_face(self._step)
	local target = face.Target
	--- A `TouchOnly` target names a thumb button, which a keyboard or pad never has on screen.
	if target and target.TouchOnly and UserInputService.PreferredInput ~= Enum.PreferredInput.Touch then
		target = nil
	end
	if not target then
		self:_clearPointer()
		self:_place(nil)
		return
	end
	--- The live link may carry its own hint, and this is the moment which link is live can change.
	self:_writeHint(self._step, face)

	local resolved = self:_leg(target)
	if resolved.Kind == "Hud" or resolved.Kind == "Page" then
		local button = self:_findGui(resolved)
		if button then
			self:_clearChip()
			--[[ Not a `DrivingHud` button: `TutorialControlHighlight` already swells those through
				`ControlButtonScale`'s channels on the same UIScale, and `_pulseOn` writing it raw
				would fight that every frame. ]]
			if resolved.Gui then
				self:_pulseOff()
			else
				self:_pulseOn(button)
			end
			self._aimBox = button
			self:_aimArrow(button)
			--[[ The card goes beside the thing it names — but for a button inside a PAGE it is placed
				against the page, not against the button. Against the button it would land on the
				page's own art, which for the WORLDS screen means the card covering the very thing it
				is telling the player to press. ]]
			--- `CardHome`: the arrow goes to the button and the card stays where it was, for a race
			--- beat whose card would otherwise land among the thumb controls it is pointing at.
			self:_place(if resolved.CardHome then nil else self:_placementBox(resolved, button))
			self:_ensureLoop()
			return
		end
	elseif resolved.Kind == "World" then
		local part = self:_findWorld(resolved)
		if part then
			self:_clearArrow()
			self:_chip(part, resolved.Above, resolved.OverSign)
			--- A target whose answer can become a DIFFERENT object is asked again by the loop; one
			--- that merely moves or streams in is not, because the chip already rides its part.
			self._follow = if resolved.Follow then resolved else nil
			self._followAt = os.clock()
			self:_place(nil)
			self:_ensureLoop()
			return
		end
	end

	-- Nothing to point at yet: a world target that has not streamed in, or a page not open.
	self:_clearPointer()
	self:_place(nil)
	if resolved.Kind == "World" then
		self:_retryPoint()
	end
end

--[[ Ask again shortly, for a WORLD target that was not there yet.

	A SCREEN TARGET HAS AN EVENT TO WAIT ON and a world one does not. A page opening moves the arrow
	and `start` watches every page's `Visible` for exactly that; the plot, the podium and the collect
	mat arrive whenever streaming decides they do (`StreamingEnabled` is on in this place), which on
	the trip home from a run is squarely inside the beat that points at them.

	Without this the COLLECT beat was ONE SHOT. `_repoint` runs when the card is allowed back after
	the results screen, and for a lobby beat the server closes nothing calls it again — `_armBeat`
	returns early on a signal beat that does not freeze, so there is not even a frame loop. A mat
	that had not streamed in by that single moment was never pointed at for the rest of the beat,
	and that beat is the last objective in the tutorial: the arrow over the mat IS its teaching.

	Fenced on its own token, bumped by every `_repoint`, so the chain is never more than one deep
	and the first resolve that succeeds ends it. ]]
function TutorialController._retryPoint(self)
	local token = self._pointToken
	task.delay(POINT_RETRY, function()
		if self._pointToken == token and self._open and self._step then
			self:_repoint()
		end
	end)
end

--[[ Which LINK of a target chain is live: `Then` wins while its page is open — the WORLDS card once
	the WORLDS screen is up, and the SELECT CAR card once that one is.

	WALKED IN FULL rather than followed hop by hop: opening a page CLOSES the one before it
	(`UIController`), so by the time the third screen is up the second is already shut, and a loop
	that stopped at the first closed link would fall back to pointing at the HUD button. Only one
	can be open at a time, so "the deepest open one" is just "the open one".

	Asked by BOTH the pointer and the hint line, so the words and the arrow cannot name different
	things — which they did, for the two presses between PLAY and the road. ]]
function TutorialController._leg(self, target)
	local resolved = target
	local hop = target and target.Then
	while hop do
		if self:_pageOpen(hop.Page) then
			resolved = hop
		end
		hop = hop.Then
	end
	return resolved
end

--- What the card should be placed against for a resolved UI target — see the note in `_repoint`.
function TutorialController._placementBox(self, resolved, button: GuiObject): GuiObject
	if resolved.Kind == "Page" then
		local pages = self._mainUI and self._mainUI:FindFirstChild("Pages")
		local page = pages and pages:FindFirstChild(resolved.Page)
		if page and page:IsA("GuiObject") then
			return page
		end
	end
	return button
end

--[[ Point the arrow at `box`, travelling there from wherever it currently is.

	=== IT PICKS A SIDE, AND THERE ARE FOUR ===================================================

	The arrow is a ninth of the screen across. There is not always room above the thing it is
	naming, and the two shapes this feature points at are opposites: a HUD button is small and sits
	against an edge, while a page card is large and sits inside a panel with acres of empty space to
	one side of it.

	So four candidates, tried in order, first one that fits inside the screen wins:

	    ABOVE   pointing down. The most readable of the four, so it is asked for first — a pointer
	            coming down at a thing is how everything else in the genre draws this.
	    RIGHT   pointing left, and LEFT pointing right. These are what a page card gets: the SELECT
	            CAR panel is 583 wide with a 180-wide card in the corner of it, so beside the card
	            is inside the panel and above it is under Roblox's own bar.
	    BELOW   pointing up. Last, because an arrow under a thing reads as pointing at whatever is
	            under IT unless there is nothing else down there — which, at the bottom of a screen
	            with a HUD on it, there usually is.

	"FITS" INCLUDES THE BOB. The arrow swings a fifth of its own height along the axis it points, so
	the room it needs is its box plus that swing in both directions — a side chosen on the resting
	geometry alone would have the arrow leaving the screen twice a second.

	If none of the four fits, ABOVE is taken and clamped. A pointer half off the screen is still a
	pointer; no pointer at all is a beat with nothing to follow.

	THE FIRST AIM IS A CUT AND EVERY ONE AFTER IT IS A TWEEN. A card that has just come up has no
	previous position to travel from, and animating in from the last beat's target would be the
	arrow flying across the screen from something the player is no longer looking at. ]]
function TutorialController._aimArrow(self, box: GuiObject, follow: boolean?)
	local root = self._root
	local arrow = self._arrow
	if not (root and arrow) then
		return
	end
	local viewport = root.AbsoluteSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return
	end

	--- Square, and sized off the SHORTER side so it is the same arrow in portrait and landscape.
	local size = math.min(viewport.X, viewport.Y) * TutorialConfig.Arrow.Size
	arrow.Size = UDim2.fromOffset(size, size)

	local origin = root.AbsolutePosition
	local at = box.AbsolutePosition - origin
	local boxSize = box.AbsoluteSize

	local half = size * 0.5
	local standoff = size * TutorialConfig.Arrow.Standoff
	local bob = size * TutorialConfig.Arrow.Bob
	local reach = half + standoff
	local centreX = at.X + boxSize.X * 0.5
	local centreY = at.Y + boxSize.Y * 0.5
	--- What this aim was measured against, kept so the frame loop can tell a target that has moved
	--- from one that has not. See the note on the follow test in `_ensureLoop`.
	self._aimAt = Vector2.new(centreX, centreY)

	local margin = EDGE_MARGIN * viewport.X
	local guard = topGuard(origin.Y)

	--[[ `axis` points from the arrow TOWARD what it is naming, which is the one number the bob and
		the rotation are both derived from — so a side cannot be added without its swing and its
		facing agreeing by construction. Rotation 0 draws the arrow pointing down, hence the map. ]]
	local sides = {
		{ x = centreX, y = at.Y - reach, rot = 0, axis = Vector2.new(0, 1) },
		{ x = at.X + boxSize.X + reach, y = centreY, rot = 90, axis = Vector2.new(-1, 0) },
		{ x = at.X - reach, y = centreY, rot = -90, axis = Vector2.new(1, 0) },
		{ x = centreX, y = at.Y + boxSize.Y + reach, rot = 180, axis = Vector2.new(0, -1) },
	}

	--- Does the whole arrow, plus the full travel of its bob, land on the screen?
	local function fits(side): boolean
		local swing = Vector2.new(math.abs(side.axis.X), math.abs(side.axis.Y)) * bob
		local x0, x1 = side.x - half - swing.X, side.x + half + swing.X
		local y0, y1 = side.y - half - swing.Y, side.y + half + swing.Y
		return x0 >= margin and x1 <= viewport.X - margin and y0 >= guard and y1 <= viewport.Y - margin
	end

	local chosen = sides[1]
	for _, side in sides do
		if fits(side) then
			chosen = side
			break
		end
	end

	arrow.Rotation = chosen.rot
	self._arrowHome = Vector2.new(chosen.x, chosen.y)
	self._arrowAxis = chosen.axis

	local target = self:_arrowPos(chosen.x, chosen.y)
	if not arrow.Visible then
		arrow.Position = target
		arrow.Visible = true
		self._arrowRestAt = 0
		self._bobFrom = os.clock()
	elseif follow then
		--[[ THE SAME TARGET, MOVED, rather than a new one to travel to — a page scaling open under
			the arrow, or a list settling. It is a re-measure and not an animation: `_arrowHome` is
			already the new one above, so the bob writes `Position` off it on the very next frame.

			A travel here would be the wrong shape twice over. It would restart the settle gate, so
			the bob would be switched off for its whole length every time the target twitched; and
			it would chase a moving box at a fixed 0.45s, which lags further behind the faster the
			box is moving. ]]
		self._arrowRestAt = 0
	else
		self:_tween(arrow, TutorialConfig.Arrow.Travel, { Position = target })
		--- When the travel is over, to the frame. See `_arrowPos` for why this is not measured.
		self._arrowRestAt = os.clock() + TutorialConfig.Arrow.Travel
		self._bobFrom = self._arrowRestAt
	end
end

--[[ PUBLIC: seconds into the arrow's bob, on the clock the bob's sine is measured from (`_bobFrom`).
	`TutorialControlHighlight` swells the thumb button off this, so the button is largest on the frame
	the arrow dips nearest it rather than drifting in and out of step on a period of its own. ]]
function TutorialController.bobClock(self): number
	return os.clock() - (self._bobFrom or 0)
end

--[[ The arrow's position, IN SCALE RATHER THAN OFFSET, which is the whole reason its bob is smooth.

	`UDim.Offset` is an integer. Anything animated through it moves in whole pixels, and a sine bob
	spends most of its cycle moving less than a pixel per frame — so it sits still for six frames and
	then jumps one, which is not a bob, it is a stutter. Scale is a float and Roblox lays out and
	draws GUI at sub-pixel precision, so the same motion comes out continuous.

	The `TweenService` travel between targets is the same story: tweening a UDim2 built from offsets
	quantises every intermediate frame. In scale it is a smooth glide.

	Falls back to offset only when the root has no size yet, which is the one frame before the first
	layout — a rounded pixel is better than a divide by zero. ]]
function TutorialController._arrowPos(self, x: number, y: number): UDim2
	local root = self._root
	local viewport = root and root.AbsoluteSize
	if not (viewport and viewport.X > 0 and viewport.Y > 0) then
		return UDim2.fromOffset(math.round(x), math.round(y))
	end
	return UDim2.fromScale(x / viewport.X, y / viewport.Y)
end

--[[ Make `button` breathe, and stop the last one.

	IT REUSES AN EXISTING `UIScale` RATHER THAN ADDING ONE, which is not a tidiness point — Roblox
	honours only the FIRST UIScale on a GuiObject, so a second one added here would be silently
	ignored on every button `UIController/Components/Button` has already scaled for its own hover.
	The one that is there is borrowed and its value put back on the way out.

	THE VALUE PUT BACK IS THE ONE FOUND, not 1. A button mid-hover is at its hover scale, and
	restoring a flat 1 would snap it out of a state its own component still thinks it is in. ]]
function TutorialController._pulseOn(self, button: GuiObject)
	if self._pulseTarget == button then
		return
	end
	self:_pulseOff()

	local scale = button:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "TutorialPulse"
		scale.Parent = button
		self._pulseOwned = scale
	end
	self._pulseTarget = button
	self._pulseScale = scale
	self._pulseBase = scale.Scale
end

function TutorialController._pulseOff(self)
	if self._pulseScale and self._pulseScale.Parent then
		self._pulseScale.Scale = self._pulseBase or 1
	end
	if self._pulseOwned then
		self._pulseOwned:Destroy()
		self._pulseOwned = nil
	end
	self._pulseTarget, self._pulseScale, self._pulseBase = nil, nil, nil
end

--[[ Rectangles the card may not cover, in `_root`'s space: the thing it is naming, the arrow
	naming it, and whatever `MainUI.HUD` has on screen at the time.

	CHILDREN RATHER THAN DESCENDANTS for the HUD. `Rail` is one box drawn around its own buttons and
	that box is the shape to dodge — a card that cleared one rail button by sitting on the two above
	it has not cleared the rail. ]]
function TutorialController._obstacles(self, box: GuiObject?)
	local origin = self._root.AbsolutePosition
	local rects = {}

	local function add(object: GuiObject)
		local at = object.AbsolutePosition - origin
		table.insert(rects, { min = at, max = at + object.AbsoluteSize })
	end

	if box then
		add(box)
	end
	-- The arrow is the whole point of the beat; a card over it would hide the pointer rather than
	-- the target, which is the worse of the two collisions.
	if self._arrow and self._arrow.Visible then
		add(self._arrow)
	end
	local hud = self._mainUI and self._mainUI:FindFirstChild("HUD")
	if hud then
		for _, child in hud:GetChildren() do
			if child:IsA("GuiObject") and child.Visible then
				add(child)
			end
		end
	end
	return rects
end

--- How much of `rects` a card at `x, y` would cover, in square pixels. Zero is the only score worth
--- having; the number exists to pick the least bad on a screen where nothing is clean.
local function covered(x: number, y: number, size: Vector2, rects): number
	local total = 0
	for _, rect in rects do
		local wide = math.min(x + size.X, rect.max.X) - math.max(x, rect.min.X)
		local tall = math.min(y + size.Y, rect.max.Y) - math.max(y, rect.min.Y)
		if wide > 0 and tall > 0 then
			total += wide * tall
		end
	end
	return total
end

--[[ Put the card by `box`, or in its resting corner when there is nothing to sit by.

	SEVERAL PLACES TRIED IN ORDER, NOT ONE, and that is a fix rather than a flourish. The card used
	to go above the box and be clamped on to the screen, and above a PAGE that never once fitted: a
	panel in this kit is 0.58 of the screen tall and centred, so the band over it is 0.21 of the
	screen and the card and its gap are 0.163 of one, before the top guard takes 64 pixels off. The
	clamp put the card back down INTO the panel on every screen anybody plays on.

	So each candidate is clamped to the screen, scored against everything it must not cover, and the
	first one covering nothing wins. Nothing clean anywhere leaves the least-bad one, which is still
	better than always landing on the same wrong spot.

	Everything is worked out in `_root`'s space, so a button's `AbsolutePosition` — which comes out
	of `MainUI`, a different ScreenGui — lands correctly here whatever the safe-area insets did to
	either of them. ]]
function TutorialController._place(self, box: GuiObject?)
	if not self._root then
		return
	end
	--[[ Remembered so the per-frame loop can keep re-placing against a box that MOVES — a page
		scales open over a quarter of a second, and the rail's buttons are laid out by a
		`UIListLayout` — and so a viewport resize can re-place without re-resolving the target. ]]
	self._placeBox = box

	--- Nothing to place on a pointer-only face, and this runs per frame while an arrow is up. The
	--- box is remembered above first, so the card lands correctly the moment a face brings it back.
	if not self._cardOn then
		return
	end

	local viewport = self._root.AbsoluteSize
	local size = self._card.AbsoluteSize
	if viewport.X <= 0 or viewport.Y <= 0 or size.X <= 0 then
		return -- not laid out yet; the next call places it
	end
	local origin = self._root.AbsolutePosition

	local margin = EDGE_MARGIN * viewport.X
	local guard = topGuard(origin.Y)
	--[[ Both upper bounds are floored at the lower one rather than at zero, so a viewport too short
		or too narrow to hold the card at all pins it to the guard instead of throwing out of
		`math.clamp` — which rejects a max below its min, and would take the placement loop with it. ]]
	local maxX = math.max(margin, viewport.X - size.X - margin)
	local maxY = math.max(guard, viewport.Y - size.Y - margin)
	-- The resting spot: hard left (or right, `CARD_LEFT`), under the bar. See the header.
	local restX, restY = if CARD_LEFT then margin else maxX, guard
	local farX = if CARD_LEFT then maxX else margin

	local x, y = restX, restY
	if box then
		--[[ WAIT FOR THE BOX TO SETTLE (2026-10-20: the card "goes to the right side, goes to the
			bottom and kinda clips back up" as the WORLDS page opened and closed). A page scales open
			over a quarter of a second, and scoring every frame of that against a box that keeps
			growing picked a different winner almost every frame. So a NEW box holds the card where it
			is for `PLACE_SETTLE` seconds, past the page's opening. By the box changing only, never its
			size: the PLAY button pulses for ever while it is the target (the beckon), and a size test
			never settled, which left the finish card stuck off its spot above PLAY. ]]
		local now = os.clock()
		if box ~= self._settleBox then
			self._settleBox, self._settleSince = box, now
			return
		end
		if now - self._settleSince < PLACE_SETTLE then
			return
		end
		local at = box.AbsolutePosition - origin
		local boxSize = box.AbsoluteSize
		--[[ Clear the ARROW as well as the box. It is drawn in this gui rather than parented to the
			target, so none of it is in `AbsoluteSize`, and it is far bigger than the ring it
			replaced — a gap that cleared the old pointer lands the card squarely inside this one.

			AND THE BOB HAS TO BE IN THE NUMBER, which is the part that was wrong first time. The
			arrow's resting place is `Standoff` off the button, but it swings `Bob` of its own height
			either side of that — so on the away half of every cycle it reaches further from the
			button than its resting geometry says. A gap sized without it left the card five pixels
			inside the arrow's top of swing, which `_obstacles` scored as a collision and `_place`
			answered by giving up on "above the button" entirely and parking the card in the far
			corner. It looked like a placement bug and it was an arithmetic one. ]]
		local gap = CARD_GAP * viewport.Y
		--[[ ...and only when the arrow is stacked VERTICALLY on this box, which is the case the gap
			is for. A side-mounted arrow is beside the target rather than between it and the card, so
			padding the vertical candidates for it would push the card a whole arrow away from a
			thing nothing is standing between. Those cases are covered by `_obstacles` instead, which
			scores the arrow's live rectangle wherever it is. ]]
		local axis = self._arrowAxis
		if self._arrow and self._arrow.Visible and self._aimBox == box and (not axis or axis.X == 0) then
			local arrowCfg = TutorialConfig.Arrow
			gap += self._arrow.AbsoluteSize.Y * (1 + arrowCfg.Standoff + arrowCfg.Bob)
		end

		local midX = at.X + (boxSize.X - size.X) * 0.5
		local midY = at.Y + (boxSize.Y - size.Y) * 0.5
		local above = at.Y - gap - size.Y
		local below = at.Y + boxSize.Y + gap
		local candidates = {
			{ midX, above }, -- over it, centred, which is the reading the card is drawn for
			{ midX, below }, -- ...and under it
			{ at.X + boxSize.X + gap, midY }, -- beside it, on the right
			{ at.X - gap - size.X, midY }, -- ...and on the left
			{ restX, below }, -- under it and out to the corners, clear of a bottom-centre HUD
			{ farX, below },
			{ restX, above },
			{ restX, restY }, -- and the resting spot, for a screen with nowhere else at all
		}

		local rects = self:_obstacles(box)
		local best = math.huge
		--- ...and STAY PUT while the spot it is in is still clean, rather than hopping to an earlier one.
		local kept = self._placeSpot
		if kept and box == self._placeSpotBox and covered(kept.X, kept.Y, size, rects) <= 0 then
			best, x, y = 0, kept.X, kept.Y
		end
		for _, candidate in candidates do
			if best <= 0 then
				break
			end
			local tryX = math.clamp(candidate[1], margin, maxX)
			local tryY = math.clamp(candidate[2], guard, maxY)
			local score = covered(tryX, tryY, size, rects)
			if score < best then
				best, x, y = score, tryX, tryY
			end
		end
		self._placeSpot, self._placeSpotBox = Vector2.new(x, y), box
	end

	--- Glides to the spot rather than teleporting (`PLACE_GLIDE` of the way per frame). Only by a box,
	--- which the per-frame loop re-places; the resting corner is placed once, so it snaps, and so does
	--- a card within a couple of pixels, so a resting card is exactly on its pixel.
	local current = self._card.Position
	local fromX, fromY = current.X.Offset, current.Y.Offset
	local dx, dy = x - fromX, y - fromY
	if not box or math.abs(dx) + math.abs(dy) < 2 then
		self._card.Position = UDim2.fromOffset(math.round(x), math.round(y))
	else
		self._card.Position = UDim2.fromOffset(math.round(fromX + dx * PLACE_GLIDE), math.round(fromY + dy * PLACE_GLIDE))
	end
end

function TutorialController._clearArrow(self)
	if self._arrow then
		self._arrow.Visible = false
	end
	self._aimBox = nil
	self._aimAt = nil
	self:_pulseOff()
end

function TutorialController._clearChip(self)
	if self._chipInst then
		self._chipInst:Destroy()
		self._chipInst = nil
	end
	if self._chipGlow then
		self._chipGlow:Destroy()
		self._chipGlow = nil
	end
end

--[[ PUBLIC (GetawayHudController) — the world thing this tutorial is pointing at right now, or nil.

	It exists so that the getaway marker and this chip can never both be floating over the truck.
	They are the same idea aimed at the same object — a glyph over a thing in the world with the
	distance counting down under it — and a first-timer on the BANK beat would otherwise get two of
	them, stacked, bobbing out of phase.

	THE TEST IS THE ONE THE RIDE LOOP USES, deliberately: `_chip_` is a plain field that `_clearChip`
	does not nil out (only `_chipInst` is tracked for destruction), so a chip that has been cleared
	leaves its table behind and asking `self._chip_ ~= nil` would answer yes forever. What actually
	means "there is a chip on screen" is its billboard still being parented, which is exactly what
	`_ensureLoop` checks before riding it. ]]
function TutorialController.getChipTarget(self): BasePart?
	local chip = self._chip_
	if not (chip and chip.billboard and chip.billboard.Parent and chip.part and chip.part.Parent) then
		return nil
	end
	return chip.part
end

function TutorialController._clearPointer(self)
	self:_clearArrow()
	self:_clearChip()
	--- Nothing is being pointed at, so there is nothing left to keep asking about.
	self._follow = nil
	self:_stopLoop()
end

--- Is `MainUI.Pages.<name>` on screen? The pages set `Visible` on their own frames, which is what
--- `GamepadNav` reads for the same question — so the two can never disagree about what is open.
function TutorialController._pageOpen(self, name: string): boolean
	local pages = self._mainUI and self._mainUI:FindFirstChild("Pages")
	local page = pages and pages:FindFirstChild(name)
	return page ~= nil and page:IsA("GuiObject") and page.Visible
end

--- Walk a declared path to a GuiObject, from `MainUI.HUD` or from a page. Nil at any missing hop —
--- see `_repoint` on why that is ordinary.
function TutorialController._findGui(self, target): GuiObject?
	local node: Instance? = nil
	if target.Kind == "Hud" and target.Gui then
		--- A HUD outside `MainUI` (the race's `DrivingHud`), named by its ScreenGui.
		local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		node = playerGui and playerGui:FindFirstChild(target.Gui)
	elseif target.Kind == "Hud" then
		node = self._mainUI and self._mainUI:FindFirstChild("HUD")
	else
		local pages = self._mainUI and self._mainUI:FindFirstChild("Pages")
		node = pages and pages:FindFirstChild(target.Page)
	end
	--- The kit's pages keep their rows somewhere else, so a link may name its V2 path beside the old
	--- one. See `TutorialConfig.TeleportPathV2`.
	local path = if UIRoot.isNewUI() and target.PathV2 then target.PathV2 else target.Path
	for _, hop in path do
		if not node then
			return nil
		end
		node = node:FindFirstChild(hop)
	end
	if node and node:IsA("GuiObject") and node.Visible then
		return node
	end
	return nil
end

--[[ The world chip: a bobbing pill over a thing standing in the map, with a chevron under it
	pointing at the thing and the distance under that.

	A BILLBOARD RATHER THAN THE SCREEN ARROW, because a screen arrow at a world target has to be
	projected, clamped to the viewport when the target is behind you, and re-aimed every frame the
	camera moves — three problems a billboard does not have, in exchange for not being visible
	through walls, which `AlwaysOnTop` fixes. Sized in OFFSET so it stays legible at the far end of
	a forecourt instead of growing with distance — see `CHIP_REF_STUDS` for the second half of that,
	which is the hand-driven shrink the far end needs. ]]
function TutorialController._chip(self, part: BasePart, above: boolean?, overSign: boolean?)
	--[[ ONE CHIP, ALWAYS. Only the newest is tracked (`_chipInst`) and therefore only the newest can
		ever be destroyed, so building one without clearing the last leaves the old billboard parented
		to the PlayerGui with `ResetOnSpawn` off — it does not go away on a respawn, on a hide, or when
		the beat ends. Every re-resolve of a world target is a re-build (a page opening, the card
		coming back after the results screen, a retry landing), so the COLLECT beat stacked three of
		these on one mat inside a single session before this line existed. ]]
	self:_clearChip()

	local height = self:_chipHeight(part, above)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TutorialChip"
	billboard.Adornee = part
	billboard.Size = CHIP_SIZE
	billboard.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = math.huge
	billboard.ResetOnSpawn = false

	local pill = Instance.new("ImageLabel")
	pill.Name = "Pill"
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Position = UDim2.fromScale(0.5, 0.28)
	pill.Size = UDim2.fromScale(1, CHIP_PILL_HEIGHT)
	pill.BackgroundTransparency = 1
	pill.Image = UIAssets.url(UIAssets.Pill.Orange.Idle)
	-- Stretch, never Slice — the box holds the art's aspect, so the whole image shrinks uniformly
	-- and Slice would only pin the corner curve at texture pixels. See `UIAssets.Slice.Pill`.
	pill.ScaleType = Enum.ScaleType.Stretch
	pill.Parent = billboard

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.46)
	label.Size = UDim2.fromScale(0.86, 0.5)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	local face = self:_face(self._step)
	label.Text = oneLine(self:_fill(face.Title, face.Fill))
	label.TextColor3 = WHITE
	label.TextScaled = true
	label.Parent = pill

	--[[ The same arrow the screen pointer uses, under the pill and aimed at the thing. Its own
		instance rather than a shared one: that pointer is parented into the card's gui and this one
		has to live inside a billboard.

		No bob and no rotation of its own — the whole billboard bobs (see the loop), and a chip is
		always directly above the thing it names, so down is the only direction it ever points. ]]
	local point = Instance.new("ImageLabel")
	point.Name = "Point"
	point.AnchorPoint = Vector2.new(0.5, 0.5)
	point.Position = UDim2.fromScale(0.5, 0.63)
	--- In SCALE, unlike everything else here that is in pixels, so it rides the distance shrink with
	--- the rest of the chip. Square only because the box holds its aspect — which it does, because
	--- the shrink scales both sides by the same number. See `CHIP_REF_STUDS`.
	point.Size = UDim2.fromScale(CHIP_SIZE.Y.Offset * 0.34 / CHIP_SIZE.X.Offset, 0.34)
	point.BackgroundTransparency = 1
	point.Image = UIAssets.url(UIAssets.Tutorial.Arrow)
	point.ScaleType = Enum.ScaleType.Stretch
	point.Parent = billboard

	local distance = Instance.new("TextLabel")
	distance.Name = "Distance"
	distance.AnchorPoint = Vector2.new(0.5, 0.5)
	distance.Position = UDim2.fromScale(0.5, 0.9)
	distance.Size = UDim2.fromScale(1, 0.18)
	distance.BackgroundTransparency = 1
	distance.FontFace = FONT
	distance.Text = ""
	distance.TextColor3 = WHITE
	distance.TextTransparency = 0.25
	distance.TextScaled = true
	distance.Parent = billboard

	--- Matched to the text's own transparency rather than left solid, so the outline can never read
	--- as more present than the glyph it is outlining. See `CHIP_STROKE`.
	local distanceStroke = Instance.new("UIStroke")
	distanceStroke.Color = CHIP_STROKE_COLOR
	distanceStroke.Thickness = CHIP_STROKE -- sized against the chip's scale on every ride
	distanceStroke.Transparency = distance.TextTransparency
	distanceStroke.LineJoinMode = Enum.LineJoinMode.Round
	distanceStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	distanceStroke.Parent = distance

	billboard.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self._chipInst = billboard

	--- A buyer is outlined too, and stays outlined after the chip gives way to their sign.
	local model = if overSign then part:FindFirstAncestorWhichIsA("Model") else nil
	if model then
		local glow = Instance.new("Highlight")
		glow.Name = "TutorialBuyerGlow"
		glow.Adornee = model
		glow.FillColor = BUYER_GLOW
		glow.OutlineColor = BUYER_GLOW
		glow.FillTransparency = BUYER_GLOW_FILL[1]
		glow.OutlineTransparency = 0
		glow.DepthMode = Enum.HighlightDepthMode.Occluded
		glow.Parent = model
		self._chipGlow = glow
	end
	self._chip_ = {
		billboard = billboard,
		part = part,
		distance = distance,
		stroke = distanceStroke,
		height = height,
		scale = 1,
		overSign = overSign,
	}
	--- Placed once here as well as in the loop, so the first frame it is on screen is already the
	--- right size and height rather than a full-size flash that shrinks.
	self:_chipRide(self._chip_, 0)
end

--[[ How big the chip is and how high it rides, which are both facts about where the CAMERA is and
	so are answered in one place, once a frame.

	=== THE SIZE ==============================================================================

	`CHIP_REF_STUDS` has the reasoning. The write is gated on the number having actually moved,
	because a `Size` write re-lays-out four descendants and the chip spends most of its life sat
	against one of the two clamps; a fifth of a percent is under a pixel on the widest side.

	=== THE HEIGHT ============================================================================

	An overhead chip has a range problem the hung-below one does not: 4 studs above the roof of a
	22-stud truck is 26 studs up, which is a gentle angle at three hundred studs out and straight
	overhead at twenty. Left alone the chip climbs off the top of the screen over the last seconds
	of the chase — the exact moment the player is lining up on the ramp.

	So the authored height is a CEILING rather than a position: the chip sits at the roof while
	that is in shot and slides down the back of the truck as the player closes, staying inside a
	cone about the eye. `CHIP_RISE` is the tangent of that cone's half-angle, comfortably inside
	the camera's own, so the chip is in the frame rather than at the edge of it.

	It only ever LOWERS a chip: `CHIP_CLEAR` floors it, so a mat that already sits at that height
	never moves and a target hung below its own bottom edge is left where it is. ]]
function TutorialController._chipRide(self, chip, bob: number)
	local camera = workspace.CurrentCamera
	local height = chip.height
	if camera then
		local eye = camera.CFrame.Position
		local to = chip.part.Position - eye
		local away = to.Magnitude

		local want = math.clamp(CHIP_REF_STUDS / math.max(away, 1), CHIP_MIN_SCALE, 1)
		if math.abs(want - chip.scale) >= 0.002 then
			chip.scale = want
			--- Fractional pixels rather than rounded ones, so the box's aspect is exact at every
			--- size and the stretched pill art never skews by a rounding pixel.
			chip.billboard.Size = UDim2.fromOffset(CHIP_SIZE.X.Offset * want, CHIP_SIZE.Y.Offset * want)
			--- Under the same gate as the size, and for the same reason: the outline is quoted at the
			--- full chip and has to shrink with the text or it thickens into it. See `CHIP_STROKE`.
			chip.stroke.Thickness = CHIP_STROKE * want
		end

		--- Off the FLAT distance, because the cone is about how far the eye has to look up, and a
		--- straight-line distance would let the chip creep up as the camera rose.
		local flat = Vector3.new(to.X, 0, to.Z).Magnitude
		local ceiling = (eye.Y + flat * CHIP_RISE) - chip.part.Position.Y
		height = math.min(height, math.max(ceiling, CHIP_CLEAR))
	end
	--- Over a buyer: hidden while their offer sign is up. See `BUYER_GLOW`.
	if chip.overSign then
		local sign = chip.part.Parent and chip.part.Parent:FindFirstChild(BUYER_SIGN)
		chip.billboard.Enabled = not (sign and sign:IsA("BillboardGui") and sign.Enabled)
	end
	chip.billboard.StudsOffsetWorldSpace = Vector3.new(0, height + bob, 0)
end

--- Studs above the target's own origin to float the chip. See the note on `CHIP_TALL`.
function TutorialController._chipHeight(self, part: BasePart, above: boolean?): number
	local half = part.Size.Y * 0.5
	if above then
		--[[ Overhead, and measured off the MODEL the part belongs to rather than off the part: what
			`GetawayController.getTruck` hands back is the truck's PrimaryPart, which is a box
			somewhere inside the bodywork, and clearing that clears nothing. The bounding box is the
			world one, so its centre is a world height and the truck's yaw does not enter into it.

			A part with no model ancestor falls back to its own top, which is the honest answer for
			one. ]]
		local model = part:FindFirstAncestorWhichIsA("Model")
		if model then
			local box, size = model:GetBoundingBox()
			return (box.Position.Y - part.Position.Y) + size.Y * 0.5 + CHIP_CLEAR
		end
		return half + CHIP_CLEAR
	end
	if half > CHIP_TALL then
		return -half - CHIP_DROP
	end
	return half + CHIP_CLEAR
end

--[[ The one per-frame connection in this file, and it exists ONLY while something is being pointed
	at or a beat is waiting on an input — the same rule `CarViewportGrid` states about its build
	queue. A tutorial that kept a RenderStepped alive through a whole session for a card with
	nothing to point at would be paying for the feature at the moments it is doing nothing.

	It drives four things that all want the same clock: the arrow's bob, the card riding whatever it
	is sitting above (a page scales open; the rail is laid out rather than placed), the chip's bob
	and distance line, and the input beat's own watcher. ]]
function TutorialController._ensureLoop(self)
	if self._loop then
		return
	end
	local start = os.clock()
	self._loop = RunService.RenderStepped:Connect(function(dt: number)
		local elapsed = os.clock() - start

		local arrow = self._arrow
		if arrow and arrow.Visible and self._aimBox then
			--[[ The bob rides ON TOP of the travel tween rather than fighting it: the tween owns
				`Position` while it runs, so the bob only starts once the arrow has arrived.

				=== SETTLED IS A CLOCK, NOT A MEASUREMENT =====================================

				This asked "is the arrow within 3px of home?", which is a question that answers
				itself wrong the moment the bob starts: the swing is a FIFTH OF THE ARROW — 22px at
				a 99px arrow — so one frame after the bob began, the arrow was 4px from home, the
				test said "still travelling", and the bob switched itself off. It then sat at the
				boundary flicking in and out of settled, a pixel at a time. That is the choppiness;
				the arrow was never bobbing, it was oscillating against its own gate.

				The travel is a tween of known length, so when it ends is known without looking. ]]
			local home = self._arrowHome
			local settled = elapsed + start >= (self._arrowRestAt or 0)
			if settled then
				--[[ MEASURED FROM WHEN THE BOB TOOK OVER, not from when the loop started, and that
					is the difference between a bob and a snap. A free-running sine is at some
					arbitrary point in its cycle the moment a travel ends — the tween lands the
					arrow exactly on home, and the first bob frame then moves it up to a FULL swing
					away in one frame. Anchored, the swing is zero at the handover and grows out of
					it, so the two motions join without a seam. ]]
				local swing = math.sin((elapsed + start - self._bobFrom) * math.pi * 2 / TutorialConfig.Arrow.BobPeriod)
				--- Along the axis it points, so a side-mounted arrow nods sideways at its target
				--- rather than bobbing up and down beside it.
				local reach = (self._arrowAxis or Vector2.new(0, 1)) * (arrow.AbsoluteSize.Y * TutorialConfig.Arrow.Bob * swing)
				arrow.Position = self:_arrowPos(home.X + reach.X, home.Y + reach.Y)
			end

			--- ...and the card rides along with whatever it is sitting above, which is not still.
			if self._placeBox then
				self:_place(self._placeBox)
			end
			--[[ ...and the arrow follows a target that has moved for its own reasons.

				=== IT WATCHES THE TARGET, NOT THE ARROW =====================================

				This compared the target's centre X against the ARROW's home X, and those two
				agree only on the two sides where the arrow sits directly over or under the box.
				On a LEFT/RIGHT aim they are half a box plus the standoff apart BY CONSTRUCTION,
				so the test read "it moved" on a target sitting perfectly still — every frame,
				for the whole beat. And a side aim is not the rare case: it is what a page card
				gets, which is the SELECT CAR beat, which is the first pointer most players see.

				What that looked like is the thing this fixes, and it was not a smoothing
				problem. Every false positive restarted the 0.45s travel tween, `settled` went
				false for the whole of it, and the bob was gated off for that time and then given
				a single frame in which its sine had advanced HALF A PERIOD — so the arrow
				snapped its entire swing in one frame, crawled back under the tween, and did it
				again 0.45 seconds later.

				So it is measured against what the arrow was actually aimed at, and on both axes:
				a page scales open vertically as well as horizontally. ]]
			local aimed = self._aimAt
			if aimed and settled and self._aimBox.Parent and self._aimBox.Visible then
				local at = self._aimBox.AbsolutePosition - self._root.AbsolutePosition
				local centre = at + self._aimBox.AbsoluteSize * 0.5
				if math.abs(centre.X - aimed.X) > 2 or math.abs(centre.Y - aimed.Y) > 2 then
					self:_aimArrow(self._aimBox, true)
				end
			end
		end

		local pulse = self._pulseScale
		if pulse and pulse.Parent then
			--[[ A sine rather than a ping-pong tween: it has no corner at either end, so the button
				reads as breathing rather than as flashing. Multiplied onto the scale the button was
				found at, so a hover the component is running underneath this still shows. ]]
			local phase = (math.sin(elapsed * math.pi * 2 / TutorialConfig.Pulse.Period) + 1) * 0.5
			pulse.Scale = (self._pulseBase or 1) * (1 + (TutorialConfig.Pulse.Scale - 1) * phase)
		end

		--- The buyer's outline breathes on the same clock. See `BUYER_GLOW_FILL`.
		local glow = self._chipGlow
		if glow and glow.Parent then
			local phase = (math.sin(elapsed * math.pi * 2 / TutorialConfig.Pulse.Period) + 1) * 0.5
			glow.FillTransparency = BUYER_GLOW_FILL[1] + (BUYER_GLOW_FILL[2] - BUYER_GLOW_FILL[1]) * phase
		end

		local chip = self._chip_
		--- A FOLLOWED target that left the world (a buyer sent away) is asked again rather than
		--- ridden as a dead chip; `_repoint` falls back to the beat's other face or to a retry.
		if chip and self._follow and not chip.part.Parent then
			self:_repoint()
			chip = self._chip_
		end
		if chip and chip.billboard.Parent and chip.part.Parent then
			self:_chipRide(chip, math.sin(elapsed * math.pi * 2 / BOB_PERIOD) * BOB_STUDS)

			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				local studs = (root.Position - chip.part.Position).Magnitude
				chip.distance.Text = string.format(TutorialConfig.DistanceFormat, math.floor(studs))
			else
				chip.distance.Text = ""
			end

			--[[ ...and LAST, because it may replace the chip this block has been working on: a
				following target is asked again on `FOLLOW_INTERVAL` and the pointer moves when the
				answer is a different object (the nearest free bay, as the player walks past one).

				An answer of nil leaves the chip where it is rather than taking it down. The plot
				streaming out is not the player having nowhere to park. ]]
			local follow = self._follow
			if follow and os.clock() - (self._followAt or 0) >= FOLLOW_INTERVAL then
				self._followAt = os.clock()
				local want = self:_findWorld(follow)
				if want and want ~= chip.part then
					self:_chip(want, follow.Above, follow.OverSign)
				end
			end
		end

		self:_watchBeat(dt)
	end)
end

function TutorialController._stopLoop(self)
	--- Not while a beat still needs watching: the loop serves both the pointer and the input, and a
	--- world target coming and going must not take the watcher with it.
	if self._loop and not self._watching then
		self._loop:Disconnect()
		self._loop = nil
	end
	self._chip_ = nil
end

-- === Finding things in the map ==============================================

--[[ The plot this player holds, found by the owner stamp rather than by walking `Map.Plots`.

	BY TAG, and that is not a style preference: `StreamingEnabled` is on in this place, so a path
	walk finds nothing at all until the geometry has arrived, and can find it at any moment
	afterwards. ]]
function TutorialController._myPlot(self): Model?
	local userId = Players.LocalPlayer.UserId
	for _, plot in CollectionService:GetTagged(PlotConfig.PlotTag) do
		if plot:GetAttribute(PlotConfig.OwnerUserIdAttribute) == userId then
			return plot :: Model
		end
	end
	return nil
end

--- Resolve a "World" target to the part the chip should float over.
function TutorialController._findWorld(self, target): BasePart?
	--- The truck is on the road rather than on the lot, so it is answered before the plot is even
	--- looked for — a player mid-race is nowhere near their forecourt.
	if target.What == "Truck" then
		return self:_truck()
	end

	--- ...and so is the nearest free bay, for the opposite reason: it is not a bay the server named
	--- but one answered against this player's own lot by `CarryController`, which has already found
	--- that lot. See `_freeBay`.
	if target.What == "FreeBay" then
		return self:_freeBay()
	end

	--- A buyer walks across the lot, so the chip rides them rather than the bay. See `_buyer`.
	if target.What == "Buyer" then
		return self:_buyer()
	end

	local plot = self:_myPlot()
	if not plot then
		return nil
	end

	if target.What == "Bay" then
		--[[ The mat in front of the bay the car parked on — `Collect/CashButton`, which is the part
			`GarageService` watches for a foot. Pointing at the PODIUM would be pointing at the car,
			which is not the thing the objective asks the player to walk onto. ]]
		local bay = self._bay
		if not bay then
			return nil
		end
		for _, slot in CollectionService:GetTagged(GarageConfig.SlotTag) do
			if slot:IsDescendantOf(plot) and slot:GetAttribute(GarageConfig.SlotIndexAttribute) == bay then
				local collect = slot:FindFirstChild(GarageConfig.Collect.ButtonName, true)
				if collect and collect:IsA("BasePart") then
					return collect
				end
			end
		end
	end

	return nil
end

--[[ The bay the PLACE beat points at: the nearest podium on this player's own lot that the car in
	their hands could go on.

	THE LIST IS `CarryController`'S, NOT THIS FILE'S. Which decks a carried car may be put down on is
	that controller's question and it already answers it every quarter second to decide what to light
	up — whose floor a podium is on, whether a car is standing on it, whether the storey it belongs to
	has been bought. A second copy of that walk here is a second copy that has to stay right, and it
	would be wrong in exactly the way the glow is not: the arrow would name a bay the glow did not
	light.

	WHICH IS ALSO WHY A MISSING CONTROLLER IS NOT AN ERROR. With `CarryConfig` off there is no carry,
	the car parks itself and this beat is satisfied the instant it is published, so there is nothing
	to point at and nothing to complain about.

	THE ONE ALREADY NAMED WINS TIES by `FOLLOW_MARGIN` — see the note on it. `getChipTarget` is the
	right question for "which bay is named" rather than a field of our own, because it is the same
	test the ride loop uses: a chip whose billboard has gone is not naming anything. ]]
function TutorialController._freeBay(self): BasePart?
	local carry = Shard.get("CarryController")
	if not carry then
		return nil
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local here = (root :: BasePart).Position

	local current = self:getChipTarget()
	local best: BasePart? = nil
	local bestAway = math.huge
	--- How far the chip's current bay is, or nothing when it is not on the list any more — a car
	--- landed on it, the storey went away, the plot streamed out.
	local held: number? = nil

	for _, deck in carry:getFreeDecks() do
		local away = (deck.Position - here).Magnitude
		if deck == current then
			held = away
		end
		if away < bestAway then
			best, bestAway = deck, away
		end
	end

	if held and bestAway > held - FOLLOW_MARGIN then
		return current
	end
	return best
end

-- === Holding the game =======================================================

--[[ Stop the world, or let it go. The whole of this feature's contract with `RaceFreezeController`.

	ONE NAME, ALWAYS (`FREEZE_KEY`), and never in the lobby: `Where` says which half of the game a
	beat is in, and a hold placed in a lobby would anchor a car that is not in a race. Freezing is
	therefore refused rather than made harmless, so a beat marked `Freeze` in the wrong half fails
	visibly during authoring rather than quietly at a player.

	THE TIMEOUT IS A BACKSTOP AND NOT A TIMER — see `FREEZE_TIMEOUT`. It is armed on the way in and
	cancelled by the token on the way out, so a beat that ends normally never sees it. ]]
function TutorialController._freeze(self, on: boolean)
	local freeze = Shard.get("RaceFreezeController")
	if not freeze then
		return
	end

	if not on then
		self._freezeToken += 1
		if self._frozen then
			self._frozen = false
			freeze:release(FREEZE_KEY)
			self:_dimTo(false)
		end
		return
	end

	if self._frozen then
		return
	end
	self._frozen = true
	freeze:hold(FREEZE_KEY)
	self:_dimTo(true)

	self._freezeToken += 1
	local token = self._freezeToken
	task.delay(FREEZE_TIMEOUT, function()
		if self._freezeToken == token and self._frozen then
			self.log:warn(
				string.format(
					"A tutorial freeze on beat '%s' ran past %d seconds and was released. The beat is still up; the world is not held again for it.",
					self._step and self._step.Id or "?",
					FREEZE_TIMEOUT
				)
			)
			--- BEFORE the release, not after: `_watchFreeze` can re-apply the hold on the very next
			--- frame, and a forfeit written after that has already lost. See `FREEZE_TIMEOUT`.
			self._freezeForfeit = self._step and self._step.Id or nil
			self:_freeze(false)
		end
	end)
end

--- The sheet behind a frozen beat. Tweened rather than switched, because the freeze itself lands in
--- one frame and something on screen has to carry the transition.
function TutorialController._dimTo(self, on: boolean)
	local dim = self._dim
	if not (dim and TutorialConfig.Dim.Enabled) then
		return
	end
	if on then
		dim.BackgroundTransparency = 1
		dim.Visible = true
		self:_tween(dim, TutorialConfig.Dim.Fade, { BackgroundTransparency = 1 - TutorialConfig.Dim.Opacity })
		return
	end
	local out = self:_tween(dim, TutorialConfig.Dim.Fade, { BackgroundTransparency = 1 })
	out.Completed:Once(function()
		if not self._frozen then
			dim.Visible = false
		end
	end)
end

-- === Gating the lobby =======================================================

--[[ Make one button the only one that works, or lift that.

	The whole of the mechanism is remembering WHICH button; `blocksPress` is the half that anybody
	else sees. Nothing is switched off and nothing has to be restored, which is what makes this safe
	to call on every repoint, every hide and every teardown.

	NOTHING IS EXEMPT ANY MORE. There used to be one — the card's own SKIP, which had to work from
	inside the cage because it was the way out of a beat somebody could not complete. With the SKIP
	word gone the exemption has nothing to name, and what covers the stuck player is the freeze's own
	timeout (`FREEZE_TIMEOUT`). A gate is a lobby thing and does not stop the world, so it was never
	the half of this that could trap anybody for long. ]]
function TutorialController._setGate(self, target: GuiObject?)
	self._gateTarget = target
end

--[[ PUBLIC (UIController/ButtonPress) — should this press be refused?

	True only while a gate is up and `instance` is not the button being pointed at. Bumps as a side
	effect, because every caller that asks this is about to drop the press and the bump is the only
	thing that tells the player why.

	SAFE TO CALL ALWAYS. With no gate up — which is every beat but one, and the whole game once the
	tutorial is done — this is one nil comparison and a `false`. ]]
--- Public (ReviveController): is the tutorial still running? The end panel goes home rather than
--- racing again on its own while it is, because the next beat is waiting in the lobby.
function TutorialController.isActive(self): boolean
	return self._step ~= nil
end

function TutorialController.blocksPress(self, instance: GuiObject?): boolean
	local target = self._gateTarget
	if not target or instance == target then
		return false
	end
	self:_bump()
	return true
end

--[[ A press the gate refused. Throw the arrow at the button that would have worked, so the refusal
	reads as a redirection rather than as a dead button.

	THE ARROW IS THE WHOLE ANSWER NOW. Both faces that gate — the PLAY beat and `Offroad` — are
	pointer only, so the objective punch below lands on a card that is not on screen. It is left in
	rather than removed because the punch is what a CARDED gated face would want, and a beat gaining
	one should not also have to remember to put this back.

	THE ARROW IS RE-AIMED AT WHERE IT ALREADY IS, deliberately. `_aimArrow` tweens whenever the arrow
	is already visible, so re-aiming it at its own home tweens from wherever the bob currently has it
	back to that home — a small flick toward the target, for free, with no second animation to keep
	in step with the first.

	Guarded on there being something to point at: a gate with no resolved target should not be up at
	all (`_applyGate` requires one), and if it somehow is, a silent press is better than a punch at
	nothing. ]]
function TutorialController._bump(self)
	if not (self._open and self._aimBox and self._aimBox.Parent) then
		return
	end
	self:_punch(self._titleScale, 1.12)
	self:_aimArrow(self._aimBox)
end

-- === Watching for an input ==================================================

--[[ Arm the watcher for a beat whose completion only this client can see.

	FOUR THINGS TO WATCH and they all reduce to a per-frame poll, which is why there is no
	subscription anywhere in here. Every one of them is a value some other controller is already
	computing every frame for its own reasons, so a poll costs a table read and cannot leak:

	    Accelerate  `DriveController:getThrottleInput()` — device-agnostic, and deliberately still
	                live while the shim is suspended, which a frozen car always is.
	    Steer       `DriveController:getSteerInput()` — likewise, and likewise the same number for a
	                key, a stick, the touch slider and the on-screen arrows.
	    Bail        `StealController:getFlight()` leaving "idle" — the JUMP is watched by its EFFECT
	                rather than by its key, so a bail that the steal refused for its own reasons
	                (mid-wreck, no road) does not count as one.
	    Timer       accumulated real time, for SURVIVE.

	THE POLL IS ON REAL TIME, not on the scaled clock. Two of these beats hold the world at zero,
	and a watcher driven off `dt * TimeScale.get()` would never advance during the exact beat it
	exists to end. `RenderStepped`'s dt is what this takes.

	GRACE IS COUNTED FIRST and nothing may complete inside it. Its real job is the freeze — see
	`Grace` on the BOOST beat — but applying it to completion as well closes a race where a player
	holding accelerate from the previous run satisfies the beat on the frame it arrives. ]]
function TutorialController._armBeat(self, step)
	self._watching = nil
	self._count = 0
	self._beatTime = 0
	self._holdTime = 0
	self:_resetMeters()
	self._steerSeen = { [-1] = false, [1] = false }
	self._bailSeen = false
	--- A beat that arms is a fresh attempt at it, including one the timeout took the freeze away
	--- from on a previous race. See `FREEZE_TIMEOUT`.
	self._freezeForfeit = nil
	--- ...and the latch for a freeze this beat's own input lifted. Cleared per race too, in `_onRaceLive`.
	self._freezeSpent = nil
	--- The AIRBORNE freeze's two: the closest the arc has come to the car it is going to take, and
	--- whether that minimum has been passed. See `_watchFreeze`.
	self._airNear = nil
	self._airHold = false
	--- SELL's once-per-arrival latches (`_stepWatched`, `_stepLook`), any camera turn still going,
	--- and the guide line to its buyer (`_stepGuide`).
	self._pinged = nil
	self._looked = nil
	self:_stopLook()
	self:_pointGuide(nil)

	--[[ A beat needs watching if this client has to CLOSE it or has to FREEZE for it, and those are
		not the same set. AIRBORNE is closed by the server (the steal is ratified there) and still
		wants a frame loop, because its hold goes on and comes off with the arc rather than with a
		clock — see `FreezeWhen` on that beat.

		A beat that is neither is genuinely nothing to do: the server will say when it is over. ]]
	local advance = step.Advance
	if advance.Kind ~= "Input" and advance.Kind ~= "Timer" and not step.Freeze and not step.Arrived then
		return
	end
	self._watching = step
	self:_ensureLoop()
end

function TutorialController._disarmBeat(self)
	self._watching = nil
	self:_stopLoop()
end

--[[ One frame of the live beat. Also where a freeze is applied, because "may this beat freeze yet"
	and "has this beat finished" are the same clock and the same guards. ]]
function TutorialController._watchBeat(self, dt: number)
	local step = self._watching
	if not (step and step == self._step and self._open) then
		return
	end
	--- Before the race and grace checks below: the meter decides for itself whether it is up, and it
	--- is up through the grace, so BOOST's target is on screen before the freeze bites.
	self:_stepMeter(step, dt)
	--[[ A race beat with no race under it is a beat nobody can be doing, and the card is showing the
		off-road face rather than the objective. Nothing may advance here — most of all the SURVIVE
		timer, which would otherwise count its eight seconds down while the player stood in their
		dealership and hand them a beat they had not been shown. ]]
	if step.Where == "Race" and not self:_inRace() then
		self._beatTime = 0
		self._holdTime = 0
		return
	end
	self._beatTime += dt

	--[[ Has the FACE changed under a beat that has not? One beat can do this mid-run — BANK, the
		moment the truck spawns — and there is no event for it, because what changed is a thing on
		the road rather than a decision anybody made. `_refresh` is a no-op when the face is the same
		one already drawn, so asking every frame costs a table comparison.

		Before the grace check rather than after it: a face is about what the card SAYS, and there is
		no reason for it to wait on a timer that exists to hold back a freeze. ]]
	if self:_face(step) ~= self._drawnFace then
		self:_refresh()
	end
	--- SELL's jobs on this side (2026-10-19): say when its card is up, turn to its buyer, and draw
	--- the line to them once they stand.
	self:_stepWatched(step)
	self:_stepLook(step)
	self:_stepGuide(step)

	local grace = step.Grace or 0
	if self._beatTime < grace then
		return
	end

	if step.Freeze and step.Where == "Race" then
		self:_watchFreeze(step)
	end

	local advance = step.Advance
	if advance.Kind == "Signal" then
		return -- the server closes it; this beat was only being watched for its freeze
	end

	if advance.Kind == "Timer" then
		if self._beatTime - grace >= (advance.Seconds or 0) then
			self:_beatDone()
		end
		return
	end

	local drive = Shard.get("DriveController")

	if advance.Input == "Accelerate" then
		local held = drive and drive:getThrottleInput() > 0.1
		if held then
			--[[ THE FREEZE LIFTS ON THE FIRST FRAME OF THE HOLD, and the beat completes at the end
				of `HoldSeconds`. That split is the whole feel of this beat: the car pulls away the
				instant the key goes down, so the player learns that the key is what moved them, and
				the card only ticks over once they have held it long enough for the hold to have been
				deliberate. Debouncing the car as well would teach that the control is laggy. ]]
			--[[ AND IT STAYS LIFTED. `_watchFreeze` runs earlier in this same frame and re-applies an
				"Arrival" hold whenever the world is not held, so without this latch the hold went on
				and came off again EVERY FRAME for as long as the key was down. Each release puts
				back the velocity the hold stashed, so the car could not gain speed: it sat at about
				52 MPH with boost engaged, and letting go of the key stopped the world dead. Invisible
				while the beat lasted a quarter of a second; the speed bar made it the whole beat.

				The freeze is a wait for the FIRST press. Once that has come, the car is the
				player's, and the card goes on teaching the rest with the world running. ]]
			self._freezeSpent = step.Id
			self:_freeze(false)
		end

		--[[ WITH THE SPEED METER, THE BEAT CLOSES ON A SPEED, not on a length of hold. A tap used to
			finish it before the car had visibly done anything. Now the car has to be at the bar's
			target with the key still down, and the target sits above cruise, so letting go leaves
			the bar short of full. `GiveUpSeconds` of key-down time closes it anyway, for a car that
			cannot reach the number. See `TutorialConfig.Meters`. ]]
		if self:_meterOf(step) == "Speed" then
			if held then
				self._barHeld += dt
				local reached = self._barMph >= self:_barTarget()
				if reached or self._barHeld >= TutorialConfig.Meters.Speed.GiveUpSeconds then
					self:_beatDone()
				end
			end
			return
		end

		if held then
			self._holdTime += dt
			if self._holdTime >= TutorialConfig.HoldSeconds then
				self:_beatDone()
			end
		else
			self._holdTime = 0
		end
		return
	end

	if advance.Input == "Steer" then
		local value = if drive then drive:getSteerInput() else 0
		--[[ COUNTED PER DIRECTION, so leaning on one key does not finish it. The threshold is well
			off zero because a stick at rest is not exactly zero and a slider being released passes
			through small values on its way back. ]]
		if math.abs(value) > 0.4 then
			local side = if value > 0 then 1 else -1
			if not self._steerSeen[side] then
				--[[ WITH THE ARROWS, A DIRECTION COUNTS ONCE ITS ARROW IS FULL, which takes holding
					it for about one lane change (`Meters.Steer.HoldSeconds`). A held share is kept
					when the key comes up, so two short nudges fill it as well as one long one. ]]
				if self:_meterOf(step) == "Steer" then
					self._steerHold[side] += dt
					if self._steerHold[side] < TutorialConfig.Meters.Steer.HoldSeconds then
						return
					end
					self:_arrowFilled(side)
				end
				self._steerSeen[side] = true
				self._count += 1
				self:_paint(step, false)
				if self._count >= (step.Count or 1) then
					self:_beatDone()
				end
			end
		end
		return
	end

	if advance.Input == "Bail" then
		local steal = Shard.get("StealController")
		local state = if steal then (select(1, steal:getFlight())) else "idle"
		--[[ THE FREEZE HAS TO LIFT THE MOMENT THE JUMP TAKES, or the arc never plays: a flight is
			advanced off `dt * TimeScale.get()`, which a hold pins at zero. Watched by state rather
			than by keypress for the same reason it is watched at all — a key that the steal refused
			did not teach anything. ]]
		if state ~= "idle" then
			self._bailSeen = true
			self:_freeze(false)
			self:_beatDone()
		end
		return
	end
end

--[[ Should this frozen beat be holding the world RIGHT NOW? Asked every frame, because for one of
	the three the answer changes twice inside the beat.

	    "Arrival"   the default. Once the grace is served, hold — and keep holding until something
	                releases it. BOOST and BAIL, both of which are waiting on a key.
	    "Airborne"  hold at the moment the arc has got as close to a car as it is ever going to,
	                which is the moment E is worth pressing. AIRBORNE.

	=== THE AIRBORNE CASE WAITS FOR THE CLOSEST APPROACH, NOT FOR THE FIRST FRAME E WORKS =========

	It used to hold on the first frame `canMount` went true, and that is a different moment: E starts
	working the instant the flight is inside `StealController._reach` of something, which on the way
	down is while the player is still a good way above and behind it. Holding there froze the shot
	early — the player hangs in the sky beside the car rather than over it — and it made the lunge do
	all the remaining work, since the dive starts from wherever the press caught them.

	So the distance is watched instead. It falls while the arc closes and rises once it does not, and
	the frame it turns is the frame this holds. That is both the best shot the jump had in it and the
	shortest dive, and it is what lets the tutorial reach further without the steal turning into a
	teleport — see `_reach`, which is the other half of the same change.

	IT LATCHES, and it has to. A hold stops the flight dead, so the distance stops changing with it:
	tested afresh every frame, "has it started rising" would be false again on the very next one and
	the freeze would strobe. `_airHold` is the memory of the decision; `_armBeat` clears both.

	A PERCH LATCHES ON ARRIVAL rather than on a minimum it will never produce. Coming down ON the car
	pins the distance at zero and it never rises again, so a pure minimum-watcher would sit there and
	let `Prompt.Grace` run out into a whiff — with the world still running, which is precisely the
	beat this freeze exists to prevent.

	THE HOLD STILL RELEASES ITSELF, and that is the other load-bearing half. Pressing E moves the
	flight to "mount", which is a lunge advanced off `dt * TimeScale.get()` — so a hold that stayed
	on through the press would freeze the player at the top of the arc forever, having done exactly
	what the card asked. Reading the state every frame means the press that starts the lunge is also
	the thing that lets the world go. The same read covers a whiff, which drops back to "idle".

	Placed here rather than at the beat's arrival, for every beat, so the entry fade, the camera
	settling and the engine starting all get to happen on real time. ]]
function TutorialController._watchFreeze(self, step)
	--- This beat has already been given its world back once (see `FREEZE_TIMEOUT`); it does not get
	--- to take it again. Checked before anything else, so no branch below can re-apply the hold.
	--- ...and the same for a beat whose own input already lifted it this race. See `_freezeSpent`.
	if self._freezeForfeit == step.Id or self._freezeSpent == step.Id then
		if self._frozen then
			self:_freeze(false)
		end
		return
	end

	--[[ A FLIGHT OUTRANKS EVERY HOLD, whatever beat placed it.

		A bail can be started from inside any frozen beat — the jump is bound for the whole race and
		nothing about BOOST's card takes it away — and a flight is advanced off `dt * TimeScale.get()`,
		which a hold pins at zero. So a bail made during the wrong beat used to stop dead in the air:
		`StealController` had already anchored all 83 parts of the car for the arc, the arc could
		never take another step, and no watcher on that beat was looking for a flight to release the
		world for. Seen in a playtest as a car welded to the road with the rider perched on its boot,
		on a beat whose card was still asking for the throttle.

		The BAIL beat lifts its own hold this way already (`_watchBeat`) and the AIRBORNE beat's
		branch below is written around the arc. This is the same rule stated once for the beats that
		were never expecting a flight at all: while one is up, nobody holds the world. ]]
	if step.FreezeWhen ~= "Airborne" then
		local steal = Shard.get("StealController")
		if steal and (select(1, steal:getFlight())) ~= "idle" then
			if self._frozen then
				self:_freeze(false)
			end
			return
		end
	end

	if step.FreezeWhen == "Airborne" then
		local steal = Shard.get("StealController")
		if not steal then
			return
		end
		local state, canMount, reach = steal:getFlight()
		local flying = state == "air" or state == "perch"

		if not flying then
			--- Off the arc entirely: the press has been made, or the arc whiffed. Either way the next
			--- flight this beat sees starts its own search for a minimum.
			self._airNear = nil
			self._airHold = false
		elseif not self._airHold and canMount then
			local near = self._airNear
			if state == "perch" then
				self._airHold = true
			elseif near == nil or reach <= near then
				self._airNear = reach
			elseif reach > near + AIR_TURN then
				self._airHold = true
			end
		end

		--- `canMount` as well as the latch, so a target recycled out from under a held player gives
		--- the world back rather than leaving them in a paused sky with nothing to take.
		local want = flying and canMount and self._airHold
		if want and not self._frozen then
			self:_freeze(true)
		elseif not want and self._frozen then
			self:_freeze(false)
		end
		return
	end

	if not self._frozen and self:_inRace() then
		self:_freeze(true)
	end
end

--[[ Report the live input beat as finished. The server checks the id against what it is serving and
	advances; the card changes when its answer comes back, so a report that did not land is visibly
	a report that did not land rather than a card that moved on without the sequence.

	ONCE. `_watching` is cleared first, so a beat cannot be reported twice by the frames between the
	report and the state that replaces it. ]]
function TutorialController._beatDone(self)
	local step = self._watching
	if not step then
		return
	end
	self._watching = nil
	self:_completeMeter()
	self:getRemoteEvent("TutorialBeat"):Fire(step.Id)
end

--- Is a race actually up? A freeze anchors the player's car, so a beat marked `Race` that somehow
--- arrives in the lobby must not place one.
function TutorialController._inRace(self): boolean
	local road = Shard.get("RoadController")
	return road ~= nil and road:getCar() ~= nil
end

-- === The beat ===============================================================

--[[ A state from the server. The only thing on this controller that decides anything, and what it
	decides is timing rather than progress.

	`completed` means a beat was just finished, so the DONE stamp plays over the card before the new
	objective is drawn. Its absence means this is a resume — a join, or a skip — and the card simply
	becomes what it is told. ]]
function TutorialController._onState(self, state)
	if type(state) ~= "table" then
		return
	end

	local index = TutorialConfig.indexOf(state.step)
	local step = if index then TutorialConfig.stepAt(index) else nil

	--[[ THE SAME BEAT AGAIN, WITH A BETTER ANSWER IN IT — a correction, not a transition.

		One beat is published before the thing it points at exists: COLLECT is entered off the
		run settling and the bay is not picked until the car is parked, a step later (see the
		`CarParked` binding in `TutorialService`). The server sends the beat again once it knows.

		Nothing about the sequence has changed, so nothing about the card may. A token bump here
		would cancel the DONE stamp still playing over the beat this one just finished — and the
		beat it is stamping is the one that has not landed yet, so there is nothing to redraw
		anyway. Take the bay and re-resolve the pointer; the paint that was already coming does
		the rest. ]]
	if step and state.step == self._lastStep and not state.completed then
		self._bay = tonumber(state.bay)
		if self._step == step then
			self:_repoint()
		end
		return
	end
	self._lastStep = state.step
	self._finishPending = nil
	self._finishing = false

	self._token += 1
	local token = self._token
	self._bay = tonumber(state.bay)
	--- A beat the server closed (AIRBORNE, BANK) shows its meter finished under the stamp, the same
	--- as one this client closed. A no-op when `_beatDone` already did it.
	if state.completed then
		GameplayFeedback.play("TutorialStep")
		self:_completeMeter()
	end

	--[[ EVERY HOLD COMES OFF FIRST, before anything is drawn and whatever the new state turns out
		to be. A beat is over the moment a different state arrives, and the two things this feature
		does to the game must not survive the beat that placed them by even one frame. ]]
	self:_freeze(false)
	self:_setGate(nil)
	self:_disarmBeat()

	--[[ Finished or skipped. The finish card holds for its own beat — over the DONE stamp when there
		was a card to stamp, on its own when there was not; a skip has no `completed` and takes the
		card straight down. ]]
	if not step then
		--[[ A last beat that already celebrated as it landed (`Celebrate`: AGAIN, since 2026-10-19)
			ends quietly. It is finished by entering a race, so the card has said its last word and
			the road is the send-off; a finish card here would wait out the whole run and pop up
			after it. ]]
		local last = state.completed and TutorialConfig.stepOf(state.completed)
		if state.finished and last and last.Celebrate then
			self._step = nil
			self._celebrate = nil
			self:_clearPointer()
			self:_hide()
			return
		end
		if state.completed and state.finished then
			-- 2026-10-12: Completion outlives its objective. Modal-close syncs after Decline must
			-- still allow this card once finish() clears _step, until its own hold ends.
			self._finishing = true
			--[[ The last word. `_step` is dropped as it goes UP rather than when it comes down: the
				sequence is over, and a live beat under this card is one that can still repoint at
				the objective behind it and write that objective's hint over this one. ]]
			local function finish()
				if self._token ~= token then
					return
				end
				self._step = nil
				self:_clearPointer()
				self:_paintFinish()
				--- "Keep stealing cars", and Play starts calling for the press that does it.
				Dispatcher:Publish(RaceConfig.PlayBeckon.Event)
				task.delay(TutorialConfig.Timing.FinishHold, function()
					if self._token == token then
						self._finishing = false
						self:_hide()
					end
				end)
			end

			--[[ STAMPED ONLY IF THERE IS A CARD TO STAMP ON, and SHOWN either way — which is the
				whole of this branch and was the bug in it. The beat before this one is COLLECT, and
				collect is pointer only (`Card = false`), so `_canStamp` is false every single time
				the tutorial is finished the way a player finishes it. Gating the finish card on the
				stamp therefore did not merely skip the DONE beat; it skipped the game's last word
				entirely, on the one path that always reaches it.

				With no panel up there is nothing for DONE to be written over in any case — the
				objective that just closed was an arrow on a mat — so the card simply arrives saying
				what it has to say. ]]
			local function land()
				self._finishPending = nil
				if self._token ~= token then
					return
				end
				if self:_canStamp() then
					self:_stamp(finish)
				else
					self:_show()
					finish()
				end
			end

			--[[ NOT WHILE SOMETHING ELSE OWNS THE SCREEN (2026-10-06). The last beat is answered ON the
				buyer's offer screen, which is a modal, so the state saying "finished" lands while the
				card is stood down. Drawn then, the finish card and its confetti played out behind the
				screen and its hold ran down unseen. It waits for `_sync` to let the card back instead,
				`_step` still the beat that just closed, which is what keeps `_allowed` answering. ]]
			if self:_allowed() then
				land()
			else
				self._finishPending = land
			end
			return
		end
		self._step = nil
		self:_hide()
		return
	end

	local function land()
		if self._token ~= token then
			return
		end
		self._step = step
		--- A `Celebrate` beat reached by finishing the one before it plays the confetti the first time
		--- its card is actually on screen (`_sync`), which is after the offer screen has gone.
		self._celebrate = if step.Celebrate and state.completed then token else nil
		self:_armBeat(step)
		self:_paint(step)
		self:_sync()
		self:_repoint()
		self:_applyGate()
	end

	if state.completed and self:_canStamp() then
		self:_stamp(land)
		return
	end

	--[[ A beat with nothing before it waits `Settle` before appearing: on a join the welcome-back
		panel owns the first moment, and an objective sliding in under one is an objective nobody
		reads. The card is not shown by this — `_sync` decides that — so the delay costs nothing when
		the screen is already quiet. ]]
	task.delay(TutorialConfig.Timing.Settle, land)
end

--[[ Is there a card on screen for DONE to be stamped over?

	It is not enough that the tutorial is up. A pointer-only beat has the gui enabled, the arrow
	bouncing and no panel at all (see `_setCardShown`), and stamping into that would hold the next
	objective back by `DoneHold` for a word nobody can see — which on the PLAY beat is most of a
	second of the arrow sitting on a button the player has already pressed.

	So the stamp is skipped and the next beat lands immediately. Nothing is lost: the beat that just
	finished was one whose completion is self-evident, because the thing it asked for was the press
	that changed the screen. ]]
function TutorialController._canStamp(self): boolean
	return self._open == true and self._cardOn == true
end

--- Put the lobby gate on if the live beat asks for one and there is something to point at. Re-run
--- on every repoint, because the thing to gate TO changes as the player walks through the three
--- screens the PLAY beat spans.
function TutorialController._applyGate(self)
	local step = self._step
	local face = if step then self:_face(step) else nil
	if face and face.Gate == "Input" and self._open and self._aimBox then
		self:_setGate(self._aimBox)
	else
		self:_setGate(nil)
	end
end

-- === Race beats =============================================================

--[[ The card stands down for the length of every transition and comes back when the player has
	something to do again. `_suppressed` is one flag rather than a state machine because every one
	of these is the same question — is somebody else running the screen right now. ]]
function TutorialController._setSuppressed(self, suppressed: boolean)
	if suppressed then
		-- Anything waiting to un-suppress is stale the moment something re-suppresses.
		self._returnToken += 1
		--- ...and a suppressed card cannot explain a stopped world, so the hold comes off with it.
		self:_freeze(false)
	end
	self._suppressed = suppressed
	self:_sync()
	--- The card coming back after a transition is one of the three moments the FACE can have changed
	--- under a beat that did not — see `_refresh`.
	if not suppressed then
		self:_refresh()
	end
end

--[[ Bring the card back in `after` seconds, unless something re-suppresses first.

	FENCED ON `_returnToken`, which `_setSuppressed(true)` bumps: a run that STARTS inside the wait —
	a player who presses Play the moment they are home — must not have its entry fade un-suppressed
	by the tail of the previous run's trip back. ]]
function TutorialController._unsuppressIn(self, after: number)
	self._returnToken += 1
	local token = self._returnToken
	task.delay(after, function()
		if self._returnToken == token then
			self:_setSuppressed(false)
		end
	end)
end

--[[ The run is live. Drop the suppression and restart the beat's own clock.

	THE CLOCK RESTARTS HERE and not when the beat arrived, which matters for exactly one beat: BOOST
	is served the moment `RaceEntered` fires on the server, which is several seconds and a fade
	before the player can see anything. Its grace is measured from the road going live, or the
	freeze would land during the fade and the first thing a new player would see is a stopped
	world. ]]
function TutorialController._onRaceLive(self)
	self:_setSuppressed(false)
	self._beatTime = 0
	self._holdTime = 0
	self:_resetMeters()
	--- A new road starts the car from a standstill, so the first press is what gets it going again.
	self._freezeSpent = nil
	if self._watching then
		self:_ensureLoop()
	end
	--- There is a road now, so a race beat stops wearing its lobby face.
	self:_refresh()
end

--- A run is over, however it ended. Everything this feature was holding comes off; the beat itself
--- stays where it is, because the server has not said otherwise.
function TutorialController._onRunOver(self)
	self:_freeze(false)
	self._beatTime = 0
	self._holdTime = 0
	self:_resetMeters()
	--- ...and there is no road now. The card is suppressed for the trip home either way, so this is
	--- about what it says when it comes back — see `_setSuppressed`, which refreshes again.
	self:_refresh()
end

TutorialController:withRemoteEvents({
	{
		TutorialState = function(state)
			TutorialController:_onState(state)
		end,

		-- The entry fade is coming up over everything; nothing may sit on top of it.
		RaceEntering = function()
			TutorialController:_setSuppressed(true)
		end,
		RaceLive = function()
			TutorialController:_onRaceLive()
		end,
		-- The wreck screen owns this moment, and it is a modal — but the smoke and the coast before
		-- it are not, so this is taken explicitly rather than left to the modal flag.
		RaceWrecked = function()
			TutorialController:_onRunOver()
			TutorialController:_setSuppressed(true)
		end,
		RaceRevived = function()
			TutorialController:_onRaceLive()
		end,
		--[[ The trip home: results screen, then a fade, then the lobby. What lifts the suppression
			is the LANDING (`RaceConfig.ReturnedEvent`, subscribed in `_boot`) and this only books the
			fence behind it — see `TutorialConfig.Timing.ReturnFallback`, and the note above it for
			why the wait stopped being a blind number. ]]
		RaceEnd = function()
			TutorialController:_onRunOver()
			TutorialController:_setSuppressed(true)
			TutorialController:_unsuppressIn(TutorialConfig.Timing.ReturnFallback)
		end,
	},
	--- Declared but no longer fired from here: the card's SKIP word went with its title bar. The
	--- server end (`TutorialService`) is untouched, so a future dismiss has a wire waiting for it.
	"TutorialSkip",
	"TutorialReady",
	"TutorialBeat",
	--- A `Watched` beat's card is up with nothing over it. See `_stepWatched`.
	"TutorialWatching",
})

TutorialController:withLifecycle({
	init = function(self)
		self._open = false
		self._suppressed = false
		self._token = 0
		self._returnToken = 0
		--- The beat id of the last state that arrived, so a re-publish of the SAME beat is read as
		--- a correction rather than as a transition. See `_onState`.
		self._lastStep = nil
		--- The pointer's own fence, so a world target waiting to stream in retries at most once per
		--- resolve. See `_retryPoint`.
		self._pointToken = 0
		--- The live target when it is one whose answer can move between objects, and when it was
		--- last asked. Nil on everything else. See `_repoint` and `FOLLOW_INTERVAL`.
		self._follow = nil
		self._followAt = 0
		--- The DONE stamp's own fence. See `_stamp` for why it cannot share `_token`.
		self._stampToken = 0
		--- ...and the freeze's, which fences only its timeout backstop.
		self._freezeToken = 0
		self._step = nil
		self._frozen = false
		self._finishing = false
		--- The beat id, if any, whose freeze timed out and was given back for good. See
		--- `FREEZE_TIMEOUT` and `_watchFreeze`.
		self._freezeForfeit = nil
		--- The beat id whose own input lifted its freeze this race. See the Accelerate branch of `_watchBeat`.
		self._freezeSpent = nil
		--- Whether the live face draws a panel at all. True until a paint says otherwise, so a card
		--- built before the first state arrives is a card and not a ghost. See `_setCardShown`.
		self._cardOn = true
		--- Set only when the card is the kit's (the new UI, with its template in the place), and it
		--- holds the hint's size ceiling. See `_useKitCard`.
		self._kit = nil
		--- Which face the card is currently drawn with, so `_refresh` can tell a real change from a
		--- repaint and only punch on the first.
		self._drawnFace = nil
		--- The live input beat, or nil on a beat the server closes. See `_armBeat`.
		self._watching = nil
		self._count = 0
		self._beatTime = 0
		self._holdTime = 0
		self._steerSeen = {}
		--- SELL's latches and the camera turn's stop (`_stepWatched`, `_stepLook`), and the token of a
		--- `Celebrate` beat whose confetti is still to play (`_sync`).
		self._pinged = nil
		self._looked = nil
		self._lookStop = nil :: (() -> ())?
		--- The buyer's root the guide line is on, or nil. See `_stepGuide`.
		self._guided = nil :: BasePart?
		self._celebrate = nil :: number?
	end,

	start = function(self)
		--- Off by config, or bypassed by the Workspace flag a developer ticked. Either way there is
		--- no card, no arrow, no freeze and no gate, until the flag is lifted mid-session (the admin
		--- panel's Replay does that). See `TutorialConfig.whenOn`.
		TutorialConfig.whenOn(function()
			self:_boot()
		end)
	end,
})

--[[ Build the card, watch what moves it, and tell the server it can talk. Once, off
	`TutorialConfig.whenOn`: at start on an ordinary boot, or later when a bypassed session has the
	bypass lifted. The ping is last, so a state the server parked for this player is only sent once
	there is a card to draw it on. ]]
function TutorialController._boot(self)
	if self._booted then
		return
	end
	self._booted = true

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	--- Whichever UI is in play (`Modules/UIRoot`). Every path the beats declare is relative to
	--- `HUD` or to a page by name, and both UIs use the same names, so the targets travel.
	self._mainUI = UIRoot.wait(playerGui, 10)
	if not self._mainUI then
		--[[ A warning rather than a return: the card is this feature and it works without a HUD
			to point at. Only the arrow is lost, and a missing target is never a missing beat. ]]
		self.log:warn("No MainUI in this place; the tutorial's arrow has nothing to point at.")
	end

	--[[ BUILT BEFORE THE PING, NOT WHEN THE STATE ARRIVES. The ping is a promise that a remote
		sent now will be heard, and the card has to exist for that to be true — `_build` yields
		on PlayerGui, so a card assembled inside the remote handler would be assembled after the
		remote it was for. ]]
	self:_build()

	--[[ A page opening or closing moves the arrow (the WORLDS card), and the modal flag can take
		the whole card down. Both are watched rather than polled — and the repoint carries the
		gate with it, because which button is the only one that works changes with the page. ]]
	local pages = self._mainUI and self._mainUI:FindFirstChild("Pages")
	if pages then
		for _, page in pages:GetChildren() do
			if page:IsA("GuiObject") then
				page:GetPropertyChangedSignal("Visible"):Connect(function()
					if self._open then
						self:_repoint()
						self:_applyGate()
					end
				end)
			end
		end
	end
	playerGui:GetAttributeChangedSignal(GamepadConfig.ModalAttribute):Connect(function()
		self:_sync()
	end)

	--[[ THE WAY HOME HAS LANDED: the results screen has finished lifting and the player is stood on
		their own island with nothing over them (`RaceConfig.ReturnedEvent`). This is what brings the
		card back after a run, and `RaceEnd`'s own delay is only the fence behind it.

		THE SAME EVENT `CarryController` WAITS ON, deliberately. Both of them are announcing the same
		car to the same player in the same moment, and a card that keyed off some other clock would
		be the two of them racing. `ReturnSettle` is the beat between them, so the carry notice names
		the prize and this one then says what to do with it. ]]
	Dispatcher:Subscribe(RaceConfig.ReturnedEvent, function()
		self:_unsuppressIn(TutorialConfig.Timing.ReturnSettle)
	end)

	--[[ A rotated phone, a resized window, a device-safe-area change. The per-frame loop covers
		this while something is being pointed at; this covers the card standing on its own. ]]
	self._root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if self._open then
			self:_place(self._placeBox)
			if self._aimBox then
				self:_aimArrow(self._aimBox)
			end
		end
	end)

	self:getRemoteEvent("TutorialReady"):Fire()
end

--- Everything this feature holds over the game, dropped. A hot reload must not leave a world frozen
--- or a lobby with one working button.
TutorialController:withCleanup(function()
	TutorialController:_freeze(false)
	TutorialController:_setGate(nil)
	TutorialController:_disarmBeat()
	TutorialController:_stopLook()
	TutorialController:_pointGuide(nil)
end)

return TutorialController
