--[[
	SellPopupController  (client)
	-----------------------------
	THE QUESTION THE SELL LOT ASKS. Park a car of yours on the square, step out, and this comes up:

	         ┌─────────────────────────────┐          ┌─────────────────────────────┐
	         │ ▓▓▓▓   SELL THIS CAR?   ▓▓▓ │          │ ▓▓▓▓    ARE YOU SURE?   ▓▓▓ │
	         ├─────────────────────────────┤  starred ├─────────────────────────────┤
	         │        RED CAMARO           │  ------> │        RED CAMARO           │
	         │          $2,400             │  SELL IT │          $2,400             │
	         │      ★ THIS IS A FAVORITE   │          │      ★ THIS IS A FAVORITE   │
	         │   ( SELL IT )  ( KEEP IT )  │          │ (SELL IT-CONFIRM) (KEEP IT) │
	         └─────────────────────────────┘          └─────────────────────────────┘
	                                                     ^ red, and the red is what carries this

	IT REPLACED A HELD BUTTON on 2026-08-31, on the owner's call, and `SellConfig`'s header has the
	whole argument. Short version: the hold was a third step after a decision the player had already
	made, and it was a stock `ProximityPrompt` sitting in a lobby where every other surface is the
	artist's kit.

	=== IT KNOWS NOTHING AND DECIDES NOTHING ==================================================

	This file draws a panel and reports which of two pills was pressed. It does not know what a lot
	is, what a car is worth, whether one is standing on a pad, or what happens when somebody says
	yes. `SellController` works all of that out, hands over three strings and two callbacks, and
	`SellService` is the only thing that can actually sell anything.

	That is deliberate and it is worth keeping. The trigger — a car of yours coming to rest in the
	lot with nobody in it — is a moving target that will get fiddled with; a panel with two answers
	is not. Splitting them means the fiddling happens in one file that has no UI in it.

	SO THE OFFER IS A VALUE, NOT A LOOKUP. `offer` takes the car's NAME and PRICE already formatted
	and a flag saying whether it is starred. Nothing here reads a profile, an attribute or a config
	number about a car, which is what makes this panel testable by calling one method with a table.

	=== IT IS BUILT IN CODE OUT OF THE KIT'S OWN ART ==========================================

	Third of the project's three ways of drawing UI, after the authored pages under `UIController`
	and `ReviveController`'s plain shapes, and the same one `OfflineController` uses — which is the
	file to read alongside this one, because this panel is assembled from exactly its parts:

	  • `Page.Panel` + `Page.TitleBar.Green` — the landscape chassis. GREEN, and the choice is worth
	    a line: this is a question about MONEY and green is what this kit pays out in (the price row
	    under the cap is the same green, and the WELCOME BACK panel wears this cap for the same
	    reason). Red would read as danger, and selling a car is a thing players come here to do. The
	    caution belongs on the favourite line, where it is, and nowhere else.
	  • `Page.Close` — the kit's X, which means exactly what KEEP IT means.
	  • `Pill.Green` for SELL IT and `Pill.Silver` for KEEP IT. The safe answer is the neutral one:
	    painting it red would tell the player that keeping their own car was the dangerous choice.
	    `Pill.Red` is the SAME pill shape and is spent on one thing only — SELL IT while it is asking
	    a starred car's second question. It is the one moment on this panel where a press is about to
	    do something the player might not have meant, and spending the colour anywhere else is what
	    would stop it meaning that.
	  • `Inventory.Favorite` — the gold star off the MY CARS card, so a starred car is marked with
	    the same thing that starred it.

	Nothing new was uploaded for this screen and nothing on it is a colour somebody eyeballed.

	=== THE FOUR STATES ========================================================================

	ASKING is the left panel above. CONFIRMING is the right one and only a STARRED car has it: the
	first SELL IT does not sell, it turns the pill RED and appends CONFIRM to it, turns the title into
	a second question, and the next SELL IT goes through (`SellConfig` note 7). WORKING is a press
	that has been sent and not yet answered: both pills go dead, because between a press and a reply a
	button that still looks live is still live. REFUSED is the server saying no, held for
	`Popup.RefusalHold` so it can be read.

	THE CONFIRM'S SIGNAL IS ON THE BUTTON AND NOT ON THE TITLE, and it was the other way round for
	about an hour on 2026-08-31 until the owner named the failure: a player who presses a button and
	sees only the HEADER change reads it as the press not having registered, because nobody re-reads a
	header they have already read. So the pill they just pressed changes colour and changes words, and
	the title is what explains it once they look up.

	IT IS A COLOUR AND NOT AN OPACITY, which is the kit's own rule turned round: 80%/100% is how this
	kit says pressed on a navy surface, and it says nothing at all on a coloured pill. Dimming is also
	already taken — `_setPillsLive` uses it for "you cannot press this".

	THERE IS NO SOLD STATE, and that is the one absence worth explaining. The panel used to stand on
	SOLD over the money for a beat; it closes at once now, because the money flying out of the lot
	and into the player IS the receipt and a full-screen scrim over the first second of that flight
	is this panel standing in front of its own payoff. `Popup.RefusalHold` carries the whole
	argument.

	WORKING HAS A DEADLINE AND IT UNLOCKS RATHER THAN CLOSING (`Popup.AnswerTimeout`). Nothing was
	sold, the car is still on the pad, and the question is still worth answering — the same call
	`OfflineController` makes on its own boost timeout, and the opposite of the one it makes on a
	plain claim, which closes. It resets the confirm too: a press the server never answered is not a
	press a starred car should be able to bank.

	=== WITH THE NEW UI, THE PANEL IS AUTHORED (2026-09-16) ====================================

	With `UIRoot.isNewUI()` nothing above is built. `BuildSellCarV2` authors the panel out of the
	Cartoony Kit's `PromptUI` onto the hidden shelf `MainUIV2.Screens.SellCar`, and `_buildKit` clones
	it into this file's own ScreenGui, which keeps its name, `DisplayOrder` 997, `ResetOnSpawn` and
	`ZIndexBehavior`. `OfflineController` does the same with the same frame, and the two panels come
	out one size.

	THE STATES ARE UNCHANGED AND SO IS WHAT CARRIES THEM, only the ink differs. The kit draws a button
	as one face under a gradient, so SELL IT turns red by swapping its gradient to the `ConfirmColor`
	the template carries (the kit's own red, off its "No" button) rather than by swapping three pill
	textures. KEEP IT is the panel's own blue rather than red, for the reason in the silver pill note
	above. A dead pair fades whole, face, rim, sheen and caption, as the V2 index rail dims a band. The
	price row keeps one writer and swaps a `Tint` gradient where the old row swaps a text colour.

	THE INSET IS IGNORED, as on the old panel, so the dim covers the topbar strip and the panel centres
	on the whole screen: a few percent larger than the same frame inside `MainUIV2`, which is the
	right way round for a modal.

	If the template is missing, the old panel is built instead and a warning names the command to run.

	HOUSE RULE: no wiki-style double-bracket links in these comments — the closing pair ends the
	block comment early and the parse error points at the wrong line.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local GamepadConfig = require(ReplicatedStorage.shared.Configs.GamepadConfig)
--[[ NO `GarageConfig` HERE, and it is worth a line because it was required for one call until the
	SOLD state came out: this panel never formats money. The price arrives on the offer as a STRING
	that `SellController` has already run through `formatCash`, which is the header's "the offer is a
	value, not a lookup" — a panel that could format a number is a panel that could format a
	different one from the sign hanging over the same car. ]]
local SellConfig = require(ReplicatedStorage.shared.Configs.SellConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local GamepadInput = require(ReplicatedStorage.shared.Modules.GamepadInput)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)

local SellPopupController = Shard.new("SellPopupController")

-- === Look & feel ============================================================
--[[ Every number is a fraction — of the screen for the panel, of the PANEL for everything inside it
	— so the layout is one object that scales rather than a set of positions that agree at 1080p.
	`OfflineController`, `RaceUIController` and `ReviveController` are all written this way.

	THEY LIVE HERE AND NOT IN `SellConfig` ON PURPOSE. A fraction of a panel means nothing without
	the panel, and a layout split across two files is one where nobody can see what moving a number
	does. `SellConfig.Popup` carries the BEHAVIOUR — reach, settle, timeouts — which is the half a
	designer retunes without opening this file. ]]

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)
local WHITE = Color3.fromRGB(255, 255, 255)
--- The kit's payout green, the same one the price sign over the lot prints in and the same one the
--- results screen pays a getaway out in. One number, three screens.
local CASH_GREEN = Color3.fromRGB(126, 217, 87)
--[[ ...and the two the sign over the lot already owns, READ rather than re-typed: the kit's caution
	amber for the favourite line and its refusal red for a no. Both are in `SellConfig.Bubble.Colors`
	because that is where they were first needed, and both are now the FEATURE's — the sign and this
	panel must never say the same thing in two different colours, and the cheapest way to guarantee
	that is for there to be one of each. ]]
local WARN_AMBER = SellConfig.Bubble.Colors.Warning
local REFUSED_RED = SellConfig.Bubble.Colors.Refused

local SCRIM_COLOR = Color3.fromRGB(6, 8, 12)
--[[ Lighter than the respawn screen's and the same as WELCOME BACK's, and the reason is what is
	behind it: a wreck screen dims a road nobody is driving any more, this one dims a lot with the
	player's own car standing on it, and that car is what the question is about. Dim it out of sight
	and the panel is a sentence about nothing. ]]
local SCRIM_REST = 0.45

--[[ The panel, as a box the aspect constraint FITS INSIDE. Both numbers are maximums, not the size.
	Smaller than WELCOME BACK's 0.86 x 0.46 because it carries four rows to that screen's six and a
	panel sized past its contents reads as one that failed to load.

	A REAL BOX ON BOTH AXES, never a zero: `UIAspectRatioConstraint` defaults to FitWithinMaxSize,
	which collapses a zero-width element to 0x0 rather than solving for the aspect. ]]
local PANEL_BOX = UDim2.fromScale(0.78, 0.42)

--- Fractions of the PANEL. The cap is measured out of the PSD rather than chosen: 1788 x 138
--- against a 1798 x 1132 panel, so 99.4% of the width and 12.2% of the height, flush at the top.
local BAR_SIZE = UDim2.fromScale(0.994, 0.122)
local BAR_Y = 0.005

local CLOSE_BOX = UDim2.fromScale(0.09, 0.15) -- fitted square; see PANEL_BOX on why neither is 0
local CLOSE_POS = UDim2.fromScale(0.955, 0.066)

--[[ The four rows, top to bottom, and the spacing between them is the whole layout.

	THE STAR ROW HOLDS ITS PLACE WHEN THERE IS NO STAR. A car nobody has favourited leaves a gap
	between the price and the pills rather than sliding them up, because the panel is a question with
	a fixed shape and a player who sells two cars in a row should not watch the buttons move under
	their cursor between them. ]]
local NAME_Y = 0.295
local PRICE_Y = 0.465
local STAR_Y = 0.635
--- Measured on screen rather than picked: at 0.80 the pills left a band of bare panel under them
--- half again as deep as the one over the title, which reads as a panel that failed to finish
--- loading. 0.82 puts the gap under the pills at about the gap over the car's name.
local BUTTON_Y = 0.82

--[[ The pair of pills, at the art's own 463x119. Both boxes are MAXIMUMS the aspect constraint fits
	inside and in both the WIDTH is what wins; the height entry is only there to keep the box off
	zero. 0.42 apiece with a 0.036 gutter leaves 0.062 of the panel clear on each side, which is the
	margin the pad badges hanging under the pills need. Lifted from `OfflineController`, which is the
	same row of the same two shapes. ]]
local PAIR_BOX = UDim2.fromScale(0.42, 0.19)
local PAIR_LEFT_X = 0.272
local PAIR_RIGHT_X = 0.728

--- How far each answer swells under a cursor, read by `UIController/Components/Button` off the
--- `Scale` attribute. Both under the 1.05 default, because the art already reacts on its own — the
--- pill's face drops 6px in the image and the X swaps texture — so the nudge is the second half of
--- a reaction rather than the whole of it.
local PILL_HOVER_SCALE = 1.03
local CLOSE_HOVER_SCALE = 1.08

local RAISE_TIME = 0.28
local DROP_TIME = 0.18

--[[ A and B, the same two answers on the same two buttons as the respawn screen and WELCOME BACK. A
	player who has learned either of those screens has learned this one.

	NO SELECTION IS SEEDED, for their reason exactly: there are two answers, neither moves, and
	driving a highlight onto one of them first is a step with nothing to gain. The panel raises
	`GamepadConfig.ModalAttribute` while it is up so the navigation component stands down — B is its
	back key the rest of the time, and both of them owning one button is the bug that attribute
	exists to prevent. ]]
local PAD_YES = "SellPopupYes"
local PAD_NO = "SellPopupNo"
local PAD_PRIORITY = Enum.ContextActionPriority.High.Value + 600

--- Centred under the pill it names, in that button's own scale space, at 0.8 of the standard size:
--- a label on something already legible, not the thing being looked at. Same placement and same
--- number as WELCOME BACK's, which is the same row of the same two shapes.
local PAD_BADGE_POS = UDim2.fromScale(0.5, 1.15)
local PAD_BADGE_ANCHOR = Vector2.new(0.5, 0)
local PAD_BADGE_SIZE = GamepadConfig.Icon.Size * 0.8

-- Non-breaking, because `TextScaled` would sooner break a caption onto a second line than pick a
-- smaller font. Every space in a one-line label on this panel is this one.
local NBSP = utf8.char(0xA0)

local function oneLine(text: string): string
	return (string.gsub(string.upper(text), "%s+", NBSP))
end

-- === The kit panel (new UI) =================================================
--[[ The authored panel's names and the few numbers that are about THIS screen rather than the art.
	Every name is one `BuildSellCarV2` writes; its header says what each was cut from. ]]

local KIT_SHELF = "Screens"
local KIT_TEMPLATE = "SellCar"
--- How long each step of the path to the template is waited for. The panel is built on the first
--- offer, long after the UI has landed, so this is only ever the backstop for a place without it.
local KIT_WAIT = 5

--- The pop every V2 page opens and closes with (`UIController.openPage`), so the two arrive alike.
local KIT_START_SCALE = 0.9
local KIT_OPEN = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local KIT_CLOSE = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

--[[ How far a dead pair fades, the V2 index rail's dim. The old panel's 0.55 was image transparency on
	a pill; on the kit it is the whole button, which is the kit's state language (opacity). ]]
local KIT_DEAD_FADE = 0.55

--- Where the pad badges hang: on each pill's top left corner, for `OfflineController`'s reason (the
--- kit's buttons leave less than half a badge of body under them).
local KIT_BADGE_POS = UDim2.fromScale(0, 0)
local KIT_BADGE_ANCHOR = Vector2.new(0.3, 0.3)

--[[ Fade one kit button as a whole: its gradient face, its caption and that caption's outline, the two
	rim strokes and the sheen. Fading the face alone leaves a bright white rim round a pale button,
	which reads as a different button rather than the same one stepping back (`PagesV2/Index` found
	that first). ]]
local function fadeKitButton(button: GuiObject, alpha: number)
	button.BackgroundTransparency = alpha
	local title = button:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.TextTransparency = alpha
		local outline = title:FindFirstChildOfClass("UIStroke")
		if outline then
			outline.Transparency = alpha
		end
	end
	local container = button:FindFirstChild("Container")
	if container then
		for _, stroke in container:GetChildren() do
			if stroke:IsA("UIStroke") then
				stroke.Transparency = alpha
			end
		end
	end
	local sheen = button:FindFirstChild("BG")
	if sheen and sheen:IsA("CanvasGroup") then
		sheen.GroupTransparency = alpha
	end
end

-- === Building ===============================================================

--- 9-slice an ImageLabel/ImageButton from the recorded texture size and inset. Both come out of
--- `UIAssets`, which is measured against what Roblox STORED rather than against the PSD.
local function slice(image: ImageLabel | ImageButton, size: Vector2, inset: number)
	image.ScaleType = Enum.ScaleType.Slice
	image.SliceCenter = Rect.new(inset, inset, size.X - inset, size.Y - inset)
end

--[[ One pill and its caption. Both answers are this shape and this state language, so the difference
	between them is two arguments.

	STRETCHED, NOT SLICED — the aspect constraint pins this to the art's own 3.89:1, so the box only
	ever shrinks uniformly and `Stretch` reproduces the drawing exactly. Slicing pins the corner curve
	at texture pixels while the rest of the pill shrinks and the button comes out a fat lozenge;
	`UIAssets.Slice.Pill` has that arithmetic and the warning that goes with it.

	The caption sits slightly ABOVE centre because the pressed art drops the face 6px and loses 6px of
	height: text centred in the box would stay put while the face moved out from under it. ]]
function SellPopupController._pill(_self, parent: GuiObject, name: string, colours, x: number, text: string): (ImageButton, TextLabel)
	local button = Instance.new("ImageButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(x, BUTTON_Y)
	button.Size = PAIR_BOX
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
	--[[ Wide enough for SELL IT - CONFIRM, which is the longest string either pill ever carries. It
		costs the short labels nothing: `TextScaled` fits to the tighter axis and for those the HEIGHT is
		what binds, so SELL IT draws at exactly the size it did at 0.76. Still inside the pill's flat
		middle band, which is the constraint that actually matters — `OfflineController` runs its own
		long caption at 0.82 for the same reason. ]]
	caption.Size = UDim2.fromScale(0.84, 0.42)
	caption.BackgroundTransparency = 1
	caption.FontFace = FONT
	caption.Text = oneLine(text)
	caption.TextColor3 = WHITE
	caption.TextTransparency = 1
	caption.TextScaled = true
	caption.Parent = button

	return button, caption
end

--[[ The favourite line: the gold star and the warning beside it, laid out as a ROW rather than as
	two positioned children.

	A `UIListLayout` AND NOT TWO FRACTIONS, which is the one piece of this panel that is not simply
	copied from WELCOME BACK. The star has to sit against the text, and where the text starts depends
	on how wide `TextScaled` decided to draw it — which nothing can know in advance and which changes
	the first time this string is translated. A horizontal list centres the pair as a group and the
	gap stays the gap whatever the words do. ]]
function SellPopupController._starRow(_self, parent: GuiObject): (Frame, ImageLabel, TextLabel)
	local row = Instance.new("Frame")
	row.Name = "Favorite"
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, STAR_Y)
	row.Size = UDim2.fromScale(0.86, 0.085)
	row.BackgroundTransparency = 1
	row.Visible = false
	row.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.015, 0)
	layout.Parent = row

	local star = Instance.new("ImageLabel")
	star.Name = "Star"
	star.LayoutOrder = 1
	--- A real width, not a zero: the aspect constraint below fits INSIDE this box, and a zero
	--- collapses to 0x0 rather than solving for the aspect.
	star.Size = UDim2.fromScale(0.085, 1)
	star.BackgroundTransparency = 1
	star.Image = UIAssets.url(UIAssets.Inventory.Favorite)
	star.ImageTransparency = 1
	star.ScaleType = Enum.ScaleType.Fit
	star.Parent = row

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = UIAssets.DealerSize.Badge.X / UIAssets.DealerSize.Badge.Y
	aspect.Parent = star

	local label = Instance.new("TextLabel")
	label.Name = "Line"
	label.LayoutOrder = 2
	label.Size = UDim2.fromScale(0.62, 1)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.Text = oneLine(SellConfig.Lines.Favorite)
	label.TextColor3 = WARN_AMBER
	label.TextTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextScaled = true
	label.Parent = row

	return row, star, label
end

function SellPopupController._build(self)
	--- The new UI's panel, when there is one to clone. A missing template falls through to the panel
	--- below rather than leaving the lot with no question.
	if UIRoot.isNewUI() and self:_buildKit() then
		return
	end

	local lines = SellConfig.PopupLines

	local gui = Instance.new("ScreenGui")
	gui.Name = "SellCar"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	--[[ Under WELCOME BACK's 998, the respawn screen's 999 and the race fade's 1000. It cannot
		collide with any of them — this only opens on foot, in the lobby, standing on the sell pad —
		and ordering it below them makes "a race beat always wins" true by construction. ]]
	gui.DisplayOrder = 997
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	--[[ `Active` is what makes this modal. A Frame does not swallow input by default, so without it
		the HUD's Play button is still clickable straight through the dim — and a player who pressed it
		would start a race with a question about their car sitting over the road. ]]
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
	title.Text = oneLine(lines.Title)
	title.TextColor3 = WHITE
	title.TextTransparency = 1
	title.TextScaled = true
	title.Parent = bar

	--[[ The punch when the title becomes a different question. It is the ONLY reaction the confirm
		state has beyond the words, and it is on a `UIScale` rather than on Size so the cap's layout
		stays the one source of truth for where this sits.

		WHY A PUNCH AND NOT A COLOUR. The kit has a red title cap and swapping to it would certainly be
		noticed — and would say REFUSED, which is the one thing this state is not: nothing has gone
		wrong and the next press still sells the car. A movement says "this changed" without saying
		anything about what changed to. ]]
	local titleScale = Instance.new("UIScale")
	titleScale.Parent = title

	local close = Instance.new("ImageButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = CLOSE_POS
	close.Size = CLOSE_BOX
	close.BackgroundTransparency = 1
	close.AutoButtonColor = false
	close.Image = UIAssets.url(UIAssets.Page.Close.Idle)
	close.HoverImage = UIAssets.url(UIAssets.Page.Close.Hover)
	close.PressedImage = UIAssets.url(UIAssets.Page.Close.Pressed)
	close.ImageTransparency = 1
	close.Parent = panel

	local closeAspect = Instance.new("UIAspectRatioConstraint")
	closeAspect.AspectRatio = UIAssets.Size.Close.X / UIAssets.Size.Close.Y
	closeAspect.Parent = close

	--- WHAT is being sold. The biggest white thing on the panel, because the one mistake this screen
	--- exists to prevent is selling a car the player did not think they were selling.
	local name = Instance.new("TextLabel")
	name.Name = "CarName"
	name.AnchorPoint = Vector2.new(0.5, 0.5)
	name.Position = UDim2.fromScale(0.5, NAME_Y)
	name.Size = UDim2.fromScale(0.86, 0.13)
	name.BackgroundTransparency = 1
	name.FontFace = FONT
	name.Text = ""
	name.TextColor3 = WHITE
	name.TextTransparency = 1
	name.TextScaled = true
	name.Parent = panel

	--[[ ...and WHAT FOR. This row is the money while the question is open and it is the ANSWER once
		it has been given — SELLING..., then SOLD or a refusal — because that is the row the player is
		already looking at, and moving the reply somewhere else would mean it arrives out of the corner
		of their eye. `_setPrice` is the one writer. ]]
	local price = Instance.new("TextLabel")
	price.Name = "Price"
	price.AnchorPoint = Vector2.new(0.5, 0.5)
	price.Position = UDim2.fromScale(0.5, PRICE_Y)
	price.Size = UDim2.fromScale(0.8, 0.17)
	price.BackgroundTransparency = 1
	price.FontFace = FONT
	price.Text = ""
	price.TextColor3 = CASH_GREEN
	price.TextTransparency = 1
	price.TextScaled = true
	price.Parent = panel

	local favRow, star, starLine = self:_starRow(panel)

	local yes, yesCaption = self:_pill(panel, "Yes", UIAssets.Pill.Green, PAIR_LEFT_X, lines.Yes)
	local no, noCaption = self:_pill(panel, "No", UIAssets.Pill.Silver, PAIR_RIGHT_X, lines.No)

	self._gui = gui
	self._scrim = scrim
	self._panel = panel
	self._bar = bar
	self._title = title
	self._close = close
	self._name = name
	self._price = price
	self._titleScale = titleScale
	--- NOT `_starRow`, which is the METHOD that built it — a field of that name shadows it and the
	--- next caller of `self:_starRow()` calls a Frame. Same trap as `_yes` / `_pressYes` below.
	self._favRow = favRow
	self._star = star
	self._starLine = starLine
	--[[ NAMED `_yes` / `_no` AND THE METHODS ARE `_pressYes` / `_pressNo`, which is not fussiness: an
		instance parked on a field shadows a method of the same name, and `self:_yes()` would then call
		a TextButton — "attempt to call an Instance". `ReviveController`'s header records that trap
		being paid for twice in one file. ]]
	self._yes = yes
	self._yesCaption = yesCaption
	self._no = no
	self._noCaption = noCaption

	self:_wire()

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	--[[ BOTH ANSWERS AND THE X ARE `UIButton`s. The tag is how every pressable thing in this game is
		declared (`UIController/Components/Button`), and it is what gives these three the hover swell,
		the hover sound and the click sound.

		THE TAG BRINGS NO BEHAVIOUR WITH IT, deliberately: none of them carries a `Page` or an `Action`
		attribute, so a press through `ButtonPress` plays its click and does nothing else. What the
		answers MEAN stays in this file, on the `Activated` wires, because both are answers to an offer
		that is still open — a state the UI layer knows nothing about.

		LAST, AND AFTER THE PARENTING: the component reads the button the moment the tag lands. ]]
	self._yes:SetAttribute("Scale", PILL_HOVER_SCALE)
	self._no:SetAttribute("Scale", PILL_HOVER_SCALE)
	self._close:SetAttribute("Scale", CLOSE_HOVER_SCALE)
	CollectionService:AddTag(self._yes, "UIButton")
	CollectionService:AddTag(self._no, "UIButton")
	CollectionService:AddTag(self._close, "UIButton")
end

--[[ The new UI's panel: the authored template, cloned into a ScreenGui of this file's own.

	RETURNS WHETHER IT BUILT; false has already been said out loud, and `_build` draws the old panel.

	THE FIELDS ARE THE OLD PANEL'S, pointed at the kit's parts, so the answers, the locks, the
	timeouts and the pad are one path. The few that differ in kind are named for what they are:
	`_priceTint` and `_yesFace` are the gradients the kit colours with, and the colours they swap
	between are read off the template's attributes here, once.

	THE BUTTONS ARRIVE TAGGED (`PrepKitTemplate`, and a tag survives a clone), and they become
	`UIButton`s when the ScreenGui is parented, which is the last line: after `_wire` and after every
	part is in place, which is the order the old panel keeps by tagging by hand. ]]
function SellPopupController._buildKit(self): boolean
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", KIT_WAIT)
	local root = playerGui and UIRoot.wait(playerGui :: PlayerGui, KIT_WAIT)
	local shelf = root and root:WaitForChild(KIT_SHELF, KIT_WAIT)
	local template = shelf and shelf:WaitForChild(KIT_TEMPLATE, KIT_WAIT)
	if not (template and template:IsA("GuiObject")) then
		warn(string.format("[SellPopupController] No MainUIV2.%s.%s after %ds; drawing the old panel. Run BuildSellCarV2.", KIT_SHELF, KIT_TEMPLATE, KIT_WAIT))
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
	local name = main and main:FindFirstChild("CarName")
	local price = main and main:FindFirstChild("Price")
	local priceTint = price and price:FindFirstChild("Tint")
	local favRow = main and main:FindFirstChild("Favorite")
	local star = favRow and favRow:FindFirstChild("Star")
	local starLine = favRow and favRow:FindFirstChild("Line")
	local yes = btns and btns:FindFirstChild("YesBtn")
	local no = btns and btns:FindFirstChild("NoBtn")
	local yesFace = yes and yes:FindFirstChildOfClass("UIGradient")
	local yesCaption = yes and yes:FindFirstChild("Title")
	local noCaption = no and no:FindFirstChild("Title")
	if
		not (
			title
			and close
			and close:IsA("GuiButton")
			and name
			and price
			and priceTint
			and priceTint:IsA("UIGradient")
			and favRow
			and star
			and starLine
			and yes
			and yes:IsA("GuiButton")
			and no
			and no:IsA("GuiButton")
			and yesFace
			and yesCaption
			and noCaption
		)
	then
		warn("[SellPopupController] MainUIV2.Screens.SellCar is missing a part; drawing the old panel. Re-run BuildSellCarV2.")
		panel:Destroy()
		return false
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SellCar"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- see the header: the dim covers the topbar, and the panel centres on the screen
	gui.DisplayOrder = 997
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

	--- The confirm's punch, on the title's own UIScale as on the old panel. The title is a label, so
	--- no hover owns its scale.
	local titleScale = Instance.new("UIScale")
	titleScale.Parent = title

	self._kit = true
	self._gui = gui
	self._scrim = scrim
	self._panel = panel
	self._popScale = popScale
	self._bar = header
	self._title = title
	self._titleScale = titleScale
	self._close = close
	self._name = name
	self._price = price
	self._priceTint = priceTint
	--- The price row's two inks, from the template. A template somebody stripped them from draws the
	--- row in plain white rather than erroring.
	self._priceMoney = price:GetAttribute("MoneyColor")
	self._priceRefused = price:GetAttribute("RefusedColor")
	self._favRow = favRow
	self._star = star
	self._starLine = starLine
	self._yes = yes
	self._yesCaption = yesCaption
	self._yesFace = yesFace
	--- SELL IT's two faces: the green it was authored in, and the red it turns while it asks again.
	self._yesAsk = yesFace.Color
	self._yesConfirm = yes:GetAttribute("ConfirmColor")
	self._no = no
	self._noCaption = noCaption

	self:_wire()

	gui.Parent = playerGui
	return true
end

function SellPopupController._wire(self)
	self._yes.Activated:Connect(function()
		self:_pressYes()
	end)
	self._no.Activated:Connect(function()
		self:_pressNo()
	end)
	--- The X is KEEP IT by another name, and it goes through the same function so there is one
	--- definition of what declining does.
	self._close.Activated:Connect(function()
		self:_pressNo()
	end)

	--[[ A CLOSED PANEL SWITCHES ITSELF BACK OFF, whoever switched it on (2026-09-30).

		The NEW BEST cutscene (`ShowcaseController`) and the hide-UI setting (`InterfaceController`)
		both sweep every ScreenGui off and later switch back on each one that asked to be on in the
		meantime. A sale made under the cutscene is exactly that: this panel opened (recorded as
		wanted), sold, and its own close wrote `false` onto a screen the sweep had already forced to
		false, which fires nothing. So the restore put it back ON after it had closed, with the dim
		faded to nothing and still `Active` over the whole screen: every click in the lobby,
		PLAY included, landed on an invisible scrim. Both sweepers document that limit; this is the
		screen honouring it rather than hoping nobody sweeps mid-close.

		`offer` raises `_open` BEFORE it enables the gui, so a real open is never undone here, and
		the fade out does not change `Enabled` until its last frame, so it is never cut short. ]]
	self._gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if self._gui.Enabled and not self._open then
			self._gui.Enabled = false
		end
	end)
end

-- === The two answers ========================================================

--[[ SELL IT. On a starred car the FIRST press asks again; otherwise it sends, and locks the panel
	until somebody replies.

	THE LOCK IS THE WHOLE OF THE SEND, the same as WELCOME BACK's and the respawn screen's: between
	the press and the reply there are frames in which a button that still looks live is still live,
	and a second request for a car that has already gone comes back as a refusal for no reason.

	THE CONFIRM BORROWS THAT SAME LOCK for `Popup.ConfirmArm` — see that comment, which is the whole
	reason this branch is four lines rather than two. A second question drawn on the same pixels as
	the first is one a double click answers without ever being read. ]]
function SellPopupController._pressYes(self)
	if self._locked or not self._open then
		return
	end

	--[[ THE FIRST PRESS ON A STARRED CAR ASKS RATHER THAN SELLS — `SellConfig` note 7. Only the TITLE
		changes: the car, the price, the star and both pills stay exactly where they were, because the
		second press is the same press and re-drawing the panel around it would make the player work
		out whether it still meant what it meant a moment ago. ]]
	if self._favorite and not self._confirming then
		self._confirming = true
		--- THE BUTTON FIRST, because it is the one the player is looking at — see the header.
		self:_setYesArt(UIAssets.Pill.Red, SellConfig.PopupLines.YesConfirm)
		self._title.Text = oneLine(SellConfig.PopupLines.Confirm)
		self:_pulseTitle()
		self._locked = true
		self:_setPillsLive(false)

		local armToken = self._token
		task.delay(SellConfig.Popup.ConfirmArm, function()
			--- Only if this is still the same panel, still open, and still waiting on the answer this
			--- arm belongs to. A press that got through in the meantime owns the lock now.
			if self._open and self._token == armToken and self._confirming and self._answer == nil then
				self._locked = false
				self:_setPillsLive(true)
			end
		end)
		return
	end

	self._locked = true
	self._answer = "yes"
	self:_setPrice(SellConfig.PopupLines.Working, WHITE)
	self:_setPillsLive(false)

	local handlers = self._handlers
	if handlers and handlers.answer then
		handlers.answer(true)
	end

	--- See `Popup.AnswerTimeout`: a lost answer must not leave a locked panel over the lot. It
	--- UNLOCKS rather than closing — nothing was sold and the question still stands.
	local token = self._token
	task.delay(SellConfig.Popup.AnswerTimeout, function()
		if self._open and self._locked and self._token == token then
			self._locked = false
			self._answer = nil
			--- BACK TO THE FIRST QUESTION, confirm and all. A press the server never answered is not a
			--- press a starred car gets to bank, and the panel that comes back has to be the one the
			--- player would recognise if they had walked away and returned.
			self._confirming = false
			self:_setYesArt(UIAssets.Pill.Green, SellConfig.PopupLines.Yes)
			self._title.Text = oneLine(SellConfig.PopupLines.Title)
			self:_setPrice(self._priceText, CASH_GREEN)
			self:_setPillsLive(true)
		end
	end)
end

--[[ KEEP IT, and the X, and B on a controller. It costs the player NOTHING: the car is standing on
	the pad exactly where they left it and the lot will ask again next time they walk up to it —
	`SellController` clears the refusal the moment the offer stops applying. That is what makes it
	safe for this panel to have a plain way out rather than being a wall. ]]
function SellPopupController._pressNo(self)
	if self._locked or not self._open then
		return
	end
	self._answer = "no"

	local handlers = self._handlers
	if handlers and handlers.answer then
		handlers.answer(false)
	end
	self:_hide()
end

-- === What the server said ===================================================

--[[ The reply to a SELL IT. Draws it on the price row and drops the panel a beat later.

	AN UNKNOWN REASON STILL CLOSES. `sellCars` has refusals that cannot reach this panel at all
	("disabled", "badRequest", "noProfile") and inventing a line for each of them would be writing
	copy for states no player can be in — but a panel left standing on SELLING... because the server
	said something this file has never heard of is the one outcome worth ruling out by construction.

	IGNORED IF NOTHING IS PENDING. A reply can land after the panel has already gone: the player
	walked out of reach in the round trip, or the car rolled off the pad and `SellController` dropped
	the offer. There is nothing to draw it on and nothing to correct — the sale either happened or it
	did not, and the profile is the authority on which. ]]
function SellPopupController.result(self, reason: unknown, price: unknown)
	if not (self._open and self._locked) then
		return
	end
	local lines = SellConfig.PopupLines

	--[[ A SALE CLOSES THE PANEL ON THE SPOT and draws nothing — the header's "there is no SOLD
		state". The money is already on its way out of the lot and into the player
		(`SellController._onResult` fires the burst on this same reply, one line earlier), and every
		frame this panel stays up is a frame of that flight behind a full-screen scrim. ]]
	if reason == "sold" then
		self:_hide()
		return
	end

	if reason == "seated" then
		self:_setPrice(lines.Seated, REFUSED_RED)
	else
		--- Every other refusal means the same thing to a player standing here: the car this panel was
		--- about is not on the pad any more. "noCar", "away", and anything `sellCars` invents later.
		self:_setPrice(lines.Gone, REFUSED_RED)
	end

	local token = self._token
	task.delay(SellConfig.Popup.RefusalHold, function()
		if self._open and self._token == token then
			self:_hide()
		end
	end)
end

-- === Painting ===============================================================

--- The one writer of the price row — the money, then the reply. Everything that changes what this
--- row says goes through here so a colour can never be left over from the state before.
function SellPopupController._setPrice(self, text: string, colour: Color3)
	self._price.Text = if text == "" then "" else oneLine(text)
	if self._kit then
		--[[ The kit's type is white under a gradient, so the row's three inks are three states of its
			`Tint`: the money gradient for the price, the kit's red for a refusal, and no tint at all
			for SELLING..., which is white on both panels. The callers pass the old panel's colours and
			this reads them as the names of those states, so there is still one writer and one set of
			call sites. ]]
		local ink = if colour == CASH_GREEN then self._priceMoney elseif colour == REFUSED_RED then self._priceRefused else nil
		self._priceTint.Enabled = typeof(ink) == "ColorSequence"
		if typeof(ink) == "ColorSequence" then
			self._priceTint.Color = ink
		end
		return
	end
	self._price.TextColor3 = colour
end

--[[ The row under the price, which says one of two things (2026-10-15).

	A STARRED CAR GETS THE FAVOURITE'S WARNING, star and amber line, exactly as before. Any other car
	gets what a buyer pays for it (`SellConfig.PopupLines.Buyers`), with no star and in the kit's
	plain white, because it is information and not a warning. `worth` is the money already
	formatted, or nil when the lot pays as much as a buyer would, and then the row stays empty.

	THE WARNING WINS when both apply. It is the line that stops a slip, and the buyer line is only
	advice.

	The line's box is widened while it carries the buyer line, since the star's slot is free and the
	sentence is longer, and put back for the warning. Both panels keep the same row, so it is read
	off whichever one was built. ]]
function SellPopupController._setNote(self, worth: string?)
	local line = self._starLine
	self._noteSize = self._noteSize or line.Size
	self._noteAlign = self._noteAlign or line.TextXAlignment

	local buyers = not self._favorite and type(worth) == "string" and worth ~= ""
	self._favRow.Visible = self._favorite or buyers
	self._star.Visible = not buyers
	line.Text = oneLine(if buyers then string.format(SellConfig.PopupLines.Buyers, worth) else SellConfig.Lines.Favorite)
	line.Size = if buyers then UDim2.fromScale(0.9, self._noteSize.Y.Scale) else self._noteSize
	line.TextXAlignment = if buyers then Enum.TextXAlignment.Center else self._noteAlign

	if self._kit then
		--- The kit's amber is a `Tint` gradient over white type, so plain white is that tint switched off.
		local tint = line:FindFirstChild("Tint")
		if tint and tint:IsA("UIGradient") then
			tint.Enabled = not buyers
		end
	else
		line.TextColor3 = if buyers then WHITE else WARN_AMBER
	end
end

--[[ Repaint the SELL IT pill: all three of its states and its words, in one call.

	ALL THREE IMAGES, NEVER JUST `Image`. The pill's press is geometric — the face drops 6px inside
	the art — so a swap that left `HoverImage` or `PressedImage` on the old colour would flick back to
	green under the cursor at exactly the moment the player is deciding.

	THE CAPTION BOX IS ONE WIDTH FOR BOTH LABELS (see `_pill`), so the confirm's longer string simply
	renders smaller. `TextScaled` fits to the tighter of the two axes, and for the short label that is
	the HEIGHT — so making room for the long one costs the ordinary state nothing. ]]
function SellPopupController._setYesArt(self, colours, text: string)
	if self._kit then
		--[[ The kit pill is one face under a gradient, so the three textures become one swap, and the
			pill table the callers pass is read as which face: the red pill means the confirm. Hover and
			press are the `UIButton` component's scale on the kit, not textures, so there is no stale
			state to flick back to. ]]
		local confirming = colours == UIAssets.Pill.Red
		local face = if confirming then self._yesConfirm else self._yesAsk
		if typeof(face) == "ColorSequence" then
			self._yesFace.Color = face
		end
		self._yesCaption.Text = oneLine(text)
		return
	end
	self._yes.Image = UIAssets.url(colours.Idle)
	self._yes.HoverImage = UIAssets.url(colours.Hover)
	self._yes.PressedImage = UIAssets.url(colours.Pressed)
	self._yesCaption.Text = oneLine(text)
end

--[[ Both pills live or dead at once. `Active`/`AutoButtonColor` are not enough on their own — the
	press guard in `_pressYes` is what actually refuses — so this is the part the player can SEE:
	a dead pill is dimmed and stops swapping texture under the cursor. ]]
function SellPopupController._setPillsLive(self, live: boolean)
	if self._kit then
		for _, button in { self._yes, self._no } do
			button.Active = live
			fadeKitButton(button, if live then 0 else KIT_DEAD_FADE)
		end
		return
	end
	for _, button in { self._yes, self._no } do
		button.Active = live
		button.ImageTransparency = if live then 0 else 0.55
	end
	for _, caption in { self._yesCaption, self._noCaption } do
		caption.TextTransparency = if live then 0 else 0.55
	end
end

--- A short punch on the title when it turns into the second question. Scale only, and small: the
--- words are what changed and this only has to make sure they are looked at.
function SellPopupController._pulseTitle(self)
	self._titleScale.Scale = 1
	local up = TweenService:Create(self._titleScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.12 })
	up:Play()
	up.Completed:Once(function()
		TweenService:Create(self._titleScale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
end

-- === Show / hide ============================================================

--[[ Put the question up.

	`offer` is { name, price, worth?, favorite } and `handlers` is { answer, closed } — see the header: this
	file looks nothing up, and both of those come from `SellController`, which is the only thing that
	knows there is a lot at all.

	RE-OFFERING WHILE IT IS OPEN REPAINTS RATHER THAN REOPENING, and that is a guard rather than a
	feature: the caller is a five-times-a-second poll, and a poll that re-raised the panel would run
	the fade again in the player's face every fifth of a second. ]]
function SellPopupController.offer(self, offer, handlers)
	if not (SellConfig.Enabled and SellConfig.Popup.Enabled) then
		return
	end
	if not self._gui then
		self:_build()
	end

	self._handlers = handlers
	self._priceText = offer.price or ""
	self._name.Text = oneLine(offer.name or "")
	self:_setPrice(self._priceText, CASH_GREEN)
	--- Whether SELL IT asks again before it sells — `SellConfig` note 7. `SellController` decides it
	--- (it is the one that can read a profile) and this only obeys.
	self._favorite = offer.favorite == true
	self:_setNote(offer.worth)

	if self._open then
		return
	end

	self._open = true
	self._locked = false
	self._answer = nil
	--- Every panel opens on the FIRST question, whatever the last one was left on: green pill, short
	--- label, first title.
	self._confirming = false
	self:_setYesArt(UIAssets.Pill.Green, SellConfig.PopupLines.Yes)
	self._title.Text = oneLine(SellConfig.PopupLines.Title)
	self._token = (self._token or 0) + 1
	self._titleScale.Scale = 1
	self:_setPillsLive(true)

	self._gui.Enabled = true
	if self._kit then
		--[[ The dim on this file's timing and the panel popping from 0.9, the way every V2 page opens.
			Nothing on the kit panel fades part by part: its art is a gradient rim, a checker, a white
			body and outlined type, and fading those one at a time shows the rim through a half-clear
			body and leaves outlines standing after their letters. ]]
		self._scrim.BackgroundTransparency = 1
		self:_tween(self._scrim, RAISE_TIME, { BackgroundTransparency = SCRIM_REST })
		self._popScale.Scale = KIT_START_SCALE
		self._panel.Visible = true
		TweenService:Create(self._popScale, KIT_OPEN, { Scale = 1 }):Play()
	else
		self:_tween(self._scrim, RAISE_TIME, { BackgroundTransparency = SCRIM_REST })
		self:_tween(self._panel, RAISE_TIME, { ImageTransparency = 0 })
		self:_tween(self._bar, RAISE_TIME, { ImageTransparency = 0 })
		self:_tween(self._title, RAISE_TIME, { TextTransparency = 0 })
		self:_tween(self._close, RAISE_TIME, { ImageTransparency = 0 })
		self:_tween(self._name, RAISE_TIME, { TextTransparency = 0 })
		self:_tween(self._price, RAISE_TIME, { TextTransparency = 0 })
		self:_tween(self._yes, RAISE_TIME, { ImageTransparency = 0 })
		self:_tween(self._yesCaption, RAISE_TIME, { TextTransparency = 0 })
		self:_tween(self._no, RAISE_TIME, { ImageTransparency = 0 })
		self:_tween(self._noCaption, RAISE_TIME, { TextTransparency = 0 })
		if self._favRow.Visible then
			self:_tween(self._star, RAISE_TIME, { ImageTransparency = 0 })
			self:_tween(self._starLine, RAISE_TIME, { TextTransparency = 0 })
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
end

--- Is the question on screen? `SellController` asks so it can drop the price sign behind it.
function SellPopupController.isOpen(self): boolean
	return self._open == true
end

--[[ Is this panel mid-answer — a SELL IT sent and not yet replied to, or a receipt still up?

	IT IS THE "LEAVE ME ALONE" FLAG. `SellController` polls the world and closes this panel the
	moment the question stops applying, and the moment a sale goes through is exactly when the
	question stops applying: the car is despawned out from under the receipt. Without this the SOLD
	would be cut off at the next poll, a fifth of a second in.

	The same flag is what the answer timeout clears, so a reply that never comes gives the panel
	back to the poll rather than freezing it up there. ]]
function SellPopupController.isBusy(self): boolean
	return self._open == true and self._locked == true
end

--[[ Take it down from outside — the car rolled off the pad, the player walked away, they got back
	in. It is NOT an answer and does not report one, so nothing is marked as declined and the lot
	asks again the moment it applies again. ]]
function SellPopupController.close(self)
	if not self._open then
		return
	end
	self._answer = nil
	self:_hide()
end

function SellPopupController._hide(self)
	if not (self._gui and self._open) then
		return
	end
	self._open = false
	self._locked = false
	local token = self._token
	local answer = self._answer
	local handlers = self._handlers
	self._answer = nil
	self._handlers = nil

	local last
	if self._kit then
		--- The panel drops back to 0.9 and goes, as a page does; the dim is the longer of the two, so
		--- it is the one the switch-off below waits for.
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
		self:_tween(self._name, DROP_TIME, { TextTransparency = 1 })
		self:_tween(self._star, DROP_TIME, { ImageTransparency = 1 })
		self:_tween(self._starLine, DROP_TIME, { TextTransparency = 1 })
		self:_tween(self._yes, DROP_TIME, { ImageTransparency = 1 })
		self:_tween(self._yesCaption, DROP_TIME, { TextTransparency = 1 })
		self:_tween(self._no, DROP_TIME, { ImageTransparency = 1 })
		self:_tween(self._noCaption, DROP_TIME, { TextTransparency = 1 })
		last = self:_tween(self._price, DROP_TIME, { TextTransparency = 1 })
	end
	self:_fadePad(DROP_TIME, false)

	--[[ REPORTED NOW AND NOT AFTER THE FADE. The caller uses this to decide whether the lot may ask
		again, and a fifth of a second in which the panel is gone and the offer is still considered
		open is a fifth of a second in which nothing can re-ask. ]]
	if handlers and handlers.closed then
		handlers.closed(answer)
	end

	last.Completed:Once(function()
		--- Fenced on the token, so nothing is switched off by the tail of a panel that has already
		--- been replaced by the next one.
		if self._token == token and not self._open then
			self._gui.Enabled = false
			self:_bindPad(false)
		end
	end)
end

function SellPopupController._tween(self, inst, time: number, props)
	local tween = TweenService:Create(inst, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

-- === The controller =========================================================

--- A and B, live only while the panel is, and both are the same two functions the mouse calls — so
--- there is one definition of what each answer means and the lock guards both.
function SellPopupController._bindPad(self, on: boolean)
	GamepadInput.setModal("SellPopupController", on)

	if not on then
		GamepadInput.unbind(PAD_YES)
		GamepadInput.unbind(PAD_NO)
		return
	end

	--- Same bindings on both panels; only where the badges hang differs (see `KIT_BADGE_POS`).
	local badgePos = if self._kit then KIT_BADGE_POS else PAD_BADGE_POS
	local badgeAnchor = if self._kit then KIT_BADGE_ANCHOR else PAD_BADGE_ANCHOR

	GamepadInput.bind({
		actionName = PAD_YES,
		keyCode = Enum.KeyCode.ButtonA,
		callback = function()
			self:_pressYes()
		end,
		parent = self._yes,
		iconPosition = badgePos,
		iconAnchor = badgeAnchor,
		iconSize = PAD_BADGE_SIZE,
		priority = PAD_PRIORITY,
	})
	GamepadInput.bind({
		actionName = PAD_NO,
		keyCode = Enum.KeyCode.ButtonB,
		callback = function()
			self:_pressNo()
		end,
		parent = self._no,
		iconPosition = badgePos,
		iconAnchor = badgeAnchor,
		iconSize = PAD_BADGE_SIZE,
		priority = PAD_PRIORITY,
	})
end

function SellPopupController._padIcons(self): { ImageLabel }
	local icons = {}
	for _, action in { PAD_YES, PAD_NO } do
		local icon = GamepadInput.getIcon(action)
		if icon and icon.Parent then
			table.insert(icons, icon)
		end
	end
	return icons
end

--- The badges fade with the panel rather than popping in with it, which is the whole reason they are
--- faded by hand: `GamepadInput` draws them the frame it binds and knows nothing about this screen.
function SellPopupController._fadePad(self, time: number, shown: boolean)
	for _, icon in self:_padIcons() do
		self:_tween(icon, time, {
			ImageTransparency = if shown then 0 else 1,
			BackgroundTransparency = if shown then 0 else 1,
		})
		local stroke = icon:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			self:_tween(stroke, time, { Transparency = if shown then 0 else 1 })
		end
	end
end

-- === Lifecycle ==============================================================

SellPopupController:withLifecycle({
	init = function(self)
		self._open = false
		self._locked = false
		self._token = 0
		--- The money as it should read while the question is open, kept so the answer timeout can put
		--- it back after SELLING... has been up.
		self._priceText = ""
		--- Does this car need a second press, and has it had one? `_favorite` is the offer's; both are
		--- reset on every open. Header, and `SellConfig` note 7.
		self._favorite = false
		self._confirming = false
		self._handlers = nil
		self._answer = nil
	end,

	start = function(self)
		--[[ NOT BUILT HERE. This panel may never open in a whole session — a player who never drives a
			car onto the sell square never sees it — and building it on boot would be a ScreenGui, a
			sliced panel and five textures preloaded for nothing. `offer` builds on first use, which is
			the same call `OfflineController` makes for the opposite reason (its screen opens once and
			then never again). ]]
	end,
})

SellPopupController:withCleanup(function()
	SellPopupController:_bindPad(false)
	if SellPopupController._gui then
		SellPopupController._gui:Destroy()
		SellPopupController._gui = nil
	end
	SellPopupController._open = false
end)

return SellPopupController
