-- Arcade vehicle balance: speed dials are wheel-speed inputs, not measured road MPH.
-- Variants share rung stats. XP affects speed; saved parts apply small additive bonuses per category.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local RewardConfig = require(ReplicatedStorage.shared.Configs.RewardConfig)
local CustomizeConfig = require(ReplicatedStorage.shared.Configs.CustomizeConfig)
local CarConfig = {}
CarConfig.ChassisAttributes = {
	"MaxSpeed",
	"LaneSpeedScale",
	"LaneAccelScale",
	"ReverseSpeed",
	"DrivingTorque",
	"BrakingTorque",
	"StrutSpringStiffnessFront",
	"StrutSpringDampingFront",
	"StrutSpringStiffnessRear",
	"StrutSpringDampingRear",
	"TorsionSpringStiffness",
	"TorsionSpringDamping",
	"MaxSteer",
	"WheelFriction",
}
CarConfig.EffectsAttributes = {
	"BaseEngineRPM",
	"MaxEngineRPM",
}
CarConfig.Defaults = {
	LaneSpeedScale = 1,
	LaneAccelScale = 1,
	MaxSpeed = 36, 
	MaxSteer = 1, 
	DrivingTorque = 46000, 
	BrakingTorque = 110000, 
	WheelFriction = 1.56, 
	MaxHealth = 100, 
	ReverseSpeed = 20, 
	StrutSpringStiffnessFront = 34000,
	StrutSpringDampingFront = 1430,
	StrutSpringStiffnessRear = 32000,
	StrutSpringDampingRear = 1400,
	TorsionSpringStiffness = 20000, 
	TorsionSpringDamping = 150,
	BaseEngineRPM = 1745,
	MaxEngineRPM = 6500,
}
CarConfig.PartBonuses = { EngineTorque = 0.03, TransmissionSpeed = 0.01, TireBraking = 0.02, TireGrip = 0.01, TireResponse = 0.01 }
CarConfig.Cars = {
	["Civic"] = { MaxSpeed = 36, DrivingTorque = 46000, BrakingTorque = 110000, WheelFriction = 1.677, MaxHealth = 100, LaneSpeedScale = 1.03, LaneAccelScale = 1.04, MaxSteer = 0.978 }, 
	["Golf GTI"] = { MaxSpeed = 38, DrivingTorque = 48000, BrakingTorque = 114000, WheelFriction = 1.716, MaxHealth = 104, LaneSpeedScale = 1.05, LaneAccelScale = 1.07, MaxSteer = 0.99 }, 
	["Camaro"] = { MaxSpeed = 39.5, DrivingTorque = 49000, BrakingTorque = 115000, WheelFriction = 1.521, MaxHealth = 112, LaneSpeedScale = 0.96, LaneAccelScale = 0.94, MaxSteer = 0.936 }, 
	["Charger"] = { MaxSpeed = 41, DrivingTorque = 50000, BrakingTorque = 118000, WheelFriction = 1.521, MaxHealth = 120, LaneSpeedScale = 0.95, LaneAccelScale = 0.93, MaxSteer = 0.93 }, 
	["GNX"] = { MaxSpeed = 38.75, DrivingTorque = 48500, BrakingTorque = 114500, WheelFriction = 1.56, MaxHealth = 108, LaneSpeedScale = 1, LaneAccelScale = 1, MaxSteer = 0.96 }, 
	["Model 3"] = { MaxSpeed = 42.5, DrivingTorque = 55000, BrakingTorque = 124000, WheelFriction = 1.716, MaxHealth = 114, LaneSpeedScale = 1.03, LaneAccelScale = 1.06, MaxSteer = 0.978 }, 
	["Challenger"] = { MaxSpeed = 44, DrivingTorque = 53000, BrakingTorque = 124000, WheelFriction = 1.482, MaxHealth = 130, LaneSpeedScale = 0.94, LaneAccelScale = 0.92, MaxSteer = 0.924 }, 
	["Mustang"] = { MaxSpeed = 46, DrivingTorque = 55000, BrakingTorque = 130000, WheelFriction = 1.599, MaxHealth = 126, LaneSpeedScale = 1, LaneAccelScale = 1, MaxSteer = 0.96 }, 
	-- 2026-10-09: the Maybach took the M5's old row and rung outright; the M5 is the new world 1 top car,
	-- one step up on every stat (speed +2, torque/brakes/grip/HP each a rung's worth).
	["Maybach"] = { MaxSpeed = 48, DrivingTorque = 57000, BrakingTorque = 138000, WheelFriction = 1.716, MaxHealth = 136, LaneSpeedScale = 1.03, LaneAccelScale = 1.04, MaxSteer = 0.978 },
	["M5"] = { MaxSpeed = 50, DrivingTorque = 59000, BrakingTorque = 142000, WheelFriction = 1.755, MaxHealth = 142, LaneSpeedScale = 1.04, LaneAccelScale = 1.05, MaxSteer = 0.984 }, 
	["EVO"] = { MaxSpeed = 39, DrivingTorque = 51000, BrakingTorque = 124000, WheelFriction = 1.755, MaxHealth = 108, LaneSpeedScale = 1.05, LaneAccelScale = 1.08, MaxSteer = 0.99 }, 
	["EVO 10"] = { MaxSpeed = 39, DrivingTorque = 51000, BrakingTorque = 124000, WheelFriction = 1.755, MaxHealth = 108, LaneSpeedScale = 1.05, LaneAccelScale = 1.08, MaxSteer = 0.99 }, 
	["WRX STI"] = { MaxSpeed = 41, DrivingTorque = 53000, BrakingTorque = 127000, WheelFriction = 1.794, MaxHealth = 112, LaneSpeedScale = 1.06, LaneAccelScale = 1.1, MaxSteer = 0.996 }, 
	["F&F EVO"] = { MaxSpeed = 41, DrivingTorque = 53000, BrakingTorque = 127000, WheelFriction = 1.794, MaxHealth = 112, LaneSpeedScale = 1.06, LaneAccelScale = 1.1, MaxSteer = 0.996 }, 
	["RX7"] = { MaxSpeed = 43, DrivingTorque = 51000, BrakingTorque = 128000, WheelFriction = 1.638, MaxHealth = 110, LaneSpeedScale = 1.07, LaneAccelScale = 1.08, MaxSteer = 1.002 }, 
	["350Z"] = { MaxSpeed = 43, DrivingTorque = 51000, BrakingTorque = 128000, WheelFriction = 1.638, MaxHealth = 110, LaneSpeedScale = 1.07, LaneAccelScale = 1.08, MaxSteer = 1.002 }, 
	["RX7 F&F"] = { MaxSpeed = 45, DrivingTorque = 54000, BrakingTorque = 132000, WheelFriction = 1.677, MaxHealth = 115, LaneSpeedScale = 1.07, LaneAccelScale = 1.08, MaxSteer = 1.002 }, 
	["C7"] = { MaxSpeed = 47, DrivingTorque = 57000, BrakingTorque = 140000, WheelFriction = 1.716, MaxHealth = 122, LaneSpeedScale = 1.03, LaneAccelScale = 1.04, MaxSteer = 0.978 }, 
	["MK5 Supra"] = { MaxSpeed = 49, DrivingTorque = 59000, BrakingTorque = 145000, WheelFriction = 1.755, MaxHealth = 128, LaneSpeedScale = 1.06, LaneAccelScale = 1.07, MaxSteer = 0.996 }, 
	["Skyline R34"] = { MaxSpeed = 49, DrivingTorque = 59000, BrakingTorque = 145000, WheelFriction = 1.755, MaxHealth = 128, LaneSpeedScale = 1.06, LaneAccelScale = 1.07, MaxSteer = 0.996 }, 
	["GT"] = { MaxSpeed = 51, DrivingTorque = 61000, BrakingTorque = 150000, WheelFriction = 1.755, MaxHealth = 132, LaneSpeedScale = 1.05, LaneAccelScale = 1.06, MaxSteer = 0.99 }, 
	["Supra MK4"] = { MaxSpeed = 42, DrivingTorque = 54000, BrakingTorque = 130000, WheelFriction = 1.677, MaxHealth = 116, LaneSpeedScale = 1.04, LaneAccelScale = 1.04, MaxSteer = 0.984 }, 
	["SUPRA MK4"] = { MaxSpeed = 42, DrivingTorque = 54000, BrakingTorque = 130000, WheelFriction = 1.677, MaxHealth = 116, LaneSpeedScale = 1.04, LaneAccelScale = 1.04, MaxSteer = 0.984 },
	["BRZ/FRS/GT86"] = { MaxSpeed = 44, DrivingTorque = 52000, BrakingTorque = 132000, WheelFriction = 1.794, MaxHealth = 110, LaneSpeedScale = 1.08, LaneAccelScale = 1.12, MaxSteer = 1.008 }, 
	["S15"] = { MaxSpeed = 46, DrivingTorque = 55000, BrakingTorque = 138000, WheelFriction = 1.716, MaxHealth = 116, LaneSpeedScale = 1.07, LaneAccelScale = 1.1, MaxSteer = 1.002 }, 
	["M4"] = { MaxSpeed = 48, DrivingTorque = 59000, BrakingTorque = 145000, WheelFriction = 1.755, MaxHealth = 128, LaneSpeedScale = 1.05, LaneAccelScale = 1.07, MaxSteer = 0.99 }, 
	["M3 GTR"] = { MaxSpeed = 48, DrivingTorque = 59000, BrakingTorque = 145000, WheelFriction = 1.755, MaxHealth = 128, LaneSpeedScale = 1.05, LaneAccelScale = 1.07, MaxSteer = 0.99 }, 
	["i8"] = { MaxSpeed = 50, DrivingTorque = 61000, BrakingTorque = 150000, WheelFriction = 1.755, MaxHealth = 122, LaneSpeedScale = 1.06, LaneAccelScale = 1.08, MaxSteer = 0.996 }, 
	["M600"] = { MaxSpeed = 52, DrivingTorque = 62000, BrakingTorque = 155000, WheelFriction = 1.677, MaxHealth = 126, LaneSpeedScale = 1.02, LaneAccelScale = 1.03, MaxSteer = 0.972 }, 
	["F40"] = { MaxSpeed = 54, DrivingTorque = 63000, BrakingTorque = 160000, WheelFriction = 1.716, MaxHealth = 130, LaneSpeedScale = 1.04, LaneAccelScale = 1.06, MaxSteer = 0.984 }, 
	["190E"] = { MaxSpeed = 45, DrivingTorque = 55000, BrakingTorque = 138000, WheelFriction = 1.755, MaxHealth = 132, LaneSpeedScale = 1.02, LaneAccelScale = 1.05, MaxSteer = 0.972 }, 
	["Pantera GT5"] = { MaxSpeed = 47, DrivingTorque = 58000, BrakingTorque = 143000, WheelFriction = 1.638, MaxHealth = 130, LaneSpeedScale = 1, LaneAccelScale = 1, MaxSteer = 0.96 }, 
	["C63 AMG"] = { MaxSpeed = 49, DrivingTorque = 62000, BrakingTorque = 150000, WheelFriction = 1.716, MaxHealth = 140, LaneSpeedScale = 1.02, LaneAccelScale = 1.04, MaxSteer = 0.972 }, 
	["F1 LM"] = { MaxSpeed = 51, DrivingTorque = 62000, BrakingTorque = 156000, WheelFriction = 1.794, MaxHealth = 132, LaneSpeedScale = 1.06, LaneAccelScale = 1.1, MaxSteer = 0.996 }, 
	["918"] = { MaxSpeed = 53, DrivingTorque = 65000, BrakingTorque = 162000, WheelFriction = 1.833, MaxHealth = 138, LaneSpeedScale = 1.07, LaneAccelScale = 1.11, MaxSteer = 1.002 }, 
	["Sian"] = { MaxSpeed = 55, DrivingTorque = 65000, BrakingTorque = 168000, WheelFriction = 1.794, MaxHealth = 146, LaneSpeedScale = 1.04, LaneAccelScale = 1.07, MaxSteer = 0.984 }, 
	["F5"] = { MaxSpeed = 57, DrivingTorque = 67000, BrakingTorque = 176000, WheelFriction = 1.755, MaxHealth = 142, LaneSpeedScale = 1.03, LaneAccelScale = 1.05, MaxSteer = 0.978 }, 
	["DeLorean"] = { MaxSpeed = 48, DrivingTorque = 57000, BrakingTorque = 145000, WheelFriction = 1.677, MaxHealth = 140, LaneSpeedScale = 1, LaneAccelScale = 1, MaxSteer = 0.96 }, 
	["Roadster 2.0"] = { MaxSpeed = 50, DrivingTorque = 67000, BrakingTorque = 158000, WheelFriction = 1.794, MaxHealth = 142, LaneSpeedScale = 1.04, LaneAccelScale = 1.08, MaxSteer = 0.984 }, 
	["720S"] = { MaxSpeed = 52, DrivingTorque = 63000, BrakingTorque = 161000, WheelFriction = 1.794, MaxHealth = 138, LaneSpeedScale = 1.06, LaneAccelScale = 1.09, MaxSteer = 0.996 }, 
	["Senna"] = { MaxSpeed = 54, DrivingTorque = 65000, BrakingTorque = 170000, WheelFriction = 1.872, MaxHealth = 136, LaneSpeedScale = 1.08, LaneAccelScale = 1.12, MaxSteer = 1.008 }, 
	["Huyara BC"] = { MaxSpeed = 56, DrivingTorque = 67000, BrakingTorque = 175000, WheelFriction = 1.755, MaxHealth = 144, LaneSpeedScale = 1.04, LaneAccelScale = 1.06, MaxSteer = 0.984 }, 
	["Gemera"] = { MaxSpeed = 58, DrivingTorque = 71000, BrakingTorque = 182000, WheelFriction = 1.794, MaxHealth = 155, LaneSpeedScale = 1.02, LaneAccelScale = 1.05, MaxSteer = 0.972 }, 
	["Jesko Attack"] = { MaxSpeed = 60, DrivingTorque = 70000, BrakingTorque = 190000, WheelFriction = 1.833, MaxHealth = 148, LaneSpeedScale = 1.06, LaneAccelScale = 1.1, MaxSteer = 0.996 }, 
}
function CarConfig.statsFor(body: unknown, level: number?, parts: unknown): { [string]: number }
	local stats = table.clone(CarConfig.Defaults)
	local row = type(body) == "string" and CarConfig.Cars[body]
	if row then
		for key, value in row do
			if key ~= "Traffic" then
				stats[key] = value
			end
		end
	end
	local engine = CustomizeConfig.levelOf(parts, "Engine")
	local transmission = CustomizeConfig.levelOf(parts, "Transmission")
	local tires = CustomizeConfig.levelOf(parts, "Tires")
	local bonus = CarConfig.PartBonuses
	stats.MaxSpeed *= RewardConfig.speedScaleFor(level) * (1 + bonus.TransmissionSpeed * transmission)
	stats.DrivingTorque *= 1 + bonus.EngineTorque * engine
	stats.BrakingTorque *= 1 + bonus.TireBraking * tires
	stats.WheelFriction *= 1 + bonus.TireGrip * tires
	stats.LaneAccelScale *= 1 + bonus.TireResponse * tires
	return stats
end
function CarConfig.maxSpeedOf(body: unknown): number
	local row = type(body) == "string" and CarConfig.Cars[body]
	return (row and row.MaxSpeed) or CarConfig.Defaults.MaxSpeed
end
function CarConfig.maxHealthOf(body: unknown): number
	local row = type(body) == "string" and CarConfig.Cars[body]
	return (row and row.MaxHealth) or CarConfig.Defaults.MaxHealth
end
function CarConfig.trafficOverridesFor(body: unknown): { [string]: any }
	local row = type(body) == "string" and CarConfig.Cars[body]
	return (row and row.Traffic) or {}
end
do
	local known = { MaxHealth = true, Traffic = true }
	for _, name in CarConfig.ChassisAttributes do
		known[name] = true
	end
	for _, name in CarConfig.EffectsAttributes do
		known[name] = true
	end
	local missing = {}
	for body in WorldConfig.TierOfBody do
		if not CarConfig.Cars[body] then
			table.insert(missing, body)
		end
	end
	if #missing > 0 then
		table.sort(missing)
		warn(string.format(
			"[CarConfig] %d car(s) on the ladder have no row and will drive on the defaults: %s",
			#missing,
			table.concat(missing, ", ")
		))
	end
	for body, row in CarConfig.Cars do
		if not WorldConfig.TierOfBody[body] then
			warn(string.format(
				"[CarConfig] '%s' has a row but is on no world's ladder in WorldConfig — it will never spawn.",
				body
			))
		end
		for key in row do
			if not known[key] then
				warn(string.format(
					"[CarConfig] '%s' sets '%s', which nothing reads. Check it against ChassisAttributes.",
					body,
					key
				))
			end
		end
	end
end
return CarConfig