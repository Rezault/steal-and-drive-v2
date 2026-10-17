--[[
	WorkshopCards  (client)
	-----------------------
	The workshop's CARD layout: what `WorkshopController` draws with when `NewUIConfig.WorkshopCards` is
	on. The art is `BuildWorkshopCards`' template (`MainUIV2.Screens.WorkshopCards`); this fills it in
	from the server's state. Added 2026-09-30, off Aleafo's reference.

	=== WHAT IS SHARED WITH THE ROWS, AND WHAT IS NOT ============================================

	The controller still owns the screen: the ScreenGui, the dim, the pop, open and close, the gamepad,
	and every press (`hooks.ask`). The screen table it keeps is the one this fills, so its `_raiseKit`,
	`_lowerKit` and `_keepSelection` work on either layout unchanged. That is why this writes
	`screen.rowOrder` (each with a `buy`), `screen.swatches` (each with a `button`) and `screen.carId`.

	What is new here is PAINT. On the rows a swatch press paints the car. Here a swatch PICKS a
	colour: the car in the portrait turns in it at once, and the PAINT CAR button under the price
	buys it. The button is grey until a colour other than the car's own is picked. Nothing is bought by
	looking, and a picked colour is dropped when the screen shuts or the car changes.

	The rest follows the controller's rules: every number is the server's, nothing is drawn
	optimistically, the cards are built once and rewritten in place (a kit button carries its hover and
	the pad's highlight), and only the swatches are rebuilt, only when the palette changes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CustomizeConfig = require(ReplicatedStorage.shared.Configs.CustomizeConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)
--- A mutation's name, for the car's title.
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)

local WorkshopCards = {}
WorkshopCards.__index = WorkshopCards

--- The colours the part tiles take in turn, by their place in the row colours the builder stamps on
--- `List`: 1 red, 2 lime, 3 blue, 4 purple, 5 orange. REPAIR (red) and PAINT (blue) are set by the
--- builder; the parts go lime, purple, orange, as the reference has them.
local PART_COLOURS = { 2, 4, 5 }

export type Hooks = {
	ask: (action: string, arg: any?) -> (),
}

local function oneLine(value: string): string
	return (string.gsub(value, " ", "\u{00A0}"))
end

local function url(id: number?): string
	return if id then UIAssets.url(id) else ""
end

--- A pixel box in a parent `pw x ph`, written as scale, anchored at its centre.
local function place(gui: GuiObject, pw: number, ph: number, left: number, top: number, w: number, h: number)
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui.Position = UDim2.fromScale((left + w / 2) / pw, (top + h / 2) / ph)
	gui.Size = UDim2.fromScale(w / pw, h / ph)
end

--- The palette, each colour once, in order. `poolFor` is a roll table and lists `Stock` more than once.
local function uniquePaints(paints: { any }): { number }
	local seen, out = {}, {}
	for _, raw in paints do
		local index = tonumber(raw)
		if index and not seen[index] then
			seen[index] = true
			table.insert(out, index)
		end
	end
	return out
end

--- A card's pieces, found once.
local function parts(frame: GuiObject)
	local btns = frame:FindFirstChild("Btns")
	local buy = btns and btns:FindFirstChild("BuyBtn")
	local grey = btns and btns:FindFirstChild("GreyBtn")
	local tile = frame:FindFirstChild("Tile")
	return {
		frame = frame,
		tile = tile,
		glyph = tile and tile:FindFirstChild("Glyph"),
		title = frame:FindFirstChild("Title"),
		sub = frame:FindFirstChild("Sub"),
		level = frame:FindFirstChild("Level"),
		dots = frame:FindFirstChild("Dots"),
		gain = frame:FindFirstChild("Gain"),
		bar = frame:FindFirstChild("Bar"),
		percent = frame:FindFirstChild("Percent"),
		btns = btns,
		buy = buy,
		buyVerb = buy and buy:FindFirstChild("Title"),
		buyPrice = buy and buy:FindFirstChild("Price"),
		grey = grey,
		greyCaption = grey and grey:FindFirstChild("Title"),
		greyPrice = grey and grey:FindFirstChild("Price"),
		press = nil :: (() -> ())?,
		height = frame:GetAttribute("Height") or 92,
	}
end

--[[ Take the template's pieces and make the two cards every car has. Returns nil (having said why)
	when the template is not the builder's shape; the controller then falls back to the rows. ]]
function WorkshopCards.new(screen, hooks: Hooks)
	local panel = screen.panel :: GuiObject
	local list = screen.list :: ScrollingFrame
	local repairT = list:FindFirstChild("RepairCard")
	local paintT = list:FindFirstChild("PaintCard")
	local partT = list:FindFirstChild("PartCard")
	local swatchT = list:FindFirstChild("SwatchTemplate")
	if not (repairT and paintT and partT and swatchT and swatchT:IsA("GuiButton")) then
		warn("[WorkshopCards] MainUIV2.Screens.WorkshopCards is missing a card template; re-run BuildWorkshopCards.")
		return nil
	end
	--- Out of the list, hidden, as the source of every card and swatch.
	for _, template in { repairT, paintT, partT, swatchT } do
		template.Parent = panel
		template.Visible = false
	end

	local art = UIAssets.WorkshopCards
	local header = panel:FindFirstChild("Header")
	local headerGlyph = header and header:FindFirstChild("Glyph")
	if headerGlyph and headerGlyph:IsA("ImageLabel") then
		headerGlyph.Image = url(art.Glyphs.Wrench)
	end
	local changeGlyph = screen.change:FindFirstChild("Glyph")
	if changeGlyph and changeGlyph:IsA("ImageLabel") then
		changeGlyph.Image = url(art.Glyphs.Car)
	end
	local platform = screen.view.Parent and screen.view.Parent:FindFirstChild("Platform")
	if platform and platform:IsA("ImageLabel") then
		platform.Image = url(art.Platform)
	end

	local self = setmetatable({
		screen = screen,
		hooks = hooks,
		list = list,
		partTemplate = partT,
		swatchTemplate = swatchT,
		cards = {} :: { [string]: any },
		partKeys = "",
		paletteKey = "",
		swatches = screen.swatches,
		block = nil :: Frame?,
		--- The colour picked on the swatches and not bought yet, or nil for the car's own.
		picked = nil :: number?,
		--- Which car the pick belongs to, so a new car starts with none.
		pickedFor = nil :: string?,
		state = nil :: any,
	}, WorkshopCards)

	local words = CustomizeConfig.Screen
	local repair = self:_card("repair", repairT, nil)
	if repair.buyVerb then
		repair.buyVerb.Text = oneLine(words.CardRepair)
	end
	if repair.glyph and repair.glyph:IsA("ImageLabel") then
		repair.glyph.Image = url(art.Glyphs.Repair)
	end
	local paint = self:_card("paint", paintT, nil)
	if paint.glyph and paint.glyph:IsA("ImageLabel") then
		paint.glyph.Image = url(art.Glyphs.Paint)
	end
	if paint.buyVerb then
		paint.buyVerb.Text = oneLine(words.CardPaint)
	end
	--- The grey face at rest says what the blue one will: the verb over the price. It only has the
	--- one caption, so the blue face's second line is copied onto it.
	if paint.grey and paint.greyCaption and paint.buyPrice and paint.buyVerb then
		local caption = paint.greyCaption :: TextLabel
		caption.Position = (paint.buyVerb :: TextLabel).Position
		caption.Size = (paint.buyVerb :: TextLabel).Size
		caption.Text = oneLine(words.CardPaint)
		local price = (paint.buyPrice :: TextLabel):Clone()
		price.Parent = paint.grey
		paint.greyPrice = price
	end
	return self
end

--- One card off a template, wired once to whatever press the latest state gave it.
function WorkshopCards._card(self, key: string, template: Instance, word: string?)
	local frame = template:Clone() :: GuiObject
	frame.Name = key
	frame.Visible = true
	local card = parts(frame)
	if word and card.title then
		card.title.Text = oneLine(word)
	end
	if card.buy then
		card.buy.Activated:Connect(function()
			if card.press then
				card.press()
			end
		end)
	end
	frame.Parent = self.list
	self.cards[key] = card
	return card
end

--- Show one face of a card's button pair, or neither. `verb`/`price` go on the blue or green face.
local function setButton(card, press: (() -> ())?, verb: string?, price: string?, grey: string?, greyPrice: string?)
	local live = press ~= nil
	if card.btns then
		card.btns.Visible = live or grey ~= nil
	end
	if card.buy then
		card.buy.Visible = live
	end
	if live then
		if verb and card.buyVerb then
			card.buyVerb.Text = oneLine(verb)
		end
		if card.buyPrice then
			card.buyPrice.Text = oneLine(price or "")
		end
	end
	if card.grey then
		card.grey.Visible = not live and grey ~= nil
		if grey and card.greyCaption then
			card.greyCaption.Text = oneLine(grey)
		end
		if card.greyPrice then
			card.greyPrice.Text = oneLine(greyPrice or "")
			card.greyPrice.Visible = greyPrice ~= nil
		end
	end
	card.press = press
end

-- === Drawing =================================================================

function WorkshopCards.draw(self, state)
	self.state = state
	local screen = self.screen
	local words = CustomizeConfig.Screen
	local cash = GarageConfig.formatCash
	local current = tonumber(state.paint)
	local carKey = tostring(state.carId)
	--- The car's mutation, off its key (2026-10-14: "can't see the ghost effect in the customisation viewport").
	local _, _, mutation = GarageConfig.parseCarKey(state.carId)
	if self.pickedFor ~= carKey then
		--- A new car, or this one re-keyed by a repaint that just landed: whatever was picked is spent.
		self.pickedFor = carKey
		self.picked = nil
	end
	if self.picked == current then
		self.picked = nil
	end
	local shown = self.picked or current
	screen.paint = current

	--- The car, in the colour picked if there is one. Keyed on both, so a pick turns it at once.
	local viewKey = carKey .. ":" .. tostring(shown)
	if screen.carId ~= viewKey then
		screen.carId = viewKey
		if screen.spin then
			screen.spin.stop()
			screen.spin = nil
		end
		if CarViewport.set(screen.view, state.body, { paint = shown, aspect = screen.aspect, mutation = mutation }) then
			screen.view.Visible = true
			screen.spin = CarViewport.spin(screen.view, { aspect = screen.aspect })
		end
	end

	local name = string.upper(GarageConfig.carName(state.body, state.paint))
	screen.carName.Text = oneLine(if mutation then string.upper(WeatherConfig.nameOf(mutation)) .. " " .. name else name)
	screen.worth.Text = oneLine(string.format(words.Value, cash(tonumber(state.value) or 0)))
	local condition = math.clamp(tonumber(state.condition) or 1, 0, 1)
	screen.condition.Text = oneLine(string.format(words.Condition, math.round(condition * 100)))
	screen.fill.Size = UDim2.fromScale(condition, screen.fill.Size.Y.Scale)
	screen.fill.Visible = condition > 0

	self:_drawRepair(state, condition)
	self:_drawPaint(state, current)
	self:_drawParts(state)
	self:_layout()
end

function WorkshopCards._drawRepair(self, state, condition: number)
	local card = self.cards.repair
	local words = CustomizeConfig.Screen
	local cash = GarageConfig.formatCash
	local frame = card.frame
	local w = self.list:GetAttribute("CardWidth") or 694
	local h = card.height
	local repair = state.repair
	local damaged = type(repair) == "table"
	if card.sub then
		card.sub.Text = oneLine(if damaged then string.format(words.Gain, cash(tonumber(repair.gain) or 0)) else words.RepairDone)
	end
	--- The bar runs to the right edge when there is nothing to buy, and stops short of the button when
	--- there is. Its percentage follows its end.
	local left = frame:GetAttribute("BarLeft") or 300
	local right = if damaged then frame:GetAttribute("BarRightShort") or 440 else frame:GetAttribute("BarRightFull") or 614
	local pctW = frame:GetAttribute("PercentWidth") or 62
	local pctGap = frame:GetAttribute("PercentGap") or 8
	if card.bar then
		local barH = card.bar.Size.Y.Scale * h
		place(card.bar, w, h, left, (h - barH) / 2, right - left, barH)
		local fill = card.bar:FindFirstChild("Progress")
		if fill and fill:IsA("GuiObject") then
			fill.Size = UDim2.fromScale(condition, fill.Size.Y.Scale)
			fill.Visible = condition > 0
		end
	end
	if card.percent then
		local pctH = card.percent.Size.Y.Scale * h
		place(card.percent, w, h, right + pctGap, (h - pctH) / 2, pctW, pctH)
		card.percent.Text = oneLine(string.format(words.Percent, math.round(condition * 100)))
	end
	if damaged then
		setButton(card, function()
			self.hooks.ask("repair")
		end, words.CardRepair, cash(tonumber(repair.cost) or 0))
	else
		setButton(card, nil)
	end
end

function WorkshopCards._drawPaint(self, state, current: number?)
	local card = self.cards.paint
	local words = CustomizeConfig.Screen
	local cash = GarageConfig.formatCash
	local paints = uniquePaints(if type(state.paints) == "table" then state.paints else {})
	if card.sub then
		card.sub.Text = oneLine(if #paints == 0 then words.PaintKept else words.CardPaintSub)
	end
	self:_drawSwatches(paints, current)
	local each = string.format(words.PaintEach, cash(tonumber(state.paintCost) or 0))
	if #paints == 0 then
		setButton(card, nil)
	elseif self.picked then
		local picked = self.picked
		setButton(card, function()
			self.hooks.ask("paint", picked)
		end, words.CardPaint, each)
	else
		setButton(card, nil, nil, nil, words.CardPaint, each)
	end
	--- The card is as tall as its swatches: the head, the lines, the foot.
	local frame = card.frame
	local head = frame:GetAttribute("Head") or 64
	local foot = frame:GetAttribute("Foot") or 13
	local side = frame:GetAttribute("Swatch") or 42
	local gap = frame:GetAttribute("SwatchGap") or 7
	local columns = frame:GetAttribute("SwatchColumns") or 8
	local lines = math.ceil(#paints / columns)
	local blockH = if lines > 0 then lines * side + (lines - 1) * gap else 0
	card.height = if lines > 0 then head + blockH + foot else (self.cards.repair and self.cards.repair.height or 92)
	card.blockH = blockH
end

--- Rebuild the swatches when the palette changes; otherwise only move the check and the ring.
function WorkshopCards._drawSwatches(self, paints: { number }, current: number?)
	local key = table.concat(paints, ",")
	local swatches = self.swatches
	if key ~= self.paletteKey then
		self.paletteKey = key
		if self.block then
			self.block:Destroy()
			self.block = nil
		end
		table.clear(swatches)
		if #paints > 0 then
			local block = Instance.new("Frame")
			block.Name = "Swatches"
			block.BackgroundTransparency = 1
			block.BorderSizePixel = 0
			for order, index in paints do
				local swatch = self.swatchTemplate:Clone() :: GuiButton
				swatch.Name = "Swatch" .. index
				swatch.LayoutOrder = order
				swatch.Visible = true
				local colour = PaintConfig.colorOf(index)
				local caption = swatch:FindFirstChild("Caption")
				if colour then
					swatch.BackgroundColor3 = colour
				else
					--- `Stock`: the artist's livery, which has no one colour. White under its name.
					swatch.BackgroundColor3 = Color3.new(1, 1, 1)
					if caption and caption:IsA("TextLabel") then
						caption.Text = oneLine(CustomizeConfig.Screen.Stock)
						caption.Visible = true
					end
				end
				local entry = { button = swatch, check = swatch:FindFirstChild("Check"), ring = swatch:FindFirstChild("Ring"), paint = index }
				swatch.Activated:Connect(function()
					self:_pick(entry.paint)
				end)
				swatch.Parent = block
				table.insert(swatches, entry)
			end
			block.Parent = self.cards.paint.frame
			self.block = block
		end
	end
	local shown = self.picked or current
	for _, entry in swatches do
		if entry.check then
			entry.check.Visible = entry.paint == current
		end
		if entry.ring then
			entry.ring.Visible = entry.paint == shown
			--- The ring's glow spills into the gap; lifted, it lies over BOTH neighbours, not under the next.
			entry.button.ZIndex = self.swatchTemplate.ZIndex + (if entry.paint == shown then 1 else 0)
		end
	end
end

--- A swatch press: look at the colour on the car. The car's own colour puts the pick back.
function WorkshopCards._pick(self, paint: number)
	local state = self.state
	if not state then
		return
	end
	self.picked = if paint == tonumber(state.paint) then nil else paint
	self:draw(state)
end

function WorkshopCards._drawParts(self, state)
	local words = CustomizeConfig.Screen
	local cash = GarageConfig.formatCash
	local list = self.list
	local parts = if type(state.parts) == "table" then state.parts else {}
	local keys = {}
	for _, part in parts do
		table.insert(keys, tostring(part.key))
	end
	local partKeys = table.concat(keys, ",")
	if partKeys ~= self.partKeys then
		self.partKeys = partKeys
		for key, card in self.cards do
			if key ~= "repair" and key ~= "paint" then
				card.frame:Destroy()
				self.cards[key] = nil
			end
		end
		for index, part in parts do
			local card = self:_card("part:" .. tostring(part.key), self.partTemplate, tostring(part.label))
			local count = list:GetAttribute("ColorCount")
			local slot = PART_COLOURS[(index - 1) % #PART_COLOURS + 1]
			local colour = list:GetAttribute("Color" .. (if type(count) == "number" and count > 0 then (slot - 1) % count + 1 else slot))
			if typeof(colour) == "ColorSequence" then
				card.colour = colour
				local face = card.tile and card.tile:FindFirstChildOfClass("UIGradient")
				if face then
					face.Color = colour
				end
			end
			if card.glyph and card.glyph:IsA("ImageLabel") then
				card.glyph.Image = url(UIAssets.WorkshopCards.Glyphs[tostring(part.key)])
			end
			if card.buyVerb then
				card.buyVerb.Text = oneLine(words.CardUpgrade)
			end
		end
	end

	for _, part in parts do
		local card = self.cards["part:" .. tostring(part.key)]
		if card then
			local level = tonumber(part.level) or 0
			local max = tonumber(part.max) or CustomizeConfig.PartLevels
			if card.level then
				card.level.Text = oneLine(string.format(words.CardLevel, level, max))
			end
			if card.dots then
				local off = card.dots:GetAttribute("OffColor")
				for _, dot in card.dots:GetChildren() do
					local order = tonumber(string.match(dot.Name, "^Dot(%d+)$"))
					if order and dot:IsA("GuiObject") then
						dot.Visible = order <= max
						local face = dot:FindFirstChildOfClass("UIGradient")
						local ramp = if order <= level then card.colour else off
						if face and typeof(ramp) == "ColorSequence" then
							face.Color = ramp
						end
					end
				end
			end
			local cost = tonumber(part.cost)
			if card.gain then
				card.gain.Visible = cost ~= nil
				card.gain.Text = oneLine(string.format(words.Gain, cash(tonumber(part.gain) or 0)))
			end
			if cost then
				setButton(card, function()
					self.hooks.ask("part", part.key)
				end, words.CardUpgrade, cash(cost))
			else
				setButton(card, nil, nil, nil, words.PartMax)
			end
		end
	end
end

--[[ Stack the cards down the list in the builder's pixels, as scale of the CANVAS, whose scale of 1 is
	`CanvasBasis` tall (V2's measured trap, carried on the list; see `WorkshopController._layoutKit`). ]]
function WorkshopCards._layout(self)
	local list = self.list
	local screen = self.screen
	local width = list:GetAttribute("ReferenceWidth") or 710
	local height = list:GetAttribute("ReferenceHeight") or 604
	local side = list:GetAttribute("RowSide") or 8
	local pad = list:GetAttribute("ListPad") or 6
	local gap = list:GetAttribute("CardGap") or 9
	local cardW = list:GetAttribute("CardWidth") or (width - 2 * side)

	local order = { self.cards.repair, self.cards.paint }
	local rowOrder = { self.cards.repair, self.cards.paint }
	for _, key in string.split(self.partKeys, ",") do
		local card = self.cards["part:" .. key]
		if card then
			table.insert(order, card)
			table.insert(rowOrder, card)
		end
	end
	screen.rowOrder = rowOrder

	local total = 2 * pad
	for index, card in order do
		total += card.height + (if index > 1 then gap else 0)
	end
	local canvas = math.max(total, height)
	local basis = list:GetAttribute("CanvasBasis")
	list.CanvasSize = UDim2.fromScale(0, canvas / (if type(basis) == "number" and basis > 0 then basis else height))

	local y = pad
	for _, card in order do
		card.frame.AnchorPoint = Vector2.new(0, 0)
		card.frame.Position = UDim2.fromScale(side / width, y / canvas)
		card.frame.Size = UDim2.fromScale(cardW / width, card.height / canvas)
		y += card.height + gap
	end
	self:_placePaint(cardW)
end

--[[ PAINT's pieces for the card's height today. Everything is placed from the TOP in pixels, because
	the card grows and shrinks with the palette and a piece written as a scale of the builder's height
	would slide down it. ]]
function WorkshopCards._placePaint(self, w: number)
	local card = self.cards.paint
	local frame = card.frame
	local h = card.height
	local head = frame:GetAttribute("Head") or 64
	local tileLeft = frame:GetAttribute("TileLeft") or 10
	local tileSize = frame:GetAttribute("TileSize") or 72
	local textLeft = frame:GetAttribute("SwatchLeft") or 96
	local lines = card.blockH or 0
	if card.tile then
		place(card.tile, w, h, tileLeft, tileLeft, tileSize, tileSize)
	end
	if card.title then
		local top, th = frame:GetAttribute("TitleTop") or 12, frame:GetAttribute("TitleHeight") or 32
		place(card.title, w, h, textLeft, top, card.title.Size.X.Scale * w, th)
	end
	if card.sub then
		local top, sh = frame:GetAttribute("SubTop") or 34, frame:GetAttribute("SubHeight") or 20
		place(card.sub, w, h, textLeft, top, card.sub.Size.X.Scale * w, sh)
	end
	local bw = frame:GetAttribute("ButtonWidth") or 168
	local bh = frame:GetAttribute("ButtonHeight") or 72
	local br = frame:GetAttribute("ButtonRight") or 10
	if card.btns then
		local middle = if lines > 0 then head + lines / 2 else h / 2
		place(card.btns, w, h, w - br - bw, middle - bh / 2, bw, bh)
	end
	local block = self.block
	if block then
		local side = frame:GetAttribute("Swatch") or 42
		local gap = frame:GetAttribute("SwatchGap") or 7
		local columns = frame:GetAttribute("SwatchColumns") or 8
		local used = math.min(#self.swatches, columns)
		local blockW = used * side + (used - 1) * gap
		place(block, w, h, textLeft, head, blockW, lines)
		for index, entry in self.swatches do
			local column = (index - 1) % columns
			local line = (index - 1) // columns
			entry.button.AnchorPoint = Vector2.new(0, 0)
			entry.button.Position = UDim2.fromScale(column * (side + gap) / blockW, line * (side + gap) / lines)
			entry.button.Size = UDim2.fromScale(side / blockW, side / lines)
		end
	end
end

--- The screen shut: a picked colour does not outlive it.
function WorkshopCards.closed(self)
	self.picked = nil
	self.pickedFor = nil
end

return WorkshopCards
