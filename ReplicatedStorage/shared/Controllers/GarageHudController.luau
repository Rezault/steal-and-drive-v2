--[[
	GarageHudController  (client)
	-----------------------------
	The cash counter, bottom left, plus the lot's income rate above it — and the DEALERSHIP VALUE
	readout in the opposite corner.

	IT DRIVES AUTHORED ART AND BUILDS NOTHING. `MainUI.HUD.Cash` is the imported pill — an
	ImageButton with the coin baked in — carrying two TextLabels over the top: `TextLabel` is the
	balance the artist drew, `Rate` is the income line. This controller resolves those three and
	writes text to them. It used to draw the whole pill in code as a stand-in until the art landed;
	that builder is gone, and with it the `GarageHud` ScreenGui it parented to PlayerGui.

	=== THE VALUATION READOUT IS GONE FROM THE SCREEN ==========================================

	There used to be a second readout, `MainUI.HUD.Value` — "DEALERSHIP VALUE" over the total, bare
	text in the BOTTOM RIGHT corner, opposite the balance. Both are money and they answer opposite
	questions, which is what put them in opposite corners rather than stacked in one:

	    Cash   (bottom left)    what you can SPEND right now. Falls every time you buy an upgrade.
	    Value  (removed)        what everything you OWN would sell for. Only moved when the
	                            collection did — banking a car, selling a duplicate.

	IT WAS DELETED FROM THE PLACE on 2026-08-18, the boss's call: the same total is already on your
	plot's nameplate as "WORTH $x" (`PlotService._paintValue`), and a number you can read off the
	sign you are standing next to does not also need a corner of the HUD. Both read
	`GarageConfig.ValueAttribute`, so nothing was lost — the sign was never the copy.

	EVERY LINE BELOW THAT FEEDS IT STAYS, and stays OPTIONAL. `_bind` looks the block up with
	`FindFirstChild` and is silent when it is absent, so this costs one nil check per join and no
	warning. Authoring a `Value` frame with an `Amount` TextLabel back under `MainUI.HUD` in the
	Explorer is the whole of putting it back — no code change, same deal as every other label on
	this HUD.

	WHICH PUTS IT WITH THE OTHERS. `DrivingHud`, `CarHud` and `CarHpBar` are authored in `StarterGui`
	for the boss's stated reason — a HUD is art, and its layout wants nudging in the Explorer rather than in
	a table of pixel offsets. This one is now the same deal, and the colour, font and position of
	both numbers live in the place where they can be dragged.

	TEXT IS NEVER BAKED INTO THE ART, which is why there are labels over it at all: the number
	changes and a PNG cannot. `UIAssets` states that rule for the whole kit; the driving HUD makes
	the same split with `GaugeBase.png`.

	IT READS AN ATTRIBUTE, NOT A REMOTE. `GarageService` mirrors the profile's `Cash` and
	`CashPerSecond` onto the Player; Roblox replicates those, and this watches them change. No
	remote, no round trip, no polling, and the label can never disagree with the server. Same
	reasoning `PlotConfig` gives for plot ownership and `CarHudController` for car HP.

	THE COUNTER ROLLS. A collection is the payoff for a whole run, and a number that changes between
	two frames is a number nobody saw change — so it eases to its new value and the NUMBER punches
	its scale once. Per the effect-intensity note this is the restrained version: the drama belongs
	to the size of the number, not to how long it takes to arrive.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)

local GarageHudController = Shard.new("GarageHudController")

local GUI_WAIT = 10

-- === One rolling money readout ==============================================
--[[ A label that eases to its new value and punches once when that value goes UP.

	IT IS A RECORD RATHER THAN A SECOND COPY OF THE CODE, because there are two of these now and
	they behave identically — one in each bottom corner. Everything that was
	`self._shown` / `self._rollToken` / `self._pulseTween` lives in here instead, one set per label,
	so the two cannot roll on top of each other's state.

	FREE FUNCTIONS, NOT METHODS. Neither touches the controller — they are pure animation over one
	record — and taking `self` would only invite reaching for controller state that the second
	readout does not have. ]]
type Readout = {
	label: TextLabel,
	-- The punch handle. See `bindReadout` for why it is created rather than demanded.
	scale: UIScale,
	base: number, -- the scale to return to, read once before anything can punch it
	shown: number, -- what the label currently reads, mid-roll included
	target: number, -- where it is heading
	token: number, -- bumped to cancel a roll already in flight
	tween: Tween?,
}

--[[ Wrap an authored label as a readout.

	The `UIScale` is created if absent rather than demanded like the labels themselves, because it
	is an animation handle rather than art — the same call `CarHudController` makes for the WRECKED
	banner, and for the same reason: these labels are `TextScaled`, so a TextSize tween is a silent
	no-op and the BOX is the font size.

	Its current value is the base rather than an assumed 1, so an artist who later scales a label in
	the Explorer keeps that scale instead of having the first collection stamp it out. ]]
local function bindReadout(label: TextLabel): Readout
	local scale = label:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = label
	end
	return {
		label = label,
		scale = scale,
		base = scale.Scale,
		shown = 0,
		target = 0,
		token = 0,
		tween = nil,
	}
end

-- === Binding ================================================================

--[[ Resolve the authored art and the labels written into it.

	Resolved ONCE rather than per use, and that is safe for a specific reason: `MainUI` is
	`ResetOnSpawn = false`, so it is built at join and outlives every respawn the player has. Same
	assumption every page module under `UIController` already makes when it waits on `MainUI` once.
	The Play button is the exception that re-resolves (`RaceEntryController`), because it is found by
	attribute and could legitimately move; these are found by name under a screen that does not.

	The balance is required and the rate is not: a place that has the pill imported but has not had
	the rate line added yet should still show a balance rather than warn and give up. The valuation
	is optional for the same reason and one stronger — it landed after this HUD was imported,
	so a place whose `MainUI` predates it has no such child, and the honest outcome there is a HUD
	missing one readout rather than a HUD that refuses to bind at all. ]]
function GarageHudController._resolve(self): boolean
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	--- `UIRoot` and not the name, so this binds the kit HUD when the new UI is the one in play. The
	--- names underneath it (`HUD.Cash`, its `TextLabel` and `Rate`) are the same in both, which is
	--- what keeps this file out of the migration.
	local mainUI = UIRoot.wait(playerGui, GUI_WAIT)
	local hud = mainUI and mainUI:FindFirstChild("HUD")
	local button = hud and hud:FindFirstChild("Cash")
	if not (button and button:IsA("GuiObject")) then
		self.log:warn("No MainUI.HUD.Cash in this place; the cash counter is unbound.")
		return false
	end

	local amount = button:FindFirstChild("TextLabel")
	if not (amount and amount:IsA("TextLabel")) then
		self.log:warn("MainUI.HUD.Cash has no TextLabel to write the balance into.")
		return false
	end

	local rate = button:FindFirstChild("Rate")
	if not (rate and rate:IsA("TextLabel")) then
		self.log:warn("MainUI.HUD.Cash has no Rate label; the income line will not show.")
		rate = nil
	end

	self._button = button
	self._cash = bindReadout(amount)
	self._rate = rate

	--- The kit block's green `+`. The old pill has none, so this is optional and silent. See
	--- `_followBalance`.
	local add = button:FindFirstChild("AddBtn")
	self._add = if add and add:IsA("GuiObject") then add else nil

	--[[ The valuation block, bottom right. Silent when absent — see the note above; a warning here
		would fire on every join of an older place and name nothing the player can act on. ]]
	local valueBlock = hud and hud:FindFirstChild("Value")
	local valueAmount = valueBlock and valueBlock:FindFirstChild("Amount")
	if valueBlock and valueBlock:IsA("GuiObject") and valueAmount and valueAmount:IsA("TextLabel") then
		self._valueBlock = valueBlock
		self._value = bindReadout(valueAmount)
	end

	return true
end

-- === The numbers ============================================================

--[[ Roll one readout to `target`.

	Driven off Heartbeat rather than a TweenService NumberValue because the label wants FORMATTED
	text on every frame, not a property interpolated behind the scenes — and formatting is what makes
	the roll legible (the commas move as the digits do). `token` is what makes a second collection
	land mid-roll cancel the first rather than fight it. ]]
local function roll(r: Readout, target: number)
	local from = r.shown
	if from == target then
		return
	end

	r.token += 1
	local token = r.token
	local duration = GarageConfig.Hud.RollTime
	local elapsed = 0

	task.spawn(function()
		while token == r.token and elapsed < duration do
			elapsed += RunService.Heartbeat:Wait()
			local alpha = TweenService:GetValue(math.min(1, elapsed / duration), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			r.shown = from + (target - from) * alpha
			r.label.Text = GarageConfig.formatCash(r.shown)
		end
		if token == r.token then
			r.shown = target
			r.label.Text = GarageConfig.formatCash(target)
		end
	end)
end

--[[ One punch on the NUMBER when money arrives. Only on an INCREASE — a balance going down is a
	purchase, and celebrating that is the wrong note.

	THE DIGITS FLEX, NOT THE PILL. It used to punch the whole ImageButton, which meant the coin, the
	plate and the rate line all breathed for something only the balance did — the boss's call, and
	the right one: the thing that changed is the thing that should move. A `UIScale` on the label is
	how, because the label is `TextScaled` and a TextSize tween can't coexist with that (the lesson
	`CarHudController` already banked on the WRECKED banner).

	It also drops the old caveat about the pill growing into its bottom margin. The label anchors
	top-left inside the pill with room on every side, so the punch has nothing to collide with.

	A SIZE PUNCH RATHER THAN AN ACCENT FLASH, because the pill is art and has no stroke to recolour —
	and tinting imported art is how you end up fighting the artist. Same `Back`-easing language
	`Components/Button` gives a hover, so the UI reacts to money the way it reacts to a cursor. ]]
local function pulse(r: Readout)
	if r.tween then
		r.tween:Cancel()
	end
	r.scale.Scale = r.base

	local half = GarageConfig.Hud.PulseTime / 2
	local punched = r.base * GarageConfig.Hud.PulseScale

	local up = TweenService:Create(r.scale, TweenInfo.new(half, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = punched })
	r.tween = up
	up.Completed:Connect(function(state)
		-- Cancelled means a second collection landed and has already started its own punch from
		-- `base`; settling this one back now would fight it.
		if state ~= Enum.PlaybackState.Completed then
			return
		end
		local down = TweenService:Create(r.scale, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = r.base })
		r.tween = down
		down:Play()
	end)
	up:Play()
end

--[[ Move one readout to `value`, punching only on the way UP.

	Shared by both numbers, and the "only on an increase" rule matters differently for each: a
	balance going down is a purchase, and celebrating that is the wrong note; a valuation going down
	is a car you just SOLD, which is the same story. Neither wants a flourish.

	`previous > 0` is what stops the very first value a fresh session receives from punching — the
	seed in `_bind` sets the readout without one, but a profile that lands a beat after this
	controller binds arrives here as 0 -> n and would otherwise pop for a number nobody earned. ]]
local function applyTo(r: Readout, value: unknown)
	local target = if type(value) == "number" then value else 0
	local previous = r.target
	r.target = target

	if target > previous and previous > 0 then
		pulse(r)
	end
	roll(r, target)
end

function GarageHudController._onCash(self, value: unknown)
	local readout = self._cash
	local previous = readout and readout.target or 0
	applyTo(readout, value)
	--- `previous > 0`: the first balance of a session is a seed, not a gain (`applyTo` has the same rule).
	if type(value) == "number" and previous > 0 and value > previous then
		self:_popGain(value - previous)
	end
end

--[[ A press the player could not afford (`GarageConfig.Hud.Short`): the pill swings side to side, the
	balance flashes red and back, and "NEED $X MORE" pops off the counter in red and fades. ]]
function GarageHudController._onShort(self, shortfall: unknown)
	local cfg = GarageConfig.Hud.Short
	local block = self._button
	local readout = self._cash
	if not (cfg and cfg.Enabled and block and block.Visible and type(shortfall) == "number") then
		return
	end

	--- The shake: a few swings of Rotation, each shorter, ending square.
	if self._shakeToken then
		self._shakeToken += 1
	else
		self._shakeToken = 1
	end
	local token = self._shakeToken
	task.spawn(function()
		for swing = 1, cfg.Swings do
			if token ~= self._shakeToken then
				return
			end
			local angle = cfg.Shake * (1 - (swing - 1) / cfg.Swings) * (if swing % 2 == 1 then 1 else -1)
			local t = TweenService:Create(block, TweenInfo.new(0.05, Enum.EasingStyle.Sine), { Rotation = angle })
			t:Play()
			t.Completed:Wait()
		end
		if token == self._shakeToken then
			TweenService:Create(block, TweenInfo.new(0.06), { Rotation = 0 }):Play()
		end
	end)

	--- The balance flashes red and settles back to the colour the artist gave it.
	if readout then
		local label = readout.label
		self._cashColour = self._cashColour or label.TextColor3
		label.TextColor3 = cfg.Color
		TweenService:Create(label, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextColor3 = self._cashColour }):Play()
	end

	--- The words.
	local live = self._short
	if live and live.Parent then
		live:Destroy()
	end
	local label = Instance.new("TextLabel")
	label.Name = "ShortPop"
	label.AnchorPoint = Vector2.new(0, 1)
	label.Position = UDim2.fromScale(0.18, 0.05)
	label.Size = UDim2.fromScale(1.1, 0.5)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = string.format(cfg.Format, GarageConfig.formatCash(math.ceil(shortfall)))
	label.TextColor3 = cfg.Color
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 20
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.fromRGB(5, 25, 43)
	outline.Thickness = 2
	outline.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = label
	label.Parent = block
	self._short = label
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(label, TweenInfo.new(cfg.Seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.18, -0.35),
	}):Play()
	local fade = TweenInfo.new(cfg.Seconds * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, cfg.Seconds * 0.6)
	TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
	TweenService:Create(outline, fade, { Transparency = 1 }):Play()
	task.delay(cfg.Seconds + 0.1, function()
		label:Destroy()
	end)

	local sounds = Shard.get("SoundController")
	if sounds then
		sounds:PlayNamed(cfg.Sound.Group, cfg.Sound.Name)
	end
end

--[[ The "+$350" off the counter (`GarageConfig.Hud.GainPop`): green, outlined, floating up and fading.
	Gains within `MergeSeconds` of the last one add into it, so a stream of tips is one climbing number
	rather than a column of them. Parented to the cash block, so it hides with the HUD. ]]
function GarageHudController._popGain(self, amount: number)
	local cfg = GarageConfig.Hud.GainPop
	local block = self._button
	if not (cfg and cfg.Enabled and block and block.Visible) then
		return
	end
	local now = os.clock()
	local live = self._gain
	if live and live.label.Parent and now - live.at < cfg.MergeSeconds then
		live.sum += amount
		live.at = now
		live.label.Text = "+" .. GarageConfig.formatCash(live.sum)
		return
	end

	local label = Instance.new("TextLabel")
	label.Name = "GainPop"
	label.AnchorPoint = Vector2.new(0, 1)
	label.Position = UDim2.fromScale(0.18, 0.05)
	label.Size = UDim2.fromScale(0.75, 0.5)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = "+" .. GarageConfig.formatCash(amount)
	label.TextColor3 = Color3.fromRGB(110, 255, 110)
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 20
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.fromRGB(5, 25, 43)
	outline.Thickness = 2
	outline.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = label
	label.Parent = block
	self._gain = { label = label, sum = amount, at = now }

	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(label, TweenInfo.new(cfg.Seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.18, -0.45),
	}):Play()
	local fade = TweenInfo.new(cfg.Seconds * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, cfg.Seconds * 0.6)
	TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
	TweenService:Create(outline, fade, { Transparency = 1 }):Play()
	task.delay(cfg.Seconds + 0.1, function()
		label:Destroy()
	end)
end

--[[ The valuation, bottom right — what everything in the collection would sell for.

	HIDDEN AT ZERO, the same call `_onRate` makes and for the same reason: a player who has never
	banked a car owns nothing, and "DEALERSHIP VALUE $0" sitting in the corner reads as a broken
	feature rather than as an honest zero. It arrives on the first car they get away with, which is
	the beat it means something on.

	IT ROLLS UP FROM ZERO THE FIRST TIME, which is the one case where a roll from the seed is the
	point rather than an artefact: the readout appears the moment your first car banks, and counting
	it in is the reveal. Every change after that rolls from the previous total, as the balance does. ]]
function GarageHudController._onValue(self, value: unknown)
	local r = self._value
	if not r then
		return
	end
	applyTo(r, if type(value) == "number" then value else 0)
	self:_syncValueBlock()
end

--[[ Whether the valuation is on screen, from the only two things that decide it.

	TWO CONDITIONS IN ONE PLACE, because they are set from opposite directions and the bug they make
	together is invisible until it happens: the race hides the HUD, and BANKING A CAR — the thing a
	race exists to do — changes the collection while it is hidden. Written as `Visible = target > 0`
	at the point the attribute lands, the corner would pop up over the results screen on the one beat
	this HUD is meant to be gone. ]]
function GarageHudController._syncValueBlock(self)
	if self._valueBlock then
		self._valueBlock.Visible = self._hudVisible and self._value ~= nil and self._value.target > 0
	end
end

--[[ The income rate, small, above the balance.

	Shown because it is the only place a player (or whoever is tuning `GarageConfig.Income`) can see
	the ladder working: park a Tier 5 and this jumps from 12/s to 78/s. Hidden at zero rather than
	showing "$0/s", because an empty lot has nothing to report and a zero reads as something being
	broken. ]]
function GarageHudController._onRate(self, value: unknown)
	if not self._rate then
		return
	end
	--[[ With passive income off the lot earns through tips, so the line shows the tip rate per hour
		instead (`GarageConfig.Hud.TipRate`, 2026-10-08) — `value` is ignored and the attribute read. ]]
	if not GarageConfig.Income.Passive then
		local perHour = Players.LocalPlayer:GetAttribute(GarageConfig.Hud.TipRate.Attribute)
		local amount = if type(perHour) == "number" then perHour else 0
		self._rate.Visible = amount > 0
		self._rate.Text = string.format(GarageConfig.Hud.TipRate.Format, GarageConfig.formatCash(amount))
		return
	end
	local rate = if type(value) == "number" then value else 0
	self._rate.Visible = rate > 0
	self._rate.Text = string.format("%s/s", GarageConfig.formatRate(rate))
end

--[[ Both readouts at once. The valuation only comes BACK if there is something to show — a player
	whose collection is still empty must not have an empty "$0" handed to them by the end of a race
	that banked nothing, which is what `_syncValueBlock` is for. ]]
function GarageHudController._setVisible(self, visible: boolean)
	self._hudVisible = visible
	if self._button then
		self._button.Visible = visible
	end
	self:_syncValueBlock()
end

--[[ THE `+` SITS AGAINST THE NUMBER, NOT AGAINST THE BOX.

	The kit lays the balance out in a box wide enough for `$999,999,999` and puts the `+` one gap past
	the BOX, so a new player's `$0` sat with a hand's width of empty HUD between it and its button
	(Dylan, 2026-09-16: "too far out"). So the `+` keeps the kit's gap from the right edge of the text
	as drawn, and never goes further out than the kit put it: a balance that fills the box puts it
	back on the artist's spot.

	Every number is a fraction of the block, read once off the authored layout, so a nudge in the
	Explorer still moves the row. `TextBounds` is the drawn width and it COUNTS the label's `UIScale`
	(measured: 60 to 90 at 1.5), which the collection punch animates, so the punch is divided back
	out and the `+` holds still while the number pops. It re-runs on the text, which is every frame
	of a roll, and on the block's size, because a capped text size need not change when the screen
	does. ]]
function GarageHudController._followBalance(self)
	local add, block, readout = self._add, self._button, self._cash
	if not (add and block and readout) then
		return
	end
	local label = readout.label
	if label.TextXAlignment ~= Enum.TextXAlignment.Left then
		return -- the kit sets it flush left; any other alignment has no free right edge to follow
	end

	local labelLeft = label.Position.X.Scale - label.AnchorPoint.X * label.Size.X.Scale
	local home = add.Position.X.Scale
	local halfToAnchor = add.AnchorPoint.X * add.Size.X.Scale
	local gap = (home - halfToAnchor) - (labelLeft + label.Size.X.Scale)

	local function place()
		local width = block.AbsoluteSize.X
		if width <= 0 or readout.scale.Scale <= 0 then
			return
		end
		local drawn = label.TextBounds.X * readout.base / readout.scale.Scale / width
		local x = math.min(home, labelLeft + drawn + gap + halfToAnchor)
		add.Position = UDim2.new(x, add.Position.X.Offset, add.Position.Y.Scale, add.Position.Y.Offset)
	end

	label:GetPropertyChangedSignal("TextBounds"):Connect(place)
	block:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	place()
end

-- === Wiring =================================================================

function GarageHudController._bind(self)
	local player = Players.LocalPlayer
	if not self:_resolve() then
		return
	end

	--[[ Seeded from the current value before connecting, and NOT rolled to it.

		The attribute is set by the server the moment the profile loads, which is usually before this
		controller finishes waiting on PlayerGui — so without the seed the counter sits at $0 until
		the next time the balance happens to change, and with a roll it would count a returning
		player's entire balance up from zero every single join. ]]
	local function seed(r: Readout, value: unknown)
		r.target = if type(value) == "number" then value else 0
		r.shown = r.target
		r.label.Text = GarageConfig.formatCash(r.shown)
	end

	seed(self._cash, player:GetAttribute(GarageConfig.CashAttribute))
	self:_onRate(player:GetAttribute(GarageConfig.RateAttribute))
	self:_followBalance()

	--[[ Seeded the same way, and its visibility set from the seed rather than left to the first
		change: a returning player with a full lot should find the valuation already up when the HUD
		appears, not on whatever they next bank. ]]
	if self._value then
		seed(self._value, player:GetAttribute(GarageConfig.ValueAttribute))
		self:_syncValueBlock()
	end

	player:GetAttributeChangedSignal(GarageConfig.CashAttribute):Connect(function()
		self:_onCash(player:GetAttribute(GarageConfig.CashAttribute))
	end)
	player:GetAttributeChangedSignal(GarageConfig.RateAttribute):Connect(function()
		self:_onRate(player:GetAttribute(GarageConfig.RateAttribute))
	end)
	player:GetAttributeChangedSignal(GarageConfig.Hud.TipRate.Attribute):Connect(function()
		self:_onRate(player:GetAttribute(GarageConfig.RateAttribute))
	end)
	player:GetAttributeChangedSignal(GarageConfig.ValueAttribute):Connect(function()
		self:_onValue(player:GetAttribute(GarageConfig.ValueAttribute))
	end)
end

--[[ Off during a run.

	The driving HUD owns the screen then — gauge cluster, HP bar, steer arrows and pedals — and a
	cash counter is noise on the one beat where the player is reading traffic. It is also the only
	number on screen that cannot change during a race, since nothing pays out mid-run.

	Only these two readouts go, not `MainUI`: the rail and the Play button share that screen and hide
	themselves (`RaceEntryController`). ]]
GarageHudController:withRemoteEvents({
	{
		RaceStart = function()
			if GarageConfig.Hud.HideDuringRace then
				GarageHudController:_setVisible(false)
			end
		end,
		RaceEnd = function()
			GarageHudController:_setVisible(true)
		end,
		CashShort = function(shortfall: unknown)
			GarageHudController:_onShort(shortfall)
		end,
	},
})

GarageHudController:withLifecycle({
	--[[ No roll state to seed here any more — a readout carries its own, and is built by
		`bindReadout` at resolve time, which is the first moment there is a label to attach it to.
		Declared nil so the shape of this controller is readable without chasing `_resolve`. ]]
	init = function(self)
		self._cash = nil :: Readout?
		self._value = nil :: Readout?
		self._valueBlock = nil :: GuiObject?
		self._add = nil :: GuiObject?
		--[[ TRUE BEFORE ANYTHING BINDS, because `RaceEnd` is not the only thing that reads it: a
			player who joins mid-nothing never fires either race event, and a readout that defaulted
			to hidden would wait for a race it may never run to be allowed on screen. ]]
		self._hudVisible = true
	end,

	start = function(self)
		if not (GarageConfig.Enabled and GarageConfig.Hud.Enabled) then
			return
		end
		-- Spawned rather than awaited: `_bind` waits on PlayerGui, and `Shard.start()` is the
		-- client's boot barrier — blocking it would hold up every other controller.
		task.spawn(function()
			self:_bind()
		end)
	end,
})

return GarageHudController
