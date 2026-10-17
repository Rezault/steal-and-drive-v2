--[[
	BuildComingSoonSigns — Command Runner command

	Redraws the GARAGE / COMING SOON sign on every plot's garage door, out of the `car ui.psd` kit's
	own textures.

	=== WHY IT EXISTS =========================================================

	This sign was authored BY HAND and propagated with the plots, so until now the only way to change
	it was to change eight of them in the Explorer — and it had never been changed, which is why it
	was still the last thing in the game drawn in flat `Color3` fills with a `UICorner` on it. Same
	rebuild the forecourt billboard got on 2026-08-23 and for the same reasons; see
	`assets/ui/upgrades/README.md`.

	Note for anything else on a plot: `BuildDealershipSigns` copied ITS palette from this sign back
	when this sign was the reference ("lifted from the ComingSoonSign, which is itself the car ui.psd
	kit"). That comment is now out of date — this sign wears the kit's ART, the dealership sign still
	wears flat fills. They are the two halves of the same job and only one of them is done.

	=== THE ONE THING THAT MADE IT LOOK WRONG =================================

	`#0066FF` ON A BLUE GARAGE DOOR. The title bar is the kit's brand blue and it was laid straight
	onto `Cube.016`, which is the door mesh and is itself blue. Two blues of similar value touching
	with no border between them read as one smear, and the header stopped being a header. This is the
	exact failure the kit's own theme note warns about: put the message on the navy body and let blue
	be the HEADER, not the background.

	The fix is not to abandon the blue. It is to give the cap something to sit on: the panel texture
	brings a 5px `#151D2D` border and a 5px `#384769` inner rim, the cap is inset inside them, and the
	panel is given an OPAQUE face behind its own texture (see below). The blue then meets navy and
	dark navy on every side instead of meeting the door.

	=== AND THE PART THAT IS NOT ART ==========================================

	Both labels were `TextScaled` in their own boxes, which sizes each string independently: "GARAGE"
	came out at 66px and "COMING SOON" at 86px, and that ratio was an accident of how many characters
	each word has rather than a decision. They are ceilings now, chosen against the cap and the body
	block — see `TYPE`.

	SCOPE: the six live plots, `Workspace.Plot7` (the reference copy) and
	`ServerStorage.PlotUpgrades.PlotMaster` (the template new plots are cut from — miss it and the
	next plot built comes back wearing the old sign). The two dated `PlotSync_Backup_*` folders and
	`Map_OLD_BACKUP` are snapshots and are skipped unless `IncludeBackup` is ticked: a snapshot that
	quietly tracks HEAD is not one.

	IDEMPOTENT. The panel is destroyed and redrawn from scratch every run; the SurfaceGui, the part
	and the door are untouched apart from the gui's own display properties.
]]

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(script.Types)

-- === Scope ==================================================================

local SIGN_NAME = "ComingSoonSign"
local PANEL_NAME = "Panel"

-- Snapshots. Skipped by default; see the header.
local BACKUP_NAMES = { "Map_OLD_BACKUP", "PlotSync_Backup_20260817" }

-- === Look ===================================================================

--[[ `UIAssets`, resolved at Run time — this is a Command Runner script and the registry lives under
	ReplicatedStorage.shared.Configs, which does not exist until Rojo has synced. ]]
local ASSETS: any = nil

local COLOR_TEXT = Color3.new(1, 1, 1)
local COLOR_TEXT_STROKE = Color3.fromRGB(10, 20, 32)

--[[ The kit's face colour, painted behind the panel texture. Every navy surface in `UIAssets` is
	drawn at 80% so gameplay shows faintly through a page you opened — but this is a sign bolted to a
	blue door, and at 80% the door came through it. Same fix the forecourt billboard needed. ]]
local COLOR_PANEL_FACE = Color3.fromRGB(40, 51, 75) -- #28334B

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

--[[ The panel, as fractions of the CANVAS, left exactly where it was authored: centred on the door,
	0.66 of the canvas wide. The height is the one number that moved — 0.34 to 0.3345 — so the box
	matches the texture's own 746x308 and its border comes out the same weight on all four sides
	rather than 2% heavier top and bottom. Nobody will see 2%; it costs nothing to be right. ]]
local PANEL_W = 0.66
local PANEL_H = 0.3345

--[[ Inside the panel, as fractions OF THE PANEL.

	The cap is inset by the texture's own 5px border rather than run edge to edge, which is where the
	mockup puts it on every page and is what keeps the blue off the door. The body block is then
	centred in whatever the cap leaves, so the two do not have to be kept in step by hand. ]]
local CAP = { x = 0.0067, y = 0.0162, w = 0.9866, h = 0.3409 }
local BODY = { y = 0.4110, h = 0.5195 }

--[[ ONE TYPE SCALE, as fractions of the PANEL height, applied as `UITextSizeConstraint` ceilings
	with `TextScaled` left on.

	Same technique the billboard uses and the same reason: a ceiling makes the two lines a decision
	instead of an accident, while still letting a string that genuinely does not fit shrink rather
	than spill — which is the case a fixed `TextSize` would break the moment this is translated.

	DO NOT follow `TextScaled` with a `TextWrapped` write. Assigning `TextWrapped = false` after it
	silently clears `TextScaled`, and the label then renders at the default `TextSize` of 8 with
	nothing anywhere reporting a problem.

	Sized against the longer of the two: "COMING SOON" at the Body ceiling is about 536px against a
	656px content column, so there is room before anything starts shrinking. ]]
local TYPE = {
	Header = 0.2013, -- 62px on the 308 panel
	Body = 0.2727, -- 84px
}

-- === Building ===============================================================

local function image(parent: Instance, name: string, id: number): ImageLabel
	local l = Instance.new("ImageLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Image = ASSETS.url(id)
	-- `Stretch`, no `SliceCenter`: exported at the aspect it is drawn at, so the stretch is identity.
	l.ScaleType = Enum.ScaleType.Stretch
	l.Parent = parent
	return l
end

local function stroke(parent: Instance, thickness: number, transparency: number)
	local s = Instance.new("UIStroke")
	s.Color = COLOR_TEXT_STROKE
	s.Thickness = thickness
	s.Transparency = transparency
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	return s
end

local function label(
	parent: Instance,
	name: string,
	text: string,
	sizeFraction: number,
	panelH: number
): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	-- Plain spaces. `AutoLocalize` is on, so the string written here is the SOURCE string Roblox
	-- captures for translation, and a non-breaking space in it is a key no translation can match.
	l.Text = text
	l.TextColor3 = COLOR_TEXT
	l.FontFace = FONT
	l.TextScaled = true -- see TYPE: do NOT write `TextWrapped` after this
	l.RichText = false

	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = math.max(1, math.round(panelH * sizeFraction))
	cap.Parent = l

	l.Parent = parent
	return l
end

--[[ Redraw one sign. The SurfaceGui is kept and its panel replaced, so nothing that might hold a
	reference to the gui itself is disturbed. ]]
local function buildSign(gui: SurfaceGui)
	local part = gui.Parent :: BasePart

	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0 -- reads the same at night as at noon
	gui.Brightness = 1
	gui.AlwaysOnTop = false
	gui.ZOffset = 0
	gui.MaxDistance = 0 -- never fades; it is meant to be read from the street
	gui.ClipsDescendants = false
	-- Nothing on this sign is pressable and nothing binds it, so it takes no input. A sign that
	-- silently swallows clicks in front of a garage door is a bug waiting to be misdiagnosed.
	gui.Active = false

	local old = gui:FindFirstChild(PANEL_NAME)
	if old then
		old:Destroy()
	end

	-- The canvas is the part's own face, and the panel is a fraction of it. `Face` is left exactly as
	-- authored (Right, on this door) — which face a mesh presents is not this command's business.
	local canvasH = part.Size.Y * gui.PixelsPerStud
	local panelH = canvasH * PANEL_H

	local panel = image(gui, PANEL_NAME, ASSETS.Upgrades.SignPanel)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(PANEL_W, PANEL_H)
	-- Opaque, so the texture composites onto the kit's face colour instead of onto the blue door.
	panel.BackgroundColor3 = COLOR_PANEL_FACE
	panel.BackgroundTransparency = 0

	local cap = image(panel, "TitleBar", ASSETS.SpawnCar.TitleBar)
	cap.Position = UDim2.fromScale(CAP.x, CAP.y)
	cap.Size = UDim2.fromScale(CAP.w, CAP.h)

	local header = label(cap, "Header", "GARAGE", TYPE.Header, panelH)
	header.Position = UDim2.fromScale(0.5, 0.5)
	header.Size = UDim2.fromScale(0.9, 0.62)
	stroke(header, 2, 0.55)

	local body = label(panel, "Body", "COMING SOON", TYPE.Body, panelH)
	body.Position = UDim2.fromScale(0.5, BODY.y + BODY.h / 2)
	body.Size = UDim2.fromScale(0.88, BODY.h)
	-- The one line anybody reads from the street, so it gets the heavier stroke — same weighting the
	-- billboard gives its headline.
	stroke(body, 3, 0.5)
end

--[[ Every `ComingSoonSign` under a root, found by NAME rather than by path: it lives at
	`<plot>/Building/Floor1/Cube.016`, and `Cube.016` is a modeller's mesh name that nothing should
	depend on. Same rule `UpgradeService` follows for the ladder. ]]
local function collect(root: Instance?, into: { SurfaceGui })
	if not root then
		return
	end
	for _, d in root:GetDescendants() do
		if d.Name == SIGN_NAME and d:IsA("SurfaceGui") and d.Parent and d.Parent:IsA("BasePart") then
			table.insert(into, d)
		end
	end
end

return {
	Description = "Redraw the GARAGE / COMING SOON sign on every plot's garage door out of the car ui.psd kit textures. Idempotent.",
	Tags = { "Plots", "UI", "Signage" },
	AutoRecordChanges = true,

	Arguments = {
		IncludeBackup = {
			Type = "boolean",
			Default = false,
			LayoutOrder = 1,
			Description = "Also redraw the signs inside ServerStorage.Map_OLD_BACKUP and PlotSync_Backup_20260817. Those are snapshots and are left alone by default.",
		},
	} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		--[[ The registry is REQUIRED rather than copied, so the sign cannot drift from the ids the
			rest of the kit uses. Edit mode caches a required module, so a `UIAssets` that predates
			`Upgrades.SignPanel` means the Command Runner needs reconnecting — checked for explicitly
			rather than left to fail as a nil index deep inside the draw. ]]
		local shared = ReplicatedStorage:FindFirstChild("shared")
		local configs = shared and shared:FindFirstChild("Configs")
		local module = configs and configs:FindFirstChild("UIAssets")
		local ok, assets = pcall(require, module)
		if not (ok and type(assets) == "table" and assets.Upgrades and assets.Upgrades.SignPanel and assets.SpawnCar) then
			out:error(
				"Could not require ReplicatedStorage.shared.Configs.UIAssets, or it predates UIAssets.Upgrades.SignPanel — is Rojo syncing, and has the Command Runner been reconnected?"
			)
			return
		end
		ASSETS = assets

		local signs: { SurfaceGui } = {}
		local map = workspace:FindFirstChild("Map")
		collect(map and map:FindFirstChild("Plots"), signs)
		collect(workspace:FindFirstChild("Plot7"), signs)
		local store = ServerStorage:FindFirstChild("PlotUpgrades")
		collect(store and store:FindFirstChild("PlotMaster"), signs)

		local skipped = 0
		if arguments.IncludeBackup == true then
			for _, name in BACKUP_NAMES do
				collect(ServerStorage:FindFirstChild(name), signs)
			end
		else
			for _, name in BACKUP_NAMES do
				local backup = ServerStorage:FindFirstChild(name)
				local found: { SurfaceGui } = {}
				collect(backup, found)
				skipped += #found
			end
		end

		if #signs == 0 then
			out:error("No " .. SIGN_NAME .. " found. Expected one per plot at Building/Floor1/<door mesh>.")
			return
		end

		for _, gui in signs do
			buildSign(gui)
		end

		out:print(
			string.format(
				"Redrew %d COMING SOON sign(s) in the kit chassis.%s",
				#signs,
				if skipped > 0 then string.format(" Left %d backup copy/copies alone.", skipped) else ""
			)
		)
	end,
} :: Types.ScriptModule
