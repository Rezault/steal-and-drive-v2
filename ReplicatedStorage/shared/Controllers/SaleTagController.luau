--[[
	SaleTagController  (client)
	---------------------------
	THE CLICKABLE SALE TAG (2026-10-08). With E fully spent on place / pick up (`GarageConfig.Picker.
	Glass` has why), putting a car on or off sale needed a home that is not a second key. It is the tag
	over the car: on each of the OWNER's showroom podiums, a button above the car says the car's state
	(green FOR SALE or red NOT FOR SALE), and a tap or a click on it flips it. The state and the
	action are one object, on the car they are about, with no menu.

	It is the KIT'S OWN BUTTON since 2026-10-12 (`Modules/ArcadeKit`, the green one every kit page
	claims with, repainted red when the car is held back): its white and navy rims and its slash
	instead of the hand-made arcade pill, because it is a button and should look like the kit's.

	WHAT IT TALKS TO. Nothing new on the server: the press is the inventory screen's own path
	(`Dispatcher "InventoryFlag"` -> `DealershipController` -> `RequestSetCarFlag` ->
	`GarageService.setCarFlag`), so the server's checks, the buyer it sends away and the lot redraw all
	happen exactly as they do from there. The tag repaints from the broadcast that comes back (the
	`NotForSaleAttribute`), never from the press, so a refused change is visibly a change that did not
	happen.

	WHICH PODIUMS ARE MINE: the podium prompts the server tags (`GarageConfig.Picker.PromptTag`) carry
	their owner (`OwnerAttribute`) and sit on the podium's deck, whose slot model carries its
	`SlotIndex`. The workshop podium is skipped — nothing in it is ever for sale.

	EVERYBODY ELSE STILL SEES THE SERVER'S RED SIGN (`GarageService`'s NotForSaleSign). For the owner
	that sign is switched off locally on their own podiums, so they see one tag, not a tag and a sign.

	A gamepad cannot point at something in the world, so a controller player flips sale from the
	inventory screen, which stays. `GarageConfig.SaleTag.Enabled = false`: no tag, the sign as before.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local CustomizeConfig = require(ReplicatedStorage.shared.Configs.CustomizeConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local InventoryConfig = require(ReplicatedStorage.shared.Configs.InventoryConfig)
local ArcadeKit = require(ReplicatedStorage.shared.Modules.ArcadeKit)

local SaleTagController = Shard.new("SaleTagController")

--- The server's own sign over a held-back car; hidden for the owner on their own podiums.
local SERVER_SIGN = "NotForSaleSign"

type Tag = {
	deck: BasePart,
	slot: Model,
	index: number,
	gui: BillboardGui,
	button: GuiObject,
	label: TextLabel,
	hint: TextLabel,
	scale: UIScale,
}

--- The lot broadcast as bay -> car ID.
local function carsByBay(): { [number]: string }
	local out = {}
	for _, entry in GarageConfig.split(Players.LocalPlayer:GetAttribute(GarageConfig.LotAttribute)) do
		local bay, id = string.match(entry, "^(%d+):(.+)$")
		if bay and id then
			out[tonumber(bay) :: number] = id
		end
	end
	return out
end

--- The car IDs held back from sale, as a set.
local function heldBack(): { [string]: boolean }
	local out = {}
	for _, id in GarageConfig.split(Players.LocalPlayer:GetAttribute(InventoryConfig.NotForSaleAttribute)) do
		out[id] = true
	end
	return out
end

--- The slot model a deck belongs to: the nearest ancestor carrying a `SlotIndex`.
local function slotOf(deck: Instance): (Model?, number?)
	local node = deck.Parent
	while node and node ~= workspace do
		local index = node:GetAttribute(GarageConfig.SlotIndexAttribute)
		if node:IsA("Model") and type(index) == "number" then
			return node, index
		end
		node = node.Parent
	end
	return nil, nil
end

--[[ One podium's tag: a BillboardGui in PlayerGui (a billboard in the Workspace takes no clicks)
	adorned to the deck, holding the kit's button. ]]
function SaleTagController._build(self, deck: BasePart, slot: Model, index: number): Tag
	local cfg = GarageConfig.SaleTag
	local gui = Instance.new("BillboardGui")
	gui.Name = "SaleTag" .. index
	gui.Adornee = deck
	gui.Size = UDim2.fromScale(cfg.Size.X, cfg.Size.Y)
	gui.StudsOffsetWorldSpace = Vector3.new(0, deck.Size.Y / 2 + cfg.Height, 0)
	gui.MaxDistance = cfg.MaxDistance
	gui.LightInfluence = 0
	-- Not on top (2026-10-14): drawn through the upstairs floor, every ground-floor car's tag floated
	-- over the upper deck. Hung above the roof at `SaleTag.Height`, the car itself never hides it.
	gui.AlwaysOnTop = false
	gui.Active = true
	gui.ResetOnSpawn = false
	gui.Enabled = false
	--- The kit's parts are layered for Sibling; a new BillboardGui defaults to Global.
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local button, label = ArcadeKit.button(gui, "Claim", 0, 0, 1, 1)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	--- The state on top, big; how to change it under it, small.
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.4)
	label.Size = UDim2.fromScale(0.86, 0.5)
	local hint = ArcadeKit.text(button, 0.12, 0.64, 0.76, 0.24, ArcadeKit.White, true)
	hint.ZIndex = 7

	local tag: Tag = { deck = deck, slot = slot, index = index, gui = gui, button = button, label = label, hint = hint, scale = scale }
	if button:IsA("GuiButton") then
		button.Activated:Connect(function()
			self:_press(tag)
		end)
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	--- The server's red sign on this podium, off for the owner (header). It is rebuilt with every lot
	--- redraw, so it is caught as it arrives rather than once.
	local function hideSign(inst: Instance)
		if inst.Name == SERVER_SIGN and inst:IsA("BillboardGui") then
			inst.Enabled = false
		end
	end
	for _, inst in slot:GetDescendants() do
		hideSign(inst)
	end
	slot.DescendantAdded:Connect(hideSign)
	return tag
end

--- Flip the car on this podium, through the inventory's own path (header), with a punch on the tag.
function SaleTagController._press(self, tag: Tag)
	local id = carsByBay()[tag.index]
	if not id then
		return
	end
	local forSale = not heldBack()[id]
	--- `on` is the NotForSale flag: true takes the car off sale.
	Dispatcher:Publish("InventoryFlag", id, InventoryConfig.Keys.NotForSale, forSale)
	tag.scale.Scale = 0.85
	TweenService:Create(tag.scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local sounds = Shard.get("SoundController")
	if sounds then
		sounds:PlayRandom("UIClick")
	end
end

--- Every tag, from the broadcasts: shown over a car, coloured and worded by its state.
function SaleTagController._repaint(self)
	local cfg = GarageConfig.SaleTag
	local lot = carsByBay()
	local held = heldBack()
	local touch = UserInputService.PreferredInput == Enum.PreferredInput.Touch
	for _, tag in self._tags do
		local id = lot[tag.index]
		tag.gui.Enabled = id ~= nil and tag.deck.Parent ~= nil
		if id then
			local forSale = not held[id]
			ArcadeKit.paint(tag.button, if forSale then cfg.ForSaleColors else cfg.NotForSaleColors)
			tag.label.Text = if forSale then cfg.ForSaleText else cfg.NotForSaleText
			tag.hint.Text = if touch then cfg.TouchHint else cfg.ClickHint
		end
	end
end

--- A podium prompt arrived: if it is one of mine on a showroom podium, give that podium a tag.
function SaleTagController._watch(self, prompt: Instance)
	if not prompt:IsA("ProximityPrompt") or prompt:GetAttribute(GarageConfig.Picker.OwnerAttribute) ~= Players.LocalPlayer.UserId then
		return
	end
	local deck = prompt.Parent
	if not (deck and deck:IsA("BasePart")) or self._byDeck[deck] then
		return
	end
	local slot, index = slotOf(deck)
	if not (slot and index) or (CustomizeConfig.Enabled and index == CustomizeConfig.Bay.SlotIndex) then
		return
	end
	local tag = self:_build(deck, slot, index)
	self._byDeck[deck] = tag
	table.insert(self._tags, tag)
	--- A podium that goes away (a plot swap, the lot released) takes its tag with it.
	deck.AncestryChanged:Connect(function()
		if deck:IsDescendantOf(workspace) then
			return
		end
		tag.gui:Destroy()
		self._byDeck[deck] = nil
		local at = table.find(self._tags, tag)
		if at then
			table.remove(self._tags, at)
		end
	end)
	self:_repaint()
end

SaleTagController:withLifecycle({
	init = function(self)
		self._tags = {} :: { Tag }
		self._byDeck = {} :: { [BasePart]: Tag }
	end,

	start = function(self)
		if not (GarageConfig.SaleTag.Enabled and InventoryConfig.Enabled) then
			return
		end
		local tagName = GarageConfig.Picker.PromptTag
		for _, prompt in CollectionService:GetTagged(tagName) do
			self:_watch(prompt)
		end
		CollectionService:GetInstanceAddedSignal(tagName):Connect(function(prompt)
			self:_watch(prompt)
		end)
		local player = Players.LocalPlayer
		for _, attribute in { GarageConfig.LotAttribute, InventoryConfig.NotForSaleAttribute } do
			player:GetAttributeChangedSignal(attribute):Connect(function()
				self:_repaint()
			end)
		end
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
			self:_repaint()
		end)
	end,
})

return SaleTagController
