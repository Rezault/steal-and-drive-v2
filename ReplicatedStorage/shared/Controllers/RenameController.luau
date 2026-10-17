--[[
	RenameController  (client)
	--------------------------
	The box you type your dealership's name into. Opened by the pencil on your own sign
	(`DealershipSignController`), and by nothing else.

	IT IS BUILT IN CODE OUT OF THE KIT'S OWN ART, the third way this project draws UI and the same
	way `OfflineController` draws WELCOME BACK — see that file's header for the full reasoning. The
	short version: the artist drew no rename box, but the kit's panel, title cap, search bar, close
	button and pills are all uploaded and documented in `UIAssets`, so this is assembled from those
	rather than drawn from scratch. Nothing new was uploaded for this screen and no colour on it was
	eyeballed.

	It is deliberately NOT a `UIController` page, for that screen's reason: every page is opened by a
	tagged button carrying a `Page` attribute, and the thing that opens this is a `SurfaceGui` button
	on a beam in Workspace. Making it a page would mean inventing the one page nothing can open.

	THE BLUE CAP RATHER THAN ONE OF THE THREE RAIL COLOURS, because this screen is about the sign and
	the sign is `#0066FF` — it is the dealership panel's own woven cap (`DealerPanel.TitleBar`), so
	the modal and the thing it edits are the same blue.

	=== WHAT IT DOES AND DOES NOT DECIDE =======================================================

	Everything this checks, the server checks again: `PlotConfig.sanitize` runs here so a name that
	is too short or full of symbols is refused in the same frame the player pressed SAVE, and it runs
	in `PlotService._onRename` because that is the copy that counts. The one verdict that can only
	come from the server is the FILTER, so SAVE locks the screen until the answer arrives — a name
	that failed moderation must not flash up as accepted on its way to being rejected.

	NOTHING HERE PAINTS A SIGN. The sign changes when the server has actually taken the name and
	broadcast it back, the same no-optimistic-repaint rule the upgrade boards and the teleport screen
	follow. What this screen shows is the ANSWER, and then it closes.

	=== WITH THE NEW UI ON, IT IS THE KIT'S CODES BOX (Phase 4, 2026-09-16) ====================

	`UIRoot.isNewUI()` changes where the panel comes from and how it enters, and nothing about what it
	decides. `BuildRenameDealershipV2` authors it on `MainUIV2.Screens.RenameDealership` out of the
	Cartoony Kit's `CodesUI` (a field and a button, as the plan said), and `_buildKit` clones that
	into this file's own ScreenGui, at the same `DisplayOrder`, over the same scrim. `_build` is not
	run. The submit, the lock, the answer, the keyboard rule and all four pad keys are one code path.

	What the kit changes, and where to look:
	  • USE MY NAME IS A PREVIEW NOW. The kit's social strip (a picture, a caption, a name) shows the
	    player's own headshot and the exact title the sign goes back to, with the button beside it.
	    `open` fills it in. The shipping box asks the player to know what "my name" will mean.
	  • IT POPS RATHER THAN FADES, the way every V2 page opens (0.9 on a Back ease, a quick drop back
	    out), which is also how the other Phase 4 modals arrive. A kit panel is strokes, gradients and
	    CanvasGroups, and fading each of those by hand is a list that goes stale the first time the
	    artist adds a layer.
	  • THE CLOSE IS `KitPage.bind`'s, re-pointed at `_hide` exactly as `Components/GiftPickerV2` does.
	  • The pad badges sit on the kit's buttons' top-left corners rather than hanging off their left
	    edges: SAVE's left edge is the field, and a badge there would sit on the character count.

	INSET: like the shipping box, the ScreenGui ignores the GUI inset, so the scrim covers the topbar.
	The kit frame was authored in `MainUIV2`'s inset space, so it is drawn a few percent larger here
	than a kit page of the same `Size`; the build command sizes it for this space.

	THE TEXT FILTER IS A NO-OP IN STUDIO, so a name that saves in a playtest proves the path and not
	the filter. `PlotConfig`'s rename block and the migration notes say how to fake a refusal.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local GamepadConfig = require(ReplicatedStorage.shared.Configs.GamepadConfig)
local PlotConfig = require(ReplicatedStorage.shared.Configs.PlotConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local GamepadInput = require(ReplicatedStorage.shared.Modules.GamepadInput)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)
local KitPage = require(script.Parent.UIController.KitPage)

local RenameController = Shard.new("RenameController")

-- === Look & feel ============================================================
-- Fractions throughout — of the screen for the panel, of the PANEL for everything in it — so the
-- layout is one object that scales rather than a set of positions that agree at 1080p.

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)
local WHITE = Color3.fromRGB(255, 255, 255)
-- The kit's panel stroke, reused for the placeholder and the character count: both are furniture
-- rather than content, and this is the colour the kit already says that in.
local MUTED = Color3.fromRGB(135, 146, 181)
-- Amber for a refusal and green for a save — the same two `OfflineController` uses for the same
-- two meanings. A refusal here is not an error state, it is the screen answering.
local WARN_AMBER = Color3.fromRGB(240, 178, 74)
local OK_GREEN = Color3.fromRGB(126, 217, 87)

local SCRIM_COLOR = Color3.fromRGB(6, 8, 12)
local SCRIM_REST = 0.45

local RAISE_TIME = 0.28
local DROP_TIME = 0.18
--- How long the answer stands before a successful save closes the screen. Long enough to read.
local CONFIRM_HOLD = 0.7
--[[ The screen unlocks itself this long after a SAVE the server never answered. A lost request must
	not leave a locked box in the middle of the game — the name simply did not change, which is the
	same state the player was already in. ]]
local REPLY_TIMEOUT = 6

--[[ The panel, as a box the aspect constraint FITS INSIDE — both numbers are maximums, not the
	size. A REAL BOX ON BOTH AXES, never a zero: `UIAspectRatioConstraint` defaults to
	FitWithinMaxSize and collapses a zero-width element to 0x0 rather than solving for the aspect,
	which is a trap this project has already paid for once. ]]
local PANEL_BOX = UDim2.fromScale(0.80, 0.50)

-- Fractions of the PANEL, top to bottom. The cap's two numbers are measured out of the PSD rather
-- than chosen — 1788 x 138 against a 1798 x 1132 panel, so 99.4% wide and 12.2% tall, flush.
local BAR_SIZE = UDim2.fromScale(0.994, 0.122)
local BAR_Y = 0.005

local CLOSE_BOX = UDim2.fromScale(0.09, 0.15) -- fitted square; see PANEL_BOX on why neither is 0

--[[ How far each of the three answers swells under a cursor, read off the `Scale` attribute by
	`UIController/Components/Button`. All three sit UNDER that component's 1.05 default for the reason
	its header gives: the kit's art already reacts on its own — the pills drop their face 6px in the
	image, the X swaps texture — and a full-strength nudge on top of that reads as the panel flinching.
	The X gets the largest of the three because it is the smallest shape on the screen and the same
	fraction of a 40px square is a movement nobody sees. ]]
local PILL_HOVER_SCALE = 1.03
local CLOSE_HOVER_SCALE = 1.08
local CLOSE_POS = UDim2.fromScale(0.955, 0.066)

local PROMPT_Y = 0.245
local FIELD_Y = 0.415
local FIELD_BOX = UDim2.fromScale(0.78, 0.15)
local COUNT_Y = 0.545
local STATUS_Y = 0.635
local BUTTON_Y = 0.80

--[[ SAVE is the answer, so it wears the kit's blue pill; USE MY NAME is the way back, so it wears
	the silver one and stands a little smaller. Both are the same 463x119 art, STRETCHED — see
	`pill` below for why a pill is never sliced. ]]
local SAVE_BOX = UDim2.fromScale(0.34, 0.15)
local SAVE_X = 0.30
local RESET_BOX = UDim2.fromScale(0.30, 0.13)
local RESET_X = 0.70

--[[ === THE FACE BUTTONS ARE THE ONLY WAY INTO THIS SCREEN ON A PAD ==========================

	A controller has no cursor, it has a SELECTION (`GuiService.SelectedObject`) — and this screen is
	nowhere a selection can reach. It is its own `ScreenGui`, and `Components/GamepadNav` only ever
	navigates inside `MainUI`; it raises `GamepadConfig.ModalAttribute`, which drops any highlight
	that is out and refuses to give another; and `AutoSelectGuiEnabled` is off game-wide, so the
	engine will not pick a button either. A binding here is therefore not one way to press SAVE, it is
	the ONLY one — and until 2026-08-20 the only binding was B.

	Which is the 16 Aug playtest's "Xbox: can't save changes to the sign", exactly as filmed: a name
	goes in, SAVE is pressed at, and the status line never says a word — because nothing was ever
	submitted. On that screen a console player could close the box and nothing else.

	A IS ONLY SAFE BECAUSE IT STANDS DOWN WHILE THE KEYBOARD IS UP, which was the original objection to
	binding it at all and it was the right one: typing on a console goes through Roblox's own
	on-screen keyboard, that keyboard owns the pad while it is up, and a second meaning for A
	underneath it is a button that does different things depending on something the player cannot see.

	SO THE TEST IS THE KEYBOARD ITSELF (`_syncAnswers`), not focus. Those are not the same condition
	and the difference is the whole bug over again: a platform that gives a focused box no keyboard —
	which is the shape this went wrong in once already — would leave a screen with nothing on it that
	can be pressed. Standing down needs BOTH, a focused field and a keyboard the engine says is
	visible; anything else and the three answers are live.

	Y REOPENS THE KEYBOARD, and that is not a convenience. Focus is taken ONCE, when the screen opens,
	and a pad cannot click the field to get it back — so without Y a console player gets exactly one
	attempt at the name and is then looking at a box they cannot edit, which is the other half of what
	the clip shows. Y is `DriveConfig.ExitKeys`' button and belongs to the seat while you are in one:
	a modal outranks the seat for as long as it is up (`PAD_PRIORITY`) and hands it straight back on
	the way down. X is every proximity prompt's button and is borrowed on the same terms. ]]
local PAD_CLOSE = "RenameClose"
local PAD_SAVE = "RenameSave"
local PAD_RESET = "RenameReset"
local PAD_EDIT = "RenameEdit"
local PAD_PRIORITY = Enum.ContextActionPriority.High.Value + 600

--[[ Where a badge hangs: outside the LEFT edge of the thing it presses, anchored on its own right so
	the gap stays the gap whatever size the glyph resolves to. Parented to that thing rather than
	measured onto the panel the way the revive screen's two are — a pill is a rectangle with a caption
	in the middle, which is a parent a badge can hang off, and one that moves with it. ]]
local ANSWER_ICON_POS = UDim2.fromScale(-0.03, 0.5)
local ANSWER_ICON_ANCHOR = Vector2.new(1, 0.5)
--- Everything that is not SAVE takes the smaller badge, in the proportion the X's already used.
local SMALL_ICON = GamepadConfig.Icon.Size * 0.72

-- === The kit's box (new UI) =================================================

--- Where `BuildRenameDealershipV2` leaves the template, and how long a boot waits for it before
--- warning and building the shipping box instead.
local SHELF_NAME = "Screens"
local KIT_TEMPLATE = "RenameDealership"
local KIT_WAIT = 10

--- The pop every V2 page opens and closes with (`UIController.openPage`), so the two arrive alike.
local KIT_START_SCALE = 0.9

--[[ A badge on a kit button's top-left corner, centred on it. See the header on why the kit's
	answers do not take the shipping box's left-hand badges. ]]
local KIT_ICON_POS = UDim2.fromScale(0.04, 0.12)
local KIT_ICON_ANCHOR = Vector2.new(0.5, 0.5)

--- A headshot as a `rbxthumb` URL, which the engine resolves without a web call from this script
--- (`Components/GiftPickerV2`'s reason).
local HEADSHOT_FORMAT = "rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"

local NBSP = utf8.char(0xA0)

local function oneLine(text: string): string
	return (string.gsub(string.upper(text), "%s+", NBSP))
end

-- === Building ===============================================================

--- 9-slice an ImageLabel/ImageButton from the recorded texture size and inset. Both come out of
--- `UIAssets`, which is measured against what Roblox STORED rather than against the PSD.
local function slice(image: ImageLabel | ImageButton, size: Vector2, inset: number)
	image.ScaleType = Enum.ScaleType.Slice
	image.SliceCenter = Rect.new(inset, inset, size.X - inset, size.Y - inset)
end

--[[ One pill button with its caption. The caption sits slightly high in the pill because the pressed
	art drops the face 6px: text centred in the box would stay put while the face moved out from
	under it.

	STRETCHED, NOT SLICED, and it was sliced until 2026-08-16 — which is what made this screen's two
	buttons read as fat lozenges rather than the rounded rectangle the artist drew. The aspect
	constraint below pins the button to the art's own 3.89:1, so the box only ever shrinks
	UNIFORMLY, and `Stretch` reproduces the drawing exactly. `Slice` pins the corners at texture
	pixels instead: SAVE renders 185x47 out of a 463x119 texture (0.40x), so its 22px corner curve
	stayed ~19px on a 47px-tall button — a radius of 0.39 of the height where the artist drew 0.19.
	See `UIAssets.Slice.Pill` for the rule and the arithmetic. ]]
local function pill(name: string, art, box: UDim2, x: number, text: string): ImageButton
	local button = Instance.new("ImageButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(x, BUTTON_Y)
	button.Size = box
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false -- the art has its own three states; Roblox's tint fights them
	button.Image = UIAssets.url(art.Idle)
	button.HoverImage = UIAssets.url(art.Hover)
	button.PressedImage = UIAssets.url(art.Pressed)
	button.ImageTransparency = 1
	button.ScaleType = Enum.ScaleType.Stretch

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = UIAssets.Size.Pill.X / UIAssets.Size.Pill.Y
	aspect.Parent = button

	local caption = Instance.new("TextLabel")
	caption.Name = "Label"
	caption.AnchorPoint = Vector2.new(0.5, 0.5)
	caption.Position = UDim2.fromScale(0.5, 0.46)
	caption.Size = UDim2.fromScale(0.78, 0.42)
	caption.BackgroundTransparency = 1
	caption.FontFace = FONT
	caption.Text = oneLine(text)
	caption.TextColor3 = WHITE
	caption.TextTransparency = 1
	caption.TextScaled = true
	caption.Parent = button

	return button
end

function RenameController._build(self)
	local gui = Instance.new("ScreenGui")
	gui.Name = "RenameDealership"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	--[[ Under WELCOME BACK's 998, the respawn screen's 999 and the race fade's 1000. It cannot
		collide with any of them — this only opens from a press on a world sign, which none of those
		three leave reachable — and ordering it below them costs nothing. ]]
	gui.DisplayOrder = 997
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	--[[ `Active` is what makes this modal. A Frame does not swallow input by default, so without it
		the HUD behind the dim is still clickable — and a player could start a race with a text box
		open over the road. ]]
	local scrim = Instance.new("Frame")
	scrim.Name = "Scrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = SCRIM_COLOR
	scrim.BackgroundTransparency = 1
	scrim.BorderSizePixel = 0
	scrim.Active = true
	scrim.Parent = gui

	local panel = Instance.new("ImageLabel")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = PANEL_BOX
	panel.BackgroundTransparency = 1
	panel.Image = UIAssets.url(UIAssets.Page.Panel)
	panel.ImageTransparency = 1
	slice(panel, UIAssets.Size.Panel, UIAssets.Slice.Panel)
	panel.Parent = scrim

	local panelAspect = Instance.new("UIAspectRatioConstraint")
	panelAspect.AspectRatio = UIAssets.Size.Panel.X / UIAssets.Size.Panel.Y
	panelAspect.Parent = panel

	local bar = Instance.new("ImageLabel")
	bar.Name = "TitleBar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.fromScale(0.5, BAR_Y)
	bar.Size = BAR_SIZE
	bar.BackgroundTransparency = 1
	bar.Image = UIAssets.url(UIAssets.DealerPanel.TitleBar)
	bar.ImageTransparency = 1
	-- Stretch: the cap's alpha is a plain rectangle, so there is no corner for a slice to protect and
	-- all it did was hold the painted rim at 1:1 texture pixels. See `TutorialController`'s bar.
	bar.ScaleType = Enum.ScaleType.Stretch
	bar.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.5)
	title.Size = UDim2.fromScale(0.8, 0.62)
	title.BackgroundTransparency = 1
	title.FontFace = FONT
	title.Text = oneLine(PlotConfig.Rename.Title)
	title.TextColor3 = WHITE
	title.TextTransparency = 1
	title.TextScaled = true
	title.Parent = bar

	local close = Instance.new("ImageButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = CLOSE_POS
	close.Size = CLOSE_BOX
	close.BackgroundTransparency = 1
	close.AutoButtonColor = false
	close.Image = UIAssets.url(UIAssets.Page.Close.Idle)
	close.HoverImage = UIAssets.url(UIAssets.Page.Close.Hover)
	close.PressedImage = UIAssets.url(UIAssets.Page.Close.Pressed)
	close.ImageTransparency = 1
	close.Parent = panel

	local closeAspect = Instance.new("UIAspectRatioConstraint")
	closeAspect.AspectRatio = UIAssets.Size.Close.X / UIAssets.Size.Close.Y
	closeAspect.Parent = close

	--[[ The one sentence on the screen, and it is doing a job rather than filling space: the whole
		reason this name is filtered at all is that it is PUBLIC, and a player who did not know that
		is a player who finds out from a moderation message. Dimmer than the field it introduces. ]]
	local prompt = Instance.new("TextLabel")
	prompt.Name = "Prompt"
	prompt.AnchorPoint = Vector2.new(0.5, 0.5)
	prompt.Position = UDim2.fromScale(0.5, PROMPT_Y)
	prompt.Size = UDim2.fromScale(0.84, 0.085)
	prompt.BackgroundTransparency = 1
	prompt.FontFace = FONT
	prompt.Text = PlotConfig.Rename.Prompt
	prompt.TextColor3 = WHITE
	prompt.TextTransparency = 1
	prompt.TextScaled = true
	prompt.Parent = panel

	--[[ The kit's search bar, doing the one job it is shaped for. 9-sliced rather than fitted to its
		own 18:1 aspect, which would be a hairline on this panel — a slice inset of 23px on a 56px
		tall texture leaves a 10px band to stretch, so it grows to a real input field with its ends
		intact. ]]
	local field = Instance.new("ImageLabel")
	field.Name = "Field"
	field.AnchorPoint = Vector2.new(0.5, 0.5)
	field.Position = UDim2.fromScale(0.5, FIELD_Y)
	field.Size = FIELD_BOX
	field.BackgroundTransparency = 1
	field.Image = UIAssets.url(UIAssets.Page.SearchBar)
	field.ImageTransparency = 1
	slice(field, UIAssets.Size.SearchBar, UIAssets.Slice.SearchBar)
	field.Parent = panel

	local box = Instance.new("TextBox")
	box.Name = "Input"
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromScale(0.88, 0.56)
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	--[[ OFF, so opening the box on a lot that already has a name puts that name in it to be edited
		rather than wiping it the moment they touch it. Renaming is usually a tweak. ]]
	box.ClearTextOnFocus = false
	box.MultiLine = false
	box.Text = ""
	box.PlaceholderText = PlotConfig.Rename.Placeholder
	box.PlaceholderColor3 = MUTED
	box.TextColor3 = WHITE
	box.TextTransparency = 1
	box.FontFace = FONT
	box.TextScaled = true
	box.TextXAlignment = Enum.TextXAlignment.Center
	box.Parent = field

	-- A ceiling on the text size, so a three-letter name is not set in a font twice the height of a
	-- twenty-letter one. `TextScaled` alone has no upper bound but the box.
	local boxSize = Instance.new("UITextSizeConstraint")
	boxSize.MaxTextSize = 40
	boxSize.MinTextSize = 12
	boxSize.Parent = box

	--[[ The character count. Right under the field's own right edge rather than centred, because it
		belongs to the box above it and not to the screen. ]]
	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.AnchorPoint = Vector2.new(1, 0.5)
	count.Position = UDim2.fromScale(0.5 + FIELD_BOX.X.Scale / 2, COUNT_Y)
	count.Size = UDim2.fromScale(0.16, 0.055)
	count.BackgroundTransparency = 1
	count.FontFace = FONT
	count.Text = ""
	count.TextColor3 = MUTED
	count.TextTransparency = 1
	count.TextScaled = true
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.Parent = panel

	--[[ The answer line. It is the only thing on this screen that ever says no, and it holds the
		space whether or not there is anything in it — a message that appeared and pushed the buttons
		down would move the thing the player is about to press. ]]
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0.5, 0.5)
	status.Position = UDim2.fromScale(0.5, STATUS_Y)
	status.Size = UDim2.fromScale(0.86, 0.085)
	status.BackgroundTransparency = 1
	status.FontFace = FONT
	status.Text = ""
	status.TextColor3 = WARN_AMBER
	status.TextTransparency = 1
	status.TextScaled = true
	status.Parent = panel

	local save = pill("Save", UIAssets.Pill.Blue, SAVE_BOX, SAVE_X, PlotConfig.Rename.ConfirmText)
	save.Parent = panel
	local reset = pill("Reset", UIAssets.Pill.Silver, RESET_BOX, RESET_X, PlotConfig.Rename.ResetText)
	reset.Parent = panel

	self._gui = gui
	self._scrim = scrim
	self._panel = panel
	self._bar = bar
	self._title = title
	self._close = close
	self._prompt = prompt
	self._field = field
	self._box = box
	self._count = count
	self._status = status
	self._save = save
	self._reset = reset

	self:_wire()

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	--[[ === ALL THREE ANSWERS ARE `UIButton`s ==================================================

		Which is how a pressable thing is declared in this project (`UIController/Components/Button`),
		and the tag is what owns the hover swell, the hover sound and the click sound — including the
		ones that are still silent, since the SoundService groups exist with blank ids and go audible
		the day the boss pastes ids in, with no change here.

		THE TAG CARRIES NO BEHAVIOUR ONTO THEM: none of the three has a `Page` or an `Action`
		attribute, so a press through `ButtonPress` plays its click and does nothing else. What SAVE,
		RESET and the X mean stays on the `Activated` wires in `_wire`, because all three are answers
		about a name this screen is still holding — state the UI layer knows nothing about. The
		welcome-back screen and the respawn screen are both arranged the same way.

		LAST, AND AFTER THE PARENTING, so the component reads a button whose geometry is final. ]]
	for button, hover in { [self._save] = PILL_HOVER_SCALE, [self._reset] = PILL_HOVER_SCALE, [self._close] = CLOSE_HOVER_SCALE } do
		button:SetAttribute("Scale", hover)
		CollectionService:AddTag(button, "UIButton")
	end
end

--[[ The box on the new UI: `Screens.RenameDealership` cloned over a scrim in a ScreenGui of this file's
	own. Returns false, having built nothing, when the template is not the shape
	`BuildRenameDealershipV2` makes, and `_buildAny` falls back to `_build`.

	IT SETS THE FIELDS `_build` SETS, pointed at the kit's parts, so `_wire`, `_submit`, the answer
	and the pad never ask which box they are in. `_bar` is the header and `_title` its caption.
	`_kit` is what `open` and `_hide` branch on, and it also carries `KitPage.bind`'s close. ]]
function RenameController._buildKit(self, template: GuiObject): boolean
	local panel = template:Clone()
	--- The kit's text caps are pixels for a 1080-tall screen; this keeps them in proportion above it.
	KitPage.scaleTextCaps(panel)
	local header = panel:FindFirstChild("Header")
	local main = panel:FindFirstChild("Main")
	local strip = main and main:FindFirstChild("Default")
	local ctas = main and main:FindFirstChild("CTAs")
	local field = ctas and ctas:FindFirstChild("Input")
	local parts = {
		title = header and header:FindFirstChild("Title"),
		prompt = main and main:FindFirstChild("Prompt"),
		status = main and main:FindFirstChild("Status"),
		box = field and field:FindFirstChildOfClass("TextBox"),
		count = field and field:FindFirstChild("Count"),
		save = ctas and ctas:FindFirstChild("SaveBtn"),
		reset = strip and strip:FindFirstChild("ResetBtn"),
		signName = strip and strip:FindFirstChild("SignName", true),
		headshot = strip and strip:FindFirstChild("Headshot", true),
	}
	local complete = header and field and field:IsA("GuiObject")
	for _, part in parts do
		complete = complete and part ~= nil
	end
	if not complete then
		warn("[RenameController] Screens.RenameDealership is not the shape BuildRenameDealershipV2 makes; using the old box. Re-run the command.")
		panel:Destroy()
		return false
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "RenameDealership"
	gui.ResetOnSpawn = false
	--- The shipping box's choice, so the dim covers the topbar. See the header.
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 997
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	--- `_build`'s scrim, for its reason: `Active` is what makes this modal.
	local scrim = Instance.new("Frame")
	scrim.Name = "Scrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = SCRIM_COLOR
	scrim.BackgroundTransparency = 1
	scrim.BorderSizePixel = 0
	scrim.Active = true
	scrim.Parent = gui

	--[[ The header, the close and the selection trap. `bind` shuts what it binds and wires the X to
		`onClose`; the panel is put back up because the SCRIM is what opens and closes here, and the
		close is re-pointed with an instance field, `GiftPickerV2`'s pattern. ]]
	local kit = KitPage.bind(panel)
	kit.onClose = function()
		self:_hide()
	end
	panel.Visible = true
	panel.Parent = scrim

	local scale = Instance.new("UIScale")
	scale.Name = "OpenScale"
	scale.Scale = KIT_START_SCALE
	scale.Parent = panel

	local box = parts.box :: TextBox
	box.ClearTextOnFocus = false
	box.MultiLine = false
	box.PlaceholderText = PlotConfig.Rename.Placeholder
	-- Native iPad editing can omit the outline, leaving white input invisible on the white field.
	box.TextColor3 = Color3.fromRGB(2, 30, 56)
	box.TextTransparency = 0
	box.TextStrokeTransparency = 1
	box.RichText = false
	for _, child in box:GetChildren() do
		if child:IsA("UIStroke") then
			child.Enabled = false
		end
	end

	parts.title.Text = oneLine(PlotConfig.Rename.Title)
	parts.prompt.Text = PlotConfig.Rename.Prompt
	parts.status.Text = ""
	for key, text in { save = PlotConfig.Rename.ConfirmText, reset = PlotConfig.Rename.ResetText } do
		local label = parts[key]:FindFirstChild("Title")
		if label and label:IsA("TextLabel") then
			label.Text = oneLine(text)
		end
	end

	self._gui = gui
	self._scrim = scrim
	self._panel = panel
	self._bar = header
	self._title = parts.title
	self._close = kit.CloseBtn
	self._prompt = parts.prompt
	self._field = field
	self._box = box
	self._count = parts.count
	self._status = parts.status
	self._save = parts.save
	self._reset = parts.reset
	self._kit = kit
	self._kitScale = scale
	self._signName = parts.signName
	self._headshot = parts.headshot

	self:_wire()

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return true
end

--[[ The kit's box when the new UI is on and its template is in the place, the shipping box otherwise.

	The wait is bounded (`KIT_WAIT`) on every step and warns, so a place that never got
	`BuildRenameDealershipV2` still opens a rename box, in the old look, and says why. ]]
function RenameController._buildAny(self)
	if UIRoot.isNewUI() then
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local root = UIRoot.wait(playerGui :: PlayerGui, KIT_WAIT)
		local shelf = root and root:WaitForChild(SHELF_NAME, KIT_WAIT)
		local template = shelf and shelf:WaitForChild(KIT_TEMPLATE, KIT_WAIT)
		if template and template:IsA("GuiObject") and self:_buildKit(template) then
			return
		end
		if not template then
			warn(string.format("[RenameController] No %s.%s.%s in this place; using the old box. Run BuildRenameDealershipV2.", UIRoot.name(), SHELF_NAME, KIT_TEMPLATE))
		end
	end
	self:_build()
end

function RenameController._wire(self)
	self._save.Activated:Connect(function()
		self:_submit(self._box.Text)
	end)
	--[[ RESET sends an empty string, which is a real request the server understands rather than a
		second remote: `PlotConfig.sanitize` returns "" with no error and `_onRename` reads that as
		"put the sign back to my own name". ]]
	self._reset.Activated:Connect(function()
		self:_submit("")
	end)
	--- The kit's X is already wired, by `KitPage.bind`, to `_hide`.
	if not self._kit then
		self._close.Activated:Connect(function()
			self:_hide()
		end)
	end

	--[[ Enter submits, which is what a text field is expected to do. `FocusLost` fires on any way out
		of the box — clicking SAVE also drops focus first — so the flag is what separates "they
		pressed Return" from "they clicked something else", and only the first one submits.

		BOTH ENDS OF THE FOCUS ALSO MOVE THE PAD'S ANSWER KEYS, along with the keyboard's own
		visibility — see `_syncAnswers`, which is the one place that decides. Three signals rather
		than one because no single one of them is the whole condition: a console commit and a console
		cancel both arrive here as `FocusLost`, and neither is the enter flag.

		RESYNCED BEFORE THE SUBMIT, not after: a submit that succeeds closes the screen, and `_hide`
		takes all three off again on its way down. The other order would put bindings back onto a
		screen that had already gone. ]]
	self._box.Focused:Connect(function()
		self:_syncAnswers()
	end)
	self._box.FocusLost:Connect(function(enterPressed: boolean)
		self:_syncAnswers()
		if enterPressed then
			self:_submit(self._box.Text)
		end
	end)

	--[[ The keyboard coming and going without the focus changing — which is every console commit, and
		a phone dismissing its keyboard with the field still focused. ]]
	UserInputService:GetPropertyChangedSignal("OnScreenKeyboardVisible"):Connect(function()
		self:_syncAnswers()
	end)

	--[[ The ceiling is enforced HERE rather than left to the SAVE press, because a player who typed
		thirty characters and is told to delete ten has already done work the box could have refused.
		Trimming re-fires this signal, which is harmless: the second pass is already at the limit. ]]
	self._box:GetPropertyChangedSignal("Text"):Connect(function()
		self:_onTyped()
	end)
end

-- === The answer =============================================================

function RenameController._say(self, message: string?, ok: boolean?)
	self._status.Text = message or ""
	self._status.TextColor3 = if ok then OK_GREEN else WARN_AMBER
end

--- Keep the box inside the length the sign can show, and keep the counter honest.
function RenameController._onTyped(self)
	local max = PlotConfig.Rename.MaxLength
	local text = self._box.Text
	local length = utf8.len(text) or #text

	if length > max then
		-- By grapheme rather than by byte: `string.sub` on a multi-byte character would leave half
		-- of one behind, which Roblox renders as a replacement glyph.
		local offset = utf8.offset(text, max + 1)
		self._box.Text = if offset then string.sub(text, 1, offset - 1) else string.sub(text, 1, max)
		return -- the write above re-enters here with the trimmed text
	end

	self._count.Text = string.format(PlotConfig.Rename.CountFormat, length, max)
end

--[[ Ask the server. Refuses locally first, for everything a local copy of the rules CAN decide.

	THE LOCK IS THE WHOLE OF IT, the same as the welcome-back screen's: between the press and the
	answer there are frames in which a button that still looks live is still live, and a second
	press would spend this player's rename cooldown on a duplicate of the request already in
	flight — so the second one comes back "give it a second" and the screen would report a refusal
	for a name that was, at that moment, being accepted. ]]
function RenameController._submit(self, text: string)
	if self._pending or not self._open then
		return
	end

	local clean, err = PlotConfig.sanitize(text)
	if not clean then
		self:_say(err, false)
		return
	end

	self._pending = true
	self:_say(nil)
	self:getRemoteEvent("RequestDealershipName"):Fire(clean)

	local token = self._token
	task.delay(REPLY_TIMEOUT, function()
		if self._open and self._pending and self._token == token then
			self._pending = false
			self:_say(PlotConfig.Rename.Messages.FilterFailed, false)
		end
	end)
end

--- The server's verdict. A refusal leaves the screen open with the text still in the box, so the
--- name can be edited rather than retyped; a save shows for a beat and closes.
function RenameController._onResult(self, ok: unknown, message: unknown)
	if not self._open then
		return
	end
	self._pending = false
	self:_say(if type(message) == "string" then message else nil, ok == true)

	if ok ~= true then
		return
	end
	--[[ `_pending` is re-checked on the far side of the hold, not just the token: a player who typed
		a second name inside those 0.7 seconds has a request in flight, and closing on the previous
		one's success would throw away an answer they are waiting for. ]]
	local token = self._token
	task.delay(CONFIRM_HOLD, function()
		if self._open and not self._pending and self._token == token then
			self:_hide()
		end
	end)
end

-- === Show / hide ============================================================

--- Put the screen up with `current` in the box — the name this lot already has, or nil for a lot
--- that has never been named. Called by `DealershipSignController` and by nothing else.
function RenameController.open(self, current: string?)
	if not PlotConfig.Rename.Enabled then
		return
	end
	if not self._gui then
		self:_buildAny()
	end
	if self._open then
		return
	end

	self._open = true
	self._pending = false
	self._token += 1

	self._box.Text = if type(current) == "string" then current else ""
	self:_onTyped()
	self:_say(nil)

	if self._kit then
		self:_raiseKit()
	else
		self:_raise()
	end

	self:_bindPad(true)

	--[[ Focus is taken once the panel is actually there, not as it starts fading in. On a phone
		`CaptureFocus` is what raises the on-screen keyboard, and raising it over a panel that has not
		arrived yet looks like the keyboard opened on its own. ]]
	local token = self._token
	task.delay(RAISE_TIME * 0.6, function()
		if self._open and self._token == token then
			self._box:CaptureFocus()
		end
	end)
end

--[[ The kit box's entrance: the scrim settles as the shipping one does and the panel swells in from
	`KIT_START_SCALE`, the V2 pages' open. The strip is filled first, because what USE MY NAME puts
	back is the player's own display name and that can change between two opens. ]]
function RenameController._raiseKit(self)
	local player = Players.LocalPlayer
	self._signName.Text = PlotConfig.oneLine(PlotConfig.defaultTitle(player.DisplayName, player.Name))
	self._headshot.Image = string.format(HEADSHOT_FORMAT, player.UserId)

	self._kitScale.Scale = KIT_START_SCALE
	self._gui.Enabled = true
	self:_tween(self._scrim, RAISE_TIME, { BackgroundTransparency = SCRIM_REST })
	local tween = TweenService:Create(self._kitScale, TweenInfo.new(RAISE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	tween:Play()
end

--- The shipping box's entrance: every part fades up from nothing.
function RenameController._raise(self)
	self._gui.Enabled = true
	self:_tween(self._scrim, RAISE_TIME, { BackgroundTransparency = SCRIM_REST })
	self:_tween(self._panel, RAISE_TIME, { ImageTransparency = 0 })
	self:_tween(self._bar, RAISE_TIME, { ImageTransparency = 0 })
	self:_tween(self._title, RAISE_TIME, { TextTransparency = 0 })
	self:_tween(self._close, RAISE_TIME, { ImageTransparency = 0 })
	-- The prompt rests dimmer than the field: it is the caption, not the content.
	self:_tween(self._prompt, RAISE_TIME, { TextTransparency = 0.25 })
	self:_tween(self._field, RAISE_TIME, { ImageTransparency = 0 })
	self:_tween(self._box, RAISE_TIME, { TextTransparency = 0 })
	self:_tween(self._count, RAISE_TIME, { TextTransparency = 0.2 })
	self:_tween(self._status, RAISE_TIME, { TextTransparency = 0 })
	for _, button in { self._save, self._reset } do
		self:_tween(button, RAISE_TIME, { ImageTransparency = 0 })
		self:_tween(button.Label, RAISE_TIME, { TextTransparency = 0 })
	end
end

function RenameController._hide(self)
	if not (self._gui and self._open) then
		return
	end
	self._open = false
	self._pending = false
	local token = self._token

	self._box:ReleaseFocus()
	self:_bindPad(false)

	local last = if self._kit then self:_lowerKit() else self:_lower()

	last.Completed:Once(function()
		-- Fenced on the token so the tail of a screen that has already been reopened cannot switch
		-- the new one off.
		if self._token == token and not self._open then
			self._gui.Enabled = false
		end
	end)
end

--- The kit box's exit, the V2 pages' close: a quick settle back to `KIT_START_SCALE` under a scrim
--- fading out on the same clock. Answers the tween `_hide` waits on.
function RenameController._lowerKit(self)
	self:_tween(self._scrim, DROP_TIME, { BackgroundTransparency = 1 })
	local tween = TweenService:Create(self._kitScale, TweenInfo.new(DROP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = KIT_START_SCALE })
	tween:Play()
	return tween
end

--- The shipping box's exit: every part fades back to nothing. Answers the last tween.
function RenameController._lower(self)
	self:_tween(self._scrim, DROP_TIME, { BackgroundTransparency = 1 })
	self:_tween(self._panel, DROP_TIME, { ImageTransparency = 1 })
	self:_tween(self._bar, DROP_TIME, { ImageTransparency = 1 })
	self:_tween(self._title, DROP_TIME, { TextTransparency = 1 })
	self:_tween(self._close, DROP_TIME, { ImageTransparency = 1 })
	self:_tween(self._prompt, DROP_TIME, { TextTransparency = 1 })
	self:_tween(self._field, DROP_TIME, { ImageTransparency = 1 })
	self:_tween(self._box, DROP_TIME, { TextTransparency = 1 })
	self:_tween(self._count, DROP_TIME, { TextTransparency = 1 })
	self:_tween(self._save, DROP_TIME, { ImageTransparency = 1 })
	self:_tween(self._save.Label, DROP_TIME, { TextTransparency = 1 })
	self:_tween(self._reset, DROP_TIME, { ImageTransparency = 1 })
	self:_tween(self._reset.Label, DROP_TIME, { TextTransparency = 1 })
	return self:_tween(self._status, DROP_TIME, { TextTransparency = 1 })
end

function RenameController._tween(self, inst, time: number, props)
	local tween = TweenService:Create(inst, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

--- B, live for as long as the screen is: the one key the on-screen keyboard never takes.
function RenameController._bindPad(self, on: boolean)
	GamepadInput.setModal("RenameController", on)

	if not on then
		GamepadInput.unbind(PAD_CLOSE)
		self:_bindAnswers(false)
		return
	end

	GamepadInput.bind({
		actionName = PAD_CLOSE,
		keyCode = Enum.KeyCode.ButtonB,
		callback = function()
			self:_hide()
		end,
		parent = self._close,
		iconPosition = UDim2.fromScale(0.5, 1.35),
		iconAnchor = Vector2.new(0.5, 0.5),
		iconSize = SMALL_ICON,
		priority = PAD_PRIORITY,
	})

	self:_syncAnswers()
end

--[[ THE ONE PLACE THAT DECIDES whether the pad can answer this screen: it can, unless Roblox's own
	on-screen keyboard is up over the field it belongs to. See the block at `PAD_CLOSE` for why the
	test is the keyboard AND the focus rather than either alone.

	Called from everything that can change that answer — the screen opening and closing, the field
	gaining and losing focus, the keyboard showing and hiding — rather than each of those working out
	the state for itself. ]]
function RenameController._syncAnswers(self)
	local typing = UserInputService.OnScreenKeyboardVisible and self._box ~= nil and self._box:IsFocused()
	self:_bindAnswers(self._open == true and not typing)
end

--[[ SAVE, USE MY NAME, and "let me type that again" — the three that share the pad with Roblox's own
	keyboard, so they exist exactly when it does not. Driven by `_syncAnswers` and by nothing else.

	Each badge hangs off the thing it presses, so the answer and the glyph cannot drift apart, and
	`GamepadInput` hides all three by itself the moment the player puts the controller down. ]]
function RenameController._bindAnswers(self, on: boolean)
	if not (on and self._gui) then
		GamepadInput.unbind(PAD_SAVE)
		GamepadInput.unbind(PAD_RESET)
		GamepadInput.unbind(PAD_EDIT)
		return
	end

	--- On the kit's corners rather than off the left edges; see the header.
	local iconPosition = if self._kit then KIT_ICON_POS else ANSWER_ICON_POS
	local iconAnchor = if self._kit then KIT_ICON_ANCHOR else ANSWER_ICON_ANCHOR

	GamepadInput.bind({
		actionName = PAD_SAVE,
		keyCode = Enum.KeyCode.ButtonA,
		callback = function()
			self:_submit(self._box.Text)
		end,
		parent = self._save,
		iconPosition = iconPosition,
		iconAnchor = iconAnchor,
		priority = PAD_PRIORITY,
	})

	GamepadInput.bind({
		actionName = PAD_RESET,
		keyCode = Enum.KeyCode.ButtonX,
		callback = function()
			self:_submit("")
		end,
		parent = self._reset,
		iconPosition = iconPosition,
		iconAnchor = iconAnchor,
		-- Smaller, like the answer it belongs to: USE MY NAME is not a competing target.
		iconSize = SMALL_ICON,
		priority = PAD_PRIORITY,
	})

	--[[ The only way back into the field on a pad. Refused while a request is in flight for the same
		reason SAVE is (`_submit`'s own lock): the screen is holding a name it has asked about, and a
		keyboard opening over that answer would be editing a question already gone. ]]
	GamepadInput.bind({
		actionName = PAD_EDIT,
		keyCode = Enum.KeyCode.ButtonY,
		callback = function()
			if self._open and not self._pending then
				self._box:CaptureFocus()
			end
		end,
		parent = self._field,
		iconPosition = iconPosition,
		iconAnchor = iconAnchor,
		iconSize = SMALL_ICON,
		priority = PAD_PRIORITY,
	})
end

-- === The controller =========================================================

--- Is the box up? `DealershipSignController` asks before opening it a second time.
function RenameController.isOpen(self): boolean
	return self._open == true
end

RenameController:withRemoteEvents({
	-- client -> server (name): SAVE, or RESET's empty string.
	"RequestDealershipName",
	{
		DealershipNameResult = function(ok: unknown, message: unknown)
			RenameController:_onResult(ok, message)
		end,
	},
})

RenameController:withLifecycle({
	init = function(self)
		self._open = false
		self._pending = false
		self._token = 0
	end,

	--[[ BUILT AT START, NOT ON THE FIRST PRESS. `_build` yields on PlayerGui, and a panel assembled
		inside the pencil's click handler would be assembled after the click that wanted it — the
		same reason `OfflineController` builds before it pings the server. On the new UI that includes
		the bounded wait for the kit's template. ]]
	start = function(self)
		if not (PlotConfig.Enabled and PlotConfig.Rename.Enabled) then
			return
		end
		self:_buildAny()
	end,
})

return RenameController
