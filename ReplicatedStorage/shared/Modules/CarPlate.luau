--[[
	CarPlate  (shared)
	------------------
	Where a car's number plate text lives and how to change it. The sibling of `Modules/CarPaint`,
	and it exists for the same reason that one does: five very different callers — the display car
	on a garage podium, the one parked in the street, the card on the dealership page, the car a
	race spawns and a stranger's car on the road — have to agree about the same car, and any two of
	them disagreeing shows up as a plate that changes when you look at it from somewhere else.

	`Configs/PlateConfig` owns WHAT a plate reads and which car gets which. This module owns finding
	the thing to write it on.

	=== WHERE THE TEXT ACTUALLY IS =============================================================

	The plate is two meshes welded to the dress like any other body part — `plate_frame` (the navy
	holder) and `plate_face` (the white panel) — both fitted by `CommandRunnerScripts/
	FitLicensePlates`, whose `Plate.luau` header has the geometry. The text is a `SurfaceGui` named
	`PlateText` on `plate_face`, holding one `TextLabel` named `Label`.

	THAT MAKES THE TEXT A CHILD OF A DRESS PART, which is why it travels for free through both of
	this game's clone filters — `TrafficService._buildShell` and `CarBody.swapMeshes` — and why both
	of them list `SurfaceGui` as a render class. Drop either and this module still finds nothing to
	write on, silently, on exactly the cars a player looks at most.

	=== A RIGGED CAR, A FLAT SHELL, AND HALF A CAR =============================================

	The search is a plain recursive `FindFirstChild`, deliberately, because the three shapes a car
	arrives in here have nothing else in common: a full CarBones rig nests its dress under `Body/`,
	a published traffic shell is a flat bag of meshes welded to one `Root`, and a garage podium
	holds nothing but a clone of the `Body` folder with no chassis under it at all. The plate is
	somewhere below all three, and none of them can be walked the same way.

	=== ONE WRITE, NOT A LOOP ==================================================================

	`write` is a property set on a label that already exists — it never builds one. A car whose
	master rig has not been through `FitLicensePlates` has no plate to write on and gets nothing
	rather than a floating label, which is the correct outcome: a plate is geometry, and geometry is
	fitted per body by a command that measures the bodywork.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local PlateConfig = require(ReplicatedStorage.shared.Configs.PlateConfig)

local CarPlate = {}

-- The three names the fit command authors. Kept here rather than imported from it: that module
-- lives in ServerStorage and is a Studio plugin command, so nothing at runtime may require it.
local FACE_NAME = "plate_face"
local GUI_NAME = "PlateText"
local LABEL_NAME = "Label"

--[[ The label to write on, or nil for a car with no plate fitted.

	Worth holding on to rather than re-finding: the traffic controller re-plates a pooled record on
	every spawn and would otherwise walk a 30-part shell each time, for a string. ]]
function CarPlate.label(car: Instance?): TextLabel?
	if not car then
		return nil
	end
	local face = car:FindFirstChild(FACE_NAME, true)
	local gui = face and face:FindFirstChild(GUI_NAME)
	local label = gui and gui:FindFirstChild(LABEL_NAME)
	return if label and label:IsA("TextLabel") then label else nil
end

--[[ Write `text` on the car's plate. Returns whether there was a plate to write on, which is what
	a caller logs on: a car that quietly has no plate is worth hearing about once, and never per
	frame. ]]
function CarPlate.write(car: Instance?, text: string): boolean
	local label = CarPlate.label(car)
	if not label then
		return false
	end
	label.Text = text
	return true
end

--[[ Plate a car the player owns, by its identity.

	`body` and `paint` are the same pair every other system identifies a car by — see
	`GarageConfig.carKey` — so this is the call that makes the podium, the street, the dealership
	card and the race car agree without any of them telling the others anything. Returns the text
	written, or nil if this car had no plate on it.

	`PlateConfig.Enabled = false` leaves the authored text alone rather than writing a fallback over
	it: off means off, everywhere, on one line. ]]
function CarPlate.apply(car: Instance?, body: unknown, paint: unknown): string?
	if not PlateConfig.Enabled or type(body) ~= "string" then
		return nil
	end
	local text = PlateConfig.forKey(GarageConfig.carKey(body, tonumber(paint)))
	return if CarPlate.write(car, text) then text else nil
end

--[[ Plate a car nobody owns — traffic. Rolled per spawn off the caller's rng, the same way and at
	the same moment its colour is (`PaintConfig.roll`), so a lane of the same body is a lane of
	different cars. ]]
function CarPlate.roll(car: Instance?, rng: Random): string?
	if not PlateConfig.Enabled then
		return nil
	end
	local text = PlateConfig.roll(rng)
	return if CarPlate.write(car, text) then text else nil
end

return CarPlate
