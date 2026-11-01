--[[
	BuildPlayMenuV2: Command Runner command

	Builds `StarterGui.MainUIV2.Pages.PlayMenu`: PLAY on one screen (2026-10-25). Pick the world and
	the car on the same page and press DRIVE, where it used to be three screens (Play, Worlds, Select
	Car). `PagesV2/PlayMenu` is the behaviour; `StartCarConfig.OneScreenPlay` switches back.

	RUN `BuildTeleportV2` AND `BuildStartCarV2` FIRST. Nothing here comes from the kit master: the
	shell (header, globe, checkers, close) is the built Worlds page's, the car card and the green
	button are the built Select Car page's, the labels are the world row's and the check is the
	Workshop swatch's. So the art is the art those screens already ship with, grown text caps and
	all. `Pages.PlayMenu` is destroyed and made again on every run; nothing else is touched.

	    PlayMenu
	      Header{ Title "Play", CloseBtn, Globe }       the Worlds page's
	      Main
	        Hero{ Backdrop, Car, CarName, Tagline }
	        WorldsTitle, Worlds{ List{ WorldCard } }   every world across, no scrolling
	        CarsTitle,   Cars{ List{ CarCard }, Note, Hint }   the tray; its list scrolls
	        Search{ TextBox, Icon }                    Select Car's search bar, filters the cars
	        Footer{ Summary{ Thumb, Text }, DriveBtn } `DriveBtn` is `TutorialConfig.PlayMenuPathV2`

	=== DRAWN TO THE OWNER'S RENDER, 2026-10-25 ===============================================

	The first cut laid the two old screens' parts side by side; this one is drawn to the render.
	  • THE HERO is the car and its name on the world's panorama. The navy box that said READY TO
	    DRIVE / CITY / CAR is gone: the footer says both, and the box cost the car half the banner.
	  • A WORLD CARD stands up as a tile: the road, a navy band across its foot, the name over the
	    status. The band is a full-card frame whose gradient is clear down to a hard step, so its
	    corners are the card's own without anything having to clip.
	  • ONE PICKED LOOK on both strips (Dylan: "such that both are consistent"): a lime `Rim` with a
	    navy `Edge` outside it and a check `Badge` on the corner, all off until the page lights them.
	    The two strokes are outer, so nothing on the card covers them, and they stack by their own
	    ZIndex. A world card's inner white line and hover ring ride `Gloss`, a clear frame over the
	    picture, because a card's children paint over its own inner strokes.
	  • A CAR CARD is wide: the car on the left, its name and rarity on a navy `Plate`. The SELECTED
	    chip printed across the picture is gone; the badge says it.
	  • THE CARS SIT IN A TRAY, with room for the `Hint` the page shows while the only car is the free
	    one. The search is hidden until the cars overflow the tray.

	THE WORLD ROW IS A FRAME, NOT A ScrollingFrame. Every world fits across by construction (the page
	narrows the cards to make them), and a scrolling frame clips, which would cut the badge and the
	hover swell off the cards' tops.

	Every box is in SCALE of its parent; the page code sizes the cards in pixels at runtime, because a
	scaled child of a ScrollingFrame resolves against the canvas (see `KitPage`'s header).
]]

local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local PAGE_NAME = "PlayMenu" -- StartCarConfig.PlayPageName
local NAVY = Color3.fromRGB(2, 30, 56)

--- The page is bigger than Worlds' square: two strips of cards and a hero banner need the width.
local PAGE_SIZE = UDim2.fromScale(0.6, 0.86)
local PAGE_ASPECT = 1.25

--- `PagesV2/PlayMenu`'s CAR_ASPECT, the car card's width over its height: the sunray is fitted to it.
local CAR_ASPECT = 2.5
--- The picked rim, top to bottom: the render's lime.
local LIME_TOP = Color3.fromRGB(176, 246, 64)
local LIME_BOTTOM = Color3.fromRGB(64, 204, 24)
--- The car tray: the panel's blue, washed out on the white body.
local TRAY = Color3.fromRGB(214, 236, 255)
--- The hint's ink on the tray: the kit blue, softened, so it reads as a note rather than a button.
local HINT_INK = Color3.fromRGB(64, 122, 204)
--- The swatch's check, for a place whose Workshop screen was never built.
local CHECK_IMAGE = "rbxassetid://117799429050882"
--- Where a world card's navy band starts, as a share of the card's height from its top.
local BAND_TOP = 0.56

local function child(parent: Instance, path: { string }): Instance?
	local node: Instance? = parent
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return node
end

--- A clone with its own text caps taken off: every box here is a new size, and `TextScaled` fills it.
local function copy(source: Instance, name: string, parent: Instance): any
	local made = source:Clone()
	made.Name = name
	for _, d in made:GetDescendants() do
		if d:IsA("UITextSizeConstraint") then
			d:Destroy()
		end
	end
	local own = made:FindFirstChildOfClass("UITextSizeConstraint")
	if own then
		own:Destroy()
	end
	made.Parent = parent
	return made
end

local function place(gui: GuiObject, anchor: Vector2, position: UDim2, size: UDim2)
	gui.AnchorPoint = anchor
	gui.Position = position
	gui.Size = size
end

local function corner(parent: Instance, radius: number)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(radius, 0)
	round.Parent = parent
end

--- A ScaledSize stroke, the kit's kind: it holds its weight at any card size.
local function stroke(parent: Instance, name: string, thickness: number, colour: Color3, outer: boolean, z: number): UIStroke
	local line = Instance.new("UIStroke")
	line.Name = name
	line.Thickness = thickness
	line.Color = colour
	line.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	line.BorderStrokePosition = if outer then Enum.BorderStrokePosition.Outer else Enum.BorderStrokePosition.Inner
	line.ZIndex = z
	line.Parent = parent
	return line
end

--[[ The size `TextScaled` may grow a label to, which the page sets off the card's height at runtime.
	Named `Ceiling` because `KitPage.scaleTextCaps` leaves a constraint called that alone. ]]
local function ceiling(label: Instance)
	local cap = Instance.new("UITextSizeConstraint")
	cap.Name = "Ceiling"
	cap.MaxTextSize = 24
	cap.Parent = label
end

--[[ The picked look, the same on both strips (header). `badgeX` is the badge centre's share of the
	card's width, so a tall card and a wide one hang it the same distance in from the corner. ]]
local function dressPicked(card: GuiObject, check: string, badgeX: number)
	local rim = stroke(card, "Rim", 0.05, Color3.new(1, 1, 1), true, 3)
	rim.Enabled = false
	local lime = Instance.new("UIGradient")
	lime.Rotation = 90
	lime.Color = ColorSequence.new(LIME_TOP, LIME_BOTTOM)
	lime.Parent = rim
	stroke(card, "Edge", 0.08, NAVY, true, 2).Enabled = false

	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.SizeConstraint = Enum.SizeConstraint.RelativeYY
	place(badge, Vector2.new(0.5, 0.5), UDim2.fromScale(badgeX, 0.06), UDim2.fromScale(0.3, 0.3))
	badge.BackgroundColor3 = Color3.new(1, 1, 1)
	badge.Visible = false
	badge.ZIndex = 8
	corner(badge, 0.5)
	stroke(badge, "UIStroke", 0.09, NAVY, true, 1)
	--- What the page pops when a card is newly picked.
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = badge
	local mark = Instance.new("ImageLabel")
	mark.Name = "Check"
	mark.Image = check
	mark.BackgroundTransparency = 1
	mark.ScaleType = Enum.ScaleType.Fit
	place(mark, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.53), UDim2.fromScale(0.74, 0.74))
	mark.ZIndex = 9
	mark.Parent = badge
	badge.Parent = card
end

--[[ A horizontal strip of cards, `<name>.List`. Padding and the canvas are the page's job, in pixels.
	`scrolls` makes the list a ScrollingFrame with its bar hidden (the kit draws none on its lists; a
	swipe or the wheel moves it), else a plain Frame the cards can reach out of (header).
	IN A HOLDER FRAME because `KitPage` adopts the first ScrollingFrame directly under `Main` as its
	own list and takes its children away as row templates. ]]
local function strip(name: string, parent: Instance, y: number, height: number, scrolls: boolean): GuiObject
	local holder = Instance.new("Frame")
	holder.Name = name
	place(holder, Vector2.new(0.5, 0), UDim2.fromScale(0.5, y), UDim2.fromScale(0.95, height))
	holder.BackgroundTransparency = 1
	holder.Parent = parent
	local list: GuiObject
	if scrolls then
		local scroller = Instance.new("ScrollingFrame")
		scroller.ScrollingDirection = Enum.ScrollingDirection.X
		scroller.ScrollBarThickness = 0
		scroller.AutomaticCanvasSize = Enum.AutomaticSize.None
		scroller.CanvasSize = UDim2.new()
		scroller.ClipsDescendants = true
		scroller.Selectable = false
		list = scroller
	else
		list = Instance.new("Frame")
	end
	list.Name = "List"
	place(list, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1))
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = list
	list.Parent = holder
	return list
end

local function build(): (boolean, string)
	local screen = StarterGui:FindFirstChild(SCREEN_NAME)
	local pages = screen and screen:FindFirstChild("Pages")
	local worlds = pages and pages:FindFirstChild("Teleport")
	local cars = pages and pages:FindFirstChild("StartCar")
	if not (worlds and cars) then
		return false, "Pages.Teleport and Pages.StartCar must be built first (BuildTeleportV2, BuildStartCarV2)."
	end
	local row = child(worlds, { "Main", "ScrollingFrame", "WorldRow" })
	local carList = cars:FindFirstChild("Main") and cars.Main:FindFirstChildOfClass("ScrollingFrame")
	local carCard = carList and carList:FindFirstChild("CarCard")
	local face = carCard and carCard:FindFirstChild("Face")
	local equip = carCard and child(carCard, { "Btns", "EquipBtn" })
	local playBtn = row and child(row, { "Btns", "PlayBtn" })
	local lockIcon = row and child(row, { "Btns", "DisabledBtn", "Icon" })
	local statusIcon = row and row:FindFirstChild("StatusIcon")
	if not (row and face and equip and playBtn and lockIcon and statusIcon) then
		return false, "The built Worlds row or Select Car card is missing a part; re-run their builders."
	end
	local rowTitle, rowStatus, rowImage = row:FindFirstChild("Title"), row:FindFirstChild("Status"), row:FindFirstChild("Image")
	--- The Workshop swatch's check (header). Only its image is wanted; the badge is drawn here.
	local swatchCheck = child(screen, { "Screens", "Workshop", "Main", "List", "SwatchTemplate", "Check" })
	local check = if swatchCheck and swatchCheck:IsA("ImageLabel") then swatchCheck.Image else CHECK_IMAGE

	local old = pages:FindFirstChild(PAGE_NAME)
	if old then
		old:Destroy()
	end

	--- The shell: the Worlds page minus its list.
	local page = worlds:Clone()
	page.Name = PAGE_NAME
	page.Visible = false
	page.Size = PAGE_SIZE
	local aspect = page:FindFirstChildOfClass("UIAspectRatioConstraint")
	if aspect then
		aspect.AspectRatio = PAGE_ASPECT
	end
	local title = child(page, { "Header", "Title" })
	if title and title:IsA("TextLabel") then
		title.Text = "Play"
	end
	--- The header keeps about the Worlds page's pixel height (this page is ~9% taller on 16:9).
	local header, main = page:FindFirstChild("Header"), page:FindFirstChild("Main")
	if header and header:IsA("GuiObject") then
		header.Size = UDim2.fromScale(header.Size.X.Scale, header.Size.Y.Scale * 0.92)
		--- Raised so the globe (1.35x the header's height) clears the panel's top border (2026-10-25).
		header.Position = UDim2.fromScale(header.Position.X.Scale, 0.058)
		--- The X is sized in scale of a header that is wider here than on Worlds; held square and
		--- pinned to the header's right edge so it is the same button it is on every other page.
		local close = header:FindFirstChild("CloseBtn")
		if close and close:IsA("GuiObject") then
			local square = close:FindFirstChildOfClass("UIAspectRatioConstraint") or Instance.new("UIAspectRatioConstraint")
			square.AspectRatio = 1
			square.Parent = close
			close.AnchorPoint = Vector2.new(1, 0.5)
			close.Position = UDim2.fromScale(1, close.Position.Y.Scale)
		end
	end
	if main and main:IsA("GuiObject") then
		main.Size = UDim2.fromScale(main.Size.X.Scale, 0.86)
		main.Position = UDim2.fromScale(0.5, 0.55)
	end
	local oldList = main and main:FindFirstChildOfClass("ScrollingFrame")
	if oldList then
		oldList:Destroy()
	end

	-- === Hero ===============================================================
	local hero = Instance.new("Frame")
	hero.Name = "Hero"
	place(hero, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.02), UDim2.fromScale(0.95, 0.225))
	hero.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
	hero.ClipsDescendants = true
	hero.Parent = main
	corner(hero, 0.08)
	for _, line in row:GetChildren() do
		if line:IsA("UIStroke") then
			line:Clone().Parent = hero
		end
	end
	local backdrop = Instance.new("ImageLabel")
	backdrop.Name = "Backdrop"
	place(backdrop, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1))
	backdrop.BackgroundTransparency = 1
	backdrop.ScaleType = Enum.ScaleType.Crop
	backdrop.ZIndex = 1
	corner(backdrop, 0.08)
	backdrop.Parent = hero
	--- Where the car stands, the left of the banner. The viewport goes in at runtime (`CarViewport.new`).
	local carBox = Instance.new("Frame")
	carBox.Name = "Car"
	place(carBox, Vector2.new(0, 0.5), UDim2.fromScale(0.01, 0.5), UDim2.fromScale(0.56, 1))
	carBox.BackgroundTransparency = 1
	carBox.ZIndex = 2
	carBox.Parent = hero
	--- The car's name and the line under it, straight on the art as the render draws them. `CarName`
	--- and not `Name`, which `Hero.Name` would read as the frame's own name.
	local heroName = copy(rowTitle, "CarName", hero)
	place(heroName, Vector2.new(0.5, 0.5), UDim2.fromScale(0.77, 0.42), UDim2.fromScale(0.42, 0.44))
	heroName.TextXAlignment = Enum.TextXAlignment.Center
	heroName.Text = "CAR"
	heroName.ZIndex = 3
	local tagline = copy(rowTitle, "Tagline", hero)
	place(tagline, Vector2.new(0.5, 0.5), UDim2.fromScale(0.77, 0.76), UDim2.fromScale(0.34, 0.2))
	tagline.TextXAlignment = Enum.TextXAlignment.Center
	tagline.Text = "Ready to drive"
	tagline.ZIndex = 3

	-- === The two strips =====================================================
	local function sectionTitle(name: string, text: string, y: number)
		local label = copy(rowTitle, name, main)
		place(label, Vector2.new(0, 0.5), UDim2.fromScale(0.03, y), UDim2.fromScale(0.5, 0.05))
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = text
	end
	sectionTitle("WorldsTitle", "CHOOSE WORLD", 0.288)
	local worldStrip = strip("Worlds", main, 0.313, 0.255, false)
	sectionTitle("CarsTitle", "CHOOSE CAR", 0.607)
	local carStrip = strip("Cars", main, 0.632, 0.213, true)
	local tray = carStrip.Parent :: Frame
	tray.BackgroundColor3 = TRAY
	tray.BackgroundTransparency = 0
	corner(tray, 0.14)

	--- Select Car's search bar, at the right end of the cars title, hidden until the page finds more
	--- cars than the tray holds (header). The icon is held square off the bar's height, because this
	--- bar is shorter and narrower than the one it was drawn for.
	local searchBar = child(cars, { "TopBar", "SearchBar" })
	if searchBar then
		local search = copy(searchBar, "Search", main)
		place(search, Vector2.new(1, 0.5), UDim2.fromScale(0.975, 0.607), UDim2.fromScale(0.34, 0.05))
		search.ZIndex = 3
		search.Visible = false
		local icon = search:FindFirstChild("Icon")
		if icon and icon:IsA("GuiObject") then
			icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
			place(icon, Vector2.new(0.5, 0.5), UDim2.fromScale(0.06, 0.5), UDim2.fromScale(0.6, 0.6))
		end
		local box = search:FindFirstChildWhichIsA("TextBox")
		if box then
			place(box, Vector2.new(0, 0.5), UDim2.fromScale(0.13, 0.5), UDim2.fromScale(0.83, 0.62))
			box.Text = ""
			box.PlaceholderText = "Search cars..."
			box.TextXAlignment = Enum.TextXAlignment.Left
			box.ClearTextOnFocus = false
		end
	end
	--- Said over the car strip when the search matches nothing.
	local note = copy(rowTitle, "Note", tray)
	place(note, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.6, 0.3))
	note.TextXAlignment = Enum.TextXAlignment.Center
	note.Text = ""
	note.Visible = false
	note.ZIndex = 3
	--- Said into the tray's empty end while the free car is the only car. The page places and words it.
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.FontFace = (rowTitle :: TextLabel).FontFace
	hint.TextColor3 = HINT_INK
	hint.TextScaled = true
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Text = ""
	place(hint, Vector2.new(0, 0.5), UDim2.fromScale(0.4, 0.5), UDim2.fromScale(0.5, 0.5))
	hint.Visible = false
	hint.ZIndex = 2
	hint.Parent = tray

	--- The world card (header): the row's road stood up as a tile, a navy band across its foot.
	local worldCard = Instance.new("Frame")
	worldCard.Name = "WorldCard"
	worldCard.BackgroundTransparency = 1
	worldCard.Size = UDim2.fromOffset(104, 110)
	corner(worldCard, 0.1)
	local function fill(gui: GuiObject, z: number)
		place(gui, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1))
		gui.ZIndex = z
		corner(gui, 0.1)
		gui.Parent = worldCard
	end
	local map = Instance.new("ImageLabel")
	map.Name = "Map"
	map.BackgroundTransparency = 1
	map.ScaleType = Enum.ScaleType.Crop
	fill(map, 1)
	--- Darkens a world you cannot drive yet, under its lock: lightly, so the painting still reads.
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.BackgroundColor3 = NAVY
	dim.BackgroundTransparency = 0.55
	dim.Visible = false
	fill(dim, 2)
	--- The band (header): navy below `BAND_TOP`, clear above it, a hard step between.
	local band = Instance.new("Frame")
	band.Name = "Band"
	band.BackgroundColor3 = NAVY
	fill(band, 3)
	local step = Instance.new("UIGradient")
	step.Rotation = 90
	step.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(BAND_TOP, 1),
		NumberSequenceKeypoint.new(BAND_TOP + 0.004, 0.1),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	step.Parent = band
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.BackgroundTransparency = 1
	fill(gloss, 6)
	--[[ The row picture's white-and-navy border, at the car card's weight: at the row's own 0.06 it
		drew ~10px outside every card and the neighbours ran into each other. The navy is outside the
		card and stays on it; the white is inside, so it goes on `Gloss` over the picture (header),
		with the car card's hover ring. ]]
	for _, line in rowImage:GetChildren() do
		if line:IsA("UIStroke") then
			local made = line:Clone()
			made.Thickness = 0.035
			made.Parent = if made.BorderStrokePosition == Enum.BorderStrokePosition.Inner then gloss else worldCard
		end
	end
	local hover = face:FindFirstChild("Hover")
	if hover then
		hover:Clone().Parent = gloss
	end
	local lock = copy(lockIcon, "Lock", worldCard)
	place(lock, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.3), UDim2.fromScale(0.34, 0.34))
	lock.SizeConstraint = Enum.SizeConstraint.RelativeYY
	lock.ZIndex = 4
	lock.Visible = false
	--- The name wraps onto a second line under the page's ceiling rather than shrinking (FOREST /
	--- MOUNTAINS), so its box is two lines tall and stands on the status line.
	local name = copy(rowTitle, "Title", worldCard)
	place(name, Vector2.new(0.5, 1), UDim2.fromScale(0.5, 0.82), UDim2.fromScale(0.92, 0.3))
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextYAlignment = Enum.TextYAlignment.Bottom
	name.TextWrapped = true
	name.ZIndex = 5
	ceiling(name)
	--- The status line: the row's glyph and its status side by side, centred as one. The page sizes
	--- the type and shows the glyph (the banknote) in front of a price.
	local line = Instance.new("Frame")
	line.Name = "StatusLine"
	place(line, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.89), UDim2.fromScale(0.92, 0.14))
	line.BackgroundTransparency = 1
	line.ZIndex = 5
	line.Parent = worldCard
	local lineLayout = Instance.new("UIListLayout")
	lineLayout.FillDirection = Enum.FillDirection.Horizontal
	lineLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	lineLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	lineLayout.SortOrder = Enum.SortOrder.LayoutOrder
	lineLayout.Parent = line
	local glyph = copy(statusIcon, "Icon", line)
	place(glyph, Vector2.zero, UDim2.new(), UDim2.fromScale(1, 0.92))
	glyph.LayoutOrder = 1
	glyph.Visible = false
	glyph.ZIndex = 5
	local glyphShape = glyph:FindFirstChildOfClass("UIAspectRatioConstraint") or Instance.new("UIAspectRatioConstraint")
	glyphShape.DominantAxis = Enum.DominantAxis.Height
	glyphShape.Parent = glyph
	local status = copy(rowStatus, "Status", line)
	place(status, Vector2.zero, UDim2.new(), UDim2.fromScale(0.6, 1))
	status.LayoutOrder = 2
	status.TextScaled = false
	status.TextSize = 12
	status.TextWrapped = false
	status.TextXAlignment = Enum.TextXAlignment.Center
	status:SetAttribute("IconShift", nil)
	status.ZIndex = 5
	dressPicked(worldCard, check, 0.94)
	--- The press: the world row's own Play button, stretched invisible over the card, so it keeps
	--- the tag, the `Action` and the hover that `WorldController` already answers.
	local press = playBtn:Clone()
	press.Name = "Press"
	for _, d in press:GetChildren() do
		d:Destroy()
	end
	place(press, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1))
	press.BackgroundTransparency = 1
	press.Text = ""
	press.ZIndex = 10
	press.Parent = worldCard
	worldCard.Parent = worldStrip

	--- The car card: Select Car's face without its own DRIVE (the footer's is the one press), laid
	--- out wide (header). Its old picked look, the green `Rim` and the SELECTED chip, makes way for
	--- the shared one.
	local car = face:Clone()
	car.Name = "CarCard"
	car.Size = UDim2.fromOffset(220, 100)
	car.Position = UDim2.new()
	car.AnchorPoint = Vector2.zero
	for _, gone in { "Selected", "Rim" } do
		local part = car:FindFirstChild(gone)
		if part then
			part:Destroy()
		end
	end
	local icon = car:FindFirstChild("Icon")
	if icon and icon:IsA("GuiObject") then
		place(icon, Vector2.new(0, 0.5), UDim2.fromScale(0.02, 0.52), UDim2.fromScale(0.54, 0.94))
	end
	--- The sunray stands behind the car rather than the card's middle, at the kit's fitted size for
	--- this shape (`ArcadeKit.fit`: a square of 1.18 card widths, or 1.345 heights if that is more).
	local sunray = child(car, { "BG", "Sunray" })
	if sunray and sunray:IsA("GuiObject") then
		local side = math.max(1.345, 1.18 * CAR_ASPECT)
		place(sunray, Vector2.new(0.5, 0.5), UDim2.fromScale(0.3, 0.5), UDim2.fromScale(side / CAR_ASPECT, side))
	end
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	place(plate, Vector2.new(1, 0.5), UDim2.fromScale(0.97, 0.5), UDim2.fromScale(0.4, 0.78))
	plate.BackgroundColor3 = NAVY
	plate.BackgroundTransparency = 0.3
	plate.ZIndex = 2
	corner(plate, 0.22)
	plate.Parent = car
	local carTitle, carRarity = car:FindFirstChild("Title"), car:FindFirstChild("Rarity")
	for _, label in { carTitle, carRarity } do
		if label and label:IsA("TextLabel") then
			local cap = label:FindFirstChildOfClass("UITextSizeConstraint")
			if cap then
				cap:Destroy()
			end
			ceiling(label)
			label.TextXAlignment = Enum.TextXAlignment.Center
			label.ZIndex = 3
		end
	end
	--- The name wraps onto a second line rather than shrinking (the page writes it with plain
	--- spaces), so its box is two lines tall and stands on the rarity.
	if carTitle and carTitle:IsA("TextLabel") then
		place(carTitle, Vector2.new(0.5, 1), UDim2.fromScale(0.77, 0.6), UDim2.fromScale(0.36, 0.42))
		carTitle.TextWrapped = true
		carTitle.TextYAlignment = Enum.TextYAlignment.Bottom
	end
	if carRarity and carRarity:IsA("GuiObject") then
		place(carRarity, Vector2.new(0.5, 0.5), UDim2.fromScale(0.77, 0.71), UDim2.fromScale(0.34, 0.17))
	end
	--[[ Drawn the right way up already. `CarCardDress` swaps the kit card's two lines once (the kit
		put the rarity on top), on a card without this mark; this card's are where they belong. ]]
	car:SetAttribute("IdentitySwapped", true)
	dressPicked(car, check, 1 - 0.06 / CAR_ASPECT)
	car.Parent = carStrip

	-- === Footer =============================================================
	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	place(footer, Vector2.new(0.5, 1), UDim2.fromScale(0.5, 0.978), UDim2.fromScale(0.95, 0.105))
	footer.BackgroundTransparency = 1
	footer.Parent = main
	local summary = Instance.new("Frame")
	summary.Name = "Summary"
	place(summary, Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5), UDim2.fromScale(0.6, 1))
	summary.BackgroundColor3 = Color3.fromRGB(19, 93, 253)
	corner(summary, 0.2)
	for _, line in row:GetChildren() do
		if line:IsA("UIStroke") then
			line:Clone().Parent = summary
		end
	end
	summary.Parent = footer
	local thumb = Instance.new("ImageLabel")
	thumb.Name = "Thumb"
	place(thumb, Vector2.new(0, 0.5), UDim2.fromScale(0.02, 0.5), UDim2.fromScale(1.5, 0.8))
	thumb.SizeConstraint = Enum.SizeConstraint.RelativeYY
	thumb.BackgroundTransparency = 1
	thumb.ScaleType = Enum.ScaleType.Crop
	corner(thumb, 0.15)
	thumb.Parent = summary
	local text = copy(rowTitle, "Text", summary)
	place(text, Vector2.new(0, 0.5), UDim2.fromScale(0.24, 0.5), UDim2.fromScale(0.73, 0.6))
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Text = "CITY  •  CAR"
	local drive = copy(equip, "DriveBtn", footer)
	place(drive, Vector2.new(1, 0.5), UDim2.fromScale(1, 0.5), UDim2.fromScale(0.38, 1))
	local caption = drive:FindFirstChild("Title")
	if caption and caption:IsA("TextLabel") then
		caption.Text = "DRIVE"
		place(caption, Vector2.new(0.5, 0.5), UDim2.fromScale(0.58, 0.5), UDim2.fromScale(0.6, 0.62))
	end
	local driveGlyph = copy(child(playBtn, { "Icon" }) :: Instance, "Icon", drive)
	place(driveGlyph, Vector2.new(0.5, 0.5), UDim2.fromScale(0.2, 0.5), UDim2.fromScale(0.5, 0.5))
	driveGlyph.SizeConstraint = Enum.SizeConstraint.RelativeYY
	driveGlyph.Visible = true -- the Worlds page hides its glyphs until painted; this one is always on

	page.Parent = pages
	return true, string.format("Built %s.Pages.%s from the Worlds page and the Select Car card.", SCREEN_NAME, PAGE_NAME)
end

return {
	Description = "Build StarterGui.MainUIV2.Pages.PlayMenu (PLAY on one screen: world tiles, car tray, hero, DRIVE) out of the built Worlds and Select Car pages. Rebuilds the page every run.",
	Tags = { "UI", "NewUI" },
	AutoRecordChanges = true,

	Arguments = {} :: Types.ArgumentType,

	build = build,

	Run = function(props: Types.Props, _arguments: Types.ArgumentResult)
		local out = props:Output()
		local ok, message = build()
		if ok then
			out:print(message)
		else
			out:warn(message)
		end
	end,
} :: any
