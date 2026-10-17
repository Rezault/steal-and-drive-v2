--[[
	SettingsService
	---------------
	Remembers what a player chose on the settings screen. Three things today: which sky their lobby
	runs, how loud the soundtrack is, and how loud everything else is.

	THE SERVER HAS NO PART IN ANY OF IT, and this file is written the way `MusicService` is for
	exactly that reason. There is no authority question about which sky somebody looks at or how loud
	their speakers are: the client applies a press instantly and tells this afterwards, which is the
	opposite of how every other press in the game works and is correct here. The sky is `Lighting`,
	the levels are SoundGroups, all of it is per client, and none of it can be cheated into an
	advantage.

	So, like the mute, every remote here is a STATEMENT rather than a request:

	  - NOTHING IS REFUSED. Each preference validates the SHAPE of the message and nothing else. The
	    guard is against a malformed profile write, not against a cheat, and the worst a client can
	    do by lying is give itself a different sky or a quieter game.

	  - THE ATTRIBUTE IS A SEED, NOT A CHANNEL. Written once when the profile lands and again on
	    every accepted set so a second client of the same player agrees. The controllers read it
	    ONCE on the way in and then stop listening, so writing it mid-session is bookkeeping and
	    the client has already moved on.

	  - THE WRITE IS FIRE AND FORGET, so it must not be able to throw. A profile that has not loaded
	    yet and a player who left in the same frame both mean there is nowhere to put this, and
	    dropping the preference is the right outcome for both.

	=== IT IS A LIST NOW, AND THAT IS THE WHOLE FILE ============================================

	`PREFERENCES` below is one entry per saved setting: the remote it arrives on, the profile key it
	lands in, the attribute it is seeded through, and the two small functions that say what a valid
	value is and what a stored one means. Everything else here walks that list. The remotes are
	built from it, `_onSet` handles any of them without being told which, and `_onPlayerAdded`
	seeds them all in one pass.

	A FOURTH SETTING IS AN ENTRY AND NOTHING ELSE. That was the promise this file was created on
	when it held one preference, and adding the two volumes is what cashed it: the sky's block is
	unchanged, and neither volume needed a line of machinery of its own.

	WHY A SETTINGS SERVICE RATHER THAN A DAY AND NIGHT ONE, and then a music one, and then a sound
	one. Because they all want the same three things and none of them are worth a file.
	`MusicService` stays where it is: the mute predates this screen, it is already written, and
	moving a live profile key to buy tidiness is a migration for nothing.

	=== THE MUSIC LEVEL INHERITS THE OLD MUTE ==================================================

	`_seedValue` on the music entry is the one place in this file that reads a key belonging to
	another service, and the reason is written up at `AudioConfig.Unset`: a profile saved before
	there was a slider has `MusicMuted` and no level, reconcile fills the level in with the
	template's sentinel, and this turns that pair back into the number the player actually meant.
	Once they touch the slider the sentinel is gone and this stops mattering forever.

	Doing it HERE rather than on the client is what makes it a single answer. The client watches
	both attributes and could work it out too, but then two services writing in an undefined order
	would decide which one it saw first, and a player who set the music to 40% would sometimes come
	back at full because the boolean landed a frame earlier.

	An unset sky preference is the empty string, which `DayNightConfig.resolve` reads as AUTO, so
	every profile written before this service existed already answers correctly for that one.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data = require(script.Parent.Parent.Data)
local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local AudioConfig = require(ReplicatedStorage.shared.Configs.AudioConfig)
local DayNightConfig = require(ReplicatedStorage.shared.Configs.DayNightConfig)
local MusicConfig = require(ReplicatedStorage.shared.Configs.MusicConfig)
--- A config and not `StealController`: the setting's keys live with the feature, and a config
--- requires nothing, so this cannot cycle.
local StealJuiceConfig = require(ReplicatedStorage.shared.Configs.StealJuiceConfig)

local SettingsService = Shard.new("SettingsService")

--[[ One entry per saved setting. See the header.

	`accept` turns whatever the client sent into the value to store, or nil to drop the message.
	`seedValue` turns what is stored into the value to publish on the attribute, and takes the
	profile rather than the stored value so that an entry may look at more than its own key — which
	exactly one of them does, and the header says why.

	A VOLUME IS CLAMPED RATHER THAN REFUSED, where an unknown sky key is refused. They are different
	kinds of wrong: a key from a newer build is a preference this server does not understand and must
	not overwrite, whereas 1.4 is a number with an obvious meaning and no version behind it. ]]
local PREFERENCES = {
	{
		Name = "sky",
		Remote = DayNightConfig.RemoteName,
		ProfileKey = DayNightConfig.ProfileKey,
		Attribute = DayNightConfig.Attribute,

		--[[ AN UNKNOWN KEY IS DROPPED RATHER THAN STORED. `DayNightConfig.resolve` would happily
			fold it into AUTO, but storing the folded value would silently rewrite a preference from
			a newer build that this server does not know about yet, which is the one way a rolling
			deploy could lose somebody's setting. Refusing to write it leaves whatever they had. ]]
		accept = function(value: unknown): unknown?
			if DayNightConfig.isPreference(value) then
				return value
			end
			return nil
		end,

		seedValue = function(profile): unknown
			return DayNightConfig.resolve(profile:Get(DayNightConfig.ProfileKey))
		end,
	},

	{
		Name = "music volume",
		Remote = AudioConfig.Music.RemoteName,
		ProfileKey = AudioConfig.Music.ProfileKey,
		Attribute = AudioConfig.Music.Attribute,

		accept = function(value: unknown): unknown?
			if not AudioConfig.isSet(value) then
				return nil
			end
			return AudioConfig.clamp(value, AudioConfig.Music.Default)
		end,

		--- The migration. See the header's last block, and `AudioConfig.Unset`.
		seedValue = function(profile): unknown
			local stored = profile:Get(AudioConfig.Music.ProfileKey)
			if AudioConfig.isSet(stored) then
				return AudioConfig.clamp(stored, AudioConfig.Music.Default)
			end
			return if profile:Get(MusicConfig.ProfileKey) == true then 0 else AudioConfig.Music.Default
		end,
	},

	{
		Name = "sound effects volume",
		Remote = AudioConfig.Sfx.RemoteName,
		ProfileKey = AudioConfig.Sfx.ProfileKey,
		Attribute = AudioConfig.Sfx.Attribute,

		accept = function(value: unknown): unknown?
			if not AudioConfig.isSet(value) then
				return nil
			end
			return AudioConfig.clamp(value, AudioConfig.Sfx.Default)
		end,

		--- No migration to do: nothing has ever stored a sound effects level, so an unset one is the
		--- default and always was.
		seedValue = function(profile): unknown
			return AudioConfig.clamp(profile:Get(AudioConfig.Sfx.ProfileKey), AudioConfig.Sfx.Default)
		end,
	},

	--- The car sounds level (2026-10-15, `AudioConfig.Car`), the sound effects one's twin.
	{
		Name = "car sounds volume",
		Remote = AudioConfig.Car.RemoteName,
		ProfileKey = AudioConfig.Car.ProfileKey,
		Attribute = AudioConfig.Car.Attribute,

		accept = function(value: unknown): unknown?
			if not AudioConfig.isSet(value) then
				return nil
			end
			return AudioConfig.clamp(value, AudioConfig.Car.Default)
		end,

		seedValue = function(profile): unknown
			return AudioConfig.clamp(profile:Get(AudioConfig.Car.ProfileKey), AudioConfig.Car.Default)
		end,
	},

	--[[ The steal cinematic on or off (2026-10-02, `StealJuiceConfig.Setting`). Refused rather than
		folded when unknown, for the sky's reason: never overwrite a key this server does not know. ]]
	{
		Name = "steal camera",
		Remote = StealJuiceConfig.Setting.RemoteName,
		ProfileKey = StealJuiceConfig.Setting.ProfileKey,
		Attribute = StealJuiceConfig.Setting.Attribute,

		accept = function(value: unknown): unknown?
			if value == StealJuiceConfig.Setting.On or value == StealJuiceConfig.Setting.Off then
				return value
			end
			return nil
		end,

		seedValue = function(profile): unknown
			return StealJuiceConfig.resolveSetting(profile:Get(StealJuiceConfig.Setting.ProfileKey))
		end,
	},
}

--[[ client -> server: "I picked this on the settings screen."

	Statements, not requests. The client has already applied each of these and is not waiting on an
	answer, so nothing is sent back. Built from `PREFERENCES` so a fourth setting needs no wiring. ]]
local handlers = {}
for _, preference in PREFERENCES do
	handlers[preference.Remote] = function(player: Player, value: unknown)
		SettingsService:_onSet(player, preference, value)
	end
end
SettingsService:withRemoteEvents({ handlers })

--- The profile, or nil if it has not loaded yet. Non-yielding, same contract as `MusicService`'s.
function SettingsService._profile(self, player: Player)
	local profile = self._profiles[player]
	if profile and profile:IsActive() then
		return profile
	end
	return nil
end

--- Which sky this player is on, as stored. AUTO for a profile that has not landed.
function SettingsService.skyPreference(self, player: Player): string
	local profile = self:_profile(player)
	if not profile then
		return DayNightConfig.Preference.Auto
	end
	return DayNightConfig.resolve(profile:Get(DayNightConfig.ProfileKey))
end

--- Take a set from the client. Shape checked by the preference's own `accept` and nothing more.
function SettingsService._onSet(self, player: Player, preference, value: unknown)
	local accepted = preference.accept(value)
	if accepted == nil then
		self.log:warn(
			string.format("%s sent an unusable %s (%s); ignored.", player.Name, preference.Name, tostring(value))
		)
		return
	end

	player:SetAttribute(preference.Attribute, accepted)

	local profile = self:_profile(player)
	if profile then
		profile:Set(preference.ProfileKey, accepted)
	end
	--- No profile yet: the preference is dropped, which is the right outcome. See the header.
end

--[[ Publish the saved answers the moment the profile lands.

	EVERY ATTRIBUTE IS ALWAYS WRITTEN, including when the answer is the default or the empty string.
	The controllers are waiting on them, so "no preference" has to be said out loud: leaving an
	attribute unset is indistinguishable from a profile that never loaded, and would cost every
	untouched player a seed timeout before their screen could show a settled answer. ]]
function SettingsService._onPlayerAdded(self, player: Player)
	task.spawn(function()
		local ok, profile = pcall(function()
			return Data:GetProfileAsync(player)
		end)
		if not ok or not profile or player.Parent ~= Players then
			return
		end
		self._profiles[player] = profile

		for _, preference in PREFERENCES do
			player:SetAttribute(preference.Attribute, preference.seedValue(profile))
		end
	end)
end

SettingsService:withLifecycle({
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
		--- Anyone already in. Studio's own player joins before services start.
		for _, player in Players:GetPlayers() do
			self:_onPlayerAdded(player)
		end
	end,
})

return SettingsService
