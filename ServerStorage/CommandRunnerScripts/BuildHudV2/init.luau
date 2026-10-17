--[[
	BuildHudV2: Command Runner command

	Builds `StarterGui.MainUIV2.HUD` out of the Cartoony Kit's own HUD frame: the six-button grid
	(named `Rail`; Index, Shop, Cars, Quest, Radio, Settings), the cash block (`Cash`, with `TextLabel` and `Rate`), the `Play` button, and the
	`Boosts` row parked out of sight. Phase 2 of `docs/NewUI-Migration-Plan.md`, and the grid's bare
	icons are Phase 5; the running record is `docs/NewUI-Migration-Notes.md`.

	Run `BuildMainUIV2` first: this one fills in a screen that already exists rather than creating one.

	=== IT REBUILDS, IT DOES NOT MERGE =======================================================

	The four blocks it owns are destroyed and made again on every run. That is the opposite of
	`BuildMainUIV2`, which keeps what it finds, and the difference is what each file is for: that one
	creates an empty room somebody then furnishes, this one IS the furniture. A hand edit to `Rail` or
	`Cash` is therefore lost on the next run, and the fix is to make the edit here. Anything else under
	`HUD` is left alone, so a frame a later phase adds survives.

	=== WHERE THE NAMES COME FROM ============================================================

	Not from taste. Three files already resolve this HUD by path and none of them should have to learn
	a second set of names:

	  • `RaceEntryController` hides `HUD.Rail` as one box for a run and finds `HUD.Play` by its
	    `Action` attribute.
	  • `GarageHudController` writes the balance into `HUD.Cash.TextLabel` and the garage rate into
	    `HUD.Cash.Rate`.
	  • `TutorialController` points its arrow at `HUD.Play` and steps around `Rail` as one rectangle.

	The kit calls the same things `SideBtns`, `BottomInfo.Cash.Title` and `BottomInfo.FriendBoost.Title`,
	and has no Play button at all. Renaming happens here, once, at build time.

	=== THE CASH BLOCK IS FLATTENED ==========================================================

	`GarageHudController` looks for `TextLabel` and `Rate` as DIRECT children of `Cash`. The kit nests
	them one level deeper, in two rows that each carry a `UIListLayout`. So the two rows are dissolved
	and their four pieces are parented straight onto `Cash` at the positions the layouts had put them.

	Those positions are measured, not guessed: the kit HUD was cloned into a `CoreGui` ScreenGui with
	`MainUIV2`'s own inset settings, given a frame to lay itself out, and every rect read back as a
	fraction of the block. The numbers in `CASH_PARTS` are that reading. Dropping the layouts costs
	nothing, because every kit box is sized in scale and the layout was only ever placing fixed boxes.

	The two labels are switched to `TextXAlignment = Left`, which the kit does not need and we do: the
	kit's placeholder `$999,999,999` fills its box, a real balance does not, and centred text would put
	the balance and the rate line on two different left edges.

	=== THE ICONS ARE THE KIT'S, AND THEY ARE STAYING ========================================

	The kit ships generic simulator art (a chest, a book, a rock, a ball, a potion, a gift), and that
	is what these six cells use. Open question 7 asked whether to draw car-themed replacements and the
	answer was no: the kit's own art is fine, and if a cell ever earns a picture of its own the source
	is the Gvesster rail art already in `UIAssets` rather than a new drawing. So nothing here goes
	through the Open Cloud upload and no id below is a placeholder waiting to be swapped.

	The two that were placed rather than inherited: the book on Index and the gift on Shop, because
	those two read correctly. Quest kept the artist's. Three cells earned a picture of their own
	since: Cars (the rail's car) and Radio and Settings (the topbar chips' speaker and gear), all
	Gvesster art, none of it new.

	THE BASKET MOVED TO SHOP AND QUEST WEARS A SCROLL (Dylan, 2026-09-16). A basket says "buy", which
	is the Robux shop's word, not the quest board's; the gift it replaced there is still on every
	shop card's gift button. The scroll is the plain paper one out of Gvesster's `Free Icon Pack v3.1`
	(`Item/Scroll/256px/Scroll 1st Outline`), the pack this kit's icons come from, and the same
	drawing the old rail's Quest button is built on. Taken from the pack rather than off the old
	button because the old art had its outline recoloured; the pack's navy outline is the one the
	kit's book, basket and gift wear. PixFixed like the others (alpha and every opaque pixel
	byte-identical, the 995 transparent pixels touching the art moved from grey-teal to the outline
	navy) and checked back after upload.

	THE BOOK, BASKET, GIFT AND CAR ARE RE-UPLOADS OF THAT SAME ART, PIXFIXED (Dylan, 2026-09-16). The
	artist's uploads were 64px (basket, gift) and 128px (book) with every transparent pixel black, and
	our car's were black too, so the engine's filtering pulled a dark fringe in round the outline and
	the two small ones went soft at rail size. The kit's `Design File.fig` holds the same three
	drawings at 256px (matched against the uploads, not assumed); those were taken out, run through
	PixFix with the car, and uploaded. Alpha is byte-identical to the source and each stored image
	was downloaded back and compared. Radio and Settings were already clean. The kit's own ids are in
	the comment on each line, for putting one back.

	=== THE GRID IS BARE ICONS ===============================================================

	Dylan, 2026-09-16: "remove the background image for the HUD and only make it the icons", no
	words under them, and the words back as a tooltip when you point at one. So each cell loses
	everything that drew the kit's tile: the cell's own fill, gradient, rim and corner, and the
	button's face, its inner stroke (`Container`) and the checker pattern (`BG`, a CanvasGroup, so
	five fewer render textures as a side effect). What is left drawing is `Icon`, grown to fill the
	face the tile used to be, so the icon has the weight the tile had and the hit target is exactly
	the art a player sees.

	THE CELL AND THE BUTTON KEEP THEIR SIZES. The cell is what the grid lays out, `Rail` is the one
	box the race hide and the tutorial reason about, and the button's rect is what `GamepadNav`
	groups into rows. None of the three moved, so none of those files had to hear about this.

	THE CAPTION BECAME THE TOOLTIP rather than being deleted and redrawn: the kit's `Category` label
	is renamed `Hint`, hidden, and moved to sit under the icon. `Components/Button` shows a child
	named `Hint` for as long as a button is pointed at, by a cursor or by a gamepad highlight, so
	that name is the whole of the wiring. It keeps the kit's font, outline and size cap, which is
	what the kit draws for every small label on its HUD (the `Boosts` row is the same bare icon with
	the same outlined type under it, and no pill: in this kit a pill is a button).

	`Button`'s whole-button swell is switched off on these (`RAIL_BUTTON_SCALE`), because the icon
	is what reacts now. That reaction, and the tooltip's entrance, are `Components/RailHover`.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)
local KitGrowth = require(ReplicatedStorage.shared.Modules.KitGrowth)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local LEGACY_NAME = "MainUI" -- NewUIConfig.LegacyScreenGuiName
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage
local BUTTON_TAG = "UIButton" -- Components/Button

--- The blocks this command owns. Rebuilt every run; see the header.
local OWNED = { "Rail", "Cash", "Play", "Boosts" }

--[[ The grid, in the order the kit's `UIGridLayout` draws it: two columns, left to right, top to
	bottom. `Page` goes on the tagged button inside the cell, never on the cell, because
	`Components/Button` reads its attributes off the instance carrying the tag.

	`Caption` is what the player reads in the tooltip when they point at the icon. These are today's
	page names, which is what open question 8 is asking about, so they are one string each and easy
	to change.

	A cell opens a `Page`, or carries an `Action` for a door onto something that is not a page (the
	radio). `ButtonPress` acts on either and `HudRules` hides either. ]]
local GRID = {
	{ Name = "Index", Page = "Index", Caption = "Index", Icon = "rbxassetid://113465671824094" }, -- kit: 115378387527730
	--[[ SHOP TOP RIGHT, QUEST UNDER IT (Dylan, 2026-09-16): the two swapped places. `HudRules` hides
		this cell while nothing is on sale, and then the grid closes up behind it: Cars moves up
		beside Index and Quest comes back to the left column. ]]
	--- The kit's basket, PixFixed (kit: 87319256046859). The gift it replaced was 119201464349285 (kit: 132451149105500).
	{ Name = "Shop", Page = "Shop", Caption = "Shop", Icon = "rbxassetid://72297492337053" },
	--[[ NO MARKET CELL, on Dylan's call (2026-09-15). The market has never sold anything: there is
		no `MarketService`, no remote, and `Pages/Market._requestPurchase` is a stub that logs the
		purchase it would have made. A cell that opens a shop and refuses every price is worse than
		no cell. `PagesV2/Market` is built and stays in git, so the day a service lands this is one
		line back. ]]
	{
		Name = "Dealership",
		Page = "Dealership",
		--[[ The one cell that earned a picture of its own, which is what open question 7 said it
			would be: the car the shipping rail's `SpawnCar` button is built on
			(`assets/ui/gvesster/car-icon-transparent.png`), cropped to its art and uploaded BARE
			(2026-09-16). The first version used `UIAssets.HudButtons.SpawnCar.Idle`, which is the
			whole old rail button, so the cell drew a navy tile inside the kit's tile. The kit's
			icons are cropped flush to their art too, so this one sits in the same `Icon` box at the
			same weight. Stored 1024x741. ]]
		Caption = "Cars",
		Icon = "rbxassetid://91216847938226", -- before PixFix: 98894394847947
	},
	--[[ NO TELEPORT CELL, on Dylan's call in the human pass (2026-09-16): Play already opens the worlds
		screen, so the cell was a second door onto the same page. The kit icon it wore was
		`rbxassetid://76758407055161`. ]]
	--- The v3.1 paper scroll, PixFixed; see the header. Decal 91821193373062. Was the basket, which is Shop's now.
	{ Name = "Quest", Page = "Quest", Caption = "Quest", Icon = "rbxassetid://107432045351685" },
	--[[ RADIO AND SETTINGS came down from the topbar in the same pass, which fills the kit's six cells
		(three rows of two). The topbar chips stay, but on the new UI only for a race, when this grid is
		hidden (`TopbarController._setRacing`).

		The radio panel is not a page, so its cell carries an `Action` (`RadioConfig.PanelAction`) that
		`RadioPanelController` answers; Settings is a page (`SettingsConfig.PageName`). Both icons are the
		bare Gvesster glyphs the topbar chips already wear (`UIAssets.Topbar.Radio` and `.Settings`,
		256x256, cropped near flush), which is where open question 7 said a specific picture comes
		from: the kit draws no speaker and no gear. ]]
	{ Name = "Radio", Action = "OpenRadio", Caption = "Radio", Icon = "rbxassetid://118683803226370" },
	{ Name = "Settings", Page = "Settings", Caption = "Settings", Icon = "rbxassetid://120096252161503" },
}

--[[ Two full-strength reactions to one hover reads as the UI flinching, and the kit's cell is a face
	inside a rim: at the default 1.05 the face all but touches the rim. 1.03 is what the old rail
	settled on for the same reason. Play is a plain slab with nothing around it, so it keeps the 1.04
	the shipping Play button uses.

	The grid buttons no longer use `GRID_HOVER_SCALE` (see `RAIL_BUTTON_SCALE`); the cash `+` still
	does, and its name stayed so the cash block builds exactly as it did. ]]
local GRID_HOVER_SCALE = 1.03
local PLAY_HOVER_SCALE = 1.04

--[[ The bare-icon grid. See "THE GRID IS BARE ICONS" in the header.

	`RAIL_BUTTON_SCALE` is `Components/Button`'s swell, off: 1 is its "no change". The icon's own
	reaction lives in `Components/RailHover`, and `Button`'s would grow the tooltip with it.

	`ICON_FILL` is the icon's box as a fraction of the button. The kit drew its icons at 0.8, inset
	so the art sat inside the tile's face; with no face the inset only made the icons look small and
	far apart. At 1 the icon is exactly the button, which is exactly the hit target.

	`TIP_TOP` is where the tooltip's top edge rests, as a fraction of the button's height from its
	top. Just under the icon at its hover size (`RailHover.ICON_SCALE` 1.1, so 1.05, and a hair more
	for the ease's overshoot). The label is 0.35 of the button tall, so it ends at 1.43, and the next
	row's button starts at 1.46: measured, the gap between two rows' buttons is 0.46 of a button at
	every resolution, because every box in the grid is sized in scale. ]]
local RAIL_BUTTON_SCALE = 1
local ICON_FILL = 1
local TIP_TOP = 1.08

--- What drew the kit's tile. On the cell by class, since the cell carries nothing else of those
--- classes; on the button by name, since the button also carries `Icon` and the caption.
local TILE_CLASSES = { "UIGradient", "UIStroke", "UICorner" }
local FACE_PARTS = { "Container", "BG", "UICorner" }

--- Fallbacks for the two attributes the V2 Play button inherits from the shipping one. Used only when
--- `MainUI.HUD.Play` is not in the place to read them off.
local PLAY_ACTION = "EnterRace" -- RaceConfig.EnterRaceAction
local PLAY_GAMEPAD_KEY = "ButtonX"

--[[ Where the four pieces of the cash block sit, as a fraction of the block itself, read off the kit
	after a real layout pass. See the header. Each rect is a centre and a size, because everything we
	author is anchored 0.5, 0.5. ]]
local CASH_PARTS = {
	TextLabel = { Centre = Vector2.new(0.1484, 0.7500), Size = Vector2.new(0.2969, 0.4375) },
	AddBtn = { Centre = Vector2.new(0.3603, 0.7500), Size = Vector2.new(0.0667, 0.5000) },
	Rate = { Centre = Vector2.new(0.2011, 0.1875), Size = Vector2.new(0.2622, 0.2500) },
}

--[[ ...and the rate's icon, which is the one piece NOT placed in the block's own space, because it
	is parented to `Rate` rather than beside it. The same rect, restated as a fraction of the label:
	hanging off its left edge (a negative centre) and half again its height.

	IT IS A CHILD SO THAT IT HIDES WHEN THE LABEL DOES. `GarageHudController` shows the rate line only
	while the garage is actually earning (`Rate.Visible = rate > 0`), and it knows about one label. A
	sibling icon stayed up on its own next to nothing whenever the rate was zero, which is what a
	brand new save looks like for its first minute. ]]
local RATE_ICON = { Centre = Vector2.new(-0.1716, 0.5000), Size = Vector2.new(0.1907, 1.5000) }

--- The kit's own placeholder strings, so a freshly built HUD reads as a HUD before anything binds to
--- it. Both are overwritten by `GarageHudController` on the first collection.
local CASH_PLACEHOLDER = "$0"
local RATE_PLACEHOLDER = "+$0/s"

local function place(gui: GuiObject, rect: { Centre: Vector2, Size: Vector2 })
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui.Position = UDim2.fromScale(rect.Centre.X, rect.Centre.Y)
	gui.Size = UDim2.fromScale(rect.Size.X, rect.Size.Y)
end

--[[ THE GLOSS KEEPS ITS SHAPE WHEN THE BUTTON DOES NOT. A kit face's `BG.Slash` is sized in fractions
	of the button, its width of the button's WIDTH, so a face given a new aspect takes the slash with
	it. `ScaleType.Fit` then draws the double stripe into whatever box is left: Play, cut from the
	10.6:1 `RebirthBtn` down to 3.4:1, drew it at a quarter of its width, a sliver nobody could see.

	So the slash is measured in button HEIGHTS on the kit's own face, before anything moves it, and
	written back once the button has its new shape. Both read `AbsoluteSize`, which Studio lays out for
	the kit in ServerStorage and for the HUD in StarterGui alike. ]]
local function slashOf(button: Instance): GuiObject?
	local bg = button:FindFirstChild("BG")
	local slash = bg and bg:FindFirstChild("Slash")
	return if slash and slash:IsA("GuiObject") then slash else nil
end

local function slashWidthInHeights(button: GuiObject): number?
	local slash = slashOf(button)
	local size = button.AbsoluteSize
	if not slash or size.Y <= 0 then
		return nil
	end
	return slash.Size.X.Scale * size.X / size.Y
end

local function fitSlash(button: GuiObject, widthInHeights: number): boolean
	local slash = slashOf(button)
	local size = button.AbsoluteSize
	if not slash or size.X <= 0 then
		return false
	end
	slash.Size = UDim2.new(widthInHeights * size.Y / size.X, 0, slash.Size.Y.Scale, 0)
	return true
end

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

return {
	Description = "Build StarterGui.MainUIV2.HUD from the Cartoony Kit HUD: the six-button grid as `Rail` (bare icons, captions as hover tooltips), the cash block as `Cash` with `TextLabel` and `Rate`, a `Play` button cut from the kit's green confirm button, and `Boosts` hidden. Rebuilds those four every run.",
	Tags = { "UI", "NewUI" },
	AutoRecordChanges = true,

	Arguments = {} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		local screen = StarterGui:FindFirstChild(SCREEN_NAME)
		local hud = screen and screen:FindFirstChild("HUD")
		if not (hud and hud:IsA("GuiObject")) then
			out:error(string.format("No StarterGui.%s.HUD. Run BuildMainUIV2 first.", SCREEN_NAME))
			return
		end

		local container, why = findTemplate()
		if not container then
			out:error(string.format("The kit is not where it should be: %s", why))
			return
		end
		local kitHud = container:FindFirstChild("HUD")
		if not kitHud then
			out:error(string.format("%s has no `HUD` frame to build from.", container:GetFullName()))
			return
		end

		for _, name in OWNED do
			local existing = hud:FindFirstChild(name)
			if existing then
				existing:Destroy()
			end
		end

		-- === The grid ===================================================================

		--[[ The kit frame whole, renamed. Its `UIGridLayout` and `UIAspectRatioConstraint` come with
			it, so the column stays two wide and keeps its shape on every screen, and its anchor stays
			the kit's `0, 0.5`: this block is pinned to the left edge of the screen, and a centre
			anchor would let it drift inward once the aspect constraint resized it. ]]
		local rail = kitHud.SideBtns:Clone()
		rail.Name = "Rail"

		local cells = {}
		for _, child in rail:GetChildren() do
			if child.Name == "BtnTemplate" then
				table.insert(cells, child)
			end
		end
		if #cells < #GRID then
			out:error(string.format("The kit HUD has %d grid cells and the grid wants %d.", #cells, #GRID))
			rail:Destroy()
			return
		end

		for index, spec in GRID do
			local cell = cells[index]
			cell.Name = spec.Name
			--- Authored as 0 on all six, which leaves the draw order to whatever the explorer happens
			--- to hold. The grid reads `LayoutOrder`, so say it.
			cell.LayoutOrder = index

			--- The tile, off the cell. See "THE GRID IS BARE ICONS" in the header.
			cell.BackgroundTransparency = 1
			for _, child in cell:GetChildren() do
				if table.find(TILE_CLASSES, child.ClassName) then
					child:Destroy()
				end
			end

			local button = cell:FindFirstChild("Main")
			if not (button and button:IsA("GuiButton")) then
				out:warn(string.format("Cell %s has no `Main` button; it will do nothing.", spec.Name))
			else
				--[[ On the BUTTON and not the cell. `Components/Button` binds whatever carries the tag
					and reads `Page` and `Scale` off that same instance. The tag itself came with the
					clone: `PrepKitTemplate` put it on every kit button, and a tag survives a copy. ]]
				--- A cell carries one or the other; writing the absent one as nil clears it.
				button:SetAttribute("Page", spec.Page)
				button:SetAttribute("Action", spec.Action)
				button:SetAttribute("Scale", RAIL_BUTTON_SCALE)
				if not CollectionService:HasTag(button, BUTTON_TAG) then
					out:warn(string.format("%s.Main is not tagged %s. Re-run PrepKitTemplate.", spec.Name, BUTTON_TAG))
				end

				--- ...and the face, off the button. Its own rect stays: it is the hit target.
				button.BackgroundTransparency = 1
				for _, name in FACE_PARTS do
					local part = button:FindFirstChild(name)
					if part then
						part:Destroy()
					end
				end

				local icon = button:FindFirstChild("Icon")
				if icon and icon:IsA("ImageLabel") then
					icon.Image = spec.Icon
					icon.Size = UDim2.fromScale(ICON_FILL, ICON_FILL)
				else
					out:warn(string.format("%s.Main has no `Icon`; the cell draws nothing.", spec.Name))
				end

				--[[ The kit's caption, kept as the tooltip. Hidden, because `Components/Button` is what
					shows it; top-aligned, so the words sit the same distance under the icon whether
					or not the label's size cap has left spare height in its box (it did at 4K before
					`RailHover` handed the grid to `KitPage.scaleTextCaps`). ]]
				local caption = button:FindFirstChild("Category")
				if caption and caption:IsA("TextLabel") then
					caption.Name = "Hint"
					caption.Text = spec.Caption
					caption.Visible = false
					caption.AnchorPoint = Vector2.new(0.5, 0)
					caption.Position = UDim2.fromScale(0.5, TIP_TOP)
					caption.TextYAlignment = Enum.TextYAlignment.Top
				else
					out:warn(string.format("%s.Main has no `Category` label; it will have no tooltip.", spec.Name))
				end
			end
		end

		--- Any cell past the sixth. The kit ships exactly six, so this is here for the day it ships
		--- seven rather than because it fires today.
		for index = #GRID + 1, #cells do
			cells[index]:Destroy()
		end

		--[[ Bigger than the kit drew it (Dylan, 2026-09-16), tooltip caps included. The grid and every
			box in it are scale, so the icons, the gaps and `TIP_TOP` all come along. See
			`Modules/KitGrowth`. ]]
		KitGrowth.apply(rail, KitGrowth.Rail)
		rail.Parent = hud

		-- === The cash block =============================================================

		--[[ `BottomInfo` renamed, with its two rows dissolved onto it. See the header for why the
			nesting cannot stay and where the positions came from. ]]
		local cash = kitHud.BottomInfo:Clone()
		cash.Name = "Cash"

		local moneyRow = cash:FindFirstChild("Cash")
		local boostRow = cash:FindFirstChild("FriendBoost")
		if not (moneyRow and boostRow) then
			out:error("The kit's BottomInfo no longer holds `Cash` and `FriendBoost`.")
			cash:Destroy()
			rail:Destroy()
			return
		end

		local amount = moneyRow:FindFirstChild("Title")
		local addBtn = moneyRow:FindFirstChild("AddBtn")
		local rate = boostRow:FindFirstChild("Title")
		local rateIcon = boostRow:FindFirstChild("Icon")

		amount.Name = "TextLabel" -- GarageHudController writes the balance here
		rate.Name = "Rate" -- ...and the garage rate here
		rateIcon.Name = "RateIcon"

		for _, part in { amount, addBtn, rate } do
			part.Parent = cash
		end
		place(amount, CASH_PARTS.TextLabel)
		place(addBtn, CASH_PARTS.AddBtn)
		place(rate, CASH_PARTS.Rate)

		--- Onto the label, not beside it, so the two go dark together. See `RATE_ICON`.
		rateIcon.Parent = rate
		place(rateIcon, RATE_ICON)
		rate.ClipsDescendants = false -- the icon hangs off the label's left edge

		--- Flush left, both of them, so a short balance and the rate line share an edge. See the header.
		amount.TextXAlignment = Enum.TextXAlignment.Left
		amount.Text = CASH_PLACEHOLDER
		rate.TextXAlignment = Enum.TextXAlignment.Left
		rate.Text = RATE_PLACEHOLDER

		--- The green `+`. A page and not an action, so it needs no controller: the tag it arrived with
		--- plus this attribute is the whole of it.
		addBtn:SetAttribute("Page", "Shop")
		addBtn:SetAttribute("Scale", GRID_HOVER_SCALE)

		moneyRow:Destroy()
		boostRow:Destroy()
		cash.Parent = hud

		-- === Play =======================================================================

		--[[ The kit has no Play button, so it is cut from the green confirm button Dylan picked as the
			reference (`TradeUI.Main.Btns.AcceptBtn`, "Accept Trade"): the kit's yellow-to-green
			gradient, its double stroke, its corner radius and the `Slash` of gloss across it. Only the
			name, the words and the attributes are ours.

			NOT `RebirthUI`'s button any more, which is what this was first cut from. It is the same
			anatomy drawn heavier (a 0.09 rim, a caption 0.64 of the face with a 0.13 outline) for a bar
			ten times as wide as it is tall, and on a HUD slab it read as a different, chunkier kit.

			The two attributes are READ OFF THE SHIPPING BUTTON where there is one, rather than typed
			here. `RaceEntryController` finds Play by its `Action` and not by its name, so the V2 button
			answering to a different string than the V1 one is a bug that would only show up in a
			playtest. Taking the value from the button that already works makes that impossible. ]]
		local source = container:FindFirstChild("TradeUI")
		source = source and source:FindFirstChild("Main")
		source = source and source:FindFirstChild("Btns")
		source = source and source:FindFirstChild("AcceptBtn")
		if not (source and source:IsA("GuiButton")) then
			out:error("The kit's TradeUI.Main.Btns.AcceptBtn is gone; Play has nothing to be cut from.")
			return
		end
		--- Before the clone, which has no parent and so no size to measure. See `fitSlash`.
		local slashWidth = slashWidthInHeights(source)

		local play = source:Clone()
		play.Name = "Play"
		play.Text = ""
		play.AnchorPoint = Vector2.new(0.5, 0.5)

		local action, gamepadKey = PLAY_ACTION, PLAY_GAMEPAD_KEY
		local legacyHud = StarterGui:FindFirstChild(LEGACY_NAME)
		legacyHud = legacyHud and legacyHud:FindFirstChild("HUD")
		local legacyPlay = legacyHud and legacyHud:FindFirstChild("Play")
		if legacyPlay then
			action = legacyPlay:GetAttribute("Action") or action
			gamepadKey = legacyPlay:GetAttribute("GamepadKey") or gamepadKey
			--- The same rect the shipping button occupies, including the aspect constraint that stops
			--- it stretching into a letterbox on a wide screen.
			play.Position = legacyPlay.Position
			play.Size = legacyPlay.Size
			local legacyRatio = legacyPlay:FindFirstChildOfClass("UIAspectRatioConstraint")
			if legacyRatio then
				local ratio = play:FindFirstChildOfClass("UIAspectRatioConstraint") or legacyRatio:Clone()
				ratio.AspectRatio = legacyRatio.AspectRatio
				ratio.AspectType = legacyRatio.AspectType
				ratio.DominantAxis = legacyRatio.DominantAxis
				ratio.Parent = play
			end
		else
			out:warn("No MainUI.HUD.Play to copy the Action, the key and the rect off; using the defaults.")
			play.Position = UDim2.fromScale(0.5, 0.91)
			play.Size = UDim2.fromScale(1, 0.075)
			local ratio = Instance.new("UIAspectRatioConstraint")
			ratio.AspectRatio = 3.391
			ratio.AspectType = Enum.AspectType.FitWithinMaxSize
			ratio.DominantAxis = Enum.DominantAxis.Height
			ratio.Parent = play
		end

		play:SetAttribute("Action", action)
		play:SetAttribute("GamepadKey", gamepadKey)
		play:SetAttribute("Scale", PLAY_HOVER_SCALE)

		local playTitle = play:FindFirstChild("Title")
		if playTitle and playTitle:IsA("TextLabel") then
			playTitle.Text = "PLAY"
		end
		if not CollectionService:HasTag(play, BUTTON_TAG) then
			CollectionService:AddTag(play, BUTTON_TAG)
		end
		play.Parent = hud
		if not (slashWidth and fitSlash(play, slashWidth)) then
			out:warn("Play's gloss could not be measured (no `BG.Slash`, or the kit is not laid out); it keeps the kit's fractions.")
		end

		-- === Boosts =====================================================================

		--[[ Kept and hidden rather than left out. It is the row the weather event and its timer want
			(the plan's replacement for the WeatherNotice banner), and a frame that is already in the
			place with its three templates intact is a cheaper start than a re-import. ]]
		local boosts = kitHud.Boosts:Clone()
		boosts.Visible = false
		boosts.Parent = hud

		out:print(
			string.format(
				"Built %s.HUD: Rail with %d bare icons and hover tooltips (%s), Cash with TextLabel and Rate, Play (Action=%s, %s), Boosts hidden.",
				SCREEN_NAME,
				#GRID,
				(function()
					local names = {}
					for _, spec in GRID do
						table.insert(names, spec.Name)
					end
					return table.concat(names, ", ")
				end)(),
				tostring(action),
				tostring(gamepadKey)
			)
		)
		out:print("Icons are the kit's own except Cars (the shipping rail's car, uploaded bare), Quest (Gvesster v3.1's paper scroll) and Radio and Settings (the topbar chips' bare Gvesster glyphs). Any other cell that earns a picture takes it from the Gvesster art in `UIAssets`.")

		pcall(function()
			props:SetSelection({ hud })
		end)
	end,
} :: Types.ScriptModule
