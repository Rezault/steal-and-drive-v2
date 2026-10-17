--[[
	StartCar page, V2 - SELECT CAR  (client)
	----------------------------------------
	"Which of my cars am I driving into this world?" The third press of Play: Play opens the worlds,
	a world opens this, and a card here starts the run, in that world, in that car.

	`BuildStartCarV2` (Command Runner) cloned the kit's `InventoryUI` into `MainUIV2.Pages.StartCar`
	and its header says why that frame and not `TeamSelectionUI`. This file is the behaviour, and it
	is the cars inventory's (`PagesV2/Dealership`) card grid asking a different question of it.

	=== THE FIVE RULES THE SHIPPING PAGE HAS, UNCHANGED =======================================

	1. THE WORLD'S OWN STARTER IS ALWAYS AVAILABLE and is not a car out of the collection. Its
	   key is `StartCarConfig.DefaultKey` (the empty string), which the server reads as "resolve
	   `WorldConfig.startBodyFor` at spawn time", so a brand-new collection is a page with the car
	   they have always been given on it rather than an empty page. It is the one card with a name
	   known in advance, `Starter`, which is why the tutorial points at it
	   (`TutorialConfig.StartCarPathV2`).

	   An owned copy of that same body in stock livery is skipped: it would be a second card for the
	   identical car. A COLOURED copy is a different car and stays.

	   Unless that stock copy is owned, the starter card says FREE CAR where the rarity goes, so the
	   grid never reads as one more car than the player has (punch list B1, 2026-10-12).

	2. THE PRESS DECIDES NOTHING. It publishes `StartCarConfig.PickEvent` and stops;
	   `StartCarController` pairs the car with the world and hands both to `RaceEntryController`,
	   and the server owns whether you may drive it. Nothing repaints optimistically either: the
	   `StartCar` attribute comes back and repaints for real. `RaceEntryController` closes this page
	   on `RaceStart`, because it is the thing that knows a race actually began; a refused press
	   leaves it up, which is where you would pick again.

	3. PRESSING A CAR STARTS THE RUN. There is no GO button. The X backs out without racing and
	   leaves you exactly where you were, because nothing has moved the player at this point.

	4. A RELEASE ONLY COUNTS IF ITS PRESS BEGAN ON THIS BUTTON. The 24 Aug "no time to choose a
	   vehicle" bug, and the shipping page's guard for it: the world card before this screen presses
	   on the way DOWN, this page draws in the same frame, and on a touch screen the finger that
	   chose the world then released over a car and started a run the player never picked. So a
	   pointer press is armed by `InputBegan` on the button itself, and a release with no matching
	   press is somebody else's press finishing. A gamepad's A has no pointer to arm and comes in on
	   `Activated` alone. See `_wireCard`.

	5. IT REBUILDS ON EVERY OPEN, unlike the cars inventory, because the world can be a different one
	   each time and the world decides the starter card (and, with `StartCarConfig.WorldLadderOnly`,
	   which owned cars are offered at all).

	=== THE DETAIL WINGS (2026-09-17) ========================================================

	The screen has a SELECTED CAR now: press a card's picture and the wings either side of the panel
	show that car turning, its band, its level and its four stats, with a DRIVE button of their own.
	Dylan asked for it on both car screens at once; `Components/CarDetailV2` is the behaviour and
	`BuildCarDetailV2` draws them.

	It does not touch any of the five rules above. The picture had no press on it before, so note 3
	still holds — pressing a CARD starts the run, on one press, including the picked one — and note 4
	is why the wing's own button is armed the same way a card's is. On a pad the PICTURE is in the
	walk, so a console makes the same gesture a pointer does: the highlight landing on it is the
	hover, and A is the press.

	NOTHING BUT A PRESS OPENS THEM, AND THE SAME PRESS SHUTS THEM. The first pass had the page pick a
	car for itself, so the screen came up with both wings already out; Dylan asked for them to wait
	(2026-09-17). A card lights its rim and swells while a pointer is on it or the highlight is, so
	that the grid says a picture can be pressed at all (`Components/CarDetailV2.hoverCard`);
	`_toggleSelect` is the press and it closes what it opened; `_reselect` no longer chooses anything;
	and `_forget` puts the panel away on every open.

	=== WHAT THE KIT CHANGED =================================================================

	  • THE LIST, THE SCROLLBAR AND THE MEASURING. `KitPage` reads the kit's `UIGridLayout` and owns
	    the canvas, so `_measure`, `_buildGrid`, `_applyLayout` and the hand-driven scrollbar with its
	    drag handling all went. Same trade the cars inventory made.
	  • THE CARD SAYS WHICH WORLD. The kit's storage readout names the world this screen is choosing
	    a car for, which the shipping page never printed anywhere.
	  • THE MARKER IS A RIM AND A WORD, not a status line changing colour. Every card's button says
	    DRIVE, because that is what pressing it does, including on the car you drove last time; the
	    stored car is the one with the green rim and the SELECTED chip over its corner.
	  • A SEARCH, because the kit drew one and a collection of forty is a list you scroll to find a
	    car in. The starter is a car like any other and filters like one.

	=== SPAWN MODE, FOR THE LOBBY PAD — 2026-10-08 ===

	The car pad opens this same screen to pick a car to spawn (`StartCarController.openForPad`,
	`LobbyCarConfig.Pad` "YOU PICK THE CAR"). In that mode the title reads SPAWN A CAR, the caption
	YOUR CARS, every button SPAWN, there is no starter card (nothing to spawn: it is not owned) and no
	SELECTED rim (the stored start car means nothing to the pad). Rule 1 is the race flow's alone;
	rules 2-5 hold as written, with "starts the run" read as "spawns it on the pad".

	HOUSE RULE: no wiki-style double-bracket links in this comment; the closing pair ends the block
	comment early and the parse error points at the wrong line.

	2026-10-12: Sell mode reuses this collection grid and offers every owned car, with no starter or
	stored selection. A SELL opens SellPopupController through SellController.offerSelected; it
	never starts a race or spawns a car. The server's RequestSell validates the chosen key and price.

	=== THE FASTEST BADGE — 2026-10-15 ===

	Dylan: "make it so that it tells you which is fastest? Maybe a little badge". The quickest car on
	the grid wears FASTEST in its top right corner, under the name and opposite the mutation glyph.
	The number is the detail wing's SPEED bar (`InventoryConfig.statsFor`: the body's top speed with
	its level and its fitted transmission), so the badge and the bar can never disagree. Paint and
	mutation do not change speed, so two colours of one body at one level are the same speed, and
	every car tied for the top wears it. A grid where nothing is slower than anything else (one card,
	or every card the same body) wears none: the word would be telling the player nothing. It is
	worked out over the whole grid, not the search results, and it does not move the sort.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local CarDetailConfig = require(ReplicatedStorage.shared.Configs.CarDetailConfig)
local CustomizeConfig = require(ReplicatedStorage.shared.Configs.CustomizeConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local InventoryConfig = require(ReplicatedStorage.shared.Configs.InventoryConfig)
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)
local RewardConfig = require(ReplicatedStorage.shared.Configs.RewardConfig)
local StartCarConfig = require(ReplicatedStorage.shared.Configs.StartCarConfig)
local SellConfig = require(ReplicatedStorage.shared.Configs.SellConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
--- A mutation's name for the rarity line (`_paintIdentity`).
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local CarCardDress = require(ReplicatedStorage.shared.Modules.CarCardDress)
local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)
local CarViewportGrid = require(ReplicatedStorage.shared.Modules.CarViewportGrid)
local CarDetail = require(script.Parent.Parent.Components.CarDetailV2)
local KitPage = require(script.Parent.Parent.KitPage)

local PAGE_NAME = StartCarConfig.PageName

local Page = KitPage.extend(PAGE_NAME)

--- The kit's card, as `BuildStartCarV2` left it. The same names the cars inventory uses.
local CARD_NAME = "CarCard"
local FACE_NAME = "Face"

--- The starter's card name. `TutorialConfig.StartCarPathV2` walks to it, so it cannot change alone.
local STARTER_CARD = "Starter"

--- Which car a card is showing, read back off it at press time. See `_wireCard`.
local KEY_ATTRIBUTE = "CarKey"

--- The portrait the viewport grid fills, in the box the kit drew for its own icon.
local CAR_VIEW = "Car"

--- What `BuildCarDetailV2` added to a card: the halo the picked car wears and the invisible press
--- over its picture that picks it. See `Components/CarDetailV2`.
local DETAIL = CarDetailConfig.Parts

--[[ The words. The shipping page keeps its own and so does this one: `StartCarConfig` has no text
	table, and the two that are the same sentence as the cars inventory's (an empty search, an empty
	collection) are read from there so one search screen cannot word it differently from the other. ]]
local TITLE_TEXT = "SELECT CAR"
local DRIVE_TEXT = "DRIVE"
--- SPAWN mode's words (header, "SPAWN MODE").
local SPAWN_TITLE_TEXT = "SPAWN A CAR"
local SPAWN_CAPTION_TEXT = "YOUR CARS"
local SPAWN_TEXT = "SPAWN"
--- Seconds within which a second press on a card's picture counts as a double-click and drives it.
--- Windows' own default double-click time is 0.5s; 0.4 keeps two deliberate single presses (open the
--- stats, then close them) from being read as one.
local DOUBLE_PRESS = 0.4
local SELECTED_TEXT = "SELECTED"
--- The starter's band when it is not one of the player's cars (`_markFree`). Light grey, so it reads
--- as no rarity at all rather than as one more band.
local FREE_TEXT = "FREE CAR"
local FREE_COLOUR = Color3.fromRGB(150, 160, 175)
local TEXT = InventoryConfig.Text

--[[ The FASTEST badge (header, "THE FASTEST BADGE"). A clone of the card's own SELECTED chip, so it is
	the kit's type and navy stroke, in a yellow to orange ramp where SELECTED is green. Top right, under
	the name: the mutation glyph has the top left and SELECTED the bottom, so a card can wear all three. ]]
local FASTEST_NAME = "Fastest"
local FASTEST_TEXT = "FASTEST"
local FASTEST_RAMP = ColorSequence.new(Color3.fromRGB(255, 230, 70), Color3.fromRGB(255, 120, 20))
local FASTEST_AT = UDim2.fromScale(0.95, 0.27)
local FASTEST_SIZE = UDim2.fromScale(0.5, 0.13)
--- Top speeds closer than this are one speed: the level and part multipliers leave float dust.
local SPEED_TIE = 0.01

--[[ How much white goes into the top of a rarity's ramp. Same number and same reason as the cars
	inventory and the market: the kit writes rarity in a two-stop gradient and our bands are one
	flat colour each. ]]
local RARITY_LIFT = 0.35

--- The two input types that can start a press somewhere else and finish it here. Header note 4.
local POINTER_INPUT = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}

local NBSP = "\u{00A0}"

--[[ Header note 4's guard, as a pair of handlers on one button: a pointer's release only counts
	when `InputBegan` saw that kind of press begin HERE. Anything else — a gamepad's A, a keyboard
	selection — has no pointer that could have started somewhere else and goes straight through.

	A FUNCTION RATHER THAN THE HANDLERS INLINE, because there are two buttons that need it now: a
	card's, and the detail wing's, which is drawn under the same finger that pressed the world card
	on the screen before this one. ]]
local function armPointer(button: GuiButton): (InputObject?) -> boolean
	local armed = false
	button.InputBegan:Connect(function(input: InputObject)
		if POINTER_INPUT[input.UserInputType] then
			armed = true
		end
	end)
	return function(input: InputObject?): boolean
		if input and POINTER_INPUT[input.UserInputType] and not armed then
			return false
		end
		armed = false
		return true
	end
end

--- A label that must stay on one line: `TextScaled` would rather wrap than shrink.
local function oneLine(text: string): string
	return (string.gsub(text, " ", NBSP))
end

--- Search keys and typed queries are compared with everything but letters and digits thrown away, so
--- "golf gti", "GolfGTI" and "golf-gti" are one query.
local function normalize(text: string?): string
	return (string.gsub(string.lower(text or ""), "%W", ""))
end

--- A rarity's colour as the ramp the kit drew: lifted towards white at the top, the colour itself at
--- the bottom.
local function rarityRamp(colour: Color3): ColorSequence
	return ColorSequence.new(colour:Lerp(Color3.new(1, 1, 1), RARITY_LIFT), colour)
end

-- === Building ===============================================================

function Page.initialize(self)
	--- The kit's text caps are pixels for a 1080-tall screen; this keeps them in proportion above it.
	KitPage.scaleTextCaps(self.PageUI)

	self.Player = (self.UIController and self.UIController.Player) or Players.LocalPlayer

	--[[ One record per card, in the order the grid lays them out. NOT `self._rows`, which is
		`KitPage`'s. Each is also a `CarViewportGrid.Cell` (`viewport`, `body`, `paint`, `fade`), so
		the list handed to `setCells` is this one rather than a mirror of it. ]]
	self._entries = {} :: { any }
	self._query = ""

	self.TopBar = self.PageUI:FindFirstChild("TopBar")
	self.Note = self.Main and self.Main:FindFirstChild("Note")
	local storage = self.TopBar and self.TopBar:FindFirstChild("Storage")
	self.Caption = storage and storage:FindFirstChild("Title")

	self:setTitle(TITLE_TEXT)

	--[[ THE CELLS IN THE WINDOW'S PIXELS, before a single card exists. Left in the artist's scale, a
		cell's HEIGHT resolves against the canvas: measured on this page with twenty cards, every one
		drew 306px tall in a 266px window (0.52 of a 593px canvas), where the canvas and the viewport
		grid were both counting 139. The collection index found it first; see `KitPage`'s header. ]]
	self:pinGridToWindow()

	--- Before anything is filled: `_applyFilter` hands it the cards on the first pass.
	self._views = CarViewportGrid.new(self.List :: ScrollingFrame, self.PageUI)

	--[[ THE DETAIL WINGS, the same pair the cars inventory has and for a better reason: this is the
		screen where the question IS which car, and the numbers were never on it at all.

		NO CASH LINE. What a car earns standing in your dealership is not a fact about the run you
		are about to start, and this screen is the last thing between the player and the road.

		The press goes through the same guard a card's does (`armPointer`, header note 4): the wing's
		button stands where a finger that pressed the world card on the screen before may be about to
		come up. Nil when the feature is off or the place has not had `BuildCarDetailV2` run over it,
		and every call below is guarded. ]]
	self._detail = CarDetail.new(self.PageUI, {
		source = PAGE_NAME,
		showRate = false,
		onPress = function(key: string, input: InputObject?)
			if self._wingArmed and not self._wingArmed(input) then
				return
			end
			self:_choose(key)
		end,
	})
	if self._detail and self._detail.Action and self._detail.Action:IsA("GuiButton") then
		self._wingArmed = armPointer(self._detail.Action)
	end
	--- The card the wings are describing, and its key kept beside it: a rebuild makes new cards for
	--- the same cars, and this screen rebuilds on every open (header note 5).
	self._selected = nil :: any
	self._selectedKey = nil :: string?

	self:_buildSearch()

	--[[ `KitPage` re-derives the cell on every viewport change; the geometry the viewport grid
		tests against rides along behind it, or the cars stop agreeing with the cards.

		RE-PINNED HERE FIRST rather than trusting `KitPage`'s own handler to have run already: the
		engine does not promise an order between two connections to one signal, and the geometry
		handed on has to be the new cells' numbers. `pinGridToWindow` is safe to call again. ]]
	if self.List then
		self.List:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:pinGridToWindow()
			self:_applyGeometry()
		end)
	end

	self:_watchState()
end

--- The controller that holds the world and the selection, or nil while it is not up.
function Page:_controller()
	return Shard.get("StartCarController")
end

--- Whether this open is the lobby pad's SPAWN screen rather than Play's (header, "SPAWN MODE").
function Page:_padMode(): boolean
	local controller = self:_controller()
	return controller ~= nil and controller:mode() ~= "race"
end

function Page:_sellMode(): boolean
	local controller = self:_controller()
	return controller ~= nil and controller:mode() == "sell"
end

--- The word on every button: what pressing one does in this mode.
function Page:_verb(): string
	if self:_sellMode() then return "SELL" end
	return if self:_padMode() then SPAWN_TEXT else DRIVE_TEXT
end

--- Which world the cards are for. The controller never answers nil; this only covers it not being up.
function Page:_world(): number
	local controller = self:_controller()
	return if controller then controller:world() else WorldConfig.ActiveIndex
end

--[[ The kit's storage readout, which names the world. `BuildStartCarV2` gave it the room a long name
	needs and took its icon away. ]]
function Page:_applyCaption()
	local caption = self.Caption
	if caption and caption:IsA("TextLabel") then
		caption.Text = oneLine(if self:_padMode() then SPAWN_CAPTION_TEXT else string.upper(WorldConfig.displayName(self:_world())))
	end
	self:setTitle(if self:_sellMode() then "SELL YOUR CARS" elseif self:_padMode() then SPAWN_TITLE_TEXT else TITLE_TEXT)
end

-- === The search =============================================================

function Page:_buildSearch()
	local bar = self.TopBar and self.TopBar:FindFirstChild("SearchBar")
	local box = bar and bar:FindFirstChildWhichIsA("TextBox")
	if not box then
		return
	end
	self.SearchBox = box
	box:GetPropertyChangedSignal("Text"):Connect(function()
		self:_setQuery(box.Text)
	end)
end

function Page:_setQuery(text: string)
	local query = normalize(text)
	if query == self._query then
		return -- punctuation-only edits do not change the result set
	end
	self._query = query
	self:_applyFilter()
end

--[[ Which cards are showing, and the list the viewport grid draws cars into. `_entries` is built in
	layout order and a `UIGridLayout` lays out visible children only, so collecting the matches in
	order collects the grid. ]]
function Page:_applyFilter()
	local cells = {}
	for _, entry in self._entries do
		local matches = self._query == "" or string.find(entry.search, self._query, 1, true) ~= nil
		entry.card.Visible = matches
		if matches then
			table.insert(cells, entry)
		end
	end

	self:_updateCanvas()
	self:_updateEmptyState(#cells)

	if self.List then
		self.List.CanvasPosition = Vector2.zero
	end
	--- After the canvas, so the grid tests the new list against the new geometry rather than the old.
	self:_applyGeometry()
	self._views:setCells(cells)

	--- The wings may be describing a car the query has just hidden.
	self:_reselect()
end

function Page:_applyGeometry()
	if not self.List then
		return
	end
	self._views:setLayout(self:cellGeometry())
end

--[[ Which kind of nothing. An empty LIST only happens when the world's start body is missing from
	the config, which is a broken page rather than an empty collection, and the shipping page says
	the same thing for it. ]]
function Page:_updateEmptyState(visible: number)
	local note = self.Note
	if not (note and note:IsA("TextLabel")) then
		return
	end
	note.Visible = visible <= 0
	note.Text = oneLine(if #self._entries <= 0 then TEXT.NoCars else TEXT.NoMatch)
end

-- === The cards ==============================================================

--[[ One card. `key` is what the press sends: "Body:paint" for a car out of the collection, or
	`StartCarConfig.DefaultKey` for the starter, whose body is passed in because there is no key to
	read it out of. ]]
function Page:_makeCard(key: string, body: string, paint: number, order: number, mutation: string?)
	local card = self:newRow(CARD_NAME)
	if not card then
		return nil
	end
	card.Name = if StartCarConfig.isDefault(key) then STARTER_CARD else key
	card.LayoutOrder = order
	card:SetAttribute(KEY_ATTRIBUTE, key)

	local face = card:FindFirstChild(FACE_NAME)
	local icon = face and face:FindFirstChild("Icon")
	local btns = card:FindFirstChild("Btns")

	local entry = {
		key = key,
		card = card,
		face = face,
		--- `CarViewportGrid.Cell`'s fields, which is why this record is handed to it directly.
		body = body,
		paint = paint,
		--- Drawn on the car and worded on the rarity line (2026-10-14: "in the select car menu I can't
		--- see mutations"), as on the cars inventory (`PagesV2/Dealership`).
		mutation = mutation,
		fade = 0,
		viewport = nil :: ViewportFrame?,

		title = face and face:FindFirstChild("Title"),
		rarity = face and face:FindFirstChild("Rarity"),
		chip = face and face:FindFirstChild("Selected"),
		rim = face and face:FindFirstChild("Rim"),
		action = btns and btns:FindFirstChild("EquipBtn"),
		--- The detail wings' three additions. All nil on a place built before they landed.
		halo = face and face:FindFirstChild(DETAIL.Halo),
		hover = face and face:FindFirstChild(DETAIL.Hover),
		pick = face and face:FindFirstChild(DETAIL.Select),
		--- The mutation's name leads the key (2026-10-14), so "molten" finds every molten car.
		search = normalize((if mutation then WeatherConfig.nameOf(mutation) .. " " else "") .. GarageConfig.carName(body, paint)),
	}

	--[[ The portrait, over the box the kit drew for its own picture, exactly as on the cars
		inventory: `CarViewport` owns the camera and the lighting, and the kit's picture goes rather
		than staying underneath as a fallback. It is a pink rabbit and the cars arrive a couple a
		frame (`CarViewportGrid`), so left there it is what an opening page shows first. The box
		stays; see `PagesV2/Dealership._makeCard` for the whole of the reasoning. ]]
	if icon and icon:IsA("GuiObject") then
		if icon:IsA("ImageLabel") then
			icon.Image = ""
		end
		local view = CarViewport.new(face :: GuiObject, CAR_VIEW)
		view.AnchorPoint = icon.AnchorPoint
		view.Position = icon.Position
		view.Size = icon.Size
		view.ZIndex = icon.ZIndex
		entry.viewport = view
	end

	self:_paintIdentity(entry)
	self:_wireCard(entry)
	return entry
end

--- What a card says about WHICH car it is. Fixed for the life of the card, so it is painted once.
function Page:_paintIdentity(entry)
	local title = entry.title
	if title and title:IsA("TextLabel") then
		title.Text = GarageConfig.carName(entry.body, entry.paint)
	end

	local rarity = entry.rarity
	if rarity and rarity:IsA("TextLabel") then
		--[[ `CarRarity` rather than the tier number the shipping card printed: the same ladder, in
			the one word and colour every other V2 car card uses. A body on no ladder answers the
			empty string and the line stays blank rather than inventing a band. ]]
		local word, colour = CarRarity.labelOf(entry.body)
		rarity.Text = oneLine(string.upper(word))
		local tint = rarity:FindFirstChild("Tint")
		if tint and tint:IsA("UIGradient") then
			tint.Color = rarityRamp(colour)
		end
	end

	local action = entry.action
	local label = action and action:FindFirstChild("Title")
	if label and label:IsA("TextLabel") then
		label.Text = if self:_sellMode() then "SELL " .. GarageConfig.formatCash((SellConfig.lotPriceForOwner(self.Player, entry.key))) else self:_verb()
	end

	local chip = entry.chip
	if chip and chip:IsA("TextLabel") then
		chip.Text = SELECTED_TEXT
	end
	--- The inventory's card: rarity face, name on top, mutation glyph (`Modules/CarCardDress`).
	CarCardDress.apply(entry.face, entry.title, entry.rarity, entry.body, entry.mutation)
end

--- The starter card when the player does not own it: FREE in the rarity band, so the grid does not
--- count it as one of their cars. See `_rebuild`.
function Page:_markFree(entry)
	local rarity = entry.rarity
	if not (rarity and rarity:IsA("TextLabel")) then
		return
	end
	rarity.Text = oneLine(FREE_TEXT)
	local tint = rarity:FindFirstChild("Tint")
	if tint and tint:IsA("UIGradient") then
		tint.Color = rarityRamp(FREE_COLOUR)
	end
end

--[[ FASTEST on the quickest car, and on every car tied with it (header, "THE FASTEST BADGE"). Read
	off the same two broadcasts the detail wing reads its SPEED bar from: the level per body, and the
	fitted parts per car ID. The starter's key is not an ID, so it has no parts, which is also true of
	the car the server hands out for it. ]]
function Page:_markFastest()
	local levels = RewardConfig.decodeLevels(self.Player:GetAttribute(GarageConfig.LevelsAttribute))
	local parts = CustomizeConfig.decodeParts(self.Player:GetAttribute(CustomizeConfig.PartsAttribute))

	local top, bottom = -math.huge, math.huge
	for _, entry in self._entries do
		entry.speed = InventoryConfig.statsFor(entry.body, levels[entry.body], parts[entry.key]).MaxSpeed
		top = math.max(top, entry.speed)
		bottom = math.min(bottom, entry.speed)
	end
	local anySlower = top - bottom > SPEED_TIE

	for _, entry in self._entries do
		local face = entry.face
		local badge = face and face:FindFirstChild(FASTEST_NAME)
		local fastest = anySlower and entry.speed >= top - SPEED_TIE
		if not fastest then
			if badge then
				badge:Destroy()
			end
			continue
		end
		local chip = entry.chip
		if badge or not (chip and chip:IsA("TextLabel")) then
			continue
		end
		local made = chip:Clone()
		made.Name = FASTEST_NAME
		made.Text = oneLine(FASTEST_TEXT)
		made.AnchorPoint = Vector2.new(1, 0)
		made.Position = FASTEST_AT
		made.Size = FASTEST_SIZE
		made.Visible = true
		local tint = made:FindFirstChild("Tint")
		if tint and tint:IsA("UIGradient") then
			tint.Color = FASTEST_RAMP
		end
		made.Parent = face
	end
end

--[[ The press, and header note 4's guard on it.

	`Activated` is the one event a mouse, a touch and a gamepad's A all raise. A POINTER's only
	counts when `InputBegan` saw that same kind of press start on this button; anything else
	(a gamepad, a keyboard selection) has no pointer that could have started somewhere else and
	goes straight through. The key is read off the CARD at press time, for the cars inventory's
	reason: a rebuild can never leave a button acting on the car that used to be in its slot. ]]
function Page:_wireCard(entry)
	--[[ A press on the PICTURE opens the wings on that car, and the same press again puts them away.
		It is not the verb — the button under it still starts the run on one press — so a player who
		never touches a picture has the screen that shipped, and one who does can read a car's numbers
		without committing to drive it. No arming guard: picking a car cannot start a race, which is
		the one thing note 4 exists to stop happening by accident.

		THE SAME PRESS ON A PAD. The picture is in the gamepad's walk (`BuildCarDetailV2` makes it
		selectable), so the highlight landing on it is the hover and A is the click. A card here has
		no star, so the ladder between the picture and the button below it is one the engine's own
		search gets right and nothing is wired by hand. ]]
	local pick = entry.pick
	if pick and pick:IsA("GuiButton") then
		--[[ A DOUBLE PRESS ON THE PICTURE DRIVES IT (2026-09-28): the second press inside
			`DOUBLE_PRESS` of the first is the DRIVE button under it, and does NOT toggle the wings shut
			— the first press opened them, and a double-click that flashed the panel open and closed
			before the run started would read as a glitch. Note 4's guard still stands: this is two whole
			presses on the picture itself, and a stray release from the world screen is at most one. ]]
		local lastPress = 0
		pick.Activated:Connect(function()
			local now = os.clock()
			if now - lastPress <= DOUBLE_PRESS then
				lastPress = 0
				self:_choose(entry.card:GetAttribute(KEY_ATTRIBUTE))
				return
			end
			lastPress = now
			self:_toggleSelect(entry)
		end)

		--- The card says so while a pointer is on it or the highlight is: the rim lights and the card
		--- swells. Since the wings stopped opening by themselves this is the only thing on the grid
		--- that says a picture can be pressed at all. `Components/CarDetailV2` owns the reaction.
		CarDetail.hoverCard(entry.card, pick, entry.hover)
	end

	local action = entry.action
	if not (action and action:IsA("GuiButton")) then
		return
	end

	local mayFire = armPointer(action)
	action.Activated:Connect(function(input: InputObject?)
		if not mayFire(input) then
			return
		end
		self:_choose(entry.card:GetAttribute(KEY_ATTRIBUTE))
	end)
end

--[[ Rebuild the list for the world this screen was opened for, best first INCLUDING the starter.
	Header notes 1 and 5. The tutorial identifies the starter by name, not by grid position.

	The controller owns both lists, so the rule about what may be driven where is written down
	once, next to the code that also has to explain it to the server. ]]
function Page:_rebuild()
	--- Emptied BEFORE the cards go, so the grid lets go of viewports that still exist.
	self._views:clear()
	self:clearRows()
	table.clear(self._entries)

	local controller = self:_controller()
	local world = self:_world()

	local owned = if controller then controller:driveable(world) else {}

	--- No starter in SPAWN mode: it is not an owned car, so the pad has nothing to put out for it.
	local starterBody = if self:_padMode() then nil else WorldConfig.startBodyFor(world)
	local skip: string? = nil
	if starterBody then
		skip = GarageConfig.carKey(starterBody, PaintConfig.StockIndex)
		local starter = self:_makeCard(StartCarConfig.DefaultKey, starterBody, PaintConfig.StockIndex, 1)
		if starter then
			table.insert(self._entries, starter)
			--[[ B1, 2026-10-12: Aleafo owned three cars, this grid drew four, and he read it as the
				game miscounting. The fourth was this card, which looked exactly like a car he owned. So
				it says FREE where the rarity goes, unless he owns the stock copy, whose card this is. ]]
			local ownsStock = false
			for _, key in owned do
				if GarageConfig.modelKeyOf(key) == skip then
					ownsStock = true
					break
				end
			end
			if not ownsStock then
				self:_markFree(starter)
			end
		end
	end

	for _, key in owned do
		if GarageConfig.modelKeyOf(key) == skip then
			continue
		end
		local body, paint, mutation = GarageConfig.parseCarKey(key)
		if not body then
			continue
		end
		local entry = self:_makeCard(key, body, paint or PaintConfig.StockIndex, #self._entries + 1, mutation)
		if entry then
			table.insert(self._entries, entry)
		end
	end

	-- 2026-10-04: sorting only the owned list pinned the weakest starter above every upgrade.
	-- Sort the complete grid by tier, then key for stable ties, before search and gamepad layout.
	table.sort(self._entries, function(a, b)
		local ta = GarageConfig.TierOfBody[a.body] or 0
		local tb = GarageConfig.TierOfBody[b.body] or 0
		return if ta ~= tb then ta > tb else a.key < b.key
	end)
	for order, entry in self._entries do
		entry.card.LayoutOrder = order
	end
	self:_markFastest()
	self:_applyFilter()
end

--[[ Mark the car the server has stored, without rebuilding. Runs on every change to the `StartCar`
	attribute and on every open, so it is the one that has to be cheap.

	THE STARTER IS MARKED WHEN NOTHING ELSE MATCHES, and that is what the server does rather than a
	guess at it: a stored car this list does not hold is either the stock copy of the starter body
	(skipped, header note 1, and the same car) or one the player no longer owns, which
	`StartCarService` answers with the world's starter. Either way the run starts in the car on the
	starter card, so that is the card that says so. ]]
function Page:_refresh()
	local controller = self:_controller()
	local chosen = if controller then controller:selected() else StartCarConfig.DefaultKey

	local marked = nil
	for _, entry in self._entries do
		if entry.key == chosen then
			marked = entry
			break
		end
	end
	--- SPAWN mode marks nothing: the stored START car is not a fact about the pad.
	if self:_padMode() then
		marked = nil
	elseif not marked then
		for _, entry in self._entries do
			if StartCarConfig.isDefault(entry.key) then
				marked = entry
				break
			end
		end
	end

	for _, entry in self._entries do
		local here = entry == marked
		if entry.rim and entry.rim:IsA("UIStroke") then
			entry.rim.Enabled = here
		end
		if entry.chip and entry.chip:IsA("GuiObject") then
			entry.chip.Visible = here
		end
	end

	--- The wings pick a car up again after a rebuild, and follow the stored car when nothing else
	--- has been picked.
	self:_reselect()
end

-- === The detail wings =======================================================

--[[ Pick a car: the wings describe it and its card wears the halo. Every line is safe without them —
	`_detail` is nil when the feature is off and `halo` is nil on a card built before it landed. ]]
function Page:_select(entry)
	--- No wings, no selection: with the feature off this is the page that shipped, rather than the
	--- page that shipped plus a halo lighting up cards for a panel nobody has.
	if not (self._detail and entry and entry.key) then
		return
	end
	if self._selected == entry and self._detail and self._detail:isShowing() then
		return
	end

	self._selected = entry
	self._selectedKey = entry.key
	for _, other in self._entries do
		if other.halo and other.halo:IsA("UIStroke") then
			other.halo.Enabled = other == entry
		end
	end

	if self._detail then
		self._detail:show(entry)
		--- Every card on this screen says DRIVE, including the one already stored: pressing it still
		--- starts the run. So does the wing's, and it says the same word for the same reason.
		self._detail:setAction(if self:_sellMode() then "SELL " .. GarageConfig.formatCash((SellConfig.lotPriceForOwner(self.Player, entry.key))) else self:_verb(), true, "")
	end
end

--[[ The press on a card's picture: describe this car, or put the panel away when it is already the
	one being described. Dylan, 2026-09-17: "if you click the card again, the stats go away."

	SEPARATE FROM `_select` BECAUSE ONLY A PRESS MAY TOGGLE. `_reselect` re-points the panel at the
	rebuilt card for the car it is already showing — this page rebuilds on every open — and a toggle
	there would read that as a second press and put the wings away. It is the same reason the pad's
	highlight no longer picks: a panel that shut because the DPad passed back over its card is one
	nobody could keep open. ]]
function Page:_toggleSelect(entry)
	if not (self._detail and entry and entry.key) then
		return
	end
	if self._selected == entry and self._detail:isShowing() then
		self:_forget()
		return
	end
	self:_select(entry)
end

--[[ Keep the panel pointed at the car it is already describing, and let that car go when it leaves
	the screen. Does nothing in the usual case.

	IT NEVER PICKS A CAR, and it used to: with nothing selected it chose the car the run would start
	in if the player pressed nothing, so this screen opened with both wings already out. Dylan asked
	for that to stop on 2026-09-17 — the wings answer a press now and nothing else, and the cards say
	so under the pointer (`Components/CarDetailV2.hoverCard`). What is left is bookkeeping: this page
	rebuilds its cards on every open (header note 5), so the entry the panel was pointed at is a dead
	frame and the same car has to be found again by key. ]]
function Page:_reselect()
	local detail = self._detail
	if not (detail and self._selectedKey and detail:isShowing()) then
		return
	end

	local current = self._selected
	if current and current.key == self._selectedKey and current.card.Parent ~= nil and current.card.Visible then
		return
	end

	local keep = nil
	for _, entry in self._entries do
		if entry.key == self._selectedKey and entry.card.Visible then
			keep = entry
			break
		end
	end

	if keep then
		self._selected = nil
		self:_select(keep)
	else
		--- A query has hidden it, or the roster no longer has it. There is nothing to describe.
		self:_forget()
	end
end

--[[ Nothing is picked any more: the halos go out and the wings go away.

	ALSO WHAT AN OPEN STARTS FROM. A screen is reopened with its grid to itself, which is the other
	half of "a press opens them": a page that remembered the last car picked would come back up with
	the panel already out, which is the thing that was asked to stop. ]]
function Page:_forget()
	self._selected = nil
	self._selectedKey = nil
	for _, entry in self._entries do
		if entry.halo and entry.halo:IsA("UIStroke") then
			entry.halo.Enabled = false
		end
	end
	if self._detail then
		self._detail:clear()
	end
end

--- A card was pressed. Say which one and stop: header note 2.
function Page:_choose(key: string?)
	Dispatcher:Publish(StartCarConfig.PickEvent, key or StartCarConfig.DefaultKey)
end

function Page:_watchState()
	self:_applyCaption()
	self:_rebuild()
	self:_refresh()

	--[[ ONLY WHILE OPEN (2026-10-07). Every open already rebuilds (`StartOpenThread`), so a rebuild of a
		CLOSED picker is work nobody sees — and the bank moves this attribute, so it ran on the bank's
		frame and was one of the things behind the first-bank freeze (`Modules/HitchProbe`). The same
		fix `PagesV2/Dealership._requestRebuild` carries, simpler here because the open covers it. ]]
	self.Player:GetAttributeChangedSignal(GarageConfig.OwnedAttribute):Connect(function()
		if self.PageUI and self.PageUI.Visible then
			self:_rebuild()
			self:_refresh()
		end
	end)
	self.Player:GetAttributeChangedSignal(StartCarConfig.Attribute):Connect(function()
		self:_refresh()
	end)
end

-- === Open and close =========================================================

--[[ Header note 5: a full rebuild, because the world may have changed. The search is cleared first,
	since a query typed last time is a list that opens with most of it missing and no visible reason.

	`_query` IS CLEARED BY HAND as well as the box. The box's `Text` signal is deferred, so it lands
	after the rebuild below has already filtered by the old query: in the probe, a reopen after
	searching "zzz" read back zero cards showing and the empty note up, until that signal caught up
	and filtered again. Probably never drawn, since deferred signals run inside the frame, but a list
	that is only right because of when the engine flushes is not a list to leave. ]]
function Page:StartOpenThread()
	--- Every open starts with nothing picked. See `_forget`.
	self:_forget()

	self._query = ""
	if self.SearchBox and self.SearchBox.Text ~= "" then
		self.SearchBox.Text = ""
	end
	self:_applyCaption()
	self:_rebuild()
	self:_refresh()
	if self.List then
		self.List.CanvasPosition = Vector2.zero
	end
end

--[[ The viewport grid watches the page's own `Visible` and empties itself, so the cards need
	nothing here. The WINGS do: the rail is standing aside for them and should come back as the panel
	leaves rather than after it, and a car turning behind a closing page is work nobody can see. ]]
function Page:StartCloseThread()
	if self._detail then
		self._detail:suspend()
	end
end

return Page
