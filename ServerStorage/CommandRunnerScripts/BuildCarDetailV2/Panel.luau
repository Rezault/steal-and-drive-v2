--[[
	BuildCarDetailV2.Panel

	Builds the two DETAIL WINGS onto a car screen: `DetailLeft` and `DetailRight`, children of the
	page frame itself, standing either side of the card grid. `Components/CarDetailV2` fills them and
	`CarDetailConfig` names every part they are made of.

	A module rather than a command because THREE commands make these: `BuildCarDetailV2` (both pages
	at once, the one you re-run by hand) and `BuildDealershipV2` / `BuildStartCarV2`, each of which
	destroys and rebuilds its page from the kit on every run and would otherwise throw the wings away.
	Every one of them calls this, so there is one arrangement of the panel and not three.

	=== WHY THE WINGS HANG OUTSIDE THE PANEL ==================================================

	The alternative is to put them INSIDE it, and that costs the cards. A kit page is a fixed shape
	(944x640 in the artist's file) under an aspect constraint, `Main` is 0.966 of it, and the grid
	fills `Main` four cards across — which is already Dylan's "make the cards a little bit bigger so
	that we have a better view of the cars" spent once (`KitGrowth.columns`). Taking two columns'
	worth of width out of the middle of that to stand the wings in would undo exactly that change.

	Outside, a wing is sized in the PAGE's own fractions, so it grows and shrinks with the page, holds
	its proportion on every screen the page holds its own on, and comes along with the open tween for
	free — `UIController` scales the page frame, and these are in it.

	=== THE ARITHMETIC THAT DECIDES THE RAIL HAS TO MOVE ======================================

	At 1080p the page is 1147px wide, centred, so it runs from x=386 to x=1534. The HUD's icon grid
	is 270px wide starting at x=26, so it ENDS at 296 — ninety pixels of clear air either side of the
	panel. A wing narrow enough to fit in that is 90px wide, which is not a panel, it is a margin.

	Every other arrangement was measured and none of them works: shrinking the page until the whole
	assembly clears the rail wants it at 0.52 of the growth it has (cards smaller than the kit's own,
	which is where this started), and sliding the assembly right to clear the rail puts the panel
	visibly off-centre and still fails on a 4:3 tablet, where the rail is proportionally further in.

	So the rail steps aside while the wings are up. That is `CarDetailConfig.HideRail`, the component
	asks rather than writes, and `RaceEntryController` — which already owns that frame's `Visible` for
	the length of a race — is the one that answers. The Play button has done exactly this for any open
	page since 2026-09-16.

	=== WHAT IS HARVESTED, AND FROM WHERE =====================================================

	Nothing here is drawn; every part of both wings is a clone of something the artist drew.

	  • THE PANEL DRESS — the blue gradient, the two strokes, the corner and the checkered `BG` —
	    comes off the PAGE FRAME, so a wing is the same panel the grid is in, narrower.
	  • THE CAR'S NAME is the page's own `Header.Title`, centred.
	  • THE RARITY WORD is the card's `Rarity`, gradient and all, which is the one the page already
	    tints per band (`BuildDealershipV2` named that gradient `Tint`).
	  • THE BARS are the QUEST row's `ProgressBar`, the only continuous bar in the kit. The segmented
	    five-pip meter on the upgrades row was the other candidate and it says the wrong thing: a
	    stat is a position on a range, not three of five steps bought.
	  • THE MONEY LINE is the quest row's `Reward`, which is the kit's green cash type.
	  • THE BUTTON is the CARD's `Btns` — both faces, the green verb and the grey "already what you
	    are asking for" — so the wing's press and the card's press are the same control drawn larger.
	    It arrives already tagged `UIButton` (`PrepKitTemplate` tagged the kit), so the hover, the
	    press sound and the gamepad highlight come with it and nothing wires them.

	=== AND THREE THINGS ARE ADDED TO THE CARD ================================================

	`Pick`, a thicker stroke in the page's own blue, off by default: the halo on the card the wings are
	describing, and the same colour as `Hover` below so that pointing at a card and picking it are one
	statement getting louder rather than two colours. A card can wear this and the green `Rim` at once — they answer different questions
	("the one you are looking at" and "the one in the street") — and the halo is the THICKER of the
	two, so the pair draws as a green ring inside a cyan glow rather than as one muddy edge.

	`Hover`, the same rim again at two thirds that thickness and in the same blue, resting at
	transparency 1 so it draws nothing until a pointer arrives. It goes on before the halo so the halo covers it on a card that is wearing both. THE CARDS HAVE TO SAY THAT THEY CAN BE PRESSED, because
	since 2026-09-17 nothing but a press opens the wings: they used to come up on their own with a
	car already picked, and a panel that opens by itself teaches nobody where it came from.
	`Components/CarDetailV2.hoverCard` fades this and swells the card.

	`PickBtn`, an invisible press over the card's PICTURE, which is what picks it. The card's verb
	button is a sibling of the picture and is not under this, so a tap on it still spawns, parks or
	drives outright — the screen keeps the rule it was rewritten around on 2026-08-24, that a tap is
	the verb, and gains a second gesture on the one part of a card that never had one.

	HOUSE RULE: no wiki-style double-bracket links in this comment; the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CarDetailConfig = require(ReplicatedStorage.shared.Configs.CarDetailConfig)
local InventoryConfig = require(ReplicatedStorage.shared.Configs.InventoryConfig)
local RewardConfig = require(ReplicatedStorage.shared.Configs.RewardConfig)

local Panel = {}

local NAMES = CarDetailConfig.Parts

--- Where the kit lives. `NewUIConfig.TemplatePath`, under ServerStorage; the same walk every V2
--- build command does, because a command may not require a client config.
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" }

--- What the bars and the cash line are cut from. See the header.
local QUEST_FRAME = "QuestsUI"
local QUEST_BAR = "ProgressBar"
local QUEST_MONEY = "Reward"

--- The card the button and the rarity word are cut from, as the two page builders leave it.
local CARD_NAME = "CarCard"
local FACE_NAME = "Face"

--[[ THE WING, in fractions of the page frame. Width and gap are the room either side of a centred
	kit page: at 1080p the page is 1147px of 1920, so 0.268 of it is a 307px panel with a 23px gap,
	and the pair plus the page comes to 95% of the screen. Anything wider crowds the screen's own
	edges on a 4:3 tablet, where the page is squarer and the margins are thinner.

	SHORTER THAN THE PAGE, and centred against it rather than aligned to a corner: a wing is a
	separate object standing beside the panel, and one that matched its height exactly would read as
	a piece that had come loose off the side of it. ]]
local WING_WIDTH = 0.268
local WING_GAP = 0.020
local WING_HEIGHT = 0.80
local WING_MIDDLE = 0.55

--- Room down each side of a wing's contents.
local PAD = 0.07

--[[ The left wing, top down, in fractions of the WING: name, band, the car, what it earns, and how
	far up its own ladder it is. Each is a top edge and a height.

	THE CAR'S BOX IS WIDER THAN IT IS TALL, which is the one number here with a reason outside
	taste. A car is about three times longer than it is high and the wing is narrow, so the picture
	can only ever be as big as the wing is wide; a taller box does not draw a bigger car, it draws
	the same car with more empty road above and below it. `docs/NewUI-Migration-Notes.md` has the
	same observation about the square picture box on the cards. ]]
local NAME_Y, NAME_H = 0.040, 0.085
local RARITY_Y, RARITY_H = 0.140, 0.055
local PORTRAIT_Y, PORTRAIT_H = 0.230, 0.300
local RATE_Y, RATE_H = 0.600, 0.080
local LEVEL_Y, LEVEL_H = 0.755, 0.060
local LEVEL_BAR_Y, LEVEL_BAR_H = 0.855, 0.032

--- The right wing: a caption, the stat rows under it, and the verb at the foot.
local STATS_TITLE_Y, STATS_TITLE_H = 0.035, 0.070
local STATS_Y, STATS_H = 0.135, 0.620
local BTN_Y, BTN_H = 0.810, 0.120

--[[ One stat row, in fractions of the ROWS BOX. Four rows and the three gaps between them fill it:
	the caption and its rating on one line, the bar under them.

	The gap is a `UIListLayout` padding in SCALE, which is safe here and would not be in the grid:
	this is a plain Frame, not a ScrollingFrame, so a child's scale resolves against the frame rather
	than against a canvas it is also feeding. See `KitPage`'s header for the trap. ]]
local ROW_HEIGHT = 0.205
local ROW_GAP = 0.058
local ROW_CAPTION_H = 0.50
local ROW_RATING_W = 0.30
local ROW_BAR_Y, ROW_BAR_H = 0.62, 0.30

--[[ How much of a label's box the words are allowed to fill, as its `UITextSizeConstraint`.

	A KIT CAP IS THE LABEL'S HEIGHT IN PIXELS ON A 1080-TALL SCREEN — the page's own header is 63px
	tall and carries a cap of 63 — and `KitPage.scaleTextCaps` multiplies it by the screen's height
	at runtime. So every cap written here is worked out the same way, and a caption that should read
	smaller than its box gets a fraction of it rather than a number typed in. ]]
local CAP_REFERENCE = 1080
local FULL_CAP = 1.0
local TIGHT_CAP = 0.78

--[[ The halo on the selected card: the SAME blue as the hover ring below and half again as thick,
	so a card goes from pointed-at to picked by gaining weight rather than by changing colour, and
	keeps the outline Dylan asked it to keep ("make the outline color stay if you have it selected
	and that card is showing", 2026-09-17). It was the LIGHT end of the page's ramp, the kit's cyan,
	until then; that reads as its own state, which is the thing he did not want.

	NOT THE BUTTON'S RAMP, which was the first try and is invisible: that one runs yellow to green
	and the card's face is yellow to orange, so a yellow ring round a yellow card is a ring nobody
	can see. The page's blue is what the warm cards are drawn against, and `HOVER_THICKNESS` has the
	contrast numbers that settled it. ]]
local HALO_THICKNESS = 2.4

--[[ The hover ring on every card: the same rim again, thinner than the halo above and drawn UNDER it,
	so a card that is picked AND pointed at wears the halo alone rather than two rings arguing. It is
	left ENABLED at transparency 1, which draws nothing — `Components/CarDetailV2.hoverCard` then has
	one number to fade and no state to switch.

	IT WAS WHITE UNTIL 2026-09-17 AND WHITE IS THE ONE COLOUR IT CANNOT BE. The grid these cards are
	laid out on is `Main`, which is opaque #FFFFFF, so the half of the ring that hangs outside a card
	was white on white: a contrast ratio of 1.00, which is not a faint ring, it is no ring at all.
	Against the card's own face it is barely better (1.23 on the yellow top of the gradient), so all
	it really did was rub out the artist's navy outline, and a hovered card came out LESS defined
	than a resting one. Dylan: "the white outline blends too much with the background."

	So it is the SATURATED end of the page's own ramp — the same gradient the halo's cyan is the light
	end of, which is why `rampEnds` returns both. Measured against the three things it is ever drawn
	over: 4.83 on the white grid, 3.92 on the card's yellow, 1.64 on its orange, where the ring is
	also complementary to the fill and reads on hue rather than on luminance. The kit's navy scores
	higher still (16.9) and is the wrong answer: it is the card's own outline colour, so the card
	would gain weight without gaining a signal. ]]
local HOVER_THICKNESS = 1.6

local function findKit(): (Instance?, string?)
	local node: Instance = ServerStorage
	for _, step in TEMPLATE_PATH do
		local child = node:FindFirstChild(step)
		if not child then
			return nil, string.format("%s has no child `%s`.", node:GetFullName(), step)
		end
		node = child
	end
	local screen = node:FindFirstChildWhichIsA("ScreenGui")
	local container = screen and screen:FindFirstChild("Container")
	if not container then
		return nil, string.format("%s holds no ScreenGui with a `Container` of frames.", node:GetFullName())
	end
	return container, nil
end

--- The quest row every bar and the cash line are cut from.
local function questRow(kit: Instance): GuiObject?
	local frame = kit:FindFirstChild(QUEST_FRAME)
	local main = frame and frame:FindFirstChild("Main")
	local list = main and main:FindFirstChildOfClass("ScrollingFrame")
	if not list then
		return nil
	end
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") and child:FindFirstChild(QUEST_BAR) then
			return child
		end
	end
	return nil
end

--- A wing's height in the pixels a 1080-tall screen draws it at, which is the unit every text cap
--- below is written in.
local function wingPixels(page: GuiObject): number
	return page.Size.Y.Scale * WING_HEIGHT * CAP_REFERENCE
end

--- Cap a cloned label to its new box. `fraction` is how much of the box the words may fill.
local function capTo(label: GuiObject, heightPx: number, fraction: number)
	local cap = label:FindFirstChildOfClass("UITextSizeConstraint")
	if cap then
		cap.MaxTextSize = math.clamp(math.round(heightPx * fraction), 1, 100)
	end
end

--[[ Put a cloned part in a wing: full width less the margins, at a top edge and a height of the
	wing's own. Anchored to its TOP so every number above is a top edge, which is how the list above
	reads down the panel. ]]
local function place(part: GuiObject, parent: GuiObject, y: number, height: number, width: number?)
	part.AnchorPoint = Vector2.new(0.5, 0)
	part.Position = UDim2.fromScale(0.5, y)
	part.Size = UDim2.fromScale(width or (1 - 2 * PAD), height)
	part.Parent = parent
end

--- The saturated end of a gradient, and the light one. Both rings a card can wear are cut from the
--- first of these, so no colour is ever typed in here.
local function rampEnds(gradient: UIGradient?): (Color3?, Color3?)
	if not gradient then
		return nil, nil
	end
	local stops = gradient.Color.Keypoints
	return stops[#stops].Value, stops[1].Value
end

--[[ A gradient read at one point along it, for something that has to match the panel it is lying on
	at one height. The kit's panel ramp has a stop in the middle, so the ends are not enough. ]]
local function rampAt(gradient: UIGradient?, time: number): Color3?
	if not gradient then
		return nil
	end
	local stops = gradient.Color.Keypoints
	local at = math.clamp(time, 0, 1)
	for index = 1, #stops - 1 do
		local low, high = stops[index], stops[index + 1]
		if at <= high.Time then
			local span = high.Time - low.Time
			return low.Value:Lerp(high.Value, if span > 0 then (at - low.Time) / span else 0)
		end
	end
	return stops[#stops].Value
end

--[[ Everything that makes a kit panel look like one, copied off the page onto a wing.

	THE CHECKER IS RESIZED ON THE WAY OVER, and that is a fix rather than a nicety. The artist's
	`CheckersBG` is a square image on `ScaleType.Fit`, sized in fractions of the PAGE so that the
	square it fits inside covers the page's long side. Cloned unchanged into a wing a quarter as wide
	and four fifths as tall, those same fractions make a far smaller square and `Fit` centres it — so
	the pattern stopped a hundred pixels short of the top and bottom of both wings and the panel read
	as two different materials (Dylan, 2026-09-17: "cut off from the top and bottom").

	Dividing each fraction by the wing's own gives the image THE SIZE IT HAS ON THE PAGE, in pixels.
	That covers the wing whatever shape the texture turns out to be — a square that covers 1147x777
	covers 307x622 — and it keeps the checker at the page's own cell size, so a wing and the panel
	beside it are one weave rather than two. ]]
local function dress(page: GuiObject, wing: GuiObject)
	wing.BackgroundColor3 = page.BackgroundColor3
	wing.BackgroundTransparency = page.BackgroundTransparency
	wing.BorderSizePixel = 0
	wing.ZIndex = page.ZIndex
	for _, child in page:GetChildren() do
		if child:IsA("UIStroke") or child:IsA("UIGradient") or child:IsA("UICorner") then
			child:Clone().Parent = wing
		elseif child:IsA("CanvasGroup") and child.Name == "BG" then
			--- The checkered backing. A CanvasGroup with a corner of its own, so it clips the
			--- pattern to the panel's shape exactly as it does on the page.
			local backing = child:Clone()
			for _, part in backing:GetDescendants() do
				if part:IsA("GuiObject") then
					local size = part.Size
					part.Size = UDim2.new(
						size.X.Scale / WING_WIDTH,
						size.X.Offset,
						size.Y.Scale / WING_HEIGHT,
						size.Y.Offset
					)
				end
			end
			backing.Parent = wing
		end
	end
end

--[[ A bar: the quest row's track with its fill normalised to grow from the left.

	THE ANCHOR IS SETTLED HERE rather than at runtime. The kit's fill is centred on its own left
	edge, which is what makes a resize grow it rightwards; writing that down at build time means the
	component only ever writes one number (`Size.X.Scale`) and can never move a bar by accident. ]]
local function newBar(source: GuiObject): GuiObject
	local bar = source:Clone()
	bar.Name = NAMES.Bar
	local fill = bar:FindFirstChild(NAMES.Fill)
	if fill and fill:IsA("GuiObject") then
		fill.AnchorPoint = Vector2.new(0, 0.5)
		fill.Position = UDim2.fromScale(0, 0.5)
		fill.Size = UDim2.fromScale(1, fill.Size.Y.Scale)
	end
	return bar
end

-- === The two wings ==========================================================

local function buildLeft(page: GuiObject, wing: GuiObject, card: GuiObject, row: GuiObject, pixels: number)
	local face = card:FindFirstChild(FACE_NAME)
	local header = page:FindFirstChild("Header")
	local headerTitle = header and header:FindFirstChild("Title")
	local titleSource = if headerTitle and headerTitle:IsA("TextLabel") then headerTitle else nil

	--- The car's name, in the page header's own type.
	if titleSource then
		local name = titleSource:Clone()
		name.Name = NAMES.Name
		name.Text = "CAMARO"
		name.TextXAlignment = Enum.TextXAlignment.Center
		place(name, wing, NAME_Y, NAME_H)
		capTo(name, pixels * NAME_H, FULL_CAP)
	end

	--- The rarity band, gradient and all. The page tints it per band off `Modules/CarRarity`.
	local rarity = face and face:FindFirstChild(NAMES.Rarity)
	if rarity and rarity:IsA("TextLabel") then
		local band = rarity:Clone()
		band.Name = NAMES.Rarity
		band.Text = "SUPERCAR"
		band.TextXAlignment = Enum.TextXAlignment.Center
		place(band, wing, RARITY_Y, RARITY_H)
		capTo(band, pixels * RARITY_H, FULL_CAP)
	end

	--[[ The box the turning car goes in: NOTHING AT ALL, a rectangle the car is framed to. The car
		turns on the panel itself.

		IT USED TO BE THE CARD'S OWN FACE, emptied — the warm gradient, the corner and the sunray kept,
		so the picture in the wing was the picture on the cards drawn large. Dylan asked for that to go
		on 2026-09-17, off a shot of the car picker: "maybe remove this background image for the car".
		He is right, and the reason it was there is the reason it had to go. The card the wings are
		describing is two inches away wearing that exact face, so the wing was repeating it at four
		times the size, and a yellow-to-orange starburst a third of the way down a blue panel is the
		loudest thing on the screen — louder than the car standing in front of it, which is the one
		thing the panel exists to show.

		IT STAYS EMPTY IN THE EXPLORER. A car is twenty-five meshes built on the client for the one
		car the player is looking at, and a ViewportFrame authored here would be a second place that
		decides how a car is framed (`Modules/CarViewport` is the only one).

		`Backdrop` IS THE COLOUR THE CAR'S EDGES BLEND INTO, and it is an attribute rather than a
		number in the component because it is a fact about this art. A ViewportFrame composites its
		render against `BackgroundColor3` before transparency, so every pixel the car only partly
		covers — the whole silhouette, one pixel wide — comes out part car and part backdrop. Left at
		the engine's grey it is a white outline traced round the car. What is behind the car is now the
		PANEL, so the colour is the panel's own ramp read at the height this box sits at (`rampAt`):
		the ramp moves across the height of the box and one colour cannot be right at both ends of it,
		but the middle of the box is where most of the car's silhouette is. ]]
	local portrait = Instance.new("Frame")
	portrait.Name = NAMES.Portrait
	portrait.BackgroundTransparency = 1
	portrait.BorderSizePixel = 0
	portrait.ZIndex = wing.ZIndex + 2
	local backdrop = rampAt(wing:FindFirstChildOfClass("UIGradient"), PORTRAIT_Y + PORTRAIT_H / 2)
	if backdrop then
		portrait:SetAttribute("Backdrop", backdrop)
	end
	place(portrait, wing, PORTRAIT_Y, PORTRAIT_H, 1 - PAD)

	--- What it earns a second. The kit's green cash type, off the quest row.
	local text = row:FindFirstChild("Text")
	local money = text and text:FindFirstChild(QUEST_MONEY)
	if money and money:IsA("TextLabel") then
		local rate = money:Clone()
		rate.Name = NAMES.Rate
		rate.Text = "$12/s"
		rate.TextXAlignment = Enum.TextXAlignment.Center
		place(rate, wing, RATE_Y, RATE_H)
		capTo(rate, pixels * RATE_H, FULL_CAP)
	end

	--[[ The level, as a caption and a bar under it. The bar is the level out of the ceiling rather
		than progress towards the next one, and that is not a shortcut: the client is sent LEVELS,
		not XP (`RewardConfig.encodeLevels`), so a bar drawn as "how far to level 4" would be a bar
		with nothing behind it. Out of ten, said out loud in the caption. ]]
	if titleSource then
		local level = titleSource:Clone()
		level.Name = NAMES.Level
		level.Text = string.format("LEVEL 1 / %d", RewardConfig.Xp.MaxLevel)
		level.TextXAlignment = Enum.TextXAlignment.Center
		place(level, wing, LEVEL_Y, LEVEL_H)
		capTo(level, pixels * LEVEL_H, FULL_CAP)
	end

	local barSource = row:FindFirstChild(QUEST_BAR)
	if barSource and barSource:IsA("GuiObject") then
		place(newBar(barSource), wing, LEVEL_BAR_Y, LEVEL_BAR_H)
	end
end

local function buildRight(page: GuiObject, wing: GuiObject, card: GuiObject, row: GuiObject, pixels: number)
	local header = page:FindFirstChild("Header")
	local headerTitle = header and header:FindFirstChild("Title")
	local titleSource = if headerTitle and headerTitle:IsA("TextLabel") then headerTitle else nil
	local barSource = row:FindFirstChild(QUEST_BAR)

	if titleSource then
		local caption = titleSource:Clone()
		caption.Name = NAMES.Title
		caption.Text = CarDetailConfig.Text.Stats
		caption.TextXAlignment = Enum.TextXAlignment.Center
		place(caption, wing, STATS_TITLE_Y, STATS_TITLE_H)
		capTo(caption, pixels * STATS_TITLE_H, TIGHT_CAP)
	end

	--- The rows box. One row per `InventoryConfig.Stats` entry, in the order that file draws them.
	local stats = Instance.new("Frame")
	stats.Name = NAMES.Stats
	stats.BackgroundTransparency = 1
	stats.BorderSizePixel = 0
	stats.ZIndex = wing.ZIndex + 2
	place(stats, wing, STATS_Y, STATS_H)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(ROW_GAP, 0)
	layout.Parent = stats

	local rowPixels = pixels * STATS_H * ROW_HEIGHT
	for index, stat in InventoryConfig.Stats do
		local statRow = Instance.new("Frame")
		statRow.Name = NAMES.StatRow
		statRow.BackgroundTransparency = 1
		statRow.BorderSizePixel = 0
		statRow.LayoutOrder = index
		statRow.Size = UDim2.fromScale(1, ROW_HEIGHT)
		statRow.ZIndex = stats.ZIndex
		--- Which stat this row is, read back by `Components/CarDetailV2`. By attribute rather than by
		--- name because the caption is a WORD the config owns and may be retitled.
		statRow:SetAttribute("Stat", stat.Key)

		if titleSource then
			local caption = titleSource:Clone()
			caption.Name = NAMES.Title
			caption.Text = stat.Label
			caption.TextXAlignment = Enum.TextXAlignment.Left
			caption.AnchorPoint = Vector2.new(0, 0)
			caption.Position = UDim2.fromScale(0, 0)
			caption.Size = UDim2.fromScale(1 - ROW_RATING_W, ROW_CAPTION_H)
			caption.ZIndex = statRow.ZIndex
			caption.Parent = statRow
			capTo(caption, rowPixels * ROW_CAPTION_H, TIGHT_CAP)

			--- The same fraction the bar draws, as a number out of ten. The artist's own card carries
			--- a `Rating` label reading "5.7", which is where that unit comes from.
			local rating = caption:Clone()
			rating.Name = NAMES.Rating
			rating.Text = "5.0"
			rating.TextXAlignment = Enum.TextXAlignment.Right
			rating.AnchorPoint = Vector2.new(1, 0)
			rating.Position = UDim2.fromScale(1, 0)
			rating.Size = UDim2.fromScale(ROW_RATING_W, ROW_CAPTION_H)
			rating.Parent = statRow
		end

		if barSource and barSource:IsA("GuiObject") then
			local bar = newBar(barSource)
			bar.AnchorPoint = Vector2.new(0.5, 0)
			bar.Position = UDim2.fromScale(0.5, ROW_BAR_Y)
			bar.Size = UDim2.fromScale(1, ROW_BAR_H)
			bar.ZIndex = statRow.ZIndex
			bar.Parent = statRow
		end

		statRow.Parent = stats
	end

	--[[ The verb, which is the card's own button drawn the width of the panel. Both faces come over:
		the green one a press does something with, and the grey one for a card that is already what
		you are asking for. The page decides which is showing and what each says, exactly as it does
		on the cards. ]]
	local buttons = card:FindFirstChild(NAMES.Buttons)
	if buttons and buttons:IsA("GuiObject") then
		local wingButtons = buttons:Clone()
		wingButtons.Name = NAMES.Buttons
		place(wingButtons, wing, BTN_Y, BTN_H)
		wingButtons.ZIndex = wing.ZIndex + 2
		for _, face in wingButtons:GetChildren() do
			if face:IsA("GuiObject") then
				--- Both faces are there whatever the page does with them: the car picker never shows
				--- the grey one (there is no car on that screen that is already what you are asking
				--- for) and hiding it is one line rather than a second shape of panel.
				face.Visible = face.Name == NAMES.Action
				local title = face:FindFirstChild("Title")
				if title and title:IsA("TextLabel") then
					capTo(title, pixels * BTN_H, TIGHT_CAP)
				end
			end
		end
	end
end

--[[ The two things a card needs before it can be picked: the halo that says it HAS been, and the
	press that picks it.

	THE PRESS IS OVER THE PICTURE AND NOTHING ELSE. `Btns` is a sibling of the face, so the card's
	own verb button is not under this and still does what it always did; the star and the level chip
	sit above it on `ZIndex` and still take their own presses. What is left is the picture, which had
	no press on it before the wings existed.

	`Selectable` ON, AND STILL NO `UIButton` TAG. It is in the gamepad's walk as of 2026-09-17 (Dylan:
	"fix it so that a console can select that card"), and it has to be: the wings open on a press now,
	so a pad that picked by HIGHLIGHTING would open and shut the panel as the DPad crossed the grid,
	and the toggle would have nothing to toggle. A pad therefore makes the same gesture a pointer
	does — land on the picture, press A — and the cars inventory wires the ladder up a card by hand
	(`_wireCard`: verb, star, picture, out of the grid) because this button covers the star and two
	overlapping selectables are not a search the engine can be trusted to resolve. The car picker has
	no star, so its cards are left to the engine.

	THE TAG STAYS OFF. It is what would add a second hover swell and a press sound on top of the
	reaction `Components/CarDetailV2.hoverCard` already gives the whole card. Writing `Selectable`
	here is only safe because the tag is absent: with it, `Components/Button` owns that property. ]]
local function dressCard(card: GuiObject, halo: Color3?, hover: Color3?): boolean
	local face = card:FindFirstChild(FACE_NAME)
	if not (face and face:IsA("GuiObject")) then
		return false
	end
	for _, name in { NAMES.Halo, NAMES.Hover, NAMES.Select } do
		local existing = face:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end

	--- Straight above the picture, which is the one thing on the face it has to cover. The name, the
	--- rarity, the star and the level chip are all drawn over that and stay over this.
	local icon = face:FindFirstChild("Icon")
	local overPicture = if icon and icon:IsA("GuiObject") then icon.ZIndex + 1 else 2

	local pick = Instance.new("TextButton")
	pick.Name = NAMES.Select
	pick.Text = ""
	pick.BackgroundTransparency = 1
	pick.BorderSizePixel = 0
	pick.AutoButtonColor = false
	pick.Selectable = true
	pick.AnchorPoint = Vector2.new(0.5, 0.5)
	pick.Position = UDim2.fromScale(0.5, 0.5)
	pick.Size = UDim2.fromScale(1, 1)
	pick.ZIndex = overPicture
	pick.Parent = face

	for _, stroke in face:GetChildren() do
		--- The artist's own border, cloned: the same sizing mode and the same corner behaviour, so
		--- each ring is that stroke drawn thicker rather than a second idea about the card's edge.
		if stroke:IsA("UIStroke") and stroke.Name ~= "Rim" then
			--[[ THE HOVER RING GOES ON FIRST, and the order is the whole of how the two rings get
				along: strokes draw in child order, so the halo below covers this one completely
				(it is the thicker of the two) and a card that is picked AND pointed at reads as
				picked. Nothing has to know about the other's state for that to hold. ]]
			local lit = stroke:Clone()
			lit.Name = NAMES.Hover
			lit.Enabled = true
			lit.Thickness = stroke.Thickness * HOVER_THICKNESS
			lit.Transparency = 1
			if hover then
				lit.Color = hover
			end
			lit.Parent = face

			local ring = stroke:Clone()
			ring.Name = NAMES.Halo
			ring.Enabled = false
			ring.Thickness = stroke.Thickness * HALO_THICKNESS
			--[[ SOLID, whatever the stroke it was cut from is. The card's outer stroke is a white
				highlight at half transparency and a halo inherited from it comes out as a pale
				wash — which reads as the card being greyed out rather than picked. ]]
			ring.Transparency = 0
			if halo then
				ring.Color = halo
			end
			ring.Parent = face
			return true
		end
	end
	return false
end

--[[ Build both wings onto `page`, replacing any that are already there. Returns a sentence about
	what happened, and false with a sentence when the page is not a car screen.

	IDEMPOTENT, like every other V2 build command: run it twice and the second run destroys the first
	run's wings before it makes its own. ]]
function Panel.build(page: GuiObject): (boolean, string)
	local main = page:FindFirstChild("Main")
	local list = main and main:FindFirstChildOfClass("ScrollingFrame")
	local card = list and list:FindFirstChild(CARD_NAME)
	if not (card and card:IsA("GuiObject")) then
		return false,
			string.format("%s has no `Main.ScrollingFrame.%s`; it is not a car screen.", page:GetFullName(), CARD_NAME)
	end

	local kit, why = findKit()
	if not kit then
		return false, string.format("The kit is not where it should be: %s", why)
	end
	local row = questRow(kit)
	if not row then
		return false,
			string.format(
				"The kit's `%s` has no row with a `%s` in it; there is nothing to cut the bars from.",
				QUEST_FRAME,
				QUEST_BAR
			)
	end

	for _, name in { NAMES.Left, NAMES.Right } do
		local existing = page:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end

	local pixels = wingPixels(page)

	local left = Instance.new("Frame")
	left.Name = NAMES.Left
	left.AnchorPoint = Vector2.new(1, 0.5)
	left.Position = UDim2.fromScale(-WING_GAP, WING_MIDDLE)
	left.Size = UDim2.fromScale(WING_WIDTH, WING_HEIGHT)
	--- Hidden until a car is picked. `Components/CarDetailV2` owns both flags from here on.
	left.Visible = false
	dress(page, left)
	buildLeft(page, left, card, row, pixels)
	left.Parent = page

	local right = Instance.new("Frame")
	right.Name = NAMES.Right
	right.AnchorPoint = Vector2.new(0, 0.5)
	right.Position = UDim2.fromScale(1 + WING_GAP, WING_MIDDLE)
	right.Size = UDim2.fromScale(WING_WIDTH, WING_HEIGHT)
	right.Visible = false
	dress(page, right)
	buildRight(page, right, card, row, pixels)
	right.Parent = page

	--- The saturated end of the page's own ramp, which is BOTH rings: see `HALO_THICKNESS` for why
	--- the picked card no longer answers in a colour of its own.
	local blue = rampEnds(page:FindFirstChildOfClass("UIGradient"))
	local dressed = dressCard(card, blue, blue)

	return true,
		string.format(
			"%s: `%s` and `%s` at %.3f x %.3f of the page, %d stat rows, %s.",
			page.Name,
			NAMES.Left,
			NAMES.Right,
			WING_WIDTH,
			WING_HEIGHT,
			#InventoryConfig.Stats,
			if dressed
				then string.format("`%s` and `%s` added to %s", NAMES.Halo, NAMES.Select, CARD_NAME)
				else "NOT added (the card has no face to put them on)"
		)
end

return Panel
