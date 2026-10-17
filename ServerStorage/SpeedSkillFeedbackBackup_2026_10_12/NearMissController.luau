--[[
	NearMissController  (client)
	----------------------------
	The other half of shaving past a car: the word on the screen, the chain it belongs to, and the
	one line sent to the server so the run gets paid for it.

	`TrafficController` does the measuring — it is the only thing on this client that holds both cars
	and the road frame — and it comes in twice, from the two ends of the same ladder:

	  • `register(tier, gap)` from the near-miss pass, for a car you got past without touching it.
	  • `registerContact(severity)` from the clip, for a rub the other car shrugged off: TRADING PAINT.

	Everything after that is here, and it is here TOGETHER for one reason: the streak. A chain has to be
	counted in exactly one place, the toast has to say what THIS one paid, and the server has to be told
	the same thing. Split across two files, those three drift. The rule that trading paint KEEPS a chain
	without building it (`NearMissConfig.advancesStreak`) is exactly the sort of thing that would drift,
	which is why neither side of it is written down anywhere but the config.

	=== THE TOAST IS PRICED LOCALLY, AND THAT IS DELIBERATE =====================================

	The cash on screen is computed here, not sent back by the server. A round trip is 50-150ms, and
	the whole point of firing on the frame the two cars draw level (`TrafficController._checkNearMisses`)
	is that the number lands ON the whoosh rather than after it — a toast that arrives a tenth of a
	second late reads as the game being slow, which is the one thing a game about driving fast cannot
	afford to read as.

	Both sides therefore price the same near miss independently, out of the same two functions in
	`NearMissConfig` (`nextStreak` and `cashFor`), from the same single input: the seconds since the
	last one. That file's header has the full argument for why the streak rule is allowed to be a
	pure function of time and nothing else. The server is still the authority — it can refuse a
	report the guards catch, and the results screen shows what it actually banked — so the two can
	only differ for someone trying to cheat, which is exactly the right direction for a disagreement
	to point.

	=== WHY THIS SCREEN IS BUILT IN CODE ========================================================

	The rest of the driving UI is authored in Studio on purpose (`StarterGui.DrivingHud`,
	`StarterGui.CarHud`, `StarterGui.CarHpBar` — see DrivingHudController's header) so its LAYOUT can
	be nudged in the
	Explorer. This has no layout to nudge: one word and one number, centred, in a band the objective
	card and the gauge cluster both leave empty. What it does have is animation, which is code either
	way. So
	it is built here and every taste value in it lives in `NearMissConfig.Ui`.

	It is also deliberately transparent — text with an outline, no panel. A race screen is something
	the player is looking THROUGH, and an opaque rectangle in the middle of it at the exact moment
	they are threading traffic would cost them the thing it is congratulating them for.

	=== ONE TOAST, RE-PUNCHED ===================================================================

	A chain of four near misses does NOT stack four labels up the screen. The same toast is re-armed
	each time: new word, new number, streak chip ticks up, and the whole thing punches again. That is
	what makes a chain read as one escalating event rather than as a pile of floating text — and it
	is the restrained reading of the same feedback, which is this project's standing preference about
	effects.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local NearMissConfig = require(ReplicatedStorage.shared.Configs.NearMissConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local NitroConfig = require(ReplicatedStorage.shared.Configs.NitroConfig)

local NearMissController = Shard.new("NearMissController")

-- The kit's font, as everywhere else this project builds a screen in code.
local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

local NBSP = utf8.char(0xA0) -- TextScaled wraps rather than shrinks; see RaceUIController's note

-- Where the two lines sit inside the toast's own box, and how tall each is. The word is the
-- headline and the money is the receipt under it, same relationship as the results screen's.
local TITLE_Y, TITLE_HEIGHT = 0.32, 0.56
local AMOUNT_Y, AMOUNT_HEIGHT = 0.82, 0.3

local function approach(current: number, target: number, rate: number, dt: number): number
	if rate <= 0 then
		return target
	end
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

--[[ Everything the toast does differently per rung, in one place: the colour of the word, the size it
	settles at, how long it holds, and which SoundGroup it plays.

	Read live rather than snapshotted at load, so a colour or a hold nudged in `NearMissConfig` lands on
	the next near miss of a running playtest. ]]
local function look(tier: string): (Color3, number, number, string)
	local ui = NearMissConfig.Ui
	if tier == "Close" then
		return ui.CloseColor, ui.CloseScale, ui.CloseHold, ui.CloseSound
	elseif tier == "Thread" then
		return ui.ThreadColor, ui.ThreadScale, ui.ThreadHold, ui.ThreadSound
	elseif tier == "Paint" then
		return ui.PaintColor, ui.PaintScale, ui.PaintHold, ui.PaintSound
	end
	return ui.NearColor, ui.NearScale, ui.NearHold, ui.NearSound
end

-- `RichText` wants a hex string and the config holds a Color3, so the streak chip's colour is
-- converted once at build rather than written down twice.
local function hex(color: Color3): string
	return string.format("#%02X%02X%02X", math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255))
end

--[[ An outlined label. Both lines want the same treatment — read over tarmac, sky, or the white
	roof of the car being passed — and an outline is the only way to get that without a panel.

	The stroke is `Contextual` rather than the default so it draws only where the glyph meets the
	background, which keeps a 0.35%-of-screen outline from thickening the letterforms themselves at
	phone resolutions. ]]
local function outlined(name: string, y: number, height: number, parent: Instance): (TextLabel, UIStroke)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, y)
	label.Size = UDim2.fromScale(1, height)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.Text = ""
	label.TextScaled = true
	label.TextTransparency = 1
	label.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = NearMissConfig.Ui.OutlineColor
	stroke.Thickness = 2 -- resolved from the viewport on every show; see `_resolveOutline`
	stroke.Transparency = 1
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label

	return label, stroke
end

function NearMissController._build(self)
	local ui = NearMissConfig.Ui

	local gui = Instance.new("ScreenGui")
	gui.Name = "NearMissHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	--[[ UNDER the respawn screen's 999 and the return fade's 1000. A toast still on its way out when
		a wreck lands has to go behind both of those, not float over the decision the player is being
		asked to make — and `_onWrecked` drops it outright for the same reason. ]]
	gui.DisplayOrder = 900
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.AnchorPoint = Vector2.new(0.5, 0.5)
	toast.Position = UDim2.fromScale(ui.Position.X, ui.Position.Y)
	toast.Size = UDim2.fromScale(ui.Size.X, ui.Size.Y)
	toast.BackgroundTransparency = 1
	toast.Parent = gui

	--[[ The punch rides a UIScale rather than the frame's own Size, which matters for the same reason
		it does on the wrecked banner: the labels inside are TextScaled, so animating the box would
		animate the font size and the two lines would re-flow mid-pop. A UIScale scales the rendered
		result and re-flows nothing. ]]
	local scale = Instance.new("UIScale")
	scale.Parent = toast

	local title, titleStroke = outlined("Title", TITLE_Y, TITLE_HEIGHT, toast)
	local amount, amountStroke = outlined("Amount", AMOUNT_Y, AMOUNT_HEIGHT, toast)
	amount.RichText = true -- the streak chip is a coloured span inside the money; see `_text`
	amount.TextColor3 = ui.CashColor

	-- The kit's progress bar (NearMissConfig.Flow): a navy track with a dark outside border, a pill
	-- of fill laid over its left end, and an outlined label centred across both.
	local flowConfig = NearMissConfig.Flow
	local flow = Instance.new("Frame")
	flow.Name = "Flow"
	flow.AnchorPoint = Vector2.new(0.5, 0.5)
	flow.Position = UDim2.fromScale(flowConfig.Position.X, flowConfig.Position.Y)
	flow.Size = UDim2.fromScale(flowConfig.Size.X, flowConfig.Size.Y)
	flow.BackgroundColor3 = flowConfig.TrackColor
	flow.BorderSizePixel = 0
	flow.Visible = false
	flow.Parent = gui

	-- UICorner's scale is taken against the SHORTER side, so this is the mockup's radius at any size.
	local flowCorner = Instance.new("UICorner")
	flowCorner.CornerRadius = UDim.new(flowConfig.CornerRatio, 0)
	flowCorner.Parent = flow

	local flowStroke = Instance.new("UIStroke")
	flowStroke.Color = flowConfig.StrokeColor
	flowStroke.Thickness = 1.5 -- resolved from the bar's height; see `_resolveFlow`
	flowStroke.Parent = flow

	local flowFill = Instance.new("Frame")
	flowFill.Name = "Fill"
	flowFill.Size = UDim2.fromScale(1, 1)
	flowFill.BackgroundColor3 = flowConfig.LowColor
	flowFill.BorderSizePixel = 0
	flowFill.Parent = flow

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(flowConfig.CornerRatio, 0)
	fillCorner.Parent = flowFill

	local flowLabel = Instance.new("TextLabel")
	flowLabel.Name = "Label"
	flowLabel.Size = UDim2.fromScale(1, 1)
	flowLabel.BackgroundTransparency = 1
	flowLabel.FontFace = FONT
	flowLabel.Text = "FLOW  x1.00"
	flowLabel.TextColor3 = flowConfig.TextColor
	flowLabel.TextScaled = true
	flowLabel.ZIndex = 2
	flowLabel.Parent = flow

	local flowLabelStroke = Instance.new("UIStroke")
	flowLabelStroke.Color = flowConfig.StrokeColor
	flowLabelStroke.Thickness = 1.5 -- resolved with the border
	flowLabelStroke.LineJoinMode = Enum.LineJoinMode.Round
	flowLabelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	flowLabelStroke.Parent = flowLabel

	-- Sized so the capitals stand half the bar tall, which is the mockup's "Time Left" (0.48).
	local flowPadding = Instance.new("UIPadding")
	flowPadding.PaddingTop = UDim.new(0.09, 0)
	flowPadding.PaddingBottom = UDim.new(0.09, 0)
	flowPadding.PaddingLeft = UDim.new(0.06, 0)
	flowPadding.PaddingRight = UDim.new(0.06, 0)
	flowPadding.Parent = flowLabel

	flow:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_resolveFlow()
	end)

	self._gui = gui
	self._toast = toast
	self._scale = scale
	self._title = title
	self._titleStroke = titleStroke
	self._amount = amount
	self._amountStroke = amountStroke
	self._streakHex = hex(ui.StreakColor)
	self._flow = flow
	self._flowStroke = flowStroke
	self._flowFill = flowFill
	self._flowLabel = flowLabel
	self._flowLabelStroke = flowLabelStroke

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	flow.Visible = self._flowVisible == true
	self:_resolveFlow()
	self:_syncGui()
end

--[[ The Flow bar's measurements that have no scale form: both stroke thicknesses, and the narrowest
	the fill may get (`_stepFlow`). Re-read whenever the bar's pixel size changes, which is a resized
	window or a rotated phone. ]]
function NearMissController._resolveFlow(self)
	local size = self._flow.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	local thickness = math.max(1, size.Y * NearMissConfig.Flow.StrokeRatio)
	self._flowStroke.Thickness = thickness
	self._flowLabelStroke.Thickness = thickness
	self._flowFloor = size.Y / size.X
end

function NearMissController._syncGui(self)
	if self._gui then
		self._gui.Enabled = self._toastVisible == true or self._flowVisible == true
	end
end

--[[ Keep the chain readable between awards. The fill is time remaining, while colour and the
	camera push are chain strength. Expiration also clears the local streak at the same instant the
	server's pure `nextStreak` rule would start a new chain, so display and payout remain identical. ]]
function NearMissController._stepFlow(self, dt: number)
	local config = NearMissConfig.Flow
	local visible = false
	local targetFov = 0
	local lastAt = self._lastAt

	if config.Enabled and lastAt and self._streak >= config.MinimumStreak then
		local remaining = 1 - (os.clock() - lastAt) / NearMissConfig.Streak.Window
		if remaining > 0 then
			visible = true
			local multiplier = NearMissConfig.multiplierFor(self._streak)
			local maxMultiplier = math.max(NearMissConfig.Streak.Max, 1.001)
			local strength = math.clamp((multiplier - 1) / (maxMultiplier - 1), 0, 1)
			if self._flowFill and self._flowLabel then
				--[[ The fill is a pill of its own, so it may not get narrower than it is tall: past that
					its rounded end curves tighter than the track's and pokes out through the border. It
					stops as a round cap in the track's left end and fades out from there. ]]
				local fill = math.clamp(remaining, 0, 1)
				local floor = self._flowFloor
				self._flowFill.Size = UDim2.fromScale(math.max(fill, floor), 1)
				self._flowFill.BackgroundTransparency = if fill < floor then 1 - fill / floor else 0
				self._flowFill.BackgroundColor3 = if strength >= 1 then config.HighColor else config.LowColor
				self._flowLabel.Text = string.format("FLOW  x%.2f", multiplier)
			end
			targetFov = config.CameraFov * strength * math.clamp(remaining * 3, 0, 1)
		else
			self._streak = 0
			self._lastAt = nil
		end
	end

	if self._flow then
		self._flow.Visible = visible
	end
	if self._flowVisible ~= visible then
		self._flowVisible = visible
		self:_syncGui()
	end

	self._flowFov = approach(
		self._flowFov,
		targetFov,
		if targetFov > self._flowFov then config.CameraRise else config.CameraFall,
		dt
	)
	if self._camera and self._camera.setFlowFov then
		self._camera:setFlowFov(self._flowFov)
	end
	if self._wind and self._wind.setFlow then
		local denominator = math.max(config.CameraFov, 0.001)
		self._wind:setFlow(math.clamp(self._flowFov / denominator, 0, 1))
	end
end

--[[ The outline's thickness, which is the one measurement on this toast that has no scale form.

	Re-resolved on every show rather than once at build: the viewport changes under a rotated phone or
	a resized window, and a toast is cheap enough to ask again. Same treatment, same reason, as the
	results screen's spinner ring. ]]
function NearMissController._resolveOutline(self)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local thickness = math.max(1, camera.ViewportSize.Y * NearMissConfig.Ui.OutlineThickness)
	self._titleStroke.Thickness = thickness
	self._amountStroke.Thickness = thickness
end

-- Keep tweens from fighting, exactly as RaceUIController does: a fresh token per toast, and
-- anything still in flight is cancelled rather than merely fenced — a fade already running would
-- otherwise go on writing transparency over the top of the next near miss's arrival.
function NearMissController._tween(self, inst, time: number, props, style: Enum.EasingStyle?)
	local info = TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(inst, info, props)
	table.insert(self._tweens, tween)
	tween:Play()
	return tween
end

function NearMissController._cancelTweens(self)
	for _, tween in self._tweens do
		tween:Cancel()
	end
	table.clear(self._tweens)
end

-- What the money line says: what this pass paid, and — from the second one on — how long the chain
-- is. The chip is the CHAIN LENGTH rather than the multiplier it earned, because that is the thing
-- the player did; what it was worth is the number beside it.
function NearMissController._text(self, cash: number, streak: number): string
	local money = string.format("+$%d", cash)
	if streak <= 1 then
		return money
	end
	return string.format('%s%s%s<font color="%s">x%d</font>', money, NBSP, NBSP, self._streakHex, streak)
end

--[[ Put the toast up (or re-arm the one already up) for this near miss.

	Everything is written before anything is animated, so a re-arm mid-fade is a complete repaint
	rather than a patch over whatever state the last fade had reached. ]]
function NearMissController._show(self, tier: string, cash: number, streak: number)
	local ui = NearMissConfig.Ui
	if not (ui.Enabled and self._gui) then
		return
	end

	local token = self._token + 1
	self._token = token
	self:_cancelTweens()
	self:_resolveOutline()

	local color, rest, hold, sound = look(tier)
	self._title.Text = NearMissConfig.Labels[tier] or NearMissConfig.Labels.Near
	self._title.TextColor3 = color
	self._amount.Text = self:_text(cash, streak)
	-- A near miss that pays nothing is a real state (`NearMissConfig.Cash` zeroed, or the whole
	-- payout switched off in RewardConfig) and it still deserves the word — so the money line is
	-- dropped rather than the toast.
	self._amount.Visible = cash > 0

	self._title.TextTransparency = 0
	self._titleStroke.Transparency = 0
	self._amount.TextTransparency = 0
	self._amountStroke.Transparency = 0
	self._toast.Position = UDim2.fromScale(ui.Position.X, ui.Position.Y)
	self._toastVisible = true
	self:_syncGui()

	-- The pop. Back-eased so it overshoots a hair and settles, and each rung settles at its own size —
	-- which is the whole of the severity language on this screen (NearMissConfig.Ui).
	self._scale.Scale = ui.PopFrom * rest
	self:_tween(self._scale, ui.PopTime, { Scale = rest }, Enum.EasingStyle.Back)

	task.delay(ui.PopTime + hold, function()
		if self._token ~= token then
			return -- another near miss took the toast over; its own fade owns it now
		end
		self:_fade(token)
	end)

	if sound ~= "" and self._sounds then
		self._sounds:PlayRandom(sound)
	end
end

-- Out, drifting up a couple of percent of the screen as it goes. The outline leaves AHEAD of the
-- letters (`NearMissConfig.Ui.StrokeFade` has the reason); faded together it is the last thing on
-- screen.
function NearMissController._fade(self, token: number)
	local ui = NearMissConfig.Ui
	local strokeTime = ui.FadeTime * ui.StrokeFade
	self:_tween(self._title, ui.FadeTime, { TextTransparency = 1 })
	self:_tween(self._titleStroke, strokeTime, { Transparency = 1 })
	self:_tween(self._amount, ui.FadeTime, { TextTransparency = 1 })
	self:_tween(self._amountStroke, strokeTime, { Transparency = 1 })
	local rise = UDim2.fromScale(ui.Position.X, ui.Position.Y - ui.Rise)
	local tween = self:_tween(self._toast, ui.FadeTime, { Position = rise })
	tween.Completed:Once(function()
		if self._token == token then
			self._toastVisible = false
			self:_syncGui()
		end
	end)
end

--[[ Take it down now, without a fade, and forget the chain.

	Called on the two beats where a toast on screen would be a lie: a wreck (the chain is over, and
	the respawn screen is about to ask a question the player should be reading instead) and the end
	of a run. Instant rather than faded because both of those beats already have something loud
	happening — a fade would be a piece of the last second of the run hanging over the first second
	of what comes next. ]]
function NearMissController._reset(self)
	self._streak = 0
	self._lastAt = nil
	self._token += 1
	self:_cancelTweens()
	self._toastVisible = false
	self._flowVisible = false
	self._threadSide, self._threadAt = nil, nil
	if self._gui then
		if self._flow then
			self._flow.Visible = false
		end
		self:_syncGui()
		self._title.TextTransparency = 1
		self._titleStroke.Transparency = 1
		self._amount.TextTransparency = 1
		self._amountStroke.Transparency = 1
		self._scale.Scale = 1
	end
	self._flowFov = 0
	if self._camera and self._camera.setFlowFov then
		self._camera:setFlowFov(0)
	end
	if self._wind and self._wind.setFlow then
		self._wind:setFlow(0)
	end
end

--[[ One encounter with a traffic car, whichever end of the ladder it came from: price it, show it,
	report it.

	WHAT GOES ON THE WIRE IS THE MEASUREMENT — never the tier, never an amount. Same rule a clip report
	follows, for the same reason: the client sends what it saw and the server decides what it is worth.
	Exactly one of the two measurements is meaningful, and `NearMissConfig.tierFor` reads them in the
	order that makes a contact win, so a report can never be a tier the road would not have produced.

	THE ORDER HERE IS THE ORDER IT MATTERS IN. The chain is advanced first (both sides do it from the
	same rule, including the part where a rub does not advance it), the report goes out second so the
	money is on its way before a frame is spent animating anything, and the toast is last. ]]
--- `token` is the passed car's encounter token (`EncounterConfig`, 2026-09-28): the server pays one
--- near miss per car it issued, so the report has to say which car.
function NearMissController._award(self, tier: string, gap: number?, severity: number?, side: number?, token: string?)
	local now = os.clock()
	self._streak = NearMissConfig.nextStreak(
		self._streak,
		if self._lastAt then now - self._lastAt else nil,
		NearMissConfig.advancesStreak(tier)
	)
	self._lastAt = now

	self:getRemoteEvent("NearMiss"):Fire(gap, severity, side, token)
	local cash = NearMissConfig.cashFor(tier, self._streak, WorldConfig.resolve(Players.LocalPlayer:GetAttribute(WorldConfig.WorldAttribute)))

	--[[ THREADING THE NEEDLE — the same rule the server applies (`NearMissConfig.isThread`), minus its
		network slack. It replaces the word on the toast rather than adding a second toast, and pays on
		top of this pass's own near miss. ]]
	local clean = severity == nil
	if clean and NearMissConfig.isThread(self._threadSide, side, if self._threadAt then now - self._threadAt else nil) then
		self._threadSide, self._threadAt = nil, nil
		cash += NearMissConfig.cashFor("Thread", self._streak, WorldConfig.resolve(Players.LocalPlayer:GetAttribute(WorldConfig.WorldAttribute)))
		tier = "Thread"
	elseif clean then
		self._threadSide, self._threadAt = NearMissConfig.sideOf(side), now
	end

	self:_show(tier, cash, self._streak)

	-- The camera's lean toward the car you shaved (CameraConfig.Juice.Pass). A rub is a contact and
	-- already got the impact punch on the clip path, so only clean passes get this.
	if clean and self._camera and self._camera.nearPass then
		self._camera:nearPass(side, tier)
	end

	--[[ ...and the nitro bottle, which is the other thing a near miss buys.

		`severity` is what tells the two apart and it is already to hand: a clean pass arrives with a
		gap and no severity, a rub arrives with a severity and no gap. The gain for the second one is
		zero by default and that asymmetry is the point (`NitroConfig.Gain`): shaving past a car earns
		you speed, hitting it does not.

		Fired at the controller rather than computed here, because the tank is not this file's state
		and a fraction of it is meaningless without knowing what car it belongs to. Nil-checked
		instead of depended on: the payout is a bonus on top of the cash, and a place with nitro
		switched off must still pay the cash. ]]
	local nitro = self._nitro
	if nitro then
		local gain = NitroConfig.Gain
		nitro:reward(if severity == nil then gain.PerNearMiss else gain.PerTradingPaint)
	end
end

-- PUBLIC (TrafficController) — a clean pass, with the caller having already resolved which of the two
-- clean rungs the gap it measured comes to.
function NearMissController.register(self, tier: string, gap: number, side: number?, token: string?)
	if not NearMissConfig.Enabled then
		return
	end
	self:_award(tier, gap, nil, side, token)
end


--[[ PUBLIC (TrafficController) — you TOUCHED one. Trading paint if the other car shrugged it off, and
	nothing at all if it did not.

	The ceiling is resolved HERE rather than at the call site, because the call site is the clip path and
	it has no other reason to know that a light contact is worth anything: it hands over the severity it
	had already measured for the damage and lets this decide. A real crash therefore costs one nil check
	and says nothing. ]]
function NearMissController.registerContact(self, severity: number, token: string?)
	if not NearMissConfig.Enabled then
		return
	end
	local tier = NearMissConfig.tierFor(nil, severity)
	if not tier then
		return
	end
	self:_award(tier, nil, severity, nil, token)
end

-- How long the current chain is, for anything that wants to read it (nothing does yet — the HUD
-- shows it on the toast). Zero between chains, which is what "no chain" means.
function NearMissController.getStreak(self): number
	return self._streak
end

NearMissController:withRemoteEvents({
	--[[ Client -> server, handled by `RewardService`. Declared here rather than beside the traffic
		remotes because this controller is the only thing that fires it, and because what it buys is a
		payout rather than damage. ]]
	"NearMiss",
	{
		-- A new run starts with no chain and nothing on screen. `RaceStart` also covers a revive
		-- (`RaceRevived` fires it in every other controller for the same reason): the run carries on,
		-- but a chain does not survive the car being wrecked.
		RaceStart = function()
			NearMissController:_reset()
		end,
		RaceWrecked = function()
			NearMissController:_reset()
		end,
		RaceRevived = function()
			NearMissController:_reset()
		end,
		RaceEnd = function()
			NearMissController:_reset()
		end,
	},
})

NearMissController:withLifecycle({
	init = function(self)
		self._streak = 0
		self._lastAt = nil -- os.clock() of the last near miss, or nil for no chain
		self._token = 0
		self._tweens = {}
		self._toastVisible = false
		self._flowVisible = false
		self._threadSide = nil -- the open half of a possible thread (`NearMissConfig.isThread`)
		self._threadAt = nil
		self._flowFov = 0
		self._flowFloor = 0 -- the fill's narrowest, as a fraction of the track; see `_resolveFlow`
		self._flowConnection = nil :: RBXScriptConnection?
	end,

	start = function(self)
		-- Taken BEFORE the screen check below, because the nitro payout is a reward and not a
		-- readout: switching the toast off must not quietly stop near misses filling the bottle.
		self._nitro = Shard.get("NitroController")
		self._camera = Shard.get("RaceCameraController")
		self._wind = Shard.get("WindController")
		self._flowConnection = RunService.Heartbeat:Connect(function(dt)
			self:_stepFlow(dt)
		end)

		if not (NearMissConfig.Enabled and NearMissConfig.Ui.Enabled) then
			-- No screen to build. `register` still reports, so the bonus is banked and shows up on the
			-- results screen — this switch takes the toast out, not the reward.
			return
		end
		self._sounds = Shard.get("SoundController")
		-- Spawned rather than awaited: `_build` waits on PlayerGui, and `Shard.start()` is the
		-- client's boot barrier. Same reason CarHudController spawns its bind.
		task.spawn(function()
			self:_build()
		end)
	end,
})

NearMissController:withCleanup(function()
	NearMissController:_reset()
	if NearMissController._flowConnection then
		NearMissController._flowConnection:Disconnect()
		NearMissController._flowConnection = nil
	end
end)

return NearMissController
