--[[
	RadioController  (client)
	-------------------------
	Every car radio you can hear. Finds the cars, builds their Sounds, keeps them in step with the
	clock, and puts them away when the car goes. `RadioPanelController` is the screen that asks for
	a station; this is the only thing in the game that makes a radio noise.

	IT IS `MusicController` FOR OTHER PEOPLE'S CARS, and the parallel is deliberate down to the
	watchdog. That one owns two decks and one playlist for the local player; this owns one deck PER
	CAR IN RANGE and takes its playlist from the car itself. Everything below that is not about
	multiplicity is the same machine.

	=== NOTHING IS EVER SENT TO A LISTENER =====================================

	A car carries three attributes — station, custom track id, and the server clock reading when the
	radio was switched on (`RadioConfig.StationAttribute` and friends) — and that is the entire
	protocol. `RadioConfig.sliceAt` turns them into "this track, this many seconds in, this long
	left", and because `workspace:GetServerTimeNow()` is the same number on every machine in the
	server, every listener computes the same answer without being told anything.

	THREE THINGS FALL OUT OF THAT AND ALL THREE ARE WHY IT IS BUILT THIS WAY:

	  • WALKING UP MID-SONG IS THE NORMAL CASE. There is no "join in progress" path because there is
	    no progress to join — a car streaming in eighty seconds into a track starts at second
	    eighty, and so does a player who has been standing there the whole time.
	  • THE MUTE BUTTON REACHES IT. The radio group is faded by this controller in answer to
	    `MusicConfig.StateEvent`, so the topbar button silences the soundtrack and every radio in
	    earshot with one press. A Sound the server had made would sit outside any client-side group
	    and would be the one piece of music in the game that button could not touch.
	  • STREAMING COSTS NOTHING. `RadioConfig.CarTag` is on every lobby car, playing or not, and
	    `CollectionService`'s added/removed signals fire on streaming as well as on parenting — so a
	    car leaving range takes its Sound with it and a car coming back builds a fresh one already
	    at the right place in the track.

	=== THE SCHEDULE DRIVES THE DECK, NOT `Sound.Ended` ========================

	`MusicController` advances its playlist on `Ended` and uses a watchdog only to survive a track
	that never loads. This does the opposite: every track change is a `task.delay` for exactly as
	long as `sliceAt` says is left, and `Ended` is not connected at all.

	IT HAS TO BE THAT WAY ROUND, because the clock is the shared truth and a Sound is not. Two
	listeners' `Ended` fire at whatever moment their own downloads finished, so a playlist driven by
	them would drift apart within a couple of tracks — and a listener whose track failed to load
	would never advance at all. Driven by the clock, both are self-correcting: every step recomputes
	from `GetServerTimeNow()`, so a step that ran late simply starts the next track further in.

	The cost is that `RadioConfig`'s `Seconds` have to be right, since they are what the schedule
	counts against rather than the audio itself. That is why they are measured lengths and why the
	block above `Stations` says checking a new id is worth the minute.

	=== THE ONE THING A LISTENER REFUSES =======================================

	A custom track longer than `RadioConfig.Custom.MaxSeconds`, and it is refused HERE rather than on
	the server because the server has no way to learn an audio's duration — `GetProductInfo` carries
	the asset type and whether it is public, and no length (checked). `TimeLength` is a client-side
	fact, so the cap is enforced by the ear it protects.

	THAT IS NOT THE WEAK VERSION OF A SERVER CHECK, it is the right shape for this particular rule.
	The thing the cap exists to stop is one player making everyone else sit through an hour of
	audio; every one of those "everyone else" enforces it on their own machine, so a client that
	patched the check out would only be choosing to keep listening. Compare the mute, which is the
	same bargain (`MusicConfig` note 5).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local LobbyCarConfig = require(ReplicatedStorage.shared.Configs.LobbyCarConfig)
local MusicConfig = require(ReplicatedStorage.shared.Configs.MusicConfig)
local RadioConfig = require(ReplicatedStorage.shared.Configs.RadioConfig)
local CarBody = require(ReplicatedStorage.shared.Modules.CarBody)

local RadioController = Shard.new("RadioController")

--- One car's radio: the Sound, the connections that follow the car, and the token that invalidates
--- everything scheduled against a state the car has since moved on from.
type Deck = {
	car: Model,
	sound: Sound,
	trove: any,
	generation: number,
	nowPlaying: string?,
	--- Set while a re-sync is already queued for the end of this frame. See `_invalidate`.
	dirty: boolean,
	--- The radio is switched on and playable, including the gap between two station tracks. What
	--- the soundtrack duck asks about; see `_pollNearby`.
	on: boolean,
}

RadioController:withRemoteEvents({
	{
		--[[ server -> client: the panel's status line. Republished on `Dispatcher` rather than
			handled here, because this controller has no screen and the panel may not be built yet
			— see `RadioConfig.ReplyName`, which is the only thing the server ever sends. ]]
		[RadioConfig.ReplyName] = function(ok: any, message: any)
			Dispatcher:Publish(RadioConfig.ReplyName, ok == true, tostring(message or ""))
		end,
	},
	RadioConfig.RemoteName,
})

-- === The group ==============================================================

--[[ The SoundGroup every radio plays through, and the level the mute returns to.

	SEPARATE FROM THE SOUNDTRACK'S GROUP, and muted alongside it rather than inside it. Two groups
	is what lets the radio be trimmed against the music in Studio without a build — a radio that
	fights the soundtrack is then one number rather than a re-balance — while both answering the
	same `MusicConfig.StateEvent` keeps one button in charge of all of it.

	An authored group wins and its Volume AS FOUND becomes the unmuted target, exactly as
	`MusicController._ensureGroup` does and for the same reason: fading back to a hard 1 on unmute
	would silently discard a level somebody had set, with nothing to see in the diff. ]]
function RadioController._ensureGroup(self)
	local name = RadioConfig.Sound.GroupName
	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		self._group = existing
		self._groupVolume = existing.Volume
		return
	end

	local group = Instance.new("SoundGroup")
	group.Name = name
	group.Volume = 1
	group.Parent = SoundService
	self._group = group
	self._groupVolume = 1
end

--[[ Turn every radio in earshot down, or back up. Driven by the music mute and by nothing else.

	NOTHING IS PAUSED, which is where this parts company with `MusicController._applyMute`. That one
	pauses its decks once they are inaudible, because its playlist advances on `Sound.Ended` and a
	paused Sound stops the clock it needs. This schedule is driven by `GetServerTimeNow()`, which
	does not stop for anybody — so a muted radio keeps running silently and un-muting drops the
	player back into whatever the car is playing NOW, rather than into the middle of a track that
	finished five minutes ago. ]]
function RadioController._applyMute(self, muted: boolean)
	if not self._group then
		return
	end
	if self._muteTween then
		self._muteTween:Cancel()
		self._muteTween = nil
	end

	local target = if muted then 0 else self._groupVolume
	local tween = TweenService:Create(
		self._group,
		TweenInfo.new(MusicConfig.MuteFadeSeconds, Enum.EasingStyle.Linear),
		{ Volume = target }
	)
	self._muteTween = tween
	tween:Play()
end

-- === One car's deck =========================================================

--[[ Where a radio hangs on a car: the chassis's `RedressMount`, which is the one rigid part every
	CarBones rig in this game has (`CarBody.mounts`). A Sound has to be on a BasePart to be
	positional at all, and it has to be on a part that does not move relative to the car or the
	music arrives from the general direction of a wheel.

	Falls back to the model's primary part and then to any part, so a rig that is not quite a
	CarBones one still makes a noise from roughly the right place rather than from nowhere. ]]
function RadioController._emitterFor(self, car: Model): BasePart?
	local mounts = CarBody.mounts(car)
	local mount = mounts and mounts.Body
	if mount then
		return mount
	end
	if car.PrimaryPart then
		return car.PrimaryPart
	end
	return car:FindFirstChildWhichIsA("BasePart", true)
end

--- Start following a car. Called for every tagged car that is in range, playing or not.
function RadioController._attach(self, car: Model)
	if self._decks[car] then
		return
	end

	local emitter = self:_emitterFor(car)
	if not emitter then
		--[[ A car with no parts yet — under `StreamingEnabled` a model can arrive before its
			descendants. Try again once something lands, and give up if the car goes first. ]]
		local trove = Trove.new()
		trove:Add(car.DescendantAdded:Connect(function(inst)
			if inst:IsA("BasePart") then
				trove:Destroy()
				self._pending[car] = nil
				if car:IsDescendantOf(workspace) then
					self:_attach(car)
				end
			end
		end))
		self._pending[car] = trove
		return
	end

	local trove = Trove.new()

	local sound = Instance.new("Sound")
	sound.Name = "CarRadio"
	sound.Volume = 0
	sound.Looped = false
	sound.RollOffMode = RadioConfig.Sound.RollOffMode
	sound.RollOffMinDistance = RadioConfig.Sound.MinDistance
	sound.RollOffMaxDistance = RadioConfig.Sound.MaxDistance
	sound.SoundGroup = self._group
	sound.Parent = emitter
	trove:Add(sound)

	local deck: Deck = { car = car, sound = sound, trove = trove, generation = 0, nowPlaying = nil, dirty = false, on = false }
	self._decks[car] = deck

	--[[ All three attributes, because any of them changing is a different radio. They arrive
		individually and in no guaranteed order (`RadioService._apply` explains which order it writes
		them in and why), so each one simply re-reads the whole set rather than trying to model a
		half-applied one.

		THROUGH `_invalidate` RATHER THAN STRAIGHT INTO `_sync`, and that is not tidiness. The server
		writes all three in the same frame, so they arrive in the same frame — and three direct calls
		would mean starting the track, stopping it, starting it again and stopping it again before
		anybody heard a note of it. Coalescing to one sync at the end of the frame makes a station
		change one clean start. ]]
	for _, attribute in { RadioConfig.StationAttribute, RadioConfig.TrackAttribute, RadioConfig.StartedAttribute } do
		trove:Add(car:GetAttributeChangedSignal(attribute):Connect(function()
			self:_invalidate(deck)
		end))
	end

	self:_sync(deck)
end

--- Stop following a car: the car streamed out, was put away, or lost its tag.
function RadioController._detach(self, car: Model)
	local pending = self._pending[car]
	if pending then
		pending:Destroy()
		self._pending[car] = nil
	end

	local deck = self._decks[car]
	if not deck then
		return
	end

	--[[ Asked BEFORE the deck is dropped, because `_ownCar` only looks at cars we still have a deck
		for — after the line below there is nothing left to recognise. This is the one path where
		the local player's radio state changes without any attribute changing: their car was put
		away, or it streamed out from under them. ]]
	local mine = car:GetAttribute(LobbyCarConfig.OwnerAttribute) == Players.LocalPlayer.UserId

	self._decks[car] = nil
	deck.generation += 1 -- everything scheduled against this deck is now stale
	deck.trove:Destroy()

	if mine then
		self:_publishLocal()
	end
end

--[[ Re-read this car at the end of the frame, once, however many of its attributes moved during it.
	See the block in `_attach` for why the coalescing is load-bearing rather than a nicety.

	`task.defer` and not `task.delay(0)`: defer runs after the current resumption point without
	yielding a frame, so a station change is still applied on the frame it arrived. ]]
function RadioController._invalidate(self, deck: Deck)
	if deck.dirty then
		return
	end
	deck.dirty = true
	task.defer(function()
		deck.dirty = false
		-- The car may have gone in the meantime; a deck that is no longer the live one for its car
		-- has already been torn down and must not be restarted.
		if self._decks[deck.car] ~= deck then
			return
		end
		self:_sync(deck)
	end)
end

-- === Playing ================================================================

--- Put a track on this deck at `offset` seconds in, and fade it up. The one place a SoundId is set.
function RadioController._start(self, deck: Deck, generation: number, id: number, offset: number, looped: boolean)
	local sound = deck.sound
	sound:Stop()
	sound.SoundId = `rbxassetid://{id}`
	sound.Looped = looped
	sound.Volume = 0
	sound:Play()
	sound.TimePosition = math.max(offset, 0)

	--[[ Faded up rather than dropped in at level, and only ever from silence: a radio switching
		between two tracks does so across the gap the schedule leaves, so this is always a start
		rather than a cut. ]]
	TweenService:Create(
		sound,
		TweenInfo.new(RadioConfig.Sound.FadeSeconds, Enum.EasingStyle.Linear),
		{ Volume = RadioConfig.Sound.Volume }
	):Play()

	self:_armLoad(deck, generation, id, offset)
end

--- Take whatever is on this deck off it.
function RadioController._silence(self, deck: Deck)
	deck.nowPlaying = nil
	deck.sound:Stop()
	deck.sound.SoundId = ""
	deck.sound.Volume = 0
end

--[[ Give a just-started track a bounded time to prove it is real, then correct where the needle is.

	IT DOES TWO JOBS AND THEY SHARE A LOOP BECAUSE THEY SHARE A CONDITION — `TimeLength > 0` is both
	"it loaded" and "we can now trust its length":

	  • THE SEEK. `TimePosition` set on a Sound that has not streamed in does not stick, and the
	    download took however long it took — so once the length is known, the offset is recomputed
	    FROM THE CLOCK rather than re-applied from the stale number. A listener whose car took two
	    seconds to load arrives two seconds further into the track, which is where everyone else is.
	  • THE LENGTH CAP, for a custom track only. See the header's last section for why an hour-long
	    upload is refused by the ear rather than by the server.

	AND WHAT IT DOES ON A TIMEOUT is the reason it exists at all. An id that was moderated, made
	private, or simply mistyped never loads, never errors and never fires `Ended` — so without this
	a bad number is a car silently making no noise with a paying owner sitting in it. The owner is
	told, in the panel, in words. ]]
function RadioController._armLoad(self, deck: Deck, generation: number, id: number, offset: number)
	task.spawn(function()
		local waited = 0
		while waited < RadioConfig.LoadTimeout do
			if deck.generation ~= generation then
				return -- superseded; whatever replaced us has its own watchdog
			end
			local length = deck.sound.TimeLength
			if length > 0 then
				if deck.sound.Looped and length > RadioConfig.Custom.MaxSeconds then
					self:_silence(deck)
					deck.on = false
					self:_sayIfMine(deck, false, string.format(
						RadioConfig.Copy.TooLong,
						math.floor(RadioConfig.Custom.MaxSeconds / 60)))
					return
				end
				self:_reseek(deck, generation, offset, length)
				return
			end
			task.wait(0.25)
			waited += 0.25
		end

		if deck.generation ~= generation then
			return
		end
		self:_silence(deck)
		deck.on = false
		self.log:warn(string.format("Radio track %d never loaded after %ds.", id, RadioConfig.LoadTimeout))
		self:_sayIfMine(deck, false, RadioConfig.Copy.WillNotPlay)
	end)
end

--[[ Put the needle where the clock says it should be, now that the track's length is known.

	A LOOPED (CUSTOM) TRACK WRAPS, a station track does not — the station's schedule already decided
	which track this is, so its offset is bounded by that track's own length and needs no modulo.
	Skipped entirely if the correction is under a second, because a seek is audible and a second of
	drift is not. ]]
function RadioController._reseek(self, deck: Deck, generation: number, offset: number, length: number)
	if deck.generation ~= generation then
		return
	end

	local startedAt = tonumber(deck.car:GetAttribute(RadioConfig.StartedAttribute)) or 0
	if startedAt <= 0 then
		return
	end

	local target = offset
	if deck.sound.Looped then
		local elapsed = math.max(workspace:GetServerTimeNow() - startedAt, 0)
		target = elapsed % length
	else
		--[[ How much longer the load took than the offset the track was started at accounted for.
			Recomputed against the clock rather than measured, so a client that was hitched during
			the download still lands in the right place. ]]
		local station = RadioConfig.stationByKey(deck.car:GetAttribute(RadioConfig.StationAttribute))
		if station then
			local _, current = RadioConfig.sliceAt(station, startedAt, workspace:GetServerTimeNow() - startedAt)
			target = current
		end
	end

	if math.abs(target - deck.sound.TimePosition) > 1 and target < length then
		deck.sound.TimePosition = target
	end
end

--[[ Read the car and act on it. Everything that can change a radio comes through here, and it is
	written so that being called twice in a row with the same state is harmless.

	THE GENERATION BUMP IS THE FIRST LINE, and it is what makes the schedule safe: every `task.delay`
	and every watchdog carries the generation it was armed under and does nothing if it no longer
	matches. A station change therefore cannot leave the old station's next-track timer running
	underneath the new one. ]]
function RadioController._sync(self, deck: Deck)
	deck.generation += 1
	local generation = deck.generation

	local car = deck.car
	local station = car:GetAttribute(RadioConfig.StationAttribute)
	local startedAt = tonumber(car:GetAttribute(RadioConfig.StartedAttribute)) or 0

	deck.on = false

	if type(station) ~= "string" or station == "" or startedAt <= 0 then
		self:_silence(deck)
		self:_publishIfMine(deck)
		return
	end

	if station == RadioConfig.CustomStation then
		local id = tonumber(car:GetAttribute(RadioConfig.TrackAttribute)) or 0
		if id <= 0 then
			self:_silence(deck)
			self:_publishIfMine(deck)
			return
		end
		deck.nowPlaying = nil
		deck.on = true
		--[[ Started at zero and corrected by `_reseek` once the length is known, because a custom
			track's length is not knowable until it has loaded — the one thing a station track gets
			for free from config. Looped, for the reason `RadioConfig.Custom` gives: nothing here
			knows when it would end, so it does not end. ]]
		self:_start(deck, generation, id, 0, true)
		self:_publishIfMine(deck)
		return
	end

	local found = RadioConfig.stationByKey(station)
	if not found then
		self:_silence(deck)
		self:_publishIfMine(deck)
		return
	end

	deck.on = true
	self:_step(deck, generation, found, startedAt)
	self:_publishIfMine(deck)
end

--[[ One slice of a station: play what the clock says, then come back when it runs out.

	`sliceAt` answers with a nil track during the gap between two tracks, which is a real answer and
	not a failure — the deck goes quiet and this comes back when the gap is over. ]]
function RadioController._step(self, deck: Deck, generation: number, station: RadioConfig.Station, startedAt: number)
	if deck.generation ~= generation then
		return
	end

	local elapsed = workspace:GetServerTimeNow() - startedAt
	local track, offset, remaining = RadioConfig.sliceAt(station, startedAt, elapsed)

	if track then
		deck.nowPlaying = track.Name
		self:_start(deck, generation, track.Id, offset, false)
	else
		deck.nowPlaying = nil
		self:_silence(deck)
	end

	--[[ Republished on every track change, not only when the station does, so the panel's
		now-playing line stays true while it is open. It is one `Dispatcher` publish per track per
		car in range, which is a handful a minute. ]]
	self:_publishIfMine(deck)

	if remaining == math.huge then
		return -- an empty station: silence, not a stall. Nothing to come back for.
	end

	--[[ A floor under the delay, so an arithmetic edge that produced a zero-length slice cannot spin
		this into a busy loop. It costs at most a tenth of a second of a track nobody could hear. ]]
	task.delay(math.max(remaining, 0.1), function()
		self:_step(deck, generation, station, startedAt)
	end)
end

-- === The local player's own car =============================================

--[[ The car this player has out, or nil. Found by the same owner stamp `RadioService` uses, which
	is `LobbyCarConfig`'s documented public answer to "whose car is this".

	IT IS ONLY EVER LOOKED FOR AMONG CARS WE HAVE A DECK FOR, which under `StreamingEnabled` is the
	honest set: a car the client cannot see is a car the client cannot say anything about. In
	practice the player's own car is always in it — it spawns beside them. ]]
function RadioController._ownCar(self): Model?
	local userId = Players.LocalPlayer.UserId
	for car in self._decks do
		if car:GetAttribute(LobbyCarConfig.OwnerAttribute) == userId then
			return car
		end
	end
	return nil
end

--[[ What the local player's own radio is on: a station key, `RadioConfig.CustomStation`, or nil.

	READ OFF THE CAR, never off a message. The car is the only copy of this that exists and the
	player's own car is the one they are guaranteed to have — so there is nothing for a second
	source of truth to be out of date about. `RadioService._say`'s header makes the same point from
	the other end. ]]
function RadioController.station(self): string?
	local car = self:_ownCar()
	if not car then
		return nil
	end
	local station = car:GetAttribute(RadioConfig.StationAttribute)
	if type(station) ~= "string" or station == "" then
		return nil
	end
	return station
end

--- The name of the track the local player's own car is playing, if it is on a station. nil for a
--- custom track, whose name only the server ever knew, and nil for a radio that is off.
function RadioController.nowPlaying(self): string?
	local car = self:_ownCar()
	local deck = car and self._decks[car]
	return deck and deck.nowPlaying or nil
end

--- Tell the topbar and the panel that the local player's radio moved. One publish; both draw from it.
function RadioController._publishLocal(self)
	Dispatcher:Publish(RadioConfig.StateEvent, self:station())
end

--- ...and the same, but only when the deck that changed is the local player's own.
function RadioController._publishIfMine(self, deck: Deck)
	if deck.car:GetAttribute(LobbyCarConfig.OwnerAttribute) == Players.LocalPlayer.UserId then
		self:_publishLocal()
	end
end

--- A message about the local player's OWN car, routed to the panel's status line. Nothing is said
--- about anybody else's — a track that will not load in someone else's car is not this player's news.
function RadioController._sayIfMine(self, deck: Deck, ok: boolean, message: string)
	if deck.car:GetAttribute(LobbyCarConfig.OwnerAttribute) == Players.LocalPlayer.UserId then
		Dispatcher:Publish(RadioConfig.ReplyName, ok, message)
	end
end

--[[ PUBLIC (`RadioPanelController`): ask the server to put something on. `station` is a station key,
	`RadioConfig.CustomStation`, or nil to switch the radio off.

	NOTHING IS APPLIED OPTIMISTICALLY. The car changes when the server has actually changed it and
	the attribute has come back — the same no-optimistic-repaint rule the upgrade boards, the
	teleport screen and the rename box all follow, and here it also happens to be the only thing
	that could work: the attributes are the sound, so writing one locally would be a client playing
	music it had not been given permission for. ]]
function RadioController.request(self, station: string?, trackId: number?)
	if not RadioConfig.Enabled then
		return
	end
	self:getRemoteEvent(RadioConfig.RemoteName):Fire(station, trackId)
end

-- === Making way for the soundtrack =========================================

--[[ Is the listener within earshot of a radio that is on? Re-asked every `DuckMusic.PollSeconds`
	and published on `RadioConfig.NearbyEvent` only when the answer flips. `MusicController` is the
	listener; this side only measures. See `RadioConfig.DuckMusic` for the two radii. ]]
function RadioController._pollNearby(self)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local listener = camera.CFrame.Position
	local radius = if self._nearby then RadioConfig.DuckMusic.ReleaseRadius else RadioConfig.DuckMusic.Radius

	local near = false
	for _, deck in self._decks do
		local emitter = deck.sound.Parent
		if deck.on and emitter and emitter:IsA("BasePart") and (emitter.Position - listener).Magnitude <= radius then
			near = true
			break
		end
	end

	if near ~= self._nearby then
		self._nearby = near
		Dispatcher:Publish(RadioConfig.NearbyEvent, near)
	end
end

--- Public (`MusicController`, on the way in): the last answer `_pollNearby` published.
function RadioController.isNearby(self): boolean
	return self._nearby == true
end

-- === Lifecycle ==============================================================

RadioController:withLifecycle({
	init = function(self)
		self._decks = {} :: { [Model]: Deck }
		--- Cars that arrived with no parts yet; see `_attach`.
		self._pending = {} :: { [Model]: any }
		self._group = nil :: SoundGroup?
		self._groupVolume = 1
		self._muteTween = nil :: Tween?
		self._nearby = false
	end,

	start = function(self)
		if not RadioConfig.Enabled then
			return
		end

		self:_ensureGroup()
		self._trove = Trove.new()

		--[[ THE TAG IS THE WHOLE DISCOVERY MECHANISM. Both signals fire on streaming as well as on
			parenting, which is exactly the pair a listener needs and is the reason `RadioConfig.CarTag`
			is on every lobby car rather than only on the ones playing something. ]]
		self._trove:Add(CollectionService:GetInstanceAddedSignal(RadioConfig.CarTag):Connect(function(car)
			if car:IsA("Model") then
				self:_attach(car)
			end
		end))
		self._trove:Add(CollectionService:GetInstanceRemovedSignal(RadioConfig.CarTag):Connect(function(car)
			self:_detach(car)
		end))
		for _, car in CollectionService:GetTagged(RadioConfig.CarTag) do
			if car:IsA("Model") and car:IsDescendantOf(workspace) then
				self:_attach(car)
			end
		end

		--[[ The music mute owns the radio too — see `_applyMute`. Seeded from the controller rather
			than waited for, because `MusicController` publishes its state on the way in and a radio
			that arrived after that publish would otherwise be the one thing still audible. ]]
		local MusicController = Shard.get("MusicController")
		self:_applyMute(MusicController ~= nil and MusicController:isMuted())
		Dispatcher:Subscribe(MusicConfig.StateEvent, function(muted: boolean)
			self:_applyMute(muted == true)
		end)

		if RadioConfig.DuckMusic.Enabled then
			task.spawn(function()
				while true do
					self:_pollNearby()
					task.wait(RadioConfig.DuckMusic.PollSeconds)
				end
			end)
		end
	end,
})

RadioController:withCleanup(function()
	if RadioController._trove then
		RadioController._trove:Destroy()
	end
end)

return RadioController
