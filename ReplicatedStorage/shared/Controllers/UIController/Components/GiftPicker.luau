--[[
	GiftPicker  (client component)
	------------------------------
	"Who is it for?" — the overlay a SHOP card's gift button puts up to find out. One
	panel, one scrolling list of the people in this server, one name per row.

	=== IT IS CODE-BUILT, AND EVERY OTHER SCREEN IN THIS GAME IS AUTHORED ========================

	That is a deliberate exception rather than a shortcut. The artist's PSD has no gift screen in it
	(`car ui (3).psd`, `Old/Shop`, draws three tabs and nothing else), and a list whose rows are one
	name and one headshot is the kind of thing an authored template makes harder rather than easier —
	the row count is however many people are in the server. So it takes the CHASSIS whole, exactly
	the way `OfflineController` builds WELCOME BACK out of the same four pieces: `Page.Panel`, a
	`Page.TitleBar`, rows drawn on `Page.SlotSquare` — and, for the close button, the calling
	page's OWN instance, cloned. Nothing new was invented and nothing is drawn in code that art
	exists for.

	=== FOUR THINGS TO KNOW ===================================================================

	1. THE ROWS ARE SIZED IN OFFSET AND THE PANEL IN SCALE. A scale-sized child of a ScrollingFrame
	   measures against the CANVAS, and `AutomaticCanvasSize` computes the canvas from the children,
	   so the two chase each other and a 300px window lays 900px rows. The Market and Shop pages
	   both carry that warning at length; this is the same trap and the same fix.

	2. IT LISTS THE SERVER, NOT A FRIENDS LIST, and `GiftConfig.PickFrom` explains why: nothing in
	   the delivery path needs the recipient to be present, but a name you can SEE is a name that is
	   definitely real and definitely spelt right. When a friends picker lands, this file is what
	   changes and nothing behind it has to.

	3. THE CLOSE BUTTON IS THE PAGE'S, CLONED, AND THE ONE BEFORE IT WAS INVISIBLE. That is the
	   bug this file shipped with and it failed silently: the button was built at
	   `Size = UDim2.fromScale(0.1, 0)` under a `UIAspectRatioConstraint`, and a constraint
	   defaults to `FitWithinMaxSize` — it fits the element inside the box its own `Size`
	   describes. A box with a ZERO axis has no room in it, so the button rendered 0x0 and the
	   only way out of this picker was to pick somebody. `DominantAxis` does not rescue it
	   either; that property is read only under `ScaleWithParentSize`. Cloning the page's own
	   button sidesteps the whole question and brings the artist's three faces, the `UIButton`
	   tag and the hover `Scale` that was tuned on it.

	4. IT REBUILDS ON EVERY OPEN, AND WATCHES WHILE IT IS UP. A server's roster changes constantly
	   and a picker showing somebody who left is a picker whose next press is refused by the server
	   with a sentence about it. Rebuilding is a dozen frames' work on a sixty player server and
	   happens only while somebody is looking at it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)
local WHITE = Color3.fromRGB(255, 255, 255)
--- The kit's panel navy, for the row plate's own fill under the art. See `UIAssets` note 2 — the
--- art is translucent on purpose and a row needs something behind it to read against the dim.
local NAVY = Color3.fromRGB(54, 65, 87)

--[[ The panel art's own face, READ OFF THE TEXTURE rather than picked: `Page.Panel` reports
	`rgba(40, 51, 75, 204)` at its centre through `CreateEditableImageAsync`. The colour is what
	the fill under it has to be and the 204 is why there has to be one at all — see `panel`. ]]
local PANEL_FACE = Color3.fromRGB(40, 51, 75)

--- Row height in pixels, and the gap between rows. Offset, not scale — see note 1.
local ROW_HEIGHT = 56
local ROW_GAP = 6

local GiftPicker = {}
GiftPicker.__index = GiftPicker

--- 9-slice from the recorded texture size and inset, exactly as `OfflineController.slice` does.
local function slice(image: ImageLabel | ImageButton, size: Vector2, inset: number)
	image.ScaleType = Enum.ScaleType.Slice
	image.SliceCenter = Rect.new(inset, inset, size.X - inset, size.Y - inset)
end

--[[ The calling page's own close button, cloned, or a fresh one off the same art if it has none.

	CLONED RATHER THAN REBUILT because every authored page in this kit already wears one, and a
	second-hand copy of a button is a button that cannot drift from it — it arrives with the
	artist's three faces, the `UIButton` tag (hover swell, click sound, `Selectable`) and whatever
	hover `Scale` was tuned on the original.

	RESIZED BY THE PANEL'S OWN SCALE, so it renders at the pixel size it was drawn at. Its `Size`
	is a fraction of the PAGE and it is about to live on a panel that is itself a fraction of the
	page, so dividing by that fraction cancels the two and the button comes out the size it was.
	That also carries its aspect across unchanged, which matters because the authored one is kept
	square by the page's aspect constraint rather than by one of its own.

	THE FALLBACK IS NOT DEAD CODE. `parent` is whatever page builds a picker, and the one that
	does today has an authored Close only because its import happened to ship with one. ]]
local function buildClose(page: GuiObject, panel: GuiObject): ImageButton
	local authored = page:FindFirstChild("Close")
	local close: ImageButton

	if authored and authored:IsA("ImageButton") then
		close = authored:Clone()
		close.Size = UDim2.fromScale(
			close.Size.X.Scale / panel.Size.X.Scale,
			close.Size.Y.Scale / panel.Size.Y.Scale
		)
	else
		close = Instance.new("ImageButton")
		close.BackgroundTransparency = 1
		--- The art has its own three faces; Roblox's press tint would lay over `PressedImage`.
		close.AutoButtonColor = false
		close.Image = UIAssets.url(UIAssets.Page.Close.Idle)
		close.HoverImage = UIAssets.url(UIAssets.Page.Close.Hover)
		close.PressedImage = UIAssets.url(UIAssets.Page.Close.Pressed)
		--- A REAL BOX ON BOTH AXES. Note 3 says what a zero one does under the constraint below.
		close.Size = UDim2.fromScale(0.1, 0.13)

		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = UIAssets.Size.Close.X / UIAssets.Size.Close.Y
		aspect.Parent = close

		close:AddTag("UIButton")
	end

	close.Name = "Close"
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	--- `OfflineController.CLOSE_POS`, because the cap under it is that file's cap. The bar runs
	--- 0.005 to 0.127, so 0.066 is its middle.
	close.Position = UDim2.fromScale(0.955, 0.066)
	close.ZIndex = 23
	return close
end

--[[ Build the overlay once and keep it. `open` and `close` only flip `Visible`.

	`parent` is the SHOP page's own frame rather than a ScreenGui of its own, which is what makes
	this close when the page closes without anything having to remember to. It also means the
	picker inherits the page's DisplayOrder and cannot end up behind it. ]]
function GiftPicker.new(parent: GuiObject)
	local self = setmetatable({}, GiftPicker)

	self._onPick = nil :: ((Player?) -> ())?
	--[[ TWO LISTS, AND THE SPLIT IS NOT COSMETIC. The close button is wired once and has to keep
		working across every open; the row buttons and the roster watchers belong to ONE open and are
		dropped on close, because their instances are destroyed by the next rebuild and the watchers
		would otherwise rebuild a frame nobody is looking at for the rest of the session. Putting
		both in one list meant `close` unwiring the close button, which the second open then had no
		way to shut. ]]
	self._connections = {} :: { RBXScriptConnection }
	self._openConnections = {} :: { RBXScriptConnection }

	--[[ `Active` is what makes it modal. A Frame does not swallow input by default, so without it
		the shop's own cards are still clickable through the dim — and a player who pressed one
		would buy it for themselves while a picker was asking who to gift it to. ]]
	local dim = Instance.new("Frame")
	dim.Name = "GiftPicker"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.Active = true
	dim.Visible = false
	dim.ZIndex = 20
	dim.Parent = parent
	self.Gui = dim

	--[[ THE PANEL NEEDS SOMETHING SOLID UNDER IT, for the same reason the ROWS below do and one
		that bites harder here.

		EVERY NAVY SURFACE IN THIS KIT IS AN 80% FACE — `Page.Panel` measures `rgba(40, 51, 75, 204)`
		through. That reads correctly over the 3D WORLD, which is where `OfflineController` puts this
		exact texture, and it does not read over another lit page, which is where this one goes: at
		one pass the shop's cards, prices and pass names stayed legible straight through the picker
		and it looked like a second screen printed on the first. A fifth of a white headline is still
		a headline.

		SO A FRAME IN THE ART'S OWN COLOUR GOES BEHIND IT, and because the two colours are the same
		the result is exactly the face the artist drew, at 100%: `0.8 * face + 0.2 * face = face`.
		Nothing is tinted and nothing has to be matched by eye.

		IT TAKES THE PANEL'S WHOLE RECT AND IS ROUNDED TO MATCH, which is the only version of this
		that has no seam. Insetting a square fill far enough to clear the corner curve was the first
		attempt and it left a visible band all the way round: `Slice.Panel` is 18 texture pixels, so
		the band was about 9 rendered pixels of face still at 80%, and the shop's bright text sat
		right behind the bottom edge of it.

		THE RADIUS IS `Slice.Panel` SCALED TO THE RENDER, and it has to be recomputed because a
		`UICorner` is in pixels while the panel is in scale. Slice is the distance from the art's
		edge to where its corner curve ENDS, so it is a shade LARGER than the true radius (the
		`Pill` note in `UIAssets.Slice` measures the same relationship: a 22px radius inside a 24px
		slice). Erring large is the safe direction: the fill rounds a hair more than the art and
		stays inside its silhouette, where erring small would square off the corners on top of it. ]]
	local fill = Instance.new("Frame")
	fill.Name = "PanelFill"
	fill.AnchorPoint = Vector2.new(0.5, 0.5)
	fill.Position = UDim2.fromScale(0.5, 0.5)
	fill.Size = UDim2.fromScale(0.62, 0.78)
	fill.BackgroundColor3 = PANEL_FACE
	fill.BorderSizePixel = 0
	fill.ZIndex = 20
	fill.Parent = dim

	local fillCorner = Instance.new("UICorner")
	fillCorner.Parent = fill

	local function fitCorner()
		fillCorner.CornerRadius =
			UDim.new(0, UIAssets.Slice.Panel * fill.AbsoluteSize.X / UIAssets.Size.Panel.X)
	end
	table.insert(self._connections, fill:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitCorner))
	fitCorner()

	local panel = Instance.new("ImageLabel")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.62, 0.78)
	panel.BackgroundTransparency = 1
	panel.Image = UIAssets.url(UIAssets.Page.Panel)
	panel.ZIndex = 21
	slice(panel, UIAssets.Size.Panel, UIAssets.Slice.Panel)
	panel.Parent = dim

	--[[ THE CAP IS THE PANEL'S FULL WIDTH AND SITS INSIDE IT, which is `OfflineController`'s own
		geometry (`BAR_SIZE` 0.994 x 0.122 at `BAR_Y` 0.005) and not a new decision. This was a 0.86
		wide badge hung 2% ABOVE the panel, and against an opaque panel that reads as a separate
		floating label rather than as the screen's own header: every other page in this kit, authored
		or built, caps its panel edge to edge. ]]
	local bar = Instance.new("ImageLabel")
	bar.Name = "TitleBar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.fromScale(0.5, 0.005)
	bar.Size = UDim2.fromScale(0.994, 0.122)
	bar.BackgroundTransparency = 1
	--[[ BLUE IS NOT AN OPTION HERE — the kit ships three caps and none of them is the shop's own
		blue. Green is what this kit pays money out in (`UIAssets.Page.TitleBar`), and a gift is
		money moving, so it is the same cap WELCOME BACK wears. ]]
	bar.Image = UIAssets.url(UIAssets.Page.TitleBar.Green)
	bar.ScaleType = Enum.ScaleType.Stretch
	bar.ZIndex = 22
	bar.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.46)
	title.Size = UDim2.fromScale(0.8, 0.5)
	title.BackgroundTransparency = 1
	title.FontFace = FONT
	title.TextColor3 = WHITE
	title.TextScaled = true
	title.ZIndex = 23
	title.Parent = bar
	self.Title = title

	local close = buildClose(parent, panel)
	close.Parent = panel

	table.insert(self._connections, close.MouseButton1Click:Connect(function()
		self:_pick(nil)
	end))

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.AnchorPoint = Vector2.new(0.5, 0)
	list.Position = UDim2.fromScale(0.5, 0.16)
	list.Size = UDim2.fromScale(0.88, 0.76)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = WHITE
	list.ScrollBarImageTransparency = 0.5
	--- The canvas is computed from the rows, which is only safe because the rows are in OFFSET.
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ZIndex = 22
	list.Parent = panel
	self.List = list

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, ROW_GAP)
	layout.Parent = list

	local empty = Instance.new("TextLabel")
	empty.Name = "Empty"
	empty.AnchorPoint = Vector2.new(0.5, 0.5)
	empty.Position = UDim2.fromScale(0.5, 0.5)
	empty.Size = UDim2.fromScale(0.8, 0.16)
	empty.BackgroundTransparency = 1
	empty.FontFace = FONT
	empty.TextColor3 = WHITE
	empty.TextTransparency = 0.35
	empty.TextScaled = true
	empty.Visible = false
	empty.ZIndex = 22
	empty.Parent = panel
	self.Empty = empty

	return self
end

--[[ One row: a headshot, a display name, and the whole thing is the button.

	THE THUMBNAIL IS A `rbxthumb` URL, NOT A WEB CALL. `Players:GetUserThumbnailAsync` yields and
	would make building a sixty-row list sixty round trips; the URL form is resolved by the engine,
	renders a placeholder until it arrives, and never blocks. ]]
function GiftPicker._row(self, player: Player, order: number)
	local row = Instance.new("ImageButton")
	row.Name = tostring(player.UserId)
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = NAVY
	row.BackgroundTransparency = 0.25
	row.AutoButtonColor = false
	row.Image = UIAssets.url(UIAssets.Page.SlotSquare)
	row.ImageTransparency = 0.15
	row.LayoutOrder = order
	row.ZIndex = 23
	slice(row, UIAssets.Size.SlotSquare, UIAssets.Slice.SlotSquare)
	row.Parent = self.List

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = row

	local head = Instance.new("ImageLabel")
	head.Name = "Head"
	head.AnchorPoint = Vector2.new(0, 0.5)
	head.Position = UDim2.new(0, 8, 0.5, 0)
	head.Size = UDim2.new(0, ROW_HEIGHT - 16, 0, ROW_HEIGHT - 16)
	head.BackgroundTransparency = 1
	head.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=60&h=60", player.UserId)
	head.ZIndex = 24
	head.Parent = row

	local headCorner = Instance.new("UICorner")
	headCorner.CornerRadius = UDim.new(1, 0)
	headCorner.Parent = head

	local name = Instance.new("TextLabel")
	name.Name = "PlayerName"
	name.AnchorPoint = Vector2.new(0, 0.5)
	name.Position = UDim2.new(0, ROW_HEIGHT + 4, 0.5, 0)
	name.Size = UDim2.new(1, -(ROW_HEIGHT + 16), 0, 24)
	name.BackgroundTransparency = 1
	name.FontFace = FONT
	--[[ DISPLAY NAME, and the @username is not shown beside it. Two names on a row is twice the
		text at half the size, and the picker is a list of people the player can see standing in
		front of them — the name over their head is the one they will recognise. The server
		validates the USER ID this resolves to, never the name, so nothing here is load-bearing. ]]
	name.Text = player.DisplayName
	name.TextColor3 = WHITE
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextScaled = true
	name.ZIndex = 24
	name.Parent = row

	table.insert(self._openConnections, row.MouseButton1Click:Connect(function()
		self:_pick(player)
	end))
end

--- Rebuild the list from who is in the server right now. See note 4.
function GiftPicker._rebuild(self)
	for _, child in self.List:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local order = 0
	for _, player in Players:GetPlayers() do
		if player ~= Players.LocalPlayer then
			order += 1
			self:_row(player, order)
		end
	end

	self.Empty.Visible = order == 0
	self.List.Visible = order > 0
end

function GiftPicker._pick(self, player: Player?)
	local callback = self._onPick
	self:close()
	if callback then
		callback(player)
	end
end

--[[ Put it up. `onPick` is called exactly once — with a player, or with nil for a cancel — and the
	overlay is down before it runs, so a callback that opens a Robux prompt is not doing it behind
	a modal frame that swallows input. ]]
function GiftPicker.open(self, title: string, emptyText: string, onPick: (Player?) -> ())
	self._onPick = onPick
	self.Title.Text = title
	self.Empty.Text = emptyText
	self:_rebuild()

	--[[ Watched only while it is up, and both are torn down on close. A picker left listening to a
		sixty player server for the rest of the session is a rebuild per join for a frame nobody is
		looking at. ]]
	table.insert(self._openConnections, Players.PlayerAdded:Connect(function()
		if self.Gui.Visible then
			self:_rebuild()
		end
	end))
	table.insert(self._openConnections, Players.PlayerRemoving:Connect(function()
		if self.Gui.Visible then
			--- Deferred: `GetPlayers` still holds the leaver on this frame.
			task.defer(function()
				if self.Gui.Visible then
					self:_rebuild()
				end
			end)
		end
	end))

	self.Gui.Visible = true
end

function GiftPicker.close(self)
	self.Gui.Visible = false
	self._onPick = nil
	for _, connection in self._openConnections do
		connection:Disconnect()
	end
	self._openConnections = {}
end

function GiftPicker.destroy(self)
	self:close()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._connections = {}
	self.Gui:Destroy()
end

return GiftPicker
