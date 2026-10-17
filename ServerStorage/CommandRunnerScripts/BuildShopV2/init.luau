--[[
	BuildShopV2: Command Runner command

	Builds `StarterGui.MainUIV2.Pages.Shop` out of the Cartoony Kit's `RobuxShopUI`, with the
	owner's own card list (`ServerStorage.UIImports.ShopV2List`) in place of the kit's, and the gift
	picker overlay that lives inside it out of `InviteFriendsUI`. Phase 3 of
	`docs/NewUI-Migration-Plan.md`; the running record is `docs/NewUI-Migration-Notes.md`.

	Run `BuildMainUIV2` first: this fills in a screen that already exists rather than creating one.

	=== IT REBUILDS, IT DOES NOT MERGE =======================================================

	`Pages.Shop` is destroyed and made again on every run, the same bargain `BuildHudV2` strikes: a
	hand edit in the Explorer is lost on the next run, and the fix is to make the edit here, or IN
	THE STASH. Nothing else under `Pages` is touched, so the other pages are safe from this command.

	=== THE LIST IS THE OWNER'S, NOT THE KIT'S (2026-10-15) ==================================

	The kit's list was a set of sample rows (`FeaturedTitle`, `StarterPack`, `CashTripleRow`...) that
	`PagesV2/Shop` stamped copies of. The owner replaced it with a finished list: every card a real
	product with its own artwork, naming what it sells in `ShopProductKey` and `ShopCatalogKind`,
	laid out in offset with each row's share of the list in `PreviewHeightScale`. `PagesV2/Shop`
	now paints those cards in place, and its header has the contract.

	SO THE STASH IS THE SOURCE. Edit `ServerStorage.UIImports.ShopV2List` (or re-import over it) and
	re-run this; edit `Pages.Shop.Main.ScrollingFrame` directly for a look, and the next run puts
	the stash back. The stash is REQUIRED: without it there is no list the page module can fill,
	so the command stops rather than building a page with the kit's samples in it.

	THE LIST GOES IN AFTER `KitGrowth`, not before. The owner's text caps were authored on the
	grown page (its price pills read 44 and 17, the grown kit's numbers), so growing them again would
	draw every label a fifth too big.

	The kit-list fixes this command used to make (renaming `StarterPack`'s second `Title`, naming
	every card icon `Icon`, pulling overhanging labels onto their card, shortening the small cash
	tiles, dropping `ServerLuck` and `CratePack`) went with the kit's list. The owner's list was
	drawn with all of them already made.

	=== THE GIFT PICKER IS AN OVERLAY, NOT A PAGE ============================================

	`Components/GiftPicker` builds the shipping picker in CODE, and its own header says why: the old
	PSD had no gift screen in it. The kit does. `InviteFriendsUI` is a list of people with a headshot,
	a display name, a username and a button on each row, which is a gift picker with one word changed.
	So the V2 picker is authored like everything else and `GiftPickerV2` only fills it.

	IT IS PARENTED INSIDE THE SHOP PAGE, which is what makes it close when the page closes without
	anything having to remember to, and it inherits the page's `UIScale` and draw order. That part is
	unchanged from the shipping picker.

	THE ROW KEEPS BOTH NAMES. The old picker deliberately drew the display name alone, arguing that
	two names on a row is twice the text at half the size. The artist drew two lines at two sizes, so
	that cost is already paid. And on this screen the second line earns its place: display names are
	not unique, this is the one list in the game where picking the wrong person spends Robux, and the
	`@username` is the only thing that tells two identical display names apart.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)
local KitGrowth = require(ReplicatedStorage.shared.Modules.KitGrowth)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage

--- The page this command owns, and the kit frame it is cut from.
local PAGE_NAME = "Shop"
local KIT_FRAME = "RobuxShopUI"

--- The owner's card list, under `ServerStorage.UIImports`. See the header.
local LIST_STASH = "ShopV2List"

--- The overlay inside it, and the kit frame THAT is cut from. See the header.
local PICKER_NAME = "GiftPicker"
local PICKER_FRAME = "InviteFriendsUI"

--[[ How big the picker is inside the page. The kit drew it square (its own
	`UIAspectRatioConstraint` is 1.0) and the shop page is 1.475 wide, so the constraint decides the
	width and this only says how much of the page's HEIGHT it takes. Near full: it is modal, it is
	the only thing being read while it is up, and a small panel floating on a large one reads as a
	tooltip rather than as a question. ]]
local PICKER_SIZE = 0.95

--- Over the page's own cards. The shipping picker uses 20 to 24 for the same stack, and nothing
--- authored in the kit goes near it.
local PICKER_ZINDEX = 20

--- What the picker's row button says. The card's gift button asked; this one answers, per person.
local PICK_LABEL = "Give"
local PICK_BUTTON = "PickBtn"

--- The kit's `OnlineTitle`, kept for the picker's empty state. See where it is renamed.
local NOTE_NAME = "Note"

--- The kit template, or nil and a sentence saying which step of the path was missing.
local function findTemplate(): (Instance?, string?)
	local node: Instance = ServerStorage
	for _, step in TEMPLATE_PATH do
		local child = node:FindFirstChild(step)
		if not child then
			return nil, string.format("%s has no child `%s`.", node:GetFullName(), step)
		end
		node = child
	end
	local screen = node:FindFirstChildWhichIsA("ScreenGui")
	if not screen then
		return nil, string.format("%s holds no ScreenGui.", node:GetFullName())
	end
	local container = screen:FindFirstChild("Container")
	if not container then
		return nil, string.format("%s has no `Container` of frames.", screen:GetFullName())
	end
	return container, nil
end

--- How many rows the owner's list has and how many cards it sells, for the report.
local function countList(list: Instance): (number, number)
	local rows = 0
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			rows += 1
		end
	end
	local cards = 0
	for _, descendant in list:GetDescendants() do
		if descendant:GetAttribute("ShopProductKey") ~= nil then
			cards += 1
		end
	end
	return rows, cards
end

return {
	Description = "Build StarterGui.MainUIV2.Pages.Shop from the Cartoony Kit's RobuxShopUI with the owner's card list (ServerStorage.UIImports.ShopV2List) in it, and the GiftPicker overlay inside it from InviteFriendsUI. Rebuilds the page every run.",
	Tags = { "UI", "NewUI" },
	AutoRecordChanges = true,

	Arguments = {} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		local screen = StarterGui:FindFirstChild(SCREEN_NAME)
		local pages = screen and screen:FindFirstChild("Pages")
		if not (pages and pages:IsA("GuiObject")) then
			out:error(string.format("No StarterGui.%s.Pages. Run BuildMainUIV2 first.", SCREEN_NAME))
			return
		end

		local container, why = findTemplate()
		if not container then
			out:error(string.format("The kit is not where it should be: %s", why))
			return
		end

		local kitShop = container:FindFirstChild(KIT_FRAME)
		local kitPicker = container:FindFirstChild(PICKER_FRAME)
		if not kitShop then
			out:error(string.format("%s has no `%s` to build from.", container:GetFullName(), KIT_FRAME))
			return
		end
		if not kitPicker then
			out:error(string.format("%s has no `%s` to cut the picker from.", container:GetFullName(), PICKER_FRAME))
			return
		end

		local imports = ServerStorage:FindFirstChild("UIImports")
		local stash = imports and imports:FindFirstChild(LIST_STASH)
		if not (stash and stash:IsA("ScrollingFrame")) then
			out:error(string.format("No ScrollingFrame at ServerStorage.UIImports.%s: the shop's card list is not stashed. See the header.", LIST_STASH))
			return
		end

		local existing = pages:FindFirstChild(PAGE_NAME)
		if existing then
			existing:Destroy()
		end

		-- === The page ===================================================================

		local page = kitShop:Clone()
		page.Name = PAGE_NAME

		local main = page:FindFirstChild("Main")
		local kitList = main and main:FindFirstChildOfClass("ScrollingFrame")
		if not (main and kitList) then
			out:error("The kit's RobuxShopUI has no `Main.ScrollingFrame`; there is nowhere to put the list.")
			page:Destroy()
			return
		end

		-- === The picker =================================================================

		--[[ A dim that swallows input, and the kit's friends panel on top of it.

			`Active` is what makes it modal. A Frame does not swallow input by default, so without it
			the shop's own BUY pills are still pressable through the dim, and a player who pressed one
			would buy something for themselves while a picker was asking who to give it to. ]]
		local dim = Instance.new("Frame")
		dim.Name = PICKER_NAME
		dim.AnchorPoint = Vector2.new(0.5, 0.5)
		dim.Position = UDim2.fromScale(0.5, 0.5)
		dim.Size = UDim2.fromScale(1, 1)
		dim.BackgroundColor3 = Color3.new(0, 0, 0)
		dim.BackgroundTransparency = 0.45
		dim.BorderSizePixel = 0
		dim.Active = true
		dim.Visible = false
		dim.ZIndex = PICKER_ZINDEX
		dim.Parent = page

		local panel = kitPicker:Clone()
		panel.Name = "Panel"
		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Position = UDim2.fromScale(0.5, 0.5)
		--- Its own aspect constraint came with the clone and decides the width. See `PICKER_SIZE`.
		panel.Size = UDim2.fromScale(PICKER_SIZE, PICKER_SIZE)
		panel.Visible = true
		panel.ZIndex = PICKER_ZINDEX + 1
		panel.Parent = dim

		local pickerList = panel:FindFirstChild("Main")
		pickerList = pickerList and pickerList:FindFirstChildOfClass("ScrollingFrame")
		if not pickerList then
			out:error("The kit's InviteFriendsUI has no `Main.ScrollingFrame`; the picker has no list.")
			page:Destroy()
			return
		end

		--[[ The picker lists WHO IS IN THIS SERVER, so there is no offline half to it and no pair of
			headings to tell two halves apart. The title bar already says what the list is for.

			`OnlineTitle` IS KEPT AND RENAMED. It is the artist's own heading type, and the picker needs
			exactly one line of that shape: the note shown to somebody who is alone in the server. Using
			it means the empty state is drawn in the kit's hand rather than built in code, which is what
			the shipping picker had to do. ]]
		local trimmed = 0
		local noted = false
		for _, child in pickerList:GetChildren() do
			if child.Name == "OfflineTemplate" or child.Name == "OfflineTitle" then
				child:Destroy()
				trimmed += 1
			elseif child.Name == "OnlineTitle" then
				child.Name = NOTE_NAME
				noted = true
			end
		end
		if not noted then
			out:warn(string.format("No `OnlineTitle` to rename `%s`; the picker will have no empty-state line.", NOTE_NAME))
		end

		--- The row button, named for what it does rather than for the kit's own feature.
		local labelled = 0
		for _, child in pickerList:GetChildren() do
			if child.Name == "OnlineTemplate" then
				local button = child:FindFirstChild("InviteBtn")
				if button and button:IsA("GuiButton") then
					button.Name = PICK_BUTTON
					local title = button:FindFirstChild("Title")
					if title and title:IsA("TextLabel") then
						title.Text = PICK_LABEL
						labelled += 1
					end
				end
			end
		end
		if labelled == 0 then
			out:warn("No `OnlineTemplate.InviteBtn` to rename; the picker's rows will have no button.")
		end

		--- Bigger than the kit, text caps included. See `Modules/KitGrowth`.
		KitGrowth.apply(page, KitGrowth.Pages)

		-- === The owner's list, after the growth (header) ================================

		local list = stash:Clone()
		list.Name = kitList.Name
		list.AnchorPoint = kitList.AnchorPoint
		list.Position = kitList.Position
		list.Size = kitList.Size
		list.ZIndex = kitList.ZIndex
		list.Visible = true
		kitList:Destroy()
		list.Parent = main

		page.Parent = pages

		local rows, cards = countList(list)
		out:print(
			string.format(
				"Built %s.Pages.%s from the kit's %s with the owner's list from UIImports.%s in it: %d row(s), %d card(s).",
				SCREEN_NAME,
				PAGE_NAME,
				KIT_FRAME,
				LIST_STASH,
				rows,
				cards
			)
		)
		out:print(
			string.format(
				"GiftPicker overlay from %s: %d offline pieces trimmed, `OnlineTitle` kept as `%s`, the row button renamed `%s` on %d template(s).",
				PICKER_FRAME,
				trimmed,
				NOTE_NAME,
				PICK_BUTTON,
				labelled
			)
		)

		pcall(function()
			props:SetSelection({ page })
		end)
	end,
} :: Types.ScriptModule
