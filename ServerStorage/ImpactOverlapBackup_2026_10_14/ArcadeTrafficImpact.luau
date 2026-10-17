-- Arcade ejection trial: hit traffic skids sideways with low lift, clear of the chase camera.
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
 local function blend(band)
  return band[1] + (band[2] - band[1]) * severity
 end
 rec.arcadeImpact = true
 rec.impactStarted = os.clock()
 rec.impactUntil, rec.impactStalled, rec.impactPollAt = nil, nil, nil
 rec.give = 0
 rec.hit.CustomPhysicalProperties = PhysicalProperties.new(cfg.Density, cfg.Friction, cfg.Elasticity)
 -- Road/debris physics stays on; the driver's collision group is excluded immediately.
 CarCollision.setTrafficPhysical(rec.hit, true)
 local away = -side -- Road cross points left, side=+1 means the other car is on our right.
 local edge = math.max(math.abs(TrafficConfig.Lanes[1]), math.abs(TrafficConfig.Lanes[#TrafficConfig.Lanes]))
 if edge > 0 and math.abs(rec.cross) >= edge * 0.8 then
  away = if rec.cross > 0 then -1 else 1 -- Avoid aiming an outer-lane wreck into the rail.
 end
 -- Keep forward carry while clearing the lane sideways; never launch toward the chase camera.
 local playerSpeed = math.max(primary.AssemblyLinearVelocity:Dot(info.forward), 0)
 local carry = math.max(rec.speed, playerSpeed * cfg.ForwardCarry, 0)
 local velocity = info.forward * carry
  + info.cross * (away * blend(cfg.SideSpeed))
  + Vector3.yAxis * blend(cfg.UpSpeed)
 local impulse = (velocity - rec.hit.AssemblyLinearVelocity) * rec.hit.AssemblyMass
 -- Centre impulse avoids pitching the nose/roof at the camera. Add a readable flat yaw spin.
 rec.hit:ApplyImpulseAtPosition(impulse, rec.hit.AssemblyCenterOfMass)
 rec.hit.AssemblyAngularVelocity = Vector3.yAxis * (away * blend(cfg.Spin))
end

function ArcadeTrafficImpact.step(rec, _primary: BasePart?, _hitBox: BasePart?, _info, _now: number)
 -- Also release records created before a live tuning change.
 if rec.impactUntil then
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
