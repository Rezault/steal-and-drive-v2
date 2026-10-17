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
	   because that one is not part of the world state.

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
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
	Needs = "Finish %s: %s",
	NeedsPart = "%s: %s / %s",
}

--[[ The requirement line's colour: plain white under the row's own navy outline (see the header).
	A ColorSequence because the line is coloured through its UIGradient, like the green. ]]
local WHITE_RAMP = ColorSequence.new(Color3.new(1, 1, 1))

--[[ Where a face's caption sits beside its glyph, as fractions of the face. Without the glyph it
	goes back to where the kit drew it, read off the face when the row is made. ]]
local CAPTION_WITH_ICON_X = 0.6
local CAPTION_WITH_ICON_WIDTH = 0.62

local NBSP = utf8.char(0xA0)

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
		local shift = if image then status:GetAttribute("IconShift") or 0 else 0
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
				title.Position = UDim2.fromScale(CAPTION_WITH_ICON_X, title.Position.Y.Scale)
				title.Size = UDim2.fromScale(CAPTION_WITH_ICON_WIDTH, title.Size.Y.Scale)
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

	local event = running and workspace:GetServerTimeNow() < running.endsAt and WeatherConfig.eventOf(running.event)
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
		local value = if mutation then WeatherConfig.multiplierOf(mutation) else 1
		label.Text = if value > 1 then WeatherConfig.formatMultiplier(value) else ""
	end

	badge.Visible = true
end

-- === Open and close =========================================================

--[[ `UIController` calls this before its own scale tween. Repainted on the way in because the rows
	only follow the world state while the page is up (`_repaintIfShown`), and scrolled to the top in
	case a sixth world ever makes the list longer than its window. ]]
function Page:StartOpenThread()
	self:_repaint()
	if self.List then
		self.List.CanvasPosition = Vector2.zero
	end
end

function Page:StartCloseThread() end

return Page
