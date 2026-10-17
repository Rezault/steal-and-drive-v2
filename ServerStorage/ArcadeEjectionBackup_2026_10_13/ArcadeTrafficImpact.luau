-- Reversible arcade collision trial: traffic stays solid briefly after its first hit.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
local CarCollision = require(script.Parent.CarCollision)
local ArcadeTrafficImpact = {}

function ArcadeTrafficImpact.enabled(): boolean
 local cfg = TrafficConfig.Collision.ArcadeTrial
 return TrafficConfig.Collision.Enabled and cfg ~= nil and cfg.Enabled == true
end

function ArcadeTrafficImpact.begin(rec, primary: BasePart, info, side: number, severity: number, at: Vector3)
 local cfg = TrafficConfig.Collision.ArcadeTrial
 rec.arcadeImpact = true
 rec.impactStarted = os.clock()
 rec.impactUntil = rec.impactStarted + cfg.ContactDuration
 rec.impactStalled = 0
 rec.impactPollAt = rec.impactStarted
 rec.give = 0
 rec.hit.CustomPhysicalProperties = PhysicalProperties.new(cfg.Density, cfg.Friction, cfg.Elasticity)
 CarCollision.setTrafficImpact(rec.hit)
 local delta = rec.hit.Position - primary.Position
 local flat = Vector3.new(delta.X, 0, delta.Z)
 local direction = if flat.Magnitude > 0.001 then flat.Unit else info.cross * -side
 local push = cfg.Push[1] + (cfg.Push[2] - cfg.Push[1]) * severity
 rec.hit:ApplyImpulseAtPosition((direction + Vector3.yAxis * cfg.Lift) * (push * rec.hit.AssemblyMass), at)
 -- A little yaw makes even a low-speed bump read as a knock, rather than a rigid slide.
 local flank = math.abs(direction:Dot(info.cross))
 rec.hit.AssemblyAngularVelocity += Vector3.yAxis * (-side * (cfg.Spin[1] + (cfg.Spin[2] - cfg.Spin[1]) * severity) * math.max(flank, 0.25))
end

local function reach(part: BasePart, axis: Vector3): number
 local half = part.Size * 0.5
 local cf = part.CFrame
 return math.abs(cf.XVector:Dot(axis)) * half.X
  + math.abs(cf.YVector:Dot(axis)) * half.Y
  + math.abs(cf.ZVector:Dot(axis)) * half.Z
end

function ArcadeTrafficImpact.step(rec, primary: BasePart?, hitBox: BasePart?, info, now: number)
 if not rec.impactUntil then return end
 local cfg = TrafficConfig.Collision.ArcadeTrial
 local release = not ArcadeTrafficImpact.enabled() or now >= rec.impactUntil
 if primary and hitBox and info then
  local delta = rec.hit.Position - hitBox.Position
  local touching = math.abs(delta:Dot(info.forward)) <= reach(rec.hit, info.forward) + reach(hitBox, info.forward) + cfg.ReleaseGap
   and math.abs(delta:Dot(info.cross)) <= reach(rec.hit, info.cross) + reach(hitBox, info.cross) + cfg.ReleaseGap
  local elapsed = math.max(now - rec.impactPollAt, 0)
  rec.impactStalled = if touching and math.abs(primary.AssemblyLinearVelocity:Dot(info.forward)) < cfg.StallSpeed
   then rec.impactStalled + elapsed else 0
  if now - rec.impactStarted >= cfg.MinContact then
   release = release or not touching or rec.impactStalled >= cfg.StallTime
  end
 else
  release = true
 end
 rec.impactPollAt = now
 if release then
  CarCollision.setTrafficPhysical(rec.hit, true)
  rec.impactUntil = nil
 end
end

function ArcadeTrafficImpact.kind(severity: number, closing: number?)
 local cfg = TrafficConfig.Collision.ArcadeTrial
 local function blend(band)
  return band[1] + (band[2] - band[1]) * severity
 end
 return { SpeedKeep = blend(cfg.SpeedKeep), SideKick = blend(cfg.SideKick),
  Yaw = blend(cfg.Yaw), Shake = blend(cfg.Shake), ImpactSpeed = closing, Solid = true }
end

function ArcadeTrafficImpact.reset(rec)
 if rec.arcadeImpact then
  local cfg = TrafficConfig.Knock
  rec.hit.CustomPhysicalProperties = PhysicalProperties.new(cfg.Density, cfg.Friction, cfg.Elasticity)
 end
 rec.arcadeImpact, rec.impactStarted, rec.impactUntil = nil, nil, nil
 rec.impactStalled, rec.impactPollAt = nil, nil
end

return ArcadeTrafficImpact
