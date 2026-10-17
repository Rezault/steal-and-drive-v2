--[[
	BuildTeleportV2: Command Runner command

	Builds `StarterGui.MainUIV2.Pages.Teleport` (the world select screen) out of the Cartoony Kit's
	`TeleportUI`. Phase 3 of `docs/NewUI-Migration-Plan.md`; the running record is
	`docs/NewUI-Migration-Notes.md`.

	Run `BuildMainUIV2` first: this fills in a screen that already exists rather than creating one.
	`Pages.Teleport` is destroyed and made again on every run, and nothing else under `Pages` is
	touched, so it is safe beside the other Phase 3 commands and safe to re-run.

	The page is still called `Teleport` because `WorldConfig.PageName` is, and that string is what
	the HUD cell, the Play button and the tutorial all open. It has not teleported anybody for a
	long time: a press picks the world and hands over to the car picker.

	=== THE KIT'S ROW IS A WORLD CARD WITH THREE LABELS CHANGED ===============================

	`TeleportUI` is a vertical list, and one row of it is:

	    Template
	      Image{ Map }      a square picture in a rim
	      Name              "Place Name"
	      Price             "Owned" or "$2500", in the kit's green
	      Btns              TeleportBtn (blue) and PurchaseBtn (green), one showing at a time

	Which is every fact the shipping carousel card carries: the road's picture, its name, whether
	it is yours, what it costs, and a press that either plays it or buys it. The artist even drew
	the two presses our world screen has, in two colours, so the one-button-four-captions trick the
	shipping card needed goes away.

	SO NOTHING ABOUT THE ROW'S LAYOUT CHANGES. It is renamed, one button is added, and a badge goes
	on the picture.

	=== WHAT IS RENAMED, AND WHY ==============================================================

	  • `Name` -> `Title`. NOT OPTIONAL: every Instance has a `Name` PROPERTY, and an instance's
	    property wins over its child, so `row.Name` answers the string "Template" and the label is
	    unreachable by dot. Same trap as the Cars page's `Active`, one level more basic.
	  • `Price` -> `Status`. It carries "Owned", "You are here", a price or a requirement, so
	    calling it a price would be wrong four times out of five.
	  • `TeleportBtn` -> `PlayBtn` and `PurchaseBtn` -> `BuyBtn`, after what they say.
	  • `Template` -> `WorldRow`. The page stamps one per world and names each `World<n>`, which is
	    the stable name `TutorialConfig.TeleportPathV2` walks.

	=== WHAT IS ADDED =========================================================================

	  • `DisabledBtn`, the kit's spent grey, for a world you cannot press yet: one whose previous
	    road is not finished, and one whose price your wallet cannot meet. `TeleportUI` never drew
	    that state, so it is borrowed from `UpgradesUI`, whose row is this row's twin (same
	    `Btns` box to a percent) and whose `DisabledBtn` is the same grey Frame Quest, Settings and
	    the market all use. Its caption and its slash are set to the Teleport buttons' own
	    proportions, so the three faces are one pill in three states. A Frame and not a button, so
	    a world that cannot be pressed has nothing under the cursor or the gamepad highlight.
	  • `Weather`, on the picture: the event's glyph over the picture's lower corner, and the
	    mutation's multiplier in the row's own outlined type under it. The shipping card wears it as
	    a pill across its thumbnail, and it is the only thing in the game that answers "where is the
	    storm" (see `WeatherConfig.StartedEvent`), so losing it in a re-skin is not an option. The
	    row has no free band for a pill, and the picture is the right address anyway: the weather is
	    a fact about that road.
	  • `Action = TeleportToWorld` (`WorldConfig.TeleportAction`) on `PlayBtn` AND `BuyBtn`. That is
	    the whole press: `Components/Button` publishes it and `WorldController` resolves the world
	    off the row's `World` attribute and decides whether the press plays, asks to confirm or
	    buys. Both buttons carry it because the controller, not the button, decides which of those
	    it is.

	=== WHAT IS REMOVED =======================================================================

	  • `IslandTitle`, the section headings. Worlds are bought in order, so a player's list is
	    always the worlds they own followed by the ones they do not, and a heading at that boundary
	    would say what every row's status line already says. Without them all five worlds fit the
	    window with no scrolling, which on a screen that asks "where" is worth more than a heading.
	  • The kit's `Padding` spacer row. It becomes the list's BOTTOM PADDING, set equal to the top
	    one: the same margin under the last row, without the layout gap a spacer ROW brings with
	    it. That gap is the difference between five worlds fitting at 1080p and scrolling by ten
	    pixels.
	  • The spare `Template` rows.

	=== ALEAFO'S CARDS, 2026-09-30 ============================================================

	Aleafo painted a card per world and a mockup of this page wearing them (Discord, 2026-09-29).
	The cards are cut into two pictures (`UIAssets.WorldCards`) and the row is re-dressed to hold
	them, keeping its rims, type and buttons:

	  • `Backdrop`, the world's panorama, behind everything on the row and washed toward the row's
	    white so the type still reads over it. Its left end is a mirrored pad that sits under the
	    picture, so the painting starts where the road ends.
	  • The picture goes LANDSCAPE (3:2), which is the shape the cards paint the road at, and the
	    name and status line move right to clear it.
	  • An `Icon` in front of the status line (a pin, the banknote or a lock, chosen by the page)
	    and one on the Play and grey faces (a triangle, a lock). Each is hidden until the page
	    says otherwise.
	  • The globe beside the title.

	=== WHAT IS LEFT ALONE ====================================================================

	Both kit buttons and the kit's colours. The picture is `Crop` so the road fills its box rather
	than being squeezed into it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)
local KitGrowth = require(ReplicatedStorage.shared.Modules.KitGrowth)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage

local PAGE_NAME = "Teleport" -- WorldConfig.PageName
local KIT_FRAME = "TeleportUI"

--- Where the grey face is borrowed from. See the header.
local DISABLED_SOURCE_FRAME = "UpgradesUI"

--- `WorldConfig.TeleportAction`. Typed here rather than required, because a Command Runner module
--- reads the config the plugin VM has cached, which does not notice a Rojo sync.
local ACTION_ATTRIBUTE = "Action"
local TELEPORT_ACTION = "TeleportToWorld"

--- The kit's names, and ours. Every one of ours is a path in `PagesV2/Teleport`.
local KIT_ROW = "Template"
local ROW_NAME = "WorldRow"
local KIT_TITLE = "Name"
local TITLE_NAME = "Title"
local KIT_STATUS = "Price"
local STATUS_NAME = "Status"
local KIT_PLAY = "TeleportBtn"
local PLAY_NAME = "PlayBtn"
local KIT_BUY = "PurchaseBtn"
local BUY_NAME = "BuyBtn"
local DISABLED_NAME = "DisabledBtn"
local KIT_SECTION = "IslandTitle"
local KIT_SPACER = "Padding"

local PICTURE = "Image"
local MAP = "Map"
local WEATHER_NAME = "Weather"
local WEATHER_ICON = "Icon"
local WEATHER_MULTIPLIER = "Multiplier"

--[[ The badge, as fractions of the picture's square box.

	NEARLY THREE QUARTERS OF THE PICTURE, which at 1080p is a glyph about 48px across on a 65px
	road shot. The first cut was 0.58 and it lost: in the flag-on playtest the glyph read as a
	speck on the road and its multiplier was the smallest type on the screen. It hangs past the
	picture's lower right corner by a few percent, like a notification badge, and no further, so
	it stays inside the gap the artist left before the row's text starts. ]]
local WEATHER_SIZE = 0.72
local WEATHER_OVERHANG = 1.06

--[[ The multiplier, as fractions of the badge: its lower half, pushed a little past its right edge,
	right aligned. "x2" in the row's own outlined type, sat on the glyph's corner the way a count
	sits on an icon.

	THE DROP IS SMALL ON PURPOSE. The first cut pushed the label out by the same margin again on top
	of the badge's own overhang, and the two added up to a number sitting ON the row's bottom rim.
	Measured with these values, its bottom edge is inside the row with the rim clear. ]]
local MULTIPLIER_WIDTH = 1.2
local MULTIPLIER_HEIGHT = 0.5
local MULTIPLIER_OVERHANG = 1.1
local MULTIPLIER_DROP = 1.04

--[[ Aleafo's row, as fractions of the row (see the header). The row is 6.87 times as wide as it is
	tall, so a 3:2 picture 0.78 of its height is 0.170 of its width; it starts one sixtieth in,
	about the kit's own margin, and the type starts just past it. ]]
local ROW_ASPECT = 6.874 -- WorldRow's AbsoluteSize, 486x70.7, measured in the edit viewport
local BACKDROP_NAME = "Backdrop"
local BACKDROP_WASH = 0.35 -- ImageTransparency over the row's white
local PICTURE_HEIGHT = 0.78
local PICTURE_WIDTH = 0.170
local PICTURE_LEFT = 0.017
local TEXT_LEFT = 0.215
local TEXT_WIDTH = 0.47

--[[ The status line's glyph, as fractions of the line: a little taller than the type, in a box a
	third wider than tall so the banknote (1.67:1) is not shrunk to a speck beside the square pin.
	The page slides the line right by the box and a small gap while the glyph shows. ]]
local ICON_NAME = "Icon"
local STATUS_ICON_NAME = "StatusIcon"
local STATUS_ICON_HEIGHT = 1.3
local STATUS_ICON_ASPECT = 1.3
local STATUS_ICON_GAP = 0.008

--- The glyph on the Play and grey faces, as fractions of the face, and where the caption moves to
--- beside it. The page shows it and moves the caption; these are the numbers it moves between.
local FACE_ICON_HEIGHT = 0.52
local FACE_ICON_X = 0.22

--- The globe beside the title, as fractions of the header: bigger than the bar, like the mockup's.
local GLOBE_HEIGHT = 1.35
local GLOBE_X = -0.01
local GLOBE_TITLE_SHIFT = 0.125

local Assets = {
	Globe = 96102056801764, -- UIAssets.WorldsPage.Globe, typed for the same reason as the action
	Play = 116588596716318, -- UIAssets.WorldsPage.Play
	Lock = 89067716038082, -- UIAssets.WorldsPage.Lock
}

--- An ImageLabel for a glyph, fitted in its box, hidden unless `visible`.
local function glyph(name: string, image: number?, visible: boolean): ImageLabel
	local icon = Instance.new("ImageLabel")
	icon.Name = name
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = if image then "rbxassetid://" .. image else ""
	icon.Visible = visible
	return icon
end

--- The kit's own placeholders, so a freshly built page reads as the finished screen in the Explorer.
--- All of them are overwritten on the first paint.
local TITLE_TEXT = "Worlds"
local ROW_TITLE_PLACEHOLDER = "CITY"
local STATUS_PLACEHOLDER = "Owned"
local PLAY_PLACEHOLDER = "Play"
local BUY_PLACEHOLDER = "Buy"
local DISABLED_PLACEHOLDER = "Locked"
local MULTIPLIER_PLACEHOLDER = "x2"

--- The kit template, or nil and a sentence saying which step of the path was missing.
local function findTemplate(): (Instance?, string?)
	local node: Instance = ServerStorage
	for _, step in TEMPLATE_PATH do
		local child = node:FindFirstChild(step)
		if not child then
			return nil, string.format("%s has no child `%s`.", node:GetFullName(), step)
		end
		node = child
	end
	local screen = node:FindFirstChildWhichIsA("ScreenGui")
	if not screen then
		return nil, string.format("%s holds no ScreenGui.", node:GetFullName())
	end
	local container = screen:FindFirstChild("Container")
	if not container then
		return nil, string.format("%s has no `Container` of frames.", screen:GetFullName())
	end
	return container, nil
end

--- A child's caption, whichever of the kit's buttons it is.
local function setCaption(button: Instance?, text: string)
	local title = button and button:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = text
	end
end

--[[ The UIStrokes that draw a kit button's rim. On the two Teleport buttons they sit inside a
	`Container` frame, and on the borrowed grey face they sit on the button itself, so both places
	are looked in. ]]
local function rimStrokes(button: Instance): { UIStroke }
	local strokes = {}
	local holder = button:FindFirstChild("Container") or button
	for _, child in holder:GetChildren() do
		if child:IsA("UIStroke") then
			table.insert(strokes, child)
		end
	end
	if #strokes == 0 then
		for _, child in button:GetChildren() do
			if child:IsA("UIStroke") then
				table.insert(strokes, child)
			end
		end
	end
	return strokes
end

--[[ Make the borrowed grey face the same pill as the two it sits beside.

	`UpgradesUI` draws its grey at a slightly different caption height, rim weight and slash
	length, which is right for its row and reads as a different button next to ours. Every number
	is read off `PlayBtn`, so the three faces agree to the artist's own values on this row. ]]
local function matchFace(face: GuiObject, reference: GuiObject)
	face.AnchorPoint = reference.AnchorPoint
	face.Position = reference.Position
	face.Size = reference.Size
	face.ZIndex = reference.ZIndex

	local faceTitle = face:FindFirstChild("Title")
	local referenceTitle = reference:FindFirstChild("Title")
	if faceTitle and faceTitle:IsA("GuiObject") and referenceTitle and referenceTitle:IsA("GuiObject") then
		faceTitle.AnchorPoint = referenceTitle.AnchorPoint
		faceTitle.Position = referenceTitle.Position
		faceTitle.Size = referenceTitle.Size
	end

	local faceSlash = face:FindFirstChild("BG") and face.BG:FindFirstChild("Slash")
	local referenceSlash = reference:FindFirstChild("BG") and reference.BG:FindFirstChild("Slash")
	if faceSlash and faceSlash:IsA("GuiObject") and referenceSlash and referenceSlash:IsA("GuiObject") then
		faceSlash.Position = referenceSlash.Position
		faceSlash.Size = referenceSlash.Size
	end

	local thickness = rimStrokes(reference)[1]
	if thickness then
		for _, stroke in rimStrokes(face) do
			stroke.Thickness = thickness.Thickness
		end
	end

	local corner = face:FindFirstChildOfClass("UICorner")
	local referenceCorner = reference:FindFirstChildOfClass("UICorner")
	if corner and referenceCorner then
		corner.CornerRadius = referenceCorner.CornerRadius
	end
end

return {
	Description = "Build StarterGui.MainUIV2.Pages.Teleport (the world select screen) from the Cartoony Kit's TeleportUI: one WorldRow with Play, Buy and a borrowed grey DisabledBtn, a weather badge on the picture, and no section headings. Rebuilds the page every run.",
	Tags = { "UI", "NewUI" },
	AutoRecordChanges = true,

	Arguments = {} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		local screen = StarterGui:FindFirstChild(SCREEN_NAME)
		local pages = screen and screen:FindFirstChild("Pages")
		if not (pages and pages:IsA("GuiObject")) then
			out:error(string.format("No StarterGui.%s.Pages. Run BuildMainUIV2 first.", SCREEN_NAME))
			return
		end

		local container, why = findTemplate()
		if not container then
			out:error(string.format("The kit is not where it should be: %s", why))
			return
		end

		local kitFrame = container:FindFirstChild(KIT_FRAME)
		if not kitFrame then
			out:error(string.format("%s has no `%s` to build from.", container:GetFullName(), KIT_FRAME))
			return
		end

		--- Read before anything is destroyed, so a kit missing the grey face stops the build with the
		--- page it already had still standing.
		local greySource = container:FindFirstChild(DISABLED_SOURCE_FRAME)
		local greyRow = greySource and greySource:FindFirstChild("Main")
		greyRow = greyRow and greyRow:FindFirstChildOfClass("ScrollingFrame")
		greyRow = greyRow and greyRow:FindFirstChild(KIT_ROW)
		local grey = greyRow and greyRow:FindFirstChild("Btns")
		grey = grey and grey:FindFirstChild(DISABLED_NAME)
		if not (grey and grey:IsA("GuiObject")) then
			out:error(string.format("The kit's %s has no `%s` row with a `%s` to borrow.", DISABLED_SOURCE_FRAME, KIT_ROW, DISABLED_NAME))
			return
		end

		local existing = pages:FindFirstChild(PAGE_NAME)
		if existing then
			existing:Destroy()
		end

		local page = kitFrame:Clone()
		page.Name = PAGE_NAME

		local main = page:FindFirstChild("Main")
		local list = main and main:FindFirstChildOfClass("ScrollingFrame")
		if not (main and main:IsA("GuiObject") and list) then
			out:error(string.format("The kit's %s has no `Main.ScrollingFrame`; there is no list to fill.", KIT_FRAME))
			page:Destroy()
			return
		end

		-- === The header =====================================================
		local header = page:FindFirstChild("Header")
		local headerTitle = header and header:FindFirstChild("Title")
		if headerTitle and headerTitle:IsA("TextLabel") then
			headerTitle.Text = TITLE_TEXT
		else
			out:warn(string.format("The kit's %s has no `Header.Title`; the page keeps no heading.", KIT_FRAME))
		end

		-- === The list's other rows ==========================================
		local kept: GuiObject? = nil
		local spares, sections = 0, 0
		for _, child in list:GetChildren() do
			if child.Name == KIT_SECTION then
				sections += 1
				child:Destroy()
			elseif child.Name == KIT_ROW and child:IsA("GuiObject") then
				if kept then
					spares += 1
					child:Destroy()
				else
					kept = child
				end
			end
		end

		if not kept then
			out:error(string.format("The kit's %s list has no `%s` row to build from.", KIT_FRAME, KIT_ROW))
			page:Destroy()
			return
		end

		--[[ The spacer becomes padding. See the header: a spacer ROW costs the layout's gap as well as
			its own height, and the bottom margin should be the top one. ]]
		local spacer = list:FindFirstChild(KIT_SPACER)
		local padding = list:FindFirstChildOfClass("UIPadding")
		if spacer then
			spacer:Destroy()
		end
		if padding then
			padding.PaddingBottom = padding.PaddingTop
		else
			out:warn("The kit's list has no UIPadding; the last world will sit against the rim.")
		end

		-- === The row ========================================================
		local row = kept :: GuiObject
		row.Name = ROW_NAME

		local title = row:FindFirstChild(KIT_TITLE)
		local status = row:FindFirstChild(KIT_STATUS)
		local btns = row:FindFirstChild("Btns")
		local picture = row:FindFirstChild(PICTURE)
		if not (title and title:IsA("TextLabel") and status and status:IsA("TextLabel") and btns and picture) then
			out:error(string.format("`%s` is missing `%s`, `%s`, `Btns` or `%s`.", ROW_NAME, KIT_TITLE, KIT_STATUS, PICTURE))
			page:Destroy()
			return
		end
		title.Name = TITLE_NAME
		title.Text = ROW_TITLE_PLACEHOLDER
		status.Name = STATUS_NAME
		status.Text = STATUS_PLACEHOLDER

		local map = picture:FindFirstChild(MAP)
		if map and map:IsA("ImageLabel") then
			--- A portrait road shot in a square box: trimmed top and bottom rather than squeezed.
			map.ScaleType = Enum.ScaleType.Crop
		else
			out:warn(string.format("`%s.%s` has no `%s` ImageLabel; rows will have no picture.", ROW_NAME, PICTURE, MAP))
		end

		-- === The buttons ====================================================
		local play = btns:FindFirstChild(KIT_PLAY)
		local buy = btns:FindFirstChild(KIT_BUY)
		if not (play and play:IsA("GuiButton") and buy and buy:IsA("GuiButton")) then
			out:error(string.format("`%s.Btns` is missing `%s` or `%s`.", ROW_NAME, KIT_PLAY, KIT_BUY))
			page:Destroy()
			return
		end
		play.Name = PLAY_NAME
		buy.Name = BUY_NAME
		for _, button in { play, buy } do
			button:SetAttribute(ACTION_ATTRIBUTE, TELEPORT_ACTION)
		end
		setCaption(play, PLAY_PLACEHOLDER)
		setCaption(buy, BUY_PLACEHOLDER)
		play.Visible = true
		buy.Visible = false

		local face = (grey :: GuiObject):Clone()
		face.Name = DISABLED_NAME
		matchFace(face, play)
		face.Visible = false
		setCaption(face, DISABLED_PLACEHOLDER)
		face.Parent = btns

		-- === The weather badge ==============================================
		local badge = Instance.new("Frame")
		badge.Name = WEATHER_NAME
		badge.BackgroundTransparency = 1
		badge.BorderSizePixel = 0
		badge.AnchorPoint = Vector2.new(1, 1)
		badge.Position = UDim2.fromScale(WEATHER_OVERHANG, WEATHER_OVERHANG)
		badge.Size = UDim2.fromScale(WEATHER_SIZE, WEATHER_SIZE)
		--- Over the picture. Sibling ZIndex, so one above the map is enough.
		badge.ZIndex = (if map and map:IsA("GuiObject") then map.ZIndex else 1) + 1
		badge.Visible = false

		local square = Instance.new("UIAspectRatioConstraint")
		square.AspectRatio = 1
		square.Parent = badge

		local icon = Instance.new("ImageLabel")
		icon.Name = WEATHER_ICON
		icon.BackgroundTransparency = 1
		icon.BorderSizePixel = 0
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Size = UDim2.fromScale(1, 1)
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = badge.ZIndex
		icon.Parent = badge

		--- The row's own outlined type, so "x2" is the artist's face, rim and size cap.
		local multiplier = title:Clone()
		multiplier.Name = WEATHER_MULTIPLIER
		multiplier.Text = MULTIPLIER_PLACEHOLDER
		multiplier.TextXAlignment = Enum.TextXAlignment.Right
		multiplier.TextYAlignment = Enum.TextYAlignment.Bottom
		multiplier.AnchorPoint = Vector2.new(1, 1)
		multiplier.Position = UDim2.fromScale(MULTIPLIER_OVERHANG, MULTIPLIER_DROP)
		multiplier.Size = UDim2.fromScale(MULTIPLIER_WIDTH, MULTIPLIER_HEIGHT)
		multiplier.ZIndex = badge.ZIndex + 1
		multiplier.Parent = badge

		badge.Parent = picture

		-- === Aleafo's cards (see the header) ================================
		--- The picture, landscape. Its square constraint, if the kit ever grows one, would undo that.
		local pictureSquare = picture:FindFirstChildOfClass("UIAspectRatioConstraint")
		if pictureSquare then
			pictureSquare:Destroy()
		end
		if picture:IsA("GuiObject") then
			picture.AnchorPoint = Vector2.new(0, 0.5)
			picture.Position = UDim2.fromScale(PICTURE_LEFT, 0.5)
			picture.Size = UDim2.fromScale(PICTURE_WIDTH, PICTURE_HEIGHT)
		end

		for _, label in { title, status } do
			label.AnchorPoint = Vector2.new(0, 0.5)
			label.Position = UDim2.fromScale(TEXT_LEFT, label.Position.Y.Scale)
			label.Size = UDim2.fromScale(TEXT_WIDTH, label.Size.Y.Scale)
		end

		--- Behind everything on the row: the lowest ZIndex among its siblings, and the row's own corner.
		local backdrop = glyph(BACKDROP_NAME, nil, true)
		backdrop.ScaleType = Enum.ScaleType.Crop
		backdrop.ImageTransparency = BACKDROP_WASH
		backdrop.AnchorPoint = Vector2.new(0.5, 0.5)
		backdrop.Position = UDim2.fromScale(0.5, 0.5)
		backdrop.Size = UDim2.fromScale(1, 1)
		backdrop.ZIndex = 0
		local rowCorner = row:FindFirstChildOfClass("UICorner")
		if rowCorner then
			rowCorner:Clone().Parent = backdrop
		end
		backdrop.Parent = row

		--[[ The status line's glyph: the ROW's child, where the line starts, and not the line's own.
			A UIPadding on the line would move its children with its text, glyph included, so the page
			slides the LINE over by `IconShift` instead while the glyph shows. ]]
		local lineHeight = status.Size.Y.Scale
		local statusIcon = glyph(STATUS_ICON_NAME, nil, false)
		statusIcon.AnchorPoint = Vector2.new(0, 0.5)
		statusIcon.Position = UDim2.fromScale(TEXT_LEFT, status.Position.Y.Scale)
		statusIcon.Size = UDim2.fromScale(1, lineHeight * STATUS_ICON_HEIGHT)
		statusIcon.ZIndex = status.ZIndex
		local statusIconShape = Instance.new("UIAspectRatioConstraint")
		statusIconShape.AspectRatio = STATUS_ICON_ASPECT
		statusIconShape.DominantAxis = Enum.DominantAxis.Height
		statusIconShape.Parent = statusIcon
		statusIcon.Parent = row
		--- The glyph's width as a fraction of the row's, plus the gap. The row is `ROW_ASPECT` heights
		--- wide and nothing is rendered yet, so nothing can be measured.
		status:SetAttribute("IconShift", lineHeight * STATUS_ICON_HEIGHT * STATUS_ICON_ASPECT / ROW_ASPECT + STATUS_ICON_GAP)

		--- A glyph on the Play and grey faces. The Buy face never carries one.
		for _, entry in { { play, Assets.Play }, { face, Assets.Lock } } do
			local button, image = entry[1], entry[2]
			local faceTitle = button:FindFirstChild("Title")
			local faceIcon = glyph(ICON_NAME, image, false)
			faceIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			faceIcon.Position = UDim2.fromScale(FACE_ICON_X, 0.5)
			faceIcon.Size = UDim2.fromScale(1, FACE_ICON_HEIGHT)
			faceIcon.ZIndex = if faceTitle and faceTitle:IsA("GuiObject") then faceTitle.ZIndex else 3
			local faceIconShape = Instance.new("UIAspectRatioConstraint")
			faceIconShape.DominantAxis = Enum.DominantAxis.Height
			faceIconShape.Parent = faceIcon
			faceIcon.Parent = button
		end

		--- The globe, and the title moved over for it.
		if header and headerTitle and headerTitle:IsA("GuiObject") then
			local globe = glyph("Globe", Assets.Globe, true)
			globe.AnchorPoint = Vector2.new(0, 0.5)
			globe.Position = UDim2.fromScale(GLOBE_X, 0.5)
			globe.Size = UDim2.fromScale(1, GLOBE_HEIGHT)
			globe.ZIndex = headerTitle.ZIndex
			local globeShape = Instance.new("UIAspectRatioConstraint")
			globeShape.DominantAxis = Enum.DominantAxis.Height
			globeShape.Parent = globe
			globe.Parent = header
			headerTitle.Position = UDim2.new(
				headerTitle.Position.X.Scale + GLOBE_TITLE_SHIFT,
				headerTitle.Position.X.Offset,
				headerTitle.Position.Y.Scale,
				headerTitle.Position.Y.Offset
			)
		end

		--- Bigger than the kit, text caps included. See `Modules/KitGrowth`.
		KitGrowth.apply(page, KitGrowth.Pages)
		page.Parent = pages

		out:print(string.format("Built %s.Pages.%s from the kit's %s.", SCREEN_NAME, PAGE_NAME, KIT_FRAME))
		out:print(
			string.format(
				"Row `%s`: %d spare rows and %d section headings dropped, the spacer folded into the bottom padding. `%s`, `%s`, `%s`, `%s` renamed; `%s` borrowed from %s; `%s` badge on the picture.",
				ROW_NAME,
				spares,
				sections,
				TITLE_NAME,
				STATUS_NAME,
				PLAY_NAME,
				BUY_NAME,
				DISABLED_NAME,
				DISABLED_SOURCE_FRAME,
				WEATHER_NAME
			)
		)

		pcall(function()
			props:SetSelection({ page })
		end)
	end,
} :: Types.ScriptModule
