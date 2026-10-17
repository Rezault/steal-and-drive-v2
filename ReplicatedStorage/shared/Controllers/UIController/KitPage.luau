--[[
	KitPage  (client)
	-----------------
	EVERY CARTOONY KIT PAGE IS THE SAME SHAPE, so this knows the shape and the page modules under
	`PagesV2` only have to know their own data. It is `BasicPage`'s opposite number for the new UI:
	`BasicPage` binds a screen that has no behaviour yet, this binds the parts every kit screen has.

		Header{ Title, CloseBtn }
		Main{ ScrollingFrame{ <row templates>, UIListLayout, UIPadding } }
		BG{ CheckersBG }

	A page with nothing of its own is still one line:

		return require(script.Parent.Parent.KitPage).extend("Quest")

	NOT EVERY KIT FRAME OF THIS SHAPE IS A PAGE, so the binding half is separable. `KitPage.bind`
	takes a frame and does everything below to it; `KitPage.new` is that plus the `Pages.<name>`
	lookup and a close that goes through `UIController`. `Components/GiftPickerV2` is the first
	caller of `bind`: an overlay living inside the Shop page, with the kit's own header, close
	button, list and row templates, and none of a page's routing.

	...and one with logic keeps the same contract every page in this project has: `.new(UIController)`,
	`:initialize()` and a `.PageUI`.

		local Page = KitPage.extend("Quest")
		function Page:initialize()
			for _, quest in board do
				local row = self:newRow("QuestTemplate")
				row.Title.Text = quest.name
			end
		end

	=== WHAT IT DOES FOR YOU ==================================================================

	1. BINDS THE PAGE. `Modules/UIRoot` says which ScreenGui is the UI, so a page module never names
	   one. `Pages.<name>` is the frame, exactly as in the old UI.

	2. CLOSES. `Header.CloseBtn` (or anything named like a close button) shuts the page. Bound on
	   `Activated`, which is mouse, touch AND a gamepad's A, where the old UI's `MouseButton1Click`
	   was silent on a controller.

	3. TRAPS THE HIGHLIGHT. The page frame is a `SelectionGroup` with all four edges set to `Stop`,
	   so a DPad cannot walk out through the panel onto the HUD behind it. `Components/GamepadNav`
	   does this too, from the other end; it is idempotent and cheap, and a page that is right on its
	   own cannot be broken by a change to when that watcher runs.

	4. TAKES THE ROW TEMPLATES OUT OF THE LIST. The kit ships each list with sample rows in it. The
	   FIRST child of each distinct name is kept as a template, unparented and held; every other
	   child is destroyed. So `Main.ScrollingFrame` starts empty and `newRow("ToggleTemplate")` is
	   how a row gets made. A page with one kind of row can call `newRow()` with no name at all.

	5. SIZES THE LIST IN PIXELS, WHICH IS THE WHOLE REASON THIS FILE EXISTS.

	=== THE LIST, AND WHY IT IS NOT LEFT AS AUTHORED ==========================================

	The kit lists are `AutomaticCanvasSize = Y` with rows sized in SCALE. Both halves are traps we
	have already paid for once in the old UI, and they are written up in full at the top of
	`Pages/Quest`:

	  • A child's Y SCALE inside a `ScrollingFrame` resolves against the CANVAS, not the window. So
	    scaled rows plus a content-derived canvas feed each other: measured in this project, four
	    167px rows became 10,584px each on a 24,249px canvas within three frames. Nothing errors.
	  • `AutomaticCanvasSize` does break that cycle, and then lands about 7px SHORT of the layout's
	    real content size, so the last row is unreachable at full scroll. It reads as a clipping bug
	    in the art.

	So the authored proportions are read off the template ONCE (its height as a fraction, the
	layout's padding, the `UIPadding`), and from then on every row is sized in OFFSET pixels taken
	from the list's own rendered height, with a canvas computed from the rows. `AutomaticCanvasSize`
	is off, `ScrollBarThickness` is 0 (the kit draws its own bar, and zero also keeps
	`AbsoluteWindowSize` equal to the frame, which the arithmetic assumes), and `_syncMetrics` redoes
	the lot whenever the page is re-laid-out.

	LAYOUT RESOLVES ON HIDDEN FRAMES, so all of this works before the page is ever opened: a page
	that boots invisible can measure and fill its list on the first frame.

	=== A GRID IS THE SAME JOB WITH ONE FEWER TRAP ============================================

	Some kit lists are a `UIGridLayout` of cards rather than a column of rows (the inventory, the
	collection index, the car picker). Those need the canvas computed here just the same, and they
	need ONE number the page cannot work out for itself: how many cards fit across.

	WHAT THEY DO NOT NEED IS THE CONVERSION. A `UIGridLayout`'s `CellSize` in scale resolves against
	the ScrollingFrame's own `AbsoluteSize`, not against its canvas, which is the opposite of what a
	CHILD's `Size` does and is why the runaway above cannot happen here. Measured on the kit's
	inventory: a 0.52 cell in a 266px window on a 533px canvas came out 138px, which is the window's
	number. So the authored cell is left exactly as the artist set it, resolution-independent, and
	this file only counts the rows and sizes the canvas.

	`cellGeometry` hands the numbers on to whoever needs them in pixels. `Modules/CarViewportGrid`
	is the caller that matters: it decides which cards are on screen by arithmetic rather than by
	reading `AbsolutePosition`, so it needs the same geometry the layout is using.

	=== CORRECTION, MEASURED 2026-09-16: ONLY THE WIDTH RESOLVES AGAINST THE WINDOW ============

	The paragraph above is right about X and wrong about Y. The collection index was the first grid
	taller than its window, and its cards came out 287px tall in a 290px window: `AbsoluteCellSize.Y`
	was 0.314 of the 919px CANVAS, and 0.314 of the window would have been 91. The inventory's
	measurement could not tell the two apart, because two rows of cards is a canvas about the height
	of the window. So a grid's cell height has the same trap a row's does; it just does not run away,
	because the canvas here is computed from the window rather than from the cells.

	`pinGridToWindow` below is the fix, added rather than folded into `_syncMetrics` so that no page
	already built on the grid changes under it. A grid page calls it once from `initialize`.

	=== AN AUTHORED LIST KEEPS ITS ROWS (2026-10-15) ===========================================

	`extend(name, { AuthoredList = true })` skips note 4: every child of the list stays where it was
	put and IS a row, in `LayoutOrder`, rather than a sample to stamp from. The Shop is the first
	(the owner's own list, every card a real product). The pixel sizing is unchanged and reads each
	row's height off a `PreviewHeightScale` attribute when it has one, its `Size.Y.Scale` when not,
	because an authored list is laid out in OFFSET so it previews right in the Explorer. A row the
	page builds on top goes in with `adoptRow`. ]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIControllerTypes = require(script.Parent.UIControllerTypes)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)

--- Which template a row was cloned from, written on the clone so `_syncMetrics` can size a mixed
--- list (a settings list is toggles, sliders and button rows, and they need not be the same height).
local TEMPLATE_ATTRIBUTE = "KitTemplate"

--[[ Set by a page on a row it is animating OUT, and cleared by whatever destroys it. While it is
	there, `_syncMetrics` leaves that row's height alone: see the loop that reads it. ]]
local LEAVING_ATTRIBUTE = "Leaving"

--- An authored row's height as a share of the list's, when its own `Size` is in offset. Header.
local PREVIEW_HEIGHT_ATTRIBUTE = "PreviewHeightScale"

--- Names a close button can have, most specific first. `CloseBtn` is the kit's own.
local CLOSE_NAMES = { "CloseBtn", "ExitBtn", "Close", "CloseButton", "Exit", "X" }

export type Options = {
	--- Keep the list's children as the rows instead of taking them as templates. Header.
	AuthoredList: boolean?,
}

local KitPage = {}
KitPage.__index = KitPage

--- Named out loud so a page setting the flag and this file reading it cannot drift apart.
KitPage.LeavingAttribute = LEAVING_ATTRIBUTE

local function findCloseButton(root: Instance): GuiButton?
	for _, name in CLOSE_NAMES do
		local candidate = root:FindFirstChild(name, true)
		if candidate and candidate:IsA("GuiButton") then
			return candidate
		end
	end
	return nil
end

--[[ A page is a room with no doors: navigation inside it stays inside it. The same four properties
	`GamepadNav.trapSelection` sets, for the same reason, and setting them twice costs nothing. ]]
local function trapSelection(frame: GuiObject)
	frame.SelectionGroup = true
	frame.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	frame.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	frame.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	frame.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
end

-- === Building ===============================================================

--[[ Bind one kit frame: its header, its close button, its row templates and its list.

	EVERYTHING BELOW IS TRUE OF ANY FRAME OF THE KIT'S SHAPE, page or not. `KitPage.new` is this plus
	the `Pages.<name>` lookup; see the header for who else calls it. ]]
function KitPage.bind(frame: GuiObject, options: Options?)
	local self = setmetatable({}, KitPage)
	self.PageUI = frame
	--- Only ever used to name this frame in a warning. `new` overwrites it with the page's own name,
	--- which for a page is the same string.
	self.PageName = frame.Name

	trapSelection(frame)

	--[[ A page boots shut whatever the Explorer left it as, so a frame ticked visible while somebody
		was editing it does not open the game on it. `UIController` owns every open from here. ]]
	frame.Visible = false

	self.Header = frame:FindFirstChild("Header")
	self.Title = self.Header and self.Header:FindFirstChild("Title")
	self.Main = frame:FindFirstChild("Main")

	--[[ A LOCAL, never `self.Close`: `UIController` treats a `Close` field on a page as that page's
		own close ROUTINE and calls it, so parking the button there makes closing throw. ]]
	local close = (self.Header and self.Header:FindFirstChild("CloseBtn")) or findCloseButton(frame)
	if close and close:IsA("GuiButton") then
		self.CloseBtn = close
		--[[ `Activated` rather than `MouseButton1Click`: it covers mouse, touch and a gamepad's A.

			Dispatched through `self` at PRESS TIME rather than captured here, so a subclass that
			overrides `onClose` is the thing that runs. `extend`'s metatable is not in place yet when
			this line executes. ]]
		close.Activated:Connect(function()
			self:onClose()
		end)
	end

	--- Per-row state. A list rather than a map because the ORDER is the layout.
	self._rows = {} :: { GuiObject }
	self.Templates = {} :: { [string]: GuiObject }
	self._rowScale = {} :: { [string]: number }
	self._rowWidth = {} :: { [string]: UDim }
	self._firstTemplate = nil :: string?
	self._gapScale = 0
	self._padScale = { top = 0, bottom = 0, left = 0, right = 0 }
	self._rowHeight = {} :: { [string]: number }
	--- Authored lists only: each row's own height fraction, since rows there share names.
	self._rowScaleOf = {} :: { [GuiObject]: number }
	self._gap = 0
	--- Grid lists only; zero on a list of rows. See `_dressList` and `cellGeometry`.
	self._columns = 1
	self._cellWidth = 0
	self._cellHeight = 0
	self._cellGap = 0

	self.List = self.Main and self.Main:FindFirstChildOfClass("ScrollingFrame")
	if self.List then
		if options and options.AuthoredList then
			self:_adoptRows()
		else
			self:_takeTemplates()
		end
		self:_dressList()
		self:_syncMetrics()
		--[[ The page is laid out again on every viewport change, on the open tween's first frame and
			when a phone rotates. Re-deriving the pixels from `AbsoluteSize` is the whole maintenance
			cost of doing this in offsets. ]]
		self.List:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:_syncMetrics()
		end)
	end

	return self
end

--[[ Bind a PAGE: the frame at `Pages.<name>` in whichever ScreenGui is the UI.

	`Modules/UIRoot` says which that is, so a page module never names one. ]]
function KitPage.new(UIController: UIControllerTypes.UIController, pageName: string, options: Options?)
	local screenGui = UIRoot.wait(UIController.PlayerGui)
	local frame = (screenGui :: ScreenGui):WaitForChild("Pages"):WaitForChild(pageName) :: GuiObject

	local self = KitPage.bind(frame, options)
	self.UIController = UIController
	self.PageName = pageName
	return self
end

--[[ What the close button does. A page hands the close to `UIController`, which owns the tween and
	the "only one page at a time" rule; a frame bound with `bind` and nothing else does nothing, and
	is expected to override this. ]]
function KitPage.onClose(self)
	if self.UIController and self.PageName then
		self.UIController:closePage(self.PageName)
	end
end

--[[ Make a page class for `PagesV2/<name>.luau`.

	The returned class inherits every method below, so a page module writes only what is its own.
	Override `initialize` to fill the list: `UIController` calls it once, straight after `new`, and it
	is the first moment the page is bound and its templates are in hand. (The page's `UIScale` is
	attached a line LATER, so `initialize` must not tween or measure through it.) ]]
function KitPage.extend(pageName: string, options: Options?)
	local Page = {}
	Page.__index = Page
	setmetatable(Page, { __index = KitPage })

	function Page.new(UIController: UIControllerTypes.UIController)
		local self = KitPage.new(UIController, pageName, options)
		return setmetatable(self :: any, Page)
	end

	function Page.initialize(_self) end

	return Page
end

-- === The row templates ======================================================

--[[ Lift the sample rows out of the authored list and keep one of each as a stamp.

	KEEPS THE FIRST OF EACH NAME. The kit ships six rows in a settings list: three toggles, two
	sliders and a button row, in the artist's order. One of each is a template, the rest were only
	ever there to show what the screen looks like full. ]]
function KitPage._takeTemplates(self)
	for _, child in (self.List :: ScrollingFrame):GetChildren() do
		if not child:IsA("GuiObject") then
			continue
		end
		local name = child.Name
		if self.Templates[name] then
			child:Destroy()
			continue
		end

		--- Read BEFORE it leaves the list: this is the artist's proportion, and it is the only copy.
		self._rowScale[name] = child.Size.Y.Scale
		self._rowWidth[name] = child.Size.X
		self._firstTemplate = self._firstTemplate or name

		child.Visible = true
		child.Parent = nil
		self.Templates[name] = child
	end
end

--- An authored row's height fraction: `PreviewHeightScale` when it has one, else its own scale.
local function authoredScale(row: GuiObject): number
	local preview = row:GetAttribute(PREVIEW_HEIGHT_ATTRIBUTE)
	return if type(preview) == "number" then preview else row.Size.Y.Scale
end

--[[ The authored-list counterpart of `_takeTemplates`: every child stays put and becomes a row, in
	`LayoutOrder`. Nothing is destroyed and nothing becomes a template. See the header. ]]
function KitPage._adoptRows(self)
	local children = {}
	for _, child in (self.List :: ScrollingFrame):GetChildren() do
		if child:IsA("GuiObject") then
			table.insert(children, child)
		end
	end
	table.sort(children, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for _, child in children do
		self._rowScaleOf[child] = authoredScale(child)
		table.insert(self._rows, child)
	end
end

--[[ Put a row the page built itself into an authored list, at `index` in the draw order (the end
	when nil). Its height is `heightScale` of the list, or read the way an authored row's is.
	Renumbers every row's `LayoutOrder`, because the order of `_rows` is the layout. ]]
function KitPage.adoptRow(self, row: GuiObject, heightScale: number?, index: number?)
	self._rowScaleOf[row] = heightScale or authoredScale(row)
	table.insert(self._rows, index or #self._rows + 1, row)
	for order, each in self._rows do
		each.LayoutOrder = order
	end
	row.Parent = self.List
	self:_syncMetrics()
end

--- The template a name refers to, or the first one authored when a page has only one kind of row.
function KitPage._templateFor(self, templateName: string?): (GuiObject?, string?)
	local name = templateName or self._firstTemplate
	if not name then
		return nil, nil
	end
	return self.Templates[name], name
end

--[[ Stamp a row on the end of the list.

	The clone carries its tags with it, so every button the kit drew inside the row is already a
	`UIButton` and already reacts to a cursor and to a highlight. Nothing here wires one. ]]
function KitPage.newRow(self, templateName: string?): GuiObject?
	local template, name = self:_templateFor(templateName)
	if not (template and name) then
		warn(string.format("[KitPage] %s has no row template named '%s'.", self.PageName, tostring(templateName)))
		return nil
	end

	local row = template:Clone()
	row:SetAttribute(TEMPLATE_ATTRIBUTE, name)
	row.LayoutOrder = #self._rows + 1
	row.Position = UDim2.new()
	--- A `UIGridLayout` writes every child's size itself, so writing one here is a value the layout
	--- overwrites on the next frame and a number that looks authoritative in the Explorer.
	if not self.Grid then
		row.Size = UDim2.new(self._rowWidth[name], UDim.new(0, self._rowHeight[name] or 0))
	end
	row.Parent = self.List
	table.insert(self._rows, row)

	self:_updateCanvas()
	return row
end

--- The rows on screen, in the order they are drawn.
function KitPage.rows(self): { GuiObject }
	return self._rows
end

--[[ Take ONE row out, rather than clearing the list.

	A page whose rows come and go independently needs this: `Pages V2/Quest` keys its rows by quest
	id so a claimed card can leave the middle of the list while its neighbours stay put, and a row it
	destroyed itself would sit in this bookkeeping forever, counted by `_updateCanvas` as a row that
	is still there. Returns whether the row was one of ours, which a caller is free to ignore. ]]
function KitPage.removeRow(self, row: GuiObject): boolean
	local index = table.find(self._rows, row)
	if index then
		table.remove(self._rows, index)
	end
	self._rowScaleOf[row] = nil
	row:Destroy()
	self:_updateCanvas()
	return index ~= nil
end

function KitPage.clearRows(self)
	for _, row in self._rows do
		row:Destroy()
	end
	table.clear(self._rows)
	table.clear(self._rowScaleOf)
	self:_updateCanvas()
end

--- The kit's header caption. A page that never renames itself can leave this alone.
function KitPage.setTitle(self, text: string)
	if self.Title and self.Title:IsA("TextLabel") then
		self.Title.Text = text
	end
end

-- === The list ===============================================================

--[[ Turn the authored list into one whose canvas we own. See the header for what each line is
	defending against. The proportions are read here and never read again: the instances they came
	from are about to be told a number in pixels. ]]
function KitPage._dressList(self)
	local list = self.List :: ScrollingFrame

	local layout = list:FindFirstChildOfClass("UIListLayout")
	if layout then
		self._gapScale = layout.Padding.Scale
		self.Layout = layout
	end

	--[[ A grid INSTEAD of a list, never as well: two layouts in one frame is the second one winning
		and the first one being a mystery. The cell keeps its authored scale (see the header). ]]
	local grid = list:FindFirstChildOfClass("UIGridLayout")
	if grid then
		self.Grid = grid
	end

	local padding = list:FindFirstChildOfClass("UIPadding")
	if padding then
		self._padScale = {
			top = padding.PaddingTop.Scale,
			bottom = padding.PaddingBottom.Scale,
			left = padding.PaddingLeft.Scale,
			right = padding.PaddingRight.Scale,
		}
		self.Padding = padding
	end

	if self.Grid then
		self._columns = self:_countColumns()
	end

	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.None
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ElasticBehavior = Enum.ElasticBehavior.Never
	list.ScrollBarThickness = 0
	list.ScrollBarImageTransparency = 1
end

--[[ Re-derive every pixel from the list's rendered height.

	Returns false when there is nothing to measure against yet, which is ordinary: a page can be
	asked to lay out before the viewport has given it a size, and the `AbsoluteSize` signal brings us
	straight back here when it has. ]]
function KitPage._syncMetrics(self): boolean
	local list = self.List :: ScrollingFrame
	local height = list.AbsoluteSize.Y
	if height <= 0 then
		return false
	end

	for name, scale in self._rowScale do
		self._rowHeight[name] = math.round(scale * height)
	end
	self._gap = math.round(self._gapScale * height)

	if self.Layout then
		self.Layout.Padding = UDim.new(0, self._gap)
	end
	if self.Padding then
		--- Converted for the same reason the rows are: a scale padding on a scrolling frame is
		--- measured against a canvas this file is about to set.
		self.Padding.PaddingTop = UDim.new(0, math.round(self._padScale.top * height))
		self.Padding.PaddingBottom = UDim.new(0, math.round(self._padScale.bottom * height))
	end

	if self.Grid then
		--[[ The cell is left in the artist's scale (header) and only READ here, in pixels, for the
			canvas and for whoever asks `cellGeometry`. Nothing about a grid is written back. ]]
		local grid = self.Grid :: UIGridLayout
		local width = list.AbsoluteSize.X
		self._cellWidth = math.round(grid.CellSize.X.Scale * width) + grid.CellSize.X.Offset
		self._cellHeight = math.round(grid.CellSize.Y.Scale * height) + grid.CellSize.Y.Offset
		self._cellGap = math.round(grid.CellPadding.Y.Scale * height) + grid.CellPadding.Y.Offset
		self._columns = self:_countColumns()
		self:_updateCanvas()
		return true
	end

	for _, row in self._rows do
		--[[ A row that is animating its own height owns it until it is gone. This runs on every
			viewport change, and a window resized while a card was folding would snap that card back
			to full height mid-collapse. The flag is the page's to set and to clear. ]]
		if row:GetAttribute(LEAVING_ATTRIBUTE) then
			continue
		end
		local name = row:GetAttribute(TEMPLATE_ATTRIBUTE)
		local ownScale = self._rowScaleOf[row]
		local rowHeight = if ownScale
			then math.round(ownScale * height)
			else (type(name) == "string" and self._rowHeight[name]) or 0
		if rowHeight > 0 then
			row.Size = UDim2.new(row.Size.X, UDim.new(0, rowHeight))
		end
	end

	self:_updateCanvas()
	return true
end

--[[ The canvas is the rows, the gaps between them and the list's own padding.

	SUMMED OFF THE ROWS rather than `count * rowHeight`: a list can hold rows of different heights
	(a settings screen does), and a page animating a row's height would otherwise be scrolling
	against a number that is no longer true. ]]
function KitPage._updateCanvas(self)
	if not self.List then
		return
	end

	local total = 0
	local count = 0
	for _, row in self._rows do
		if row.Visible then
			--- The row's OWN height, not its rendered one: a row parented this frame has an
			--- `AbsoluteSize` of zero until the next layout pass, and a canvas that lags the list by
			--- a frame shows as a scrollbar that cannot reach the row you just added.
			total += row.Size.Y.Offset
			count += 1
		end
	end

	if self.Grid then
		--[[ Rows of cards rather than a stack of rows, and `count` is already the number of VISIBLE
			children, which is exactly what a `UIGridLayout` lays out. A search that hides half the
			collection therefore shortens the canvas without anybody telling this file about it. ]]
		local rows = math.ceil(count / math.max(1, self._columns))
		total = if rows > 0 then rows * self._cellHeight + (rows - 1) * self._cellGap else 0
	elseif count > 1 then
		total += (count - 1) * self._gap
	end
	if self.Padding then
		total += self.Padding.PaddingTop.Offset + self.Padding.PaddingBottom.Offset
	end

	self._canvasHeight = total
	self.List.CanvasSize = UDim2.fromOffset(0, total)
end

-- === Grids ==================================================================

--[[ How many cards fit across, off the authored fractions and nothing else.

	`FillDirectionMaxCells` wins when the artist set one, because that is them saying it out loud.
	Otherwise it is the arithmetic a `UIGridLayout` does itself: n cells and n-1 gaps have to fit
	inside the width the `UIPadding` leaves, so the gap is added to both sides of the division and
	taken off the top. Measured on the kit's inventory (cell 0.178, gap 0.0225, left pad 0.018) this
	answers 5, and a naive `1 / (cell + gap)` answers 4.988 and then floors to the wrong number.

	NOT MEASURED FROM PIXELS, so it is the same answer before the page has ever been laid out. ]]
function KitPage._countColumns(self): number
	local grid = self.Grid :: UIGridLayout?
	if not grid then
		return 1
	end
	if grid.FillDirectionMaxCells > 0 then
		return grid.FillDirectionMaxCells
	end

	local cell = grid.CellSize.X.Scale
	local gap = grid.CellPadding.X.Scale
	if cell <= 0 then
		return 1
	end
	local room = 1 - self._padScale.left - self._padScale.right
	--- The epsilon is for the artist who made it fit exactly: 5 cells landing on 4.9999999 is a
	--- column lost to a float.
	return math.max(1, math.floor((room + gap) / (cell + gap) + 1e-6))
end

--[[ The grid's geometry in the canvas's own pixels, for a caller that has to reason about where a
	card IS without reading `AbsolutePosition` (which is a frame behind a canvas move).
	`Modules/CarViewportGrid.setLayout` takes these five in this order.

	Returns nothing useful on a list of rows; a page knows which kind it has. ]]
function KitPage.cellGeometry(self): (number, number, number, number, number)
	local top = if self.Padding then self.Padding.PaddingTop.Offset else 0
	local aspect = if self._cellHeight > 0 then self._cellWidth / self._cellHeight else 1
	return self._columns, self._cellHeight + self._cellGap, self._cellHeight, top, aspect
end

--[[ Size a grid's cells in the WINDOW's pixels, which is what the artist drew and what
	`_syncMetrics` already assumes. See "Correction" in the header: left in scale, a cell's height
	resolves against the canvas and a grid taller than its window draws every card several rows tall.

	THE ARTIST'S FRACTIONS ARE READ ONCE AND KEPT, and every write after that is offsets computed
	from them, redone whenever the list is re-laid-out. The COLUMN COUNT is settled first and written
	to `FillDirectionMaxCells`, because `_countColumns` reads the scale this is about to replace and
	would otherwise answer 1; the count is a fact about the authored fractions, so it cannot change
	with the window.

	Ends in `_syncMetrics`, so the canvas and `cellGeometry` are the new cells' numbers whichever of
	the two `AbsoluteSize` handlers the engine happens to run first. Safe to call more than once. ]]
function KitPage.pinGridToWindow(self)
	local grid = self.Grid :: UIGridLayout?
	local list = self.List :: ScrollingFrame?
	if not (grid and list) then
		return
	end

	if not self._gridScale then
		self._gridScale = { cell = grid.CellSize, gap = grid.CellPadding }
		if grid.FillDirectionMaxCells <= 0 then
			grid.FillDirectionMaxCells = self:_countColumns()
		end
		list:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:_pinGridCells()
		end)
	end
	self:_pinGridCells()
end

function KitPage._pinGridCells(self)
	local grid = self.Grid :: UIGridLayout
	local size = (self.List :: ScrollingFrame).AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return -- not laid out yet; the `AbsoluteSize` signal brings us back
	end

	-- The X values FLOOR. The kit's fractions leave 0.2% of slack across a row, so five rounded-up
	-- cells and their gaps can come out a pixel wider than the window, the layout wraps to one column
	-- fewer, and the canvas and the viewport grid are left counting the old one. Measured over window
	-- widths 200 to 1400: rounding overflowed at 272 of them, flooring at none.
	local cell, gap = self._gridScale.cell, self._gridScale.gap
	grid.CellSize = UDim2.fromOffset(
		math.floor(cell.X.Scale * size.X) + cell.X.Offset,
		math.round(cell.Y.Scale * size.Y) + cell.Y.Offset
	)
	grid.CellPadding = UDim2.fromOffset(
		math.floor(gap.X.Scale * size.X) + gap.X.Offset,
		math.round(gap.Y.Scale * size.Y) + gap.Y.Offset
	)
	self:_syncMetrics()
end

-- === Odds and ends ==========================================================

--- Tag a button this page built itself, so it gains the hover, the sound and the press every other
--- button in the UI has. Kit buttons arrive tagged; this is for anything a page adds.
function KitPage.tagButton(_self, button: GuiButton)
	if not CollectionService:HasTag(button, "UIButton") then
		CollectionService:AddTag(button, "UIButton")
	end
end

-- === Text size caps =========================================================

--[[ THE KIT'S TEXT CAPS ARE PIXELS, AND THEY WERE SET ON A SCREEN 1080 TALL.

	Nearly every kit label is `TextScaled` under a `UITextSizeConstraint` whose `MaxTextSize` is the
	label's own height in the frame the artist drew. Measured 2026-09-16 over the 284 capped labels in
	`MainUIV2`: cap times screen height over label height has a median of exactly 1080. So at 1080p
	the cap and the box agree, and on a taller screen the box grows and the cap does not. Rendered
	against its box, kit text came out at 97% at 1080p, 77% at 1440p and 55% at 4K. The old UI has no
	caps and holds 97% at all three.

	`scaleTextCaps` multiplies every cap under `root` by the screen's height over 1080, NEVER BELOW 1,
	so nothing at 1080p or smaller moves and a 4K screen gets the picture a 1080p one does. A label the
	artist capped below its box stays that much below it.

	THE ARTIST'S NUMBER IS KEPT ON THE CONSTRAINT (`KitTextCap`), so a row stamped from a template that
	was already scaled, a second call and a resize all start from the authored value rather than
	compounding. A constraint called `Ceiling` is a controller's own (`WeatherController._fitNotice`
	sizes those from the card's rendered height) and is left alone, as is anything added later that
	carries a `Fraction`. 100 is the engine's own ceiling. ]]
local TEXT_CAP_ATTRIBUTE = "KitTextCap"
local TEXT_CAP_ENGINE_MAX = 100

--- The screen height the kit's caps were drawn for. A test can set this very high and call
--- `refreshTextCaps` to see the unscaled caps again.
KitPage.TextCapReference = 1080

--[[ Every root `scaleTextCaps` has been handed, so a resize and `refreshTextCaps` can reach them.

	STRONG, AND EMPTIED ON `Destroying`. A weak table was the first cut and it lost roots: a Luau
	reference to an Instance that nothing else in Luau holds is collectable even while the Instance
	sits in the game, so a screen whose controller kept only the parts (the random car offer) dropped
	out and missed every resize after boot. Measured in the Phase 5 device pass at 1440p. ]]
local textCapRoots = {} :: { [Instance]: boolean }
local textCapWatching = false

local function textCapFactor(): number
	local camera = workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else 0
	return math.max(1, height / KitPage.TextCapReference)
end

local function scaleCap(constraint: Instance, factor: number)
	if not constraint:IsA("UITextSizeConstraint") then
		return
	end
	if constraint.Name == "Ceiling" or constraint:GetAttribute("Fraction") ~= nil then
		return
	end
	local authored = constraint:GetAttribute(TEXT_CAP_ATTRIBUTE)
	if type(authored) ~= "number" then
		authored = constraint.MaxTextSize
		constraint:SetAttribute(TEXT_CAP_ATTRIBUTE, authored)
	end
	constraint.MaxTextSize = math.clamp(math.round(authored * factor), 1, TEXT_CAP_ENGINE_MAX)
end

--- Rescale every cap under every root handed to `scaleTextCaps`, against the screen as it is now.
function KitPage.refreshTextCaps()
	local factor = textCapFactor()
	for root in textCapRoots do
		if root.Parent then
			for _, descendant in root:GetDescendants() do
				scaleCap(descendant, factor)
			end
		end
	end
end

--[[ Keep the kit's text caps in proportion to the screen, for `root` and everything later added
	under it (stamped rows included). Safe to call more than once on the same root. A page calls it
	from `initialize`; a code-built screen calls it on its clone of the shelf template. ]]
function KitPage.scaleTextCaps(root: Instance)
	if textCapRoots[root] then
		return
	end
	textCapRoots[root] = true
	root.Destroying:Connect(function()
		textCapRoots[root] = nil
	end)

	local factor = textCapFactor()
	for _, descendant in root:GetDescendants() do
		scaleCap(descendant, factor)
	end
	root.DescendantAdded:Connect(function(descendant)
		scaleCap(descendant, textCapFactor())
	end)

	--- One watcher for every root. The camera is looked up again on each change so a replaced
	--- `CurrentCamera` is not the one being read.
	if not textCapWatching then
		textCapWatching = true
		local function watch(camera: Camera?)
			if camera then
				camera:GetPropertyChangedSignal("ViewportSize"):Connect(KitPage.refreshTextCaps)
			end
		end
		watch(workspace.CurrentCamera)
		workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			watch(workspace.CurrentCamera)
			KitPage.refreshTextCaps()
		end)
	end
end

return KitPage
