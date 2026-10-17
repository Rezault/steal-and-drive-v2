--[[
	StarController  (client)
	------------------------
	The Star pickup's client half (`PickupConfig.Packs.Star`, punch list N2): for a few seconds the
	car runs faster, shimmers, and ploughs through traffic and obstacles instead of being slowed by
	them.

	WHAT IT OWNS, AND WHAT IT ONLY ANSWERS FOR

	  • THE CLOCK. `start` is called by `PickupController._onUsed` when the server has spent a star,
	    and `isActive` is the one question every other file asks. A second star collected mid-star
	    extends the clock rather than restarting it, the same rule the server keeps for `starUntil`.
	  • THE SPEED, through `DriveController.setStar`, a claimant on the speed dial beside boost and
	    nitro and resolved against them by the highest. Re-asserted every frame, because a steal
	    installs a fresh car and resets every claim on the dial, and the star must survive one.
	  • THE LOOK: a hue-cycling Highlight over the car's own paint, glints off the HitBox and a warm
	    light under it, all built onto whatever car the player is in and rebuilt when that changes.

	It does NOT own the immunity. HP is the server's, so `ObstacleService._applyDamage` refuses hits
	on its own deadline. The plough lives where each hit already lands: `TrafficController._onClip`
	for cars and `ObstacleController.applyImpact` for everything else, both of which ask `isActive`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local PickupConfig = require(ReplicatedStorage.shared.Configs.PickupConfig)

local StarController = Shard.new("StarController")

local HITBOX_NAME = "HitBox"
local FX_NAME = "StarFx"

local function rangeOf(value: { number }): NumberRange
	return NumberRange.new(value[1], value[2] or value[1])
end

-- === The look ===============================================================

function StarController._buildFx(self, car: Model)
	local fx = PickupConfig.StarFx
	local pack = PickupConfig.Packs.Star

	--- Parented to the car so it goes wherever the car goes, and adorned explicitly so a Highlight
	--- living inside the Model cannot end up adorning nothing.
	local highlight = Instance.new("Highlight")
	highlight.Name = FX_NAME
	highlight.Adornee = car
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Parent = car

	local built = { car = car, highlight = highlight }

	local hit = car:FindFirstChild(HITBOX_NAME, true)
	if hit and hit:IsA("BasePart") then
		local spec = fx.Sparkles
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = FX_NAME
		emitter.Texture = spec.Texture
		emitter.Rate = spec.Rate
		emitter.Lifetime = rangeOf(spec.Lifetime)
		emitter.Speed = rangeOf(spec.Speed)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, spec.Size[1]),
			NumberSequenceKeypoint.new(0.3, spec.Size[2]),
			NumberSequenceKeypoint.new(1, spec.Size[3]),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.7, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Color = ColorSequence.new(pack.Color)
		emitter.LightEmission = spec.LightEmission
		emitter.LightInfluence = 0
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Rotation = NumberRange.new(-180, 180)
		emitter.RotSpeed = NumberRange.new(-90, 90)
		--- Glints are left on the road behind the car rather than dragged along with it, which is
		--- what makes them read as a trail at speed.
		emitter.VelocityInheritance = 0
		--- On the HitBox itself rather than an Attachment, so the glints are born across the whole
		--- car's volume instead of from one point in its middle.
		emitter.Shape = Enum.ParticleEmitterShape.Box
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		emitter.Parent = hit

		local light = Instance.new("PointLight")
		light.Name = FX_NAME
		light.Color = pack.Color
		light.Brightness = fx.Light.Brightness
		light.Range = fx.Light.Range
		light.Parent = hit

		built.emitter = emitter
		built.light = light
	end

	self._fx = built
end

--- Take the look off the car. `fade` lets the shimmer ease out over `Shimmer.FadeOut` first, which is
--- how a star ENDS; a wreck or a race ending cuts it, because a fade there announces nothing.
function StarController._dropFx(self, fade: boolean)
	local built = self._fx
	self._fx = nil
	if not built then
		return
	end
	if built.emitter then
		built.emitter.Enabled = false
	end
	if built.light then
		built.light.Enabled = false
	end
	local fadeOut = PickupConfig.StarFx.Shimmer.FadeOut
	if not fade or fadeOut <= 0 then
		built.highlight:Destroy()
		if built.emitter then
			built.emitter:Destroy()
		end
		if built.light then
			built.light:Destroy()
		end
		return
	end
	local highlight = built.highlight
	local fill0, line0 = highlight.FillTransparency, highlight.OutlineTransparency
	local t = 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		t += dt
		local k = math.clamp(t / fadeOut, 0, 1)
		if highlight.Parent then
			highlight.FillTransparency = fill0 + (1 - fill0) * k
			highlight.OutlineTransparency = line0 + (1 - line0) * k
		end
		if k >= 1 then
			conn:Disconnect()
			highlight:Destroy()
			-- Held to the end of the fade so the last glints are not cut off mid-life.
			if built.emitter then
				built.emitter:Destroy()
			end
			if built.light then
				built.light:Destroy()
			end
		end
	end)
end

function StarController._paint(self, remaining: number)
	local built = self._fx
	if not built then
		return
	end
	local shimmer = PickupConfig.StarFx.Shimmer
	local ending = remaining <= PickupConfig.Packs.Star.Star.WarnTime
	local elapsed = os.clock() - self._startedAt

	self._hue = (self._hue + (if ending then shimmer.WarnHueSpeed else shimmer.HueSpeed) * self._dt) % 1
	local color = Color3.fromHSV(self._hue, shimmer.Saturation, shimmer.Value)
	local highlight = built.highlight
	highlight.FillColor = color
	highlight.OutlineColor = color

	local fadeIn = if shimmer.FadeIn > 0 then math.clamp(elapsed / shimmer.FadeIn, 0, 1) else 1
	local fill = shimmer.FillTransparency
	if ending and math.floor(elapsed * shimmer.WarnBlinkHz * 2) % 2 == 1 then
		fill = shimmer.WarnFillTransparency
	end
	highlight.FillTransparency = 1 - (1 - fill) * fadeIn
	highlight.OutlineTransparency = 1 - (1 - shimmer.OutlineTransparency) * fadeIn
end

-- === The frame ==============================================================

function StarController._step(self, dt: number)
	self._dt = dt
	local remaining = self._until - os.clock()
	if remaining <= 0 then
		self:_stop(true)
		return
	end

	--- The car first: a steal swaps it mid-star, and both the look and the dial belong on the new one.
	local car = self._road and self._road:getCar() or nil
	if car ~= (self._fx and self._fx.car) then
		self:_dropFx(false)
		if car then
			self:_buildFx(car)
		end
	end

	if self._drive then
		local star = PickupConfig.Packs.Star.Star
		self._drive:setStar(star.SpeedScale, star.Kick)
	end
	self:_paint(remaining)
end

function StarController._stop(self, fade: boolean)
	self._until = 0
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	if self._drive then
		self._drive:setStar(nil)
	end
	self:_dropFx(fade)
end

-- === Public =================================================================

--[[ PUBLIC (PickupController._onUsed) — the server spent a star for this player: light it, or
	extend the one already lit. Refused outside a live race, where there is no car to dress and the
	server has no run to be immune in. ]]
function StarController.start(self)
	if not self._racing then
		return
	end
	local star = PickupConfig.Packs.Star.Star
	local now = os.clock()
	local fresh = self._until <= now
	self._until = math.max(self._until, now + star.Duration)
	if not fresh then
		return
	end
	self._startedAt = now
	self._hue = 0
	self._dt = 0
	if not self._conn then
		self._conn = RunService.Heartbeat:Connect(function(dt)
			self:_step(dt)
		end)
	end
	self:_step(0)
end

--- PUBLIC — is a star lit right now? Asked on every traffic clip and every impact.
function StarController.isActive(self): boolean
	return self._racing and os.clock() < self._until
end

--- PUBLIC — seconds left on the star, 0 when none.
function StarController.remaining(self): number
	return if self:isActive() then self._until - os.clock() else 0
end

StarController:withRemoteEvents({
	{
		RaceStart = function()
			StarController._racing = true
			StarController:_stop(false)
		end,
		--- A star does not survive a wreck, and a revive does not hand one back: the server's
		--- deadline has run out by the time the respawn screen closes anyway.
		RaceWrecked = function()
			StarController._racing = false
			StarController:_stop(false)
		end,
		RaceRevived = function()
			StarController._racing = true
		end,
		RaceEnd = function()
			StarController._racing = false
			StarController:_stop(false)
		end,
	},
})

StarController:withLifecycle({
	init = function(self)
		self._racing = false
		self._until = 0
		self._startedAt = 0
		self._hue = 0
		self._dt = 0
		self._conn = nil
		self._fx = nil
	end,

	start = function(self)
		self._drive = Shard.get("DriveController")
		self._road = Shard.get("RoadController")
	end,
})

return StarController
