--[[
	TurntableController  (client)
	-----------------------------
	Turns the car on the workshop podium (`CustomizeConfig.Turntable` has the design and why it is
	client-side), and dresses the pad with a light and a few sparkles.

	HOW A CAR IS TURNED WITHOUT FIGHTING THE SERVER. The server places `DisplayCar` once, anchored, and
	never touches it again until it rebuilds it. So the first time this sees a car on a podium it
	records where the server put it (`home`) and from then on poses it every frame as that pose turned
	about the DECK's centre — never accumulating, so a dropped frame or a stall cannot drift it. A new
	model on the podium (a swap, a repaint) is a new `home`, picked up the next frame. The deck is found
	the way `GarageService._platforms` finds it: the higher of the slot's two `Platform` parts.

	Only podiums within `MaxDistance` of the camera move, and the work is one `PivotTo` per car per
	frame — the same call the server made to place it.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local CustomizeConfig = require(ReplicatedStorage.shared.Configs.CustomizeConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)

local TurntableController = Shard.new("TurntableController")

local DRESS_NAME = "TurntableDress"

type Table = {
	slot: Model,
	deck: BasePart?,
	car: Model?,
	home: CFrame?, -- the car's pivot as the server placed it
	centre: Vector3?, -- the turn's axis: the deck's centre, at the car's height
	angle: number,
	dress: Attachment?,
}

--- The deck: the higher of the slot's two `Platform` parts (`GarageService._platforms`).
local function deckOf(slot: Model): BasePart?
	local best, bestTop = nil, -math.huge
	for _, child in slot:GetDescendants() do
		if child:IsA("BasePart") and child.Name == "Platform" then
			local top = child.Position.Y + child.Size.Y / 2
			if top > bestTop then
				best, bestTop = child, top
			end
		end
	end
	return best
end

function TurntableController._watch(self, slot: Instance)
	if not slot:IsA("Model") or self._tables[slot] then
		return
	end
	local index = slot:GetAttribute(GarageConfig.SlotIndexAttribute)
	if type(index) ~= "number" or not CustomizeConfig.Turntable.Bays[index] then
		return
	end
	self._tables[slot] = { slot = slot, deck = nil, car = nil, home = nil, centre = nil, angle = 0, dress = nil }
end

--[[ The pad's light and sparkles, on an attachment at the deck's top centre. Made once per podium,
	kept for its life; `arrive` throws the burst for a car that has just been put on it. ]]
function TurntableController._dress(self, entry: Table, deck: BasePart)
	local cfg = CustomizeConfig.Turntable
	local attachment = deck:FindFirstChild(DRESS_NAME) :: Attachment?
	if not attachment then
		local made = Instance.new("Attachment")
		made.Name = DRESS_NAME
		made.Position = Vector3.new(0, deck.Size.Y / 2 + 0.3, 0)
		made.Parent = deck
		attachment = made
		if cfg.Light.Enabled then
			local light = Instance.new("PointLight")
			light.Color = cfg.Light.Color
			light.Brightness = cfg.Light.Brightness
			light.Range = cfg.Light.Range
			light.Shadows = false
			light.Parent = made
		end
		if cfg.Sparkle.Enabled then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "Sparkle"
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Color = ColorSequence.new(cfg.Sparkle.Color)
			emitter.LightEmission = 1
			emitter.LightInfluence = 0
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.6), NumberSequenceKeypoint.new(1, 0) })
			emitter.Lifetime = NumberRange.new(1.4, 2.4)
			emitter.Speed = NumberRange.new(1.5, 3)
			emitter.SpreadAngle = Vector2.new(70, 70)
			emitter.EmissionDirection = Enum.NormalId.Top
			--[[ ON THE DECK ITSELF, not the attachment: a box-shaped emitter spawns across its parent
				part's volume, and an attachment has none. So they rise from all round the car rather than
				one point at its middle. The deck may be hidden under the new pad; its particles are not. ]]
			emitter.Shape = Enum.ParticleEmitterShape.Box
			emitter.Rate = cfg.Sparkle.Rate
			emitter.Parent = deck
		end
	end
	entry.dress = attachment
end

function TurntableController._step(self, dt: number)
	local cfg = CustomizeConfig.Turntable
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position
	local turn = math.rad(cfg.DegreesPerSecond) * dt

	for slot, entry in self._tables do
		if not slot.Parent then
			self._tables[slot] = nil
			continue
		end
		local deck = entry.deck
		if not (deck and deck.Parent) then
			deck = deckOf(slot)
			entry.deck = deck
			if not deck then
				continue -- not streamed in yet
			end
			self:_dress(entry, deck)
		end
		if eye and (deck.Position - eye).Magnitude > cfg.MaxDistance then
			continue
		end

		local car = slot:FindFirstChild(GarageConfig.Display.CarName)
		if not (car and car:IsA("Model")) then
			entry.car = nil
			continue
		end
		if car ~= entry.car then
			--- A new car on the podium: remember where the server put it, and give it an arrival.
			entry.car = car
			entry.home = car:GetPivot()
			entry.centre = Vector3.new(deck.Position.X, entry.home.Position.Y, deck.Position.Z)
			entry.angle = 0
			local sparkle = deck:FindFirstChild("Sparkle")
			if sparkle and sparkle:IsA("ParticleEmitter") then
				sparkle:Emit(cfg.Sparkle.Arrival)
			end
		end

		entry.angle = (entry.angle + turn) % (math.pi * 2)
		local axis = CFrame.new(entry.centre :: Vector3)
		car:PivotTo(axis * CFrame.Angles(0, entry.angle, 0) * axis:Inverse() * (entry.home :: CFrame))
	end
end

TurntableController:withLifecycle({
	init = function(self)
		self._tables = {} :: { [Model]: Table }
	end,

	start = function(self)
		if not CustomizeConfig.Turntable.Enabled then
			return
		end
		for _, slot in CollectionService:GetTagged(GarageConfig.SlotTag) do
			self:_watch(slot)
		end
		--- Streaming brings plots in and out; a podium that arrives later is picked up then.
		CollectionService:GetInstanceAddedSignal(GarageConfig.SlotTag):Connect(function(slot)
			self:_watch(slot)
		end)
		RunService.Heartbeat:Connect(function(dt)
			self:_step(dt)
		end)
	end,
})

return TurntableController
