--[[
	StealNudgeController  (client)
	------------------------------
	A small line under the STOLEN! toast that reminds a long-cruising driver to steal something:
	"Don't forget to steal a car!" after a while with no steal, or "RED CAMARO ahead. Steal it!" when a
	better car than theirs is coming up. `StealNudgeConfig` has the rules, the copy and the look.

	IT IS A REMINDER, NOT A TUTORIAL. It never blocks, never plays a sound, never points. One line fades
	in, holds, fades out, and a whole run hears at most `MaxPerRun` of them, so a player who just wants
	to see how far they can drive is told a couple of times and then left alone.

	THE CLOCK ONLY RUNS WHILE THE PLAYER IS ACTUALLY DRIVING (`_driving`). Everything that is not that
	(the entry fade, a freeze, a jump, a wreck, the tutorial) pauses it rather than resetting it.

	It reads the other systems and owns nothing of theirs: `CarStolen` off the Dispatcher for a steal,
	`StealController:getFlight` for "mid-jump", `TrafficController:getCars` for what is ahead.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local StealNudgeConfig = require(ReplicatedStorage.shared.Configs.StealNudgeConfig)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local CarStats = require(ReplicatedStorage.shared.Modules.CarStats)

local StealNudgeController = Shard.new("StealNudgeController")

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)
--- Over the driving HUD (900), level with the STOLEN! toast (905), under the race fade (1000).
local DISPLAY_ORDER = 904
--- Seconds between scans of the traffic for a nice car. The answer only matters on a scale of seconds.
local SCAN_EVERY = 0.25

local function hex(color: Color3): string
	return string.format("#%02X%02X%02X", math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255))
end

-- === The line ===============================================================

function StealNudgeController._build(self)
	local ui = StealNudgeConfig.Ui
	local gui = Instance.new("ScreenGui")
	gui.Name = "StealNudge"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = DISPLAY_ORDER
	gui.Enabled = false

	local label = Instance.new("TextLabel")
	label.Name = "Line"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(ui.Position.X, ui.Position.Y)
	label.Size = UDim2.fromScale(ui.Size.X, ui.Size.Y)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.RichText = true
	label.TextWrapped = false
	label.TextColor3 = ui.TextColor
	label.TextTransparency = 1
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = ui.StrokeColor
	stroke.Thickness = 2
	stroke.Transparency = 1
	stroke.Parent = label

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self._gui, self._label, self._stroke = gui, label, stroke
end

function StealNudgeController._tween(self, seconds: number, text: number, stroke: number, y: number)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local ui = StealNudgeConfig.Ui
	TweenService:Create(self._label, info, {
		TextTransparency = text,
		Position = UDim2.new(ui.Position.X, 0, ui.Position.Y, y),
	}):Play()
	TweenService:Create(self._stroke, info, { Transparency = stroke }):Play()
end

function StealNudgeController._show(self, text: string)
	if not self._gui then
		return
	end
	local ui = StealNudgeConfig.Ui
	self._token += 1
	local token = self._token
	self._showing = true

	--[[ Sized here by hand rather than with TextScaled. TextScaled resolved while this gui was still
		disabled and stayed at 8px until a property was toggled, so the line drew at a third of its
		size. Off the viewport rather than the label's AbsoluteSize, which is the number a disabled gui
		cannot be trusted to have, and read per nudge so a resized window is picked up. ]]
	local height = workspace.CurrentCamera.ViewportSize.Y * ui.Size.Y
	self._label.TextSize = math.min(ui.MaxTextSize, math.floor(height * 0.9))
	self._label.Text = text
	self._label.TextTransparency = 1
	self._stroke.Transparency = 1
	self._label.Position = UDim2.new(ui.Position.X, 0, ui.Position.Y, ui.Rise)
	self._gui.Enabled = true
	self:_tween(ui.FadeIn, 0, ui.StrokeTransparency, 0)

	task.delay(ui.FadeIn + ui.Hold, function()
		if self._token == token then
			self:_hide(ui.FadeOut)
		end
	end)
end

--- Fade the line out over `seconds`, or drop it at once with 0. Safe to call with nothing showing.
function StealNudgeController._hide(self, seconds: number)
	if not (self._gui and self._showing) then
		return
	end
	self._token += 1
	local token = self._token
	self._showing = false
	if seconds <= 0 then
		self._gui.Enabled = false
		return
	end
	self:_tween(seconds, 1, 1, 0)
	task.delay(seconds, function()
		if self._token == token then
			self._gui.Enabled = false
		end
	end)
end

-- === When to speak ==========================================================

--- The car under the player, or nil while the road has not latched one.
function StealNudgeController._car(self): Model?
	local car = self._road and self._road:getCar()
	return if car and car.Parent and car.PrimaryPart then car else nil
end

--[[ Is this a moment of plain driving? The clock only runs, and a nudge only lands, when it is.

	The anchored check is there because an anchored part keeps reporting the velocity it had when it
	was anchored, so a car frozen behind the entry fade would otherwise count as cruising. ]]
function StealNudgeController._driving(self): boolean
	if not self._active or self._wrecked then
		return false
	end
	if self._tutorial and self._tutorial:isActive() then
		return false
	end
	if self._freeze and self._freeze:isHeld() then
		return false
	end
	if self._steal and self._steal:getFlight() ~= "idle" then
		return false
	end
	local car = self:_car()
	local root = car and car.PrimaryPart
	if not root or root.Anchored then
		return false
	end
	return root.AssemblyLinearVelocity.Magnitude >= StealNudgeConfig.MinSpeed
end

--- Has the run got room for another nudge right now?
function StealNudgeController._canSpeak(self): boolean
	return self._spoken < StealNudgeConfig.MaxPerRun and self._sinceNudge >= StealNudgeConfig.Cooldown
end

function StealNudgeController._speak(self, text: string)
	self._spoken += 1
	self._sinceNudge = 0
	self:_show(text)
end

--[[ The best car in the window ahead that beats the player's own, or nil.

	"Beats" is by rarity band, and it has to clear `MinBand` as well, so a Beater driver is not told
	about a Sedan. Physical shells (cars already knocked about) and frozen ones are skipped for the
	same reason `TrafficController.hasCarAhead` skips them: neither is a car on offer. ]]
function StealNudgeController._niceCarAhead(self)
	local cfg = StealNudgeConfig.NiceCar
	local traffic = self._traffic
	local car = self:_car()
	if not (traffic and car) then
		return nil
	end
	local _, ownBand = CarRarity.of(CarStats.bodyOf(car))
	local floor = math.max(cfg.MinBand, ownBand + 1)

	local playerAlong = traffic:playerAlong()
	local best, bestBand = nil, 0
	for _, rec in traffic:getCars() do
		if rec.physical or rec.frozen or type(rec.body) ~= "string" then
			continue
		end
		local ahead = rec.along - playerAlong
		if ahead < cfg.MinAhead or ahead > cfg.MaxAhead then
			continue
		end
		local _, band = CarRarity.of(rec.body)
		if band >= floor and band > bestBand then
			best, bestBand = rec, band
		end
	end
	return best, bestBand
end

function StealNudgeController._niceCarLine(self, rec, band: number): string
	local name = GarageConfig.carName(rec.body, if type(rec.paint) == "number" then rec.paint else nil)
	local coloured = string.format('<font color="%s">%s</font>', hex(CarRarity.colourOf(band)), name)
	return string.format(StealNudgeConfig.NiceCar.Line, coloured)
end

function StealNudgeController._step(self, dt: number)
	if not self:_driving() then
		-- A jump or a steal starting is the player doing the thing; get out of the way.
		if self._showing and self._steal and self._steal:getFlight() ~= "idle" then
			self:_hide(StealNudgeConfig.Ui.FadeOutQuick)
		end
		return
	end

	self._sinceSteal += dt
	self._sinceNudge += dt
	if self._showing or not self:_canSpeak() then
		return
	end

	local idle = StealNudgeConfig.Idle
	if idle.Enabled and not self._stoleThisRun then
		local due = idle.First + idle.Every * self._idleSpoken
		if self._sinceSteal >= due and #idle.Lines > 0 then
			local text = idle.Lines[self._idleSpoken % #idle.Lines + 1]
			self._idleSpoken += 1
			self:_speak(text)
			return
		end
	end

	local nice = StealNudgeConfig.NiceCar
	if nice.Enabled and self._sinceSteal >= nice.Quiet then
		self._scanIn -= dt
		if self._scanIn > 0 then
			return
		end
		self._scanIn = SCAN_EVERY
		local rec, band = self:_niceCarAhead()
		if rec then
			self:_speak(self:_niceCarLine(rec, band))
		end
	end
end

-- === Lifecycle ==============================================================

function StealNudgeController._reset(self)
	self._active = false
	self._wrecked = false
	self._stoleThisRun = false
	self._spoken = 0
	self._idleSpoken = 0
	self._sinceSteal = 0
	-- Starts full so the first nudge of a run is gated by its own rule, not by the cooldown.
	self._sinceNudge = math.huge
	self._scanIn = 0
	self:_hide(0)
end

function StealNudgeController._onRaceStart(self)
	self:_reset()
	self._active = true
end

function StealNudgeController._onStolen(self)
	self._stoleThisRun = true
	self._sinceSteal = 0
	self:_hide(StealNudgeConfig.Ui.FadeOutQuick)
end

StealNudgeController:withRemoteEvents({
	{
		RaceStart = function()
			StealNudgeController:_onRaceStart()
		end,
		-- A wreck pauses the clock and a revive resumes it. The run carries on, so nothing resets.
		RaceWrecked = function()
			StealNudgeController._wrecked = true
			StealNudgeController:_hide(0)
		end,
		RaceRevived = function()
			StealNudgeController._wrecked = false
		end,
		RaceEnd = function()
			StealNudgeController:_reset()
		end,
	},
})

StealNudgeController:withLifecycle({
	init = function(self)
		self._token = 0
		self._showing = false
		self._gui = nil :: ScreenGui?
		self:_reset()
	end,

	start = function(self)
		if not StealNudgeConfig.Enabled then
			return
		end
		self._road = Shard.get("RoadController")
		self._traffic = Shard.get("TrafficController")
		self._steal = Shard.get("StealController")
		self._freeze = Shard.get("RaceFreezeController")
		self._tutorial = Shard.get("TutorialController")

		Dispatcher:Subscribe("CarStolen", function()
			self:_onStolen()
		end)
		-- Spawned rather than awaited: `_build` waits on PlayerGui, and `Shard.start()` is the boot barrier.
		task.spawn(function()
			self:_build()
			self._conn = RunService.Heartbeat:Connect(function(dt)
				self:_step(dt)
			end)
		end)
	end,
})

StealNudgeController:withCleanup(function()
	if StealNudgeController._conn then
		StealNudgeController._conn:Disconnect()
		StealNudgeController._conn = nil
	end
end)

return StealNudgeController
