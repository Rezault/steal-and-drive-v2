-- Shadowless event headlights. Traffic uses dimmer, shorter beams on at most three nearby cars.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CarLamps = require(ReplicatedStorage.shared.Modules.CarLamps)

local CarHeadlights = {}
CarHeadlights.TWIN_NAME = "light_eventheadlight"
local COLOR = Color3.fromRGB(255, 246, 217)

function CarHeadlights.build(shell: Instance, root: BasePart, illuminate: boolean?, strength: number?)
	local rig = { twins = {}, emitters = {}, lights = {}, lit = false, beams = false }
	local positions = {}
	for _, lamp in CarLamps.each(shell, root, 0.65) do
		if lamp.rear or lamp.words.red or lamp.words.amber or lamp.words.reverse then
			continue
		end
		if lamp.side == 0 and not (lamp.words.light or lamp.words.lens) then
			continue
		end
		local twin = CarLamps.twin(lamp.part, root.CFrame, {
			Name = CarHeadlights.TWIN_NAME, Color = COLOR, Grow = 0.03, Proud = 0.06,
		}, shell)
		if twin then
			table.insert(rig.twins, twin)
		end
		if lamp.side ~= 0 then
			positions[lamp.side] = lamp.centre
		end
	end
	if illuminate then
		local front = -CarLamps.halfLength(shell, root)
		for _, side in { -1, 1 } do
			local emitter = Instance.new("Attachment")
			emitter.Name = CarHeadlights.TWIN_NAME
			local position = positions[side] or Vector3.new(side * root.Size.X * 0.35, 0, front)
			emitter.CFrame = CFrame.new(position + Vector3.new(0, 0, -0.12)) * CFrame.Angles(math.rad(-5), 0, 0)
			emitter.Parent = root
			local light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Front
			light.Color = COLOR
			light.Range = if strength and strength < 1 then 30 else 60
			light.Angle = 85
			light.Brightness = 3 * (strength or 1)
			light.Shadows = false
			light.Enabled = false
			light.Parent = emitter
			table.insert(rig.emitters, emitter)
			table.insert(rig.lights, light)
		end
	end
	return rig
end

function CarHeadlights.set(rig, lit: boolean, illuminate: boolean?)
	local beams = lit and illuminate ~= false
	if not rig or (rig.lit == lit and rig.beams == beams) then
		return
	end
	if rig.lit ~= lit then
		rig.lit = lit
		for _, twin in rig.twins do
			twin.Transparency = if lit then 0 else 1
		end
	end
	rig.beams = beams
	for _, light in rig.lights do
		light.Enabled = beams
	end
end

function CarHeadlights.nearby(cars, playerAlong: number)
	local closest = {}
	for _, car in cars do
		local distance = math.abs(car.along - playerAlong)
		if distance > 110 then
			continue
		end
		local index = #closest + 1
		for i, other in closest do
			if distance < math.abs(other.along - playerAlong) then
				index = i
				break
			end
		end
		if index <= 3 then
			table.insert(closest, index, car)
			closest[4] = nil
		end
	end
	local selected = {}
	for _, car in closest do
		selected[car] = true
	end
	return selected
end

function CarHeadlights.destroy(rig)
	if not rig then
		return
	end
	for _, twin in rig.twins do
		twin:Destroy()
	end
	for _, emitter in rig.emitters do
		emitter:Destroy()
	end
	table.clear(rig.twins)
	table.clear(rig.emitters)
	table.clear(rig.lights)
	rig.lit = false
	rig.beams = false
end

return CarHeadlights
