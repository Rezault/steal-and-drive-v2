--[[
	BuildBuyerOfferV2: Command Runner command

	Builds `StarterGui.MainUIV2.Screens.BuyerOffer`, the screen a buyer's offer opens, out of the
	Cartoony Kit's `PromptUI`: the same frame the sell lot's question is cut from, so the two money
	questions a player is asked about their own car read as one family. Added 2026-09-30.

	Run `BuildMainUIV2` first: this fills in a shelf that already exists rather than creating one.
	`Screens.BuyerOffer` is destroyed and made again on every run and nothing else on the shelf is
	touched, so it is safe beside the other screen commands and safe to re-run.

	=== A TEMPLATE, NOT A SCREEN ==============================================================

	Nothing draws this where it is built. `Screens` is hidden, and `BuyerController._buildKit` clones
	the template into its own `BuyerOffer` ScreenGui, which keeps the old screen's `DisplayOrder`. The
	dim behind the panel stays built in code, as on every other shelf screen.

	=== WHAT IT BECOMES =======================================================================

	`PromptUI` is a two-answer question with one line of body type. This one needs a car and five
	lines, so the frame is WIDENED and split rather than grown:

	    BuyerOffer          the kit frame, 860x440 at 1080p (PromptUI is 696x304)
	      Header            Title "OFFER FROM HALT_CEO" (left, as the kit sets it), CloseBtn
	      Showcase          the LEFT column, on the panel's own blue
	        CarName         the header's type, centred: WHITE KAMARO
	        Portrait        an empty box the car turns in, `Backdrop` stamped on it
	      Main              the kit's white body, now the RIGHT column
	        Offered         THEY OFFER
	        Price           $1,125, under the money `Tint`
	        Value           MARKET VALUE $1,345
	        Percent         -16% BELOW VALUE
	        Rating          LOW OFFER, coloured per band at runtime
	        Btns
	          AcceptBtn     green, ACCEPT
	          DeclineBtn    red, DECLINE

	THE CAR STANDS ON THE BLUE, NOT ON THE WHITE. The body is opaque white and the car being sold is
	as often as not a white one; on the blue it has an edge. It is also where the car detail wings
	put a turning car (`BuildCarDetailV2.Panel`, after Dylan asked for the card face behind it to go),
	so a car on a kit panel looks the same wherever it turns. `BuildWorkshopV2` makes the same split.

	THE ANSWERS KEEP THE KIT'S OWN COLOURS. The sell prompt paints its "no" blue because KEEP IT is
	the safe answer and red would call it dangerous. DECLINE is not that: it ends the offer and the
	buyer walks, which is exactly the "No Way!" the artist drew in red. The safe way out of THIS
	screen is the X, which closes it with the buyer still waiting.

	=== THE GEOMETRY IS WORKED IN 1080p PIXELS ===============================================

	Every number below is a pixel on a 1920x1080 screen, and every box is written back as a scale of
	its parent, so the panel is exactly the kit's proportions at 1080p and in proportion everywhere
	else. A kit text cap is also a 1080p pixel height (`KitPage.scaleTextCaps`), so the caps written
	here are simply the heights of their boxes. The kit's rims and corners are fractions of each
	frame's SHORTER side, so every frame whose shorter side moves has them divided back to the
	artist's pixels (`keepRim`), and the checker keeps its cell size (`keepChecker`).

	=== AND THE SIGN OVER THE BUYER'S HEAD (2026-10-06) ======================================

	`Screens.BuyerSign` is the world billboard (`BuyerController._bind`, `BuyerOfferSign.buildKit`) cut
	from the same `PromptUI`, so the sign and the screen it opens are one family. It replaced a
	hand-drawn arcade card whose cyan rim, ten-cell checker and pixel outlines were nowhere in the kit.

	    BuyerSign           fills the BillboardGui; the controller sets the two shares below
	      Panel             PromptUI's chassis: blue ramp, both rims, the kit checker
	        Header.Title    HALT_CE WANTS TO BUY
	        Main            the white body: Car, Caption, Amount (money Tint), Comparison, Rating
	      Countdown         a small strip of the same chassis hanging under it
	        Time            OFFER ENDS IN 0:42 (rich text)
	        Track.Progress  QuestsUI's progress bar

	IT LIVES IN WORLD SPACE, so two kit habits are undone: every `UITextSizeConstraint` goes (a cap is
	a screen pixel, and a billboard walked up to would stop its text growing), and the rims stay
	`ScaledSize`, which is what keeps them in proportion at every distance where a pixel stroke would
	not (`billboard-ui-is-scale-only`). The geometry is worked at a NOMINAL 380px-wide sign, about the
	size one reads at across a bay, so the rims are the artist's at the distance it is read from.

	HOUSE RULE: no wiki-style double-bracket links in this comment; the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local SHELF_NAME = "Screens"
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage

local ENTRY_NAME = "BuyerOffer"
local KIT_FRAME = "PromptUI"

--- The kit's cash counter, whose gradient is the money ink (the sell prompt borrows the same one).
local MONEY_SOURCE = { "HUD", "BottomInfo", "Cash", "Title" }

--- The screen every pixel below is measured on.
local REF_W, REF_H = 1920, 1080

--- The whole panel. Wider than `PromptUI` by the left column, taller by the four extra lines.
local PANEL_W, PANEL_H = 860, 440

--- Room down each side of the panel, and between the two columns.
local EDGE = 16
local GAP = 14

--- The left column's width. The rest of the panel's width is the white body.
local SHOWCASE_W = 330

--- The header title's share of the header, wider than the kit's 0.6 because a buyer's name rides in it.
local TITLE_SHARE = 0.84

--- Inside the left column, top down: the car's name, then the box the car turns in. Pixels.
local NAME_TOP, NAME_H = 8, 44
local PORTRAIT_GAP = 10
local PORTRAIT_BOTTOM = 10

--[[ The five lines of the body, as { top, bottom } fractions of the band above the buttons.

	THE PRICE IS THE TALLEST, as it was on the placeholder screen: it is what the question is about.
	The rating is the second loudest because it is the one word that tells a player whether to take
	it. The two measurements between them are the evidence and read smaller. ]]
local BANDS = {
	Offered = { 0.00, 0.13 },
	Price = { 0.15, 0.44 },
	Value = { 0.50, 0.62 },
	Percent = { 0.65, 0.76 },
	Rating = { 0.82, 0.98 },
}

--- Pixels between the body's top edge and the first line, and between the last line and the buttons.
local BAND_PAD = 12

--- Side margin of the lines and of the button pair inside the body.
local BODY_SIDE = 16

--- Pixels between the two answers.
local BUTTON_GAP = 12

--- The kit's placeholders, replaced by what a player could see, so a freshly built template reads as
--- the finished screen in the Explorer. All of them are overwritten on the first offer.
local PLACEHOLDER = {
	Title = "OFFER FROM HALT_CEO", -- BuyerConfig.Screen.From
	CarName = "WHITE KAMARO",
	Offered = "THEY OFFER", -- BuyerConfig.Screen.Offered
	Price = "$1,125",
	Value = "MARKET VALUE $1,345",
	Percent = "-16% BELOW VALUE",
	Rating = "LOW OFFER",
	Accept = "ACCEPT", -- BuyerConfig.Screen.Accept
	Decline = "DECLINE", -- BuyerConfig.Screen.Decline
}

-- === The sign (world billboard) =============================================

local SIGN_NAME = "BuyerSign"
local KIT_BAR = { "QuestsUI", "Main", "Templates", "Template", "ProgressBar" }

--[[ The nominal sign, in pixels: `CarDealConfig.Bubble` is 11 studs by 6.926 for the panel, then a
	0.35 gap and a 1.15 strip, and these are those studs at 380px across. The controller rewrites the
	two vertical shares from the live config, so only the proportions inside each part are fixed here. ]]
local SIGN_W = 380
local SIGN_PANEL_H = 239
local SIGN_GAP_H = 12
local SIGN_CLOCK_H = 40
local SIGN_CLOCK_W = 236 -- `Bubble.Clock.Width` 0.62 of the sign

local SIGN_EDGE = 12
local SIGN_HEADER = { 8, 44 } -- top, bottom
local SIGN_MAIN_TOP = 52
local SIGN_SIDE = 12 -- inside Main

--- Main's five lines as { top, bottom } fractions of its height. The price is the loudest, as on the
--- screen; the rating is next because it is the one word that says whether to walk over.
local SIGN_BANDS = {
	{ "Car", 0.04, 0.2 },
	{ "Caption", 0.24, 0.34 },
	{ "Amount", 0.36, 0.65 },
	{ "Comparison", 0.68, 0.8 },
	{ "Rating", 0.84, 0.97 },
}

local SIGN_PLACEHOLDER = {
	Title = "HALT_CE WANTS TO BUY", -- BuyerConfig.Bubble.Named
	Car = "WHITE KAMARO",
	Caption = "OFFER", -- BuyerConfig.Bubble.Caption
	Amount = "$1,125",
	Comparison = "16% BELOW VALUE",
	Rating = "LOW OFFER",
	Time = "OFFER ENDS IN 0:42", -- BuyerConfig.Bubble.Clock
}

type Box = { x: number, y: number, w: number, h: number }

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
	local container = screen and screen:FindFirstChild("Container")
	if not container then
		return nil, string.format("%s holds no ScreenGui with a `Container` of frames.", node:GetFullName())
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

--- A child's box in its parent's pixels: centre and size, whatever its anchor.
local function boxOf(gui: GuiObject, pw: number, ph: number): Box
	local w = gui.Size.X.Scale * pw + gui.Size.X.Offset
	local h = gui.Size.Y.Scale * ph + gui.Size.Y.Offset
	local left = gui.Position.X.Scale * pw + gui.Position.X.Offset - gui.AnchorPoint.X * w
	local top = gui.Position.Y.Scale * ph + gui.Position.Y.Offset - gui.AnchorPoint.Y * h
	return { x = left + w / 2, y = top + h / 2, w = w, h = h }
end

--- Put a child at a box in its parent's pixels, written back as scale on a centre anchor (the kit's
--- own convention, and `ui-anchor-convention`'s).
local function setBox(gui: GuiObject, pw: number, ph: number, box: Box)
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui.Position = UDim2.fromScale(box.x / pw, box.y / ph)
	gui.Size = UDim2.fromScale(box.w / pw, box.h / ph)
end

--- A box from edges, which is how a layout reads down a panel.
local function edges(left: number, top: number, right: number, bottom: number): Box
	return { x = (left + right) / 2, y = (top + bottom) / 2, w = right - left, h = bottom - top }
end

--[[ A frame's own rim and corner after its SHORTER side went from `before` to `after` pixels. Both
	are fractions of that side, so dividing by the ratio keeps them at the artist's pixels. ]]
local function keepRim(frame: Instance, before: number, after: number)
	local ratio = before / after
	for _, child in frame:GetChildren() do
		if child:IsA("UIStroke") and child.StrokeSizingMode == Enum.StrokeSizingMode.ScaledSize then
			child.Thickness *= ratio
		elseif child:IsA("UICorner") then
			child.CornerRadius = UDim.new(child.CornerRadius.Scale * ratio, child.CornerRadius.Offset)
		end
	end
end

--[[ The checkered backing after the panel went from `oldW x oldH` to `newW x newH`. The pattern is a
	square image on `Fit`, sized in fractions of the panel; re-expressing those fractions against the
	new panel keeps the square, and so the cell size, exactly what the artist drew. The backing's own
	corner is a fraction of its shorter side like any other. ]]
local function keepChecker(panel: Instance, oldW: number, oldH: number, newW: number, newH: number)
	local bg = panel:FindFirstChild("BG")
	if not bg then
		return
	end
	keepRim(bg, math.min(oldW, oldH), math.min(newW, newH))
	for _, part in bg:GetChildren() do
		if part:IsA("GuiObject") then
			local size = part.Size
			part.Size = UDim2.fromScale(size.X.Scale * oldW / newW, size.Y.Scale * oldH / newH)
		end
	end
end

--- Cap a label's text at `fraction` of its box height, which is a 1080p pixel (see the header).
local function capTo(label: Instance, height: number, fraction: number)
	local cap = label:FindFirstChildOfClass("UITextSizeConstraint")
	if cap then
		cap.MaxTextSize = math.clamp(math.round(height * fraction), 1, 100)
	end
end

--- Non-breaking spaces, because `TextScaled` would sooner wrap a line than shrink it.
local function oneLine(text: string): string
	return (string.gsub(text, " ", "\u{00A0}"))
end

--- A gradient read at one point along it (`BuildCarDetailV2.Panel.rampAt`, for the same reason: the
--- panel's ramp has a stop in the middle, so its ends are not enough).
local function rampAt(gradient: UIGradient?, time: number): Color3?
	if not gradient then
		return nil
	end
	local stops = gradient.Color.Keypoints
	local at = math.clamp(time, 0, 1)
	for index = 1, #stops - 1 do
		local low, high = stops[index], stops[index + 1]
		if at <= high.Time then
			local span = high.Time - low.Time
			return low.Value:Lerp(high.Value, if span > 0 then (at - low.Time) / span else 0)
		end
	end
	return stops[#stops].Value
end

--[[ A kit button after its width went from `before` to `after` pixels at the same height. Its rim
	and corner are fractions of the height and do not move; the gloss does, because `BG.Slash` is
	sized in fractions of the WIDTH and a narrower face squeezes it (`kit-face-gloss-is-width-scaled`). ]]
local function rewidthButton(button: Instance, before: number, after: number)
	local bg = button:FindFirstChild("BG")
	local slash = bg and bg:FindFirstChild("Slash")
	if slash and slash:IsA("GuiObject") then
		slash.Size = UDim2.new(slash.Size.X.Scale * before / after, slash.Size.X.Offset, slash.Size.Y)
	end
end

local function setCaption(button: Instance, text: string)
	local title = button:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = oneLine(text)
	end
end

--- Strip every text cap under `root`: a world sign's text has to grow with the sign. See the header.
local function uncap(root: Instance)
	for _, item in root:GetDescendants() do
		if item:IsA("UITextSizeConstraint") then
			item:Destroy()
		end
	end
end

--[[ The kit frame's chassis at a new size: the clone with its header and body gone, rims and checker
	re-expressed for `w x h`. What is left is the blue ramp, both rims, the corner and the checker. ]]
local function chassis(kitFrame: GuiObject, kitW: number, kitH: number, w: number, h: number): GuiObject
	local frame = kitFrame:Clone() :: GuiObject
	frame.Visible = true
	local aspect = frame:FindFirstChildOfClass("UIAspectRatioConstraint")
	if aspect then
		aspect:Destroy()
	end
	keepRim(frame, math.min(kitW, kitH), math.min(w, h))
	keepChecker(frame, kitW, kitH, w, h)
	return frame
end

--[[ `Screens.BuyerSign`, the world billboard. See the header's last section. Returns the entry, or nil
	and why; the screen above has already been built either way. ]]
local function buildSign(container: Instance, kitFrame: GuiObject, money: UIGradient): (GuiObject?, string?)
	local kitW = kitFrame.Size.X.Scale * REF_W
	local aspect = kitFrame:FindFirstChildOfClass("UIAspectRatioConstraint")
	local kitH = kitW / (if aspect then aspect.AspectRatio else 2.29)

	local bar: Instance? = container
	for _, step in KIT_BAR do
		bar = bar and bar:FindFirstChild(step)
	end
	local kitMain = kitFrame:FindFirstChild("Main")
	local kitBody = kitMain and kitMain:FindFirstChild("Title")
	if not (bar and bar:IsA("GuiObject") and bar:FindFirstChild("Progress") and kitMain and kitMain:IsA("GuiObject") and kitBody) then
		return nil, string.format("the kit needs `%s` (with `Progress`) and `%s.Main.Title`", table.concat(KIT_BAR, "."), KIT_FRAME)
	end
	local kitMainBox = boxOf(kitMain, kitW, kitH)
	local signH = SIGN_PANEL_H + SIGN_GAP_H + SIGN_CLOCK_H

	local sign = Instance.new("Frame")
	sign.Name = SIGN_NAME
	sign.AnchorPoint = Vector2.new(0.5, 0.5)
	sign.Position = UDim2.fromScale(0.5, 0.5)
	sign.Size = UDim2.fromScale(1, 1)
	sign.BackgroundTransparency = 1
	sign.BorderSizePixel = 0

	-- === The panel ======================================================
	local panel = chassis(kitFrame, kitW, kitH, SIGN_W, SIGN_PANEL_H)
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.fromScale(0.5, 0)
	panel.Size = UDim2.fromScale(1, SIGN_PANEL_H / signH)
	panel.Parent = sign

	local header = panel:FindFirstChild("Header") :: GuiObject
	local close = header:FindFirstChild("CloseBtn")
	if close then
		close:Destroy()
	end
	local headerBox = edges(SIGN_EDGE, SIGN_HEADER[1], SIGN_W - SIGN_EDGE, SIGN_HEADER[2])
	setBox(header, SIGN_W, SIGN_PANEL_H, headerBox)
	local title = header:FindFirstChild("Title") :: TextLabel
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.Text = oneLine(SIGN_PLACEHOLDER.Title)
	setBox(title, headerBox.w, headerBox.h, edges(0, 0, headerBox.w, headerBox.h))

	local main = panel:FindFirstChild("Main") :: GuiObject
	for _, child in main:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local mainBox = edges(SIGN_EDGE, SIGN_MAIN_TOP, SIGN_W - SIGN_EDGE, SIGN_PANEL_H - SIGN_EDGE)
	setBox(main, SIGN_W, SIGN_PANEL_H, mainBox)
	keepRim(main, math.min(kitMainBox.w, kitMainBox.h), math.min(mainBox.w, mainBox.h))

	for _, band in SIGN_BANDS do
		local name, top, bottom = band[1], band[2] * mainBox.h, band[3] * mainBox.h
		local label = kitBody:Clone() :: TextLabel
		label.Name = name
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.TextScaled = true
		label.Text = oneLine(SIGN_PLACEHOLDER[name])
		setBox(label, mainBox.w, mainBox.h, edges(SIGN_SIDE, top, mainBox.w - SIGN_SIDE, bottom))
		label.Parent = main
		if name == "Amount" then
			local tint = money:Clone()
			tint.Name = "Tint"
			tint.Enabled = true
			tint.Parent = label
		end
	end

	-- === The countdown strip ============================================
	local strip = chassis(kitFrame, kitW, kitH, SIGN_CLOCK_W, SIGN_CLOCK_H)
	strip.Name = "Countdown"
	for _, child in strip:GetChildren() do
		if child.Name == "Header" or child.Name == "Main" then
			child:Destroy()
		end
	end
	strip.AnchorPoint = Vector2.new(0.5, 1)
	strip.Position = UDim2.fromScale(0.5, 1)
	strip.Size = UDim2.fromScale(SIGN_CLOCK_W / SIGN_W, SIGN_CLOCK_H / signH)
	strip.Parent = sign

	local time = title:Clone()
	time.Name = "Time"
	time.RichText = true
	time.Text = oneLine(SIGN_PLACEHOLDER.Time)
	time.ZIndex = 2
	setBox(time, SIGN_CLOCK_W, SIGN_CLOCK_H, edges(10, 3, SIGN_CLOCK_W - 10, 25))
	time.Parent = strip

	local track = bar:Clone() :: GuiObject
	track.Name = "Track"
	track.ZIndex = 2
	setBox(track, SIGN_CLOCK_W, SIGN_CLOCK_H, edges(16, 28, SIGN_CLOCK_W - 16, 34))
	local progress = track:FindFirstChild("Progress") :: GuiObject
	progress.AnchorPoint = Vector2.new(0, 0.5)
	progress.Position = UDim2.fromScale(0, 0.5)
	progress.Size = UDim2.fromScale(0.7, 1)
	track.Parent = strip

	uncap(sign)
	return sign, nil
end

return {
	Description = "Build StarterGui.MainUIV2.Screens.BuyerOffer (a buyer's offer on one of your cars) from the Cartoony Kit's PromptUI: widened into the car turning on the blue at the left and the offer, the market value, the percentage and the rating on the white body at the right, over ACCEPT and DECLINE. Also builds Screens.BuyerSign, the world billboard over the buyer, from the same frame. Rebuilds both shelf entries every run.",
	Tags = { "UI", "NewUI" },
	AutoRecordChanges = true,

	Arguments = {} :: Types.ArgumentType,

	Run = function(props: Types.Props, _arguments: Types.ArgumentResult)
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
		local money = gradientAt(container, MONEY_SOURCE)
		if not money then
			out:error(string.format("The kit has no money gradient at %s.", table.concat(MONEY_SOURCE, ".")))
			return
		end

		local panel = kitFrame:Clone() :: GuiObject
		panel.Name = ENTRY_NAME
		--- The kit ships every frame hidden. The shelf is what hides a template.
		panel.Visible = true

		local aspect = panel:FindFirstChildOfClass("UIAspectRatioConstraint")
		local header = panel:FindFirstChild("Header")
		local title = header and header:FindFirstChild("Title")
		local close = header and header:FindFirstChild("CloseBtn")
		local main = panel:FindFirstChild("Main")
		local body = main and main:FindFirstChild("Title")
		local btns = main and main:FindFirstChild("Btns")
		local accept = btns and btns:FindFirstChild("AcceptBtn")
		local decline = btns and btns:FindFirstChild("DeclineBtn")
		local rim = panel:FindFirstChildOfClass("UIGradient")
		if
			not (
				aspect
				and header
				and header:IsA("GuiObject")
				and title
				and title:IsA("TextLabel")
				and close
				and close:IsA("GuiObject")
				and main
				and main:IsA("GuiObject")
				and body
				and body:IsA("TextLabel")
				and btns
				and btns:IsA("GuiObject")
				and accept
				and accept:IsA("GuiObject")
				and decline
				and decline:IsA("GuiObject")
			)
		then
			out:error(
				string.format(
					"The kit's %s is not the shape this expects: it needs an aspect constraint, `Header.Title`, `Header.CloseBtn`, `Main.Title` and `Main.Btns.AcceptBtn` / `DeclineBtn`.",
					KIT_FRAME
				)
			)
			panel:Destroy()
			return
		end

		-- === Measure the kit before anything moves ==========================
		local kitW = panel.Size.X.Scale * REF_W
		local kitH = kitW / aspect.AspectRatio
		local headerBox = boxOf(header, kitW, kitH)
		local titleBox = boxOf(title, headerBox.w, headerBox.h)
		local closeBox = boxOf(close, headerBox.w, headerBox.h)
		local mainBox = boxOf(main, kitW, kitH)
		local btnsBox = boxOf(btns, mainBox.w, mainBox.h)
		local kitButtonW = accept.Size.X.Scale * btnsBox.w
		local bodyTop = mainBox.y - mainBox.h / 2
		local bodyBottomMargin = kitH - (mainBox.y + mainBox.h / 2)
		local buttonsBottomMargin = mainBox.h - (btnsBox.y + btnsBox.h / 2)

		-- === The panel ======================================================
		panel.Size = UDim2.fromScale(PANEL_W / REF_W, PANEL_H / REF_H)
		aspect.AspectRatio = PANEL_W / PANEL_H
		keepRim(panel, math.min(kitW, kitH), math.min(PANEL_W, PANEL_H))
		keepChecker(panel, kitW, kitH, PANEL_W, PANEL_H)

		-- === The header =====================================================
		local headerMargin = (kitW - headerBox.w) / 2
		local newHeader = { x = PANEL_W / 2, y = headerBox.y, w = PANEL_W - 2 * headerMargin, h = headerBox.h }
		setBox(header, PANEL_W, PANEL_H, newHeader)
		--- The title keeps its left edge and its height and takes more of the width.
		local titleLeft = titleBox.x - titleBox.w / 2
		local titleW = newHeader.w * TITLE_SHARE
		setBox(title, newHeader.w, newHeader.h, { x = titleLeft + titleW / 2, y = titleBox.y, w = titleW, h = titleBox.h })
		title.Text = oneLine(PLACEHOLDER.Title)
		--- The X keeps its size and its distance from the right edge.
		setBox(close, newHeader.w, newHeader.h, {
			x = newHeader.w - (headerBox.w - closeBox.x),
			y = closeBox.y,
			w = closeBox.w,
			h = closeBox.h,
		})

		-- === The two columns ================================================
		local columnsBottom = PANEL_H - bodyBottomMargin
		local showcaseBox = edges(EDGE, bodyTop, EDGE + SHOWCASE_W, columnsBottom)
		local newMain = edges(EDGE + SHOWCASE_W + GAP, bodyTop, PANEL_W - EDGE, columnsBottom)
		setBox(main, PANEL_W, PANEL_H, newMain)
		keepRim(main, math.min(mainBox.w, mainBox.h), math.min(newMain.w, newMain.h))

		local showcase = Instance.new("Frame")
		showcase.Name = "Showcase"
		showcase.BackgroundTransparency = 1
		showcase.BorderSizePixel = 0
		showcase.ZIndex = main.ZIndex
		setBox(showcase, PANEL_W, PANEL_H, showcaseBox)

		--- The car's name, in the header's own type, centred over the car.
		local carName = title:Clone()
		carName.Name = "CarName"
		carName.TextXAlignment = Enum.TextXAlignment.Center
		carName.ZIndex = showcase.ZIndex + 1
		carName.Text = oneLine(PLACEHOLDER.CarName)
		setBox(carName, showcaseBox.w, showcaseBox.h, edges(0, NAME_TOP, showcaseBox.w, NAME_TOP + NAME_H))
		capTo(carName, NAME_H, 1)
		carName.Parent = showcase

		--[[ The box the car turns in: nothing at all, a rectangle the car is framed to, as on the
			detail wings. It stays empty in the Explorer: `Modules/CarViewport` is the only thing that
			decides how a car is framed. `Backdrop` is the panel's own ramp read at the box's middle,
			the colour the car's one-pixel edge blends into (`CarViewport.new`). ]]
		local portraitTop = NAME_TOP + NAME_H + PORTRAIT_GAP
		local portraitBox = edges(0, portraitTop, showcaseBox.w, showcaseBox.h - PORTRAIT_BOTTOM)
		local portrait = Instance.new("Frame")
		portrait.Name = "Portrait"
		portrait.BackgroundTransparency = 1
		portrait.BorderSizePixel = 0
		portrait.ZIndex = showcase.ZIndex + 1
		setBox(portrait, showcaseBox.w, showcaseBox.h, portraitBox)
		local backdrop = rampAt(rim, (showcaseBox.y - showcaseBox.h / 2 + portraitBox.y) / PANEL_H)
		if backdrop then
			portrait:SetAttribute("Backdrop", backdrop)
		end
		--- The box's shape, so the controller frames the car without measuring a frame that has not
		--- been laid out yet (`CarViewport` header note 5).
		portrait:SetAttribute("Aspect", portraitBox.w / portraitBox.h)
		portrait.Parent = showcase

		showcase.Parent = panel

		-- === The body =======================================================
		local buttonsBox = {
			x = newMain.w / 2,
			y = newMain.h - buttonsBottomMargin - btnsBox.h / 2,
			w = newMain.w - 2 * BODY_SIDE,
			h = btnsBox.h,
		}
		local bandTop = BAND_PAD
		local bandBottom = buttonsBox.y - buttonsBox.h / 2 - BAND_PAD
		local bandHeight = bandBottom - bandTop

		local function line(name: string, text: string): TextLabel
			local band = BANDS[name]
			local top = bandTop + bandHeight * band[1]
			local bottom = bandTop + bandHeight * band[2]
			local label = body:Clone()
			label.Name = name
			label.TextXAlignment = Enum.TextXAlignment.Center
			label.TextYAlignment = Enum.TextYAlignment.Center
			--- Never `TextWrapped = false`: it switches `TextScaled` off with it. One line stays one
			--- line through non-breaking spaces in the text.
			label.TextScaled = true
			label.Text = oneLine(text)
			setBox(label, newMain.w, newMain.h, edges(BODY_SIDE, top, newMain.w - BODY_SIDE, bottom))
			capTo(label, bottom - top, 1)
			label.Parent = main
			return label
		end

		line("Offered", PLACEHOLDER.Offered)
		local price = line("Price", PLACEHOLDER.Price)
		local tint = (money :: UIGradient):Clone()
		tint.Name = "Tint"
		tint.Enabled = true
		tint.Parent = price
		line("Value", PLACEHOLDER.Value)
		line("Percent", PLACEHOLDER.Percent)
		line("Rating", PLACEHOLDER.Rating)
		body:Destroy()

		-- === The answers ====================================================
		setBox(btns, newMain.w, newMain.h, buttonsBox)
		local buttonW = (buttonsBox.w - BUTTON_GAP) / 2
		for order, button in { accept, decline } do
			button.LayoutOrder = order
			button.Size = UDim2.fromScale(buttonW / buttonsBox.w, 1)
			rewidthButton(button, kitButtonW, buttonW)
		end
		setCaption(accept, PLACEHOLDER.Accept)
		setCaption(decline, PLACEHOLDER.Decline)
		local layout = btns:FindFirstChildOfClass("UIListLayout")
		if layout then
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			layout.VerticalAlignment = Enum.VerticalAlignment.Center
			layout.Padding = UDim.new(BUTTON_GAP / buttonsBox.w, 0)
		end
		--- The kit paints the row behind the pair white, which only ever showed on a white body.
		btns.BackgroundTransparency = 1

		local existing = shelf:FindFirstChild(ENTRY_NAME)
		if existing then
			existing:Destroy()
		end
		panel.Parent = shelf

		out:print(string.format("Built %s.%s.%s from the kit's %s.", SCREEN_NAME, SHELF_NAME, ENTRY_NAME, KIT_FRAME))

		local oldSign = shelf:FindFirstChild(SIGN_NAME)
		if oldSign then
			oldSign:Destroy()
		end
		local sign, signWhy = buildSign(container, kitFrame, money :: UIGradient)
		if sign then
			sign.Parent = shelf
			out:print(string.format("Built %s.%s.%s, the world billboard, from the same frame.", SCREEN_NAME, SHELF_NAME, SIGN_NAME))
		else
			out:warn(string.format("No %s: %s. Buyers keep the code-drawn sign.", SIGN_NAME, tostring(signWhy)))
		end
		out:print(
			string.format(
				"%dx%d at 1080p: `Showcase` (%dpx, the car on the blue) beside `Main` (%dpx) with five lines and the answers.",
				PANEL_W,
				PANEL_H,
				SHOWCASE_W,
				math.round(newMain.w)
			)
		)

		pcall(function()
			props:SetSelection({ panel })
		end)
	end,
} :: Types.ScriptModule
