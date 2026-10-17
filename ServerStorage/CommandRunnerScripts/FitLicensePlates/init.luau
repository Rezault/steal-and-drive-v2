--[[
	FitLicensePlates — Command Runner command

	Fits the number plate onto the back of every car on the roster, or onto the selection. The
	geometry — where it lands, how big it is, how it welds on, and the one rotation rule that is
	not negotiable — is in `Plate.luau`; this is the wrapper and the report.

	=== WHAT IT TOUCHES ========================================================

	`Workspace.CarSystem`, which is the master roster. Every other copy of a car in this game is
	made from one of those rigs — the lobby car, a garage podium, a dealership viewport, the
	published traffic shells, the rig a race spawns — so fitting the master IS fitting the game.
	Nothing here writes to a clone, and nothing here should ever be run against one.

	The prefab it clones from is `ServerStorage.LicensePlate`: a two-mesh model, `plate_frame`
	(the navy holder) and `plate_face` (the white panel the text is printed on). Authored at 82
	studs wide, which is why everything is scaled rather than used as-is.

	IDEMPOTENT. A car that already has a plate has it removed and re-fitted, and the fit measures
	the bodywork with any existing plate excluded, so re-running with a different width is a fresh
	answer rather than a drift.

	THE NUMBER ON IT IS PER CAR, out of `Configs/PlateConfig` — the same pool, and for a stock car
	the same plate, the game gives that body at runtime. Fill the `Text` argument in to override
	every plate with one string instead, which is what you want while looking at placement.

	=== READING THE REPORT =====================================================

	`height%` is where the plate sits up the body, and the honest way to spot a bad fit without
	looking at 63 cars. The band is 18-55% by construction; anything sitting hard against either
	end got there because the search had nowhere better to go, and is worth a look. `standoff` is
	how far the plate had to be pushed out of a sloped panel — a large one means the bumper there
	is raked, and the plate will read as floating. `inset` is how far forward of the car's
	rearmost point it ended up; a big number means the car has a wing and the plate is correctly
	tucked under it.
]]

local Types = require(script.Types)
local Plate = require(script.Plate)

-- The master roster. See the header: these are the rigs everything else is cloned from.
local ROSTER = "CarSystem"
-- Rigs in the roster folder that are not cars on the roster.
local SKIP = { CarBones = true, CarBones_BACKUP = true }
local PREFAB = "LicensePlate"

local function rosterCars(): { Model }
	-- The roster was parked in ServerStorage on 2026-10-13; Workspace still wins if dragged back.
	local folder = workspace:FindFirstChild(ROSTER) or game:GetService("ServerStorage"):FindFirstChild(ROSTER)
	local out = {}
	if not folder then
		return out
	end
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and not SKIP[child.Name] then
			table.insert(out, child)
		end
	end
	return out
end

--[[ The rig a selected instance belongs to.

	Selecting a car in this place usually means having clicked one of its meshes, so a selection is
	far more often a part somewhere under a rig than the rig itself. Walk up to the model that has
	a `Chassis` and take that. ]]
local function rigOf(inst: Instance): Model?
	local current: Instance? = inst
	while current and current ~= workspace do
		if current:IsA("Model") and current:FindFirstChild("Chassis") and current:FindFirstChild("Body") then
			return current
		end
		current = current.Parent
	end
	return nil
end

return {
	Description = "Fits the number plate to the rear of every car on the roster.",
	Tags = { "cars", "art", "roster" },
	AutoRecordChanges = true,

	Arguments = {
		Width = {
			Type = "number",
			Default = Plate.Defaults.Width,
			Description = "Plate width in studs. The pack's bodies are 8.5-12.9 studs wide.",
			LayoutOrder = 1,
		},
		Depth = {
			Type = "number",
			Default = Plate.Defaults.Depth,
			Description = "Frame thickness in studs. Scaled separately from the width on purpose — see Plate.luau.",
			LayoutOrder = 2,
		},
		Text = {
			Type = "string",
			Default = Plate.Defaults.Text,
			Description = "One string on every plate. LEAVE EMPTY and each car gets its own generated plate.",
			LayoutOrder = 3,
		},
		SelectionOnly = {
			Type = "boolean",
			Default = false,
			Description = "Fit only the selected car(s) instead of the whole roster.",
			LayoutOrder = 4,
		},
	} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()
		out:clear()

		local prefab = game:GetService("ServerStorage"):FindFirstChild(PREFAB)
		if not prefab then
			out:error(string.format("No ServerStorage.%s — nothing to fit.", PREFAB))
			return
		end

		local cars
		if arguments.SelectionOnly then
			local seen, picked = {}, {}
			for _, inst in props.Selected do
				local rig = rigOf(inst)
				if rig and not seen[rig] then
					seen[rig] = true
					table.insert(picked, rig)
				end
			end
			if #picked == 0 then
				out:error("Nothing selected that is part of a car rig.")
				return
			end
			cars = picked
		else
			cars = rosterCars()
			if #cars == 0 then
				out:error(string.format("No cars under %s in Workspace or ServerStorage.", ROSTER))
				return
			end
		end

		local options = {
			Width = if type(arguments.Width) == "number" and arguments.Width > 0 then arguments.Width else nil,
			Depth = if type(arguments.Depth) == "number" and arguments.Depth > 0 then arguments.Depth else nil,
			Text = if type(arguments.Text) == "string" and arguments.Text ~= "" then arguments.Text else nil,
		}

		local fitted, failed, plates = {}, {}, {}
		for _, car in cars do
			local fit, why = Plate.place(car, prefab, options)
			if fit then
				table.insert(fitted, { name = car.Name, fit = fit })
				table.insert(plates, car.Body.plate_frame)
			else
				table.insert(failed, string.format("%s (%s)", car.Name, why or "?"))
			end
		end

		if #fitted == 0 then
			out:error("Fitted nothing. " .. table.concat(failed, "; "))
			return
		end

		table.sort(fitted, function(a, b)
			return a.fit.height < b.fit.height
		end)
		out:print(string.format("%-22s %-9s %8s %9s %7s", "car", "plate", "height%", "standoff", "inset"))
		for _, entry in fitted do
			out:print(
				string.format(
					"%-22s %-9s %7.1f%% %9.3f %7.2f",
					entry.name,
					entry.fit.text,
					entry.fit.height * 100,
					entry.fit.standoff,
					entry.fit.inset
				)
			)
		end

		if #failed > 0 then
			out:warn(string.format("No plate on %d: %s", #failed, table.concat(failed, ", ")))
		end
		out:print(
			string.format(
				"Fitted %d plate(s), %.2f studs wide, %s.",
				#fitted,
				options.Width or Plate.Defaults.Width,
				if options.Text then string.format("all reading %q", options.Text) else "each with its own generated plate"
			)
		)

		pcall(function()
			props:SetSelection(plates)
		end)
	end,
} :: Types.ScriptModule
