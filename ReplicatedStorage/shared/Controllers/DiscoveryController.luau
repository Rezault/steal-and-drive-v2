--[[
	DiscoveryController  (client)
	-----------------------------
	"NEW CAR DISCOVERED!" (2026-10-08, the polish pass). The first time a player gets a model they have
	never had, a kit panel (`Modules/ArcadeKit`) slides into the top-right corner with the car turning
	on a card in its rarity's colours, its name, the rarity word, and how much of the collection they
	have now found ("12 / 49 FOUND", on the kit's progress bar). Collecting was a number on the Index page nobody opened
	mid-session; this makes each new one a moment, and the count is the reason to go after the next.

	WHAT COUNTS AS NEW is the server's own found list (`CarCatalogue.FoundAttribute`), read as BODIES:
	the first value this client sees is the baseline and shows nothing, and every body that joins it
	after is a discovery. Several at once (an offline catch-up, a gift) queue and play one after another.

	NEVER OVER A RUN. A bank awards its car while the run is still on screen, so a discovery that lands
	mid-run waits for the trip home to finish (`RaceConfig.ReturnedEvent`) and plays in the lobby. The
	NEW BEST cutscene holds every screen off while it plays (`ShowcaseController._holdGui`).

	=== IT WAITS FOR NEW BEST NOW — 2026-10-08 ===
	WAS: the card counted on that hold — "a card under it simply appears once it ends". It did not: the
	hold hides the card's ScreenGui but the card's own `Hold` timer kept running, and a first-ever car is
	very often also a new best, so the card played its five seconds unseen under the cutscene (the
	owner: "i didnt get to see the new index card thing because the NEW BEST played"). IS: the card does
	not start while `ShowcaseController:busy()` (playing, or a car waiting for it), and plays on
	`ShowcaseEnded`. A cutscene that starts while a card is already up sends that card back to the
	front of the queue, to play again in full after.

	=== IT TAKES ITS TURN IN THE NOTICE LANE, 2026-10-13 ===
	WAS: on a PC it simply appeared top-right whatever else was up, so the trip home could show it
	beside the carry card and the run summary at once (Rezault: "a lot happening on the screen"). IS:
	it joins the lane's queue on every device (`NoticeLaneConfig.MaxVisible`), so it waits while the
	lane is full. On a phone the lane also places it; on a PC it still rests top-right, unplaced.

	Its words, timing and switch live in `InventoryConfig.Discovery`; `Enabled = false` shows nothing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local InventoryConfig = require(ReplicatedStorage.shared.Configs.InventoryConfig)
local RaceConfig = require(ReplicatedStorage.shared.Configs.RaceConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local ArcadeKit = require(ReplicatedStorage.shared.Modules.ArcadeKit)
local CarCatalogue = require(ReplicatedStorage.shared.Modules.CarCatalogue)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)
local NoticeLane = require(ReplicatedStorage.shared.Modules.NoticeLane)
local NoticeLaneConfig = require(ReplicatedStorage.shared.Configs.NoticeLaneConfig)

local DiscoveryController = Shard.new("DiscoveryController")

--[[ THE BOTTOM-RIGHT CORNER, NOT THE NOTICE LANE (2026-10-08, the owner: "it gets caught in another
	frame"). It first lived in the left-side notice lane, which it shares with the carry card, the run
	summary and the offline line, and a discovery landing right after a run lands exactly when those are
	up. The lobby's bottom-right is empty — the cash is bottom-left, the hotbar bottom-centre — so the card
	slides in from the right edge there. Height is a share of the screen and the width follows it
	(`ASPECT`), so the card keeps its shape on a phone.

	=== TOP-RIGHT, NOT BOTTOM-RIGHT — 2026-10-08 ===
	The bottom-right was empty on a PC and is exactly where a phone draws the jump button and the
	thumb's whole working area (the owner: "mobile controls would get cooked"). The top-right, under
	the Roblox top bar, is clear on every device, so the card rests there now, still sliding in from
	the right edge. `TOP` sits it below the top bar's inset (the gui ignores the inset). ]]
--- 2026-10-13: was 0.17. Smaller with the rest of the lane's cards (the U2 pass on post-run notices).
local CARD_HEIGHT = 0.12
local ASPECT = 2.7
--- Where it rests (its TOP-right corner, screen share) and where it waits off screen.
local TOP = 0.11
local SHOWN = UDim2.fromScale(0.985, TOP)
local HIDDEN = UDim2.fromScale(1.6, TOP)
local SLIDE_IN = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

--[[ === ON THE KIT'S PROMPT PANEL, 2026-10-12 =============================================
	WAS the hand-made arcade strip with a dark well and a white pill. IS the kit's own parts
	(`Modules/ArcadeKit`): the prompt panel the carry and weather notices are cut from, its header
	saying what happened; in its white body the car turning on a kit day card faced in its rarity's
	gradient, the car's name, the rarity word in that same gradient, and the collection as the kit's
	progress bar with the count on it. ]]
local HEADER = 0.27
--- The body's share of the panel, and from it the body's own shape, for the car card's aspect.
local BODY_ASPECT = ASPECT * (1 - 2 * 0.053 / ASPECT) / (1 - HEADER - 0.053)
local CAR_H = 0.84
local CAR_W = CAR_H * 1.35 / BODY_ASPECT
local COLUMN_X = 0.03 + CAR_W + 0.03

function DiscoveryController._build(self)
	local gui = Instance.new("ScreenGui")
	gui.Name = "CarDiscovered"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 21
	--- The kit's parts are layered for Sibling; a new ScreenGui defaults to Global.
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(1, 0)
	card.Size = UDim2.fromScale(CARD_HEIGHT * ASPECT, CARD_HEIGHT)
	card.Position = HIDDEN
	card.BackgroundTransparency = 1
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = ASPECT
	ratio.DominantAxis = Enum.DominantAxis.Height
	ratio.Parent = card
	card.Visible = false
	card.Parent = gui
	if NoticeLaneConfig.Enabled then
		--- Placed by the lane on a phone; on a PC it only queues there and keeps its corner (header).
		self._placed = NoticeLane.compact()
		self._lane = NoticeLane.join(card, NoticeLaneConfig.Order.Discovery, true, ASPECT, self._placed)
	end
	local _, title, body = ArcadeKit.panel(card, HEADER, ASPECT)
	title.Text = InventoryConfig.Discovery.Title
	self._title = title

	--- The car, turning, on a day card in its rarity's gradient.
	local carHolder = Instance.new("Frame")
	carHolder.AnchorPoint = Vector2.new(0, 0.5)
	carHolder.Position = UDim2.fromScale(0.03, 0.5)
	carHolder.Size = UDim2.fromScale(CAR_W, CAR_H)
	carHolder.BackgroundTransparency = 1
	carHolder.ZIndex = 3
	carHolder.Parent = body
	local carFace = ArcadeKit.card(carHolder, { aspect = 1.35 })
	local view = CarViewport.new(carFace, "DiscoveredCar")
	view.Position = UDim2.fromScale(0.02, 0.04)
	view.Size = UDim2.fromScale(0.96, 0.92)
	view.ZIndex = 4

	local width = 0.97 - COLUMN_X
	local name = ArcadeKit.text(body, COLUMN_X, 0.07, width, 0.36, ArcadeKit.White, true)
	name.TextXAlignment = Enum.TextXAlignment.Left
	local rarity = ArcadeKit.heading(body, COLUMN_X, 0.43, width, 0.22)
	rarity.TextXAlignment = Enum.TextXAlignment.Left
	local track, fill = ArcadeKit.bar(body, COLUMN_X, 0.7, width, 0.2)
	self._track = track
	local count = ArcadeKit.text(body, COLUMN_X, 0.69, width, 0.22, ArcadeKit.White, true)
	count.ZIndex = 8

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self._card, self._view, self._carFace, self._name, self._rarity, self._fill, self._count =
		card, view, carFace, name, rarity, fill, count
end

--- Play the queue, one card at a time, unless a run is on (the trip home's landing restarts it).
function DiscoveryController._next(self)
	if self._showing or self._racing or #self._queue == 0 or not self._card or self:_showcaseBusy() then
		return
	end
	local entry = table.remove(self._queue, 1)
	local body = entry.body
	self._showing = true
	self._token += 1
	local token = self._token
	self._current = entry

	local cfg = InventoryConfig.Discovery
	local word, band = CarRarity.of(body)
	local face = ArcadeKit.rarityFace(band)
	self._name.Text = string.upper(GarageConfig.displayName(body))
	self._rarity.Text = string.upper(word ~= "" and word or "NEW")
	ArcadeKit.paint(self._rarity, face)
	ArcadeKit.paint(self._carFace, face)
	--- A new world's free starter says where it is free; a discovery shows the collection count.
	self._title.Text = if entry.world then cfg.FreeTitle else cfg.Title
	self._track.Visible = entry.world == nil
	if entry.world then
		self._count.Text = string.format(cfg.FreeFormat, string.upper(entry.world))
	else
		local found, total = 0, #CarCatalogue.Roster
		for _ in self._found or {} do
			found += 1
		end
		found = math.min(found, total)
		self._count.Text = string.format(cfg.FoundFormat, found, total)
		self._fill.Size = UDim2.fromScale(if total > 0 then math.max(found / total, 0.04) else 0, 1)
	end
	CarViewport.set(self._view, body, { aspect = 1.35 * 0.96 / 0.92 })

	--[[ Everything from here runs when the card is really up, which with a full lane is after the
		cards ahead of it have gone: the slide (when the lane is not placing it), the sound, the hold. ]]
	local function shown()
		if token ~= self._token then
			return
		end
		self._card.Visible = true
		if not (self._lane and self._placed) then
			self._card.Position = HIDDEN
			TweenService:Create(self._card, SLIDE_IN, { Position = SHOWN }):Play()
		end
		local sounds = Shard.get("SoundController")
		if sounds then
			sounds:PlayNamed(cfg.Sound.Group, cfg.Sound.Name)
		end
		task.delay(cfg.Hold, function()
			if token ~= self._token then
				return
			end
			local function finished()
				if token ~= self._token then
					return
				end
				self._card.Visible = false
				self._showing = false
				self._current = nil
				self:_next()
			end
			if self._lane and self._placed then
				self._lane:hide(finished)
				return
			end
			--- Its slot goes as the slide starts, the way a placed card's does.
			if self._lane then
				self._lane:hide()
			end
			local out = TweenService:Create(self._card, SLIDE_OUT, { Position = HIDDEN })
			out.Completed:Once(finished)
			out:Play()
		end)
	end
	if self._lane then
		--- Hidden until its turn: `shown` switches it on as the lane brings it up.
		self._card.Visible = false
		self._lane:show(shown)
	else
		shown()
	end
end

--- Whether the NEW BEST cutscene has (or is about to have) the screen. No showcase: never busy.
function DiscoveryController._showcaseBusy(self): boolean
	local showcase = Shard.get("ShowcaseController")
	return showcase ~= nil and showcase:busy()
end

--[[ A cutscene took the screen with a card up: put that card back at the front of the queue and park
	it off screen, so it plays again whole once the cutscene ends (header). Called off the card's own
	ScreenGui being switched off, which is exactly what the cutscene's hold does to it. ]]
function DiscoveryController._interrupt(self)
	if not (self._showing and self._current) then
		return
	end
	self._token += 1
	table.insert(self._queue, 1, self._current)
	self._current = nil
	self._card.Visible = false
	if self._lane then
		self._lane:hide()
	end
	self._card.Position = HIDDEN
	self._showing = false
end

--- The found list moved: every body new to it is a discovery. The first read is the baseline.
function DiscoveryController._onFound(self)
	local now = CarCatalogue.parseFound(Players.LocalPlayer:GetAttribute(CarCatalogue.FoundAttribute))
	if self._found == nil then
		self._found = now
		return
	end
	for body in now do
		if not self._found[body] then
			table.insert(self._queue, { body = body })
		end
	end
	self._found = now
	self:_next()
end

--[[ A NEW WORLD'S FREE CAR (2026-10-15, Aleafo: "we didn't add the popup of the new free car with the
	new world?"). Every world starts its runs in its own starter (`WorldConfig.startBodyFor`), free to
	drive, and unlocking a world said nothing about it. Off the highest-unlocked broadcast
	(`WorldConfig.UnlockAttribute`), the first read a baseline as `_onFound`'s is, so a join shows
	nothing; each world that joins it after queues one "NEW FREE CAR!" card on this same card,
	waiting out a run and the NEW BEST screen exactly as a discovery does. ]]
function DiscoveryController._onUnlock(self)
	local highest = tonumber(Players.LocalPlayer:GetAttribute(WorldConfig.UnlockAttribute))
	if not highest then
		return
	end
	local before = self._unlocked
	self._unlocked = highest
	if before == nil or highest <= before then
		return
	end
	for world = before + 1, highest do
		table.insert(self._queue, { body = WorldConfig.startBodyFor(world), world = WorldConfig.shortName(world) })
	end
	self:_next()
end

DiscoveryController:withRemoteEvents({
	{
		RaceStart = function()
			DiscoveryController._racing = true
			DiscoveryController:_interrupt()
		end,
	},
})

DiscoveryController:withLifecycle({
	init = function(self)
		self._found = nil :: { [string]: boolean }?
		--- `world` set: a new world's free starter (`_onUnlock`); nil: a discovery.
		self._queue = {} :: { { body: string, world: string? } }
		self._unlocked = nil :: number?
		self._showing = false
		self._racing = false
		self._token = 0
		self._current = nil :: { body: string, world: string? }?
	end,

	start = function(self)
		if not InventoryConfig.Discovery.Enabled then
			return
		end
		local player = Players.LocalPlayer
		--- Seeded only once the attribute exists, so a profile that lands late is still a baseline.
		if player:GetAttribute(CarCatalogue.FoundAttribute) ~= nil then
			self:_onFound()
		end
		player:GetAttributeChangedSignal(CarCatalogue.FoundAttribute):Connect(function()
			self:_onFound()
		end)
		--- The free starter of a newly unlocked world (`_onUnlock`). Seeded the same way.
		self:_onUnlock()
		player:GetAttributeChangedSignal(WorldConfig.UnlockAttribute):Connect(function()
			self:_onUnlock()
		end)
		--- Home from a run: anything found during it plays now, in the lobby.
		Dispatcher:Subscribe(RaceConfig.ReturnedEvent, function()
			self._racing = false
			-- Let every return subscriber release its held summary before checking the queue.
			task.defer(function()
				self:_next()
			end)
		end)
		Dispatcher:Subscribe("ShowcaseEnded", function()
			self:_next()
		end)
		--- Built off the start path: the kit's parts arrive with the UI, after the join screen
		--- (`ArcadeKit.shelf`). Anything found meanwhile is queued and plays once it is up.
		task.spawn(function()
			self:_build()
			local gui = self._card:FindFirstAncestorOfClass("ScreenGui")
			gui:GetPropertyChangedSignal("Enabled"):Connect(function()
				if not gui.Enabled then
					self:_interrupt()
				end
			end)
			self:_next()
		end)
	end,
})

return DiscoveryController
