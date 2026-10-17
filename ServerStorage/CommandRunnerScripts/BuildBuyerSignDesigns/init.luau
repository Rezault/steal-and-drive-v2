--[[
	BuildBuyerSignDesigns: Command Runner command

	Builds `StarterGui.MainUIV2.Screens.BuyerSigns`, the Folder of world-sign templates for a buyer's
	offer. Added 2026-10-15 from a reference Dylan sent: a blue header with the buyer's face, "OFFER
	FROM" over their name; a white body with sun rays behind a car name, a huge green price and a pill
	saying how far under or over value it is; a navy footer with a clock, "EXPIRES IN 1:03" and a
	draining bar.

	`BuyerConfig.Bubble.Design` picks a template by name and `BuyerOfferSign.buildDesign` clones it.
	`Screens.BuyerSign` (BuildBuyerOfferV2) is NOT touched: the market's seller sign reads its
	layout (`CarDealConfig.Bubble.KitStyle`), so the buyer moved without moving the market.
	Destroys and remakes the folder on every run.

	=== ONE DESIGN, B ========================================================================

	Four were built and photographed side by side for the boss (A the reference as drawn, B with a
	rating badge, C compact, D with the clock hanging under the card). B was chosen the same day and
	the other three were taken out of this file:

	    B   Header: face, OFFER FROM, NAME, and the rating badge (LOW OFFER .. GREAT DEAL) where the
	        reference has its chevrons, a kit button painted per band so the one word that says
	        "take it" survives the redesign. White body: car, price, value pill. The clock is a navy
	        footer INSIDE the card, always showing.

	The footer's clock is the Gvesster pack's "Clock Outline" (`assets/ui/gvesster/Clock.png`), asked
	for by Dylan in place of the kit's red timer, which read as a crosshair.

	=== THE PARTS ===========================================================================

	    chassis      PromptUI: the blue ramp, both rims, the corner and the checker
	    white body   PromptUI.Main
	    face seat    TradeUI ... PlayerInformation.Avatar (the round, checkered avatar well)
	    sun rays     IndexUI's card Sunray, tinted to read on white
	    bar          QuestsUI's ProgressBar
	    badge        PromptUI's AcceptBtn face, with every kit button ramp kept beside it
	    money        the HUD cash counter's gradient
	    type         PromptUI.Main.Title, FredokaOne with the navy ScaledSize outline
	    clock        Gvesster v6 Clock Outline (`UIAssets.BuyerSign.Clock`)

	The other things the kit does not draw are `UIAssets.BuyerSign` too (a tintable arrow and the
	face seat's fallback silhouette), made by `assets/ui/buyer/build_buyer_sign.py`.

	=== AND THE SELLER'S, ON THE SAME CARD (2026-10-15) =====================================

	The seller at the kerb (`SellerConfig`) still wore the old kit sign after the buyer moved to B,
	and Dylan asked for the seller's to be "just slightly different" from the offer, so a player
	can tell somebody SELLING from somebody BUYING. `Screens.SellerSigns` holds it: B's geometry so
	the two still read as one family; `SellerConfig.Bubble.Design` picks it and
	`BuyerOfferSign.buildDesign` clones it from that folder.

	Four variations were photographed side by side (Blue: B with only the words changed; Green;
	Gold; Tag: B's blue with a FOR SALE tag hung over the top edge). Dylan picked GOLD the same day
	and the other three were taken out of this file:

	    Gold    the chassis and the face well in gold (`GOLD_CHASSIS`), so a seller tells apart
	            from the blue buyer before any word on it can be read

	It carries the seller's rating bands as badge ramps (STEAL! gold .. RIP-OFF red), and a pill
	that is green under worth, since a price under worth is good news for a BUYER.

	=== WORLD SPACE ==========================================================================

	The same two rules as `BuildBuyerOfferV2`'s sign: every `UITextSizeConstraint` goes (a cap is
	a screen pixel) and every rim stays `ScaledSize`. Geometry is worked in NOMINAL pixels of a
	sign about as wide as it reads across a bay and written back as scale; the template root
	carries `Aspect` (its width over its height) so the controller sizes the billboard to match.

	HOUSE RULE: no wiki-style double-bracket links in this comment; the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local SHELF_NAME = "Screens"
local FOLDER_NAME = "BuyerSigns"
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage

--- The screen the kit is measured on.
local REF_W = 1920

local KIT = {
	Frame = { "PromptUI" },
	Seat = { "TradeUI", "Main", "You", "PlayerInformation", "Avatar" },
	Sunray = { "IndexUI", "Main", "ScrollingFrame", "Template", "BG", "Sunray" },
	Bar = { "QuestsUI", "Main", "Templates", "Template", "ProgressBar" },
	Accept = { "PromptUI", "Main", "Btns", "AcceptBtn" },
	Decline = { "PromptUI", "Main", "Btns", "DeclineBtn" },
	Gold = { "TimedRewardsUI", "Header", "UnlockAllBtn" },
	Money = { "HUD", "BottomInfo", "Cash", "Title" },
}

--- `UIAssets.BuyerSign`, spelled here because a command runs in the plugin VM, whose require cache
--- can hand back a stale config.
local ART = {
	ArrowTint = 119554516263030,
	Person = 91850622972732,
	Clock = 87525150759633,
}

local INK = Color3.fromRGB(28, 42, 74) -- type on the white body

--- The footer's well: the kit's own dark ramp (CodesUI's Logo) lifted toward the panel's blue, so it
--- reads as the card's floor rather than a hole in it.
local FOOTER_RAMP = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 84, 168)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 44, 100)),
})

--- The rays behind the price: the kit's white rays multiplied down to a cool grey, faint.
local RAY_TINT = Color3.fromRGB(150, 180, 226)
local RAY_TRANSPARENCY = 0.15

--- What a freshly built template reads as in the Explorer. All of it is overwritten per buyer.
local PLACEHOLDER = {
	From = "OFFER FROM",
	Name = "HALT_CEO",
	Car = "BRONZE CHARGENT",
	Amount = "$9,151",
	Pill = "13% BELOW VALUE",
	Badge = "LOW OFFER",
	Time = 'EXPIRES IN <font color="#FFD21F">1:03</font>',
}

--[[ Each design in nominal pixels. `panel` is the card's height; `seat`, `from`, `name` and `badge`
	sit in the header band; `main` is the white body's top and bottom; the body's rows are
	{ top, bottom } in the body's own pixels; `footer` is { top, bottom } in the PANEL's pixels and
	overlaps the body's floor, as the reference draws it.

	500 wide since the same afternoon (was 420, 1.33 : 1): Dylan found the card too square and asked
	for it longer, towards the compact design's proportions, at the SAME height. The 80px went to the
	name, the badge's slide right and a wider pill; nothing vertical moved. ]]
local DESIGNS = {
	B = {
		w = 500, panel = 316, edge = 12,
		seat = { x = 52, y = 46, d = 66 },
		from = { 16, 38 }, name = { 34, 80 }, textLeft = 96, textRight = 352,
		badge = { 360, 22, 484, 68 },
		main = { 88, 304 },
		rows = { car = { 6, 32 }, amount = { 29, 99 }, pill = { 102, 132 } },
		pillW = 300,
		footer = { 226, 304 },
	},
}

--[[ How a card is dressed beyond its geometry. `badge` names the badge's ramps by the band keys
	the controller looks up (`BuyerConfig.Bands` / `SellerConfig.Bands`), each a kit ramp from `gather`.
	`pill` is the placeholder pill's look; the controller repaints it per offer. ]]
local BUYER_LOOK = {
	text = PLACEHOLDER,
	badge = { Low = "Low", Fair = "Fair", Good = "Good", Great = "Great" },
	badgeStart = "Low",
	pill = { fill = Color3.fromRGB(255, 218, 218), rim = Color3.fromRGB(236, 104, 104), arrow = Color3.fromRGB(232, 57, 58), ink = Color3.fromRGB(160, 22, 30) },
}

local SELLER_FOLDER = "SellerSigns"

local SELLER_TEXT = {
	From = "FOR SALE BY",
	Name = "HALT_CEO",
	Car = "BRONZE CHARGENT",
	Amount = "$5,280",
	Pill = "12% BELOW WORTH",
	Badge = "GOOD DEAL",
	Time = 'LEAVES IN <font color="#FFD21F">1:12</font>',
}

--[[ The gold chassis. NOT the kit's gold button ramp as it stands: that runs yellow to orange over
	the whole card, and the header only ever shows the top quarter of the ramp, so a card in a kit
	button ramp reads as its first colour (the kit's green came out yellow). This keeps PromptUI's
	own blue ramp's shape (light at the top, the full colour by 0.25, deep at the floor) hue-shifted,
	ending near the kit's gold (`#D36606`, Unlock All). ]]
local GOLD_CHASSIS = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 225, 77)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 176, 0)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 110, 12)),
})

--[[ The seller's card (header), over `SELLER_BASE`. `chassis` swaps the card's blue ramp, and the
	face well's, for the one above. ]]
local SELLER_LOOKS = {
	Gold = { chassis = GOLD_CHASSIS },
}

local SELLER_BASE = {
	text = SELLER_TEXT,
	--- STEAL! is the gold one, the buyer's GREAT DEAL colour, because it is the same news.
	badge = { Steal = "Great", Good = "Good", Fair = "Fair", RipOff = "Low" },
	badgeStart = "Good",
	pill = { fill = Color3.fromRGB(214, 247, 206), rim = Color3.fromRGB(96, 200, 84), arrow = Color3.fromRGB(52, 196, 60), ink = Color3.fromRGB(22, 118, 30) },
}

type Box = { x: number, y: number, w: number, h: number }

local function at(root: Instance, path: { string }): Instance?
	local node: Instance? = root
	for _, step in path do
		node = node and node:FindFirstChild(step)
	end
	return node
end

--- The kit template's container of frames, or nil and why.
local function findContainer(): (Instance?, string?)
	local node = at(ServerStorage, TEMPLATE_PATH)
	if not node then
		return nil, string.format("ServerStorage.%s is missing", table.concat(TEMPLATE_PATH, "."))
	end
	local screen = node:FindFirstChildWhichIsA("ScreenGui")
	local container = screen and screen:FindFirstChild("Container")
	if not container then
		return nil, string.format("%s holds no ScreenGui with a `Container`", node:GetFullName())
	end
	return container, nil
end

local function boxOf(gui: GuiObject, pw: number, ph: number): Box
	local w = gui.Size.X.Scale * pw + gui.Size.X.Offset
	local h = gui.Size.Y.Scale * ph + gui.Size.Y.Offset
	local left = gui.Position.X.Scale * pw + gui.Position.X.Offset - gui.AnchorPoint.X * w
	local top = gui.Position.Y.Scale * ph + gui.Position.Y.Offset - gui.AnchorPoint.Y * h
	return { x = left + w / 2, y = top + h / 2, w = w, h = h }
end

--- A child at a box in its parent's pixels, as scale on a centre anchor (`ui-anchor-convention`).
local function setBox(gui: GuiObject, pw: number, ph: number, box: Box)
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui.Position = UDim2.fromScale(box.x / pw, box.y / ph)
	gui.Size = UDim2.fromScale(box.w / pw, box.h / ph)
end

local function edges(left: number, top: number, right: number, bottom: number): Box
	return { x = (left + right) / 2, y = (top + bottom) / 2, w = right - left, h = bottom - top }
end

--[[ A frame's own rim and corner after its SHORTER side went from `before` to `after` pixels. Both
	are fractions of that side, so dividing by the ratio keeps them at the artist's pixels. ]]
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

--- The checker after its frame went from `oldW x oldH` to `newW x newH` (`kit-panel-dress-cloned-to-a-new-shape`).
local function keepChecker(frame: Instance, oldW: number, oldH: number, newW: number, newH: number)
	local bg = frame:FindFirstChild("BG")
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

--- Non-breaking spaces, because `TextScaled` would sooner wrap a line than shrink it.
local function oneLine(text: string): string
	return (string.gsub(text, " ", "\u{00A0}"))
end

local function uncap(root: Instance)
	for _, item in root:GetDescendants() do
		if item:IsA("UITextSizeConstraint") then
			item:Destroy()
		end
	end
end

--- The kit frame's chassis at `w x h`: the clone with its rims and checker re-expressed.
local function chassis(kitFrame: GuiObject, kitW: number, kitH: number, w: number, h: number): GuiObject
	local frame = kitFrame:Clone() :: GuiObject
	frame.Visible = true
	local aspect = frame:FindFirstChildOfClass("UIAspectRatioConstraint")
	if aspect then
		aspect:Destroy()
	end
	keepRim(frame, math.min(kitW, kitH), math.min(w, h))
	keepChecker(frame, kitW, kitH, w, h)
	return frame
end

local function image(name: string, id: number): ImageLabel
	local item = Instance.new("ImageLabel")
	item.Name = name
	item.BackgroundTransparency = 1
	item.BorderSizePixel = 0
	item.Image = "rbxassetid://" .. id
	item.ScaleType = Enum.ScaleType.Fit
	return item
end

type Kit = {
	frame: GuiObject,
	kitW: number,
	kitH: number,
	mainMin: number,
	body: TextLabel,
	seat: GuiObject,
	sunray: ImageLabel,
	bar: GuiObject,
	button: GuiObject,
	ramps: { [string]: UIGradient },
	money: UIGradient,
}

--- Gather and check every kit part up front, so a missing one stops the build before anything is made.
local function gather(container: Instance): (Kit?, string?)
	local missing = {}
	local function need(key: string): Instance?
		local found = at(container, KIT[key])
		if not found then
			table.insert(missing, table.concat(KIT[key], "."))
		end
		return found
	end
	local frame, seat, sunray, bar = need("Frame"), need("Seat"), need("Sunray"), need("Bar")
	local accept, decline, gold, moneyLabel = need("Accept"), need("Decline"), need("Gold"), need("Money")
	if #missing > 0 then
		return nil, "missing " .. table.concat(missing, ", ")
	end
	local main = frame:FindFirstChild("Main")
	local body = main and main:FindFirstChild("Title")
	local aspect = frame:FindFirstChildOfClass("UIAspectRatioConstraint")
	local money = moneyLabel:FindFirstChildOfClass("UIGradient")
	if not (main and main:IsA("GuiObject") and body and body:IsA("TextLabel") and aspect and money) then
		return nil, "PromptUI needs Main, Main.Title and an aspect constraint, and the cash counter its gradient"
	end
	local kitW = (frame :: GuiObject).Size.X.Scale * REF_W
	local kitH = kitW / aspect.AspectRatio
	local mainBox = boxOf(main, kitW, kitH)

	--- The four kit button ramps a band can wear. Fair borrows the panel's own blue.
	local function rampOf(source: Instance): UIGradient?
		return source:FindFirstChildOfClass("UIGradient")
	end
	local ramps = {
		Low = rampOf(decline :: Instance),
		Fair = rampOf(frame :: Instance),
		Good = rampOf(accept :: Instance),
		Great = rampOf(gold :: Instance),
	}
	for key, ramp in ramps do
		if not ramp then
			return nil, "no button ramp for " .. key
		end
	end

	return {
		frame = frame :: GuiObject,
		kitW = kitW,
		kitH = kitH,
		mainMin = math.min(mainBox.w, mainBox.h),
		body = body,
		seat = seat :: GuiObject,
		sunray = sunray :: ImageLabel,
		bar = bar :: GuiObject,
		button = accept :: GuiObject,
		ramps = ramps :: any,
		money = money,
	}, nil
end

--- A line of the kit's type at a box. `ink` recolours it; `bare` drops the outline.
local function label(kit: Kit, parent: GuiObject, pw: number, ph: number, name: string, text: string, box: Box,
	ink: Color3?, bare: boolean?): TextLabel
	local item = kit.body:Clone()
	item.Name = name
	item.TextXAlignment = Enum.TextXAlignment.Center
	item.TextYAlignment = Enum.TextYAlignment.Center
	--- Never `TextWrapped = false`: it switches `TextScaled` off with it.
	item.TextScaled = true
	item.Text = oneLine(text)
	if ink then
		item.TextColor3 = ink
	end
	if bare then
		for _, child in item:GetChildren() do
			if child:IsA("UIStroke") then
				child:Destroy()
			end
		end
	end
	setBox(item, pw, ph, box)
	item.ZIndex = 3
	item.Parent = parent
	return item
end

--- The kit progress bar at a box, its fill pinned to the left and at 70% for the Explorer.
local function bar(kit: Kit, parent: GuiObject, pw: number, ph: number, box: Box): GuiObject
	local track = kit.bar:Clone()
	track.Name = "Track"
	track.ZIndex = 3
	setBox(track, pw, ph, box)
	local fill = track:FindFirstChild("Progress") :: GuiObject
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.fromScale(0, 0.5)
	fill.Size = UDim2.fromScale(0.7, 1)
	track.Parent = parent
	return track
end

--[[ One design, dressed as `look` says (`BUYER_LOOK`, or `SELLER_BASE` with one of `SELLER_LOOKS`
	over it). Returns the template root: a transparent frame filling the billboard, holding
	`Panel`. ]]
local function build(kit: Kit, key: string, spec, look): Frame
	local w, panelH = spec.w, spec.panel
	local words = look.text

	local root = Instance.new("Frame")
	root.Name = key
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root:SetAttribute("Aspect", w / panelH)

	-- === The card =======================================================
	local panel = chassis(kit.frame, kit.kitW, kit.kitH, w, panelH)
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(1, 1)
	panel.Parent = root
	local kitHeader = panel:FindFirstChild("Header")
	if kitHeader then
		kitHeader:Destroy()
	end
	--- Another ramp on the chassis: it is the header's colour and the card's edge.
	if look.chassis then
		local ramp = panel:FindFirstChildOfClass("UIGradient")
		if ramp then
			ramp.Color = look.chassis
		end
	end

	-- === The header =====================================================
	local seatSpec = spec.seat
	local seat = kit.seat:Clone()
	seat.Name = "Seat"
	seat.ZIndex = 3
	setBox(seat, w, panelH, { x = seatSpec.x, y = seatSpec.y, w = seatSpec.d, h = seatSpec.d })
	local face = seat:FindFirstChild("Icon") :: ImageLabel
	face.Name = "Face"
	face.Image = "rbxassetid://" .. ART.Person
	face.ScaleType = Enum.ScaleType.Crop
	--- The well wears the chassis ramp, so it follows a recoloured header.
	local well = seat:FindFirstChildOfClass("UIGradient")
	if look.chassis and well then
		well.Color = look.chassis
	end
	seat.Parent = panel

	local from = label(kit, panel, w, panelH, "From", words.From, edges(spec.textLeft, spec.from[1], spec.textRight, spec.from[2]))
	from.TextXAlignment = Enum.TextXAlignment.Left
	--- Never named `Name`: `panel.Name` is the property, and a reader reaching for the label gets a string.
	--- `Buyer` on the seller's card too, so `buildDesign` reads both alike.
	local name = label(kit, panel, w, panelH, "Buyer", words.Name, edges(spec.textLeft, spec.name[1], spec.textRight, spec.name[2]))
	name.TextXAlignment = Enum.TextXAlignment.Left

	--- The rating badge: the kit button face, its live ramp swapped per band from `Ramps` at runtime.
	local b = spec.badge
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.BackgroundColor3 = Color3.new(1, 1, 1)
	badge.BorderSizePixel = 0
	badge.ZIndex = 3
	for _, child in kit.button:GetChildren() do
		if child.Name ~= "Title" and not child:IsA("UITextSizeConstraint") then
			child:Clone().Parent = badge
		end
	end
	local ramps = Instance.new("Folder")
	ramps.Name = "Ramps"
	for band, kitKey in look.badge do
		local copy = kit.ramps[kitKey]:Clone()
		copy.Name = band
		copy.Enabled = false
		copy.Parent = ramps
	end
	ramps.Parent = badge
	local live = badge:FindFirstChildOfClass("UIGradient")
	if live then
		live.Color = kit.ramps[look.badgeStart].Color
	end
	local badgeBox = edges(b[1], b[2], b[3], b[4])
	setBox(badge, w, panelH, badgeBox)
	badge.Rotation = 4
	label(kit, badge, badgeBox.w, badgeBox.h, "Title", words.Badge,
		edges(badgeBox.w * 0.07, badgeBox.h * 0.18, badgeBox.w * 0.93, badgeBox.h * 0.82))
	badge.Parent = panel

	-- === The white body =================================================
	local main = panel:FindFirstChild("Main") :: GuiObject
	for _, child in main:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local edge = spec.edge
	local mainBox = edges(edge, spec.main[1], w - edge, spec.main[2])
	setBox(main, w, panelH, mainBox)
	keepRim(main, kit.mainMin, math.min(mainBox.w, mainBox.h))
	local mw, mh = mainBox.w, mainBox.h

	--- The floor, cloned off the body BEFORE the body is filled, so it carries the same rim and corner.
	local footer = main:Clone()
	local footerBox = edges(edge, spec.footer[1], w - edge, spec.footer[2])
	setBox(footer, w, panelH, footerBox)
	keepRim(footer, math.min(mw, mh), math.min(footerBox.w, footerBox.h))

	--- The rays, in a CanvasGroup so the body's rounded corners clip them.
	local rays = Instance.new("CanvasGroup")
	rays.Name = "Rays"
	rays.BackgroundTransparency = 1
	rays.BorderSizePixel = 0
	rays.ZIndex = 1
	setBox(rays, mw, mh, edges(0, 0, mw, mh))
	local corner = main:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Clone().Parent = rays
	end
	local sunray = kit.sunray:Clone()
	sunray.Name = "Sunray"
	sunray.ImageColor3 = RAY_TINT
	sunray.ImageTransparency = RAY_TRANSPARENCY
	local amountY = (spec.rows.amount[1] + spec.rows.amount[2]) / 2
	local side = 1.3 * math.max(mw, mh)
	setBox(sunray, mw, mh, { x = mw / 2, y = amountY, w = side, h = side })
	sunray.Parent = rays
	rays.Parent = main

	local rows = spec.rows
	label(kit, main, mw, mh, "Car", words.Car, edges(16, rows.car[1], mw - 16, rows.car[2]), INK, true)
	local amount = label(kit, main, mw, mh, "Amount", words.Amount, edges(16, rows.amount[1], mw - 16, rows.amount[2]))
	local tint = kit.money:Clone()
	tint.Name = "Tint"
	tint.Enabled = true
	tint.Parent = amount

	-- The value pill: a soft fill and rim in the direction's colour, the arrow, the words.
	local pillBox = edges((mw - spec.pillW) / 2, rows.pill[1], (mw + spec.pillW) / 2, rows.pill[2])
	local pillLook = look.pill
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.BackgroundColor3 = pillLook.fill
	pill.BorderSizePixel = 0
	pill.ZIndex = 3
	setBox(pill, mw, mh, pillBox)
	local pillCorner = Instance.new("UICorner")
	pillCorner.CornerRadius = UDim.new(0.5, 0)
	pillCorner.Parent = pill
	local rim = Instance.new("UIStroke")
	rim.Name = "Rim"
	rim.Color = pillLook.rim
	rim.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	rim.Thickness = 0.09
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = pill
	local ph = pillBox.h
	local arrow = image("Arrow", ART.ArrowTint)
	arrow.ImageColor3 = pillLook.arrow
	arrow.ZIndex = 4
	setBox(arrow, pillBox.w, ph, { x = ph * 0.62, y = ph / 2, w = ph * 0.86, h = ph * 0.86 })
	arrow.Parent = pill
	local pillWords = label(kit, pill, pillBox.w, ph, "Text", words.Pill, edges(ph * 1.15, ph * 0.14, pillBox.w - ph * 0.45, ph * 0.86),
		pillLook.ink, true)
	pillWords.ZIndex = 4
	pill.Parent = main

	-- === The clock ======================================================
	--- One line, the clock then the words, over a bar the width of the floor.
	local fw, fh = footerBox.w, footerBox.h
	footer.Name = "Footer"
	footer.ZIndex = main.ZIndex + 1
	footer.BackgroundColor3 = Color3.new(1, 1, 1)
	local ramp = Instance.new("UIGradient")
	ramp.Rotation = 90
	ramp.Color = FOOTER_RAMP
	ramp.Parent = footer
	local line = fh * 0.42
	local top = fh * 0.1
	--- The clock and "EXPIRES IN 4:02" centred as one group. The words run about 6.1 line heights
	--- wide in FredokaOne (measured on the shot), so the group is about 7.6 with the clock and gap.
	local left = (fw - line * 7.6) / 2
	local clock = image("Clock", ART.Clock)
	clock.ZIndex = 3
	setBox(clock, fw, fh, { x = left + line * 0.625, y = top + line / 2, w = line * 1.25, h = line * 1.25 })
	clock.Parent = footer
	local time = label(kit, footer, fw, fh, "Time", "", edges(left + line * 1.45, top, fw * 0.95, top + line))
	time.TextXAlignment = Enum.TextXAlignment.Left
	time.RichText = true
	time.Text = words.Time
	bar(kit, footer, fw, fh, edges(fw * 0.05, fh * 0.64, fw * 0.95, fh * 0.82))
	footer.Parent = panel

	uncap(root)
	return root
end

return {
	Description = "Build StarterGui.MainUIV2.Screens.BuyerSigns and Screens.SellerSigns: the buyer offer sign redesigned off Dylan's reference (face, name and rating badge in the header, white body with rays and a value pill, the clock as a navy footer), design B, chosen 2026-10-15, and the kerb seller's Gold version of it, chosen the same day. Kit parts plus a Gvesster clock. Leaves Screens.BuyerSign (the old kit sign) alone. Rebuilds both folders every run.",
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
		local container, why = findContainer()
		if not container then
			out:error(string.format("The kit is not where it should be: %s.", tostring(why)))
			return
		end
		local kit, missing = gather(container)
		if not kit then
			out:error(string.format("The kit is not the shape this expects: %s.", tostring(missing)))
			return
		end

		--- One folder of templates, replacing whatever was there; `lookFor(key)` dresses each.
		local function shelve(folderName: string, keys: { string }, specFor: (string) -> any, lookFor: (string) -> any): Folder
			local folder = Instance.new("Folder")
			folder.Name = folderName
			table.sort(keys)
			for _, key in keys do
				build(kit, key, specFor(key), lookFor(key)).Parent = folder
			end
			local existing = shelf:FindFirstChild(folderName)
			if existing then
				existing:Destroy()
			end
			folder.Parent = shelf
			out:print(string.format("Built %s.%s.%s with %s.", SCREEN_NAME, SHELF_NAME, folderName, table.concat(keys, ", ")))
			return folder
		end

		local buyerKeys = {}
		for key in DESIGNS do
			table.insert(buyerKeys, key)
		end
		local buyers = shelve(FOLDER_NAME, buyerKeys, function(key)
			return DESIGNS[key]
		end, function()
			return BUYER_LOOK
		end)

		--- Every seller card is B's geometry; the look is the seller's base with the variation over it.
		local sellerKeys = {}
		for key in SELLER_LOOKS do
			table.insert(sellerKeys, key)
		end
		local sellers = shelve(SELLER_FOLDER, sellerKeys, function()
			return DESIGNS.B
		end, function(key)
			local look = table.clone(SELLER_BASE)
			for field, value in SELLER_LOOKS[key] do
				look[field] = value
			end
			return look
		end)
		pcall(function()
			props:SetSelection({ buyers, sellers })
		end)
	end,
} :: Types.ScriptModule
