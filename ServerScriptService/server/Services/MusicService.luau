--[[
	MusicService
	------------
	Remembers whether a player has the music muted. That is the entire job.

	THE SERVER HAS NO PART IN THE SOUNDTRACK. There is no music on this side, no playlist, no
	decks and no authority — `MusicController` owns all of it and applies a press before this is
	ever told. What lives here is one bit of storage and its broadcast, for the same reason
	`StartCarService` keeps a car key: a preference that does not survive a rejoin is a preference
	the player has to set again every session, and for a mute button that means hearing the exact
	thing they turned off, every single time they come back.

	IT IS THE ONLY REMOTE IN THE GAME THAT IS NOT ALSO A REQUEST, and that shapes everything about
	how it is written:

	  • NOTHING IS REFUSED. There is no ruling to make. A player is allowed to mute their own music,
	    so `_onSet` validates the SHAPE of the message (it must be a boolean) and nothing else —
	    the guard is against a malformed profile write, not against a cheat. The worst a client can
	    do by lying here is silence its own speakers.

	  • THE ATTRIBUTE IS A SEED, NOT A CHANNEL. It is written once when the profile lands, and
	    again on every accepted set so a second client of the same player agrees. The controller
	    reads it ONCE, on the way in, and then stops listening — see its "Who owns the mute". So
	    this must never treat the attribute as a way to *tell* a live client anything: writing it
	    mid-session is bookkeeping, and the client has already moved on.

	  • THE WRITE IS FIRE-AND-FORGET, so it must not be able to throw. A profile that has not
	    loaded yet, or a player who left in the same frame, both mean "there is nowhere to put
	    this" — and dropping the preference is the correct outcome for both, because there is
	    nothing for it to be wrong about later.

	Absent from a profile is FALSE — unmuted — which is what every profile written before this
	service existed already answers, so nothing needs migrating.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data = require(script.Parent.Parent.Data)
local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local MusicConfig = require(ReplicatedStorage.shared.Configs.MusicConfig)

local MusicService = Shard.new("MusicService")

MusicService:withRemoteEvents({
	{
		--[[ client -> server: "I pressed the music button, and it is now this."

			A STATEMENT, NOT A REQUEST. The client has already applied it; this is where it is kept
			so the next session starts the same way. Nothing is sent back — the client is not
			waiting on an answer and would ignore one. ]]
		[MusicConfig.RemoteName] = function(player: Player, muted: unknown)
			MusicService:_onSet(player, muted)
		end,
	},
})

--- The profile, or nil if it has not loaded yet. Non-yielding, same contract as StartCarService's.
function MusicService._profile(self, player: Player)
	local profile = self._profiles[player]
	if profile and profile:IsActive() then
		return profile
	end
	return nil
end

--- Whether this player has the music off, as stored. False for a profile that has not landed.
function MusicService.isMuted(self, player: Player): boolean
	local profile = self:_profile(player)
	return profile ~= nil and profile:Get(MusicConfig.ProfileKey) == true
end

--[[ Take a set from the client. Shape-checked and nothing more (see the header).

	A non-boolean is dropped rather than coerced: `muted = "false"` is truthy in Lua, so coercing
	would store the exact opposite of what a buggy caller meant, and silently. ]]
function MusicService._onSet(self, player: Player, muted: unknown)
	if type(muted) ~= "boolean" then
		self.log:warn(string.format("%s sent a non-boolean music mute (%s); ignored.", player.Name, typeof(muted)))
		return
	end

	player:SetAttribute(MusicConfig.MuteAttribute, muted)

	local profile = self:_profile(player)
	if profile then
		profile:Set(MusicConfig.ProfileKey, muted)
	end
	-- No profile yet: the preference is dropped, which is the right outcome. See the header.
end

--[[ Publish the saved answer the moment the profile lands.

	THE ATTRIBUTE IS ALWAYS WRITTEN, including when the answer is `false`. The controller waits for
	it before it plays anything at all (`MusicConfig.SeedTimeout`), so "not muted" has to be said
	out loud — leaving the attribute unset would look identical to a profile that never loaded and
	would cost every unmuted player their timeout in silence. ]]
function MusicService._onPlayerAdded(self, player: Player)
	task.spawn(function()
		local ok, profile = pcall(function()
			return Data:GetProfileAsync(player)
		end)
		if not ok or not profile or player.Parent ~= Players then
			return
		end
		self._profiles[player] = profile

		player:SetAttribute(MusicConfig.MuteAttribute, profile:Get(MusicConfig.ProfileKey) == true)
	end)
end

MusicService:withLifecycle({
	init = function(self)
		self._profiles = {} :: { [Player]: any }
	end,

	start = function(self)
		self._trove = Trove.new()

		self._trove:Add(Players.PlayerAdded:Connect(function(player)
			self:_onPlayerAdded(player)
		end))
		self._trove:Add(Players.PlayerRemoving:Connect(function(player)
			self._profiles[player] = nil
		end))
		-- Anyone already in (Studio's own player joins before services start).
		for _, player in Players:GetPlayers() do
			self:_onPlayerAdded(player)
		end
	end,
})

return MusicService
