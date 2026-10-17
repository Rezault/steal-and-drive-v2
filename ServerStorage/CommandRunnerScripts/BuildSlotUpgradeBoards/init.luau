--[[
	BuildSlotUpgradeBoards — Command Runner command

	Draws the upgrade kiosk onto every podium: the tilted little board standing on each bay's collect
	mat, which sells one level of that bay's income. It rebuilds the SCREEN and re-proportions the
	PART it is drawn on; it never moves the stand, and it never creates a kiosk on a podium that has
	none.

	=== WHY IT EXISTS =========================================================

	The kiosks were authored by hand on 2026-08-01 and propagated with the podiums, so until now the
	only way to change one was to change fifty-four of them in the Explorer. That was survivable
	while the layout was settled. It stopped being survivable on 2026-08-21, when the "Improve
	Upgrade UI" card took the board from six readouts to two.

	=== WHAT THE BOARD SAYS NOW ===============================================

	Two lines and a colour, from the reference art on that card:

	    +---------------------------+
	    |           $1.6B           |   the price of the next level, or MAX
	    |      Lvl 24 > Lvl 25      |   what buying it does
	    +---------------------------+

	THE WHOLE FACE IS THE BUTTON, which is the part that makes it readable at a glance. Its colour is
	`UpgradeConfig.Bay.Colors`, and since 2026-08-26 that says two words: orange while there is a
	level to buy, green once there is not. The balance is not in it, because a press you cannot
	afford opens a cash pack rather than doing nothing. `GarageService._drawKiosk` writes the colour;
	nothing here is live text.

	What came off, and the one thing that cost something to lose, is argued in `UpgradeConfig.Bay`.

	=== IT RESHAPES THE PART, AND HERE IS THE RULE IT FOLLOWS ==================

	Six readouts needed a 3:2 board and two do not — at 3:2 the new screen is mostly margin, and the
	board is the one thing on a podium standing between the camera and the parked car. So the part is
	re-proportioned to `Aspect` (2.25 by default, the reference art's own shape), which at the
	authored 5.4-stud width takes it from 3.6 studs tall to 2.4.

	THE BOTTOM EDGE IS WHAT STAYS PUT, not the centre. The board leans out over the collect mat on a
	post whose top it overlaps by about a third of a stud, and keeping the centre would lift it off
	its own stand. So the height comes off the TOP, along the board's own tilted up-vector:

	    board.CFrame = board.CFrame * CFrame.new(0, -(oldHeight - newHeight) / 2, 0)

	Safe to write directly because all three parts of the stand are `Anchored` with no joint between
	them — checked, and worth re-checking if the stand is ever rebuilt, because setting `CFrame` on a
	welded part drags its whole assembly in edit mode too.

	IT IS DERIVED FROM THE PART'S OWN WIDTH rather than written as a pair of studs, so it survives
	`Model:ScaleTo` — the podiums are at 0.85 — and so re-running is a no-op once the shape is right.

	=== AND IT MAKES THE PART INVISIBLE, WHICH IS THE WHOLE SHAPE OF THE SIGN ===================

	A `Part` cannot have rounded corners and this UI kit rounds everything, so an opaque board is a
	SQUARE SILHOUETTE sticking out past a rounded screen — visible as four lighter corners around the
	rim, and the first thing anybody notices about the sign. Two ways out, and the losing one is worth
	naming: squaring the screen to match the part reads as a television, and throws away both the
	reference art on the card and the roundness every other surface in this game has.

	So the PART goes to `Transparency = 1` and the SCREEN becomes the object. The rounded rim is the
	sign's whole outline, and there is no square anything to disagree with it. This is the shape the
	forecourt billboard has always had (`MapLayout.md` §3.6: an invisible `UpgradeScreen` inside the
	art's own frame) — the difference is only that a kiosk has no art frame to sit in.

	TWO THINGS THAT FALL OUT OF IT, both handled here:

	  • THE BACK NEEDS A PLATE. A `SurfaceGui` draws on one face, so an invisible part with only a
	    front screen is a sign you can see straight through from behind — and the aisle runs both
	    ways. `BackPlate` is the same rounded rim in the same colour with no text on it, at the same
	    radius, so the two outlines cannot disagree at a grazing angle. It is `Active = false`: the
	    front face is the button, and a second pressable surface on the back of it is a bug.
	  • `CastShadow` GOES OFF. Transparency does not stop a part shadowing, so an invisible board
	    lays a hard SQUARE shadow on the mat — the silhouette this whole change exists to get rid of,
	    reappearing on the floor.

	The 0.18 studs between the two faces is the one honest cost, and it is invisible at any angle a
	player stands at; checked head-on, near edge-on from the aisle, and from directly behind.

	=== SCOPE =================================================================

	Every `CarSlot`-tagged model that has an `Upgrade/UpgradeBoard`, wherever it lives: the six live
	plots, `Workspace.Plot7` (the reference copy), and `ServerStorage.PlotUpgrades.Floor2Contents`
	(the stored upstairs deck, cloned in when somebody buys Floor 2 — miss it and half the bays in
	the game keep the old sign). `ServerStorage.Map_OLD_BACKUP` is skipped unless `IncludeBackup` is
	ticked: it is a snapshot, and a snapshot that quietly tracks HEAD is not one.

	IDEMPOTENT. The screen is destroyed and redrawn, the part is re-proportioned from its own width,
	and a second run reports the same counts and changes nothing.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Types = require(script.Types)

-- === Scope ==================================================================

local SLOT_TAG = "CarSlot"
-- Skipped by default. See the header.
local BACKUP_NAME = "Map_OLD_BACKUP"

-- === Geometry ===============================================================

--[[ Width : height of the board part. 2.25 is the reference art's own shape and takes the authored
	5.4 x 3.6 board to 5.4 x 2.4. An argument because it is the one number here worth eyeballing in
	the viewport. ]]
local DEFAULT_ASPECT = 2.25

--[[ Canvas pixels per stud. The authored guis are already `PixelsPerStud` at 100, so this only
	matters for a board that arrives without one; every offset below is derived from the resulting
	canvas rather than assuming it, so changing it re-lays-out cleanly. ]]
local PIXELS_PER_STUD = 100

-- === Palette ================================================================
-- The rim, the text stroke, and nothing else: the button's own colour is the server's to write, and
-- painting a second opinion of it here would be a state the board holds and `_drawKiosk` does not.
local COLOR_RIM = Color3.fromRGB(10, 20, 32) -- #0A1420, the kit's outline navy
local COLOR_TEXT = Color3.fromRGB(255, 255, 255)

--[[ The blank rounded plate on the far face. Named here rather than in `UpgradeConfig.Bay` because
	nothing reads it — it is art, and the config is the contract between the builder and the two
	scripts that WRITE to the sign. Both faces round at `RADIUS_RIM` so their outlines coincide. ]]
local BACK_NAME = "BackPlate"
local RADIUS_RIM = 0.14 -- of the board's height
local RADIUS_FACE = 0.10

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

--[[ The layout, as fractions of the button's own box, top-down. Fractions rather than pixels so the
	`Aspect` argument re-lays-out instead of overflowing.

	The price gets half the height and the level line a little over a quarter, which is the hierarchy
	the reference art draws: the two lines are the same colour and the same font, and SIZE is the
	only thing saying which one to read first. Both are `TextScaled`, so those fractions are ceilings
	rather than sizes — a short "MAX" fills its box and a long "$1.6B" fills the same box. ]]
local RIM = 0.055 -- of the board's height, all round
local PAD_X = 0.06 -- of the button's width
local ROW_COST = { y = 0.08, h = 0.50 }
local ROW_LEVEL = { y = 0.62, h = 0.28 }

-- === Small builders =========================================================

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	return s
end

--[[ One of the two lines.

	THE PLACEHOLDER TEXT IS A REAL-LOOKING VALUE, not an empty string, because this board is drawn
	blank on every plot nobody owns and an empty one in the Explorer is indistinguishable from a
	broken one. `GarageService` overwrites both the moment a plot is claimed.

	Every space is a non-breaking one (`UpgradeConfig.oneLine`) for the reason that function exists:
	`TextScaled` would rather wrap "Lvl 24 > Lvl 25" onto three lines than shrink it. ]]
local function line(parent: Instance, name: string, text: string, box: { y: number, h: number }, oneLine: (string) -> string): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.fromScale(0.5, box.y)
	l.Size = UDim2.fromScale(1 - 2 * PAD_X, box.h)
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Text = oneLine(text)
	l.TextColor3 = COLOR_TEXT
	l.FontFace = FONT
	l.TextScaled = true
	l.RichText = false
	l.Parent = parent
	return l
end

--[[ Draw one board's screen, from scratch every time.

	DESTROYED AND REBUILT RATHER THAN PATCHED, which is the only way this stays idempotent across a
	layout change: the boards in the map are three generations of hand-editing deep, and a patch
	would have to know every shape they have ever been in. The gui is the only thing removed — the
	part, its stand and its place in the world are untouched. ]]
local function buildGui(board: BasePart, config: any)
	local names = config.Bay
	local oneLine = config.oneLine

	for _, name in { names.GuiName, BACK_NAME } do
		local old = board:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = names.GuiName
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.ResetOnSpawn = false
	gui.ClipsDescendants = false
	--[[ THE ONE PROPERTY THAT DECIDES WHETHER ANY OF THIS IS PRESSABLE. A SurfaceGui takes input only
		while it is `Active`, and a board without it is dead in a way that looks exactly like a
		controller that never bound. `UpgradeController` carries the same warning at the other end. ]]
	gui.Active = true
	gui.Parent = board

	local height = math.round(board.Size.Y * PIXELS_PER_STUD)
	local rim = math.max(2, math.round(height * RIM))

	--[[ The Panel is the dark rim and nothing else — no title bar, no rows, no children but the
		button. It stays a Frame, and stays named `Panel`, because `UpgradeController` and
		`GarageService` both walk `... > Panel > UpgradeButton` and neither should have to care that
		the panel stopped holding anything of its own. ]]
	local panel = Instance.new("Frame")
	panel.Name = names.PanelName
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = COLOR_RIM
	panel.BorderSizePixel = 0
	panel.Parent = gui
	corner(panel, math.round(height * RADIUS_RIM))

	local button = Instance.new("TextButton")
	button.Name = names.ButtonName
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.5)
	button.Size = UDim2.new(1, -2 * rim, 1, -2 * rim)
	-- A real state colour rather than a placeholder: an unclaimed plot's board is drawn `Vacant` and
	-- a claimed one is repainted before anybody has looked at it. The KIOSK's palette and not the
	-- billboard's. See `UpgradeConfig.Bay.Colors` for why those are two tables.
	button.BackgroundColor3 = names.Colors.Buy
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = true
	button.Parent = panel
	corner(button, math.round(height * RADIUS_FACE))

	--[[ The price, and the only thing on this board somebody reads from across the showroom. Its
		stroke is heavier than the level line's for the same reason its box is taller: on a sign this
		small, size and contrast are the whole of the hierarchy. ]]
	local cost = line(button, names.CostName, "$250", ROW_COST, oneLine)
	stroke(cost, COLOR_RIM, math.max(2, math.round(height * 0.022)), 0.25)

	local level = line(button, names.LevelName, string.format(names.LevelFormat, 1, 2), ROW_LEVEL, oneLine)
	stroke(level, COLOR_RIM, math.max(1, math.round(height * 0.013)), 0.35)

	--[[ The far face: the same rounded rim, nothing on it. See the header — the part is invisible, so
		without this the sign is see-through from behind, and the aisle runs both ways.

		`Active` is false and stays false. The front face is the button; a second pressable surface on
		the back of the same part is a press that fires the remote from somewhere nobody is looking. ]]
	local back = Instance.new("SurfaceGui")
	back.Name = BACK_NAME
	back.Face = Enum.NormalId.Back
	back.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	back.PixelsPerStud = PIXELS_PER_STUD
	back.ResetOnSpawn = false
	back.Active = false
	back.Parent = board

	local plate = Instance.new("Frame")
	plate.Name = names.PanelName
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = COLOR_RIM
	plate.BorderSizePixel = 0
	plate.Parent = back
	corner(plate, math.round(height * RADIUS_RIM))
end

--[[ Everything done to the PART: re-proportion it to `aspect` taking the difference off the TOP, and
	take it out of the picture so the rounded screen is the sign's only outline. Returns whether the
	shape moved — the two visibility properties are idempotent writes and not worth reporting.

	See the header for why the bottom edge is the fixed one, why the part is invisible, and why
	`CastShadow` has to go with it. The 0.01-stud deadband is what makes a second run a no-op rather
	than a shower of sub-micron CFrame writes that the change recorder would dutifully log as a diff.

	`CanQuery` IS DELIBERATELY LEFT ALONE. A `SurfaceGui` takes a click only where the mouse ray hits
	the part under it, so an invisible board still has to be queryable — turning it off here would
	make every kiosk in the game unpressable in a way that looks exactly like an unbound controller. ]]
local function reshape(board: BasePart, aspect: number): boolean
	board.Transparency = 1
	board.CastShadow = false

	local wanted = board.Size.X / aspect
	local delta = board.Size.Y - wanted
	if math.abs(delta) < 0.01 then
		return false
	end
	board.Size = Vector3.new(board.Size.X, wanted, board.Size.Z)
	board.CFrame = board.CFrame * CFrame.new(0, -delta / 2, 0)
	return true
end

-- Every tagged podium worth touching, and a count of the two reasons one was not.
local function boards(includeBackup: boolean): ({ BasePart }, number, number)
	local found: { BasePart } = {}
	local skippedBackup, noKiosk = 0, 0

	local backup = ServerStorage:FindFirstChild(BACKUP_NAME)
	for _, slot in CollectionService:GetTagged(SLOT_TAG) do
		if backup and not includeBackup and slot:IsDescendantOf(backup) then
			skippedBackup += 1
			continue
		end
		local model = slot:FindFirstChild("Upgrade")
		local board = model and model:FindFirstChild("UpgradeBoard")
		if board and board:IsA("BasePart") then
			table.insert(found, board)
		else
			noKiosk += 1
		end
	end
	return found, skippedBackup, noKiosk
end

return {
	AutoRecordChanges = true,
	Description = "Redraw the two-line upgrade kiosk on every bay's podium and re-proportion the board it is drawn on. Idempotent — re-run after any change to UpgradeConfig.Bay's name contract.",
	Tags = { "Plots", "UI", "Garage" },
	Arguments = {
		Aspect = {
			Type = "number",
			Default = DEFAULT_ASPECT,
			LayoutOrder = 1,
			Description = "Width : height of the board part. 2.25 is the reference art's shape and takes the authored 5.4-stud board to 2.4 tall. Lower is taller and covers more of the parked car; the height comes off the top, so the stand stays where it is either way.",
		},
		IncludeBackup = {
			Type = "boolean",
			Default = false,
			LayoutOrder = 2,
			Description = "Also rebuild the 36 podiums inside ServerStorage.Map_OLD_BACKUP. Off, because a snapshot that tracks HEAD is not a snapshot.",
		},
		DryRun = {
			Type = "boolean",
			Default = false,
			LayoutOrder = 3,
			Description = "Report what would be rebuilt and touch nothing.",
		},
	} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		--[[ REQUIRED, not copied. There are seven instance names and a format string here, and a
			board that disagrees with `UpgradeConfig` about any one of them is a label the service
			silently never writes to. The cost is edit mode's require cache: change `UpgradeConfig`
			and the Command Runner has to be reconnected before this sees it. ]]
		local shared = ReplicatedStorage:FindFirstChild("shared")
		local configs = shared and shared:FindFirstChild("Configs")
		local module = configs and configs:FindFirstChild("UpgradeConfig")
		local ok, config = pcall(require, module)
		if
			not (
				ok
				and type(config) == "table"
				and type(config.Bay) == "table"
				and config.Bay.CostName
				and type(config.Bay.Colors) == "table"
			)
		then
			out:error("Could not require ReplicatedStorage.shared.Configs.UpgradeConfig, or it predates the two-line kiosk (no Bay.CostName / Bay.Colors). Is Rojo syncing? Reconnect the Command Runner after a config change.")
			return
		end

		local aspect = if type(arguments.Aspect) == "number" and arguments.Aspect > 0 then arguments.Aspect else DEFAULT_ASPECT
		local dry = arguments.DryRun == true

		local found, skippedBackup, noKiosk = boards(arguments.IncludeBackup == true)
		if #found == 0 then
			out:error(string.format("No podium carries an Upgrade/UpgradeBoard (%d tagged slots had none). Nothing to draw on.", noKiosk))
			return
		end

		if dry then
			out:print(string.format("DRY RUN — would redraw %d board(s) at aspect %.2f.", #found, aspect))
		else
			local reshaped = 0
			for _, board in found do
				if reshape(board, aspect) then
					reshaped += 1
				end
				buildGui(board, config)
			end
			out:print(string.format("Redrew %d kiosk(s); %d board(s) re-proportioned to %.2f.", #found, reshaped, aspect))
		end

		if skippedBackup > 0 then
			out:print(string.format("Skipped %d podium(s) in ServerStorage.%s — tick IncludeBackup to take them too.", skippedBackup, BACKUP_NAME))
		end
		if noKiosk > 0 then
			out:warn(string.format("%d tagged slot(s) have no Upgrade/UpgradeBoard and were left alone. That is expected for copies made before the kiosks existed; a LIVE bay with no sign just has no ladder to show.", noKiosk))
		end
	end,
} :: Types.ScriptModule
