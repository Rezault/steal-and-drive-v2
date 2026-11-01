--[[
	CarryController  (client)
	-------------------------
	WHAT A PLAYER HOLDING A CAR IS TOLD, and it is two things: a line at the top of the screen that
	says the car is theirs to place, and a glow on the bays it can go on.

	The car itself is not drawn here. `CarryService` builds it and puts it in the player's hand as a
	tool, so it is already on screen for everybody, at every angle, with no client work at all. What
	is left is the part a model cannot say, which is what to do with it. (One line of the tool's half
	does live here: Roblox's backpack is taken down in `start`, because a tool draws itself a hotbar.)

	=== IT READS ONE ATTRIBUTE AND NOTHING ELSE ===============================================

	`CarryConfig.Attribute` on the Player is the whole of this controller's input: a car key while the
	hands are full, the empty string while they are not. No remote, no round trip, and it replicates,
	so the same reading works for anybody else's carry the day something wants to draw one.

	The one exception is the pickup and place sounds (`_listen`, `CarryConfig.Sound`, 2026-10-12),
	which also read the toy attribute, because a toy from the Cars screen is held in the same hands.

	=== THE HINT IS RAISED WHEN THE SCREEN HAS GONE, NOT BY THE ATTRIBUTE =====================

	A banked car lands in the player's hands DURING the run: `GetawayService` awards it the moment the
	truck takes them, several seconds before the screen comes down. A hint raised on the attribute
	would therefore spend its whole life behind the results screen and be gone by the time anybody
	could read it. `RaceEnd` is no better: it lands at the top of the results hold, with five seconds
	of screen still to go.

	So the attribute ARMS it (`_arm`) and `RaceConfig.ReturnedEvent` FIRES it. That event is published
	by `RaceUIController` on the last frame of the fade home, which is the first moment the player is
	stood on their own island with nothing over them, holding the car. A beat later
	(`CarryConfig.Hint.Delay`) the card slides in, so the lobby has finished streaming back in around
	them before anything moves. Once per car: a second bank raises it again, walking past a podium
	does not.

	NOTHING IS LOST IF THAT EVENT NEVER COMES. `_arm` books a fallback (`Hint.Fallback`) that raises
	the card anyway, and a raise that lands during a race is held over rather than spent: the card is
	only ever marked as shown at the moment it is really shown.

	=== TWO CARDS, ONE OF THEM THE KIT'S ======================================================

	With the new UI on (`NewUIConfig`) the card is the Cartoony Kit's, cloned from the template
	`BuildCarryNoticeV2` puts on the hidden `MainUIV2.Screens` shelf, and it slides in from above the
	way the weather notice does. That is the same shelf, the same kit frame and the same motion as
	that toast on purpose: they share a band at the top of the screen and can be up together.

	Everything `_build` makes is the shipping card, which is what a place with the flag off, or
	one whose template has not been built, still draws. `_showHint` and `_hideHint` are the only
	things that know which of the two is up, and they know it from one flag.

	=== AND THE FIRST CAR GETS A LONGER SENTENCE ==============================================

	`CarryConfig.Guide` is the walkthrough, and from this file's side it is one more attribute and
	nothing else. `FirstCarService` decides who is on their first car and publishes one of three
	strings; `_face` turns that into which words the card says and how long it stands for. One of
	the three is raised by EMPTY hands, because the last thing a first-timer needs told is what a
	car standing on a bay is now doing for them.

	NO SECOND CARD AND NO SECOND SCREEN. The panel, the band, the slide and the colours are the same
	for all three faces, so a player who has done this fifty times and a player doing it once are
	reading the same toast in the same place. Only the sentence changed.

	=== THE GLOW IS A RESCAN, NOT A SUBSCRIPTION ==============================================

	Which bays are free changes for reasons this file would otherwise have to watch four of: a car
	placed, a car sold, a second storey bought, a plot streaming in around the player. So it rescans
	on a timer instead (`CarryConfig.Glow.Interval`), cheaply, and only while a car is being carried.
	Streaming is the reason that is the right shape rather than the lazy one: the bays are not in this
	client's DataModel until the player is near them, which is exactly when the glow is wanted.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
--- For one line: taking Roblox's backpack down, because a carried car is a tool. See `start`.
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local CarryConfig = require(ReplicatedStorage.shared.Configs.CarryConfig)
local CarryNoticeLayout = require(ReplicatedStorage.shared.Modules.CarryNoticeLayout)
local NoticeLane = require(ReplicatedStorage.shared.Modules.NoticeLane)
local NoticeLaneConfig = require(ReplicatedStorage.shared.Configs.NoticeLaneConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
--- For one attribute name: the toy from the Cars screen, which is the other thing the hands can
--- hold. Read by `_listen` only, for the pickup and place sounds.
local LobbyCarConfig = require(ReplicatedStorage.shared.Configs.LobbyCarConfig)
-- Tutorial placement teaches earning from a display; the workshop is still available outside
-- that guidance. Config dependencies keep the glow and tutorial controller free of a start cycle.
local CustomizeConfig = require(ReplicatedStorage.shared.Configs.CustomizeConfig)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local PlotConfig = require(ReplicatedStorage.shared.Configs.PlotConfig)
local RaceConfig = require(ReplicatedStorage.shared.Configs.RaceConfig)
--- For one attribute name: which storeys a plot actually has right now. A bay upstairs on a plot
--- with no upstairs is a bay standing in the air, and the server already refuses to bind it.
local UpgradeConfig = require(ReplicatedStorage.shared.Configs.UpgradeConfig)
--- Which UI this client booted, and where its ScreenGui is. The kit card is only looked for on the
--- new one; `UIRoot` is the one place that answers either question.
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)
--- The customize chip wears the tutorial chip's pill and arrow (`_syncChip`).
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)

local CarryController = Shard.new("CarryController")

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

--[[ Under the getaway countdown (890) and far under the results screen and the return fade, which
	are the two things this must never be drawn over. It is a lobby line: anything that lands on top
	of it is either a question the player has to answer or the end of a run. ]]
local DISPLAY_ORDER = 880

--- Fractions of the card's own box. Title over line, both full width, which is the shape every
--- two-row chip in this kit uses.
local TITLE_Y, TITLE_HEIGHT = 0.3, 0.42
local TEXT_Y, TEXT_HEIGHT = 0.72, 0.34
local SIDE_PAD = 0.04

--[[ THE KIT CARD (the new UI): where its template is authored, and how long to wait for it.
	`BuildCarryNoticeV2` puts it on the hidden `MainUIV2.Screens` shelf, and `_buildKit` clones it.
	The wait is for that shelf replicating at join, which lands long before anybody banks a car, so
	ten seconds is a fence rather than a budget. ]]
local KIT_SHELF = "Screens"
local KIT_TEMPLATE = "CarryNotice"
local KIT_WAIT = 10

--[[ How far above the top edge the kit card is parked before it has ever been measured, in pixels.

	A MEASUREMENT IS USED WHEREVER THERE IS ONE (`_hiddenPosition`): the card's own rendered height is
	what puts it off screen at any viewport, and this is only the answer for the frame before it has
	been laid out. It is the weather notice's number, and comfortably taller than either card. ]]
local KIT_CARD_BOX = 400

-- === The card ===============================================================

--[[ Build whichever card this client should draw, once, on the first thing that wants to show one.

	LAZY, AND THAT IS WHAT MAKES THE KIT CARD POSSIBLE. `MainUIV2` is a StarterGui clone that arrives
	with the character, after `start` has run, so a build at boot would have nothing to clone. Every
	caller of this reaches it from a thread of its own (see `_raise`), which is what makes the wait
	inside `_buildKit` free.

	IT IS NOT CALLED `_card`, and that is not a style choice. `self._card` is the card itself, and a
	field on an instance is found before the method of the same name on the class: with both, the
	first call after the card was built indexes the frame and tries to call it. Measured, as a card
	that showed on a rejoin and never again.

	A SECOND CALLER WAITS WITH THE FIRST rather than being told there is no card. The build takes as
	long as the template takes to arrive, and two raises can overlap inside that window (the fallback
	and a return, a rejoin and a bank); the answer the first one gets is the answer they both want.

	Answers whether there is a card to show. False only with the hint switched off. ]]
function CarryController._ensureCard(self): boolean
	if not CarryConfig.Hint.Enabled then
		return false
	end
	if self._gui then
		return true
	end

	if self._building then
		--- Bounded, because a build that threw would otherwise leave a thread spinning for the rest
		--- of the session. The wait inside `_buildKit` is the whole of what is being waited on.
		local until_ = os.clock() + KIT_WAIT * 2
		while self._building and os.clock() < until_ do
			task.wait(0.1)
		end
		return self._gui ~= nil
	end

	self._building = true
	local ok, err = pcall(function()
		if not (UIRoot.isNewUI() and self:_buildKit()) then
			self:_build()
		end
	end)
	self._building = false
	if not ok then
		self.log:warn(string.format("The carry hint could not be built, so nothing is drawn: %s", tostring(err)))
	end
	return self._gui ~= nil
end

--[[ THE SAME TOAST ON THE CARTOONY KIT, for the new UI (`NewUIConfig`).

	THE ART IS AUTHORED, NOT BUILT. `BuildCarryNoticeV2` cuts it out of the kit's `PromptUI` onto the
	hidden `MainUIV2.Screens` shelf, and its header says why it is the weather notice's twin. This
	clones it into a ScreenGui of this file's own at the same layer the shipping card uses, because a
	frame left inside `MainUIV2` would share that ScreenGui's one layer with the menus.

	IT FILLS IN THE SAME THREE STRINGS the shipping card has, plus the car's name, which is the one
	row the shipping card has no space for. Everything downstream reads `_card*` fields, so the show,
	the hold and the hide are one code path with one branch in it.

	FALSE, AND A WARNING, when the template is not in the place. `_card` then builds the shipping
	card, so a place that is missing the art still tells the player what they are holding. ]]
function CarryController._buildKit(self): boolean
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", KIT_WAIT)
	local root = playerGui and UIRoot.wait(playerGui :: PlayerGui, KIT_WAIT)
	local shelf = root and root:WaitForChild(KIT_SHELF, KIT_WAIT)
	local template = shelf and shelf:WaitForChild(KIT_TEMPLATE, KIT_WAIT)
	if not (template and template:IsA("GuiObject")) then
		self.log:warn(
			string.format(
				"No %s.%s.%s in this place (run BuildCarryNoticeV2); showing the shipping card instead.",
				UIRoot.name(),
				KIT_SHELF,
				KIT_TEMPLATE
			)
		)
		return false
	end

	local card = template:Clone() :: GuiObject
	card.Name = "Card"
	CarryNoticeLayout.apply(card)
	--- The kit's text caps are pixels for a 1080-tall screen; this keeps them in proportion above it.
	--- The two line ceilings are `_fitNotice`'s and are named `Ceiling`, which the helper leaves alone.
	require(script.Parent.UIController.KitPage).scaleTextCaps(card)

	local header = card:FindFirstChild("Header")
	local main = card:FindFirstChild("Main")
	local parts = {
		title = header and header:FindFirstChild("Title"),
		--- `Car` rather than `Name`, and the build command's header says why: a child called `Name`
		--- is shadowed by its parent's own `Name` property, so `Main.Name` is the string "Main".
		car = main and main:FindFirstChild("Car"),
		line = main and main:FindFirstChild("Line"),
	}
	--- By a list of names rather than over the table: a lookup that came back nil is not a key in it.
	for _, name in { "title", "car", "line" } do
		if not parts[name] then
			self.log:warn(
				string.format("The %s template has no `%s`; re-run BuildCarryNoticeV2. Showing the shipping card instead.", KIT_TEMPLATE, name)
			)
			card:Destroy()
			return false
		end
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CarryHint"
	gui.ResetOnSpawn = false
	--- The kit's own space, which is where this frame was laid out: the topbar is already taken out
	--- of it, so the margin in `Hint.Kit.ShownY` is a margin from what the player can see.
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = DISPLAY_ORDER
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	card.Visible = true
	card.Position = UDim2.new(0.5, 0, 0, -KIT_CARD_BOX)
	card.Parent = gui
	--- In the left-side notice lane rather than top-centre (Leaf, 2026-10-06). See `NoticeLaneConfig`.
	if NoticeLaneConfig.Enabled then
		self._lane = NoticeLane.join(card, NoticeLaneConfig.Order.CarryHint, true, 3.5)
	end

	self._gui = gui
	self._kit = true
	self._card = card
	self._cardTitle = parts.title
	self._cardCar = parts.car
	self._cardLine = parts.line
	--- Where the build command put each line. `_fill` moves the sentence up into the middle when
	--- there is no name over it, and this is what it puts back.
	self._carPosition = (parts.car :: TextLabel).Position
	self._linePosition = (parts.line :: TextLabel).Position
	self._rows = { parts.car, parts.line }

	self._fit = card:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_fitNotice()
	end)
	self:_fitNotice()

	gui.Parent = playerGui
	return true
end

--[[ Re-derive both rows' `MaxTextSize` from the card's rendered height.

	`TextScaled` on its own sizes each row to its own box, so a two word name in a tall box and a
	sentence in a short one render at sizes that have nothing to do with each other. One ceiling per
	row against ONE measurement is what makes them agree, and it is the same instrument, with the
	same names, that `WeatherController._fitNotice` uses on the other toast.

	A zero height (the frame has not been laid out yet, or the GUI is disabled) is skipped rather than
	written, because a ceiling of zero is a label that renders nothing. ]]
function CarryController._fitNotice(self)
	local card = self._card
	if not card then
		return
	end
	local height = card.AbsoluteSize.Y
	if height <= 0 then
		return
	end
	for _, label in self._rows or {} do
		local ceiling = label:FindFirstChild("Ceiling")
		if ceiling and ceiling:IsA("UITextSizeConstraint") then
			local fraction = ceiling:GetAttribute("Fraction")
			if type(fraction) == "number" then
				ceiling.MaxTextSize = math.max(8, math.round(height * fraction))
			end
		end
	end
end

--- Off the top of the screen by its own height, measured if there is anything to measure. The kit
--- card only; the shipping card fades rather than moving.
function CarryController._hiddenPosition(self): UDim2
	local card = self._card
	local height = if card and card.AbsoluteSize.Y > 0 then card.AbsoluteSize.Y else KIT_CARD_BOX
	return UDim2.new(0.5, 0, 0, -math.ceil(height) - 8)
end

--[[ WHICH OF THE THREE THINGS THIS CARD CAN SAY IT IS ABOUT TO SAY.

	One card, three faces, picked off `CarryConfig.Guide.Attribute` and nothing else:

	    the ordinary carry   "Your New Car"    for somebody who has done this before
	    the first one        "Your First Car"  the walkthrough, longer, and it names the LOT
	    just parked          "Parked"          the only face raised by EMPTY hands

	ONLY THE WORDS AND THE CLOCK ARE IN HERE. The panel, the band, the slide and the colours are
	`Hint`'s for all three, because a first-timer deserves a better sentence rather than a different
	screen, and because a toast that arrived differently depending on how many cars you owned would
	read as two features.

	IT IS RE-READ ON EVERY RAISE rather than remembered. The attribute is the server's and it can
	move between a card being asked for and being shown. ]]
function CarryController._face(self)
	local hint = CarryConfig.Hint
	local guide = CarryConfig.Guide
	local state = if guide.Enabled then Players.LocalPlayer:GetAttribute(guide.Attribute) else nil

	if state == guide.Parked then
		return {
			Title = guide.ParkedTitle,
			KitTitle = guide.KitParkedTitle,
			Text = guide.ParkedText,
			Seconds = guide.ParkedSeconds,
			--- The name row belongs to the card announcing a prize, and by now the prize is behind
			--- them on a podium they are looking at.
			CarName = false,
		}
	end

	if state == guide.Customize then
		return {
			Title = guide.CustomizeTitle,
			KitTitle = guide.KitCustomizeTitle,
			Text = guide.CustomizeText,
			Seconds = guide.CustomizeSeconds,
			CarName = hint.CarName,
		}
	end

	if state == guide.Carrying then
		return {
			Title = guide.Title,
			KitTitle = guide.KitTitle,
			Text = guide.Text,
			Seconds = guide.Seconds,
			CarName = hint.CarName,
		}
	end

	--- Nothing to say: this profile has parked a car before (`Hint.FirstTimeOnly`).
	if hint.FirstTimeOnly and Players.LocalPlayer:GetAttribute(guide.ParkedBeforeAttribute) == true then
		return nil
	end

	return {
		Title = hint.Title,
		KitTitle = hint.KitTitle,
		Text = hint.Text,
		Seconds = hint.Seconds,
		CarName = hint.CarName,
	}
end

--[[ What the card says about THIS car, written before it is shown.

	THE NAME ROW IS THE ONLY CONDITIONAL THING ON IT. A key that will not parse, a face with no name
	row, or `Hint.CarName` off, leaves the card with one line, and that line moves to the middle of
	the body rather than sitting under a gap: a sentence pinned to the bottom of an empty card reads
	as a row that failed to load.

	THE SHIPPING CARD IS WRITTEN HERE TOO, which it did not used to be. Its two labels were filled
	once at build, which was correct while there was one thing to say; there are three now, and a
	place with the new UI off would otherwise show the first-timer's clock over the veteran's
	sentence. ]]
function CarryController._fill(self, face, key: string?)
	if not self._kit then
		for index, label in self._labels or {} do
			label.Text = if index == 1 then face.Title else face.Text
		end
		return
	end

	self._cardTitle.Text = face.KitTitle or face.Title
	self._cardLine.Text = face.Text

	local body, paint = nil, nil
	if key then
		body, paint = GarageConfig.parseCarKey(key)
	end
	local named = face.CarName ~= false and body ~= nil
	self._cardCar.Visible = named
	if named then
		self._cardCar.Text = GarageConfig.carName(body :: string, paint)
		self._cardLine.Position = self._linePosition
	else
		self._cardLine.Position = UDim2.new(self._linePosition.X.Scale, self._linePosition.X.Offset, 0.5, 0)
	end
end

function CarryController._build(self)
	local hint = CarryConfig.Hint
	if not hint.Enabled then
		return -- `_showHint` and `_hideHint` both answer to a nil `_gui`, so the glow still works.
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CarryHint"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = DISPLAY_ORDER
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	--[[ NOT `Active`, and nothing under it is either. It is a line of text near the top of a screen
		whose top is where a touch player's fingers go looking for the topbar, and a label that ate a
		press would cost somebody a button they were reaching for. ]]
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, hint.CentreY)
	card.Size = UDim2.fromScale(hint.Size.X, hint.Size.Y)
	card.BackgroundColor3 = hint.PanelColor
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0
	card.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(hint.CornerRadius, 0)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = hint.StrokeColor
	stroke.Thickness = hint.StrokeThickness
	stroke.Transparency = 1
	stroke.Parent = card

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, TITLE_Y)
	title.Size = UDim2.fromScale(1 - SIDE_PAD * 2, TITLE_HEIGHT)
	title.BackgroundTransparency = 1
	title.FontFace = FONT
	title.Text = hint.Title
	title.TextColor3 = hint.TitleColor
	title.TextScaled = true
	--- `TextScaled` would sooner break a line in two than pick a smaller font, and these two are
	--- authored to fit on one. Clearing `TextWrapped` is what makes it shrink instead.
	title.TextWrapped = false
	title.TextTransparency = 1
	title.Parent = card

	local text = title:Clone()
	text.Name = "Line"
	text.Position = UDim2.fromScale(0.5, TEXT_Y)
	text.Size = UDim2.fromScale(1 - SIDE_PAD * 2, TEXT_HEIGHT)
	text.Text = hint.Text
	text.TextColor3 = hint.TextColor
	text.Parent = card

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	self._gui = gui
	self._card = card
	self._stroke = stroke
	self._labels = { title, text }
end

--[[ Raise the hint, and take it down again on its own clock.

	THE TOKEN IS WHAT MAKES A SECOND CAR SAFE. Banking again while the last hint is still counting
	down restarts it rather than stacking two timers, either of which would otherwise be able to put
	away a card the other one had just raised.

	THE KIT CARD SLIDES AND THE SHIPPING ONE FADES, which is the only place the two differ. A fade on
	the kit's card would mean tweening its panel, its cap, its rim, its well and every line of type
	towards transparencies they do not share; the pack's own toast slides, and so does the weather
	notice this sits beside. ]]
function CarryController._showHint(self, face, key: string?)
	if not (CarryConfig.Hint.Enabled and self._gui) then
		return
	end
	local hint = CarryConfig.Hint

	self._hintToken = (self._hintToken or 0) + 1
	local token = self._hintToken
	self:_fill(face, key)

	if self._kit then
		--- Cancelled rather than merely fenced: a slide still running from the last card would
		--- otherwise keep moving this one towards where that one was going.
		if self._slide then
			self._slide:Cancel()
			self._slide = nil
		end
		self._gui.Enabled = true
		if self._lane then
			--[[ The lane slides it in from the left, into its slot. Same clock either way, but it
				starts when the card is really up: with the lane full it waits its turn
				(`NoticeLaneConfig.MaxVisible`), and a clock that ran meanwhile would spend the hold
				off screen. ]]
			self._lane:show(function()
				task.delay(hint.Kit.SlideIn + face.Seconds, function()
					if self._hintToken == token then
						self:_hideHint()
					end
				end)
			end)
			return
		end
		self._card.Position = self:_hiddenPosition()
		local slide = TweenService:Create(
			self._card,
			TweenInfo.new(hint.Kit.SlideIn, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, hint.Kit.ShownY, 0) }
		)
		self._slide = slide
		slide:Play()

		task.delay(hint.Kit.SlideIn + face.Seconds, function()
			if self._hintToken == token then
				self:_hideHint()
			end
		end)
		return
	end

	self._gui.Enabled = true
	local fade = TweenInfo.new(hint.FadeIn, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(self._card, fade, { BackgroundTransparency = hint.PanelTransparency }):Play()
	TweenService:Create(self._stroke, fade, { Transparency = 0 }):Play()
	for _, label in self._labels do
		TweenService:Create(label, fade, { TextTransparency = 0 }):Play()
	end

	task.delay(face.Seconds, function()
		if self._hintToken == token then
			self:_hideHint()
		end
	end)
end

--- Put it away. Safe to call on a card that is already down, which is what lets the carry ending and
--- the timer running out both simply call it.
function CarryController._hideHint(self)
	if not (self._gui and self._gui.Enabled) then
		return
	end
	local hint = CarryConfig.Hint
	--- Neither up nor waiting its turn: already sliding out, and that slide's finish switches it off.
	if self._kit and self._lane and not self._lane:isPending() then
		return
	end

	self._hintToken = (self._hintToken or 0) + 1
	local token = self._hintToken

	if self._kit and self._lane then
		self._lane:hide(function()
			--- Fenced for the same reason as the slide below.
			if self._hintToken == token and self._gui then
				self._gui.Enabled = false
			end
		end)
		return
	end

	if self._kit then
		if self._slide then
			self._slide:Cancel()
			self._slide = nil
		end
		local slide = TweenService:Create(
			self._card,
			TweenInfo.new(hint.Kit.SlideOut, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = self:_hiddenPosition() }
		)
		self._slide = slide
		slide.Completed:Connect(function()
			--- Fenced, so a card raised during the slide out does not have its own screen disabled
			--- out from under it by the previous one finishing.
			if self._hintToken == token and self._gui then
				self._gui.Enabled = false
			end
		end)
		slide:Play()
		return
	end

	local fade = TweenInfo.new(hint.FadeOut, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(self._card, fade, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(self._stroke, fade, { Transparency = 1 }):Play()
	for _, label in self._labels do
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
	end

	task.delay(hint.FadeOut, function()
		--- Only the fade that is still current may switch the screen off. A carry that started again
		--- inside the fade has already raised it, and this would black it out.
		if self._hintToken == token and self._gui then
			self._gui.Enabled = false
		end
	end)
end

-- === The bays ===============================================================

--[[ This player's own plot, or nil.

	TAGGED, IN THE PLOTS FOLDER, AND CARRYING THE INDEX THE PLAYER WAS GIVEN. All three, for the
	reason `PlotService` and `DealershipMarkerController` both spell out: `workspace.Plot7` is a full
	copy of Plot1 parked off the island, tagged, claiming index 1. A lookup that trusts the tag alone
	lights up a lot in the sea. ]]
function CarryController._myPlot(self): Model?
	local index = Players.LocalPlayer:GetAttribute(PlotConfig.PlayerPlotAttribute)
	if type(index) ~= "number" then
		return nil
	end

	local map = workspace:FindFirstChild(PlotConfig.MapName)
	local folder = map and map:FindFirstChild(PlotConfig.PlotsFolderName)
	if not folder then
		return nil
	end
	--[[ THE OWNER STAMP FIRST, THE INDEX ONLY AS A FALLBACK (2026-10-12, the new map: after the
		tutorial the bay glow lit "a completely different plot"). `PlotService` stamps
		`OwnerUserIdAttribute` on the exact model it gave this player, so that is the server's own
		answer; the index alone is not, once a map carries two plots with one `PlotIndex` (a copied
		plot keeps its source's number, and the server skips the second). An index match is only
		trusted on a plot nobody owns — never on one stamped with somebody else's id. Same rule as
		`DealershipMarkerController._bind`. ]]
	local userId = Players.LocalPlayer.UserId
	local byIndex = nil
	for _, plot in folder:GetChildren() do
		if not (plot:IsA("Model") and CollectionService:HasTag(plot, PlotConfig.PlotTag)) then
			continue
		end
		local owner = plot:GetAttribute(PlotConfig.OwnerUserIdAttribute)
		if owner == userId then
			return plot
		end
		if owner == nil and not byIndex and plot:GetAttribute(PlotConfig.IndexAttribute) == index then
			byIndex = plot
		end
	end
	return byIndex
end

--[[ The slab a car stands on: the HIGHER of the podium's two parts both named `Platform`.

	THE SAME RULE `GarageService._platforms` USES, and it is written out again rather than shared
	because that one is a method on a server service. Its comment has the history worth knowing: the
	two slabs were once told apart by volume, and that picked the wrong one on all 36 podiums,
	because the deck is smaller in footprint and thicker than the base under it. ]]
local function deckOf(slot: Model): BasePart?
	local best: BasePart? = nil
	for _, child in slot:GetDescendants() do
		if child:IsA("BasePart") and child.Name == "Platform" then
			if not best or child.Position.Y + child.Size.Y / 2 > best.Position.Y + best.Size.Y / 2 then
				best = child
			end
		end
	end
	return best
end

--[[ Every deck on this player's own lot that the car in their hands could be put down on, at any
	distance. `occupied` includes the ones with a car already standing on them, which a placement
	swaps rather than refuses.

	THE FLOOR CHECK IS AGAINST THE PLOT, not against a config: a plot in its locked state has one
	deck and a plot whose owner bought the second has two, and the podiums for the second exist in the
	map either way. Offering one on a plot with no upstairs points the player at a bay standing in
	the air, which the server would refuse anyway. ]]
function CarryController._decks(self, occupied: boolean, showroomOnly: boolean?): { BasePart }
	local plot = self:_myPlot()
	local slots = plot and plot:FindFirstChild(GarageConfig.SlotsFolderName)
	if not (plot and slots) then
		return {}
	end

	local topFloor = tonumber(plot:GetAttribute(UpgradeConfig.PlotFloorsAttribute)) or GarageConfig.BaseFloor
	local decks = {}
	for _, slot in slots:GetChildren() do
		if not (slot:IsA("Model") and CollectionService:HasTag(slot, GarageConfig.SlotTag)) then
			continue
		end

		local floor = slot:GetAttribute(GarageConfig.SlotFloorAttribute)
		-- 2026-10-04: the nearest empty podium can be the customization bay, which cannot earn
		-- the income the next tutorial beat teaches. Filter before choosing either glow or pointer.
		if showroomOnly and CustomizeConfig.Enabled and GarageConfig.Enabled
			and slot:GetAttribute(GarageConfig.SlotIndexAttribute) == CustomizeConfig.Bay.SlotIndex then
			continue
		end
		if type(floor) == "number" and floor > topFloor then
			continue
		end
		if not occupied and slot:FindFirstChild(GarageConfig.Display.CarName) then
			continue
		end

		local deck = deckOf(slot)
		if deck then
			table.insert(decks, deck)
		end
	end
	return decks
end

--[[ PUBLIC (`TutorialController`) — the EMPTY bays of that list, which is what "somewhere to put
	this down" means to a player who has never done it.

	IT IS THIS FILE'S ANSWER AND NOT THE TUTORIAL'S on purpose. Whose floor a podium is on, whether
	the storey it belongs to has been bought and whether something is already standing on it are the
	questions the glow settles every quarter second, and a second walk over there would be a second
	one to keep right — wrong in exactly the way that shows, with an arrow over a bay the glow did
	not light. Unoccupied regardless of `Glow.OccupiedToo`: that flag is about what is worth lighting
	up, and this is about where a first car should be sent.

	UNCAPPED BY DISTANCE, unlike the glow. `Glow.Studs` is how near a deck has to be to be worth
	drawing attention to; the caller here is choosing between them, and a nearest-of-three that
	silently dropped the ones over the far side of the lot would answer nothing at all on a player
	who landed facing away. ]]
function CarryController.getFreeDecks(self): { BasePart }
	local decks = self:_decks(false, true)
	local player = Players.LocalPlayer
	if player:GetAttribute("FirstPlacementActive") == true then
		local assigned = player:GetAttribute("FirstPlacementBay")
		for _, deck in decks do
			local node: Instance? = deck
			while node and node ~= workspace do
				if node:GetAttribute(GarageConfig.SlotIndexAttribute) == assigned and assigned ~= nil then return { deck } end
				node = node.Parent
			end
		end
		return {} -- Wait for the assigned bay to stream in; do not point somewhere else.
	end
	return decks
end

--[[ PUBLIC (`GuideTrailController`) - the decks the guide line may end at. The CUSTOMIZE podium alone
	while its pointer is up, because that is the one bay this file is lighting and chipping; every
	free showroom bay otherwise, which is `getFreeDecks` and so the tutorial's answer too. ]]
function CarryController.getGuideDecks(self): { BasePart }
	if self:_pointingCustomize() then
		local workshop = self:_workshopDeck()
		return if workshop then { workshop } else {}
	end
	return self:getFreeDecks()
end

--- Is the customize pointer up? The server's say (`CarryConfig.Guide.PointCustomize`).
function CarryController._pointingCustomize(self): boolean
	local guide = CarryConfig.Guide
	return guide.Enabled and guide.PointCustomize and CustomizeConfig.Enabled
		and Players.LocalPlayer:GetAttribute(guide.Attribute) == guide.Customize
end

--- The CUSTOMIZE podium's deck on this player's lot, or nil (no workshop, or not streamed in).
function CarryController._workshopDeck(self): BasePart?
	local plot = self:_myPlot()
	local slots = plot and plot:FindFirstChild(GarageConfig.SlotsFolderName)
	if not slots then
		return nil
	end
	for _, slot in slots:GetChildren() do
		if slot:IsA("Model") and CollectionService:HasTag(slot, GarageConfig.SlotTag)
			and slot:GetAttribute(GarageConfig.SlotIndexAttribute) == CustomizeConfig.Bay.SlotIndex then
			return deckOf(slot)
		end
	end
	return nil
end

--[[ The chip over the CUSTOMIZE podium while the pointer is up: the tutorial chip's pill and arrow,
	built here because the tutorial is over by the time this shows and its chip belongs to its beats.
	Sized in pixels like that one, so it reads at the far end of a lot. Bobbed by the carry loop. ]]
local CHIP_SIZE = UDim2.fromOffset(200, 110)
local CHIP_HEIGHT = 6 -- studs over the deck
local CHIP_BOB = 0.6
local CHIP_BOB_PERIOD = 1.6

function CarryController._clearChip(self)
	if self._chip then
		self._chip:Destroy()
		self._chip = nil
	end
end

function CarryController._syncChip(self)
	local want = if self:_pointingCustomize() then self:_workshopDeck() else nil
	if self._chip and self._chip.Parent and self._chip.Adornee == want then
		return
	end
	self:_clearChip()
	if not want then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CustomizeChip"
	billboard.Adornee = want
	billboard.Size = CHIP_SIZE
	billboard.StudsOffsetWorldSpace = Vector3.new(0, CHIP_HEIGHT, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = math.huge
	billboard.ResetOnSpawn = false

	local pillHeight = (CHIP_SIZE.X.Offset / (UIAssets.Size.Pill.X / UIAssets.Size.Pill.Y)) / CHIP_SIZE.Y.Offset
	local pill = Instance.new("ImageLabel")
	pill.Name = "Pill"
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Position = UDim2.fromScale(0.5, 0.3)
	pill.Size = UDim2.fromScale(1, pillHeight)
	pill.BackgroundTransparency = 1
	pill.Image = UIAssets.url(UIAssets.Pill.Orange.Idle)
	pill.ScaleType = Enum.ScaleType.Stretch
	pill.Parent = billboard

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.46)
	label.Size = UDim2.fromScale(0.86, 0.5)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.Text = CarryConfig.Guide.CustomizeChip
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Parent = pill

	local point = Instance.new("ImageLabel")
	point.Name = "Point"
	point.AnchorPoint = Vector2.new(0.5, 0.5)
	point.Position = UDim2.fromScale(0.5, 0.75)
	point.Size = UDim2.fromScale(CHIP_SIZE.Y.Offset * 0.4 / CHIP_SIZE.X.Offset, 0.4)
	point.BackgroundTransparency = 1
	point.Image = UIAssets.url(UIAssets.Tutorial.Arrow)
	point.ScaleType = Enum.ScaleType.Stretch
	point.Parent = billboard

	billboard.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self._chip = billboard
end

--[[ Which decks should be glowing right now: the ones close enough to be worth naming. Empty for a
	player with no plot near them, which is every player carrying a car somewhere else on the island.

	A podium with a car on it is a podium you can still place onto — it swaps — so whether it is LIT
	is the question `Glow.OccupiedToo` answers, and its note says why the default is no. ]]
function CarryController._litDecks(self): { BasePart }
	local glow = CarryConfig.Glow
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return {}
	end

	local here = (root :: BasePart).Position
	local lit = {}
	local tutorialPlace = TutorialConfig.isOn()
		and Players.LocalPlayer:GetAttribute(TutorialConfig.StepAttribute) == "place"
	local decks = if Players.LocalPlayer:GetAttribute("FirstPlacementActive") == true
		then self:getFreeDecks() else self:_decks(glow.OccupiedToo, tutorialPlace)
	for _, deck in decks do
		if (deck.Position - here).Magnitude <= glow.Studs then
			table.insert(lit, deck)
		end
	end
	--- The CUSTOMIZE podium glows while the pointer names it, full or empty, near or far.
	if self:_pointingCustomize() then
		local workshop = self:_workshopDeck()
		if workshop and not table.find(lit, workshop) then
			table.insert(lit, workshop)
		end
	end
	return lit
end

--- Make the set of highlights match `_litDecks`. A diff rather than a rebuild, because a highlight
--- torn down and remade every quarter second is a visible blink on a deck nothing happened to.
function CarryController._rescan(self)
	local glow = CarryConfig.Glow
	local wanted = {}
	for _, deck in self:_litDecks() do
		wanted[deck] = true
	end

	for deck, highlight in self._highlights do
		if not wanted[deck] or not deck.Parent then
			highlight:Destroy()
			self._highlights[deck] = nil
		end
	end

	for deck in wanted do
		if not self._highlights[deck] then
			local highlight = Instance.new("Highlight")
			highlight.Name = "CarryBay"
			highlight.Adornee = deck
			highlight.FillColor = glow.Color
			highlight.OutlineColor = glow.Color
			highlight.FillTransparency = glow.FillTransparency
			highlight.OutlineTransparency = glow.OutlineTransparency
			--- `AlwaysOnTop` off on purpose. A deck that shines through the building it is inside
			--- is a waypoint, and this is a surface you are being invited to walk up to.
			highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			highlight.Parent = deck
			self._highlights[deck] = highlight
		end
	end
end

--- Put every glow out. Called when the carry ends, when a run starts, and on cleanup, so a deck can
--- never be left lit by a car that is no longer in anybody's hands.
function CarryController._clearGlow(self)
	for deck, highlight in self._highlights do
		highlight:Destroy()
		self._highlights[deck] = nil
	end
end

-- === The loop ===============================================================

--[[ One connection, alive only while a car is being carried and a run is not running. It does two
	things at two rates: the rescan on `Glow.Interval`, and the breath every frame.

	THE BREATH IS THE FILL ALONE. A pulsing outline reads as a warning; a surface that gently fills
	and empties reads as somewhere to put something down. `Glow.Pulse` at 0 is a flat glow and skips
	the write. ]]
function CarryController._start(self)
	if self._loop or not CarryConfig.Glow.Enabled then
		return
	end

	local glow = CarryConfig.Glow
	local accumulator = glow.Interval -- rescan on the first frame rather than a quarter second late
	self._loop = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= glow.Interval then
			accumulator = 0
			self:_rescan()
			self:_syncChip()
		end
		local chip = self._chip
		if chip then
			local bob = math.sin(os.clock() * math.pi * 2 / CHIP_BOB_PERIOD) * CHIP_BOB
			chip.StudsOffsetWorldSpace = Vector3.new(0, CHIP_HEIGHT + bob, 0)
		end

		if glow.Pulse <= 0 then
			return
		end
		local phase = math.sin(os.clock() * math.pi * 2 / glow.PulsePeriod) * 0.5 + 0.5
		local fill = math.clamp(glow.FillTransparency + glow.Pulse * (phase - 0.5), 0, 1)
		for _, highlight in self._highlights do
			highlight.FillTransparency = fill
		end
	end)
end

function CarryController._stop(self)
	if self._loop then
		self._loop:Disconnect()
		self._loop = nil
	end
	self:_clearGlow()
	self:_clearChip()
end

-- === State ==================================================================

--[[ Put a car in the queue for a card, to be raised when the screen the run ended on has gone.

	THE FALLBACK IS THE WHOLE REASON THIS IS A FUNCTION rather than one assignment. Every way home
	goes through the results screen and that screen drops itself inside twelve seconds whatever
	happens, so `RaceConfig.ReturnedEvent` always comes. If a path is ever added that ends a run
	without one, this is what stops the car in the player's hands from going unexplained: late is a
	worse card, no card is a worse game. ]]
function CarryController._arm(self, key: string)
	self._pendingKey = key
	self._armToken = (self._armToken or 0) + 1
	local token = self._armToken

	task.delay(CarryConfig.Hint.Fallback, function()
		--- Still waiting for the same car. A card that was raised on the screen lifting cleared
		--- `_pendingKey` on its way up, and a car that was placed or replaced cleared it too.
		if self._armToken == token and self._pendingKey == key then
			self.log:warn("No return screen was announced, so the carry hint is being raised late.")
			self:_raise(key, 0)
		end
	end)
end

--[[ Show the card for this car, after `delay` seconds, unless the world has moved on by then.

	IT IS A THREAD OF ITS OWN and every caller wants that: the first one to arrive builds the card,
	which waits on the UI replicating, and two of the three callers are signal handlers that must not
	be held up by it (`Dispatcher:Publish` runs its subscribers inline).

	A RAISE THAT LANDS DURING A RACE IS HELD OVER, NOT SPENT. `_hintedKey` is written at the moment
	the card is really shown rather than when it is asked for, so a player who pressed Play inside the
	delay still gets told about their car when they next come home. ]]
function CarryController._raise(self, key: string, delay: number)
	self._raiseToken = (self._raiseToken or 0) + 1
	local token = self._raiseToken

	task.delay(delay, function()
		if self._raiseToken ~= token or self._suspended then
			return
		end
		--- Placed, sold or replaced while the delay ran. The attribute is the only truth about what
		--- is in their hands, and it is read again here rather than trusted from when this was asked.
		if Players.LocalPlayer:GetAttribute(CarryConfig.Attribute) ~= key then
			return
		end
		if not self:_ensureCard() then
			return
		end
		--- Read again after the build, which yields the first time: a race can have started under it.
		if self._raiseToken ~= token or self._suspended then
			return
		end
		if self._pendingKey == key then
			self._pendingKey = nil
		end
		self._hintedKey = key
		--- Counted as told: the tutorial's own card is saying it, and `_apply` must not re-raise it.
		local face = self:_face()
		if face == nil or self:_tutorialOwns() then
			return
		end
		self:_showHint(face, key)
	end)
end

--[[ Is the tutorial's card on screen telling the player what this card would (`Hint.YieldToTutorial`)?
	True for every beat until the tutorial is done, lobby beats included: those are the ones whose card
	sits in the same top band, and the PLACE beat says "park your new car" in so many words. ]]
function CarryController._tutorialOwns(self): boolean
	return CarryConfig.Hint.YieldToTutorial == true
		and TutorialConfig.isUnfinished(Players.LocalPlayer:GetAttribute(TutorialConfig.StepAttribute))
end

--[[ The follow-up card, after the first car in this profile's life has landed on a podium.

	THE ONE RAISE THAT IS NOT ABOUT SOMETHING IN THE HANDS, which is why it is its own function
	rather than a `nil` key through `_raise`: every fence in there is "are they still holding the
	car I was asked about", and the whole point of this card is that they are not. What it checks
	instead is the one thing that is still true, which is the attribute the server put up.

	IT SHARES `_raiseToken` WITH `_raise` on purpose. A player who banks another car inside the hold
	should get told about THAT, and the newer raise winning is exactly what the token is for. ]]
function CarryController._raiseParked(self, delay: number)
	local guide = CarryConfig.Guide
	self._raiseToken = (self._raiseToken or 0) + 1
	local token = self._raiseToken

	task.delay(delay, function()
		if self._raiseToken ~= token or self._suspended then
			return
		end
		if Players.LocalPlayer:GetAttribute(guide.Attribute) ~= guide.Parked then
			return
		end
		if not self:_ensureCard() then
			return
		end
		--- Read again after the build, which yields the first time: a race can have started under it.
		local face = self:_face()
		if self._raiseToken ~= token or self._suspended or face == nil or self:_tutorialOwns() then
			return
		end
		self:_showHint(face, nil)
	end)
end

--[[ The one place that decides whether anything is drawn, from the two facts that matter: what is in
	the player's hands, and whether they are on the road.

	A RUN SUSPENDS IT RATHER THAN ENDING IT. The car comes off the character for the length of a race
	(`CarryService`), the bays are half an island away, and the results screen is about to cover the
	lot. The glow comes back on `RaceEnd`; the card waits for the screen itself to lift. ]]
function CarryController._apply(self)
	local guide = CarryConfig.Guide
	local player = Players.LocalPlayer
	local key = player:GetAttribute(CarryConfig.Attribute)
	local carrying = type(key) == "string" and key ~= ""

	if not carrying then
		self._hintedKey = nil
		self._pendingKey = nil
		self:_stop()

		--[[ THE ONE CARD EMPTY HANDS CAN RAISE. The first car in a profile's life has just gone onto
			a podium, and `FirstCarService` has put `Parked` up to say so.

			ONCE, AND THE FLAG IS WHY. This runs again for a respawn, for the plot streaming in and
			for both ends of a run, and every one of those would otherwise re-raise a card the player
			has already read. The flag is cleared by hands that are full again and by the attribute
			going back to empty, which are the only two things that can make this card due again. ]]
		if guide.Enabled and player:GetAttribute(guide.Attribute) == guide.Parked then
			if not self._parkedShown then
				self._parkedShown = true
				self:_raiseParked(guide.ParkedDelay)
			end
			return
		end

		self._parkedShown = false
		self:_hideHint()
		return
	end

	self._parkedShown = false

	if self._suspended then
		self:_stop()
		return
	end

	self:_start()

	--[[ A car they have not been told about yet, with no screen owed to them: a rejoin holding one,
		or any future way of being handed a car that does not go through a run.

		A CAR WITH A SCREEN STILL COMING DOWN OVER IT IS LEFT ALONE. `_pendingKey` is what says so,
		and it is the whole difference between this path and the bank's: raising the card here would
		put it behind the results, which is the bug this arrangement exists to fix. ]]
	if self._hintedKey ~= key and self._pendingKey ~= key then
		self:_raise(key, 0)
	end
end

-- === The sounds ==============================================================

--- What one of the two hand attributes says right now: a car key, or nil for empty.
local function heldBy(attribute: string): string?
	local key = Players.LocalPlayer:GetAttribute(attribute)
	return if type(key) == "string" and key ~= "" then key else nil
end

--[[ The pickup and place sounds (`CarryConfig.Sound`), off the attributes and nothing else, so a car
	that the server refused to move makes no noise.

	TWO CHANNELS, COMPARED SEPARATELY. A toy is held over a hotbar car (`CarryService._wanted`), so
	dropping the toy hands the model back to the car underneath it. Read as one "what is in the hand"
	that drop would be a swap and sound like a pickup; read per attribute it is the toy channel
	emptying, which is a place.

	COALESCED TO ONE SOUND A FRAME. One press can move both attributes in the same breath, and two
	clips stacked read as a fumble. A channel that filled or swapped wins over one that emptied,
	because a car is in the hand at the end of it. ]]
function CarryController._listen(self)
	if self._listenQueued then
		return
	end
	self._listenQueued = true
	task.defer(function()
		self._listenQueued = false
		local sound = CarryConfig.Sound
		local picked, placed = false, false
		for attribute, before in self._held do
			local now = heldBy(attribute) or false
			if now ~= before then
				self._held[attribute] = now
				if now then
					picked = true
				elseif before then
					placed = true
				end
			end
		end

		if not sound.Enabled or self._suspended or not (picked or placed) then
			return
		end
		local cue = if picked then sound.Pickup else sound.Place
		local sounds = Shard.get("SoundController")
		if sounds and cue then
			sounds:PlayNamed(cue.Group, cue.Name)
		end
	end)
end

CarryController:withRemoteEvents({
	{
		--[[ The race bracket, the same one the dealership marker and the play button use. Fired for
			this client only, so there is no "is it mine" to check. ]]
		RaceStart = function()
			CarryController._suspended = true
			CarryController:_hideHint()
			CarryController:_apply()
		end,
		--[[ The run is over, but the screen it ended on is not: this lands at the top of the results
			hold, about five seconds before anything moves. So the glow comes back here and the card
			is only ARMED, for `RaceConfig.ReturnedEvent` to raise once the screen has lifted. ]]
		RaceEnd = function()
			CarryController._suspended = false
			local key = Players.LocalPlayer:GetAttribute(CarryConfig.Attribute)
			if type(key) == "string" and key ~= "" and CarryController._hintedKey ~= key then
				CarryController:_arm(key)
			end
			CarryController:_apply()
		end,
	},
})

CarryController:withLifecycle({
	init = function(self)
		self._highlights = {} :: { [BasePart]: Highlight }
		self._suspended = false
		--- The card is built on the first thing that wants to show one. See `_ensureCard`: the kit's
		--- template arrives with the character, which is after this.
		self._building = false
		self._kit = false
		--- Whether the "you parked it" card has been raised for the placement that is currently
		--- being announced. See `_apply`.
		self._parkedShown = false
		--- [attribute] = the car key each hand channel last held, false for empty. See `_listen`.
		self._held = {} :: { [string]: string | false }
		self._listenQueued = false
	end,

	start = function(self)
		if not CarryConfig.Enabled then
			return
		end

		--[[ ROBLOX'S BACKPACK GOES DOWN, and it is this feature that asks for it: a carried car is a
			`Tool` (`CarryConfig.Hold.Tool`), and a tool draws itself a hotbar slot at the bottom
			centre of the screen, which is exactly where the Play button is.

			FOR GOOD, RATHER THAN WHILE CARRYING. This game has no other tools, so there is nothing
			in that UI to lose, and a hotbar that appeared and disappeared with a reward would read as
			a glitch. It also takes the keys that unequip with it, which is the first half of the car
			staying in the hand; `CarryService` putting it back on is the second.

			`InterfaceController`'s hide is unharmed: it captures each core type before it writes, so
			it records this as off and restores it as off. ]]
		local tool = CarryConfig.Hold.Tool
		if tool.Enabled and tool.HideBackpack then
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)
		end

		local player = Players.LocalPlayer
		player:GetAttributeChangedSignal(CarryConfig.Attribute):Connect(function()
			self:_apply()
		end)

		--[[ The pickup and place sounds watch both hand attributes (`_listen`). Seeded silently with
			what is already held, so a rejoin with a car in hand does not open on a grab. ]]
		for _, attribute in { CarryConfig.Attribute, LobbyCarConfig.Toy.Attribute } do
			self._held[attribute] = heldBy(attribute) or false
			player:GetAttributeChangedSignal(attribute):Connect(function()
				self:_listen()
			end)
		end

		--[[ ...and the walkthrough's own state, which moves independently of what is in the hands.
			`FirstCarService` raises it before the first car arrives and leaves it up for a while
			after the hands are empty, so neither edge of it can be inferred from the other
			attribute. See `_face` for what each of its three values means. ]]
		player:GetAttributeChangedSignal(CarryConfig.Guide.Attribute):Connect(function()
			self:_apply()
		end)

		--[[ The screen the run ended on has finished lifting, which is the moment a banked car
			becomes something the player can stand and look at in their own hands. See the header:
			`RaceEnd` arms the card and this raises it, a beat later, because `RaceEnd` lands with
			five seconds of results still to run.

			IT ALSO CLEARS THE SUSPENSION, which `RaceEnd` has almost always done already. The two
			are not ordered by anything, and a run that somehow ends with no `RaceEnd` should still
			put the glow back. ]]
		Dispatcher:Subscribe(RaceConfig.ReturnedEvent, function()
			self._suspended = false
			self:_apply()

			local key = self._pendingKey
			if key and player:GetAttribute(CarryConfig.Attribute) == key then
				self:_raise(key, CarryConfig.Hint.Delay)
			end
		end)

		--- A respawn moves the character out from under the glow's distance check, and the plot can
		--- stream in around a player who was already carrying. Both are one `_apply` away.
		player.CharacterAdded:Connect(function()
			self:_apply()
		end)

		self:_apply()
	end,
})

return CarryController
