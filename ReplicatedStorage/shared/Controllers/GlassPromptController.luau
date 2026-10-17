--[[
	GlassPromptController  (client)
	-------------------------------
	Draws every `ProximityPrompt` tagged `GlassPromptConfig.Tag` as a frosted glass card, one card per
	PART, one row per prompt on it. `GlassPromptConfig` has the look and the contract with the server.

	=== THE INPUT IS STILL THE ENGINE'S ======================================================

	`Style = Custom` only takes the DRAWING away. The key, the pad button, the hold timer, the range
	check and the `Triggered` that reaches the server all stay the prompt's, exactly as for
	`CarDealController`'s buy pill. What Custom also takes away is the touch tap target, so each row
	is a button that drives `InputHoldBegin`/`InputHoldEnd` (Roblox's own reference pattern). It
	answers a mouse click too, which costs nothing and is what a desktop player tries first.

	=== FOCUS: WHICH PART'S CARD IS UP =======================================================

	Ten times a second this picks the nearest tagged part the local player may use, within its
	prompts' reach, and switches every other tagged prompt's `Enabled` off LOCALLY. That is the whole
	fix for the engine's one-prompt-per-key draw: with only one part's prompts enabled there is only
	one card to draw, and the key you press is the key on the card you are reading. The server never
	writes `Enabled` after creating a prompt, so these local writes stand.

	=== WHAT IS ON SCREEN IS WHAT THE ENGINE SHOWED ==========================================

	Rows come from `PromptShown`/`PromptHidden`, not from our own distance test, so a row is drawn
	exactly when its key would work: out of range, a drive switching `ProximityPromptService` off, or
	the server hiding a row (`Attributes.Hidden`) all take it off the card by the same path.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local GlassPromptConfig = require(ReplicatedStorage.shared.Configs.GlassPromptConfig)
local GamepadInput = require(ReplicatedStorage.shared.Modules.GamepadInput)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)

local GlassPromptController = Shard.new("GlassPromptController")

local SIZE = GlassPromptConfig.Size
local COLORS = GlassPromptConfig.Colors
local FONTS = GlassPromptConfig.Font
local MOTION = GlassPromptConfig.Motion
local ATTRS = GlassPromptConfig.Attributes

type Device = "Keyboard" | "Gamepad" | "Touch"

type Row = {
	prompt: ProximityPrompt,
	--- Drawn from the kit template (`GlassPromptConfig.KitStyle`), not the glass. `alt` is the
	--- orange face, `slot` the card slot it sits in, `titleBox` the caption's authored box.
	kit: boolean,
	alt: boolean,
	slot: number,
	titleBox: { UDim2 }?,
	frame: Frame,
	fill: Frame,
	gradient: UIGradient,
	lip: Frame?,
	key: Frame,
	keyScale: UIScale,
	keyText: TextLabel,
	keyImage: ImageLabel,
	label: TextLabel,
	hint: TextLabel,
	button: GuiButton,
	trove: any,
	progress: NumberValue,
	alpha: NumberValue,
	tween: Tween?,
	down: boolean,
}

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function frame(name: string, parent: Instance, color: Color3, transparency: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function label(name: string, parent: Instance, font: Font, size: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.FontFace = font
	t.TextSize = size
	t.TextColor3 = COLORS.Text
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Parent = parent
	return t
end

--- The card's place in the world: a part's position, or an attachment's.
local function anchorPosition(anchor: Instance?): Vector3?
	if anchor and anchor:IsA("BasePart") then
		return anchor.Position
	elseif anchor and anchor:IsA("Attachment") then
		return anchor.WorldPosition
	end
	return nil
end

--- The screen's share of the 1080p reference, clamped (`GlassPromptConfig.Size`).
local function viewScale(): number
	local camera = workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else SIZE.Reference
	return math.clamp(height / SIZE.Reference, SIZE.MinScale, SIZE.MaxScale)
end

--- How lit a row's fill is: the glass's blue, or white light over a kit face.
local function fillAlpha(row): number
	return if row.kit then GlassPromptConfig.Kit.FillTransparency else COLORS.FillTransparency
end

local function device(): Device
	if UserInputService.PreferredInput == Enum.PreferredInput.Touch then
		return "Touch"
	elseif GamepadInput.isGamepad() then
		return "Gamepad"
	end
	return "Keyboard"
end

--[[ Paint a row's fill: the left `progress` of it lit at transparency `alpha`, the rest clear. A
	hard-edged gradient rather than a frame growing in width, because a narrow frame with a UICorner
	draws as a pill, not as the left end of a rounded row. ]]
local function paintFill(row: Row)
	local p, a = row.progress.Value, row.alpha.Value
	if p <= 0 or a >= 1 then
		row.fill.Visible = false
		return
	end
	row.fill.Visible = true
	if p >= 0.995 then
		row.gradient.Transparency = NumberSequence.new(a)
		return
	end
	row.gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, a),
		NumberSequenceKeypoint.new(p, a),
		NumberSequenceKeypoint.new(math.min(p + 0.004, 0.999), 1),
		NumberSequenceKeypoint.new(1, 1),
	})
end

-- === The card ===============================================================

function GlassPromptController._buildCard(self)
	local gui = Instance.new("BillboardGui")
	gui.Name = "GlassPrompt"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Active = true
	gui.Enabled = false
	gui.StudsOffsetWorldSpace = GlassPromptConfig.Offset
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ClipsDescendants = false
	--- In PlayerGui with an Adornee, never in Workspace: a workspace billboard takes no input.
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local root = frame("Root", gui, COLORS.Tint, 1)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	local scale = Instance.new("UIScale")
	scale.Parent = root

	--- Two soft layers make a shadow without an image: wider and fainter outside, tighter inside.
	local shadowOuter = frame("ShadowOuter", root, COLORS.Shadow, 1 - (1 - COLORS.ShadowTransparency) * 0.5)
	shadowOuter.ZIndex = 1
	corner(shadowOuter, SIZE.CornerRadius + 4)
	local shadowInner = frame("ShadowInner", root, COLORS.Shadow, COLORS.ShadowTransparency)
	shadowInner.ZIndex = 2
	corner(shadowInner, SIZE.CornerRadius + 1)

	local pane = frame("Pane", root, COLORS.Tint, COLORS.TintTransparency)
	pane.Size = UDim2.fromScale(1, 1)
	pane.ZIndex = 3
	corner(pane, SIZE.CornerRadius)
	--- The pane is a touch lighter at the top: a light from above, which is most of what reads as glass.
	local depth = Instance.new("UIGradient")
	depth.Rotation = 90
	depth.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(205, 212, 228))
	depth.Parent = pane

	local sheen = frame("Sheen", pane, Color3.new(1, 1, 1), 0)
	sheen.Size = UDim2.fromScale(1, 0.5)
	corner(sheen, SIZE.CornerRadius)
	local sheenFade = Instance.new("UIGradient")
	sheenFade.Rotation = 90
	sheenFade.Transparency = NumberSequence.new(COLORS.SheenTransparency, 1)
	sheenFade.Parent = sheen

	local rim = Instance.new("UIStroke")
	rim.Color = COLORS.Rim
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = pane
	local rimFade = Instance.new("UIGradient")
	rimFade.Rotation = 90
	rimFade.Transparency = NumberSequence.new(COLORS.RimTop, COLORS.RimBottom)
	rimFade.Parent = rim

	local header = label("Header", pane, FONTS.Header, SIZE.HeaderText)
	header.TextTransparency = COLORS.TextMuted

	self._card = {
		gui = gui,
		root = root,
		scale = scale,
		shadowOuter = shadowOuter,
		shadowInner = shadowInner,
		pane = pane,
		rim = rim,
		header = header,
	}
	self._pop = 1
	self._shownCard = false
end

--[[ Lay the card out for `n` rows at the reference size, and size the billboard to match the
	screen. Positions are written by hand rather than by a UIListLayout because the billboard's own
	size has to be known in the same breath. ]]
function GlassPromptController._layout(self, rows: { Row }, headerText: string)
	local card = self._card
	local s = viewScale()
	local hasHeader = headerText ~= ""
	local top = SIZE.Padding + (if hasHeader then SIZE.HeaderHeight else 0)
	local height = top + #rows * SIZE.RowHeight + math.max(#rows - 1, 0) * SIZE.RowGap + SIZE.Padding
	local width = SIZE.Width

	card.gui.Size = UDim2.fromOffset(width * s, height * s)
	card.root.Size = UDim2.fromOffset(width, height)
	card.scale.Scale = s * self._pop
	--- A stroke is drawn in screen pixels whatever its UIScale says, so it is scaled by hand.
	card.rim.Thickness = math.max(1, 1.2 * s)
	card.shadowOuter.Size = UDim2.new(1, 8, 1, 8)
	card.shadowOuter.Position = UDim2.fromOffset(-4, 1)
	card.shadowInner.Size = UDim2.new(1, 2, 1, 2)
	card.shadowInner.Position = UDim2.fromOffset(-1, 2)

	card.header.Visible = hasHeader
	card.header.Text = string.upper(headerText)
	card.header.Position = UDim2.fromOffset(SIZE.Padding + 4, SIZE.Padding - 1)
	card.header.Size = UDim2.fromOffset(width - SIZE.Padding * 2 - 8, SIZE.HeaderHeight)

	for i, row in rows do
		row.frame.Position = UDim2.fromOffset(SIZE.Padding, top + (i - 1) * (SIZE.RowHeight + SIZE.RowGap))
		row.frame.Size = UDim2.fromOffset(width - SIZE.Padding * 2, SIZE.RowHeight)
	end
end

function GlassPromptController._setPop(self, value: number)
	self._pop = value
	if self._card then
		local look = if self._mode == "kit" then GlassPromptConfig.Kit.Scale else 1
		self._card.scale.Scale = viewScale() * look * value
	end
end

function GlassPromptController._showCard(self)
	if self._shownCard then
		return
	end
	self._shownCard = true
	self._popToken += 1
	local card = self._card
	card.gui.Enabled = true
	local pop = Instance.new("NumberValue")
	pop.Value = MOTION.PopFrom
	pop.Changed:Connect(function(v)
		self:_setPop(v)
	end)
	self:_setPop(MOTION.PopFrom)
	local tween = TweenService:Create(pop, TweenInfo.new(MOTION.PopIn, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Value = 1 })
	tween.Completed:Once(function()
		pop:Destroy()
	end)
	tween:Play()
end

function GlassPromptController._hideCard(self)
	if not self._shownCard then
		return
	end
	self._shownCard = false
	self._popToken += 1
	local token = self._popToken
	local pop = Instance.new("NumberValue")
	pop.Value = self._pop
	pop.Changed:Connect(function(v)
		if self._popToken == token then
			self:_setPop(v)
		end
	end)
	local tween = TweenService:Create(pop, TweenInfo.new(MOTION.PopOut, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = MOTION.PopFrom })
	tween.Completed:Once(function()
		pop:Destroy()
		if self._popToken == token then
			self._card.gui.Enabled = false
		end
	end)
	tween:Play()
end

-- === Rows ===================================================================

function GlassPromptController._buildRow(self, prompt: ProximityPrompt): Row
	local trove = Trove.new()
	local track = frame("Row", self._card.pane, COLORS.Row, COLORS.RowTransparency)
	corner(track, SIZE.RowCorner)
	trove:Add(track)

	local fill = frame("Fill", track, COLORS.Fill, 0)
	fill.Size = UDim2.fromScale(1, 1)
	fill.Visible = false
	corner(fill, SIZE.RowCorner)
	local gradient = Instance.new("UIGradient")
	gradient.Parent = fill

	local keyY = (SIZE.RowHeight - SIZE.Key) / 2
	local lip = frame("Lip", track, COLORS.KeyLip, 0)
	lip.Size = UDim2.fromOffset(SIZE.Key, SIZE.Key)
	lip.Position = UDim2.fromOffset(6, keyY + SIZE.KeyDepth)
	corner(lip, SIZE.KeyCorner)

	local key = frame("Key", track, COLORS.Key, 0)
	key.Size = UDim2.fromOffset(SIZE.Key, SIZE.Key)
	key.AnchorPoint = Vector2.new(0.5, 0.5)
	key.Position = UDim2.fromOffset(6 + SIZE.Key / 2, keyY + SIZE.Key / 2)
	corner(key, SIZE.KeyCorner)
	local keyScale = Instance.new("UIScale")
	keyScale.Parent = key
	local keyText = label("Letter", key, FONTS.Key, math.floor(SIZE.Key * 0.6))
	keyText.Size = UDim2.fromScale(1, 1)
	keyText.TextXAlignment = Enum.TextXAlignment.Center
	keyText.TextColor3 = COLORS.KeyText
	keyText.TextTruncate = Enum.TextTruncate.None
	local keyImage = Instance.new("ImageLabel")
	keyImage.Name = "Glyph"
	keyImage.BackgroundTransparency = 1
	keyImage.AnchorPoint = Vector2.new(0.5, 0.5)
	keyImage.Position = UDim2.fromScale(0.5, 0.5)
	keyImage.Size = UDim2.fromScale(1.15, 1.15)
	keyImage.Parent = key

	local action = label("Action", track, FONTS.Action, SIZE.ActionText)
	local hint = label("Hint", track, FONTS.Header, SIZE.HintText)
	hint.Text = GlassPromptConfig.Text.Hold
	hint.TextTransparency = COLORS.TextMuted
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.Size = UDim2.fromOffset(40, SIZE.RowHeight)

	local button = Instance.new("TextButton")
	button.Name = "Press"
	button.Text = ""
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Size = UDim2.fromScale(1, 1)
	button.ZIndex = 5
	button.Parent = track

	local progress = Instance.new("NumberValue")
	local alpha = Instance.new("NumberValue")
	alpha.Value = COLORS.FillTransparency
	trove:Add(progress)
	trove:Add(alpha)

	local row: Row = {
		prompt = prompt,
		kit = false,
		alt = false,
		slot = 0,
		titleBox = nil,
		frame = track,
		fill = fill,
		gradient = gradient,
		lip = lip,
		key = key,
		keyScale = keyScale,
		keyText = keyText,
		keyImage = keyImage,
		label = action,
		hint = hint,
		button = button,
		trove = trove,
		progress = progress,
		alpha = alpha,
		tween = nil,
		down = false,
	}
	return self:_finishRow(row)
end

--[[ Everything a row does, whichever look drew it: the hold fill, the touch and mouse press, the
	key dip and the flash. The two builders only make the pieces. ]]
function GlassPromptController._finishRow(self, row: Row): Row
	local prompt, trove, button = row.prompt, row.trove, row.button
	trove:Add(row.progress.Changed:Connect(function()
		paintFill(row)
	end))
	trove:Add(row.alpha.Changed:Connect(function()
		paintFill(row)
	end))

	--- Touch and mouse: the row is the button. Began on the row, ended anywhere, like a key.
	trove:Add(button.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
			row.down = true
			prompt:InputHoldBegin()
		end
	end))
	trove:Add(button.InputEnded:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if (kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1) and row.down then
			row.down = false
			prompt:InputHoldEnd()
		end
	end))

	trove:Add(prompt.PromptButtonHoldBegan:Connect(function()
		self:_holdBegan(row)
	end))
	trove:Add(prompt.PromptButtonHoldEnded:Connect(function()
		self:_holdEnded(row)
	end))
	trove:Add(prompt.Triggered:Connect(function()
		self:_fired(row)
	end))
	trove:Add(function()
		if row.down then
			row.down = false
			pcall(function()
				prompt:InputHoldEnd()
			end)
		end
		if row.tween then
			row.tween:Cancel()
		end
	end)

	self:_dressRow(row)
	return row
end

--- Text, key and hint, off the prompt as it is now and the device in the player's hands.
function GlassPromptController._dressRow(self, row: Row)
	if row.kit then
		self:_dressKitRow(row)
		return
	end
	local prompt = row.prompt
	local kind = device()
	local left = 6 + SIZE.Key + 10
	local hold = prompt.HoldDuration > 0

	row.frame.BackgroundTransparency = if kind == "Touch" then COLORS.RowTouchTransparency else COLORS.RowTransparency
	row.key.Visible = kind ~= "Touch"
	if row.lip then
		row.lip.Visible = kind == "Keyboard"
	end
	if kind == "Touch" then
		left = 14
	elseif kind == "Gamepad" then
		local image = UserInputService:GetImageForKeyCode(prompt.GamepadKeyCode)
		row.key.BackgroundTransparency = 1
		row.keyImage.Image = image or ""
		row.keyImage.Visible = true
		row.keyText.Visible = false
	else
		local text = UserInputService:GetStringForKeyCode(prompt.KeyboardKeyCode)
		row.key.BackgroundTransparency = 0
		row.keyImage.Visible = false
		row.keyText.Visible = true
		--- `GetStringForKeyCode` answers for the player's own layout, so AZERTY gets its own letter.
		row.keyText.Text = if text and text ~= "" then string.upper(text) else prompt.KeyboardKeyCode.Name
	end

	local rowWidth = SIZE.Width - SIZE.Padding * 2
	local hintWidth = if hold then 46 else 0
	row.label.Text = prompt.ActionText
	row.label.Position = UDim2.fromOffset(left, 0)
	row.label.Size = UDim2.fromOffset(rowWidth - left - hintWidth - 8, SIZE.RowHeight)
	row.hint.Visible = hold
	row.hint.Position = UDim2.fromOffset(rowWidth - 40 - 10, 0)
end

function GlassPromptController._holdBegan(self, row: Row)
	if row.tween then
		row.tween:Cancel()
	end
	row.alpha.Value = fillAlpha(row)
	row.progress.Value = 0
	TweenService:Create(row.keyScale, TweenInfo.new(0.06), { Scale = MOTION.PressScale }):Play()
	row.tween = TweenService:Create(
		row.progress,
		TweenInfo.new(math.max(row.prompt.HoldDuration, 0.01), Enum.EasingStyle.Linear),
		{ Value = 1 }
	)
	row.tween:Play()
end

function GlassPromptController._holdEnded(self, row: Row)
	TweenService:Create(row.keyScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	--- A completed hold flashes (`_fired`); a hold let go early drains back, quicker than it filled.
	if row.progress.Value < 1 then
		if row.tween then
			row.tween:Cancel()
		end
		row.tween = TweenService:Create(row.progress, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Value = 0 })
		row.tween:Play()
	end
end

--- The prompt fired: the whole row lights and fades, and a tapped key dips and comes back.
function GlassPromptController._fired(self, row: Row)
	if row.tween then
		row.tween:Cancel()
	end
	row.progress.Value = 1
	row.alpha.Value = fillAlpha(row)
	row.tween = TweenService:Create(row.alpha, TweenInfo.new(MOTION.Flash, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 1 })
	row.tween:Play()
	if row.prompt.HoldDuration <= 0 then
		row.keyScale.Scale = MOTION.PressScale
		TweenService:Create(row.keyScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

-- === What is on the card ====================================================

--[[ Rebuild the card from the shown prompts of the focused part. Cheap and idempotent: rows are
	kept per prompt, so a redraw only re-letters them, and the card is two or three rows. ]]
function GlassPromptController._redraw(self)
	local focus = self._focus
	local list: { ProximityPrompt } = {}
	for prompt in self._shown do
		if prompt.Parent == focus and prompt.Enabled then
			table.insert(list, prompt)
		end
	end
	table.sort(list, function(a, b)
		return (a:GetAttribute(ATTRS.Order) or 99) < (b:GetAttribute(ATTRS.Order) or 99)
	end)

	--- Nothing to show: the card animates out with the rows it had, which go on the next redraw.
	if #list == 0 then
		self:_hideCard()
		return
	end

	--- Which look draws it. Switching (the kit template arriving late) starts the rows again.
	local entry = self:_kitEntry()
	local mode = if entry then "kit" else "glass"
	if mode ~= self._mode then
		self:_dropRows()
		self._mode = mode
		self:_showGlass(mode == "glass")
	end
	if entry then
		self:_kitRedraw(list, entry)
		return
	end

	--- Rows for prompts no longer on the card go.
	local keep = {}
	for _, prompt in list do
		keep[prompt] = true
	end
	for prompt, row in self._rows do
		if not keep[prompt] then
			row.trove:Destroy()
			self._rows[prompt] = nil
		end
	end

	local rows = {}
	for _, prompt in list do
		local row = self._rows[prompt]
		if not row then
			row = self:_buildRow(prompt)
			self._rows[prompt] = row
		else
			self:_dressRow(row)
		end
		table.insert(rows, row)
	end
	self._card.gui.Adornee = focus
	self:_layout(rows, list[1].ObjectText)
	self:_showCard()
end

-- === The kit look ===========================================================
--[[ `GlassPromptConfig.KitStyle` on the new UI: the card is cut from the Cartoony Kit's PromptUI
	(`BuildWorldPromptV2` builds `MainUIV2.Screens.WorldPrompt`), and the rows are its green and
	orange buttons with a white keycap. Without that template this whole section stands down and the
	glass draws instead. ]]

--- The built kit entry in this player's UI, or nil (flag off, old UI, or a place without it).
function GlassPromptController._kitEntry(self): Instance?
	if not GlassPromptConfig.KitStyle or not UIRoot.isNewUI() then
		return nil
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local root = playerGui and UIRoot.find(playerGui)
	local shelf = root and root:FindFirstChild(GlassPromptConfig.Kit.Shelf)
	local entry = shelf and shelf:FindFirstChild(GlassPromptConfig.Kit.Entry)
	if entry and entry:FindFirstChild("Card1") and entry:FindFirstChild("Row") then
		return entry
	end
	return nil
end

function GlassPromptController._dropRows(self)
	for prompt, row in self._rows do
		row.trove:Destroy()
		self._rows[prompt] = nil
	end
end

--- The glass's own layers, off while the kit draws (they live on the same billboard).
function GlassPromptController._showGlass(self, on: boolean)
	local card = self._card
	for _, layer in { card.shadowOuter, card.shadowInner, card.pane } do
		layer.Visible = on
	end
	if not on then
		return
	end
	if self._kitCard then
		self._kitCard:Destroy()
		self._kitCard = nil
		self._kitRows = 0
	end
end

function GlassPromptController._buildKitRow(self, prompt: ProximityPrompt, entry: Instance, slot: number): Row
	local alt = slot > 1
	local row = (entry:FindFirstChild(if alt then "RowAlt" else "Row") or entry:FindFirstChild("Row")) :: Frame
	row = row:Clone()
	local btn = row:FindFirstChild("Btn") :: GuiButton
	local fill = btn:FindFirstChild("Fill") :: Frame
	local key = btn:FindFirstChild("Key") :: Frame
	local title = btn:FindFirstChild("Title") :: TextLabel
	local trove = Trove.new()
	trove:Add(row)
	if btn:IsA("TextButton") then
		btn.AutoButtonColor = false
	end

	local progress = Instance.new("NumberValue")
	local alpha = Instance.new("NumberValue")
	alpha.Value = GlassPromptConfig.Kit.FillTransparency
	trove:Add(progress)
	trove:Add(alpha)

	local kitRow: Row = {
		prompt = prompt,
		kit = true,
		alt = alt,
		slot = slot,
		titleBox = { title.Position, title.Size },
		frame = row,
		fill = fill,
		gradient = fill:FindFirstChildOfClass("UIGradient") :: UIGradient,
		lip = nil,
		key = key,
		keyScale = key:FindFirstChildOfClass("UIScale") :: UIScale,
		keyText = key:FindFirstChild("Letter") :: TextLabel,
		keyImage = key:FindFirstChild("Glyph") :: ImageLabel,
		label = title,
		hint = btn:FindFirstChild("Hold") :: TextLabel,
		button = btn,
		trove = trove,
		progress = progress,
		alpha = alpha,
		tween = nil,
		down = false,
	}
	return self:_finishRow(kitRow)
end

--- The kit row's caption, key and HOLD tag, for the prompt as it is now and the device in hand.
function GlassPromptController._dressKitRow(self, row: Row)
	local prompt = row.prompt
	local kind = device()
	local hold = prompt.HoldDuration > 0
	row.label.Text = prompt.ActionText
	row.hint.Visible = hold

	row.key.Visible = kind ~= "Touch"
	for _, child in row.key:GetChildren() do
		if child:IsA("UIStroke") then
			child.Enabled = kind == "Keyboard"
		end
	end
	if kind == "Gamepad" then
		row.key.BackgroundTransparency = 1
		row.keyImage.Image = UserInputService:GetImageForKeyCode(prompt.GamepadKeyCode) or ""
		row.keyImage.Visible = true
		row.keyText.Visible = false
	elseif kind == "Keyboard" then
		local text = UserInputService:GetStringForKeyCode(prompt.KeyboardKeyCode)
		row.key.BackgroundTransparency = 0
		row.keyImage.Visible = false
		row.keyText.Visible = true
		row.keyText.Text = if text and text ~= "" then string.upper(text) else prompt.KeyboardKeyCode.Name
	end

	--- On touch there is no key, so the caption takes the face from the left edge to the HOLD tag.
	local box = row.titleBox :: { UDim2 }
	local position, size = box[1], box[2]
	if kind == "Touch" then
		local right = position.X.Scale + size.X.Scale / 2
		local left = GlassPromptConfig.Kit.TouchInset
		row.label.Position = UDim2.fromScale((left + right) / 2, position.Y.Scale)
		row.label.Size = UDim2.fromScale(right - left, size.Y.Scale)
	else
		row.label.Position = position
		row.label.Size = size
	end
end

--[[ The kit card for `list`: the entry's card for that many rows, a green row for the main action
	and orange for the rest. A different row count is a different card, so the rows go with it and
	are rebuilt in the new card's slots. ]]
function GlassPromptController._kitRedraw(self, list: { ProximityPrompt }, entry: Instance)
	local n = math.min(#list, 3)
	local template = entry:FindFirstChild("Card" .. n) :: Frame?
	if not template then
		return
	end
	if self._kitRows ~= n or not self._kitCard then
		self:_dropRows()
		if self._kitCard then
			self._kitCard:Destroy()
		end
		local card = template:Clone()
		card.Visible = true
		card.Parent = self._card.root
		self._kitCard = card
		self._kitRows = n
	end
	local card = self._kitCard :: Frame

	--- Rows that left the card, or moved slot, or changed face, go.
	local slotOf = {}
	for i, prompt in list do
		slotOf[prompt] = i
	end
	for prompt, row in self._rows do
		if slotOf[prompt] ~= row.slot then
			row.trove:Destroy()
			self._rows[prompt] = nil
		end
	end

	local main = card:FindFirstChild("Main")
	for i = 1, n do
		local prompt = list[i]
		local row = self._rows[prompt]
		if not row then
			row = self:_buildKitRow(prompt, entry, i)
			row.frame.Parent = main and main:FindFirstChild("Slot" .. i)
			self._rows[prompt] = row
		else
			self:_dressKitRow(row)
		end
	end

	local header = card:FindFirstChild("Header")
	local title = header and header:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = string.upper(list[1].ObjectText)
	end

	local w = card:GetAttribute("NominalWidth") or 300
	local h = card:GetAttribute("NominalHeight") or 120
	local s = viewScale() * GlassPromptConfig.Kit.Scale
	self._card.gui.Size = UDim2.fromOffset(w * s, h * s)
	self._card.root.Size = UDim2.fromOffset(w, h)
	self._kitScale = GlassPromptConfig.Kit.Scale
	self:_setPop(self._pop)
	self._card.gui.Adornee = self._focus
	self:_showCard()
end

-- === Focus ==================================================================

--- May the local player be offered this prompt at all?
local function offered(prompt: ProximityPrompt): boolean
	if prompt:GetAttribute(ATTRS.Hidden) == true then
		return false
	end
	local owner = prompt:GetAttribute(ATTRS.Owner)
	return owner == nil or owner == Players.LocalPlayer.UserId
end

--[[ Pick the nearest part with a prompt on offer in range, keep the current one unless a rival is
	`Hysteresis` nearer, and switch every tagged prompt's `Enabled` to match. ]]
function GlassPromptController._refocus(self)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local here = if root and root:IsA("BasePart") then root.Position else nil

	local distances: { [Instance]: number } = {}
	if here then
		for prompt in self._prompts do
			local parent = prompt.Parent
			local at = anchorPosition(parent)
			if parent and at and offered(prompt) then
				local d = (at - here).Magnitude
				if d <= prompt.MaxActivationDistance then
					distances[parent] = math.min(distances[parent] or math.huge, d)
				end
			end
		end
	end

	local best, bestDistance = nil, math.huge
	for parent, d in distances do
		if d < bestDistance then
			best, bestDistance = parent, d
		end
	end
	local current = self._focus
	if current and distances[current] and distances[current] <= bestDistance + GlassPromptConfig.Focus.Hysteresis then
		best = current
	end

	local changed = best ~= self._focus
	self._focus = best
	for prompt in self._prompts do
		local want = prompt.Parent == best and best ~= nil and offered(prompt)
		if prompt.Enabled ~= want then
			prompt.Enabled = want
			changed = true
		end
	end
	if changed then
		self:_redraw()
	end
end

-- === Tagged prompts arriving and leaving ====================================

function GlassPromptController._track(self, prompt: Instance)
	if not prompt:IsA("ProximityPrompt") or self._prompts[prompt] then
		return
	end
	local trove = Trove.new()
	self._prompts[prompt] = trove
	--- Start switched off; the next refocus turns on the one card that should be up.
	prompt.Enabled = false
	for _, property in { "ActionText", "ObjectText", "HoldDuration", "KeyboardKeyCode", "GamepadKeyCode" } do
		trove:Add(prompt:GetPropertyChangedSignal(property):Connect(function()
			if self._shown[prompt] then
				self:_redraw()
			end
		end))
	end
	trove:Add(prompt.AttributeChanged:Connect(function()
		self:_refocus()
	end))
end

function GlassPromptController._untrack(self, prompt: Instance)
	local trove = self._prompts[prompt :: ProximityPrompt]
	if not trove then
		return
	end
	trove:Destroy()
	self._prompts[prompt :: ProximityPrompt] = nil
	self._shown[prompt :: ProximityPrompt] = nil
	if (prompt :: ProximityPrompt).Parent == self._focus or self._rows[prompt :: ProximityPrompt] then
		self:_redraw()
	end
end

GlassPromptController:withLifecycle({
	init = function(self)
		self._prompts = {} :: { [ProximityPrompt]: any }
		self._shown = {} :: { [ProximityPrompt]: boolean }
		self._rows = {} :: { [ProximityPrompt]: Row }
		self._focus = nil :: Instance?
		self._popToken = 0
		self._mode = nil :: string?
		self._kitCard = nil :: Frame?
		self._kitRows = 0
	end,

	start = function(self)
		if not GlassPromptConfig.Enabled then
			return
		end
		self:_buildCard()

		for _, prompt in CollectionService:GetTagged(GlassPromptConfig.Tag) do
			self:_track(prompt)
		end
		CollectionService:GetInstanceAddedSignal(GlassPromptConfig.Tag):Connect(function(prompt)
			self:_track(prompt)
			self:_refocus()
		end)
		CollectionService:GetInstanceRemovedSignal(GlassPromptConfig.Tag):Connect(function(prompt)
			self:_untrack(prompt)
		end)

		ProximityPromptService.PromptShown:Connect(function(prompt)
			if self._prompts[prompt] then
				self._shown[prompt] = true
				self:_redraw()
			end
		end)
		ProximityPromptService.PromptHidden:Connect(function(prompt)
			if self._shown[prompt] then
				self._shown[prompt] = nil
				self:_redraw()
			end
		end)

		--- A new device redraws every row (key letter, pad glyph, or a bare touch row).
		GamepadInput.observePreferred(function()
			if self._focus then
				self:_redraw()
			end
		end)
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
			if self._focus then
				self:_redraw()
			end
		end)
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				if self._focus then
					self:_redraw()
				end
			end)
		end

		task.spawn(function()
			while true do
				self:_refocus()
				task.wait(GlassPromptConfig.Focus.Interval)
			end
		end)
	end,
})

return GlassPromptController
