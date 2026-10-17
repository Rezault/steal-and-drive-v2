--[[
	SellController  (client)
	------------------------
	The sell lot's personal price sign and collection picker confirmation.
	2026-10-12: The prompt opens StartCar in sell mode, with every owned car. Choosing one opens
	SellPopupController's existing price and favourite confirmation. Walking away closes the grid
	and any unanswered question. RequestSell carries only a key; SellService validates ownership,
	proximity and race state and GarageService computes the payout. Driving a car onto the pad is
	still useful for the world price sign, but no longer opens or selects a sale automatically.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local StartCarConfig = require(ReplicatedStorage.shared.Configs.StartCarConfig)
local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local InventoryConfig = require(ReplicatedStorage.shared.Configs.InventoryConfig)
local LobbyCarConfig = require(ReplicatedStorage.shared.Configs.LobbyCarConfig)
local SellConfig = require(ReplicatedStorage.shared.Configs.SellConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)

local SellController = Shard.new("SellController")

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

--- One lot, dressed. There is one in the game today; it is keyed by model anyway, because the tag
--- is what binds and a tag does not promise how many things wear it.
type Lot = {
	model: Model,
	pad: BasePart,
	gui: BillboardGui,
	panel: ImageLabel,
	caption: TextLabel,
	body: TextLabel,
	price: TextLabel,
	shown: boolean,
	trove: any,
}

-- === The sign ===============================================================

--- One row of the panel, positioned as a fraction of its height. Three of these are the whole sign.
local function row(parent: Frame, name: string, band, colour: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, band.Y)
	label.Size = UDim2.fromScale(0.9, band.Height)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.TextColor3 = colour
	label.TextScaled = true
	label.Text = ""
	label.Parent = parent
	return label
end

--[[ Build the sign and park it invisible.

	`AlwaysOnTop` IS OFF, deliberately, and for `CarDealController._buildBubble`'s reason: the car is
	the thing this sign is about and the sign hangs over it. Drawn through the roof it would be a
	price tag floating inside a car.

	IT STARTS AT `Enabled = false` AND FULLY TRANSPARENT. A billboard that exists before it has
	anything to say is a panel that flashes on for one frame every time the lot streams in. ]]
function SellController._buildSign(self, lot: Lot, anchor: Attachment)
	local cfg = SellConfig.Bubble

	local gui = Instance.new("BillboardGui")
	gui.Name = "SellSign"
	gui.Adornee = anchor
	gui.Size = UDim2.fromScale(cfg.Size.X, cfg.Size.Y)
	gui.MaxDistance = cfg.MaxDistance
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = self._gui

	--[[ THE KIT'S SPEECH BUBBLE, one texture — 2026-08-26. It was a `#364157` Frame with a `UICorner`
		and a `#0066FF` `UIStroke`, which is the rounded-rect-and-neon-outline the plot signage and the
		dealership customers were both rebuilt to get away from (`UIAssets.Bubble`).

		THE TAIL IS WHY THIS TEXTURE AND NOT A PANEL. It is the same drawing a customer in a showroom
		talks out of, and it is doing the same job here: the tail points DOWN AT THE PAD, so the price
		belongs to the car standing under it rather than being a number floating over the plaza. The lot
		holds one car at a time and this sign is about that car — a panel would say it and a bubble
		points at it.

		`Stretch`, never `Slice`: `Bubble.Size` is set from this texture's own 1024x398, so the stretch
		is the identity. See `UIAssets.Slice`. ]]
	local panel = Instance.new("ImageLabel")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundTransparency = 1
	panel.Image = UIAssets.url(UIAssets.Bubble.Panel)
	panel.ScaleType = Enum.ScaleType.Stretch
	--- Parked invisible; `_setShown` fades it up to `cfg.PanelTransparency`.
	panel.ImageTransparency = 1
	panel.BorderSizePixel = 0
	panel.Parent = gui

	--[[ THE ROWS GO IN HERE AND NOT IN THE BILLBOARD, because the bottom fifth of the drawing is
		tail — `UIAssets.BubbleBodyFraction` is that split and it lives with the texture because it is a
		property of it. Laying the three rows out against the whole thing would drop the price into the
		spike. `Bubble.Rows` is unchanged and still means what it meant: fractions of the part of the
		sign that has room for words. ]]
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.fromScale(1, UIAssets.BubbleBodyFraction)
	body.BackgroundTransparency = 1
	body.Parent = panel

	lot.gui = gui
	lot.panel = panel
	lot.caption = row(body, "Caption", cfg.Rows.Caption, cfg.Colors.Caption)
	lot.body = row(body, "Body", cfg.Rows.Body, Color3.new(1, 1, 1))
	lot.price = row(body, "Price", cfg.Rows.Price, cfg.Colors.Price)
	lot.trove:Add(gui)
end

--[[ Fade the whole sign in or out.

	EVERY PIECE IS TWEENED RATHER THAN `Visible` FLIPPED, because a panel that pops is a panel that
	looks like a bug when a car rolls a stud too far and it blinks. `Enabled` is switched at the two
	ends: on before a fade in, off after a fade out, so a sign at zero opacity is not still being
	laid out every frame. ]]
function SellController._setShown(self, lot: Lot, shown: boolean)
	if lot.shown == shown then
		return
	end
	lot.shown = shown

	local cfg = SellConfig.Bubble
	local info = TweenInfo.new(cfg.FadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	if shown then
		lot.gui.Enabled = true
	end

	local panelGoal = if shown then cfg.PanelTransparency else 1
	local textGoal = if shown then 0 else 1

	--- `ImageTransparency` now the panel is a texture, and there is no stroke left to fade: the
	--- border and the rim are drawn into the art.
	TweenService:Create(lot.panel, info, { ImageTransparency = panelGoal }):Play()
	for _, label in { lot.caption, lot.body, lot.price } do
		TweenService:Create(label, info, { TextTransparency = textGoal }):Play()
	end

	if not shown then
		task.delay(cfg.FadeSeconds, function()
			--- Only if nothing has asked for it again in the meantime.
			if not lot.shown and lot.gui.Parent then
				lot.gui.Enabled = false
			end
		end)
	end
end

--- Write the three rows at once. Every state below is one call to this.
function SellController._say(self, lot: Lot, caption: string, body: string, price: string, priceColour: Color3)
	lot.caption.Text = if caption == "" then "" else SellConfig.oneLine(caption)
	lot.body.Text = if body == "" then "" else SellConfig.oneLine(body)
	lot.price.Text = if price == "" then "" else SellConfig.oneLine(price)
	lot.price.TextColor3 = priceColour
	self:_setShown(lot, true)
end

-- === Reading the world ======================================================

--[[ The car this player has standing in the lobby, or nil.

	GATED ON THE PLAYER'S OWN ATTRIBUTE FIRST. `LobbyCarConfig.SpawnedAttribute` is the key of the
	car that is out, or "" for none, and it is written by the server as part of spawning one — so the
	common case (walking past the lot with no car out) costs one string compare and never touches the
	workspace at all.

	The scan itself is the contract `LobbyCarConfig` documents: a flat folder, the owner on the model
	as an attribute. It is re-run rather than cached because a car can be despawned by six different
	things and a cached model that has been destroyed is a sign about a car that is not there. ]]
function SellController._myCar(self): Model?
	local player = Players.LocalPlayer
	local spawned = player:GetAttribute(LobbyCarConfig.SpawnedAttribute)
	if type(spawned) ~= "string" or spawned == "" then
		return nil
	end

	local folder = workspace:FindFirstChild(LobbyCarConfig.FolderName)
	if not folder then
		--- The car is out but has not streamed in here yet. Nothing to measure.
		return nil
	end
	for _, model in folder:GetChildren() do
		if model:IsA("Model") and model:GetAttribute(LobbyCarConfig.OwnerAttribute) == player.UserId then
			return model
		end
	end
	return nil
end

--- Is the local player sitting in this car? The one thing the sign says that is about the player
--- rather than about the car — see `SellConfig` note 5 for why it matters at all.
function SellController._seatedIn(_self, car: Model): boolean
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	return seat ~= nil and seat:IsDescendantOf(car)
end

--- Has this player starred this car? Off the same attribute the MY CARS screen sorts by, which is
--- the client's only copy of that list and is written by the server. Header note 2: all it decides
--- is what the panel says and whether SELL IT asks once more, so a client that got it wrong would
--- mis-label its own panel and skip its own speed bump. `SellConfig` note 7 on why that is fine.
function SellController._isFavorite(_self, key: string): boolean
	if not (InventoryConfig.Enabled and InventoryConfig.Sell.ConfirmFavorites) then
		return false
	end
	for _, starred in GarageConfig.split(Players.LocalPlayer:GetAttribute(InventoryConfig.FavoritesAttribute)) do
		if starred == key then
			return true
		end
	end
	return false
end

function SellController._popup(self)
	self._popupController = self._popupController or Shard.get("SellPopupController")
	return self._popupController
end

-- 2026-10-12: The lot is now a collection picker. Only an explicit car pick asks to sell;
-- proximity still closes the question and the grid, and the server checks it again on YES.
function SellController._nearLot(self): boolean
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then return false end
	for _, lot in self._lots do
		if lot.pad.Parent and (root.Position - lot.pad.Position).Magnitude <= SellConfig.Popup.Reach then
			return true
		end
	end
	return false
end

function SellController.offerSelected(self, key: string)
	local popup = self:_popup()
	if not (popup and not popup:isOpen() and self:_nearLot()) then return end
	local owned = GarageConfig.split(Players.LocalPlayer:GetAttribute(GarageConfig.OwnedAttribute))
	if not table.find(owned, key) then return end
	self._offerKey = key
	local price, worth = SellConfig.lotPriceForOwner(Players.LocalPlayer, key)
	popup:offer({
		name = SellConfig.carNameOfKey(key),
		price = GarageConfig.formatCash(price),
		--- What a buyer pays, for the line under the price. Only when the lot pays less than that.
		worth = if price < worth then GarageConfig.formatCash(worth) else nil,
		favorite = self:_isFavorite(key),
	}, {
		answer = function(yes: boolean)
			if yes then self:getRemoteEvent("RequestSell"):Fire(key) end
		end,
		closed = function()
			self._offerKey = ""
		end,
	})
end

function SellController._offerStep(self)
	if self:_nearLot() then return end
	local popup = self:_popup()
	if popup and popup:isOpen() and not popup:isBusy() then popup:close() end
	local picker = Shard.get("StartCarController")
	if picker and picker:mode() == "sell" then
		Dispatcher:Publish("ClosePage", StartCarConfig.PageName)
	end
end

--[[ The server's answer to a request.

	IT GOES TO THE PANEL, which is the thing that asked. `"sold"` is the one that spends money on
	chrome as well: the notes fly out of the lot and into the player (`CashBurstController`, the same
	beat a collect mat gives) while the panel holds SOLD over the amount.

	A REPLY WITH NO PANEL BEHIND IT IS DROPPED ON THE FLOOR, and there is one way to get there — the
	player walked out of reach during the round trip, so `_offerStep` closed the panel under an
	answer that was already on its way. Nothing is wrong and nothing needs correcting: the sale
	either happened or it did not, and the profile is the authority on which. ]]
function SellController._onResult(self, reason: unknown, price: unknown)
	if reason == "sold" then
		local amount = tonumber(price) or 0
		local burst = Shard.get("CashBurstController")
		local lot = self:_anyLot()
		if burst and lot then
			burst:burst(amount, lot.pad.Position)
		end
	end

	local popup = self:_popup()
	if popup then
		popup:result(reason, price)
	end
end

--- Any bound lot, for the one caller that needs a position rather than a particular sign.
function SellController._anyLot(self): Lot?
	for _, lot in self._lots do
		return lot
	end
	return nil
end

-- === What the sign says =====================================================

--[[ Redraw one lot's sign from what is currently true.

	THREE STATES AND THEY ARE IN PRIORITY ORDER: nothing of mine in the lot, a car I am still sitting
	in, and the car itself. The middle one keeps the price up and puts the instruction on the caption
	row, so the sign teaches the gesture without hiding the number the player drove here to read.

	THERE ARE NO REFUSALS ON THIS SIGN ANY MORE. Every one of them used to be a flash over the top of
	it, because the only way to earn one was to hold a button that could fail; a request now comes
	from a panel that is already open, so the answer goes back to the panel and this sign never has
	to be interrupted. `SellConfig.Lines` shrank by four strings for that reason. ]]
function SellController._refresh(self, lot: Lot)
	local cfg = SellConfig.Bubble
	local lines = SellConfig.Lines

	local car = self:_myCar()
	if not (car and SellConfig.isInside(lot.pad, car:GetPivot().Position)) then
		self:_setShown(lot, false)
		return
	end

	local key = car:GetAttribute(LobbyCarConfig.KeyAttribute)
	if type(key) ~= "string" then
		self:_setShown(lot, false)
		return
	end

	local name = SellConfig.carNameOfKey(key)
	local price = GarageConfig.formatCash((SellConfig.lotPriceForOwner(Players.LocalPlayer, key)))

	--[[ STILL SITTING IN IT — and now that getting out is the gesture rather than permission for it,
		this line is the instruction for the whole feature. It is also very nearly a no-op in practice:
		a player who has driven onto the square is about to press E anyway. ]]
	if self:_seatedIn(car) then
		self:_say(lot, lines.GetOut, name, price, cfg.Colors.Price)
		return
	end

	self:_say(lot, lines.SellCaption, name, price, cfg.Colors.Price)
end

-- === The poll ===============================================================

--[[ Note 3: neither a car arriving in the lot nor a player stepping out of it is an event, so this
	asks. It drives both the sign and the question.

	THE DISTANCE GATE IS THE POINT OF THE SIGN'S HALF. A player on the far side of the island has a
	lot streamed out and nothing to draw, and this runs every frame for the whole session — so the
	first thing it does is decide whether there is any question worth asking. `MaxDistance` is the
	sign's own draw distance, so the gate and what it gates cannot disagree.

	THE SIGN GOES DOWN WHILE THE PANEL IS UP. They say the same thing about the same car and the
	panel says it in front of the player's eyes; leaving the sign up behind a scrim would be the
	price printed twice, once dimmed. ]]
function SellController._step(self, dt: number)
	self._since += dt
	if self._since < SellConfig.Bubble.PollInterval then
		return
	end
	self._since = 0

	self:_offerStep()

	local popup = self:_popup()
	local asking = popup ~= nil and popup:isOpen()

	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position
	local reach = SellConfig.Bubble.MaxDistance

	for _, lot in self._lots do
		if asking or not eye or (eye - lot.pad.Position).Magnitude > reach then
			self:_setShown(lot, false)
		else
			self:_refresh(lot)
		end
	end
end

-- === A lot arriving and leaving =============================================

function SellController._bind(self, model: Model)
	if self._lots[model] or not model:IsA("Model") then
		return
	end

	local pad = model:FindFirstChild(SellConfig.Names.Pad, true)
	local anchor = model:FindFirstChild(SellConfig.Names.BubbleAnchor, true)
	if not (pad and pad:IsA("BasePart") and anchor and anchor:IsA("Attachment")) then
		--[[ A lot whose subtree has not arrived. It should not be reachable — the lot is
			`ModelStreamingMode.Atomic` (note 4) — and it is checked because the failure it guards
			against is silent: a sign bound to nothing, over a lot that looks finished. ]]
		self.log:warn(string.format("Sell lot %s arrived without its pad — not dressed.", model.Name))
		return
	end

	local lot: Lot = {
		model = model,
		pad = pad,
		gui = nil :: any,
		panel = nil :: any,
		caption = nil :: any,
		body = nil :: any,
		price = nil :: any,
		shown = false,
		trove = Trove.new(),
	}

	self._lots[model] = lot
	self:_buildSign(lot, anchor)
end

function SellController._unbind(self, model: Instance)
	local lot = self._lots[model]
	if not lot then
		return
	end
	self._lots[model] = nil
	lot.trove:Destroy()
end

-- === Lifecycle ==============================================================

SellController:withRemoteEvents({
	{
		OpenSellPicker = function()
			local picker = Shard.get("StartCarController")
			if picker then picker:openForSell() end
		end,
		SellResult = function(reason: string, price: number)
			SellController:_onResult(reason, price)
		end,
	},
	--[[ DECLARED BY NAME, and it has to be: the table form above CONNECTS a handler, and the string
		form is the only one that hands back a handle to fire with. `getRemoteEvent("RequestSell")` is
		nil without this line and a SELL IT does nothing at all, silently — the same pairing
		`OfflineController` makes for its own claim. ]]
	"RequestSell",
})

SellController:withLifecycle({
	init = function(self)
		self._lots = {} :: { [Instance]: Lot }
		self._since = 0
		--- The car the panel is currently asking about, or "" for no question out. It is a KEY rather
		--- than the model because the model can be destroyed under us and a key cannot.
		self._offerKey = ""
		self._popupController = nil
		self._gui = nil :: Instance?
		self._trove = Trove.new()
	end,

	start = function(self)
		if not SellConfig.Enabled then
			return
		end

		task.spawn(function()
			local player = Players.LocalPlayer
			self._gui = player:WaitForChild("PlayerGui")

			for _, model in CollectionService:GetTagged(SellConfig.Tag) do
				self:_bind(model :: Model)
			end
			self._trove:Add(CollectionService:GetInstanceAddedSignal(SellConfig.Tag):Connect(function(model)
				self:_bind(model :: Model)
			end))
			self._trove:Add(CollectionService:GetInstanceRemovedSignal(SellConfig.Tag):Connect(function(model)
				self:_unbind(model)
			end))

			--[[ `Heartbeat` and not `RenderStepped`: what this drives is a billboard's TEXT and a panel
				that opens five times a second at most, neither of which is re-derived per frame by
				anything. The accumulator inside means the work happens at `PollInterval` either way, and
				RenderStepped would only move the same work earlier in the frame. ]]
			self._trove:Add(RunService.Heartbeat:Connect(function(dt)
				self:_step(dt)
			end))
		end)
	end,
})

SellController:withCleanup(function()
	for model in SellController._lots or {} do
		SellController:_unbind(model)
	end
	if SellController._trove then
		SellController._trove:Destroy()
	end
end)

return SellController
