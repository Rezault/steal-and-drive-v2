--[[
	Index page, V2 - THE CAR COLLECTION  (client)
	---------------------------------------------
	"Every car there is to steal, and which ones I have." The Cartoony Kit's index: a five-column grid
	of cards, one per car in the game, each coloured by its rarity band. A car you have stolen is
	drawn as itself with what it pays; a car you have not is a black cut-out called `???`. The rail
	beside the panel narrows the grid to one band.

	It is the HUD's `Index` cell (`BuildHudV2`).

	`BuildIndexV2` (Command Runner) cloned the kit's `IndexUI` into `MainUIV2.Pages.Index`, turned the
	kit's five rarity buttons into our five bands and added the count and the rate chip. Its header
	carries every decision about the SHAPE of this screen; this file is the behaviour.

	=== WHAT CARRIED OVER FROM THE SHIPPING PAGE, UNCHANGED ===================================

	1. THE ROSTER IS THE WHOLE GAME, NOT THE PLAYER'S LOT, and `Modules/CarCatalogue` is where it
	   comes from. Both index pages read the same list in the same order and count "stolen" off the
	   same attribute, which is the one that never shrinks; that module's note 2 is the trap it exists
	   to keep a second screen out of.

	2. A CAR YOU HAVE NOT STOLEN IS A CUT-OUT, `???`, AND KEEPS ITS RARITY. The name would leak the
	   car and the picture would give it away, but "there is a SUPERCAR you have not found" is the
	   thing that makes an empty card worth filling, so the band stays: on this art that is the
	   card's whole colour. THE CUT-OUT IS NOT FADED and everything else on a locked card is, because
	   a faded silhouette on a faded card is a smudge.

	3. ONE CARD IS ONE BODY, in its artist's livery. A Camaro in four colours is one card ticked, so
	   there is no single paint to draw it in. The Cars page is the one that lists every copy.

	4. A STOLEN CARD SAYS WHAT THE CAR PAYS, and only a stolen one: a price on a `???` is a fact about
	   a car the player cannot look at. The base rate, `CarCatalogue.rateText`, which is the Cars
	   page's number to the character.

	5. THE CARS ARE A VIRTUALISED LIST and `Modules/CarViewportGrid` is the whole of it. Forty-odd
	   real models behind a panel showing a dozen is the cost that module exists to avoid. This page
	   hands it the geometry `KitPage` works out and the cards that are showing, in grid order.

	=== WHAT THE KIT CHANGED ==================================================================

	  • THE RAIL IS THE FILTER. The shipping page lists one WORLD at a time behind a pager and has a
	    search box; the kit draws neither and draws a column of rarity buttons instead, so the grid
	    is every world in world order and a press narrows it to one band. Pressing the lit band again
	    puts everything back. The kit drew five buttons and no "all", so "all" is the state with none
	    of them chosen: every button lit. Choosing one dims the other four, which is opacity as the
	    kit's own state language, the same way the Cars page dims a car parked elsewhere.

	    A BAND IS A SHORTER LADDER TO FINISH, which is what the shipping page's per-world count was
	    for. The count in the header follows the filter: "12/43 STOLEN" for the whole game, "3/9" for
	    the sedans.

	  • THE MAPS TAB IS GONE. The kit's index is a car collection with no tabs, and how far down each
	    road you have driven is the Teleport screen's subject. `docs/NewUI-Migration-Notes.md` has it
	    as a known gap.

	  • THE GRID NEEDS NO LAYOUT CODE. `KitPage` reads the kit's `UIGridLayout`, counts the columns
	    and owns the canvas, so the shipping page's `_measure`, `_applyLayout`, `GRID_COLUMNS` and the
	    driven scrollbar all go.

	=== ON A GAMEPAD ==========================================================================

	THE CARDS ARE SELECTABLE AND PRESS NOTHING. The kit's card is a Frame with no button on it, and a
	grid with nothing selectable in it is a grid a controller can never scroll. So every card takes
	the highlight: a DPad walks the grid and the list scrolls to follow it. `Components/GamepadNav`
	seeds a page on its topmost button, which here is the first band, so a page opens with the filter
	under the thumb and the grid one press to the left.

	THE ENGINE WILL NOT STEP INTO A SCROLLING GRID FROM OUTSIDE IT, measured, so the three doors are
	wired by hand. Inside the grid its own neighbour search is fine (down from a card lands on the card
	below and scrolls to it), but left from a band button skipped every card and landed on the X, and
	down from the X skipped the card directly under it and landed back on the rail. Making the list
	selectable only moved the problem: the highlight parked on the list itself and stayed there. So a
	band button's LEFT, the X's DOWN and a row-end card's RIGHT are worked out at the moment each gains
	the highlight, against where things are on screen right then. See `_wireGamepad`.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
local CarCatalogue = require(ReplicatedStorage.shared.Modules.CarCatalogue)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)
local CarViewportGrid = require(ReplicatedStorage.shared.Modules.CarViewportGrid)
local KitPage = require(script.Parent.Parent.KitPage)

local PAGE_NAME = "Index"

local Page = KitPage.extend(PAGE_NAME)

--- What `BuildIndexV2` left, by name.
local CARD_NAME = "CarCard"
local TINT_NAME = "Tint"
local RAIL_NAME = "SideBtns"
local BAND_ATTRIBUTE = "Band"

--- The portrait the viewport grid fills, laid over the kit's `Icon` box.
local CAR_VIEW = "Car"

--[[ The words. Upper case like every other word on the Cars page, and `{found}` before `{total}`
	because it is a count of what you did, not a result count: "STOLEN" is the verb that fills a
	card, which is the one thing the caption should teach. ]]
local TEXT = {
	Count = "{found}/{total} STOLEN",
}

--[[ How far a locked card is faded: the face and its sunray, and both lines of type. The rim is not
	faded, so a locked card is still a card-shaped slot rather than a hole, and the cut-out is not
	faded at all (header note 2). The shipping page's two numbers, for the same two jobs. ]]
local LOCKED_FACE_FADE = 0.6
local LOCKED_TEXT_FADE = 0.45

--- How far the bands you did NOT choose are dimmed while a filter is on.
local RAIL_DIM = 0.55

--- How much white goes into the top of a band's ramp. `BuildIndexV2` and `PagesV2/Dealership` use
--- the same number, so a band is the same two colours wherever it is drawn.
local RAMP_LIFT = 0.35

local NBSP = "\u{00A0}"

--- Upper case with every space unbreakable: TextScaled would rather wrap than shrink.
local function caption(text: string): string
	return (string.gsub(string.upper(text), " ", NBSP))
end

local function fill(template: string, fields: { [string]: string | number }): string
	return caption((string.gsub(template, "{(%w+)}", function(name)
		local value = fields[name]
		return if value ~= nil then tostring(value) else "{" .. name .. "}"
	end)))
end

local function ramp(colour: Color3): ColorSequence
	return ColorSequence.new(colour:Lerp(Color3.new(1, 1, 1), RAMP_LIFT), colour)
end

--- A label and the stroke that outlines its type, faded together. A text stroke keeps its own
--- transparency, so fading the text alone leaves a ring of outline round nothing.
local function fadeText(label: Instance?, alpha: number)
	if not (label and label:IsA("TextLabel")) then
		return
	end
	label.TextTransparency = alpha
	for _, stroke in label:GetChildren() do
		if stroke:IsA("UIStroke") then
			stroke.Transparency = alpha
		end
	end
end

-- === Building ===============================================================

function Page.initialize(self)
	--- The kit's text caps are pixels for a 1080-tall screen; this keeps them in proportion above it.
	KitPage.scaleTextCaps(self.PageUI)

	self.Player = (self.UIController and self.UIController.Player) or Players.LocalPlayer

	--[[ One record per car, in roster order, which is also grid order. NOT `self._rows`, which is
		`KitPage`'s own list of the cells it has stamped.

		AN ENTRY IS ALSO A `CarViewportGrid.Cell`: `viewport`, `body`, `silhouette` and `fade` are
		the whole of what that module reads, so the list handed to `setCells` is this list. ]]
	self._entries = {} :: { any }
	--- The band the grid is narrowed to, or nil for every band. Header, "The rail is the filter".
	self._band = nil :: number?
	self._found = {} :: { [string]: boolean }
	--- How many cards the filter is showing; `_setBand` owns it.
	self._shown = 0

	self.Count = self.Header and self.Header:FindFirstChild("Count")
	self._views = CarViewportGrid.new(self.List :: ScrollingFrame, self.PageUI)

	--[[ A ScrollingFrame is selectable by default, and here it is the biggest target on the page: a
		DPad leaving the rail would land on the well rather than on the card beside it, and A on the
		well does nothing. The cards are the targets (header, "On a gamepad"). ]]
	if self.List then
		self.List.Selectable = false
	end

	--[[ THE CELLS IN THE WINDOW'S PIXELS. Left in the artist's scale, a card's height resolves against
		the canvas, and this is the first grid tall enough to show it: 43 cards drew 287px tall in a
		290px window. `KitPage.pinGridToWindow`'s note has the measurement. ]]
	self:pinGridToWindow()

	self:_buildRail()
	self:_buildCards()
	self:_wireGamepad()

	--[[ The geometry the viewport grid tests against moves with the list. Pinned again FIRST, because
		`KitPage` re-pins on this same signal and the engine does not promise which handler runs
		first; pinning twice is two property writes, and a car framed against last frame's cell is a
		car drawn at the wrong size until it scrolls away. ]]
	if self.List then
		self.List:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:pinGridToWindow()
			self:_applyGeometry()
		end)
	end

	self.Player:GetAttributeChangedSignal(CarCatalogue.FoundAttribute):Connect(function()
		self:_refreshFound()
	end)
	self:_refreshFound()
	self:_setBand(nil)
end

--[[ One button per band, as `BuildIndexV2` stamped them. The caption and the colour are written again
	here off the live modules, so a band renamed in `TrafficConfig` or retinted in `CarRarity` reaches
	this rail without a rebuild. ]]
function Page:_buildRail()
	self._buttons = {} :: { { button: GuiButton, band: number } }

	local rail = self.PageUI:FindFirstChild(RAIL_NAME)
	if not rail then
		warn(string.format("[%s] no `%s` rail; the grid cannot be filtered.", PAGE_NAME, RAIL_NAME))
		return
	end

	for _, button in rail:GetChildren() do
		local band = button:GetAttribute(BAND_ATTRIBUTE)
		if not (button:IsA("GuiButton") and type(band) == "number") then
			continue
		end

		local title = button:FindFirstChild("Title")
		local spec = TrafficConfig.Bands[band]
		if title and title:IsA("TextLabel") and spec then
			--- The RARITY word, the one every card prints (`TrafficConfig.RarityWords`, 2026-10-08) — the
			--- band's `Name` is the car-shape word that rule retired, and the rail read BEATER..SUPERCAR.
			title.Text = caption(if TrafficConfig.RarityWords then spec.RarityName or spec.Name else spec.Name)
		end
		local tint = button:FindFirstChild(TINT_NAME)
		if tint and tint:IsA("UIGradient") then
			tint.Color = ramp(CarRarity.colourOf(band))
		end

		--- `Activated` covers a mouse, a touch and a gamepad's A. The kit button is already a
		--- `UIButton`, so the sound and the swell are not this file's.
		button.Activated:Connect(function()
			self:_setBand(if self._band == band then nil else band)
		end)
		table.insert(self._buttons, { button = button, band = band })
	end
end

--[[ Every card, once. The roster is a fact about the config and cannot change during a session, so
	nothing here is rebuilt: stealing a car repaints a card, and filtering hides some. ]]
function Page:_buildCards()
	for index, car in CarCatalogue.Roster do
		local card = self:newRow(CARD_NAME)
		if not card then
			return
		end
		card.Name = car.body
		card.LayoutOrder = index
		--- Header, "On a gamepad". A Frame the highlight can land on, pressing nothing.
		card.Selectable = true

		local word, band = CarRarity.of(car.body)
		local colour = CarRarity.colourOf(band)

		local tint = card:FindFirstChild(TINT_NAME)
		if tint and tint:IsA("UIGradient") then
			tint.Color = ramp(colour)
		end

		local rarity = card:FindFirstChild("Rarity")
		if rarity and rarity:IsA("TextLabel") then
			rarity.Text = caption(word)
			--- A body on no ladder has no word, and a coloured card with an empty line on it reads fine;
			--- a line that says nothing in a box does not.
			rarity.Visible = word ~= ""
		end

		--[[ The car, over the kit's icon box. `backdrop` is the band's colour because that is what
			the viewport's edge pixels are laid on: the default is the Cars page's face, and on a
			purple card it would draw a pale fringe round the car. ]]
		local icon = card:FindFirstChild("Icon")
		local viewport: ViewportFrame? = nil
		if icon and icon:IsA("GuiObject") then
			local view = CarViewport.new(card, CAR_VIEW, colour)
			view.AnchorPoint = icon.AnchorPoint
			view.Position = icon.Position
			view.Size = icon.Size
			--- Over the sunray and the empty icon, under both lines of type.
			view.ZIndex = icon.ZIndex + 1
			viewport = view
		end

		table.insert(self._entries, {
			body = car.body,
			world = car.world,
			band = band,
			card = card,
			rarity = rarity,
			title = card:FindFirstChild("Title"),
			rate = card:FindFirstChild("Rate"),
			sunray = card:FindFirstChild("BG"),
			rateText = CarCatalogue.rateText(car.body),
			--- `CarViewportGrid.Cell`'s fields. `silhouette` is settled by `_refreshFound`, which
			--- runs before the page is ever visible and so before anything is built.
			viewport = viewport,
			silhouette = nil :: boolean?,
			fade = 0,
		})
	end
end

-- === Stolen or not ==========================================================

--[[ Re-read the catalogue and repaint every card. Cheap enough to do wholesale: one loop and a
	handful of property writes per card.

	EVERY CARD, NOT EVERY VISIBLE ONE, so changing the filter is only ever a filter.

	THE ONE EXPENSIVE THING IS DONE ONLY WHEN IT HAS TO BE. A card going from locked to stolen needs a
	different MODEL, not a different colour (a cut-out has been flattened), so the viewport grid is
	told to drop it. Compared against the last state, because this runs on every write of the
	attribute and one steal should rebuild one car. ]]
function Page:_refreshFound()
	local found = CarCatalogue.parseFound(self.Player:GetAttribute(CarCatalogue.FoundAttribute))
	self._found = found

	for _, entry in self._entries do
		local has = found[entry.body] == true
		local locked = not has
		if entry.silhouette ~= locked then
			entry.silhouette = locked
			self._views:invalidate(entry)
		end

		local title = entry.title
		if title and title:IsA("TextLabel") then
			title.Text = if has then GarageConfig.displayName(entry.body) else CarCatalogue.LockedText
		end

		local card = entry.card
		card.BackgroundTransparency = if has then 0 else LOCKED_FACE_FADE
		local sunray = entry.sunray
		if sunray and sunray:IsA("CanvasGroup") then
			sunray.GroupTransparency = if has then 0 else LOCKED_FACE_FADE
		end
		local textFade = if has then 0 else LOCKED_TEXT_FADE
		fadeText(title, textFade)
		fadeText(entry.rarity, textFade)

		local rate = entry.rate
		if rate and rate:IsA("TextLabel") then
			rate.Text = entry.rateText
			rate.Visible = has and entry.rateText ~= ""
		end
	end

	--- The invalidations above dropped models; this puts the replacements in the queue.
	self._views:refresh()
	self:_updateCount()
end

--- The header count, over the cards the filter is showing.
function Page:_updateCount()
	local count = self.Count
	if not (count and count:IsA("TextLabel")) then
		return
	end
	local found, total = 0, 0
	for _, entry in self._entries do
		if self._band == nil or entry.band == self._band then
			total += 1
			if self._found[entry.body] then
				found += 1
			end
		end
	end
	count.Text = fill(TEXT.Count, { found = found, total = total })
end

-- === The filter =============================================================

--[[ Narrow the grid to one band, or nil for all of them. The one write, and the only place a card's
	`Visible` changes.

	IT IS NOT THE SAME LIST AS `_entries` that goes to the viewport grid: a `UIGridLayout` lays out
	VISIBLE children only, so a filter moves every card behind it up into the rows the window is
	over. `_entries` is in layout order, so collecting it in order collects the grid. ]]
function Page:_setBand(band: number?)
	self._band = band

	local cells = {}
	for _, entry in self._entries do
		local shown = band == nil or entry.band == band
		entry.card.Visible = shown
		--- Where the card lands in the grid as it is now laid out, which is what says whether it
		--- ends a row. See `_wireGamepad`.
		entry.slot = nil
		if shown then
			table.insert(cells, entry)
			entry.slot = #cells
		end
	end
	self._shown = #cells

	--- `KitPage` sizes the canvas off the VISIBLE cells, so a filter shortens the list too.
	self:_updateCanvas()
	if self.List then
		self.List.CanvasPosition = Vector2.zero
	end
	--- After the canvas, so the grid tests the new list against the new geometry.
	self:_applyGeometry()
	self._views:setCells(cells)

	self:_paintRail()
	self:_updateCount()
	--- The doors into the grid named cards by position, and the positions just changed.
	self:_refreshDoors()
end

--[[ Every band lit when nothing is chosen, and only the chosen one lit when something is.

	THE WHOLE BUTTON FADES, not just its fill: the gradient face, the caption and its outline, the
	two rim strokes and the sheen. Fading the face alone left a bright white rim round a pale button,
	which reads as a different button rather than the same one stepping back. ]]
function Page:_paintRail()
	for _, item in self._buttons do
		local lit = self._band == nil or self._band == item.band
		local alpha = if lit then 0 else RAIL_DIM
		local button = item.button

		button.BackgroundTransparency = alpha
		fadeText(button:FindFirstChild("Title"), alpha)
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
end

--[[ The cell geometry, from `KitPage`, with the one adjustment this card needs: the car is drawn in
	the `Icon` box rather than the whole cell, so the aspect the camera frames for is that box's. ]]
function Page:_applyGeometry()
	if not self.List then
		return
	end
	local columns, pitch, cellHeight, top, cellAspect = self:cellGeometry()
	local template = self.Templates[CARD_NAME]
	local icon = template and template:FindFirstChild("Icon")
	local aspect = cellAspect
	if icon and icon:IsA("GuiObject") and icon.Size.Y.Scale > 0 then
		aspect = cellAspect * icon.Size.X.Scale / icon.Size.Y.Scale
	end
	self._views:setLayout(columns, pitch, cellHeight, top, aspect)
end

-- === On a gamepad ===========================================================

local function centreY(gui: GuiObject): number
	return gui.AbsolutePosition.Y + gui.AbsoluteSize.Y / 2
end

--[[ The three doors between the grid and the rest of the page. Header, "On a gamepad".

	EACH IS DECIDED WHEN ITS CONTROL GAINS THE HIGHLIGHT, not when the page is built, because the
	answer depends on the scroll position and the filter, and both move. `NextSelection*` is only
	read on the press that follows, so writing it on arrival is in time for a DPad.

	...AND AGAIN WHEN THE FILTER CHANGES, which arrival alone missed: a band is chosen by pressing A
	ON THE RAIL, so the highlight is already on the button whose door the filter just moved. Measured:
	SUPERCAR's left door still named GT, GT had just been hidden, and the next press put the highlight
	on a card nobody could see. `_setBand` calls `_refreshDoors`. ]]
function Page:_wireGamepad()
	for _, item in self._buttons do
		item.button.SelectionGained:Connect(function()
			self:_refreshDoors()
		end)
	end

	local close = self.CloseBtn
	if close then
		close.SelectionGained:Connect(function()
			self:_refreshDoors()
		end)
	end

	for _, entry in self._entries do
		entry.card.SelectionGained:Connect(function()
			entry.card.NextSelectionRight = if self:_endsRow(entry) then self:_railNearest(entry.card) else nil
		end)
	end
end

--- The doors INTO the grid: every band button's left and the X's down. Cheap enough to redo whole.
function Page:_refreshDoors()
	for _, item in self._buttons do
		item.button.NextSelectionLeft = self:_rowEndNearest(item.button)
	end
	if self.CloseBtn then
		self.CloseBtn.NextSelectionDown = self:_rowEndNearest(self.CloseBtn)
	end
end

--- Whether a card is the last one on its row as the grid is laid out now: the right-hand column, or
--- the last card of a short final row.
function Page:_endsRow(entry): boolean
	local slot = entry.slot
	if not slot then
		return false
	end
	return slot % math.max(1, self._columns) == 0 or slot == self._shown
end

--[[ The row-end card level with `from`, preferring one that is inside the list's window so a press
	never jumps the highlight onto a card the player cannot see. Nil when nothing is showing, which
	leaves the engine's own answer in place.

	A CARD'S HEIGHT ON SCREEN IS COMPUTED FROM ITS SLOT, NOT READ. `_setBand` asks this in the same
	frame it hides half the grid, before the layout has moved anything, so `AbsolutePosition` would
	still be describing the last filter. The slot and `cellGeometry` are already the new layout. ]]
function Page:_rowEndNearest(from: GuiObject): GuiObject?
	local list = self.List
	if not list then
		return nil
	end
	local top = list.AbsolutePosition.Y
	local bottom = top + list.AbsoluteSize.Y
	local target = centreY(from)
	local columns, pitch, cellHeight, padTop = self:cellGeometry()
	local originY = top - list.CanvasPosition.Y + padTop

	local best, bestDistance, bestOnScreen = nil, math.huge, false
	for _, entry in self._entries do
		if not self:_endsRow(entry) then
			continue
		end
		local row = math.floor((entry.slot - 1) / math.max(1, columns))
		local y = originY + row * pitch + cellHeight / 2
		local onScreen = y >= top and y <= bottom
		local distance = math.abs(y - target)
		if (onScreen and not bestOnScreen) or (onScreen == bestOnScreen and distance < bestDistance) then
			best, bestDistance, bestOnScreen = entry.card, distance, onScreen
		end
	end
	return best
end

--- The band button level with a card.
function Page:_railNearest(card: GuiObject): GuiObject?
	local target = centreY(card)
	local best, bestDistance = nil, math.huge
	for _, item in self._buttons do
		local distance = math.abs(centreY(item.button) - target)
		if distance < bestDistance then
			best, bestDistance = item.button, distance
		end
	end
	return best
end

-- === Open and close =========================================================

--[[ The filter is reset on every open, which is the shipping page's rule for its search and its
	pager: a narrowed grid you did not choose reads as a broken one. ]]
function Page:StartOpenThread()
	self:_setBand(nil)
end

--- Nothing to stop: the viewport grid watches the page's own `Visible` and empties itself.
function Page:StartCloseThread() end

return Page
