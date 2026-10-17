--[[
	FirstPersonWheel  (client)
	--------------------------
	The car's OWN steering wheel while `RaceCameraController` has the first-person shot: turned with
	the steer when the cockpit overlay is off, hidden when the overlay draws a wheel of its own, left
	alone otherwise. This file is the only writer of the real wheel's `LocalTransparencyModifier`, so
	the overlay can be switched on and off mid-shot without two owners fighting over one part.

	=== WHY IT TURNS A CLONE ====================================================================

	The real `steering_wheel` is welded into the car's assembly, and writing a welded part's CFrame
	moves the whole assembly with it. Rewriting its weld every frame is no better: that is a joint in
	the car this client is simulating. So the real part is hidden for this client and an anchored
	clone with no joints is put exactly where it is every render frame, turned about the wheel's own
	column. It is read off the real part in the same render step the camera is, so the two can never
	be a frame apart.

	The column and the hub come from `CockpitConfig.CarWheel`, measured off the meshes; that file says
	how. The sign is settled here once per car: + is anticlockwise as the driver sees the wheel, which
	is a turn to the left, so the axis is flipped if it happens to point away from the seat.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CockpitConfig = require(ReplicatedStorage.shared.Configs.CockpitConfig)
--- The body name, for this car's `CockpitConfig.Cabin.Nudge.<body>.Wheel`.
local CarStats = require(ReplicatedStorage.shared.Modules.CarStats)

local FirstPersonWheel = {}
FirstPersonWheel.__index = FirstPersonWheel

--- "turn" shows the clone turning in place of the real wheel, "hide" shows neither (the overlay draws
--- one), "show" leaves the real wheel as it is.
export type Mode = "turn" | "hide" | "show"

--- Children a clone keeps: the ones that are how it looks. Joints, welds and scripts all go.
local VISUAL_CHILDREN = { "SurfaceAppearance", "Decal" }

local function approach(current: number, target: number, dt: number, gain: number): number
	if gain <= 0 then
		return target
	end
	return current + (target - current) * (1 - math.exp(-dt * gain))
end

local function isVisual(inst: Instance): boolean
	for _, class in VISUAL_CHILDREN do
		if inst:IsA(class) then
			return true
		end
	end
	return false
end

--- Public: the car's own steering wheel, or nil on the four rigs that have none. The same name rule
--- `CarPaint` vetoes on, so anything called a steering part is one.
function FirstPersonWheel.find(car: Model?): BasePart?
	local body = car and car:FindFirstChild("Body")
	if not body then
		return nil
	end
	for _, inst in body:GetDescendants() do
		if inst:IsA("BasePart") and string.find(string.lower(inst.Name), "steering", 1, true) then
			return inst
		end
	end
	return nil
end

--- Public: the top of the wheel's rim in `seat`'s frame, studs. What the eye has to clear to see the
--- road over it.
function FirstPersonWheel.topIn(wheel: BasePart, seat: BasePart): number
	local cf, half = wheel.CFrame, wheel.Size / 2
	local top = -math.huge
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				local corner = cf:PointToWorldSpace(Vector3.new(x * half.X, y * half.Y, z * half.Z))
				top = math.max(top, seat.CFrame:PointToObjectSpace(corner).Y)
			end
		end
	end
	return top
end

--- The column, the hub and the rim's radius for this mesh, in the part's own space (the hub and the
--- radius already scaled by `Size`).
local function fitFor(part: BasePart): (Vector3, Vector3, number)
	local W = CockpitConfig.CarWheel
	local id = if part:IsA("MeshPart") then string.match(part.MeshId, "%d+") else nil
	local fit = id and W.ByMesh[id]
	local axis = (fit and fit.Axis) or W.Axis
	local centre = (fit and fit.Centre) or W.Centre
	local radius = (fit and fit.Radius) or W.Radius
	local size = part.Size
	return axis.Unit, centre * size, radius * math.max(size.X, size.Y, size.Z)
end

--- Public: the wheel of `car`, ready to turn, or nil when the car has none to turn.
function FirstPersonWheel.new(car: Model, seat: BasePart)
	local real = FirstPersonWheel.find(car)
	if not real then
		return nil
	end
	local twin = real:Clone()
	if not twin then
		return nil -- not Archivable
	end
	for _, inst in twin:GetDescendants() do
		if not isVisual(inst) then
			inst:Destroy()
		end
	end
	twin.Name = "FirstPersonWheel"
	twin.Anchored = true
	twin.CanCollide = false
	twin.CanQuery = false
	twin.CanTouch = false
	twin.Massless = true
	twin.LocalTransparencyModifier = 1
	twin.CFrame = real.CFrame

	local axis, centre, radius = fitFor(real)
	local pivot = CFrame.new(centre)
	-- Point the column at the driver, so a positive angle is anticlockwise from the seat.
	local hub = real.CFrame:PointToWorldSpace(centre)
	local head = seat.CFrame:PointToWorldSpace(Vector3.new(0, 3, 0))
	if real.CFrame:VectorToWorldSpace(axis):Dot(head - hub) < 0 then
		axis = -axis
	end
	--[[ The rim's own frame in the part's space, for the hands: hub at the origin, +Z the column toward
		the driver, +Y the seat's up laid into the rim's plane, +X the driver's right. The same frame
		`FirstPersonCockpit` builds its drawn wheel in, so its grips mean the same here. A wheel lying
		near flat (the Roadster's) has no "up" in its plane worth the name, so the seat's forward is. ]]
	local up = real.CFrame:VectorToObjectSpace(seat.CFrame.UpVector)
	local inPlane = up - axis * up:Dot(axis)
	if inPlane.Magnitude < 0.3 then
		local ahead = real.CFrame:VectorToObjectSpace(seat.CFrame.LookVector)
		inPlane = ahead - axis * ahead:Dot(axis)
	end
	inPlane = inPlane.Unit
	local plane = CFrame.fromMatrix(centre, inPlane:Cross(axis), inPlane, axis)

	-- Under the camera: local to this client, out of every folder the game sweeps for car parts.
	twin.Parent = workspace.CurrentCamera

	local self = setmetatable({}, FirstPersonWheel)
	self._real = real
	self._twin = twin
	self._seat = seat
	self._body = CarStats.bodyOf(car)
	self._axis = axis
	self._pivot = pivot
	self._unpivot = pivot:Inverse()
	self._plane = plane
	self._radius = radius
	self._angle = 0
	--- What the real wheel's modifier read before this hid it, or nil while it is not hidden.
	self._realWas = nil :: number?
	return self
end

function FirstPersonWheel._hideReal(self, hidden: boolean)
	local real = self._real
	if hidden and self._realWas == nil then
		self._realWas = real.LocalTransparencyModifier
		real.LocalTransparencyModifier = 1
	elseif not hidden and self._realWas ~= nil then
		real.LocalTransparencyModifier = self._realWas
		self._realWas = nil
	end
end

--- Public, once a render frame. `steer` is the road steer, + = left.
function FirstPersonWheel.update(self, mode: Mode, steer: number, dt: number)
	local real, twin = self._real, self._twin
	if not real.Parent then
		twin.LocalTransparencyModifier = 1
		return
	end
	self:_hideReal(mode ~= "show")

	-- Only a turning wheel is turned: a wheel left still is still for the hands holding it, too.
	local W = CockpitConfig.CarWheel
	local want = if mode == "turn" then math.rad(W.MaxDeg) * math.clamp(steer, -1, 1) else 0
	self._angle = approach(self._angle, want, dt, W.Gain)
	if mode ~= "turn" then
		twin.LocalTransparencyModifier = 1
		return
	end
	twin.LocalTransparencyModifier = 0
	-- The race's fades write the real wheel's Transparency; the clone wears whatever it says.
	if twin.Transparency ~= real.Transparency then
		twin.Transparency = real.Transparency
	end
	twin.CFrame = self:_shift() * real.CFrame * self._pivot * CFrame.fromAxisAngle(self._axis, self._angle) * self._unpivot
end

--[[ This car's hand correction (`CockpitConfig.Cabin.Nudge.<body>.Wheel`, seat-frame studs) as a
	world translation, read every frame so it tunes live. Applied to the turning clone and to the
	hands' rim alike, so they never part. Identity for a car with none. ]]
function FirstPersonWheel._shift(self): CFrame
	local nudges = CockpitConfig.Cabin.Nudge
	local row = nudges and self._body and nudges[self._body]
	local offset = row and row.Wheel
	if not (offset and self._seat.Parent) then
		return CFrame.identity
	end
	return CFrame.new(self._seat.CFrame:VectorToWorldSpace(offset))
end

--[[ Public: the wheel for the hands to hold, as `FirstPersonCockpit.Hold`: the rim at rest in the
	frame `eye` (the cockpit's eye frame), its radius and the angle it is turned to. Read after this
	frame's `update`, so the hands and the rim agree on the angle. ]]
function FirstPersonWheel.hold(self, eye: CFrame): { frame: CFrame, radius: number, angle: number }
	return {
		frame = eye:ToObjectSpace(self:_shift() * self._real.CFrame * self._plane),
		radius = self._radius,
		angle = self._angle,
	}
end

--- Public: put the real wheel back and drop the clone.
function FirstPersonWheel.destroy(self)
	if self._real.Parent then
		self:_hideReal(false)
	end
	self._twin:Destroy()
end

return FirstPersonWheel
