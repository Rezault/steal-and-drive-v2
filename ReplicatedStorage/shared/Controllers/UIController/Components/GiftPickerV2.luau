--[[
	GiftPickerV2  (client component)
	--------------------------------
	"Who is it for?" The overlay a SHOP card's gift button puts up to find out, on the Cartoony
	Kit. One panel, one row per person in this server, one button per row.

	=== IT IS AUTHORED NOW, AND THAT IS THE WHOLE DIFFERENCE ==================================

	`Components/GiftPicker` builds the shipping one in CODE: a dim, a panel, a title bar, a close
	button cloned off the page, a scrolling list and a row of two labels and a headshot, all in
	instances made at runtime. Its header opens by admitting that is an exception in a project where
	every other screen is authored, and gives the reason: the artist's PSD had no gift screen in it.

	The kit has one. `InviteFriendsUI` is a list of people with an avatar, a display name, a username
	and a button on each row, which is a gift picker with one word changed. So `BuildShopV2` clones it
	into the Shop page and this file only fills it.

	=== IT IS A KIT FRAME, SO `KitPage` DOES THE WORK =========================================

	The panel has the same shape every kit screen has (`Header{Title, CloseBtn}`, `Main{Scrolling
	Frame + row templates}`, `BG`), so it binds with `KitPage.bind` and gets the header, the close
	button on `Activated`, the selection trap, the row template lifted out of the list, and the list
	sized in offset pixels with a canvas computed from the rows. That last one is not a nicety: the
	kit ships the exact `AutomaticCanvasSize` plus scale-rows trap that made the shipping picker size
	its rows in offset by hand.

	THIS IS THE FIRST CALLER OF `bind` RATHER THAN `new`. A picker is not a page: it has no entry in
	`PagesV2`, `UIController` does not route to it, and its close button answers to the card that
	opened it. Everything else about it is a kit screen.

	=== FOUR THINGS TO KNOW ==================================================================

	1. IT LIVES INSIDE THE SHOP PAGE, which is what makes it close when the page closes without
	   anything having to remember to, and it inherits the page's `UIScale` and draw order so it can
	   never end up behind the cards it is covering. Unchanged from the shipping picker.

	2. IT LISTS THE SERVER, NOT A FRIENDS LIST, and `GiftConfig.PickFrom` explains why: nothing in
	   the delivery path needs the recipient to be present, but a name you can SEE is a name that is
	   definitely real and definitely spelt right. When a friends picker lands, this file is what
	   changes and nothing behind it has to.

	3. IT SHOWS BOTH NAMES, WHERE THE SHIPPING ONE SHOWS THE DISPLAY NAME ALONE. That was a real
	   argument, since two names on a row is twice the text at half the size, and it was an argument
	   about a row built in code. The artist drew two lines at two sizes, so the cost is already
	   paid, and on this screen the second line earns its place: display names are not unique, this
	   is the one list in the game where picking the wrong person spends Robux, and the `@username`
	   is the only thing that tells two identical display names apart.

	4. IT REBUILDS ON EVERY OPEN, AND WATCHES WHILE IT IS UP. A server's roster changes constantly
	   and a picker showing somebody who left is a picker whose next press the server refuses with a
	   sentence about it. Rebuilding is a dozen frames' work on a sixty player server and happens
	   only while somebody is looking at it.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KitPage = require(script.Parent.Parent.KitPage)
local GamepadInput = require(ReplicatedStorage.shared.Modules.GamepadInput)

--[[ ON A CONTROLLER (2026-10-15). The picker sits inside the Shop page, so `GamepadNav` sees only
	the page: it never put the highlight into the picker, and its B shut the whole Shop rather than
	the picker. So the picker does both itself. B is bound above `GamepadNav`'s own (default High) so
	it is this one that answers while the picker is up, and the highlight goes back to the gift button
	that opened it. `KitPage.bind` already made the panel a selection group, so the DPad stays in. ]]
local PAD_BACK = "GiftPickerBack"
local PAD_PRIORITY = Enum.ContextActionPriority.High.Value + 100
--- Frames to keep offering the first row: the rows are stamped this frame and the engine refuses a
--- selection it has not drawn yet.
local SEED_FRAMES = 10

--- The frames `BuildShopV2` left in the page. Its header says what each was cut from.
local OVERLAY_NAME = "GiftPicker"
local PANEL_NAME = "Panel"
local ROW_TEMPLATE = "OnlineTemplate"
--- The kit's `OnlineTitle`, kept and renamed: the picker's empty state in the artist's own type.
local NOTE_NAME = "Note"
local PICK_BUTTON = "PickBtn"

--[[ A headshot as a `rbxthumb` URL, NOT a web call. `Players:GetUserThumbnailAsync` yields, and a
	sixty row list would be sixty round trips; the URL form is resolved by the engine, renders a
	placeholder until it arrives and never blocks. ]]
local function headshot(userId: number): string
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=60&h=60", userId)
end

local GiftPickerV2 = {}
GiftPickerV2.__index = GiftPickerV2

--[[ Bind the overlay that is already in the page.

	`page` is the Shop page's own frame. Nothing is created here: if `BuildShopV2` has not been run
	against this place, the overlay is missing and that is a build problem rather than something to
	paper over at runtime, so it is said out loud and the picker becomes inert. ]]
function GiftPickerV2.new(page: GuiObject)
	local self = setmetatable({}, GiftPickerV2)

	self._onPick = nil :: ((Player?) -> ())?
	--- Belongs to ONE open: the row buttons and the roster watchers are dropped on close, because
	--- their instances are destroyed by the next rebuild and the watchers would otherwise keep
	--- rebuilding a frame nobody is looking at for the rest of the session.
	self._openConnections = {} :: { RBXScriptConnection }

	local overlay = page:FindFirstChild(OVERLAY_NAME)
	local panel = overlay and overlay:FindFirstChild(PANEL_NAME)
	if not (overlay and overlay:IsA("GuiObject") and panel and panel:IsA("GuiObject")) then
		warn(string.format("[GiftPickerV2] %s has no `%s.%s`. Run BuildShopV2.", page:GetFullName(), OVERLAY_NAME, PANEL_NAME))
		return self
	end

	self.Gui = overlay
	self.Kit = KitPage.bind(panel)

	--[[ `bind` shuts what it binds, which is right for a page and wrong here: the thing that opens
		and closes is the DIM, and the panel is simply part of it. Put the panel back up and let the
		overlay carry the state. ]]
	panel.Visible = true
	overlay.Visible = false

	--[[ The close button hands back a nil pick rather than closing a page. An instance field, which
		SHADOWS `KitPage.onClose`. That is normally a trap in this project; here it is the mechanism:
		`bind` deliberately dispatches through `self` at press time so this can exist. ]]
	self.Kit.onClose = function()
		self:_pick(nil)
	end

	self.Note = self.Kit.Templates and self.Kit.Templates[NOTE_NAME]

	return self
end

--[[ One row: an avatar, the two names, and a button that picks that person.

	The row arrives with the artist's button already tagged `UIButton`, so it has the hover, the
	click sound and `Selectable` for a controller without anything here asking for them. ]]
function GiftPickerV2._row(self, player: Player)
	local row = self.Kit:newRow(ROW_TEMPLATE)
	if not row then
		return
	end
	row.Name = tostring(player.UserId)

	local display = row:FindFirstChild("Display")
	if display and display:IsA("TextLabel") then
		display.Text = player.DisplayName
	end
	local username = row:FindFirstChild("Username")
	if username and username:IsA("TextLabel") then
		--[[ The server validates the USER ID this resolves to, never the name, so nothing here is
			load bearing. It is the line that tells two identical display names apart. ]]
		username.Text = "@" .. player.Name
	end

	local profile = row:FindFirstChild("Profile")
	local avatar = profile and profile:FindFirstChild("Avatar")
	if avatar and avatar:IsA("ImageLabel") then
		avatar.Image = headshot(player.UserId)
	end

	local button = row:FindFirstChild(PICK_BUTTON)
	if button and button:IsA("GuiButton") then
		table.insert(self._openConnections, button.Activated:Connect(function()
			self:_pick(player)
		end))
	end
end

--- Rebuild the list from who is in the server right now. See note 4.
function GiftPickerV2._rebuild(self)
	self.Kit:clearRows()

	local count = 0
	for _, player in Players:GetPlayers() do
		if player ~= Players.LocalPlayer then
			count += 1
			self:_row(player)
		end
	end

	--- Alone in the server. The note is a row like any other, so it takes the list's own place
	--- rather than floating over an empty one.
	if count == 0 and self.Note then
		self.Kit:newRow(NOTE_NAME)
	end
end

function GiftPickerV2._pick(self, player: Player?)
	local callback = self._onPick
	self:close()
	if callback then
		callback(player)
	end
end

--[[ Put it up. `onPick` is called exactly once, with a player or with nil for a cancel, and the
	overlay is down before it runs, so a callback that opens a Robux prompt is not doing it behind a
	modal frame that swallows input. ]]
function GiftPickerV2.open(self, title: string, emptyText: string, onPick: (Player?) -> ())
	if not self.Gui then
		return
	end

	self._onPick = onPick
	self.Kit:setTitle(title)
	if self.Note and self.Note:IsA("TextLabel") then
		--- Written on the TEMPLATE, before `_rebuild` stamps it, so the copy carries the text.
		self.Note.Text = emptyText
	end
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

	GamepadInput.bind({
		actionName = PAD_BACK,
		keyCode = Enum.KeyCode.ButtonB,
		callback = function()
			self:_pick(nil)
		end,
		parent = self.Kit.CloseBtn,
		iconPosition = UDim2.new(0.5, 0, -0.4, 0),
		priority = PAD_PRIORITY,
	})
	if GamepadInput.isGamepadActive() then
		self._returnTo = GuiService.SelectedObject
		self:_seed()
	end
end

--- The highlight onto the first person's button, or the X when the server is just you.
function GiftPickerV2._seed(self)
	local overlay = self.Gui
	local function shown(object: Instance): boolean
		local node: Instance? = object
		while node and node ~= overlay do
			if node:IsA("GuiObject") and not node.Visible then
				return false
			end
			node = node.Parent
		end
		return node == overlay
	end
	local function pick(): GuiButton?
		local best: GuiButton? = nil
		local bestY = math.huge
		for _, descendant in overlay:GetDescendants() do
			if descendant:IsA("GuiButton") and descendant ~= self.Kit.CloseBtn and descendant.Selectable and shown(descendant) then
				if descendant.AbsolutePosition.Y < bestY then
					best, bestY = descendant, descendant.AbsolutePosition.Y
				end
			end
		end
		return best or self.Kit.CloseBtn
	end
	task.spawn(function()
		for _ = 1, SEED_FRAMES do
			if not overlay.Visible then
				return
			end
			local current = GuiService.SelectedObject
			if current and current:IsDescendantOf(overlay) and current ~= self.Kit.CloseBtn then
				return
			end
			local target = pick()
			if target and target ~= current then
				GuiService.SelectedObject = target
			end
			task.wait()
		end
	end)
end

function GiftPickerV2.close(self)
	if not self.Gui then
		return
	end
	self.Gui.Visible = false
	self._onPick = nil
	for _, connection in self._openConnections do
		connection:Disconnect()
	end
	self._openConnections = {}

	GamepadInput.unbind(PAD_BACK)
	--- Back onto the gift button that opened this, if it is still there (a purchase re-stamps the
	--- cards); otherwise `GamepadNav` puts the lost highlight on the nearest card.
	local returnTo = self._returnTo
	self._returnTo = nil
	local selected = GuiService.SelectedObject
	if (selected == nil or selected:IsDescendantOf(self.Gui)) and returnTo and returnTo.Parent and returnTo.Visible then
		GuiService.SelectedObject = returnTo
	end
end

return GiftPickerV2
