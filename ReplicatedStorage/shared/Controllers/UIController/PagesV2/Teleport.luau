--[[
	Teleport page, V2 - THE WORLD SELECT SCREEN  (client)
	-----------------------------------------------------
	"Where do you want to go." One row per world in `WorldConfig`: a picture of its road, its name,
	a status line and a press. The second screen of Play: the HUD's Play button opens this, a row's
	Play hands over to the car picker, and a car there starts the run.

	`BuildTeleportV2` (Command Runner) cloned the kit's `TeleportUI` into `MainUIV2.Pages.Teleport`,
	named the row's parts, borrowed the kit's grey face for a world you cannot press yet and put a
	weather badge on the picture. Its header carries every decision about the SHAPE of this screen;
	this file is the behaviour. Still called `Teleport` because `WorldConfig.PageName` is.

	=== THE THREE RULES THE SHIPPING PAGE HAS, UNCHANGED ======================================

	1. NOTHING HERE DECIDES ANYTHING. A row's buttons carry `Action = TeleportToWorld` and the row
	   carries `World = <index>`, so a press is `Components/Button` publishing the action and
	   `WorldController` resolving the world off the row. The controller decides whether that press
	   plays, asks to confirm or buys, and a world you own hands over to
	   `StartCarController:choose(index)` from there. This page never names either controller's
	   press and never calls it. `RaceEntryController` shuts it on `RaceStart`, and opening the car
	   picker shuts it too, because `UIController` only keeps one page up.

	2. THE CONTROLLER OWNS THE STATE AND THIS PAGE OWNS THE WORDS. `WorldController:cardState` says
	   what a press would do; everything a row SAYS about that is below. No optimistic repaint: the
	   unlock, the progress, the cash and the chosen world are all replicated attributes, and
	   `WorldConfig.StateEvent` fires when any of them lands.

	3. THE WEATHER BADGE IS HOW A PLAYER FINDS THE STORM. An event is announced to the players in its
	   own world and to nobody else (`WeatherConfig.StartedEvent`), so this screen is the only place
	   the other worlds' weather is visible, and it repaints on the weather attribute directly
	   because that one is not part of the world state. Since 2026-10-14 only on a world you OWN
	   (see "EVERY OPEN ROW SAYS WHEN ITS WEATHER IS" below): a storm you cannot drive into is noise.

	=== WHAT THE KIT TOOK OVER ===============================================================

	THE CAROUSEL. The shipping page is three cards at the artist's size behind a clipping track,
	two arrow discs hanging off the panel, a drag, a flick and a wheel, and it exists because the old
	art drew three cards for five worlds. The kit draws a list, and all five worlds fit in its window
	with no scrolling at all, so every line of that is gone and so is the need to open "focused on
	your world": your world is on screen because every world is.

	THE BUTTON'S FOUR CAPTIONS. The old card had one button that said PLAY, a price, a requirement or
	CONFIRM?. The kit gives a row two lines and two coloured buttons, so the fact goes on the status
	line and the verb goes on the button: blue Play for a world you own, green Buy (then Confirm?)
	for one you can buy, and the kit's spent grey for one you cannot press yet.

	=== AND WHAT IS DELIBERATELY NOT HERE ====================================================

	  • THE BAND OF CARS AND THEIR ODDS (`TrafficConfig.chancesFor`). The shipping card drifts live
	    car viewports across the foot of a 314x523 card; a kit row is about 600x88 and every part of
	    it is already spoken for. The numbers are real and worth showing, so the honest home is a
	    press-to-open panel or the collection screen rather than a squeeze. Carried in the notes as
	    the known gap.
	  • THE WORLD'S COLOUR ROUND ITS CARD. That was the boss's mockup on the old kit, and the kit
	    palette as shipped is the house style now (open question 2), so a row keeps the artist's rim.

	=== ALEAFO'S CARDS, 2026-09-30 ===========================================================

	Each row wears its world's painted card (`UIAssets.WorldCards`): the road as the picture and
	the panorama washed out behind the row, both looked up by MAP like the old road shots. A map
	with no card keeps the road shot and no backdrop. The status line and the faces carry glyphs
	as the mockup draws them:

	    You are here        green pin         Play face         triangle
	    a price             the banknote      Buy face          none
	    Finish Desert: 0%   white lock        grey Locked       lock
	    Owned               none              grey In a race    none

	The requirement is written in WHITE now, not the grey of the face beside it: on a painted
	backdrop the grey went muddy, and the mockup writes it white. And a locked world's picture is
	no longer faded; the lock on the line and on the button already says "not yet".

	=== EVERY OPEN ROW SAYS WHEN ITS WEATHER IS — 2026-10-14 =================================

	The owner, on this screen: "where is the countdown? we should have one here for each world". The
	badge said what was running and nothing about what was next.

	WHAT IT WAS, three times over, the same day: a line of text across the top of the road picture
	(a smudge on bright art), then a dark bar along the picture's bottom, then a dark strip under the
	status line with a LIVE / SOON tag, the glyph, the name and the clock.

	WHAT IT IS, Aleafo's second mockup ("do that for upcoming events; we do the icon for when it's
	live, with a hover tooltip that shows more info"):
	  COMING  a red BANNER across the foot of the row, "UPCOMING EVENT 3:00" (`_paintClock`), and the
	          rest of the row squeezed into the space above it (`_layoutBanner`). The clock turns
	          gold inside `WeatherConfig.Countdown.SoonWithin`.
	  LIVE    no banner; the weather badge on the picture is the sign, and hovering it (tapping, on a
	          phone) opens a TOOLTIP with the event, what its cars are worth and the time left
	          (`_tooltipFor`). A running event outranks the next one.

	ONLY ON A WORLD YOU OWN (Aleafo: "I think we don't show it on locked worlds"; the owner: "I don't
	own desert yet so it shouldn't show", and the same for the badge). A world you could buy counts
	as not owned. `entry.locked` is that one rule, and `_paintWeather` reads it too.

	THE ROWS ARE TALLER (Aleafo: "make the world templates larger in height"). `ROW_GROW` multiplies
	the kit row's authored height, so the list scrolls a little where all five used to fit; the road
	picture is `Crop`, so a taller box crops it rather than stretching it.
	It ticks four times a second while the page is up and costs nothing while it is shut.
	`WeatherConfig.Countdown.Enabled = false`: no banners and no tooltip, the rows exactly as before.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local KitPage = require(script.Parent.Parent.KitPage)

local Page = KitPage.extend(WorldConfig.PageName)

--- The kit's row, as `BuildTeleportV2` left it.
local ROW_NAME = "WorldRow"

--[[ Every row is named after its world's INDEX, `World1` to `World5`, never after the order it was
	stamped in. `TutorialConfig.TeleportPathV2` walks to `World1`'s Play button to point at the city,
	and a name that meant "first row" would move the arrow the day the list is ever sorted. ]]
local ROW_PREFIX = "World"

--[[ The words. The controller says what a press would do; these say it to the player.

	`Here` REPLACES `Owned` ON THE WORLD YOU ARE IN. The shipping carousel said that by opening on
	your world; a list that shows all five at once has to say it in words, and the status line is
	the free place to say it. The button still says Play, because the world you are already in is
	the one most players pick most of the time.

	`Needs` is the shipping button's requirement, moved to the line: the road you have to finish and
	how far down it you are, so it moves as you drive. `NeedsPart` is the form for a softened rule
	(`RequirePrevious` below 1), which has to say both numbers or the bare one is a lie by omission. ]]
local TEXT = {
	Play = "Play",
	Buy = "Buy",
	Confirm = "Confirm?",
	Locked = "Locked",
	Racing = "In a race",
	Owned = "Owned",
	Here = "You are here",
	--- WAS "Finish %s: %s", which did not say finishing means driving to the end (2026-10-20).
	Needs = "Drive to end of %s: %s",
	NeedsPart = "%s: %s / %s",
}

--[[ The requirement line's colour: plain white under the row's own navy outline (see the header).
	A ColorSequence because the line is coloured through its UIGradient, like the green. ]]
local WHITE_RAMP = ColorSequence.new(Color3.new(1, 1, 1))

--[[ Where a face's caption sits beside its glyph, as fractions of the face. Without the glyph it
	goes back to where the kit drew it, read off the face when the row is made. ]]
local CAPTION_WITH_ICON_X = 0.6
local CAPTION_WITH_ICON_WIDTH = 0.62
--- Space between a face's glyph and its caption, as a fraction of the face's width.
local CAPTION_ICON_GAP = 0.03
--- Space kept between the title/status line and the buttons, as a fraction of the row's width.
local BUTTON_CLEARANCE = 0.015

local NBSP = utf8.char(0xA0)

--- Every row's height over the kit's authored one (header, "THE ROWS ARE TALLER"). 1: the kit's.
local ROW_GROW = 1.3
--[[ The upcoming banner (header): its share of the row's height at the foot, and the inset from the
	row's edges. Everything else in the row is squeezed into the `1 - BANNER_SHARE` above it while it
	shows, so the two can never overlap. ]]
local BANNER_SHARE = 0.24
local BANNER_INSET = 0.012
local BANNER_RED = Color3.fromRGB(226, 32, 52)
local BANNER_SOON = Color3.fromRGB(255, 214, 60)
--- How long a tap holds the live tooltip open on a phone, which has no "mouse left" to close it.
local TOOLTIP_TAP_SECONDS = 3

--[[ Non-breaking every space. `TextScaled` would sooner wrap "You are here" onto a second line of
	a box drawn for one than shrink it, and every label on this row is one line by design. ]]
local function oneLine(text: string): string
	return (string.gsub(text, " ", NBSP))
end

--[[ "62%", floored. Floored because a row that says 100% while its button is still grey is worse than
	one that says 99% for a few hundred studs longer; the shipping page's rule, kept. ]]
local function percent(fraction: number): string
	return string.format("%d%%", math.floor(fraction * 100))
end

--- The requirement line for a world whose previous road is not finished.
local function needsText(state): string
	local required = state.required or 1
	local progress = math.clamp(state.progress or 0, 0, required)
	local road = state.previousShort or state.previousName or "?"
	if required < 1 then
		return oneLine(string.format(TEXT.NeedsPart, road, percent(progress), percent(required)))
	end
	return oneLine(string.format(TEXT.Needs, road, percent(progress)))
end

-- === Building ===============================================================

function Page.initialize(self)
	--- The kit's text caps are pixels for a 1080-tall screen; this keeps them in proportion above it.
	KitPage.scaleTextCaps(self.PageUI)

	self.Player = (self.UIController and self.UIController.Player) or Players.LocalPlayer

	--[[ One record per world, keyed by index. NOT `self._rows`, which is `KitPage`'s own list of
		the rows it has stamped: a page extending it owns the names it invents and nothing else. ]]
	self._worlds = {} :: { [number]: any }

	self:_readRamps()

	--- Taller rows (header). Before any row is stamped, so every row is born at the new height.
	if self._rowScale[ROW_NAME] then
		self._rowScale[ROW_NAME] *= ROW_GROW
		self:_syncMetrics()
	end

	for index in WorldConfig.Worlds do
		local entry = self:_makeRow(index)
		if entry then
			self._worlds[index] = entry
		end
	end

	--[[ Painted before the page is ever opened, so `UIController`'s preload, which runs straight
		after this, finds five road pictures to fetch and the first open is a finished screen. ]]
	self:_repaint()

	--[[ Everything a row is drawn from except the weather arrives as this one event:
		`WorldController` publishes it for the world you are in, what you own, how far down each
		road you have driven, your cash, a race starting or ending and a confirm timing out. ]]
	Dispatcher:Subscribe(WorldConfig.StateEvent, function()
		self:_repaintIfShown()
	end)
	workspace:GetAttributeChangedSignal(WeatherConfig.Attribute):Connect(function()
		self:_repaintIfShown()
	end)

	--- The weather clocks tick on their own (header); a whole repaint every quarter second would not.
	task.spawn(function()
		while true do
			if self.PageUI.Visible then
				self:_paintClocks()
			end
			task.wait(0.25)
		end
	end)
end

--[[ The two colours the status line is written in, read off the artist's own row rather than typed
	here: the green the kit prints "Owned" and a price in, and the spent grey of `DisabledBtn` for
	a requirement. The grey on the line and the grey on the button beside it are then one colour
	by construction. ]]
function Page:_readRamps()
	local template = self.Templates[ROW_NAME]
	local status = template and template:FindFirstChild("Status")
	local green = status and status:FindFirstChildOfClass("UIGradient")
	local btns = template and template:FindFirstChild("Btns")
	local disabled = btns and btns:FindFirstChild("DisabledBtn")
	local grey = disabled and disabled:FindFirstChildOfClass("UIGradient")
	self._ramps = {
		live = green and green.Color,
		locked = grey and grey.Color,
		requirement = WHITE_RAMP,
	}
end

--[[ One row, for one world. Its identity (the name, the picture, the `World` attribute) never
	changes, so it is written once here; `_paintRow` writes everything that does.

	The clone carries its tags, so `PlayBtn` and `BuyBtn` are already `UIButton`s with hover, sound,
	a gamepad highlight and the `Action` the controller listens for. Nothing here wires a press. ]]
function Page:_makeRow(index: number)
	local row = self:newRow(ROW_NAME)
	if not row then
		return nil
	end
	row.Name = ROW_PREFIX .. index
	row.LayoutOrder = index
	--- The attribute `WorldController._worldOfButton` walks up to. Header rule 1.
	row:SetAttribute(WorldConfig.WorldAttribute, index)

	local btns = row:FindFirstChild("Btns")
	local picture = row:FindFirstChild("Image")
	local status = row:FindFirstChild("Status")
	local entry = {
		index = index,
		row = row,
		title = row:FindFirstChild("Title"),
		status = status,
		statusIcon = row:FindFirstChild("StatusIcon"),
		backdrop = row:FindFirstChild("Backdrop"),
		map = picture and picture:FindFirstChild("Map"),
		weather = picture and picture:FindFirstChild("Weather"),
		play = btns and btns:FindFirstChild("PlayBtn"),
		buy = btns and btns:FindFirstChild("BuyBtn"),
		disabled = btns and btns:FindFirstChild("DisabledBtn"),
	}

	if entry.title and entry.title:IsA("TextLabel") then
		entry.title.Text = oneLine(string.upper(WorldConfig.displayName(index)))
	end
	--[[ The picture of the road and the panorama behind the row, looked up by MAP and not by
		index, so a ladder moved onto another road takes its pictures with it. A map with no card
		falls back to its road shot (or the placeholder) and an empty backdrop. ]]
	local map = WorldConfig.mapFor(index)
	local card = map and UIAssets.WorldCards[map]
	if entry.map and entry.map:IsA("ImageLabel") then
		entry.map.Image = UIAssets.url(if card then card.Thumb else UIAssets.worldThumb(map))
	end
	if entry.backdrop and entry.backdrop:IsA("ImageLabel") then
		entry.backdrop.Image = if card then UIAssets.url(card.Backdrop) else ""
	end

	--[[ The upcoming banner and the live tooltip (header). Their words are cloned from the badge's
		multiplier label, so they are the kit's type and outline. A row whose badge has no label gets
		neither: a row without a clock, not a banner in the wrong font. ]]
	local countdown = WeatherConfig.Countdown
	local multiplier = entry.weather and entry.weather:FindFirstChild("Multiplier")
	if countdown and countdown.Enabled and multiplier and multiplier:IsA("TextLabel") then
		self._wordStyle = self._wordStyle or multiplier
		entry.clock = self:_makeBanner(row, multiplier)
		self:_hookTooltip(entry)
	end

	--[[ The title and the status line END BEFORE THE BUTTONS. Both are TextScaled, so the taller rows
		(`ROW_GROW`) set them larger and a long name ("FOREST MOUNTAINS") filled its box right up to the
		Locked button (2026-10-16). Shrinking the box makes TextScaled pick a smaller size instead. Before
		`statusHome` is read, so the glyph slide works from the clamped box. Scale-built boxes only,
		which is what `BuildTeleportV2` makes; anything with an offset is left alone. ]]
	if btns and btns:IsA("GuiObject") and btns.Position.X.Offset == 0 then
		local limit = btns.Position.X.Scale - btns.AnchorPoint.X * btns.Size.X.Scale - BUTTON_CLEARANCE
		for _, label in { entry.title, status } do
			if label and label:IsA("GuiObject") and label.Size.X.Offset == 0 and label.Position.X.Offset == 0 then
				local left = label.Position.X.Scale - label.AnchorPoint.X * label.Size.X.Scale
				local width = math.min(label.Size.X.Scale, limit - left)
				if width > 0 and width < label.Size.X.Scale then
					label.Size = UDim2.new(width, 0, label.Size.Y.Scale, label.Size.Y.Offset)
					label.Position = UDim2.new(left + label.AnchorPoint.X * width, 0, label.Position.Y.Scale, label.Position.Y.Offset)
				end
			end
		end
	end

	--- The status line's box as built, to slide back to when its glyph hides.
	if status and status:IsA("GuiObject") then
		entry.statusHome = { position = status.Position, size = status.Size }
	end

	--- Each face's caption box as the kit drew it, to put back when its glyph hides.
	entry.captionHome = {}
	for _, face in { entry.play, entry.buy, entry.disabled } do
		local caption = face and face:FindFirstChild("Title")
		if caption and caption:IsA("GuiObject") then
			entry.captionHome[face] = { position = caption.Position, size = caption.Size }
		end
	end

	return entry
end

-- === Painting ===============================================================

--[[ A page nobody is looking at does not repaint five rows on every cash tick. `StartOpenThread`
	repaints on the way in, which is the one moment a stale row could be seen. ]]
function Page:_repaintIfShown()
	if self.PageUI.Visible then
		self:_repaint()
	end
end

function Page:_repaint()
	local controller = Shard.get("WorldController")
	local here = if controller then controller:worldOf() else WorldConfig.resolve(self.Player:GetAttribute(WorldConfig.WorldAttribute))
	--- Decoded once for all five rows rather than once a row: it is one string and one answer.
	local weather = WeatherConfig.decode(workspace:GetAttribute(WeatherConfig.Attribute))

	for index, entry in self._worlds do
		local state = if controller
			then controller:cardState(index)
			else { action = "play", label = "play", enabled = true }
		--- Only a world you OWN shows its weather, strip or badge (header); "racing" keeps what it knew.
		if state.label ~= "racing" then
			entry.locked = state.label ~= "play"
		end
		self:_paintRow(entry, state, index == here)
		self:_paintWeather(entry, weather[index])
	end
end

--[[ Everything a row shows about what a press would do. Header rule 2: `state` is the controller's
	answer and this only turns it into words and faces.

	ONE FACE SHOWS AT A TIME, and all three are written on every paint so a flip never uncovers a
	stale caption.

	    play      Owned / You are here       blue Play
	    buy       $850.0K                    green Buy, whether or not the wallet covers it
	    confirm   $850.0K                    green Confirm?
	    needs     Finish Desert: 62%         grey Locked, a lock on both
	    racing    (left as it was)           grey In a race

	A PRICE YOU CANNOT MEET IS STILL A GREEN BUY (2026-09-30, Aleafo). It used to wear the grey face,
	and a grey Buy read as broken rather than as "not yet". Now the press offers the cash that closes
	the gap (`WorldController._onTeleportPressed`), so the button is live and looks it. The grey
	branch below is kept for a controller that ever answers a buy as not enabled. ]]
function Page:_paintRow(entry, state, isHere: boolean)
	local face, caption = "play", TEXT.Play
	local line, ramp = nil :: string?, self._ramps.live
	--- The status line's glyph (a `UIAssets.WorldsPage` key) and whether the face wears its own.
	--- Header table.
	local lineIcon, faceIcon = nil :: string?, true

	if state.label == "racing" then
		--- The line keeps whatever it said: the controller answers nothing else during a run, and the
		--- page is shut for the length of one anyway. So does its glyph.
		face, caption = "disabled", TEXT.Racing
		lineIcon, faceIcon = entry.lineIcon, false
	elseif state.label == "needs" then
		face, caption = "disabled", TEXT.Locked
		line, ramp = needsText(state), self._ramps.requirement
		lineIcon = "Lock"
	elseif state.label == "buy" or state.label == "confirm" then
		lineIcon, faceIcon = "Cash", false
		line = oneLine(GarageConfig.formatCash(state.cost or 0))
		if state.label == "confirm" then
			face, caption = "buy", TEXT.Confirm
		elseif state.enabled then
			face, caption = "buy", TEXT.Buy
		else
			face, caption = "disabled", TEXT.Buy
		end
	else
		line = oneLine(if isHere then TEXT.Here else TEXT.Owned)
		lineIcon = if isHere then "Pin" else nil
	end

	local status = entry.status
	if line and status and status:IsA("TextLabel") then
		status.Text = line
		local gradient = status:FindFirstChildOfClass("UIGradient")
		if gradient and ramp then
			gradient.Color = ramp
		end
	end

	self:_paintLineIcon(entry, lineIcon)
	self:_showFace(entry, face, oneLine(caption), faceIcon)
end

--[[ The glyph in front of the status line, or none, and the line slid over for it. The glyph sits
	where the line starts; the room it takes is `IconShift`, which `BuildTeleportV2` worked out from
	the row's shape, as a fraction of the row. ]]
function Page:_paintLineIcon(entry, key: string?)
	entry.lineIcon = key
	local icon, status, home = entry.statusIcon, entry.status, entry.statusHome
	local image = key and UIAssets.WorldsPage[key]
	if icon and icon:IsA("ImageLabel") then
		icon.Visible = image ~= nil
		if image then
			icon.Image = UIAssets.url(image)
		end
	end
	if status and home then
		--[[ `IconShift` was worked out for the kit's row aspect, and the glyph is sized off the row's
			HEIGHT, so `ROW_GROW` widens it by the same factor (2026-10-16: at 1.3 the lock sat on top of
			"Finish Desert"). Scaled here rather than in `BuildTeleportV2`, which never sees the grow. ]]
		local shift = if image then (status:GetAttribute("IconShift") or 0) * ROW_GROW else 0
		status.Position = home.position + UDim2.fromScale(shift, 0)
		status.Size = home.size - UDim2.fromScale(shift, 0)
	end
end

--[[ Show one of the row's three faces with a caption on it.

	THE GAMEPAD HIGHLIGHT FOLLOWS THE PRESS ACROSS A FLIP. Confirming a purchase is two A presses on
	`BuyBtn`, and the world arriving swaps that button for `PlayBtn` under the highlight. Left alone,
	the engine drops a selection whose button just hid and a console player is stranded with nothing
	lit; handed over, the highlight is already on Play, which is the next thing they want. Only when
	it was on this row's own button, so a repaint never pulls the highlight off somewhere else. ]]
function Page:_showFace(entry, which: string, caption: string, withIcon: boolean)
	local faces = { play = entry.play, buy = entry.buy, disabled = entry.disabled }
	local shown = faces[which]
	local selected = GuiService.SelectedObject

	for name, face in faces do
		if not (face and face:IsA("GuiObject")) then
			continue
		end
		face.Visible = name == which
		--- Only the Play and grey faces carry a glyph (`BuildTeleportV2`); the Buy face never does.
		local icon = face:FindFirstChild("Icon")
		local iconShown = withIcon and icon ~= nil
		if icon and icon:IsA("GuiObject") then
			icon.Visible = iconShown
		end
		local title = face:FindFirstChild("Title")
		if title and title:IsA("TextLabel") then
			title.Text = caption
			local home = entry.captionHome[face]
			if iconShown then
				local left = CAPTION_WITH_ICON_X - title.AnchorPoint.X * CAPTION_WITH_ICON_WIDTH
				local right = left + CAPTION_WITH_ICON_WIDTH
				--[[ Clear the glyph's measured right edge. The glyph is sized off the face's HEIGHT, so
					the taller rows (`ROW_GROW`) pushed it into the "L" of Locked (2026-10-16); a fixed
					share cannot know the face's shape. Not drawn yet (no size): the share alone. ]]
				if face.AbsoluteSize.X > 0 and icon and icon:IsA("GuiObject") then
					local iconRight = icon.Position.X.Scale + icon.AbsoluteSize.X * (1 - icon.AnchorPoint.X) / face.AbsoluteSize.X
					left = math.max(left, iconRight + CAPTION_ICON_GAP)
				end
				title.Position = UDim2.fromScale(left + title.AnchorPoint.X * (right - left), title.Position.Y.Scale)
				title.Size = UDim2.fromScale(right - left, title.Size.Y.Scale)
			elseif home then
				title.Position = home.position
				title.Size = home.size
			end
		end
	end

	local wasOurs = selected ~= nil and (selected == entry.play or selected == entry.buy)
	if wasOurs and selected ~= shown and shown and shown:IsA("GuiButton") then
		self:_handOver(shown)
	end
end

--[[ Put the highlight on a button that became visible this frame. The engine can refuse a target
	that has not rendered yet, so it is tried now and once more after the next frame, and the second
	try stands down if anything else has taken the highlight in between. ]]
function Page:_handOver(button: GuiButton)
	GuiService.SelectedObject = button
	if GuiService.SelectedObject == button then
		return
	end
	task.spawn(function()
		RunService.Heartbeat:Wait()
		local current = GuiService.SelectedObject
		if (current == nil or not current.Visible) and button.Visible and self.PageUI.Visible then
			GuiService.SelectedObject = button
		end
	end)
end

--[[ The weather badge on a row's picture. Header rule 3.

	AN EVENT IS SHOWN WHILE IT IS RUNNING, judged against the server's clock and not by the entry
	merely existing, so a badge never outlives its storm by a replication hop.

	THE NUMBER IS THE MUTATION'S, NOT THE EVENT'S: the glyph already says what the weather is, and
	the multiplier is the only reason to drive into it. An event with no mutation, or one worth x1,
	shows the glyph alone. An event with no glyph shows nothing, because every event in
	`WeatherConfig` has one and a client a deploy behind a server never decodes an event it does not
	know (`WeatherConfig.decode` drops it). ]]
function Page:_paintWeather(entry, running)
	local badge = entry.weather
	if not (badge and badge:IsA("GuiObject")) then
		return
	end

	--- Not on a world you do not own (header, "ONLY ON A WORLD YOU OWN").
	local event = not entry.locked and running and workspace:GetServerTimeNow() < running.endsAt and WeatherConfig.eventOf(running.event)
	local glyph = event and WeatherConfig.iconOf(event.Key)
	if not glyph then
		badge.Visible = false
		return
	end

	local icon = badge:FindFirstChild("Icon")
	if icon and icon:IsA("ImageLabel") then
		icon.Image = UIAssets.url(glyph)
	end

	local label = badge:FindFirstChild("Multiplier")
	if label and label:IsA("TextLabel") then
		local mutation = WeatherConfig.MutationOfEvent[event.Key]
		local value = if mutation then WeatherConfig.valueMultiplierOf(mutation) else 1
		label.Text = if value > 1 then WeatherConfig.formatMultiplier(value) else ""
	end

	badge.Visible = true
end

--- Every row's weather clock, from the wire for a running event and the schedule for the next.
function Page:_paintClocks()
	local now = workspace:GetServerTimeNow()
	local running = WeatherConfig.decode(workspace:GetAttribute(WeatherConfig.Attribute))
	for index, entry in self._worlds do
		self:_paintClock(entry, running[index], WeatherConfig.nextScheduled(index, now), now)
	end
	if self._tipEntry then
		self:_tooltipFor(self._tipEntry)
	end
end

--- A label in the badge's own type (`_wordStyle`), its size cap and gradient taken off.
local function words(style: TextLabel, name: string, parent: Instance): TextLabel
	local label = style:Clone()
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = ""
	for _, class in { "UITextSizeConstraint", "UIGradient" } do
		local child = label:FindFirstChildOfClass(class)
		if child then
			child:Destroy()
		end
	end
	label.Parent = parent
	return label
end

--[[ One row's upcoming banner, hidden, and where every other part of the row was drawn, so
	`_layoutBanner` can squeeze them above it and put them back. ]]
function Page:_makeBanner(row: GuiObject, multiplier: TextLabel)
	local banner = Instance.new("Frame")
	banner.Name = "EventBanner"
	banner.AnchorPoint = Vector2.new(0.5, 1)
	banner.Position = UDim2.fromScale(0.5, 1 - BANNER_INSET * ROW_GROW)
	banner.Size = UDim2.fromScale(1 - BANNER_INSET * 2, BANNER_SHARE)
	banner.BackgroundColor3 = BANNER_RED
	banner.ZIndex = multiplier.ZIndex
	banner.Visible = false
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.45, 0)
	round.Parent = banner
	local rim = Instance.new("UIStroke")
	rim.Color = Color3.fromRGB(2, 30, 56)
	rim.Thickness = 2
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = banner
	local text = words(multiplier, "Text", banner)
	text.Position = UDim2.fromScale(0.5, 0.5)
	text.Size = UDim2.fromScale(0.8, 0.72)
	text.ZIndex = banner.ZIndex + 1

	--- Every part of the row the banner would sit on: all but the backdrop, which is the whole row.
	local homes = {}
	for _, child in row:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "Backdrop" then
			homes[child] = { y = child.Position.Y, h = child.Size.Y }
		end
	end
	banner.Parent = row
	return { banner = banner, text = text, homes = homes }
end

--[[ The banner in or out. In, every other part of the row is squeezed into the top `1 - BANNER_SHARE`
	(position and height scaled alike, which keeps each part's anchor where it was relative to the
	smaller box); out, each goes back to where the kit drew it. Only on a change. ]]
function Page:_layoutBanner(entry, shown: boolean)
	local clock = entry.clock
	if clock.shown == shown then
		return
	end
	clock.shown = shown
	clock.banner.Visible = shown
	local k = if shown then 1 - BANNER_SHARE - BANNER_INSET else 1
	for part, home in clock.homes do
		part.Position = UDim2.new(part.Position.X, UDim.new(home.y.Scale * k, home.y.Offset))
		part.Size = UDim2.new(part.Size.X, UDim.new(home.h.Scale * k, home.h.Offset))
	end
	--- `_paintLineIcon` slides the status line from `statusHome`; that home moves with it.
	local status = entry.status
	if entry.statusHome and status then
		entry.statusHome = {
			position = UDim2.new(entry.statusHome.position.X, status.Position.Y),
			size = UDim2.new(entry.statusHome.size.X, status.Size.Y),
		}
	end
end

--[[ One row's banner (header): up for the next event on a world you own, down while one runs (the
	badge says it then) or on a world you do not own. `entry.live` is kept for the tooltip. ]]
function Page:_paintClock(entry, running, upcoming, now: number)
	local clock = entry.clock
	if not clock then
		return
	end
	local live = running and running.endsAt > now and WeatherConfig.eventOf(running.event)
	entry.live = if live and not entry.locked then { event = live, endsAt = running.endsAt } else nil
	if entry.locked or live or not upcoming then
		self:_layoutBanner(entry, false)
		return
	end
	local seconds = math.max(0, math.floor(upcoming.startsAt - now))
	clock.text.Text = oneLine(string.format("UPCOMING EVENT %d:%02d", seconds // 60, seconds % 60))
	clock.text.TextColor3 = if seconds <= WeatherConfig.Countdown.SoonWithin then BANNER_SOON else Color3.new(1, 1, 1)
	self:_layoutBanner(entry, true)
end

-- === The live tooltip =======================================================

--[[ Hover (or tap) a live badge for the event's card. ONE tooltip for the page, parented to the page
	rather than the row: the list clips its rows, and a card hanging off the bottom row would be cut. ]]
function Page:_hookTooltip(entry)
	local badge = entry.weather
	if not (badge and badge:IsA("GuiObject")) then
		return
	end
	--[[ THE HOVER PAIR IGNORES TOUCH (2026-10-16: "on mobile/ipad it doesnt show when clicking it").
		Roblox fires `MouseEnter` for a tap too, so the card opened, and then the same tap's
		`InputBegan` below found it open and toggled it shut in that frame; the `MouseLeave` on lift
		could close it as well. A tap now goes through the tap path alone. ]]
	local function touching(): boolean
		return UserInputService:GetLastInputType() == Enum.UserInputType.Touch
	end
	badge.MouseEnter:Connect(function()
		if touching() then
			return
		end
		self:_tooltipFor(entry)
	end)
	badge.MouseLeave:Connect(function()
		if touching() then
			return
		end
		if self._tipEntry == entry then
			self:_tooltipFor(nil)
		end
	end)
	badge.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if self._tipEntry == entry then
			self:_tooltipFor(nil)
			return
		end
		self:_tooltipFor(entry)
		local token = {}
		self._tipToken = token
		task.delay(TOOLTIP_TAP_SECONDS, function()
			if self._tipToken == token and self._tipEntry == entry then
				self:_tooltipFor(nil)
			end
		end)
	end)
end

--- The card, built on first use in the badge's type: the event, what its cars are worth, the time left.
function Page:_tooltip()
	if self._tip then
		return self._tip
	end
	local frame = Instance.new("Frame")
	frame.Name = "EventTooltip"
	frame.AnchorPoint = Vector2.new(0, 0.5)
	frame.Size = UDim2.fromScale(0.34, 0.15)
	frame.BackgroundColor3 = Color3.fromRGB(2, 30, 56)
	frame.BackgroundTransparency = 0.08
	frame.ZIndex = 50
	frame.Visible = false
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.14, 0)
	round.Parent = frame
	local rim = Instance.new("UIStroke")
	rim.Color = Color3.new(1, 1, 1)
	rim.Thickness = 2
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = frame
	local tip = { frame = frame }
	for i, name in { "Event", "Payoff", "Time" } do
		local label = words(self._wordStyle, name, frame)
		label.Position = UDim2.fromScale(0.5, 0.2 + (i - 1) * 0.3)
		label.Size = UDim2.fromScale(0.9, if i == 1 then 0.32 else 0.26)
		label.ZIndex = 51
		tip[name] = label
	end
	tip.Event.TextColor3 = BANNER_SOON
	frame.Parent = self.PageUI
	self._tip = tip
	return tip
end

--[[ Open the card on `entry`'s badge, or close it (nil). Re-placed and re-worded every tick while
	open (`_paintClocks`), so the clock counts down and the card follows the list as it scrolls. ]]
function Page:_tooltipFor(entry)
	self._tipEntry = entry
	if not (entry and entry.live and self._wordStyle) then
		self._tipEntry = nil
		if self._tip then
			self._tip.frame.Visible = false
		end
		return
	end
	local tip = self:_tooltip()
	local event = entry.live.event
	local seconds = math.max(0, math.floor(entry.live.endsAt - workspace:GetServerTimeNow()))
	tip.Event.Text = oneLine(string.upper(event.Name))
	local mutationKey = WeatherConfig.MutationOfEvent[event.Key]
	local mutation = mutationKey and WeatherConfig.mutationOf(mutationKey)
	tip.Payoff.Text = if mutation
		then oneLine(string.format("%s cars %s value", mutation.Name, WeatherConfig.formatMultiplier(WeatherConfig.valueMultiplierOf(mutationKey))))
		else ""
	tip.Payoff.TextColor3 = if mutation and typeof(mutation.Color) == "Color3" then mutation.Color else Color3.new(1, 1, 1)
	tip.Time.Text = oneLine(string.format("ENDS IN: %d:%02d", seconds // 60, seconds % 60))

	--- Beside the badge, in the page's own (scaled) space: screen pixels over the open tween's scale.
	local badge = entry.weather
	local page = self.PageUI
	local scale = page:FindFirstChildOfClass("UIScale")
	local k = if scale and scale.Scale > 0 then scale.Scale else 1
	local at = badge.AbsolutePosition - page.AbsolutePosition
	tip.frame.Position = UDim2.fromOffset((at.X + badge.AbsoluteSize.X + 6) / k, (at.Y + badge.AbsoluteSize.Y / 2) / k)
	tip.frame.Visible = true
end

-- === Open and close =========================================================

--[[ `UIController` calls this before its own scale tween. Repainted on the way in because the rows
	only follow the world state while the page is up (`_repaintIfShown`), and scrolled to the top in
	case a sixth world ever makes the list longer than its window. ]]
function Page:StartOpenThread()
	self:_repaint()
	self:_paintClocks()
	if self.List then
		self.List.CanvasPosition = Vector2.zero
	end
end

function Page:StartCloseThread()
	self:_tooltipFor(nil)
end

return Page
