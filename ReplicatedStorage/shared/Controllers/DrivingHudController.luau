--[[
	DrivingHudController  (client)
	------------------------------
	The on-screen driving controls — two steering arrows and two pedals — plus the gauge cluster
	they sit beside.

	THE UI IS AUTHORED IN STUDIO, NOT HERE. It lives at `StarterGui.DrivingHud`, so its layout can
	be nudged in the Explorer without touching this file, and this controller only ever *finds* the
	instances and binds them. CarHudController is on the same contract twice over — `StarterGui.CarHud`
	for what is left in it (the WRECKED banner) and `StarterGui.CarHpBar` for the car's HP, which is
	a BillboardGui rather than a ScreenGui because it is no longer on the screen at all: it moved
	onto the car itself, so there is nothing up there left to collide with this cluster.

	If the GUI isn't there — a place that hasn't had the art imported yet — it warns once and does
	nothing at all. The race still runs, on the stock keyboard and touch controls.

	THE SPEEDO READS THE CAR, not this controller's input: speed comes off the VehicleSeat, flat.
	Suppressing the stock speedo that the CarBones kit deploys alongside it is here too, for the
	same reason: see _suppressStockSpeedo.

	THERE ARE TWO SPEEDOS AUTHORED AND ONE IS LIVE (`SpeedoConfig.Style`, and `_attachSpeedo` is
	where it is acted on). `Bar` is `SpeedoV2`, the minimal panel in the bottom-right corner: a
	number and a row of segments with a red band at the top, built by `BuildSpeedoV2`. `Dial` is the
	old `Cluster` — the half-gauge, the number and a gear off a simulated six-speed, the chassis
	having none of its own. The flag exists so the two can be looked at in one playtest and the
	loser deleted; it is the same bargain `NitroConfig.Hud.Layout` is on.

	NOTE THAT `Bar` HIDES THE CLUSTER'S ART AND NOT THE CLUSTER. The vertical nitro bar hangs off
	that frame and has to (`NitroConfig.Hud.Bars`), so hiding the frame would take the nitro with
	it. Moving the nitro up beside the new panel is the next job and not this one.

	THE CONTROLS ARE TOUCH-ONLY, the speedo is not. A keyboard player sees the speedo and nothing
	else — no arrows, no pedals and no action button (_applyTouchOnly) — and a touch player sees
	ONLY these, because the other two sets of driving controls on the screen are put away for the
	length of a race: Roblox's own thumbstick and jump button (_syncStockControls) and the CarBones
	kit's own accelerate/brake circles (_claimStockTouch). One set of driving controls, whichever
	device it is. Three owners, three places to look: ours is here, the kit's is inside the car model
	(place-side, not in git), Roblox's is in the PlayerModule.

	THE SIXTH BUTTON IS THE NITRO, and it is the only control here with a READOUT beside it. It is
	a plain hold, published straight at `NitroController:setHudHeld` rather than through
	DriveController, because nitro is not an axis on the stock chassis: it is a tank being spent,
	and the controller that owns the tank is the one that has to know a finger is down. Everything
	the player sees of that tank is the `Nitro` bar (`_stepNitro`), drawn here for the same reason
	the speedo is: the instances are authored in Studio and this file only fills them in.

	THE FIFTH BUTTON IS THE STEAL, AND IT IS TWO VERBS. A phone has no Space and no E, so the whole
	signature mechanic was unreachable on one: `Jump` is a single button that reads JUMP in the seat
	and swaps to STEAL the moment you are in the air over a car worth taking (_syncAction). It is a
	TAP rather than a hold, and it presses `StealController:bail()` / `:steal()` — the same two entry
	points the keys reach, guards included. The press re-asks which verb it is rather than trusting
	the face it last drew, so it always does what the game state says.

	AND ON A CONSOLE THERE ARE NO BUTTONS AT ALL, which is the gap the CONTROL LEGEND closes. Every
	control above is gated on `TouchEnabled` and a console is not a touch device, so a pad player
	was handed the gauge cluster and nothing else: no glyphs, no keycaps, no way to learn that L1 is
	the nitro or that A is the bail (Trello, "Console: no on-screen button prompts or controls").
	`Modules/ControlLegend` draws that as a panel in the bottom-left — see `_buildLegend` for what
	this controller owns of it, which is WHEN it is up, how long for, and what its one contextual
	row says. It is a KEYBOARD legend as well as a pad one since 2026-09-17 (Dylan), and the corner
	moved off the right in the same change to make room for the new speedo panel.

	The legend is a FOURTH thing on this screen and deliberately not a fourth OWNER: it binds
	nothing, sinks nothing and is not `Active`, so the three sets of controls above still argue only
	among themselves.

	WHY THE INPUT GOES THROUGH DriveController rather than at the chassis. The stock Driver already
	calls `UpdateThrottle` / `UpdateSteering` every input frame with the player's raw values, and
	DriveController already wraps both to reshape them. Publishing a virtual -1..1 into that same
	shim puts the buttons exactly where the keyboard and the stock touch stick already land — so
	boost, the brake floor and its fade, the lane-change easing, the heading cone and StealController's
	air control all apply to them for free. Nothing in this file knows anything about physics.

	The virtual input is SUMMED with the player's real input rather than overriding it (see
	DriveController._shapeSteer). Holding a key and the opposite button at once cancels, which is the
	honest reading of "both are held", and it means neither input source has to know the other exists.

	STEERING SIGN. `setHudSteer` is called with +1 meaning LEFT, in road terms, and DriveController
	converts that into whatever the rig's steering sign is via its own STEER_LEFT. The rig convention
	(DriveConfig.PositiveSteerIsLeft) therefore stays in exactly one file.

	MULTI-TOUCH is the one fiddly part, and it's why these are InputBegan/InputEnded rather than
	Activated. A finger that slides off a button never fires *that button's* InputEnded, so a
	per-button release alone leaves the pedal stuck down — the player is left braking forever. Every
	binding therefore also listens on UserInputService.InputEnded for the same InputObject, which
	fires wherever the finger actually ends up. The held set is keyed by InputObject rather than a
	boolean so two fingers on one button still release cleanly on the second lift.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local DriveConfig = require(ReplicatedStorage.shared.Configs.DriveConfig)
local AutomaticGearbox = require(ReplicatedStorage.shared.Modules.AutomaticGearbox)
local TutorialControlHighlight = require(ReplicatedStorage.shared.Modules.TutorialControlHighlight)
local ButtonScale = require(ReplicatedStorage.shared.Modules.ControlButtonScale)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local TrafficCollectionCue = require(ReplicatedStorage.shared.Modules.TrafficCollectionCue)
local ControlLegend = require(ReplicatedStorage.shared.Modules.ControlLegend)
local LegendConfig = require(ReplicatedStorage.shared.Configs.LegendConfig)
local NitroConfig = require(ReplicatedStorage.shared.Configs.NitroConfig)
local SpeedoConfig = require(ReplicatedStorage.shared.Configs.SpeedoConfig)
local StealConfig = require(ReplicatedStorage.shared.Configs.StealConfig)
--- The star timer's placement, fade and duration (`PickupConfig.StarTimer`), and its icon. CONFIGS,
--- not `StarController`, which is asked for `remaining()` through `Shard.get` at paint time.
local PickupConfig = require(ReplicatedStorage.shared.Configs.PickupConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
--- For the nitro hint's pad glyph: the stock art of the controller actually in hand (LB vs L1).
local GamepadInput = require(ReplicatedStorage.shared.Modules.GamepadInput)

local DrivingHudController = Shard.new("DrivingHudController"):withDependencies({
	"DriveController",
	"RoadController",
	"StealController",
	"NitroController",
	"TrafficController",
})

-- How long to wait for the authored GUI to replicate into PlayerGui before giving up on it.
-- Generous: it's a StarterGui clone, so it's there on the first frame or it isn't coming.
local GUI_WAIT = 10

-- The four buttons, and what each publishes. Steering is +1 = LEFT (see the header); throttle is
-- +1 = accelerate (which DriveController reads as boost) and -1 = brake.
local BUTTONS = {
	{ name = "SteerLeft", field = "_leftHeld", kind = "steer" },
	{ name = "SteerRight", field = "_rightHeld", kind = "steer" },
	{ name = "Gas", field = "_gasHeld", kind = "throttle" },
	{ name = "Brake", field = "_brakeHeld", kind = "throttle" },
}

-- === The speedo ==============================================================

-- Studs/s -> mph, the stock CarBones speedo's own conversion (it treats 28cm as a stud). Kept
-- across all three readouts so the number never changes meaning when one replaces another.
local MPH_PER_STUD = 0.6263

--[[ The speed the DIAL treats as "all six gears used". The bar readout does not use it — see
	`SpeedoConfig.ScaleTop`, which is a different number for a different question.

	It has to be a display constant rather than anything read off the rig, because the rig has no
	number that means this. DriveConfig (§MinSpeedFraction) spells out why: the car's `MaxSpeed`
	attribute is 40, `VehicleSeat.MaxSpeed` is in a different unit again, and the stock torque
	damping compares linear studs/s against an angular figure — so no number on the car is in mph.

	68 comes from measuring the Lambo in a playtest (2026-07-28): it cruises at 42–51 mph and
	peaks at 65 on boost. That puts cruise in 4th/5th and boost in 6th. A steal onto a faster
	tier just parks the cluster in top gear rather than reading wrong. If the drive tuning moves
	a long way, this is the one number to move with it. ]]
local TOP_MPH = DriveConfig.Gearbox.TopMph
local GEARS = DriveConfig.Gearbox.Gears

--[[ How far below a gear's floor the car has to fall before the box drops down, in gear-widths.
	Cruise wanders several mph either side of its equilibrium, so without this the readout hunts
	across a band edge a few times a second — which no automatic does, and which draws the eye
	exactly where it shouldn't be. ]]
local GEAR_HYSTERESIS = DriveConfig.Gearbox.DownshiftHysteresis

-- How fast the speed readout chases the car, per second. Landing instantly reads as a number
-- flickering rather than an instrument. One value for both readouts, so the dial and the bar can
-- never be seen to disagree about how quickly the car is speeding up.
local SPEED_LERP = SpeedoConfig.Lerp

-- The stock CarBones speedo, which both of ours replace. See _suppressStockSpeedo.
local STOCK_SPEEDO = "SpeedoFrame"

--[[ Every other on-screen control that lands in the same two corners, by instance name.

	`AccelerateButton` / `BrakeButton` are the CarBones kit's own touch pedals — a 70px and a 44px
	circle in the bottom-right, drawn UNDER ours because `VehicleGui` sits at DisplayOrder 0 and this
	HUD at 895. That is the "there are two of everything" a mobile playtester reported: our pedal on
	top of the kit's, with the kit's peeking out around the edges. `JumpButton` is Roblox's, from the
	PlayerModule's TouchJump, and it is worse than a duplicate — a jump while seated unseats you, and
	`RaceService._onRiderLeftSeat` correctly reads that as coming out of the car and ends the run.

	Latched rather than hidden once, and released rather than hidden for good: see _claimStockTouch. ]]
local STOCK_TOUCH = {
	AccelerateButton = true,
	BrakeButton = true,
	JumpButton = true,
}

local function approach(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

-- === Publishing ==============================================================

function DrivingHudController._publish(self)
	local drive = self._drive
	if not drive then
		return
	end

	local steer = 0
	if self._leftHeld then
		steer += 1
	end
	if self._rightHeld then
		steer -= 1
	end

	local throttle = 0
	if self._gasHeld then
		throttle += 1
	end
	if self._brakeHeld then
		throttle -= 1
	end

	drive:setHudSteer(steer)
	drive:setHudThrottle(throttle)

	--[[ Nitro goes to its own controller and not through the drive shim, because it is not one of
		the two axes the stock chassis takes. `_bindHold` gives it the same multi-touch handling the
		pedals get, which is what this call is doing inside `_publish` at all: one place where every
		held button is turned into the value somebody else reads. ]]
	local nitro = self._nitro
	if nitro then
		nitro:setHudHeld(self._nitroHeld)
	end
end

--[[ Drop everything that's held and publish the zero.

	Called whenever the HUD stops being the player's controls — race over, wrecked, or the controls
	hidden by the TouchOnly switch. Without it, a race that ends with the gas pedal held would leave
	a +1 sitting in DriveController for the *next* race, which would silently boost from the line. ]]
function DrivingHudController._clear(self)
	self._leftHeld = false
	self._rightHeld = false
	self._gasHeld = false
	self._brakeHeld = false
	self._nitroHeld = false
	for _, held in self._held do
		table.clear(held)
	end
	self:_publish()
end

-- === Binding =================================================================

--[[ Bind one button as a hold, tolerating the finger leaving it. `held` is a set of live
	InputObjects rather than a counter so a release can never take it negative and strand the
	button in the down state. ]]
function DrivingHudController._bindHold(self, button: GuiButton, field: string)
	local held = {}
	self._held[field] = held

	local function press(input: InputObject)
		if
			input.UserInputType ~= Enum.UserInputType.Touch
			and input.UserInputType ~= Enum.UserInputType.MouseButton1
		then
			return
		end
		if held[input] then
			return
		end
		held[input] = true
		self[field] = true
		self:_publish()
	end

	local function release(input: InputObject)
		if not held[input] then
			return
		end
		held[input] = nil
		if next(held) == nil then
			self[field] = false
			self:_publish()
		end
	end

	button.InputBegan:Connect(press)
	button.InputEnded:Connect(release)
	-- The safety net: fires wherever the finger ends up, including off the button entirely.
	UserInputService.InputEnded:Connect(release)
end

--[[ Bind one button as a TAP — fires on the way down and has nothing to release.

	`InputBegan` rather than `Activated` for two reasons. Activated wants a press AND a release on
	the same button, so a finger that lands and slides off does nothing at all — the same multi-touch
	problem `_bindHold` is built around, except a tap has no held state to strand, so the fix is
	simply to fire early. And a bail is a timing read: the arc should start on the frame the finger
	lands, which is the same call `StealConfig.Launch` makes about Space.

	No re-entrancy guard: `fn` is expected to be idempotent within a state (StealController's own
	`_canBail` refuses a second bail), and two fingers landing together on a 60px button is not a
	case worth carrying state for. ]]
function DrivingHudController._bindTap(self, button: GuiButton, fn: () -> ())
	button.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType ~= Enum.UserInputType.Touch
			and input.UserInputType ~= Enum.UserInputType.MouseButton1
		then
			return
		end
		fn()
	end)
end

-- === The cluster =============================================================

--[[ The car's VehicleSeat, which is where every number on the cluster comes from.

	Read off the car rather than out of DriveController on purpose: the cluster is a readout of
	the vehicle, so it keeps working with DriveConfig.Enabled off, and a steal that swaps what
	we're driving is picked up by the `Parent` check without anyone telling us. ]]
function DrivingHudController._vehicleSeat(self): VehicleSeat?
	local seat = self._seat
	if seat and seat.Parent then
		return seat
	end
	local car = self._road and self._road:getCar()
	local chassis = car and car:FindFirstChild("Chassis")
	seat = chassis and chassis:FindFirstChild("VehicleSeat")
	self._seat = seat
	return seat
end

--[[ PUBLIC (TutorialController): the speed the speedo is showing right now, smoothed exactly as the
	readout is, and the conversion it shows it in. The BOOST beat's speed bar reads these so its
	number and the speedo's can never disagree. ]]
function DrivingHudController.getMph(self): number
	return self._mph or 0
end

function DrivingHudController.toMph(self, studsPerSecond: number): number
	return studsPerSecond * MPH_PER_STUD
end

--[[ One frame of the speedo, whichever one is live.

	The gearbox is simulated and only the DIAL has one. The chassis has no gears at all; that
	readout exists so the dial's gear box has something to show, in six even bands across TOP_MPH
	shared with the engine note through `AutomaticGearbox` so the number and the shift you hear
	agree. The bar has no gear at all ("we arent gonna have gears", Aleafo) and skips the whole
	calculation, which is what the `_gearLabel` guard buys.

	Speed is measured FLAT (X/Z only). The magnitude the stock speedo used counts vertical
	velocity too, so every ramp spiked the readout by twenty-odd mph on the way down — which
	matters a lot more in this game than it did in the kit the speedo shipped with. ]]
function DrivingHudController._stepSpeedo(self, dt: number)
	local seat = self:_vehicleSeat()
	if not seat then
		return
	end

	--[[ AN ANCHORED CAR READS ZERO, whatever its velocity says.

		Anchoring does not clear `AssemblyLinearVelocity` — it stops the solver integrating it — so a
		held car reports the speed it was doing when it stopped, for as long as it is held. That is
		the correct thing for the physics to remember (the car resumes at that speed, and the bail
		seeds a flight's forward carry from it), and the wrong thing for a gauge to show: the
		tutorial's pause put a still road under a speedometer reading 32 MPH.

		So the DISPLAY is where it gets resolved, rather than by zeroing a number four other systems
		read. See `DriveController.setFrozen`, which used to do the latter. ]]
	local v = if seat.Anchored then Vector3.zero else seat.AssemblyLinearVelocity
	-- Getaway boarding is anchored but moving. Read its explicit presentation speed so the ramp
	-- handoff does not look like a stall; ordinary anchors (including tutorial holds) remain zero.
	local getaway = Shard.get("GetawayController")
	local boardingSpeed = getaway and getaway:getBoardingSpeed(seat)
	local mph = (boardingSpeed or Vector3.new(v.X, 0, v.Z).Magnitude) * MPH_PER_STUD

	self._mph = approach(self._mph, mph, SPEED_LERP, dt)

	--- Written only when the digits actually change, which is most frames at a stop and few of them
	--- at speed. A `Text` write is a layout invalidation whether or not the string differs.
	local shown = math.floor(self._mph + 0.5)
	local speedLabel = self._speedLabel
	if speedLabel and self._shownMph ~= shown then
		self._shownMph = shown
		speedLabel.Text = tostring(shown)
	end

	local gearLabel = self._gearLabel
	if gearLabel then
		-- Which gear. Gear `g` owns band [g-1, g); it shifts up the moment the band leaves the top
		-- of the current gear, and down only once it's a hair's breadth clear of the bottom
		-- (GEAR_HYSTERESIS).
		local gear = AutomaticGearbox.sample(mph, self._gear, TOP_MPH, GEARS, GEAR_HYSTERESIS)
		self._gear = gear
		gearLabel.Text = tostring(gear)
	end

	self:_lightSegments()
end

--[[ The bar's marks, lit from the left.

	THE TOP BAND IS DRAWN WHETHER OR NOT THE CAR HAS REACHED IT — dim red under the needle, hot red
	once it is in it — because the bar's job is to say how much is LEFT, not how far along the car
	is. See `SpeedoConfig.Bar`, which is where both pairs of colours live, and which band a mark is
	in is an attribute written at build time rather than a sum done here: a mark moved about in the
	Explorer then keeps the colours it was built with.

	ONE WRITE PER CHANGE OF TIP, not one per frame. Twenty `BackgroundColor3` writes every frame for
	a bar that moves a segment a second is the kind of cost that does not show up in a playtest and
	does show up on a phone. ]]
function DrivingHudController._lightSegments(self)
	local segments = self._segments
	if not segments then
		return
	end

	local bar = SpeedoConfig.Bar
	local fraction = math.clamp(self._mph / SpeedoConfig.ScaleTop, 0, 1)
	--- `bias` 0.5 is round-to-nearest, so the top-most lit mark is the one the speed is actually
	--- IN. 0 would light a mark on entering it and 1 only on filling it.
	local lit = math.clamp(
		math.floor(fraction * bar.Count + (1 - SpeedoConfig.SegmentBias)),
		0,
		bar.Count
	)
	if lit == self._segLit then
		return
	end
	self._segLit = lit

	for index, segment in segments do
		local on = index <= lit
		if segment:GetAttribute("Redline") == true then
			segment.BackgroundColor3 = if on then bar.RedlineLit else bar.RedlineUnlit
		else
			segment.BackgroundColor3 = if on then bar.Lit else bar.Unlit
		end
	end
end

-- === The nitro bar ===========================================================

--[[ The fill's leading edge, drawn as a step in the fill's own gradient rather than by resizing it.

	A BAR MADE BY SHRINKING A FRAME STOPS BEING A PILL the moment it is short. `UICorner`'s radius
	is taken against the frame's SHORTER side, so a fill at 10% has a cap radius a tenth of the one
	the trough behind it is drawn with: the fill flattens into a lozenge whose corners no longer
	follow the trough's rounded ends, and what should be a sliver sitting inside the pill reads as
	a slab poking out of its sides.

	Held at the trough's exact size and cut by transparency instead, the fill IS the trough's shape
	at every level, because its geometry never moves. What is left at 10% is the bottom cap of the
	same pill, sides and all.

	The step carries a hairline of ramp (`CUT_EDGE`) rather than being infinitely sharp. Zero width
	is not on offer — `NumberSequence` keypoints have to advance in time — and the hairline earns
	its keep anyway: on a 68px bar it is the only anti-aliasing the cut gets.

	OPTIONAL, and that is deliberate. The gradient lives in the place like the rest of this HUD, so
	a bar authored without one falls back to the size write below and still reads. ]]
local CUT_EDGE = 0.006
local CUT_EMPTY = NumberSequence.new(1)
local CUT_FULL = NumberSequence.new(0)

--- The trough behind a fill, and the ring's track behind its arc: the lit colour, dimmed. One
--- helper for both so nothing on this HUD can dim a readout by a different rule than its neighbour.
local function dimmed(color: Color3, by: number): Color3
	return Color3.new(color.R * by, color.G * by, color.B * by)
end

--[[ The badge arc at `swept` (0..1, clockwise from twelve): the two half-rings' cuts. Shared by the
	nitro badge and its star clone (`_buildStarBadge`), so the two rings can never be drawn by
	different rules. `_paintBadge`'s header explains the halves. ]]
local function sweepArc(badge, swept: number)
	local hand = swept * 360
	--- The right half's element is turned 180 so one upload can draw both halves, and a
	--- gradient turns with the element it is on, so its cut is turned back by that 180.
	if badge.rightCut then
		badge.rightCut.Rotation = hand - 180
		badge.rightCut.Enabled = swept < 0.5
	end
	if badge.leftCut then
		badge.leftCut.Rotation = hand
	end
	badge.left.Visible = swept > 0.5
end

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

--[[ One frame of the bottle, whichever shape is drawing it.

	THIS FUNCTION WORKS OUT THE READING AND NOTHING ELSE. What the tank is, what colour that makes
	it, whether it is breathing and whether it just became usable again are the same answers for a
	bar and for a badge, so they are settled once here and handed to `_paintBar` or `_paintBadge`.
	Two readouts that computed their own state would eventually disagree about it.

	Three colours for three things a player has to tell apart without looking: the resting blue,
	the hot core while it is alight, and the dim blue-grey below `Tank.MinToFire`, which is the one
	that matters most because it is the only state in which pressing the button does nothing. The
	trough behind the fill, and the track behind the badge's arc, are that colour dimmed, which is
	the trick the HP bar uses so the two halves of a readout can never disagree about hue.

	THE FILL CHASES rather than snapping, unlike the HP bar's, and the difference is what each is
	for. HP is a reading you act on, so a fifth of a second of lag is a fifth of a second in which
	the bar lies about whether you are about to die. A bottle is a resource you plan with, and the
	near miss that pays it back arrives as a step function: snapped, the bar teleports and the eye
	misses the payout entirely, which is exactly the feedback the reward exists to give.

	The white flash is the one event in here. It fires once, on the frame the tank crosses back over
	`MinToFire`, because "you can use it again" is the only thing about a refill worth interrupting
	someone for. Everything else about the refill is just the bar getting longer. ]]
function DrivingHudController._stepNitro(self, dt: number)
	local nitro, fill = self._nitro, self._nitroFill
	--[[ EITHER SHAPE WILL DO. The badge has no `Fill` frame at all — its reading is an arc and a
		liquid level rather than a rectangle's width — so a guard on the fill alone would leave the
		badge parked at whatever the builder drew it at for the whole race. ]]
	local badge = self._nitroBadge
	if not (nitro and (fill or badge)) then
		return
	end
	local hud = NitroConfig.Hud
	local tank, burning, ready = nitro:getTank(), nitro:isBurning(), nitro:canFire()

	self._nitroShown = approach(self._nitroShown, tank, hud.FillLerp, dt)
	local shown = self._nitroShown
	local color = if burning then hud.BurningColor elseif ready then hud.ReadyColor else hud.LowColor

	--[[ The pulse while alight. A cosine rather than a square wave, and shallow: this is a bar
		breathing, not a warning light. It rides on transparency instead of on colour so it cannot
		fight the three states above for the same property. ]]
	local alpha = 0
	if burning and hud.BurnPulse > 0 then
		alpha = hud.BurnPulse * 0.5 * (1 - math.cos(os.clock() * hud.BurnPulseHz * math.pi * 2))
	end

	if badge then
		self:_paintBadge(shown, color, burning, alpha, dt)
	elseif fill then
		self:_paintBar(fill, shown, color, alpha)
	end

	-- `nil` on the first frame of a race rather than false, so a run that starts with a full tank
	-- does not flash at the line for a threshold it was never below.
	if self._nitroReady == false and ready and hud.ReadyFlash > 0 then
		self._nitroFlashFor = hud.ReadyFlash
	end
	self._nitroReady = ready

	local flash = self._nitroFlash
	if flash then
		self._nitroFlashFor = math.max((self._nitroFlashFor or 0) - dt, 0)
		local t = if hud.ReadyFlash > 0 then self._nitroFlashFor / hud.ReadyFlash else 0
		flash.BackgroundTransparency = 1 - t * 0.75
	end

	if self._nitroAmount then
		self._nitroAmount.Text = string.format("%d%%", math.floor(tank * 100 + 0.5))
	end
end

--[[ One frame of the BAR: the pill, its trough and the step that cuts it.

	Split out of `_stepNitro` when the badge arrived. Everything above the split is the READING
	(what the tank is, what colour that makes it, whether it is breathing) and everything in here
	and in `_paintBadge` is one shape's opinion about how to show it. Neither painter decides
	anything; between them they cannot disagree about the state, because they are handed it. ]]
function DrivingHudController._paintBar(self, fill: GuiObject, shown: number, color: Color3, alpha: number)
	local cut = self._nitroCut
	if cut then
		-- Guarded on movement, not written every frame: the tank spends most of a race parked at
		-- one end, and a settled bar has no business rebuilding a sequence sixty times a second.
		-- A fifth of a pixel on the tallest bar this HUD has, so nothing visible is skipped.
		if math.abs(shown - self._nitroCutAt) > 0.002 then
			self._nitroCutAt = shown
			cut.Transparency = cutAt(shown)
		end
	else
		-- The only thing the two layouts disagree about at runtime. The vertical bar's Fill is
		-- authored anchored at its BOTTOM, so growing it upward is a size write and nothing else.
		fill.Size = if self._nitroVertical then UDim2.fromScale(1, shown) else UDim2.fromScale(shown, 1)
	end

	fill.BackgroundColor3 = color
	if self._nitroTrough then
		self._nitroTrough.BackgroundColor3 = dimmed(color, NitroConfig.Hud.TrackDim)
	end
	fill.BackgroundTransparency = alpha
end

--[[ One frame of the BADGE: the arc around it, the liquid in it, and the bloom behind it.

	=== THE ARC IS ONE NUMBER PER HALF ======================================================

	Half a ring, twice, each pinned in place with a hard-stepped `UIGradient` on it. A gradient cuts
	along a line through the middle of the element it sits on, so its ROTATION is the hand of the
	clock and the art either side of that line is what survives. `BuildNitroBadge` draws the
	geometry and argues why it is built this way rather than by clipping something rotated.

	So a tank of `t` is one angle, `t * 360` clockwise from twelve, and the two halves divide it:

	  Right  carries the first half, twelve round to six. Its cut turns with the tank until the
	         halfway mark, and past it the cut is switched OFF: the whole half is lit, which is not
	         the same instruction as "a cut that happens to keep all of it".
	  Left   carries the second half, six round to twelve, and is taken away below halfway. A cut
	         keeps a half-plane, and below halfway the half-plane it would keep reaches back over
	         twelve into the part of the left half that has not been earned yet.

	`Style` decides which of the two shapes carries the reading, and the other is pinned at full
	rather than hidden: a ring that vanished in Fill mode would leave the bottle floating in a
	plate, and the rim is what makes the badge a badge.

	=== WHY THE WRITES ARE GUARDED ==========================================================

	Not for the cost of a float, which is nothing, but for the `NumberSequence` the liquid's cut
	rebuilds beside it. The same 0.002 gate the bar's cut uses and for the same reason: it is well
	under a pixel on a badge this size, and a tank spends most of a race parked at one end. ]]
function DrivingHudController._paintBadge(self, shown: number, color: Color3, burning: boolean, alpha: number, dt: number)
	local badge = self._nitroBadge
	if not badge then
		return
	end
	local cfg = NitroConfig.Hud.Badge
	local style = cfg.Style
	--- The ring reads in `Ring` and `Both`, the liquid in `Fill` and `Both`. Whichever is not
	--- reading sits at full, which is also exactly what a fresh full tank looks like.
	local swept = if style == "Fill" then 1 else shown
	local level = if style == "Ring" then 1 else shown

	if badge.right and badge.left then
		if math.abs(swept - (self._nitroArcAt or -1)) > 0.002 then
			self._nitroArcAt = swept
			sweepArc(badge, swept)
		end
		badge.right.ImageColor3 = color
		badge.left.ImageColor3 = color
	end
	if badge.track then
		badge.track.ImageColor3 = dimmed(color, cfg.RingDim)
	end

	if badge.cut and math.abs(level - self._nitroCutAt) > 0.002 then
		self._nitroCutAt = level
		badge.cut.Transparency = cutAt(level)
	end
	if badge.liquid then
		badge.liquid.ImageColor3 = color
		--- The liquid breathes on the burn the way the bar's fill does, so the two readouts are
		--- the same animation wearing different geometry.
		badge.liquid.ImageTransparency = alpha
	end
	if badge.well then
		badge.well.ImageColor3 = dimmed(color, cfg.WellDim)
	end

	--[[ The bloom, EASED rather than switched. A burn ends the instant the key comes up and a glow
		that vanished with it would read as a bulb blowing; the tank's own fill is already chasing
		for the same reason. It rides the pulse on top so the bloom breathes with the liquid. ]]
	if badge.glow then
		local want = if burning then cfg.Glow.Max + alpha * 0.5 else 1
		self._nitroGlowAt = approach(self._nitroGlowAt or 1, want, 9, dt)
		badge.glow.ImageColor3 = color
		badge.glow.ImageTransparency = self._nitroGlowAt
	end
end

--[[ Which verb the action button is offering this frame, and the face that says so.

	Polled, not pushed. There is no event for "the nearest car came into range" — it is a distance
	that changes continuously through the flight — and `StealController:canSteal()` reads the very
	same `_candidate` the billboard over the car is adorned to, so polling both off one field per
	frame is what guarantees the button and the prompt cannot advertise different things.

	Guarded on a change so the three `Image` writes happen on the two frames the verb actually flips
	rather than every frame of a race. The faces come off the instance (the STEAL ones as attributes,
	see `_attach`), so re-skinning either verb stays a Studio edit like the rest of this HUD. ]]
function DrivingHudController._syncAction(self)
	local button = self._action
	if not button then
		return
	end
	local steal = self._steal ~= nil and self._steal:canSteal()
	if self._actionSteal == steal then
		return
	end
	self._actionSteal = steal
	self._pulseFrom = os.clock()
	local face = if steal then self._stealFace else self._jumpFace
	button.Image, button.HoverImage, button.PressedImage = face[1], face[2], face[3]
end

--[[ The swell while the button is offering STEAL (`StealConfig.ThumbPulse`). Every frame rather than
	on the flip, because it is a motion; it starts from rest on the frame the face changes, so the
	first thing the swap does is not a jump in size. ]]
function DrivingHudController._pulseAction(self)
 local action = self._action
 if not (action and self._actionPulse) then return end
 local cfg = StealConfig.ThumbPulse
 if not (cfg.Enabled and (self._actionSteal or self._jumpReminder)) then
  ButtonScale.set(action, "Action", 1)
  return
 end
 local t = os.clock() - (self._pulseFrom or 0)
 local pulse = 1 + (cfg.Scale - 1) * (0.5 - 0.5 * math.cos(t * cfg.Rate * 2 * math.pi))
 ButtonScale.set(action, "Action", pulse)
end

-- === The control legend ======================================================

--[[ Which of the legend's rows describe a mechanic that is switched ON, because a legend that
	advertises a disabled verb is worse than one that is a row shorter.

	The same rule `_attach` already applies to the action button ("a control that does nothing when
	pressed is worse than one that is not there"), applied to the thing that TELLS you about the
	control. Keyed by the row's `id` rather than by position, so re-ordering `LegendConfig.Driving`
	cannot silently re-point a switch at the wrong row. ]]
local LEGEND_GATES: { [string]: () -> boolean } = {
	Nitro = function()
		return NitroConfig.Enabled
	end,
	Action = function()
		return StealConfig.Enabled
	end,
}

--[[ Build the driving legend, once, for the session.

	IT IS NOT PART OF `StarterGui.DrivingHud` and could not be. Everything in that ScreenGui is
	authored art this controller finds and binds (the header's first paragraph), and the legend is a
	list whose length depends on which mechanics are switched on and whose glyphs depend on the
	CONTROLLER BRAND in the player's hands. There is nothing for an artist to author.

	IT TAKES ITSELF AWAY, and this controller does not own that. `LegendConfig.HoldSeconds` retires
	the panel a few seconds into a run — a control legend that never leaves is a menu footer, not a
	gameplay HUD, and the one verb worth prompting mid-run is already prompted on the car itself.
	The timer lives in `ControlLegend` rather than here because it has to survive things this
	controller cannot see: a pad plugged in after the window has closed re-opens it, which is a
	device change, which the legend is already subscribed to and this is not.

	Built even on a device that will never show it. `ControlLegend` owns the device question in
	full — it re-asks on every change, so a pad picked up in the middle of a run brings the legend
	in on its own — and building it lazily on the first gamepad input would mean a player who plugs
	one in mid-race waits for a build instead of seeing it. It is one hidden ScreenGui. ]]
function DrivingHudController._buildLegend(self)
	local entries = {}
	for _, entry in LegendConfig.Driving do
		local gate = LEGEND_GATES[entry.id]
		if not gate or gate() then
			--- Copied rather than referenced: `setRowLabel` writes onto the entry it was given, and
			--- the Action row is rewritten twice a flight. The config table is shared module state
			--- and a second legend built later must not inherit whatever this one last said.
			table.insert(entries, {
				id = entry.id,
				label = entry.label,
				keys = entry.keys,
				keyboard = entry.keyboard,
			})
		end
		--- The bail half of the two-verb row, kept so `_syncLegend` can put it back. Held by ID
		--- rather than by position: the row is last in the config today and the moment someone adds
		--- a sixth verb under it, an index would quietly start swapping the wrong row.
		if entry.id == "Action" then
			self._legendBail = entry
		end
	end

	self._legend = ControlLegend.new({
		name = "DrivingLegend",
		title = LegendConfig.Title.Text,
		entries = entries,
	})
end

--[[ The one row on this legend that changes during a run, and the one that dims.

	BAIL AND STEAL ARE ONE ROW, and the row says exactly what the action button's face says, because
	both are asked off the same `canSteal()` on the same frame — see `_syncAction`'s note on why
	that question is polled rather than pushed. Two readouts of the same verb that could disagree
	would be worse than one, so they are guarded on the same latch: `_syncAction` writes
	`_actionSteal` and this reads it, which also means the two `setRowLabel` calls a flight happen
	on the frames the verb flips rather than every frame of a race.

	THE NITRO ROW DIMS BELOW THE FIRING FLOOR, which is the one piece of this legend that answers a
	question the player is actually asking mid-race: `NitroConfig.Tank.MinToFire` means a
	nearly-empty bottle will not light at all, and without this the honest player experience is
	pressing L1 and having nothing happen. `setRowActive` is idempotent, so calling it per frame
	costs a comparison. ]]
function DrivingHudController._syncLegend(self)
	local legend = self._legend
	if not legend then
		return
	end

	if self._legendSteal ~= self._actionSteal and self._legendBail then
		self._legendSteal = self._actionSteal
		local entry = if self._actionSteal then LegendConfig.DrivingSteal else self._legendBail
		legend:setRowLabel("Action", entry.label, entry.keys, entry.keyboard)
	end

	if self._nitro and NitroConfig.Enabled then
		legend:setRowActive("Nitro", self._nitro:getTank() >= NitroConfig.Tank.MinToFire)
	end
end

function DrivingHudController._runFrame(self, on: boolean)
	if self._clusterConn then
		self._clusterConn:Disconnect()
		self._clusterConn = nil
	end
	if not on then
		--- The star timer goes with the run, at once: the loop that would fade it is stopping, and a
		--- badge left lit would open the next race showing a star nobody has.
		local star = self._starBadge
		if star then
			star.shown = 0
			star.arcAt = -1
			star.frame.Visible = false
		end
		self._jumpReminder = false
		if self._tutorialHighlight then self._tutorialHighlight:step(nil,false) end
		self._actionSteal = nil
		self._legendSteal = nil
		self:_pulseAction()
		return
	end
	-- Re-resolved per race: the seat and car both die with the race that made them.
	self._seat = nil
	self._mph, self._gear = 0, 1
	--- Both `nil` rather than 0 on purpose: they are "what is on screen", and the first frame of a
	--- race has to write whatever the last one left there rather than assume it agrees.
	self._shownMph = nil
	self._segLit = nil
	-- The bar starts wherever the tank actually is rather than at zero, so a run does not open with
	-- the bottle visibly filling itself. `nil` on the ready flag for the reason `_stepNitro` gives.
	self._nitroShown = if self._nitro then self._nitro:getTank() else 0
	self._nitroCutAt = -1 -- out of range on purpose: the first frame of a race always writes.
	self._nitroArcAt = nil -- ...and the same for the badge's arc.
	self._nitroReady = nil
	self._nitroFlashFor = 0
	-- `nil` rather than false, so the first `_syncAction` writes the face instead of assuming the
	-- one left on the button by the previous race is the right one.
	self._actionSteal = nil
	--- ...and the same for the legend's copy of that verb, which is a separate latch because the
	--- legend can be built on a place whose HUD has no action button to latch at all.
	self._legendSteal = nil
	self:_syncAction()
	self:_syncLegend()
	self._clusterConn = RunService.RenderStepped:Connect(function(dt)
		-- Before the cluster, which returns early when there is no seat to read — and there is no
		-- seat to read for the whole flight, which is exactly when this button has something to say.
		self:_syncAction()
		if self._collectionCue then
			self._jumpReminder = self._collectionCue:step(self._road, self._traffic, self._steal, self._drive._baseMaxSpeed or 0)
		end
		self:_pulseAction()
		--- After it, and never before: the legend's action row is guarded on the latch `_syncAction`
		--- writes, so reading it first would leave the legend one frame behind the button's face.
		self:_syncLegend()
		self:_stepSpeedo(dt)
		-- ...and outside it for the same reason: the bottle is still there through a bail, and a bar
		-- that froze for the length of a flight would look broken at exactly the moment the player
		-- is deciding whether to take the car in front.
		self:_stepNitro(dt)
		self:_layoutTimers()
		self:_stepStar(dt)
		self:_stepNitroHint()
		if self._tutorialHighlight then
			--- On the arrow's bob clock, so the swell and the bob move together. See `TutorialController.bobClock`.
			local tutorial = Shard.get("TutorialController")
			self._tutorialHighlight:step(Players.LocalPlayer:GetAttribute(TutorialConfig.StepAttribute), self:_wantsThumbControls(), if tutorial then tutorial:bobClock() else nil)
		end
	end)
end

--[[ Hide the speedo the CarBones kit brings with it, wherever it turns up.

	The kit's `LocalVehicleGui` lives in the car model, and RaceService deploys a clone of the
	car's whole Scripts folder into a ScreenGui under PlayerGui — so the stock speedo renders,
	bottom-centre, exactly where the new cluster sits. Same reason DriveController wraps the stock
	chassis instead of editing it: those scripts live in the place, not in git, and every car model
	and every future redress carries its own copy, so a fix applied there is five hand-edits that a
	fresh CarBones import silently reverts.

	Only the speedo. The kit's other always-on screen furniture is its touch ExitButton, and that
	one is already claimed — DriveController._holdSeat latches it away for the length of a race so
	nobody can get out mid-run, on every device. A second latch here would fight its restore.

	It has to survive being turned back on, not just be hidden once. The Driver LocalScript calls
	`VehicleGui:EnableSpeedo()` during its setup, which sets Visible = true — after the frame is
	parented, so hiding it on DescendantAdded alone loses the race every time. Latching the
	property is deterministic where a deferred hide would be a guess about when setup finishes.
	The connections die with each race's deployed controls, so nothing accumulates. ]]
function DrivingHudController._suppressStockSpeedo(self, playerGui: Instance)
	local function claim(inst: Instance)
		if inst.Name ~= STOCK_SPEEDO or not inst:IsA("GuiObject") then
			return
		end
		inst.Visible = false
		inst:GetPropertyChangedSignal("Visible"):Connect(function()
			if inst.Visible then
				inst.Visible = false
			end
		end)
	end
	for _, descendant in playerGui:GetDescendants() do
		claim(descendant)
	end
	playerGui.DescendantAdded:Connect(claim)
end

--[[ Put the OTHER two sets of touch buttons away while ours are up, and give them back after.

	`STOCK_TOUCH` says which and why. Three things about how, each of which is a way this goes wrong:

	1. LATCHED, not hidden once — the same trap `_suppressStockSpeedo` and `DriveController._holdSeat`
	   both sit in. `VehicleGui:DisplayTouchDriveControls` sets its two buttons visible during setup,
	   *after* they are parented, and RaceService re-deploys the car's whole Scripts folder on every
	   race and every re-seat; TouchJump likewise sets `Visible = true` from inside its own `Enable`.
	   A single hide loses that race, silently, and only on the device that has the buttons.

	2. SCOPED to our controls being up, not to the session. The kit's accelerate/brake circles ARE
	   the controls for the lobby car, which this HUD never shows for — hiding them for good would
	   leave a phone unable to drive it. So this is claimed and released like the seat lock, and
	   released restores what each button was rather than forcing it true.

	3. RELEASED BY VALUE, so a device the kit never drew a button on does not get one handed to it.

	Cheaper than fighting the PlayerModule for the jump button, and version-proof in a way that
	matters: `ControlModule:Disable()` is supposed to take TouchJump down with the thumbstick, and on
	the Android build a playtester filmed it plainly did not — the thumbstick went and the jump button
	stayed, sitting under the gas pedal. Hiding the instance does not care which is true. ]]
function DrivingHudController._claimStockTouch(self, on: boolean)
	if self._touchClaimed == on then
		return
	end

	if not on then
		self._touchClaimed = false
		for _, conn in self._touchConns do
			conn:Disconnect()
		end
		table.clear(self._touchConns)
		for button, wasVisible in self._stockTouch do
			if button.Parent then
				button.Visible = wasVisible
			end
		end
		table.clear(self._stockTouch)
		return
	end

	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return -- claim nothing rather than latch nothing; the next sync tries again
	end
	self._touchClaimed = true

	local function claim(inst: Instance)
		if not (STOCK_TOUCH[inst.Name] and inst:IsA("GuiObject")) or self._stockTouch[inst] ~= nil then
			return
		end
		self._stockTouch[inst] = inst.Visible
		inst.Visible = false
		table.insert(
			self._touchConns,
			inst:GetPropertyChangedSignal("Visible"):Connect(function()
				if inst.Visible and self._touchClaimed then
					inst.Visible = false
				end
			end)
		)
	end
	for _, descendant in playerGui:GetDescendants() do
		claim(descendant)
	end
	-- The car's controls are deployed a beat after RaceStart and again on every re-seat, and
	-- TouchJump builds its button the first time it is enabled — so most of what this hides does
	-- not exist yet when the claim is made.
	table.insert(self._touchConns, playerGui.DescendantAdded:Connect(claim))
end

-- === Visibility ==============================================================

--[[ The mobile switch. The arrows and pedals are FOR touch, so touch is the only place they show:
	a keyboard player steers with the keys and gets a clear screen, which is the whole point of the
	gate. Set `TouchOnly = false` on the ScreenGui to force them on everywhere instead — an override
	kept for Studio, where clicking a pedal is the quickest way to exercise the touch path.

	`TouchEnabled` and not the stricter "touch and no keyboard" that DriveController reads for its
	handling tuning: this is about what's on the screen, and Studio's device emulator sets
	TouchEnabled while leaving KeyboardEnabled true, so the strict test would make the mobile layout
	impossible to look at without a phone. The cost is that a touchscreen laptop also gets the
	buttons, which is the right answer for a device that can actually press them.

	Only the Controls frame is gated. The gauge cluster is a readout, not an input, and there's no
	reason to hide it from anyone. ]]
--[[ Is this a device that should be SHOWN thumb controls right now?

	THE OLD TEST WAS `TouchEnabled` ALONE, and the note above records the cost it accepted: "a
	touchscreen laptop also gets the buttons, which is the right answer for a device that can
	actually press them". It is not the right answer. A touchscreen laptop is a keyboard machine
	that happens to have a screen you can poke, and its owner drives with the keys — so the pedals
	and arrows are clutter sitting over the road, and they were reported as a bug.

	The stricter "touch and no keyboard" was rejected for a real reason, which this keeps: Studio's
	device emulator sets `TouchEnabled` while leaving `KeyboardEnabled` true, so the strict test
	makes the mobile layout impossible to look at without a phone.

	SO THE QUESTION IS NOT WHAT THE DEVICE HAS, IT IS WHAT THE PLAYER IS USING, and Roblox answers
	that directly. Three cases, and each falls out of one rule:

	  • No touch at all -> never. Unchanged.
	  • Touch and no keyboard -> always. A phone has nothing else to drive with, and this must not
	    depend on `LastInputType`, which passes through `Focus` and `TextInput` on a real device and
	    would blink the controls out mid-run.
	  • BOTH -> follow the last input. Type on the laptop and the buttons go; tap the screen and
	    they come back. This is also what fixes Studio, for free and without a special case: the
	    emulator delivers genuine `Touch` input, so clicking in it shows the mobile layout exactly
	    as it always did. ]]
function DrivingHudController._wantsThumbControls(self): boolean
	if not UserInputService.TouchEnabled then
		return false
	end
	if not UserInputService.KeyboardEnabled then
		return true
	end
	return UserInputService:GetLastInputType() == Enum.UserInputType.Touch
end

--[[ Should the KIT's touch furniture be held down? Deliberately a different question from the one
	above, and separating the two is what stops this fix trading one set of buttons for another.

	`_syncStockControls` used to key off our own controls being up, which was the same answer while
	the only way to hide ours was to be on a desktop. It no longer is: a keyboard player on a touch
	laptop now hides ours, and under the old rule that would RELEASE the kit's accelerate/brake
	circles and re-enable the PlayerModule's TouchJump — handing them a different set of thumb
	buttons instead of a clean screen.

	During a race on any touch-capable device, nobody wants the kit's controls: either ours are up
	and win, or the player is on the keyboard and wants neither. Outside a race they are how a phone
	drives the lobby car, which is why this is bracketed on the race and not switched off for good. ]]
function DrivingHudController._touchSuppressed(self): boolean
	return UserInputService.TouchEnabled and self._gui ~= nil and self._gui.Enabled
end

--[[ 2026-10-12: Phone readouts belong between the thumb controls, not over the pedals.
	Keep the authored geometry so hybrid devices regain the desktop layout when using keys.
	Scale sizes retain the existing aspect constraints and follow viewport/orientation changes. ]]
function DrivingHudController._layoutReadouts(self, mobile: boolean)
	if self._readoutMobile == mobile then return end
	if not self._readoutLayouts then
		self._readoutLayouts = {}
		--- The nitro badge only while the powerup row is off: with it on, the row places the badge
		--- (`_layoutTimers`) and two writers on one frame's Size would fight every frame.
		for _, name in if PickupConfig.TimerRow.Enabled then { SpeedoConfig.FrameName } else { SpeedoConfig.FrameName, "NitroBadge" } do
			local frame = self._gui:FindFirstChild(name)
			if frame and frame:IsA("GuiObject") then
				table.insert(self._readoutLayouts, {
					frame = frame, anchor = frame.AnchorPoint, position = frame.Position, size = frame.Size,
				})
			end
		end
	end
	self._readoutMobile = mobile
	for _, layout in self._readoutLayouts do
		local frame = layout.frame
		if mobile then
			local speedo = frame.Name == SpeedoConfig.FrameName
			frame.AnchorPoint = Vector2.new(if speedo then 1 else 0, 1)
			-- Six pixels either side of the join; fourteen above the bottom keeps rims clear.
			frame.Position = UDim2.new(0.55, if speedo then -6 else 6, 1, -14)
			frame.Size = if speedo then UDim2.fromScale(0.30, 0.16) else UDim2.fromScale(0.16, 0.16)
		else
			frame.AnchorPoint, frame.Position, frame.Size = layout.anchor, layout.position, layout.size
		end
	end
end

function DrivingHudController._layoutSteering(self, mobile: boolean)
 -- Small-screen Nitro gets the same enlargement as steering; all pulse channels remain independent.
 for _,name in { "SteerLeft", "SteerRight", "Nitro" } do
  local button = self._controls:FindFirstChild(name)
  if button and button:IsA("GuiButton") then
   ButtonScale.set(button, "Mobile", if mobile then 1.3 else 1)
  end
 end
end

function DrivingHudController._applyTouchOnly(self)
	local gui, controls = self._gui, self._controls
	if not (gui and controls) then
		return
	end
	local mobile = self:_wantsThumbControls()
	local visible = mobile or gui:GetAttribute("TouchOnly") == false
	self:_layoutReadouts(mobile)
	self:_layoutSteering(mobile)
	self:_syncArrows()
	if controls.Visible ~= visible then
		controls.Visible = visible
		if not visible then
			self:_clear() -- a hidden button can never fire its own InputEnded
		end
	end
	self:_syncStockControls()
end

--[[ PUBLIC (StealController): the player is in the air, or not (2026-10-20: "hide the left/right arrows
	and brake/accelerate while flying, and re-enable the joystick so the player can fly around ... full
	control of their flight"). On a thumb device only: the arrows and pedals hide, and Roblox's own
	thumbstick comes back (`_syncStockControls`), which `StealController._flightStick` reads for the
	flight across and along the road. The car is suspended for the whole flight, so the stick cannot
	steer it meanwhile, which was the only reason it was off. Off again: the arrows and pedals return
	and the stick goes. Nitro and the steal button stay up throughout. ]]
--- The arrows HIDE (the stick does their job); the pedals only DIM (2026-10-20: "don't fully hide
--- brake/accelerate, just darken them") and stay live, so gas and brake still glide you forward and back.
local FLIGHT_HIDES = { "SteerLeft", "SteerRight" }

--- Does the stick steer the car on this device (`DriveConfig.TouchJoystick`)? A thumb device only.
function DrivingHudController._joystickSteers(self): boolean
	return DriveConfig.TouchJoystick == true and self:_wantsThumbControls()
end

--- The arrows: up on a thumb device unless the stick steers there, and never in the air.
function DrivingHudController._syncArrows(self)
	local controls = self._controls
	if not controls then
		return
	end
	local shown = not (self._flying == true or self:_joystickSteers())
	for _, name in FLIGHT_HIDES do
		local button = controls:FindFirstChild(name, true)
		if button and button:IsA("GuiObject") and button.Visible ~= shown then
			button.Visible = shown
			if not shown then
				self._leftHeld, self._rightHeld = false, false
				self:_publish()
			end
		end
	end
end
local FLIGHT_DIMS = { "Gas", "Brake" }
local FLIGHT_DIM = 0.55 -- how far toward black the pedals' art is taken
function DrivingHudController.setFlying(self, on: boolean)
	on = on == true and self:_wantsThumbControls()
	if (self._flying == true) == on then
		return
	end
	self._flying = on
	local controls = self._controls
	self:_syncArrows()
	if controls then
		--- Every image in the pedal darkened, its own colour remembered and put back after.
		self._flightDimmed = self._flightDimmed or {}
		for _, name in FLIGHT_DIMS do
			local pedal = controls:FindFirstChild(name, true)
			if pedal then
				for _, inst in pedal:GetDescendants() do
					if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
						if on then
							self._flightDimmed[inst] = inst.ImageColor3
							inst.ImageColor3 = inst.ImageColor3:Lerp(Color3.new(0, 0, 0), FLIGHT_DIM)
						elseif self._flightDimmed[inst] then
							inst.ImageColor3 = self._flightDimmed[inst]
						end
					end
				end
				if pedal:IsA("ImageLabel") or pedal:IsA("ImageButton") then
					if on then
						self._flightDimmed[pedal] = pedal.ImageColor3
						pedal.ImageColor3 = pedal.ImageColor3:Lerp(Color3.new(0, 0, 0), FLIGHT_DIM)
					elseif self._flightDimmed[pedal] then
						pedal.ImageColor3 = self._flightDimmed[pedal]
					end
				end
			end
		end
		if not on then
			table.clear(self._flightDimmed)
		end
	end
	if on then
		--- Only the arrows' holds: they are hidden and can never fire their own InputEnded.
		self._leftHeld, self._rightHeld = false, false
		self:_publish()
	end
	self:_syncStockControls()
end

-- Are our controls the ones on the screen right now? The single question both the PlayerModule
-- toggle and the button latch are answers to, so the two can never disagree about it.
function DrivingHudController._controlsUp(self): boolean
	local controls = self._controls
	return controls ~= nil and controls.Visible and self._gui ~= nil and self._gui.Enabled
end

--[[ Roblox's own touch controls — the thumbstick and the jump button — for the length of a race.

	They are the third set of driving controls on the screen, and they land exactly where the other
	two are: the DynamicThumbstick sits under the steering arrows in the bottom-left corner, and the
	jump button under the gas pedal in the bottom-right. Measured on an emulated iPhone 16, the
	thumbstick's ring and SteerLeft overlap by about 45 of the arrow's 48 pixels.

	The jump button is there at all because `StarterPlayer.CharacterUseJumpPower` is false: the kit's
	own `disableJumpButton` writes `Humanoid.JumpPower`, which a JumpHeight character ignores, so its
	attempt to get out of the way silently does nothing.

	Turning the module off rather than hiding its GUI is what also takes the INPUT away, which is the
	half that matters: the stock LocalVehicleGui steers on touch by reading
	`ControlModule:GetMoveVector()`, so leaving the thumbstick live would have it fighting the arrows
	over the same car. Disabled, the arrows are the steering, which is what they are for.

	Only ever touched while our own controls are up — on a keyboard PC this never runs, and the
	player keeps the movement module they walked in with.

	THE JUMP BUTTON IS NO LONGER THIS FUNCTION'S PROBLEM, and the reason is worth keeping. The
	PlayerModule shipping today does take TouchJump down inside `Disable()` — but the 16 Aug playtest
	filmed an Android build where it plainly did not: the thumbstick went and the jump button stayed,
	rendering under the gas pedal. So `_claimStockTouch` hides that instance outright and this stays
	responsible for the half only the module can do, which is taking the thumbstick's INPUT away. ]]
function DrivingHudController._syncStockControls(self)
	--- Both halves ride the RACE and the device rather than our own buttons being up — see
	--- `_touchSuppressed`. A desktop is unchanged by this: with no touch it answers false in exactly
	--- the cases `_controlsUp` used to.
	local suppressed = self:_touchSuppressed()

	-- Before the early return below: the latch has its own idea of what it has claimed, and the two
	-- fall out of step the first time this is called with the module already where we want it.
	self:_claimStockTouch(suppressed)

	--- Back on in the air on a thumb device (`setFlying`): the stick is how a flight is steered there.
	--- The claimed jump and pedal buttons stay hidden by `_claimStockTouch` either way.
	local wanted = not suppressed or self._flying == true or self:_joystickSteers()
	if self._stockControls == wanted then
		return
	end

	local playerScripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
	local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if not playerModule then
		return -- nothing to switch; the arrows still work, they just share the screen
	end

	local ok, err = pcall(function()
		local module = require(playerModule) :: any
		local stock = module:GetControls()
		if wanted then
			stock:Enable()
		else
			stock:Disable()
		end
	end)
	if not ok then
		self.log:warn(string.format("Could not toggle the stock touch controls: %s", tostring(err)))
		return
	end
	self._stockControls = wanted
end

function DrivingHudController._show(self, on: boolean)
	self._collectionActive = on
	if self._collectionCue then self._collectionCue:setActive(on) end
	--[[ The legend FIRST, and outside the `_gui` guard on purpose. It is not part of the authored
		DrivingHud (see `_buildLegend`), so a place that has not had that art imported yet still
		gets its controls explained — which is precisely the place where a console player has the
		least else to go on. It also means a legend never survives the race it was raised for. ]]
	if self._legend then
		--[[ THE FIRST RACE TEACHES AND EVERY RACE AFTER IT REMINDS (Dylan, 2026-09-17). Twelve
			seconds the first time is sized against READING — five or six rows is three or four
			seconds of it, taken a glance at a time between gaps in traffic — and five seconds
			afterwards is sized against RECOGNISING, which is one glance at a panel whose shape the
			player already knows.

			SET BEFORE THE SHOW, not after it. `setHold` takes effect on the next show by design, so
			writing it here is what makes this race use this race's number — and it is also what
			keeps `ControlLegend`'s mid-run re-arm honest: a pad plugged in thirty seconds into the
			FIRST race re-opens a twelve-second window, which is the whole point of that re-arm
			(that player has just become the person the legend is for). Written after the show, it
			would have handed them the returning player's five.

			PER SESSION, not per profile. "Have I seen this" would survive a rejoin if it were
			saved — but a player coming back after a week is a player who could use the long one,
			and the alternative is a profile field for seven seconds of panel. ]]
		if on then
			self._legend:setHold(
				if self._legendSeen then LegendConfig.ReturnSeconds else LegendConfig.HoldSeconds
			)
			self._legendSeen = true
		end
		self._legend:setVisible(on)
	end

	if not self._gui then
		return
	end
	self._gui.Enabled = on
	self:_runFrame(on) -- nothing to read between races, and nothing to read it off
	if on then
		self:_applyTouchOnly()
	else
		self:_clear()
		self:_syncStockControls() -- the player is back on foot and needs them
	end
end

-- === Setup ===================================================================

--[[ Pick a speedo and bind it: the new `SpeedoV2` panel, or the old `Cluster` dial.

	OPTIONAL IN A WAY THE CONTROLS ARE NOT. A place can have the buttons imported and neither
	readout built, and the race should still be drivable — so every reader here is nil-checked and
	a miss is a warning, not a failure.

	THE CLUSTER FRAME IS NEVER HIDDEN, only the five pieces of art inside it that `SpeedoConfig`
	names. The vertical nitro bar is a CHILD of that frame and has to be, because the cluster's
	`UIAspectRatioConstraint` is the only box on this screen measured against the viewport's height
	(`NitroConfig.Hud.Bars` argues it at length). Hiding the frame would take the bar with it, and
	the bar is not what this change is about.

	THE SEGMENT COUNT IS CHECKED AGAINST THE CONFIG rather than taken from whatever the panel
	happens to hold. `BuildSpeedoV2` builds the marks from `SpeedoConfig.Bar.Count`, so a count that
	has moved since the last build means the config was edited and the command was not re-run — and
	the failure without this check is a bar whose last few marks never light, which looks like a
	tuning problem rather than a missing step. It says which command to run instead. ]]
function DrivingHudController._attachSpeedo(self, gui: Instance)
	local wantsBar = SpeedoConfig.Style == "Bar"

	local cluster = gui:FindFirstChild("Cluster")
	if cluster then
		for _, name in SpeedoConfig.DialParts do
			local part = cluster:FindFirstChild(name)
			if part and part:IsA("GuiObject") then
				part.Visible = not wantsBar
			end
		end
		if not wantsBar then
			self._speedLabel = cluster:FindFirstChild("Speed")
			self._gearLabel = cluster:FindFirstChild("Gear")
		end
	elseif not wantsBar then
		self.log:warn("DrivingHud has no Cluster frame; the speedo will not read.")
	end

	local panel = gui:FindFirstChild(SpeedoConfig.FrameName)
	if not panel then
		if wantsBar then
			self.log:warn(
				`DrivingHud has no {SpeedoConfig.FrameName} panel; run the BuildSpeedoV2 command. No speed readout this race.`
			)
		end
		return
	end
	if panel:IsA("GuiObject") then
		panel.Visible = wantsBar
	end
	if not wantsBar then
		return
	end

	self._speedLabel = panel:FindFirstChild("Speed")
	if not self._speedLabel then
		self.log:warn(`{SpeedoConfig.FrameName} has no Speed label; the number will not read.`)
	end

	local well = panel:FindFirstChild("Bar")
	local strip = well and well:FindFirstChild("Segments")
	if not strip then
		self.log:warn(`{SpeedoConfig.FrameName} has no Bar.Segments; the speed bar will not light.`)
		return
	end

	--- Counted rather than measured with `#`, because a gap anywhere in the run makes the length of
	--- a table with holes a question the language does not promise an answer to.
	local segments, found = {}, 0
	for index = 1, SpeedoConfig.Bar.Count do
		local segment = strip:FindFirstChild(`Seg{index}`)
		if segment and segment:IsA("GuiObject") then
			segments[index] = segment
			found += 1
		end
	end
	if found ~= SpeedoConfig.Bar.Count then
		self.log:warn(
			`{SpeedoConfig.FrameName} holds {found} of {SpeedoConfig.Bar.Count} segments; re-run BuildSpeedoV2.`
		)
	end
	self._segments = if found > 0 then segments else nil
end

--[[ Find the two nitro instances and bind them. Both optional, independently.

	A place that has the bar imported and not the button is a desktop-complete HUD (the key still
	fires it); a place with neither still races, on cruise, boost and the brake. Neither absence is
	worth failing the attach for, which is the same contract the cluster and the action button are
	on, so this warns and carries on.

	SWITCHED OFF MEANS GONE, not disabled. `NitroConfig.Enabled` false hides both outright rather
	than leaving a dead button and a bar that never moves, on the same reasoning `_attach` hides the
	action button when the steal is off: a control that does nothing when pressed is worse than one
	that is not there.

	The BAR is a sibling of Controls rather than a child, deliberately. `_applyTouchOnly` hides the
	whole Controls frame on a keyboard, and the bar is a readout that a keyboard player needs just
	as much as a phone one, exactly like the gauge cluster beside it. ]]
--[[ The framed track art behind the pill, on or off.

	`Hud.Track` is a switch someone is going to flip while looking at the thing, so both dressings
	have to be reachable from one authored instance. Neither size is computed here: `FillArea`
	carries `SizeBare` and `SizeTracked` as attributes and this only picks one, which keeps the
	layout numbers in Studio with the rest of the layout, the same contract the action button's
	STEAL faces use. A bar missing an attribute keeps whatever size it was authored at.

	Undressed, the pill needs its own edge or it is a floating lozenge, so the trough's `UIStroke`
	comes on exactly when the art goes off. That undressed shape is not an invention: it is how
	`CarHpBar` over the car is built, trough plus stroke plus a glossed fill. ]]
function DrivingHudController._dressNitro(self, bar: Instance, area: Instance?)
	local dressed = NitroConfig.Hud.Track == true

	-- Only the TRACK goes. `Ticks` stays either way: its marks are drawn over rows 14..65 of the
	-- 80px canvas, which is 63.75% of the bar centred, and the undressed pill is 65% centred, so
	-- they land on it to within a fifth of a pixel. They are foreground on any dressing.
	local art = bar:FindFirstChild("Track")
	if art and art:IsA("GuiObject") then
		art.Visible = dressed
	end

	if not (area and area:IsA("GuiObject")) then
		return
	end

	local want = area:GetAttribute(if dressed then "SizeTracked" else "SizeBare")
	if typeof(want) == "UDim2" then
		area.Size = want
	end

	local trough = area:FindFirstChild("Trough")
	local stroke = trough and trough:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Enabled = not dressed
	end
end

--[[ Pick up the badge's pieces, the way `_attachNitro` picks up a bar's.

	NONE OF THEM IS REQUIRED. A badge built before an art id existed, or one somebody has taken a
	layer out of in the Explorer, drives whatever it still has and says what is missing once. The
	alternative is a race with no nitro readout at all because one ImageLabel was renamed.

	`Amount` is read here rather than shared with the bar branch because the badge wears it OUTSIDE
	its own frame (under the disc), and a label that is a child of the thing it describes is the
	only arrangement either layout has in common. ]]
function DrivingHudController._attachBadge(self, frame: Instance)
	local icon = frame:FindFirstChild("Icon")
	local arc = frame:FindFirstChild("Arc")
	local liquid = icon and icon:FindFirstChild("Liquid")
	local right = arc and arc:FindFirstChild("Right")
	local left = arc and arc:FindFirstChild("Left")

	local badge = {
		track = frame:FindFirstChild("RingTrack"),
		glow = frame:FindFirstChild("Glow"),
		right = right,
		left = left,
		--- The gradients are what the arc is actually drawn with; the images they sit on never
		--- move again after the builder places them.
		rightCut = right and right:FindFirstChild("Cut"),
		leftCut = left and left:FindFirstChild("Cut"),
		well = icon and icon:FindFirstChild("Well"),
		liquid = liquid,
		cut = liquid and liquid:FindFirstChild("Cut"),
	}
	self._nitroBadge = badge
	self._nitroAmount = frame:FindFirstChild("Amount")

	local missing = {}
	for _, name in { "track", "glow", "right", "left", "rightCut", "leftCut", "well", "liquid", "cut" } do
		if not badge[name] then
			table.insert(missing, name)
		end
	end
	if #missing > 0 then
		self.log:warn(
			`DrivingHud.NitroBadge is missing {table.concat(missing, ", ")}; re-run BuildNitroBadge.`
		)
	end
	--- What `_layoutTimers` stands in slot 1 of the powerup row.
	self._nitroBadgeFrame = if frame:IsA("GuiObject") then frame else nil
	self:_buildNitroHint(frame)
	self:_buildStarBadge(frame)
end

--[[ The tutorial's SHIFT cap over the nitro badge (`TutorialConfig.NitroHint`). A CHILD of the badge,
	standing on its top edge, so it rides wherever the badge goes, the powerup row included. Hidden
	until `_stepNitroHint` says otherwise.

	The press that retires it is watched on `InputBegan` WITHOUT the processed gate, on purpose:
	nitro's own binding goes through ContextActionService, which marks the input processed, and a
	gated listener would never see the one press it exists to see. ]]
function DrivingHudController._buildNitroHint(self, frame: Instance)
	local cfg = TutorialConfig.NitroHint
	if not (cfg and cfg.Enabled and frame:IsA("GuiObject")) then
		return
	end
	local old = frame:FindFirstChild("NitroHint")
	if old then
		old:Destroy()
	end
	local cap = Instance.new("Frame")
	cap.Name = "NitroHint"
	cap.AnchorPoint = Vector2.new(0.5, 1)
	cap.Position = UDim2.fromScale(0.5, -0.06)
	cap.Size = UDim2.fromScale(1.1, 0.36)
	cap.BackgroundColor3 = NitroConfig.Hud.ReadyColor
	cap.ZIndex = 20
	cap.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = cap
	local rim = Instance.new("UIStroke")
	rim.Color = Color3.fromRGB(10, 22, 48)
	rim.Thickness = 2.5
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = cap
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.Text = cfg.Text
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.ZIndex = 21
	label.Parent = cap
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0.14, 0), UDim.new(0.14, 0)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0.08, 0), UDim.new(0.08, 0)
	pad.Parent = label
	local textRim = Instance.new("UIStroke")
	textRim.Color = Color3.fromRGB(10, 22, 48)
	textRim.Thickness = 1.5
	textRim.Parent = label
	--- On a pad the cap carries the button's glyph instead of the word, in the controller's own art.
	local glyph = Instance.new("ImageLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.Size = UDim2.fromScale(0.8, 0.8)
	glyph.SizeConstraint = Enum.SizeConstraint.RelativeYY
	glyph.ScaleType = Enum.ScaleType.Fit
	glyph.ZIndex = 21
	glyph.Visible = false
	glyph.Parent = cap
	local scale = Instance.new("UIScale")
	scale.Parent = cap
	cap.Parent = frame
	self._nitroHint = { frame = cap, scale = scale, label = label, glyph = glyph, rim = rim }

	if not self._nitroHintConn then
		self._nitroHintConn = UserInputService.InputBegan:Connect(function(input: InputObject)
			local kind = input.UserInputType
			if self._nitroHintDone or not (kind == Enum.UserInputType.Keyboard or kind.Name:sub(1, 7) == "Gamepad") then
				return
			end
			if table.find(NitroConfig.Keys, input.KeyCode) and self._nitroHint and self._nitroHint.frame.Visible then
				self._nitroHintDone = true
				self._nitroHint.frame.Visible = false
			end
		end)
	end
end

--[[ One frame of the SHIFT cap: up while the tutorial's `NitroHint.Step` beat is live, the player is
	on keyboard and mouse, the tank can fire and the key has not yet been pressed this session.
	Retired for the SESSION rather than saved: the tutorial runs once, and a returning player who
	never pressed it is past the beat it shows on. ]]
function DrivingHudController._stepNitroHint(self)
	local hint = self._nitroHint
	if not hint then
		return
	end
	local cfg = TutorialConfig.NitroHint
	local preferred = UserInputService.PreferredInput
	local pad = preferred == Enum.PreferredInput.Gamepad
	local padKey = if pad then GamepadInput.gamepadKeyIn(NitroConfig.Keys) else nil
	local show = not self._nitroHintDone
		and Players.LocalPlayer:GetAttribute(TutorialConfig.StepAttribute) == cfg.Step
		and (preferred == Enum.PreferredInput.KeyboardAndMouse or padKey ~= nil)
		and self._nitro ~= nil
		and self._nitro:getTank() >= NitroConfig.Tank.MinToFire
	hint.frame.Visible = show
	if show then
		--- Word on a keyboard, glyph on a pad; the image re-asked only when the device flips.
		hint.label.Visible = not pad
		hint.glyph.Visible = pad
		if pad and hint.padKey ~= padKey then
			hint.padKey = padKey
			hint.glyph.Image = GamepadInput.getButtonImage(padKey :: Enum.KeyCode)
		end
		--- A pad's cap is the glyph's own square plus a rim, not the word's wide key.
		hint.frame.Size = if pad then UDim2.fromScale(0.5, 0.5) else UDim2.fromScale(1.1, 0.36)
		hint.frame.BackgroundTransparency = if pad then 1 else 0
		hint.rim.Enabled = not pad
		--- The tutorial's own key-cap breath (`TutorialConfig.Meters.Key`), so it reads as the same prompt.
		local key = TutorialConfig.Meters.Key
		local phase = (math.sin(os.clock() * math.pi * 2 / key.PulsePeriod) + 1) * 0.5
		hint.scale.Scale = 1 + (key.PulseScale - 1) * phase
	end
end

--[[ The star's timer (`PickupConfig.StarTimer`): the nitro badge cloned, the bottle swapped for the
	star, parented INTO the nitro badge so its square and its placement follow that one on every
	screen without measuring anything. Hidden until a star lights; `_stepStar` drives it.

	THE FADE IS PER LAYER, not a CanvasGroup: a CanvasGroup clips to its box, and the plate's stroke
	sits on the box's edge. Each layer's authored transparency is captured once and the fade runs
	from it to 1, so a translucent plate stays exactly as translucent at full.

	Only the ring and plate survive the clone. The bottle (`Well`, `Liquid`, `Glass`) and the burn's
	bloom (`Glow`) are nitro's, and a glow nothing drives would be stuck at whatever the original
	was showing on the frame it was copied. ]]
function DrivingHudController._buildStarBadge(self, frame: Instance)
	--- A rebuild's old badge may be in the touch row rather than under `frame`, so it goes by reference.
	if self._starBadge and self._starBadge.frame then
		self._starBadge.frame:Destroy()
	end
	self._starBadge = nil
	local cfg = PickupConfig.StarTimer
	if not (cfg and cfg.Enabled and frame:IsA("GuiObject")) then
		return
	end
	local old = frame:FindFirstChild("StarBadge")
	if old then
		old:Destroy()
	end

	local star = frame:Clone()
	star.Name = "StarBadge"
	star.AnchorPoint = Vector2.zero
	star.Position = UDim2.fromScale(cfg.Offset.X, cfg.Offset.Y)
	star.Size = UDim2.fromScale(1, 1)
	star.Visible = false
	for _, name in { "Glow", "Amount" } do
		local layer = star:FindFirstChild(name)
		if layer then
			layer:Destroy()
		end
	end
	local icon = star:FindFirstChild("Icon")
	if icon then
		icon:ClearAllChildren()
		local glyph = Instance.new("ImageLabel")
		glyph.Name = "Star"
		glyph.BackgroundTransparency = 1
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.ScaleType = Enum.ScaleType.Fit
		glyph.Image = UIAssets.url(PickupConfig.Packs.Star.Icon)
		glyph.ZIndex = 7
		glyph.Parent = icon
	end

	local gold = PickupConfig.Packs.Star.Color
	local arc = star:FindFirstChild("Arc")
	local right = arc and arc:FindFirstChild("Right")
	local left = arc and arc:FindFirstChild("Left")
	local track = star:FindFirstChild("RingTrack")
	for _, half in { right, left } do
		if half and half:IsA("ImageLabel") then
			half.ImageColor3 = gold
		end
	end
	if track and track:IsA("ImageLabel") then
		track.ImageColor3 = dimmed(gold, NitroConfig.Hud.Badge.RingDim)
	end

	local layers = {}
	local function capture(object: Instance)
		if object:IsA("ImageLabel") then
			table.insert(layers, { object = object, key = "ImageTransparency", base = object.ImageTransparency })
		elseif object:IsA("Frame") and object.BackgroundTransparency < 1 then
			table.insert(layers, { object = object, key = "BackgroundTransparency", base = object.BackgroundTransparency })
		elseif object:IsA("UIStroke") then
			table.insert(layers, { object = object, key = "Transparency", base = object.Transparency })
		end
	end
	for _, object in star:GetDescendants() do
		capture(object)
	end
	star.Parent = frame
	--- Its place in a touch row (`PickupConfig.TimerRow`): packs sit in `Names` order.
	star.LayoutOrder = table.find(PickupConfig.Names, "Star") or 0

	self._starBadge = {
		frame = star,
		right = right,
		left = left,
		rightCut = right and right:FindFirstChild("Cut"),
		leftCut = left and left:FindFirstChild("Cut"),
		layers = layers,
		shown = 0, -- 0 hidden .. 1 fully faded in
		arcAt = -1,
	}
	if not (right and left) then
		self.log:warn("DrivingHud.NitroBadge has no Arc halves to clone; the star timer will not drain.")
	end
end

--[[ The row of powerup readouts over the speedo (`PickupConfig.TimerRow`), on every device: the
	nitro badge in slot 1 for good, then each timed pack while it runs. Made on first use in the
	nitro badge's ScreenGui and re-laid every frame: its left edge on the speedo's, its bottom `Gap`
	px over the speedo's top, measured off whichever speedo is drawn (`SpeedoV2` or the old
	`Cluster`), which `_layoutReadouts` moves between the desktop and phone spots. Its height is
	`NitroConfig.Hud.Badge.Height` of the screen, the badge's own authored size, so nothing in the
	row is measured off something inside it. nil when there is no speedo to stand on, which sends
	every readout back to where it was authored. ]]
function DrivingHudController._timerRow(self, gui: Instance): Frame?
	local speedo = gui:FindFirstChild(if SpeedoConfig.Style == "Bar" then SpeedoConfig.FrameName else "Cluster")
	if not (speedo and speedo:IsA("GuiObject") and speedo.Visible and gui:IsA("ScreenGui")) then
		return nil
	end
	local row = self._timerRowFrame
	if not (row and row.Parent == gui) then
		row = Instance.new("Frame")
		row.Name = "PowerupTimers"
		row.BackgroundTransparency = 1
		row.AnchorPoint = Vector2.new(0, 1)
		row.ZIndex = 5
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, PickupConfig.TimerRow.Spacing)
		layout.Parent = row
		row.Parent = gui
		self._timerRowFrame = row
	end
	local origin = (gui :: ScreenGui).AbsolutePosition
	local at, size = speedo.AbsolutePosition, speedo.AbsoluteSize
	row.Position = UDim2.fromOffset(at.X - origin.X, at.Y - origin.Y - PickupConfig.TimerRow.Gap)
	--- Twice the speedo's width is room for the nitro badge and a few packs; the frame is invisible
	--- and not `Active`, so the spare width costs nothing and catches no input.
	row.Size = UDim2.new(0, size.X * 2, NitroConfig.Hud.Badge.Height * PickupConfig.TimerRow.Scale, 0)
	return row
end

--- One readout into the row: a square the row's height (`RelativeYY` reads both axes off it).
local function intoRow(frame: GuiObject, row: Frame)
	if frame.Parent ~= row then
		frame.Parent = row
		frame.SizeConstraint = Enum.SizeConstraint.RelativeYY
		frame.Size = UDim2.fromScale(1, 1)
	end
end

--[[ Put the nitro badge and the timers where they go this frame: into the row, or, with the row
	off or no speedo to stand on, back where each was authored, the nitro badge in its corner and
	the star over it at `StarTimer.Offset`. The nitro badge's authored layout is captured the first
	time it is moved, so the way back is exact. Every frame, so a speedo moved by `_layoutReadouts`
	on a device switch is followed the same frame. ]]
function DrivingHudController._layoutTimers(self)
	local nitro = self._nitroBadgeFrame
	if not nitro then
		return
	end
	local gui = self._gui
	local row = if PickupConfig.TimerRow.Enabled and gui then self:_timerRow(gui) else nil
	local star = self._starBadge and self._starBadge.frame
	if row then
		if not self._nitroHome then
			self._nitroHome = {
				parent = nitro.Parent, anchor = nitro.AnchorPoint, position = nitro.Position,
				size = nitro.Size, constraint = nitro.SizeConstraint,
			}
		end
		nitro.LayoutOrder = 0
		intoRow(nitro, row)
		if star then
			intoRow(star, row)
		end
		return
	end
	local home = self._nitroHome
	if home and nitro.Parent ~= home.parent then
		nitro.Parent = home.parent
		nitro.AnchorPoint, nitro.Position, nitro.Size = home.anchor, home.position, home.size
		nitro.SizeConstraint = home.constraint
	end
	if star and star.Parent ~= nitro then
		star.Parent = nitro
		star.SizeConstraint = Enum.SizeConstraint.RelativeXY
		star.Size = UDim2.fromScale(1, 1)
		star.Position = UDim2.fromScale(PickupConfig.StarTimer.Offset.X, PickupConfig.StarTimer.Offset.Y)
	end
end

--[[ One frame of the star timer: fade toward lit while `StarController:isActive()`, the ring at the
	share of `Duration` left. A second star mid-star tops the clock back up to `Duration`
	(`StarController.start`), so the share never exceeds 1 and the ring simply refills. ]]
function DrivingHudController._stepStar(self, dt: number)
	local badge = self._starBadge
	if not badge then
		return
	end
	local star = Shard.get("StarController")
	local remaining = if star then star:remaining() else 0
	local live = remaining > 0

	local fade = math.max(PickupConfig.StarTimer.Fade, 1e-3)
	local shown = math.clamp(badge.shown + (if live then dt else -dt) / fade, 0, 1)
	if shown ~= badge.shown then
		badge.shown = shown
		for _, layer in badge.layers do
			layer.object[layer.key] = layer.base + (1 - layer.base) * (1 - shown)
		end
	end
	badge.frame.Visible = shown > 0

	--- Held where it last was while fading OUT, so the ring does not snap empty under the fade.
	if live and badge.right and badge.left then
		local swept = math.clamp(remaining / PickupConfig.Packs.Star.Star.Duration, 0, 1)
		if math.abs(swept - badge.arcAt) > 0.002 then
			badge.arcAt = swept
			sweepArc(badge, swept)
		end
	end
end

function DrivingHudController._attachNitro(self, gui: Instance, controls: Instance)
	local hud = NitroConfig.Hud
	local on = NitroConfig.Enabled

	local wanted = NitroConfig.barPath()
	local label = table.concat(wanted, ".")

	--[[ Walk a path from the ScreenGui. The bars do not all live at the same depth: the vertical
		one hangs off `Cluster` so it is measured against the gauge art rather than the screen.
		A recursive search would be shorter and wrong, because `Controls.Nitro` is the touch
		button and depth-first finds it before the bar of the same name. ]]
	local function resolve(path: { string }): GuiObject?
		local at: Instance? = gui
		for _, name in ipairs(path) do
			at = at and at:FindFirstChild(name)
		end
		return if at and at:IsA("GuiObject") then at :: GuiObject else nil
	end

	-- Exactly one bar is ever visible. Walking `Bars` rather than everything that is not `wanted`
	-- means a frame someone parks in this ScreenGui by hand is none of the switch's business.
	for _, path in pairs(hud.Bars) do
		local other = resolve(path)
		if other then
			other.Visible = on and table.concat(path, ".") == label
		end
	end

	local bar = resolve(wanted)
	if bar then
		-- The readers are only picked up when the feature is on. Left set, `_stepNitro` would spend
		-- a race painting a frame nobody can see with a tank nothing is filling.
		--
		-- The badge is a different SHAPE rather than a third bar, so it binds its own pieces and
		-- skips everything below: it has no framed track to dress and no caption to write, and its
		-- fill is a gradient on an image rather than a Frame with a width.
		if on and NitroConfig.Hud.Layout == "Badge" then
			self:_attachBadge(bar)
		elseif on then
			local area = bar:FindFirstChild("FillArea")
			self._nitroFill = area and area:FindFirstChild("Fill")
			-- `Cut` by name rather than by class, so the gradient that draws the fill's edge is
			-- distinguishable from a gloss ramp someone parks on the same frame later.
			local cut = self._nitroFill and self._nitroFill:FindFirstChild("Cut")
			self._nitroCut = if cut and cut:IsA("UIGradient") then cut else nil
			self._nitroTrough = area and area:FindFirstChild("Trough")
			self._nitroFlash = area and area:FindFirstChild("Flash")
			self._nitroAmount = bar:FindFirstChild("Amount")
			-- Which way the fill grows is the INSTANCE's business, not the flag's, so a bar added
			-- later only has to say what it is rather than teach the config a third name.
			self._nitroVertical = bar:GetAttribute("Vertical") == true
			if self._nitroCut and self._nitroFill then
				--[[ The two things a cut fill cannot be authored wrong, so neither is left to be
					authored. It has to BE the trough — any smaller and the corners disagree again,
					which is the whole bug — and the gradient has to run along the axis the bar
					grows on, which the `Vertical` attribute above already says. 270 is
					bottom-to-top, 0 is left-to-right. ]]
				self._nitroFill.Size = UDim2.fromScale(1, 1)
				self._nitroCut.Rotation = if self._nitroVertical then 270 else 0
			end
			if not self._nitroFill then
				self.log:warn(`DrivingHud.{label} has no FillArea.Fill to drive; the bar will not read.`)
			end
			self:_dressNitro(bar, area)
			local caption = bar:FindFirstChild("Caption")
			if caption and caption:IsA("TextLabel") then
				caption.Text = hud.Caption
			end
		end
	elseif on then
		self.log:warn(`DrivingHud has no {label} bar; nitro runs without a readout.`)
	end

	local button = controls:FindFirstChild(hud.ButtonName)
	if button and button:IsA("GuiButton") then
		button.Visible = on
		if on then
			-- The same hold binding the pedals get, so a finger sliding off it releases the burn
			-- rather than stranding it alight. `_publish` is what carries the value across.
			self:_bindHold(button, "_nitroHeld")
		end
	elseif on then
		self.log:warn(`DrivingHud.Controls has no {hud.ButtonName} button; no nitro by thumb.`)
	end
end

function DrivingHudController._attach(self)
	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

		-- Done before the GUI check: the stock speedo has to go whether or not this place has
		-- the new art imported yet, and it's the deployed car scripts that put it there.
		self:_suppressStockSpeedo(playerGui)

		local gui = playerGui:WaitForChild("DrivingHud", GUI_WAIT)
		if not gui then
			self.log:warn("No StarterGui.DrivingHud to bind; racing with the stock controls only.")
			return
		end
		local controls = gui:FindFirstChild("Controls")
		if not controls then
			self.log:warn("DrivingHud has no Controls frame; the on-screen buttons are unbound.")
			return
		end

		self._collectionCue = TrafficCollectionCue.new(playerGui)
		self._collectionCue:setActive(self._collectionActive == true)
		self._gui = gui
		self._controls = controls
		self._tutorialHighlight = TutorialControlHighlight.new(controls)
		gui.Enabled = false

		self:_attachSpeedo(gui)

		for _, spec in BUTTONS do
			local button = controls:FindFirstChild(spec.name)
			if button and button:IsA("GuiButton") then
				self:_bindHold(button, spec.field)
			else
				self.log:warn(string.format("DrivingHud.Controls has no %s button to bind.", spec.name))
			end
		end

		--[[ The action button. Optional in the same way the cluster is — a place that has the four
			driving buttons imported and not this one is still drivable, it just cannot steal by
			thumb — and hidden outright when the mechanic is switched off, because a button whose
			only verb is disabled is a button that does nothing when you press it.

			Both faces are read off the instance: the JUMP one is whatever the ImageButton is
			authored with, the STEAL one comes off three attributes beside it. That keeps re-skinning
			either verb a Studio edit, the same contract as the nitro bar's SizeBare/SizeTracked, and it means
			a place that has not had the STEAL art imported degrades to a button that keeps its jump
			face rather than to a blank square. ]]
		local action = controls:FindFirstChild("Jump")
		if action and action:IsA("ImageButton") then
			self._action = action
			action.Visible = StealConfig.Enabled
			self._jumpFace = { action.Image, action.HoverImage, action.PressedImage }
			self._stealFace = {
				action:GetAttribute("StealImage") or action.Image,
				action:GetAttribute("StealHoverImage") or action.HoverImage,
				action:GetAttribute("StealPressedImage") or action.PressedImage,
			}
			--- What `_pulseAction` drives. Found first so a rebind never stacks a second one.
			self._actionPulse = ButtonScale.ensure(action)
			self:_bindTap(action, function()
				local steal = self._steal
				if not steal then
					return
				end
				-- Asked again here rather than read off `_actionSteal`: the face is what was true on
				-- the last rendered frame, and this has to be what is true now.
				if steal:canSteal() then
					steal:steal()
				else
					steal:bail()
				end
			end)
		else
			self.log:warn("DrivingHud.Controls has no Jump button to bind; no bail or steal by thumb.")
		end

		self:_attachNitro(gui, controls)

		-- Watched rather than read once, so flipping the attribute in Studio during a playtest
		-- takes effect without a rejoin.
		gui:GetAttributeChangedSignal("TouchOnly"):Connect(function()
			self:_applyTouchOnly()
		end)

		--[[ A hybrid device changing its mind: pick the keys up on a touchscreen laptop and the thumb
			controls go, tap the screen and they come back. See `_wantsThumbControls`.

			`LastInputTypeChanged` fires for mouse movement too, so this runs often — which is fine,
			because `_applyTouchOnly` compares against the current `Visible` and does nothing at all
			unless the answer actually changed. Only devices with BOTH a keyboard and a touchscreen
			can ever see a different answer here; a phone and a desktop each have one fixed reply. ]]
		UserInputService.LastInputTypeChanged:Connect(function()
			self:_applyTouchOnly()
		end)

		--[[ A respawn rebuilds the movement module's controllers, which can hand a player back the
			thumbstick we switched off — and, if a race ever ended without us hearing about it,
			would otherwise leave them stuck in the lobby with no controls at all. Re-asking the
			question is both halves of that: it re-disables mid-race and restores on foot. ]]
		Players.LocalPlayer.CharacterAdded:Connect(function()
			self._stockControls = nil -- whatever we last set, the respawn may have undone
			self:_syncStockControls()
		end)

		self:_applyTouchOnly()
	end)
end

DrivingHudController:withRemoteEvents({
	{
		RaceStart = function()
			DrivingHudController:_show(true)
		end,
		-- HP is gone and DriveController has already torn its shim down, so the pedals control
		-- nothing. Dropping them here also releases anything held into the wreck.
		RaceWrecked = function()
			DrivingHudController:_show(false)
		end,
		-- ...and the wreck was paid out of (`ReviveService`): there is a car to drive again, so the
		-- pedals come back. Same call `RaceStart` makes, because this is the same state.
		RaceRevived = function()
			DrivingHudController:_show(true)
		end,
		RaceEnd = function()
			DrivingHudController:_show(false)
		end,
		-- The end panel is up over the scene (`RaceService.holdEndPanel`). On a getaway nothing else
		-- has put the pedals away by then, since a bank is not a wreck, and they would sit under it.
		RaceEndPanel = function()
			DrivingHudController:_show(false)
		end,
	},
})

DrivingHudController:withLifecycle({
	init = function(self)
		self._held = {} -- [field] = set of live InputObjects
		self._leftHeld = false
		self._rightHeld = false
		self._gasHeld = false
		self._brakeHeld = false
		self._nitroHeld = false

		-- The speedo. `_speedLabel` is whichever readout's number is live and `_gearLabel` only ever
		-- the dial's; `_segments` is the bar's marks by index, and is nil on the dial. The two
		-- `nil`s beside them are what is currently DRAWN, so the first frame of a race always
		-- writes rather than trusting what the last one left on screen.
		self._mph, self._gear = 0, 1
		self._speedLabel, self._gearLabel, self._segments = nil, nil, nil
		self._shownMph = nil
		self._segLit = nil

		-- The nitro bar: the instances it is made of, and the two pieces of state drawing it needs.
		-- `_nitroReady` is nil rather than false until the first frame reads the tank, so a full
		-- bottle at the line does not flash for a threshold it never crossed.
		self._nitroFill, self._nitroTrough, self._nitroFlash, self._nitroAmount = nil, nil, nil, nil
		self._nitroCut = nil -- the gradient the fill's leading edge is cut with, if it has one
		self._nitroVertical = false -- which axis the authored bar's fill grows along
		-- ...and the badge, which is the same reading in a different shape: its pieces, the arc's
		-- last written sweep and the bloom's eased transparency. All nil until one is bound, which
		-- is what `_stepNitro` tests to know which painter to call.
		self._nitroBadge = nil
		self._starBadge = nil -- the star timer cloned off it (`_buildStarBadge`); lives inside it
		self._timerRowFrame = nil -- the powerup row over the speedo (`_timerRow`), made on first use
		self._nitroBadgeFrame = nil -- slot 1 of that row
		self._nitroHome = nil -- the nitro badge's authored layout, for the way back out of the row
		self._nitroArcAt = nil
		self._nitroGlowAt = 1
		self._nitroShown = 0 -- the bar's own eased fraction, chasing the tank
		self._nitroCutAt = -1 -- the fraction the cut was last written at
		self._nitroReady = nil
		self._nitroFlashFor = 0 -- seconds left of the "you can fire again" flash

		-- The action button: which verb its face is currently showing (nil = it has not been drawn
		-- yet this race), and the two sets of three images to draw it with.
		self._actionSteal = nil
		self._jumpFace, self._stealFace = nil, nil
		self._actionPulse = nil -- the UIScale `_pulseAction` swells it through
		self._pulseFrom = 0 -- clock time the current face went up

		-- The control legend: the panel itself, the bail half of its two-verb row, and that row's
		-- own copy of which verb is showing. The clock that takes the panel away is the LEGEND's —
		-- see `ControlLegend._arm`, which also has to re-open it on a pad plugged in mid-run. How
		-- LONG that clock runs is this controller's, and `_legendSeen` is the whole of it: false
		-- for the session's first race, which is the one that has to teach. See `_show`.
		self._legend = nil
		self._legendBail = nil
		self._legendSteal = nil
		self._legendSeen = false

		-- The other two owners' touch buttons, while we are holding them down. Keyed by instance and
		-- valued by the visibility to give back, so a release restores rather than forces. See
		-- _claimStockTouch.
		self._touchClaimed = false
		self._stockTouch = {} -- [GuiObject] = the Visible it had when we took it
		self._touchConns = {}

		-- Roblox's touch controls, as we last left them. `true` is what a player joins with, so
		-- the first sync on a keyboard device is a no-op and the module is never even required.
		self._stockControls = true
	end,

	start = function(self)
		self._drive = Shard.get("DriveController")
		self._road = Shard.get("RoadController")
		self._steal = Shard.get("StealController")
		self._nitro = Shard.get("NitroController")
		self._traffic = Shard.get("TrafficController")
		--- Before `_attach`, which is a spawned thread that waits on PlayerGui: the legend has to
		--- exist by the time the first `RaceStart` can arrive, and it does not need that GUI.
		self:_buildLegend()
		self:_attach()
	end,
})

return DrivingHudController
