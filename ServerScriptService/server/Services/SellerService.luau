--[[
	SellerService  (server — rolls, stands and ratifies the seller at your kerb)
	------------------------------------------------------------------------------
	A car pulls up in front of your dealership with a seller beside it and a price on it
	(`SellerConfig` has the design). This file decides when, rolls the car and the price, stands the
	car and the person, and takes the money.

	THE SERVER DOES THE STANDING AND THE CLIENT DOES THE MOVING. The car is a `CarDisplay` model,
	anchored, put straight onto the spot. The drive in and out is a tween each client plays off two
	timestamps (`Attributes.ArriveAt` / `LeaveAt`, `SellerController`). Moving it here would replicate
	every step at network rate and stutter. The seller rides in the driver's seat (`SellerConfig.Seat`,
	`_seatRoot` / `_pose`): seated when the car is put down, which the client carries along with
	its tween, stood beside the car once the tween has had time to end, and seated again before
	the car pulls away.

	TRUST: the client sends nothing but BUY or DECLINE about its own seller (`_answer`). Body, tier,
	paint and price are server state read back off the model's attributes this file wrote; the
	visit is looked up by the sender, so only the owner can answer; the price is
	checked against the cash the server holds. The purchase is `CarDealService._onTriggered`'s, step
	for step (pay, award, refund a rejected award), because that order is the one that cannot charge
	for nothing. The price floor (`SellerConfig.floorHolds`) is checked at start-up, and a broken
	floor turns the feature off rather than opening a money printer.

	ONE SELLER PER PLAYER, AT A TIME, AND ONLY IN THE LOBBY. A visit is not started mid-run, in the
	tutorial, or before the profile is ready; it is retried a little later instead. A seller already
	waiting when you start a run keeps waiting until it times out, which is the honest outcome:
	nothing about the offer changed.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local SellerConfig = require(ReplicatedStorage.shared.Configs.SellerConfig)
--- The car roll (`rollBody`) and the display car's pose (`Car`) are the market's: a CONFIG and not
--- `CarDealService`, which is off while this is on.
local CarDealConfig = require(ReplicatedStorage.shared.Configs.CarDealConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
--- The road's ladders and the world age weights, for the seller's own rarity roll (`_rollBody`).
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
local BalanceConfig = require(ReplicatedStorage.shared.Configs.BalanceConfig)
local CarDisplay = require(ReplicatedStorage.shared.Modules.CarDisplay)
local CarRoster = require(ReplicatedStorage.shared.Modules.CarRoster)
--- The crowd's idle clip, to add the seller's sit to: a CONFIG and not `CustomerService`, which only
--- stands the rig.
local CustomerConfig = require(ReplicatedStorage.shared.Configs.CustomerConfig)
--- The buyer's 😠, so a turned-down seller fumes with the same face (`_decline`). A CONFIG.
local BuyerConfig = require(ReplicatedStorage.shared.Configs.BuyerConfig)
local Data = require(script.Parent.Parent.Data)

local SellerService = Shard.new("SellerService"):withDependencies({ "GarageService", "PlotService", "CustomerService" })

SellerService:withRemoteEvents({
	{
		SellerAnswer = function(player: Player, accept: unknown)
			SellerService:_answer(player, accept)
		end,
		--[[ The owner's client: any NEW BEST screen is over, start the show. TRUST: it only moves the
			sender's own celebration earlier than the timeout would; nothing is paid on it. ]]
		SellerShowReady = function(player: Player)
			local visit = SellerService._shows[player]
			if visit then
				SellerService:_show(player, visit)
			end
		end,
	},
})

--[[ For `AnalyticsService` (2026-10-15). Since the sellers replaced the plaza market they are the
	only way to buy a car with cash, so "a car at the kerb" to "a car bought" is a funnel the
	dashboards have to be able to count. `info` is one table per visit and the same table on both:
	`{ body, tier, band, price, usual, first }`, `band` being `SellerConfig.Bands` key the price
	falls in and `first` whether the onboarding arrow was on it. ]]
SellerService:withSignals({
	--- (player: Player, info) : a seller pulled up and is waiting with a price.
	"SellerArrived",
	--[[ (player: Player, info, outcome: string, viewed: boolean, shortCash: boolean) : the visit is
		over, reported once. `outcome` is "Bought", "Declined", "Ignored" (it ran out and drove off)
		or "Gone" (the lot was released, the player left, or an admin replaced it). `viewed` is whether
		the owner opened the offer screen, `shortCash` whether they pressed BUY without the money. ]]
	"SellerResolved",
})

--- Seconds between passes of the visit loop. A visit's timing is in tens of seconds, so this only
--- has to be fine enough that a seller leaves within a moment of their clock reaching zero.
local TICK = 1

type Visit = {
	model: Model,
	frame: CFrame,
	expires: number,
	leaving: boolean,
	rig: Model?,
	anim: any?,
	--- Root frames for the two poses (`_pose`); nil `seatRoot` is `Seat.Enabled = false`.
	seatRoot: CFrame?,
	standRoot: CFrame?,
	--- The celebration has started (`_show`), so the ready signal and the timeout run it once.
	shown: boolean?,
	--- For `SellerResolved`: what was on offer, whether the owner opened the offer screen or pressed
	--- BUY short of cash, and whether the visit has been reported (`_resolve`).
	info: { [string]: any }?,
	viewed: boolean?,
	shortCash: boolean?,
	resolved: boolean?,
}

local ATTR = SellerConfig.Attributes
local NAMES = SellerConfig.Names

--[[ The plot's `SellerSpot`, as the frame the car stands on: feet on the part's bottom face, nose
	along its LookVector flattened. nil for a plot without one, logged once per plot. ]]
function SellerService._spotOf(self, plot: Model): CFrame?
	local spot = plot:FindFirstChild(SellerConfig.SpotName, true)
	if not (spot and spot:IsA("BasePart")) then
		if not self._warned[plot] then
			self._warned[plot] = true
			self.log:warn(string.format("%s has no %s part, so no sellers will pull up there.", plot.Name, SellerConfig.SpotName))
		end
		return nil
	end
	spot.Transparency, spot.CanCollide, spot.CanQuery, spot.CanTouch = 1, false, false, false
	local nose = spot.CFrame.LookVector * Vector3.new(1, 0, 1)
	if nose.Magnitude < 1e-3 then
		return nil
	end
	local origin = spot.Position - Vector3.yAxis * (spot.Size.Y / 2)
	return CFrame.lookAt(origin, origin + nose.Unit, Vector3.yAxis)
end

--[[ Can a visit start for this player right now? Each false is "try again in `RetrySeconds`",
	never "never". ]]
function SellerService._canVisit(self, player: Player): boolean
	local Garage = Shard.get("GarageService")
	local Race = Shard.get("RaceService")
	if not (Garage and Garage:isProfileReady(player)) then
		return false
	end
	if TutorialConfig.isUnfinished(player:GetAttribute(TutorialConfig.StepAttribute)) then
		return false
	end
	if Race and (Race:isRacing(player) or Race:isReturning(player)) then
		return false
	end
	return true
end

--[[ One body from the player's worlds (`SellerConfig.Rarity`). The WORLD is the market's draw, the
	newest unlocked weighted heaviest (`BalanceConfig.WorldWeightsByAge`), so nothing above it can come.
	Then the RARITY by the seller's own band weights, then the car within that band by the road's own
	relative weights, so a band's cars keep the road's order among themselves. With `Rarity` off, the
	market's roll, which is the road's odds exactly. ]]
function SellerService._rollBody(self, highest: number): (string?, number?)
	local rarity = SellerConfig.Rarity
	if not rarity.Enabled then
		return CarDealConfig.rollBody(self._rng, nil, highest)
	end
	local ages = BalanceConfig.WorldWeightsByAge
	local top = math.clamp(math.floor(highest), 1, #WorldConfig.Worlds)
	local total = 0
	for world = 1, top do
		total += ages[top - world + 1] or 0
	end
	local roll, world = self._rng:NextNumber() * total, top
	for index = top, 1, -1 do
		roll -= ages[top - index + 1] or 0
		if roll <= 0 then
			world = index
			break
		end
	end

	local tiers = TrafficConfig.tiersFor(world)
	if not tiers then
		return nil, nil
	end
	--- Each rung weighs its band's share times its own share of that band on the road.
	local bandTotals = {}
	for _, tier in tiers do
		bandTotals[tier.Band] = (bandTotals[tier.Band] or 0) + math.max(tier.Weight or 0, 0)
	end
	local weights, sum = {}, 0
	for index, tier in tiers do
		local bandTotal = bandTotals[tier.Band] or 0
		local weight = if bandTotal > 0 then (rarity.Weights[tier.Band] or 0) * math.max(tier.Weight or 0, 0) / bandTotal else 0
		weights[index] = weight
		sum += weight
	end
	local pick = self._rng:NextNumber() * sum
	for index, tier in tiers do
		pick -= weights[index]
		if pick <= 0 then
			local body = TrafficConfig.rollBody(self._rng, tier)
			return body, if body then WorldConfig.TierOfBody[body] else nil
		end
	end
	return nil, nil
end

--[[ Roll a car this player does not already own, from their highest unlocked world's weights. Bounded
	by `Visit.MaxRerolls`; nil when every roll was a car they have, and the visit is skipped. ]]
function SellerService._rollCar(self, player: Player): (string?, number?, number?)
	local Garage = Shard.get("GarageService")
	local highest = WorldConfig.highestUnlocked(player)
	for _ = 1, SellerConfig.Visit.MaxRerolls do
		local body, tier = self:_rollBody(highest)
		if not (body and tier) then
			return nil
		end
		local paint = PaintConfig.roll(self._rng, body)
		if not Garage:ownsModel(player, GarageConfig.carKey(body, paint)) then
			return body, tier, paint
		end
	end
	return nil
end

--- Has this player ever bought from a seller? Read off the profile; an unreadable profile is "no",
--- which only costs a returning player one extra arrow.
function SellerService._hasBought(self, player: Player): boolean
	local profile = self._profiles[player]
	return profile ~= nil and profile:IsActive() and profile:Get(SellerConfig.Onboarding.ProfileKey) == true
end

--[[ Start one visit: the car on the spot with every attribute written, and, after the drive-in
	has had time to finish, the seller beside it and the prompt on it. Returns false when it could
	not (no spot, no car, no rig on the roster) so the caller retries. `band` forces the price band
	(`SellerConfig.rollPrice`), for the admin panel. ]]
function SellerService._arrive(self, player: Player, band: unknown?): boolean
	local plot = Shard.get("PlotService"):getPlot(player)
	local frame = plot and self:_spotOf(plot)
	local body, tier, paint = self:_rollCar(player)
	if not (frame and body and tier and paint) then
		return false
	end
	local value = GarageConfig.valueOf(tier)
	if value <= 0 then
		return false
	end
	local price, usual = SellerConfig.rollPrice(self._rng, value, band)

	local carCfg = CarDealConfig.Car
	local car, offsets, extents = CarDisplay.build(body, paint, {
		rosterFolder = GarageConfig.Display.RosterFolderName,
		bodyFolder = GarageConfig.Display.BodyFolderName,
		hitBoxName = GarageConfig.Display.HitBoxName,
		name = NAMES.Car,
		castShadow = carCfg.CastShadow,
	})
	if not car then
		return false
	end
	local target = CarDisplay.standOn(extents, frame.Position, frame.Position.Y, frame, carCfg.Lift)
	CarDisplay.place(offsets, target)

	local model = Instance.new("Model")
	model.Name = NAMES.Model
	--- Atomic for `CarDealConfig.Tag`'s reason: the client tweens every part, so it needs them all.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	car.Parent = model

	--- The sign and the prompt hang off one invisible part at roof height, centred on the car.
	local boxCFrame, boxSize = car:GetBoundingBox()
	local anchor = Instance.new("Part")
	anchor.Name = NAMES.Anchor
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(boxCFrame.Position + Vector3.yAxis * (boxSize.Y / 2))
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Parent = model
	model.PrimaryPart = anchor

	local now = workspace:GetServerTimeNow()
	local expires = now + SellerConfig.Drive.ArriveSeconds + SellerConfig.Visit.WaitSeconds
	model:SetAttribute(ATTR.Owner, player.UserId)
	model:SetAttribute(ATTR.Body, body)
	model:SetAttribute(ATTR.Tier, tier)
	model:SetAttribute(ATTR.Paint, paint)
	model:SetAttribute(ATTR.Price, price)
	model:SetAttribute(ATTR.Usual, usual)
	model:SetAttribute(ATTR.ArriveAt, now)
	model:SetAttribute(ATTR.ExpiresAt, expires)
	model:SetAttribute(ATTR.Frame, frame)
	model:SetAttribute(ATTR.First, SellerConfig.Onboarding.Enabled and not self:_hasBought(player))
	model.Parent = self._folder
	CollectionService:AddTag(model, SellerConfig.Tag)

	--[[ The seller stands on the side of the car nearer the showroom, where the owner walks out
		from, facing away from the car. Derived from the plot's own centre rather than configured,
		so a spot on either side of the road is right without a second setting. ]]
	local side = frame.RightVector
	if plot and (plot:GetPivot().Position - frame.Position):Dot(side) < 0 then
		side = -side
	end
	local feet = frame.Position + side * ((extents.maxX - extents.minX) / 2 + 2)
	local standing = CFrame.lookAt(feet, feet + side)

	local visit: Visit = { model = model, frame = frame, expires = expires, leaving = false }
	self._visits[player] = visit
	self.log:info(string.format("A seller pulled up at %s's lot with a %s for %s (usual %s).",
		player.Name, body, GarageConfig.formatCash(price), GarageConfig.formatCash(usual)))
	visit.info = {
		body = body,
		tier = tier,
		band = SellerConfig.bandFor(price, usual).Key,
		price = price,
		usual = usual,
		first = model:GetAttribute(ATTR.First) == true,
	}
	self:getSignal("SellerArrived"):Fire(player, visit.info)

	--[[ IN THE DRIVER'S SEAT FOR THE DRIVE (`SellerConfig.Seat`). Built now, after the model is in
		the workspace, because an animator cannot load a clip on a rig that is not. The seat is
		written as an attribute relative to `frame`, so a client carries the person along with the
		car it is tweening whenever it streamed in. ]]
	local function spawnRig()
		local rig, anim = Shard.get("CustomerService"):standSeller(player, standing, model, self._clips)
		if not rig then
			return
		end
		rig.Name = NAMES.Rig
		model:SetAttribute(ATTR.UserId, rig:GetAttribute(ATTR.UserId))
		model:SetAttribute(ATTR.Name, rig:GetAttribute(ATTR.Name))
		local humanoid = rig:FindFirstChildOfClass("Humanoid")
		local root = rig.PrimaryPart
		visit.rig, visit.anim = rig, anim
		visit.standRoot = if humanoid and root then standing + Vector3.yAxis * (humanoid.HipHeight + root.Size.Y / 2) else nil
	end
	if SellerConfig.Seat.Enabled then
		visit.seatRoot = self:_seatRoot(body, target, extents, frame)
		model:SetAttribute(ATTR.Seat, frame:ToObjectSpace(visit.seatRoot))
		spawnRig()
		self:_pose(visit, false)
	end

	task.delay(SellerConfig.Drive.ArriveSeconds, function()
		if self._visits[player] ~= visit or visit.leaving then
			return
		end
		--- Out of the car: stood beside it, or, with `Seat` off, appearing there as before.
		if visit.rig then
			self:_pose(visit, true)
		elseif not SellerConfig.Seat.Enabled then
			spawnRig()
		end

		--[[ The prompt only OPENS the offer screen, on the owner's client (`SellerController`); the
			answer comes back on `SellerAnswer` (`_answer`). Hidden on every other client, and the
			answer is owner-checked here, `placeBuyer`'s rule, since `Enabled` is a client property. ]]
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = NAMES.Prompt
		prompt.ActionText = SellerConfig.Text.ActionText
		prompt.ObjectText = GarageConfig.formatCash(price)
		prompt.HoldDuration = SellerConfig.Prompt.HoldDuration
		prompt.MaxActivationDistance = SellerConfig.Prompt.MaxDistance
		prompt.RequiresLineOfSight = false
		--- The owner opened the offer screen (`SellerResolved`'s `viewed`). Goes with the prompt.
		prompt.Triggered:Connect(function(who: Player)
			if who == player then
				visit.viewed = true
			end
		end)
		--[[ ON THE SELLER, NOT THE ROOF (2026-10-15, "this prompt and the UI are overlapping"). The
			prompt's own card drew on the sign's anchor, right over the countdown strip. On the person
			standing beside the car it reads as "talk to them" and sits clear of the sign. With no
			person (no face to wear), it goes low on the car's side instead of on its roof. ]]
		local root = visit.rig and visit.rig.PrimaryPart
		if root then
			prompt.Parent = root
		else
			local low = Instance.new("Attachment")
			low.Name = "PromptMount"
			low.WorldPosition = frame.Position + Vector3.yAxis * 2
			low.Parent = anchor
			prompt.Parent = low
		end
	end)
	return true
end

--[[ Where the seated seller's root goes, in world space, for a car standing at `target` (the frame
	`CarDisplay.place` was given). The roster body's own `VehicleSeat`, re-expressed against `target`
	the way `CarDisplay.build` re-expresses every panel (against the source car's pivot), so the
	driver lands where that car's seat is. A body with no seat gets `Seat.Fallback`'s estimate.
	Faced down the road whatever the seat's own rotation, so a seat authored sideways cannot turn
	the driver. ]]
function SellerService._seatRoot(self, body: string, target: CFrame, extents: CarDisplay.Extents, frame: CFrame): CFrame
	local cfg = SellerConfig.Seat
	local source = CarRoster.car(body, GarageConfig.Display.RosterFolderName)
	local seat = source and source:FindFirstChildWhichIsA("VehicleSeat", true)
	local pan = if seat and source
		then (target * (source:GetPivot():Inverse() * seat.CFrame)).Position
		else (target * CFrame.new(
			(extents.minX + extents.maxX) / 2 - (extents.maxX - extents.minX) / 2 * cfg.Fallback.Side,
			extents.minY + cfg.Fallback.PanHeight,
			(extents.minZ + extents.maxZ) / 2
		)).Position
	return CFrame.lookAt(pan, pan + frame.LookVector) * cfg.Offset
end

--[[ Seat or stand the seller: `out` true stands them beside the car idling, false sits them in the
	driver's seat. `Out` is written BEFORE the move when sitting and after it when standing, so a
	client never moves a person the server has just stood up (`SellerController._step` leaves the
	rig alone while `Out` is set). ]]
function SellerService._pose(self, visit: Visit, out: boolean)
	local root = visit.rig and visit.rig.PrimaryPart
	if not root then
		return
	end
	if out then
		if visit.standRoot then
			root.CFrame = visit.standRoot
		end
		if visit.anim then
			visit.anim:play("Idle", 0.15)
		end
		visit.model:SetAttribute(ATTR.Out, true)
	else
		visit.model:SetAttribute(ATTR.Out, false)
		if visit.seatRoot then
			root.CFrame = visit.seatRoot
		end
		if visit.anim then
			visit.anim:play("Sit", 0)
		end
	end
end

--[[ The visit's one `SellerResolved`. Latched on the visit, so a decline and the drive-off after it,
	or a sale and the handover after it, report once. ]]
function SellerService._resolve(self, player: Player, visit: Visit, outcome: string)
	if visit.resolved or not visit.info then
		return
	end
	visit.resolved = true
	self:getSignal("SellerResolved"):Fire(player, visit.info, outcome, visit.viewed == true, visit.shortCash == true)
end

--[[ End a visit. `drive` true plays the leave (the person and the prompt go at once, the car after
	the tween); false removes it all now, for a sale or a released lot. Idempotent. ]]
function SellerService._end(self, player: Player, drive: boolean)
	local visit = self._visits[player]
	if not visit then
		return
	end
	--- Anything not already answered or timed out (a released lot, a leave, an admin) is "Gone".
	self:_resolve(player, visit, "Gone")
	self._visits[player] = nil
	self._nextAt[player] = os.clock() + SellerConfig.Visit.Interval
		+ self._rng:NextNumber(-SellerConfig.Visit.Jitter, SellerConfig.Visit.Jitter)
	visit.leaving = true
	if not drive then
		visit.model:Destroy()
		return
	end
	--- Back into the driver's seat to drive off (`SellerConfig.Seat`); with no seat, gone as before.
	if visit.rig and visit.seatRoot then
		self:_pose(visit, false)
	elseif visit.rig then
		visit.rig:Destroy()
	end
	local prompt = visit.model:FindFirstChild(NAMES.Prompt, true)
	if prompt then
		prompt:Destroy()
	end
	visit.model:SetAttribute(ATTR.LeaveAt, workspace:GetServerTimeNow())
	task.delay(SellerConfig.Drive.LeaveSeconds + 0.5, function()
		visit.model:Destroy()
	end)
end

--[[ The offer screen's answer (`SellerAnswer`). TRUST: the client says only BUY or DECLINE, and only
	about its OWN waiting seller. `_visits[player]` is keyed by the sender, so nobody can answer for
	another lot, and a seller still driving in (no prompt yet) cannot be answered. DECLINE sends the
	seller away at once, the person gone and the car pulling off. That is the owner's call to make,
	and the next seller is a full interval away as after any visit. ]]
function SellerService._answer(self, player: Player, accept: unknown)
	local visit = self._visits[player]
	if not visit or visit.leaving or not visit.model:FindFirstChild(NAMES.Prompt, true) then
		return
	end
	if accept == true then
		self:_buy(player, visit)
	elseif accept == false then
		self:_decline(player, visit)
	end
end

--[[ Turned down: the 😠 (the buyer's own, `BuyerConfig.Declined.Emoji`), a beat, then back in the car
	and away. The offer ends on the first line (no prompt, `leaving`), so it cannot be answered twice
	while the seller fumes, and the tick cannot time it out underneath the beat. ]]
function SellerService._decline(self, player: Player, visit: Visit)
	self:_resolve(player, visit, "Declined")
	visit.leaving = true
	local prompt = visit.model:FindFirstChild(NAMES.Prompt, true)
	if prompt then
		prompt:Destroy()
	end
	visit.model:SetAttribute(ATTR.Declined, true)
	if visit.rig then
		Shard.get("CustomerService"):emoteOver(visit.rig, BuyerConfig.Declined.Emoji, SellerConfig.Sold.DeclineHold + 0.4)
	end
	task.delay(SellerConfig.Sold.DeclineHold, function()
		if self._visits[player] == visit then
			self:_end(player, true)
		end
	end)
end

--[[ Bought, with the show (`SellerConfig.Sold`). The VISIT ends now: the next seller is scheduled
	and the kerb is free in the books. The MODEL stays for the show, held in `_shows` until the
	owner's client says any NEW BEST screen is done (`SellerShowReady`) or `MaxWaitSeconds` runs out,
	whichever is first. ]]
function SellerService._sold(self, player: Player, visit: Visit)
	self._visits[player] = nil
	self._nextAt[player] = os.clock() + SellerConfig.Visit.Interval
		+ self._rng:NextNumber(-SellerConfig.Visit.Jitter, SellerConfig.Visit.Jitter)
	visit.leaving = true
	local prompt = visit.model:FindFirstChild(NAMES.Prompt, true)
	if prompt then
		prompt:Destroy()
	end
	visit.model:SetAttribute(ATTR.Sold, true)
	self._shows[player] = visit
	task.delay(SellerConfig.Sold.MaxWaitSeconds, function()
		self:_show(player, visit)
	end)
end

--- A sold car still on the kerb for its show goes at once with its owner or their lot.
function SellerService._dropShow(self, player: Player)
	local show = self._shows[player]
	if show then
		self._shows[player] = nil
		show.model:Destroy()
	end
end

--[[ The celebration itself: cheer, 😄, the stamp on every client (`SoldAt`), then the fade
	(`FadeAt`) and the model gone. Idempotent: the ready signal and the timeout both call it. ]]
function SellerService._show(self, player: Player, visit: Visit)
	if visit.shown or not visit.model.Parent then
		return
	end
	visit.shown = true
	if self._shows[player] == visit then
		self._shows[player] = nil
	end
	local cfg = SellerConfig.Sold
	if visit.anim then
		visit.anim:play("Cheer", 0.15)
	end
	if visit.rig then
		Shard.get("CustomerService"):emoteOver(visit.rig, cfg.Emoji, cfg.HoldSeconds)
	end
	visit.model:SetAttribute(ATTR.SoldAt, workspace:GetServerTimeNow())
	task.delay(cfg.HoldSeconds, function()
		if not visit.model.Parent then
			return
		end
		visit.model:SetAttribute(ATTR.FadeAt, workspace:GetServerTimeNow())
		task.delay(cfg.FadeSeconds + 0.3, function()
			visit.model:Destroy()
		end)
	end)
end

--[[ The purchase. `CarDealService._onTriggered`'s order exactly (header): every refusal before the
	first write, then pay, award, refund a rejected award. A refusal for "too poor" opens the cash
	pack for the gap, as the market's did, and the seller keeps waiting. ]]
function SellerService._buy(self, player: Player, visit: Visit)
	if not (SellerConfig.Enabled and GarageConfig.Enabled) or self._visits[player] ~= visit or visit.leaving then
		return
	end
	local now = os.clock()
	if (self._cooldowns[player] or -math.huge) + SellerConfig.Prompt.Cooldown > now then
		return
	end
	self._cooldowns[player] = now

	local Garage = Shard.get("GarageService")
	if not (Garage and Garage:isProfileReady(player)) then
		return
	end
	local model = visit.model
	local body, tier, paint, price = model:GetAttribute(ATTR.Body), model:GetAttribute(ATTR.Tier), model:GetAttribute(ATTR.Paint), model:GetAttribute(ATTR.Price)
	if type(body) ~= "string" or type(tier) ~= "number" or type(price) ~= "number" or price <= 0 then
		return
	end
	if Garage:ownsModel(player, GarageConfig.carKey(body, PaintConfig.sanitize(body, paint))) then
		return
	end
	local cash = Garage:getCash(player)
	if cash < price then
		visit.shortCash = true
		local CashService = Shard.get("CashService")
		if CashService then
			CashService:offerTopUp(player, price - cash, string.format("a %s from a seller", body))
		end
		return
	end

	Garage:addCash(player, -price)
	--[[ EQUIPPED ON PURCHASE (2026-10-15, the owner: "make it so the player equips it if they buy
		it"). The `Seller` source puts the car in a hotbar slot AND in the buyer's hands, the bank's
		own outcome ("carried", `CarryConfig.Sources`). A full hotbar leaves it in the inventory
		unheld, the bank's rule: the held car is always a hotbar car. Not passed with `Handover`,
		which seats them in the real car instead. ]]
	local source = if SellerConfig.Sold.Handover then nil else "Seller"
	local outcome, _, awardedId = Garage:awardCar(player, tier, body, paint, nil, source)
	if outcome == "rejected" or (not awardedId and outcome ~= "sold") then
		Garage:addCash(player, price)
		self.log:warn(string.format("%s paid for a %s but the garage refused it (%s); refunded.", player.Name, body, outcome))
		return
	end
	self.log:info(string.format("%s bought a %s from a seller for %s: %s.", player.Name, body, GarageConfig.formatCash(price), outcome))
	self:_resolve(player, visit, "Bought")
	--- A lobby toy wins a tie for the hands (`CarryService._wanted`), so one still held from the Cars
	--- Inventory would hide the car just bought. The newer car wins (`CarryConfig` note 2).
	if outcome == "carried" then
		local Lobby = Shard.get("LobbyCarService")
		if Lobby then
			Lobby:setToyCar(player, nil)
		end
	end

	local profile = self._profiles[player]
	if profile and profile:IsActive() then
		profile:Set(SellerConfig.Onboarding.ProfileKey, true)
	end

	--- Bought: the celebration and the fade, the car already in the inventory (`SellerConfig.Sold`).
	if not SellerConfig.Sold.Handover then
		self:_sold(player, visit)
		return
	end
	--- `Sold.Handover`: the old beat, the real car on the spot with the owner in it. A failed spawn
	--- still leaves the car banked.
	local frame = visit.frame
	self:_end(player, false)
	local LobbyCarService = Shard.get("LobbyCarService")
	if awardedId and LobbyCarService then
		local handover = CarDealConfig.Handover
		local ok, reason = LobbyCarService:setLobbyCar(player, awardedId, { ground = frame, seat = handover.SeatBuyer, seatDelay = handover.SeatDelay })
		if not ok then
			self.log:warn(string.format("%s bought %s but could not be put in it (%s); it is in their collection.", player.Name, awardedId, reason))
		end
	end
end

--[[ Public (AdminService): a seller at this player's kerb now, replacing any already there.
	SKIPS the clock, the tutorial and the mid-run checks, which are what an admin is testing past.
	Keeps the profile check and everything about the car and the price, so what pulls up is a real
	seller that sells for real money. `(ok, sentence)`, the admin panel's shape. ]]
function SellerService.forceVisit(self, player: Player, band: unknown?): (boolean, string)
	if not (SellerConfig.Enabled and self._folder) then
		return false, "sellers are off (SellerConfig.Enabled, or the price floor check)"
	end
	local Garage = Shard.get("GarageService")
	if not (Garage and Garage:isProfileReady(player)) then
		return false, "their data is still loading"
	end
	local plot = Shard.get("PlotService"):getPlot(player)
	if not plot then
		return false, "they have no plot"
	end
	if not self:_spotOf(plot) then
		return false, string.format("%s has no %s part", plot.Name, SellerConfig.SpotName)
	end
	self:_end(player, false)
	if not self:_arrive(player, band) then
		self._nextAt[player] = os.clock() + SellerConfig.Visit.RetrySeconds
		return false, "no car could be rolled that they do not already own, or its rig is missing"
	end
	local model = self._visits[player].model
	return true, string.format("a %s for %s", tostring(model:GetAttribute(ATTR.Body)), GarageConfig.formatCash(model:GetAttribute(ATTR.Price) :: number))
end

--- Public (AdminService): the waiting seller drives off now, unsold. The next visit is a full
--- interval away, as after any visit.
function SellerService.clearVisit(self, player: Player): (boolean, string)
	if not self._visits[player] then
		return false, "no seller is waiting"
	end
	self:_end(player, true)
	return true, "the seller drove off"
end

function SellerService._tick(self)
	local clock = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	for player, nextAt in self._nextAt do
		local visit = self._visits[player]
		if visit then
			if not visit.leaving and serverNow >= visit.expires then
				self:_resolve(player, visit, "Ignored")
				self:_end(player, true)
			end
		elseif clock >= nextAt then
			if not (self:_canVisit(player) and self:_arrive(player)) then
				self._nextAt[player] = clock + SellerConfig.Visit.RetrySeconds
			end
		end
	end
end

SellerService:withLifecycle({
	init = function(self)
		self._visits = {} :: { [Player]: Visit }
		self._nextAt = {} :: { [Player]: number }
		self._profiles = {} :: { [Player]: any }
		self._cooldowns = {} :: { [Player]: number }
		self._warned = {} :: { [Model]: boolean }
		self._rng = Random.new()
		--- The crowd's clips plus the seat pose (`SellerConfig.Seat.Clip`).
		self._clips = table.clone(CustomerConfig.Animations.Clips)
		self._clips.Sit = SellerConfig.Seat.Clip
		self._clips.Cheer = SellerConfig.Sold.Emote
		--- Sold visits still on the kerb for their show (`_sold`), by owner.
		self._shows = {} :: { [Player]: Visit }
	end,

	start = function(self)
		if not SellerConfig.Enabled then
			return
		end
		if not SellerConfig.floorHolds() then
			self.log:warn("SellerConfig.Bands go under SellerConfig.Price.Floor, so a seller could give cars away; sellers are off until it is fixed.")
			return
		end

		local folder = Instance.new("Folder")
		folder.Name = "Sellers"
		folder.Parent = workspace
		self._folder = folder

		local PlotService = Shard.get("PlotService")
		PlotService:getSignal("PlotAssigned"):Connect(function(player: Player)
			self._nextAt[player] = os.clock() + SellerConfig.Visit.FirstDelay
		end)
		PlotService:getSignal("PlotReleased"):Connect(function(player: Player)
			self:_end(player, false)
			self._nextAt[player] = nil
			self:_dropShow(player)
		end)
		--- The profile handle, for the onboarding flag. `CodesService`'s pattern.
		Shard.get("GarageService"):getSignal("ProfileReady"):Connect(function(player: Player)
			task.spawn(function()
				local ok, profile = pcall(function()
					return Data:GetProfileAsync(player)
				end)
				if ok and profile and player.Parent == Players then
					self._profiles[player] = profile
				end
			end)
		end)
		Players.PlayerRemoving:Connect(function(player)
			self:_end(player, false)
			self._nextAt[player] = nil
			self:_dropShow(player)
			self._profiles[player] = nil
			self._cooldowns[player] = nil
		end)
		--- A plot assigned before this started (a fast join) is picked up here rather than missed.
		for _, player in Players:GetPlayers() do
			if PlotService:getPlot(player) and not self._nextAt[player] then
				self._nextAt[player] = os.clock() + SellerConfig.Visit.FirstDelay
			end
		end

		task.spawn(function()
			while true do
				task.wait(TICK)
				local ok, err = pcall(self._tick, self)
				if not ok then
					--- One bad pass must not end the loop; the kerb would go empty for the server.
					self.log:warn(string.format("Seller pass failed (%s); sellers carry on next pass.", tostring(err)))
				end
			end
		end)
	end,
})

return SellerService
