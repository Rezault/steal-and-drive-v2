-- Keep the vehicle's hull inside the road before the physics solver can hit a rail.
local Edge = { Margin = 1.5, LaneClearance = 2, LookAhead = 0.08, RecoverySpeed = 8 }
function Edge.limit(cf: CFrame, size: Vector3, cross: Vector3, width: number?, laneHalf: number): number
 local half = size * 0.5
 local reach = math.abs(cf.RightVector:Dot(cross))*half.X
  + math.abs(cf.UpVector:Dot(cross))*half.Y
  + math.abs(cf.LookVector:Dot(cross))*half.Z
 local roadHalf = if type(width)=="number" and width>0 then width*0.5 else laneHalf+reach+Edge.Margin
 return math.max(1, math.min(laneHalf-Edge.LaneClearance,roadHalf-reach-Edge.Margin))
end
function Edge.constrain(offset: number, lateral: number, limit: number, dt: number): number
 local horizon = math.max(dt,1/60)+Edge.LookAhead
 -- A displaced car eases inward; steering inward faster is always allowed.
 local upper = math.max(-Edge.RecoverySpeed,(limit-offset)/horizon)
 local lower = math.min(Edge.RecoverySpeed,(-limit-offset)/horizon)
 return math.clamp(lateral,lower,upper)
end
return Edge
