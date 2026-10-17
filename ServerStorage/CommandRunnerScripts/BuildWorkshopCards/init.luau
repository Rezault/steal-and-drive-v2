--[[
	BuildWorkshopCards: Command Runner command

	Builds `StarterGui.MainUIV2.Screens.WorkshopCards`, the customization bay's screen in the CARD
	layout: the reference Aleafo liked (2026-09-30), a dark card per option with a coloured icon tile
	at its left, instead of `BuildWorkshopV2`'s coloured upgrade rows on a white body.

	Run `BuildWorkshopV2` first: this starts from its `Screens.Workshop` and restyles a COPY, so the
	kit's pieces (the panel, its header and close, the green and grey buttons, the orange CHANGE CAR,
	the condition bar, the paint swatch) are the same instances with the same tags, sounds and hover,
	and a fix to one of them in V2 reaches this on a re-run. `Screens.Workshop` itself is not touched:
	it is still the screen with `NewUIConfig.WorkshopCards` off. `Screens.WorkshopCards` is destroyed
	and made again on every run, so this is safe to re-run.

	=== WHAT IT LOOKS LIKE ======================================================================

	    WorkshopCards       V2's panel, same size, same header and close
	      Header            a wrench `Glyph` before the title
	      Showcase          a navy CARD now, not type on the panel's blue
	        Portrait        the car, standing on `Platform`, a glowing turntable behind it
	        ChangeBtn       with a car `Glyph` before its caption
	      Main              the right column, deep blue instead of white
	        List            emptied; the controller lays the cards out in it
	          RepairCard    tile, REPAIR, a green line, the condition bar and its %, a REPAIR/$ button
	          PaintCard     tile, PAINT, a line, the swatches, a PAINT CAR/$ EACH button
	          PartCard      tile, name, "Level 1 / 3" and dots, +$ VALUE, an UPGRADE/$ button
	          SwatchTemplate V2's swatch at this card's size, with a selection `Ring`

	THE TILES ARE THE HEADER'S CLOSE BUTTON with its tag taken off: the kit's one square face, recoloured
	with the five row colours V2 stamped on its row (red repair, blue paint, then lime, purple, orange
	for the parts, as the reference has them). The glyph on each is white with a navy rim, so it reads
	on every one of them. The glyph ids live in `UIAssets.WorkshopCards`; the controller sets them, so
	a new drawing is a config line and not a re-run (this sets them too, so the template reads right in
	the Explorer).

	THE CARDS ARE NAVY ON A DEEP BLUE, with a light blue rim, the reference's colours. A kit white body
	under navy cards would be the dark-well-on-white mistake (`kit-dark-well-needs-its-blue-strip`).

	=== THE GEOMETRY IS WORKED IN 1080p PIXELS ===============================================

	As in V2: every number is a pixel on a 1920x1080 screen written back as a scale of its parent, and
	the list's cards are laid out by the controller in the same pixels, read off attributes stamped on
	`List` and on each card. A card's height can change (PAINT grows a line of swatches for a big
	palette), so a card's pieces are placed by the controller from those attributes, not only here.

	HOUSE RULE: no wiki-style double-bracket links in this comment; the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)

local CustomizeConfig = require(ReplicatedStorage.shared.Configs.CustomizeConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local SHELF_NAME = "Screens"
local SOURCE_NAME = "Workshop" -- BuildWorkshopV2's entry
local ENTRY_NAME = "WorkshopCards"

local REF_W, REF_H = 1920, 1080

--- The card and column colours, off the reference: navy cards, a deep blue column behind them, a
--- light blue rim. A `UIGradient` MULTIPLIES a white fill, so each is a ramp top to bottom.
local CARD_FACE = ColorSequence.new(Color3.fromRGB(22, 46, 98), Color3.fromRGB(12, 27, 62))
local CARD_RIM = Color3.fromRGB(47, 110, 214)
local SHOWCASE_FACE = ColorSequence.new(Color3.fromRGB(26, 64, 138), Color3.fromRGB(10, 24, 58))
local COLUMN_FACE = ColorSequence.new(Color3.fromRGB(17, 70, 160), Color3.fromRGB(9, 44, 112))
--- Pixels, at 1080p, of a card's rim and corner.
local RIM = 2.5
local CORNER = 12

--- The green of every "+$ VALUE" and "FULLY REPAIRED", the reference's bright one.
local GAIN_GREEN = Color3.fromRGB(128, 245, 64)
--- A level dot not reached yet.
local DOT_OFF = ColorSequence.new(Color3.fromRGB(122, 136, 168), Color3.fromRGB(78, 90, 118))
--- The ramp the PAINT CAR button wears: `RowTemplate`'s third colour, the blue row.
local PAINT_BUTTON_COLOUR = 3

--- The list, as V2 left it. A card is the list's width less `ROW_SIDE` each side.
local ROW_SIDE = 8
local LIST_PAD = 6
local CARD_GAP = 9

--- One card, in its own pixels. `CARD_W` is worked out from the list; heights are per kind.
local REPAIR_H = 92
local PART_H = 92
local TILE = { left = 10, size = 72 }
local TEXT_LEFT = 96
local TITLE = { top = 12, w = 230, h = 32 }
local SUB = { top = 50, w = 250, h = 24 }
local LEVEL = { top = 52, w = 104, h = 26 }
local DOT = { left = 206, size = 20, gap = 8 }
--- The button, against the right edge: two lines, the verb over the price.
local BUTTON = { right = 10, w = 168, h = 72 }
--- The value line, right-aligned 14px short of the button.
local GAIN = { gap = 14, w = 160, h = 30 }
--- REPAIR's bar and its percentage, starting where the value line would.
local BAR = { left = 300, h = 20, pctW = 62, pctGap = 8 }
--- PAINT: the head is the same as any card; the swatches start under it, and the card is as tall as
--- they need. Two lines of eight are what the reference draws.
local PAINT_HEAD = 72
--- PAINT's line under its title sits higher and smaller than a part's, to leave the swatches room.
local PAINT_SUB = { top = 44, w = 320, h = 20 }
local SWATCH = 42
local SWATCH_GAP = 7
local SWATCH_COLUMNS = 8
local PAINT_FOOT = 13
local PAINT_H = PAINT_HEAD + 2 * SWATCH + SWATCH_GAP + PAINT_FOOT
--- The selection ring, in 1080p pixels out from the swatch's edge (Aleafo's mock, 2026-09-30): a
--- white hairline just inside, a green band laid OVER the kit's dark rim so no gap shows between
--- the colour and the green, then a glow in fading steps. A ring floating outside the rim read as
--- a second, loose outline. Each glow step is { width, transparency }.
local RING_HAIRLINE = 1.5
local RING_BAND = 4.5
local RING_GLOW = { { 1.5, 0.3 }, { 1.5, 0.55 }, { 1.5, 0.75 }, { 1.5, 0.9 } }
--- The swatch's corner, as a share of its side (V2's swatch `UICorner`).
local SWATCH_CORNER = 0.2

--- The kit's buttons as V2 left them, which `refit` resizes from.
local V2_BUTTON = { w = 184, h = 54 }
local V2_SWATCH = 54
local V2_BAR = { w = 300, h = 20 }

--- The header glyph, and the space between it and the title, in the header's pixels.
local HEADER_GLYPH_GAP = 10
--- CHANGE CAR's glyph, as shares of the button: its centre across, and its height.
local CHANGE_GLYPH = { x = 0.16, h = 0.66 }
local CHANGE_TITLE = { x = 0.6, w = 0.64 }
--- The turntable under the car, in the portrait's pixels: its width as a share of the portrait, its
--- height from the art's own aspect, and where its centre sits from the portrait's top.
local PLATFORM = { share = 0.96, aspect = 1024 / 320, centre = 0.72 }
--- How much taller the car's box is than V2's, in the showcase's pixels, and so how far the worth,
--- the condition and its bar move down: V2 left a gap over CHANGE CAR that the car fills here.
local PORTRAIT_GROW = 44

local PLACEHOLDER = {
	RepairTitle = "REPAIR",
	RepairSub = "FULLY REPAIRED",
	Percent = "100%",
	PaintTitle = "PAINT",
	PaintSub = "CHANGES APPEARANCE ONLY",
	PartTitle = "ENGINE",
	Level = "Level 1 / 3",
	Gain = "+$24 VALUE",
	Verb = "UPGRADE",
	Price = "$19",
	PaintVerb = "PAINT CAR",
	PaintPrice = "$24 EACH",
	Maxed = "MAXED",
	Repair = "REPAIR",
}

type Box = { x: number, y: number, w: number, h: number }

-- === Helpers (V2's, the ones this needs) =====================================

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

--- A label cut from `source`, placed at `box` in a parent `pw x ph`, capped to its height.
local function label(source: TextLabel, parent: GuiObject, name: string, pw: number, ph: number, box: Box, text: string, align: Enum.TextXAlignment?): TextLabel
	local copy = source:Clone()
	copy.Name = name
	copy.TextXAlignment = align or Enum.TextXAlignment.Left
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

--- A white fill under a vertical ramp, with a rim and a corner in 1080p pixels.
local function dress(frame: GuiObject, face: ColorSequence, rim: Color3?, rimPx: number, cornerPx: number, w: number, h: number)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	for _, child in frame:GetChildren() do
		if child:IsA("UIGradient") or child:IsA("UIStroke") or child:IsA("UICorner") then
			child:Destroy()
		end
	end
	local gradient = Instance.new("UIGradient")
	gradient.Color = face
	gradient.Rotation = 90
	gradient.Parent = frame
	local side = math.min(w, h)
	if rim then
		local stroke = Instance.new("UIStroke")
		stroke.Color = rim
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
		stroke.Thickness = rimPx / side
		stroke.Parent = frame
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(cornerPx / side, 0)
	corner.Parent = frame
end

--- A bare picture, square, centred on `box`.
local function glyph(parent: GuiObject, name: string, pw: number, ph: number, box: Box, image: number?): ImageLabel
	local icon = Instance.new("ImageLabel")
	icon.Name = name
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = if image then UIAssets.url(image) else ""
	icon.ZIndex = parent.ZIndex + 2
	setBox(icon, pw, ph, box)
	icon.Parent = parent
	return icon
end

--- Take every tag off a clone that must not behave as a button (a tile is a picture, not a press).
local function untag(root: Instance)
	for _, node in { root, table.unpack(root:GetDescendants()) } do
		for _, tag in CollectionService:GetTags(node) do
			CollectionService:RemoveTag(node, tag)
		end
	end
end

return {
	Description = "Build StarterGui.MainUIV2.Screens.WorkshopCards (the customization bay's screen in the card layout: a navy card per option with a coloured icon tile) by restyling a copy of BuildWorkshopV2's Screens.Workshop. Run BuildWorkshopV2 first. Rebuilds the shelf entry every run.",
	Tags = { "UI", "NewUI" },
	AutoRecordChanges = true,

	Arguments = {} :: Types.ArgumentType,

	Run = function(props: Types.Props, _arguments: Types.ArgumentResult)
		local out = props:Output()

		local screen = StarterGui:FindFirstChild(SCREEN_NAME)
		local shelf = screen and screen:FindFirstChild(SHELF_NAME)
		local source = shelf and shelf:FindFirstChild(SOURCE_NAME)
		if not (source and source:IsA("GuiObject")) then
			out:error(string.format("No StarterGui.%s.%s.%s. Run BuildWorkshopV2 first.", SCREEN_NAME, SHELF_NAME, SOURCE_NAME))
			return
		end

		local panel = source:Clone() :: GuiObject
		panel.Name = ENTRY_NAME
		local header = panel:FindFirstChild("Header") :: Frame
		local title = header and header:FindFirstChild("Title") :: TextLabel
		local close = header and header:FindFirstChild("CloseBtn") :: GuiObject
		local showcase = panel:FindFirstChild("Showcase") :: Frame
		local portrait = showcase and showcase:FindFirstChild("Portrait") :: Frame
		local change = showcase and showcase:FindFirstChild("ChangeBtn") :: GuiObject
		local conditionBar = showcase and showcase:FindFirstChild("ConditionBar") :: GuiObject
		local main = panel:FindFirstChild("Main") :: Frame
		local list = main and main:FindFirstChild("List") :: ScrollingFrame
		local rowTemplate = list and list:FindFirstChild("RowTemplate") :: Frame
		local swatch = list and list:FindFirstChild("SwatchTemplate") :: GuiObject
		local btns = rowTemplate and rowTemplate:FindFirstChild("Btns") :: Frame
		if not (header and title and close and showcase and portrait and change and conditionBar and main and list and rowTemplate and swatch and btns) then
			out:error("Screens.Workshop is not the shape BuildWorkshopV2 makes. Re-run BuildWorkshopV2, then this.")
			panel:Destroy()
			return
		end
		local glyphs = UIAssets.WorkshopCards and UIAssets.WorkshopCards.Glyphs or {}

		-- === Measure =========================================================
		local panelW = panel.Size.X.Scale * REF_W
		local panelH = panel.Size.Y.Scale * REF_H
		local headerBox = boxOf(header, panelW, panelH)
		local titleBox = boxOf(title, headerBox.w, headerBox.h)
		local showBox = boxOf(showcase, panelW, panelH)
		local mainBox = boxOf(main, panelW, panelH)
		local listBox = boxOf(list, mainBox.w, mainBox.h)
		local listW, listH = listBox.w, listBox.h
		local cardW = listW - 2 * ROW_SIDE
		local colours = {}
		for index = 1, (rowTemplate:GetAttribute("ColorCount") or 0) :: number do
			colours[index] = rowTemplate:GetAttribute("Color" .. index)
		end

		-- === The header: a wrench before the title ==========================
		local titleLeft = titleBox.x - titleBox.w / 2
		local glyphSide = titleBox.h
		glyph(header, "Glyph", headerBox.w, headerBox.h, { x = titleLeft + glyphSide / 2, y = titleBox.y, w = glyphSide, h = glyphSide }, glyphs.Wrench)
		local shifted = titleLeft + glyphSide + HEADER_GLYPH_GAP
		setBox(title, headerBox.w, headerBox.h, { x = shifted + titleBox.w / 2, y = titleBox.y, w = titleBox.w, h = titleBox.h })

		-- === The left column: a navy card ===================================
		dress(showcase, SHOWCASE_FACE, CARD_RIM, RIM, CORNER, showBox.w, showBox.h)
		showcase.ClipsDescendants = false
		--- The car's edges blend into the card behind it, not V2's panel blue.
		portrait:SetAttribute("Backdrop", SHOWCASE_FACE.Keypoints[1].Value:Lerp(SHOWCASE_FACE.Keypoints[2].Value, 0.4))
		local portraitBox = boxOf(portrait, showBox.w, showBox.h)
		portraitBox = { x = portraitBox.x, y = portraitBox.y + PORTRAIT_GROW / 2, w = portraitBox.w, h = portraitBox.h + PORTRAIT_GROW }
		setBox(portrait, showBox.w, showBox.h, portraitBox)
		portrait:SetAttribute("Aspect", portraitBox.w / portraitBox.h)
		for _, name in { "Worth", "Condition", "ConditionBar" } do
			local piece = showcase:FindFirstChild(name)
			if piece and piece:IsA("GuiObject") then
				local box = boxOf(piece, showBox.w, showBox.h)
				box.y += PORTRAIT_GROW
				setBox(piece, showBox.w, showBox.h, box)
			end
		end
		local platformW = portraitBox.w * PLATFORM.share
		local platformH = platformW / PLATFORM.aspect
		local platform = glyph(portrait, "Platform", portraitBox.w, portraitBox.h, {
			x = portraitBox.w / 2,
			y = portraitBox.h * PLATFORM.centre,
			w = platformW,
			h = platformH,
		}, UIAssets.WorkshopCards and UIAssets.WorkshopCards.Platform)
		platform.ScaleType = Enum.ScaleType.Stretch
		--- Under the car: the viewport is made at the portrait's own ZIndex, so this goes one below it.
		platform.ZIndex = portrait.ZIndex - 1

		--- CHANGE CAR: a car before the caption.
		local changeW = change.Size.X.Scale * showBox.w
		local changeH = change.Size.Y.Scale * showBox.h
		local carSide = changeH * CHANGE_GLYPH.h
		glyph(change, "Glyph", changeW, changeH, { x = changeW * CHANGE_GLYPH.x, y = changeH / 2, w = carSide * 1.6, h = carSide }, glyphs.Car)
		local changeTitle = change:FindFirstChild("Title")
		if changeTitle and changeTitle:IsA("GuiObject") then
			changeTitle.Position = UDim2.fromScale(CHANGE_TITLE.x, changeTitle.Position.Y.Scale)
			changeTitle.Size = UDim2.fromScale(CHANGE_TITLE.w, changeTitle.Size.Y.Scale)
		end

		-- === The right column: deep blue ====================================
		local mainGradient = Instance.new("UIGradient")
		mainGradient.Color = COLUMN_FACE
		mainGradient.Rotation = 90
		mainGradient.Parent = main

		-- === The card templates =============================================
		--- Copied out BEFORE the list is emptied: the row goes, and `Destroy` takes its buttons with it,
		--- so a clone made after is an empty frame.
		btns = btns:Clone()
		for _, child in list:GetChildren() do
			if child ~= swatch then
				child:Destroy()
			end
		end
		list:SetAttribute("CardWidth", cardW)
		list:SetAttribute("CardGap", CARD_GAP)
		list:SetAttribute("RowSide", ROW_SIDE)
		list:SetAttribute("ListPad", LIST_PAD)
		list:SetAttribute("ReferenceWidth", listW)
		list:SetAttribute("ReferenceHeight", listH)
		--- The five row colours, carried on as V2 stamped them, for the controller to hand the part tiles.
		for index, colour in colours do
			list:SetAttribute("Color" .. index, colour)
		end
		list:SetAttribute("ColorCount", #colours)

		--- One card: the navy face, the tile, the title. Everything else is per kind.
		local function card(name: string, h: number, colour: number, image: number?): (Frame, TextLabel)
			local frame = Instance.new("Frame")
			frame.Name = name
			frame.Visible = false
			frame.ZIndex = list.ZIndex + 1
			frame.Size = UDim2.fromScale(cardW / listW, h / listH)
			dress(frame, CARD_FACE, CARD_RIM, RIM, CORNER, cardW, h)
			frame:SetAttribute("Height", h)

			local tile = close:Clone() :: GuiObject
			untag(tile)
			tile.Name = "Tile"
			if tile:IsA("GuiButton") then
				tile.Active = false
				tile.AutoButtonColor = false
				tile.Selectable = false
			end
			local kitSide = close.Size.Y.Scale * headerBox.h
			refit(tile, kitSide, kitSide, TILE.size, TILE.size)
			local tileTop = if name == "PaintCard" then TILE.left else (h - TILE.size) / 2
			setBox(tile, cardW, h, edges(TILE.left, tileTop, TILE.left + TILE.size, tileTop + TILE.size))
			tile.ZIndex = frame.ZIndex + 1
			local face = tile:FindFirstChildOfClass("UIGradient")
			if face and typeof(colours[colour]) == "ColorSequence" then
				face.Color = colours[colour]
			end
			local x = tile:FindFirstChild("Icon")
			if x then
				x:Destroy()
			end
			local art = glyph(tile, "Glyph", TILE.size, TILE.size, { x = TILE.size / 2, y = TILE.size / 2, w = TILE.size * 0.72, h = TILE.size * 0.72 }, image)
			art.ZIndex = tile.ZIndex + 3
			tile.Parent = frame

			local cardTitle = label(title, frame, "Title", cardW, h, edges(TEXT_LEFT, TITLE.top, TEXT_LEFT + TITLE.w, TITLE.top + TITLE.h), PLACEHOLDER.PartTitle)
			return frame, cardTitle
		end

		--- The button pair against the right edge, V2's `Btns` resized, each face given a second line.
		local function buttons(parent: Frame, h: number, centreY: number, h2: number?): Frame
			local bh = h2 or BUTTON.h
			local pair = btns:Clone()
			pair.Name = "Btns"
			setBox(pair, cardW, h, { x = cardW - BUTTON.right - BUTTON.w / 2, y = centreY, w = BUTTON.w, h = bh })
			pair.ZIndex = parent.ZIndex + 1
			for _, face in pair:GetChildren() do
				if face:IsA("GuiObject") then
					refit(face, V2_BUTTON.w, V2_BUTTON.h, BUTTON.w, bh)
					face.Visible = face.Name == "BuyBtn"
					local caption = face:FindFirstChild("Title")
					if caption and caption:IsA("TextLabel") then
						if face.Name == "BuyBtn" then
							--- Two lines: the verb over the price, each its own label so each fits alone.
							caption.Position = UDim2.fromScale(0.5, 0.3)
							caption.Size = UDim2.fromScale(0.9, 0.46)
							caption.Text = oneLine(PLACEHOLDER.Verb)
							capTo(caption, bh * 0.46, 1)
							local price = caption:Clone()
							price.Name = "Price"
							price.Position = UDim2.fromScale(0.5, 0.7)
							price.Size = UDim2.fromScale(0.9, 0.46)
							price.Text = oneLine(PLACEHOLDER.Price)
							price.Parent = face
						else
							caption.Text = oneLine(PLACEHOLDER.Maxed)
							capTo(caption, bh * caption.Size.Y.Scale, 1)
						end
					end
				end
			end
			pair.Parent = parent
			return pair
		end

		local function gainLabel(parent: Frame, h: number): TextLabel
			local right = cardW - BUTTON.right - BUTTON.w - GAIN.gap
			local gain = label(title, parent, "Gain", cardW, h, edges(right - GAIN.w, (h - GAIN.h) / 2, right, (h + GAIN.h) / 2), PLACEHOLDER.Gain, Enum.TextXAlignment.Right)
			gain.TextColor3 = GAIN_GREEN
			return gain
		end

		--- REPAIR.
		local repair = card("RepairCard", REPAIR_H, 1, glyphs.Repair)
		repair.Title.Text = oneLine(PLACEHOLDER.RepairTitle)
		local repairSub = label(title, repair, "Sub", cardW, REPAIR_H, edges(TEXT_LEFT, SUB.top, TEXT_LEFT + BAR.left - TEXT_LEFT - 14, SUB.top + SUB.h), PLACEHOLDER.RepairSub)
		repairSub.TextColor3 = GAIN_GREEN
		local bar = conditionBar:Clone()
		bar.Name = "Bar"
		bar.ZIndex = repair.ZIndex + 1
		local fullRight = cardW - BAR.pctW - BAR.pctGap - BUTTON.right
		refit(bar, V2_BAR.w, V2_BAR.h, fullRight - BAR.left, BAR.h)
		setBox(bar, cardW, REPAIR_H, edges(BAR.left, (REPAIR_H - BAR.h) / 2, fullRight, (REPAIR_H + BAR.h) / 2))
		bar.Parent = repair
		local pct = label(title, repair, "Percent", cardW, REPAIR_H, edges(fullRight + BAR.pctGap, (REPAIR_H - 30) / 2, fullRight + BAR.pctGap + BAR.pctW, (REPAIR_H + 30) / 2), PLACEHOLDER.Percent, Enum.TextXAlignment.Center)
		pct.Name = "Percent"
		local repairBtns = buttons(repair, REPAIR_H, REPAIR_H / 2)
		repairBtns.Visible = false
		--- Where the bar and its percentage go when there is a button: short of it by the value gap.
		local shortRight = cardW - BUTTON.right - BUTTON.w - GAIN.gap - BAR.pctW - BAR.pctGap
		repair:SetAttribute("BarLeft", BAR.left)
		repair:SetAttribute("BarRightFull", fullRight)
		repair:SetAttribute("BarRightShort", shortRight)
		repair:SetAttribute("PercentWidth", BAR.pctW)
		repair:SetAttribute("PercentGap", BAR.pctGap)
		repair.Parent = list

		--- PAINT. Laid out for two lines of swatches; the controller moves the swatch block and the
		--- button for any other count, from these attributes.
		local paint = card("PaintCard", PAINT_H, 3, glyphs.Paint)
		paint.Title.Text = oneLine(PLACEHOLDER.PaintTitle)
		local paintSub = label(title, paint, "Sub", cardW, PAINT_H, edges(TEXT_LEFT, PAINT_SUB.top, TEXT_LEFT + PAINT_SUB.w, PAINT_SUB.top + PAINT_SUB.h), PLACEHOLDER.PaintSub)
		paintSub.TextColor3 = Color3.fromRGB(206, 214, 232)
		local swatchesH = 2 * SWATCH + SWATCH_GAP
		local paintBtns = buttons(paint, PAINT_H, PAINT_HEAD + swatchesH / 2)
		local paintFace = paintBtns:FindFirstChild("BuyBtn")
		local paintGradient = paintFace and paintFace:FindFirstChildOfClass("UIGradient")
		if paintGradient and typeof(colours[PAINT_BUTTON_COLOUR]) == "ColorSequence" then
			paintGradient.Color = colours[PAINT_BUTTON_COLOUR]
		end
		for _, face in paintBtns:GetChildren() do
			local verb = face:FindFirstChild("Title")
			local price = face:FindFirstChild("Price")
			if verb and verb:IsA("TextLabel") then
				verb.Text = oneLine(PLACEHOLDER.PaintVerb)
			end
			if price and price:IsA("TextLabel") then
				price.Text = oneLine(PLACEHOLDER.PaintPrice)
			end
		end
		paint:SetAttribute("Head", PAINT_HEAD)
		paint:SetAttribute("Foot", PAINT_FOOT)
		paint:SetAttribute("SwatchLeft", TEXT_LEFT)
		paint:SetAttribute("Swatch", SWATCH)
		paint:SetAttribute("SwatchGap", SWATCH_GAP)
		paint:SetAttribute("SwatchColumns", SWATCH_COLUMNS)
		paint:SetAttribute("ButtonRight", BUTTON.right)
		paint:SetAttribute("ButtonWidth", BUTTON.w)
		paint:SetAttribute("ButtonHeight", BUTTON.h)
		paint:SetAttribute("TileLeft", TILE.left)
		paint:SetAttribute("TileSize", TILE.size)
		paint:SetAttribute("TitleTop", TITLE.top)
		paint:SetAttribute("TitleHeight", TITLE.h)
		paint:SetAttribute("SubTop", PAINT_SUB.top)
		paint:SetAttribute("SubHeight", PAINT_SUB.h)
		paint.Parent = list

		--- A PART. The tile colour and glyph are the controller's, per part.
		local part = card("PartCard", PART_H, 2, nil)
		label(title, part, "Level", cardW, PART_H, edges(TEXT_LEFT, LEVEL.top, TEXT_LEFT + LEVEL.w, LEVEL.top + LEVEL.h), PLACEHOLDER.Level)
		local dots = Instance.new("Frame")
		dots.Name = "Dots"
		dots.BackgroundTransparency = 1
		dots.ZIndex = part.ZIndex + 1
		local levels = CustomizeConfig.PartLevels
		local dotsW = levels * DOT.size + (levels - 1) * DOT.gap
		local dotsTop = LEVEL.top + (LEVEL.h - DOT.size) / 2
		setBox(dots, cardW, PART_H, edges(DOT.left, dotsTop, DOT.left + dotsW, dotsTop + DOT.size))
		for level = 1, levels do
			local dot = Instance.new("Frame")
			dot.Name = "Dot" .. level
			dot.ZIndex = dots.ZIndex + 1
			setBox(dot, dotsW, DOT.size, edges((level - 1) * (DOT.size + DOT.gap), 0, (level - 1) * (DOT.size + DOT.gap) + DOT.size, DOT.size))
			dress(dot, DOT_OFF, Color3.fromRGB(2, 30, 56), 2, DOT.size / 2, DOT.size, DOT.size)
			dot.Parent = dots
		end
		dots:SetAttribute("OffColor", DOT_OFF)
		dots.Parent = part
		gainLabel(part, PART_H)
		buttons(part, PART_H, PART_H / 2)
		part.Parent = list

		--- The swatch: V2's at this card's size, and a ring for the colour picked but not bought yet.
		refit(swatch, V2_SWATCH, V2_SWATCH, SWATCH, SWATCH)
		local ring = Instance.new("Frame")
		ring.Name = "Ring"
		ring.BackgroundTransparency = 1
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromScale(1, 1)
		ring.ZIndex = swatch.ZIndex + 3
		ring.Visible = false
		--- One shell: a frame whose edge sits `offset` pixels beyond the swatch's, stroked `width` pixels
		--- outward, its corner grown by `offset` so every shell is concentric with the swatch.
		local function shell(name: string, offset: number, width: number, colour: Color3, transparency: number, z: number)
			local side = SWATCH + 2 * offset
			local frame = Instance.new("Frame")
			frame.Name = name
			frame.BackgroundTransparency = 1
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.Position = UDim2.fromScale(0.5, 0.5)
			frame.Size = UDim2.fromScale(side / SWATCH, side / SWATCH)
			frame.ZIndex = z
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new((SWATCH_CORNER * SWATCH + offset) / side, 0)
			corner.Parent = frame
			local stroke = Instance.new("UIStroke")
			stroke.Color = colour
			stroke.Transparency = transparency
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
			stroke.Thickness = width / side
			stroke.Parent = frame
			frame.Parent = ring
		end
		shell("Hairline", -RING_HAIRLINE, RING_HAIRLINE, Color3.new(1, 1, 1), 0, ring.ZIndex + 1)
		shell("Band", 0, RING_BAND, GAIN_GREEN, 0, ring.ZIndex + 1)
		local reach = RING_BAND
		for step, glow in RING_GLOW do
			shell("Glow" .. step, reach, glow[1], GAIN_GREEN, glow[2], ring.ZIndex)
			reach += glow[1]
		end
		ring.Parent = swatch
		list:SetAttribute("Swatch", SWATCH)

		local existing = shelf:FindFirstChild(ENTRY_NAME)
		if existing then
			existing:Destroy()
		end
		panel.Visible = false
		panel.Parent = shelf

		out:print(string.format("Built %s.%s.%s from %s.", SCREEN_NAME, SHELF_NAME, ENTRY_NAME, SOURCE_NAME))
		out:print(string.format("Cards %dpx wide: REPAIR %d, PAINT %d (two lines of %d), each part %d.", math.round(cardW), REPAIR_H, PAINT_H, SWATCH_COLUMNS, PART_H))
		if not (UIAssets.WorkshopCards and UIAssets.WorkshopCards.Glyphs) then
			out:warn("UIAssets.WorkshopCards has no glyphs yet; the tiles are blank until it does (the controller sets them).")
		end
		pcall(function()
			props:SetSelection({ panel })
		end)
	end,
} :: Types.ScriptModule
