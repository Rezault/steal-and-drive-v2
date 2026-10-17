--[[
	BuildRandomCarV2: Command Runner command

	Builds BOTH random car templates on the Phase 4 shelf, `StarterGui.MainUIV2.Screens.RandomCarOffer`
	and `Screens.RandomCarReveal`, out of one Cartoony Kit card. Phase 4 of
	`docs/NewUI-Migration-Plan.md`; the running record is `docs/NewUI-Migration-Notes.md`.

	Run `BuildMainUIV2` and `PrepKitTemplate` first. Both entries are destroyed and made again on every
	run, and nothing else on the shelf is touched, so this is safe beside the other Phase 4 commands.

	Nothing draws these where they are built. `Screens` is hidden, and `RandomCarController` clones
	each into its own ScreenGui (the offer at `DisplayOrder` 5, the reveal at 998), because both sit at
	a layer `MainUIV2` does not.

	=== BOTH SCREENS ARE THE SAME CARD =======================================================

	The plan offered `PromptUI` or the `TeamSelectionUI` card. The card won, and for the reason the
	shipping screens were built the way they were: `RandomCarController` draws the offer's mystery
	shape and the reveal's finished car with THE SAME `CarViewport` call, one flag flipped, so the
	reveal is a car arriving rather than one picture swapping for another. On one card that promise
	extends to the whole screen: the card you pressed at the edge of the lobby is the card that opens
	in the middle of it and turns over.

	`PromptUI` is a sentence and two answers. It has nowhere to put a car, and a reveal is a car.

	The card is `TeamSelectionUI`'s `Template`, and specifically THE ONE THE ARTIST DREW LIVE (its
	`PlayBtn` showing, not its grey `DisabledBtn`), which is the magenta one. Picked by that rule
	rather than by child order, so a re-import that shuffles the three cannot quietly repaint both
	screens.

	    Template
	      Imagery{ Avatar, Fade }   a CanvasGroup: the picture, and a wash of the face colour under the text
	      BG{ CheckersBG }          the kit's checker pattern over the face
	      Players                   a small line in the kit's green gradient ("5/8")
	      Name                      the big line ("Team Name")
	      Btns{ PlayBtn, DisabledBtn }

	=== WHAT IS RENAMED, AND WHY ==============================================================

	  • `Name` -> `Title`. NOT OPTIONAL: `card.Name` is the Instance's own name property, so the
	    label is unreachable by dot. The Teleport build met the same trap on the same word.
	  • `Players` -> `Subtitle` on the offer and `Rarity` on the reveal, after what each says. Its
	    gradient is renamed `Tint` on the reveal, which is what the V2 car cards call the gradient a
	    rarity colour is written into (`PagesV2/StartCar`).
	  • `PlayBtn` -> `BuyBtn` on the offer and `NiceBtn` on the reveal.

	=== WHAT IS ADDED =========================================================================

	  • `Car`, an empty transparent Frame: WHERE the car goes. The controller puts a `CarViewport` in
	    it at runtime (a ViewportFrame cannot be authored with a car in it, the shells are published
	    by the server) and reads the card's aspect off the template to fit the camera.
	  • `Burst`, the sunburst (`UIAssets.Results.Sunburst`, id typed below). On the offer it is INSIDE
	    `Imagery`, so the card's own rounded CanvasGroup clips it and the rays come out from behind
	    the car without spilling over the lobby; the shipping card had no rim and had to sit further
	    off the screen edge to fit its light. On the reveal it is BEHIND the card and overhangs it,
	    because there it is the modal's backdrop. The controller tags it `SunBurst` after the clone
	    is parented, so the hidden template on the shelf is never turned.
	  • The offer gets an `OpenBtn` beside `BuyBtn`: the same button in the kit's green, for a player
	    holding a banked pull. They are not being sold anything, so that press must not wear the
	    colour the kit sells Robux in. `BuyBtn` takes the kit's orange PURCHASE face, borrowed from
	    `RobuxShopUI`, which is the face Shop V2 prices Robux on. The grey `DisabledBtn` stays for
	    "coming soon". One of the three shows at a time.
	  • The offer gets `Hit`, a transparent ImageButton the size of the card under everything the card
	    draws. The shipping card's promise was that a click anywhere on the shape buys, and that a
	    click one pixel off it still belongs to the HUD; this keeps both halves.
	  • The offer is wrapped: `RandomCarOffer{ Slide{ Press, Card } }`. The root holds the slot and
	    the aspect, `Slide` is what the cadence moves on and off screen, and `Press` is the UIScale the
	    press dip squashes. The shipping controller's reason for sliding a wrapper rather than the card
	    is unchanged: the card itself never leaves its own position.
	  • The reveal gets `Outcome`, a second small line under the car's name (parked, swapped,
	    collected or sold), cloned from the rarity line without its gradient so it reads as plain
	    type. It WRAPS, on purpose, because "PARKED IN BAY 3. YOUR WORST CAR WENT BACK" on one line
	    of a phone-sized card is about eight pixels tall.
	  • The reveal gets `Heading`, the kit's own header title (`TeamSelectionUI.Header.Title`), over
	    the card: YOUR CAR, which the shipping screen wore on its green cap.

	=== WHAT IS REMOVED =======================================================================

	The avatar picture and the other two cards. `DisabledBtn` stays on the reveal: it is the locked
	face the NICE button wears while the car is still rolling (`RandomCarConfig.Reveal.
	CloseLockSeconds`), which is the lock the shipping panel drew by hiding its button.

	=== THE CHANCES (2026-10-06; a page since 2026-10-15) =====================================

	    Card.OddsBtn        `SpinWheel.Header.OddsBtn` widened into a pill reading ODDS, in the
	                        card's top right corner, with `Page = "CarOdds"` on it

	The odds were a tooltip beside the card first (a `PromptUI` chassis, a row per car and the paint
	rows under them), which was too much type in too little room. They are a page now,
	`Pages.CarOdds`, built by `BuildCarOddsV2` and filled by `PagesV2/CarOdds`, and the button opens
	it the way every kit button opens a page: by its `Page` attribute, through `UIController`.

	THE BUTTON HAS A WORD ON IT, for Roblox's paid random items policy: the way to the odds must say
	what it is, and a bare `?` is not enough. So the kit's `?` art is dropped and the pill carries the
	word alone, in the kit's header type (`Label`).

	`RebuildOdds` (a button on this command) redoes ONLY the button on the offer that is already in
	the place, and takes away the old tooltip if it is still there.

	=== THE COPY IS PLACEHOLDER ===============================================================

	Every string written here is what a freshly built template reads like in the Explorer. The
	controller writes the real text out of `RandomCarConfig` on every show.
]]

local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local SHELF_NAME = "Screens"
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage

local OFFER_NAME = "RandomCarOffer"
local REVEAL_NAME = "RandomCarReveal"

local KIT_FRAME = "TeamSelectionUI"
local KIT_CARD = "Template"
local KIT_PURCHASE_FRAME = "RobuxShopUI" -- where the orange Robux face is borrowed from
local KIT_PURCHASE_BUTTON = "PurchaseBtn"

local NBSP = utf8.char(0xA0) -- TextScaled wraps rather than shrinks
local ROBUX = utf8.char(0xE002) -- the kit's own Robux mark; see the notes, "Shop"

--- `UIAssets.Results.Sunburst`. Typed rather than required: a Command Runner module reads the
--- config the plugin VM cached, which does not notice a Rojo sync.
local SUNBURST_IMAGE = "rbxassetid://112192466987787"

--[[ The card's shape, width over height. MEASURED OFF THE KIT, not chosen: the panel is 1.796:1,
	`Main` is 0.961 x 0.743 of it and a card is 0.303 x 0.905 of `Main`, which is 0.778:1. Both
	screens keep it, so the art is never stretched, and the controller reads it back off the
	`UIAspectRatioConstraint` written here to fit the car's camera. ]]
local CARD_ASPECT = (0.303 * 0.961 * 1.796) / (0.905 * 0.743)

-- === The offer ==============================================================

--[[ Where the offer stands, in the kit's own space (the controller's ScreenGui does not ignore the
	inset, so a notched phone held sideways keeps the card off the notch).

	PINNED TO THE RIGHT EDGE, A LITTLE ABOVE CENTRE, which is the shipping card's slot and its reason:
	the kit HUD is down the left and along the bottom, and the middle right is where the speedometer
	lives the moment a race starts. The HEIGHT binds (the aspect constraint is height-dominant), so
	the width here is a ceiling and not a size; see the shipping controller's `CARD_SIZE` on why it
	may not be zero. ]]
local OFFER_ANCHOR = Vector2.new(1, 0.5)
local OFFER_POSITION = UDim2.fromScale(0.985, 0.42)
local OFFER_SIZE = UDim2.fromScale(0.5, 0.34)

--[[ The offer card, top to bottom, in its own scale. The car takes the top half, where the artist
	put the avatar's head and shoulders. The title comes up a little off the kit's line and the
	subtitle goes UNDER it rather than over it, so the card reads RANDOM CAR, then the honesty line,
	then the price. ]]
local OFFER_CAR_Y, OFFER_CAR_SIZE = 0.285, UDim2.fromScale(0.96, 0.5)
local OFFER_TITLE_Y, OFFER_TITLE_HEIGHT = 0.6, 0.118
local OFFER_SUBTITLE_Y, OFFER_SUBTITLE_HEIGHT = 0.705, 0.07

--- The burst inside the card: centred on the car and wider than the card, so the rays leave the
--- rounded rim on every side. Pure white art, tinted here, and quiet enough not to fight the car.
local OFFER_BURST_SIZE = 1.7
local OFFER_BURST_COLOR = Color3.fromRGB(255, 240, 200)
local OFFER_BURST_TRANSPARENCY = 0.6

-- === The reveal =============================================================

--[[ Where the reveal stands, in the reveal ScreenGui's full-screen space. A transparent root the size
	of the card's slot, holding the burst behind it and the heading over it. ]]
local REVEAL_POSITION = UDim2.fromScale(0.5, 0.54)
local REVEAL_SIZE = UDim2.fromScale(0.6, 0.72)

--- The card fills the root; the heading sits over its top edge, outside it.
local REVEAL_HEADING_Y, REVEAL_HEADING_HEIGHT = -0.075, 0.1

--[[ The reveal card, top to bottom, in its own scale. The kit's button row is left exactly where the
	artist drew it (0.783 to 0.953), and the three lines of words pack above it: rarity, name, outcome. ]]
local REVEAL_CAR_Y, REVEAL_CAR_SIZE = 0.275, UDim2.fromScale(0.96, 0.47)
local REVEAL_RARITY_Y, REVEAL_RARITY_HEIGHT = 0.545, 0.07
local REVEAL_TITLE_Y, REVEAL_TITLE_HEIGHT = 0.633, 0.105
local REVEAL_OUTCOME_Y, REVEAL_OUTCOME_HEIGHT = 0.733, 0.085
local REVEAL_OUTCOME_WIDTH = 0.9

--[[ Behind the card and overhanging it, which is the shipping reveal's burst and its tint. A multiple
	of the card's WIDTH (the burst is width-led and square). 1.6 puts it at about 0.88 of the screen's
	height, the footprint the shipping reveal settled on after a bigger one ran its rays off the screen
	and drowned the scrim. The first cut, 1.25, was narrower than the card is tall and barely showed. ]]
local REVEAL_BURST_SIZE = 1.6
local REVEAL_BURST_COLOR = Color3.fromRGB(255, 214, 112)
local REVEAL_BURST_TRANSPARENCY = 0.55

-- === The chances ============================================================

local KIT_ODDS_FRAME = "SpinWheel" -- `Header.OddsBtn` is the kit's own odds button
local REF_H = 1080
--- The page the button opens: `RandomCarConfig.Odds.PageName`, built by `BuildCarOddsV2`.
local ODDS_PAGE = "CarOdds"

--[[ The pill, in 1080p pixels against the offer card at `OFFER_SIZE`'s height, in the card's top
	right corner. Wide enough for the word at the kit header's weight. ]]
local ODDS_BTN_W = 92
local ODDS_BTN_H = 36
local ODDS_BTN_INSET = 10

--[[ Draw order inside a card. The kit ships `Imagery` 1, `BG` 2 and the words 3; the car goes over
	the checker pattern and under the words, so the words move up one. ]]
local Z_CAR = 3
local Z_WORDS = 4

--- The kit template, or nil and a sentence saying which step of the path was missing.
local function findTemplate(): (Instance?, string?)
	local node: Instance = ServerStorage
	for _, step in TEMPLATE_PATH do
		local child = node:FindFirstChild(step)
		if not child then
			return nil, string.format("%s has no child `%s`.", node:GetFullName(), step)
		end
		node = child
	end
	local screen = node:FindFirstChildWhichIsA("ScreenGui")
	if not screen then
		return nil, string.format("%s holds no ScreenGui.", node:GetFullName())
	end
	local container = screen:FindFirstChild("Container")
	if not container then
		return nil, string.format("%s has no `Container` of frames.", screen:GetFullName())
	end
	return container, nil
end

--- The card the artist drew live, or the first one if none is. See the header.
local function liveCard(main: Instance): GuiObject?
	local first: GuiObject? = nil
	for _, child in main:GetChildren() do
		if child.Name ~= KIT_CARD or not child:IsA("GuiObject") then
			continue
		end
		first = first or child
		local btns = child:FindFirstChild("Btns")
		local play = btns and btns:FindFirstChild("PlayBtn")
		if play and play:IsA("GuiObject") and play.Visible then
			return child
		end
	end
	return first
end

--- Put a GuiObject centred at `y` in its parent with the given height, keeping its X.
local function band(gui: GuiObject, y: number, height: number)
	gui.AnchorPoint = Vector2.new(gui.AnchorPoint.X, 0.5)
	gui.Position = UDim2.new(gui.Position.X.Scale, gui.Position.X.Offset, y, 0)
	gui.Size = UDim2.new(gui.Size.X.Scale, gui.Size.X.Offset, height, 0)
end

local function aspect(parent: Instance, ratio: number, dominant: Enum.DominantAxis?)
	local constraint = Instance.new("UIAspectRatioConstraint")
	constraint.AspectRatio = ratio
	if dominant then
		constraint.DominantAxis = dominant
	end
	constraint.Parent = parent
end

--- The empty frame the controller puts a car in.
local function carSlot(card: GuiObject, y: number, size: UDim2): Frame
	local slot = Instance.new("Frame")
	slot.Name = "Car"
	slot.AnchorPoint = Vector2.new(0.5, 0.5)
	slot.Position = UDim2.fromScale(0.5, y)
	slot.Size = size
	slot.BackgroundTransparency = 1
	slot.BorderSizePixel = 0
	slot.ZIndex = Z_CAR
	slot.Parent = card
	return slot
end

local function burst(parent: Instance, position: UDim2, size: number, colour: Color3, transparency: number, z: number): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = "Burst"
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = position
	image.Size = UDim2.fromScale(size, size)
	image.BackgroundTransparency = 1
	image.Image = SUNBURST_IMAGE
	image.ImageColor3 = colour
	image.ImageTransparency = transparency
	image.ZIndex = z
	image.Parent = parent
	--- Square, so `Rotation` pivots without an offset. Width-led, so it is sized off the card's width.
	aspect(image, 1, Enum.DominantAxis.Width)
	return image
end

--[[ Dress one clone of the kit card with what both screens share: the picture goes, the words
	move above the car, and the big label gets a name a script can reach. Returns the big label and
	the small one, or nil and why. ]]
local function dressCard(card: GuiObject): (TextLabel?, TextLabel?, string?)
	local imagery = card:FindFirstChild("Imagery")
	local title = card:FindFirstChild("Name")
	local small = card:FindFirstChild("Players")
	local btns = card:FindFirstChild("Btns")
	if not (imagery and title and title:IsA("TextLabel") and small and small:IsA("TextLabel") and btns) then
		return nil, nil, "the card is not the shape this command expects (Imagery, Name, Players, Btns)"
	end

	local avatar = imagery:FindFirstChild("Avatar")
	if avatar then
		avatar:Destroy()
	end

	title.Name = "Title"
	--- Siblings only. A child always draws over its parent, so the button's own insides keep the
	--- artist's order without being touched.
	title.ZIndex = Z_WORDS
	small.ZIndex = Z_WORDS
	btns.ZIndex = Z_WORDS
	return title, small, nil
end

--- A button's caption, which in this kit is its `Title` child.
local function caption(button: Instance?, text: string)
	local label = button and button:FindFirstChild("Title")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

-- === The chances ============================================================

type Box = { x: number, y: number, w: number, h: number }

local function setBox(gui: GuiObject, pw: number, ph: number, box: Box)
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui.Position = UDim2.fromScale(box.x / pw, box.y / ph)
	gui.Size = UDim2.fromScale(box.w / pw, box.h / ph)
end

local function edges(left: number, top: number, right: number, bottom: number): Box
	return { x = (left + right) / 2, y = (top + bottom) / 2, w = right - left, h = bottom - top }
end

--- A kit text cap is a 1080p pixel height (`KitPage.scaleTextCaps`).
local function capTo(label: Instance, height: number)
	local cap = label:FindFirstChildOfClass("UITextSizeConstraint")
	if cap then
		cap.MaxTextSize = math.clamp(math.round(height), 1, 100)
	end
end

--[[ The ODDS button on the card. See the header's "THE CHANCES". Returns nil, or a sentence saying
	what the kit was missing; the offer is complete without it, and the controller falls back to
	drawing a tooltip of its own. ]]
local function buildOdds(container: Instance, card: GuiObject): string?
	local wheel = container:FindFirstChild(KIT_ODDS_FRAME)
	local header = wheel and wheel:FindFirstChild("Header")
	local kitButton = header and header:FindFirstChild("OddsBtn")
	if not (header and kitButton and kitButton:IsA("GuiObject")) then
		return string.format("the kit needs `%s.Header.OddsBtn`", KIT_ODDS_FRAME)
	end

	local cardH = OFFER_SIZE.Y.Scale * REF_H
	local cardW = cardH * CARD_ASPECT

	local button = kitButton:Clone() :: GuiObject
	button.Name = "OddsBtn"
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale((cardW - ODDS_BTN_INSET - ODDS_BTN_W / 2) / cardW, (ODDS_BTN_INSET + ODDS_BTN_H / 2) / cardH)
	button.Size = UDim2.fromScale(ODDS_BTN_W / cardW, ODDS_BTN_H / cardH)
	button.ZIndex = Z_WORDS + 1
	button.Visible = true
	--- `UIController` opens the page off this, the same as a HUD cell (`Components/Button`).
	button:SetAttribute("Page", ODDS_PAGE)
	button.Parent = card

	--- The word alone: a `?` beside it would be the symbol the policy rules out, said twice.
	local icon = button:FindFirstChild("Icon")
	if icon then
		icon:Destroy()
	end

	--- The word, in the kit's own header type (white over a dark ScaledSize stroke).
	local kitTitle = header:FindFirstChild("Title")
	local word = if kitTitle and kitTitle:IsA("TextLabel") then kitTitle:Clone() else Instance.new("TextLabel")
	word.Name = "Label"
	word.BackgroundTransparency = 1
	word.TextScaled = true
	word.TextWrapped = false
	word.TextXAlignment = Enum.TextXAlignment.Center
	word.TextYAlignment = Enum.TextYAlignment.Center
	word.Text = "ODDS"
	setBox(word, ODDS_BTN_W, ODDS_BTN_H, edges(ODDS_BTN_H * 0.3, ODDS_BTN_H * 0.16, ODDS_BTN_W - ODDS_BTN_H * 0.3, ODDS_BTN_H * 0.84))
	capTo(word, ODDS_BTN_H * 0.68)
	word.Parent = button
	return nil
end

--[[ The `RebuildOdds` button: swap the ODDS button on the offer already in the place for a fresh one,
	take away the tooltip an older build left on the slide, and touch nothing else. ]]
local function rebuildOdds(props: Types.Props)
	local out = props:Output()
	local screen = StarterGui:FindFirstChild(SCREEN_NAME)
	local shelf = screen and screen:FindFirstChild(SHELF_NAME)
	local offer = shelf and shelf:FindFirstChild(OFFER_NAME)
	local slide = offer and offer:FindFirstChild("Slide")
	local card = slide and slide:FindFirstChild("Card")
	if not (slide and slide:IsA("GuiObject") and card and card:IsA("GuiObject")) then
		out:error(string.format("No StarterGui.%s.%s.%s.Slide.Card. Run the full build first.", SCREEN_NAME, SHELF_NAME, OFFER_NAME))
		return
	end
	local container, why = findTemplate()
	if not container then
		out:error(string.format("The kit is not where it should be: %s", why))
		return
	end
	local oldPanel = slide:FindFirstChild("Odds")
	local oldButton = card:FindFirstChild("OddsBtn")
	if oldPanel then
		oldPanel:Destroy()
	end
	if oldButton then
		oldButton:Destroy()
	end
	local oddsWhy = buildOdds(container, card)
	if oddsWhy then
		out:warn(string.format("No ODDS button: %s. The controller draws its own.", oddsWhy))
		return
	end
	out:print(string.format("Rebuilt %s's OddsBtn (opens Pages.%s)%s.", OFFER_NAME, ODDS_PAGE, if oldPanel then ", old tooltip removed" else ""))
	local pages = screen and screen:FindFirstChild("Pages")
	if not (pages and pages:FindFirstChild(ODDS_PAGE)) then
		out:warn(string.format("There is no Pages.%s yet. Run BuildCarOddsV2 too.", ODDS_PAGE))
	end
end

return {
	Description = "Build StarterGui.MainUIV2.Screens.RandomCarOffer and Screens.RandomCarReveal from the Cartoony Kit's TeamSelectionUI card: a car slot, a sunburst, and the offer's three button faces, its ODDS button (opens Pages.CarOdds), or the reveal's rarity, name and outcome lines. Rebuilds both entries every run.",
	Tags = { "UI", "NewUI" },
	AutoRecordChanges = true,

	Arguments = {
		RebuildOdds = {
			Type = "button",
			Default = "Rebuild the odds only",
			LayoutOrder = 1,
			Description = "Replace only the offer's ODDS button (and remove the old odds tooltip), leaving the rest of the offer and the reveal as they are.",
			Run = function(props: Types.Props, _value: any)
				rebuildOdds(props)
			end,
		},
	} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		local screen = StarterGui:FindFirstChild(SCREEN_NAME)
		local shelf = screen and screen:FindFirstChild(SHELF_NAME)
		if not (shelf and shelf:IsA("GuiObject")) then
			out:error(string.format("No StarterGui.%s.%s. Run BuildMainUIV2 first.", SCREEN_NAME, SHELF_NAME))
			return
		end

		local container, why = findTemplate()
		if not container then
			out:error(string.format("The kit is not where it should be: %s", why))
			return
		end

		local kitFrame = container:FindFirstChild(KIT_FRAME)
		local kitMain = kitFrame and kitFrame:FindFirstChild("Main")
		local kitCard = kitMain and liveCard(kitMain)
		if not kitCard then
			out:error(string.format("%s has no `%s.Main.%s` card to build from.", container:GetFullName(), KIT_FRAME, KIT_CARD))
			return
		end

		local kitHeading = kitFrame:FindFirstChild("Header")
		kitHeading = kitHeading and kitHeading:FindFirstChild("Title")

		local purchase = container:FindFirstChild(KIT_PURCHASE_FRAME)
		purchase = purchase and purchase:FindFirstChild(KIT_PURCHASE_BUTTON, true)
		local purchaseFace = purchase and purchase:FindFirstChildOfClass("UIGradient")

		for _, name in { OFFER_NAME, REVEAL_NAME } do
			local existing = shelf:FindFirstChild(name)
			if existing then
				existing:Destroy()
			end
		end

		-- === The offer ==========================================================

		local offer = Instance.new("Frame")
		offer.Name = OFFER_NAME
		offer.AnchorPoint = OFFER_ANCHOR
		offer.Position = OFFER_POSITION
		offer.Size = OFFER_SIZE
		offer.BackgroundTransparency = 1
		offer.BorderSizePixel = 0
		aspect(offer, CARD_ASPECT, Enum.DominantAxis.Height)

		local slide = Instance.new("Frame")
		slide.Name = "Slide"
		slide.AnchorPoint = Vector2.new(0.5, 0.5)
		slide.Position = UDim2.fromScale(0.5, 0.5)
		slide.Size = UDim2.fromScale(1, 1)
		slide.BackgroundTransparency = 1
		slide.BorderSizePixel = 0
		slide.Parent = offer

		local press = Instance.new("UIScale")
		press.Name = "Press"
		press.Parent = slide

		local offerCard = kitCard:Clone() :: GuiObject
		offerCard.Name = "Card"
		offerCard.AnchorPoint = Vector2.new(0.5, 0.5)
		offerCard.Position = UDim2.fromScale(0.5, 0.5)
		offerCard.Size = UDim2.fromScale(1, 1)
		offerCard.Visible = true
		offerCard.Parent = slide

		local offerTitle, subtitle, badCard = dressCard(offerCard)
		if not (offerTitle and subtitle) then
			out:error(string.format("The kit's %s: %s.", KIT_FRAME, tostring(badCard)))
			offer:Destroy()
			return
		end

		offerTitle.Text = "RANDOM" .. NBSP .. "CAR"
		band(offerTitle, OFFER_TITLE_Y, OFFER_TITLE_HEIGHT)
		subtitle.Name = "Subtitle"
		subtitle.Text = "ANY" .. NBSP .. "CAR" .. NBSP .. "IN" .. NBSP .. "THIS" .. NBSP .. "WORLD"
		band(subtitle, OFFER_SUBTITLE_Y, OFFER_SUBTITLE_HEIGHT)

		carSlot(offerCard, OFFER_CAR_Y, OFFER_CAR_SIZE)

		--- Inside the rounded CanvasGroup, under the face-colour wash. See the header.
		local imagery = offerCard:FindFirstChild("Imagery")
		burst(imagery, UDim2.fromScale(0.5, OFFER_CAR_Y), OFFER_BURST_SIZE, OFFER_BURST_COLOR, OFFER_BURST_TRANSPARENCY, 0)

		local hit = Instance.new("ImageButton")
		hit.Name = "Hit"
		hit.AnchorPoint = Vector2.new(0.5, 0.5)
		hit.Position = UDim2.fromScale(0.5, 0.5)
		hit.Size = UDim2.fromScale(1, 1)
		hit.BackgroundTransparency = 1
		hit.ImageTransparency = 1
		hit.AutoButtonColor = false
		hit.ZIndex = 1
		hit.Parent = offerCard

		local offerBtns = offerCard:FindFirstChild("Btns") :: Instance
		local buy = offerBtns:FindFirstChild("PlayBtn")
		local disabled = offerBtns:FindFirstChild("DisabledBtn")
		if not (buy and disabled) then
			out:error(string.format("The kit's %s card has no `Btns.PlayBtn` and `Btns.DisabledBtn`.", KIT_FRAME))
			offer:Destroy()
			return
		end

		--- Green, before the orange goes on: `OpenBtn` is the kit's own confirm face untouched.
		local open = buy:Clone()
		open.Name = "OpenBtn"
		open.Visible = false
		open.Parent = offerBtns
		caption(open, "OPEN")

		buy.Name = "BuyBtn"
		buy.Visible = true
		caption(buy, ROBUX .. "99")
		local face = buy:FindFirstChildOfClass("UIGradient")
		if face and purchaseFace then
			face.Color = purchaseFace.Color
		else
			out:warn(string.format("No %s.%s gradient to borrow; BuyBtn keeps the green face.", KIT_PURCHASE_FRAME, KIT_PURCHASE_BUTTON))
		end

		disabled.Visible = false
		caption(disabled, "COMING" .. NBSP .. "SOON")

		local oddsWhy = buildOdds(container, offerCard)
		if oddsWhy then
			out:warn(string.format("No ODDS button: %s. The controller draws its own.", oddsWhy))
		end

		offer.Parent = shelf

		-- === The reveal =========================================================

		local reveal = Instance.new("Frame")
		reveal.Name = REVEAL_NAME
		reveal.AnchorPoint = Vector2.new(0.5, 0.5)
		reveal.Position = REVEAL_POSITION
		reveal.Size = REVEAL_SIZE
		reveal.BackgroundTransparency = 1
		reveal.BorderSizePixel = 0
		aspect(reveal, CARD_ASPECT)

		burst(reveal, UDim2.fromScale(0.5, 0.5), REVEAL_BURST_SIZE, REVEAL_BURST_COLOR, REVEAL_BURST_TRANSPARENCY, 1)

		local revealCard = kitCard:Clone() :: GuiObject
		revealCard.Name = "Card"
		revealCard.AnchorPoint = Vector2.new(0.5, 0.5)
		revealCard.Position = UDim2.fromScale(0.5, 0.5)
		revealCard.Size = UDim2.fromScale(1, 1)
		revealCard.Visible = true
		revealCard.ZIndex = 2
		revealCard.Parent = reveal

		local revealTitle, rarity = dressCard(revealCard)
		if not (revealTitle and rarity) then
			out:error(string.format("The kit's %s card changed shape between two clones.", KIT_FRAME))
			offer:Destroy()
			reveal:Destroy()
			return
		end

		carSlot(revealCard, REVEAL_CAR_Y, REVEAL_CAR_SIZE)

		rarity.Name = "Rarity"
		rarity.Text = "SUPERCAR"
		band(rarity, REVEAL_RARITY_Y, REVEAL_RARITY_HEIGHT)
		local tint = rarity:FindFirstChildOfClass("UIGradient")
		if tint then
			tint.Name = "Tint"
		end

		revealTitle.Text = "ROLLING..."
		band(revealTitle, REVEAL_TITLE_Y, REVEAL_TITLE_HEIGHT)

		--- Plain white type under the name, two lines allowed. See the header.
		local outcome = rarity:Clone()
		outcome.Name = "Outcome"
		local outcomeTint = outcome:FindFirstChild("Tint")
		if outcomeTint then
			outcomeTint:Destroy()
		end
		outcome.Text = "PARKED IN BAY 3"
		outcome.TextWrapped = true
		outcome.AnchorPoint = Vector2.new(0.5, 0.5)
		outcome.Position = UDim2.fromScale(0.5, REVEAL_OUTCOME_Y)
		outcome.Size = UDim2.fromScale(REVEAL_OUTCOME_WIDTH, REVEAL_OUTCOME_HEIGHT)
		outcome.Parent = revealCard

		local revealBtns = revealCard:FindFirstChild("Btns") :: Instance
		local nice = revealBtns:FindFirstChild("PlayBtn")
		local locked = revealBtns:FindFirstChild("DisabledBtn")
		if not (nice and locked) then
			out:error(string.format("The kit's %s card has no `Btns.PlayBtn` and `Btns.DisabledBtn`.", KIT_FRAME))
			offer:Destroy()
			reveal:Destroy()
			return
		end
		nice.Name = "NiceBtn"
		nice.Visible = false
		caption(nice, "NICE")
		locked.Visible = true
		caption(locked, "NICE")

		if kitHeading and kitHeading:IsA("TextLabel") then
			local heading = kitHeading:Clone()
			heading.Name = "Heading"
			heading.Text = "YOUR" .. NBSP .. "CAR"
			heading.AnchorPoint = Vector2.new(0.5, 0.5)
			heading.Position = UDim2.fromScale(0.5, REVEAL_HEADING_Y)
			heading.Size = UDim2.fromScale(1.4, REVEAL_HEADING_HEIGHT)
			heading.TextXAlignment = Enum.TextXAlignment.Center
			heading.ZIndex = 3
			heading.Parent = reveal
		else
			out:warn(string.format("The kit's %s has no `Header.Title`; the reveal has no heading.", KIT_FRAME))
		end

		reveal.Parent = shelf

		out:print(
			string.format(
				"Built %s.%s.%s and %s.%s from %s's live card (aspect %.3f). Offer faces: BuyBtn (%s), OpenBtn, DisabledBtn. Reveal lines: Rarity, Title, Outcome; buttons NiceBtn and DisabledBtn.",
				SCREEN_NAME,
				SHELF_NAME,
				OFFER_NAME,
				SHELF_NAME,
				REVEAL_NAME,
				KIT_FRAME,
				CARD_ASPECT,
				if purchaseFace then "the kit's orange purchase face" else "green, no purchase face found"
			)
		)

		pcall(function()
			props:SetSelection({ offer, reveal })
		end)
	end,
} :: Types.ScriptModule
