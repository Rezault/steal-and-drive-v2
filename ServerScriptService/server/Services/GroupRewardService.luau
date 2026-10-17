--[[
	GroupRewardService  (server — dresses the stands, checks the group, pays once)
	--------------------------------------------------------------------------------
	`GroupRewardConfig` has the design and the trust note. This file parks the reward car on every
	tagged stand, puts the claim prompt on it, and answers claims.

	THE CAR IS SERVER-SIDE AND THE DANCER IS NOT. The car is the same for everyone, so it is one
	anchored `CarDisplay` model replicated to all. The person beside it is each viewer's OWN avatar,
	which only that viewer's client can build (`GroupRewardController`).

	A CLAIM, IN THIS ORDER: cooldown, profile ready, not yet claimed, room for a car, in the group,
	then MARK, then award. Every refusal comes before the mark, so a refusal costs nothing. An award
	that still fails after the mark is unmarked and refunded nothing, because nothing was paid.
]]

local CollectionService = game:GetService("CollectionService")
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local GroupRewardConfig = require(ReplicatedStorage.shared.Configs.GroupRewardConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
--- The display car's pose: the market's, a CONFIG (`SellerService` takes the same one).
local CarDealConfig = require(ReplicatedStorage.shared.Configs.CarDealConfig)
local CarDisplay = require(ReplicatedStorage.shared.Modules.CarDisplay)
local Data = require(script.Parent.Parent.Data)

local GroupRewardService = Shard.new("GroupRewardService"):withDependencies({ "GarageService" })

local TEXT = GroupRewardConfig.Text
local PARTS = GroupRewardConfig.Parts

GroupRewardService:withRemoteEvents({
	GroupRewardConfig.Remotes.Result,
	{
		[GroupRewardConfig.Remotes.Claim] = function(player: Player)
			GroupRewardService:_claim(player)
		end,
	},
})

--[[ Dress one stand: hide its parts, park the car on `CarSpot`, hang the prompt off it. A stand
	missing `CarSpot`, or a roster with no such body, is logged and left bare: the failure mode of a
	stand is an empty stand. ]]
function GroupRewardService._dress(self, stand: Instance)
	if not stand:IsA("Model") or self._dressed[stand] then
		return
	end
	self._dressed[stand] = true
	--- Atomic so a client gets `AvatarSpot` and `Sign` with the stand, never the stand without them.
	stand.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	CarDisplay.markerFrame(stand:FindFirstChild(PARTS.Avatar))
	CarDisplay.markerFrame(stand:FindFirstChild(PARTS.Sign))
	local carSpot = stand:FindFirstChild(PARTS.Car)
	local frame = CarDisplay.markerFrame(carSpot)
	if not frame then
		self.log:warn(string.format("%s has no usable %s, so no reward car is shown there.", stand:GetFullName(), PARTS.Car))
		return
	end

	local car = GroupRewardConfig.Car
	local carCfg = CarDealConfig.Car
	local model, offsets, extents = CarDisplay.build(car.Body, car.Paint, {
		rosterFolder = GarageConfig.Display.RosterFolderName,
		bodyFolder = GarageConfig.Display.BodyFolderName,
		hitBoxName = GarageConfig.Display.HitBoxName,
		name = "RewardCar",
		castShadow = carCfg.CastShadow,
	})
	if not model then
		self.log:warn(string.format("No %s on the roster, so the group reward stand shows no car (the claim still works).", car.Body))
	else
		CarDisplay.place(offsets, CarDisplay.standOn(extents, frame.Position, frame.Position.Y, frame, carCfg.Lift))
		model.Parent = stand
	end

	--- The claim itself is the client's: it opens Roblox's join popup first (`GroupRewardController`).
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GroupRewardPrompt"
	prompt.ActionText = GroupRewardConfig.Prompt.ActionText
	prompt.ObjectText = GroupRewardConfig.Prompt.ObjectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = GroupRewardConfig.Prompt.MaxDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = carSpot
end

--[[ Is this player in the group right now? `GetGroupsAsync` first, because it is read off Roblox
	per call where `Player:IsInGroup` is cached for the session (so it would say no to somebody who
	joined through the popup a second ago). `IsInGroup` is the fallback for a failed web call.
	nil: neither could answer, which the claim reports as "try again", never as "not a member". ]]
function GroupRewardService._isMember(self, player: Player): boolean?
	local ok, groups = pcall(function()
		return GroupService:GetGroupsAsync(player.UserId)
	end)
	if ok and type(groups) == "table" then
		for _, group in groups do
			if group.Id == GroupRewardConfig.GroupId then
				return true
			end
		end
	end
	local cached, member = pcall(function()
		return player:IsInGroup(GroupRewardConfig.GroupId)
	end)
	if cached and member then
		return true
	end
	return if ok or cached then false else nil
end

function GroupRewardService._reply(self, player: Player, ok: boolean, message: string)
	self:getRemoteEvent(GroupRewardConfig.Remotes.Result):Fire(player, ok, message)
end

function GroupRewardService._claim(self, player: Player)
	if not GroupRewardConfig.Enabled then
		return
	end
	local now = os.clock()
	if (self._last[player] or -math.huge) + GroupRewardConfig.Prompt.Cooldown > now then
		return
	end
	self._last[player] = now

	local Garage = Shard.get("GarageService")
	local profile = self._profiles[player]
	if not (Garage and Garage:isProfileReady(player) and profile and profile:IsActive()) then
		self:_reply(player, false, TEXT.NotReady)
		return
	end
	if profile:Get(GroupRewardConfig.ProfileKey) == true then
		self:_reply(player, false, TEXT.Already)
		return
	end
	--- Refused rather than auto-sold (header of `GroupRewardConfig`).
	if not Garage:hasRoom(player) then
		self:_reply(player, false, TEXT.Full)
		return
	end
	local member = self:_isMember(player)
	if member == nil then
		self:_reply(player, false, TEXT.Failed)
		return
	elseif not member then
		self:_reply(player, false, TEXT.NotMember)
		return
	end

	--- Marked first, awarded second (header).
	profile:Set(GroupRewardConfig.ProfileKey, true)
	local car = GroupRewardConfig.Car
	local outcome, _, id = Garage:awardCar(player, GarageConfig.TierOfBody[car.Body], car.Body, car.Paint, nil, "GroupReward")
	if not id then
		--- Nothing was given, so the reward is still theirs to claim.
		profile:Set(GroupRewardConfig.ProfileKey, false)
		self.log:warn(string.format("%s's group reward %s was refused by the garage (%s); they can claim again.", player.Name, car.Body, tostring(outcome)))
		self:_reply(player, false, TEXT.Failed)
		return
	end
	player:SetAttribute(GroupRewardConfig.ClaimedAttribute, true)
	self.log:info(string.format("%s claimed the group reward %s (%s).", player.Name, car.Body, tostring(outcome)))
	self:_reply(player, true, string.format(TEXT.Success, string.upper(GarageConfig.displayName(car.Body))))
end

GroupRewardService:withLifecycle({
	init = function(self)
		self._dressed = {} :: { [Instance]: boolean }
		self._profiles = {} :: { [Player]: any }
		self._last = {} :: { [Player]: number }
	end,

	start = function(self)
		if not GroupRewardConfig.Enabled then
			return
		end
		CollectionService:GetInstanceAddedSignal(GroupRewardConfig.Tag):Connect(function(stand)
			self:_dress(stand)
		end)
		for _, stand in CollectionService:GetTagged(GroupRewardConfig.Tag) do
			self:_dress(stand)
		end

		--- The profile handle and the claimed flag, off `ProfileReady`: `CodesService`'s pattern.
		Shard.get("GarageService"):getSignal("ProfileReady"):Connect(function(player: Player)
			task.spawn(function()
				local ok, profile = pcall(function()
					return Data:GetProfileAsync(player)
				end)
				if ok and profile and player.Parent == Players then
					self._profiles[player] = profile
					player:SetAttribute(GroupRewardConfig.ClaimedAttribute, profile:Get(GroupRewardConfig.ProfileKey) == true)
				end
			end)
		end)
		Players.PlayerRemoving:Connect(function(player)
			self._profiles[player] = nil
			self._last[player] = nil
		end)
	end,
})

return GroupRewardService
