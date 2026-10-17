--[[
	CarDetailV2  (client component)
	-------------------------------
	THE CAR DETAIL WINGS: the panel on the left of a car screen with the car itself turning in it,
	and the panel on the right with what it is made of. `BuildCarDetailV2` draws them, this fills
	them, and both car screens — `PagesV2/Dealership` and `PagesV2/StartCar` — own one.

	Dylan asked for it on 2026-09-17 off a reference shot of an anime unit collector: a grid in the
	middle, the thing you picked on one side and its numbers on the other. It is also the answer to
	the gap `docs/NewUI-Migration-Notes.md` has carried since the V2 inventory shipped — the
	shipping page's hover tooltip never made the crossing, and that note already said the honest
	version of it is a panel a press opens rather than a panel a pointer summons.

	=== WHAT IT KNOWS AND WHAT THE PAGE KNOWS ================================================

	This component knows how to describe A CAR: its name, its band, its picture, what it earns, how
	far up its own ladder it is and where its four stats land. All of that is a function of the car
	key and the levels attribute, so it reads those for itself and repaints when they change.

	THE PAGE KNOWS THE VERB. PARK HERE, SPAWN, PUT AWAY, CLEAR BAY and DRIVE are things about a
	screen and a mode, not about a car, and the page already works every one of them out for the
	button on the card (`_paintButton`). So it hands the same two strings down with `setAction` and
	this file only draws them. A component that tried to work the verb out itself would be a second
	opinion about what a press does, and the two would disagree the first time a mode changed.

	=== FOUR THINGS TO KNOW ==================================================================

	1. THE CAR IS BUILT ONCE PER CAR, NOT PER PAINT OF THE PANEL. `show` is called again on every
	   repaint — an attribute changed, the mode changed, the player spawned the car it is describing
	   — and rebuilding twenty-five meshes each time would make a repaint cost more than a page open.
	   The body and the paint are remembered, and the model is only remade when one of them moves.

	2. IT TURNS, AND THAT IS THE WHOLE REASON THIS PICTURE IS NOT A CARD'S. `Modules/CarViewport`
	   owns the turntable (`spin`): a fixed radius settled over a whole revolution so the car cannot
	   breathe in and out of frame, and the aim recomputed per frame so it stays centred as its
	   silhouette changes. The cards keep still pictures, because forty turning cars is forty cameras
	   a frame.

	3. IT STOPS WHEN THE PANEL IS PUT AWAY. `suspend` drops the spin and gives the rail back the
	   moment a close begins; `clear` empties the viewport once the page is actually hidden, so a
	   shut screen is not holding a car model. The page calls the first and the page's own `Visible`
	   calls the second, which is the same arrangement `Modules/CarViewportGrid` uses and for the
	   same reason: a page can be closed by things that never call the page.

	4. THE WINGS ARE A PRESS, AND THEY COME OUT OF THE PANEL. Nothing opens them but a press on a
	   card's picture (`_toggleSelect`, on either page), and the same press again puts them away.
	   Before 2026-09-17 a page opened with a car already picked, and a panel that shows up by itself
	   teaches nobody that the cards are the way in. So the cards answer the pointer now (`hoverCard`
	   below) and the wings answer only a press, and when they do they GROW OUT of the page's own edge
	   rather than appearing beside it (`_pop`).

	   ON A PAD IT IS THE SAME PRESS. The card's picture is in the gamepad's walk
	   (`BuildCarDetailV2`'s `Selectable`), the highlight landing on it is the hover, and A is the
	   click. It used to be the HIGHLIGHT that picked, which cannot survive a toggle: the panel would
	   open and shut as the DPad crossed the grid.

	5. THE RAIL STEPS ASIDE WHILE THE WINGS ARE UP. `BuildCarDetailV2`'s header has the arithmetic —
	   there is no width at which a readable panel fits between a centred kit page and the HUD's icon
	   grid. This ASKS, under its own source name, and `RaceEntryController` writes, exactly as
	   `UIController._syncPlayRoom` asks for the Play button. One writer, so a race and a panel can
	   never disagree about that frame.

	HOUSE RULE: no wiki-style double-bracket links in this comment; the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local CarDetailConfig = require(ReplicatedStorage.shared.Configs.CarDetailConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local InventoryConfig = require(ReplicatedStorage.shared.Configs.InventoryConfig)
-- The value line, without passive income: the same pure price the server pays. See `_paint`.
local MarketValueConfig = require(ReplicatedStorage.shared.Configs.MarketValueConfig)
--- Only for the name of the parts broadcast the value line repaints on.
local CustomizeConfig = require(ReplicatedStorage.shared.Configs.CustomizeConfig)
local RewardConfig = require(ReplicatedStorage.shared.Configs.RewardConfig)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)

local CarDetailV2 = {}
CarDetailV2.__index = CarDetailV2

local NAMES = CarDetailConfig.Parts
local TEXT = CarDetailConfig.Text

--- The viewport's name inside the portrait box. One car, so it needs no more than a name.
local CAR_VIEW = "Car"

--[[ The picture's shape before the screen has ever been laid out, width over height.

	A page can fill itself on the frame it is built, ahead of any layout pass (`KitPage`'s header:
	layout resolves on hidden frames, but not before the first one), and `AbsoluteSize` is zero until
	then. This is what `BuildCarDetailV2` draws the box at; the real number replaces it the moment
	there is one, and a viewport fitted to the wrong shape for one frame is not visible. ]]
local FALLBACK_ASPECT = 1.4

--- How far the portrait has to change shape before the shot is refitted. A window drag moves it a
--- pixel at a time, and refitting on every one of those is a bisection per frame for no difference.
local ASPECT_TOLERANCE = 0.02

--[[ How much white goes into the top of a rarity's ramp. The kit writes a rarity in a two-stop
	gradient, light at the top and saturated at the bottom, and our bands are one flat colour each
	(`CarRarity.Colours`), so the colour is the bottom stop and this is the lift on the top one. Same
	number and the same reason as the card's own rarity and the market's listing row. ]]
local RARITY_LIFT = 0.35

--[[ THE POP: a wing does not appear beside the page, it comes OUT of it. It starts half size, tucked
	against the page's own edge, and grows outward into its place.

	THE ANCHOR DOES THE WORK. Each wing is anchored on the edge FACING the page (the left one on its
	right side, the right one on its left), so a `UIScale` under one shrinks it towards that edge
	rather than towards its own middle, and growing it back plays as the panel pushing it out.
	Nothing has to be clipped and nothing has to be drawn behind the page for that to read, which is
	what both alternatives needed: the page's own `Main` is opaque and the HUD sits under the pages,
	so a wing that really slid out from inside would be either over the cards or under the HUD.

	THE TIMINGS ARE THE PAGE'S OWN, out of `UIController` (`OPEN_TWEEN` and `CLOSE_TWEEN`), so a wing
	and the panel it belongs to move alike. Dylan asked for the movement on 2026-09-17 off First to
	Destroy, where picking a rocket pushes its panel out of the menu. ]]
local POP_SCALE_NAME = "WingPop"
local POP_FROM = 0.5
local POP_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SHUT_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

--- How long after the left wing the right one follows it out. Small on purpose: the pair should read
--- as one movement with a lean to it rather than as two panels taking turns.
local POP_STAGGER = 0.05

--[[ WHAT A CARD DOES UNDER THE POINTER, which is the other half of "the wings are a press": a grid
	that reacts to the pointer is a grid that says its cards can be pressed, and until now the
	pictures were the one pressable thing in this UI that gave nothing back.

	THE RING IS THE CARD'S OWN RIM drawn thicker and brought up to solid (`BuildCarDetailV2` cuts it
	off the artist's stroke), so a hovered card is the artist's card with its edge lit rather than a
	card wearing a second opinion about its border. It is the SATURATED end of the page's ramp where
	the halo is the light end, because the two say different things — and because white, which it was
	until Dylan looked at it, has a contrast ratio of 1.00 against the white grid the cards are laid
	out on. `HOVER_THICKNESS` in the builder carries the measurements.

	THE SWELL IS `Components/Button`'S, a hair smaller: a card is several times the size of a kit
	button, so the same fraction of it is a much bigger movement. ]]
local HOVER_SCALE_NAME = "HoverPop"
local HOVER_SCALE = 1.035
local HOVER_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local HOVER_OUT_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--- The ring's own fade, on an ease that cannot overshoot: `Back` aimed at a transparency would
--- overshoot past the ends of that property's range.
local RING_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local NBSP = "\u{00A0}"

--- Fill a template out of `CarDetailConfig.Text`, with every space made non-breaking: `TextScaled`
--- would rather wrap a label to a second line than shrink it, and these boxes are one line tall.
local function fill(template: string, fields: { [string]: string | number }?): string
	local text = template
	if fields then
		text = (string.gsub(text, "{(%w+)}", function(name)
			local value = fields[name]
			return if value ~= nil then tostring(value) else "{" .. name .. "}"
		end))
	end
	return (string.gsub(text, " ", NBSP))
end

--- A rarity's colour as the ramp the kit drew: lifted towards white at the top, the colour itself at
--- the bottom. Two stops, which is what the artist's own gradient has.
local function rarityRamp(colour: Color3): ColorSequence
	return ColorSequence.new(colour:Lerp(Color3.new(1, 1, 1), RARITY_LIFT), colour)
end

--[[ Set a kit bar to a fraction of its track.

	RESIZED, not cut by transparency: the fill carries the ramp and the rim, and a fill drawn full
	width under a transparency mask is a bar whose end cap never moves. Hidden outright at zero,
	because a pill squeezed to nothing still draws its own rim. Same two rules as the quest rows,
	which is where this bar was cut from. ]]
local function setBar(bar: GuiObject?, ratio: number)
	if not bar then
		return
	end
	local level = math.clamp(ratio, 0, 1)
	bar.Visible = level > 0
	bar.Size = UDim2.new(level, 0, bar.Size.Y.Scale, bar.Size.Y.Offset)
end

--- The shape of a box, or the authored one while there is no layout to read.
local function aspectOf(frame: GuiObject): number
	local size = frame.AbsoluteSize
	if size.X > 0 and size.Y > 0 then
		return size.X / size.Y
	end
	return FALLBACK_ASPECT
end

--[[ Bind the wings on `page`. Nil when the feature is off or the page has not been rebuilt since it
	landed, which is a page that behaves exactly as it did before — the caller checks for nil and
	carries on, so a place missing the build is a screen without wings rather than a screen that
	throws.

	`options.source` is what this asks for the rail under, and it must be per PAGE: two screens have
	one of these each, and two askers sharing a name is one of them putting the rail back while the
	other is still using the room. ]]
export type Options = {
	source: string,
	--- The cash line is the cars inventory's question ("what is this car worth to me standing
	--- there"); the car picker hides it, because nothing on that screen is about money.
	showRate: boolean?,
	--[[ What a press on the wing's button does. The page owns it; see the header.

		THE INPUT IS PASSED ON because one caller needs it: the car picker arms a pointer press on
		its own buttons (a release with no matching press is the finger that chose the WORLD on the
		screen before, coming up over this one), and it can only apply that guard if it is told what
		kind of press this was. ]]
	onPress: ((key: string, input: InputObject?) -> ())?,
	--[[ What a press on the SECOND button does, and whether there is one at all: a page that passes
		nothing gets exactly the one-button panel that shipped. The page decides what it says, per
		car, through `setSecondary` — see that function. ]]
	onSecondary: ((key: string) -> ())?,
}

--- The clone of the button band that carries the second verb. See `setSecondary`.
local SECONDARY_NAME = "SecondaryButtons"
--- Share of the band's width each half takes when it is split; the rest is the gap between them.
local SPLIT_SHARE = 0.48

function CarDetailV2.new(page: GuiObject, options: Options)
	if not CarDetailConfig.Enabled then
		return nil
	end

	local left = page:FindFirstChild(NAMES.Left)
	local right = page:FindFirstChild(NAMES.Right)
	if not (left and left:IsA("GuiObject") and right and right:IsA("GuiObject")) then
		return nil
	end

	local self = setmetatable({}, CarDetailV2)
	self.Player = Players.LocalPlayer
	self.Page = page
	self.Left = left :: GuiObject
	self.Right = right :: GuiObject
	self.Source = options.source
	self._showRate = options.showRate ~= false
	self._onPress = options.onPress

	--[[ THE TWO WINGS AS THE POP KNOWS THEM: the frame, the scale it grows on, where it rests and
		where it is tucked away. `edge` is the page edge each one comes out of, and it is the X the
		builder anchored that wing to — the left wing is anchored on its RIGHT side, and that side
		rests just off the page's left edge, which is 0. ]]
	self._wings = {}
	for _, side in { { frame = left :: GuiObject, edge = 0 }, { frame = right :: GuiObject, edge = 1 } } do
		local frame = side.frame
		local found = frame:FindFirstChild(POP_SCALE_NAME)
		local scale: UIScale
		if found and found:IsA("UIScale") then
			scale = found
		else
			scale = Instance.new("UIScale")
			scale.Name = POP_SCALE_NAME
			scale.Parent = frame
		end
		local rest = frame.Position
		table.insert(self._wings, {
			frame = frame,
			scale = scale,
			rest = rest,
			tucked = UDim2.new(side.edge, rest.X.Offset, rest.Y.Scale, rest.Y.Offset),
			tweens = {} :: { Tween },
		})
	end

	--- Are the wings OUT? Not the same question as "is there a car": a retract is still running for
	--- a sixth of a second after the car has been let go of.
	self._open = false
	--- Bumped by every pop. A retract that an open interrupts must not shut the panel it has stopped
	--- being about, and a cancelled tween still leaves its `Completed` connection holding a closure.
	self._popToken = 0

	--- What the wings are describing: `{ key, body, paint, mutation }`, or nothing.
	self._car = nil :: any
	--- What the VIEWPORT is showing, which lags the above by design — see header note 1.
	self._shownBody = nil :: string?
	self._shownPaint = nil :: number?
	self._aspect = 0
	self._spin = nil :: any
	self._railHeld = false

	self.Name = left:FindFirstChild(NAMES.Name)
	self.Rarity = left:FindFirstChild(NAMES.Rarity)
	self.Tint = self.Rarity and self.Rarity:FindFirstChild(NAMES.Tint)
	self.Portrait = left:FindFirstChild(NAMES.Portrait)
	self.Rate = left:FindFirstChild(NAMES.Rate)
	self.Level = left:FindFirstChild(NAMES.Level)
	local levelBar = left:FindFirstChild(NAMES.Bar)
	self.LevelFill = levelBar and levelBar:FindFirstChild(NAMES.Fill)

	local buttons = right:FindFirstChild(NAMES.Buttons)
	self.Action = buttons and buttons:FindFirstChild(NAMES.Action)
	self.State = buttons and buttons:FindFirstChild(NAMES.State)

	--[[ THE SECOND BUTTON (2026-09-28), built here by cloning the band `BuildCarDetailV2` authored,
		rather than by the builder. A builder change is a Command Runner pass over the place before
		anyone can see it; a clone of the band that is already there inherits its art, its tags (so
		the kit's hover, sound and gamepad highlight come with it) and its text cap, and needs nothing
		run. Only the green face is kept: the second verb is never a "this is already so" state.

		Hidden until a page asks for it. `_band` remembers where the builder put the original, so
		putting the second button away puts the first back exactly. ]]
	self._onSecondary = options.onSecondary
	if options.onSecondary and buttons and buttons:IsA("GuiObject") then
		local second = buttons:Clone()
		second.Name = SECONDARY_NAME
		for _, face in second:GetChildren() do
			if face:IsA("GuiObject") then
				face.Visible = face.Name == NAMES.Action
			end
		end
		second.Visible = false
		second.Parent = buttons.Parent
		self._band = { frame = buttons, position = buttons.Position, size = buttons.Size }
		self._second = second
		self.SecondAction = second:FindFirstChild(NAMES.Action)

		local action = self.SecondAction
		if action and action:IsA("GuiButton") then
			action.Activated:Connect(function()
				local car = self._car
				if car and car.key and self._onSecondary then
					self._onSecondary(car.key)
				end
			end)
		end
	end

	--[[ The stat rows, in the order `InventoryConfig` draws them. Matched by the attribute the
		builder stamped rather than by position, so a stat added in the middle of that table lands in
		its own row instead of shifting every row after it by one. ]]
	self._rows = {}
	local stats = right:FindFirstChild(NAMES.Stats)
	if stats then
		local byKey = {}
		for _, row in stats:GetChildren() do
			local key = row:GetAttribute("Stat")
			if type(key) == "string" then
				byKey[key] = row
			end
		end
		for _, stat in InventoryConfig.Stats do
			local row = byKey[stat.Key]
			local bar = row and row:FindFirstChild(NAMES.Bar)
			if row then
				table.insert(self._rows, {
					stat = stat,
					fill = bar and bar:FindFirstChild(NAMES.Fill),
					rating = row:FindFirstChild(NAMES.Rating),
				})
			end
		end
	end

	if self.Rate and self.Rate:IsA("GuiObject") then
		self.Rate.Visible = self._showRate
		if not self._showRate then
			--[[ THE SLOT CLOSES UP. The cash line is hidden on the car picker, and a hidden label
				still holds its place in a panel laid out in fractions — so the level and its bar
				move up by exactly the height it was drawn at, rather than leaving a hole in the
				middle of the wing. Once, here, because `showRate` never changes for a page. ]]
			local shift = UDim2.fromScale(0, self.Rate.Size.Y.Scale)
			for _, part in { self.Level, self.LevelFill and self.LevelFill.Parent } do
				if part and part:IsA("GuiObject") then
					part.Position -= shift
				end
			end
		end
	end

	--[[ The press. The key is read off `self._car` AT PRESS TIME rather than closed over, for the
		same reason the cards read theirs off the card: the panel is repainted under the pointer
		whenever an attribute lands, and a handler holding the car that was there when it was wired
		would act on a car the player has stopped looking at. ]]
	if self.Action and self.Action:IsA("GuiButton") then
		self.Action.Activated:Connect(function(input: InputObject?)
			local car = self._car
			if car and car.key and self._onPress then
				self._onPress(car.key, input)
			end
		end)
	end

	--[[ A level is per BODY and it moves while this is open — banking a car is what raises it — so
		the panel watches the attribute rather than waiting to be told. It is the one number here
		that is not a fact about the car key. ]]
	self.Player:GetAttributeChangedSignal(GarageConfig.LevelsAttribute):Connect(function()
		if self._car then
			self:_paint()
		end
	end)
	--- ...and so do a car's condition and its fitted parts, which price the value line (2026-09-28).
	for _, attribute in { GarageConfig.ConditionAttribute, CustomizeConfig.PartsAttribute } do
		self.Player:GetAttributeChangedSignal(attribute):Connect(function()
			if self._car then
				self:_paint()
			end
		end)
	end

	--[[ THE PAGE'S OWN `Visible` IS THE BACKSTOP. `UIController` flips it at the END of the close
		tween, and plenty of things close a page without going through the page: a race starting, a
		rail button opening something else, `CloseAllPages`. Header note 3. ]]
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			--- The other half of `show`'s "nothing is built for a shut page": an open is where the
			--- car remembered at boot, or through a close, is actually made.
			if self._car then
				self:show(self._car)
			end
		else
			self:clear()
		end
	end)

	--- The shot is fitted to the box, so a window resize is a refit. Cheap, because it only runs
	--- when the shape has actually moved (`ASPECT_TOLERANCE`).
	if self.Portrait and self.Portrait:IsA("GuiObject") then
		self.Portrait:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:_refit()
		end)
	end

	return self
end

-- === What it says ===========================================================

--[[ Describe this car. `car` is `{ key, body, paint, mutation }` — the page's own card record, which
	already carries all four — or nothing, which puts the wings away.

	Called on selection AND on every repaint: header note 1 is why that is cheap. ]]
function CarDetailV2:show(car: any)
	if not (car and car.key and car.body) then
		self:clear()
		return
	end

	self._car = car
	self:_paint()

	--[[ NOTHING IS BUILT FOR A SHUT PAGE. A page fills itself at boot, before it has ever been
		opened — `KitPage`'s list arithmetic works on hidden frames on purpose — and the car screens
		pick a default car as part of that. Building the model there would put a twenty-five mesh car
		in memory for a panel nobody has opened, on two screens, and would take the HUD's rail away
		at boot. The words are painted (they cost nothing), the car is remembered, and the page's own
		`Visible` brings both back the moment it is actually opened. ]]
	if not self.Page.Visible then
		return
	end

	self:_setCar()

	--- The pop and the rail on every show rather than only on the way in: a page can be reopened
	--- before its own close has finished, and a panel that only asked once would come back up over a
	--- rail it had already given away. Both answer twice with nothing, so a repaint costs neither.
	self:_pop(true)
	self:_holdRail(true)
end

--[[ Is there a car on the panel? What a page asks before deciding whether its selection still needs
	acting on: a page can hold a perfectly valid selection while the wings are empty, because closing
	the page drops the car and reopening it has to put one back. ]]
function CarDetailV2:isShowing(): boolean
	return self._car ~= nil
end

--- Everything the panel says in words and bars. No model work: see `_setCar`.
function CarDetailV2:_paint()
	local car = self._car
	if not car then
		return
	end

	local body = car.body
	local tier = GarageConfig.TierOfBody[body]
	local level = RewardConfig.decodeLevels(self.Player:GetAttribute(GarageConfig.LevelsAttribute))[body] or 1

	if self.Name and self.Name:IsA("TextLabel") then
		self.Name.Text = fill(GarageConfig.carName(body, car.paint))
	end

	if self.Rarity and self.Rarity:IsA("TextLabel") then
		--[[ `CarRarity` rather than a word off the roster: the same word off the same ladder as the
			card under the pointer, and that module is the only thing in the game that also has the
			COLOUR. One lookup keeps the two from ever disagreeing. ]]
		local word, colour = CarRarity.labelOf(body)
		self.Rarity.Text = fill(string.upper(word))
		if self.Tint and self.Tint:IsA("UIGradient") then
			self.Tint.Color = rarityRamp(colour)
		end
	end

	if self.Rate and self.Rate:IsA("TextLabel") and self._showRate then
		--[[ THE MUTATED RATE. `rateOf` multiplies by the weather (`WeatherConfig`), and a panel
			quoting the plain rate would tell the player a Charged Camaro earns what an ordinary one
			does, while the dealership pays out the other number. ]]
		if GarageConfig.Income.Passive then
			self.Rate.Text = fill(TEXT.Rate, { rate = GarageConfig.formatRate(GarageConfig.rateOf(tier, car.mutation)) })
		else
			--[[ THE CAR'S OWN VALUE, NOT THE MODEL'S. `car.key` is a car ID, and its condition comes
				off the broadcast the server keeps for exactly this (`GarageConfig.ConditionAttribute`),
				so a battered Camaro reads the lower number the sell lot will actually pay. Its fitted
				parts come off the partner broadcast through the same helper (2026-09-28). ]]
			local value = MarketValueConfig.valueOfId(car.key, MarketValueConfig.broadcastRecord(self.Player, car.key))
			self.Rate.Text = fill(TEXT.Value, { value = GarageConfig.formatCash(value) })
		end
	end

	local ceiling = RewardConfig.Xp.MaxLevel
	if self.Level and self.Level:IsA("TextLabel") then
		self.Level.Text = fill(TEXT.Level, { level = level, max = ceiling })
	end
	setBar(self.LevelFill, if ceiling > 0 then level / ceiling else 0)

	--[[ The four bars, straight out of `InventoryConfig`: the same view of `CarConfig` the shipping
		tooltip drew, levelled where a level moves the number and not where it does not (that file's
		header notes 1 to 4). Three of the four are flat across the whole roster today and that is a
		`CarConfig` problem rather than one this panel can fix by drawing something else. ]]
	local stats = InventoryConfig.statsFor(body, level, MarketValueConfig.broadcastRecord(self.Player, car.key).Parts)
	for _, row in self._rows do
		local _, fraction = InventoryConfig.readStat(row.stat, stats)
		setBar(row.fill, fraction)
		if row.rating and row.rating:IsA("TextLabel") then
			row.rating.Text = InventoryConfig.formatRating(fraction)
		end
	end
end

--- What the wing's button says and which of its two faces is showing. The page's words; see the
--- header. `state` is what the grey face says when the green one is not pressable.
function CarDetailV2:setAction(action: string, pressable: boolean, state: string?)
	local button = self.Action
	if button and button:IsA("GuiObject") then
		button.Visible = pressable
		local label = button:FindFirstChild("Title")
		if label and label:IsA("TextLabel") then
			label.Text = action
		end
	end

	local grey = self.State
	if grey and grey:IsA("GuiObject") then
		grey.Visible = not pressable
		local label = grey:FindFirstChild("Title")
		if label and label:IsA("TextLabel") then
			label.Text = state or ""
		end
	end
end

--[[ Show a second verb beside the first, or put it away (`action = nil`).

	THE BAND IS SPLIT, NOT GROWN. The right wing is laid out in fractions down to the button band
	(`BuildCarDetailV2`'s `STATS_Y`..`BTN_Y`), and the four stat rows fill everything above it, so a
	second row would have to take height from the stats or hang off the panel. Two halves of the band
	the builder already sized keep every other number in that file true. `SPLIT_SHARE` of the width
	each, the first on the left.

	The arithmetic is done on the band's LEFT EDGE rather than its position, so it is right whatever
	anchor the builder gave it: left = position - anchor * width, and each half is re-anchored from
	there. Scale and offset are both carried, so a band authored in either survives. ]]
function CarDetailV2:setSecondary(action: string?)
	local band, second = self._band, self._second
	if not (band and second) then
		return
	end
	local frame = band.frame :: GuiObject

	if not action then
		frame.Position = band.position
		frame.Size = band.size
		second.Visible = false
		return
	end

	local anchor = frame.AnchorPoint.X
	local width = band.size.X
	local half = UDim.new(width.Scale * SPLIT_SHARE, width.Offset * SPLIT_SHARE)
	local left = UDim.new(band.position.X.Scale - anchor * width.Scale, band.position.X.Offset - anchor * width.Offset)
	local halfSize = UDim2.new(half, band.size.Y)

	frame.Size = halfSize
	frame.Position = UDim2.new(
		UDim.new(left.Scale + anchor * half.Scale, left.Offset + anchor * half.Offset),
		band.position.Y
	)

	second.Size = halfSize
	second.Position = UDim2.new(
		UDim.new(
			left.Scale + width.Scale - half.Scale + anchor * half.Scale,
			left.Offset + width.Offset - half.Offset + anchor * half.Offset
		),
		band.position.Y
	)
	second.Visible = true

	local label = self.SecondAction and self.SecondAction:FindFirstChild("Title")
	if label and label:IsA("TextLabel") then
		label.Text = action
	end
end

-- === The car in the box =====================================================

--- Build the car, or leave the one that is already there. Header note 1.
function CarDetailV2:_setCar()
	local car = self._car
	local portrait = self.Portrait
	if not (car and portrait and portrait:IsA("GuiObject")) then
		return
	end

	if not self._viewport then
		--- `Backdrop` is the colour the car's edges blend into, stamped on the box by the builder
		--- off the art it is drawn in. See `BuildCarDetailV2.Panel`.
		local backdrop = portrait:GetAttribute("Backdrop")
		local view = CarViewport.new(portrait, CAR_VIEW, if typeof(backdrop) == "Color3" then backdrop else nil)
		view.AnchorPoint = Vector2.new(0.5, 0.5)
		view.Position = UDim2.fromScale(0.5, 0.5)
		view.Size = UDim2.fromScale(1, 1)
		--- Over the sunray the face draws behind it, and under nothing: the box holds one thing.
		view.ZIndex = portrait.ZIndex + 1
		self._viewport = view
	end

	--- The mutation too (2026-10-14): two copies of one car in one colour can differ only by it.
	if car.body ~= self._shownBody or car.paint ~= self._shownPaint or car.mutation ~= self._shownMutation then
		self:_stopSpin()
		self._shownBody = car.body
		self._shownPaint = car.paint
		self._shownMutation = car.mutation
		self._aspect = aspectOf(portrait)
		if not CarViewport.set(self._viewport, car.body, { paint = car.paint, mutation = car.mutation, aspect = self._aspect }) then
			--- No published shell for that body: an empty frame, which is what `set` leaves, and
			--- nothing to turn. The words beside it are still true, and a later show retries,
			--- because the shell folder only ever fills up.
			self._shownBody = nil
			return
		end
	end

	--- Unconditional, and `_startSpin` is what makes that cheap: a repaint of the car already
	--- showing lands here, and so does a reopen whose `suspend` stopped the turn.
	self:_startSpin()
end

function CarDetailV2:_startSpin()
	if self._spin or not self._viewport then
		return
	end
	self._spin = CarViewport.spin(self._viewport, {
		aspect = self._aspect,
		degreesPerSecond = CarDetailConfig.SpinDegreesPerSecond,
	})
end

function CarDetailV2:_stopSpin()
	if self._spin then
		self._spin.stop()
		self._spin = nil
	end
end

--- The box changed shape: refit the shot. The model is untouched — only the camera knows the frame.
function CarDetailV2:_refit()
	if not (self._viewport and self._spin and self.Portrait) then
		return
	end
	local aspect = aspectOf(self.Portrait)
	if math.abs(aspect - self._aspect) <= ASPECT_TOLERANCE * math.max(self._aspect, 1) then
		return
	end
	self._aspect = aspect
	self:_stopSpin()
	self:_startSpin()
end

-- === Putting it away ========================================================

--[[ A close has begun: stop turning and give the rail back, but leave the wings drawn. They are
	children of the page, so they go out on the page's own tween; hiding them here would take them
	off a beat before the panel they belong to. Header note 3. ]]
function CarDetailV2:suspend()
	self:_stopSpin()
	self:_holdRail(false)
end

--[[ The page is actually shut, or there is nothing left to describe: wings away, car dropped.

	IT PULLS THEM BACK IN WHEN THERE IS SOMEONE TO SEE IT — the car being described was sold, or a
	search has just hidden it — and takes them off the frame when there is not. A page that has
	closed is already gone by the time this runs, and a retract played inside it would be a sixth of
	a second of work behind a frame nobody is looking at. ]]
function CarDetailV2:clear()
	self:suspend()
	self._car = nil
	if self._open and self.Page.Visible then
		self:_pop(false)
	else
		self:_shut()
	end
end

--[[ Put the wings out, or pull them back in. See the header note on the pop for why a `UIScale` and
	an anchor are the whole of it.

	TWEENED FROM WHEREVER THEY ARE, except from a standing start: a wing that is not drawn is tucked
	first, so the first open of a page (the builder leaves them at rest, hidden) is a pop rather than
	a panel that fades in already in place. One that is half way back in, because a press landed
	during a retract, comes out again from there. ]]
function CarDetailV2:_pop(open: boolean)
	if self._open == open then
		return
	end
	self._open = open
	self._popToken += 1
	local token = self._popToken

	for index, wing in self._wings do
		for _, tween in wing.tweens do
			tween:Cancel()
		end
		table.clear(wing.tweens)

		if open and not wing.frame.Visible then
			wing.scale.Scale = POP_FROM
			wing.frame.Position = wing.tucked
			wing.frame.Visible = true
		end

		--- The stagger is the tween's own delay rather than a `task.delay`: a cancel then takes the
		--- wing that has not started moving with it, which a deferred thread would not.
		local info = if open
			then TweenInfo.new(
				POP_TWEEN.Time,
				POP_TWEEN.EasingStyle,
				POP_TWEEN.EasingDirection,
				0,
				false,
				(index - 1) * POP_STAGGER
			)
			else SHUT_TWEEN
		local grow = TweenService:Create(wing.scale, info, { Scale = if open then 1 else POP_FROM })
		local slide = TweenService:Create(wing.frame, info, { Position = if open then wing.rest else wing.tucked })
		table.insert(wing.tweens, grow)
		table.insert(wing.tweens, slide)

		if not open then
			--[[ Whichever wing lands first takes the pair off the frame, and `_shut` bumps the token
				on its way through, so the other one's turn finds it stale and does nothing. The
				state is checked because a CANCEL raises `Completed` as well, and a press arriving
				half way through a retract cancels exactly this. ]]
			slide.Completed:Once(function(state: Enum.PlaybackState)
				if state == Enum.PlaybackState.Completed and token == self._popToken then
					self:_shut()
				end
			end)
		end

		grow:Play()
		slide:Play()
	end
end

--- Wings off the frame this instant, and the car in the box let go of. The end of a retract, and
--- what a page that has already closed gets instead of one.
function CarDetailV2:_shut()
	self._open = false
	self._popToken += 1
	for _, wing in self._wings do
		for _, tween in wing.tweens do
			tween:Cancel()
		end
		table.clear(wing.tweens)
		wing.frame.Visible = false
	end

	self._shownBody = nil
	self._shownPaint = nil
	if self._viewport then
		CarViewport.clear(self._viewport)
	end
end

-- === The cards in the grid ==================================================

--[[ WHAT A CARD DOES WHILE THE POINTER IS ON IT: its rim lights up and it swells a little. Wire it
	once per card, from the page's own `_wireCard`, beside the press it is advertising.

	IT IS PART OF THE WINGS AND IT LIVES HERE FOR THAT REASON. The picture only became pressable when
	the wings landed, and until 2026-09-17 they opened on their own — so a player never learned that a
	card could be pressed at all. This is the card saying so. Two pages draw these cards and one copy
	of the reaction keeps them from drifting apart.

	NOTHING HAPPENS WITH THE FEATURE OFF, for the same reason the halo does not light up: a card that
	reacts to a pointer and then does nothing when it is pressed is worse than one that sits still.

	`pick` IS WHAT IS WATCHED AND `card` IS WHAT MOVES. The press covers the card's face, so it is the
	one thing that can see the pointer arrive over any part of the picture; the swell goes on the
	whole card so its button comes along rather than being left behind by its own art.

	IT IS THE HOVER ON BOTH DEVICES. A pointer entering and a highlight landing are the same news, and
	they are the same news here for a sharper reason than usual: on a pad the highlight is the ONLY
	thing that happens before the press, so a card that did not react would leave a console player
	with no idea which card A is about to answer for.

	THE SWELL RIDES A `UIScale`, for `Components/Button`'s reason: a `UIGridLayout` owns the card's
	`Size` and would take a tween of it straight back off again. ]]
function CarDetailV2.hoverCard(card: GuiObject?, pick: GuiObject?, ring: UIStroke?)
	if not (CarDetailConfig.Enabled and card and pick and pick:IsA("GuiButton")) then
		return
	end

	local found = card:FindFirstChild(HOVER_SCALE_NAME)
	local scale: UIScale
	if found and found:IsA("UIScale") then
		scale = found
	else
		scale = Instance.new("UIScale")
		scale.Name = HOVER_SCALE_NAME
		scale.Parent = card
	end

	local swell: Tween? = nil
	local glow: Tween? = nil
	local function react(on: boolean)
		if swell then
			swell:Cancel()
		end
		local grow = TweenService:Create(
			scale,
			if on then HOVER_TWEEN else HOVER_OUT_TWEEN,
			{ Scale = if on then HOVER_SCALE else 1 }
		)
		swell = grow
		grow:Play()

		if ring then
			if glow then
				glow:Cancel()
			end
			local fade = TweenService:Create(ring, RING_TWEEN, { Transparency = if on then 0 else 1 })
			glow = fade
			fade:Play()
		end
	end

	pick.MouseEnter:Connect(function()
		react(true)
	end)
	pick.MouseLeave:Connect(function()
		react(false)
	end)

	--[[ AND THE HIGHLIGHT IS THE POINTER ON A PAD. `Components/Button` makes exactly this pair of
		connections for exactly this reason: a gamepad fires no mouse events at all, so a console
		player crossing the grid would otherwise watch nothing happen — and since 2026-09-17 the
		highlight is all a pad gets until it presses A, because the press is what opens the wings. ]]
	pick.SelectionGained:Connect(function()
		react(true)
	end)
	pick.SelectionLost:Connect(function()
		react(false)
	end)

	--[[ A CARD THAT IS HIDDEN UNDER THE POINTER NEVER GETS ITS `MouseLeave`. The cars inventory hides
		cards rather than destroying them as a search is typed, so without this a card filtered out
		while hovered would come back swollen and lit, looking picked before it had been touched. ]]
	card:GetPropertyChangedSignal("Visible"):Connect(function()
		if card.Visible then
			return
		end
		if swell then
			swell:Cancel()
		end
		if glow then
			glow:Cancel()
		end
		scale.Scale = 1
		if ring then
			ring.Transparency = 1
		end
	end)
end

--[[ Ask for the room the rail is standing in, or give it back. Header note 5: this asks and
	`RaceEntryController` writes.

	Latched, because `Publish` runs its listeners inline and a page that repaints ten times while it
	is open would otherwise send ten identical requests through the whole chain. ]]
function CarDetailV2:_holdRail(hold: boolean)
	if not CarDetailConfig.HideRail or hold == self._railHeld then
		return
	end
	self._railHeld = hold
	Dispatcher:Publish("SuppressRail", hold, self.Source)
end

return CarDetailV2
