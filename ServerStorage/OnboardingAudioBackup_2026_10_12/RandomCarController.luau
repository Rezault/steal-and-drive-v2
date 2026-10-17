--[[
	RandomCarController  (client)
	-----------------------------
	Two screens for one product. THE CARD slides in from the right-hand edge on a timer and offers a
	random car for Robux; THE REVEAL opens over the middle when one is rolled and shows what came
	out.

	BOTH ARE BUILT IN CODE OUT OF THE KIT'S OWN ART, which is this project's third way of drawing UI
	and the one `OfflineController`'s header sets out: the pages under `UIController` are authored in
	the place because the artist drew them, `ReviveController` is code and plain shapes because the
	artist drew no wreck screen, and this is code assembled from UPLOADED PIECES because neither PSD
	has an offer card but the kit already has every part one is made of. The reveal is the page
	chassis whole, panel and title cap and pill, and the card is one piece of it: the sunburst
	`RaceUIController` spins behind the run results.

	NOTHING NEW WAS UPLOADED FOR EITHER SCREEN. Worth stating plainly, because the obvious way to
	build a card that looks like the reference is to draw one: every navy surface, every button state
	and the burst itself already exist and are documented in `UIAssets`, and a hand-drawn card would
	be the one screen in the game that drifts when the kit moves.

	=== THE CARD IS A SILHOUETTE, NOT A PANEL ================================================

	It had the kit's navy panel behind it and a green pill under it. Both are gone, and what is left
	is a shape in a turning light with three lines of text on it. The panel was a box drawn round
	furniture that already reads as furniture, and the pill was a second click target on a card that
	is only ever pressed for one reason.

	SO THE WHOLE CARD IS THE BUTTON. `Hit` is a transparent ImageButton the size of the card, under
	everything the card draws, and it is the only `Active` thing on the screen. That keeps the old
	promise a new way: a click anywhere on the shape buys, and a click one pixel off it still belongs
	to the HUD.

	THE SILHOUETTE IS THE HERO AND IT SITS ON THE BURST'S CENTRE. Nothing else on the card has an
	edge any more, so the shape has to carry it: it fills the card's width, it is centred on the
	burst rather than riding above it, and the rays come out from behind the car on every side.

	=== THE CAR IS A VIEWPORT, NOT A PICTURE ==================================================

	`Modules/CarViewport` puts a real roster body in a box, and it already has `silhouette` — the
	locked cut-out the Cars Inventory draws for a car you have not found. So the card's mystery shape
	and the reveal's finished car are THE SAME CALL with one flag flipped, which is what makes the
	reveal a genuine resolve rather than a cross-fade between two different drawings.

	It also means the shape is honest: the silhouette on the card is the outline of an actual car in
	this world, at the same pose and framing it will be revealed at.

	=== WHAT THE CARD IS ALLOWED TO CLAIM ====================================================

	It draws `RandomCarConfig.teaserFor` — the BEST car in the player's world — and that is a claim
	with a knife-edge on it. Read the header note in `RandomCarConfig` before touching any of the
	copy: it is honest only for as long as the card never names the car, never prints its income, and
	says RANDOM in the loudest place on it. A card that named the shape would be selling one specific
	car for 99 Robux.

	=== THE CADENCE IS THE WHOLE OF WHY IT IS BEARABLE =======================================

	Ported from NeedohEscape's `SideButtonsController` — the rotating right-side product buttons,
	which is where this project's `UIController` came from too. The card shows for `ShowSeconds`,
	leaves for `HideSeconds`, and is off screen entirely while a race is running. Sliding rather than
	appearing, on the same Sine easing and the same off-screen offset that game uses, because two
	games in the same house should move a card the same way.

	IT SLIDES A WRAPPER, NOT THE CARD. `__Slide` is a plain Frame holding the card's visuals; the
	card itself never moves. That is NeedohEscape's trick and the reason is the same one there: the
	burst and the title overhang the card's own box, and a `CanvasGroup` — the other way to move a
	subtree — renders to a bounded buffer and would clip both. A Frame does not clip its descendants.

	=== THE REVEAL IS MODAL AND THE CARD IS NOT ==============================================

	The card is furniture: it must never eat a click meant for the HUD, so nothing in it is `Active`
	except the one transparent button that covers it. The reveal is the opposite — it is the moment
	the player paid for, so it takes a scrim, it takes the screen, and it closes every page behind it
	on the way up. That
	last part is not only tidiness: the reveal wears the kit's GREEN title cap, and `UIAssets.Page`
	notes that green is shared with the Market page — closing the pages means the two can never be on
	screen together, which is the condition that sharing was allowed under.

	=== WITH THE NEW UI ON, BOTH ARE THE KIT'S CARD (Phase 4, 2026-09-16) ======================

	`UIRoot.isNewUI()` swaps where the art comes from and nothing else. `BuildRandomCarV2` authors
	both screens on `MainUIV2.Screens` out of ONE Cartoony Kit card (`TeamSelectionUI`'s), and
	`_buildCardV2` / `_buildRevealV2` clone them into this file's own two ScreenGuis, at the same
	`DisplayOrder`s, instead of assembling panels out of `UIAssets`. The cadence, the press, the
	remotes, the roll and the beat are the same code on both paths; the handful of methods that touch
	a drawn part branch on whether the V2 part is there. With the flag off `_buildCard` and
	`_buildReveal` run exactly as they always have.

	THE SAME CARD ON BOTH SCREENS is the kit version of this file's own idea: the silhouette and the
	resolved car are one `CarViewport` call, and now the card the player pressed at the edge of the
	lobby is the card that opens in the middle and turns over. The build command's header has the
	rest (why not `PromptUI`, what each part is).

	WHAT THE KIT CHANGES, and where to look:
	  • The price goes on a real button. The card still presses anywhere (`Hit`), but the kit draws a
	    button and hiding it would be the one card in the kit with no affordance. It wears three
	    faces, one at a time: orange `BuyBtn` (the kit's Robux face, priced with its U+E002 glyph),
	    green `OpenBtn` for a banked pull, grey `DisabledBtn` for COMING SOON. See `_paintCard`.
	  • The rarity is TYPE in the band's colour, not a pill. A pill reads as a button in this kit and
	    the rarity cannot be pressed. It uses `Modules/CarRarity`, the word and colour every V2 car
	    card prints, and the name is `GarageConfig.carName`, colour included.
	  • The close is locked by FACE, not hidden: the grey `DisabledBtn` stands where NICE will be
	    until `CloseLockSeconds` pass, which is the kit's own drawing of "not yet".
	  • THE REVEAL GAINS A PAD. It raises `GamepadConfig.ModalAttribute` and binds A and B to NICE.
	    The shipping reveal has neither and a controller cannot close it (its NICE listens for a mouse
	    click, and nothing can select a button in this ScreenGui); that is left as it is on the old
	    path and written up in the migration notes.
	  • The offer card has NO pad path, on either UI. It is lobby furniture on a timer and every face
	    button is spoken for in the lobby (A jump, X prompts, Y play, B back).

	INSETS: the offer does NOT ignore the GUI inset, so it lays out in the kit's own space beside
	the kit HUD and a notched phone keeps it off the notch. The reveal DOES, like the shipping one,
	so its scrim covers the topbar.

	HOUSE RULE: no wiki-style double-bracket links in these comments — the closing pair ends the
	block comment early and the parse error points at the wrong line.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local GamepadConfig = require(ReplicatedStorage.shared.Configs.GamepadConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local RandomCarConfig = require(ReplicatedStorage.shared.Configs.RandomCarConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)
local GamepadInput = require(ReplicatedStorage.shared.Modules.GamepadInput)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)

local LocalPlayer = Players.LocalPlayer

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)
local WHITE = Color3.fromRGB(255, 255, 255)
local SCRIM_COLOR = Color3.fromRGB(6, 8, 12)

--[[ The burst's tint. Warm gold rather than white, because it is laid over the kit's navy panel and
	a white burst on navy is a grey smear — `UIAssets.Results.Sunburst` is pure white precisely so
	each screen picks its own colour, and this is the one this screen picks. ]]
local BURST_COLOR = Color3.fromRGB(255, 214, 112)

--[[ The price. `OfflineController`'s cash green, and it is deliberate that the number wears the
	colour the button used to: the pill is gone, so the colour is all that is left of the affordance
	saying this line is the thing you press for. ]]
local PRICE_GREEN = Color3.fromRGB(126, 217, 87)

--[[ What every word on the card is outlined in. There is no panel behind them any more, so the copy
	is read against whatever the lobby happens to be doing: a bright forecourt, a night street, a car
	going past. `NearMissController` draws over the road for the same reason and its note explains
	the `Contextual` mode this uses. ]]
local TEXT_OUTLINE = Color3.fromRGB(8, 10, 16)

--[[ Rarity word -> `UIAssets.Pill` colour. THE SAME FIVE PAIRINGS `Market.luau` USES, copied
	deliberately rather than shared: the Market page owns its map for the shelf it draws, and a
	player who has learned that a purple pill means Sports on one screen must not meet a different
	purple on another. If a sixth band is ever added, both move together or neither should.

	Blue and Red are left out here for Market's reasons too — Blue is a buy pill and would read as a
	rarity, Red is kept for a state rather than spent on a tier. ]]
local RARITY_PILL = {
	Beater = "Silver",
	Sedan = "Green",
	Coupe = "Sky",
	Sports = "Purple",
	Supercar = "Orange",
}

--[[ NeedohEscape's own two positions, so the motion matches. See the header.

	CENTRED RATHER THAN CORNERED, which the old card had no reason to be and this one does: the
	wrapper carries the press dip's `UIScale`, and a scale grows about its object's anchor point. Off
	the top-left corner every press would shove the card down and to the right instead of squashing
	it where it stands. ]]
local HOME_POS = UDim2.fromScale(0.5, 0.5)
local OFF_POS = UDim2.fromScale(0.5 + RandomCarConfig.Card.SlideOffset, 0.5)

--[[ The press. No pill means no pressed art, so the card itself takes the press: one squash on the
	wrapper, which reads the same for a click and for a tap and costs one instance. ]]
local PRESS_SCALE = 0.95
local PRESS_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLIDE_IN = TweenInfo.new(RandomCarConfig.Card.SlideSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(RandomCarConfig.Card.SlideSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.In)

--[[ Where the card sits: pinned to the right edge, a little above centre.

	ABOVE CENTRE RATHER THAN ON IT, because the middle-right of the screen is where the speedometer
	and the HP track live the moment a race starts. The card is hidden during a race
	(`HideDuringRace`), so they can never actually collide — but a card that occupies race furniture's
	space in the lobby teaches the player to ignore that corner, and they need it later.

	IT SITS FURTHER OFF THE EDGE THAN IT USED TO. The panel used to be where the card ended, and now
	the burst is: the light is wider than the card's own box on purpose, so leaving the box pinned at
	0.985 would run the rays off the side of the screen and cut half of them away. ]]
local CARD_POS = UDim2.fromScale(0.96, 0.42)
local CARD_ANCHOR = Vector2.new(1, 0.5)

--[[ PORTRAIT, and sized off the viewport's SHORT side rather than in mixed scale.

	`UDim2.fromScale(w, h)` on a 16:9 screen makes a box whose proportions change with the window —
	the same two numbers are a portrait card on a phone and a landscape one on an ultrawide, and the
	car inside it is framed to the box. So the height is the scale and the aspect is a constraint,
	which is the same bargain `CarViewport`'s own callers make: the card is the same shape on every
	device and only its size changes.

	0.72:1 is a little taller than the reference card and deliberately so — the burst has to leave
	the box on all four sides to read as light rather than as a textured panel, and a squarer card
	crops the rays top and bottom first.

	THE WIDTH SCALE IS A CEILING, NOT THE WIDTH, and it may not be 0. `UIAspectRatioConstraint`
	defaults to `FitWithinMaxSize`, which fits the box inside the size it was given rather than
	deriving one axis from the other — so a width of 0 fits inside 0 and the card collapses to
	nothing on both axes. 0.5 is simply more width than 0.3 of the viewport's height can ever ask
	for at this aspect, which leaves the height in charge on every screen shape. ]]
local CARD_SIZE = UDim2.fromScale(0.5, 0.32)
local CARD_ASPECT = 0.72

--[[ The car's box inside the card, and the shape its camera is fitted to.

	IT FILLS THE CARD, because with the panel gone there is nothing else holding the shape. Centred
	on the card, which puts it on the burst's centre, which is the whole look.

	`VIEW_ASPECT` IS DERIVED AND MUST STAY THAT WAY. `CarViewport.set` fits the camera to the frame's
	width over height and cannot measure it (its header, note 5: a card built this frame has not been
	laid out and reads 0), so the number is passed in. Typed by hand it would be a third constant
	that has to move whenever either of the first two does, and the failure is silent: the camera
	backs off until the car fits a frame that is not this one and the car sits small in its box,
	which is exactly what the old card did by passing no aspect at all. ]]
local VIEW_W, VIEW_H = 0.98, 0.5
local VIEW_BOX = UDim2.fromScale(VIEW_W, VIEW_H)
local VIEW_ASPECT = (VIEW_W * CARD_ASPECT) / VIEW_H

local PANEL_BOX = UDim2.fromScale(0.62, 0.62)

-- === The kit's card (new UI) ================================================

--- Where `BuildRandomCarV2` leaves the two templates, and how long a boot waits for each before
--- warning and falling back to the shipping screen.
local SHELF_NAME = "Screens"
local OFFER_TEMPLATE = "RandomCarOffer"
local REVEAL_TEMPLATE = "RandomCarReveal"
local TEMPLATE_WAIT = 10

--- The kit prices Robux with Roblox's own mark from the private use area. See the notes, "Shop".
local ROBUX = utf8.char(0xE002)

--- The pop every V2 page opens with (`UIController.openPage`), which the other Phase 4 modals use too.
local KIT_START_SCALE = 0.9
local KIT_POP = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

--- The rarity line's colour runs from a lift of the band's colour down to the colour itself, the
--- ramp `PagesV2/StartCar` writes into the same kit gradient.
local RARITY_LIFT = 0.35

--[[ The reveal's pad keys. Priority over the seat and the prompts for as long as the modal is up,
	the same margin `RenameController` takes, and handed straight back on the way down. ]]
local PAD_REVEAL_CLOSE = "RandomCarRevealClose"
local PAD_PRIORITY = Enum.ContextActionPriority.High.Value + 600

-- Non-breaking, because `TextScaled` would sooner break a caption onto a second line than pick a
-- smaller font. Every space in a one-line label on these screens is this one.
local NBSP = utf8.char(0xA0)

local function oneLine(text: string): string
	return (string.gsub(string.upper(text), "%s+", NBSP))
end

--- 9-slice from the recorded texture size and inset, both out of `UIAssets` — the same helper
--- `OfflineController` carries, and the same warning applies: `Size` is what Roblox STORED, not what
--- the PSD measured.
local function slice(image: ImageLabel | ImageButton, size: Vector2, inset: number)
	image.ScaleType = Enum.ScaleType.Slice
	image.SliceCenter = Rect.new(inset, inset, size.X - inset, size.Y - inset)
end

--[[ A sunburst behind whatever it is parented to, tagged so `Components/SunBurst` turns it.

	`ZIndex` 0 and the parent's children at 1+, so it sits behind them without either needing to know
	about the other. Square and oversized — the rays have to leave the box on every side or the
	burst reads as a textured panel rather than as light coming from the car. ]]
local function sunburst(parent: GuiObject, speed: number): ImageLabel
	local burst = Instance.new("ImageLabel")
	burst.Name = "Burst"
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.5)
	burst.Size = UDim2.fromScale(1.7, 1.7)
	burst.BackgroundTransparency = 1
	burst.Image = UIAssets.url(UIAssets.Results.Sunburst)
	burst.ImageColor3 = BURST_COLOR
	burst.ImageTransparency = 0.55
	burst.ZIndex = 0
	burst.Parent = parent

	--- Square, so `Rotation` pivots without an offset — the burst is drawn on a 1024 square
	--- (`UIAssets.ResultsSize.Sunburst`) for exactly this reason.
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = burst

	burst:SetAttribute("RotateSpeed", speed)
	CollectionService:AddTag(burst, "SunBurst")
	return burst
end

--[[ One pill button and its caption, the shape `OfflineController._pill` makes and for its reasons —
	stretched rather than sliced (the aspect constraint pins it to the art's own 3.89:1, and slicing
	pins the corner curve at texture pixels while the middle shrinks), caption padded up off the
	bottom edge so the pressed art's 6px drop does not slide out from under the word. ]]
local function pill(parent: GuiObject, name: string, colour: string, text: string): (ImageButton, TextLabel)
	local colours = UIAssets.Pill[colour] or UIAssets.Pill.Green

	local button = Instance.new("ImageButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false -- the art has its own three states; Roblox's tint fights them
	button.Image = UIAssets.url(colours.Idle)
	button.HoverImage = UIAssets.url(colours.Hover)
	button.PressedImage = UIAssets.url(colours.Pressed)
	button.ScaleType = Enum.ScaleType.Stretch
	button.Parent = parent

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = UIAssets.Size.Pill.X / UIAssets.Size.Pill.Y
	aspect.Parent = button

	local caption = Instance.new("TextLabel")
	caption.Name = "Label"
	caption.AnchorPoint = Vector2.new(0.5, 0.5)
	caption.Position = UDim2.fromScale(0.5, 0.46)
	caption.Size = UDim2.fromScale(0.82, 0.42)
	caption.BackgroundTransparency = 1
	caption.FontFace = FONT
	caption.Text = oneLine(text)
	caption.TextColor3 = WHITE
	caption.TextScaled = true
	caption.Parent = button

	return button, caption
end

--[[ An outline on a label, so it survives being read against the lobby instead of a panel.

	`Contextual` rather than the default, which is `NearMissController`'s choice and its reason: the
	stroke then draws only where the glyph meets the background, so it darkens the edge of a letter
	without thickening the letter itself at phone resolutions. ]]
local function outline(text: TextLabel): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = TEXT_OUTLINE
	stroke.Thickness = 2
	stroke.Transparency = 0.1
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = text
	return stroke
end

local function label(parent: GuiObject, name: string, pos: UDim2, size: UDim2, text: string): TextLabel
	local text_ = Instance.new("TextLabel")
	text_.Name = name
	text_.AnchorPoint = Vector2.new(0.5, 0.5)
	text_.Position = pos
	text_.Size = size
	text_.BackgroundTransparency = 1
	text_.FontFace = FONT
	text_.Text = oneLine(text)
	text_.TextColor3 = WHITE
	text_.TextScaled = true
	text_.Parent = parent
	return text_
end

--[[ The kit card's face colour at a height down the card, read off its own gradient.

	FOR THE VIEWPORT'S BACKDROP, which is only ever seen one pixel at a time round the edge of the car
	(see `Modules/CarViewport`'s `BACKDROP`). The kit card is a top-to-bottom gradient rather than the
	flat navy that module defaults to, so the colour is sampled where the car actually sits. Nil for a
	card with no gradient, which leaves the module's default. ]]
local function faceColourAt(card: Instance, y: number): Color3?
	local gradient = card:FindFirstChildOfClass("UIGradient")
	if not gradient then
		return nil
	end
	local points = gradient.Color.Keypoints
	for index = 1, #points - 1 do
		local from, to = points[index], points[index + 1]
		if y <= to.Time then
			local alpha = (y - from.Time) / math.max(to.Time - from.Time, 1e-3)
			return from.Value:Lerp(to.Value, math.clamp(alpha, 0, 1))
		end
	end
	return points[#points].Value
end

local function rarityRamp(colour: Color3): ColorSequence
	return ColorSequence.new(colour:Lerp(WHITE, RARITY_LIFT), colour)
end

--- A kit button's caption, which is its `Title` child.
local function caption(button: Instance?, text: string)
	local title = button and button:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = text
	end
end

--[[ The shape the car's camera is fitted to: the `Car` slot's width over its height, in pixels,
	worked out from the template's proportions because a clone made this frame has not been laid out
	(`CarViewport`'s header, note 5). `cardAspect` is the card's own, off the template's constraint. ]]
local function slotAspect(slot: GuiObject, cardAspect: number): number
	return (slot.Size.X.Scale * cardAspect) / math.max(slot.Size.Y.Scale, 1e-3)
end

local RandomCarController = Shard.new("RandomCarController")

-- === The kit's templates (new UI) ===========================================

--[[ One template off the shelf, waited for with a timeout and a warning, or nil.

	NIL IS NOT FATAL. The caller falls back to the shipping screen, which needs nothing from the
	place, so a build that has not run `BuildRandomCarV2` still sells the product in the old look and
	says why in the output rather than leaving a card that never appears. ]]
function RandomCarController._template(_self, name: string): GuiObject?
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local root = UIRoot.wait(playerGui :: PlayerGui, TEMPLATE_WAIT)
	local shelf = root and root:WaitForChild(SHELF_NAME, TEMPLATE_WAIT)
	local template = shelf and shelf:WaitForChild(name, TEMPLATE_WAIT)
	if not (template and template:IsA("GuiObject")) then
		warn(string.format("[RandomCarController] No %s.%s.%s in this place; using the old screen. Run BuildRandomCarV2.", UIRoot.name(), SHELF_NAME, name))
		return nil
	end
	return template
end

-- === The card ===============================================================

--[[ The offer, assembled once and then only ever slid, repainted and hidden. Built in `start` rather
	than on the first appearance for `OfflineController._build`'s reason: this yields on PlayerGui,
	and a card assembled inside a timer callback is a card assembled after the moment it was for. ]]
function RandomCarController._buildCard(self)
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "RandomCarOffer"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	--[[ BELOW the HUD's own layer and far below the reveal's 998. The card is the least important
		thing on screen by construction — it is an advertisement — and anything the game needs to say
		must be able to land on top of it. ]]
	gui.DisplayOrder = 5
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = playerGui

	local root = Instance.new("Frame")
	root.Name = "Card"
	root.AnchorPoint = CARD_ANCHOR
	root.Position = CARD_POS
	root.Size = CARD_SIZE
	root.BackgroundTransparency = 1
	root.Parent = gui

	--- Height is the scale, aspect is the shape — see `CARD_SIZE`.
	local rootAspect = Instance.new("UIAspectRatioConstraint")
	rootAspect.AspectRatio = CARD_ASPECT
	rootAspect.DominantAxis = Enum.DominantAxis.Height
	rootAspect.Parent = root

	--[[ The wrapper that actually moves — see the header on why this is a plain Frame and not a
		CanvasGroup, and why the card itself never leaves its own position. ]]
	local sliding = Instance.new("Frame")
	sliding.Name = "__Slide"
	sliding.AnchorPoint = Vector2.new(0.5, 0.5)
	sliding.Size = UDim2.fromScale(1, 1)
	sliding.Position = OFF_POS
	sliding.BackgroundTransparency = 1
	sliding.Parent = root

	--- The press dip, on the wrapper so one tween squashes the whole card. See `PRESS_SCALE`.
	local scale = Instance.new("UIScale")
	scale.Parent = sliding

	--[[ THE CARD IS THE BUTTON: one transparent ImageButton the size of the card, under everything
		the card draws and the only `Active` thing on this screen. See the header.

		THE SIZE OF THE CARD AND NOT OF THE BURST, deliberately. The light is half again as wide as
		the box, and a click target cut to it would be a slab of invisible furniture sitting over the
		HUD, which is the one thing this screen is not allowed to be. ]]
	local hit = Instance.new("ImageButton")
	hit.Name = "Hit"
	hit.AnchorPoint = Vector2.new(0.5, 0.5)
	hit.Position = UDim2.fromScale(0.5, 0.5)
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.ImageTransparency = 1
	hit.AutoButtonColor = false
	hit.ZIndex = 1
	hit.Parent = sliding

	sunburst(sliding, RandomCarConfig.Card.BurstSpeed)

	--[[ The mystery car, dead centre so it covers the middle of the burst and the rays come out from
		behind it. `Active` is false on a ViewportFrame by default and `CarViewport` keeps it that way
		on purpose (its own note says so), which is what lets the button underneath stay pressable
		with this sitting over it. ]]
	local view = CarViewport.new(sliding, "Teaser")
	view.AnchorPoint = Vector2.new(0.5, 0.5)
	view.Position = UDim2.fromScale(0.5, 0.5)
	view.Size = VIEW_BOX
	view.ZIndex = 2

	local title = label(sliding, "Title", UDim2.fromScale(0.5, 0.075), UDim2.fromScale(1, 0.12), RandomCarConfig.CardTitle)
	title.ZIndex = 3
	outline(title)

	--[[ The price, which is all that is left of the button: the number, in the pill's own green,
		close under the car so it reads as the price OF the shape rather than a line of copy.
		`_paintCard` is the other half of it and swaps this for OPEN when a pull is banked. ]]
	local price = label(sliding, "Price", UDim2.fromScale(0.5, 0.85), UDim2.fromScale(0.8, 0.13), string.format(RandomCarConfig.CardBuyFormat, RandomCarConfig.Price))
	price.TextColor3 = PRICE_GREEN
	price.ZIndex = 3
	outline(price)

	--[[ The honesty line, and it is opaque where the old one was faded. A dimmed white over a navy
		panel is grey text; a dimmed white over the lobby is text that vanishes into whatever happens
		to be behind it. It is quieter than the price because it is smaller, which is the only way to
		be quiet out here. ]]
	local subtitle = label(sliding, "Subtitle", UDim2.fromScale(0.5, 0.955), UDim2.fromScale(1, 0.065), RandomCarConfig.CardSubtitle)
	subtitle.ZIndex = 3
	outline(subtitle)

	--[[ Down and up rather than the click alone, so the card answers on the way down. `MouseLeave`
		is in there because a press dragged off the card never gets its `Up`, and a card left squashed
		reads as one that has broken. ]]
	local function dip(on: boolean)
		TweenService:Create(scale, PRESS_TWEEN, { Scale = if on then PRESS_SCALE else 1 }):Play()
	end
	hit.MouseButton1Down:Connect(function()
		dip(true)
	end)
	hit.MouseButton1Up:Connect(function()
		dip(false)
	end)
	hit.MouseLeave:Connect(function()
		dip(false)
	end)
	hit.MouseButton1Click:Connect(function()
		self:_press()
	end)

	self._cardGui = gui
	self._slide = sliding
	self._cardScale = scale
	self._cardView = view
	self._cardPrice = price
	self:_buildOdds(sliding, sliding, { hit })
end

--[[ The offer on the new UI: `Screens.RandomCarOffer` cloned into a ScreenGui of this file's own.
	Returns false, having built nothing, when the template is not the shape `BuildRandomCarV2` makes,
	and `start` then builds the shipping card instead.

	It sets the same five fields `_buildCard` does, so the cadence and the slide never ask which card
	they are moving. What it adds is `_cardFaces` (the three buttons `_paintCard` picks between) and
	`_cardViewAspect` (the car slot's shape, which the shipping card keeps as a constant). ]]
function RandomCarController._buildCardV2(self, template: GuiObject): boolean
	local root = template:Clone()
	--- The kit's text caps are pixels for a 1080-tall screen; this keeps them in proportion above it.
	require(script.Parent.UIController.KitPage).scaleTextCaps(root)
	local slide = root:FindFirstChild("Slide")
	local press = slide and slide:FindFirstChildOfClass("UIScale")
	local card = slide and slide:FindFirstChild("Card")
	local slot = card and card:FindFirstChild("Car")
	local hit = card and card:FindFirstChild("Hit")
	local btns = card and card:FindFirstChild("Btns")
	local buy = btns and btns:FindFirstChild("BuyBtn")
	local open = btns and btns:FindFirstChild("OpenBtn")
	local disabled = btns and btns:FindFirstChild("DisabledBtn")
	local constraint = root:FindFirstChildOfClass("UIAspectRatioConstraint")
	if not (slide and press and card and slot and slot:IsA("GuiObject") and hit and hit:IsA("GuiButton") and buy and buy:IsA("GuiButton") and open and open:IsA("GuiButton") and disabled and constraint) then
		warn("[RandomCarController] Screens.RandomCarOffer is not the shape BuildRandomCarV2 makes; using the old card. Re-run the command.")
		root:Destroy()
		return false
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "RandomCarOffer"
	gui.ResetOnSpawn = false
	--- The kit's own space, beside the kit HUD. See the header on the two screens' insets.
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	--- Below the HUD's layer, for `_buildCard`'s reason: it is an advertisement.
	gui.DisplayOrder = 5
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	local sliding = slide :: GuiObject
	sliding.Position = OFF_POS
	root.Visible = true
	root.Parent = gui

	local title = card:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = oneLine(RandomCarConfig.CardTitle)
	end
	local subtitle = card:FindFirstChild("Subtitle")
	if subtitle and subtitle:IsA("TextLabel") then
		subtitle.Text = oneLine(RandomCarConfig.CardSubtitle)
	end

	--- In the slot the template drew, on the face colour behind it. `Active` stays false (see
	--- `_buildCard`), so `Hit` underneath still takes the press.
	local cardAspect = constraint.AspectRatio
	local slotCentre = slot.Position.Y.Scale
	local view = CarViewport.new(slot :: GuiObject, "Teaser", faceColourAt(card, slotCentre))
	view.AnchorPoint = Vector2.new(0.5, 0.5)
	view.Position = UDim2.fromScale(0.5, 0.5)
	view.Size = UDim2.fromScale(1, 1)

	--- Tagged here, on the clone, so the template on the hidden shelf is never turned.
	local imagery = card:FindFirstChild("Imagery")
	local burst = imagery and imagery:FindFirstChild("Burst")
	if burst then
		burst:SetAttribute("RotateSpeed", RandomCarConfig.Card.BurstSpeed)
		CollectionService:AddTag(burst, "SunBurst")
	end

	--[[ The press, off `Hit` and off whichever face is showing. `Activated` rather than the shipping
		card's click, so a tap counts. The dip stays on `Hit` alone: the kit's buttons already swell
		and sound through `Components/Button`, and a second squash under the cursor would be the card
		flinching twice for one press. ]]
	local function dip(on: boolean)
		TweenService:Create(press, PRESS_TWEEN, { Scale = if on then PRESS_SCALE else 1 }):Play()
	end
	hit.MouseButton1Down:Connect(function()
		dip(true)
	end)
	hit.MouseButton1Up:Connect(function()
		dip(false)
	end)
	hit.MouseLeave:Connect(function()
		dip(false)
	end)
	for _, button: GuiButton in { hit, buy, open } do
		button.Activated:Connect(function()
			self:_press()
		end)
	end

	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	self._cardGui = gui
	self._slide = sliding
	self._cardScale = press
	self._cardView = view
	self._cardPrice = buy:FindFirstChild("Title")
	self._cardFaces = { buy = buy, open = open, disabled = disabled }
	self._cardViewAspect = slotAspect(slot :: GuiObject, cardAspect)
	--[[ The chances: the template's own (`BuildRandomCarV2`, the kit's `OddsBtn` and a `PromptUI`
		tooltip) when the build has them, else drawn here like the shipping card's. ]]
	local targets = { hit, buy, open, disabled } :: { any }
	local odds = sliding:FindFirstChild("Odds")
	local oddsMain = odds and odds:FindFirstChild("Main")
	local oddsRow = oddsMain and oddsMain:FindFirstChild("RowTemplate")
	local oddsBtn = card:FindFirstChild("OddsBtn")
	if odds and odds:IsA("GuiObject") and oddsRow and oddsBtn and oddsBtn:IsA("GuiButton") then
		self:_bindKitOdds(odds, oddsBtn, oddsMain :: Instance, oddsRow, targets)
	else
		--- The panel on the slide, outside the card (which may clip); the `?` on the card's own corner.
		self:_buildOdds(sliding, card :: GuiObject, targets)
	end
	return true
end

-- === The odds tooltip ======================================================
--[[ THE CHANCES, NEXT TO THE CARD (2026-09-30). A panel to the card's left listing each rarity in this
	world's pool and its chance, read off `RandomCarConfig.oddsFor` — the roll's own arithmetic, so
	the printed odds are the real ones. Shown while the pointer is anywhere on the card; a small `?`
	button in the card's corner pins it open, which is the whole of the touch-screen version (a phone
	has no hover).

	HOVER IS COUNTED ACROSS EVERY PART OF THE CARD THAT CAN TAKE THE POINTER (`targets`): on the kit's
	card the buy button sits over `Hit`, and moving onto it fires `Hit.MouseLeave` — judged per event,
	the tooltip would blink off and on as the pointer crossed the price. The verdict is deferred a
	frame so a leave and an enter landing together settle before anything is drawn.

	The panel is built on the card's sliding frame (`slide`), so it arrives and leaves with the card
	and is never cut off by a card that clips its children; the `?` goes on `corner`, the card box. `_slideIn` repaints
	it (the world may have changed since the card was last up); `_slideOut` unpins and hides it. ]]
function RandomCarController._buildOdds(self, slide: GuiObject, corner: GuiObject, targets: { GuiObject })
	local odds = RandomCarConfig.Odds
	if not odds.Enabled then
		return
	end

	local panel = Instance.new("Frame")
	panel.Name = "Odds"
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = UDim2.new(0, -odds.Gap, 0.5, 0)
	panel.Size = UDim2.fromOffset(odds.Width, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	-- 2026-10-04: the odds now share BuyerOfferSign's blue checker header and white inset rows.
	-- Keep the existing pixel width: a tooltip should not grow into another offer screen.
	panel.BackgroundColor3 = WHITE
	panel.BackgroundTransparency = 0
	panel.Visible = false
	panel.ZIndex = 20
	panel.Parent = slide
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = panel
	local colourRamp = Instance.new("UIGradient")
	colourRamp.Rotation = 90
	colourRamp.Color = ColorSequence.new(Color3.fromRGB(33, 222, 255), Color3.fromRGB(12, 91, 235))
	colourRamp.Parent = panel
	local rim = Instance.new("UIStroke")
	rim.Color = Color3.fromRGB(82, 241, 255)
	rim.Thickness = 2
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = panel
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 4)
	list.Parent = panel

	-- The checker cells live inside the header so UIListLayout only lays out the header and odds.
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.LayoutOrder = 0
	header.Size = UDim2.new(1, 0, 0, odds.RowHeight + 8)
	header.BackgroundTransparency = 1
	header.ClipsDescendants = true
	header.ZIndex = 21
	header.Parent = panel
	for row = 0, 1 do
		for column = 0, 9 do
			if (row + column) % 2 == 0 then
				local cell = Instance.new("Frame")
				cell.Name = "Check"
				cell.Position = UDim2.fromScale(column / 10, row / 2)
				cell.Size = UDim2.fromScale(0.1, 0.5)
				cell.BackgroundColor3 = WHITE
				cell.BackgroundTransparency = 0.88
				cell.BorderSizePixel = 0
				cell.ZIndex = 21
				cell.Parent = header
			end
		end
	end
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.LayoutOrder = 0
	title.Position = UDim2.fromScale(0.04, 0.08)
	title.Size = UDim2.fromScale(0.92, 0.84)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = WHITE
	title.Text = oneLine(odds.Title)
	title.ZIndex = 22
	outline(title)
	title.Parent = header

	--- The `?` that pins it open. Top-right corner of the card, over everything the card draws.
	local info = Instance.new("TextButton")
	info.Name = "OddsInfo"
	info.AnchorPoint = Vector2.new(0.5, 0.5)
	info.Position = UDim2.fromScale(0.9, 0.09)
	info.Size = UDim2.fromScale(0.13, 0.13)
	info.SizeConstraint = Enum.SizeConstraint.RelativeXX
	info.BackgroundColor3 = Color3.fromRGB(12, 126, 244)
	info.Font = Enum.Font.FredokaOne
	info.TextScaled = true
	info.TextColor3 = WHITE
	info.Text = odds.InfoText
	info.AutoButtonColor = true
	info.ZIndex = 20
	info.Parent = corner
	local infoCorner = Instance.new("UICorner")
	infoCorner.CornerRadius = UDim.new(0.5, 0)
	infoCorner.Parent = info
	local infoRim = Instance.new("UIStroke")
	infoRim.Color = Color3.fromRGB(82, 241, 255)
	infoRim.Thickness = 2
	infoRim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	infoRim.Parent = info

	self:_wireOdds(panel, info, targets)
end

--[[ The kit's chances (2026-10-06): the template's tooltip and `?`, wired exactly as the drawn ones.
	`_paintOdds` fills `main` from `row`, a hidden `Rarity` / `Chance` pair. ]]
function RandomCarController._bindKitOdds(self, panel: GuiObject, info: GuiButton, main: Instance, row: Instance, targets: { GuiObject })
	if not RandomCarConfig.Odds.Enabled then
		panel:Destroy()
		info:Destroy()
		return
	end
	local header = panel:FindFirstChild("Header")
	local title = header and header:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = oneLine(RandomCarConfig.Odds.Title)
	end
	panel.Visible = false
	self._oddsMain = main
	self._oddsRow = row
	self:_wireOdds(panel, info, targets)
end

--[[ Hover and pin, shared by both tooltips. See the header above `_buildOdds` for why hover is
	counted across every target and settled a frame late. ]]
function RandomCarController._wireOdds(self, panel: GuiObject, info: GuiButton, targets: { GuiObject })
	local hovered: { [GuiObject]: boolean } = {}
	local function settle()
		task.defer(function()
			panel.Visible = self._oddsPinned or next(hovered) ~= nil
		end)
	end
	for _, target in { info, table.unpack(targets) } do
		target.MouseEnter:Connect(function()
			hovered[target] = true
			settle()
		end)
		target.MouseLeave:Connect(function()
			hovered[target] = nil
			settle()
		end)
	end
	info.Activated:Connect(function()
		self._oddsPinned = not self._oddsPinned
		settle()
	end)

	self._odds = panel
	self._oddsHovered = hovered
end

--- Refill the rows for the world the player is in now. Cheap: five rows at most, once per appearance.
function RandomCarController._paintOdds(self)
	local panel = self._odds
	if not panel then
		return
	end
	if self._oddsRow then
		self:_paintKitOdds()
		return
	end
	for _, child in panel:GetChildren() do
		if child:IsA("Frame") and child.Name == "Row" then
			child:Destroy()
		end
	end
	local odds = RandomCarConfig.Odds
	for index, row in RandomCarConfig.oddsFor(LocalPlayer:GetAttribute(WorldConfig.WorldAttribute)) do
		local line = Instance.new("Frame")
		line.Name = "Row"
		line.LayoutOrder = index
		line.Size = UDim2.new(1, 0, 0, odds.RowHeight)
		line.BackgroundColor3 = WHITE
		line.BackgroundTransparency = 0
		line.BorderSizePixel = 0
		line.ZIndex = 21
		line.Parent = panel
		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 5)
		rowCorner.Parent = line
		local rowRim = Instance.new("UIStroke")
		rowRim.Color = Color3.fromRGB(5, 25, 43)
		rowRim.Thickness = 1
		rowRim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rowRim.Parent = line

		local colour = CarRarity.colourOf(row.Band)
		local swatch = Instance.new("Frame")
		swatch.AnchorPoint = Vector2.new(0, 0.5)
		swatch.Position = UDim2.fromScale(0.035, 0.5)
		swatch.Size = UDim2.fromScale(0.55, 0.55)
		swatch.SizeConstraint = Enum.SizeConstraint.RelativeYY
		swatch.BackgroundColor3 = colour
		swatch.ZIndex = 22
		swatch.Parent = line
		local swatchCorner = Instance.new("UICorner")
		swatchCorner.CornerRadius = UDim.new(0.5, 0)
		swatchCorner.Parent = swatch

		local name = Instance.new("TextLabel")
		name.Position = UDim2.fromScale(0.14, 0.12)
		name.Size = UDim2.fromScale(0.54, 0.76)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.FredokaOne
		name.TextScaled = true
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = colour
		name.Text = oneLine(string.upper(row.Rarity))
		name.ZIndex = 22
		outline(name)
		name.Parent = line

		local chance = Instance.new("TextLabel")
		chance.AnchorPoint = Vector2.new(1, 0)
		chance.Position = UDim2.fromScale(0.96, 0.12)
		chance.Size = UDim2.fromScale(0.26, 0.76)
		chance.BackgroundTransparency = 1
		chance.Font = Enum.Font.FredokaOne
		chance.TextScaled = true
		chance.TextXAlignment = Enum.TextXAlignment.Right
		chance.TextColor3 = Color3.fromRGB(5, 25, 43)
		chance.Text = RandomCarConfig.formatChance(row.Chance)
		chance.ZIndex = 22
		chance.Parent = line
	end
end

--- The same rows on the kit's tooltip: the rarity in its band's ramp, the chance in plain kit type.
function RandomCarController._paintKitOdds(self)
	local main = self._oddsMain
	for _, child in main:GetChildren() do
		if child.Name == "Row" then
			child:Destroy()
		end
	end
	for index, row in RandomCarConfig.oddsFor(LocalPlayer:GetAttribute(WorldConfig.WorldAttribute)) do
		local line = self._oddsRow:Clone()
		line.Name = "Row"
		line.LayoutOrder = index
		local rarity = line:FindFirstChild("Rarity")
		local tint = rarity and rarity:FindFirstChild("Tint")
		local chance = line:FindFirstChild("Chance")
		if rarity and rarity:IsA("TextLabel") then
			rarity.Text = oneLine(row.Rarity)
		end
		if tint and tint:IsA("UIGradient") then
			tint.Color = rarityRamp(CarRarity.colourOf(row.Band))
		end
		if chance and chance:IsA("TextLabel") then
			chance.Text = RandomCarConfig.formatChance(row.Chance)
		end
		line.Visible = true
		line.Parent = main
	end
end

--[[ Put the world's best car in the card as a silhouette.

	RE-READ RATHER THAN CACHED, because the player's world changes under this screen: they teleport,
	and the card is still advertising the ladder they left. Called on every appearance, which is at
	most once a minute and is a `CarViewport.set` — a clone of a published shell, not a load. ]]
function RandomCarController._paintTeaser(self)
	if not self._cardView then
		return
	end
	local entry = RandomCarConfig.teaserFor(LocalPlayer:GetAttribute(WorldConfig.WorldAttribute))
	if entry then
		--- `aspect` is not optional here whatever its default says: see `VIEW_ASPECT` for what a
		--- wrong one costs, which is a car sitting small in the middle of its own frame. The kit's
		--- card brings its own slot, and its own shape with it.
		CarViewport.set(self._cardView, entry.Name, { silhouette = true, aspect = self._cardViewAspect or VIEW_ASPECT })
	else
		CarViewport.clear(self._cardView)
	end
end

--[[ What the card's price line says. Two states and the difference between them is the whole
	banked-pull bargain: a player holding one is not being sold anything, so the PRICE IS GONE rather
	than greyed. A struck-through number on something they have already paid for is the one thing
	here that could read as a double charge, and `OfflineConfig.BoostOwnedText` makes the identical
	split. ]]
function RandomCarController._paintCard(self)
	if self._cardFaces then
		self:_paintCardFaces()
		return
	end
	if not self._cardPrice then
		return
	end
	if self._pulls > 1 then
		self._cardPrice.Text = oneLine(string.format(RandomCarConfig.CardOpenFormat, self._pulls))
	elseif self._pulls == 1 then
		self._cardPrice.Text = oneLine(RandomCarConfig.CardOpenText)
	elseif not self._sellable then
		self._cardPrice.Text = oneLine(RandomCarConfig.UnavailableText)
	else
		self._cardPrice.Text = oneLine(string.format(RandomCarConfig.CardBuyFormat, RandomCarConfig.Price))
	end
end

--[[ The same four states on the kit's card, where each is a FACE rather than a string.

	A banked pull is the kit's green, because nothing is being sold; the price is the kit's orange
	Robux face with the kit's own Robux glyph (`CardBuyFormat` says "R$" for the shipping card, which
	has no glyph to draw); a product that cannot roll is the kit's spent grey. Exactly one shows. ]]
function RandomCarController._paintCardFaces(self)
	local faces = self._cardFaces
	local face, text
	if self._pulls > 1 then
		face, text = faces.open, string.format(RandomCarConfig.CardOpenFormat, self._pulls)
	elseif self._pulls == 1 then
		face, text = faces.open, RandomCarConfig.CardOpenText
	elseif not self._sellable then
		face, text = faces.disabled, RandomCarConfig.UnavailableText
	else
		face, text = faces.buy, ROBUX .. tostring(RandomCarConfig.Price)
	end
	for _, candidate in faces do
		candidate.Visible = candidate == face
	end
	caption(face, oneLine(text))
end

--[[ The press. It sends NOTHING but the fact of itself — see `RandomCarService`'s header on why the
	client is trusted with the press and with no other part of this transaction.

	The card is not locked behind it. There is nothing to lock: a second press while a pull is being
	rolled is refused by the server's own `_rolling` latch, and a second press while Roblox's modal
	is open cannot happen because the modal has the input. Locking would only strand the card on the
	one path where the answer never comes back. ]]
function RandomCarController._press(self)
	if not self._sellable then
		return
	end
	self:getRemoteEvent("RandomCarBuy"):Fire()
end

-- === Sliding ================================================================

function RandomCarController._slideIn(self)
	if self._shown or not self._slide then
		return
	end
	self._shown = true
	--- A press that took the card off screen leaves the dip mid-tween; it comes back at full size.
	if self._cardScale then
		self._cardScale.Scale = 1
	end
	self:_paintTeaser()
	self:_paintCard()
	self:_paintOdds()
	if self._cardGui then
		self._cardGui.Enabled = true
	end

	if self._tween then
		self._tween:Cancel()
	end
	if RandomCarConfig.Card.SlideSeconds <= 0 then
		self._slide.Position = HOME_POS
		return
	end
	self._slide.Position = OFF_POS
	self._tween = TweenService:Create(self._slide, SLIDE_IN, { Position = HOME_POS })
	self._tween:Play()
end

--[[ Out, then hidden — never hidden first. The `Completed` guard is NeedohEscape's and is not
	decoration: a cancelled tween fires `Completed` with a non-`Completed` state, and disabling the
	ScreenGui on that path would blink the card out mid-slide the first time the cadence and a race
	beat land on the same frame. ]]
function RandomCarController._slideOut(self)
	if not self._shown or not self._slide then
		return
	end
	self._shown = false
	--- The tooltip goes with the card, and a pin does not outlive the appearance it was made on.
	self._oddsPinned = false
	if self._odds then
		self._odds.Visible = false
		table.clear(self._oddsHovered)
	end

	if self._tween then
		self._tween:Cancel()
	end
	if RandomCarConfig.Card.SlideSeconds <= 0 then
		self._slide.Position = OFF_POS
		if self._cardGui then
			self._cardGui.Enabled = false
		end
		return
	end

	local tween = TweenService:Create(self._slide, SLIDE_OUT, { Position = OFF_POS })
	self._tween = tween
	tween.Completed:Once(function(state)
		if self._tween ~= tween or state ~= Enum.PlaybackState.Completed then
			return
		end
		self._tween = nil
		if self._cardGui and not self._shown then
			self._cardGui.Enabled = false
		end
	end)
	tween:Play()
end

--[[ The show/hide cycle. One Heartbeat and one accumulator rather than a chain of `task.delay`s,
	because the cadence has to be interruptible: a race starting has to be able to take the card off
	screen immediately and put the clock back to the start of a hidden phase, and a pending
	`task.delay` cannot be told that. ]]
function RandomCarController._tick(self, dt: number)
	if not self._sellable then
		return
	end

	--[[ Suppressed: in a race, or the reveal is up. Both hide it and neither advances the clock, so
		the card does not come back the instant a race ends having "waited" through it. ]]
	if self._suppressed or self._revealOpen then
		if self._shown then
			self:_slideOut()
		end
		self._timeLeft = RandomCarConfig.Card.HideSeconds
		return
	end

	self._timeLeft -= dt
	if self._timeLeft > 0 then
		return
	end

	if self._shown then
		self:_slideOut()
		self._timeLeft = RandomCarConfig.Card.HideSeconds
	else
		self:_slideIn()
		self._timeLeft = RandomCarConfig.Card.ShowSeconds
	end
end

-- === The reveal =============================================================

--[[ The payoff panel. Built once, alongside the card, and shown by `_reveal`.

	It is the kit's own page chassis whole — panel, green cap, `Close`, a pill — which is what
	`OfflineController` does and what `UIAssets.Page` says green is for. See the header on why the
	pages behind it are closed on the way up rather than left open. ]]
function RandomCarController._buildReveal(self)
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "RandomCarReveal"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	--- Alongside the welcome-back screen's 998: under the respawn screen and the race fade, above
	--- everything the lobby draws. The two can never be up together — one opens on join only.
	gui.DisplayOrder = 998
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = playerGui

	--- `Active` is what makes this modal: without it the HUD's Play button is clickable straight
	--- through the dim, and a player who pressed it would start a race over their own reveal.
	local scrim = Instance.new("Frame")
	scrim.Name = "Scrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = SCRIM_COLOR
	scrim.BackgroundTransparency = 0.4
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
	slice(panel, UIAssets.Size.Panel, UIAssets.Slice.Panel)
	panel.ZIndex = 1
	panel.Parent = scrim

	local panelAspect = Instance.new("UIAspectRatioConstraint")
	panelAspect.AspectRatio = UIAssets.Size.Panel.X / UIAssets.Size.Panel.Y
	panelAspect.Parent = panel

	local bar = Instance.new("ImageLabel")
	bar.Name = "TitleBar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.fromScale(0.5, -0.055)
	bar.Size = UDim2.fromScale(0.98, 0.155)
	bar.BackgroundTransparency = 1
	bar.Image = UIAssets.url(UIAssets.Page.TitleBar.Green)
	--- Stretch: the cap's alpha is a plain rectangle, so there is no corner for a slice to protect.
	bar.ScaleType = Enum.ScaleType.Stretch
	bar.ZIndex = 4
	bar.Parent = panel

	local title = label(bar, "Title", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.7, 0.62), RandomCarConfig.RevealTitle)
	title.ZIndex = 5

	--- Behind the car, and the reason this screen exists at all — it is what turns a car being added
	--- to a list into a car being WON.
	--[[ Sized to overhang the panel and stop there. It was 1.25 x 1.9 for one build and the rays ran
		off the top and bottom of the SCREEN — at that size the burst stops being light behind a
		panel and becomes the background, which drowns the scrim the modal is relying on. Just over
		the panel's own box on both axes is enough for the rays to read as coming from the car. ]]
	local burst = sunburst(panel, RandomCarConfig.Reveal.BurstSpeed)
	burst.Size = UDim2.fromScale(1.12, 1.42)
	burst.Position = UDim2.fromScale(0.5, 0.4)

	local view = CarViewport.new(panel, "Car")
	view.AnchorPoint = Vector2.new(0.5, 0.5)
	view.Position = UDim2.fromScale(0.5, 0.37)
	view.Size = UDim2.fromScale(0.6, 0.44)
	view.ZIndex = 2

	--- The car's name, and the rarity word under it. Blank until a roll lands; the panel is never
	--- shown without one.
	local name = label(panel, "CarName", UDim2.fromScale(0.5, 0.635), UDim2.fromScale(0.86, 0.1), "")
	name.ZIndex = 3

	local rarity, rarityCaption = pill(panel, "Rarity", "Silver", "")
	rarity.Position = UDim2.fromScale(0.5, 0.735)
	rarity.Size = UDim2.fromScale(0.3, 0.088)
	rarity.AutoButtonColor = false
	rarity.Active = false --- a label wearing a button's art; it must not take a click
	rarity.ZIndex = 3
	rarityCaption.ZIndex = 4

	--- What happened to it — parked, swapped, collected or sold. One sentence, and a different one
	--- for each; `RandomCarConfig` has them all and says why they are separate strings.
	local outcome = label(panel, "Outcome", UDim2.fromScale(0.5, 0.825), UDim2.fromScale(0.88, 0.062), "")
	outcome.TextTransparency = 0.25
	outcome.ZIndex = 3

	--[[ INSIDE the panel, not hanging below it. It sat at 1.06 for one build and landed exactly on
		the HUD's PLAY button, which is centred at the bottom of the screen: the scrim meant PLAY
		could not actually be pressed, but two buttons stacked on the same pixels is a modal that
		looks like it has a bug in it. Everything this panel says now fits between the cap and the
		bottom edge. ]]
	local close, closeCaption = pill(panel, "Done", "Green", RandomCarConfig.RevealCloseText)
	close.Position = UDim2.fromScale(0.5, 0.925)
	close.Size = UDim2.fromScale(0.38, 0.115)
	close.ZIndex = 3
	closeCaption.ZIndex = 4
	close.MouseButton1Click:Connect(function()
		self:_closeReveal()
	end)

	self._revealGui = gui
	self._revealView = view
	self._revealBurst = burst
	self._revealName = name
	self._revealRarity = rarity
	self._revealRarityCaption = rarityCaption
	self._revealOutcome = outcome
	self._revealClose = close
end

--[[ The reveal on the new UI: `Screens.RandomCarReveal` cloned over a scrim in a ScreenGui of this
	file's own. False, having built nothing, when the template is not the shape `BuildRandomCarV2`
	makes, and `start` builds the shipping panel instead.

	Sets the fields `_buildReveal` does, pointed at the kit's parts, so `_reveal` and `_closeReveal`
	run one beat for both. The differences are three fields the shipping panel has no use for:
	`_revealLockedFace` (the grey button that stands in for NICE during the lock),
	`_revealViewAspect` (the car slot's shape) and `_revealKit`, which the rarity line and the pad
	branch on. ]]
function RandomCarController._buildRevealV2(self, template: GuiObject): boolean
	local root = template:Clone()
	--- The kit's text caps are pixels for a 1080-tall screen; this keeps them in proportion above it.
	require(script.Parent.UIController.KitPage).scaleTextCaps(root)
	local card = root:FindFirstChild("Card")
	local burst = root:FindFirstChild("Burst")
	local slot = card and card:FindFirstChild("Car")
	local rarity = card and card:FindFirstChild("Rarity")
	local name = card and card:FindFirstChild("Title")
	local outcome = card and card:FindFirstChild("Outcome")
	local btns = card and card:FindFirstChild("Btns")
	local nice = btns and btns:FindFirstChild("NiceBtn")
	local locked = btns and btns:FindFirstChild("DisabledBtn")
	local constraint = root:FindFirstChildOfClass("UIAspectRatioConstraint")
	if
		not (
			card
			and burst
			and slot
			and slot:IsA("GuiObject")
			and rarity
			and rarity:IsA("TextLabel")
			and name
			and name:IsA("TextLabel")
			and outcome
			and outcome:IsA("TextLabel")
			and nice
			and nice:IsA("GuiButton")
			and locked
			and locked:IsA("GuiObject")
			and constraint
		)
	then
		warn("[RandomCarController] Screens.RandomCarReveal is not the shape BuildRandomCarV2 makes; using the old reveal. Re-run the command.")
		root:Destroy()
		return false
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "RandomCarReveal"
	gui.ResetOnSpawn = false
	--- The shipping reveal's choice, so the dim covers the topbar too. See the header.
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 998
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	--- `_buildReveal`'s scrim, for its reason: `Active` is what makes this modal.
	local scrim = Instance.new("Frame")
	scrim.Name = "Scrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = SCRIM_COLOR
	scrim.BackgroundTransparency = 0.4
	scrim.BorderSizePixel = 0
	scrim.Active = true
	scrim.Parent = gui

	root.Visible = true
	root.Parent = scrim

	--- The pop every V2 page and Phase 4 modal opens with. See `_reveal`.
	local scale = Instance.new("UIScale")
	scale.Name = "OpenScale"
	scale.Parent = root

	local heading = root:FindFirstChild("Heading")
	if heading and heading:IsA("TextLabel") then
		heading.Text = oneLine(RandomCarConfig.RevealTitle)
	end

	local view = CarViewport.new(slot :: GuiObject, "Car", faceColourAt(card, slot.Position.Y.Scale))
	view.AnchorPoint = Vector2.new(0.5, 0.5)
	view.Position = UDim2.fromScale(0.5, 0.5)
	view.Size = UDim2.fromScale(1, 1)

	burst:SetAttribute("RotateSpeed", RandomCarConfig.Reveal.BurstSpeed)
	CollectionService:AddTag(burst, "SunBurst")

	caption(nice, oneLine(RandomCarConfig.RevealCloseText))
	caption(locked, oneLine(RandomCarConfig.RevealCloseText))
	nice.Activated:Connect(function()
		self:_closeReveal()
	end)

	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	self._revealGui = gui
	self._revealView = view
	self._revealBurst = burst
	self._revealName = name
	self._revealRarity = rarity
	self._revealRarityCaption = rarity
	self._revealOutcome = outcome
	self._revealClose = nice
	self._revealLockedFace = locked
	self._revealViewAspect = slotAspect(slot :: GuiObject, constraint.AspectRatio)
	self._revealScale = scale
	self._revealKit = true
	return true
end

--[[ Lock or unlock the reveal's close.

	THE SHIPPING PANEL HIDES ITS BUTTON AND THE KIT'S SHOWS A GREY ONE, and `Active` is what
	`_closeReveal` reads on both. On the kit's card the two faces trade places, so NICE is visibly
	on its way rather than missing. ]]
function RandomCarController._lockReveal(self, locked: boolean)
	self._revealClose.Active = not locked
	self._revealClose.Visible = not locked
	if self._revealLockedFace then
		self._revealLockedFace.Visible = locked
	end
end

--[[ The resolved car's name and rarity.

	The shipping panel prints the body name and puts the rarity on a coloured pill. The kit's card
	prints what every V2 car card prints: `GarageConfig.carName` (the colour is part of the car) and
	`CarRarity`'s word in the band's colour as type, because a pill in this kit reads as a button. ]]
function RandomCarController._paintRevealCar(self, pull)
	if not self._revealKit then
		self._revealName.Text = oneLine(GarageConfig.displayName(tostring(pull.body)))

		local colour = RARITY_PILL[tostring(pull.rarity)] or "Silver"
		self._revealRarity.Image = UIAssets.url(UIAssets.Pill[colour].Idle)
		self._revealRarityCaption.Text = oneLine(string.format(RandomCarConfig.RarityFormat, tostring(pull.rarity)))
		self._revealRarity.Visible = true
		return
	end

	self._revealName.Text = GarageConfig.carName(tostring(pull.body), if type(pull.paint) == "number" then pull.paint else nil)

	local word, colour = CarRarity.labelOf(pull.body)
	if word == "" then
		word = tostring(pull.rarity or "")
	end
	self._revealRarity.Text = oneLine(string.format(RandomCarConfig.RarityFormat, word))
	local tint = self._revealRarity:FindFirstChild("Tint")
	if tint and tint:IsA("UIGradient") then
		tint.Color = rarityRamp(colour)
	end
	self._revealRarity.Visible = word ~= ""
end

--[[ A and B close the kit's reveal, both through `_closeReveal`, which refuses during the lock.

	The badge hangs off NICE, so it is hidden with it for the length of the lock and appears when the
	press would work. `GamepadConfig.ModalAttribute` goes up with the bindings, which is what drops
	any HUD highlight left out under the scrim and stops `GamepadNav` giving another one. ]]
function RandomCarController._bindRevealPad(self, on: boolean)
	if not self._revealKit then
		return
	end
	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		playerGui:SetAttribute(GamepadConfig.ModalAttribute, on or nil)
	end
	if not on then
		GamepadInput.unbind(PAD_REVEAL_CLOSE)
		return
	end
	GamepadInput.bind({
		actionName = PAD_REVEAL_CLOSE,
		keyCode = Enum.KeyCode.ButtonA,
		extraKeys = { Enum.KeyCode.ButtonB },
		callback = function()
			self:_closeReveal()
		end,
		parent = self._revealClose,
		iconPlacement = "left",
		priority = PAD_PRIORITY,
	})
end

--- The outcome sentence for one pull. Every branch `GarageService.awardCar` can return has its own,
--- because they are genuinely different news — see `RandomCarConfig`'s note on these four strings.
function RandomCarController._outcomeText(self, pull): string
	if pull.outcome == "sold" then
		return string.format(RandomCarConfig.DuplicateFormat, GarageConfig.formatCash(pull.cash or 0))
	elseif pull.outcome == "parked" then
		return string.format(RandomCarConfig.ParkedFormat, tostring(pull.bay or "?"))
	elseif pull.outcome == "upgraded" then
		return string.format(RandomCarConfig.SwappedFormat, tostring(pull.bay or "?"))
	end
	return RandomCarConfig.CollectedText
end

--[[ Play the reveal.

	THE PANEL OPENS AS A SILHOUETTE AND RESOLVES. That is the whole beat and the reason
	`CarViewport`'s `silhouette` flag is what this screen is built on: the shape on screen during the
	hold is the SAME CAR at the SAME framing it is about to become, so the resolve is a car arriving
	rather than one picture swapping for another.

	`_revealToken` is the guard against a second pull landing mid-beat — a player holding three
	presses OPEN three times, and without it the second roll's resolve would fire into the first
	roll's panel while the third was still counting. Every step below re-checks it and drops out.

	The burst accelerates INTO the resolve rather than spinning flat, so the motion peaks on the
	frame the car appears. It is written straight onto the attribute the `SunBurst` component reads,
	which is what lets one shared loop do the turning while this file only decides how fast. ]]
function RandomCarController._reveal(self, pull)
	if not self._revealGui then
		return
	end

	self._revealToken += 1
	local token = self._revealToken

	--- Everything behind it goes, so the modal is genuinely modal and the shared green cap cannot
	--- meet the Market page's — see the header.
	Dispatcher:Publish("CloseAllPages")

	self._revealOpen = true
	if self._shown then
		self:_slideOut()
	end

	--- `_revealViewAspect` is nil on the shipping panel, which is the call it always made.
	CarViewport.set(self._revealView, pull.body, { silhouette = true, aspect = self._revealViewAspect })
	self._revealName.Text = oneLine(RandomCarConfig.RollingText)
	self._revealRarity.Visible = false
	self._revealOutcome.Text = ""
	--- Locked, not hidden: a modal that can be dismissed on the frame it opens eats its own reveal
	--- to a stray click, and that player has paid 99 Robux to see nothing.
	self:_lockReveal(true)
	--[[ The kit's card swells in from nine tenths on a Back ease, which is how every V2 page and the
		other Phase 4 modals arrive. Only on the first of a run of pulls: a second roll landing on an
		open card re-rolls in place rather than bouncing the card again. ]]
	if self._revealScale and not self._revealGui.Enabled then
		self._revealScale.Scale = KIT_START_SCALE
		TweenService:Create(self._revealScale, KIT_POP, { Scale = 1 }):Play()
	end
	self._revealGui.Enabled = true
	self:_bindRevealPad(true)

	local spin = RandomCarConfig.Reveal.SpinSeconds
	local from = RandomCarConfig.Reveal.BurstSpeed
	local to = RandomCarConfig.Reveal.RevealBurstSpeed

	task.spawn(function()
		--[[ Hand-stepped rather than tweened, because what is being animated is an ATTRIBUTE that
			another loop reads — `TweenService` cannot drive one, and giving the burst a second
			writer of `Rotation` would fight the component. Quadratic in, so the wind-up is slow
			enough to notice and fast enough to feel like it is arriving somewhere. ]]
		local elapsed = 0
		while elapsed < spin do
			if self._revealToken ~= token then
				return
			end
			elapsed += RunService.RenderStepped:Wait()
			local alpha = math.clamp(elapsed / math.max(spin, 1e-3), 0, 1)
			self._revealBurst:SetAttribute("RotateSpeed", from + (to - from) * alpha * alpha)
		end

		task.wait(math.max(RandomCarConfig.Reveal.SuspenseSeconds - spin, 0))
		if self._revealToken ~= token then
			return
		end

		--- The resolve. Same body, same box, silhouette off — and the paint the server rolled, which
		--- is half of what makes it a specific car rather than a model name.
		CarViewport.set(self._revealView, pull.body, { paint = pull.paint, aspect = self._revealViewAspect })
		self:_paintRevealCar(pull)

		--- The kit's outcome line wraps (see `BuildRandomCarV2`), so its spaces stay breakable.
		local outcome = self:_outcomeText(pull)
		self._revealOutcome.Text = if self._revealKit then string.upper(outcome) else oneLine(outcome)

		--- Back down to the idle turn, so the panel settles instead of buzzing while it is read.
		self._revealBurst:SetAttribute("RotateSpeed", RandomCarConfig.Reveal.BurstSpeed)

		task.wait(RandomCarConfig.Reveal.CloseLockSeconds)
		if self._revealToken ~= token then
			return
		end
		self:_lockReveal(false)
	end)
end

function RandomCarController._closeReveal(self)
	if not (self._revealClose and self._revealClose.Active) then
		return
	end
	self._revealToken += 1
	self._revealOpen = false
	self:_bindRevealPad(false)
	if self._revealGui then
		self._revealGui.Enabled = false
	end
	CarViewport.clear(self._revealView)

	--[[ Straight back into a hidden phase rather than showing the card again. They have just seen
		the product; the one moment it is certainly not worth advertising is the second after it was
		bought. A player holding another pull will see OPEN on the next cycle. ]]
	self._timeLeft = RandomCarConfig.Card.HideSeconds
end

-- === Remotes ================================================================

RandomCarController:withRemoteEvents({
	"RandomCarBuy",
	"RandomCarReady",
	{
		RandomCarState = function(pulls: unknown, sellable: unknown)
			RandomCarController:_onState(pulls, sellable)
		end,
		RandomCarRolled = function(pull: unknown)
			if type(pull) == "table" and type(pull.body) == "string" then
				RandomCarController:_reveal(pull)
			end
		end,
		--[[ The card is a LOBBY object and comes off the screen for the length of a run — see
			`RandomCarConfig.Card.HideDuringRace`. `RaceStart` also covers a revive, which is the
			convention every other controller in this project follows (`NearMissController`'s note
			says why): the run carries on, so nothing may come back mid-race.

			`RaceAborted` and `RaceEnd` are both ends, because a run can finish either way and a card
			that only listened to one would stay hidden for the rest of the session. ]]
		RaceStart = function()
			RandomCarController:_suppress(true)
		end,
		RaceEnd = function()
			RandomCarController:_suppress(false)
		end,
		RaceAborted = function()
			RandomCarController:_suppress(false)
		end,
	},
})

--- Server's word on how many pulls are banked and whether the product exists at all. Repaints the
--- card; a `sellable` of false takes it off the screen for good this session, which is the honest
--- outcome for a product rbxsync has never created — see `RandomCarService`'s start.
function RandomCarController._onState(self, pulls: unknown, sellable: unknown)
	self._pulls = if type(pulls) == "number" then math.max(0, math.floor(pulls)) else 0
	self._sellable = sellable == true
	if not self._sellable and self._shown then
		self:_slideOut()
	end
	self:_paintCard()
end

function RandomCarController._suppress(self, on: boolean)
	if not RandomCarConfig.Card.HideDuringRace then
		return
	end
	self._suppressed = on
end

-- === The panel =============================================================
--[[ Four functions the F2 admin panel's Products tab calls, and nothing else does.

	The problem they solve is the cadence. The card is tuned to be missable — twenty-five seconds
	before its first appearance, then twelve on and forty-five off (`RandomCarConfig.Card`) — which
	is right for a player and useless for anyone trying to look at it: a change to the artwork costs
	a minute of standing in the lobby before you find out whether it worked.

	They drive the same `_slideIn` / `_slideOut` / `_press` the cadence and the button drive, so what
	the panel puts on screen is the card, not a mock of it. The clock is reset alongside, so a card
	shown by hand still goes away on its own and the cadence is never left in a state it could not
	have reached by itself. ]]

--- Put the card on screen now. False if the product does not exist in this place, in which case
--- there is nothing to show and the tab says so rather than stranding a card the tick cannot clear.
function RandomCarController.debugShowCard(self): boolean
	if not self._sellable then
		return false
	end
	self:_slideIn()
	self._timeLeft = RandomCarConfig.Card.ShowSeconds
	return true
end

--- Take it away now, and start the hidden half of the cycle from here.
function RandomCarController.debugHideCard(self)
	self:_slideOut()
	self._timeLeft = RandomCarConfig.Card.HideSeconds
end

--[[ Press the card's own button, whether or not the card is on screen.

	WHAT THIS DOES DEPENDS ON THE PROFILE AND THE PANEL SAYS SO. Holding a pull, it spends one and
	the reveal opens; holding none, the server opens the real Robux prompt — because that is what
	the button does, and a debug press that skipped the prompt would be testing the half of the
	product that was never in doubt. Grant a pull from the same tab first. ]]
function RandomCarController.debugPress(self)
	self:_press()
end

--- What the card is doing, for the tab to draw. Read every frame, so it allocates one small table.
function RandomCarController.debugState(self): { pulls: number, sellable: boolean, shown: boolean, suppressed: boolean, revealOpen: boolean, timeLeft: number }
	return {
		pulls = self._pulls or 0,
		sellable = self._sellable == true,
		shown = self._shown == true,
		suppressed = self._suppressed == true,
		revealOpen = self._revealOpen == true,
		timeLeft = self._timeLeft or 0,
	}
end

-- === Lifecycle ==============================================================

RandomCarController:withLifecycle({
	init = function(self)
		self._pulls = 0
		--- False until the server says otherwise, so a card cannot flash up for a product that turns
		--- out not to exist. `_onState` is the only thing that opens this gate.
		self._sellable = false
		self._shown = false
		self._suppressed = false
		self._revealOpen = false
		self._revealToken = 0
		self._tween = nil
		self._timeLeft = RandomCarConfig.Card.FirstDelay
	end,

	start = function(self)
		if not (RandomCarConfig.Enabled and GarageConfig.Enabled) then
			return
		end

		--[[ BUILT BEFORE THE PING, for `OfflineController`'s reason: the ping is a promise that a
			remote sent now will be heard, and both screens have to exist for that to be true. Both
			yield on PlayerGui, so a panel assembled inside the state handler would be assembled
			after the remote it was for.

			On the new UI the wait for a template is bounded (`TEMPLATE_WAIT`), so a place that never
			got `BuildRandomCarV2` costs this ping a few seconds and a warning rather than the product. ]]
		--[[ The kit's card when the new UI is on and its templates are in the place, the shipping
			screens otherwise. Decided per screen, so a place with one template and not the other still
			gets the one it has. See the header. ]]
		local offerTemplate = if UIRoot.isNewUI() then self:_template(OFFER_TEMPLATE) else nil
		if not (offerTemplate and self:_buildCardV2(offerTemplate)) then
			self:_buildCard()
		end
		local revealTemplate = if UIRoot.isNewUI() then self:_template(REVEAL_TEMPLATE) else nil
		if not (revealTemplate and self:_buildRevealV2(revealTemplate)) then
			self:_buildReveal()
		end
		self:getRemoteEvent("RandomCarReady"):Fire()

		RunService.Heartbeat:Connect(function(dt)
			self:_tick(dt)
		end)
	end,
})

return RandomCarController
