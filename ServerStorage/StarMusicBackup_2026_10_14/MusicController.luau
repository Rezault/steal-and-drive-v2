--[[
	MusicController  (client)
	-------------------------
	The soundtrack. Owns two decks, decides which playlist they draw from, and owns the mute. What
	plays where is `MusicConfig`; this is only the machine that plays it.

	  • TWO DECKS, AND ONLY TO CROSSFADE. One Sound cannot fade out while another fades in, so
	    there are two and they take turns. Everything else — the playlist, the shuffle, the mute —
	    is single-state and lives on the controller; the decks are just the pair of voices it has.
	    Within a playlist only one deck is ever in use (a track ends, a gap, the next one starts on
	    the same deck); the second one exists for the moment the CONTEXT changes.

	  • THE CONTEXT IS "LOBBY" OR A WORLD INDEX, and it comes from the same `RaceStart`/`RaceEnd`
	    pair `WorldController` and `RaceEntryController` bracket a run with — for the same reason
	    they use that pair rather than `RaceEntering`/`RaceLive`: it is the pairing that always
	    closes, including on the entry paths that fail after the fade has gone up. Music that did
	    not come back because a race half-failed would be a bug nobody could reproduce.

	    THE WAY IN IS DELAYED. `RaceStart` names the world but does not switch to it: the lobby
	    music plays on under the entry's loading screen and the road's music starts as that screen
	    lifts (`RaceConfig.RevealedEvent`), so the music changes when the picture does. `_holdRoad`
	    has the details. `RaceEnd` still switches back to the lobby at once.

	  • A WRECK DOES NOT CHANGE THE MUSIC, on purpose. A wreck is no longer the end of a run — a
	    banked life brings the player back on the same road — so cutting to lobby music on
	    `RaceWrecked` would be wrong for every revived player and would have to be undone by a
	    handler on `RaceRevived`. `RaceEnd` fires once the run has actually settled either way, and
	    it is the only thing here that listens.

	  • THE SHUFFLE IS A BAG, NOT A DIE. A fresh shuffle of the whole list is dealt out one track
	    at a time and re-dealt when it runs out, so four tracks means all four before any repeats.
	    Rolling at random instead clumps — the same track twice in five minutes reads as a broken
	    playlist, and with four tracks it happens constantly. The one seam is the join between two
	    bags, where the last of one and the first of the next can be the same track; `_refillBag`
	    is what stops that, and it is the same "no repeat back to back" rule `SoundController`
	    applies to its one-shots.

	  • A TRACK THAT NEVER LOADS MUST NOT END THE MUSIC. `Sound.Ended` advances the playlist, and it
	    never fires for an id that was moderated, made private, or mistyped — so a watchdog gives
	    every track a bounded time to prove it is playing and skips it if it does not. It only
	    guards the START: once a track is audibly running, `Ended` owns it. See `_armWatchdog`.

	=== THE MUTE AND THE SLIDER ARE ONE NUMBER =================================

	There is no mute FLAG on this controller. There is a level, `_volume`, which is the player's own
	0 to 1 (`AudioConfig.Music`), and MUTED IS WHAT ZERO MEANS. The topbar button sets it to zero and
	back to whatever it last was; the settings screen's slider sets it to anything.

	That is worth being firm about, because the obvious alternative is a boolean beside a slider and
	it has a bug in it that cannot be written out: press unmute while the slider sits at 0 and
	nothing happens, because both facts have to agree before a sound comes out and only one of them
	moved. One number cannot disagree with itself.

	`_lastAudible` is the whole cost of the arrangement: the level to come back to when the button
	unmutes. It is remembered rather than defaulted so that a player who mixed the music down to 20%
	and then muted gets 20% back, not full.

	=== WHO OWNS THE LEVEL =====================================================

	THE CLIENT DOES, AND THIS IS THE ONLY PRESS IN THE GAME THAT WORKS THAT WAY. Everywhere else —
	buying a world, choosing a car, selling — the server decides and the client waits for an
	attribute to come back, because the server is the thing being asked for something. Nothing is
	being asked for here. There is no ruling the server could make about whether this player's
	speakers make noise, and a round trip before the sound stops would make a mute button that
	visibly lags, which is the one thing a mute button must never do.

	So: a press applies instantly and locally, and the remote that follows is a SAVE, not a request.

	The server's copy still matters exactly once — on the way in, as the seed. That is the whole
	reason `_seeded` and `_touched` exist:

	  • `_seeded` is "the server has told us what this player chose last time". Until it is set, or
	    `MusicConfig.SeedTimeout` passes, NOTHING PLAYS. Starting unmuted and correcting a moment
	    later would give a player who muted the game a slice of music on every single join, which is
	    precisely what they turned off.
	  • `_touched` is "they have pressed the button this session", and it makes the seed lose. A
	    profile that loads slowly can land its attribute after an impatient player has already
	    pressed mute, and without this the save would arrive and un-mute them.

	After those two, the attribute is not read again. It is a seed, not a channel.
]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local AudioConfig = require(ReplicatedStorage.shared.Configs.AudioConfig)
local MusicConfig = require(ReplicatedStorage.shared.Configs.MusicConfig)
local RaceConfig = require(ReplicatedStorage.shared.Configs.RaceConfig)
local RadioConfig = require(ReplicatedStorage.shared.Configs.RadioConfig)

local MusicController = Shard.new("MusicController")

type Track = MusicConfig.Track

-- A voice: its Sound, the fade currently running on it, and a token that invalidates that fade's
-- completion callback if something newer takes the deck over mid-fade.
type Deck = {
	sound: Sound,
	tween: Tween?,
	fadeToken: number,
}

--[[ Does this deck have a track on it at all?

	ASKED BEFORE EVERY Play/Pause/Resume DECISION, because "is this Sound playing" is not the same
	question and answering the wrong one silently kills the soundtrack.

	A FRESH `Sound` REPORTS `IsPaused = true`. Not false — a Sound that has never been played, has
	no `SoundId` and has never been parented anywhere already claims to be paused (measured in a
	playtest 2026-08-20, both parented and not). So an unmute that resumes "everything paused"
	resumes both empty decks, which sets `Playing = true` on a Sound with nothing on it, and from
	then on every "is something already playing?" check answers yes and no track is ever started.
	That is a game with a music system, two decks, no errors and total silence.

	`SoundId ~= ""` is the honest test, and it is the one thing that cannot lie: this controller is
	the only writer of it, and it only ever writes a real id. ]]
local function hasTrack(deck: Deck): boolean
	return deck.sound.SoundId ~= ""
end

-- === The decks ==============================================================

--[[ The SoundGroup everything plays through, and the level the mute returns to.

	An authored group wins (`MusicConfig.SoundGroupName` — the mix can be trimmed in Studio without
	a build), and its Volume AS FOUND becomes the unmuted target rather than a hard 1. Getting that
	wrong is the trap this function exists to avoid: fading back to 1 on unmute would silently
	discard whatever level someone had set and there would be nothing to see in the diff. ]]
function MusicController._ensureGroup(self)
	local existing = SoundService:FindFirstChild(MusicConfig.SoundGroupName)
	if existing and existing:IsA("SoundGroup") then
		self._group = existing
		self._groupVolume = existing.Volume
		return
	end

	local group = Instance.new("SoundGroup")
	group.Name = MusicConfig.SoundGroupName
	group.Volume = 1
	group.Parent = SoundService
	self._group = group
	self._groupVolume = 1
end

--- One deck. Parented to the group so nothing here depends on a character, a PlayerGui, or the
--- camera surviving a respawn — a soundtrack that stopped when you died would be its own bug.
function MusicController._makeDeck(self, index: number): Deck
	local sound = Instance.new("Sound")
	sound.Name = `MusicDeck{index}`
	sound.Volume = 0
	sound.Looped = false
	sound.SoundGroup = self._group
	sound.Parent = self._group

	local deck: Deck = { sound = sound, tween = nil, fadeToken = 0 }

	--[[ The normal way a playlist advances, and the only one for a track that plays through.

		GUARDED ON WHICH DECK THIS IS, because a crossfade leaves the outgoing deck running for
		`CrossfadeSeconds` after it stopped being the active one — and a track short enough to
		finish inside that window would otherwise queue a second track behind the one the new deck
		has just started. Only the deck currently holding the playlist gets to advance it. ]]
	sound.Ended:Connect(function()
		if deck ~= self:_activeDeck() then
			return
		end
		self:_scheduleNext(MusicConfig.GapSeconds)
	end)

	return deck
end

function MusicController._activeDeck(self): Deck
	return self._decks[self._active]
end

--[[ Fade one deck to `target`, optionally stopping it at the end.

	The token is what makes this safe to call over itself. A deck that is fading out and gets
	handed a new track mid-fade must NOT then be stopped by the old fade's completion, and that is
	not hypothetical — it is what a player pressing PLAY and immediately backing out does. ]]
function MusicController._fadeDeck(self, deck: Deck, target: number, seconds: number, stopAfter: boolean?)
	deck.fadeToken += 1
	local token = deck.fadeToken

	if deck.tween then
		deck.tween:Cancel()
		deck.tween = nil
	end

	if seconds <= 0 then
		deck.sound.Volume = target
		if stopAfter then
			deck.sound:Stop()
			deck.sound.SoundId = ""
		end
		return
	end

	local tween = TweenService:Create(deck.sound, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Volume = target })
	deck.tween = tween
	tween.Completed:Connect(function()
		if deck.fadeToken ~= token then
			return -- something newer owns this deck; its fade decides what happens next
		end
		deck.tween = nil
		if stopAfter then
			--[[ Emptied as well as stopped. A stopped Sound reports `IsPaused` (see `hasTrack`), so
				a deck left holding its id would be resumed by the next unmute or unduck and play the
				old context's track at zero volume underneath, or answer `_ensurePlaying` as busy. ]]
			deck.sound:Stop()
			deck.sound.SoundId = ""
		end
	end)
	tween:Play()
end

-- === The playlist ===========================================================

--[[ Deal a fresh shuffled bag of the current context's playlist.

	`avoid` is the track that just played, and it is only ever the LAST track of the previous bag.
	If the shuffle puts it first, it is swapped with the next one along — enough to guarantee no
	back-to-back repeat without biasing the rest of the order, and a no-op on a one-track list,
	where a repeat is the only thing that can happen. ]]
function MusicController._refillBag(self, avoid: number?)
	local playlist = MusicConfig.playlistFor(self._context)

	local bag = table.clone(playlist)
	for i = #bag, 2, -1 do
		local j = math.random(i)
		bag[i], bag[j] = bag[j], bag[i]
	end

	if avoid and #bag > 1 and bag[1].Id == avoid then
		bag[1], bag[2] = bag[2], bag[1]
	end

	self._bag = bag
end

--- The next track to play, or nil if this context has no music configured at all.
function MusicController._nextTrack(self): Track?
	if not self._bag or #self._bag == 0 then
		self:_refillBag(self._lastTrackId)
	end
	if #self._bag == 0 then
		return nil -- an empty playlist is a real answer: silence, not a stall
	end
	return table.remove(self._bag, 1)
end

--[[ Put a track on the active deck and fade it up over `fadeIn`.

	NO-OP WHILE MUTED, and that is the whole of how muting saves bandwidth: a muted player never
	starts a track at all, rather than streaming one down and playing it at zero. The deck is left
	empty and `_ensurePlaying` starts one the moment they unmute. ]]
function MusicController._beginTrack(self, fadeIn: number)
	if self:_silent() or not self._seeded then
		return
	end

	local track = self:_nextTrack()
	if not track then
		return
	end

	local deck = self:_activeDeck()
	self._generation += 1
	self._lastTrackId = track.Id

	deck.sound:Stop()
	deck.sound.SoundId = `rbxassetid://{track.Id}`
	deck.sound.Volume = 0
	deck.sound.TimePosition = 0
	deck.sound:Play()

	self:_fadeDeck(deck, MusicConfig.volumeOf(track), fadeIn)
	self:_armWatchdog(deck, self._generation, track)
end

--- Start the next track after `delay` seconds of air. Generation-guarded so a context change
--- during the gap cancels it rather than dropping a lobby track onto a race that has begun.
function MusicController._scheduleNext(self, delay: number)
	self._generation += 1
	local generation = self._generation
	task.delay(delay, function()
		if self._generation ~= generation then
			return
		end
		self:_beginTrack(0)
	end)
end

--[[ Give a just-started track a bounded time to prove it is real, and skip it if it does not.

	IT ONLY GUARDS THE START. Once `TimeLength` has resolved the track is known-good and `Sound.Ended`
	owns the rest of it — which matters, because the alternative (a watchdog that also counts the
	track out) would have to know about pausing, and a muted deck is a paused deck whose clock has
	stopped. Guarding only the load keeps this ignorant of the mute entirely.

	The failure it exists for is an id that never resolves: moderated after it went in the list,
	made private by its uploader, or simply mistyped. `Ended` never fires for any of those, so
	without this one bad number is not a skipped track, it is the end of the music for the session. ]]
function MusicController._armWatchdog(self, deck: Deck, generation: number, track: Track)
	task.spawn(function()
		local waited = 0
		while waited < MusicConfig.LoadTimeout do
			if self._generation ~= generation then
				return -- superseded; whatever replaced us has its own watchdog
			end
			if deck.sound.TimeLength > 0 then
				return -- it is real, and `Ended` will advance it
			end
			task.wait(0.25)
			waited += 0.25
		end

		if self._generation ~= generation then
			return
		end
		self.log:warn(string.format(
			"Music track %s (%d) never loaded after %ds; skipping it.",
			track.Name or "?", track.Id, MusicConfig.LoadTimeout))
		self:_scheduleNext(MusicConfig.TrackTimeoutSlack)
	end)
end

--- Start something if something should be playing and nothing is. The unmute path, and the seed's.
function MusicController._ensurePlaying(self, fadeIn: number)
	if self:_silent() or not self._seeded then
		return
	end
	local deck = self:_activeDeck()
	if hasTrack(deck) and (deck.sound.IsPlaying or deck.sound.IsPaused) then
		return
	end
	self:_beginTrack(fadeIn)
end

-- === Context ================================================================

--[[ Public: what the player is doing, which decides what they hear. `MusicConfig.LobbyContext` for
	everywhere that is not a run, a world index for a road.

	Idempotent — being told the context you are already in is a no-op, not a restart. That matters
	because `RaceEnd` can arrive on paths that never got as far as a `RaceStart`, and restarting the
	lobby playlist under a player who never left the lobby would be an audible glitch with no
	visible cause. ]]
function MusicController.setContext(self, context: unknown)
	if self._context == context then
		return
	end
	self._context = context
	self._bag = nil -- a new playlist deals a new bag; the old one's remainder is not ours

	if not MusicConfig.Enabled then
		return
	end

	--[[ The handover. The outgoing deck fades out and stops itself; the incoming one becomes
		active and starts the new list. Swapping BEFORE starting is what makes the two overlap —
		start on the same deck and the fade-out would be fading out the new track. ]]
	local outgoing = self:_activeDeck()
	self:_fadeDeck(outgoing, 0, MusicConfig.CrossfadeSeconds, true)
	self._active = 3 - self._active

	self._generation += 1
	self:_beginTrack(MusicConfig.CrossfadeSeconds)

	-- Leaving the lobby lets go of a radio duck, and coming back into one takes it up again.
	self:_refreshDuck()
end

--[[ A run has started building, in `world`. HELD, NOT PLAYED: the road's music waits for the road.

	`RaceStart` lands while the entry's loading screen is still up. Switching there cut the lobby
	music off under a black screen and had the road's music a crossfade in before there was anything
	to look at. So the lobby list plays on, and `_releaseRoad` does the handover when
	`RaceUIController` lifts the screen.

	`MusicConfig.RevealTimeout` is the floor under a screen that never says so. The token keeps one
	run's timer out of the next: a player who wrecks and goes straight back in can be behind a second
	loading screen when the first run's timer comes due, and that timer must not start the music
	under it. ]]
function MusicController._holdRoad(self, world: number?)
	self._roadWorld = world
	self._roadToken += 1
	if world == nil then
		return
	end

	local token = self._roadToken
	task.delay(MusicConfig.RevealTimeout, function()
		if self._roadToken ~= token or self._roadWorld == nil then
			return
		end
		self.log:warn(string.format(
			"The loading screen never reported lifting after %ds; starting the road's music anyway.",
			MusicConfig.RevealTimeout))
		self:_releaseRoad()
	end)
end

--- The loading screen is lifting: hand over to the held world's music. A no-op with nothing held,
--- which is every lift that did not follow a `RaceStart` (an entry that never got as far as a car).
function MusicController._releaseRoad(self)
	local world = self._roadWorld
	if world == nil then
		return
	end
	self._roadWorld = nil
	self:setContext(world)
end

-- === The level ==============================================================

--- Public (the settings screen's slider): the player's own 0 to 1. Not the SoundGroup's volume and
--- not a track's; see `AudioConfig`'s header on why a player level is a multiplier.
function MusicController.volume(self): number
	return self._volume
end

--- Public (the topbar button): is the music off? Which is the same question as "is the level 0",
--- and deliberately has no second fact behind it. See the header.
function MusicController.isMuted(self): boolean
	return self._volume <= 0
end

--- Public (the first-person cabin's dash screen): the track the soundtrack is playing and the Sound
--- it is playing on, or nil between tracks, while muted and before anything has started.
function MusicController.nowPlaying(self): (MusicConfig.Track?, Sound?)
	local deck = self._decks and self:_activeDeck()
	if not (deck and deck.sound.IsPlaying and self._lastTrackId) then
		return nil, nil
	end
	for _, track in MusicConfig.allTracks() do
		if track.Id == self._lastTrackId then
			return track, deck.sound
		end
	end
	return nil, deck.sound
end

--[[ Is the soundtrack making way for a car radio? Only ever the lobby playlist, and only while
	`RadioController` says one is on within earshot (`RadioConfig.DuckMusic`).

	NOT A MUTE, and kept apart from `_volume` on purpose: the topbar button and the slider stay
	exactly where the player left them, nothing is saved, and `MusicConfig.StateEvent` is not
	published, so the radios themselves (which follow that event) keep playing. ]]
function MusicController._ducked(self): boolean
	return self._radioNear and self._context == MusicConfig.LobbyContext
end

--- Should nothing be audible right now, for either reason. What the deck paths ask instead of
--- `isMuted`, so a duck pauses and resumes through the same machine a mute does.
function MusicController._silent(self): boolean
	return self:isMuted() or self:_ducked()
end

--- Apply the duck if it has changed since it was last applied. Called when a radio comes into or
--- out of range and on every context change, since leaving the lobby releases it.
function MusicController._refreshDuck(self)
	local ducked = self:_ducked()
	if ducked == self._duckApplied then
		return
	end
	self._duckApplied = ducked
	self:_applyLevel(RadioConfig.DuckMusic.FadeSeconds)
end

--- What the SoundGroup should be sitting at: the authored group level scaled by the player's own.
--- The one place the two are combined, so nothing else has to remember that both exist.
function MusicController._target(self): number
	return self._groupVolume * self._volume
end

--[[ Take the group to where `_target` says it should be.

	Volume rides the SoundGroup rather than the decks so a crossfade in progress keeps its own shape
	underneath, and the decks are paused only once they are inaudible.

	ONE PATH FOR BOTH JOBS, and that is the point of it being written this way: a mute, an unmute and
	a slider being dragged are the same instruction with a different destination and a different
	duration. `seconds` is the only thing a caller chooses. ]]
function MusicController._applyLevel(self, seconds: number)
	if not self._group then
		return
	end

	if self._levelTween then
		self._levelTween:Cancel()
		self._levelTween = nil
	end

	self._levelToken += 1
	local token = self._levelToken

	if self:_silent() then
		local tween =
			TweenService:Create(self._group, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Volume = 0 })
		self._levelTween = tween
		tween.Completed:Connect(function()
			if self._levelToken ~= token then
				return -- raised again mid-fade; do not pause a deck that is coming back up
			end
			self._levelTween = nil
			for _, deck in self._decks do
				if hasTrack(deck) and deck.sound.IsPlaying then
					deck.sound:Pause()
				end
			end
		end)
		tween:Play()
		return
	end

	--[[ Coming back. Resume before the fade rather than after, so the group's rise IS the fade in;
		a deck resumed at the end of it would pop in at full level. A deck with nothing on it — the
		player muted before a track ever started, or across a context change — gets one now.

		Both of these are no-ops for a slider nudged from 60% to 65%, which is why that case is
		allowed to come through here rather than needing a path of its own. ]]
	for _, deck in self._decks do
		if hasTrack(deck) and deck.sound.IsPaused then
			deck.sound:Resume()
		end
	end

	local tween = TweenService:Create(
		self._group,
		TweenInfo.new(seconds, Enum.EasingStyle.Linear),
		{ Volume = self:_target() }
	)
	self._levelTween = tween
	tween:Play()

	self:_ensurePlaying(seconds)
end

--[[ Public: set the level, apply it now, and remember it.

	`persist` is what separates a press from the seed. A press is the player's decision and is sent
	to the server to be saved; the seed IS the server's saved answer arriving and must not be sent
	straight back to it.

	TWO EVENTS COME OUT OF ONE MOVE and both are published every time, not only when they change.
	`AudioConfig.Music.StateEvent` carries the level for the slider; `MusicConfig.StateEvent` carries
	the mute for the topbar button, which has been drawn from it since long before there was a
	slider. Publishing unconditionally costs two table lookups and means neither listener has to
	care which of them the move was really about.

	THE OLD BOOLEAN IS STILL SAVED, but only when the muted-ness actually flips. `MusicService` owns
	that key and is the thing a rolled-back build would read; keeping it current is one remote on the
	two presses that change it rather than one on every step of a drag. ]]
function MusicController.setVolume(self, volume: unknown, persist: boolean?)
	local level = AudioConfig.clamp(volume, AudioConfig.Music.Default)
	local flipped = false

	--[[ A SET THAT MOVES NOTHING STILL SAVES, and that is not a stray branch: the settings screen
		re-sets the level it is already sitting on when a drag is let go, because it applies every
		frame of a drag and only SAVES at the end. Early-returning out of the whole function would
		mean the last thing anybody dragged was the one thing never written down. ]]
	if level ~= self._volume or not self._appliedOnce then
		local wasMuted = self:isMuted()
		self._volume = level
		if level > 0 then
			self._lastAudible = level
		end
		flipped = self:isMuted() ~= wasMuted or not self._appliedOnce
		self._appliedOnce = true

		--- A mute is a fade the player is meant to hear; a slider is meant to feel like the knob is
		--- dragging the sound. Different durations, same instruction.
		self:_applyLevel(if flipped then MusicConfig.MuteFadeSeconds else AudioConfig.RampSeconds)

		Dispatcher:Publish(AudioConfig.Music.StateEvent, level)
		Dispatcher:Publish(MusicConfig.StateEvent, self:isMuted())
	end

	if persist then
		self._touched = true
		self:getRemoteEvent(AudioConfig.Music.RemoteName):Fire(level)
		if flipped then
			self:getRemoteEvent(MusicConfig.RemoteName):Fire(self:isMuted())
		end
	end
end

--[[ Public: mute or unmute, which is the level going to zero and coming back.

	UNMUTING GOES BACK TO `_lastAudible`, never to a constant, so the button returns the player to
	their own mix. `_lastAudible` starts at the default, so the button works before the slider has
	ever been touched. ]]
function MusicController.setMuted(self, muted: boolean, persist: boolean?)
	if muted then
		self:setVolume(0, persist)
	else
		self:setVolume(self._lastAudible, persist)
	end
end

--- Public (the topbar button): flip it. Always a press, so always saved.
function MusicController.toggleMuted(self): boolean
	self:setMuted(not self:isMuted(), true)
	return self:isMuted()
end

-- === The seed ===============================================================

--[[ Take the server's saved answer, once, and let the music start.

	IGNORED IF THE PLAYER HAS ALREADY MOVED THE LEVEL (`_touched`). A profile that loads slowly can
	land its attribute after an impatient player has muted, and adopting it then would un-mute
	them — the save arriving would undo the press that is about to be saved. ]]
function MusicController._seed(self, volume: number?)
	if self._seeded or self._touched then
		return
	end
	--- Before the set, because `setVolume` starts a track through `_applyLevel` and `_beginTrack`
	--- refuses to while this is false.
	self._seeded = true

	self:setVolume(volume, false)
	self:_ensurePlaying(MusicConfig.CrossfadeSeconds)
end

--[[ The saved level, out of the two attributes that could be carrying it.

	THE NUMBER WINS AND THE OLD BOOLEAN IS THE FALLBACK. `AudioConfig.Music.Attribute` is written by
	`SettingsService` for every player on every join, so it is present for everybody a current server
	has seen; `MusicConfig.MuteAttribute` is what a profile saved before the slider existed has, and
	all it can say is "off" or "not off".

	Nil means neither has landed yet, which is a real answer and is what the caller waits on. ]]
function MusicController._savedLevel(self, player: Player): number?
	local level = player:GetAttribute(AudioConfig.Music.Attribute)
	if level ~= nil then
		return AudioConfig.clamp(level, AudioConfig.Music.Default)
	end

	local muted = player:GetAttribute(MusicConfig.MuteAttribute)
	if muted ~= nil then
		return if muted == true then 0 else AudioConfig.Music.Default
	end

	return nil
end

MusicController:withRemoteEvents({
	{
		--[[ The run's brackets, and the only things that move the music between playlists. `world`
			is the index the server put the player in — taken from the message rather than read off
			the player attribute, because that write and this fire are not ordered against each
			other and reading it here would sometimes get the world they were in BEFORE. ]]
		RaceStart = function(_seed: any, world: any)
			MusicController:_holdRoad(tonumber(world))
		end,
		RaceEnd = function()
			-- An entry that ends before its screen lifts (an abort) lets go of the world it held.
			MusicController:_holdRoad(nil)
			MusicController:setContext(MusicConfig.LobbyContext)
		end,
	},
	MusicConfig.RemoteName,
	AudioConfig.Music.RemoteName,
})

MusicController:withLifecycle({
	init = function(self)
		self._context = MusicConfig.LobbyContext
		--- The world a run is building in, held until its loading screen lifts. See `_holdRoad`.
		self._roadWorld = nil :: number?
		self._roadToken = 0
		self._bag = nil :: { Track }?
		self._lastTrackId = nil :: number?
		self._decks = {} :: { Deck }
		self._active = 1
		self._generation = 0
		--- The player's own 0 to 1, and the only thing on this controller that says whether there is
		--- any sound. Muted IS zero; see the header.
		self._volume = AudioConfig.Music.Default
		--- Where an unmute goes back to. The default until the slider has been touched.
		self._lastAudible = AudioConfig.Music.Default
		self._levelToken = 0
		self._levelTween = nil :: Tween?
		self._groupVolume = 1
		--[[ Nothing plays until one of these is true: the server answered (`_seeded`), or the
			player pressed the button before it did (`_touched`, which seeds itself). See the
			header's "Who owns the mute". ]]
		self._seeded = false
		self._touched = false
		self._appliedOnce = false
		--- A car radio is on within earshot (`RadioConfig.NearbyEvent`), and whether the duck that
		--- implies has been applied yet. See `_ducked`.
		self._radioNear = false
		self._duckApplied = false
	end,

	start = function(self)
		if not MusicConfig.Enabled then
			return
		end

		self:_ensureGroup()
		self._decks = { self:_makeDeck(1), self:_makeDeck(2) }

		-- The road's music starts as the entry's loading screen lifts. See `_holdRoad`.
		Dispatcher:Subscribe(RaceConfig.RevealedEvent, function()
			self:_releaseRoad()
		end)

		--[[ The lobby music makes way for a car radio. Seeded from the controller as well as
			subscribed, because `Shard` start is not ordered and the radio's first answer can land
			before this subscription exists. ]]
		Dispatcher:Subscribe(RadioConfig.NearbyEvent, function(near: boolean)
			self._radioNear = near == true
			self:_refreshDuck()
		end)
		local RadioController = Shard.get("RadioController")
		self._radioNear = RadioController ~= nil and RadioController.isNearby ~= nil and RadioController:isNearby()
		self:_refreshDuck()

		local player = Players.LocalPlayer

		--[[ The seed, whichever way round the attributes and this controller arrive in.

			BOTH ATTRIBUTES ARE WATCHED, and the first one to land that `_savedLevel` will answer on
			wins. They come from two different services reading the same profile, so their order is
			not defined; watching only one of them would mean a build where the other service is the
			only one running seeds from the timeout instead of from the save. ]]
		local existing = self:_savedLevel(player)
		if existing ~= nil then
			self:_seed(existing)
		else
			local connections = {}
			local function stopWatching()
				for _, connection in connections do
					connection:Disconnect()
				end
				table.clear(connections)
			end

			for _, attribute in { AudioConfig.Music.Attribute, MusicConfig.MuteAttribute } do
				table.insert(
					connections,
					player:GetAttributeChangedSignal(attribute):Connect(function()
						local level = self:_savedLevel(player)
						if level == nil then
							return
						end
						stopWatching()
						self:_seed(level)
					end)
				)
			end

			--[[ ...and a floor under it. A profile that never loads, a server with the service
				switched off, or Studio's own player joining before anything wrote the attribute
				would otherwise mean a session with no music at all — which is a far worse failure
				than the second of misplaced music the wait exists to avoid. ]]
			task.delay(MusicConfig.SeedTimeout, function()
				if not self._seeded and not self._touched then
					self.log:info("No saved music preference arrived; starting at the default level.")
					stopWatching()
					self:_seed(AudioConfig.Music.Default)
				end
			end)
		end

		--[[ The lobby list and the driving list, fetched while the player is still reading the loading
			screen. The driving list is one track, and every run on every road opens on it, so it
			earns the head start: without it the first race of a session starts its music however
			long that track takes to stream in. A world's own list (`MusicConfig.Worlds`) is left to
			the crossfade, since a player may never visit that world this session. Failures are
			ignored; this is a head start, not a gate. ]]
		task.spawn(function()
			local warm = {}
			for _, list in { MusicConfig.Lobby, MusicConfig.Driving } do
				for _, track in list do
					local probe = Instance.new("Sound")
					probe.SoundId = `rbxassetid://{track.Id}`
					probe.Parent = self._group
					table.insert(warm, probe)
				end
			end
			pcall(function()
				ContentProvider:PreloadAsync(warm)
			end)
			for _, probe in warm do
				probe:Destroy()
			end
		end)
	end,
})

return MusicController
