--[[
	ControlLegend  (shared, client-side in practice)
	-----------------------------------------------
	"Here is what the buttons do", in a corner, as a panel that draws itself.

	    +---------------------+
	    |  CONTROLS           |
	    |   (o)   STEER       |
	    |   (o)   BOOST       |
	    |   (o)   BRAKE       |
	    |   (o)   NITRO       |
	    |   (o)   BAIL        |
	    +---------------------+

	Give it a list of `{ id, label, keys }` and it builds that; the glyph on each row is whichever
	of that row's keys matches the device the player is holding, re-asked every time they change
	device. Nothing here knows what a race is, which is the point — see `LegendConfig`'s header for
	why this is a module and what the other legends look like.

	FOUR THINGS THAT ARE NOT OBVIOUS FROM THE CODE.

	  • IT IS A READOUT AND MUST STAY ONE. Nothing built here is `Active`, nothing is a `GuiButton`,
	    and no input is bound anywhere in this file. The panel sits in a corner where thumbs live on
	    a phone, and one that ate a press would occasionally cost somebody a steal. This is the same
	    contract the getaway card and the tutorial card are on.

	  • THE DEVICE DECIDES BOTH WHAT IT DRAWS AND WHETHER IT DRAWS. `LegendConfig.ShowFor` is
	    keyed by input device, and `GamepadInput.observePreferred` is the subscription — one per
	    legend, taken at build time, which is also what re-reads every glyph when a player swaps a
	    DualSense for an Xbox pad (`GetImageForKeyCode` hands back the art of the controller
	    actually connected, so a glyph cannot be cached).

	  • EVERY NUMBER IS SCALE. A fraction of the screen for the panel, a fraction of the panel for a
	    row, a fraction of the row for what is in it. No offset pixels and no reference-pixel
	    normalisation — this is a block of text on a television across the room as often as it is on
	    a phone, and the only thing that must not skew with the viewport is the glyph itself, which
	    carries a `UIAspectRatioConstraint` for exactly that. See the note over `_buildRow`.

	  • THE PANEL'S HEIGHT IS DERIVED, NOT AUTHORED. It is padding + title + N rows, so a two-row
	    legend and a five-row one are the same design and adding a row does not mean re-tuning a
	    height by eye. `setEntries` re-derives it, which is what makes a legend that changes shape
	    mid-race possible at all.

	A legend built while `LegendConfig.Enabled` is false is a live handle with no instances behind
	it: every method is a no-op and `:destroy` is safe. Callers never have to ask.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GamepadInput = require(ReplicatedStorage.shared.Modules.GamepadInput)
local LegendConfig = require(ReplicatedStorage.shared.Configs.LegendConfig)

local ControlLegend = {}
ControlLegend.__index = ControlLegend

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

--- `TextScaled` would sooner break a caption onto a second line than pick a smaller font, so every
--- one-line label in this project is written through a non-breaking space. Same helper, same
--- reason, as RaceUIController and GetawayHudController — a legend row is one line by definition.
local NBSP = utf8.char(0xA0)
local function oneLine(text: string): string
	return (string.gsub(text, "%s+", NBSP))
end

--[[ What a keycap SAYS when the row is drawing its keyboard half and the entry did not override it.

	Only the keys whose `KeyCode.Name` is not what a player calls the key. Everything else — every
	letter, every digit — is its own name already and falls through. Deliberately short: a cap is a
	cap, not a sentence, and `TextScaled` shrinks a long one until it is unreadable rather than
	wrapping it. ]]
local KEY_NAMES: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.LeftShift] = "SHIFT",
	[Enum.KeyCode.RightShift] = "SHIFT",
	[Enum.KeyCode.LeftControl] = "CTRL",
	[Enum.KeyCode.RightControl] = "CTRL",
	[Enum.KeyCode.LeftAlt] = "ALT",
	[Enum.KeyCode.RightAlt] = "ALT",
	[Enum.KeyCode.Space] = "SPACE",
	[Enum.KeyCode.Return] = "ENTER",
	[Enum.KeyCode.Escape] = "ESC",
	[Enum.KeyCode.Backspace] = "BKSP",
	[Enum.KeyCode.Tab] = "TAB",
	[Enum.KeyCode.Up] = "UP",
	[Enum.KeyCode.Down] = "DOWN",
	[Enum.KeyCode.Left] = "LEFT",
	[Enum.KeyCode.Right] = "RIGHT",
}

--- Where a corner name puts the panel: which of its own corners is pinned, and which way the
--- margins run from the screen edge.
local CORNERS: { [string]: { anchor: Vector2, x: number, y: number } } = {
	BottomRight = { anchor = Vector2.new(1, 1), x = 1, y = 1 },
	BottomLeft = { anchor = Vector2.new(0, 1), x = 0, y = 1 },
	TopRight = { anchor = Vector2.new(1, 0), x = 1, y = 0 },
	TopLeft = { anchor = Vector2.new(0, 0), x = 0, y = 0 },
}

export type Entry = {
	--- Stable handle for `setRowActive` / `setRowLabel`. Not the label, which can change.
	id: string,
	label: string,
	--- Mixed keyboard-and-pad list, the shape every binding in this game is configured in. The
	--- legend reads whichever half matches the device (`GamepadInput.gamepadKeyIn` finds the pad
	--- one); a list with no pad key draws nothing on a pad, which is the honest answer.
	keys: { Enum.KeyCode },
	--- Overrides what the KEYCAP says. For "LeftShift" -> SHIFT, or a row covering two keys.
	keyboard: string?,
}

export type Options = {
	--- Names the ScreenGui. Two legends up at once must not share one.
	name: string?,
	title: string?,
	entries: { Entry }?,
	corner: string?,
	--- Overrides `LegendConfig.Panel.Width` for a legend that needs a different column.
	width: number?,
	--- Seconds the panel stays up per show; 0 to keep it up for as long as its owner wants it.
	--- Omit for `LegendConfig.HoldSeconds`. See `_arm` for why the default is not 0.
	hold: number?,
	displayOrder: number?,
	--- Defaults to the local PlayerGui, which is where every legend so far belongs.
	parent: Instance?,
}

type Row = {
	entry: Entry,
	frame: Frame,
	glyph: ImageLabel,
	cap: Frame,
	capText: TextLabel,
	label: TextLabel,
	active: boolean,
}

export type Legend = typeof(setmetatable(
	{} :: {
		_gui: ScreenGui?,
		_panel: Frame?,
		_stroke: UIStroke?,
		_title: TextLabel?,
		--- The padded interior, and the box the rows are laid out inside. Both exist so that a
		--- row's own coordinates never have to know about the padding or the title.
		_content: Frame?,
		_rowHolder: Frame?,
		_rows: { Row },
		_byId: { [string]: Row },
		_entries: { Entry },
		_options: Options,
		--- The three questions that decide whether the panel is on screen, and they are separate on
		--- purpose: the OWNER's intent (`_wanted`), the DEVICE's answer (`_deviceOk`) and the hold
		--- timer's (`_expired`). Collapsing any two of them loses a case — see `_arm`.
		_wanted: boolean,
		_deviceOk: boolean,
		_expired: boolean,
		_hold: number,
		_holdThread: thread?,
		_alpha: number,
		_fade: Tween?,
		_deviceConn: RBXScriptConnection?,
	},
	ControlLegend
))

-- === Build ===================================================================

--[[ Which device is the player on, and does this legend draw for it?

	Touch is tested FIRST and on the capability rather than on `PreferredInput`, because a phone
	with a pad paired is still a phone: the six touch buttons are on screen, they are the legend,
	and a block of text over them is clutter over the thing it describes. `LegendConfig.ShowFor`'s
	note makes that argument in full.

	`isGamepad` and not `isGamepadActive` — this is what is ON SCREEN, which must not flicker
	because a hand brushed the mouse. The immediate answer is for reacting to a press and there are
	no presses in this file. ]]
local function deviceAllows(): boolean
	local show = LegendConfig.ShowFor
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return show.Touch
	end
	if GamepadInput.isGamepad() then
		return show.Gamepad
	end
	return show.Keyboard
end

--[[ How tall the CONTENT of this legend is, as a fraction of the screen's height: a row's pitch per
	row, plus the title and the air under it if it has one.

	This is the number every vertical fraction inside the panel is derived from, and it is why
	`Row.Pitch` and `Title.Height` are authored against the SCREEN rather than against the panel —
	the panel has no height of its own to be a fraction of until this has been added up. ]]
local function contentHeight(self: Legend): number
	local row, title = LegendConfig.Row, LegendConfig.Title
	local height = #self._rows * row.Pitch
	if self._options.title then
		height += title.Height + title.Gap
	end
	return height
end

--[[ ...and the panel that has to hold it, padding included.

	`UIPadding` eats a fraction of the panel's OWN height, so the panel cannot simply be the content
	plus the padding — it has to be solved for: `content = (1 - 2p) * panel`. Which is also why
	`Padding` reading 0.05 costs a tenth of the panel rather than a twentieth. ]]
local function panelHeight(self: Legend): number
	local inner = math.max(1 - LegendConfig.Panel.Padding * 2, 0.05)
	return contentHeight(self) / inner
end

--[[ ONE ROW: the glyph column, then the verb.

	THE GLYPH IS THE ONE THING HERE THAT MUST NOT SKEW, and it is bounded by the row's HEIGHT
	rather than its width for a reason that only shows up on an unusual screen. Its box is
	`Glyph.Width` of the row across and `Glyph.Height` of the row down, and the
	`UIAspectRatioConstraint` inside it resolves the square by taking the SMALLER of the two — so on
	a 16:9 screen it is width-bounded and on a 32:9 one it is height-bounded, and in neither case
	does it overflow the row it is in. A wider screen makes the column looser, never taller.

	Never a zero-width box: `FitWithinMaxSize` (the default) collapses one of those to nothing
	rather than resolving it from the aspect, which is a trap this project has already paid for.

	THE CAP AND THE GLYPH ARE BOTH BUILT, ALWAYS, and one of them is hidden. Building both up front
	is what makes a device change a visibility flip rather than a rebuild — a player who picks up a
	pad mid-race gets glyphs on the next frame, with no chance of the panel reflowing under them.

	NOTHING VERTICAL IS SET HERE. A row's Y position and height are fractions of the rows box, which
	does not know how tall it is until every row exists — so `_layout` writes both, for every row,
	after the list is complete. This builds the row's INSIDES, which are fractions of the row and
	are therefore knowable straight away. ]]
function ControlLegend._buildRow(self: Legend, entry: Entry): Row
	local cfg = LegendConfig.Row
	local capCfg = LegendConfig.Cap

	local frame = Instance.new("Frame")
	frame.Name = "Row_" .. entry.id
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0

	local glyph = Instance.new("ImageLabel")
	glyph.Name = "Glyph"
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(cfg.Glyph.CentreX, 0.5)
	glyph.Size = UDim2.fromScale(cfg.Glyph.Width, cfg.Glyph.Height)
	glyph.BackgroundTransparency = 1
	--- Fit, not Stretch: the stock art is square-canvassed but the ink inside it is not always
	--- (a trigger is a wide pill on a square page), and Fit is what keeps the drawn shape honest.
	glyph.ScaleType = Enum.ScaleType.Fit
	glyph.ImageTransparency = 1
	glyph.Visible = false
	glyph.Parent = frame

	local glyphAspect = Instance.new("UIAspectRatioConstraint")
	glyphAspect.AspectRatio = 1
	glyphAspect.Parent = glyph

	--- The keyboard half. Wider than the glyph's square and left-aligned rather than sharing its
	--- centre, because a keyboard row says SHIFT and SPACE where a pad row says one symbol — see
	--- `LegendConfig.Cap`.
	local cap = Instance.new("Frame")
	cap.Name = "Cap"
	cap.AnchorPoint = Vector2.new(0, 0.5)
	cap.Position = UDim2.fromScale(capCfg.Left, 0.5)
	cap.Size = UDim2.fromScale(capCfg.Width, capCfg.Height)
	cap.BackgroundColor3 = capCfg.Color
	cap.BackgroundTransparency = 1
	cap.BorderSizePixel = 0
	cap.Visible = false
	cap.Parent = frame

	local capCorner = Instance.new("UICorner")
	--- Against the cap's HEIGHT, via a scale taken on the shorter side — so a wide cap and a narrow
	--- one wear the same curve rather than the same fraction of two different widths.
	capCorner.CornerRadius = UDim.new(capCfg.CornerRadius, 0)
	capCorner.Parent = cap

	local capText = Instance.new("TextLabel")
	capText.Name = "Key"
	capText.AnchorPoint = Vector2.new(0.5, 0.5)
	capText.Position = UDim2.fromScale(0.5, 0.5)
	--- Inset inside the cap so the glyph never touches the rounded edge.
	capText.Size = UDim2.fromScale(0.84, 0.66)
	capText.BackgroundTransparency = 1
	capText.FontFace = FONT
	capText.Text = ""
	capText.TextColor3 = capCfg.TextColor
	capText.TextScaled = true
	capText.TextTransparency = 1
	capText.Parent = cap

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.fromScale(cfg.Label.Left, 0.5)
	label.Size = UDim2.fromScale(cfg.Label.Right - cfg.Label.Left, cfg.Label.Height)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.Text = oneLine(entry.label)
	label.TextColor3 = cfg.Label.Color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextScaled = true
	label.TextTransparency = 1
	label.Parent = frame

	return {
		entry = entry,
		frame = frame,
		glyph = glyph,
		cap = cap,
		capText = capText,
		label = label,
		active = true,
	}
end

--[[ Draw one row for the device the player is on: the pad glyph, or the keycap, or neither.

	NEITHER IS A REAL CASE and it is why `padKey` is allowed to be nil rather than asserted: a row
	whose `keys` carry no controller button has nothing to show a pad player, and drawing the
	keyboard cap instead would be telling a console player to press a key they do not have. An
	empty column is the honest answer and the label still reads.

	Re-read rather than cached, every time: `GetImageForKeyCode` returns the art of the controller
	actually connected, so ButtonX is a square on an Xbox pad and a triangle-family symbol on a
	DualSense, and a player who swaps brands mid-session has to see it change. ]]
function ControlLegend._dressRow(self: Legend, row: Row, isGamepad: boolean)
	local cfg = LegendConfig.Row
	local capCfg = LegendConfig.Cap
	local padKey = GamepadInput.gamepadKeyIn(row.entry.keys)
	local usePad = isGamepad and padKey ~= nil

	if usePad then
		row.glyph.Image = GamepadInput.getButtonImage(padKey :: Enum.KeyCode)
	else
		local text = row.entry.keyboard
		if not text then
			--- The first key in the list that is NOT a controller button, which is the keyboard
			--- half of the same mixed list the pad half was read out of.
			for _, keyCode in row.entry.keys do
				if keyCode ~= padKey then
					text = KEY_NAMES[keyCode] or keyCode.Name:upper()
					break
				end
			end
		end
		row.capText.Text = oneLine(text or "")
		--- A one-character cap is a squarish key and a word is a wide one, which is what a keyboard
		--- looks like. Written here rather than at build time because the text can change under a
		--- row — the action row swaps SPACE for E mid-race — and the cap has to follow it.
		--- `utf8.len` rather than `#`, so a multi-byte glyph counts as the one character it is.
		local length = utf8.len(row.capText.Text) or #row.capText.Text
		local width = if length <= capCfg.NarrowUpTo then capCfg.NarrowWidth else capCfg.Width
		row.cap.Size = UDim2.fromScale(width, capCfg.Height)
	end

	row.glyph.Visible = usePad
	row.cap.Visible = not usePad and row.capText.Text ~= ""

	--- The label starts where whichever column is showing ends. See `LegendConfig.Row.Label`.
	local left = if usePad then cfg.Label.Left else cfg.Label.LeftKeyboard
	row.label.Position = UDim2.fromScale(left, 0.5)
	row.label.Size = UDim2.fromScale(cfg.Label.Right - left, cfg.Label.Height)
end

--- The panel and its title. Built once per legend; rows come and go inside it.
function ControlLegend._build(self: Legend)
	local panel = LegendConfig.Panel
	local titleCfg = LegendConfig.Title
	local opts = self._options

	local gui = Instance.new("ScreenGui")
	gui.Name = opts.name or "ControlLegend"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = opts.displayOrder or LegendConfig.DisplayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	local corner = CORNERS[opts.corner or panel.Corner] or CORNERS.BottomRight

	--- NOT `Active`, and nothing under it is either. See the header: this is a readout sitting in
	--- the corner a phone keeps its thumbs in.
	local root = Instance.new("Frame")
	root.Name = "Panel"
	root.AnchorPoint = corner.anchor
	root.Position = UDim2.fromScale(
		--- Anchored INTO its corner, so the margin is a gap from the screen edge at any viewport
		--- rather than a gap that grows with the panel.
		if corner.x == 1 then 1 - panel.Margin.X else panel.Margin.X,
		if corner.y == 1 then 1 - panel.Margin.Y else panel.Margin.Y
	)
	root.Size = UDim2.fromScale(opts.width or panel.Width, 0)
	root.BackgroundColor3 = panel.Color
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Parent = gui

	local roundness = Instance.new("UICorner")
	--- Against the panel's WIDTH: this is a tall column, so its short side is the horizontal one.
	--- (`UICorner`'s scale is taken against the shorter side, so authoring it as a fraction of the
	--- width is what makes the curve stable as rows are added.)
	roundness.CornerRadius = UDim.new(panel.CornerRadius, 0)
	roundness.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.Color = panel.StrokeColor
	stroke.Thickness = panel.StrokeThickness
	stroke.Transparency = 1
	stroke.Parent = root

	--- One padding for the whole panel, so every row and the title share one left edge without any
	--- of them repeating the number.
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(panel.Padding, 0)
	padding.PaddingBottom = UDim.new(panel.Padding, 0)
	padding.PaddingLeft = UDim.new(panel.Padding, 0)
	padding.PaddingRight = UDim.new(panel.Padding, 0)
	padding.Parent = root

	--- Everything inside the padding lives in here, so a row's `Position` is a fraction of the
	--- CONTENT rather than of the panel, and the derived height in `panelHeight` is the only place
	--- the padding has to be reasoned about.
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.AnchorPoint = Vector2.new(0.5, 1)
	content.Position = UDim2.fromScale(0.5, 1)
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Parent = root

	local title: TextLabel? = nil
	if opts.title then
		local label = Instance.new("TextLabel")
		label.Name = "Title"
		label.AnchorPoint = Vector2.new(0, 0)
		label.Position = UDim2.fromScale(0, 0)
		label.Size = UDim2.fromScale(1, 0)
		label.BackgroundTransparency = 1
		label.FontFace = FONT
		label.Text = oneLine(opts.title)
		label.TextColor3 = titleCfg.Color
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextScaled = true
		label.TextTransparency = 1
		label.Parent = content
		title = label
	end

	--- The rows sit below the title, in their own box, so a row's index maths never has to know
	--- whether this legend has a title.
	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.AnchorPoint = Vector2.new(0.5, 1)
	rows.Position = UDim2.fromScale(0.5, 1)
	rows.Size = UDim2.fromScale(1, 1)
	rows.BackgroundTransparency = 1
	rows.BorderSizePixel = 0
	rows.Parent = content

	self._gui = gui
	self._panel = root
	self._stroke = stroke
	self._title = title
	self._content = content
	self._rowHolder = rows

	gui.Parent = opts.parent or Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- === Layout ==================================================================

--[[ Re-derive the panel's height from what is in it, then hand the title, the rows box and every
	row its share of it.

	THIS IS THE ONLY PLACE IN THE FILE WHERE TWO COORDINATE SPACES MEET, and it is one function for
	that reason. `Row.Pitch` and `Title.Height` are authored against the SCREEN (they have to be —
	see `contentHeight`), and every box below is sized against its PARENT, so each of them is that
	authored number over the height of whatever it is going into:

	    title  -> of the content:  Title.Height / content
	    rows   -> of the content:  (content - title - gap) / content
	    a row  -> of the rows box: Pitch / rowsHeight, which is exactly 1/N

	Once a row is 1/N of the box, its position is (i-1)/N and its height is Fill/N — so the run of
	rows is exact at any count and does not accumulate rounding down the stack. ]]
function ControlLegend._layout(self: Legend)
	local rowCfg, titleCfg = LegendConfig.Row, LegendConfig.Title
	local root, rows = self._panel, self._rowHolder
	if not (root and rows) then
		return
	end

	root.Size = UDim2.fromScale(root.Size.X.Scale, panelHeight(self))

	local content = contentHeight(self)
	if content <= 0 then
		return -- a legend with no title and no rows; nothing to divide
	end

	local titleShare = if self._title then (titleCfg.Height + titleCfg.Gap) / content else 0
	if self._title then
		--- The gap under the title is left OUTSIDE the label's own box, so the text is not
		--- vertically centred in a box a fifth of which is deliberately empty.
		self._title.Size = UDim2.fromScale(1, titleCfg.Height / content)
	end

	rows.Size = UDim2.fromScale(1, math.max(1 - titleShare, 0))

	local count = #self._rows
	for index, row in self._rows do
		row.frame.Position = UDim2.fromScale(0.5, (index - 1) / count)
		row.frame.Size = UDim2.fromScale(1, rowCfg.Fill / count)
	end
end

-- === Public ==================================================================

--[[ Build a legend. It starts hidden: a caller shows it when whatever it describes is live.

	`entries` may be omitted and set later, which is what a legend whose rows depend on a server
	round trip wants. Everything else falls back to `LegendConfig`. ]]
function ControlLegend.new(options: Options?): Legend
	local self = setmetatable({
		_gui = nil,
		_panel = nil,
		_stroke = nil,
		_title = nil,
		_content = nil,
		_rowHolder = nil,
		_rows = {},
		_byId = {},
		_entries = {},
		_options = options or {},
		_wanted = false,
		_deviceOk = false,
		_expired = false,
		--- Seconds the panel stays up per show. Falls back to the config's default rather than to
		--- "forever", so a caller that says nothing gets the convention rather than the outlier.
		_hold = (options and options.hold) or LegendConfig.HoldSeconds,
		_holdThread = nil,
		_alpha = 0,
		_fade = nil,
		_deviceConn = nil,
	}, ControlLegend) :: any

	if not LegendConfig.Enabled then
		return self
	end

	self:_build()
	self:setEntries(self._options.entries or {})

	--[[ One subscription per legend, taken here rather than by each row, and it does both halves of
		the device question at once: WHETHER this legend draws at all (`ShowFor`) and WHAT each row
		draws (glyph or cap, and which brand's glyph). Fires immediately, which is what seeds the
		first draw. ]]
	self._deviceConn = GamepadInput.observePreferred(function()
		self:refresh()
	end)

	return self
end

--[[ Replace the rows. Rebuilds them and re-derives the panel's height, so a legend can change
	shape without its owner touching a number.

	The old rows are destroyed rather than pooled: this runs when a screen changes what it is
	teaching, not per frame, and a pool here would be a cache to keep correct for no gain. ]]
function ControlLegend.setEntries(self: Legend, entries: { Entry })
	if not self._rowHolder then
		return
	end

	for _, row in self._rows do
		row.frame:Destroy()
	end
	table.clear(self._rows)
	table.clear(self._byId)

	self._entries = entries
	for _, entry in entries do
		local row = self:_buildRow(entry)
		row.frame.Parent = self._rowHolder
		table.insert(self._rows, row)
		self._byId[entry.id] = row
	end

	self:_layout()
	self:refresh()
end

--[[ Change one row's verb and the key it advertises, in place.

	`keys` is optional: a row that means the same thing under a different name keeps its glyph. The
	driving screen uses the both-at-once form, because BAIL and STEAL are different buttons as well
	as different words. ]]
function ControlLegend.setRowLabel(self: Legend, id: string, label: string, keys: { Enum.KeyCode }?, keyboard: string?)
	local row = self._byId[id]
	if not row then
		return
	end
	row.entry.label = label
	if keys then
		row.entry.keys = keys
		row.entry.keyboard = keyboard
	end
	row.label.Text = oneLine(label)
	self:_dressRow(row, GamepadInput.isGamepad())
end

--[[ Dim a row that is not available right now, or bring it back.

	Dimmed rather than hidden, and `LegendConfig.Row.Dim`'s note says why: a row that comes and goes
	makes the rows under it jump, and a legend that reshuffles itself in the corner of a driving
	screen is worse than one that is briefly greyed.

	Idempotent, because the caller is a per-frame sync (`DrivingHudController._syncLegendAction`)
	and re-tweening to the value a property already holds every frame would stall the tween at its
	first step forever. ]]
function ControlLegend.setRowActive(self: Legend, id: string, active: boolean)
	local row = self._byId[id]
	if not row or row.active == active then
		return
	end
	row.active = active
	self:_applyRowAlpha(row)
end

--[[ ARM THE HOLD TIMER: the legend teaches, then gets out of the way.

	A CONTROL LEGEND THAT NEVER LEAVES IS NOT THE CONVENTION and this is the machinery that makes it
	not one. A persistent button strip belongs in a MENU, where it is a footer describing the thing
	you are looking at; during gameplay the pattern everywhere is teach-then-retire, with anything
	situational prompted in context instead. This game already does the second half — the steal is
	drawn on the car you are over (`StealController`'s prompt billboard carries its own ButtonX), so
	the one verb a player would genuinely need reminding of at the moment it matters is covered
	without the panel being there.

	`hold` of 0 means never, for a caller whose legend IS a footer.

	IT RE-ARMS ON A DEVICE CHANGE, and that is not a nicety — it is the hole this timer would
	otherwise open. A player who plugs a pad in thirty seconds into a run has just become the person
	the legend is for, and without this the window has already closed on them and they would never
	see it at all. `refresh` calls this on the false->true edge of `_deviceOk` for that reason.

	A thread rather than `task.delay` plus a guard, so re-arming CANCELS the old timer rather than
	leaving two of them racing to expire the same panel. ]]
function ControlLegend._arm(self: Legend)
	if self._holdThread then
		task.cancel(self._holdThread)
		self._holdThread = nil
	end
	self._expired = false
	if self._hold <= 0 then
		return
	end
	self._holdThread = task.delay(self._hold, function()
		self._holdThread = nil
		self._expired = true
		self:refresh()
	end)
end

--[[ Show or hide the legend, and start its hold timer.

	The device still gets the final say — asking for a legend on a device `ShowFor` says no to
	leaves it hidden, and picking up a pad then brings it in on its own.

	Showing always re-arms, including a show that is already showing... which cannot happen, because
	of the guard. That is deliberate: the owner's "the race started" is what opens a window, and a
	race that is already running should not keep re-opening it. The two beats that DO want a fresh
	window both go through a hide first — a revive is preceded by a wreck. ]]
function ControlLegend.setVisible(self: Legend, on: boolean)
	if self._wanted == on then
		return
	end
	self._wanted = on
	if on then
		self:_arm()
	elseif self._holdThread then
		task.cancel(self._holdThread)
		self._holdThread = nil
	end
	self:refresh()
end

--- How long this legend stays up once shown, in seconds; 0 for the whole time its owner wants it.
--- Takes effect on the NEXT show rather than re-arming a window that is already running.
function ControlLegend.setHold(self: Legend, seconds: number)
	self._hold = math.max(seconds, 0)
end

function ControlLegend.isVisible(self: Legend): boolean
	return self._wanted and self._deviceOk and not self._expired
end

--[[ Re-ask both device questions and act on the answers. Called on every device change, on every
	`setVisible`, and after any rebuild.

	The order matters: the rows are dressed BEFORE the fade is started, so a legend arriving on a
	pad has its glyphs in place for the first frame of the fade rather than popping them in a
	third of a second later. ]]
function ControlLegend.refresh(self: Legend)
	if not self._gui then
		return
	end

	local isGamepad = GamepadInput.isGamepad()
	for _, row in self._rows do
		self:_dressRow(row, isGamepad)
	end

	--[[ A DEVICE THIS LEGEND DRAWS FOR HAS JUST ARRIVED — re-open the window. See `_arm`: the
		player who plugs a pad in mid-run is exactly who this is for, and a timer that had already
		expired on them would mean they never saw it.

		The false->true EDGE and not the state, or every refresh on a pad (a row swapping, a rebuild)
		would push the window out again and the legend would never retire. ]]
	local was = self._deviceOk
	self._deviceOk = deviceAllows()
	if self._deviceOk and not was and self._wanted then
		self:_arm()
	end

	self:_fadeTo(if self:isVisible() then 1 else 0)
end

--- Take the whole legend down. Safe to call twice, and safe on a legend that never built.
function ControlLegend.destroy(self: Legend)
	if self._deviceConn then
		self._deviceConn:Disconnect()
		self._deviceConn = nil
	end
	if self._holdThread then
		task.cancel(self._holdThread)
		self._holdThread = nil
	end
	if self._fade then
		self._fade:Cancel()
		self._fade = nil
	end
	if self._gui then
		self._gui:Destroy()
		self._gui = nil
	end
	self._panel, self._stroke, self._title, self._content, self._rowHolder = nil, nil, nil, nil, nil
	table.clear(self._rows)
	table.clear(self._byId)
end

-- === Fading ==================================================================

--[[ One row's transparencies, which are the PRODUCT of the legend's own fade and the row's dim.

	They multiply rather than one of them winning, or a dimmed row would snap to full opacity the
	moment the panel finished fading in — and the dim is the whole reason the legend is honest about
	what can be pressed right now.

	`seconds` is the panel's fade when this is being called as part of one, so the rows arrive with
	the box rather than a tenth of a second ahead of it; it falls back to the dim's own, shorter
	tween when a single row is changing state mid-race. ]]
function ControlLegend._applyRowAlpha(self: Legend, row: Row, seconds: number?)
	local dim = LegendConfig.Row.Dim
	local a = self._alpha
	local glyphAlpha = if row.active then a else a * dim.Glyph
	local labelAlpha = if row.active then a else a * dim.Label
	local info = TweenInfo.new(seconds or dim.Fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	TweenService:Create(row.glyph, info, { ImageTransparency = 1 - glyphAlpha }):Play()
	TweenService:Create(row.cap, info, { BackgroundTransparency = 1 - glyphAlpha }):Play()
	TweenService:Create(row.capText, info, { TextTransparency = 1 - glyphAlpha }):Play()
	TweenService:Create(row.label, info, { TextTransparency = 1 - labelAlpha }):Play()
end

--[[ The panel arriving or leaving. One tween on the panel and its stroke and title; the rows are
	written straight, because each one already owns a tween of its own for the dim and two tweens
	fighting over one transparency is how a row ends up stuck half-faded.

	`ScreenGui.Enabled` is switched at the two ends rather than tweened: on before the fade in so
	there is something to fade, off after the fade out so nothing is left rendering at alpha zero.
	A legend fading out that is asked to come back mid-fade cancels and reverses, which is why the
	`Enabled = false` is guarded on the alpha still being zero when it lands. ]]
function ControlLegend._fadeTo(self: Legend, alpha: number)
	local panel, gui = self._panel, self._gui
	if not (panel and gui) then
		return
	end
	if self._alpha == alpha and self._fade == nil then
		return
	end

	if self._fade then
		self._fade:Cancel()
		self._fade = nil
	end

	self._alpha = alpha
	if alpha > 0 then
		gui.Enabled = true
	end

	local cfg = LegendConfig.Panel
	--[[ THREE DURATIONS, AND THE THIRD IS THE ONE THAT MATTERS. Leaving because the race ended is
		quick — the results are coming and this is in the way. Leaving because the hold timer ran
		out is SLOW, because nothing happened: the panel has to drift off rather than blink out, or
		a player glancing up catches a disappearance and looks for what caused it. `_expired` is the
		only thing that tells the two aparts. ]]
	local seconds
	if alpha > 0 then
		seconds = LegendConfig.Fade.In
	else
		seconds = if self._expired then LegendConfig.Fade.Expire else LegendConfig.Fade.Out
	end
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local tween = TweenService:Create(panel, info, {
		BackgroundTransparency = 1 - (1 - cfg.Transparency) * alpha,
	})
	if self._stroke then
		TweenService:Create(self._stroke, info, { Transparency = 1 - alpha }):Play()
	end
	if self._title then
		TweenService:Create(self._title, info, {
			TextTransparency = 1 - (1 - LegendConfig.Title.Transparency) * alpha,
		}):Play()
	end
	for _, row in self._rows do
		self:_applyRowAlpha(row, seconds)
	end

	self._fade = tween
	tween.Completed:Connect(function()
		if self._fade == tween then
			self._fade = nil
		end
		if self._alpha == 0 and self._gui then
			self._gui.Enabled = false
		end
	end)
	tween:Play()
end

return ControlLegend
