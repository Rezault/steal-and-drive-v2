--[[
	BuildPlayMenuV2: Command Runner command

	Builds `StarterGui.MainUIV2.Pages.PlayMenu`: PLAY on one screen (2026-10-25). Pick the world and
	the car on the same page and press DRIVE, where it used to be three screens (Play, Worlds, Select
	Car). `PagesV2/PlayMenu` is the behaviour; `StartCarConfig.OneScreenPlay` switches back.

	RUN `BuildTeleportV2` AND `BuildStartCarV2` FIRST. Nothing here comes from the kit master: the
	shell (header, globe, checkers, close) is the built Worlds page's, the car card and the green
	button are the built Select Car page's, and the labels are the world row's. So the art is the
	art those two screens already ship with, grown text caps and all. `Pages.PlayMenu` is destroyed
	and made again on every run; nothing else is touched.

	    PlayMenu
	      Header{ Title "Play", CloseBtn, Globe }       the Worlds page's
	      Main
	        Hero{ Backdrop, Car, Info{ Ready, World, Car } }
	        WorldsTitle, Worlds{ List{ WorldCard } }   a horizontal list; the card is a template
	        CarsTitle,   Cars{ List{ CarCard } }       the Select Car face, minus its DRIVE
	        Search{ TextBox, Icon }                    Select Car's search bar, filters the cars
	        Footer{ Summary{ Thumb, Text }, DriveBtn } `DriveBtn` is `TutorialConfig.PlayMenuPathV2`

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

--[[ A horizontal strip of cards, `<name>.List`. Scrollbar hidden: the kit draws none on its lists,
	and a swipe or the wheel moves it. Padding and canvas are the page's job, in pixels.
	IN A HOLDER FRAME because `KitPage` adopts the first ScrollingFrame directly under `Main` as its
	own list and takes its children away as row templates. ]]
local function strip(name: string, parent: Instance, y: number, height: number): ScrollingFrame
	local holder = Instance.new("Frame")
	holder.Name = name
	place(holder, Vector2.new(0.5, 0), UDim2.fromScale(0.5, y), UDim2.fromScale(0.95, height))
	holder.BackgroundTransparency = 1
	holder.Parent = parent
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	place(list, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1))
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollingDirection = Enum.ScrollingDirection.X
	list.ScrollBarThickness = 0
	list.AutomaticCanvasSize = Enum.AutomaticSize.None
	list.CanvasSize = UDim2.new()
	list.ClipsDescendants = true
	list.Selectable = false
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
	if not (row and face and equip and playBtn) then
		return false, "The built Worlds row or Select Car card is missing a part; re-run their builders."
	end
	local rowTitle, rowStatus, rowImage = row:FindFirstChild("Title"), row:FindFirstChild("Status"), row:FindFirstChild("Image")

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
	place(hero, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.025), UDim2.fromScale(0.95, 0.28))
	hero.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
	hero.ClipsDescendants = true
	hero.Parent = main
	corner(hero, 0.08)
	for _, stroke in row:GetChildren() do
		if stroke:IsA("UIStroke") then
			stroke:Clone().Parent = hero
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
	--- Where the car turns. The viewport goes in at runtime (`CarViewport.new`).
	local carBox = Instance.new("Frame")
	carBox.Name = "Car"
	place(carBox, Vector2.new(0, 0.5), UDim2.fromScale(0.01, 0.5), UDim2.fromScale(0.56, 1))
	carBox.BackgroundTransparency = 1
	carBox.ZIndex = 2
	carBox.Parent = hero
	local info = Instance.new("Frame")
	info.Name = "Info"
	place(info, Vector2.new(1, 0.5), UDim2.fromScale(0.98, 0.5), UDim2.fromScale(0.42, 0.84))
	info.BackgroundColor3 = NAVY
	info.BackgroundTransparency = 0.35
	info.ZIndex = 2
	corner(info, 0.12)
	info.Parent = hero
	local ready = copy(rowTitle, "Ready", info)
	place(ready, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.22), UDim2.fromScale(0.9, 0.3))
	ready.TextXAlignment = Enum.TextXAlignment.Center
	ready.Text = "READY TO DRIVE"
	ready.ZIndex = 3
	for i, name in { "World", "Car" } do
		local line = copy(rowStatus, name, info)
		place(line, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.36 + i * 0.2), UDim2.fromScale(0.86, 0.2))
		line.TextXAlignment = Enum.TextXAlignment.Center
		line.Text = name
		line.ZIndex = 3
		line:SetAttribute("IconShift", nil)
	end

	-- === The two strips =====================================================
	local function sectionTitle(name: string, text: string, y: number)
		local label = copy(rowTitle, name, main)
		place(label, Vector2.new(0, 0.5), UDim2.fromScale(0.03, y), UDim2.fromScale(0.5, 0.05))
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = text
	end
	sectionTitle("WorldsTitle", "CHOOSE WORLD", 0.355)
	local worldStrip = strip("Worlds", main, 0.385, 0.215)
	sectionTitle("CarsTitle", "CHOOSE CAR", 0.635)
	local carStrip = strip("Cars", main, 0.665, 0.2)

	--- Select Car's search bar, beside the cars title. The icon is held square off the bar's height,
	--- because this bar is shorter and narrower than the one it was drawn for.
	local searchBar = child(cars, { "TopBar", "SearchBar" })
	if searchBar then
		local search = copy(searchBar, "Search", main)
		place(search, Vector2.new(0, 0.5), UDim2.fromScale(0.25, 0.635), UDim2.fromScale(0.36, 0.05))
		search.ZIndex = 3
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
	local note = copy(rowTitle, "Note", carStrip.Parent :: Instance)
	place(note, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.6, 0.3))
	note.TextXAlignment = Enum.TextXAlignment.Center
	note.Text = ""
	note.Visible = false
	note.ZIndex = 3

	--- The world card: the row's picture, name and status line stood up as a tile.
	local worldCard = Instance.new("Frame")
	worldCard.Name = "WorldCard"
	worldCard.BackgroundColor3 = Color3.new(1, 1, 1)
	worldCard.Size = UDim2.fromOffset(160, 110)
	corner(worldCard, 0.1)
	--- The row picture's white-and-navy border, at the car card's weight: at the row's own 0.06 it
	--- drew ~10px outside every card and the neighbours ran into each other.
	for _, stroke in rowImage:GetChildren() do
		if stroke:IsA("UIStroke") then
			local made = stroke:Clone()
			made.Thickness = 0.035
			made.Parent = worldCard
		end
	end
	local rim = face:FindFirstChild("Rim")
	if rim then
		local made = rim:Clone()
		made.Enabled = false
		made.Thickness = 0.05
		made.Parent = worldCard
	end
	local map = Instance.new("ImageLabel")
	map.Name = "Map"
	place(map, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1))
	map.BackgroundTransparency = 1
	map.ScaleType = Enum.ScaleType.Crop
	corner(map, 0.1)
	map.Parent = worldCard
	--- Darkens a world you cannot drive yet, under its lock.
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	place(dim, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1))
	dim.BackgroundColor3 = NAVY
	dim.BackgroundTransparency = 0.45
	dim.Visible = false
	dim.ZIndex = 2
	corner(dim, 0.1)
	dim.Parent = worldCard
	local lock = copy(child(row, { "Btns", "DisabledBtn", "Icon" }) :: Instance, "Lock", worldCard)
	place(lock, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.4), UDim2.fromScale(0.3, 0.3))
	lock.SizeConstraint = Enum.SizeConstraint.RelativeYY
	lock.ZIndex = 3
	lock.Visible = false
	local name = copy(rowTitle, "Title", worldCard)
	place(name, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.68), UDim2.fromScale(0.9, 0.24))
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.ZIndex = 4
	local status = copy(rowStatus, "Status", worldCard)
	place(status, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.88), UDim2.fromScale(0.9, 0.17))
	status.TextXAlignment = Enum.TextXAlignment.Center
	status:SetAttribute("IconShift", nil)
	status.ZIndex = 4
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
	press.ZIndex = 5
	press.Parent = worldCard
	worldCard.Parent = worldStrip

	--- The car card: Select Car's face, without its own DRIVE (the footer's is the one press).
	local car = face:Clone()
	car.Name = "CarCard"
	car.Size = UDim2.fromOffset(150, 110)
	car.Position = UDim2.new()
	car.AnchorPoint = Vector2.zero
	car.Parent = carStrip

	-- === Footer =============================================================
	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	place(footer, Vector2.new(0.5, 1), UDim2.fromScale(0.5, 0.975), UDim2.fromScale(0.95, 0.095))
	footer.BackgroundTransparency = 1
	footer.Parent = main
	local summary = Instance.new("Frame")
	summary.Name = "Summary"
	place(summary, Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5), UDim2.fromScale(0.6, 1))
	summary.BackgroundColor3 = Color3.fromRGB(19, 93, 253)
	corner(summary, 0.2)
	for _, stroke in row:GetChildren() do
		if stroke:IsA("UIStroke") then
			stroke:Clone().Parent = summary
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
	local glyph = copy(child(playBtn, { "Icon" }) :: Instance, "Icon", drive)
	place(glyph, Vector2.new(0.5, 0.5), UDim2.fromScale(0.2, 0.5), UDim2.fromScale(0.5, 0.5))
	glyph.SizeConstraint = Enum.SizeConstraint.RelativeYY
	glyph.Visible = true -- the Worlds page hides its glyphs until painted; this one is always on

	page.Parent = pages
	return true, string.format("Built %s.Pages.%s from the Worlds page and the Select Car card.", SCREEN_NAME, PAGE_NAME)
end

return {
	Description = "Build StarterGui.MainUIV2.Pages.PlayMenu (PLAY on one screen: world strip, car strip, hero, DRIVE) out of the built Worlds and Select Car pages. Rebuilds the page every run.",
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
