--[[
	FirstCarService  (server)
	-------------------------
	THE ONE TIME A CAR IS NEW. A player's first car is the only one they will ever be handed without
	already knowing what it is for, and this service is the two facts that follow from that: which
	players are on theirs right now, and how many of them ever put it down.

	It owns nothing else and draws nothing. The model in the hands is `CarryService`'s, the record of
	what is held is `GarageService`'s, the card is `CarryController`'s, and every word and clock the
	walkthrough uses is `CarryConfig.Guide`. What lives here is a latch in the profile, one attribute
	published off it, and three analytics events.

	=== IT SUBSCRIBES, IT IS NEVER CALLED =====================================================

	Two signals are the whole input, and both of them already existed:

	    GarageService.CarryChanged   a car is in their hands, or has left them
	    GarageService.CarParked      a car reached a bay, by any route

	That is the same "subscribe, do not sprinkle" shape `AnalyticsService`'s header argues for, and
	it is what keeps this feature out of the reward path: nothing in banking, placing or awarding a
	car has to know this service exists, so none of it can be broken by this service being wrong.

	=== THE LATCH IS TWO BOOLEANS AND THE GAP IS THE MEASUREMENT ==============================

	`Carried` is "a car has been in this player's hands at least once". `Placed` is "and one of them
	reached a bay". A profile with the first and not the second is a player the reward flow lost
	somewhere between handing them the prize and them keeping it, and until this existed nothing in
	the game could count those people. `CarryConfig`'s own header names that as the question the
	whole carry feature exists to answer.

	IT IS A PROFILE KEY RATHER THAN SESSION STATE because the answer has to survive a logout. A
	player who banks their first car, sees the card, and quits while still holding it is precisely
	the case worth counting, and a session-scoped flag would report them as a fresh first-timer the
	next time they logged in.

	=== THE ATTRIBUTE IS THE WHOLE CLIENT CONTRACT ============================================

	`CarryConfig.Guide.Attribute` on the Player, one of three strings, replicated. No remote, no
	round trip, and the same bargain `CarryConfig.Attribute` itself makes one line further up. The
	client reads it and picks a face; it is never asked a question and never answers one.

	A rejoin is covered by `ProfileReady` rather than by anything remembered: the profile says
	whether they are still on their first car and `GarageService` says whether it is still in their
	hands, so the attribute is simply derived again.

	=== IT STANDS DOWN FOR THE TUTORIAL, AND ONLY THE WORDS DO ================================

	A player on the tutorial's `place` beat already has an objective card up saying the same
	sentence in the same seconds. Two cards saying one thing is worse than either of them alone, so
	the attribute is not published for anybody the tutorial is still talking to.

	THE FUNNEL IS COUNTED EITHER WAY. What it is asking about is every player's first car, not this
	card, and a funnel that quietly excluded the players who were being taught properly would be the
	one measurement guaranteed to flatter the feature.

	=== WHY THE FUNNEL IS NOT MORE TUTORIAL STEPS =============================================

	Because the interesting half of the question is the players who are not in the tutorial: the
	skippers, the profiles that finished the five-step version long ago, and everybody who joins if a
	future build ships with the onboarding off. The tutorial funnel cannot see any of them.

	It also cannot lend its stage numbers. Roblox's onboarding funnel is one numbered sequence per
	experience and `TutorialConfig` already owns nine stages of it; a second feature numbering into
	the same chart would corrupt the one it was borrowing. So this reports to a NAMED funnel of its
	own (`LogFunnelStepEvent`), which is what that call is for, and to GameAnalytics beside it in the
	same two-audience split `TutorialService._funnel` documents.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
--- Roblox's own, not ours. `Shard.get("AnalyticsService")` is the GameAnalytics one, and the two are
--- deliberately both fed: see the header.
local RobloxAnalytics = game:GetService("AnalyticsService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local CarryConfig = require(ReplicatedStorage.shared.Configs.CarryConfig)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)

local Data = require(script.Parent.Parent.Data)

local FirstCarService = Shard.new("FirstCarService"):withDependencies({ "GarageService" })

--[[ The named funnel, and its two steps.

	THE SESSION ID IS EMPTY ON PURPOSE. That field exists for funnels a player runs more than once,
	such as a checkout; this one happens once in a lifetime, and the API's own rule for an empty
	session is that a repeated step is IGNORED. So the endpoint enforces the same once-per-player
	shape the profile latch does, and the two of them cannot disagree. ]]
local FUNNEL = "FirstCar"
local FUNNEL_SESSION = ""
local STEP_CARRIED, STEP_PLACED = 1, 2

-- === The profile ============================================================

--[[ NON-YIELDING, like `GarageService._profile` and `QuestService._profile`, and for their reason:
	every caller here is another service's signal handler, and none of them may stall for the seconds
	`Data:GetProfileAsync` can take. The handle is cached off the join path by `_watch`; until it
	lands every read answers "not yet", which every caller already handles by doing nothing. ]]
function FirstCarService._profile(self, player: Player)
	local profile = self._profiles[player]
	if profile and profile:IsActive() then
		return profile
	end
	return nil
end

--[[ The stored latch, always a table with both fields, or nil when there is no profile yet.

	ARRAY PATH, NEVER THE STRING FORM, which is `QuestService._board`'s rule: `PlayerProfile:Get`
	treats a string as a RECURSIVE KEY SEARCH and returns whichever matching key it reaches first,
	and `Carried` and `Placed` are exactly the sort of names another feature adds somewhere else in
	the template one day.

	A PROFILE THAT STORED SOMETHING ELSE HERE READS AS A FRESH ONE rather than erroring. That is
	every save written before this key existed, and the right answer for all of them is that they
	have not been walked through anything yet. ]]
function FirstCarService._record(self, player: Player): { [string]: boolean }?
	local profile = self:_profile(player)
	if not profile then
		return nil
	end
	local stored = profile:Get({ CarryConfig.Guide.ProfileKey })
	if type(stored) ~= "table" then
		return { Carried = false, Placed = false, Pointed = false }
	end
	--- `Pointed`: the customize pointer has been shown (`CarryConfig.Guide.PointCustomize`).
	return { Carried = stored.Carried == true, Placed = stored.Placed == true, Pointed = stored.Pointed == true }
end

--- Latch one of the two fields on. Written as the WHOLE table rather than as one field, so the key
--- can never exist in a shape half of this file's readers would not recognise.
function FirstCarService._mark(self, player: Player, field: string)
	local profile = self:_profile(player)
	local record = self:_record(player)
	if not (profile and record) or record[field] then
		return
	end
	record[field] = true
	profile:Set({ CarryConfig.Guide.ProfileKey }, record)
end

-- === What the client is told ================================================

--- Mirror the walkthrough's state onto the Player. Guarded against writing a value that is already
--- there, because an attribute written to itself still wakes every listener on it.
function FirstCarService._publish(self, player: Player, value: string)
	if player.Parent ~= Players then
		return
	end
	local attribute = CarryConfig.Guide.Attribute
	if player:GetAttribute(attribute) ~= value then
		player:SetAttribute(attribute, value)
	end
end

--[[ Does this player get the walkthrough's WORDS? The funnel is not asking.

	THE TUTORIAL WINS WHENEVER IT IS STILL TALKING. See the header: its `place` beat is the same
	sentence, on screen at the same moment, with a pointer and a gate this has neither of.

	`isOn` as well as `isFinished`, because a place carrying the developer bypass has no tutorial
	running to defer to, and a player on one would otherwise be told nothing at all. ]]
function FirstCarService._guided(self, player: Player): boolean
	if not (CarryConfig.Enabled and CarryConfig.Guide.Enabled) then
		return false
	end
	if not TutorialConfig.isOn() then
		return true
	end
	local Tutorial = Shard.get("TutorialService")
	return Tutorial == nil or Tutorial:isFinished(player)
end

--[[ Mirror the `Placed` latch onto the Player for `CarryConfig.Hint.FirstTimeOnly`. Not gated on
	`_guided`: the ordinary card is not the walkthrough, and a player the tutorial taught still has
	parked a car. ]]
function FirstCarService._publishParkedBefore(self, player: Player, record)
	local attribute = CarryConfig.Guide.ParkedBeforeAttribute
	if player.Parent == Players and record and player:GetAttribute(attribute) ~= record.Placed then
		player:SetAttribute(attribute, record.Placed)
	end
end

-- === The funnel =============================================================

--[[ Roblox's half. `pcall` for `TutorialService._funnel`'s reason: analytics may be off, unavailable
	in Studio, or rate-limited, and none of those is allowed to be why a player stops being told
	where to put their car. ]]
function FirstCarService._funnel(self, player: Player, step: number, name: string)
	pcall(function()
		RobloxAnalytics:LogFunnelStepEvent(player, FUNNEL, FUNNEL_SESSION, step, name)
	end)
end

-- === The two moments ========================================================

--[[ What is in their hands changed.

	IT IS ALSO THE REJOIN PATH, called by `_watch` with whatever `GarageService` says they are
	holding, which is what makes a player who logged off mid-carry pick the walkthrough back up
	rather than lose it. ]]
function FirstCarService._onCarryChanged(self, player: Player, key: string?)
	local guide = CarryConfig.Guide
	local record = self:_record(player)
	if not record then
		return
	end

	if not (type(key) == "string" and key ~= "") then
		--[[ Empty hands: placed, sold, or swapped for another car mid-flight. Only the CARRYING face
			is taken down here, never the parked one. `GarageService.placeCarried` clears the hands
			before it announces the park, so this runs first and `_onParked` is a moment behind it
			with something better to say. ]]
		local state = player:GetAttribute(guide.Attribute)
		if state == guide.Carrying or state == guide.Customize then
			self:_publish(player, "")
		end
		return
	end

	--[[ They have parked a car before, so nothing in their hands is anybody's first time. This is
		the line that stops the walkthrough coming back for somebody who sold their whole lot and
		banked a fresh car: what they have forgotten is not how a podium works. ]]
	if record.Placed then
		self:_offerCustomize(player, record)
		return
	end

	if not record.Carried then
		self:_mark(player, "Carried")
		self:_funnel(player, STEP_CARRIED, "Carried")
		local Analytics = Shard.get("AnalyticsService")
		if Analytics then
			Analytics:FirstCarCarried(player)
		end
		self.log:info(string.format("%s is holding their first car.", player.Name))
	end

	if self:_guided(player) then
		self:_publish(player, guide.Carrying)
	end
end

--[[ The car now in their hands came home from a run, they have parked a car before, and nobody has
	shown them the workshop: put the customize face up (`CarryConfig.Guide.PointCustomize`). Only a
	car that arrived inside `CustomizeBankWindow` of a banked run counts, so a car taken off the hotbar
	is not mistaken for a steal. Latched only when it is really published, so a car banked while the
	tutorial still has the screen leaves the pointer for the next one. ]]
function FirstCarService._offerCustomize(self, player: Player, record)
	local guide = CarryConfig.Guide
	local at = self._bankedAt[player]
	self._bankedAt[player] = nil
	if not (guide.PointCustomize and at and os.clock() - at <= guide.CustomizeBankWindow) then
		return
	end
	if record.Pointed or not self:_guided(player) then
		return
	end
	self:_mark(player, "Pointed")
	self:_publish(player, guide.Customize)
	self.log:info(string.format("%s banked another car; pointing them at the workshop.", player.Name))
end

--[[ A car reached a bay, by any route: out of their hands at a podium, off the Cars Inventory
	screen, or parked for them by `awardCar` on a build with the carry switched off.

	`Placed` LATCHES FOR ALL THREE, and the walkthrough is over for all three. Somebody with a car
	standing on their forecourt has been shown what a bay is, whoever put it there.

	THE FUNNEL ONLY COUNTS A PARK THAT FOLLOWED A CARRY. A first car that parked itself never
	reported step one, and a step two with no step one ahead of it is a completion the chart would
	read as a flow nobody entered. ]]
function FirstCarService._onParked(self, player: Player)
	local guide = CarryConfig.Guide
	local record = self:_record(player)
	if not record or record.Placed then
		return
	end
	self:_mark(player, "Placed")
	record.Placed = true
	self:_publishParkedBefore(player, record)

	if not record.Carried then
		return
	end

	self:_funnel(player, STEP_PLACED, "Placed")
	local Analytics = Shard.get("AnalyticsService")
	if Analytics then
		Analytics:FirstCarPlaced(player)
	end
	self.log:info(string.format("%s parked their first car.", player.Name))

	if not self:_guided(player) then
		return
	end

	--[[ The follow-up card, and then its own expiry. Cleared rather than left standing, so that
		nothing in the game is still reading "this player has just parked their first car" ten
		minutes later, and fenced on the value so a car banked and carried inside the hold takes the
		attribute back without this pulling it out from under them. ]]
	self:_publish(player, guide.Parked)
	task.delay(guide.ParkedHold, function()
		if player.Parent == Players and player:GetAttribute(guide.Attribute) == guide.Parked then
			self:_publish(player, "")
		end
	end)
end

--[[ They left. If the first car is still in their hands, the reward did not land.

	SCORED AS A FAILURE EVEN THOUGH NOTHING WAS LOST. The car is in their collection either way and
	the Cars Inventory screen can park it whenever they like (`CarryConfig` note 1). What is being
	counted is whether the prize ARRIVED, and somebody who logged off holding it did not see it
	arrive. ]]
function FirstCarService._onLeaving(self, player: Player)
	local record = self:_record(player)
	if record and record.Carried and not record.Placed then
		local Garage = Shard.get("GarageService")
		if Garage and Garage:getCarriedCar(player) then
			local Analytics = Shard.get("AnalyticsService")
			if Analytics then
				Analytics:FirstCarAbandoned(player)
			end
		end
	end
	self._profiles[player] = nil
	self._bankedAt[player] = nil
end

--[[ Cache the profile off the join path, then derive the attribute from scratch.

	Hung off `GarageService.ProfileReady` rather than `PlayerAdded` for the reason that signal
	exists: one service owns the profile cache, so one service says when a player is warm, and
	`GetProfileAsync` therefore returns immediately here.

	The re-check after the yield is `QuestService._watch`'s: a player who joins and leaves inside
	that window would otherwise have an attribute written onto an instance that has gone. ]]
function FirstCarService._watch(self, player: Player)
	task.spawn(function()
		local ok, profile = pcall(function()
			return Data:GetProfileAsync(player)
		end)
		if not ok or not profile or player.Parent ~= Players then
			return
		end
		self._profiles[player] = profile
		self:_publishParkedBefore(player, self:_record(player))

		local Garage = Shard.get("GarageService")
		self:_onCarryChanged(player, Garage and Garage:getCarriedCar(player) or nil)
	end)
end

-- === Lifecycle ==============================================================

FirstCarService:withLifecycle({
	init = function(self)
		self._profiles = {} :: { [Player]: any }
		self._bankedAt = {} :: { [Player]: number }
		self._trove = Trove.new()
	end,

	start = function(self)
		local Garage = Shard.get("GarageService")
		if not Garage then
			self.log:warn("No GarageService, so nobody's first car can be recognised as one.")
			return
		end

		self._trove:Add(Garage:getSignal("ProfileReady"):Connect(function(player: Player)
			self:_watch(player)
		end))

		self._trove:Add(Garage:getSignal("CarryChanged"):Connect(function(player: Player, key: string?)
			self:_onCarryChanged(player, key)
		end))

		self._trove:Add(Garage:getSignal("CarParked"):Connect(function(player: Player)
			self:_onParked(player)
		end))

		--- When a run last banked, for `_offerCustomize`. The car lands in the hands just after.
		local Reward = Shard.get("RewardService")
		if Reward then
			self._trove:Add(Reward:getSignal("RunSettled"):Connect(function(player: Player, _cash, _studs, banked)
				if banked == true then
					self._bankedAt[player] = os.clock()
				end
			end))
		end

		--- Anyone already warm. `ProfileReady` fires off the join path, so on a hot reload, or simply
		--- if GarageService started first, a player can be past it by the time this connects. The
		--- same catch-up `CarryService`, `TutorialService` and `OfflineService` all make.
		for _, player in Players:GetPlayers() do
			if Garage:isProfileReady(player) then
				self:_watch(player)
			end
		end

		self._trove:Add(Players.PlayerRemoving:Connect(function(player: Player)
			self:_onLeaving(player)
		end))
	end,
})

FirstCarService:withCleanup(function()
	if FirstCarService._trove then
		FirstCarService._trove:Destroy()
	end
	FirstCarService._profiles = {}
end)

return FirstCarService
