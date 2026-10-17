--[[
	UpgradeBoardFace  (shared — the server's billboards and the client's Upgrades page)
	-----------------------------------------------------------------------------------
	How one face of the dealership upgrade board is found and drawn. It was `UpgradeService`'s own
	`_discoverFace`/`_drawFace` until 2026-10-14, when the board's kit face was lifted into a
	ScreenGui page (`MainUIV2.Pages.Upgrades`, opened from the `Upgrades` machine on every plot).
	A page in PlayerGui is the client's and the server cannot write it, so the drawing had to run on
	both sides. MOVED HERE RATHER THAN COPIED: the rules inside (a one-level upgrade says OWNED not
	LEVEL 1/1, a world-locked rung says WORLD N, three button states and none of them the balance)
	are exactly the kind that drift when written twice. Moved verbatim, comments and all.

	Pure writes into instances that already exist; nothing is created. The failure mode of a face
	missing a label is that label not drawn.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local UpgradeConfig = require(ReplicatedStorage.shared.Configs.UpgradeConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local UpgradeBoardFace = {}

-- One authored billboard, resolved once at discovery so writing a label is a straight-line property
-- write and a malformed board is one startup warning rather than a silent no-op per purchase.
--[[ WIDENED FROM THE CONCRETE CLASSES ON 2026-08-23, when the board stopped being flat fills and
	became the kit's textures: a tile, its bar fill and its button are an `ImageLabel`, `ImageLabel`
	and `ImageButton` now rather than a `Frame`, `Frame` and `TextButton`. Everything this file does
	to them — `Size`, `Text`, and the button's three image slots — is on the base classes, so these
	are deliberately the widest type that still says what the field is FOR. It also means a board
	authored before the rebuild still binds and still draws. ]]
export type Pip = {
	index: number,
	gradient: UIGradient?,
}

export type Tile = {
	key: string,
	frame: GuiObject,
	headline: TextLabel?,
	detail: TextLabel?,
	level: TextLabel?,
	fill: GuiObject?,
	pips: { Pip },
	button: GuiButton?,
	action: TextLabel?,
	cashIcon: GuiObject?,
	cost: TextLabel?,
	status: TextLabel?,
}

--[[ One of the two faces on a billboard's plate: the classic `UpgradeGui` or the kit's
	`UpgradeGuiKit`. Both are drawn on every write, because which one a player sees is decided on
	their own client (`NewUIConfig.KitUpgradeBoards`) and the server has no business knowing. ]]
export type Face = {
	gui: GuiObject | SurfaceGui,
	kit: boolean,
	owner: TextLabel?,
	tiles: { [string]: Tile },
}

-- === Look ===================================================================

--[[ THE BILLBOARD'S BUTTON IS A PILL, NOT A FILL, since 2026-08-23.

	It used to be a `TextButton` whose `BackgroundColor3` this file wrote per state. It is an
	`ImageButton` wearing one of the kit's seven pills, so the state is a change of TEXTURE, and each
	state brings its own idle, hover and pressed art rather than relying on Roblox's automatic tint.
	`UpgradeConfig.ButtonPills` is the map, and it sits beside the kiosk's own palette so the two
	boards cannot drift on what a pressable button looks like.

	THERE ARE THREE OF THEM AND NONE IS ABOUT THE BALANCE. Orange means there is something to press
	here, green means this ladder is finished, silver means nobody owns this lot. `ButtonPills` in
	`UpgradeConfig` carries the long argument for why affordability came off the button on
	2026-08-26; the one-liner is that a press you cannot afford opens a cash pack now, so a face
	saying "pressing me does nothing" was telling the player the opposite of what happens.

	RESOLVED ONCE, HERE, rather than per draw: `_draw` runs on every purchase and every cash tick for
	every board on the island, and building three `rbxassetid://` strings per tile per draw would be
	twelve throwaway strings a frame for nothing. ]]
local function pillFor(state: string)
	local set = UIAssets.Pill[UpgradeConfig.ButtonPills[state]]
	return {
		Image = UIAssets.url(set.Idle),
		HoverImage = UIAssets.url(set.Hover),
		PressedImage = UIAssets.url(set.Pressed),
		-- The caption colour rides WITH the pill and never separately. See `ButtonTextColors`: two of
		-- the three faces are light enough that white on them cannot be read across a forecourt.
		TextColor = UpgradeConfig.ButtonTextColors[state],
	}
end

local PILL_BUY = pillFor("Buy")
local PILL_DONE = pillFor("Done")
local PILL_VACANT = pillFor("Vacant")

-- The kit face's caption colour, on every state: white under the kit's own dark outline.
local KIT_CAPTION = Color3.new(1, 1, 1)

-- === Discovery ==============================================================

--[[ Resolve one of a plate's two SurfaceGuis — or the Upgrades page, which is the kit face lifted
	into a ScreenGui — into a face the write path can use without searching. `kit` forces the kit
	face's drawing for a root that carries no `StyleAttribute` (the page); `warn` is the caller's,
	so the server names the plot and the page names itself.

	Everything is optional below the gui itself. A board half-authored by an older run of the command
	should light up whatever it does have rather than erroring on the first missing label — the
	failure mode of a sign is a blank sign, not a broken service. ]]
function UpgradeBoardFace.discover(gui: GuiObject | SurfaceGui, kit: boolean?, warn: (string) -> ()): Face?
	local names = UpgradeConfig.Board

	local panel = gui:FindFirstChild(names.PanelName)
	local grid = panel and panel:FindFirstChild(names.GridName)
	if not grid then
		warn(string.format("%s has no %s.%s, re-run BuildPlotUpgradeSigns.", gui.Name, names.PanelName, names.GridName))
		return nil
	end

	local tiles: { [string]: Tile } = {}
	for _, frame in grid:GetChildren() do
		local key = frame:GetAttribute(names.KeyAttribute)
		--[[ `isOnBoard`, not `isKey`: `UpgradeConfig.Upgrades` still holds the three ladders that came
			off this board, and a plot carrying a sign built before the swap has tiles for them. Those
			tiles are stale art and binding them would draw a live price onto an upgrade nothing sells
			— re-run `BuildPlotUpgradeSigns` and they go away. ]]
		-- `GuiObject` rather than `Frame`: a tile is an `ImageLabel` on a board built after the
		-- 2026-08-23 rebuild and a `Frame` on one built before it, and both are drawable.
		if not (frame:IsA("GuiObject") and UpgradeConfig.isOnBoard(key)) then
			continue
		end
		local bar = frame:FindFirstChild(names.TileBarName)
		local button = frame:FindFirstChild(names.ButtonName)

		-- A lit-pip ladder (the kit face) instead of, or as well as, a fill. Each pip says which rung
		-- it is, so nothing here depends on the order they were parented in.
		local pips: { Pip } = {}
		if bar then
			for _, child in bar:GetChildren() do
				local index = child:GetAttribute(names.PipAttribute)
				if type(index) == "number" then
					table.insert(pips, { index = index, gradient = child:FindFirstChildWhichIsA("UIGradient") })
				end
			end
		end

		tiles[key] = {
			key = key,
			frame = frame,
			headline = frame:FindFirstChild(names.TileHeadlineName) :: TextLabel?,
			detail = frame:FindFirstChild(names.TileDetailName) :: TextLabel?,
			level = frame:FindFirstChild(names.TileLevelName) :: TextLabel?,
			fill = bar and bar:FindFirstChild(names.TileFillName) :: GuiObject?,
			pips = pips,
			button = button :: GuiButton?,
			action = button and button:FindFirstChild(names.ButtonActionName) :: TextLabel?,
			cashIcon = button and button:FindFirstChild(names.ButtonCashIconName) :: GuiObject?,
			cost = button and button:FindFirstChild(names.ButtonCostName) :: TextLabel?,
			status = button and button:FindFirstChild(names.ButtonStatusName) :: TextLabel?,
		}
	end

	local owner = panel and panel:FindFirstChild(names.OwnerName)
	return {
		gui = gui,
		kit = kit == true or gui:GetAttribute(names.StyleAttribute) == names.KitStyle,
		owner = if owner and owner:IsA("TextLabel") then owner else nil,
		tiles = tiles,
	}
end

-- === Drawing ================================================================

-- Draw one face for `player`'s levels (nil: a vacant lot). The server calls it for both faces
-- of every board on every draw; the Upgrades page for its one face, for the local player.
function UpgradeBoardFace.draw(face: Face, player: Player?, upgrades: any)
	local names = UpgradeConfig.Board

	if face.owner then
		face.owner.Text = if player
			then string.format(names.OwnerFormat, player.DisplayName)
			else names.VacantText
	end

	for key, tile in face.tiles do
		local spec = UpgradeConfig.Upgrades[key]
		local level = UpgradeConfig.levelOf(upgrades, key)
		local cost = UpgradeConfig.costOf(key, level)
		local requiredWorld = UpgradeConfig.requiredWorldOf(key, level)
		local locked = cost ~= nil and player ~= nil and WorldConfig.highestUnlocked(player) < requiredWorld

		if tile.headline then
			tile.headline.Text = spec.Headline(level)
		end
		if tile.level then
			--[[ A one-level upgrade has no ladder to show, so it says what it IS rather than where on
				a ladder it sits: "LOCKED" / "OWNED" reads as a purchase, "LEVEL 0/1" reads as a bug.
				The builder authors no `Level` on such a tile since 2026-09-17; this is for a board built
				before that. ]]
			tile.level.Text = if spec.MaxLevel <= 1
				then (if level >= 1 then "OWNED" else "LOCKED")
				else string.format(names.LevelFormat, level, spec.MaxLevel)
		end
		if tile.detail then
			-- The static line of copy: what the tile DOES does not change with its level, and a player
			-- deciding whether to buy is reading that rather than the ladder. Its colour is the face's.
			tile.detail.Text = spec.Detail
		end
		if tile.fill then
			tile.fill.Size = UDim2.new(math.clamp(level / spec.MaxLevel, 0, 1), 0, 1, 0)
		end
		for _, pip in tile.pips do
			if pip.gradient then
				pip.gradient.Color = if pip.index <= level
					then UpgradeConfig.KitPipGradients.Lit
					else UpgradeConfig.KitPipGradients.Unlit
			end
		end

		if tile.button then
			--[[ THREE STATES, AND NOT ONE OF THEM IS THE BALANCE. Orange whenever there is a level to
				buy, green when the ladder is finished, silver when the lot has no owner and the
				prices below belong to nobody. `UpgradeConfig.ButtonPills` argues all three.

				THE PRESS IS NEVER STOPPED, in any state. The press reads, the remote fires, and the
				server decides: too poor is answered with a cash pack, not your lot and already maxed
				are answered with nothing. A button that refuses locally is a button that has to be
				right about the same rules twice.

				All three slots are written every time. Setting only `Image` would leave the previous
				state's hover and pressed art behind, so a maxed tile would flash orange under the
				cursor. The state has to move as a set. ]]
			local state = if player == nil then "Vacant" elseif cost == nil then "Done" else "Buy"
			local pill = if state == "Vacant" then PILL_VACANT elseif state == "Done" then PILL_DONE else PILL_BUY
			local caption = if face.kit then KIT_CAPTION else pill.TextColor

			--[[ GUARDED, because `.Image` does not exist on a `TextButton` and writing it throws. A
				plot carrying a board built before the 2026-08-23 rebuild still has the flat button,
				and this runs on every cash tick — an unguarded write would be a stack trace a second
				per stale board rather than one that fails once and gets noticed. Such a board draws
				its text and its bar correctly and simply does not change colour; re-run
				`BuildPlotUpgradeSigns` and it does.

				The kit face's button is a white face under a `UIGradient`, the way the Cartoony Kit
				draws every button, so its state is that gradient's colour. ]]
			local button = tile.button
			if face.kit then
				local gradient = button:FindFirstChildWhichIsA("UIGradient")
				if gradient then
					gradient.Color = UpgradeConfig.KitButtonGradients[state]
				end
			elseif button:IsA("ImageButton") then
				button.Image = pill.Image
				button.HoverImage = pill.HoverImage
				button.PressedImage = pill.PressedImage
			end

			--[[ Two layouts on one button. With a price: UPGRADE on the left, the cash note and the
				price on the right. Without one: a single centred MAXED or UNLOCKED in `Status`, so a
				finished ladder does not read as half a button. A board built before `Status` existed
				puts that word in `Action` instead, which is what it always did. ]]
			local finished = if spec.MaxLevel <= 1 then names.OwnedText else names.MaxText
			local status = tile.status
			if status then
				status.Text = if cost == nil then finished else ""
				status.TextColor3 = caption
			end
			if tile.action then
				tile.action.Text = if locked then string.format("WORLD %d", requiredWorld) elseif cost ~= nil then names.BuyText elseif status then "" else finished
				tile.action.TextColor3 = caption
			end
			if tile.cashIcon then
				tile.cashIcon.Visible = cost ~= nil and not locked
			end
			if tile.cost then
				tile.cost.Text = if locked or cost == nil then "" else GarageConfig.formatCash(cost)
				tile.cost.TextColor3 = caption
			end
		end
	end
end

return UpgradeBoardFace
