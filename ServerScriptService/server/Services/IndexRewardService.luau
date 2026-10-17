--[[
	IndexRewardService  (server)
	----------------------------
	One claim per discovered car, stored forever, with one small permanent luck term per claim.

	THE SERVER RE-DERIVES EVERY CONDITION. A single request carries a body name; Claim All carries no
	list and derives its candidates from the roster. This service verifies
	that it is on `CarCatalogue.Roster`, asks `GarageService.hasFound` against the profile, and refuses
	an existing claim before it writes. A forged request can therefore claim nothing the player has
	not already earned by banking a car.

	Claims are published twice from one roster walk: an ordered body list for the Index cards and a
	count for the luck calculation. Unknown keys in an old or manually repaired save are preserved but
	count for nothing, so stale data cannot inflate gameplay.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local CarCatalogue = require(ReplicatedStorage.shared.Modules.CarCatalogue)
local IndexRewardConfig = require(ReplicatedStorage.shared.Configs.IndexRewardConfig)
local Data = require(script.Parent.Parent.Data)

local IndexRewardService = Shard.new("IndexRewardService"):withDependencies({ "GarageService" })

local BODY_SET: { [string]: boolean } = {}
for _, car in CarCatalogue.Roster do
	BODY_SET[car.body] = true
end

IndexRewardService:withSignals({
	"Claimed", -- (player: Player, body: string, total: number)
})

IndexRewardService:withRemoteEvents({
	IndexRewardConfig.Remotes.Claimed,
	{
		[IndexRewardConfig.Remotes.Claim] = function(player: Player, body: unknown)
			IndexRewardService:_claim(player, body)
		end,
		[IndexRewardConfig.Remotes.ClaimAll] = function(player: Player)
			IndexRewardService:_claimEligible(player)
		end,
	},
})

function IndexRewardService._profile(self, player: Player)
	local profile = self._profiles[player]
	return if profile and profile:IsActive() then profile else nil
end

function IndexRewardService._claims(self, player: Player): { [string]: any }
	local profile = self:_profile(player)
	local stored = profile and profile:Get({ IndexRewardConfig.ProfileKey })
	return if type(stored) == "table" then stored else {}
end

--[[ One roster walk owns both attributes, so the button state and the luck count cannot disagree.
	The profile map is not rewritten here: unknown keys are preserved for the same forward/backward
	server-version reason `GarageService._ownedList` preserves unknown cars. ]]
function IndexRewardService._publish(self, player: Player)
	if player.Parent ~= Players then
		return
	end
	local claims = self:_claims(player)
	local ordered = {}
	for _, car in CarCatalogue.Roster do
		if claims[car.body] == true then
			table.insert(ordered, car.body)
		end
	end
	player:SetAttribute(IndexRewardConfig.ClaimedAttribute, table.concat(ordered, ","))
	player:SetAttribute(IndexRewardConfig.CountAttribute, #ordered)
end

function IndexRewardService._claim(self, player: Player, body: unknown)
	if not IndexRewardConfig.Enabled or type(body) ~= "string" or not BODY_SET[body] then
		return
	end
	self:_claimEligible(player, body)
end

-- A nil body is the server's Claim All path; never accepts a client list or reward count.
function IndexRewardService._claimEligible(self, player: Player, body: string?)
	if not IndexRewardConfig.Enabled then
		return
	end
	local now = os.clock()
	if (self._lastClaim[player] or -math.huge) + IndexRewardConfig.ClaimCooldown > now then
		return
	end
	self._lastClaim[player] = now

	local profile = self:_profile(player)
	local Garage = Shard.get("GarageService")
	if not (profile and Garage) then
		return
	end
	local claims = self:_claims(player)
	local nextClaims = table.clone(claims)
	local added = {}
	for _, car in CarCatalogue.Roster do
		if (body == nil or body == car.body) and claims[car.body] ~= true and Garage:hasFound(player, car.body) then
			nextClaims[car.body] = true
			table.insert(added, car.body)
		end
	end
	if #added == 0 then
		return
	end
	profile:Set({ IndexRewardConfig.ProfileKey }, nextClaims)
	self:_publish(player)
	local total = player:GetAttribute(IndexRewardConfig.CountAttribute) or 0
	for _, claimedBody in added do
		self:getSignal("Claimed"):Fire(player, claimedBody, total)
	end
	self:getRemoteEvent(IndexRewardConfig.Remotes.Claimed):Fire(player, body, total, #added)
	self.log:info(string.format("%s claimed %d Index rewards (%d total).", player.Name, #added, total))
end

function IndexRewardService._watch(self, player: Player)
	task.spawn(function()
		local ok, profile = pcall(function()
			return Data:GetProfileAsync(player)
		end)
		if not ok or not profile or player.Parent ~= Players then
			return
		end
		self._profiles[player] = profile
		self:_publish(player)
	end)
end

IndexRewardService:withLifecycle({
	init = function(self)
		self._profiles = {} :: { [Player]: any }
		self._lastClaim = {} :: { [Player]: number }
	end,

	start = function(self)
		if not IndexRewardConfig.Enabled then
			return
		end
		local Garage = Shard.get("GarageService")
		if not Garage then
			self.log:warn("No GarageService — Index rewards cannot verify discoveries.")
			return
		end
		Garage:getSignal("ProfileReady"):Connect(function(player: Player)
			self:_watch(player)
		end)
		for _, player in Players:GetPlayers() do
			if Garage:isProfileReady(player) then
				self:_watch(player)
			end
		end
		Players.PlayerRemoving:Connect(function(player)
			self._profiles[player] = nil
			self._lastClaim[player] = nil
		end)
	end,
})

return IndexRewardService
