--[[
	CarryHotbarController  (client)
	-------------------------------
	The hotbar: up to `CarryConfig.Hotbar.Slots` cars along the bottom of the screen, the one in your
	hands lit. `CarryConfig.Hotbar` has the design (the hotbar is a PLACE a car lives, beside the bays
	and the inventory); `GarageService.hotbarAction` has every rule; `CarryService` owns the model in
	the hands; `CarryController` still owns the card and the glowing bays.

	=== ONE CLICK, TWO MEANINGS, AND THE CAPTION SAYS WHICH — 2026-09-30 ======================

	    inventory shut   the click HOLDS the car, or puts it back in its slot if it is the one held
	    inventory open   the click MOVES the car into the inventory, and `Text.MoveHint` sits over
	                     the bar for as long as the screen is up, because the same click now does
	                     something else. The card's TO HOTBAR button is the way back out.

	WHAT IT WAS. One slot, drawn only while something was held, whose click always put the car away
	(2026-09-28): the intermediary caption was cut then because the one slot had one job. Nine slots
	with two jobs is the case the caption is for, so it is back, and only while it is true.

	The number keys are the same as clicking that tile with the inventory shut — Roblox's own
	backpack keys, which are free because its bar is down for good (`CarryConfig.Hold.Tool`).

	=== THE BACKPACK IS TILE 1 — 2026-09-30 =====================================================

	The owner's ask: a backpack tile, always first, that opens and shuts the Cars Inventory. It takes
	the 1 key and the cars move up to 2..9 and 0 (Roblox's own ten-tile numbering). Because it is
	always there, the bar is now up for the whole lobby rather than only while a car is in it, and the
	tile's rim lights while the inventory is open, which is the same moment the MOVE IN / OUT caption
	is up. A tile rather than a topbar icon, because the bar is where the cars it moves between live.

	=== IT READS TWO ATTRIBUTES AND SENDS ONE EVENT ============================================

	`CarryConfig.Hotbar.Attribute` is which cars are in the slots, `CarryConfig.Attribute` is the one
	held — the same broadcasts the server writes, so the bar cannot disagree with the save. A click
	goes out as `HotbarAction` (`DealershipController` puts it on the wire) and changes nothing here:
	the attribute write coming back is the repaint.

	Hidden for the length of a run (`RaceStart` / `RaceEnd`), because so is the car: `CarryService`
	takes the model off for a race, and a bar showing a car you are holding would be lying.

	=== SMALLER ON TOUCH, AND OUT OF THE WAY OF MENUS, 2026-10-06 ===========================

	Leaf, on a phone: "too large and interferes with world menu, make it hide after opening the
	menu". So the tiles take `Hotbar.TouchSize` while `PreferredInput` is Touch, and the bar steps
	aside while any page or the radio panel is up (`PageOpened` / `PageClosed`), except over the pages
	in `Hotbar.ShowOverPages`: the Cars Inventory, whose MOVE IN / OUT is a click on a tile.

	=== ON A CONTROLLER, 2026-10-06 ============================================================

	Leaf asked twice for a console pass. Everything else answers to a pad (`GamepadConfig`), but the
	bar took only mouse, touch and digits, and once the Cars cell left the rail the backpack tile was
	the only way into the Cars Inventory. So, on foot with the bar up: R1 and L1 step the car in your
	hands along the bar (empty hands is one of the steps), and View/Select is the backpack. Each has its
	glyph on the bar while `PreferredInput` is a gamepad. They are bound only while the bar is up and
	you are not in a seat, so L1 is still nitro in a lobby car and Y and X keep their jobs. Select is
	free because `GamepadNav` turns the engine's auto-select off.

	The tiles cannot be selected (the inventory page traps the highlight), so the click's second
	meaning has a key of its own: with the Cars Inventory open and a car in your hands, Y moves that
	car in, and the caption over the bar says so (2026-10-15, `_syncMove`).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local CarryConfig = require(ReplicatedStorage.shared.Configs.CarryConfig)
local GamepadConfig = require(ReplicatedStorage.shared.Configs.GamepadConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local RadioConfig = require(ReplicatedStorage.shared.Configs.RadioConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)
local GamepadInput = require(ReplicatedStorage.shared.Modules.GamepadInput)

local CarryHotbarController = Shard.new("CarryHotbarController")

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)
local NAVY = Color3.fromRGB(40, 51, 75)
--- The held slot's rim. Gold and thicker, so "this one is in your hands" reads at a glance.
local HELD_RIM = Color3.fromRGB(255, 200, 40)
local IDLE_RIM = Color3.new(1, 1, 1)

--[[ Over every lobby screen that can lie across the bottom of the view — the tutorial card's gui is
	950 — and under the modals (996 and up), the results screen and the return fade. It was 870, under
	the carry card, and a playtest on 2026-09-30 found only the very middle of a slot took a click:
	something higher in the stack was lying over the rest of it. The bar is small and only exists in
	the lobby, so sitting over the tutorial costs nothing. ]]
local DISPLAY_ORDER = 960

--- The inventory screen, whose being open changes what a click means. `UIController.pages` key.
local INVENTORY_PAGE = "Dealership"

--- The controller's three buttons (header, "On a controller"), and the action names they bind under.
local PAD = {
	Next = { action = "CarryHotbarNext", key = Enum.KeyCode.ButtonR1 },
	Prev = { action = "CarryHotbarPrev", key = Enum.KeyCode.ButtonL1 },
	Backpack = { action = "CarryHotbarBackpack", key = Enum.KeyCode.ButtonSelect },
}

--[[ The fourth, live only while the Cars Inventory is open and a hotbar car is in your hands: Y moves
	that car into the inventory, the click's meaning on a tile while the screen is up. Kept out of `PAD`
	because it comes and goes with the screen, not with the bar (`_syncMove`). Y and not a face the
	page uses: A presses its cards, B shuts it, X is every prompt in the lot. ]]
local PAD_MOVE = { action = "CarryHotbarMove", key = Enum.KeyCode.ButtonY }

--- The digit keys, tile 1 (the backpack) first, then the cars; 0 is the tenth tile, as on Roblox's own
--- bar. Only as many as there are tiles are bound.
local DIGITS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
	Enum.KeyCode.Seven,
	Enum.KeyCode.Eight,
	Enum.KeyCode.Nine,
	Enum.KeyCode.Zero,
}

--- The number printed on tile `n`: 1..9, then 0 for the tenth.
local function digitFor(n: number): string
	return tostring(n % 10)
end

type Slot = {
	button: ImageLabel,
	view: ViewportFrame,
	rim: UIStroke,
	glyph: ImageLabel,
	shown: string?, -- the car ID the viewport was last built for; rebuilt only when it changes
}

-- === Drawing ================================================================

function CarryHotbarController._buildSlot(self, parent: Instance, index: number): Slot
	local hotbar = CarryConfig.Hotbar
	local button = Instance.new("ImageLabel")
	button.Name = "Slot" .. index
	--- After the backpack, which is LayoutOrder 0 and tile 1; so car slot `index` is tile `index + 1`.
	button.LayoutOrder = index
	button.Size = UDim2.fromOffset(hotbar.Size, hotbar.Size) -- `_fit` sets the real size
	button.Image = UIAssets.url(UIAssets.Page.Panel)
	button.ScaleType = Enum.ScaleType.Stretch
	button.BackgroundColor3 = NAVY
	button.BorderSizePixel = 0
	button.Visible = false
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.15, 0)
	corner.Parent = button
	local rim = Instance.new("UIStroke")
	rim.Color = IDLE_RIM
	rim.Thickness = 2
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = button

	--[[ NO CAPTION, AND THE CAR FILLS THE TILE (2026-09-30, the owner's call for every tile). The name
		took the bottom quarter and the car sat small above it; the picture says which car it is, and
		the full name is one press away on the inventory card. `aspect = 1` in `_apply` is this square. ]]
	local view = CarViewport.new(button, "Car")
	view.Position = UDim2.fromScale(0.03, 0.03)
	view.Size = UDim2.fromScale(0.94, 0.94)

	--- The digit that selects this slot, in the corner, the way Roblox's own bar numbers its slots.
	local digit = Instance.new("TextLabel")
	digit.Position = UDim2.fromScale(0.06, 0.02)
	digit.Size = UDim2.fromScale(0.28, 0.24)
	digit.BackgroundTransparency = 1
	digit.FontFace = FONT
	digit.TextColor3 = Color3.new(1, 1, 1)
	digit.TextTransparency = 0.25
	digit.TextScaled = true
	digit.TextXAlignment = Enum.TextXAlignment.Left
	digit.Text = digitFor(index + 1)
	digit.Parent = button

	--[[ THE MUTATION, as its weather's glyph in the corner opposite the digit (Aleafo, 2026-10-15:
		"need mutation icon here"). The same glyph the inventory card wears (`Modules/CarCardDress`), and
		the only tell for Soaked and Charged, whose looks a viewport cannot draw. `_apply` fills it. ]]
	local glyph = Instance.new("ImageLabel")
	glyph.Name = "MutationGlyph"
	glyph.AnchorPoint = Vector2.new(1, 0)
	glyph.Position = UDim2.fromScale(0.96, 0.04)
	glyph.Size = UDim2.fromScale(0.32, 0.32)
	glyph.BackgroundTransparency = 1
	glyph.ScaleType = Enum.ScaleType.Fit
	glyph.ZIndex = 2
	glyph.Visible = false
	glyph.Parent = button

	--[[ ONE CLICK TARGET OVER THE WHOLE SLOT, laid on top of the picture and the digit, so a
		press anywhere on the tile is a press on the slot — the slot itself is only the picture. See
		`DISPLAY_ORDER` for the other half of the "only the car took the click" fix. The hover dims the
		tile the way `AutoButtonColor` did when the slot was the button. ]]
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.ZIndex = 10
	hit.Parent = button
	hit.MouseEnter:Connect(function()
		button.ImageColor3 = Color3.fromRGB(215, 215, 215)
	end)
	hit.MouseLeave:Connect(function()
		button.ImageColor3 = Color3.new(1, 1, 1)
	end)
	hit.Activated:Connect(function()
		self:_press(index)
	end)
	self:_watchHit(hit)
	table.insert(self._tiles, {
		button = button,
		press = function()
			self:_press(index)
		end,
	})
	return { button = button, view = view, rim = rim, glyph = glyph, shown = nil }
end

--- The press really reached this tile. `_catchStray` reads it to stay out of the way.
function CarryHotbarController._watchHit(self, hit: GuiButton)
	hit.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self._hitAt = os.clock()
		end
	end)
end

--[[ Tile 1: the backpack. The same tile shape as a car's — panel, rim, digit — with the owner's
	image filling it, so the bar reads as one row of ten rather than a button glued to a bar. No
	caption, unlike a car's: the picture says what it is (the owner's call, 2026-09-30). ]]
function CarryHotbarController._buildBackpack(self, parent: Instance)
	local hotbar = CarryConfig.Hotbar
	local tile = Instance.new("ImageLabel")
	tile.Name = "Backpack"
	tile.LayoutOrder = 0
	tile.Size = UDim2.fromOffset(hotbar.Size, hotbar.Size) -- `_fit` sets the real size
	tile.Image = UIAssets.url(UIAssets.Page.Panel)
	tile.ScaleType = Enum.ScaleType.Stretch
	tile.BackgroundColor3 = NAVY
	tile.BorderSizePixel = 0
	tile.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.15, 0)
	corner.Parent = tile
	local rim = Instance.new("UIStroke")
	rim.Color = IDLE_RIM
	rim.Thickness = 2
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = tile

	--- No caption on this tile (the owner's call), so the icon takes the room the words had.
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.94, 0.94)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = UIAssets.url(hotbar.BackpackImage)
	icon.Parent = tile

	local digit = Instance.new("TextLabel")
	digit.Position = UDim2.fromScale(0.06, 0.02)
	digit.Size = UDim2.fromScale(0.28, 0.24)
	digit.BackgroundTransparency = 1
	digit.FontFace = FONT
	digit.TextColor3 = Color3.new(1, 1, 1)
	digit.TextTransparency = 0.25
	digit.TextScaled = true
	digit.TextXAlignment = Enum.TextXAlignment.Left
	digit.Text = digitFor(1)
	digit.Parent = tile

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.ZIndex = 10
	hit.Parent = tile
	hit.MouseEnter:Connect(function()
		tile.ImageColor3 = Color3.fromRGB(215, 215, 215)
	end)
	hit.MouseLeave:Connect(function()
		tile.ImageColor3 = Color3.new(1, 1, 1)
	end)
	hit.Activated:Connect(function()
		self:_toggleInventory()
	end)
	self:_watchHit(hit)
	table.insert(self._tiles, {
		button = tile,
		press = function()
			self:_toggleInventory()
		end,
	})
	self._backpackRim = rim
	self._backpackTile = tile
end

--[[ Open the Cars Inventory, or shut it. Opened through `UIController` with no bay armed, which is
	what makes it the inventory rather than a podium's picker (`PagesV2/Dealership` rule 1). ]]
function CarryHotbarController._toggleInventory(self)
	if self._racing then
		return
	end
	local UIController = Shard.get("UIController")
	if not UIController then
		return
	end
	if self:_inventoryOpen() then
		UIController:closePage(INVENTORY_PAGE)
	else
		UIController:openPage(INVENTORY_PAGE)
	end
end

function CarryHotbarController._build(self)
	local hotbar = CarryConfig.Hotbar
	local gui = Instance.new("ScreenGui")
	gui.Name = "CarryHotbar"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = DISPLAY_ORDER
	gui.Enabled = false

	local bar = Instance.new("ScrollingFrame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1 - hotbar.Lift, -hotbar.Margin)
	bar.Size = UDim2.fromOffset(0, hotbar.Size)
	bar.CanvasSize = UDim2.fromOffset(0, 0)
	bar.ScrollingDirection = Enum.ScrollingDirection.X
	bar.ScrollBarThickness = 3
	--- Not a stop of its own for a pad highlight walking down from PLAY: the tiles inside are.
	bar.Selectable = false
	bar.BorderSizePixel = 0
	bar.ClipsDescendants = true
	bar.BackgroundTransparency = 1
	bar.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, hotbar.Gap)
	layout.Parent = bar
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 4)
	padding.Parent = bar

	local hint = Instance.new("TextLabel")
	hint.Name = "MoveHint"
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1 - hotbar.Lift, -hotbar.Margin - hotbar.Size - 6)
	hint.Size = UDim2.fromOffset(420, 24)
	hint.BackgroundTransparency = 1
	hint.FontFace = FONT
	hint.TextColor3 = Color3.new(1, 1, 1)
	hint.TextScaled = true
	hint.Text = hotbar.Text.MoveHint
	hint.Visible = false
	hint.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = NAVY
	stroke.Parent = hint

	self._tiles = {} :: { { button: GuiObject, press: () -> () } }
	self:_buildBackpack(bar)
	self._slots = {} :: { Slot }
	for index = 1, hotbar.Slots do
		table.insert(self._slots, self:_buildSlot(bar, index))
	end

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self._gui = gui
	self._hint = hint
	self._bar = bar
	self._layout = layout
	self:_fit()
end

--- The tile size and gap for the device in hand: smaller on touch. See the header.
function CarryHotbarController._tileSize(self): (number, number)
	local hotbar = CarryConfig.Hotbar
	if UserInputService.PreferredInput == Enum.PreferredInput.Touch then
		return hotbar.TouchSize or hotbar.Size, hotbar.TouchGap or hotbar.Gap
	end
	return hotbar.Size, hotbar.Gap
end

--- Size every tile, the bar and the caption over it to `_tileSize`. Again whenever the input changes.
function CarryHotbarController._fit(self)
	if not self._bar then
		return
	end
	local hotbar = CarryConfig.Hotbar
	local size, gap = self:_tileSize()
	local count = 0
	for _, tile in self._tiles do
		tile.button.Size = UDim2.fromOffset(size, size)
		if tile.button.Visible then count += 1 end
	end
	local viewport = workspace.CurrentCamera.ViewportSize
	local content = count * size + math.max(count - 1, 0) * gap + 8
	local width = math.min(content, viewport.X - 24)
	-- Scroll instead of shrinking ten touch targets below 42px or adding a row over PLAY (2026-10-12).
	self._bar.Size = UDim2.fromOffset(width, size + 8)
	self._bar.CanvasSize = UDim2.fromOffset(content, 0)
	self._bar.ScrollingEnabled = content > width
	self._bar.ClipsDescendants = content > width
	self._bar.CanvasPosition = Vector2.new(math.clamp(self._bar.CanvasPosition.X, 0, math.max(content - width, 0)), 0)
	self._layout.Padding = UDim.new(0, gap)
	self._hint.Size = UDim2.fromOffset(math.min(420, viewport.X - 24), 24)
	--[[ On a pad the backpack's Select glyph hangs above its tile, right where the caption sits, so
		the caption steps up by a glyph's height (`GamepadConfig.Icon.Size`, a 1080p pixel). ]]
	local padLift = if GamepadInput.isGamepad() then GamepadConfig.Icon.Size * viewport.Y / 1080 else 0
	self._hint.Position = UDim2.new(0.5, 0, 1 - hotbar.Lift, -hotbar.Margin - size - 14 - padLift)
end

--[[ Is a menu up that the bar should step aside for? Any page but those in `ShowOverPages`, or the
	radio panel, which stands where a page does. ]]
function CarryHotbarController._menuUp(self): boolean
	if self._radioUp then
		return true
	end
	local UIController = Shard.get("UIController")
	return UIController ~= nil
		and UIController.anyPageOpen ~= nil
		and UIController:anyPageOpen(CarryConfig.Hotbar.ShowOverPages)
end

--- The hotbar's car IDs, slot order.
function CarryHotbarController._ids(self): { string }
	return GarageConfig.split(Players.LocalPlayer:GetAttribute(CarryConfig.Hotbar.Attribute))
end

--[[ Redraw from the two attributes. A slot's viewport is rebuilt only when its car changes: it is a
	model clone, and a race ending or the held car moving is no reason to make another. ]]
function CarryHotbarController._apply(self)
	if not self._gui then
		return
	end
	local ids = self:_ids()
	local held = Players.LocalPlayer:GetAttribute(CarryConfig.Attribute)
	--- The whole lobby now, not only while a car is in it: the backpack tile is always there. Down
	--- behind a menu, though. See the header.
	self._gui.Enabled = not self._racing and not self:_menuUp()

	for index, slot in self._slots do
		local id = ids[index]
		slot.button.Visible = id ~= nil
		local isHeld = id ~= nil and id == held
		slot.rim.Color = if isHeld then HELD_RIM else IDLE_RIM
		slot.rim.Thickness = if isHeld then 4 else 2
		local _, _, mutation = GarageConfig.parseCarKey(id)
		local icon = WeatherConfig.mutationIcon(mutation)
		slot.glyph.Image = if icon then UIAssets.url(icon) else ""
		slot.glyph.Visible = icon ~= nil
		--[[ NOT DURING A RUN (2026-10-07). The bar is hidden while racing, and a bank awards its car
			mid-run — so this built a car picture for a hidden bar on the bank's own frame, which the
			first-bank freeze (`Modules/HitchProbe`) caught: a second-long stall with
			`CarViewport.set` in it. The picture is built when the run ends instead (`RaceEnd` re-runs
			this), behind the trip home, where nobody is watching the frame rate. ]]
		if slot.shown ~= id and not self._racing then
			slot.shown = id
			CarViewport.clear(slot.view)
			local body, paint, mutation = GarageConfig.parseCarKey(id)
			if body then
				CarViewport.set(slot.view, body, { paint = paint, mutation = mutation, aspect = 1 })
			end
		end
	end
	self:_fit()
	--- Pad first: the hint binds the inventory's Y off `_padLive` (`_syncMove`).
	self:_syncPad()
	self:_applyHint()
end

-- === On a controller (header, "On a controller") ===============================

--- In a seat, where L1 is nitro and the bar's buttons are not ours to take.
function CarryHotbarController._seated(self): boolean
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.SeatPart ~= nil
end

--- Bind the three buttons while the bar is up and you are on foot; unbind them otherwise.
function CarryHotbarController._syncPad(self)
	local live = self._gui ~= nil and self._gui.Enabled and not self._racing and not self:_seated()
	if live == self._padLive then
		return
	end
	self._padLive = live
	if not live then
		for _, entry in PAD do
			GamepadInput.unbind(entry.action)
		end
		GamepadInput.unbind(PAD_MOVE.action)
		return
	end
	GamepadInput.bind({
		actionName = PAD.Next.action,
		keyCode = PAD.Next.key,
		callback = function()
			self:_cycle(1)
		end,
		parent = self._bar,
		iconPosition = UDim2.new(1, 10, 0.5, 0),
		iconAnchor = Vector2.new(0, 0.5),
	})
	GamepadInput.bind({
		actionName = PAD.Prev.action,
		keyCode = PAD.Prev.key,
		callback = function()
			self:_cycle(-1)
		end,
		parent = self._bar,
		iconPosition = UDim2.new(0, -10, 0.5, 0),
		iconAnchor = Vector2.new(1, 0.5),
	})
	GamepadInput.bind({
		actionName = PAD.Backpack.action,
		keyCode = PAD.Backpack.key,
		callback = function()
			if not self:_modalUp() then
				self:_toggleInventory()
			end
		end,
		parent = self._backpackTile,
		iconPlacement = "top",
	})
end

--[[ Step the car in your hands along the bar: `step` 1 is the next slot, -1 the one before. Empty
	hands is the step before slot 1 and after the last, so the bumpers can also put a car away. ]]
function CarryHotbarController._cycle(self, step: number)
	if self._racing or self:_modalUp() then
		return
	end
	local ids = self:_ids()
	local count = math.min(#ids, CarryConfig.Hotbar.Slots)
	if count == 0 then
		return
	end
	local at = table.find(ids, Players.LocalPlayer:GetAttribute(CarryConfig.Attribute)) or 0
	if at > count then
		at = 0
	end
	local nextAt = (at + step) % (count + 1)
	if nextAt ~= 0 then
		self:_press(nextAt, true)
	elseif at ~= 0 then
		self:_press(at, true) -- the held car's own toggle puts it away
	end
end

--- Is the Cars Inventory up? Read off the page itself, the same way `DealershipController` asks.
function CarryHotbarController._inventoryOpen(self): boolean
	local UIController = Shard.get("UIController")
	local page = UIController and UIController.pages and UIController.pages[INVENTORY_PAGE]
	local ui = page and page.PageUI
	if ui and not self._pageWatched then
		--- Hooked the first time the page exists, so the caption follows it open and shut.
		self._pageWatched = true
		ui:GetPropertyChangedSignal("Visible"):Connect(function()
			self:_applyHint()
		end)
	end
	return ui ~= nil and ui.Visible == true
end

function CarryHotbarController._applyHint(self)
	local open = self:_inventoryOpen()
	local ids = self:_ids()
	if self._hint then
		--- Only with a car to move; with an empty bar the caption would describe nothing.
		self._hint.Visible = open and #ids > 0
		local text = CarryConfig.Hotbar.Text
		if GamepadInput.isGamepad() then
			self._hint.Text = if self:_heldId() then text.PadMoveHint else text.PadPickHint
		else
			self._hint.Text = text.MoveHint
		end
	end
	--- The backpack lights while its screen is up, the same language as the held car's rim.
	if self._backpackRim then
		self._backpackRim.Color = if open then HELD_RIM else IDLE_RIM
		self._backpackRim.Thickness = if open then 4 else 2
	end
	self:_syncMove(open)
end

--- The car in your hands, when it is one of the bar's (the only kind the move can take).
function CarryHotbarController._heldId(self): string?
	local held = Players.LocalPlayer:GetAttribute(CarryConfig.Attribute)
	if type(held) == "string" and table.find(self:_ids(), held) then
		return held
	end
	return nil
end

--[[ Y, while the Cars Inventory is open, moves the held car in (`PAD_MOVE`). Bound and unbound here
	because this is where the screen's open and shut and the held car's changes all already arrive. ]]
function CarryHotbarController._syncMove(self, open: boolean)
	local live = self._padLive and open and self:_heldId() ~= nil
	if not live then
		GamepadInput.unbind(PAD_MOVE.action)
		return
	end
	if GamepadInput.isBound(PAD_MOVE.action) then
		return
	end
	GamepadInput.bind({
		actionName = PAD_MOVE.action,
		keyCode = PAD_MOVE.key,
		callback = function()
			local held = self:_heldId()
			if held and not self._racing and not self:_modalUp() and self:_inventoryOpen() then
				Dispatcher:Publish("HotbarAction", "toInventory", held)
			end
		end,
		parent = self._hint,
		iconPlacement = "left",
	})
end

-- === Pressing ===============================================================

--[[ THE STRAY-PRESS CATCH (2026-09-30). Playtested twice: only a press on the car picture took, even
	after the whole tile got its own click target (`Hit`) and the bar was lifted over the tutorial —
	so something from ANOTHER screen is lying over the tile and swallowing the press before the engine
	routes it here. Rather than chase every screen that might, this checks the press's position
	against the tiles itself: a press inside a visible slot that `Hit` did NOT receive is acted on
	here, so the bar works whatever is layered over it.

	IT NEVER DOUBLES A PRESS: it waits a frame and stands down if `Hit` saw the press (`_hitAt`), in
	which case `Activated` is already on its way. And it stands down while a real modal is up — any
	enabled screen drawn above this one (`DISPLAY_ORDER`), which is the scrims, the reveal and the fade.

	It also LOGS ONCE what was on top, so the screen doing the swallowing can be found and fixed at the
	source; this catch can then go. ]]
function CarryHotbarController._catchStray(self, input: InputObject)
	local kind = input.UserInputType
	if not (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) or not self._gui or not self._gui.Enabled then
		return
	end
	--[[ COMPARED IN `input.Position`'s SPACE, which is the space `AbsolutePosition` is in, top bar
		excluded, even on this screen. It used to be `GetMouseLocation()` on the reading that a screen
		with `IgnoreGuiInset` reports full-window pixels. It does not: measured 2026-09-30, this ScreenGui's
		own `AbsolutePosition` is (0, -58), so every tile was compared 58px too high and PLAY, which
		stands just above the backpack tile, counted as a backpack press. One click opened the world
		screen AND the Cars Inventory over it, which read as PLAY not working. ]]
	local point = Vector2.new(input.Position.X, input.Position.Y)
	local low, size = self._bar.AbsolutePosition, self._bar.AbsoluteSize
	if point.X < low.X or point.X > low.X + size.X or point.Y < low.Y or point.Y > low.Y + size.Y then
		return
	end
	-- A swipe must stay with ScrollingFrame; the fallback cannot equip a car on touch-down.
	if kind == Enum.UserInputType.Touch and self._bar.ScrollingEnabled then
		return
	end
	local target = nil
	for _, tile in self._tiles do
		local button = tile.button
		local low, size = button.AbsolutePosition, button.AbsoluteSize
		if button.Visible and point.X >= low.X and point.Y >= low.Y and point.X <= low.X + size.X and point.Y <= low.Y + size.Y then
			target = tile
			break
		end
	end
	if not target then
		return
	end
	local pressedAt = os.clock()
	task.defer(function()
		task.wait() -- one frame, so `Hit`'s own InputBegan has had its turn
		if (self._hitAt or 0) >= pressedAt - 0.05 or self:_modalUp() then
			return
		end
		if not self._strayLogged then
			self._strayLogged = true
			local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
			local names = {}
			if playerGui then
				for _, gui in playerGui:GetGuiObjectsAtPosition(input.Position.X, input.Position.Y) do
					table.insert(names, gui:GetFullName())
					if #names >= 4 then
						break
					end
				end
			end
			warn(string.format("[CarryHotbar] A hotbar press was swallowed by another screen; handled it anyway. On top: %s", table.concat(names, " | ")))
		end
		target.press()
	end)
end

--[[ Is a screen drawn above the hotbar switched on? Those are the modals, and a press there is theirs.

	EXCEPT A NOTICE, which only sits above everything so it cannot be covered. The INVENTORY FULL
	banner is the one that bit (2026-10-15): drawn at 1101 and up for as long as the inventory is full,
	it read as a modal, so the bumpers and Select did nothing on a pad, the only way into the inventory
	gone exactly when the banner says to go and sell. A screen like that carries
	`CarryConfig.Hotbar.NoticeAttribute`. ]]
function CarryHotbarController._modalUp(self): boolean
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	for _, gui in (if playerGui then playerGui:GetChildren() else {}) do
		if gui:IsA("ScreenGui") and gui ~= self._gui and gui.Enabled and gui.DisplayOrder > DISPLAY_ORDER
			and gui:GetAttribute(CarryConfig.Hotbar.NoticeAttribute) ~= true then
			return true
		end
	end
	return false
end

--- A slot pressed, by click or digit. The header's two meanings; `digit` never moves a car.
function CarryHotbarController._press(self, index: number, digit: boolean?)
	local id = self:_ids()[index]
	if not id or self._racing then
		return
	end
	local action = if not digit and self:_inventoryOpen() then "toInventory" else "toggle"
	Dispatcher:Publish("HotbarAction", action, id)
end

CarryHotbarController:withRemoteEvents({
	{
		--- The race bracket, the one `CarryController` uses for the same reason. See the header.
		RaceStart = function()
			CarryHotbarController._racing = true
			CarryHotbarController:_apply()
		end,
		RaceEnd = function()
			CarryHotbarController._racing = false
			CarryHotbarController:_apply()
		end,
	},
})

CarryHotbarController:withLifecycle({
	init = function(self)
		self._racing = false
		self._radioUp = false
		self._pageWatched = false
		self._padLive = false
		self._tiles = {}
	end,

	start = function(self)
		if not (CarryConfig.Enabled and CarryConfig.Hotbar.Enabled) then
			return
		end
		self:_build()
		for _, attribute in { CarryConfig.Hotbar.Attribute, CarryConfig.Attribute } do
			Players.LocalPlayer:GetAttributeChangedSignal(attribute):Connect(function()
				self:_apply()
			end)
		end
		--- Behind a menu. See the header and `_menuUp`.
		for _, event in { "PageOpened", "PageClosed" } do
			Dispatcher:Subscribe(event, function()
				self:_apply()
			end)
		end
		Dispatcher:Subscribe(RadioConfig.PanelEvent, function(open: boolean)
			self._radioUp = open == true
			self:_apply()
		end)
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
			self:_fit()
			--- The caption says click or Y depending on the device. See `Hotbar.Text`.
			self:_applyHint()
		end)
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			self:_fit()
		end)
		--- Other screens switch the bar off too (the NEW BEST cutscene hides the HUD it covers), and
		--- the buttons go with it, so they follow `Enabled` itself rather than only `_apply`.
		self._gui:GetPropertyChangedSignal("Enabled"):Connect(function()
			self:_syncPad()
		end)
		--- Sitting down hands the bumpers back to the seat; standing up takes them again.
		local function watchSeat(character: Model)
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid and humanoid:IsA("Humanoid") then
				humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
					self:_syncPad()
				end)
			end
			self:_syncPad()
		end
		if Players.LocalPlayer.Character then
			task.spawn(watchSeat, Players.LocalPlayer.Character)
		end
		Players.LocalPlayer.CharacterAdded:Connect(watchSeat)
		--- `gameProcessed` keeps a digit typed into chat or a rename box from grabbing a car.
		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			--- Before the `gameProcessed` gate on purpose: a swallowed press arrives processed.
			self:_catchStray(input)
			if gameProcessed then
				return
			end
			--- Tile 1 is the backpack; tile n > 1 is car slot n - 1. Backquote is the backpack too.
			local tile = table.find(DIGITS, input.KeyCode)
			if tile == 1 or table.find(CarryConfig.Hotbar.BackpackKeys, input.KeyCode) then
				self:_toggleInventory()
			elseif tile and tile - 1 <= CarryConfig.Hotbar.Slots and self._gui.Enabled then
				--- Not while the bar is down behind a menu: a car changing hands off screen.
				self:_press(tile - 1, true)
			end
		end)
		self:_apply()
	end,
})

return CarryHotbarController
