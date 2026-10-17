-- Arcade traffic is knocked away from the driver; trapped wrecks fade before being recycled.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
local CarCollision = require(script.Parent.CarCollision)
local ArcadeTrafficImpact = {}

function ArcadeTrafficImpact.enabled(): boolean
	local cfg = TrafficConfig.Collision.ArcadeTrial
	return TrafficConfig.Collision.Enabled and cfg ~= nil and cfg.Enabled == true
end

function ArcadeTrafficImpact.begin(rec, primary: BasePart, info, side: number, severity: number, _at: Vector3)
	local cfg = TrafficConfig.Collision.ArcadeTrial
	local function blend(band) return band[1] + (band[2] - band[1]) * severity end
	rec.arcadeImpact = true
	rec.impactStarted = os.clock()
	rec.impactUntil, rec.impactStalled, rec.impactPollAt = nil, nil, nil
	rec.impactOverlapSince, rec.impactFadeAt = nil, nil
	rec.give = 0
	rec.hit.CustomPhysicalProperties = PhysicalProperties.new(cfg.Density, cfg.Friction, cfg.Elasticity)
	CarCollision.setTrafficPhysical(rec.hit, true)
	-- Never reverse toward the driver to avoid a rail. Use the actual road-relative separation,
	-- because the driver's steering can make its local RightVector disagree with the road.
	local separation = (rec.hit.Position - primary.Position):Dot(info.cross)
	local away = if math.abs(separation) > 0.1 then math.sign(separation) else -side
	rec.impactAway = away
	local playerSpeed = math.max(primary.AssemblyLinearVelocity:Dot(info.forward), 0)
	local carry = math.max(rec.speed, playerSpeed * cfg.ForwardCarry, 0)
	local velocity = info.forward * carry + info.cross * (away * blend(cfg.SideSpeed)) + Vector3.yAxis * blend(cfg.UpSpeed)
	local impulse = (velocity - rec.hit.AssemblyLinearVelocity) * rec.hit.AssemblyMass
	rec.hit:ApplyImpulseAtPosition(impulse, rec.hit.AssemblyCenterOfMass)
	rec.hit.AssemblyAngularVelocity = Vector3.yAxis * (away * blend(cfg.Spin))
end

local function reach(part, axis)
	local cf, half = part.CFrame, part.Size * 0.5
	return math.abs(cf.RightVector:Dot(axis)) * half.X
		+ math.abs(cf.UpVector:Dot(axis)) * half.Y + math.abs(cf.LookVector:Dot(axis)) * half.Z
end

local function overlaps(a, b, info)
	local delta = a.Position - b.Position
	for _, axis in { info.forward, info.cross, Vector3.yAxis } do
		if math.abs(delta:Dot(axis)) > reach(a, axis) + reach(b, axis) + 0.25 then return false end
	end
	return true
end

local function fade(rec, alpha)
	if not rec.impactFadeParts then
		rec.impactFadeParts, rec.impactFadeGuis = {}, {}
		for _, object in rec.model:GetDescendants() do
			if object:IsA("BasePart") then rec.impactFadeParts[object] = object.LocalTransparencyModifier
			elseif object:IsA("BillboardGui") then
				rec.impactFadeGuis[object] = object.Enabled
				object.Enabled = false
			end
		end
		if rec.smoke then rec.smoke.Enabled = false end
	end
	for part, original in rec.impactFadeParts do
		if part.Parent then part.LocalTransparencyModifier = original + (1 - original) * alpha end
	end
end

function ArcadeTrafficImpact.step(rec, primary: BasePart?, hitBox: BasePart?, info, now: number): boolean
	if rec.impactUntil then
		CarCollision.setTrafficPhysical(rec.hit, true)
		rec.impactUntil = nil
	end
	if not rec.arcadeImpact then return false end
	local cfg = TrafficConfig.Collision.ArcadeTrial.ClearContact
	if rec.impactFadeAt then
		local alpha = math.clamp((now - rec.impactFadeAt) / cfg.FadeSeconds, 0, 1)
		fade(rec, alpha)
		return alpha >= 1
	end
	if not (primary and hitBox and primary.Parent and hitBox.Parent and info) then return false end
	if not overlaps(rec.hit, hitBox, info) then
		rec.impactOverlapSince = nil
		return false
	end
	local age = now - (rec.impactStarted or now)
	if age < cfg.AssistSeconds then
		local separation = (rec.hit.Position - hitBox.Position):Dot(info.cross)
		local away = if math.abs(separation) > 0.1 then math.sign(separation) else rec.impactAway
		local velocity = rec.hit.AssemblyLinearVelocity
		local outward = velocity:Dot(info.cross) * away
		if outward < cfg.MinAwaySpeed then
			rec.hit.AssemblyLinearVelocity = velocity + info.cross * (away * (cfg.MinAwaySpeed - outward))
		end
	end
	local relative = rec.hit.AssemblyLinearVelocity - primary.AssemblyLinearVelocity
	local stalled = math.abs(relative:Dot(info.forward)) <= cfg.StallSpeed
	rec.impactOverlapSince = if stalled then rec.impactOverlapSince or now else nil
	if rec.impactOverlapSince and now - rec.impactOverlapSince >= cfg.StuckSeconds then
		rec.impactFadeAt = now
		fade(rec, 0)
	end
	return false
end

function ArcadeTrafficImpact.kind(severity: number, closing: number?)
	local cfg = TrafficConfig.Collision.ArcadeTrial
	local function blend(band) return band[1] + (band[2] - band[1]) * severity end
	return { SpeedKeep=blend(cfg.SpeedKeep), SideKick=blend(cfg.SideKick), Yaw=blend(cfg.Yaw),
		Shake=blend(cfg.Shake), ImpactSpeed=closing, Solid=true }
end

function ArcadeTrafficImpact.reset(rec)
	if rec.arcadeImpact then
		local cfg = TrafficConfig.Knock
		rec.hit.CustomPhysicalProperties = PhysicalProperties.new(cfg.Density, cfg.Friction, cfg.Elasticity)
	end
	for part, original in rec.impactFadeParts or {} do
		if part.Parent then part.LocalTransparencyModifier = original end
	end
	for gui, enabled in rec.impactFadeGuis or {} do
		if gui.Parent then gui.Enabled = enabled end
	end
	rec.impactFadeParts, rec.impactFadeGuis = nil, nil
	rec.arcadeImpact, rec.impactStarted, rec.impactUntil = nil, nil, nil
	rec.impactStalled, rec.impactPollAt, rec.impactAway = nil, nil, nil
	rec.impactOverlapSince, rec.impactFadeAt = nil, nil
end

return ArcadeTrafficImpact