--[[
	SpeedTrapController  (client)
	-----------------------------
	Camera gantries across the road that rate how fast you went through them (`SpeedTrapConfig`).

	ONE TRAP AT A TIME. The next trap's `along` coordinate is decided the moment the last one is passed
	(or at run start); its gantry is built once it is `BuildAhead` studs away and destroyed a little
	after you go under it. Positions are road-frame scalars like traffic's, so a world rebase is one
	addition (`_onWorldShift`).

	The gantry is cosmetic and never collides, queries or touches. The crossing is a coordinate test,
	not a Touched event, so it cannot be missed at speed.

	PAID SINCE 2026-09-28 (`SpeedTrapConfig.Pay`): a crossing tells `SpeedTrapService`, which measures
	the car's speed itself, pays and keeps the per-world best. The toast goes up on the crossing frame
	with this client's own rating, and the server's answer rewrites it with the real rating, the cash
	and NEW BEST (`_onResult`).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local SpeedTrapConfig = require(ReplicatedStorage.shared.Configs.SpeedTrapConfig)
--- For one function: the payout on the toast (`_setResultText`).
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local WindConfig = require(ReplicatedStorage.shared.Configs.WindConfig)

local SpeedTrapController = Shard.new("SpeedTrapController")

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)
local FOLDER_NAME = "SpeedTraps"
-- Studs past the gantry before it is torn down: far enough that it is off the back of the shot.
local CLEANUP_BEHIND = 120

local function part(name: string, size: Vector3, color: Color3, material: Enum.Material, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function outlinedLabel(parent: Instance, name: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.TextScaled = true
	label.TextColor3 = SpeedTrapConfig.Ui.TextColor
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	return label
end

-- === World ===================================================================

function SpeedTrapController._buildGantry(self, info, along: number)
	local cfg = SpeedTrapConfig.Gantry
	local folder = workspace:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = workspace
	end

	local model = Instance.new("Model")
	model.Name = "SpeedTrap"

	local half = if type(info.driveWidth) == "number" then info.driveWidth * 0.5 + 4 else cfg.HalfSpan
	local forward, cross = info.forward, info.cross
	local base = forward * along + cross * info.driveCenter + Vector3.yAxis * info.deckY
	-- Faces back down the road at the driver.
	local facing = CFrame.lookAt(Vector3.zero, -forward)

	for _, sideSign in { -1, 1 } do
		local post = part("Post", cfg.PostSize, cfg.PostColor, Enum.Material.Metal, model)
		post.CFrame = facing + base + cross * (half * sideSign) + Vector3.yAxis * (cfg.PostSize.Y * 0.5)
	end

	local beamY = cfg.Height
	local beam = part("Beam", Vector3.new(half * 2 + cfg.PostSize.X, cfg.BeamThickness, cfg.BeamThickness), cfg.PostColor, Enum.Material.Metal, model)
	beam.CFrame = facing + base + Vector3.yAxis * beamY

	local sign = part("Sign", Vector3.new(34, 7, 1), cfg.SignColor, Enum.Material.SmoothPlastic, model)
	sign.CFrame = facing + base + Vector3.yAxis * (beamY - cfg.BeamThickness * 0.5 - 3.8) - forward * 0.5
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 30
	surface.LightInfluence = 0
	surface.Parent = sign
	local text = outlinedLabel(surface, "Text")
	text.Position = UDim2.fromScale(0.5, 0.5)
	text.Size = UDim2.fromScale(0.92, 0.8)
	text.Text = cfg.SignText
	text.TextColor3 = cfg.LightColor

	local camBox = part("Camera", Vector3.new(3, 2.4, 3.6), cfg.SignColor, Enum.Material.Metal, model)
	camBox.CFrame = facing * CFrame.Angles(math.rad(-12), 0, 0) + base + cross * (half * 0.55) + Vector3.yAxis * (beamY - 2.4)
	local lens = part("Lens", Vector3.new(1.4, 1.4, 0.4), cfg.LightColor, Enum.Material.Neon, model)
	lens.CFrame = camBox.CFrame * CFrame.new(0, 0, -1.9)
	local light = Instance.new("PointLight")
	light.Color = cfg.FlashColor
	light.Range = 60
	light.Brightness = 0
	light.Parent = lens

	model.Parent = folder
	return { model = model, lens = lens, light = light }
end

function SpeedTrapController._destroyGantry(self)
	local trap = self._trap
	if trap and trap.gantry then
		trap.gantry.model:Destroy()
		trap.gantry = nil
	end
end

-- === Screen ==================================================================

function SpeedTrapController._build(self)
	local ui = SpeedTrapConfig.Ui
	local gui = Instance.new("ScreenGui")
	gui.Name = "SpeedTrapHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 900
	gui.Enabled = false

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Parent = gui

	local warn = outlinedLabel(gui, "Warn")
	warn.Position = UDim2.fromScale(ui.WarnPosition.X, ui.WarnPosition.Y)
	warn.Size = UDim2.fromScale(ui.WarnSize.X, ui.WarnSize.Y)
	warn.TextColor3 = ui.WarnColor
	warn.Visible = false

	local result = Instance.new("Frame")
	result.Name = "Result"
	result.AnchorPoint = Vector2.new(0.5, 0.5)
	result.Position = UDim2.fromScale(ui.ResultPosition.X, ui.ResultPosition.Y)
	result.Size = UDim2.fromScale(ui.ResultSize.X, ui.ResultSize.Y)
	result.BackgroundTransparency = 1
	result.Visible = false
	result.Parent = gui
	local resultScale = Instance.new("UIScale")
	resultScale.Parent = result

	local rating = outlinedLabel(result, "Rating")
	rating.Position = UDim2.fromScale(0.5, 0.3)
	rating.Size = UDim2.fromScale(1, 0.55)
	local detail = outlinedLabel(result, "Detail")
	detail.Position = UDim2.fromScale(0.5, 0.78)
	detail.Size = UDim2.fromScale(1, 0.34)
	detail.RichText = true

	self._gui = gui
	self._flash = flash
	self._warn = warn
	self._result = result
	self._resultScale = resultScale
	self._ratingLabel = rating
	self._detailLabel = detail
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function hex(color: Color3): string
	return string.format("#%02X%02X%02X", math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255))
end

--[[ The toast's words. `cash` is the server's payout (2026-09-28, `SpeedTrapConfig.Pay`), nil until it
	has answered — the rating shown before then is the client's own, and is replaced by the server's. ]]
function SpeedTrapController._setResultText(self, rating, mph: number, best: boolean, cash: number?)
	local ui = SpeedTrapConfig.Ui
	self._ratingLabel.Text = if rating then rating.Name else SpeedTrapConfig.MissLabel
	self._ratingLabel.TextColor3 = if rating then rating.Color else SpeedTrapConfig.MissColor
	local detail = string.format("%d MPH", mph)
	if cash and cash > 0 then
		detail ..= string.format('  <font color="%s">+%s</font>', hex(ui.BestColor), GarageConfig.formatCash(cash))
	end
	if best then
		detail ..= string.format('  <font color="%s">NEW BEST</font>', hex(ui.BestColor))
	end
	self._detailLabel.Text = detail
end

--- Hold the toast for `Ui.Hold` from now, then fade it — unless a newer toast has taken over.
function SpeedTrapController._holdResult(self)
	local ui = SpeedTrapConfig.Ui
	self._token += 1
	local token = self._token
	local labels = { self._ratingLabel, self._detailLabel }
	task.delay(ui.Hold, function()
		if self._token ~= token then
			return
		end
		local info = TweenInfo.new(ui.FadeTime)
		local strokeInfo = TweenInfo.new(ui.FadeTime * ui.StrokeFade)
		for _, label in labels do
			TweenService:Create(label, info, { TextTransparency = 1 }):Play()
			TweenService:Create(label.UIStroke, strokeInfo, { Transparency = 1 }):Play()
		end
		task.delay(ui.FadeTime, function()
			if self._token == token then
				self._result.Visible = false
			end
		end)
	end)
end

--[[ The server's answer to the crossing: its rating, the measured mph, the cash and whether it was a
	best. Rewrites the toast that is already up (it went up on the crossing frame) and restarts its
	hold, so the money is on screen for the full `Ui.Hold` rather than the tail of it. ]]
function SpeedTrapController._onResult(self, ratingName: unknown, mph: unknown, cash: unknown, best: unknown)
	if not self._gui then
		return
	end
	local rating = SpeedTrapConfig.ratingNamed(ratingName)
	self:_setResultText(rating, tonumber(mph) or 0, best == true, tonumber(cash))
	for _, label in { self._ratingLabel, self._detailLabel } do
		label.TextTransparency = 0
		label.UIStroke.Transparency = 0
	end
	self._result.Visible = true
	self:_holdResult()
end

function SpeedTrapController._showResult(self, rating, mph: number, best: boolean)
	local ui = SpeedTrapConfig.Ui
	if not self._gui then
		return
	end
	self._token += 1
	local token = self._token

	self._flash.BackgroundTransparency = ui.FlashTransparency
	TweenService:Create(self._flash, TweenInfo.new(ui.FlashTime), { BackgroundTransparency = 1 }):Play()

	self:_setResultText(rating, mph, best, nil)
	local labels = { self._ratingLabel, self._detailLabel }
	for _, label in labels do
		label.TextTransparency = 0
		label.UIStroke.Transparency = 0
	end
	self._result.Visible = true
	self._resultScale.Scale = ui.PopFrom
	TweenService:Create(self._resultScale, TweenInfo.new(ui.PopTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = if rating and rating == SpeedTrapConfig.Ratings[1] then ui.GoldScale else 1,
	}):Play()

	task.delay(ui.Hold, function()
		if self._token ~= token then
			return
		end
		-- The outlines fade too, and first: left at full they hang on screen after the letters go.
		local info = TweenInfo.new(ui.FadeTime)
		local strokeInfo = TweenInfo.new(ui.FadeTime * ui.StrokeFade)
		for _, label in labels do
			TweenService:Create(label, info, { TextTransparency = 1 }):Play()
			TweenService:Create(label.UIStroke, strokeInfo, { Transparency = 1 }):Play()
		end
		task.delay(ui.FadeTime, function()
			if self._token == token then
				self._result.Visible = false
			end
		end)
	end)
end

function SpeedTrapController._play(self, group: string)
	if self._sounds and group ~= "" then
		self._sounds:PlayRandom(group)
	end
end

-- === The frame ===============================================================

function SpeedTrapController._topSpeed(self): number?
	local dial = self._drive and self._drive:getTopSpeed()
	return if dial then dial * WindConfig.StudsPerMaxSpeed else nil
end

function SpeedTrapController._trigger(self, speed: number, world)
	local trap = self._trap
	local top = self:_topSpeed()
	local rating = if top then SpeedTrapConfig.ratingFor(speed, top) else nil
	local mph = SpeedTrapConfig.mph(speed)

	--[[ With traps paying, the server measures, prices and keeps the best (`SpeedTrapService`): this
		says "crossed" and the toast shows no best until the server's answer rewrites it. Off, the
		session best is kept here as it always was. ]]
	local best = false
	if SpeedTrapConfig.Pay.Enabled then
		self:getRemoteEvent("SpeedTrapCrossed"):Fire()
	else
		local key = world or "default"
		best = rating ~= nil and mph > (self._best[key] or 0)
		if best then
			self._best[key] = mph
		end
	end

	if trap and trap.gantry then
		local light, lens = trap.gantry.light, trap.gantry.lens
		light.Brightness = 12
		lens.Color = SpeedTrapConfig.Gantry.FlashColor
		TweenService:Create(light, TweenInfo.new(0.35), { Brightness = 0 }):Play()
	end

	self:_play(SpeedTrapConfig.Ui.ShutterSound)
	if rating == SpeedTrapConfig.Ratings[1] then
		self:_play(SpeedTrapConfig.Ui.GoldSound)
	end
	if rating and rating.Nitro > 0 and self._nitro then
		self._nitro:reward(rating.Nitro)
	end
	self:_showResult(rating, mph, best)
end

function SpeedTrapController._step(self)
	local road = self._road
	local info = road and road:getRoadInfo()
	local car = road and road:getCar()
	local primary = car and car.PrimaryPart
	if not (info and primary) then
		return
	end

	local forward = info.forward
	local myAlong = primary.Position:Dot(forward)
	if not self._nextAlong then
		self._nextAlong = myAlong + SpeedTrapConfig.FirstAt
	end

	local trap = self._trap
	if not trap then
		trap = { along = self._nextAlong, triggered = false }
		self._trap = trap
	end

	local ahead = trap.along - myAlong
	if not trap.gantry and ahead <= SpeedTrapConfig.BuildAhead and ahead > 0 then
		trap.gantry = self:_buildGantry(info, trap.along)
	end

	if not trap.triggered then
		if self._warn then
			local show = ahead > 0 and ahead <= SpeedTrapConfig.WarnAhead
			if show and not self._warn.Visible then
				--- Placed as it appears: a phone takes `Ui.WarnTouchPosition` (M4, 2026-10-13).
				local ui = SpeedTrapConfig.Ui
				local phone = UserInputService.PreferredInput == Enum.PreferredInput.Touch and ui.WarnTouchPosition ~= nil
				local at = if phone then ui.WarnTouchPosition else ui.WarnPosition
				local size = if phone then ui.WarnTouchSize else ui.WarnSize
				self._warn.Position = UDim2.fromScale(at.X, at.Y)
				self._warn.Size = UDim2.fromScale(size.X, size.Y)
			end
			self._warn.Visible = show
			if show then
				self._warn.Text = string.format("SPEED TRAP  %dm", math.floor(ahead / SpeedTrapConfig.Ui.StudsPerMeter))
			end
		end
		if ahead <= 0 then
			trap.triggered = true
			if self._warn then
				self._warn.Visible = false
			end
			-- Mid-bail the car is anchored and flown, so its speed is not a driven speed: no rating.
			if self._drive and self._drive:isDriving() then
				self:_trigger(primary.AssemblyLinearVelocity:Dot(forward), info.world)
			end
		end
	elseif ahead < -CLEANUP_BEHIND then
		self:_destroyGantry()
		self._trap = nil
		self._nextAlong = SpeedTrapConfig.nextAlong(trap.along, self._rng:NextNumber())
	end

	if self._gui then
		self._gui.Enabled = true
	end
end

function SpeedTrapController._onWorldShift(self, shift: Vector3)
	local info = self._road and self._road:getRoadInfo()
	-- Not gated on `_active`: a course kept through a wreck still has to ride a rebase that lands
	-- during the revive offer, or the trap would come back hundreds of studs out of place.
	if not (info and (self._trap or self._nextAlong)) then
		return
	end
	local delta = shift:Dot(info.forward)
	if self._nextAlong then
		self._nextAlong += delta
	end
	local trap = self._trap
	if trap then
		trap.along += delta
		if trap.gantry then
			trap.gantry.model:PivotTo(trap.gantry.model:GetPivot() + shift)
		end
	end
end

-- === Lifecycle ===============================================================

function SpeedTrapController._onRaceStart(self)
	self:_onRaceEnd()
	-- No traps on the tutorial's run (`TutorialConfig.isTutorialRun`), latched for the whole run.
	self._tutorialRun = TutorialConfig.isTutorialRun(Players.LocalPlayer:GetAttribute(TutorialConfig.StepAttribute))
	if not SpeedTrapConfig.Enabled or self._tutorialRun then
		return
	end
	self._active = true
	self._conn = RunService.Heartbeat:Connect(function()
		self:_step()
	end)
end

--[[ `keepCourse` is the wreck: the trap and its position stay for the revive. Everything else starts
	the course over. ]]
function SpeedTrapController._onRaceEnd(self, keepCourse: boolean?)
	self._active = false
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	if not keepCourse then
		self:_destroyGantry()
		self._trap = nil
		self._nextAlong = nil
	end
	if self._warn then
		self._warn.Visible = false
	end
	if self._gui then
		self._gui.Enabled = false
	end
end

SpeedTrapController:withRemoteEvents({
	{
		RaceStart = function()
			SpeedTrapController:_onRaceStart()
		end,
		RaceWrecked = function()
			SpeedTrapController:_onRaceEnd(true)
		end,
		RaceRevived = function()
			if SpeedTrapController._tutorialRun or not SpeedTrapConfig.Enabled then
				return
			end
			SpeedTrapController._active = true
			if not SpeedTrapController._conn then
				SpeedTrapController._conn = RunService.Heartbeat:Connect(function()
					SpeedTrapController:_step()
				end)
			end
		end,
		RaceEnd = function()
			SpeedTrapController:_onRaceEnd()
		end,
		-- The end panel is up (`RaceService.holdEndPanel`): the run is over, and on a getaway the
		-- truck is still tearing down the road, so the countdown to the next trap would sit over it.
		-- Stood down like a wreck, the gantry kept for the teardown to take.
		RaceEndPanel = function()
			SpeedTrapController:_onRaceEnd(true)
		end,
		SpeedTrapResult = function(ratingName, mph, cash, best)
			SpeedTrapController:_onResult(ratingName, mph, cash, best)
		end,
	},
	"SpeedTrapCrossed",
})

SpeedTrapController:withLifecycle({
	init = function(self)
		self._active = false
		self._tutorialRun = false -- latched at race start; see `_onRaceStart`
		self._conn = nil :: RBXScriptConnection?
		self._trap = nil -- { along, triggered, gantry? }
		self._nextAlong = nil :: number?
		self._best = {} -- [world] = best rated mph this session
		self._token = 0
		self._rng = Random.new()
	end,

	start = function(self)
		self._road = Shard.get("RoadController")
		self._drive = Shard.get("DriveController")
		self._nitro = Shard.get("NitroController")
		self._sounds = Shard.get("SoundController")
		if self._sounds and SpeedTrapConfig.Ui.ShutterSound ~= "" then
			self._sounds:Preload(SpeedTrapConfig.Ui.ShutterSound)
		end
		if self._road then
			self._road:onWorldShift(function(shift)
				self:_onWorldShift(shift)
			end)
		end
		if SpeedTrapConfig.Enabled and SpeedTrapConfig.Ui.Enabled then
			task.spawn(function()
				self:_build()
			end)
		end
	end,
})

SpeedTrapController:withCleanup(function()
	SpeedTrapController:_onRaceEnd()
end)

return SpeedTrapController
