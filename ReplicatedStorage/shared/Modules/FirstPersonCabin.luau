--[[
	FirstPersonCabin  (client)
	--------------------------
	The black cabin while `RaceCameraController` has the first-person shot and
	`CameraConfig.FirstPerson.Cabin` is on: the car's insides redrawn in one dark colour with no door
	mirrors and no rear-view mirror. `CockpitConfig.Cabin` is the look and says why; this file only
	puts it there and takes it away again.

	=== HOW ======================================================================================

	A baked car (`Configs/CabinSkinConfig`, 49 of the 50 on the ladders) gets ONE MeshPart, the skin,
	which is every opaque part of its body merged, mirrors cut out and every triangle facing the
	driver's eye. It is loaded once per mesh with `AssetService:CreateMeshPartAsync` and cloned from
	then on. While the
	lens is in the seat the car's own parts are hidden for this client (`LocalTransparencyModifier`,
	the same tool and the same reasons `RaceCameraController._fpHide` gives), so the skin is all there
	is to see of the car's opaque body, and what was cut from the skin is simply gone.

	The skin is drawn `Scale` of the way from the eye to where the shell is: scaled ABOUT THE EYE, so
	from the eye it covers exactly what the shell covers (same angles, nearer). That is what lets it
	ride along inside the car through the blend in and out without the two fighting for the same
	pixels. The car's parts are only hidden once the blend is past `HideAtBlend`, so from the chase
	camera the car is always itself, and the skin is a dark interior through its glass.

	A car with no bake (a new rig, a legacy body) gets the fallback: its own opaque parts cloned in
	the cabin colour, scaled the same way, with the originals left showing. The painted insides go
	dark; the mirrors stay, dark.

	It is placed every render frame off the live seat, in the same render step as the camera, like
	`FirstPersonWheel`'s clone and for the same reason: a frame apart, the shell would peek out from
	behind it at every edge.

	OWNERSHIP. This file is the only writer of `LocalTransparencyModifier` on the car's body parts
	other than the steering wheel (`FirstPersonWheel`'s) and the glass and road wheels (nobody's).

	THE DETAIL (`Modules/FirstPersonCabinDetail`: the mirrors, gauges, a radio screen, vents) is
	built once the skin is in and its own meshes have loaded, and its parts become more pieces here,
	placed by the same loop. `CameraConfig.FirstPerson.CabinDetail` shows and hides it on its own.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CabinSkinConfig = require(ReplicatedStorage.shared.Configs.CabinSkinConfig)
local CarStats = require(ReplicatedStorage.shared.Modules.CarStats)
local CockpitConfig = require(ReplicatedStorage.shared.Configs.CockpitConfig)
local FirstPersonCabinDetail = require(ReplicatedStorage.shared.Modules.FirstPersonCabinDetail)

local FirstPersonCabin = {}
FirstPersonCabin.__index = FirstPersonCabin

--[[ A piece of the drawn cabin: the part, its full size, and where it goes at full size: `rel` in the
	seat's frame for a skin, or wherever `original` is this frame for a fallback clone (read live, so
	a body that settles on the chassis after the first frame is followed). `detail` marks a piece of
	`FirstPersonCabinDetail`'s, which has its own switch. ]]
type Piece = { part: BasePart, size: Vector3, rel: CFrame?, original: BasePart?, detail: boolean?, group: string? }

--- One loaded MeshPart per skin mesh, cloned for each use. False while it loads.
local templates: { [number]: MeshPart | false } = {}
--- Skin meshes that would not load. A car whose skin is here gets the fallback instead.
local failed: { [number]: boolean } = {}

--[[ Does the skin stand in for `part`? The rule `assets/cabins/bake.py` merged by, so what is hidden
	is what the skin replaces: everything opaque on the body but the glass (the windows), the road
	wheels (they turn) and the steering wheel (`FirstPersonWheel` turns its own). ]]
local function stoodInFor(part: Instance): boolean
	if not (part:IsA("MeshPart") or part.ClassName == "Part") or part.Name == "HitBox" then
		return false
	end
	local name = string.lower(part.Name)
	if string.find(name, "^wheel_") or string.find(name, "^rim_") or string.find(name, "^tire") then
		return false
	end
	return not (string.find(name, "steering", 1, true) or string.find(name, "glass", 1, true))
end

local function dress(part: BasePart)
	local look = CockpitConfig.Cabin
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Color = look.Color
	part.Material = look.Material
end

--- Starts loading the skin mesh `id` the first time it is asked for; nil until it has arrived.
local function template(id: number): MeshPart?
	local have = templates[id]
	if have ~= nil then
		return have or nil
	end
	templates[id] = false
	task.spawn(function()
		local ok, part = pcall(function()
			return AssetService:CreateMeshPartAsync(Content.fromUri("rbxassetid://" .. id), {
				CollisionFidelity = Enum.CollisionFidelity.Box,
				RenderFidelity = Enum.RenderFidelity.Precise,
			})
		end)
		if ok and part then
			part.Name = "FirstPersonCabin"
			dress(part)
			templates[id] = part
		else
			failed[id] = true
			warn("[FirstPersonCabin] could not load cabin skin", id, part)
		end
	end)
	return nil
end

--- Seconds one background fetch may take before `warm` moves on to the next (it keeps loading).
local WARM_TIMEOUT = 10
local warming = false

--- Every mesh a body's cabin is drawn from: its skin and its two door mirrors.
local function meshesOf(body: string): { number }
	local ids = {}
	local skin = CabinSkinConfig.Cars[body]
	if skin then
		table.insert(ids, skin.Mesh)
	end
	for _, mirror in CabinSkinConfig.Mirrors[body] or {} do
		table.insert(ids, mirror.Mesh)
	end
	return ids
end

--[[ Public: fetch cabins before they are needed (`CockpitConfig.Cabin.Preload` has why). `car`'s
	own meshes and the shared detail meshes are asked for at once; then, once per session, every
	other cabin is fetched in the background ONE AT A TIME. Safe to call any number of times: a mesh
	already in hand or on its way is not asked for twice (`template`). ]]
function FirstPersonCabin.warm(car: Model?)
	local body = car and CarStats.bodyOf(car)
	if body then
		for _, id in meshesOf(body) do
			template(id)
		end
	end
	for _, mesh in CabinSkinConfig.DetailMeshes do
		template(mesh.Mesh)
	end
	if warming then
		return
	end
	warming = true
	task.spawn(function()
		for name in CabinSkinConfig.Cars do
			for _, id in meshesOf(name) do
				template(id)
				local deadline = os.clock() + WARM_TIMEOUT
				while templates[id] == false and not failed[id] and os.clock() < deadline do
					task.wait(0.05)
				end
			end
		end
	end)
end

--- The detail's view of the loads: the template, and whether it failed.
local function fetch(id: number): (MeshPart?, boolean)
	return template(id), failed[id] == true
end

--- Public: the cabin for `car` while its driver's eye is the lens. Builds nothing visible until the
--- first `update`.
function FirstPersonCabin.new(car: Model, seat: BasePart)
	local self = setmetatable({}, FirstPersonCabin)
	self._car = car
	self._seat = seat
	self._body = nil :: string?
	self._skin = nil :: CabinSkinConfig.Skin?
	self._pieces = {} :: { Piece }
	--- The car's own parts the skin stands in for, the biggest first (it is the fade's reference).
	self._originals = {} :: { BasePart }
	--- What each hidden instance's modifier read before this hid it.
	self._hidden = {} :: { [Instance]: number }
	self._hiding = false
	self._shown = false
	self._shownDetail = false
	self._detail = nil :: any -- Modules/FirstPersonCabinDetail, once the skin and its meshes are in
	self._scale = -1
	self._transparency = -1
	self:_build()
	return self
end

function FirstPersonCabin._build(self)
	local car = self._car
	local body = car:FindFirstChild("Body")
	self._body = CarStats.bodyOf(car)
	local skin = CabinSkinConfig.Cars[self._body]
	self._skin = if skin and not failed[skin.Mesh] then skin else nil
	if not body then
		return
	end
	local originals = {}
	for _, inst in body:GetDescendants() do
		if stoodInFor(inst) then
			table.insert(originals, inst :: BasePart)
		end
	end
	table.sort(originals, function(a, b)
		local sa, sb = a.Size, b.Size
		return sa.X * sa.Y * sa.Z > sb.X * sb.Y * sb.Z
	end)
	self._originals = originals

	if self._skin then
		template(self._skin.Mesh)
	elseif CockpitConfig.Cabin.CloneUnbaked and not CockpitConfig.Cabin.DashWhenUnbaked then
		self:_cloneUnbaked()
	end
end

--[[ Public: does this car have a baked skin that has not failed to load? False is the cue for
	`RaceCameraController` to draw the dash instead (`CockpitConfig.Cabin.DashWhenUnbaked`). True
	while a skin is still loading, so the dash does not flash up for the first frames of a baked car. ]]
function FirstPersonCabin.hasSkin(self): boolean
	return self._skin ~= nil
end

--- The fallback for a car with no bake: its own opaque parts, cloned in the cabin colour.
function FirstPersonCabin._cloneUnbaked(self)
	local camera = workspace.CurrentCamera
	for _, original in self._originals do
		if original.Transparency < 0.5 then
			local part = original:Clone()
			if part then
				for _, child in part:GetChildren() do
					child:Destroy()
				end
				if part:IsA("MeshPart") then
					part.TextureID = ""
				end
				part.Name = "FirstPersonCabin"
				dress(part)
				part.LocalTransparencyModifier = 1
				part.Parent = camera
				table.insert(self._pieces, { part = part, size = original.Size, original = original })
			end
		end
	end
	-- New pieces start hidden; the next `update` shows them.
	self._shown = false
	self._scale = -1
	self._transparency = -1
end

--[[ The skin arrived: put it in the cabin. Turned half round, because Roblox's importer turns a glTF
	to face its own front (glTF's front is +Z, a Roblox part's is -Z) and the bake wrote seat space
	straight in. The sizes come through identical either way, which is why only a look at it shows. ]]
function FirstPersonCabin._mountSkin(self, from: MeshPart)
	local part = from:Clone()
	part.LocalTransparencyModifier = 1
	part.Parent = workspace.CurrentCamera
	local rel = CFrame.new(self._skin.Centre) * CFrame.Angles(0, math.pi, 0)
	table.insert(self._pieces, { part = part, rel = rel, size = from.Size })
	self._shown = false
	self._scale = -1
	self._transparency = -1
end

function FirstPersonCabin._hide(self, hidden: boolean)
	if hidden == self._hiding then
		return
	end
	self._hiding = hidden
	if hidden then
		for _, part in self._originals do
			if part.Parent and self._hidden[part] == nil then
				self._hidden[part] = part.LocalTransparencyModifier
				part.LocalTransparencyModifier = 1
				for _, child in part:GetChildren() do
					if (child:IsA("Decal") or child:IsA("Texture")) and self._hidden[child] == nil then
						self._hidden[child] = child.LocalTransparencyModifier
						child.LocalTransparencyModifier = 1
					end
				end
			end
		end
	else
		for inst, previous in self._hidden do
			if inst.Parent then
				(inst :: any).LocalTransparencyModifier = previous
			end
		end
		table.clear(self._hidden)
	end
end

function FirstPersonCabin._show(self, shown: boolean, detail: boolean)
	detail = shown and detail
	if shown == self._shown and detail == self._shownDetail then
		return
	end
	self._shown = shown
	self._shownDetail = detail
	for _, piece in self._pieces do
		local on = if piece.detail then detail else shown
		piece.part.LocalTransparencyModifier = if on then 0 else 1
	end
	if self._detail then
		self._detail:setVisible(detail)
	end
end

--- The detail arrives: its parts become pieces, hidden until the next `_show`.
function FirstPersonCabin._mountDetail(self)
	local detail = FirstPersonCabinDetail.new(
		CabinSkinConfig.Detail[self._body],
		CabinSkinConfig.Mirrors[self._body],
		self._car,
		fetch,
		workspace.CurrentCamera
	)
	if not detail then
		return -- still loading
	end
	self._detail = detail
	for _, piece in detail.pieces do
		table.insert(self._pieces, { part = piece.part, size = piece.size, rel = piece.rel, detail = true, group = piece.group })
	end
	self._shown = false
	self._shownDetail = false
	self._scale = -1
	self._transparency = -1
end

--[[ Public, once a render frame, after the camera is placed. `eye` is the eye in the seat's frame
	(`RaceCameraController._eyeOffset`), `blend` the first-person blend, `on` the live switch and
	`detail` the detail's. `dt` is the frame, for the gauges. ]]
function FirstPersonCabin.update(self, eye: Vector3, blend: number, on: boolean, detail: boolean, dt: number)
	local seat = self._seat
	if not (seat.Parent and self._car.Parent) then
		self:_hide(false)
		self:_show(false, false)
		return
	end
	if CarStats.bodyOf(self._car) ~= self._body then
		-- Same car, new body (a regraft): what this was built for is gone.
		self:_teardown()
		self:_build()
	end

	local look = CockpitConfig.Cabin
	local skin = self._skin
	if skin and #self._pieces == 0 then
		if failed[skin.Mesh] then
			self._skin = nil
			skin = nil
			if look.CloneUnbaked and not look.DashWhenUnbaked then
				self:_cloneUnbaked()
			end
		else
			local from = template(skin.Mesh)
			if from then
				self:_mountSkin(from)
			end
		end
	end
	-- The detail goes on a car with a skin (the skin is what cut the car's own mirrors out).
	if detail and self._skin and #self._pieces > 0 and not self._detail and CabinSkinConfig.Detail[self._body] then
		self:_mountDetail()
	end

	-- Every triangle of a skin faces the eye it was baked for; far from it, some would face away.
	local fits = true
	if skin then
		fits = math.abs(eye.Y - skin.Eye) <= look.EyeTolerance
			and math.abs(eye.X) <= look.EyeTolerance
			and math.abs(eye.Z) <= look.EyeTolerance
	end
	local active = on and fits and blend > 0 and #self._pieces > 0
	self:_show(active, detail)
	self:_hide(active and skin ~= nil and blend >= look.HideAtBlend)
	if not active then
		return
	end

	local scale = if skin then look.Scale else look.CloneScale
	local pieces = self._pieces
	if scale ~= self._scale then
		self._scale = scale
		for _, piece in pieces do
			piece.part.Size = piece.size * scale
		end
	end
	-- The race's fades write the body's Transparency; the cabin wears what the biggest part wears.
	local reference = self._originals[1]
	local transparency = if reference and reference.Parent then reference.Transparency else 0
	if transparency ~= self._transparency then
		self._transparency = transparency
		for _, piece in pieces do
			piece.part.Transparency = transparency
		end
		if self._detail then
			self._detail:setFaded(transparency > 0.5)
		end
	end

	local seatCF = seat.CFrame
	local eyeAt = seatCF:PointToWorldSpace(eye)
	local parts, frames = table.create(#pieces), table.create(#pieces)
	--- This car's hand corrections (`CockpitConfig.Cabin.Nudge`), read every frame so they tune live.
	local nudges = look.Nudge and look.Nudge[self._body]
	for i, piece in pieces do
		local nudge = nudges and piece.group and nudges[piece.group]
		local rel = if nudge then CFrame.new(nudge) * (piece.rel :: CFrame) else piece.rel
		local at = if piece.original then piece.original.CFrame else seatCF * (rel :: CFrame)
		parts[i] = piece.part
		frames[i] = at.Rotation + (eyeAt + (at.Position - eyeAt) * scale)
	end
	workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	if self._shownDetail and self._detail then
		self._detail:tick(dt)
	end
end

function FirstPersonCabin._teardown(self)
	self:_hide(false)
	for _, piece in self._pieces do
		piece.part:Destroy()
	end
	table.clear(self._pieces)
	table.clear(self._originals)
	if self._detail then
		self._detail:destroy()
		self._detail = nil
	end
	self._shown = false
	self._shownDetail = false
	self._scale = -1
	self._transparency = -1
end

--- Public: give the car its own cabin back and drop the drawn one.
function FirstPersonCabin.destroy(self)
	self:_teardown()
end

return FirstPersonCabin
