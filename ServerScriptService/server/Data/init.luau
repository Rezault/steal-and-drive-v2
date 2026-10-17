local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Packages = ReplicatedStorage.Packages

local PlayerProfile = require(script.Components.PlayerProfile)
local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)
local Replica = require(Packages.ReplicaServer)

local observePlayer = require(Packages.Observers).observePlayer
local DevProducts = require(script.Components.DevProductsHandler)
local Settings = require(script.Components.Settings)
local ProfileReset = require(script.Components.ProfileReset)
local Types = require(script.Components.Types)

--[[ A save carrying this key is emptied back to the template the next time a session opens it. See
	`MarkForWipe`. It is a key in the data rather than anything held by this server, because the
	session that honours it is usually on a different server from the one that set it. ]]
local WIPE_KEY = "WipeOnNextLoad"

local Data = {}
Data.__index = Data

local DataSingleton = setmetatable({}, Data)

function DataSingleton:initialize()
	self._playerToken = Replica.Token("PlayerData")
	self._playerStore = ProfileStore.New("PlayerStore", Settings.TEMPLATE)
	self._suffix = self:GetSuffix()
	if RunService:IsStudio() and Settings.DEBUG_MOCK then
		print("[ProfileStore]: Using mock profile store")
		self._playerStore = self._playerStore.Mock
	end

	self._profiles = {} :: { [Player]: typeof(self._playerStore:StartSessionAsync()) }
	self._profilesByUserId = {} :: { [number]: typeof(self._playerStore:StartSessionAsync()) }

	self:_observePlayers()

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		return DevProducts:ProcessReceipt(receiptInfo, self)
	end
end

function DataSingleton:GetProfileAsync(player: Player): Types.PlayerProfile?
	while not self._profiles[player] and player.Parent == Players do
		task.wait()
	end
	return self._profiles[player]
end

function DataSingleton:_playerAdded(player: Player)
	local existingProfile = self._profilesByUserId[player.UserId]
	if existingProfile then
		local oldProfile = existingProfile:GetProfile()
		local oldReplica = existingProfile:GetReplica()

		self._profilesByUserId[player.UserId] = nil
		for p, prof in self._profiles do
			if prof == existingProfile then
				self._profiles[p] = nil
				break
			end
		end

		if oldProfile and oldProfile:IsActive() then
			if oldReplica then
				oldReplica:Destroy()
			end
			local sessionEnded = false
			local connection = oldProfile.OnSessionEnd:Connect(function()
				sessionEnded = true
			end)
			oldProfile:EndSession()
			while not sessionEnded do
				task.wait()
			end
			connection:Disconnect()
		end
	end

	local profile = nil
	while player.Parent == Players and not ProfileStore.IsClosing do
		profile = self._playerStore:StartSessionAsync(`{player.UserId}{self._suffix}`, {
			Cancel = function()
				return player.Parent ~= Players
			end,
		})
		if profile then
			break
		end
	end

	if not profile then
		player:Kick(Settings.LOAD_FAILED_MESSAGE)
		return
	end

	--[[ A save marked by `MarkForWipe`, opened for the first time since. Emptied here, before the
		replica exists and before any service has read a key, and `Reconcile` below then fills the
		empty table from the template: what comes out is exactly the save a first join makes. ]]
	if profile.Data[WIPE_KEY] == true then
		table.clear(profile.Data)
		print(string.format("[ProfileStore]: Wiped %s's save back to the template, as marked.", player.Name))
	end

	-- Reset offline and returning players before any service or replica sees their old progress.
	ProfileReset.apply(profile.Data, Settings.TEMPLATE)

	profile:AddUserId(player.UserId)
	profile:Reconcile()
 -- Preserve balances, ownership, upgrades and world unlocks; expire only stale offers.
 if (tonumber(profile.Data.EconomyVersion) or 0) < 2 then
  if type(profile.Data.Garage) == "table" then profile.Data.Garage.Offers = {} end
  profile.Data.EconomyVersion = 2
 end

	profile.OnSessionEnd:Connect(function()
		self._profiles[player] = nil
		self._profilesByUserId[player.UserId] = nil

		player:Kick(Settings.SESSION_END_MESSAGE)
	end)

	if player.Parent ~= Players then
		profile:EndSession()
	end

	local replica = Replica.New({
		Token = self._playerToken,
		Data = profile.Data,
		Tags = { Player = player },
	})
	replica:Replicate()

	self._profiles[player] = PlayerProfile.new(player, profile, replica)
	self._profilesByUserId[player.UserId] = self._profiles[player]
end

--[[ Mark this player's save to be emptied back to the template the next time it loads. Answers
	whether the mark was made; false means there is no live session to write it into.

	MARKED, NOT WIPED IN PLACE, and the difference is the whole design. Most services hold this
	player's state in memory and some write to the save on the way out (the offline stamp, for one),
	so a table emptied now would be partly refilled by the leave that follows it. The mark rides out on that same final save,
	and the next session empties whatever the leave wrote, before anything can read it.

	The caller is expected to send the player away straight after (AdminService rejoins them).
	Nothing here does, because the data layer has no opinion on how somebody leaves. ]]
function DataSingleton:MarkForWipe(player: Player): boolean
	local playerProfile = self._profiles[player]
	local profile = playerProfile and playerProfile:GetProfile()
	if not (profile and profile:IsActive()) then
		return false
	end
	profile.Data[WIPE_KEY] = true
	return true
end

--- Is this server on Studio's mock store, which starts empty on every playtest and is gone after it?
function DataSingleton:IsMock(): boolean
	return RunService:IsStudio() and Settings.DEBUG_MOCK == true
end

function DataSingleton:GetPlayerStore()
	return self._playerStore
end

function DataSingleton:GetProfileStore()
	return self._playerStore
end

function DataSingleton:GetPlayerKey(player: Player): string
	return `{player.UserId}{self._suffix}`
end

function DataSingleton:GetKeyFromUserId(userId: number): string
	return `{userId}{self._suffix}`
end

function DataSingleton:GetSuffix()
	local suffix
	if RunService:IsStudio() then
		suffix = Settings.DEVELOPMENT_SUFFIX
	else
		if game.PlaceId == Settings.PRODUCTION_PLACE_ID then
			suffix = Settings.PRODUCTION_SUFFIX
		else
			suffix = Settings.DEVELOPMENT_SUFFIX
		end
	end
	return suffix
end

function DataSingleton:_observePlayers()
	observePlayer(function(player)
		self:_playerAdded(player)
		return function()
			local playerProfile = self._profiles[player]
			local profile = playerProfile and playerProfile:GetProfile()
			local replica = playerProfile and playerProfile:GetReplica()
			if profile and replica then
				-- We do RunService.Heartbeat:Wait() to allow BindToClose to fire, when a shutdown happens Roblox kicks all players then does BindsToClose
				-- This correctly identifies the shutdown reason in the .OnLastSave method of ProfileStore.
				-- (I.e. you want to detect if a dev/owner shutdown the server in order to save their boosts or something like that)
				RunService.Heartbeat:Wait()

				if profile:IsActive() then
					replica:Destroy()
					profile:EndSession()

					local userId = playerProfile:GetUserId()
					if userId and self._profilesByUserId[userId] then
						self._profilesByUserId[userId] = nil
					end
				end
			end
		end
	end)
end

return DataSingleton
