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
-- Rung-based arcade stats. Later-world opening speeds smoothed on 2026-10-09;
-- top speeds and non-speed traits retain the existing tuning.
-- All active bodies have explicit rows; retained owned bodies follow their replacement's stats.
CarConfig.Cars = {
	["918"] = { ["MaxSteer"] = 1.002, ["MaxHealth"] = 138, ["MaxSpeed"] = 55, ["WheelFriction"] = 1.833, ["LaneAccelScale"] = 1.11, ["LaneSpeedScale"] = 1.07, ["DrivingTorque"] = 65000, ["BrakingTorque"] = 162000 },
	["Civic"] = { ["MaxSteer"] = 0.978, ["MaxHealth"] = 100, ["MaxSpeed"] = 36, ["WheelFriction"] = 1.677, ["LaneAccelScale"] = 1.04, ["LaneSpeedScale"] = 1.03, ["DrivingTorque"] = 46000, ["BrakingTorque"] = 110000 },
	["Golf GTI"] = { ["MaxSteer"] = 0.99, ["MaxHealth"] = 104, ["MaxSpeed"] = 38, ["WheelFriction"] = 1.716, ["LaneAccelScale"] = 1.07, ["LaneSpeedScale"] = 1.05, ["DrivingTorque"] = 48000, ["BrakingTorque"] = 114000 },
	["GNX"] = { ["MaxSteer"] = 0.96, ["MaxHealth"] = 108, ["MaxSpeed"] = 38.75, ["WheelFriction"] = 1.56, ["LaneAccelScale"] = 1, ["LaneSpeedScale"] = 1, ["DrivingTorque"] = 48500, ["BrakingTorque"] = 114500 },
	["Camaro"] = { ["MaxSteer"] = 0.936, ["MaxHealth"] = 112, ["MaxSpeed"] = 39.5, ["WheelFriction"] = 1.521, ["LaneAccelScale"] = 0.94, ["LaneSpeedScale"] = 0.96, ["DrivingTorque"] = 49000, ["BrakingTorque"] = 115000 },
	["Charger"] = { ["MaxSteer"] = 0.93, ["MaxHealth"] = 120, ["MaxSpeed"] = 41, ["WheelFriction"] = 1.521, ["LaneAccelScale"] = 0.93, ["LaneSpeedScale"] = 0.95, ["DrivingTorque"] = 50000, ["BrakingTorque"] = 118000 },
	["EVO"] = { ["MaxSteer"] = 0.978, ["MaxHealth"] = 114, ["MaxSpeed"] = 42.5, ["WheelFriction"] = 1.716, ["LaneAccelScale"] = 1.06, ["LaneSpeedScale"] = 1.03, ["DrivingTorque"] = 55000, ["BrakingTorque"] = 124000 },
	["Challenger"] = { ["MaxSteer"] = 0.924, ["MaxHealth"] = 130, ["MaxSpeed"] = 44, ["WheelFriction"] = 1.482, ["LaneAccelScale"] = 0.92, ["LaneSpeedScale"] = 0.94, ["DrivingTorque"] = 53000, ["BrakingTorque"] = 124000 },
	["Mustang"] = { ["MaxSteer"] = 0.96, ["MaxHealth"] = 126, ["MaxSpeed"] = 46, ["WheelFriction"] = 1.599, ["LaneAccelScale"] = 1, ["LaneSpeedScale"] = 1, ["DrivingTorque"] = 55000, ["BrakingTorque"] = 130000 },
	["Maybach"] = { ["MaxSteer"] = 0.978, ["MaxHealth"] = 136, ["MaxSpeed"] = 48, ["WheelFriction"] = 1.716, ["LaneAccelScale"] = 1.04, ["LaneSpeedScale"] = 1.03, ["DrivingTorque"] = 57000, ["BrakingTorque"] = 138000 },
	["M5"] = { ["MaxSteer"] = 0.984, ["MaxHealth"] = 142, ["MaxSpeed"] = 50, ["WheelFriction"] = 1.755, ["LaneAccelScale"] = 1.05, ["LaneSpeedScale"] = 1.04, ["DrivingTorque"] = 59000, ["BrakingTorque"] = 142000 },
	["EVO 10"] = { ["MaxSteer"] = 0.99, ["MaxHealth"] = 108, ["MaxSpeed"] = 47, ["WheelFriction"] = 1.755, ["LaneAccelScale"] = 1.08, ["LaneSpeedScale"] = 1.05, ["DrivingTorque"] = 51000, ["BrakingTorque"] = 124000 },
	["WRX STI"] = { ["MaxSteer"] = 0.994, ["MaxHealth"] = 111, ["MaxSpeed"] = 47.44, ["WheelFriction"] = 1.781, ["LaneAccelScale"] = 1.093, ["LaneSpeedScale"] = 1.057, ["DrivingTorque"] = 52300, ["BrakingTorque"] = 126000 },
	["F&F EVO"] = { ["MaxSteer"] = 0.998, ["MaxHealth"] = 111, ["MaxSpeed"] = 47.89, ["WheelFriction"] = 1.742, ["LaneAccelScale"] = 1.093, ["LaneSpeedScale"] = 1.063, ["DrivingTorque"] = 52300, ["BrakingTorque"] = 127300 },
	["RX7"] = { ["MaxSteer"] = 1.002, ["MaxHealth"] = 110, ["MaxSpeed"] = 48.33, ["WheelFriction"] = 1.638, ["LaneAccelScale"] = 1.08, ["LaneSpeedScale"] = 1.07, ["DrivingTorque"] = 51000, ["BrakingTorque"] = 128000 },
	["350Z"] = { ["MaxSteer"] = 1.002, ["MaxHealth"] = 113, ["MaxSpeed"] = 48.78, ["WheelFriction"] = 1.664, ["LaneAccelScale"] = 1.08, ["LaneSpeedScale"] = 1.07, ["DrivingTorque"] = 53000, ["BrakingTorque"] = 130700 },
	["MK5 Supra"] = { ["MaxSteer"] = 0.994, ["MaxHealth"] = 117, ["MaxSpeed"] = 49.22, ["WheelFriction"] = 1.69, ["LaneAccelScale"] = 1.067, ["LaneSpeedScale"] = 1.057, ["DrivingTorque"] = 55000, ["BrakingTorque"] = 134700 },
	["Skyline R34"] = { ["MaxSteer"] = 0.978, ["MaxHealth"] = 122, ["MaxSpeed"] = 49.67, ["WheelFriction"] = 1.716, ["LaneAccelScale"] = 1.04, ["LaneSpeedScale"] = 1.03, ["DrivingTorque"] = 57000, ["BrakingTorque"] = 140000 },
	["RX7 F&F"] = { ["MaxSteer"] = 0.99, ["MaxHealth"] = 126, ["MaxSpeed"] = 50.11, ["WheelFriction"] = 1.742, ["LaneAccelScale"] = 1.06, ["LaneSpeedScale"] = 1.05, ["DrivingTorque"] = 58300, ["BrakingTorque"] = 143300 },
	["C7"] = { ["MaxSteer"] = 0.994, ["MaxHealth"] = 129, ["MaxSpeed"] = 50.56, ["WheelFriction"] = 1.755, ["LaneAccelScale"] = 1.067, ["LaneSpeedScale"] = 1.057, ["DrivingTorque"] = 59700, ["BrakingTorque"] = 146700 },
	["GT"] = { ["MaxSteer"] = 0.99, ["MaxHealth"] = 132, ["MaxSpeed"] = 51, ["WheelFriction"] = 1.755, ["LaneAccelScale"] = 1.06, ["LaneSpeedScale"] = 1.05, ["DrivingTorque"] = 61000, ["BrakingTorque"] = 150000 },
	["BRZ/FRS/GT86"] = { ["MaxSteer"] = 0.984, ["MaxHealth"] = 116, ["MaxSpeed"] = 48, ["WheelFriction"] = 1.677, ["LaneAccelScale"] = 1.04, ["LaneSpeedScale"] = 1.04, ["DrivingTorque"] = 54000, ["BrakingTorque"] = 130000 },
	["S15"] = { ["MaxSteer"] = 1, ["MaxHealth"] = 112, ["MaxSpeed"] = 48.67, ["WheelFriction"] = 1.755, ["LaneAccelScale"] = 1.093, ["LaneSpeedScale"] = 1.067, ["DrivingTorque"] = 52700, ["BrakingTorque"] = 131300 },
	["Supra MK4"] = { ["MaxSteer"] = 1.006, ["MaxHealth"] = 112, ["MaxSpeed"] = 49.34, ["WheelFriction"] = 1.768, ["LaneAccelScale"] = 1.113, ["LaneSpeedScale"] = 1.077, ["DrivingTorque"] = 53000, ["BrakingTorque"] = 134000 },
	["M4"] = { ["MaxSteer"] = 1.002, ["MaxHealth"] = 116, ["MaxSpeed"] = 50, ["WheelFriction"] = 1.716, ["LaneAccelScale"] = 1.1, ["LaneSpeedScale"] = 1.07, ["DrivingTorque"] = 55000, ["BrakingTorque"] = 138000 },
	["NewSports14"] = { ["MaxSteer"] = 0.994, ["MaxHealth"] = 124, ["MaxSpeed"] = 50.67, ["WheelFriction"] = 1.742, ["LaneAccelScale"] = 1.08, ["LaneSpeedScale"] = 1.057, ["DrivingTorque"] = 57700, ["BrakingTorque"] = 142700 },
	["NewSports02"] = { ["MaxSteer"] = 0.992, ["MaxHealth"] = 126, ["MaxSpeed"] = 51.34, ["WheelFriction"] = 1.755, ["LaneAccelScale"] = 1.073, ["LaneSpeedScale"] = 1.053, ["DrivingTorque"] = 59700, ["BrakingTorque"] = 146700 },
	["i8"] = { ["MaxSteer"] = 0.996, ["MaxHealth"] = 122, ["MaxSpeed"] = 52, ["WheelFriction"] = 1.755, ["LaneAccelScale"] = 1.08, ["LaneSpeedScale"] = 1.06, ["DrivingTorque"] = 61000, ["BrakingTorque"] = 150000 },
	["NewSports06"] = { ["MaxSteer"] = 0.98, ["MaxHealth"] = 125, ["MaxSpeed"] = 52.67, ["WheelFriction"] = 1.703, ["LaneAccelScale"] = 1.047, ["LaneSpeedScale"] = 1.033, ["DrivingTorque"] = 61700, ["BrakingTorque"] = 153300 },
	["M600"] = { ["MaxSteer"] = 0.976, ["MaxHealth"] = 127, ["MaxSpeed"] = 53.34, ["WheelFriction"] = 1.69, ["LaneAccelScale"] = 1.04, ["LaneSpeedScale"] = 1.027, ["DrivingTorque"] = 62300, ["BrakingTorque"] = 156700 },
	["F40"] = { ["MaxSteer"] = 0.984, ["MaxHealth"] = 130, ["MaxSpeed"] = 54, ["WheelFriction"] = 1.716, ["LaneAccelScale"] = 1.06, ["LaneSpeedScale"] = 1.04, ["DrivingTorque"] = 63000, ["BrakingTorque"] = 160000 },
	["190E"] = { ["MaxSteer"] = 0.972, ["MaxHealth"] = 132, ["MaxSpeed"] = 51, ["WheelFriction"] = 1.755, ["LaneAccelScale"] = 1.05, ["LaneSpeedScale"] = 1.02, ["DrivingTorque"] = 55000, ["BrakingTorque"] = 138000 },
	["C63 AMG"] = { ["MaxSteer"] = 0.964, ["MaxHealth"] = 131, ["MaxSpeed"] = 51.67, ["WheelFriction"] = 1.677, ["LaneAccelScale"] = 1.017, ["LaneSpeedScale"] = 1.007, ["DrivingTorque"] = 57000, ["BrakingTorque"] = 141300 },
	["Pantera GT5"] = { ["MaxSteer"] = 0.964, ["MaxHealth"] = 133, ["MaxSpeed"] = 52.34, ["WheelFriction"] = 1.664, ["LaneAccelScale"] = 1.013, ["LaneSpeedScale"] = 1.007, ["DrivingTorque"] = 59300, ["BrakingTorque"] = 145300 },
	["NewSports23"] = { ["MaxSteer"] = 0.972, ["MaxHealth"] = 140, ["MaxSpeed"] = 53, ["WheelFriction"] = 1.716, ["LaneAccelScale"] = 1.04, ["LaneSpeedScale"] = 1.02, ["DrivingTorque"] = 62000, ["BrakingTorque"] = 150000 },
	["NewSports18"] = { ["MaxSteer"] = 0.988, ["MaxHealth"] = 135, ["MaxSpeed"] = 53.67, ["WheelFriction"] = 1.768, ["LaneAccelScale"] = 1.08, ["LaneSpeedScale"] = 1.047, ["DrivingTorque"] = 62000, ["BrakingTorque"] = 154000 },
	["NewSports13"] = { ["MaxSteer"] = 0.998, ["MaxHealth"] = 134, ["MaxSpeed"] = 54.34, ["WheelFriction"] = 1.807, ["LaneAccelScale"] = 1.103, ["LaneSpeedScale"] = 1.063, ["DrivingTorque"] = 63000, ["BrakingTorque"] = 158000 },
	["F1 LM"] = { ["MaxSteer"] = 0.99, ["MaxHealth"] = 143, ["MaxSpeed"] = 55.67, ["WheelFriction"] = 1.807, ["LaneAccelScale"] = 1.083, ["LaneSpeedScale"] = 1.05, ["DrivingTorque"] = 65000, ["BrakingTorque"] = 166000 },
	["Sian"] = { ["MaxSteer"] = 0.982, ["MaxHealth"] = 145, ["MaxSpeed"] = 56.34, ["WheelFriction"] = 1.781, ["LaneAccelScale"] = 1.063, ["LaneSpeedScale"] = 1.037, ["DrivingTorque"] = 65700, ["BrakingTorque"] = 170700 },
	["F5"] = { ["MaxSteer"] = 0.978, ["MaxHealth"] = 142, ["MaxSpeed"] = 57, ["WheelFriction"] = 1.755, ["LaneAccelScale"] = 1.05, ["LaneSpeedScale"] = 1.03, ["DrivingTorque"] = 67000, ["BrakingTorque"] = 176000 },
	["DeLorean"] = { ["MaxSteer"] = 0.96, ["MaxHealth"] = 140, ["MaxSpeed"] = 54, ["WheelFriction"] = 1.677, ["LaneAccelScale"] = 1, ["LaneSpeedScale"] = 1, ["DrivingTorque"] = 57000, ["BrakingTorque"] = 145000 },
	["Roadster 2.0"] = { ["MaxSteer"] = 0.976, ["MaxHealth"] = 141, ["MaxSpeed"] = 54.67, ["WheelFriction"] = 1.755, ["LaneAccelScale"] = 1.053, ["LaneSpeedScale"] = 1.027, ["DrivingTorque"] = 63700, ["BrakingTorque"] = 153700 },
	["NewSports34"] = { ["MaxSteer"] = 0.988, ["MaxHealth"] = 141, ["MaxSpeed"] = 55.34, ["WheelFriction"] = 1.794, ["LaneAccelScale"] = 1.083, ["LaneSpeedScale"] = 1.047, ["DrivingTorque"] = 65700, ["BrakingTorque"] = 159000 },
	["720S"] = { ["MaxSteer"] = 0.996, ["MaxHealth"] = 138, ["MaxSpeed"] = 56, ["WheelFriction"] = 1.794, ["LaneAccelScale"] = 1.09, ["LaneSpeedScale"] = 1.06, ["DrivingTorque"] = 63000, ["BrakingTorque"] = 161000 },
	["NewSports04"] = { ["MaxSteer"] = 1.004, ["MaxHealth"] = 137, ["MaxSpeed"] = 56.67, ["WheelFriction"] = 1.846, ["LaneAccelScale"] = 1.11, ["LaneSpeedScale"] = 1.073, ["DrivingTorque"] = 64300, ["BrakingTorque"] = 167000 },
	["Gemera"] = { ["MaxSteer"] = 1, ["MaxHealth"] = 139, ["MaxSpeed"] = 57.34, ["WheelFriction"] = 1.833, ["LaneAccelScale"] = 1.1, ["LaneSpeedScale"] = 1.067, ["DrivingTorque"] = 65700, ["BrakingTorque"] = 171700 },
	["Huyara BC"] = { ["MaxSteer"] = 0.984, ["MaxHealth"] = 144, ["MaxSpeed"] = 58, ["WheelFriction"] = 1.755, ["LaneAccelScale"] = 1.06, ["LaneSpeedScale"] = 1.04, ["DrivingTorque"] = 67000, ["BrakingTorque"] = 175000 },
	["NewSports11"] = { ["MaxSteer"] = 0.976, ["MaxHealth"] = 151, ["MaxSpeed"] = 58.67, ["WheelFriction"] = 1.781, ["LaneAccelScale"] = 1.053, ["LaneSpeedScale"] = 1.027, ["DrivingTorque"] = 69700, ["BrakingTorque"] = 179700 },
	["Senna"] = { ["MaxSteer"] = 0.98, ["MaxHealth"] = 153, ["MaxSpeed"] = 59.34, ["WheelFriction"] = 1.807, ["LaneAccelScale"] = 1.067, ["LaneSpeedScale"] = 1.033, ["DrivingTorque"] = 70700, ["BrakingTorque"] = 184700 },
	["Jesko Attack"] = { ["MaxSteer"] = 0.996, ["MaxHealth"] = 148, ["MaxSpeed"] = 60, ["WheelFriction"] = 1.833, ["LaneAccelScale"] = 1.1, ["LaneSpeedScale"] = 1.06, ["DrivingTorque"] = 70000, ["BrakingTorque"] = 190000 },
	["Model 3"] = { ["MaxSteer"] = 0.978, ["MaxHealth"] = 114, ["MaxSpeed"] = 42.5, ["WheelFriction"] = 1.716, ["LaneAccelScale"] = 1.06, ["LaneSpeedScale"] = 1.03, ["DrivingTorque"] = 55000, ["BrakingTorque"] = 124000 },
	["M3 GTR"] = { ["MaxSteer"] = 1.002, ["MaxHealth"] = 116, ["MaxSpeed"] = 50, ["WheelFriction"] = 1.716, ["LaneAccelScale"] = 1.1, ["LaneSpeedScale"] = 1.07, ["DrivingTorque"] = 55000, ["BrakingTorque"] = 138000 },
	["SUPRA MK4"] = { ["MaxSteer"] = 1.006, ["MaxHealth"] = 112, ["MaxSpeed"] = 49.34, ["WheelFriction"] = 1.768, ["LaneAccelScale"] = 1.113, ["LaneSpeedScale"] = 1.077, ["DrivingTorque"] = 53000, ["BrakingTorque"] = 134000 },
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