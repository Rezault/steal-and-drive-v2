--[[ RoamingCarController — draws the highway cars and turns a jump into stealing one
	==================================================================================

	EVERYTHING HERE IS PRESENTATION. Which cars exist, where they are going and who gets them is
	`RoamingCarService`'s; this file reads the `Configuration` per car it replicates and draws it:

	  • A SHELL per nearby car, cloned from `ReplicatedStorage.TrafficCars` (the same anchored,
	    physics-free shells the road run used), painted and mutated, posed every frame from the leg
	    attributes with `CollectorConfig.positionAt` — the same function the server checks with.
	    Only cars within `RENDER_RADIUS` of the camera have a shell; the rest are just attributes.
	  • A LABEL over each: mutation / SECRET / new! tags, rarity in its colour, the car's name and
	    "Required: ⚡N" in green when you meet it and red when you do not. Sized in studs, so it
	    shrinks with distance like the reference's.
	  • THE LEAP (`CollectorConfig.Leap`): the nearest car you can steal within `Range` is outlined
	    and its label says JUMP!. Jump (`JumpRequest`: Space, the mobile button, gamepad A — one input
	    on every device) and you fly at where it will be, flip, land on the roof and ride it for a beat
	    while the server decides. "ok" bursts the car into sparkles; anything else just drops you off.
	  • ZONE BARRIERS: a glowing wall across the line of every zone whose cheapest car is beyond
	    your Steal Power, solid for you only. The server re-checks power on every steal anyway, so
	    the wall is a signpost, not the lock.

	The result of a steal is published on `Dispatcher` ("CollectorCaptured") for the HUD's toast. ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local CollectorConfig = require(ReplicatedStorage.shared.Configs.CollectorConfig)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
local CarNameConfig = require(ReplicatedStorage.shared.Configs.CarNameConfig)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local CarPaint = require(ReplicatedStorage.shared.Modules.CarPaint)
local CarMutation = require(ReplicatedStorage.shared.Modules.CarMutation)
local CarCatalogue = require(ReplicatedStorage.shared.Modules.CarCatalogue)
local Feedback = require(ReplicatedStorage.shared.Modules.GameplayFeedback)

local Remotes = CollectorConfig.Remotes
local FONT = Font.fromEnum(Enum.Font.FredokaOne)
local RENDER_RADIUS = 330
local GREEN = Color3.fromRGB(110, 235, 90)
local RED = Color3.fromRGB(255, 84, 84)

type Rec = {
	inst: Configuration,
	model: Model?,
	lift: number,
	height: number,
	yaw: number,
	label: BillboardGui?,
	jump: TextLabel?,
	need: TextLabel?,
	dust: ParticleEmitter?,
	dipAt: number?,
	a: Vector3?,
	b: Vector3?,
	t0: number?,
	t1: number?,
	required: number,
}

local Controller = Shard.new("RoamingCarController")

Controller:withRemoteEvents({
	Remotes.Capture,
	{
		[Remotes.Captured] = function(result)
			Controller:_onResult(result)
		end,
	},
})

function Controller.displayName(body: string): string
	return CarNameConfig.nameOf(body) or body
end

function Controller._power(self): number
	return CollectorConfig.powerOf(self._player)
end

local function floorY(): number
	return CollectorConfig.Corridor.FloorY + CollectorConfig.Road.Lift
end

local function flat(v: Vector3): number
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

-- === Shells ==================================================================

function Controller._buildModel(self, rec: Rec)
	local inst = rec.inst
	local body = inst:GetAttribute("Body")
	local folder = ReplicatedStorage:FindFirstChild(TrafficConfig.TemplateFolderName)
	local template = folder and folder:FindFirstChild(body)
	if not (template and template:IsA("Model")) then
		return
	end
	local model = template:Clone()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.CastShadow = false
		end
	end
	CarPaint.apply(model, inst:GetAttribute("Paint"), body)
	local mutation = inst:GetAttribute("Mutation")
	if mutation ~= "" then
		CarMutation.apply(model, mutation, true)
	end

	-- Stand it on the floor: how far the pivot sits above the lowest point of the bodywork.
	local pivot = model:GetPivot()
	local box, size = model:GetBoundingBox()
	rec.lift = pivot.Position.Y - (box.Position.Y - size.Y / 2)
	rec.height = size.Y

	local root = model.PrimaryPart or model:FindFirstChild("Root")
	if root and root:IsA("BasePart") then
		local attachment = Instance.new("Attachment")
		attachment.Position = Vector3.new(0, -rec.lift + 0.5, (inst:GetAttribute("BodyLength") or size.Z) * 0.45)
		attachment.Parent = root
		local dust = Instance.new("ParticleEmitter")
		dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
		dust.Color = ColorSequence.new(Color3.fromRGB(200, 200, 205))
		dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5) })
		dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })
		dust.Lifetime = NumberRange.new(0.5, 0.9)
		dust.Speed = NumberRange.new(2, 4)
		dust.SpreadAngle = Vector2.new(25, 25)
		dust.Rate = 0
		dust.Parent = attachment
		rec.dust = dust

		if inst:GetAttribute("Secret") then
			local highlight = Instance.new("Highlight")
			highlight.FillColor = Color3.fromRGB(255, 210, 60)
			highlight.FillTransparency = 0.75
			highlight.OutlineColor = Color3.fromRGB(255, 240, 150)
			highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			highlight.Parent = model
			local sparkle = Instance.new("Sparkles")
			sparkle.SparkleColor = Color3.fromRGB(255, 220, 90)
			sparkle.Parent = root
		end
		-- Adorned to the biggest visible part, AFTER the model is in the workspace (2026-11-01, Studio
		-- play): a billboard whose adornee was parented later never drew.
		model.Parent = self._world
		local anchor, volume = root, -1
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Transparency < 1 then
				local v = part.Size.X * part.Size.Y * part.Size.Z
				if v > volume then
					anchor, volume = part, v
				end
			end
		end
		-- Bottom edge half a stud over the roof: label height 4.8, so its centre is 2.9 above the top.
		local above = box.Position.Y + size.Y / 2 - anchor.Position.Y + 2.9
		rec.label = self:_buildLabel(rec, anchor, above)
	end
	model.Name = "Roaming_" .. inst.Name
	model.Parent = self._world -- no-op when the label branch already did it
	rec.model = model
end

function Controller._buildLabel(self, rec: Rec, adornee: BasePart, above: number): BillboardGui
	local inst = rec.inst
	local body = inst:GetAttribute("Body")
	local cfg = CollectorConfig.Label
	local gui = Instance.new("BillboardGui")
	gui.Name = "RoamLabel"
	gui.Adornee = adornee
	-- Depth-tested: a label floating through gates and buildings read as clutter. It sits
	-- StudsOffset above the roof, so the car itself never hides it.
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = cfg.MaxDistance
	gui.Size = UDim2.fromScale(12, 4.8) -- studs: shrinks with distance
	gui.StudsOffsetWorldSpace = Vector3.new(0, above, 0)
	gui.ResetOnSpawn = false

	local function line(y: number, h: number, text: string, color: Color3): TextLabel
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromScale(0, y)
		t.Size = UDim2.fromScale(1, h)
		t.FontFace = FONT
		t.TextScaled = true
		t.Text = text
		t.TextColor3 = color
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2.5
		stroke.Color = Color3.fromRGB(20, 22, 32)
		stroke.Parent = t
		t.Parent = gui
		return t
	end

	local tags = {}
	if inst:GetAttribute("Secret") then
		table.insert(tags, '<font color="#FFD23C">SECRET</font>')
	end
	local mutation = WeatherConfig.mutationOf(inst:GetAttribute("Mutation"))
	if mutation then
		table.insert(tags, string.format('<font color="#%s">%s</font>', mutation.Color:ToHex(), mutation.Name))
	end
	if not self._found[body] then
		table.insert(tags, '<font color="#FF3B3B">new!</font>')
	end
	if #tags > 0 then
		local tag = line(0, 0.2, table.concat(tags, "  "), Color3.new(1, 1, 1))
		tag.RichText = true
	end
	local rarity, colour = CarRarity.labelOf(body)
	line(0.18, 0.3, rarity, colour)
	line(0.46, 0.24, Controller.displayName(body), Color3.new(1, 1, 1))
	rec.need = line(0.7, 0.26, "", GREEN)

	-- The call to action on the targeted car, under its requirement.
	local jump = line(1.0, 0.3, self:_jumpText(), Color3.fromRGB(255, 235, 90))
	jump.Name = "Jump"
	jump.Visible = false
	rec.jump = jump

	gui.Parent = self._labels
	self:_paintNeed(rec)
	return gui
end

--- What the JUMP! tag says: the input to press on this device.
function Controller._jumpText(self): string
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Ⓐ JUMP!"
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "TAP JUMP!"
	end
	return "SPACE · JUMP!"
end

function Controller._paintNeed(self, rec: Rec)
	local need = rec.need
	if not need then
		return
	end
	local required = rec.inst:GetAttribute("Required") or 0
	local ok = self._powerNow >= required
	need.Text = string.format("Required: ⚡%s", tostring(required))
	need.TextColor3 = if ok then GREEN else RED
end

function Controller._drop(self, rec: Rec)
	if self._target == rec then
		self:_setTarget(nil)
	end
	if rec.model then
		rec.model:Destroy()
		rec.model = nil
	end
	if rec.label then
		rec.label:Destroy()
		rec.label = nil
	end
	rec.jump, rec.need, rec.dust = nil, nil, nil
end

-- === Frame ===================================================================

function Controller._step(self)
	local t = workspace:GetServerTimeNow()
	local camera = workspace.CurrentCamera
	local focus = camera and camera.Focus.Position or Vector3.zero
	local character = self._player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local me = if root and root:IsA("BasePart") then root.Position else nil
	local y = floorY()
	local range = CollectorConfig.Leap.Range

	local best: Rec?, bestDistance = nil, range
	for inst, rec in self._recs do
		local a, b, t0, t1 = rec.a, rec.b, rec.t0, rec.t1
		if not (a and b and t0 and t1) then
			continue
		end
		local pos = CollectorConfig.positionAt(a, b, t0, t1, t)
		local near = (pos - focus).Magnitude < RENDER_RADIUS
		if near and not rec.model then
			self:_buildModel(rec)
		elseif not near and rec.model then
			self:_drop(rec)
		end
		local model = rec.model
		if model then
			local moving = t < t1 and (b - a).Magnitude > 0.5
			if moving then
				local dir = b - a
				rec.yaw = math.atan2(-dir.X, -dir.Z)
			end
			-- A short dip when somebody lands on the roof.
			local dip = 0
			if rec.dipAt then
				local k = (os.clock() - rec.dipAt) / 0.3
				if k < 1 then
					dip = -0.8 * math.sin(k * math.pi)
				else
					rec.dipAt = nil
				end
			end
			model:PivotTo(CFrame.new(pos.X, y + rec.lift + dip, pos.Z) * CFrame.Angles(0, rec.yaw, 0))
			if rec.dust then
				rec.dust.Rate = if moving then 14 else 0
			end
		end
		-- Target: the nearest car you can take, not one already being landed on, with enough road
		-- left that it is still there when you come down.
		if me and rec.model and not self._pending[inst.Name] and not self._leaping then
			local distance = flat(pos - me)
			if
				distance < bestDistance
				and math.abs(pos.Y - me.Y) < 25
				and self._powerNow >= rec.required
				and t1 - t > CollectorConfig.Leap.Time[2] + 0.2
			then
				best, bestDistance = rec, distance
			end
		end
	end
	self:_setTarget(best)
end

function Controller._setTarget(self, target: Rec?)
	if target == self._target then
		return
	end
	local old = self._target
	if old and old.jump then
		old.jump.Visible = false
	end
	self._target = target
	if target and target.model then
		self._highlight.Adornee = target.model
		self._highlight.Enabled = true
		if target.jump then
			target.jump.Text = self:_jumpText()
			target.jump.Visible = true
		end
		Feedback.play("StealReady")
	else
		self._highlight.Enabled = false
		self._highlight.Adornee = nil
	end
end

function Controller._hintWeak(self, required: number)
	local now = os.clock()
	if now - (self._lastWeakHint or 0) < 6 then
		return
	end
	self._lastWeakHint = now
	Dispatcher:Publish("CollectorHint", string.format("You need ⚡%s to steal this car — train on the kiddie ride!", tostring(required)))
end

-- === The leap ================================================================

--- Jump pressed: leap at the target, or explain why a car in reach cannot be taken.
function Controller._onJump(self)
	if self._leaping or os.clock() < (self._nextLeapAt or 0) then
		return
	end
	local target = self._target
	if target then
		self:_leap(target)
		return
	end
	local root = self._player.Character and self._player.Character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local t = workspace:GetServerTimeNow()
	for _, rec in self._recs do
		if rec.model and rec.a and rec.b and rec.t0 and rec.t1 and self._powerNow < rec.required then
			local pos = CollectorConfig.positionAt(rec.a, rec.b, rec.t0, rec.t1, t)
			if flat(pos - root.Position) < CollectorConfig.Leap.Range then
				self:_hintWeak(rec.required)
				return
			end
		end
	end
end

--[[ Public: Space in the driver's seat (`LobbyCarController._jumpExit`, which sinks the jump so
	`JumpRequest` never fires). The caller has already asked to leave the seat; this waits for the
	seat to let go, then leaps at whatever was highlighted. No target: nothing, a plain exit. ]]
function Controller.leapFromSeat(self)
	local target = self._target
	local humanoid = self._player.Character and self._player.Character:FindFirstChildOfClass("Humanoid")
	if not (target and humanoid) or self._leaping then
		return
	end
	task.spawn(function()
		local deadline = os.clock() + 0.5
		while humanoid.SeatPart and os.clock() < deadline do
			RunService.Heartbeat:Wait()
		end
		if target.inst.Parent then
			self:_leap(target)
		end
	end)
end

function Controller._leap(self, rec: Rec)
	local character = self._player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") and not humanoid.SeatPart) then
		return
	end
	local a, b, t0, t1 = rec.a :: Vector3, rec.b :: Vector3, rec.t0 :: number, rec.t1 :: number
	local cfg = CollectorConfig.Leap
	local launchAt = workspace:GetServerTimeNow()
	local start = root.Position

	-- Flight time from the distance to where the car will be; once more with that time, since the car
	-- moves while you fly. Two passes is within a stud at highway speeds.
	local duration = math.clamp(flat(CollectorConfig.positionAt(a, b, t0, t1, launchAt) - start) / cfg.Speed, cfg.Time[1], cfg.Time[2])
	local land = CollectorConfig.positionAt(a, b, t0, t1, launchAt + duration)
	duration = math.clamp(flat(land - start) / cfg.Speed, cfg.Time[1], cfg.Time[2])
	land = CollectorConfig.positionAt(a, b, t0, t1, launchAt + duration)
	if launchAt + duration + 0.1 > t1 then
		return
	end

	local id = rec.inst.Name
	self._leaping = rec
	self._pending[id] = true
	self:_setTarget(nil)

	-- Feet on the roof: the root rides its own half height plus the hip height above what it stands on.
	local standOff = humanoid.HipHeight + root.Size.Y / 2
	local function roofAt(t: number): Vector3
		local pos = CollectorConfig.positionAt(a, b, t0, t1, t)
		return Vector3.new(pos.X, floorY() + rec.height + standOff, pos.Z)
	end
	local finish = roofAt(launchAt + duration)
	local across = flat(finish - start)
	local peak = cfg.Height[1] + (cfg.Height[2] - cfg.Height[1]) * math.clamp(across / cfg.Range, 0, 1)
	local heading = Vector3.new(finish.X - start.X, 0, finish.Z - start.Z)
	heading = if heading.Magnitude > 0.1 then heading.Unit else Vector3.new(0, 0, -1)

	humanoid.Jump = false
	humanoid.PlatformStand = true
	local camera = workspace.CurrentCamera
	local fov = self._fov or camera.FieldOfView
	self._fov = fov
	TweenService:Create(camera, TweenInfo.new(duration * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = fov + cfg.Fov,
	}):Play()

	local began = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if not root.Parent or humanoid.Health <= 0 then
			connection:Disconnect()
			self:_release(rec, humanoid, root, fov)
			return
		end
		local s = math.clamp((os.clock() - began) / duration, 0, 1)
		local p = start:Lerp(finish, s) + Vector3.new(0, peak * 4 * s * (1 - s), 0)
		-- One forward flip over the flight, eased so it whips through the middle and settles upright.
		local spin = s * s * (3 - 2 * s) * math.pi * 2
		root.CFrame = CFrame.lookAt(p, p + heading) * CFrame.Angles(-spin, 0, 0)
		root.AssemblyLinearVelocity = Vector3.zero
		if s >= 1 then
			connection:Disconnect()
			self:_landed(rec, humanoid, root, roofAt, fov)
		end
	end)
end

--- On the roof: ask the server, ride the car until it answers (or `Leap.Ride` runs out).
function Controller._landed(self, rec: Rec, humanoid: Humanoid, root: BasePart, roofAt: (number) -> Vector3, fov: number)
	rec.dipAt = os.clock()
	self:getRemoteEvent(Remotes.Capture):Fire(rec.inst.Name)
	self:_shake(0.25, 0.6)

	local facing = Vector3.new(0, 0, -1)
	if rec.a and rec.b and (rec.b - rec.a).Magnitude > 0.5 then
		facing = (rec.b - rec.a).Unit
	end
	local until_ = os.clock() + CollectorConfig.Leap.Ride
	self._riding = rec
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if self._riding ~= rec or os.clock() >= until_ or not root.Parent then
			connection:Disconnect()
			if self._riding == rec then
				self:_release(rec, humanoid, root, fov)
			end
			return
		end
		local p = roofAt(workspace:GetServerTimeNow())
		root.CFrame = CFrame.lookAt(p, p + facing)
		root.AssemblyLinearVelocity = Vector3.zero
	end)
end

--- Let go: stand the character back up, hop it off the roof, restore the camera.
function Controller._release(self, rec: Rec, humanoid: Humanoid, root: BasePart, fov: number, stay: boolean?)
	if self._riding == rec then
		self._riding = nil
	end
	if self._leaping == rec then
		self._leaping = nil
	end
	self._nextLeapAt = os.clock() + 0.25
	local id = rec.inst.Name
	task.delay(1.5, function()
		self._pending[id] = nil
	end)
	if humanoid.Parent then
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	if root.Parent and not stay then
		root.AssemblyLinearVelocity = Vector3.new(0, 22, 0)
	end
	local camera = workspace.CurrentCamera
	self._fov = nil
	TweenService:Create(camera, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = fov,
	}):Play()
end

--- A short camera shake through the humanoid's offset (the default camera keeps its own control).
function Controller._shake(self, seconds: number, size: number)
	local humanoid = self._player.Character and self._player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local stop = os.clock() + seconds
	task.spawn(function()
		while os.clock() < stop and humanoid.Parent do
			local k = (stop - os.clock()) / seconds
			humanoid.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * size * 2 * k
			RunService.RenderStepped:Wait()
		end
		humanoid.CameraOffset = Vector3.zero
	end)
end

-- === Results =================================================================

function Controller._onResult(self, result: { [string]: any })
	if type(result) ~= "table" then
		return
	end
	-- Whatever the answer, the car you are standing on is done with you.
	local riding = self._riding
	if riding and riding.inst.Name == result.id then
		local character = self._player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and root:IsA("BasePart") then
			-- Taken: stay on the roof, the server is about to seat you in it.
			self:_release(riding, humanoid, root, self._fov or workspace.CurrentCamera.FieldOfView, result.ok == true)
		end
	end
	if not result.ok then
		if result.reason == "weak" then
			self:_hintWeak(result.required or 0)
		end
		return
	end
	Feedback.play("RampCaptured")
	Dispatcher:Publish("CollectorCaptured", result)
end

--- The stolen car leaves: sparkles, a ring on the road, and the shell shrinks away into them.
function Controller._poof(self, rec: Rec)
	local model = rec.model
	if self._target == rec then
		self:_setTarget(nil)
	end
	if rec.label then
		rec.label:Destroy()
		rec.label = nil
	end
	if not model then
		return
	end
	rec.model = nil
	self:_burst(model:GetPivot().Position)
	task.spawn(function()
		local began = os.clock()
		while os.clock() - began < 0.28 and model.Parent do
			local k = (os.clock() - began) / 0.28
			model:ScaleTo(math.max(0.05, 1 + 0.25 * math.sin(k * math.pi) - k))
			RunService.RenderStepped:Wait()
		end
		model:Destroy()
	end)
end

function Controller._burst(self, position: Vector3)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Position = position + Vector3.new(0, 3, 0)
	part.Parent = self._world
	-- Built-in textures only: no uploaded asset to go missing.
	for _, spec in {
		{ texture = "rbxasset://textures/particles/sparkles_main.dds", color = Color3.fromRGB(255, 90, 150), count = 22 },
		{ texture = "rbxasset://textures/particles/sparkles_main.dds", color = Color3.fromRGB(255, 230, 120), count = 36 },
	} do
		local e = Instance.new("ParticleEmitter")
		e.Texture = spec.texture
		e.Color = ColorSequence.new(spec.color)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.8), NumberSequenceKeypoint.new(1, 0.4) })
		e.Lifetime = NumberRange.new(0.7, 1.2)
		e.Speed = NumberRange.new(16, 30)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0, -12, 0)
		e.Rate = 0
		e.Parent = part
		e:Emit(spec.count)
	end
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = GREEN
	ring.Size = Vector3.new(0.3, 4, 4)
	ring.CFrame = CFrame.new(position.X, CollectorConfig.Corridor.FloorY + 0.5, position.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = self._world
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, 34, 34),
		Transparency = 1,
	}):Play()
	task.delay(1.5, function()
		part:Destroy()
		ring:Destroy()
	end)
end

-- === Zone barriers ===========================================================

function Controller._refreshBarriers(self)
	local c = CollectorConfig.Corridor
	for zone = 2, #CollectorConfig.Zones do
		local locked = self._powerNow < CollectorConfig.zoneMinimum(zone)
		local wall = self._barriers[zone]
		if locked and not wall then
			wall = Instance.new("Part")
			wall.Name = "ZoneBarrier" .. zone
			wall.Anchored = true
			wall.CanQuery = false
			wall.CanTouch = false
			wall.Material = Enum.Material.ForceField
			wall.Color = RED
			wall.Size = Vector3.new(c.HalfWidth * 2 + 80, 40, 2)
			wall.CFrame = CFrame.new(c.CenterX, c.FloorY + 20, c.StartZ - (zone - 1) * c.ZoneLength)
			wall.Parent = self._world
			self._barriers[zone] = wall
		elseif not locked and wall then
			wall:Destroy()
			self._barriers[zone] = nil
		end
	end
end

function Controller._onPowerChanged(self)
	local power = self:_power()
	if power == self._powerNow then
		return
	end
	self._powerNow = power
	for _, rec in self._recs do
		self:_paintNeed(rec)
	end
	self:_refreshBarriers()
end

-- === Lifecycle ===============================================================

--- Cache the leg off the attributes when they change, so the frame loop reads table fields
--- instead of six `GetAttribute` calls per car per frame.
function Controller._track(self, inst: Instance)
	if not inst:IsA("Configuration") or self._recs[inst] then
		return
	end
	local rec = { inst = inst, model = nil, lift = 0, height = 4, yaw = 0 } :: any
	local function read()
		rec.a, rec.b = inst:GetAttribute("A"), inst:GetAttribute("B")
		rec.t0, rec.t1 = inst:GetAttribute("T0"), inst:GetAttribute("T1")
		rec.required = inst:GetAttribute("Required") or math.huge
	end
	read()
	inst.AttributeChanged:Connect(read)
	self._recs[inst] = rec
end

Controller:withLifecycle({
	init = function(self)
		self._player = Players.LocalPlayer
		self._recs = {} :: { [Instance]: Rec }
		self._pending = {} :: { [string]: boolean }
		self._barriers = {} :: { [number]: BasePart }
		self._found = {}
		self._powerNow = -1
	end,

	start = function(self)
		-- Road mode: no highway to draw, but `_onResult` (the Captured remote) still runs, and it is
		-- what turns a race steal into the toast.
		if not (CollectorConfig.Enabled and CollectorConfig.Roaming) then
			return
		end
		local world = Instance.new("Folder")
		world.Name = "RoamingCarsLocal"
		world.Parent = workspace
		self._world = world
		-- Billboards live in PlayerGui (not on the shells) so a respawn or a shell rebuild never
		-- flickers them, and InterfaceController's hide-all covers them.
		local labels = Instance.new("Folder")
		labels.Name = "RoamingCarLabels"
		labels.Parent = self._player:WaitForChild("PlayerGui")
		self._labels = labels

		local highlight = Instance.new("Highlight")
		highlight.Name = "LeapTarget"
		highlight.FillColor = GREEN
		highlight.FillTransparency = 0.7
		highlight.OutlineColor = Color3.fromRGB(200, 255, 170)
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Enabled = false
		highlight.Parent = world
		self._highlight = highlight

		local function refreshFound()
			self._found = CarCatalogue.parseFound(self._player:GetAttribute(CarCatalogue.FoundAttribute))
		end
		refreshFound()
		self._player:GetAttributeChangedSignal(CarCatalogue.FoundAttribute):Connect(refreshFound)
		self._player:GetAttributeChangedSignal(CollectorConfig.Power.Attribute):Connect(function()
			self:_onPowerChanged()
		end)
		self:_onPowerChanged()

		local folder = ReplicatedStorage:WaitForChild(CollectorConfig.FolderName)
		for _, inst in folder:GetChildren() do
			self:_track(inst)
		end
		folder.ChildAdded:Connect(function(inst)
			self:_track(inst)
		end)
		folder.ChildRemoved:Connect(function(inst)
			local rec = self._recs[inst]
			if not rec then
				return
			end
			self._recs[inst] = nil
			-- The car you just landed on goes out with a burst; any other one just goes.
			if self._pending[inst.Name] then
				self:_poof(rec)
			else
				self:_drop(rec)
			end
		end)

		UserInputService.JumpRequest:Connect(function()
			self:_onJump()
		end)
		RunService.RenderStepped:Connect(function()
			self:_step()
		end)
	end,
})

return Controller
