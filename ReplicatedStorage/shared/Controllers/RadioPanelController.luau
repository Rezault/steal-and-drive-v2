--[[
	RadioPanelController  (client)
	------------------------------
	The screen you pick a station on. Opened by the RADIO button in the topbar
	(`TopbarController`) on the old UI. On the new UI it is the grid's Radio cell in the lobby (a
	`UIAction` carrying `RadioConfig.PanelAction`, answered in `start` below) and the topbar chip
	only for a race, when the grid is hidden.

	IT IS BUILT IN CODE OUT OF THE KIT'S OWN ART, the same third way of drawing UI that
	`OfflineController` and `RenameController` use — see the latter's header for the full reasoning.
	The short version: the artist drew no radio panel, but the kit's panel, title cap, search bar,
	close button and pills are all uploaded and documented in `UIAssets`, so this is assembled from
	those rather than drawn from scratch. Nothing new was uploaded for this screen and no colour on
	it was eyeballed.

	NOT A `UIController` PAGE, for that screen's reason: every page is opened by a tagged button
	carrying a `Page` attribute, and the thing that opens this is an icon in Roblox's own topbar.
	Making it a page would mean inventing the one page nothing in `MainUI` can open.

	THE BLUE CAP, and by elimination rather than by taste: `Page.TitleBar` comes in three colours
	and each is the identity of one rail page (orange INDEX, red QUESTS, green MARKET — and green is
	also WELCOME BACK). The radio is none of them, so it takes the dealership panel's woven blue,
	which is the same cap the rename box takes and for the same reason.

	=== IT DECIDES NOTHING, IN EITHER DIRECTION ================================

	NOT WHAT IS PLAYING. The station on this screen is read off the player's own car through
	`RadioController:station()`, and a press sends a request and then waits — no button paints
	itself as chosen on the way to being refused. That is the same no-optimistic-repaint rule the
	upgrade boards and the teleport screen follow, and here it is also the only thing that could
	work: the car's attributes ARE the sound, so a locally-applied station would be a client playing
	music it had not been given permission for.

	NOT WHETHER THE PASS IS OWNED. `RadioConfig.OwnedAttribute` is the server's answer and this
	draws whatever it says — including the third state, `nil`, which is "Roblox has not answered
	yet" and is NOT the same as "no". Drawing an unanswered pass as unowned would offer to sell the
	radio to somebody who already has it, every join, for as long as the web call takes.

	=== WHY THE CUSTOM BOX IS THE SECOND THING ON IT ===========================

	Because most audio ids do not work — `RadioConfig`'s header has the whole of it. Since Roblox's
	2022 privacy change an upload is private to its creator unless they publish it, so the classic
	"paste any id" boombox fails for most ids, and fails SILENTLY. The four stations are therefore
	what the pass sells and the box is the extra: a new owner who presses the first thing they see
	hears music, and a player who does paste an id gets a sentence back about why it will not play
	rather than a car that sits there making no noise.

	=== ON THE NEW UI THE PANEL IS THE CARTOONY KIT'S =============================================

	With `NewUIConfig` on, the panel is the kit's settings list rather than the pills built below:
	`BuildCarRadioV2` authors it on the hidden `MainUIV2.Screens` shelf and `_buildKit` clones it
	into this file's own `CarRadio` ScreenGui at the same 996. That command's header has the rows.

	EVERYTHING ABOVE STILL HOLDS ON IT, word for word: the station is read off the car, a press asks
	and waits, the pass has three states and the unanswered one never shows a price. What changes is
	the shape (a row per station with Play or On air, the paste box on a row, the whole radio and the
	soundtrack on rows of their own) and the four methods that draw it, which branch on `self._kit`.
	The listening (`_listen`) and every answer (`_choose`, `_submitCustom`, `_pressAction`) are
	shared. With the flag off, none of the kit code runs.
]]

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local GamepadConfig = require(ReplicatedStorage.shared.Configs.GamepadConfig)
local LobbyCarConfig = require(ReplicatedStorage.shared.Configs.LobbyCarConfig)
local MusicConfig = require(ReplicatedStorage.shared.Configs.MusicConfig)
local RadioConfig = require(ReplicatedStorage.shared.Configs.RadioConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local GamepadInput = require(ReplicatedStorage.shared.Modules.GamepadInput)
local LivePrice = require(ReplicatedStorage.shared.Modules.LivePrice)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)
--- By `script.Parent`: at runtime the controllers live under PlayerScripts, not ReplicatedStorage.
local KitPage = require(script.Parent.UIController.KitPage)

local RadioPanelController = Shard.new("RadioPanelController")

-- === Look & feel ============================================================
-- Fractions throughout — of the screen for the panel, of the PANEL for everything in it — so the
-- layout is one object that scales rather than a set of positions that agree at 1080p.

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)
local WHITE = Color3.fromRGB(255, 255, 255)
-- The kit's panel stroke, reused for anything that is furniture rather than content. Same colour
-- and the same meaning as `RenameController`'s `MUTED`.
local MUTED = Color3.fromRGB(135, 146, 181)
-- Amber for a refusal, green for a confirmation. The same two `OfflineController` and the rename
-- box use for the same two meanings — a refusal here is the screen answering, not an error state.
local WARN_AMBER = Color3.fromRGB(240, 178, 74)
local OK_GREEN = Color3.fromRGB(126, 217, 87)

local SCRIM_COLOR = Color3.fromRGB(6, 8, 12)
local SCRIM_REST = 0.45
local RAISE_TIME = 0.28
local DROP_TIME = 0.18

--[[ The panel, as a box the aspect constraint FITS INSIDE — both numbers are maximums, not the
	size. A REAL BOX ON BOTH AXES, never a zero: `UIAspectRatioConstraint` defaults to
	FitWithinMaxSize and collapses a zero-width element to 0x0 rather than solving for the aspect,
	which is a trap this project has already paid for once. ]]
local PANEL_BOX = UDim2.fromScale(0.82, 0.62)

-- The cap's two numbers are measured out of the PSD rather than chosen — 1788 x 138 against a
-- 1798 x 1132 panel, so 99.4% wide and 12.2% tall, flush. Same as every other code-built panel.
local BAR_SIZE = UDim2.fromScale(0.994, 0.122)
local BAR_Y = 0.005

local CLOSE_BOX = UDim2.fromScale(0.075, 0.13) -- fitted square; see PANEL_BOX on why neither is 0
local CLOSE_POS = UDim2.fromScale(0.958, 0.072)

--[[ How far each thing swells under a cursor, read off the `Scale` attribute by
	`UIController/Components/Button`. All of them sit UNDER that component's 1.05 default for the
	reason its header gives — the kit's art already reacts on its own, and a full-strength nudge on
	top of that reads as the panel flinching. The X gets the largest because it is the smallest
	shape on screen and the same fraction of a 40px square is a movement nobody sees. ]]
local PILL_HOVER_SCALE = 1.03
local CLOSE_HOVER_SCALE = 1.08

--[[ The line under the title. Smaller than the title on purpose: it used to be the largest type on
	the panel, and a caption that outshouts the heading makes the whole screen read as loud. ]]
local NOW_PLAYING_Y = 0.2
local NOW_PLAYING_BOX = UDim2.fromScale(0.86, 0.055)

--[[ === ONE GRID ================================================================================

	EVERY ROW UNDER THE TITLE HANGS OFF THE SAME TWO EDGES, which is most of what makes this screen
	read as tidy. The stations fill the grid exactly; the custom row runs edge to edge with PLAY on
	the right; the bottom row puts OFF on the left edge and MUSIC on the right, directly under PLAY
	and the same size. Before this, each row had its own margins and PLAY was a third the height of
	the field beside it.

	THE PILLS ARE BUILT AT THEIR OWN SHAPE rather than left for the aspect constraint to shrink into
	a box, because a pill whose box is wider than the pill is a pill whose edges cannot be lined up
	with anything. `pillWidth` turns a height into the width the art will actually draw at. ]]
local PANEL_ASPECT = UIAssets.Size.Panel.X / UIAssets.Size.Panel.Y
local PILL_ASPECT = UIAssets.Size.Pill.X / UIAssets.Size.Pill.Y

local function pillWidth(height: number): number
	return height * PILL_ASPECT / PANEL_ASPECT
end

local GRID_LEFT, GRID_RIGHT = 0.11, 0.89
-- The gap between station rows, and the same number of PIXELS between the columns.
local GAP = 0.035
local GUTTER = GAP / PANEL_ASPECT

--[[ The four stations, as a 2x2 of pills. Two columns rather than a single list because four
	shoulder-height rows in a landscape panel leaves the whole right-hand half empty, and because a
	station is a CHOICE — a grid reads as four things to pick between, where a column reads as a
	list to scroll. ]]
local STATION_W = (GRID_RIGHT - GRID_LEFT - GUTTER) / 2
local STATION_BOX = UDim2.fromScale(STATION_W, STATION_W * PANEL_ASPECT / PILL_ASPECT)
local STATION_X = { GRID_LEFT + STATION_W / 2, GRID_RIGHT - STATION_W / 2 }
local STATION_Y = { 0.352, 0.352 + STATION_BOX.Y.Scale + GAP }

--[[ EVERY STATION IS BLUE, the kit's own colour, and which one is playing is said by the face
	coming forward (`_paint`). It used to be one colour per station, and four colours plus PLAY's
	green, OFF's silver and a purple MUSIC made seven on one screen: the selection was the one thing
	the rainbow hid, since a bright purple and a dimmed orange do not read as "on" and "off". ]]
local STATION_PILL = UIAssets.Pill.Blue

-- The custom row and the bottom row share one height, so PLAY and MUSIC are the same pill stacked.
local ROW_H = 0.115
local ROW_W = pillWidth(ROW_H)

local FIELD_Y = 0.728
local FIELD_BOX = UDim2.fromScale(GRID_RIGHT - GRID_LEFT - ROW_W - GUTTER, ROW_H)
local FIELD_X = GRID_LEFT + FIELD_BOX.X.Scale / 2
local PLAY_BOX = UDim2.fromScale(ROW_W, ROW_H)
local PLAY_X = GRID_RIGHT - ROW_W / 2

--[[ THE ANSWER LINE GETS ITS OWN ROW, full width, above the button rather than beside it. It was
	beside it once and that was wrong twice over: the longest sentence it can hold ("that track is
	private — only its uploader can play it") ran straight through the pill, and shrinking the label
	to fit would have made the one thing on this screen that has something to say the smallest thing
	on it. A row of its own costs 6% of the panel's height and nothing else. ]]
local STATUS_Y = 0.816
local STATUS_BOX = UDim2.fromScale(0.86, 0.05)

--[[ THE BOTTOM ROW IS THE TWO SWITCHES: the radio as a whole on the left, and the soundtrack on the
	right. Everything above it picks a station; this row is what is playing AT ALL.

	THE MUSIC ONE MOVED HERE FROM THE TOPBAR on 2026-08-27. It was the game's first topbar icon and
	its new home is this panel for one reason: this is the screen a player thinking about sound is
	already on, and a game whose every noise is settled under one title bar is easier to explain than
	one where the soundtrack is a glyph in Roblox's strip and the car radio is a panel. What it left
	behind is the slot the settings button now sits in. `TopbarController`'s header has the swap,
	including the one case where the old icon is still built.

	IT IS THE SOUNDTRACK AND NOT THE CAR. Worth keeping straight, because they are two feet apart on
	this screen: the stations above make the player's own CAR play music that everybody nearby hears,
	and this mutes the game's background score for this player alone. `MusicConfig` note 6 is the
	full division, and it is why the pill says MUSIC rather than SOUND.

	A CENTRED SINGLE BUTTON WHEN THERE IS NO SOUNDTRACK, which is `MusicConfig.Enabled` off: the row
	is then one switch and it belongs in the middle, exactly where it was before this pill existed. ]]
local ACTION_Y = 0.905
local ACTION_BOX = UDim2.fromScale(ROW_W, ROW_H)
local ACTION_X_ALONE = 0.5
local ACTION_X_PAIRED = GRID_LEFT + ROW_W / 2
local MUSIC_X = PLAY_X

--- B, and only B. See `_bindPad`.
local PAD_CLOSE = "RadioClose"
local PAD_PRIORITY = Enum.ContextActionPriority.High.Value + 600
local SMALL_ICON = GamepadConfig.Icon.Size * 0.72

local NBSP = utf8.char(0xA0)

--- Pill captions are set in one line: the art is a lozenge and a caption that wrapped would be
--- centred against a box the words no longer fit in.
local function oneLine(text: string): string
	return (string.gsub(string.upper(text), "%s+", NBSP))
end

--[[ The kit's label outline, which every white caption in the PSD wears and the Quest page's labels
	carry. It is what keeps OFF and MUSIC legible on the pale silver pill, where plain white was
	barely there.

	`Contextual`, so it darkens the edge of a letter without fattening it at phone resolutions (the
	reason `RandomCarController.outline` gives). Built hidden, like the caption it sits on. ]]
local OUTLINE = Color3.fromRGB(21, 29, 45) -- #151D2D
local OUTLINE_THICKNESS = 2

--[[ How much of a fade the outline gets. It LEAVES FIRST AND ARRIVES LAST: a stroke is drawn under
	the whole glyph, so a half-faded letter over a half-faded stroke reads as a grey smudge, and a
	dark ring outlasts white letters on the way out. Same number as `NearMissConfig.Ui.StrokeFade`. ]]
local STROKE_SHARE = 0.5

local function outline(label: TextLabel)
	local stroke = Instance.new("UIStroke")
	stroke.Color = OUTLINE
	stroke.Thickness = OUTLINE_THICKNESS
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Transparency = 1
	stroke.Parent = label
end

--- A caption's resting transparency, with its outline kept in step.
local function setAlpha(label: Instance?, transparency: number)
	if not (label and label:IsA("TextLabel")) then
		return
	end
	label.TextTransparency = transparency
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = transparency
	end
end

-- === The new UI's panel =====================================================
-- Everything in this block is for `_buildKit` and the kit half of the drawing. See the header.

--- Where the template is authored, and how long to wait for it. The wait is for the shelf
--- replicating at join, which lands long before anybody reaches the topbar, so it is a fence
--- rather than a budget.
local KIT_SHELF = "Screens"
local KIT_TEMPLATE = "CarRadio"
local KIT_WAIT = 10

--- The row templates `BuildCarRadioV2` makes, by what goes on them.
local NOTE_ROW = "NoteTemplate"
local STATION_ROW = "StationTemplate"
local INPUT_ROW = "InputTemplate"
local RADIO_ROW = "RadioTemplate"
local MUSIC_ROW = "ToggleTemplate"

--[[ The open and close every V2 page has (`UIController.openPage`): a swell out of 0.9 on the
	panel's own `UIScale`, and a quicker drop back. The scrim keeps this file's own fade, because a
	page has no scrim to borrow one from. ]]
local KIT_OPEN = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local KIT_CLOSE = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local KIT_START_SCALE = 0.9

--[[ THE KIT PANEL'S DIM SITS UNDER THE HUD, not over it (Dylan, 2026-09-17). The world goes dark
	while the radio is up, but the grid, the cash and the topbar stay lit and pressable, the way they
	are while a page is open. So the scrim is a ScreenGui of its own one `DisplayOrder` below the new
	UI's root, rather than a frame in the panel's 996 gui, which dimmed the HUD and swallowed every
	press on it. It ignores the inset, so it covers the strip behind the topbar too. ]]
local KIT_SHADE_NAME = "CarRadioShade"
local KIT_SHADE_BELOW_HUD = 1

--- The name the kit panel asks `RaceEntryController` to move the Play button under while it is open.
local PLAY_ROOM_SOURCE = "Radio"

--- The kit's rows have names, where the shipping pills did not, so these are the words the kit panel
--- says that `RadioConfig.Copy` has no entry for.
local KIT_COPY = {
	OnAir = "On air",
	Radio = "Radio",
	Music = "Music",
}

--- The kit's own Robux mark (U+E002), which is how the V2 shop prints a price.
local ROBUX = utf8.char(0xE002)

--- Hover swell for the kit's row buttons, the HUD grid's 1.03. The X keeps `CLOSE_HOVER_SCALE`.
local KIT_ROW_HOVER_SCALE = 1.03

--[[ A kit caption on one line, in the words' own case. `oneLine` above is for the pills, which set
	everything in capitals; the kit sets its rows and buttons as written ("Setting Name", "Yeah,
	Sure!"). Non-breaking for the reason `oneLine` gives. ]]
local function kitLine(text: string): string
	return (string.gsub(text, "%s+", NBSP))
end

--- A kit button's caption.
local function setCaption(button: Instance?, text: string)
	local title = button and button:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = kitLine(text)
	end
end

--- `root.A.B`, or nil at the first missing step.
local function find(root: Instance?, path: string): Instance?
	local node = root
	for step in string.gmatch(path, "[^%.]+") do
		node = node and node:FindFirstChild(step)
	end
	return node
end

-- === Building ===============================================================

--- 9-slice an ImageLabel/ImageButton from the recorded texture size and inset. Both come out of
--- `UIAssets`, which is measured against what Roblox STORED rather than against the PSD.
local function slice(image: ImageLabel | ImageButton, size: Vector2, inset: number)
	image.ScaleType = Enum.ScaleType.Slice
	image.SliceCenter = Rect.new(inset, inset, size.X - inset, size.Y - inset)
end

--[[ One pill button with its caption, and optionally a smaller second line under it.

	STRETCHED, NOT SLICED. `UIAssets.Slice`'s "WHY NO PILL IS EVER 9-SLICED" block is the whole
	argument: the aspect constraint pins the button to the art's own 3.89:1 so it only ever shrinks
	uniformly, and `Stretch` reproduces the artist's proportion exactly, where `Slice` holds the
	corner curve at texture pixels and turns a small pill into a lozenge.

	The caption sits slightly high in the pill because the pressed art drops the face 6px: text
	centred in the box would stay put while the face moved out from under it. ]]
local function pill(name: string, art, box: UDim2, x: number, y: number, text: string, sub: string?): ImageButton
	local button = Instance.new("ImageButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(x, y)
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
	-- A pill with a second line lifts its title to make room; one without keeps the kit's own
	-- slightly-high centre.
	caption.Position = UDim2.fromScale(0.5, if sub then 0.37 else 0.46)
	caption.Size = UDim2.fromScale(0.78, if sub then 0.34 else 0.42)
	caption.BackgroundTransparency = 1
	caption.FontFace = FONT
	caption.Text = oneLine(text)
	caption.TextColor3 = WHITE
	caption.TextTransparency = 1
	caption.TextScaled = true
	caption.Parent = button
	outline(caption)

	if sub then
		local blurb = Instance.new("TextLabel")
		blurb.Name = "Sub"
		blurb.AnchorPoint = Vector2.new(0.5, 0.5)
		blurb.Position = UDim2.fromScale(0.5, 0.68)
		blurb.Size = UDim2.fromScale(0.7, 0.2)
		blurb.BackgroundTransparency = 1
		blurb.FontFace = FONT
		blurb.Text = oneLine(sub)
		blurb.TextColor3 = WHITE
		blurb.TextTransparency = 1
		blurb.TextScaled = true
		blurb.Parent = button
		outline(blurb)
	end

	return button
end

function RadioPanelController._build(self)
	--[[ The new UI's panel, when the new UI is on and its template is in the place. A missing
		template warns and falls through to the code-built panel below, so the radio never vanishes
		because a build command was not run.

		`_building` because `_buildKit` can wait on the shelf, and a second topbar press landing in
		that wait would otherwise build a second panel. `open` returns while there is no panel yet. ]]
	if UIRoot.isNewUI() then
		if self._building then
			return
		end
		self._building = true
		local built = self:_buildKit()
		self._building = false
		if built then
			return
		end
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CarRadio"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	--[[ Below the rename box's 997, and therefore below WELCOME BACK, the respawn screen and the
		race fade as well. It cannot collide with any of them — this only opens from a topbar press,
		and all four of those are modal over the topbar — and ordering it lowest costs nothing. ]]
	gui.DisplayOrder = 996
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	--[[ `Active` is what makes this modal. A Frame does not swallow input by default, so without it
		the HUD behind the dim is still clickable — and a player could start a race with this open. ]]
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
	-- Stretch: the cap's alpha is a plain rectangle, so there is no corner for a slice to protect
	-- and all it would do is hold the painted rim at 1:1 texture pixels. `UIAssets.Slice` has it.
	bar.ScaleType = Enum.ScaleType.Stretch
	bar.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.5)
	title.Size = UDim2.fromScale(0.8, 0.62)
	title.BackgroundTransparency = 1
	title.FontFace = FONT
	title.Text = oneLine(RadioConfig.Copy.Title)
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

	--[[ The one line at the top, and it is doing a job rather than filling space: it is where the
		screen says what is on and, when nothing is, where it says that the radio needs a car to come
		out of. It holds its place whether or not there is anything in it. ]]
	local nowPlaying = Instance.new("TextLabel")
	nowPlaying.Name = "NowPlaying"
	nowPlaying.AnchorPoint = Vector2.new(0.5, 0.5)
	nowPlaying.Position = UDim2.fromScale(0.5, NOW_PLAYING_Y)
	nowPlaying.Size = NOW_PLAYING_BOX
	nowPlaying.BackgroundTransparency = 1
	nowPlaying.FontFace = FONT
	nowPlaying.Text = ""
	nowPlaying.TextColor3 = WHITE
	nowPlaying.TextTransparency = 1
	nowPlaying.TextScaled = true
	nowPlaying.Parent = panel

	--[[ The four stations. Built from `RadioConfig.Stations` rather than authored, so adding one to
		that list is one edit — the grid takes the fifth onto a third row on its own. ]]
	local stations = {}
	for index, station in RadioConfig.Stations do
		local column = ((index - 1) % 2) + 1
		local row = math.floor((index - 1) / 2) + 1
		local y = STATION_Y[1] + (row - 1) * (STATION_Y[2] - STATION_Y[1])

		local button = pill(
			"Station_" .. station.Key,
			STATION_PILL,
			STATION_BOX,
			STATION_X[column],
			y,
			station.Name,
			station.Blurb
		)
		button.Parent = panel
		stations[station.Key] = button
	end

	--[[ The kit's search bar, doing the one job it is shaped for. 9-sliced rather than fitted to its
		own 18:1 aspect, which would be a hairline on this panel — a slice inset of 23px on a 56px
		tall texture leaves a 10px band to stretch, so it grows to a real input field with its ends
		intact. Same treatment as the rename box's field. ]]
	local field = Instance.new("ImageLabel")
	field.Name = "Field"
	field.AnchorPoint = Vector2.new(0.5, 0.5)
	field.Position = UDim2.fromScale(FIELD_X, FIELD_Y)
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
	box.Size = UDim2.fromScale(0.9, 0.56)
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	--[[ ON, unlike the rename box's. That one opens holding a name you are usually TWEAKING; this
		one holds the last id you tried, and the next thing you paste replaces it whole. ]]
	box.ClearTextOnFocus = true
	box.MultiLine = false
	box.Text = ""
	box.PlaceholderText = RadioConfig.Custom.Placeholder
	box.PlaceholderColor3 = MUTED
	box.TextColor3 = WHITE
	box.TextTransparency = 1
	box.FontFace = FONT
	box.TextScaled = true
	box.TextXAlignment = Enum.TextXAlignment.Center
	box.Parent = field

	-- A ceiling on the text size, so a short id is not set in a font twice the height of a long one.
	local boxSize = Instance.new("UITextSizeConstraint")
	boxSize.MaxTextSize = 34
	boxSize.MinTextSize = 12
	boxSize.Parent = box

	local play = pill("Play", UIAssets.Pill.Green, PLAY_BOX, PLAY_X, FIELD_Y, RadioConfig.Copy.Play)
	play.Parent = panel

	--[[ ONE PILL, TWO MEANINGS, and which one it is wearing is the whole state of this screen: OFF
		for an owner (silver — a way back, the same register the rename box's USE MY NAME is in), and
		the price for everybody else (green, which is what this kit pays money in). Not two buttons
		stacked with one hidden, because they occupy the same place for the same reason: it is the
		one thing on this screen that acts on the radio as a whole. ]]
	local action = pill(
		"Action",
		UIAssets.Pill.Silver,
		ACTION_BOX,
		if MusicConfig.Enabled then ACTION_X_PAIRED else ACTION_X_ALONE,
		ACTION_Y,
		RadioConfig.Copy.Off
	)
	action.Parent = panel

	--[[ THE SOUNDTRACK SWITCH, and the second half of the bottom row. See the constants above for
		why it is here at all and why it is not the same thing as a station.

		SILVER, THE SAME AS OFF BESIDE IT. The bottom row is the two switches, and giving them one
		colour is what separates them from the blue stations above without adding a colour to the
		screen. It was purple, the one pill colour nothing else was using, and that made seven.

		ITS STATE IS THE FACE COMING FORWARD, exactly like a chosen station: full opacity for music
		playing, pushed back for muted. The caption spells out which is which, so the dimming never
		has to be interpreted on its own. ]]
	local music: ImageButton? = nil
	if MusicConfig.Enabled then
		music = pill("Music", UIAssets.Pill.Silver, ACTION_BOX, MUSIC_X, ACTION_Y, RadioConfig.Copy.MusicOn)
		;(music :: ImageButton).Parent = panel
	end

	--[[ The answer line. It is the only thing on this screen that ever says no, and it holds its
		space whether or not there is anything in it — a message that appeared and pushed the button
		below it along would move the thing the player is about to press. ]]
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0.5, 0.5)
	status.Position = UDim2.fromScale(0.5, STATUS_Y)
	status.Size = STATUS_BOX
	status.BackgroundTransparency = 1
	status.FontFace = FONT
	status.Text = ""
	status.TextColor3 = WARN_AMBER
	status.TextTransparency = 1
	status.TextScaled = true
	status.TextWrapped = true
	status.Parent = panel

	self._gui = gui
	self._scrim = scrim
	self._panel = panel
	self._bar = bar
	self._title = title
	self._close = close
	self._nowPlaying = nowPlaying
	self._stations = stations
	self._field = field
	self._box = box
	self._play = play
	self._action = action
	self._music = music
	self._status = status

	self:_wire()

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	--[[ === EVERY PRESSABLE THING IS A `UIButton` ==============================================

		Which is how a pressable thing is declared in this project (`UIController/Components/Button`),
		and the tag is what owns the hover swell, the hover sound and the click sound.

		THE TAG CARRIES NO BEHAVIOUR ONTO THEM: none of these has a `Page` or an `Action` attribute,
		so a press through `ButtonPress` plays its click and does nothing else. What each one MEANS
		stays on the `Activated` wires in `_wire`, because they are answers about a radio this screen
		is still holding — state the UI layer knows nothing about. The rename box, the welcome-back
		screen and the respawn screen are all arranged the same way.

		LAST, AND AFTER THE PARENTING, so the component reads a button whose geometry is final. ]]
	for _, button in self._stations do
		button:SetAttribute("Scale", PILL_HOVER_SCALE)
		CollectionService:AddTag(button, "UIButton")
	end
	for _, button in self:_loosePills() do
		button:SetAttribute("Scale", PILL_HOVER_SCALE)
		CollectionService:AddTag(button, "UIButton")
	end
	self._close:SetAttribute("Scale", CLOSE_HOVER_SCALE)
	CollectionService:AddTag(self._close, "UIButton")
end

--[[ THE NEW UI'S PANEL: clone the kit template off the shelf, stamp a row per thing on the screen,
	and hand back true. False, with a warning, when the template is missing or is not the shape this
	expects, and `_build` then builds the shipping panel.

	`KitPage.bind` DOES THE KIT'S HALF, exactly as it does for the gift picker: the X, the selection
	trap, the row templates and the list sized in pixels. The panel is stretched to fit every row by
	the build command, so the list does not scroll with four stations.

	THE FIELDS THE SHARED CODE READS ARE SET TO THEIR KIT EQUIVALENTS: `_box` (the paste box, for
	`_submitCustom` and `close`), `_status` (the answer line, for `_say`) and `_close` (the X, which
	`_bindPad` hangs the B glyph off). Everything else the kit draws lives in `self._kit`, and that
	table being there is how every drawing method knows which panel it has. The shipping panel's own
	fields (`_stations`, `_play`, `_action`, `_music`) are never set on this path.

	THE INSET IS THE KIT'S: `IgnoreGuiInset` false with `CoreUISafeInsets`, so the panel lands where
	the artist put it and at the same size the Settings page has. The dim is not in that gui at all;
	see `KIT_SHADE_NAME`. ]]
function RadioPanelController._buildKit(self): boolean
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", KIT_WAIT)
	local root = playerGui and UIRoot.wait(playerGui :: PlayerGui, KIT_WAIT)
	local shelf = root and root:WaitForChild(KIT_SHELF, KIT_WAIT)
	local template = shelf and shelf:WaitForChild(KIT_TEMPLATE, KIT_WAIT)
	if not (template and template:IsA("GuiObject")) then
		self.log:warn(
			string.format(
				"No %s.%s.%s in this place (run BuildCarRadioV2); the radio uses the code-built panel.",
				UIRoot.name(),
				KIT_SHELF,
				KIT_TEMPLATE
			)
		)
		return false
	end

	local panel = template:Clone() :: GuiObject
	panel.Name = "Panel"
	--- The kit's text caps are pixels for a 1080-tall screen; this keeps them in proportion above it.
	KitPage.scaleTextCaps(panel)
	local page = KitPage.bind(panel)
	--- `bind` dispatches the X through `onClose` at press time, so this is the whole of wiring it.
	page.onClose = function()
		self:close()
	end
	page:setTitle(RadioConfig.Copy.Title)

	--[[ The rows, top to bottom, in the shipping panel's own order: what is playing, the stations,
		the paste box, the answer line, then the two switches. A station per `RadioConfig.Stations`
		entry, so a fifth is one edit there (and a re-run of the build command to fit it). ]]
	local nowPlayingRow = page:newRow(NOTE_ROW)
	local stationRows = {}
	for _, station in RadioConfig.Stations do
		local row = page:newRow(STATION_ROW)
		if row then
			row.Name = "Station_" .. station.Key
			stationRows[station.Key] = row
		end
	end
	local customRow = page:newRow(INPUT_ROW)
	local statusRow = page:newRow(NOTE_ROW)
	local radioRow = page:newRow(RADIO_ROW)
	local musicRow = if MusicConfig.Enabled then page:newRow(MUSIC_ROW) else nil

	--- Every part this file writes to, looked up once and checked once, so a template that has
	--- drifted from the build command fails here with its name rather than on the first press.
	local missing = {}
	local function need(root: Instance?, path: string, class: string): any
		local part = find(root, path)
		if not (part and part:IsA(class)) then
			table.insert(missing, string.format("%s.%s", if root then root.Name else "?", path))
			return nil
		end
		return part
	end

	local kit = {
		page = page,
		stations = {},
		nowPlaying = need(nowPlayingRow, "Title", "TextLabel"),
		status = need(statusRow, "Title", "TextLabel"),
		box = need(customRow, "Field.TextBox", "TextBox"),
		play = need(customRow, "Btns.OnBtn", "GuiButton"),
		playGrey = need(customRow, "Btns.DisabledBtn", "GuiObject"),
		off = need(radioRow, "Btns.OffBtn", "GuiButton"),
		buy = need(radioRow, "Btns.OnBtn", "GuiButton"),
		radioGrey = need(radioRow, "Btns.DisabledBtn", "GuiObject"),
		radioTitle = need(radioRow, "Title", "TextLabel"),
		musicTitle = if musicRow then need(musicRow, "Title", "TextLabel") else nil,
		musicOn = if musicRow then need(musicRow, "Toggle.On", "GuiButton") else nil,
		musicOff = if musicRow then need(musicRow, "Toggle.Off", "GuiButton") else nil,
		scale = nil :: UIScale?,
		tween = nil :: Tween?,
	}
	for _, station in RadioConfig.Stations do
		local row = stationRows[station.Key]
		kit.stations[station.Key] = {
			title = need(row, "Title", "TextLabel"),
			genre = need(row, "Genre", "TextLabel"),
			play = need(row, "Btns.OnBtn", "GuiButton"),
			onAir = need(row, "Btns.DisabledBtn", "GuiObject"),
		}
	end
	if not page.CloseBtn then
		table.insert(missing, "Header.CloseBtn")
	end
	if #missing > 0 then
		self.log:warn(
			string.format(
				"The %s template is missing %s; re-run BuildCarRadioV2. The radio uses the code-built panel.",
				KIT_TEMPLATE,
				table.concat(missing, ", ")
			)
		)
		panel:Destroy()
		return false
	end

	-- The words that never change. Everything that does is `_paintKit`'s.
	for _, station in RadioConfig.Stations do
		local parts = kit.stations[station.Key]
		parts.title.Text = kitLine(station.Name)
		parts.genre.Text = kitLine(station.Blurb)
		setCaption(parts.play, RadioConfig.Copy.Play)
		setCaption(parts.onAir, KIT_COPY.OnAir)
	end
	setCaption(kit.play, RadioConfig.Copy.Play)
	setCaption(kit.playGrey, RadioConfig.Copy.Play)
	setCaption(kit.off, RadioConfig.Copy.Off)
	setCaption(kit.buy, ROBUX .. tostring(self:_price()))
	kit.radioTitle.Text = KIT_COPY.Radio
	if kit.musicTitle then
		kit.musicTitle.Text = KIT_COPY.Music
	end
	kit.box.Text = ""
	kit.box.PlaceholderText = RadioConfig.Custom.Placeholder
	kit.box.ClearTextOnFocus = true -- see the shipping field's note on why this one clears
	kit.nowPlaying.Text = ""
	kit.status.Text = ""

	local gui = Instance.new("ScreenGui")
	gui.Name = "CarRadio"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 996 -- see `_build` on why this sits where it does
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	--[[ The dim, under the HUD. See `KIT_SHADE_NAME`. `Active` still, so a press on the darkened
		world lands on the dim rather than on whatever is behind it. ]]
	local shade = Instance.new("ScreenGui")
	shade.Name = KIT_SHADE_NAME
	shade.ResetOnSpawn = false
	shade.IgnoreGuiInset = true
	shade.DisplayOrder = (root :: ScreenGui).DisplayOrder - KIT_SHADE_BELOW_HUD
	shade.Enabled = false

	local scrim = Instance.new("Frame")
	scrim.Name = "Scrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = SCRIM_COLOR
	scrim.BackgroundTransparency = 1
	scrim.BorderSizePixel = 0
	scrim.Active = true
	scrim.Parent = shade

	local scale = Instance.new("UIScale")
	scale.Scale = KIT_START_SCALE
	scale.Parent = panel
	kit.scale = scale

	self._kit = kit
	self._gui = gui
	self._shade = shade
	self._scrim = scrim
	self._panel = panel
	self._box = kit.box
	self._status = kit.status
	self._nowPlaying = kit.nowPlaying
	self._close = page.CloseBtn

	self:_wireKit()

	--[[ THE TAGS COME OFF FOR THE PARENTING AND GO BACK ON AFTER IT, which is the order the shipping
		panel tags in (see the end of `_build`). The kit's buttons arrive already tagged by
		`PrepKitTemplate`, so without this the component would bind them mid-parent. The grey faces
		were untagged at build time and stay that way. ]]
	local tagged = {}
	for _, descendant in panel:GetDescendants() do
		if CollectionService:HasTag(descendant, "UIButton") then
			CollectionService:RemoveTag(descendant, "UIButton")
			table.insert(tagged, descendant)
		end
	end

	panel.Parent = gui
	shade.Parent = playerGui
	gui.Parent = playerGui

	--- The switch's swatches take no swell, as on the Settings page: a swatch inside a track that
	--- grows under a cursor pokes out of the track.
	for _, button in tagged do
		local scale = if button == self._close
			then CLOSE_HOVER_SCALE
			elseif button == kit.musicOn or button == kit.musicOff then 1
			else KIT_ROW_HOVER_SCALE
		button:SetAttribute("Scale", scale)
		CollectionService:AddTag(button, "UIButton")
	end
	return true
end

--[[ The kit panel's presses. Each lands in the same answer the shipping panel's does, so the two
	panels cannot disagree about what a press means; only which instance was pressed differs. The X
	is `KitPage`'s (see `onClose` in `_buildKit`). ]]
function RadioPanelController._wireKit(self)
	local kit = self._kit

	for key, parts in kit.stations do
		parts.play.Activated:Connect(function()
			self:_choose(key)
		end)
	end

	kit.play.Activated:Connect(function()
		self:_submitCustom()
	end)

	--- Off and the price are one button with two faces, exactly as on the shipping panel, so both
	--- faces ask the same question at press time.
	kit.off.Activated:Connect(function()
		self:_pressAction()
	end)
	kit.buy.Activated:Connect(function()
		self:_pressAction()
	end)

	--- Either swatch: the one showing is the one pressed, and a press means "the other answer".
	for _, swatch in { kit.musicOn, kit.musicOff } do
		swatch.Activated:Connect(function()
			self:_toggleMusic()
		end)
	end

	self._box.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			self:_submitCustom()
		end
	end)

	self:_listen()
end

--[[ Every pill on this screen that is not a station: PLAY, the radio switch, and the soundtrack
	switch when there is a soundtrack to switch.

	ONE LIST, BUILT ONCE PER CALL, because four separate places need exactly the same set (the tag
	pass, the fade in, the fade out, and nothing else) and three of them used to spell it out. The
	music pill is the first thing on this panel that is conditional, and a conditional member of a
	list written out four times is a list that will be wrong in one of them. ]]
function RadioPanelController._loosePills(self): { ImageButton }
	local pills = { self._play, self._action }
	if self._music then
		table.insert(pills, self._music)
	end
	return pills
end

function RadioPanelController._wire(self)
	for key, button in self._stations do
		button.Activated:Connect(function()
			self:_choose(key)
		end)
	end

	self._play.Activated:Connect(function()
		self:_submitCustom()
	end)

	self._action.Activated:Connect(function()
		self:_pressAction()
	end)

	if self._music then
		self._music.Activated:Connect(function()
			self:_toggleMusic()
		end)
	end

	self._close.Activated:Connect(function()
		self:close()
	end)

	--[[ Enter plays what is in the box, which is what a text field is expected to do. `FocusLost`
		fires on any way out of the box — clicking PLAY also drops focus first — so the flag is what
		separates "they pressed Return" from "they clicked something else". ]]
	self._box.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			self:_submitCustom()
		end
	end)

	self:_listen()
end

--[[ The one button whose meaning depends on the state of the screen: see the comment where it
	is built. Read at press time rather than remembered on repaint, so a pass that arrives
	between the two cannot leave the button doing the other thing. Both panels press this. ]]
function RadioPanelController._pressAction(self)
	if self:_owned() then
		self:_choose(nil)
	else
		self:_choose(RadioConfig.DefaultStation) -- refused server-side, which opens the prompt
	end
end

--[[ The soundtrack switch. It goes STRAIGHT to the controller and this screen repaints from the
	event that comes back out, which is the one-way arrangement the topbar's icon used to have
	with the same controller and is why the move cost no behaviour.

	IT IS APPLIED INSTANTLY where a station press is not, and the difference is worth naming: a
	station is the car making noise for everybody nearby and the server has to allow it, where
	the soundtrack is this player's own speakers and there is no ruling to make. `MusicConfig`
	note 5 has the whole argument. Both panels press this. ]]
function RadioPanelController._toggleMusic(self)
	local MusicController = Shard.get("MusicController")
	if not MusicController then
		self.log:warn("MusicController is not up; the music button cannot do anything.")
		return
	end
	MusicController:toggleMuted()
end

--[[ What this screen listens to, whichever panel it is: the server's answers and the three things
	that move what it draws. Wired once, by whichever `_wire` ran. ]]
function RadioPanelController._listen(self)
	-- The server's answers, republished by `RadioController` because it is the thing holding the
	-- remote. A message that arrives while the screen is shut is dropped: it has nowhere to go.
	Dispatcher:Subscribe(RadioConfig.ReplyName, function(ok: boolean, message: string)
		if self._open then
			self:_say(message, ok)
		end
	end)

	-- The local player's radio moved — a station took, their car was put away, they bought the pass.
	Dispatcher:Subscribe(RadioConfig.StateEvent, function()
		if self._open then
			self:_paint()
		end
	end)

	--[[ ...and the mute moving, which is nearly always this screen's own button but is not only it:
		the server's saved answer lands a second or two into a session, and a player who opened this
		panel before it did would otherwise be looking at a switch that says the opposite of what
		their speakers are doing. ]]
	Dispatcher:Subscribe(MusicConfig.StateEvent, function()
		if self._open then
			self:_paint()
		end
	end)

	--[[ ...and the pass answer landing, which is the third state `_paint` draws and the one that
		arrives late. A player who opened this screen before Roblox answered would otherwise be
		looking at a price for a pass they already own until they pressed something. ]]
	Players.LocalPlayer:GetAttributeChangedSignal(RadioConfig.OwnedAttribute):Connect(function()
		if self._open then
			self:_paint()
		end
	end)
end

-- === Drawing ================================================================

--- The server's answer to "does this player own the radio pass": true, false, or nil for "not yet".
--- The three are all different and `_paint` draws all three — see the header.
function RadioPanelController._owned(self): boolean?
	local value = Players.LocalPlayer:GetAttribute(RadioConfig.OwnedAttribute)
	if type(value) ~= "boolean" then
		return nil
	end
	return value
end

function RadioPanelController._say(self, message: string?, ok: boolean?)
	--- On one line on the kit panel, whose answer line is one row high: wrapped, the longest refusal
	--- set at half the size of the rows around it.
	self._status.Text = if self._kit then kitLine(message or "") else message or ""
	self._status.TextColor3 = if ok then OK_GREEN else WARN_AMBER
end

--[[ Draw the whole screen from the two things that decide it: whether the pass is owned, and what
	the player's own car is playing. Called on open and on every change to either.

	IT IS ONE FUNCTION AND NOT A SET OF LITTLE ONES, because every element on this screen answers to
	both inputs and a partial repaint is how a screen ends up half in one state and half in the
	other — the station lit as chosen next to a button offering to sell you the pass. ]]
function RadioPanelController._paint(self)
	if self._kit then
		self:_paintKit()
		return
	end

	local RadioController = Shard.get("RadioController")
	local owned = self:_owned()
	local station = RadioController and RadioController:station()

	--[[ THE CHOSEN STATION IS DIMMED, NOT HIGHLIGHTED, and that is the way round this kit already
		works: a pill's pressed art is its own colour at full opacity and its idle is 80% (`UIAssets`
		note 2), so "engaged" reads as the FACE COMING FORWARD. Holding the chosen one at full
		opacity and pushing the others back says the same thing with the art rather than against
		it, and needs no second texture. Now that all four are one colour, that is the only
		difference between them, so it is a deep step.

		NOTHING RECEDES WHEN NONE OF THE FOUR IS ON (radio off, or a custom track). There is no
		choice to point at then, and four pushed-back pills read as a radio that is switched off
		or locked. Locked is its own, deeper step, for a player without the pass. ]]
	local onAir = RadioConfig.stationByKey(station) ~= nil
	for key, button in self._stations do
		local chosen = station == key
		local reachable = owned == true
		local receded = onAir and not chosen
		button.ImageTransparency = if chosen then 0 elseif not reachable then 0.55 elseif receded then 0.45 else 0
		setAlpha(button.Label, if chosen then 0 elseif not reachable then 0.4 elseif receded then 0.25 else 0)
		setAlpha(button:FindFirstChild("Sub"), if chosen or (reachable and not receded) then 0.15 else 0.45)
	end

	--[[ The custom half is only for owners, and it is switched off rather than hidden: a box that
		vanished would make the panel change shape depending on something the player cannot see, and
		a greyed-out field is itself an advert for what the pass includes. ]]
	local canCustom = owned == true and RadioConfig.Custom.Enabled
	self._box.TextEditable = canCustom
	self._field.ImageTransparency = if canCustom then 0 else 0.45
	self._play.ImageTransparency = if canCustom then 0 else 0.5
	setAlpha(self._play.Label, if canCustom then 0 else 0.45)

	--[[ The one button with two meanings. `Silver` is a way back and `Green` is what this kit pays
		money in, so an owner sees OFF in silver and everybody else sees the price in green. The
		unanswered state wears the silver too — an unanswered pass must never show a price. ]]
	local art = if owned == true or owned == nil then UIAssets.Pill.Silver else UIAssets.Pill.Green
	self._action.Image = UIAssets.url(art.Idle)
	self._action.HoverImage = UIAssets.url(art.Hover)
	self._action.PressedImage = UIAssets.url(art.Pressed)
	self._action.Label.Text = oneLine(
		if owned == true then RadioConfig.Copy.Off
		elseif owned == nil then RadioConfig.Copy.Checking
		else string.format(RadioConfig.Copy.Buy, self:_price())
	)
	self._action.ImageTransparency = if owned == nil then 0.5 else 0
	--[[ Set explicitly, not left where the last fade put it. `_fadeTo` reads an element's CURRENT
		transparency as the value to rise to, and `close` leaves everything at 1 — so a caption this
		function never touched would come back invisible on the second open. Every transparency this
		screen has a resting value for is written here, for that reason. ]]
	setAlpha(self._action.Label, if owned == nil then 0.4 else 0)

	--[[ The soundtrack switch, which answers to neither of this function's two inputs and is drawn
		here anyway. It belongs in the one repaint for the reason the block above this function
		gives: a partial repaint is how a screen ends up half in one state and half in the other, and
		"the pill I just pressed did not move" is exactly the bug that produces.

		THE FACE COMES FORWARD FOR MUSIC PLAYING, which is the same language the chosen station is
		drawn in, and the caption names the state so the dimming never has to be read on its own. ]]
	if self._music then
		local MusicController = Shard.get("MusicController")
		local muted = MusicController ~= nil and MusicController:isMuted()
		self._music.Label.Text = oneLine(if muted then RadioConfig.Copy.MusicOff else RadioConfig.Copy.MusicOn)
		self._music.ImageTransparency = if muted then 0.45 else 0
		setAlpha(self._music.Label, if muted then 0.3 else 0)
	end

	--- ...and the line that says what is going on, in the order the player would ask it in.
	self._nowPlaying.Text = self:_nowPlayingText(owned, station)
end

--[[ The kit panel, drawn from the same two inputs, in one function for the same reason `_paint` is.

	THE KIT SAYS STATE WITH FACES, NOT OPACITY. Each button row has a green face, a grey one and (on
	the radio row) a pink one, and exactly one shows. So where the shipping panel pushes pills back,
	this swaps faces:

	  • A STATION: green Play, or grey On air for the one the car is playing. Grey is the kit's "not
	    now", and pressing the station that is already on would change nothing.
	  • THE PASTE BOX'S PLAY: green for an owner who can paste, AND for a player without the pass,
	    because their press is the one that opens the purchase prompt (`_submitCustom`). Grey only
	    while the pass is unanswered or custom tracks are switched off. The box itself only takes
	    typing from an owner, as on the shipping panel.
	  • THE RADIO ROW: pink Off while something is playing, grey Off when nothing is, the green price
	    for a player without the pass, and grey Checking while Roblox has not answered. The
	    unanswered pass never shows a price, which is the header's rule.
	  • MUSIC: the kit's switch, green on the right for music playing and red on the left for muted.

	NOTHING IS DIMMED FOR A PLAYER WITHOUT THE PASS. The shipping panel greys its stations as an
	advert; here the price is on its own row in green, the line at the top pitches it, and a green
	Play that opens the prompt is a truer picture of what the press does than a faded one. ]]
--- What Roblox says this player pays for the pass (`Modules/LivePrice`); `RadioConfig.Price` until it
--- answers, and for good if it cannot.
function RadioPanelController._price(self): number
	return LivePrice.peek(RadioConfig.PassId, Enum.InfoType.GamePass) or RadioConfig.Price
end

function RadioPanelController._paintKit(self)
	local kit = self._kit
	local RadioController = Shard.get("RadioController")
	local owned = self:_owned()
	local station = RadioController and RadioController:station()

	for key, parts in kit.stations do
		local onAir = station == key
		parts.play.Visible = not onAir
		parts.onAir.Visible = onAir
	end

	local canCustom = owned == true and RadioConfig.Custom.Enabled
	local customLive = canCustom or owned == false
	self._box.TextEditable = canCustom
	kit.play.Visible = customLive
	kit.playGrey.Visible = not customLive

	local playing = station ~= nil
	kit.off.Visible = owned == true and playing
	kit.buy.Visible = owned == false
	setCaption(kit.buy, ROBUX .. tostring(self:_price()))
	kit.radioGrey.Visible = owned == nil or (owned == true and not playing)
	setCaption(kit.radioGrey, if owned == nil then RadioConfig.Copy.Checking else RadioConfig.Copy.Off)

	if kit.musicOn and kit.musicOff then
		local MusicController = Shard.get("MusicController")
		local muted = MusicController ~= nil and MusicController:isMuted()
		kit.musicOn.Visible = not muted
		kit.musicOff.Visible = muted
	end

	self._nowPlaying.Text = kitLine(self:_nowPlayingText(owned, station))
end

--[[ The sentence at the top of the screen. Four answers, and they are ordered by what the player
	most needs to know rather than by what is easiest to check.

	"SPAWN A CAR" OUTRANKS EVERYTHING INCLUDING THE PRICE, because it is the one problem the player
	can fix in the next ten seconds and the one this screen would otherwise be silent about — a
	station press with no car out is refused by the server with exactly that sentence, and saying it
	before they press is simply saying it earlier. ]]
function RadioPanelController._nowPlayingText(self, owned: boolean?, station: string?): string
	local RadioController = Shard.get("RadioController")

	if station == RadioConfig.CustomStation then
		return RadioConfig.Copy.OnCustom
	end

	local found = RadioConfig.stationByKey(station)
	if found then
		-- The station itself is the lit pill in the grid, so the line names the track, and the
		-- station only while the track is not known yet.
		local track = RadioController and RadioController:nowPlaying()
		return string.format(RadioConfig.Copy.OnStation, track or found.Name)
	end

	if not self:_hasCarOut() then
		return RadioConfig.Copy.NoCar
	end
	if owned == false then
		return RadioConfig.Copy.Pitch
	end
	return RadioConfig.Copy.Idle
end

--- Whether this player has a lobby car standing in the world at all, which is a different question
--- from whether its radio is on. Read off the same attribute the Cars Inventory draws its SPAWNED
--- marker from, so the two can never disagree.
function RadioPanelController._hasCarOut(self): boolean
	local key = Players.LocalPlayer:GetAttribute(LobbyCarConfig.SpawnedAttribute)
	return type(key) == "string" and key ~= ""
end

-- === Answers ================================================================

--[[ Ask for a station. `nil` switches the radio off.

	NOTHING IS REFUSED LOCALLY except a press with no controller up, and that is deliberate: the
	server has every rule (the pass, the car, the id) and a second copy of them here would be a
	second thing to keep in step. A non-owner pressing a station is a real request — it is refused,
	and the refusal is what opens Roblox's purchase prompt in front of them. ]]
function RadioPanelController._choose(self, station: string?)
	local RadioController = Shard.get("RadioController")
	if not RadioController then
		return
	end
	self:_say(nil)
	RadioController:request(station, nil)
end

--[[ Play whatever is in the box.

	`RadioConfig.parseId` IS RUN HERE AS WELL AS ON THE SERVER, for the reason the rename box runs
	`PlotConfig.sanitize` twice: an empty box or a line of text can be answered in the same frame
	the player pressed PLAY, without spending their cooldown on a request that was never going to
	work. Everything the local copy cannot decide — is it audio, is it public — is the server's. ]]
function RadioPanelController._submitCustom(self)
	if self:_owned() ~= true then
		self:_choose(RadioConfig.DefaultStation) -- refused server-side, which opens the prompt
		return
	end
	if not RadioConfig.Custom.Enabled then
		self:_say(RadioConfig.Copy.CustomOff)
		return
	end

	local id = RadioConfig.parseId(self._box.Text)
	if not id then
		self:_say(RadioConfig.Copy.BadId)
		return
	end

	local RadioController = Shard.get("RadioController")
	if not RadioController then
		return
	end
	self:_say(nil)
	RadioController:request(RadioConfig.CustomStation, id)
end

-- === Show / hide ============================================================

--- Public (`TopbarController`): is the screen up?
function RadioPanelController.isOpen(self): boolean
	return self._open == true
end

--- Public (`TopbarController`): the topbar button, which is a toggle.
function RadioPanelController.toggle(self)
	if self._open then
		self:close()
	else
		self:open()
	end
end

function RadioPanelController.open(self)
	if not RadioConfig.Enabled then
		return
	end
	if not self._gui then
		self:_build()
		--- Still nothing when a press lands while the kit panel's build is waiting on the shelf.
		if not self._gui then
			return
		end
	end
	if self._open then
		return
	end

	self._open = true
	self._token += 1

	self:_say(nil)
	self:_paint()

	self._gui.Enabled = true
	if self._kit then
		self._shade.Enabled = true
		self:_raiseKit()
		self:_bindPad(true)
		Dispatcher:Publish(RadioConfig.PanelEvent, true)
		--- The kit panel opens off the HUD grid like a page, so Play steps aside for it as it does for
		--- a page (`UIController._syncPlayRoom`), under a name of its own.
		Dispatcher:Publish("SuppressPlayButton", true, PLAY_ROOM_SOURCE)
		--[[ ...and it takes a page's place. The pages live in the HUD's gui, above the dim, so one
			left open would sit lit beside the radio. After the Play request, so the last page letting
			go of Play cannot send it up for a frame. The other way round is `PageOpened` in `start`. ]]
		Dispatcher:Publish("CloseAllPages")
		return
	end

	self:_tween(self._scrim, RAISE_TIME, { BackgroundTransparency = SCRIM_REST })
	self:_tween(self._panel, RAISE_TIME, { ImageTransparency = 0 })
	self:_tween(self._bar, RAISE_TIME, { ImageTransparency = 0 })
	self:_tween(self._title, RAISE_TIME, { TextTransparency = 0 })
	self:_tween(self._close, RAISE_TIME, { ImageTransparency = 0 })
	-- The now-playing line rests a little back: it is the caption, not the content.
	self:_tween(self._nowPlaying, RAISE_TIME, { TextTransparency = 0.15 })
	self:_tween(self._box, RAISE_TIME, { TextTransparency = 0 })
	self:_tween(self._status, RAISE_TIME, { TextTransparency = 0 })

	--[[ The pills and the field are faded to whatever `_paint` decided rather than to zero, so the
		dimming that says "you do not own this" is not undone by the screen arriving. `_paint` sets
		the resting transparency and this tween takes them there from 1. ]]
	for _, button in self._stations do
		self:_fadeTo(button, RAISE_TIME)
	end
	self:_fadeTo(self._field, RAISE_TIME)
	for _, button in self:_loosePills() do
		self:_fadeTo(button, RAISE_TIME)
	end

	self:_bindPad(true)

	-- For the topbar button, which follows this panel. LAST, because `Publish` runs its listeners
	-- inline and one that threw would otherwise stop the screen half raised.
	Dispatcher:Publish(RadioConfig.PanelEvent, true)
end

--[[ Take an element from invisible to the resting transparency `_paint` chose for it. The rest
	value is read off the instance rather than passed in, because `_paint` is the only thing that
	gets to decide it and reading it here is what keeps that true. ]]
function RadioPanelController._fadeTo(self, element: ImageLabel | ImageButton, time: number)
	local rest = element.ImageTransparency
	element.ImageTransparency = 1
	self:_tween(element, time, { ImageTransparency = rest })

	for _, name in { "Label", "Sub" } do
		local label = element:FindFirstChild(name)
		if label and label:IsA("TextLabel") then
			local textRest = label.TextTransparency
			setAlpha(label, 1)
			self:_fadeCaption(label, time, textRest)
		end
	end
end

--[[ One pill caption in or out, to `rest` (1 is out). The outline takes the last part of the way in
	and the first part of the way out, for the reason `STROKE_SHARE` gives. ]]
function RadioPanelController._fadeCaption(self, label: Instance?, time: number, rest: number)
	if not (label and label:IsA("TextLabel")) then
		return
	end
	self:_tween(label, time, { TextTransparency = rest })
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		local share = time * STROKE_SHARE
		self:_tween(stroke, share, { Transparency = rest }, if rest < 1 then time - share else 0)
	end
end

function RadioPanelController.close(self)
	if not (self._gui and self._open) then
		return
	end
	self._open = false
	local token = self._token

	self._box:ReleaseFocus()
	self:_bindPad(false)

	if self._kit then
		self:_dropKit(token)
		Dispatcher:Publish(RadioConfig.PanelEvent, false)
		Dispatcher:Publish("SuppressPlayButton", false, PLAY_ROOM_SOURCE)
		return
	end

	self:_tween(self._scrim, DROP_TIME, { BackgroundTransparency = 1 })
	self:_tween(self._panel, DROP_TIME, { ImageTransparency = 1 })
	self:_tween(self._bar, DROP_TIME, { ImageTransparency = 1 })
	self:_tween(self._title, DROP_TIME, { TextTransparency = 1 })
	self:_tween(self._close, DROP_TIME, { ImageTransparency = 1 })
	self:_tween(self._nowPlaying, DROP_TIME, { TextTransparency = 1 })
	self:_tween(self._field, DROP_TIME, { ImageTransparency = 1 })
	self:_tween(self._box, DROP_TIME, { TextTransparency = 1 })
	for _, button in self._stations do
		self:_tween(button, DROP_TIME, { ImageTransparency = 1 })
		self:_fadeCaption(button.Label, DROP_TIME, 1)
		self:_fadeCaption(button:FindFirstChild("Sub"), DROP_TIME, 1)
	end
	for _, button in self:_loosePills() do
		self:_tween(button, DROP_TIME, { ImageTransparency = 1 })
		self:_fadeCaption(button.Label, DROP_TIME, 1)
	end
	local last = self:_tween(self._status, DROP_TIME, { TextTransparency = 1 })

	last.Completed:Once(function()
		-- Fenced on the token so the tail of a screen that has already been reopened cannot switch
		-- the new one off.
		if self._token == token and not self._open then
			self._gui.Enabled = false
		end
	end)

	-- Every way out comes through here (the X, B, the topbar), so this is where the topbar button
	-- hears that the panel has shut. Last, for the reason `open` gives.
	Dispatcher:Publish(RadioConfig.PanelEvent, false)
end

--[[ The kit panel up and down. The panel itself does what a V2 page does (`KIT_OPEN`); the scrim
	fades the way the shipping one does. Nothing inside the panel fades: the kit's buttons are frames
	with gradients and strokes rather than images, and the swell is how every kit screen arrives. ]]
function RadioPanelController._raiseKit(self)
	local kit = self._kit
	if kit.tween then
		kit.tween:Cancel()
	end
	self._panel.Visible = true
	kit.scale.Scale = KIT_START_SCALE
	kit.tween = TweenService:Create(kit.scale, KIT_OPEN, { Scale = 1 })
	kit.tween:Play()
	self:_tween(self._scrim, RAISE_TIME, { BackgroundTransparency = SCRIM_REST })
end

function RadioPanelController._dropKit(self, token: number)
	local kit = self._kit
	if kit.tween then
		kit.tween:Cancel()
	end
	kit.tween = TweenService:Create(kit.scale, KIT_CLOSE, { Scale = KIT_START_SCALE })
	kit.tween:Play()

	--[[ A highlight left on a button of a panel that has gone is a highlight on nothing, and the
		engine does not clear it on its own (see `GamepadNav`). Only ours is cleared. ]]
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(self._gui) then
		GuiService.SelectedObject = nil
	end

	local last = self:_tween(self._scrim, DROP_TIME, { BackgroundTransparency = 1 })
	last.Completed:Once(function()
		--- Fenced on the token, for the reason the shipping close gives.
		if self._token == token and not self._open then
			self._panel.Visible = false
			self._gui.Enabled = false
			self._shade.Enabled = false
		end
	end)
end

function RadioPanelController._tween(self, inst, time: number, props, delay: number?)
	local info = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay or 0)
	local tween = TweenService:Create(inst, info, props)
	tween:Play()
	return tween
end

--[[ B closes, and the highlight is put on the panel.

	THIS USED TO BIND B AND NOTHING ELSE, on the belief that a console player arrives with Roblox's
	gamepad cursor up (ButtonSelect) and so can already press every pill. They do not: Select is the
	hotbar's backpack now, and the way a pad reaches the radio's topbar icon is the DPad, up from the
	top of the rail, which is a SELECTION, not a cursor. The modal flag then took that selection away
	and nothing put one back, so on a pad the panel could be opened and closed and nothing on it could
	be pressed (measured 2026-10-15). So `_seedPad` lands the highlight on the first live button and
	the panel is a selection group, the same bargain every page makes with `GamepadNav`.

	`GamepadConfig.ModalAttribute` is still raised, so the rail's own highlight drops while this is
	up and does not sit behind it. ]]
function RadioPanelController._bindPad(self, on: boolean)
	GamepadInput.setModal("RadioPanelController", on)

	if not on then
		GamepadInput.unbind(PAD_CLOSE)
		local selected = GuiService.SelectedObject
		if selected and self._panel and selected:IsDescendantOf(self._panel) then
			GuiService.SelectedObject = nil
		end
		return
	end

	GamepadInput.bind({
		actionName = PAD_CLOSE,
		keyCode = Enum.KeyCode.ButtonB,
		callback = function()
			self:close()
		end,
		parent = self._close,
		iconPosition = UDim2.fromScale(0.5, 1.35),
		iconAnchor = Vector2.new(0.5, 0.5),
		iconSize = SMALL_ICON,
		priority = PAD_PRIORITY,
	})
	self:_seedPad()
end

--[[ Put a pad's highlight on the topmost live button that is not the X, and keep it in the panel.

	A FEW FRAMES, NOT ONE. The panel switched on this frame, and the engine refuses a selection it has
	not drawn yet; the modal flag going up also clears the topbar icon that opened this, a frame later.
	So it re-tries until the highlight is inside the panel, and stops the moment it is, or the moment
	the panel is gone. A mouse player is never handed a highlight. ]]
local SEED_FRAMES = 10

function RadioPanelController._seedPad(self)
	local panel = self._panel
	if not (panel and GamepadInput.isGamepadActive()) then
		return
	end
	panel.SelectionGroup = true
	panel.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorRight = Enum.SelectionBehavior.Stop

	local function shown(object: Instance): boolean
		local node: Instance? = object
		while node and node ~= panel do
			if node:IsA("GuiObject") and not node.Visible then
				return false
			end
			node = node.Parent
		end
		return node == panel
	end

	local function pick(): GuiButton?
		local best: GuiButton? = nil
		local bestY = math.huge
		for _, descendant in panel:GetDescendants() do
			if descendant:IsA("GuiButton") and descendant ~= self._close and descendant.Selectable and shown(descendant) then
				local y = descendant.AbsolutePosition.Y
				if y < bestY then
					best, bestY = descendant, y
				end
			end
		end
		return best
	end

	local token = self._token
	task.spawn(function()
		for _ = 1, SEED_FRAMES do
			if token ~= self._token or not self._open then
				return
			end
			--[[ The X does not count as landed. The topbar icon that opened this goes unselectable
				under the dim, and the engine moves the highlight to the nearest thing it can, which is
				this panel's X, right under the topbar (measured 2026-10-15). ]]
			local current = GuiService.SelectedObject
			if current and current:IsDescendantOf(panel) and current ~= self._close then
				return
			end
			local target = pick()
			if target then
				GuiService.SelectedObject = target
			end
			task.wait()
		end
	end)
end

RadioPanelController:withLifecycle({
	init = function(self)
		self._gui = nil :: ScreenGui?
		self._open = false
		self._token = 0
		self._stations = {} :: { [string]: ImageButton }
		--- Nil on a build with no soundtrack (`MusicConfig.Enabled` off), which is why every use of
		--- it is guarded and why `_loosePills` exists.
		self._music = nil :: ImageButton?
		--- The new UI's panel and everything on it (`_buildKit`), or nil for the shipping panel. Its
		--- presence is how every drawing method knows which panel it is drawing.
		self._kit = nil :: any
		--- The kit panel's dim, in a gui under the HUD's (`KIT_SHADE_NAME`). Nil on the shipping panel.
		self._shade = nil :: ScreenGui?
		--- True while `_buildKit` waits on the shelf. See `_build`.
		self._building = false
	end,

	start = function(self)
		--- The pass's real price, asked before the panel is first opened; one landing while it is up redraws it.
		LivePrice.fetch(RadioConfig.PassId, Enum.InfoType.GamePass, function(price)
			if price and self._open then
				self:_paint()
			end
		end)

		--- The new HUD grid's Radio cell. A toggle, like the topbar chip: the grid stays pressable
		--- over the dim, so a second press on the cell puts the radio away.
		Dispatcher:Subscribe("UIAction", function(action: string)
			if action == RadioConfig.PanelAction then
				self:toggle()
			end
		end)

		--[[ A page opening puts the kit panel away. The HUD stays pressable over the dim, so a rail
			button can open a page while the radio is up, and that page would draw under the panel. ]]
		Dispatcher:Subscribe("PageOpened", function()
			if self._kit then
				self:close()
			end
		end)
	end,
})

return RadioPanelController
