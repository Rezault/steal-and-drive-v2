--[[
	LeaderboardController  (client)
	-------------------------------
	Draws the leaderboard standing in the middle of the roundabout: fills the rows from the server's
	snapshot, and switches which board is showing when somebody presses a tab.

	=== IT DRAWS. IT DOES NOT RANK. ============================================================

	`LeaderboardService` sends one `LeaderboardState` carrying EVERY board at once, keyed by
	`LeaderboardConfig` `Key` — so switching tab is a local operation with no remote, no spinner and
	no round trip. The only thing this file ever sends upward is `LeaderboardReady`, which means "my
	board exists, send me the snapshot" and is safe to fire any number of times.

	That also means THERE IS NO SCORE THIS CAN SUBMIT. Every number on the board came off a profile
	the server already had; see the service's header note 2.

	=== FIVE THINGS THAT SHAPE THE REST ========================================================

	1. THE BOARD ARRIVES BEFORE ITS INSIDES DO. `StreamingEnabled` is on, so `observeTag` fires on
	   the Model while its descendants are still replicating, and a `FindFirstChild` walk at that
	   moment binds nothing at all. Every hop down is a `WaitForChild` — the same bug that once left
	   all 48 upgrade kiosks unbound, and that `DealershipSignController` note 1 documents.

	2. TWO FACES, ONE SELECTION. The plate carries a SurfaceGui on its Front and its Back so the plots
	   on both sides of the roundabout can read it. Both are bound and both are driven from ONE
	   selected key held on the board record, so a tab pressed on either face moves both. Binding them
	   separately with a tab each would let a player walk around the board and find it showing
	   something else.

	3. THE SNAPSHOT IS CACHED AND THE BOARD IS NOT THE CACHE. A board can stream out and back in, and
	   the snapshot arrives on the server's own slow timer — so the last one received is held here and
	   replayed onto any board that binds later. Without that, walking away and back leaves an empty
	   board until the next broadcast, up to a `ReadInterval` away.

	4. ROWS ARE HIDDEN, NEVER CLEARED-AND-LEFT. A refresh that returns four names has to hide rows
	   five through ten, or the board shows six stale entries from the last one. Every repaint walks
	   all `RowsShown` rows and turns off the ones it did not fill.

	5. THE TAB BUTTONS ARE BOUND BY HAND, not by tagging them `UIButton`. Not because the tag would
	   break — these tabs are sized in scale, and since 2026-08-19 the hover nudge rides a UIScale
	   and works on any shape anyway. Because the tag forces `Selectable` on, so a gamepad can reach
	   what it marks, and these are SurfaceGuis in Workspace: tagging them would put a board on a
	   wall into the same selection graph as the screen UI. `UpgradeController` and the dealership
	   sign's pencil are bound by hand for the same reason.

	HOUSE RULE: no wiki-style double-bracket links in this comment — the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Observers = require(ReplicatedStorage.Packages.Observers)
local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local LeaderboardConfig = require(ReplicatedStorage.shared.Configs.LeaderboardConfig)

local NAMES = LeaderboardConfig.Board

--- Seconds to wait for each hop down to a board's widgets. See note 1.
local BOARD_WAIT = 20

--[[ And the wait for the OPTIONAL ones — the refresh bar. Short on purpose: a board that does not
	have one is a board this must not park a bind thread on for twenty seconds, and by the time the
	required hops above it have all resolved, anything else on the same panel has had its chance to
	replicate. ]]
local EXTRA_WAIT = 3

--[[ How often the refresh bar is redrawn. FOUR TIMES A SECOND, not once a frame: it is a bar that
	drains over a minute, so a frame-rate update would be sixty writes to say the same thing. ]]
local TIMER_STEP = 0.25

--[[ The active tab's colours against an idle one. A COLOUR SWAP AND NOT AN OPACITY ONE: the kit's
	80%/100% state language dies on saturated fills — the same reason the title bars needed a shape
	rather than a transparency — and a tab strip has to answer "which one am I on?" from across a
	plaza, where a 20% difference in alpha is nothing at all. ]]
local TAB_ACTIVE_BG = Color3.fromRGB(0, 102, 255) -- #0066FF
local TAB_IDLE_BG = Color3.fromRGB(41, 52, 75) -- #29344B
local TAB_ACTIVE_TEXT = Color3.new(1, 1, 1)
local TAB_IDLE_TEXT = Color3.fromRGB(168, 179, 208)

type Face = {
	title: TextLabel,
	tabs: { [string]: TextButton },
	pages: { [string]: Frame },
	--- The refresh bar's gradient, or nil on a board authored before it existed. See `_drawTimer`.
	timer: UIGradient?,
}

type Board = {
	model: Model,
	faces: { Face },
	--- Which board is showing. One per BOARD, not per face — note 2.
	selected: string,
}

local LeaderboardController = Shard.new("LeaderboardController")

-- === Binding ================================================================

--[[ Walk one SurfaceGui down to the widgets this file writes, or nil if it is not a board face.

	Every hop waits, and every hop re-checks that the gui is still in the DataModel — without that, a
	board that streams out mid-walk parks the thread for the full timeout on each remaining hop. ]]
function LeaderboardController._resolveFace(self, gui: SurfaceGui): Face?
	local function step(parent: Instance?, name: string): Instance?
		if not (parent and gui:IsDescendantOf(game)) then
			return nil
		end
		return parent:WaitForChild(name, BOARD_WAIT)
	end

	local panel = step(gui, NAMES.PanelName)
	local bar = step(panel, NAMES.TitleBarName)
	local title = step(bar, NAMES.TitleName)
	local tabsFrame = step(panel, NAMES.TabsName)
	local pagesFrame = step(panel, NAMES.PagesName)
	if not (title and title:IsA("TextLabel") and tabsFrame and pagesFrame) then
		return nil
	end

	--[[ Resolved BY KEY off the config rather than by walking the children, which is the whole point
		of the naming contract: a page with no tab, or a tab whose page was renamed, is a missing
		entry here rather than a mismatched pair discovered when somebody presses it. ]]
	local tabs, pages = {}, {}
	for _, board in LeaderboardConfig.List do
		local button = tabsFrame:FindFirstChild(board.Key)
		local page = pagesFrame:FindFirstChild(board.Key)
		if button and button:IsA("TextButton") and page and page:IsA("Frame") then
			tabs[board.Key] = button
			pages[board.Key] = page
		end
	end

	if not next(pages) then
		return nil
	end

	--[[ Optional, and resolved LAST so a board without one still binds everything above it. The whole
		chain is nil-tolerant: no trough, no fill or no ramp all mean the same thing here, which is
		that this face simply has no bar to draw. ]]
	local timer = panel:WaitForChild(NAMES.TimerName, EXTRA_WAIT)
	local fill = timer and timer:WaitForChild(NAMES.TimerFillName, EXTRA_WAIT)
	local ramp = fill and fill:FindFirstChild(NAMES.TimerRampName)

	return {
		title = title,
		tabs = tabs,
		pages = pages,
		timer = if ramp and ramp:IsA("UIGradient") then ramp else nil,
	}
end

--[[ One tagged board has arrived. Bind every face on it and hand back the undo.

	FACES ARE WAITED FOR BY NAME, one per `LeaderboardConfig.Board.Faces` — never swept out of
	`GetChildren`. Note 1 is the reason and it is not hypothetical: a sweep on the frame the tag
	fires sees whichever guis happen to have replicated so far, which on a cold stream-in is
	routinely one of the two, and the result is a board whose back face is never bound and never
	repaints. A named wait cannot half-succeed. ]]
function LeaderboardController._bind(self, model: Model): (() -> ())?
	local screen = model:WaitForChild(NAMES.ScreenName, BOARD_WAIT)
	if not screen then
		return nil
	end

	local faces: { Face } = {}
	for _, side in NAMES.Faces do
		local gui = screen:WaitForChild(NAMES.GuiName .. side, BOARD_WAIT)
		--[[ Re-checked between hops: a board that streams out while this is waiting would otherwise
			keep the thread parked for the full timeout on every face left. ]]
		if not model:IsDescendantOf(game) then
			return nil
		end
		if gui and gui:IsA("SurfaceGui") then
			local face = self:_resolveFace(gui)
			if face then
				table.insert(faces, face)
			end
		end
	end

	if #faces == 0 then
		self.log:warn(string.format("%s has no usable face — run the BuildLeaderboardBoard command.", model:GetFullName()))
		return nil
	end

	local board: Board = { model = model, faces = faces, selected = LeaderboardConfig.List[1].Key }
	local trove = Trove.new()
	self._boards[model] = board

	for _, face in faces do
		for key, button in face.tabs do
			trove:Add(button.Activated:Connect(function()
				self:_select(board, key)
			end))
		end
	end

	self:_select(board, board.selected)

	--[[ Ask again on every bind, not only in `start`. A board that streams back in after the player
		has been away is a board with nothing on it, and this is what refills it — the service treats
		the ping as a refresh precisely so this can be fired freely. ]]
	self:getRemoteEvent("LeaderboardReady"):Fire()

	trove:Add(function()
		if self._boards[model] == board then
			self._boards[model] = nil
		end
	end)

	return function()
		trove:Destroy()
	end
end

-- === Drawing ================================================================

--[[ Show one board's page on every face, and paint the tab strip to match.

	Both halves of the state are written on every call rather than diffed against the last one: it is
	a dozen property writes on a press a player makes every few seconds, and a diff would be a second
	copy of "what is showing" that could disagree with the first. ]]
function LeaderboardController._select(self, board: Board, key: string)
	if not LeaderboardConfig.isBoard(key) then
		return
	end
	board.selected = key

	local entry = LeaderboardConfig.ByKey[key]
	for _, face in board.faces do
		face.title.Text = self:_oneLine(entry.Title)
		for pageKey, page in face.pages do
			page.Visible = pageKey == key
		end
		for tabKey, button in face.tabs do
			local active = tabKey == key
			button.BackgroundColor3 = if active then TAB_ACTIVE_BG else TAB_IDLE_BG
			button.TextColor3 = if active then TAB_ACTIVE_TEXT else TAB_IDLE_TEXT
		end
	end

	self:_paint(board)
end

--[[ `TextScaled` would sooner wrap a label to a second line than pick a smaller font, and every
	label on this board is one line. Same substitution the signs make; see `PlotConfig`. ]]
function LeaderboardController._oneLine(_self, text: string): string
	return (string.gsub(text, " ", utf8.char(0x00A0)))
end

--[[ Fill the visible page of one board from the cached snapshot.

	ONLY THE SELECTED PAGE IS FILLED, and that is about the headshots rather than about the text: a
	row's face is an `rbxthumb` image, and painting all six pages would put sixty thumbnail requests
	on the wire for the ten a player can actually see. The hidden pages are repainted the moment they
	are selected, which is the same beat their `Visible` flips on.

	A BOARD WITH NO SNAPSHOT YET DRAWS ITS EMPTY STATE, not a blank rectangle — a board that has not
	heard from the server and a board nobody has ranked on look the same to a player, and both of
	them should say so rather than look broken. ]]
function LeaderboardController._paint(self, board: Board)
	local entry = LeaderboardConfig.ByKey[board.selected]
	local rows = self._snapshot and self._snapshot[board.selected] or {}

	for _, face in board.faces do
		local page = face.pages[board.selected]
		if not page then
			continue
		end

		local drawn = 0
		for index = 1, NAMES.RowsShown do
			local row = page:FindFirstChild(NAMES.RowName .. index)
			if not row then
				continue
			end

			local data = rows[index]
			--[[ Note 4: a row the refresh did not reach is turned OFF, not left holding whatever the
				last one put in it. A shorter list must not leave a tail of stale names behind it. ]]
			if not data then
				row.Visible = false
				continue
			end

			row.Visible = true
			drawn += 1

			local rank = row:FindFirstChild(NAMES.RankName)
			if rank then
				rank.Text = "#" .. index
				rank.TextColor3 = LeaderboardConfig.rankColor(index)
			end

			local face3 = row:FindFirstChild(NAMES.HeadshotName)
			if face3 then
				face3.Image = string.format(NAMES.HeadshotFormat, data.Id)
			end

			local playerName = row:FindFirstChild(NAMES.PlayerName)
			if playerName then
				playerName.Text = self:_oneLine(data.Name)
			end

			--[[ Formatted HERE, from the raw number on the wire, through the board's own `Unit` —
				config header note 5. It is why a distance and a cash balance of the same magnitude
				read differently on two tabs of the same board. ]]
			local amount = row:FindFirstChild(NAMES.AmountName)
			if amount then
				amount.Text = LeaderboardConfig.format(entry, data.Value)
			end
		end

		local empty = page:FindFirstChild(NAMES.EmptyName)
		if empty then
			empty.Visible = drawn == 0
		end
	end
end

--[[ The refresh bar on every bound face: full when a snapshot has just landed, empty a
	`ReadInterval` later.

	=== IT IS TIMED OFF THE ARRIVAL, NOT OFF A DEADLINE ON THE WIRE ============================

	The server sends the snapshot and nothing else — no "next refresh at" — so this measures forward
	from the last one that came in. That is a bar which is right about the thing a player actually
	reads off it (how long ago these names were true) and only approximately right about the next
	update, because the server SKIPS a refresh on an empty lobby and a joining player's ping can
	force an early one. Both of those land as a bar that refills, which is the honest reading.

	A BOARD WITH NO SNAPSHOT YET IS DRAWN FULL rather than empty. An empty bar next to "NO RANKINGS
	YET" reads as a board that has given up; a full one reads as a board that is waiting, which is
	what it is doing.

	=== THE FILL IS CUT, NOT RESIZED ===========================================================

	`Offset.X` slides the ramp's hard step across a fill held at full width — the config's note on
	`TimerRampName` has the reasoning. The ramp is opaque below its midpoint, so a step parked at
	`alpha - 0.5` leaves exactly `alpha` of the trough coloured. ]]
function LeaderboardController._drawTimer(self)
	local alpha = 1
	if self._refreshedAt then
		local interval = math.max(1, LeaderboardConfig.ReadInterval)
		alpha = math.clamp(1 - (os.clock() - self._refreshedAt) / interval, 0, 1)
	end

	for _, board in self._boards do
		for _, face in board.faces do
			if face.timer then
				face.timer.Offset = Vector2.new(alpha - 0.5, 0)
			end
		end
	end
end

--[[ A fresh snapshot. Cached first, then every bound board repainted — note 3.

	Repaints ALL boards rather than a "current" one because there is no reason there may only ever be
	one: the tag is what makes a board, and a second one in a future lobby would bind and draw with
	no change here. ]]
function LeaderboardController._onState(self, snapshot: unknown)
	if type(snapshot) ~= "table" then
		return
	end
	self._snapshot = snapshot :: { [string]: { any } }
	--- Refills the bar. See `_drawTimer` for why the clock starts here and not on the server.
	self._refreshedAt = os.clock()

	for _, board in self._boards do
		self:_paint(board)
	end
	self:_drawTimer()
end

LeaderboardController:withRemoteEvents({
	-- client -> server: my board exists, send me the snapshot. Also "send it again".
	"LeaderboardReady",
	{
		LeaderboardState = function(snapshot: unknown)
			LeaderboardController:_onState(snapshot)
		end,
	},
})

LeaderboardController:withLifecycle({
	init = function(self)
		self._trove = Trove.new()
		self._boards = {} :: { [Model]: Board }
		--- The last snapshot the server sent. Survives a board streaming out and back in — note 3.
		self._snapshot = nil :: { [string]: { any } }?
		--- `os.clock()` when that snapshot landed. Nil = none has; the bar is drawn full.
		self._refreshedAt = nil :: number?
	end,

	--[[ Bound in `start` and not `init`, the rule every module here follows: `init` may not yield and
		this reaches into Workspace. `observeTag` makes the timing a non-question — it fires for the
		board if it is already here and for it whenever it streams in. ]]
	start = function(self)
		if not LeaderboardConfig.Enabled then
			return
		end

		self._trove:Add(Observers.observeTag(NAMES.Tag, function(model: Instance)
			if not model:IsA("Model") then
				return nil
			end
			return self:_bind(model)
		end, { workspace }))

		--[[ The refresh bar's clock. HEARTBEAT AND NOT RENDERSTEPPED: a minimised Studio stops
			rendering and every RenderStepped-driven thing on screen freezes with it, which has cost
			this project an afternoon before. Accumulated to `TIMER_STEP` rather than run every frame,
			and it exits early on a client with no board bound, so the cost on a player who has never
			walked past the roundabout is one comparison a frame. ]]
		local since = 0
		self._trove:Add(RunService.Heartbeat:Connect(function(delta: number)
			since += delta
			if since < TIMER_STEP then
				return
			end
			since = 0
			if next(self._boards) then
				self:_drawTimer()
			end
		end))

		--[[ The ping goes out here as well as on every bind, and it is not redundant: a client whose
			board is streamed out at boot would otherwise never ask, and would then bind — much later
			— against a snapshot that had been sitting on the server the whole time. ]]
		self:getRemoteEvent("LeaderboardReady"):Fire()
	end,
})

LeaderboardController:withCleanup(function()
	if LeaderboardController._trove then
		LeaderboardController._trove:Destroy()
	end
end)

return LeaderboardController
