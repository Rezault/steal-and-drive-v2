--[[
	BundleStandController  (client)
	-------------------------------
	The viewer's side of a bundle stand in the lobby (`ShopConfig.BundleStand`): the board over it and
	the press. `BundleService` parks the cars and the prompt; the receipt pays (`grantBundle`).

	THE PRICE IS ROBLOX'S, ASKED HERE. `GetProductInfo` on the client answers what THIS player pays (a
	price changed on the dashboard, regional or optimised pricing), the shop page's rule
	(`PagesV2/Shop`'s `livePrice`). The config's `Price` shows until the answer comes, and stays if
	the call fails: a briefly stale tag beats a blank one.

	THE PRESS ONLY OPENS ROBLOX'S WINDOW. Nothing is decided here and nothing is trusted to the
	client: Roblox takes the Robux and the server's receipt hands out the cars.
]]

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local ShopConfig = require(ReplicatedStorage.shared.Configs.ShopConfig)

local BundleStandController = Shard.new("BundleStandController")

local CFG = ShopConfig.BundleStand
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
--- Roblox's own Robux mark, the shop pills' (`PagesV2/Shop`'s `ROBUX`).
local ROBUX = utf8.char(0xE002)

local function line(parent: Instance, y: number, h: number, colour: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, y)
	label.Size = UDim2.fromScale(1, h)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.TextColor3 = colour
	label.TextScaled = true
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(20, 12, 30)
	stroke.Parent = label
	label.Parent = parent
	return label
end

--- The bundle a stand is showing now: the server's `CurrentAttribute` on a cycling stand, else its one
--- `Attribute` (`ShopConfig.BundleStand`). Read at every paint and every press, never cached.
local function currentOf(model: Model): ShopConfig.Bundle?
	return ShopConfig.bundleOf(model:GetAttribute(CFG.CurrentAttribute) or model:GetAttribute(CFG.Attribute))
end

--[[ This player's price for a product, asked once per session (`GetProductInfo`, header). nil until
	Roblox answers, or for good if it cannot: the caller shows the config's price meanwhile. ]]
local livePrices: { [number]: number | false } = {}
local function livePrice(id: number): number?
	if livePrices[id] == nil then
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(id, Enum.InfoType.Product)
		end)
		livePrices[id] = if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then info.PriceInRobux else false
	end
	local price = livePrices[id]
	return if price then price else nil
end

function BundleStandController._bind(self, model: Instance)
	if not model:IsA("Model") or self._stands[model] then
		return
	end
	--- Over the middle podium unless the stand has its own `Sign` part (`ShopConfig.BundleStand.Lift`).
	local podiums = 0
	while model:FindFirstChild(CFG.SpotPrefix .. (podiums + 1)) do
		podiums += 1
	end
	local signPart = model:FindFirstChild(CFG.SignName)
	local middleSpot = model:FindFirstChild(CFG.SpotPrefix .. math.max(1, math.ceil(podiums / 2)))
	local adornee = if signPart and signPart:IsA("BasePart") then signPart else middleSpot
	if not (adornee and adornee:IsA("BasePart")) then
		return
	end

	local unified = model:GetAttribute("UnifiedBundleDisplay") == true
	local preview = model:FindFirstChild("BundleHeaderBillboard", true)
	if unified and preview and preview:IsA("BillboardGui") then
		preview.Enabled = false
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "BundleSign"
	gui.Adornee = adornee
	gui.Size = if unified then UDim2.fromScale(53, 8) else UDim2.fromScale(CFG.SignSize.X, CFG.SignSize.Y)
	gui.StudsOffset = if adornee == signPart then Vector3.zero else Vector3.new(0, CFG.Lift, 0)
	gui.MaxDistance = if unified then 280 else CFG.SignMaxDistance
	gui.AlwaysOnTop = if unified then false else CFG.SignOnTop
	gui.LightInfluence = 0
	gui.Parent = self._folder
	local title = if unified then line(gui, 0, 0.54, Color3.new(1, 1, 1)) else line(gui, 0, 0.36, Color3.fromRGB(255, 220, 60))
	local contents = if unified then line(gui, 0.57, 0.38, Color3.fromRGB(51, 199, 253)) else line(gui, 0.38, 0.2, Color3.new(1, 1, 1))
	local terminal = model:FindFirstChild("BundlePurchaseTerminal", true)
	local action = terminal and terminal:FindFirstChild("ActionText", true)
	local summary = terminal and terminal:FindFirstChild("OfferSummary", true)
	local price = if unified and action and action:IsA("TextLabel") then action else line(gui, 0.6, 0.34, Color3.fromRGB(91, 255, 91))
	local function priceText(value: string)
		price.Text = if unified and value ~= CFG.OwnedText then "BUY BUNDLE\n" .. value else value
	end
	self._stands[model] = gui

	--- The server's prompts on this stand, so a once-only bundle already owned can switch them off.
	local prompts: { ProximityPrompt } = {}

	--- Draw the bundle on show; a cycle (`CurrentAttribute` changing) redraws it, and so does buying a
	--- once-only bundle (`BoughtAttribute`), which turns its price to OWNED and its prompt off here.
	local painted = 0
	local function paint()
		local bundle = currentOf(model)
		gui.Enabled = bundle ~= nil
		if not bundle then
			return
		end
		painted += 1
		local token = painted
		local owned = ShopConfig.boughtOnce(Players.LocalPlayer, bundle)
		for _, prompt in prompts do
			prompt.Enabled = not owned and ShopConfig.isSellable(bundle)
		end
		title.Text = string.upper(bundle.Title)
		contents.Text = if unified then string.format("ALL %d %s INCLUDED", #bundle.Cars, if #bundle.Cars == 1 then "CAR" else "CARS") else bundle.Subtitle
		if unified and summary and summary:IsA("TextLabel") then
			summary.Text = string.format("GET ALL %d %s", #bundle.Cars, if #bundle.Cars == 1 then "CAR" else "CARS")
		end
		priceText(if owned then CFG.OwnedText else ROBUX .. " " .. tostring(bundle.Price))
		if not owned and ShopConfig.isSellable(bundle) then
			task.spawn(function()
				local live = livePrice(bundle.ProductId)
				--- Fenced: a slow answer must not paint one bundle's price over the next one's.
				if live and token == painted and price.Parent then
					priceText(ROBUX .. " " .. tostring(live))
				end
			end)
		end
	end

	--- The prompt is the server's and may arrive after the stand; wire it whenever it does. The press
	--- buys whatever is on show at that moment, unless it is a once-only bundle already owned.
	local function wire(child: Instance)
		if child:IsA("ProximityPrompt") and child.Name == CFG.PromptName then
			table.insert(prompts, child)
			child.Triggered:Connect(function()
				local bundle = currentOf(model)
				if bundle and ShopConfig.isSellable(bundle) and not ShopConfig.boughtOnce(Players.LocalPlayer, bundle) then
					MarketplaceService:PromptProductPurchase(Players.LocalPlayer, bundle.ProductId)
				end
			end)
			paint()
		end
	end
	for _, child in model:GetDescendants() do
		wire(child)
	end
	paint()
	model:GetAttributeChangedSignal(CFG.CurrentAttribute):Connect(paint)
	Players.LocalPlayer:GetAttributeChangedSignal(CFG.BoughtAttribute):Connect(paint)

	--[[ THE CARS TURN ON THEIR PODIUMS (2026-10-15, "the cars should spin on the podium"), here and not
		on the server: a turntable is decoration, and moving fifty anchored parts a frame from the server
		would replicate every one. Each `BundleCar<n>` the server parents in is captured against its
		podium's `CarSpot<n>` as it arrives (the server's own placement, so a re-shown car starts from
		rest) and turned about that spot's centre every frame in `_spin`. ]]
	--[[ === PARTS ARE ADDED AS THEY ARRIVE — 2026-10-15 === ("sometimes the cars don't spin, or one
		spins and the other two don't"). WAS: every part captured the moment the car model appeared.
		A model the server parents in can reach a client BEFORE its parts do, so a car caught empty
		never turned and one caught half-built turned in pieces. IS: the parts present now, and every
		part that arrives after (`DescendantAdded`), each captured as it lands. A part lands in the
		server's rest pose, so its offset from the spot is right whenever it comes. The podium's spot
		is waited for too, in case it is the one running late. ]]
	local function track(child: Instance)
		local podium = tonumber(string.match(child.Name, "^BundleCar(%d+)$"))
		if not (child:IsA("Model") and podium) then
			return
		end
		task.spawn(function()
			local name = CFG.SpotPrefix .. podium
			local spot = model:FindFirstChild(name) or model:WaitForChild(name, 10)
			if not (spot and spot:IsA("BasePart") and child.Parent == model) then
				return
			end
			local entry = { pivot = spot.CFrame, parts = {} :: { [BasePart]: CFrame }, conn = nil :: RBXScriptConnection? }
			local function add(part: Instance)
				if part:IsA("BasePart") and not entry.parts[part] then
					entry.parts[part] = spot.CFrame:ToObjectSpace(part.CFrame)
				end
			end
			for _, part in child:GetDescendants() do
				add(part)
			end
			entry.conn = child.DescendantAdded:Connect(add)
			self._spinning[child] = entry
		end)
	end
	for _, child in model:GetChildren() do
		track(child)
	end
	model.ChildAdded:Connect(track)
	model.ChildRemoved:Connect(function(child)
		local entry = self._spinning[child]
		if entry and entry.conn then
			entry.conn:Disconnect()
		end
		self._spinning[child] = nil
	end)
end

--- One frame of every turntable (`_bind`'s note). Angle off the clock, so all cars turn together.
function BundleStandController._spin(self)
	local degrees = CFG.SpinDegreesPerSecond
	if degrees == 0 then
		return
	end
	local turn = CFrame.Angles(0, math.rad(os.clock() * degrees % 360), 0)
	for car, entry in self._spinning do
		if not car.Parent then
			if entry.conn then
				entry.conn:Disconnect()
			end
			self._spinning[car] = nil
			continue
		end
		--[[ IN STEP (2026-10-15, "they're not spinning in sync, they're at different orientations").
			WAS the podium's own frame turned, so each car kept its placeholder's facing as an offset
			and three angled podiums spun three different ways. IS the podium's POSITION with the
			shared turn alone: the offsets are measured against the spot's facing, so every car's nose
			points the same way at every moment. ]]
		local at = CFrame.new(entry.pivot.Position) * turn
		for part, offset in entry.parts do
			part.CFrame = at * offset
		end
	end
end

function BundleStandController._unbind(self, model: Instance)
	local gui = self._stands[model :: Model]
	if gui then
		self._stands[model :: Model] = nil
		gui:Destroy()
	end
end

BundleStandController:withLifecycle({
	init = function(self)
		self._stands = {} :: { [Model]: BillboardGui }
		self._spinning = {} :: { [Instance]: { pivot: CFrame, parts: { [BasePart]: CFrame }, conn: RBXScriptConnection? } }
	end,
	start = function(self)
		if not CFG.Enabled then
			return
		end
		--- The boards live here, on this client only (the group reward stand's arrangement).
		local folder = Instance.new("Folder")
		folder.Name = "BundleStandsLocal"
		folder.Parent = workspace
		self._folder = folder
		CollectionService:GetInstanceAddedSignal(CFG.Tag):Connect(function(model)
			self:_bind(model)
		end)
		CollectionService:GetInstanceRemovedSignal(CFG.Tag):Connect(function(model)
			self:_unbind(model)
		end)
		for _, model in CollectionService:GetTagged(CFG.Tag) do
			self:_bind(model)
		end
		RunService.RenderStepped:Connect(function()
			self:_spin()
		end)
	end,
})

return BundleStandController
