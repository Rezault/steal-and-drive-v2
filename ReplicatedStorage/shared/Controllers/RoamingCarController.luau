--[[ RoamingCarController — draws the roaming cars and turns walking into one into stealing it
	==========================================================================================

	EVERYTHING HERE IS PRESENTATION. Which cars exist, where they are going and who gets them is
	`RoamingCarService`'s; this file reads the `Configuration` per car it replicates and draws it:

	  • A SHELL per nearby car, cloned from `ReplicatedStorage.TrafficCars` (the same anchored,
	    physics-free shells the road run used), painted and mutated, posed every frame from the leg
	    attributes with `CollectorConfig.positionAt` — the same function the server checks with.
	    Only cars within `RenderRadius` of the camera have a shell; the rest are just attributes.
	  • A LABEL over each: mutation / SECRET / new! tags, rarity in its colour, the car's name and
	    "Required: ⚡N" in green when you meet it and red when you do not. Sized in studs, so it
	    shrinks with distance like the reference's.
	  • THE STEAL: stand within `Capture.Radius` of a car you can steal and a ring on its label fills
	    over `HoldSeconds`; full, it asks the server. No button, so mobile, desktop and controller
	    play it the same way — walk into the car.
	  • ZONE BARRIERS: a glowing wall across the line of every zone whose cheapest car is beyond
	    your Steal Power, solid for you only. The server re-checks power on every steal anyway, so
	    the wall is a signpost, not the lock.

	The result of a steal is published on `Dispatcher` ("CollectorCaptured") for the HUD's toast. ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local CollectorConfig = require(ReplicatedStorage.shared.Configs.CollectorConfig)
local UpgradeConfig = require(ReplicatedStorage.shared.Configs.UpgradeConfig)
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
	yaw: number,
	label: BillboardGui?,
	ring: Frame?,
	need: TextLabel?,
	dust: ParticleEmitter?,
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
	return CollectorConfig.powerOf(UpgradeConfig.decode(self._player:GetAttribute(UpgradeConfig.Attribute)))
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

	local root = model.PrimaryPart or model:FindFirstChild("Root")
	if root and root:IsA("BasePart") then
		local attachment = Instance.new("Attachment")
		attachment.Position = Vector3.new(0, -rec.lift + 0.5, (inst:GetAttribute("BodyLength") or size.Z) * 0.45)
		attachment.Parent = root
		local dust = Instance.new("ParticleEmitter")
		dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
		dust.Color = ColorSequence.new(Color3.fromRGB(232, 214, 170))
		dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 7) })
		dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		dust.Lifetime = NumberRange.new(0.6, 1.1)
		dust.Speed = NumberRange.new(2, 5)
		dust.SpreadAngle = Vector2.new(30, 30)
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

	-- The steal ring: a bar that fills under the requirement while you hold.
	local back = Instance.new("Frame")
	back.AnchorPoint = Vector2.new(0.5, 0)
	back.Position = UDim2.fromScale(0.5, 0.98)
	back.Size = UDim2.fromScale(0.6, 0.08)
	back.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
	back.Visible = false
	Instance.new("UICorner", back).CornerRadius = UDim.new(1, 0)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = GREEN
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
	fill.Parent = back
	back.Parent = gui
	rec.ring = back

	gui.Parent = self._labels
	self:_paintNeed(rec)
	return gui
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
	if rec.model then
		rec.model:Destroy()
		rec.model = nil
	end
	if rec.label then
		rec.label:Destroy()
		rec.label = nil
	end
	rec.ring, rec.need, rec.dust = nil, nil, nil
end

-- === Frame ===================================================================

function Controller._step(self)
	local t = workspace:GetServerTimeNow()
	local camera = workspace.CurrentCamera
	local focus = camera and camera.Focus.Position or Vector3.zero
	local character = self._player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local me = if root and root:IsA("BasePart") then root.Position else nil
	local floorY = CollectorConfig.Corridor.FloorY + CollectorConfig.Move.Lift
	local capture = CollectorConfig.Capture

	local best: Rec?, bestDistance = nil, capture.Radius
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
			model:PivotTo(CFrame.new(pos.X, floorY + rec.lift, pos.Z) * CFrame.Angles(0, rec.yaw, 0))
			if rec.dust then
				rec.dust.Rate = if moving then 18 else 0
			end
		end
		if me and rec.label and not self._pending[inst.Name] then
			local flat = Vector3.new(pos.X - me.X, 0, pos.Z - me.Z).Magnitude
			local required = rec.required
			if flat < bestDistance and math.abs(pos.Y - me.Y) < 25 and self._powerNow >= required then
				best, bestDistance = rec, flat
			elseif flat < capture.Radius and self._powerNow < required then
				self:_hintWeak(required)
			end
		end
	end
	self:_hold(best)
end

function Controller._hold(self, target: Rec?)
	local dt = os.clock() - (self._lastHoldAt or os.clock())
	self._lastHoldAt = os.clock()
	if self._target and self._target ~= target and self._target.ring then
		self._target.ring.Visible = false
	end
	if target ~= self._target then
		self._target = target
		self._held = 0
		if target then
			Feedback.play("StealReady")
		end
	end
	if not (target and target.ring) then
		return
	end
	self._held += dt
	local share = math.clamp(self._held / CollectorConfig.Capture.HoldSeconds, 0, 1)
	target.ring.Visible = true
	local fill = target.ring:FindFirstChildOfClass("Frame")
	if fill then
		fill.Size = UDim2.fromScale(share, 1)
	end
	if share >= 1 then
		local id = target.inst.Name
		self._pending[id] = true
		task.delay(1.5, function()
			self._pending[id] = nil
		end)
		target.ring.Visible = false
		self._target = nil
		self:getRemoteEvent(Remotes.Capture):Fire(id)
	end
end

function Controller._hintWeak(self, required: number)
	local now = os.clock()
	if now - (self._lastWeakHint or 0) < 6 then
		return
	end
	self._lastWeakHint = now
	Dispatcher:Publish("CollectorHint", string.format("You need ⚡%s to steal this car — upgrade Steal Power!", tostring(required)))
end

-- === Results =================================================================

function Controller._onResult(self, result: { [string]: any })
	if type(result) ~= "table" then
		return
	end
	if not result.ok then
		if result.reason == "weak" then
			self:_hintWeak(result.required or 0)
		end
		return
	end
	-- The server destroys the car's Configuration; burst where the shell stood before it goes.
	for inst, rec in self._recs do
		if inst.Name == result.id and rec.model then
			self:_burst(rec.model:GetPivot().Position)
		end
	end
	Feedback.play("RampCaptured")
	Dispatcher:Publish("CollectorCaptured", result)
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
		{ texture = "rbxasset://textures/particles/sparkles_main.dds", color = Color3.fromRGB(255, 90, 150), count = 18 },
		{ texture = "rbxasset://textures/particles/sparkles_main.dds", color = Color3.fromRGB(255, 230, 120), count = 30 },
	} do
		local e = Instance.new("ParticleEmitter")
		e.Texture = spec.texture
		e.Color = ColorSequence.new(spec.color)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0.4) })
		e.Lifetime = NumberRange.new(0.7, 1.2)
		e.Speed = NumberRange.new(14, 26)
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
	ring.CFrame = CFrame.new(position.X, CollectorConfig.Corridor.FloorY + 0.4, position.Z) * CFrame.Angles(0, 0, math.rad(90))
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
	local rec = { inst = inst, model = nil, lift = 0, yaw = 0 } :: any
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
		self._held = 0
	end,

	start = function(self)
		if not CollectorConfig.Enabled then
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

		local function refreshFound()
			self._found = CarCatalogue.parseFound(self._player:GetAttribute(CarCatalogue.FoundAttribute))
		end
		refreshFound()
		self._player:GetAttributeChangedSignal(CarCatalogue.FoundAttribute):Connect(refreshFound)
		self._player:GetAttributeChangedSignal(UpgradeConfig.Attribute):Connect(function()
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
			if rec then
				self:_drop(rec)
				self._recs[inst] = nil
			end
		end)

		RunService.RenderStepped:Connect(function()
			self:_step()
		end)
	end,
})

return Controller
