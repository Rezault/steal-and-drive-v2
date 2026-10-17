--[[
	SellerController  (client)
	--------------------------
	Everything a player SEES of a seller at a dealership's kerb (`SellerConfig`): the car pulling in
	and away, the honk, the sign, and for a first-timer the outline and the arrow. `SellerService`
	stands the car and decides everything; this reads the model's attributes and draws.

	THE DRIVE IS A LOCAL TWEEN OF PARTS THE SERVER PUT STILL. The server parents the car already on
	its spot and stamps `ArriveAt`; every client that has it streamed in moves each part back along
	the road and eases it home over `Drive.ArriveSeconds`, then honks. Leaving is the same off
	`LeaveAt`. A client that streams the car in after the drive-in sees it parked, with no replayed
	arrival, which is right: they were not there for it.

	THE SIGN IS THE BUYER'S (`BuyerOfferSign`), so selling you a car and buying one off you read as
	one family: who, what, PRICE, the price, the comparison against the usual price and the rating
	word, with the countdown strip under it. It shows only once the car has stopped, for
	`BuyerController`'s reason: a price racing up the road is not an offer yet.

	SINCE 2026-10-15 IT IS THE BUYER'S NEW CARD (design B) in the seller's own colours
	(`SellerConfig.Bubble`), so the two still read as one family but a seller is told apart from a
	buyer at a glance: FOR SALE BY over the name, the seller's bands on the badge, and the pill
	green under worth. `_paintDesign` fills it. The old kit sign is the fallback.

	Everyone sees the seller; only the owner gets the prompt (hidden here, refused by the server).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local SellerConfig = require(ReplicatedStorage.shared.Configs.SellerConfig)
local BuyerConfig = require(ReplicatedStorage.shared.Configs.BuyerConfig)
--- The sign's size and clock geometry are the market's bubble, which the buyer sign was cut for.
local CarDealConfig = require(ReplicatedStorage.shared.Configs.CarDealConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local BuyerOfferSign = require(ReplicatedStorage.shared.Modules.BuyerOfferSign)
--- The seller's car sounds like itself on the drive (`driveSound`), and the owner's arrival cue.
local EngineAudio = require(ReplicatedStorage.shared.Modules.EngineAudio)
local EngineSoundConfig = require(ReplicatedStorage.shared.Configs.EngineSoundConfig)
local GameplayFeedback = require(ReplicatedStorage.shared.Modules.GameplayFeedback)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)

local SellerController = Shard.new("SellerController")

SellerController:withRemoteEvents({ "SellerAnswer", "SellerShowReady" })

local ATTR = SellerConfig.Attributes
local NAMES = SellerConfig.Names

type Seller = {
	model: Model,
	frame: CFrame,
	--- Every part that drives, as an offset from `frame`, read once when it streamed in parked.
	parts: { [BasePart]: CFrame },
	gui: BillboardGui,
	sign: any,
	arrow: BillboardGui?,
	honk: Sound?,
	--- The car's own engine while it drives (`SellerConfig.Sound`); false: this body has no pack.
	engine: any?,
	--- The car is in its drive-in tween and has not honked yet.
	arriving: boolean,
	signHeight: number,
	connections: { RBXScriptConnection },
	--- The offer screen has been closed for this seller's leaving, so it is done once, not per frame.
	closed: boolean?,
	--- Which one-off ending beats have played (`_endings`).
	beats: { [string]: boolean },
	key: string,
}

local function isOwner(model: Model): boolean
	return model:GetAttribute(ATTR.Owner) == Players.LocalPlayer.UserId
end

--- Put every part at `frame` moved `along` studs down its own look axis (negative is behind).
--[[ Also carries the seller in the driver's seat (`SellerConfig.Seat`): their anchored root goes to
	`Attributes.Seat` against the moving frame, and the limbs follow on their joints. Looked up every
	call rather than captured at `_bind`, since the rig arrives a moment after the car. Never while
	`Out` is set: that person is standing where the server put them. ]]
--- `offset` is the car's pose in the spot's frame (`SellerConfig.route`); identity is parked.
local function pose(seller: Seller, offset: CFrame)
	local at = seller.frame * offset
	for part, offset in seller.parts do
		part.CFrame = at * offset
	end
	local model = seller.model
	local seat = model:GetAttribute(ATTR.Seat)
	local rig = model:FindFirstChild(NAMES.Rig)
	local root = rig and rig:IsA("Model") and rig.PrimaryPart
	if root and typeof(seat) == "CFrame" and model:GetAttribute(ATTR.Out) ~= true then
		root.CFrame = at * seat
	end
end

--[[ Fade the whole car, driver included, to `amount` (0 solid, 1 gone) on this client only
	(`SellerConfig.Drive.FadeFrom`). `LocalTransparencyModifier` rather than `Transparency`, so the
	authored see-through parts (glass, hidden helpers) keep their own value and a part the art left
	invisible is never made visible. Walks the model every call while leaving, a couple of seconds
	of one car, rather than caching a list the late-arriving rig would be missing from. ]]
local function fade(model: Model, amount: number)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") or item:IsA("Decal") then
			item.LocalTransparencyModifier = amount
		end
	end
end

--[[ The engine under the drive (`SellerConfig.Sound.Engine`, 2026-10-15, Aleafo: "I never heard it,
	I never looked in that direction"). The car's OWN pack (`EngineSoundConfig.packFor`), the same
	layers a player hears driving that body, positional on the car, so a seller is heard coming down
	the road before it is seen. Built on the first frame it is needed, fed one frame at a time. ]]
local function driveSound(seller: Seller, through: number, accelerating: boolean, dt: number, idle: boolean?)
	if not SellerConfig.Sound.Engine or seller.engine == false then
		return
	end
	if not seller.engine then
		local pack = EngineSoundConfig.packFor(seller.model:GetAttribute(ATTR.Body))
		local anchor = seller.model:FindFirstChild(NAMES.Anchor)
		if not (pack and anchor) then
			seller.engine = false
			return
		end
		seller.engine = EngineAudio.new(anchor, pack, SellerConfig.Sound.EngineFullWithin, false)
	end
	--- Parked, the engine idles (`idle`, standing still) at `IdleVolume`; driving, `EngineVolume`.
	local sound = SellerConfig.Sound
	seller.engine:update(through, idle == true, accelerating, if idle then sound.IdleVolume else sound.EngineVolume, dt, 2, if idle then 0 else 1)
end

--- The engine winds down and goes; a later drive (the leave) builds a fresh one.
local function stopSound(seller: Seller)
	local engine = seller.engine
	if engine then
		engine:fadeOut(0.5)
		task.delay(0.6, function()
			engine:destroy()
		end)
	end
	if engine ~= false then
		seller.engine = nil
	end
end

--[[ `_paint` for the buyer's card (`SellerConfig.Bubble.Design`). The header is the seller: their
	friend's face when one stands behind the rig (`Attributes.UserId`), the kit silhouette otherwise,
	and FOR SALE BY over the name. The pill is the buyer's the other way round, green and down under
	worth, red and up over it, because here the player is the one paying. ]]
function SellerController._paintDesign(self, seller: Seller)
	local model, sign, text = seller.model, seller.sign, SellerConfig.Bubble
	local userId = model:GetAttribute(ATTR.UserId)
	if type(userId) == "number" and userId > 0 then
		sign.face.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
	end
	local name = model:GetAttribute(ATTR.Name)
	sign.who.Text = CarDealConfig.oneLine(if type(name) == "string" and name ~= "" then string.upper(name) else text.AnonymousName)
	sign.from.Text = CarDealConfig.oneLine(text.From)
	local body, paint = model:GetAttribute(ATTR.Body), model:GetAttribute(ATTR.Paint)
	sign.body.Text = if type(body) == "string"
		then CarDealConfig.oneLine(string.upper(GarageConfig.carName(body, if type(paint) == "number" then paint else nil)))
		else ""

	local price, usual = model:GetAttribute(ATTR.Price), model:GetAttribute(ATTR.Usual)
	if not (type(price) == "number" and type(usual) == "number") then
		return
	end
	sign.price.Text = GarageConfig.formatCash(price)
	--- Rounded as `compareText` rounds, so the pill's colour and its words never disagree.
	local percent = if usual > 0 then math.round((price / usual - 1) * 100) else 0
	local look = if percent < 0 then text.Pill.Below elseif percent > 0 then text.Pill.Above else text.Pill.At
	sign.pill.BackgroundColor3 = look.Fill
	if sign.pillRim then
		sign.pillRim.Color = look.Rim
	end
	sign.pillText.TextColor3 = look.Ink
	sign.pillText.Text = CarDealConfig.oneLine(SellerConfig.compareText(price, usual))
	sign.pillArrow.Visible = look.Arrow ~= nil
	if look.Arrow then
		sign.pillArrow.ImageColor3 = look.Arrow
		--- The art points down; over worth it turns to point up.
		sign.pillArrow.Rotation = if percent > 0 then 180 else 0
	end
	if sign.badge then
		local band = SellerConfig.bandFor(price, usual)
		sign.badgeText.Text = CarDealConfig.oneLine(band.Label)
		--- The card carries a ramp per seller band (`BuildBuyerSignDesigns`), named by its `Key`.
		local ramp = sign.badgeRamps and sign.badgeRamps:FindFirstChild(band.Key)
		if ramp and sign.badgeTint then
			sign.badgeTint.Color = ramp.Color
		end
	end
end

--- Fill the sign from the attributes. Re-run when the seller's name arrives (they step out after).
function SellerController._paint(self, seller: Seller)
	if seller.sign.design then
		self:_paintDesign(seller)
		return
	end
	local model, sign, text = seller.model, seller.sign, SellerConfig.Text
	local name = model:GetAttribute(ATTR.Name)
	sign.who.Text = CarDealConfig.oneLine(if type(name) == "string" and name ~= ""
		then string.format(text.Named, string.upper(name))
		else text.Anonymous)
	local body, paint = model:GetAttribute(ATTR.Body), model:GetAttribute(ATTR.Paint)
	if type(body) == "string" then
		sign.body.Text = CarDealConfig.oneLine(string.upper(GarageConfig.carName(body, if type(paint) == "number" then paint else nil)))
		sign.body.TextColor3 = Color3.new(1, 1, 1)
	end
	sign.caption.Text = CarDealConfig.oneLine(text.Caption)
	local price, usual = model:GetAttribute(ATTR.Price), model:GetAttribute(ATTR.Usual)
	if type(price) == "number" and type(usual) == "number" then
		sign.price.Text = GarageConfig.formatCash(price)
		sign.value.Text = CarDealConfig.oneLine(SellerConfig.compareText(price, usual))
		local band = SellerConfig.bandFor(price, usual)
		sign.rating.Text = CarDealConfig.oneLine(band.Label)
		sign.rating.TextColor3 = if sign.arcade and not sign.kit then Color3.new(1, 1, 1) else band.Color
		if sign.badge then
			sign.badge.BackgroundColor3 = band.Color
		end
	end
end

--[[ The first-time pointers (`SellerConfig.Onboarding`): an outline round the car and an arrow over
	the sign. Only for the owner, only while the server says they have never bought from a seller. ]]
function SellerController._onboard(self, seller: Seller, anchor: BasePart)
	local cfg = SellerConfig.Onboarding
	if not (cfg.Enabled and seller.model:GetAttribute(ATTR.First) == true and isOwner(seller.model)) then
		return
	end
	local outline = Instance.new("Highlight")
	outline.Adornee = seller.model:FindFirstChild(NAMES.Car)
	outline.FillTransparency = 1
	outline.OutlineColor = cfg.OutlineColor
	outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	outline.Parent = seller.model

	local arrow = Instance.new("BillboardGui")
	arrow.Name = "SellerArrow"
	arrow.Adornee = anchor
	arrow.Size = UDim2.fromScale(cfg.ArrowSize, cfg.ArrowSize)
	arrow.AlwaysOnTop = true
	arrow.LightInfluence = 0
	arrow.Enabled = false
	local image = Instance.new("ImageLabel")
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	--- `UIAssets.Tutorial.Arrow` points DOWN at rotation 0, which is the way this one points.
	image.Image = UIAssets.url(UIAssets.Tutorial.Arrow)
	image.Parent = arrow
	arrow.Parent = seller.model
	seller.arrow = arrow
end

function SellerController._bind(self, model: Instance)
	if not model:IsA("Model") or self._sellers[model] then
		return
	end
	local frame = model:GetAttribute(ATTR.Frame)
	local anchor = model:FindFirstChild(NAMES.Anchor)
	local car = model:FindFirstChild(NAMES.Car)
	if typeof(frame) ~= "CFrame" or not (anchor and anchor:IsA("BasePart") and car) then
		return
	end

	local parts = { [anchor] = frame:ToObjectSpace(anchor.CFrame) }
	for _, part in car:GetDescendants() do
		if part:IsA("BasePart") then
			parts[part] = frame:ToObjectSpace(part.CFrame)
		end
	end

	--- Sized as `BuyerController._bind` sizes the buyer's, and sat on the roof rather than a head.
	local bubble = CarDealConfig.Bubble
	local clock = bubble.Clock
	local scale = BuyerConfig.Bubble.ArcadeScale
	local total = bubble.Size.Y + (if clock.Enabled then clock.Gap + clock.Height else 0)
	local gui = Instance.new("BillboardGui")
	gui.Name = "SellerSign"
	gui.Adornee = anchor
	gui.Size = UDim2.fromScale(bubble.Size.X * scale, total * scale)
	gui.StudsOffset = Vector3.new(0, total * scale / 2 + 1, 0)
	gui.MaxDistance = bubble.MaxDistance
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	local panelShare, clockShare = bubble.Size.Y / total, if clock.Enabled then clock.Height / total else 0
	local height = total * scale
	--[[ The buyer's card in the seller's colours (`SellerConfig.Bubble.Design`) first. It brings its
		own shape: `DesignHeight` studs tall, as wide as its `Aspect` makes it, its bottom kept just
		over the roof. ]]
	local design = SellerConfig.Bubble.Design
	local sign = if UIRoot.isNewUI() and type(design) == "string"
		then BuyerOfferSign.buildDesign(gui, design, "SellerSigns")
		else nil
	if sign then
		height = SellerConfig.Bubble.DesignHeight
		gui.Size = UDim2.fromScale(height * sign.aspect, height)
		gui.StudsOffset = Vector3.new(0, height / 2 + 1, 0)
	end
	--- The kit sign when the place has its template, the arcade one otherwise (`BuyerOfferSign`).
	sign = sign
		or (if UIRoot.isNewUI() then BuyerOfferSign.buildKit(gui, panelShare, clockShare) else nil)
		or BuyerOfferSign.build(gui, panelShare, clockShare)
	gui.Parent = model

	self._nextKey += 1
	local seller: Seller = {
		model = model,
		frame = frame,
		parts = parts,
		gui = gui,
		sign = sign,
		arrow = nil,
		honk = nil,
		arriving = false,
		signHeight = height + 1,
		connections = {},
		key = "seller:" .. tostring(self._nextKey),
		beats = {},
	}
	self._sellers[model] = seller
	self:_paint(seller)
	self:_onboard(seller, anchor)
	table.insert(seller.connections, model:GetAttributeChangedSignal(ATTR.Name):Connect(function()
		self:_paint(seller)
	end))
	--- The face arrives with the name (`SellerService`), on whichever attribute lands second.
	table.insert(seller.connections, model:GetAttributeChangedSignal(ATTR.UserId):Connect(function()
		self:_paint(seller)
	end))

	if SellerConfig.Honk.SoundId ~= "" then
		local honk = Instance.new("Sound")
		honk.SoundId = SellerConfig.Honk.SoundId
		honk.Volume = SellerConfig.Honk.Volume
		honk.RollOffMode = Enum.RollOffMode.InverseTapered
		honk.RollOffMinDistance = SellerConfig.Honk.RollOffMinDistance
		honk.RollOffMaxDistance = SellerConfig.Honk.RollOffMaxDistance
		honk.Parent = anchor
		seller.honk = honk
	end

	--- Yours: the prompt opens the buyer's offer screen on this seller (`SellerConfig.Text.ActionText`).
	if isOwner(model) then
		local function wire(child: Instance)
			if child:IsA("ProximityPrompt") then
				table.insert(seller.connections, child.Triggered:Connect(function()
					self:_openOffer(seller)
				end))
			end
		end
		for _, child in model:GetDescendants() do
			wire(child)
		end
		table.insert(seller.connections, model.DescendantAdded:Connect(wire))
	else
		--- Somebody else's seller: no button, the server would refuse it anyway (header).
		local function hide(child: Instance)
			if child:IsA("ProximityPrompt") then
				child.Enabled = false
			end
		end
		for _, child in model:GetDescendants() do
			hide(child)
		end
		table.insert(seller.connections, model.DescendantAdded:Connect(hide))
	end

	local arriveAt = model:GetAttribute(ATTR.ArriveAt)
	if type(arriveAt) == "number" and workspace:GetServerTimeNow() - arriveAt < SellerConfig.Drive.ArriveSeconds then
		seller.arriving = true
		pose(seller, if SellerConfig.Drive.Path
			then self._route.arrive[1]
			else CFrame.new(0, 0, SellerConfig.Drive.Distance))
	end
end

--- The screen's key for this seller, handed out once at `_bind`: unique per car, so a stale screen
--- never answers a new seller.
local function keyOf(seller: Seller): string
	return seller.key
end

--[[ Open the buyer's offer screen on this seller (`BuyerController.openSeller`). The answer goes to
	the server on `SellerAnswer`. DECLINE closes the screen at once, since the seller is leaving
	whatever happens next. BUY leaves it up until the server acts: a sale removes the car, which
	closes it in `_unbind`, and a refusal (short of cash) keeps it open with the cash pack offered
	over it. ]]
function SellerController._openOffer(self, seller: Seller)
	local Buyers = Shard.get("BuyerController")
	local model = seller.model
	if not Buyers or model:GetAttribute(ATTR.LeaveAt) then
		return
	end
	local key = keyOf(seller)
	Buyers:openSeller(key, {
		name = model:GetAttribute(ATTR.Name),
		body = model:GetAttribute(ATTR.Body),
		paint = model:GetAttribute(ATTR.Paint),
		amount = model:GetAttribute(ATTR.Price),
		value = model:GetAttribute(ATTR.Usual),
	}, function(accept: boolean)
		self:getRemoteEvent("SellerAnswer"):Fire(accept)
		if not accept then
			Buyers:closeSeller(key)
		end
	end)
end

function SellerController._unbind(self, model: Instance)
	local seller = self._sellers[model :: Model]
	if not seller then
		return
	end
	self._sellers[model :: Model] = nil
	local Buyers = Shard.get("BuyerController")
	if Buyers then
		Buyers:closeSeller(keyOf(seller))
	end
	for _, connection in seller.connections do
		connection:Disconnect()
	end
	if seller.engine then
		seller.engine:destroy()
	end
end

--[[ The one-off beats of an ending, each at most once per seller (`seller.beats`), off the server's
	attributes (`SellerConfig.Sold`):
	  * Sold: the offer screen closes; the OWNER's client waits out any NEW BEST screen, then tells
	    the server to start the show (`SellerShowReady`). The server's timeout covers a client that
	    never says.
	  * SoldAt: the SOLD! stamp with the car's name, on every client; the owner hears the sale.
	  * Declined: the owner hears the huff (`BuyerConfig.Declined.Sound`). ]]
function SellerController._endings(self, seller: Seller)
	local model, beats = seller.model, seller.beats
	local owner = isOwner(model)
	if model:GetAttribute(ATTR.Sold) == true and not beats.sold then
		beats.sold = true
		--- The first-timer outline would outlive the fade (a Highlight draws its own outline).
		local outline = model:FindFirstChildOfClass("Highlight")
		if outline then
			outline:Destroy()
		end
		local Buyers = Shard.get("BuyerController")
		if Buyers then
			Buyers:closeSeller(keyOf(seller))
		end
		if owner then
			task.spawn(function()
				--- A beat for the NEW BEST remote, fired before this attribute, to have landed.
				task.wait(0.4)
				local Showcase = Shard.get("ShowcaseController")
				local started = os.clock()
				while Showcase and Showcase:busy() and os.clock() - started < SellerConfig.Sold.MaxWaitSeconds do
					task.wait(0.25)
				end
				self:getRemoteEvent("SellerShowReady"):Fire()
			end)
		end
	end
	if type(model:GetAttribute(ATTR.SoldAt)) == "number" and not beats.stamped then
		beats.stamped = true
		local Buyers = Shard.get("BuyerController")
		local body, paint = model:GetAttribute(ATTR.Body), model:GetAttribute(ATTR.Paint)
		local rig = model:FindFirstChild(NAMES.Rig)
		local head = rig and rig:FindFirstChild("Head")
		local at = if head and head:IsA("BasePart") then head.Position else model:GetPivot().Position
		if Buyers and type(body) == "string" then
			Buyers:stamp(at, CarDealConfig.oneLine(string.upper(GarageConfig.carName(body, if type(paint) == "number" then paint else nil))))
		end
		if owner then
			local sounds = Shard.get("SoundController")
			if sounds then
				sounds:PlayNamed(BuyerConfig.Sold.Sound.Group, BuyerConfig.Sold.Sound.Name)
			end
		end
	end
	if model:GetAttribute(ATTR.Declined) == true and not beats.declined then
		beats.declined = true
		local sounds = Shard.get("SoundController")
		if owner and sounds and BuyerConfig.Declined.Enabled then
			sounds:PlayNamed(BuyerConfig.Declined.Sound.Group, BuyerConfig.Declined.Sound.Name)
		end
	end
end

--[[ One pass over every seller: where the car is along its drive, whether the sign shows, the clock,
	the arrow's bob. One connection for all of them rather than one each. ]]
function SellerController._step(self, dt: number)
	local now = workspace:GetServerTimeNow()
	local drive = SellerConfig.Drive
	for model, seller in self._sellers do
		local arriveAt = model:GetAttribute(ATTR.ArriveAt)
		local leaveAt = model:GetAttribute(ATTR.LeaveAt)
		local sold = model:GetAttribute(ATTR.Sold) == true
		local parked = false
		self:_endings(seller)
		if sold then
			--- Bought (`SellerConfig.Sold`): it stays put for the show, then fades where it stands. The
			--- engine stops with the sale (it was idling while parked).
			stopSound(seller)
			local fadeAt = model:GetAttribute(ATTR.FadeAt)
			if type(fadeAt) == "number" then
				fade(model, math.clamp((now - fadeAt) / SellerConfig.Sold.FadeSeconds, 0, 1))
			end
		elseif type(leaveAt) == "number" then
			--- Timed out under an open screen: nothing left to answer.
			if not seller.closed then
				seller.closed = true
				local Buyers = Shard.get("BuyerController")
				if Buyers then
					Buyers:closeSeller(keyOf(seller))
				end
			end
			local t = math.clamp((now - leaveAt) / drive.LeaveSeconds, 0, 1)
			--- How far into the fading leg (0..1): the drive away on the road route, the whole leave
			--- on the straight line.
			local fading = t
			if drive.Path then
				--[[ Reverse out, eased in and out so it stops before pulling away; then drive off,
					eased in. Two legs on their own clocks, split by `ReverseShare`. ]]
				local split = drive.ReverseShare
				if t < split then
					local u = t / split
					pose(seller, SellerConfig.sample(self._route.reverse, u * u * (3 - 2 * u)))
					fading = 0
					driveSound(seller, 0.2, true, dt)
				else
					local u = (t - split) / (1 - split)
					pose(seller, SellerConfig.sample(self._route.away, u * u))
					fading = u
					driveSound(seller, 0.2 + 0.7 * u, true, dt)
				end
			else
				--- Ease in, backwards out the way it came or on forwards (`Drive.LeaveBackwards`).
				pose(seller, CFrame.new(0, 0, (if drive.LeaveBackwards then drive.Distance else -drive.Distance) * t * t))
			end
			if drive.FadeFrom < 1 then
				fade(model, math.clamp((fading - drive.FadeFrom) / (1 - drive.FadeFrom), 0, 1))
			end
			if t >= 1 then
				stopSound(seller)
			end
		elseif seller.arriving and type(arriveAt) == "number" then
			--- Ease out: pulling in ends on a gentle stop.
			local t = math.clamp((now - arriveAt) / drive.ArriveSeconds, 0, 1)
			local eased = 1 - (1 - t) ^ 2
			pose(seller, if drive.Path
				then SellerConfig.sample(self._route.arrive, eased)
				else CFrame.new(0, 0, drive.Distance * (1 - eased)))
			--- Off the throttle and winding down as it brakes into the spot.
			driveSound(seller, 0.15 + 0.6 * (1 - t), false, dt)
			if t >= 1 then
				--- The engine keeps running: it idles while parked (below) and revs up on the way out.
				seller.arriving = false
				if seller.honk then
					seller.honk:Play()
				end
				--[[ THE OWNER HEARS IT WHEREVER THEY ARE LOOKING: a flat (not positional) cue,
					`Sound.ArrivalCue`, the "HEY!", falling back to the buyer's own arrival cue
					while the place has no clip by that name. ]]
				if isOwner(model) and not GameplayFeedback.play(SellerConfig.Sound.ArrivalCue) then
					GameplayFeedback.play(SellerConfig.Sound.FallbackCue)
				end
			end
		else
			parked = true
			--- Left running at the kerb (`SellerConfig.Sound.IdleVolume`); not for a sold car.
			if not sold then
				driveSound(seller, 0, false, dt, true)
			end
		end

		parked = parked and not sold
		seller.gui.Enabled = parked
		if seller.arrow then
			local bob = SellerConfig.Onboarding
			seller.arrow.Enabled = parked
			local wave = (math.sin(os.clock() * 2 * math.pi / bob.BobPeriod) + 1) / 2
			seller.arrow.StudsOffset = Vector3.new(0, 1 + seller.signHeight + bob.ArrowLift + bob.ArrowSize / 2 + wave * bob.BobStuds, 0)
		end

		local sign = seller.sign
		local expires = model:GetAttribute(ATTR.ExpiresAt)
		--- A card's clock is its own footer and always part of it; only the kit sign's strip comes and goes.
		if parked and (sign.strip or sign.design) and type(expires) == "number" then
			local remaining = math.max(0, expires - now)
			if sign.strip then
				sign.strip.Visible = true
			end
			if sign.clock then
				sign.clock.Text = string.format(SellerConfig.Text.Clock, CarDealConfig.formatCountdown(remaining))
			end
			if sign.timeFill then
				sign.timeFill.Size = UDim2.fromScale(math.clamp(remaining / SellerConfig.Visit.WaitSeconds, 0, 1), 1)
			end
			--- The bar goes red near the end, as the buyer's does (`BuyerController._stepClocks`); set on the flip only.
			local urgent = remaining <= CarDealConfig.Bubble.Clock.UrgentSeconds
			if sign.timeTint and sign.urgent ~= urgent then
				sign.urgent = urgent
				local hot = CarDealConfig.Bubble.Clock.UrgentColor
				sign.timeTint.Color = if urgent then ColorSequence.new(hot:Lerp(Color3.new(1, 1, 1), 0.35), hot) else sign.timeRamp
			end
		end
	end
end

SellerController:withLifecycle({
	init = function(self)
		self._sellers = {} :: { [Model]: Seller }
		self._nextKey = 0
		--- The road route, built once: it is config, the same for every seller (`SellerConfig.route`).
		self._route = SellerConfig.route()
	end,

	start = function(self)
		if not SellerConfig.Enabled then
			return
		end
		CollectionService:GetInstanceAddedSignal(SellerConfig.Tag):Connect(function(model)
			self:_bind(model)
		end)
		CollectionService:GetInstanceRemovedSignal(SellerConfig.Tag):Connect(function(model)
			self:_unbind(model)
		end)
		for _, model in CollectionService:GetTagged(SellerConfig.Tag) do
			self:_bind(model)
		end
		RunService.RenderStepped:Connect(function(dt: number)
			self:_step(dt)
		end)
	end,
})

return SellerController
