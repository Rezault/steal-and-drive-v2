--[[
	BuildPlotUpgradeSigns — Command Runner command

	Stands a billboard on the forecourt of every dealership plot and draws the dealership upgrade
	screen onto it: a 2 x 2 grid with one upgrade in each corner.

	`UpgradeService` never builds this. It writes text, a bar width and a button colour into the
	instances below and nothing else — the same split the dealership sign, the collect mats and the
	race pads all make, because nothing on a hot path should be constructing UI it could instead be
	filling in. `UpgradeConfig.Board` is the half of the contract the code reads and this file is the
	half that authors it; they are required from the same module here specifically so the four
	upgrade names and the instance names cannot drift apart.

	=== TWO FACES ON ONE PLATE (2026-09-17) ==================================================

	Redrawn off Dylan's mockup: a header with a picture, the title and a line of copy, and four
	cards that each carry a picture on the left, the copy on the right, a segmented level bar and a
	wide UPGRADE button with the price on it. He asked for it twice, once per UI:

	  * `UpgradeGui`, the CLASSIC face, built from the `car ui.psd` kit the board has always worn:
	    the navy panel and tile textures, the orange pill, the bar track and fill, Ubuntu Bold.
	  * `UpgradeGuiKit`, the KIT face, built from the Cartoony Kit's own Upgrades frame, CLONED out of
	    `NewUIConfig.TemplatePath` rather than imitated: its blue panel, white well, gradient cards,
	    lit pips and yellow-to-green button, Fredoka One.

	Both go on the same plate with the same instance names, so the service draws them with one loop.
	The classic face is authored enabled and the kit face disabled; `UpgradeController` flips them on
	each client from `NewUIConfig.KitUpgradeBoards`. A place without the kit template still gets a
	working classic board and a warning.

	=== THE SIGN IS NOT NEW ART ==============================================================

	It is lifted out of `Workspace.Worlds.FuturisticCity` — the SignNeons prop pack the modeller
	handed over with the themed road passes. There are three sizes in that pack and this takes the
	SQUARE one (about 27 x 27 studs), because a 2 x 2 grid wants a square and the other two are
	letterbox. It arrives complete with its own legs, so nothing here builds a stand.

	IT IS THEN STRETCHED WIDER, since 2026-09-17 (`Stretch`, 1.18 by default). Picture-left cards
	need the width a square board does not have, and the mockup is about 1.4:1 where the square sign's
	aperture is 1.19:1. The stretch is along the frame's own X only, so the bezel and the legs come out
	18% heavier across and nothing else about the sign changes; the height, and so where it stands,
	is exactly what `Width` always gave.

	A PRISTINE COPY IS STORED at `ServerStorage.PlotUpgrades.UpgradeSign` on the first run and every
	later run uses that. The world tiles are a greybox that WILL be replaced (see `WorldConfig`'s
	note on the maps), and a plot sign that silently changes shape the day a themed road is re-imported
	is a bad afternoon. Pass `Restock` to deliberately re-capture it.

	=== WHERE IT GOES ========================================================================

	Plot-local (3, -47) — the street-side edge of the forecourt, backed onto the planter row.

	It used to stand at (22, -2), out in the middle of the parking apron where it was in frame the
	instant you spawned. That framing was the one thing it had going for it and it cost the lot its
	whole middle, so it was moved to the perimeter. What the new spot is measured against:

	  * IT IS OFF THE APRON. The forecourt slab runs local Z -49.5 .. +13 and the six podiums line
	    its far side (Z +38, X -40..+18, plus X -43). At Z -47 the board is against the slab's
	    street-side lip: nothing to drive round, and it occludes no bay from anywhere in the lot.
	  * IT SITS IN FRONT OF THE PLANTERS, NOT BETWEEN THEM. The two big palm planters are at local
	    X -7.9 and +14.4, Z -53.8, pots 10.7 wide, with an 11.6-stud gap between them that the board
	    never fit through. So it stands in FRONT of both, centred on their midpoint (X 3.25,
	    rounded to 3), with its back face 2.1 studs clear of the pot fronts at Z -49.75. The palms
	    and the frontage railing at Z -59.5 read as its backdrop. At 20 studs wide it spans local
	    X -7 .. +13, still inside the two pots' outer edges.
	  * IT IS NO LONGER IN FRAME ON ARRIVAL. `PlotSpawn` is at local (0, -30) facing +Z into the
	    showroom, so the board is now BEHIND you when you land. Deliberate, and the trade the move
	    was worth making; the sign still turns toward the spawn (see the lookAt below), so it reads
	    head-on the moment you turn round.
	  * IT IS SQUARE TO THE PLOT, NOT AIMED. The bearing to the spawn is 10 degrees off local +Z from
	    here, which skewed it against the slab edge and the planter row; the lookAt now rounds that
	    bearing to a quarter turn, so the board faces local +Z exactly.

	⚠️ IT NOW OVERLAPS THE RACE PAD'S HALO. `BuildPlotRacePads` puts the entry trigger at local
	(0, -52) with a 12-stud pad and a +6-stud touch halo — X -9..+9, Z -61..-43 — and (3, -47) is
	inside that. No plot carries a pad today (the only `EnterRace` part in the place is
	`Workspace.EnterRacePart`), but building the per-plot pads at the
	default Z would mean walking up to press UPGRADE starts a race. Move one or the other first. The
	board's own parts carry `CanTouch = false`, so it never triggers anything itself.

	The GROUND IS RAYCAST, NEVER ASSUMED — same rule as `PlotService._resolveSpawn` and
	`BuildPlotRacePads`, and for the same reason: deck heights in this map are derived from the floor
	mesh, and a hardcoded Y is the one number that silently breaks if the slab ever moves.

	=== THE ONE MEASUREMENT THAT MATTERS =====================================================

	`CanQuery` is switched OFF on the sign's two meshes and the screen plate sits in FRONT of them,
	and that is not tidiness — it is the difference between a board you can click and one you cannot.

	Both meshes are `CollisionFidelity.Default`, so what a ray hits is a convex decomposition and not
	the visible geometry. Probed at 0.5-stud steps across the face, that hull juts into the aperture
	asymmetrically: the neon is reachable out to x +6.5 at y -1 and only to x +4.5 at y +1, for a
	frame that is visually symmetrical. A SurfaceGui parked inside the recess would therefore have a
	dead patch in its top-right tile that nothing in the layout explains. So the canvas goes 0.03
	studs proud of the frame's front face, where nothing can be in front of it, and the meshes stop
	answering queries at all.

	The plate is sized from the NEON PART'S BOX x 0.98 — measured to land inside the visible aperture
	with an even bezel. Do not "fix" that to the raycast aperture; see the note above about which of
	the two is the real geometry.

	IDEMPOTENT. An existing `UpgradeSign` is destroyed and rebuilt rather than patched: the whole
	model is generated, nothing in the place holds a reference to it between runs, and a half-updated
	board is worse than none.
]]

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(script.Types)

-- === The map contract =======================================================

local PLOTS_PATH = { "Map", "Plots" }
local ORIGIN_NAME = "Origin"
local SPAWN_NAME = "PlotSpawn" -- PlotConfig.SpawnName

-- Where the pristine sign is kept, beside the Floor 2 template the same upgrade board sells.
local STORE_FOLDER = "PlotUpgrades"
local STORE_NAME = "UpgradeSign"

-- Where it is quarried from the first time. `SignNeons` holds 22 signs in three sizes.
local WORLDS_FOLDER = "Worlds"
local SOURCE_WORLD = "FuturisticCity"
local SOURCE_PROPS = "Props"
local SOURCE_PACK = "SignNeons"

-- The Cartoony Kit frame the kit face is cloned from, under `NewUIConfig.TemplatePath`.
local KIT_FRAME = "UpgradesUI"

-- === Geometry ===============================================================

-- Plot-local placement. Both are arguments; these are the defaults the header justifies.
local DEFAULT_LOCAL_X = 3
local DEFAULT_LOCAL_Z = -47

--[[ Studs across the sign's frame BEFORE the stretch below. 17 puts the screen at 12.96 studs tall,
	which is a canvas 1296 px high at 100 px/stud: the same pixels-per-stud the per-bay kiosks use,
	so text on the two is the same physical size and the board reads as the big brother of the
	little ones.

	The pack's own scale is about 1.56 and is NOT 1, so this is applied as a ratio against the
	measured bounding box rather than by setting `Scale` to a number. ]]
local DEFAULT_WIDTH = 17

--[[ How much wider than its own proportions the sign is drawn, along the frame's X only. 1.18 takes
	the frame from 17 to 20 studs and the screen from 1.19:1 to 1.41:1, which is the mockup's shape. ]]
local DEFAULT_STRETCH = 1.18

-- Where the ground probe starts and ends, in plot-local Y. Above the forecourt slab (~1.4) and
-- under the dropped roof (~28), same window `BuildPlotRacePads` uses.
local PROBE_TOP = 8
local PROBE_DROP = 24

-- Plate: fraction of the neon part's own box, and how far in front of the frame's face it sits.
local SCREEN_INSET = 0.98
local SCREEN_PROUD = 0.03
local SCREEN_THICKNESS = 0.06

-- === Look ===================================================================

--[[ `UIAssets` and the kit's Upgrades frame, resolved at Run time for the same reason `UpgradeConfig`
	is: this is a Command Runner script, and the configs live under ReplicatedStorage.shared.Configs,
	which does not exist until Rojo has synced. `Run` sets both before it builds anything. `KIT` may
	stay nil, and then only the classic face is built. ]]
local ASSETS: any = nil
local KIT: Instance? = nil

-- The sign's neon MESH, which is a part property and not part of any texture.
local COLOR_ACCENT = Color3.fromRGB(0, 102, 255) -- #0066FF

-- Classic face, the `car ui.psd` palette.
local COLOR_TEXT = Color3.new(1, 1, 1)
local COLOR_TEXT_STROKE = Color3.fromRGB(21, 29, 45) -- #151D2D, the kit's outline navy
local COLOR_COPY = Color3.fromRGB(142, 192, 255) -- the mockup's light blue line of copy
local COLOR_LEVEL = Color3.fromRGB(214, 226, 250)
local COLOR_TICK = Color3.fromRGB(21, 29, 45)
local COLOR_BAR_RIM = Color3.fromRGB(88, 106, 150)
--[[ The kit's face colour, sampled off the artist's own panel. Painted behind the panel texture so
	the 80% art has something to sit on other than the neon; see `buildClassic`. ]]
local COLOR_PANEL_FACE = Color3.fromRGB(40, 51, 75) -- #28334B
-- The title's top-to-bottom shade, white into the mockup's pale blue.
local COLOR_TITLE_LOW = Color3.fromRGB(160, 205, 255)

-- Kit face.
local COLOR_KIT_STROKE = Color3.fromHex("021e38")

local FONT_CLASSIC = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)
local FONT_KIT = Font.new("rbxasset://fonts/families/FredokaOne.json")

-- 100 px per stud, matching the per-bay kiosks, so text on the two is the same physical size.
local PIXELS_PER_STUD = 100

--[[ THE LAYOUT IS WRITTEN IN PIXELS ON A REFERENCE CANVAS, and converted to scale when it is
	applied, so the numbers below can be read against a screenshot and a board built at another
	`Width` or `Stretch` still re-lays-out rather than overflowing. `CANVAS` is what the defaults
	produce: an 18.22 x 12.96 stud plate at 100 px/stud. Type ceilings are pixels on the same canvas
	and are scaled by the real canvas height. ]]
local CANVAS = Vector2.new(1822, 1296)

-- A card, on the classic face's grid. The kit face's cards are within 1% of this shape and reuse it.
local TILE = Vector2.new(873, 494)

--[[ One card, top to bottom, in TILE pixels. The picture takes the left third; everything else is a
	right-hand column. A one-level upgrade (EXPAND BASE) has no ladder, so it has no `Level` and no
	bar and its headline and copy sit lower, the way the mockup's fourth card does. ]]
local CARD = {
	Icon = { 20, 34, 224, 262 },
	Title = { 264, 18, 586, 64 },
	Headline = { 264, 78, 586, 106 },
	Detail = { 264, 182, 586, 52 },
	Level = { 264, 232, 586, 44 },
	Bar = { 264, 280, 566, 30 },
	-- One-level cards.
	SingleHeadline = { 264, 92, 586, 124 },
	SingleDetail = { 264, 220, 586, 56 },
}

--[[ Where the button's bottom edge sits above the card's, in TILE pixels, and how wide the classic
	pill is. The pill's height follows from its own 3.89:1. ]]
local BUTTON_MARGIN = 22
local PILL_WIDTH = 560

-- Type ceilings, in CANVAS pixels. One scale per row across all four cards, so the four read as the
-- same object. See `label` for why it is a ceiling and not a size.
local TYPE = {
	Title = 104,
	Subtitle = 44,
	Owner = 50,
	TileTitle = 58,
	Headline = 104,
	SingleHeadline = 112,
	Detail = 46,
	Level = 40,
	Button = 58,
}

-- === Building: shared =======================================================

local function clearChildren(instance: Instance)
	for _, child in ipairs(instance:GetChildren()) do
		child:Destroy()
	end
end

-- Position and size a GuiObject from a pixel box measured against `ref`.
local function box(inst: GuiObject, ref: Vector2, rect: { number })
	inst.Position = UDim2.fromScale(rect[1] / ref.X, rect[2] / ref.Y)
	inst.Size = UDim2.fromScale(rect[3] / ref.X, rect[4] / ref.Y)
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	return s
end

--[[ An `ImageLabel` wearing one of the kit's textures. `Stretch` unless the caller slices it. ]]
local function image(parent: Instance, name: string, id: number): ImageLabel
	local l = Instance.new("ImageLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Image = ASSETS.url(id)
	l.ScaleType = Enum.ScaleType.Stretch
	l.Parent = parent
	return l
end

--[[ A picture that keeps its own proportions inside its box. ]]
local function picture(parent: Instance, name: string, id: number): ImageLabel
	local l = image(parent, name, id)
	l.ScaleType = Enum.ScaleType.Fit
	return l
end

--[[ 9-slice a texture so its drawn border keeps its drawn weight at any aspect.

	`SliceScale` is what makes this safe where `UIAssets` warns slicing is not: the corners are drawn
	at `scale` texture pixels per canvas pixel, so a texture rendered 1.5x bigger keeps a border 1.5x
	thicker, exactly as a uniform stretch would draw it. Only the middle band changes shape, and on the
	two navy textures that band is the kit's weave, which measures about 2 units of luma cell to cell
	(40,51,75 against 38,48,72): stretching it is not visible at any distance. The pill's checker is
	nothing like that faint, which is why the pill is never sliced. ]]
local function slice(l: ImageLabel, inset: number, texture: Vector2, scale: number)
	l.ScaleType = Enum.ScaleType.Slice
	l.SliceCenter = Rect.new(inset, inset, texture.X - inset, texture.Y - inset)
	l.SliceScale = scale
end

--[[ Every label on the board comes through here.

	ONE CEILING, NOT ONE SIZE PER BOX. Applied as a `UITextSizeConstraint` CEILING with `TextScaled`
	left ON: every string the game ships fits its box at the ceiling, so all four cards render their
	rows at identical sizes, and a string that does NOT fit (a translation into a longer language)
	still shrinks rather than spilling out.

	NO NON-BREAKING SPACES. `AutoLocalize` is on, so a string laced with U+00A0 is captured for
	translation as something no translation will ever match. The ceiling is what stops `TextScaled`
	wrapping instead, so there is nothing to defend against.

	AND `TextWrapped` IS NOT TOUCHED, WHICH IS LOAD-BEARING. `TextScaled` implies `TextWrapped`, and
	assigning `TextWrapped = false` AFTER it silently clears `TextScaled` back to false — the label
	then renders at the default `TextSize` of 8 and nothing anywhere reports a problem. ]]
local function label(
	parent: Instance,
	name: string,
	text: string,
	font: Font,
	color: Color3,
	capPx: number,
	canvasScale: number
): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Text = text
	l.TextColor3 = color
	l.FontFace = font
	l.TextScaled = true -- see the note above: do NOT follow this with a `TextWrapped` write
	l.RichText = false
	l.TextXAlignment = Enum.TextXAlignment.Left

	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = math.max(1, math.round(capPx * canvasScale))
	cap.Parent = l

	l.Parent = parent
	return l
end

-- "DEALERSHIP UPGRADES" -> "Dealership Upgrades", the way the kit sets its titles.
local function titleCase(text: string): string
	return (string.gsub(string.lower(text), "(%a)([%w']*)", function(first, rest)
		return string.upper(first) .. rest
	end))
end

-- "UPGRADE YOUR DEALERSHIP..." -> "Upgrade your dealership...".
local function sentenceCase(text: string): string
	local lower = string.lower(text)
	return string.upper(string.sub(lower, 1, 1)) .. string.sub(lower, 2)
end

--[[ The caption set every button carries, whatever it is drawn in: UPGRADE on the left, the cash
	note and the price on the right, and `Status` across the middle for the one word a finished
	ladder says. `UpgradeService` decides which half is showing. `layout` is in fractions of the
	button, because the two faces' buttons are different shapes. ]]
local function captions(button: GuiObject, names: any, font: Font, color: Color3, capPx: number, canvasScale: number, layout: any)
	local action = label(button, names.ButtonActionName, names.BuyText, font, color, capPx, canvasScale)
	action.Position = UDim2.fromScale(layout.Action[1], layout.Action[2])
	action.Size = UDim2.fromScale(layout.Action[3], layout.Action[4])

	local cash = picture(button, names.ButtonCashIconName, ASSETS.Page.CashIcon)
	cash.Position = UDim2.fromScale(layout.Cash[1], layout.Cash[2])
	cash.Size = UDim2.fromScale(layout.Cash[3], layout.Cash[4])

	local cost = label(button, names.ButtonCostName, "", font, color, capPx, canvasScale)
	cost.Position = UDim2.fromScale(layout.Cost[1], layout.Cost[2])
	cost.Size = UDim2.fromScale(layout.Cost[3], layout.Cost[4])

	local status = label(button, names.ButtonStatusName, "", font, color, capPx, canvasScale)
	status.Position = UDim2.fromScale(layout.Action[1], layout.Action[2])
	status.Size = UDim2.fromScale(1 - 2 * layout.Action[1], layout.Action[4])
	status.TextXAlignment = Enum.TextXAlignment.Center

	return action, cost, status
end

-- A fresh SurfaceGui for one face, replacing any older one of the same name.
local function surface(part: BasePart, name: string, style: string, config: any, enabled: boolean): SurfaceGui
	local existing = part:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0 -- reads the same at night as at noon
	gui.Brightness = 1
	gui.AlwaysOnTop = false
	gui.ZOffset = 0
	gui.MaxDistance = 0 -- never fades; it is a billboard, meant to be read from the road
	gui.ClipsDescendants = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	--[[ `Active` is the single property that decides whether any of the four buttons can ever be
		pressed: a SurfaceGui takes input only while it is set. If a playtest finds dead buttons,
		check it (and the plate's `CanQuery`) before anything else. ]]
	gui.Active = true
	gui.Enabled = enabled
	gui:SetAttribute(config.Board.StyleAttribute, style)
	gui.Parent = part
	return gui
end

-- === Building: the classic face =============================================

--[[ The card's grid slot, as a fraction of the grid, for card `index` in `Order`. ]]
local function gridSlot(index: number, gapX: number, gapY: number): (UDim2, UDim2)
	local tileW = (1 - gapX) / 2
	local tileH = (1 - gapY) / 2
	local col = (index - 1) % 2
	local row = math.floor((index - 1) / 2)
	return UDim2.fromScale(col * (tileW + gapX), row * (tileH + gapY)), UDim2.fromScale(tileW, tileH)
end

--[[ One upgrade on the classic face.

	THE BUTTON IS THE KIT'S PILL AT THE PILL'S OWN 3.89:1, and so it is not full width the way the
	mockup's is. The pill's checker is drawn ROTATED about five degrees and at full strength, so any
	aspect other than its own shears the squares visibly, and 9-slicing it is the bug `UIAssets`
	documents at length. A centred pill as wide as the copy column is the closest the classic art
	gets to that button without new art. The kit face, whose buttons are frames, is full width. ]]
local function buildClassicTile(grid: GuiObject, key: string, spec: any, config: any, index: number, canvasScale: number)
	local names = config.Board
	local single = spec.MaxLevel <= 1

	-- The grid's gaps, as fractions OF THE GRID FRAME: the tiles are its children.
	local tile = image(grid, key, ASSETS.Upgrades.Tile)
	tile.Position, tile.Size = gridSlot(index, 24 / 1770, 24 / 1012)
	-- The tile texture is 720x508 with a 4px border and 5px rim; a card is ~873x494, near 1:1.
	slice(tile, 12, ASSETS.UpgradesSize.Tile, 1)
	tile:SetAttribute(names.KeyAttribute, key)

	local iconId = ASSETS.Upgrades.Icons and ASSETS.Upgrades.Icons[key]
	if iconId then
		local icon = picture(tile, names.TileIconName, iconId)
		box(icon, TILE, CARD.Icon)
	end

	local title = label(tile, names.TileTitleName, spec.Title, FONT_CLASSIC, COLOR_TEXT, TYPE.TileTitle, canvasScale)
	box(title, TILE, CARD.Title)

	-- The big number, and the one thing on the card a player reads from the road.
	local headline =
		label(tile, names.TileHeadlineName, spec.Headline(0), FONT_CLASSIC, COLOR_TEXT, if single then TYPE.SingleHeadline else TYPE.Headline, canvasScale)
	box(headline, TILE, if single then CARD.SingleHeadline else CARD.Headline)
	stroke(headline, COLOR_TEXT_STROKE, 4, 0.35)

	local detail = label(tile, names.TileDetailName, spec.Detail, FONT_CLASSIC, COLOR_COPY, TYPE.Detail, canvasScale)
	box(detail, TILE, if single then CARD.SingleDetail else CARD.Detail)

	if not single then
		local level = label(
			tile,
			names.TileLevelName,
			string.format(names.LevelFormat, 0, spec.MaxLevel),
			FONT_CLASSIC,
			COLOR_LEVEL,
			TYPE.Level,
			canvasScale
		)
		box(level, TILE, CARD.Level)

		--[[ The kit's own progress bar, sliced so its rounded ends survive a bar ~18:1, and cut
			into one segment per level by dark ticks laid over it. The fill keeps its name and its
			`Size` contract: `UpgradeService` writes `UDim2.new(level / max, 0, 1, 0)` into it. ]]
		local barPx = CARD.Bar[4] * canvasScale
		local bar = image(tile, names.TileBarName, ASSETS.Page.Bar.Track)
		box(bar, TILE, CARD.Bar)
		slice(bar, ASSETS.Slice.BarTrack, ASSETS.Size.BarTrack, barPx / ASSETS.Size.BarTrack.Y)
		--[[ A pale rim round the track. The kit draws it `#232735` inside `#151D2D`, which is a recess on
			a page and very nearly nothing on this card's `#28334B`: an empty ladder read as no bar at
			all. The rim is the kit's own `#384769` inner-rim colour, lifted. ]]
		local barCorner = Instance.new("UICorner")
		barCorner.CornerRadius = UDim.new(0.5, 0)
		barCorner.Parent = bar
		stroke(bar, COLOR_BAR_RIM, math.max(2, math.round(3 * canvasScale)), 0)

		local fill = image(bar, names.TileFillName, ASSETS.Page.Bar.FillBlue)
		fill.Position = UDim2.fromScale(0, 0)
		fill.Size = UDim2.fromScale(0, 1) -- level 0; the service rewrites this immediately
		slice(fill, ASSETS.Slice.BarFill, ASSETS.Size.BarFill, barPx / ASSETS.Size.BarFill.Y)
		fill.ZIndex = 2

		for rung = 1, spec.MaxLevel - 1 do
			local tick = Instance.new("Frame")
			tick.Name = "Tick"
			tick.AnchorPoint = Vector2.new(0.5, 0)
			tick.Position = UDim2.fromScale(rung / spec.MaxLevel, 0)
			tick.Size = UDim2.new(0, math.max(2, math.round(4 * canvasScale)), 1, 0)
			tick.BackgroundColor3 = COLOR_TICK
			tick.BorderSizePixel = 0
			tick.ZIndex = 3
			tick.Parent = bar
		end
	end

	--[[ The UPGRADE button: the only control on the card. `AutoButtonColor` is OFF because it
		multiplies a grey tint over `.Image` on press, which fights `PressedImage` and muddies the
		artist's gloss. The pill draws its own three states. Centre-anchored so
		`UpgradeController._press` shrinks it into its middle. ]]
	local pillW = PILL_WIDTH
	local pillH = pillW * ASSETS.Size.Pill.Y / ASSETS.Size.Pill.X
	local bottom = TILE.Y - BUTTON_MARGIN
	local button = Instance.new("ImageButton")
	button.Name = names.ButtonName
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, (bottom - pillH / 2) / TILE.Y)
	button.Size = UDim2.fromScale(pillW / TILE.X, pillH / TILE.Y)
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.ScaleType = Enum.ScaleType.Stretch
	button.AutoButtonColor = false

	local pill = ASSETS.Pill[config.ButtonPills.Buy]
	button.Image = ASSETS.url(pill.Idle)
	button.HoverImage = ASSETS.url(pill.Hover)
	button.PressedImage = ASSETS.url(pill.Pressed)
	button.Parent = tile

	--[[ Caption colour belongs to the button's STATE (`UpgradeConfig.ButtonTextColors`): orange and
		silver are too light for white. Authored in the buyable one so the first redraw agrees. The
		pill's darker bottom lip is why the captions sit a little above centre. ]]
	local caption = (config.ButtonTextColors and config.ButtonTextColors.Buy) or COLOR_TEXT
	captions(button, names, FONT_CLASSIC, caption, TYPE.Button, canvasScale, {
		Action = { 0.07, 0.15, 0.40, 0.62 },
		Cash = { 0.49, 0.22, 0.16, 0.48 },
		Cost = { 0.66, 0.15, 0.29, 0.62 },
	})
end

--[[ The classic face: the navy kit panel, a header with the car and the title, and the four cards.

	THE PANEL IS GIVEN AN OPAQUE BACKGROUND. Every navy surface in `UIAssets` is drawn at 80% so
	gameplay shows faintly through a page you opened. This is a world sign bolted to a NEON MESH the
	builder tints `#0066FF`, and at 80% that neon glowed straight through and turned the board blue.
	The face colour painted behind the texture puts the navy back where the artist drew it. ]]
local function buildClassic(part: BasePart, config: any, canvasScale: number): SurfaceGui
	local names = config.Board
	local gui = surface(part, names.GuiName, names.ClassicStyle, config, true)

	local panel = image(gui, names.PanelName, ASSETS.Upgrades.Panel)
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = COLOR_PANEL_FACE
	panel.BackgroundTransparency = 0
	-- Drawn 1544x1296 and stored 1024x859, so it renders at about 1.5x; slice at that scale to keep
	-- the border the weight it had on the square board.
	slice(panel, 10, ASSETS.UpgradesSize.Panel, part.Size.Y * PIXELS_PER_STUD / ASSETS.UpgradesSize.Panel.Y)

	-- The header: the car, the title, a line of copy, and whose lot this is.
	local icon = picture(panel, "HeaderIcon", ASSETS.Upgrades.HeaderIcon)
	box(icon, CANVAS, { 44, 36, 236, 186 })

	local title = label(panel, names.TitleName, names.TitleText, FONT_CLASSIC, COLOR_TEXT, TYPE.Title, canvasScale)
	box(title, CANVAS, { 306, 38, 1480, 116 })
	stroke(title, COLOR_TEXT_STROKE, 6, 0.2)
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new(COLOR_TEXT, COLOR_TITLE_LOW)
	shade.Parent = title

	local subtitle = label(panel, names.SubtitleName, names.SubtitleText, FONT_CLASSIC, COLOR_COPY, TYPE.Subtitle, canvasScale)
	box(subtitle, CANVAS, { 310, 160, 1010, 52 })

	--[[ Whose lot this is: the one line about a PLAYER rather than an upgrade, so a visitor can tell
		at a glance they are reading somebody else's board. ]]
	local owner = label(panel, names.OwnerName, names.VacantText, FONT_CLASSIC, COLOR_TEXT, TYPE.Owner, canvasScale)
	box(owner, CANVAS, { 1330, 158, 452, 54 })
	owner.TextXAlignment = Enum.TextXAlignment.Right

	-- A kit-blue rule under the header, faded out at both ends.
	local rule = Instance.new("Frame")
	rule.Name = "HeaderRule"
	rule.BackgroundColor3 = COLOR_ACCENT
	rule.BorderSizePixel = 0
	box(rule, CANVAS, { 26, 232, 1770, 6 })
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0),
		NumberSequenceKeypoint.new(0.85, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = rule
	rule.Parent = panel

	local grid = Instance.new("Frame")
	grid.Name = names.GridName
	grid.BackgroundTransparency = 1
	box(grid, CANVAS, { 26, 258, 1770, 1012 })
	grid.Parent = panel

	for index, key in config.Order do
		local spec = config.Upgrades[key]
		if spec then
			buildClassicTile(grid, key, spec, config, index, canvasScale)
		end
	end

	return gui
end

-- === Building: the kit face =================================================

--[[ The kit's parts, found once per run in its Upgrades frame. Named by what they are here, not by
	the kit's names, which repeat (`Template` is a card, a pip and a list row). ]]
local function kitParts(frame: Instance): any?
	local list = frame:FindFirstChild("Main")
	list = list and list:FindFirstChild("ScrollingFrame")
	local card
	for _, child in (if list then list:GetChildren() else {}) do
		if child.Name == "Template" and child:FindFirstChild("Btns") then
			card = child
			break
		end
	end
	local progress = card and card:FindFirstChild("UpgradesProgress")
	local btns = card and card:FindFirstChild("Btns")
	local parts = {
		panel = frame,
		header = frame:FindFirstChild("Header"),
		main = frame:FindFirstChild("Main"),
		card = card,
		pip = progress and progress:FindFirstChild("Template"),
		button = btns and btns:FindFirstChild("RebirthBtn"),
	}
	for _, name in { "header", "main", "card", "pip", "button" } do
		if not parts[name] then
			return nil
		end
	end
	return parts
end

--[[ Copy an element's decoration (its gradient, strokes and corner) onto a fresh frame. The kit
	draws every surface this way, as a white face under a `UIGradient` with a white and a navy
	`UIStroke`, sized in `ScaledSize` so the rims stay in proportion at any size. ]]
local function dress(target: Instance, source: Instance)
	for _, child in source:GetChildren() do
		if child:IsA("UIGradient") or child:IsA("UIStroke") or child:IsA("UICorner") then
			child:Clone().Parent = target
		end
	end
end

--[[ The kit's checker weave over a surface, WITHOUT the kit's `CanvasGroup`.

	The kit clips an oversized, pre-rotated checker texture to each surface through a CanvasGroup.
	A CanvasGroup renders to its own texture at its full pixel size, and on a 1822x1296 canvas that
	is about 9 MB for the panel alone, per board, times six plots. So the texture is cropped instead:
	`ImageRect` picks a patch from inside the rotated square (its corners are transparent) at the
	surface's own aspect, and a copy of the surface's `UICorner` rounds the image the way the group
	did. `cellPx` is how big a checker square should come out, on the canvas. ]]
local function checker(surfaceFrame: GuiObject, source: ImageLabel, corner: UICorner?, sizePx: Vector2, cellPx: number)
	local texel = 14.3 -- the texture's own cell, measured
	local rectW = math.min(820, sizePx.X * texel / cellPx)
	local rectH = rectW * sizePx.Y / sizePx.X
	if rectH > 820 then
		rectH = 820
		rectW = rectH * sizePx.X / sizePx.Y
	end

	local l = Instance.new("ImageLabel")
	l.Name = "Checkers"
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Size = UDim2.fromScale(1, 1)
	l.Image = source.Image
	l.ImageColor3 = source.ImageColor3
	l.ImageTransparency = source.ImageTransparency
	l.ScaleType = Enum.ScaleType.Stretch
	l.ImageRectOffset = Vector2.new(505 - rectW / 2, 512 - rectH / 2)
	l.ImageRectSize = Vector2.new(rectW, rectH)
	l.ZIndex = 0
	if corner then
		corner:Clone().Parent = l
	end
	l.Parent = surfaceFrame
	return l
end

--- A kit label: Fredoka One, white, under the kit's navy outline in `ScaledSize`.
local function kitLabel(parent: Instance, name: string, text: string, capPx: number, canvasScale: number, outline: number?): TextLabel
	local l = label(parent, name, text, FONT_KIT, COLOR_TEXT, capPx, canvasScale)
	local s = stroke(l, COLOR_KIT_STROKE, outline or 0.12, 0)
	s.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	s.LineJoinMode = Enum.LineJoinMode.Miter -- kit TEXT outlines are Miter; rims stay Round
	return l
end

--[[ The white well's inner padding and the gutter between cards, in panel pixels. Wide enough that
	the well reads as white gutters round four cards: at the kit's own spacing the cards' thick rims
	met in the middle and left a stray white diamond where the four corners nearly touched. ]]
local KIT_WELL_PAD = 30
local KIT_GAP = 36
local KIT_CARD_RIM = 0.02

-- Each card's gradient, from the kit's own card set. Chosen so no card matches its picture or the
-- yellow-to-green button sitting on it.
local KIT_CARD_COLORS = {
	Luck = { "fd5bcc", "cf1215" }, -- pink, under a green clover
	Customers = { "05fff2", "2c5dff" }, -- cyan, under a yellow player
	Jump = { "ff61ef", "7d12cf" }, -- purple, under a red coil
	Floor2 = { "ffea05", "ff642c" }, -- orange, under a blue house
}

local function buildKitTile(
	grid: GuiObject,
	key: string,
	spec: any,
	config: any,
	index: number,
	canvasScale: number,
	kit: any,
	tilePx: Vector2,
	gap: Vector2
)
	local names = config.Board
	local single = spec.MaxLevel <= 1

	local tile = Instance.new("Frame")
	tile.Name = key
	tile.BackgroundColor3 = COLOR_TEXT
	tile.BorderSizePixel = 0
	tile.Position, tile.Size = gridSlot(index, gap.X, gap.Y)
	dress(tile, kit.card)
	--[[ The kit's card rims are `ScaledSize` 0.045 of the card's short side, drawn for a list row
		about 60px tall. This card is eight times that, so the same fraction came out ~21px a rim and
		the four cards' rims met across the gutter. 0.02 is the kit's weight at this size. ]]
	for _, rim in tile:GetChildren() do
		if rim:IsA("UIStroke") then
			rim.Thickness = KIT_CARD_RIM
		end
	end
	local colors = KIT_CARD_COLORS[key]
	local gradient = tile:FindFirstChildWhichIsA("UIGradient")
	if colors and gradient then
		gradient.Color = ColorSequence.new(Color3.fromHex(colors[1]), Color3.fromHex(colors[2]))
	end
	local cardChecker = kit.card:FindFirstChild("BG") and kit.card.BG:FindFirstChild("CheckersBG")
	if cardChecker then
		checker(tile, cardChecker, tile:FindFirstChildWhichIsA("UICorner"), tilePx, 22)
	end
	tile:SetAttribute(names.KeyAttribute, key)
	tile.Parent = grid

	local iconId = ASSETS.Upgrades.Icons and ASSETS.Upgrades.Icons[key]
	if iconId then
		local icon = picture(tile, names.TileIconName, iconId)
		box(icon, TILE, CARD.Icon)
	end

	box(kitLabel(tile, names.TileTitleName, titleCase(spec.Title), TYPE.TileTitle, canvasScale), TILE, CARD.Title)

	local headline = kitLabel(tile, names.TileHeadlineName, spec.Headline(0), if single then TYPE.SingleHeadline else TYPE.Headline, canvasScale, 0.1)
	box(headline, TILE, if single then CARD.SingleHeadline else CARD.Headline)

	box(kitLabel(tile, names.TileDetailName, spec.Detail, TYPE.Detail, canvasScale), TILE, if single then CARD.SingleDetail else CARD.Detail)

	if not single then
		box(
			kitLabel(tile, names.TileLevelName, string.format(names.LevelFormat, 0, spec.MaxLevel), TYPE.Level, canvasScale),
			TILE,
			CARD.Level
		)

		--[[ The kit's level ladder: one capsule per level, lit green up to the level and grey past it.
			Each pip carries its rung, and `UpgradeService` recolours its gradient. ]]
		local bar = Instance.new("Frame")
		bar.Name = names.TileBarName
		bar.BackgroundTransparency = 1
		box(bar, TILE, CARD.Bar)
		bar.Parent = tile

		local gap = 0.18 / spec.MaxLevel
		local pipW = (1 - gap * (spec.MaxLevel - 1)) / spec.MaxLevel
		for rung = 1, spec.MaxLevel do
			local pip = kit.pip:Clone()
			pip.Name = "Pip" .. rung
			for _, child in pip:GetChildren() do
				if not (child:IsA("UIGradient") or child:IsA("UIStroke") or child:IsA("UICorner")) then
					child:Destroy()
				end
			end
			pip.AnchorPoint = Vector2.zero
			pip.Position = UDim2.fromScale((rung - 1) * (pipW + gap), 0)
			pip.Size = UDim2.fromScale(pipW, 1)
			pip.LayoutOrder = rung
			pip:SetAttribute(names.PipAttribute, rung)
			local pipGradient = pip:FindFirstChildWhichIsA("UIGradient")
			if pipGradient then
				pipGradient.Color = config.KitPipGradients.Unlit
			end
			pip.Parent = bar
		end
	end

	--[[ The kit's own confirm button, cloned whole and stretched across the card like the mockup's.
		A frame button has no texture to shear, so any width is honest here. Three things come off
		the clone: its price label (the captions below replace it), its `UIButton` tag (that binds
		`Components/Button`, which is screen UI; `UpgradeController` owns this press), and its
		CanvasGroup, which becomes a plain clipping frame for the cost the panel note gives. The
		gloss inside it is not rotated, so rectangular clipping is exact. ]]
	local button = kit.button:Clone()
	button.Name = names.ButtonName
	for _, tag in button:GetTags() do
		button:RemoveTag(tag)
	end
	for _, child in button:GetChildren() do
		if child:IsA("TextLabel") or child:IsA("UITextSizeConstraint") then
			child:Destroy()
		end
	end
	local group = button:FindFirstChild("BG")
	if group and group:IsA("CanvasGroup") then
		local clip = Instance.new("Frame")
		clip.Name = "BG"
		clip.BackgroundTransparency = 1
		clip.AnchorPoint = group.AnchorPoint
		clip.Position = group.Position
		clip.Size = group.Size
		clip.ClipsDescendants = true
		for _, child in group:GetChildren() do
			child.Parent = clip
		end
		group:Destroy()
		clip.Parent = button
	end
	if button:IsA("TextButton") then
		button.Text = ""
	end
	button.AutoButtonColor = false
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, (TILE.Y - BUTTON_MARGIN - 64) / TILE.Y)
	button.Size = UDim2.fromScale(826 / TILE.X, 128 / TILE.Y)
	local buttonGradient = button:FindFirstChildWhichIsA("UIGradient")
	if buttonGradient then
		buttonGradient.Color = config.KitButtonGradients.Buy
	end
	button.Parent = tile

	local action, cost, status = captions(button, names, FONT_KIT, COLOR_TEXT, TYPE.Button + 6, canvasScale, {
		Action = { 0.06, 0.17, 0.42, 0.64 },
		Cash = { 0.53, 0.2, 0.13, 0.58 },
		Cost = { 0.67, 0.17, 0.28, 0.64 },
	})
	for _, caption in { action, cost, status } do
		local s = stroke(caption, COLOR_KIT_STROKE, 0.12, 0)
		s.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
		s.LineJoinMode = Enum.LineJoinMode.Miter
	end
end

--[[ The kit face: the kit's blue panel with its weave, a header, the white well and four gradient
	cards. Every decoration is cloned from the kit's Upgrades frame, so it cannot drift from the
	pages players open. ]]
local function buildKit(part: BasePart, config: any, canvasScale: number, kit: any): SurfaceGui
	local names = config.Board
	local gui = surface(part, names.KitGuiName, names.KitStyle, config, false)

	-- Inset by the outer rim, so the kit's stroke draws on the plate rather than off its edge.
	local panelRect = { 14, 14, 1794, 1268 }
	local panel = Instance.new("Frame")
	panel.Name = names.PanelName
	panel.BackgroundColor3 = COLOR_TEXT
	panel.BorderSizePixel = 0
	box(panel, CANVAS, panelRect)
	dress(panel, kit.panel)
	local panelChecker = kit.panel:FindFirstChild("BG") and kit.panel.BG:FindFirstChild("CheckersBG")
	if panelChecker then
		checker(panel, panelChecker, panel:FindFirstChildWhichIsA("UICorner"), Vector2.new(panelRect[3], panelRect[4]) * canvasScale, 34)
	end
	panel.Parent = gui

	local ref = Vector2.new(panelRect[3], panelRect[4])
	local icon = picture(panel, "HeaderIcon", ASSETS.Upgrades.HeaderIcon)
	box(icon, ref, { 36, 26, 236, 184 })

	box(kitLabel(panel, names.TitleName, titleCase(names.TitleText), TYPE.Title + 8, canvasScale, 0.1), ref, { 290, 20, 1470, 124 })
	box(kitLabel(panel, names.SubtitleName, sentenceCase(names.SubtitleText), TYPE.Subtitle + 4, canvasScale), ref, { 294, 148, 1000, 52 })
	local owner = kitLabel(panel, names.OwnerName, names.VacantText, TYPE.Owner, canvasScale)
	box(owner, ref, { 1310, 146, 452, 54 })
	owner.TextXAlignment = Enum.TextXAlignment.Right

	-- The kit's white well the cards sit in.
	local wellRect = { 28, 222, 1738, 1022 }
	local well = Instance.new("Frame")
	well.Name = "Main"
	well.BackgroundColor3 = kit.main.BackgroundColor3
	well.BorderSizePixel = 0
	box(well, ref, wellRect)
	dress(well, kit.main)
	well.Parent = panel

	--[[ The grid is the PANEL's child and not the well's, laid over the well, because the service and
		the controller both walk `Panel.Grid` by name on either face. ]]
	local grid = Instance.new("Frame")
	grid.Name = names.GridName
	grid.BackgroundTransparency = 1
	grid.ZIndex = 2
	local gridPx = Vector2.new(wellRect[3] - 2 * KIT_WELL_PAD, wellRect[4] - 2 * KIT_WELL_PAD)
	box(grid, ref, { wellRect[1] + KIT_WELL_PAD, wellRect[2] + KIT_WELL_PAD, gridPx.X, gridPx.Y })
	grid.Parent = panel

	local gap = Vector2.new(KIT_GAP / gridPx.X, KIT_GAP / gridPx.Y)
	local tilePx = (gridPx - Vector2.new(KIT_GAP, KIT_GAP)) / 2 * canvasScale
	for index, key in config.Order do
		local spec = config.Upgrades[key]
		if spec then
			buildKitTile(grid, key, spec, config, index, canvasScale, kit, tilePx, gap)
		end
	end

	return gui
end

-- === The sign ===============================================================

--[[ The two mesh parts of a sign: the thin one is the neon face, the thick one is the frame.

	Told apart by THICKNESS and not by name, because the pack names its meshes `Cube.013` /
	`Cube.014` / `Cube.015` / `Cube.016` depending on which of the three sizes a sign is, and the
	numbering does not line up between them. The neon is authored at 0.001 studs deep in every one. ]]
local function faces(sign: Model): (BasePart?, BasePart?)
	local frame, neon
	for _, part in sign:GetDescendants() do
		if part:IsA("BasePart") then
			if part.Size.Z < 0.2 then
				neon = part
			elseif not frame or part.Size.X > frame.Size.X then
				frame = part
			end
		end
	end
	return frame, neon
end

--[[ Widen a sign along its frame's own X, about the frame's centre.

	Each part's offset from the frame is spread by `factor`, and its size grows along whichever of
	its own axes runs along the frame's X, so a part authored rotated inside the model still widens
	the right way. A MeshPart's mesh follows its `Size` on each axis. Everything here is anchored
	with no joints, so writing `CFrame` moves only the part it is written to. ]]
local function stretch(sign: Model, frame: BasePart, factor: number)
	if math.abs(factor - 1) < 1e-3 then
		return
	end
	local pivot = frame.CFrame
	for _, part in sign:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		local rel = pivot:ToObjectSpace(part.CFrame)
		local along = { math.abs(rel.RightVector.X), math.abs(rel.UpVector.X), math.abs(rel.LookVector.X) }
		local size = part.Size
		if along[1] >= along[2] and along[1] >= along[3] then
			size = Vector3.new(size.X * factor, size.Y, size.Z)
		elseif along[2] >= along[3] then
			size = Vector3.new(size.X, size.Y * factor, size.Z)
		else
			size = Vector3.new(size.X, size.Y, size.Z * factor)
		end
		part.Size = size
		part.CFrame = pivot * CFrame.new(rel.Position.X * factor, rel.Position.Y, rel.Position.Z) * rel.Rotation
	end
end

--[[ The pristine sign, quarried from the world the first time and kept in ServerStorage after.

	Picks the SQUARE sign out of the pack — the three sizes are roughly 27 x 27, 25 x 15 and
	21 x 13, so "widest, and no more than a fifth wider than it is tall" separates them with room to
	spare and does not depend on the pack's child order. ]]
local function template(restock: boolean): (Model?, string)
	local store = ServerStorage:FindFirstChild(STORE_FOLDER)
	if not store then
		store = Instance.new("Folder")
		store.Name = STORE_FOLDER
		store.Parent = ServerStorage
	end

	local kept = store:FindFirstChild(STORE_NAME)
	if kept and kept:IsA("Model") and not restock then
		return kept, "stored"
	end

	-- Parked in ServerStorage on 2026-10-13; Workspace still wins if dragged back.
	local worlds = workspace:FindFirstChild(WORLDS_FOLDER) or ServerStorage:FindFirstChild(WORLDS_FOLDER)
	local world = worlds and worlds:FindFirstChild(SOURCE_WORLD)
	if not world then
		return nil, string.format("no workspace.%s.%s to take a sign from", WORLDS_FOLDER, SOURCE_WORLD)
	end

	local best, bestWidth = nil, 0
	for _, tile in world:GetChildren() do
		local props = tile:FindFirstChild(SOURCE_PROPS)
		local pack = props and props:FindFirstChild(SOURCE_PACK)
		if not pack then
			continue
		end
		for _, candidate in pack:GetChildren() do
			if not candidate:IsA("Model") then
				continue
			end
			local _, size = candidate:GetBoundingBox()
			if size.X > bestWidth and size.Y > 0 and size.X / size.Y < 1.2 and size.Y / size.X < 1.2 then
				best, bestWidth = candidate, size.X
			end
		end
	end

	if not best then
		return nil, string.format("no square sign in %s.*.%s.%s", SOURCE_WORLD, SOURCE_PROPS, SOURCE_PACK)
	end

	if kept then
		kept:Destroy()
	end
	local copy = best:Clone()
	copy.Name = STORE_NAME
	copy.Parent = store
	return copy, "quarried from " .. best:GetFullName()
end

--[[ Put one sign on one plot.

	`localX` / `localZ` are in the plot-local frame `docs/MapLayout.md` §3.3 defines — origin at the
	ground centre of the lot, +Y up — which is what makes one set of numbers serve all six plots
	however each one is rotated in the world. ]]
local function buildSign(
	plot: Model,
	source: Model,
	localX: number,
	localZ: number,
	width: number,
	widen: number,
	config: any
): (Model?, string?)
	local names = config.Board
	local origin = plot:FindFirstChild(ORIGIN_NAME)
	if not (origin and origin:IsA("BasePart")) then
		return nil, "no " .. ORIGIN_NAME
	end

	local existing = plot:FindFirstChild(names.ModelName)
	if existing then
		existing:Destroy()
	end

	local sign = source:Clone()
	sign.Name = names.ModelName
	sign.Parent = plot

	local frame, neon = faces(sign)
	if not (frame and neon) then
		sign:Destroy()
		return nil, "the stored sign has no frame/neon pair"
	end

	--[[ EVERY MEASUREMENT BELOW IS OFF THE FRAME PART, NEVER OFF THE MODEL. `Model:GetBoundingBox`
		reports in the model's PIVOT frame, and these signs come out of the world import with a pivot
		that is neither the frame's centre nor aligned to it — measured on the stored copy, the pivot
		sits 0.48 studs off in X and 0.62 in Z and its "up" is the frame's 1.18-stud THICKNESS. Sizing
		and standing the sign off that box put the first build face-up on the forecourt, buried to the
		waist, which is exactly what it should have looked like.

		The frame part is the sign: 17 x 17.19 x 1.18 in its own space, legs included, with local +Y
		up and local -Z out of the face. So it is the only thing worth asking. ]]
	if frame.Size.X > 0 then
		-- Scale by RATIO: the pack's own Scale is about 1.56, so setting `Scale` to a number would
		-- not give the width asked for.
		sign:ScaleTo(sign:GetScale() * width / frame.Size.X)
	end
	-- Then wider than its own proportions, which `ScaleTo` cannot do. See the header.
	stretch(sign, frame, widen)

	-- Set for anything that later calls `GetPivot` on the finished sign; nothing in this file relies
	-- on it, for the reason the block above gives.
	sign.PrimaryPart = frame

	--[[ Ground under the sign, raycast. The sign's own parts are excluded implicitly — they carry
		`CanQuery = false` a few lines down, but the probe runs BEFORE that, so it is filtered here
		as well rather than relying on an ordering. ]]
	local probeParams = RaycastParams.new()
	probeParams.FilterType = Enum.RaycastFilterType.Exclude
	probeParams.FilterDescendantsInstances = { sign }
	local from = origin.CFrame:PointToWorldSpace(Vector3.new(localX, PROBE_TOP, localZ))
	local ground = workspace:Raycast(from, Vector3.new(0, -PROBE_DROP, 0), probeParams)
	local groundLocalY = if ground then origin.CFrame:PointToObjectSpace(ground.Position).Y else 1.4

	--[[ Face the arrival, SNAPPED TO THE PLOT AXIS. The authored spawn is where the player lands and
		which way they are looking, so pointing at it is what decides which way the board turns; local
		(0, -30) is the fallback `PlotConfig.Fallback` describes for a plot that has no authored pad.

		But the raw bearing is only square by accident. From the perimeter spot the board now lives at,
		(3, -47) to the spawn at (0, -30) is 10 degrees off the plot's own axis — enough that the board
		visibly skews against the slab's street-side edge, the planter row and the frontage railing,
		all three of which run parallel to local X. So the bearing picks the DIRECTION and the dominant
		component then rounds it to a quarter turn. Everything on a plot is built on this grid; a sign
		that is the one thing on the lot at an angle reads as a mistake, not as emphasis. ]]
	local spawn = plot:FindFirstChild(SPAWN_NAME)
	local lookAt = if spawn and spawn:IsA("BasePart")
		then origin.CFrame:PointToObjectSpace(spawn.Position)
		else Vector3.new(0, 0, -30)
	local toward = Vector3.new(lookAt.X - localX, 0, lookAt.Z - localZ)
	if toward.Magnitude < 0.01 then
		toward = Vector3.new(0, 0, -1)
	end
	toward = if math.abs(toward.X) > math.abs(toward.Z)
		then Vector3.new(if toward.X < 0 then -1 else 1, 0, 0)
		else Vector3.new(0, 0, if toward.Z < 0 then -1 else 1)

	--[[ Stand it on the ground, facing the spawn, by moving every PART rather than the model.

		`PivotTo` would go through the imported pivot the block above disqualifies. A delta against the
		frame's own CFrame is exact and needs nothing to be true of the model. Safe to write CFrames
		directly here: every part is anchored with no joint of any kind, so each one moves alone and
		nothing drags an assembly. ]]
	local centre = Vector3.new(localX, groundLocalY + frame.Size.Y / 2, localZ)
	local target = origin.CFrame * CFrame.lookAt(centre, centre + toward.Unit)
	local delta = target * frame.CFrame:Inverse()
	for _, part in sign:GetDescendants() do
		if part:IsA("BasePart") then
			part.CFrame = delta * part.CFrame
		end
	end

	--[[ The neon behind the screen goes to the kit blue. It is the only thing about the sign that is
		recoloured, and it is why the board reads as part of this map rather than as a prop borrowed
		from a neon-pink world: a thin rim of #0066FF glows around the panel, matching the blue on the
		panel itself and the blue inlay on the race pad twenty studs away. ]]
	neon.Color = COLOR_ACCENT

	--[[ THE MESHES STOP ANSWERING QUERIES. Both are CollisionFidelity.Default, so their query shape
		is a convex hull that juts into the aperture and would eat clicks aimed at the top-right tile.
		They keep their collision, so the billboard is still solid to walk into. ]]
	for _, part in sign:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
		end
	end

	local screen = Instance.new("Part")
	screen.Name = names.ScreenName
	screen.Size = Vector3.new(neon.Size.X * SCREEN_INSET, neon.Size.Y * SCREEN_INSET, SCREEN_THICKNESS)
	screen.Anchored = true
	screen.CanCollide = false
	screen.CanTouch = false
	--[[ AND THIS ONE MUST ANSWER THEM. A SurfaceGui's buttons are reached by the mouse's own ray, so
		a plate with `CanQuery = false` renders a board that cannot be pressed — the exact failure the
		two meshes above are being switched off to prevent. ]]
	screen.CanQuery = true
	screen.CastShadow = false
	screen.Transparency = 1
	screen.TopSurface = Enum.SurfaceType.Smooth
	screen.BottomSurface = Enum.SurfaceType.Smooth

	-- Centred on the neon's own centre and pushed out to the frame's face — in FRAME space, the only
	-- frame this sign can be trusted to describe itself in.
	local neonLocal = frame.CFrame:PointToObjectSpace(neon.Position)
	-- Safe to write CFrame directly: this part is new and nothing is ever welded to it.
	screen.CFrame = frame.CFrame * CFrame.new(neonLocal.X, neonLocal.Y, -frame.Size.Z / 2 - SCREEN_PROUD)
	screen.Parent = sign

	--[[ Both faces, then the tag. The tag is the client's whole integration: `UpgradeController`
		observes it rather than walking the map, because a board on a plot that has not streamed in
		yet is a board a path walk cannot find. Added last, so nothing can observe a plate that has no
		screen on it. ]]
	local canvasScale = screen.Size.Y * PIXELS_PER_STUD / CANVAS.Y
	buildClassic(screen, config, canvasScale)
	if KIT then
		local parts = kitParts(KIT)
		if parts then
			buildKit(screen, config, canvasScale, parts)
		end
	end
	CollectionService:AddTag(screen, names.Tag)
	return sign, nil
end

-- === Command ================================================================

return {
	AutoRecordChanges = true,
	Description = "Stand a billboard from Worlds.FuturisticCity on every plot's forecourt and draw the 2x2 dealership upgrade screen onto it, in both the classic and the Cartoony Kit face. Idempotent: re-run after any map re-import or layout change.",
	Tags = { "Plots", "UI" },
	Arguments = {
		LocalX = {
			Type = "number",
			Default = DEFAULT_LOCAL_X,
			LayoutOrder = 1,
			Description = "Plot-local X of the sign. 3 centres it on the two big palm planters (X -7.9 and +14.4); the forecourt slab runs X -10..+60, so much below 0 walks it off the tiles.",
		},
		LocalZ = {
			Type = "number",
			Default = DEFAULT_LOCAL_Z,
			LayoutOrder = 2,
			Description = "Plot-local Z. -47 tucks it against the street-side lip of the slab (which ends at -49.5) in front of the planters at -53.8. The spawn is at -30 and the race pad at -52; nearer 0 walks it back out into the middle of the apron, and past about +5 it starts covering bay 6.",
		},
		Width = {
			Type = "number",
			Default = DEFAULT_WIDTH,
			LayoutOrder = 3,
			Description = "Studs across the sign's frame before the stretch. The screen and all its text scale with it, so this is the one dial for how big the board reads from the spawn.",
		},
		Stretch = {
			Type = "number",
			Default = DEFAULT_STRETCH,
			LayoutOrder = 4,
			Description = "How much wider than its own proportions the sign is drawn. 1 is the square prop; 1.18 gives the 1.4:1 screen the picture-left cards are laid out for.",
		},
		Restock = {
			Type = "boolean",
			Default = false,
			LayoutOrder = 5,
			Description = "Re-capture the sign from Worlds.FuturisticCity even though a copy is already stored in ServerStorage.PlotUpgrades. Use this after the themed worlds are replaced with finished art.",
		},
	} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		--[[ The config is REQUIRED rather than copied. There are a couple of dozen names and four
			upgrade specs here, and a board that disagrees with `UpgradeConfig` about any one of them
			is a tile the service silently never fills in. The cost is that edit mode caches a
			required module: change `UpgradeConfig` and the Command Runner has to be reconnected
			before this sees it. ]]
		local shared = ReplicatedStorage:FindFirstChild("shared")
		local configs = shared and shared:FindFirstChild("Configs")
		local module = configs and configs:FindFirstChild("UpgradeConfig")
		local ok, config = pcall(require, module)
		if not (ok and type(config) == "table" and config.Board and config.Board.KitGuiName and config.KitButtonGradients) then
			out:error("Could not require ReplicatedStorage.shared.Configs.UpgradeConfig, or it predates the two faces. Is Rojo syncing, and has the Command Runner been reconnected?")
			return
		end

		--[[ And `UIAssets`, checked down to the entries this file actually needs, because a stale
			required copy from before they were added is exactly the failure that reconnecting the
			Command Runner fixes and that a bare type check would wave through. ]]
		local assetModule = configs and configs:FindFirstChild("UIAssets")
		local assetsOk, assetTable = pcall(require, assetModule)
		if
			not (
				assetsOk
				and type(assetTable) == "table"
				and assetTable.Upgrades
				and assetTable.Upgrades.Icons
				and assetTable.Pill
				and assetTable.Page
				and assetTable.Slice
			)
		then
			out:error(
				"Could not require ReplicatedStorage.shared.Configs.UIAssets, or it predates UIAssets.Upgrades.Icons. Is Rojo syncing, and has the Command Runner been reconnected?"
			)
			return
		end
		ASSETS = assetTable

		-- The kit face's source. Optional: without it every plot still gets the classic face.
		KIT = nil
		local uiImports = ServerStorage:FindFirstChild("UIImports")
		local kitFolder = uiImports and uiImports:FindFirstChild("NewUITemplate")
		local kitGui = kitFolder and kitFolder:FindFirstChildWhichIsA("ScreenGui")
		local container = kitGui and kitGui:FindFirstChild("Container")
		local kitFrame = container and container:FindFirstChild(KIT_FRAME)
		if kitFrame and kitParts(kitFrame) then
			KIT = kitFrame
		else
			out:warn(string.format("No Cartoony Kit %s under ServerStorage.UIImports.NewUITemplate; building the classic face only.", KIT_FRAME))
		end

		local folder: Instance = workspace
		for _, name in ipairs(PLOTS_PATH) do
			local nextFolder = folder:FindFirstChild(name)
			if not nextFolder then
				out:error(string.format("No workspace.%s — nothing to build on.", table.concat(PLOTS_PATH, ".")))
				return
			end
			folder = nextFolder
		end

		local source, note = template(arguments.Restock == true)
		if not source then
			out:error("No sign to build from: " .. note)
			return
		end

		local localX = if type(arguments.LocalX) == "number" then arguments.LocalX else DEFAULT_LOCAL_X
		local localZ = if type(arguments.LocalZ) == "number" then arguments.LocalZ else DEFAULT_LOCAL_Z
		local width = if type(arguments.Width) == "number" and arguments.Width > 1 then arguments.Width else DEFAULT_WIDTH
		local widen = if type(arguments.Stretch) == "number" and arguments.Stretch >= 1 then arguments.Stretch else DEFAULT_STRETCH

		local built, failed = {}, {}
		for _, plot in ipairs(folder:GetChildren()) do
			if not plot:IsA("Model") then
				continue
			end
			local sign, why = buildSign(plot, source, localX, localZ, width, widen, config)
			if sign then
				table.insert(built, sign)
			else
				table.insert(failed, string.format("%s (%s)", plot.Name, why or "?"))
			end
		end

		if #built == 0 then
			out:error("Built nothing — " .. (failed[1] or "no plot Models in the folder"))
			return
		end

		pcall(function()
			props:SetSelection(built)
			props:FocusView(built)
		end)

		if #failed > 0 then
			out:warn("Skipped: " .. table.concat(failed, ", "))
		end
		out:print(string.format(
			"Built %d upgrade billboard(s) at plot-local (%.0f, %.0f), %.0f studs wide x%.2f, %s. Sign %s. UpgradeService fills them in on claim.",
			#built,
			localX,
			localZ,
			width,
			widen,
			if KIT then "both faces" else "classic face only",
			note
		))
	end,
} :: Types.ScriptModule
