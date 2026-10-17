local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CarConfig = require(ReplicatedStorage.shared.Configs.CarConfig)
local CustomizeConfig = require(ReplicatedStorage.shared.Configs.CustomizeConfig)
local CarStats = {}
function CarStats.bodyOf(car: Model): string
 local body=car:GetAttribute("Body")
 return if type(body)=="string" and body~="" then body else car.Name
end
function CarStats.maxHealthOf(car: Model): number
 return CarConfig.maxHealthOf(CarStats.bodyOf(car))
end
local function stamp(car: Model, body: string?, level: number?, parts: unknown, effects: boolean)
 local stats=CarConfig.statsFor(body or car.Name,level,parts)
 for _,name in CarConfig.ChassisAttributes do car:SetAttribute(name,stats[name]) end
 if effects then for _,name in CarConfig.EffectsAttributes do car:SetAttribute(name,stats[name]) end end
 -- Reset fitted parts on every handoff: a newly stolen car does not inherit the previous car's kit.
 for _,key in {"Engine","Transmission","Tires"} do
  car:SetAttribute("Performance"..key.."Level",CustomizeConfig.levelOf(parts,key))
 end
 return stats
end
function CarStats.apply(car: Model, body: string?, level: number?, parts: unknown): { [string]: number }
 return stamp(car,body,level,parts,true)
end
function CarStats.reapply(car: Model, body: string?, level: number?, parts: unknown): { [string]: number }
 return stamp(car,body,level,parts,false)
end
return CarStats