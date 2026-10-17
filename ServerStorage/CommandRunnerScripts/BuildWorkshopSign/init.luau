--[[
	BuildWorkshopSign: Command Runner command

	Gives the workshop podium's CUSTOMIZE sign a KIT face (2026-09-30), the second face beside the
	classic purple plaque, on every `CarSlot` whose `SlotIndex` is `CustomizeConfig.Bay.SlotIndex`.
	`UpgradeController` shows one face or the other per client (`NewUIConfig.KitWorkshopSign`), the
	same two-face trick the forecourt billboard uses, so the old UI keeps its plaque untouched.

	=== WHAT IT LOOKS LIKE ======================================================================

	A small window in the Cartoony Kit's own vocabulary, every piece CLONED out of the kit's
	`UpgradesUI` frame (`ServerStorage.UIImports.NewUITemplate`), the shape its `DonationUI` has:

	    UpgradeBoard
	      UpgradeGui            the classic plaque, authored DISABLED
	      BackPlate             its back, authored DISABLED
	      UpgradeGuiKit         Front, the AUTHORED face
	        Panel               transparent, the name the controller walks
	          UpgradeButton     the kit window: cyan, weave, rims. THE WHOLE FACE, the only control
	            Content         hidden on an unowned lot (`GarageService._drawKiosk`)
	              Header        "Workshop" in the kit's title, nothing else
	              Main          the kit's white body
	                Info        "Repair  Paint  Parts": bare glyphs and plain navy words, one line
	                Go          the kit's green button, most of the body, "Customize"

	ONLY THE GREEN BUTTON LOOKS PRESSABLE (Dylan, 2026-09-30). The version before put Repair, Paint
	and Parts on the kit's gradient cards and the wrench in the kit's square (its close button), and
	in game all four read as buttons that did nothing. Anything that is information here is bare type
	and bare glyphs; anything shaped like a kit control is the control.
	      BackPlateKit          Back, authored: the kit window, blank

	THE KIT FACE IS THE AUTHORED ONE (Dylan, 2026-09-30), so the place shows it in Studio and it is
	what a board the controller never reaches displays. A player on the old UI, or with
	`NewUIConfig.KitWorkshopSign` off, gets the plaque back from `UpgradeController._bindKiosk`,
	which writes both faces' `Enabled` locally.

	The words and the cards are `CustomizeConfig.Kiosk` (`KitTitle`, `KitButton`, `KitCards`). Every
	label is stamped with `KitTextAttribute`, which is how `GarageService` finds and redraws them.

	NOTHING ON IT IS A GuiButton BUT THE FACE. The kit's square and green buttons are rebuilt as
	Frames, because a button nested in the face would take the click for itself and the press would go
	nowhere, and their `UIButton` tags go with them (that is screen UI).

	NO CanvasGroup. The kit clips its weave and its button gloss through CanvasGroups, each of which
	renders to a texture at its full pixel size, on six plots. The weave is cropped with `ImageRect`
	instead and the gloss is clipped by a plain frame (it is not rotated, so the clip is exact), the
	recipe `BuildPlotUpgradeSigns` set for the forecourt billboard.

	OPAQUE. The board part is invisible, so anything see-through on the face shows the showroom behind
	it. Every surface here has a solid background under its gradient.

	Idempotent: both kit SurfaceGuis are destroyed and rebuilt every run, and the classic pair is
	switched off again.

	HOUSE RULE: no wiki-style double-bracket links in this comment; the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Types = require(script.Types)

local CustomizeConfig = require(ReplicatedStorage.shared.Configs.CustomizeConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local UpgradeConfig = require(ReplicatedStorage.shared.Configs.UpgradeConfig)

local KIT_FOLDER = "UIImports"
local KIT_NAME = "NewUITemplate" -- NewUIConfig's template, a Folder holding the pack's ScreenGui
local KIT_FRAME = "UpgradesUI"
local CLASSIC_BACK_NAME = "BackPlate" -- BuildSlotUpgradeBoards's back face

-- === Geometry, in canvas pixels (100 px a stud, so the 5.4 x 2.4 board is 540 x 240) ==========

--- The kit window, inset so its outer rim draws on the board rather than off its edge.
local PANEL_INSET = 6
--- In the window's own pixels (528 x 228 at the default board).
--- The header: the title alone, at the kit's own inset.
local HEADER = { top = 6, h = 46, left = 16, titleW = 330, cap = 40 }
local MAIN = { side = 10, top = 56, bottom = 10 }
--- In the white body's pixels: the info line, then the green button under it.
local PAD = 10
local INFO = { top = 8, h = 34, glyph = 28, glyphGap = 5, itemGap = 22, text = 24 }
local GO_GAP = 6
local GO_CAP = 50

--- Corners and rims, in pixels. The kit sets them as scales of a screen-sized window; at sign size
--- those come out hairline, so they are set to the weight the kit's own windows show on screen.
local PANEL_CORNER, PANEL_RIM = 14, 5
local MAIN_CORNER, MAIN_RIM = 10, 3.5
local GO_CORNER, GO_RIM = 12, 5
--- One weave cell, in pixels.
local PANEL_CELL = 22

--- The info line's words: the kit's outline navy as a plain fill, the colour type takes on its white
--- body. No outline, no shape behind it: it is information, not a control.
local INFO_TEXT = Color3.fromHex("021e38")
local INFO_FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")

-- === Helpers =================================================================

local function px(gui: GuiObject, pw: number, ph: number, left: number, top: number, w: number, h: number)
	gui.AnchorPoint = Vector2.zero
	gui.Position = UDim2.fromScale(left / pw, top / ph)
	gui.Size = UDim2.fromScale(w / pw, h / ph)
end

--- Every `ScaledSize` rim on `target` set to `rimPx` pixels on a box `short` pixels on its short side.
local function rims(target: Instance, short: number, rimPx: number)
	for _, child in target:GetChildren() do
		if child:IsA("UIStroke") then
			child.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
			child.Thickness = rimPx / short
		end
	end
end

local function corners(target: Instance, cornerPx: number)
	for _, child in target:GetChildren() do
		if child:IsA("UICorner") then
			child.CornerRadius = UDim.new(0, cornerPx)
		end
	end
end

local function isDecoration(child: Instance): boolean
	return child:IsA("UIGradient") or child:IsA("UIStroke") or child:IsA("UICorner")
end

--- A solid frame (or the face's TextButton) wearing a kit element's gradient, strokes and corner.
local function dressed(className: "Frame" | "TextButton", name: string, source: Instance): GuiObject
	local f: GuiObject
	if className == "TextButton" then
		local button = Instance.new("TextButton")
		button.Text = ""
		button.AutoButtonColor = false
		f = button
	else
		f = Instance.new("Frame")
	end
	f.Name = name
	f.BackgroundColor3 = if source:IsA("GuiObject") then source.BackgroundColor3 else Color3.new(1, 1, 1)
	f.BackgroundTransparency = 0
	f.BorderSizePixel = 0
	for _, child in source:GetChildren() do
		if isDecoration(child) then
			child:Clone().Parent = f
		end
	end
	return f
end

--[[ The kit's weave, cropped rather than clipped (header). `sizePx` is the surface's own pixels. The
	texture is a pre-rotated square whose corners are transparent, so the crop is taken from inside it
	at the surface's aspect. 14.3 is the texture's own cell, measured for the billboard. ]]
local function checker(parent: GuiObject, source: ImageLabel, sizePx: Vector2, cellPx: number, cornerPx: number)
	local texel = 14.3
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
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, cornerPx)
	corner.Parent = l
	l.Parent = parent
	return l
end

--[[ A kit button rebuilt as a Frame (header): same face, rim, gloss and caption, nothing that takes
	input. Its `BG` CanvasGroup becomes a clipping frame; its icon and caption are left to the caller. ]]
local function buttonFrame(source: GuiObject, name: string): Frame
	local f = dressed("Frame", name, source) :: Frame
	for _, child in source:GetChildren() do
		if isDecoration(child) or child:IsA("UITextSizeConstraint") then
			continue
		elseif child:IsA("CanvasGroup") then
			local clip = Instance.new("Frame")
			clip.Name = child.Name
			clip.BackgroundTransparency = 1
			clip.BorderSizePixel = 0
			clip.AnchorPoint = child.AnchorPoint
			clip.Position = child.Position
			clip.Size = child.Size
			clip.ClipsDescendants = true
			for _, inner in child:GetChildren() do
				inner:Clone().Parent = clip
			end
			clip.Parent = f
		elseif child:IsA("GuiObject") and child.Name == "Container" then
			child:Clone().Parent = f -- the rim
		end
	end
	return f
end

--[[ A kit label: a clone of one of the kit's own (its font, colour and outline), with new words, a
	cap in canvas pixels, and the attribute `GarageService` redraws it by. ]]
local function word(source: TextLabel, name: string, key: string, cap: number, align: Enum.TextXAlignment): TextLabel
	local l = source:Clone()
	l.Name = name
	l.Text = CustomizeConfig.kioskText(key) or key
	l.TextScaled = true
	l.TextXAlignment = align
	l.AnchorPoint = Vector2.zero
	l.ZIndex = 3
	for _, tag in l:GetTags() do
		l:RemoveTag(tag)
	end
	local constraint = l:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = cap
	constraint.MinTextSize = 1
	constraint.Parent = l
	l:SetAttribute(CustomizeConfig.Kiosk.KitTextAttribute, key)
	return l
end

local function glyphImage(parent: Instance, key: string, size: number): ImageLabel?
	local glyphs = UIAssets.WorkshopCards and UIAssets.WorkshopCards.Glyphs
	local id = glyphs and glyphs[key]
	if not id then
		return nil
	end
	local l = Instance.new("ImageLabel")
	l.Name = "Glyph"
	l.BackgroundTransparency = 1
	l.Image = "rbxassetid://" .. tostring(id)
	l.ScaleType = Enum.ScaleType.Fit
	l.ZIndex = 3
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, 0.5)
	l.Size = UDim2.fromScale(size, size)
	l.Parent = parent
	return l
end

--[[ A kit SurfaceGui, made from the classic one beside it so every property that makes the plaque
	work (face, pixels per stud, light influence, `Active`) is the same. Sibling z-order, since every
	z here is relative to its parent. ]]
local function kitSurface(from: SurfaceGui, name: string): SurfaceGui
	local gui = from:Clone()
	gui.Name = name
	gui:ClearAllChildren()
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = true -- the authored face; see the header
	return gui
end

-- === The kit's parts =========================================================

type Parts = {
	panel: GuiObject,
	weave: ImageLabel?,
	title: TextLabel,
	main: GuiObject,
	button: GuiObject,
}

local function partsOf(frame: Instance): Parts?
	local header = frame:FindFirstChild("Header")
	local main = frame:FindFirstChild("Main")
	local list = main and main:FindFirstChild("ScrollingFrame")
	local card
	for _, child in (if list then list:GetChildren() else {}) do
		if child.Name == "Template" and child:FindFirstChild("Btns") then
			card = child
			break
		end
	end
	local btns = card and card:FindFirstChild("Btns")
	local bg = frame:FindFirstChild("BG")
	local parts = {
		panel = frame,
		weave = bg and bg:FindFirstChild("CheckersBG"),
		title = header and header:FindFirstChild("Title"),
		main = main,
		button = btns and btns:FindFirstChild("RebirthBtn"),
	}
	for _, key in { "title", "main", "button" } do
		if not parts[key] then
			return nil
		end
	end
	return parts :: any
end

-- === The build ===============================================================

--- The kit window, its weave and rims, centred in `parent` (`w` x `h` pixels) less the inset.
local function window(parent: Instance, kit: Parts, className: "Frame" | "TextButton", name: string, w: number, h: number): (GuiObject, number, number)
	local fw, fh = w - 2 * PANEL_INSET, h - 2 * PANEL_INSET
	local face = dressed(className, name, kit.panel)
	--- Centred, so the controller's press (a Size tween) shrinks it about its middle.
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.Size = UDim2.fromScale(fw / w, fh / h)
	rims(face, math.min(fw, fh), PANEL_RIM)
	corners(face, PANEL_CORNER)
	if kit.weave and kit.weave:IsA("ImageLabel") then
		checker(face, kit.weave, Vector2.new(fw, fh), PANEL_CELL, PANEL_CORNER)
	end
	face.Parent = parent
	return face, fw, fh
end

local function buildFront(board: BasePart, classic: SurfaceGui, kit: Parts, sign: any): SurfaceGui
	local w, h = board.Size.X * classic.PixelsPerStud, board.Size.Y * classic.PixelsPerStud
	local gui = kitSurface(classic, sign.KitGuiName)

	local holder = Instance.new("Frame")
	holder.Name = UpgradeConfig.Bay.PanelName
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = gui

	local face, fw, fh = window(holder, kit, "TextButton", UpgradeConfig.Bay.ButtonName, w, h)

	local content = Instance.new("Frame")
	content.Name = sign.KitContentName
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = 2
	content.Parent = face

	--[[ The header: the kit's title and nothing else. No wrench in it (Dylan, 2026-09-30): Repair's
		glyph on the line below is the same wrench, so a second one in the header was a repeat. And no
		kit square: that is the kit's close button, and on the sign it read as a thing to press. ]]
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	px(header, fw, fh, 0, HEADER.top, fw, HEADER.h)
	header.ZIndex = 2
	header.Parent = content

	local title = word(kit.title, "Title", "KitTitle", HEADER.cap, Enum.TextXAlignment.Left)
	px(title, fw, HEADER.h, HEADER.left, 0, HEADER.titleW, HEADER.h)
	title.Parent = header

	-- The white body.
	local mw, mh = fw - 2 * MAIN.side, fh - MAIN.top - MAIN.bottom
	local main = dressed("Frame", "Main", kit.main)
	px(main, fw, fh, MAIN.side, MAIN.top, mw, mh)
	main.ZIndex = 2
	rims(main, math.min(mw, mh), MAIN_RIM)
	corners(main, MAIN_CORNER)
	main.Parent = content

	--[[ What the workshop does, as ONE LINE OF PLAIN TYPE: a bare glyph and a navy word per item,
		centred, nothing behind them. It used to be three of the kit's gradient cards, which are the
		kit's button shape, and players read them as three buttons. Laid out by a list so the words
		take their own width; `TextSize` is fixed for that reason (a scaled label has no width of its
		own to report). ]]
	local info = Instance.new("Frame")
	info.Name = "Info"
	info.BackgroundTransparency = 1
	px(info, mw, mh, PAD, INFO.top, mw - 2 * PAD, INFO.h)
	info.ZIndex = 2
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(0, INFO.itemGap)
	row.Parent = info
	for index, spec in sign.KitCards do
		local item = Instance.new("Frame")
		item.Name = spec.Label
		item.BackgroundTransparency = 1
		item.LayoutOrder = index
		item.AutomaticSize = Enum.AutomaticSize.X
		item.Size = UDim2.fromOffset(0, INFO.h)
		item.ZIndex = 2
		local pair = Instance.new("UIListLayout")
		pair.FillDirection = Enum.FillDirection.Horizontal
		pair.VerticalAlignment = Enum.VerticalAlignment.Center
		pair.SortOrder = Enum.SortOrder.LayoutOrder
		pair.Padding = UDim.new(0, INFO.glyphGap)
		pair.Parent = item

		local glyphBox = Instance.new("Frame")
		glyphBox.Name = "Icon"
		glyphBox.BackgroundTransparency = 1
		glyphBox.LayoutOrder = 1
		glyphBox.Size = UDim2.fromOffset(INFO.glyph, INFO.glyph)
		glyphBox.ZIndex = 3
		glyphImage(glyphBox, spec.Glyph, 1)
		glyphBox.Parent = item

		local label = Instance.new("TextLabel")
		label.Name = "Title"
		label.BackgroundTransparency = 1
		label.LayoutOrder = 2
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromOffset(0, INFO.h)
		label.FontFace = INFO_FONT
		label.TextColor3 = INFO_TEXT
		label.TextSize = INFO.text
		label.Text = CustomizeConfig.kioskText(spec.Key) or spec.Label
		label.ZIndex = 3
		label:SetAttribute(CustomizeConfig.Kiosk.KitTextAttribute, spec.Key)
		label.Parent = item
		item.Parent = info
	end
	info.Parent = main

	-- The kit's green button, most of the body: the one thing on the sign that looks pressable.
	local goTop = INFO.top + INFO.h + GO_GAP
	local goH = mh - goTop - PAD
	local go = buttonFrame(kit.button, sign.KitButtonName)
	px(go, mw, mh, PAD, goTop, mw - 2 * PAD, goH)
	-- Anchored on its centre (Dylan, 2026-09-30), so a resize or the hover lift grows it in place.
	go.AnchorPoint = Vector2.new(0.5, 0.5)
	go.Position = UDim2.fromScale(0.5, (goTop + goH / 2) / mh)
	go.ZIndex = 2
	corners(go, GO_CORNER)
	local goRim = go:FindFirstChild("Container")
	if goRim then
		rims(goRim, goH, GO_RIM)
		corners(goRim, GO_CORNER)
	end
	local buttonTitle = kit.button:FindFirstChild("Title")
	if buttonTitle and buttonTitle:IsA("TextLabel") then
		local caption = word(buttonTitle, "Title", "KitButton", GO_CAP, Enum.TextXAlignment.Center)
		caption.AnchorPoint = Vector2.new(0.5, 0.5)
		caption.Position = UDim2.fromScale(0.5, 0.5)
		caption.Size = UDim2.fromScale(0.9, 0.66)
		caption.ZIndex = 4
		caption.Parent = go
	end
	go.Parent = main

	gui.Parent = board
	return gui
end

local function buildBack(board: BasePart, classicBack: SurfaceGui, kit: Parts, sign: any): SurfaceGui
	local w, h = board.Size.X * classicBack.PixelsPerStud, board.Size.Y * classicBack.PixelsPerStud
	local gui = kitSurface(classicBack, sign.KitBackName)
	gui.Active = false
	window(gui, kit, "Frame", UpgradeConfig.Bay.PanelName, w, h)
	gui.Parent = board
	return gui
end

return {
	Description = "Give the workshop podium's CUSTOMIZE sign its kit face (UpgradeGuiKit + BackPlateKit), a small window built from the Cartoony Kit's UpgradesUI pieces, on every workshop CarSlot. Rebuilds both kit faces every run; the classic plaque is untouched.",
	Tags = { "UI", "NewUI" },
	AutoRecordChanges = true,

	Arguments = {} :: Types.ArgumentType,

	Run = function(props: Types.Props, _arguments: Types.ArgumentResult)
		local out = props:Output()
		local sign = CustomizeConfig.Kiosk
		local names = UpgradeConfig.Bay

		local imports = ServerStorage:FindFirstChild(KIT_FOLDER)
		local template = imports and imports:FindFirstChild(KIT_NAME)
		local frame = template and template:FindFirstChild(KIT_FRAME, true)
		local kit = frame and partsOf(frame)
		if not kit then
			out:error(string.format("No complete %s under ServerStorage.%s.%s.", KIT_FRAME, KIT_FOLDER, KIT_NAME))
			return
		end

		local built, skipped = {}, 0
		for _, slot in CollectionService:GetTagged(GarageConfig.SlotTag) do
			if slot:GetAttribute(GarageConfig.SlotIndexAttribute) ~= CustomizeConfig.Bay.SlotIndex then
				continue
			end
			local model = slot:FindFirstChild(names.ModelName)
			local board = model and model:FindFirstChild(names.BoardName)
			local classic = board and board:FindFirstChild(names.GuiName)
			local classicBack = board and board:FindFirstChild(CLASSIC_BACK_NAME)
			if not (board and board:IsA("BasePart") and classic and classic:IsA("SurfaceGui")) then
				skipped += 1
				out:warn(string.format("%s has no %s.%s.%s; skipped.", slot:GetFullName(), names.ModelName, names.BoardName, names.GuiName))
				continue
			end
			for _, old in { sign.KitGuiName, sign.KitBackName } do
				local existing = board:FindFirstChild(old)
				if existing then
					existing:Destroy()
				end
			end
			table.insert(built, buildFront(board, classic, kit, sign))
			classic.Enabled = false
			if classicBack and classicBack:IsA("SurfaceGui") then
				buildBack(board, classicBack, kit, sign)
				classicBack.Enabled = false
			end
		end

		out:print(string.format("Built the kit face on %d workshop sign(s), skipped %d.", #built, skipped))
		pcall(function()
			props:SetSelection(built)
		end)
	end,
} :: Types.ScriptModule
