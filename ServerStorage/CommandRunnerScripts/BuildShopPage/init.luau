--[[
	BuildShopPage — Command Runner command

	Turns the IMPORTED shop art into a page `Pages/Shop` can bind to, and puts the category tabs
	back on top of it. Idempotent: it rebuilds from a pristine stash of the import every run.

	=== THIS SCRIPT NO LONGER DRAWS A PAGE, IT ADAPTS ONE ======================================

	The previous version of this file measured `car ui (3).psd` -> `Old/Shop` and built every frame
	in code. That page is gone. The owner imported a finished shop screen as
	`StarterGui.MainUI.Pages.Shop1` on 2026-09-02 and the art in it is better than what the old
	script assembled out of kit parts: real card bodies instead of a Frame with a UIStroke standing
	in for `Group 2`, and a currency MOSAIC (three small tiles then two wide ones) instead of a
	uniform grid.

	So the numbers this file used to carry are gone with it, and there is nothing here to check
	against the PSD any more. WHAT REPLACES THEM IS THE IMPORT ITSELF: every rect below is read off
	the imported children rather than written down, which is why the script is short and why moving
	a card in the Explorer moves it on screen without a source edit. The old page is kept as
	`Pages.ShopOld` for comparison, the same way `DealershipOld` and `SpawnCarOld` are.

	=== THE STASH IS WHAT MAKES IT IDEMPOTENT ==================================================

	A script that renames and reparents its own input cannot be run twice. So the FIRST run clones
	the import to `ServerStorage.UIImports.Shop1` and every run after that rebuilds from the clone.
	That stash is the master copy of the artist's art: re-import over it, or edit it directly, and
	re-run this. Editing `Pages.Shop` instead is fine for a look but the next run overwrites it.

	=== WHAT THE IMPORT IS, AND THE FOUR THINGS THAT HAD TO CHANGE ==============================

	The import is `BG` + `XButton` + `Title` + a `Slots` ScrollingFrame holding four section frames
	(`Bundle`, `Bundles#2`, `Currency`, `Gamepasses`), each a fixed-aspect block of cards.

	1. `Bundles#2` IS A DUPLICATE and it goes. It is `Bundle` without its heading — two bundle
	   sections in the same scroll, which is what you get when a group is copied to try a variant.
	   `Bundle` is the one that was finished, so it survives and takes the plural name.

	2. THE SECTIONS BECOME TABS, which is what the owner asked for and is also what the original
	   mockup wanted: `shop-page-and-passes` records that the artist drew all three sections at the
	   same y, so they were always alternatives rather than a stack. The import stacked them because
	   an importer cannot know that. Three pills go in a band under the title bar and the shelf
	   gives up the height to make room.

	3. EVERY CARD BECOMES A HIDDEN TEMPLATE, NOT A DRAWN CARD. There are 5 currency tiles for 6 cash
	   rungs and 4 gamepass slots for 5 passes, so the drawn cards were never a capacity — they are
	   a PITCH. Renaming them `Slot1..SlotN` in reading order and hiding them leaves the artist's
	   rects in the Explorer as the layout pattern, and `Pages/Shop` clones the right one per entry.
	   Nothing about the pattern is written down here: it is read back off these rects.

	4. THE ART HAS NO ICONS. The card bodies are plain navy panels — no circle, no cash chip — and
	   the gamepass slot leaves its whole left half empty for one. So `Icon` is added here, along
	   with the labels the art has no room to have drawn (`Amount`, `Saving`, `Owned`).

	=== THE ASPECT CONSTRAINTS COME OFF, AND ARE KEPT AS A NUMBER ==============================

	Each section carries a `UIAspectRatioConstraint`, which is right for a fixed block and wrong for
	a section that grows a row when a sixth cash pack exists. The ratio is saved to a `BlockAspect`
	attribute and the constraint deleted; `Pages/Shop` sizes the section in OFFSET as
	`width / BlockAspect * (rows used)`, which keeps every card at the artist's proportions at any
	screen size and lets the section outgrow its drawing. Offset and not scale for the usual reason:
	a scale-sized child of a ScrollingFrame measures against the canvas and the canvas is computed
	from the children. See the header of `Pages/Market.luau`.
]]

local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)

-- === The kit ================================================================

local PILL = {
	Blue = { Idle = 105422062127555, Hover = 113077658651318, Pressed = 106495930646044 },
	Silver = { Idle = 90929760244764, Hover = 71981963827079, Pressed = 100917385797993 },
	Orange = { Idle = 128562412847803, Hover = 77968783436056, Pressed = 108954042785479 },
	Green = { Idle = 137803438531465, Hover = 106178988911760, Pressed = 106810705668357 },
	Sky = { Idle = 88779436181116, Hover = 101537520743378, Pressed = 100925546412142 },
	Purple = { Idle = 136106448710116, Hover = 77887045034856, Pressed = 94228386766275 },
}

--- `UIAssets.Size.Pill`, 463x119. A pill is Stretch plus an aspect constraint, never 9-slice —
--- the note in `UIAssets` explains why at length. Repeated rather than required: a Command Runner
--- module runs in the plugin VM and `UIAssets` is a game module.
local PILL_ASPECT = 463 / 119

--[[ The kit's woven `#0066FF` cap — `UIAssets.SpawnCar.TitleBar`, which `UIAssets.Page.TitleBar`'s
	Orange/Red/Green are the accent versions of. Every other page in this kit wears one of the four
	as its own ImageLabel over the panel; INDEX is orange, QUESTS red, MARKET green, and the rest of
	the kit blue.

	BLUE FOR THE SHOP, for two reasons. It is the colour the import already paints there, so nothing
	on screen changes hue; and the tabs under it are ORANGE, which would fight an orange cap for the
	one thing on this page that has to read as selected.

	Stretch, never 9-slice: measured 2026-08-16, these caps have a corner radius of ZERO and their
	alpha is a plain rectangle, so slicing them only pins the artist's hairline rim at texture
	pixels. The rounding at the top of a page belongs to the PANEL. See the note in `UIAssets`. ]]
local TITLE_BAR = 137047383295367

--[[ How far down the page the header band reaches, in the page's own scale.

	MEASURED OFF THE IMPORT'S OWN PAINTED BAR rather than taken from another page, because the
	import is not on the PSD chassis: `BG` is one image with its header baked in, so the cap has to
	land exactly on the band already drawn there. Read at 4x off a render — the import's pixels
	cannot be read back with `CreateEditableImageAsync` (it is the owner's upload, and Roblox
	refuses it), so a ruled screenshot was the only way to the number.

	FULL WIDTH, and that is the part worth not re-litigating. The kit's cap carries its own light
	rim, and so does the band painted into `BG`; inset the cap even 0.4% and BOTH rims draw, which
	reads as a box inside a box. At 1.0 the cap's rim lands exactly on the painted one and replaces
	it. Slightly TALL is the safe way to be wrong — the cap's bottom rim just lands a pixel into the
	navy, where a cap that is short leaves a strip of the import's flat blue showing under it.

	THE SETTINGS IMPORT USES THIS SAME NUMBER, because it is literally the same texture: both pages
	point `BG` at `86485756805541`, and their `XButton` rects are identical to the last decimal. So
	the two aspects differing in the fourth place (1.72637 against 1.72557) is under a tenth of a
	pixel of band. `Pages/Settings` builds its cap at 0.104 for that reason and not by luck. ]]
local CAP_HEIGHT = 0.104

--- `UIAssets.Page.Close`, the kit's crimson X in its three states. Gvesster `UI/Close Button`, 256
--- square, with the hover and pressed faces this project derived from the artist's own. Every page
--- that is not an import already wears it; see the swap in the transform below.
local CLOSE = { Idle = 86144554047441, Hover = 127351455924011, Pressed = 133046877609540 }

--[[ `UIAssets.CashTiers[1]`, the first rung of the cash pack ladder, at its stored 256x256.

	ONLY THE TEMPLATE'S DEFAULT. `Pages/Shop` paints the real glyph per rung out of
	`UIAssets.CashTiers`, because a currency tile's picture has to say WHICH rung it is: all six cash
	products share one icon on Roblox (`rbxsync.lock.toml`: `88963008124478` six times), so the
	product art cannot tell them apart at all. Rung 1 rather than an empty string so the template
	reads as a finished tile in the Explorer, which is where the layout is authored. ]]
local CASH_ICON, CASH_ICON_ASPECT = 76693993929101, 1

local GOLD = Color3.fromRGB(255, 198, 0) -- the PLAY gold, this kit's "look here"
local STROKE = Color3.fromRGB(26, 26, 26) -- what the import's own labels carry

local UBUNTU = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

-- === The tab band ===========================================================
--
-- All in the page's own scale. The shelf gives up its top to the band: it was 0.8653 tall centred
-- at 0.5574 (so 0.1247..0.9901), and the band takes the first 0.088 of that plus a gap.

local BAND_TOP = 0.1247
local BAND_HEIGHT = 0.088
local BAND_GAP = 0.014
local SHELF_BOTTOM = 0.9901
local TAB_GAP = 0.022 -- between pills, in page scale
local PAGE_ASPECT = 1.7263682 -- the import's own UIAspectRatioConstraint

-- === Helpers ================================================================

local function make(className: string, name: string, parent: Instance?, props: { [string]: any }?): any
	local inst = Instance.new(className)
	inst.Name = name
	for key, value in props or {} do
		(inst :: any)[key] = value
	end
	inst.Parent = parent
	return inst
end

--- Drop a child by name if it is there. Used so a re-run does not stack a second copy.
local function clear(parent: Instance, name: string)
	local existing = parent:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
end

--- Left edge / top edge of a child, in its parent's scale. Anchor-aware, because the import
--- anchors its cards at the top left and everything else at the centre.
local function left(gui: GuiObject): number
	return gui.Position.X.Scale - gui.AnchorPoint.X * gui.Size.X.Scale
end
local function top(gui: GuiObject): number
	return gui.Position.Y.Scale - gui.AnchorPoint.Y * gui.Size.Y.Scale
end

--- An `ImageButton` wearing one of the kit's pills, with a centred label.
local function pill(name: string, parent: Instance, pos: UDim2, size: UDim2, text: string, colour: string)
	local set = PILL[colour]
	local button = make("ImageButton", name, parent, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Position = pos,
		Size = size,
		Image = "rbxassetid://" .. set.Idle,
		HoverImage = "rbxassetid://" .. set.Hover,
		PressedImage = "rbxassetid://" .. set.Pressed,
		ScaleType = Enum.ScaleType.Stretch,
		ZIndex = 6,
	})
	make("UIAspectRatioConstraint", "UIAspectRatioConstraint", button, { AspectRatio = PILL_ASPECT })

	local text_ = make("TextLabel", "Label", button, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.82, 0.5),
		FontFace = UBUNTU,
		Text = text,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		ZIndex = 7,
	})
	make("UIStroke", "UIStroke", text_, { Color = STROKE, Thickness = 2 })
	return button
end

--- A label in the import's own idiom: Ubuntu Bold, white, scaled, with the dark hairline every
--- text in the imported art carries.
local function label(name: string, parent: Instance, pos: UDim2, size: UDim2, text: string, props: { [string]: any }?)
	local text_ = make("TextLabel", name, parent, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = pos,
		Size = size,
		FontFace = UBUNTU,
		Text = text,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		ZIndex = 4,
	})
	for key, value in props or {} do
		(text_ :: any)[key] = value
	end
	make("UIStroke", "UIStroke", text_, { Color = STROKE, Thickness = 2 })
	return text_
end

--[[ An icon box that keeps its own aspect whatever tile it lands on.

	`FitWithinMaxSize` and NOT a hand-computed scale size, because the same template is cloned onto
	tiles of three different widths (the currency mosaic's 0.29, 0.40 and 0.53) and a scale size
	that is square on one is an oval on the other two. The Size below is the BOX it must fit inside;
	the height is always the binding edge at these proportions, so the width falls out of it. ]]
local function icon(parent: Instance, pos: UDim2, box: UDim2, aspect: number)
	local image = make("ImageLabel", "Icon", parent, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = pos,
		Size = box,
		Image = "",
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 4,
	})
	make("UIAspectRatioConstraint", "UIAspectRatioConstraint", image, {
		AspectRatio = aspect,
		AspectType = Enum.AspectType.FitWithinMaxSize,
	})
	return image
end

-- === The transform ==========================================================

--[[ Name the card's own children, so `Pages/Shop` can address them.

	THE IMPORT NAMES SIBLINGS THE SAME THING. A gamepass slot holds two labels both called `Texts`
	and a bundle row holds three called `NameTags`, which is what a design tool exports when the
	artist did not rename a duplicated layer. `FindFirstChild` on either picks one at random, so the
	first job is to tell them apart, and the only thing that distinguishes them is WHERE THEY ARE:
	the title is above the blurb in every card in the file. Sorting on y is therefore the whole
	identification, and it is why this runs before anything is moved. ]]
local function nameByHeight(card: Instance, fromName: string, toNames: { string })
	local found = {}
	for _, child in card:GetChildren() do
		if child.Name == fromName and child:IsA("GuiObject") then
			table.insert(found, child)
		end
	end
	table.sort(found, function(a, b)
		return top(a) < top(b)
	end)
	for index, child in found do
		child.Name = toNames[index] or (fromName .. index)
	end
	return found
end

--[[ The price pill inside a card. The import draws it as art plus a `TextLabel`; the page wants a
	known name for it, and the player wants it to react.

	THE TAG GOES ON THE TEMPLATE, NOT ON THE CLONES, which is the only reason this is one line
	rather than a loop in `Pages/Shop`: a tag survives `Clone()`, so every card the page ever builds
	arrives already carrying it and `Components/Button` picks it up as it is parented. Nothing in
	the page module knows this happened.

	No `Page` or `Action` attribute, deliberately. Those are what a press MEANS (see `ButtonPress`),
	and what this press means is a Roblox purchase prompt, which the page wires by hand because it
	needs the entry the card was built from. The tag here buys the hover swell, the click sound and
	`Selectable` for a controller — the three things every other button in the kit has and these did
	not.

	THE ART IS LEFT ALONE HERE AND REPLACED AT RUNTIME. The import's own flat green button ships one
	image, no hover and no pressed; `Pages/Shop._paintBuy` puts the kit's GOLD pill on every card it
	builds, which is where the checker weave and the three-face ladder come from. It stays the
	artist's green on these hidden templates so the Explorer still shows what was imported. ]]
local function nameBuyButton(card: Instance)
	local buy = card:FindFirstChild("BuyButton")
	if not buy then
		return nil
	end
	local text = buy:FindFirstChildWhichIsA("TextLabel")
	if text then
		text.Name = "Label"
	end
	buy:AddTag("UIButton")
	return buy
end

--[[ One section: hide its heading, turn its cards into named templates, and record its aspect.

	THE HEADING GOES BECAUSE THE TAB SAYS IT. With a tab strip above the shelf, a section that also
	prints "Currency" over its cards is saying the same word twice a centimetre apart. It is hidden
	rather than deleted so the owner can put it back by ticking Visible, and `Pages/Shop` reclaims
	the band it was drawn in rather than leaving a hole where it was. ]]
local function prepareSection(section: Frame, kind: string)
	local aspectConstraint = section:FindFirstChildWhichIsA("UIAspectRatioConstraint")
	if aspectConstraint then
		section:SetAttribute("BlockAspect", aspectConstraint.AspectRatio)
		aspectConstraint:Destroy()
	end

	local title = section:FindFirstChild("Title")
	if title and title:IsA("GuiObject") then
		title.Visible = false
	end

	-- Reading order: down the page, then across. This is the order the page fills entries in, so it
	-- is the order the artist's escalation is read in (three small tiles, then the two wide ones).
	local cards = {}
	for _, child in section:GetChildren() do
		if child:IsA("GuiButton") then
			table.insert(cards, child)
		end
	end
	table.sort(cards, function(a, b)
		local ay, by = top(a), top(b)
		if math.abs(ay - by) > 0.01 then
			return ay < by
		end
		return left(a) < left(b)
	end)

	for index, card in cards do
		card.Name = "Slot" .. index
		card.Visible = false
		card.ZIndex = 2

		nameBuyButton(card)

		if kind == "Bundles" then
			local named = nameByHeight(card, "NameTags", { "BundleName", "Subtitle", "Blurb" })

			--[[ THE ARTIST'S TWO LOWER BOXES WERE DRAWN AROUND PLACEHOLDER WORDS, and the real copy
				does not fit in them. "Second title bundle" and "Description of bundle" are three
				words each; what actually goes there is `$150,000 + a random car + one 2x offline
				boost` and a full sentence. `TextScaled` in a box that narrow answers by wrapping and
				then shrinking to fit the wrap (see `textscaled-wraps-instead-of-shrinking`), which
				came out at about a third the size of the title above it and unreadable in a
				playtest.

				So both boxes are widened into the empty run between the text column and the icon,
				which the artist left clear anyway: the icon starts at x 0.59 and the price pill at
				0.85, so 0.08..0.52 is free. Their CENTRES do not move, so the row still reads as the
				centred column the artist composed. The title is untouched — it always fit. ]]
			if named[2] then
				named[2].Size = UDim2.fromScale(0.44, 0.17)
				named[2].Position = UDim2.fromScale(0.3, named[2].Position.Y.Scale)
				named[2].TextWrapped = true
			end
			if named[3] then
				named[3].Size = UDim2.fromScale(0.44, 0.15)
				named[3].Position = UDim2.fromScale(0.3, named[3].Position.Y.Scale)
				named[3].TextWrapped = true
			end
			clear(card, "Icon")
			clear(card, "Saving")
			--[[ The icon sits in the dead middle of the row: the artist's three lines end around
				x 0.50 and the price pill starts at 0.85, so this is the one gap in the row that was
				drawn empty on purpose. ]]
			icon(card, UDim2.fromScale(0.66, 0.48), UDim2.fromScale(0.28, 0.72), 1)
			-- Over the pill's shoulder rather than beside it: the row has no width left at 0.916,
			-- and a saving that overlapped the price would be read as part of it.
			label("Saving", card, UDim2.fromScale(0.916, 0.68), UDim2.fromScale(0.14, 0.13), "SAVE 24%", {
				TextColor3 = GOLD,
				ZIndex = 5,
			})
		elseif kind == "Gamepasses" then
			local named = nameByHeight(card, "Texts", { "PassName", "Blurb" })
			if named[2] then
				named[2].TextWrapped = true -- same reason as the bundle blurb above
			end
			clear(card, "Icon")
			clear(card, "Owned")
			-- The card's whole left half. Every text the artist drew starts at x 0.499.
			icon(card, UDim2.fromScale(0.25, 0.5), UDim2.fromScale(0.44, 0.66), 1)

			--[[ OWNED replaces the price rather than sitting next to it, and it is a SILVER PILL on
				the buy pill's exact rect. Same shape in the same place means the eye reads the
				colour, which is the kit's own "off" (the Market page's sold-out pills). A tick or a
				greyed price would both need a second look to tell from a buyable card.

				The pill it replaces is GOLD, not the import's green — `Pages/Shop._paintBuy` repaints
				every one of them on build, and both pills carry the same Ubuntu label as a result. ]]
			local buy = card:FindFirstChild("BuyButton") :: ImageButton?
			if buy then
				local owned = pill("Owned", card, buy.Position, buy.Size, "OWNED", "Silver")
				owned.Active = false
				--[[ And OFF the controller's map. An ImageButton is `Selectable` by default, so
					without this the DPad walks the highlight onto a badge that is not a button at
					all, and a console player presses A on it and gets nothing. It carries no
					`UIButton` tag either, so there is no handler behind it to reach. ]]
				owned.Selectable = false
				owned.ZIndex = 3
				owned:FindFirstChild("Label").ZIndex = 4
				owned.Visible = false
			end
		elseif kind == "Currency" then
			clear(card, "Icon")
			clear(card, "Amount")
			--[[ The tile is empty above its price pill (which starts at y 0.78), so the glyph and
				the amount split that space: glyph on top, dollars under it, price at the bottom.

				0.50 TALL AND CENTRED AT 0.295, which is the whole of the gap. The amount starts at
				0.555 and the tile's own rim wants about 0.04, so 0.045 to 0.545 is everything that
				is free and the glyph takes all of it. It was 0.4 while the chip here was the
				landscape 1.673 note; these are SQUARE, so the same box would have rendered them at
				65px on the mosaic's small tile. At 0.50 they come out 81, against the old chip's
				109 by 65: taller than it was and barely narrower, which is what a tier has to be to
				be told from the tier next to it at a glance.

				HEIGHT IS THE BINDING EDGE ON EVERY TILE, from the mosaic's 0.29 square to the
				full-width one (0.8 of the narrowest is still 166px against 81), so all six glyphs
				render at exactly the same size however wide the tile under them is. ]]
			icon(card, UDim2.fromScale(0.5, 0.295), UDim2.fromScale(0.8, 0.5), CASH_ICON_ASPECT).Image = "rbxassetid://"
				.. CASH_ICON
			label("Amount", card, UDim2.fromScale(0.5, 0.64), UDim2.fromScale(0.88, 0.17), "$15,000")
		end
	end

	--[[ The two bundle-row skins, recorded as attributes so the page does not have to know which
		slot the artist happened to draw which one on.

		THE GRADIENT IS A STATE, NOT A SECOND DESIGN. The artist drew the blue-to-cyan on the FIRST
		row and left the second navy, which is a FEATURED treatment of one row rather than two kinds
		of row — the two are otherwise identical down to the text positions. `ShopConfig.Bundle
		.Featured` says which bundle gets it, and the page swaps the image. Note this is real
		painted art here and NOT the `UIGradient` the old code-built page used, so none of the
		multiply trap in `uigradient-multiplies-the-tint` applies any more. ]]
	if kind == "Bundles" and cards[1] then
		section:SetAttribute("ArtFeatured", (cards[1] :: ImageButton).Image)
		section:SetAttribute("ArtPlain", (cards[2] or cards[1] :: any).Image)
	end

	section:SetAttribute("SlotCount", #cards)
	return #cards
end

return {
	Description = "Rebuild StarterGui.MainUI.Pages.Shop from the imported shop art (stashed at ServerStorage.UIImports.Shop1): three category tabs, hidden card templates and the icons the art has no room for. Idempotent — rebuilds from the stash every run.",
	Arguments = {} :: Types.ArgumentType,

	Run = function(props: Types.RunProps, _arguments)
		local out = props:Output()

		local mainUI = StarterGui:FindFirstChild("MainUI")
		local pages = mainUI and mainUI:FindFirstChild("Pages")
		if not pages then
			out:error("StarterGui.MainUI.Pages is missing. Nothing to build against.")
			return
		end

		-- === The stash ==================================================

		local imports = ServerStorage:FindFirstChild("UIImports")
		if not imports then
			imports = make("Folder", "UIImports", ServerStorage)
		end

		local stash = imports:FindFirstChild("Shop1")
		if not stash then
			local imported = pages:FindFirstChild("Shop1")
			if not imported then
				out:error(
					"No import to build from: neither ServerStorage.UIImports.Shop1 nor StarterGui.MainUI.Pages.Shop1 exists. Re-import the art as Pages.Shop1 and run again."
				)
				return
			end
			stash = imported:Clone()
			stash.Parent = imports
			out:print("Stashed the import at ServerStorage.UIImports.Shop1. Every run rebuilds from that copy.")
		end

		-- === Out with the old ===========================================

		local existing = pages:FindFirstChild("Shop")
		if existing then
			if existing:GetAttribute("ImportedShop") then
				existing:Destroy() -- our own last run
			elseif pages:FindFirstChild("ShopOld") then
				existing:Destroy() -- the code-built page, already kept once
			else
				--[[ The page the old version of this script drew, kept the way `DealershipOld` and
					`SpawnCarOld` are: it is the only copy of a layout measured off the PSD, and it
					costs nothing parked and invisible. Nothing requires it — `UIController` loads
					modules and looks for a frame per module, never the other way round — so a Frame
					with no module beside it is inert. ]]
				existing.Name = "ShopOld"
				existing.Visible = false
			end
		end
		clear(pages, "Shop1")

		-- === In with the new ============================================

		local page = stash:Clone()
		page.Name = "Shop"
		page.Visible = false
		page:SetAttribute("ImportedShop", true)
		page.Parent = pages

		-- === The header ================================================
		--
		-- BG 1, cap 2, title 3, close 4 — the same stack `Pages.Market`, `Pages.Quest` and
		-- `Pages.Index` are authored in. The import left everything on ZIndex 1, so without this
		-- the cap would be laid over its own title.

		local bg = page:FindFirstChild("BG")
		if bg then
			bg.ZIndex = 1
		end

		clear(page, "TitleBar")
		make("ImageLabel", "TitleBar", page, {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromScale(1, CAP_HEIGHT),
			Image = "rbxassetid://" .. TITLE_BAR,
			ScaleType = Enum.ScaleType.Stretch,
			ZIndex = 2,
		})

		local title = page:FindFirstChild("Title")
		if title then
			title.ZIndex = 3
		end

		-- The close button. `Pages/Shop` and every other page in this project call it `Close`.
		local close = page:FindFirstChild("XButton")
		if close then
			close.Name = "Close"
			close.ZIndex = 4
			--[[ The X reacts like every other button in the kit, at the number every other page in
				the kit uses: Quest, Market and Index sit at 1.05, Teleport and Start Car at 1.06.
				It was 1.1 here on the theory that this was the page's smallest control, which was
				wrong twice over. It is the LARGEST close in the game (36px against their 29 to 30),
				and it now wears art with its own brighter hover face, so a swell loud enough to
				notice on top of that reads as two things answering one cursor. ]]
			close:AddTag("UIButton")
			close:SetAttribute("Scale", 1.06)

			--[[ AND IT IS THE KIT'S X, not the import's. Quest, Market, Index, Teleport and Start
				Car all wear `UIAssets.Page.Close`: a crimson coin with a soft cross, and a hover
				and a pressed face to go with it. The import brought its own, a flat red rounded
				square with a hard-rimmed cross and a single state. One page closing with a
				different shaped button in a different red was the last thing on this screen still
				announcing that it came from somewhere else.

				THE RECT IS THE ARTIST'S AND DOES NOT MOVE. Their X is square in pixels (0.0476 of
				the width against 0.0819 of the height at this page's 1.726 aspect) and it is
				centred in the band they painted, which is not where the kit pages put theirs.
				Only the three faces change.

				`AutoButtonColor` OFF, or Roblox lays its own press tint over `PressedImage` and
				the two darken together. Every kit page has it off for this reason; the import
				shipped it on because it had no pressed face to protect. ]]
			local button = close :: ImageButton
			button.Image = "rbxassetid://" .. CLOSE.Idle
			button.HoverImage = "rbxassetid://" .. CLOSE.Hover
			button.PressedImage = "rbxassetid://" .. CLOSE.Pressed
			button.AutoButtonColor = false
		end

		local shelf = page:FindFirstChild("Slots")
		if not shelf or not shelf:IsA("ScrollingFrame") then
			out:error("The import has no `Slots` ScrollingFrame. Has the art changed shape?")
			return
		end
		--[[ `Slots` is also what the import calls the CARDS inside each section, and a name that
			means two things one level apart is the kind of thing that reads fine until somebody
			writes `FindFirstChild("Slots")` and gets the wrong one. The container is the shelf. ]]
		shelf.Name = "Shelf"

		-- === The shelf ==================================================

		local shelfHeight = SHELF_BOTTOM - (BAND_TOP + BAND_HEIGHT + BAND_GAP)
		shelf.Size = UDim2.fromScale(shelf.Size.X.Scale, shelfHeight)
		shelf.Position = UDim2.fromScale(0.5, SHELF_BOTTOM - shelfHeight / 2)
		shelf.ScrollingDirection = Enum.ScrollingDirection.Y
		shelf.CanvasSize = UDim2.new()
		shelf.AutomaticCanvasSize = Enum.AutomaticSize.Y
		shelf.ScrollBarThickness = 8
		-- The kit's muted tone, at full opacity. The import's default bar and a first pass at
		-- `#5A688F` @0.2 both disappeared into the panel: this face is `#28334B` and anything only
		-- a shade off it is a bar you have to go looking for.
		shelf.ScrollBarImageColor3 = Color3.fromRGB(123, 133, 169)
		shelf.ScrollBarImageTransparency = 0
		--[[ THE BAR IS ALWAYS RESERVED, and that is a layout fix rather than a taste one. Sections
			are sized off `AbsoluteWindowSize.X`; with the default inset that width CHANGES when the
			bar appears, which resizes the sections, which changes the canvas, which can take the bar
			away again. Reserving the gutter makes the window width constant. ]]
		shelf.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar

		local list = shelf:FindFirstChildWhichIsA("UIListLayout")
		if not list then
			list = make("UIListLayout", "UIListLayout", shelf)
		end
		-- The import left this Horizontal, which is why the sections rendered as one long row. With
		-- tabs only one is ever visible, and a list layout skips invisible children, so this simply
		-- puts whichever section is showing at the top of the canvas.
		list.FillDirection = Enum.FillDirection.Vertical
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new()

		-- === The sections ===============================================

		clear(shelf, "Bundles#2")
		local bundleSection = shelf:FindFirstChild("Bundle")
		if bundleSection then
			bundleSection.Name = "Bundles"
		end

		local counts = {}
		for order, name in { "Bundles", "Currency", "Gamepasses" } do
			local section = shelf:FindFirstChild(name)
			if not section then
				out:warn(string.format("The import has no `%s` section; that tab will be empty.", name))
				continue
			end
			section.LayoutOrder = order
			section.Visible = false
			counts[name] = prepareSection(section, name)
		end

		--[[ THE CURRENCY MOSAIC IS THE ONE SECTION THAT STRETCHES ITS LAST ROW, and the reason is
			arithmetic the artist did not do: the mosaic holds five tiles and `CashConfig.Packs`
			holds six rungs, so the pattern always leaves exactly one over. Left alone that is the
			BIGGEST pack sat alone in a small tile at the bottom left, which reads backwards — the
			mosaic whole logic is that the tile grows with the amount. Sharing the row's width
			among however many tiles are actually in it puts a full-width tile under the two wide
			ones and the escalation lands. `Pages/Shop` picks the card art by width, so a stretched
			tile takes the wide art rather than a smeared small one.

			Off for the other two: a lone full-width GAMEPASS among half-width ones would stretch a
			card whose whole composition (icon left, text right) is drawn for that half-width. ]]
		local currency = shelf:FindFirstChild("Currency")
		if currency then
			currency:SetAttribute("StretchLastRow", true)
		end

		-- === The tabs ===================================================
		--
		-- Three pills in the band the shelf gave up. Sized off the pill's own aspect so they are the
		-- shape the art is drawn at, then centred as a group.

		clear(page, "Tabs")
		local tabs = make("Frame", "Tabs", page, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
		})

		local names = { "Bundles", "Currency", "Gamepasses" }
		-- A pill's width in PAGE scale: its height in page scale is a fraction of the page's height,
		-- and the page is `PAGE_ASPECT` times wider than it is tall.
		local tabWidth = BAND_HEIGHT * PILL_ASPECT / PAGE_ASPECT
		local span = #names * tabWidth + (#names - 1) * TAB_GAP
		local bandY = BAND_TOP + BAND_HEIGHT / 2

		for index, name in names do
			local centreX = 0.5 - span / 2 + (index - 1) * (tabWidth + TAB_GAP) + tabWidth / 2
			--[[ ONE COLOUR PER TAB, and `Pages/Shop.TAB` is where they are decided — these are copied
				so the strip in the Explorer is the strip in the game, not so that anything reads them
				from here. It was ORANGE selected and SILVER unselected until 2026-09-04, which put the
				two you were not on into the panel's own navy and read as two dead chips.

				No BLUE, because the title bar over them is `#0066FF` and a blue chip under a blue cap
				has to be told apart by shade. No ORANGE either — that is the buy pill now, and a tab
				the colour of the button that takes money is a tab people press expecting to be charged.

				`Pages/Shop` re-paints all of this on open: it lights the selected pill, grows it, and
				dims the other two. None of that shows in the Explorer. `ShopConfig.DefaultTab` is the
				truth; what is authored here is only what the page looks like sitting in the tree. ]]
			local colour = if name == "Bundles"
				then "Purple"
				elseif name == "Currency" then "Green"
				else "Sky"
			local tab = pill(
				name,
				tabs,
				UDim2.fromScale(centreX, bandY),
				UDim2.fromScale(tabWidth, BAND_HEIGHT),
				string.upper(name),
				colour
			)
			-- Hover swell and the click sound, for free. No `Page` attribute: a tab switches a
			-- section, it does not open a screen. See `Components/Button`.
			tab:AddTag("UIButton")
			tab:SetAttribute("Scale", 1.04)
		end

		pcall(function()
			props:SetSelection({ page })
		end)

		out:print(
			string.format(
				"Rebuilt StarterGui.MainUI.Pages.Shop from the import: 3 tabs, templates Bundles %d / Currency %d / Gamepasses %d. Old page parked as Pages.ShopOld.",
				counts.Bundles or 0,
				counts.Currency or 0,
				counts.Gamepasses or 0
			)
		)
	end,
} :: Types.ScriptModule
