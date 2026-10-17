--[[
	BuildWorldPromptV2
	------------------
	Builds `StarterGui.MainUIV2.Screens.WorldPrompt`, the Cartoony Kit face of the in-world prompt
	card (`GlassPromptController`, `GlassPromptConfig.KitStyle`), cut from the kit's `PromptUI`: the
	same frame the buyer's sign and the sell lot's question are cut from, so a podium's prompt is one
	family with the screens it opens.

	    WorldPrompt         the shelf entry; nothing in it is drawn as it stands
	      Card1..Card3      PromptUI's chassis (blue ramp, both rims, the checker) for 1-3 rows
	        Header.Title    the prompt's ObjectText: BAY 3, WORKSHOP
	        Main            the white body
	          Slot1..n      empty boxes the controller drops a row into
	      Row               the MAIN action: the kit's green AcceptBtn, a keycap riding on its face
	        Btn.Key         the kit's white well (PromptUI.Main) shrunk square: Letter, Glyph
	        Btn.Title       the action
	        Btn.Hold        HOLD, on a hold prompt only
	        Btn.Fill        the light that sweeps the face while it is held
	      RowAlt            the same, re-faced in the kit's LEGENDARY ORANGE: every other action

	THE SECOND ROW IS ORANGE BECAUSE THE WORKSHOP SCREEN'S CHANGE CAR IS (`BuildWorkshopV2`'s header
	has the argument): not green, which is every price, not blue, which is the panel, and not the kit's
	red DeclineBtn, which would tell a player that changing their car was the dangerous choice.

	Each card's nominal size, in 1080p pixels, is on it as `NominalWidth`/`NominalHeight`; the
	controller sizes the billboard from those. Every rim is the kit's own `ScaledSize` stroke, so it
	holds its proportion at whatever size the card is drawn, and every text cap is stripped because a
	world card's text has to grow with the card.

	HOUSE RULE: no wiki-style double-bracket links in this comment; the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local SHELF_NAME = "Screens"
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage
local ENTRY_NAME = "WorldPrompt" -- GlassPromptConfig.Kit.Entry
local KIT_FRAME = "PromptUI"
--- The legendary orange, the one `BuildWorkshopV2` re-faces CHANGE CAR in.
local ORANGE_SOURCE = { "IndexUI", "SideBtns", "LegendaryBtn" }
--- The kit's outline navy, for the keycap's letter.
local NAVY = Color3.fromRGB(2, 30, 56)

local REF_W = 1920
local MAX_ROWS = 3

--- The card, in 1080p pixels. See the header for what each region is.
local CARD_W = 300
local EDGE = 10 -- panel edge to the white body, left, right and bottom
local HEADER = { 6, 44 } -- the header band's top and bottom
local MAIN_TOP = 48
local PAD = 8 -- white body edge to a row
local ROW_H = 46
local ROW_GAP = 8
local KEY = 32 -- the keycap, square
local KEY_LEFT = 8
local HOLD_W = 44

type Box = { x: number, y: number, w: number, h: number }

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

local function find(root: Instance, path: { string }): Instance?
	local node: Instance? = root
	for _, step in path do
		node = node and node:FindFirstChild(step)
	end
	return node
end

local function boxOf(gui: GuiObject, pw: number, ph: number): Box
	local w = gui.Size.X.Scale * pw + gui.Size.X.Offset
	local h = gui.Size.Y.Scale * ph + gui.Size.Y.Offset
	local left = gui.Position.X.Scale * pw + gui.Position.X.Offset - gui.AnchorPoint.X * w
	local top = gui.Position.Y.Scale * ph + gui.Position.Y.Offset - gui.AnchorPoint.Y * h
	return { x = left + w / 2, y = top + h / 2, w = w, h = h }
end

--- Put a child at a box in its parent's pixels, as scale on a centre anchor (the kit's convention).
local function setBox(gui: GuiObject, pw: number, ph: number, box: Box)
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui.Position = UDim2.fromScale(box.x / pw, box.y / ph)
	gui.Size = UDim2.fromScale(box.w / pw, box.h / ph)
end

local function edges(left: number, top: number, right: number, bottom: number): Box
	return { x = (left + right) / 2, y = (top + bottom) / 2, w = right - left, h = bottom - top }
end

--- A frame's rim and corner after its SHORTER side went from `before` to `after` pixels.
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

--- The checker keeps its cell size when the panel changes shape (`BuildBuyerOfferV2.keepChecker`).
local function keepChecker(panel: Instance, oldW: number, oldH: number, newW: number, newH: number)
	local bg = panel:FindFirstChild("BG")
	if not bg then
		return
	end
	keepRim(bg, math.min(oldW, oldH), math.min(newW, newH))
	for _, part in bg:GetChildren() do
		if part:IsA("GuiObject") then
			local size = part.Size
			part.Size = UDim2.fromScale(size.X.Scale * oldW / newW, size.Y.Scale * oldH / newH)
		end
	end
end

--- The gloss is sized in fractions of the WIDTH; a wider face would stretch it (`kit-face-gloss-is-width-scaled`).
local function rewidthButton(button: Instance, before: number, after: number)
	local slash = find(button, { "BG", "Slash" })
	if slash and slash:IsA("GuiObject") then
		slash.Size = UDim2.new(slash.Size.X.Scale * before / after, slash.Size.X.Offset, slash.Size.Y)
	end
end

--- Strip text caps (a world card's text grows with it) and the `UIButton` tag (this is not a HUD
--- button: `Components/Button` would bind clicks and sounds to a face the prompt already drives).
local function worldify(root: Instance)
	for _, item in root:GetDescendants() do
		if item:IsA("UITextSizeConstraint") then
			item:Destroy()
		end
	end
	for _, item in { root, table.unpack(root:GetDescendants()) } do
		for _, tag in item:GetTags() do
			item:RemoveTag(tag)
		end
	end
end

--- Pixel height of the card for `n` rows.
local function cardHeight(n: number): number
	return MAIN_TOP + PAD * 2 + n * ROW_H + (n - 1) * ROW_GAP + EDGE
end

local function buildCard(kitFrame: GuiObject, kitW: number, kitH: number, n: number): GuiObject
	local h = cardHeight(n)
	local card = kitFrame:Clone() :: GuiObject
	card.Name = "Card" .. n
	card.Visible = true
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(1, 1)
	local aspect = card:FindFirstChildOfClass("UIAspectRatioConstraint")
	if aspect then
		aspect:Destroy()
	end
	keepRim(card, math.min(kitW, kitH), math.min(CARD_W, h))
	keepChecker(card, kitW, kitH, CARD_W, h)
	card:SetAttribute("NominalWidth", CARD_W)
	card:SetAttribute("NominalHeight", h)

	local header = card:FindFirstChild("Header") :: GuiObject
	local close = header:FindFirstChild("CloseBtn")
	if close then
		close:Destroy()
	end
	local headerBox = edges(EDGE, HEADER[1], CARD_W - EDGE, HEADER[2])
	setBox(header, CARD_W, h, headerBox)
	local title = header:FindFirstChild("Title") :: TextLabel
	title.Text = "WORKSHOP"
	title.TextXAlignment = Enum.TextXAlignment.Left
	setBox(title, headerBox.w, headerBox.h, edges(4, 6, headerBox.w - 4, headerBox.h - 4))

	local main = card:FindFirstChild("Main") :: GuiObject
	local kitMain = boxOf(main, kitW, kitH)
	for _, child in main:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local mainBox = edges(EDGE, MAIN_TOP, CARD_W - EDGE, h - EDGE)
	setBox(main, CARD_W, h, mainBox)
	keepRim(main, math.min(kitMain.w, kitMain.h), math.min(mainBox.w, mainBox.h))

	for i = 1, n do
		local slot = Instance.new("Frame")
		slot.Name = "Slot" .. i
		slot.BackgroundTransparency = 1
		slot.BorderSizePixel = 0
		slot.ZIndex = 2
		local top = PAD + (i - 1) * (ROW_H + ROW_GAP)
		setBox(slot, mainBox.w, mainBox.h, edges(PAD, top, mainBox.w - PAD, top + ROW_H))
		slot.Parent = main
	end
	return card
end

local function buildRow(name: string, kitButton: GuiObject, kitButtonW: number, well: GuiObject, wellMin: number, face: UIGradient?): GuiObject
	local rowW = CARD_W - EDGE * 2 - PAD * 2

	local row = Instance.new("Frame")
	row.Name = name
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.5)
	row.Size = UDim2.fromScale(1, 1)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0

	local btn = kitButton:Clone() :: GuiObject
	btn.Name = "Btn"
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.Position = UDim2.fromScale(0.5, 0.5)
	btn.Size = UDim2.fromScale(1, 1)
	btn.LayoutOrder = 0
	rewidthButton(btn, kitButtonW, rowW)
	if face then
		local gradient = btn:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = face.Color
		end
	end
	btn.Parent = row

	local title = btn:FindFirstChild("Title") :: TextLabel
	title.Text = "Pick Up"
	title.TextXAlignment = Enum.TextXAlignment.Left
	setBox(title, rowW, ROW_H, edges(KEY_LEFT + KEY + 10, ROW_H * 0.2, rowW - HOLD_W - 6, ROW_H * 0.8))

	local hold = title:Clone()
	hold.Name = "Hold"
	hold.Text = "HOLD"
	hold.TextXAlignment = Enum.TextXAlignment.Right
	setBox(hold, rowW, ROW_H, edges(rowW - HOLD_W - 4, ROW_H * 0.32, rowW - 10, ROW_H * 0.68))
	hold.Parent = btn

	--- The hold's sweep: under the caption, over the face. The controller writes its gradient.
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0.5, 0.5)
	fill.Position = UDim2.fromScale(0.5, 0.5)
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	fill.Visible = false
	fill.ZIndex = 2
	local fillCorner = btn:FindFirstChildOfClass("UICorner")
	if fillCorner then
		fillCorner:Clone().Parent = fill
	end
	Instance.new("UIGradient").Parent = fill
	fill.Parent = btn

	--- The keycap: the kit's white well with its navy rim, shrunk to a square.
	local key = well:Clone() :: GuiObject
	key.Name = "Key"
	for _, child in key:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	keepRim(key, wellMin, KEY)
	key.ZIndex = 4
	setBox(key, rowW, ROW_H, edges(KEY_LEFT, (ROW_H - KEY) / 2, KEY_LEFT + KEY, (ROW_H + KEY) / 2))
	key.Parent = btn

	local letter = title:Clone()
	letter.Name = "Letter"
	letter.Text = "E"
	letter.TextColor3 = NAVY
	letter.TextXAlignment = Enum.TextXAlignment.Center
	letter.ZIndex = 5
	for _, child in letter:GetChildren() do
		if child:IsA("UIStroke") then
			child:Destroy()
		end
	end
	setBox(letter, KEY, KEY, edges(KEY * 0.18, KEY * 0.16, KEY * 0.82, KEY * 0.84))
	letter.Parent = key

	local glyph = Instance.new("ImageLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.Size = UDim2.fromScale(1.2, 1.2)
	glyph.ZIndex = 5
	glyph.Visible = false
	glyph.Parent = key

	--- The press dip, on the keycap alone; the face does not move.
	Instance.new("UIScale").Parent = key

	worldify(row)
	return row
end

return {
	Description = "Build StarterGui.MainUIV2.Screens.WorldPrompt, the Cartoony Kit face of the in-world prompt card (the podium's E and F), from the kit's PromptUI: Card1-3 (chassis, header, white body with row slots), Row (green AcceptBtn with a white keycap) and RowAlt (the same in the legendary orange). Rebuilds the shelf entry every run.",
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
		local kitMain = kitFrame and kitFrame:FindFirstChild("Main")
		local accept = kitMain and find(kitMain, { "Btns", "AcceptBtn" })
		local btns = kitMain and kitMain:FindFirstChild("Btns")
		local orangeSource = find(container, ORANGE_SOURCE)
		local orange = orangeSource and orangeSource:FindFirstChildOfClass("UIGradient")
		if not (kitFrame and kitFrame:IsA("GuiObject") and kitMain and kitMain:IsA("GuiObject") and btns and btns:IsA("GuiObject") and accept and accept:IsA("GuiObject") and orange) then
			out:error(string.format("The kit needs %s with Main.Btns.AcceptBtn, and %s's gradient.", KIT_FRAME, table.concat(ORANGE_SOURCE, ".")))
			return
		end

		local kitW = kitFrame.Size.X.Scale * REF_W
		local aspect = kitFrame:FindFirstChildOfClass("UIAspectRatioConstraint")
		local kitH = kitW / (if aspect then aspect.AspectRatio else 2.29)
		local mainBox = boxOf(kitMain, kitW, kitH)
		local btnsBox = boxOf(btns, mainBox.w, mainBox.h)
		local acceptW = accept.Size.X.Scale * btnsBox.w

		local old = shelf:FindFirstChild(ENTRY_NAME)
		if old then
			old:Destroy()
		end
		local entry = Instance.new("Frame")
		entry.Name = ENTRY_NAME
		entry.BackgroundTransparency = 1
		entry.Size = UDim2.fromScale(0, 0)
		entry.Visible = false

		for n = 1, MAX_ROWS do
			local card = buildCard(kitFrame, kitW, kitH, n)
			worldify(card)
			card.Parent = entry
		end
		buildRow("Row", accept, acceptW, kitMain, math.min(mainBox.w, mainBox.h), nil).Parent = entry
		buildRow("RowAlt", accept, acceptW, kitMain, math.min(mainBox.w, mainBox.h), orange).Parent = entry

		entry.Parent = shelf
		out:print(
			string.format(
				"Built %s.%s.%s: Card1-%d (%dpx wide, %d-%dpx tall at 1080p), Row (green) and RowAlt (orange).",
				SCREEN_NAME,
				SHELF_NAME,
				ENTRY_NAME,
				MAX_ROWS,
				CARD_W,
				cardHeight(1),
				cardHeight(MAX_ROWS)
			)
		)
		pcall(function()
			props:SetSelection({ entry })
		end)
	end,
} :: Types.ScriptModule
