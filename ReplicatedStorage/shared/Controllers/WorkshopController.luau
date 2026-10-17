--[[
	WorkshopController  (client)
	----------------------------
	The customization bay's screen: the car turning in a viewport, what it is worth and its
	condition, and three sections — REPAIR, PAINT, PERFORMANCE PARTS — each option showing its price
	and what it adds to the car's value before it is pressed. `WorkshopService` works out every number
	and this draws them; `CustomizeConfig` has the design. Added 2026-09-28.

	=== IT IS A PLACEHOLDER, AND IT KNOWS NOTHING ==============================================

	Built in code in the offer screen's style (`BuyerController`): a navy panel, the kit's panel art,
	scale-based so it holds on a phone. No art pass has been done. More to the point, it PRICES
	NOTHING: every dollar on it is the server's (`WorkshopService._state`), sent finished, so the
	number on a button is the number charged and this file never has to agree with a formula. A
	press sends the action and waits for the server's new state; nothing is drawn optimistically,
	because the one thing worse than a slow button is a button that showed a car repainted and then
	quietly wasn't.

	=== WITH THE NEW UI, THE SCREEN IS THE KIT'S (2026-09-30) ==================================

	With `UIRoot.isNewUI()` none of the code-built panel below is made. `BuildWorkshopV2` authors the
	screen out of the Cartoony Kit's `UpgradesUI` onto the hidden shelf `MainUIV2.Screens.Workshop`,
	and `_buildKit` clones it into this file's own `Workshop` ScreenGui at the same `DisplayOrder`.
	The car turns on the panel's blue at the left over its worth, its condition bar and CHANGE CAR;
	the white body at the right holds one kit upgrade row each for REPAIR, PAINT and every part, with
	the paint swatches on the white under the PAINT row. The builder's header has why each piece is
	the piece it is.

	WHAT IT KNOWS IS UNCHANGED, and so is every rule above: the state is the server's, nothing is
	optimistic, a press is `_ask`. What differs is that the rows are BUILT ONCE AND REWRITTEN IN
	PLACE rather than rebuilt per state, because a kit button carries a hover, a press sound and the
	gamepad's highlight, and destroying the button under the cursor on every reply drops all three.
	Only the swatches are rebuilt, and only when the car's palette changes.

	THE PALETTE IS SHOWN ONCE PER COLOUR. `PaintConfig.poolFor` is a ROLL table, and it lists `Stock`
	several times to weight the dice (`PaintConfig.StockWeight`); the placeholder drew one grey swatch
	per entry. Here each index is one swatch, and `Stock`, which has no single colour to fill with,
	says so on its face.

	If the template is missing, the placeholder is built instead and a warning names the command.

	=== THE CARD LAYOUT (2026-09-30) ============================================================

	`NewUIConfig.WorkshopCards` picks a second kit layout, off Aleafo's reference: a navy card per
	option with a coloured icon tile (`BuildWorkshopCards`, template `Screens.WorkshopCards`). This file
	still owns the screen, its open and close, the pad and every press; `Modules/WorkshopCards` fills
	the cards in. With the flag off, or with that template missing, it is the rows above, unchanged.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local CustomizeConfig = require(ReplicatedStorage.shared.Configs.CustomizeConfig)
local GamepadConfig = require(ReplicatedStorage.shared.Configs.GamepadConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)
local NewUIConfig = require(ReplicatedStorage.shared.Configs.NewUIConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)
--- A mutation's name, for the title (`nameOf`).
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local GamepadInput = require(ReplicatedStorage.shared.Modules.GamepadInput)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)
local WorkshopCards = require(ReplicatedStorage.shared.Modules.WorkshopCards)

local WorkshopController = Shard.new("WorkshopController")

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)
local NAVY = Color3.fromRGB(40, 51, 75)
local MONEY = Color3.fromRGB(13, 180, 21)
local CAPTION = Color3.fromRGB(206, 214, 232)
local DIM = Color3.fromRGB(96, 104, 124)
local WHITE = Color3.new(1, 1, 1)

--- Height of one row in the options list, in pixels. Pixels rather than scale because the list
--- scrolls: a scaled row inside a canvas sized to its contents is a loop the layout cannot settle.
local ROW = 34

local function text(parent: Instance, colour: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.FontFace = FONT
	t.TextColor3 = colour
	t.TextScaled = true
	t.Text = ""
	t.Parent = parent
	return t
end

local function button(parent: Instance, word: string, colour: Color3): TextButton
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = colour
	b.BorderSizePixel = 0
	b.FontFace = FONT
	b.Text = word
	b.TextColor3 = WHITE
	b.TextScaled = true
	b.AutoButtonColor = true
	b.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = b
	return b
end

-- === The frame ==============================================================

--- Build the screen once, hidden: everything that does not change with the car.
function WorkshopController._build(self)
	--- The new UI's screen, when there is one to clone. A missing template falls through to the
	--- placeholder below rather than leaving the bay with no screen.
	if UIRoot.isNewUI() and self:_buildKit() then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "Workshop"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui.Enabled = false

	local shade = Instance.new("TextButton")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.45
	shade.BorderSizePixel = 0
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.Parent = gui
	--- Pressing outside the panel closes it, the offer screen's rule: nothing is bought by leaving.
	shade.Activated:Connect(function()
		self:_close()
	end)

	local panel = Instance.new("ImageLabel")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.62, 0.78)
	panel.Image = UIAssets.url(UIAssets.Page.Panel)
	panel.ScaleType = Enum.ScaleType.Stretch
	panel.BackgroundColor3 = NAVY
	panel.BorderSizePixel = 0
	panel.Active = true -- swallows presses, so a click on the panel is not a click on the shade
	panel.Parent = gui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.45
	aspect.Parent = panel

	local title = text(panel, WHITE)
	title.Position = UDim2.fromScale(0.04, 0.03)
	title.Size = UDim2.fromScale(0.92, 0.08)

	-- Left column: the car and its two numbers.
	local view = CarViewport.new(panel, "Car")
	view.Position = UDim2.fromScale(0.03, 0.14)
	view.Size = UDim2.fromScale(0.42, 0.5)

	local value = text(panel, MONEY)
	value.Position = UDim2.fromScale(0.03, 0.66)
	value.Size = UDim2.fromScale(0.42, 0.08)

	local condition = text(panel, CAPTION)
	condition.Position = UDim2.fromScale(0.03, 0.75)
	condition.Size = UDim2.fromScale(0.42, 0.06)

	local words = CustomizeConfig.Screen
	local change = button(panel, words.Change, Color3.fromRGB(64, 96, 168))
	change.Position = UDim2.fromScale(0.03, 0.86)
	change.Size = UDim2.fromScale(0.2, 0.09)
	change.Activated:Connect(function()
		--- The picker opens over this, so this goes; the lot change it causes brings this back only
		--- if it is already open (`WorkshopService`'s refresh rule), which it now is not.
		self:_ask("change")
		self:_close()
	end)

	local close = button(panel, words.Close, Color3.fromRGB(96, 104, 124))
	close.Position = UDim2.fromScale(0.25, 0.86)
	close.Size = UDim2.fromScale(0.2, 0.09)
	close.Activated:Connect(function()
		self:_close()
	end)

	-- Right column: the options, scrolling, rebuilt per state.
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromScale(0.49, 0.14)
	list.Size = UDim2.fromScale(0.48, 0.81)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.fromScale(0, 0)
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self._screen = {
		gui = gui,
		title = title,
		view = view,
		value = value,
		condition = condition,
		list = list,
		carId = nil :: string?,
	}
end

-- === Drawing ================================================================

--- One full-width row in the list, in order. `height` in rows.
function WorkshopController._row(self, order: number, height: number?): Frame
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -8, 0, ROW * (height or 1))
	row.LayoutOrder = order
	row.Parent = self._screen.list
	return row
end

--- A caption line followed by a button on the right, the shape every option takes.
function WorkshopController._option(self, order: number, caption: string, word: string?, colour: Color3, press: (() -> ())?)
	local row = self:_row(order)
	local label = text(row, CAPTION)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.fromScale(if word then 0.56 else 1, 0.8)
	label.Position = UDim2.fromScale(0, 0.1)
	label.Text = caption
	if word then
		local b = button(row, word, colour)
		b.AnchorPoint = Vector2.new(1, 0)
		b.Position = UDim2.fromScale(1, 0)
		b.Size = UDim2.fromScale(0.42, 1)
		if press then
			b.Activated:Connect(press)
		else
			b.AutoButtonColor = false
		end
	end
end

function WorkshopController._heading(self, order: number, word: string)
	local row = self:_row(order)
	local label = text(row, WHITE)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.fromScale(1, 0.85)
	label.Text = word
end

--[[ The workshop car's mutation, read off its key (`state.carId`, "Body:paint:Mutation"): the
	server already sends the key, so nothing new goes on the wire. 2026-10-14, the owner: "in the
	customisation menu I can't see the car mutation". Drawn on the picture and named in front of
	the car, the way the STOLEN! toast words it. ]]
local function mutationOf(state): string?
	local _, _, mutation = GarageConfig.parseCarKey(state.carId)
	return mutation
end

local function nameOf(state): string
	local mutation = mutationOf(state)
	local name = string.upper(GarageConfig.carName(state.body, state.paint))
	return if mutation then string.upper(WeatherConfig.nameOf(mutation)) .. " " .. name else name
end

--[[ Draw one state from the server. The list is emptied and rebuilt rather than diffed: it is a
	dozen rows at most, redrawn only when the server answers, and a rebuild cannot leave a button
	wired to a price from the last state. ]]
function WorkshopController._draw(self, state)
	if self._cards then
		self._cards:draw(state)
		self:_keepSelection()
		return
	end
	if self._kit then
		self:_drawKit(state)
		return
	end
	local screen = self._screen
	local words = CustomizeConfig.Screen
	local cash = GarageConfig.formatCash

	if screen.carId ~= state.carId then
		screen.carId = state.carId
		CarViewport.set(screen.view, state.body, { paint = tonumber(state.paint), mutation = mutationOf(state) })
	end

	screen.title.Text = string.format(words.Title, nameOf(state))
	screen.value.Text = string.format(words.Value, cash(tonumber(state.value) or 0))
	screen.condition.Text = string.format(words.Condition, math.round((tonumber(state.condition) or 1) * 100))

	for _, child in screen.list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	self:_heading(nextOrder(), words.Repair)
	local repair = state.repair
	if type(repair) == "table" then
		self:_option(nextOrder(), string.format(words.RepairLine, cash(repair.cost), cash(repair.gain)), cash(repair.cost), MONEY, function()
			self:_ask("repair")
		end)
	else
		self:_option(nextOrder(), words.RepairDone, nil, DIM)
	end

	self:_heading(nextOrder(), words.Paint)
	local paints = if type(state.paints) == "table" then state.paints else {}
	if #paints == 0 then
		local by = state.paintLockedBy
		local line = if type(by) == "string" then string.format(words.PaintLockedMutation, by) else words.PaintLocked
		self:_option(nextOrder(), line, nil, DIM)
	else
		self:_option(nextOrder(), string.format(words.PaintLine, cash(state.paintCost)), nil, DIM)
		--- The swatches, wrapped. The current colour is drawn dimmed and does nothing: repainting a
		--- car the colour it already is would be paying for nothing, and the server refuses it anyway.
		local rows = math.ceil(#paints / 6)
		local grid = self:_row(nextOrder(), rows * 1.2)
		local layout = Instance.new("UIGridLayout")
		layout.CellSize = UDim2.new(1 / 6, -6, 0, ROW)
		layout.CellPadding = UDim2.fromOffset(6, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = grid
		for index, paint in paints do
			local current = paint == state.paint
			local swatch = button(grid, if current then "✓" else "", PaintConfig.colorOf(paint) or Color3.fromRGB(150, 150, 150))
			swatch.LayoutOrder = index
			swatch.TextColor3 = WHITE
			if not current then
				swatch.Activated:Connect(function()
					self:_ask("paint", paint)
				end)
			end
		end
	end

	self:_heading(nextOrder(), words.Parts)
	for _, part in (if type(state.parts) == "table" then state.parts else {}) do
		local caption = string.format(words.PartLine, part.label, part.level, part.max)
		if part.cost then
			self:_option(nextOrder(), caption, string.format(words.PartBuy, cash(part.cost), cash(part.gain or 0)), MONEY, function()
				self:_ask("part", part.key)
			end)
		else
			self:_option(nextOrder(), caption, words.PartMax, DIM)
		end
	end
end

-- === The kit screen (new UI) ================================================
--[[ Every name here is one `BuildWorkshopV2` writes, and every pixel the list is laid out in is read
	off the attributes it stamps on `List`, so this file and the art cannot disagree about a row. ]]

local KIT_SHELF = "Screens"
local KIT_TEMPLATE = "Workshop"
--- The card layout's template, `NewUIConfig.WorkshopCards`.
local CARDS_TEMPLATE = "WorkshopCards"
--- How long each step of the path to the template is waited for. The screen is built at start, long
--- after the UI has landed, so this is only ever the backstop for a place without it.
local KIT_WAIT = 5

--- The pop every V2 page opens and closes with (`UIController.openPage`), and the sell prompt's dim.
local KIT_START_SCALE = 0.9
local KIT_OPEN = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local KIT_CLOSE = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SCRIM_REST = 0.45
local SCRIM_TIME = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--[[ Which of the kit's five row colours each row wears, by its place in the artist's stack: 1 red,
	2 lime, 3 blue, 4 purple, 5 orange. REPAIR is the red one (damage), PAINT the blue one, and the
	parts take the other three in turn. ]]
local REPAIR_COLOUR = 1
local PAINT_COLOUR = 3
local PART_COLOURS = { 2, 4, 5 }

--- Each row's picture, by `Repair`, `Paint` or a part's `Key`. A part with none shows no picture.
local ROW_ICONS = UIAssets.Workshop.Icons

--- B closes, as the X does. Bound only while the screen is up.
local PAD_CLOSE = "WorkshopClose"

--- Non-breaking, because `TextScaled` would sooner break a line than shrink it.
local function oneLine(value: string): string
	return (string.gsub(value, " ", "\u{00A0}"))
end

--- A kit row's parts, found once. The template's shape is `BuildWorkshopV2`'s.
local function rowParts(frame: GuiObject)
	local btns = frame:FindFirstChild("Btns")
	local buy = btns and btns:FindFirstChild("BuyBtn")
	local grey = btns and btns:FindFirstChild("GreyBtn")
	local pips = frame:FindFirstChild("UpgradesProgress")
	local gain = frame:FindFirstChild("Gain")
	local pipFaces = {}
	if pips then
		for _, pip in pips:GetChildren() do
			local face = pip:IsA("GuiObject") and pip:FindFirstChildOfClass("UIGradient")
			if face then
				pipFaces[pip.LayoutOrder] = face
			end
		end
	end
	local row = {
		frame = frame,
		face = frame:FindFirstChildOfClass("UIGradient"),
		title = frame:FindFirstChild("Title"),
		icon = frame:FindFirstChild("Icon"),
		sub = frame:FindFirstChild("Sub"),
		gain = gain,
		pips = pips,
		pipFaces = pipFaces,
		btns = btns,
		buy = buy,
		buyCaption = buy and buy:FindFirstChild("Title"),
		grey = grey,
		greyCaption = grey and grey:FindFirstChild("Title"),
		press = nil :: (() -> ())?,
		--- Where the value line sits: beside the button, or against the right edge when the row has
		--- no button (PAINT). Both worked out from the template's own boxes, once.
		gainBeside = gain and gain.Position,
		gainEdge = nil :: UDim2?,
	}
	if gain and btns then
		local right = btns.Position.X.Scale + (1 - btns.AnchorPoint.X) * btns.Size.X.Scale
		gain.AnchorPoint = Vector2.new(0.5, gain.AnchorPoint.Y)
		row.gainEdge = UDim2.new(right - gain.Size.X.Scale / 2, 0, gain.Position.Y.Scale, gain.Position.Y.Offset)
	end
	--[[ The line under the name has two widths: the template's, for a row whose value line has gone
		to the right edge (PAINT), and one that stops short of the value line when it sits beside a
		button (REPAIR), so the two never run into each other. `TextScaled` shrinks a line that is
		too long for the narrow one. ]]
	local sub = row.sub
	if sub and gain then
		local subLeft = sub.Position.X.Scale - sub.AnchorPoint.X * sub.Size.X.Scale
		local gainLeft = gain.Position.X.Scale - gain.AnchorPoint.X * gain.Size.X.Scale
		local width = math.max(0, gainLeft - subLeft - 0.01)
		row.subWide = { position = sub.Position, size = sub.Size }
		row.subNarrow = {
			position = UDim2.new(subLeft + sub.AnchorPoint.X * width, 0, sub.Position.Y.Scale, sub.Position.Y.Offset),
			size = UDim2.new(width, 0, sub.Size.Y.Scale, sub.Size.Y.Offset),
		}
	end
	return row
end

--[[ The new UI's screen: the authored template, cloned into a ScreenGui of this file's own.

	RETURNS WHETHER IT BUILT; false has already been said out loud, and `_build` draws the placeholder.

	THE KIT'S BUTTONS ARRIVE TAGGED (`PrepKitTemplate`, and a tag survives a clone), so every press on
	this screen has the kit's hover, sound and highlight, and they come alive when the ScreenGui is
	parented, which is the last line. ]]
function WorkshopController._buildKit(self): boolean
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", KIT_WAIT)
	local root = playerGui and UIRoot.wait(playerGui :: PlayerGui, KIT_WAIT)
	local shelf = root and root:WaitForChild(KIT_SHELF, KIT_WAIT)
	--- The card layout when it is asked for and its template is whole; the rows otherwise.
	local cards = false
	local template: Instance? = nil
	if shelf and NewUIConfig.WorkshopCards then
		local candidate = shelf:WaitForChild(CARDS_TEMPLATE, KIT_WAIT)
		local cardList = candidate and candidate:FindFirstChild("Main") and candidate.Main:FindFirstChild("List")
		if cardList and cardList:FindFirstChild("RepairCard") and cardList:FindFirstChild("PaintCard") and cardList:FindFirstChild("PartCard") then
			template = candidate
			cards = true
		else
			warn(string.format("[WorkshopController] No usable MainUIV2.%s.%s; drawing the rows. Run BuildWorkshopCards.", KIT_SHELF, CARDS_TEMPLATE))
		end
	end
	if not template then
		template = shelf and shelf:WaitForChild(KIT_TEMPLATE, KIT_WAIT)
	end
	if not (template and template:IsA("GuiObject")) then
		warn(string.format("[WorkshopController] No MainUIV2.%s.%s after %ds; drawing the placeholder. Run BuildWorkshopV2.", KIT_SHELF, KIT_TEMPLATE, KIT_WAIT))
		return false
	end

	local panel = template:Clone() :: GuiObject
	--- The kit's text caps are pixels for a 1080-tall screen; this keeps them in proportion above it.
	require(script.Parent.UIController.KitPage).scaleTextCaps(panel)

	local header = panel:FindFirstChild("Header")
	local title = header and header:FindFirstChild("Title")
	local close = header and header:FindFirstChild("CloseBtn")
	local showcase = panel:FindFirstChild("Showcase")
	local carName = showcase and showcase:FindFirstChild("CarName")
	local portrait = showcase and showcase:FindFirstChild("Portrait")
	local worth = showcase and showcase:FindFirstChild("Worth")
	local condition = showcase and showcase:FindFirstChild("Condition")
	local bar = showcase and showcase:FindFirstChild("ConditionBar")
	local fill = bar and bar:FindFirstChild("Progress")
	local change = showcase and showcase:FindFirstChild("ChangeBtn")
	local main = panel:FindFirstChild("Main")
	local list = main and main:FindFirstChild("List")
	local rowTemplate = list and list:FindFirstChild("RowTemplate")
	local swatchTemplate = list and list:FindFirstChild("SwatchTemplate")
	if
		not (
			title
			and close
			and close:IsA("GuiButton")
			and carName
			and portrait
			and portrait:IsA("GuiObject")
			and worth
			and condition
			and fill
			and fill:IsA("GuiObject")
			and change
			and change:IsA("GuiButton")
			and list
			and list:IsA("ScrollingFrame")
			and (cards or (rowTemplate and rowTemplate:IsA("GuiObject") and swatchTemplate and swatchTemplate:IsA("GuiButton")))
		)
	then
		warn("[WorkshopController] MainUIV2.Screens.Workshop is missing a part; drawing the placeholder. Re-run BuildWorkshopV2.")
		panel:Destroy()
		return false
	end
	--- The templates stay in the clone, hidden, as the source of every row and swatch. Out of the
	--- list, so nothing lays them out and no gamepad walk can land on one. (The cards take theirs.)
	if not cards then
		rowTemplate.Parent = panel
		swatchTemplate.Parent = panel
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "Workshop"
	gui.ResetOnSpawn = false
	--- The placeholder's inset and order: the dim covers the topbar, and the panel centres on the
	--- whole screen, as every modal on the shelf does.
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	--- Pressing outside the panel closes it, the placeholder's rule: nothing is bought by leaving.
	local scrim = Instance.new("TextButton")
	scrim.Name = "Scrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = Color3.new(0, 0, 0)
	scrim.BackgroundTransparency = 1
	scrim.BorderSizePixel = 0
	scrim.Text = ""
	scrim.AutoButtonColor = false
	scrim.Selectable = false
	scrim.Parent = gui
	scrim.Activated:Connect(function()
		self:_close()
	end)

	panel.Visible = false
	panel.Parent = scrim
	--[[ A press on the panel that lands on nothing pressable must not reach the dim and close the
		screen. `Active` on the panel does NOT stop it (measured 2026-09-30 on the offer screen, which
		is built the same way), so the panel carries a button of its own under everything else, which
		takes the press and does nothing with it. ]]
	local catcher = Instance.new("TextButton")
	catcher.Name = "Catcher"
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.BackgroundTransparency = 1
	catcher.Text = ""
	catcher.AutoButtonColor = false
	catcher.Selectable = false
	catcher.ZIndex = 0
	catcher.Parent = panel
	local pop = Instance.new("UIScale")
	pop.Name = "PopScale"
	pop.Scale = KIT_START_SCALE
	pop.Parent = panel

	local words = CustomizeConfig.Screen
	title.Text = oneLine(words.KitTitle)
	local changeCaption = change:FindFirstChild("Title")
	if changeCaption and changeCaption:IsA("TextLabel") then
		changeCaption.Text = oneLine(words.Change)
	end

	local backdrop = portrait:GetAttribute("Backdrop")
	local aspect = portrait:GetAttribute("Aspect")
	local view = CarViewport.new(portrait, "Car", if typeof(backdrop) == "Color3" then backdrop else nil)
	view.Size = UDim2.fromScale(1, 1)
	view.ZIndex = portrait.ZIndex

	self._kit = true
	self._screen = {
		gui = gui,
		scrim = scrim,
		panel = panel,
		pop = pop,
		close = close,
		change = change,
		carName = carName,
		view = view,
		aspect = if type(aspect) == "number" then aspect else 1.5,
		spin = nil :: CarViewport.Spin?,
		worth = worth,
		condition = condition,
		fill = fill,
		list = list,
		rowTemplate = rowTemplate,
		swatchTemplate = swatchTemplate,
		rows = {} :: { [string]: any },
		--- The rows top to bottom, as last drawn: the order a pad's first highlight is looked for in.
		rowOrder = {} :: { any },
		partKeys = "",
		block = nil :: Frame?,
		swatches = {} :: { any },
		paletteKey = "",
		paint = nil :: number?,
		carId = nil :: string?,
		open = false,
		token = 0,
	}

	close.Activated:Connect(function()
		self:_close()
	end)
	change.Activated:Connect(function()
		--- The picker opens over this, so this goes; see the placeholder's CHANGE CAR for the rest.
		self:_ask("change")
		self:_close()
	end)

	if cards then
		self._cards = WorkshopCards.new(self._screen, {
			ask = function(action: string, arg: any?)
				self:_ask(action, arg)
			end,
		})
	end
	if not self._cards then
		--- The two rows every car has. The parts are made on the first state, from its list.
		self:_newRow("repair", words.Repair, REPAIR_COLOUR, ROW_ICONS.Repair)
		self:_newRow("paint", words.Paint, PAINT_COLOUR, ROW_ICONS.Paint)
	end

	gui.Parent = playerGui
	return true
end

--- One row off the template, titled, coloured and pictured, wired once to whatever press the latest
--- state gave it. Parented to the list; `_layoutKit` places it.
function WorkshopController._newRow(self, key: string, word: string, colour: number, icon: number?)
	local screen = self._screen
	local frame = screen.rowTemplate:Clone() :: GuiObject
	frame.Name = key
	frame.Visible = true
	local row = rowParts(frame)
	local count = screen.rowTemplate:GetAttribute("ColorCount")
	local index = if type(count) == "number" and count > 0 then (colour - 1) % count + 1 else colour
	local ramp = screen.rowTemplate:GetAttribute("Color" .. index)
	if row.face and typeof(ramp) == "ColorSequence" then
		row.face.Color = ramp
	end
	if row.title then
		row.title.Text = oneLine(word)
	end
	if row.icon then
		row.icon.Image = if icon then UIAssets.url(icon) else ""
		row.icon.Visible = icon ~= nil
	end
	if row.buy then
		row.buy.Activated:Connect(function()
			if row.press then
				row.press()
			end
		end)
	end
	frame.Parent = screen.list
	screen.rows[key] = row
	return row
end

--[[ Write one row. Every field is optional and an absent one is hidden:
	`sub` the line under the name, `level`/`max` the meter, `gain` the value line, `price` the green
	button (with `press`), `grey` the grey one. A row with neither button moves its value line to the
	right edge, where the button would have been. ]]
function WorkshopController._setRow(self, row, spec)
	local hasButton = spec.price ~= nil or spec.grey ~= nil
	if row.sub then
		row.sub.Visible = spec.sub ~= nil
		if spec.sub then
			row.sub.Text = oneLine(spec.sub)
		end
		local box = if spec.gain ~= nil and hasButton then row.subNarrow else row.subWide
		if box then
			row.sub.Position = box.position
			row.sub.Size = box.size
		end
	end

	if row.pips then
		row.pips.Visible = spec.level ~= nil
		if spec.level then
			local on = row.pips:GetAttribute("OnColor")
			local off = row.pips:GetAttribute("OffColor")
			for order, face in row.pipFaces do
				local lit = order <= spec.level
				local ramp = if lit then on else off
				if typeof(ramp) == "ColorSequence" then
					face.Color = ramp
				end
				--- A ladder shorter than the meter hides the pips past its top.
				local pip = face.Parent :: GuiObject
				pip.Visible = order <= (spec.max or order)
			end
		end
	end

	if row.gain then
		row.gain.Visible = spec.gain ~= nil
		if spec.gain then
			row.gain.Text = oneLine(spec.gain)
		end
		local where = if hasButton then row.gainBeside else row.gainEdge
		if where then
			row.gain.Position = where
		end
	end

	if row.btns then
		row.btns.Visible = hasButton
	end
	if row.buy then
		row.buy.Visible = spec.price ~= nil
		if spec.price and row.buyCaption then
			row.buyCaption.Text = oneLine(spec.price)
		end
	end
	if row.grey then
		row.grey.Visible = spec.price == nil and spec.grey ~= nil
		if spec.grey and row.greyCaption then
			row.greyCaption.Text = oneLine(spec.grey)
		end
	end
	row.press = spec.press
end

--[[ The palette, deduplicated in order. `poolFor` is a roll table and lists `Stock` more than once to
	weight it (see the header); a screen offers each colour once. ]]
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

--- Rebuild the swatches when the palette changes; otherwise only move the check.
function WorkshopController._drawSwatches(self, paints: { number }, current: number?)
	local screen = self._screen
	local key = table.concat(paints, ",")
	if key ~= screen.paletteKey then
		screen.paletteKey = key
		if screen.block then
			screen.block:Destroy()
			screen.block = nil
		end
		table.clear(screen.swatches)
		if #paints > 0 then
			local block = Instance.new("Frame")
			block.Name = "Swatches"
			block.BackgroundTransparency = 1
			block.BorderSizePixel = 0
			for order, index in paints do
				local swatch = screen.swatchTemplate:Clone() :: GuiButton
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
				local entry = { button = swatch, check = swatch:FindFirstChild("Check"), paint = index }
				swatch.Activated:Connect(function()
					--- The colour the car already wears does nothing: the server refuses it anyway.
					if entry.paint ~= screen.paint then
						self:_ask("paint", entry.paint)
					end
				end)
				swatch.Parent = block
				table.insert(screen.swatches, entry)
			end
			block.Parent = screen.list
			screen.block = block
		end
	end
	for _, entry in screen.swatches do
		if entry.check then
			entry.check.Visible = entry.paint == current
		end
	end
end

--[[ Place every row and the swatch block down the list, in the builder's pixels, written as scale of
	the CANVAS: the canvas is sized first, and a child's scale resolves against the canvas, so a row is
	its authored height whether or not the list scrolls. No `UIListLayout` and no
	`AutomaticCanvasSize`: that pair with scale rows is the runaway `KitPage` exists to avoid.

	THE CANVAS'S SCALE IS NOT IN THE LIST'S OWN HEIGHT. Measured live, a `CanvasSize` scale of 1 on
	this list came out as its PARENT's height, so the canvas is written against `CanvasBasis`, the
	height the builder stamps for that, and a list that fits is exactly as tall as its window. ]]
function WorkshopController._layoutKit(self, order: { GuiObject })
	local screen = self._screen
	local list = screen.list
	local width = list:GetAttribute("ReferenceWidth") or 710
	local height = list:GetAttribute("ReferenceHeight") or 604
	local side = list:GetAttribute("RowSide") or 8
	local pad = list:GetAttribute("ListPad") or 6
	local rowH = list:GetAttribute("RowHeight") or 84
	local gap = list:GetAttribute("RowGap") or 10
	local swatch = list:GetAttribute("Swatch") or 54
	local swatchGap = list:GetAttribute("SwatchGap") or 10
	local columns = list:GetAttribute("SwatchColumns") or 10
	local rowW = width - 2 * side

	local heights = {}
	local total = 2 * pad
	for index, frame in order do
		local h = rowH
		if frame == screen.block then
			local lines = math.ceil(#screen.swatches / columns)
			h = lines * swatch + math.max(0, lines - 1) * swatchGap
		end
		heights[index] = h
		total += h + (if index > 1 then gap else 0)
	end
	local canvas = math.max(total, height)
	local basis = list:GetAttribute("CanvasBasis")
	list.CanvasSize = UDim2.fromScale(0, canvas / (if type(basis) == "number" and basis > 0 then basis else height))

	local y = pad
	for index, frame in order do
		local h = heights[index]
		frame.AnchorPoint = Vector2.new(0, 0)
		frame.Position = UDim2.fromScale(side / width, y / canvas)
		frame.Size = UDim2.fromScale(rowW / width, h / canvas)
		y += h + gap
	end

	--- The swatches inside their block, centred as a grid. Scale of the block, whose size is known.
	local block = screen.block
	if block then
		local blockH = heights[table.find(order, block) or 1]
		local used = math.min(#screen.swatches, columns)
		local left = (rowW - (used * swatch + (used - 1) * swatchGap)) / 2
		for index, entry in screen.swatches do
			local column = (index - 1) % columns
			local line = (index - 1) // columns
			entry.button.AnchorPoint = Vector2.new(0, 0)
			entry.button.Position = UDim2.fromScale((left + column * (swatch + swatchGap)) / rowW, line * (swatch + swatchGap) / blockH)
			entry.button.Size = UDim2.fromScale(swatch / rowW, swatch / blockH)
		end
	end
end

--- Draw one state from the server onto the kit screen. See the section header for what is rebuilt.
function WorkshopController._drawKit(self, state)
	local screen = self._screen
	local words = CustomizeConfig.Screen
	local cash = GarageConfig.formatCash
	local paint = tonumber(state.paint)
	screen.paint = paint

	--- The car. A repaint re-keys it (`CustomizeConfig` note 4), so the ID changing is also how a
	--- new colour reaches the picture.
	if screen.carId ~= state.carId then
		screen.carId = state.carId
		if screen.spin then
			screen.spin.stop()
			screen.spin = nil
		end
		if CarViewport.set(screen.view, state.body, { paint = paint, aspect = screen.aspect, mutation = mutationOf(state) }) then
			screen.view.Visible = true
			screen.spin = CarViewport.spin(screen.view, { aspect = screen.aspect })
		end
	end

	screen.carName.Text = oneLine(nameOf(state))
	screen.worth.Text = oneLine(string.format(words.Value, cash(tonumber(state.value) or 0)))
	local condition = math.clamp(tonumber(state.condition) or 1, 0, 1)
	screen.condition.Text = oneLine(string.format(words.Condition, math.round(condition * 100)))
	screen.fill.Size = UDim2.fromScale(condition, screen.fill.Size.Y.Scale)
	screen.fill.Visible = condition > 0

	local rows = screen.rows
	local repair = state.repair
	if type(repair) == "table" then
		self:_setRow(rows.repair, {
			sub = words.RepairSub,
			gain = string.format(words.Gain, cash(tonumber(repair.gain) or 0)),
			price = cash(tonumber(repair.cost) or 0),
			press = function()
				self:_ask("repair")
			end,
		})
	else
		self:_setRow(rows.repair, { sub = words.RepairDone, grey = words.RepairFull })
	end

	local paints = uniquePaints(if type(state.paints) == "table" then state.paints else {})
	if #paints == 0 then
		self:_setRow(rows.paint, { sub = words.PaintKept })
	else
		self:_setRow(rows.paint, {
			sub = words.PaintSub,
			gain = string.format(words.PaintEach, cash(tonumber(state.paintCost) or 0)),
		})
	end
	self:_drawSwatches(paints, paint)

	--- The parts, made the first time a list is seen and whenever its keys change.
	local parts = if type(state.parts) == "table" then state.parts else {}
	local keys = {}
	for _, part in parts do
		table.insert(keys, tostring(part.key))
	end
	local partKeys = table.concat(keys, ",")
	if partKeys ~= screen.partKeys then
		screen.partKeys = partKeys
		for key, row in rows do
			if key ~= "repair" and key ~= "paint" then
				row.frame:Destroy()
				rows[key] = nil
			end
		end
		for index, part in parts do
			self:_newRow(
				"part:" .. tostring(part.key),
				tostring(part.label),
				PART_COLOURS[(index - 1) % #PART_COLOURS + 1],
				ROW_ICONS[tostring(part.key)]
			)
		end
	end

	local order = { rows.repair.frame, rows.paint.frame }
	local rowOrder = { rows.repair, rows.paint }
	if screen.block then
		table.insert(order, screen.block)
	end
	for _, part in parts do
		local row = rows["part:" .. tostring(part.key)]
		if row then
			table.insert(rowOrder, row)
			local cost = tonumber(part.cost)
			self:_setRow(row, {
				level = tonumber(part.level) or 0,
				max = tonumber(part.max),
				gain = if cost then string.format(words.Gain, cash(tonumber(part.gain) or 0)) else nil,
				price = if cost then cash(cost) else nil,
				grey = if cost then nil else words.PartMax,
				press = if cost
					then function()
						self:_ask("part", part.key)
					end
					else nil,
			})
			table.insert(order, row.frame)
		end
	end
	screen.rowOrder = rowOrder
	self:_layoutKit(order)
	self:_keepSelection()
end

--[[ A pad's highlight has to be ON something live. It lands on the first price on open, and moves
	there again when the one it was on went grey (a part just maxed, the repair just done). A mouse
	player is never given a highlight they did not ask for. ]]
function WorkshopController._keepSelection(self)
	local screen = self._screen
	if not (screen and screen.open and GamepadInput.isGamepadActive()) then
		return
	end
	--- Drawn, all the way up to the panel: a button in a hidden row is not a place to stand.
	local function shown(gui: Instance?): boolean
		local node = gui
		while node and node ~= screen.panel do
			if node:IsA("GuiObject") and not node.Visible then
				return false
			end
			node = node.Parent
		end
		return node == screen.panel
	end
	if shown(GuiService.SelectedObject) then
		return
	end
	for _, row in screen.rowOrder do
		if row.buy and shown(row.buy) then
			GuiService.SelectedObject = row.buy
			return
		end
	end
	local first = screen.swatches[1]
	GuiService.SelectedObject = if first then first.button else screen.change
end

--- Bring the panel up: the dim on the sell prompt's timing, the panel popping from 0.9.
function WorkshopController._raiseKit(self)
	local screen = self._screen
	if screen.open then
		return
	end
	screen.open = true
	screen.token += 1
	screen.gui.Enabled = true
	screen.panel.Visible = true
	screen.pop.Scale = KIT_START_SCALE
	TweenService:Create(screen.pop, KIT_OPEN, { Scale = 1 }):Play()
	TweenService:Create(screen.scrim, SCRIM_TIME, { BackgroundTransparency = SCRIM_REST }):Play()

	--- The HUD's own navigation stands down while this is up (`GamepadConfig.ModalAttribute`).
	GamepadInput.setModal("WorkshopController", true)
	GamepadInput.bind({
		actionName = PAD_CLOSE,
		keyCode = Enum.KeyCode.ButtonB,
		callback = function()
			self:_close()
		end,
		parent = screen.close,
	})
	--[[ The DPad stays inside the panel. Without a selection group the engine walks straight out of
		it onto the HUD rail drawn behind the dim, the trap `GamepadNav` sets on every page. ]]
	local panel = screen.panel
	panel.SelectionGroup = true
	panel.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	self:_keepSelection()
end

--- Take the panel down, and put the car away once it is out of sight.
function WorkshopController._lowerKit(self)
	local screen = self._screen
	if not screen.open then
		return
	end
	screen.open = false
	screen.carId = nil
	screen.token += 1
	local token = screen.token
	if self._cards then
		self._cards:closed()
	end

	GamepadInput.unbind(PAD_CLOSE)
	GamepadInput.setModal("WorkshopController", false)
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(screen.panel) then
		GuiService.SelectedObject = nil
	end

	TweenService:Create(screen.pop, KIT_CLOSE, { Scale = KIT_START_SCALE }):Play()
	local fade = TweenService:Create(screen.scrim, SCRIM_TIME, { BackgroundTransparency = 1 })
	fade:Play()
	fade.Completed:Once(function()
		--- Fenced, so the tail of a close never shuts a screen that has been opened again since.
		if screen.token ~= token then
			return
		end
		screen.gui.Enabled = false
		screen.panel.Visible = false
		if screen.spin then
			screen.spin.stop()
			screen.spin = nil
		end
		CarViewport.clear(screen.view)
	end)
end

-- === Talking to the server ==================================================

--- Send one press. Rate limited here as a courtesy; the server has its own floor.
function WorkshopController._ask(self, action: string, arg: any?)
	local now = os.clock()
	if now < self._nextAsk then
		return
	end
	self._nextAsk = now + CustomizeConfig.Screen.Cooldown
	self:getRemoteEvent("WorkshopRequest"):Fire(action, arg)
end

function WorkshopController._close(self)
	local screen = self._screen
	if not screen then
		return
	end
	if self._kit then
		self:_lowerKit()
		return
	end
	screen.gui.Enabled = false
	screen.carId = nil
	CarViewport.clear(screen.view)
end

--- Is the screen up? The kit's is still ENABLED while it animates shut, so it keeps its own flag.
function WorkshopController._isOpen(self): boolean
	local screen = self._screen
	if not screen then
		return false
	end
	if self._kit then
		return screen.open == true
	end
	return screen.gui.Enabled
end

--[[ The server's `WorkshopState`. A nil state closes the screen (the car left the workshop). A
	`refresh` the player did not ask for is dropped while the screen is shut; see the remote's note
	in `WorkshopService` for why the server cannot tell. ]]
function WorkshopController._onState(self, state: unknown, refresh: unknown)
	local screen = self._screen
	if not screen then
		return
	end
	if refresh == true and not self:_isOpen() then
		return
	end
	if type(state) ~= "table" or type(state.body) ~= "string" then
		self:_close()
		return
	end
	if self._kit then
		--- Drawn before it is raised, so the panel pops open already showing this car.
		self:_draw(state)
		self:_raiseKit()
		return
	end
	screen.gui.Enabled = true
	self:_draw(state)
end

WorkshopController:withRemoteEvents({
	"WorkshopRequest",
	{
		WorkshopState = function(state: unknown, refresh: unknown)
			WorkshopController:_onState(state, refresh)
		end,
	},
})

WorkshopController:withLifecycle({
	init = function(self)
		self._nextAsk = 0
	end,

	start = function(self)
		if not CustomizeConfig.Enabled then
			return
		end
		self:_build()
	end,
})

return WorkshopController
