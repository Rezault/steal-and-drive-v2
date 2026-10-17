--[[
	Quest page, V2  (client)
	------------------------
	The daily quest board on the Cartoony Kit: one card per quest with its reward, its name, a
	progress caption and a bar, and a Claim button on the right; a Time Left clock draining under
	the panel. Claim one and its card leaves the board, so the list is a thing a player EMPTIES rather
	than a list they scroll past.

	`BuildQuestV2` (Command Runner) cloned the kit's `QuestsUI` into `MainUIV2.Pages.Quest`, kept the
	category tabs, hung the clock under the panel, and dressed the row. Its header carries every
	decision about the SHAPE of this screen; this file is the behaviour.

	THE TABS: Daily, Weekly, Monthly and All Time, and only Daily has a board (`QuestConfig.Tabs`).
	A tab with no board draws no cards, says `ComingSoonText` in the note row, and hides the clock.
	The page opens on `DefaultTab` every time. See `_selectTab`.

	=== THE FOUR RULES THE SHIPPING PAGE HAS, UNCHANGED =======================================

	They are the feature rather than the skin, so they are the same here and worded the same way.

	1. THE PAGE DECIDES NOTHING. Every number on it arrived from `QuestService` in one payload, via
	   `QuestController`. Pressing Claim fires a request and repaints NOTHING — the board that comes
	   back is the answer, which is what makes a refused claim visibly a claim that did not happen
	   rather than a card saying CLAIMED over money nobody was paid.

	   THE CELEBRATION IS FIRED BY THE ARRIVING BOARD, NOT BY THE PRESS. `_repaint` diffs the board
	   it was just handed against the one on screen, and a quest that WAS unclaimed and IS now
	   claimed is the only thing that starts an outro.

	2. THE COUNTDOWN IS DERIVED FROM A DEADLINE, NEVER DECREMENTED. `_resetAt - os.time()`, formatted.
	   One `os.time()` survives a page left open for an hour, a rejoin, and a server that never
	   ticked. The deadline comes in the payload and is also computable here, which is what the clock
	   falls back to before the first board lands and why it is never wrong by a timezone.

	3. THE ROWS ARE KEYED BY QUEST ID, not by position. A claimed card leaves the middle of the list,
	   and a pool indexed 1..n would hand row 2 to a different quest the moment row 1 left — which is
	   a card mid-outro being repainted as its neighbour. It also means a row that survives a refresh
	   is the SAME instance, so the `UIButton` observers are not churned.

	4. AN EMPTY LIST IS A REAL STATE AND IT SAYS SO. `_updateEmptyState` picks between "nothing
	   today" and "you took all of it", because those are different facts and only one of them is
	   worth feeling good about.

	=== WHAT THE KIT TOOK OVER ===============================================================

	Two thirds of the shipping page was layout, and none of it is here. `KitPage` owns the list, the
	row heights and the canvas, so `_readAuthoredLayout`, `_relayoutRow`, `_buildList`,
	`_syncMetrics`, `_updateCanvas` and the hand-drawn scroll indicator are all gone. The empty line
	is a row rather than a label floating over the well, and the pill's seven-colour palette is two
	buttons the artist drew — `ClaimBtn` in green and `DisabledBtn` in grey.

	THE BAR IS RESIZED HERE AND CUT BY A GRADIENT ON THE SHIPPING PAGE, and that is not a change of
	mind. The old fill is a 9-sliced pill that cannot draw its rounded caps in a box narrower than
	they are, so it is held at full width and cut by transparency. The kit's fill is a plain Frame
	whose `UICorner` radius is 1 in SCALE, so it is a rounded pill at any width at all, and the
	artist's own finished row is drawn by resizing it. Resizing is the kit's mechanism, so we use it.

	=== AND THE ONE THING THAT CHANGED BECAUSE THE ART DID ====================================

	THE REWARD FLIES AS A LABEL, NOT AS A BANKNOTE. The shipping row draws a chip with a coin sprite
	in it, and a claim sends that sprite to the cash counter. The kit writes the reward as text in its
	own green and draws no chip, so what leaves the card is a copy of the LABEL: `$2,500` lobbing
	into the corner where the money lives. It is the same sentence in the kit's own handwriting, and
	the chip emptying is the same beat it always was.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local QuestConfig = require(ReplicatedStorage.shared.Configs.QuestConfig)
local KitPage = require(script.Parent.Parent.KitPage)

local Page = KitPage.extend(QuestConfig.PageName)

--- The kit's row templates, as `BuildQuestV2` left them.
local ROW_NAME = "QuestRow"
local NOTE_NAME = "Note"
local SPACER_NAME = "Padding"

--[[ Where the spacer and the note sit relative to the quests. The quests take 1..n, so both of these
	are past anything the board can hold. ]]
local NOTE_ORDER = 500
local SPACER_ORDER = 999

--- The finished-state colour `BuildQuestV2` harvested off the artist's own completed row.
local DONE_ATTRIBUTE = "DoneColor"

--- Written on a row the outro owns. `KitPage` reads it and leaves that row's height alone.
local LEAVING_ATTRIBUTE = KitPage.LeavingAttribute

--[[ How often the countdown is recomputed while the page is open.

	A quarter second rather than a whole one, and for a reason that only applies to a DERIVED clock:
	the label is `deadline - now`, so a 1s tick lands wherever it lands relative to the real second
	boundary and the display skips a number roughly every other minute. At 0.25s the shown second is
	never more than a quarter second stale. Four cheap subtractions a second, only while the page is
	on screen. ]]
local TIMER_TICK = 0.25

--[[ The layer the claimed reward's label flies on.

	`MainUIV2` is a Sibling-behaviour ScreenGui whose two children, `HUD` and `Pages`, both sit at
	ZIndex 1. So a direct child of the ScreenGui at anything above that is over the panel it left and
	over the counter it lands on; the round number is headroom for whatever goes on that screen next. ]]
local FLYER_ZINDEX = 50

--- How far through the flight the label starts fading, as a fraction of the trip. See `_flyReward`:
--- it is absorbed by the counter rather than cut off at it.
local FLYER_FADE_FROM = 0.8

-- === The payload the service sends ==========================================
--[[ The contract, written down. Every field is one the UI actually reads, and there is no field for
	the button's state: see `statusOf`. `QuestService.QuestRow` is the other end of it. ]]
export type Reward = {
	Kind: string, -- "Cash" today
	Amount: number,
}

export type Quest = {
	Id: string, -- stable; what a claim names, and what a row is stamped with
	Name: string,
	Progress: number,
	Target: number,
	Unit: string?, -- "count" (default) or "cash" — how the two numbers in the caption are written
	Claimed: boolean?,
	Reward: Reward,
}

-- === State language =========================================================
--[[ The three states a quest can be in, onto the two buttons the artist drew.

	THE KIT HAS NO THIRD BUTTON AND DOES NOT NEED ONE. `DisabledBtn` is grey, which is this pack's
	spent colour, and it serves both ends of the quest's life: not yet, and already taken. The two
	read completely differently because the CAPTION says which, and both captions are the shipping
	screen's own words out of `QuestConfig`.

	`Claim` IS THE ONLY PRESSABLE STATE, and it is the only one that is a `TextButton` at all —
	`DisabledBtn` is a Frame, so an in-progress quest has nothing under the cursor to press. That is
	the artist agreeing with `Interactable = false` by construction. ]]
local BUTTON_STATE = {
	InProgress = { Claimable = false, Caption = QuestConfig.InProgressText },
	Claimable = { Claimable = true, Caption = QuestConfig.ClaimText },
	Claimed = { Claimable = false, Caption = QuestConfig.ClaimedText },
}

-- === Text ===================================================================
--[[ Non-breaking every space.

	`TextScaled` would sooner wrap a label onto a second line than pick a smaller one, and every
	string this page writes lands in a TextScaled box. `TextWrapped = false` silently clears
	`TextScaled` and drops the label to size 8, and `MinTextSize` is inert; NBSP is what works. The
	one label here that is exempt is the empty-list note, which is authored wrapped on purpose. ]]
local NBSP = utf8.char(0xA0)

local function oneLine(text: string): string
	return (string.gsub(text, " ", NBSP))
end

--[[ One named element of a row, wherever the wrapping put it.

	EVERY ROW'S CONTENTS LIVE ONE LEVEL DOWN, inside the `Card` frame `BuildQuestV2` wraps them in,
	and this is the one function that has to know. The card exists so the claim outro has something
	it can scale and fade as a single object: the row itself is owned by the `UIListLayout` (which
	writes its Position every frame) and its HEIGHT is the thing that collapses, so the contents need
	a parent that neither of those touches.

	Falls back to the row so this is also correct on a row that was never wrapped. ]]
local function partOf(row: Instance, name: string): Instance?
	local card = row:FindFirstChild("Card")
	local found = card and card:FindFirstChild(name)
	return found or row:FindFirstChild(name)
end

--[[ What "invisible" is called on one instance, as a tween goal, or nil for something with no alpha
	to give.

	WRITTEN OUT PER CLASS rather than looped over a list of property names, because the kinds of
	instance on a card do not agree on the word: a label fades on `TextTransparency` and again on
	`TextStrokeTransparency`, the kit's rims are `UIStroke` instances with a third name, and the card
	and its buttons are plain backgrounds. A card that faded only its text would leave the artist's
	white rectangle hanging over the row sliding up into it. ]]
local function fadeGoal(instance: Instance): { [string]: number }?
	if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		return { ImageTransparency = 1, BackgroundTransparency = 1 }
	elseif instance:IsA("TextLabel") or instance:IsA("TextButton") then
		return { TextTransparency = 1, TextStrokeTransparency = 1, BackgroundTransparency = 1 }
	elseif instance:IsA("UIStroke") then
		return { Transparency = 1 }
	elseif instance:IsA("CanvasGroup") then
		return { GroupTransparency = 1, BackgroundTransparency = 1 }
	elseif instance:IsA("GuiObject") then
		return { BackgroundTransparency = 1 }
	end
	return nil
end

--- A point on the quadratic curve through `from` and `to`, bent by `control`. The reward's flight
--- path; see `_flyReward` for why it is a curve and not a line.
local function bezier(from: Vector2, control: Vector2, to: Vector2, t: number): Vector2
	local inv = 1 - t
	return from * (inv * inv) + control * (2 * inv * t) + to * (t * t)
end

--- `Time Left: 15h 15m 15s`, the shipping screen's own format. Clamped at zero, never negative.
local function clockText(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return oneLine(string.format(QuestConfig.TimeLeftFormat, `{seconds // 3600}h {(seconds % 3600) // 60}m {seconds % 60}s`))
end

--[[ What the reward line says. Cash goes through the project's own formatter so a quest payout reads
	the same as the number on a collect mat; anything else is a count.

	SIGNED, WHERE THE SHIPPING PAGE'S IS NOT, and the art is why. There the reward sits in a chip on
	the far right with a banknote beside it, so nothing has to say which number is the prize. Here it
	is a bare figure directly above the quest's name, and half this catalogue's quests are about money
	too: `$3,500` over `Collect $50,000` is two cash figures on top of each other with nothing to tell
	them apart. A leading `+` is the shortest thing that does, and it is the notation the HUD's rate
	line already uses. ]]
local REWARD_PREFIX = "+"

local function rewardText(reward: Reward): string
	if reward.Kind == "Cash" then
		return REWARD_PREFIX .. QuestConfig.formatAmount(reward.Amount, "cash")
	end
	return `{REWARD_PREFIX}{QuestConfig.formatCount(reward.Amount)}`
end

--[[ Which of the three states a quest is in.

	DERIVED, NOT STORED, for the same reason the garage derives pending cash: a `Status` field
	alongside `Progress` and `Claimed` is a third thing that can disagree with the two that are
	actually true. ]]
local function statusOf(quest: Quest): string
	if quest.Claimed then
		return "Claimed"
	elseif quest.Progress >= quest.Target then
		return "Claimable"
	end
	return "InProgress"
end

--[[ Set a kit bar to a fraction of its track.

	RESIZED, not cut by transparency — see the header. `UICorner` at radius 1 in scale keeps both
	ends round at any width, so a bar at 3% is the left cap of the same pill rather than a sliver.
	Hidden outright at zero, because a pill squeezed to nothing still draws its own rim. ]]
local function setBar(fill: GuiObject, ratio: number, done: boolean)
	local level = math.clamp(ratio, 0, 1)
	fill.Visible = level > 0
	fill.Size = UDim2.new(level, 0, fill.Size.Y.Scale, fill.Size.Y.Offset)

	local gradient = fill:FindFirstChild("Fill")
	local target = if done then fill:GetAttribute(DONE_ATTRIBUTE) else fill:GetAttribute("FillColor")
	if gradient and gradient:IsA("UIGradient") and typeof(target) == "ColorSequence" then
		gradient.Color = target
	end
end

--[[ Remember the bar's authored colour before anything overwrites it.

	The blue ramp lives in the gradient itself, where an artist expects to find it, and the green one
	is the `DoneColor` attribute `BuildQuestV2` harvested off the artist's finished row. Reading the
	blue back off the instance on the first pass is what keeps it one copy rather than two. ]]
local function rememberFill(fill: GuiObject)
	if fill:GetAttribute("FillColor") ~= nil then
		return
	end
	local gradient = fill:FindFirstChild("Fill")
	if gradient and gradient:IsA("UIGradient") then
		fill:SetAttribute("FillColor", gradient.Color)
	end
end

-- === Building ===============================================================

function Page.initialize(self)
	--- The kit's text caps are pixels for a 1080-tall screen; this keeps them in proportion above it.
	KitPage.scaleTextCaps(self.PageUI)

	--[[ The rows, keyed by quest id — header note 3.

		NOT `self._rows`, which is `KitPage`'s own list of the GuiObjects it has stamped. A page
		extending `KitPage` owns the names it invents and nothing else; overwriting that one is a
		mistake this project has already made once, on the settings screen. ]]
	self._byId = {} :: { [string]: GuiObject }
	--[[ Quests whose card is mid-outro: still drawn, no longer repainted, and not yet destroyed. Set
		by `_repaint` when it spots a claim, cleared by the one function that destroys the row. ]]
	self._leaving = {} :: { [string]: boolean }
	--[[ What is currently ON SCREEN, as `[id] = wasClaimed`. The claim diff is a comparison against
		this and nothing else: a board is a snapshot, so "this quest just got claimed" is only
		answerable against the snapshot before it. Empty at construction, which is what makes the
		first board of a session animate nothing — a quest claimed yesterday is not news. ]]
	self._painted = {} :: { [string]: boolean }
	self.Quests = {} :: { Quest }
	self._shown = {} :: { Quest }

	--[[ The clock starts on the answer this client can work out for itself, so the countdown is right
		from the first frame rather than sitting on a dead zero until the first board lands. The
		server sends the same number — header note 2. ]]
	self._resetAt = QuestConfig.resetAt()
	self._period = QuestConfig.ResetPeriod

	self:_bindFooter()
	self:_buildFixedRows()
	self:_bindTabs()
	self:_selectTab(QuestConfig.DefaultTab)

	--[[ Painted before the page is ever opened, which is load-bearing rather than tidy: `UIController`
		preloads every image under the page immediately after this returns, and it can only preload
		rows that exist. Built here, the first open is a finished screen; built on open, it is one
		assembling itself. ]]
	self:refresh()

	--[[ Repainted whenever a new board lands, which is the ONLY thing that changes what is drawn — a
		claim included. Subscribed here rather than in `new` because the controller may not have
		started when pages are constructed. ]]
	Dispatcher:Subscribe(QuestConfig.StateEvent, function()
		self:refresh()
	end)
end

--- The countdown under the panel: a drained copy of the row's own bar, and the clock over it.
function Page:_bindFooter()
	local footer = self.PageUI:FindFirstChild("TimeLeft")
	if not (footer and footer:IsA("GuiObject")) then
		warn("[Quest] No `TimeLeft` under the page; the board has no clock. Run BuildQuestV2.")
		return
	end

	self.Footer = footer
	self.TimerLabel = footer:FindFirstChild("Label")
	local track = footer:FindFirstChild("Track")
	self.TimerFill = track and track:FindFirstChild("Progress")
	if self.TimerFill and self.TimerFill:IsA("GuiObject") then
		rememberFill(self.TimerFill)
	end
end

--[[ The two rows that are not quests: the empty-list note and the kit's bottom spacer.

	BOTH ARE STAMPED ONCE, HERE, and neither is ever destroyed. The note is hidden rather than taken
	out, so `_updateEmptyState` is a `Visible` flip and a fade with nothing to rebuild, and
	`KitPage._updateCanvas` counts only visible rows so a hidden note costs the canvas nothing. ]]
function Page:_buildFixedRows()
	local note = self:newRow(NOTE_NAME)
	if note then
		note.LayoutOrder = NOTE_ORDER
		note.Visible = false
		if note:IsA("TextLabel") then
			--- What "opaque" is for this label, read off the art rather than assumed to be zero, so
			--- the fade-in has somewhere to land.
			self._noteAlpha = { Text = note.TextTransparency, Stroke = note.TextStrokeTransparency }
			self._noteStroke = note:FindFirstChildOfClass("UIStroke")
			self._noteStrokeAlpha = self._noteStroke and self._noteStroke.Transparency or 0
		end
	end
	self.Note = note

	--- The kit's own bottom spacer, so the last card does not sit against the panel's rim.
	local spacer = self:newRow(SPACER_NAME)
	if spacer then
		spacer.LayoutOrder = SPACER_ORDER
	end
end

-- === Tabs ===================================================================

--[[ Wire the kit's four category buttons. Each keeps the face colour the artist gave it, read here
	before `_paintTabs` ever dims one, so the picked tab goes back to exactly that. ]]
function Page:_bindTabs()
	self._tabButtons = {} :: { [string]: GuiButton }
	self._tabFace = {} :: { [string]: Color3 }

	local strip = self.Main and self.Main:FindFirstChild("CategoryBtns")
	if not strip then
		warn("[Quest] No `Main.CategoryBtns`; the board has no tabs. Run BuildQuestV2.")
		return
	end

	for _, tab in QuestConfig.Tabs do
		local button = strip:FindFirstChild(tab.Button)
		if not (button and button:IsA("GuiButton")) then
			warn(string.format("[Quest] No tab button `%s` under `CategoryBtns`.", tab.Button))
			continue
		end
		self._tabButtons[tab.Id] = button
		self._tabFace[tab.Id] = button.BackgroundColor3
		button.Activated:Connect(function()
			self:_pressTab(tab.Id)
		end)
	end
end

--- Whether the tab on screen has a board behind it.
function Page:_isLive(): boolean
	local tab = QuestConfig.tabOf(self._tab)
	return tab ~= nil and tab.Live == true
end

--[[ Point the page at one tab: the picked face, the dimmed ones, and whether the clock shows.

	IT DOES NOT REPAINT THE LIST. Its two callers want different things around it: a press repaints
	straight away, and `StartOpenThread` is about to repaint anyway. ]]
function Page:_selectTab(id: string)
	if not QuestConfig.tabOf(id) then
		return
	end
	self._tab = id

	local dim = QuestConfig.TabDimColor
	for tabId, button in self._tabButtons or {} do
		local face = self._tabFace[tabId]
		button.BackgroundColor3 = if tabId == id
			then face
			else Color3.new(face.R * dim.R, face.G * dim.G, face.B * dim.B)
	end

	if self.Footer then
		self.Footer.Visible = self:_isLive()
	end
end

--- A tab pressed. Pressing the one already showing does nothing.
function Page:_pressTab(id: string)
	if id == self._tab then
		return
	end
	self:_selectTab(id)
	if self.List then
		self.List.CanvasPosition = Vector2.zero
	end
	self:refresh()
end

--[[ One card, wired and parented. Painting is somebody else's job.

	The clone carries its tags with it, so `ClaimBtn` is already a `UIButton` with hover, sound and a
	gamepad highlight, and nothing here wires any of that. ]]
function Page:_newRow(id: string): GuiObject?
	local row = self:newRow(ROW_NAME)
	if not row then
		return nil
	end

	local fill = partOf(row, "ProgressBar")
	fill = fill and fill:FindFirstChild("Progress")
	if fill and fill:IsA("GuiObject") then
		rememberFill(fill)
	end

	local claim = partOf(row, "Btns")
	claim = claim and claim:FindFirstChild("ClaimBtn")
	if claim and claim:IsA("GuiButton") then
		--[[ The id is read off the row AT PRESS TIME rather than closed over here, so a refresh that
			moves a row cannot leave a button claiming the quest that used to be in that slot.
			`Activated` and not `MouseButton1Click`: it is the one event a mouse, a touch and a
			gamepad's A press all raise. ]]
		claim.Activated:Connect(function()
			self:_claim(row:GetAttribute("QuestId"))
		end)
	end

	return row
end

--[[ Bring the row pool into line with `_shown`, then paint it.

	ROWS ARE REUSED RATHER THAN REBUILT, which a rebuild on every open would ruin twice over: it
	would churn the `UIButton` observers, and it would destroy the very button whose handler is
	running when a claim repaints its own row.

	A LEAVING ROW IS IN `_shown` AND IS NOT REPAINTED. It has to stay in the list or the sweep below
	would take it before its outro had a frame to run; it must not be repainted or the CLAIMED
	caption and the flown reward would both come back. `_celebrate` paints it once, and that is the
	last paint it ever gets. ]]
function Page:_renderRows()
	local wanted: { [string]: boolean } = {}
	for index, quest in self._shown do
		wanted[quest.Id] = true
		local row = self._byId[quest.Id]
		if not row then
			row = self:_newRow(quest.Id)
			self._byId[quest.Id] = row
		end
		if row then
			row.LayoutOrder = index
		end
	end

	for id, row in self._byId do
		if not wanted[id] then
			self:removeRow(row)
			self._byId[id] = nil
			--[[ The one path that takes a row from under a running outro: the board rolled over at
				midnight and the quest it was folding is not on today's. `_outroRow` bails when it
				finds its row gone, so this is the only place left that can drop the flag — and a
				flag left set would hold a phantom quest in `_shown` on whatever future day drew that
				id again. ]]
			self._leaving[id] = nil
		end
	end

	self:_syncMetrics()

	for _, quest in self._shown do
		local row = self._byId[quest.Id]
		if row and not self._leaving[quest.Id] then
			self:_paintRow(row, quest)
		end
	end
end

-- === Drawing ================================================================

--- Everything one card shows, from one quest. Safe to call on a row that is already painted.
function Page:_paintRow(row: GuiObject, quest: Quest)
	row:SetAttribute("QuestId", quest.Id)

	local text = partOf(row, "Text")
	local title = text and text:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = oneLine(quest.Name)
	end

	local reward = text and text:FindFirstChild("Reward")
	if reward and reward:IsA("TextLabel") then
		reward.Text = oneLine(rewardText(quest.Reward))
		--- Shown again on a repaint, because `_flyReward` hides it when the money leaves and a row
		--- reused for tomorrow's board would otherwise come back with an empty reward line.
		reward.Visible = true
	end

	--[[ The two buttons, one showing at a time. Both are written on even though only one is visible,
		so a repaint into the other state is a `Visible` flip with nothing stale behind it. ]]
	local state = BUTTON_STATE[statusOf(quest)]
	local btns = partOf(row, "Btns")
	for _, name in { "ClaimBtn", "DisabledBtn" } do
		local button = btns and btns:FindFirstChild(name)
		if button and button:IsA("GuiObject") then
			button.Visible = (name == "ClaimBtn") == state.Claimable
			local caption = button:FindFirstChild("Title")
			if caption and caption:IsA("TextLabel") then
				caption.Text = oneLine(state.Caption)
			end
		end
	end

	self:setRowProgress(row, quest.Progress, quest.Target, quest.Unit)
end

--[[ Fill one card's bar and caption.

	`unit` is how the two numbers are WRITTEN and has nothing to do with the bar — a cash quest reads
	"Progress: $4,200/$10,000" and a count reads "Progress: 3/5", because a five-digit stud count
	with no separators is a number nobody parses at a glance. See `QuestConfig.formatAmount`. ]]
function Page:setRowProgress(row: Instance, done: number, target: number, unit: string?)
	local ratio = if target > 0 then math.clamp(done / target, 0, 1) else 0

	local bar = partOf(row, "ProgressBar")
	local fill = bar and bar:FindFirstChild("Progress")
	if fill and fill:IsA("GuiObject") then
		--- Full is the artist's own finished row: the green ramp at the full width of the track.
		setBar(fill, ratio, ratio >= 1)
	end

	local label = partOf(row, "BarLabel")
	if label and label:IsA("TextLabel") then
		label.Text = oneLine(string.format(
			QuestConfig.ProgressFormat,
			QuestConfig.formatAmount(done, unit),
			QuestConfig.formatAmount(target, unit)
		))
	end
end

--[[ The line under an empty list, and WHICH line.

	NIL AND EMPTY ARE DIFFERENT. No board at all is the first moments of a session, before the
	server's reply has arrived — that draws an empty well and NO message, because "no quests today"
	is a claim we cannot make yet and would be wrong a fraction of a second later. An empty `quests`
	list IS the server saying so, and that gets the line.

	AND "EMPTY" IS TWO DIFFERENT FACTS. A board with nothing on it is the server having nothing to
	give; a board whose every quest has been claimed is the player having taken all of it, and that is
	the one a normal session ends on. Header note 4.

	IT FADES IN RATHER THAN APPEARING, and only when it was not already there. The last card folds
	away over about a fifth of a second, and a line that hard-cuts into the space underneath arrives
	before the card has finished leaving, which reads as its having been there all along. ]]
function Page:_updateEmptyState()
	local note = self.Note
	if not (note and note:IsA("TextLabel")) then
		return
	end

	--- A tab with no board says so whether or not the daily board has arrived.
	local live = self:_isLive()
	local controller = live and Shard.get("QuestController")
	local board = controller and controller:board()
	local show = not live or (board ~= nil and #self._shown == 0)
	note.Text = if not live
		then QuestConfig.ComingSoonText
		elseif #self.Quests > 0 then QuestConfig.AllClaimedText
		else QuestConfig.EmptyText

	if show == note.Visible then
		return
	end

	if self._noteTween then
		self._noteTween:Cancel()
		self._noteTween = nil
	end

	if not show then
		note.Visible = false
		--- The canvas is the visible rows, so a note going away has to say so.
		self:_updateCanvas()
		return
	end

	local alpha = self._noteAlpha or { Text = 0, Stroke = 0 }
	note.TextTransparency = 1
	note.TextStrokeTransparency = 1
	note.Visible = true
	self:_updateCanvas()

	local info = TweenInfo.new(QuestConfig.ClaimEffect.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	self._noteTween = TweenService:Create(note, info, {
		TextTransparency = alpha.Text,
		TextStrokeTransparency = alpha.Stroke,
	})
	self._noteTween:Play()

	--- The kit's type carries its own outline, and a caption that faded in from behind a hard rim
	--- would read as two objects arriving at different times.
	if self._noteStroke then
		self._noteStroke.Transparency = 1
		TweenService:Create(self._noteStroke, info, { Transparency = self._noteStrokeAlpha or 0 }):Play()
	end
end

-- === The countdown ==========================================================
--[[ Header note 2: this reads a clock, it does not run one.

	THE ZERO BRANCH IS THE ROLLOVER, and it is the one thing on this page that asks the server for
	something on its own. A player sitting on the board at midnight has a deadline that has passed;
	`_askServer` re-pings, `QuestService._roll` notices the day has turned and wipes the board, and
	the reply repaints these rows through the state event. Until it lands, `_fetch` falls back to the
	client's own `QuestConfig.resetAt()`, so the clock restarts at a full day immediately rather than
	sitting on a dead zero waiting for a round trip. ]]
function Page:_updateTimer()
	local remaining = self._resetAt - os.time()
	if remaining <= 0 then
		self:_askServer()
		--- `_repaint` and not `refresh`: refresh ends by calling this, and a countdown that repaints
		--- itself is a loop.
		self:_repaint()
		remaining = math.max(0, self._resetAt - os.time())
	end

	if self.TimerLabel and self.TimerLabel:IsA("TextLabel") then
		self.TimerLabel.Text = clockText(remaining)
	end

	--- The bar DRAINS: it is time left, which is how the shipping screen draws it too.
	if self.TimerFill and self.TimerFill:IsA("GuiObject") then
		local ratio = if self._period > 0 then math.clamp(remaining / self._period, 0, 1) else 0
		setBar(self.TimerFill, ratio, false)
	end
end

-- === Data ===================================================================
--[[ The seam. Everything above is fed by this and knows nothing else about where quests come from.

	It reads whatever board `QuestController` is currently holding — no remote is fired here and
	nothing yields, so it is safe on a Heartbeat tick and safe before the controller exists.

	NO BOARD YET IS A REAL STATE, not an error: this runs once during page construction, which is
	before the first board can possibly have arrived. It answers an empty list and the client's own
	deadline, which draws an empty well under a correct clock. ]]
function Page:_fetch(): ({ Quest }, number, number)
	local controller = Shard.get("QuestController")
	local board = controller and controller:board()
	if not board then
		return {}, QuestConfig.resetAt(), QuestConfig.ResetPeriod
	end

	return board.quests, tonumber(board.resetAt) or QuestConfig.resetAt(), tonumber(board.period) or QuestConfig.ResetPeriod
end

--- Ask for a fresh board. The reply comes back through the state event, not from this call.
function Page:_askServer()
	local controller = Shard.get("QuestController")
	if controller then
		controller:refresh()
	end
end

--[[ Which of the board's quests the list actually draws: everything unclaimed, plus whatever is still
	folding itself away.

	IN THE BOARD'S OWN ORDER. Filtering preserves it, and the board arrives sorted by id
	(`QuestConfig.dailySet`), so a card leaving does not reshuffle the two beside it — they close up,
	which is the only movement the eye should have to follow.

	A TAB WITH NO BOARD SHOWS NONE OF THEM. The daily rows are taken out rather than hidden, and made
	again when Daily is picked; three rows is nothing to rebuild, and it keeps one path through
	`_renderRows` rather than two. ]]
function Page:_visibleQuests(): { Quest }
	local shown = {}
	if not self:_isLive() then
		return shown
	end
	for _, quest in self.Quests do
		if not quest.Claimed or self._leaving[quest.Id] then
			table.insert(shown, quest)
		end
	end
	return shown
end

--[[ Take the board, work out what just happened to it, and draw the answer.

	THE DIFF IS THE WHOLE POINT OF THIS FUNCTION and it is three lines: a quest this page was drawing
	as unclaimed, which the board now says is claimed, was just paid for. That is the only thing that
	starts a celebration — header note 1. It cannot fire for a claim the server refused (the board
	comes back unchanged), it cannot fire twice for one claim (`_painted` is rewritten before anything
	animates), and it cannot fire for a quest claimed in an earlier session (`_painted` starts empty).

	THE ANIMATION IS SKIPPED WHEN NOBODY IS LOOKING. `refresh` runs on every state event, including
	ones that land while the page is shut, and a card that folded away unwatched would just be a quest
	that had vanished by the time the player next opened the screen. ]]
function Page:_repaint()
	local previous = self._painted
	self.Quests, self._resetAt, self._period = self:_fetch()

	local celebrating: { Quest } = {}
	--- On another tab the daily cards are not drawn, so there is nothing to watch fold away.
	local watching = self.PageUI.Visible and self:_isLive()
	local painted: { [string]: boolean } = {}
	for _, quest in self.Quests do
		painted[quest.Id] = quest.Claimed == true
		if quest.Claimed and previous[quest.Id] == false and watching then
			self._leaving[quest.Id] = true
			table.insert(celebrating, quest)
		end
	end
	self._painted = painted

	self._shown = self:_visibleQuests()
	self:_renderRows()
	self:_updateEmptyState()

	--- After the render, because a celebration needs the row it is celebrating to exist.
	for _, quest in celebrating do
		self:_celebrate(quest)
	end
end

--- Pull the board and repaint the whole page from it.
function Page:refresh()
	self:_repaint()
	self:_updateTimer()
end

-- === Claiming ===============================================================
--[[ What a claim looks like: the reward leaves the card and flies to the cash counter, the card says
	CLAIMED once, and then it folds away and takes its row with it.

	FIRED BY THE BOARD, NEVER BY THE PRESS (header note 1), so everything below is downstream of money
	the server has already paid. Nothing here can fail in a way that costs anybody a dollar, which is
	why none of it is guarded beyond "is the instance still there".

	THE CARD IS PAINTED ONE LAST TIME, first, before anything moves. The button goes grey and reads
	CLAIMED for the length of the outro, which is the receipt for the press — a card that vanished the
	instant it was pressed leaves the player unsure which of the three they just took. ]]
function Page:_celebrate(quest: Quest)
	local row = self._byId[quest.Id]
	if not row then
		--- Nothing to animate, so nothing owns the id. Dropping the flag here is what stops a quest
		--- with no row sticking in `_shown` forever.
		self._leaving[quest.Id] = nil
		return
	end

	self:_paintRow(row, quest)
	self:_flyReward(row)
	self:_outroRow(row, quest.Id)
end

--[[ Where the money is going: the HUD's cash block, bottom left.

	FOUND EACH TIME RATHER THAN CACHED, and not for tidiness — the HUD's race rules hide this exact
	instance for the length of a run, and a claim with the counter off screen should send its reward
	nowhere rather than into a corner where there is nothing to land on. Absent art answers nil and
	the flight is skipped, which is a claim with no flourish rather than a broken one. ]]
function Page:_cashCounter(): (GuiObject?, GuiObject?)
	local screen = self.PageUI:FindFirstAncestorWhichIsA("ScreenGui")
	local hud = screen and screen:FindFirstChild("HUD")
	local cash = hud and hud:FindFirstChild("Cash")
	if cash and cash:IsA("GuiObject") and cash.Visible then
		return cash, screen
	end
	return nil, screen
end

--[[ The reward's flight, card to counter.

	ONE LABEL, NOT A SPRAY. The house note on effect intensity is that a reaction should be small and
	physical, and the readable version of "this money is now yours" is the thing that was on the card
	going to the place the money lives. A burst says the same thing louder and less clearly, and this
	screen already has three cards' worth of art on it.

	IT IS THE CARD'S OWN REWARD LINE THAT LEAVES. The label is hidden on the same frame the flyer
	appears at its exact rect, so it reads as one object rather than as a copy. The card is then a
	quest with no price on it for the fifth of a second before it starts to fade, which is the honest
	picture — the money is off the card — and is why `HoldTime` is short.

	PARENTED TO THE SCREENGUI, NOT TO THE PAGE, for two reasons that both matter. The page is about to
	fade and fold, and a child of it would fade and fold with the label still in mid-air; and the list
	`ClipsDescendants`, so a label inside it would be cut off at the panel's edge one frame after it
	left. The ScreenGui is also the one coordinate space the card and the counter can both be
	expressed in without an inset correction — every rect below is an absolute one with the screen's
	own origin subtracted back out.

	HAND-STEPPED, NOT TWEENED, because the path is a curve. `TweenService` interpolates a straight
	line between two `UDim2`s; a reward that slides diagonally across the screen reads as a sprite
	being dragged, where one that lobs reads as something thrown. The easing is `Quad In`, so it
	drifts off the card and then dives into the counter rather than arriving at a constant crawl.

	NOTHING WAITS ON IT. The cash landed in the profile before this client heard about the claim, so
	the counter has usually finished rolling before the label gets there; it explains a number that
	already moved. That is also why it does not punch the counter on arrival. ]]
function Page:_flyReward(row: GuiObject)
	local knobs = QuestConfig.ClaimEffect
	local text = partOf(row, "Text")
	local reward = text and text:FindFirstChild("Reward")
	local target, screen = self:_cashCounter()
	if not (target and screen and reward and reward:IsA("TextLabel") and reward.Visible) then
		return
	end

	local size = reward.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end

	local root = screen.AbsolutePosition
	local from = reward.AbsolutePosition + size / 2 - root
	local to = target.AbsolutePosition + target.AbsoluteSize / 2 - root

	--[[ The bow in the flight, perpendicular to nothing and simply UP: the card is high on the panel
		and the counter is in the bottom corner, so a lifted midpoint gives the label a throw rather
		than a slide. Scaled by the distance travelled, so the arc is the same shape on a phone as on
		a monitor. ]]
	local control = (from + to) / 2 - Vector2.new(0, (to - from).Magnitude * knobs.Lift)

	--- A clone, so it arrives in the artist's own type, outline and green gradient rather than in a
	--- label this file had to describe.
	local flyer = reward:Clone()
	flyer.Name = "QuestRewardNote"
	flyer.AnchorPoint = Vector2.new(0.5, 0.5)
	flyer.Position = UDim2.fromOffset(from.X, from.Y)
	flyer.Size = UDim2.fromOffset(size.X, size.Y)
	flyer.Visible = true
	flyer.ZIndex = FLYER_ZINDEX

	local scale = Instance.new("UIScale")
	scale.Scale = knobs.FlightStartScale
	scale.Parent = flyer

	--- Hidden and parented on the same frame, so the reward never exists twice on screen.
	reward.Visible = false
	flyer.Parent = screen

	local stroke = flyer:FindFirstChildOfClass("UIStroke")
	local opaque = { Text = flyer.TextTransparency, Stroke = stroke and stroke.Transparency or 0 }

	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(delta)
		if not flyer.Parent then
			connection:Disconnect()
			return
		end

		elapsed += delta
		local alpha = math.clamp(elapsed / knobs.FlightTime, 0, 1)
		local eased = TweenService:GetValue(alpha, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

		local point = bezier(from, control, to, eased)
		flyer.Position = UDim2.fromOffset(point.X, point.Y)
		scale.Scale = knobs.FlightStartScale + (knobs.FlightEndScale - knobs.FlightStartScale) * eased

		--- Faded over the last of the flight rather than blinked out on arrival: the label is
		--- absorbed by the counter, and a hard cut at full opacity reads as a dropped frame.
		local faded = math.max(0, (alpha - FLYER_FADE_FROM) / (1 - FLYER_FADE_FROM))
		flyer.TextTransparency = opaque.Text + (1 - opaque.Text) * faded
		if stroke then
			stroke.Transparency = opaque.Stroke + (1 - opaque.Stroke) * faded
		end

		if alpha >= 1 then
			connection:Disconnect()
			flyer:Destroy()
		end
	end)
end

--[[ The card folds away and the list closes up behind it.

	THREE BEATS, and they are separate because they say different things. The PUNCH is the press
	landing. The HOLD is long enough to read the grey CLAIMED button the punch drew attention to. The
	FOLD is the quest leaving: the card fades and shrinks in place while the ROW's height collapses
	under it, so everything below slides up into the gap.

	THE CARD SHRINKS AND THE ROW COLLAPSES, WHICH ARE TWO DIFFERENT INSTANCES. Folding the row alone
	squashes the art vertically on its way out, which looks like a rendering fault rather than a card
	leaving; fading the card alone leaves a quest-shaped hole in the middle of the list that closes
	with a jump. Running both, with the card ahead of the row, means the art is nearly gone by the
	time the space it occupied starts to close.

	THE CANVAS IS DRIVEN WHILE IT FOLDS. `KitPage._updateCanvas` sums the live row heights, so
	stepping it each frame keeps the list honest through the collapse instead of holding a canvas a
	whole row taller than its contents for as long as the fold lasts.

	`Quad In` ON THE COLLAPSE, deliberately: the layout's padding does not shrink with the row, so the
	last gap closes in one frame when the row is finally destroyed. Easing the fold so it is at its
	fastest at the end is what hides that step in motion.

	IT OWNS THE ROW UNTIL IT IS DONE. `finish` is the only thing that clears `_leaving`, takes the row
	out of the pool and destroys it, and it runs down every path out of here — including the one where
	the card was never wrapped. A page closed mid-fold leaves the tweens to finish on an invisible
	screen, which they do. ]]
function Page:_outroRow(row: GuiObject, id: string)
	local knobs = QuestConfig.ClaimEffect
	local card = row:FindFirstChild("Card")
	local scale = card and card:FindFirstChild("CardScale")

	local function finish()
		self._leaving[id] = nil
		if self._byId[id] == row then
			self._byId[id] = nil
		end
		self:removeRow(row)
		--- The board has not changed; this is the list catching up with a row that has gone, and it
		--- is what puts the "all claimed" line up when the last card leaves.
		self:_repaint()
	end

	if not (card and scale and scale:IsA("UIScale")) then
		finish()
		return
	end

	row:SetAttribute(LEAVING_ATTRIBUTE, true)

	task.spawn(function()
		local punch = TweenService:Create(
			scale,
			TweenInfo.new(knobs.PunchTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = knobs.PunchScale }
		)
		punch:Play()
		punch.Completed:Wait()
		task.wait(knobs.HoldTime)

		--- The row can be destroyed inside those two beats: a board that rolls over at midnight takes
		--- every quest on it with it.
		if not row.Parent then
			return
		end

		local fade = TweenInfo.new(knobs.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(scale, fade, { Scale = knobs.FadeScale }):Play()
		for _, part in card:GetDescendants() do
			local goal = fadeGoal(part)
			if goal then
				TweenService:Create(part, fade, goal):Play()
			end
		end
		local cardGoal = fadeGoal(card)
		if cardGoal then
			TweenService:Create(card, fade, cardGoal):Play()
		end

		--- The fold starts inside the fade rather than after it, so the two read as one movement.
		task.wait(math.max(0, knobs.FadeTime - knobs.CollapseTime))
		if not row.Parent then
			return
		end

		local collapse = TweenService:Create(
			row,
			TweenInfo.new(knobs.CollapseTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Size = UDim2.new(row.Size.X, UDim.new(0, 0)) }
		)
		local stepping = RunService.Heartbeat:Connect(function()
			self:_updateCanvas()
		end)
		collapse:Play()
		collapse.Completed:Wait()
		stepping:Disconnect()

		if row.Parent then
			finish()
		end
	end)
end

--[[ Press the green button.

	IT REPAINTS NOTHING, which is the whole of header note 1: the request goes out and the board that
	comes back is the answer. An optimistic flip to CLAIMED would be this page asserting a payment it
	cannot see land, and the one failure a reward screen must not have is saying CLAIMED over money
	nobody was paid.

	The local guard inside `QuestController.claim` stops the obvious dead press leaving the machine;
	`QuestService._onClaim` re-derives every part of it from state this client never touched. ]]
function Page:_claim(questId: string?)
	local controller = Shard.get("QuestController")
	if controller then
		controller:claim(questId)
	end
end

-- === Open / close ===========================================================
--[[ `UIController` calls these alongside its own scale tween, which is why this page does not define
	`Open`/`Close` — defining those would take the tween away from it and the panels would stop
	feeling like one object. ]]
function Page:StartOpenThread()
	if self.List then
		self.List.CanvasPosition = Vector2.zero
	end
	--- Back on the default tab, which is the one with the board, whatever was picked at close.
	self:_selectTab(QuestConfig.DefaultTab)

	--[[ Ask, then draw what we already have. In that order deliberately: the request is a round trip
		and the board in hand is at most a few seconds stale, so repainting from it first means the
		screen is never blank while the reply is in flight. The reply repaints again when it lands,
		through the state event. ]]
	self:_askServer()
	self:refresh()

	if self._timerConnection then
		return
	end
	local accumulated = 0
	self._timerConnection = RunService.Heartbeat:Connect(function(delta)
		accumulated += delta
		if accumulated < TIMER_TICK then
			return
		end
		accumulated = 0
		self:_updateTimer()
	end)
end

--- Nothing recomputes a countdown for a page nobody is looking at.
function Page:StartCloseThread()
	if self._timerConnection then
		self._timerConnection:Disconnect()
		self._timerConnection = nil
	end
end

return Page
