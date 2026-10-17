--[[
	BuildSellCarV2: Command Runner command

	Builds `StarterGui.MainUIV2.Screens.SellCar`, the question the sell lot asks, out of the Cartoony
	Kit's `PromptUI`. Phase 4 of `docs/NewUI-Migration-Plan.md`; the running record is
	`docs/NewUI-Migration-Notes.md`.

	Run `BuildMainUIV2` first: this fills in a shelf that already exists rather than creating one.
	`Screens.SellCar` is destroyed and made again on every run, and nothing else on the shelf is
	touched, so it is safe beside the other Phase 4 commands and safe to re-run.

	=== A TEMPLATE, NOT A SCREEN ==============================================================

	Nothing draws this where it is built. `Screens` is hidden, and `SellPopupController` clones the
	template into its own `SellCar` ScreenGui, because that gui sits at `DisplayOrder` 997, under the
	welcome back panel, the revive question and the race fade, and a frame inside `MainUIV2` would
	share the HUD's one layer. The dim behind the panel stays built in code beside it.

	=== WHAT THE KIT DREW ====================================================================

	`PromptUI` is a two-answer question, which is this screen word for word:

	    PromptUI            the blue checker rim, 2.29:1
	      Header            Title "Prompt Request" (left) and a red CloseBtn
	      Main              the white body
	        Title           "You got invited to ... Would you like to go?", two lines
	        Btns            green AcceptBtn "Yeah, Sure!" and red DeclineBtn "No Way!", side by side

	=== WHAT IT BECOMES ======================================================================

	    SellCar             the kit frame, renamed, with the same taller body as WelcomeBack's
	      Header            Title "SELL THIS CAR?", CloseBtn unchanged (it means KEEP IT)
	      Main
	        CarName         the kit body's type, the top third: RED CAMARO
	        Price           the same type under a `Tint` gradient, the middle third: $2,400
	        Favorite        a row: the gold star and THIS IS A FAVORITE in the kit's orange
	        Btns
	          YesBtn        was AcceptBtn, green, SELL IT
	          NoBtn         was DeclineBtn, in the PANEL'S OWN BLUE, KEEP IT

	THE BODY GROWS BY THE SAME `BODY_EXTRA` AS WELCOME BACK'S, so the two prompts built on this frame
	are one size and a player who has met either has met the other. `growBody` is the same function in
	both commands; see the arithmetic there.

	=== THE COLOURS, AND WHY KEEP IT IS NOT RED ==============================================

	The kit's prompt answers green for yes and red for no. This screen cannot, and the reason is V1's
	and still holds: KEEP IT is the SAFE answer, and painting it red tells a player that keeping their
	own car is the dangerous choice. Red is also spent elsewhere on this panel, on the one moment that
	earns it: SELL IT turns red while it asks a starred car's second question. Two red pills at that
	moment would say nothing.

	So KEEP IT wears the panel's own blue, read off `PromptUI`'s rim gradient, which is exactly the
	face the kit's `TeleportBtn` wears: the kit's ordinary, go-ahead button. And the red the kit drew
	on `DeclineBtn` is kept, as the `ConfirmColor` ATTRIBUTE on `YesBtn`, before `NoBtn` is re-faced.
	`ColorSequence` is a supported attribute type, so the colour stays in the art (the Quest precedent).

	Every other colour is borrowed the same way:

	  • `Price` carries `MoneyColor`, the kit's cash counter's gradient (`HUD.BottomInfo.Cash.Title`),
	    and `RefusedColor`, that same red, for THAT CAR HAS LEFT THE LOT. Its `Tint` ships on, in money.
	    SELLING... is the plain white type: the controller switches the tint off.
	  • `Favorite.Line` wears the kit's legendary orange (`IndexUI.SideBtns.LegendaryBtn`), the caution
	    colour V1 used amber for.
	  • The star is `UIAssets.Inventory.Favorite`, the same star the Cars page draws on a starred card,
	    so a starred car is marked on this panel with the thing that starred it. The kit has no star.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)

--- The gold star. Read rather than typed, so it cannot drift from the Cars page's.
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local SHELF_NAME = "Screens"
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage

local ENTRY_NAME = "SellCar"
local KIT_FRAME = "PromptUI"

--- Where each borrowed colour comes from, as a path under the kit's `Container`. See the header.
local MONEY_SOURCE = { "HUD", "BottomInfo", "Cash", "Title" }
local WARN_SOURCE = { "IndexUI", "SideBtns", "LegendaryBtn" }

--- The kit's names, and ours. Every one of ours is a path `SellPopupController` walks.
local KIT_BODY = "Title"
local KIT_ACCEPT = "AcceptBtn"
local KIT_DECLINE = "DeclineBtn"
local NAME_NAME = "CarName"
local PRICE_NAME = "Price"
local FAVORITE_NAME = "Favorite"
local STAR_NAME = "Star"
local LINE_NAME = "Line"
local YES_NAME = "YesBtn"
local NO_NAME = "NoBtn"
local TINT_GRADIENT = "Tint"
local MONEY_ATTRIBUTE = "MoneyColor"
local REFUSED_ATTRIBUTE = "RefusedColor"
local CONFIRM_ATTRIBUTE = "ConfirmColor"

--- How much taller the body gets, as a fraction of the panel's authored height. The same number as
--- `BuildWelcomeBackV2`'s, on purpose: see the header.
local BODY_EXTRA = 0.22

--[[ The three rows, as { top, bottom } fractions of the grown body band.

	THE PRICE IS THE TALLEST, as it was on V1 (0.17 of its panel to the name's 0.13): it is what the
	question is about, and the row doubles as the reply. The name is nearly as tall, because the one
	mistake this screen exists to prevent is selling a car the player did not think they were selling.
	The favourite row keeps its place when there is no star, so the buttons never move between two
	cars (V1's `STAR_Y` note). ]]
local NAME_BAND = { 0, 0.3 }
local PRICE_BAND = { 0.34, 0.72 }
local FAVORITE_BAND = { 0.77, 1 }

--[[ The favourite row: the star as a square the row's height, then the line, centred as a pair by a
	horizontal layout so the gap stays the gap whatever the words are. The line's box is a fixed share
	of the row, left aligned against the star: V1's arrangement, since `TextScaled` gives no width to
	lay out against.

	0.44 IS MEASURED, NOT PICKED. The first cut was V1's 0.62 less a little (0.56), and the render put
	the pair visibly left of centre: THIS IS A FAVORITE sets 157px wide at the row's height in a 213px
	box, and the layout centres the boxes, not the words. 0.44 is 167px at Studio's viewport, which
	keeps the height the binding axis with a few pixels to spare. ]]
local STAR_WIDTH = 0.08
local LINE_WIDTH = 0.44
local ROW_GAP = 0.015

--- The kit's own placeholders, replaced by what a player could see, so a freshly built template reads
--- as the finished screen in the Explorer. All of them are overwritten on the first offer.
local TITLE_TEXT = "SELL THIS CAR?" -- SellConfig.PopupLines.Title
local NAME_PLACEHOLDER = "RED CAMARO"
local PRICE_PLACEHOLDER = "$2,400"
local LINE_PLACEHOLDER = "THIS IS A FAVORITE" -- SellConfig.Lines.Favorite
local YES_PLACEHOLDER = "SELL IT" -- SellConfig.PopupLines.Yes
local NO_PLACEHOLDER = "KEEP IT" -- SellConfig.PopupLines.No

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

--- The `UIGradient` on the instance at `path` under the kit's container, or nil.
local function gradientAt(container: Instance, path: { string }): UIGradient?
	local node: Instance? = container
	for _, step in path do
		node = node and node:FindFirstChild(step)
	end
	return node and node:FindFirstChildOfClass("UIGradient")
end

--[[ Re-express one child's vertical box after its parent grew by `added` at the line `at`, both in
	the parent's OLD height units. Below the line moves down, across it grows, above it stays; then
	everything is divided by the parent's new height. `BuildWelcomeBackV2` has the same function. ]]
local function refit(child: GuiObject, at: number, added: number)
	local ratio = 1 + added
	local anchor = child.AnchorPoint.Y
	local height = child.Size.Y.Scale
	local top = child.Position.Y.Scale - anchor * height
	if top >= at then
		top += added
	elseif top + height > at then
		height += added
	end
	child.Size = UDim2.new(child.Size.X, UDim.new(height / ratio, child.Size.Y.Offset))
	child.Position = UDim2.new(child.Position.X, UDim.new((top + anchor * height) / ratio, child.Position.Y.Offset))
end

--- A frame's rim and corner after its height grew by `ratio`: both are fractions of the shorter side,
--- which is the height here, so dividing keeps them at the artist's pixels.
local function keepRim(frame: GuiObject, ratio: number)
	for _, child in frame:GetChildren() do
		if child:IsA("UIStroke") and child.StrokeSizingMode == Enum.StrokeSizingMode.ScaledSize then
			child.Thickness /= ratio
		elseif child:IsA("UICorner") then
			child.CornerRadius = UDim.new(child.CornerRadius.Scale / ratio, child.CornerRadius.Offset)
		end
	end
end

--[[ Make the body band taller by `extra` of the panel's height and leave every other pixel alone:
	the panel and `Main` grow, `Header` and `Btns` keep their size and their distance from the edges
	they sit against, and the checker keeps its squares. Returns the band as { top, height } in
	`Main`'s new units. `BuildWelcomeBackV2` has the same function and the longer note. ]]
local function growBody(panel: GuiObject, main: GuiObject, body: GuiObject, extra: number): (number, number)
	local panelRatio = 1 + extra

	local mainHeight = main.Size.Y.Scale
	local mainTop = main.Position.Y.Scale - main.AnchorPoint.Y * mainHeight
	local bodyTop = body.Position.Y.Scale - body.AnchorPoint.Y * body.Size.Y.Scale
	local bodyMiddle = bodyTop + body.Size.Y.Scale / 2

	panel.Size = UDim2.new(panel.Size.X, UDim.new(panel.Size.Y.Scale * panelRatio, panel.Size.Y.Offset))
	local aspect = panel:FindFirstChildOfClass("UIAspectRatioConstraint")
	if aspect then
		aspect.AspectRatio /= panelRatio
	end
	keepRim(panel, panelRatio)

	local line = mainTop + mainHeight * bodyMiddle
	for _, child in panel:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "BG" then
			refit(child, line, extra)
		end
	end
	local bg = panel:FindFirstChild("BG")
	local checkers = bg and bg:FindFirstChild("CheckersBG")
	if checkers and checkers:IsA("GuiObject") then
		checkers.Size = UDim2.new(checkers.Size.X, UDim.new(checkers.Size.Y.Scale / panelRatio, checkers.Size.Y.Offset))
	end

	local mainAdded = extra / mainHeight
	keepRim(main, 1 + mainAdded)
	for _, child in main:GetChildren() do
		if child:IsA("GuiObject") then
			refit(child, bodyMiddle, mainAdded)
		end
	end

	local newHeight = body.Size.Y.Scale
	return body.Position.Y.Scale - body.AnchorPoint.Y * newHeight, newHeight
end

--- Non-breaking spaces, because `TextScaled` would sooner wrap a line than shrink it. The controller
--- writes every runtime string this way; the placeholders follow so the Explorer shows the real look.
local function oneLine(text: string): string
	return (string.gsub(text, " ", "\u{00A0}"))
end

--- One row of the body: a copy of the kit's own body type, cut to a slice of the band.
local function bodyLine(body: TextLabel, name: string, band: { number }, top: number, height: number, text: string): TextLabel
	local label = body:Clone()
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = UDim2.new(body.Size.X, UDim.new(height * (band[2] - band[1]), 0))
	label.Position = UDim2.new(body.Position.X, UDim.new(top + height * (band[1] + band[2]) / 2, 0))
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	--- Never `TextWrapped = false`: it switches `TextScaled` off with it (`BuildWelcomeBackV2` found
	--- that). One line stays one line through non-breaking spaces in the text.
	label.TextScaled = true
	label.Text = oneLine(text)
	label.Parent = body.Parent
	return label
end

local function setCaption(button: Instance, text: string)
	local title = button:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = oneLine(text)
	end
end

return {
	Description = "Build StarterGui.MainUIV2.Screens.SellCar (the sell lot's question) from the Cartoony Kit's PromptUI: a taller body holding the car's name, the price and the favourite row, SELL IT on the green button (its confirm red kept as an attribute) and KEEP IT in the panel's blue. Rebuilds the shelf entry every run.",
	Tags = { "UI", "NewUI" },
	AutoRecordChanges = true,

	Arguments = {} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		local screen = StarterGui:FindFirstChild(SCREEN_NAME)
		local shelf = screen and screen:FindFirstChild(SHELF_NAME)
		if not (shelf and shelf:IsA("GuiObject")) then
			out:error(string.format("No StarterGui.%s.%s. Run BuildMainUIV2 first.", SCREEN_NAME, SHELF_NAME))
			return
		end

		local container, why = findTemplate()
		if not container then
			out:error(string.format("The kit is not where it should be: %s", why))
			return
		end

		local kitFrame = container:FindFirstChild(KIT_FRAME)
		if not (kitFrame and kitFrame:IsA("GuiObject")) then
			out:error(string.format("%s has no `%s` to build from.", container:GetFullName(), KIT_FRAME))
			return
		end

		--- Read before anything is destroyed, so a kit missing one stops the build with the entry it
		--- already had still standing.
		local money = gradientAt(container, MONEY_SOURCE)
		local warnTint = gradientAt(container, WARN_SOURCE)
		if not (money and warnTint) then
			out:error(
				string.format(
					"The kit is missing a colour this panel borrows: %s%s.",
					if money then "" else table.concat(MONEY_SOURCE, ".") .. " (money) ",
					if warnTint then "" else table.concat(WARN_SOURCE, ".") .. " (warning)"
				)
			)
			return
		end

		local existing = shelf:FindFirstChild(ENTRY_NAME)
		if existing then
			existing:Destroy()
		end

		local panel = kitFrame:Clone() :: GuiObject
		panel.Name = ENTRY_NAME
		--- The kit ships every frame hidden. The shelf is what hides a template.
		panel.Visible = true

		local header = panel:FindFirstChild("Header")
		local main = panel:FindFirstChild("Main")
		local body = main and main:FindFirstChild(KIT_BODY)
		local btns = main and main:FindFirstChild("Btns")
		local accept = btns and btns:FindFirstChild(KIT_ACCEPT)
		local decline = btns and btns:FindFirstChild(KIT_DECLINE)
		local rim = panel:FindFirstChildOfClass("UIGradient")
		local yesFace = accept and accept:FindFirstChildOfClass("UIGradient")
		local noFace = decline and decline:FindFirstChildOfClass("UIGradient")
		if not (header and main and main:IsA("GuiObject") and body and body:IsA("TextLabel") and btns and yesFace and noFace and rim) then
			out:error(
				string.format(
					"The kit's %s is missing `Header`, `Main.%s`, its rim gradient, or a `Main.Btns.%s` / `%s` with a gradient face.",
					KIT_FRAME,
					KIT_BODY,
					KIT_ACCEPT,
					KIT_DECLINE
				)
			)
			panel:Destroy()
			return
		end

		-- === The header =====================================================
		local title = header:FindFirstChild("Title")
		if title and title:IsA("TextLabel") then
			title.Text = TITLE_TEXT
		else
			out:warn(string.format("The kit's %s has no `Header.Title`; the panel keeps no heading.", KIT_FRAME))
		end

		-- === The body =======================================================
		local bandTop, bandHeight = growBody(panel, main :: GuiObject, body :: GuiObject, BODY_EXTRA)
		local bodyLabel = body :: TextLabel

		bodyLine(bodyLabel, NAME_NAME, NAME_BAND, bandTop, bandHeight, NAME_PLACEHOLDER)

		local price = bodyLine(bodyLabel, PRICE_NAME, PRICE_BAND, bandTop, bandHeight, PRICE_PLACEHOLDER)
		local tint = (money :: UIGradient):Clone()
		tint.Name = TINT_GRADIENT
		tint.Enabled = true
		tint.Parent = price
		price:SetAttribute(MONEY_ATTRIBUTE, (money :: UIGradient).Color)
		--- Read off the kit's red button BEFORE that button is re-faced below.
		price:SetAttribute(REFUSED_ATTRIBUTE, (noFace :: UIGradient).Color)

		local row = Instance.new("Frame")
		row.Name = FAVORITE_NAME
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.AnchorPoint = Vector2.new(0.5, 0.5)
		row.Size = UDim2.new(bodyLabel.Size.X, UDim.new(bandHeight * (FAVORITE_BAND[2] - FAVORITE_BAND[1]), 0))
		row.Position = UDim2.new(bodyLabel.Position.X, UDim.new(bandTop + bandHeight * (FAVORITE_BAND[1] + FAVORITE_BAND[2]) / 2, 0))
		row.ZIndex = bodyLabel.ZIndex

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(ROW_GAP, 0)
		layout.Parent = row

		local star = Instance.new("ImageLabel")
		star.Name = STAR_NAME
		star.LayoutOrder = 1
		--- A real width, never zero: the aspect constraint fits INSIDE this box.
		star.Size = UDim2.fromScale(STAR_WIDTH, 1)
		star.BackgroundTransparency = 1
		star.Image = UIAssets.url(UIAssets.Inventory.Favorite)
		star.ScaleType = Enum.ScaleType.Fit
		star.ZIndex = bodyLabel.ZIndex
		star.Parent = row
		local starAspect = Instance.new("UIAspectRatioConstraint")
		starAspect.AspectRatio = UIAssets.DealerSize.Badge.X / UIAssets.DealerSize.Badge.Y
		starAspect.Parent = star

		local line = bodyLabel:Clone()
		line.Name = LINE_NAME
		line.LayoutOrder = 2
		line.AnchorPoint = Vector2.new(0, 0)
		line.Position = UDim2.new()
		line.Size = UDim2.fromScale(LINE_WIDTH, 1)
		line.TextXAlignment = Enum.TextXAlignment.Left
		line.TextScaled = true
		line.Text = oneLine(LINE_PLACEHOLDER)
		local lineTint = (warnTint :: UIGradient):Clone()
		lineTint.Name = TINT_GRADIENT
		lineTint.Parent = line
		line.Parent = row

		row.Parent = main

		bodyLabel:Destroy()

		-- === The buttons ====================================================
		accept.Name = YES_NAME
		accept.LayoutOrder = 1
		setCaption(accept, YES_PLACEHOLDER)
		accept:SetAttribute(CONFIRM_ATTRIBUTE, (noFace :: UIGradient).Color)

		decline.Name = NO_NAME
		decline.LayoutOrder = 2
		local blue = noFace :: UIGradient
		blue.Color = (rim :: UIGradient).Color
		blue.Rotation = (rim :: UIGradient).Rotation
		setCaption(decline, NO_PLACEHOLDER)

		local buttons = btns:FindFirstChildOfClass("UIListLayout")
		if buttons then
			buttons.SortOrder = Enum.SortOrder.LayoutOrder
			buttons.HorizontalAlignment = Enum.HorizontalAlignment.Center
			buttons.VerticalAlignment = Enum.VerticalAlignment.Center
		end

		panel.Parent = shelf

		out:print(string.format("Built %s.%s.%s from the kit's %s.", SCREEN_NAME, SHELF_NAME, ENTRY_NAME, KIT_FRAME))
		out:print(
			string.format(
				"Body grown by %.2f of the panel; `%s`, `%s` (money tint, refused red as an attribute), `%s` row with the star. `%s` green with `%s`, `%s` in the panel's blue.",
				BODY_EXTRA,
				NAME_NAME,
				PRICE_NAME,
				FAVORITE_NAME,
				YES_NAME,
				CONFIRM_ATTRIBUTE,
				NO_NAME
			)
		)

		pcall(function()
			props:SetSelection({ panel })
		end)
	end,
} :: Types.ScriptModule
