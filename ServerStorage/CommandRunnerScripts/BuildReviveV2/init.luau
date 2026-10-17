--[[
	BuildReviveV2: Command Runner command

	Builds `StarterGui.MainUIV2.Screens.Revive`, the revive question, out of the Cartoony Kit's
	`PromptUI`. Phase 4 of `docs/NewUI-Migration-Plan.md`; the running record is
	`docs/NewUI-Migration-Notes.md` ("Revive question").

	Run `BuildMainUIV2` first: this fills in a shelf that already exists rather than creating one.
	`Screens.Revive` is destroyed and made again on every run, and nothing else on the shelf is
	touched, so it is safe beside the other Phase 4 commands and safe to re-run.

	=== A TEMPLATE, NOT A SCREEN ==============================================================

	Nothing draws this frame where it is built. The shelf is hidden, and `ReviveController` clones the
	template into its own `RespawnScreen` ScreenGui at `DisplayOrder` 999, under the race fade, which
	is the whole reason it cannot live inside `MainUIV2`. So the geometry written here is the geometry
	of that ScreenGui: full screen, `IgnoreGuiInset = true`, the same space the shipping screen was
	laid out in. The controller adds the scrim; the panel is all that is art.

	=== THE KIT DREW A YES/NO PROMPT, AND THIS IS ONE =========================================

	`PromptUI` is a header, a white card holding a sentence, and two buttons side by side: a pink
	`No Way!` on the left and a green `Yeah, Sure!` on the right. That is the question the shipping
	screen asks, drawn by the artist, so the mapping is one to one:

	  • the HEADER is the question, `KEEP GOING?`, which is what the shipping screen's biggest line
	    already was (`ReviveController`: "this screen ASKS, that screen REPORTS");
	  • the CARD's sentence is the stake, the distance driven, renamed `Stake`;
	  • the GREEN button is the offer, renamed `Revive`, with the price and the clock on it;
	  • the PINK button is the way out, renamed `Decline`, reading `END RUN`.

	The words are the shipping screen's own, in its capitals, which is the call every other Phase 4
	prompt made. Only the price changes, to the kit's Robux mark.

	The artist's order is kept, the way out on the left and the offer on the right.

	=== WHAT THIS COMMAND ACTUALLY CHANGES ===================================================

	  • THE X GOES. A header close button on a question with money on it is a THIRD answer, and it
	    is an ambiguous one: it could be read as "put this away and let me keep going" just as easily
	    as "end the run". The shipping screen has exactly two answers and a clock, so this has two.
	  • THE BUTTONS GROW AND THE SENTENCE SHRINKS. The kit's buttons are about a nineteenth of the
	    panel's area each, which is right for a party invite and wrong for the one button in this
	    game a player presses in a hurry, on a phone, with a countdown running. The card's sentence
	    here is three words, so its band gives up height to the buttons (`TITLE_*`, `BTNS_*`).
	  • THE OFFER IS WIDER THAN THE WAY OUT. The kit draws the two as equals. The shipping screen's
	    hierarchy is that the offer is plainly the loud one while the way out is plainly pressable,
	    and colour alone is half of that. `REVIVE_WIDTH` and `DECLINE_WIDTH` are the other half.
	  • EACH BUTTON SITS IN A SLOT. `Components/Button` puts its hover on a `UIScale` inside the
	    button, and only one `UIScale` on an instance takes effect, so the controller's press dip
	    lives on the slot around it. Same arrangement, same reason, as the shipping screen.
	  • THE CLOCK IS DRAWN ON THE OFFER. A `DrainTrack` with a `Drain` inside it along the bottom of
	    the green face, and a `Lit` wash over the face for the last fifth of the clock. The caption
	    moves up to make room, and the way out's caption moves up with it so the two words sit on one
	    line across the pair.
	  • THE PANEL SITS LOW. Anchored at its bottom edge near the foot of the screen, because the
	    wrecked car is in the middle of the frame and it is the argument for paying.

	=== AND A SECOND TEMPLATE: THE WRECK AS ONE SCREEN ========================================

	`Screens.WreckRevive` (`NewUIConfig.WreckPanel`, Aleafo's reference, 2026-09-30) is the same
	prompt grown into the whole ending: the run's results on the white card, the crashed car in the
	top right corner over the header, the two buttons BELOW the card on the blue, and a countdown line
	under the panel. It replaces both the revive question and the results screen after it, so it is
	taller (1.47:1 rather than the kit's 2.29:1) and sits in the middle of the screen.

	Every name `ReviveController._buildKit` binds is kept (`Header.Title`, `Main.Stake`, the slots,
	`Revive.Caption/Lit/DrainTrack`, `Decline.Label`), so one code path drives both. What is new:

	  • `CarSlot`, an empty box the controller asks `RaceUIController.buildWreckShot` to fill;
	  • `Main.Headline` (WRECKED), `Main.Ladder` (`Track.Fill`, `Ticks`, `Marker`), `Main.Cash`,
	    `Main.Stake` as the distance, and `Main.Strip.Text` for the near-miss tally;
	  • `Countdown`, the line under the panel.

	Text caps are written as each label's height on a 1080p screen, the kit's own rule
	(`KitPage.scaleTextCaps` scales them up from there).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local SHELF_NAME = "Screens"
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage

local ENTRY_NAME = "Revive"
local WRECK_ENTRY_NAME = "WreckRevive"
local KIT_FRAME = "PromptUI"

local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)

local NBSP = utf8.char(0xA0) -- TextScaled wraps rather than shrinks
local ROBUX = utf8.char(0xE002) -- the kit's own Robux mark; see the notes, "Shop"

--[[ Where the panel stands, in the RespawnScreen's full-screen space. The kit's `UIAspectRatioConstraint`
	(2.29:1) is kept, so the HEIGHT is what binds on every landscape screen and the width follows. ]]
local PANEL_ANCHOR = Vector2.new(0.5, 1)
local PANEL_POSITION = UDim2.fromScale(0.5, 0.9)
local PANEL_SIZE = UDim2.fromScale(0.62, 0.36)

--[[ The card, top to bottom, in its own scale. The kit's sentence band ran 0.09 to 0.46 and its
	buttons 0.62 to 0.91; the bottom margin (0.09) is kept and the buttons take what the sentence
	gives up. ]]
local TITLE_Y, TITLE_HEIGHT = 0.21, 0.26
local BTNS_Y, BTNS_HEIGHT = 0.675, 0.47

--- Across the button row, as fractions of it. With the kit's 0.02 gap they fill 0.96 of the row.
local REVIVE_WIDTH = 0.56
local DECLINE_WIDTH = 0.38

--- Both captions, raised off the button's centre so the drain has the bottom of the face.
local CAPTION_Y = 0.43
local CAPTION_SIZE = UDim2.fromScale(0.9, 0.5)
--- The way out's word is set smaller than the offer's, the same ranking the shipping screen gives it.
local DECLINE_CAPTION_SIZE = UDim2.fromScale(0.9, 0.4)
--- The kit caps its button captions at 32px for its small buttons; these are about twice as tall.
local CAPTION_MAX_TEXT = 64

--- The drain. Inset from the rounded ends rather than clipped, because a rounded corner is geometry.
local DRAIN_Y = 0.8
local DRAIN_SIZE = UDim2.fromScale(0.78, 0.1)
local KIT_NAVY = Color3.fromRGB(2, 30, 56) -- the kit's outline colour
local DRAIN_TRACK_REST = 0.45

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

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

--[[ Wrap a kit button in a transparent slot that takes its place in the row: the slot carries the
	layout order and the width, the button fills it at 1x1. See the header on why. ]]
local function slot(button: GuiObject, name: string, width: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromScale(width, 1)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.LayoutOrder = button.LayoutOrder
	frame.Parent = button.Parent

	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.5)
	button.Size = UDim2.fromScale(1, 1)
	button.Parent = frame
	return frame
end

--[[ THE GLOSS KEEPS ITS SHAPE WHEN THE BUTTON DOES NOT. A kit face's `BG.Slash` is sized in fractions
	of the button, its width of the button's WIDTH, so the slots above squeeze it: the kit's buttons
	are 5.5:1, the offer here is 4.1:1 and the way out 2.8:1, and `ScaleType.Fit` drew the double
	stripe at three quarters and a half of the kit's size. `BuildHudV2`'s Play had the same fault.

	So the slash is measured in button HEIGHTS on the kit's own face, before anything moves it, and
	written back once the panel is parented and the button has its new shape. ]]
local function slashOf(button: Instance): GuiObject?
	local bg = button:FindFirstChild("BG")
	local slash = bg and bg:FindFirstChild("Slash")
	return if slash and slash:IsA("GuiObject") then slash else nil
end

local function slashWidthInHeights(button: Instance?): number?
	local slash = button and slashOf(button)
	if not (slash and button and button:IsA("GuiObject")) or button.AbsoluteSize.Y <= 0 then
		return nil
	end
	return slash.Size.X.Scale * button.AbsoluteSize.X / button.AbsoluteSize.Y
end

local function fitSlash(button: GuiObject, widthInHeights: number?): boolean
	local slash = slashOf(button)
	local size = button.AbsoluteSize
	if not (slash and widthInHeights) or size.X <= 0 then
		return false
	end
	slash.Size = UDim2.new(widthInHeights * size.Y / size.X, 0, slash.Size.Y.Scale, 0)
	return true
end

local function retitle(label: TextLabel, name: string, text: string, size: UDim2, maxText: number?)
	label.Name = name
	label.Text = text
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, CAPTION_Y)
	label.Size = size
	local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
	if limit and maxText then
		limit.MaxTextSize = maxText
	end
end


-- === The one-screen wreck (`WreckRevive`) =====================================================

--[[ The panel, in the RespawnScreen's full-screen space. Its HEIGHT binds on every landscape screen
	(1.47:1 against 16:9), so the 0.56 is the number that sizes everything below. Centred a touch above
	the middle so the countdown line has room under it. ]]
local WRECK_PANEL_POSITION = UDim2.fromScale(0.5, 0.47)
local WRECK_PANEL_SIZE = UDim2.fromScale(0.9, 0.56)
local WRECK_PANEL_ASPECT = 1.47

-- Down the panel, in its own scale: the header band, the white card, the buttons on the blue.
local WRECK_HEADER_Y, WRECK_HEADER_H = 0.09, 0.14
local WRECK_CARD_Y, WRECK_CARD_H = 0.465, 0.56
local WRECK_BTNS_Y, WRECK_BTNS_H = 0.87, 0.16
--[[ Across the button row. Near equals, as the reference draws them, the offer a little the wider,
	and smaller than the reference with a real gap between them (Dylan, 2026-09-30: the pair sat too
	close). The gap is the row's `UIListLayout.Padding`, written here rather than left at the kit's 0.02. ]]
local WRECK_REVIVE_WIDTH = 0.45
local WRECK_DECLINE_WIDTH = 0.41
local WRECK_BTN_GAP = 0.06

--[[ Down the card, in its own scale, as (centre, height). The reference's order: the word, the
	ladder, the money, the distance, and the tally in a pale strip at the foot. ]]
local ROW = {
	Headline = { 0.13, 0.17 },
	Ladder = { 0.345, 0.055 },
	Cash = { 0.525, 0.2 },
	Stake = { 0.695, 0.1 },
	Strip = { 0.865, 0.16 },
}
local LADDER_WIDTH = 0.82
local STRIP_WIDTH = 0.82
local STRIP_TEXT_SIZE = UDim2.fromScale(0.94, 0.62)

-- The crashed car, over the header's right end and the card's top edge. Width-bound.
local CAR_SLOT_POSITION = UDim2.fromScale(0.8, 0.06)
local CAR_SLOT_SIZE = UDim2.fromScale(0.36, 1)
local CAR_SLOT_ASPECT = 1.35

-- The line under the panel.
local COUNTDOWN_POSITION = UDim2.fromScale(0.5, 1.075)
local COUNTDOWN_SIZE = UDim2.fromScale(0.9, 0.075)

--- The reference's colours: gold money, a slate track, a pale strip with slate type.
local GOLD = Color3.fromRGB(255, 203, 31)
local TRACK_GREY = Color3.fromRGB(88, 92, 104)
local STRIP_FILL = Color3.fromRGB(214, 224, 243)
local STRIP_INK = Color3.fromRGB(74, 88, 118)

--- How tall a piece of the panel is on a 1080p screen, which is what a kit text cap is.
local function capFor(...: number): number
	local height = WRECK_PANEL_SIZE.Y.Scale * 1080
	for _, fraction in { ... } do
		height *= fraction
	end
	return math.max(8, math.round(height))
end

--- A copy of the card's kit label (Fredoka, white, the navy outline), named, placed and capped.
local function rowLabel(source: TextLabel, parent: Instance, name: string, row: { number }, text: string, color: Color3): TextLabel
	local label = source:Clone()
	label.Name = name
	label.Text = text
	label.TextColor3 = color
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, row[1])
	label.Size = UDim2.fromScale(0.95, row[2])
	label.TextScaled = true -- NOT TextWrapped = false, which switches TextScaled off; the NBSPs keep it on one line
	local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
	if limit then
		limit.MaxTextSize = capFor(WRECK_CARD_H, row[2])
	end
	label.Parent = parent
	return label
end

local function frame(name: string, parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	for key, value in props do
		(f :: any)[key] = value
	end
	f.Parent = parent
	return f
end

local function outline(parent: Instance, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = KIT_NAVY
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
end

--[[ Build `Screens.WreckRevive` from the kit's prompt. Answers the panel, or nil and why. The
	buttons go through the same slot, caption, wash and drain construction as `Revive`'s, so the
	controller's press, hover, lock and urgency code runs on it unchanged. ]]
local function buildWreckPanel(kitFrame: Instance, shelf: Instance, acceptSlash: number?, declineSlash: number?): (Frame?, string?)
	local panel = kitFrame:Clone() :: Frame
	local header = panel:FindFirstChild("Header") :: Frame
	local main = panel:FindFirstChild("Main") :: Frame
	local btns = main and main:FindFirstChild("Btns") :: Frame
	local accept = btns and btns:FindFirstChild("AcceptBtn") :: GuiObject
	local decline = btns and btns:FindFirstChild("DeclineBtn") :: GuiObject
	local sentence = main and main:FindFirstChild("Title") :: TextLabel
	local title = header and header:FindFirstChild("Title") :: TextLabel
	if not (accept and decline and sentence and title) then
		panel:Destroy()
		return nil, "the kit's PromptUI is not the expected shape"
	end

	local existing = shelf:FindFirstChild(WRECK_ENTRY_NAME)
	if existing then
		existing:Destroy()
	end

	panel.Name = WRECK_ENTRY_NAME
	panel.Visible = true
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = WRECK_PANEL_POSITION
	panel.Size = WRECK_PANEL_SIZE
	local aspect = panel:FindFirstChildOfClass("UIAspectRatioConstraint")
	if aspect then
		aspect.AspectRatio = WRECK_PANEL_ASPECT
	end

	--[[ The checker is a square sized off the kit's 2.29:1 panel. Kept square on the new shape, and
		at the cell size it has on the 0.36-tall revive panel rather than growing with this one. ]]
	local bg = panel:FindFirstChild("BG")
	local checkers = bg and bg:FindFirstChild("CheckersBG")
	if checkers and checkers:IsA("GuiObject") then
		local tall = checkers.Size.Y.Scale * PANEL_SIZE.Y.Scale / WRECK_PANEL_SIZE.Y.Scale
		checkers.Size = UDim2.fromScale(tall / WRECK_PANEL_ASPECT, tall)
	end

	-- The question, in a taller band. No X, for the reason `Revive` has none.
	local close = header:FindFirstChild("CloseBtn")
	if close then
		close:Destroy()
	end
	header.Position = UDim2.fromScale(header.Position.X.Scale, WRECK_HEADER_Y)
	header.Size = UDim2.fromScale(header.Size.X.Scale, WRECK_HEADER_H)
	title.Text = "KEEP" .. NBSP .. "GOING?"
	local titleLimit = title:FindFirstChildOfClass("UITextSizeConstraint")
	if titleLimit then
		titleLimit.MaxTextSize = capFor(WRECK_HEADER_H, title.Size.Y.Scale)
	end

	-- The card, which now holds the run.
	main.Position = UDim2.fromScale(main.Position.X.Scale, WRECK_CARD_Y)
	main.Size = UDim2.fromScale(main.Size.X.Scale, WRECK_CARD_H)

	local dot = NBSP .. NBSP .. "·" .. NBSP .. NBSP
	rowLabel(sentence, main, "Headline", ROW.Headline, "WRECKED", Color3.new(1, 1, 1))
	rowLabel(sentence, main, "Cash", ROW.Cash, "+$143" .. dot .. "kept" .. NBSP .. "25%", GOLD)
	rowLabel(sentence, main, "Stake", ROW.Stake, "1,293m" .. NBSP .. "driven", Color3.new(1, 1, 1))
	sentence:Destroy()

	-- The ladder: a slate track, a gold fill the controller drives, its ticks, and the car riding it.
	local ladder = frame("Ladder", main, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, ROW.Ladder[1]),
		Size = UDim2.fromScale(LADDER_WIDTH, ROW.Ladder[2]),
	})
	local track = frame("Track", ladder, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = TRACK_GREY,
		BackgroundTransparency = 0,
		ZIndex = 1,
	})
	corner(track, UDim.new(1, 0))
	outline(track, 2)
	local fill = frame("Fill", track, {
		Size = UDim2.fromScale(0.45, 1),
		BackgroundColor3 = GOLD,
		BackgroundTransparency = 0,
		ZIndex = 2,
	})
	corner(fill, UDim.new(1, 0))
	frame("Ticks", ladder, { Size = UDim2.fromScale(1, 1), ZIndex = 3 })
	local markerSize = UIAssets.ResultsSize and UIAssets.ResultsSize.CarMarker
	local marker = Instance.new("ImageLabel")
	marker.Name = "Marker"
	marker.AnchorPoint = Vector2.new(0.5, 1)
	marker.Position = UDim2.fromScale(0.45, -0.15)
	marker.Size = UDim2.fromScale(1, 2.6)
	marker.BackgroundTransparency = 1
	marker.Image = UIAssets.url(UIAssets.Results.CarMarker)
	marker.ImageColor3 = GOLD
	marker.ZIndex = 4
	local markerAspect = Instance.new("UIAspectRatioConstraint")
	markerAspect.AspectRatio = if markerSize then markerSize.X / markerSize.Y else 256 / 169
	markerAspect.Parent = marker
	marker.Parent = ladder

	-- The tally strip: pale, rounded, slate type, the bonus in gold through rich text.
	local strip = frame("Strip", main, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, ROW.Strip[1]),
		Size = UDim2.fromScale(STRIP_WIDTH, ROW.Strip[2]),
		BackgroundColor3 = STRIP_FILL,
		BackgroundTransparency = 0,
	})
	corner(strip, UDim.new(0.3, 0))
	local stripText = Instance.new("TextLabel")
	stripText.Name = "Text"
	stripText.AnchorPoint = Vector2.new(0.5, 0.5)
	stripText.Position = UDim2.fromScale(0.5, 0.5)
	stripText.Size = STRIP_TEXT_SIZE
	stripText.BackgroundTransparency = 1
	stripText.FontFace = title.FontFace
	stripText.TextColor3 = STRIP_INK
	stripText.TextScaled = true -- NOT TextWrapped = false, which switches TextScaled off; the NBSPs keep it on one line
	stripText.RichText = true
	stripText.Text = "1" .. NBSP .. "near" .. NBSP .. "miss" .. dot .. "1" .. NBSP .. "rub"
	local stripLimit = Instance.new("UITextSizeConstraint")
	stripLimit.MaxTextSize = capFor(WRECK_CARD_H, ROW.Strip[2], STRIP_TEXT_SIZE.Y.Scale)
	stripLimit.Parent = stripText
	stripText.Parent = strip

	-- The buttons leave the card for the blue under it, the reference's layout.
	btns.Parent = panel
	btns.AnchorPoint = Vector2.new(0.5, 0.5)
	btns.Position = UDim2.fromScale(0.5, WRECK_BTNS_Y)
	btns.Size = UDim2.fromScale(main.Size.X.Scale, WRECK_BTNS_H)
	btns.ZIndex = 2
	-- The kit's row is a white strip the full-width buttons used to cover; with a gap, it would show.
	btns.BackgroundTransparency = 1
	local row = btns:FindFirstChildOfClass("UIListLayout")
	if row then
		row.Padding = UDim.new(WRECK_BTN_GAP, 0)
	end

	accept.Name = "Revive"
	slot(accept, "ReviveSlot", WRECK_REVIVE_WIDTH)
	local caption = accept:FindFirstChild("Title")
	if caption and caption:IsA("TextLabel") then
		retitle(caption, "Caption", "REVIVE" .. NBSP .. NBSP .. ROBUX .. "25", CAPTION_SIZE, CAPTION_MAX_TEXT)
		caption.Position = UDim2.fromScale(0.5, 0.47) -- no drain under it on this panel
	end
	local lit = frame("Lit", accept, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 2,
	})
	local faceCorner = accept:FindFirstChildOfClass("UICorner")
	corner(lit, if faceCorner then faceCorner.CornerRadius else UDim.new(0.15, 0))
	--[[ The drain is built and HIDDEN: the countdown line under the panel is this screen's clock. It
		stays so `_buildKit` binds one shape of button for both templates. ]]
	local drainTrack = frame("DrainTrack", accept, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, DRAIN_Y),
		Size = DRAIN_SIZE,
		Visible = false,
	})
	frame("Drain", drainTrack, { Size = UDim2.fromScale(1, 1) })

	decline.Name = "Decline"
	slot(decline, "DeclineSlot", WRECK_DECLINE_WIDTH)
	local label = decline:FindFirstChild("Title")
	if label and label:IsA("TextLabel") then
		retitle(label, "Label", "END" .. NBSP .. "RUN", CAPTION_SIZE, CAPTION_MAX_TEXT)
		label.Position = UDim2.fromScale(0.5, 0.47)
	end

	-- The crashed car's box, empty: the shot is made at runtime from the car that just wrecked.
	local carSlot = frame("CarSlot", panel, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = CAR_SLOT_POSITION,
		Size = CAR_SLOT_SIZE,
		ZIndex = 6,
	})
	local carAspect = Instance.new("UIAspectRatioConstraint")
	carAspect.AspectRatio = CAR_SLOT_ASPECT
	carAspect.Parent = carSlot

	-- The countdown, under the panel on the road: white kit type with the navy outline.
	local countdown = title:Clone()
	countdown.Name = "Countdown"
	countdown.AnchorPoint = Vector2.new(0.5, 0.5)
	countdown.Position = COUNTDOWN_POSITION
	countdown.Size = COUNTDOWN_SIZE
	countdown.TextXAlignment = Enum.TextXAlignment.Center
	countdown.TextScaled = true -- NOT TextWrapped = false, which switches TextScaled off; the NBSPs keep it on one line
	countdown.Text = "Racing" .. NBSP .. "again" .. NBSP .. "in" .. NBSP .. "8"
	local countdownLimit = countdown:FindFirstChildOfClass("UITextSizeConstraint")
	if countdownLimit then
		countdownLimit.MaxTextSize = capFor(COUNTDOWN_SIZE.Y.Scale)
	end
	countdown.Parent = panel

	panel.Parent = shelf
	fitSlash(accept, acceptSlash)
	fitSlash(decline, declineSlash)
	return panel, nil
end

return {
	Description = "Build StarterGui.MainUIV2.Screens.Revive from the Cartoony Kit's PromptUI: the revive question's template, with the X removed, bigger buttons in slots, and a drain on the offer. Also builds Screens.WreckRevive, the one-screen wreck with the run's results on it. Rebuilds both entries every run.",
	Tags = { "UI", "NewUI" },
	AutoRecordChanges = true,

	Arguments = {} :: Types.ArgumentType,

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
		if not kitFrame then
			out:error(string.format("%s has no `%s` to build from.", container:GetFullName(), KIT_FRAME))
			return
		end

		--- Off the kit's own buttons, before the clone: a clone has no parent and so no size. See `fitSlash`.
		local kitBtns = kitFrame:FindFirstChild("Main") and kitFrame.Main:FindFirstChild("Btns")
		local acceptSlash = slashWidthInHeights(kitBtns and kitBtns:FindFirstChild("AcceptBtn"))
		local declineSlash = slashWidthInHeights(kitBtns and kitBtns:FindFirstChild("DeclineBtn"))

		local panel = kitFrame:Clone() :: Frame
		local header = panel:FindFirstChild("Header")
		local main = panel:FindFirstChild("Main")
		local btns = main and main:FindFirstChild("Btns")
		local accept = btns and btns:FindFirstChild("AcceptBtn")
		local decline = btns and btns:FindFirstChild("DeclineBtn")
		local sentence = main and main:FindFirstChild("Title")
		local title = header and header:FindFirstChild("Title")
		if not (accept and decline and sentence and title) then
			out:error(string.format("The kit's %s is not the shape this command expects (Header.Title, Main.Title, Main.Btns.AcceptBtn/DeclineBtn).", KIT_FRAME))
			panel:Destroy()
			return
		end

		local existing = shelf:FindFirstChild(ENTRY_NAME)
		if existing then
			existing:Destroy()
		end

		panel.Name = ENTRY_NAME
		panel.Visible = true -- the shelf is what is hidden; a template that is itself hidden would clone hidden
		panel.AnchorPoint = PANEL_ANCHOR
		panel.Position = PANEL_POSITION
		panel.Size = PANEL_SIZE

		-- The question. No X: see the header.
		local close = header:FindFirstChild("CloseBtn")
		if close then
			close:Destroy()
		end
		title.Text = "KEEP" .. NBSP .. "GOING?"

		-- The stake, in a shorter band.
		sentence.Name = "Stake"
		sentence.Text = "2,140m" .. NBSP .. "driven"
		sentence.Position = UDim2.fromScale(sentence.Position.X.Scale, TITLE_Y)
		sentence.Size = UDim2.fromScale(sentence.Size.X.Scale, TITLE_HEIGHT)

		btns.Position = UDim2.fromScale(btns.Position.X.Scale, BTNS_Y)
		btns.Size = UDim2.fromScale(btns.Size.X.Scale, BTNS_HEIGHT)

		-- The offer.
		accept.Name = "Revive"
		slot(accept, "ReviveSlot", REVIVE_WIDTH)
		local caption = accept:FindFirstChild("Title")
		if caption and caption:IsA("TextLabel") then
			retitle(caption, "Caption", "REVIVE" .. NBSP .. NBSP .. ROBUX .. "25", CAPTION_SIZE, CAPTION_MAX_TEXT)
		else
			out:warn("The offer button has no `Title`; the price will have nowhere to go.")
		end

		--[[ The urgency wash, under the caption and over the art. White on the green face, so the
			button gets BRIGHTER as the clock runs out rather than fading toward the scrim. ]]
		local lit = Instance.new("Frame")
		lit.Name = "Lit"
		lit.AnchorPoint = Vector2.new(0.5, 0.5)
		lit.Position = UDim2.fromScale(0.5, 0.5)
		lit.Size = UDim2.fromScale(1, 1)
		lit.BackgroundColor3 = Color3.new(1, 1, 1)
		lit.BackgroundTransparency = 1
		lit.BorderSizePixel = 0
		lit.ZIndex = 2
		local faceCorner = accept:FindFirstChildOfClass("UICorner")
		corner(lit, if faceCorner then faceCorner.CornerRadius else UDim.new(0.15, 0))
		lit.Parent = accept

		local track = Instance.new("Frame")
		track.Name = "DrainTrack"
		track.AnchorPoint = Vector2.new(0.5, 0.5)
		track.Position = UDim2.fromScale(0.5, DRAIN_Y)
		track.Size = DRAIN_SIZE
		track.BackgroundColor3 = KIT_NAVY
		track.BackgroundTransparency = DRAIN_TRACK_REST
		track.BorderSizePixel = 0
		track.ZIndex = 3
		corner(track, UDim.new(1, 0))
		track.Parent = accept

		-- Anchored to the LEFT end: time runs out from one side.
		local drain = Instance.new("Frame")
		drain.Name = "Drain"
		drain.AnchorPoint = Vector2.new(0, 0.5)
		drain.Position = UDim2.fromScale(0, 0.5)
		drain.Size = UDim2.fromScale(1, 1)
		drain.BackgroundColor3 = Color3.new(1, 1, 1)
		drain.BorderSizePixel = 0
		drain.ZIndex = 3
		corner(drain, UDim.new(1, 0))
		drain.Parent = track

		-- The way out.
		decline.Name = "Decline"
		slot(decline, "DeclineSlot", DECLINE_WIDTH)
		local label = decline:FindFirstChild("Title")
		if label and label:IsA("TextLabel") then
			retitle(label, "Label", "END" .. NBSP .. "RUN", DECLINE_CAPTION_SIZE, CAPTION_MAX_TEXT)
		else
			out:warn("The decline button has no `Title`; it will be a blank pink button.")
		end

		panel.Parent = shelf

		local fitted = fitSlash(accept :: GuiObject, acceptSlash)
		fitted = fitSlash(decline :: GuiObject, declineSlash) and fitted
		if not fitted then
			out:warn("A button's gloss could not be measured (no `BG.Slash`, or the kit is not laid out); it keeps the kit's fractions.")
		end

		local untagged = 0
		for _, button in { accept, decline } do
			if not button:HasTag("UIButton") then
				untagged += 1
			end
		end
		if untagged > 0 then
			out:warn(string.format("%d button(s) are not tagged UIButton. Run PrepKitTemplate, then this again.", untagged))
		end

		out:print(
			string.format(
				"Built %s.%s.%s from the kit's %s: X removed, Revive (%.2f) and Decline (%.2f) in slots, drain and wash on the offer.",
				SCREEN_NAME,
				SHELF_NAME,
				ENTRY_NAME,
				KIT_FRAME,
				REVIVE_WIDTH,
				DECLINE_WIDTH
			)
		)

		local wreck, wreckWhy = buildWreckPanel(kitFrame, shelf, acceptSlash, declineSlash)
		if wreck then
			out:print(string.format("Built %s.%s.%s, the one-screen wreck (NewUIConfig.WreckPanel).", SCREEN_NAME, SHELF_NAME, WRECK_ENTRY_NAME))
		else
			out:warn(string.format("Could not build %s: %s.", WRECK_ENTRY_NAME, tostring(wreckWhy)))
		end

		pcall(function()
			props:SetSelection({ wreck or panel })
		end)
	end,
} :: Types.ScriptModule
