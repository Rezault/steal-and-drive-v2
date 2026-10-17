--[[
	BuyerController  (client)
	-------------------------
	Everything a player SEES of a buyer: the sign over their head and, for the owner, the offer screen.
	`BuyerService` decides the offer and `CustomerService` stands the rig; the rig carries the offer as
	attributes and a CollectionService tag, so every client draws every buyer on every lot with no
	remote at all. The screen is the one thing that needs one, because only the server knows what the
	car is worth to the dollar. Added 2026-09-28 with the dealership rework.

	=== THE SIGN MATCHES THE OFFER SCREEN — 2026-10-04 ========================================

	BuyerOfferSign builds the cyan/blue checker card, outlined type, white cash panel and deal
	badge. The clock has a remaining-time bar, updated only when its displayed second changes.
	The market's world size and visibility distances still apply, so the style does not make
	showrooms into larger walls of UI. BuyerConfig.Bubble.ArcadeStyle = false restores the sign
	described below. The server's offer and the modal's accept/decline flow are unchanged.

	=== AND THEN THE REDESIGN, 2026-10-15 =====================================================

	`BuyerConfig.Bubble.Design` picks one of the designs on `Screens.BuyerSigns` (`BuildBuyerSignDesigns`),
	drawn off a reference Dylan sent: face, name and rating badge in the header, the car, the price and
	a value pill on the white body, the clock as a footer that is always part of the card. Four were
	built for the boss and B was chosen. `_paintDesign` fills it and `rebuildSigns` rebuilds every sign
	live. The market's seller sign keeps the kit sign; only the buyer's moved.

	=== THE ORIGINAL SIGN IS THE MARKET'S SIGN, THE OTHER WAY ROUND ===========================

	A buyer is the plaza's seller reversed — somebody standing by a car with a price over their head
	and a clock under it — so the sign is built from the same `CarDealConfig.Bubble` numbers, the same
	kit panel art and the same clock line (`CarDealConfig.clockLineFor`) as the market stands. The
	rows say who wants it, which car, OFFER, the amount, and the rating word in the rating's colour
	where the market's sign has its hold-to-buy pill. Change the market's bubble and this one moves
	with it; that is the point of reading the same table rather than copying it.

	It is NOT the market's code, deliberately: `CarDealController`'s bubble is wired to stands, rotation
	and a hold prompt that a buyer has none of, and lifting it into a shared module would be a
	refactor of a working screen for one caller. If a third sign like this ever appears, that is the
	moment to extract it.

	=== THE SCREEN IS A PLACEHOLDER ===========================================================

	Built in code: a navy panel, the car turning in a viewport, the two numbers, the percentage, the
	rating, ACCEPT and DECLINE. No art pass has been done; every word is `BuyerConfig.Screen` and the
	colours are the kit's. It takes the server's word for the VALUE (so the rating is measured against
	what the sell lot would pay to the dollar) and sends back nothing but the car and yes/no.

	=== WITH THE NEW UI, THE SCREEN IS THE KIT'S (2026-09-30) ==================================

	With `UIRoot.isNewUI()` the placeholder is not built. `BuildBuyerOfferV2` authors the screen out
	of the Cartoony Kit's `PromptUI` (the sell prompt's frame) onto the hidden shelf
	`MainUIV2.Screens.BuyerOffer`, and `_buildKit` clones it into this file's own `BuyerOffer`
	ScreenGui at the same `DisplayOrder`. The car turns on the panel's blue at the left under its
	name; the white body at the right carries the same five lines and the two answers. The header
	says who is asking, off the offer's `name`, which the placeholder never showed.

	The answers are the placeholder's: ACCEPT sells, DECLINE turns the buyer away, and the X or a
	press on the dim closes the screen with the buyer still waiting. On a pad, A accepts and B is
	the X, NOT decline: B means "back" everywhere else in this game, and backing out of a screen
	should never cost a player the offer on it.

	If the template is missing, the placeholder is built instead and a warning names the command.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameplayFeedback = require(ReplicatedStorage.shared.Modules.GameplayFeedback)
local Shard = require(ReplicatedStorage.Packages.Shard)
local BuyerConfig = require(ReplicatedStorage.shared.Configs.BuyerConfig)
local CarDealConfig = require(ReplicatedStorage.shared.Configs.CarDealConfig)
local GamepadConfig = require(ReplicatedStorage.shared.Configs.GamepadConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local MarketValueConfig = require(ReplicatedStorage.shared.Configs.MarketValueConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)
local GamepadInput = require(ReplicatedStorage.shared.Modules.GamepadInput)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)
local BuyerOfferSign = require(ReplicatedStorage.shared.Modules.BuyerOfferSign)
--- A seller at the kerb opens this same screen (`openSeller`): their words and bands, a CONFIG.
local SellerConfig = require(ReplicatedStorage.shared.Configs.SellerConfig)

local BuyerController = Shard.new("BuyerController")

-- The tag and attribute names `CustomerService.placeBuyer` writes. Spelled here as well because a
-- client cannot require a server service; the two lists are one contract.
local BUYER_TAG = "Buyer"
local ATTR = {
	Owner = "BuyerOwner",
	CarId = "BuyerCarId",
	Amount = "BuyerOffer",
	ExpiresAt = "BuyerExpiresAt",
	Name = "BuyerName",
	Body = "BuyerBody",
	Arrived = "BuyerArrived",
	Kind = "BuyerKind",
	UserId = "BuyerUserId",
}

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)
local NAVY = Color3.fromRGB(40, 51, 75)
local MONEY = Color3.fromRGB(13, 180, 21)
local CAPTION = Color3.fromRGB(206, 214, 232)

--- Studs above the buyer's head the sign's bottom sits. The market's `HeadOffset`, for the same
--- reason: it has to clear a hat, not a flagpole.
local HEAD_CLEARANCE = CarDealConfig.Bubble.HeadOffset

local function label(parent: Instance, row, colour: Color3): TextLabel
	local text = Instance.new("TextLabel")
	text.AnchorPoint = Vector2.new(0.5, 0)
	text.Position = UDim2.fromScale(0.5, row.Y)
	text.Size = UDim2.fromScale(0.92, row.Height)
	text.BackgroundTransparency = 1
	text.FontFace = FONT
	text.TextColor3 = colour
	text.TextScaled = true
	text.Text = ""
	text.Parent = parent
	return text
end

-- === The sign ===============================================================

--[[ What one buyer is worth to the reader: the offer measured against the car's value. For the owner
	the value is priced with the car's condition and fitted parts off their own broadcasts
	(`MarketValueConfig.broadcastRecord`); for a visitor, off the
	owner's (attributes replicate for every player). A car whose owner has left prices as its model,
	which only moves the rating word, never the offer. ]]
local function ratingFor(model: Model)
	local carId = model:GetAttribute(ATTR.CarId)
	local amount = model:GetAttribute(ATTR.Amount)
	if type(carId) ~= "string" or type(amount) ~= "number" then
		return nil
	end
	local owner = Players:GetPlayerByUserId(model:GetAttribute(ATTR.Owner) or 0)
	local value = MarketValueConfig.valueOfId(carId, MarketValueConfig.broadcastRecord(owner, carId))
	return BuyerConfig.bandFor(amount, value), value
end

--- Build the sign over one buyer rig. Everything hangs off the rig, so it goes when the rig does.
function BuyerController._bind(self, model: Instance)
	if not model:IsA("Model") or self._signs[model] then
		return
	end
	local head = model:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end

	local cfg = CarDealConfig.Bubble
	local clock = cfg.Clock
	local total = cfg.Size.Y + (if clock.Enabled then clock.Gap + clock.Height else 0)
	local kitSign = BuyerConfig.Bubble.KitStyle and UIRoot.isNewUI()
	local sizeScale = if BuyerConfig.Bubble.ArcadeStyle or kitSign then BuyerConfig.Bubble.ArcadeScale else 1

	local gui = Instance.new("BillboardGui")
	gui.Name = "BuyerSign"
	gui.Adornee = head
	gui.Size = UDim2.fromScale(cfg.Size.X * sizeScale, total * sizeScale)
	-- Keep its bottom above the hat when shrinking; retaining the old centre would leave a gap.
	gui.StudsOffset = Vector3.new(0, head.Size.Y / 2 + total * sizeScale / 2 + HEAD_CLEARANCE, 0)
	gui.MaxDistance = BuyerConfig.Bubble.MaxDistance
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.AlwaysOnTop = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local panelShare, clockShare = cfg.Size.Y / total, if clock.Enabled then clock.Height / total else 0
	--[[ The redesign (`Bubble.Design`, 2026-10-15) first: it brings its own shape, so the billboard is
		re-sized to `DesignHeight` studs tall and as wide as the design's `Aspect` makes it, its bottom
		kept at the same clearance. ]]
	local design = BuyerConfig.Bubble.Design
	local sign = if kitSign and type(design) == "string" then BuyerOfferSign.buildDesign(gui, design) else nil
	if sign then
		local height = BuyerConfig.Bubble.DesignHeight
		local width = height * sign.aspect
		gui.Size = UDim2.fromScale(width, height)
		gui.StudsOffset = Vector3.new(0, head.Size.Y / 2 + height / 2 + HEAD_CLEARANCE, 0)
		sign.model, sign.head, sign.gui = model, head, gui
	end
	--- The kit's sign when the place has its template; nil falls through to the arcade one.
	if not sign and kitSign then
		sign = BuyerOfferSign.buildKit(gui, panelShare, clockShare)
	end
	if sign then
		sign.model, sign.head, sign.gui = model, head, gui
	elseif BuyerConfig.Bubble.ArcadeStyle then
		sign = BuyerOfferSign.build(gui, panelShare, clockShare)
		sign.model, sign.head, sign.gui = model, head, gui
	else

		--- The kit's page panel, drawn exactly as the market's sign draws it (`CarDealController._buildBubble`).
		local panel = Instance.new("ImageLabel")
		panel.Name = "Panel"
		panel.Size = UDim2.fromScale(1, cfg.Size.Y / total)
		panel.Image = UIAssets.url(UIAssets.Page.Panel)
		panel.ScaleType = Enum.ScaleType.Stretch
		panel.BackgroundColor3 = cfg.Colors.Face
		panel.BorderSizePixel = 0
		panel.Parent = gui

		local rows = cfg.Rows
		sign = {
			model = model,
			head = head,
			gui = gui,
			who = label(panel, rows.Seller, cfg.Colors.Caption),
			body = label(panel, rows.Body, Color3.new(1, 1, 1)),
			caption = label(panel, rows.PriceCaption, cfg.Colors.Caption),
			price = label(panel, rows.Price, cfg.Colors.Price),
			rating = label(panel, rows.Pill, Color3.new(1, 1, 1)),
			clock = nil :: TextLabel?,
			strip = nil :: Frame?,
			lastWhole = nil :: number?,
		}

		if clock.Enabled then
			local strip = Instance.new("Frame")
			strip.AnchorPoint = Vector2.new(0.5, 1)
			strip.Position = UDim2.fromScale(0.5, 1)
			strip.Size = UDim2.fromScale(clock.Width, clock.Height / total)
			strip.BackgroundColor3 = clock.PanelColor
			strip.BackgroundTransparency = clock.PanelTransparency
			strip.BorderSizePixel = 0
			strip.Visible = false
			strip.Parent = gui
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = strip
			local text = Instance.new("TextLabel")
			text.AnchorPoint = Vector2.new(0.5, 0.5)
			text.Position = UDim2.fromScale(0.5, 0.5)
			text.Size = UDim2.fromScale(0.86, 0.66)
			text.BackgroundTransparency = 1
			text.FontFace = FONT
			text.RichText = true
			text.TextColor3 = clock.CaptionColor
			text.TextScaled = true
			text.Parent = strip
			sign.strip = strip
			sign.clock = text
		end
	end

	--[[ HIDDEN UNTIL THE BUYER IS AT THE CAR (2026-09-28, `BuyerConfig.Stand.ClockOnArrival`). The
		offer does not exist for the player until then, so neither does the sign — a price and a
		ticking clock crossing the forecourt read as an offer that is already running out. Built now
		and only shown later, so arrival is a flip and not a build on the frame it matters. ]]
	local excited = false
	local function showIfArrived()
		gui.Enabled = model:GetAttribute(ATTR.Arrived) == true
		--- Where the SOLD! goes if this offer is taken (`_celebrate`): the rig is gone by the time the
		--- answer comes back, so the spot is kept from when they stood at the car.
		local carId = model:GetAttribute(ATTR.CarId)
		if gui.Enabled and type(carId) == "string" then
			self._soldAt[carId] = head.Position
		end
		--- Once, on the arrival, for the offers worth celebrating (`BuyerConfig.Excite`).
		if gui.Enabled and not excited then
			excited = true
			if model:GetAttribute(ATTR.Owner) == Players.LocalPlayer.UserId then GameplayFeedback.play("OfferArrived") end
			self:_excite(sign)
		end
	end
	showIfArrived()
	model:GetAttributeChangedSignal(ATTR.Arrived):Connect(showIfArrived)

	gui.Parent = model
	self._signs[model] = sign
	self:_paint(sign)

	--[[ The prompt is the owner's; everybody else is not offered a button the server would refuse.

		WATCHED FOR, not just looked up: a buyer who walks in only gets their prompt on arrival
		(`CustomerService.placeBuyer`, 2026-09-28), which is after this sign was built. The connection
		lives on the root and goes with the rig. ]]
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and model:GetAttribute(ATTR.Owner) ~= Players.LocalPlayer.UserId then
		local function hide(child: Instance)
			if child.Name == "BuyerPrompt" and child:IsA("ProximityPrompt") then
				child.Enabled = false
			end
		end
		for _, child in root:GetChildren() do
			hide(child)
		end
		root.ChildAdded:Connect(hide)
	end
end

--[[ The big offer's arrival (`BuyerConfig.Excite`): the sign breathes for as long as it stands, a
	burst of sparkles goes up off the buyer, and the owner hears it. A no-op for every ordinary offer.
	The breathing is a looping tween on the billboard's own size, which moves every sign style at
	once (kit, arcade, plain) without knowing how any of them is built; it dies with the rig. ]]
function BuyerController._excite(self, sign)
	local cfg = BuyerConfig.Excite
	if not cfg.Enabled then
		return
	end
	local model = sign.model
	local band = ratingFor(model)
	local kind = model:GetAttribute(ATTR.Kind)
	if not ((band and cfg.Bands[band.Key]) or (type(kind) == "string" and cfg.Kinds[kind])) then
		return
	end

	local gui = sign.gui
	local size = gui.Size
	TweenService:Create(
		gui,
		TweenInfo.new(cfg.PulseSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Size = UDim2.fromScale(size.X.Scale * cfg.Pulse, size.Y.Scale * cfg.Pulse) }
	):Play()

	local head = sign.head
	if head and head.Parent then
		local attachment = Instance.new("Attachment")
		attachment.Name = "BuyerExcite"
		attachment.Position = Vector3.new(0, head.Size.Y, 0)
		attachment.Parent = head
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(cfg.SparkleColor)
		emitter.LightEmission = 1
		emitter.LightInfluence = 0
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
		emitter.Lifetime = NumberRange.new(0.8, 1.4)
		emitter.Speed = NumberRange.new(8, 16)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Acceleration = Vector3.new(0, -10, 0)
		emitter.Drag = 2
		emitter.Rate = 0
		emitter.Parent = attachment
		emitter:Emit(cfg.Sparkles)
		task.delay(2, function()
			attachment:Destroy()
		end)
	end

	if model:GetAttribute(ATTR.Owner) == Players.LocalPlayer.UserId then
		local sounds = Shard.get("SoundController")
		if sounds then
			sounds:PlayNamed(cfg.Sound.Group, cfg.Sound.Name)
		end
	end
end

--[[ The SOLD moment (`BuyerConfig.Sold`), where the buyer of `carId` stood: a SOLD! stamp with the
	price that pops, floats up and fades; sparkles; the banknotes into the player; the sound. Only ever
	after the server's "sold", so it celebrates a sale that has already happened. ]]
function BuyerController._celebrate(self, carId: unknown, amount: unknown)
	local cfg = BuyerConfig.Sold
	local at = type(carId) == "string" and self._soldAt[carId]
	if type(carId) == "string" then
		self._soldAt[carId] = nil
	end
	if not (cfg.Enabled and at) then
		return
	end

	self:stamp(at, if type(amount) == "number" then "+" .. GarageConfig.formatCash(amount) else "")
	local burst = Shard.get("CashBurstController")
	if burst and type(amount) == "number" then
		burst:burst(amount, at)
	end
	local sounds = Shard.get("SoundController")
	if sounds then
		sounds:PlayNamed(cfg.Sound.Group, cfg.Sound.Name)
	end
end

--[[ PUBLIC: the SOLD! stamp, its line under it and the sparkles, floating up from `at` and gone in
	`BuyerConfig.Sold.Seconds`. Effect only, no cash and no sound: a buyer's sale adds those
	(`_celebrate`), and a seller's sale at the kerb (`SellerController`, 2026-10-15) shows the car's
	name instead of money coming in. ]]
function BuyerController.stamp(self, at: Vector3, line: string)
	local cfg = BuyerConfig.Sold
	if not cfg.Enabled then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = "SoldStamp"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new(at + Vector3.new(0, cfg.Above, 0))
	anchor.Parent = workspace

	local gui = Instance.new("BillboardGui")
	gui.MaxDistance = BuyerConfig.Bubble.MaxDistance
	gui.Size = UDim2.fromScale(cfg.Width, cfg.Height)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	gui.Parent = anchor
	local stamp = Instance.new("TextLabel")
	stamp.Size = UDim2.fromScale(1, 0.62)
	stamp.BackgroundTransparency = 1
	stamp.FontFace = Font.new("rbxasset://fonts/families/LuckiestGuy.json")
	stamp.Text = cfg.Text
	stamp.TextColor3 = cfg.Color
	stamp.TextScaled = true
	stamp.TextStrokeTransparency = 0
	stamp.Rotation = -8
	stamp.Parent = gui
	local price = Instance.new("TextLabel")
	price.Position = UDim2.fromScale(0, 0.62)
	price.Size = UDim2.fromScale(1, 0.38)
	price.BackgroundTransparency = 1
	price.FontFace = FONT
	price.Text = line
	price.TextColor3 = Color3.new(1, 1, 1)
	price.TextScaled = true
	price.TextStrokeTransparency = 0
	price.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = stamp

	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local float = TweenInfo.new(cfg.Seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(anchor, float, { CFrame = anchor.CFrame + Vector3.new(0, cfg.Rise, 0) }):Play()
	local fade = TweenInfo.new(cfg.Seconds * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, cfg.Seconds * 0.6)
	for _, label in { stamp, price } do
		TweenService:Create(label, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end

	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(cfg.Color, BuyerConfig.Excite.SparkleColor)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.8, 1.5)
	emitter.Speed = NumberRange.new(10, 22)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -12, 0)
	emitter.Drag = 2
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(cfg.Sparkles)
	task.delay(cfg.Seconds + 0.3, function()
		anchor:Destroy()
	end)
end

--[[ The turned-down buyer (`BuyerConfig.Declined`): the owner hears them huff. The rest is the server's,
	because the rig is: the face over their head and the walk out are `CustomerService.sendBuyerAway`,
	and the sign has already come down with the tag. Only ever after the server's "declined". ]]
function BuyerController._declined(self, carId: unknown)
	if type(carId) == "string" then
		self._soldAt[carId] = nil
	end
	local cfg = BuyerConfig.Declined
	if not cfg.Enabled then
		return
	end
	local sounds = Shard.get("SoundController")
	if sounds then
		sounds:PlayNamed(cfg.Sound.Group, cfg.Sound.Name)
	end
end

--[[ PUBLIC: every sign torn down and built again, so a `Bubble.Design` change shows at once (the
	side-by-side for the boss, 2026-10-15). The buyers themselves are untouched. ]]
function BuyerController.rebuildSigns(self)
	local models = {}
	for model in self._signs do
		table.insert(models, model)
	end
	for _, model in models do
		self:_unbind(model)
	end
	for _, model in CollectionService:GetTagged(BUYER_TAG) do
		self:_bind(model)
	end
end

function BuyerController._unbind(self, model: Instance)
	local sign = self._signs[model]
	if sign then
		self._signs[model] = nil
		sign.gui:Destroy()
	end
end

--[[ `_paint` for the redesign (`BuyerOfferSign.buildDesign`). The header is the buyer: their real face
	when a friend's account stands behind the rig (`BuyerUserId`), the kit silhouette otherwise, and
	OFFER FROM over the name (a kind's title in its place, in gold). The pill is the DIRECTION, red and
	down under value, green and up over it; the rating word lives on the designs with a badge. ]]
function BuyerController._paintDesign(self, sign)
	local model = sign.model
	local text = BuyerConfig.Bubble

	local userId = model:GetAttribute(ATTR.UserId)
	if type(userId) == "number" and userId > 0 then
		sign.face.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
	end
	local name = model:GetAttribute(ATTR.Name)
	sign.who.Text = CarDealConfig.oneLine(if type(name) == "string" and name ~= "" then string.upper(name) else text.AnonymousName)
	local kind = BuyerConfig.kindOf(model:GetAttribute(ATTR.Kind))
	sign.from.Text = CarDealConfig.oneLine(if kind and kind.Title then kind.Title else text.From)
	sign.from.TextColor3 = if kind and kind.Title then text.KindInk else Color3.new(1, 1, 1)

	local body, paint = GarageConfig.parseCarKey(model:GetAttribute(ATTR.CarId))
	sign.body.Text = if body then CarDealConfig.oneLine(string.upper(GarageConfig.carName(body, paint))) else ""
	local amount = model:GetAttribute(ATTR.Amount)
	sign.price.Text = if type(amount) == "number" then GarageConfig.formatCash(amount) else ""

	local band, value = ratingFor(model)
	local percent = if type(amount) == "number" and type(value) == "number" and value > 0
		then math.round((amount / value - 1) * 100)
		else 0
	local look = if percent < 0 then text.Pill.Below elseif percent > 0 then text.Pill.Above else text.Pill.At
	sign.pill.BackgroundColor3 = look.Fill
	if sign.pillRim then
		sign.pillRim.Color = look.Rim
	end
	sign.pillText.TextColor3 = look.Ink
	sign.pillText.Text = CarDealConfig.oneLine(if percent < 0 then string.format(text.Below, -percent)
		elseif percent > 0 then string.format(text.Above, percent)
		else text.AtValue)
	sign.pillArrow.Visible = look.Arrow ~= nil
	if look.Arrow then
		sign.pillArrow.ImageColor3 = look.Arrow
		--- The art points down; over value it turns to point up.
		sign.pillArrow.Rotation = if percent > 0 then 180 else 0
	end

	if sign.badge then
		sign.badgeText.Text = if band then CarDealConfig.oneLine(band.Label) else ""
		sign.badge.Visible = band ~= nil
		local ramp = band and sign.badgeRamps and sign.badgeRamps:FindFirstChild(band.Key)
		if ramp and sign.badgeTint then
			sign.badgeTint.Color = ramp.Color
		end
	end
end

--- Everything on the sign that is not the clock. Written once per bind; the attributes do not move
--- for the life of a rig (a new offer is a new rig).
function BuyerController._paint(self, sign)
	if sign.design then
		self:_paintDesign(sign)
		return
	end
	local model = sign.model
	local name = model:GetAttribute(ATTR.Name)
	local text = BuyerConfig.Bubble
	--- Who they are first (`BuyerConfig.Kinds`), so the sign is readable from across the lot.
	local kind = BuyerConfig.kindOf(model:GetAttribute(ATTR.Kind))
	local named = type(name) == "string" and name ~= ""
	sign.who.Text = CarDealConfig.oneLine(
		if kind and kind.Title
			then (if named then string.format(text.NamedKind, kind.Title, string.upper(name)) else string.format(text.AnonymousKind, kind.Title))
			elseif named then string.format(text.Named, string.upper(name))
			else text.Anonymous
	)

	local carId = model:GetAttribute(ATTR.CarId)
	local body, paint = GarageConfig.parseCarKey(carId)
	if body then
		local _, colour = CarRarity.labelOf(body)
		sign.body.Text = CarDealConfig.oneLine(string.upper(GarageConfig.carName(body, paint)))
		sign.body.TextColor3 = if sign.arcade then Color3.new(1, 1, 1) else colour
	end
	sign.caption.Text = CarDealConfig.oneLine(text.Caption)
	local amount = model:GetAttribute(ATTR.Amount)
	sign.price.Text = if type(amount) == "number" then GarageConfig.formatCash(amount) else ""

	local band, value = ratingFor(model)
	sign.rating.Text = if band then CarDealConfig.oneLine(band.Label) else ""
	--- The kit sign colours the word, as the offer screen does; the arcade one put it on a badge.
	sign.rating.TextColor3 = if sign.arcade and not sign.kit then Color3.new(1, 1, 1) else (if band then band.Color else CAPTION)
	if sign.badge then
		sign.badge.BackgroundColor3 = if band then band.Color else CAPTION
	end
	if sign.value then
		if type(amount) == "number" and type(value) == "number" and value > 0 then
			local percent = math.round((amount / value - 1) * 100)
			sign.value.Text = if percent == 0 then "AT MARKET VALUE"
				else string.format("%d%% %s VALUE", math.abs(percent), if percent > 0 then "ABOVE" else "BELOW")
		else
			sign.value.Text = ""
		end
	end
end

--[[ The clock strips, once a frame and rewritten on the second. Shown only near the sign
	(`Bubble.Clock.NearDistance`), measured from the character like the market's, for the market's
	reason: a deadline is for somebody walking up to the car, not a skyline of ticking signs. ]]
function BuyerController._stepClocks(self)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local origin = if root and root:IsA("BasePart") then root.Position else nil
	local near = CarDealConfig.Bubble.Clock.NearDistance
	local now = workspace:GetServerTimeNow()

	for _, sign in self._signs do
		local strip, clock = sign.strip, sign.clock
		--- A redesign's footer is part of the card and always shows; only a strip comes and goes.
		if not (clock and (strip or sign.design)) then
			continue
		end
		local expires = sign.model:GetAttribute(ATTR.ExpiresAt)
		local visible = sign.gui.Enabled and type(expires) == "number"
		if strip then
			visible = visible and origin ~= nil and (sign.head.Position - origin).Magnitude <= near
			strip.Visible = visible
		end
		if not visible then
			continue
		end
		local remaining = math.max(0, expires - now)
		local whole = math.ceil(remaining)
		if whole ~= sign.lastWhole then
			sign.lastWhole = whole
			if sign.design then
				clock.Text = CarDealConfig.clockLineFor(BuyerConfig.Bubble.Expires, remaining)
			else
				clock.Text = CarDealConfig.clockLineFor(BuyerConfig.Bubble.Clock, remaining)
			end
			if sign.timeFill then
				-- Updated with the clock, not a new tween every render frame. The lifetime is the
				-- server's configured offer window, so late-streamed buyers show an honest remainder.
				sign.timeFill.Size = UDim2.fromScale(math.clamp(remaining / BuyerConfig.Lifetime, 0, 1), 1)
				local urgent = remaining <= CarDealConfig.Bubble.Clock.UrgentSeconds
				if sign.timeTint then
					--- The kit fill is white under a ramp, and a ramp multiplies, so the ramp is what swaps.
					local hot = CarDealConfig.Bubble.Clock.UrgentColor
					sign.timeTint.Color = if urgent then ColorSequence.new(hot:Lerp(Color3.new(1, 1, 1), 0.35), hot) else sign.timeRamp
				else
					sign.timeFill.BackgroundColor3 = if urgent then CarDealConfig.Bubble.Clock.UrgentColor else Color3.fromRGB(82, 241, 255)
				end
			end
		end
	end
end

-- === The offer screen =======================================================

--- Build the screen once, hidden. Placeholder layout in scale, so it holds on a phone.
function BuyerController._buildScreen(self)
	--- The new UI's screen, when there is one to clone. A missing template falls through to the
	--- placeholder below rather than leaving an offer with no screen.
	if UIRoot.isNewUI() and self:_buildKit() then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "BuyerOffer"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui.Enabled = false

	local shade = Instance.new("Frame")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.45
	shade.BorderSizePixel = 0
	shade.Parent = gui

	local panel = Instance.new("ImageLabel")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.42, 0.62)
	panel.Image = UIAssets.url(UIAssets.Page.Panel)
	panel.ScaleType = Enum.ScaleType.Stretch
	panel.BackgroundColor3 = NAVY
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.1
	aspect.Parent = panel

	local function text(y: number, h: number, colour: Color3): TextLabel
		local t = label(panel, { Y = y, Height = h }, colour)
		return t
	end

	local screen = {
		gui = gui,
		title = text(0.04, 0.08, Color3.new(1, 1, 1)),
		view = CarViewport.new(panel, "Car"),
		offeredCaption = text(0.5, 0.05, CAPTION),
		offered = text(0.555, 0.1, MONEY),
		value = text(0.67, 0.055, CAPTION),
		percent = text(0.73, 0.05, CAPTION),
		rating = text(0.79, 0.06, Color3.new(1, 1, 1)),
		carId = nil :: string?,
	}
	screen.view.AnchorPoint = Vector2.new(0.5, 0)
	screen.view.Position = UDim2.fromScale(0.5, 0.13)
	screen.view.Size = UDim2.fromScale(0.8, 0.35)

	local function button(x: number, word: string, colour: Color3, accept: boolean)
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(0.5, 0)
		b.Position = UDim2.fromScale(x, 0.87)
		b.Size = UDim2.fromScale(0.4, 0.09)
		b.BackgroundColor3 = colour
		b.BorderSizePixel = 0
		b.FontFace = FONT
		b.Text = word
		b.TextColor3 = Color3.new(1, 1, 1)
		b.TextScaled = true
		b.AutoButtonColor = true
		b.Parent = panel
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.3, 0)
		corner.Parent = b
		b.Activated:Connect(function()
			self:_answer(accept)
		end)
		return b
	end
	screen.accept = button(0.27, BuyerConfig.Screen.Accept, MONEY, true)
	screen.decline = button(0.73, BuyerConfig.Screen.Decline, Color3.fromRGB(196, 44, 44), false)

	--- Pressing the shade outside the panel closes the screen without answering: the buyer keeps
	--- waiting, which is what walking away from someone mid-conversation does.
	local close = Instance.new("TextButton")
	close.Size = UDim2.fromScale(1, 1)
	close.BackgroundTransparency = 1
	close.Text = ""
	close.ZIndex = 0
	close.Parent = shade
	close.Activated:Connect(function()
		self:_close()
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self._screen = screen
end

-- === The kit screen (new UI) ================================================
--[[ Every name here is one `BuildBuyerOfferV2` writes; its header says what each was cut from. ]]

local KIT_SHELF = "Screens"
local KIT_TEMPLATE = "BuyerOffer"
--- How long each step of the path to the template is waited for; only ever the backstop for a
--- place without it, since the screen is built at start.
local KIT_WAIT = 5

--- The pop every V2 page opens and closes with, and the sell prompt's dim.
local KIT_START_SCALE = 0.9
local KIT_OPEN = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local KIT_CLOSE = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SCRIM_REST = 0.45
local SCRIM_TIME = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--- A and B while the screen is up. See the header for why B is the X and not DECLINE.
local PAD_ACCEPT = "BuyerOfferAccept"
local PAD_DECLINE = "BuyerOfferDecline"
local PAD_CLOSE = "BuyerOfferClose"
--- The badges hang on each button's top left corner, the sell prompt's placement on kit buttons.
local PAD_BADGE_POS = UDim2.fromScale(0, 0)
local PAD_BADGE_ANCHOR = Vector2.new(0.3, 0.3)

--[[ The new UI's screen: the authored template, cloned into a ScreenGui of this file's own.

	RETURNS WHETHER IT BUILT; false has already been said out loud, and `_buildScreen` draws the
	placeholder. The fields are the placeholder's where the placeholder has one, so `_answer` and
	`OfferResolved` read one `screen` whichever was built. ]]
function BuyerController._buildKit(self): boolean
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", KIT_WAIT)
	local root = playerGui and UIRoot.wait(playerGui :: PlayerGui, KIT_WAIT)
	local shelf = root and root:WaitForChild(KIT_SHELF, KIT_WAIT)
	local template = shelf and shelf:WaitForChild(KIT_TEMPLATE, KIT_WAIT)
	if not (template and template:IsA("GuiObject")) then
		warn(string.format("[BuyerController] No MainUIV2.%s.%s after %ds; drawing the placeholder. Run BuildBuyerOfferV2.", KIT_SHELF, KIT_TEMPLATE, KIT_WAIT))
		return false
	end

	local panel = template:Clone() :: GuiObject
	--- The kit's text caps are pixels for a 1080-tall screen; this keeps them in proportion above it.
	require(script.Parent.UIController.KitPage).scaleTextCaps(panel)

	local header = panel:FindFirstChild("Header")
	local title = header and header:FindFirstChild("Title")
	local close = header and header:FindFirstChild("CloseBtn")
	local showcase = panel:FindFirstChild("Showcase")
	local carName = showcase and showcase:FindFirstChild("CarName")
	local portrait = showcase and showcase:FindFirstChild("Portrait")
	local main = panel:FindFirstChild("Main")
	local offered = main and main:FindFirstChild("Offered")
	local price = main and main:FindFirstChild("Price")
	local value = main and main:FindFirstChild("Value")
	local percent = main and main:FindFirstChild("Percent")
	local rating = main and main:FindFirstChild("Rating")
	local btns = main and main:FindFirstChild("Btns")
	local accept = btns and btns:FindFirstChild("AcceptBtn")
	local decline = btns and btns:FindFirstChild("DeclineBtn")
	if
		not (
			title
			and close
			and close:IsA("GuiButton")
			and carName
			and portrait
			and portrait:IsA("GuiObject")
			and offered
			and price
			and value
			and percent
			and rating
			and accept
			and accept:IsA("GuiButton")
			and decline
			and decline:IsA("GuiButton")
		)
	then
		warn("[BuyerController] MainUIV2.Screens.BuyerOffer is missing a part; drawing the placeholder. Re-run BuildBuyerOfferV2.")
		panel:Destroy()
		return false
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "BuyerOffer"
	gui.ResetOnSpawn = false
	--- The placeholder's inset and order: the dim covers the topbar and the panel centres on the whole
	--- screen, as every modal on the shelf does.
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	--- Pressing the dim outside the panel closes the screen without answering, the placeholder's rule.
	local scrim = Instance.new("TextButton")
	scrim.Name = "Scrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = Color3.new(0, 0, 0)
	scrim.BackgroundTransparency = 1
	scrim.BorderSizePixel = 0
	scrim.Text = ""
	scrim.AutoButtonColor = false
	scrim.Selectable = false
	scrim.Parent = gui
	scrim.Activated:Connect(function()
		self:_close()
	end)

	panel.Visible = false
	panel.Parent = scrim
	--[[ A press on the panel that lands on nothing pressable must not reach the dim and close the
		screen. `Active` on the panel does NOT stop it (measured 2026-09-30: a click on the white body
		closed the offer), so the panel carries a button of its own under everything else, which takes
		the press and does nothing with it. ]]
	local catcher = Instance.new("TextButton")
	catcher.Name = "Catcher"
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.BackgroundTransparency = 1
	catcher.Text = ""
	catcher.AutoButtonColor = false
	catcher.Selectable = false
	catcher.ZIndex = 0
	catcher.Parent = panel
	local pop = Instance.new("UIScale")
	pop.Name = "PopScale"
	pop.Scale = KIT_START_SCALE
	pop.Parent = panel

	local backdrop = portrait:GetAttribute("Backdrop")
	local aspect = portrait:GetAttribute("Aspect")
	local view = CarViewport.new(portrait, "Car", if typeof(backdrop) == "Color3" then backdrop else nil)
	view.Size = UDim2.fromScale(1, 1)
	view.ZIndex = portrait.ZIndex

	self._kit = true
	self._screen = {
		gui = gui,
		scrim = scrim,
		panel = panel,
		pop = pop,
		title = title,
		close = close,
		carName = carName,
		view = view,
		aspect = if type(aspect) == "number" then aspect else 1.3,
		spin = nil :: CarViewport.Spin?,
		offeredCaption = offered,
		offered = price,
		value = value,
		percent = percent,
		rating = rating,
		accept = accept,
		decline = decline,
		carId = nil :: string?,
		open = false,
		token = 0,
	}

	close.Activated:Connect(function()
		self:_close()
	end)
	accept.Activated:Connect(function()
		self:_answer(true)
	end)
	decline.Activated:Connect(function()
		self:_answer(false)
	end)

	gui.Parent = playerGui
	return true
end

--[[ What the screen says for one offer. A buyer's reads `BuyerConfig`; one with `offer.seller` is a
	seller at the kerb (2026-10-15, `openSeller`), the same screen read the other way round: who is
	selling, PRICE, the usual price, how far under it, the seller's own rating bands and BUY.
	`offer.value` is the number the rating is measured against either way (market value for a
	buyer, the usual price for a seller). Pure. ]]
local function wordsFor(offer): { [string]: any }
	local amount = tonumber(offer.amount) or 0
	local value = tonumber(offer.value) or 0
	local named = type(offer.name) == "string" and offer.name ~= ""
	if offer.seller then
		local text = SellerConfig.Text
		return {
			title = if named then string.format(text.Named, string.upper(offer.name)) else text.Anonymous,
			caption = text.Caption,
			value = string.format("%s %s", text.UsualLabel, GarageConfig.formatCash(value)),
			percent = SellerConfig.compareText(amount, value),
			band = SellerConfig.bandFor(amount, value),
			accept = text.Buy,
		}
	end
	local words = BuyerConfig.Screen
	return {
		title = if named then string.format(words.From, string.upper(offer.name)) else words.FromAnonymous,
		caption = words.Offered,
		value = string.format("%s %s", words.Value, GarageConfig.formatCash(value)),
		percent = BuyerConfig.percentText(amount, value),
		band = BuyerConfig.bandFor(amount, value),
		accept = words.Accept,
	}
end

--- The accept button's word: the kit button's `Title`, or the placeholder button's own text.
local function setAcceptWord(button: GuiObject, word: string)
	local label = button:FindFirstChild("Title") or button
	if label:IsA("TextLabel") or label:IsA("TextButton") then
		label.Text = CarDealConfig.oneLine(word)
	end
end

--- Draw one offer onto the kit screen and bring it up. See `_open` for where the numbers come from.
function BuyerController._openKit(self, offer)
	local screen = self._screen
	local amount = tonumber(offer.amount) or 0
	local body = offer.body
	local paint = tonumber(offer.paint)
	local said = wordsFor(offer)
	local oneLine = CarDealConfig.oneLine

	screen.title.Text = oneLine(said.title)
	screen.carName.Text = oneLine(if type(body) == "string" then string.upper(GarageConfig.carName(body, offer.paint)) else "")
	screen.offeredCaption.Text = oneLine(said.caption)
	screen.offered.Text = GarageConfig.formatCash(amount)
	screen.value.Text = oneLine(said.value)
	screen.percent.Text = oneLine(said.percent)
	screen.rating.Text = oneLine(said.band.Label)
	screen.rating.TextColor3 = said.band.Color
	setAcceptWord(screen.accept, said.accept)

	--- A different car (or the first) goes into the box and starts turning; the same car keeps turning.
	if screen.carId ~= offer.carId or not screen.spin then
		if screen.spin then
			screen.spin.stop()
			screen.spin = nil
		end
		if type(body) == "string" and CarViewport.set(screen.view, body, { paint = paint, aspect = screen.aspect }) then
			screen.spin = CarViewport.spin(screen.view, { aspect = screen.aspect })
		else
			CarViewport.clear(screen.view)
		end
	end
	screen.carId = offer.carId

	if screen.open then
		return
	end
	screen.open = true
	screen.token += 1
	screen.gui.Enabled = true
	screen.panel.Visible = true
	screen.pop.Scale = KIT_START_SCALE
	TweenService:Create(screen.pop, KIT_OPEN, { Scale = 1 }):Play()
	TweenService:Create(screen.scrim, SCRIM_TIME, { BackgroundTransparency = SCRIM_REST }):Play()

	--- The HUD's own navigation stands down while this is up (`GamepadConfig.ModalAttribute`).
	GamepadInput.setModal("BuyerController", true)
	GamepadInput.bind({
		actionName = PAD_ACCEPT,
		keyCode = Enum.KeyCode.ButtonA,
		callback = function()
			self:_answer(true)
		end,
		parent = screen.accept,
		iconPosition = PAD_BADGE_POS,
		iconAnchor = PAD_BADGE_ANCHOR,
	})
	--[[ DECLINE ON Y (2026-10-15). It had no key at all, and B only closes the screen, so a pad player
		could not turn an offer down: the buyer stood there until the offer ran out, and the tutorial's
		sell beat ("either answer finishes it") could only be finished by selling. Not X, though X is
		the usual second answer: the buyer's own See Offer prompt is still up on X right beside them,
		and a prompt in range takes its key ahead of any binding of ours. ]]
	GamepadInput.bind({
		actionName = PAD_DECLINE,
		keyCode = Enum.KeyCode.ButtonY,
		callback = function()
			self:_answer(false)
		end,
		parent = screen.decline,
		iconPosition = PAD_BADGE_POS,
		iconAnchor = PAD_BADGE_ANCHOR,
	})
	GamepadInput.bind({
		actionName = PAD_CLOSE,
		keyCode = Enum.KeyCode.ButtonB,
		callback = function()
			self:_close()
		end,
		parent = screen.close,
	})
end

--- Take the kit screen down, and put the car away once it is out of sight.
function BuyerController._closeKit(self)
	local screen = self._screen
	screen.carId = nil
	if not screen.open then
		return
	end
	screen.open = false
	screen.token += 1
	local token = screen.token

	GamepadInput.unbind(PAD_ACCEPT)
	GamepadInput.unbind(PAD_DECLINE)
	GamepadInput.unbind(PAD_CLOSE)
	GamepadInput.setModal("BuyerController", false)

	TweenService:Create(screen.pop, KIT_CLOSE, { Scale = KIT_START_SCALE }):Play()
	local fade = TweenService:Create(screen.scrim, SCRIM_TIME, { BackgroundTransparency = 1 })
	fade:Play()
	fade.Completed:Once(function()
		--- Fenced, so the tail of a close never shuts a screen that has been opened again since.
		if screen.token ~= token then
			return
		end
		screen.gui.Enabled = false
		screen.panel.Visible = false
		if screen.spin then
			screen.spin.stop()
			screen.spin = nil
		end
		CarViewport.clear(screen.view)
	end)
end

--[[ The server's `OfferOpen`: draw it. The rating and the percentage are worked out here from the
	server's VALUE with `BuyerConfig`'s own bands, so this screen and the sign over the buyer agree
	(both read `bandFor`) and neither invents a threshold. ]]
function BuyerController._open(self, offer: unknown)
	local screen = self._screen
	if not screen or type(offer) ~= "table" then
		return
	end
	--- Only `openSeller` sets an answer callback, so a buyer's offer opening clears any seller's.
	if not offer.seller then
		screen.onAnswer = nil
	end
	if self._kit then
		self:_openKit(offer)
		return
	end
	local amount = tonumber(offer.amount) or 0
	local body = offer.body
	local said = wordsFor(offer)
	local words = BuyerConfig.Screen

	screen.carId = offer.carId
	screen.title.Text = CarDealConfig.oneLine(if offer.seller
		then said.title
		else string.format(
			words.Title,
			if type(body) == "string" then string.upper(GarageConfig.carName(body, offer.paint)) else "CAR"
		))
	screen.offeredCaption.Text = CarDealConfig.oneLine(said.caption)
	screen.offered.Text = GarageConfig.formatCash(amount)
	screen.value.Text = CarDealConfig.oneLine(said.value)
	screen.percent.Text = CarDealConfig.oneLine(said.percent)
	screen.rating.Text = CarDealConfig.oneLine(said.band.Label)
	screen.rating.TextColor3 = said.band.Color
	setAcceptWord(screen.accept, said.accept)

	screen.gui.Enabled = true
	if type(body) == "string" then
		CarViewport.set(screen.view, body, { paint = tonumber(offer.paint) })
	end
end

function BuyerController._answer(self, accept: boolean)
	local screen = self._screen
	if not (screen and screen.carId) then
		return
	end
	local now = os.clock()
	if now < self._nextAnswer then
		return
	end
	self._nextAnswer = now + BuyerConfig.Screen.Cooldown
	--- A seller's offer answers to whoever opened it (`openSeller`), not to `BuyerService`.
	if screen.onAnswer then
		screen.onAnswer(accept)
		return
	end
	self:getRemoteEvent("OfferAnswer"):Fire(screen.carId, accept)
end

--[[ PUBLIC (`SellerController`): open this screen on a seller's offer at the kerb. `key` identifies
	the seller (it stands where a buyer's car id would, so `closeSeller` and a buyer's resolution can
	tell the two apart); `onAnswer` receives BUY (true) or DECLINE (false). The screen stays up after
	an answer, and the caller closes it when the server has acted (`closeSeller`). ]]
function BuyerController.openSeller(self, key: string, offer: { [string]: any }, onAnswer: (boolean) -> ())
	local screen = self._screen
	if not screen then
		return
	end
	offer.seller = true
	offer.carId = key
	screen.onAnswer = onAnswer
	self:_open(offer)
end

--- PUBLIC (`SellerController`): close the screen if it is showing this seller, and only then.
function BuyerController.closeSeller(self, key: string)
	local screen = self._screen
	if screen and screen.onAnswer and screen.carId == key then
		self:_close()
	end
end

function BuyerController._close(self)
	local screen = self._screen
	if not screen then
		return
	end
	screen.onAnswer = nil
	if self._kit then
		self:_closeKit()
		return
	end
	screen.gui.Enabled = false
	screen.carId = nil
	CarViewport.clear(screen.view)
end

--[[ A CLOSED SCREEN SWITCHES ITSELF BACK OFF, whoever switched it on (2026-09-30).

	The NEW BEST cutscene (`ShowcaseController`) and the hide-UI setting (`InterfaceController`) sweep
	every ScreenGui off and later switch back on each one that asked to be on in the meantime. An offer
	answered under a sweep closes onto a screen already forced off, its own `false` fires nothing, and
	the restore puts it back ON after it has closed: the kit's dim is a full-screen button faded to
	nothing, so every click in the lobby, PLAY included, lands on it. `SellPopupController._wire` has
	the same guard for the same trap.

	Both opens mark the screen open BEFORE enabling it (`screen.open` on the kit, `carId` on the
	placeholder), so a real open is never undone here. ]]
function BuyerController._keepClosedShut(self)
	local screen = self._screen
	if not screen then
		return
	end
	screen.gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		local open = if self._kit then screen.open else screen.carId ~= nil
		if screen.gui.Enabled and not open then
			screen.gui.Enabled = false
		end
	end)
end

BuyerController:withRemoteEvents({
	"OfferAnswer",
	{
		OfferOpen = function(offer: unknown)
			BuyerController:_open(offer)
		end,
		--- Any answer closes the screen on that car; a resolution for a different car (a stale
		--- press) leaves an open screen alone.
		OfferResolved = function(carId: unknown, result: unknown, amount: unknown)
			local screen = BuyerController._screen
			if screen and screen.carId == carId then
				BuyerController:_close()
			end
			if result == "sold" then
				BuyerController:_celebrate(carId, amount)
			elseif result == "declined" then
				BuyerController:_declined(carId)
			end
		end,
	},
})

BuyerController:withLifecycle({
	init = function(self)
		self._signs = {} :: { [Model]: any }
		self._soldAt = {} :: { [string]: Vector3 } -- carId -> where its buyer stood (`_celebrate`)
		self._nextAnswer = 0
	end,

	start = function(self)
		if not BuyerConfig.Enabled then
			return
		end
		self:_buildScreen()
		self:_keepClosedShut()

		CollectionService:GetInstanceAddedSignal(BUYER_TAG):Connect(function(model)
			self:_bind(model)
		end)
		CollectionService:GetInstanceRemovedSignal(BUYER_TAG):Connect(function(model)
			self:_unbind(model)
		end)
		for _, model in CollectionService:GetTagged(BUYER_TAG) do
			self:_bind(model)
		end

		RunService.Heartbeat:Connect(function()
			self:_stepClocks()
		end)
	end,
})

return BuyerController
