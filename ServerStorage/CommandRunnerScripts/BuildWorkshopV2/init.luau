--[[
	BuildWorkshopV2: Command Runner command

	Builds `StarterGui.MainUIV2.Screens.Workshop`, the customization bay's screen, out of the Cartoony
	Kit's `UpgradesUI`. Added 2026-09-30, when the placeholder screen `WorkshopController` drew in code
	was moved onto the kit.

	Run `BuildMainUIV2` first: this fills in a shelf that already exists rather than creating one.
	`Screens.Workshop` is destroyed and made again on every run and nothing else on the shelf is
	touched, so it is safe beside the other screen commands and safe to re-run.

	=== A TEMPLATE, NOT A SCREEN ==============================================================

	Nothing draws this where it is built. `Screens` is hidden, and `WorkshopController._buildKit`
	clones it into its own `Workshop` ScreenGui, which keeps the old screen's `DisplayOrder`.

	=== WHY UPGRADESUI =========================================================================

	The kit's upgrades page is already this screen's parts list: a coloured row per upgrade, its name,
	a segmented meter of levels bought, and a price button with a grey twin for "nothing left to buy".
	ENGINE, TRANSMISSION and TIRES are exactly that. REPAIR and PAINT are the same row with a line of
	type where the meter would be. So nothing on the right is drawn: it is the artist's row, sized.

	    Workshop            the kit frame, 1160x740 at 1080p (UpgradesUI is 656x696)
	      Header            Title "WORKSHOP", CloseBtn
	      Showcase          the LEFT column, on the panel's own blue
	        CarName         the header's type, centred
	        Portrait        an empty box the car turns in, `Backdrop` and `Aspect` stamped on it
	        Worth           WORTH $1,345, the header's type under the money `Tint`
	        Condition       CONDITION 87%
	        ConditionBar    the quest row's bar, `Progress` refilled in the kit's pip green
	        ChangeBtn       the row's buy button re-faced in the kit's orange, CHANGE CAR
	      Main              the kit's white body, now the RIGHT column
	        List            the kit's ScrollingFrame, emptied; the controller lays rows out in it
	          RowTemplate   one upgrade row, hidden, carrying the five row colours as attributes;
	                        an empty `Icon` at its left the controller fills (`UIAssets.Workshop`)
	          SwatchTemplate one paint swatch, hidden: the kit's square button with its check

	THE CAR STANDS ON THE BLUE, as on the car detail wings and the buyer's offer (`BuildBuyerOfferV2`),
	and for the same reasons: the body is opaque white and half the cars in the game are white.

	THE SWATCHES STAND ON THE WHITE, under the PAINT row rather than inside it. Inside, a blue or cyan
	swatch disappears into the blue row, and every other row would have to leave a hole for it. On the
	body each swatch is its own colour against the one background that does not compete, with the kit's
	navy rim round it.

	THE CHANGE BUTTON IS ORANGE, not the kit's green and not its blue. Green is the colour of every
	price on this screen, and CHANGE CAR is not a purchase. Blue is the panel it stands on. Orange is
	the kit's other button face on a blue ground (TimedRewardsUI's "Unlock All" sits on its blue header).

	=== THE GEOMETRY IS WORKED IN 1080p PIXELS ===============================================

	As in `BuildBuyerOfferV2`: every number is a pixel on a 1920x1080 screen, written back as a scale
	of its parent; every text cap is the height of its box; every frame whose shorter side moved has
	its rims, corners and checker put back to the artist's pixels (`refit`). The list's rows are laid
	out by the controller in the same pixels, read off attributes this command stamps on `List`, so
	the two cannot disagree about how tall a row is.

	HOUSE RULE: no wiki-style double-bracket links in this comment; the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)

--- How many level pips a part row carries. Read, so a longer ladder is a re-run and not an edit.
local CustomizeConfig = require(ReplicatedStorage.shared.Configs.CustomizeConfig)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local SHELF_NAME = "Screens"
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage

local ENTRY_NAME = "Workshop"
local KIT_FRAME = "UpgradesUI"

--- Where the borrowed parts and colours come from, as paths under the kit's `Container`.
local MONEY_SOURCE = { "HUD", "BottomInfo", "Cash", "Title" }
local ORANGE_SOURCE = { "IndexUI", "SideBtns", "LegendaryBtn" }
local QUEST_FRAME = "QuestsUI"
local CLAIMED_ICON = { "TimedRewardsUI", "Main", "ScrollingFrame", "Template", "ClaimedOverlay", "Icon" }

--- The screen every pixel below is measured on.
local REF_W, REF_H = 1920, 1080

--- The whole panel: about the size of the Cars page, which is the other screen about one car.
local PANEL_W, PANEL_H = 1160, 740

--- Room down each side of the panel, between the two columns, and inside the body round the list.
local EDGE = 16
local GAP = 14
local LIST_INSET = 12

--- The left column's width. The rest of the panel's width is the white body.
local SHOWCASE_W = 380

--- The header title's share of the header.
local TITLE_SHARE = 0.6

--[[ The left column, top down, as { top, height } in its own pixels. The car gets the most room,
	and a box WIDER than it is tall: a car is long and low, so a taller box only adds empty road
	above and below it (the detail wings found the same). ]]
local SHOWCASE = {
	Name = { 8, 44 },
	Portrait = { 60, 260 },
	Worth = { 334, 50 },
	Condition = { 396, 30 },
	Bar = { 436, 20 },
	Change = { 552, 60 },
}
local BAR_W = 300
local CHANGE_W = 280

--[[ One row of the list, in its own pixels (the list's width less `ROW_SIDE` each side, by `ROW_H`). A picture at
	the far left, the name and a line of type beside it, the meter where the line would be, what it
	adds to the value right-aligned before the button, and the button against the right edge. ]]
local ROW_H = 84
--[[ Room between the list's edges and the rows. THE LIST CLIPS, and a kit row's rim is drawn
	OUTSIDE its box (the strokes are `Contextual` borders), so a row laid edge to edge loses its
	outline on every side it touches. The sides also leave the scroll bar somewhere to go. ]]
local ROW_SIDE = 8
local LIST_PAD = 6
local ROW = {
	--- The row's picture, square and centred top to bottom. The type starts at 86, clear of it.
	Icon = { left = 12, size = 64 },
	--- Ends 16px short of the value line (`Gain` starts at 298 on a 694 row), so a long part name shrinks rather than
	--- running under it.
	Title = { left = 86, top = 8, w = 196, h = 34 },
	--- Ends where it did before the icon moved it right (458), short of where the value line goes on
	--- a row with no button (PAINT).
	Sub = { left = 86, top = 48, w = 372, h = 26 },
	Pips = { left = 86, top = 52, h = 16 },
	--- Ends 18px short of the button (`Buttons` starts at 198 from the right). The button's rim is drawn
	--- outside its box, so a value line laid flush against it reads as cut by the button.
	Gain = { right = 216, top = 25, w = 180, h = 36 },
	Buttons = { right = 14, w = 184, h = 54 },
}
local PIP_W = 56
local PIP_GAP = 10

--- The paint swatches: side, gap, and how many to a line. Laid out by the controller.
local SWATCH = 54
local SWATCH_GAP = 10
local SWATCH_COLUMNS = 10
--- Pixels between two rows, and between a row and the swatch block.
local ROW_GAP = 10

--- A swatch's face: white at the top to a light grey at the foot, over the paint colour, so the kit's
--- top-lit shading lands on any colour (a `UIGradient` MULTIPLIES the fill, `uigradient-multiplies`).
local SWATCH_SHADE = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205))

--- The check on the current colour, as a share of the swatch.
local CHECK_SIZE = 0.72
--- The word on the stock swatch's face, as a share of the swatch.
local SWATCH_CAPTION = { w = 0.94, h = 0.34 }

--- The kit's placeholders, replaced by what a player could see, so a freshly built template reads as
--- the finished screen in the Explorer. All of them are overwritten on the first state.
local PLACEHOLDER = {
	Title = "WORKSHOP",
	CarName = "WHITE KAMARO",
	Worth = "WORTH $1,345",
	Condition = "CONDITION 87%",
	Change = "CHANGE CAR",
	RowTitle = "ENGINE",
	RowSub = "BACK TO 100% CONDITION",
	RowGain = "+$67 VALUE",
	Price = "$58",
	Maxed = "MAXED",
}

type Box = { x: number, y: number, w: number, h: number }

-- === Helpers (the same ones `BuildBuyerOfferV2` carries) =====================

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
	local container = screen and screen:FindFirstChild("Container")
	if not container then
		return nil, string.format("%s holds no ScreenGui with a `Container` of frames.", node:GetFullName())
	end
	return container, nil
end

local function at(container: Instance, path: { string }): Instance?
	local node: Instance? = container
	for _, step in path do
		node = node and node:FindFirstChild(step)
	end
	return node
end

local function gradientAt(container: Instance, path: { string }): UIGradient?
	local node = at(container, path)
	return node and node:FindFirstChildOfClass("UIGradient")
end

local function boxOf(gui: GuiObject, pw: number, ph: number): Box
	local w = gui.Size.X.Scale * pw + gui.Size.X.Offset
	local h = gui.Size.Y.Scale * ph + gui.Size.Y.Offset
	local left = gui.Position.X.Scale * pw + gui.Position.X.Offset - gui.AnchorPoint.X * w
	local top = gui.Position.Y.Scale * ph + gui.Position.Y.Offset - gui.AnchorPoint.Y * h
	return { x = left + w / 2, y = top + h / 2, w = w, h = h }
end

local function setBox(gui: GuiObject, pw: number, ph: number, box: Box)
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui.Position = UDim2.fromScale(box.x / pw, box.y / ph)
	gui.Size = UDim2.fromScale(box.w / pw, box.h / ph)
end

local function edges(left: number, top: number, right: number, bottom: number): Box
	return { x = (left + right) / 2, y = (top + bottom) / 2, w = right - left, h = bottom - top }
end

--- A frame's own rim and corner after its SHORTER side went from `before` to `after` pixels.
local function keepRim(frame: Instance, before: number, after: number)
	local ratio = before / after
	for _, child in frame:GetChildren() do
		if child:IsA("UIStroke") and child.StrokeSizingMode == Enum.StrokeSizingMode.ScaledSize then
			child.Thickness *= ratio
		elseif child:IsA("UICorner") then
			child.CornerRadius = UDim.new(child.CornerRadius.Scale * ratio, child.CornerRadius.Offset)
		end
	end
end

--[[ A kit part after it went from `oldW x oldH` to `newW x newH` pixels, with every piece of its
	dress put back to the artist's pixels: its own rim and corner, the rim on a `Container` (the kit
	button's), and whatever is in its `BG` (the checker on a panel or a row, the gloss slash on a
	button), all of which are sized in fractions of the part and would otherwise stretch with it. ]]
local function refit(part: Instance, oldW: number, oldH: number, newW: number, newH: number)
	local before, after = math.min(oldW, oldH), math.min(newW, newH)
	keepRim(part, before, after)
	local container = part:FindFirstChild("Container")
	if container then
		keepRim(container, before, after)
	end
	local bg = part:FindFirstChild("BG")
	if bg then
		keepRim(bg, before, after)
		for _, piece in bg:GetChildren() do
			if piece:IsA("GuiObject") then
				local size = piece.Size
				piece.Size = UDim2.fromScale(size.X.Scale * oldW / newW, size.Y.Scale * oldH / newH)
			end
		end
	end
end

local function capTo(label: Instance, height: number, fraction: number)
	local cap = label:FindFirstChildOfClass("UITextSizeConstraint")
	if cap then
		cap.MaxTextSize = math.clamp(math.round(height * fraction), 1, 100)
	end
end

local function oneLine(text: string): string
	return (string.gsub(text, " ", "\u{00A0}"))
end

local function rampAt(gradient: UIGradient?, time: number): Color3?
	if not gradient then
		return nil
	end
	local stops = gradient.Color.Keypoints
	local t = math.clamp(time, 0, 1)
	for index = 1, #stops - 1 do
		local low, high = stops[index], stops[index + 1]
		if t <= high.Time then
			local span = high.Time - low.Time
			return low.Value:Lerp(high.Value, if span > 0 then (t - low.Time) / span else 0)
		end
	end
	return stops[#stops].Value
end

--- A label cut from `source`, placed at `box` in a parent `pw x ph`, capped to its height.
local function label(source: TextLabel, parent: GuiObject, name: string, pw: number, ph: number, box: Box, text: string, align: Enum.TextXAlignment?): TextLabel
	local copy = source:Clone()
	copy.Name = name
	copy.TextXAlignment = align or Enum.TextXAlignment.Center
	copy.TextYAlignment = Enum.TextYAlignment.Center
	--- Never `TextWrapped = false`: it switches `TextScaled` off with it.
	copy.TextScaled = true
	copy.Text = oneLine(text)
	copy.ZIndex = parent.ZIndex + 1
	setBox(copy, pw, ph, box)
	capTo(copy, box.h, 1)
	copy.Parent = parent
	return copy
end

--- Every `UIGradient` directly under the list's kit rows, in the order the artist stacked them, which
--- is the order the five colours are handed out in (red, lime, blue, purple, orange).
local function rowColours(list: Instance): { ColorSequence }
	local rows = {}
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") and child:FindFirstChild("UpgradesProgress") then
			table.insert(rows, child)
		end
	end
	--- The kit leaves every row at LayoutOrder 0, so the list order is the child order it shipped in.
	local colours = {}
	for _, row in rows do
		local gradient = row:FindFirstChildOfClass("UIGradient")
		if gradient then
			table.insert(colours, gradient.Color)
		end
	end
	return colours
end

return {
	Description = "Build StarterGui.MainUIV2.Screens.Workshop (the customization bay's screen) from the Cartoony Kit's UpgradesUI: the car turning on the blue with its worth, condition and CHANGE CAR at the left, and the kit's upgrade row (for repair, paint and each part) plus a paint swatch as hidden templates in the white body at the right. Rebuilds the shelf entry every run.",
	Tags = { "UI", "NewUI" },
	AutoRecordChanges = true,

	Arguments = {} :: Types.ArgumentType,

	Run = function(props: Types.Props, _arguments: Types.ArgumentResult)
		local out = props:Output()

		local screen = StarterGui:FindFirstChild(SCREEN_NAME)
		local shelf = screen and screen:FindFirstChild(SHELF_NAME)
		if not (shelf and shelf:IsA("GuiObject")) then
			out:error(string.format("No StarterGui.%s.%s. Run BuildMainUIV2 first.", SCREEN_NAME, SHELF_NAME))
			return
		end

		local container, why = findTemplate()
		if not container then
			out:error(string.format("The kit is not where it should be: %s", why))
			return
		end
		local kitFrame = container:FindFirstChild(KIT_FRAME)
		if not (kitFrame and kitFrame:IsA("GuiObject")) then
			out:error(string.format("%s has no `%s` to build from.", container:GetFullName(), KIT_FRAME))
			return
		end

		--- Everything borrowed from other kit frames, read before anything is built so a kit missing
		--- one stops the build with the old entry still standing.
		local money = gradientAt(container, MONEY_SOURCE)
		local orange = gradientAt(container, ORANGE_SOURCE)
		local check = at(container, CLAIMED_ICON)
		local questBar: GuiObject? = nil
		do
			local quests = container:FindFirstChild(QUEST_FRAME)
			local qMain = quests and quests:FindFirstChild("Main")
			local qList = qMain and qMain:FindFirstChildOfClass("ScrollingFrame")
			for _, row in (if qList then qList:GetChildren() else {}) do
				local bar = row:FindFirstChild("ProgressBar")
				if bar and bar:IsA("GuiObject") then
					questBar = bar
					break
				end
			end
		end
		if not (money and orange and check and check:IsA("ImageLabel") and questBar) then
			out:error("The kit is missing a part this screen borrows: the cash gradient, the legendary orange, TimedRewardsUI's claimed check, or a QuestsUI row's ProgressBar.")
			return
		end

		local panel = kitFrame:Clone() :: GuiObject
		panel.Name = ENTRY_NAME
		panel.Visible = true

		local aspect = panel:FindFirstChildOfClass("UIAspectRatioConstraint")
		local header = panel:FindFirstChild("Header")
		local title = header and header:FindFirstChild("Title")
		local close = header and header:FindFirstChild("CloseBtn")
		local main = panel:FindFirstChild("Main")
		local list = main and main:FindFirstChildOfClass("ScrollingFrame")
		local rim = panel:FindFirstChildOfClass("UIGradient")
		local kitRow: GuiObject? = nil
		for _, child in (if list then list:GetChildren() else {}) do
			if child:IsA("GuiObject") and child:FindFirstChild("UpgradesProgress") and child:FindFirstChild("Btns") then
				kitRow = child
				break
			end
		end
		if
			not (
				aspect
				and header
				and header:IsA("GuiObject")
				and title
				and title:IsA("TextLabel")
				and close
				and close:IsA("GuiObject")
				and main
				and main:IsA("GuiObject")
				and list
				and kitRow
			)
		then
			out:error(
				string.format(
					"The kit's %s is not the shape this expects: it needs an aspect constraint, `Header.Title`, `Header.CloseBtn` and a `Main` ScrollingFrame holding an upgrade row.",
					KIT_FRAME
				)
			)
			panel:Destroy()
			return
		end
		local row = kitRow :: GuiObject
		local buyFace = row.Btns:FindFirstChild("RebirthBtn")
		local greyFace = row.Btns:FindFirstChild("DisabledBtn")
		local pips = row:FindFirstChild("UpgradesProgress")
		local rowTitle = row:FindFirstChild("Title")
		if not (buyFace and greyFace and pips and rowTitle and rowTitle:IsA("TextLabel")) then
			out:error("The kit's upgrade row has lost `Btns.RebirthBtn`, `Btns.DisabledBtn`, `UpgradesProgress` or `Title`.")
			panel:Destroy()
			return
		end

		-- === Measure the kit before anything moves ==========================
		local kitW = panel.Size.X.Scale * REF_W
		local kitH = kitW / aspect.AspectRatio
		local headerBox = boxOf(header, kitW, kitH)
		local titleBox = boxOf(title, headerBox.w, headerBox.h)
		local closeBox = boxOf(close, headerBox.w, headerBox.h)
		local mainBox = boxOf(main, kitW, kitH)
		local listBox = boxOf(list, mainBox.w, mainBox.h)
		local kitRowW = row.Size.X.Scale * listBox.w
		local kitRowH = row.Size.Y.Scale * listBox.h
		local btnsBox = boxOf(row.Btns, kitRowW, kitRowH)
		local pipsBox = boxOf(pips, kitRowW, kitRowH)
		local firstPip = pips:FindFirstChildWhichIsA("GuiObject")
		local kitPipW = firstPip and firstPip.Size.X.Scale * pipsBox.w or PIP_W
		local kitPipH = firstPip and firstPip.Size.Y.Scale * pipsBox.h or ROW.Pips.h
		local closeKitSide = closeBox.h
		local bodyTop = mainBox.y - mainBox.h / 2
		local bodyBottomMargin = kitH - (mainBox.y + mainBox.h / 2)
		local colours = rowColours(list)

		-- === The panel ======================================================
		panel.Size = UDim2.fromScale(PANEL_W / REF_W, PANEL_H / REF_H)
		aspect.AspectRatio = PANEL_W / PANEL_H
		refit(panel, kitW, kitH, PANEL_W, PANEL_H)

		-- === The header =====================================================
		local headerMargin = (kitW - headerBox.w) / 2
		local newHeader = { x = PANEL_W / 2, y = headerBox.y, w = PANEL_W - 2 * headerMargin, h = headerBox.h }
		setBox(header, PANEL_W, PANEL_H, newHeader)
		local titleLeft = titleBox.x - titleBox.w / 2
		local titleW = newHeader.w * TITLE_SHARE
		setBox(title, newHeader.w, newHeader.h, { x = titleLeft + titleW / 2, y = titleBox.y, w = titleW, h = titleBox.h })
		title.Text = oneLine(PLACEHOLDER.Title)
		setBox(close, newHeader.w, newHeader.h, {
			x = newHeader.w - (headerBox.w - closeBox.x),
			y = closeBox.y,
			w = closeBox.w,
			h = closeBox.h,
		})

		-- === The two columns ================================================
		local columnsBottom = PANEL_H - bodyBottomMargin
		local showBox = edges(EDGE, bodyTop, EDGE + SHOWCASE_W, columnsBottom)
		local newMain = edges(EDGE + SHOWCASE_W + GAP, bodyTop, PANEL_W - EDGE, columnsBottom)
		setBox(main, PANEL_W, PANEL_H, newMain)
		keepRim(main, math.min(mainBox.w, mainBox.h), math.min(newMain.w, newMain.h))

		-- === The left column ================================================
		local showcase = Instance.new("Frame")
		showcase.Name = "Showcase"
		showcase.BackgroundTransparency = 1
		showcase.BorderSizePixel = 0
		showcase.ZIndex = main.ZIndex
		setBox(showcase, PANEL_W, PANEL_H, showBox)

		local function band(key: string, width: number?): Box
			local spec = SHOWCASE[key]
			local w = width or showBox.w
			return { x = showBox.w / 2, y = spec[1] + spec[2] / 2, w = w, h = spec[2] }
		end

		label(title, showcase, "CarName", showBox.w, showBox.h, band("Name"), PLACEHOLDER.CarName)

		local portraitBox = band("Portrait")
		local portrait = Instance.new("Frame")
		portrait.Name = "Portrait"
		portrait.BackgroundTransparency = 1
		portrait.BorderSizePixel = 0
		portrait.ZIndex = showcase.ZIndex + 1
		setBox(portrait, showBox.w, showBox.h, portraitBox)
		local backdrop = rampAt(rim, (bodyTop + portraitBox.y) / PANEL_H)
		if backdrop then
			portrait:SetAttribute("Backdrop", backdrop)
		end
		portrait:SetAttribute("Aspect", portraitBox.w / portraitBox.h)
		portrait.Parent = showcase

		local worth = label(title, showcase, "Worth", showBox.w, showBox.h, band("Worth"), PLACEHOLDER.Worth)
		local worthTint = (money :: UIGradient):Clone()
		worthTint.Name = "Tint"
		worthTint.Enabled = true
		worthTint.Parent = worth

		label(title, showcase, "Condition", showBox.w, showBox.h, band("Condition"), PLACEHOLDER.Condition)

		--[[ The condition bar: the quest row's track, its fill anchored on its left edge so one number
			(`Size.X.Scale`) draws it. REFILLED IN THE PIP GREEN, because the kit's own blue fill on a
			blue panel is a bar nobody can read, and green is what the level pips already say "done" in. ]]
		local bar = (questBar :: GuiObject):Clone()
		bar.Name = "ConditionBar"
		local barKitW = bar.Size.X.Scale * 880 -- the quest row's width at 1080p; only the ratio matters below
		local barKitH = bar.Size.Y.Scale * 124
		local barBox = band("Bar", BAR_W)
		refit(bar, barKitW, barKitH, barBox.w, barBox.h)
		setBox(bar, showBox.w, showBox.h, barBox)
		bar.ZIndex = showcase.ZIndex + 1
		local fill = bar:FindFirstChild("Progress")
		if fill and fill:IsA("GuiObject") then
			refit(fill, barKitW * fill.Size.X.Scale, barKitH, barBox.w * fill.Size.X.Scale, barBox.h)
			fill.AnchorPoint = Vector2.new(0, 0.5)
			fill.Position = UDim2.fromScale(0, 0.5)
			fill.Size = UDim2.fromScale(0.87, 1)
			local fillFace = fill:FindFirstChildOfClass("UIGradient")
			local pipFace = firstPip and firstPip:FindFirstChildOfClass("UIGradient")
			if fillFace and pipFace then
				fillFace.Color = pipFace.Color
				fillFace.Rotation = pipFace.Rotation
			end
		end
		bar.Parent = showcase

		--- CHANGE CAR: the row's own buy button, re-faced orange. See the header for the colour.
		local change = buyFace:Clone()
		change.Name = "ChangeBtn"
		local changeBox = band("Change", CHANGE_W)
		refit(change, btnsBox.w, btnsBox.h, changeBox.w, changeBox.h)
		setBox(change, showBox.w, showBox.h, changeBox)
		change.ZIndex = showcase.ZIndex + 1
		local changeFace = change:FindFirstChildOfClass("UIGradient")
		if changeFace then
			changeFace.Color = (orange :: UIGradient).Color
			changeFace.Rotation = (orange :: UIGradient).Rotation
		end
		local changeTitle = change:FindFirstChild("Title")
		if changeTitle and changeTitle:IsA("TextLabel") then
			changeTitle.Text = oneLine(PLACEHOLDER.Change)
			capTo(changeTitle, changeBox.h * changeTitle.Size.Y.Scale, 1)
		end
		change.Parent = showcase

		showcase.Parent = panel

		-- === The list =======================================================
		local listW = newMain.w - 2 * LIST_INSET
		--- A row's width: the list less `ROW_SIDE` down each side. Every pixel of the row template is laid
		--- out against this, and the controller places rows at this width.
		local rowW = listW - 2 * ROW_SIDE
		local listH = newMain.h - 2 * LIST_INSET
		list.Name = "List"
		setBox(list, newMain.w, newMain.h, edges(LIST_INSET, LIST_INSET, newMain.w - LIST_INSET, newMain.h - LIST_INSET))
		list.AutomaticCanvasSize = Enum.AutomaticSize.None
		list.ScrollingDirection = Enum.ScrollingDirection.Y
		--- A thin bar, which the kit's zero hides; the list only overflows on a car with a very long
		--- palette, and a list that scrolls with nothing saying so reads as cut off.
		list.ScrollBarThickness = 6
		list.ScrollBarImageColor3 = Color3.fromRGB(2, 30, 56)
		list.ClipsDescendants = true
		--- The pixels the controller lays rows out in. One source for both sides; see the header.
		list:SetAttribute("ReferenceWidth", listW)
		list:SetAttribute("ReferenceHeight", listH)
		--[[ What a `CanvasSize` scale of 1 MEANS here, and it is not the list's own height: measured
			live (2026-09-30), this list's `AbsoluteCanvasSize.Y` at `CanvasSize` 0,1 came out as
			`Main`'s height, 398px, against the list's 382px, and every row laid out against the list
			slid 4% down and out of the bottom. So the controller divides by this, `Main`'s height. ]]
		list:SetAttribute("CanvasBasis", newMain.h)
		list.CanvasSize = UDim2.fromScale(0, listH / newMain.h)
		list:SetAttribute("RowSide", ROW_SIDE)
		list:SetAttribute("ListPad", LIST_PAD)
		list:SetAttribute("RowHeight", ROW_H)
		list:SetAttribute("RowGap", ROW_GAP)
		list:SetAttribute("Swatch", SWATCH)
		list:SetAttribute("SwatchGap", SWATCH_GAP)
		list:SetAttribute("SwatchColumns", SWATCH_COLUMNS)

		-- === The row template ===============================================
		local template = row:Clone()
		template.Name = "RowTemplate"
		template.Visible = false
		template.LayoutOrder = 0
		refit(template, kitRowW, kitRowH, rowW, ROW_H)
		template.AnchorPoint = Vector2.new(0, 0)
		template.Position = UDim2.new()
		template.Size = UDim2.fromScale(1, ROW_H / listH)
		for index, colour in colours do
			template:SetAttribute("Color" .. index, colour)
		end
		template:SetAttribute("ColorCount", #colours)

		local tTitle = template:FindFirstChild("Title") :: TextLabel
		setBox(tTitle, rowW, ROW_H, edges(ROW.Title.left, ROW.Title.top, ROW.Title.left + ROW.Title.w, ROW.Title.top + ROW.Title.h))
		tTitle.TextXAlignment = Enum.TextXAlignment.Left
		tTitle.Text = oneLine(PLACEHOLDER.RowTitle)
		capTo(tTitle, ROW.Title.h, 1)

		--- The picture: empty here, filled per row by the controller off `UIAssets.Workshop.Icons`. Bare
		--- art on the row's colour, no well behind it, like the HUD rail's cells.
		local rowIcon = Instance.new("ImageLabel")
		rowIcon.Name = "Icon"
		rowIcon.BackgroundTransparency = 1
		rowIcon.Image = ""
		rowIcon.ScaleType = Enum.ScaleType.Fit
		rowIcon.ZIndex = tTitle.ZIndex
		setBox(rowIcon, rowW, ROW_H, edges(ROW.Icon.left, (ROW_H - ROW.Icon.size) / 2, ROW.Icon.left + ROW.Icon.size, (ROW_H + ROW.Icon.size) / 2))
		rowIcon.Parent = template

		local sub = tTitle:Clone()
		sub.Name = "Sub"
		setBox(sub, rowW, ROW_H, edges(ROW.Sub.left, ROW.Sub.top, ROW.Sub.left + ROW.Sub.w, ROW.Sub.top + ROW.Sub.h))
		sub.Text = oneLine(PLACEHOLDER.RowSub)
		capTo(sub, ROW.Sub.h, 1)
		sub.Visible = false
		sub.Parent = template

		local gain = tTitle:Clone()
		gain.Name = "Gain"
		local gainRight = rowW - ROW.Gain.right
		setBox(gain, rowW, ROW_H, edges(gainRight - ROW.Gain.w, ROW.Gain.top, gainRight, ROW.Gain.top + ROW.Gain.h))
		gain.TextXAlignment = Enum.TextXAlignment.Right
		gain.Text = oneLine(PLACEHOLDER.RowGain)
		capTo(gain, ROW.Gain.h, 0.85)
		gain.Parent = template

		--[[ The meter: `CustomizeConfig.PartLevels` pips, each the kit's pip, its green and its grey
			parked on the meter as `OnColor` / `OffColor` so the controller colours by level without
			knowing which pip the artist happened to fill. ]]
		local tPips = template:FindFirstChild("UpgradesProgress") :: Frame
		local onFace, offFace
		for _, pip in tPips:GetChildren() do
			local face = pip:FindFirstChildOfClass("UIGradient")
			if face then
				local lit = face.Color.Keypoints[1].Value.G > face.Color.Keypoints[1].Value.B + 0.2
				if lit and not onFace then
					onFace = face.Color
				elseif not lit and not offFace then
					offFace = face.Color
				end
			end
		end
		tPips:SetAttribute("OnColor", onFace)
		tPips:SetAttribute("OffColor", offFace)
		--- Copied out BEFORE the kit's five are cleared below: `Destroy` takes a part's gradient and
		--- strokes with it, and a clone of what is left is a bare frame.
		local firstKitPip = tPips:FindFirstChildWhichIsA("GuiObject")
		local pipTemplate = firstKitPip and firstKitPip:Clone()
		local levels = CustomizeConfig.PartLevels
		local pipsW = levels * PIP_W + (levels - 1) * PIP_GAP
		setBox(tPips, rowW, ROW_H, edges(ROW.Pips.left, ROW.Pips.top, ROW.Pips.left + pipsW, ROW.Pips.top + ROW.Pips.h))
		for _, pip in tPips:GetChildren() do
			if pip:IsA("GuiObject") then
				pip:Destroy()
			end
		end
		if pipTemplate then
			for level = 1, levels do
				local pip = pipTemplate:Clone()
				pip.Name = "Pip" .. level
				pip.LayoutOrder = level
				refit(pip, kitPipW, kitPipH, PIP_W, ROW.Pips.h)
				pip.Size = UDim2.fromScale(PIP_W / pipsW, 1)
				pip.Parent = tPips
			end
		end
		local pipLayout = tPips:FindFirstChildOfClass("UIListLayout")
		if pipLayout then
			pipLayout.SortOrder = Enum.SortOrder.LayoutOrder
			pipLayout.Padding = UDim.new(PIP_GAP / pipsW, 0)
		end

		--- The button pair: the green face a press buys with, and the grey one for nothing to buy.
		local tBtns = template:FindFirstChild("Btns") :: Frame
		local btnsRight = rowW - ROW.Buttons.right
		setBox(tBtns, rowW, ROW_H, {
			x = btnsRight - ROW.Buttons.w / 2,
			y = ROW_H / 2,
			w = ROW.Buttons.w,
			h = ROW.Buttons.h,
		})
		tBtns.BackgroundTransparency = 1
		for _, face in tBtns:GetChildren() do
			if face:IsA("GuiObject") then
				refit(face, btnsBox.w, btnsBox.h, ROW.Buttons.w, ROW.Buttons.h)
				local caption = face:FindFirstChild("Title")
				if caption and caption:IsA("TextLabel") then
					caption.Text = oneLine(if face.Name == "DisabledBtn" then PLACEHOLDER.Maxed else PLACEHOLDER.Price)
					capTo(caption, ROW.Buttons.h * caption.Size.Y.Scale, 1)
				end
			end
		end
		local buy = tBtns:FindFirstChild("RebirthBtn")
		if buy then
			buy.Name = "BuyBtn"
		end
		local grey = tBtns:FindFirstChild("DisabledBtn")
		if grey and grey:IsA("GuiObject") then
			grey.Name = "GreyBtn"
			grey.Visible = false
		end

		-- === The swatch template ============================================
		local swatch = close:Clone()
		swatch.Name = "SwatchTemplate"
		swatch.Visible = false
		refit(swatch, closeKitSide, closeKitSide, SWATCH, SWATCH)
		swatch.AnchorPoint = Vector2.new(0, 0)
		swatch.Position = UDim2.new()
		swatch.Size = UDim2.fromScale(SWATCH / listW, SWATCH / listH)
		swatch.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
		local shade = swatch:FindFirstChildOfClass("UIGradient")
		if shade then
			shade.Color = SWATCH_SHADE
			shade.Rotation = 90
		end
		--- The kit's X becomes the claimed check, shown only on the colour the car already wears.
		local icon = swatch:FindFirstChild("Icon")
		if icon then
			icon:Destroy()
		end
		local tick = (check :: ImageLabel):Clone()
		tick.Name = "Check"
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = UDim2.fromScale(0.5, 0.5)
		tick.Size = UDim2.fromScale(CHECK_SIZE, CHECK_SIZE)
		tick.ScaleType = Enum.ScaleType.Fit
		tick.ZIndex = swatch.ZIndex + 2
		tick.Visible = false
		tick.Parent = swatch

		--[[ A word on the face, for the one swatch that is not a colour: `Stock`, the livery the
			artist authored, which the client cannot draw as a single fill. Hidden on every other. ]]
		local caption = tTitle:Clone()
		caption.Name = "Caption"
		caption.TextXAlignment = Enum.TextXAlignment.Center
		caption.AnchorPoint = Vector2.new(0.5, 0.5)
		caption.Position = UDim2.fromScale(0.5, 0.5)
		caption.Size = UDim2.fromScale(SWATCH_CAPTION.w, SWATCH_CAPTION.h)
		caption.Text = "STOCK"
		caption.ZIndex = swatch.ZIndex + 1
		caption.Visible = false
		capTo(caption, SWATCH * SWATCH_CAPTION.h, 1)
		caption.Parent = swatch

		-- === Empty the kit's list and park the templates in it ===============
		for _, child in list:GetChildren() do
			child:Destroy()
		end
		template.Parent = list
		swatch.Parent = list

		local existing = shelf:FindFirstChild(ENTRY_NAME)
		if existing then
			existing:Destroy()
		end
		panel.Parent = shelf

		out:print(string.format("Built %s.%s.%s from the kit's %s.", SCREEN_NAME, SHELF_NAME, ENTRY_NAME, KIT_FRAME))
		out:print(
			string.format(
				"%dx%d at 1080p: `Showcase` (%dpx) beside `Main` (%dpx); `List` %dx%d with `RowTemplate` (%d row colours, %d pips) and `SwatchTemplate`.",
				PANEL_W,
				PANEL_H,
				SHOWCASE_W,
				math.round(newMain.w),
				math.round(listW),
				math.round(listH),
				#colours,
				levels
			)
		)

		pcall(function()
			props:SetSelection({ panel })
		end)
	end,
} :: Types.ScriptModule
