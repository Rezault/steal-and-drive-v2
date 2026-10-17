--[[
	BuildLeaderboardBoard — Command Runner command

	Dresses the global leaderboard: finds the modeller's board standing in the middle of the
	roundabout and authors a double-sided SurfaceGui onto its plate, with one tab and one page per
	entry in `LeaderboardConfig.List`.

		+------------------------------------------+
		|              MOST VALUABLE               |  <- the ACTIVE board's Title
		|  #1  (O) Gvistic               $33,120   |
		|  #2  (O) SomebodyElse          $12,400   |  <- RowsShown rows
		|  ...                                     |
		|  ======================------------      |  <- the refresh bar, emptying
		|  [  Cash  ][  Cars  ][  Value  ]         |
		|  [ Distance ][ Steals ][  Time  ]        |  <- TabColumns wide, wrapping
		+------------------------------------------+

	`LeaderboardController` never builds any of this — it fills it in and switches the tabs. Every
	name it looks for lives in `LeaderboardConfig.Board`, and THE PAGES AND TABS ARE NAMED BY THE
	BOARD `Key` rather than by anything in this file, so adding a seventh board to `List` and
	re-running this command is the whole job.

	=== IT DRESSES ART. IT DOES NOT BUILD GEOMETRY. ============================================

	This used to stand up its own plinth and plate out of two Parts. It no longer does: the board is
	now the modeller's model, a stone-footed timber frame around a white backing plane, and the
	command's job is the same one `BuildPlotUpgradeSigns` does for the forecourt billboard — find the
	authored plate, throw away whatever placeholder gui shipped on it, and author ours at the right
	fractions of ITS canvas.

	So the layout constants below are all fractions, and they are fractions of a PORTRAIT plate now
	(roughly 19.6 x 26.6 studs against the old 30 x 15). That is why the tab strip wraps: six tabs
	across a portrait board would be six slivers, and two rows of three are targets you can read from
	the far side of the roundabout. `LeaderboardConfig.Board.TabColumns` is the knob.

	=== WHICH PART IS THE PLATE ================================================================

	`LeaderboardConfig.Board.ScreenName` ("Screen"), if a part by that name is there. On a freshly
	imported model nothing is named that yet, so the fallback is THE PART THE PLACEHOLDER GUI SAT ON
	— the modeller authored their mockup on the right face, and that is the one fact about an
	imported board that is always true. The command renames it, so the fallback is only ever needed
	once per import.

	If neither finds it, the command stops and says so rather than guessing: a board dressed onto the
	backing plane or onto a frame post renders behind the art or off the edge of it, and both of
	those look like a bug in the controller.

	=== TWO FACES ==============================================================================

	Plots stand on both sides of the roundabout, so a one-sided board shows its back to half the map.
	The plate carries two SurfaceGuis, `Front` and `Back`, built identically; the controller drives
	every one it finds from a single selected tab, so they cannot drift apart.

	BOTH SIT ON THE PLATE AND NOT ON THE BACKING PLANE. The plate is a frame with a hole in it and
	the white backing hangs behind the hole, so a face drawn on the plate is nearer to its own viewer
	than the backing is and draws over it — which is exactly what the modeller's own mockup did on
	the front. Moving the back face onto the backing plane instead would give the two faces different
	canvas sizes and therefore different type.

	IDEMPOTENT. Re-run it freely — an existing board is re-seated and its guis rebuilt in place.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(script.Types)
local LeaderboardConfig = require(ReplicatedStorage.shared.Configs.LeaderboardConfig)

local NAMES = LeaderboardConfig.Board

-- === Where it goes ==========================================================

--[[ The centre of the roundabout, measured off the ring road's own geometry — `Roads.Surface.Circle`
	is a ~930 x 884 disc centred here, with the two rows of plots north and south of it. It is the
	one piece of ground in this map that everybody drives past and nobody has built on. ]]
local DEFAULT_X = 2041
local DEFAULT_Z = 490

local PARENT_PATH = { "Map", "City" }

--[[ Names the imported model may be sitting under before it has been dressed once. The modeller
	exports it as `Leaderboard`; after a run it is `ModelName` and lives under `PARENT_PATH`. ]]
local IMPORT_NAMES = { "LeaderboardBoard", "Leaderboard" }

--- Raycast for the ground: start this far above the target and drop this far.
local PROBE_TOP = 150
local PROBE_DROP = 300

--- Preview only. Long-lived Roblox accounts, so the thumbnails are guaranteed to resolve — the same
--- five `BuildDealershipSigns` previews its headshot with.
local PREVIEW_USER_IDS = { 1, 156, 261, 2032622, 1516946 }

-- === Look ===================================================================
-- `car ui.psd`: #0066FF on #29344B, Ubuntu Bold. Same palette the upgrade boards and the dealership
-- signs use, so the three read as one set of signage.
--
-- WHAT THE ART ALREADY GIVES US IS THE BACKGROUND. The plate has a white backing plane behind it, so
-- unlike the old built board there is no panel fill to author — the page frames are transparent and
-- the art shows through. That is the whole reason the rows are translucent dark cards rather than
-- the kit's flat #29344B: a solid card would read as a second, smaller sign pasted onto the first.

local COLOR_ROW = Color3.fromRGB(12, 20, 32)
local ROW_TRANSPARENCY = 0.25

local COLOR_CARD = Color3.fromRGB(41, 52, 75) -- #29344B, the idle tab. Matches the controller.
local COLOR_ACCENT = Color3.fromRGB(0, 102, 255) -- #0066FF
local COLOR_STROKE = Color3.fromRGB(135, 146, 181)
local COLOR_MUTED = Color3.fromRGB(168, 179, 208)
local COLOR_TEXT_STROKE = Color3.fromRGB(8, 14, 24)
local COLOR_TEXT = Color3.new(1, 1, 1)

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

--[[ 50 px per stud, the value the modeller's own mockup carried. At the plate's ~19.6 x 26.6 that is
	a 979 x 1330 canvas — a row's name lands at a comfortable 40 px without the whole thing being a
	texture nobody can read up close. Every offset below is a fraction of the canvas rather than a
	pixel, so a plate of another size rescales the layout instead of breaking it. ]]
local PIXELS_PER_STUD = 50

-- === Canvas layout, in fractions ============================================

--[[ THESE ARE FRACTIONS OF THE PLATE, NOT OF THE WHITE BACKING, and the backing is the smaller of
	the two: it covers x 0.083..0.917 and y 0.061..0.939 of the plate's face. Everything below is
	inset to sit inside that, because a row hanging over the edge of the backing is a row printed on
	the timber frame. `PAD_X` is the margin that keeps it there. ]]
local PAD_X = 0.090

local TITLE_TOP = 0.070
local TITLE_H = 0.068

local ROWS_TOP = 0.150
local ROWS_BOTTOM = 0.762

--- The refresh bar: a hairline, and the gap it leaves above the tab strip.
local TIMER_TOP = 0.782
local TIMER_H = 0.013
local TIMER_INSET = 0.06 -- extra x margin, so the bar is narrower than the rows above it

local TABS_TOP = 0.806
local TABS_BOTTOM = 0.936

--- Gaps between two tabs, as a fraction of the strip's width and height.
local TAB_GAP_X = 0.020
local TAB_GAP_Y = 0.090

--- One row's share of the page, and how much of that share is the row itself (the rest is the gap).
local ROW_FILL = 0.88

--[[ Columns inside a row, as fractions of the row's width. The amount is right-aligned against the
	far edge so every value in the column ends in the same place — a list of money that is ragged on
	the right is a list nobody can compare down. ]]
local RANK_X, RANK_W = 0.012, 0.075
local FACE_X, FACE_W = 0.092, 0.055
local NAME_X = 0.160
local AMOUNT_W = 0.270
local AMOUNT_RIGHT = 0.988

-- === Helpers ================================================================

local NB_SPACE = utf8.char(0x00A0)

--[[ Same substitution the dealership sign makes, and for the same reason: `TextScaled` would sooner
	wrap a label to a second line than pick a smaller font, and every label on this board is one
	line. See `BuildDealershipSigns` for the two fixes that look right and are not. ]]
local function oneLine(text: string): string
	return (string.gsub(text, " ", NB_SPACE))
end

local function clearChildren(instance: Instance)
	for _, child in instance:GetChildren() do
		child:Destroy()
	end
end

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

local function textLabel(parent: Instance, name: string, text: string, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Text = oneLine(text)
	l.TextColor3 = color
	l.FontFace = FONT
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Parent = parent
	stroke(l, COLOR_TEXT_STROKE, 2, 0.6)
	return l
end

-- === One row ================================================================

--[[ A rank, a face, a name and an amount. Every one of them is written by the controller; what is
	built here is the shape and, importantly, the EMPTY STATE — a row is authored blank and invisible
	so a board with four names on it does not show six leftover rows from the last refresh. ]]
local function buildRow(page: Frame, index: number)
	local share = 1 / NAMES.RowsShown

	local row = Instance.new("Frame")
	row.Name = NAMES.RowName .. index
	row.Position = UDim2.fromScale(0, (index - 1) * share)
	row.Size = UDim2.fromScale(1, share * ROW_FILL)
	row.BackgroundColor3 = COLOR_ROW
	--[[ TRANSLUCENT, against the art's white backing rather than against a panel we drew. See the
		note over the palette: an opaque card here reads as a sign inside the sign. ]]
	row.BackgroundTransparency = ROW_TRANSPARENCY
	row.BorderSizePixel = 0
	row.Visible = false
	row.Parent = page
	corner(row, 12)
	stroke(row, COLOR_TEXT_STROKE, 2, 0.55)

	local rank = textLabel(row, NAMES.RankName, "#" .. index, COLOR_MUTED)
	rank.AnchorPoint = Vector2.new(0, 0.5)
	rank.Position = UDim2.fromScale(RANK_X, 0.5)
	rank.Size = UDim2.fromScale(RANK_W, 0.62)
	rank.TextXAlignment = Enum.TextXAlignment.Center

	--[[ A circle, like the dealership sign's. It is an ImageLabel with no Image until the controller
		fills one in — `rbxthumb` resolves client-side without yielding, so a row can gain its face in
		the same frame it gains its name. ]]
	local face = Instance.new("ImageLabel")
	face.Name = NAMES.HeadshotName
	face.AnchorPoint = Vector2.new(0, 0.5)
	face.Position = UDim2.fromScale(FACE_X, 0.5)
	--[[ Sized off the ROW's height rather than the canvas's width, so it stays a circle: a
		`fromScale(FACE_W, 0.8)` box on a row three times wider than it is tall would be an ellipse,
		and `UIAspectRatioConstraint` on a zero-width parent collapses (see the UI image pipeline
		notes). Width in x, and the constraint below squares it against that. ]]
	face.Size = UDim2.fromScale(FACE_W, 0.8)
	face.BackgroundColor3 = COLOR_ACCENT
	face.BorderSizePixel = 0
	face.Image = ""
	face.ScaleType = Enum.ScaleType.Fit
	face.Parent = row
	corner(face, 999)

	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.DominantAxis = Enum.DominantAxis.Height
	ratio.Parent = face

	local playerName = textLabel(row, NAMES.PlayerName, "", COLOR_TEXT)
	playerName.AnchorPoint = Vector2.new(0, 0.5)
	playerName.Position = UDim2.fromScale(NAME_X, 0.5)
	playerName.Size = UDim2.fromScale(AMOUNT_RIGHT - AMOUNT_W - NAME_X - 0.02, 0.6)

	local amount = textLabel(row, NAMES.AmountName, "", COLOR_TEXT)
	amount.AnchorPoint = Vector2.new(1, 0.5)
	amount.Position = UDim2.fromScale(AMOUNT_RIGHT, 0.5)
	amount.Size = UDim2.fromScale(AMOUNT_W, 0.6)
	amount.TextXAlignment = Enum.TextXAlignment.Right
end

-- === The tab strip ==========================================================

--[[ ONE BUTTON PER ENTRY IN `List`, NAMED BY `Key` — header note 1 of the config.

	WRAPPED, over `TabColumns` columns, and placed by index rather than by a UIGridLayout so a
	button's name and its position stay the same fact and the controller can find "the Value tab"
	without walking the strip. The row count and the cell height are DERIVED from the number of
	boards, so a seventh makes three rows of three that still fit the strip instead of one that
	hangs off the bottom of it.

	A short last row is centred against the ones above it. Six over three is exact today; five would
	otherwise leave a hole on the right that reads as a missing tab. ]]
local function buildTabs(panel: Frame)
	local tabs = Instance.new("Frame")
	tabs.Name = NAMES.TabsName
	tabs.Position = UDim2.fromScale(PAD_X, TABS_TOP)
	tabs.Size = UDim2.fromScale(1 - 2 * PAD_X, TABS_BOTTOM - TABS_TOP)
	tabs.BackgroundTransparency = 1
	tabs.Parent = panel

	local count = #LeaderboardConfig.List
	local columns = math.max(1, math.min(NAMES.TabColumns, count))
	local rows = math.ceil(count / columns)

	local cellW = (1 - TAB_GAP_X * (columns - 1)) / columns
	local cellH = (1 - TAB_GAP_Y * (rows - 1)) / rows

	for index, board in LeaderboardConfig.List do
		local column = (index - 1) % columns
		local row = math.floor((index - 1) / columns)
		--- How many tabs are on THIS row, so a short last one can be centred.
		local onRow = math.min(columns, count - row * columns)
		local indent = (columns - onRow) * (cellW + TAB_GAP_X) / 2

		local button = Instance.new("TextButton")
		button.Name = board.Key
		--- Centre-anchored (house rule), so the cell's middle rather than its top-left corner.
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = UDim2.fromScale(indent + column * (cellW + TAB_GAP_X) + cellW / 2, row * (cellH + TAB_GAP_Y) + cellH / 2)
		button.Size = UDim2.fromScale(cellW, cellH)
		--[[ Built in the INACTIVE colours, including the first one. The controller paints the
			selection the moment it binds, and seeding one tab as active here would mean two files
			believing they own which tab is up — with the built-in one winning on any board the
			controller failed to bind, which is the state that most needs to look wrong. ]]
		button.BackgroundColor3 = COLOR_CARD
		button.BorderSizePixel = 0
		button.AutoButtonColor = true
		button.Text = oneLine(board.Short)
		button.TextColor3 = COLOR_MUTED
		button.FontFace = FONT
		button.TextScaled = true
		button.Parent = tabs
		corner(button, 14)
		stroke(button, COLOR_TEXT_STROKE, 2, 0.5)

		local cap = Instance.new("UITextSizeConstraint")
		cap.MaxTextSize = 40
		cap.MinTextSize = 12
		cap.Parent = button

		--[[ Padding rather than a smaller label: `TextScaled` fills whatever box it is given, so the
			only way to keep "Distance" off the pill's rounded ends is to shrink the box it may use. ]]
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.06, 0)
		pad.PaddingRight = UDim.new(0.06, 0)
		pad.PaddingTop = UDim.new(0.18, 0)
		pad.PaddingBottom = UDim.new(0.18, 0)
		pad.Parent = button
	end
end

-- === One face ===============================================================

--[[ Build (or rebuild) one SurfaceGui on `part`, on the given face.

	The two calls differ ONLY in `Face` and in the gui's name — everything inside is identical, which
	is what lets the controller treat "a face" as a unit and drive both from one selection. ]]
local function buildFace(part: BasePart, face: Enum.NormalId, name: string): SurfaceGui
	local gui = part:FindFirstChild(name)
	if not (gui and gui:IsA("SurfaceGui")) then
		if gui then
			gui:Destroy()
		end
		gui = Instance.new("SurfaceGui")
		gui.Name = name
	end
	clearChildren(gui)

	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0 -- reads the same at night as at noon
	gui.Brightness = 1
	gui.AlwaysOnTop = false
	gui.ZOffset = 0
	gui.MaxDistance = 0 -- never fades; it is meant to be read from across the roundabout
	gui.ClipsDescendants = false
	--[[ WITHOUT THIS THE TABS ARE DECORATION. A SurfaceGui in Workspace takes no input unless it is
		`Active` AND the part under it is `CanQuery` — the buttons are reached by the mouse's own ray.
		Both halves are set here and in `dressBoard`; miss either and the board looks exactly like an
		unbound controller. The dealership sign and the upgrade boards carry the same pair of lines. ]]
	gui.Active = true
	gui.Parent = part

	--[[ TRANSPARENT, unlike the old built board's #364157 slab. The art's white backing plane IS the
		panel — see the note over the palette. It is still a Frame and it is still called `Panel`,
		because that name is the first hop of the controller's walk down. ]]
	local panel = Instance.new("Frame")
	panel.Name = NAMES.PanelName
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.Parent = gui

	--[[ The heading. A TRANSPARENT bar holding a stroked white label rather than the kit's #0066FF
		title bar: the plate is already framed in timber and a blue bar inside a timber frame is two
		frames. The modeller's mockup put the heading here in exactly this style, and the outline is
		what carries it over a light backing. The Frame is kept because `TitleBar` is a hop on the
		controller's walk. ]]
	local bar = Instance.new("Frame")
	bar.Name = NAMES.TitleBarName
	bar.Position = UDim2.fromScale(PAD_X, TITLE_TOP)
	bar.Size = UDim2.fromScale(1 - 2 * PAD_X, TITLE_H)
	bar.BackgroundTransparency = 1
	bar.BorderSizePixel = 0
	bar.Parent = panel

	--[[ The ACTIVE board's `Title`, not a fixed word — the heading changes with the tab, which is
		what stops "RICHEST" sitting over a list of distances. Seeded with the first board's title so
		the dressed board looks right in Studio before a client has ever driven it. ]]
	local title = textLabel(bar, NAMES.TitleName, LeaderboardConfig.List[1].Title, COLOR_TEXT)
	title.Position = UDim2.fromScale(0, 0)
	title.Size = UDim2.fromScale(1, 1)
	title.TextXAlignment = Enum.TextXAlignment.Center
	local titleStroke = title:FindFirstChildWhichIsA("UIStroke")
	if titleStroke then
		--[[ Heavier than a row's. White type on a white backing is carried entirely by its outline,
			and at this size a 2px hairline disappears from across the roundabout. ]]
		titleStroke.Thickness = 5
		titleStroke.Transparency = 0
	end

	--[[ One page per board, all stacked in the same rect and all but one hidden. The controller
		flips `Visible`; nothing here decides which is up, for the reason on the tab colours. ]]
	local pages = Instance.new("Frame")
	pages.Name = NAMES.PagesName
	pages.Position = UDim2.fromScale(PAD_X, ROWS_TOP)
	pages.Size = UDim2.fromScale(1 - 2 * PAD_X, ROWS_BOTTOM - ROWS_TOP)
	pages.BackgroundTransparency = 1
	pages.Parent = panel

	for _, board in LeaderboardConfig.List do
		local page = Instance.new("Frame")
		page.Name = board.Key
		page.Size = UDim2.fromScale(1, 1)
		page.BackgroundTransparency = 1
		page.Visible = false
		page.Parent = pages

		for index = 1, NAMES.RowsShown do
			buildRow(page, index)
		end

		--[[ The "nobody has ranked yet" line, sitting behind the rows. Its own label rather than a
			row with placeholder text in it, because it is centred across the whole page and a row is
			a four-column layout — reusing one would mean a row that is sometimes not a row. ]]
		local empty = textLabel(page, NAMES.EmptyName, NAMES.EmptyText, COLOR_TEXT)
		empty.AnchorPoint = Vector2.new(0.5, 0.5)
		empty.Position = UDim2.fromScale(0.5, 0.5)
		empty.Size = UDim2.fromScale(0.8, 0.09)
		empty.TextXAlignment = Enum.TextXAlignment.Center
		empty.Visible = false
		local emptyStroke = empty:FindFirstChildWhichIsA("UIStroke")
		if emptyStroke then
			emptyStroke.Thickness = 4
			emptyStroke.Transparency = 0
		end
	end

	buildTabs(panel)

	--[[ The refresh bar the modeller's mockup carried, kept and given a job: it empties over
		`LeaderboardConfig.ReadInterval` and refills the moment a snapshot lands.

		IT IS DRIVEN OFF THE ARRIVAL OF A SNAPSHOT, CLIENT-SIDE, and there is no "next refresh at" on
		the wire — see the controller's note. Authored FULL, so a board nobody has sent anything to
		yet does not read as one that is a second away from updating. ]]
	local timer = Instance.new("Frame")
	timer.Name = NAMES.TimerName
	timer.AnchorPoint = Vector2.new(0.5, 0)
	timer.Position = UDim2.fromScale(0.5, TIMER_TOP)
	timer.Size = UDim2.fromScale(1 - 2 * (PAD_X + TIMER_INSET), TIMER_H)
	timer.BackgroundColor3 = COLOR_ROW
	timer.BackgroundTransparency = 0.35
	timer.BorderSizePixel = 0
	timer.Parent = panel
	corner(timer, 999)
	stroke(timer, COLOR_STROKE, 2, 0.6)

	--[[ Held at FULL width and cut with a gradient rather than resized, the fix the pill bars
		needed: a rounded fill sized in scale flattens its own corners as it shrinks and leaks past
		the ends of the trough. The controller writes the gradient's `Offset`, not this frame's
		`Size`. ]]
	local fill = Instance.new("Frame")
	fill.Name = NAMES.TimerFillName
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = COLOR_ACCENT
	fill.BorderSizePixel = 0
	fill.Parent = timer
	corner(fill, 999)

	--[[ A hard step from opaque to invisible. `Offset.X` slides the step across the trough, so the
		visible run of colour is the remaining fraction and the corners never deform. Two keypoints
		either side of the middle because a NumberSequence may not repeat a time exactly. ]]
	local ramp = Instance.new("UIGradient")
	ramp.Name = NAMES.TimerRampName
	ramp.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.501, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	--[[ Parked at the far end, which is what "full" is: a point at fraction `p` across the trough
		samples the ramp at `p - Offset.X`, so the coloured run is `0.5 + Offset.X` wide and +0.5 is
		all of it. Authored full rather than at the ramp's own resting half — see the note above. ]]
	ramp.Offset = Vector2.new(0.5, 0)
	ramp.Parent = fill

	return gui
end

-- === The board ==============================================================

--- Drop a ray onto whatever is under `x, z` and hand back the surface height. Nil = nothing there.
local function groundAt(x: number, z: number, ignore: { Instance }): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(Vector3.new(x, PROBE_TOP, z), Vector3.new(0, -PROBE_DROP, 0), params)
	return hit and hit.Position.Y
end

--[[ The lowest point of the model, in WORLD space, walked off the parts' own corners.

	NOT `Model:GetBoundingBox()`, which measures in the PIVOT's frame and would report the height of
	a rotated art model as whatever its pivot happens to be turned to — the trap the sign-fitting
	notes already carry. Eight corners a part is cheap and it cannot be wrong. ]]
local function lowestPoint(model: Model): number
	local lowest = math.huge
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local half = part.Size / 2
			for x = -1, 1, 2 do
				for y = -1, 1, 2 do
					for z = -1, 1, 2 do
						local at = part.CFrame:PointToWorldSpace(Vector3.new(x * half.X, y * half.Y, z * half.Z))
						lowest = math.min(lowest, at.Y)
					end
				end
			end
		end
	end
	return if lowest == math.huge then 0 else lowest
end

--[[ Which part carries the guis. See the header's "WHICH PART IS THE PLATE" — named first, and on a
	fresh import the one the modeller's own mockup was authored on. ]]
local function findScreen(model: Model): BasePart?
	local named = model:FindFirstChild(NAMES.ScreenName, true)
	if named and named:IsA("BasePart") then
		return named
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part:FindFirstChildWhichIsA("SurfaceGui") then
			return part
		end
	end
	return nil
end

--- The model, wherever it currently is: already dressed and parented, or freshly imported loose.
local function findModel(parent: Instance): Model?
	for _, name in IMPORT_NAMES do
		local found = parent:FindFirstChild(name)
		if found and found:IsA("Model") then
			return found
		end
	end
	for _, name in IMPORT_NAMES do
		local found = workspace:FindFirstChild(name, true)
		if found and found:IsA("Model") then
			return found
		end
	end
	return nil
end

--[[ Turn the board so its plate's front looks down -Z and stand it on the ground at `x, z`.

	`FRONT FACES -Z`, which puts it toward the northern row of plots; the Back face therefore reads
	to the southern row. That was true of the old built board and the plots have not moved, so it is
	the orientation this one has to land in however the art happened to be exported. ]]
local function seat(model: Model, screen: BasePart, x: number, z: number): number
	--[[ The plate's current heading, with 0 meaning "already facing -Z". Rotated about the vertical
		through the model's own pivot, so it turns on the spot rather than swinging around the
		origin. ]]
	local look = screen.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local pivot = model:GetPivot()
	model:PivotTo(CFrame.new(pivot.Position) * CFrame.Angles(0, -yaw, 0) * pivot.Rotation)

	--[[ The board's own parts are excluded from the ground probe. Without this a re-run measures the
		height of whatever the board is standing on itself and it climbs a little every run. ]]
	local ground = groundAt(x, z, { model }) or 0

	--[[ Centred on the PLATE's x/z rather than the model's, because the plate is the thing that has
		to sit in the middle of the roundabout — an art model whose footing is offset from its screen
		would otherwise park the screen off-centre by exactly that offset. ]]
	local offset = Vector3.new(x - screen.Position.X, ground - lowestPoint(model), z - screen.Position.Z)
	model:PivotTo(model:GetPivot() + offset)

	return ground
end

--- Name the plate, author both faces, seat it and tag it. Nil screen = the reason it could not be.
local function dressBoard(model: Model, parent: Instance, x: number, z: number): (BasePart?, number, string?)
	local screen = findScreen(model)
	if not screen then
		return nil, 0, string.format("no plate — name the part the guis belong on `%s` and re-run", NAMES.ScreenName)
	end

	model.Name = NAMES.ModelName
	model.Parent = parent
	screen.Name = NAMES.ScreenName

	--[[ Any gui the modeller left on the plate that is not one of ours goes. Their mockup ships with
		placeholder pages (`Jumps`, `Wins`, `Rebirths`) that bind to nothing and would otherwise sit
		behind the real board forever. Ours are rebuilt below either way. ]]
	local keep = {}
	for _, side in NAMES.Faces do
		keep[NAMES.GuiName .. side] = true
	end
	for _, child in screen:GetChildren() do
		if child:IsA("SurfaceGui") and not keep[child.Name] then
			child:Destroy()
		end
	end

	screen.Anchored = true
	--[[ QUERYABLE, AND IT HAS TO BE. A SurfaceGui's buttons are reached by the MOUSE'S OWN RAY, so a
		plate the mouse cannot hit renders a board whose tabs do nothing. `BuildDealershipSigns` has
		the long version of this note; it is the single easiest thing to lose here. ]]
	screen.CanQuery = true
	screen.CanTouch = false

	--[[ AND THE MESH HAS TO BE SOLID TO THAT RAY. The plate is a frame with a hole in it, so its
		`Default` collision hull has a hole in it too — every tab that lands over the opening would be
		unclickable while the ones over the timber worked, which reads as half a broken board. `Box`
		fills it in, and a billboard nobody should be able to walk through wants that anyway. ]]
	if screen:IsA("MeshPart") and screen.CollisionFidelity ~= Enum.CollisionFidelity.Box then
		screen.CollisionFidelity = Enum.CollisionFidelity.Box
	end

	--[[ One gui per face in the config's list, named `GuiName .. side` — that string IS the contract
		the controller waits on, so the list here and the list it reads are the same list. ]]
	for _, side in NAMES.Faces do
		buildFace(screen, (Enum.NormalId :: any)[side], NAMES.GuiName .. side)
	end

	model.PrimaryPart = screen
	local ground = seat(model, screen, x, z)

	if not CollectionService:HasTag(model, NAMES.Tag) then
		CollectionService:AddTag(model, NAMES.Tag)
	end

	return screen, ground, nil
end

-- === Command ================================================================

return {
	AutoRecordChanges = true,
	Description = "Dress the leaderboard art model standing in the roundabout: two faces, one tab and one page per entry in LeaderboardConfig.List. Idempotent — re-run after adding a board or moving the model.",
	Tags = { "UI", "Map" },
	Arguments = {
		X = {
			Type = "number",
			Default = DEFAULT_X,
			LayoutOrder = 1,
			Description = "World X for the plate. Defaults to the centre of the roundabout.",
		},
		Z = {
			Type = "number",
			Default = DEFAULT_Z,
			LayoutOrder = 2,
			Description = "World Z for the plate. Defaults to the centre of the roundabout. The board's ground height is raycast, not typed, so moving it sideways re-seats it.",
		},
		Preview = {
			Type = "boolean",
			Default = false,
			LayoutOrder = 3,
			Description = "Fill the first page with placeholder rows so the dressed board can be judged in Studio without joining a game. Off = leave every row hidden, which is what a board with no snapshot yet shows.",
		},
	} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		local parent: Instance = workspace
		for _, name in PARENT_PATH do
			local nextParent = parent:FindFirstChild(name)
			if not nextParent then
				out:error(string.format("No workspace.%s — nowhere to put the board.", table.concat(PARENT_PATH, ".")))
				return
			end
			parent = nextParent
		end

		local model = findModel(parent)
		if not model then
			out:error(string.format(
				"No leaderboard model found. Import the art and leave it in Workspace named one of: %s.",
				table.concat(IMPORT_NAMES, ", ")
			))
			return
		end

		local x = tonumber(arguments.X) or DEFAULT_X
		local z = tonumber(arguments.Z) or DEFAULT_Z

		local screen, ground, problem = dressBoard(model, parent, x, z)
		if not screen then
			out:error(string.format("%s: %s", model:GetFullName(), tostring(problem)))
			return
		end

		if arguments.Preview then
			--[[ Only the FIRST page, and only on the front face — the point is to judge a row's
				layout, and six identical pages of fake names would just be more of the same thing to
				scroll past in the Explorer.

				IT HAS TO TURN THE PAGE ON AND PAINT THE TAB ITSELF, because the build leaves every
				page hidden and every tab idle on purpose (see the note on the tab colours) — a
				preview that only filled the rows would show a blank board and prove nothing, which
				is exactly what the first run of this did. ]]
			local entry = LeaderboardConfig.List[1]
			local panel = screen[NAMES.GuiName .. "Front"][NAMES.PanelName]
			local page = panel[NAMES.PagesName]:FindFirstChild(entry.Key)
			page.Visible = true

			local tab = panel[NAMES.TabsName]:FindFirstChild(entry.Key)
			if tab then
				tab.BackgroundColor3 = COLOR_ACCENT
				tab.TextColor3 = COLOR_TEXT
			end

			--[[ Five rows, not ten, and deliberately so: it shows the filled rows AND the hidden
				tail in one look, which is the pair of states the row layout has to get right.
				The names span the widths a real one reaches, from two characters to an overlong
				one that has to meet the amount column without touching it. ]]
			local sample = {
				{ "Gvistic", 4_182_500 },
				{ "SomebodyElseEntirely", 921_400 },
				{ "ThirdPlace", 640_100 },
				{ "aa", 88_250 },
				{ "PlayerFour", 12_900 },
			}
			for index = 1, NAMES.RowsShown do
				local row = page:FindFirstChild(NAMES.RowName .. index)
				local data = sample[index]
				if row and data then
					row.Visible = true
					row[NAMES.RankName].Text = "#" .. index
					row[NAMES.RankName].TextColor3 = LeaderboardConfig.rankColor(index)
					row[NAMES.PlayerName].Text = oneLine(data[1])
					row[NAMES.AmountName].Text = LeaderboardConfig.format(entry, data[2])
					row[NAMES.HeadshotName].Image = string.format(NAMES.HeadshotFormat, PREVIEW_USER_IDS[index] or 1)
				end
			end
			panel[NAMES.TitleBarName][NAMES.TitleName].Text = oneLine(entry.Title)
		end

		pcall(function()
			props:SetSelection({ model })
			props:FocusView({ model })
		end)

		local columns = math.max(1, math.min(NAMES.TabColumns, #LeaderboardConfig.List))
		out:print(string.format(
			"Dressed %s at (%d, %.1f, %d): %d tabs over %d rows, %d rows a page, two faces.%s",
			model:GetFullName(),
			x,
			ground,
			z,
			#LeaderboardConfig.List,
			math.ceil(#LeaderboardConfig.List / columns),
			NAMES.RowsShown,
			arguments.Preview and " Front page filled with preview rows." or ""
		))
	end,
} :: Types.ScriptModule
