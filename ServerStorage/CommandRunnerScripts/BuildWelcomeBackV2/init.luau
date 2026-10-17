--[[
	BuildWelcomeBackV2: Command Runner command

	Builds `StarterGui.MainUIV2.Screens.WelcomeBack`, the offline cash panel a player meets on join,
	out of the Cartoony Kit's `PromptUI`. Phase 4 of `docs/NewUI-Migration-Plan.md`; the running
	record is `docs/NewUI-Migration-Notes.md`.

	Run `BuildMainUIV2` first: this fills in a shelf that already exists rather than creating one.
	`Screens.WelcomeBack` is destroyed and made again on every run, and nothing else on the shelf is
	touched, so it is safe beside the other Phase 4 commands and safe to re-run.

	=== A TEMPLATE, NOT A SCREEN ==============================================================

	Nothing draws this where it is built. `Screens` is hidden, and `OfflineController` clones the
	template into its own `WelcomeBack` ScreenGui, because that gui sits at `DisplayOrder` 998, under
	the revive question and the race fade, and a frame inside `MainUIV2` would share the HUD's one
	layer. The dim behind the panel stays built in code beside it.

	=== WHAT THE KIT DREW ====================================================================

	`PromptUI` is a two-answer question:

	    PromptUI            the blue checker rim, 2.29:1
	      Header            Title "Prompt Request" (left) and a red CloseBtn
	      Main              the white body
	        Title           "You got invited to ... Would you like to go?", two lines
	        Btns            green AcceptBtn "Yeah, Sure!" and red DeclineBtn "No Way!", side by side

	Which is the welcome back panel's shape exactly: a heading, the X that dismisses, something to
	read, and two presses side by side. So the composition is the artist's and nothing moves.

	=== WHAT IT BECOMES ======================================================================

	    WelcomeBack         the kit frame, renamed, with a taller body (below)
	      Header            Title "WELCOME BACK", CloseBtn unchanged
	      Main
	        Away            the kit body's type, the top fifth of the body: AWAY FOR 3h 12m
	        Amount          the same type in the kit's MONEY gradient, the middle half: the payout
	        Foot            the same type, the bottom fifth: the bays line, the cap warning or 2x APPLIED
	        Btns
	          CollectBtn    was AcceptBtn, green, COLLECT
	          BoostBtn      was DeclineBtn, in the kit's ROBUX PURCHASE face: COLLECT 2X and the price

	THE BODY IS ONE SENTENCE IN THE KIT AND THREE LINES HERE, and one of them is the reason the screen
	exists. The kit's body band is two lines of prose at about 20px each at 1080p's height in Studio,
	which is a fine size for "would you like to go?" and a footnote-sized payout. So the body grows
	(`BODY_EXTRA`) and nothing else does: the header, the buttons and every rim keep their pixels, and
	only the band between them gets taller. See `growBody` for the arithmetic, which is the part worth
	reading before changing a number.

	=== WHAT IS BORROWED, AND FROM WHERE =====================================================

	The kit states everything this panel says in colour somewhere else, so nothing here is a colour
	somebody picked:

	  • `Amount` wears `HUD.BottomInfo.Cash.Title`'s gradient, the kit's cash counter, yellow into
	    green. It is the number the counter is about to roll up by, so it is drawn in the counter's ink.
	  • `BoostBtn` wears `RobuxShopUI`'s `PurchaseBtn` face, yellow into orange, which is how this kit
	    draws a button that spends Robux (the shop's packs, the spin wheel's `+1 Spin`, the timed
	    rewards' `Unlock All`). V1 made the boost orange for its own reasons and arrived at the same place.
	  • `Foot` carries both of its tints as ATTRIBUTES rather than as colours in the controller:
	    `WarnColor` is the kit's legendary orange (`IndexUI.SideBtns.LegendaryBtn`), for the line that
	    says the bays filled up, and `AppliedColor` is the money gradient again, for 2x APPLIED. Its
	    `Tint` gradient ships disabled, which is the plain white line. `ColorSequence` is a supported
	    attribute type, so the colours stay in the art where they can be retuned (the Quest precedent).

	=== WHAT GOES ============================================================================

	`DeclineBtn` as a NO. The kit's X already dismisses, and V1's panel has the same two exits (the X
	and B on a pad); a red "No" beside COLLECT would be a third way of leaving money on the bays. The
	button stays, re-faced as the boost, because the second press is the artist's and the layout
	centres COLLECT on its own when the boost cannot be sold.
]]

local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local SHELF_NAME = "Screens"
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage

local ENTRY_NAME = "WelcomeBack"
local KIT_FRAME = "PromptUI"

--- Where each borrowed colour comes from, as a path under the kit's `Container`. See the header.
local MONEY_SOURCE = { "HUD", "BottomInfo", "Cash", "Title" }
local PURCHASE_SOURCE = { "RobuxShopUI", "Main", "ScrollingFrame", "StarterPack", "Btns", "MainBtns", "PurchaseBtn" }
local WARN_SOURCE = { "IndexUI", "SideBtns", "LegendaryBtn" }

--- The kit's names, and ours. Every one of ours is a path `OfflineController` walks.
local KIT_BODY = "Title"
local KIT_ACCEPT = "AcceptBtn"
local KIT_DECLINE = "DeclineBtn"
local AWAY_NAME = "Away"
local AMOUNT_NAME = "Amount"
local FOOT_NAME = "Foot"
local COLLECT_NAME = "CollectBtn"
local BOOST_NAME = "BoostBtn"
local MONEY_GRADIENT = "Money"
local TINT_GRADIENT = "Tint"
local WARN_ATTRIBUTE = "WarnColor"
local APPLIED_ATTRIBUTE = "AppliedColor"

--[[ How much taller the body gets, as a fraction of the panel's AUTHORED height. Everything else
	keeps its pixels.

	0.22 takes the band from about 43px to about 83px at Studio's 651px viewport, which is room for a
	payout line twice the height of the kit's prose line with the two small lines either side of it.
	The panel comes out 1.22 times as tall and exactly as wide. ]]
local BODY_EXTRA = 0.22

--[[ The three lines, as { top, bottom } fractions of the grown body band.

	THE NUMBER TAKES HALF THE BAND and the two lines either side of it take a fifth each, which is
	V1's proportion (0.09, 0.19, 0.075 of its panel) squared up. The gaps between them are the only
	spacing on the panel that is ours. ]]
local AWAY_BAND = { 0, 0.21 }
local AMOUNT_BAND = { 0.25, 0.75 }
local FOOT_BAND = { 0.79, 1 }

--- The kit's own placeholders, replaced by numbers a player could see, so a freshly built template
--- reads as the finished screen in the Explorer. All of them are overwritten on the first paint.
local ROBUX = utf8.char(0xE002)
local TITLE_TEXT = "WELCOME BACK" -- OfflineConfig.Title
local AWAY_PLACEHOLDER = "AWAY FOR 3h\u{00A0}12m"
local AMOUNT_PLACEHOLDER = "$12,480"
local FOOT_PLACEHOLDER = "WAITING ON 4 BAYS"
local COLLECT_PLACEHOLDER = "COLLECT" -- OfflineConfig.CollectText
local BOOST_PLACEHOLDER = "COLLECT 2X  " .. ROBUX .. "49"

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
	the parent's OLD height units.

	A child wholly below the line moves down by `added`, the one that straddles it grows by `added`,
	and one wholly above it stays put. Then everything is divided by the parent's new height, which
	is what turns "keeps its pixels" into scale again. ]]
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

--[[ A frame's own rim and corner, after its height grew by `ratio`.

	BOTH ARE MEASURED AGAINST THE SHORTER SIDE: a `ScaledSize` stroke is a fraction of the parent's
	minimum width or height, and so is a `UICorner`'s scale radius. Both of these frames are wider
	than tall before and after, so the height is the side, and dividing by the growth keeps the rim
	and the curve at the artist's pixels. ]]
local function keepRim(frame: GuiObject, ratio: number)
	for _, child in frame:GetChildren() do
		if child:IsA("UIStroke") and child.StrokeSizingMode == Enum.StrokeSizingMode.ScaledSize then
			child.Thickness /= ratio
		elseif child:IsA("UICorner") then
			child.CornerRadius = UDim.new(child.CornerRadius.Scale / ratio, child.CornerRadius.Offset)
		end
	end
end

--[[ Make the body band taller by `extra` of the panel's height and leave every other pixel alone.

	THREE LEVELS, ONE RULE (`refit`):

	  • The PANEL grows by `extra`. Its `Size.Y` scale goes up and its aspect ratio comes down by the
	    same factor, so the width does not move whichever axis the constraint is fitting to.
	  • Inside it, `Header` sits above the band and keeps its pixels; `Main` straddles it and grows by
	    all of it; `BG` fills the panel and stays a fill, with the checker pattern held at its pixels
	    so the squares stay square.
	  • Inside `Main`, the body label straddles the band and grows; `Btns` sits below it and moves
	    down, keeping its height and its gap to the bottom rim.

	Returns the body band as { top, height } in `Main`'s new units, for the lines that replace it. ]]
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

--- One line of the body: a copy of the kit's own body type, cut to a slice of the band.
local function bodyLine(body: TextLabel, name: string, band: { number }, top: number, height: number, text: string): TextLabel
	local label = body:Clone()
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = UDim2.new(body.Size.X, UDim.new(height * (band[2] - band[1]), 0))
	label.Position = UDim2.new(body.Position.X, UDim.new(top + height * (band[1] + band[2]) / 2, 0))
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	--[[ `TextScaled` stays as the kit set it, and NOTHING HERE WRITES `TextWrapped`: the two are one
		switch underneath, and setting `TextWrapped = false` turns `TextScaled` off with it. The first
		build did exactly that and every line drew at 14px in its box. One line is kept to one line the
		project's way instead, with non-breaking spaces in the text. ]]
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
	Description = "Build StarterGui.MainUIV2.Screens.WelcomeBack (the offline cash panel) from the Cartoony Kit's PromptUI: a taller body holding the time away, the payout in the kit's money gradient and the bays line, COLLECT on the green button and the boost on the kit's Robux purchase face. Rebuilds the shelf entry every run.",
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

		--- Read before anything is destroyed, so a kit missing one of them stops the build with the
		--- entry it already had still standing.
		local money = gradientAt(container, MONEY_SOURCE)
		local purchase = gradientAt(container, PURCHASE_SOURCE)
		local warnTint = gradientAt(container, WARN_SOURCE)
		if not (money and purchase and warnTint) then
			out:error(
				string.format(
					"The kit is missing a colour this panel borrows: %s%s%s.",
					if money then "" else table.concat(MONEY_SOURCE, ".") .. " (money) ",
					if purchase then "" else table.concat(PURCHASE_SOURCE, ".") .. " (purchase) ",
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
		--- The kit ships every frame hidden. The shelf is what hides a template; ticking the shelf
		--- visible to author this should show it.
		panel.Visible = true

		local header = panel:FindFirstChild("Header")
		local main = panel:FindFirstChild("Main")
		local body = main and main:FindFirstChild(KIT_BODY)
		local btns = main and main:FindFirstChild("Btns")
		local accept = btns and btns:FindFirstChild(KIT_ACCEPT)
		local decline = btns and btns:FindFirstChild(KIT_DECLINE)
		if not (header and main and main:IsA("GuiObject") and body and body:IsA("TextLabel") and btns and accept and decline) then
			out:error(string.format("The kit's %s is missing `Header`, `Main.%s`, `Main.Btns.%s` or `Main.Btns.%s`.", KIT_FRAME, KIT_BODY, KIT_ACCEPT, KIT_DECLINE))
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
		bodyLine(bodyLabel, AWAY_NAME, AWAY_BAND, bandTop, bandHeight, AWAY_PLACEHOLDER)

		local amount = bodyLine(bodyLabel, AMOUNT_NAME, AMOUNT_BAND, bandTop, bandHeight, AMOUNT_PLACEHOLDER)
		local moneyGradient = (money :: UIGradient):Clone()
		moneyGradient.Name = MONEY_GRADIENT
		moneyGradient.Parent = amount

		local foot = bodyLine(bodyLabel, FOOT_NAME, FOOT_BAND, bandTop, bandHeight, FOOT_PLACEHOLDER)
		local tint = (money :: UIGradient):Clone()
		tint.Name = TINT_GRADIENT
		tint.Enabled = false
		tint.Parent = foot
		foot:SetAttribute(WARN_ATTRIBUTE, (warnTint :: UIGradient).Color)
		foot:SetAttribute(APPLIED_ATTRIBUTE, (money :: UIGradient).Color)

		bodyLabel:Destroy()

		-- === The buttons ====================================================
		accept.Name = COLLECT_NAME
		accept.LayoutOrder = 1
		setCaption(accept, COLLECT_PLACEHOLDER)

		decline.Name = BOOST_NAME
		decline.LayoutOrder = 2
		local face = decline:FindFirstChildOfClass("UIGradient")
		if face then
			face.Color = (purchase :: UIGradient).Color
			face.Rotation = (purchase :: UIGradient).Rotation
		else
			out:warn(string.format("`%s` has no UIGradient; the boost keeps the kit's red face.", BOOST_NAME))
		end
		setCaption(decline, BOOST_PLACEHOLDER)

		--- One button centres on its own when the boost cannot be sold (the controller hides it).
		local layout = btns:FindFirstChildOfClass("UIListLayout")
		if layout then
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			layout.VerticalAlignment = Enum.VerticalAlignment.Center
		else
			out:warn("The kit's `Main.Btns` has no UIListLayout; a lone COLLECT will not centre.")
		end

		panel.Parent = shelf

		out:print(string.format("Built %s.%s.%s from the kit's %s.", SCREEN_NAME, SHELF_NAME, ENTRY_NAME, KIT_FRAME))
		out:print(
			string.format(
				"Body grown by %.2f of the panel; `%s`, `%s` (money gradient) and `%s` (tint off, warn and applied as attributes). `%s` green, `%s` on the kit's purchase face.",
				BODY_EXTRA,
				AWAY_NAME,
				AMOUNT_NAME,
				FOOT_NAME,
				COLLECT_NAME,
				BOOST_NAME
			)
		)

		pcall(function()
			props:SetSelection({ panel })
		end)
	end,
} :: Types.ScriptModule
