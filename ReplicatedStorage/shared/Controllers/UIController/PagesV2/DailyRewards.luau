--[[
	Daily Rewards page, V2  (client)
	--------------------------------
	The seven-day calendar on the Cartoony Kit. `DailyRewardConfig` has the design; this is the screen.

	=== A GRID OF DAY CARDS, NOT A LIST — 2026-10-06 ============================================

	WAS: the quest board's list of rows, one per day (the first cut). The owner, with five reference
	screens from other games: "that's an ugly ui, I want it designed nicely". Every one of those
	references is the same shape and it is the right one: a GRID OF CARDS, each a day — DAY N on top,
	a big picture of the prize in the middle, the amount under it — with taken days ticked, future
	days locked, today lit up, and the last day bigger than the rest.

	NOW, inside the quest board's panel (`BuildDailyRewardsV2` copies it, so the header, close button,
	checker backdrop and the clock under the panel are the kit's own art and unchanged):

	    [ DAY 1 ][ DAY 2 ][ DAY 3 ][ DAY 4 ]
	    [ DAY 5 ][ DAY 6 ][      DAY 7     ]      day 7: the JACKPOT, two cards wide, gold,
	                                              a turning Supra over the card's turning sunray

	The prize pictures are the kit's own uploads: the cash ladder (`UIAssets.CashTiers`, a bigger
	heap each cash day), the health pickup for the revive, a real car viewport for the free car, and
	the worlds page's padlock. No new art was needed.

	    today, unclaimed   green card, breathing; the kit's green CLAIM on it
	    taken              grey card, the prize faded, a green tick over it, grey CLAIMED
	    to come            the cyan card, the prize dimmed, a padlock over it, grey LOCKED
	    day 7              gold, its sunray turning, whatever its state

	=== THE KIT'S OWN DAY CARD, IN THE KIT'S OWN LAYOUT, 2026-10-12 ==============================

	WAS: the cards drawn by hand in an imitation of the kit (a flat gradient, a checker of white
	Frames across the top, pixel strokes, a drop shadow, the amount on a white pill), with day 7 a
	TALL card on the right. Dylan, after a playtest: "polish the daily rewards ui cards. increase size
	of car". IS: every card is the kit's own `DailyRewardsUI` day card (`Modules/ArcadeKit`: its
	gradient, white and navy rims, the checker texture and sunray), laid out the way the kit lays its
	own seven days out (four on top, three under, day 7 TWICE AS WIDE), with the kit card's own
	anatomy: the gold DAY heading, the prize amount under it, the picture, the kit button at the foot.
	A car is wide, so the wide jackpot gives it about twice the room the tall card did.

	THE PAGE DECIDES NOTHING (the quest board's rule 1). CLAIM fires a request; only the calendar that
	comes back (`DailyRewardController`, `StateEvent`) moves a card, and the card that just turned to
	taken is the one that punches — so a refused claim celebrates nothing.

	The list the quest board shipped with is still there, hidden; the grid takes its place exactly.
	Each card's button is the kit's own (`ArcadeKit.button`): green CLAIM on today, grey on the rest.
	If this place has no `Pages.DailyRewards` (`BuildDailyRewardsV2` not run), `new` answers nil.

	=== THE CLAIM LIVES ON TODAY — 2026-10-07 =====================================================

	The old footer repeated the streak rule and held one global CLAIM. Removing it gives the cards the
	height they were missing, and putting a clone on every card means the green action travels with
	today instead of asking the player to connect a distant button to the highlighted reward.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local DailyRewardConfig = require(ReplicatedStorage.shared.Configs.DailyRewardConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local ArcadeKit = require(ReplicatedStorage.shared.Modules.ArcadeKit)
local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)
local KitPage = require(script.Parent.Parent.KitPage)

local Page = KitPage.extend(DailyRewardConfig.PageName)
local TEXT = DailyRewardConfig.Text

-- === Layout ===================================================================

local WHITE = Color3.fromRGB(255, 255, 255)

--- Card faces per state, from the kit's own palette (`ArcadeKit.Faces`).
local FACE = {
	Waiting = "Cyan",
	Today = "Green",
	Taken = "Grey",
	Jackpot = "Gold",
}
local TICK = Color3.fromRGB(110, 235, 90)

--- The grid, in the area the quest board's list had: its share of that height, and the gaps.
local GRID_HEIGHT = 0.94
local GAP_X = 0.018
local GAP_Y = 0.045
--[[ Breathing room inside the white well, as shares of it (2026-10-07, the owner: "pad it a little on
	the left"). The first cut ran the cards edge to edge, so day 1 sat on the well's rim. ]]
local PAD_X = 0.02
local PAD_Y = 0.025
--- Cards in the top row; the bottom row has one fewer because day 7 takes two places.
local PER_ROW = 4
--[[ Inside a card, as `{ top, height }` shares of it, top to bottom: the kit's day card anatomy.
	`PRIZE` is the picture's band; the jackpot's car takes a taller band of the same card. ]]
local HEADING = { 0.045, 0.13 }
local AMOUNT = { 0.16, 0.15 }
local PRIZE = { 0.33, 0.42 }
local CAR = { 0.28, 0.54 }
local BUTTON = { 0.785, 0.165 }
--- Today's card swells to this and back; a card that has just been taken punches to `PUNCH`.
local PULSE = 1.05
local PUNCH = 1.18
--- Degrees a second the jackpot's sunray turns.
local SPIN_SPEED = 18
local TIMER_TICK = 0.25

local function box(parent: Instance, name: string, x: number, y: number, w: number, h: number, z: number): Frame
	local item = Instance.new("Frame")
	item.Name = name
	item.Position = UDim2.fromScale(x, y)
	item.Size = UDim2.fromScale(w, h)
	item.BackgroundTransparency = 1
	item.BorderSizePixel = 0
	item.ZIndex = z
	item.Parent = parent
	return item
end

local function picture(parent: Instance, name: string, x: number, y: number, w: number, h: number, image: number, z: number): ImageLabel
	local item = Instance.new("ImageLabel")
	item.Name = name
	item.Position = UDim2.fromScale(x, y)
	item.Size = UDim2.fromScale(w, h)
	item.BackgroundTransparency = 1
	item.Image = UIAssets.url(image)
	item.ScaleType = Enum.ScaleType.Fit
	item.ZIndex = z
	item.Parent = parent
	return item
end

--- The prize picture for a day: the cash ladder rung by how far into the week, the heart, the car.
local function prizeImage(day, index: number): number
	if day.Kind == "Legacy" then
		return UIAssets.GiftGlyph
	elseif day.Kind == "Revive" then
		return UIAssets.Pickups.Health
	end
	local ladder = UIAssets.CashTiers
	return ladder[math.clamp(math.ceil(index * #ladder / #DailyRewardConfig.Days), 1, #ladder)]
end

local function prizeText(day): string
	if day.Kind == "Legacy" then
		return TEXT.Claimed
	elseif day.Kind == "Cash" then
		return "+" .. GarageConfig.formatCash(day.Amount)
	elseif day.Kind == "Revive" then
		return string.format(TEXT.Revive, day.Amount)
	elseif day.Kind == "Car" then
		return string.format(TEXT.Car, GarageConfig.displayName(day.Body or "CAR"))
	end
	return ""
end

--- A missing page is a nil page, not an infinite wait (`KitPage.new` would wait for it forever).
function Page.new(UIController)
	local screen = UIRoot.wait(UIController.PlayerGui)
	local pages = screen and screen:FindFirstChild("Pages")
	if not (pages and pages:FindFirstChild(DailyRewardConfig.PageName)) then
		return nil
	end
	local self = KitPage.new(UIController, DailyRewardConfig.PageName)
	return setmetatable(self :: any, Page)
end

-- === Building =================================================================

--[[ One day's card: the kit's day card (`ArcadeKit.card`, which fits its checker and sunray to the
	card's shape), the DAY heading, the amount, the prize (a car on the jackpot), the kit button at
	the foot, and the two overlays a state can show: the tick and the padlock. Returned as a table of
	its parts; `_paintCard` decides which are showing. ]]
function Page:_buildCard(parent: Instance, index: number, x: number, y: number, w: number, h: number, big: boolean)
	local holder = box(parent, "Day" .. index, x, y, w, h, 2)
	local scale = Instance.new("UIScale")
	scale.Parent = holder
	local face = ArcadeKit.card(holder)

	local heading = ArcadeKit.heading(face, 0.05, HEADING[1], 0.9, HEADING[2])
	heading.Name = "Day"
	heading.ZIndex = 6
	local amount = ArcadeKit.text(face, 0.05, AMOUNT[1], 0.9, AMOUNT[2], WHITE, true)
	amount.Name = "Amount"
	amount.ZIndex = 6

	-- The jackpot can become cash; always build both visual types and select from the receipt.
	local prize = picture(face, "Prize", if big then 0.25 else 0.1, PRIZE[1], if big then 0.5 else 0.8, PRIZE[2], UIAssets.GiftGlyph, 5)
	local viewport
	if big then
		viewport = CarViewport.new(face, "PrizeCar")
		viewport.Position = UDim2.fromScale(0.03, CAR[1])
		viewport.Size = UDim2.fromScale(0.94, CAR[2])
		viewport.ZIndex = 5
	end
	local conversion = ArcadeKit.text(face, 0.04, 0.685, 0.92, 0.075, WHITE, true)
	conversion.Name = "Conversion"
	conversion.ZIndex = 9
	conversion.Visible = false

	--[[ The old check was made from two thick rotated bars. At card size it read as a bent pipe over
		the reward, so this uses one font glyph with the same outline as the rest of the UI. ]]
	local band = if big then CAR else PRIZE
	local tick = ArcadeKit.text(face, 0.25, band[1] + band[2] * 0.05, 0.5, band[2] * 0.9, TICK, true)
	tick.Name = "Tick"
	tick.Font = Enum.Font.GothamBold
	tick.Text = "✓"
	tick.ZIndex = 8
	local tickScale = Instance.new("UIScale")
	tickScale.Parent = tick
	--[[ The worlds page's lock (white, the kit navy grown round it). It was `DealerPanel.Lock` until
		2026-10-12, a key that does not exist, so no locked day ever drew its padlock. ]]
	--- On the jackpot the lock is a badge in the car's corner, not a padlock over the prize itself.
	local lock = if big
		then picture(face, "Lock", 0.84, band[1], 0.12, band[2] * 0.36, UIAssets.WorldsPage.Lock, 8)
		else picture(face, "Lock", 0.3, band[1] + band[2] * 0.15, 0.4, band[2] * 0.7, UIAssets.WorldsPage.Lock, 8)

	--[[ The kit's green button for today and its grey one for every other state; one shows at a time.
		A button per card rather than one moved at refresh time: a button never changes parent while
		it is pressed. ]]
	local claim, claimCaption = ArcadeKit.button(face, "Claim", 0.07, BUTTON[1], 0.86, BUTTON[2])
	claim.Name = "ClaimBtn"
	claimCaption.Text = TEXT.Claim
	local idle, idleCaption = ArcadeKit.button(face, "Disabled", 0.07, BUTTON[1], 0.86, BUTTON[2])
	idle.Name = "Idle"
	if claim:IsA("GuiButton") then
		claim.Activated:Connect(function()
			local controller = Shard.get("DailyRewardController")
			if controller then
				controller:claim()
			end
		end)
	end

	local bg = face:FindFirstChild("BG")
	return {
		index = index,
		big = big,
		holder = holder,
		scale = scale,
		face = face,
		heading = heading,
		prize = prize,
		viewport = viewport,
		viewportBody = nil :: string?,
		viewAspect = 2,
		burst = if big and bg then bg:FindFirstChild("Sunray") else nil,
		amount = amount,
		conversion = conversion,
		tick = tick,
		tickScale = tickScale,
		lock = lock,
		claim = claim,
		idle = idle,
		idleCaption = idleCaption,
		state = nil :: string?,
	}
end

function Page:initialize()
	self:setTitle(TEXT.Title)
	self._cards = {}
	self._tweens = {} :: { Tween }

	--- The grid goes exactly where the quest board's list was; the list stays, hidden.
	local list = self.List :: GuiObject?
	local area = box(list and list.Parent or self.PageUI, "DailyGrid", 0, 0, 1, 1, 2)
	if list then
		area.AnchorPoint = list.AnchorPoint
		area.Position = list.Position
		area.Size = list.Size
		list.Visible = false
	end
	self._area = area

	local width = 1 - PAD_X * 2
	local cardW = (width - GAP_X * (PER_ROW - 1)) / PER_ROW
	local cardH = (GRID_HEIGHT - GAP_Y) / 2
	local days = #DailyRewardConfig.Days
	for index = 1, days do
		local big = index == days
		local col = (index - 1) % PER_ROW
		local row = (index - 1) // PER_ROW
		local w = if big then cardW * 2 + GAP_X else cardW
		table.insert(self._cards, self:_buildCard(area, index, PAD_X + col * (cardW + GAP_X), PAD_Y + row * (cardH + GAP_Y), w, cardH, big))
	end

	local footer = self.PageUI:FindFirstChild("TimeLeft")
	self.TimerLabel = footer and footer:FindFirstChild("Label")
	local track = footer and footer:FindFirstChild("Track")
	self.TimerFill = track and track:FindFirstChild("Progress")

	self:refresh()
	Dispatcher:Subscribe(DailyRewardConfig.StateEvent, function(state)
		self:refresh(state)
	end)
end

-- === Drawing ==================================================================

--- One card in one state: "Today", "Taken" or "Waiting" (the jackpot keeps its gold face throughout).
function Page:_paintCard(card, day, state: string)
	local faceKey = if card.big and state ~= "Taken" then "Jackpot" else state
	ArcadeKit.paint(card.face, ArcadeKit.Faces[FACE[faceKey]])
	card.heading.Text = string.format(if card.big then TEXT.BigDayFormat else TEXT.DayFormat, card.index)
	local showCar = card.viewport ~= nil and day.Kind == "Car" and type(day.Body) == "string"
	if card.prize then
		card.prize.Visible = not showCar
		card.prize.Image = UIAssets.url(prizeImage(day, card.index))
	end
	if card.viewport then
		card.viewport.Visible = showCar
		if showCar and card.viewportBody ~= day.Body then
			local size = card.viewport.AbsoluteSize
			if size.X > 0 and size.Y > 0 then card.viewAspect = size.X / size.Y end
			if CarViewport.set(card.viewport, day.Body, { aspect = card.viewAspect }) then
				card.viewportBody = day.Body
			end
		elseif not showCar and card.viewportBody then
			CarViewport.clear(card.viewport)
			card.viewportBody = nil
		end
	end
	local converted = day.Kind == "Cash" and type(day.ConvertedFrom) == "string"
	card.conversion.Visible = converted
	card.conversion.Text = if converted then string.format(
		if day.Reason == "Full" then TEXT.ConvertedFull else TEXT.ConvertedDuplicate,
		GarageConfig.displayName(day.ConvertedFrom)
	) else ""
	if card.prize then
		card.prize.Size = UDim2.fromScale(if card.big then 0.5 else 0.8, if converted then 0.33 else PRIZE[2])
	end
	card.amount.Text = prizeText(day)
	local fade = if state == "Taken" then 0.55 elseif state == "Waiting" then 0.25 else 0
	if card.prize then
		card.prize.ImageTransparency = fade
		card.prize.ImageColor3 = if state == "Waiting" then Color3.fromRGB(190, 200, 215) else WHITE
	elseif card.viewport then
		--[[ Fading the ViewportFrame composites the rays through the whole car, so they look painted
			over its body. The lock already communicates "later"; the jackpot car stays solid. ]]
		card.viewport.ImageTransparency = 0
	end
	card.tick.Visible = state == "Taken" and not converted
	card.lock.Visible = state == "Waiting"
	card.claim.Visible = state == "Today"
	card.idle.Visible = state ~= "Today"
	card.idleCaption.Text = if state == "Taken" then TEXT.Claimed else TEXT.Locked
	card.state = state
end

--- Every card, the streak, the button and the clock, from the controller's calendar.
function Page:refresh(incoming)
	local controller = Shard.get("DailyRewardController")
	local state = incoming or (controller and controller:state())
	if not state then
		return
	end
	for _, tween in self._tweens do
		tween:Cancel()
	end
	table.clear(self._tweens)

	for _, card in self._cards do
		local day = state.days[card.index]
		if not day then
			continue
		end
		local was = card.state
		local now = if state.claimable and card.index == state.current then "Today"
			elseif card.index <= state.claimedThrough then "Taken"
			else "Waiting"
		self:_paintCard(card, day, now)
		card.scale.Scale = 1
		if now == "Today" then
			self:_loop(card.scale, PULSE, 0.6)
		elseif now == "Taken" and was == "Today" then
			self:_punch(card)
		end
	end
	self:_updateTimer(state)
end

function Page:_loop(scale: UIScale, to: number, seconds: number)
	local tween = TweenService:Create(scale, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = to })
	tween:Play()
	table.insert(self._tweens, tween)
end

--- The card that was just taken: a punch, and the tick popping in over the prize.
function Page:_punch(card)
	card.scale.Scale = PUNCH
	TweenService:Create(card.scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	card.tickScale.Scale = 0.2
	TweenService:Create(card.tickScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

--- The clock under the panel and its bar, drained by how much of the day is left.
function Page:_updateTimer(given)
	local controller = Shard.get("DailyRewardController")
	local state = given or (controller and controller:state())
	local nextAt = state and state.nextAt
	if type(nextAt) ~= "number" then
		return
	end
	local left = math.max(0, nextAt - os.time())
	if self.TimerLabel and self.TimerLabel:IsA("TextLabel") then
		local clock = string.format("%dh %dm %ds", left // 3600, (left % 3600) // 60, left % 60)
		self.TimerLabel.Text = string.format(TEXT.NextIn, clock)
	end
	local fill = self.TimerFill
	if fill and fill:IsA("GuiObject") then
		local ratio = math.clamp(left / 86400, 0, 1)
		fill.Visible = ratio > 0
		fill.Size = UDim2.new(ratio, 0, fill.Size.Y.Scale, fill.Size.Y.Offset)
	end
end

-- === Open and close ===========================================================

function Page:StartOpenThread()
	local controller = Shard.get("DailyRewardController")
	if controller then
		controller:refresh()
	end
	self:refresh()
	local jackpot = self._cards[#self._cards]
	if jackpot and jackpot.viewport and not self._carSpin then
		self._carSpin = CarViewport.spin(jackpot.viewport, { aspect = jackpot.viewAspect, degreesPerSecond = 22 })
	end
	if self._frameConnection then
		return
	end
	local accumulated = 0
	self._frameConnection = RunService.Heartbeat:Connect(function(dt)
		for _, card in self._cards do
			if card.burst then
				card.burst.Rotation = (card.burst.Rotation + SPIN_SPEED * dt) % 360
			end
		end
		accumulated += dt
		if accumulated >= TIMER_TICK then
			accumulated = 0
			self:_updateTimer()
		end
	end)
end

--- Nothing turns or ticks for a page nobody is looking at.
function Page:StartCloseThread()
	if self._carSpin then
		self._carSpin.stop()
		self._carSpin = nil
	end
	if self._frameConnection then
		self._frameConnection:Disconnect()
		self._frameConnection = nil
	end
end

return Page
