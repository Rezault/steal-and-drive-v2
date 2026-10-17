--[[
	CarLightsController  (client)
	-----------------------------
	Event headlights follow `WeatherController.currentEvent`: front lamp glow plus two shadowless
	road lights on the driven car, rebuilt with every stolen body and removed on race exit.

	The lamps on the car the player is driving: the stop lamps, lit off the pedal, and the
	indicators, lit off a key. Traffic's are driven by `TrafficController` off its own steering and
	speed easing; this is the player's half of the same two features.

	It owns nothing but the twins and the stalk. The lamp choice and the lit twins come from
	`Modules/CarBrakeLights` and `Modules/CarBlinkers`, exactly as traffic's do, so the car you
	stole brakes and indicates with the same lamps it was using in front of you a moment earlier.
	The pedal is read through `DriveController.getThrottleInput`, under the same threshold
	`_shapeThrottle` brakes on, and only while `isDriving` says the shim is actually at the wheel:
	a bailed car coasting on with nobody in it, and a car held still by a tutorial freeze, both go
	dark and drop their signal.

	=== THE STALK ===============================================================================

	A press toggles its side and the other side's press swaps it, then the signal cancels itself
	off the steering (`TurnSignalConfig.AutoCancel`): steered the signalled way, then released, and
	the lamp goes out, the way a stalk springs back after the wheel does. The keys and the touch
	buttons are `ContextActionService` bindings held for the length of a race; a press that lands
	while the shim is not driving is PASSED rather than sunk, so the same key can go on to whoever
	else wants it (nothing does today, and `TurnSignalConfig` says why the keys are Z and C).

	=== THE BODY CHANGES UNDER US =============================================================

	A steal does not swap the car; it swaps the BODY. `CarBody.swapMeshes` destroys everything under
	`Body/` but the `HitBox` and rebuilds it flat from the stolen shell, which takes our twins with
	it and leaves us pointing at parts that no longer exist. So the rigs are not built once per race
	but once per BODY: `Body`'s `ChildAdded`/`ChildRemoved` mark them dirty (ignoring our own twins,
	or building them would dirty it again), and the next frame rebuilds. That also covers the first
	car of a race, whose body may still be replicating when `RaceStart` lands, and a door rig moving
	a panel into its hinge model. A storm of thirty removals and thirty additions on a steal costs
	one rebuild.

	The twins are parented under `Body/` and welded to their lamps; the `HitBox`, which every rig
	in the game has, only lends its CFrame as the car's frame (nose down -Z, the way NitroController
	reads it). Being under `Body/` is what lets the next steal clean them up for free; the `light`
	token in their names keeps `CarPaint` off them, and they carry no attributes, so the steal and
	the door rig never see them either.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local BrakeLightConfig = require(ReplicatedStorage.shared.Configs.BrakeLightConfig)
local DriveConfig = require(ReplicatedStorage.shared.Configs.DriveConfig)
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
local TurnSignalConfig = require(ReplicatedStorage.shared.Configs.TurnSignalConfig)
local CarBlinkers = require(ReplicatedStorage.shared.Modules.CarBlinkers)
local CarBrakeLights = require(ReplicatedStorage.shared.Modules.CarBrakeLights)
local CarHeadlights = require(ReplicatedStorage.shared.Modules.CarHeadlights)

local CarLightsController = Shard.new("CarLightsController"):withDependencies({ "DriveController", "RoadController" })

-- The redress container on a rigged car and the chassis hull inside it (Modules/CarBody).
local BODY_NAME = "Body"
local HITBOX_NAME = "HitBox"
-- The raw throttle at or below which the drive shim brakes (`DriveController._shapeThrottle`).
local BRAKE_INPUT = -0.1
-- Sign of a raw steer value that turns the car left, the same constant DriveController keeps.
local STEER_LEFT = if DriveConfig.PositiveSteerIsLeft then 1 else -1
-- Our own twins, which a body change must not count as one.
local TWIN_NAMES = { [CarBrakeLights.TWIN_NAME] = true, [CarBlinkers.TWIN_NAME] = true, [CarHeadlights.TWIN_NAME] = true }

local ACTIONS = { [-1] = "TurnSignalLeft", [1] = "TurnSignalRight" }
-- The driving HUD's touch steering arrows, which the touch indicator buttons sit above.
local STEER_BUTTONS = { [-1] = "SteerLeft", [1] = "SteerRight" }

-- === The car ==================================================================

function CarLightsController._destroyRigs(self)
	CarBrakeLights.destroy(self._brakes)
	CarBlinkers.destroy(self._blinkers)
	CarHeadlights.destroy(self._headlights)
	self._headlights = nil
	self._brakes, self._blinkers = nil, nil
end

function CarLightsController._unwatchBody(self)
	for _, conn in self._bodyConns do
		conn:Disconnect()
	end
	self._bodyConns = {}
	self._body = nil
end

--[[ Which car we are lighting. Re-resolved every frame rather than latched at race start, the way
	NitroController does, because a revive can hand the player a fresh model. ]]
function CarLightsController._bindCar(self, car: Model?)
	if car == self._car then
		return
	end
	self:_destroyRigs()
	self:_unwatchBody()
	self._car = car
	self._dirty = car ~= nil
end

--[[ Build the twins for whatever body the car is wearing right now. Leaves `_dirty` set when the
	body or its hull has not arrived yet, so the next frame tries again. ]]
function CarLightsController._rebuild(self)
	local car = self._car
	local body = car and car:FindFirstChild(BODY_NAME)
	local hit = body and body:FindFirstChild(HITBOX_NAME)
	if not (body and hit and hit:IsA("BasePart")) then
		return
	end

	self:_destroyRigs()
	if body ~= self._body then
		self:_unwatchBody()
		self._body = body
		local function changed(child: Instance)
			if not TWIN_NAMES[child.Name] then
				self._dirty = true
			end
		end
		table.insert(self._bodyConns, body.ChildAdded:Connect(changed))
		table.insert(self._bodyConns, body.ChildRemoved:Connect(changed))
	end

	self._dirty = false
	if BrakeLightConfig.Enabled and BrakeLightConfig.Player.Enabled then
		self._brakes = CarBrakeLights.build(body, hit, BrakeLightConfig, BrakeLightConfig.Player.Hold, body)
	end
	if TurnSignalConfig.Enabled then
		self._blinkers = CarBlinkers.build(body, hit, TrafficConfig.Blinkers)
	end
	self._headlights = CarHeadlights.build(body, hit, true)
end

-- === The stalk ================================================================

--[[ A press on one side: on, off again, or over from the other side. Refused while the shim is
	not driving, and the caller passes the key on when it is. ]]
function CarLightsController._press(self, side: number): boolean
	if not (self._drive and self._drive:isDriving()) then
		return false
	end
	self._signal = if self._signal == side then 0 else side
	self._signalAt = os.clock()
	self._steered = false
	return true
end

--[[ Cancel the signal the way a stalk does: after the turn it was for, or after long enough that
	no turn is coming. `toward` is the raw steer measured in the signalled direction, so the same
	two thresholds serve both sides. ]]
function CarLightsController._stepSignal(self, now: number, driving: boolean)
	local side = self._signal
	if side == 0 then
		return
	end
	if not driving then
		self._signal = 0
		return
	end
	local cancel = TurnSignalConfig.AutoCancel
	if not cancel.Enabled then
		return
	end
	if now - self._signalAt > cancel.MaxSeconds then
		self._signal = 0
		return
	end
	local toward = self._drive:getSteerInput() * STEER_LEFT * -side
	if toward > cancel.SteerThreshold then
		self._steered = true
	elseif self._steered and math.abs(toward) < cancel.ReleaseThreshold then
		self._signal = 0
	end
end

--[[ Park the two touch buttons above the driving HUD's steering arrows, on their own side, sized
	off the arrows. `ContextActionService` positions a button inside its own bottom-right frame,
	so the target is measured in screen space and handed over as an offset from that frame; both
	are `AbsolutePosition`s and share a space. With no arrows to measure off (a HUD that has not
	built yet, or a place without one) the buttons take the config's viewport fractions instead.

	THEY ALSO SHOW EXACTLY WHEN THE ARROWS DO. `ContextActionService` draws a touch button whenever
	`TouchEnabled` is true, but the driving HUD hides its controls until the last input was a
	touch (`DrivingHudController`), so on a touch laptop, or in the device emulator, the arrows are
	gone while the buttons would still be there. Following the HUD's `Controls.Visible` keeps the
	indicator buttons and the steering arrows one control cluster. ]]
function CarLightsController._placeButtons(self)
	local cfg = TurnSignalConfig.Touch
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("DrivingHud")
	local controls = hud and hud:FindFirstChild("Controls")
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)

	if controls and controls:IsA("GuiObject") and controls ~= self._controls then
		if self._controlsConn then
			self._controlsConn:Disconnect()
		end
		self._controls = controls
		self._controlsConn = controls:GetPropertyChangedSignal("Visible"):Connect(function()
			if self._bound then
				self:_placeButtons()
			end
		end)
	end
	local shown = not (controls and controls:IsA("GuiObject")) or controls.Visible

	for side, action in ACTIONS do
		local button = ContextActionService:GetButton(action)
		local frame = button and button.Parent
		if not (button and frame and frame:IsA("GuiObject")) then
			continue
		end
		local arrow = controls and controls:FindFirstChild(STEER_BUTTONS[side])
		local centre, size
		if arrow and arrow:IsA("GuiObject") and arrow.AbsoluteSize.Y > 0 then
			local height = arrow.AbsoluteSize.Y
			centre = arrow.AbsolutePosition + arrow.AbsoluteSize * 0.5 - Vector2.new(0, height * cfg.Above)
			size = height * cfg.Size
		else
			local fallback = if side < 0 then cfg.Fallback.Left else cfg.Fallback.Right
			centre = Vector2.new(viewport.X * fallback.X, viewport.Y * fallback.Y)
			size = viewport.Y * cfg.Fallback.Size
		end
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Size = UDim2.fromOffset(size, size)
		button.Position = UDim2.fromOffset(centre.X - frame.AbsolutePosition.X, centre.Y - frame.AbsolutePosition.Y)
		button.Visible = shown
	end
end

--[[ Bind the keys, and on a touch device the two buttons, for the length of a race.

	Begin only: a signal is a tap, and everything else about the key (End, Cancel) is passed
	through untouched. Sunk on a press that took, passed on one that did not, which is what keeps
	the same key available to anything else while the shim is not driving. ]]
function CarLightsController._bind(self)
	if self._bound then
		return
	end
	self._bound = true
	local cfg = TurnSignalConfig
	local touch = cfg.Touch.Enabled and UserInputService.TouchEnabled
	for side, action in ACTIONS do
		local keys = if side < 0 then cfg.Keys.Left else cfg.Keys.Right
		ContextActionService:BindActionAtPriority(action, function(_, state)
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			return if self:_press(side) then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
		end, touch, cfg.BindPriority, table.unpack(keys))
		if touch then
			ContextActionService:SetTitle(action, if side < 0 then cfg.Touch.Titles.Left else cfg.Touch.Titles.Right)
		end
	end
	if touch then
		-- The HUD's arrows are enabled by DrivingHudController off the same RaceStart, in no fixed
		-- order with us, so the first placement waits a beat and the layout is followed after that.
		task.delay(0.2, function()
			if self._bound then
				self:_placeButtons()
			end
		end)
		local camera = workspace.CurrentCamera
		if camera then
			self._viewportConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				self:_placeButtons()
			end)
		end
	end
end

function CarLightsController._unbind(self)
	if not self._bound then
		return
	end
	self._bound = false
	for _, action in ACTIONS do
		ContextActionService:UnbindAction(action)
	end
	if self._viewportConn then
		self._viewportConn:Disconnect()
		self._viewportConn = nil
	end
	if self._controlsConn then
		self._controlsConn:Disconnect()
		self._controlsConn = nil
	end
	self._controls = nil
end

-- === The frame ================================================================

function CarLightsController._step(self)
	self:_bindCar(self._road:getCar())
	if self._dirty then
		self:_rebuild()
	end
	local now = os.clock()
	local driving = self._drive:isDriving()
	local weather = Shard.get("WeatherController")
	CarHeadlights.set(self._headlights, weather ~= nil and weather:currentEvent() ~= nil)
	if self._brakes then
		local braking = DriveConfig.AllowBrake and driving and self._drive:getThrottleInput() <= BRAKE_INPUT
		CarBrakeLights.set(self._brakes, braking, now)
	end
	self:_stepSignal(now, driving)
	CarBlinkers.signal(self._blinkers, self._signal, now)
end

-- === Public ===================================================================

--- PUBLIC: the side signalled right now, -1 left, 1 right, 0 none.
function CarLightsController.getSignal(self): number
	return self._signal
end

--- PUBLIC (an on-screen control that is not ours): press the stalk. Returns whether it took.
function CarLightsController.pressSignal(self, side: number): boolean
	return self:_press(side)
end

-- === Lifecycle ================================================================

function CarLightsController._onRaceStart(self)
	self:_onRaceEnd() -- idempotent: a revive re-enters through here and must not stack a second loop
	if not (self._drive and self._road) then
		return
	end
	local signals = TurnSignalConfig.Enabled
	if signals then
		self:_bind()
	end
	self._conn = RunService.Heartbeat:Connect(function()
		self:_step()
	end)
end

function CarLightsController._onRaceEnd(self)
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	self:_unbind()
	self._signal = 0
	self:_bindCar(nil)
end

CarLightsController:withRemoteEvents({
	{
		RaceStart = function()
			CarLightsController:_onRaceStart()
		end,
		RaceWrecked = function()
			CarLightsController:_onRaceEnd()
		end,
		RaceRevived = function()
			CarLightsController:_onRaceStart()
		end,
		RaceEnd = function()
			CarLightsController:_onRaceEnd()
		end,
	},
})

CarLightsController:withLifecycle({
	init = function(self)
		self._car = nil
		self._body = nil
		self._bodyConns = {}
		self._brakes = nil
		self._blinkers = nil
		self._dirty = false
		self._conn = nil
		self._bound = false
		self._viewportConn = nil
		self._controls = nil -- the driving HUD's touch control cluster, whose visibility ours follows
		self._controlsConn = nil
		self._signal = 0 -- -1 left, 1 right, 0 none
		self._signalAt = 0
		self._steered = false
	end,

	start = function(self)
		self._drive = Shard.get("DriveController")
		self._road = Shard.get("RoadController")
		if not (self._drive and self._road) then
			self.log:warn("DriveController or RoadController unavailable; the player's car lights are off.")
		end
	end,
})

return CarLightsController
