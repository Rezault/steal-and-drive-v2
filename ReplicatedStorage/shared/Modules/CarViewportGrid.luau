--[[
	CarViewportGrid  (shared, client)
	---------------------------------
	Keeps a scrolling grid of car pictures down to the ones somebody can actually see. Hand it the
	cells and the cell geometry; it decides which of them have a car in them, moment to moment.

	IT EXISTS BECAUSE THE ALTERNATIVE IS A REAL COST, not because two pages happened to want the same
	code. `Modules/CarViewport` builds a genuine 25-mesh model of a body, and the screens that list
	cars list ALL of them — 43 slots on the collection index, one card per copy you own on the
	dealership and spawn screens. Built in one go that is a thousand-odd meshes rendering behind a
	panel showing six of them, on a game that is otherwise careful enough to publish its traffic
	bodies once. Built this way it is the six, plus a row of headroom.

	FIVE THINGS TO KNOW BEFORE CHANGING ANY OF IT.

	1. A CELL IS A CARD'S SLOT IN THE GRID, and the array position IS the slot. `setCells` takes the
	   cells in the order the layout will lay them out — which is the order of the cards that are
	   SHOWING, not of the collection, because a UIGridLayout lays out visible children only and a
	   search moves everything behind the query up the list.

	   A CELL WITH NO VIEWPORT IS A SPACER and is expected: the dealership's "leave empty" card is a
	   real card holding a real place in the grid with no car to put in it. Leaving it out of the
	   array would shift every car after it up one slot and fill the wrong rows.

	2. ROWS ARE COMPUTED, NEVER MEASURED. `AbsolutePosition` is a frame behind a canvas move — it is
	   where the layout engine last resolved a card, not where it is going — so the window test runs
	   against the same cell geometry the page lays its grid out with. The page has those numbers
	   already and they are exact; see `setLayout`.

	3. BUILDS GO THROUGH A QUEUE, drained a couple per frame. A flung scrollbar sweeps the window
	   over every row in the list, and building each row as it went past is a stutter rather than a
	   scroll. Cells are re-checked when they come OFF the queue rather than when they went on, so
	   everything the flick passed over is dropped unbuilt and only what it landed on is made.
	   Visible cards go first; buffer rows use the remaining budget, capped by elapsed build time.

	4. THE HEARTBEAT ONLY EXISTS WHILE THERE IS WORK. An idle connection on an open page is a
	   callback per frame doing nothing, forever. It is made when the queue fills and dropped the
	   moment it empties, so a page nobody is scrolling costs nothing at all.

	5. IT WATCHES THE SCROLL AND THE PAGE ITSELF, so a page wires this up once and then only has to
	   say when its layout or its list changed. Closing the page empties every viewport — the cards
	   survive, so reopening is a rebuild of the half-dozen on screen rather than of the list.

	   IT IS BOTH `Visible` FLAGS AND NOT JUST THE PAGE'S, which is what makes a page with TABS work
	   without knowing this module exists. The PAGE's flag is the one that survives the close tween
	   (`UIController` flips it at the END, so the cars are there for the whole animation out); the
	   SCROLL's is the one a tab switch moves. Watching only the page left a hidden tab holding a
	   dozen built car models, drawing nothing and costing everything.

	HOUSE RULE: no wiki-style double-bracket links in this comment — the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)

--[[ How much of the list is kept built either side of the scroll window, in rows, and how many cars
	may be built in one frame.

	One row of margin is what makes a scroll look like the cars were always there: a row is finished
	before any of it is on screen. The per-frame budget is deliberately low — one build measures about
	a millisecond, and the case the budget exists for is the flung scrollbar in note 3, where its job
	is to make sure most of that work is never done at all. ]]
local MARGIN_ROWS = 1
local BUILD_BUDGET = 2
local BUILD_SECONDS = 0.002

--[[ One card's place in the grid. Everything above `built` is the page's to write — `fade` is read
	at build time, so a car that scrolls into view on a card that is already dimmed arrives dimmed
	rather than flashing to full and being corrected. The rest is bookkeeping and belongs to this
	module.

	`built` is "this cell has had its turn", not "this cell has a car in it": a body with no published
	shell comes back from `CarViewport.set` empty, and without this it would be asked again every
	frame it stayed in the window for. `missing` lets replication events retry it when templates
	arrive; leaving the window also clears it. ]]
export type Cell = {
	viewport: ViewportFrame?,
	body: string?,
	paint: number?,
	mutation: string?, -- a weather mutation to draw the car wearing (`CarViewport.Options.mutation`)
	silhouette: boolean?,
	fade: number?,
	built: boolean?,
	queued: boolean?,
	wanted: boolean?,
	missing: boolean?,
}

local CarViewportGrid = {}
CarViewportGrid.__index = CarViewportGrid

export type Grid = typeof(setmetatable({} :: {
	_scroll: ScrollingFrame,
	_page: GuiObject,
	_cells: { Cell },
	_queue: { Cell },
	_pump: RBXScriptConnection?,
	_columns: number,
	_rowPitch: number,
	_cellHeight: number,
	_top: number,
	_aspect: number,
	_connections: { RBXScriptConnection },
	_templateRefreshPending: boolean,
}, CarViewportGrid))

--[[ `scroll` is the frame the cards are laid out in; `page` is the frame whose `Visible` says the
	screen is up (`UIController` flips it at the END of its close tween, so the cars are there for the
	whole of the animation out). Both are watched from here, so a page never has to remember to. ]]
function CarViewportGrid.new(scroll: ScrollingFrame, page: GuiObject): Grid
	local self = setmetatable({
		_scroll = scroll,
		_page = page,
		_cells = {},
		_queue = {},
		_pump = nil,
		_columns = 1,
		_rowPitch = 0,
		_cellHeight = 0,
		_top = 0,
		_aspect = 1,
		_connections = {},
		_templateRefreshPending = false,
	}, CarViewportGrid)

	-- Fires once per frame while a drag is moving and not at all when it is not, so this is the whole
	-- of what drives cars in and out of the list.
	table.insert(self._connections, scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:refresh()
	end))
	-- Both flags, and note 5 is why. The page's is the screen opening and closing; the scroll's is a
	-- tab on that page being switched away from.
	table.insert(self._connections, scroll:GetPropertyChangedSignal("Visible"):Connect(function()
		self:refresh()
	end))
	table.insert(self._connections, page:GetPropertyChangedSignal("Visible"):Connect(function()
		self:refresh()
	end))

	local function watchTemplates(folder: Instance)
		-- Coalesce replication bursts and retry only failed cells; no polling or extra model cache.
		table.insert(self._connections, folder.DescendantAdded:Connect(function()
			if self._templateRefreshPending then
				return
			end
			self._templateRefreshPending = true
			task.defer(function()
				self._templateRefreshPending = false
				local changed = false
				for _, cell in self._cells do
					if cell.missing then
						cell.built = false
						cell.missing = false
						changed = true
					end
				end
				if changed then
					self:refresh()
				end
			end)
		end))
	end
	local folder = ReplicatedStorage:FindFirstChild(TrafficConfig.TemplateFolderName)
	if folder then
		watchTemplates(folder)
	else
		local waiting: RBXScriptConnection
		waiting = ReplicatedStorage.ChildAdded:Connect(function(child)
			if child.Name == TrafficConfig.TemplateFolderName then
				waiting:Disconnect()
				watchTemplates(child)
				for _, cell in self._cells do
					if cell.missing then
						cell.built = false
						cell.missing = false
					end
				end
				self:refresh()
			end
		end)
		table.insert(self._connections, waiting)
	end
	table.insert(self._connections, page.Destroying:Connect(function()
		self:clear()
		for _, connection in self._connections do
			connection:Disconnect()
		end
	end))

	return self
end

--[[ The geometry the window test runs against, in the scroll's canvas pixels: how many cards to a
	row, the distance from one row's top edge to the next, how tall a card is, where the first row
	starts (a `UIPadding` on the scroll, 0 without one), and the width/height of the box the car is
	drawn in.

	`aspect` is passed on to `CarViewport.set`, which frames the camera for it. Changing it therefore
	invalidates every car already built, and rather than leave those subtly mis-framed until they
	happen to scroll away, they are dropped here and rebuilt. In practice it never changes: both pages
	using this draw their cards at a fixed shape. ]]
function CarViewportGrid:setLayout(columns: number, rowPitch: number, cellHeight: number, top: number, aspect: number)
	if math.abs(aspect - self._aspect) > 1e-3 then
		self._aspect = aspect
		for _, cell in self._cells do
			self:_release(cell)
		end
	end
	self._columns = math.max(columns, 1)
	self._rowPitch = rowPitch
	self._cellHeight = cellHeight
	self._top = top
	self:refresh()
end

--[[ The cells, in grid order. See note 1 — including the spacers.

	Cells that are no longer in the list are emptied, and cells that are in both keep their car: a
	search that narrows the list should not rebuild the cars that survived it. The queue is dropped
	wholesale instead of filtered, because every row in it has just moved. ]]
function CarViewportGrid:setCells(cells: { Cell })
	local kept = {}
	for _, cell in cells do
		kept[cell] = true
		cell.queued = false
	end
	for _, cell in self._cells do
		if not kept[cell] then
			self:_release(cell)
		end
		cell.queued = false
	end

	table.clear(self._queue)
	self._cells = cells
	self:refresh()
end

--[[ This cell is to be drawn differently than it already has been — the collection screen calls this
	on the car you have just stolen, which stops being a locked cut-out and becomes the real thing.
	What is there is dropped; the next pass builds it again if it is still on screen, and does not if
	it is not.

	`fade` and the transparency that goes with it are NOT this: that is one property write on a
	viewport and the page does it directly. This is for the things that are baked into the model when
	it is built. ]]
function CarViewportGrid:invalidate(cell: Cell)
	self:_release(cell)
end

--- Empty every viewport and forget the work. For a page tearing its list down.
function CarViewportGrid:clear()
	for _, cell in self._cells do
		self:_release(cell)
		cell.queued = false
	end
	table.clear(self._queue)
	self._cells = {}
	self:_drain() -- nothing left to do, which is what drops the Heartbeat
end

--[[ Which cars exist right now: the rows the scroll window is over, plus `MARGIN_ROWS` either side.
	Everything else is emptied.

	CHEAP ENOUGH TO RUN ON EVERY SCROLL FRAME, which is what it does. One loop over the cells doing
	two comparisons each, and the only work it starts is a queue push — nothing is cloned on this
	path. Call it after anything that moves the cards; the scroll and the page are already watched. ]]
function CarViewportGrid:refresh()
	local pitch = self._rowPitch
	if pitch <= 0 then
		return -- no layout yet, so nothing can have been built either
	end

	local open = self._page.Visible and self._scroll.Visible
	local top = self._scroll.CanvasPosition.Y
	local bottom = top + self._scroll.AbsoluteWindowSize.Y
	local margin = MARGIN_ROWS * pitch
	local buffer = {}
	table.clear(self._queue)

	for index, cell in self._cells do
		cell.queued = false
		if not cell.viewport then
			continue -- a spacer: a card with a place in the grid and no car to put in it
		end

		local wanted = open
		local visible = false
		if wanted then
			-- `index - 1` because the array is 1-based and the row is not.
			local rowTop = self._top + math.floor((index - 1) / self._columns) * pitch
			visible = rowTop + self._cellHeight > top and rowTop < bottom
			wanted = rowTop + self._cellHeight > top - margin and rowTop < bottom + margin
		end
		cell.wanted = wanted

		if wanted then
			if not cell.built then
				cell.queued = true
				table.insert(if visible then self._queue else buffer, cell)
			end
		elseif cell.built then
			self:_release(cell)
		end
	end

	for _, cell in buffer do
		table.insert(self._queue, cell)
	end
	-- Only Heartbeat spends the budget, so repeated layout/scroll updates cannot multiply it.
	if #self._queue > 0 then
		if not self._pump then
			self._pump = RunService.Heartbeat:Connect(function()
				self:_drain()
			end)
		end
	elseif self._pump then
		self._pump:Disconnect()
		self._pump = nil
	end
end

function CarViewportGrid:_release(cell: Cell)
	if cell.built and cell.viewport then
		CarViewport.clear(cell.viewport)
	end
	cell.built = false
	cell.missing = false
end

--- Build the cars that are waiting, a couple per frame, until there are none. Notes 3 and 4.
function CarViewportGrid:_drain()
	local built = 0
	local started = os.clock()
	while built < BUILD_BUDGET and (built == 0 or os.clock() - started < BUILD_SECONDS) do
		local cell = table.remove(self._queue, 1)
		if not cell then
			break
		end
		cell.queued = false
		-- Re-checked here rather than trusted from when it was queued; see note 3.
		if cell.wanted and not cell.built and cell.viewport then
			cell.built = true
			local shown = CarViewport.set(cell.viewport, cell.body, {
				paint = cell.paint,
				mutation = cell.mutation,
				aspect = self._aspect,
				silhouette = cell.silhouette,
			})
			cell.missing = not shown
			if shown then
				cell.viewport.ImageTransparency = cell.fade or 0
			end
			built += 1
		end
	end

	if #self._queue > 0 then
		if not self._pump then
			self._pump = RunService.Heartbeat:Connect(function()
				self:_drain()
			end)
		end
	elseif self._pump then
		self._pump:Disconnect()
		self._pump = nil
	end
end

return CarViewportGrid
