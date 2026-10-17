--!strict

-- Pure simulated gearbox shared by the dashboard and engine audio. The chassis itself has no
-- gears; keeping this calculation in one place prevents the gear label and engine note from
-- disagreeing about when a shift happened.
local AutomaticGearbox = {}

function AutomaticGearbox.sample(
	speedMph: number,
	currentGear: number,
	topMph: number,
	gearCount: number,
	downshiftHysteresis: number
): (number, number)
	local count = math.max(1, math.floor(gearCount))
	local gear = math.clamp(math.floor(currentGear), 1, count)
	local band = math.clamp(speedMph / math.max(topMph, 1e-3), 0, 1) * count

	-- Upshifts happen at the top of the current band. A downshift waits until speed is slightly
	-- below its boundary so ordinary cruise variation cannot make the box hunt between two gears.
	if band >= gear or band < gear - 1 - math.max(downshiftHysteresis, 0) then
		gear = math.clamp(math.floor(band) + 1, 1, count)
	end

	local through = math.clamp(band - (gear - 1), 0, 1)
	return gear, through
end

return table.freeze(AutomaticGearbox)
