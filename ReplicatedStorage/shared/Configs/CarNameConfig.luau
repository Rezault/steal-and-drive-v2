--[[
	CarNameConfig
	-------------
	WHAT EVERY CAR IS CALLED ON SCREEN. Added 2026-09-28: the roster is named after real cars, and a
	real car's name is somebody's trademark, so every body gets a game name that is recognisably the
	same car and not the same word — "Civix", not "Civic".

	TWO NAMES, AND ONLY ONE OF THEM IS SHOWN. The INTERNAL name is the key on the left: it is the rig's
	name in `Workspace.CarSystem`, the body in every save file (`Camaro:6#17`), and what
	`WorldConfig`, `PaintConfig.KeepLivery`, `CarConfig` and the stats tables are keyed by. It must
	never change here — renaming it would orphan every car anybody owns. The DISPLAY name on the right
	is what a player reads, and it is free to change at any time: nothing stores it.

	ONE DOOR. `GarageConfig.displayName` is the only reader, and every label that names a car goes
	through it (or through `GarageConfig.carName`, which adds the colour). A screen that printed a body
	name straight off a key would be showing the trademark this file exists to hide — so a new screen
	that names a car should call that function, never `string.upper(body)`.

	WHAT CHANGED IN THE NAMES, as a rule to follow when adding a car: keep the silhouette of the word
	(first letter, length, a number where there was one) and change a letter or two; replace a
	franchise tag outright ("F&F" is the films, so those liveries are "Fury"); keep generic
	designations only where they are not a model name in their own right.

	A body missing from `Names` falls back to its internal name, spaced for reading — which is right
	for the placeholder traffic bodies (`Sedan12` -> "SEDAN 12") and WRONG for a real car, so the
	roster is checked against this table (`missing`, logged by `GarageService` at start).

	`Enabled = false` shows every internal name again, exactly as before this file.
]]

local CarNameConfig = {}

CarNameConfig.Enabled = true

--- Internal body name -> display name. Grouped by world in ladder order, variants after each ladder.
CarNameConfig.Names = {
	["918"] = "Porten 918",
	["Civic"] = "Civaro",
	["Golf GTI"] = "Golven GTI",
	["GNX"] = "Garnex",
	["Camaro"] = "Kammro",
	["Charger"] = "Chargent",
	["Model 3"] = "Moden 3",
	["Challenger"] = "Challent",
	["Mustang"] = "Mavero",
	["Maybach"] = "Genes GE7", -- the model is a Genesis, not a Maybach (2026-10-14); the body key stays, saves hold it
	["M5"] = "Mavik 5",
	["EVO"] = "Evora",
	["EVO 10"] = "Evora 10",
	["WRX STI"] = "Wrex ST",
	["F&F EVO"] = "Evora Custom",
	["RX7"] = "Rexel 7",
	["350Z"] = "Zentro 350",
	["RX7 F&F"] = "Rexel 7 Custom",
	["C7"] = "Corven 7",
	["MK5 Supra"] = "Supran MK5",
	["Skyline R34"] = "Skylane 34",
	["GT"] = "Granvel GT",
	["Supra MK4"] = "Supran MK4",
	["SUPRA MK4"] = "Supran MK4 Custom",
	["BRZ/FRS/GT86"] = "Braven 86",
	["S15"] = "Silven 15",
	["M4"] = "Mavik 4",
	["M3 GTR"] = "Mavik 3 GT",
	["i8"] = "Iven 8",
	["M600"] = "Nover 600",
	["F40"] = "Ferro 40",
	["190E"] = "Meron 190",
	["Pantera GT5"] = "Panterro GT5",
	["C63 AMG"] = "Cavren 63",
	["F1 LM"] = "Macren LM",
	["Sian"] = "Siano",
	["F5"] = "Venaro F5",
	["DeLorean"] = "Deloren",
	["Roadster 2.0"] = "Rovster 2",
	["720S"] = "Macren 720",
	["Senna"] = "Senera",
	["Huyara BC"] = "Huvara BC",
	["Gemera"] = "Gemeris",
	["Jesko Attack"] = "Jestra",
	-- Newly rostered bodies keep their internal asset keys; only captions are authored here.
	["NewSports02"] = "Auren 8",
	["NewSports06"] = "Ferro 48",
	["NewSports14"] = "Skylane GT",
	["NewSports18"] = "Porten GT",
	["NewSports23"] = "Porten Classic",
	["NewSports13"] = "Ferro Spider",
	["NewSports34"] = "Porten Sport",
	["NewSports04"] = "Huraven",
	["NewSports11"] = "Ferro Apex",
	["NewSports31"] = "Meron GT",
	["Lambo"] = "Aventra",
}

--- The display name for a body, or nil when it has none (or the table is switched off).
function CarNameConfig.nameOf(body: string): string?
	if not CarNameConfig.Enabled then
		return nil
	end
	return CarNameConfig.Names[body]
end

--- Every body in `bodies` with no display name, sorted. Pure, so a test can run it too.
function CarNameConfig.missing(bodies: { string }): { string }
	local out = {}
	for _, body in bodies do
		if CarNameConfig.Names[body] == nil then
			table.insert(out, body)
		end
	end
	table.sort(out)
	return out
end

return CarNameConfig
