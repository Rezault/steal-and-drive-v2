--[[
	Quest page  (client)
	--------------------
	The daily quest list: one row per quest with a status pill, a reward chip and a progress bar, over
	a "Time Left" countdown along the bottom. Claim a quest and its card leaves the board, so the
	list is a thing a player EMPTIES rather than a list they scroll past.

	SIX THINGS TO KNOW BEFORE CHANGING ANY OF IT.

	1. THE PAGE DECIDES NOTHING. Every number on it arrived from `QuestService` in one payload, via
	   `QuestController`; there is no local counter and no locally-remembered claim. Pressing the
	   green pill fires a request and repaints NOTHING — the board that comes back is the answer,
	   which is what makes a refused claim visibly a claim that did not happen rather than a row
	   saying CLAIMED over money nobody was paid. `_fetch` is still the one place that knows where a
	   board comes from; it just reads the controller now instead of a table in this file.

	   THE CELEBRATION IS FIRED BY THE ARRIVING BOARD, NOT BY THE PRESS, which is the same rule
	   wearing a party hat. `_repaint` diffs the board it was just handed against the one on screen,
	   and a quest that WAS unclaimed and IS now claimed is the only thing that starts an outro. So
	   the money flies out of a card the server has already paid for, and a refused claim animates
	   nothing at all. See note 6.

	2. ROW HEIGHTS ARE IN PIXELS, AND THAT IS NOT A STYLE CHOICE. Inside a ScrollingFrame a child's Y
	   *scale* resolves against the CANVAS, and the canvas is derived from the children — so scaled
	   rows and a content-sized canvas feed each other and run away. Measured here, in edit mode:
	   four 167px rows became 10,584px each on a 24,249px canvas within three frames. Roblox's own
	   `AutomaticCanvasSize` breaks that cycle, but then lands ~7px short of the layout's real content
	   size, which clips the last row at full scroll. So the row keeps its AUTHORED PROPORTIONS by
	   taking its authored height in *pixels* off the page's `AbsoluteSize`, the canvas is computed
	   from the row count, and `_syncMetrics` redoes both on resize. Nothing here reads
	   `AbsoluteCanvasSize`, and `AutomaticCanvasSize` is explicitly off.

	3. THE COUNTDOWN IS DERIVED FROM A DEADLINE, NEVER DECREMENTED. Same reason `GarageConfig` gives
	   for pending cash being derived rather than accumulated: one `os.time()` value survives a page
	   left open for an hour, a rejoin, and a server that never ticked, and there is no counter for
	   anything to disagree with. `_resetAt - os.time()`, formatted.

	   The deadline comes in the payload, but it is also computable here — `QuestConfig.resetAt()`
	   is the same UTC arithmetic on both sides of the wire — which is what the page falls back to
	   before the first board has arrived, and why the clock is never wrong by a timezone.

	4. THE LAYOUT IS THE MOCKUP, so every number this file needs is read OFF the authored art instead
	   of typed in again: the content well is the authored row's own rect, the gap above the list is
	   the gap the artist left under the title bar, and each bar's full width is its own inset
	   doubled. `_readAuthoredLayout` is the whole of it. `QuestRow` in the place is the TEMPLATE —
	   it is hidden and cloned, never shown.

	   PART OF THE ROW IS NOT WHERE THE MOCKUP DREW IT, on purpose. The claim pill sits on the
	   progress bar's line at the row's right edge rather than under the quest name, the bar is
	   shortened to make room for it, and two of the mockup's text boxes are widened past what the
	   artist drew because the strings that go in them are longer than the samples that were drawn
	   in them. `_relayoutRow` is where all of that happens and the whole argument for it. It is
	   still arithmetic on the authored rects rather than a second set of coordinates, so this note
	   holds: the row is described as relationships between edges instead of read straight off the
	   art. Moving the pill in the Explorer will not move it on screen, so change `_relayoutRow`
	   instead.

	5. THE CLONES ARE ALREADY BUTTONS. `StatusButton` carries the `UIButton` tag and `Instance:Clone`
	   keeps tags, so every cloned pill gets hover feedback and a click sound from
	   `Components/Button` with nothing wired here. It carries no `Page` attribute, so it opens
	   nothing.

	6. A CLAIMED QUEST IS NOT ON THE BOARD. The server still sends it — it has to, or nothing here
	   could tell a claim from a quest that vanished — but the list draws only the quests that are
	   still worth pressing, plus whichever card is currently animating its way off. Three
	   consequences, all of them deliberate:

	     • The rows are keyed by QUEST ID, not by position. A pool indexed 1..n would hand row 2 to
	       a different quest the moment row 1 left, which is a card mid-outro being repainted as its
	       neighbour. `_rows[id]` cannot do that, and it also means a row that survives a refresh is
	       the SAME instance, so the `UIButton` observers are not churned.
	     • An empty list is a real state and it says so. `_updateEmptyState` picks between "nothing
	       today" and "you took all of it", because those are different facts and only one of them
	       is worth feeling good about.
	     • The outro OWNS its row until it finishes. `_leaving` keeps the quest in the drawn list
	       while its card folds, keeps `_syncMetrics` from resizing it mid-collapse, and is cleared
	       by the one function that destroys it. Every knob it uses is in `QuestConfig.ClaimEffect`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UIControllerTypes = require(script.Parent.Parent.UIControllerTypes)
local UIGeom = require(script.Parent.Parent.UIGeom)
local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local QuestConfig = require(ReplicatedStorage.shared.Configs.QuestConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)

local PAGE_NAME = "Quest"

--[[ How often the countdown is recomputed while the page is open.

	A quarter second rather than a whole one, and for a reason that only applies to a *derived* clock:
	the label is `deadline - now`, so a 1s tick lands wherever it lands relative to the real second
	boundary and the display skips a number roughly every other minute. At 0.25s the shown second is
	never more than a quarter second stale. It is four cheap subtractions a second, only while the
	page is on screen. ]]
local TIMER_TICK = 0.25

--[[ The layer the claimed reward's banknote flies on.

	`MainUI` is a Sibling-behaviour ScreenGui, so a direct child's ZIndex is judged against the two
	frames that are already there — `HUD` at 1 and `Pages` at 5 — and not against anything inside
	them. Anything above 5 puts the note over the panel it left and over the counter it lands on;
	the round number is headroom for whatever gets added to that screen next. ]]
local FLYER_ZINDEX = 50

--- How far through the banknote's flight it starts fading, as a fraction of the trip. See
--- `_flyReward`: it is absorbed by the counter rather than cut off at it.
local FLYER_FADE_FROM = 0.8

-- === The payload the service sends ==========================================
--[[ This is the contract, written down. Every field is one the UI actually reads, and there is no
	field for the pill's state: see `statusOf`. `QuestService.QuestRow` is the other end of it. ]]
export type Reward = {
	Kind: string, -- "Cash" today; the key into `REWARD_ICON`
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
--[[ The pill's three states.

	One shape in seven colours, which the PSD parks in a palette outside the panels precisely so that
	state picks the colour at runtime rather than a screen hard-assigning one. Blue is what the mockup
	drew, so in-progress keeps it; green is the only one of the seven that reads as "press me" and it
	is the only pressable state; silver is the kit's spent colour and a claimed quest is spent.

	`Pressable` drives `Interactable`, not just the caption. A pill that is not a button should not
	light up or click under the cursor, and `Components/Button` hangs its hover off MouseEnter, which
	`Interactable` gates — so this one flag turns the whole reaction off with it.

	`Shown` is the second flag, and IN-PROGRESS IS THE ONLY STATE THAT DRAWS NO PILL. A blue pill
	saying IN-PROGRESS restated what the bar underneath it already shows, and it left three rows out
	of three wearing something button-shaped that does nothing; the pill now appears only when there
	is a press to make, so a green one anywhere on the board means a reward is waiting. Claimed keeps
	its silver pill because "already taken" is NOT visible anywhere else on the row — a full bar
	alone reads the same whether the money was collected or not.

	The state still EXISTS, with its colour and caption intact. Hiding is done at paint time on the
	instances, not by deleting the entry, so a row that needs the in-progress pill back is one flag.
	`Shown` hides the caption with the pill: `StatusLabel` is the pill's sibling in the row, not its
	child, so it does not inherit the button's visibility and would otherwise float on its own.

	CLAIMED IS NOW A FAREWELL RATHER THAN A RESTING STATE. A claimed card leaves the board (header
	note 6), so silver is on screen for the half second of the outro and never again — it is the
	receipt for the press, painted once by `_celebrate` and then folded away. It is still worth
	painting: a card that vanished the instant it was pressed would leave the player unsure which
	of the three they just took. ]]
local PILL_STATE = {
	InProgress = { Colour = "Blue", Caption = QuestConfig.InProgressText, Pressable = false, Shown = false },
	Claimable = { Colour = "Green", Caption = QuestConfig.ClaimText, Pressable = true, Shown = true },
	Claimed = { Colour = "Silver", Caption = QuestConfig.ClaimedText, Pressable = false, Shown = true },
}

--[[ What goes IN the reward chip.

	THREE PIECES, NOT ONE, and the split matters because only the middle one changes: `RewardFrame`
	is the 190x192 chip (the authored square), `RewardIcon` is what the reward IS, and `RewardCount`
	is the badge on the lower edge saying how much. The chip is a frame and stays a frame; the ICON
	is what a reward kind picks.

	It used to be the other way round — the chip itself was keyed by reward kind, and since cash was
	the only kind and no icon had been cut out of the mockup yet, "the icon" was the empty square you
	could see on screen. The banknote now sits inside it (`UIAssets.Page.CashIcon`), which is the
	same artwork the HUD cash counter wears.

	NO ICON IS A REAL ANSWER. An unknown reward kind draws the chip with nothing in it and its count
	underneath, which is what this page has always done and is still better than a broken image. ]]
local REWARD_ICON: { [string]: number } = {
	Cash = UIAssets.Page.CashIcon,
}

--[[ How much of the chip the icon fills, across its widest axis.

	0.62 rather than something nearer 1 because the chip is a FRAME with a drawn border and an inner
	inset — the artist's own square leaves about a fifth of its width to that edge on each side, so
	an icon any larger sits on the border instead of inside it. ]]
local REWARD_ICON_SCALE = 0.62

--[[ How tall the claim pill is, as a multiple of the progress bar it now stands beside.

	IT HAS TO BE A MULTIPLE OF THE BAR AND NOT ITS OWN AUTHORED HEIGHT, because at the size the
	artist drew it the pill does not fit on that line: 0.281 of the row centred on a bar whose
	centre sits 0.137 off the bottom edge runs off the card. So the pill is scaled, and the number
	is stated against the thing it has to sit next to rather than typed as a rect.

	1.25 rather than 1: exactly the bar's height reads as a second trough rather than as a button,
	and a quarter taller is enough to look pressable while still leaving the card the bottom margin
	the bar itself keeps. The pill art is aspect-locked, so this drives the WIDTH as well, and the
	caption inside it is scaled by the same factor. See `_relayoutRow`. ]]
local PILL_BAR_HEIGHT = 1.25

-- === Text ===================================================================
--[[ Non-breaking every space.

	`TextScaled` would rather wrap a label onto a second line than shrink it, and every string this
	page writes lands in a TextScaled box — a wrapped "IN-PROGRESS" or a two-line quest name is the
	one way this layout can look broken. `TextWrapped = false` and `MinTextSize` both fail silently
	here; NBSP is what actually works. See the fleet brief's house rules. ]]
local function oneLine(text: string): string
	return (string.gsub(text, " ", "\u{00A0}"))
end

--[[ One named element of a row, wherever the wrapping put it.

	EVERY ROW'S CONTENTS LIVE ONE LEVEL DOWN, inside a `Card` frame that `_newRow` builds around
	them, and this is the one function that has to know. The wrapping exists so the claim outro has
	something it can scale and fade as a single object: the row itself is owned by the
	`UIListLayout` (which writes its Position every frame and would fight any move) and its height
	is the thing that collapses, so the *contents* need a parent of their own that neither of those
	touches. The card is exactly the row's rect, so every authored scale coordinate inside it
	resolves to the same pixel it always did and `_relayoutRow`'s arithmetic is untouched.

	Falls back to the row itself so this is also correct on an unwrapped row — the TEMPLATE is one,
	and reading a part off it should not depend on knowing that. ]]
local function partOf(row: Instance, name: string): Instance?
	local card = row:FindFirstChild("Card")
	local found = card and card:FindFirstChild(name)
	return found or row:FindFirstChild(name)
end

--[[ What "invisible" is called on one instance, as a tween goal, or nil for something with no
	alpha to give.

	WRITTEN OUT PER CLASS rather than looped over a list of property names, because the four kinds
	of instance on a card do not agree on the word: an image fades on `ImageTransparency`, a label
	on `TextTransparency` and again on `TextStrokeTransparency`, and the kit's outlines are their
	own `UIStroke` instances with a third name. A card that faded only its images would leave the
	quest name hanging in mid-air over the row sliding up into it. ]]
local function fadeGoal(instance: Instance): { [string]: number }?
	if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		return { ImageTransparency = 1, BackgroundTransparency = 1 }
	elseif instance:IsA("TextLabel") or instance:IsA("TextButton") then
		return { TextTransparency = 1, TextStrokeTransparency = 1, BackgroundTransparency = 1 }
	elseif instance:IsA("UIStroke") then
		return { Transparency = 1 }
	elseif instance:IsA("GuiObject") then
		return { BackgroundTransparency = 1 }
	end
	return nil
end

--- A point on the quadratic curve through `from` and `to`, bent by `control`. The banknote's
--- flight path; see `_flyReward` for why it is a curve and not a line.
local function bezier(from: Vector2, control: Vector2, to: Vector2, t: number): Vector2
	local inv = 1 - t
	return from * (inv * inv) + control * (2 * inv * t) + to * (t * t)
end

--- `Time Left: 15h 15m 15s`, the mockup's own format. Clamped at zero, never negative.
local function clockText(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return oneLine(string.format(QuestConfig.TimeLeftFormat, `{seconds // 3600}h {(seconds % 3600) // 60}m {seconds % 60}s`))
end

--- The badge on the reward chip. Cash goes through the project's own formatter so a quest payout
--- reads the same as the number on a collect mat; anything else is a count.
local function rewardText(reward: Reward): string
	if reward.Kind == "Cash" then
		return QuestConfig.formatAmount(reward.Amount, "cash")
	end
	return `x{QuestConfig.formatCount(reward.Amount)}`
end

--[[ Which of the three states a quest is in.

	DERIVED, NOT STORED, and for the same reason the garage derives pending cash: a `Status` field
	alongside `Progress` and `Claimed` is a third thing that can disagree with the two that are
	actually true. A service sending one would be sending something this can already compute. ]]
local function statusOf(quest: Quest): string
	if quest.Claimed then
		return "Claimed"
	elseif quest.Progress >= quest.Target then
		return "Claimable"
	end
	return "InProgress"
end

-- === Bars ===================================================================
--[[ A bar's level, drawn as a step in a `UIGradient` on its fill rather than by resizing the fill.

	A FILL SHRUNK TO ITS LEVEL STOPS BEING A PILL once it is short. Both bars on this page are the
	same 9-sliced image, and a slice cannot draw its rounded caps in a box narrower than the caps
	are: at $48 of $10,000 what was left was a hard-edged sliver standing across the trough's
	rounded end.

	Held at full width and cut by transparency instead, the fill's art never changes size, so what
	is left at 3% is the left cap of the same pill, following the trough's curve. The price is the
	leading edge, which is FLAT at every level rather than rounded; the nitro and police bars
	already look that way.

	Same construction and same numbers as `DrivingHudController.cutAt`, which is where the width of
	the edge is argued for. ]]
local CUT_EDGE = 0.006
local CUT_EMPTY = NumberSequence.new(1)
local CUT_FULL = NumberSequence.new(0)

local function cutAt(shown: number): NumberSequence
	if shown <= CUT_EDGE then
		return CUT_EMPTY
	elseif shown >= 1 - CUT_EDGE then
		return CUT_FULL
	end
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(shown, 0),
		NumberSequenceKeypoint.new(shown + CUT_EDGE, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
end

--[[ The fill's cut, built on first use so the art in the place needs nothing new. An authored
	gradient is reused rather than joined, because a GuiObject only draws one. Rotation 0 is the
	default, and it runs left to right, which is the way both of these bars fill. ]]
local function cutOf(fill: Instance): UIGradient
	local cut = fill:FindFirstChildOfClass("UIGradient")
	if not cut then
		cut = Instance.new("UIGradient")
		cut.Name = "Cut"
		cut.Parent = fill
	end
	return cut :: UIGradient
end

local Page = {}
Page.__index = Page

function Page.new(UIController: UIControllerTypes.UIController)
	local self = setmetatable({}, Page)
	self.UIController = UIController

	local mainUI = UIController.PlayerGui:WaitForChild("MainUI")
	self.PageUI = mainUI:WaitForChild("Pages"):WaitForChild(PAGE_NAME)
	--[[ Kept because the claim's banknote flies OUT of this page and into the HUD's cash counter,
		and the two are separate branches of `MainUI`. Their common ancestor is the one coordinate
		space both rects can be expressed in without a single inset correction — see `_flyReward`. ]]
	self.MainUI = mainUI

	self.RowTemplate = self.PageUI:WaitForChild("QuestRow")
	self.TimerFill = self.PageUI:WaitForChild("BottomBarFill")
	self.TimerLabel = self.PageUI:WaitForChild("BottomBarLabel")
	self.ScrollBar = self.PageUI:WaitForChild("ScrollBar")

	local close = self.PageUI:WaitForChild("Close")
	close.MouseButton1Click:Connect(function()
		self.UIController:closePage(PAGE_NAME)
	end)

	self.Quests = {} :: { Quest } -- the whole board, claimed rows included
	self._shown = {} :: { Quest } -- what the list actually draws: unclaimed, plus anything leaving
	--[[ KEYED BY QUEST ID, not by position — header note 6. A row that survives a refresh is the
		same instance, and a row can never be handed a different quest than the one it was built
		for. ]]
	self._rows = {} :: { [string]: Frame }
	--[[ Quests whose card is mid-outro: still drawn, no longer repainted, and not yet destroyed.
		Set by `_repaint` when it spots a claim, cleared by the one function that destroys the
		row. ]]
	self._leaving = {} :: { [string]: boolean }
	--[[ What is currently ON SCREEN, as `[id] = wasClaimed`. The claim diff is a comparison against
		this and nothing else: a board is a snapshot, so "this quest just got claimed" is only
		answerable against the snapshot before it. Empty at construction, which is what makes the
		first board of a session animate nothing — a quest claimed yesterday is not news. ]]
	self._painted = {} :: { [string]: boolean }
	--[[ The clock starts on the answer this client can work out for itself, so the countdown is
		right from the first frame rather than sitting on a dead zero until the first board lands.
		The server sends the same number — see header note 3. ]]
	self._resetAt = QuestConfig.resetAt()
	self._period = QuestConfig.ResetPeriod
	-- Pixel metrics, filled by `_syncMetrics` once the page has been laid out. Zero until then, which
	-- is a list with no canvas rather than an error.
	self._rowHeight = 0
	self._rowGap = 0
	self._canvasHeight = 0

	self:_readAuthoredLayout()
	-- The countdown's fill sits at full width for good; `_updateTimer` moves its cut. See `cutAt`.
	self.TimerFill.Size = UDim2.fromScale(self._timerWidth, self.TimerFill.Size.Y.Scale)
	self._timerCut = cutOf(self.TimerFill)
	self:_buildList()

	return self
end

function Page:initialize()
	--[[ Painted before the page is ever opened, which is load-bearing rather than tidy: the
		controller preloads every ImageLabel and ImageButton under the page immediately after this
		returns, and it can only preload rows that exist. Built here, the first open is a finished
		screen; built on open, it is one assembling itself. ]]
	self:refresh()

	--[[ Repainted whenever a new board lands, which is the ONLY thing that changes what is drawn —
		a claim included. `QuestController` publishes this after storing the board, so by the time
		this runs `_fetch` already has the new one.

		Subscribed here rather than in `new` because the controller may not have started when pages
		are constructed; `initialize` runs after `Shard.start`, which is also why the refresh above
		is the first one that can actually reach the server. ]]
	Dispatcher:Subscribe(QuestConfig.StateEvent, function()
		self:refresh()
	end)
end

-- === Reading the authored art ===============================================
--[[ Turn the mockup into the handful of numbers the list needs. Header note 4: nothing below is a
	pixel rect typed in a second time — each one is measured off the art that is already there, so a
	nudge in the Explorer moves the list with it. ]]
function Page:_readAuthoredLayout()
	local page = self.PageUI
	local panel = page:WaitForChild("Panel")
	local titleBar = page:WaitForChild("TitleBar")
	local template = self.RowTemplate

	-- The gap the artist left between the title bar and the first row. Reused as the gap BETWEEN
	-- rows and as the bottom margin inside the panel, so the list has one rhythm and it is the
	-- mockup's.
	-- EDGES THROUGHOUT, never a raw Position: everything on this page is centre-anchored like the
	-- rest of the kit, so `Position` is a centre and the arithmetic below is all about edges. See
	-- UIGeom.
	local templateLeft, templateTop = UIGeom.topLeft(template)
	self._gap = templateTop - UIGeom.bottom(titleBar)

	-- The content well: the authored row's own left edge, top edge and width, running down to that
	-- same gap above the bottom of the panel.
	local panelBottom = UIGeom.bottom(panel)
	self._well = {
		Left = templateLeft,
		Top = templateTop,
		Width = template.Size.X.Scale,
		Height = (panelBottom - self._gap) - templateTop,
	}
	self._rowScale = template.Size.Y.Scale

	-- The scroll indicator: its authored rect gives the top of its travel and its width. It runs
	-- down to the bottom of the well, and its LENGTH becomes the visible fraction of the list.
	local barLeft, barTop = UIGeom.topLeft(self.ScrollBar)
	self._barX = barLeft
	self._barWidth = self.ScrollBar.Size.X.Scale
	self._barTop = barTop
	self._barTravel = (self._well.Top + self._well.Height) - self._barTop

	--[[ How wide the countdown's fill is at 100%.

		The fill is inset from its track by the same margin it starts at, so full width is the track
		less that inset twice. Measured rather than assumed, because the two bars on this page have
		different insets and eyeballing one of them is how a bar ends up overshooting its own
		rounded cap by a few pixels at full.

		THE ROW BARS USED TO BE DERIVED HERE TOO and no longer can be: `_relayoutRow` shortens a
		row's track to make room for the claim pill, so the answer is a property of the ROW rather
		than of the template. `setRowProgress` works it out from the row it was handed, by the same
		arithmetic. ]]
	self._timerWidth = 1 - 2 * UIGeom.left(self.TimerFill)
end

-- === The list ===============================================================
function Page:_buildList()
	local list = Instance.new("ScrollingFrame")
	list.Name = "QuestList"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ClipsDescendants = true
	list.Position = UDim2.fromScale(self._well.Left, self._well.Top)
	list.Size = UDim2.fromScale(self._well.Width, self._well.Height)
	-- The well IS where the authored row sat, so it inherits the row's own layer.
	list.ZIndex = self.RowTemplate.ZIndex
	list.Active = true
	list.Selectable = false
	list.ScrollingEnabled = true
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ElasticBehavior = Enum.ElasticBehavior.Never
	-- Header note 2: the canvas is computed, never automatic.
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.None
	-- Roblox's own scrollbar is off because the kit already drew one: `ScrollBar` is the indicator.
	-- Zero thickness also keeps `AbsoluteWindowSize` equal to the frame, which the metrics assume.
	list.ScrollBarThickness = 0
	list.ScrollBarImageTransparency = 1

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = list

	list.Parent = self.PageUI
	self.List = list
	self.Layout = layout

	-- The authored row is the template. It is art, not the first row.
	self.RowTemplate.Visible = false

	list:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:_updateScrollIndicator()
	end)
	-- Rows are sized in pixels, so a window resize has to re-derive them.
	self.PageUI:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_syncMetrics()
	end)

	self:_buildEmptyLabel()
end

--[[ The "nothing today" line, over the middle of the well.

	BUILT IN CODE BECAUSE THE MOCKUP HAS NO EMPTY STATE — it was drawn with a full board, which is
	what a normal day looks like, so there is no authored art to switch on. Every property it does
	not need to invent is copied off the row template's own name label, so it is in the kit's font
	and colour without a second set of numbers to keep in step with the artist.

	IT IS NOW A LINE A NORMAL SESSION REACHES, which it was not when it was written: a claimed card
	leaves the board (header note 6), so a player who clears all three ends the day looking at this
	label rather than at a list. That is why it carries two strings and a fade — see
	`_updateEmptyState`. The other two ways in are still `QuestConfig.Enabled` off on the server and
	a client told there are no quests today; a client that has not heard YET gets no message at
	all. ]]
function Page:_buildEmptyLabel()
	local label = Instance.new("TextLabel")
	label.Name = "QuestEmpty"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(self._well.Left, self._well.Top)
	label.Size = UDim2.fromScale(self._well.Width, self._well.Height)
	label.ZIndex = self.RowTemplate.ZIndex
	label.TextScaled = false
	--[[ WRAPPED, and it is the one label on this page that is. Everything else here is `TextScaled`
		in a box the artist sized, which is why every other string goes through `oneLine` — a
		TextScaled label answers a string that does not fit by wrapping instead of shrinking, and a
		two-line quest name is how this layout looks broken.

		This label is the opposite case on both counts: its size is fixed by the line below rather
		than by its box, and the two things it says are different lengths — "No quests today" is
		three words and the all-claimed line is six. Unwrapped, the longer one runs off both edges
		of the panel; wrapped, it takes a second line in a well that is two and a half rows tall.
		So it wraps, and it is NOT put through `oneLine`. ]]
	label.TextWrapped = true
	label.Text = QuestConfig.EmptyText
	label.Visible = false

	--[[ Sized off a QUEST NAME, which is the whole trick here and the reason this is not
		`TextScaled`.

		TextScaled in a box the height of the well renders one line of copy at the height of the
		well, which is a headline several times the size of the rows it replaces. But a fixed
		fraction of the well is no better: the first draft took a third of a row's height, which
		was tuned against "No quests today" and rendered the longer all-claimed line as three
		lines of 43px filling the panel like an error page.

		So the yardstick is the thing this label is standing in for — the authored `QuestName` box,
		scaled through the row exactly as `_syncMetrics` scales a row through the page. The message
		then lands at the size of a quest title, reads as one of the list's own lines rather than as
		an announcement, and holds that relationship at every resolution. ]]
	local source = self.RowTemplate:FindFirstChild("QuestName")
	local textScale = self._rowScale / 3
	if source and source:IsA("TextLabel") then
		label.Font = source.Font
		label.TextColor3 = source.TextColor3
		label.TextTransparency = source.TextTransparency
		label.TextStrokeColor3 = source.TextStrokeColor3
		label.TextStrokeTransparency = source.TextStrokeTransparency
		textScale = self._rowScale * source.Size.Y.Scale
	end
	-- What "opaque" is for this label, remembered so the fade-in has somewhere to land. Read off
	-- the art rather than assumed to be zero, for the same reason everything else here is.
	self._emptyAlpha = { Text = label.TextTransparency, Stroke = label.TextStrokeTransparency }

	local function resize()
		label.TextSize = math.max(12, math.round(textScale * self.PageUI.AbsoluteSize.Y))
	end
	resize()
	self.PageUI:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)

	label.Parent = self.PageUI
	self.EmptyLabel = label
end

--[[ The line under an empty list, and WHICH line.

	NIL AND EMPTY ARE DIFFERENT. No board at all is the first moments of a session, before the
	server's reply has arrived — that draws an empty well and NO message, because "no quests today"
	is a claim we cannot make yet and would be wrong a fraction of a second later. An empty `quests`
	list IS the server saying so, and that gets the line.

	AND "EMPTY" IS NOW TWO DIFFERENT FACTS. A board with nothing on it is the server having nothing
	to give; a board whose every quest has been claimed is the player having taken all of it, and
	that is the one a normal session ends on. They read completely differently to somebody looking
	at the screen, so they are two strings — see `QuestConfig.AllClaimedText`.

	IT FADES IN RATHER THAN APPEARING, and only when it was not already there. The last card folds
	away over about a fifth of a second and a message that hard-cuts into the space underneath it
	arrives before the card has finished leaving, which reads as the label having been there all
	along. Fading it means the board empties and THEN says so. ]]
function Page:_updateEmptyState()
	local label = self.EmptyLabel
	if not label then
		return
	end

	local controller = Shard.get("QuestController")
	local board = controller and controller:board()
	local show = board ~= nil and #self._shown == 0
	label.Text = if #self.Quests > 0 then QuestConfig.AllClaimedText else QuestConfig.EmptyText

	if show == label.Visible then
		return
	end

	if self._emptyTween then
		self._emptyTween:Cancel()
		self._emptyTween = nil
	end

	local alpha = self._emptyAlpha or { Text = 0, Stroke = 0 }
	if not show then
		label.Visible = false
		return
	end

	label.TextTransparency = 1
	label.TextStrokeTransparency = 1
	label.Visible = true
	self._emptyTween = TweenService:Create(
		label,
		TweenInfo.new(QuestConfig.ClaimEffect.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = alpha.Text, TextStrokeTransparency = alpha.Stroke }
	)
	self._emptyTween:Play()
end

--[[ Convert the authored scale layout into the pixel metrics the list runs on. Cheap and idempotent,
	so it is safe on every resize. Returns false while the page has not been laid out yet — a hidden
	page still resolves its AbsoluteSize, but there is a frame or two at boot before it does. ]]
function Page:_syncMetrics(): boolean
	local pageHeight = self.PageUI.AbsoluteSize.Y
	if pageHeight <= 0 then
		return false
	end

	self._rowHeight = math.round(self._rowScale * pageHeight)
	self._rowGap = math.round(self._gap * pageHeight)
	self.Layout.Padding = UDim.new(0, self._rowGap)
	for _, row in self._rows do
		-- A folding card owns its own height until it is gone (header note 6). Resizing it here —
		-- which a window resize would do — snaps it back to full height mid-collapse.
		if not row:GetAttribute("Leaving") then
			row.Size = UDim2.new(1, 0, 0, self._rowHeight)
		end
	end

	self:_updateCanvas()
	return true
end

--[[ The canvas is the rows plus the gaps between them. Computing it is what keeps the last row
	reachable at full scroll — header note 2, and the reason `AutomaticCanvasSize` is off.

	SUMMED OFF THE ROWS RATHER THAN `count * rowHeight`, which it used to be, because a folding card
	is a row whose height is somewhere between full and zero for a fifth of a second. Multiplying by
	the nominal height there leaves the canvas a whole row taller than its contents while the list
	closes up, which is a scrollbar claiming there is something below the last quest. The outro
	drives this every frame while it folds. ]]
function Page:_updateCanvas()
	local total, count = 0, 0
	for _, row in self._rows do
		total += row.Size.Y.Offset
		count += 1
	end

	self._canvasHeight = if count > 0 then total + (count - 1) * self._rowGap else 0
	self.List.CanvasSize = UDim2.fromOffset(0, self._canvasHeight)
	self:_updateScrollIndicator()
end

--[[ Drive the authored `ScrollBar` image from the scroll position: it is the thumb, so its length is
	the fraction of the list on screen and its position is how far down that window has travelled.

	It is an INDICATOR, not a grab handle — the wheel and a touch drag scroll the list. It is hidden
	outright when everything fits, because a full-length bar beside a list that does not scroll is a
	bar implying there is more below. ]]
function Page:_updateScrollIndicator()
	local windowHeight = self._well.Height * self.PageUI.AbsoluteSize.Y
	local overflow = self._canvasHeight - windowHeight

	if windowHeight <= 0 or overflow <= 1 then
		self.ScrollBar.Visible = false
		return
	end

	self.ScrollBar.Visible = true
	local length = self._barTravel * (windowHeight / self._canvasHeight)
	local at = math.clamp(self.List.CanvasPosition.Y / overflow, 0, 1)
	-- Size first: `place` corrects against the bar's current height, so a thumb resized afterwards
	-- would be positioned by the old one.
	self.ScrollBar.Size = UDim2.fromScale(self._barWidth, length)
	UIGeom.place(self.ScrollBar, self._barX, self._barTop + (self._barTravel - length) * at)
end

-- === Rows ===================================================================
--[[ Where everything on a row sits, and the only thing on this page that moves an authored rect.

	THE MOCKUP PUT THE CLAIM PILL UNDER THE QUEST NAME, on the left, with the reward chip alone on
	the far right and the whole middle of the row empty. That reads backwards. The pill is the one
	thing on a quest row a player can DO anything to, and it sat where the eye starts rather than
	where it finishes, in the same column as the other quest titles.

	IT NOW SITS ON THE PROGRESS BAR'S LINE, at the row's right edge, and the bar is shortened to
	make room for it. That is the owner's layout and it is the better one: the bar and the button
	are the same thought, "how far along, and collect it", so they belong on the same line, and it
	leaves the whole upper band to the two things that describe the quest. Nothing else has to move
	for it. The reward chip goes back to exactly where the artist drew it, on the band's right
	margin, directly above the pill, and the name takes everything to the left of it.

	    mockup                          before this               now
	    +----------------------+        +----------------------+  +----------------------+
	    | Quest name     [$]   |        |                      |  | Quest name     [$]   |
	    | [ CLAIM ]            |        | Quest name [$][CLAIM]|  |                      |
	    | ##--- Progress: 3/5  |        | ##--- Progress: 3/5  |  | ##--- 3/5  [ CLAIM ] |
	    +----------------------+        +----------------------+  +----------------------+

	THE BAR IS THE SAME LENGTH ON EVERY ROW, whether that row has a pill on it or not. An
	in-progress quest draws no pill at all (see `PILL_STATE`), so the alternative was a bar that
	grew when there was no button beside it, which puts two different bar lengths on one board and
	makes the same percentage look like two different amounts of progress. One length reads as a
	column; the trough has its own rounded cap, so it plainly ends where it is meant to.

	IT IS ARITHMETIC ON THE ART, NOT A SECOND SET OF COORDINATES, which is header note 4 kept
	rather than broken: there is no rect typed in below, only edges measured off the authored row
	and the layout stated as the relationships between them. Re-author the row's margins and this
	moves with them. Re-author where the PILL sits and nothing changes, because where the pill sits
	is one of the things this decides. That is the point: the template is hidden art (header note
	4), and a layout nobody can see is a layout nobody can keep in step.

	IT RUNS ON A PRISTINE CLONE and therefore never has to be idempotent: `_newRow` clones
	`RowTemplate`, and nothing anywhere mutates the template itself.

	ONE AUTHORED MARGIN IS THE WHOLE RHYTHM. The gap the artist left to the left of the quest name
	is reused as the gap between the bar and the pill and, doubled, as the gutter that holds the
	name off the reward chip, so the row has one horizontal spacing and it is the mockup's own.
	That is the same way `_readAuthoredLayout` makes one authored gap the rhythm of the list. ]]
function Page:_relayoutRow(row: Frame)
	local name = partOf(row, "QuestName")
	local pill = partOf(row, "StatusButton")
	local caption = partOf(row, "StatusLabel")
	local chip = partOf(row, "RewardFrame")
	local badge = partOf(row, "RewardCount")
	local track = partOf(row, "BarTrack")
	local progress = partOf(row, "BarLabel")
	if not (name and pill and chip and track) then
		-- A re-authored row missing one of them is left exactly as it was drawn, which is a
		-- readable row rather than a half-moved one.
		return
	end

	--[[ The three edges everything below is hung off, all of them the artist's own: the quest
		name's left edge, the reward chip's right edge, and the centre line of the progress bar. ]]
	local margin = UIGeom.left(name)
	local bandRight = UIGeom.right(chip)
	local barCentre = UIGeom.top(track) + track.Size.Y.Scale / 2

	--[[ The pill, scaled to the bar it now stands beside and pushed to the band's right margin so
		it is squarely under the reward chip.

		THE SCALE IS APPLIED TO BOTH AXES AND TO THE CAPTION WITH IT. The pill art is aspect-locked
		(`UIAssets` says why at length), so a height decides a width; and `StatusLabel` is the
		pill's SIBLING rather than its child (header note 5), so it neither shrinks nor moves on its
		own and would otherwise be left as a full-size word across a smaller button. Its offset from
		the pill's centre is carried through the same scale, which keeps whatever optical offset
		inside the pill the artist drew. ]]
	local scale = (track.Size.Y.Scale * PILL_BAR_HEIGHT) / pill.Size.Y.Scale
	local pillWidth, pillHeight = pill.Size.X.Scale * scale, pill.Size.Y.Scale * scale
	local pillCentreX, pillCentreY = bandRight - pillWidth / 2, barCentre

	if caption then
		local captionX, captionY = UIGeom.centre(caption)
		local oldX, oldY = UIGeom.centre(pill)
		caption.Size = UDim2.fromScale(caption.Size.X.Scale * scale, caption.Size.Y.Scale * scale)
		UIGeom.place(
			caption,
			pillCentreX + (captionX - oldX) * scale - caption.Size.X.Scale / 2,
			pillCentreY + (captionY - oldY) * scale - caption.Size.Y.Scale / 2
		)
	end

	pill.Size = UDim2.fromScale(pillWidth, pillHeight)
	UIGeom.place(pill, pillCentreX - pillWidth / 2, pillCentreY - pillHeight / 2)

	--[[ The bar, shortened to stop one margin short of the pill. Its LEFT edge and its height are
		the artist's and are not touched, so the trough still starts where it always did and still
		sits on the line the row was drawn around; only its right end is now decided by what has to
		stand beside it. `BarFill` is left alone here because `setRowProgress` sizes it from the
		track every time it paints. ]]
	local trackWidth = math.max((bandRight - pillWidth - margin) - UIGeom.left(track), 0)
	local trackLeft, trackTop = UIGeom.topLeft(track)
	track.Size = UDim2.fromScale(trackWidth, track.Size.Y.Scale)
	UIGeom.place(track, trackLeft, trackTop)

	--[[ The progress caption, taking the shortened track's rect outright.

		TWO FIXES IN ONE LINE. It has to follow the track, or a bar that shortened would leave its
		own caption centred on where the bar used to end. And the box wanted widening anyway: the
		mockup sized it for "Progress: 10/15", a cash quest writes "Progress: $4,200/$10,000" into
		it, and `TextScaled` answers a string that does not fit by shrinking it, so a cash row
		rendered its caption at under half the height of a count row directly above it. The HEIGHT
		is deliberately untouched, since that is what caps a short caption: "Progress: 3/3" does not
		grow to fill the new room and the two rows land at the same size rather than at two new
		ones. ]]
	if progress then
		progress.Size = UDim2.fromScale(trackWidth, progress.Size.Y.Scale)
		UIGeom.place(progress, trackLeft, UIGeom.top(progress))
	end

	--[[ The count badge, widened to the chip it hangs under.

		A SEPARATE FIX AND AN OLDER ONE, kept because it is the same trap as the caption above: the
		badge box in the mockup is sized for "x25", a cash amount is wider than that, and a
		TextScaled label in an 83px box renders it at about a third of the height the artist drew.
		Widening to the chip keeps the artist's centre and is measured off the chip, so it tracks
		the art rather than a number typed here. The CHIP itself does not move at all. ]]
	if badge then
		local badgeLeft, badgeTop = UIGeom.topLeft(badge)
		local centre = badgeLeft + badge.Size.X.Scale / 2
		badge.Size = UDim2.fromScale(chip.Size.X.Scale, badge.Size.Y.Scale)
		UIGeom.place(badge, centre - chip.Size.X.Scale / 2, badgeTop)
	end

	--[[ The name takes the rest of the upper band, on the chip's centre line.

		BOTH HALVES OF THAT ARE THE POINT. It gains everything the pill used to stand in, which is
		what stops a long quest title being shrunk by `TextScaled` into something a third the height
		of its neighbours. It is `TextXAlignment.Left` in the mockup, so a short name still starts
		exactly where it always did and only a long one uses the new room. And it drops from the top
		corner to the chip's line, so the band is one horizontal line of content rather than a title
		in a corner with the reward alongside nothing.

		SIZE BEFORE `place`, which `UIGeom` is explicit about: `place` corrects against the rect's
		CURRENT width, so a resize afterwards would be positioned by the old one. ]]
	local _, bandCentre = UIGeom.centre(chip)
	local nameHeight = name.Size.Y.Scale
	name.Size = UDim2.fromScale(math.max((UIGeom.left(chip) - 2 * margin) - margin, 0), nameHeight)
	UIGeom.place(name, margin, bandCentre - nameHeight / 2)
end

--[[ Wrap a fresh clone's contents in a `Card` frame that fills the row.

	THE ROW AND THE CARD ARE TWO DIFFERENT THINGS AND THE OUTRO NEEDS BOTH. The row is a slot in the
	`UIListLayout`: the layout writes its Position every frame, so nothing may move it, and its
	HEIGHT is the thing that folds so the quests below slide up into the space. The card is what the
	player sees: it has to be able to punch, shrink and fade as one object, which means one parent
	with one `UIScale` over the lot.

	It costs the layout nothing. The card is the row's own rect (centred, full size, no background),
	so every authored scale coordinate inside it resolves against exactly the box it always did —
	`_relayoutRow` is arithmetic on those same rects and does not know this happened, which is why
	`partOf` exists.

	The `UIScale` is built here and left at 1, so the outro never has to check for one. ]]
local function wrapCard(row: Frame): Frame
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(1, 1)
	-- Sibling ZIndexBehavior: the card takes the row's layer and its children keep their order
	-- inside it, so nothing about the drawn stack changes.
	card.ZIndex = row.ZIndex

	-- `GetChildren` is a snapshot, so reparenting as we walk it is safe.
	for _, child in row:GetChildren() do
		child.Parent = card
	end
	card.Parent = row

	local scale = Instance.new("UIScale")
	scale.Name = "CardScale"
	scale.Parent = card
	return card
end

--- One clone of the template, wired and parented. Sizing and painting are somebody else's job.
function Page:_newRow(id: string): Frame
	local row = self.RowTemplate:Clone()
	row.Name = `QuestRow_{id}`
	row.Visible = true
	-- The list is exactly the authored row's width, so scale 1 across is the mockup's width; the
	-- UIListLayout owns Y and the height comes from `_syncMetrics`.
	row.Position = UDim2.new()
	row.Size = UDim2.new(1, 0, 0, self._rowHeight)

	-- Everything the row draws moves one level down, so the claim outro has an object to animate.
	wrapCard(row)

	-- Where the name, the reward chip and the claim pill end up. See `_relayoutRow`.
	self:_relayoutRow(row)
	local chip = partOf(row, "RewardFrame")

	--[[ The reward's icon, centred in its chip.

		BUILT HERE RATHER THAN AUTHORED, because the mockup never drew one — the chip is empty art
		in the PSD and the banknote had to be cut out of the cash counter's own group to exist at
		all. A row that gains an authored `RewardIcon` one day is still fine: this finds it first
		and only builds one when there is none.

		A `UIAspectRatioConstraint` and NOT a hand-computed size. The icon is 124x74 inside a chip
		that is square, so its scale-Y within the row is a different number from its scale-X and
		both move with the window; the constraint is the one thing that keeps a banknote a banknote
		at every resolution. Its box is `fromScale(s, s)` and deliberately not a zero width — a zero
		on either axis collapses the whole element to 0x0 under the default `FitWithinMaxSize`,
		which is a trap this project has already fallen into once. ]]
	if chip then
		local icon = chip:FindFirstChild("RewardIcon")
		if not icon then
			icon = Instance.new("ImageLabel")
			icon.Name = "RewardIcon"
			icon.BackgroundTransparency = 1
			icon.BorderSizePixel = 0
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
			icon.Size = UDim2.fromScale(REWARD_ICON_SCALE, REWARD_ICON_SCALE)
			-- Stretch, never Slice: this is a fixed box that shrinks uniformly from its texture.
			-- Only `BarFill` and the ScrollBar thumb change aspect at runtime. See `setRowProgress`.
			icon.ScaleType = Enum.ScaleType.Stretch
			icon.ZIndex = chip.ZIndex + 1

			local ratio = Instance.new("UIAspectRatioConstraint")
			local size = UIAssets.Size.CashIcon
			ratio.AspectRatio = size.X / size.Y
			ratio.DominantAxis = Enum.DominantAxis.Width
			ratio.Parent = icon

			icon.Parent = chip
		end
	end

	-- The row is stamped with its quest id on every paint, so the handler reads the id at press time
	-- rather than closing over an index that a refresh can move.
	local pill = partOf(row, "StatusButton")
	if pill then
		pill.MouseButton1Click:Connect(function()
			self:_claim(row:GetAttribute("QuestId"))
		end)
	end

	row.Parent = self.List
	return row
end

--[[ Bring the row pool into line with `_shown`, then paint it.

	KEYED BY QUEST ID — header note 6. Rows are REUSED rather than rebuilt, which a rebuild on every
	open would ruin twice over: it would churn the `UIButton` observers, and it would destroy the
	very button whose click handler is running when a claim repaints its own row. Keying by id
	rather than by position is what makes that reuse safe now that cards leave the middle of the
	list: a positional pool hands row 2 to a different quest the moment row 1 goes, so the card
	folding away would be repainted as its neighbour halfway through the fold.

	A LEAVING ROW IS IN `_shown` AND IS NOT REPAINTED. It has to stay in the list or it would be
	swept away by the loop below before its outro had a frame to run; it must not be repainted or
	the claimed pill and the flown banknote would both come back. `_celebrate` paints it once, and
	that is the last paint it ever gets. ]]
function Page:_renderRows()
	local shown = self._shown

	local wanted: { [string]: boolean } = {}
	for index, quest in shown do
		wanted[quest.Id] = true
		local row = self._rows[quest.Id]
		if not row then
			row = self:_newRow(quest.Id)
			self._rows[quest.Id] = row
		end
		row.LayoutOrder = index
	end

	for id, row in self._rows do
		if not wanted[id] then
			row:Destroy()
			self._rows[id] = nil
			--[[ The one path that takes a row from under a running outro: the board rolled over at
				midnight and the quest it was folding is not on today's. `_outroRow` bails when it
				finds its row gone, so this is the only place left that can drop the flag — and a
				flag left set would hold a phantom quest in `_shown` on whatever future day drew
				that id again. ]]
			self._leaving[id] = nil
		end
	end

	if not self:_syncMetrics() then
		-- Not laid out yet, so there are no pixel metrics; the canvas still has to match the pool.
		self:_updateCanvas()
	end

	for _, quest in shown do
		local row = self._rows[quest.Id]
		if row and not self._leaving[quest.Id] then
			self:_paintRow(row, quest)
		end
	end
end

--- Everything one row shows, from one quest. Safe to call on a row that is already painted.
function Page:_paintRow(row: Frame, quest: Quest)
	row:SetAttribute("QuestId", quest.Id)

	local name = partOf(row, "QuestName")
	if name then
		name.Text = oneLine(quest.Name)
	end

	--[[ The pill, its caption, and whether either is on screen at all. See `PILL_STATE`: an
		in-progress quest draws no pill, so both instances go invisible together. The art and the
		caption are still written on a hidden pill — a repaint into a shown state is then one
		`Visible` flip with nothing stale behind it. ]]
	local state = PILL_STATE[statusOf(quest)]
	local pill = partOf(row, "StatusButton")
	if pill then
		local art = UIAssets.Pill[state.Colour]
		pill.Image = UIAssets.url(art.Idle)
		pill.HoverImage = UIAssets.url(art.Hover)
		pill.PressedImage = UIAssets.url(art.Pressed)
		pill.Interactable = state.Pressable
		pill.Visible = state.Shown
	end

	local caption = partOf(row, "StatusLabel")
	if caption then
		caption.Text = oneLine(state.Caption)
		caption.Visible = state.Shown
	end

	--[[ The chip keeps its authored frame; only what is INSIDE it depends on the reward. An icon
		this page has no art for is left blank rather than guessed at, so the chip and its count
		still read correctly. ]]
	local chip = partOf(row, "RewardFrame")
	local icon = chip and chip:FindFirstChild("RewardIcon")
	if icon then
		local art = REWARD_ICON[quest.Reward.Kind]
		icon.Image = if art then UIAssets.url(art) else ""
		icon.Visible = art ~= nil
	end

	local badge = partOf(row, "RewardCount")
	if badge then
		badge.Text = oneLine(rewardText(quest.Reward))
	end

	self:setRowProgress(row, quest.Progress, quest.Target, quest.Unit)
end

--[[ Fill one row's progress bar and caption. `row` is a clone of `RowTemplate`.

	`unit` is how the two numbers are WRITTEN and has nothing to do with the bar — a cash quest reads
	"Progress: $4,200/$10,000" and a count reads "Progress: 3/5", because a five-digit stud count
	with no separators is a number nobody parses at a glance. See `QuestConfig.formatAmount`. ]]
function Page:setRowProgress(row: Instance, done: number, target: number, unit: string?)
	local ratio = target > 0 and math.clamp(done / target, 0, 1) or 0

	local fill = partOf(row, "BarFill")
	if fill then
		--[[ Always FULL WIDTH, with the level drawn by `cutAt` in the fill's own gradient. Resized
			to the level instead, a slice has no room for its caps at the low end and the fill turns
			into a square sliver. See `cutAt`.

			`BarFill` IS ONE OF ONLY TWO THINGS IN THIS UI THAT SHOULD BE SLICED — it and the
			ScrollBar thumb are the only elements whose ASPECT is decided at runtime (this one's by
			the shortened track, see `_relayoutRow`), which is the one case 9-slice is for. Every
			other image here is a fixed box that shrinks uniformly from its texture, and slicing
			those pins the corners at 1:1 texture pixels and inflates them 2-5x; `Stretch`
			reproduces the artist's proportion exactly. 27 instances were moved back to Stretch on
			2026-08-02 for that reason, so a sliced-looking neighbour is not a precedent to copy.

			Two bugs had to be fixed before this bar could keep its caps, and the first hid the
			second: it was authored `ScaleType = Stretch`, so its `SliceCenter` was ignored outright
			and the whole image squashed to a hard-edged rectangle at low progress. Setting Slice
			then exposed the real one — the rect was in PSD pixels, but Roblox had downscaled the
			1172px art to 1012 on upload (it caps at 1024), so the rect's far edge pointed off the
			image and only the near cap survived. See `UIAssets.Size`.

			ScaleType and SliceCenter are authored in the place, not set here, so a re-authored row
			has to carry both. ]]
		--[[ FULL WIDTH IS MEASURED OFF THIS ROW, not off the template, because `_relayoutRow`
			shortens the track to make room for the claim pill and the fill has to stop where the
			trough does. The inset is the same on both ends, so full is the track less it twice. ]]
		local track = partOf(row, "BarTrack")
		local full = if track then track.Size.X.Scale - 2 * (UIGeom.left(fill) - UIGeom.left(track)) else 0
		fill.Size = UDim2.fromScale(full, fill.Size.Y.Scale)
		cutOf(fill).Transparency = cutAt(ratio)
	end

	local label = partOf(row, "BarLabel")
	if label then
		label.Text = oneLine(string.format(
			QuestConfig.ProgressFormat,
			QuestConfig.formatAmount(done, unit),
			QuestConfig.formatAmount(target, unit)
		))
	end
end

-- === The countdown ==========================================================
--[[ Header note 3: this reads a clock, it does not run one.

	THE ZERO BRANCH IS THE ROLLOVER, and it is the one thing on this page that asks the server for
	something on its own. A player sitting on the board at midnight has a deadline that has passed;
	`_askServer` re-pings, `QuestService._roll` notices the day has turned and wipes the board, and
	the reply repaints these rows through the state event. Until that reply lands, `_fetch` falls
	back to the client's own `QuestConfig.resetAt()`, so the clock restarts at a full day
	immediately rather than sitting on a dead zero waiting for a round trip. ]]
function Page:_updateTimer()
	local remaining = self._resetAt - os.time()
	if remaining <= 0 then
		self:_askServer()
		-- `_repaint` and not `refresh`: refresh ends by calling this, and a countdown that repaints
		-- itself is a loop.
		self:_repaint()
		remaining = math.max(0, self._resetAt - os.time())
	end

	self.TimerLabel.Text = clockText(remaining)

	-- The bar drains: it is time LEFT, which is also how the mockup drew it (15h15m of a day, at
	-- about two thirds full).
	local ratio = self._period > 0 and math.clamp(remaining / self._period, 0, 1) or 0
	self._timerCut.Transparency = cutAt(ratio)
end

-- === Data ===================================================================
--[[ The seam. Everything above is fed by this and knows nothing else about where quests come from.

	It reads whatever board `QuestController` is currently holding — no remote is fired here and
	nothing yields, so it is safe on a Heartbeat tick and safe before the controller exists.

	NO BOARD YET IS A REAL STATE, not an error: this runs once during page construction, which is
	before the first `QuestState` can possibly have arrived. It answers an empty list and the
	client's own deadline, which draws an empty well under a correct clock — and the state event
	repaints it the moment the server's board lands. See header note 3 for why that deadline is the
	same number the server would have sent. ]]
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

--[[ Which of the board's quests the list actually draws: everything unclaimed, plus whatever is
	still folding itself away.

	IN THE BOARD'S OWN ORDER. Filtering preserves it, and the board arrives sorted by id
	(`QuestConfig.dailySet`), so a card leaving does not reshuffle the two beside it — they close
	up, which is the only movement the eye should have to follow. ]]
function Page:_visibleQuests(): { Quest }
	local shown = {}
	for _, quest in self.Quests do
		if not quest.Claimed or self._leaving[quest.Id] then
			table.insert(shown, quest)
		end
	end
	return shown
end

--[[ Take the board, work out what just happened to it, and draw the answer.

	THE DIFF IS THE WHOLE POINT OF THIS FUNCTION and it is three lines: a quest that this page was
	drawing as unclaimed, and which the board now says is claimed, was just paid for. That is the
	only thing that starts a celebration — header note 1. It cannot fire for a claim the server
	refused (the board comes back unchanged), it cannot fire twice for one claim (`_painted` is
	rewritten before anything animates), and it cannot fire for a quest claimed in an earlier
	session (`_painted` starts empty, so the first board of a session is news about nothing).

	THE ANIMATION IS SKIPPED WHEN NOBODY IS LOOKING. `refresh` runs on every state event, including
	ones that land while the page is shut, and a card that folded away unwatched would just be a
	quest that had vanished by the time the player next opened the screen. So a claim that arrives
	off-screen takes the row out with no ceremony, which is exactly what the list looks like on a
	fresh open anyway. ]]
function Page:_repaint()
	local previous = self._painted
	self.Quests, self._resetAt, self._period = self:_fetch()

	local celebrating: { Quest } = {}
	local watching = self.PageUI.Visible
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

	-- After the render, because a celebration needs the row it is celebrating to exist.
	for _, quest in celebrating do
		self:_celebrate(quest)
	end
end

--- Pull the set and repaint the whole page from it.
function Page:refresh()
	self:_repaint()
	self:_updateTimer()
end

-- === Claiming ===============================================================
--[[ What a claim looks like: the banknote leaves the chip and flies to the cash counter, the card
	says CLAIMED once, and then it folds away and takes its row with it.

	FIRED BY THE BOARD, NEVER BY THE PRESS (header note 1), so everything below is downstream of
	money the server has already paid. Nothing here can fail in a way that costs anybody a dollar,
	which is why none of it is guarded beyond "is the instance still there".

	THE ROW IS PAINTED ONE LAST TIME, first, before anything moves. The pill goes silver and reads
	CLAIMED for the length of the outro, which is the receipt for the press — a card that vanished
	the instant it was pressed leaves the player unsure which of the three they just took. It is the
	last paint that row ever gets: `_renderRows` skips it from here on. ]]
function Page:_celebrate(quest: Quest)
	local row = self._rows[quest.Id]
	if not row then
		-- Nothing to animate, so nothing owns the id. Dropping the flag here is what stops a quest
		-- with no row sticking in `_shown` forever.
		self._leaving[quest.Id] = nil
		return
	end

	self:_paintRow(row, quest)
	self:_flyReward(row, quest)
	self:_outroRow(row, quest.Id)
end

--[[ Where the money is going: the HUD's cash pill, bottom left.

	FOUND EACH TIME RATHER THAN CACHED, and not for tidiness — `GarageHudController` hides this
	exact instance during a race, and a claim with the counter off screen should send its banknote
	nowhere rather than into a corner where there is nothing to land on. Absent art answers nil and
	the flight is skipped, which is a claim with no flourish rather than a broken one. ]]
function Page:_cashCounter(): GuiObject?
	local hud = self.MainUI and self.MainUI:FindFirstChild("HUD")
	local cash = hud and hud:FindFirstChild("Cash")
	if cash and cash:IsA("GuiObject") and cash.Visible then
		return cash
	end
	return nil
end

--[[ The banknote's flight, chip to counter.

	ONE NOTE, NOT A SPRAY. The house note on effect intensity is that a reaction should be small and
	physical, and the readable version of "this money is now yours" is the thing that was in the box
	going to the place the money lives. A burst says the same thing louder and less clearly, and
	this screen already has three cards' worth of art on it.

	IT IS THE CHIP'S OWN ICON THAT LEAVES. The one in the chip is hidden on the same frame the flyer
	appears at its exact rect, so it reads as one object rather than as a copy. The chip is then an
	empty square for the fifth of a second before the card starts to fade, which is the honest
	picture — the money is out of the box — and is why `HoldTime` is short. Lengthen that beat much
	and it stops reading as "taken" and starts reading as "missing".

	PARENTED TO `MainUI`, NOT TO THE PAGE, for two reasons that both matter. The page is about to
	fade and fold, and a child of it would fade and fold with the note still in mid-air; and the
	list `ClipsDescendants`, so a note inside it would be cut off at the panel's edge one frame
	after it left. `MainUI` is also the one coordinate space the chip and the counter can both be
	expressed in without an inset correction — every rect below is an absolute one with the screen's
	own origin subtracted back out.

	HAND-STEPPED, NOT TWEENED, because the path is a curve. `TweenService` interpolates a straight
	line between two `UDim2`s; a banknote that slides diagonally across the screen reads as a sprite
	being dragged, where one that lobs reads as something thrown. The curve is a quadratic bezier
	whose control point is lifted off the midpoint, and the easing is `Quad In` so the note drifts
	out of the chip and then dives into the counter rather than arriving at a constant crawl.

	NOTHING WAITS ON IT. The cash landed in the profile before this client heard about the claim, so
	the counter has usually finished rolling before the note gets there; the note explains a number
	that already moved. That is also why it does not punch the counter on arrival — the counter's
	own punch belongs to `GarageHudController` and fired when the money did. ]]
function Page:_flyReward(row: Frame, quest: Quest)
	local knobs = QuestConfig.ClaimEffect
	local art = REWARD_ICON[quest.Reward.Kind]
	local chip = partOf(row, "RewardFrame")
	local icon = chip and chip:FindFirstChild("RewardIcon")
	local target = self:_cashCounter()
	if not (art and target and self.MainUI and icon and icon:IsA("GuiObject") and icon.Visible) then
		return
	end

	local root = self.MainUI.AbsolutePosition
	local from = icon.AbsolutePosition + icon.AbsoluteSize / 2 - root
	local to = target.AbsolutePosition + target.AbsoluteSize / 2 - root
	local size = icon.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end

	--[[ The bow in the flight, perpendicular to nothing and simply UP: the chip is high on the
		panel and the counter is in the bottom corner, so a lifted midpoint gives the note a throw
		rather than a slide. Scaled by the distance travelled, so the arc is the same shape on a
		phone as on a monitor. ]]
	local control = (from + to) / 2 - Vector2.new(0, (to - from).Magnitude * knobs.Lift)

	local flyer = Instance.new("ImageLabel")
	flyer.Name = "QuestRewardNote"
	flyer.BackgroundTransparency = 1
	flyer.BorderSizePixel = 0
	flyer.AnchorPoint = Vector2.new(0.5, 0.5)
	flyer.Position = UDim2.fromOffset(from.X, from.Y)
	flyer.Size = UDim2.fromOffset(size.X, size.Y)
	flyer.Image = UIAssets.url(art)
	-- Stretch for the same reason the chip's icon uses it: a fixed box shrinking uniformly from its
	-- texture. Slicing this would inflate the corners. See `setRowProgress`.
	flyer.ScaleType = Enum.ScaleType.Stretch
	-- Above `Pages` and `HUD`, which are its siblings under a Sibling-behaviour ScreenGui.
	flyer.ZIndex = FLYER_ZINDEX

	local scale = Instance.new("UIScale")
	scale.Scale = knobs.FlightStartScale
	scale.Parent = flyer

	-- Hidden and parented on the same frame, so the note never exists twice on screen.
	icon.Visible = false
	flyer.Parent = self.MainUI

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
		-- Faded over the last of the flight rather than blinked out on arrival: the note is
		-- absorbed by the counter, and a hard cut at full opacity reads as a dropped frame.
		flyer.ImageTransparency = math.max(0, (alpha - FLYER_FADE_FROM) / (1 - FLYER_FADE_FROM))

		if alpha >= 1 then
			connection:Disconnect()
			flyer:Destroy()
		end
	end)
end

--[[ The card folds away and the list closes up behind it.

	THREE BEATS, and they are separate because they say different things. The PUNCH is the press
	landing. The HOLD is long enough to read the silver CLAIMED pill the punch drew attention to.
	The FOLD is the quest leaving: the card fades and shrinks in place while the ROW's height
	collapses under it, so everything below slides up into the gap.

	THE CARD SHRINKS AND THE ROW COLLAPSES, WHICH ARE TWO DIFFERENT INSTANCES. Folding the row alone
	squashes the art vertically on its way out, which looks like a rendering fault rather than a
	card leaving; fading the card alone leaves a quest-shaped hole in the middle of the list that
	closes with a jump. Running both, with the card ahead of the row, means the art is nearly gone
	by the time the space it occupied starts to close.

	THE CANVAS IS DRIVEN WHILE IT FOLDS. `_updateCanvas` sums the live row heights, so stepping it
	each frame keeps the scroll indicator honest through the collapse instead of claiming there is
	still a row below for as long as the fold lasts.

	`Quad In` ON THE COLLAPSE, deliberately: the layout's padding does not shrink with the row, so
	the last `_rowGap` of the space closes in one frame when the row is finally destroyed. Easing
	the fold so it is at its fastest at the end is what hides that step in motion.

	IT OWNS THE ROW UNTIL IT IS DONE. `finish` is the only thing that clears `_leaving`, takes the
	row out of the pool and destroys it, and it runs down every path out of here — including the one
	where the card was never wrapped. A page closed mid-fold leaves the tweens to finish on an
	invisible screen, which they do. ]]
function Page:_outroRow(row: Frame, id: string)
	local knobs = QuestConfig.ClaimEffect
	local card = row:FindFirstChild("Card")
	local scale = card and card:FindFirstChild("CardScale")

	local function finish()
		self._leaving[id] = nil
		if self._rows[id] == row then
			self._rows[id] = nil
		end
		row:Destroy()
		-- The board has not changed; this is the list catching up with a row that has gone, and it
		-- is what puts the "all claimed" line up when the last card leaves.
		self:_repaint()
	end

	if not (card and scale and scale:IsA("UIScale")) then
		finish()
		return
	end

	row:SetAttribute("Leaving", true)

	task.spawn(function()
		local punch = TweenService:Create(
			scale,
			TweenInfo.new(knobs.PunchTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = knobs.PunchScale }
		)
		punch:Play()
		punch.Completed:Wait()
		task.wait(knobs.HoldTime)

		-- The row can be destroyed inside those two beats: a board that rolls over at midnight
		-- takes every quest on it with it.
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

		-- The fold starts inside the fade rather than after it, so the two read as one movement.
		task.wait(math.max(0, knobs.FadeTime - knobs.CollapseTime))
		if not row.Parent then
			return
		end

		local collapse = TweenService:Create(
			row,
			TweenInfo.new(knobs.CollapseTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Size = UDim2.new(1, 0, 0, 0) }
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

--[[ Press the green pill.

	IT REPAINTS NOTHING, which is the whole of header note 1: the request goes out and the board
	that comes back is the answer. An optimistic flip to CLAIMED would be this page asserting a
	payment it cannot see land — and the one failure a reward screen must not have is saying
	CLAIMED over money nobody was paid.

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
	`Open`/`Close` — defining those would take the tween away from it and the three panels would stop
	feeling like one object.

	Opening is where a service call belongs: the set is pulled when the player looks at it, not held
	live. The scroll goes back to the top because a fresh open should start at the top of the list. ]]
function Page:StartOpenThread()
	self.List.CanvasPosition = Vector2.zero
	--[[ Ask, then draw what we already have. In that order deliberately: the request is a round
		trip and the board in hand is at most a few seconds stale, so repainting from it first means
		the screen is never blank while the reply is in flight. The reply repaints again when it
		lands, through the state event. ]]
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
