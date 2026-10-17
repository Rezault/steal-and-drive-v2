--[[
	Shop page  (client)
	-------------------
	The Robux shop: three category tabs on the imported shop art. BUNDLES is a list of wide rows,
	CURRENCY is the cash mosaic, GAMEPASSES is a grid of passes. `Configs/ShopConfig` says what is
	in each, and `BuildShopPage` (Command Runner) prepared the frame this binds to.

	SIX THINGS TO KNOW.

	1. THIS PAGE SELLS NOTHING BY ITSELF. Every purchase is `MarketplaceService:PromptPurchase` or
	   `PromptGamePassPurchase`, which is Roblox's modal and Roblox's money. There is no remote here
	   and there must not be one: the server learns about a sale from a RECEIPT
	   (`DevProductsHandler`) or from `UserOwnsGamePassAsync`, never from a client saying it bought
	   something. That is the whole reason this page can be written without a `ShopService`.

	   THE GIFT BUTTON IS THE ONE EXCEPTION, AND IT STILL SELLS NOTHING. A receipt cannot carry a
	   recipient, so somebody has to write down who a gift is for before Roblox's window opens,
	   and that somebody has to be the server. `GiftController` asks for the window and
	   `GiftService` decides; the money still only ever moves on a receipt. See `_wireGift`.

	2. NOTHING UNWIRED IS DRAWN. `ShopConfig.isSellable` is the gate and it fails two ways: an id of
	   0 was never synced, and `Wired = false` means the pass exists on Roblox but nothing reads its
	   ownership yet. Today that means the Gamepasses tab holds Radio alone and the Bundles tab is
	   empty. That is correct and not a bug to route around: a card that takes Robux for nothing is
	   the worst thing this page could ship. `ShopConfig.ShowUnwired` fills it out for a look.

	   AN EMPTY TAB SAYS SO rather than showing a blank shelf, because an empty shelf reads as a
	   page that failed to load. See `_paintEmpty`.

	3. THE ARTIST'S CARDS ARE A PATTERN, NOT A CAPACITY, and reading that pattern back off the
	   Explorer is most of this file. `BuildShopPage` left each section holding its drawn cards as
	   hidden `Slot1..SlotN`; `_readPattern` groups them into ROWS by where they sit, and `_fill`
	   walks those rows over and over until every entry has somewhere to go. So five drawn currency
	   tiles hold six cash rungs, four drawn gamepass slots hold five passes, and the artist's
	   mosaic — three small tiles, then two wide ones — survives all of it. Move a card in the
	   Explorer and the pattern moves with it. Nothing here has a rect written down.

	4. THE SECTION IS SIZED IN OFFSET AND ITS CARDS IN SCALE, and that split is deliberate.

	   A scale-sized child of a ScrollingFrame measures against the CANVAS, and the canvas is
	   computed from the children, so the two chase each other and a shelf whose window is 300px
	   lays its rows out on a 900px pitch. The Market page's header explains the failure at length.
	   So the SECTION — the only direct child of the shelf — is offset, sized from the shelf's real
	   window and the `BlockAspect` the build script saved off the artist's aspect constraint.

	   Its CARDS stay in scale, because they measure against the section, and a section is an
	   ordinary Frame. Which means a resize touches exactly one property on one instance and every
	   card follows: `_layout` does not walk the cards at all.

	5. THE LAST ROW OF THE CURRENCY MOSAIC STRETCHES. Five tiles, six rungs, so the pattern always
	   leaves one over, and a lone small tile holding the BIGGEST pack reads backwards. With the
	   section's `StretchLastRow` attribute set, a part-filled row shares its width out among the
	   tiles actually in it and the card art is re-picked by width, so the sixth rung lands as one
	   full-width tile under the two wide ones. See `_fill`.

	6. OWNERSHIP IS ASKED ONCE PER OPEN, NOT PER FRAME. `UserOwnsGamePassAsync` is a web call, so it
	   is made for the visible passes when the page opens and cached for as long as it is up. A
	   player who buys a pass while the page is open is handled by `PromptGamePassPurchaseFinished`,
	   which is the one event that can move a card without asking Roblox again.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local GiftConfig = require(ReplicatedStorage.shared.Configs.GiftConfig)
local PassConfig = require(ReplicatedStorage.shared.Configs.PassConfig)
local ShopConfig = require(ReplicatedStorage.shared.Configs.ShopConfig)
local CashConfig = require(ReplicatedStorage.shared.Configs.CashConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local GiftPicker = require(script.Parent.Parent.Components.GiftPicker)
local UIControllerTypes = require(script.Parent.Parent.UIControllerTypes)

local PAGE_NAME = "Shop"

--- Two slots count as the same ROW when their tops are within this, in section scale. Generous
--- because the import's rows are hand-placed and its two bundle rows differ in the fourth decimal.
local ROW_EPSILON = 0.01

--[[ The gift button's gap from the price pill it stands beside, as a fraction of its own width.
	Deliberately small: the two are one control group, and a gap wide enough to read as a margin
	would make the gift button look like it belonged to the card's rim instead. ]]
local GIFT_GAP = 0.2

--[[ How close to a card's own right edge the pill-and-button pair may finish, in card scale.
	A BACKSTOP AND NOT A LAYOUT NUMBER: it is only consulted for a card whose price pill was drawn
	well inside its rim, and on every such card the pair is comfortably inside it anyway. Where
	the pill was drawn hard against the rim, the pill's own edge is the limit instead — see
	`_wireGift`, which takes whichever of the two is further out. ]]
local CARD_RIM = 0.03

--- How far the gift button swells on hover (`Components/Button` defaults to 1.05). A shade past
--- the 1.06 the page's own Close wears, because this is the smallest control on the page and the
--- same proportional nudge on it is otherwise a pixel and a half.
local GIFT_HOVER = 1.08

--[[ ONE COLOUR PER TAB, AND ALL THREE ARE ALWAYS ON. Until 2026-09-04 the strip was one ORANGE
	pill and two SILVER ones dimmed to 0.62, which landed the unselected pair in the panel's own navy
	and read as two dead chips beside a live one. That is a clear answer to "which tab am I on" and a
	poor answer to "what else is in this shop", and the owner called it: a tab you have not opened is
	not a tab that is switched off.

	So each tab keeps its own hue whatever is selected, and the three were picked to spread round the
	wheel rather than to mean anything — except CURRENCY, which is green because it sells cash and
	that is the one tab where a colour can carry the word. Nothing here is BLUE: the panel's title bar
	is `#0066FF` and a blue chip under a blue cap disappears into it. Nothing here is ORANGE either,
	because that is now the buy pill (see `BUY`), and a tab the colour of the button that takes money
	is a tab people press expecting to be charged. ]]
local TAB = {
	Bundles = "Purple",
	Currency = "Green",
	Gamepasses = "Sky",
}

--[[ What a price pill is painted in, and it is GOLD because gold is what this kit already uses for
	"this is the thing to press" — the HUD's PLAY button is the same face.

	IT IS ALSO WHAT PUT THE CHECKER BACK. The artist's import drew its own flat green button
	(`118470325949237`) with no hover and no pressed state, so a price pill was the one control on
	this page that neither wove nor reacted; every other button in the kit carries the checkerboard
	overlay and a three-face ladder. Swapping in the kit's own pill art buys all of that at once and
	costs one property write per card. See `_wirePill`. ]]
local BUY = "Orange"

--[[ THE SELECTED TAB IS LIT AND A LITTLE BIGGER; THE OTHER TWO ARE ONLY A LITTLE BACK.

	Two signals, and the colour itself is not one of them any more, so both have to work whichever
	tab is on. Checked in a playtest against all three: the strip was captured with each of them
	selected in turn, which is the only way to catch the case a single screenshot hides.

	  • THE LIT FACE. A selected pill wears its own HOVER art rather than its idle art. The kit's
	    hover is `HSV(h, s * 0.88, v * 1.25)`, so this is the same colour lifted and never a
	    different one.
	  • THE SIZE. `TAB_LIFT` is written to `Size`, not to a `UIScale`, because `Components/Button`
	    owns the tab's scale channel for its hover nudge and only ONE `UIScale` on an instance takes
	    effect. The two stack cleanly: the tag multiplies whatever `Size` says when the cursor lands.
	    It fits — a tab is 0.198 of the page wide with a 0.022 gap beside it, so 8% puts 0.008 a side
	    into 0.011.

	A THIRD SIGNAL WAS BUILT AND TAKEN BACK OUT on the owner's call: a light rim behind the selected
	pill, made from a slightly larger SILVER pill because a `UIStroke` on an `ImageButton` traces the
	element's RECTANGLE rather than the image's alpha and put the tab inside a square box. The lit
	face reads well enough on its own and the rim was one outline too many. The `UIStroke` finding is
	the part worth keeping: it is true of every pill in this kit, not just these three.

	THE DIM IS THE KNOB THAT CAN UNDO BOTH OF THEM, so it is deliberately shallow. `ImageColor3`
	multiplies, and far enough back a purple tab is just a dark chip again — which is the look this
	pass exists to remove. 0.70 keeps the hue unmistakable and still reads as standing behind.

	GREEN IS DIMMED LESS THAN THE OTHER TWO because it starts darkest: `#2FA40F` is the one face in
	the palette whose idle is already below the navy panel in luminance, and at 0.70 it went muddy
	rather than quiet. This is a per-face floor and not a per-tab preference — an eighth palette
	colour darker than Green would want an entry here too. ]]
local TAB_DIM = { Green = 0.8 }
local TAB_DIM_DEFAULT = 0.7
local TAB_LIFT = 1.08
local TAB_LABEL_ON = Color3.new(1, 1, 1)
--- Barely off-white. The old `(198, 205, 224)` was half of the greyed-out look and read as muddy
--- over a saturated face; the pill says which tab is live, the label only has to not shout.
local TAB_LABEL_OFF = Color3.fromRGB(236, 241, 255)

local TEXT_MUTED = Color3.fromRGB(123, 133, 169)

local function url(id: number): string
	return "rbxassetid://" .. tostring(id)
end

--- Multiply a size on both channels, offset included. `Components/Button.grow`, repeated here for
--- the one thing it does not do: that one rides a `UIScale` and this writes `Size`. See `TAB_LIFT`.
local function grow(size: UDim2, factor: number): UDim2
	return UDim2.new(
		size.X.Scale * factor,
		size.X.Offset * factor,
		size.Y.Scale * factor,
		size.Y.Offset * factor
	)
end

--[[ What a cash pack says it grants. `GarageConfig.formatCash` with a hollow decimal taken off.

	THE DECIMAL IS RIGHT EVERYWHERE ELSE AND WRONG HERE. `formatCash` always prints one, because
	everywhere else it is used the number is arbitrary and moving: a $2.2M car beside a $2.0M one
	are two prices that have to line up, and a balance ticking over wants the digit. A cash pack is
	neither. Every rung is a round 15, 150 or 1500 times a power of ten by construction, so the
	decimal is always a zero, and six tiles reading "$150.0K" next to "$1.5M" spend a character
	each on saying nothing.

	ONLY A ZERO IS REMOVED, so a rung retuned to something that is not round keeps its digit rather
	than being silently rounded on the tile that is selling it. ]]
local function packAmount(cash: number): string
	return (string.gsub(GarageConfig.formatCash(cash), "%.0(%a)$", "%1"))
end

--- Left edge / top edge in the parent's scale. The kit anchors cards top-left and labels centred,
--- so neither `Position` alone is an edge.
local function left(gui: GuiObject): number
	return gui.Position.X.Scale - gui.AnchorPoint.X * gui.Size.X.Scale
end
local function top(gui: GuiObject): number
	return gui.Position.Y.Scale - gui.AnchorPoint.Y * gui.Size.Y.Scale
end

-- === Page ===================================================================

local Page = {}
Page.__index = Page

--[[ Read one section's drawn cards back as a layout pattern.

	Everything below is in BLOCK UNITS: the section as the artist drew it is 1.0 tall, whatever it
	turns out to be in pixels, and a section holding more rows than were drawn is simply taller than
	1. Positions come out of the Explorer, so this is the only place the artist's geometry is read
	and the only thing that has to change when they move a card. ]]
local function readPattern(section: Frame)
	local slots = {}
	for _, child in section:GetChildren() do
		if child:IsA("GuiObject") and string.match(child.Name, "^Slot%d+$") then
			table.insert(slots, child)
		end
	end
	table.sort(slots, function(a, b)
		local ay, by = top(a), top(b)
		if math.abs(ay - by) > ROW_EPSILON then
			return ay < by
		end
		return left(a) < left(b)
	end)

	local rows = {}
	for _, slot in slots do
		local row = rows[#rows]
		if not row or math.abs(row.Y - top(slot)) > ROW_EPSILON then
			row = { Y = top(slot), H = slot.Size.Y.Scale, Slots = {} }
			table.insert(rows, row)
		end
		table.insert(row.Slots, { X = left(slot), W = slot.Size.X.Scale, Template = slot })
	end

	--[[ The gap between rows, taken from the first pair and then used for every pair. The artist
		drew two rows, so there IS no measured gap for the third; one uniform gap is both the only
		answer available and the one that makes a repeated pattern look repeated. ]]
	local gap = if #rows > 1 then rows[2].Y - (rows[1].Y + rows[1].H) else 0

	--[[ The margin above the first row and below the last, taken from the artist's LEFT margin
		rather than from where they put the first card.

		The drawn top margin is not a margin — it is the room the section HEADING was drawn in, and
		`BuildShopPage` hides that heading because the tab above now says the same word. Reusing it
		as whitespace would leave a visible hole at the top of every tab. The left margin is a real
		margin, and converting it to a y-fraction (an x-scale times the aspect is the same number of
		pixels) makes the gutter the same width all the way round. ]]
	local inset = if rows[1] and rows[1].Slots[1] then rows[1].Slots[1].X else 0

	return rows, gap, inset
end

function Page.new(UIController: UIControllerTypes.UIController)
	local self = setmetatable({}, Page)
	self.UIController = UIController

	local mainUI = UIController.PlayerGui:WaitForChild("MainUI")
	self.PageUI = mainUI:WaitForChild("Pages"):WaitForChild(PAGE_NAME)

	self.Tabs = self.PageUI:WaitForChild("Tabs")
	self.Shelf = self.PageUI:WaitForChild("Shelf")

	self.Sections = {}
	for _, name in ShopConfig.Tabs do
		local section = self.Shelf:WaitForChild(name)
		local rows, gap, inset = readPattern(section)
		local aspect = section:GetAttribute("BlockAspect") or 2

		self.Sections[name] = {
			Section = section,
			--- Width/height of the section as drawn. The section's height in pixels is its width
			--- divided by this, times however many block units it has grown to.
			Aspect = aspect,
			--- The section's own width as a fraction of the shelf window, kept so the artist's side
			--- gutter survives.
			WidthScale = section.Size.X.Scale,
			Rows = rows,
			Gap = gap,
			-- The left margin as a y-fraction. See `readPattern`.
			Inset = inset * aspect,
			Stretch = section:GetAttribute("StretchLastRow") == true,
			ArtFeatured = section:GetAttribute("ArtFeatured"),
			ArtPlain = section:GetAttribute("ArtPlain"),
			--- Height in block units, written by `_fill` and read by `_layout`.
			Units = 1,
			Cards = {},
		}
	end

	self.Active = ShopConfig.DefaultTab
	self.Owned = {} :: { [string]: boolean }
	--- Each tab's authored rect, so the selected one's `TAB_LIFT` is applied to the drawing rather
	--- than to whatever the last selection left behind.
	self.TabSize = {} :: { [string]: UDim2 }

	--[[ THE ONLY THING GIFTING REMEMBERS, and it lives for exactly one round trip: the gift whose
		button was pressed, held so that a REFUSAL can put the picker back up over the right card.
		There is no "currently gifting to" and there is no mode — `ShopConfig.Gift` has the
		argument for why that state went away. ]]
	self.PendingGift = nil :: GiftConfig.Gift?
	self.Picker = GiftPicker.new(self.PageUI)

	local close = self.PageUI:WaitForChild("Close")
	close.MouseButton1Click:Connect(function()
		self.UIController:closePage(PAGE_NAME)
	end)

	return self
end

function Page.initialize(self)
	--[[ One signal, on the shelf, and it re-sizes whichever section is showing. The old page
		watched three ScrollingFrames; there is one here, and the sections inside it are ordinary
		Frames whose children are in scale, so a resize is one property write. ]]
	self.Shelf:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_layout()
	end)

	for _, name in ShopConfig.Tabs do
		local tab = self.Tabs:FindFirstChild(name)
		if tab then
			tab.MouseButton1Click:Connect(function()
				self:_selectTab(name)
			end)
		end
	end

	--[[ The one event that can move a card without asking Roblox again (header note 6). It fires on
		this client for this client, so a `true` is a purchase that actually completed. ]]
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if player ~= Players.LocalPlayer or not purchased then
			return
		end
		for _, pass in ShopConfig.Passes do
			if pass.PassId == passId then
				self.Owned[pass.Key] = true
				self:_buildGamepasses()
				self:_layout()
				break
			end
		end
	end)

	--[[ The server's status line, and a toast when somebody gives this player something. Both come
		through `Dispatcher` rather than off a remote held here — see `GiftController`, which has no
		screen and cannot know whether this page is built yet. ]]
	Dispatcher:Subscribe(GiftConfig.ReplyName, function(ok: boolean, message: string)
		local gift = self.PendingGift
		self.PendingGift = nil

		--[[ REFUSALS GO TO THE PICKER'S OWN TITLE BAR, which is where the player last looked. There
			is no status strip on the shop art and adding one would mean moving the artist's rows;
			the picker is code-built, is already the thing that asked the question, and reopening it
			with the reason written across it is both the answer and the retry.

			IT REOPENS ON THE SAME GIFT, which is what makes it a retry rather than a dead end: the
			commonest refusal by far is a recipient who left the server between the pick and the
			request, and the answer to that is the same list with somebody else on it. ]]
		if not ok and gift then
			self:_pickFor(gift, string.upper(message))
		end
	end)

	Dispatcher:Subscribe(GiftConfig.ReceivedName, function(_fromName: string, _title: string)
		--[[ A gift landing on THIS player while they are looking at the shop. The card that was
			showing a price for a pass they have just been given has to stop doing that, and the
			cheapest correct way is to forget what we knew and ask again. ]]
		self.Owned = {}
		self:_refreshOwnership()
	end)

	-- Built at start rather than on first open, so the art is in the tree in time for the
	-- controller's preload pass and the first open is not a page assembling itself.
	self:_buildAll()
	self:_selectTab(self.Active)

	return self
end

function Page:StartOpenThread()
	self:_refreshOwnership()
	self:_layout()
end

function Page:StartCloseThread() end

-- === Tabs ===================================================================

function Page:_selectTab(name: string)
	self.Active = name

	for _, tabName in ShopConfig.Tabs do
		local on = tabName == name

		local tab = self.Tabs:FindFirstChild(tabName)
		if tab then
			local colour = TAB[tabName] or "Silver"
			local set = UIAssets.Pill[colour]
			--[[ The selected tab shows the HOVER face as its resting one — the same colour lifted, not
				a different colour — so the strip reads as one chip standing forward. Its `HoverImage` is
				the same face, which means pointing at the tab you are already on does nothing but the
				scale nudge, and pointing at either of the others brightens it towards this. ]]
			tab.Image = url(if on then set.Hover else set.Idle)
			tab.HoverImage = url(set.Hover)
			tab.PressedImage = url(set.Pressed)

			local dim = TAB_DIM[colour] or TAB_DIM_DEFAULT
			tab.ImageColor3 = if on then Color3.new(1, 1, 1) else Color3.new(dim, dim, dim)

			--[[ The authored rect, read once and kept, because the lift is written to `Size` and a
				second call would otherwise compound it. `BuildShopPage` is the only other writer and it
				only ever runs in the Explorer. ]]
			local base = self.TabSize[tabName]
			if not base then
				base = tab.Size
				self.TabSize[tabName] = base
			end
			tab.Size = if on then grow(base, TAB_LIFT) else base

			local label = tab:FindFirstChild("Label")
			if label then
				label.TextColor3 = if on then TAB_LABEL_ON else TAB_LABEL_OFF
			end
		end

		local entry = self.Sections[tabName]
		if entry then
			-- The shelf's UIListLayout skips invisible children, so hiding the other two is the
			-- whole of "switch tab": the visible one lands at the top of the canvas by itself.
			entry.Section.Visible = on
		end
	end

	self.Shelf.CanvasPosition = Vector2.zero
	self:_layout()
end

-- === Building ===============================================================

function Page:_buildAll()
	self:_buildBundles()
	self:_buildCurrency()
	self:_buildGamepasses()
end

--[[ Place `count` cards over the section's row pattern and hand each one back to `paint`.

	The pattern repeats: rows are walked in order and then from the top again, so a section holds as
	many entries as it is given rather than as many as were drawn (header note 3). Everything is in
	block units until the very end, where a card's rect is divided by the section's total height to
	become the scale the card actually carries. ]]
function Page:_fill(name: string, count: number, paint: (GuiObject, number) -> ())
	local entry = self.Sections[name]
	if not entry or #entry.Rows == 0 then
		return
	end

	for _, card in entry.Cards do
		card:Destroy()
	end
	table.clear(entry.Cards)

	-- Lay the rects out first, because a card's y-scale needs the section's FINAL height and that
	-- is only known once the last row has been placed.
	local placed = {}
	local cursor = entry.Inset
	local index, rowIndex = 1, 1

	while index <= count do
		local row = entry.Rows[(rowIndex - 1) % #entry.Rows + 1]
		local take = math.min(#row.Slots, count - index + 1)

		--[[ A part-filled last row, shared out. `span` is the row's full drawn width — its first
			card's left edge to its last card's right edge — and the used cards are scaled by
			whatever factor makes them plus the drawn gaps fill it. One card in a three-card row
			therefore goes full width, which is the case this exists for (header note 5). ]]
		local scale = 1
		local interGap = 0
		if #row.Slots > 1 then
			interGap = row.Slots[2].X - (row.Slots[1].X + row.Slots[1].W)
		end
		if entry.Stretch and take < #row.Slots then
			local span = (row.Slots[#row.Slots].X + row.Slots[#row.Slots].W) - row.Slots[1].X
			local used = 0
			for slot = 1, take do
				used += row.Slots[slot].W
			end
			scale = (span - (take - 1) * interGap) / used
		end

		local x = row.Slots[1].X
		for slot = 1, take do
			local width = row.Slots[slot].W * scale
			local template = if scale == 1 then row.Slots[slot].Template else self:_nearestTemplate(entry, width)
			table.insert(placed, {
				Template = template,
				X = x,
				W = width,
				Y = cursor,
				H = row.H,
				--[[ How much wider the card came out than THE ART IT IS CLONED FROM, which is not
					the slot it is standing in: a stretched card swaps to the nearest-width template
					and that template is already most of the way to the final width. Measuring
					against the slot instead shrinks the contents by the whole stretch a second
					time, and the widest tile in the shop ends up with the smallest price pill on
					it. See `_stretchChildren`. ]]
				Widened = width / template.Size.X.Scale,
			})
			x += width + interGap
			index += 1
		end

		cursor += row.H + entry.Gap
		rowIndex += 1
	end

	--[[ The section's height. The trailing gap comes back off, because a gap is between rows and
		the bottom margin is the inset. An EMPTY section still gets one row's worth of height, so
		`_paintEmpty` has a box to write in rather than a zero-tall strip. ]]
	local units = if #placed > 0
		then cursor - entry.Gap + entry.Inset
		else entry.Inset * 2 + entry.Rows[1].H
	entry.Units = units

	for order, rect in placed do
		local card = rect.Template:Clone()
		card.Name = name .. "_" .. order
		card.LayoutOrder = order
		card.Visible = true
		card.Position = UDim2.fromScale(rect.X, rect.Y / units)
		card.Size = UDim2.fromScale(rect.W, rect.H / units)
		card.AnchorPoint = Vector2.zero

		--[[ The card's rendered width over its rendered height, which `_wireGift` needs because a
			square drawn in a card's own scale is not square. The section renders at
			`width / Aspect * units` tall and the card takes `rect.H / units` of that, so `units`
			cancels out and this stays exact for a STRETCHED card as well as a drawn one. ]]
		card:SetAttribute("CardAspect", rect.W / rect.H * entry.Aspect)

		if rect.Widened ~= 1 then
			self:_stretchChildren(card, rect.Widened)
		end

		card.Parent = entry.Section
		table.insert(entry.Cards, card)
		paint(card, order)
	end
end

--[[ The drawn card whose width is closest to `width`.

	A stretched tile has to change its ART as well as its rect, because the artist drew TWO card
	textures rather than one — a narrow one and a wide one — precisely so that a wide tile is not a
	narrow tile with its checker smeared sideways. Picking by nearest drawn width means the full
	width sixth cash rung takes the wide art without anything having to say so. ]]
function Page:_nearestTemplate(entry, width: number)
	local best, bestGap = nil, math.huge
	for _, row in entry.Rows do
		for _, slot in row.Slots do
			local gap = math.abs(slot.W - width)
			if gap < bestGap then
				best, bestGap = slot.Template, gap
			end
		end
	end
	return best
end

--[[ Put a widened card's contents back to the size they were drawn at, centred.

	A card's children are in scale, so a tile stretched to three times its drawn width gets a price
	pill three times as long, which is the one thing about the stretch that looks wrong rather than
	generous. Shrinking their x-scale by the same factor the card grew by restores the drawn PIXEL
	width, and re-mapping x about the card's centre keeps the composition together. Everything on a
	currency tile is centred, which is why this is safe on the one section that stretches. ]]
function Page:_stretchChildren(card: GuiObject, widened: number)
	local factor = 1 / widened
	for _, child in card:GetChildren() do
		if child:IsA("GuiObject") then
			local size, position = child.Size, child.Position
			child.Size = UDim2.new(size.X.Scale * factor, size.X.Offset, size.Y.Scale, size.Y.Offset)
			child.Position = UDim2.new(
				0.5 + (position.X.Scale - 0.5) * factor,
				position.X.Offset,
				position.Y.Scale,
				position.Y.Offset
			)
		end
	end
end

--[[ A shelf with nothing in it says why. An empty section is indistinguishable from a page that
	failed to load, and today two of the three tabs are legitimately empty (header note 2). ]]
function Page:_paintEmpty(name: string, message: string)
	local entry = self.Sections[name]
	if not entry then
		return
	end

	local note = entry.Section:FindFirstChild("EmptyNote")
	if #entry.Cards > 0 then
		if note then
			note.Visible = false
		end
		return
	end

	if not note then
		note = Instance.new("TextLabel")
		note.Name = "EmptyNote"
		note.AnchorPoint = Vector2.new(0.5, 0.5)
		note.BackgroundTransparency = 1
		note.Position = UDim2.fromScale(0.5, 0.5)
		-- Sized against ONE row, which is all an empty section is tall. The 0.8 x 0.2 the old page
		-- used was measured against a full-height shelf and came out as a headline here.
		note.Size = UDim2.fromScale(0.6, 0.11)
		note.FontFace = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)
		note.TextScaled = true
		note.TextColor3 = TEXT_MUTED
		note.ZIndex = 3
		note.Parent = entry.Section
	end
	note.Text = message
	note.Visible = true
end

function Page:_buildGamepasses()
	local passes = ShopConfig.visiblePasses()

	self:_fill("Gamepasses", #passes, function(card, order)
		local pass = passes[order]

		card.PassName.Text = pass.Title
		card.Blurb.Text = pass.Blurb
		card.Icon.Image = url(pass.IconId or 0)

		self:_wirePill(card, pass.Key, pass.Price, self.Owned[pass.Key] == true, function()
			self:_promptPass(pass)
		end)
	end)

	self:_paintEmpty("Gamepasses", "Nothing here yet. Check back soon.")
end

function Page:_buildCurrency()
	--[[ Only the rungs Roblox will actually take money for. `CashConfig.Packs` is the ladder and a
		rung with no product id was never synced, so it is filtered BEFORE the count reaches `_fill`
		— a hole in the middle of the mosaic would otherwise be laid out as a card and drawn blank. ]]
	--[[ THE RUNG IS CARRIED, NOT THE POSITION IN THIS LIST. A rung that was filtered out leaves a
		hole in the ladder, and the rungs after it must keep their own glyphs rather than sliding
		down into them: rung 5's silver case belongs to $150M whether or not $15M is on sale. ]]
	local packs = {}
	for rung, pack in ShopConfig.cashPacks() do
		if pack.ProductId ~= 0 then
			table.insert(packs, { Pack = pack, Rung = rung })
		end
	end

	local tiers = UIAssets.CashTiers

	self:_fill("Currency", #packs, function(card, order)
		local pack = packs[order].Pack

		--[[ The glyph is the only part of a currency tile that says WHICH pack it is at a glance.
			See `UIAssets.CashTiers`: one drawing per rung, escalating note to throne, because all
			six of these products wear the same icon on Roblox and the product art can therefore
			say nothing at all. Clamped rather than left blank past the end of the list, so a
			seventh rung wears the throne instead of an empty square. ]]
		local tier = tiers[math.min(packs[order].Rung, #tiers)]
		if tier then
			card.Icon.Image = url(tier)
		end

		-- `formatCash` is the garage's own formatter, so a price on this tile and a price on a car
		-- read the same way. `packAmount` only takes off the trailing zero it leaves behind.
		card.Amount.Text = packAmount(CashConfig.cashFor(pack, Players.LocalPlayer))

		--- A cash pack is never "owned", so the third argument is always false here.
		self:_wirePill(card, pack.Key, pack.Price, false, function()
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, pack.ProductId)
		end)
	end)

	self:_paintEmpty("Currency", "Cash packs are not available right now.")
end

function Page:_buildBundles()
	local bundles = ShopConfig.visibleBundles()
	local entry = self.Sections.Bundles

	self:_fill("Bundles", #bundles, function(card, order)
		local bundle = bundles[order]

		card.BundleName.Text = bundle.Title
		card.Subtitle.Text = bundle.Subtitle
		card.Blurb.Text = bundle.Blurb
		card.Icon.Image = url(bundle.IconId or 0)

		local saving = ShopConfig.savingLabel(bundle)
		card.Saving.Text = saving
		card.Saving.Visible = saving ~= ""

		-- The featured skin is a swap between two painted rows, not a gradient laid over one. See
		-- `BuildShopPage`, which recorded both ids off the artist's own two rows.
		local art = if bundle.Featured then entry.ArtFeatured else entry.ArtPlain
		if art then
			card.Image = art
		end

		--[[ There is no `GiftStarterBundle` product, so `giftFor` answers nil and this row keeps its
			ordinary pill even in gift mode. Deliberate rather than missed: the bundle is a NEW
			ACCOUNT's pack — cash, a first car and an offline boost — and the player most likely to
			be gifted one is the player least likely to be standing in the server to be picked. ]]
		self:_wirePill(card, bundle.Key, bundle.Price, false, function()
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, bundle.ProductId)
		end)
	end)

	self:_paintEmpty("Bundles", "No bundles on offer right now.")
end

-- === Gifting ================================================================

--[[ THE GIFT BUTTON, one per giftable card, hard against the right edge of that card's price pill.

	IT REPLACED A GIFT TOGGLE IN THE TAB ROW on 2026-09-04 at the owner's ask, and `ShopConfig.Gift`
	carries the argument: a gift is a fact about one purchase, not a state the whole page is in.

	IT IS THE HUD RAIL'S OWN SQUARE BUTTON, NOT A PILL, and `UIAssets.GiftButton` has that argument
	in full. The short version is that a pill is only ever drawn at the art's own 3.89:1, so at the
	price pill's height a pill-shaped neighbour would be most of the width of the card.

	THE PAIR KEEPS THE PILL'S CENTRE UNLESS THAT WOULD PUSH IT OFF THE CARD, and that is the only
	reason this moves the artist's pill at all. The button goes against the pill's right edge and
	the two then slide left by half of what the pair grew by, which is what keeps a CENTRED pill
	centred — every cash tile.

	THE CLAMP IS FOR THE OTHER KIND OF CARD, and the pass cards are it: their pill was drawn from
	x 0.599 to 0.977, hard against the rim, so there is nothing to grow into on that side and
	centring the pair hung a third of the gift button off the card. So the pair's right edge is
	held at whichever is further out, the rim line or THE PILL'S OWN RIGHT EDGE — the second
	because the artist put the pill there, which proves that x is inside the art. A clamped pair
	grows leftward instead, into the empty run under the card's text column.

	THE OWNED BADGE SLIDES WITH THE PILL, because `BuildShopPage` draws it on the pill's exact
	rect. A badge left where the pill used to be would end up half underneath the gift button.

	NOTHING IS DRAWN FOR A CARD THAT CANNOT BE GIFTED. `ShopConfig.giftFor` answers nil for an
	unwired pass, for a rung that never synced, and for the bundles (there is no
	`GiftStarterBundle`) — which is the same call header note 2 makes about the cards themselves:
	draw nothing rather than draw a control that leads somewhere empty. ]]
function Page:_wireGift(card: GuiObject, key: string)
	local gift = ShopConfig.giftFor(key)
	if not gift then
		return
	end

	local buy = card:FindFirstChild("BuyButton") :: ImageButton?
	--- What `_fill` measured for this card. Without it there is no way to draw a square in scale.
	local aspect = card:GetAttribute("CardAspect")
	if not (buy and type(aspect) == "number" and aspect > 0) then
		return
	end

	local art = UIAssets.Size.GiftButton
	--- The pill's own height, so the two share a top edge and a bottom edge and read as one control.
	local height = buy.Size.Y.Scale
	local width = height * (art.X / art.Y) / aspect
	local gap = width * GIFT_GAP

	local pillWidth = buy.Size.X.Scale
	local pillRight = buy.Position.X.Scale + pillWidth / 2
	--- Centred on the pill, then pulled back inside the card. See the block above for both halves.
	local pairRight = math.min(pillRight + (width + gap) / 2, math.max(pillRight, 1 - CARD_RIM))
	local pillX = pairRight - (width + gap) - pillWidth / 2

	buy.Position = UDim2.fromScale(pillX, buy.Position.Y.Scale)
	local owned = card:FindFirstChild("Owned")
	if owned then
		owned.Position = UDim2.fromScale(pillX, owned.Position.Y.Scale)
	end

	local button = Instance.new("ImageButton")
	button.Name = "GiftButton"
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(pairRight - width / 2, buy.Position.Y.Scale)
	button.Size = UDim2.fromScale(width, height)
	button.BackgroundTransparency = 1
	--- The art carries its own three faces; Roblox's press tint fights them. Every pill does this.
	button.AutoButtonColor = false
	button.Image = UIAssets.url(UIAssets.GiftButton.Idle)
	button.HoverImage = UIAssets.url(UIAssets.GiftButton.Hover)
	button.PressedImage = UIAssets.url(UIAssets.GiftButton.Pressed)
	--- Square art at a square size, so Stretch is a uniform scale and reproduces the drawing
	--- exactly. The block under `UIAssets.Slice` says why nothing in this kit is ever 9-sliced.
	button.ScaleType = Enum.ScaleType.Stretch
	--- Over the OWNED badge's 3, because on a pass this player already owns the two are neighbours.
	button.ZIndex = 4
	button.Parent = card

	--[[ TAGGED AFTER PARENTING, and the tag is what makes this a button of this kit rather than a
		clickable picture: `Components/Button` gives it the hover swell, the click sound and
		`Selectable` for a controller. No `Page` or `Action` attribute, deliberately — those say what
		a press MEANS, and what this press means is a question, which is asked below. ]]
	button:SetAttribute("Scale", GIFT_HOVER)
	button:AddTag("UIButton")

	button.MouseButton1Click:Connect(function()
		self:_pickFor(gift)
	end)
end

--[[ Ask who one gift is for, and then ask the server to open Roblox's window for it.

	`title` is passed only on the retry after a refusal, where the reason takes the title bar's
	place. An ordinary open names the thing being given, which is the whole of the picker's job.

	A CANCEL COSTS NOTHING AND LEAVES NOTHING BEHIND. `GiftPicker` calls back exactly once — with a
	player, or with nil for its close button — and nothing has been recorded by then, so there is no
	mode to get out of and no card to put back. ]]
function Page:_pickFor(gift: GiftConfig.Gift, title: string?)
	--- A cash rung is named the way its own tile names it. See `packAmount`.
	local name = gift.Title
	--- Upper, because every title bar in this kit is. The refusal path arrives already upper.
	local heading = title or string.upper(string.format(ShopConfig.Gift.PickerFormat, name))

	self.Picker:open(heading, ShopConfig.Gift.PickerEmpty, function(player: Player?)
		if not player then
			return
		end
		local controller = Shard.get("GiftController")
		if not controller then
			return
		end
		--[[ Recorded for the REPLY, which is the only thing left that can need to know which card
			this came from. `GiftController` re-checks the recipient and `GiftService` decides; this
			is a note to ourselves, not a claim. ]]
		self.PendingGift = gift
		controller:request(gift.Key, player)
	end)
end

--[[ Repaint the artist's price button as the kit's own GOLD pill, in place.

	THE RECT IS NOT TOUCHED, only the four properties that say what is drawn in it. Everything else on
	this page is measured off that rect — the OWNED badge is built on it, and `_wireGift` slides the
	pair from it — so moving it would be three changes rather than one. The cost is that the art is
	stretched to whatever the artist drew rather than to the pill's own 3.89:1; measured off a capture
	it lands at 4.07, a 4.6% horizontal stretch, which on a 22px corner radius is one pixel. That is
	well inside what `UIAssets`' "why no pill is ever 9-sliced" note calls acceptable — it is the
	SLICE that could not survive an aspect change, not the stretch.

	THE THREE FACES ARE THE POINT. The import shipped one image and no reaction; a pill is idle, hover
	and pressed, and `AutoButtonColor` has to go off or Roblox's own grey press tint fights the third
	one. That flag was left true on every one of these cards.

	AND THE LABEL MOVES TO UBUNTU, which is the kit's face and already what the OWNED badge sitting on
	this exact rect is set in. The import's Arial was the artist's; with the two pills now the same
	shape in the same place, a different typeface on each was the one thing left telling them apart
	for the wrong reason. ]]
function Page:_paintBuy(pill: ImageButton)
	local set = UIAssets.Pill[BUY]
	pill.Image = url(set.Idle)
	pill.HoverImage = url(set.Hover)
	pill.PressedImage = url(set.Pressed)
	pill.AutoButtonColor = false
	pill.ScaleType = Enum.ScaleType.Stretch

	pill.Label.FontFace = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)
end

--[[ Wire one card's price pill, and hand it a gift button if what is on it can be given away.

	ONE FUNCTION FOR ALL THREE SHELVES, because "what does the price say, what does pressing it do,
	and is this one already owned" is the same three lines on a cash tile, a pass card and a bundle
	row.

	AN OWNED PASS STILL GETS A GIFT BUTTON, which is the one rule here that is not obvious. Owning a
	pass says nothing about whether the person you are buying it for owns it, so the OWNED badge
	takes the price's place and the gift button stays beside it. The server does not check the
	recipient's ownership either, and `PassService.grant`'s header says why: the gifter cannot see
	what the recipient owns and should not be able to. ]]
function Page:_wirePill(card: GuiObject, key: string, price: number, owned: boolean, buy: () -> ())
	local pill = card.BuyButton
	pill.Visible = not owned
	if card:FindFirstChild("Owned") then
		card.Owned.Visible = owned
	end
	self:_paintBuy(pill)
	pill.Label.Text = ShopConfig.priceLabel(price)
	pill.MouseButton1Click:Connect(buy)

	self:_wireGift(card, key)
end

-- === Buying =================================================================

function Page:_promptPass(pass)
	if pass.PassId == 0 then
		return -- never synced; `isSellable` should already have kept this card off the shelf
	end
	MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, pass.PassId)
end

--[[ Which of the visible passes does this player own? Asked once per open (header note 6).

	THE SERVER'S ATTRIBUTE IS ASKED FIRST, AND THAT IS NOT AN OPTIMISATION. Since gifting landed,
	ownership is the UNION of two sources — bought on Roblox, or given by another player — and
	`UserOwnsGamePassAsync` only knows about the first. A page that asked Roblox alone would show a
	BUY pill for a pass somebody had been given, and take their Robux for it. `PassService` computes
	the union server-side and mirrors it onto the Player under `PassConfig.ownedAttribute`, so that
	attribute is the answer and the web call below is only the fallback for a client whose join has
	not published yet.

	THE ATTRIBUTE IS A BROADCAST AND DECIDES NOTHING, which is why reading it here is safe: this is
	a screen deciding what to draw, and every actual ruling is made on the server against
	`PassService`. A client that lied to itself about this would see a card it could not buy from.

	THE FALLBACK IS WRAPPED PER CALL: one failure costs one card its OWNED badge rather than taking
	the page down. A pass whose answer never arrives stays un-owned, which shows a BUY pill to
	somebody who already bought it — the safe way round, because Roblox's own prompt then tells them
	they own it and takes no money. ]]
function Page:_refreshOwnership()
	local player = Players.LocalPlayer
	task.spawn(function()
		local changed = false
		for _, pass in ShopConfig.visiblePasses() do
			if self.Owned[pass.Key] == nil then
				local published = player:GetAttribute(PassConfig.ownedAttribute(pass.Key))
				if type(published) == "boolean" then
					self.Owned[pass.Key] = published
					changed = true
				else
					local ok, owns = pcall(function()
						return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.PassId)
					end)
					if ok then
						self.Owned[pass.Key] = owns
						changed = true
					end
				end
			end
		end
		if changed then
			self:_buildGamepasses()
			self:_layout()
		end
	end)
end

-- === Layout =================================================================

--[[ Size the visible section against the shelf's real window. That is the whole of layout, for the
	reason header note 4 gives: the cards are in scale against this frame, so they follow it.

	Only the ACTIVE section is measured. A hidden one has an AbsoluteSize too, but it is not in the
	list layout and nobody is looking at it. `_selectTab` calls this after switching, so a section
	is always sized before it is shown. ]]
function Page:_layout()
	local entry = self.Sections[self.Active]
	if not entry then
		return
	end

	local window = self.Shelf.AbsoluteWindowSize.X
	if window <= 0 then
		-- Laid out before the page has a size. The AbsoluteSize signal brings us back.
		return
	end

	local width = math.floor(window * entry.WidthScale)
	entry.Section.Size = UDim2.fromOffset(width, math.round(width / entry.Aspect * entry.Units))
end

return Page
