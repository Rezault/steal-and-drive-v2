--[[
	PoliceHudController  (client)
	-----------------------------
	WHAT THE PLAYER IS TOLD ABOUT THE CHASE. Three pieces, and none of them is on screen for the
	whole of one:

	    (arm) --> [ POLICE across the middle ] --> [ CATCHING UP bar, bottom centre ] --> gone
	                  "this is happening"              "how close, right now"
	                                       \
	                                        --> [ red and blue washing the edges, as the bar falls ]

	IT OWNS NO STATE OF ITS OWN ABOUT THE CHASE. Everything drawn here is read from
	`PoliceController:getChase()` every frame, and nothing is driven by an event. That is deliberate
	and it is what makes the display unbreakable, exactly as the getaway card's polling does: a
	chase that arms, is survived, is armed again and is then wrecked out of moves this through five
	states without a single subscription to get out of sync, and a wreck or a revive needs no
	handler here at all because both are already visible in what that accessor answers.

	=== THE VIGNETTE IS TIED TO THE BAR, NOT TO THE CHASE ======================================

	At a full bar there is no tint at all, and it comes up as the bar falls. That is the single most
	important decision on this screen. Flashing lights over the whole of a forty second chase would
	be forty seconds of strobing across the exact part of the frame the player is trying to read the
	road through, which is how a good beat becomes an unbearable one. Tied to the bar, the lights
	close in when the player is in trouble and the screen is clean when they are not, which also
	makes the tint a SIGNAL instead of a texture.

	=== IT IS NOT THE GAUGE, IT IS THE READING ================================================

	The cruisers out of the window are the gauge (`PoliceConfig` note 1): they ride closer as the
	bar drains, so a player who never looks down still knows where they stand. What this adds is a
	legible number on the frames where a cruiser happens to be behind the player's own car, and the
	news that the rule has started applying at all. If a change here would make the bar the only
	place the state lives, it is the wrong change.

	=== EVERY NUMBER IS IN `PoliceConfig.Hud` ==================================================

	What is in this file is layout and sequencing. The bar is the same pill-with-a-stroke-and-no-
	track-art construction the nitro bar, the car's HP bar and the getaway card use, cut by a
	`UIGradient` rather than resized (see `cutAt` for why).

	HOUSE RULE: no wiki-style double-bracket links in this comment. The closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local PoliceConfig = require(ReplicatedStorage.shared.Configs.PoliceConfig)
--- Which steal popups have folded into the toast (`StealJuiceConfig.OneMoment`).
local StealJuiceConfig = require(ReplicatedStorage.shared.Configs.StealJuiceConfig)
local NoticeLane = require(ReplicatedStorage.shared.Modules.NoticeLane)

local PoliceHudController = Shard.new("PoliceHudController"):withDependencies({ "PoliceController" })

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

--- `TextScaled` would sooner break a caption onto a second line than pick a smaller font, so every
--- one-line label in this project is written through a non-breaking space. See RaceUIController.
local NBSP = utf8.char(0xA0)
local function oneLine(text: string): string
	return (string.gsub(text, "%s+", NBSP))
end

--[[ ABOVE the getaway card (890) and the near-miss toast (900), and UNDER everything that asks the
	player a question: the respawn screen is 999 and the return fade 1000.

	Higher than the toast because this is the only thing on the driving screen that can END A RUN,
	and a near miss congratulating you must not be drawn over the reason you are about to be
	arrested. Lower than the respawn screen for the reason `CarHudController` takes its banner down:
	once a full-screen overlay is up, this has already had its say. ]]
local DISPLAY_ORDER = 910

--[[ The cut in the fill's gradient, and why the bar is not simply resized.

	`UICorner`'s scale radius is taken against a frame's SHORTER side, so a fill shrunk to a tenth
	of its trough has a tenth of the cap radius the trough is drawn with: it flattens into a lozenge
	whose corners no longer follow the pill's ends and visibly pokes out of its sides. Held at the
	trough's exact size and cut by transparency instead, the fill IS the trough's shape at every
	level, because its geometry never moves.

	The step carries a hairline of ramp rather than being infinitely sharp. Zero width is not on
	offer (`NumberSequence` keypoints have to advance in time) and the hairline is the only
	anti-aliasing the cut gets anyway. Same construction and same number as
	`DrivingHudController.cutAt`, which is where this was worked out. ]]
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

--- Approach a target at a rate, frame-rate independently. The bar's own smoothing, and the only
--- thing on this screen that lags what it is drawing: see `_stepBar`.
local function approach(current: number, target: number, rate: number, dt: number): number
	return target + (current - target) * math.exp(-rate * dt)
end

-- === Build ==================================================================

--[[ The four edge tints: one band per side of the screen, each faded out toward the middle by a
	transparency ramp of its own.

	A FRAME WITH A HARD INNER EDGE WOULD READ AS A COLOURED BORDER, which is a UI element. What this
	wants is light spilling in from off screen, which has no edge at all, and a `UIGradient` on a
	plain frame is the cheapest honest way to get one: no art to upload, no image to slice, and the
	falloff is a curve anybody can retune here.

	TWO BANDS ARE RED AND TWO ARE BLUE, on opposite sides, so the wash pivots across the screen with
	the flash rather than the whole frame pulsing one colour and then the other. A screen that goes
	fully red and then fully blue is a strobe; two colours trading places about the middle is a
	light bar going round. ]]
function PoliceHudController._buildVignette(self, gui: ScreenGui)
	local cfg = PoliceConfig.Hud.Vignette
	if not cfg.Enabled then
		return
	end

	local holder = Instance.new("Frame")
	holder.Name = "Lights"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.ZIndex = 0 -- under the bar and the alert, both of which have to stay readable through it
	holder.Parent = gui

	--[[ `rot` IS THE DIRECTION THE RAMP RUNS, and it has to run INTO the screen from that band's own
		edge: a `UIGradient` puts its offset 0 at the side its rotation points away from, and
		Rotation 0 is left-to-right, 90 top-to-bottom.

		Both of the obvious ways to write this are wrong and the first version had both. Deriving the
		rotation as "the side's angle plus 90" swaps Left and Right, and a ramp written
		transparent-to-opaque draws every band opaque along its INNER edge, which is the exact
		opposite of a vignette. What it renders as is four hard-edged slabs across the middle of the
		frame, and it is unmistakable in a screenshot. ]]
	local sides = {
		{ name = "Top", anchor = Vector2.new(0.5, 0), rot = 90, horizontal = true, red = true },
		{ name = "Bottom", anchor = Vector2.new(0.5, 1), rot = 270, horizontal = true, red = true },
		{ name = "Left", anchor = Vector2.new(0, 0.5), rot = 0, horizontal = false, red = false },
		{ name = "Right", anchor = Vector2.new(1, 0.5), rot = 180, horizontal = false, red = false },
	}

	--[[ Opaque at the screen edge, gone before the inner one. The falloff is deliberately fast: the
		point at which a player notices an edge is the point at which it has stopped being light and
		started being a border.

		ONLY THE TRANSPARENCY MOVES. The colour ramp is left flat because a `UIGradient` MULTIPLIES
		the fill colour, so a ramp that darkened toward one end would take the red out of a red tint
		(the standing note on that lives in `UIAssets`). ]]
	local falloff = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.45, 0.62),
		NumberSequenceKeypoint.new(1, 1),
	})

	self._tints = {}
	for _, side in sides do
		local tint = Instance.new("Frame")
		tint.Name = side.name
		tint.AnchorPoint = side.anchor
		tint.Position = UDim2.fromScale(side.anchor.X, side.anchor.Y)
		--- The two horizontal bands span the full width and the two vertical ones the full height,
		--- so the corners are covered twice and read as the brightest part of the wash. That is
		--- also where a real light spill is brightest.
		tint.Size = if side.horizontal then UDim2.fromScale(1, cfg.Reach) else UDim2.fromScale(cfg.Reach, 1)
		tint.BackgroundColor3 = if side.red then cfg.Red else cfg.Blue
		tint.BackgroundTransparency = 1
		tint.BorderSizePixel = 0
		tint.Parent = holder

		local ramp = Instance.new("UIGradient")
		ramp.Rotation = side.rot
		ramp.Transparency = falloff
		ramp.Parent = tint

		table.insert(self._tints, { frame = tint, red = side.red })
	end
end

--[[ THE HEAT READOUT (`PoliceConfig.Heat`, 2026-10-19): the live stars and what the run will bank
	for, on a screen of its own because it is up for the whole run and the chase's screen is not
	(it switches itself off between chases, see `_loop`). Red stars while the police are on you or
	coming; grey once you have lost them; the gold multiplier under them is the bank's, and stays. ]]
function PoliceHudController._buildHeat(self)
	local cfg = PoliceConfig.Heat
	local gui = Instance.new("ScreenGui")
	gui.Name = "HeatHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = DISPLAY_ORDER
	gui.Enabled = false
	local stars = Instance.new("TextLabel")
	stars.AnchorPoint = Vector2.new(0, 0)
	stars.Position = UDim2.fromScale(cfg.HudX, cfg.HudY)
	stars.Size = UDim2.fromScale(0.16, cfg.HudHeight)
	stars.BackgroundTransparency = 1
	stars.FontFace = FONT
	stars.TextScaled = true
	stars.TextXAlignment = Enum.TextXAlignment.Left
	stars.Parent = gui
	local starStroke = Instance.new("UIStroke")
	starStroke.Color = Color3.fromRGB(8, 10, 14)
	starStroke.Thickness = 2
	starStroke.Parent = stars
	local scale = Instance.new("UIScale")
	scale.Parent = stars
	local bonus = Instance.new("TextLabel")
	bonus.AnchorPoint = Vector2.new(0, 0)
	bonus.Position = UDim2.fromScale(cfg.HudX, cfg.HudY + cfg.HudHeight * 1.05)
	bonus.Size = UDim2.fromScale(0.16, cfg.HudHeight * 0.65)
	bonus.BackgroundTransparency = 1
	bonus.FontFace = FONT
	bonus.TextScaled = true
	bonus.TextXAlignment = Enum.TextXAlignment.Left
	bonus.TextColor3 = Color3.fromRGB(255, 214, 64)
	bonus.Parent = gui
	local bonusStroke = Instance.new("UIStroke")
	bonusStroke.Color = Color3.fromRGB(8, 10, 14)
	bonusStroke.Thickness = 1.5
	bonusStroke.Parent = bonus
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self._heatGui, self._heatStars, self._heatBonus, self._heatScale = gui, stars, bonus, scale
	self._heatShown = -1
end

--- Pixels between the LUCK INCREASED card and the heat readout slid under it, and how fast the slide
--- closes (per second, exponential). See `_stepHeat`.
local HEAT_LUCK_GAP = 6
local HEAT_SLIDE_RATE = 14

--- "1.45" for a multiplier, trailing zeros off.
local function multiplierText(value: number): string
	return (string.gsub(string.format("%.2f", value), "%.?0+$", ""))
end

--- One frame of the heat readout. Up whenever the run has heat to show; a new star pops it.
function PoliceHudController._stepHeat(self, heat, now: number)
	local gui = self._heatGui
	if not gui then
		return
	end
	local show = heat ~= nil and (heat.stars > 0 or heat.earned > 0)
	gui.Enabled = show
	--[[ THE LUCK INCREASED card is the same top-left corner, up for a few seconds at a time (2026-10-20,
		Aleafo's "overlap"). The readout slides down under it while it is up and back when it goes:
		the drop is however far the card's bottom edge reaches past the readout's own top, eased.
		Both are measured in `AbsolutePosition`, one shared space whatever either gui's inset. ]]
	local luck = Shard.get("LuckProgressController")
	local bottom = luck and luck:bottom()
	local drop = self._heatDrop or 0
	local want = 0
	if bottom then
		want = math.max(0, bottom + HEAT_LUCK_GAP - (self._heatStars.AbsolutePosition.Y - drop))
	end
	local dt = math.clamp(now - (self._heatAt or now), 0, 0.1)
	self._heatAt = now
	drop += (want - drop) * (1 - math.exp(-HEAT_SLIDE_RATE * dt))
	if math.abs(want - drop) < 0.5 then
		drop = want
	end
	if drop ~= self._heatDrop then
		self._heatDrop = drop
		local base = PoliceConfig.Heat
		self._heatStars.Position = UDim2.new(base.HudX, 0, base.HudY, math.round(drop))
		self._heatBonus.Position = UDim2.new(base.HudX, 0, base.HudY + base.HudHeight * 1.05, math.round(drop))
	end
	if not show then
		self._heatShown = -1
		return
	end
	local cfg = PoliceConfig.Heat
	if heat.stars ~= self._heatShown then
		--- No pop with `OneMoment.QuietStars`: the toast already said what the steal did.
		if heat.stars > self._heatShown and self._heatShown >= 0 and not StealJuiceConfig.oneMoment("QuietStars") then
			self._heatPop = now
		end
		self._heatShown = heat.stars
		self._heatStars.Text = string.rep(cfg.Star, heat.stars) .. string.rep(cfg.EmptyStar, cfg.Max - heat.stars)
		self._heatStars.TextColor3 = if heat.stars > 0 then Color3.fromRGB(255, 70, 70) else Color3.fromRGB(170, 175, 185)
	end
	self._heatBonus.Text = string.format(cfg.BonusFormat, multiplierText(heat.multiplier))
	local t = math.clamp((now - (self._heatPop or -math.huge)) / 0.35, 0, 1)
	self._heatScale.Scale = 1 + 0.35 * (1 - t) * (1 - t)
end

function PoliceHudController._build(self)
	local hud = PoliceConfig.Hud
	local alert, bar = hud.Alert, hud.Bar

	local gui = Instance.new("ScreenGui")
	gui.Name = "PoliceHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = DISPLAY_ORDER
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	self:_buildVignette(gui)

	--[[ NOTHING HERE IS `Active`, which is the tutorial card's rule for the tutorial card's reason:
		this is drawn over a live game with a car being steered underneath it, and on a touch device
		the bottom of the screen is where the pedals are. A readout that ate a press would be a
		readout that occasionally cost somebody a run. ]]
	local alertLabel = Instance.new("TextLabel")
	alertLabel.Name = "Alert"
	alertLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	alertLabel.Position = UDim2.fromScale(0.5, alert.CentreY)
	alertLabel.Size = UDim2.fromScale(0.7, alert.Height)
	alertLabel.BackgroundTransparency = 1
	alertLabel.FontFace = FONT
	alertLabel.Text = ""
	alertLabel.TextColor3 = alert.ArmColor
	alertLabel.TextScaled = true
	alertLabel.TextTransparency = 1
	alertLabel.ZIndex = 3
	alertLabel.Parent = gui

	--- The pop rides a `UIScale` rather than the label's `Size`, which is the WRECKED banner's note:
	--- the label is `TextScaled`, so animating the box animates the font and the word re-flows in
	--- the middle of its own arrival.
	local alertScale = Instance.new("UIScale")
	alertScale.Parent = alertLabel

	local alertStroke = Instance.new("UIStroke")
	alertStroke.Color = Color3.fromRGB(8, 10, 14)
	alertStroke.Thickness = 3
	alertStroke.Transparency = 1
	alertStroke.Parent = alertLabel

	local sub = Instance.new("TextLabel")
	sub.Name = "AlertSub"
	sub.AnchorPoint = Vector2.new(0.5, 0)
	sub.Position = UDim2.fromScale(0.5, alert.CentreY + alert.Height * 0.55)
	sub.Size = UDim2.fromScale(0.5, alert.Height * 0.42)
	sub.BackgroundTransparency = 1
	sub.FontFace = FONT
	sub.Text = ""
	sub.TextColor3 = alert.SubColor
	sub.TextScaled = true
	sub.TextTransparency = 1
	sub.ZIndex = 3
	sub.Parent = gui

	local subStroke = Instance.new("UIStroke")
	subStroke.Color = Color3.fromRGB(8, 10, 14)
	subStroke.Thickness = 2
	subStroke.Transparency = 1
	subStroke.Parent = sub

	--- The trough IS the fill dimmed, so the two can never disagree about hue however the fill is
	--- retuned. Same trick and same shape as every other bar in this game.
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.fromScale(0.5, bar.CentreY)
	track.Size = UDim2.fromScale(bar.Size.X, bar.Size.Y)
	track.BackgroundColor3 = bar.SafeColor
	track.BackgroundTransparency = 1
	track.BorderSizePixel = 0
	track.ZIndex = 2
	track.Parent = gui

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(bar.CornerRadius, 0)
	trackCorner.Parent = track

	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color = bar.StrokeColor
	trackStroke.Thickness = bar.StrokeThickness
	trackStroke.Transparency = 1
	trackStroke.Parent = track

	--- The strike punch rides a `UIScale` rather than the trough's `Size`, for the alert's reason
	--- (see `alertScale`): the trough is positioned from its own centre and its fill, its corners
	--- and its stroke all size off it, so scaling the box would move four things and swell one.
	local trackScale = Instance.new("UIScale")
	trackScale.Parent = track

	--[[ The fill, held at the trough's exact size and cut by the gradient below. It is therefore
		one of the very few frames in this project that is anchored at its CENTRE and still behaves
		as an edge-driven bar: the edge is drawn rather than positioned, so the usual exception for
		fill bars does not apply to it. ]]
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0.5, 0.5)
	fill.Position = UDim2.fromScale(0.5, 0.5)
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = bar.SafeColor
	fill.BackgroundTransparency = 1
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(bar.CornerRadius, 0)
	fillCorner.Parent = fill

	local cut = Instance.new("UIGradient")
	cut.Rotation = 0 -- left to right: the bar empties from its right-hand end
	cut.Transparency = CUT_FULL
	cut.Parent = fill

	local label = Instance.new("TextLabel")
	label.Name = "BarLabel"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.fromScale(0.5, bar.CentreY - bar.Size.Y * 0.5 - bar.LabelGap)
	label.Size = UDim2.fromScale(0.3, bar.LabelHeight)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.Text = oneLine(bar.Label)
	self._labelText = bar.Label
	label.TextColor3 = bar.LabelColor
	label.TextScaled = true
	label.TextTransparency = 1
	label.ZIndex = 2
	label.Parent = gui

	local labelStroke = Instance.new("UIStroke")
	labelStroke.Color = Color3.fromRGB(8, 10, 14)
	labelStroke.Thickness = 2
	labelStroke.Transparency = 1
	labelStroke.Parent = label

	self._gui = gui
	self._alert = alertLabel
	self._alertScale = alertScale
	self._alertStroke = alertStroke
	self._sub = sub
	self._subStroke = subStroke
	self._track = track
	self._trackScale = trackScale
	self._trackStroke = trackStroke
	self._fill = fill
	self._cut = cut
	self._label = label
	self._labelStroke = labelStroke

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self:_fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		self:_fit()
	end)
end

function PoliceHudController._fit(self)
	local bar = PoliceConfig.Hud.Bar
	if NoticeLane.compact() then
		local viewport = workspace.CurrentCamera.ViewportSize
		local x = if viewport.X < 700 and viewport.Y <= viewport.X then 0.35 else 0.5
		-- The old 1.9%-high caption was seven pixels on a landscape phone (2026-10-12).
		self._track.Position = UDim2.new(x, 0, 0, 94)
		self._track.Size = UDim2.fromOffset(180, 10)
		self._label.Position = UDim2.new(x, 0, 0, 85)
		self._label.Size = UDim2.fromOffset(180, 18)
	else
		self._track.Position = UDim2.fromScale(0.5, bar.CentreY)
		self._track.Size = UDim2.fromScale(bar.Size.X, bar.Size.Y)
		self._label.Position = UDim2.fromScale(0.5, bar.CentreY - bar.Size.Y * 0.5 - bar.LabelGap)
		self._label.Size = UDim2.fromScale(0.3, bar.LabelHeight)
	end
end

-- === The alert ==============================================================

--[[ Put a word up. `_stepAlert` takes it away again on its own clock.

	Both announcements go through here because they are the same object saying two things, and the
	second one has to be able to interrupt the first: a chase short enough that LOST THEM lands
	while POLICE is still fading would otherwise draw them on top of each other. Setting the text
	and restarting the clock is what makes the newer one win outright. ]]
function PoliceHudController._say(self, text: string, subText: string, colour: Color3, hold: number)
	local cfg = PoliceConfig.Hud.Alert
	self._alert.Text = oneLine(text)
	self._alert.TextColor3 = colour
	self._sub.Text = if subText == "" then "" else oneLine(subText)
	self._alertUntil = os.clock() + hold
	self._alertPop = os.clock()
	self._alertScale.Scale = cfg.PopFrom
end

function PoliceHudController._stepAlert(self, now: number)
	local cfg = PoliceConfig.Hud.Alert

	--- The spring in, as a plain eased scale rather than a tween, so an alert replaced mid-pop
	--- simply restarts rather than leaving a stopped tween holding the label at 0.78.
	local popT = math.clamp((now - (self._alertPop or 0)) / math.max(cfg.PopTime, 1e-3), 0, 1)
	--- Overshoot and settle. One expression, and it is what gives the word its snap: the same shape
	--- `Enum.EasingStyle.Back` draws, written out so it can be sampled rather than played.
	local overshoot = 1 + (1 - popT) * (1 - popT) * (popT * 2.2 - 1) * 1.1
	self._alertScale.Scale = cfg.PopFrom + (1 - cfg.PopFrom) * math.min(overshoot, 1.12) * popT

	local left = (self._alertUntil or 0) - now
	local alpha = math.clamp(left / math.max(cfg.FadeTime, 1e-3), 0, 1)
	self._alert.TextTransparency = 1 - alpha
	self._alertStroke.Transparency = 1 - alpha
	local hasSub = self._sub.Text ~= ""
	self._sub.TextTransparency = if hasSub then 1 - alpha else 1
	self._subStroke.Transparency = if hasSub then 1 - alpha * 0.6 else 1
end

-- === The bar and the lights =================================================

--[[ One frame of the bar.

	IT LAGS THE REAL VALUE, unlike the car's HP bar and deliberately. HP is a reading you act on, so
	lag there is the bar lying about whether you are about to die; this is a bar whose input is a
	car's instantaneous speed, which is noisy by nature (every kerb, every gear of the torque curve)
	and would jitter visibly at the top of its range. A fifth of a second of smoothing costs nothing
	the player can act on, because the thing they act on is the throttle.

	The colour is the alarm. Green above `Warn`, red below it, and nothing flashes while everything
	is fine: a bar that pulsed for the whole chase would have nothing left to say when it mattered.

	AND THE ONE THING IT DOES SAY LOUDLY IS A CRASH. `struck` is seconds since the last strike took
	a bite (`PoliceController.reportStrike`), and inside `StrikeFlash.Time` the whole bar swells and
	the fill washes toward white. Without it the most important event in the beat is a pill getting
	shorter by a fifth of an inch, at the bottom of a screen the player is not looking at, on the
	one frame they are busy reacting to the thing they hit. The smoothing above makes that worse by
	design, so the punch is what carries it: the bar moves fast because it was HIT, not because the
	number changed. ]]
function PoliceHudController._stepBar(self, dt: number, bar: number, alpha: number, struck: number, lead: number)
	local cfg = PoliceConfig.Hud.Bar
	self._shown = approach(self._shown or 1, bar, 9, dt)
	local shown = self._shown

	--[[ ...and the one thing the fill cannot draw, because the fill is already full: whether the
		player is merely holding the police off or actually getting away from them
		(`PoliceConfig.Lead`). Written only when it CHANGES, because a `TextLabel.Text` assignment
		is a layout invalidation and this runs every frame of every chase.

		A flat threshold with no hysteresis is on purpose. The lead falls at
		`PoliceConfig.Lead.Drop`, which is under two seconds from full, so the caption cannot chatter
		across the line the way it could if the two rates were comparable; and `LeadFrom` sits far
		enough up the range that an ordinary lift for a corner does not reach it. ]]
	local wantLabel = if cfg.LeadLabel and lead >= (cfg.LeadFrom or 1) then cfg.LeadLabel else cfg.Label
	if wantLabel ~= self._labelText then
		self._labelText = wantLabel
		self._label.Text = oneLine(wantLabel)
	end

	local flash = cfg.StrikeFlash
	--- Linear decay off the clock rather than an eased tween off a state machine, because a punch
	--- can land on top of an unfinished punch (that is the chain) and a clock has no trouble with
	--- that: the second one simply restarts it.
	local punch = math.clamp(1 - struck / math.max(flash.Time, 1e-3), 0, 1) * alpha

	if math.abs(shown - (self._cutAt or -1)) > 0.002 then
		self._cutAt = shown
		self._cut.Transparency = cutAt(shown)
	end

	local colour = if shown > cfg.Warn then cfg.SafeColor else cfg.WarnColor
	--- The wash is applied to the FILL only and not to the trough, so the punch reads as the bar
	--- being struck rather than as the whole widget changing colour.
	self._fill.BackgroundColor3 = colour:Lerp(flash.Colour, punch)
	self._trackScale.Scale = 1 + flash.Scale * punch
	self._track.BackgroundColor3 =
		Color3.new(colour.R * cfg.TroughDarken, colour.G * cfg.TroughDarken, colour.B * cfg.TroughDarken)

	self._fill.BackgroundTransparency = 1 - alpha
	self._track.BackgroundTransparency = 1 - alpha
	self._trackStroke.Transparency = 1 - alpha
	self._label.TextTransparency = 1 - alpha
	self._labelStroke.Transparency = 1 - alpha * 0.7
end

--[[ The edge wash, and its whole job is to be absent most of the time.

	`From` is where it starts existing at all: above that bar value the four bands are fully
	transparent and the screen is untouched. Below it the tint ramps to `Max`, and it alternates
	with the SAME flash clock the light bars on the cruisers use, so the screen and the cars are
	blinking together rather than at two rates that beat against each other.

	`alpha` is the chase's own fade, so a wash that was up when a chase ends goes out with
	everything else instead of being left on the screen. ]]
function PoliceHudController._stepLights(self, bar: number, alpha: number, redLit: boolean)
	local cfg = PoliceConfig.Hud.Vignette
	if not self._tints then
		return
	end
	local intensity = math.clamp((cfg.From - bar) / math.max(cfg.From, 1e-3), 0, 1) * cfg.Max * alpha
	--- The heartbeat (`Vignette.Pulse`): a faint red on every edge for the whole of a live chase.
	local pulse = cfg.Pulse
	local beat = 0
	if pulse and pulse.Enabled then
		local wave = 0.5 + 0.5 * math.sin(os.clock() * 2 * math.pi / math.max(pulse.Period, 1e-3))
		beat = (pulse.Min + (pulse.Max - pulse.Min) * wave) * alpha
	end
	for _, tint in self._tints do
		--- The lit pair is at full intensity and the other pair at a fifth of it, rather than at
		--- nothing. Taking one pair to zero makes the screen look like it is being wiped from side
		--- to side; leaving a trace of the off colour reads as two lights, one of which is brighter.
		local lit = tint.red == redLit
		local wash = intensity * (if lit then 1 else 0.2)
		if beat > wash then
			tint.frame.BackgroundColor3 = cfg.Red
			tint.frame.BackgroundTransparency = 1 - beat
		else
			tint.frame.BackgroundColor3 = if tint.red then cfg.Red else cfg.Blue
			tint.frame.BackgroundTransparency = 1 - wash
		end
	end
end

-- === The loop ===============================================================

--[[ Everything, every frame, off one poll.

	It runs whenever a race is on rather than only during a chase, because the fades at both ends
	are frames in which `getChase()` already answers nil and there is still something on screen to
	take away. `_visible` is what carries that: it eases toward 1 while there is a chase and toward
	0 when there is not, and the whole overlay is disabled once it has arrived at 0 so a client not
	being chased is not drawing anything at all.

	TIMED ON THE WALL CLOCK, not on `TimeScale`. The thing it is drawing runs on real seconds
	(`PoliceConfig.Duration`), and a readout on a different clock from the event would drift away
	from it in front of the player. The fades and the pop are real-time for the same reason: they
	are chrome, not world motion. ]]
function PoliceHudController._loop(self, dt: number)
	local police = self._police
	local chase = police and police:getChase()
	local now = os.clock()
	--- First, and on its own screen: the heat outlives every chase in the run (`_buildHeat`).
	local heat = police and police.getHeat and police:getHeat()
	self:_stepHeat(heat, now)

	--- The two transitions this file cares about, both detected by comparing against the last frame
	--- rather than by subscribing to anything. See the header for why that is the point.
	local state = chase and chase.state or "off"
	if state ~= self._lastState then
		local cfg = PoliceConfig.Hud.Alert
		if state == "live" and self._lastState ~= "live" then
			--[[ The one thing the alert says differently, and the only reader of `reason` there is:
				a chase the player CAUSED says so, rather than teaching them a rule they are about
				to work out from the bar anyway (`PoliceConfig.StealHeat`, and `Hud.Alert`'s note on
				why the steal line is the shorter of the two). Falls back to the rule for any reason
				this file has not been told about. ]]
			local stolen = chase.reason == "steal"
			local sub = if stolen then cfg.StealSubText or cfg.ArmSubText else cfg.ArmSubText
			--- A chase a steal called in was already announced on the STOLEN! toast
			--- (`StealJuiceConfig.OneMoment.MergeHeat`); only a road chase gets the banner.
			if not (stolen and StealJuiceConfig.oneMoment("MergeHeat")) then
				self:_say(if stolen then cfg.StealText or cfg.ArmText else cfg.ArmText, sub, cfg.ArmColor, cfg.ArmHold)
				--- One big message at a time, and the danger first (`StealJuiceConfig.OneMoment.AlertCuts`).
				local toast = StealJuiceConfig.oneMoment("AlertCuts") and Shard.get("StealToastController")
				if toast then
					toast:dismiss()
				end
			end
			self._shown = 1
		elseif state == "leaving" then
			--- With heat, the escape says what it was worth: the bank's multiplier, now the truck can come.
			local sub = if heat and heat.earned > 0
				then string.format(PoliceConfig.Heat.LostSubText, multiplierText(heat.multiplier))
				else cfg.LostSubText
			self:_say(cfg.LostText, sub, cfg.LostColor, cfg.LostHold)
		end
		self._lastState = state
	end

	--[[ The bar is drawn for a LIVE chase only. During the peel-off there is no rule to report any
		more, so it fades with the alert rather than sitting at whatever it happened to be on when
		the police gave up. ]]
	--- Up for the arrest as well as for the chase. The PIT is the last two seconds of the rule
	--- being enforced, and a bar that faded out as the cruiser came in would take the answer off
	--- the screen on the frame it is finally given.
	local wanted = if state == "live" or state == "pit" then 1 else 0
	self._visible = approach(self._visible or 0, wanted, 1 / math.max(PoliceConfig.Hud.Bar.FadeTime, 1e-3), dt)
	local alpha = self._visible
	local alertLeft = (self._alertUntil or 0) - now

	if alpha < 0.004 and alertLeft < -PoliceConfig.Hud.Alert.FadeTime then
		if self._gui.Enabled then
			self._gui.Enabled = false
		end
		return
	end
	if not self._gui.Enabled then
		self._gui.Enabled = true
	end

	local bar = chase and chase.bar or 1
	--- The same clock the cruisers' light bars run on, read the same way, so the screen and the cars
	--- cannot fall out of step. It is one `math.floor`, so re-deriving it is cheaper than plumbing
	--- it across from the controller.
	local redLit = math.floor(now / math.max(PoliceConfig.Cruisers.FlashTime, 1e-3)) % 2 == 0

	self:_stepAlert(now)
	self:_stepBar(dt, bar, alpha, if chase then chase.struck else math.huge, if chase then chase.lead else 0)
	self:_stepLights(bar, alpha, redLit)
end

PoliceHudController:withLifecycle({
	init = function(self)
		self._visible = 0
		self._shown = 1
		self._lastState = "off"
		self._alertUntil = 0
		self._alertPop = 0
	end,

	start = function(self)
		if not (PoliceConfig.Enabled and PoliceConfig.Hud.Enabled) then
			return
		end
		self._police = Shard.get("PoliceController")
		if not self._police then
			self.log:warn("No PoliceController to read; the chase runs without its HUD.")
			return
		end

		--- Spawned rather than awaited: `_build` waits on PlayerGui and `Shard.start()` is the
		--- client's boot barrier, so blocking it would hold up every other controller behind one
		--- `WaitForChild`.
		task.spawn(function()
			self:_build()
			if PoliceConfig.Heat.Enabled then
				self:_buildHeat()
			end
			RunService.RenderStepped:Connect(function(dt)
				self:_loop(dt)
			end)
		end)
	end,
})

return PoliceHudController
