--[[
	SoundController  (client)
	-------------------------
	Two jobs, and they are the same job seen from either end: it PLAYS the game's one-shot feedback
	sounds, and it owns HOW LOUD every sound in the game that is not the soundtrack is.

	=== PLAYING ================================================================

	Non-positional feedback sounds come out of named SoundGroups under SoundService. A group's Sound
	children are interchangeable variations of the one effect; `PlayRandom` picks one.

	THE SOUNDS LIVE IN THE PLACE, NOT IN SOURCE. SoundService is not Rojo-synced, so the groups are
	authored in Studio and this only ever looks them up. `SoundService.UIHover` and
	`SoundService.UIClick` exist with their Sound children already created and their `SoundId` left
	blank, waiting for the boss to paste ids in. A blank id is not an error here — the group is
	found, a Sound is picked, and Roblox plays silence. Wiring works today and gets audible the
	moment an id lands, with no code change.

	A MISSING GROUP WARNS ONCE, THEN GOES QUIET. UI sound calls sit on hover and click, so a group
	that does not exist would otherwise warn several times a second and bury everything else in the
	output. The first miss is recorded and the group is disabled for the session.

	NO REPEAT BACK TO BACK. Two identical clips in a row read as a stutter rather than as feedback,
	and `PlayLocalSound` on the instance already playing cuts it off mid-sample. Both are avoided by
	stepping to the next variation when the random pick matches the last one.

	=== THE SFX LEVEL ==========================================================

	The settings screen's second slider ends here (`AudioConfig.Sfx`). It is deliberately not one
	number on one instance, because Roblox does not offer one:

	  • SOUNDGROUPS DO NOT NEST. There is no `SoundGroup.SoundGroup`, so a master group cannot sit
	    over `UIClick` and `NearMiss` and turn them both down. What this does instead is SCALE each
	    group in place, remembering the level it was authored at (`_authored`) so that scaling is
	    reversible and 100% means exactly the mix that shipped. Anything on `AudioConfig.Sfx.Exclude`
	    is left alone; those are the soundtrack's and the radio's, and two writers on one Volume is a
	    fight nobody wins.

	  • MOST OF THE GAME'S NOISE IS IN NO GROUP AT ALL. Every car carries an `Effects` folder of
	    engine, door and tyre Sounds authored with `SoundGroup` unset, and they are the loudest thing
	    a player hears. So ungrouped Sounds in the Workspace are ADOPTED into a master group of this
	    controller's own, which is then scaled like any other. Adoption is transparent at 100%: a
	    Sound in a group at Volume 1 sounds exactly like a Sound in no group.

	    A Sound that already has a group is never touched. That is what keeps the music decks and the
	    radio out of this, and it is also the escape hatch: author a Sound into any group and this
	    stops having an opinion about it.

	  • THE ADOPTION IS A SWEEP PLUS A LISTENER, and the listener is on Workspace, which is a hot
	    signal in this game because the road is built client-side a tile at a time. The handler is an
	    `IsA` test and an early return. `AudioConfig.Sfx.AdoptFrom` carries the measurement and the
	    argument for why that is affordable.

	NOTHING HERE IS AUTHORITATIVE AND NOTHING WAITS ON THE SERVER. A level applies the instant it is
	set and the remote that follows is a save, exactly as `MusicController`'s is; the seed comes in
	on a player attribute and is read once.
]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local AudioConfig = require(ReplicatedStorage.shared.Configs.AudioConfig)

local SoundController = Shard.new("SoundController")

-- [groupName] = { sounds = {Sound}, lastIndex = number? }, or false once warned-missing
local groups = {}

local function getGroup(name: string)
	local cached = groups[name]
	if cached ~= nil then
		return cached or nil
	end

	local group = SoundService:FindFirstChild(name)
	if not group then
		Shard.log:warn(`SoundController: SoundService.{name} not found; "{name}" sounds disabled.`)
		groups[name] = false
		return nil
	end

	local sounds = {}
	for _, child in group:GetChildren() do
		if child:IsA("Sound") then
			table.insert(sounds, child)
		end
	end

	local entry = { sounds = sounds, lastIndex = nil }
	groups[name] = entry
	return entry
end

--- Preload a group's clips. Safe to call on blank ids — they simply have nothing to fetch.
function SoundController.Preload(_self, groupName: string)
	local entry = getGroup(groupName)
	if not entry or #entry.sounds == 0 then
		return
	end
	task.spawn(function()
		local loadable = {}
		for _, sound in entry.sounds do
			if sound.SoundId ~= "" and sound.SoundId ~= "rbxassetid://0" then
				table.insert(loadable, sound)
			end
		end
		if #loadable > 0 then
			pcall(function()
				ContentProvider:PreloadAsync(loadable)
			end)
		end
	end)
end

local function pickSound(groupName: string): Sound?
	local entry = getGroup(groupName)
	if not entry or #entry.sounds == 0 then
		return nil
	end

	local count = #entry.sounds
	local index = math.random(count)
	if count > 1 and index == entry.lastIndex then
		index = (index % count) + 1
	end
	entry.lastIndex = index
	return entry.sounds[index]
end

--- Play one fire-and-forget clip from `groupName`, avoiding an immediate repeat.
function SoundController.PlayRandom(_self, groupName: string): Sound?
	local sound = pickSound(groupName)
	if not sound then
		return nil
	end
	SoundService:PlayLocalSound(sound)
	return sound
end

--[[ Play ONE NAMED clip out of `groupName` (2026-09-30), for a group that is a bank of different
	effects rather than variations of one — `SoundService.Steal` holds a Sound per beat of the steal
	(`StealJuiceConfig.Sounds`). A missing group warns once, like every call here; a missing NAME is
	silence without a warning, because it is a clip not yet authored rather than a broken build. ]]
local function namedSound(groupName: string, soundName: string): Sound?
	local entry = getGroup(groupName)
	if not entry then
		return nil
	end
	for _, sound in entry.sounds do
		if sound.Name == soundName then
			return sound
		end
	end
	return nil
end

function SoundController.PlayNamed(_self, groupName: string, soundName: string): Sound?
	local sound = namedSound(groupName, soundName)
	if sound then
		SoundService:PlayLocalSound(sound)
	end
	return sound
end

-- 2026-10-04: Cutscene buildup must stop at the hit or on abort. As with held nitro below,
-- PlayLocalSound's hidden copy cannot be stopped through the source template.
function SoundController.PlayNamedOwned(_self, groupName: string, soundName: string): Sound?
	local source = namedSound(groupName, soundName)
	if not source then
		return nil
	end
	local playback = source:Clone()
	playback.Name = `{source.Name}Playback`
	playback.Parent = SoundService
	playback:Play()
	return playback
end

--[[ Play a clip whose lifetime belongs to the caller.

	`PlayLocalSound` plays an internal COPY of its argument. Returning that argument therefore does
	not give a sustained effect anything it can stop: `sound:Stop()` only stops the untouched source
	template while the hidden copy keeps looping. An explicit client-side clone has a real identity,
	so nitro and any future held effect can stop and destroy the exact playback on release. ]]
function SoundController.PlayRandomOwned(_self, groupName: string): Sound?
	local source = pickSound(groupName)
	if not source then
		return nil
	end

	local playback = source:Clone()
	playback.Name = `{source.Name}Playback`
	playback.Parent = SoundService
	playback:Play()
	return playback
end

--[[ Play one clip from `groupName` POSITIONALLY, parented to `emitter` (a BasePart or Attachment), so
	Roblox pans and attenuates it from the listener. Used for the pass-by whoosh on the car you just
	overtook (`NearMissConfig.Whoosh`).

	A clone for the same reason `PlayRandomOwned` clones, and it cleans itself up: destroyed when it
	ends, with a delayed backstop for a clip that never reports `Ended` (a blank id plays nothing and
	may not). The group's `SoundGroup` rides along on the clone, so the SFX slider still applies. ]]
function SoundController.PlayRandomAt(
	_self,
	groupName: string,
	emitter: Instance,
	pitch: number?,
	volumeScale: number?,
	rollOffMin: number?,
	rollOffMax: number?
): Sound?
	local source = pickSound(groupName)
	if not (source and emitter and emitter.Parent) then
		return nil
	end

	local playback = source:Clone()
	playback.Name = `{source.Name}Positional`
	playback.PlaybackSpeed = source.PlaybackSpeed * (pitch or 1)
	playback.Volume = source.Volume * (volumeScale or 1)
	playback.RollOffMode = Enum.RollOffMode.InverseTapered
	if rollOffMin then
		playback.RollOffMinDistance = rollOffMin
	end
	if rollOffMax then
		playback.RollOffMaxDistance = rollOffMax
	end
	playback.Parent = emitter
	playback.Ended:Once(function()
		playback:Destroy()
	end)
	task.delay(6, function()
		if playback.Parent then
			playback:Destroy()
		end
	end)
	playback:Play()
	--- A `StartAt` attribute on the authored Sound skips its silent lead-in (2026-10-12, the crash
	--- clips): an impact that sounds 0.15 s after the hit reads as a different event.
	local startAt = source:GetAttribute("StartAt")
	if type(startAt) == "number" and startAt > 0 then
		playback.TimePosition = startAt
	end
	return playback
end

-- === The level ==============================================================

--- Public: the player's own 0 to 1 for everything that is not the soundtrack.
function SoundController.volume(self): number
	return self._volume
end

--[[ The master group ungrouped Sounds are adopted into.

	ADOPTED IF ONE IS ALREADY AUTHORED, and its Volume as found is what 100% means — the same
	bargain, and the same trap, as `MusicController._ensureGroup`'s. Scaling back to a hard 1 would
	silently discard a level somebody set in Studio and there would be nothing to see in the diff. ]]
function SoundController._ensureMaster(self): SoundGroup?
	if self._master then
		return self._master
	end

	local existing = SoundService:FindFirstChild(AudioConfig.Sfx.GroupName)
	if existing and existing:IsA("SoundGroup") then
		self._master = existing
	else
		local group = Instance.new("SoundGroup")
		group.Name = AudioConfig.Sfx.GroupName
		group.Volume = 1
		group.Parent = SoundService
		self._master = group
	end

	return self._master
end

--[[ Take a SoundGroup under this controller's management, recording the level it was authored at.

	THE AUTHORED LEVEL IS RECORDED ONCE AND NEVER RE-READ, because after the first scaling the
	instance's own Volume is this controller's arithmetic rather than anybody's decision. Reading it
	again would compound: a group scaled to 50% and then re-adopted would take 50% as its authored
	level and land at 25%. ]]
function SoundController._adoptGroup(self, group: SoundGroup)
	if self._authored[group] ~= nil or AudioConfig.Sfx.Exclude[group.Name] then
		return
	end
	self._authored[group] = group.Volume
	group.Volume = group.Volume * self._volume
end

--[[ Put an ungrouped Sound into the master group.

	`SoundGroup ~= nil` IS THE WHOLE FILTER and it is what keeps this out of everything that has
	already been placed: the music decks, the radios, and the UI clips sitting in their own groups.
	A Sound the game later assigns a group to is simply reassigned by whoever does that; nothing
	here holds it. ]]
function SoundController._adoptSound(self, sound: Sound)
	if sound.SoundGroup ~= nil then
		return
	end
	sound.SoundGroup = self._master
end

--[[ Apply `_volume` to everything this controller manages.

	TWEENED RATHER THAN SET, and short (`AudioConfig.RampSeconds`), for the reason a volume slider
	always wants: a level that jumps while a siren is mid-wail clicks, and a level that ramps over
	80ms does not, without the drag feeling like it is steering rather than dragging. ]]
function SoundController._applyLevel(self)
	for group, authored in self._authored do
		if group.Parent then
			TweenService:Create(
				group,
				TweenInfo.new(AudioConfig.RampSeconds, Enum.EasingStyle.Linear),
				{ Volume = authored * self._volume }
			):Play()
		else
			self._authored[group] = nil -- destroyed since; stop holding a reference to it
		end
	end
end

--[[ Public (the settings screen's slider): set the level, apply it now, and remember it.

	`persist` separates a drag from the seed, exactly as `MusicController.setVolume` does: a drag is
	the player's decision and is saved, the seed IS the saved answer arriving and must not be sent
	straight back. ]]
function SoundController.setVolume(self, volume: unknown, persist: boolean?)
	local level = AudioConfig.clamp(volume, AudioConfig.Sfx.Default)

	--- A set that moves nothing still saves. `MusicController.setVolume` has the reason, and it is
	--- the same slider at the other end of the same drag.
	if level ~= self._volume or not self._appliedOnce then
		self._volume = level
		self._appliedOnce = true
		self:_applyLevel()
		Dispatcher:Publish(AudioConfig.Sfx.StateEvent, level)
	end

	if persist then
		self._touched = true
		self:getRemoteEvent(AudioConfig.Sfx.RemoteName):Fire(level)
	end
end

--- The saved level arriving, once. Loses to a drag that got in first, for the reason
--- `MusicController._seed` gives.
function SoundController._seed(self, volume: unknown)
	if self._seeded or self._touched then
		return
	end
	self._seeded = true
	self:setVolume(volume, false)
end

--[[ Find everything there is to manage and start watching for more.

	THE GROUP SWEEP IS ALSO A LISTENER because two of the groups do not exist yet when this runs:
	`MusicController` and `RadioController` both create theirs on demand, and while both are excluded
	by name, anything else authored or created later is not. One `ChildAdded` on SoundService covers
	it and fires a handful of times in a session. ]]
function SoundController._watch(self)
	self:_ensureMaster()

	for _, child in SoundService:GetChildren() do
		if child:IsA("SoundGroup") then
			self:_adoptGroup(child)
		end
	end
	self._groupWatch = SoundService.ChildAdded:Connect(function(child)
		if child:IsA("SoundGroup") then
			self:_adoptGroup(child)
		end
	end)

	local root = game:GetService(AudioConfig.Sfx.AdoptFrom)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("Sound") then
			self:_adoptSound(descendant)
		end
	end
	--- See the header: this is a hot signal and the handler is deliberately one type test.
	root.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Sound") then
			self:_adoptSound(descendant)
		end
	end)
end

SoundController:withRemoteEvents({ AudioConfig.Sfx.RemoteName })

SoundController:withLifecycle({
	init = function(self)
		self._volume = AudioConfig.Sfx.Default
		self._master = nil :: SoundGroup?
		--- [SoundGroup] = the Volume it was authored at. See `_adoptGroup` on why it is read once.
		self._authored = {} :: { [SoundGroup]: number }
		self._seeded = false
		self._touched = false
		self._appliedOnce = false
	end,
	start = function(self)
		for _, groupName in { "UIHover", "UIClick" } do
			self:Preload(groupName)
		end
		--[[ ...AND EVERY OTHER GROUP, a few seconds in (2026-10-07). The first-bank freeze
			(`Modules/HitchProbe`) had the truck doors' sound playing for the FIRST TIME in the same frame
			as a second-long stall; a clip nobody has preloaded is fetched and decoded when it is first
			played, in the middle of the moment it was meant to decorate. So every group in SoundService
			is fetched once the join has settled — after the UI's own two, and late enough not to
			compete with the place itself loading. A blank clip has nothing to fetch (`Preload`). ]]
		task.delay(6, function()
			for _, group in SoundService:GetChildren() do
				if group:IsA("SoundGroup") and group.Name ~= "UIHover" and group.Name ~= "UIClick" then
					self:Preload(group.Name)
				end
			end
		end)

		if not AudioConfig.Enabled or not AudioConfig.Sfx.Enabled then
			return
		end

		self:_watch()

		--[[ The seed, whichever way round the attribute and this controller arrive in. There is no
			timeout under it and there does not need to be one: unlike the music, which stays SILENT
			until it has been answered, the effects are already playing at the authored mix and a
			profile that never lands simply leaves them there. ]]
		local player = Players.LocalPlayer
		local existing = player:GetAttribute(AudioConfig.Sfx.Attribute)
		if existing ~= nil then
			self:_seed(existing)
		else
			local connection
			connection = player:GetAttributeChangedSignal(AudioConfig.Sfx.Attribute):Connect(function()
				connection:Disconnect()
				self:_seed(player:GetAttribute(AudioConfig.Sfx.Attribute))
			end)
		end
	end,
})

return SoundController
