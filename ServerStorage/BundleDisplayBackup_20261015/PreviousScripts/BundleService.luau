--[[
	BundleService  (server — grants the shop's car bundles off their receipts)
	--------------------------------------------------------------------------
	`ShopConfig.Bundles` says what is in each box; `DevProductsHandler` calls `grantBundle` with the
	receipt's bundle. Every car goes through `GarageService.awardCar`, the same path a banked car
	takes, so the catalogue ticks, the NEW BEST screen plays for a car that beats the record, and a
	full inventory auto-sells with its own notice (`InventoryLimitController`).

	It also dresses the lobby's bundle stands (`ShopConfig.BundleStand`, 2026-10-15): the cars on
	display and a prompt that only opens Roblox's purchase window. The sale is still the receipt's.

	RAISE BEFORE THE FIRST GRANT, NEVER AFTER IT. A raise is how a receipt asks Roblox to deliver it
	again (`DevProductsHandler`'s `mustGrant`), and a retry runs the WHOLE bundle again. So everything
	that can fail as a whole (no garage, no profile yet) is waited for or raised up front, and once the
	first car is in, a later failure is logged and skipped: one missing car beats three duplicated
	ones. In practice the up-front wait is the only failure there is, since `awardCar` only refuses a
	body off the roster, which a config typo would show on the first test purchase.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local ShopConfig = require(ReplicatedStorage.shared.Configs.ShopConfig)
--- The profile wait is the cash packs' (`CashConfig.GrantWait`), for `grantCash`'s reason.
local CashConfig = require(ReplicatedStorage.shared.Configs.CashConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
--- The display car's pose on a stand is the market's (`CarDealConfig.Car`), a CONFIG, as the other stands take it.
local CarDealConfig = require(ReplicatedStorage.shared.Configs.CarDealConfig)
local CarDisplay = require(ReplicatedStorage.shared.Modules.CarDisplay)
local Data = require(script.Parent.Parent.Data)

local BundleService = Shard.new("BundleService"):withDependencies({ "GarageService" })

--[[ Public (`DevProductsHandler`): pay one bundle in. YIELDS for the profile and RAISES if it never
	comes (the receipt is then retried); after that it does not raise (header). ]]
function BundleService.grantBundle(self, player: Player, bundle: ShopConfig.Bundle, profile: any?)
	local Garage = Shard.get("GarageService")
	if not Garage then
		error("No GarageService, so a bundle receipt cannot be paid in.")
	end
	--- WAIT, DO NOT TEST: `CashService.grantCash`'s note. A grant against an uncached profile is lost.
	local deadline = os.clock() + CashConfig.GrantWait
	while not Garage:isProfileReady(player) do
		if player.Parent ~= Players then
			error(string.format("%s left before their %s could be paid in.", player.Name, bundle.Key))
		end
		if os.clock() > deadline then
			error(string.format("%s's profile never arrived, so their %s was not paid in.", player.Name, bundle.Key))
		end
		task.wait()
	end

	for _, body in bundle.Cars do
		local outcome = Garage:awardCar(player, GarageConfig.TierOfBody[body], body, nil, nil, bundle.Key)
		if outcome == "rejected" then
			self.log:warn(string.format("%s's %s could not give a %s (not on the roster?); the rest was paid.", player.Name, bundle.Key, body))
		end
	end
	if bundle.Cash > 0 then
		Garage:addCash(player, bundle.Cash)
	end
	--- A once-only bundle is recorded, so the shop and the stand show it OWNED (`Bundle.OncePerPlayer`).
	if bundle.OncePerPlayer and profile then
		local stand = ShopConfig.BundleStand
		local bought = profile:Get(stand.BoughtProfileKey)
		bought = if type(bought) == "table" then table.clone(bought) else {}
		bought[bundle.Key] = true
		profile:Set(stand.BoughtProfileKey, bought)
		self:_publishBought(player, bought)
	end
	self.log:info(string.format("%s bought the %s.", player.Name, bundle.Key))
end

--- The once-only bundles a player owns, onto `BundleStand.BoughtAttribute` as "Key,Key".
function BundleService._publishBought(self, player: Player, bought: unknown)
	local keys = {}
	if type(bought) == "table" then
		for key, owned in bought do
			if owned == true and type(key) == "string" then
				table.insert(keys, key)
			end
		end
	end
	player:SetAttribute(ShopConfig.BundleStand.BoughtAttribute, table.concat(keys, ","))
end

-- === The lobby stands =======================================================

--[[ AN AUTHORED PODIUM SET (2026-10-15, Aleafo's `Map.CarsPodiumDisplay`): podium models named
	`Podium_01`, `Podium_02`.. anywhere under the stand, each holding a `Placeholder_<car>` model and a
	`CarInfoTerminal` name plate. Turned into the stand's own convention, so everything after reads it
	the same: a hidden `CarSpot<n>` per podium, in name order, standing where the placeholder stood
	and facing the way it faced (`ShopConfig.BundleStand.PodiumYaw` turns them all if that was not the
	car's nose), and the placeholder removed. Returns each podium's name plate labels by podium number,
	for `_dress` to write the car on show into; a "FEATURED" label is left alone. A stand that already
	has `CarSpot1`, or has no podiums, is left as it is (empty result). ]]
function BundleService._podiumSpots(self, stand: Model): { [number]: { TextLabel } }
	local cfg = ShopConfig.BundleStand
	local plates = {}
	if stand:FindFirstChild(cfg.SpotPrefix .. 1) then
		return plates
	end
	--- The tagged model may BE one podium (each podium its own bundle), or hold several.
	local isPodium = function(item: Instance): boolean
		return item:IsA("Model") and string.match(item.Name, "^" .. cfg.PodiumPattern .. "$") ~= nil
	end
	local podiums = {}
	if isPodium(stand) then
		table.insert(podiums, stand)
	else
		for _, item in stand:GetDescendants() do
			if isPodium(item) then
				table.insert(podiums, item)
			end
		end
	end
	table.sort(podiums, function(a, b)
		return a.Name < b.Name
	end)
	for index, podium in podiums do
		local placeholder = nil
		for _, child in podium:GetChildren() do
			if child:IsA("Model") and string.sub(child.Name, 1, #cfg.PlaceholderPrefix) == cfg.PlaceholderPrefix then
				placeholder = child
				break
			end
		end
		if not placeholder then
			self.log:warn(string.format("%s has no %s model; its podium shows no car.", podium:GetFullName(), cfg.PlaceholderPrefix))
			continue
		end
		local box, size = placeholder:GetBoundingBox()
		local look = placeholder:GetPivot().LookVector * Vector3.new(1, 0, 1)
		local bottom = box.Position - Vector3.yAxis * (size.Y / 2)
		local spot = Instance.new("Part")
		spot.Name = cfg.SpotPrefix .. index
		spot.Size = Vector3.new(8, 1, 18)
		spot.CFrame = CFrame.lookAt(bottom, bottom + (if look.Magnitude > 1e-3 then look.Unit else Vector3.zAxis))
			* CFrame.Angles(0, math.rad(cfg.PodiumYaw), 0)
			+ Vector3.yAxis * 0.5
		spot.Anchored, spot.Transparency = true, 1
		spot.Parent = stand
		placeholder:Destroy()

		local labels = {}
		local terminal = podium:FindFirstChild(cfg.TerminalName, true)
		for _, item in (if terminal then terminal:GetDescendants() else {}) do
			if item:IsA("TextLabel") and string.upper(item.Text) ~= "FEATURED" then
				table.insert(labels, item)
			end
		end
		plates[index] = labels
	end
	return plates
end

--[[ Dress one bundle stand (`ShopConfig.BundleStand`): the bundle's cars parked on its `CarSpot`s,
	the same anchored display car the podiums use, the same for every viewer; and the prompt, which
	only OPENS Roblox's purchase window on the pressing client (`BundleStandController`). Nothing is
	sold here: the receipt is `grantBundle`'s, so a stand cannot pay out anything a purchase did not.
	A stand naming no known bundle, or a spot missing, is logged and left with what it has: the
	failure mode of a stand is an emptier stand. ]]
function BundleService._dress(self, stand: Instance)
	local cfg = ShopConfig.BundleStand
	if not stand:IsA("Model") or self._dressed[stand] then
		return
	end
	self._dressed[stand] = true
	--- Atomic so a client gets the stand with its sign part and spots, never in pieces.
	stand.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	CarDisplay.markerFrame(stand:FindFirstChild(cfg.SignName))

	--[[ WHICH BUNDLES: `Bundles` ("StarterBundle,JDMBundle,SupercarBundle"), cycled; or the single
		`Bundle` it started with (2026-10-15, Aleafo: "make the cars cycle"). Unknown keys are skipped. ]]
	local listed = stand:GetAttribute(cfg.ListAttribute)
	local keys = {}
	if type(listed) == "string" then
		for key in string.gmatch(listed, "[^,%s]+") do
			table.insert(keys, key)
		end
	else
		table.insert(keys, stand:GetAttribute(cfg.Attribute))
	end
	local bundles = {}
	for _, key in keys do
		local bundle = ShopConfig.bundleOf(key)
		if bundle then
			table.insert(bundles, bundle)
		end
	end
	if #bundles == 0 then
		self.log:warn(string.format("%s names no bundle (attribute %s or %s); it stays bare.", stand:GetFullName(), cfg.ListAttribute, cfg.Attribute))
		return
	end

	--- An authored podium set (`Podium_01`.. with placeholders) is turned into `CarSpot`s first.
	local plates = self:_podiumSpots(stand)

	--- The podiums, in order, and how many there are; a bundle with fewer cars is centred on them.
	local frames = {}
	while true do
		local spot = stand:FindFirstChild(cfg.SpotPrefix .. (#frames + 1))
		local frame = CarDisplay.markerFrame(spot)
		if not frame then
			break
		end
		table.insert(frames, frame)
	end
	if #frames == 0 then
		self.log:warn(string.format("%s has no %s1; it stays bare.", stand:GetFullName(), cfg.SpotPrefix))
		return
	end

	--[[ SLIDES (2026-10-15). What the stand shows at one moment: one bundle's cars, as many as there
		are podiums, centred. A bundle that fits is one slide; one with more cars than podiums is split
		into several (a single podium showing the JDM Bundle is three slides, one car each), and the
		stand cycles through every slide of every bundle it names, `CycleSeconds` each. EVERY SLIDE IS
		BUILT ONCE, then shown by parenting, so a cycle swaps models rather than cloning and painting
		them again. ]]
	local carCfg = CarDealConfig.Car
	type Slide = { bundle: ShopConfig.Bundle, models: { Model }, onPodium: { [number]: string } }
	local slides: { Slide } = {}
	for _, bundle in bundles do
		for from = 1, #bundle.Cars, #frames do
			local chunk = table.move(bundle.Cars, from, math.min(from + #frames - 1, #bundle.Cars), 1, {})
			local slide: Slide = { bundle = bundle, models = {}, onPodium = {} }
			local first = math.floor((#frames - #chunk) / 2) + 1
			for index, body in chunk do
				local podium = first + index - 1
				local frame = frames[podium]
				local model, offsets, extents = CarDisplay.build(body, nil, {
					rosterFolder = GarageConfig.Display.RosterFolderName,
					bodyFolder = GarageConfig.Display.BodyFolderName,
					hitBoxName = GarageConfig.Display.HitBoxName,
					name = "BundleCar" .. podium,
					castShadow = carCfg.CastShadow,
				})
				if frame and model then
					CarDisplay.place(offsets, CarDisplay.standOn(extents, frame.Position, frame.Position.Y, frame, carCfg.Lift))
					table.insert(slide.models, model)
					slide.onPodium[podium] = body
				else
					if model then
						model:Destroy()
					end
					self.log:warn(string.format("%s: no podium for %s of %s, or it is not on the roster; not shown.", stand:GetFullName(), body, bundle.Key))
				end
			end
			table.insert(slides, slide)
		end
	end

	--[[ AT DOOR HEIGHT ON THE MIDDLE PODIUM (2026-10-15, "the proximity prompt is too high up"). It hung
		off the `Sign` part, which sits over the cars, so the prompt floated up there with it. ]]
	local middle = stand:FindFirstChild(cfg.SpotPrefix .. math.ceil(#frames / 2)) :: BasePart
	local mount = Instance.new("Attachment")
	mount.Name = "PromptMount"
	mount.Parent = middle
	mount.WorldPosition = middle.Position + Vector3.yAxis * (cfg.PromptHeight - middle.Size.Y / 2)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = cfg.PromptName
	prompt.ActionText = cfg.ActionText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = cfg.MaxDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = mount

	--[[ Show one slide: its cars in, the last one's out, each podium's name plate saying its car (an
		empty podium's saying nothing), the prompt naming the bundle, and `CurrentAttribute` telling
		every client which board and price to draw and which product the press buys. ]]
	local showing = 0
	local function show(slideIndex: number)
		if showing ~= 0 then
			for _, model in slides[showing].models do
				model.Parent = nil
			end
		end
		showing = slideIndex
		local slide = slides[slideIndex]
		for _, model in slide.models do
			model.Parent = stand
		end
		for podium, labels in plates do
			local body = slide.onPodium[podium]
			local name = if body then string.upper(GarageConfig.displayName(body)) else ""
			for _, label in labels do
				label.Text = name
			end
		end
		prompt.ObjectText = slide.bundle.Title
		prompt.Enabled = ShopConfig.isSellable(slide.bundle)
		stand:SetAttribute(cfg.CurrentAttribute, slide.bundle.Key)
	end
	show(1)
	if #slides > 1 then
		task.spawn(function()
			while stand.Parent do
				task.wait(cfg.CycleSeconds)
				show(showing % #slides + 1)
			end
		end)
	end
end

BundleService:withLifecycle({
	init = function(self)
		self._dressed = {} :: { [Instance]: boolean }
	end,
	start = function(self)
		local cfg = ShopConfig.BundleStand
		--[[ The once-only bundles a player owns, published as their profile lands, so the shop and
			the stands draw OWNED from the first frame. `CodesService`'s profile handle pattern. Ahead
			of the stand switch below: the shop reads it whether or not the lobby has stands. ]]
		Shard.get("GarageService"):getSignal("ProfileReady"):Connect(function(player: Player)
			task.spawn(function()
				local ok, profile = pcall(function()
					return Data:GetProfileAsync(player)
				end)
				if ok and profile and player.Parent == Players then
					self:_publishBought(player, profile:Get(cfg.BoughtProfileKey))
				end
			end)
		end)
		if not cfg.Enabled then
			return
		end
		CollectionService:GetInstanceAddedSignal(cfg.Tag):Connect(function(stand)
			self:_dress(stand)
		end)
		for _, stand in CollectionService:GetTagged(cfg.Tag) do
			self:_dress(stand)
		end
	end,
})

return BundleService
