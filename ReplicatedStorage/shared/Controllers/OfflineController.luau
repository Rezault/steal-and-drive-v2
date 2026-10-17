--[[
	OfflineController  (client)
	---------------------------
	The WELCOME BACK screen. How long you were gone, what your lot is holding, and one button that
	takes it.

	IT IS BUILT IN CODE OUT OF THE KIT'S OWN ART, which is a third thing from the two ways this
	project draws UI and worth saying why. The pages under `UIController` are authored in the place
	because the artist drew them; `ReviveController` is code and plain shapes because the artist drew
	no wreck screen. Neither mockup has a welcome-back panel either — but this one is a PANEL, and
	the kit's panel, title cap, close button and pill are all uploaded, sliced and documented in
	`UIAssets`. So it is assembled from those rather than drawn from scratch: nothing new was
	uploaded for this screen and nothing about it is a colour somebody eyeballed.

	It is deliberately NOT a `UIController` page. Every one of those is opened by a tagged button
	with a `Page` attribute — that is the whole architecture, and this screen has no button, opens
	itself once per session and closes for good. Making it a page would mean inventing the one page
	nothing can ever open.

	=== THE THREE ANSWERS ======================================================================

	COLLECT sweeps the lot (server side: `GarageService.collectAll`, the same payout a foot on a mat
	runs). COLLECT 2x does the same sweep and multiplies it, for Robux — or for free, if the player
	is holding a boost they bought on a session that ended before it could be spent. The X — and B on
	a controller — dismisses without collecting, and that costs the player NOTHING: the money is not
	on this screen, it is standing on the bays, and closing this leaves it exactly where it was for
	the mats to pay out one at a time. That is the whole reason it is safe for this to be a modal
	with a close button rather than a wall.

	THE BOOST BUTTON IS DRAWN FROM THE OFFER, NEVER FROM THIS FILE'S OPINION. Whether it exists at all
	(`canBoost` — off in config, or rbxsync never run), what it multiplies by, what it costs and how
	many are already owned all arrive on the offer, and the caption is assembled from them. So a
	price change is a config edit and a screen that cannot sell anything simply draws one button.

	=== WHAT IT WAITS FOR ======================================================================

	The screen counts to the number the SERVER CONFIRMS, not to the one it was offered. The offer is
	drawn on arrival and the press does not close anything; `OfflineCollected` comes back with what
	`collectAll` actually paid — the same figure plus however long the player spent reading — and the
	label snaps to that before the panel drops. So the number that flies away and the number the cash
	pill rolls up to are the same number, which they would not be if this closed optimistically.

	=== WHAT LOCKS, AND FOR HOW LONG ===========================================================

	Both collect buttons lock on press, because between a press and an answer a live-looking button
	is a live button. They unlock differently and that difference is the whole of the purchase story:
	a plain claim is answered in a round trip, so it auto-closes after `CLAIM_TIMEOUT` if it is not;
	a boost press opens ROBLOX'S OWN PURCHASE MODAL, which the player can sit in for as long as they
	like, so it must not close under them. It waits for the server instead — `OfflineCollected` if
	the boost was applied, `OfflineBoostState` if it was banked or the prompt was cancelled — with
	`BOOST_TIMEOUT` as the backstop for an answer that never arrives. That backstop UNLOCKS rather
	than closes: nothing has been collected, so the screen is still worth having.

	=== WITH THE NEW UI, THE PANEL IS AUTHORED (2026-09-16) ====================================

	With `UIRoot.isNewUI()` the panel is not built here at all. `BuildWelcomeBackV2` authors it out of
	the Cartoony Kit's `PromptUI` onto the hidden shelf `MainUIV2.Screens.WelcomeBack`, and `_buildKit`
	clones that template into this file's own ScreenGui. The ScreenGui stays, with the same name,
	`DisplayOrder`, `ResetOnSpawn` and `ZIndexBehavior`, because 998 is its place in the ladder under
	the revive question and the race fade, and a frame inside `MainUIV2` would sit on the HUD's layer.

	EVERYTHING ABOVE STILL HOLDS, because only the drawing branched. The offer, the lock, the count,
	both timeouts and the pad bindings are one code path; `_build`, the open and close animation,
	the foot's colour and the button layout each have a kit half, and each branch is on `self._kit`.
	With the flag off `_build` runs exactly as it did.

	THE INSET IS IGNORED ON BOTH PATHS, on purpose. The kit is authored in `MainUIV2`'s space, which
	leaves the topbar out; this ScreenGui keeps `IgnoreGuiInset = true` so the dim still covers the
	topbar strip, and the panel therefore centres on the whole screen and sizes against its whole
	height. That makes it a few percent larger than the same frame would be inside `MainUIV2` (about
	5% at 1080p), and it is the right trade for a modal: the dim is the screen, and the panel sits in
	the middle of it.

	If the template is missing, the old panel is built instead and a warning says which command to run.
	A player with money on the bays still gets a screen.

	HOUSE RULE: no wiki-style double-bracket links in these comments — the closing pair ends the
	block comment early and the parse error points at the wrong line.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local GamepadConfig = require(ReplicatedStorage.shared.Configs.GamepadConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local OfflineConfig = require(ReplicatedStorage.shared.Configs.OfflineConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local GamepadInput = require(ReplicatedStorage.shared.Modules.GamepadInput)
local LivePrice = require(ReplicatedStorage.shared.Modules.LivePrice)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)

local OfflineController = Shard.new("OfflineController")

-- === Look & feel ============================================================
--[[ Everything here is a fraction — of the screen for the panel, of the PANEL for everything inside
	it — so the layout is one object that scales rather than a set of positions that agree at 1080p.
	`RaceUIController` and `ReviveController` are written the same way and for the same reason.

	The art is `UIAssets`. Which pieces and why:

	  • `Page.Panel` + `Page.TitleBar.Green` — the landscape page chassis out of `car ui (2).psd`,
	    the same panel the Index, Quest and Market screens are drawn on. GREEN of the three caps
	    because this screen is a payout and green is what the kit pays out in (the results screen's
	    getaway line is the same green). It is Market's colour in the rail, which is a real cost and
	    a small one: Market is a rail page you go to, this is a modal that arrives once a session,
	    and the two are never on screen together.
	  • `Page.Close` — the kit's X, with the hover the project derived from the artist's own face.
	  • `Pill.Green` — the one pill shape in the kit's green, for COLLECT. Its press is GEOMETRIC
	    rather than a colour (the face drops 6px in the art itself), so all three states are wired
	    straight to Image/HoverImage/PressedImage and nothing here fakes a press.
	  • `Pill.Orange` — the SAME shape for the boost, and the colour is the only decision in it.
	    Green is already spoken for by the button next to it, blue is `ReviveController`'s and the kit's
	    "primary action" everywhere else, and red is the tutorial pointer and the wreck. Orange is
	    warm against a green neighbour on a navy panel, which is what makes the pair readable at a
	    glance rather than as two pills of similar weight — and it is the kit's own, run through the
	    same hover transform as the other six, so it is not a colour anybody eyeballed either. ]]

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)
local WHITE = Color3.fromRGB(255, 255, 255)
-- The kit's payout green, the same one `RaceUIController` pays a getaway out in.
local CASH_GREEN = Color3.fromRGB(126, 217, 87)
-- ...and its amber, which that file uses for a wreck. Here it is the "you hit the ceiling" line —
-- not a failure, but the one line on this screen that is telling the player something cost them.
local WARN_AMBER = Color3.fromRGB(240, 178, 74)

local SCRIM_COLOR = Color3.fromRGB(6, 8, 12)
local SCRIM_REST = 0.45

--[[ How far each answer swells under a cursor, read by `UIController/Components/Button` off the
	`Scale` attribute the tag looks for. Both are UNDER the 1.05 default and for the reason that note
	gives: the art already reacts on its own — the pill's face drops 6px in the image and the X swaps
	texture — so the nudge is the second half of a reaction, not the whole of it. Same two numbers the
	respawn screen uses, because they are the same two shapes. ]]
local COLLECT_HOVER_SCALE = 1.03
local CLOSE_HOVER_SCALE = 1.08

local RAISE_TIME = 0.30
local DROP_TIME = 0.20
--- How long the number takes to count up to itself. Long enough to watch, short enough that the
--- COLLECT button is never something you are waiting for permission to press.
local COUNT_TIME = 0.7
--- ...and how long the confirmed figure stands before the panel drops, so the press has a result.
local CONFIRM_HOLD = 0.35
--[[ ...times this, when a boost landed. The number grows and counts up to itself a second time
	(see `_onCollected`), so the beat it needs is longer. It is a MULTIPLE of the ordinary hold
	rather than its own number, because the two are the same beat and should stay tied if either is
	retuned. ]]
local BOOST_HOLD_FACTOR = 3.0
--[[ The screen closes on its own this long after a press even if the server never answers. A claim
	that got lost must not leave a locked panel across the middle of the game; the money is still on
	the bays, so the worst case of closing early is a walk to the mats. ]]
local CLAIM_TIMEOUT = 2.5

--[[ The boost press has no such deadline, because the thing it is waiting on is a player reading
	Roblox's purchase modal. This is the backstop for a server that never answers at all, and it
	UNLOCKS rather than closing — nothing was collected, so the screen is still worth having. Two
	minutes is long enough that no real purchase can outlive it and short enough that a truly lost
	answer does not strand the button for the session. ]]
local BOOST_TIMEOUT = 120

--[[ The panel, as a box the aspect constraint FITS INSIDE. Both numbers are maximums, not the size
	— on a 16:9 monitor the height wins and the panel lands about 41% of the width; on a phone in
	portrait the width wins and it lands about 25% of the height. That is the whole reason it is a
	fit rather than a scale: one set of numbers that is sensible on both.

	A REAL BOX ON BOTH AXES, never a zero. `UIAspectRatioConstraint` defaults to FitWithinMaxSize,
	which collapses a zero-width element to 0x0 rather than solving for the aspect — a trap this
	project has already paid for once. ]]
local PANEL_BOX = UDim2.fromScale(0.86, 0.46)

--[[ Fractions of the PANEL, top to bottom. The title bar's two numbers are measured out of the PSD
	rather than chosen: the cap is 1788 x 138 against a 1798 x 1132 panel (see `UIAssets.PageBox`),
	so it is 99.4% of the width and 12.2% of the height and it sits flush at the top. ]]
local BAR_SIZE = UDim2.fromScale(0.994, 0.122)
local BAR_Y = 0.005

local CLOSE_BOX = UDim2.fromScale(0.09, 0.15) -- fitted square; see PANEL_BOX on why neither is 0
local CLOSE_POS = UDim2.fromScale(0.955, 0.066)

local AWAY_Y = 0.30
local AMOUNT_Y = 0.465
local FOOT_Y = 0.635
local BUTTON_Y = 0.815

--[[ The pill. Wide and low, at the art's own 463x119, and the caption is a TextLabel over it — the
	kit's rule is that text is never baked into an image, because the image cannot change and the
	word might.

	TWO SETS OF NUMBERS, because the row is one button or two depending on whether there is a boost to
	sell (see `_layoutButtons`). Both boxes are MAXIMUMS the aspect constraint fits inside, and in
	both the WIDTH is what wins — the height entry is only there to keep the box off zero, which
	`UIAspectRatioConstraint` collapses to nothing rather than solving for.

	The pair is 0.42 apiece with a 0.036 gutter, which leaves 0.062 of the panel clear on each side.
	That margin is not slack: the pad badges hang under the pills, and the outer one on each side is
	the only thing on this screen that can reach the panel's painted rim. ]]
local BUTTON_BOX = UDim2.fromScale(0.46, 0.19)
local PAIR_BOX = UDim2.fromScale(0.42, 0.19)
local PAIR_LEFT_X = 0.272
local PAIR_RIGHT_X = 0.728

--[[ The pad bindings. A collects, B closes — the same two answers `ReviveController` binds, and
	deliberately the same two buttons, because a player who has just learned that screen should not
	have to learn this one.

	NO SELECTION IS SEEDED, for that screen's reason exactly: there are two answers, neither moves,
	and driving a highlight onto one of them first is a step with nothing to gain. The screen raises
	`GamepadConfig.ModalAttribute` while it is up so the navigation component stands down — B is its
	back key the rest of the time, and both of them owning one button is the bug that attribute
	exists to prevent. ]]
local PAD_COLLECT = "OfflineCollect"
local PAD_BOOST = "OfflineBoost"
local PAD_CLOSE = "OfflineClose"
local PAD_PRIORITY = Enum.ContextActionPriority.High.Value + 600

--[[ Where a collect button's badge hangs: CENTRED UNDER IT, in the button's own scale space.

	Under rather than beside, which is what the single-button version of this screen did. Beside
	stops working the moment there are two pills: the pair plus its gutter leaves 6% of the panel on
	each flank and a badge is about 5% of it wide, so an outer badge would sit on the panel's painted
	rim — and an inner one would sit in the gutter between two buttons, next to neither. Under is the
	one placement that reads as belonging to the pill above it in both layouts.

	0.8 of the standard size for the same reason the close button's B is 0.72: these are labels on
	something that is already legible, not the thing being looked at. ]]
local PAD_BADGE_POS = UDim2.fromScale(0.5, 1.15)
local PAD_BADGE_ANCHOR = Vector2.new(0.5, 0)
local PAD_BADGE_SIZE = GamepadConfig.Icon.Size * 0.8

-- Non-breaking, because `TextScaled` would sooner break a caption onto a second line than pick a
-- smaller font. Every space in a one-line label on this screen is this one.
local NBSP = utf8.char(0xA0)

local function oneLine(text: string): string
	return (string.gsub(string.upper(text), "%s+", NBSP))
end

-- === The kit panel (new UI) =================================================
--[[ The authored panel's names and the few numbers that are about THIS screen rather than the art.
	Every name here is one `BuildWelcomeBackV2` writes, and its header says what each was cut from. ]]

local KIT_SHELF = "Screens"
local KIT_TEMPLATE = "WelcomeBack"
--- How long each step of the path to the template is waited for. Generous, because the ScreenGui is
--- a StarterGui clone that lands with the character, and nothing waits on this but the ping.
local KIT_WAIT = 10

--- The kit's Robux mark, U+E002, which the kit's own price buttons are written in. Shop V2 has the
--- note on why this renders.
local ROBUX = utf8.char(0xE002)

--[[ The panel opens and closes the way every V2 page does (`UIController.openPage`): a pop from 0.9
	on a `Back` ease and a quick drop back to 0.9. Same numbers, so a modal and a page arrive with the
	same gesture. The dim keeps this file's own fade. ]]
local KIT_START_SCALE = 0.9
local KIT_OPEN = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local KIT_CLOSE = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

--[[ Where the pad badges hang on the kit panel: ON THE BUTTON'S TOP LEFT CORNER, like a count on an
	icon, rather than under it as on the old panel. The kit's buttons sit about 10px above the white
	body's rim at 1080p, which is less than half a badge, so a badge under a button draws across the
	rim. Above the buttons is the gap the artist left before the body text, and a corner badge uses
	it. The B hangs off the X's lower left corner into the gap between the header and the body. ]]
local KIT_BADGE_POS = UDim2.fromScale(0, 0)
local KIT_BADGE_ANCHOR = Vector2.new(0.3, 0.3)
local KIT_CLOSE_BADGE_POS = UDim2.fromScale(0, 1)
local KIT_CLOSE_BADGE_ANCHOR = Vector2.new(0.35, 0.65)

-- === Building ===============================================================

--- 9-slice an ImageLabel/ImageButton from the recorded texture size and inset. Both come out of
--- `UIAssets`, which is measured against what Roblox STORED rather than against the PSD — see the
--- warning on `UIAssets.Size`.
local function slice(image: ImageLabel | ImageButton, size: Vector2, inset: number)
	image.ScaleType = Enum.ScaleType.Slice
	image.SliceCenter = Rect.new(inset, inset, size.X - inset, size.Y - inset)
end

--[[ One pill button and its caption. Both collect buttons are this shape and this state language,
	so the differences between them are three arguments and nothing else.

	STRETCHED, NOT SLICED — the aspect constraint pins this to the art's own 3.89:1, so the box only
	ever shrinks uniformly and `Stretch` reproduces the drawing exactly. Slicing it (which this did
	until 2026-08-16) pins the corner curve at texture pixels while the rest of the pill shrinks, and
	the button comes out a fat lozenge. `UIAssets.Slice.Pill` has the arithmetic.

	The caption sits ABOVE the pill's own bottom edge rather than centred in it, because the pressed
	art drops the face 6px and loses 6px of height: text centred in the box would stay put while the
	face moved out from under it. Padding is the cheapest way to keep the word inside the part of the
	pill that is drawn in both states. ]]
function OfflineController._pill(self, parent: GuiObject, name: string, colours, text: string): (ImageButton, TextLabel)
	local button = Instance.new("ImageButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, BUTTON_Y)
	button.Size = BUTTON_BOX
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false -- the art has its own three states; Roblox's tint fights them
	button.Image = UIAssets.url(colours.Idle)
	button.HoverImage = UIAssets.url(colours.Hover)
	button.PressedImage = UIAssets.url(colours.Pressed)
	button.ImageTransparency = 1
	button.ScaleType = Enum.ScaleType.Stretch
	button.Parent = parent

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = UIAssets.Size.Pill.X / UIAssets.Size.Pill.Y
	aspect.Parent = button

	local caption = Instance.new("TextLabel")
	caption.Name = "Label"
	caption.AnchorPoint = Vector2.new(0.5, 0.5)
	caption.Position = UDim2.fromScale(0.5, 0.46)
	--[[ WIDER THAN THE SINGLE-BUTTON VERSION WAS (0.7), because the boost caption is twice the
		length of "COLLECT" and `TextScaled` shrinks to fit the box it is given. It is still inside the
		pill's flat middle band on both ends, which is the constraint that matters. ]]
	caption.Size = UDim2.fromScale(0.82, 0.42)
	caption.BackgroundTransparency = 1
	caption.FontFace = FONT
	caption.Text = oneLine(text)
	caption.TextColor3 = WHITE
	caption.TextTransparency = 1
	caption.TextScaled = true
	caption.Parent = button

	return button, caption
end

function OfflineController._build(self)
	--- The new UI's panel, when there is one to clone. See the header: a missing template falls
	--- through to the panel below rather than leaving the player with no screen.
	if UIRoot.isNewUI() and self:_buildKit() then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "WelcomeBack"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	--[[ Under the respawn screen's 999 and the race fade's 1000. It cannot collide with either — this
		only ever opens on join, in the lobby — and ordering it below them costs nothing while making
		"a race beat always wins" true by construction rather than by timing. ]]
	gui.DisplayOrder = 998
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	--[[ `Active` is what makes this modal. A Frame does not swallow input by default, so without it
		the HUD's Play button is still clickable straight through the dim — and a player who pressed
		it would start a race with a welcome screen sitting over the road. ]]
	local scrim = Instance.new("Frame")
	scrim.Name = "Scrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = SCRIM_COLOR
	scrim.BackgroundTransparency = 1
	scrim.BorderSizePixel = 0
	scrim.Active = true
	scrim.Parent = gui

	local panel = Instance.new("ImageLabel")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = PANEL_BOX
	panel.BackgroundTransparency = 1
	panel.Image = UIAssets.url(UIAssets.Page.Panel)
	panel.ImageTransparency = 1
	slice(panel, UIAssets.Size.Panel, UIAssets.Slice.Panel)
	panel.Parent = scrim

	local panelAspect = Instance.new("UIAspectRatioConstraint")
	panelAspect.AspectRatio = UIAssets.Size.Panel.X / UIAssets.Size.Panel.Y
	panelAspect.Parent = panel

	local bar = Instance.new("ImageLabel")
	bar.Name = "TitleBar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.fromScale(0.5, BAR_Y)
	bar.Size = BAR_SIZE
	bar.BackgroundTransparency = 1
	bar.Image = UIAssets.url(UIAssets.Page.TitleBar.Green)
	bar.ImageTransparency = 1
	-- Stretch: the cap's alpha is a plain rectangle (measured, all four cap textures), so there is no
	-- corner for a slice to protect and all it did was hold the painted rim at 1:1 texture pixels.
	bar.ScaleType = Enum.ScaleType.Stretch
	bar.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.5)
	title.Size = UDim2.fromScale(0.7, 0.62)
	title.BackgroundTransparency = 1
	title.FontFace = FONT
	title.Text = oneLine(OfflineConfig.Title)
	title.TextColor3 = WHITE
	title.TextTransparency = 1
	title.TextScaled = true
	title.Parent = bar

	local close = Instance.new("ImageButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = CLOSE_POS
	close.Size = CLOSE_BOX
	close.BackgroundTransparency = 1
	close.AutoButtonColor = false -- the art has its own three states; Roblox's tint fights them
	close.Image = UIAssets.url(UIAssets.Page.Close.Idle)
	close.HoverImage = UIAssets.url(UIAssets.Page.Close.Hover)
	close.PressedImage = UIAssets.url(UIAssets.Page.Close.Pressed)
	close.ImageTransparency = 1
	close.Parent = panel

	local closeAspect = Instance.new("UIAspectRatioConstraint")
	closeAspect.AspectRatio = UIAssets.Size.Close.X / UIAssets.Size.Close.Y
	closeAspect.Parent = close

	--[[ How long they were gone. Above the number and dimmer than it, because it is the REASON there
		is a number rather than the number — the same relationship the results screen's distance line
		has to its payout. ]]
	local away = Instance.new("TextLabel")
	away.Name = "Away"
	away.AnchorPoint = Vector2.new(0.5, 0.5)
	away.Position = UDim2.fromScale(0.5, AWAY_Y)
	away.Size = UDim2.fromScale(0.7, 0.09)
	away.BackgroundTransparency = 1
	away.FontFace = FONT
	away.Text = ""
	away.TextColor3 = WHITE
	away.TextTransparency = 1
	away.TextScaled = true
	away.Parent = panel

	local amount = Instance.new("TextLabel")
	amount.Name = "Amount"
	amount.AnchorPoint = Vector2.new(0.5, 0.5)
	amount.Position = UDim2.fromScale(0.5, AMOUNT_Y)
	amount.Size = UDim2.fromScale(0.82, 0.19)
	amount.BackgroundTransparency = 1
	amount.FontFace = FONT
	amount.Text = ""
	amount.TextColor3 = CASH_GREEN
	amount.TextTransparency = 1
	amount.TextScaled = true
	amount.Parent = panel

	-- The punch when the count lands, and again when the server confirms. On a UIScale rather than on
	-- Size, so the layout above stays the one source of truth for where this sits.
	local amountScale = Instance.new("UIScale")
	amountScale.Parent = amount

	local foot = Instance.new("TextLabel")
	foot.Name = "Foot"
	foot.AnchorPoint = Vector2.new(0.5, 0.5)
	foot.Position = UDim2.fromScale(0.5, FOOT_Y)
	foot.Size = UDim2.fromScale(0.86, 0.075)
	foot.BackgroundTransparency = 1
	foot.FontFace = FONT
	foot.Text = ""
	foot.TextColor3 = WHITE
	foot.TextTransparency = 1
	foot.TextScaled = true
	foot.Parent = panel

	local button, caption = self:_pill(panel, "Collect", UIAssets.Pill.Green, OfflineConfig.CollectText)

	--[[ The boost, built unconditionally and SHOWN conditionally. `_layoutButtons` decides, off the
		offer's `canBoost`, and it decides once per screen — building it here rather than inside the
		offer handler keeps `_build` the one place that knows what this panel is made of, which is
		what lets `_show`/`_hide` fade a fixed list of instances. ]]
	local boost, boostCaption = self:_pill(panel, "Boost", UIAssets.Pill.Orange, "")
	boost.Visible = false

	self._gui = gui
	self._scrim = scrim
	self._panel = panel
	self._bar = bar
	self._title = title
	self._close = close
	self._away = away
	self._amount = amount
	self._amountScale = amountScale
	self._foot = foot
	self._button = button
	self._caption = caption
	self._boost = boost
	self._boostCaption = boostCaption
	-- The punch when a purchase lands and the button stops asking for Robux. Same instrument the
	-- number uses, one notch quieter — it is a confirmation, not the payout.
	self._boostScale = Instance.new("UIScale")
	self._boostScale.Parent = boost

	self:_wire()

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	--[[ === BOTH ANSWERS ARE `UIButton`s =======================================================

		The tag is how every pressable thing in this game is declared (`UIController/Components/Button`),
		and having it is what gives these two the hover swell, the hover sound and the click sound —
		including the sounds that are still silent, since the groups exist in SoundService with blank
		ids and start being audible the day the boss pastes ids in, with no change here.

		THE TAG BRINGS NO BEHAVIOUR WITH IT, deliberately: neither button carries a `Page` or an
		`Action` attribute, so a press through `ButtonPress` plays its click and does nothing else.
		What COLLECT and the X mean stays in this file, on the `Activated` wires in `_wire`, because
		both are answers to an offer that is still open — a state the UI layer knows nothing about.
		Same arrangement as the respawn screen, which is the other modal built this way.

		It also hands nothing to `Components/GamepadNav`: that only ever looks inside `MainUI`, and
		this is its own ScreenGui. `_bindPad` stays the whole of the controller story here.

		LAST, AND AFTER THE PARENTING. The component reads the button the moment the tag lands, so the
		tag goes on once everything it measures is final. ]]
	self._button:SetAttribute("Scale", COLLECT_HOVER_SCALE)
	self._boost:SetAttribute("Scale", COLLECT_HOVER_SCALE)
	self._close:SetAttribute("Scale", CLOSE_HOVER_SCALE)
	CollectionService:AddTag(self._button, "UIButton")
	CollectionService:AddTag(self._boost, "UIButton")
	CollectionService:AddTag(self._close, "UIButton")
end

--[[ The new UI's panel: the authored template, cloned into a ScreenGui of this file's own.

	RETURNS WHETHER IT BUILT. False means the template or one of its parts was not there, which has
	already been said out loud, and `_build` goes on to draw the old panel.

	THE FIELDS ARE THE OLD PANEL'S FIELDS, pointed at the kit's parts, so everything that reads them
	(the paint, the count, the locks, the pad) is one path. Where a field has no kit meaning it is
	still set: `_bar` is the header, and `_caption` is the COLLECT button's own `Title`.

	THE BUTTONS ARRIVE TAGGED. `PrepKitTemplate` tagged the kit and a tag survives a clone, so these
	are `UIButton`s the moment the ScreenGui is parented, which is the last line here, after `_wire`
	and after every part is in place: the same "after the parenting" order the old panel keeps by
	adding its tags by hand. They take the kit's default hover, like every other V2 button. ]]
function OfflineController._buildKit(self): boolean
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", KIT_WAIT)
	local root = playerGui and UIRoot.wait(playerGui :: PlayerGui, KIT_WAIT)
	local shelf = root and root:WaitForChild(KIT_SHELF, KIT_WAIT)
	local template = shelf and shelf:WaitForChild(KIT_TEMPLATE, KIT_WAIT)
	if not (template and template:IsA("GuiObject")) then
		warn(string.format("[OfflineController] No MainUIV2.%s.%s after %ds; drawing the old panel. Run BuildWelcomeBackV2.", KIT_SHELF, KIT_TEMPLATE, KIT_WAIT))
		return false
	end

	local panel = template:Clone() :: GuiObject
	--- The kit's text caps are pixels for a 1080-tall screen; this keeps them in proportion above it.
	require(script.Parent.UIController.KitPage).scaleTextCaps(panel)
	local header = panel:FindFirstChild("Header")
	local main = panel:FindFirstChild("Main")
	local btns = main and main:FindFirstChild("Btns")
	local title = header and header:FindFirstChild("Title")
	local close = header and header:FindFirstChild("CloseBtn")
	local away = main and main:FindFirstChild("Away")
	local amount = main and main:FindFirstChild("Amount")
	local foot = main and main:FindFirstChild("Foot")
	local footTint = foot and foot:FindFirstChild("Tint")
	local button = btns and btns:FindFirstChild("CollectBtn")
	local boost = btns and btns:FindFirstChild("BoostBtn")
	local caption = button and button:FindFirstChild("Title")
	local boostCaption = boost and boost:FindFirstChild("Title")
	if not (title and close and close:IsA("GuiButton") and away and amount and foot and footTint and footTint:IsA("UIGradient") and button and button:IsA("GuiButton") and boost and boost:IsA("GuiButton") and caption and boostCaption) then
		warn("[OfflineController] MainUIV2.Screens.WelcomeBack is missing a part; drawing the old panel. Re-run BuildWelcomeBackV2.")
		panel:Destroy()
		return false
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "WelcomeBack"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- see the header: the dim covers the topbar, and the panel centres on the screen
	gui.DisplayOrder = 998
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	--- `Active`, for the old panel's reason: without it the HUD's Play is clickable through the dim.
	local scrim = Instance.new("Frame")
	scrim.Name = "Scrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = SCRIM_COLOR
	scrim.BackgroundTransparency = 1
	scrim.BorderSizePixel = 0
	scrim.Active = true
	scrim.Parent = gui

	panel.Visible = false
	panel.Parent = scrim

	local popScale = Instance.new("UIScale")
	popScale.Name = "PopScale"
	popScale.Scale = KIT_START_SCALE
	popScale.Parent = panel

	title.Text = oneLine(OfflineConfig.Title)

	--[[ The number's punch, on a UIScale of the label's own as on the old panel. The boost's receipt
		punch goes on its CAPTION rather than on the button, because the button's one UIScale is the
		hover's (`Components/Button` names it `HoverScale` and stands down to a Size tween if something
		else got there first). ]]
	local amountScale = Instance.new("UIScale")
	amountScale.Parent = amount
	local boostScale = Instance.new("UIScale")
	boostScale.Parent = boostCaption

	self._kit = true
	self._gui = gui
	self._scrim = scrim
	self._panel = panel
	self._popScale = popScale
	self._bar = header
	self._title = title
	self._close = close
	self._away = away
	self._amount = amount
	self._amountScale = amountScale
	self._foot = foot
	self._footTint = footTint
	--- The foot's two colours are the ART's, read off the template (`BuildWelcomeBackV2`). A template
	--- somebody stripped them from draws a plain line rather than erroring.
	self._footWarn = foot:GetAttribute("WarnColor")
	self._footApplied = foot:GetAttribute("AppliedColor")
	self._button = button
	self._caption = caption
	self._boost = boost
	self._boostCaption = boostCaption
	self._boostScale = boostScale
	boost.Visible = false

	self:_wire()

	gui.Parent = playerGui
	return true
end

function OfflineController._wire(self)
	self._button.Activated:Connect(function()
		self:_pressCollect()
	end)
	self._boost.Activated:Connect(function()
		self:_pressBoost()
	end)
	self._close.Activated:Connect(function()
		self:_pressClose()
	end)
end

-- === The two answers ========================================================

--[[ COLLECT. Locks, asks, and waits to be told what it got.

	THE LOCK IS THE WHOLE OF IT, the same as the respawn screen's: between the press and the answer
	there are frames in which a button that still looks live is still live, and a second press is a
	second sweep of a lot that has nothing left in it — which would come back as $0 and repaint this
	screen with a zero. ]]
function OfflineController._pressCollect(self)
	if self._locked or not self._open then
		return
	end
	self._locked = true
	self:getRemoteEvent("OfflineClaim"):Fire()

	-- See CLAIM_TIMEOUT: a lost claim must not leave a locked panel in the middle of the game.
	local token = self._token
	task.delay(CLAIM_TIMEOUT, function()
		if self._open and self._locked and self._token == token then
			self:_hide()
		end
	end)
end

--[[ COLLECT 2x, and Y on a controller. One message, and the server decides what it means.

	IT DOES NOT KNOW WHETHER THIS IS A PURCHASE. The client's copy of the count is only ever what the
	button is DRAWN from — the server reads the profile to decide whether this spends a stored boost
	or opens Roblox's prompt, which is the same "trusted with the press and nothing else" split
	`ReviveController` makes. So a client that lies about owning one gets a purchase prompt.

	NO AUTO-CLOSE TIMER, unlike the plain claim, because what this can be waiting on is a player
	reading a purchase modal. See the header: the unlock comes from the server, and `BOOST_TIMEOUT`
	is the backstop for one that never speaks. ]]
function OfflineController._pressBoost(self)
	if self._locked or not self._open or not self._boost.Visible then
		return
	end
	self._locked = true
	self:getRemoteEvent("OfflineClaim"):Fire(true)

	local token = self._token
	task.delay(BOOST_TIMEOUT, function()
		if self._open and self._locked and self._token == token then
			self._locked = false
		end
	end)
end

--[[ The X, and B on a controller. Dismisses without collecting, and that is not a forfeit: the cash
	is on the bays, not on this screen, and every mat still pays it out one at a time. ]]
function OfflineController._pressClose(self)
	if self._locked or not self._open then
		return
	end
	self:_hide()
end

--[[ The server's answer: what `collectAll` actually paid, and whether a multiplier was applied to
	it. The label lands on THAT number rather than on the offered one — see the header — and the
	panel drops.

	THE MULTIPLIER IS THE SERVER'S WORD, NOT THE BUTTON'S. `_pressBoost` does not know whether the
	boost was spendable (an empty lot declines it, a profile that went inactive declines it), so this
	reads what actually happened rather than what was asked for. A screen that announced 2x over a
	1x payout would be the one lie on it.

	TWO DIFFERENT LANDINGS, and the difference is worth the branch:

	  1x   SNAP. The confirmed figure differs from the one on screen by however many seconds the
	       player spent reading, which is pennies — animating to it would draw the eye to a change
	       nobody should notice.
	  2x   COUNT AGAIN, from where the number already stands up to double it. That gap IS the
	       purchase, and it is the one moment on this screen worth watching happen. ]]
function OfflineController._onCollected(self, amount: unknown, multiplier: unknown)
	if not self._open then
		return
	end
	local paid = tonumber(amount) or 0
	local times = math.max(1, math.floor(tonumber(multiplier) or 1))
	local hold = CONFIRM_HOLD

	if paid > 0 and times > 1 then
		--[[ The count restarts from wherever it had got to rather than from the confirmed 1x figure,
			so a player who presses the boost while the first count is still running gets one continuous
			climb instead of a jump backwards and a second start. ]]
		self._countFrom = self._counted or 0
		self._target = paid
		self._countStart = os.clock()
		hold = CONFIRM_HOLD * BOOST_HOLD_FACTOR

		self:_setFoot(oneLine(string.format(OfflineConfig.BoostAppliedFormat, times)), "applied")
	elseif paid > 0 then
		--[[ `_counted` is moved with `_target`, not just the text. A player who presses COLLECT while
			the number is still counting up would otherwise leave the tick loop mid-run, and it would
			carry on writing the eased value straight over the confirmed one for the rest of its span —
			the screen would snap to the true figure and then walk back down to it. ]]
		self._countFrom = paid
		self._target = paid
		self._counted = paid
		self._amount.Text = GarageConfig.formatCash(paid)
		self:_pulse()
	end

	--[[ The screen stays LOCKED through the hold. It is on its way out either way, and a second press
		landing in the tail of a boosted count would fire a claim at a lot that has already been
		swept — which comes back as $0 and repaints this screen with a zero. ]]
	self._locked = true
	task.delay(hold, function()
		self:_hide()
	end)
end

--[[ A purchase landed but there was nothing to spend it on this instant, so it is banked — or a
	prompt closed without one. Either way the count is now authoritative and the button stops
	waiting.

	THIS IS WHAT MAKES A SLOW RECEIPT SURVIVABLE. Without it a purchase that the server could not
	apply on the spot would leave the panel locked with no answer coming; with it the button simply
	repaints as owned and the player presses it again, for free, and gets the same outcome. ]]
function OfflineController._onBoostState(self, boosts: unknown)
	-- The screen is built in `start`, before the ping that can bring any of this back — but a config
	-- that switched the feature off skips `_build` entirely, and this must be inert then rather than
	-- indexing a panel that was never made.
	if not self._boostCaption then
		return
	end
	local count = math.max(0, math.floor(tonumber(boosts) or 0))
	local gained = count > (self._boosts or 0)
	self._boosts = count
	self._locked = false
	self:_paintBoost()
	if gained and self._open and self._boost.Visible then
		self:_pulseBoost()
	end
end

-- === Drawing ================================================================

--[[ Draw one offer. Everything is written unconditionally rather than assumed to be at rest,
	because this screen is rebuilt exactly once per session and a field left over from a previous
	one would be invisible until the day something opened it twice. ]]
function OfflineController._paint(self, offer)
	local amount = math.max(0, tonumber(offer.amount) or 0)
	local bays = math.max(0, math.floor(tonumber(offer.bays) or 0))

	self._target = amount
	self._countFrom = 0
	self._counted = 0
	self._countStart = os.clock()
	self._amount.Text = GarageConfig.formatCash(0)

	--[[ Everything the boost button draws itself from, latched here rather than read out of the offer
		later: `_paintBoost` is called again when a purchase lands, at which point the offer is a
		stale table and only the count has moved. ]]
	self._multiplier = math.max(1, math.floor(tonumber(offer.multiplier) or OfflineConfig.Boost.Multiplier))
	self._price = math.max(0, math.floor(tonumber(offer.price) or OfflineConfig.Boost.Price))
	self._boosts = math.max(0, math.floor(tonumber(offer.boosts) or 0))
	self:_layoutButtons(offer.canBoost == true)
	self:_paintBoost()

	self._away.Text = oneLine(string.format(OfflineConfig.AwayFormat, OfflineConfig.formatAway(offer.away)))

	--[[ THE CAP LINE WINS WHEN THERE IS ONE, and that is the one editorial decision on this screen.
		A player who was away nine hours with a two-hour ceiling earned nothing for seven of them, and
		a footnote counting bays instead of saying so would be the screen quietly declining to mention
		the only thing on it that cost them money. It names STORAGE because that is the upgrade that
		fixes it, and this is the exact moment its absence is being felt. ]]
	--[[ Two vocabularies for the same two lines, picked by the income mode: with passive income the
		offer is what the BAYS held and `bays` counts them; without it (2026-09-28) the offer is what
		customers tipped and the server sends the VISITOR count in that same field. See
		`OfflineConfig.VisitorsFormat` for why the words had to change with it. ]]
	local passive = GarageConfig.Income.Passive
	if offer.capped then
		local format = if passive then OfflineConfig.CappedFormat else OfflineConfig.ShowroomClosedFormat
		self:_setFoot(oneLine(string.format(format, OfflineConfig.formatAway(offer.cap))), "warn")
	elseif passive then
		self:_setFoot(oneLine(if bays == 1 then OfflineConfig.OneBayText else string.format(OfflineConfig.BaysFormat, bays)), "plain")
	else
		local line = if bays == 1 then OfflineConfig.OneVisitorText else string.format(OfflineConfig.VisitorsFormat, bays)
		local buyers = math.max(0, math.floor(tonumber(offer.buyers) or 0))
		if buyers > 0 then
			line ..= if buyers == 1 then OfflineConfig.OneBuyerSuffix else string.format(OfflineConfig.BuyersSuffixFormat, buyers)
		end
		self:_setFoot(oneLine(line), "plain")
	end
end

--[[ The foot line and its tone: `plain` (the bays), `warn` (the cap) or `applied` (2x APPLIED).

	ONE WRITER, TWO WAYS OF COLOURING. The old panel sets the text colour; the kit's type is white
	under a gradient (the kit colours money that way, the cash counter included), so the kit panel
	switches the foot's `Tint` gradient on in the template's own warn or applied colours, and off for
	plain. The text is written first either way, so a tone can never be left on the previous line. ]]
function OfflineController._setFoot(self, text: string, tone: string)
	self._foot.Text = text
	if self._kit then
		local colour = if tone == "warn" then self._footWarn elseif tone == "applied" then self._footApplied else nil
		self._footTint.Enabled = typeof(colour) == "ColorSequence"
		if typeof(colour) == "ColorSequence" then
			self._footTint.Color = colour
		end
		return
	end
	self._foot.TextColor3 = if tone == "warn" then WARN_AMBER elseif tone == "applied" then CASH_GREEN else WHITE
end

--[[ One button or two. Called once per screen, from `_paint`.

	COLLECT MOVES; the boost is the one that appears. A screen that cannot sell anything has to look
	like it was always going to be one button — which means the survivor sits dead centre at the
	art's full width, not off to one side with a hole beside it. ]]
function OfflineController._layoutButtons(self, canBoost: boolean)
	self._boost.Visible = canBoost

	--- The kit's buttons sit in a centred `UIListLayout`, so hiding the boost is the whole layout: the
	--- survivor centres at the artist's width.
	if self._kit then
		return
	end

	if canBoost then
		self._button.Size = PAIR_BOX
		self._button.Position = UDim2.fromScale(PAIR_LEFT_X, BUTTON_Y)
		self._boost.Size = PAIR_BOX
		self._boost.Position = UDim2.fromScale(PAIR_RIGHT_X, BUTTON_Y)
	else
		self._button.Size = BUTTON_BOX
		self._button.Position = UDim2.fromScale(0.5, BUTTON_Y)
	end
end

--[[ What the boost button says. The only part of this screen that changes without a new offer.

	TWO STATES, AND THE FREE ONE COMES FIRST — the same split `ReviveController._caption` makes, for
	the same reason. A player holding a boost they bought on a session that ended before it could be
	spent is not being sold anything, so the button must not show a price it is not going to charge.
	That case is rare and it is exactly the case where getting it wrong looks like a double charge.

	The count is only printed above one. "(1)" next to a button that is already free is a number
	doing no work; "(3)" is telling the player something they had forgotten.

	The price is written `R$49` rather than as a Robux glyph because there is no Robux glyph in this
	kit — `ReviveController` has the long version. ]]
function OfflineController._paintBoost(self)
	local multiplier = self._multiplier or OfflineConfig.Boost.Multiplier
	local owned = self._boosts or 0
	--- What Roblox says this player pays (`Modules/LivePrice`); the offer's config figure until it answers.
	local price = LivePrice.peek(OfflineConfig.Boost.ProductId) or self._price or OfflineConfig.Boost.Price

	if owned > 1 then
		self._boostCaption.Text = oneLine(string.format(OfflineConfig.BoostOwnedFormat, multiplier, owned))
	elseif owned == 1 then
		self._boostCaption.Text = oneLine(string.format(OfflineConfig.BoostOwnedText, multiplier))
	elseif self._kit then
		--[[ The kit writes a price as its own Robux mark and the number, which is what every purchase
			button in the pack says and what Shop V2 prints. So the caption is the owned words plus the
			mark, rather than `BoostBuyFormat`'s `R$`, which was the old kit standing in for a glyph it
			did not have. Joined with non-breaking spaces, after `oneLine`, so nothing upper-cases the mark. ]]
		self._boostCaption.Text = oneLine(string.format(OfflineConfig.BoostOwnedText, multiplier))
			.. NBSP
			.. NBSP
			.. ROBUX
			.. NBSP
			.. tostring(price)
	else
		self._boostCaption.Text = oneLine(string.format(OfflineConfig.BoostBuyFormat, multiplier, price))
	end
end

--- A short squeeze on the boost button when a purchase lands on it. Quieter than the number's own
--- pulse: this is the receipt, and the payout is still to come.
function OfflineController._pulseBoost(self)
	self._boostScale.Scale = 1
	local up = TweenService:Create(self._boostScale, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.07 })
	up:Play()
	up.Completed:Once(function()
		TweenService:Create(self._boostScale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
end

--[[ The count-up. The only thing on this controller that runs per frame, and it stops itself the
	moment it arrives — a screen that a player leaves open is not one that should still be doing
	arithmetic behind them.

	EASED OUT rather than linear: the number is the payoff and a linear count arrives without ever
	having felt like it was going to. ]]
function OfflineController._tick(self)
	if not self._open or self._counted == nil or self._counted >= (self._target or 0) then
		return
	end
	local elapsed = os.clock() - (self._countStart or 0)
	local fraction = math.clamp(elapsed / COUNT_TIME, 0, 1)
	local eased = 1 - (1 - fraction) ^ 3

	--[[ FROM `_countFrom`, NOT FROM ZERO. It is 0 for the offer's own count and it is wherever the
		number had got to for a boosted one, which is what lets the boost continue the climb instead of
		restarting it — see `_onCollected`. ]]
	local from = self._countFrom or 0
	local value = math.floor(from + ((self._target or 0) - from) * eased)
	if value ~= self._counted then
		self._counted = value
		self._amount.Text = GarageConfig.formatCash(value)
	end
	if fraction >= 1 then
		self._counted = self._target
		self._amount.Text = GarageConfig.formatCash(self._target or 0)
		self:_pulse()
	end
end

--- A short punch on the number when it lands. Scale only, and small — the drama belongs to the size
--- of the number, which is the note this project's effects are tuned to.
function OfflineController._pulse(self)
	self._amountScale.Scale = 1
	local up = TweenService:Create(self._amountScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.12 })
	up:Play()
	up.Completed:Once(function()
		TweenService:Create(self._amountScale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
end

-- === Show / hide ============================================================

function OfflineController._show(self, offer)
	if not self._gui then
		self:_build()
	end
	if self._open then
		return
	end

	self._open = true
	self._locked = false
	self._token = (self._token or 0) + 1
	self:_paint(offer)

	self._gui.Enabled = true
	self._amountScale.Scale = 1
	if self._kit then
		self:_raiseKit()
	else
		self:_tween(self._scrim, RAISE_TIME, { BackgroundTransparency = SCRIM_REST })
		self:_tween(self._panel, RAISE_TIME, { ImageTransparency = 0 })
		self:_tween(self._bar, RAISE_TIME, { ImageTransparency = 0 })
		self:_tween(self._title, RAISE_TIME, { TextTransparency = 0 })
		self:_tween(self._close, RAISE_TIME, { ImageTransparency = 0 })
		-- The away line rests dimmer than the number: it is the receipt, not the headline.
		self:_tween(self._away, RAISE_TIME, { TextTransparency = 0.3 })
		self:_tween(self._amount, RAISE_TIME, { TextTransparency = 0 })
		self:_tween(self._foot, RAISE_TIME, { TextTransparency = 0.15 })
		self:_tween(self._button, RAISE_TIME, { ImageTransparency = 0 })
		self:_tween(self._caption, RAISE_TIME, { TextTransparency = 0 })
		if self._boost.Visible then
			self._boostScale.Scale = 1
			self:_tween(self._boost, RAISE_TIME, { ImageTransparency = 0 })
			self:_tween(self._boostCaption, RAISE_TIME, { TextTransparency = 0 })
		end
	end

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

	--[[ The count starts when the panel is actually there to be read, not when `_show` is called. The
		results screen learned this the hard way: a beat that opens under a fade is a beat nobody ever
		watches, however correctly it plays. ]]
	self._countStart = os.clock() + RAISE_TIME * 0.5

	if not self._tickConn then
		self._tickConn = RunService.RenderStepped:Connect(function()
			self:_tick()
		end)
	end
end

function OfflineController._hide(self)
	if not (self._gui and self._open) then
		return
	end
	self._open = false
	local token = self._token

	local last
	if self._kit then
		--- The panel drops back to 0.9 and goes, as a page does, and the dim finishes its own fade
		--- behind it. The dim is the longer of the two, so it is the one the switch-off waits for.
		local drop = TweenService:Create(self._popScale, KIT_CLOSE, { Scale = KIT_START_SCALE })
		drop:Play()
		drop.Completed:Once(function()
			if self._token == token and not self._open then
				self._panel.Visible = false
			end
		end)
		last = self:_tween(self._scrim, DROP_TIME, { BackgroundTransparency = 1 })
	else
		self:_tween(self._scrim, DROP_TIME, { BackgroundTransparency = 1 })
		self:_tween(self._panel, DROP_TIME, { ImageTransparency = 1 })
		self:_tween(self._bar, DROP_TIME, { ImageTransparency = 1 })
		self:_tween(self._title, DROP_TIME, { TextTransparency = 1 })
		self:_tween(self._close, DROP_TIME, { ImageTransparency = 1 })
		self:_tween(self._away, DROP_TIME, { TextTransparency = 1 })
		self:_tween(self._amount, DROP_TIME, { TextTransparency = 1 })
		self:_tween(self._foot, DROP_TIME, { TextTransparency = 1 })
		self:_tween(self._button, DROP_TIME, { ImageTransparency = 1 })
		self:_tween(self._boost, DROP_TIME, { ImageTransparency = 1 })
		self:_tween(self._boostCaption, DROP_TIME, { TextTransparency = 1 })
		last = self:_tween(self._caption, DROP_TIME, { TextTransparency = 1 })
	end
	self:_fadePad(DROP_TIME, false)

	last.Completed:Once(function()
		-- Fenced on the token for the same reason the respawn screen fences its own: nothing should
		-- be switched off by the tail of a screen that has already been replaced.
		if self._token == token and not self._open then
			self._gui.Enabled = false
			self:_bindPad(false)
			if self._tickConn then
				self._tickConn:Disconnect()
				self._tickConn = nil
			end
		end
	end)
end

function OfflineController._tween(self, inst, time: number, props)
	local tween = TweenService:Create(inst, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

--[[ The kit panel's arrival: the dim fades in on this file's own timing and the panel pops from 0.9,
	which is how every V2 page opens. Nothing on the panel is faded part by part. The kit's art is a
	gradient rim, a checker, a white body, strokes and outlined type, and fading those one at a time
	shows the rim through a half-clear body and leaves outlines standing after their letters. ]]
function OfflineController._raiseKit(self)
	self._boostScale.Scale = 1
	self._scrim.BackgroundTransparency = 1
	self:_tween(self._scrim, RAISE_TIME, { BackgroundTransparency = SCRIM_REST })
	self._popScale.Scale = KIT_START_SCALE
	self._panel.Visible = true
	TweenService:Create(self._popScale, KIT_OPEN, { Scale = 1 }):Play()
end

-- === The controller =========================================================

--[[ A and B, live only while the screen is, and both are the same two functions the mouse calls —
	so there is one definition of what collecting is and the lock guards all of it.

	Each badge hangs off the button it names, which the respawn screen could NOT do — its two answers
	are a button that scales on press and a bare word, so its glyphs had to be measured onto the
	scrim instead. Here the press is inside the art (the pill's face drops 6px in the image; the X
	swaps texture), so both instances stand perfectly still and the badge can simply be their
	child. ]]
function OfflineController._bindPad(self, on: boolean)
	GamepadInput.setModal("OfflineController", on)

	if not on then
		GamepadInput.unbind(PAD_COLLECT)
		GamepadInput.unbind(PAD_BOOST)
		GamepadInput.unbind(PAD_CLOSE)
		return
	end

	--- Same bindings on both panels; only where the badges hang differs (see `KIT_BADGE_POS`).
	local badgePos = if self._kit then KIT_BADGE_POS else PAD_BADGE_POS
	local badgeAnchor = if self._kit then KIT_BADGE_ANCHOR else PAD_BADGE_ANCHOR

	GamepadInput.bind({
		actionName = PAD_COLLECT,
		keyCode = Enum.KeyCode.ButtonA,
		callback = function()
			self:_pressCollect()
		end,
		parent = self._button,
		iconPosition = badgePos,
		iconAnchor = badgeAnchor,
		iconSize = PAD_BADGE_SIZE,
		priority = PAD_PRIORITY,
	})

	--[[ Y, and BOUND ONLY WHEN THE BUTTON IS THERE. A binding whose parent is invisible draws a badge
		nobody can see attached to a button nobody can press, and would still swallow the press.

		Y RATHER THAN X because it is the button this game already means "the other thing" with —
		`DriveConfig.ExitKeys` is Y — and because A and B are already spoken for here by the two
		answers the respawn screen taught. ]]
	if self._boost.Visible then
		GamepadInput.bind({
			actionName = PAD_BOOST,
			keyCode = Enum.KeyCode.ButtonY,
			callback = function()
				self:_pressBoost()
			end,
			parent = self._boost,
			iconPosition = badgePos,
			iconAnchor = badgeAnchor,
			iconSize = PAD_BADGE_SIZE,
			priority = PAD_PRIORITY,
		})
	end
	GamepadInput.bind({
		actionName = PAD_CLOSE,
		keyCode = Enum.KeyCode.ButtonB,
		callback = function()
			self:_pressClose()
		end,
		parent = self._close,
		iconPosition = if self._kit then KIT_CLOSE_BADGE_POS else UDim2.fromScale(0.5, 1.35),
		iconAnchor = if self._kit then KIT_CLOSE_BADGE_ANCHOR else Vector2.new(0.5, 0.5),
		-- Smaller, like the answer it belongs to: closing is the way out, not the offer.
		iconSize = GamepadConfig.Icon.Size * 0.72,
		priority = PAD_PRIORITY,
	})
end

function OfflineController._padIcons(self): { ImageLabel }
	local icons = {}
	for _, action in { PAD_COLLECT, PAD_BOOST, PAD_CLOSE } do
		local icon = GamepadInput.getIcon(action)
		if icon and icon.Parent then
			table.insert(icons, icon)
		end
	end
	return icons
end

--- Fade the badges with the screen. The badge is a filled disc, so its background goes with the
--- image rather than being left as a solid dot behind a fading glyph.
function OfflineController._fadePad(self, time: number, visible: boolean)
	local transparency = if visible then 0 else 1
	for _, icon in self:_padIcons() do
		self:_tween(icon, time, { ImageTransparency = transparency, BackgroundTransparency = transparency })
		local stroke = icon:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			self:_tween(stroke, time, { Transparency = transparency })
		end
	end
end

OfflineController:withRemoteEvents({
	{
		OfflineEarnings = function(offer)
			if type(offer) == "table" and type(offer.amount) == "number" then
				OfflineController:_show(offer)
			end
		end,
		OfflineCollected = function(amount, multiplier)
			OfflineController:_onCollected(amount, multiplier)
		end,
		OfflineBoostState = function(boosts)
			OfflineController:_onBoostState(boosts)
		end,
	},
	"OfflineClaim",
	"OfflineReady",
})

OfflineController:withLifecycle({
	init = function(self)
		self._open = false
		self._locked = false
		self._token = 0
		--- What the boost button is drawn from until an offer says otherwise. Config rather than zero so
		--- a repaint that somehow beats the first offer draws a sane button instead of a free one.
		self._boosts = 0
		self._multiplier = OfflineConfig.Boost.Multiplier
		self._price = OfflineConfig.Boost.Price
	end,

	start = function(self)
		if not (OfflineConfig.Enabled and GarageConfig.Enabled) then
			return
		end

		--[[ BUILT BEFORE THE PING, NOT WHEN THE OFFER ARRIVES. The ping is a promise that a remote sent
			now will be heard, and the screen has to exist for that to be true — `_build` yields on
			PlayerGui, so a panel assembled inside the remote handler would be assembled after the
			remote it was for. ]]
		--- Asked now so the welcome-back screen has the real price by the time it opens, and redrawn if
		--- the answer lands after it does.
		LivePrice.fetch(OfflineConfig.Boost.ProductId, nil, function(price)
			if price and self._boostCaption then
				self:_paintBoost()
			end
		end)
		self:_build()
		self:getRemoteEvent("OfflineReady"):Fire()
	end,
})

return OfflineController
