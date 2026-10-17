--[[
	CarAura  (shared, client-side in practice)
	------------------------------------------
	The glow round a rare traffic car, in its rarity colour, so "there's a good one" reads from far
	down the road and not only once its plate is legible (punch list V1, 2026-10-13). What it looks
	like per band is `TrafficConfig.RareAura`; this file only builds it and switches it.

	THREE PIECES, ALL HUNG OFF THE SHELL'S `Hit` HULL, a car-sized box:

	  1. `RareAuraGlow`, a handful of big soft particles locked to the car and pushed BEHIND it with a
	     negative `ZOffset`. The body draws over the middle of each one, so what is left is a coloured
	     rim round the silhouette: a glow, from any angle, for a few particles a car.
	  2. `RareAuraMotes`, small dots rising off the car. Not locked, so at speed they stay where they
	     were let go and draw a short coloured trail behind it, which is the part that reads from a
	     distance on a busy road.
	  3. `RareAuraLight`, an optional PointLight, so the top band also lights the tarmac round it.

	WHY NOT A HIGHLIGHT, which is the obvious glow. Roblox draws about 31 of them a frame and the weather
	mutations already spend one per mutated car (`CarMutation`), on the same Model; a second one per car
	would fight it for the same slot and starve the budget on a busy road. Particles have no budget.

	WHY LightEmission IS NOT 1. Fully additive pale colour vanishes over a bright sky and white lane
	paint (see the wind effect's note), so the glow is partly additive and partly painted.

	POOLED WITH THE SHELL. The pieces are made the first time a shell needs them and only switched after
	that, so a shell that comes back out of the pool as a common costs nothing but three disabled
	instances. `apply(model, nil)` is the release path.

	HOUSE RULE: no wiki-style double-bracket links in this comment — the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)

local CarAura = {}

local GLOW = "RareAuraGlow"
local MOTES = "RareAuraMotes"
local LIGHT = "RareAuraLight"

--- The band's look: the entry for the highest band at or below it, or nil below the first one. So a
--- band added past the top of the table keeps the top band's look rather than losing its aura.
local function lookFor(band: number)
	local best, bestKey = nil, -math.huge
	for key, look in TrafficConfig.RareAura.Bands do
		if key <= band and key > bestKey then
			best, bestKey = look, key
		end
	end
	return best
end

local function fade(from: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, from),
		NumberSequenceKeypoint.new(0.7, from),
		NumberSequenceKeypoint.new(1, 1),
	})
end

--[[ Every property written on every apply, not only when the piece is made, so a look tuned in the
	config (or from a running client, by mutating the required table) lands on shells that already
	exist. Cheap: this runs once per spawn, never per frame. ]]
local function dressGlow(emitter: ParticleEmitter, shared, look, colour: Color3)
	emitter.Texture = shared.Texture
	emitter.Color = ColorSequence.new(colour)
	emitter.LightEmission = shared.LightEmission
	emitter.LightInfluence = 0
	emitter.LockedToPart = true
	emitter.Orientation = Enum.ParticleOrientation.FacingCamera
	emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.None
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Speed = NumberRange.new(0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-20, 20)
	emitter.Lifetime = NumberRange.new(shared.Lifetime[1], shared.Lifetime[2])
	emitter.ZOffset = shared.ZOffset
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, look.Size * 0.85),
		NumberSequenceKeypoint.new(1, look.Size),
	})
	emitter.Transparency = fade(look.Transparency)
	emitter.Rate = look.Rate
end

local function dressMotes(emitter: ParticleEmitter, shared, look, colour: Color3)
	emitter.Texture = shared.Texture
	emitter.Color = ColorSequence.new(colour)
	emitter.LightEmission = shared.LightEmission
	emitter.LightInfluence = 0
	emitter.LockedToPart = false
	emitter.Orientation = Enum.ParticleOrientation.FacingCamera
	emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.None
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Speed = NumberRange.new(shared.Speed[1], shared.Speed[2])
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.Acceleration = Vector3.new(0, shared.Rise, 0)
	emitter.Drag = 0
	emitter.Lifetime = NumberRange.new(shared.Lifetime[1], shared.Lifetime[2])
	emitter.ZOffset = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, look.Size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(look.Transparency)
	emitter.Rate = look.Rate
end

local function child(host: BasePart, name: string, class: string): Instance
	local found = host:FindFirstChild(name)
	if found and found:IsA(class) then
		return found
	end
	local made = Instance.new(class)
	made.Name = name
	made.Parent = host
	return made
end

local function switchOff(host: BasePart)
	for _, name in { GLOW, MOTES } do
		local emitter = host:FindFirstChild(name)
		if emitter then
			(emitter :: ParticleEmitter).Enabled = false
			;(emitter :: ParticleEmitter):Clear()
		end
	end
	local light = host:FindFirstChild(LIGHT)
	if light then
		(light :: PointLight).Enabled = false
	end
end

--[[ The aura on or off for this shell: on, in its band's colour and its band's strength, when `body`
	is rare enough (`TrafficConfig.RareAura.Bands`); off for nil or anything below. ]]
function CarAura.apply(model: Model, body: string?)
	local host = model:FindFirstChild("Hit")
	if not (host and host:IsA("BasePart")) then
		return
	end
	local cfg = TrafficConfig.RareAura
	local _, band = CarRarity.of(body)
	local look = if cfg.Enabled and body ~= nil then lookFor(band) else nil
	if not look then
		switchOff(host)
		return
	end
	local colour = CarRarity.colourOf(band)

	local glow = child(host, GLOW, "ParticleEmitter") :: ParticleEmitter
	dressGlow(glow, cfg.Glow, look.Glow, colour)
	glow.Enabled = true

	local motes = child(host, MOTES, "ParticleEmitter") :: ParticleEmitter
	dressMotes(motes, cfg.Motes, look.Motes, colour)
	motes.Enabled = true

	local existing = host:FindFirstChild(LIGHT)
	if look.Light then
		local light = child(host, LIGHT, "PointLight") :: PointLight
		light.Color = colour
		light.Range = look.Light.Range
		light.Brightness = look.Light.Brightness
		light.Shadows = false
		light.Enabled = true
	elseif existing then
		(existing :: PointLight).Enabled = false
	end
end

return CarAura
