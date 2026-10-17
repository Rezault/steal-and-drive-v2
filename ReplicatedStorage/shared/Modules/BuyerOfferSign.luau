--[[
	BuyerOfferSign (client presentation)
	-----------------------------------
	The buyer's world card in the offer screen's arcade style, 2026-10-04. Built from native UI so
	streaming a buyer never waits for a screen template or an image upload. A small checker field
	belongs to the blue header; the price sits on white so it stays readable against any showroom.

	Only construction lives here. BuyerController owns arrival visibility, the server's offer,
	rating, countdown and destruction. No buttons: the existing proximity prompt opens the offer.

	`buildKit` (2026-10-06) is the new UI's sign: the Cartoony Kit's PromptUI, authored by
	`BuildBuyerOfferV2` as `MainUIV2.Screens.BuyerSign` and cloned here, so the sign and the offer
	screen it opens are the same frame. `build` below stays as the fallback for a place without it.

	`buildDesign` (2026-10-15) is the redesign off Dylan's reference, one of several designs on
	`Screens.BuyerSigns` (`BuildBuyerSignDesigns`) picked by `BuyerConfig.Bubble.Design`. It falls
	back to `buildKit`. The kerb seller's sign reads the same card off `Screens.SellerSigns`
	(`SellerConfig.Bubble.Design`), built by the same command.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)

local BuyerOfferSign = {}

local KIT_SHELF = "Screens"
local KIT_TEMPLATE = "BuyerSign"

--[[ The kit sign, cloned into `gui`, or nil when this place has no template (the caller then builds
	the arcade sign). Fills the same fields `build` does, plus `kit`, and `timeTint` for the clock. ]]
function BuyerOfferSign.buildKit(gui: BillboardGui, panelShare: number, clockShare: number)
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local root = playerGui and UIRoot.find(playerGui)
	local shelf = root and root:FindFirstChild(KIT_SHELF)
	local template = shelf and shelf:FindFirstChild(KIT_TEMPLATE)
	if not (template and template:IsA("GuiObject")) then
		return nil
	end

	local sign = template:Clone()
	local panel = sign:FindFirstChild("Panel")
	local header = panel and panel:FindFirstChild("Header")
	local main = panel and panel:FindFirstChild("Main")
	local strip = sign:FindFirstChild("Countdown")
	local track = strip and strip:FindFirstChild("Track")
	local fill = track and track:FindFirstChild("Progress")
	local fields = {
		who = header and header:FindFirstChild("Title"),
		body = main and main:FindFirstChild("Car"),
		caption = main and main:FindFirstChild("Caption"),
		price = main and main:FindFirstChild("Amount"),
		value = main and main:FindFirstChild("Comparison"),
		rating = main and main:FindFirstChild("Rating"),
	}
	for _, key in { "who", "body", "caption", "price", "value", "rating" } do
		local label = fields[key]
		if not (label and label:IsA("TextLabel")) then
			sign:Destroy()
			return nil
		end
	end
	if not (panel and panel:IsA("GuiObject") and strip and strip:IsA("GuiObject") and fill and fill:IsA("GuiObject")) then
		sign:Destroy()
		return nil
	end

	panel.Size = UDim2.fromScale(1, panelShare)
	local result = {
		who = fields.who,
		body = fields.body,
		caption = fields.caption,
		price = fields.price,
		value = fields.value,
		rating = fields.rating,
		arcade = true,
		kit = true,
	}
	if clockShare > 0 then
		strip.Size = UDim2.fromScale(strip.Size.X.Scale, clockShare)
		strip.Visible = false
		--- The fill's own ramp, kept so an urgent clock can swap it and put it back.
		local tint = fill:FindFirstChildOfClass("UIGradient")
		result.strip = strip
		result.clock = strip:FindFirstChild("Time")
		result.timeFill = fill
		result.timeTint = tint
		result.timeRamp = tint and tint.Color
	else
		strip:Destroy()
	end
	sign.Parent = gui
	return result
end

local DESIGN_SHELF = "BuyerSigns"

--[[ The redesigned sign (2026-10-15, `BuyerConfig.Bubble.Design`): design `key` from
	`Screens.BuyerSigns`, built by `BuildBuyerSignDesigns`, cloned into `gui`. Nil when the place has
	no such design, and the caller falls back to `buildKit`. The billboard is NOT sized here: the
	caller reads `aspect` and sizes it, because only it knows the studs. The clock is the card's own
	`Footer`, always showing.

	`folder` reads another shelf of the same cards: the seller's are `SellerSigns`. ]]
function BuyerOfferSign.buildDesign(gui: BillboardGui, key: string, folder: string?)
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local root = playerGui and UIRoot.find(playerGui)
	local shelf = root and root:FindFirstChild(KIT_SHELF)
	local designs = shelf and shelf:FindFirstChild(folder or DESIGN_SHELF)
	local template = designs and designs:FindFirstChild(key)
	local aspect = template and template:GetAttribute("Aspect")
	if not (template and template:IsA("GuiObject") and type(aspect) == "number") then
		return nil
	end

	local sign = template:Clone()
	local panel = sign:FindFirstChild("Panel")
	local main = panel and panel:FindFirstChild("Main")
	local seat = panel and panel:FindFirstChild("Seat")
	local pill = main and main:FindFirstChild("Pill")
	local holder = panel and panel:FindFirstChild("Footer")
	local track = holder and holder:FindFirstChild("Track")
	local fill = track and track:FindFirstChild("Progress")
	local result = {
		who = panel and panel:FindFirstChild("Buyer"),
		from = panel and panel:FindFirstChild("From"),
		face = seat and seat:FindFirstChild("Face"),
		body = main and main:FindFirstChild("Car"),
		price = main and main:FindFirstChild("Amount"),
		pill = pill,
		pillText = pill and pill:FindFirstChild("Text"),
		pillArrow = pill and pill:FindFirstChild("Arrow"),
		pillRim = pill and pill:FindFirstChildOfClass("UIStroke"),
		clock = holder and holder:FindFirstChild("Time"),
		timeFill = fill,
		arcade = true,
		kit = true,
		design = key,
		aspect = aspect,
	}
	for _, field in { "who", "from", "face", "body", "price", "pill", "pillText", "pillArrow", "clock", "timeFill" } do
		if result[field] == nil then
			sign:Destroy()
			return nil
		end
	end
	--- The rating badge, on the designs that have one, with every band's kit ramp kept beside it.
	local badge = panel:FindFirstChild("Badge")
	if badge then
		result.badge = badge
		result.badgeText = badge:FindFirstChild("Title")
		result.badgeTint = badge:FindFirstChildOfClass("UIGradient")
		result.badgeRamps = badge:FindFirstChild("Ramps")
	end
	local tint = fill:FindFirstChildOfClass("UIGradient")
	result.timeTint = tint
	result.timeRamp = tint and tint.Color
	sign.Parent = gui
	return result
end

local INK = Color3.fromRGB(5, 25, 43)
local WHITE = Color3.fromRGB(255, 255, 255)
local CYAN = Color3.fromRGB(82, 241, 255)

local function corner(parent: GuiObject, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(radius, 0)
	item.Parent = parent
end

local function stroke(parent: GuiObject, colour: Color3, thickness: number)
	local item = Instance.new("UIStroke")
	item.Color = colour
	item.Thickness = thickness
	item.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	item.Parent = parent
end

local function gradient(parent: GuiObject, top: Color3, bottom: Color3)
	local item = Instance.new("UIGradient")
	item.Rotation = 90
	item.Color = ColorSequence.new(top, bottom)
	item.Parent = parent
end

local function frame(parent: Instance, name: string, x: number, y: number, w: number, h: number,
	colour: Color3, z: number): Frame
	local item = Instance.new("Frame")
	item.Name = name
	item.Position = UDim2.fromScale(x, y)
	item.Size = UDim2.fromScale(w, h)
	item.BackgroundColor3 = colour
	item.BorderSizePixel = 0
	item.ZIndex = z
	item.Parent = parent
	return item
end

local function text(parent: Instance, name: string, x: number, y: number, w: number, h: number,
	colour: Color3): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.Position = UDim2.fromScale(x, y)
	item.Size = UDim2.fromScale(w, h)
	item.BackgroundTransparency = 1
	item.Font = Enum.Font.FredokaOne
	item.TextColor3 = colour
	item.TextWrapped = false
	-- Set scaling LAST: clearing wrapping after it can clear TextScaled too, leaving default-size
	-- lettering stranded in a large billboard. BuyerController supplies nonbreaking single lines.
	item.TextScaled = true
	item.Text = ""
	item.ZIndex = 5
	item.Parent = parent
	local outline = Instance.new("UIStroke")
	outline.Color = INK
	outline.Thickness = 2
	outline.Parent = item
	return item
end

function BuyerOfferSign.build(gui: BillboardGui, panelShare: number, clockShare: number)
	local shadow = frame(gui, "Shadow", 0.025, 0.018, 0.95, panelShare, INK, 1)
	shadow.BackgroundTransparency = 0.2
	corner(shadow, 0.065)
	local panel = frame(gui, "ArcadeCard", 0.02, 0, 0.96, panelShare, WHITE, 2)
	corner(panel, 0.065)
	stroke(panel, INK, 3)
	gradient(panel, Color3.fromRGB(33, 222, 255), Color3.fromRGB(12, 91, 235))
	local rim = frame(panel, "Rim", 0.012, 0.016, 0.976, 0.968, WHITE, 3)
	rim.BackgroundTransparency = 1
	corner(rim, 0.055)
	stroke(rim, CYAN, 1.5)

	-- Twenty translucent cells, built once per buyer. Keeping the pattern in the header avoids
	-- both an unreadable price background and a full-card grid of replicated-looking UI parts.
	for row = 0, 3 do
		for col = 0, 9 do
			if (row + col) % 2 == 0 then
				local cell = frame(panel, "Check", 0.035 + col * 0.093, 0.025 + row * 0.075,
					0.093, 0.075, WHITE, 3)
				cell.BackgroundTransparency = 0.9
			end
		end
	end
	local who = text(panel, "Buyer", 0.055, 0.035, 0.89, 0.105, WHITE)
	local body = text(panel, "Car", 0.05, 0.15, 0.9, 0.175, WHITE)
	local offer = frame(panel, "Offer", 0.06, 0.35, 0.88, 0.43, WHITE, 4)
	corner(offer, 0.08)
	stroke(offer, INK, 2)
	local caption = text(offer, "Caption", 0.06, 0.035, 0.88, 0.16, WHITE)
	local price = text(offer, "Amount", 0.045, 0.205, 0.91, 0.56, WHITE)
	gradient(price, Color3.fromRGB(197, 255, 0), Color3.fromRGB(49, 219, 0))
	local value = text(offer, "Comparison", 0.055, 0.79, 0.89, 0.14, WHITE)
	local badge = frame(panel, "DealBadge", 0.16, 0.825, 0.68, 0.125, WHITE, 4)
	corner(badge, 0.35)
	stroke(badge, INK, 2)
	gradient(badge, WHITE, Color3.fromRGB(181, 206, 211))
	local rating = text(badge, "Rating", 0.06, 0.06, 0.88, 0.86, WHITE)
	local sign = { who = who, body = body, caption = caption, price = price,
		value = value, rating = rating, badge = badge, arcade = true }
	if clockShare > 0 then
		local strip = frame(gui, "Countdown", 0.12, 1 - clockShare, 0.76, clockShare, INK, 2)
		corner(strip, 0.25)
		stroke(strip, CYAN, 1.5)
		local clock = text(strip, "Time", 0.045, 0.08, 0.91, 0.59, WHITE)
		clock.RichText = true
		local track = frame(strip, "Track", 0.065, 0.78, 0.87, 0.085, Color3.fromRGB(50, 72, 98), 3)
		corner(track, 0.5)
		local fill = frame(track, "Remaining", 0, 0, 1, 1, CYAN, 4)
		corner(fill, 0.5)
		strip.Visible = false
		sign.strip, sign.clock, sign.timeFill = strip, clock, fill
	end
	return sign
end

return BuyerOfferSign
