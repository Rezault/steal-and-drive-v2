--[[
	GamepadInput  (shared, client-side in practice)
	-----------------------------------------------
	One button on a controller, and the little glyph on screen that says so.

	Two jobs, and they are deliberately the same call. `bind` takes a KeyCode, a callback and
	(optionally) the GuiObject the action belongs to, binds the action through
	ContextActionService, and hangs a badge with that button's glyph off the GuiObject. Unbinding
	takes the badge away with it. The point is that there is no way to ship a binding nobody can
	discover, or a glyph for a binding that is no longer live — the two cannot drift because they
	are one object.

	Ported from Epic Sword Tycoon, where it was written and then debugged on real hardware. The
	parts that look fussy are the parts that were wrong the first time:

	  • `isGamepad` vs `isGamepadActive`. `UserInputService.PreferredInput` is the stable signal and
	    is what icon visibility follows — it should not flicker every time someone brushes the
	    mouse. But it lags the very press that invoked your callback (it flips after input
	    processing), so inside a binding's callback that followed mouse use it still reads
	    KeyboardAndMouse. Anything reacting to a press — seeding a selection, say — has to ask
	    `isGamepadActive`, which accepts the last physical input type too.

	  • THE GLYPH IS NOT ALWAYS A CIRCLE. The shoulder and trigger art is a pill and the menu chips
	    are rounded rectangles; a circular badge behind those reads as a mistake. Those keycodes get
	    the bare white line-art instead (`BADGELESS_KEYCODES`).

	  • THE ART FOLLOWS THE CONTROLLER. `GetImageForKeyCode` returns PlayStation art on a DualSense
	    and Xbox art on an Xbox pad, on its own — so `ButtonA` is drawn as a cross for a player
	    holding a PlayStation controller without us knowing anything about it. Which is also why
	    every icon re-reads its image on a device change rather than caching it at creation.

	  • SIZES ARE REFERENCE PIXELS AT 1080p, not raw pixels and not a fraction of the parent.
	    Parent-relative scaling made a badge on a small button microscopic and one on a big button
	    enormous, when the whole point is that every glyph reads the same size. So the authored
	    number is what it looks like on a 1080p-tall screen and the live viewport scales it.

	`GamepadConfig.Enabled = false` makes `isGamepad` answer false everywhere, which hides every
	badge this module has drawn. The bindings stay live — a controller that is plugged in still
	works, it just stops being advertised.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GamepadConfig = require(ReplicatedStorage.shared.Configs.GamepadConfig)

local GamepadInput = {}

export type IconPlacement = "top" | "bottom" | "left" | "right"

-- Where a badge sits relative to the thing it presses. Every one of them hangs OUTSIDE the parent's
-- bounds, which is why `createIcon` unclips the parent — see the note there.
local ICON_PLACEMENTS: { [IconPlacement]: { position: UDim2, anchor: Vector2 } } = {
	top = { position = UDim2.new(0.5, 0, -0.1, 0), anchor = Vector2.new(0.5, 1) },
	bottom = { position = UDim2.new(0.5, 0, 1.1, 0), anchor = Vector2.new(0.5, 0) },
	left = { position = UDim2.new(-0.1, 0, 0.5, 0), anchor = Vector2.new(1, 0.5) },
	right = { position = UDim2.new(1.1, 0, 0.5, 0), anchor = Vector2.new(0, 0.5) },
}

-- Keycodes whose stock glyphs aren't circular (shoulder/trigger pills, menu chips). They skip the
-- badge and render as bare white line-art; a circle behind an odd-shaped glyph reads wrong.
local BADGELESS_KEYCODES: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.ButtonL1] = true,
	[Enum.KeyCode.ButtonR1] = true,
	[Enum.KeyCode.ButtonL2] = true,
	[Enum.KeyCode.ButtonR2] = true,
	[Enum.KeyCode.ButtonSelect] = true,
	[Enum.KeyCode.ButtonStart] = true,
}

-- Press feedback: the badge squashes while the button is held and springs back on release (Back
-- overshoots slightly for the pop). Restrained on purpose — it is a 36px hint, not an event.
local PRESS_SCALE = 0.8
local PRESS_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- See the header: authored sizes are "how big this reads on a 1080p-tall screen". Bounds keep a
-- badge legible on a phone-sized window and stop it dominating a 4K one.
local REF_HEIGHT = 1080
local SCALE_MIN = 0.55
local SCALE_MAX = 1.6

-- Live badges -> the reference size they were authored at, re-applied whenever the viewport moves.
local activeIcons: { [ImageLabel]: number } = {}

local function viewportFactor(): number
	local camera = workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else 0
	if height <= 0 then
		return 1
	end
	return math.clamp(height / REF_HEIGHT, SCALE_MIN, SCALE_MAX)
end

local function applyIconSize(icon: ImageLabel, refSize: number)
	local factor = viewportFactor()
	local pixels = math.round(refSize * factor)
	icon.Size = UDim2.fromOffset(pixels, pixels)
	-- The stroke is part of the badge's footprint, so it scales with the same factor.
	local stroke = icon:FindFirstChildWhichIsA("UIStroke")
	if stroke then
		stroke.Thickness = math.max(1, math.round(GamepadConfig.Icon.StrokeThickness * factor))
	end
end

type GamepadBinding = {
	actionName: string,
	keyCode: Enum.KeyCode,
	callback: () -> (),
	icon: ImageLabel?,
	parent: GuiObject?,
}

local activeBindings: { [string]: GamepadBinding } = {}

--[[ Is a controller the player's input device? The STABLE answer, and the one badge visibility
	follows: it does not flip because a hand brushed the mouse. ]]
function GamepadInput.isGamepad(): boolean
	if not GamepadConfig.Enabled then
		return false
	end
	return UserInputService.PreferredInput == Enum.PreferredInput.Gamepad
end

--[[ Is a controller driving RIGHT NOW? The IMMEDIATE answer, for reacting to a press.

	`PreferredInput` flips after input processing, so inside the callback of a binding that a
	gamepad just invoked it can still say KeyboardAndMouse. Anything that reacts to the press
	itself — seeding `GuiService.SelectedObject`, most of all — has to ask this instead, which
	accepts the last physical input type as well. Keep `isGamepad` for what is on screen. ]]
function GamepadInput.isGamepadActive(): boolean
	if GamepadInput.isGamepad() then
		return true
	end
	if not GamepadConfig.Enabled then
		return false
	end
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

-- The stock glyph for a button, in the art of the controller actually in the player's hands.
function GamepadInput.getButtonImage(keyCode: Enum.KeyCode): string
	return UserInputService:GetImageForKeyCode(keyCode)
end

--[[ The controller half of a mixed key list, or nil if it has none.

	Our verbs are configured as "the keys that do this" — `StealConfig.Prompt.Keys` is `{ E, ButtonX }`
	— which is the right shape for binding and the wrong shape for DRAWING, where exactly one of them
	is the answer to "what do I press". Rather than have every config list its keyboard and gamepad
	key twice, the gamepad one is recognised by its name: every controller KeyCode is a Button*,
	DPad*, Thumbstick* or the two sticks' clicks, none of which any keyboard key is called. ]]
function GamepadInput.gamepadKeyIn(keys: { Enum.KeyCode }): Enum.KeyCode?
	for _, keyCode in keys do
		local name = keyCode.Name
		if name:sub(1, 6) == "Button" or name:sub(1, 4) == "DPad" or name:sub(1, 10) == "Thumbstick" then
			return keyCode
		end
	end
	return nil
end

function GamepadInput.createIcon(
	parent: GuiObject,
	keyCode: Enum.KeyCode,
	placement: IconPlacement?,
	position: UDim2?,
	size: number?, -- reference pixels at 1080p (see the header); omit for the standard size
	color: Color3?,
	anchor: Vector2?
): ImageLabel
	local preset = ICON_PLACEMENTS[placement or "top"]

	--[[ EVERY PLACEMENT HANGS THE BADGE OUTSIDE THE BUTTON, so a parent that clips its descendants
		renders nothing at all and reads as "the icon never appeared". Our authored buttons carry
		their decor in-bounds, so unclipping them is invisible — but it is a real property write on
		someone else's instance, and this is the one place it happens. ]]
	if parent.ClipsDescendants then
		parent.ClipsDescendants = false
	end

	-- The ImageLabel's own background IS the badge — fill, corner and stroke on the root, no wrapper
	-- frame. Non-circular glyphs skip it and stay bare line-art.
	local badged = not BADGELESS_KEYCODES[keyCode]

	local icon = Instance.new("ImageLabel")
	icon.Name = "GamepadIcon"
	icon.BackgroundColor3 = GamepadConfig.Icon.Background
	icon.BackgroundTransparency = if badged then 0 else 1
	icon.BorderSizePixel = 0
	icon.AnchorPoint = anchor or preset.anchor
	icon.Position = position or preset.position
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = GamepadInput.getButtonImage(keyCode)
	icon.ImageColor3 = color or Color3.new(1, 1, 1)
	icon.ZIndex = 10 -- over the button art it is describing, never behind it
	icon.Visible = GamepadInput.isGamepad()

	if badged then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = icon

		local stroke = Instance.new("UIStroke")
		stroke.Color = GamepadConfig.Icon.Stroke
		stroke.Thickness = GamepadConfig.Icon.StrokeThickness
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = icon
	end

	local pressScale = Instance.new("UIScale")
	pressScale.Name = "PressScale"
	pressScale.Parent = icon

	-- Sized after the stroke exists so one viewport factor covers both, and registered so a window
	-- resize re-applies. `unbind` destroys the icon, which deregisters it.
	local refSize = size or GamepadConfig.Icon.Size
	applyIconSize(icon, refSize)
	activeIcons[icon] = refSize
	icon.Destroying:Once(function()
		activeIcons[icon] = nil
	end)

	icon.Parent = parent
	return icon
end

-- Squash/spring the badge. Playing a new tween on the same property cancels the in-flight one, so
-- rapid press/release stays smooth.
local function animatePress(icon: ImageLabel?, pressed: boolean)
	if not icon then
		return
	end
	local pressScale = icon:FindFirstChild("PressScale")
	if not (pressScale and pressScale:IsA("UIScale")) then
		return
	end
	TweenService:Create(pressScale, if pressed then PRESS_TWEEN else RELEASE_TWEEN, {
		Scale = if pressed then PRESS_SCALE else 1,
	}):Play()
end

--[[ Bind a button, and draw it.

	`parent` is what the badge hangs off and is optional: a binding with no parent is a silent
	shortcut. `result` decides what happens to the press underneath — Sink by default, because a
	button that does something here should not also do something down there. Pass
	`Enum.ContextActionResult.Pass` for a binding that must not starve the engine's own handling of
	the same key (the UI focus key does exactly that).

	`extraKeys` are bound to the same action but never drawn, for a verb that answers to more than
	one button: the DPad opens the UI on any of its four directions, and there is no glyph for "the
	DPad" — so `keyCode` is the one the badge shows and these come along quietly. ]]
function GamepadInput.bind(config: {
	actionName: string,
	keyCode: Enum.KeyCode,
	extraKeys: { Enum.KeyCode }?,
	callback: () -> (),
	parent: GuiObject?,
	iconPlacement: IconPlacement?,
	iconPosition: UDim2?,
	-- Reference pixels at 1080p, viewport-normalised. Omit for the standard size; badges are meant
	-- to read identically everywhere.
	iconSize: number?,
	iconColor: Color3?,
	iconAnchor: Vector2?,
	-- ContextActionPriority value (default High). Bind lower when another context's binding of the
	-- same button should win if both are ever live at once.
	priority: number?,
	result: Enum.ContextActionResult?,
}): ImageLabel?
	GamepadInput.unbind(config.actionName)

	local icon: ImageLabel? = nil
	if config.parent then
		icon = GamepadInput.createIcon(
			config.parent,
			config.keyCode,
			config.iconPlacement,
			config.iconPosition,
			config.iconSize,
			config.iconColor,
			config.iconAnchor
		)
	end

	activeBindings[config.actionName] = {
		actionName = config.actionName,
		keyCode = config.keyCode,
		callback = config.callback,
		icon = icon,
		parent = config.parent,
	}

	local onBegin = config.result or Enum.ContextActionResult.Sink

	-- Deduped, because the drawn key is usually one of the extras as well (the DPad badge shows Up
	-- and Up is also one of the four it binds), and a key handed to CAS twice is a key bound twice.
	local keys = { config.keyCode }
	for _, extra in config.extraKeys or {} do
		if extra ~= config.keyCode then
			table.insert(keys, extra)
		end
	end

	ContextActionService:BindActionAtPriority(config.actionName, function(_actionName, inputState)
		if inputState == Enum.UserInputState.Begin then
			animatePress(icon, true)
			config.callback()
			return onBegin
		end
		if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			animatePress(icon, false)
		end
		return Enum.ContextActionResult.Pass
	end, false, config.priority or Enum.ContextActionPriority.High.Value, table.unpack(keys))

	return icon
end

function GamepadInput.unbind(actionName: string)
	local binding = activeBindings[actionName]
	if not binding then
		return
	end

	ContextActionService:UnbindAction(actionName)

	if binding.icon and binding.icon.Parent then
		binding.icon:Destroy()
	end

	activeBindings[actionName] = nil
end

function GamepadInput.unbindAll()
	for actionName in activeBindings do
		GamepadInput.unbind(actionName)
	end
end

function GamepadInput.isBound(actionName: string): boolean
	return activeBindings[actionName] ~= nil
end

function GamepadInput.getIcon(actionName: string): ImageLabel?
	local binding = activeBindings[actionName]
	return binding and binding.icon
end

--[[ "A SCREEN OF MINE OWNS THE CONTROLLER", said by name (`GamepadConfig.ModalAttribute`).

	The attribute is one boolean and nine screens raise it. Each used to write it straight, so the
	first one to close cleared it for everybody: Welcome Back shutting while a buyer's offer was up
	handed the offer's B back to the rail underneath it. Now each screen says which it is, and the
	attribute is true while ANY of them is up. `owner` is the screen's own name; raising twice or
	clearing a claim that was never made are both no-ops. ]]
local modalOwners: { [string]: true } = {}

function GamepadInput.setModal(owner: string, on: boolean)
	modalOwners[owner] = if on then true else nil
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		playerGui:SetAttribute(GamepadConfig.ModalAttribute, if next(modalOwners) ~= nil then true else nil)
	end
end

-- Re-read every live badge: the image (the player swapped controller brands) and whether it should
-- be on screen at all (they put the pad down and took the mouse).
function GamepadInput.refreshIcons()
	local isGamepad = GamepadInput.isGamepad()
	for _, binding in activeBindings do
		if binding.icon then
			binding.icon.Image = GamepadInput.getButtonImage(binding.keyCode)
			binding.icon.Visible = isGamepad and (binding.parent == nil or binding.parent.Visible)
		end
	end
end

--[[ Call `fn(isGamepad)` now and again every time the player's device changes.

	The device change matters to more than badges — the steal prompt draws a letter or a glyph off
	the same answer — so it is a subscription rather than something each caller re-derives from the
	property signal. Returns the connection for a caller that has a lifetime; most don't. ]]
function GamepadInput.observePreferred(fn: (boolean) -> ()): RBXScriptConnection
	fn(GamepadInput.isGamepad())
	return UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
		fn(GamepadInput.isGamepad())
	end)
end

UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
	GamepadInput.refreshIcons()
end)

-- Keep badges tracking the viewport (window resizes, device emulation) so they hold their
-- proportion against the scale-authored UI. No-ops server-side: no CurrentCamera means factor 1.
local viewportConnection: RBXScriptConnection? = nil
local function watchViewport()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		for icon, refSize in activeIcons do
			applyIconSize(icon, refSize)
		end
	end)
end
watchViewport()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchViewport)

return GamepadInput
