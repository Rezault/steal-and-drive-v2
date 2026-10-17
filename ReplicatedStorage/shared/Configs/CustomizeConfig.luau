--[[
	CustomizeConfig
	---------------
	THE CUSTOMIZATION BAY: one podium on every lot that is a workshop instead of a display. Park a car
	on it and pressing the podium (or its kiosk) opens a screen where the car can be REPAIRED back to
	full condition, REPAINTED, and fitted with PERFORMANCE PARTS — each shown with its price and what
	it adds to the car's market value before it is bought. Added 2026-09-28, the dealership rework's
	third card. `WorkshopService` is the machine, `WorkshopController` the (placeholder) screen, and
	`GarageService` owns every write to the car.

	=== FIVE THINGS TO KNOW BEFORE TOUCHING ANY OF IT ==========================================

	1. IT IS A BAY THAT IS NOT A SHOWROOM: `CarSlot_Workshop`, its own podium on every plot
	   (`Bay.SlotIndex` has how it got there). A car stands on it exactly as on any bay — the
	   picker, the carry and the swap rules are unchanged — but NOTHING SHOWROOM HAPPENS TO IT: no
	   customer tips it, no buyer offers on it, no NOT FOR SALE sign hangs on it, and a bank never
	   auto-parks into it. That is the "one car, one system" lock the card asked for, and it falls out
	   of `GarageService.locationOf` answering "Workshop" rather than "Bay" for that podium.

	2. EVERYTHING IS INSTANT. Pay, and the change is on the car in the same press — no timer, no
	   queue. The owner's call over a workshop that takes real minutes; a timed job is the obvious
	   next knob and would live here.

	3. PARTS ARE VALUE ONLY, for now. They raise market value — and through it the tips a car draws
	   and what a buyer offers — but the run still drives every car on its model's stats. Wiring them
	   to `CarStats` needs the start car to be picked by ID all the way into the chassis, which is its
	   own job. Nothing here pretends otherwise: the screen says VALUE, not SPEED.

	4. A REPAINT CHANGES THE CAR'S ID. Colour is part of a car's identity (`GarageConfig.Banking`), so
	   a red Camaro repainted black is re-keyed `Camaro:6#17` -> `Camaro:3#17` — THE SERIAL SURVIVES,
	   which is what keeps it the same car. `GarageService.repaintCar` moves every table keyed by it
	   in one pass and fires `CarRekeyed` for the services that hold an ID of their own.

	5. EVERY PRICE IS A FRACTION OF THE MODEL'S BASE VALUE (`GarageConfig.valueOf`), so the workshop
	   scales with the ladder: a Tier 1 repair is pocket change and a Tier 8 one is a decision.

	`Enabled = false`: the podium is an ordinary display bay again, the kiosk sells tip levels, and
	any parts a car was fitted with stop counting toward its value — exactly as before this file.
	Nothing saved is deleted, so switching it back on restores every fitted part.
]]

local CustomizeConfig = {}

CustomizeConfig.Enabled = true

-- === Where ==================================================================

CustomizeConfig.Bay = {
	--[[ === ITS OWN PODIUM NOW, NOT BAY 3 — 2026-09-28 ======================================

		WHAT IT WAS. The workshop took over `CarSlot_F1_3`, the display bay at the back of floor 1, and
		the lot went from six showroom bays to five.

		WHAT IT IS. A SEVENTH podium, `CarSlot_Workshop`, cloned from slot 3 and moved elsewhere on
		every plot (a command-bar script, run once, 2026-09-28), so all six display bays stay
		showroom. It is a stand-in for the pedestal model that is coming; that model only needs to be
		a tagged `CarSlot` carrying this `SlotIndex` to take over.

		WHY 0 AND NOT 7. `UpgradeService` numbers the floor-2 podiums on from the HIGHEST index already
		standing on the plot (its "bay numbers are per lot" note). A workshop at 7 would push the
		upstairs bays to 8..13 and move every car a player already has parked up there; a workshop at
		99 would make them 100..105. 0 sits below everything, so floor 2 stays 7..12. ]]
	SlotIndex = 0,
}

--- The podium's prompt, with a car on the workshop and empty hands. Empty, it is the ordinary
--- picker prompt (so a car can be put there at all); holding a car, it places it.
CustomizeConfig.Prompt = {
	ActionText = "Customize",
	ObjectText = "Workshop",
}

--[[ The kiosk on the workshop podium, repurposed: it used to sell that bay's tip level, and a bay
	that draws no tips has no use for one. It becomes the workshop's sign, and pressing it opens the
	screen (`UpgradeService._onBayRequest`). The two lines are the kiosk's own cost and level labels,
	so the board needs no rebuild. ]]
CustomizeConfig.Kiosk = {
	Title = "CUSTOMIZE",
	Subtitle = "REPAIR · PAINT · PARTS",
	Color = Color3.fromRGB(122, 84, 214),

	--[[ The KIT face (2026-09-30, `BuildWorkshopSign`, `NewUIConfig.KitWorkshopSign`): a small kit
		window built from the Cartoony Kit's own Upgrades frame, in the kit's words (title case, like
		its "Upgrades" and "Rebirth").

		ONE THING ON IT LOOKS PRESSABLE, AND IT IS THE GREEN BUTTON (Dylan, same day). The first kit
		face put Repair, Paint and Parts on the kit's gradient cards and a wrench in the kit's square
		button, and in game every one of them read as its own button, while only Customize did
		anything. So the header is the title alone (Repair's wrench below already says workshop), the
		three are one line of plain type with bare glyphs, and the green button fills most of the
		body. The whole face still takes the press, so a click on the words is not lost. ]]
	KitTitle = "Workshop",
	KitButton = "Customize",
	--- The info line, left to right. `Glyph` is a key of `UIAssets.WorkshopCards.Glyphs`.
	KitCards = {
		{ Key = "KitRepair", Label = "Repair", Glyph = "Repair" },
		{ Key = "KitPaint", Label = "Paint", Glyph = "Paint" },
		{ Key = "KitParts", Label = "Parts", Glyph = "Engine" },
	},
	--- The two SurfaceGuis the kit face adds beside `UpgradeGui` and `BackPlate` on the same board.
	KitGuiName = "UpgradeGuiKit",
	KitBackName = "BackPlateKit",
	--- Under the kit face's button: everything drawn on the sign, hidden on an unowned lot, the way
	--- the classic plaque blanks its two lines.
	KitContentName = "Content",
	KitButtonName = "Go",
	--[[ Every label on the kit face carries this attribute, naming the field of this table its text
		comes from ("KitTitle", "KitButton", or a card's `Key`), and `GarageService` redraws each from
		here. So a wording change is a config line, not a rebuild, and the service does not need to
		know the layout. ]]
	KitTextAttribute = "SignText",

	--[[ A CONTROLLER'S WAY IN (2026-10-15). The sign is a SurfaceGui in the world, which a pad can
		neither point at nor select, and E/X on the workshop podium picks the car up rather than
		opening the menu, so on a pad the Workshop could not be opened at all. So for a pad player, on
		their own plot, the sign also carries Roblox's own prompt, and pressing it is the same as
		pressing the sign (`UpgradeController._bindKiosk`). Nobody on a mouse or a phone ever sees it.

		ON Y, NOT X: the podium's own prompt is X and stands within reach of the sign, and two prompts
		on one key show only the nearer. `MaxDistance` is from the sign, so it comes up as you walk to
		the sign and not from anywhere on the podium. ]]
	PadPrompt = {
		Key = Enum.KeyCode.ButtonY,
		MaxDistance = 10,
	},
}

--- The words a kit-face label with `KitTextAttribute = key` shows, or nil for a key nothing names.
function CustomizeConfig.kioskText(key: unknown): string?
	local sign = CustomizeConfig.Kiosk
	if type(key) ~= "string" then
		return nil
	end
	for _, card in sign.KitCards do
		if card.Key == key then
			return card.Label
		end
	end
	local text = (sign :: any)[key]
	return if type(text) == "string" then text else nil
end

-- === Repair =================================================================

CustomizeConfig.Repair = {
	--[[ A repair costs this fraction of the market value it GIVES BACK:

		    cost = CostOfGain * (value at full condition - value now)

		0.6 so a repair is always worth doing on paper — pay 60 cents, the car is worth a dollar more —
		without being free money: selling straight after repairing nets 40% of the damage back, not
		all of it. At 1.0 repairing only helps the tips; above 1.0 it loses money on a sale, which
		would make the bay's first button a trap. A TASTE CALL. ]]
	CostOfGain = 0.6,
}

-- === Paint ==================================================================

CustomizeConfig.Paint = {
	--[[ A repaint costs this fraction of the model's base value, flat, whatever colour it goes to.
		It adds NO value — colour is taste, and a black Camaro is not worth more than a red one — so
		this is a pure sink, priced to feel like a real spend on a cheap car and trivial on a
		supercar. A TASTE CALL; a colour premium would be a per-palette table here. ]]
	CostFraction = 0.05,
}

-- === Parts ==================================================================

--[[ The performance parts, in the order the screen lists them. Placeholders: the names are real car
	words so the screen reads right, and none of them touches the chassis yet (header note 3). Adding
	a part is adding a row; the save keys on `Key`, so renaming a `Label` is free and renaming a
	`Key` orphans every level already bought for it. ]]
CustomizeConfig.Parts = {
	{ Key = "Engine", Label = "ENGINE" },
	{ Key = "Transmission", Label = "TRANSMISSION" },
	{ Key = "Tires", Label = "TIRES" },
}

--- Levels each part goes up to.
CustomizeConfig.PartLevels = 3

--[[ Market value each level of each part adds, as a fraction of the model's base value. Applied in
	`MarketValueConfig.valueOf`, after condition:

	    value = base * conditionFactor * (1 + ValuePerLevel * total levels fitted)

	so a fully fitted car (3 parts x 3 levels) is worth 1.45x its model. ]]
CustomizeConfig.ValuePerLevel = 0.05

--[[ What level L of a part costs, as a fraction of the model's base value: `CostPerLevel * L`.

	THE LADDER CLIMBS, THE REWARD DOES NOT. Level 1 costs 4% and adds 5% — ahead the moment it is
	fitted. Level 2 costs 8% for the same 5%, level 3 costs 12%: those only pay back through the tips
	and offers a more valuable car draws over time, which is the point of putting it on display. A
	full car costs 72% of its base for +45% of value. Move `CostPerLevel` and `ValuePerLevel`
	together; only level 1 should ever beat its own price on the spot. A TASTE CALL. ]]
CustomizeConfig.CostPerLevel = 0.04

--- The key of a known part, or nil. Anything else in a save is ignored rather than trusted.
function CustomizeConfig.partOf(key: unknown)
	for _, part in CustomizeConfig.Parts do
		if part.Key == key then
			return part
		end
	end
	return nil
end

--- One part's level off a car record's `Parts` table, clamped to the ladder.
function CustomizeConfig.levelOf(parts: unknown, key: string): number
	local raw = if type(parts) == "table" then parts[key] else nil
	if type(raw) ~= "number" or raw ~= raw then
		return 0
	end
	return math.clamp(math.floor(raw), 0, CustomizeConfig.PartLevels)
end

--[[ The value multiplier a car's parts give it: `1 + ValuePerLevel * levels`. Only known parts count
	(`partOf`), and nothing counts with the workshop switched off — header, `Enabled`. ]]
function CustomizeConfig.partsFactor(parts: unknown): number
	if not CustomizeConfig.Enabled then
		return 1
	end
	local levels = 0
	for _, part in CustomizeConfig.Parts do
		levels += CustomizeConfig.levelOf(parts, part.Key)
	end
	return 1 + CustomizeConfig.ValuePerLevel * levels
end

-- === Broadcast ==============================================================

--[[ Every fitted part of every car, on the Player, so a screen prices a car the way the server does
	— the partner of `GarageConfig.ConditionAttribute`, for the same reason. Format:

	    "Camaro:6#17=Engine.2|Tires.1,Civic:1#3=Engine.1"

	`=` and `,` for `ConditionAttribute`'s reasons, `|` between parts and `.` before a level because
	the ID already spends the colon and the hash. A car with nothing fitted is absent. ]]
CustomizeConfig.PartsAttribute = "CarParts"

--- The other half of `PartsAttribute`: car ID -> { [partKey] = level }.
function CustomizeConfig.decodeParts(raw: unknown): { [string]: { [string]: number } }
	local out = {}
	if type(raw) ~= "string" then
		return out
	end
	for entry in string.gmatch(raw, "[^,]+") do
		local id, list = string.match(entry, "^(.+)=(.+)$")
		if id and list then
			local parts = {}
			for key, level in string.gmatch(list, "([%w_]+)%.(%d+)") do
				parts[key] = tonumber(level)
			end
			out[id] = parts
		end
	end
	return out
end

--- The same format the other way, for `GarageService`. Parts are written in `Parts` order so the
--- attribute does not churn between two writes of the same car.
function CustomizeConfig.encodeParts(id: string, parts: unknown): string?
	local bits = {}
	for _, part in CustomizeConfig.Parts do
		local level = CustomizeConfig.levelOf(parts, part.Key)
		if level > 0 then
			table.insert(bits, string.format("%s.%d", part.Key, level))
		end
	end
	if #bits == 0 then
		return nil
	end
	return string.format("%s=%s", id, table.concat(bits, "|"))
end

-- === Words ==================================================================

--- The screen. Placeholder UI built in code; see `WorkshopController`.
CustomizeConfig.Screen = {
	Title = "WORKSHOP · %s",
	Value = "WORTH %s",
	Condition = "CONDITION %d%%",
	Repair = "REPAIR",
	RepairDone = "FULLY REPAIRED",
	RepairLine = "Back to 100%%: %s (worth +%s)",
	Paint = "PAINT",
	PaintLine = "Any colour: %s each (no value change)",
	PaintLocked = "This car keeps its factory livery.",
	--- A mutation that hides the paint (`WeatherConfig` `NoPaint`); `%s` is the mutation's name.
	PaintLockedMutation = "%s cars can't be repainted.",
	Parts = "PERFORMANCE PARTS",
	PartLine = "%s  LV %d/%d",
	PartBuy = "%s (+%s)",
	PartMax = "MAXED",
	Change = "CHANGE CAR",
	Close = "CLOSE",
	Empty = "Put a car on the workshop podium to customize it.",
	--[[ The new UI's screen (`BuildWorkshopV2`, 2026-09-30). The car's name moves out of the title
		into the column over the car, so the title is the bay's name alone, and every line is set in
		capitals like the rest of the kit. `Value`, `Condition`, `RepairDone`, `PartMax` and `Change`
		above are shared with it. Only `Gain` and `PaintEach` are format strings. ]]
	KitTitle = "WORKSHOP",
	--- Short, because it shares its row with the value line and the button.
	RepairSub = "BACK TO 100%",
	--- On the grey button of a car with nothing to repair.
	RepairFull = "100%",
	Gain = "+%s VALUE",
	PaintSub = "ANY COLOUR · NO VALUE CHANGE",
	PaintEach = "%s EACH",
	PaintKept = "KEEPS ITS FACTORY LIVERY",
	--- The word on the swatch that puts the artist's own livery back.
	Stock = "STOCK",
	--[[ The card layout's (`BuildWorkshopCards`, behind `NewUIConfig.WorkshopCards`). Its buttons are
		two lines, the verb over the price, and PAINT is picked on the swatches and bought on its own
		button, so a colour can be looked at on the car before it is paid for. ]]
	CardPaintSub = "CHANGES APPEARANCE ONLY",
	CardLevel = "Level %d / %d",
	CardUpgrade = "UPGRADE",
	CardRepair = "REPAIR",
	CardPaint = "PAINT CAR",
	Percent = "%d%%",
	--- Seconds between presses of any button. Courtesy on top of the server's own limit.
	Cooldown = 0.35,
}

-- Approved economy balance, 2026-10-04.
CustomizeConfig.Paint.CostFraction = 0.02
--[[ RAISED 2026-10-08 (was 0.08 / 0.11 / 0.15): a level adds 5% of value, which on the podium is 5% more
	tips, and at the old prices that paid itself back in about six minutes — a button to press, not a
	choice. At 0.2 / 0.4 / 0.8 of base, level 1 repays in roughly half an hour of a world 2 car's tips and
	level 3 in a few hours: the last levels are for the car you mean to keep. ]]
CustomizeConfig.PartLevelFractions = {0.2, 0.4, 0.8}
CustomizeConfig.Screen.Parts = "PERFORMANCE & VALUE"
function CustomizeConfig.partCost(baseValue: number, nextLevel: number): number
 return math.max(1, math.round(baseValue * (CustomizeConfig.PartLevelFractions[nextLevel] or 0)))
end

-- === The turntable ==========================================================
--[[ THE WORKSHOP CAR TURNS (2026-10-07, the owner, on the new pad: "can we maybe make the car spin?").
	The workshop podium is a turntable now: the car on it turns slowly about the pad's centre, a soft
	light in the workshop's purple sits under it, a few sparkles drift up off the pad, and a car newly
	put on it arrives in a burst of them. `TurntableController` does it all ON EACH CLIENT — the server
	places the car once and never hears about the turning, so it costs no network at all, and a car
	the server rebuilds (a repaint, a swap) is simply picked up and turned from where it was put.

	`Bays` is which podiums turn, by `SlotIndex`: the workshop alone (0) by default. Adding the
	showroom bays (1..12) turns every car on the lot — handsome, and a cost of one model move per car
	per frame on screen, which `MaxDistance` bounds. `Enabled = false`: still cars, exactly as before. ]]
CustomizeConfig.Turntable = {
	Enabled = true,
	Bays = { [0] = true },
	--- Degrees a second. Slow enough to read the car, fast enough to see it is a turntable.
	DegreesPerSecond = 22,
	--- Studs from the camera past which a car is left still (and its effects idle).
	MaxDistance = 160,
	Light = { Enabled = true, Color = Color3.fromRGB(150, 110, 255), Brightness = 1.6, Range = 14 },
	Sparkle = { Enabled = true, Color = Color3.fromRGB(190, 160, 255), Rate = 4, Arrival = 35 },
}


--- Hide the cash mat in front of the workshop podium: it earns nothing (`GarageService` bay discovery).
CustomizeConfig.HideCollectMat = true

return CustomizeConfig
